import { expect } from "chai";
import hre from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers.js";
import {
  deployFullProtocol,
  restoreAddresses,
} from "../helpers/deployFixture.js";
import {
  eth,
  advanceTime,
  advanceToNextDay,
  getLastVRFRequestId,
  ZERO_BYTES32,
} from "../helpers/testUtils.js";

const ZERO_ADDRESS = hre.ethers.ZeroAddress;
const MintPaymentKind = { DirectEth: 0 };

/**
 * LivenessMidJackpot — integration tests that drive the game into a real
 * jackpot phase, then exercise the two clocks that govern liveness there.
 *
 * While jackpotPhaseFlag is set, _livenessTriggered (DegenerusGameStorage.sol)
 * does NOT consult the in-phase day clock — that clock would false-fire in the
 * productive window between target-met and phase-transition close, deadlocking
 * the multi-call jackpot dance. Instead it returns _vrfDeadmanFired(), the
 * phase-independent VRF-death deadman: simulatedDayIndex - dailyIdx > 120.
 *
 *   - Inside the deadman window (no day sealed for <= 120 days) the pause holds
 *     and liveness stays false: the jackpot phase completes normally.
 *   - Once the stall exceeds 120 days the deadman fires, overriding the pause.
 *     advanceGame then consults it separately (AdvanceModule:216,
 *     `(!inJackpot && !lastPurchase) || _vrfDeadmanFired()`) to reach
 *     _handleGameOverPath and drain to terminal fund release even mid-jackpot,
 *     rather than bricking.
 *
 * dailyIdx (slot 0, byte offset 3, uint24) is read straight from storage to
 * land the warp exactly on the 120-day deadman threshold.
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
    const dailyIdx = readUint24(await readSlot0(await game.getAddress()), OFF_DAILY_IDX);
    const currentDay = Number(await game.currentDayView());
    return currentDay - dailyIdx;
  }

  async function buyFullTickets(game, buyer, n, totalEth) {
    return game.connect(buyer).purchase(
      ZERO_ADDRESS,
      BigInt(n) * 400n,
      0n,
      ZERO_BYTES32,
      MintPaymentKind.DirectEth,false,
      { value: eth(totalEth) }
    );
  }

  async function driveOneCycleSameDay(game, deployer, mockVRF, word) {
    await game.connect(deployer).advanceGame();
    const reqId = await getLastVRFRequestId(mockVRF);
    try {
      await mockVRF.fulfillRandomWords(reqId, word);
    } catch {
      /* may already be fulfilled */
    }
    for (let i = 0; i < 200; i++) {
      try {
        await game.connect(deployer).advanceGame();
      } catch {
        break;
      }
      if (!(await game.rngLocked())) break;
    }
  }

  async function driveOneCycle(game, deployer, mockVRF, word) {
    await advanceToNextDay();
    return driveOneCycleSameDay(game, deployer, mockVRF, word);
  }

  /**
   * Repeatedly call advanceGame until gameOver latches. Once the deadman has
   * fired mid-jackpot, advanceGame enters _handleGameOverPath every call: it
   * commits the historical-fallback word, drains queued tickets one batch per
   * tx, then handleGameOverDrain sets gameOver. VRF is fulfilled defensively in
   * case any path issues a fresh request.
   */
  async function driveToGameOver(game, deployer, mockVRF) {
    for (let i = 0; i < 600; i++) {
      try {
        await game.connect(deployer).advanceGame();
      } catch {
        await advanceToNextDay();
      }
      try {
        const reqId = await getLastVRFRequestId(mockVRF);
        await mockVRF.fulfillRandomWords(reqId, BigInt(i) * 1009n + 7n);
      } catch {
        /* no fresh request / already fulfilled */
      }
      if (await game.gameOver()) return true;
    }
    return false;
  }

  /** 2.4 ETH whale + 500 tickets × 5 ETH = 7.4 ETH per buyer. */
  async function heavyPurchases(game, buyers) {
    for (const buyer of buyers) {
      try {
        await game
          .connect(buyer)
          .purchaseWhalePass(buyer.address, 1, { value: eth(2.4) });
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
    const { game, deployer, mockVRF, alice, bob, carol, dan, eve, others } =
      fixture;

    // Day 2 warmup: small purchase + cycle so purchaseDays >= 2 on next cycle
    // (prevents turbo, which would compress jackpot into a single physical day).
    await buyFullTickets(game, alice, 10, 0.1);
    await advanceToNextDay();
    await driveOneCycleSameDay(game, deployer, mockVRF, 7n);

    // Heavy purchases (19 buyers × 7.4 ETH = 140 ETH > 50 ETH bootstrap).
    const buyers = [bob, carol, dan, eve, ...others.slice(0, 15)];
    await heavyPurchases(game, buyers);

    // Drive cycles until jackpot phase is reached.
    for (let cycle = 0; cycle < 8; cycle++) {
      await driveOneCycle(game, deployer, mockVRF, BigInt(cycle * 1000 + 42));
      if (await game.jackpotPhase()) return;
    }
    throw new Error("Failed to enter jackpot phase");
  }

  // ---------------------------------------------------------------------
  // Tests
  // ---------------------------------------------------------------------

  it("liveness is paused on entry to a real jackpot phase (deadman not fired)", async function () {
    const fixture = await loadFixture(deployFullProtocol);
    const { game } = fixture;

    await driveIntoJackpotPhase(fixture);
    expect(await game.jackpotPhase()).to.equal(true);

    // Just entered: dailyIdx tracks currentDay, so the deadman has not fired
    // and the jackpot flag suppresses the in-phase clock.
    expect(await stallDays(game)).to.be.lessThanOrEqual(120);
    expect(await game.livenessTriggered()).to.equal(
      false,
      "fresh jackpot phase: in-phase clock suppressed, deadman not fired"
    );
  });

  it("productive pause holds at exactly the 120-day stall (deadman not yet fired)", async function () {
    const fixture = await loadFixture(deployFullProtocol);
    const { game } = fixture;

    await driveIntoJackpotPhase(fixture);
    expect(await game.jackpotPhase()).to.equal(true);

    // Warp the stall (currentDay - dailyIdx) to exactly 120: the deadman is a
    // strict `> 120`, so it stays unfired and the jackpot pause holds.
    const warpDays = 120 - (await stallDays(game));
    expect(warpDays).to.be.greaterThan(0);
    await advanceTime(warpDays * 86400);

    expect(await stallDays(game)).to.equal(120);
    expect(await game.jackpotPhase()).to.equal(true);
    expect(await game.livenessTriggered()).to.equal(
      false,
      "120-day stall: deadman not yet fired, in-phase clock still suppressed"
    );
  });

  it("VRF-death deadman overrides the jackpot pause once the stall exceeds 120 days", async function () {
    const fixture = await loadFixture(deployFullProtocol);
    const { game } = fixture;

    await driveIntoJackpotPhase(fixture);
    expect(await game.jackpotPhase()).to.equal(true);

    // Warp the stall to 121 days: deadman fires. jackpotPhaseFlag is still set,
    // yet liveness flips true because _livenessTriggered returns the deadman.
    const warpDays = 121 - (await stallDays(game));
    expect(warpDays).to.be.greaterThan(0);
    await advanceTime(warpDays * 86400);

    expect(await stallDays(game)).to.equal(121);
    expect(await game.jackpotPhase()).to.equal(true);
    expect(await game.livenessTriggered()).to.equal(
      true,
      "121-day stall: deadman overrides the in-phase jackpot pause"
    );
  });

  it("advanceGame does not revert mid-jackpot when the deadman has fired", async function () {
    const fixture = await loadFixture(deployFullProtocol);
    const { game, deployer, mockVRF } = fixture;

    await driveIntoJackpotPhase(fixture);
    expect(await game.jackpotPhase()).to.equal(true);

    // Warp well past the deadman while still in jackpot phase.
    await advanceTime(125 * 86400);
    expect(await game.livenessTriggered()).to.equal(true);

    // advanceGame now takes the deadman game-over path instead of the jackpot
    // ticket-queue path; it must not revert, and the RNG lock must not stick.
    await driveOneCycle(game, deployer, mockVRF, 0xdeadbeefn);

    expect(await game.rngLocked()).to.equal(false);
  });

  it("deadman drives the stalled jackpot to terminal game-over fund release", async function () {
    const fixture = await loadFixture(deployFullProtocol);
    const { game, deployer, mockVRF } = fixture;

    await driveIntoJackpotPhase(fixture);
    expect(await game.jackpotPhase()).to.equal(true);
    expect(await game.gameOver()).to.equal(false);

    // Warp past the deadman, then drive advanceGame to the terminal drain.
    await advanceTime(125 * 86400);
    expect(await game.livenessTriggered()).to.equal(true);

    const reached = await driveToGameOver(game, deployer, mockVRF);

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
