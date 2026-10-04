// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/*
 * TERMS OF INTERACTION — submitting a transaction to this contract accepts them.
 *
 * THIS IS GAMBLING. Outcomes are decided by chance. You can lose everything you put in
 * simply by being unlucky. That is the software working exactly as intended. Do not
 * commit funds you are not prepared to lose entirely.
 *
 * The deployed bytecode is the entire agreement and the exclusive source of truth; any
 * comment, name, document or statement that disagrees with it is in error. It has been
 * audited but is not proven correct: it may contain defects the author did not find, and
 * by interacting with it you accept that risk in full.
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
    /// @notice Opens a bracket's resolution (today's winning-flip claims route onward).
    function beginBaf() external;

    /// @notice Closes a resolved bracket: clears the board and bumps the epoch.
    function finalizeBaf(uint24 lvl) external;

    /// @notice Head award `slot` (0 top bettor, 1 armed-day depositor draw, 2 word-picked 3rd/4th).
    function bafHeadWinner(uint24 lvl, uint256 rngWord, uint8 slot) external view returns (address winner);

    /// @notice Best and second-best BAF score of scatter rounds 2 * pair and 2 * pair + 1 of `rounds`.
    function bafPairWinners(uint24 lvl, uint256 rngWord, uint256 pair, uint256 rounds)
        external view returns (address[4] memory winners);

    /// @notice Record a coinflip win for BAF score tracking.
    /// @param player Address of the player.
    /// @param lvl BAF bracket (level rounded up to the next multiple of 10).
    /// @param amount Winning coinflip payout credited to the player's BAF score.
    function recordBafFlip(address player, uint24 lvl, uint256 amount) external;

    /// @notice Mark a BAF bracket as skipped when the daily flip loses.
    /// @dev Bumps lastBafResolvedDay so pre-skip winning-flip credit cannot
    ///      roll forward into future bracket leaderboards.
    /// @param lvl Level whose BAF was skipped.
    function markBafSkipped(uint24 lvl) external;

    /// @notice Day index of the most recent BAF resolution or skip.
    function getLastBafResolvedDay() external view returns (uint24);
}
