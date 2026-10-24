// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

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

import {IDegenerusGame} from "../interfaces/IDegenerusGame.sol";
import {ContractAddresses} from "../ContractAddresses.sol";

/**
 * @title GameTimeLib
 * @notice Logical gameplay identities and independent wall-clock reset calculations.
 * @dev Gameplay advances only on an accepted daily request. Wall windows reset at
 *      22:57 UTC and use ContractAddresses.DEPLOY_DAY_BOUNDARY as their origin.
 */
library GameTimeLib {
    /// @notice Daily reset time in seconds from midnight UTC (22:57 UTC = 82620 seconds)
    uint32 internal constant JACKPOT_RESET_TIME = 82620;

    /// @notice Logical index of Degenesis cohort 1, opened by the first daily request.
    uint24 internal constant DEGENESIS_START_DAY = 2;
    /// @notice First post-Degenesis logical index. Degenesis cohort `n` is index DEGENESIS_START_DAY + n - 1.
    uint24 internal constant MAIN_LAUNCH_DAY = DEGENESIS_START_DAY + 7;
    /// @notice Earliest calendar launch boundary with uninterrupted daily requests; fixture reference only.
    /// @dev Production sale and credit gates use the logical index, never this timestamp.
    uint256 internal constant DEGENESIS_END_TS =
        (uint256(ContractAddresses.DEPLOY_DAY_BOUNDARY) + MAIN_LAUNCH_DAY - 1) * 1 days + JACKPOT_RESET_TIME;

    /**
     * @notice Read the Game's most recently requested logical daily round.
     * @dev Bootstrap is day 1. Elapsed wall time does not advance this counter.
     * @return Current logical index.
     */
    function gameDayIndex() internal view returns (uint24) {
        return IDegenerusGame(ContractAddresses.GAME).currentDayView();
    }

    /// @notice Actual 22:57 reset window relative to deployment, independent of gameplay.
    function currentDayIndex() internal view returns (uint24) {
        return currentDayIndexAt(block.timestamp);
    }

    /**
     * @notice Get day index for a specific timestamp.
     * @dev Day 1 = deploy day. Days reset at JACKPOT_RESET_TIME (22:57 UTC).
     * @param ts Timestamp to evaluate. Must be at or after the deploy-day reset boundary;
     *        earlier values underflow the checked subtraction and revert.
     * @return Day index (1-indexed from deploy day).
     */
    function currentDayIndexAt(uint256 ts) internal pure returns (uint24) {
        uint24 currentDayBoundary = uint24((ts - JACKPOT_RESET_TIME) / 1 days);
        return currentDayBoundary - uint24(ContractAddresses.DEPLOY_DAY_BOUNDARY) + 1;
    }
}
