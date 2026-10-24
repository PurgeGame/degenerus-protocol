// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

/// @dev Independent specification oracle: explicit launch table value and cumulative weights.
///      Production derives its normalization from the shared table instead.
library DegenesisBoonReference {
    uint256 internal constant EXPECTED = 282_051_820_728_291_316;
    uint256 internal constant SCALE = 1_000_000;

    function chance(uint256 amount) internal pure returns (uint256 result) {
        uint256 budget = amount / 5;
        if (budget > 1 ether) budget = 1 ether;
        result = budget * SCALE / EXPECTED;
        if (result > 3 * SCALE) result = 3 * SCALE;
    }

    function root(uint256 word, uint256 cohort, uint256 index) internal pure returns (uint256) {
        return uint256(keccak256(abi.encode(uint256(113), word, cohort, index)));
    }

    function extra(uint256 seed) internal pure returns (uint256) {
        return uint256(keccak256(abi.encode(uint256(114), seed))) % SCALE;
    }

    function count(uint256 amount, uint256 seed) internal pure returns (uint256 n) {
        uint256 ppm = chance(amount);
        n = ppm / SCALE;
        if (extra(seed) < ppm % SCALE) ++n;
    }

    function selected(uint256 amount, uint256 seed) internal pure returns (uint24 packed) {
        uint256 n = count(amount, seed);
        for (uint256 i; i < n; ++i) {
            uint256 roll = uint256(keccak256(abi.encode(uint256(115), seed, i))) % 2856;
            packed |= uint24(boonType(roll)) << (8 * i);
        }
    }

    function boonType(uint256 roll) internal pure returns (uint8) {
        uint16[38] memory ends = [
            uint16(200),
            240,
            248,
            448,
            478,
            486,
            886,
            966,
            982,
            1022,
            1030,
            1032,
            1060,
            1070,
            1072,
            1100,
            1110,
            1112,
            1212,
            1242,
            1246,
            1446,
            1448,
            1478,
            1486,
            1488,
            1688,
            1738,
            1748,
            1948,
            1998,
            2008,
            2208,
            2408,
            2608,
            2808,
            2848,
            2856
        ];
        uint8[38] memory types_ = [
            uint8(1),
            2,
            3,
            5,
            6,
            22,
            7,
            8,
            9,
            13,
            14,
            15,
            16,
            23,
            24,
            25,
            26,
            27,
            17,
            18,
            19,
            4,
            28,
            29,
            30,
            31,
            32,
            33,
            34,
            35,
            36,
            37,
            38,
            39,
            40,
            41,
            42,
            43
        ];
        for (uint256 i; i < ends.length; ++i) {
            if (roll < ends[i]) return types_[i];
        }
        revert("roll outside table");
    }

    function packedCount(uint24 packed) internal pure returns (uint256 n) {
        while (packed != 0) {
            require(uint8(packed) != 0, "noncontiguous draws");
            ++n;
            packed >>= 8;
        }
    }
}
