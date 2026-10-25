import { expect } from "chai";
import hre from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers.js";
import {
  deployFullProtocol,
  restoreAddresses,
} from "../helpers/deployFixture.js";
import { driveDailyCycle } from "../helpers/dailyCycle.js";
import {
  eth,
  advanceTime,
  advanceToNextDay,
  ZERO_BYTES32,
} from "../helpers/testUtils.js";

const ZERO_ADDRESS = hre.ethers.ZeroAddress;
const MintPaymentKind = { DirectEth: 0 };

/**
 * LivenessMidJackpot — integration tests that drive the game into a real
 * jackpot phase, then exercise the two clocks that govern liveness there.
 *
 * A jackpot phase in progress is never ended by the purchase deadline (the only VRF-alive
 * ending). The one thing that overrides it is the hard stall: fourteen days without a completed
 * day always takes the dead-VRF deterministic ending, even if the VRF would still answer.
 *
 *   - Inside the stall window (no day completed for < 14 days) the jackpot phase continues
 *     and liveness stays false.
 *   - Once the stall reaches fourteen days the hard stall fires, overriding the phase.
 *     mineFlip then reaches the terminal path and drains to terminal fund release even
 *     mid-jackpot, rather than bricking.
 *
 * The stall is measured from the last completed day (dailySessionState), which the warps below
 * move to exactly the 13- and 14-day thresholds.
 */
