// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Test} from "forge-std/Test.sol";
import {CrapsBattle} from "../../contracts/CrapsBattle.sol";
import {CrapsEngine} from "../../contracts/CrapsEngine.sol";
import {JackpotBattle} from "../../contracts/JackpotBattle.sol";
import {CrapsBattleStorage} from "../../contracts/storage/CrapsBattleStorage.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

contract CrapsConsolidationTest is Test {
    CrapsBattle private table;

    function setUp() public {
        table = new CrapsBattle();
    }

    function test_aliasesResolveToTable() public pure {
        assertEq(ContractAddresses.CRAPS_ENGINE, ContractAddresses.CRAPS);
        assertEq(ContractAddresses.JACKPOT_BATTLE, ContractAddresses.CRAPS);
    }

    function test_unknownAndEmptySelectorsRevertWithoutData() public {
        (bool ok, bytes memory result) = address(table).call(hex"ffffffff");
        assertFalse(ok);
        assertEq(result.length, 0);
        (ok, result) = address(table).call("");
        assertFalse(ok);
        assertEq(result.length, 0);
    }

    function test_selfOnlyFramesRejectAnExternalCaller() public {
        vm.expectRevert(JackpotBattle.OnlyTableSelf.selector);
        table.registerRngSlot(0, 0, bytes32(0));
        vm.expectRevert(CrapsBattleStorage.OnlyGame.selector);
        table.resolveRngSlot(0, 1_000_000);
        CrapsBattleStorage.Window memory w;
        vm.expectRevert(JackpotBattle.OnlyTableSelf.selector);
        table.finalizeBattle(w, 0, 0);
        vm.expectRevert(JackpotBattle.OnlyTableSelf.selector);
        table.admitCustom(0);
        vm.expectRevert(JackpotBattle.OnlyTableSelf.selector);
        table.settleHighRollerReserve(0);
        vm.expectRevert(JackpotBattle.OnlyTableSelf.selector);
        table.payBattlePot(0, bytes32(0), 0, 0, 0, 0);
    }

    function test_externalEngineSurfaceRunsUnderStaticcallWithoutWrites() public {
        CrapsEngine referenceEngine = new CrapsEngine();
        bytes[] memory calls = new bytes[](4);
        calls[0] = abi.encodeCall(CrapsEngine.settleSlip,
            (0, 300, 123, 10, bytes32(uint256(9)), 30_000 ether, 300_000 ether, 17, 0));
        calls[1] = abi.encodeCall(CrapsEngine.settleSlipBounded,
            (0, 300, 123, 10, bytes32(uint256(9)), 30_000 ether, 17, 0, (uint256(600) << 16) | 32));
        calls[2] = abi.encodeCall(CrapsEngine.settleBattle,
            (17, 17, 300, 30_000, 300_000, uint48(14), uint256(5) << 64, 9));
        calls[3] = abi.encodeCall(CrapsEngine.customDefinition,
            (3_000, 10, 10, 1, uint40(block.timestamp + 1 days), false, 0));
        for (uint256 i; i < calls.length; ++i) {
            (bool expectedOk, bytes memory expected) = address(referenceEngine).staticcall(calls[i]);
            vm.record();
            (bool ok, bytes memory result) = address(table).staticcall(calls[i]);
            (, bytes32[] memory writes) = vm.accesses(address(table));
            assertTrue(expectedOk);
            assertEq(ok, expectedOk);
            assertEq(result, expected);
            assertEq(writes.length, 0);
        }
    }
}
