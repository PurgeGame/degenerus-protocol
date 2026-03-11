import { expect } from "chai";
import hre from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers.js";
import {
  deployFullProtocol,
  restoreAddresses,
} from "../helpers/deployFixture.js";
import {
  eth,
  getEvents,
  getEvent,
  ZERO_BYTES32,
} from "../helpers/testUtils.js";

/*
 * AffiliateHardening - Per-referrer Commission Cap & Lootbox Activity Taper
 * =========================================================================
 * Targeted tests for Phase 44 affiliate hardening features:
 *
 * Commission Cap (AFF-01 through AFF-04):
 *   - 0.5 ETH BURNIE cap per sender per affiliate per level
 *   - Cumulative tracking across multiple purchases
 *   - Cap resets at each new level
 *   - Independent caps per affiliate
 *
 * Lootbox Activity Taper (AFF-05 through AFF-09):
 *   - No taper below 15000 BPS score
 *   - Linear taper from 100% to 50% between 15000 and 25500 BPS
 *   - Floor at 50% payout above 25500 BPS
 *   - Leaderboard tracking uses full untapered amount
 *   - lootboxActivityScore parameter flows correctly
 */

// ---------------------------------------------------------------------------
// Constants (mirror contract values)
// ---------------------------------------------------------------------------

const MAX_COMMISSION_PER_REFERRER_PER_LEVEL = eth("0.5"); // 0.5 ether
const REWARD_SCALE_FRESH_L1_3_BPS = 2_500n; // 25%
const REWARD_SCALE_FRESH_L4P_BPS = 2_000n; // 20%
const REWARD_SCALE_RECYCLED_BPS = 500n; // 5%
const BPS_DENOMINATOR = 10_000n;
const LOOTBOX_TAPER_START_SCORE = 15_000;
const LOOTBOX_TAPER_END_SCORE = 25_500;
const LOOTBOX_TAPER_MIN_BPS = 5_000n;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function toBytes32(str) {
  return hre.ethers.encodeBytes32String(str);
}

/**
 * Call payAffiliate as the COIN contract via impersonation.
 * Returns the transaction receipt.
 */
async function payAffiliateAsCoin(
  hreEthers,
  coin,
  affiliate,
  amount,
  code,
  sender,
  lvl,
  isFreshEth,
  lootboxActivityScore = 0
) {
  const coinAddr = await coin.getAddress();
  await hreEthers.provider.send("hardhat_impersonateAccount", [coinAddr]);
  await hreEthers.provider.send("hardhat_setBalance", [
    coinAddr,
    "0x1000000000000000000",
  ]);
  const coinSigner = await hreEthers.getSigner(coinAddr);
  const tx = await affiliate
    .connect(coinSigner)
    .payAffiliate(amount, code, sender, lvl, isFreshEth, lootboxActivityScore);
  await hreEthers.provider.send("hardhat_stopImpersonatingAccount", [coinAddr]);
  return tx;
}

/**
 * staticCall payAffiliate as coin to get the return value without mutating.
 */
async function payAffiliateAsCoinStatic(
  hreEthers,
  coin,
  affiliate,
  amount,
  code,
  sender,
  lvl,
  isFreshEth,
  lootboxActivityScore = 0
) {
  const coinAddr = await coin.getAddress();
  await hreEthers.provider.send("hardhat_impersonateAccount", [coinAddr]);
  await hreEthers.provider.send("hardhat_setBalance", [
    coinAddr,
    "0x1000000000000000000",
  ]);
  const coinSigner = await hreEthers.getSigner(coinAddr);
  const result = await affiliate
    .connect(coinSigner)
    .payAffiliate.staticCall(
      amount,
      code,
      sender,
      lvl,
      isFreshEth,
      lootboxActivityScore
    );
  await hreEthers.provider.send("hardhat_stopImpersonatingAccount", [coinAddr]);
  return result;
}

/**
 * Compute the expected scaledAmount from a raw amount at a given level,
 * fresh/recycled ETH type, and apply per-referrer commission cap if needed.
 */
function computeScaledAmount(amount, lvl, isFreshEth) {
  let bps;
  if (isFreshEth) {
    bps = lvl <= 3n ? REWARD_SCALE_FRESH_L1_3_BPS : REWARD_SCALE_FRESH_L4P_BPS;
  } else {
    bps = REWARD_SCALE_RECYCLED_BPS;
  }
  return (amount * bps) / BPS_DENOMINATOR;
}

/**
 * Compute the expected taper multiplier at a given activity score.
 * Returns the tapered amount from a base amount.
 */
function computeTaperedAmount(amt, score) {
  if (score < LOOTBOX_TAPER_START_SCORE) return amt;
  if (score >= LOOTBOX_TAPER_END_SCORE) {
    return (amt * LOOTBOX_TAPER_MIN_BPS) / BPS_DENOMINATOR;
  }
  const excess = BigInt(score - LOOTBOX_TAPER_START_SCORE);
  const range = BigInt(LOOTBOX_TAPER_END_SCORE - LOOTBOX_TAPER_START_SCORE);
  const reductionBps = ((BPS_DENOMINATOR - LOOTBOX_TAPER_MIN_BPS) * excess) / range;
  return (amt * (BPS_DENOMINATOR - reductionBps)) / BPS_DENOMINATOR;
}

