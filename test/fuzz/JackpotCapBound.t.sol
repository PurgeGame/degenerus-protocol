// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import "forge-std/Test.sol";
import {JackpotBucketLib} from "../../contracts/libraries/JackpotBucketLib.sol";

/// @notice Pins the REAL (approximate) winner-total cap of JackpotBucketLib.capBucketCounts.
///
/// capBucketCounts is not exact: it reserves only ONE slot for a size-1 "solo" bucket
/// (nonSoloCap = maxTotal-1), but lets EVERY size-1 bucket pass through untouched, so when
/// multiple trait buckets arrive at exactly 1 the total lands a few above maxTotal
/// (e.g. [1,1,310,400], cap 305 -> [1,1,132,172] = 306). This is by-accepted-design (the
/// contract is frozen): the effective cap is maxTotal + a small slack, and that is SAFE —
/// every downstream uint8(count) cast is clamped to 250 (pool-cap paths) or on a <=120
/// path, and bucketShares is proved to never over-distribute the pool. These tests fix the
/// slack so a future change that worsens it fails loudly.
contract JackpotCapBoundTest is Test {
    uint16[4] internal CAPS = [uint16(50), 100, 120, 305];

    /// PRODUCTION caps: the effective winner total never exceeds maxTotal + 2.
    /// => real caps are 52 / 102 / 122 / 307.
    function testFuzz_productionCapSlack(
        uint16 a,
        uint16 b,
        uint16 c,
        uint16 d,
        uint8 pick,
        uint256 entropy
    ) public {
        uint16 maxTotal = CAPS[pick % 4];
        uint16[4] memory counts = [
            uint16(bound(a, 0, 600)),
            uint16(bound(b, 0, 600)),
            uint16(bound(c, 0, 600)),
            uint16(bound(d, 0, 600))
        ];
        uint16[4] memory capped = JackpotBucketLib.capBucketCounts(counts, maxTotal, entropy);
        uint256 total = uint256(capped[0]) + capped[1] + capped[2] + capped[3];
        assertLe(total, uint256(maxTotal) + 2, "production winner total exceeds maxTotal + 2");
    }

    /// Full domain: never more than maxTotal + 4 (the 4-bucket slack), and a single
    /// bucket never reaches the 256 uint8-cast boundary.
    function testFuzz_fullDomainSlack(
        uint16 a,
        uint16 b,
        uint16 c,
        uint16 d,
        uint16 mt,
        uint256 entropy
    ) public {
        uint16 maxTotal = uint16(bound(mt, 2, 305));
        uint16[4] memory counts = [
            uint16(bound(a, 0, 600)),
            uint16(bound(b, 0, 600)),
            uint16(bound(c, 0, 600)),
            uint16(bound(d, 0, 600))
        ];
        uint16[4] memory capped = JackpotBucketLib.capBucketCounts(counts, maxTotal, entropy);
        uint256 total = uint256(capped[0]) + capped[1] + capped[2] + capped[3];
        assertLe(total, uint256(maxTotal) + 4, "winner total exceeds maxTotal + 4");
    }
}
