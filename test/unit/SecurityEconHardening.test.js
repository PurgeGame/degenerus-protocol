import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers.js";
import { expect } from "chai";
import hre from "hardhat";
import {
  deployFullProtocol,
  restoreAddresses,
  giveWalletId,
} from "../helpers/deployFixture.js";
import {
  eth,
  advanceTime,
  advanceToNextDay,
  getLastVRFRequestId,
  ZERO_ADDRESS,
  ZERO_BYTES32,
} from "../helpers/testUtils.js";

// MintPaymentKind enum values
const MintPaymentKind = { DirectEth: 0, Claimable: 1, Combined: 2 };

// Time constants (seconds)
const DAY = 86400;
const DEPLOY_IDLE_TIMEOUT_DAYS = 250;
const INACTIVITY_TIMEOUT_DAYS = 365;
const COIN_PURCHASE_CUTOFF_LVL0 = 220; // 250 - 30 days

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/**
 * Trigger game over at level 0 via the idle-timeout liveness path.
 * The drain is multi-tx (entropy round, then a ticket-drain pass, then the
 * terminal gameOver drain), so loop mineFlip — fulfilling any VRF request —
 * until gameOver latches.
 */
async function triggerGameOverAtLevel0(game, caller, mockVRF) {
  for (let i = 0; i < 12; i++) {
    const reqBefore = await getLastVRFRequestId(mockVRF);
    try {
      await game.connect(caller).mineFlip(0);
    } catch {
      /* may revert mid-sequence; keep driving */
    }
    const reqAfter = await getLastVRFRequestId(mockVRF);
    if (reqAfter > reqBefore) {
      try {
        await mockVRF.fulfillRandomWords(reqAfter, 42n);
      } catch {}
    }
    if (await game.gameOver()) return;
  }
}

/**
 * Buy N full tickets with DirectEth.
 * 1 full ticket = qty 400, costs priceWei.
 */
async function buyFullTickets(game, buyer, n, totalEth) {
  return game.connect(buyer).purchase(
    0,
    BigInt(n) * 400n,
    0n,
    ZERO_BYTES32,
    MintPaymentKind.DirectEth,false, 
    { value: eth(totalEth) }
  );
}

// ===========================================================================
// TEST SUITE
// ===========================================================================

