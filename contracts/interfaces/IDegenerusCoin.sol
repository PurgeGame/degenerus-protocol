// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/*
 * TERMS OF INTERACTION — submitting a transaction to this contract accepts them.
 *
 * THIS IS GAMBLING. Outcomes are decided by chance. You can lose everything you put in
 * simply by being unlucky. That is the software working exactly as intended. Do not
 * commit funds you are not prepared to lose entirely.
 *
 * The deployed bytecode is the entire agreement, and controls over every comment, name,
 * document and statement made about it. It has been audited but is not proven correct:
 * it may contain defects the author did not find, and by interacting with it you accept
 * that risk in full.
 *
 * Any state transition the code permits is authorised — including one that exploits a
 * defect, and including sequences the author did not intend or foresee. A bug is not a
 * breach of these terms. There is no unwritten rule behind the code for a permitted
 * transaction to violate, and no unauthorised access to this contract.
 *
 * You bear all resulting loss, whether it follows from chance or from a defect. There is
 * no refund, no rollback and no privileged party able to restore a position.
 *
 * Provided AS IS, without warranty of any kind. Full text: TERMS.md
 */

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
