// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {VmSafe} from "forge-std/Vm.sol";

/// @notice Re-prices a measured Osaka call under the Glamsterdam schedule (EIP-8037 / EIP-8038)
///         from its recorded account and storage accesses, for a transaction without a state-gas
///         reservoir (every state charge is taken from gas_left, which `gasleft()` reads):
///         - SSTORE first change of a slot in the transaction: 20,000 (0->x) / 2,900 (x->y)
///           becomes 10,000 plus the 100 warm access (cold access 2,100 is unchanged). A slot
///           whose first access is the write is cold, where Amsterdam charges 2,100 + 10,000;
///           the model keeps the extra 100 (conservative, it cannot see warmth from earlier
///           frames of the same transaction);
///         - cold account access 2,600 becomes 3,000;
///         - a value-bearing CALL inside the call costs 11,300 instead of 9,000;
///         - EXTCODESIZE / EXTCODECOPY inside the call add one warm access (100);
///         - a value CALL to a dead account drops the 25,000 execution charge for 183,600 state gas;
///         - each new slot (zero at the start of the call, then nonzero) adds 97,920 state gas,
///           refilled when it is cleared again.
///         `stateGas` is the peak state gas held during the call: a slot created and cleared again
///         inside the call draws 97,920 from gas_left until the clear refills it. `finalStateGas`
///         is what stays charged at the end. Admission compares `glamsterdamExec + stateGas`.
/// @dev Wrap the measured call in vm.startStateDiffRecording / vm.stopAndReturnStateDiff and
///      pass the accesses with `to`, the transaction's target (warm in a real transaction).
///      Calls at the shallowest recorded call depth are the measured frames themselves; their
///      own CALL cost and any code-size check before them are outside the measured gas.
library GlamsterdamReprice {
    uint256 internal constant NEW_SLOT_STATE_GAS = 97_920;
    uint256 internal constant NEW_ACCOUNT_STATE_GAS = 183_600;
    uint256 internal constant VALUE_CALL_DELTA = 2_300;
    uint256 internal constant CODE_READ_DELTA = 100;
    uint256 internal constant OSAKA_NEW_ACCOUNT_GAS = 25_000;
    uint256 private constant MAX_SLOTS = 16_384;
    address private constant VM = address(uint160(uint256(keccak256("hevm cheat code"))));
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
        uint256 valueCalls;
        uint256 newAccounts;
        uint256 codeReads;
        uint256 finalStateGas;
    }

    struct Slots {
        address[] account;
        bytes32[] slot;
        bytes32[] original;
        bytes32[] current;
        // Committed value: writes inside reverted frames still pay execution gas but leave no state.
        bytes32[] committed;
        bool[] pending;
        uint256[] pendingIdx;
        uint256 n;
        uint256 nPending;
    }

    function reprice(uint256 measured, VmSafe.AccountAccess[] memory acc, address to)
        internal
        pure
        returns (Result memory r)
    {
        uint64 topDepth = type(uint64).max;
        for (uint256 i; i < acc.length; ++i) {
            if (_isCall(acc[i].kind) && acc[i].depth < topDepth) topDepth = acc[i].depth;
        }
        address[] memory warm = new address[](MAX_ACCOUNTS);
        uint256 nAccts;
        warm[nAccts++] = to;
        Slots memory s = Slots(
            new address[](MAX_SLOTS), new bytes32[](MAX_SLOTS), new bytes32[](MAX_SLOTS),
            new bytes32[](MAX_SLOTS), new bytes32[](MAX_SLOTS), new bool[](MAX_SLOTS),
            new uint256[](MAX_SLOTS), 0, 0
        );
        int256 delta;
        uint256 held;
        uint256 heldAccounts;
        uint256 pendingAccounts;
        for (uint256 i; i < acc.length; ++i) {
            VmSafe.AccountAccessKind kind = acc[i].kind;
            // A committed record after records of a reverted frame means that frame has ended:
            // its slots are back at their committed values and its state gas is refilled.
            if (!acc[i].reverted) {
                held = _rollBack(s, held) - pendingAccounts;
                pendingAccounts = 0;
            }
            if (kind != VmSafe.AccountAccessKind.Resume) {
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
            if (acc[i].depth > topDepth) {
                if (kind == VmSafe.AccountAccessKind.Call && acc[i].value != 0) {
                    ++r.valueCalls;
                    delta += int256(VALUE_CALL_DELTA);
                    if (!acc[i].initialized) {
                        ++r.newAccounts;
                        delta -= int256(OSAKA_NEW_ACCOUNT_GAS);
                        // Charged before the child frame; a reverted child refills it.
                        held += NEW_ACCOUNT_STATE_GAS;
                        if (acc[i].reverted) pendingAccounts += NEW_ACCOUNT_STATE_GAS;
                        else heldAccounts += NEW_ACCOUNT_STATE_GAS;
                        if (held > r.stateGas) r.stateGas = held;
                    }
                } else if (
                    kind == VmSafe.AccountAccessKind.Extcodesize || kind == VmSafe.AccountAccessKind.Extcodecopy
                ) {
                    ++r.codeReads;
                    delta += int256(CODE_READ_DELTA);
                }
            }
            VmSafe.StorageAccess[] memory sa = acc[i].storageAccesses;
            for (uint256 j; j < sa.length; ++j) {
                uint256 idx = _slot(s, sa[j]);
                if (s.pending[idx] && !sa[j].reverted) held = _restore(s, idx, held);
                if (!sa[j].isWrite) continue;
                ++r.sstores;
                bytes32 cur = s.current[idx];
                bytes32 nv = sa[j].newValue;
                // Osaka folds the warm term into 20,000 / 2,900 on a first change and charges 100
                // otherwise; Amsterdam charges 100 + 10,000 on a first change and 100 otherwise.
                if (nv != cur && cur == s.original[idx]) {
                    ++r.firstChanges;
                    bool fresh = s.original[idx] == bytes32(0);
                    delta += int256(10_100) - (fresh ? int256(20_000) : int256(2_900));
                }
                held = held - _charge(s.original[idx], cur) + _charge(s.original[idx], nv);
                if (held > r.stateGas) r.stateGas = held;
                s.current[idx] = nv;
                if (!sa[j].reverted) {
                    s.committed[idx] = nv;
                    s.pending[idx] = false;
                } else if (!s.pending[idx]) {
                    require(s.nPending < MAX_SLOTS, "reprice: pending table full");
                    s.pending[idx] = true;
                    s.pendingIdx[s.nPending++] = idx;
                }
            }
        }
        // A slot created and cleared again within the call refills its state gas.
        for (uint256 k; k < s.n; ++k) {
            if (s.original[k] == bytes32(0) && s.committed[k] != bytes32(0)) ++r.newSlots;
        }
        r.osakaExec = measured;
        r.execDelta = delta;
        r.glamsterdamExec = uint256(int256(measured) + delta);
        r.finalStateGas = r.newSlots * NEW_SLOT_STATE_GAS + heldAccounts;
        if (r.finalStateGas > r.stateGas) r.stateGas = r.finalStateGas;
    }

    /// @notice Osaka cold-equivalent gas of a recorded replay. This Foundry build warms each account
    ///         and slot before its first recorded access and keeps doing so for the rest of the
    ///         test, so a recorded replay, and any later "cold" call in the same test, reads warm.
    ///         Adds back 2,500 per existing account other than `target`, `skip` and precompiles
    ///         (an account that does not exist yet is not pre-warmed, so the replay already paid its
    ///         cold access), 2,000 per slot first read and 2,100 per slot first written (slots of
    ///         `skip` excluded).
    /// @dev Pass `skip` = the test contract, whose own accesses sit outside the measured frame.
    ///      A probe takes max(measured cold, this): exact for a test's first recording, and the
    ///      corrected figure for every later one.
    function coldEquivalent(uint256 replayGas, VmSafe.AccountAccess[] memory acc, address target, address skip)
        internal
        pure
        returns (uint256 gas)
    {
        gas = replayGas;
        address[] memory accounts = new address[](MAX_ACCOUNTS);
        uint256 na;
        address[] memory slotAccounts = new address[](MAX_SLOTS);
        bytes32[] memory slots = new bytes32[](MAX_SLOTS);
        uint256 ns;
        for (uint256 i; i < acc.length; ++i) {
            address a = acc[i].account;
            if (acc[i].kind != VmSafe.AccountAccessKind.Resume && a != target && a != skip && a != VM
                && uint160(a) > 0x100) {
                bool seen;
                for (uint256 k; k < na; ++k) {
                    if (accounts[k] == a) {
                        seen = true;
                        break;
                    }
                }
                if (!seen) {
                    require(na < MAX_ACCOUNTS, "coldEquivalent: account table full");
                    accounts[na++] = a;
                    if (acc[i].initialized) gas += 2_500;
                }
            }
            VmSafe.StorageAccess[] memory sa = acc[i].storageAccesses;
            for (uint256 j; j < sa.length; ++j) {
                if (sa[j].account == skip) continue;
                bool seen;
                for (uint256 k = ns; k != 0; --k) {
                    if (slots[k - 1] == sa[j].slot && slotAccounts[k - 1] == sa[j].account) {
                        seen = true;
                        break;
                    }
                }
                if (seen) continue;
                require(ns < MAX_SLOTS, "coldEquivalent: slot table full");
                slotAccounts[ns] = sa[j].account;
                slots[ns++] = sa[j].slot;
                gas += sa[j].isWrite ? 2_100 : 2_000;
            }
        }
    }

    function _isCall(VmSafe.AccountAccessKind kind) private pure returns (bool) {
        return kind == VmSafe.AccountAccessKind.Call || kind == VmSafe.AccountAccessKind.DelegateCall
            || kind == VmSafe.AccountAccessKind.CallCode || kind == VmSafe.AccountAccessKind.StaticCall
            || kind == VmSafe.AccountAccessKind.Create;
    }

    function _rollBack(Slots memory s, uint256 held) private pure returns (uint256) {
        for (uint256 k; k < s.nPending; ++k) {
            uint256 idx = s.pendingIdx[k];
            if (s.pending[idx]) held = _restore(s, idx, held);
        }
        s.nPending = 0;
        return held;
    }

    function _restore(Slots memory s, uint256 idx, uint256 held) private pure returns (uint256) {
        held = held - _charge(s.original[idx], s.current[idx]) + _charge(s.original[idx], s.committed[idx]);
        s.current[idx] = s.committed[idx];
        s.pending[idx] = false;
        return held;
    }

    function _charge(bytes32 original, bytes32 value) private pure returns (uint256) {
        return original == bytes32(0) && value != bytes32(0) ? NEW_SLOT_STATE_GAS : 0;
    }

    function _slot(Slots memory s, VmSafe.StorageAccess memory a) private pure returns (uint256 idx) {
        for (uint256 k = s.n; k != 0; --k) {
            if (s.slot[k - 1] == a.slot && s.account[k - 1] == a.account) return k - 1;
        }
        require(s.n < MAX_SLOTS, "reprice: slot table full");
        idx = s.n++;
        s.account[idx] = a.account;
        s.slot[idx] = a.slot;
        s.original[idx] = a.previousValue;
        s.current[idx] = a.previousValue;
        s.committed[idx] = a.previousValue;
    }
}
