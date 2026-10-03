// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/// @dev Eight independent lane-column rotations across four packed owner words.
///      All moves are in memory. `positions` carries one original-position byte
///      per player, so reveals can be reassembled after the groups change.
library PackedTicketShuffle {
    function shuffle(uint256[4] memory words, uint256 positions, uint256 entropy)
        internal pure returns (uint256 mixedPositions)
    {
        assembly ("memory-safe") {
            let mask0 := 0
            let mask1 := 0
            let mask2 := 0
            let mask3 := 0
            for { let lane := 0 } lt(lane, 8) { lane := add(lane, 1) } {
                let rotation := and(shr(mul(lane, 2), entropy), 3)
                let mask := shl(mul(lane, 32), 0xffffffff)
                switch rotation
                case 0 { mask0 := or(mask0, mask) }
                case 1 { mask1 := or(mask1, mask) }
                case 2 { mask2 := or(mask2, mask) }
                case 3 { mask3 := or(mask3, mask) }
                let shift := mul(rotation, 64)
                let column := shl(mul(lane, 8), 0xff00000000000000ff00000000000000ff00000000000000ff)
                mixedPositions := or(mixedPositions,
                    and(or(shr(shift, positions), shl(sub(256, shift), positions)), column))
            }
            let w0 := mload(words)
            let w1 := mload(add(words, 32))
            let w2 := mload(add(words, 64))
            let w3 := mload(add(words, 96))
            mstore(words, or(or(and(w0, mask0), and(w1, mask1)), or(and(w2, mask2), and(w3, mask3))))
            mstore(add(words, 32), or(or(and(w1, mask0), and(w2, mask1)), or(and(w3, mask2), and(w0, mask3))))
            mstore(add(words, 64), or(or(and(w2, mask0), and(w3, mask1)), or(and(w0, mask2), and(w1, mask3))))
            mstore(add(words, 96), or(or(and(w3, mask0), and(w0, mask1)), or(and(w1, mask2), and(w2, mask3))))
        }
    }
}
