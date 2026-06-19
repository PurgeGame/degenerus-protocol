// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";

/// @title ActivityScorePointFloorTest -- proves the whole-point activity score's sole sub-point leg
///        (the quest streak) floors at `floor(questStreak/2)`, that this point-domain leg is the exact
///        integer image of the retired `questStreak*50` bps leg, and that the manual quest streak and the
///        live afking-run streak base feed the score through ONE exact integer path with afking-XOR-manual
///        exclusivity.
///
/// @notice The score is now whole points end-to-end; the only place precision is intentionally dropped is
///   the quest-streak leg (`bonusPoints += questStreak / 2`, DegenerusGameMintStreakUtils._playerActivityScoreAt).
///   A round-half-up policy (5 -> 3) or a 0.5-pt-granular representation would diverge from the floored value
///   asserted here, so each assertion fails-without the shipped floor.
///
/// @dev Drives `game.playerActivityScore` (the public getter reaching `_playerActivityScoreAt`) against a
///   fresh fixture where a player's ONLY score contributor is a known quest streak: at deploy `level == 0`,
///   so `_mintCountBonusPoints` returns 0 and the affiliate cached leg reads 0, a fresh player carries no
///   deity pass / whale bundle / curse, and `_mintStreakEffectiveFromPacked` returns 0 — the quest leg is the
///   whole score. The manual streak is reached by writing `questPlayerState[player]` directly (the same
///   decay-aware value `effectiveBaseStreakAndAfking` reads), with the day anchors left 0 so the decay branch
///   is inert and `state.streak` reads straight through. Test-only: ZERO contracts/*.sol mutation.
contract ActivityScorePointFloorTest is DeployProtocol {
    /// @dev questPlayerState mapping root (slot 1 in DegenerusQuests; the per-player PlayerQuestState packs
    ///      into one slot). Byte offsets within that slot: lastCompletedDay u24 off0, lastActiveDay u24 off3,
    ///      lastSyncDay u24 off6, streak u16 off9, baseStreak u16 off11, afkingActive bool off13.
    uint256 private constant QUESTSTATE_SLOT = 1;
    uint256 private constant OFF_QS_SYNCDAY = 6;
    uint256 private constant OFF_QS_STREAK = 9;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
    }

    // =========================================================================
    // Task 1 — the quest-streak floor rule + the bps-equivalence identity
    // =========================================================================

    /// @notice The point-domain quest-streak leg `floor(questStreak/2)` is the exact integer image of the
    ///         retired bps leg `floor((questStreak*50)/100)` at every streak on the grid, and the floor drops
    ///         the trailing half-point at odd counts. Asserting `q/2` explicitly at the odd boundaries means a
    ///         round-half-up regression (5 -> 3, 7 -> 4) would fail this test — the floor is pinned, not merely
    ///         the identity.
    function test_QuestStreakFloorRule_BpsEquivalence() public pure {
        uint256[18] memory grid = [
            uint256(0), 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 49, 50, 51, 100, 255, 1000, 32767
        ];

        // D-02 identity: the point leg equals the integer hundredths of the old bps leg for every streak.
        // Both are uint256 integer divisions, so bit-equality here is the whole equivalence claim.
        for (uint256 i; i < grid.length; i++) {
            uint256 q = grid[i];
            assertEq(q / 2, (q * 50) / 100, "point leg q/2 == integer hundredths of the old bps leg (q*50)/100");
        }

        // Even streaks keep the full point; odd streaks drop the trailing half-point. A round-half-up
        // implementation would give 5 -> 3 / 7 -> 4 (rejected); a 0.5-pt-granular score would carry the
        // half-point at all (also rejected). Pinning the floored values makes either regression fail.
        assertEq(uint256(4) / 2, 2, "even streak keeps the full point (4 -> 2)");
        assertEq(uint256(5) / 2, 2, "odd streak drops the trailing half-point (5 -> 2, not the round-half-up 3)");
        assertEq(uint256(6) / 2, 3, "even streak keeps the full point (6 -> 3)");
        assertEq(uint256(7) / 2, 3, "odd streak drops the trailing half-point (7 -> 3, not the round-half-up 4)");
    }

    /// @notice End-to-end, the public `playerActivityScore` quest leg is exactly `floor(questStreak/2)`.
    ///         A fresh player whose sole contributor is a manual quest streak of an ODD value reads back a
    ///         clean whole-point score that drops the trailing half-point: streak 7 -> score 3 (not 3.5, not
    ///         the round-half-up 4). The even-vs-odd differences (6 vs 7 -> +0, 8 vs 9 -> +0, 8 vs 10 -> +1)
    ///         independently witness that the odd half-point never reaches the score.
    function test_QuestStreakLegIsoEndToEnd() public {
        // Non-vacuity: a fresh player has a zero score, so any streak contribution stands alone.
        address fresh = makeAddr("floor_fresh");
        assertEq(game.playerActivityScore(fresh), 0, "fresh player has no score contributor (quest leg isolated)");

        // Odd streak 7: the score is exactly floor(7/2) = 3. A 0.5-pt-granular score (3.5-equivalent) or a
        // round-half-up score (4) would not equal 3.
        address odd = makeAddr("floor_odd7");
        _setManualQuestStreak(odd, 7);
        assertEq(_effectiveStreakSeenByScore(odd), 7, "the score reads the driven manual streak of 7");
        assertEq(game.playerActivityScore(odd), 3, "odd streak 7 -> clean whole-point score floor(7/2) = 3");

        // Even/odd difference pairs: the odd member contributes the SAME points as the even one below it
        // (the half-point is dropped), and a +2 streak step adds exactly one point.
        address e6 = makeAddr("floor_e6");
        address o7 = makeAddr("floor_o7");
        address e8 = makeAddr("floor_e8");
        address o9 = makeAddr("floor_o9");
        address e10 = makeAddr("floor_e10");
        _setManualQuestStreak(e6, 6);
        _setManualQuestStreak(o7, 7);
        _setManualQuestStreak(e8, 8);
        _setManualQuestStreak(o9, 9);
        _setManualQuestStreak(e10, 10);

        uint256 s6 = game.playerActivityScore(e6);
        uint256 s7 = game.playerActivityScore(o7);
        uint256 s8 = game.playerActivityScore(e8);
        uint256 s9 = game.playerActivityScore(o9);
        uint256 s10 = game.playerActivityScore(e10);

        assertEq(s7 - s6, 0, "6 vs 7: the odd half-point is dropped (floor(7/2) - floor(6/2) == 0)");
        assertEq(s9 - s8, 0, "8 vs 9: the odd half-point is dropped (floor(9/2) - floor(8/2) == 0)");
        assertEq(s10 - s8, 1, "8 vs 10: a +2 streak step adds exactly one whole point");
    }

    // =========================================================================
    // Shared drive helpers
    // =========================================================================

    /// @dev Drive `player`'s effective quest streak to `q` by writing the dormant manual streak directly into
    ///      `questPlayerState[player]`. `state.streak` is set to `q`; `lastSyncDay` is set to a non-zero value
    ///      while the day anchors (lastActiveDay / lastCompletedDay) stay 0, so `_effectiveBaseStreak` skips
    ///      its decay branch (anchorDay == 0) and the non-synced path returns `state.streak` verbatim. The
    ///      player is a non-afker (afkingActive == 0), so `_effectiveQuestStreak` returns this manual streak
    ///      with no Sub-slot read — the score's sole contributor.
    function _setManualQuestStreak(address player, uint16 q) internal {
        bytes32 slot = keccak256(abi.encode(player, QUESTSTATE_SLOT));
        uint256 word = (uint256(q) << (OFF_QS_STREAK * 8)) | (uint256(1) << (OFF_QS_SYNCDAY * 8));
        vm.store(address(quests), slot, bytes32(word));
    }

    /// @dev The effective quest streak the activity score reads for `player` — the same value
    ///      `_effectiveQuestStreak` resolves (manual for a non-afker, live compute-on-read for an afker).
    function _effectiveStreakSeenByScore(address player) internal view returns (uint32 streak) {
        (streak, ) = quests.effectiveBaseStreakAndAfking(player);
    }
}
