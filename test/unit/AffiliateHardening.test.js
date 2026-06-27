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
 *   - 0.5 ETH FLIP cap per sender per affiliate per level
 *   - Cumulative tracking across multiple purchases
 *   - Cap resets at each new level
 *   - Independent caps per affiliate
 *
 * Lootbox Activity Taper (AFF-05 through AFF-09):
 *   - No taper below 10000 BPS score
 *   - Linear taper from 100% to 25% between 10000 and 25500 BPS
 *   - Floor at 25% payout above 25500 BPS
 *   - Leaderboard tracking uses post-taper amount
 *   - lootboxActivityScore parameter flows correctly
 */

// ---------------------------------------------------------------------------
// Constants (mirror contract values)
// ---------------------------------------------------------------------------

// The per-sender per-level 0.5 ETH commission cap was removed (perf(344)): the
// affiliate score now accrues the full scaled amount uncapped. This literal is
// retained only as the convenient 0.5-ETH value some scenarios still produce.
const MAX_COMMISSION_PER_REFERRER_PER_LEVEL = eth("0.5"); // 0.5 ether
const REWARD_SCALE_FRESH_L1_3_BPS = 2_500n; // 25%
const REWARD_SCALE_FRESH_L4P_BPS = 2_000n; // 20%
const REWARD_SCALE_RECYCLED_BPS = 500n; // 5%
const BPS_DENOMINATOR = 10_000n;
// Activity score is now whole points (v69 bps->points migration): taper starts
// at 100 points and floors at 255 points (was 10000/25500 BPS).
const LOOTBOX_TAPER_START_SCORE = 100;
const LOOTBOX_TAPER_END_SCORE = 255;
const LOOTBOX_TAPER_MIN_BPS = 2_500n;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function toBytes32(str) {
  return hre.ethers.encodeBytes32String(str);
}

/**
 * Call payAffiliate as the GAME contract via impersonation.
 * Returns the transaction receipt.
 */
async function payAffiliateAsGame(
  hreEthers,
  game,
  affiliate,
  amount,
  code,
  sender,
  lvl,
  isFreshEth,
  lootboxActivityScore = 0
) {
  const gameAddr = await game.getAddress();
  await hreEthers.provider.send("hardhat_impersonateAccount", [gameAddr]);
  await hreEthers.provider.send("hardhat_setBalance", [
    gameAddr,
    "0x1000000000000000000",
  ]);
  const gameSigner = await hreEthers.getSigner(gameAddr);
  const tx = await affiliate
    .connect(gameSigner)
    .payAffiliate(amount, code, sender, lvl, isFreshEth, lootboxActivityScore);
  await hreEthers.provider.send("hardhat_stopImpersonatingAccount", [gameAddr]);
  return tx;
}

/**
 * staticCall payAffiliate as game to get the return value without mutating.
 */
