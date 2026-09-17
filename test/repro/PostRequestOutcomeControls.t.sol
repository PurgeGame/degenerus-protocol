// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {CrapsProgressiveTest} from "../craps/CrapsProgressive.t.sol";
import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {BoonBatchParityHarness, BoonBatchQuestRecorder} from "../fuzz/BoonBatchParity.t.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @notice Audit witnesses, asserting the current vulnerable behavior rather than a fix.
///         Progressive fixtures inject finalized results through existing production-helper taps.
contract PostRequestProgressiveControls is CrapsProgressiveTest {
    function testAuditOtherDayVictoryErasesEarnedEventDouble() public {
        uint256 pool = 1_000_000 ether;
        uint256 standing = craps.SYBIL_SCORE_FLOOR();
        craps.noteRoutineVictory(TAP_SLOT, true, alice);
        craps.seedProgressive(pool);
        uint256 snapshot = vm.snapshotState();
        uint256 normal = craps.awardAt(TAP_EVENT_SLOT, 3000, true, 360_000, standing, alice);
        assertTrue(vm.revertToState(snapshot));
        // Resolve an already-known routine victory from another day before the event.
        craps.noteRoutineVictory(TAP_SLOT_DAY2, true, alice);
        uint256 reordered = craps.awardAt(TAP_EVENT_SLOT, 3000, true, 360_000, standing, alice);
        assertEq(normal, 800_000 ether);
        assertEq(reordered, 400_000 ether);
    }

    function testAuditCrossBattleOrderChangesSameWinningAward() public {
        uint256 standing = craps.SYBIL_SCORE_FLOOR();
        craps.seedProgressive(1_000_000 ether);
        uint256 snapshot = vm.snapshotState();
        uint256 aliceFirst = craps.awardAt(TAP_EVENT_SLOT, 3000, true, 360_000, standing, alice);
        craps.awardAt(TAP_SLOT_DAY2, 3000, true, 360_000, standing, bob);
        assertTrue(vm.revertToState(snapshot));
        craps.awardAt(TAP_SLOT_DAY2, 3000, true, 360_000, standing, bob);
        uint256 aliceLast = craps.awardAt(TAP_EVENT_SLOT, 3000, true, 360_000, standing, alice);
        assertEq(aliceFirst, 400_000 ether);
        assertEq(aliceLast, 360_000 ether);
    }
}

contract PostRequestBoonControls is Test {
    BoonBatchParityHarness private boon;
    bytes32 private constant REWARD = keccak256("LootBoxReward(address,uint8,uint256,uint256)");

    function setUp() public {
        vm.warp(1_900_000_000);
        BoonBatchParityHarness implementation = new BoonBatchParityHarness();
        vm.etch(ContractAddresses.GAME, address(implementation).code);
        boon = BoonBatchParityHarness(ContractAddresses.GAME);
        BoonBatchQuestRecorder quests = new BoonBatchQuestRecorder();
        vm.etch(ContractAddresses.QUESTS, address(quests).code);
    }

    function _reward(uint256 seed, uint24 lvl) private returns (uint256 rewardType) {
        vm.recordLogs();
        boon.rollBoxBoons(address(0xB00B), 0.025 ether, 1, 0.25 ether, lvl, seed, 0);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == REWARD) return uint256(logs[i].topics[2]);
        }
    }

    function testAuditSameSeedDifferentLiveLevelChangesBoonType() public {
        for (uint256 seed = 1; seed < 1000; ++seed) {
            uint256 snapshot = vm.snapshotState();
            uint256 first = _reward(seed, 100);
            assertTrue(vm.revertToState(snapshot));
            snapshot = vm.snapshotState();
            uint256 second = _reward(seed, 101);
            assertTrue(vm.revertToState(snapshot));
            if (first != 0 && second != 0 && first != second) {
                emit log_named_uint("fixed seed", seed);
                emit log_named_uint("boon at level 100", first);
                emit log_named_uint("boon at level 101", second);
                return;
            }
        }
        fail("no different delivered boon types found");
    }
}
