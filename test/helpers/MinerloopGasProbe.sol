// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Test} from "forge-std/Test.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {Vm} from "forge-std/Vm.sol";
import {GlamsterdamReprice} from "./GlamsterdamReprice.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

abstract contract MinerloopGasProbe is Test {
    function _tableTranscript(Vm.Log[] memory logs) private pure returns (bytes32 digest) {
        // MinerWork reports measured gas; coinflip flushes can interleave differently
        // with seats. Table outcomes retain their canonical order across those splits.
        for (uint256 i; i < logs.length; ++i) if (logs[i].emitter == ContractAddresses.CRAPS)
            digest = keccak256(abi.encode(digest, logs[i].topics, logs[i].data));
    }

    function _poststate(VmSafe.AccountAccess[] memory acc) private view returns (bytes32 digest) {
        for (uint256 i; i < acc.length; ++i) {
            for (uint256 j; j < acc[i].storageAccesses.length; ++j) {
                VmSafe.StorageAccess memory a = acc[i].storageAccesses[j];
                digest = keccak256(abi.encode(digest, a.account, a.slot, vm.load(a.account, a.slot)));
            }
        }
    }
    /// @dev The self-call is the isolated transaction; lastCallGas describes its nested
    /// production frame and excludes transaction intrinsic gas and fixture overhead.
    function minerloopMeasured(address target, address sender, bytes calldata data, uint256 cap)
        external returns (uint256 used, bytes memory result)
    {
        require(msg.sender == address(this));
        vm.prank(sender);
        bool ok;
        (ok, result) = target.call{gas: cap}(data);
        VmSafe.Gas memory g = vm.lastCallGas();
        used = uint256(g.gasLimit) - uint256(g.gasRemaining);
        if (!ok) assembly ("memory-safe") { revert(add(result, 32), mload(result)) }
    }

    function _probe(address target, address sender, bytes memory data, uint256 cap)
        internal returns (GlamsterdamReprice.Result memory r, bytes memory result)
    {
        require(vm.envOr("FOUNDRY_ISOLATE", false), "requires isolation");
        uint256 snap = vm.snapshotState();
        uint256 used;
        vm.recordLogs();
        (used, result) = this.minerloopMeasured(target, sender, data, cap);
        bytes32 transcript = _tableTranscript(vm.getRecordedLogs());
        uint256 coldPost = vm.snapshotState();
        assertTrue(vm.revertToState(snap));
        vm.recordLogs();
        vm.startStateDiffRecording();
        (, bytes memory replay) = this.minerloopMeasured(target, sender, data, cap);
        VmSafe.AccountAccess[] memory acc = vm.stopAndReturnStateDiff();
        assertEq(_tableTranscript(vm.getRecordedLogs()), transcript,
            "cold measurement and replay must commit identical ordered table outcomes");
        assertEq(replay, result, "recorded replay must preserve returned progress");
        uint256 count;
        for (uint256 i; i < acc.length; ++i) {
            if (acc[i].account == address(vm)) continue;
            if (acc[i].account == address(this) && acc[i].kind != VmSafe.AccountAccessKind.Resume) continue;
            assertFalse(acc[i].reverted, "repricing assumes successful frames");
            acc[count++] = acc[i];
        }
        assembly ("memory-safe") { mstore(acc, count) }
        r = GlamsterdamReprice.reprice(used, acc, target);
        bytes32 replayState = _poststate(acc);
        assertTrue(vm.revertToState(coldPost));
        assertEq(_poststate(acc), replayState, "cold and recorded replay: all touched storage agrees");
        vm.deleteStateSnapshot(coldPost);
        vm.deleteStateSnapshot(snap);
    }

    function _report(string memory label, GlamsterdamReprice.Result memory r, uint256 bound) internal {
        emit log_named_string("unit", label);
        emit log_named_uint("osaka_exec", r.osakaExec);
        emit log_named_uint("glamsterdam_exec", r.glamsterdamExec);
        emit log_named_uint("glamsterdam_state", r.stateGas);
        emit log_named_uint("glamsterdam_total", r.glamsterdamExec + r.stateGas);
        emit log_named_uint("first_changes", r.firstChanges);
        emit log_named_uint("cold_accounts", r.coldAccounts);
        emit log_named_uint("bound", bound);
        emit log_named_int("margin", int256(bound) - int256(r.glamsterdamExec + r.stateGas));
    }
}
