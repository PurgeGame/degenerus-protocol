// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title IDegenerusStonk
/// @notice Interface for DGNRS token contract
interface IDegenerusStonk {
    /// @notice DGNRS reward pools (pre-minted supply buckets).
    enum Pool {
        Exterminator,
        Whale,
        Affiliate,
        Lootbox,
        Reward,
        Earlybird
    }

    /// @notice Escrow virtual BURNIE mint allowance
    /// @dev Called by COIN contract when it escrows virtual BURNIE to DGNRS
    /// @param amount Amount of BURNIE mint allowance
    function vaultEscrow(uint256 amount) external;

    /// @notice Deposit stETH to DGNRS reserves
    /// @dev Called by game contract to deposit 20% of stETH to DGNRS
    /// @param amount Amount of stETH to deposit
    function depositSteth(uint256 amount) external;

    /// @notice Return remaining balance for a pool.
    /// @param pool Pool identifier.
    /// @return Remaining pool balance.
    function poolBalance(Pool pool) external view returns (uint256);

    /// @notice Transfer DGNRS from a pool to a recipient (game only).
    /// @param pool Pool identifier.
    /// @param to Recipient address.
    /// @param amount Amount of DGNRS to transfer.
    /// @return transferred Amount actually transferred.
    function transferFromPool(Pool pool, address to, uint256 amount) external returns (uint256 transferred);

    /// @notice Approve a spender to transfer DGNRS.
    /// @param spender Spender address.
    /// @param amount Allowance amount.
    /// @return success True on success.
    function approve(address spender, uint256 amount) external returns (bool);

    /// @notice Get token balance for an address
    /// @param account Address to query
    /// @return Balance of DGNRS
    function balanceOf(address account) external view returns (uint256);

    /// @notice Transfer DGNRS to a recipient
    /// @param to Recipient address
    /// @param amount Amount to transfer
    /// @return success True on success
    function transfer(address to, uint256 amount) external returns (bool);

    /// @notice Transfer DGNRS from a sender (requires allowance).
    /// @param from Sender address.
    /// @param to Recipient address.
    /// @param amount Amount to transfer.
    /// @return success True on success.
    function transferFrom(address from, address to, uint256 amount) external returns (bool);

    /// @notice Get total supply of DGNRS
    /// @return Total supply
    function totalSupply() external view returns (uint256);

    /// @notice Get ETH reserve backing DGNRS
    /// @return ETH reserve
    function ethReserve() external view returns (uint256);

    /// @notice Get stETH reserve backing DGNRS
    /// @return stETH reserve
    function stethReserve() external view returns (uint256);

    /// @notice Get BURNIE reserve backing DGNRS (vaultMintAllowance)
    /// @return BURNIE reserve
    function burnieReserve() external view returns (uint256);

    /// @notice Get virtual BURNIE mint allowance
    /// @return Mint allowance
    function vaultMintAllowance() external view returns (uint256);

    /// @notice Get total backing (ETH + stETH + BURNIE)
    /// @return Total backing
    function totalBacking() external view returns (uint256);

    /// @notice Preview burn output
    /// @param amount Amount to burn
    /// @return ethOut ETH output
    /// @return stethOut stETH output
    /// @return burnieOut BURNIE output
    function previewBurn(uint256 amount) external view returns (uint256 ethOut, uint256 stethOut, uint256 burnieOut);
}
