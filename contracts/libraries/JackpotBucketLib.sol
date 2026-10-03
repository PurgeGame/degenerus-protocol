// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {EntropyLib} from "./EntropyLib.sol";

/*
 * TERMS OF INTERACTION — submitting a transaction to this contract accepts them.
 *
 * THIS IS GAMBLING. Outcomes are decided by chance. You can lose everything you put in
 * simply by being unlucky. That is the software working exactly as intended. Do not
 * commit funds you are not prepared to lose entirely.
 *
 * The deployed bytecode is the entire agreement and the exclusive source of truth; any
 * comment, name, document or statement that disagrees with it is in error. It has been
 * audited but is not proven correct: it may contain defects the author did not find, and
 * by interacting with it you accept that risk in full.
 *
 * Any state transition the code permits is authorised — including one that exploits a
 * defect, and including sequences the author did not intend or foresee. A bug is not a
 * breach of these terms. There is no unwritten rule behind the code for a permitted
 * transaction to violate, and no unauthorised access to this contract.
 *
 * You bear all resulting loss, whether it follows from chance or from a defect. There is
 * no refund, no rollback and no privileged party able to restore a position.
 *
 * Provided AS IS, without warranty of any kind. Full text: TERMS.md
 */

/**
 * @title JackpotBucketLib
 * @notice Pure helper functions for jackpot bucket sizing and share calculations.
 * @dev All functions are internal and pure, so they get inlined by the compiler
 *      with no runtime call boundary. Extracted from DegenerusGameJackpotModule to reduce bytecode.
 */
