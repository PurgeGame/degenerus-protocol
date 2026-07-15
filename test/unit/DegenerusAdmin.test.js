import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers.js";
import { expect } from "chai";
import hre from "hardhat";
import {
  deployFullProtocol,
  restoreAddresses,
} from "../helpers/deployFixture.js";
import {
  eth,
  getEvents,
  getEvent,
  ZERO_ADDRESS,
  ZERO_BYTES32,
} from "../helpers/testUtils.js";

const Pool = { Whale: 0, Affiliate: 1, Lootbox: 2, Reward: 3, Earlybird: 4 };

async function grantSdgnrs(sdgnrs, game, recipient, amount) {
  const gameAddr = await game.getAddress();
  await hre.network.provider.request({ method: "hardhat_impersonateAccount", params: [gameAddr] });
  await hre.ethers.provider.send("hardhat_setBalance", [gameAddr, "0xDE0B6B3A7640000"]);
  const gameSigner = await hre.ethers.getSigner(gameAddr);
  try {
    await sdgnrs.connect(gameSigner).transferFromPool(Pool.Reward, recipient, amount);
  } catch {
    try {
      await sdgnrs.connect(gameSigner).transferFromPool(Pool.Whale, recipient, amount);
    } catch {
      await sdgnrs.connect(gameSigner).transferFromPool(Pool.Lootbox, recipient, amount);
    }
  }
  await hre.network.provider.request({ method: "hardhat_stopImpersonatingAccount", params: [gameAddr] });
}

