// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

/// @notice Seven affiliate levels plus the immutable upline cache in one retained word.
/// @dev Two exact 35-bit scores, five clipped 19-bit bonus inputs, a uint24 level and 66 cache bits.
library AffiliateEarningsLib {
    uint256 internal constant LIVE_CAP = (uint256(1) << 35) - 1;
    uint256 internal constant HISTORY_CAP = 500_000;
    uint256 internal constant CACHE_SHIFT = 189;
    uint256 internal constant PAYLOAD_MASK = (uint256(1) << CACHE_SHIFT) - 1;
    uint256 private constant HISTORY_MASK = (uint256(1) << 95) - 1;
    uint256 private constant CACHE_MASK = ((uint256(1) << 66) - 1) << CACHE_SHIFT;

    function score(uint256 word, uint24 level) internal pure returns (uint256) {
        uint256 latest = uint24(word >> 165);
        if (level == 0 || level > latest || latest - level > 1) return 0;
        return (word >> ((latest - level) * 35)) & LIVE_CAP;
    }

    /// @dev Older lanes are bonus inputs only. Never expose them as exact historical scores.
    function bonusScore(uint256 word, uint24 level) internal pure returns (uint256) {
        uint256 latest = uint24(word >> 165);
        if (level == 0 || level > latest) return 0;
        uint256 age = latest - level;
        if (age < 2) return (word >> (age * 35)) & LIVE_CAP;
        if (age > 6) return 0;
        return (word >> (70 + (age - 2) * 19)) & ((uint256(1) << 19) - 1);
    }

    function add(uint256 word, uint24 level, uint256 amount)
        internal pure returns (uint256 updated, uint256 total, uint256 accepted)
    {
        // Zero score must not roll or initialize the word, even when its route emits an event.
        if (amount == 0) return (word, score(word, level), 0);
        uint256 latest = uint24(word >> 165);
        // Production writers all target the monotonic Game level + 1. Ignore an
        // invalid score target without interrupting the commission's token payout.
        if (level == 0 || level < latest) return (word, 0, 0);
        uint256 distance = uint256(level) - latest;
        if (distance != 0) {
            uint256 newest = word & LIVE_CAP;
            uint256 previous = (word >> 35) & LIVE_CAP;
            uint256 history = (word >> 70) & HISTORY_MASK;
            if (latest == 0 || distance >= 7) {
                previous = 0;
                history = 0;
            } else if (distance == 1) {
                history = ((history << 19) | _clip(previous)) & HISTORY_MASK;
                previous = newest;
            } else {
                history = (history << (distance * 19)) & HISTORY_MASK;
                history |= _clip(newest) << ((distance - 2) * 19);
                if (distance <= 5) history |= _clip(previous) << ((distance - 1) * 19);
                previous = 0;
            }
            word = (word & CACHE_MASK) | (uint256(level) << 165) | (history << 70) | (previous << 35);
        }
        total = word & LIVE_CAP;
        uint256 room = LIVE_CAP - total;
        accepted = amount > room ? room : amount;
        total += accepted;
        updated = (word & ~LIVE_CAP) | total;
    }

    function _clip(uint256 value) private pure returns (uint256) {
        return value > HISTORY_CAP ? HISTORY_CAP : value;
    }
}
