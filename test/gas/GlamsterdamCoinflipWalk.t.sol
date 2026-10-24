// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {NativeGasExport} from "../helpers/NativeGasExport.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {CoinflipDeepClaimWorstCaseGas} from "./CoinflipDeepClaimWorstCaseGas.t.sol";
import {GlamsterdamReprice} from "../helpers/GlamsterdamReprice.sol";

/// @notice Re-prices the worst-case 90-day coinflip claim walks under the Glamsterdam
///         schedule (EIP-8037 / EIP-8038) from their recorded storage and account accesses;
///         see GlamsterdamReprice for the schedule delta. Execution gas must stay under 10M,
///         and so must execution plus state gas, as if no reservoir were supplied.
contract GlamsterdamCoinflipWalk is CoinflipDeepClaimWorstCaseGas, NativeGasExport {
    function test_glamsterdam_claim90_rebuyOff() public {
        _reprice(regularPlayer, _claimData(), "claim90_rebuyOff");
    }

    function test_glamsterdam_exit90_rebuyOnTakeProfit() public {
        _reprice(rebuyPlayer, _exitData(), "exit90_rebuyOn_tp1");
    }

    function test_glamsterdam_firstClaim90() public {
        _reprice(firstPlayer, _claimData(), "firstClaim90");
    }

    function _reprice(address p, bytes memory data, string memory label) internal {
        // The cold figure comes from an isolated call; the recorded replay of the same call
        // supplies the accesses (recording does not keep the call's own cold state).
        uint256 snap = vm.snapshotState();
        uint256 exec = _call(p, data);
        vm.revertToState(snap);
        vm.startStateDiffRecording();
        _call(p, data);
        VmSafe.AccountAccess[] memory acc = vm.stopAndReturnStateDiff();
        _assertWholeWindow(p);
        GlamsterdamReprice.Result memory r = GlamsterdamReprice.reprice(exec, acc, address(coinflip));
        emit log_named_string("case", label);
        emit log_named_uint("osaka_exec_gas", r.osakaExec);
        emit log_named_uint("sstores", r.sstores);
        emit log_named_uint("first_change_sstores", r.firstChanges);
        emit log_named_uint("new_slots_0_to_x", r.newSlots);
        emit log_named_uint("cold_accounts", r.coldAccounts);
        emit log_named_int("exec_delta", r.execDelta);
        emit log_named_uint("glamsterdam_exec_gas", r.glamsterdamExec);
        emit log_named_uint("glamsterdam_state_gas", r.stateGas);
        emit log_named_uint("glamsterdam_total_if_no_reservoir", r.glamsterdamExec + r.stateGas);
        assertLt(r.glamsterdamExec, GAS_TARGET, "90-day walk execution under Glamsterdam stays under 10M");
        assertLt(r.glamsterdamExec + r.stateGas, GAS_TARGET, "and with its state gas");
        if (bytes(vm.envOr("STORAGE_REUSE_EXPORT", string(""))).length != 0) {
            assertTrue(vm.revertToState(snap));
            string memory nativeLabel = string.concat("coinflip-window-", label);
            vm.serializeUint(nativeLabel, "fixedCalleeBudget", GAS_TARGET);
            vm.serializeBool(nativeLabel, "enforceBudget", true);
            this.exportNativeFixture(nativeLabel, p, address(coinflip), data);
            _call(p, data);
            _assertWholeWindow(p);
        }
        vm.deleteStateSnapshot(snap);
    }
}
