// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {GameActions} from "./GameActions.sol";
import {ContractAddresses} from "../ContractAddresses.sol";

abstract contract GameActionEntries is GameActions {
    function drainAffiliateBases(uint256 ids, uint256 uplines) external returns (uint256, uint256, uint256) {
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();
        return _actionDrainAffiliateBases(ids, uplines);
    }

    function registerWallet_g9539(address owner, bool allocate) external returns (uint32 id) {
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();
        return _actionRegisterWallet_g9539(owner, allocate);
    }

    function registerWalletIdentity(address owner) external returns (uint32 id) {
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();
        return _actionRegisterWalletIdentity(owner);
    }

    function recordAfkingSecondary_g3316(uint32 id, uint16 amount) external {
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();
        _actionRecordAfkingSecondary(id, amount);
    }

    function floorAfkingStreakBase(uint32 id, uint16 floor) external {
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();
        _actionFloorAfkingStreakBase(id, floor);
    }

    function payRecordSdgnrs(
        uint32 id,
        uint256 shareBps
    ) external returns (uint256 paid, address payee) {
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();
        return _actionPayRecordSdgnrs(id, shareBps);
    }

    function setOperatorApproval(uint32 id, address operator, bool approved) external {
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();
        _actionSetOperatorApproval(id, operator, approved);
    }

    function setLootboxRngThreshold(uint256 newThreshold) external {
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();
        _actionSetLootboxRngThreshold(newThreshold);
    }

    function setMiddayMaxBasefee(uint256 newGwei) external {
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();
        _actionSetMiddayMaxBasefee(newGwei);
    }

    function claimClaimable(uint32 id) external {
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();
        _actionClaimWinnings(id);
    }

    function claimWinnings(uint32 id, uint256 amount) external {
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();
        _actionClaimWinnings(id, amount);
    }

    function claimWinningsStethFirst() external {
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();
        _actionClaimWinningsStethFirst();
    }

    function depositAfkingFunding(uint32 id) external payable {
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();
        _actionDepositAfkingFunding(id);
    }

    function adminSwapEthForStEth(
        address recipient,
        uint256 amount
    ) external payable {
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();
        _actionAdminSwapEthForStEth(recipient, amount);
    }

    function adminStakeEthForStEth(uint256 amount) external {
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();
        _actionAdminStakeEthForStEth(amount);
    }

    function reverseFlip(uint256 expectedCost) external {
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();
        _actionReverseFlip(expectedCost);
    }
}
