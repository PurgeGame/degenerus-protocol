// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {EntropyLib} from "./EntropyLib.sol";

/// @notice Gold Dice 6 is the unique natural entry at each level.
library GoldSixLib {
    uint8 internal constant TRAIT = 253;
    uint256 private constant REPLACEMENT_TAG = uint256(keccak256("GOLD_SIX_REPLACEMENT_V1"));
    uint256 private constant DAILY_TAG = uint256(keccak256("GOLD_SIX_DAILY_V1"));

    /// @dev All seven other gold dice, with equal weight apart from negligible modulo bias.
    function replacement(uint256 seed) internal pure returns (uint8) {
        uint8 symbol = uint8(EntropyLib.hash2(seed, REPLACEMENT_TAG) % 7);
        return 248 + symbol + (symbol >= 5 ? 1 : 0);
    }

    /// @dev Keep a natural daily gold-six roll 1/6 of the time. Separate domains
    ///      prevent the keep decision from biasing the replacement symbol.
    function daily(uint8 trait, uint256 word) internal pure returns (uint8) {
        if (trait != TRAIT || EntropyLib.hash2(word, DAILY_TAG) % 6 == 0) return trait;
        return replacement(word);
    }
}
