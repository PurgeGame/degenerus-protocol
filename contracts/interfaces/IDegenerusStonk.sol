// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

/// @title IDegenerusStonk
/// @notice Interface for the DGNRS token contract (contract-to-contract calls only)
/// @dev DGNRS is backed by ETH, stETH, and BURNIE reserves with pool-based distribution
interface IDegenerusStonk {
    /// @notice DGNRS reward pools (pre-minted supply buckets)
    /// @dev Each pool has a dedicated balance for specific distribution purposes
    enum Pool {
        Whale,
        Affiliate,
        Lootbox,
        Reward,
        Earlybird
    }

    /// @notice Deposit stETH to DGNRS reserves
    /// @dev Called by the game contract to deposit stETH backing
    /// @param amount Amount of stETH to deposit
    function depositSteth(uint256 amount) external;

    /// @notice Get the remaining balance for a specific pool
    /// @param pool Pool identifier to query
    /// @return Remaining token balance in the pool
    function poolBalance(Pool pool) external view returns (uint256);

    /// @notice Transfer DGNRS from a pool to a recipient
    /// @dev Restricted to authorized game contracts only
    /// @param pool Pool identifier to transfer from
    /// @param to Recipient address
    /// @param amount Amount of DGNRS to transfer
    /// @return transferred Amount actually transferred (may be less if pool has insufficient balance)
    function transferFromPool(Pool pool, address to, uint256 amount) external returns (uint256 transferred);

    /// @notice Transfer DGNRS between two reward pools
    /// @dev Restricted to authorized game contracts only
    /// @param from Pool to transfer from
    /// @param to Pool to transfer to
    /// @param amount Amount of DGNRS to transfer
    /// @return transferred Amount actually transferred (may be less if source pool has insufficient balance)
    function transferBetweenPools(Pool from, Pool to, uint256 amount) external returns (uint256 transferred);

    /// @notice Burn DGNRS tokens for game bets
    /// @dev Restricted to authorized game contracts only
    /// @param from Address to burn tokens from
    /// @param amount Amount of DGNRS to burn
    function burnForGame(address from, uint256 amount) external;

    /// @notice Approve a spender to transfer DGNRS on behalf of the caller
    /// @param spender Address to approve as spender
    /// @param amount Allowance amount to grant
    /// @return success True if approval succeeded
    function approve(address spender, uint256 amount) external returns (bool);

    /// @notice Get the DGNRS token balance for an address
    /// @param account Address to query balance for
    /// @return Token balance of the account
    function balanceOf(address account) external view returns (uint256);

    /// @notice Transfer DGNRS tokens to a recipient
    /// @param to Recipient address
    /// @param amount Amount of DGNRS to transfer
    /// @return success True if transfer succeeded
    function transfer(address to, uint256 amount) external returns (bool);

    /// @notice Transfer DGNRS from a sender using allowance
    /// @dev Requires sufficient allowance from the sender to the caller
    /// @param from Sender address
    /// @param to Recipient address
    /// @param amount Amount of DGNRS to transfer
    /// @return success True if transfer succeeded
    function transferFrom(address from, address to, uint256 amount) external returns (bool);

    /// @notice Get the total supply of DGNRS tokens
    /// @return Total number of DGNRS tokens in circulation
    function totalSupply() external view returns (uint256);

    /// @notice Get the ETH reserve backing DGNRS
    /// @return Amount of ETH in reserves
    function ethReserve() external view returns (uint256);

    /// @notice Get the BURNIE reserve backing DGNRS
    /// @dev Includes claimable coinflip backing
    /// @return Amount of BURNIE in reserves
    function burnieReserve() external view returns (uint256);

    /// @notice Get the total backing value (ETH + stETH + claimable ETH + BURNIE backing)
    /// @return Combined value of all reserves and claimables
    function totalBacking() external view returns (uint256);

    /// @notice Preview the output amounts from burning DGNRS tokens
    /// @dev Returns proportional amounts based on current reserves
    /// @param amount Amount of DGNRS to simulate burning
    /// @return ethOut Amount of ETH that would be returned
    /// @return stethOut Amount of stETH that would be returned
    /// @return burnieOut Amount of BURNIE that would be minted
    function previewBurn(uint256 amount) external view returns (uint256 ethOut, uint256 stethOut, uint256 burnieOut);
}
