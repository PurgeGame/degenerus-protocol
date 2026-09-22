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
  getBlockTimestamp,
  getEvents,
  getLastVRFRequestId,
  ZERO_BYTES32,
} from "../helpers/testUtils.js";

const ZERO_ADDRESS = hre.ethers.ZeroAddress;
const MintPaymentKind = { DirectEth: 0, Claimable: 1, Combined: 2 };

/**
 * Jackpot Duration Tests (Standard / Turbo)
 *
 * jackpotDuration() returns 3 by default and 1 while turbo is selected:
 *
 *   Standard (3 physical days):
 *     Every non-turbo level, regardless of how long the purchase target takes.
 *     Counter 0→1→2→3: early-bird day, doubled middle day, final pool payout.
 *     Jackpot→purchase housekeeping folds into the last jackpot day.
 *
 *   Turbo (1 physical day):
 *     Target already met when purchaseDays ≤ 1 (checked at top of advanceGame).
 *     Counter 0→1 in one physical day.
 *     Entire jackpot completes via same-day advance cycles. BAF levels arm
 *     at purchase-day settlement to preserve their last-purchase window.
 *
 * purchaseStartDay is initialized to day 1 at deploy. The first advance on
 * day 2 can trigger turbo; later targets always select the three-day schedule.
 */
