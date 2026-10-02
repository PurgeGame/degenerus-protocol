// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/// @notice Common conservative work currency for the MineFlip basic-work pipeline.
/// @dev Prices are upper estimates, not gasleft() refunds. Workers reserve the next
///      indivisible operation before executing it and return charged units <= allowance.
///      Jackpot stages use their independently calibrated transaction envelopes.
library MineFlipBudget {
    uint256 internal constant GAS_PER_UNIT = 4_700;
    uint256 internal constant BASIC_BUDGET = 1_920;
    // Dispatcher, stage probes, cross-module calls, completion and one bounty credit.
    uint256 internal constant ROUTER_RESERVE = 96;
    uint256 internal constant WORK_BUDGET = BASIC_BUDGET - ROUTER_RESERVE;

    function clamp(uint256 allowance) internal pure returns (uint256) {
        return allowance < WORK_BUDGET ? allowance : WORK_BUDGET;
    }
}
