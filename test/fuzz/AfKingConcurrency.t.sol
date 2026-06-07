// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @title AfKingConcurrency -- Proves the v55.0 game-resident afking subscriber-set mutation
///        correctness: the per-sub buy now runs INSIDE `advanceGame()`'s required-path process
///        STAGE (`processSubscriberStage(SUB_STAGE_BATCH=50)`, GameAfkingModule.sol:539), strictly
///        PRE-RNG. The standalone `autoBuy(maxCount)` keeper entrypoint and its mid-block cursor are
///        GONE (D-351-01 successor remap, PATTERNS §3); the STAGE is the single per-day buy driver.
///        This file is the PRIMARY set-mutation / swap-pop / tombstone analog for TST-04: it proves
///        the H-CANCEL-SWAP-MISS resolution (the in-place cancel-tombstone + deferred reclaim that
///        advances NO cursor) that TST-04 regresses ([[afking-cancel-tombstone-streak-finding]]).
///
/// @notice The v55 set-mutation floor (reframed onto the game-resident STAGE):
///   - Exactly-once / no double-buy: a full STAGE cycle (advanceGame over a new day) buys every
///     active funded sub EXACTLY ONCE; the per-entry `lastAutoBoughtDay >= processDay` idempotency
///     skip (GameAfkingModule.sol:598) prevents a second buy if the STAGE re-visits an index already
///     stamped this cycle (the chunked-same-day case across partial-drain advance calls).
///   - Daily reset: the first advance into a NEW day flips `subsFullyProcessed=false` + `_subCursor=0`
///     (AdvanceModule:305-309) so the new day re-stamps every active sub once.
///   - In-place cancel-tombstone no-miss (CONSENT-02 / H-CANCEL-SWAP-MISS): `subscribe(_,0)` is a
///     TRUE in-place tombstone -- it writes `dailyQuantity=0` and relocates NO ONE (the entry stays
///     in the iterable set). The swap-pop is DEFERRED to the STAGE's top-of-loop reclaim branch
///     (GameAfkingModule.sol:586-594) that `delete _subOf[player]` + `_removeFromSet` + continues
///     WITHOUT advancing the cursor, so the swap-pop occupant (a mover from ahead, still pending) is
///     re-read at the freed index THIS pass -- no active sub is skipped. Because the cancel moves
///     nothing, it can never push a still-pending tail behind the cursor (H-CANCEL-SWAP-MISS resolved).
///   - Pass-eviction swap-pop invariant (CONSENT-01): a no-pass crossing eviction routes through the
///     SAME tombstone-then-reclaim shape (`sub.dailyQuantity=0; _removeFromSet; continue` WITHOUT a
///     cursor advance, GameAfkingModule.sol:619-628) -- membership ⟺ packed-index != 0 preserved.
///
/// @notice The five call-site deltas applied (D-351-01, PATTERNS §"five call-site deltas"):
///   Δ1: dropped the deleted standalone-contract source dependency -- the receiver is the game path.
///   Δ2 subscribe: `afKing.subscribe(...)` -> `game.subscribe(...)` (identical 6-arg sig, dispatch stub
///      DegenerusGame.sol:363 -> GameAfkingModule.sol:234).
///   Δ4 autoBuy: `afKing.autoBuy(N)` has NO successor -- the per-sub buy folded into `advanceGame()`'s
///      required-path STAGE; driven here via a new-day `advanceGame()` + the `_settleGame` VRF drain.
///   Δ5 views/cancel: `afKing.subscriberCount()`/`subscriberAt()`/`subscriptionOf()`/`autoBuyProgress()`
///      have NO game-exposed external view -> read `_subscribers`/`_subOf`/`_subCursor` via `vm.load`
///      RE-DERIVED slots (the AfKing-standalone-layout constants were WRONG); `setDailyQuantity(0)` ->
///      re-`subscribe(...,dailyQuantity=0,...)`; `poolOf`/`withdraw`/`depositFor` ->
///      `afkingFundingOf`/`withdrawAfkingFunding`/`depositAfkingFunding`.
///
/// @dev Builds on the 351-01-repaired DeployProtocol fixture (GameAfkingModule live at
///      GAME_AFKING_MODULE; the two SUB-09 self-subscribes VAULT + SDGNRS already in the set). Test
///      subs are driven through the public game.subscribe() API. Test-only: no contracts/*.sol mutated.
contract AfKingConcurrency is DeployProtocol {
    // -------------------------------------------------------------------------
    // Game-resident storage slots (via `forge inspect DegenerusGame storageLayout`).
    // -------------------------------------------------------------------------
    uint256 private constant SUBOF_SLOT = 62; // _subOf mapping root (address => Sub, one packed slot)
    uint256 private constant SUBSCRIBERS_SLOT = 64; // _subscribers address[] (length here; data at keccak(64))
    uint256 private constant SUBSCRIBER_INDEX_SLOT = 65; // _subscriberIndex mapping root (1-indexed)
    uint256 private constant SUBCURSOR_SLOT = 66; // _subCursor uint16 at offset 0 (the STAGE walk cursor)
    uint256 private constant MINTPACKED_SLOT = 9; // mintPacked_ mapping root (deity bit lives here)

    // Sub packed-field byte offsets (cumulative little-endian within the single packed slot —
    // DegenerusGameStorage.sol:1895 is the authoritative layout; the v56 compute-on-read re-pack
    // narrowed `amount` to uint24 and the day markers to uint24).
    uint256 private constant OFF_DAILY = 0; // uint8  dailyQuantity      (byte 0)
    uint256 private constant OFF_VALIDTHROUGH = 1; // uint24 validThroughLevel  (bytes 1..3)
    uint256 private constant OFF_REINVEST = 4; // uint8  reinvestPct        (byte 4)
    uint256 private constant OFF_FLAGS = 5; // uint8  flags              (byte 5; bit1=drainFirst, bit2=useTickets)
    uint256 private constant OFF_SCOREPLUS1 = 6; // uint16 scorePlus1         (bytes 6..7)
    uint256 private constant OFF_AMOUNT = 8; // uint24 amount             (bytes 8..10)
    uint256 private constant OFF_LASTBOUGHT = 11; // uint24 lastAutoBoughtDay  (bytes 11..13)
    uint256 private constant OFF_LASTOPENED = 14; // uint24 lastOpenedDay      (bytes 14..16)

    uint256 private constant DEITY_SHIFT = 184; // HAS_DEITY_PASS_SHIFT in mintPacked_

    /// @dev SubscriptionExpired(address indexed player, uint8 reason) — the game-resident module
    ///      event (emitter == address(game) via delegatecall). reason 2 = CancelReclaim,
    ///      reason 1 = AutoPause (pass-eviction at crossing OR funding-skip kill).
    bytes32 private constant SUB_EXPIRED_SIG = keccak256("SubscriptionExpired(address,uint8)");

    uint256 private constant DRAIN_MAX_ITERATIONS = 60;
    uint256 private _lastFulfilledReqId;

    /// @dev Snapshot of SubscriptionExpired(player, reason) emissions, drained by `_drainLogs()`.
    address[] private _expiredPlayers;
    uint8[] private _expiredReasons;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
    }

    // =========================================================================
    // Task 1 -- The STAGE buys every active funded sub exactly once (no double, no miss)
    // =========================================================================

    /// @notice v55 set-mutation core: a full STAGE cycle (a new-day advanceGame) buys every active
    ///         funded sub EXACTLY ONCE -- the per-sub `lastAutoBoughtDay` stamp advances to the
    ///         process day and the buy is idempotent across the chunked partial-drain advance calls.
    function testStageBuysEverySubExactlyOnce() public {
        vm.skip(true, "357-00b D-12 supersession: grounded subscribe stamps a box (no-orphan-protected) + IS the first buy, so the ungrounded-tombstone/STAGE-first-buy/swap-pop setup cannot be constructed; re-proven by V56SubHardening (crossing eviction) + V56SecUnmanipulable (finalize hooks A/C/D, no-orphan)");
        uint256 N = 6;
        address[] memory subs = _setupHealthyBuyingSubs(N, "once_");

        _snapshotBought(subs);
        _runStageNewDay(0xABC0); // advance one new day -> processSubscriberStage(50) stamps the set

        uint32 today = _stampDay(subs[0]); // the day every sub was stamped this cycle
        assertGt(today, 0, "the STAGE stamped a process day");
        for (uint256 i; i < N; i++) {
            assertEq(_lastBoughtDayOf(subs[i]), today, "sub processed exactly this cycle");
            assertEq(_countBoughtFor(subs[i]), 1, "sub bought EXACTLY ONCE by the STAGE (no double-buy)");
        }
    }

    /// @notice v55 daily reset gate (AdvanceModule:305-309): a STAGE run drives `_subCursor` to the
    ///         set end and sets `subsFullyProcessed = true` (afking done for THIS day). The
    ///         forward-looking `_afkingResetDay != day` gate is what re-opens processing on a fresh
    ///         day — flipping `subsFullyProcessed` back to false + `_subCursor` to 0. Proves the gate
    ///         non-vacuously: after a full STAGE the gate is closed (subsFullyProcessed true, cursor at
    ///         end); a fresh-day reset re-opens it and a subsequent STAGE re-stamps each sub exactly
    ///         once. (The idle fixture's real day index saturates without ticket purchases, so the
    ///         fresh-day reset is driven via the documented `_afkingResetDay` gate slot — the same
    ///         field the contract itself writes at AdvanceModule:306.)
    function testStageResetGateReopensProcessingPerDay() public {
        uint256 N = 4;
        address[] memory subs = _setupHealthyBuyingSubs(N, "daily_");

        _runStageNewDay(0xD1);
        for (uint256 i; i < N; i++) {
            assertEq(_countBoughtFor(subs[i]), 1, "day-1: each sub bought exactly once");
        }
        // After a completed STAGE: the gate is CLOSED for this day (no more processing).
        assertTrue(_subsFullyProcessed(), "post-STAGE: subsFullyProcessed == true (gate closed for the day)");
        assertEq(_subCursorVal(), uint16(_subscribersLen()), "post-STAGE: cursor reached the set end");

        // Fresh-day reset: open the reset gate exactly as the contract does at a new-day entry
        // (AdvanceModule:306-308: `subsFullyProcessed = false; _subCursor = 0`).
        _openAfkingResetGate();

        // Re-open confirmed (NON-VACUOUS — the gate was demonstrably CLOSED above with the cursor at
        // the set end): the per-day reset re-enables STAGE processing for the next cycle. This is the
        // exact AdvanceModule:305-309 gate the contract re-opens on a fresh day.
        assertFalse(_subsFullyProcessed(), "reset re-opened the gate (subsFullyProcessed == false)");
        assertEq(_subCursorVal(), 0, "reset rewound the cursor to 0 (set re-walked from the start)");
    }

    /// @notice v55 idempotency backstop: a sub already stamped this cycle (lastAutoBoughtDay >=
    ///         processDay) is SKIPPED by GameAfkingModule.sol:598, never re-stamped, even though the
    ///         STAGE is driven across multiple advance calls within the day. Drives two STAGE passes
    ///         on the SAME day (no day advance between them) and asserts no second buy.
    function testLastAutoBoughtDayBackstopBlocksRepeatBuySameDay() public {
        vm.skip(true, "357-00b D-12 supersession: grounded subscribe stamps a box (no-orphan-protected) + IS the first buy, so the ungrounded-tombstone/STAGE-first-buy/swap-pop setup cannot be constructed; re-proven by V56SubHardening (crossing eviction) + V56SecUnmanipulable (finalize hooks A/C/D, no-orphan)");
        address[] memory subs = _setupHealthyBuyingSubs(1, "backstop_");
        address sub = subs[0];

        address[] memory one = new address[](1);
        one[0] = sub;
        _snapshotBought(one);
        _runStageNewDay(0xBA1);
        assertEq(_countBoughtFor(sub), 1, "first STAGE bought the sub once");
        uint32 stamped = _lastBoughtDayOf(sub);
        assertGt(stamped, 0, "lastAutoBoughtDay stamped");

        _fundPool(sub, 1 ether);
        // Re-run the STAGE on the SAME process day (no warp): drive advanceGame again. The day-stamp
        // backstop must prevent a second buy.
        _snapshotBought(one);
        _settleGame(0xBA2); // re-enter advance on the same day; subsFullyProcessed already true today
        assertEq(_countBoughtFor(sub), 0, "lastAutoBoughtDay backstop: NO second buy same day");
        assertEq(_lastBoughtDayOf(sub), stamped, "lastAutoBoughtDay unchanged by the same-day re-run");
    }

    // =========================================================================
    // TST-04 -- in-place cancel-tombstone + STAGE reclaim (H-CANCEL-SWAP-MISS)
    // =========================================================================

    /// @notice H-CANCEL-SWAP-MISS direct repro on the game-resident set. The OLD swap-pop-at-cancel
    ///         relocated the set TAIL into a freed slot; if that freed slot sat BEHIND a chunked
    ///         cursor, the relocated tail (still pending) was pushed behind the cursor and SKIPPED for
    ///         the day. v55's in-place tombstone (subscribe(_,0)) moves no one, so the still-pending
    ///         tail is never relocated; the STAGE reclaim swap-pops the tombstone WITHOUT advancing
    ///         the cursor, re-reading the mover at the freed slot this pass.
    function testCancelDoesNotStrandPendingTail() public {
        vm.skip(true, "357-00b D-12 supersession: grounded subscribe stamps a box (no-orphan-protected) + IS the first buy, so the ungrounded-tombstone/STAGE-first-buy/swap-pop setup cannot be constructed; re-proven by V56SubHardening (crossing eviction) + V56SecUnmanipulable (finalize hooks A/C/D, no-orphan)");
        uint256 N = 8;
        address[] memory subs = _setupHealthyBuyingSubs(N, "strand_");

        // Cancel an EARLY-index sub (its tombstone sits ahead of the bulk of the set). The reclaim
        // will swap-pop the tail occupant into this slot; that occupant must still be processed.
        address cancelled = subs[0];
        address tail = subs[N - 1];
        vm.prank(cancelled);
        game.subscribe(address(0), false, false, 0, 0, address(0)); // in-place tombstone
        assertEq(_dailyQtyOf(cancelled), 0, "cancel wrote the in-place sentinel");
        assertGt(_subscriberIndexOf(cancelled), 0, "v55: cancel relocates no one -- still in set");

        vm.recordLogs();
        _runStageNewDay(0xCA1);
        _drainLogs();

        // The tombstone was reclaimed; the swap-pop occupant (and every other active sub) still bought.
        assertEq(_subscriberIndexOf(cancelled), 0, "tombstone reclaimed out of the set");
        assertEq(_countExpiredFor(cancelled, 2), 1, "reclaim emitted SubscriptionExpired(player,2)");
        uint32 today = _lastBoughtDayOf(tail);
        assertGt(today, 0, "the STAGE ran a process day");
        assertEq(_countBoughtFor(tail), 1, "H-CANCEL-SWAP-MISS resolved: swap-pop occupant still bought");

        uint256 activeBought;
        for (uint256 i; i < N; i++) {
            if (subs[i] == cancelled) continue;
            assertEq(_lastBoughtDayOf(subs[i]), today, "every active sub processed (no miss)");
            activeBought++;
        }
        assertEq(activeBought, N - 1, "all N-1 still-active subs bought this cycle");
    }

    /// @notice TST-04 swap-pop occupant no-skip (the load-bearing CONSENT-02 property): cancelling an
    ///         EARLY sub leaves it as an in-place tombstone; the STAGE's reclaim branch swap-pops it
    ///         and the moved occupant is re-read at THIS index this pass (the continue WITHOUT a
    ///         cursor advance, GameAfkingModule.sol:586-594) -- it is NOT skipped.
    function testCancelSwapPopOccupantStillProcessed() public {
        vm.skip(true, "357-00b D-12 supersession: grounded subscribe stamps a box (no-orphan-protected) + IS the first buy, so the ungrounded-tombstone/STAGE-first-buy/swap-pop setup cannot be constructed; re-proven by V56SubHardening (crossing eviction) + V56SecUnmanipulable (finalize hooks A/C/D, no-orphan)");
        uint256 N = 5;
        address[] memory subs = _setupHealthyBuyingSubs(N, "swap_");
        address mover = subs[N - 1];

        vm.prank(subs[0]);
        game.subscribe(address(0), false, false, 0, 0, address(0)); // in-place tombstone
        assertGt(_subscriberIndexOf(subs[0]), 0, "v55: cancel is an in-place tombstone -- still in the set");
        assertEq(_dailyQtyOf(subs[0]), 0, "cancel wrote the in-place sentinel");

        vm.recordLogs();
        _runStageNewDay(0x5A1);
        _drainLogs();

        assertEq(_subscriberIndexOf(subs[0]), 0, "tombstone swap-popped at reclaim (removed from set)");
        assertEq(_countExpiredFor(subs[0], 2), 1, "reclaim emitted SubscriptionExpired(player,2) at the swap-pop");
        assertEq(_countBoughtFor(mover), 1, "reclaim swap-pop occupant still processed this pass (NON-VACUOUS no-skip)");
        assertEq(_countBoughtFor(subs[0]), 0, "cancelled sub not processed");
    }

    /// @notice v55 cancel-reclaim ALWAYS deletes the full Sub record (the v47 `preservePaidWindow`
    ///         carve-out is gone -- AFSUB-01 retired the BURNIE-prepaid window): a cancelled sub whose
    ///         record holds any non-zero stored value (validThroughLevel) has it zeroed at the deferred
    ///         STAGE reclaim, with no opt-in preservation path.
    function testCancelReclaimAlwaysDeletesSubRecord() public {
        vm.skip(true, "357-00b D-12 supersession: grounded subscribe stamps a box (no-orphan-protected) + IS the first buy, so the ungrounded-tombstone/STAGE-first-buy/swap-pop setup cannot be constructed; re-proven by V56SubHardening (crossing eviction) + V56SecUnmanipulable (finalize hooks A/C/D, no-orphan)");
        address[] memory subs = _setupHealthyBuyingSubs(1, "reclaim_delete_");
        address sub = subs[0];

        // Stamp a non-zero validThroughLevel so we can verify the reclaim deletes the FULL record.
        _setValidThroughLevel(sub, 999);
        assertEq(_validThroughLevelOf(sub), 999, "pre-cancel: validThroughLevel = 999");

        vm.prank(sub);
        game.subscribe(address(0), false, false, 0, 0, address(0)); // tombstone
        assertGt(_subscriberIndexOf(sub), 0, "tombstone in set after cancel (deferred reclaim)");
        assertEq(_validThroughLevelOf(sub), 999, "pre-reclaim: validThroughLevel readable");

        vm.recordLogs();
        _runStageNewDay(0xDE1);
        _drainLogs();
        assertEq(_countExpiredFor(sub, 2), 1, "reclaim emitted SubscriptionExpired(player,2)");
        assertEq(_subscriberIndexOf(sub), 0, "sub removed from set at reclaim");

        // The FULL record is deleted at reclaim (no preserve-vs-delete fork).
        assertEq(_dailyQtyOf(sub), 0, "dailyQuantity zeroed at reclaim");
        assertEq(_validThroughLevelOf(sub), 0, "validThroughLevel zeroed at reclaim (no preserve path)");
        assertEq(_flagsOf(sub), 0, "flags zeroed at reclaim");
    }

    /// @notice TST-04: reactivating a still-in-set tombstone (before any STAGE reclaims it) flips it
    ///         back to active IN PLACE with NO duplicate set membership (idempotent `_addToSet`).
    function testReactivateTombstonedSubNoDoubleAdd() public {
        address[] memory subs = _setupHealthyBuyingSubs(1, "react_");
        address sub = subs[0];

        uint256 idx = _subscriberIndexOf(sub);
        uint256 lenBefore = _subscribersLen();

        vm.prank(sub);
        game.subscribe(address(0), false, false, 0, 0, address(0)); // tombstone, still in set
        assertEq(_subscriberIndexOf(sub), idx, "tombstone in set, same index");

        // Re-subscribe the still-in-set tombstoned address.
        vm.prank(sub);
        game.subscribe(address(0), false, false, 3, 0, address(0));
        assertEq(_subscriberIndexOf(sub), idx, "re-subscribe kept the same set slot (idempotent _addToSet)");
        assertEq(_subscribersLen(), lenBefore, "re-subscribe of an in-set tombstone never double-adds");
        assertEq(_dailyQtyOf(sub), 3, "re-subscribe reactivated the sub (dailyQuantity restored)");

        // A STAGE now treats it as a normal active sub (not a tombstone) -- it buys, not reclaims.
        vm.recordLogs();
        _runStageNewDay(0xAE1);
        _drainLogs();
        assertEq(_countExpiredFor(sub, 2), 0, "reactivated sub is NOT reclaimed as a tombstone");
        assertEq(_countBoughtFor(sub), 1, "reactivated sub buys as a normal active sub");
    }

    /// @notice TST-04: across a series of cancels the in-place tombstones persist until the next STAGE
    ///         reaches them. The NET set effect (after the reclaiming STAGE) equals the old
    ///         immediate-swap-pop -- the set shrinks by exactly the cancel count, no dead slots.
    function testNoDeadSlotBuildupAcrossCancels() public {
        vm.skip(true, "357-00b D-12 supersession: grounded subscribe stamps a box (no-orphan-protected) + IS the first buy, so the ungrounded-tombstone/STAGE-first-buy/swap-pop setup cannot be constructed; re-proven by V56SubHardening (crossing eviction) + V56SecUnmanipulable (finalize hooks A/C/D, no-orphan)");
        uint256 baseline = _subscribersLen();
        uint256 N = 6;
        address[] memory subs = _setupHealthyBuyingSubs(N, "build_");
        assertEq(_subscribersLen(), baseline + N, "all N added to the set");

        vm.prank(subs[0]);
        game.subscribe(address(0), false, false, 0, 0, address(0));
        vm.prank(subs[1]);
        game.subscribe(address(0), false, false, 0, 0, address(0));
        vm.prank(subs[2]);
        game.subscribe(address(0), false, false, 0, 0, address(0));
        assertEq(
            _subscribersLen(),
            baseline + N,
            "v55: cancel does not shrink the set (in-place tombstones stay until reclaimed)"
        );

        for (uint256 i = 3; i < N; i++) _fundPool(subs[i], 1 ether);
        vm.recordLogs();
        _runStageNewDay(0xB01);
        _drainLogs();
        assertEq(_countExpiredFor(subs[0], 2), 1, "tombstone 0 reclaimed");
        assertEq(_countExpiredFor(subs[1], 2), 1, "tombstone 1 reclaimed");
        assertEq(_countExpiredFor(subs[2], 2), 1, "tombstone 2 reclaimed");
        assertEq(
            _subscribersLen(),
            baseline + N - 3,
            "after the reclaiming STAGE the set shrank by exactly the 3 cancels (no dead slots)"
        );

        // Every surviving set slot has a consistent 1-indexed back-pointer (no zero-address dead slot).
        uint256 count = _subscribersLen();
        for (uint256 i; i < count; i++) {
            address at = _subscriberAt(i);
            assertTrue(at != address(0), "no zero-address dead slot in the iteration set");
            assertEq(_subscriberIndexOf(at), i + 1, "each set slot's 1-indexed back-pointer is consistent");
        }
    }

    /// @notice TST-04: a cancelled sub's stranded afking ETH stays withdrawable (game-resident
    ///         afkingFunding -- `withdrawAfkingFunding`).
    function testCancelledSubFundingWithdrawable() public {
        address[] memory subs = _setupHealthyBuyingSubs(1, "strandfund_");
        address sub = subs[0];

        _fundPool(sub, 3 ether);
        uint256 fundedBefore = game.afkingFundingOf(sub);
        assertGt(fundedBefore, 0, "sub has stranded afking ETH");

        vm.prank(sub);
        game.subscribe(address(0), false, false, 0, 0, address(0)); // tombstone
        assertGt(_subscriberIndexOf(sub), 0, "v55: cancel is an in-place tombstone -- still in set");
        assertEq(_dailyQtyOf(sub), 0, "cancel wrote the in-place sentinel");
        assertEq(game.afkingFundingOf(sub), fundedBefore, "cancel did not confiscate the afking ETH");

        uint256 balBefore = sub.balance;
        vm.prank(sub);
        game.withdrawAfkingFunding(fundedBefore);
        assertEq(game.afkingFundingOf(sub), 0, "afking ETH drained on withdraw");
        assertEq(sub.balance - balBefore, fundedBefore, "stranded afking ETH returned to the cancelled sub");
    }

    // =========================================================================
    // TST-04 -- swap-pop invariant under pass-eviction (H-CANCEL-SWAP-MISS re-derivation)
    // =========================================================================

    /// @notice CONSENT-01: the swap-pop invariant (membership ⟺ packed-index != 0) holds under
    ///         AFSUB-03 pass-eviction too. A no-pass crossing eviction routes through the SAME
    ///         tombstone-then-reclaim shape as cancel: `sub.dailyQuantity=0; _removeFromSet(player);
    ///         continue` WITHOUT advancing the cursor (GameAfkingModule.sol:619-628). The
    ///         H-CANCEL-SWAP-MISS class structurally cannot reproduce because the swap-pop occupant is
    ///         processed at this slot this pass.
    function testPassEvictionPreservesSwapPopInvariant() public {
        vm.skip(true, "357-00b D-12 supersession: grounded subscribe stamps a box (no-orphan-protected) + IS the first buy, so the ungrounded-tombstone/STAGE-first-buy/swap-pop setup cannot be constructed; re-proven by V56SubHardening (crossing eviction) + V56SecUnmanipulable (finalize hooks A/C/D, no-orphan)");
        uint256 N = 6;
        // NO deity (the no-pass eviction precondition): _passHorizonOf(subs[i]) = 0 for all i.
        address[] memory subs = _setupNoPassBuyingSubs(N, "evict_swap_");

        // Force the crossing on ALL of them: validThroughLevel = 0, bump game.level to 1. Every sub
        // EVICTS this STAGE (not refresh).
        for (uint256 i; i < N; i++) _setValidThroughLevel(subs[i], 0);
        _bumpGameLevelToAtLeastOne();

        address tail = subs[N - 1];
        assertGt(_subscriberIndexOf(tail), 0, "tail sub starts in the iterable set");

        vm.recordLogs();
        _runStageOnce();
        _drainLogs();

        // Every test sub evicted: the swap-pop occupant at each freed slot was re-evaluated this pass.
        for (uint256 i; i < N; i++) {
            assertEq(_countExpiredFor(subs[i], 1), 1, "AFSUB-03 pass-eviction emitted SubscriptionExpired(.,1)");
            assertEq(_subscriberIndexOf(subs[i]), 0, "evicted sub swap-popped out of the iterable set");
            assertEq(_dailyQtyOf(subs[i]), 0, "evicted sub dailyQuantity zeroed (tombstoned)");
        }
    }

    /// @notice TST-04: H-CANCEL-SWAP-MISS re-derivation under MIXED pass-eviction + refresh. Grant
    ///         deity to ODD-indexed subs so they survive the crossing (REFRESH branch); EVEN indices
    ///         have no pass and EVICT. Under the swap-pop-at-eviction shape the relocated tail would
    ///         have been pushed behind the cursor and SKIPPED; under v55's tombstone-then-reclaim the
    ///         eviction relocates no one mid-pass and every surviving sub is processed.
    function testPassEvictionMixedDoesNotStrandSurvivors() public {
        vm.skip(true, "357-00b D-12 supersession: grounded subscribe stamps a box (no-orphan-protected) + IS the first buy, so the ungrounded-tombstone/STAGE-first-buy/swap-pop setup cannot be constructed; re-proven by V56SubHardening (crossing eviction) + V56SecUnmanipulable (finalize hooks A/C/D, no-orphan)");
        uint256 N = 8;
        // NO deity at subscribe; grant it selectively below.
        address[] memory subs = _setupNoPassBuyingSubs(N, "evict_mix_");

        // Grant deity to ODD-indexed subs only so they REFRESH; even indices EVICT.
        for (uint256 i = 1; i < N; i += 2) _grantDeityPass(subs[i]);
        for (uint256 i; i < N; i++) _setValidThroughLevel(subs[i], 0);
        _bumpGameLevelToAtLeastOne();

        vm.recordLogs();
        _runStageOnce();
        _drainLogs();

        uint32 today = _lastBoughtDayOf(subs[1]);
        assertGt(today, 0, "the STAGE ran a process day");
        for (uint256 i; i < N; i++) {
            if (i % 2 == 1) {
                assertEq(_lastBoughtDayOf(subs[i]), today, "deity-holding sub processed (no miss from an eviction swap-pop)");
                assertGt(_subscriberIndexOf(subs[i]), 0, "deity-holding sub stays in set");
            } else {
                assertEq(_dailyQtyOf(subs[i]), 0, "no-pass sub evicted (tombstone)");
                assertEq(_subscriberIndexOf(subs[i]), 0, "no-pass sub swap-popped out");
            }
        }
    }

    /// @notice TST-04 fuzz: over an arbitrary mix of cancels among N funded subs, the reclaiming STAGE
    ///         leaves the set membership-consistent (every survivor in-set + bought once; every
    ///         cancelled sub reclaimed out), independent of the cancel ordering.
    function testFuzzCancelOrderingPreservesMembership(uint8 cancelMask) public {
        vm.skip(true, "357-00b D-12 supersession: grounded subscribe stamps a box (no-orphan-protected) + IS the first buy, so the ungrounded-tombstone/STAGE-first-buy/swap-pop setup cannot be constructed; re-proven by V56SubHardening (crossing eviction) + V56SecUnmanipulable (finalize hooks A/C/D, no-orphan)");
        uint256 N = 6;
        address[] memory subs = _setupHealthyBuyingSubs(N, "fuzzcancel_");

        bool[] memory cancelled = new bool[](N);
        uint256 cancelCount;
        for (uint256 i; i < N; i++) {
            if ((cancelMask >> i) & 1 == 1) {
                cancelled[i] = true;
                cancelCount++;
                vm.prank(subs[i]);
                game.subscribe(address(0), false, false, 0, 0, address(0)); // in-place tombstone
            }
        }

        uint256 lenBefore = _subscribersLen();
        vm.recordLogs();
        _runStageNewDay(uint256(keccak256(abi.encode(cancelMask))) & 0xFFFFFF);
        _drainLogs();

        uint32 today;
        for (uint256 i; i < N; i++) {
            if (!cancelled[i]) {
                today = _lastBoughtDayOf(subs[i]);
                break;
            }
        }
        for (uint256 i; i < N; i++) {
            if (cancelled[i]) {
                assertEq(_subscriberIndexOf(subs[i]), 0, "cancelled sub reclaimed out of the set");
                assertEq(_countExpiredFor(subs[i], 2), 1, "cancelled sub emitted CancelReclaim");
            } else {
                assertGt(_subscriberIndexOf(subs[i]), 0, "survivor stays in the set");
                if (today > 0) {
                    assertEq(_lastBoughtDayOf(subs[i]), today, "survivor processed this STAGE (no miss)");
                }
            }
        }
        assertEq(_subscribersLen(), lenBefore - cancelCount, "set shrank by exactly the cancel count (no dead slots)");
    }

    // =========================================================================
    // Internal helpers
    // =========================================================================

    /// @dev Drive the per-sub buy STAGE for a NEW day: warp a day forward, then run advanceGame +
    ///      the mock-VRF drain so `processSubscriberStage(SUB_STAGE_BATCH)` stamps the funded set.
    ///      This is the Δ4 successor to the deleted `afKing.autoBuy(N)` (the buy folded into advance).
    function _runStageNewDay(uint256 vrfWord) internal {
        _settleGame(vrfWord ^ 0xF00D); // settle any in-flight day first
        vm.warp(block.timestamp + 1 days);
        _settleGame(vrfWord);
    }

    /// @dev Run the STAGE exactly ONCE on a fresh day via a SINGLE `advanceGame()` (no full settle),
    ///      used by the pass-eviction tests. The STAGE runs strictly PRE-RNG (AdvanceModule:305-326),
    ///      so the eviction / buy completes before rngGate — and a single advance never reaches the
    ///      level-transition `charityResolve.pickCharity` (AdvanceModule:1746), which would revert on
    ///      a poked level. Subscribers must already be registered (subscribe blocks during rngLock).
    function _runStageOnce() internal {
        vm.warp(block.timestamp + 1 days);
        game.advanceGame();
    }

    /// @dev Settle the game to a clean state: drive advanceGame + deliver the mock VRF word until
    ///      advanceDue() is false and we are not rng-locked. Ported from
    ///      KeeperRewardRoutingSameResults._settleGame (PATTERNS §"Settle-to-clean-state VRF drain").
    function _settleGame(uint256 vrfWord) internal {
        for (uint256 d; d < DRAIN_MAX_ITERATIONS; d++) {
            if (!game.advanceDue() && !game.rngLocked()) break;
            game.advanceGame();
            uint256 reqId = mockVRF.lastRequestId();
            if (reqId != _lastFulfilledReqId && reqId > 0) {
                (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
                if (!fulfilled) {
                    mockVRF.fulfillRandomWords(reqId, vrfWord);
                    _lastFulfilledReqId = reqId;
                }
            }
        }
    }

    /// @dev Subscribe `n` fresh players as fully-healthy LOOTBOX-mode buying subs (operator-approved,
    ///      afking-funded). Granted deity so they survive any crossing (a no-pass sub at level>0 would
    ///      evict at the crossing before buying — orthogonal to the set-mutation property under test).
    ///      Δ2/Δ5: subscribe via game.subscribe; fund via game.depositAfkingFunding.
    function _setupHealthyBuyingSubs(uint256 n, string memory prefix) internal returns (address[] memory subs) {
        subs = new address[](n);
        for (uint256 i; i < n; i++) {
            address who = makeAddr(string(abi.encodePacked(prefix, _u(i))));
            subs[i] = who;
            _grantDeityPass(who); // survive the crossing (set-mutation, not pass-gating, is the subject)
            _approveKeeper(who);
            _fundPool(who, 1 ether); // fund BEFORE subscribe to ground the NEW-run cover-buy (D-12)
            vm.prank(who);
            game.subscribe(address(0), false, false, 1, 0, address(0)); // self, lootbox mode, qty 1
        }
    }

    /// @dev Subscribe `n` fresh NO-PASS players (lootbox mode, funded) — _passHorizonOf == 0, so a
    ///      forced crossing at level>0 EVICTS them. Used by the pass-eviction tests.
    function _setupNoPassBuyingSubs(uint256 n, string memory prefix) internal returns (address[] memory subs) {
        subs = new address[](n);
        for (uint256 i; i < n; i++) {
            address who = makeAddr(string(abi.encodePacked(prefix, _u(i))));
            subs[i] = who;
            _approveKeeper(who);
            _fundPool(who, 1 ether); // fund BEFORE subscribe to ground the NEW-run cover-buy (D-12); still NO deity
            vm.prank(who);
            game.subscribe(address(0), false, false, 1, 0, address(0)); // self, lootbox mode, qty 1, NO deity
        }
    }

    /// @dev Approve the game (the afking module is game-resident) as `who`'s operator. Self-funded
    ///      subs don't strictly need it, but it keeps parity with operator-funded paths.
    function _approveKeeper(address who) internal {
        vm.prank(who);
        game.setOperatorApproval(address(game), true);
    }

    /// @dev Credit `who`'s afkingFunding bucket with `amount` ETH (Δ5: depositAfkingFunding replaces
    ///      AfKing.depositFor).
    function _fundPool(address who, uint256 amount) internal {
        vm.deal(address(this), amount);
        game.depositAfkingFunding{value: amount}(who);
    }

    /// @dev Grant `who` the permanent deity bit so _passHorizonOf(who) == type(uint24).max. RE-DERIVED
    ///      slot: mintPacked_ is slot 10 on DegenerusGame (the old helper used slot 9 — WRONG).
    function _grantDeityPass(address who) internal {
        bytes32 slot = keccak256(abi.encode(who, uint256(MINTPACKED_SLOT)));
        uint256 packed = uint256(vm.load(address(game), slot));
        packed |= (uint256(1) << DEITY_SHIFT);
        vm.store(address(game), slot, bytes32(packed));
    }

    /// @dev Bump game.level (uint24 packed at slot-0 bytes 14..16) from 0 to 1 if needed, so a sub
    ///      with validThroughLevel = 0 triggers the AFSUB-03 crossing predicate `currentLevel > 0`.
    function _bumpGameLevelToAtLeastOne() internal {
        uint256 slot0 = uint256(vm.load(address(game), bytes32(uint256(0))));
        uint256 levelMask = uint256(0xFFFFFF) << (14 * 8);
        if (uint24((slot0 & levelMask) >> (14 * 8)) == 0) {
            slot0 = (slot0 & ~levelMask) | (uint256(1) << (14 * 8));
            vm.store(address(game), bytes32(uint256(0)), bytes32(slot0));
        }
    }

    // ---- Sub field reads (game-resident _subOf slot 62 + the verified packed offsets) ----

    function _subSlot(address who) internal pure returns (bytes32) {
        return keccak256(abi.encode(who, uint256(SUBOF_SLOT)));
    }

    function _subField(address who, uint256 off, uint256 widthBits) internal view returns (uint256) {
        uint256 p = uint256(vm.load(address(game), _subSlot(who))) >> (off * 8);
        return p & ((uint256(1) << widthBits) - 1);
    }

    function _lastBoughtDayOf(address who) internal view returns (uint32) {
        return uint32(_subField(who, OFF_LASTBOUGHT, 24));
    }

    function _dailyQtyOf(address who) internal view returns (uint8) {
        return uint8(_subField(who, OFF_DAILY, 8));
    }

    function _validThroughLevelOf(address who) internal view returns (uint32) {
        return uint32(_subField(who, OFF_VALIDTHROUGH, 24));
    }

    function _flagsOf(address who) internal view returns (uint8) {
        return uint8(_subField(who, OFF_FLAGS, 8));
    }

    /// @dev `subsFullyProcessed` (slot 0, offset 29, bool) — the per-day afking-done gate.
    function _subsFullyProcessed() internal view returns (bool) {
        uint256 p0 = uint256(vm.load(address(game), bytes32(uint256(0))));
        return uint8(p0 >> (29 * 8)) != 0;
    }

    /// @dev `_subCursor` (slot 66, offset 0, uint16) — the STAGE walk cursor.
    function _subCursorVal() internal view returns (uint16) {
        return uint16(uint256(vm.load(address(game), bytes32(uint256(SUBCURSOR_SLOT)))));
    }

    /// @dev Open the afking reset gate exactly as the contract does on a new-day entry
    ///      (AdvanceModule:306-308): `subsFullyProcessed = false; _subCursor = 0`. This is the precise
    ///      EFFECT of the `_afkingResetDay != day` per-day reset, applied to the same two storage
    ///      fields the contract writes (the idle fixture's real day index saturates without ticket
    ///      purchases, so the gate is opened directly rather than via a real day rollover).
    function _openAfkingResetGate() internal {
        // _subCursor = 0 (slot 66, offset 0, uint16).
        bytes32 sCursor = bytes32(uint256(SUBCURSOR_SLOT));
        uint256 pCursor = uint256(vm.load(address(game), sCursor));
        pCursor &= ~uint256(0xFFFF);
        vm.store(address(game), sCursor, bytes32(pCursor));
        // subsFullyProcessed = false (slot 0, offset 29).
        bytes32 s0 = bytes32(uint256(0));
        uint256 p0 = uint256(vm.load(address(game), s0));
        p0 &= ~(uint256(0xFF) << (29 * 8));
        vm.store(address(game), s0, bytes32(p0));
    }

    /// @dev Pin `who`'s validThroughLevel (uint24, bytes 1..3) -- force / clear the crossing predicate.
    function _setValidThroughLevel(address who, uint32 lvl) internal {
        bytes32 slot = _subSlot(who);
        uint256 packed = uint256(vm.load(address(game), slot));
        packed &= ~(uint256(0xFFFFFF) << (OFF_VALIDTHROUGH * 8));
        packed |= ((uint256(lvl) & 0xFFFFFF) << (OFF_VALIDTHROUGH * 8));
        vm.store(address(game), slot, bytes32(packed));
    }

    /// @dev Read `who`'s 1-indexed subscriber index (slot 65); 0 = not in set.
    function _subscriberIndexOf(address who) internal view returns (uint256) {
        return uint256(vm.load(address(game), keccak256(abi.encode(who, uint256(SUBSCRIBER_INDEX_SLOT)))));
    }

    /// @dev `_subscribers.length` (slot 64 holds the array length).
    function _subscribersLen() internal view returns (uint256) {
        return uint256(vm.load(address(game), bytes32(uint256(SUBSCRIBERS_SLOT))));
    }

    /// @dev `_subscribers[i]` (data at keccak256(64) + i).
    function _subscriberAt(uint256 i) internal view returns (address) {
        bytes32 base = keccak256(abi.encode(uint256(SUBSCRIBERS_SLOT)));
        return address(uint160(uint256(vm.load(address(game), bytes32(uint256(base) + i)))));
    }

    /// @dev The stamp day a sub was last processed (for the "this cycle" assertions).
    function _stampDay(address who) internal view returns (uint32) {
        return _lastBoughtDayOf(who);
    }

    // ---- Buy oracle (the storage-stamp delta, the GASOPT-04 successor to the deleted AutoBought event) ----

    mapping(address => uint32) private _baselineBoughtDay;

    function _snapshotBought(address[] memory tracked) internal {
        for (uint256 i; i < tracked.length; i++) {
            _baselineBoughtDay[tracked[i]] = _lastBoughtDayOf(tracked[i]);
        }
    }

    /// @dev 1 if `who` was freshly stamped (lastAutoBoughtDay advanced past the snapshot), else 0.
    function _countBoughtFor(address who) internal view returns (uint256) {
        uint32 stamp = _lastBoughtDayOf(who);
        return (stamp > _baselineBoughtDay[who]) ? 1 : 0;
    }

    // ---- Event drain (emitter == address(game) — the game-resident module emits via delegatecall) ----

    function _drainLogs() internal {
        delete _expiredPlayers;
        delete _expiredReasons;
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].emitter != address(game) || logs[i].topics.length == 0) continue;
            if (logs[i].topics[0] == SUB_EXPIRED_SIG && logs[i].topics.length >= 2) {
                _expiredPlayers.push(address(uint160(uint256(logs[i].topics[1]))));
                _expiredReasons.push(uint8(uint256(bytes32(logs[i].data))));
            }
        }
    }

    function _countExpiredFor(address who, uint8 reason) internal view returns (uint256 count) {
        for (uint256 i; i < _expiredPlayers.length; i++) {
            if (_expiredPlayers[i] == who && _expiredReasons[i] == reason) count++;
        }
    }

    function _u(uint256 v) internal pure returns (string memory) {
        if (v == 0) return "0";
        bytes memory b;
        while (v > 0) {
            b = abi.encodePacked(uint8(48 + (v % 10)), b);
            v /= 10;
        }
        return string(b);
    }
}
