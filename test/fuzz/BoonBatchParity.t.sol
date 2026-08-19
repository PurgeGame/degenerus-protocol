// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {IDegenerusGameBoonModule} from "../../contracts/interfaces/IDegenerusGameModules.sol";
import {DegenerusGameBoonModule} from "../../contracts/modules/DegenerusGameBoonModule.sol";

contract BoonBatchParityHarness is DegenerusGameBoonModule {
    function playerState(address player)
        external
        view
        returns (uint256 slot0, uint256 slot1, uint256 mintData, uint256 whaleClaims)
    {
        BoonPacked storage bp = boonPacked[player];
        return (bp.slot0, bp.slot1, mintPacked_[player], whalePassClaims[player]);
    }
}

contract BoonBatchQuestRecorder {
    mapping(address => uint256) public streakBonus;
    mapping(address => uint256) public shields;

    event StreakBonus(address indexed player, uint16 amount, uint24 day);
    event Shields(address indexed player, uint16 amount);

    function awardQuestStreakBonus(address player, uint16 amount, uint24 day) external {
        streakBonus[player] += amount;
        emit StreakBonus(player, amount, day);
    }

    function awardQuestStreakShield(address player, uint16 amount) external {
        shields[player] += amount;
        emit Shields(player, amount);
    }
}

/// @notice Locks the mixed-tier entrypoint to the pre-batch sequence of homogeneous calls.
contract BoonBatchParity is Test {
    address private constant PLAYER = address(0xB00B);
    uint24 private constant CURRENT_LEVEL = 101;

    BoonBatchParityHarness private harness;
    IDegenerusGameBoonModule private gameBoon;
    BoonBatchQuestRecorder private questRecorder;

    function setUp() public {
        vm.warp(1_900_000_000);

        BoonBatchParityHarness implementation = new BoonBatchParityHarness();
        vm.etch(ContractAddresses.GAME, address(implementation).code);
        harness = BoonBatchParityHarness(ContractAddresses.GAME);
        gameBoon = IDegenerusGameBoonModule(ContractAddresses.GAME);

        BoonBatchQuestRecorder quests = new BoonBatchQuestRecorder();
        vm.etch(ContractAddresses.QUESTS, address(quests).code);
        questRecorder = BoonBatchQuestRecorder(ContractAddresses.QUESTS);
    }

    function testFuzzMixedBatchMatchesFiveLegacyLaneCalls(uint256 seed) public {
        uint256[5] memory amounts = [uint256(0.01 ether), 0.05 ether, 0.25 ether, 1 ether, 10 ether];
        uint40 countsPacked = 0x0101010101;
        uint256 snapshot = vm.snapshotState();

        vm.recordLogs();
        uint256 nonceBase;
        for (uint256 lane; lane < 5; ++lane) {
            gameBoon.rollBoxBoons(PLAYER, _budget(amounts[lane]), 1, amounts[lane], CURRENT_LEVEL, seed, nonceBase++);
        }
        Vm.Log[] memory expectedLogs = vm.getRecordedLogs();
        bytes32 expectedState = _stateHash();

        assertTrue(vm.revertToState(snapshot), "snapshot restore failed");

        vm.recordLogs();
        gameBoon.rollBoxBoonTiers(PLAYER, amounts, countsPacked, CURRENT_LEVEL, seed);
        Vm.Log[] memory actualLogs = vm.getRecordedLogs();

        assertEq(_stateHash(), expectedState, "batched boon state drift");
        _assertLogsEqual(actualLogs, expectedLogs);
    }

    function _budget(uint256 amount) private pure returns (uint256) {
        uint256 budget = amount / 10;
        return budget > 1 ether ? 1 ether : budget;
    }

    function _stateHash() private view returns (bytes32) {
        (uint256 s0, uint256 s1, uint256 mintData, uint256 whaleClaims) = harness.playerState(PLAYER);
        return keccak256(
            abi.encode(s0, s1, mintData, whaleClaims, questRecorder.streakBonus(PLAYER), questRecorder.shields(PLAYER))
        );
    }

    function _assertLogsEqual(Vm.Log[] memory actual, Vm.Log[] memory expected) private pure {
        assertEq(actual.length, expected.length, "batched boon log count drift");
        for (uint256 i; i < actual.length; ++i) {
            assertEq(actual[i].emitter, expected[i].emitter, "batched boon emitter drift");
            assertEq(actual[i].topics.length, expected[i].topics.length, "batched boon topic count drift");
            for (uint256 j; j < actual[i].topics.length; ++j) {
                assertEq(actual[i].topics[j], expected[i].topics[j], "batched boon topic drift");
            }
            assertEq(keccak256(actual[i].data), keccak256(expected[i].data), "batched boon data drift");
        }
    }
}
