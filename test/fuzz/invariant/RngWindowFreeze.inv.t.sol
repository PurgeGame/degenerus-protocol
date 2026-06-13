// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployProtocol} from "../helpers/DeployProtocol.sol";
import {RngWindowFreezeHandler} from "../handlers/RngWindowFreezeHandler.sol";

/// @title RngWindowFreeze — FUZZ-02 canonical RNG-FREEZE durable invariant.
///
/// @notice Promotes the scattered freeze SCENARIO proofs (RngFreezeAndRemovalProofs placement/resolve
///         guards, V56FreezeSolvency stamped-day open, the RngIndexDrainOrdering ghost binding) into ONE
///         always-on fuzzed property: across any fuzzed action sequence, no player-controllable action
///         taken WHILE THE VRF WINDOW IS OPEN (rngLocked() == true) mutates a storage slot the pending
///         consumption reads. This is the v45 north-star as a continuous net — trace BACKWARD from each
///         consumer, ENUMERATE every in-window SLOAD (not only the VRF-derived seeds; the non-VRF cursors
///         read alongside the word are a distinct bug class per
///         [[feedback_rng_window_storage_read_freshness]]), and assert byte-equality across an isolated
///         in-window player action. Case (b) PROMOTE/EXTEND — it does NOT re-prove the scenario guards; it
///         asserts the GENERAL property over the player-controllable in-window action space.
///
///         THE ENUMERATED IN-WINDOW SLOAD SET (the RngWindowFreezeHandler backward trace):
///           (1) rngWordByDay[currentDay]     — slot 10 : the VRF-DERIVED day word.
///           (2) lootboxRngWordByIndex[index] — slot 35 : the VRF-DERIVED lootbox word.
///           (3) lootboxRngPacked cursor      — slot 34 low 48 bits : the NON-VRF index read alongside
///                                                       the word.
///           (4) dailyIdx                     — slot 0, byte 3 : the NON-VRF day cursor the consumption
///                                                       keys against (included precisely because it is
///                                                       not a seed — a non-VRF in-window read is its own
///                                                       bug class).
///
///         NON-VACUITY. The freeze assertion is meaningful only if the campaign actually opens the window
///         and fires in-window actions. afterInvariant + a focused non-vacuity test gate acceptance on
///         ghost_windowsOpened > 0 AND ghost_inWindowActions > 0 (a "passes because nothing happened"
///         green is impossible).
///
/// @dev Test-only: ZERO contracts/*.sol mutation. The only vm.store is the standard slot-34 lootbox-index
///      seed inside the handler (mirroring RngFreezeAndRemovalProofs.setUp) so an active index exists to
///      snapshot, plus the seeded-violation vm.store in the falsifiability test (reverted in-test).
contract RngWindowFreeze is DeployProtocol {
    RngWindowFreezeHandler public handler;

    uint256 private constant LOOTBOX_RNG_PACKED_SLOT = 34; // post Stage B pack: was 35
    uint256 private constant LR_INDEX_MASK = 0xFFFFFFFFFFFF;
    uint256 private constant RNG_WORD_BY_DAY_SLOT = 10;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        // Fund the game so any in-window purchase / placement that DOES run has solvent backing (the freeze
        // property is about state mutation, not solvency — keep the buy paths from reverting on funds).
        vm.deal(address(game), 5_000_000 ether);

        handler = new RngWindowFreezeHandler(game, mockVRF, 5);
        targetContract(address(handler));

        // The falsifiability seam (debugSeedInWindowMutationAndCheck) is a TEST-ONLY hook for the focused
        // falsifiability test — it deliberately seeds a freeze violation. Exclude it from the fuzz campaign
        // so the always-on invariant only ever sees the real player-action surface (the seam is also
        // counter-neutral as defence-in-depth, but excluding it keeps the campaign's action mix honest).
        bytes4[] memory excluded = new bytes4[](1);
        excluded[0] = RngWindowFreezeHandler.debugSeedInWindowMutationAndCheck.selector;
        excludeSelector(StdInvariant.FuzzSelector({addr: address(handler), selectors: excluded}));
    }

    // =========================================================================
    // INVARIANT: every enumerated in-window SLOAD is frozen against a player action
    // =========================================================================

    /// @notice THE PROPERTY. No player-controllable action taken inside the VRF window mutated, in
    ///         isolation (no advanceGame between snapshot and re-check), any enumerated consumed slot. The
    ///         handler increments ghost_frozenSlotMutations only for player-attributable changes — the
    ///         advanceGame heartbeat (the v45-exempt mutator) is never measured against the property.
    function invariant_inWindowSloadsFrozen() public view {
        assertEq(
            handler.ghost_frozenSlotMutations(),
            0,
            "RNG-FREEZE: a player action inside the VRF window mutated an enumerated consumed slot"
        );
    }

    // =========================================================================
    // SURVEILLANCE: emit the freeze counters at end-of-run (mirrors RngIndexDrainOrdering)
    // =========================================================================

    /// @notice Non-asserting read of the ghost counters so forge surfaces the freeze metrics
    ///         (windows-opened / in-window-actions / per-action coverage) alongside the property. Mirrors
    ///         RngIndexDrainOrdering's branch-coverage-surveillance — coverage is diagnostic, not a gate
    ///         (the non-vacuity GATE lives in afterInvariant + the focused test below).
    function invariant_freezeWindowExercised() public view {
        handler.ghost_windowsOpened();
        handler.ghost_inWindowActions();
        handler.calls_openWindow();
        handler.calls_inWindowPlacement();
        handler.calls_inWindowPurchase();
        handler.calls_inWindowOpenBoxes();
        handler.calls_closeWindow();
    }

    // =========================================================================
    // NON-VACUITY GATE: the campaign actually opened the window and fired in-window actions
    // =========================================================================

    /// @notice afterInvariant runs once at the END of the campaign. The freeze property is only meaningful
    ///         if the fuzzer actually drove the window open AND attempted in-window player actions across
    ///         the 256/128 run — otherwise invariant_inWindowSloadsFrozen would hold vacuously (no window,
    ///         no action). Asserting both counters > 0 here makes a "passes because nothing happened" green
    ///         impossible: if the campaign never opened the window or never fired an in-window action, it
    ///         FAILS.
    function afterInvariant() public view {
        assertGt(
            handler.ghost_windowsOpened(),
            0,
            "NON-VACUITY: the campaign must open the VRF window > 0 times (else the freeze property is vacuous)"
        );
        assertGt(
            handler.ghost_inWindowActions(),
            0,
            "NON-VACUITY: the campaign must attempt an in-window player action > 0 times (else the freeze property is vacuous)"
        );
    }

    // =========================================================================
    // FOCUSED non-vacuity: directly prove one open-window -> in-window-action -> close-window cycle
    // =========================================================================

    /// @notice Directly drives the handler through one open → in-window-action → close cycle and asserts the
    ///         non-vacuity counters move — proving the campaign's window-open + in-window-action machinery
    ///         works deterministically (independent of fuzzer luck), so the always-on invariant is not
    ///         vacuously green. Also re-confirms the freeze property holds across the real (un-seeded)
    ///         in-window actions: ghost_frozenSlotMutations stays 0.
    function test_freezeWindowIsExercised_nonVacuous() public {
        handler.openWindow(0);
        assertTrue(game.rngLocked(), "the open-window driver actually opened the VRF window");
        assertGt(handler.ghost_windowsOpened(), 0, "non-vacuity: ghost_windowsOpened > 0 after openWindow");

        // Fire each in-window player action against the real (un-seeded) contract — none must move an
        // enumerated consumed slot in isolation.
        handler.tryInWindowPlacement(0, 1 ether, 12345);
        handler.tryInWindowPurchase(0, 800, 0.1 ether);
        handler.tryInWindowOpenBoxes(0, 50);

        assertGt(
            handler.ghost_inWindowActions(),
            0,
            "non-vacuity: ghost_inWindowActions > 0 after firing in-window actions"
        );
        assertEq(
            handler.ghost_frozenSlotMutations(),
            0,
            "real in-window actions froze every enumerated consumed slot (property holds outside the seeded falsification)"
        );

        // Close the window (the exempt heartbeat completion) — clears the lock.
        handler.closeWindow(7);
        assertFalse(game.rngLocked(), "closeWindow fulfilled the pending VRF and cleared the lock");
    }

    // =========================================================================
    // RED (falsifiability): the invariant's detector MUST catch a seeded in-window mutation
    // =========================================================================

    /// @notice FALSIFIABILITY. Drives the handler open → seeds an in-window mutation of an enumerated
    ///         consumed slot (rngWordByDay[currentDay]) between the handler's snapshot and its isolation
    ///         re-check, and asserts the detector FIRES (ghost_frozenSlotMutations increments). If the
    ///         detector did not register the seeded break, the freeze invariant would be unfalsifiable —
    ///         vacuously green. A passing assertion here proves the wired property genuinely catches a
    ///         freeze violation.
    /// @dev RED→GREEN: this is authored RED (asserting a detection the handler does not yet expose a hook
    ///      for), then made GREEN by the handler exposing a seam to inject + re-check a violation in
    ///      isolation.
    function test_invariantCatchesSeededInWindowMutation() public {
        handler.openWindow(0);
        require(game.rngLocked(), "precondition: window opened");

        // The campaign's live property counter must NOT move (the seam is counter-neutral); the detection is
        // reported via the return value, so a deliberately-seeded falsification never pollutes the invariant.
        uint256 propBefore = handler.ghost_frozenSlotMutations();

        // Inject an in-window mutation of an enumerated consumed slot against the openWindow snapshot; the
        // SAME isolation comparison the live in-window actions use must observe the delta.
        bool detected = handler.debugSeedInWindowMutationAndCheck();

        assertTrue(
            detected,
            "FALSIFIABILITY: the freeze detector must catch a seeded in-window mutation of an enumerated consumed slot"
        );
        assertEq(
            handler.ghost_frozenSlotMutations(),
            propBefore,
            "the seeded falsification is counter-neutral: it never pollutes the live property counter"
        );
    }
}
