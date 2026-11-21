// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {VmSafe} from "forge-std/Vm.sol";

/// @notice Osaka cold-access gas a fresh transaction pays over a fully warm replay of the same call.
/// @dev A state-diff-recorded call is priced warm and leaves every account and slot it touches warm
///      for the rest of the test (snapshot reverts, isolation and vm.cool do not re-cool them), so
///      a cold figure is a replay after the recorded run plus this premium: 2,500 per account
///      other than the target and precompiles, 2,000 per slot whose first access is a read and
///      2,100 per slot whose first access is a write.
library ColdAccessPremium {
    uint256 internal constant ACCOUNT = 2_500;
    uint256 internal constant SLOAD = 2_000;
    uint256 internal constant SSTORE = 2_100;

    function premium(VmSafe.AccountAccess[] memory acc, address to)
        internal
        pure
        returns (uint256 total, uint256 accounts, uint256 slots)
    {
        address[] memory seen = new address[](acc.length + 1);
        seen[0] = to;
        uint256 nSeen = 1;
        uint256 nAccess;
        for (uint256 i; i < acc.length; ++i) nAccess += acc[i].storageAccesses.length;
        address[] memory slotAccount = new address[](nAccess);
        bytes32[] memory slotKey = new bytes32[](nAccess);
        for (uint256 i; i < acc.length; ++i) {
            if (acc[i].kind != VmSafe.AccountAccessKind.Resume && uint160(acc[i].account) > 0x100
                && !_has(seen, nSeen, acc[i].account)) {
                seen[nSeen++] = acc[i].account;
                ++accounts;
            }
            VmSafe.StorageAccess[] memory sa = acc[i].storageAccesses;
            for (uint256 j; j < sa.length; ++j) {
                bool known;
                for (uint256 k = slots; k != 0; --k) {
                    if (slotKey[k - 1] == sa[j].slot && slotAccount[k - 1] == sa[j].account) {
                        known = true;
                        break;
                    }
                }
                if (known) continue;
                (slotAccount[slots], slotKey[slots]) = (sa[j].account, sa[j].slot);
                ++slots;
                total += sa[j].isWrite ? SSTORE : SLOAD;
            }
        }
        total += accounts * ACCOUNT;
    }

    function _has(address[] memory list, uint256 n, address a) private pure returns (bool) {
        for (uint256 k; k < n; ++k) if (list[k] == a) return true;
        return false;
    }
}
