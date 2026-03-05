// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";

/// @title PriceLookup Invariant Fuzz Tests
/// @notice Verifies price curve properties: bounded, monotonic within tiers, deterministic.
contract PriceLookupInvariantsTest is Test {
    using PriceLookupLib for uint24;

    /// @notice price is always within [0.01 ETH, 0.24 ETH]
    function testFuzz_priceBounded(uint24 level) public pure {
        uint256 price = PriceLookupLib.priceForLevel(level);
        assertGe(price, 0.01 ether, "price must be >= 0.01 ETH");
        assertLe(price, 0.24 ether, "price must be <= 0.24 ETH");
    }

    /// @notice price is deterministic (same level always returns same price)
    function testFuzz_priceDeterministic(uint24 level) public pure {
        uint256 price1 = PriceLookupLib.priceForLevel(level);
        uint256 price2 = PriceLookupLib.priceForLevel(level);
        assertEq(price1, price2, "price must be deterministic");
    }

    /// @notice price only takes one of exactly 6 valid values
    function testFuzz_priceInValidSet(uint24 level) public pure {
        uint256 price = PriceLookupLib.priceForLevel(level);
        assertTrue(
            price == 0.01 ether ||
            price == 0.02 ether ||
            price == 0.04 ether ||
            price == 0.08 ether ||
            price == 0.12 ether ||
            price == 0.16 ether ||
            price == 0.24 ether,
            "price must be one of the 7 valid tiers"
        );
    }

    /// @notice cyclic property: for levels >= 200, level N and level N+100 have same price
    function testFuzz_cyclicAfter100(uint24 level) public pure {
        vm.assume(level >= 100);
        vm.assume(level <= type(uint24).max - 100);

        uint256 priceA = PriceLookupLib.priceForLevel(level);
        uint256 priceB = PriceLookupLib.priceForLevel(level + 100);
        assertEq(priceA, priceB, "price must repeat every 100 levels after level 100");
    }

    /// @notice milestone levels (x00) always cost 0.24 ETH
    function testFuzz_milestonePricing(uint24 cycleNum) public pure {
        vm.assume(cycleNum >= 1 && cycleNum <= 100_000);
        uint24 level = cycleNum * 100;
        assertEq(PriceLookupLib.priceForLevel(level), 0.24 ether, "x00 levels must be 0.24 ETH");
    }

    /// @notice within a cycle, price is weakly monotonic (never decreases within cycle segments)
    function testFuzz_weaklyMonotonicInCycle(uint24 baseLevel, uint24 offsetA, uint24 offsetB) public pure {
        vm.assume(baseLevel >= 1 && baseLevel <= 10_000);
        vm.assume(offsetA < 100 && offsetB < 100);

        uint24 levelA = baseLevel * 100 + offsetA;
        uint24 levelB = baseLevel * 100 + offsetB;

        if (offsetA < offsetB) {
            // price at higher offset within same cycle should be >= price at lower offset
            // EXCEPT offset 0 is the milestone (0.24), offsets 1-29 drop back to 0.04
            if (offsetA > 0) {
                assertGe(
                    PriceLookupLib.priceForLevel(levelB),
                    PriceLookupLib.priceForLevel(levelA),
                    "price should be weakly monotonic within non-milestone offsets"
                );
            }
        }
    }

    /// @notice intro pricing verified
    function testFuzz_introPricing(uint24 level) public pure {
        vm.assume(level < 10);
        uint256 price = PriceLookupLib.priceForLevel(level);
        if (level < 5) {
            assertEq(price, 0.01 ether, "levels 0-4 must be 0.01 ETH");
        } else {
            assertEq(price, 0.02 ether, "levels 5-9 must be 0.02 ETH");
        }
    }

    /// @notice cost calculation: (priceWei * ticketQuantity) / 400 never overflows for reasonable inputs
    function testFuzz_costCalculation(uint24 level, uint256 ticketQuantity) public pure {
        vm.assume(ticketQuantity > 0 && ticketQuantity <= 400 * 100); // max 100 full tickets
        uint256 priceWei = PriceLookupLib.priceForLevel(level);

        // This must not overflow
        uint256 cost = (priceWei * ticketQuantity) / 400;
        assertLe(cost, priceWei * 100, "cost should never exceed 100 full ticket prices");
        assertGt(cost, 0, "cost should be non-zero for non-zero quantity");
    }
}
