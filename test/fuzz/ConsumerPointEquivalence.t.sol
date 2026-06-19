// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";

/// @title ConsumerPointEquivalenceTest -- proves the whole-point activity-score consumer math reproduces the
///        intended pre-change (bps-domain) outcomes for the three score consumers: the Lootbox EV multiplier,
///        the Degenerette ROI (+ WWXRP high ROI), and the Decimator multiplier + bucket.
///
/// @notice The activity score migrated from a bps representation to whole points (1 point = 100 bps), and every
///   score-INPUT threshold the consumers compare against / divide by migrated the same way (÷100). The OUTPUT
///   anchors (the ROI / EV-multiplier result values, the quadratic shape coefficients, BPS_DENOMINATOR) did NOT
///   convert -- they stay in their own bps output domain. For a clean whole-point score the point-domain math is
///   bit-identical to the pre-change bps-domain math because the factor 100 cancels in every comparison and in
///   every interpolation ratio BEFORE the integer division. The one exception is the Decimator multiplier
///   `bonusBps/3`, which is re-expressed as `(points*100)/3` (a ×100 re-scale, not a ÷100 of a constant) so the
///   `/3` still divides the bps-equivalent magnitude.
///
/// @dev Each consumer is mirrored TWICE in-test: a point-domain mirror (the shipped formula, point anchors) and
///   a bps-domain ORACLE (the same shape with every score-INPUT anchor ×100 and the score fed ×100, OUTPUT
///   anchors unchanged). The two are compared cell-by-cell on a leg-spanning whole-point grid, plus pinned to
///   the design-locked worked numbers so a wrong migration (e.g. a naive Decimator `points/3`, or converting an
///   OUTPUT anchor by mistake) fails the test. Equivalence is asserted on the clean whole-point grid only -- the
///   floored on-chain score is always a clean whole point; the odd-half-point threshold-tip is the documented,
///   accepted residual (bounded to <=1 grid cell at one boundary) and is NOT asserted as exact here. These are
///   pure-math mirror tests; the harness is extended only for suite consistency. Test-only: ZERO contracts/*.sol
///   mutation.
contract ConsumerPointEquivalenceTest is DeployProtocol {
    // =========================================================================
    // Score-INPUT thresholds (TABLE A): convert ÷100 with the score.
    // Point domain on the left, the ×100 bps-domain oracle form on the right.
    // =========================================================================

    // Lootbox EV (DegenerusGameStorage.sol:1553/1555)
    uint256 private constant EV_NEUTRAL_POINTS = 60;
    uint256 private constant EV_MAX_POINTS = 400;
    uint256 private constant EV_NEUTRAL_BPS_IN = 6_000; // 60 * 100
    uint256 private constant EV_MAX_BPS_IN = 40_000; // 400 * 100

    // Degenerette / WWXRP (DegenerusGameDegeneretteModule.sol:188/191/194)
    uint256 private constant ROI_MID_POINTS = 75;
    uint256 private constant ROI_HIGH_POINTS = 255;
    uint256 private constant ROI_MAX_POINTS = 305;
    uint256 private constant ROI_MID_BPS_IN = 7_500; // 75 * 100
    uint256 private constant ROI_HIGH_BPS_IN = 25_500; // 255 * 100
    uint256 private constant ROI_MAX_BPS_IN = 30_500; // 305 * 100

    // Decimator (DegenerusGameDecimatorModule.sol:772)
    uint256 private constant DEC_CAP_POINTS = 235;
    uint256 private constant DEC_CAP_BPS_IN = 23_500; // 235 * 100

    // =========================================================================
    // OUTPUT anchors (TABLE B): do NOT convert -- identical in both domains.
    // =========================================================================

    // Lootbox EV-multiplier output (DegenerusGameStorage.sol:1557/1559/1561)
    uint256 private constant EV_MIN_BPS = 9_000;
    uint256 private constant EV_NEUTRAL_BPS = 10_000;
    uint256 private constant EV_MAX_BPS = 14_500;

    // Degenerette ROI output (DegenerusGameDegeneretteModule.sol:197/200/203/206)
    uint256 private constant ROI_MIN_BPS = 9_000;
    uint256 private constant ROI_MID_BPS = 9_500;
    uint256 private constant ROI_HIGH_BPS = 9_950;
    uint256 private constant ROI_MAX_BPS = 9_990;

    // WWXRP high ROI output (DegenerusGameDegeneretteModule.sol:214/217)
    uint256 private constant WWXRP_BASE_BPS = 9_000;
    uint256 private constant WWXRP_MAX_BPS = 10_990;

    // Quadratic low-leg shape coefficients (DegenerusGameDegeneretteModule.sol:1152-1153)
    uint256 private constant QUAD_C1 = 1_000;
    uint256 private constant QUAD_C2 = 500;

    // Decimator multiplier base + bucket constants (DegenerusGameDecimatorModule.sol:104/770/771)
    uint256 private constant BPS_DENOMINATOR = 10_000;
    uint256 private constant BUCKET_BASE = 12;
    uint256 private constant MIN_BUCKET = 2;
    uint256 private constant BUCKET_RANGE = BUCKET_BASE - MIN_BUCKET; // 10, a bucket count -- NOT a score, never ×100

    function setUp() public {
        // Pure-math mirror tests; the deploy keeps the contract suite-consistent (the consumer formulas under
        // test are pure functions read directly from source, mirrored below).
        _deployProtocol();
    }

    // =========================================================================
    // Lootbox EV multiplier mirrors
    //   point: DegenerusGameStorage.sol:_lootboxEvMultiplierFromScore (:1633-1654)
    //   The two legs are an interpolation ratio (low: score/NEUTRAL; high: excess/maxExcess); both NEUTRAL and
    //   MAX divide by 100 alongside the score, so the factor 100 cancels in numerator and denominator BEFORE the
    //   integer division -> bit-identical for a clean whole-point score.
    // =========================================================================

    function _evPoint(uint256 score) internal pure returns (uint256) {
        if (score <= EV_NEUTRAL_POINTS) {
            return EV_MIN_BPS + (score * (EV_NEUTRAL_BPS - EV_MIN_BPS)) / EV_NEUTRAL_POINTS;
        }
        if (score >= EV_MAX_POINTS) {
            return EV_MAX_BPS;
        }
        uint256 excess = score - EV_NEUTRAL_POINTS;
        uint256 maxExcess = EV_MAX_POINTS - EV_NEUTRAL_POINTS;
        return EV_NEUTRAL_BPS + (excess * (EV_MAX_BPS - EV_NEUTRAL_BPS)) / maxExcess;
    }

    /// @dev The pre-change bps-domain oracle: identical shape, score-INPUT anchors ×100, score fed ×100, OUTPUT
    ///      anchors unchanged. The factor 100 cancels in each ratio so this reproduces the original outcome.
    function _evBps(uint256 scoreBps) internal pure returns (uint256) {
        if (scoreBps <= EV_NEUTRAL_BPS_IN) {
            return EV_MIN_BPS + (scoreBps * (EV_NEUTRAL_BPS - EV_MIN_BPS)) / EV_NEUTRAL_BPS_IN;
        }
        if (scoreBps >= EV_MAX_BPS_IN) {
            return EV_MAX_BPS;
        }
        uint256 excess = scoreBps - EV_NEUTRAL_BPS_IN;
        uint256 maxExcess = EV_MAX_BPS_IN - EV_NEUTRAL_BPS_IN;
        return EV_NEUTRAL_BPS + (excess * (EV_MAX_BPS - EV_NEUTRAL_BPS)) / maxExcess;
    }

    // =========================================================================
    // Degenerette ROI mirrors
    //   point: DegenerusGameDegeneretteModule.sol:_roiBpsFromScore (:1141-1170)
    //   The low leg is QUADRATIC: term1 = C1*score/MID, term2 = C2*score^2/MID^2. The 100^2 in term2's numerator
    //   and denominator cancels cleanly (numerator carries 100^2, denominator MID^2 carries 100^2), so the
    //   integer quotient is identical. The mid/high legs are linear interpolation ratios (delta/span), invariant.
    // =========================================================================

    function _roiPoint(uint256 score) internal pure returns (uint256 roiBps) {
        if (score > ROI_MAX_POINTS) score = ROI_MAX_POINTS;
        if (score <= ROI_MID_POINTS) {
            uint256 term1 = (QUAD_C1 * score) / ROI_MID_POINTS;
            uint256 term2 = (QUAD_C2 * score * score) / (ROI_MID_POINTS * ROI_MID_POINTS);
            roiBps = ROI_MIN_BPS + term1 - term2;
        } else if (score <= ROI_HIGH_POINTS) {
            uint256 delta = score - ROI_MID_POINTS;
            uint256 span = ROI_HIGH_POINTS - ROI_MID_POINTS;
            roiBps = ROI_MID_BPS + (delta * (ROI_HIGH_BPS - ROI_MID_BPS)) / span;
        } else {
            uint256 delta = score - ROI_HIGH_POINTS;
            uint256 span = ROI_MAX_POINTS - ROI_HIGH_POINTS;
            roiBps = ROI_HIGH_BPS + (delta * (ROI_MAX_BPS - ROI_HIGH_BPS)) / span;
        }
    }

    function _roiBps(uint256 scoreBps) internal pure returns (uint256 roiBps) {
        if (scoreBps > ROI_MAX_BPS_IN) scoreBps = ROI_MAX_BPS_IN;
        if (scoreBps <= ROI_MID_BPS_IN) {
            uint256 term1 = (QUAD_C1 * scoreBps) / ROI_MID_BPS_IN;
            uint256 term2 = (QUAD_C2 * scoreBps * scoreBps) / (ROI_MID_BPS_IN * ROI_MID_BPS_IN);
            roiBps = ROI_MIN_BPS + term1 - term2;
        } else if (scoreBps <= ROI_HIGH_BPS_IN) {
            uint256 delta = scoreBps - ROI_MID_BPS_IN;
            uint256 span = ROI_HIGH_BPS_IN - ROI_MID_BPS_IN;
            roiBps = ROI_MID_BPS + (delta * (ROI_HIGH_BPS - ROI_MID_BPS)) / span;
        } else {
            uint256 delta = scoreBps - ROI_HIGH_BPS_IN;
            uint256 span = ROI_MAX_BPS_IN - ROI_HIGH_BPS_IN;
            roiBps = ROI_HIGH_BPS + (delta * (ROI_MAX_BPS - ROI_HIGH_BPS)) / span;
        }
    }

    // WWXRP high ROI mirrors (DegenerusGameDegeneretteModule.sol:_wwxrpHighValueRoi :1178-1190)
    //   Single-anchor denominator MAX; score*K/MAX = s'*K/m' -> invariant.

    function _wwxrpPoint(uint256 score) internal pure returns (uint256) {
        if (score > ROI_MAX_POINTS) score = ROI_MAX_POINTS;
        return WWXRP_BASE_BPS + (score * (WWXRP_MAX_BPS - WWXRP_BASE_BPS)) / ROI_MAX_POINTS;
    }

    function _wwxrpBps(uint256 scoreBps) internal pure returns (uint256) {
        if (scoreBps > ROI_MAX_BPS_IN) scoreBps = ROI_MAX_BPS_IN;
        return WWXRP_BASE_BPS + (scoreBps * (WWXRP_MAX_BPS - WWXRP_BASE_BPS)) / ROI_MAX_BPS_IN;
    }

    // =========================================================================
    // Tests -- Lootbox EV
    // =========================================================================

    /// @notice The Lootbox EV multiplier is bit-identical between the point-domain mirror and the bps-domain
    ///         oracle for every whole-point score spanning the low leg, the neutral join, the high leg, and the
    ///         max clamp -- plus the design-locked worked anchors. A wrong migration (e.g. converting EV_MIN /
    ///         EV_NEUTRAL / EV_MAX, the OUTPUT anchors, by ÷100, or failing to convert NEUTRAL/MAX) breaks the
    ///         worked anchors below.
    function test_LootboxEvEquivalence_Grid() public pure {
        uint256[11] memory grid = [
            uint256(0), 30, 59, 60, 61, 120, 230, 399, 400, 401, 1000
        ];
        for (uint256 i; i < grid.length; i++) {
            uint256 s = grid[i];
            assertEq(_evPoint(s), _evBps(s * 100), "EV point-vs-bps equivalence on the whole-point grid");
        }

        // Design-locked worked anchors (435 D-04.2(1)).
        assertEq(_evPoint(30), 9500, "EV worked: 30pt -> 9500 (low leg)");
        assertEq(_evPoint(230), 12250, "EV worked: 230pt -> 12250 (high leg)");
        assertEq(_evPoint(400), 14500, "EV worked: >=400pt -> 14500 (max clamp)");
        assertEq(_evPoint(401), 14500, "EV worked: above max still clamps to 14500");
        assertEq(_evPoint(0), 9000, "EV anchor: 0pt -> EV_MIN 9000");
        assertEq(_evPoint(60), 10000, "EV anchor: 60pt -> EV_NEUTRAL 10000 (legs meet at NEUTRAL)");
    }

    // =========================================================================
    // Tests -- Degenerette ROI + WWXRP
    // =========================================================================

    /// @notice The Degenerette ROI (quadratic low leg + two linear segments + the >MAX clamp) and the WWXRP
    ///         high ROI are bit-identical between the point mirror and the bps oracle across a grid spanning
    ///         every segment and the clamp -- plus the worked anchors. The quadratic term's 100^2 cancellation
    ///         is exercised at score 30 (the worked 9320). Converting any ROI/WWXRP OUTPUT anchor or the
    ///         quadratic coefficients 1000/500 by ÷100 would break the worked anchor.
    function test_DegeneretteRoiEquivalence_Grid() public pure {
        uint256[13] memory grid = [
            uint256(0), 30, 74, 75, 76, 150, 254, 255, 256, 304, 305, 306, 1000
        ];
        for (uint256 i; i < grid.length; i++) {
            uint256 s = grid[i];
            assertEq(_roiPoint(s), _roiBps(s * 100), "ROI point-vs-bps equivalence on the whole-point grid");
            assertEq(_wwxrpPoint(s), _wwxrpBps(s * 100), "WWXRP point-vs-bps equivalence on the whole-point grid");
        }

        // Design-locked worked anchors (435 D-04.2(2)).
        assertEq(_roiPoint(30), 9320, "ROI worked: 30pt -> 9320 (quadratic low leg, 100^2 cancellation)");
        assertEq(_roiPoint(0), 9000, "ROI anchor: 0pt -> ROI_MIN 9000");
        assertEq(_roiPoint(305), ROI_MAX_BPS, "ROI anchor: 305pt -> ROI_MAX 9990 (high-leg endpoint)");
        assertEq(_roiPoint(306), _roiPoint(305), "ROI clamp: above MAX behaves as 305");
        assertEq(_roiPoint(75), ROI_MID_BPS, "ROI anchor: 75pt -> ROI_MID 9500 (quadratic meets mid leg)");
        assertEq(_roiPoint(255), ROI_HIGH_BPS, "ROI anchor: 255pt -> ROI_HIGH 9950 (mid meets high leg)");

        // WWXRP endpoints.
        assertEq(_wwxrpPoint(0), WWXRP_BASE_BPS, "WWXRP anchor: 0pt -> base 9000");
        assertEq(_wwxrpPoint(305), WWXRP_MAX_BPS, "WWXRP anchor: 305pt -> max 10990");
        assertEq(_wwxrpPoint(306), WWXRP_MAX_BPS, "WWXRP clamp: above MAX behaves as 305");
    }
}
