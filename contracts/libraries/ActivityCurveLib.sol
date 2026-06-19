// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/**
 * @title ActivityCurveLib
 * @notice Pure activity-score reward curves shared across the Degenerus contracts.
 * @dev All functions are internal and pure, so the compiler inlines them with ZERO
 *      gas overhead. Centralizing the math keeps the decimator multiplier and bucket
 *      ladder identical between FLIP and the decimator module, and the century bonus
 *      identical between the mint and afking paths — one source of truth for weights
 *      that are still being tuned.
 *
 *      Value-curve shape: a steep early ramp to vA at the old cap K, a shallow middle
 *      leg to vB at ACTIVITY_SEG_B_KNEE_POINTS, then a long near-flat crawl to MAX at
 *      ACTIVITY_EFFECTIVE_CAP_POINTS, flat at MAX beyond. Score is in whole points and
 *      is already bounded by the game's activity-score hard cap before it arrives here,
 *      so the >= ACTIVITY_EFFECTIVE_CAP_POINTS branch is the saturation guard (the curve
 *      self-caps; callers no longer pre-clamp the input).
 */
library ActivityCurveLib {
    // -------------------------------------------------------------------------
    // Shared segment knees
    // -------------------------------------------------------------------------

    /// @dev Score where the shallow middle leg ends (98% of the gain delivered).
    uint256 internal constant ACTIVITY_SEG_B_KNEE_POINTS = 500;

    /// @dev Score where every curve reaches MAX and saturates flat beyond.
    uint256 internal constant ACTIVITY_EFFECTIVE_CAP_POINTS = 30_000;

    // -------------------------------------------------------------------------
    // Decimator / terminal-dec burn multiplier (bps; 10000 = 1x)
    // -------------------------------------------------------------------------

    uint256 internal constant MULT_MIN_BPS = 10_000; // 1.0x at score 0 (no-boost gate)
    uint256 internal constant MULT_K_POINTS = 235; // old cap / seg-A knee
    uint256 internal constant MULT_VA_BPS = 17_049; // ~1.705x at K (90% of gain)
    uint256 internal constant MULT_VB_BPS = 17_676; // ~1.768x at the seg-B knee (98%)
    uint256 internal constant MULT_MAX_BPS = 17_833; // 1.7833x at the effective cap

    /// @notice Decimator burn multiplier in bps from a whole-point activity score.
    function decMultBps(uint256 score) internal pure returns (uint256) {
        if (score == 0) return MULT_MIN_BPS;
        if (score >= ACTIVITY_EFFECTIVE_CAP_POINTS) return MULT_MAX_BPS;
        if (score <= MULT_K_POINTS) {
            return
                MULT_MIN_BPS +
                (score * (MULT_VA_BPS - MULT_MIN_BPS)) /
                MULT_K_POINTS;
        }
        if (score <= ACTIVITY_SEG_B_KNEE_POINTS) {
            return
                MULT_VA_BPS +
                ((score - MULT_K_POINTS) * (MULT_VB_BPS - MULT_VA_BPS)) /
                (ACTIVITY_SEG_B_KNEE_POINTS - MULT_K_POINTS);
        }
        return
            MULT_VB_BPS +
            ((score - ACTIVITY_SEG_B_KNEE_POINTS) * (MULT_MAX_BPS - MULT_VB_BPS)) /
            (ACTIVITY_EFFECTIVE_CAP_POINTS - ACTIVITY_SEG_B_KNEE_POINTS);
    }

    // -------------------------------------------------------------------------
    // Century mint/afking bonus (bps of base quantity; 10000 = 100%)
    // -------------------------------------------------------------------------

    uint256 internal constant CENTURY_K_POINTS = 305; // old cap / seg-A knee
    uint256 internal constant CENTURY_VA_BPS = 9_000; // 90% of qty at K
    uint256 internal constant CENTURY_VB_BPS = 9_800; // 98% at the seg-B knee
    uint256 internal constant CENTURY_MAX_BPS = 10_000; // 100% at the effective cap

    /// @notice Century purchase/afking bonus as bps of the base quantity.
    /// @dev Caller computes bonusQty = baseQty * centuryBps(score) / CENTURY_MAX_BPS.
    function centuryBps(uint256 score) internal pure returns (uint256) {
        if (score >= ACTIVITY_EFFECTIVE_CAP_POINTS) return CENTURY_MAX_BPS;
        if (score <= CENTURY_K_POINTS) {
            return (score * CENTURY_VA_BPS) / CENTURY_K_POINTS;
        }
        if (score <= ACTIVITY_SEG_B_KNEE_POINTS) {
            return
                CENTURY_VA_BPS +
                ((score - CENTURY_K_POINTS) * (CENTURY_VB_BPS - CENTURY_VA_BPS)) /
                (ACTIVITY_SEG_B_KNEE_POINTS - CENTURY_K_POINTS);
        }
        return
            CENTURY_VB_BPS +
            ((score - ACTIVITY_SEG_B_KNEE_POINTS) *
                (CENTURY_MAX_BPS - CENTURY_VB_BPS)) /
            (ACTIVITY_EFFECTIVE_CAP_POINTS - ACTIVITY_SEG_B_KNEE_POINTS);
    }

    // -------------------------------------------------------------------------
    // Decimator bucket ladder (lower bucket = better odds)
    // -------------------------------------------------------------------------

    /// @dev Bucket at score 0 (worst odds).
    uint8 internal constant BUCKET_BASE = 12;

    // Absolute score to REACH each bucket. decBucket() and minScoreForBucket() are
    // exact inverses of this table — keep the two in lockstep when tuning.
    uint16 internal constant BUCKET_T11 = 10;
    uint16 internal constant BUCKET_T10 = 30;
    uint16 internal constant BUCKET_T9 = 55;
    uint16 internal constant BUCKET_T8 = 85;
    uint16 internal constant BUCKET_T7 = 120;
    uint16 internal constant BUCKET_T6 = 180;
    uint16 internal constant BUCKET_T5 = 250;
    uint16 internal constant BUCKET_T4 = 300;
    uint16 internal constant BUCKET_T3 = 500;
    uint16 internal constant BUCKET_T2 = 1_000;

    /// @notice Decimator bucket from an activity score, clamped up to `minBucket`.
    /// @param minBucket Per-path floor (5 on normal levels, 2 on century/terminal).
    function decBucket(
        uint256 score,
        uint8 minBucket
    ) internal pure returns (uint8 bucket) {
        if (score >= BUCKET_T2) bucket = 2;
        else if (score >= BUCKET_T3) bucket = 3;
        else if (score >= BUCKET_T4) bucket = 4;
        else if (score >= BUCKET_T5) bucket = 5;
        else if (score >= BUCKET_T6) bucket = 6;
        else if (score >= BUCKET_T7) bucket = 7;
        else if (score >= BUCKET_T8) bucket = 8;
        else if (score >= BUCKET_T9) bucket = 9;
        else if (score >= BUCKET_T10) bucket = 10;
        else if (score >= BUCKET_T11) bucket = 11;
        else bucket = BUCKET_BASE;
        if (bucket < minBucket) bucket = minBucket;
    }

    /// @notice Minimum activity score that lands a burn in `bucket` (the pre-floor
    ///         inverse of decBucket). Seals the lootbox EV score at decimator-claim time.
    function minScoreForBucket(uint8 bucket) internal pure returns (uint16) {
        if (bucket >= BUCKET_BASE) return 0;
        if (bucket == 11) return BUCKET_T11;
        if (bucket == 10) return BUCKET_T10;
        if (bucket == 9) return BUCKET_T9;
        if (bucket == 8) return BUCKET_T8;
        if (bucket == 7) return BUCKET_T7;
        if (bucket == 6) return BUCKET_T6;
        if (bucket == 5) return BUCKET_T5;
        if (bucket == 4) return BUCKET_T4;
        if (bucket == 3) return BUCKET_T3;
        return BUCKET_T2; // bucket <= 2
    }
}
