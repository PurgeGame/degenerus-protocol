// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title IDegenerusVault
/// @notice Interface for DegenerusVault functions needed by game modules
interface IDegenerusVault {
    /// @notice Mint DGNRS shares as a reward to a recipient
    /// @param to Recipient address
    /// @param amount Amount of DGNRS shares to mint (18 decimals)
    function mintDgnrsReward(address to, uint256 amount) external;

    /// @notice Get the total supply of DGNRS shares
    /// @return Total supply of allShare token
    function allShareSupply() external view returns (uint256);

    /// @notice Get ETH+stETH reserve for DGNRS claims
    /// @return ETH reserve backing DGNRS
    function dgnrsEthReserve() external view returns (uint256);

    /// @notice Get BURNIE reserve for DGNRS claims
    /// @return BURNIE reserve backing DGNRS
    function dgnrsCoinReserve() external view returns (uint256);
}
