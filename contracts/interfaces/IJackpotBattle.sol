// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

/// @dev Called at CRAPS. Lifecycle selectors delegate to JackpotBattle; settlement stays on the table.
interface IJackpotBattle {
    /// @param pool The recorded prize pool the Added allocation is drawn from, in wei.
    /// @param level The Game's level at the request, which prices the pool and picks the floor.
    /// @return locked True when a round is active for the daily phase to draw; false before the
    ///         first window day.
    function lockJackpotBattle(uint24 requestDay, uint256 pool, uint24 level) external returns (bool locked);
    function prepareJackpotBattle(uint24 level, uint256 word) external returns (uint256 drawWord, uint256 cursor, uint256 remaining);
    function appendJackpotBattle(uint256[] calldata field, uint256 cursor, bool last) external;
    function jackpotProgress() external view returns (uint64 slot, uint256 added, bool started, bool complete);
}
