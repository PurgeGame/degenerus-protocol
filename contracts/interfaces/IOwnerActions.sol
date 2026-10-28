// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

/// @notice Owner governance reads its DGVE collateral token from the pinned Vault, never from a caller.
interface IOwnerVault {
    function dgve() external view returns (address);
}
