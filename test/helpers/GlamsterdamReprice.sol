// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {VmSafe} from "forge-std/Vm.sol";

/// @notice Re-prices a measured Osaka call under the Glamsterdam schedule (EIP-8037 / EIP-8038)
///         from its recorded account and storage accesses. No local EVM implements Amsterdam, so
///         the schedule delta is applied to the measured gas:
///         - SSTORE first change of a slot in the transaction: 20,000 (0->x) / 2,900 (x->y)
///           becomes 10,000 plus the 100 warm access (cold access 2,100 is unchanged);
///         - cold account access 2,600 becomes 3,000;
///         - each new slot (original 0, nonzero at the end of the call) adds 97,920 state gas.
/// @dev Wrap the measured call in vm.startStateDiffRecording / vm.stopAndReturnStateDiff and
///      pass the accesses with `to`, the transaction's target (warm in a real transaction).
library GlamsterdamReprice {
    uint256 internal constant NEW_SLOT_STATE_GAS = 97_920;
    uint256 private constant MAX_SLOTS = 16_384;
    uint256 private constant MAX_ACCOUNTS = 128;

    struct Result {
        uint256 osakaExec;
        uint256 sstores;
        uint256 firstChanges;
        uint256 newSlots;
        uint256 coldAccounts;
        int256 execDelta;
        uint256 glamsterdamExec;
        uint256 stateGas;
    }

    function reprice(uint256 measured, VmSafe.AccountAccess[] memory acc, address to)
        internal
        pure
        returns (Result memory r)
    {
        address[] memory warm = new address[](MAX_ACCOUNTS);
        uint256 nAccts;
        warm[nAccts++] = to;
        address[] memory seenAccount = new address[](MAX_SLOTS);
        bytes32[] memory seenSlot = new bytes32[](MAX_SLOTS);
        bytes32[] memory original = new bytes32[](MAX_SLOTS);
        bytes32[] memory current = new bytes32[](MAX_SLOTS);
        // Committed value: writes inside reverted frames still pay execution gas but leave no state.
        bytes32[] memory committed = new bytes32[](MAX_SLOTS);
        uint256 nSeen;
        int256 delta;
        for (uint256 i; i < acc.length; ++i) {
            if (acc[i].kind != VmSafe.AccountAccessKind.Resume) {
                address a = acc[i].account;
                bool known;
                for (uint256 k; k < nAccts; ++k) {
                    if (warm[k] == a) {
                        known = true;
                        break;
                    }
                }
                // Precompiles are always warm.
                if (!known && uint160(a) > 0x100) {
                    require(nAccts < MAX_ACCOUNTS, "reprice: account table full");
                    warm[nAccts++] = a;
                    ++r.coldAccounts;
                    delta += 400;
                }
            }
            VmSafe.StorageAccess[] memory sa = acc[i].storageAccesses;
            for (uint256 j; j < sa.length; ++j) {
                uint256 idx = type(uint256).max;
                for (uint256 k = nSeen; k != 0; --k) {
                    if (seenSlot[k - 1] == sa[j].slot && seenAccount[k - 1] == sa[j].account) {
                        idx = k - 1;
                        break;
                    }
                }
                if (idx == type(uint256).max) {
                    require(nSeen < MAX_SLOTS, "reprice: slot table full");
                    idx = nSeen++;
                    seenAccount[idx] = sa[j].account;
                    seenSlot[idx] = sa[j].slot;
                    original[idx] = sa[j].previousValue;
                    current[idx] = sa[j].previousValue;
                    committed[idx] = sa[j].previousValue;
                }
                if (!sa[j].isWrite) continue;
                ++r.sstores;
                bytes32 cur = current[idx];
                bytes32 nv = sa[j].newValue;
                // Osaka folds the warm term into 20,000 / 2,900 on a first change and charges 100
                // otherwise; Amsterdam charges 100 + 10,000 on a first change and 100 otherwise.
                if (nv != cur && cur == original[idx]) {
                    ++r.firstChanges;
                    bool fresh = original[idx] == bytes32(0);
                    delta += int256(10_100) - (fresh ? int256(20_000) : int256(2_900));
                }
                current[idx] = nv;
                if (!sa[j].reverted) committed[idx] = nv;
            }
        }
        // A slot created and cleared again within the transaction refills its state gas.
        for (uint256 k; k < nSeen; ++k) {
            if (original[k] == bytes32(0) && committed[k] != bytes32(0)) ++r.newSlots;
        }
        r.osakaExec = measured;
        r.execDelta = delta;
        r.glamsterdamExec = uint256(int256(measured) + delta);
        r.stateGas = r.newSlots * NEW_SLOT_STATE_GAS;
    }
}