describe("JackpotDuration", function () {
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
      MintPaymentKind.DirectEth,false, 
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
   * on the next cycle. This prevents turbo (1 day) from firing when
   * the target is met on the following day.
   * After warmUpDay: dailyIdx = day 2, purchaseStartDay = 1.
   * Next advance will be day 3: purchaseDays = 3 - 1 = 2 → standard.
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
          .purchaseWhalePass(buyer.address, 1, hre.ethers.ZeroHash, { value: eth(2.4) });
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
   * WARNING: This cannot detect turbo (1 day) because turbo completes
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
   * Drive standard completion: advance to next day then run cycles
   * until level advances. purchaseDays=2 triggers standard (three-day schedule).
   */
  async function driveTurboCompletion(game, deployer, mockVRF, advanceModule) {
    const levelBefore = await game.level();
    // Advance to next day so advanceGame doesn't revert with NotTimeYet
    await advanceToNextDay();
    // First cycle — triggers standard (purchaseDays=2)
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
    it("jackpotDuration is 3 on deploy", async function () {
      const { game } = await loadFixture(deployFullProtocol);
      expect(await game.jackpotDuration()).to.equal(3);
    });
  });

  // ---------------------------------------------------------------------------
  // Tier activation — which tier gets set based on timing
  // ---------------------------------------------------------------------------

  describe("tier activation", function () {
    it("3 days when target met early (purchaseDays=2)", async function () {
      const { game, deployer, mockVRF, advanceModule, alice, bob, carol, dan, eve, others } =
        await loadFixture(deployFullProtocol);

      // Warm-up: consume day 2 with a small purchase (target NOT met).
      // This prevents turbo (purchaseDays=1) from firing on the next cycle.
      await warmUpDay(game, deployer, mockVRF, advanceModule, alice);

      // Heavy purchases to exceed target
      const buyers = [bob, carol, dan, eve, ...others.slice(0, 15)];
      await heavyPurchases(game, buyers);

      // driveToJackpotPhase advances to day 3 → purchaseDays = 3 - 1 = 2 ≤ 3 → standard
      const reached = await driveToJackpotPhase(
        game,
        deployer,
        mockVRF,
        advanceModule
      );
      expect(reached).to.equal(true, "Should reach jackpot phase");
      expect(await game.jackpotDuration()).to.equal(3);
    });

    it("3 days when target met after first advance + next day (purchaseDays=2)", async function () {
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

      // driveToJackpotPhase → day 3: purchaseDays = 3 - 1 = 2 ≤ 3 → standard
      const reached = await driveToJackpotPhase(
        game,
        deployer,
        mockVRF,
        advanceModule
      );
      expect(reached).to.equal(true, "Should reach jackpot phase");
      expect(await game.jackpotDuration()).to.equal(3);
    });

    it("3 days when target met after 4+ daily advances (purchaseDays > 3)", async function () {
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

      // Next advance: purchaseDays = day - 1 > 3 still selects three days
      const reached = await driveToJackpotPhase(
        game,
        deployer,
        mockVRF,
        advanceModule
      );
      expect(reached).to.equal(true, "Should reach jackpot phase");
      expect(await game.jackpotDuration()).to.equal(3);
    });
  });

  // ---------------------------------------------------------------------------
  // Turbo mode (1 day)
  // ---------------------------------------------------------------------------

  describe("standard mode via early target (3 days)", function () {
    it("standard schedule is used when target met after warm-up (purchaseDays=2)", async function () {
      const { game, deployer, mockVRF, advanceModule, alice, bob, carol, dan, eve, others } =
        await loadFixture(deployFullProtocol);

      // Warm-up: consume day 2 so purchaseDays > 1 on next advance
      await warmUpDay(game, deployer, mockVRF, advanceModule, alice);

      // Heavy purchases to exceed target
      const buyers = [bob, carol, dan, eve, ...others.slice(0, 15)];
      await heavyPurchases(game, buyers);

      // Drive a full cycle on day 3 — standard flag is set during daily processing
      // purchaseDays = day 3 - purchaseStartDay 1 = 2 → standard
      await advanceToNextDay();
      await driveOneCycleSameDay(game, deployer, mockVRF, advanceModule, 42n);
      expect(await game.jackpotDuration()).to.equal(3,
        "Standard flag should be set after cycle on day 3");
    });

    it("one-day schedule IS set when first advance is on day 2 (purchaseDays=1)", async function () {
      const { game, deployer, mockVRF, advanceModule, alice, bob, carol, dan, eve, others } =
        await loadFixture(deployFullProtocol);

      // Heavy purchases on deploy day (no warm-up)
      const buyers = [alice, bob, carol, dan, eve, ...others.slice(0, 15)];
      await heavyPurchases(game, buyers);

      // Advance to day 2 before calling advanceGame → purchaseDays = 2 - 1 = 1
      await advanceToNextDay();
      await game.connect(deployer).advanceGame();
      // purchaseDays=1 triggers turbo (one-day schedule)
      const days = await game.jackpotDuration();
      expect(days).to.equal(1, "Turbo should activate on day 2 (purchaseDays=1)");
    });

    it("level advances after standard jackpot completes", async function () {
      const { game, deployer, mockVRF, advanceModule, alice, bob, carol, dan, eve, others } =
        await loadFixture(deployFullProtocol);

      // Warm-up to avoid turbo
      await warmUpDay(game, deployer, mockVRF, advanceModule, alice);

      const buyers = [bob, carol, dan, eve, ...others.slice(0, 15)];
      await heavyPurchases(game, buyers);

      const levelBefore = await game.level();
      // Drive standard jackpot to completion
      const reached = await driveToJackpotPhase(game, deployer, mockVRF, advanceModule);
      expect(reached).to.equal(true, "Should reach jackpot phase");
      expect(await game.jackpotDuration()).to.equal(3);
      await countJackpotPhaseDays(game, deployer, mockVRF, advanceModule);
      const levelAfter = await game.level();

      expect(levelAfter).to.be.gt(levelBefore, "Level should advance after standard");
    });

    it("jackpotPhase() is false after standard completion", async function () {
      const { game, deployer, mockVRF, advanceModule, alice, bob, carol, dan, eve, others } =
        await loadFixture(deployFullProtocol);

      // Warm-up to avoid turbo
      await warmUpDay(game, deployer, mockVRF, advanceModule, alice);

      const buyers = [bob, carol, dan, eve, ...others.slice(0, 15)];
      await heavyPurchases(game, buyers);

      const reached = await driveToJackpotPhase(game, deployer, mockVRF, advanceModule);
      expect(reached).to.equal(true);
      expect(await game.jackpotDuration()).to.equal(3);

      // Drive through standard jackpot phase to completion
      await countJackpotPhaseDays(game, deployer, mockVRF, advanceModule);
      expect(await game.jackpotPhase()).to.equal(false,
        "Jackpot phase should be over after standard completion");
    });

    it("duration returns to 3 days after standard completion", async function () {
      const { game, deployer, mockVRF, advanceModule, alice, bob, carol, dan, eve, others } =
        await loadFixture(deployFullProtocol);

      // Warm-up to avoid turbo
      await warmUpDay(game, deployer, mockVRF, advanceModule, alice);

      const buyers = [bob, carol, dan, eve, ...others.slice(0, 15)];
      await heavyPurchases(game, buyers);

      const reached = await driveToJackpotPhase(game, deployer, mockVRF, advanceModule);
      expect(reached).to.equal(true);
      expect(await game.jackpotDuration()).to.equal(3);

      // Drive through standard jackpot phase to completion
      await countJackpotPhaseDays(game, deployer, mockVRF, advanceModule);

      expect(await game.jackpotDuration()).to.equal(3,
        "Flag should be reset to 0 after standard completion");
    });

    it("standard drains currentPrizePool to zero", async function () {
      const { game, deployer, mockVRF, advanceModule, alice, bob, carol, dan, eve, others } =
        await loadFixture(deployFullProtocol);

      // Warm-up to avoid turbo
      await warmUpDay(game, deployer, mockVRF, advanceModule, alice);

      const buyers = [bob, carol, dan, eve, ...others.slice(0, 15)];
      await heavyPurchases(game, buyers);

      const reached = await driveToJackpotPhase(game, deployer, mockVRF, advanceModule);
      expect(reached).to.equal(true);
      expect(await game.jackpotDuration()).to.equal(3);

      // Drive through standard jackpot phase to completion
      await countJackpotPhaseDays(game, deployer, mockVRF, advanceModule);

      const poolAfter = await game.currentPrizePoolView();
      expect(poolAfter).to.equal(0n, "Prize pool should drain to zero after standard");
    });
  });

  // ---------------------------------------------------------------------------
  // Standard mode (3 days) — jackpot phase duration
  // ---------------------------------------------------------------------------

  describe("standard mode (3 days)", function () {
    it("standard jackpot takes 3 physical days (2 remaining after transition)", async function () {
      const { game, deployer, mockVRF, advanceModule, alice, bob, carol, dan, eve, others } =
        await loadFixture(deployFullProtocol);

      // Warm-up: consume day 2 so purchaseDays > 1 on next advance
      await warmUpDay(game, deployer, mockVRF, advanceModule, alice);

      // Heavy purchases → driveToJackpotPhase → day 3 → standard (3 days)
      const buyers = [bob, carol, dan, eve, ...others.slice(0, 15)];
      await heavyPurchases(game, buyers);

      const reached = await driveToJackpotPhase(
        game,
        deployer,
        mockVRF,
        advanceModule
      );
      expect(reached).to.equal(true);
      expect(await game.jackpotDuration()).to.equal(3);

      // driveToJackpotPhase already consumed jackpot day 1 (counter 0→1).
      // Remaining: day 2 (counter 1→2) + day 3 (counter 2→3, _endPhase folds
      //           housekeeping into same day, jackpotPhase becomes false) = 2 cycles.
      const remainingDays = await countJackpotPhaseDays(
        game,
        deployer,
        mockVRF,
        advanceModule
      );

      // Total physical jackpot days: 1 (in driveToJackpotPhase) + remainingDays = 3
      expect(remainingDays).to.equal(2, "Standard phase should have 2 remaining cycles after transition");
    });

    it("standard duration returns to 3 days after jackpot phase ends", async function () {
      const { game, deployer, mockVRF, advanceModule, alice, bob, carol, dan, eve, others } =
        await loadFixture(deployFullProtocol);

      // Warm-up to avoid turbo
      await warmUpDay(game, deployer, mockVRF, advanceModule, alice);

      // Trigger standard jackpot
      const buyers = [bob, carol, dan, eve, ...others.slice(0, 15)];
      await heavyPurchases(game, buyers);

      const reached = await driveToJackpotPhase(
        game,
        deployer,
        mockVRF,
        advanceModule
      );
      expect(reached).to.equal(true);
      expect(await game.jackpotDuration()).to.equal(3);

      // Drive through jackpot phase to completion
      await countJackpotPhaseDays(game, deployer, mockVRF, advanceModule);

      // After phase ends, duration should be 3 days
      expect(await game.jackpotPhase()).to.equal(false);
      expect(await game.jackpotDuration()).to.equal(3);
    });

    it("standard jackpot drains currentPrizePool to zero by final day", async function () {
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
      expect(await game.jackpotDuration()).to.equal(3);

      // Record pool before jackpot phase payouts
      const poolBefore = await game.currentPrizePoolView();
      expect(poolBefore).to.be.gt(0n, "Prize pool should be non-zero at jackpot phase start");

      // Drive through standard jackpot phase
      await countJackpotPhaseDays(game, deployer, mockVRF, advanceModule);

      // After phase ends, current prize pool should be drained
      const poolAfter = await game.currentPrizePoolView();
      expect(poolAfter).to.equal(0n, "Prize pool should be zero after jackpot phase completes");
    });
  });

  // ---------------------------------------------------------------------------
  // Purchase duration never selects a five-day jackpot
  // ---------------------------------------------------------------------------

  describe("three-day schedule across purchase durations", function () {
    for (const purchaseDays of [3, 4, 30]) {
      it(`target met on purchase day ${purchaseDays} still takes exactly 3 jackpot days`, async function () {
        const { game, deployer, mockVRF, advanceModule, alice, bob, carol, dan, eve, others } =
          await loadFixture(deployFullProtocol);

        // Keep the pool below target through the requested purchase duration.
        for (let day = 1; day < purchaseDays; day++) {
          await buyFullTickets(game, alice, 10, 0.1);
          await driveOneCycle(game, deployer, mockVRF, advanceModule, BigInt(day * 1000));
          expect(await game.jackpotPhase()).to.equal(false);
          expect(await game.level()).to.equal(0n);
        }
        await heavyPurchases(game, [bob, carol, dan, eve, ...others.slice(0, 15)]);

        // The target-met settlement must select tier 1 even after the old cutoff.
        await driveOneCycle(game, deployer, mockVRF, advanceModule, 41n);
        expect((await game.purchaseInfo()).lastPurchaseDay_).to.equal(true);
        expect(await game.jackpotDuration()).to.equal(3);

        const reached = await driveToJackpotPhase(game, deployer, mockVRF, advanceModule);
        expect(reached).to.equal(true);
        expect(await game.jackpotDuration()).to.equal(3);
        expect(await game.currentPrizePoolView()).to.be.gt(0n);

        // Entry already paid day one (counter 0→1); two days remain (1→2→3).
        const remainingDays = await countJackpotPhaseDays(game, deployer, mockVRF, advanceModule);
        expect(remainingDays).to.equal(2, "Exactly three physical jackpot days including entry");
        expect(await game.currentPrizePoolView()).to.equal(0n);
        expect(await game.jackpotPhase()).to.equal(false);
        expect(await game.jackpotDuration()).to.equal(3);
      });
    }
  });

  // ---------------------------------------------------------------------------
  // Turbo mode (1 day) — 1 day per level
  // ---------------------------------------------------------------------------

  describe("turbo mode (1 day)", function () {
    /**
     * Run same-day advance cycles until the game exits jackpot phase or level
     * advances. Does NOT call advanceToNextDay between cycles — every call
     * lands on the same physical day. Returns the number of same-day cycles
     * required to transition back to the next purchase phase.
     */
    async function drainTurboSameDay(game, deployer, mockVRF, advanceModule, word) {
      let cycles = 0;
      for (let i = 0; i < 40; i++) {
        await driveOneCycleSameDay(game, deployer, mockVRF, advanceModule, word + BigInt(i));
        cycles++;
        if (!(await game.jackpotPhase())) return cycles;
      }
      return cycles;
    }

    it("turbo completes an entire level within a single physical day", async function () {
      const { game, deployer, mockVRF, advanceModule, alice, bob, carol, dan, eve, others } =
        await loadFixture(deployFullProtocol);

      const buyers = [alice, bob, carol, dan, eve, ...others.slice(0, 15)];
      await heavyPurchases(game, buyers);

      const levelBefore = await game.level();

      // Single advanceToNextDay → day 2, purchaseDays=1 → turbo path eligible.
      await advanceToNextDay();
      const tsBefore = await getBlockTimestamp();
      await drainTurboSameDay(game, deployer, mockVRF, advanceModule, 42n);
      const tsAfter = await getBlockTimestamp();

      // Level advanced, phase is back to purchase — all within one day. The
      // turbo flag survives phase end as the coinflip bonus-day latch (the
      // collapsed phase never spans a flip settlement, so the bonus shifts to
      // the next level's first purchase day).
      expect(await game.level()).to.equal(levelBefore + 1n, "Level should advance by 1");
      expect(await game.jackpotPhase()).to.equal(false, "Should be back in purchase phase");
      expect(await game.jackpotDuration()).to.equal(3);
      expect((BigInt(await game.extsload(ZERO_BYTES32)) >> 184n) & 2n).to.equal(2n, "Turbo bonus remains owed");

      // Drain completed without any day-boundary crossing (timestamp stayed within 24h window).
      expect(tsAfter - tsBefore).to.be.lessThan(86400,
        "Turbo drain should complete within a single physical day (no day rollover)");

      // The next (normal) purchase day's settlement consumes the latch.
      await advanceToNextDay();
      await driveOneCycleSameDay(game, deployer, mockVRF, advanceModule, 4242n);
      expect(await game.jackpotDuration()).to.equal(3,
        "Latch consumed by the next purchase day's settlement");
    });

    it("two consecutive turbo levels complete in 2 physical days (1 day per level)", async function () {
      const { game, deployer, mockVRF, advanceModule, alice, bob, carol, dan, eve, others } =
        await loadFixture(deployFullProtocol);

      const buyers = [alice, bob, carol, dan, eve, ...others.slice(0, 15)];
      await heavyPurchases(game, buyers);

      const levelBefore = await game.level();

      // Level 1 turbo (day 2, purchaseDays=1)
      await advanceToNextDay();
      await drainTurboSameDay(game, deployer, mockVRF, advanceModule, 42n);
      expect(await game.level()).to.equal(levelBefore + 1n);
      // Bonus-day latch armed; the next day is itself a last-purchase (turbo)
      // day, so the latch defers rather than consuming.
      expect(await game.jackpotDuration()).to.equal(3);

      // Fund the next level's pool so the target is already met when the
      // next purchase phase's first advance runs.
      await heavyPurchases(game, buyers);

      // Level 2 turbo: next physical day, purchaseDays=1 again since
      // purchaseStartDay was set to the previous turbo day.
      await advanceToNextDay();
      await drainTurboSameDay(game, deployer, mockVRF, advanceModule, 777n);

      expect(await game.level()).to.equal(levelBefore + 2n, "Second level should also advance");
      expect(await game.jackpotPhase()).to.equal(false);
      // Chain latch still armed after the second collapse; the first normal
      // purchase day settles and consumes it.
      expect(await game.jackpotDuration()).to.equal(3);

      await advanceToNextDay();
      await driveOneCycleSameDay(game, deployer, mockVRF, advanceModule, 7777n);
      expect(await game.jackpotDuration()).to.equal(3,
        "Deferred chain latch consumed on the first normal purchase day");
    });
  });
});
