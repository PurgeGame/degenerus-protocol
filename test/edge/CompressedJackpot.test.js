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
 *     Target met after 2+ daily advances (purchaseDays > 2).
 *     counterStep=1, jackpot counter 0→1→2→3→4→5 in 5 physical days.
 *
 *   Tier 1 — Compressed (3 physical days):
 *     Target met within 2 daily advances (purchaseDays ≤ 2, but > 1).
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
 *   purchaseStartDay defaults to 0 at level 0.
 *   GameTimeLib.currentDayIndexAt returns 1 on deploy day.
 *   Turbo:      (day - purchaseStartDay ≤ 1)  → checked at top of advanceGame.
 *   Compressed: (day - purchaseStartDay ≤ 2)  → checked during daily processing.
 *   Normal:     (day - purchaseStartDay > 2)   → default.
 *
 *   On deploy day (day 1): 1 - 0 = 1 → turbo if target met.
 *   After advanceToNextDay (day 2): 2 - 0 = 2 → compressed if target met.
 *   After 2x advanceToNextDay (day 3): 3 - 0 = 3 → normal.
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
   * Used for the very first advance on deploy day (day 1) where
   * dailyIdx=0 and day=1, so day != dailyIdx passes immediately.
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
   * Drive turbo completion: advance on deploy day (day 1) where
   * purchaseDays=1 triggers turbo (flag=2). The entire jackpot phase
   * completes within a single driveOneCycleSameDay call.
   * Continues driving cycles until level advances (turbo + any remaining
   * processing may span more than one cycle).
   */
  async function driveTurboCompletion(game, deployer, mockVRF, advanceModule) {
    const levelBefore = await game.level();
    // First cycle on deploy day — triggers turbo
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
    it("tier=1 (compressed) when target met on first driveToJackpotPhase cycle (day 2, purchaseDays=2)", async function () {
      const { game, deployer, mockVRF, advanceModule, alice, bob, carol, dan, eve, others } =
        await loadFixture(deployFullProtocol);

      // Heavy purchases to exceed target immediately
      const buyers = [alice, bob, carol, dan, eve, ...others.slice(0, 15)];
      await heavyPurchases(game, buyers);

      // driveToJackpotPhase advances time first → day 2 → purchaseDays = 2 - 0 = 2 ≤ 2
      const reached = await driveToJackpotPhase(
        game,
        deployer,
        mockVRF,
        advanceModule
      );
      expect(reached).to.equal(true, "Should reach jackpot phase");
      expect(await game.jackpotCompressionTier()).to.equal(1);
    });

    it("tier=1 (compressed) when target met after same-day advance + next day", async function () {
      const { game, deployer, mockVRF, advanceModule, alice, bob, carol, dan, eve, others } =
        await loadFixture(deployFullProtocol);

      // Advance 1 (deploy day = day 1): small purchase, target NOT met
      await buyFullTickets(game, alice, 200, 2);
      await driveOneCycleSameDay(game, deployer, mockVRF, advanceModule, 100n);
      expect(await game.jackpotPhase()).to.equal(false, "Should still be in purchase phase");

      // Heavy purchases push past the target
      const buyers = [bob, carol, dan, eve, ...others.slice(0, 15)];
      await heavyPurchases(game, buyers);

      // driveToJackpotPhase → day 2: purchaseDays = 2 ≤ 2 → compressed
      const reached = await driveToJackpotPhase(
        game,
        deployer,
        mockVRF,
        advanceModule
      );
      expect(reached).to.equal(true, "Should reach jackpot phase");
      expect(await game.jackpotCompressionTier()).to.equal(1);
    });

    it("tier=0 (normal) when target met after 2+ daily advances (day 3+)", async function () {
      const { game, deployer, mockVRF, advanceModule, alice, bob, carol, dan, eve, others } =
        await loadFixture(deployFullProtocol);

      // Advance 1 (deploy day = day 1): small purchase, target NOT met
      await buyFullTickets(game, alice, 200, 2);
      await driveOneCycleSameDay(game, deployer, mockVRF, advanceModule, 100n);
      expect(await game.jackpotPhase()).to.equal(false);

      // Advance 2 (day 2): small purchase, target NOT met
      await buyFullTickets(game, bob, 200, 2);
      await driveOneCycle(game, deployer, mockVRF, advanceModule, 200n);
      expect(await game.jackpotPhase()).to.equal(false);

      // Heavy purchases push past target
      const buyers = [carol, dan, eve, ...others.slice(0, 15)];
      await heavyPurchases(game, buyers);

      // Advance 3 (day 3): purchaseDays = 3 - 0 = 3 > 2 → normal
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

  describe("turbo mode (tier=2)", function () {
    it("turbo flag (2) is set when target met on deploy day (purchaseDays ≤ 1)", async function () {
      const { game, deployer, mockVRF, advanceModule, alice, bob, carol, dan, eve, others } =
        await loadFixture(deployFullProtocol);

      // Heavy purchases on deploy day to exceed target
      const buyers = [alice, bob, carol, dan, eve, ...others.slice(0, 15)];
      await heavyPurchases(game, buyers);

      // First advanceGame on deploy day (day 1, purchaseDays=1) sets turbo flag
      // and requests RNG. Check flag before VRF fulfillment.
      await game.connect(deployer).advanceGame();
      expect(await game.jackpotCompressionTier()).to.equal(2,
        "Turbo flag should be set after initial advanceGame on deploy day");
    });

    it("turbo flag is NOT set when first advance is on day 2 (purchaseDays=2)", async function () {
      const { game, deployer, mockVRF, advanceModule, alice, bob, carol, dan, eve, others } =
        await loadFixture(deployFullProtocol);

      // Heavy purchases on deploy day
      const buyers = [alice, bob, carol, dan, eve, ...others.slice(0, 15)];
      await heavyPurchases(game, buyers);

      // Advance to day 2 before calling advanceGame → purchaseDays = 2 > 1
      await advanceToNextDay();
      await game.connect(deployer).advanceGame();
      // Should be compressed (1) or not yet determined, but NOT turbo (2)
      const tier = await game.jackpotCompressionTier();
      expect(tier).to.not.equal(2, "Turbo should NOT activate on day 2");
    });

    it("level advances after turbo jackpot completes", async function () {
      const { game, deployer, mockVRF, advanceModule, alice, bob, carol, dan, eve, others } =
        await loadFixture(deployFullProtocol);

      const buyers = [alice, bob, carol, dan, eve, ...others.slice(0, 15)];
      await heavyPurchases(game, buyers);

      const levelBefore = await game.level();
      const completed = await driveTurboCompletion(game, deployer, mockVRF, advanceModule);
      const levelAfter = await game.level();

      expect(completed).to.equal(true, "Turbo jackpot should complete");
      expect(levelAfter).to.be.gt(levelBefore, "Level should advance after turbo");
    });

    it("jackpotPhase() is false after turbo (phase completed within cycle)", async function () {
      const { game, deployer, mockVRF, advanceModule, alice, bob, carol, dan, eve, others } =
        await loadFixture(deployFullProtocol);

      const buyers = [alice, bob, carol, dan, eve, ...others.slice(0, 15)];
      await heavyPurchases(game, buyers);

      await driveTurboCompletion(game, deployer, mockVRF, advanceModule);
      expect(await game.jackpotPhase()).to.equal(false,
        "Jackpot phase should already be over after turbo");
    });

    it("flag resets to 0 after turbo completion", async function () {
      const { game, deployer, mockVRF, advanceModule, alice, bob, carol, dan, eve, others } =
        await loadFixture(deployFullProtocol);

      const buyers = [alice, bob, carol, dan, eve, ...others.slice(0, 15)];
      await heavyPurchases(game, buyers);

      // Verify flag is 2 during turbo
      await game.connect(deployer).advanceGame();
      expect(await game.jackpotCompressionTier()).to.equal(2);

      // Fulfill VRF and drive to completion
      const requestId = await getLastVRFRequestId(mockVRF);
      try { await mockVRF.fulfillRandomWords(requestId, 42n); } catch {}
      for (let i = 0; i < 200; i++) {
        try { await game.connect(deployer).advanceGame(); } catch { break; }
        if (!(await game.rngLocked())) break;
      }
      // Continue driving until level advances
      for (let i = 0; i < 20; i++) {
        if ((await game.level()) > 0n) break;
        await driveOneCycle(game, deployer, mockVRF, advanceModule, BigInt(i * 3000 + 77));
      }

      expect(await game.jackpotCompressionTier()).to.equal(0,
        "Flag should be reset to 0 after turbo completion");
    });

    it("turbo drains currentPrizePool to zero", async function () {
      const { game, deployer, mockVRF, advanceModule, alice, bob, carol, dan, eve, others } =
        await loadFixture(deployFullProtocol);

      const buyers = [alice, bob, carol, dan, eve, ...others.slice(0, 15)];
      await heavyPurchases(game, buyers);

      // Pool gets filled AND drained within the turbo cycle (daily advance
      // splits ETH into the pool, then turbo jackpot pays it all out).
      await driveTurboCompletion(game, deployer, mockVRF, advanceModule);

      const poolAfter = await game.currentPrizePoolView();
      expect(poolAfter).to.equal(0n, "Prize pool should drain to zero after turbo");
    });

    it("turbo completes faster than compressed", async function () {
      // Turbo: deploy heavy purchases + driveOneCycleSameDay → level advances in 1 cycle
      // Compressed: driveToJackpotPhase → 3 total physical days
      // This test verifies turbo needs fewer total cycles than compressed.
      const { game, deployer, mockVRF, advanceModule, alice, bob, carol, dan, eve, others } =
        await loadFixture(deployFullProtocol);

      const buyers = [alice, bob, carol, dan, eve, ...others.slice(0, 15)];
      await heavyPurchases(game, buyers);

      // Turbo: track total cycles to completion
      const levelBefore = await game.level();
      let turboCycles = 0;
      // First cycle on deploy day
      await driveOneCycleSameDay(game, deployer, mockVRF, advanceModule, 42n);
      turboCycles++;
      // Additional cycles if needed
      for (let i = 0; i < 20; i++) {
        if ((await game.level()) > levelBefore) break;
        await driveOneCycle(game, deployer, mockVRF, advanceModule, BigInt(i * 1000 + 99));
        turboCycles++;
      }
      expect(await game.level()).to.be.gt(levelBefore, "Turbo should complete");

      // Compressed takes 3 physical days (1 transition + 2 remaining).
      // Since driveToJackpotPhase + countJackpotPhaseDays = 1 + 2 = 3 cycles minimum.
      // Turbo should take fewer total cycles.
      expect(turboCycles).to.be.lte(3,
        "Turbo should complete in fewer cycles than compressed's 3 days");
    });
  });

  // ---------------------------------------------------------------------------
  // Compressed mode (tier=1) — jackpot phase duration
  // ---------------------------------------------------------------------------

  describe("compressed mode (tier=1)", function () {
    it("compressed jackpot takes 3 physical days (2 remaining after transition)", async function () {
      const { game, deployer, mockVRF, advanceModule, alice, bob, carol, dan, eve, others } =
        await loadFixture(deployFullProtocol);

      // Heavy purchases → driveToJackpotPhase → day 2 → compressed (tier=1)
      const buyers = [alice, bob, carol, dan, eve, ...others.slice(0, 15)];
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
      // Remaining: day 2 (counter 2→4) + day 3 (counter 4→5, phase ends) = 2 cycles.
      const remainingDays = await countJackpotPhaseDays(
        game,
        deployer,
        mockVRF,
        advanceModule
      );

      // Total physical jackpot days: 1 (in driveToJackpotPhase) + remainingDays = 3
      expect(remainingDays).to.equal(2, "Compressed phase should have 2 remaining cycles after transition");
    });

    it("compressed flag resets to 0 after jackpot phase ends", async function () {
      const { game, deployer, mockVRF, advanceModule, alice, bob, carol, dan, eve, others } =
        await loadFixture(deployFullProtocol);

      // Trigger compressed jackpot
      const buyers = [alice, bob, carol, dan, eve, ...others.slice(0, 15)];
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

      const buyers = [alice, bob, carol, dan, eve, ...others.slice(0, 15)];
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

      // Spread purchases over 3+ advances to avoid compressed/turbo flag
      // Advance 1 (deploy day)
      await buyFullTickets(game, alice, 200, 2);
      await driveOneCycleSameDay(game, deployer, mockVRF, advanceModule, 100n);

      // Advance 2 (day 2)
      await buyFullTickets(game, bob, 200, 2);
      await driveOneCycle(game, deployer, mockVRF, advanceModule, 200n);

      // Advance 3+ (day 3): push past target
      const buyers = [carol, dan, eve, ...others.slice(0, 15)];
      await heavyPurchases(game, buyers);

      let reached = await driveToJackpotPhase(game, deployer, mockVRF, advanceModule);
      expect(reached).to.equal(true);
      expect(await game.jackpotCompressionTier()).to.equal(0);

      // driveToJackpotPhase consumed jackpot day 1 (counter 0→1).
      // Remaining: days 2-5 (counter 1→2→3→4→5) = 4 cycles.
      const normalRemainingDays = await countJackpotPhaseDays(
        game,
        deployer,
        mockVRF,
        advanceModule
      );

      // Total physical jackpot days: 1 (in driveToJackpotPhase) + normalRemainingDays = 5
      expect(normalRemainingDays).to.equal(4, "Normal phase should have 4 remaining cycles after transition");
      // Compressed would be 2 remaining days, normal is 4 → normal takes longer
    });
  });
});
