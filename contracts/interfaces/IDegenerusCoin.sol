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

    /// @notice Spendable FLIP for a player: wallet balance + claimable coinflip stake.
    /// @param player The address to read.
    /// @return spendable The total amount the player can spend on a burn/transfer.
    function balanceOfWithClaimable(
        address player
    ) external view returns (uint256 spendable);

    /// @notice Salvage-spendable FLIP: burnable held + claimable + auto-rebuy carry.
    /// @param player The address to read.
    /// @return spendable The amount the player can fund a salvage FLIP leg with.
    function balanceOfSpendableForSalvage(
        address player
    ) external view returns (uint256 spendable);

    /// @notice Burn FLIP for a salvage swap, draining held -> claimable -> auto-rebuy carry.
    /// @param target The buyer whose FLIP backs the swap.
    /// @param amount The FLIP (wei) to destroy.
    function burnCoinForSalvage(address target, uint256 amount) external;
}
