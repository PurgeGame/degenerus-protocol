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

    /// @dev Reference packing of four quadrant traits from one 256-bit seed: 64 bits per quadrant
    ///      through `traitFromWord`, quadrant tag in bits 7-6, output [D:8][C:8][B:8][A:8].
    function packedTraitsFromSeed(uint256 rand) external pure returns (uint32) {
        uint8 traitA = DegenerusTraitUtils.traitFromWord(uint64(rand));
        uint8 traitB = DegenerusTraitUtils.traitFromWord(uint64(rand >> 64)) | 64;
        uint8 traitC = DegenerusTraitUtils.traitFromWord(uint64(rand >> 128)) | 128;
        uint8 traitD = DegenerusTraitUtils.traitFromWord(uint64(rand >> 192)) | 192;
        return uint32(traitA) | (uint32(traitB) << 8) | (uint32(traitC) << 16) | (uint32(traitD) << 24);
    }
}
