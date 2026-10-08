// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {MineFlipGasBounds as GasBounds} from "../../contracts/libraries/MineFlipGasBounds.sol";
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
        _setRngRequestActive(true);
        _setRngSessionPublished(false);
        _setRngComplete(false);
        rngRequestTime = uint48(block.timestamp);
        rngRequestDay = day;
        rngWordCurrent = 987654321;
        _recordDailyRng(day, 0);
        _recordDailyRng(day - 1, 12345);

    }
}

/// @dev Retains the complete facade for callback/view dependencies while exposing
///      the exact native phase selected by Miner. No production cost is mocked.
contract ProtocolDailyGasHost is DegenerusGame {
    function publishOnly() external {
        _callPhase(ContractAddresses.GAME_RNG_MODULE, abi.encodeWithSignature("publishRng()"));
    }
    function applyOnly() external {
        _callPhase(ContractAddresses.GAME_ADVANCE_MODULE, abi.encodeWithSignature("applyDailyWord()"));
    }
    function _callPhase(address target, bytes memory data) private {
        (bool ok, bytes memory reason) = target.delegatecall(data);
        if (!ok) assembly ("memory-safe") { revert(add(reason, 32), mload(reason)) }
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
        game.mineFlip{gas: 10_000_000}(0);
        uint256 used = beforeGas - gasleft() + 21_192;
        emit log_named_uint("cold RNG settlement plus six automatic boons including intrinsic", used);
        // This call must make progress with the supplied allowance and commit all six awards.
        // The separate native phase test checks DAILY_APPLY; a whole engine call may compose more work.
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 awarded;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == keccak256("ProtocolBoonDrawAwarded(uint32,uint32,uint24,uint8,uint32,uint8)")) ++awarded;
        }
        assertEq(awarded, 6, "all six awards committed without a player claim");
        DegenerusGameLens lens = new DegenerusGameLens();
        uint24 day = game.currentDayView();
        assertEq(lens.protocolBoonPool(address(game), address(vault), day - 1).awardedMask, 7);
        assertEq(lens.protocolBoonPool(address(game), address(sdgnrs), day - 1).awardedMask, 7);
        vm.warp(vm.getBlockTimestamp() + 1 days);
        vm.recordLogs();
        game.mineFlip(0);
        logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            assertTrue(logs[i].topics[0] != keccak256("ProtocolBoonDrawAwarded(uint32,uint32,uint24,uint8,uint32,uint8)"), "resume re-awarded a slot");
        }
    }

    function testNativeDailyApplyColdSixBoonsFitsSavedBound() public {
        vm.etch(address(game), type(ProtocolDailyGasHost).runtimeCode);
        ProtocolDailyGasHost host = ProtocolDailyGasHost(payable(address(game)));
        host.publishOnly();
        vm.recordLogs();
        host.applyOnly{gas: 12_000_000}();
        uint256 used = vm.lastCallGas().gasTotalUsed;
        if (!vm.envOr("FOUNDRY_ISOLATE", false)) used += 21_192;
        emit log_named_uint("native_daily_apply_six_boons_including_intrinsic", used);
        assertLt(used, GasBounds.DAILY_APPLY, "complete native daily phase exceeds saved admission bound");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 awards;
        uint256 applies;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length == 0) continue;
            if (logs[i].topics[0] == keccak256("ProtocolBoonDrawAwarded(uint32,uint32,uint24,uint8,uint32,uint8)")) ++awards;
            if (logs[i].topics[0] == keccak256("DailyRngApplied(uint24,uint256,uint256,uint256)")) ++applies;
        }
        assertEq(awards, 6, "all maximum-depth draws must run inside the measured phase");
        assertEq(applies, 1, "phase must consume a fresh daily word exactly once");
        assertTrue(game.rngLocked(), "native application leaves the later daily phases locked");
    }

    function testInsufficientGasCannotDiscardOrSealAwards() public {
        uint24 day = game.currentDayView();
        (bool ok,) = address(game).call{gas: 100_000}(abi.encodeCall(game.mineFlip, (uint32(0))));
        // A low-gas call may return without progress or fail naturally; neither may
        // consume the day word or drop any owed boon.
        ok;
        DegenerusGameLens lens = new DegenerusGameLens();
        assertEq(game.rngWordForDay(day), 0, "failed advance cannot record the word");
        assertEq(lens.protocolBoonPool(address(game), address(vault), day - 1).awardedMask, 0);
        assertEq(lens.protocolBoonPool(address(game), address(sdgnrs), day - 1).awardedMask, 0);
        game.mineFlip(0);
        assertEq(lens.protocolBoonPool(address(game), address(vault), day - 1).awardedMask, 7);
        assertEq(lens.protocolBoonPool(address(game), address(sdgnrs), day - 1).awardedMask, 7);
    }
}
