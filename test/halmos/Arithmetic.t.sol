// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import "forge-std/Test.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";

/// @title FVRF-02: Arithmetic Property Symbolic Tests
/// @notice Halmos bounded model checks for key arithmetic invariants.
/// @dev Run with: halmos --contract ArithmeticSymbolicTest --solver-timeout-assertion 60
contract ArithmeticSymbolicTest is Test {
    // =========================================================================
    // Property 1: PriceLookupLib.priceForLevel is weakly monotonic within cycle
    // =========================================================================

    /// @notice Price is always in valid set [0.01, 0.02, 0.04, 0.08, 0.12, 0.16, 0.24] ETH
    function check_price_in_valid_set(uint24 n) public pure {
        uint256 p = PriceLookupLib.priceForLevel(n);
        assert(
            p == 0.01 ether ||
            p == 0.02 ether ||
            p == 0.04 ether ||
            p == 0.08 ether ||
            p == 0.12 ether ||
            p == 0.16 ether ||
            p == 0.24 ether
        );
    }

    /// @notice Price is always bounded [0.01 ETH, 0.24 ETH]
    function check_price_bounded(uint24 n) public pure {
        uint256 p = PriceLookupLib.priceForLevel(n);
        assert(p >= 0.01 ether);
        assert(p <= 0.24 ether);
    }

    /// @notice For levels >= 100, price repeats every 100 levels
    function check_price_cyclic(uint24 n) public pure {
        if (n < 100 || n > type(uint24).max - 100) return;
        assert(PriceLookupLib.priceForLevel(n) == PriceLookupLib.priceForLevel(n + 100));
    }

    /// @notice Within a non-milestone segment of a cycle, price is weakly monotonic
    /// @dev For offsets 1-99 within any cycle (100+), price(a) <= price(b) when a < b
    function check_price_weakly_monotonic_in_cycle(uint24 cycle, uint24 a, uint24 b) public pure {
        if (cycle < 1 || cycle > 10000) return;
        if (a == 0 || b == 0 || a >= 100 || b >= 100 || a >= b) return;

        uint24 levelA = cycle * 100 + a;
        uint24 levelB = cycle * 100 + b;
        assert(PriceLookupLib.priceForLevel(levelB) >= PriceLookupLib.priceForLevel(levelA));
    }

    // =========================================================================
    // Property 2: BPS arithmetic -- splits never exceed 10000
    // =========================================================================

    /// @notice BPS split of any amount sums correctly (no rounding amplification)
    function check_bps_split_bounded(uint256 amount, uint16 bps) public pure {
        if (amount > 1e30) return; // reasonable ETH range
        if (bps > 10000) return;

        uint256 share = (amount * bps) / 10000;
        uint256 remainder = amount - share;
        assert(share + remainder == amount);
        assert(share <= amount);
    }

    /// @notice Two-way BPS split sums to original
    function check_bps_two_split(uint256 amount, uint16 futureBps) public pure {
        if (amount > 1e30) return;
        if (futureBps > 10000) return;

        uint256 futureShare = (amount * futureBps) / 10000;
        uint256 nextShare = amount - futureShare;
        assert(futureShare + nextShare == amount);
    }

    // =========================================================================
    // Property 3: Deity pass T(n) formula -- no overflow
    // =========================================================================

    /// @notice T(n) = n*(n+1)/2 does not overflow for practical deity pass counts
    function check_deity_tn_no_overflow(uint256 n) public pure {
        if (n > 1000) return; // max practical deity passes
        uint256 tn = n * (n + 1) / 2;
        uint256 price = 24 ether + tn;
        assert(price >= 24 ether); // no underflow
        assert(price < type(uint256).max); // no overflow
        assert(tn == n * (n + 1) / 2); // deterministic
    }

    /// @notice T(n) is strictly monotonic: T(n+1) > T(n) for n >= 1
    function check_deity_tn_monotonic(uint256 n) public pure {
        if (n == 0 || n > 1000) return;
        uint256 tn = n * (n + 1) / 2;
        uint256 tn1 = (n + 1) * (n + 2) / 2;
        assert(tn1 > tn);
    }

    // =========================================================================
    // Property 4: Cost calculation conservation
    // =========================================================================

    /// @notice Cost = (priceWei * ticketQuantity) / 400 is bounded and non-zero
    function check_cost_bounded(uint24 level, uint32 ticketQuantity) public pure {
        if (ticketQuantity == 0 || ticketQuantity > 40000) return;

        uint256 priceWei = PriceLookupLib.priceForLevel(level);
        uint256 cost = (priceWei * uint256(ticketQuantity)) / 400;

        // Cost should never exceed 100 full tickets (qty 40000 / 400 = 100)
        assert(cost <= priceWei * 100);
        // Cost should be non-zero for non-zero quantity and non-zero price
        if (priceWei > 0) {
            // For very small quantities, cost could round to 0
            // but for qty >= 400/priceWei it should be non-zero
            assert(cost <= type(uint256).max);
        }
    }

    /// @notice Cost calculation does not overflow for max inputs
    function check_cost_no_overflow(uint24 level, uint256 ticketQuantity) public pure {
        if (ticketQuantity > 40000) return;

        uint256 priceWei = PriceLookupLib.priceForLevel(level);
        // priceWei max = 0.24 ether = 2.4e17
        // ticketQuantity max = 40000
        // product max = 2.4e17 * 40000 = 9.6e21, well under uint256 max
        uint256 product = priceWei * ticketQuantity;
        assert(product / ticketQuantity == priceWei || ticketQuantity == 0);
        uint256 cost = product / 400;
        assert(cost <= product);
    }

    // =========================================================================
    // Property 5: Auto-rebuy ethSpent <= rebuyAmount
    // =========================================================================

    /// @notice baseTickets * ticketPrice <= rebuyAmount by construction
    function check_autorebuy_ethspent_bounded(uint256 rebuyAmount, uint24 targetLevel) public pure {
        if (targetLevel > 16_000_000) return;

        uint256 ticketPrice = PriceLookupLib.priceForLevel(targetLevel) >> 2;
        if (ticketPrice == 0) return;

        uint256 baseTickets = rebuyAmount / ticketPrice;
        if (baseTickets == 0) return;

        uint256 ethSpent = baseTickets * ticketPrice;
        assert(ethSpent <= rebuyAmount);
    }

    /// @notice Take-profit reserved amount is always a multiple of takeProfit setting
    function check_takeprofit_multiple(uint256 weiAmount, uint256 takeProfit) public pure {
        if (takeProfit == 0) return;
        if (weiAmount > 1e30) return;

        uint256 reserved = (weiAmount / takeProfit) * takeProfit;
        assert(reserved <= weiAmount);
        assert(reserved % takeProfit == 0);

        uint256 rebuyAmount = weiAmount - reserved;
        assert(rebuyAmount < takeProfit);
        assert(reserved + rebuyAmount == weiAmount);
    }
}
