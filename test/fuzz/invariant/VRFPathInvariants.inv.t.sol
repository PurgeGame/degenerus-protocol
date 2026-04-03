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

    /// @notice lootboxRngIndex never skips a value across any arbitrary sequence
    function invariant_indexNeverSkips() public view {
        assertEq(
            handler.ghost_indexSkipViolations(),
            0,
            "VRFPath: lootboxRngIndex skipped a value"
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

    /// @notice Every unlocked lootboxRngIndex has a nonzero word
    function invariant_everyIndexHasWord() public view {
        assertEq(
            handler.ghost_orphanedIndices(),
            0,
            "VRFPath: lootboxRngIndex has orphaned index with no word"
        );
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TEST-02: Stall-to-Recovery State Machine
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Stall-to-recovery transitions are valid: rngLocked false after swap,
    ///         gap days have words after resume
    function invariant_stallRecoveryValid() public view {
        assertEq(
            handler.ghost_stateViolations(),
            0,
            "VRFPath: invalid stall-to-recovery state transition"
        );
    }

    /// @notice rngLocked is always false immediately after coordinator swap
    function invariant_rngUnlockedAfterSwap() public view {
        assertEq(
            handler.ghost_stateViolations(),
            0,
            "VRFPath: rngLocked true after coordinator swap"
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
