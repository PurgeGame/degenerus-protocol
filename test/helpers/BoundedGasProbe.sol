// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Test} from "forge-std/Test.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {GlamsterdamReprice} from "./GlamsterdamReprice.sol";

/// @dev One measurement per test. Cold execution precedes state-diff recording;
///      the warmed replay must reproduce its exact cold-access surcharge.
abstract contract BoundedGasProbe is Test {
    function boundedMeasured(address target, address sender, uint256 value, bytes calldata data) external returns (uint256 gasUsed, int64 refund)
    {
        require(msg.sender == address(this), "measurement self-call");
        vm.prank(sender);
        (bool ok, bytes memory reason) = target.call{value: value}(data);
        VmSafe.Gas memory gas = vm.lastCallGas();
        gasUsed = gas.gasTotalUsed;
        refund = gas.gasRefunded;
        if (!ok) assembly ("memory-safe") { revert(add(reason, 32), mload(reason)) }
    }

    function _measureBounded(string memory label, address target, address sender, uint256 value, bytes memory data, bool warm) internal {
        // Measure cold first: this Forge version retains recorder state across
        // isolated transactions after a recorded replay. The fully warm replay is
        // valid and independently cross-checks this initial uninstrumented call.
        uint256 snapshot = vm.snapshotState();
        (uint256 coldGas, int64 coldRefund) = this.boundedMeasured(target, sender, value, data);
        assertTrue(vm.revertToState(snapshot));
        snapshot = vm.snapshotState();
        vm.startStateDiffRecording();
        this.boundedMeasured(target, sender, value, data);
        VmSafe.AccountAccess[] memory accesses = vm.stopAndReturnStateDiff();
        assertTrue(vm.revertToState(snapshot));
        {
            uint256 n = accesses.length;
            for (uint256 i; i < accesses.length; ++i) n += accesses[i].storageAccesses.length;
            VmSafe.AccessListItem[] memory list = new VmSafe.AccessListItem[](n);
            uint256 next;
            for (uint256 i; i < accesses.length; ++i) {
                list[next++] = VmSafe.AccessListItem(accesses[i].account, new bytes32[](0));
                for (uint256 j; j < accesses[i].storageAccesses.length; ++j) {
                    VmSafe.StorageAccess memory a = accesses[i].storageAccesses[j];
                    bytes32[] memory keys = new bytes32[](1);
                    keys[0] = a.slot;
                    list[next++] = VmSafe.AccessListItem(a.account, keys);
                }
            }
            vm.accessList(list);
        }
        (uint256 warmGas, int64 warmRefund) = this.boundedMeasured(target, sender, value, data);
        vm.noAccessList();
        VmSafe.AccountAccess[] memory acc = accesses;
        uint256 count;
        for (uint256 i; i < acc.length; ++i) {
            // Forge can attach a resumed callee's storage accesses to a wrapper
            // Resume record after a mocked nested call. Each storage access has
            // its own authoritative account; retain these records.
            if (acc[i].account == address(vm)) continue;
            if (acc[i].account == address(this) && acc[i].kind != VmSafe.AccountAccessKind.Resume) continue;
            acc[count++] = acc[i];
        }
        assembly ("memory-safe") { mstore(acc, count) }
        (uint256 surcharge, uint256 coldAccounts, uint256 firstWrites) = _surcharge(acc, sender, target);
        emit log_named_uint("cold_frame_crosscheck", coldGas);
        emit log_named_uint("warm_frame_crosscheck", warmGas);
        emit log_named_uint("cold_surcharge", surcharge);
        assertEq(coldGas, warmGas + surcharge, "benchmark cold/warm cross-check");
        assertTrue(vm.revertToState(snapshot));
        vm.startDebugTraceRecording();
        this.boundedMeasured(target, sender, value, data);
        VmSafe.DebugStep[] memory steps = vm.stopAndReturnDebugTraceRecording();
        uint256 extcodes;
        for (uint256 i; i < steps.length; ++i) {
            if (steps[i].contractAddr != address(this) &&
                (steps[i].opcode == 0x3b || steps[i].opcode == 0x3c)) ++extcodes;
        }
        uint256 valueCalls;
        uint256 newAccounts;
        for (uint256 i = 1; i < acc.length; ++i) {
            if (acc[i].kind == VmSafe.AccountAccessKind.Call && acc[i].value != 0) {
                ++valueCalls;
                if (!acc[i].initialized) ++newAccounts;
            }
        }
        uint256 used = warm ? warmGas : coldGas;
        int64 refund = warm ? warmRefund : coldRefund;
        GlamsterdamReprice.Result memory g = GlamsterdamReprice.reprice(used, acc, target);
        uint256 projectedExec = uint256(int256(used) + g.execDelta - int256(g.coldAccounts * 400))
            + (warm ? 0 : coldAccounts * 400) + extcodes * 100 + valueCalls * 2300
            - (warm ? 0 : firstWrites * 100) - newAccounts * 25_000;
        uint256 projectedState = g.stateGas + newAccounts * 183600;
        emit log_named_string("bounded_case", label);
        emit log_named_uint("osaka_frame_gross", used);
        emit log_named_int("refund_counter", refund);
        emit log_named_uint("projected_glamsterdam_exec", projectedExec);
        emit log_named_uint("projected_glamsterdam_state", projectedState);
        emit log_named_uint("projected_glamsterdam_total", projectedExec + projectedState);
        emit log_named_uint("value_calls", valueCalls);
        emit log_named_uint("extcode_operations", extcodes);
        emit log_named_uint("first_write_cold_slots", firstWrites);
        emit log_named_uint("cold_accounts", coldAccounts);
        emit log_named_uint("new_accounts", newAccounts);
        emit log_named_uint("new_slots", g.newSlots);
        emit log_named_uint("sstores", g.sstores);
    }

    function _surcharge(VmSafe.AccountAccess[] memory acc, address sender, address target) private view returns (uint256 charge, uint256 accountCount, uint256 firstWrites) {
        address[] memory accounts = new address[](acc.length);
        address[] memory slotAccounts = new address[](4096);
        bytes32[] memory slots = new bytes32[](4096);
        uint256 na;
        uint256 ns;
        for (uint256 i; i < acc.length; ++i) {
            address account = acc[i].account;
            if (acc[i].kind != VmSafe.AccountAccessKind.Resume && account != sender
                && account != target && uint160(account) > 0x100) {
                bool seen;
                for (uint256 j; j < na; ++j) if (accounts[j] == account) seen = true;
                if (!seen) { accounts[na++] = account; charge += 2500; ++accountCount; }
            }
            for (uint256 j; j < acc[i].storageAccesses.length; ++j) {
                VmSafe.StorageAccess memory a = acc[i].storageAccesses[j];
                bool seen;
                for (uint256 k; k < ns; ++k) if (slotAccounts[k] == a.account && slots[k] == a.slot) seen = true;
                if (seen) continue;
                require(ns < 4096, "surcharge capacity");
                slotAccounts[ns] = a.account; slots[ns++] = a.slot;
                charge += a.isWrite ? 2100 : 2000;
                if (a.isWrite) ++firstWrites;
            }
        }
    }

}
