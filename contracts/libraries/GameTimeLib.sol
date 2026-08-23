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

import {ContractAddresses} from "../ContractAddresses.sol";

/**
 * @title GameTimeLib
 * @notice Shared day index and time calculations for game mechanics
 * @dev Days reset at JACKPOT_RESET_TIME (22:57 UTC), not midnight.
 *      Day 1 = deploy day. Uses ContractAddresses.DEPLOY_DAY_BOUNDARY for reference.
 */
library GameTimeLib {
    /// @notice Daily reset time in seconds from midnight UTC (22:57 UTC = 82620 seconds)
    uint32 internal constant JACKPOT_RESET_TIME = 82620;

    /**
     * @notice Get current day index relative to deploy time.
     * @dev Day 1 = deploy day. Days reset at JACKPOT_RESET_TIME (22:57 UTC).
     * @return Current day index (1-indexed from deploy day).
     */
    function currentDayIndex() internal view returns (uint24) {
        return currentDayIndexAt(block.timestamp);
    }

    /**
     * @notice Get day index for a specific timestamp.
     * @dev Day 1 = deploy day. Days reset at JACKPOT_RESET_TIME (22:57 UTC).
     * @param ts Timestamp to evaluate. Must be at or after the deploy-day reset boundary;
     *        earlier values underflow the unsigned subtraction and wrap.
     * @return Day index (1-indexed from deploy day).
     */
    function currentDayIndexAt(uint256 ts) internal pure returns (uint24) {
        uint24 currentDayBoundary = uint24((ts - JACKPOT_RESET_TIME) / 1 days);
        return currentDayBoundary - uint24(ContractAddresses.DEPLOY_DAY_BOUNDARY) + 1;
    }
}
