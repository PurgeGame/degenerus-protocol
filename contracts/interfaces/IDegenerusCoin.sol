// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/*
 * TERMS OF INTERACTION — submitting a transaction to this contract accepts them.
 *
 * THIS IS GAMBLING. Outcomes are decided by chance. You can lose everything you put in
 * simply by being unlucky. That is the software working exactly as intended. Do not
 * commit funds you are not prepared to lose entirely.
 *
 * The deployed bytecode is the entire agreement and the exclusive source of truth; any
 * comment, name, document or statement that disagrees with it is in error. It has been
 * audited but is not proven correct: it may contain defects the author did not find, and
 * by interacting with it you accept that risk in full.
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
    /// @param amount The FLIP (whole tokens) to destroy.
    function burnCoinForSalvage(address target, uint256 amount) external;

    /// @notice Burn FLIP during an active Decimator window for account `id`'s weighted entry.
    /// @dev Authorized: `id == 0` is the caller (no Game resolution call; on a first burn the
    ///      caller registers through Game `registerWallet(msg.sender, true)`, a paying action). A
    ///      nonzero `id` needs Game `resolveAccount(id, msg.sender).authorized` (the account's key,
    ///      a smurf's owner, or an approved operator). The FLIP burns from the account's PAYEE
    ///      (wallet balance, then the payee's settled coinflip winnings for a shortfall); the
    ///      quest, boon, activity multiplier and the Decimator entry (`recordDecBurn(key, ...)`)
    ///      belong to the account.
    /// @param id Account the entry belongs to (0 = caller).
    /// @param amount Amount (whole FLIP) to burn; must satisfy the 2,000 FLIP minimum.
    /// @param chips The entry's board (zero to seven named chips); the last burn's board counts.
    /// @custom:reverts NotApproved If the caller may not act for `id`.
    /// @custom:reverts E (Game) If `id` is unallocated, or a new self burner registers past paid
    ///                 admission.
    /// @custom:reverts AmountLTMin If `amount` is below the minimum.
    /// @custom:reverts NotDecimatorWindow If no Decimator window is open.
    function decimatorBurn(uint32 id, uint256 amount, uint32 chips) external;

    /// @notice GAME-only sDGNRS decimator entry; the advance calls it at most once per opening (a stalled arming word skips it).
    /// @param lvl Resolution level for the opening window (current game level + 1).
    /// @param cap Whole-FLIP spending cap: 4x the previous sealed round's average credited stack (8,000 before any).
    /// @return amount Settled backing consumed; zero for an underfunded or below-minimum attempt.
    function autoDecimatorBurn(uint24 lvl, uint256 cap) external returns (uint256 amount);
}
