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
 * Compressed Jackpot Phase Tests
 *
 * When a level's purchase-phase prize pool target is met within the first
 * 2 daily advances, the subsequent jackpot phase compresses from 5 days
 * to 3 days by combining payout pairs:
 *   - Compressed day 1: doubled BPS (12-28%) + early-bird
 *   - Compressed day 2: doubled BPS (12-28%) + carryover
 *   - Compressed day 3: 100% remaining (final day)
 *
 * The mechanism uses counterStep=2 for the first two compressed days
 * so the jackpotCounter advances 0→2→4→5 in 3 physical days.
 *
 * Day counting:
 *   purchaseStartDay defaults to 0 at level 0.
 *   GameTimeLib.currentDayIndexAt returns 1 on deploy day.
 *   The compressed check is: (day - purchaseStartDay <= 2).
 *   On deploy day (day 1): 1 - 0 = 1 ≤ 2 → compressed.
 *   After 1 advanceToNextDay (day 2): 2 - 0 = 2 ≤ 2 → compressed.
 *   After 2 advanceToNextDay (day 3): 3 - 0 = 3 > 2 → NOT compressed.
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

  // ---------------------------------------------------------------------------
  // Initial state
  // ---------------------------------------------------------------------------

  describe("initial state", function () {
    it("isCompressedJackpot is false on deploy", async function () {
      const { game } = await loadFixture(deployFullProtocol);
      expect(await game.isCompressedJackpot()).to.equal(false);
    });
  });

  // ---------------------------------------------------------------------------
  // Compressed flag set when target met within 2 days
  // ---------------------------------------------------------------------------

  describe("compressed flag activation", function () {
    it("flag is set when prize target met on first advance", async function () {
      const { game, deployer, mockVRF, advanceModule, alice, bob, carol, dan, eve, others } =
        await loadFixture(deployFullProtocol);

      // Heavy purchases to exceed 50 ETH target immediately
      const buyers = [alice, bob, carol, dan, eve, ...others.slice(0, 15)];
      await heavyPurchases(game, buyers);

      // First advance on deploy day (day 1): day - purchaseStartDay = 1 - 0 = 1 ≤ 2
      const reached = await driveToJackpotPhase(
        game,
        deployer,
        mockVRF,
        advanceModule
      );
      expect(reached).to.equal(true, "Should reach jackpot phase");
      expect(await game.isCompressedJackpot()).to.equal(true);
    });

    it("flag is set when prize target met on second advance", async function () {
      const { game, deployer, mockVRF, advanceModule, alice, bob, carol, dan, eve, others } =
        await loadFixture(deployFullProtocol);

      // Advance 1 (deploy day = day 1): small purchase, target NOT met
      await buyFullTickets(game, alice, 200, 2);
      await driveOneCycleSameDay(game, deployer, mockVRF, advanceModule, 100n);
      expect(await game.jackpotPhase()).to.equal(false, "Should still be in purchase phase");

      // Heavy purchases push past the target
      const buyers = [bob, carol, dan, eve, ...others.slice(0, 15)];
      await heavyPurchases(game, buyers);

      // Advance 2 (day 2): day - purchaseStartDay = 2 - 0 = 2 ≤ 2
      const reached = await driveToJackpotPhase(
        game,
        deployer,
        mockVRF,
        advanceModule
      );
      expect(reached).to.equal(true, "Should reach jackpot phase");
      expect(await game.isCompressedJackpot()).to.equal(true);
    });

    it("flag is NOT set when prize target met on third advance", async function () {
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

      // Advance 3 (day 3): day - purchaseStartDay = 3 - 0 = 3 > 2
      const reached = await driveToJackpotPhase(
        game,
        deployer,
        mockVRF,
        advanceModule
      );
      expect(reached).to.equal(true, "Should reach jackpot phase");
      expect(await game.isCompressedJackpot()).to.equal(false);
    });
  });

  // ---------------------------------------------------------------------------
  // Jackpot phase duration
  // ---------------------------------------------------------------------------

  describe("jackpot phase duration", function () {
    it("compressed jackpot phase completes in fewer remaining cycles than normal", async function () {
      const { game, deployer, mockVRF, advanceModule, alice, bob, carol, dan, eve, others } =
        await loadFixture(deployFullProtocol);

      // Heavy purchases to trigger compressed mode
      const buyers = [alice, bob, carol, dan, eve, ...others.slice(0, 15)];
      await heavyPurchases(game, buyers);

      const reached = await driveToJackpotPhase(
        game,
        deployer,
        mockVRF,
        advanceModule
      );
      expect(reached).to.equal(true);
      expect(await game.isCompressedJackpot()).to.equal(true);

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

    it("normal jackpot phase takes more cycles than compressed", async function () {
      const { game, deployer, mockVRF, advanceModule, alice, bob, carol, dan, eve, others } =
        await loadFixture(deployFullProtocol);

      // Spread purchases over 3+ advances to avoid compressed flag
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
      expect(await game.isCompressedJackpot()).to.equal(false);

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

  // ---------------------------------------------------------------------------
  // Flag reset
  // ---------------------------------------------------------------------------

  describe("flag lifecycle", function () {
    it("compressed flag resets to false after jackpot phase ends", async function () {
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
      expect(await game.isCompressedJackpot()).to.equal(true);

      // Drive through jackpot phase to completion
      await countJackpotPhaseDays(game, deployer, mockVRF, advanceModule);

      // After phase ends, flag should be false
      expect(await game.jackpotPhase()).to.equal(false);
      expect(await game.isCompressedJackpot()).to.equal(false);
    });
  });

  // ---------------------------------------------------------------------------
  // Prize pool drain verification
  // ---------------------------------------------------------------------------

  describe("prize pool economics", function () {
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
      expect(await game.isCompressedJackpot()).to.equal(true);

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
});
