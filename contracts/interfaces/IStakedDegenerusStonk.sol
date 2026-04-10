// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/// @title IStakedDegenerusStonk
/// @notice Interface for the sDGNRS token contract (contract-to-contract calls only)
/// @dev sDGNRS is backed by ETH, stETH, and BURNIE reserves with pool-based distribution
interface IStakedDegenerusStonk {
    /// @notice sDGNRS reward pools (pre-minted supply buckets)
    /// @dev Each pool has a dedicated balance for specific distribution purposes
    enum Pool {
        Whale,
        Affiliate,
        Lootbox,
        Reward,
        Earlybird
    }

    /// @notice Deposit stETH to sDGNRS reserves
    /// @dev Called by the game contract to deposit stETH backing
    /// @param amount Amount of stETH to deposit
    function depositSteth(uint256 amount) external;

    /// @notice Get the remaining balance for a specific pool
    /// @param pool Pool identifier to query
    /// @return Remaining token balance in the pool
    function poolBalance(Pool pool) external view returns (uint256);

    /// @notice Transfer sDGNRS from a pool to a recipient
    /// @dev Restricted to authorized game contracts only
    /// @param pool Pool identifier to transfer from
    /// @param to Recipient address
    /// @param amount Amount of sDGNRS to transfer
    /// @return transferred Amount actually transferred (may be less if pool has insufficient balance)
    function transferFromPool(Pool pool, address to, uint256 amount) external returns (uint256 transferred);

    /// @notice Transfer sDGNRS between two reward pools
    /// @dev Restricted to authorized game contracts only
    /// @param from Pool to transfer from
    /// @param to Pool to transfer to
    /// @param amount Amount of sDGNRS to transfer
    /// @return transferred Amount actually transferred (may be less if source pool has insufficient balance)
    function transferBetweenPools(Pool from, Pool to, uint256 amount) external returns (uint256 transferred);

    /// @notice Burn all undistributed pool tokens at game over
    function burnAtGameOver() external;

    /// @notice Burn sDGNRS. Post-gameOver: immediate proportional payout. During game: enters
    ///         gambling claim queue (returns 0,0,0) — call claimRedemption() after resolution.
    /// @param amount Amount of sDGNRS to burn
    /// @return ethOut ETH received (0 during active game)
    /// @return stethOut stETH received (0 during active game)
    /// @return burnieOut BURNIE received (0 during active game)
    function burn(uint256 amount) external returns (uint256 ethOut, uint256 stethOut, uint256 burnieOut);

    /// @notice Transfer sDGNRS from the wrapper to a recipient (DGNRS wrapper only)
    /// @param to Recipient address
    /// @param amount Amount to transfer
    function wrapperTransferTo(address to, uint256 amount) external;

    /// @notice Get the sDGNRS token balance for an address
    /// @param account Address to query balance for
    /// @return Token balance of the account
    function balanceOf(address account) external view returns (uint256);


    /// @notice Get the total supply of sDGNRS tokens
    /// @return Total number of sDGNRS tokens in circulation
    function totalSupply() external view returns (uint256);

    /// @notice Get the BURNIE reserve backing sDGNRS
    /// @dev Includes claimable coinflip backing
    /// @return Amount of BURNIE in reserves
    function burnieReserve() external view returns (uint256);


    /// @notice Preview the output amounts from burning sDGNRS tokens
    /// @dev Returns proportional amounts based on current reserves
    /// @param amount Amount of sDGNRS to simulate burning
    /// @return ethOut Amount of ETH that would be returned
    /// @return stethOut Amount of stETH that would be returned
    /// @return burnieOut Amount of BURNIE that would be minted
    function previewBurn(uint256 amount) external view returns (uint256 ethOut, uint256 stethOut, uint256 burnieOut);

    /// @notice Check if there are unresolved gambling burn claims for the current period
    /// @return True if current period has pending base amounts
    function hasPendingRedemptions() external view returns (bool);

    /// @notice Resolve the current gambling burn period with RNG results
    /// @dev Only callable by game contract during advanceGame
    /// @param roll The random roll (25-175)
    /// @param flipDay The coinflip day for BURNIE gamble
    function resolveRedemptionPeriod(uint16 roll, uint32 flipDay) external;
}
