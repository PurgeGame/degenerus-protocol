// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/**
 * @title JackpotBucketLib
 * @notice Pure helper functions for jackpot bucket sizing and share calculations.
 * @dev All functions are internal and pure, so they get inlined by the compiler
 *      with no runtime call boundary. Extracted from DegenerusGameJackpotModule to reduce bytecode.
 */
library JackpotBucketLib {
    // -------------------------------------------------------------------------
    // Constants — Jackpot Bucket Scaling
    // -------------------------------------------------------------------------

    /// @dev Minimum pool size before scaling kicks in.
    uint256 internal constant JACKPOT_SCALE_MIN_WEI = 10 ether;

    /// @dev First scale target (2x) by this pool size.
    uint256 internal constant JACKPOT_SCALE_FIRST_WEI = 50 ether;

    /// @dev Pool size at which the caller's maxScaleBps is reached; cap beyond.
    ///      Both production callers pass 63_600 bps (6.36x).
    uint256 internal constant JACKPOT_SCALE_SECOND_WEI = 200 ether;

    /// @dev Scale values in basis points.
    uint16 internal constant JACKPOT_SCALE_BASE_BPS = 10_000;
    uint16 internal constant JACKPOT_SCALE_FIRST_BPS = 20_000;

    // -------------------------------------------------------------------------
    // Bucket Count Functions
    // -------------------------------------------------------------------------

    /// @dev Computes base winner counts for each of the 4 trait buckets.
    ///      Base counts [25, 15, 8, 1] are rotated by entropy for fairness.
    /// @param entropy Used for rotation offset (bottom 2 bits).
    /// @return counts Winner counts for each bucket [bucket0, bucket1, bucket2, bucket3].
    function traitBucketCounts(uint256 entropy) internal pure returns (uint16[4] memory counts) {
        uint16[4] memory base;
        base[0] = 25; // Large bucket
        base[1] = 15; // Mid bucket
        base[2] = 8; // Small bucket
        base[3] = 1; // Solo bucket (receives the 60% share via rotation)

        // Rotate bucket assignments based on entropy for fairness across traits.
        uint8 offset = uint8(entropy & 3);
        for (uint8 i; i < 4; ) {
            counts[i] = base[(i + offset) & 3];
            unchecked {
                ++i;
            }
        }
    }

    /// @dev Scales base bucket counts by jackpot size (excluding solo).
    ///      1x under 10 ETH, linearly to 2x by 50 ETH, linearly to maxScaleBps by 200 ETH, then flat.
    ///      The solo bucket is never scaled, so the total is bounded by the base geometry times
    ///      maxScaleBps: at the production 6.36x ceiling [25,15,8,1] -> [159,95,50,1] = 305 winners.
    function scaleTraitBucketCounts(
        uint16[4] memory baseCounts,
        uint256 ethPool,
        uint32 maxScaleBps
    ) internal pure returns (uint16[4] memory counts) {
        counts = baseCounts;

        if (ethPool < JACKPOT_SCALE_MIN_WEI) return counts;

        uint256 scaleBps;
        if (ethPool < JACKPOT_SCALE_FIRST_WEI) {
            uint256 range = JACKPOT_SCALE_FIRST_WEI - JACKPOT_SCALE_MIN_WEI;
            uint256 progress = ethPool - JACKPOT_SCALE_MIN_WEI;
            scaleBps = JACKPOT_SCALE_BASE_BPS + (progress * (JACKPOT_SCALE_FIRST_BPS - JACKPOT_SCALE_BASE_BPS)) / range;
        } else if (ethPool < JACKPOT_SCALE_SECOND_WEI) {
            uint256 range = JACKPOT_SCALE_SECOND_WEI - JACKPOT_SCALE_FIRST_WEI;
            uint256 progress = ethPool - JACKPOT_SCALE_FIRST_WEI;
            scaleBps = JACKPOT_SCALE_FIRST_BPS + (progress * (uint256(maxScaleBps) - JACKPOT_SCALE_FIRST_BPS)) / range;
        } else {
            scaleBps = maxScaleBps;
        }

        if (scaleBps != JACKPOT_SCALE_BASE_BPS) {
            for (uint8 i; i < 4; ) {
                uint16 baseCount = counts[i];
                if (baseCount > 1) {
                    uint256 scaled = (uint256(baseCount) * scaleBps) / 10_000;
                    if (scaled < baseCount) scaled = baseCount;
                    if (scaled > type(uint16).max) scaled = type(uint16).max;
                    counts[i] = uint16(scaled);
                }
                unchecked {
                    ++i;
                }
            }
        }

        return counts;
    }

    /// @dev Computes base + scaled bucket counts for a given pool; returns zeroes when pool is empty.
    function bucketCountsForPool(
        uint256 ethPool,
        uint256 entropy,
        uint32 maxScaleBps
    ) internal pure returns (uint16[4] memory bucketCounts) {
        if (ethPool == 0) return bucketCounts;
        uint16[4] memory baseCounts = traitBucketCounts(entropy);
        return scaleTraitBucketCounts(baseCounts, ethPool, maxScaleBps);
    }

    /// @dev Sums the bucket counts.
    function sumBucketCounts(uint16[4] memory counts) internal pure returns (uint256 total) {
        total = uint256(counts[0]) + counts[1] + counts[2] + counts[3];
    }

    // -------------------------------------------------------------------------
    // Share & Index Functions
    // -------------------------------------------------------------------------

    /// @dev Computes ETH/COIN shares for each bucket.
    ///      Round non-solo buckets to unit * winnerCount; remainder goes to the override bucket.
    ///      Empty non-remainder buckets (count==0) contribute their computed share to
    ///      `distributed` without receiving ETH, reducing the remainder bucket allocation.
    ///      The caller is responsible for refunding ethPool - paidEth to the source pool.
    function bucketShares(
        uint256 pool,
        uint16[4] memory shareBps,
        uint16[4] memory bucketCounts,
        uint8 remainderIdx,
        uint256 unit
    ) internal pure returns (uint256[4] memory shares) {
        uint256 distributed;
        for (uint8 i; i < 4; ) {
            if (i != remainderIdx) {
                uint16 count = bucketCounts[i];
                uint256 share = (pool * shareBps[i]) / 10_000;
                if (count != 0) {
                    if (unit != 0) {
                        uint256 unitBucket = unit * count;
                        share = (share / unitBucket) * unitBucket;
                    }
                    shares[i] = share;
                }
                distributed += share;
            }
            unchecked {
                ++i;
            }
        }
        shares[remainderIdx] = pool - distributed;
    }

    /// @dev Returns the solo bucket index (receives 60% share) based on entropy rotation.
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
        w[0] = uint8(rw & 0x3F); // Quadrant 0: 0-63
        w[1] = 64 + uint8((rw >> 6) & 0x3F); // Quadrant 1: 64-127
        w[2] = 128 + uint8((rw >> 12) & 0x3F); // Quadrant 2: 128-191
        w[3] = 192 + uint8((rw >> 18) & 0x3F); // Quadrant 3: 192-255
    }

    // -------------------------------------------------------------------------
    // Jackpot Percentage & Ordering
    // -------------------------------------------------------------------------

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
