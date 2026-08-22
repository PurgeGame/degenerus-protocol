// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/*
 * TERMS OF INTERACTION — submitting a transaction to this contract accepts them.
 *
 * THIS IS GAMBLING. Outcomes are decided by chance. You can lose everything you put in
 * simply by being unlucky. That is the software working exactly as intended, not a
 * malfunction and not a defect. Do not commit funds you are not prepared to lose
 * entirely.
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

/// @title IStETH
/// @notice Minimal Lido stETH interface shared across contracts
/// @dev This interface exposes only the subset of stETH functions needed by consuming contracts
interface IStETH {
    /// @notice Submit ETH to the Lido staking pool and receive stETH in return
    /// @param referral Address to attribute this deposit to for referral tracking
    /// @return The amount of stETH shares minted
    function submit(address referral) external payable returns (uint256);

    /// @notice Get the stETH balance of an account
    /// @param account The address to query the balance of
    /// @return The amount of stETH held by the account
    function balanceOf(address account) external view returns (uint256);

    /// @notice Transfer stETH to a recipient
    /// @param to The address to transfer stETH to
    /// @param amount The amount of stETH to transfer
    /// @return True if the transfer succeeded
    function transfer(address to, uint256 amount) external returns (bool);

    /// @notice Approve a spender to transfer stETH on behalf of the caller
    /// @param spender The address authorized to spend
    /// @param amount The maximum amount the spender can transfer
    /// @return True if the approval succeeded
    function approve(address spender, uint256 amount) external returns (bool);

    /// @notice Transfer stETH from one address to another using an allowance
    /// @param from The address to transfer stETH from
    /// @param to The address to transfer stETH to
    /// @param amount The amount of stETH to transfer
    /// @return True if the transfer succeeded
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}
