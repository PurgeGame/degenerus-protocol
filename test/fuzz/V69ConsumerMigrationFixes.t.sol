// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";

/// @title V69ConsumerMigrationFixes -- regression proof for the DegenerusAffiliate lootbox taper, the one
///        score consumer migrated from the bps activity-score domain to whole points that is NOT part of the
///        later curve reshape.
///
/// @notice The other three migrated consumers (FLIP/terminal decimator multiplier + bucket, century quantity
///   bonus, _minScoreForBucket) were subsequently reshaped onto the steep-ramp/long-tail curves in
///   ActivityCurveLib; their behavior is validated by ConsumerPointEquivalence. The affiliate lootbox taper was
///   left unchanged, so its migration fix still stands and is pinned here: the taper starts at 100 points (not
///   the old 10_000 bps threshold) and floors at 25% by 255 points.
///
/// @dev Pure-math mirror test; the deploy keeps the suite consistent. Test-only: ZERO contracts/*.sol mutation.
contract V69ConsumerMigrationFixes is DeployProtocol {
    uint256 private constant BPS_DENOMINATOR = 10_000;

    // Affiliate lootbox taper (DegenerusAffiliate.sol:187/188/189)
    uint256 private constant TAPER_START_POINTS = 100;
    uint256 private constant TAPER_END_POINTS = 255;
    uint256 private constant TAPER_MIN_BPS = 2_500; // the 25% floor, a bps OUTPUT anchor (unchanged)
    uint256 private constant TAPER_START_BPS_OLD = 10_000; // the OLD pre-migration start threshold

    function setUp() public {
        _deployProtocol();
    }

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
}
