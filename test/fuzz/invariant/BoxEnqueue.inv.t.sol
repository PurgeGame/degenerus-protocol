// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployProtocol} from "../helpers/DeployProtocol.sol";
import {BoxCreationHandler} from "../handlers/BoxCreationHandler.sol";
import {DegenerusGame} from "../../../contracts/DegenerusGame.sol";

/// @dev Read-only view overlay etched onto the live game to inspect internal box-queue state. Reuses the
///      one-shot's BoxQueueViewer shape (PassBoxAutoOpenEnqueue.t.sol) and extends it with a presaleBoxEth
///      base reader so the invariant can distinguish a persisted presale box (base != 0) from a resolved one.
///      The viewer is a DegenerusGame subclass: etching type().runtimeCode (no constructor) gives the reads
///      access to the live internal boxPlayers / lootboxEth / presaleBoxEth maps without a storage change;
///      the real code is restored after the read.
contract BoxQueueViewer is DegenerusGame {
    function lrIndexView() external view returns (uint48) {
        return uint48(_lrRead(LR_INDEX_SHIFT, LR_INDEX_MASK));
    }

    /// @notice Walk boxPlayers[index] for `who`. TRUE iff the box is enqueued for the permissionless
    ///         openBoxes() auto-opener (the WHALE-01 property: a persisted box must be present here).
    function boxPlayersContains(uint48 index, address who) external view returns (bool) {
        address[] storage q = boxPlayers[index];
        for (uint256 i; i < q.length; ++i) {
            if (q[i] == who) return true;
        }
        return false;
    }

    /// @notice The persisted lootbox amount (the [232:amount] field). base != 0 => a persisted, not-yet-opened
    ///         box; base == 0 => already resolved (drained on open) and correctly absent from the queue.
    function lootboxAmountFor(uint48 index, address who) external view returns (uint256) {
        return lootboxEth[index][who] & ((1 << 232) - 1);
    }

    /// @notice The persisted presale-box applied-ETH base (the low 96-bit field; the closing flag at bit 255
    ///         and soldBefore at bits 96:191 are masked off). base != 0 => a persisted presale box.
    function presaleBoxBaseFor(uint48 index, address who) external view returns (uint256) {
        return presaleBoxEth[index][who] & PRESALE_BOX_AMOUNT_MASK;
    }
}

