// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {MintPaymentKind} from "../interfaces/IDegenerusGame.sol";
import {ContractAddresses} from "../ContractAddresses.sol";
import {GamePurchase} from "./GamePurchase.sol";

abstract contract GamePurchaseEntries is GamePurchase {
    function purchase(uint32 buyerId, uint256 entryQuantityScaled, uint256 boxOrder, bytes32 affiliateCode, MintPaymentKind payKind) external payable {
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();
        _purchase(buyerId, entryQuantityScaled, boxOrder, affiliateCode, payKind);
    }

    function createSmurf(bytes32 affiliateCode, MintPaymentKind payKind) external payable returns (uint32) {
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();
        return _createSmurf(affiliateCode, payKind);
    }

    function redeemFlip(uint32 id, uint256 entryQuantityScaled) external {
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();
        _redeemFlip(id, entryQuantityScaled);
    }

    function withdrawAfkingFunding(uint32 id, uint256 amount) external {
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();
        _withdrawAfkingFunding(id, amount);
    }

    function borrow(uint32 id, uint24 dueLevel, uint256 amount, uint256 minEthOut) external {
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();
        _borrow(id, dueLevel, amount, minEthOut);
    }

    function clearDebtNow(uint32 id) external payable {
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();
        _repay(id);
    }

    function sweepAccounts(uint32[] calldata ids) external returns (uint256, uint256) {
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();
        return _sweepAccounts(ids);
    }
}
