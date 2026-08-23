// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/*
 * TERMS OF INTERACTION — submitting a transaction to this contract accepts them.
 *
 * THIS IS GAMBLING. Outcomes are decided by chance. You can lose everything you put in
 * simply by being unlucky. That is the software working exactly as intended. Do not
 * commit funds you are not prepared to lose entirely.
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

/// @title IDegenerusJackpots
/// @notice Interface for the jackpot distribution contract.
/// @dev Handles BAF (Big Ass Flip) jackpot calculations and payouts.
interface IDegenerusJackpots {
    /// @notice Run the BAF (Big Ass Flip) jackpot distribution for a level.
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
    function getLastBafResolvedDay() external view returns (uint24);
}
