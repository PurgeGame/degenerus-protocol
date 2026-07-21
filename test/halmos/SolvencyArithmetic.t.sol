// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import "forge-std/Test.sol";
import {JackpotBucketLib} from "../../contracts/libraries/JackpotBucketLib.sol";

/// @title Solvency-arithmetic symbolic proofs (pre-C4A hardening, track 3)
/// @notice Proves for ALL inputs the conservation/bound properties the audit agents
///         argued informally:
///         (1) the v61 packed-pool halves round-trip with no cross-half corruption;
///         (2) bucketShares never distributes MORE than the pool (no over-payment /
///             insolvency — a counterexample = ETH paid out > pool drawn from).
/// @dev halmos --contract SolvencyArithmeticTest --solver-timeout-assertion 120000
contract SolvencyArithmeticTest is Test {
    // -------------------------------------------------------------------------
    // (1) v61 packed-balance pool halves — mirrors DegenerusGameStorage
    //     _setPrizePools / _getPrizePools ([future:high128 | next:low128]).
    //     No division → proves cleanly for all 2^256 inputs.
    // -------------------------------------------------------------------------
    function check_packed_pool_roundtrip(uint128 next, uint128 future) public pure {
        uint256 packed = (uint256(future) << 128) | uint256(next);
        assert(uint128(packed) == next); // low half
        assert(uint128(packed >> 128) == future); // high half
    }

    /// @notice Overwriting one half never disturbs the other (no carry/borrow across 128).
    function check_packed_pool_no_cross_half(uint128 next, uint128 future, uint128 newNext)
        public
        pure
    {
        uint256 packed = (uint256(future) << 128) | uint256(next);
        uint256 packed2 = (packed & (uint256(type(uint128).max) << 128)) | uint256(newNext);
        assert(uint128(packed2 >> 128) == future); // high half intact
        assert(uint128(packed2) == newNext); // low half updated
    }

    // NOTE: there is no winner-total cap function to prove. The total is bounded
    //       structurally by the bucket geometry: base [25,15,8,1] scaled by at most
    //       DAILY_JACKPOT_SCALE_MAX_BPS (6.36x) gives 159+95+50+1 = 305, with the solo
    //       bucket never scaled. The gas suite pins that ceiling directly.

    // -------------------------------------------------------------------------
    // (2) bucketShares: sum of distributed shares never exceeds the pool.
    //     (The leftover pool - sum is refunded to the source pool by the caller;
    //      the solvency-critical direction is the upper bound — never pay out more
    //      than was drawn.) A counterexample = over-payment = insolvency.
    // -------------------------------------------------------------------------
    function check_bucketShares_no_overpay(
        uint256 pool,
        uint16 s0,
        uint16 s1,
        uint16 s2,
        uint16 s3,
        uint16 c0,
        uint16 c1,
        uint16 c2,
        uint16 c3,
        uint8 remainderIdx,
        uint256 unit
    ) public pure {
        if (pool > 1e30) return; // realistic ETH range
        if (uint256(s0) + s1 + s2 + s3 > 10_000) return; // shareBps within 100% (as the real splits are)
        if (remainderIdx > 3) return;
        if (unit > 1e18) return; // realistic unit; avoids unit*count overflow noise
        uint16[4] memory shareBps = [s0, s1, s2, s3];
        uint16[4] memory counts = [c0, c1, c2, c3];
        uint256[4] memory shares =
            JackpotBucketLib.bucketShares(pool, shareBps, counts, remainderIdx, unit);
        uint256 sum = shares[0] + shares[1] + shares[2] + shares[3];
        assert(sum <= pool);
    }
}
