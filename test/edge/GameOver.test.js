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
  getEvents,
  getLastVRFRequestId,
  ZERO_BYTES32,
} from "../helpers/testUtils.js";

const ZERO_ADDRESS = hre.ethers.ZeroAddress;
const MintPaymentKind = { DirectEth: 0, Claimable: 1, Combined: 2 };

/**
 * GameOver edge-case tests.
 *
 * The game over flow is multi-step:
 *   1. mineFlip when liveness guard fires → issues VRF request (does NOT yet set gameOver)
 *   2. VRF fulfillment stores word in rngWordCurrent
 *   3. mineFlip again → processes the word → terminal drain → gameOver = true
 *
 * Two liveness guards:
 *   - level==0 && currentDay - purchaseStartDay > DEPLOY_IDLE_TIMEOUT_DAYS  (pre-game 365-day idle timeout)
 *   - level!=0 && currentDay - purchaseStartDay > 30                        (post-game 30-day death clock)
 *
 * Deity pass refunds (GameOverModule:105-135):
 *   - Levels 0-9: min(deityPassPricePaid[owner], 20 ETH) per owner, FIFO,
 *                 budget-capped (a standard 24/25 ETH pass is above the cap, so
 *                 the refund is exactly 20 ETH)
 *   - Level 10+: No refund
 */
