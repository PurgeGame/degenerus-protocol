// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../helpers/DeployProtocol.sol";
import {VRFPathHandler} from "../handlers/VRFPathHandler.sol";

/// @title VRFPathInvariants -- Proves VRF path lifecycle invariants (TEST-01/02/03)
/// @notice Asserts lootboxRngIndex never skips/double-increments, stall-to-recovery
///         state transitions are valid, and gap backfill produces nonzero words for all
///         gap days.
contract VRFPathInvariants is DeployProtocol {
    VRFPathHandler public handler;

    function setUp() public {
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
    ///         paths (advanceGame daily request, requestLootboxRng mid-day request) —
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

    // ═══════════════════════════════════════════════════════════════════════
    // TEST-02: Stall-to-Recovery State Machine
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Stall-to-recovery transitions are valid: a coordinator swap preserves
    ///         the lock state, gap days have words after resume
    function invariant_stallRecoveryValid() public view {
        assertEq(
            handler.ghost_stateViolations(),
            0,
            "VRFPath: invalid stall-to-recovery state transition"
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

    /// @notice All gap days have nonzero rngWordForDay after recovery
    function invariant_allGapDaysBackfilled() public view {
        assertEq(
            handler.ghost_gapBackfillFailures(),
            0,
            "VRFPath: gap day missing rngWordForDay after recovery"
        );
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Canary
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Confirms handler is deployed and being exercised
    function invariant_handlerCanary() public view {
        assertTrue(
            address(handler.game()) != address(0),
            "VRFPath: handler game reference is zero"
        );
    }
}
