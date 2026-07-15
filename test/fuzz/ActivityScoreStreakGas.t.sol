// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";

/// @title ActivityScoreStreakGas — gas comparison for the DECSTREAK fix (Option B).
/// @notice Measures the per-call gas of the three effective-streak read options so the
///         lightweight getter's cost can be compared to the heavy getPlayerQuestView and the
///         old raw read:
///           - quests.playerQuestStates(p)   : the old RAW read (status quo, but exploitable)
///           - quests.effectiveBaseStreak(p) : Option B (decay logic only — what we shipped)
///           - quests.getPlayerQuestView(p)  : Option A (full quest-view struct materialization)
contract ActivityScoreStreakGasTest is DeployProtocol {
    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
    }

    function test_gas_streakReads() public {
        address p = makeAddr("streak_gas_probe");

        uint256 g1 = gasleft();
        quests.playerQuestStates(p);
        uint256 rawGas = g1 - gasleft();

        uint256 g2 = gasleft();
        quests.effectiveBaseStreak(p);
        uint256 effGas = g2 - gasleft();

        uint256 g3 = gasleft();
        quests.getPlayerQuestView(p);
        uint256 fullGas = g3 - gasleft();

        emit log_named_uint("A) raw playerQuestStates gas (status quo)", rawGas);
        emit log_named_uint("B) effectiveBaseStreak gas (SHIPPED)", effGas);
        emit log_named_uint("   getPlayerQuestView gas (heavy alt)", fullGas);
        emit log_named_uint("   delta B over raw (fix cost)", effGas > rawGas ? effGas - rawGas : 0);
        emit log_named_uint("   delta heavy over B (gas B saves)", fullGas > effGas ? fullGas - effGas : 0);

        // Sanity floor so this gas probe contributes a real signal rather than a vacuous green:
        // each read must consume non-zero gas (a 0 would mean the call was elided/reverted, making
        // the comparison meaningless), and the SHIPPED lightweight getter (B) must not cost more
        // than the heavy full-struct view (A, getPlayerQuestView) it was introduced to undercut.
        assertGt(effGas, 0, "effectiveBaseStreak read consumed no gas (call elided/reverted)");
        assertGt(fullGas, 0, "getPlayerQuestView read consumed no gas (call elided/reverted)");
        assertGt(rawGas, 0, "raw playerQuestStates read consumed no gas (call elided/reverted)");
        assertLe(effGas, fullGas, "SHIPPED effectiveBaseStreak (B) must not cost more than the heavy getPlayerQuestView (A)");
    }
}
