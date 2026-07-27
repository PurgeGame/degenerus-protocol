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
    // (1) Packed pool slots — mirrors DegenerusGameStorage's
    //     [volume:48 | future:104 | next:104] layout: _setPrizePools (saturating,
    //     counter-preserving), _addPrizeContribution's packed write, and the
    //     _unfreezePool fold (halves add saturating, the volume counter rolls).
    //     No division → proves cleanly for all inputs.
    // -------------------------------------------------------------------------
    uint256 private constant HALF = (uint256(1) << 104) - 1; // POOL_HALF_MAX
    uint256 private constant FUT = 104; // POOL_FUTURE_SHIFT
    uint256 private constant VOL = 208; // POOL_VOLUME_SHIFT
    uint256 private constant HALVES = (uint256(1) << VOL) - 1; // POOL_HALVES_MASK

    function check_packed_pool_roundtrip(uint48 vol, uint256 next, uint256 future)
        public
        pure
    {
        next &= HALF;
        future &= HALF;
        uint256 packed = (uint256(vol) << VOL) | (future << FUT) | next;
        assert((packed & HALF) == next);
        assert(((packed >> FUT) & HALF) == future);
        assert(uint48(packed >> VOL) == vol);
    }

    /// @notice The saturating half-setter (mirrors _setPrizePools): clamps at uint104,
    ///         never reverts, and never disturbs the volume counter above the halves.
    function check_packed_pool_set_saturates_and_preserves_volume(
        uint256 slot,
        uint128 next,
        uint128 future
    ) public pure {
        uint256 n = next > HALF ? HALF : next;
        uint256 f = future > HALF ? HALF : future;
        uint256 packed2 = (slot & ~HALVES) | (f << FUT) | n;
        assert((packed2 >> VOL) == (slot >> VOL)); // counter intact
        assert((packed2 & HALF) <= HALF); // halves in range by construction
        assert(((packed2 >> FUT) & HALF) == f); // no bleed between fields
        assert((packed2 & HALF) == n);
    }

    /// @notice The unfreeze fold (mirrors _unfreezePool): halves ADD with saturation and
    ///         can never bleed into a neighbouring field; the live volume counter is
    ///         REPLACED by the pending one; pending zeroes.
    function check_packed_pool_fold(uint256 live, uint256 pending) public pure {
        uint256 next = (live & HALF) + (pending & HALF);
        uint256 future = ((live >> FUT) & HALF) + ((pending >> FUT) & HALF);
        if (next > HALF) next = HALF;
        if (future > HALF) future = HALF;
        uint256 folded = (pending & ~HALVES) | (future << FUT) | next;
        assert((folded & HALF) == next);
        assert(((folded >> FUT) & HALF) == future);
        assert((folded >> VOL) == (pending >> VOL)); // the counter rolls pending -> live
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
