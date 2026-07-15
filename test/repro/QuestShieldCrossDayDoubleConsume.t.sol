// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @title QuestShieldCrossDayDoubleConsume
/// @notice Candidate F3 regression: a partial (non-completing) quest action on a rolled missed
///         day must leave the player NO WORSE OFF than doing nothing.
///
///         `_questSyncState` measures the missed-day gap from `anchorDay`
///         (= lastActiveDay, else lastCompletedDay). The anchor only advances on a completion,
///         streak-bonus, foil-floor, or afking-finalize — NOT when a sync merely consumes a
///         shield. `_missedQuestDays` is stateless: every call re-derives the whole gap from the
///         anchor, and `missLimit = streakShield + 1`. Before the fix, a partial action that
///         consumed a shield on day N left the anchor pinned; the next day's sync re-scanned the
///         SAME earlier missed day(s) against a now-smaller shield budget, double-counting the
///         miss the shield already absorbed and resetting the streak the shields were sized to
///         protect.
///
///         FIX: the gap floor advances to `lastSyncDay - 1`, so days a prior sync already
///         adjudicated are not re-billed. This test asserts the FIXED behavior — both variants
///         preserve the streak: PARTIAL streak equals IDLE streak, both > 0. (It fails against
///         the pre-fix code, where PARTIAL reset to 0.)
///
///         Test-only storage reads use compiler-derived packed offsets (mirrors
///         QuestStreakStallForgiveness.t.sol).
contract QuestShieldCrossDayDoubleConsume is DeployProtocol {
    // PlayerQuestState packed layout in questPlayerState mapping (base slot 1).
    uint256 private constant QUEST_STATE_SLOT = 1;
    uint256 private constant OFF_STREAK = 9; // uint16 streak
    uint256 private constant OFF_SHIELD = 25; // uint8 streakShield

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        vm.deal(address(game), 5_000_000 ether);
    }

    /// @notice Two players, one shared timeline, identical starting state. The ONLY difference is
    ///         whether the player performs an accounting-neutral partial action on rolled day 12.
    ///         After the fix, both keep the streak: acting is no longer worse than idling.
    function test_PartialActionOnRolledMissDayMatchesIdling() public {
        address actor = makeAddr("partial-actor");
        address control = makeAddr("idle-control");

        // --- Common setup: both players end day 10 with streak 10, shield 2, anchor day 10. ---
        _roll(10);
        _award(actor, 10, 10);
        _award(control, 10, 10);
        _grantShields(actor, 2);
        _grantShields(control, 2);

        assertEq(_streak(actor), 10, "actor: seeded streak");
        assertEq(_streak(control), 10, "control: seeded streak");
        assertEq(_shield(actor), 2, "actor: seeded shields");
        assertEq(_shield(control), 2, "control: seeded shields");

        // Days 11 and 12 both carry a rolled quest (genuine playable days).
        _roll(11);
        _roll(12);

        // --- Day 12: PARTIAL performs a below-target FLIP action; IDLE does nothing. ---
        // A 1-wei flip credit is far below any FLIP target (2000 FLIP), so it never completes.
        // `_questSyncState(...,12)` runs first: anchor=10, gap={11}, missed=1, shield 2->1,
        // streak preserved (1 <= 2), and lastSyncDay is stamped to 12.
        _partialFlip(actor);

        assertEq(_streak(actor), 10, "actor: day-12 sync preserves streak (1 miss <= 2 shields)");
        assertEq(_shield(actor), 1, "actor: day-12 sync consumed one shield for day 11");
        assertEq(_streak(control), 10, "control: untouched on day 12");
        assertEq(_shield(control), 2, "control: untouched on day 12");

        // --- Day 13: identical action for BOTH players. ---
        _roll(13);
        _partialFlip(actor);
        _partialFlip(control);

        // PARTIAL day-13 sync (fixed): the floor advances to lastSyncDay-1 = 11, so gap={12}=1,
        //   missed=1 <= shield(1) => streak PRESERVED (day 11 was already billed on day 12).
        // IDLE day-13 sync: anchor 10, gap={11,12}=2, shield 2, 2 > 2 is false => PRESERVED.
        uint256 partialStreak = _streak(actor);
        uint256 idleStreak = _streak(control);

        emit log_named_uint("PARTIAL streak after day 13", partialStreak);
        emit log_named_uint("IDLE   streak after day 13", idleStreak);

        // Fixed: a partial action bills each missed day once, so it is no worse than idling.
        assertEq(partialStreak, idleStreak, "acting is no longer worse than idling");
        assertGt(partialStreak, 0, "partial action preserves the shielded streak");
        assertEq(partialStreak, 10, "streak preserved at its seeded value");
        // Both players spent one shield per distinct missed day (days 11 and 12): 2 -> 0.
        assertEq(_shield(actor), 0, "actor: two distinct misses billed once each");
        assertEq(_shield(control), 0, "control: two distinct misses billed once each");
    }

    // --------------------------------------------------------------------- helpers

    function _roll(uint24 day) private {
        vm.prank(ContractAddresses.GAME);
        quests.rollDailyQuest(day, uint256(keccak256(abi.encode("f3-quest", day))) | 1, false, false);
    }

    function _award(address player, uint16 amount, uint24 wallDay) private {
        vm.prank(ContractAddresses.GAME);
        quests.awardQuestStreakBonus(player, amount, wallDay);
    }

    function _grantShields(address player, uint16 amount) private {
        vm.prank(ContractAddresses.GAME);
        quests.awardQuestStreakShield(player, amount);
    }

    /// @dev A partial (non-completing) quest action: 1-wei FLIP credit, far below the FLIP target.
    ///      Drives the real `handleFlip` entrypoint, so `_questSyncState` runs exactly as it does
    ///      for any live below-target flip/decimator/affiliate action.
    function _partialFlip(address player) private {
        vm.prank(ContractAddresses.COIN);
        (, , , bool completed) = quests.handleFlip(player, 1);
        assertFalse(completed, "partial flip must not complete the quest");
    }

    function _questWord(address player) private view returns (uint256) {
        return uint256(vm.load(address(quests), keccak256(abi.encode(player, QUEST_STATE_SLOT))));
    }

    function _streak(address player) private view returns (uint256) {
        return (_questWord(player) >> (OFF_STREAK * 8)) & type(uint16).max;
    }

    function _shield(address player) private view returns (uint256) {
        return (_questWord(player) >> (OFF_SHIELD * 8)) & type(uint8).max;
    }
}