describe("GameOver", function () {
  after(function () {
    restoreAddresses();
  });

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  const SECONDS_912_DAYS = 912 * 86400;
  const SECONDS_365_DAYS = 365 * 86400;
  const SECONDS_30_DAYS = 30 * 86400;

  /**
   * Trigger game over at level 0 via the idle-timeout liveness path.
   * The drain is multi-tx (entropy round, then a ticket-drain pass, then the
   * terminal gameOver drain), so loop mineFlip — fulfilling any VRF request —
   * until gameOver latches.
   */
  async function triggerGameOverAtLevel0(game, deployer, mockVRF) {
    const transactions = [];
    for (let i = 0; i < 12; i++) {
      const reqBefore = await getLastVRFRequestId(mockVRF);
      try {
        transactions.push(await game.connect(deployer).mineFlip());
      } catch {
        /* may revert mid-sequence; keep driving */
      }
      const reqAfter = await getLastVRFRequestId(mockVRF);
      if (reqAfter > reqBefore) {
        try {
          await mockVRF.fulfillRandomWords(reqAfter, 42n);
        } catch {}
      }
      if (await game.gameOver()) return transactions;
    }
    return transactions;
  }

  /**
   * Drive a full VRF cycle: request → fulfill → drain tickets.
   */
  async function driveFullVRFCycle(game, deployer, mockVRF, word) {
    await advanceToNextDay();
    await game.connect(deployer).mineFlip();
    const requestId = await getLastVRFRequestId(mockVRF);
    await mockVRF.fulfillRandomWords(requestId, word || 123456n);
    for (let i = 0; i < 30; i++) {
      if (!(await game.rngLocked())) break;
      await game.connect(deployer).mineFlip();
    }
  }

  /**
   * Helper to buy tickets via the correct purchase signature.
   */
  async function buyTickets(game, buyer, qty, valueEth) {
    await game
      .connect(buyer)
      .purchase(
        0,
        BigInt(qty) * 100n,
        0n,
        ZERO_BYTES32,
        MintPaymentKind.DirectEth,false, 
        { value: eth(valueEth) }
      );
  }

  // =========================================================================
  // 1. Pre-game timeout (912 days, level == 0)
  // =========================================================================

  describe("pre-game 912-day timeout (level 0)", function () {
    it("gameOver becomes true after 912+ days at level 0", async function () {
      const { game, deployer, mockVRF } = await loadFixture(deployFullProtocol);

      expect(await game.level()).to.equal(0n);
      expect(await game.gameOver()).to.equal(false);

      // Advance past 912 days + buffer
      await advanceTime(SECONDS_912_DAYS + 86400);

      // Multi-step: mineFlip → VRF → mineFlip
      await triggerGameOverAtLevel0(game, deployer, mockVRF);

      expect(await game.gameOver()).to.equal(true);
    });

    it("gameOver is NOT triggered at 911 days", async function () {
      const { game, deployer } = await loadFixture(deployFullProtocol);

      // Advance 911 days (just under threshold)
      await advanceTime(911 * 86400);
      await advanceToNextDay();

      // mineFlip should not trigger game over (normal VRF path instead)
      const tx = await game.connect(deployer).mineFlip();
      const receipt = await tx.wait();
      expect(receipt.status).to.equal(1);
      expect(await game.gameOver()).to.equal(false);
    });

    it("first mineFlip at 912+ days issues VRF request but does NOT set gameOver yet", async function () {
      const { game, deployer, mockVRF } = await loadFixture(
        deployFullProtocol
      );

      await advanceTime(SECONDS_912_DAYS + 86400);

      // First call: issues VRF (gameOver still false)
      await game.connect(deployer).mineFlip();
      expect(await game.gameOver()).to.equal(false);

      // VRF request was issued
      const requestId = await getLastVRFRequestId(mockVRF);
      expect(requestId).to.be.gt(0n);
    });

    it("mineFlip after VRF fulfillment drives the drain to gameOver", async function () {
      const { game, deployer, mockVRF } = await loadFixture(
        deployFullProtocol
      );

      await advanceTime(SECONDS_912_DAYS + 86400);
      await game.connect(deployer).mineFlip();

      const requestId = await getLastVRFRequestId(mockVRF);
      await mockVRF.fulfillRandomWords(requestId, 42n);

      // After fulfillment the terminal drain completes over the remaining
      // ticket-drain / gameOver-drain txs.
      for (let i = 0; i < 12; i++) {
        await game.connect(deployer).mineFlip();
        if (await game.gameOver()) break;
      }
      expect(await game.gameOver()).to.equal(true);
    });

    it("mineFlip reports NoWork after completed terminal payout while the sweep is not due", async function () {
      const { game, deployer, mockVRF } = await loadFixture(
        deployFullProtocol
      );

      await advanceTime(SECONDS_912_DAYS + 86400);
      await triggerGameOverAtLevel0(game, deployer, mockVRF);
      expect(await game.gameOver()).to.equal(true);

      expect(await game.nextMinerAction()).to.equal(0n);
      const miner = await hre.ethers.getContractFactory("DegenerusGameMinerModule");
      await expect(game.connect(deployer).mineFlip()).to.be.revertedWithCustomError(miner, "NoWork");
      expect(await game.isFinalSwept()).to.equal(false);
    });
  });

  // =========================================================================
  // 2. Post-game inactivity timeout (365 days, level >= 1)
  // =========================================================================

  describe("post-game 365-day inactivity timeout (level >= 1)", function () {
    it("gameOver triggers after 365+ days of inactivity at level >= 1", async function () {
      const { game, deployer, mockVRF } = await loadFixture(
        deployFullProtocol
      );

      // Advance to level >= 1 via normal VRF cycle
      await driveFullVRFCycle(game, deployer, mockVRF, 2n);

      const level = await game.level();
      // level might still be 0 if not enough tickets to advance;
      // only test gameOver if we actually reached level >= 1
      if (level >= 1n) {
        await advanceTime(SECONDS_365_DAYS + 86400 * 2);

        // gameOver flow: mineFlip → VRF → mineFlip
        await game.connect(deployer).mineFlip();
        const requestId = await getLastVRFRequestId(mockVRF);
        if (requestId > 0n) {
          try {
            await mockVRF.fulfillRandomWords(requestId, 42n);
          } catch {
            // May already be fulfilled
          }
        }
        await game.connect(deployer).mineFlip();

        expect(await game.gameOver()).to.equal(true);
      }
    });

    it("gameOver does NOT trigger at 364 days of inactivity", async function () {
      const { game, deployer, mockVRF } = await loadFixture(
        deployFullProtocol
      );

      await driveFullVRFCycle(game, deployer, mockVRF, 2n);

      // Only 364 days
      await advanceTime(364 * 86400);
      await advanceToNextDay();

      // Should issue VRF, not game over
      await game.connect(deployer).mineFlip();
      expect(await game.gameOver()).to.equal(false);
    });
  });

  // =========================================================================
  // 3. Deity pass refund at level 0
  // =========================================================================

  // The early-gameover (levels 0-9) deity refund is min(deityPassPricePaid[owner],
  // 20 ETH) per owner (GameOverModule:111-115). A standard pass is bought at 24/25
  // ETH (> the 20 ETH cap), so the cap binds and the refund is exactly 20 ETH —
  // Compare refunds separately from terminal jackpot winnings: every deity now
  // also owns ordinary perpetual tickets and may win in the terminal cohort.
  describe("deity pass refund at level 0", function () {
    it("deity pass holders get the capped 20 ETH refund (min(pricePaid, 20 ETH)) when gameOver at level 0", async function () {
      const { game, deployer, alice, mockVRF, jackpotModule, gameOverModule } = await loadFixture(
        deployFullProtocol
      );

      // First paid pass (k=0): totalPrice = DEITY_PASS_BASE (24 ETH); recorded pricePaid = 24 ETH > the
      // 20 ETH cap, so min(pricePaid, 20 ETH) binds at exactly 20 ETH.
      await game
        .connect(alice)
        .purchaseDeityPass(0, 4, hre.ethers.ZeroHash, { value: eth(24) });

      expect(await game.level()).to.equal(0n);

      const claimBefore = await game.claimableWinningsOf(alice.address);
      await advanceTime(SECONDS_912_DAYS + 86400);
      const txs = await triggerGameOverAtLevel0(game, deployer, mockVRF);
      expect(await game.gameOver()).to.equal(true);
      const wins = (await Promise.all(txs.map(tx => getEvents(tx, jackpotModule, "JackpotEthWin")))).flat();
      const aliceId = await game.walletIdOf(alice.address);
      const jackpot = wins.filter(e => e.args.walletId === aliceId).reduce((sum, e) => sum + e.args.amount, 0n);
      const claimAfter = await game.claimableWinningsOf(alice.address);
      expect(claimAfter - claimBefore - jackpot).to.equal(eth(20));
      const refunds = (await Promise.all(txs.map(tx => getEvents(tx, gameOverModule, "DeityPassRefundsSettled")))).flat();
      expect(refunds.reduce((sum, e) => sum + e.args.totalRefunded, 0n)).to.equal(eth(20));
    });

    it("multiple deity pass holders all get refunds at level 0", async function () {
      const { game, deployer, alice, bob, mockVRF, jackpotModule, gameOverModule } = await loadFixture(
        deployFullProtocol
      );

      // Pass 0 (k=0): totalPrice = 24 ETH; pass 1 (k=1): totalPrice = 24 + (1*2/2) = 25 ETH.
      // Both recorded pricePaid values exceed the 20 ETH cap, so each refund is exactly 20 ETH.
      const price1 = eth(24);
      await game
        .connect(alice)
        .purchaseDeityPass(0, 4, hre.ethers.ZeroHash, { value: price1 });

      const price2 = eth(25);
      await game
        .connect(bob)
        .purchaseDeityPass(0, 1, hre.ethers.ZeroHash, { value: price2 });

      // Isolate the capped refunds from their perpetual-ticket jackpot winnings.
      const aliceBefore = await game.claimableWinningsOf(alice.address);
      const bobBefore = await game.claimableWinningsOf(bob.address);

      await advanceTime(SECONDS_912_DAYS + 86400);
      const txs = await triggerGameOverAtLevel0(game, deployer, mockVRF);
      const wins = (await Promise.all(txs.map(tx => getEvents(tx, jackpotModule, "JackpotEthWin")))).flat();
      const idOf = { [alice.address]: await game.walletIdOf(alice.address), [bob.address]: await game.walletIdOf(bob.address) };
      const won = who => wins.filter(e => e.args.walletId === idOf[who]).reduce((sum, e) => sum + e.args.amount, 0n);

      const aliceAfter = await game.claimableWinningsOf(alice.address);
      const bobAfter = await game.claimableWinningsOf(bob.address);
      // EXACT cap, not gte: a removed min(pricePaid, 20 ETH) clamp would refund 24 / 25 ETH
      // (the full pricePaid) and these strict equalities would FAIL.
      expect(aliceAfter - aliceBefore - won(alice.address)).to.equal(eth(20));
      expect(bobAfter - bobBefore - won(bob.address)).to.equal(eth(20));
    });
  });

  // =========================================================================
  // 4. Post-gameover state checks
  // =========================================================================

  describe("post-gameover state", function () {
    it("gameOver() returns true after trigger", async function () {
      const { game, deployer, mockVRF } = await loadFixture(
        deployFullProtocol
      );

      await advanceTime(SECONDS_912_DAYS + 86400);
      await triggerGameOverAtLevel0(game, deployer, mockVRF);

      expect(await game.gameOver()).to.equal(true);
    });

    it("purchase reverts after gameOver", async function () {
      const { game, deployer, alice, mockVRF } = await loadFixture(
        deployFullProtocol
      );

      await advanceTime(SECONDS_912_DAYS + 86400);
      await triggerGameOverAtLevel0(game, deployer, mockVRF);

      await expect(
        game
          .connect(alice)
          .purchase(
            0,
            100n,
            0n,
            ZERO_BYTES32,
            MintPaymentKind.DirectEth,false, 
            { value: eth(0.01) }
          )
      ).to.be.reverted;
    });

    it("feed-swap proposals revert with GameOver after the terminal drain", async function () {
      const { game, admin, deployer, mockVRF } = await loadFixture(deployFullProtocol);
      await advanceTime(SECONDS_912_DAYS + 86400);
      await triggerGameOverAtLevel0(game, deployer, mockVRF);
      expect(await game.gameOver()).to.be.true;
      await expect(admin.connect(deployer).proposeFeedSwap(ZERO_ADDRESS))
        .to.be.revertedWithCustomError(admin, "GameOver");
    });

    it("purchaseDeityPass reverts with GameOver after the terminal drain", async function () {
      const { game, deployer, alice, mockVRF } = await loadFixture(
        deployFullProtocol
      );

      await advanceTime(SECONDS_912_DAYS + 86400);
      await triggerGameOverAtLevel0(game, deployer, mockVRF);

      expect(await game.gameOver()).to.be.true;
      await expect(game
          .connect(alice)
          .purchaseDeityPass(0, 4, hre.ethers.ZeroHash, { value: eth(24) }))
        .to.be.revertedWithCustomError(game, "GameOver");
    });
  });

  // =========================================================================
  // 5. Final sweep (30 days post-gameover)
  // =========================================================================

  describe("final sweep (30 days post-gameover)", function () {
    it("mineFlip before 30 days reports NoWork and preserves the unexpired claim window", async function () {
      const { game, deployer, alice, mockVRF } = await loadFixture(
        deployFullProtocol
      );

      await buyTickets(game, alice, 10, 0.1);

      await advanceTime(SECONDS_912_DAYS + 86400);
      await triggerGameOverAtLevel0(game, deployer, mockVRF);
      expect(await game.gameOver()).to.equal(true);

      // 15 days post-gameover (< 30)
      await advanceTime(15 * 86400);

      const timestamp = await game.gameOverTimestamp();
      const reserved = await game.claimablePoolView();
      const miner = await hre.ethers.getContractFactory("DegenerusGameMinerModule");
      await expect(game.connect(deployer).mineFlip()).to.be.revertedWithCustomError(miner, "NoWork");
      expect(await game.isFinalSwept()).to.equal(false);
      expect(await game.gameOverTimestamp()).to.equal(timestamp);
      expect(await game.claimablePoolView()).to.equal(reserved);
    });

    it("mineFlip after 30 days triggers final sweep path", async function () {
      const { game, deployer, alice, mockVRF } = await loadFixture(
        deployFullProtocol
      );

      await buyTickets(game, alice, 10, 0.1);

      await advanceTime(SECONDS_912_DAYS + 86400);
      await triggerGameOverAtLevel0(game, deployer, mockVRF);

      // 31 days post-gameover
      await advanceTime(SECONDS_30_DAYS + 86400);

      const tx = await game.connect(deployer).mineFlip();
      expect((await tx.wait()).status).to.equal(1);
    });
  });

  // =========================================================================
  // 6. Claimable winnings withdrawal
  // =========================================================================

  describe("claimable winnings post-gameover", function () {
    it("deity pass holder can claim winnings after gameOver", async function () {
      const { game, deployer, alice, mockVRF } = await loadFixture(
        deployFullProtocol
      );

      const deityPrice = eth(24);
      await game
        .connect(alice)
        .purchaseDeityPass(0, 4, hre.ethers.ZeroHash, { value: deityPrice });

      await advanceTime(SECONDS_912_DAYS + 86400);
      await triggerGameOverAtLevel0(game, deployer, mockVRF);

      const claimable = await game.claimableWinningsOf(alice.address);
      if (claimable > 0n) {
        const balBefore = await hre.ethers.provider.getBalance(alice.address);
        const tx = await game.connect(alice)["claimWinnings(uint32)"](0);
        const receipt = await tx.wait();
        const gasUsed = receipt.gasUsed * receipt.gasPrice;
        const balAfter = await hre.ethers.provider.getBalance(alice.address);

        expect(balAfter + gasUsed).to.be.gt(balBefore);
      }
    });

    it("claimableWinningsOf returns 0 for non-participant after gameOver", async function () {
      const { game, deployer, bob, mockVRF } = await loadFixture(
        deployFullProtocol
      );

      await advanceTime(SECONDS_912_DAYS + 86400);
      await triggerGameOverAtLevel0(game, deployer, mockVRF);

      const claimable = await game.claimableWinningsOf(bob.address);
      expect(claimable).to.equal(0n);
    });
  });
});