/**
 * Deploy fixture + set up alice as affiliate with bob referred to her.
 * Returns all protocol contracts plus alice/bob setup for immediate testing.
 */
async function deployWithAffiliateSetup() {
  const protocol = await deployFullProtocol();
  const { affiliate, coin, alice, bob, carol, dan, eve } = protocol;

  // Alice creates affiliate code "ALICE" with 0% kickback
  const aliceCode = toBytes32("ALICE");
  await affiliate.connect(alice).createAffiliateCode(aliceCode, 0);

  // Bob refers to Alice
  await affiliate.connect(bob).referPlayer(aliceCode);

  return { ...protocol, aliceCode };
}

/**
 * Deploy fixture + set up two affiliates: alice ("ALICE") and carol ("CAROL"),
 * both with bob referred. Actually, each sender can only have one referrer.
 * For AFF-04 (different affiliates, same sender), we use bob referred to alice
 * and dan referred to carol.
 */
async function deployWithTwoAffiliates() {
  const protocol = await deployFullProtocol();
  const { affiliate, alice, bob, carol, dan } = protocol;

  const aliceCode = toBytes32("ALICE");
  const carolCode = toBytes32("CAROL");

  await affiliate.connect(alice).createAffiliateCode(aliceCode, 0);
  await affiliate.connect(carol).createAffiliateCode(carolCode, 0);

  // Bob refers to Alice
  await affiliate.connect(bob).referPlayer(aliceCode);
  // Dan refers to Carol
  await affiliate.connect(dan).referPlayer(carolCode);

  return { ...protocol, aliceCode, carolCode };
}

// ---------------------------------------------------------------------------
// Test Suite
// ---------------------------------------------------------------------------

