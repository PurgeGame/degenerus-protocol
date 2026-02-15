// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IDegenerusCoinModule} from "./DegenerusGameModuleInterfaces.sol";

/// @title IDegenerusCoin
/// @notice Interface for the Degenerus Coin token with game integration functionality
/// @dev Extends IDegenerusCoinModule to provide coin management and quest notification capabilities
interface IDegenerusCoin is IDegenerusCoinModule {
    /// @notice Credits coin to a player's balance without minting new tokens
    /// @param player The address to credit coins to
    /// @param amount The amount of coins to credit
    function creditCoin(address player, uint256 amount) external;

    /// @notice Burns coins from a target address
    /// @param target The address to burn coins from
    /// @param amount The amount of coins to burn
    function burnCoin(address target, uint256 amount) external;

    /// @notice Mints new coins directly to a player for game rewards
    /// @param player The address to mint coins to
    /// @param amount The amount of coins to mint
    function mintForGame(address player, uint256 amount) external;

    /// @notice Notifies the coin contract when a player mints through a quest
    /// @param player The address of the player who minted
    /// @param quantity The number of items minted
    /// @param paidWithEth True if the mint was paid with ETH, false if paid with coins
    function notifyQuestMint(address player, uint32 quantity, bool paidWithEth) external;

    /// @notice Notifies the coin contract when a player opens a loot box through a quest
    /// @param player The address of the player who opened the loot box
    /// @param amountWei The ETH amount in wei spent on the loot box
    function notifyQuestLootBox(address player, uint256 amountWei) external;

    /// @notice Notifies the coin contract when a player places a Degenerette bet
    /// @param player The address of the player who placed the bet
    /// @param amount The bet amount (wei for ETH, base units for BURNIE)
    /// @param paidWithEth True if the bet was paid with ETH, false if paid with BURNIE
    function notifyQuestDegenerette(address player, uint256 amount, bool paidWithEth) external;
}
