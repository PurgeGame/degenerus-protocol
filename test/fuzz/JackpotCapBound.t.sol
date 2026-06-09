// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import "forge-std/Test.sol";
import {JackpotBucketLib} from "../../contracts/libraries/JackpotBucketLib.sol";

/// @notice Characterizes JackpotBucketLib.capBucketCounts's winner-total bound.
///
/// FINDING (pre-C4A hardening, track 3 — Halmos surfaced, fuzz adjudicated):
/// capBucketCounts is NOT exact — its trim + min-1 rounding can leave the capped
/// winner total a small amount ABOVE maxTotal (e.g. 306 at the real 305 cap). The
/// code (and a prior audit pass) assumed total <= maxTotal exactly; it does not.
///
/// MATERIALITY = none (defended downstream), recorded as a hardening item:
///  - The overflow only occurs on the bucketCountsForPoolCap paths (daily-ETH 305 /
///    lootbox 100 / coin 50), whose counts feed _processBucket/_resolveTraitWinners,
///    which CLAMP totalCount to MAX_BUCKET_WINNERS(250) before every uint8 cast
///    (JackpotModule:1154/:1163, :1234/:1247) — so the overflow can never truncate.
///  - The one UNGUARDED uint8(count) cast (JackpotModule:881, _distributeTicketJackpot)
///    is only reached with maxWinners in {100,120} via _computeBucketCounts, which
///    bounds each bucket <= maxWinners < 256 and never calls capBucketCounts.
///  - bucketShares conservation (no over-payment) is independently proved for all
///    inputs in test/halmos/SolvencyArithmetic.t.sol, so the few extra winners only
///    split the pool into smaller shares — solvency holds.
///
/// This test pins the overflow magnitude so a future change that worsens it (toward
/// the 256 truncation boundary or a large gas blowup) fails loudly.
contract JackpotCapBoundTest is Test {
    /// The capped total never exceeds maxTotal by more than the 4-bucket min-1 slack.
    function testFuzz_capOverflowBounded(
        uint16 a,
        uint16 b,
        uint16 c,
        uint16 d,
        uint16 mt,
        uint256 entropy
    ) public {
        uint16 maxTotal = uint16(bound(mt, 2, 305));
        uint16[4] memory counts = [
            uint16(bound(a, 0, 400)),
            uint16(bound(b, 0, 400)),
            uint16(bound(c, 0, 400)),
            uint16(bound(d, 0, 400))
        ];
        uint16[4] memory capped = JackpotBucketLib.capBucketCounts(counts, maxTotal, entropy);
        uint256 total = uint256(capped[0]) + capped[1] + capped[2] + capped[3];
        // Bounded imprecision: never more than 4 over the cap (one per bucket).
        assertLe(total, uint256(maxTotal) + 4, "capBucketCounts overflow exceeds the 4-bucket slack");
    }
}