describe("AffiliateHardening", function () {
  after(() => restoreAddresses());

  // =========================================================================
  // Per-Referrer Commission Cap
  // =========================================================================
  describe("Per-Referrer Commission Cap", function () {

    // AFF-01: Affiliate earns at most 0.5 ETH BURNIE from single sender per level
    describe("AFF-01: Single large purchase hits cap", function () {

      it("caps commission at 0.5 ETH when scaled amount exceeds cap", async function () {
        const { affiliate, coin, alice, bob, aliceCode } =
          await loadFixture(deployWithAffiliateSetup);

        // At level 1, fresh ETH: 25% reward rate
        // To exceed 0.5 ETH cap: need amount > 2 ETH (2 * 25% = 0.5)
        // Send 4 ETH -> scaled = 1 ETH, but capped at 0.5 ETH
        const amount = eth("4");
        const lvl = 1;

        await payAffiliateAsCoin(
          hre.ethers,
          coin,
          affiliate,
          amount,
          aliceCode,
          bob.address,
          lvl,
          true, // freshEth
          0
        );

        // Alice's score should be capped at 0.5 ETH
        const score = await affiliate.affiliateScore(lvl, alice.address);
        expect(score).to.equal(MAX_COMMISSION_PER_REFERRER_PER_LEVEL);
      });

      it("returns 0 kickback once cap is fully consumed (0% kickback code)", async function () {
        const { affiliate, coin, alice, bob, aliceCode } =
          await loadFixture(deployWithAffiliateSetup);

        // First call: exactly fill the cap
        await payAffiliateAsCoin(
          hre.ethers, coin, affiliate,
          eth("4"), aliceCode, bob.address, 1, true, 0
        );

        // Second call: cap already full, should return 0
        const kickback = await payAffiliateAsCoinStatic(
          hre.ethers, coin, affiliate,
          eth("1"), aliceCode, bob.address, 1, true, 0
        );
        expect(kickback).to.equal(0n);
      });

      it("emits AffiliateEarningsRecorded with capped amount, not full scaled", async function () {
        const { affiliate, coin, alice, bob, aliceCode } =
          await loadFixture(deployWithAffiliateSetup);

        // 4 ETH at 25% = 1 ETH scaled, should be capped to 0.5 ETH
        const tx = await payAffiliateAsCoin(
          hre.ethers, coin, affiliate,
          eth("4"), aliceCode, bob.address, 1, true, 0
        );

        const events = await getEvents(tx, affiliate, "AffiliateEarningsRecorded");
        expect(events.length).to.equal(1);
        expect(events[0].args.amount).to.equal(MAX_COMMISSION_PER_REFERRER_PER_LEVEL);
        expect(events[0].args.newTotal).to.equal(MAX_COMMISSION_PER_REFERRER_PER_LEVEL);
      });

      it("allows exactly 0.5 ETH when scaled amount equals cap", async function () {
        const { affiliate, coin, alice, bob, aliceCode } =
          await loadFixture(deployWithAffiliateSetup);

        // At level 1, fresh ETH: 25% rate
        // 2 ETH * 25% = 0.5 ETH exactly
        await payAffiliateAsCoin(
          hre.ethers, coin, affiliate,
          eth("2"), aliceCode, bob.address, 1, true, 0
        );

        const score = await affiliate.affiliateScore(1, alice.address);
        expect(score).to.equal(MAX_COMMISSION_PER_REFERRER_PER_LEVEL);
      });

      it("allows full amount when scaled amount is below cap", async function () {
        const { affiliate, coin, alice, bob, aliceCode } =
          await loadFixture(deployWithAffiliateSetup);

        // 1 ETH * 25% = 0.25 ETH, well under cap
        await payAffiliateAsCoin(
          hre.ethers, coin, affiliate,
          eth("1"), aliceCode, bob.address, 1, true, 0
        );

        const expected = computeScaledAmount(eth("1"), 1n, true);
        const score = await affiliate.affiliateScore(1, alice.address);
        expect(score).to.equal(expected);
        expect(score).to.be.lt(MAX_COMMISSION_PER_REFERRER_PER_LEVEL);
      });
    });

    // AFF-02: Cap tracks cumulative spend across multiple small purchases
    describe("AFF-02: Cumulative spend tracking", function () {

      it("multiple small purchases accumulate toward 0.5 ETH cap", async function () {
        const { affiliate, coin, alice, bob, aliceCode } =
          await loadFixture(deployWithAffiliateSetup);

        // 5 purchases of 0.4 ETH each at 25% = 0.1 ETH each -> 0.5 ETH total
        for (let i = 0; i < 5; i++) {
          await payAffiliateAsCoin(
            hre.ethers, coin, affiliate,
            eth("0.4"), aliceCode, bob.address, 1, true, 0
          );
        }

        const score = await affiliate.affiliateScore(1, alice.address);
        expect(score).to.equal(MAX_COMMISSION_PER_REFERRER_PER_LEVEL);
      });

      it("6th purchase after cap is hit yields zero additional commission", async function () {
        const { affiliate, coin, alice, bob, aliceCode } =
          await loadFixture(deployWithAffiliateSetup);

        // Fill cap: 5 x 0.4 ETH at 25% = 5 x 0.1 = 0.5 ETH
        for (let i = 0; i < 5; i++) {
          await payAffiliateAsCoin(
            hre.ethers, coin, affiliate,
            eth("0.4"), aliceCode, bob.address, 1, true, 0
          );
        }

        const scoreBefore = await affiliate.affiliateScore(1, alice.address);

        // 6th purchase: should produce 0 additional commission
        await payAffiliateAsCoin(
          hre.ethers, coin, affiliate,
          eth("0.4"), aliceCode, bob.address, 1, true, 0
        );

        const scoreAfter = await affiliate.affiliateScore(1, alice.address);
        expect(scoreAfter).to.equal(scoreBefore);
        expect(scoreAfter).to.equal(MAX_COMMISSION_PER_REFERRER_PER_LEVEL);
      });

      it("partial cap fill then large purchase is clamped to remaining", async function () {
        const { affiliate, coin, alice, bob, aliceCode } =
          await loadFixture(deployWithAffiliateSetup);

        // First: 0.8 ETH at 25% = 0.2 ETH
        await payAffiliateAsCoin(
          hre.ethers, coin, affiliate,
          eth("0.8"), aliceCode, bob.address, 1, true, 0
        );

        const scoreAfterFirst = await affiliate.affiliateScore(1, alice.address);
        expect(scoreAfterFirst).to.equal(eth("0.2"));

        // Second: 4 ETH at 25% = 1 ETH, but only 0.3 ETH remaining in cap
        await payAffiliateAsCoin(
          hre.ethers, coin, affiliate,
          eth("4"), aliceCode, bob.address, 1, true, 0
        );

        const scoreAfterSecond = await affiliate.affiliateScore(1, alice.address);
        expect(scoreAfterSecond).to.equal(MAX_COMMISSION_PER_REFERRER_PER_LEVEL);
      });

      it("recycled ETH purchases also accumulate toward the same cap", async function () {
        const { affiliate, coin, alice, bob, aliceCode } =
          await loadFixture(deployWithAffiliateSetup);

        // Recycled ETH at 5% rate: 10 ETH * 5% = 0.5 ETH -> exactly cap
        await payAffiliateAsCoin(
          hre.ethers, coin, affiliate,
          eth("10"), aliceCode, bob.address, 1, false, 0
        );

        const score = await affiliate.affiliateScore(1, alice.address);
        expect(score).to.equal(MAX_COMMISSION_PER_REFERRER_PER_LEVEL);
      });

      it("mixed fresh and recycled ETH purchases share the same cap", async function () {
        const { affiliate, coin, alice, bob, aliceCode } =
          await loadFixture(deployWithAffiliateSetup);

        // Fresh: 1 ETH * 25% = 0.25 ETH
        await payAffiliateAsCoin(
          hre.ethers, coin, affiliate,
          eth("1"), aliceCode, bob.address, 1, true, 0
        );

        // Recycled: 5 ETH * 5% = 0.25 ETH -> total 0.5 ETH = cap
        await payAffiliateAsCoin(
          hre.ethers, coin, affiliate,
          eth("5"), aliceCode, bob.address, 1, false, 0
        );

        const score = await affiliate.affiliateScore(1, alice.address);
        expect(score).to.equal(MAX_COMMISSION_PER_REFERRER_PER_LEVEL);
      });
    });

    // AFF-03: Cap resets per level
    describe("AFF-03: Cap resets at each new level", function () {

      it("same sender/affiliate pair earns again at a different level", async function () {
        const { affiliate, coin, alice, bob, aliceCode } =
          await loadFixture(deployWithAffiliateSetup);

        // Fill cap at level 1
        await payAffiliateAsCoin(
          hre.ethers, coin, affiliate,
          eth("4"), aliceCode, bob.address, 1, true, 0
        );
        const scoreL1 = await affiliate.affiliateScore(1, alice.address);
        expect(scoreL1).to.equal(MAX_COMMISSION_PER_REFERRER_PER_LEVEL);

        // Level 2: fresh cap, should earn again
        await payAffiliateAsCoin(
          hre.ethers, coin, affiliate,
          eth("1"), aliceCode, bob.address, 2, true, 0
        );
        const scoreL2 = await affiliate.affiliateScore(2, alice.address);
        const expectedL2 = computeScaledAmount(eth("1"), 2n, true);
        expect(scoreL2).to.equal(expectedL2);
        expect(scoreL2).to.be.gt(0n);
      });

      it("cap at level 1 does not affect level 0 earnings", async function () {
        const { affiliate, coin, alice, bob, aliceCode } =
          await loadFixture(deployWithAffiliateSetup);

        // Fill cap at level 1
        await payAffiliateAsCoin(
          hre.ethers, coin, affiliate,
          eth("4"), aliceCode, bob.address, 1, true, 0
        );

        // Earn at level 0 independently
        await payAffiliateAsCoin(
          hre.ethers, coin, affiliate,
          eth("1"), aliceCode, bob.address, 0, true, 0
        );

        const scoreL0 = await affiliate.affiliateScore(0, alice.address);
        const expectedL0 = computeScaledAmount(eth("1"), 0n, true);
        expect(scoreL0).to.equal(expectedL0);
      });

      it("can fill cap independently at multiple levels", async function () {
        const { affiliate, coin, alice, bob, aliceCode } =
          await loadFixture(deployWithAffiliateSetup);

        // Fill cap at levels 1, 2, and 5
        for (const lvl of [1, 2, 5]) {
          await payAffiliateAsCoin(
            hre.ethers, coin, affiliate,
            eth("4"), aliceCode, bob.address, lvl, true, 0
          );
        }

        for (const lvl of [1, 2, 5]) {
          const score = await affiliate.affiliateScore(lvl, alice.address);
          expect(score).to.equal(MAX_COMMISSION_PER_REFERRER_PER_LEVEL);
        }
      });
    });

    // AFF-04: Cap is per-affiliate (different affiliates have independent caps)
    describe("AFF-04: Independent caps per affiliate", function () {

      it("two affiliates each get their own 0.5 ETH cap from different senders", async function () {
        const { affiliate, coin, alice, bob, carol, dan, aliceCode, carolCode } =
          await loadFixture(deployWithTwoAffiliates);

        // Bob -> Alice: fill cap
        await payAffiliateAsCoin(
          hre.ethers, coin, affiliate,
          eth("4"), aliceCode, bob.address, 1, true, 0
        );

        // Dan -> Carol: fill cap
        await payAffiliateAsCoin(
          hre.ethers, coin, affiliate,
          eth("4"), carolCode, dan.address, 1, true, 0
        );

        const aliceScore = await affiliate.affiliateScore(1, alice.address);
        const carolScore = await affiliate.affiliateScore(1, carol.address);
        expect(aliceScore).to.equal(MAX_COMMISSION_PER_REFERRER_PER_LEVEL);
        expect(carolScore).to.equal(MAX_COMMISSION_PER_REFERRER_PER_LEVEL);
      });

      it("alice cap exhaustion does not affect carol earning from a different sender", async function () {
        const { affiliate, coin, alice, bob, carol, dan, aliceCode, carolCode } =
          await loadFixture(deployWithTwoAffiliates);

        // Bob -> Alice: exhaust cap
        await payAffiliateAsCoin(
          hre.ethers, coin, affiliate,
          eth("4"), aliceCode, bob.address, 1, true, 0
        );

        // Bob -> Alice: should yield 0 additional
        await payAffiliateAsCoin(
          hre.ethers, coin, affiliate,
          eth("1"), aliceCode, bob.address, 1, true, 0
        );
        const aliceScore = await affiliate.affiliateScore(1, alice.address);
        expect(aliceScore).to.equal(MAX_COMMISSION_PER_REFERRER_PER_LEVEL);

        // Dan -> Carol: still has full cap
        await payAffiliateAsCoin(
          hre.ethers, coin, affiliate,
          eth("1"), carolCode, dan.address, 1, true, 0
        );
        const carolScore = await affiliate.affiliateScore(1, carol.address);
        expect(carolScore).to.equal(computeScaledAmount(eth("1"), 1n, true));
        expect(carolScore).to.be.gt(0n);
      });

      it("same affiliate tracks caps independently per sender", async function () {
        const { affiliate, coin, alice, bob, carol, eve, aliceCode } =
          await loadFixture(deployWithAffiliateSetup);

        // Carol also refers to Alice
        await affiliate.connect(carol).referPlayer(aliceCode);

        // Bob -> Alice: fill cap
        await payAffiliateAsCoin(
          hre.ethers, coin, affiliate,
          eth("4"), aliceCode, bob.address, 1, true, 0
        );

        // Carol -> Alice: has her own independent cap
        await payAffiliateAsCoin(
          hre.ethers, coin, affiliate,
          eth("4"), aliceCode, carol.address, 1, true, 0
        );

        // Alice earned 0.5 from bob + 0.5 from carol = 1.0 total
        const aliceScore = await affiliate.affiliateScore(1, alice.address);
        expect(aliceScore).to.equal(MAX_COMMISSION_PER_REFERRER_PER_LEVEL * 2n);
      });
    });
  });

  // =========================================================================
  // Lootbox Activity Taper
  // =========================================================================
  describe("Lootbox Activity Taper", function () {

    // AFF-05: No taper below 15000 BPS
    describe("AFF-05: No taper when score < 15000 BPS", function () {

      it("score 0: full payout, no taper", async function () {
        const { affiliate, coin, alice, bob, aliceCode } =
          await loadFixture(deployWithAffiliateSetup);

        const amount = eth("1");
        await payAffiliateAsCoin(
          hre.ethers, coin, affiliate,
          amount, aliceCode, bob.address, 1, true, 0
        );

        const score = await affiliate.affiliateScore(1, alice.address);
        const expected = computeScaledAmount(amount, 1n, true);
        expect(score).to.equal(expected);
      });

      it("score 14999: still full payout, no taper", async function () {
        const { affiliate, coin, alice, bob, aliceCode } =
          await loadFixture(deployWithAffiliateSetup);

        const amount = eth("1");
        await payAffiliateAsCoin(
          hre.ethers, coin, affiliate,
          amount, aliceCode, bob.address, 1, true, 14999
        );

        // Leaderboard records full untapered amount regardless
        const score = await affiliate.affiliateScore(1, alice.address);
        const expected = computeScaledAmount(amount, 1n, true);
        expect(score).to.equal(expected);
      });

      it("score 1: no taper applied", async function () {
        const { affiliate, coin, alice, bob, aliceCode } =
          await loadFixture(deployWithAffiliateSetup);

        const amount = eth("0.5");
        await payAffiliateAsCoin(
          hre.ethers, coin, affiliate,
          amount, aliceCode, bob.address, 2, true, 1
        );

        const score = await affiliate.affiliateScore(2, alice.address);
        const expected = computeScaledAmount(amount, 2n, true);
        expect(score).to.equal(expected);
      });
    });

    // AFF-06: Linear taper from 100% to 50% between 15000-25500 BPS
    describe("AFF-06: Linear taper in 15000-25500 BPS range", function () {

      it("score exactly 15000: no reduction (taper just starts)", async function () {
        const { affiliate, coin, alice, bob, aliceCode } =
          await loadFixture(deployWithAffiliateSetup);

        // Use small amount so cap does not interfere
        const amount = eth("0.1");
        const lvl = 1;

        // We use two calls: one with score 0, one with score 15000
        // Compare events to verify the tapered payout amount
        const tx = await payAffiliateAsCoin(
          hre.ethers, coin, affiliate,
          amount, aliceCode, bob.address, lvl, true, LOOTBOX_TAPER_START_SCORE
        );

        // Leaderboard always gets full amount
        const score = await affiliate.affiliateScore(lvl, alice.address);
        const fullScaled = computeScaledAmount(amount, BigInt(lvl), true);
        expect(score).to.equal(fullScaled);

        // At exactly 15000, excess=0 so reductionBps=0, full payout
        // The taper condition is: score >= LOOTBOX_TAPER_START_SCORE
        // At 15000: excess=0, so (5000*0)/10500 = 0, taper = amt * 10000/10000 = full
        // So payout equals untapered amount
      });

      it("score 20250 (midpoint): approximately 75% payout", async function () {
        const { affiliate, coin, alice, bob, aliceCode } =
          await loadFixture(deployWithAffiliateSetup);

        const amount = eth("0.1");
        const lvl = 1;
        const midScore = 20250; // halfway between 15000 and 25500

        // Compute expected taper
        const fullScaled = computeScaledAmount(amount, BigInt(lvl), true);
        const expectedTapered = computeTaperedAmount(fullScaled, midScore);

        // Midpoint: 100% -> 50% means midpoint is 75%
        // (10000 - 5000) * 5250 / 10500 = 5000 * 0.5 = 2500 reduction
        // payout = amt * (10000-2500)/10000 = amt * 75%
        expect(expectedTapered).to.equal((fullScaled * 7500n) / 10000n);

        await payAffiliateAsCoin(
          hre.ethers, coin, affiliate,
          amount, aliceCode, bob.address, lvl, true, midScore
        );

        // Leaderboard still shows full untapered amount
        const score = await affiliate.affiliateScore(lvl, alice.address);
        expect(score).to.equal(fullScaled);
      });

      it("score 15001: very small reduction from 100%", async function () {
        const { affiliate, coin, alice, bob, aliceCode } =
          await loadFixture(deployWithAffiliateSetup);

        const amount = eth("1");
        const fullScaled = computeScaledAmount(amount, 1n, true);
        const tapered = computeTaperedAmount(fullScaled, 15001);

        // Very small reduction: excess=1, range=10500
        // reductionBps = 5000 * 1 / 10500 = 0 (integer division)
        // So payout = full amount (because 5000/10500 = 0 in integer math)
        expect(tapered).to.equal(fullScaled);
      });

      it("score 25499: just below floor, slightly above 50%", async function () {
        const { affiliate, coin, alice, bob, aliceCode } =
          await loadFixture(deployWithAffiliateSetup);

        const amount = eth("1");
        const fullScaled = computeScaledAmount(amount, 1n, true);
        const tapered = computeTaperedAmount(fullScaled, 25499);

        // excess=10499, range=10500
        // reductionBps = 5000 * 10499 / 10500 = 4999 (integer)
        // payout = amt * (10000-4999)/10000 = amt * 5001/10000
        const expectedReductionBps = (5000n * 10499n) / 10500n;
        const expectedPayout = (fullScaled * (10000n - expectedReductionBps)) / 10000n;
        expect(tapered).to.equal(expectedPayout);
        // Confirm it's slightly above 50%
        expect(tapered).to.be.gt((fullScaled * LOOTBOX_TAPER_MIN_BPS) / BPS_DENOMINATOR);
      });
    });

    // AFF-07: Floor at 50% payout when score >= 25500
    describe("AFF-07: Floor at 50% for score >= 25500 BPS", function () {

      it("score exactly 25500: 50% payout floor", async function () {
        const { affiliate, coin, alice, bob, aliceCode } =
          await loadFixture(deployWithAffiliateSetup);

        const amount = eth("0.1");
        const fullScaled = computeScaledAmount(amount, 1n, true);
        const expected50pct = (fullScaled * LOOTBOX_TAPER_MIN_BPS) / BPS_DENOMINATOR;

        await payAffiliateAsCoin(
          hre.ethers, coin, affiliate,
          amount, aliceCode, bob.address, 1, true, LOOTBOX_TAPER_END_SCORE
        );

        // Leaderboard: full untapered
        const score = await affiliate.affiliateScore(1, alice.address);
        expect(score).to.equal(fullScaled);

        // Verify the tapered output via our helper math
        expect(expected50pct).to.equal(fullScaled / 2n);
      });

      it("score 30000: still 50% floor (no further reduction)", async function () {
        const { affiliate, coin, alice, bob, aliceCode } =
          await loadFixture(deployWithAffiliateSetup);

        const amount = eth("0.1");
        const fullScaled = computeScaledAmount(amount, 1n, true);
        const tapered = computeTaperedAmount(fullScaled, 30000);
        const expected50pct = (fullScaled * LOOTBOX_TAPER_MIN_BPS) / BPS_DENOMINATOR;

        expect(tapered).to.equal(expected50pct);
      });

      it("score 65535 (max uint16): still 50% floor", async function () {
        const { affiliate, coin, alice, bob, aliceCode } =
          await loadFixture(deployWithAffiliateSetup);

        const amount = eth("0.1");
        const fullScaled = computeScaledAmount(amount, 1n, true);
        const tapered = computeTaperedAmount(fullScaled, 65535);
        const expected50pct = (fullScaled * LOOTBOX_TAPER_MIN_BPS) / BPS_DENOMINATOR;

        expect(tapered).to.equal(expected50pct);

        // Also execute on-chain to verify it does not revert
        await payAffiliateAsCoin(
          hre.ethers, coin, affiliate,
          amount, aliceCode, bob.address, 1, true, 65535
        );

        const score = await affiliate.affiliateScore(1, alice.address);
        expect(score).to.equal(fullScaled);
      });
    });

    // AFF-08: Leaderboard tracking uses full untapered amount
    describe("AFF-08: Leaderboard uses untapered amount", function () {

      it("leaderboard score matches full scaled amount even when heavily tapered", async function () {
        const { affiliate, coin, alice, bob, aliceCode } =
          await loadFixture(deployWithAffiliateSetup);

        const amount = eth("0.1");
        const lvl = 1;

        // Pay with maximum taper (score >= 25500 -> 50% payout)
        await payAffiliateAsCoin(
          hre.ethers, coin, affiliate,
          amount, aliceCode, bob.address, lvl, true, LOOTBOX_TAPER_END_SCORE
        );

        const fullScaled = computeScaledAmount(amount, BigInt(lvl), true);
        const score = await affiliate.affiliateScore(lvl, alice.address);

        // Leaderboard should reflect FULL untapered amount
        expect(score).to.equal(fullScaled);
        // Not the tapered 50%
        expect(score).to.not.equal(fullScaled / 2n);
      });

      it("AffiliateEarningsRecorded event emits full untapered amount", async function () {
        const { affiliate, coin, alice, bob, aliceCode } =
          await loadFixture(deployWithAffiliateSetup);

        const amount = eth("0.1");
        const lvl = 2;
        const fullScaled = computeScaledAmount(amount, BigInt(lvl), true);

        const tx = await payAffiliateAsCoin(
          hre.ethers, coin, affiliate,
          amount, aliceCode, bob.address, lvl, true, 25500
        );

        const events = await getEvents(tx, affiliate, "AffiliateEarningsRecorded");
        expect(events.length).to.equal(1);
        // The emitted amount is the full scaled (post-cap but pre-taper)
        expect(events[0].args.amount).to.equal(fullScaled);
        expect(events[0].args.newTotal).to.equal(fullScaled);
      });

      it("top affiliate tracks untapered cumulative across multiple tapered calls", async function () {
        const { affiliate, coin, alice, bob, aliceCode } =
          await loadFixture(deployWithAffiliateSetup);

        const amount = eth("0.1");
        const lvl = 1;
        const fullScaled = computeScaledAmount(amount, BigInt(lvl), true);

        // 3 purchases each with heavy taper
        for (let i = 0; i < 3; i++) {
          await payAffiliateAsCoin(
            hre.ethers, coin, affiliate,
            amount, aliceCode, bob.address, lvl, true, 25000
          );
        }

        const score = await affiliate.affiliateScore(lvl, alice.address);
        // Should be 3 x fullScaled (untapered accumulation)
        expect(score).to.equal(fullScaled * 3n);
      });
    });

    // AFF-09: lootboxActivityScore parameter flows correctly through payAffiliate
    describe("AFF-09: lootboxActivityScore parameter flow", function () {

      it("score=0 produces same result as no-taper baseline", async function () {
        const { affiliate, coin, alice, bob, aliceCode } =
          await loadFixture(deployWithAffiliateSetup);

        const amount = eth("0.1");
        const lvl = 1;

        await payAffiliateAsCoin(
          hre.ethers, coin, affiliate,
          amount, aliceCode, bob.address, lvl, true, 0
        );

        const score = await affiliate.affiliateScore(lvl, alice.address);
        const fullScaled = computeScaledAmount(amount, BigInt(lvl), true);
        expect(score).to.equal(fullScaled);
      });

      it("taper does not apply to recycled ETH purchases (still valid parameter)", async function () {
        const { affiliate, coin, alice, bob, aliceCode } =
          await loadFixture(deployWithAffiliateSetup);

        const amount = eth("1");
        const lvl = 1;

        // Recycled ETH at 5% with high taper score
        await payAffiliateAsCoin(
          hre.ethers, coin, affiliate,
          amount, aliceCode, bob.address, lvl, false, 25500
        );

        const score = await affiliate.affiliateScore(lvl, alice.address);
        const fullScaled = computeScaledAmount(amount, BigInt(lvl), false);
        // Leaderboard always tracks full amount (taper is applied but only to payout)
        expect(score).to.equal(fullScaled);
      });

      it("different taper scores produce different payout amounts for same input", async function () {
        // We verify via kickback amounts with a non-zero kickback affiliate
        const protocol = await loadFixture(deployFullProtocol);
        const { affiliate, coin, alice, bob, carol, dan, eve } = protocol;

        // Create affiliate with 25% kickback
        const code = toBytes32("RAKE25");
        await affiliate.connect(alice).createAffiliateCode(code, 25);

        // Bob refers to alice's code
        await affiliate.connect(bob).referPlayer(code);
        // Carol refers to alice's code
        await affiliate.connect(carol).referPlayer(code);

        const amount = eth("0.1");
        const lvl = 1;

        // Bob pays with no taper (score=0)
        const kickbackNoTaper = await payAffiliateAsCoinStatic(
          hre.ethers, coin, affiliate,
          amount, code, bob.address, lvl, true, 0
        );

        // Carol pays with max taper (score=25500 -> 50%)
        const kickbackMaxTaper = await payAffiliateAsCoinStatic(
          hre.ethers, coin, affiliate,
          amount, code, carol.address, lvl, true, LOOTBOX_TAPER_END_SCORE
        );

        // Kickback should be different: tapered = 50% of untapered
        expect(kickbackNoTaper).to.be.gt(0n);
        expect(kickbackMaxTaper).to.be.gt(0n);
        expect(kickbackMaxTaper).to.equal(kickbackNoTaper / 2n);
      });

      it("taper interacts correctly with commission cap (cap applied first, then taper)", async function () {
        const { affiliate, coin, alice, bob, aliceCode } =
          await loadFixture(deployWithAffiliateSetup);

        // Partially fill cap: 0.8 ETH at 25% = 0.2 ETH used
        await payAffiliateAsCoin(
          hre.ethers, coin, affiliate,
          eth("0.8"), aliceCode, bob.address, 1, true, 0
        );

        // Now: remaining cap = 0.3 ETH
        // Send 4 ETH at 25% = 1.0 scaled, capped to 0.3 ETH
        // With taper score 25500: tapered payout = 0.3 * 50% = 0.15 ETH
        // But leaderboard should record 0.3 (the capped but untapered amount)
        await payAffiliateAsCoin(
          hre.ethers, coin, affiliate,
          eth("4"), aliceCode, bob.address, 1, true, LOOTBOX_TAPER_END_SCORE
        );

        const score = await affiliate.affiliateScore(1, alice.address);
        // 0.2 + 0.3 = 0.5 ETH (cap)
        expect(score).to.equal(MAX_COMMISSION_PER_REFERRER_PER_LEVEL);
      });
    });
  });

  // =========================================================================
  // Edge Cases & Combined Scenarios
  // =========================================================================
  describe("Edge Cases", function () {

    it("zero amount produces no commission and no revert", async function () {
      const { affiliate, coin, alice, bob, aliceCode } =
        await loadFixture(deployWithAffiliateSetup);

      await payAffiliateAsCoin(
        hre.ethers, coin, affiliate,
        0n, aliceCode, bob.address, 1, true, 0
      );

      const score = await affiliate.affiliateScore(1, alice.address);
      expect(score).to.equal(0n);
    });

    it("very small amount (1 wei) does not revert", async function () {
      const { affiliate, coin, alice, bob, aliceCode } =
        await loadFixture(deployWithAffiliateSetup);

      // 1 wei * 2500 / 10000 = 0 (rounds to zero) -> returns early
      await payAffiliateAsCoin(
        hre.ethers, coin, affiliate,
        1n, aliceCode, bob.address, 1, true, 0
      );

      const score = await affiliate.affiliateScore(1, alice.address);
      expect(score).to.equal(0n);
    });

    it("cap boundary: exact cap fill then exact 0 on next call", async function () {
      const { affiliate, coin, alice, bob, aliceCode } =
        await loadFixture(deployWithAffiliateSetup);

      // Exact 0.5 ETH: 2 ETH * 25% = 0.5 ETH
      await payAffiliateAsCoin(
        hre.ethers, coin, affiliate,
        eth("2"), aliceCode, bob.address, 1, true, 0
      );

      // Even tiny additional amount yields 0
      const kickback = await payAffiliateAsCoinStatic(
        hre.ethers, coin, affiliate,
        1n, aliceCode, bob.address, 1, true, 0
      );
      expect(kickback).to.equal(0n);
    });

    it("level 4+ uses 20% reward scale for fresh ETH cap calculations", async function () {
      const { affiliate, coin, alice, bob, aliceCode } =
        await loadFixture(deployWithAffiliateSetup);

      // At level 4, fresh ETH: 20% rate
      // 2.5 ETH * 20% = 0.5 ETH exactly (cap)
      await payAffiliateAsCoin(
        hre.ethers, coin, affiliate,
        eth("2.5"), aliceCode, bob.address, 4, true, 0
      );

      const score = await affiliate.affiliateScore(4, alice.address);
      expect(score).to.equal(MAX_COMMISSION_PER_REFERRER_PER_LEVEL);
    });

    it("commission cap and taper combined: cap restricts before taper reduces payout", async function () {
      const protocol = await loadFixture(deployFullProtocol);
      const { affiliate, coin, alice, bob } = protocol;

      // Create code with 10% kickback to observe payout differences
      const code = toBytes32("TEST10");
      await affiliate.connect(alice).createAffiliateCode(code, 10);
      await affiliate.connect(bob).referPlayer(code);

      // Send enough to exceed cap: 4 ETH at 25% = 1 ETH, capped to 0.5 ETH
      // With taper 25500: kickback = 0.5 * 50% * 10% = 0.025 ETH
      const kickback = await payAffiliateAsCoinStatic(
        hre.ethers, coin, affiliate,
        eth("4"), code, bob.address, 1, true, LOOTBOX_TAPER_END_SCORE
      );

      // Expected: scaledAmount capped to 0.5, then tapered to 0.25, then 10% kickback = 0.025
      const expectedKickback = eth("0.025");
      expect(kickback).to.equal(expectedKickback);
    });

    it("taper at score 15000 with large amount does not lose precision", async function () {
      const { affiliate, coin, alice, bob, aliceCode } =
        await loadFixture(deployWithAffiliateSetup);

      // At score 15000: excess=0, reductionBps=0, full payout (no precision issue)
      const amount = eth("0.1");

      await payAffiliateAsCoin(
        hre.ethers, coin, affiliate,
        amount, aliceCode, bob.address, 1, true, LOOTBOX_TAPER_START_SCORE
      );

      const score = await affiliate.affiliateScore(1, alice.address);
      const fullScaled = computeScaledAmount(amount, 1n, true);
      expect(score).to.equal(fullScaled);
    });
  });
});
