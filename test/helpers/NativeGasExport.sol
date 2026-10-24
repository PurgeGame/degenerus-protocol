// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Test} from "forge-std/Test.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {Vm} from "forge-std/Vm.sol";

/// @dev Opt-in export of an independently seeded local prestate for read-only native RPC replay.
///      Include every accessed slot and codec-specific sibling slots for translated baselines.
abstract contract NativeGasExport is Test {
    /// @dev The serializer returns its entire growing JSON object. Keep that temporary
    /// allocation in a separate frame so large heap fixtures do not accumulate it.
    function nativeSerializeSlot(string calldata key, address account, bytes32 slot) external {
        require(msg.sender == address(this), "serializer self-call");
        vm.serializeBytes32(key, vm.toString(slot), vm.load(account, slot));
    }

    /// @dev Keep export allocations out of subsequent measurements in the caller.
    function exportNativeFixture(string calldata label, address sender, address target, bytes calldata input) external {
        require(msg.sender == address(this), "export self-call");
        _nativeFixture(label, sender, target, input);
    }

    function exportNativeFixture(string calldata label, address sender, address target, uint256 value, bytes calldata input) external {
        require(msg.sender == address(this), "export self-call");
        _nativeFixture(label, sender, target, value, input);
    }

    function nativeExpectedStorage(string calldata label, VmSafe.AccountAccess[] calldata accesses)
        external returns (string memory state)
    {
        require(msg.sender == address(this), "poststate self-call");
        state = "{";
        for (uint256 i; i < accesses.length; ++i) {
            address account = accesses[i].account;
            bool seen;
            for (uint256 j; j < i; ++j) if (accesses[j].account == account) { seen = true; break; }
            if (seen) continue;
            string memory key = string.concat(label, "-post-", vm.toString(account));
            vm.serializeJson(key, "{}");
            bool written;
            for (uint256 j; j < accesses.length; ++j) {
                for (uint256 k; k < accesses[j].storageAccesses.length; ++k) {
                    VmSafe.StorageAccess calldata slot = accesses[j].storageAccesses[k];
                    if (slot.account == account && slot.isWrite && !slot.reverted) {
                        this.nativeSerializeSlot(key, account, slot.slot);
                        written = true;
                    }
                }
            }
            if (!written) continue;
            string memory slots = vm.serializeBytes32(key, vm.toString(bytes32(0)), vm.load(account, 0));
            state = string.concat(state, bytes(state).length == 1 ? "" : ",", '"', vm.toString(account), '":', slots);
        }
        return string.concat(state, "}");
    }

    /// @dev A native profile may touch additional checkpoint slots. A replay
    /// discovery manifest supplies only their addresses/keys; their actual values
    /// are always read here from the original Foundry prestate, never guessed.
    function nativeReplayCoverage(string calldata key, address account, string calldata dir) external {
        require(msg.sender == address(this), "coverage self-call");
        string memory path = string.concat(dir, "/replay-extra-slots.json");
        if (!vm.exists(path)) return;
        string memory json = vm.readFile(path);
        address[] memory accounts = vm.parseJsonAddressArray(json, ".accounts");
        bytes32[] memory slots = vm.parseJsonBytes32Array(json, ".slots");
        require(accounts.length == slots.length, "coverage manifest shape");
        for (uint256 i; i < slots.length; ++i) {
            if (accounts[i] == account) this.nativeSerializeSlot(key, account, slots[i]);
        }
    }

    function _nativeExtraStorage(string memory, address) internal virtual {}

    function nativeWriteState(string calldata label, string calldata dir, address[] calldata accounts,
        VmSafe.AccountAccess[] calldata accesses) external
    {
        require(msg.sender == address(this), "state writer self-call");
        string memory statePath = string.concat(dir, "/", label, ".state.json");
        vm.writeFile(statePath, "{\n");
        bool comma;
        for (uint256 i; i < accounts.length; ++i) {
            address account = accounts[i];
            bool seen;
            for (uint256 j; j < i; ++j) if (accounts[j] == account) { seen = true; break; }
            if (seen) continue;
            this.nativeWriteAccount(label, dir, account, accesses, comma);
            comma = true;
        }
        vm.writeLine(statePath, "}");
    }

    /// @dev Stream one account in a fresh frame. Fixture runtimes can contain all
    /// deployment creation code; repeatedly concatenating them into a growing
    /// in-memory document makes export itself exhaust the test's memory budget.
    function nativeWriteAccount(string calldata label, string calldata dir, address account,
        VmSafe.AccountAccess[] calldata accesses, bool comma) external
    {
        require(msg.sender == address(this), "account writer self-call");
        string memory key = string.concat(label, vm.toString(account), "-storage");
        vm.serializeJson(key, "{}");
        for (uint256 j; j < accesses.length; ++j) {
            for (uint256 k; k < accesses[j].storageAccesses.length; ++k) {
                VmSafe.StorageAccess calldata slot = accesses[j].storageAccesses[k];
                if (slot.account == account) this.nativeSerializeSlot(key, account, slot.slot);
            }
        }
        this.nativeReplayCoverage(key, account, dir);
        _nativeExtraStorage(key, account);
        string memory storageJson = vm.serializeBytes32(key, vm.toString(bytes32(0)), vm.load(account, 0));
        vm.writeLine(string.concat(dir, "/", label, ".state.json"), string.concat(
            comma ? "," : "", '"', vm.toString(account), '":{"code":"', vm.toString(account.code),
            '","balance":"', vm.toString(bytes32(account.balance)), '","nonce":', vm.toString(vm.getNonce(account)),
            ',"storage":', storageJson, '}'));
    }

    function _nativeFixture(string memory label, address sender, address target, bytes memory input) internal {
        _nativeFixture(label, sender, target, 0, input);
    }

    struct NativeFixtureData {
        string label;
        string dir;
        address sender;
        address target;
        uint256 value;
        bytes input;
        bytes output;
        string expectedStorage;
        VmSafe.AccountAccess[] accesses;
        Vm.Log[] logs;
    }

    function _nativeFixture(string memory label, address sender, address target, uint256 value, bytes memory input) internal {
        NativeFixtureData memory work;
        work.label = label;
        work.dir = vm.envOr("STORAGE_REUSE_EXPORT", string(""));
        work.sender = sender;
        work.target = target;
        work.value = value;
        work.input = input;
        uint256 snapshot = vm.snapshotState();
        vm.startStateDiffRecording();
        vm.recordLogs();
        vm.prank(sender);
        (bool ok, bytes memory output) = target.call{value: value}(input);
        work.output = output;
        work.accesses = vm.stopAndReturnStateDiff();
        work.logs = vm.getRecordedLogs();
        if (!ok) assembly ("memory-safe") { revert(add(output, 32), mload(output)) }
        if (bytes(work.dir).length != 0) work.expectedStorage = this.nativeExpectedStorage(label, work.accesses);
        assertTrue(vm.revertToStateAndDelete(snapshot));
        if (bytes(work.dir).length != 0) this.nativeWriteFixture(work);
    }

    function nativeWriteFixture(NativeFixtureData calldata work) external {
        require(msg.sender == address(this), "fixture writer self-call");
        address[] memory accounts = new address[](work.accesses.length + 2);
        accounts[0] = work.sender;
        accounts[1] = work.target;
        for (uint256 i; i < work.accesses.length; ++i) accounts[i + 2] = work.accesses[i].account;
        vm.serializeAddress(work.label, "accounts", accounts);
        vm.serializeAddress(work.label, "from", work.sender);
        vm.serializeAddress(work.label, "to", work.target);
        vm.serializeBytes(work.label, "input", work.input);
        vm.serializeUint(work.label, "value", work.value);
        vm.serializeBytes(work.label, "expectedReturn", work.output);
        vm.serializeString(work.label, "expectedStorage", work.expectedStorage);
        vm.serializeUint(work.label, "baseFee", block.basefee);
        vm.serializeUint(work.label, "number", block.number);
        string memory logsJson = "[";
        for (uint256 i; i < work.logs.length; ++i) {
            string memory logKey = string.concat(work.label, "-log-", vm.toString(i));
            vm.serializeAddress(logKey, "address", work.logs[i].emitter);
            vm.serializeBytes(logKey, "data", work.logs[i].data);
            string memory entry = vm.serializeBytes32(logKey, "topics", work.logs[i].topics);
            logsJson = string.concat(logsJson, i == 0 ? "" : ",", entry);
        }
        vm.serializeString(work.label, "expectedLogs", string.concat(logsJson, "]"));
        string memory json = vm.serializeUint(work.label, "timestamp", block.timestamp);
        vm.writeJson(json, string.concat(work.dir, "/", work.label, ".call.json"));
        this.nativeWriteState(work.label, work.dir, accounts, work.accesses);
    }
}