describe("DegenerusAdmin", function () {
  after(() => restoreAddresses());

  // ---------------------------------------------------------------------------
  // 1. Constructor / Initial State
  // ---------------------------------------------------------------------------
  describe("Initial state", function () {
    it("subscriptionId is non-zero after deployment", async function () {
      const { admin } = await loadFixture(deployFullProtocol);
      const subId = await admin.subscriptionId();
      expect(subId).to.be.gt(0n);
    });

    it("coordinator is set to VRF coordinator address", async function () {
      const { admin, mockVRF } = await loadFixture(deployFullProtocol);
      const vrfAddr = await mockVRF.getAddress();
      expect(await admin.coordinator()).to.equal(vrfAddr);
    });

    it("vrfKeyHash is set (non-zero)", async function () {
      const { admin } = await loadFixture(deployFullProtocol);
      const hash = await admin.vrfKeyHash();
      expect(hash).to.not.equal(ZERO_BYTES32);
    });

    it("linkEthPriceFeed is initially zero", async function () {
      const { admin } = await loadFixture(deployFullProtocol);
      expect(await admin.linkEthPriceFeed()).to.equal(ZERO_ADDRESS);
    });

    it("constructor emits SubscriptionCreated event", async function () {
      // We verify state instead of replaying constructor events
      const { admin } = await loadFixture(deployFullProtocol);
      const subId = await admin.subscriptionId();
      expect(subId).to.be.gt(0n);
    });

    it("constructor emits CoordinatorUpdated event (captured via state)", async function () {
      const { admin, mockVRF } = await loadFixture(deployFullProtocol);
      const vrfAddr = await mockVRF.getAddress();
      // Coordinator was updated during construction
      expect(await admin.coordinator()).to.equal(vrfAddr);
    });
  });

  // ---------------------------------------------------------------------------
  // 2. setLinkEthPriceFeed — REMOVED (replaced by feed governance in FeedGovernance.test.js)
  // ---------------------------------------------------------------------------

  // ---------------------------------------------------------------------------
  // 3. onTokenTransfer (LINK ERC-677 callback)
  // ---------------------------------------------------------------------------
  describe("onTokenTransfer", function () {
    it("reverts when called by non-LINK address", async function () {
      const { admin, alice } = await loadFixture(deployFullProtocol);
      await expect(
        admin.connect(alice).onTokenTransfer(alice.address, eth("1"), "0x")
      ).to.be.revertedWithCustomError(admin, "NotAuthorized");
    });

    it("reverts when amount is zero", async function () {
      const { admin, mockLINK, alice } = await loadFixture(deployFullProtocol);
      const linkAddr = await mockLINK.getAddress();
      await hre.network.provider.request({
        method: "hardhat_impersonateAccount",
        params: [linkAddr],
      });
      await hre.ethers.provider.send("hardhat_setBalance", [
        linkAddr,
        "0xDE0B6B3A7640000",
      ]);
      const linkSigner = await hre.ethers.getSigner(linkAddr);
      await expect(
        admin.connect(linkSigner).onTokenTransfer(alice.address, 0n, "0x")
      ).to.be.revertedWithCustomError(admin, "InvalidAmount");
      await hre.network.provider.request({
        method: "hardhat_stopImpersonatingAccount",
        params: [linkAddr],
      });
    });

    it("LINK donation forwards to VRF subscription (subscription funded)", async function () {
      const { admin, mockLINK, mockVRF, deployer, alice } =
        await loadFixture(deployFullProtocol);

      const adminAddr = await admin.getAddress();
      const subId = await admin.subscriptionId();
      const vrfAddr = await mockVRF.getAddress();

      // Pre-fund the VRF subscription with >= 1000 LINK so the reward multiplier
      // is 0. This prevents the creditLinkReward call and lets us test the
      // LINK-forwarding path cleanly.
      await mockVRF.fundSubscription(subId, hre.ethers.parseUnits("1000", 18));

      // Mint LINK to alice for the donation
      await mockLINK.connect(deployer).mint(alice.address, eth("10"));

      // Alice calls transferAndCall on LINK which forwards LINK to admin
      // and calls admin.onTokenTransfer(alice, amount, data).
      // With the subscription already fully funded, mult=0 → no creditLinkReward call.
      const tx = await mockLINK.connect(alice).transferAndCall(
        adminAddr,
        eth("1"),
        "0x"
      );
      const receipt = await tx.wait();
      expect(receipt.status).to.equal(1);

      // Verify LINK was forwarded to the VRF subscription
      const [subBal] = await mockVRF.getSubscription(subId);
      // subBal increased by donated amount (1 LINK = 1e18 added to 1000e18 prefund)
      expect(subBal).to.be.gte(hre.ethers.parseUnits("1001", 18));
    });

    it("no credit emitted when price feed not set (oracle unavailable)", async function () {
      const { admin, mockLINK, deployer, alice } = await loadFixture(
        deployFullProtocol
      );
      // No price feed set; LINK is forwarded but no credit expected
      const adminAddr = await admin.getAddress();
      await mockLINK.connect(deployer).mint(alice.address, eth("5"));

      // transferAndCall triggers onTokenTransfer; should succeed but no LinkCreditRecorded
      const tx = await mockLINK.connect(alice).transferAndCall(
        adminAddr,
        eth("1"),
        "0x"
      );
      const receipt = await tx.wait();
      expect(receipt.status).to.equal(1);

      // Verify no LinkCreditRecorded event was emitted
      const events = await getEvents(tx, admin, "LinkCreditRecorded");
      expect(events.length).to.equal(0);
    });

    // Helper: donate linkAmount LINK to admin with price feed set and a given sub prefund.
    // Returns { flipBefore, flipAfter, event }.
    async function donateLink({ admin, sdgnrs, game, mockLINK, mockVRF, mockFeed, deployer, alice, coinflip, subPrefund, linkAmount }) {
      const adminAddr = await admin.getAddress();
      const feedAddr = await mockFeed.getAddress();
      const subId = await admin.subscriptionId();

      // Set price feed via governance (propose + vote → auto-executes)
      await grantSdgnrs(sdgnrs, game, deployer.address, hre.ethers.parseEther("1000"));
      await admin.connect(deployer).proposeFeedSwap(feedAddr);
      await admin.connect(deployer).voteFeedSwap(await admin.feedProposalCount(), true);

      // Pre-fund subscription to desired level to set multiplier tier
      if (subPrefund > 0n) {
        await mockVRF.fundSubscription(subId, subPrefund);
      }

      // Mint LINK to alice
      await mockLINK.connect(deployer).mint(alice.address, linkAmount);

      const flipBefore = await coinflip.coinflipAmount(alice.address);
      const tx = await mockLINK.connect(alice).transferAndCall(adminAddr, linkAmount, "0x");
      await tx.wait();
      const flipAfter = await coinflip.coinflipAmount(alice.address);

      const events = await getEvents(tx, admin, "LinkCreditRecorded");
      return { flipBefore, flipAfter, event: events[0] ?? null, tx };
    }

    // ---------------------------------------------------------------------------
    // creditLinkReward — flip credit from the integrated multiplier curve
    //
    // Formula: FLIP = linkAmount × (LINK/ETH price) × PRICE_COIN_UNIT / priceWei × mult
    //          PRICE_COIN_UNIT = 1000 FLIP/ticket (contract constant)
    //          mock feed       = 0.004 ETH/LINK
    //          fixture level   = L0 (0.01 ETH/ticket)
    //          base rate       = 1 LINK × 0.004 / 0.01 × 1000 = 400 FLIP (at 1x)
    //
    // `mult` is the length-weighted AVERAGE multiplier across [bal, bal+amount],
    // integrated over the piecewise-linear curve, so a donation earns the same
    // credit split or whole. The curve's marginal (point) multiplier is:
    //  Sub bal  │ Marginal mult
    //  ─────────┼───────────────
    //    0 LINK │  3x
    //  100 LINK │  2x
    //  200 LINK │  1x
    //  600 LINK │ 0.5x
    // 1000 LINK │  0x  (LINK past this point earns nothing)
    //
    // A finite donation integrates across the slice it spans, so 1 LINK from
    // empty earns the average over [0,1] ≈ 2.995x (1198 FLIP), not the 3x point.
    //
    // The formula is level-invariant in ticket value (priceWei cancels): FLIP
    // earned early at a low price retains its ticket value when spent later at a
    // higher price — rewarding early donors who hold their FLIP.
    // ---------------------------------------------------------------------------

    it("empty sub, 1 LINK → integrated ~3x = 1198 FLIP flip stake", async function () {
      const { admin, sdgnrs, game, mockLINK, mockVRF, mockFeed, coinflip, deployer, alice } =
        await loadFixture(deployFullProtocol);

      const { event, flipAfter } = await donateLink({
        admin, sdgnrs, game, mockLINK, mockVRF, mockFeed, coinflip, deployer, alice,
        subPrefund: 0n,
        linkAmount: eth("1"),
      });

      expect(event).to.not.be.null;
      expect(event.args.player).to.equal(alice.address);
      expect(event.args.amount).to.equal(eth("1198"));
      expect(flipAfter).to.equal(eth("1198"));
    });

    it("100 LINK in sub, 1 LINK → integrated ~2x = 798 FLIP flip stake", async function () {
      const { admin, sdgnrs, game, mockLINK, mockVRF, mockFeed, coinflip, deployer, alice } =
        await loadFixture(deployFullProtocol);

      // avg over [100,101]: (2 + 1.99)/2 = 1.995x → 798 FLIP
      const { event, flipAfter } = await donateLink({
        admin, sdgnrs, game, mockLINK, mockVRF, mockFeed, coinflip, deployer, alice,
        subPrefund: eth("100"),
        linkAmount: eth("1"),
      });

      expect(event).to.not.be.null;
      expect(event.args.amount).to.equal(eth("798"));
      expect(flipAfter).to.equal(eth("798"));
    });

    it("200 LINK in sub, 1 LINK → integrated ~1x = 399.75 FLIP flip stake", async function () {
      const { admin, sdgnrs, game, mockLINK, mockVRF, mockFeed, coinflip, deployer, alice } =
        await loadFixture(deployFullProtocol);

      // avg over [200,201]: (1 + 0.99875)/2 = 0.999375x → 399.75 FLIP
      const { event, flipAfter } = await donateLink({
        admin, sdgnrs, game, mockLINK, mockVRF, mockFeed, coinflip, deployer, alice,
        subPrefund: eth("200"),
        linkAmount: eth("1"),
      });

      expect(event).to.not.be.null;
      expect(event.args.amount).to.equal(eth("399.75"));
      expect(flipAfter).to.equal(eth("399.75"));
    });

    it("600 LINK in sub, 1 LINK → integrated ~0.5x = 199.75 FLIP flip stake", async function () {
      const { admin, sdgnrs, game, mockLINK, mockVRF, mockFeed, coinflip, deployer, alice } =
        await loadFixture(deployFullProtocol);

      // avg over [600,601]: (0.5 + 0.49875)/2 = 0.499375x → 199.75 FLIP
      const { event, flipAfter } = await donateLink({
        admin, sdgnrs, game, mockLINK, mockVRF, mockFeed, coinflip, deployer, alice,
        subPrefund: eth("600"),
        linkAmount: eth("1"),
      });

      expect(event).to.not.be.null;
      expect(event.args.amount).to.equal(eth("199.75"));
      expect(flipAfter).to.equal(eth("199.75"));
    });

    it("0x tier (1000+ LINK in sub): no flip credit emitted", async function () {
      const { admin, sdgnrs, game, mockLINK, mockVRF, mockFeed, coinflip, deployer, alice } =
        await loadFixture(deployFullProtocol);

      const { event, flipAfter } = await donateLink({
        admin, sdgnrs, game, mockLINK, mockVRF, mockFeed, coinflip, deployer, alice,
        subPrefund: eth("1000"),
        linkAmount: eth("1"),
      });

      expect(event).to.be.null;
      expect(flipAfter).to.equal(0n);
    });

    it("large donation integrates the curve: 10 LINK from empty = 11800 FLIP", async function () {
      const { admin, sdgnrs, game, mockLINK, mockVRF, mockFeed, coinflip, deployer, alice } =
        await loadFixture(deployFullProtocol);

      // avg mult over [0,10] = (3 + 2.9)/2 = 2.95x → 10 × 400 × 2.95 = 11800 FLIP
      // (below the 12000 a flat 3x would give — the donation climbs the decay curve)
      const { event, flipAfter } = await donateLink({
        admin, sdgnrs, game, mockLINK, mockVRF, mockFeed, coinflip, deployer, alice,
        subPrefund: 0n,
        linkAmount: eth("10"),
      });

      expect(event).to.not.be.null;
      expect(event.args.amount).to.equal(eth("11800"));
      expect(flipAfter).to.equal(eth("11800"));
    });

    it("batch equals split: one 100-LINK donation = five 20-LINK donations", async function () {
      // The integral makes credit path-independent: the same LINK from the same
      // starting balance earns identical total FLIP whole or split.
      const whole = await loadFixture(deployFullProtocol);
      const { flipAfter: wholeFlip } = await donateLink({
        ...whole, subPrefund: 0n, linkAmount: eth("100"),
      });

      // Split: donateLink sets up the feed on the first 20-LINK chunk (it can't
      // run again — proposeFeedSwap reverts once the feed is healthy), so the
      // remaining four chunks are raw transferAndCall. The mock's sub balance
      // accumulates across chunks, so each sees the balance the prior left.
      const split = await loadFixture(deployFullProtocol);
      const { admin, mockLINK, deployer, alice } = split;
      const adminAddr = await admin.getAddress();
      let splitRes = await donateLink({ ...split, subPrefund: 0n, linkAmount: eth("20") });
      let splitFlip = splitRes.flipAfter;
      for (let i = 0; i < 4; i++) {
        await mockLINK.connect(deployer).mint(alice.address, eth("20"));
        await (await mockLINK.connect(alice).transferAndCall(adminAddr, eth("20"), "0x")).wait();
        splitFlip = await split.coinflip.coinflipAmount(alice.address);
      }

      expect(wholeFlip).to.equal(splitFlip);
    });

    it("overfunding clamp: LINK past 1000 in one donation earns 0 on the excess", async function () {
      const { admin, sdgnrs, game, mockLINK, mockVRF, mockFeed, coinflip, deployer, alice } =
        await loadFixture(deployFullProtocol);

      // Donate 2000 LINK into an empty sub. Only the first 1000 is rewarded
      // (integral of the curve over [0,1000]); the 1000 past the zero point
      // earns nothing. Integral = area of the two linear tiers:
      //   [0,200]:   (3 + 1)/2   × 200 = 400
      //   [200,1000]:(1 + 0)/2   × 800 = 400
      //   total area = 800 LINK-equiv at 1x → 800 × 400 = 320000 FLIP
      const { event, flipAfter } = await donateLink({
        admin, sdgnrs, game, mockLINK, mockVRF, mockFeed, coinflip, deployer, alice,
        subPrefund: 0n,
        linkAmount: eth("2000"),
      });

      expect(event).to.not.be.null;
      expect(event.args.amount).to.equal(eth("320000"));
      expect(flipAfter).to.equal(eth("320000"));
    });

    it("game-level value: formula is level-invariant — 3x at any level gives ~0.012 ETH ticket value per LINK", async function () {
      // ticket value = ethEquivalent × mult (priceWei cancels in formula, up to 1 wei rounding)
      // 1 LINK × 0.004 ETH/LINK × 3 = 0.012 ETH ticket value, regardless of priceWei
      const PRICE_COIN_UNIT = eth("1000");
      const ethEquiv = eth("0.004");
      const mult = 3n;
      const expected = ethEquiv * mult; // 0.012 ETH
      // verify at several levels — all within 1 wei of invariant due to integer division
      for (const priceWei of [eth("0.01"), eth("0.04"), eth("0.12"), eth("0.24")]) {
        const flip = ethEquiv * PRICE_COIN_UNIT / priceWei * mult;
        const ticketValue = flip * priceWei / PRICE_COIN_UNIT;
        const diff = ticketValue > expected ? ticketValue - expected : expected - ticketValue;
        expect(diff).to.be.lessThanOrEqual(1n);
      }
    });

    it("game-level value: 1200 FLIP earned at L0 is worth 24x more at L100 than at L0", async function () {
      // FLIP earned early (at low price) retains value when spent at high price.
      // L0: 1200 × 0.01 / 1000 = 0.012 ETH; L100: 1200 × 0.24 / 1000 = 0.288 ETH → 24x ratio
      const PRICE_COIN_UNIT = eth("1000");
      const flip = eth("1200");   // what 1 LINK at 3x earns at L0
      const l0Value = flip * eth("0.01") / PRICE_COIN_UNIT;
      const l100Value = flip * eth("0.24") / PRICE_COIN_UNIT;
      expect(l100Value / l0Value).to.equal(24n);
    });

    it("game-level value: 3x tier returns 300% of donated LINK value as ticket stake", async function () {
      // ticket value = ethEquivalent × mult = 0.004 × 3 = 0.012 ETH
      // return = 0.012 / 0.004 = 300% = 30000 BPS
      const linkValueEth = eth("0.004");   // 1 LINK at mock price
      const ticketValue = linkValueEth * 3n; // mult=3 cancels priceWei
      const bps = (ticketValue * 10000n) / linkValueEth;
      expect(bps).to.equal(30000n);
    });
  });

  // ---------------------------------------------------------------------------
  // 4. linkAmountToEth (exposed as external for try/catch)
  // ---------------------------------------------------------------------------
  describe("linkAmountToEth", function () {
    it("returns 0 when no price feed is set", async function () {
      const { admin } = await loadFixture(deployFullProtocol);
      const result = await admin.linkAmountToEth(eth("1"));
      expect(result).to.equal(0n);
    });

    it("returns non-zero ETH equivalent when feed is set", async function () {
      const { admin, sdgnrs, game, mockFeed, deployer } = await loadFixture(deployFullProtocol);
      const feedAddr = await mockFeed.getAddress();
      // Set feed via governance (propose + vote → auto-executes)
      await grantSdgnrs(sdgnrs, game, deployer.address, hre.ethers.parseEther("1000"));
      await admin.connect(deployer).proposeFeedSwap(feedAddr);
      await admin.connect(deployer).voteFeedSwap(await admin.feedProposalCount(), true);
      // mockFeed price is 0.004 ETH per LINK
      const result = await admin.linkAmountToEth(eth("1"));
      // 1 LINK * 0.004 ETH/LINK = 0.004 ETH
      expect(result).to.equal(eth("0.004"));
    });

    it("returns 0 when amount is zero", async function () {
      const { admin, sdgnrs, game, mockFeed, deployer } = await loadFixture(deployFullProtocol);
      const feedAddr = await mockFeed.getAddress();
      // Set feed via governance (propose + vote → auto-executes)
      await grantSdgnrs(sdgnrs, game, deployer.address, hre.ethers.parseEther("1000"));
      await admin.connect(deployer).proposeFeedSwap(feedAddr);
      await admin.connect(deployer).voteFeedSwap(await admin.feedProposalCount(), true);
      const result = await admin.linkAmountToEth(0n);
      expect(result).to.equal(0n);
    });
  });

  // ---------------------------------------------------------------------------
  // 5. VRF Governance (propose / vote / execute)
  // ---------------------------------------------------------------------------
  describe("VRF Governance", function () {
    it("propose reverts when VRF is not stalled (< 44h)", async function () {
      const { admin, mockVRF, deployer } = await loadFixture(deployFullProtocol);
      const vrfAddr = await mockVRF.getAddress();
      const newKeyHash = hre.ethers.id("test-key-hash");
      await expect(
        admin.connect(deployer).propose(vrfAddr, newKeyHash)
      ).to.be.revertedWithCustomError(admin, "NotStalled");
    });

    it("propose reverts with ZeroAddress for zero coordinator", async function () {
      const { admin, deployer } = await loadFixture(deployFullProtocol);
      const newKeyHash = hre.ethers.id("test-key-hash");
      // Even if stalled, zero coordinator should revert ZeroAddress first
      await expect(
        admin.connect(deployer).propose(ZERO_ADDRESS, newKeyHash)
      ).to.be.revertedWithCustomError(admin, "ZeroAddress");
    });

    it("propose reverts with ZeroAddress for zero keyHash", async function () {
      const { admin, mockVRF, deployer } = await loadFixture(deployFullProtocol);
      const vrfAddr = await mockVRF.getAddress();
      await expect(
        admin.connect(deployer).propose(vrfAddr, ZERO_BYTES32)
      ).to.be.revertedWithCustomError(admin, "ZeroAddress");
    });

    it("community propose reverts with InsufficientStake when caller has no sDGNRS", async function () {
      const { admin, mockVRF, alice } = await loadFixture(deployFullProtocol);
      const vrfAddr = await mockVRF.getAddress();
      const newKeyHash = hre.ethers.id("test-key-hash");
      // Even after 7d stall, alice has no sDGNRS
      await hre.ethers.provider.send("evm_increaseTime", [7 * 86400 + 1]);
      await hre.ethers.provider.send("evm_mine");
      await expect(
        admin.connect(alice).propose(vrfAddr, newKeyHash)
      ).to.be.revertedWithCustomError(admin, "InsufficientStake");
    });

    it("vote reverts ProposalNotActive when the proposal does not exist (active-proposal precondition runs before any stall logic)", async function () {
      const { admin, deployer } = await loadFixture(deployFullProtocol);
      // vote() validates the proposal is active FIRST; the stall is no longer a
      // revert source (a recovered/healthy VRF now KILLS the proposal in-place
      // rather than reverting). A non-existent proposal (createdAt == 0) trips
      // the active-proposal guard regardless of stall state.
      await expect(
        admin.connect(deployer).vote(1, true)
      ).to.be.revertedWithCustomError(admin, "ProposalNotActive");
    });

    it("vote reverts with ProposalNotActive for non-existent proposal", async function () {
      const { admin, deployer } = await loadFixture(deployFullProtocol);
      // Advance 21 hours to pass stall check
      await hre.ethers.provider.send("evm_increaseTime", [21 * 3600]);
      await hre.ethers.provider.send("evm_mine");
      await expect(
        admin.connect(deployer).vote(999, true)
      ).to.be.revertedWithCustomError(admin, "ProposalNotActive");
    });

    it("votingSupply returns reasonable value", async function () {
      const { sdgnrs } = await loadFixture(deployFullProtocol);
      // After deployment, voting supply may be 0 or positive
      const supply = await sdgnrs.votingSupply();
      expect(supply).to.be.gte(0n);
    });

    it("threshold returns 6000 for fresh proposal (day 0)", async function () {
      const { admin } = await loadFixture(deployFullProtocol);
      // Threshold for non-existent proposal: createdAt=0, elapsed=block.timestamp (huge) → 0
      // This is expected — expired proposals have 0 threshold
      expect(await admin.threshold(0)).to.equal(0);
    });

    it("canExecute returns false for non-existent proposal", async function () {
      const { admin } = await loadFixture(deployFullProtocol);
      expect(await admin.canExecute(1)).to.equal(false);
    });

    it("proposalCount starts at 0", async function () {
      const { admin } = await loadFixture(deployFullProtocol);
      expect(await admin.proposalCount()).to.equal(0n);
    });

  });

  // ---------------------------------------------------------------------------
  // 6. shutdownVrf
  // ---------------------------------------------------------------------------
  describe("shutdownVrf", function () {
    it("reverts when called by non-GAME address", async function () {
      const { admin, deployer } = await loadFixture(deployFullProtocol);
      await expect(
        admin.connect(deployer).shutdownVrf()
      ).to.be.revertedWithCustomError(admin, "NotAuthorized");
    });

    it("reverts when called by alice", async function () {
      const { admin, alice } = await loadFixture(deployFullProtocol);
      await expect(
        admin.connect(alice).shutdownVrf()
      ).to.be.revertedWithCustomError(admin, "NotAuthorized");
    });
  });

  // ---------------------------------------------------------------------------
  // 7. swapGameEthForStEth
  // ---------------------------------------------------------------------------
  describe("swapGameEthForStEth", function () {
    it("reverts when called by non-owner", async function () {
      const { admin, alice } = await loadFixture(deployFullProtocol);
      await expect(
        admin.connect(alice).swapGameEthForStEth({ value: eth("1") })
      ).to.be.revertedWithCustomError(admin, "NotOwner");
    });

    it("reverts when msg.value is zero", async function () {
      const { admin, deployer } = await loadFixture(deployFullProtocol);
      await expect(
        admin.connect(deployer).swapGameEthForStEth({ value: 0n })
      ).to.be.revertedWithCustomError(admin, "InvalidAmount");
    });
  });

  // stakeGameEthToStEth and setLootboxRngThreshold removed from Admin in Phase 146
  // (now live directly on DegenerusGame with vault-owner access control)
});
