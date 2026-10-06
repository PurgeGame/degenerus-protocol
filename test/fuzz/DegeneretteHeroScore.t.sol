// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;
import "forge-std/Test.sol";
import {DegeneretteMathHarness} from "../../contracts/mocks/DegeneretteMathHarness.sol";

/// @notice Production math regressions for the wild-color scoring and payout table.
contract DegeneretteHeroScoreTest is Test {
    DegeneretteMathHarness private h;

    function setUp() public {
        h = new DegeneretteMathHarness();
    }

    function testDiceCannotBeChosenAsHeroes() public {
        for (uint8 symbol = 24; symbol < 32; ++symbol) {
            vm.expectRevert(bytes4(keccak256("InvalidBet()")));
            h.hero(123, symbol);
            vm.expectRevert(bytes4(keccak256("InvalidBet()")));
            h.ticket(123, symbol);
            vm.expectRevert(bytes4(keccak256("InvalidBet()")));
            h.spin(123, 456, symbol, 0);
        }
    }

    function testEveryOtherHeroRemainsSelectableAsTheOneWild() public view {
        for (uint8 symbol; symbol < 24; ++symbol) {
            assertEq(h.hero(123, symbol), symbol);
            uint32 t = h.ticket(123, symbol);
            for (uint8 q; q < 4; ++q) {
                uint8 lane = uint8(t >> (q * 8));
                if (q == symbol >> 3) assertEq(lane, 0x40 | (symbol & 7), "hero lane is wild with its symbol");
                else assertEq(lane & 0xC0, 0, "every other player lane is ordinary");
            }
        }
    }

    function testFuzzRandomHeroNeverSelectsDice(uint256 seed) public view {
        uint8 hero = h.hero(seed, 32);
        assertLt(hero, 24);
    }

    function testRandomHeroStillReachesAllOtherSymbols() public view {
        uint256 seen;
        for (uint256 seed; seed < 1024; ++seed) seen |= uint256(1) << h.hero(seed, 32);
        assertEq(seen, uint256(type(uint24).max));
    }

    function testAllDiceStillRollNaturallyInEveryColorAndWild() public view {
        for (uint256 color; color < 8; ++color) {
            for (uint256 die; die < 8; ++die) {
                uint256 ordinarySeed = (color << 192) | (uint256(1) << 195) | (die << 224);
                (uint32 player, uint32 house,,) = h.spin(123, ordinarySeed, 0, 0);
                assertEq(uint8(house >> 24), (color << 3) | die);
                assertEq(player, h.ticket(123, 0));
                (, house,,) = h.spin(123, (color << 192) | (die << 224), 0, 0);
                assertEq(uint8(house >> 24), 0x40 | die, "a zero wild nibble makes the lane wild");
            }
        }
    }

    /// @notice Hero lane: ordinary/wild house color crossed with wrong/right symbol scores 1/2/2/3.
    function testHeroLaneScoresOneTwoTwoThree() public view {
        for (uint8 hero; hero < 4; ++hero) {
            uint32 shift = uint32(hero) * 8;
            uint32 p = uint32(0x40) << shift; // hero symbol 0, wild; other lanes color 0 symbol 0
            uint32 missRest = 0x09090909 & ~(uint32(0xFF) << shift); // symbol 1, color 1: no points
            uint32[4] memory heroLane = [uint32(0x09), 0x08, 0x41, 0x40];
            uint8[4] memory expected = [1, 2, 2, 3];
            for (uint256 i; i < 4; ++i) {
                (uint8 s, uint8 w) = h.score(p, missRest | (heroLane[i] << shift));
                assertEq(s, expected[i]);
                assertEq(w, i >= 2 ? 1 : 0, "a house wild counts even when its symbol misses");
            }
        }
    }

    function testNonHeroLanesScoreSymbolAndColorOrHouseWild() public view {
        uint32 p = 0x40; // hero lane 0 wild symbol 0; lanes 1..3 color 0 symbol 0
        uint32 base = 0x09090909 & ~uint32(0xFF);
        (uint8 s, uint8 w) = h.score(p, base | 0x09);
        assertEq(s, 1, "only the guaranteed hero color point");
        (s, w) = h.score(p, base & ~(uint32(7) << 8) | 0x09);
        assertEq(s, 2, "non-hero symbol is one point");
        (s, w) = h.score(p, base & ~(uint32(0x38) << 8) | 0x09);
        assertEq(s, 2, "equal ordinary color is one point");
        (s, w) = h.score(p, (base & ~(uint32(0x3F) << 8)) | (uint32(0x41) << 8) | 0x09);
        assertEq(s, 2, "a house wild matches an ordinary player color for one point");
        assertEq(w, 1);
        (s, w) = h.score(0x40, 0x40404040);
        assertEq(s, 9, "all symbols, all colors, hero double wild");
        assertEq(w, 4);
        (s, w) = h.score(0x40, 0x00000008);
        assertEq(s, 8, "every axis equal without a hero-lane house wild is S8");
        assertEq(w, 0);
    }

    function testScoreTwoPaysNothingAndScoreThreePaysHalfBeforeActivityAndWilds() public view {
        assertEq(h.base(2), 0);
        assertEq(h.payout(2, 2, 0, 1 ether, 30_000), 0);
        assertEq(h.base(3), 50);
        assertEq(h.payout(3, 0, 1, 1 ether, 0), 0.45 ether);
        assertEq(h.payout(3, 0, 1, 1 ether, 30_000), 0.4995 ether);
        assertEq(h.payout(3, 2, 1, 1 ether, 0), 0.675 ether);
    }

    function testWildBoostAddsInsteadOfCompounds() public view {
        for (uint8 w; w < 5; ++w) {
            assertEq(h.payout(9, w, 1, 1 ether, 0), 207_000 ether * (4 + uint256(w)) / 4);
        }
    }

    function testEthAdditionIsFlatAndKeepsPrecisionUntilFinalDivision() public view {
        uint128 stake = 1 ether;
        for (uint8 score = 3; score <= 9; ++score) {
            uint256 expected = uint256(stake) * (h.base(score) * 9891 + h.ethAdd(score) * 10_000) * 5 / 4_000_000;
            assertEq(h.payout(score, 1, 0, stake, 305), expected);
            if (score >= 6) assertGt(h.payout(score, 1, 0, stake, 305), h.payout(score, 1, 1, stake, 305));
            else assertEq(h.payout(score, 1, 0, stake, 305), h.payout(score, 1, 1, stake, 305));
        }
        // The addition is not activity-scaled: ETH minus FLIP is the same at every activity.
        uint256 gap0 = h.payout(9, 0, 0, stake, 0) - h.payout(9, 0, 1, stake, 0);
        assertEq(gap0, h.payout(9, 0, 0, stake, 30_000) - h.payout(9, 0, 1, stake, 30_000));
        assertEq(gap0, 224_084 ether);
    }

    function testActivityKneesAndSaturation() public view {
        assertEq(h.roi(0), 9000);
        assertEq(h.roi(305), 9891);
        assertEq(h.roi(500), 9970);
        assertEq(h.roi(30_000), 9990);
        assertEq(h.roi(65_535), 9990);
    }

    /// @notice Fully boosted jackpot: max activity, +12% boon, S9, four house wilds. No ceiling.
    function testFullyBoostedJackpotMatchesScheduleWithoutCeiling() public view {
        uint128 boosted = 1.12 ether;
        assertEq(h.payout(9, 4, 1, boosted, 30_000) * 2, 1_029_369.6 ether, "FLIP after survival");
        assertEq(h.payout(9, 4, 0, boosted, 30_000), 1_016_632.96 ether, "ETH gross");
    }

    function testMaximumStakeAndWildsRemainInBounds() public view {
        assertEq(h.base(9), 23_000_000);
        assertEq(h.payout(9, 4, 0, 1 ether, 30_000), 907_708 ether);
        assertEq(h.payout(9, 4, 3, 1 ether, 30_000), 3_844_039.7806 ether);
        assertEq(h.payout(9, 4, 1, type(uint128).max, 30_000), uint256(type(uint128).max) * 459_540);
        assertEq(h.payout(9, 4, 0, type(uint128).max, 30_000), uint256(type(uint128).max) * 907_708);
    }

    /// @notice Exact neutral EV through the compiled payout path over every symbol-hit,
    /// house-wild and ordinary-color-equality state (lane 0 is the hero).
    function testExactJointEvFromProductionPayouts() public view {
        uint256 weightedPayout;
        for (uint8 symMask; symMask < 16; ++symMask) {
            for (uint8 wildMask; wildMask < 16; ++wildMask) {
                for (uint8 eqMask; eqMask < 8; ++eqMask) {
                    uint32 r;
                    uint256 weight = 1;
                    for (uint8 q; q < 4; ++q) {
                        bool hit = (symMask >> q) & 1 == 1;
                        bool wild = (wildMask >> q) & 1 == 1;
                        bool eq = q > 0 && (eqMask >> (q - 1)) & 1 == 1;
                        uint32 lane = hit ? 0 : 1;
                        lane |= wild ? 0x40 : (eq ? 0 : 0x08);
                        r |= lane << (q * 8);
                        weight *= uint256(hit ? 1 : 7) * uint256(wild ? 1 : 15) * uint256(q == 0 || eq ? 1 : 7);
                    }
                    (uint8 score, uint8 wilds) = h.score(0x40, r);
                    weightedPayout += weight * h.payout(score, wilds, 1, 1 ether, 30_000);
                }
            }
        }
        // E0 = 27487789317497/27487790694400 including wilds, times max activity 999/1000.
        assertEq(weightedPayout * 27_487_790_694_400 * 1000, uint256(2) ** 37 * 1 ether * 27_487_789_317_497 * 999);
    }

    function testWwxrpActivityTargetsAndHighScoreOnlyBonus() public view {
        assertEq(h.wwxrpRoi(0), 7000);
        assertEq(h.wwxrpRoi(100), 8770);
        assertLt(h.wwxrpRoi(169), 10_000);
        assertGe(h.wwxrpRoi(170), 10_000);
        assertEq(h.wwxrpRoi(305), 12_400);
        assertEq(h.wwxrpRoi(500), 12_760);
        assertEq(h.wwxrpRoi(30_000), 13_000);
        assertEq(h.wwxrpRoi(65_535), 13_000);
        for (uint8 s; s < 10; ++s) {
            for (uint8 w; w < 5; ++w) {
                uint256 low = h.payout(s, w, 3, 1 ether, 0);
                uint256 high = h.payout(s, w, 3, 1 ether, 30_000);
                if (s < 6) assertEq(low, high, "low winning scores must not get activity bonus");
                else assertGt(high, low, "all four high tiers must receive bonus");
                assertLe(h.payout(s, w, 3, type(uint128).max, 65_535), uint256(type(uint128).max) * 3_844_040);
            }
        }
    }
}
