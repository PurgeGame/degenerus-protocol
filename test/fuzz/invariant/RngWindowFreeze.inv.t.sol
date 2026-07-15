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
///         THE MID-DAY LOOTBOX WINDOW (second window shape). requestLootboxRng opens a lootbox-only
///         VRF window that sets NEITHER rngLockedFlag NOR prizePoolFrozen — the in-flight marker is
///         rngRequestTime != 0 with rngLocked() == false. Its pending consumption (the mid-day
///         rawFulfillRandomWords branch + the next advance's frozen ticket batch) reads its own
///         enumerated set, checked by the tryMidDay* actions under the same isolation discipline:
///           (5)  LR_INDEX cursor            — slot 34 low 48   : the landing index (-1) of the pending word.
///           (6)  lootboxRngWordByIndex[N-1] — slot 35 leaf     : the reserved landing leaf.
///           (7)  LR_MID_DAY flag            — slot 34 bits 224 : routes the frozen ticket batch.
///           (8)  ticketWriteSlot            — slot 0 byte 26   : the buffer selector frozen at request.
///           (9)  vrfRequestId               — slot 4           : the fulfillment request-match gate.
///           (10) rngRequestTime             — slot 0 bytes 6-11: the in-flight marker (reroll guard).
///           (11) rngLockedFlag              — slot 0 byte 19   : the fulfillment branch selector.
///
///         NON-VACUITY. The freeze assertion is meaningful only if the campaign actually opens the window
///         and fires in-window actions. afterInvariant + focused non-vacuity tests gate acceptance on
///         ghost_windowsOpened / ghost_inWindowActions AND their mid-day counterparts all > 0 (a "passes
///         because nothing happened" green is impossible for either window shape).
///
/// @dev Test-only: ZERO contracts/*.sol mutation. The only vm.store is the standard slot-34 lootbox-index
///      seed inside the handler (mirroring RngFreezeAndRemovalProofs.setUp) so an active index exists to
///      snapshot, plus the seeded-violation vm.store in the falsifiability test (reverted in-test).
contract RngWindowFreeze is DeployProtocol {
    RngWindowFreezeHandler public handler;

    uint256 private constant LOOTBOX_RNG_PACKED_SLOT = 33; // post Stage B pack: was 35
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

        // requestLootboxRng gates on the VRF subscription holding >= 40 LINK; DeployProtocol does
        // not fund the mock subscription (subId 1 — the Admin constructor's createSubscription).
        // Fund it here so the mid-day window driver can actually open the lootbox window.
        mockVRF.fundSubscription(1, 100e18);

        // The falsifiability seams (debugSeed*MutationAndCheck) are TEST-ONLY hooks for the focused
        // falsifiability tests — they deliberately seed freeze violations. Exclude them from the fuzz
        // campaign so the always-on invariant only ever sees the real player-action surface (the seams are
        // also counter-neutral as defence-in-depth, but excluding them keeps the campaign's action mix honest).
        bytes4[] memory excluded = new bytes4[](2);
        excluded[0] = RngWindowFreezeHandler.debugSeedInWindowMutationAndCheck.selector;
        excluded[1] = RngWindowFreezeHandler.debugSeedMidDayMutationAndCheck.selector;
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
        handler.ghost_midDayWindowsOpened();
        handler.ghost_midDayInWindowActions();
        handler.calls_openMidDayWindow();
        handler.calls_midDayPlacement();
        handler.calls_midDayPurchase();
        handler.calls_midDayOpenBoxes();
        handler.calls_closeMidDayWindow();
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
        assertGt(
            handler.ghost_midDayWindowsOpened(),
            0,
            "NON-VACUITY: the campaign must open the MID-DAY lootbox window > 0 times (else the mid-day freeze property is vacuous)"
        );
        assertGt(
            handler.ghost_midDayInWindowActions(),
            0,
            "NON-VACUITY: the campaign must attempt a mid-day in-window player action > 0 times (else the mid-day freeze property is vacuous)"
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

    // =========================================================================
    // MID-DAY LOOTBOX WINDOW: focused non-vacuity + falsifiability
    // =========================================================================

    /// @notice Directly drives the handler through one MID-DAY cycle — open (requestLootboxRng in
    ///         flight, daily lock NOT held) → the three in-window player actions → close (the
    ///         mid-day fulfillment lands the word directly) — and asserts the mid-day non-vacuity
    ///         counters move while the freeze property holds. Proves the mid-day window machinery
    ///         works deterministically, so the always-on invariant's mid-day coverage is not
    ///         fuzzer-luck-dependent.
    function test_midDayWindowIsExercised_nonVacuous() public {
        handler.openMidDayWindow(0);
        assertGt(
            handler.ghost_midDayWindowsOpened(),
            0,
            "non-vacuity: the mid-day driver actually opened the lootbox VRF window"
        );
        assertFalse(game.rngLocked(), "the mid-day window holds NO daily lock (that is its defining shape)");

        handler.tryMidDayPlacement(0, 1 ether, 54321);
        handler.tryMidDayPurchase(0, 800, 0.1 ether);
        handler.tryMidDayOpenBoxes(0, 50);

        assertGt(
            handler.ghost_midDayInWindowActions(),
            0,
            "non-vacuity: ghost_midDayInWindowActions > 0 after firing mid-day in-window actions"
        );
        assertEq(
            handler.ghost_frozenSlotMutations(),
            0,
            "real mid-day in-window actions froze every enumerated mid-day slot"
        );

        // Close: the mid-day fulfillment finalizes directly (no advanceGame needed).
        handler.closeMidDayWindow(7);
    }

    /// @notice FALSIFIABILITY (mid-day). Opens the mid-day window, seeds a mutation of the RESERVED
    ///         lootbox landing leaf — the pre-fulfillment word-steering the property forbids — and
    ///         asserts the detector observes it, counter-neutrally.
    function test_invariantCatchesSeededMidDayMutation() public {
        handler.openMidDayWindow(0);
        require(handler.ghost_midDayWindowsOpened() > 0, "precondition: mid-day window opened");

        uint256 propBefore = handler.ghost_frozenSlotMutations();

        bool detected = handler.debugSeedMidDayMutationAndCheck();

        assertTrue(
            detected,
            "FALSIFIABILITY: the mid-day freeze detector must catch a seeded mutation of the reserved lootbox leaf"
        );
        assertEq(
            handler.ghost_frozenSlotMutations(),
            propBefore,
            "the seeded mid-day falsification is counter-neutral: it never pollutes the live property counter"
        );
    }
}
