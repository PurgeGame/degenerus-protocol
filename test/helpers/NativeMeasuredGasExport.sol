// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {NativeGasExport} from "./NativeGasExport.sol";
import {Vm} from "forge-std/Vm.sol";

/// @dev State-diff recording changes access warmth and therefore worker throughput.
/// Keep the independently measured cold call's return, logs and poststate as the
/// oracle; use the recording replay only to discover prestate accounts and slots.
abstract contract NativeMeasuredGasExport is NativeGasExport {
    /// @dev Caller restores its cold poststate in the same frame that took the
    /// snapshot before entering this serializer; Forge cannot restore it across
    /// an isolated self-call boundary.
    function finalizeMeasuredFixture(string calldata label, bytes calldata coldReturn, Vm.Log[] calldata coldLogs) external {
        require(msg.sender == address(this), "measured export self-call");
        string memory dir = vm.envString("STORAGE_REUSE_EXPORT");
        string memory callPath = string.concat(dir, "/", label, ".call.json");
        string memory state = vm.readFile(string.concat(dir, "/", label, ".state.json"));
        vm.serializeJson(label, vm.readFile(callPath));
        string[] memory accounts = vm.parseJsonKeys(state, ".");
        string memory expected = "{";
        for (uint256 i; i < accounts.length; ++i) {
            string memory slots = this.coldAccountStorage(label, state, accounts[i]);
            expected = string.concat(expected, i == 0 ? "" : ",", '"', accounts[i], '":', slots);
        }
        vm.serializeString(label, "expectedStorage", string.concat(expected, "}"));
        vm.serializeBytes(label, "expectedReturn", coldReturn);
        string memory entries = "[";
        for (uint256 i; i < coldLogs.length; ++i) {
            string memory key = string.concat(label, "-cold-log-", vm.toString(i));
            vm.serializeAddress(key, "address", coldLogs[i].emitter);
            vm.serializeBytes(key, "data", coldLogs[i].data);
            string memory entry = vm.serializeBytes32(key, "topics", coldLogs[i].topics);
            entries = string.concat(entries, i == 0 ? "" : ",", entry);
        }
        vm.serializeString(label, "expectedLogs", string.concat(entries, "]"));
        string memory json = vm.serializeString(label, "oracle", "cold call before state-diff recording");
        vm.writeJson(json, callPath);
    }

    /// @dev Complete local state dumps avoid recording altogether for repeated
    /// cold measurements. Both dumps are taken by the caller in its own frame.
    function writeDumpFixture(string calldata label, address sender, address target, bytes calldata input,
        bytes calldata coldReturn, Vm.Log[] calldata coldLogs) external
    {
        require(msg.sender == address(this), "dump metadata self-call");
        vm.serializeAddress(label, "from", sender);
        vm.serializeAddress(label, "to", target);
        vm.serializeBytes(label, "input", input);
        vm.serializeBytes(label, "expectedReturn", coldReturn);
        vm.serializeUint(label, "baseFee", block.basefee);
        vm.serializeUint(label, "number", block.number);
        vm.serializeUint(label, "timestamp", block.timestamp);
        vm.serializeBool(label, "completeStateDump", true);
        string memory entries = "[";
        for (uint256 i; i < coldLogs.length; ++i) {
            string memory key = string.concat(label, "-dump-log-", vm.toString(i));
            vm.serializeAddress(key, "address", coldLogs[i].emitter);
            vm.serializeBytes(key, "data", coldLogs[i].data);
            string memory entry = vm.serializeBytes32(key, "topics", coldLogs[i].topics);
            entries = string.concat(entries, i == 0 ? "" : ",", entry);
        }
        vm.serializeString(label, "expectedLogs", string.concat(entries, "]"));
        string memory json = vm.serializeString(label, "oracle", "cold call, complete vm.dumpState before and after, no state-diff recording");
        vm.writeJson(json, string.concat(vm.envString("STORAGE_REUSE_EXPORT"), "/", label, ".call.json"));
    }

    function coldAccountStorage(string calldata label, string calldata state, string calldata account)
        external returns (string memory)
    {
        require(msg.sender == address(this), "cold storage self-call");
        string[] memory slots = vm.parseJsonKeys(state, string.concat(".", account, ".storage"));
        string memory key = string.concat(label, "-cold-post-", account);
        vm.serializeJson(key, "{}");
        address target = vm.parseAddress(account);
        for (uint256 i; i < slots.length; ++i) {
            this.nativeSerializeSlot(key, target, vm.parseBytes32(slots[i]));
        }
        return vm.serializeBytes32(key, vm.toString(bytes32(0)), vm.load(target, 0));
    }
}
