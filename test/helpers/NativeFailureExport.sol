// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {NativeGasExport} from "./NativeGasExport.sol";
import {VmSafe} from "forge-std/Vm.sol";

/// @dev Test-only finite gas boundary; production failure policies run unchanged.
contract NativeFailureProbe {
    function invoke(address target, bytes calldata input, uint256 budget) external returns (bool ok, bytes4 reason) {
        bytes memory output;
        (ok, output) = target.call{gas: budget}(input);
        if (!ok && output.length >= 4) assembly ("memory-safe") { reason := mload(add(output, 32)) }
    }
}

abstract contract NativeFailureExport is NativeGasExport {
    function _nativeCheckedFixture(string memory label, address sender, address target, bytes memory input) internal {
        _nativeFixture(label, sender, target, input);
        string memory dir = vm.envOr("STORAGE_REUSE_EXPORT", string(""));
        if (bytes(dir).length == 0) return;
        uint256 snapshot = vm.snapshotState();
        vm.startStateDiffRecording();
        vm.prank(sender);
        (bool ok,) = target.call(input);
        require(ok);
        VmSafe.AccountAccess[] memory accesses = vm.stopAndReturnStateDiff();
        string memory state = "{";
        for (uint256 i; i < accesses.length; ++i) {
            address account = accesses[i].account;
            bool seen;
            for (uint256 j; j < i; ++j) if (accesses[j].account == account) { seen = true; break; }
            if (seen) continue;
            string memory key = string.concat(label, "-post-", vm.toString(account));
            vm.serializeJson(key, "{}");
            for (uint256 j; j < accesses.length; ++j) {
                VmSafe.StorageAccess[] memory slots = accesses[j].storageAccesses;
                for (uint256 k; k < slots.length; ++k) if (slots[k].account == account) {
                    vm.serializeBytes32(key, vm.toString(slots[k].slot), vm.load(account, slots[k].slot));
                }
            }
            string memory storageJson = vm.serializeBytes32(key, vm.toString(bytes32(0)), vm.load(account, 0));
            if (bytes(state).length > 1) state = string.concat(state, ",");
            state = string.concat(state, '"', vm.toString(account), '":', storageJson);
        }
        vm.writeJson(string.concat(state, "}"), string.concat(dir, "/", label, ".post.json"));
        require(vm.revertToState(snapshot));
        vm.deleteStateSnapshot(snapshot);
    }
}
