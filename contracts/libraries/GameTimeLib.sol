// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {ContractAddresses} from "../ContractAddresses.sol";

/**
 * @title GameTimeLib
 * @notice Shared day index and time calculations for game mechanics
 * @dev Days reset at JACKPOT_RESET_TIME (22:57 UTC), not midnight.
 *      Day 1 = deploy day. Uses ContractAddresses.DEPLOY_DAY_BOUNDARY for reference.
 */
library GameTimeLib {
    /// @notice Daily reset time in seconds from midnight UTC (22:57 UTC = 82620 seconds)
    uint48 internal constant JACKPOT_RESET_TIME = 82620;

    /**
     * @notice Get current day index relative to deploy time.
     * @dev Day 1 = deploy day. Days reset at JACKPOT_RESET_TIME (22:57 UTC).
     * @return Current day index (1-indexed from deploy day).
     */
    function currentDayIndex() internal view returns (uint48) {
        return currentDayIndexAt(uint48(block.timestamp));
    }

    /**
     * @notice Get day index for a specific timestamp.
     * @dev Day 1 = deploy day. Days reset at JACKPOT_RESET_TIME (22:57 UTC).
     * @param ts Timestamp to evaluate.
     * @return Day index (1-indexed from deploy day).
     */
    function currentDayIndexAt(uint48 ts) internal pure returns (uint48) {
        uint48 currentDayBoundary = uint48((ts - JACKPOT_RESET_TIME) / 1 days);
        return currentDayBoundary - ContractAddresses.DEPLOY_DAY_BOUNDARY + 1;
    }
}
