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
 * jackpot phase, then warp past the 120-day death clock to verify the
 * productive-phase pause in _livenessTriggered (storage:1247) actually
 * lets the contract complete the multi-call dance instead of deadlocking.
 *
 * The deadlock chain pre-fix: advanceGame line 182 gates _handleGameOverPath
 * on !inJackpot && !lastPurchase. Once jackpotPhaseFlag flips true and the
 * day clock passes purchaseStartDay+120, _handleGameOverPath is unreachable.
 * Execution falls into the do-while jackpot-phase block, which calls
 * payDailyJackpotCoinAndTickets → _distributeTicketJackpot → _queueTickets,
 * and the unconditional liveness guard inside _queueTickets reverts E()
 * with no path to clear rngLockedFlag.
 *
 * These tests exercise that exact code path with real contract state,
 * mirroring the helpers from test/edge/CompressedJackpot.test.js.
 */
describe("LivenessMidJackpot", function () {
  this.timeout(600_000);

  after(function () {
    restoreAddresses();
  });

  // ---------------------------------------------------------------------
  // Helpers (mirrors CompressedJackpot.test.js)
  // ---------------------------------------------------------------------

  async function buyFullTickets(game, buyer, n, totalEth) {
    return game.connect(buyer).purchase(
      ZERO_ADDRESS,
      BigInt(n) * 400n,
      0n,
      ZERO_BYTES32,
      MintPaymentKind.DirectEth,
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

  /** 2.4 ETH whale + 500 tickets × 5 ETH = 7.4 ETH per buyer. */
  async function heavyPurchases(game, buyers) {
    for (const buyer of buyers) {
      try {
        await game
          .connect(buyer)
          .purchaseWhaleBundle(buyer.address, 1, { value: eth(2.4) });
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

  it("livenessTriggered() returns false in real jackpot phase past 120-day mark", async function () {
    const fixture = await loadFixture(deployFullProtocol);
    const { game } = fixture;

    await driveIntoJackpotPhase(fixture);
    expect(await game.jackpotPhase()).to.equal(true);
    expect(await game.livenessTriggered()).to.equal(false);

    // Warp past the death clock while still in jackpot phase.
    await advanceTime(125 * 86400);

    expect(await game.jackpotPhase()).to.equal(true);
    expect(await game.livenessTriggered()).to.equal(
      false,
      "fix: liveness paused by jackpotPhaseFlag despite day clock expired"
    );
  });

  it("advanceGame does not revert mid-jackpot when 120-day deadline elapsed", async function () {
    const fixture = await loadFixture(deployFullProtocol);
    const { game, deployer, mockVRF } = fixture;

    await driveIntoJackpotPhase(fixture);
    expect(await game.jackpotPhase()).to.equal(true);

    // Warp past the death clock while still in jackpot phase.
    await advanceTime(125 * 86400);

    // Pre-fix: payDailyJackpotCoinAndTickets reverts in _queueTickets.
    // Post-fix: liveness paused → tickets queue normally → cycle completes.
    await driveOneCycle(game, deployer, mockVRF, 0xdeadbeefn);

    expect(await game.rngLocked()).to.equal(false);
  });

  it("game completes jackpot phase + transition past 120-day liveness", async function () {
    const fixture = await loadFixture(deployFullProtocol);
    const { game, deployer, mockVRF } = fixture;

    await driveIntoJackpotPhase(fixture);
    expect(await game.jackpotPhase()).to.equal(true);

    await advanceTime(125 * 86400);

    // Drive cycles until jackpot phase + transition close. Each cycle =
    // 1 jackpot day. Compressed tier wraps in ~3 days; allow extra slack.
    let exitedJackpot = false;
    for (let cycle = 0; cycle < 12; cycle++) {
      await driveOneCycle(game, deployer, mockVRF, BigInt(cycle * 7919 + 13));
      if (!(await game.jackpotPhase())) {
        exitedJackpot = true;
        break;
      }
    }

    expect(exitedJackpot).to.equal(
      true,
      "jackpotPhase must flip false (transition closed) past death clock"
    );
    expect(await game.gameOver()).to.equal(
      false,
      "natural transition completed; gameOver must remain false"
    );
    expect(await game.rngLocked()).to.equal(
      false,
      "rngLocked must clear at transition close (proves _unlockRng fired)"
    );
  });

  it("liveness re-arms with fresh purchaseStartDay after jackpot phase closes", async function () {
    const fixture = await loadFixture(deployFullProtocol);
    const { game, deployer, mockVRF } = fixture;

    await driveIntoJackpotPhase(fixture);
    await advanceTime(125 * 86400);

    // Complete jackpot phase + transition through liveness.
    for (let cycle = 0; cycle < 12; cycle++) {
      await driveOneCycle(game, deployer, mockVRF, BigInt(cycle * 31 + 7));
      if (!(await game.jackpotPhase())) break;
    }
    expect(await game.jackpotPhase()).to.equal(false);

    // Next purchase phase: psd was reset at AdvanceModule:330 to the
    // transition close day; fresh 120-day window started.
    expect(await game.livenessTriggered()).to.equal(
      false,
      "fresh purchase phase: psd just reset, day clock fresh"
    );

    // Warp 130 days with no activity. No productive flag, day clock should fire.
    // Use 130 (not 121) to give buffer over the rngGate gap-backfill that
    // bumps psd by up to 120 on the next advanceGame call.
    await advanceTime(130 * 86400);

    expect(await game.livenessTriggered()).to.equal(
      true,
      "regression guard: liveness must re-arm past 120 days in next purchase phase"
    );
  });
});
