// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {ContractAddresses} from "../ContractAddresses.sol";
import {GamePurchase} from "./GamePurchase.sol";

/// @dev Vault-controlled account allowance administration in Game storage.
abstract contract GameAllowanceEntries is GamePurchase {
    function raiseSmurfBaseAllowance(uint32 mainId, uint16 newBase) external {
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();
        _raiseSmurfBaseAllowance(mainId, newBase);
    }
}
