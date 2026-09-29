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
  expect(events, "each successful advance reports its completed stage").to.have.length(1);
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

  it("credits a delayed VRF gap exactly once and preserves its words across midnight", async function () {
    const { game, advanceModule, mockVRF, alice } = await loadFixture(deployFullProtocol);
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
    await mockVRF.fulfillRandomWords(stalledId, REQUEST_WORD);
    await drainDay(game, advanceModule, async () => {
      expect((await readClocks(game)).purchaseStartDay).to.equal(initial.purchaseStartDay);
      for (let day = requestDayR + 1n; day <= resumeDayW; ++day) {
        expect(await game.rngWordForDay(day), `late request did not resolve day ${day}`).to.equal(0n);
      }
    });
    expect(await readClocks(game)).to.deep.equal({
      purchaseStartDay: initial.purchaseStartDay, dailyIdx: requestDayR,
    });
    expect(await game.rngWordForDay(requestDayR)).to.equal(REQUEST_WORD);

    const resumeId = await requestDay(game, advanceModule, mockVRF);
    expect(resumeId).to.be.gt(stalledId);
    await mockVRF.fulfillRandomWords(resumeId, RESUME_WORD);
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
    const expectedWords = new Map([[requestDayR, REQUEST_WORD], [resumeDayW, RESUME_WORD]]);
    for (let day = requestDayR + 1n; day < resumeDayW; ++day) {
      const derived = BigInt(hre.ethers.solidityPackedKeccak256(["uint256", "uint24"], [RESUME_WORD, day]));
      expectedWords.set(day, derived === 0n ? 1n : derived);
    }
    async function assertFrozenGap() {
      expect((await readClocks(game)).purchaseStartDay, "exactly one gap credit").to.equal(creditedStart);
      for (const [day, word] of expectedWords) {
        expect(await game.rngWordForDay(day), `committed word for day ${day}`).to.equal(word);
      }
      expect(await game.rngWordForDay(resumeDayW + 1n), "next day has no borrowed word").to.equal(0n);
      expect(await mockVRF.lastRequestId(), "drain keeps the same request").to.equal(resumeId);
    }
    await assertFrozenGap();

    // Stage 12 deliberately leaves the lock held. Cross midnight at that exact
    // boundary, then require every remaining advance to preserve the credit and
    // all stored words while finishing W rather than the new wall day W+1.
    await advanceToNextDay();
    expect(await game.currentDayView()).to.equal(resumeDayW + 1n);
    await drainDay(game, advanceModule, assertFrozenGap);
    expect((await readClocks(game)).dailyIdx).to.equal(resumeDayW);
    expect(await game.gameOver()).to.equal(false);

    const laterId = await requestDay(game, advanceModule, mockVRF);
    expect(laterId).to.be.gt(resumeId);
    expect(await game.rngWordForDay(resumeDayW + 1n)).to.equal(0n);
    await mockVRF.fulfillRandomWords(laterId, LATER_WORD);
    await drainDay(game, advanceModule, async () => {
      expect((await readClocks(game)).purchaseStartDay).to.equal(creditedStart);
      for (const [day, word] of expectedWords) {
        expect(await game.rngWordForDay(day)).to.equal(word);
      }
    });
    expect(await readClocks(game)).to.deep.equal({
      purchaseStartDay: creditedStart, dailyIdx: resumeDayW + 1n,
    });
    expect(await game.rngWordForDay(resumeDayW + 1n)).to.equal(LATER_WORD);
    expect(LATER_WORD).not.to.equal(RESUME_WORD);
    expect(await game.gameOver()).to.equal(false);
  });
});
