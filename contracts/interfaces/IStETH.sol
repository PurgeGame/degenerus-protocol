// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

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
