import { expect } from "chai";
import hre from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers.js";
import { deployFullProtocol, restoreAddresses } from "../helpers/deployFixture.js";
import { seedLogicalDay, setPackedField } from "../helpers/logicalDayFixture.js";
import { advanceTime } from "../helpers/testUtils.js";

describe("LivenessProductivePause", function () {
  after(restoreAddresses);

  async function agedPurchase() {
    const f = await deployFullProtocol();
    await seedLogicalDay(f.game, 39n, f.coinflip);
    await setPackedField(f.game, "purchaseStartDay", 9n);
    await advanceTime(86400);
    return f;
  }

  it("thirty completed logical rounds require the following wall reset", async function () {
    const { game, coinflip } = await loadFixture(deployFullProtocol);
    await seedLogicalDay(game, 39n, coinflip);
    expect(await game.livenessTriggered()).to.equal(false);
    await advanceTime(86400);
    expect(await game.livenessTriggered()).to.equal(true);
  });

  for (const flag of ["lastPurchaseDay", "jackpotPhaseFlag"]) {
    it(`${flag} suppresses the normal purchase timeout`, async function () {
      const { game } = await loadFixture(agedPurchase);
      expect(await game.livenessTriggered()).to.equal(true);
      await setPackedField(game, flag, 1);
      expect(await game.livenessTriggered()).to.equal(false);
      await setPackedField(game, flag, 0);
      expect(await game.livenessTriggered()).to.equal(true);
    });

    it(`${flag} cannot suppress the exact fourteen-day completion deadline`, async function () {
      const { game } = await loadFixture(deployFullProtocol);
      await setPackedField(game, flag, 1);
      const now = (await hre.ethers.provider.getBlock("latest")).timestamp;
      await setPackedField(game, "lastDailyCompletedAt", now - 14 * 86400 + 1);
      expect(await game.livenessTriggered()).to.equal(false);
      await advanceTime(1);
      expect(await game.livenessTriggered()).to.equal(true);
    });
  }

  it("an unfinished daily session pauses normal expiry but cannot reset the hard deadline", async function () {
    const { game } = await loadFixture(agedPurchase);
    await setPackedField(game, "dailyComplete", 0);
    expect(await game.livenessTriggered()).to.equal(false);
    await advanceTime(13 * 86400);
    expect(await game.livenessTriggered()).to.equal(true);
  });

  it("elapsed calendar days alone never create thirty purchase rounds", async function () {
    const { game } = await loadFixture(deployFullProtocol);
    const day = await game.currentDayView();
    await advanceTime(13 * 86400);
    expect(await game.currentDayView()).to.equal(day);
    expect(await game.livenessTriggered()).to.equal(false);
    await advanceTime(86400);
    expect(await game.livenessTriggered()).to.equal(true);
  });
});
