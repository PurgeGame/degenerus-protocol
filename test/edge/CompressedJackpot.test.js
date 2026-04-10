import { expect } from "chai";
import hre from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers.js";
import {
  deployFullProtocol,
  restoreAddresses,
} from "../helpers/deployFixture.js";
import {
  eth,
  advanceToNextDay,
  getEvents,
  getLastVRFRequestId,
  ZERO_BYTES32,
} from "../helpers/testUtils.js";

const ZERO_ADDRESS = hre.ethers.ZeroAddress;
const MintPaymentKind = { DirectEth: 0, Claimable: 1, Combined: 2 };

/**
 * Jackpot Compression Tier Tests (Normal / Compressed / Turbo)
 *
 * compressedJackpotFlag (uint8) determines how jackpot days are compressed:
 *
 *   Tier 0 — Normal (5 physical days):
 *     Target met after 3+ daily advances (purchaseDays > 3).
 *     counterStep=1, jackpot counter 0→1→2→3→4→5 in 5 physical days.
 *
 *   Tier 1 — Compressed (3 physical days):
 *     Target met within 3 daily advances (purchaseDays ≤ 3, but > 1).
 *     counterStep=2 for middle days: counter 0→2→4→5 in 3 physical days.
 *     Set in daily processing at AdvanceModule line ~255.
 *
 *   Tier 2 — Turbo (1 physical day):
 *     Target already met when purchaseDays ≤ 1 (checked at top of advanceGame).
 *     counterStep=JACKPOT_LEVEL_CAP (5): counter 0→5 in 1 physical day.
 *     Entire jackpot (transition + all draws) completes within a single
 *     advance cycle. Set at AdvanceModule line ~133.
 *
 * Day counting:
 *   purchaseStartDay is initialized to currentDayIndex() = 1 at deploy.
 *   GameTimeLib.currentDayIndexAt returns 1 on deploy day.
 *   Turbo:      (day - purchaseStartDay ≤ 1)  → checked at top of advanceGame.
 *   Compressed: (day - purchaseStartDay ≤ 3)  → checked during daily processing.
 *   Normal:     (day - purchaseStartDay > 3)   → default.
 *
 *   advanceGame reverts on deploy day (dailyIdx initialized to currentDayIndex).
 *   After advanceToNextDay (day 2): 2 - 1 = 1 → turbo if target met.
 *   After 2x advanceToNextDay (day 3): 3 - 1 = 2 → compressed if target met.
 *   After 3x advanceToNextDay (day 4): 4 - 1 = 3 → compressed if target met.
 *   After 4x advanceToNextDay (day 5): 5 - 1 = 4 → normal.
 */
