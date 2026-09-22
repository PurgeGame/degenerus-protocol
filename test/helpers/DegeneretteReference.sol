// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/// @dev Independent reference for the public ticket-stream contract and score.
library DegeneretteReference {
    function traits(uint256 seed) internal pure returns (uint32 t) {
        for (uint8 q; q < 4; ++q) {
            uint256 lane = seed >> (64 * q);
            t |= uint32((q << 6) | (uint8(lane & 7) << 3) | uint8((lane >> 32) & 7)) << (8 * q);
        }
    }

    function drawWord(uint256 word, bool wwxrp) internal pure returns (uint256) {
        return wwxrp ? uint256(keccak256(abi.encode(word, uint256(0x575758525044726177)))) : word;
    }

    function player(uint256 word, uint32 index, uint8 symbol, uint8 spin, bool wwxrp) internal pure returns (uint32 t) {
        uint256 seed =
            uint256(keccak256(abi.encode(drawWord(word, wwxrp), uint256(index), uint256(symbol), uint256(spin))));
        t = traits(uint256(keccak256(abi.encode(seed, uint256(0x446567656e506c61796572)))));
        uint8 shift = (symbol >> 3) * 8;
        t = (t & ~(uint32(7) << shift)) | (uint32(symbol & 7) << shift);
    }

    function house(uint256 word, uint32 index, uint8 spin, bool wwxrp) internal pure returns (uint32) {
        word = drawWord(word, wwxrp);
        uint256 seed = spin == 0
            ? uint256(keccak256(abi.encodePacked(word, index, bytes1(0x51))))
            : uint256(keccak256(abi.encodePacked(word, index, spin, bytes1(0x51))));
        return traits(seed);
    }

    function score(uint32 p, uint32 r, uint8 hero) internal pure returns (uint8 s, uint8 gold) {
        for (uint8 q; q < 4; ++q) {
            uint8 a = uint8(p >> (8 * q));
            uint8 b = uint8(r >> (8 * q));
            if (a % 8 == b % 8) s += q == hero ? 2 : 1;
            if ((a / 8) % 8 == (b / 8) % 8) {
                ++s;
                if ((a / 8) % 8 == 7) ++gold;
            }
        }
    }
}
