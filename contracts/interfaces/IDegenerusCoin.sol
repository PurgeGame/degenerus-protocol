// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/// @title IDegenerusCoin
/// @notice Interface for the Degenerus Coin token with game integration functionality
interface IDegenerusCoin {
    /// @notice Record an escrow amount to the vault's mint allowance
    /// @dev Only callable by GAME or VAULT contract.
    /// @param amount The amount to add to the vault's mint allowance
    function vaultEscrow(uint256 amount) external;

    /// @notice Burns coins from a target address
    /// @param target The address to burn coins from
    /// @param amount The amount of coins to burn
    function burnCoin(address target, uint256 amount) external;

    /// @notice Mints new coins directly to a player for game rewards
    /// @param player The address to mint coins to
    /// @param amount The amount of coins to mint
    function mintForGame(address player, uint256 amount) external;
}