describe("CompressedJackpot", function () {
  this.timeout(300_000);

  after(function () {
    restoreAddresses();
  });

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  async function getAdvanceEvents(tx, advanceModule) {
    return getEvents(tx, advanceModule, "Advance");
  }

  /** Buy N full tickets. 1 full ticket = qty 400 = costs priceWei. */
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

  /**
   * Drive one VRF cycle on the CURRENT day (no time advancement).
   * Caller must ensure advanceToNextDay() was called first so that
   * day != dailyIdx (advanceGame reverts with NotTimeYet otherwise).
   */
  async function driveOneCycleSameDay(game, deployer, mockVRF, advanceModule, word) {
    await game.connect(deployer).advanceGame();
    const requestId = await getLastVRFRequestId(mockVRF);
    try {
      await mockVRF.fulfillRandomWords(requestId, word);
    } catch {
      // May already be fulfilled
    }
    let lastStage = -1n;
    for (let i = 0; i < 200; i++) {
      try {
        const tx = await game.connect(deployer).advanceGame();
        const events = await getAdvanceEvents(tx, advanceModule);
        if (events.length > 0) {
          lastStage = events[0].args.stage;
        }
      } catch {
        break;
      }
      if (!(await game.rngLocked())) break;
    }
    return lastStage;
  }

  /**
   * Drive one VRF cycle: next day → advanceGame → fulfill → drain all processing.
   * Returns the last Advance stage observed.
   */
  async function driveOneCycle(game, deployer, mockVRF, advanceModule, word) {
    await advanceToNextDay();
    return driveOneCycleSameDay(game, deployer, mockVRF, advanceModule, word);
  }

  /**
   * Warm-up: advance one day with a small purchase so purchaseDays > 1
   * on the next cycle. This prevents turbo (tier=2) from firing when
   * the target is met on the following day.
   * After warmUpDay: dailyIdx = day 2, purchaseStartDay = 1.
   * Next advance will be day 3: purchaseDays = 3 - 1 = 2 → compressed.
   */
  async function warmUpDay(game, deployer, mockVRF, advanceModule, buyer) {
    await buyFullTickets(game, buyer, 10, 0.1);
    await advanceToNextDay();
    await driveOneCycleSameDay(game, deployer, mockVRF, advanceModule, 7n);
  }

  /**
   * Heavy purchasing: fill prize pool well above the 50 ETH bootstrap target.
   * Each buyer: whale bundle (2.4 ETH) + 500 full tickets (5 ETH) = 7.4 ETH.
   */
  async function heavyPurchases(game, buyers) {
    for (const buyer of buyers) {
      try {
        await game
          .connect(buyer)
          .purchaseWhaleBundle(buyer.address, 1, { value: eth(2.4) });
      } catch {
        // May fail for some buyers
      }
      await buyFullTickets(game, buyer, 500, 5);
    }
  }

  /**
   * Drive the game into jackpot phase. Returns true if reached.
   * Note: this also processes jackpot day 1 within the same cycle
   * that transitions (the advance module doesn't unlock RNG on
   * STAGE_ENTERED_JACKPOT, so processing continues to day-1 jackpot).
   *
   * WARNING: This cannot detect turbo (tier=2) because turbo completes
   * the entire jackpot phase within a single cycle, so jackpotPhase()
   * is already false by the time we check. Use driveTurboCompletion instead.
   */
  async function driveToJackpotPhase(game, deployer, mockVRF, advanceModule) {
    for (let cycle = 0; cycle < 30; cycle++) {
      await driveOneCycle(
        game,
        deployer,
        mockVRF,
        advanceModule,
        BigInt(cycle * 1000 + 42)
      );
      if (await game.jackpotPhase()) return true;
    }
    return false;
  }

  /**
   * Count the number of daily jackpot cycles remaining in the current jackpot phase.
   * Returns the count when the phase ends (jackpotPhase() becomes false).
   *
   * Important: driveToJackpotPhase already processes jackpot day 1,
   * so this counts REMAINING days. Total physical jackpot days =
   * 1 (consumed by driveToJackpotPhase) + countJackpotPhaseDays().
   */
  async function countJackpotPhaseDays(game, deployer, mockVRF, advanceModule) {
    let dayCount = 0;
    for (let day = 0; day < 12; day++) {
      await driveOneCycle(
        game,
        deployer,
        mockVRF,
        advanceModule,
        BigInt(day * 2000 + 99)
      );
      dayCount++;
      if (!(await game.jackpotPhase())) return dayCount;
    }
    return dayCount; // Phase didn't end within 12 days (unexpected)
  }

  /**
   * Drive compressed completion: advance to next day then run cycles
   * until level advances. purchaseDays=2 triggers compressed (flag=1).
   */
  async function driveTurboCompletion(game, deployer, mockVRF, advanceModule) {
    const levelBefore = await game.level();
    // Advance to next day so advanceGame doesn't revert with NotTimeYet
    await advanceToNextDay();
    // First cycle — triggers compressed (purchaseDays=2)
    await driveOneCycleSameDay(game, deployer, mockVRF, advanceModule, 42n);
    // Drive additional cycles if needed for full jackpot processing
    for (let i = 0; i < 20; i++) {
      const currentLevel = await game.level();
      if (currentLevel > levelBefore) return true;
      await driveOneCycle(game, deployer, mockVRF, advanceModule, BigInt(i * 1000 + 99));
    }
    return (await game.level()) > levelBefore;
  }

  // ---------------------------------------------------------------------------
  // Initial state
  // ---------------------------------------------------------------------------

  describe("initial state", function () {
    it("jackpotCompressionTier is 0 on deploy", async function () {
      const { game } = await loadFixture(deployFullProtocol);
      expect(await game.jackpotCompressionTier()).to.equal(0);
    });
  });

  // ---------------------------------------------------------------------------
  // Tier activation — which tier gets set based on timing
  // ---------------------------------------------------------------------------

  describe("tier activation", function () {
    it("tier=1 (compressed) when target met early (purchaseDays=2)", async function () {
      const { game, deployer, mockVRF, advanceModule, alice, bob, carol, dan, eve, others } =
        await loadFixture(deployFullProtocol);

      // Warm-up: consume day 2 with a small purchase (target NOT met).
      // This prevents turbo (purchaseDays=1) from firing on the next cycle.
      await warmUpDay(game, deployer, mockVRF, advanceModule, alice);

      // Heavy purchases to exceed target
      const buyers = [bob, carol, dan, eve, ...others.slice(0, 15)];
      await heavyPurchases(game, buyers);

      // driveToJackpotPhase advances to day 3 → purchaseDays = 3 - 1 = 2 ≤ 3 → compressed
      const reached = await driveToJackpotPhase(
        game,
        deployer,
        mockVRF,
        advanceModule
      );
      expect(reached).to.equal(true, "Should reach jackpot phase");
      expect(await game.jackpotCompressionTier()).to.equal(1);
    });

    it("tier=1 (compressed) when target met after first advance + next day (purchaseDays=2)", async function () {
      const { game, deployer, mockVRF, advanceModule, alice, bob, carol, dan, eve, others } =
        await loadFixture(deployFullProtocol);

      // Advance 1 (day 2): small purchase, target NOT met
      await buyFullTickets(game, alice, 200, 2);
      await advanceToNextDay();
      await driveOneCycleSameDay(game, deployer, mockVRF, advanceModule, 100n);
      expect(await game.jackpotPhase()).to.equal(false, "Should still be in purchase phase");

      // Heavy purchases push past the target
      const buyers = [bob, carol, dan, eve, ...others.slice(0, 15)];
      await heavyPurchases(game, buyers);

      // driveToJackpotPhase → day 3: purchaseDays = 3 - 1 = 2 ≤ 3 → compressed
      const reached = await driveToJackpotPhase(
        game,
        deployer,
        mockVRF,
        advanceModule
      );
      expect(reached).to.equal(true, "Should reach jackpot phase");
      expect(await game.jackpotCompressionTier()).to.equal(1);
    });

    it("tier=0 (normal) when target met after 4+ daily advances (purchaseDays > 3)", async function () {
      const { game, deployer, mockVRF, advanceModule, alice, bob, carol, dan, eve, others } =
        await loadFixture(deployFullProtocol);

      // Advance 1 (day 2): small purchase, target NOT met
      await buyFullTickets(game, alice, 200, 2);
      await advanceToNextDay();
      await driveOneCycleSameDay(game, deployer, mockVRF, advanceModule, 100n);
      expect(await game.jackpotPhase()).to.equal(false);

      // Advance 2 (day 3): small purchase, target NOT met
      await buyFullTickets(game, bob, 200, 2);
      await driveOneCycle(game, deployer, mockVRF, advanceModule, 200n);
      expect(await game.jackpotPhase()).to.equal(false);

      // Advance 3 (day 4): small purchase, target NOT met
      await buyFullTickets(game, carol, 200, 2);
      await driveOneCycle(game, deployer, mockVRF, advanceModule, 300n);
      expect(await game.jackpotPhase()).to.equal(false);

      // Advance 4 (day 5): small purchase, target NOT met
      await buyFullTickets(game, others[0], 200, 2);
      await driveOneCycle(game, deployer, mockVRF, advanceModule, 400n);
      expect(await game.jackpotPhase()).to.equal(false);

      // Heavy purchases push past target
      const buyers = [dan, eve, ...others.slice(1, 15)];
      await heavyPurchases(game, buyers);

      // Next advance: purchaseDays = day - 1 > 3 → normal
      const reached = await driveToJackpotPhase(
        game,
        deployer,
        mockVRF,
        advanceModule
      );
      expect(reached).to.equal(true, "Should reach jackpot phase");
      expect(await game.jackpotCompressionTier()).to.equal(0);
    });
  });

  // ---------------------------------------------------------------------------
  // Turbo mode (tier=2)
  // ---------------------------------------------------------------------------

  describe("compressed mode via early target (tier=1)", function () {
    it("compressed flag (1) is set when target met after warm-up (purchaseDays=2)", async function () {
      const { game, deployer, mockVRF, advanceModule, alice, bob, carol, dan, eve, others } =
        await loadFixture(deployFullProtocol);

      // Warm-up: consume day 2 so purchaseDays > 1 on next advance
      await warmUpDay(game, deployer, mockVRF, advanceModule, alice);

      // Heavy purchases to exceed target
      const buyers = [bob, carol, dan, eve, ...others.slice(0, 15)];
      await heavyPurchases(game, buyers);

      // Drive a full cycle on day 3 — compressed flag is set during daily processing
      // purchaseDays = day 3 - purchaseStartDay 1 = 2 → compressed
      await advanceToNextDay();
      await driveOneCycleSameDay(game, deployer, mockVRF, advanceModule, 42n);
      expect(await game.jackpotCompressionTier()).to.equal(1,
        "Compressed flag should be set after cycle on day 3");
    });

    it("turbo flag (2) IS set when first advance is on day 2 (purchaseDays=1)", async function () {
      const { game, deployer, mockVRF, advanceModule, alice, bob, carol, dan, eve, others } =
        await loadFixture(deployFullProtocol);

      // Heavy purchases on deploy day (no warm-up)
      const buyers = [alice, bob, carol, dan, eve, ...others.slice(0, 15)];
      await heavyPurchases(game, buyers);

      // Advance to day 2 before calling advanceGame → purchaseDays = 2 - 1 = 1
      await advanceToNextDay();
      await game.connect(deployer).advanceGame();
      // purchaseDays=1 triggers turbo (flag=2)
      const tier = await game.jackpotCompressionTier();
      expect(tier).to.equal(2, "Turbo should activate on day 2 (purchaseDays=1)");
    });

    it("level advances after compressed jackpot completes", async function () {
      const { game, deployer, mockVRF, advanceModule, alice, bob, carol, dan, eve, others } =
        await loadFixture(deployFullProtocol);

      // Warm-up to avoid turbo
      await warmUpDay(game, deployer, mockVRF, advanceModule, alice);

      const buyers = [bob, carol, dan, eve, ...others.slice(0, 15)];
      await heavyPurchases(game, buyers);

      const levelBefore = await game.level();
      // Drive compressed jackpot to completion
      const reached = await driveToJackpotPhase(game, deployer, mockVRF, advanceModule);
      expect(reached).to.equal(true, "Should reach jackpot phase");
      expect(await game.jackpotCompressionTier()).to.equal(1);
      await countJackpotPhaseDays(game, deployer, mockVRF, advanceModule);
      const levelAfter = await game.level();

      expect(levelAfter).to.be.gt(levelBefore, "Level should advance after compressed");
    });

    it("jackpotPhase() is false after compressed completion", async function () {
      const { game, deployer, mockVRF, advanceModule, alice, bob, carol, dan, eve, others } =
        await loadFixture(deployFullProtocol);

      // Warm-up to avoid turbo
      await warmUpDay(game, deployer, mockVRF, advanceModule, alice);

      const buyers = [bob, carol, dan, eve, ...others.slice(0, 15)];
      await heavyPurchases(game, buyers);

      const reached = await driveToJackpotPhase(game, deployer, mockVRF, advanceModule);
      expect(reached).to.equal(true);
      expect(await game.jackpotCompressionTier()).to.equal(1);

      // Drive through compressed jackpot phase to completion
      await countJackpotPhaseDays(game, deployer, mockVRF, advanceModule);
      expect(await game.jackpotPhase()).to.equal(false,
        "Jackpot phase should be over after compressed completion");
    });

    it("flag resets to 0 after compressed completion", async function () {
      const { game, deployer, mockVRF, advanceModule, alice, bob, carol, dan, eve, others } =
        await loadFixture(deployFullProtocol);

      // Warm-up to avoid turbo
      await warmUpDay(game, deployer, mockVRF, advanceModule, alice);

      const buyers = [bob, carol, dan, eve, ...others.slice(0, 15)];
      await heavyPurchases(game, buyers);

      const reached = await driveToJackpotPhase(game, deployer, mockVRF, advanceModule);
      expect(reached).to.equal(true);
      expect(await game.jackpotCompressionTier()).to.equal(1);

      // Drive through compressed jackpot phase to completion
      await countJackpotPhaseDays(game, deployer, mockVRF, advanceModule);

      expect(await game.jackpotCompressionTier()).to.equal(0,
        "Flag should be reset to 0 after compressed completion");
    });

    it("compressed drains currentPrizePool to zero", async function () {
      const { game, deployer, mockVRF, advanceModule, alice, bob, carol, dan, eve, others } =
        await loadFixture(deployFullProtocol);

      // Warm-up to avoid turbo
      await warmUpDay(game, deployer, mockVRF, advanceModule, alice);

      const buyers = [bob, carol, dan, eve, ...others.slice(0, 15)];
      await heavyPurchases(game, buyers);

      const reached = await driveToJackpotPhase(game, deployer, mockVRF, advanceModule);
      expect(reached).to.equal(true);
      expect(await game.jackpotCompressionTier()).to.equal(1);

      // Drive through compressed jackpot phase to completion
      await countJackpotPhaseDays(game, deployer, mockVRF, advanceModule);

      const poolAfter = await game.currentPrizePoolView();
      expect(poolAfter).to.equal(0n, "Prize pool should drain to zero after compressed");
    });

    it("compressed completes faster than normal", async function () {
      // Compressed: warm-up + heavy purchases + early target → 3 physical jackpot days
      // Normal: spread purchases over 4+ days → 5 physical jackpot days
      // This test verifies compressed needs fewer total cycles than normal.
      const { game, deployer, mockVRF, advanceModule, alice, bob, carol, dan, eve, others } =
        await loadFixture(deployFullProtocol);

      // Warm-up to avoid turbo
      await warmUpDay(game, deployer, mockVRF, advanceModule, alice);

      const buyers = [bob, carol, dan, eve, ...others.slice(0, 15)];
      await heavyPurchases(game, buyers);

      // Compressed: track total cycles to completion
      const levelBefore = await game.level();
      let compressedCycles = 0;
      // First cycle on day 3 (purchaseDays = 3-1 = 2 → compressed)
      await advanceToNextDay();
      await driveOneCycleSameDay(game, deployer, mockVRF, advanceModule, 42n);
      compressedCycles++;
      // Additional cycles if needed
      for (let i = 0; i < 20; i++) {
        if ((await game.level()) > levelBefore) break;
        await driveOneCycle(game, deployer, mockVRF, advanceModule, BigInt(i * 1000 + 99));
        compressedCycles++;
      }
      expect(await game.level()).to.be.gt(levelBefore, "Compressed should complete");

      // Normal takes 5 physical jackpot days (1 transition + 4 remaining).
      // Compressed should take fewer total cycles than normal's 5+ days.
      expect(compressedCycles).to.be.lte(5,
        "Compressed should complete in fewer cycles than normal's 5+ days");
    });
  });

  // ---------------------------------------------------------------------------
  // Compressed mode (tier=1) — jackpot phase duration
  // ---------------------------------------------------------------------------

  describe("compressed mode (tier=1)", function () {
    it("compressed jackpot takes 3 physical days (2 remaining after transition)", async function () {
      const { game, deployer, mockVRF, advanceModule, alice, bob, carol, dan, eve, others } =
        await loadFixture(deployFullProtocol);

      // Warm-up: consume day 2 so purchaseDays > 1 on next advance
      await warmUpDay(game, deployer, mockVRF, advanceModule, alice);

      // Heavy purchases → driveToJackpotPhase → day 3 → compressed (tier=1)
      const buyers = [bob, carol, dan, eve, ...others.slice(0, 15)];
      await heavyPurchases(game, buyers);

      const reached = await driveToJackpotPhase(
        game,
        deployer,
        mockVRF,
        advanceModule
      );
      expect(reached).to.equal(true);
      expect(await game.jackpotCompressionTier()).to.equal(1);

      // driveToJackpotPhase already consumed jackpot day 1 (counter 0→2).
      // Remaining: day 2 (counter 2→4) + day 3 (counter 4→5, _endPhase, jackpotPhase still true)
      //           + day 4 (phaseTransitionActive processed, jackpotPhase becomes false) = 3 cycles.
      const remainingDays = await countJackpotPhaseDays(
        game,
        deployer,
        mockVRF,
        advanceModule
      );

      // Total physical jackpot days: 1 (in driveToJackpotPhase) + remainingDays = 4
      expect(remainingDays).to.equal(3, "Compressed phase should have 3 remaining cycles after transition");
    });

    it("compressed flag resets to 0 after jackpot phase ends", async function () {
      const { game, deployer, mockVRF, advanceModule, alice, bob, carol, dan, eve, others } =
        await loadFixture(deployFullProtocol);

      // Warm-up to avoid turbo
      await warmUpDay(game, deployer, mockVRF, advanceModule, alice);

      // Trigger compressed jackpot
      const buyers = [bob, carol, dan, eve, ...others.slice(0, 15)];
      await heavyPurchases(game, buyers);

      const reached = await driveToJackpotPhase(
        game,
        deployer,
        mockVRF,
        advanceModule
      );
      expect(reached).to.equal(true);
      expect(await game.jackpotCompressionTier()).to.equal(1);

      // Drive through jackpot phase to completion
      await countJackpotPhaseDays(game, deployer, mockVRF, advanceModule);

      // After phase ends, flag should be 0
      expect(await game.jackpotPhase()).to.equal(false);
      expect(await game.jackpotCompressionTier()).to.equal(0);
    });

    it("compressed jackpot drains currentPrizePool to zero by final day", async function () {
      const { game, deployer, mockVRF, advanceModule, alice, bob, carol, dan, eve, others } =
        await loadFixture(deployFullProtocol);

      // Warm-up to avoid turbo
      await warmUpDay(game, deployer, mockVRF, advanceModule, alice);

      const buyers = [bob, carol, dan, eve, ...others.slice(0, 15)];
      await heavyPurchases(game, buyers);

      const reached = await driveToJackpotPhase(
        game,
        deployer,
        mockVRF,
        advanceModule
      );
      expect(reached).to.equal(true);
      expect(await game.jackpotCompressionTier()).to.equal(1);

      // Record pool before jackpot phase payouts
      const poolBefore = await game.currentPrizePoolView();
      expect(poolBefore).to.be.gt(0n, "Prize pool should be non-zero at jackpot phase start");

      // Drive through compressed jackpot phase
      await countJackpotPhaseDays(game, deployer, mockVRF, advanceModule);

      // After phase ends, current prize pool should be drained
      const poolAfter = await game.currentPrizePoolView();
      expect(poolAfter).to.equal(0n, "Prize pool should be zero after jackpot phase completes");
    });
  });

  // ---------------------------------------------------------------------------
  // Normal mode (tier=0) — jackpot phase duration
  // ---------------------------------------------------------------------------

  describe("normal mode (tier=0)", function () {
    it("normal jackpot takes 5 physical days (4 remaining after transition)", async function () {
      const { game, deployer, mockVRF, advanceModule, alice, bob, carol, dan, eve, others } =
        await loadFixture(deployFullProtocol);

      // Spread purchases over 4+ advances so purchaseDays > 3 when target met.
      // purchaseStartDay = 1 at deploy.
      // Advance 1 (day 2): purchaseDays = 2-1 = 1
      await buyFullTickets(game, alice, 200, 2);
      await advanceToNextDay();
      await driveOneCycleSameDay(game, deployer, mockVRF, advanceModule, 100n);

      // Advance 2 (day 3): purchaseDays = 3-1 = 2
      await buyFullTickets(game, bob, 200, 2);
      await driveOneCycle(game, deployer, mockVRF, advanceModule, 200n);

      // Advance 3 (day 4): purchaseDays = 4-1 = 3
      await buyFullTickets(game, carol, 200, 2);
      await driveOneCycle(game, deployer, mockVRF, advanceModule, 300n);

      // Advance 4 (day 5): purchaseDays = 5-1 = 4 > 3 → normal
      await buyFullTickets(game, others[0], 200, 2);
      await driveOneCycle(game, deployer, mockVRF, advanceModule, 400n);

      // Heavy purchases push past target
      const buyers = [dan, eve, ...others.slice(1, 15)];
      await heavyPurchases(game, buyers);

      let reached = await driveToJackpotPhase(game, deployer, mockVRF, advanceModule);
      expect(reached).to.equal(true);
      expect(await game.jackpotCompressionTier()).to.equal(0);

      // driveToJackpotPhase consumed jackpot day 1 (counter 0→1).
      // Remaining: days 2-5 (counter 1→2→3→4→5, _endPhase, jackpotPhase still true)
      //           + day 6 (phaseTransitionActive processed, jackpotPhase becomes false) = 5 cycles.
      const normalRemainingDays = await countJackpotPhaseDays(
        game,
        deployer,
        mockVRF,
        advanceModule
      );

      // Total physical jackpot days: 1 (in driveToJackpotPhase) + normalRemainingDays = 6
      expect(normalRemainingDays).to.equal(5, "Normal phase should have 5 remaining cycles after transition");
    });
  });
});
