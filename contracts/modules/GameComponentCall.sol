// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DegenerusGameStorage} from "../storage/DegenerusGameStorage.sol";

/// @dev Uncapped component boundary. Retained capped/rollback calls use their own frames.
abstract contract GameComponentCall is DegenerusGameStorage {
    function _componentDelegate(address target, bytes memory payload) internal returns (bytes memory data) {
        bool ok;
        (ok, data) = target.delegatecall(payload);
        if (!ok) {
            if (data.length == 0) revert EmptyRevert();
            assembly ("memory-safe") { revert(add(data, 32), mload(data)) }
        }
    }
}
