import { expect } from "chai";
import hre from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers.js";
import { deployFullProtocol, restoreAddresses } from "../helpers/deployFixture.js";
import { advanceToNextDay, eth, ZERO_BYTES32 } from "../helpers/testUtils.js";

const ONE_UNIT = 0xffffffff;
async function clocks(game) {
  const packed = BigInt(await hre.ethers.provider.getStorage(await game.getAddress(), 0));
  return [packed & 0xffffffn, (packed >> 24n) & 0xffffffn];
}
async function request(game, vrf) {
  for (let i = 0; i < 200 && !(await game.rngLocked()); ++i) {
    const id = await vrf.lastRequestId();
    if (id && !(await vrf.pendingRequests(id))[2]) await vrf.fulfillRandomWords(id, 777n);
    await game.mineFlip(ONE_UNIT, { gasLimit: 16_777_216 });
  }
  expect(await game.rngLocked()).to.equal(true);
  return vrf.lastRequestId();
}
async function finish(game) {
  for (let i = 0; i < 200 && !(await game.dailySessionState())[0]; ++i) await game.mineFlip(ONE_UNIT, { gasLimit: 16_777_216 });
  expect((await game.dailySessionState())[0]).to.equal(true);
}

describe("Delayed logical rounds never backfill calendar gaps", function () {
  this.timeout(600_000);
  after(() => restoreAddresses());
  for (const paidNudge of [false, true]) {
    it(`settles each committed cohort once across resets (${paidNudge ? "paid nudge" : "no nudge"})`, async function () {
      const { game, mockVRF, coinflip, coin, alice } = await loadFixture(deployFullProtocol);
      const [start, initial] = await clocks(game);
      await game.connect(alice).purchase(0, 400n, 0n, ZERO_BYTES32, 0, false, { value: eth(0.01) });
      await advanceToNextDay();
      expect(await game.currentDayView_g542950()).to.equal(initial);
      const id = await request(game, mockVRF);
      const day = initial + 1n;
      expect(await game.currentDayView_g542950()).to.equal(day);
      expect(await coinflip.requestedDailyIdx()).to.equal(day);
      for (let i = 0; i < 8; ++i) await advanceToNextDay();
      expect(await game.currentDayView_g542950()).to.equal(day);
      const pool = await coinflip.recordPool();
      await mockVRF.fulfillRandomWords(id, 0xcafebabfn);
      await finish(game);
      expect(await clocks(game)).to.deep.equal([start, day]);
      expect(await game.rngWordForDay(day)).to.equal(0xcafebabfn);
      expect(await coinflip.recordPool()).to.be.gte(pool);
      for (let d = day + 1n; d < day + 9n; ++d) {
        expect((await coinflip.getCoinflipDayResult(d))[0]).to.equal(0n);
        expect(await game.rngWordForDay(d)).to.equal(0n);
      }
      const settled = Array.from(await coinflip.getCoinflipDayResult(day));
      if (paidNudge) {
        const [, cost] = await game.rngNudgeQuote();
        const available = await coin.balanceOfWithClaimable(alice.address);
        expect(available).to.be.gte(cost);
        await game.connect(alice).reverseFlip(cost);
        expect(await coin.balanceOfWithClaimable(alice.address)).to.equal(available - cost);
      }
      const next = await request(game, mockVRF);
      expect(next).to.be.gt(id);
      expect(await game.currentDayView_g542950()).to.equal(day + 1n);
      await mockVRF.fulfillRandomWords(next, 0xbadc0fffn);
      await finish(game);
      expect(await game.rngWordForDay(day + 1n)).to.equal(0xbadc0fffn + (paidNudge ? 1n : 0n));
      expect(Array.from(await coinflip.getCoinflipDayResult(day))).to.deep.equal(settled);
      expect(await clocks(game)).to.deep.equal([start, day + 1n]);
      // The actual send window permits only one fresh daily request.
      for (let i = 0; i < 20 && (await game.nextMinerAction()) !== 0n; ++i) {
        const pending = await mockVRF.lastRequestId();
        if (pending && !(await mockVRF.pendingRequests(pending))[2]) await mockVRF.fulfillRandomWords(pending, 999n);
        await game.mineFlip(ONE_UNIT, { gasLimit: 16_777_216 });
      }
      expect(await game.currentDayView_g542950()).to.equal(day + 1n);
      expect(await game.gameOver()).to.equal(false);
    });
  }
});
