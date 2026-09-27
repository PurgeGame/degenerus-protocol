// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {CrapsViews} from "./CrapsViews.sol";
import {CrapsPins} from "./CrapsPins.sol";
import {CrapsPriceLib} from "../../contracts/libraries/CrapsPriceLib.sol";

contract PricingHarness is CrapsViews {
    function presetPrice(uint256 roll, uint256 period) external pure returns (uint256 price) {
        (uint128 bank,,, uint256 bounty,) = _bonusPreset(roll, period);
        return bank + bounty * _BATTLE_STAKE_UNIT;
    }
}

contract CrapsPricingTest is CrapsPins {
    PricingHarness internal table;

    function setUp() public {
        _installPins();
        table = new PricingHarness();
    }

    // Exhaust the joint tier/bounty cycle, rather than estimating its mean from random seeds.
    function test_exactRoutineEntryExpectation() public view {
        uint256 sum;
        // lcm(100 tier buckets, 256 * 3 bounty buckets).
        for (uint256 roll; roll < 19_200; ++roll) sum += table.presetPrice(roll, 1);
        assertEq(sum, 19_200 * 2_595 ether);
        assertEq(sum / 19_200, CrapsPriceLib.ROUTINE_EV);
    }

    function test_exactMatchingBookendEntryExpectation() public view {
        uint256 sum;
        for (uint256 bucket; bucket < 100; ++bucket) {
            for (uint256 bounty; bounty < 3; ++bounty) {
                uint256 roll = (bucket << 40) | (bounty << 8);
                uint256 price = table.presetPrice(roll, 0);
                assertEq(table.presetPrice(roll, 4), price);
                sum += price;
            }
        }
        assertEq(sum, 300 * 4_520 ether);
        assertEq(sum / 300, CrapsPriceLib.BOOKEND_EV);
    }

    function test_exactHighExpectationAndRetailMargins() public view {
        uint256 sum;
        uint256 tails;
        for (uint256 bucket; bucket < 90; ++bucket) {
            uint256 mult = CrapsPriceLib.highMultiple(bucket);
            assertTrue(mult == 10 || mult == 100);
            sum += mult;
            if (mult == 100) ++tails;
        }
        assertEq(tails, 11);
        assertEq(sum, 90 * 21);
        assertEq(CrapsPriceLib.HIGH_EV, 21);
        assertEq(CrapsPriceLib.DAY_EV, 24_825 ether);
        assertEq(CrapsPriceLib.DAY_EV * CrapsPriceLib.HIGH_EV, 521_325 ether);
        uint256 normalPrice = table.NORMAL_FUTURE_DAY_PRICE();
        uint256 highPrice = table.HIGH_FUTURE_DAY_PRICE();
        assertEq(normalPrice, 25_000 ether);
        assertEq(highPrice, 500_000 ether);
        assertGe(normalPrice, CrapsPriceLib.DAY_EV);
        assertLe(normalPrice * 100, CrapsPriceLib.DAY_EV * 101);
        assertLt(highPrice, CrapsPriceLib.DAY_EV * 21);
        assertGe(highPrice * 100, CrapsPriceLib.DAY_EV * 21 * 95);
        assertEq(table.NORMAL_PASS_VALUE(), 24_800 ether);
        assertEq(table.HIGH_PASS_VALUE(), 520_800 ether);
        assertGt(CrapsPriceLib.HIGH_SWITCH, CrapsPriceLib.HIGH_VALUE);
        assertEq(table.presetPrice(type(uint256).max, 5), 8_000 ether);
    }

    function test_jackpotAddedFloorsAndAwardCount() public pure {
        assertEq(CrapsPriceLib.jackpotAdded(0, 0), 150_000 ether);
        assertEq(CrapsPriceLib.jackpotAdded(25_000 ether, 0), 150_000 ether);
        assertEq(CrapsPriceLib.jackpotAdded(25_000 ether, 1), 150_000 ether);
        assertEq(CrapsPriceLib.jackpotAdded(400_000 ether, 1), 400_000 ether);
        assertEq(CrapsPriceLib.jackpotAdded(25_000 ether, 2), 50_000 ether);
        assertEq(CrapsPriceLib.jackpotAdded(60_000 ether, 2), 60_000 ether);
        assertEq(CrapsPriceLib.jackpotAdded(0, type(uint24).max), 50_000 ether);
        assertEq(CrapsPriceLib.JACKPOT_EARLY_MIN_ADDED / CrapsPriceLib.JACKPOT_AWARD_VALUE, 15);
        assertEq(CrapsPriceLib.JACKPOT_MIN_ADDED / CrapsPriceLib.JACKPOT_AWARD_VALUE, 5);
        // Added per award never falls below the fee, so paid entries never fund awards.
        assertGt(CrapsPriceLib.JACKPOT_AWARD_VALUE, CrapsPriceLib.JACKPOT_FEE);
    }
}
