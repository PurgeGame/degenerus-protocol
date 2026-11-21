// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {VmSafe} from "forge-std/Vm.sol";

/// @notice The slots a recorded call creates: zero at their first access and nonzero when the
///         call ends. Writes inside reverted frames leave no state and are not counted.
library NewSlotCensus {
    uint256 private constant MAX_SLOTS = 16_384;

    struct Census {
        address[] account;
        uint256 n;
    }

    function created(VmSafe.AccountAccess[] memory acc) internal pure returns (Census memory c) {
        address[] memory account = new address[](MAX_SLOTS);
        bytes32[] memory slot = new bytes32[](MAX_SLOTS);
        bytes32[] memory original = new bytes32[](MAX_SLOTS);
        bytes32[] memory committed = new bytes32[](MAX_SLOTS);
        uint256 n;
        for (uint256 i; i < acc.length; ++i) {
            VmSafe.StorageAccess[] memory sa = acc[i].storageAccesses;
            for (uint256 j; j < sa.length; ++j) {
                uint256 idx = n;
                for (uint256 k = n; k != 0; --k) {
                    if (slot[k - 1] == sa[j].slot && account[k - 1] == sa[j].account) {
                        idx = k - 1;
                        break;
                    }
                }
                if (idx == n) {
                    require(n < MAX_SLOTS, "census: slot table full");
                    account[n] = sa[j].account;
                    slot[n] = sa[j].slot;
                    original[n] = sa[j].previousValue;
                    committed[n] = sa[j].previousValue;
                    ++n;
                }
                if (sa[j].isWrite && !sa[j].reverted) committed[idx] = sa[j].newValue;
            }
        }
        c.account = new address[](n);
        for (uint256 k; k < n; ++k) {
            if (original[k] == bytes32(0) && committed[k] != bytes32(0)) c.account[c.n++] = account[k];
        }
    }

    /// @dev Number of created slots held by `who`.
    function countOf(Census memory c, address who) internal pure returns (uint256 count) {
        for (uint256 k; k < c.n; ++k) if (c.account[k] == who) ++count;
    }
}
