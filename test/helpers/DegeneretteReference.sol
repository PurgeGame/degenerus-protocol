// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;
import {RngTags} from "../../contracts/libraries/RngTags.sol";

/// @dev Independent reference for the public ticket-stream contract and score.
library DegeneretteReference {
    function randomHero(uint256 seed) internal pure returns (uint8 symbol) {
        uint256 roll = uint256(keccak256(abi.encode(RngTags.SPIN_HERO, seed)));
        symbol = uint8(roll % 24);
    }

    /// @dev Ordinary untagged lanes: [0][0][color][symbol] per byte, quadrant = byte position.
    function ordinary(uint256 seed) internal pure returns (uint32 t) {
        for (uint8 q; q < 4; ++q) {
            uint256 lane = seed >> (64 * q);
            t |= uint32((uint8(lane & 7) << 3) | uint8((lane >> 32) & 7)) << (8 * q);
        }
    }

    /// @dev House lanes: wild (0x40 | symbol) when the lane's bits 3..6 are all zero.
    function traits(uint256 seed) internal pure returns (uint32 t) {
        for (uint8 q; q < 4; ++q) {
            uint256 lane = seed >> (64 * q);
            uint8 sym = uint8((lane >> 32) & 7);
            uint8 b = (lane >> 3) & 0xF == 0 ? 0x40 | sym : (uint8(lane & 7) << 3) | sym;
            t |= uint32(b) << (8 * q);
        }
    }

    function drawWord(uint256 word, bool wwxrp) internal pure returns (uint256) {
        return word; // The action tag separates the shared reel; no preliminary rehash.
    }

    function player(uint256 word, uint32 index, uint8 symbol, uint8 spin, bool wwxrp) internal pure returns (uint32 t) {
        uint256 seed =
            uint256(keccak256(abi.encode(RngTags.BET_PLAYER, word, uint256(symbol), uint256(spin))));
        t = ordinary(uint256(keccak256(abi.encode(RngTags.SPIN_PLAYER, seed))));
        uint8 shift = (symbol >> 3) * 8;
        t = (t & ~(uint32(0xFF) << shift)) | (uint32(0x40 | (symbol & 7)) << shift);
    }

    function house(uint256 word, uint32 index, uint8 spin, bool wwxrp) internal pure returns (uint32) {
        uint256 seed = uint256(keccak256(abi.encode(RngTags.BET_HOUSE, word, uint256(spin))));
        return traits(seed);
    }

    /// @dev Symbol match 1; color: equal ordinary 1, one wild 1, two wilds 2. Counts house wilds.
    function score(uint32 p, uint32 r) internal pure returns (uint8 s, uint8 wilds) {
        for (uint8 q; q < 4; ++q) {
            uint8 a = uint8(p >> (8 * q));
            uint8 b = uint8(r >> (8 * q));
            bool aw = a & 0x40 != 0;
            bool bw = b & 0x40 != 0;
            if (a % 8 == b % 8) ++s;
            if (aw && bw) s += 2;
            else if (aw || bw) ++s;
            else if ((a / 8) % 8 == (b / 8) % 8) ++s;
            if (bw) ++wilds;
        }
    }
}
