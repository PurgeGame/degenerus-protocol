// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/// @title IDegenerusCoinModule
/// @notice Interface for coin-related game module operations (quest rolling and vault escrow)
/// @dev Implemented by the coin contract to expose game-callable functions.
///      Flip crediting is handled directly via IBurnieCoinflip.
interface IDegenerusCoinModule {
    /// @notice Roll daily quests for a given day using provided entropy
    /// @dev Only callable by the game contract. Randomly selects quest types for the day.
    /// @param day The day number to roll quests for
    /// @param entropy Random value used to determine quest types
    function rollDailyQuest(uint48 day, uint256 entropy) external;

    /// @notice Record an escrow amount to the vault's mint allowance
    /// @dev Only callable by GAME or VAULT contract. Increases the vault's allowance
    ///      to mint tokens later.
    /// @param amount The amount to add to the vault's mint allowance
    function vaultEscrow(uint256 amount) external;
}
