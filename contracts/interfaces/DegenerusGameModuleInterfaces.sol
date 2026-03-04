// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.26;

/// @title IDegenerusCoinModule
/// @notice Interface for coin-related game module operations
/// @dev Implemented by the coin contract to expose game-callable functions
interface IDegenerusCoinModule {
    /// @notice Credit FLIP tokens to a player's pending coinflip balance
    /// @dev Only callable by authorized flip creditors. Silently returns if player is zero address or amount is zero.
    /// @param player The address to receive the FLIP credit
    /// @param amount The amount of FLIP to credit
    function creditFlip(address player, uint256 amount) external;

    /// @notice Credit FLIP tokens to multiple players in a single call
    /// @dev Gas optimization for batch crediting. Only callable by authorized flip creditors.
    ///      Silently skips entries where player is zero address or amount is zero.
    /// @param players Array of 3 recipient addresses (unused slots should be address(0))
    /// @param amounts Array of 3 amounts corresponding to each player
    function creditFlipBatch(address[3] calldata players, uint256[3] calldata amounts) external;

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