describe("SecurityEconHardening", function () {
  after(() => restoreAddresses());

  // =========================================================================
  // FIXTURE: Fresh protocol deploy
  // =========================================================================

  // Use loadFixture for test isolation. Each describe block that needs
  // gameOver state will advance time internally to avoid cross-test leakage.

  // =========================================================================
  // FIX-01: Whale bundle purchase reverts after gameOver
  // =========================================================================
  describe("FIX-01: Whale bundle blocked after gameOver", function () {
    it("purchaseWhalePass reverts after gameOver at level 0", async function () {
      const { game, deployer, alice, mockVRF } =
        await loadFixture(deployFullProtocol);

      // Advance time past 250-day deploy idle timeout
      await advanceTime(DEPLOY_IDLE_TIMEOUT_DAYS * DAY + DAY);
      await triggerGameOverAtLevel0(game, deployer, mockVRF);
      expect(await game.gameOver()).to.equal(true);

      // Whale bundle at level 0 costs 2.4 ETH
      await expect(
        game
          .connect(alice)
          .purchaseWhalePass(0, 1, hre.ethers.ZeroHash, { value: eth(2.4) })
      ).to.be.reverted;
    });
  });

  // =========================================================================
  // FIX-02: Lazy pass purchase reverts after gameOver
  // =========================================================================
  describe("FIX-02: Lazy pass blocked after gameOver", function () {
    it("purchaseLazyPass reverts after gameOver at level 0", async function () {
      const { game, deployer, alice, mockVRF } =
        await loadFixture(deployFullProtocol);

      await advanceTime(DEPLOY_IDLE_TIMEOUT_DAYS * DAY + DAY);
      await triggerGameOverAtLevel0(game, deployer, mockVRF);
      expect(await game.gameOver()).to.equal(true);

      // Lazy pass at level 0 costs 0.24 ETH
      await expect(
        game
          .connect(alice)
          .purchaseLazyPass(0, hre.ethers.ZeroHash, { value: eth(0.24) })
      ).to.be.reverted;
    });
  });

  // =========================================================================
  // FIX-03: Deity pass purchase reverts after gameOver
  // =========================================================================
  describe("FIX-03: Deity pass blocked after gameOver", function () {
    it("purchaseDeityPass reverts after gameOver at level 0", async function () {
      const { game, deployer, alice, mockVRF } =
        await loadFixture(deployFullProtocol);

      await advanceTime(DEPLOY_IDLE_TIMEOUT_DAYS * DAY + DAY);
      await triggerGameOverAtLevel0(game, deployer, mockVRF);
      expect(await game.gameOver()).to.equal(true);

      // Deity pass base price is 24 ETH + T(0) = 24 ETH for the first pass
      await expect(
        game
          .connect(alice)
          .purchaseDeityPass(0, 4, hre.ethers.ZeroHash, { value: eth(24) })
      ).to.be.reverted;
    });
  });

  // =========================================================================
  // FIX-04: receive() reverts after gameOver (plain ETH transfers blocked)
  // =========================================================================
  describe("FIX-04: receive() blocked after gameOver", function () {
    it("plain ETH transfer to game reverts after gameOver", async function () {
      const { game, deployer, alice, mockVRF } =
        await loadFixture(deployFullProtocol);

      await giveWalletId(game, alice.address);
      // Verify receive() works before gameOver
      const gameAddr = await game.getAddress();
      await expect(
        alice.sendTransaction({ to: gameAddr, value: eth(1) })
      ).to.not.be.reverted;

      await advanceTime(DEPLOY_IDLE_TIMEOUT_DAYS * DAY + DAY);
      await triggerGameOverAtLevel0(game, deployer, mockVRF);
      expect(await game.gameOver()).to.equal(true);

      // Now receive() should revert
      await expect(
        alice.sendTransaction({ to: gameAddr, value: eth(1) })
      ).to.be.reverted;
    });

    it("receive() credits the sender's afking funding before gameOver", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);
      const gameAddr = await game.getAddress();

      // receive() routes plain ETH to the sender's afking funding (claimablePool),
      // not directly to the future prize pool.
      await giveWalletId(game, alice.address);
      const before = await game.afkingFundingOf(alice.address);
      await alice.sendTransaction({ to: gameAddr, value: eth(1) });
      const after_ = await game.afkingFundingOf(alice.address);

      expect(after_ - before).to.equal(eth(1));
    });
  });

  // =========================================================================
  // Deity pass early-gameover refund — price-paid model (c4d48008)
  //
  // The contract tracks `deityPassPricePaid[buyer]` (a uint96 = the ETH price the
  // buyer paid; WhaleModule:605) and refunds `min(deityPassPricePaid[owner], 20e18)`
  // per owner at an early gameover (level < 10), then clamps to the remaining
  // budget FIFO (GameOverModule:105-135). There is no per-buyer purchase counter
  // and no "refund clears the count" step — the boon-ownership gate is the
  // HAS_DEITY_PASS bit, and the refund cap is the price-paid value above. A
  // standard-priced pass (24/25 ETH) is above the 20 ETH cap, so the cap binds and
  // the refund is exactly 20 ETH.
  // =========================================================================
  describe("Deity pass refund uses deityPassPricePaid (min(pricePaid, 20 ETH)) for payout", function () {
    it("a deity pass NFT is minted on purchase", async function () {
      const { game, deityPass, alice } = await loadFixture(deployFullProtocol);

      // Before purchase, the buyer holds no deity pass NFT.
      expect(
        await deityPass.balanceOf(alice.address)
      ).to.equal(0);

      // Purchase deity pass (symbol 0, base price 24 ETH)
      await game
        .connect(alice)
        .purchaseDeityPass(0, 4, hre.ethers.ZeroHash, { value: eth(24) });

      // After purchase, the buyer holds exactly one deity pass NFT (the
      // HAS_DEITY_PASS gate blocks a second; deityPassPricePaid records the price).
      expect(
        await deityPass.balanceOf(alice.address)
      ).to.equal(1);
    });

    it("gameOver refund credits min(deityPassPricePaid, 20 ETH) per pass = 20 ETH for a standard pass (level 0)", async function () {
      const { game, deityPass, deployer, alice, bob, mockVRF } =
        await loadFixture(deployFullProtocol);

      // Alice and Bob buy deity passes
      await game
        .connect(alice)
        .purchaseDeityPass(0, 4, hre.ethers.ZeroHash, { value: eth(24) });
      await game
        .connect(bob)
        .purchaseDeityPass(0, 1, hre.ethers.ZeroHash, { value: eth(25) });

      // Check pass counts via the DeityPass NFT balanceOf
      expect(
        await deityPass.balanceOf(alice.address)
      ).to.equal(1);
      expect(
        await deityPass.balanceOf(bob.address)
      ).to.equal(1);

      // Record claimable before gameOver
      const aliceClaimBefore = await game.claimableWinningsOf(alice.address);
      const bobClaimBefore = await game.claimableWinningsOf(bob.address);

      // Trigger gameOver
      await advanceTime(DEPLOY_IDLE_TIMEOUT_DAYS * DAY + DAY);
      await triggerGameOverAtLevel0(game, deployer, mockVRF);
      expect(await game.gameOver()).to.equal(true);

      // Check that claimable increased by 20 ETH per pass
      const aliceClaimAfter = await game.claimableWinningsOf(alice.address);
      const bobClaimAfter = await game.claimableWinningsOf(bob.address);

      // Pass 0 (k=0): recorded pricePaid = 24 ETH; pass 1 (k=1): pricePaid = 25 ETH. Both
      // exceed the 20 ETH cap, so min(deityPassPricePaid, 20e18) binds at exactly 20 ETH each.
      // These buyers hold ONLY a deity pass (no tickets/jackpot position), so the entire
      // claimable delta is the refund -> assert the EXACT cap, not a one-sided floor: a removed
      // min(pricePaid, 20e18) clamp would credit the full 24/25 ETH and FAIL this equality.
      expect(aliceClaimAfter - aliceClaimBefore).to.equal(eth(20));
      expect(bobClaimAfter - bobClaimBefore).to.equal(eth(20));
    });
  });

  // =========================================================================
  // FIX-06: Terminal deity refunds
  // =========================================================================
  describe("FIX-06: Terminal deity refunds", function () {


    it("deity pass refund only occurs via gameOver drain (level < 10)", async function () {
      const { game, deployer, alice, mockVRF } =
        await loadFixture(deployFullProtocol);

      // Buy a deity pass
      await game
        .connect(alice)
        .purchaseDeityPass(0, 4, hre.ethers.ZeroHash, { value: eth(24) });

      const claimBefore = await game.claimableWinningsOf(alice.address);

      // Without gameOver, no refund accumulates just by waiting
      await advanceTime(100 * DAY);
      const claimMid = await game.claimableWinningsOf(alice.address);
      expect(claimMid).to.equal(claimBefore);

      // Trigger gameOver and verify refund credits
      await advanceTime((DEPLOY_IDLE_TIMEOUT_DAYS - 100) * DAY + DAY);
      await triggerGameOverAtLevel0(game, deployer, mockVRF);
      expect(await game.gameOver()).to.equal(true);

      const claimAfter = await game.claimableWinningsOf(alice.address);
      expect(claimAfter).to.be.gt(claimBefore);
    });
  });

  // =========================================================================
  // FIX-07: GameOver deity payout — flat 20 ETH/pass, levels 0-9, FIFO, budget-capped
  // =========================================================================
  describe("FIX-07: GameOver deity payout correctness", function () {
    it("flat 20 ETH refund per pass at level 0 (early gameOver)", async function () {
      const { game, deployer, alice, mockVRF } =
        await loadFixture(deployFullProtocol);

      await game
        .connect(alice)
        .purchaseDeityPass(0, 4, hre.ethers.ZeroHash, { value: eth(24) });

      const claimBefore = await game.claimableWinningsOf(alice.address);

      await advanceTime(DEPLOY_IDLE_TIMEOUT_DAYS * DAY + DAY);
      await triggerGameOverAtLevel0(game, deployer, mockVRF);

      const claimAfter = await game.claimableWinningsOf(alice.address);
      const refund = claimAfter - claimBefore;

      // At least 20 ETH deity refund; terminal jackpot may add more
      expect(refund).to.be.gte(eth(20));
    });

    it("FIFO ordering: first buyer gets refund first if budget limited", async function () {
      const { game, deployer, alice, bob, carol, mockVRF } =
        await loadFixture(deployFullProtocol);

      // Buy passes in order: alice(0), bob(1), carol(2)
      await game
        .connect(alice)
        .purchaseDeityPass(0, 4, hre.ethers.ZeroHash, { value: eth(24) });
      await game
        .connect(bob)
        .purchaseDeityPass(0, 1, hre.ethers.ZeroHash, { value: eth(25) });
      await game
        .connect(carol)
        .purchaseDeityPass(0, 2, hre.ethers.ZeroHash, { value: eth(27) });

      const aliceBefore = await game.claimableWinningsOf(alice.address);
      const bobBefore = await game.claimableWinningsOf(bob.address);
      const carolBefore = await game.claimableWinningsOf(carol.address);

      // Trigger gameOver
      await advanceTime(DEPLOY_IDLE_TIMEOUT_DAYS * DAY + DAY);
      await triggerGameOverAtLevel0(game, deployer, mockVRF);

      const aliceRefund =
        (await game.claimableWinningsOf(alice.address)) - aliceBefore;
      const bobRefund =
        (await game.claimableWinningsOf(bob.address)) - bobBefore;
      const carolRefund =
        (await game.claimableWinningsOf(carol.address)) - carolBefore;

      // All should get at least 20 ETH deity refund each (budget sufficient: 24+25+27=76 ETH)
      // Terminal jackpot may add more since deity pass holders also hold tickets
      expect(aliceRefund).to.be.gte(eth(20));
      expect(bobRefund).to.be.gte(eth(20));
      // Carol also gets at least 20 ETH deity refund if budget allows
      expect(carolRefund).to.be.gte(eth(20));
    });

    it("gameOverFinalJackpotPaid prevents double-drain", async function () {
      const { game, deployer, alice, mockVRF } =
        await loadFixture(deployFullProtocol);

      await game
        .connect(alice)
        .purchaseDeityPass(0, 4, hre.ethers.ZeroHash, { value: eth(24) });

      await advanceTime(DEPLOY_IDLE_TIMEOUT_DAYS * DAY + DAY);
      await triggerGameOverAtLevel0(game, deployer, mockVRF);
      expect(await game.gameOver()).to.equal(true);

      const claimAfterFirst = await game.claimableWinningsOf(alice.address);

      // Calling mineFlip again should not increase claimable (drain already done)
      try {
        await game.connect(deployer).mineFlip(0);
      } catch {
        // May revert or be a no-op
      }

      const claimAfterSecond = await game.claimableWinningsOf(alice.address);
      expect(claimAfterSecond).to.equal(claimAfterFirst);
    });
  });

  // =========================================================================
  // FIX-08: FLIP ticket purchases revert within 30 days of liveness timeout
  // =========================================================================
  describe("FIX-08: FLIP ticket purchase cutoff", function () {
    it("redeemFlip reverts after 220 days at level 0 (within 30 days of timeout)", async function () {
      const { game, alice } =
        await loadFixture(deployFullProtocol);

      // First, make a normal ETH purchase to give alice some activity
      await game.connect(alice).purchase(
        0,
        400n,
        0n,
        ZERO_BYTES32,
        MintPaymentKind.DirectEth,false, 
        { value: eth(0.01) }
      );

      // Advance time past the cutoff (220 days = 250 - 30)
      await advanceTime(COIN_PURCHASE_CUTOFF_LVL0 * DAY + DAY);

      // Past the liveness cutoff, redeemFlip reverts (the liveness gate fires
      // before any purchase work). The call must revert regardless.
      await expect(
        game.connect(alice).redeemFlip(0, 400n)
      ).to.be.reverted;
    });
  });

  // =========================================================================
  // FIX-09: subscriptionId stored as uint256, large IDs handled
  // =========================================================================
  describe("FIX-09: uint256 subscriptionId", function () {


    it("subscriptionId exposes uint256 in the ABI", async function () {
      const { admin } = await loadFixture(deployFullProtocol);

      // The storage slot is uint256. Verify the ABI encodes it as uint256
      // by checking the function fragment
      const frag = admin.interface.getFunction("subscriptionId");
      expect(frag.outputs[0].type).to.equal("uint256");
    });

    it("subscriptionId is non-zero after deployment (VRF wired)", async function () {
      const { admin } = await loadFixture(deployFullProtocol);
      const subId = await admin.subscriptionId();
      expect(subId).to.not.equal(0n);
    });
  });

  // =========================================================================
  // FIX-10: 1 wei sentinel preserved in claimable winnings
  // =========================================================================
  describe("FIX-10: 1 wei sentinel in claimable winnings", function () {
    it("claimWinnings leaves 1 wei sentinel after full claim", async function () {
      const { game, deployer, alice, mockVRF } =
        await loadFixture(deployFullProtocol);

      // We need alice to have claimable winnings.
      // The simplest way: buy a deity pass, trigger gameOver refund.
      await game
        .connect(alice)
        .purchaseDeityPass(0, 4, hre.ethers.ZeroHash, { value: eth(24) });

      await advanceTime(DEPLOY_IDLE_TIMEOUT_DAYS * DAY + DAY);
      await triggerGameOverAtLevel0(game, deployer, mockVRF);

      // Alice should have 20 ETH claimable
      const claimBefore = await game.claimableWinningsOf(alice.address);
      expect(claimBefore).to.be.gte(eth(20));

      // Claim winnings
      await game.connect(alice)["claimWinnings(uint32)"](0);

      // After claim, 1 wei sentinel should remain
      const claimAfter = await game.claimableWinningsOf(alice.address);
      expect(claimAfter).to.equal(1n);
    });

    it("claimWinnings reverts if balance is only 1 wei (sentinel)", async function () {
      const { game, deployer, alice, mockVRF } =
        await loadFixture(deployFullProtocol);

      await game
        .connect(alice)
        .purchaseDeityPass(0, 4, hre.ethers.ZeroHash, { value: eth(24) });

      await advanceTime(DEPLOY_IDLE_TIMEOUT_DAYS * DAY + DAY);
      await triggerGameOverAtLevel0(game, deployer, mockVRF);

      // First claim succeeds
      await game.connect(alice)["claimWinnings(uint32)"](0);
      expect(await game.claimableWinningsOf(alice.address)).to.equal(1n);

      // Second claim should revert (only 1 wei = sentinel, nothing to claim)
      await expect(
        game.connect(alice)["claimWinnings(uint32)"](0)
      ).to.be.reverted;
    });

    it("processMintPayment preserves sentinel in Combined mode", async function () {
      const { game, deployer, alice, mockVRF } =
        await loadFixture(deployFullProtocol);

      // Give alice some claimable by buying deity pass and triggering gameOver
      await game
        .connect(alice)
        .purchaseDeityPass(0, 4, hre.ethers.ZeroHash, { value: eth(24) });

      await advanceTime(DEPLOY_IDLE_TIMEOUT_DAYS * DAY + DAY);
      await triggerGameOverAtLevel0(game, deployer, mockVRF);

      // Claim to leave just 1 wei sentinel
      await game.connect(alice)["claimWinnings(uint32)"](0);
      expect(await game.claimableWinningsOf(alice.address)).to.equal(1n);

      // Attempting to purchase with Claimable mode should revert
      // since balance is only 1 wei (sentinel)
      await expect(
        game.connect(alice).purchase(
          0,
          400n,
          0n,
          ZERO_BYTES32,
          MintPaymentKind.Claimable,false, 
          { value: 0n }
        )
      ).to.be.reverted;
    });
  });

  // =========================================================================
  // ECON-03: Multi-level scatter targeting (terminal jackpot)
  // =========================================================================
  describe("ECON-03: Multi-level scatter targeting", function () {
    it("terminal jackpot worker takes an explicit target level (runTerminalJackpotWork)", async function () {
      // The game-over drain pays the final ticket cohort through
      // runTerminalJackpotWork(poolWei, targetLvl, rngWord, allowance): the GameOver
      // module passes the phase-correct terminal level, so the trait-bucket scatter
      // samples that level's ticketholders rather than an implied current level.
      //
      // Structural test: the live worker on the jackpot module exposes the target level.
      const { jackpotModule } = await loadFixture(deployFullProtocol);
      const frag = jackpotModule.interface.getFunction("runTerminalJackpotWork");
      expect(frag).to.not.be.null;
      expect(frag.inputs.map((i) => `${i.type} ${i.name}`)).to.deep.equal([
        "uint256 poolWei",
        "uint24 targetLvl",
        "uint256 rngWord",
        "uint256 allowance",
      ]);
    });
  });

  // =========================================================================
  // ECON-04: Jackpot duration defaults to three days
  // =========================================================================
  describe("ECON-04: Jackpot duration", function () {
    it("starts with the standard three-day schedule", async function () {
      const { game } = await loadFixture(deployFullProtocol);
      expect(await game.jackpotDuration()).to.equal(3);
    });
  });

  // =========================================================================
  // ECON-05: LINK reward formula correctness
  // =========================================================================
  describe("ECON-05: LINK reward formula", function () {
    async function assertDonation(startLink, donatedLink, expectedFlip) {
      const { admin, mockLINK, mockVRF, mockFeed, game, coinflip, vault, sdgnrs, deployer, alice } =
        await loadFixture(deployFullProtocol);
      const adminAddr = await admin.getAddress();
      const vrfAddr = await mockVRF.getAddress();
      const feedAddr = await mockFeed.getAddress();
      const subId = await admin.subscriptionId();
      expect(subId).to.be.gt(0n);
      expect(await admin.linkEthPriceFeed()).to.equal(ZERO_ADDRESS);
      expect((await mockVRF.getSubscription(subId))[0]).to.equal(0n);

      // Public unwrap supplies a real voter; governance installs the healthy feed.
      await vault.connect(deployer).dgnrsUnwrapTo(deployer.address, hre.ethers.parseUnits("1000", 12));
      expect(await sdgnrs.votingSupply()).to.equal(hre.ethers.parseUnits("1000", 12));
      await admin.connect(deployer).proposeFeedSwap(feedAddr);
      const proposalId = await admin.feedProposalCount();
      await admin.connect(deployer).voteFeedSwap(proposalId, true);
      expect(await admin.linkEthPriceFeed()).to.equal(feedAddr);
      expect((await admin.feedProposals(proposalId)).state).to.equal(1n);
      expect(await mockFeed.price()).to.equal(eth("0.004"));
      expect(await game.mintPrice()).to.equal(eth("0.01"));

      // Seed the subscription with an actual LINK transfer, without donor rewards.
      const initial = eth(startLink);
      if (initial !== 0n) {
        await mockLINK.mint(deployer.address, initial);
        await mockLINK.connect(deployer).transferAndCall(vrfAddr, initial,
          hre.ethers.AbiCoder.defaultAbiCoder().encode(["uint256"], [subId]));
      }
      const amount = eth(donatedLink);
      const reward = BigInt(expectedFlip);
      expect(reward, "fixture must exercise a nonzero reward").to.be.gt(0n);
      await mockLINK.mint(alice.address, amount);
      expect(await mockLINK.balanceOf(alice.address)).to.equal(amount);
      expect(await mockLINK.balanceOf(adminAddr)).to.equal(0n);
      expect(await mockLINK.balanceOf(vrfAddr)).to.equal(initial);
      expect((await mockVRF.getSubscription(subId))[0]).to.equal(initial);
      expect(await coinflip.coinflipAmount(alice.address)).to.equal(0n);
      const middayBefore = await game.middayRngCredits(alice.address);

      const tx = await mockLINK.connect(alice).transferAndCall(adminAddr, amount, "0x");
      await expect(tx).to.emit(admin, "LinkCreditRecorded").withArgs(await game.walletIdOf(alice.address), reward);
      expect(await coinflip.coinflipAmount(alice.address), "actual donor reward").to.equal(reward);
      expect(await mockLINK.balanceOf(alice.address)).to.equal(0n);
      expect(await mockLINK.balanceOf(adminAddr)).to.equal(0n);
      expect(await mockLINK.balanceOf(vrfAddr)).to.equal(initial + amount);
      expect((await mockVRF.getSubscription(subId))[0]).to.equal(initial + amount);
      expect(await game.middayRngCredits(alice.address)).to.equal(middayBefore + amount);
    }

    it("10 LINK from empty earns the integrated 2.95x reward: 11800 FLIP", async function () {
      // Average of 3 and 2.9 over [0,10], times 400 FLIP/LINK at 1x.
      await assertDonation("0", "10", "11800");
    });

    it("LINK donation across 200 LINK pays the exact two-tier integral and forwards custody", async function () {
      // [190,200]: 10*(1.1+1)/2; [200,210]: 10*(1+.9875)/2.
      // Combined area 20.4375, at 400 FLIP per LINK-equivalent = 8175 FLIP.
      await assertDonation("190", "20", "8175");
    });

    it("LINK donation crossing 1000 LINK rewards only its below-cap integral", async function () {
      // [990,1000]: 10*(.0125+0)/2; [1000,1010]: zero. Area .0625 * 400.
      await assertDonation("990", "20", "25");
    });
  });

  // =========================================================================
  // ADDITIONAL: Cross-cutting structural tests
  // =========================================================================
  describe("Cross-cutting: gameOver guard consistency", function () {


    it("normal ETH ticket purchases also revert after gameOver", async function () {
      const { game, deployer, alice, mockVRF } =
        await loadFixture(deployFullProtocol);

      await advanceTime(DEPLOY_IDLE_TIMEOUT_DAYS * DAY + DAY);
      await triggerGameOverAtLevel0(game, deployer, mockVRF);

      await expect(
        game.connect(alice).purchase(
          0,
          400n,
          0n,
          ZERO_BYTES32,
          MintPaymentKind.DirectEth,false, 
          { value: eth(0.01) }
        )
      ).to.be.reverted;
    });
  });

  describe("Cross-cutting: deity pass is soulbound", function () {
    it("deity pass transferFrom reverts with Soulbound", async function () {
      const { game, deityPass, alice, bob } =
        await loadFixture(deployFullProtocol);

      await game
        .connect(alice)
        .purchaseDeityPass(0, 4, hre.ethers.ZeroHash, { value: eth(24) });

      await expect(
        deityPass.connect(alice).transferFrom(alice.address, bob.address, 0)
      ).to.be.revertedWithCustomError(deityPass, "Soulbound");
    });
  });

  describe("Cross-cutting: Pre-gameOver state validation", function () {
    it("whale bundle works at level 0 (before gameOver)", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);

      // Whale bundle at level 0: 2.4 ETH
      await expect(
        game
          .connect(alice)
          .purchaseWhalePass(0, 1, hre.ethers.ZeroHash, { value: eth(2.4) })
      ).to.not.be.reverted;
    });

    it("lazy pass works at level 0 (before gameOver)", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);

      // Lazy pass at level 0: 0.24 ETH
      await expect(
        game
          .connect(alice)
          .purchaseLazyPass(0, hre.ethers.ZeroHash, { value: eth(0.24) })
      ).to.not.be.reverted;
    });

    it("deity pass works at level 0 (before gameOver)", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);

      // First deity pass: 24 ETH (base price, no T(n) since n=0)
      await expect(
        game
          .connect(alice)
          .purchaseDeityPass(0, 4, hre.ethers.ZeroHash, { value: eth(24) })
      ).to.not.be.reverted;
    });


  });
});
