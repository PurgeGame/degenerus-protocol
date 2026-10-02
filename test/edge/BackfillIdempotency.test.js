import { expect } from "chai";
import hre from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers.js";
import { deployFullProtocol, restoreAddresses } from "../helpers/deployFixture.js";
import { advanceToNextDay, eth, ZERO_BYTES32 } from "../helpers/testUtils.js";

const UINT24_MASK = (1n << 24n) - 1n;
const STAGE_RNG_REQUESTED = 1n;
const STAGE_GAP_BACKFILLED = 12n;
const REQUEST_WORD = 0xcafebaben;
const RESUME_WORD = 0xbadc0ffen;
const LATER_WORD = 0xa110cen;

// Slot 0 starts with purchaseStartDay:uint24, dailyIdx:uint24. These reads
// observe the real production state; setup never writes contract storage.
async function readClocks(game) {
  const packed = BigInt(await hre.ethers.provider.getStorage(await game.getAddress(), 0));
  return {
    purchaseStartDay: packed & UINT24_MASK,
    dailyIdx: (packed >> 24n) & UINT24_MASK,
  };
}

async function advanceStage(game, advanceModule) {
  const receipt = await (await game.advanceGame()).wait();
  const topic = advanceModule.interface.getEvent("Advance").topicHash;
  const gameAddress = (await game.getAddress()).toLowerCase();
  const events = receipt.logs
    .filter((log) => log.address.toLowerCase() === gameAddress && log.topics[0] === topic)
    .map((log) => advanceModule.interface.parseLog(log));
  expect(events.length, "at most one advance stage per transaction").to.be.at.most(1);
  if (events.length === 0) {
    // The public work router can finish unlocked read consumers before a fresh request.
    expect(await game.rngLocked(), "consumer-only work does not hold the daily lock").to.equal(false);
    return 0n;
  }
  return events[0].args.stage;
}

async function requestDay(game, advanceModule, mockVRF) {
  expect(await game.rngLocked(), "request begins unlocked").to.equal(false);
  const previousId = await mockVRF.lastRequestId();
  for (let i = 0; i < 64; ++i) {
    const stage = await advanceStage(game, advanceModule);
    if (stage === STAGE_RNG_REQUESTED) {
      expect(await game.rngLocked(), "fresh request holds the lock").to.equal(true);
      const requestId = await mockVRF.lastRequestId();
      expect(requestId, "coordinator received a new request").to.be.gt(previousId);
      return requestId;
    }
  }
  throw new Error("daily request was not reached in 64 advances");
}

async function drainDay(game, advanceModule, assertState) {
  for (let i = 0; i < 128 && await game.rngLocked(); ++i) {
    const stage = await advanceStage(game, advanceModule);
    expect(stage, "draining an applied word cannot repeat the backfill").not.to.equal(STAGE_GAP_BACKFILLED);
    await assertState();
  }
  expect(await game.rngLocked(), "the committed day finishes within the drain bound").to.equal(false);
}

