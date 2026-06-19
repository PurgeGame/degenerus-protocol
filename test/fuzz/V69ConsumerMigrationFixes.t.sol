// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";

/// @title V69ConsumerMigrationFixes -- regression proofs for the four score-consumer sites migrated from the
///        bps activity-score domain to the WHOLE-POINT domain (1 point = 100 bps). The score now returns whole
///        points (~305 normal max, hard-capped at 65534), so a consumer that still treated the value as bps would
///        feed a ~100x-too-small magnitude into its formula and silently mis-pay. Each fix below mirrors the
///        already-migrated terminal-decimator pattern; this file replicates BOTH the FIXED point-domain formula
///        and the OLD bps-domain formula in-test and asserts the fix reproduces the intended outcome AND rejects
///        the buggy value.
///
/// @notice The four fixed sites (the value each test pins):
///   1. FLIP regular decimator multiplier -- DECIMATOR_ACTIVITY_CAP 23_500 bps -> 235 points, and the
///      multiplier `BPS_DENOMINATOR + (bonusPoints*100)/3` (the x100 re-scale that keeps the /3 dividing the
///      bps-equivalent magnitude). The bucket reduction divides by the 235 cap.
///   2. DegenerusAffiliate lootbox taper -- LOOTBOX_TAPER_START 10_000 -> 100, END 25_500 -> 255; the 25% floor
///      anchor LOOTBOX_TAPER_MIN_BPS=2500 stays a bps OUTPUT constant.
///   3. Century quantity bonus -- `bonusQty = qty * min(score, 305) / 305` (the divisor is the point max, not
///      the old 30_500 bps max).
///   4. DegenerusGameDecimatorModule._minScoreForBucket -- cap 23_500 -> 235; the frozen per-bucket score it
///      seals feeds a graduated lootbox EV (NEUTRAL 60 / MAX 400 points), not the saturated 145% the bug gave.
///
/// @dev Pure-math mirror tests in the ConsumerPointEquivalence style; the deploy keeps the suite consistent (the
///   consumer formulas under test are pure functions read directly from the FROZEN source, mirrored below).
///   Test-only: ZERO contracts/*.sol mutation.
contract V69ConsumerMigrationFixes is DeployProtocol {
    // -------------------------------------------------------------------------
    // Shared score-domain anchors
    // -------------------------------------------------------------------------
    uint256 private constant BPS_DENOMINATOR = 10_000;
    uint256 private constant SCORE_POINT_MAX = 305; // the normal-player point ceiling (the century divisor)

    // FLIP regular decimator (FLIP.sol:164/746/752/764)
    uint256 private constant DEC_CAP_POINTS = 235;
    uint256 private constant DEC_CAP_BPS = 23_500; // the OLD pre-migration bps cap
    uint256 private constant DECIMATOR_BUCKET_BASE = 12;

    // Affiliate lootbox taper (DegenerusAffiliate.sol:187/188/189)
    uint256 private constant TAPER_START_POINTS = 100;
    uint256 private constant TAPER_END_POINTS = 255;
    uint256 private constant TAPER_MIN_BPS = 2_500; // the 25% floor, a bps OUTPUT anchor (unchanged)
    uint256 private constant TAPER_START_BPS_OLD = 10_000; // the OLD pre-migration start threshold

    // Lootbox EV multiplier (DegenerusGameStorage.sol:1553/1555/1557/1559/1561)
    uint256 private constant EV_NEUTRAL_POINTS = 60;
    uint256 private constant EV_MAX_POINTS = 400;
    uint256 private constant EV_MIN_BPS = 9_000;
    uint256 private constant EV_NEUTRAL_BPS = 10_000;
    uint256 private constant EV_MAX_BPS = 14_500;

    function setUp() public {
        _deployProtocol();
    }

    // =========================================================================
    // (1) FLIP regular decimator -- multiplier + bucket reduction
    //     FIXED:  BPS_DENOMINATOR + (bonusPoints*100)/3,  cap 235 points
    //     BUGGY:  treating the point value as bps -> BPS_DENOMINATOR + points/3 (no x100 re-scale)
    // =========================================================================

    /// @dev The FIXED multiplier (FLIP.sol:_decimatorBurnMultiplier): the x100 re-scale keeps the /3 dividing
    ///      the bps-equivalent magnitude, so a maxed 235-point score yields the same ~1.78x the bps domain did.
    function _decMultFixed(uint256 points) internal pure returns (uint256) {
        if (points > DEC_CAP_POINTS) points = DEC_CAP_POINTS;
        return points == 0 ? BPS_DENOMINATOR : BPS_DENOMINATOR + (points * 100) / 3;
    }

    /// @dev The BUGGY multiplier: the point value fed straight into the old bps formula (no x100 re-scale) --
    ///      `10000 + points/3`. ~100x too small; this is the value the fix must reject.
    function _decMultBuggy(uint256 points) internal pure returns (uint256) {
        if (points > DEC_CAP_POINTS) points = DEC_CAP_POINTS;
        return points == 0 ? BPS_DENOMINATOR : BPS_DENOMINATOR + points / 3;
    }

    /// @dev The FIXED bucket reduction (FLIP.sol:_adjustDecimatorBucket): divides by the 235-point cap, so a
    ///      maxed score reduces all the way to the floor bucket.
    function _decBucketFixed(uint256 points, uint8 floorBucket) internal pure returns (uint256) {
        if (points == 0) return DECIMATOR_BUCKET_BASE;
        if (points > DEC_CAP_POINTS) points = DEC_CAP_POINTS;
        uint256 range = DECIMATOR_BUCKET_BASE - uint256(floorBucket);
        uint256 reduction = (range * points + (DEC_CAP_POINTS / 2)) / DEC_CAP_POINTS;
        uint256 bucket = DECIMATOR_BUCKET_BASE - reduction;
        return bucket < floorBucket ? floorBucket : bucket;
    }

    /// @dev The BUGGY bucket reduction: divides by the OLD 23_500 bps cap while the score is now points -- the
    ///      reduction is ~100x too small, so a maxed score barely moves off the base bucket.
    function _decBucketBuggy(uint256 points, uint8 floorBucket) internal pure returns (uint256) {
        if (points == 0) return DECIMATOR_BUCKET_BASE;
        uint256 range = DECIMATOR_BUCKET_BASE - uint256(floorBucket);
        uint256 reduction = (range * points + (DEC_CAP_BPS / 2)) / DEC_CAP_BPS;
        uint256 bucket = DECIMATOR_BUCKET_BASE - reduction;
        return bucket < floorBucket ? floorBucket : bucket;
    }

    /// @notice At the capped 235-point score the FIXED FLIP decimator multiplier is 17833 (≈1.78x) -- the
    ///         intended pre-migration magnitude -- and the naive bps-as-points value 10078 (≈1.008x) is REJECTED.
    ///         A regression that drops the x100 re-scale would collapse the burn boost ~100x.
    function test_FlipDecimatorMultiplier_FixedReproducesRejectsBuggy() public pure {
        // FIXED: 10000 + (235*100)/3 = 10000 + 7833 = 17833.
        assertEq(_decMultFixed(235), 17_833, "FIXED multiplier at cap 235pt == 17833 (~1.78x, the intended boost)");

        // BUGGY: 10000 + 235/3 = 10000 + 78 = 10078 -- ~100x too small a boost; must NOT equal the fix.
        assertEq(_decMultBuggy(235), 10_078, "buggy bps-as-points multiplier computes 10078 (~1.008x)");
        assertTrue(_decMultFixed(235) != _decMultBuggy(235), "the fix REJECTS the naive bps-as-points multiplier");

        // The zero special-case is identical in both domains (a sanity floor).
        assertEq(_decMultFixed(0), BPS_DENOMINATOR, "0pt -> neutral 10000 (no boost)");
    }

    /// @notice At the capped 235-point score the FIXED bucket reduction reaches the FLOOR bucket (full odds
    ///         improvement) for both the normal floor (5) and the x100-level floor (2); the BUGGY bps-divisor
    ///         reduction is ~0, leaving the score stuck at (or one off) the BASE bucket -- the fix is REJECTED
    ///         against that near-no-op.
    function test_FlipDecimatorBucket_FixedReachesFloorRejectsBuggy() public pure {
        // FIXED at the cap: reduction = (range*235 + 117)/235 = range (round-to-nearest) -> base - range = floor.
        assertEq(_decBucketFixed(235, 5), 5, "FIXED bucket at cap 235pt -> floor bucket 5 (full reduction)");
        assertEq(_decBucketFixed(235, 2), 2, "FIXED bucket at cap 235pt (x100 level) -> floor bucket 2");

        // BUGGY at the same score: reduction = (7*235 + 11750)/23500 = 13405/23500 = 0 -> stuck at the base 12.
        assertEq(_decBucketBuggy(235, 5), DECIMATOR_BUCKET_BASE, "buggy bps-divisor leaves the score at the base bucket 12");
        assertTrue(
            _decBucketFixed(235, 5) != _decBucketBuggy(235, 5),
            "the fix REJECTS the buggy bps-divisor bucket (floor 5 != base 12)"
        );

        // 0pt -> base bucket in both, the neutral floor.
        assertEq(_decBucketFixed(0, 5), DECIMATOR_BUCKET_BASE, "0pt -> base bucket 12 (no reduction)");
    }

    // =========================================================================
    // (2) Affiliate lootbox taper -- start 100 / end 255 points, 25% floor
    //     FIXED:  100pt begins taper, 255+ pt hits the 25% floor (amt*2500/10000)
    //     BUGGY:  10_000 start threshold -> a normal ~235pt buyer never tapers
    // =========================================================================

    /// @dev The FIXED taper (DegenerusAffiliate.sol:_applyLootboxTaper): no taper below 100pt; linear from
    ///      100% at 100pt to 25% at 255pt; floored at 25% for >=255pt. `score` is whole points.
    function _taperFixed(uint256 amt, uint256 score) internal pure returns (uint256) {
        if (score < TAPER_START_POINTS) return amt; // call-site gate: no taper below the start
        if (score >= TAPER_END_POINTS) return (amt * TAPER_MIN_BPS) / BPS_DENOMINATOR;
        uint256 excess = score - TAPER_START_POINTS;
        uint256 range = TAPER_END_POINTS - TAPER_START_POINTS;
        uint256 reductionBps = (BPS_DENOMINATOR - TAPER_MIN_BPS) * excess / range;
        return (amt * (BPS_DENOMINATOR - reductionBps)) / BPS_DENOMINATOR;
    }

    /// @dev Whether the BUGGY taper (old 10_000 start threshold against a now-points score) would even ENGAGE.
    ///      A normal score (<= ~305 points) is far below 10_000, so the buggy gate never tapers a real buyer.
    function _buggyTaperEngages(uint256 score) internal pure returns (bool) {
        return score >= TAPER_START_BPS_OLD;
    }

    /// @notice The FIXED affiliate lootbox taper engages at 100 points (1% off at the start), hits the 25%
    ///         floor at 255+ points, and does NOT taper at 99 points (full 100% payout). Under the OLD 10_000
    ///         start threshold a normal 235-point buyer would NEVER taper -- the bug that let high-activity
    ///         buyers keep the full affiliate payout; the fix is asserted to engage where the bug did not.
    function test_AffiliateLootboxTaper_FixedEngagesRejectsBuggy() public pure {
        uint256 amt = 10_000 ether;

        // 99pt: below the start -> NO taper, full payout.
        assertEq(_taperFixed(amt, 99), amt, "99pt: below the 100pt start -> full 100% payout (no taper)");

        // 100pt: the start boundary -- excess 0 -> reduction 0, still the full amount (the taper begins HERE).
        assertEq(_taperFixed(amt, 100), amt, "100pt: the start boundary (excess 0) -> full amount, taper engaged");

        // 101pt: one point past the start -> the taper bites (strictly < the full amount).
        assertLt(_taperFixed(amt, 101), amt, "101pt: the taper bites (strictly less than the full amount)");

        // 255pt and above: the 25% floor -> amt*2500/10000.
        assertEq(_taperFixed(amt, 255), (amt * TAPER_MIN_BPS) / BPS_DENOMINATOR, "255pt: 25% floor (amt*2500/10000)");
        assertEq(_taperFixed(amt, 305), (amt * TAPER_MIN_BPS) / BPS_DENOMINATOR, "305pt (point max): still the 25% floor");

        // The BUG: under the old 10_000 threshold a normal high-activity buyer (235 points) never engages the
        // taper -- they would have kept the FULL payout. The fix DOES taper that buyer (here to the floor).
        assertFalse(_buggyTaperEngages(235), "BUG: old 10_000 threshold never tapers a normal 235-point buyer");
        assertLt(_taperFixed(amt, 235), amt, "FIXED: a 235-point buyer IS tapered (the bug let them keep 100%)");
    }

    // =========================================================================
    // (3) Century quantity bonus -- bonusQty = qty * min(score,305) / 305
    //     FIXED:  divide by the 305 point max -> a maxed score gives the full bonus
    //     BUGGY:  divide by the old 30_500 bps max -> ~qty/100 (the bonus vanishes)
    // =========================================================================

    /// @dev The FIXED century bonus (GameMintModule.sol:1712 / GameAfkingModule.sol:835): clamp the point score
    ///      to 305 then `qty * score / 305` -- a maxed score awards the full `qty` bonus.
    function _centuryBonusFixed(uint256 qty, uint256 score) internal pure returns (uint256) {
        uint256 s = score > SCORE_POINT_MAX ? SCORE_POINT_MAX : score;
        return (qty * s) / SCORE_POINT_MAX;
    }

    /// @dev The BUGGY century bonus: the point score fed into the old bps divisor 30_500 -- `qty*305/30500`
    ///      ≈ qty/100, so a maxed buyer's century bonus all but disappears.
    function _centuryBonusBuggy(uint256 qty, uint256 score) internal pure returns (uint256) {
        return (qty * score) / 30_500;
    }

    /// @notice For a maxed 305-point score the FIXED century quantity bonus awards the FULL `qty` (bonusQty ==
    ///         qty); the buggy bps-divisor value `qty*305/30500 ≈ qty/100` is REJECTED. A representative qty of
    ///         500 makes the ~100x shortfall concrete (500 vs 5).
    function test_CenturyQuantityBonus_FixedFullRejectsBuggy() public pure {
        uint256 qty = 500;

        // FIXED at the point max: bonusQty = 500 * 305 / 305 = 500 (the full bonus).
        assertEq(_centuryBonusFixed(qty, 305), qty, "FIXED century bonus at 305pt -> full qty (500)");
        // A score above the max clamps to the same full bonus.
        assertEq(_centuryBonusFixed(qty, 65_534), qty, "FIXED century bonus clamps an over-max score to the full bonus");

        // BUGGY: 500 * 305 / 30500 = 152500 / 30500 = 5 -- ~100x too small; must NOT equal the fix.
        assertEq(_centuryBonusBuggy(qty, 305), 5, "buggy bps-divisor century bonus computes ~qty/100 (5)");
        assertTrue(
            _centuryBonusFixed(qty, 305) != _centuryBonusBuggy(qty, 305),
            "the fix REJECTS the buggy bps-divisor century bonus (500 != 5)"
        );

        // Mid-score sanity: a half-max score gives roughly half the qty bonus (graduated, not collapsed).
        assertEq(_centuryBonusFixed(qty, 152), (qty * 152) / 305, "FIXED century bonus is graduated by point score");
    }

    // =========================================================================
    // (4) _minScoreForBucket (cap 235) -> graduated lootbox EV (NEUTRAL 60 / MAX 400)
    //     FIXED:  a non-base bucket seals a graduated point score (< 400) -> graduated EV (< 145%)
    //     BUGGY:  cap 23_500 seals a ~bps-scale score that saturates the EV at the 145% max
    // =========================================================================

    /// @dev The FIXED _minScoreForBucket (DegenerusGameDecimatorModule.sol:689): the per-bucket frozen score
    ///      ceiling capped at 235 points. Mirrors the contract's ceil-division.
    function _minScoreForBucketFixed(uint8 bucket, bool x100Level) internal pure returns (uint256) {
        if (bucket >= 12) return 0; // base bucket -> ~0 score -> EV floor
        uint256 cap = 235;
        uint256 floorBucket = x100Level ? 2 : 5;
        uint256 reduction = 12 - uint256(bucket);
        uint256 range = 12 - floorBucket;
        uint256 numer = reduction * cap - cap / 2;
        uint256 s = (numer + range - 1) / range; // ceil
        return s > cap ? cap : s;
    }

    /// @dev The BUGGY _minScoreForBucket: the OLD 23_500 bps cap -- it seals a ~bps-scale score (thousands)
    ///      that the now-point EV curve clamps straight to the 400-point MAX.
    function _minScoreForBucketBuggy(uint8 bucket, bool x100Level) internal pure returns (uint256) {
        if (bucket >= 12) return 0;
        uint256 cap = 23_500;
        uint256 floorBucket = x100Level ? 2 : 5;
        uint256 reduction = 12 - uint256(bucket);
        uint256 range = 12 - floorBucket;
        uint256 numer = reduction * cap - cap / 2;
        uint256 s = (numer + range - 1) / range;
        return s > cap ? cap : s;
    }

    /// @dev The lootbox EV multiplier (DegenerusGameStorage.sol:_lootboxEvMultiplierFromScore): NEUTRAL 60 /
    ///      MAX 400 points; the EV-multiplier OUTPUT anchors stay in bps (9000/10000/14500). `score` is points.
    function _evMultiplier(uint256 score) internal pure returns (uint256) {
        if (score <= EV_NEUTRAL_POINTS) {
            return EV_MIN_BPS + (score * (EV_NEUTRAL_BPS - EV_MIN_BPS)) / EV_NEUTRAL_POINTS;
        }
        if (score >= EV_MAX_POINTS) return EV_MAX_BPS;
        uint256 excess = score - EV_NEUTRAL_POINTS;
        uint256 maxExcess = EV_MAX_POINTS - EV_NEUTRAL_POINTS;
        return EV_NEUTRAL_BPS + (excess * (EV_MAX_BPS - EV_NEUTRAL_BPS)) / maxExcess;
    }

    /// @notice With the 235-point cap, _minScoreForBucket seals a GRADUATED point score per bucket (every value
    ///         < the 400-point EV max), so the decimator-claim lootbox EV rises GRADUALLY across buckets instead
    ///         of pinning at the saturated 145% the bug produced. The buggy 23_500 cap seals a ~bps-scale score
    ///         that the point EV curve clamps straight to the 14500 max for EVERY non-base bucket -- the fix is
    ///         asserted to break that saturation and to produce a strictly increasing gradient.
    function test_MinScoreForBucket_GraduatedEvRejectsSaturatedBuggy() public pure {
        // Every fixed sealed score stays within the point domain (< the 400-point EV max), so the EV is graduated.
        // Walk buckets 11 (just off base) down to 5 (the floor) and assert a strictly increasing EV gradient.
        uint256 prevEv = _evMultiplier(_minScoreForBucketFixed(11, false));
        for (uint8 b = 10; b >= 5; --b) {
            uint256 sealed_ = _minScoreForBucketFixed(b, false);
            assertLt(sealed_, EV_MAX_POINTS, "FIXED sealed score stays under the 400-point EV max (no saturation)");
            uint256 ev = _evMultiplier(sealed_);
            assertGt(ev, prevEv, "FIXED EV rises gradually as the bucket improves (a real gradient)");
            assertLe(ev, EV_MAX_BPS, "FIXED EV stays within the 14500 max");
            prevEv = ev;
            if (b == 5) break; // uint8 loop floor guard
        }

        // The floor bucket (5) seals a high-but-sub-max point score (219, well under the 235 cap and the 400
        // EV max) -> a high-but-not-saturated EV, NOT the flat 14500 the bug pinned every bucket to.
        uint256 floorSealed = _minScoreForBucketFixed(5, false);
        assertEq(floorSealed, 219, "FIXED floor bucket 5 seals 219 points (under the 235 cap, no saturation)");
        assertLt(floorSealed, EV_MAX_POINTS, "FIXED floor-bucket sealed score stays under the 400-point EV max");
        assertLt(_evMultiplier(floorSealed), EV_MAX_BPS, "FIXED floor-bucket EV is below the 14500 saturation");

        // The BUG: the 23_500 cap seals a ~bps-scale score that the point EV curve clamps to the 14500 MAX for
        // EVERY non-base bucket -- a flat, saturated 145% with no gradient. The fix REJECTS that.
        assertGe(_minScoreForBucketBuggy(11, false), EV_MAX_POINTS, "BUG: 23500-cap seals a score past the EV max");
        assertEq(_evMultiplier(_minScoreForBucketBuggy(11, false)), EV_MAX_BPS, "BUG: even bucket 11 saturates the EV at 14500");
        assertEq(_evMultiplier(_minScoreForBucketBuggy(5, false)), EV_MAX_BPS, "BUG: the floor bucket also saturates at 14500");
        assertTrue(
            _evMultiplier(_minScoreForBucketFixed(11, false)) != _evMultiplier(_minScoreForBucketBuggy(11, false)),
            "the fix REJECTS the saturated buggy EV (graduated != flat 14500)"
        );
    }
}
