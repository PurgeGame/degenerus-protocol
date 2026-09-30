// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/*
 * TERMS OF INTERACTION — submitting a transaction to this contract accepts them.
 *
 * THIS IS GAMBLING. Outcomes are decided by chance. You can lose everything you put in
 * simply by being unlucky. That is the software working exactly as intended. Do not
 * commit funds you are not prepared to lose entirely.
 *
 * The deployed bytecode is the entire agreement and the exclusive source of truth; any
 * comment, name, document or statement that disagrees with it is in error. It has been
 * audited but is not proven correct: it may contain defects the author did not find, and
 * by interacting with it you accept that risk in full.
 *
 * Any state transition the code permits is authorised — including one that exploits a
 * defect, and including sequences the author did not intend or foresee. A bug is not a
 * breach of these terms. There is no unwritten rule behind the code for a permitted
 * transaction to violate, and no unauthorised access to this contract.
 *
 * You bear all resulting loss, whether it follows from chance or from a defect. There is
 * no refund, no rollback and no privileged party able to restore a position.
 *
 * Provided AS IS, without warranty of any kind. Full text: TERMS.md
 */

/**
 * @title ActivityCurveLib
 * @notice Pure activity-score reward curves shared across the Degenerus contracts.
 * @dev All functions are internal and pure, so the compiler inlines them with no
 *      runtime call boundary. Shared curves price battle chips, WWXRP rewards,
 *      manual century mints and foil boosts.
 *
 *      Value-curve shape: a steep early ramp to vA at the seg-A knee K, a shallow middle
 *      leg to vB at ACTIVITY_SEG_B_KNEE_POINTS, then a long near-flat crawl to MAX at
 *      ACTIVITY_EFFECTIVE_CAP_POINTS, flat at MAX beyond. Score is in whole points and
 *      is already bounded by the game's activity-score hard cap before it arrives here,
 *      so the >= ACTIVITY_EFFECTIVE_CAP_POINTS branch is the saturation guard: the curve
 *      self-caps and callers pass the score through unclamped.
 */