describe("BackfillIdempotency", function () {
  this.timeout(600_000);

  after(function () {
    restoreAddresses();
  });

  for (const paidNudge of [false, true]) {
  it(`credits a delayed VRF gap exactly once across midnight (${paidNudge ? "paid nudge" : "no nudge"})`, async function () {
    const { game, advanceModule, mockVRF, coinflip, coin, alice } = await loadFixture(deployFullProtocol);
    // An odd initial word funds the real nudge through Alice's resolved purchase credit.
    const requestWord = paidNudge ? REQUEST_WORD | 1n : REQUEST_WORD;
    // +1 carries across several gap bits, making accidental use of the nudged root visible.
    const resumeWord = paidNudge ? 0xbadc0fffn : RESUME_WORD;
    const appliedResumeWord = resumeWord + (paidNudge ? 1n : 0n);
    const initial = await readClocks(game);
    expect(initial).to.deep.equal({ purchaseStartDay: 1n, dailyIdx: 1n });

    await game.connect(alice).purchase(
      hre.ethers.ZeroAddress, 400n, 0n, ZERO_BYTES32, 0, false, { value: eth(0.01) }
    );
    await advanceToNextDay();
    const requestDayR = await game.currentDayView();
    expect(requestDayR).to.equal(initial.dailyIdx + 1n);
    const stalledId = await requestDay(game, advanceModule, mockVRF);

    // Deliver the original request four days late. It must still seal only R;
    // the intervening days await a separately requested current-day word.
    for (let i = 0; i < 4; ++i) await advanceToNextDay();
    const resumeDayW = await game.currentDayView();
    expect(resumeDayW).to.equal(requestDayR + 4n);
    await mockVRF.fulfillRandomWords(stalledId, requestWord);
    await drainDay(game, advanceModule, async () => {
      expect((await readClocks(game)).purchaseStartDay).to.equal(initial.purchaseStartDay);
      for (let day = requestDayR + 1n; day <= resumeDayW; ++day) {
        expect(await game.rngWordForDay(day), `late request did not resolve day ${day}`).to.equal(0n);
      }
    });
    expect(await readClocks(game)).to.deep.equal({
      purchaseStartDay: initial.purchaseStartDay, dailyIdx: requestDayR,
    });
    expect(await game.rngWordForDay(requestDayR), "calendar-expired full word is hidden").to.equal(0n);
    expect((await coinflip.getCoinflipDayResult(requestDayR))[0], "sealed outcome survives expiry").to.be.gt(0n);

    if (paidNudge) {
      const [queued, cost] = await game.rngNudgeQuote();
      expect(queued).to.equal(0n);
      const available = await coin.balanceOfWithClaimable(alice.address);
      expect(available, "resolved winnings fund the nudge").to.be.gte(cost);
      await game.connect(alice).reverseFlip(cost);
      expect(await coin.balanceOfWithClaimable(alice.address), "real FLIP cost was burned").to.equal(available - cost);
      expect((await game.rngNudgeQuote())[0], "one paid nudge is queued").to.equal(1n);
      expect((resumeWord >> 1n) & 7n, "raw gap fixture wins every skipped day").to.equal(7n);
      expect((appliedResumeWord >> 1n) & 7n, "nudged gap bits would instead lose").to.equal(0n);
    }

    const resumeId = await requestDay(game, advanceModule, mockVRF);
    expect(resumeId).to.be.gt(stalledId);
    await mockVRF.fulfillRandomWords(resumeId, resumeWord);
    let reachedBackfill = false;
    for (let i = 0; i < 64; ++i) {
      if (await advanceStage(game, advanceModule) === STAGE_GAP_BACKFILLED) {
        reachedBackfill = true;
        break;
      }
      expect(await game.rngLocked(), "the gap cannot silently finish without stage 12").to.equal(true);
    }
    expect(reachedBackfill, "the real gap-backfill stage executed").to.equal(true);
    expect(await game.rngLocked(), "the wall-day draw is still owed after backfill").to.equal(true);

    const gapCount = resumeDayW - requestDayR - 1n;
    expect(gapCount).to.equal(3n);
    const creditedStart = initial.purchaseStartDay + gapCount;
    expect(await readClocks(game)).to.deep.equal({
      purchaseStartDay: creditedStart, dailyIdx: resumeDayW - 1n,
    });
    const expectedWords = new Map([[requestDayR, requestWord], [resumeDayW, appliedResumeWord]]);
    for (let day = requestDayR + 1n; day < resumeDayW; ++day) {
      const derived = BigInt(hre.ethers.solidityPackedKeccak256(["uint256", "uint24"], [resumeWord, day]));
      expectedWords.set(day, derived === 0n ? 1n : derived);
    }
    const expectedResults = new Map();
    const rewardTag = hre.ethers.keccak256(hre.ethers.toUtf8Bytes("degenerus.coinflip.reward-percent"));
    for (let day = requestDayR + 1n; day < resumeDayW; ++day) {
      // Gap wins use bits 1..31 of the RAW root; nudges affect only the real daily word.
      // The retained yesterday word still serves the other daily RNG consumers.
      const seed = BigInt(hre.ethers.solidityPackedKeccak256(["bytes32", "uint256", "uint24"], [rewardTag, resumeWord, day]));
      const win = ((resumeWord >> (day - (requestDayR + 1n) + 1n)) & 1n) !== 0n;
      const roll = seed % 20n;
      const reward = roll === 0n ? 50n : roll === 1n ? 150n : seed % 38n + 78n;
      expectedResults.set(day, [win ? reward : 1n, win]);
    }
    async function assertRetainedWordsAndGapResults() {
      const today = await game.currentDayView();
      for (const [day, word] of expectedWords) {
        const retained = day <= today && today - day <= 1n;
        expect(await game.rngWordForDay(day), `retained word for day ${day}`).to.equal(retained ? word : 0n);
      }
      for (const [day, result] of expectedResults) {
        expect(Array.from(await coinflip.getCoinflipDayResult(day)), `immutable outcome ${day}`).to.deep.equal(result);
      }
    }
    async function assertFrozenGap() {
      expect((await readClocks(game)).purchaseStartDay, "exactly one gap credit").to.equal(creditedStart);
      await assertRetainedWordsAndGapResults();
      expect(await game.rngWordForDay(resumeDayW + 1n), "next day has no borrowed word").to.equal(0n);
      expect(await mockVRF.lastRequestId(), "drain keeps the same request").to.equal(resumeId);
    }
    await assertFrozenGap();

    // Stage 12 deliberately leaves the lock held. Cross midnight at that exact
    // boundary, then require every remaining advance to preserve the credit and
    // packed gap outcomes while finishing W rather than the new wall day W+1.
    await advanceToNextDay();
    expect(await game.currentDayView()).to.equal(resumeDayW + 1n);
    await drainDay(game, advanceModule, assertFrozenGap);
    expect((await readClocks(game)).dailyIdx).to.equal(resumeDayW);
    expect((await coinflip.getCoinflipDayResult(resumeDayW))[1], "real daily flip uses the final nudged bit 0")
      .to.equal((appliedResumeWord & 1n) !== 0n);
    expect(await game.gameOver()).to.equal(false);

    const laterId = await requestDay(game, advanceModule, mockVRF);
    expect(laterId).to.be.gt(resumeId);
    expect(await game.rngWordForDay(resumeDayW + 1n)).to.equal(0n);
    await mockVRF.fulfillRandomWords(laterId, LATER_WORD);
    await drainDay(game, advanceModule, async () => {
      expect((await readClocks(game)).purchaseStartDay).to.equal(creditedStart);
      await assertRetainedWordsAndGapResults();
    });
    expect(await readClocks(game)).to.deep.equal({
      purchaseStartDay: creditedStart, dailyIdx: resumeDayW + 1n,
    });
    expect(await game.rngWordForDay(resumeDayW + 1n)).to.equal(LATER_WORD);
    expect(LATER_WORD).not.to.equal(appliedResumeWord);
    expect(await game.gameOver()).to.equal(false);
  });
  }
});