async function payAffiliateAsGameStatic(
  hreEthers,
  game,
  affiliate,
  amount,
  code,
  sender,
  lvl,
  isFreshEth,
  lootboxActivityScore = 0
) {
  const gameAddr = await game.getAddress();
  await hreEthers.provider.send("hardhat_impersonateAccount", [gameAddr]);
  await hreEthers.provider.send("hardhat_setBalance", [
    gameAddr,
    "0x1000000000000000000",
  ]);
  const gameSigner = await hreEthers.getSigner(gameAddr);
  const result = await affiliate
    .connect(gameSigner)
    .payAffiliate.staticCall(
      amount,
      code,
      sender,
      lvl,
      isFreshEth,
      lootboxActivityScore
    );
  await hreEthers.provider.send("hardhat_stopImpersonatingAccount", [gameAddr]);
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
  const { affiliate, game, coin, alice, bob, carol, dan, eve } = protocol;

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
  const { affiliate, game, coin, alice, bob, carol, dan } = protocol;

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

    // AFF-01: Affiliate earns at most 0.5 ETH FLIP from single sender per level
    describe("AFF-01: Single large purchase hits cap", function () {

      it("records full uncapped commission for a single large purchase", async function () {
        const { affiliate, game, coin, alice, bob, aliceCode } =
          await loadFixture(deployWithAffiliateSetup);

        // At level 1, fresh ETH: 25% reward rate
        // Send 4 ETH -> scaled = 1 ETH; the legacy 0.5 ETH cap was removed so
        // the full 1 ETH accrues to the affiliate score.
        const amount = eth("4");
        const lvl = 1;

        await payAffiliateAsGame(
          hre.ethers,
          game,
          affiliate,
          amount,
          aliceCode,
          bob.address,
          lvl,
          true, // freshEth
          0
        );

        // Alice's score is the full scaled amount (no cap)
        const score = await affiliate.affiliateScore(lvl, alice.address);
        expect(score).to.equal(eth("1"));
      });

      it("returns 0 kickback once cap is fully consumed (0% kickback code)", async function () {
        const { affiliate, game, coin, alice, bob, aliceCode } =
          await loadFixture(deployWithAffiliateSetup);

        // First call: exactly fill the cap
        await payAffiliateAsGame(
          hre.ethers, game, affiliate,
          eth("4"), aliceCode, bob.address, 1, true, 0
        );

        // Second call: cap already full, should return 0
        const kickback = await payAffiliateAsGameStatic(
          hre.ethers, game, affiliate,
          eth("1"), aliceCode, bob.address, 1, true, 0
        );
        expect(kickback).to.equal(0n);
      });

      it("emits AffiliateEarningsRecorded with the full scaled amount", async function () {
        const { affiliate, game, coin, alice, bob, aliceCode } =
          await loadFixture(deployWithAffiliateSetup);

        // 4 ETH at 25% = 1 ETH scaled; recorded in full (cap removed)
        const tx = await payAffiliateAsGame(
          hre.ethers, game, affiliate,
          eth("4"), aliceCode, bob.address, 1, true, 0
        );

        const events = await getEvents(tx, affiliate, "AffiliateEarningsRecorded");
        expect(events.length).to.equal(1);
        expect(events[0].args.amount).to.equal(eth("1"));
        expect(events[0].args.newTotal).to.equal(eth("1"));
      });

      it("allows exactly 0.5 ETH when scaled amount equals cap", async function () {
        const { affiliate, game, coin, alice, bob, aliceCode } =
          await loadFixture(deployWithAffiliateSetup);

        // At level 1, fresh ETH: 25% rate
        // 2 ETH * 25% = 0.5 ETH exactly
        await payAffiliateAsGame(
          hre.ethers, game, affiliate,
          eth("2"), aliceCode, bob.address, 1, true, 0
        );

        const score = await affiliate.affiliateScore(1, alice.address);
        expect(score).to.equal(MAX_COMMISSION_PER_REFERRER_PER_LEVEL);
      });

      it("allows full amount when scaled amount is below cap", async function () {
        const { affiliate, game, coin, alice, bob, aliceCode } =
          await loadFixture(deployWithAffiliateSetup);

        // 1 ETH * 25% = 0.25 ETH, well under cap
        await payAffiliateAsGame(
          hre.ethers, game, affiliate,
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
        const { affiliate, game, coin, alice, bob, aliceCode } =
          await loadFixture(deployWithAffiliateSetup);

        // 5 purchases of 0.4 ETH each at 25% = 0.1 ETH each -> 0.5 ETH total
        for (let i = 0; i < 5; i++) {
          await payAffiliateAsGame(
            hre.ethers, game, affiliate,
            eth("0.4"), aliceCode, bob.address, 1, true, 0
          );
        }

        const score = await affiliate.affiliateScore(1, alice.address);
        expect(score).to.equal(MAX_COMMISSION_PER_REFERRER_PER_LEVEL);
      });

      it("6th purchase keeps accruing (no cap)", async function () {
        const { affiliate, game, coin, alice, bob, aliceCode } =
          await loadFixture(deployWithAffiliateSetup);

        // 5 x 0.4 ETH at 25% = 5 x 0.1 = 0.5 ETH
        for (let i = 0; i < 5; i++) {
          await payAffiliateAsGame(
            hre.ethers, game, affiliate,
            eth("0.4"), aliceCode, bob.address, 1, true, 0
          );
        }

        const scoreBefore = await affiliate.affiliateScore(1, alice.address);

        // 6th purchase: cap removed, so it adds another 0.1 ETH
        await payAffiliateAsGame(
          hre.ethers, game, affiliate,
          eth("0.4"), aliceCode, bob.address, 1, true, 0
        );

        const scoreAfter = await affiliate.affiliateScore(1, alice.address);
        expect(scoreAfter).to.equal(scoreBefore + eth("0.1"));
        expect(scoreAfter).to.equal(eth("0.6"));
      });

      it("partial fill then large purchase accrues both in full (no clamp)", async function () {
        const { affiliate, game, coin, alice, bob, aliceCode } =
          await loadFixture(deployWithAffiliateSetup);

        // First: 0.8 ETH at 25% = 0.2 ETH
        await payAffiliateAsGame(
          hre.ethers, game, affiliate,
          eth("0.8"), aliceCode, bob.address, 1, true, 0
        );

        const scoreAfterFirst = await affiliate.affiliateScore(1, alice.address);
        expect(scoreAfterFirst).to.equal(eth("0.2"));

        // Second: 4 ETH at 25% = 1 ETH; no cap so the full 1 ETH is added
        await payAffiliateAsGame(
          hre.ethers, game, affiliate,
          eth("4"), aliceCode, bob.address, 1, true, 0
        );

        const scoreAfterSecond = await affiliate.affiliateScore(1, alice.address);
        expect(scoreAfterSecond).to.equal(eth("1.2"));
      });

      it("recycled ETH purchases also accumulate toward the same cap", async function () {
        const { affiliate, game, coin, alice, bob, aliceCode } =
          await loadFixture(deployWithAffiliateSetup);

        // Recycled ETH at 5% rate: 10 ETH * 5% = 0.5 ETH -> exactly cap
        await payAffiliateAsGame(
          hre.ethers, game, affiliate,
          eth("10"), aliceCode, bob.address, 1, false, 0
        );

        const score = await affiliate.affiliateScore(1, alice.address);
        expect(score).to.equal(MAX_COMMISSION_PER_REFERRER_PER_LEVEL);
      });

      it("mixed fresh and recycled ETH purchases share the same cap", async function () {
        const { affiliate, game, coin, alice, bob, aliceCode } =
          await loadFixture(deployWithAffiliateSetup);

        // Fresh: 1 ETH * 25% = 0.25 ETH
        await payAffiliateAsGame(
          hre.ethers, game, affiliate,
          eth("1"), aliceCode, bob.address, 1, true, 0
        );

        // Recycled: 5 ETH * 5% = 0.25 ETH -> total 0.5 ETH = cap
        await payAffiliateAsGame(
          hre.ethers, game, affiliate,
          eth("5"), aliceCode, bob.address, 1, false, 0
        );

        const score = await affiliate.affiliateScore(1, alice.address);
        expect(score).to.equal(MAX_COMMISSION_PER_REFERRER_PER_LEVEL);
      });
    });

    // AFF-03: Cap resets per level
    describe("AFF-03: Cap resets at each new level", function () {

      it("same sender/affiliate pair earns again at a different level", async function () {
        const { affiliate, game, coin, alice, bob, aliceCode } =
          await loadFixture(deployWithAffiliateSetup);

        // Earn at level 1 (4 ETH * 25% = 1 ETH, uncapped)
        await payAffiliateAsGame(
          hre.ethers, game, affiliate,
          eth("4"), aliceCode, bob.address, 1, true, 0
        );
        const scoreL1 = await affiliate.affiliateScore(1, alice.address);
        expect(scoreL1).to.equal(eth("1"));

        // Level 2: independent per-level tracking, should earn again
        await payAffiliateAsGame(
          hre.ethers, game, affiliate,
          eth("1"), aliceCode, bob.address, 2, true, 0
        );
        const scoreL2 = await affiliate.affiliateScore(2, alice.address);
        const expectedL2 = computeScaledAmount(eth("1"), 2n, true);
        expect(scoreL2).to.equal(expectedL2);
        expect(scoreL2).to.be.gt(0n);
      });

      it("cap at level 1 does not affect level 0 earnings", async function () {
        const { affiliate, game, coin, alice, bob, aliceCode } =
          await loadFixture(deployWithAffiliateSetup);

        // Fill cap at level 1
        await payAffiliateAsGame(
          hre.ethers, game, affiliate,
          eth("4"), aliceCode, bob.address, 1, true, 0
        );

        // Earn at level 0 independently
        await payAffiliateAsGame(
          hre.ethers, game, affiliate,
          eth("1"), aliceCode, bob.address, 0, true, 0
        );

        const scoreL0 = await affiliate.affiliateScore(0, alice.address);
        const expectedL0 = computeScaledAmount(eth("1"), 0n, true);
        expect(scoreL0).to.equal(expectedL0);
      });

      it("accrues independently at multiple levels", async function () {
        const { affiliate, game, coin, alice, bob, aliceCode } =
          await loadFixture(deployWithAffiliateSetup);

        // Earn at levels 1, 2, and 5 (uncapped; rate is 25% at lvl<=3, 20% at lvl>3)
        for (const lvl of [1, 2, 5]) {
          await payAffiliateAsGame(
            hre.ethers, game, affiliate,
            eth("4"), aliceCode, bob.address, lvl, true, 0
          );
        }

        for (const lvl of [1, 2, 5]) {
          const score = await affiliate.affiliateScore(lvl, alice.address);
          expect(score).to.equal(computeScaledAmount(eth("4"), BigInt(lvl), true));
        }
      });
    });

    // AFF-04: Cap is per-affiliate (different affiliates have independent caps)
    describe("AFF-04: Independent caps per affiliate", function () {

      it("two affiliates each accrue independently from different senders", async function () {
        const { affiliate, game, coin, alice, bob, carol, dan, aliceCode, carolCode } =
          await loadFixture(deployWithTwoAffiliates);

        // Bob -> Alice
        await payAffiliateAsGame(
          hre.ethers, game, affiliate,
          eth("4"), aliceCode, bob.address, 1, true, 0
        );

        // Dan -> Carol
        await payAffiliateAsGame(
          hre.ethers, game, affiliate,
          eth("4"), carolCode, dan.address, 1, true, 0
        );

        const aliceScore = await affiliate.affiliateScore(1, alice.address);
        const carolScore = await affiliate.affiliateScore(1, carol.address);
        expect(aliceScore).to.equal(eth("1"));
        expect(carolScore).to.equal(eth("1"));
      });

      it("alice earnings do not affect carol earning from a different sender", async function () {
        const { affiliate, game, coin, alice, bob, carol, dan, aliceCode, carolCode } =
          await loadFixture(deployWithTwoAffiliates);

        // Bob -> Alice
        await payAffiliateAsGame(
          hre.ethers, game, affiliate,
          eth("4"), aliceCode, bob.address, 1, true, 0
        );

        // Bob -> Alice again: adds another 1 * 25% = 0.25 ETH (no cap)
        await payAffiliateAsGame(
          hre.ethers, game, affiliate,
          eth("1"), aliceCode, bob.address, 1, true, 0
        );
        const aliceScore = await affiliate.affiliateScore(1, alice.address);
        expect(aliceScore).to.equal(eth("1.25"));

        // Dan -> Carol: still has full cap
        await payAffiliateAsGame(
          hre.ethers, game, affiliate,
          eth("1"), carolCode, dan.address, 1, true, 0
        );
        const carolScore = await affiliate.affiliateScore(1, carol.address);
        expect(carolScore).to.equal(computeScaledAmount(eth("1"), 1n, true));
        expect(carolScore).to.be.gt(0n);
      });

      it("same affiliate tracks caps independently per sender", async function () {
        const { affiliate, game, coin, alice, bob, carol, eve, aliceCode } =
          await loadFixture(deployWithAffiliateSetup);

        // Carol also refers to Alice
        await affiliate.connect(carol).referPlayer(aliceCode);

        // Bob -> Alice
        await payAffiliateAsGame(
          hre.ethers, game, affiliate,
          eth("4"), aliceCode, bob.address, 1, true, 0
        );

        // Carol -> Alice (different sender, accrues to the same affiliate)
        await payAffiliateAsGame(
          hre.ethers, game, affiliate,
          eth("4"), aliceCode, carol.address, 1, true, 0
        );

        // Alice earned 1 ETH from bob + 1 ETH from carol = 2.0 total (no cap)
        const aliceScore = await affiliate.affiliateScore(1, alice.address);
        expect(aliceScore).to.equal(eth("2"));
      });
    });
  });

  // =========================================================================
  // Lootbox Activity Taper
  // =========================================================================
  describe("Lootbox Activity Taper", function () {

    // AFF-05: No taper below 10000 BPS
    describe("AFF-05: No taper when score < 10000 BPS", function () {

      it("score 0: full payout, no taper", async function () {
        const { affiliate, game, coin, alice, bob, aliceCode } =
          await loadFixture(deployWithAffiliateSetup);

        const amount = eth("1");
        await payAffiliateAsGame(
          hre.ethers, game, affiliate,
          amount, aliceCode, bob.address, 1, true, 0
        );

        const score = await affiliate.affiliateScore(1, alice.address);
        const expected = computeScaledAmount(amount, 1n, true);
        expect(score).to.equal(expected);
      });

      it("score 99: still full payout, no taper", async function () {
        const { affiliate, game, coin, alice, bob, aliceCode } =
          await loadFixture(deployWithAffiliateSetup);

        const amount = eth("1");
        await payAffiliateAsGame(
          hre.ethers, game, affiliate,
          amount, aliceCode, bob.address, 1, true, 99
        );

        // Leaderboard records full amount (99 < 100, so no taper applies)
        const score = await affiliate.affiliateScore(1, alice.address);
        const expected = computeScaledAmount(amount, 1n, true);
        expect(score).to.equal(expected);
      });

      it("score 1: no taper applied", async function () {
        const { affiliate, game, coin, alice, bob, aliceCode } =
          await loadFixture(deployWithAffiliateSetup);

        const amount = eth("0.5");
        await payAffiliateAsGame(
          hre.ethers, game, affiliate,
          amount, aliceCode, bob.address, 2, true, 1
        );

        const score = await affiliate.affiliateScore(2, alice.address);
        const expected = computeScaledAmount(amount, 2n, true);
        expect(score).to.equal(expected);
      });
    });

    // AFF-06: Linear taper from 100% to 25% between 10000-25500 BPS
    describe("AFF-06: Linear taper in 10000-25500 BPS range", function () {

      it("score exactly 10000: no reduction (taper just starts)", async function () {
        const { affiliate, game, coin, alice, bob, aliceCode } =
          await loadFixture(deployWithAffiliateSetup);

        // Use small amount so cap does not interfere
        const amount = eth("0.1");
        const lvl = 1;

        // We use two calls: one with score 0, one with score 15000
        // Compare events to verify the tapered payout amount
        const tx = await payAffiliateAsGame(
          hre.ethers, game, affiliate,
          amount, aliceCode, bob.address, lvl, true, LOOTBOX_TAPER_START_SCORE
        );

        // Leaderboard always gets full amount
        const score = await affiliate.affiliateScore(lvl, alice.address);
        const fullScaled = computeScaledAmount(amount, BigInt(lvl), true);
        expect(score).to.equal(fullScaled);

        // At exactly 10000, excess=0 so reductionBps=0, full payout
        // The taper condition is: score >= LOOTBOX_TAPER_START_SCORE
        // At 10000: excess=0, so (7500*0)/15500 = 0, taper = amt * 10000/10000 = full
        // So payout equals untapered amount
      });

      it("score 177 (midpoint): partial linear taper between full and the 25% floor", async function () {
        const { affiliate, game, coin, alice, bob, aliceCode } =
          await loadFixture(deployWithAffiliateSetup);

        const amount = eth("0.1");
        const lvl = 1;
        const midScore = 177; // ~halfway between 100 and 255

        // Compute expected taper (mirrors the contract math)
        const fullScaled = computeScaledAmount(amount, BigInt(lvl), true);
        const expectedTapered = computeTaperedAmount(fullScaled, midScore);

        // Mid-range: strictly below the full amount and strictly above the 25% floor
        expect(expectedTapered).to.be.lt(fullScaled);
        expect(expectedTapered).to.be.gt(
          (fullScaled * LOOTBOX_TAPER_MIN_BPS) / BPS_DENOMINATOR
        );

        await payAffiliateAsGame(
          hre.ethers, game, affiliate,
          amount, aliceCode, bob.address, lvl, true, midScore
        );

        // Leaderboard records the post-taper amount
        const score = await affiliate.affiliateScore(lvl, alice.address);
        expect(score).to.equal(expectedTapered);
      });

      it("score 101: small reduction just above the taper start", async function () {
        const { affiliate, game, coin, alice, bob, aliceCode } =
          await loadFixture(deployWithAffiliateSetup);

        const amount = eth("1");
        const fullScaled = computeScaledAmount(amount, 1n, true);
        const tapered = computeTaperedAmount(fullScaled, 101);

        // Just above the 100-point start: excess=1, range=155
        // reductionBps = 7500 * 1 / 155 = 48 (integer), a sub-1% reduction
        expect(tapered).to.be.lt(fullScaled);
        expect(tapered).to.be.gt((fullScaled * 99n) / 100n);
      });

      it("score 254: just below floor, slightly above 25%", async function () {
        const { affiliate, game, coin, alice, bob, aliceCode } =
          await loadFixture(deployWithAffiliateSetup);

        const amount = eth("1");
        const fullScaled = computeScaledAmount(amount, 1n, true);
        const tapered = computeTaperedAmount(fullScaled, 254);

        // excess=154, range=155
        // reductionBps = 7500 * 154 / 155 = 7451 (integer)
        // payout = amt * (10000-7451)/10000
        const expectedReductionBps = (7500n * 154n) / 155n;
        const expectedPayout = (fullScaled * (10000n - expectedReductionBps)) / 10000n;
        expect(tapered).to.equal(expectedPayout);
        // Confirm it's slightly above 25%
        expect(tapered).to.be.gt((fullScaled * LOOTBOX_TAPER_MIN_BPS) / BPS_DENOMINATOR);
      });
    });

    // AFF-07: Floor at 25% payout when score >= 25500
    describe("AFF-07: Floor at 25% for score >= 25500 BPS", function () {

      it("score exactly 25500: 25% payout floor", async function () {
        const { affiliate, game, coin, alice, bob, aliceCode } =
          await loadFixture(deployWithAffiliateSetup);

        const amount = eth("0.1");
        const fullScaled = computeScaledAmount(amount, 1n, true);
        const expected25pct = (fullScaled * LOOTBOX_TAPER_MIN_BPS) / BPS_DENOMINATOR;

        await payAffiliateAsGame(
          hre.ethers, game, affiliate,
          amount, aliceCode, bob.address, 1, true, LOOTBOX_TAPER_END_SCORE
        );

        // Leaderboard records the post-taper (25% floor) amount
        const score = await affiliate.affiliateScore(1, alice.address);
        expect(score).to.equal(expected25pct);

        // Confirm the 25% floor: tapered = fullScaled / 4
        expect(expected25pct).to.equal(fullScaled / 4n);
      });

      it("score 30000: still 25% floor (no further reduction)", async function () {
        const { affiliate, game, coin, alice, bob, aliceCode } =
          await loadFixture(deployWithAffiliateSetup);

        const amount = eth("0.1");
        const fullScaled = computeScaledAmount(amount, 1n, true);
        const tapered = computeTaperedAmount(fullScaled, 30000);
        const expected25pct = (fullScaled * LOOTBOX_TAPER_MIN_BPS) / BPS_DENOMINATOR;

        expect(tapered).to.equal(expected25pct);
      });

      it("score 65535 (max uint16): still 25% floor", async function () {
        const { affiliate, game, coin, alice, bob, aliceCode } =
          await loadFixture(deployWithAffiliateSetup);

        const amount = eth("0.1");
        const fullScaled = computeScaledAmount(amount, 1n, true);
        const tapered = computeTaperedAmount(fullScaled, 65535);
        const expected25pct = (fullScaled * LOOTBOX_TAPER_MIN_BPS) / BPS_DENOMINATOR;

        expect(tapered).to.equal(expected25pct);

        // Also execute on-chain to verify it does not revert
        await payAffiliateAsGame(
          hre.ethers, game, affiliate,
          amount, aliceCode, bob.address, 1, true, 65535
        );

        const score = await affiliate.affiliateScore(1, alice.address);
        expect(score).to.equal(expected25pct);
      });
    });

    // AFF-08: Leaderboard tracking uses post-taper amount
    describe("AFF-08: Leaderboard uses post-taper amount", function () {

      it("leaderboard score matches post-taper scaled amount when heavily tapered", async function () {
        const { affiliate, game, coin, alice, bob, aliceCode } =
          await loadFixture(deployWithAffiliateSetup);

        const amount = eth("0.1");
        const lvl = 1;

        // Pay with maximum taper (score >= 25500 -> 25% floor)
        await payAffiliateAsGame(
          hre.ethers, game, affiliate,
          amount, aliceCode, bob.address, lvl, true, LOOTBOX_TAPER_END_SCORE
        );

        const fullScaled = computeScaledAmount(amount, BigInt(lvl), true);
        const score = await affiliate.affiliateScore(lvl, alice.address);
        const expected25pct = (fullScaled * LOOTBOX_TAPER_MIN_BPS) / BPS_DENOMINATOR;

        // Leaderboard reflects the post-taper (25% floor) amount
        expect(score).to.equal(expected25pct);
        // Not the full untapered amount
        expect(score).to.not.equal(fullScaled);
      });

      it("AffiliateEarningsRecorded event emits post-taper amount", async function () {
        const { affiliate, game, coin, alice, bob, aliceCode } =
          await loadFixture(deployWithAffiliateSetup);

        const amount = eth("0.1");
        const lvl = 2;
        const fullScaled = computeScaledAmount(amount, BigInt(lvl), true);
        // score=25500 triggers 25% floor: tapered = fullScaled * 2500 / 10000
        const taperedScaled = computeTaperedAmount(fullScaled, 25500);

        const tx = await payAffiliateAsGame(
          hre.ethers, game, affiliate,
          amount, aliceCode, bob.address, lvl, true, 25500
        );

        const events = await getEvents(tx, affiliate, "AffiliateEarningsRecorded");
        expect(events.length).to.equal(1);
        // The emitted amount is the post-taper scaled amount
        expect(events[0].args.amount).to.equal(taperedScaled);
        expect(events[0].args.newTotal).to.equal(taperedScaled);
      });

      it("top affiliate tracks post-taper cumulative across multiple tapered calls", async function () {
        const { affiliate, game, coin, alice, bob, aliceCode } =
          await loadFixture(deployWithAffiliateSetup);

        const amount = eth("0.1");
        const lvl = 1;
        const fullScaled = computeScaledAmount(amount, BigInt(lvl), true);
        // score=200: mid-range taper (mirrors the contract math)
        const taperedOnce = computeTaperedAmount(fullScaled, 200);

        // 3 purchases each with the same taper
        for (let i = 0; i < 3; i++) {
          await payAffiliateAsGame(
            hre.ethers, game, affiliate,
            amount, aliceCode, bob.address, lvl, true, 200
          );
        }

        const score = await affiliate.affiliateScore(lvl, alice.address);
        // Should be 3 x taperedOnce (post-taper accumulation)
        expect(score).to.equal(taperedOnce * 3n);
      });
    });

    // AFF-09: lootboxActivityScore parameter flows correctly through payAffiliate
    describe("AFF-09: lootboxActivityScore parameter flow", function () {

      it("score=0 produces same result as no-taper baseline", async function () {
        const { affiliate, game, coin, alice, bob, aliceCode } =
          await loadFixture(deployWithAffiliateSetup);

        const amount = eth("0.1");
        const lvl = 1;

        await payAffiliateAsGame(
          hre.ethers, game, affiliate,
          amount, aliceCode, bob.address, lvl, true, 0
        );

        const score = await affiliate.affiliateScore(lvl, alice.address);
        const fullScaled = computeScaledAmount(amount, BigInt(lvl), true);
        expect(score).to.equal(fullScaled);
      });

      it("taper applies to recycled ETH purchases (parameter is always respected)", async function () {
        const { affiliate, game, coin, alice, bob, aliceCode } =
          await loadFixture(deployWithAffiliateSetup);

        const amount = eth("1");
        const lvl = 1;

        // Recycled ETH at 5% with high taper score
        await payAffiliateAsGame(
          hre.ethers, game, affiliate,
          amount, aliceCode, bob.address, lvl, false, 25500
        );

        const score = await affiliate.affiliateScore(lvl, alice.address);
        const fullScaled = computeScaledAmount(amount, BigInt(lvl), false);
        // score=25500 triggers 25% floor: leaderboard records post-taper amount
        const taperedScaled = computeTaperedAmount(fullScaled, 25500);
        expect(score).to.equal(taperedScaled);
      });

      it("different taper scores produce different payout amounts for same input", async function () {
        // We verify via kickback amounts with a non-zero kickback affiliate
        const protocol = await loadFixture(deployFullProtocol);
        const { affiliate, game, coin, alice, bob, carol, dan, eve } = protocol;

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
        const kickbackNoTaper = await payAffiliateAsGameStatic(
          hre.ethers, game, affiliate,
          amount, code, bob.address, lvl, true, 0
        );

        // Carol pays with max taper (score=25500 -> 25% floor)
        const kickbackMaxTaper = await payAffiliateAsGameStatic(
          hre.ethers, game, affiliate,
          amount, code, carol.address, lvl, true, LOOTBOX_TAPER_END_SCORE
        );

        // Kickback should be different: tapered = 25% of untapered
        expect(kickbackNoTaper).to.be.gt(0n);
        expect(kickbackMaxTaper).to.be.gt(0n);
        expect(kickbackMaxTaper).to.equal(kickbackNoTaper / 4n);
      });

      it("taper applies to the full uncapped scaled amount, accumulating with prior", async function () {
        const { affiliate, game, coin, alice, bob, aliceCode } =
          await loadFixture(deployWithAffiliateSetup);

        // First: 0.8 ETH at 25% = 0.2 ETH (no taper)
        await payAffiliateAsGame(
          hre.ethers, game, affiliate,
          eth("0.8"), aliceCode, bob.address, 1, true, 0
        );

        // Second: 4 ETH at 25% = 1.0 scaled (no cap); taper floor 25% -> 0.25 ETH
        await payAffiliateAsGame(
          hre.ethers, game, affiliate,
          eth("4"), aliceCode, bob.address, 1, true, LOOTBOX_TAPER_END_SCORE
        );

        const score = await affiliate.affiliateScore(1, alice.address);
        // 0.2 (untapered from call 1) + 0.25 (floored from call 2) = 0.45 ETH
        expect(score).to.equal(eth("0.45"));
      });
    });
  });

  // =========================================================================
  // Edge Cases & Combined Scenarios
  // =========================================================================
  describe("Edge Cases", function () {

    it("zero amount produces no commission and no revert", async function () {
      const { affiliate, game, coin, alice, bob, aliceCode } =
        await loadFixture(deployWithAffiliateSetup);

      await payAffiliateAsGame(
        hre.ethers, game, affiliate,
        0n, aliceCode, bob.address, 1, true, 0
      );

      const score = await affiliate.affiliateScore(1, alice.address);
      expect(score).to.equal(0n);
    });

    it("very small amount (1 wei) does not revert", async function () {
      const { affiliate, game, coin, alice, bob, aliceCode } =
        await loadFixture(deployWithAffiliateSetup);

      // 1 wei * 2500 / 10000 = 0 (rounds to zero) -> returns early
      await payAffiliateAsGame(
        hre.ethers, game, affiliate,
        1n, aliceCode, bob.address, 1, true, 0
      );

      const score = await affiliate.affiliateScore(1, alice.address);
      expect(score).to.equal(0n);
    });

    it("cap boundary: exact cap fill then exact 0 on next call", async function () {
      const { affiliate, game, coin, alice, bob, aliceCode } =
        await loadFixture(deployWithAffiliateSetup);

      // Exact 0.5 ETH: 2 ETH * 25% = 0.5 ETH
      await payAffiliateAsGame(
        hre.ethers, game, affiliate,
        eth("2"), aliceCode, bob.address, 1, true, 0
      );

      // Even tiny additional amount yields 0
      const kickback = await payAffiliateAsGameStatic(
        hre.ethers, game, affiliate,
        1n, aliceCode, bob.address, 1, true, 0
      );
      expect(kickback).to.equal(0n);
    });

    it("level 4+ uses 20% reward scale for fresh ETH cap calculations", async function () {
      const { affiliate, game, coin, alice, bob, aliceCode } =
        await loadFixture(deployWithAffiliateSetup);

      // At level 4, fresh ETH: 20% rate
      // 2.5 ETH * 20% = 0.5 ETH exactly (cap)
      await payAffiliateAsGame(
        hre.ethers, game, affiliate,
        eth("2.5"), aliceCode, bob.address, 4, true, 0
      );

      const score = await affiliate.affiliateScore(4, alice.address);
      expect(score).to.equal(MAX_COMMISSION_PER_REFERRER_PER_LEVEL);
    });

    it("taper then kickback on the full uncapped scaled amount", async function () {
      const protocol = await loadFixture(deployFullProtocol);
      const { affiliate, game, coin, alice, bob } = protocol;

      // Create code with 10% kickback to observe payout differences
      const code = toBytes32("TEST10");
      await affiliate.connect(alice).createAffiliateCode(code, 10);
      await affiliate.connect(bob).referPlayer(code);

      // 4 ETH at 25% = 1 ETH scaled (no cap)
      // With taper floor 25%: scaled -> 0.25 ETH, then 10% kickback = 0.025 ETH
      const kickback = await payAffiliateAsGameStatic(
        hre.ethers, game, affiliate,
        eth("4"), code, bob.address, 1, true, LOOTBOX_TAPER_END_SCORE
      );

      // Expected: 1 ETH scaled, tapered to 0.25, then 10% kickback = 0.025
      const expectedKickback = eth("0.025");
      expect(kickback).to.equal(expectedKickback);
    });

    it("taper at score 10000 with large amount does not lose precision", async function () {
      const { affiliate, game, coin, alice, bob, aliceCode } =
        await loadFixture(deployWithAffiliateSetup);

      // At score 10000: excess=0, reductionBps=0, full payout (no precision issue)
      const amount = eth("0.1");

      await payAffiliateAsGame(
        hre.ethers, game, affiliate,
        amount, aliceCode, bob.address, 1, true, LOOTBOX_TAPER_START_SCORE
      );

      const score = await affiliate.affiliateScore(1, alice.address);
      const fullScaled = computeScaledAmount(amount, 1n, true);
      expect(score).to.equal(fullScaled);
    });
  });
});
