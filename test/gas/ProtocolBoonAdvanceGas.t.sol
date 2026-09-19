// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {DegenerusGameLens} from "../../contracts/DegenerusGameLens.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {ProtocolBoonDrawSeeder} from "./helpers/ProtocolBoonDrawSeeder.sol";
import {Vm} from "forge-std/Vm.sol";

contract ProtocolDrawGasSeeder is DegenerusGameStorage {
    function seed() external {
        uint24 day = _simulatedDayIndex();
        dailyIdx = day - 1;
        ticketsFullyProcessed = true;
        subsFullyProcessed = true;
        _afkingResetDay = day;
        rngLockedFlag = true;
        rngRequestTime = uint48(block.timestamp);
        rngWordCurrent = 987654321;
        rngWordByDay[day] = 0;
        rngWordByDay[day - 1] = 12345;

    }
}

contract ProtocolBoonAdvanceGasTest is DeployProtocol {
    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 2 days);
        uint24 day = game.currentDayView();
        bytes memory original = address(game).code;
        vm.etch(address(game), type(ProtocolDrawGasSeeder).runtimeCode);
        ProtocolDrawGasSeeder(address(game)).seed();
        vm.etch(address(game), type(ProtocolBoonDrawSeeder).runtimeCode);
        ProtocolBoonDrawSeeder(address(game)).seedPools(day, 987654321);
        vm.etch(address(game), original);
    }
    function testColdAdvanceAwardsSixAtMaximumSearchDepthAndResumes() public {
        vm.recordLogs();
        uint256 beforeGas = gasleft();
        game.advanceGame{gas: 16_777_216 - 21_064}();
        uint256 used = beforeGas - gasleft() + 21_064;
        emit log_named_uint("cold RNG settlement plus six automatic boons including intrinsic", used);
        assertLt(used, 3_000_000, "daily settlement plus six maximum-depth searches must remain bounded");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 awarded;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == keccak256("ProtocolBoonDrawAwarded(address,address,uint24,uint8,uint32,uint8)")) ++awarded;
        }
        assertEq(awarded, 6, "all six awards committed without a player claim");
        DegenerusGameLens lens = new DegenerusGameLens();
        uint24 day = game.currentDayView();
        assertEq(lens.protocolBoonPool(address(game), address(vault), day - 1).awardedMask, 7);
        assertEq(lens.protocolBoonPool(address(game), address(sdgnrs), day - 1).awardedMask, 7);
        vm.warp(block.timestamp + 1 days);
        vm.recordLogs();
        game.advanceGame();
        logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            assertTrue(logs[i].topics[0] != keccak256("ProtocolBoonDrawAwarded(address,address,uint24,uint8,uint32,uint8)"), "resume re-awarded a slot");
        }
    }

    function testInsufficientGasCannotDiscardOrSealAwards() public {
        uint24 day = game.currentDayView();
        (bool ok,) = address(game).call{gas: 100_000}(abi.encodeCall(game.advanceGame, ()));
        assertFalse(ok, "the deliberately underfunded advance should fail");
        DegenerusGameLens lens = new DegenerusGameLens();
        assertEq(game.rngWordForDay(day), 0, "failed advance cannot record the word");
        assertEq(lens.protocolBoonPool(address(game), address(vault), day - 1).awardedMask, 0);
        assertEq(lens.protocolBoonPool(address(game), address(sdgnrs), day - 1).awardedMask, 0);
        game.advanceGame();
        assertEq(lens.protocolBoonPool(address(game), address(vault), day - 1).awardedMask, 7);
        assertEq(lens.protocolBoonPool(address(game), address(sdgnrs), day - 1).awardedMask, 7);
    }
}
