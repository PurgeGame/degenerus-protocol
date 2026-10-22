// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployProtocol} from "../helpers/DeployProtocol.sol";
import {BoxCreationHandler} from "../handlers/BoxCreationHandler.sol";

/// @title BoxEnqueue — FUZZ-04 (BOX-ENQUEUE) canonical always-on box-queue invariant.
///
/// @notice Every box purchase — mint-with-lootbox, and the whale / lazy / deity pass bundles —
///         appends ONE complete entry to the write buffer's box queue, which the
///         permissionless mineFlip human-box stage settles in FIFO order from `boxCursor` once the
///         buffer is sealed and its word published. A box that never reached the queue could be held
///         closed by its owner and opened at a favorable live level/boon (the WHALE-01 finding); an
///         entry rewritten after its append, or settled out of order, would let a later purchase
///         change or pre-empt an earlier one.
///
///         THE PROPERTIES.
///           (1) invariant_everyCreationAppendsOneMatchingEntry: each successful creating call grew
///               the write buffer by exactly one entry, at the prior count, whose wallet ID, level,
///               box counts/size match the action and whose
///               purchase event names that (buffer, position). One entry per purchase, however many
///               boxes it holds; a ticket-only purchase appends nothing.
///           (2) invariant_entriesAreNeverRewritten: every tracked entry whose cohort still lives
///               (its buffer has not reopened for a new cohort) still holds the word appended.
///           (3) invariant_readCursorObeysFifo: the read cursor never passes the read count,
///               completion implies the cursor reached it, and across every observed engine call the
///               cursor never moves backwards and every queued-entry resolution lands in FIFO order
///               inside [cursor, readCount), behind the stored cursor, to the entry's own wallet.
///
///         NON-VACUITY. afterInvariant gates acceptance on boxes created across >= 2 distinct paths;
///         a focused test drives the creation actions directly.
///
///         FALSIFIABILITY. A focused test rewrites a tracked live entry in place through the
///         handler's debugRewriteEntry seam and asserts property (2)'s check registers the break,
///         then restores it.
///
/// @dev Test-only. ZERO contracts/*.sol mutation. Entries are read through the queue's storage
///      location (RecyclingState.boxEntry / boxCount); slots come from GameSlots.
contract BoxEnqueue is DeployProtocol {
    BoxCreationHandler public handler;

    function setUp() public virtual {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        // Back the box-creating buys with solvent funds so a creation that DOES run does not revert on
        // the contract's balance (the queue properties are about entries, not solvency).
        vm.deal(address(game), 5_000_000 ether);
        mockVRF.fundSubscription(1, 100e18);

        handler = new BoxCreationHandler(game, deityPass, mockVRF, 5);
        targetContract(address(handler));

        // The falsifiability seam is a TEST-ONLY hook for the focused falsifiability test; the
        // campaign must only ever see entries created through the REAL entrypoints.
        bytes4[] memory excluded = new bytes4[](1);
        excluded[0] = BoxCreationHandler.debugRewriteEntry.selector;
        excludeSelector(StdInvariant.FuzzSelector({addr: address(handler), selectors: excluded}));
    }

    // =========================================================================
    // INVARIANTS
    // =========================================================================

    function invariant_everyCreationAppendsOneMatchingEntry() public view {
        assertEq(handler.appendViolations(), 0, handler.lastAppendViolation());
    }

    function invariant_entriesAreNeverRewritten() public view {
        assertEq(handler.rewrittenEntries(), 0, "an appended entry was rewritten while its cohort lives");
    }

    function invariant_readCursorObeysFifo() public view {
        BoxCreationHandler.ReadState memory s = handler.readState();
        assertLe(s.cursor, s.readCount, "the read cursor never passes the read count");
        if (s.complete) assertEq(s.cursor, s.readCount, "completion implies every read entry settled");
        assertEq(handler.fifoViolations(), 0, handler.lastFifoViolation());
    }

    // =========================================================================
    // NON-VACUITY: the campaign created boxes across >= 2 distinct paths
    // =========================================================================

    function afterInvariant() public {
        assertGe(
            handler.pathsExercised(),
            2,
            "NON-VACUITY: boxes must be created across >= 2 distinct paths (else the queue invariants are vacuous)"
        );
        assertGt(handler.totalBoxesCreated(), 0, "NON-VACUITY: the campaign must create > 0 boxes");
        // The FIFO property only bites when the engine settles queued entries under observation. Measured
        // minima over 771 default-profile runs: 50 observed resolutions and 52 boxes per run.
        assertGe(handler.resolutionsObserved(), 10, "NON-VACUITY: the engine settled (almost) no queued entry");
        assertGe(handler.totalBoxesCreated(), 10, "NON-VACUITY: the campaign created (almost) no boxes");
        // Every creation path must append at least once over the process (unique BE_ prefix); lazy passes
        // can be absent from a single run (108 of 771 runs had none).
        uint256 runs = _acc("BE_RUNS", 1);
        uint256[4] memory paths = [
            _acc("BE_mintLootbox", handler.boxesCreated_mintLootbox()),
            _acc("BE_whale", handler.boxesCreated_whale()),
            _acc("BE_lazy", handler.boxesCreated_lazy()),
            _acc("BE_deity", handler.boxesCreated_deity())
        ];
        if (runs < 16) return;
        for (uint256 i; i < paths.length; ++i) {
            assertGt(paths[i], 0, string.concat("NON-VACUITY: box creation path never appended: ", vm.toString(i)));
        }
    }

    function _acc(string memory k, uint256 v) internal virtual returns (uint256 total) {
        total = vm.envOr(k, uint256(0)) + v;
        vm.setEnv(k, vm.toString(total));
    }

    /// @notice Drive the handler's creation actions directly (deterministic seeds spanning the actor
    ///         pool) and assert entries are created across >= 2 distinct paths with every property
    ///         holding — the action surface is reachable independent of the fuzzer's sequencing.
    function test_boxesCreatedAcrossPaths_nonVacuous() public {
        // mint-with-lootbox across the actors (both DirectEth and Combined kinds).
        for (uint256 a; a < handler.actorCount(); a++) {
            handler.mintWithLootbox(a, 0.5 ether, uint8(a));
        }
        // pass bundles: whale + lazy + deity across the actors.
        for (uint256 a; a < handler.actorCount(); a++) {
            handler.buyWhalePass(a, 1);
            handler.buyLazyPass(a);
            handler.buyDeityPass(a, a);
        }

        assertGt(handler.totalBoxesCreated(), 0, "fixture: at least one box was created");
        assertGe(handler.pathsExercised(), 2, "fixture: boxes created across >= 2 distinct paths");
        assertEq(handler.trackedCount(), handler.totalBoxesCreated(), "every creation tracked one entry");
        invariant_everyCreationAppendsOneMatchingEntry();
        invariant_entriesAreNeverRewritten();

        // Seal, publish and settle through the engine; the FIFO properties hold across it.
        for (uint256 i; i < 4; i++) handler.openSome(i, 3, i);
        assertGt(handler.resolutionsObserved(), 0, "fixture: the engine settled queued entries under observation");
        invariant_entriesAreNeverRewritten();
        invariant_readCursorObeysFifo();
    }

    // =========================================================================
    // FALSIFIABILITY: an entry rewritten in place breaks property (2)'s check
    // =========================================================================

    function test_invariantIsFalsifiable_rewrittenEntry() public {
        handler.mintWithLootbox(0, 0.5 ether, 0);
        handler.mintWithLootbox(1, 0.7 ether, 1);
        assertEq(handler.trackedCount(), 2, "fixture: two entries appended");
        assertEq(handler.rewrittenEntries(), 0, "pre: both entries hold their appended words");

        // Rewrite the first entry in place, as a purchase that merged into it would.
        BoxCreationHandler.EntryRef memory first = handler.trackedEntry(0);
        handler.debugRewriteEntry(0, first.word ^ (uint256(1) << 77));
        assertEq(handler.rewrittenEntries(), 1, "FALSIFIABILITY: a rewritten live entry registers the break");

        // Restoring the word returns the check to green (the break was the injection).
        handler.debugRewriteEntry(0, first.word);
        assertEq(handler.rewrittenEntries(), 0, "post: restored entry, check green again");
    }
}
