// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {ContractAddresses} from "../ContractAddresses.sol";
import {GamePurchase} from "./GamePurchase.sol";
import {MintPaymentKind} from "../interfaces/IDegenerusGame.sol";

/// @notice Explicit-value purchase adapter for the Foil module; executes in Game storage.
contract DegenerusGameMintModule is GamePurchase {
    /// @notice Execute the Foil purchase's explicit-value ticket and box legs in Game storage.
    /// @dev Payable so the carried msg.value does not revert the delegatecall.
    function purchaseWith(
        uint32 buyerId,
        uint256 entryQuantityScaled,
        uint256 boxOrder,
        bytes32 affiliateCode,
        MintPaymentKind payKind,
        uint256 ethValue,
        uint32 payerId
    ) external payable {
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();
        _purchaseWith(buyerId, entryQuantityScaled, boxOrder, affiliateCode, payKind, ethValue, payerId);
    }
}
