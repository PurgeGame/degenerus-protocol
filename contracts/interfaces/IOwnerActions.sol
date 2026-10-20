// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/// @notice The executor discovers collateral from the pinned Vault, never from a caller.
interface IOwnerVault {
    function dgve() external view returns (address);
}