describe("LivenessMidJackpot", function () {
  this.timeout(600_000);

  after(function () {
    restoreAddresses();
  });

  // ---------------------------------------------------------------------
  // Helpers (mirrors CompressedJackpot.test.js)
  // ---------------------------------------------------------------------

  // Slot 0 byte offset of dailyIdx (uint24), authoritative from
  // `forge inspect DegenerusGameStorage storage-layout`.
  const OFF_DAILY_IDX = 3;

  async function readSlot0(addr) {
    return hre.network.provider.send("eth_getStorageAt", [
      addr,
      "0x0",
      "latest",
    ]);
  }

  /** Read a little-endian-positioned uint24 at byteIdx (3 bytes) from slot 0. */
  function readUint24(slotHex, byteIdx) {
    const byteAt = (i) => {
      const charPos = (31 - i) * 2 + 2;
      return parseInt(slotHex.slice(charPos, charPos + 2), 16);
    };
    return byteAt(byteIdx) + (byteAt(byteIdx + 1) << 8) + (byteAt(byteIdx + 2) << 16);
  }

  /** Days since the last sealed day: the live argument of _vrfDeadmanFired(). */
  async function stallDays(game) {
    const { timestamp } = await hre.ethers.provider.getBlock("latest");
    const [, , completedAt] = await game.dailySessionState();
    return Math.floor((timestamp - Number(completedAt)) / 86400);
  }

  async function buyFullTickets(game, buyer, n, totalEth) {
    return game.connect(buyer).purchaseOrderFor(
      0,
      BigInt(n) * 400n,
      0n,
      ZERO_BYTES32,
      MintPaymentKind.DirectEth,false,
      { value: eth(totalEth) }
    );
  }

  async function driveOneCycleSameDay(game, deployer, mockVRF, advanceModule, word) {
    return driveDailyCycle(game, deployer, mockVRF, advanceModule, word);
  }

  async function driveOneCycle(game, deployer, mockVRF, advanceModule, word) {
    await advanceToNextDay();
    return driveOneCycleSameDay(game, deployer, mockVRF, advanceModule, word);
  }

  /**
   * Repeatedly call mineFlip until gameOver latches. A 14-day stall always takes the dead-VRF
   * deterministic ending (no VRF request, no wait for a word): the terminal drain walks its
   * cohorts one checkpoint per call and then latches gameOver.
   */
  async function driveToGameOver(game, deployer) {
    for (let i = 0; i < 600; i++) {
      if (await game.gameOver()) return true;
      await game.connect(deployer).mineRun(0, { gasLimit: 16_777_216 });
    }
    return await game.gameOver();
  }

  /** 2.4 ETH whale + 500 tickets × 5 ETH = 7.4 ETH per buyer. */
  async function heavyPurchases(game, buyers) {
    for (const buyer of buyers) {
      try {
        await game
          .connect(buyer)
          .purchaseWhalePass(0, 1, hre.ethers.ZeroHash, { value: eth(2.4) });
      } catch {
        /* may not be available for some buyers */
      }
      await buyFullTickets(game, buyer, 500, 5);
    }
  }

  /**
   * Drive the game into L1 jackpot phase via the compressed-tier path.
   * Returns once jackpotPhase() == true.
   */
  async function driveIntoJackpotPhase(fixture) {
    const { game, deployer, mockVRF, advanceModule, alice, bob, carol, dan, eve, others } =
      fixture;

    // Day 2 warmup: small purchase + cycle so purchaseDays >= 2 on next cycle
    // (prevents turbo, which would compress jackpot into a single physical day).
    await buyFullTickets(game, alice, 10, 0.1);
    await advanceToNextDay();
    await driveOneCycleSameDay(game, deployer, mockVRF, advanceModule, 7n);

    // Heavy purchases (19 buyers × 7.4 ETH = 140 ETH > 50 ETH bootstrap).
    const buyers = [bob, carol, dan, eve, ...others.slice(0, 15)];
    await heavyPurchases(game, buyers);

    // Drive cycles until jackpot phase is reached.
    for (let cycle = 0; cycle < 8; cycle++) {
      await driveOneCycle(game, deployer, mockVRF, advanceModule, BigInt(cycle * 1000 + 42));
      if (await game.jackpotPhase()) return;
    }
    throw new Error("Failed to enter jackpot phase");
  }

  // Reuse the expensive public lifecycle prefix. Replaying thousands of ticket
  // writes from the deployment snapshot in each case retains excessive EDR state.
  // Each test still starts at the same real, freshly entered jackpot phase.
  async function deployAtJackpot() {
    const fixture = await deployFullProtocol();
    await driveIntoJackpotPhase(fixture);
    return fixture;
  }

  // ---------------------------------------------------------------------
  // Tests
  // ---------------------------------------------------------------------

  it("liveness is paused on entry to a real jackpot phase (deadman not fired)", async function () {
    const fixture = await loadFixture(deployAtJackpot);
    const { game } = fixture;

    expect(await game.jackpotPhase()).to.equal(true);

    // Just entered: dailyIdx tracks currentDay, so the deadman has not fired
    // and the jackpot flag suppresses the in-phase clock.
    expect(await stallDays(game)).to.be.lessThanOrEqual(30);
    expect(await game.livenessTriggered()).to.equal(
      false,
      "fresh jackpot phase: in-phase clock suppressed, deadman not fired"
    );
  });

  it("productive pause holds at exactly the 13-day stall (deadman not yet fired)", async function () {
    const fixture = await loadFixture(deployAtJackpot);
    const { game } = fixture;

    expect(await game.jackpotPhase()).to.equal(true);

    // Warp the stall to 13 days: the hard stall fires at 14, so
    // it stays unfired and the jackpot phase continues.
    const warpDays = 13 - (await stallDays(game));
    expect(warpDays).to.be.greaterThan(0);
    await advanceTime(warpDays * 86400);

    expect(await stallDays(game)).to.equal(13);
    expect(await game.jackpotPhase()).to.equal(true);
    expect(await game.livenessTriggered()).to.equal(
      false,
      "13-day stall: deadman not yet fired, in-phase clock still suppressed"
    );
  });

  it("VRF-death deadman overrides the jackpot pause once the stall reaches fourteen days", async function () {
    const fixture = await loadFixture(deployAtJackpot);
    const { game } = fixture;

    expect(await game.jackpotPhase()).to.equal(true);

    // Warp the stall to 14 days: the hard stall fires. jackpotPhaseFlag is still set,
    // yet liveness flips true because the hard stall takes the dead-VRF ending.
    const warpDays = 14 - (await stallDays(game));
    expect(warpDays).to.be.greaterThan(0);
    await advanceTime(warpDays * 86400);

    expect(await stallDays(game)).to.equal(14);
    expect(await game.jackpotPhase()).to.equal(true);
    expect(await game.livenessTriggered()).to.equal(
      true,
      "14-day stall: deadman overrides the in-phase jackpot pause"
    );
  });

  it("mineFlip does not revert mid-jackpot when the deadman has fired", async function () {
    const fixture = await loadFixture(deployAtJackpot);
    const { game, deployer } = fixture;

    expect(await game.jackpotPhase()).to.equal(true);

    // Warp well past the deadman while still in jackpot phase.
    await advanceTime(14 * 86400);
    expect(await game.livenessTriggered()).to.equal(true);

    // mineFlip now takes the dead-VRF terminal path instead of the jackpot
    // ticket-queue path; it must not revert, and the RNG lock must not stick.
    await game.connect(deployer).mineRun(0, { gasLimit: 16_777_216 });

    expect(await game.rngLocked()).to.equal(false);
  });

  it("deadman drives the stalled jackpot to terminal game-over fund release", async function () {
    const fixture = await loadFixture(deployAtJackpot);
    const { game, deployer } = fixture;

    expect(await game.jackpotPhase()).to.equal(true);
    expect(await game.gameOver()).to.equal(false);

    // Warp past the deadman, then drive mineFlip to the terminal drain.
    await advanceTime(14 * 86400);
    expect(await game.livenessTriggered()).to.equal(true);

    const reached = await driveToGameOver(game, deployer);

    expect(reached).to.equal(
      true,
      "deadman game-over path must reach terminal fund release"
    );
    expect(await game.gameOver()).to.equal(true);
    expect(await game.rngLocked()).to.equal(
      false,
      "rngLocked must clear at terminal _unlockRng"
    );
  });
});
