// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DeployProtocol} from "../helpers/DeployProtocol.sol";
import {VRFPathHandler} from "../handlers/VRFPathHandler.sol";

/// @title VRFPathInvariants -- Proves VRF path lifecycle invariants (TEST-01/02/03)
/// @notice Asserts lootboxRngIndex never skips/double-increments, stall-to-recovery
///         state transitions are valid, and gap backfill produces nonzero words for all
///         gap days.
contract VRFPathInvariants is DeployProtocol {
    VRFPathHandler public handler;

    function setUp() public virtual {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);

        handler = new VRFPathHandler(game, mockVRF, admin, 5);

        targetContract(address(handler));
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TEST-01: Lootbox RNG Index Lifecycle
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice lootboxRngIndex never moves during VRF fulfillment or a coordinator swap —
    ///         only fresh requests advance it
    function invariant_indexNeverSkips() public view {
        assertEq(
            handler.ghost_indexSkipViolations(),
            0,
            "VRFPath: lootboxRngIndex moved outside a fresh request"
        );
    }

    /// @notice lootboxRngIndex equals the sum of increments observed on the two request
    ///         paths (mineFlip daily request, mineFlip mid-day request) —
    ///         no other action allocates an index
    function invariant_indexMatchesExpected() public view {
        assertEq(
            handler.actualLootboxRngIndex(),
            handler.ghost_expectedIndex(),
            "VRFPath: lootboxRngIndex diverged from sanctioned request-path increments"
        );
    }

    /// @notice lootboxRngIndex never double-increments on a single request
    function invariant_noDoubleIncrement() public view {
        assertEq(
            handler.ghost_doubleIncrementCount(),
            0,
            "VRFPath: lootboxRngIndex double-incremented on single request"
        );
    }

    /// @notice The unworded trailing suffix never exceeds the single in-flight index:
    ///         every fresh allocation finds the previously pending index already worded
    function invariant_everyIndexHasWord() public view {
        assertEq(
            handler.ghost_orphanedIndices(),
            0,
            "VRFPath: fresh request allocated over an unworded pending index"
        );
    }


    /// @notice A coordinator swap never flips rngLocked in either direction: a daily
    ///         request in flight keeps the lock until the re-issued word lands (freeze
    ///         discipline); an idle or mid-day-only state stays unlocked.
    function invariant_swapPreservesLockState() public view {
        assertEq(
            handler.ghost_stateViolations(),
            0,
            "VRFPath: coordinator swap flipped rngLocked"
        );
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TEST-03: Gap Backfill
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice After a recovery the sealed day and the final gap day hold their words in the
    ///         two-day ring, and every gap day is settled (coinflip). Only the final gap day's
    ///         derived word is retained since 6d0e64b09/c729ecfc9.
    function invariant_allGapDaysBackfilled() public view {
        assertEq(
            handler.ghost_gapBackfillFailures(),
            0,
            "VRFPath: gap day missing rngWordForDay after recovery"
        );
    }


    /// @notice Runs after each call sequence: the detection sites above were actually exercised.
    ///         A sequence where the 0/1 buffer selector never flips would make every index invariant
    ///         pass vacuously. One sequence can legitimately make no request (time warps past the liveness
    ///         deadline before the first daily request routes it into the terminal flow), so every
    ///         coverage gate is pooled across the process (unique VP_ prefix). The six invariant
    ///         functions run in parallel and add into the same counters, so the thresholds count runs
    ///         from all of them: about 31% of runs evaluate a post-swap recovery and about 4% recover
    ///         across a real gap (seed 0xdeadbeef and default-profile measurements).
    function afterInvariant() public {
        uint256 runs = _acc("VP_RUNS", 1);
        uint256 advances = _acc("VP_advances", handler.ghost_advances());
        uint256 fulfillments = _acc("VP_fulfillments", handler.ghost_fulfillments());
        uint256 fresh = _acc("VP_fresh", handler.ghost_freshRequests());
        uint256 swaps = _acc("VP_swaps", handler.ghost_stallCount());
        uint256 purchases = _acc("VP_purchases", handler.ghost_purchases());
        uint256 recoveries = _acc("VP_recoveries", handler.ghost_recoveryCount());
        uint256 gaps = _acc("VP_gaps", handler.ghost_maxGapSize() > 0 ? 1 : 0);
        if (runs < 16) return;
        assertGt(advances, 0, "VRFPath: mineFlip never succeeded");
        assertGt(fulfillments, 0, "VRFPath: no VRF word was ever fulfilled");
        assertGt(fresh, 0, "VRFPath: no fresh index allocation ever committed - TEST-01 unexercised");
        assertGt(swaps, 0, "VRFPath: no coordinator swap ever succeeded - TEST-02 unexercised");
        assertGt(purchases, 0, "VRFPath: no purchase ever succeeded");
        if (runs < 192) return;
        assertGt(recoveries, 0, "VRFPath: no post-swap recovery was ever evaluated - TEST-03 unexercised");
        if (runs < 1024) return;
        assertGt(gaps, 0, "VRFPath: no recovery ever spanned a skipped day - gap backfill unexercised");
    }

    function _acc(string memory k, uint256 v) internal virtual returns (uint256 total) {
        total = vm.envOr(k, uint256(0)) + v;
        vm.setEnv(k, vm.toString(total));
    }
}
