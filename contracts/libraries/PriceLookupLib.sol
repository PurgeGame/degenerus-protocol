// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/// @title PriceLookupLib
/// @notice Shared price tier calculations for level-based pricing
/// @dev Implements an intro tier followed by a 100-level cycle used across game modules
library PriceLookupLib {
    /// @notice Get price for a specific level
    /// @dev Price tiers follow a 100-level cycle with discounted intro prices:
    ///      Cycle (repeating every 100 levels):
    ///      - Levels x00 (100, 200, etc.): 0.24 ETH (milestone)
    ///      - Levels x01-x29: 0.04 ETH
    ///      - Levels x30-x59: 0.08 ETH
    ///      - Levels x60-x89: 0.12 ETH
    ///      - Levels x90-x99: 0.16 ETH
    ///      First cycle overrides (levels 0-9 use intro pricing):
    ///      - Levels 0-4: 0.01 ETH (instead of 0.04 ETH)
    ///      - Levels 5-9: 0.02 ETH (instead of 0.04 ETH)
    /// @param targetLevel Level to query price for
    /// @return Price in wei
    function priceForLevel(uint24 targetLevel) internal pure returns (uint256) {
        // Intro tiers (levels 0-9)
        if (targetLevel < 5) return 0.01 ether;
        if (targetLevel < 10) return 0.02 ether;

        // Levels 10-99 (first full cycle without intro tiers)
        if (targetLevel < 30) return 0.04 ether;
        if (targetLevel < 60) return 0.08 ether;
        if (targetLevel < 90) return 0.12 ether;
        if (targetLevel < 100) return 0.16 ether;

        uint256 cycleOffset = targetLevel % 100;

        // Price tiers within the repeating 100-level cycle (levels 100+)
        if (cycleOffset == 0) {
            return 0.24 ether; // Milestone levels: 100, 200, 300...
        } else if (cycleOffset < 30) {
            return 0.04 ether; // Early cycle: x01-x29
        } else if (cycleOffset < 60) {
            return 0.08 ether; // Mid cycle: x30-x59
        } else if (cycleOffset < 90) {
            return 0.12 ether; // Late cycle: x60-x89
        } else {
            return 0.16 ether; // Final cycle: x90-x99
        }
    }
}
