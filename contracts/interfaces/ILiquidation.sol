// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

/// @notice Game-only move of a seized deity account's soulbound pass to the account's lender.
interface IDeityPassSeize {
    function seize(uint256 tokenId, address to) external;
}
