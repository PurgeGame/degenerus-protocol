// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {Vm} from "forge-std/Vm.sol";

/// @dev Opt-in export of an independently seeded local prestate for read-only native RPC replay.
///      Include every accessed slot and codec-specific sibling slots for translated baselines.
abstract contract NativeGasExport is Test {
    function _nativeExtraStorage(string memory, address) internal virtual {}

    function _nativeFixture(string memory label, address sender, address target, bytes memory input) internal {
        string memory dir = vm.envOr("STORAGE_REUSE_EXPORT", string(""));
        uint256 snapshot = vm.snapshotState();
        vm.startStateDiffRecording();
        vm.recordLogs();
        vm.prank(sender);
        (bool ok, bytes memory output) = target.call(input);
        VmSafe.AccountAccess[] memory accesses = vm.stopAndReturnStateDiff();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        if (!ok) assembly ("memory-safe") { revert(add(output, 32), mload(output)) }
        assertTrue(vm.revertToState(snapshot));
        if (bytes(dir).length != 0) {
            address[] memory accounts = new address[](accesses.length + 2);
            accounts[0] = sender;
            accounts[1] = target;
            for (uint256 i; i < accesses.length; ++i) accounts[i + 2] = accesses[i].account;
            vm.serializeAddress(label, "accounts", accounts);
            vm.serializeAddress(label, "from", sender);
            vm.serializeAddress(label, "to", target);
            vm.serializeBytes(label, "input", input);
            vm.serializeBytes(label, "expectedReturn", output);
            vm.serializeUint(label, "baseFee", block.basefee);
            string memory logsJson = "[";
            for (uint256 i; i < logs.length; ++i) {
                string memory logKey = string.concat(label, "-log-", vm.toString(i));
                vm.serializeAddress(logKey, "address", logs[i].emitter);
                vm.serializeBytes(logKey, "data", logs[i].data);
                string memory entry = vm.serializeBytes32(logKey, "topics", logs[i].topics);
                logsJson = string.concat(logsJson, i == 0 ? "" : ",", entry);
            }
            vm.serializeString(label, "expectedLogs", string.concat(logsJson, "]"));
            string memory json = vm.serializeUint(label, "timestamp", block.timestamp);
            vm.writeJson(json, string.concat(dir, "/", label, ".call.json"));
            string memory state = "{";
            for (uint256 i; i < accounts.length; ++i) {
                address account = accounts[i];
                bool seen;
                for (uint256 j; j < i; ++j) if (accounts[j] == account) { seen = true; break; }
                if (seen) continue;
                string memory key = string.concat(label, vm.toString(account), "-storage");
                vm.serializeJson(key, "{}");
                for (uint256 j; j < accesses.length; ++j) {
                    VmSafe.StorageAccess[] memory slots = accesses[j].storageAccesses;
                    for (uint256 k; k < slots.length; ++k) if (slots[k].account == account) {
                        vm.serializeBytes32(key, vm.toString(slots[k].slot), vm.load(account, slots[k].slot));
                    }
                }
                _nativeExtraStorage(key, account);
                string memory storageJson = vm.serializeBytes32(key, vm.toString(bytes32(uint256(0))), vm.load(account, 0));
                if (bytes(state).length > 1) state = string.concat(state, ",");
                state = string.concat(state, '"', vm.toString(account), '":{"code":"', vm.toString(account.code),
                    '","balance":"', vm.toString(bytes32(account.balance)), '","nonce":', vm.toString(vm.getNonce(account)),
                    ',"storage":', storageJson, '}');
            }
            vm.writeJson(string.concat(state, "}"), string.concat(dir, "/", label, ".state.json"));
        }
    }
}
