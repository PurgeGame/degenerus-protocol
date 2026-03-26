// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/// @dev Minimal mock for DegenerusVault used by DegenerusCharity unit tests.
///      Supports isVaultOwner check.
contract MockVaultCharity {
    mapping(address => bool) public isVaultOwner;

    function setVaultOwner(address account, bool status) external {
        isVaultOwner[account] = status;
    }
}
