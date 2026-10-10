// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {CrapsPins} from "./CrapsPins.sol";
import {CrapsViews} from "./CrapsViews.sol";
import {LootboxCraps} from "../../contracts/LootboxCraps.sol";
import {JackpotBattle} from "../../contracts/JackpotBattle.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {Vm} from "forge-std/Vm.sol";

contract CrapsGlobalWorkOrderTest is CrapsPins {
    CrapsViews private table;
    JackpotBattle private cohort;
    uint64 private first;
    uint64 private second;
    uint48 private index;

    function setUp() public {
        _installPins();
        table = new CrapsViews();
        cohort = JackpotBattle(address(table));
        vm.prank(vaultOwner);
        table.setBattleCreator(address(this), true);
        first = table.createBattle(300, 2, 5, 0, uint40(block.timestamp + 60), true, 0);
        second = table.createBattle(300, 2, 5, 0, uint40(block.timestamp + 60), true, 0);
        table.enterBattle(first, 0, 1);
        table.enterBattle(second, 0, 1);
        vm.warp(block.timestamp + 60);
        index = table.closeBattle(first);
        _setIndex(index);
        assertEq(table.closeBattle(second), index);
        _setWord(index, 0xC0FFEE);
    }

    function _worker(uint256 allowance) private returns (MineFlipGas.Result memory result) {
        vm.prank(ContractAddresses.GAME);
        return cohort.runCrapsReadWork(index, allowance);
    }

    /// @dev An earlier RNG consumer stage blocks read settlement: neither the read worker nor the
    ///      maintenance worker touches a committed field until the read cohort is the live stage.
    function test_EarlierCategoriesBlockReadSettlement() public {
        for (uint8 stage; stage < 6; ++stage) {
            game.setRngConsumerStage(stage);
            MineFlipGas.Result memory result = _worker(gasleft());
            assertFalse(result.progressed);
            assertFalse(result.done);
            _maintain(table);
            assertEq(table.bonusCursorOf(first), 0);
        }
        game.setRngConsumerStage(6);
        assertTrue(_worker(gasleft()).progressed);
        assertEq(table.bonusCursorOf(first), 1);
    }

    /// @dev The read worker takes the committed fields strictly in order: the later field cannot
    ///      settle before the earlier one, and a drained cohort is a no-op.
    function test_ReadWorkSettlesCommittedFieldsInOrder() public {
        _worker(gasleft());
        assertEq(table.bonusCursorOf(first), 1);
        assertEq(table.bonusCursorOf(second), 0);
        assertFalse(table.rngCohortComplete(index));
        _worker(gasleft());
        assertEq(table.bonusCursorOf(second), 1);
        assertTrue(table.rngCohortComplete(index));
        MineFlipGas.Result memory result = _worker(gasleft());
        assertFalse(result.progressed);
        assertTrue(result.done);
        assertTrue(table.rngCohortComplete(index));
    }

    function test_OnlyGameCanSupplyWorkerAllowance() public {
        vm.expectRevert();
        cohort.runCrapsReadWork(index, 9_000_000);
        vm.expectRevert();
        table.runCrapsMaintenance(9_000_000);
    }

    function test_ProtocolAllowanceReservesEntireAtomicSeat() public {
        MineFlipGas.Result memory result = _worker(1_000_000);
        assertFalse(result.progressed);
        assertEq(table.bonusCursorOf(first), 0);
        uint256 before = gasleft();
        result = _worker(3_000_000);
        assertLt(before - gasleft(), 3_000_000);
        assertTrue(result.progressed);
        assertEq(result.rewardBasis, 1);
        assertEq(table.bonusCursorOf(first), 1);
        assertEq(table.bonusCursorOf(second), 0);
    }

    function test_ZeroWorkerAllowanceLeavesSettlementAndLifecycleUntouched() public {
        MineFlipGas.Result memory result = _worker(0);
        assertFalse(result.progressed);
        uint64 keeper = table.minerSlot();
        game.setRngConsumerStage(7);
        vm.prank(ContractAddresses.GAME);
        result = table.runCrapsMaintenance(0);
        assertFalse(result.progressed);
        assertEq(table.minerSlot(), keeper);
        assertEq(table.bonusCursorOf(first), 0);
    }

    function test_FundedGasLimitsHaveIdenticalReceiptsAndLowGasLeavesSafeCheckpoint() public {
        bytes32 expected;
        uint256[3] memory limits = [uint256(10_000_000), 15_000_000, 25_000_000];
        for (uint256 i; i < limits.length; ++i) {
            uint256 snap = vm.snapshotState();
            vm.recordLogs();
            vm.prank(ContractAddresses.GAME);
            (bool ok,) = address(table).call{gas: limits[i]}(abi.encodeCall(cohort.runCrapsReadWork, (index, limits[i])));
            assertTrue(ok, "funded fixed batch failed");
            bytes32 digest = keccak256(abi.encode(table.battleOf(table.keyOfSlot(first)),
                table.bonusCursorOf(first), coinflip.totalCredited(), vm.getRecordedLogs()));
            if (i == 0) expected = digest;
            else assertEq(digest, expected);
            vm.revertToState(snap);
        }
        bytes32 beforeBoard = keccak256(abi.encode(table.battleOf(table.keyOfSlot(first))));
        vm.prank(ContractAddresses.GAME);
        (bool ok,) = address(table).call{gas: 300_000}(abi.encodeCall(cohort.runCrapsReadWork, (index, 300_000)));
        // A low-gas caller may return at an atomic checkpoint or revert; neither consumes a seat here.
        assertEq(table.bonusCursorOf(first), 0);
        assertEq(keccak256(abi.encode(table.battleOf(table.keyOfSlot(first)))), beforeBoard);
        _worker(gasleft());
        assertEq(table.bonusCursorOf(first), 1);
    }

    /// @dev Settlement outcomes are a function of state alone: production-sized 10M chunks on warm
    ///      state and whole-gas chunks on cold state settle the same deep field identically.
    function test_WarmnessAndChunkBoundariesPreserveFinalResults() public {
        _worker(gasleft());
        _worker(gasleft());
        assertTrue(table.rngCohortComplete(index));
        uint64 deep = table.createBattle(300, 25, 1000, 75, uint40(block.timestamp + 60), true, 255);
        uint32 chips = 1 | uint32(1) << 3 | uint32(1) << 6 | uint32(1) << 9
            | uint32(1) << 12 | uint32(1) << 15 | uint32(1) << 18;
        for (uint256 i; i < 160; ++i) {
            address player = address(uint160(0xD0000 + i));
            vm.prank(player);
            table.enterBattle(deep, chips, 255);
        }
        vm.warp(block.timestamp + 60);
        uint48 draw = table.closeBattle(deep);
        _setWord(draw, 0xBADC0DE);
        bytes32 expected;
        for (uint256 mode; mode < 2; ++mode) {
            uint256 snap = vm.snapshotState();
            if (mode == 0) {
                for (uint64 seat = 1; seat <= 160; ++seat) table.previewSettlement((uint256(deep) << 64) | seat);
            } else {
                vm.cool(address(table));
                vm.cool(ContractAddresses.CRAPS_ENGINE);
                vm.cool(ContractAddresses.JACKPOT_BATTLE);
                vm.cool(ContractAddresses.COINFLIP);
            }
            for (uint256 i; i < 64 && !table.battleOf(table.keyOfSlot(deep)).finalized; ++i) {
                vm.prank(ContractAddresses.GAME);
                cohort.runCrapsReadWork(draw, mode == 0 ? 10_000_000 : gasleft());
            }
            assertTrue(table.battleOf(table.keyOfSlot(deep)).finalized);
            bytes32 digest = keccak256(abi.encode(table.battleOf(table.keyOfSlot(deep)),
                table.bonusCursorOf(deep), coinflip.totalCredited(), table.progressivePool()));
            if (mode == 0) expected = digest;
            else assertEq(digest, expected, "warmness cannot change settled outcomes");
            vm.revertToState(snap);
        }
    }

}
