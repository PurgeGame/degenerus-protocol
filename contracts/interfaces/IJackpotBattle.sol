// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/// @dev Called at CRAPS. Lifecycle/view selectors delegate to JackpotBattle; settlement stays on the table.
interface IJackpotBattle {
    /// @param pool The recorded prize pool the Added allocation is drawn from, in wei.
    /// @param level The Game's level at the request, which prices the pool and picks the floor.
    function lockJackpotBattle(uint24 requestDay, uint256 pool, uint24 level) external;
    function prepareJackpotBattle(uint24 level, uint256 word) external returns (uint256 drawWord, uint256 cursor, uint256 remaining);
    function appendJackpotBattle(uint256[] calldata field, uint256 cursor, bool last) external;
    function jackpotProgress() external view returns (uint64 slot, uint256 added, bool started, bool complete);
    function highRollerReserve() external view returns (uint256);
    function jackpotEntryPrice() external view returns (uint256);
    function jackpotEntryPriceOf(uint64 slot) external view returns (uint256);
}