library ActivityCurveLib {
    /// @notice Protocol boon-draw multiplier scaled by 800: 1x at zero, 2x at
    ///         400, 3x at 1200, flat thereafter. Retain this scale in draw weight
    ///         so even a minimum ETH bet keeps every whole-score increment.
    function boonDrawMultUnits(uint256 score) internal pure returns (uint256) {
        if (score <= 400) return 800 + 2 * score;
        if (score < 1200) return 1600 + (score - 400);
        return 2400;
    }

    // -------------------------------------------------------------------------
    // Shared segment knees
    // -------------------------------------------------------------------------

    /// @dev Score where the shallow middle leg ends; each curve delivers its own fraction of the gain here (~98% decimator/century, 87.5% foil).
    uint256 internal constant ACTIVITY_SEG_B_KNEE_POINTS = 500;

    /// @dev Score where every curve reaches MAX and saturates flat beyond.
    uint256 internal constant ACTIVITY_EFFECTIVE_CAP_POINTS = 30_000;

    // -------------------------------------------------------------------------
    // Legacy activity curve retained by WWXRP (bps; 10000 = 1x)
    // -------------------------------------------------------------------------

    uint256 internal constant MULT_MIN_BPS = 10_000; // 1.0x at score 0 (no-boost gate)
    uint256 internal constant MULT_K_POINTS = 235; // seg-A knee
    uint256 internal constant MULT_VA_BPS = 17_049; // ~1.705x at K (90% of gain)
    uint256 internal constant MULT_VB_BPS = 17_676; // ~1.768x at the seg-B knee (98%)
    uint256 internal constant MULT_MAX_BPS = 17_833; // 1.7833x at the effective cap

    /// @notice Original activity multiplier retained for WWXRP reward scaling.
    function decMultBps(uint256 score) internal pure returns (uint256) {
        if (score == 0) return MULT_MIN_BPS;
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
        // Cap moved below the two segment checks: low scores (the common case) skip this
        // comparison; the disjoint [K<SegB<CAP] partition keeps every region bit-identical.
        if (score >= ACTIVITY_EFFECTIVE_CAP_POINTS) return MULT_MAX_BPS;
        return
            MULT_VB_BPS +
            ((score - ACTIVITY_SEG_B_KNEE_POINTS) * (MULT_MAX_BPS - MULT_VB_BPS)) /
            (ACTIVITY_EFFECTIVE_CAP_POINTS - ACTIVITY_SEG_B_KNEE_POINTS);
    }

    /// @notice Battle-only degen multiplier: keep the early knee, reach 1.9x at 500,
    ///         then 2x at 30,000. WWXRP retains decMultBps above.
    function decBattleMultBps(uint256 score) internal pure returns (uint256) {
        if (score <= MULT_K_POINTS) return MULT_MIN_BPS + score * (MULT_VA_BPS - MULT_MIN_BPS) / MULT_K_POINTS;
        if (score <= ACTIVITY_SEG_B_KNEE_POINTS) {
            return MULT_VA_BPS + (score - MULT_K_POINTS) * (19_000 - MULT_VA_BPS)
                / (ACTIVITY_SEG_B_KNEE_POINTS - MULT_K_POINTS);
        }
        if (score >= ACTIVITY_EFFECTIVE_CAP_POINTS) return 20_000;
        return 19_000 + (score - ACTIVITY_SEG_B_KNEE_POINTS) * 1_000
            / (ACTIVITY_EFFECTIVE_CAP_POINTS - ACTIVITY_SEG_B_KNEE_POINTS);
    }

    // -------------------------------------------------------------------------
    // Century mint bonus (bps of base quantity; 10000 = 100%)
    // -------------------------------------------------------------------------

    uint256 internal constant CENTURY_K_POINTS = 305; // seg-A knee
    uint256 internal constant CENTURY_VA_BPS = 9_000; // 90% of qty at K
    uint256 internal constant CENTURY_VB_BPS = 9_800; // 98% at the seg-B knee
    uint256 internal constant CENTURY_MAX_BPS = 10_000; // 100% at the effective cap

    /// @notice Century purchase bonus as bps of the base quantity (manual mints only; afking deliveries skip it).
    /// @dev Caller computes bonusQty = baseQty * centuryBps(score) / CENTURY_MAX_BPS.
    function centuryBps(uint256 score) internal pure returns (uint256) {
        if (score <= CENTURY_K_POINTS) {
            return (score * CENTURY_VA_BPS) / CENTURY_K_POINTS;
        }
        if (score <= ACTIVITY_SEG_B_KNEE_POINTS) {
            return
                CENTURY_VA_BPS +
                ((score - CENTURY_K_POINTS) * (CENTURY_VB_BPS - CENTURY_VA_BPS)) /
                (ACTIVITY_SEG_B_KNEE_POINTS - CENTURY_K_POINTS);
        }
        // Cap moved below the segment checks (see decMultBps); score 0 still resolves via the
        // first segment ((0*VA)/K == 0), so the zero/cap endpoints are preserved.
        if (score >= ACTIVITY_EFFECTIVE_CAP_POINTS) return CENTURY_MAX_BPS;
        return
            CENTURY_VB_BPS +
            ((score - ACTIVITY_SEG_B_KNEE_POINTS) *
                (CENTURY_MAX_BPS - CENTURY_VB_BPS)) /
            (ACTIVITY_EFFECTIVE_CAP_POINTS - ACTIVITY_SEG_B_KNEE_POINTS);
    }

    // -------------------------------------------------------------------------
    // Foil-pack rarity boost multiplier (bps; 10000 = 1x)
    // -------------------------------------------------------------------------

    uint256 internal constant FOIL_MIN_BPS = 20_000; // 2.0x at score 0 (floor)
    uint256 internal constant FOIL_K_POINTS = 300; // seg-A knee
    uint256 internal constant FOIL_VA_BPS = 50_000; // 5.0x at K (75% of gain)
    uint256 internal constant FOIL_VB_BPS = 55_000; // 5.5x at the seg-B knee (87.5%)
    uint256 internal constant FOIL_MAX_BPS = 60_000; // 6.0x at the effective cap

    /// @notice Foil-pack rarity boost multiplier in bps from a whole-point activity
    ///         score. Frozen at buy and applied at resolve — never live-read.
    /// @dev Steep early ramp MIN->VA over [0, K], shallow middle VA->VB over
    ///      [K, ACTIVITY_SEG_B_KNEE_POINTS], long near-flat crawl VB->MAX over
    ///      [ACTIVITY_SEG_B_KNEE_POINTS, ACTIVITY_EFFECTIVE_CAP_POINTS], flat at MAX
    ///      beyond. The two endpoint guards make 0 and the cap exact (no interp rounding).
    function foilBoostBps(uint256 score) internal pure returns (uint256) {
        if (score == 0) return FOIL_MIN_BPS;
        if (score <= FOIL_K_POINTS) {
            return
                FOIL_MIN_BPS +
                (score * (FOIL_VA_BPS - FOIL_MIN_BPS)) /
                FOIL_K_POINTS;
        }
        if (score <= ACTIVITY_SEG_B_KNEE_POINTS) {
            return
                FOIL_VA_BPS +
                ((score - FOIL_K_POINTS) * (FOIL_VB_BPS - FOIL_VA_BPS)) /
                (ACTIVITY_SEG_B_KNEE_POINTS - FOIL_K_POINTS);
        }
        // Cap moved below the two segment checks (see decMultBps); endpoints preserved.
        if (score >= ACTIVITY_EFFECTIVE_CAP_POINTS) return FOIL_MAX_BPS;
        return
            FOIL_VB_BPS +
            ((score - ACTIVITY_SEG_B_KNEE_POINTS) * (FOIL_MAX_BPS - FOIL_VB_BPS)) /
            (ACTIVITY_EFFECTIVE_CAP_POINTS - ACTIVITY_SEG_B_KNEE_POINTS);
    }

}
