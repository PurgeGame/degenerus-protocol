// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/// @title IDegenerusJackpots
/// @notice Interface for the jackpot distribution contract.
/// @dev Handles BAF (Biggest and First) jackpot calculations and payouts.
interface IDegenerusJackpots {
    /// @notice Run the BAF (Biggest and First) jackpot distribution for a level.
    /// @dev Uses VRF randomness for winner selection. Access restricted to game contract.
    /// @param poolWei Total ETH pool to distribute.
    /// @param lvl The level being settled.
    /// @param rngWord VRF random word for winner selection.
    /// @return winners Array of winning addresses.
    /// @return amounts Array of corresponding payout amounts.
    /// @return returnAmountWei Amount of pool returned (undistributed).
    function runBafJackpot(
        uint256 poolWei,
        uint24 lvl,
        uint256 rngWord
    )
        external
        returns (address[] memory winners, uint256[] memory amounts, uint256 returnAmountWei);

    /// @notice Record a BAF (coinflip) deposit for jackpot eligibility tracking.
    /// @param player The player making the deposit.
    /// @param lvl The current game level.
    /// @param amount The amount deposited (for leaderboard ranking).
    function recordBafFlip(address player, uint24 lvl, uint256 amount) external;

    /// @notice Mark a BAF bracket as skipped when the daily flip loses.
    /// @dev Bumps lastBafResolvedDay so pre-skip winning-flip credit cannot
    ///      roll forward into future bracket leaderboards.
    /// @param lvl Level whose BAF was skipped.
    function markBafSkipped(uint24 lvl) external;

    /// @notice Day index of the most recent BAF jackpot resolution.
    function getLastBafResolvedDay() external view returns (uint32);
}