/// @title BoxEnqueue — FUZZ-04 (BOX-ENQUEUE) canonical always-on enqueue invariant.
///
/// @notice Promotes the WHALE-01 one-shot (PassBoxAutoOpenEnqueue.t.sol — one whale bundle, one assertion)
///         into a fuzzed invariant over the FULL box-creating action-space: mint-with-lootbox, the
///         whale / lazy / deity pass bundles, and the coin-presale box (and, where reachable, afking-cover).
///         Case (b) PROMOTE — it REUSES the one-shot's BoxQueueViewer etch overlay + boxPlayersContains read
///         pattern and GENERALIZES the single assertion to every tracked (index, owner) the campaign creates.
///
///         THE PROPERTY (invariant_everyPersistedBoxIsEnqueued). Across any fuzzed sequence of box-creating
///         actions, every persisted box — a lootboxEth or presaleBoxEth record with base != 0 for an active
///         index — is present in boxPlayers[index] until it is opened, never held un-enqueued. A box owner is
///         the ONLY party who can open a box (manual openLootBox is operator-gated); a persisted-but-unenqueued
///         box lets the owner hold it closed and time the open to a favorable live level/boon, defeating the
///         lootbox-resolution-timing by-design ruling for that box class (the WHALE-01 finding). The invariant
///         distinguishes persisted-but-unenqueued (a BUG) from already-resolved (base == 0, drained on open
///         and correctly absent from / no longer owed in the queue) by checking ONLY base != 0 entries.
///
///         NON-VACUITY. The property is meaningful only if the campaign actually creates boxes across MULTIPLE
///         creation paths. afterInvariant gates acceptance on the per-path ghost counters: a campaign that
///         created 0 boxes (every creation reverted) — under which the for-each loop is empty and the
///         invariant trivially green — FAILS. A focused non-vacuity test additionally drives the creation
///         actions directly and asserts boxes are created across >= 2 distinct paths, so a path that silently
///         skipped its enqueue could not hide behind a vacuous green.
///
///         FALSIFIABILITY. A focused test seeds the exact WHALE-01 bug shape — a persisted lootboxEth record
///         (base != 0) NOT pushed into boxPlayers[index] — via the handler's debugSeedUnenqueuedBox seam, then
///         asserts the invariant's underlying check (base != 0 AND boxPlayersContains == false) registers the
///         break. Restoring the slot returns the check to green. A passing assertion here proves the wired
///         invariant is genuinely falsifiable, not vacuously true.
///
/// @dev Test-only. ZERO contracts/*.sol mutation. The viewer is etched (type().runtimeCode, no constructor)
///      to inspect the internal box maps, then the real code is restored after every read.
contract BoxEnqueue is DeployProtocol {
    BoxCreationHandler public handler;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        // Back the box-creating buys with solvent funds so a creation that DOES run does not revert on the
        // contract's balance (the enqueue property is about queue membership, not solvency).
        vm.deal(address(game), 5_000_000 ether);
        mockVRF.fundSubscription(1, 100e18);

        handler = new BoxCreationHandler(game, deityPass, mockVRF, 5);
        targetContract(address(handler));

        // The falsifiability seams (debugSeedUnenqueuedBox / debugClearBox) are TEST-ONLY hooks used solely by
        // the focused falsifiability test — they vm.store an un-enqueued box record to prove the invariant can
        // fail. Exclude them from the fuzz campaign so the always-on invariant only ever sees boxes created
        // through the REAL entrypoints (which always enqueue at c4d48008); otherwise the fuzzer could seed a
        // persisted-but-unenqueued record and either spuriously trip the invariant or, by clearing it, mask the
        // real action mix. The campaign must reflect genuine contract behaviour, not a seeded bug shape.
        bytes4[] memory excluded = new bytes4[](2);
        excluded[0] = BoxCreationHandler.debugSeedUnenqueuedBox.selector;
        excluded[1] = BoxCreationHandler.debugClearBox.selector;
        excludeSelector(StdInvariant.FuzzSelector({addr: address(handler), selectors: excluded}));
    }

    // =========================================================================
    // INVARIANT: every persisted box (base != 0) for a tracked (index, owner) is enqueued
    // =========================================================================

    /// @notice THE PROPERTY. For each (index, owner) the campaign created, read its persisted base (the
    ///         lootbox amount OR the presale-box applied-ETH base) via the etched viewer; if base != 0
    ///         (persisted, not yet opened) assert it is present in boxPlayers[index]. Opened boxes (base == 0)
    ///         are skipped — they are correctly resolved and no longer owed in the queue. The viewer is etched
    ///         once, all reads are batched under it, and the real code is restored at the end so the campaign's
    ///         next call sees the unmodified game.
    function invariant_everyPersistedBoxIsEnqueued() public {
        BoxCreationHandler.BoxRef[] memory refs = handler.trackedBoxes();

        bytes memory realCode = address(game).code;
        vm.etch(address(game), type(BoxQueueViewer).runtimeCode);
        BoxQueueViewer viewer = BoxQueueViewer(payable(address(game)));

        for (uint256 i; i < refs.length; i++) {
            uint48 idx = refs[i].index;
            address who = refs[i].owner;

            // A box is persisted if EITHER its lootbox amount OR its presale-box base is non-zero. base == 0 on
            // both => resolved (drained on open) => correctly absent from the queue => skip (no false positive).
            uint256 lootboxBase = viewer.lootboxAmountFor(idx, who);
            uint256 presaleBase = viewer.presaleBoxBaseFor(idx, who);
            if (lootboxBase == 0 && presaleBase == 0) continue;

            bool enqueued = viewer.boxPlayersContains(idx, who);
            // Restore the real code BEFORE the assertion so a revert here cannot leave the viewer etched.
            if (!enqueued) {
                vm.etch(address(game), realCode);
                assertTrue(
                    enqueued,
                    "WHALE-01: every persisted box (base != 0) must be enqueued in boxPlayers[index] for the permissionless auto-open"
                );
            }
        }

        vm.etch(address(game), realCode);
    }

    // =========================================================================
    // NON-VACUITY: the campaign created boxes across >= 2 distinct paths
    // =========================================================================

    /// @notice afterInvariant runs once at the END of the campaign. The enqueue property is only meaningful if
    ///         boxes were actually created across multiple paths — otherwise the for-each loop is empty and the
    ///         invariant is trivially green. Gating on >= 2 distinct paths (pathsExercised) makes a
    ///         "green because nothing was created" pass impossible: if fewer than two creation paths fired, this
    ///         campaign FAILS.
    function afterInvariant() public view {
        assertGe(
            handler.pathsExercised(),
            2,
            "NON-VACUITY: boxes must be created across >= 2 distinct paths (else the enqueue invariant is vacuous)"
        );
        assertGt(
            handler.totalBoxesCreated(),
            0,
            "NON-VACUITY: the campaign must create > 0 boxes"
        );
    }

    // =========================================================================
    // NON-VACUITY (focused): driving the creation actions directly creates boxes across >= 2 paths
    // =========================================================================

    /// @notice Drive the handler's creation actions directly (deterministic seeds spanning the actor pool) and
    ///         assert boxes are created across >= 2 distinct paths. This proves the action surface is reachable
    ///         at the fixture level independent of the fuzzer's sequencing — a path that silently skipped its
    ///         enqueue would still be tracked here and so could be caught by the invariant.
    function test_boxesCreatedAcrossPaths_nonVacuous() public {
        // mint-with-lootbox across the actors (both DirectEth and Combined kinds).
        for (uint256 a; a < handler.actorCount(); a++) {
            handler.mintWithLootbox(a, 0.5 ether, uint8(a));
        }
        // pass bundles: whale + lazy + deity across the actors.
        for (uint256 a; a < handler.actorCount(); a++) {
            handler.buyWhaleBundle(a, 1);
            handler.buyLazyPass(a);
            handler.buyDeityPass(a, a);
        }

        assertGt(handler.totalBoxesCreated(), 0, "fixture: at least one box was created");
        assertGe(
            handler.pathsExercised(),
            2,
            "fixture: boxes created across >= 2 distinct paths (mint-lootbox + a pass path)"
        );
    }

    // =========================================================================
    // FALSIFIABILITY: a seeded persisted-but-unenqueued box breaks the invariant's check
    // =========================================================================

    /// @notice The WHALE-01 bug shape the net catches: a box-creating path persists a lootboxEth record
    ///         (base != 0) but DROPS the boxPlayers[index] enqueue. We simulate that bug via the handler's
    ///         debugSeedUnenqueuedBox seam (a field-isolated vm.store of a lootboxEth amount with NO enqueue),
    ///         then assert the invariant's underlying condition — base != 0 AND boxPlayersContains == false —
    ///         now holds (the break is registered). Clearing the seeded slot returns the check to green. If the
    ///         invariant were vacuous (never reading the seeded entry, or comparing against a mirror that drifts
    ///         with it), this seeded break would NOT register — so a passing assertion proves the wired property
    ///         is genuinely falsifiable.
    function test_invariantIsFalsifiable_persistedButUnenqueued() public {
        address victim = handler.actors(0);

        bytes memory realCode = address(game).code;
        vm.etch(address(game), type(BoxQueueViewer).runtimeCode);
        BoxQueueViewer viewer = BoxQueueViewer(payable(address(game)));
        uint48 idx = viewer.lrIndexView();
        // Pre: nothing persisted/enqueued for the victim at this index.
        assertEq(viewer.lootboxAmountFor(idx, victim), 0, "pre: no persisted box for the victim");
        assertFalse(viewer.boxPlayersContains(idx, victim), "pre: victim not in the queue");
        vm.etch(address(game), realCode);

        // Seed the bug: a persisted lootboxEth amount (base != 0) WITHOUT pushing to boxPlayers[index].
        uint256 injected = 3 ether;
        handler.debugSeedUnenqueuedBox(idx, victim, injected);

        // The invariant's underlying check must now register the break.
        vm.etch(address(game), realCode); // ensure real code (handler seam may have left it set)
        vm.etch(address(game), type(BoxQueueViewer).runtimeCode);
        viewer = BoxQueueViewer(payable(address(game)));
        uint256 base = viewer.lootboxAmountFor(idx, victim);
        bool enqueued = viewer.boxPlayersContains(idx, victim);
        vm.etch(address(game), realCode);

        assertEq(base, injected, "the seeded persisted base is non-zero");
        assertFalse(
            enqueued,
            "FALSIFIABILITY: a persisted box (base != 0) NOT in boxPlayers is exactly the WHALE-01 break the invariant catches"
        );
        assertTrue(base != 0 && !enqueued, "FALSIFIABILITY: base != 0 && !enqueued => the invariant would FAIL");

        // Clear the seeded slot — the check returns to green (proves the break was the injection).
        handler.debugClearBox(idx, victim);
        vm.etch(address(game), type(BoxQueueViewer).runtimeCode);
        viewer = BoxQueueViewer(payable(address(game)));
        assertEq(viewer.lootboxAmountFor(idx, victim), 0, "post: seeded box cleared, base back to 0");
        vm.etch(address(game), realCode);
    }
}