library JackpotBucketLib {
    bytes32 internal constant TRAIT_BOARD_TAG = keccak256("degenerus.jackpot.trait-board");
    // -------------------------------------------------------------------------
    // Constants — Jackpot Bucket Scaling
    // -------------------------------------------------------------------------

    /// @dev Winner targets double at 4x, 16x, 64x, ... this budget.
    uint256 internal constant TARGET_ANCHOR_WEI = 10 ether;

    // -------------------------------------------------------------------------
    // Bucket Count Functions
    // -------------------------------------------------------------------------

    /// @dev 1, doubled at each fourfold step of `value` from 4 anchors (2 at 40 ETH, 4 at 160,
    ///      ...), at most `max`.
    function targetMultiplier(uint256 value, uint256 max) internal pure returns (uint256 m) {
        m = 1;
        for (uint256 step = 4 * TARGET_ANCHOR_WEI; m < max && value >= step; step *= 4) m *= 2;
    }

    /// @dev Target ETH winners for a live draw: base [32, 16, 4, 1] rotated by the bottom two
    ///      entropy bits (counts[i] = base[(i + offset) & 3]), so the 1 sits on soloBucketIndex.
    ///      Non-solo bases scale by targetMultiplier(pool, 32): 1,024 / 512 / 128 from
    ///      10,240 ETH. Zeroes for an empty pool.
    function ethWinnerTargets(uint256 pool, uint256 entropy) internal pure returns (uint16[4] memory counts) {
        if (pool == 0) return counts;
        uint256 m = targetMultiplier(pool, 32);
        uint256 offset = entropy & 3;
        for (uint256 i; i < 4; ++i) {
            // Bytes of 0x01041020, low first: base [32, 16, 4, 1].
            uint256 b = (uint256(0x01041020) >> (((i + offset) & 3) * 8)) & 0xff;
            counts[i] = uint16(b > 1 ? b * m : b);
        }
    }

    /// @dev Terminal winner counts: [152, 104, 48, 1] rotated like ethWinnerTargets.
    function terminalWinnerCounts(uint256 entropy) internal pure returns (uint16[4] memory counts) {
        uint256 offset = entropy & 3;
        for (uint256 i; i < 4; ++i) {
            // Bytes of 0x01306898, low first: [152, 104, 48, 1].
            counts[i] = uint16((uint256(0x01306898) >> (((i + offset) & 3) * 8)) & 0xff);
        }
    }

    /// @dev Total winner cap for a ticket leg worth `value` wei: three non-solo quadrants of
    ///      32 * targetMultiplier(value, 4) each: 96, 192 from 40 ETH, 384 from 160 ETH.
    function ticketWinnerCap(uint256 value) internal pure returns (uint256) {
        return 96 * targetMultiplier(value, 4);
    }

    // -------------------------------------------------------------------------
    // Share & Index Functions
    // -------------------------------------------------------------------------

    /// @dev Computes ETH shares for each bucket; the remainder goes to the solo bucket.
    ///      Empty non-remainder buckets (count==0) contribute their computed share to
    ///      `distributed` without receiving ETH, reducing the remainder bucket allocation.
    ///      The caller is responsible for refunding ethPool - paidEth to the source pool.
    function bucketShares(
        uint256 pool,
        uint16[4] memory shareBps,
        uint16[4] memory bucketCounts,
        uint8 remainderIdx
    ) internal pure returns (uint256[4] memory shares) {
        uint256 distributed;
        for (uint8 i; i < 4; ) {
            if (i != remainderIdx) {
                uint16 count = bucketCounts[i];
                uint256 share = (pool * shareBps[i]) / 10_000;
                if (count != 0) shares[i] = share;
                distributed += share;
            }
            unchecked {
                ++i;
            }
        }
        shares[remainderIdx] = pool - distributed;
    }

    /// @dev Returns the solo bucket index (the remainder bucket in bucketShares) from the entropy rotation.
    function soloBucketIndex(uint256 entropy) internal pure returns (uint8) {
        return uint8((uint256(3) - (entropy & 3)) & 3);
    }

    /// @dev Rotates share BPS based on offset and trait index.
    function rotatedShareBps(uint64 packed, uint8 offset, uint8 traitIdx) internal pure returns (uint16) {
        uint8 baseIndex = uint8((uint256(traitIdx) + uint256(offset) + 1) & 3);
        return uint16(packed >> (baseIndex * 16));
    }

    /// @dev Unpacks share BPS from packed uint64 with rotation offset for fairness.
    function shareBpsByBucket(uint64 packed, uint8 offset) internal pure returns (uint16[4] memory shares) {
        unchecked {
            for (uint8 i; i < 4; ++i) {
                shares[i] = rotatedShareBps(packed, offset, i);
            }
        }
    }

    // -------------------------------------------------------------------------
    // Trait Packing/Unpacking
    // -------------------------------------------------------------------------

    /// @dev Packs 4 trait IDs (0-255 each) into a single uint32.
    function packWinningTraits(uint8[4] memory traits) internal pure returns (uint32 packed) {
        packed = uint32(traits[0]) | (uint32(traits[1]) << 8) | (uint32(traits[2]) << 16) | (uint32(traits[3]) << 24);
    }

    /// @dev Unpacks a uint32 into 4 trait IDs.
    function unpackWinningTraits(uint32 packed) internal pure returns (uint8[4] memory traits) {
        traits[0] = uint8(packed);
        traits[1] = uint8(packed >> 8);
        traits[2] = uint8(packed >> 16);
        traits[3] = uint8(packed >> 24);
    }

    /// @dev Derives 4 random trait IDs from entropy. Each quadrant uses 6 bits (0-63 range).
    ///      Quadrant offsets: 0, 64, 128, 192.
    function getRandomTraits(uint256 rw) internal pure returns (uint8[4] memory w) {
        // Keep the shared board independent of the raw daily flip and redemption bits.
        rw = EntropyLib.hash2(rw, uint256(TRAIT_BOARD_TAG));
        w[0] = uint8(rw & 0x3F); // Quadrant 0: 0-63
        w[1] = 64 + uint8((rw >> 6) & 0x3F); // Quadrant 1: 64-127
        w[2] = 128 + uint8((rw >> 12) & 0x3F); // Quadrant 2: 128-191
        w[3] = 192 + uint8((rw >> 18) & 0x3F); // Quadrant 3: 192-255
    }

    // -------------------------------------------------------------------------
    // Jackpot Percentage & Ordering
    // -------------------------------------------------------------------------

    /// @dev Non-solo buckets by count, largest first (ties keep the lower index), then the solo.
    function bucketOrderSoloLast(uint16[4] memory counts, uint8 solo) internal pure returns (uint8[4] memory order) {
        uint256 n;
        for (uint8 i; i < 4; ++i) {
            if (i == solo) continue;
            uint256 j = n;
            while (j != 0 && counts[order[j - 1]] < counts[i]) {
                order[j] = order[j - 1];
                --j;
            }
            order[j] = i;
            ++n;
        }
        order[3] = solo;
    }

    /// @dev Return bucket order (largest count first; ties keep lower index).
    function bucketOrderLargestFirst(uint16[4] memory counts) internal pure returns (uint8[4] memory order) {
        unchecked {
            uint8 largestIdx;
            uint16 largestCount = counts[0];
            for (uint8 i = 1; i < 4; ++i) {
                if (counts[i] > largestCount) {
                    largestCount = counts[i];
                    largestIdx = i;
                }
            }
            order[0] = largestIdx;
            uint8 k = 1;
            for (uint8 i; i < 4; ++i) {
                if (i != largestIdx) {
                    order[k++] = i;
                }
            }
        }
    }
}
