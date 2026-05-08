// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DegenerusTraitUtils} from "../DegenerusTraitUtils.sol";

/// @title TraitUtilsTester
/// @notice Test helper that exposes DegenerusTraitUtils internal-pure functions as
///         external-pure passthroughs so Hardhat JS tests can invoke them directly.
/// @dev Deploy in tests to verify color tier boundaries, bit-slice composition, and
///      packed-trait byte layout without round-tripping through any consumer module.
contract TraitUtilsTester {
    function weightedColorBucket(uint32 rnd) external pure returns (uint8) {
        return DegenerusTraitUtils.weightedColorBucket(rnd);
    }

    function traitFromWord(uint64 rnd) external pure returns (uint8) {
        return DegenerusTraitUtils.traitFromWord(rnd);
    }

    function packedTraitsFromSeed(uint256 rand) external pure returns (uint32) {
        return DegenerusTraitUtils.packedTraitsFromSeed(rand);
    }
}
