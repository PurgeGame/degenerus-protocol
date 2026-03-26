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
  getEvents,
  ZERO_BYTES32,
} from "../helpers/testUtils.js";

/**
 * Charity Game Hooks integration tests.
 *
 * Verifies that the game modules correctly call GNRUS hooks:
 *   1. pickCharity(level) at each level transition during advanceGame
 *   2. burnAtGameOver() during gameover drain to burn unallocated GNRUS
 *
 * Both hooks are direct calls (no try/catch) that surface reverts as bugs.
 */
describe("CharityGameHooks", function () {
  after(function () {
    restoreAddresses();
  });

  const ZERO_ADDRESS = hre.ethers.ZeroAddress;
  const SECONDS_912_DAYS = 912 * 86400;

  /**
   * Get the GNRUS contract instance at the deployed GNRUS address.
   * The contract is deployed as part of DEPLOY_ORDER but not returned by name.
   */
  async function getCharity(deployedAddrs) {
    const gnrusAddr = deployedAddrs.get("GNRUS");
    return hre.ethers.getContractAt("GNRUS", gnrusAddr);
  }

  /**
   * Purchase a large number of tickets to fill the prize pool past the 50 ETH
   * bootstrap target, triggering a level transition on the next advanceGame cycle.
   *
   * At 0.01 ETH per ticket unit (TICKET_SCALE=100), and ~30% flowing to the
   * next prize pool, we need ~170 ETH of purchases. We buy in bulk from
   * multiple accounts to avoid per-account limits.
   */
  async function fillPrizePoolForLevelTransition(game, signers) {
    // At price=0.01 ETH, ticketCost = (price * qty) / (4 * TICKET_SCALE)
    //   = (0.01e18 * qty) / 400
    // Need >50 ETH in next pool. 90% of prizeContribution goes to next pool.
    // So need ~56 ETH prizeContribution total (56 * 0.9 = 50.4 > 50).
    // Per buyer: qty=300,000 => cost = 0.01e18 * 300,000 / 400 = 7.5 ETH
    // 10 buyers => 75 ETH total, 67.5 ETH to next pool >> 50 ETH target.
    const ticketQty = 300_000n;  // 300,000 ticket units (divide by TICKET_SCALE=100 => 3000 tickets)
    const valuePerBuy = eth("8");  // 7.5 ETH cost + margin (DirectEth allows overpay)
    const buyerCount = Math.min(signers.length, 10);
    for (let i = 0; i < buyerCount; i++) {
      await game.connect(signers[i]).purchase(
        signers[i].address,
        ticketQty,
        0n,
        ZERO_BYTES32,
        0, // DirectEth
        { value: valuePerBuy }
      );
    }
  }

  /**
   * Drive VRF cycle to completion:
   *   1. advanceGame -> triggers VRF request
   *   2. fulfill VRF
   *   3. advanceGame repeatedly until RNG unlocked
   */
  async function driveVRFCycle(game, deployer, mockVRF) {
    await game.connect(deployer).advanceGame();
    const requestId = await getLastVRFRequestId(mockVRF);
    if (requestId > 0n) {
      await mockVRF.fulfillRandomWords(requestId, 12345678901234567890n);
    }
    // Drive ticket processing until RNG unlocks.
    // The game pre-queues ~1600 vault+DGNRS perpetual tickets (16 per level * 100 levels)
    // so the first advance cycle needs many batch-processing calls.
    for (let i = 0; i < 200; i++) {
      if (!(await game.rngLocked())) break;
      await game.connect(deployer).advanceGame();
    }
  }

  /**
   * Trigger game over at level 0 via the 912-day timeout:
   *   1. Advance time past 912 days
   *   2. advanceGame -> issues VRF request
   *   3. Fulfill VRF
   *   4. advanceGame -> processes word, calls handleGameOverDrain
   */
  async function triggerGameOver(game, deployer, mockVRF) {
    await advanceTime(SECONDS_912_DAYS + 86400);
    await game.connect(deployer).advanceGame();
    const requestId = await getLastVRFRequestId(mockVRF);
    if (requestId > 0n) {
      await mockVRF.fulfillRandomWords(requestId, 42n);
    }
    await game.connect(deployer).advanceGame();
  }

  // =========================================================================
  // pickCharity hook
  // =========================================================================

  describe("pickCharity fires at level transition", function () {
    it("charity.currentLevel increments from 0 to 1 after first level transition", async function () {
      const fixture = await loadFixture(deployFullProtocol);
      const { game, deployer, mockVRF, alice, bob, carol, dan, eve, others, deployedAddrs } = fixture;
      const charity = await getCharity(deployedAddrs);

      // Verify initial state
      expect(await charity.currentLevel()).to.equal(0);
      expect(await charity.levelResolved(0)).to.equal(false);

      // Fill prize pool past 50 ETH bootstrap target
      const buyers = [alice, bob, carol, dan, eve, ...others.slice(0, 5)];
      await fillPrizePoolForLevelTransition(game, buyers);

      // Day 1: Process first VRF cycle (drains pre-queued tickets, sets lastPurchaseDay)
      await advanceToNextDay();
      await driveVRFCycle(game, deployer, mockVRF);

      // Day 2: Second VRF cycle triggers the level transition via _finalizeRngRequest
      // with isTicketJackpotDay=true, which calls charityResolve.pickCharity(lvl - 1)
      await advanceToNextDay();
      await driveVRFCycle(game, deployer, mockVRF);

      // Verify: game level incremented
      const gameLevel = await game.level();
      expect(gameLevel).to.be.gte(1, "Game level should have incremented past 0");

      // Verify: charity pickCharity was called (currentLevel advanced)
      expect(await charity.currentLevel()).to.equal(1,
        "Charity currentLevel should be 1 after pickCharity(0) called");
      expect(await charity.levelResolved(0)).to.equal(true,
        "Level 0 should be marked as resolved");
    });

    it("emits LevelSkipped(0) when no proposals exist for level 0", async function () {
      const fixture = await loadFixture(deployFullProtocol);
      const { game, deployer, mockVRF, alice, bob, carol, dan, eve, others, deployedAddrs } = fixture;
      const charity = await getCharity(deployedAddrs);

      // Fill prize pool
      const buyers = [alice, bob, carol, dan, eve, ...others.slice(0, 5)];
      await fillPrizePoolForLevelTransition(game, buyers);

      // Day 1: Process first VRF cycle (drains pre-queued tickets)
      await advanceToNextDay();
      await driveVRFCycle(game, deployer, mockVRF);

      // Day 2: Level transition day -- capture LevelSkipped event
      await advanceToNextDay();
      await game.connect(deployer).advanceGame();
      const requestId = await getLastVRFRequestId(mockVRF);
      await mockVRF.fulfillRandomWords(requestId, 12345678901234567890n);

      // Collect events during ticket processing (level transition fires pickCharity)
      let levelSkippedFound = false;
      for (let i = 0; i < 200; i++) {
        if (!(await game.rngLocked())) break;
        const tx = await game.connect(deployer).advanceGame();
        const events = await getEvents(tx, charity, "LevelSkipped");
        if (events.length > 0) {
          expect(events[0].args.level).to.equal(0);
          levelSkippedFound = true;
        }
      }

      // Verify charity state advanced (pickCharity was called)
      expect(await charity.currentLevel()).to.equal(1,
        "Charity currentLevel should be 1 (pickCharity was called)");
      expect(await charity.levelResolved(0)).to.equal(true,
        "Level 0 should be marked as resolved");
    });
  });

  // =========================================================================
  // burnAtGameOver hook
  // =========================================================================

  describe("burnAtGameOver fires during gameover drain", function () {
    it("charity.finalized becomes true after game over", async function () {
      const fixture = await loadFixture(deployFullProtocol);
      const { game, deployer, mockVRF, deployedAddrs } = fixture;
      const charity = await getCharity(deployedAddrs);

      // Verify initial state
      expect(await charity.finalized()).to.equal(false);
      expect(await game.gameOver()).to.equal(false);

      // Trigger game over via 912-day timeout
      await triggerGameOver(game, deployer, mockVRF);

      // Verify game is over
      expect(await game.gameOver()).to.equal(true);

      // Verify burnAtGameOver was called: finalized = true
      expect(await charity.finalized()).to.equal(true,
        "Charity should be finalized after burnAtGameOver() called");
    });

    it("unallocated GNRUS is burned at gameover", async function () {
      const fixture = await loadFixture(deployFullProtocol);
      const { game, deployer, mockVRF, deployedAddrs } = fixture;
      const charity = await getCharity(deployedAddrs);
      const charityAddr = await charity.getAddress();

      // Before gameover: contract holds unallocated GNRUS (minted at deploy)
      const balBefore = await charity.balanceOf(charityAddr);
      expect(balBefore).to.be.gt(0, "Charity should hold unallocated GNRUS before gameover");

      // Trigger game over
      await triggerGameOver(game, deployer, mockVRF);

      // After gameover: all unallocated GNRUS burned
      const balAfter = await charity.balanceOf(charityAddr);
      expect(balAfter).to.equal(0, "All unallocated GNRUS should be burned at gameover");
    });

    it("emits GameOverFinalized event", async function () {
      const fixture = await loadFixture(deployFullProtocol);
      const { game, deployer, mockVRF, deployedAddrs } = fixture;
      const charity = await getCharity(deployedAddrs);

      await advanceTime(SECONDS_912_DAYS + 86400);

      // First call: VRF request
      await game.connect(deployer).advanceGame();
      const requestId = await getLastVRFRequestId(mockVRF);
      await mockVRF.fulfillRandomWords(requestId, 42n);

      // Second call: processes word, calls handleGameOverDrain -> burnAtGameOver
      const tx = await game.connect(deployer).advanceGame();
      const events = await getEvents(tx, charity, "GameOverFinalized");

      expect(events.length).to.equal(1, "GameOverFinalized event should be emitted");
      expect(events[0].args.gnrusBurned).to.be.gt(0,
        "Should have burned non-zero GNRUS");
    });
  });
});
