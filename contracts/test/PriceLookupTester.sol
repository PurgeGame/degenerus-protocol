// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {PriceLookupLib} from "../libraries/PriceLookupLib.sol";

/// @title PriceLookupTester
/// @notice Test helper that exposes PriceLookupLib.priceForLevel as a public function.
/// @dev Deploy in tests to verify price tier boundaries without advancing game state.
contract PriceLookupTester {
    function priceForLevel(uint24 level) external pure returns (uint256) {
        return PriceLookupLib.priceForLevel(level);
    }

    /// @notice Compute the sum of prices for 10 consecutive levels starting at startLevel.
    /// @dev Mirrors the lazy pass cost calculation in WhaleModule._lazyPassCost().
    function lazyPassCost(uint24 startLevel) external pure returns (uint256 total) {
        for (uint24 i = 0; i < 10; ) {
            total += PriceLookupLib.priceForLevel(startLevel + i);
            unchecked {
                ++i;
            }
        }
    }
}
