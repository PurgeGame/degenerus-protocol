// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/// @dev Frozen pricing and source geometry shared by jackpot pricing and direct delivery.
struct TicketWorkPlan {
    uint24 sourceLvl;
    uint24 queueLvl;
    uint8 salt;
    uint256 entropy;
    uint256 entriesEach;
    uint256 fullPasses;
    uint8[4] traits;
    uint16[4] counts;
    uint256[4] lens;
    address[4] deities;
}
