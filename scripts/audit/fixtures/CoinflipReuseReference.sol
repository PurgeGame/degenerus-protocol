// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

/// @notice Independent absolute-day ledger. No page, ring, hint or packed-state logic.
/// @dev Whole FLIP, 90 resolved days, implicit seeds and current carry/take-profit rounding.
contract CoinflipReuseReference {
    struct Position {
        uint256 bank;
        uint256 carry;
        uint256 stop;
        uint24 cursor;
        bool rebuy;
    }

    mapping(uint32 => mapping(uint24 => uint256)) public stakes;
    mapping(uint24 => uint16) public results;
    mapping(uint32 => Position) public positions;
    uint24 public frontier;
    uint24 public seedFirst = 1;
    uint24 public seedLast = 20;

    function setSeedWindow(uint24 first, uint24 last) external {
        seedFirst = first;
        seedLast = last;
    }

    error StakeAboveDailyCap();

    function credit(uint32 id, uint24 day, uint256 amount, bool manual) external returns (uint256 total) {
        uint256 previous = stakes[id][day];
        uint256 room = type(uint32).max - previous;
        if (manual && amount > room) revert StakeAboveDailyCap();
        total = previous + (amount > room ? room : amount);
        stakes[id][day] = total;
    }

    function configure(uint32 id, uint24 cursor, uint256 bank, uint128 carry, bool rebuy, uint128 stop) external {
        positions[id] = Position(bank, carry, stop, cursor, rebuy);
    }

    function resolve(uint24 day, uint16 reward) external {
        require(day >= frontier && reward <= 156, "reference resolution");
        results[day] = reward;
        frontier = day;
    }

    function settle(uint32 id, uint24 bafCutoff) external returns (uint256 winnings, uint256 baf, uint256 losses) {
        Position storage p = positions[id];
        uint256 carry = p.carry;
        if (!p.rebuy) {
            winnings = carry;
            carry = 0;
        }
        uint256 start = p.cursor;
        if (frontier > 90 && start < frontier - 90) {
            start = frontier - 90;
            carry = 0;
        }
        for (uint256 d = start + 1; d <= frontier; ++d) {
            // Resolved days are contiguous from day 2; only bootstrap day 1 reads 0, and nothing
            // stakes or carries into it, so it is walked like a loss day that settles nothing.
            uint256 reward = results[uint24(d)];
            uint256 stake = stakes[id][uint24(d)];
            if ((id == 1 || id == 2) && d >= seedFirst && d <= seedLast) stake += 200_000;
            stake += carry;
            if (stake != 0) {
                if (reward >= 50) {
                    uint256 payout = stake + stake * reward / 100;
                    if (d >= bafCutoff && id != 2) baf += payout;
                    if (p.rebuy) {
                        uint256 reserved = p.stop == 0 ? 0 : payout / p.stop * p.stop;
                        winnings += reserved;
                        carry = payout - reserved;
                        carry += carry * 75 / 10_000;
                        if (carry > type(uint128).max) carry = type(uint128).max;
                    } else winnings += payout;
                } else {
                    ++losses;
                    carry = 0;
                }
            }
            p.cursor = uint24(d);
        }
        p.carry = carry;
        uint256 bank = p.bank + winnings;
        p.bank = bank > type(uint128).max ? type(uint128).max : bank;
    }
}
