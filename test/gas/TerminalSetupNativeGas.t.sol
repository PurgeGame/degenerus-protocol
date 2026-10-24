// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {ColdTerminalFixture} from "./AdvanceColdTerminalGas.t.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {Vm} from "forge-std/Vm.sol";

contract TerminalSetupNativeHost is DegenerusGame {
    function nativeTerminalSetup(uint256 allowance) external {
        (bool ok, bytes memory reason) = ContractAddresses.GAME_GAMEOVER_MODULE.delegatecall(
            abi.encodeWithSignature("runGameOverAdvance(uint24,uint24,uint256)", _simulatedDayIndex(), level,
                MineFlipGas.budget(allowance, 10_000, true)));
        if (!ok) assembly ("memory-safe") { revert(add(reason, 32), mload(reason)) }
    }
}

/// @dev Original normal-ending fixture: 30 paid deity refunds and full trait
/// buckets. The budget retains the bounded balance-read reserve and can admit
/// later jackpot work. Native opcode/call traces separate setup from that work.
contract TerminalSetupNativeGasTest is ColdTerminalFixture {
    function _fresh() internal pure override returns (bool) { return false; }

    function test_NativeTerminalSetupThirtyRefunds() public {
        assertFalse(game.gameOver(), "setup not yet run");
        vm.etch(address(game), type(TerminalSetupNativeHost).runtimeCode);
        TerminalSetupNativeHost host = TerminalSetupNativeHost(payable(address(game)));
        uint256 snapshot = vm.snapshotState();
        vm.cool(address(game));
        vm.cool(ContractAddresses.GAME_GAMEOVER_MODULE);
        vm.cool(address(mockStETH));
        vm.cool(address(sdgnrs));
        vm.cool(address(coinflip));
        vm.recordLogs();
        host.nativeTerminalSetup(2_000_000);
        uint256 used = vm.lastCallGas().gasTotalUsed;
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 refunds;
        uint256 winners;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == keccak256("DeityPassRefundsSettled(uint256)")) refunds += abi.decode(logs[i].data, (uint256));
            if (logs[i].topics[0] == keccak256("JackpotEthWin(uint32,uint24,uint16,uint256,uint256)")) ++winners;
        }
        assertTrue(game.gameOver(), "setup latches ending");
        assertEq(refunds, 600 ether, "all 30 refunds executed");
        assertGt(winners, 0, "trace includes the separate jackpot worker");
        assertLt(used, 10_000_000, "combined setup and admitted draw fit");
        emit log_named_uint("terminal_setup_and_admitted_draw", used);
        if (bytes(vm.envOr("STORAGE_REUSE_EXPORT", string(""))).length != 0) {
            assertTrue(vm.revertToState(snapshot));
            this.exportNativeFixture("terminal-setup-thirty-refunds", address(this), address(host),
                abi.encodeCall(host.nativeTerminalSetup, (uint256(2_000_000))));
            string memory path = string.concat(vm.envString("STORAGE_REUSE_EXPORT"), "/terminal-setup-thirty-refunds.call.json");
            vm.serializeJson("terminal-setup-thirty-refunds", vm.readFile(path));
            vm.serializeUint("terminal-setup-thirty-refunds", "workerAllowance", 2_000_000);
            string memory json = vm.serializeUint("terminal-setup-thirty-refunds", "allowanceWord", 0);
            vm.writeJson(json, path);
        }
        vm.deleteStateSnapshot(snapshot);
    }
}
