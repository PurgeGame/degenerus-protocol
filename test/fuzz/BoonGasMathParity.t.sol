// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {DegenerusGameBoonModule} from "../../contracts/modules/DegenerusGameBoonModule.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";

contract BoonGasMathHarness is DegenerusGameBoonModule {
    function optimizedAverage(uint24 currentLevel) external pure returns (uint256) {
        return _boonAvgMaxValue(currentLevel);
    }

    function optimizedLazyValue(uint24 passLevel) external pure returns (uint256) {
        return _lazyPassPriceForLevel(passLevel);
    }
}

/// @notice Exact-equivalence locks for the closed-form boon normalization and packed lazy-price lookup.
contract BoonGasMathParity is Test {
    uint256 private constant PRICE_COIN_UNIT = 1000 ether;
    BoonGasMathHarness private harness;

    function setUp() public {
        harness = new BoonGasMathHarness();
    }

    function testLazyLookupMatchesTenPriceSumAcrossIntroAndTwoCycles() public view {
        for (uint24 start; start < 210; ++start) {
            assertEq(harness.optimizedLazyValue(start), _legacyLazyValue(start), "lazy lookup drift");
        }
    }

    function testLazyLookupPreservesUint24WrapBoundary() public view {
        for (uint24 delta; delta < 9; ++delta) {
            uint24 start = type(uint24).max - delta;
            assertEq(harness.optimizedLazyValue(start), _legacyLazyValue(start), "lazy wrap drift");
        }
    }

    function testAverageMatchesLegacyTableAcrossIntroAndTwoCycles() public view {
        for (uint24 currentLevel = 1; currentLevel < 210; ++currentLevel) {
            assertEq(harness.optimizedAverage(currentLevel), _legacyAverage(currentLevel), "average drift");
        }
    }

    function testFuzzAverageMatchesLegacyTable(uint24 currentLevel) public view {
        currentLevel = uint24(bound(currentLevel, 1, type(uint24).max - 1));
        assertEq(harness.optimizedAverage(currentLevel), _legacyAverage(currentLevel), "fuzz average drift");
    }

    function _legacyLazyValue(uint24 passLevel) private pure returns (uint256 total) {
        for (uint24 i; i < 10;) {
            unchecked {
                total += PriceLookupLib.priceForLevel(passLevel + i);
                ++i;
            }
        }
    }

    function _flipValue(uint256 flipAmount, uint256 priceWei) private pure returns (uint256) {
        return (flipAmount * priceWei) / PRICE_COIN_UNIT;
    }

    function _legacyAverage(uint24 currentLevel) private pure returns (uint256) {
        uint256 priceWei = PriceLookupLib.priceForLevel(currentLevel - 1);
        uint256 lazyPassValue = _legacyLazyValue(currentLevel + 1);
        uint256 weighted;

        // Coinflip deposits: 5/10/25% of a 100k-FLIP cap, weights 200/40/8.
        weighted += 200 * _flipValue(5000 ether, priceWei);
        weighted += 40 * _flipValue(10_000 ether, priceWei);
        weighted += 8 * _flipValue(25_000 ether, priceWei);

        // Lootbox and purchase boosts: 5/15/25% of a 10-ETH cap.
        weighted += 200 * 0.5 ether + 30 * 1.5 ether + 8 * 2.5 ether;
        weighted += 400 * 0.5 ether + 80 * 1.5 ether + 16 * 2.5 ether;

        // Decimator: 10/25/50% of a 50k-FLIP cap.
        weighted += 40 * _flipValue(5000 ether, priceWei);
        weighted += 8 * _flipValue(12_500 ether, priceWei);
        weighted += 2 * _flipValue(25_000 ether, priceWei);

        // Whale discounts at 4 ETH and deity discounts at the fixed 160-ETH nominal price.
        weighted += 28 * 0.4 ether + 10 * 0.8 ether + 2 * 1.4 ether;
        weighted += 28 * 16 ether + 10 * 32 ether + 2 * 56 ether;

        // Whale pass plus lazy-pass 10/25/50% discounts.
        weighted += 2 * 4.5 ether;
        weighted += 30 * ((lazyPassValue * 1000) / 10_000);
        weighted += 8 * ((lazyPassValue * 2500) / 10_000);
        weighted += 2 * ((lazyPassValue * 5000) / 10_000);

        // Degenerette ETH and FLIP stake boons. WWXRP/activity/quest carry zero value.
        weighted += 200 * 0.4 ether + 50 * 0.8 ether + 10 * 1.2 ether;
        weighted += 200 * _flipValue(4000 ether, priceWei);
        weighted += 50 * _flipValue(8000 ether, priceWei);
        weighted += 10 * _flipValue(12_000 ether, priceWei);

        // Craps bankroll-payout boons: 5/10/25% of a 60k-FLIP payout base, weights 200/40/8.
        weighted += 200 * _flipValue(3000 ether, priceWei);
        weighted += 40 * _flipValue(6000 ether, priceWei);
        weighted += 8 * _flipValue(15_000 ether, priceWei);

        return weighted / 2856;
    }
}
