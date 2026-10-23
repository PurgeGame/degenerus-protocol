// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;
import {QaSlots} from "./QaSlots.sol";

/// @dev Compiler pins checked by scripts/check-storage-reuse-phase2-layout.py.
library PeripheralSlots {
    uint256 internal constant SD_BATCHES = 10;
    uint256 internal constant SD_BATCH_PLAYERS = 8;
    uint256 internal constant SD_BATCH_COUNTS = 6;
    uint256 internal constant AFF_LEVEL_SCORE = QaSlots.SCORE;
    uint256 internal constant CR_DAY_TICKETS = 15;
    uint256 internal constant CR_DAY_STAKED = 79;
    uint256 internal constant CR_BOOST_BUDGET = 143;
    uint256 internal constant CR_DAY_SEATED = 2833;
    uint256 internal constant GNR_APPROVE_WEIGHT = 45;
    uint256 internal constant WW_DRAW_HEADER = 9;
    uint256 internal constant WW_DRAW_ENTRY = 3;
    uint256 internal constant WW_INCIN_HEADER = 39;
    uint256 internal constant WW_INCIN_ENTRY = 5;
    uint256 internal constant WW_DAY_CLAIMED = 4;
    uint256 internal constant WW_CLAIMABLE = 8;
    uint256 internal constant JP_BAF_TOP = 3;
    uint256 internal constant JP_BAF_LEVEL = 1;
    uint256 internal constant JP_BAF_BANK_LEVELS = 2;
    uint256 internal constant CENSUS_DIRECT_END = 2849;
}
