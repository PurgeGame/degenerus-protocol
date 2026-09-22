// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;
import "forge-std/Test.sol";
import {DegeneretteMathHarness} from "../../contracts/mocks/DegeneretteMathHarness.sol";

/// @notice Production math regressions replacing the retired per-gold/hero tables.
contract DegeneretteHeroScoreTest is Test {
    DegeneretteMathHarness private h;

    function setUp() public {
        h = new DegeneretteMathHarness();
    }

    function testHeroTwoPointsAndIndependentColorOnePoint() public view {
        for (uint8 hero; hero < 4; ++hero) {
            uint32 allMiss = 0x09090909;
            uint32 symbolOnly = allMiss & ~(uint32(7) << (hero * 8));
            (uint8 s,) = h.score(0, symbolOnly, hero);
            assertEq(s, 2);
            uint32 colorOnly = allMiss & ~(uint32(0x38) << (hero * 8));
            (s,) = h.score(0, colorOnly, hero);
            assertEq(s, 1);
        }
    }

    function testScoreTwoReturnsHalfBeforeActivityAndGold() public view {
        assertEq(h.base(2), 50);
        assertEq(h.payout(2, 0, 1, 1 ether, 0), 0.45 ether);
        assertEq(h.payout(2, 0, 1, 1 ether, 30_000), 0.4995 ether);
        assertEq(h.payout(2, 2, 1, 1 ether, 0), 0.675 ether);
    }

    function testGoldBoostAddsInsteadOfCompounds() public view {
        for (uint8 g; g < 5; ++g) {
            assertEq(h.payout(9, g, 1, 1 ether, 0), 90_000 ether * (4 + uint256(g)) / 4);
        }
    }

    function testEthBonusBudgetKeepsPrecisionUntilFinalDivision() public view {
        uint256[4] memory factors = [uint256(1_013_556), 7_134_497, 3_952_953, 44_739_242];
        uint128 stake = 1 ether;
        for (uint8 score = 6; score <= 9; ++score) {
            uint256 expected =
                uint256(stake) * h.base(score) * 5 * (uint256(9891) * 1e6 + 500 * factors[score - 6]) / 4e12;
            assertEq(h.payout(score, 1, 0, stake, 305), expected);
            assertGt(h.payout(score, 1, 0, stake, 305), h.payout(score, 1, 1, stake, 305));
        }
        assertEq(h.payout(5, 1, 0, stake, 305), h.payout(5, 1, 1, stake, 305));
    }

    function testActivityKneesAndSaturation() public view {
        assertEq(h.roi(0), 9000);
        assertEq(h.roi(305), 9891);
        assertEq(h.roi(500), 9970);
        assertEq(h.roi(30_000), 9990);
        assertEq(h.roi(65_535), 9990);
    }

    function testMaximumStakeAndGoldRemainInBounds() public view {
        assertEq(h.payout(9, 4, 1, type(uint128).max, 30_000), uint256(type(uint128).max) * 199_800);
        assertLe(h.payout(9, 4, 0, type(uint128).max, 30_000), uint256(type(uint128).max) * 647_193);
    }

    /// @notice Exact neutral EV cross-check through the compiled payout path over
    /// every match/gold state. Matching and player gold masks are independent.
    function testExactJointEvFromProductionPayouts() public view {
        uint256 weightedPayout;
        for (uint16 matches; matches < 256; ++matches) {
            uint8 hitCount;
            for (uint8 axis; axis < 8; ++axis) {
                hitCount += uint8((matches >> axis) & 1);
            }
            for (uint8 goldMask; goldMask < 16; ++goldMask) {
                uint8 goldCount;
                uint32 p;
                uint32 r;
                for (uint8 q; q < 4; ++q) {
                    bool isGold = (goldMask >> q) & 1 == 1;
                    if (isGold) ++goldCount;
                    uint8 color = isGold ? 7 : 0;
                    p |= uint32(color << 3) << (q * 8);
                    uint8 resultSymbol = (matches >> q) & 1 == 1 ? 0 : 1;
                    uint8 resultColor = (matches >> (q + 4)) & 1 == 1 ? color : (color + 1) % 8;
                    r |= uint32(resultSymbol | (resultColor << 3)) << (q * 8);
                }
                (uint8 score, uint8 gold) = h.score(p, r, 0);
                uint256 weight = 7 ** uint256(8 - hitCount) * 7 ** uint256(4 - goldCount);
                weightedPayout += weight * h.payout(score, gold, 1, 1 ether, 30_000);
            }
        }
        // E0=3355443131/3355443200 including gold, times max activity=999/1000.
        assertEq(weightedPayout * 3_355_443_200 * 1000, uint256(8) ** 12 * 1 ether * 3_355_443_131 * 999);
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
            for (uint8 g; g < 5; ++g) {
                uint256 low = h.payout(s, g, 3, 1 ether, 0);
                uint256 high = h.payout(s, g, 3, 1 ether, 30_000);
                if (s < 6) assertEq(low, high, "low winning scores must not get activity bonus");
                else assertGt(high, low, "all four high tiers must receive bonus");
                assertLe(h.payout(s, g, 3, type(uint128).max, 65_535), uint256(type(uint128).max) * 5_485_508);
            }
        }
    }
}
