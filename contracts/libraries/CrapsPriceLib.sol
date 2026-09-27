// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/// @dev Scheduled-entry expectations and pass denominations, shared by the table, Game and FLIP.
///      Retail buys an unworded future day. Reward denominations track rounded entry-cost EV.
library CrapsPriceLib {
    uint256 internal constant NORMAL_RETAIL = 25_000 ether;
    uint256 internal constant HIGH_RETAIL = 500_000 ether;
    uint256 internal constant JACKPOT_FEE = 8_000 ether;
    // Jackpot Added is 0.5% of the recorded pool, raised to a floor: 150,000 FLIP while the
    // game level is 0 or 1, then 50,000.
    uint256 internal constant JACKPOT_EARLY_MIN_ADDED = 150_000 ether;
    uint256 internal constant JACKPOT_MIN_ADDED = 50_000 ether;
    uint256 internal constant JACKPOT_EARLY_LAST_LEVEL = 1;
    // One award per 10,000 FLIP of Added keeps Added per award above the fee, so paid entries
    // never fund the awards.
    uint256 internal constant JACKPOT_AWARD_VALUE = 10_000 ether;

    // Tier means (bankroll + mean bounty): 900, 2,800 and 7,000 FLIP.
    uint256 internal constant BOOKEND_EV = (20 * 900 + 30 * 2_800 + 50 * 7_000) * 1 ether / 100;
    uint256 internal constant ROUTINE_EV = (55 * 900 + 25 * 2_800 + 20 * 7_000) * 1 ether / 100;
    uint256 internal constant DAY_EV = 2 * BOOKEND_EV + 3 * ROUTINE_EV + JACKPOT_FEE;
    uint256 internal constant HIGH_BASE = 10;
    uint256 internal constant HIGH_TAIL = 100;
    uint256 internal constant HIGH_BUCKETS = 90;
    uint256 internal constant HIGH_TAIL_BUCKETS = 11;
    uint256 internal constant HIGH_EV =
        ((HIGH_BUCKETS - HIGH_TAIL_BUCKETS) * HIGH_BASE + HIGH_TAIL_BUCKETS * HIGH_TAIL) / HIGH_BUCKETS;

    uint256 internal constant NORMAL_VALUE = (DAY_EV + 50 ether) / 100 ether * 100 ether;
    uint256 internal constant HIGH_VALUE = HIGH_EV * NORMAL_VALUE;
    // Keep the denomination switch above one whole high pass, including before stochastic rounding.
    uint256 internal constant HIGH_SWITCH = (HIGH_EV + 1) * NORMAL_VALUE;

    function tier(uint256 roll, bool bookend) internal pure returns (uint256) {
        uint256 draw = (bookend ? roll >> 40 : roll) % 100;
        if (bookend) return draw < 20 ? 0 : (draw < 50 ? 1 : 2);
        return draw < 55 ? 0 : (draw < 80 ? 1 : 2);
    }

    function highMultiple(uint256 draw) internal pure returns (uint256) {
        return draw % HIGH_BUCKETS < HIGH_TAIL_BUCKETS ? HIGH_TAIL : HIGH_BASE;
    }

    function jackpotAdded(uint256 percentage, uint256 level) internal pure returns (uint256) {
        uint256 floor = level <= JACKPOT_EARLY_LAST_LEVEL ? JACKPOT_EARLY_MIN_ADDED : JACKPOT_MIN_ADDED;
        return percentage > floor ? percentage : floor;
    }
}
