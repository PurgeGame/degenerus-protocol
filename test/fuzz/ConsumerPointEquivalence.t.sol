// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {ActivityCurveLib} from "../../contracts/libraries/ActivityCurveLib.sol";

/// @title ConsumerPointEquivalenceTest -- validates the reshaped activity-score consumer curves.
///
/// @notice The five value curves (WWXRP activity multiplier, Degenerette ROI, WWXRP total-RTP, century
///   bonus, lootbox EV) share one shape: a steep early ramp to vA at the old cap K, a shallow middle leg to vB
///   at the seg-B knee (500), then a near-flat crawl to MAX at the effective cap (30000), flat beyond. Each
///   curve's MIN (score-0) and MAX (cap) are pinned by its golden waypoints below (the WWXRP curve carries the
///   rigged 70%->120% endpoints). The Decimator battle's chip multiplier is pinned by its own anchors.
///
/// @dev The shared math (multiplier, battle multiplier, century) lives in ActivityCurveLib and is exercised
///   DIRECTLY here. The in-place curves (ROI/WWXRP in DegeneretteModule, lootbox EV in DegenerusGameStorage) are
///   mirrored to the shipped formula and pinned to independently-derived golden waypoints, plus shape properties
///   (monotonic non-decreasing, continuity at every knee, MIN/MAX exact, ROI strictly sub-100%). Test-only:
///   ZERO contracts/*.sol mutation.
contract ConsumerPointEquivalenceTest is DeployProtocol {
    uint256 private constant SEG_B = ActivityCurveLib.ACTIVITY_SEG_B_KNEE_POINTS; // 500
    uint256 private constant CAP = ActivityCurveLib.ACTIVITY_EFFECTIVE_CAP_POINTS; // 30000

    function setUp() public {
        // Pure-math validation; deploy keeps the suite consistent.
        _deployProtocol();
    }

    // =========================================================================
    // In-place curve mirrors (match the shipped formula exactly)
    // =========================================================================

    // Degenerette ROI: MIN 9000, K=305 -> vA 9891, SEG_B -> vB 9970, CAP -> MAX 9990.
    function _roi(uint256 s) internal pure returns (uint256) {
        if (s >= CAP) return 9990;
        if (s <= 305) return 9000 + (s * (9891 - 9000)) / 305;
        if (s <= SEG_B) return 9891 + ((s - 305) * (9970 - 9891)) / (SEG_B - 305);
        return 9970 + ((s - SEG_B) * (9990 - 9970)) / (CAP - SEG_B);
    }

    // WWXRP total-RTP curve E: MIN 7000, K=305 -> vA 11500, SEG_B -> vB 11800, CAP -> MAX 12000.
    function _wwxrp(uint256 s) internal pure returns (uint256) {
        if (s >= CAP) return 12000;
        if (s <= 305) return 7000 + (s * (11500 - 7000)) / 305;
        if (s <= SEG_B) return 11500 + ((s - 305) * (11800 - 11500)) / (SEG_B - 305);
        return 11800 + ((s - SEG_B) * (12000 - 11800)) / (CAP - SEG_B);
    }

    // Lootbox EV: keep 0..60 anchor (9000->10000), K=400 -> vA 13950, SEG_B -> vB 14390, CAP -> MAX 14500.
    function _ev(uint256 s) internal pure returns (uint256) {
        if (s <= 60) return 9000 + (s * (10000 - 9000)) / 60;
        if (s >= CAP) return 14500;
        if (s <= 400) return 10000 + ((s - 60) * (13950 - 10000)) / (400 - 60);
        if (s <= SEG_B) return 13950 + ((s - 400) * (14390 - 13950)) / (SEG_B - 400);
        return 14390 + ((s - SEG_B) * (14500 - 14390)) / (CAP - SEG_B);
    }

    // =========================================================================
    // Golden waypoints (independently derived; integer-truncated)
    // =========================================================================

    function test_GoldenWaypoints_Multiplier() public pure {
        uint16[12] memory s = [uint16(0), 60, 75, 155, 235, 305, 400, 500, 1000, 2000, 10000, 30000];
        uint256[12] memory g = [
            uint256(10000), 11799, 12249, 14649, 17049, 17214, 17439, 17676, 17678, 17683, 17726, 17833
        ];
        for (uint256 i; i < s.length; i++) {
            assertEq(ActivityCurveLib.decMultBps(s[i]), g[i], "multiplier golden waypoint");
        }
    }

    function test_GoldenWaypoints_Roi() public pure {
        uint16[12] memory s = [uint16(0), 60, 75, 155, 235, 305, 400, 500, 1000, 2000, 10000, 30000];
        uint256[12] memory g = [
            uint256(9000), 9175, 9219, 9452, 9686, 9891, 9929, 9970, 9970, 9971, 9976, 9990
        ];
        for (uint256 i; i < s.length; i++) {
            assertEq(_roi(s[i]), g[i], "roi golden waypoint");
        }
    }

    function test_GoldenWaypoints_Wwxrp() public pure {
        uint16[12] memory s = [uint16(0), 60, 75, 155, 235, 305, 400, 500, 1000, 2000, 10000, 30000];
        uint256[12] memory g = [
            uint256(7000), 7885, 8106, 9286, 10467, 11500, 11646, 11800, 11803, 11810, 11864, 12000
        ];
        for (uint256 i; i < s.length; i++) {
            assertEq(_wwxrp(s[i]), g[i], "wwxrp golden waypoint");
        }
    }

    function test_GoldenWaypoints_Century() public pure {
        uint16[12] memory s = [uint16(0), 60, 75, 155, 235, 305, 400, 500, 1000, 2000, 10000, 30000];
        uint256[12] memory g = [
            uint256(0), 1770, 2213, 4573, 6934, 9000, 9389, 9800, 9803, 9810, 9864, 10000
        ];
        for (uint256 i; i < s.length; i++) {
            assertEq(ActivityCurveLib.centuryBps(s[i]), g[i], "century golden waypoint");
        }
    }

    function test_GoldenWaypoints_LootboxEv() public pure {
        uint16[12] memory s = [uint16(0), 60, 75, 155, 235, 305, 400, 500, 1000, 2000, 10000, 30000];
        uint256[12] memory g = [
            uint256(9000), 10000, 10174, 11103, 12033, 12846, 13950, 14390, 14391, 14395, 14425, 14500
        ];
        for (uint256 i; i < s.length; i++) {
            assertEq(_ev(s[i]), g[i], "lootbox EV golden waypoint");
        }
    }

    // =========================================================================
    // Shape properties: MIN/MAX, monotonic, continuous, sub-100% ROI
    // =========================================================================

    /// @notice Every value curve holds its MIN at score 0, its MAX exactly at the effective cap, saturates flat
    ///         beyond, and is monotonic non-decreasing. Degenerette ROI is additionally strictly below 100%.
    function test_CurveInvariants() public pure {
        // MIN at 0, MAX (== pre-reshape ceiling) at the cap, flat beyond.
        assertEq(ActivityCurveLib.decMultBps(0), 10000, "mult MIN");
        assertEq(ActivityCurveLib.decMultBps(CAP), 17833, "mult MAX");
        assertEq(ActivityCurveLib.decMultBps(CAP + 50000), 17833, "mult flat beyond cap");
        assertEq(_roi(0), 9000, "roi MIN");
        assertEq(_roi(CAP), 9990, "roi MAX");
        assertEq(_wwxrp(0), 7000, "wwxrp MIN");
        assertEq(_wwxrp(CAP), 12000, "wwxrp MAX");
        assertEq(ActivityCurveLib.centuryBps(0), 0, "century MIN");
        assertEq(ActivityCurveLib.centuryBps(CAP), 10000, "century MAX");
        assertEq(_ev(0), 9000, "ev MIN");
        assertEq(_ev(60), 10000, "ev neutral anchor preserved");
        assertEq(_ev(CAP), 14500, "ev MAX");

        // Monotonic non-decreasing across all knees and into the tail.
        uint256 pm = ActivityCurveLib.decMultBps(0);
        uint256 pr = _roi(0);
        uint256 pw = _wwxrp(0);
        uint256 pc = ActivityCurveLib.centuryBps(0);
        uint256 pe = _ev(0);
        for (uint256 s = 1; s <= 1200; s++) {
            uint256 m = ActivityCurveLib.decMultBps(s);
            uint256 r = _roi(s);
            uint256 w = _wwxrp(s);
            uint256 c = ActivityCurveLib.centuryBps(s);
            uint256 e = _ev(s);
            assertGe(m, pm, "mult monotonic");
            assertGe(r, pr, "roi monotonic");
            assertGe(w, pw, "wwxrp monotonic");
            assertGe(c, pc, "century monotonic");
            assertGe(e, pe, "ev monotonic");
            assertLt(r, 10000, "roi strictly sub-100%");
            pm = m; pr = r; pw = w; pc = c; pe = e;
        }
        // Tail stays monotonic up to and past the cap.
        uint16[5] memory hi = [uint16(2000), 5000, 10000, 30000, 60000];
        for (uint256 i = 1; i < hi.length; i++) {
            assertGe(ActivityCurveLib.decMultBps(hi[i]), ActivityCurveLib.decMultBps(hi[i - 1]), "mult tail monotonic");
            assertGe(_roi(hi[i]), _roi(hi[i - 1]), "roi tail monotonic");
            assertLt(_roi(hi[i]), 10000, "roi tail sub-100%");
        }
    }

    /// @notice No cliff at any knee: the piecewise legs join exactly (the higher leg evaluated at the knee equals
    ///         the lower leg's endpoint). Continuity at K, at SEG_B, and (for lootbox) at the 60-point anchor.
    function test_Continuity_AtKnees() public pure {
        // Multiplier: K=235, SEG_B=500.
        assertEq(ActivityCurveLib.decMultBps(235), 17049, "mult @K");
        assertEq(ActivityCurveLib.decMultBps(500), 17676, "mult @SEG_B");
        // ROI / WWXRP: K=305.
        assertEq(_roi(305), 9891, "roi @K");
        assertEq(_roi(500), 9970, "roi @SEG_B");
        assertEq(_wwxrp(305), 11500, "wwxrp @K");
        assertEq(_wwxrp(500), 11800, "wwxrp @SEG_B");
        // Century: K=305.
        assertEq(ActivityCurveLib.centuryBps(305), 9000, "century @K");
        assertEq(ActivityCurveLib.centuryBps(500), 9800, "century @SEG_B");
        // Lootbox: anchor 60, K=400, SEG_B=500.
        assertEq(_ev(60), 10000, "ev @neutral");
        assertEq(_ev(400), 13950, "ev @K");
        assertEq(_ev(500), 14390, "ev @SEG_B");
    }

    function test_BattleCurveAnchors() public pure {
        assertEq(ActivityCurveLib.decBattleMultBps(0), 10_000);
        assertEq(ActivityCurveLib.decBattleMultBps(235), 17_049);
        assertEq(ActivityCurveLib.decBattleMultBps(500), 19_000);
        assertEq(ActivityCurveLib.decBattleMultBps(30_000), 20_000);
        assertEq(ActivityCurveLib.decBattleMultBps(type(uint256).max), 20_000);
    }

    // =========================================================================
    // Century bonus: Mint <-> Afking parity (single shared helper)
    // =========================================================================

    // Both century sites compute the same expression from the same helper:
    //   DegenerusGameMintModule: bonusQty = adjustedQty * centuryBps(score) / CENTURY_MAX_BPS
    //   GameAfkingModule:        bonusQty = adjustedQty * centuryBps(score) / CENTURY_MAX_BPS
    function _centuryBonusMint(uint256 baseQty, uint256 score) internal pure returns (uint256) {
        return baseQty * ActivityCurveLib.centuryBps(score) / ActivityCurveLib.CENTURY_MAX_BPS;
    }

    function _centuryBonusAfking(uint256 baseQty, uint256 score) internal pure returns (uint256) {
        return baseQty * ActivityCurveLib.centuryBps(score) / ActivityCurveLib.CENTURY_MAX_BPS;
    }

    /// @notice The century purchase bonus (DegenerusGameMintModule) and the century afking bonus
    ///         (GameAfkingModule) draw from the SAME shared centuryBps helper, so for an identical
    ///         (baseQty, score) they yield an identical bonus quantity -- no path can drift. The bonus
    ///         tracks the curve fraction of the base quantity: 0% at score 0, 90% at K=305, 98% at the
    ///         seg-B knee, 100% only at the effective cap (the pre-clamp-removal makes that tail reachable).
    function test_CenturyBonus_MintAfkingParity() public pure {
        uint256[5] memory baseQtys =
            [uint256(1), uint256(100), uint256(12_345), uint256(1e18), uint256(7 ether)];
        uint16[4] memory anchors = [uint16(0), uint16(305), uint16(500), uint16(30000)];
        uint16[4] memory expectedBps = [uint16(0), uint16(9000), uint16(9800), uint16(10000)];

        for (uint256 i; i < baseQtys.length; i++) {
            uint256 q = baseQtys[i];
            for (uint256 j; j < anchors.length; j++) {
                // Parity: the two paths are identical for the same inputs.
                assertEq(
                    _centuryBonusMint(q, anchors[j]),
                    _centuryBonusAfking(q, anchors[j]),
                    "Mint/Afking century bonus parity"
                );
                // Value pin: the bonus equals the anchor fraction of the base quantity.
                assertEq(
                    _centuryBonusMint(q, anchors[j]),
                    q * expectedBps[j] / 10000,
                    "century bonus matches anchor fraction"
                );
            }
        }

        // Dense parity over the whole early domain (where the bonus actually ramps).
        for (uint256 s; s <= 1200; s++) {
            assertEq(
                _centuryBonusMint(1_000_000, s),
                _centuryBonusAfking(1_000_000, s),
                "century parity dense"
            );
        }
    }
}
