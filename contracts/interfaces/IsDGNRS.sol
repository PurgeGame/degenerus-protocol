// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/// @title IsDGNRS
/// @notice Interface for the sDGNRS token contract (contract-to-contract calls only)
/// @dev sDGNRS is backed by ETH, stETH, and FLIP reserves with pool-based distribution
interface IsDGNRS {
    /// @notice sDGNRS reward pools (pre-minted supply buckets)
    /// @dev Each pool has a dedicated balance for specific distribution purposes
    enum Pool {
        Whale,
        Affiliate,
        Lootbox,
        Reward,
        PresaleBox
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

    /// @notice Burn all undistributed pool tokens at game over
    function burnAtGameOver() external;

    /// @notice Burn sDGNRS. Post-gameOver: immediate proportional payout. During game: enters
    ///         gambling claim queue (returns 0,0,0) — call claimRedemption() after resolution.
    /// @param amount Amount of sDGNRS to burn
    /// @return ethOut ETH received (0 during active game)
    /// @return stethOut stETH received (0 during active game)
    /// @return flipOut FLIP received (0 during active game)
    function burn(uint256 amount) external returns (uint256 ethOut, uint256 stethOut, uint256 flipOut);

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

    /// @notice Get the FLIP reserve backing sDGNRS
    /// @dev Includes claimable coinflip backing
    /// @return Amount of FLIP in reserves
    function flipReserve() external view returns (uint256);


    /// @notice Preview the output from burning sDGNRS tokens
    /// @dev Proportional share of current reserves, net of the redemption reservation. The value
    ///      is paid as ETH, stETH, or a mix chosen at pay time — the two are at par, so it is
    ///      reported as one wei-denominated figure.
    /// @param amount Amount of sDGNRS to simulate burning
    /// @return ethOut Total value that would be returned, in wei (paid as ETH and/or stETH)
    /// @return flipOut Amount of FLIP that would be minted
    function previewBurnValue(uint256 amount) external view returns (uint256 ethOut, uint256 flipOut);

    /// @notice Check if day `day` has an unresolved gambling-burn pool.
    /// @param day Wall-clock day to query.
    /// @return True if `pendingByDay[day]` has a non-zero ETH base.
    function hasPendingRedemptions(uint24 day) external view returns (bool);

    /// @notice Sentinel for the single-pool invariant.
    /// @return The wall-day of the currently-pending unresolved gambling-burn pool, or 0 if none.
    ///         Read by AdvanceModule to derive `dayToResolve` under both normal and stall paths.
    function pendingResolveDay() external view returns (uint24);

    /// @notice Total ETH value reserved in sDGNRS custody for in-flight gambling-burn redemptions.
    /// @dev Backed sDGNRS-side either way — the ETH leg of pullRedemptionReserve moves the ETH out
    ///      of the Game at submit, the custody leg pins sDGNRS's existing ETH + stETH — so it is
    ///      never part of the Game's balance and handleGameOverDrain never subtracts it. Read by
    ///      the custody leg to enforce cumulative coverage.
    function pendingRedemptionEthValue() external view returns (uint256);

    /// @notice Resolve day `dayToResolve`'s gambling-burn pool with RNG results.
    /// @dev Only callable by game contract during advanceGame. Writes redemptionPeriods[dayToResolve],
    ///      emits RedemptionResolved, then deletes pendingByDay[dayToResolve] at resolve.
    /// @param roll The random roll (25-175).
    /// @param dayToResolve Wall-clock day whose pool this call resolves.
    function resolveRedemptionPeriod(uint16 roll, uint24 dayToResolve) external;
}
