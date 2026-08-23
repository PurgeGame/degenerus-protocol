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

/// @notice Interface for tokens with vault mint allowance (FLIP).
/// @dev Used by DegenerusVault and game modules for minting tokens
///      from vault escrow without requiring token transfers.
interface IVaultCoin {
    /// @notice Mint tokens to recipient from vault's allowance.
    /// @param to Recipient address.
    /// @param amount Amount to mint.
    function vaultMintTo(address to, uint256 amount) external;

    /// @notice View the vault's remaining mint allowance.
    /// @return Remaining amount available for vault minting.
    function vaultMintAllowance() external view returns (uint256);

    /// @notice Get token balance for an address.
    /// @param account Address to query.
    /// @return Balance of FLIP.
    function balanceOf(address account) external view returns (uint256);

    /// @notice Transfer FLIP to a recipient.
    /// @param to Recipient address.
    /// @param amount Amount to transfer.
    /// @return success True on success.
    function transfer(address to, uint256 amount) external returns (bool);
}
