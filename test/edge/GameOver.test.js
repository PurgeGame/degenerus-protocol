import { ownerAction } from "../helpers/deployFixture.js";
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
  errorAbi,
} from "../helpers/testUtils.js";

const ZERO_ADDRESS = hre.ethers.ZeroAddress;
const MintPaymentKind = { DirectEth: 0, Claimable: 1, Combined: 2 };

/** Terminal entry uses thirty completed purchase rounds or fourteen real days
 * without a daily completion. The hard escape does not request another word. */
describe("GameOver", function () {
  after(function () {
    restoreAddresses();
  });

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  const SECONDS_HARD_STALL = 14 * 86400;
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
        transactions.push(await game.connect(deployer).mineFlip(0, { gasLimit: 16_777_216 }));
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
  // 1. Hard progress timeout at level 0
  // =========================================================================

  describe("fourteen-day progress timeout (level 0)", function () {
    it("gameOver becomes true after fourteen days at level 0", async function () {
      const { game, deployer, mockVRF } = await loadFixture(deployFullProtocol);

      expect(await game.level()).to.equal(0n);
      expect(await game.gameOver()).to.equal(false);

      // Expire the real daily-progress clock.
      await advanceTime(SECONDS_HARD_STALL + 86400);

      // Multi-step: mineFlip → VRF → mineFlip
      await triggerGameOverAtLevel0(game, deployer, mockVRF);

      expect(await game.gameOver()).to.equal(true);
    });

    it("gameOver is NOT triggered before fourteen days", async function () {
      const { game, deployer } = await loadFixture(deployFullProtocol);

      // Stay below the fourteen-day hard deadline.
      await advanceTime(12 * 86400);
      await advanceToNextDay();

      // mineFlip should not trigger game over (normal VRF path instead)
      const tx = await game.connect(deployer).mineFlip(0, { gasLimit: 16_777_216 });
      const receipt = await tx.wait();
      expect(receipt.status).to.equal(1);
      expect(await game.gameOver()).to.equal(false);
    });

    it("hard-stall entry ends without an additional VRF request", async function () {
      const { game, deployer, mockVRF } = await loadFixture(deployFullProtocol);
      await advanceTime(SECONDS_HARD_STALL + 1);
      const before = await getLastVRFRequestId(mockVRF);
      await triggerGameOverAtLevel0(game, deployer, mockVRF);
      expect(await game.gameOver()).to.equal(true);
      expect(await getLastVRFRequestId(mockVRF)).to.equal(before);
    });

    it("mineFlip reports NoWork after completed terminal payout while the sweep is not due", async function () {
      const { game, deployer, mockVRF } = await loadFixture(
        deployFullProtocol
      );

      await advanceTime(SECONDS_HARD_STALL + 86400);
      await triggerGameOverAtLevel0(game, deployer, mockVRF);
      expect(await game.gameOver()).to.equal(true);

      expect(await game.nextMinerAction()).to.equal(0n);
      const miner = await hre.ethers.getContractFactory("DegenerusGame");
      await expect(game.connect(deployer).mineFlip(0, { gasLimit: 16_777_216 })).to.be.revertedWithCustomError(miner, "NoWork");
      expect(await game.isFinalSwept()).to.equal(false);
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
      await advanceTime(SECONDS_HARD_STALL + 86400);
      const txs = await triggerGameOverAtLevel0(game, deployer, mockVRF);
      expect(await game.gameOver()).to.equal(true);
      const wins = (await Promise.all(txs.map(tx => getEvents(tx, jackpotModule, "JackpotEthWin")))).flat();
      const aliceId = await game.walletIdOf_g3120(alice.address);
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

      await advanceTime(SECONDS_HARD_STALL + 86400);
      const txs = await triggerGameOverAtLevel0(game, deployer, mockVRF);
      const wins = (await Promise.all(txs.map(tx => getEvents(tx, jackpotModule, "JackpotEthWin")))).flat();
      const idOf = { [alice.address]: await game.walletIdOf_g3120(alice.address), [bob.address]: await game.walletIdOf_g3120(bob.address) };
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

      await advanceTime(SECONDS_HARD_STALL + 86400);
      await triggerGameOverAtLevel0(game, deployer, mockVRF);

      expect(await game.gameOver()).to.equal(true);
    });

    it("purchase reverts after gameOver", async function () {
      const { game, deployer, alice, mockVRF } = await loadFixture(
        deployFullProtocol
      );

      await advanceTime(SECONDS_HARD_STALL + 86400);
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
      ).to.be.revertedWithCustomError(errorAbi("E()"), "E");
    });

    it("feed-swap proposals revert with GameOver after the terminal drain", async function () {
      const { game, admin, deployer, mockVRF } = await loadFixture(deployFullProtocol);
      await advanceTime(SECONDS_HARD_STALL + 86400);
      await triggerGameOverAtLevel0(game, deployer, mockVRF);
      expect(await game.gameOver()).to.be.true;
      await expect(ownerAction(admin.connect(deployer), "proposeFeedSwap", [ZERO_ADDRESS]))
        .to.be.revertedWithCustomError(admin, "GameOver");
    });

    it("purchaseDeityPass reverts with GameOver after the terminal drain", async function () {
      const { game, deployer, alice, mockVRF } = await loadFixture(
        deployFullProtocol
      );

      await advanceTime(SECONDS_HARD_STALL + 86400);
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

      await advanceTime(SECONDS_HARD_STALL + 86400);
      await triggerGameOverAtLevel0(game, deployer, mockVRF);
      expect(await game.gameOver()).to.equal(true);

      // 15 days post-gameover (< 30)
      await advanceTime(15 * 86400);

      const timestamp = await game.gameOverTimestamp();
      const reserved = await game.claimablePoolView();
      const miner = await hre.ethers.getContractFactory("DegenerusGame");
      await expect(game.connect(deployer).mineFlip(0, { gasLimit: 16_777_216 })).to.be.revertedWithCustomError(miner, "NoWork");
      expect(await game.isFinalSwept()).to.equal(false);
      expect(await game.gameOverTimestamp()).to.equal(timestamp);
      expect(await game.claimablePoolView()).to.equal(reserved);
    });

    it("mineFlip after 30 days triggers final sweep path", async function () {
      const { game, deployer, alice, mockVRF } = await loadFixture(
        deployFullProtocol
      );

      await buyTickets(game, alice, 10, 0.1);

      await advanceTime(SECONDS_HARD_STALL + 86400);
      await triggerGameOverAtLevel0(game, deployer, mockVRF);

      // 31 days post-gameover
      await advanceTime(SECONDS_30_DAYS + 86400);

      const tx = await game.connect(deployer).mineFlip(0, { gasLimit: 16_777_216 });
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

      await advanceTime(SECONDS_HARD_STALL + 86400);
      await triggerGameOverAtLevel0(game, deployer, mockVRF);

      expect(await game.gameOver()).to.equal(true);
      // A level-0 ending refunds the deity pass (capped at 20 ETH), so there is always
      // something to claim here.
      const claimable = await game.claimableWinningsOf(alice.address);
      expect(claimable).to.be.gte(eth(20));

      const balBefore = await hre.ethers.provider.getBalance(alice.address);
      const tx = await game.connect(alice)["claimWinnings(uint32)"](0);
      const receipt = await tx.wait();
      const gasUsed = receipt.gasUsed * receipt.gasPrice;
      const balAfter = await hre.ethers.provider.getBalance(alice.address);

      expect(balAfter + gasUsed - balBefore).to.be.gte(eth(20), "the refund was paid out");
      expect(await game.claimableWinningsOf(alice.address)).to.equal(1n, "only the 1-wei sentinel stays behind");
    });

    it("claimableWinningsOf returns 0 for non-participant after gameOver", async function () {
      const { game, deployer, bob, mockVRF } = await loadFixture(
        deployFullProtocol
      );

      await advanceTime(SECONDS_HARD_STALL + 86400);
      await triggerGameOverAtLevel0(game, deployer, mockVRF);

      const claimable = await game.claimableWinningsOf(bob.address);
      expect(claimable).to.equal(0n);
    });
  });
});
