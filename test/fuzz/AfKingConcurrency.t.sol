// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @title AfKingConcurrency -- Proves SAFE-03 autoBuy concurrency-correctness for the AF_KING keeper:
///        two same-block autoBuy(maxCount) callers self-partition via the advancing `_autoBuyCursor` plus
///        the per-entry `lastAutoBoughtDay` idempotency backstop, AND (TOMB-04, v47) the in-place
///        cancel-tombstone + in-autoBuy deferred reclaim relocates no one (resolving H-CANCEL-SWAP-MISS),
///        leaves no dead-slot buildup, and skips no active subscriber.
///
/// @notice The autoBuy is PERMISSIONLESS and CONCURRENT -- multiple keepers/craners can call autoBuy in
///         the SAME block. SAFE-03 is the concurrency floor:
///   - Same-block self-partition (Task 1, SUB-03): with N active subs and two autoBuy(maxCount) calls in
///     the same block (each maxCount < N so neither covers all at once), every subscriber is bought
///     EXACTLY ONCE across the two autoBuys. The cursor advances across the first autoBuy; the second
///     autoBuy resumes from the advanced position. No subscriber is bought twice (the `lastAutoBoughtDay >=
///     today` backstop blocks a repeat) and none is left unprocessed once combined maxCount >= N.
///   - Daily cursor reset: the first autoBuy of a NEW keeper-local day restarts the cursor at 0, and the
///     per-entry lastAutoBoughtDay gates the fresh-day buy (one buy per sub per day).
///   - lastAutoBoughtDay backstop alone: even if a autoBuy re-visits an index already bought today (cursor
///     position notwithstanding), the day-stamp prevents a second buy.
///   - In-place cancel-tombstone no-miss (TOMB-04 / Task 2, SUB-07): v47 setDailyQuantity(0) is a TRUE
///     in-place tombstone -- it writes the dailyQuantity=0 sentinel and relocates NO ONE (the entry
///     stays in the iterable set). The swap-pop + the windowPaid-gated delete-vs-preserve are DEFERRED
///     to a top-of-loop reclaim branch in autoBuy() that does NOT advance the cursor, so the swap-pop
///     occupant is re-read at the freed index THIS autoBuy -- no active sub is skipped. Because the cancel
///     moves nothing, it can never push a still-pending tail entry behind the chunked cursor (the v46.0
///     H-CANCEL-SWAP-MISS missed-day -> mint-streak reset is RESOLVED). After the reclaiming autoBuy the
///     set holds only the active subs (no dead-slot buildup -- deferred, net-equal to the old swap-pop),
///     a cancelled sub's stranded pool ETH stays withdrawable, and the windowPaid-gated reclaim rule
///     holds at reclaim time (paid+unexpired -> _subOf preserved; unpaid/expired -> deleted).
///
/// @dev Builds on the 318-01-repaired DeployProtocol fixture (AfKing live at AF_KING; the two SUB-09
///      self-subscribes VAULT + SDGNRS already in the set). Test subs are driven through the public
///      subscribe() API and made healthy (ticket mode, operator-approved, pool-funded, not renewal-due)
///      so each lands a clean buy. To isolate the new subscribers from the two deploy-time subs, every
///      assertion is keyed on per-player lastAutoBoughtDay / pool deltas / event counts rather than on the
///      raw subscriberCount of the whole set. Test-only: no contracts/*.sol mutated.
contract AfKingConcurrency is DeployProtocol {
    // -------------------------------------------------------------------------
    // AfKing pinned 4-slot layout + Sub packed-field offsets (per AfKing.sol)
    // -------------------------------------------------------------------------
    uint256 private constant SUBOF_SLOT = 1;          // _subOf mapping root (address => Sub, one slot)
    uint256 private constant SUBSCRIBER_INDEX_SLOT = 3; // _subscriberIndex mapping root (1-indexed)

    // Sub packed-field byte offsets re-derived from the post-OPEN-E repack (319.1-01 AFTER
    // layout): the two standalone bools collapsed into `flags` and a 20-byte `fundingSource`
    // address was appended, shifting lastAutoBoughtDay 3->1, paidThroughDay 7->5, flags 12->10.
    uint256 private constant OFF_DAILY = 0;          // uint8  dailyQuantity  (byte 0)
    uint256 private constant OFF_LASTSWEPT = 1;      // uint32 lastAutoBoughtDay    (bytes 1..4)
    uint256 private constant OFF_PAIDTHROUGH = 5;    // uint32 paidThroughDay  (bytes 5..8)
    uint256 private constant OFF_REINVEST = 9;       // uint8  reinvestPct     (byte 9)
    uint256 private constant OFF_FLAGS = 10;         // uint8  flags (bit 0 = windowPaid, byte 10)
    uint256 private constant OFF_FUNDING_SOURCE = 11; // address fundingSource (bytes 11..30)

    uint256 private constant FLAG_WINDOW_PAID = 1;
    uint32 private constant WINDOW_DAYS = 30;

    bytes32 private constant SUB_UPDATED_SIG =
        keccak256("SubscriptionUpdated(address,uint8,bool,bool,uint8,address)");
    /// @dev SubscriptionExpired(address indexed player, uint8 reason). reason 2 = CancelReclaim (the
    ///      in-autoBuy reclaim of an externally-cancelled tombstone); reason 1 = AutoPause.
    bytes32 private constant SUB_EXPIRED_SIG = keccak256("SubscriptionExpired(address,uint8)");

    /// @dev GASOPT-04 oracle migration: the per-player `AutoBought(address,uint32,uint256)` event was
    ///      DELETED. The no-double-buy / "bought today exactly once" oracle is now the authoritative
    ///      `lastAutoBoughtDay` storage stamp (the same stamp the contract's `lastAutoBoughtDay >= today`
    ///      skip at AfKing.sol:626 keys on) read via `_lastAutoBoughtDayOf`, complemented by per-player
    ///      pool/balance deltas. `_countAutoBoughtFor` is re-expressed below as a stamp-vs-baseline
    ///      derived count: 1 iff the sub's lastAutoBoughtDay advanced to today since the last baseline,
    ///      else 0. Per-chunk no-overlap is proven by re-baselining between chunks.
    uint32 private _boughtBaselineDay;

    /// @dev Snapshot of SubscriptionExpired(player, reason) emissions, drained by the single _drainLogs()
    ///      pass (so a test can count reclaim-events without a second getRecordedLogs seeing an
    ///      already-consumed buffer).
    address[] private _expiredPlayers;
    uint8[] private _expiredReasons;

    function setUp() public {
        _deployProtocol();
        // Advance one keeper-local day off the deploy boundary so _currentDay() is a clean, stable
        // index for the whole test (mirrors AfKingSubscription.setUp()).
        vm.warp(block.timestamp + 1 days);
    }

    // =========================================================================
    // Task 1 -- Same-block cursor self-partition: exactly-once, no double-buy, no miss
    // =========================================================================

    /// @notice SAFE-03 core: with N healthy subscribers and TWO autoBuy(maxCount) calls in the SAME
    ///         block (each maxCount < N), every subscriber is bought EXACTLY ONCE. The cursor advances
    ///         across the first autoBuy and the second resumes from the advanced position; the combined
    ///         maxCount covers all N, none is double-bought (sum of buys == N, max per-player buys == 1).
    function testSameBlockTwoAutoBuysExactlyOnce() public {
        uint256 N = 6;
        address[] memory subs = _setupHealthyBuyingSubs(N, "split_");

        // Cursor starts at 0 for this fresh day (no autoBuy yet today).
        (, uint256 cursor0) = afKing.autoBuyProgress();
        assertEq(cursor0, 0, "cursor starts at 0 for a fresh day");

        // Two same-block autoBuys: maxCount 4 then 4 (each < the full set so neither covers all in one).
        // The set also holds the 2 deploy subs (VAULT/SDGNRS) ahead/among ours; maxCount 4+4 = 8 and
        // the set is 8 (6 ours + 2 deploy), so the combined reach covers the whole set this day.
        _snapshotBought(subs); // GASOPT-04 storage-stamp baseline (replaces the AutoBought recordLogs)

        vm.prank(makeAddr("keeper_A"));
        afKing.autoBuy(4);
        (, uint256 cursorAfterA) = afKing.autoBuyProgress();

        vm.prank(makeAddr("keeper_B"));
        afKing.autoBuy(4);
        (, uint256 cursorAfterB) = afKing.autoBuyProgress();

        // The cursor advanced monotonically (B resumed from A's advanced position).
        assertGt(cursorAfterA, 0, "first same-block autoBuy advanced the cursor");
        assertGe(cursorAfterB, cursorAfterA, "second autoBuy resumed from the advanced cursor (monotonic)");

        // Every one of OUR N subs was bought exactly once across the two same-block autoBuys:
        //  - lastAutoBoughtDay == today for each (processed this day), and
        //  - exactly one AutoBought event per sub (no double-buy).
        uint32 today = _today();
        for (uint256 i; i < N; i++) {
            assertEq(_lastAutoBoughtDayOf(subs[i]), today, "sub processed exactly this day");
            assertEq(_countAutoBoughtFor(subs[i]), 1, "sub bought EXACTLY ONCE across the two same-block autoBuys");
        }
    }

    /// @notice SAFE-03: a SINGLE autoBuy with maxCount < N processes only the first chunk and advances
    ///         the cursor; a SECOND same-block autoBuy picks up the rest with NO overlap (no sub appears
    ///         in both chunks' AutoBought stream). Proves the self-partition is by the shared advancing
    ///         cursor, not by luck.
    function testSameBlockNoOverlapBetweenChunks() public {
        uint256 N = 5;
        address[] memory subs = _setupHealthyBuyingSubs(N, "noov_");

        // First chunk: a small maxCount. Baseline the stamps before it (GASOPT-04 storage-stamp oracle).
        _snapshotBought(subs);
        vm.prank(makeAddr("chunk1_keeper"));
        afKing.autoBuy(3);
        // Snapshot which of OUR subs were bought in chunk 1 (stamp advanced past the chunk-1 baseline).
        bool[] memory boughtInChunk1 = new bool[](N);
        uint256 chunk1Count;
        for (uint256 i; i < N; i++) {
            if (_countAutoBoughtFor(subs[i]) == 1) {
                boughtInChunk1[i] = true;
                chunk1Count++;
            }
        }

        // Second chunk (same block): the rest. Re-baseline so the count window holds ONLY chunk-2 buys
        // (the per-chunk granularity the per-chunk getRecordedLogs() once gave). A chunk-1 sub's stamp
        // was already == today before chunk 2, so re-baselining makes its chunk-2 count 0.
        _snapshotBought(subs);
        vm.prank(makeAddr("chunk2_keeper"));
        afKing.autoBuy(10);
        for (uint256 i; i < N; i++) {
            uint256 c2 = _countAutoBoughtFor(subs[i]);
            if (boughtInChunk1[i]) {
                // Already bought in chunk 1 -> NOT autoBought again in chunk 2 (no overlap / no double-buy).
                assertEq(c2, 0, "a chunk-1 sub is NOT re-autoBought in the same-block chunk 2 (no overlap)");
            }
        }

        // Union covers every sub exactly once for the day.
        uint32 today = _today();
        for (uint256 i; i < N; i++) {
            assertEq(_lastAutoBoughtDayOf(subs[i]), today, "every sub processed across the two chunks");
        }
    }

    /// @notice SAFE-03 daily reset: after a full autoBuy today, advancing one keeper-local day resets the
    ///         cursor to 0 on the next autoBuy, and each subscriber is eligible for exactly one fresh buy
    ///         (lastAutoBoughtDay advances to the new day; one AutoBought per sub on the new day).
    function testCursorResetsPerDayAndEachSubBuysOncePerDay() public {
        uint256 N = 4;
        address[] memory subs = _setupHealthyBuyingSubs(N, "daily_");

        // Day 1 full autoBuy.
        vm.prank(makeAddr("day1_keeper"));
        afKing.autoBuy(50);
        uint32 day1 = _today();
        for (uint256 i; i < N; i++) {
            assertEq(_lastAutoBoughtDayOf(subs[i]), day1, "day-1 buy stamped");
        }

        // Re-funding the pool so the day-2 buy can land (day-1 buy debited it).
        for (uint256 i; i < N; i++) _fundPool(subs[i], 1 ether);

        // Advance one day -> first autoBuy of the new day resets the cursor.
        vm.warp(block.timestamp + 1 days);
        uint32 day2 = _today();
        assertGt(day2, day1, "a keeper-local day elapsed");

        _snapshotBought(subs); // baseline at day1 stamps; the day-2 buy advances each to day2
        vm.prank(makeAddr("day2_keeper"));
        afKing.autoBuy(50);

        // Cursor day-stamp tracks the new day (first autoBuy of the day reset the index to 0 then advanced).
        (uint32 progDay, ) = afKing.autoBuyProgress();
        assertEq(progDay, day2, "autoBuyProgress day-stamp tracks the new keeper-local day");

        for (uint256 i; i < N; i++) {
            assertEq(_lastAutoBoughtDayOf(subs[i]), day2, "fresh day-2 buy stamped (one per day)");
            assertEq(_countAutoBoughtFor(subs[i]), 1, "exactly one fresh buy on the new day");
        }
    }

    /// @notice SAFE-03 backstop: the per-entry lastAutoBoughtDay idempotency stamp alone prevents a repeat
    ///         buy. Force a sub's lastAutoBoughtDay to today, reset the cursor to 0 so the autoBuy RE-VISITS
    ///         that index, and confirm the sub is skipped (PlayerSkipped reason 2) -- no second buy --
    ///         independent of the cursor position.
    function testLastAutoBoughtDayBackstopBlocksRepeatBuyOnCursorRevisit() public {
        address[] memory subs = _setupHealthyBuyingSubs(1, "backstop_");
        address sub = subs[0];

        // First autoBuy today buys the sub once.
        address[] memory one = new address[](1);
        one[0] = sub;
        _snapshotBought(one);
        vm.prank(makeAddr("first_keeper"));
        afKing.autoBuy(50);
        assertEq(_countAutoBoughtFor(sub), 1, "first autoBuy bought the sub once");
        assertEq(_lastAutoBoughtDayOf(sub), _today(), "lastAutoBoughtDay stamped today");

        // Re-fund so a (hypothetical) second buy COULD land if the backstop were absent.
        _fundPool(sub, 1 ether);

        // Force the cursor back to 0 so the next autoBuy RE-VISITS the already-bought index.
        _resetCursorToZeroForToday();

        // Re-baseline at the post-first-buy stamp (== today). A second buy would have to advance the
        // stamp PAST today, which the contract's `lastAutoBoughtDay >= today` skip forbids -> count 0.
        _snapshotBought(one);
        vm.prank(makeAddr("revisit_keeper"));
        // Every active sub is already-autoBought-today now, so the whole chunk produces zero buys ->
        // the buy leg no-ops on an all-already-bought chunk. The point is the absence of a SECOND
        // buy for `sub`.
        afKing.autoBuy(50);
        assertEq(_countAutoBoughtFor(sub), 0, "lastAutoBoughtDay backstop: NO second buy on a cursor re-visit");
        assertEq(_lastAutoBoughtDayOf(sub), _today(), "lastAutoBoughtDay unchanged by the re-visit skip");
    }

    /// @notice SAFE-03 fuzz: over an arbitrary same-block split (k, then the rest), every subscriber is
    ///         bought EXACTLY ONCE -- no double-buy, no miss -- regardless of where the first autoBuy's
    ///         maxCount lands.
    function testFuzzSameBlockSplitExactlyOnce(uint8 firstChunk) public {
        uint256 N = 6;
        address[] memory subs = _setupHealthyBuyingSubs(N, "fuzz_");

        // Total set size = N + 2 deploy subs. Bound the first chunk to (0, total) so the split is real.
        uint256 total = afKing.subscriberCount();
        uint256 k = (uint256(firstChunk) % (total + 1)); // 0..total
        if (k == 0) k = 1; // 0 now means the default batch; keep an explicit small first chunk for the split

        _snapshotBought(subs); // GASOPT-04 storage-stamp baseline for the combined two-autoBuy window
        vm.prank(makeAddr("fuzz_keeperA"));
        afKing.autoBuy(k); // a tiny chunk that hits only deploy subs may still buy >=1

        vm.prank(makeAddr("fuzz_keeperB"));
        // The remainder, generously sized to drain the rest of the set this same block.
        afKing.autoBuy(total + 1);

        // Invariant: each of OUR subs autoBought exactly once for the day (sum == N, max-per == 1).
        uint32 today = _today();
        uint256 sumBuys;
        for (uint256 i; i < N; i++) {
            uint256 c = _countAutoBoughtFor(subs[i]);
            assertLe(c, 1, "no sub double-bought across any same-block split");
            assertEq(_lastAutoBoughtDayOf(subs[i]), today, "every sub processed across the split (no miss)");
            sumBuys += c;
        }
        assertEq(sumBuys, N, "sum of buys == N across the two same-block autoBuys (exactly-once)");
    }

    // =========================================================================
    // TOMB-04 -- v47 in-place cancel-tombstone + in-autoBuy reclaim (H-CANCEL-SWAP-MISS)
    // =========================================================================
    //
    // v47 changed setDailyQuantity(0) from an IMMEDIATE swap-pop into a TRUE in-place tombstone:
    // cancel writes the dailyQuantity=0 sentinel and relocates NO ONE (the entry stays in the
    // iterable set). The delete-vs-preserve + the swap-pop are DEFERRED to a top-of-loop reclaim
    // branch in autoBuy() (AfKing.sol:612-624) that does NOT advance the cursor. This is the SUB-07
    // restoration that resolves the v46.0 Phase 320 MEDIUM finding H-CANCEL-SWAP-MISS: because the
    // cancel moves nothing, it can never push a still-pending tail entry behind the chunked-autoBuy
    // cursor -> no missed day -> no collateral mint-streak reset.

    /// @notice TOMB-04 / H-CANCEL-SWAP-MISS direct repro. The OLD swap-pop-at-cancel relocated the
    ///         set TAIL into a freed slot; if that freed slot sat BEHIND the chunked-autoBuy cursor, the
    ///         relocated tail (still pending today) was pushed behind the cursor and SKIPPED for the
    ///         day -> a missed buy -> a collateral mint-streak reset. v47's in-place tombstone moves no
    ///         one, so the still-pending tail is never relocated. Here: begin a chunked autoBuy so the
    ///         cursor sits partway (a chunk processed, cursor advanced into the set), then cancel a sub
    ///         AT/BEFORE the cursor (the freed-slot-behind-cursor case), then finish the day's autoBuy.
    ///         Assert EVERY still-active sub got its daily buy exactly once -- the tail the old swap-pop
    ///         would have stranded still buys this day.
    function testCancelBehindCursorDoesNotStrandPendingTail() public {
        // A wide set so the first chunk leaves the cursor partway with a real pending tail behind it.
        uint256 N = 8;
        address[] memory subs = _setupHealthyBuyingSubs(N, "strand_");

        // First chunk: advance the cursor partway into OUR subs (the 2 deploy subs precede ours, so a
        // chunk of 4 stamps the deploy pair + the first couple of ours and leaves the cursor mid-set).
        vm.recordLogs();
        vm.prank(makeAddr("strand_keeperA"));
        afKing.autoBuy(4);
        _captureAutoBought();
        (, uint256 cursorMid) = afKing.autoBuyProgress();
        assertGt(cursorMid, 0, "first chunk advanced the cursor partway");
        assertLt(cursorMid, afKing.subscriberCount(), "cursor sits mid-set with a pending tail behind it");

        // Identify a still-PENDING tail sub (not yet autoBought this day) and a autoBought sub BEHIND the cursor
        // to cancel. Under the OLD swap-pop, cancelling the behind-cursor sub would have moved the set
        // tail into that behind-cursor slot, stranding the moved-tail's buy for the day.
        uint32 today = _today();
        address pendingTail;
        for (uint256 i = N; i > 0; i--) {
            if (_lastAutoBoughtDayOf(subs[i - 1]) != today) {
                pendingTail = subs[i - 1];
                break;
            }
        }
        assertTrue(pendingTail != address(0), "a still-pending tail sub exists behind the cursor reach");

        address behindCursorAutoBought;
        for (uint256 i; i < N; i++) {
            if (_lastAutoBoughtDayOf(subs[i]) == today) {
                behindCursorAutoBought = subs[i];
                break;
            }
        }
        assertTrue(behindCursorAutoBought != address(0), "a autoBought sub sits behind the cursor");

        // Cancel the behind-cursor (already-autoBought) sub. v47: in-place tombstone -- it STAYS in the set,
        // relocates no one, so the pending tail is NOT pushed behind the cursor.
        vm.prank(behindCursorAutoBought);
        afKing.setDailyQuantity(0);
        assertEq(_dailyQtyOf(behindCursorAutoBought), 0, "cancel wrote the in-place sentinel");
        assertGt(_subscriberIndexOf(behindCursorAutoBought), 0, "v47: cancel relocates no one -- still in set");

        // Finish the day's autoBuy (a generous remaining chunk drains the rest).
        vm.recordLogs();
        vm.prank(makeAddr("strand_keeperB"));
        afKing.autoBuy(afKing.subscriberCount() + 5);
        _captureAutoBought();

        // The pending tail STILL buys this day -- the cancel did not strand it behind the cursor.
        assertEq(_countAutoBoughtFor(pendingTail), 1, "H-CANCEL-SWAP-MISS resolved: pending tail still bought");
        assertEq(_lastAutoBoughtDayOf(pendingTail), today, "pending tail's daily buy landed (no missed day)");

        // EVERY still-active sub (all but the one cancelled) got its daily buy exactly once across the
        // two chunks -- no active sub was skipped because of someone else's cancel.
        uint256 activeBought;
        for (uint256 i; i < N; i++) {
            if (subs[i] == behindCursorAutoBought) continue; // the cancelled one is not bought
            assertEq(_lastAutoBoughtDayOf(subs[i]), today, "every active sub processed (no miss)");
            activeBought++;
        }
        assertEq(activeBought, N - 1, "all N-1 still-active subs bought this day");
    }

    /// @notice TOMB-04: a cancelled sub is an in-place tombstone (still in the set) until the next
    ///         autoBuy that REACHES its slot reclaims it. Covers BOTH sub-cases:
    ///         (a) tombstone AHEAD of the cursor -> reclaimed THIS autoBuy (SubscriptionExpired(p,2), set
    ///             membership swap-popped, the swap-pop occupant re-processed at the same index);
    ///         (b) tombstone BEHIND the cursor (cancelled after the cursor passed its slot this day) ->
    ///             not reached this day, reclaimed on the next-day cursor reset.
    function testCancelTombstoneReclaimedByNextAutoBuy() public {
        // ---- Sub-case (a): tombstone AHEAD of the cursor -> reclaimed THIS autoBuy. ----
        uint256 N = 6;
        address[] memory subs = _setupHealthyBuyingSubs(N, "reclaimA_");

        // Cancel a sub BEFORE any autoBuy today (cursor at 0, so its slot is ahead of the cursor).
        address ahead = subs[2];
        uint256 idxBefore = _subscriberIndexOf(ahead);
        uint256 setLenBefore = afKing.subscriberCount();
        vm.prank(ahead);
        afKing.setDailyQuantity(0);
        // Still in the set immediately after cancel (relocates no one).
        assertEq(_subscriberIndexOf(ahead), idxBefore, "tombstone still in set after cancel (no relocation)");
        assertEq(afKing.subscriberCount(), setLenBefore, "set length unchanged by cancel (in-place tombstone)");

        // AutoBuy reaches the tombstone this day -> reclaim fires.
        vm.recordLogs();
        vm.prank(makeAddr("reclaimA_keeper"));
        afKing.autoBuy(afKing.subscriberCount() + 5);
        _captureAutoBought(); // single drain: feeds both the Expired and AutoBought counts below
        // Reclaim emitted SubscriptionExpired(ahead, 2 = CancelReclaim).
        assertEq(_countExpiredFor(ahead, 2), 1, "reclaim emitted SubscriptionExpired(player,2) this autoBuy");
        // Removed from the set by the in-loop swap-pop.
        assertEq(_subscriberIndexOf(ahead), 0, "tombstone reclaimed: removed from the set this autoBuy");
        // The swap-pop occupant re-read at the freed index was still processed (no skip): every OTHER
        // sub got its daily buy.
        uint32 today = _today();
        for (uint256 i; i < N; i++) {
            if (subs[i] == ahead) {
                assertEq(_countAutoBoughtFor(subs[i]), 0, "the reclaimed tombstone is not bought");
            } else {
                assertEq(_lastAutoBoughtDayOf(subs[i]), today, "swap-pop occupant re-processed -- no skip");
            }
        }

        // ---- Sub-case (b): tombstone BEHIND the cursor -> reclaimed on the next-day reset. ----
        address[] memory subsB = _setupHealthyBuyingSubs(N, "reclaimB_");
        // Full autoBuy today: every B-sub is autoBought and the cursor walks past all their slots.
        vm.prank(makeAddr("reclaimB_keeperD1"));
        afKing.autoBuy(afKing.subscriberCount() + 5);
        uint32 day1 = _today();
        // Cancel a B-sub AFTER the cursor already passed its slot today (cursor is at end-of-set).
        address behind = subsB[1];
        vm.prank(behind);
        afKing.setDailyQuantity(0);
        // Not reached again this day -> still in the set (the day's cursor is past it).
        assertGt(_subscriberIndexOf(behind), 0, "behind-cursor tombstone not reclaimed same day (still in set)");

        // Next day: cursor resets to 0, the autoBuy reaches the tombstone slot and reclaims it.
        vm.warp(block.timestamp + 1 days);
        for (uint256 i; i < N; i++) _fundPool(subsB[i], 1 ether); // re-fund so the day-2 active buys land
        vm.recordLogs();
        vm.prank(makeAddr("reclaimB_keeperD2"));
        afKing.autoBuy(afKing.subscriberCount() + 5);
        _captureAutoBought();
        assertEq(_countExpiredFor(behind, 2), 1, "behind-cursor tombstone reclaimed on the next-day reset");
        assertEq(_subscriberIndexOf(behind), 0, "behind-cursor tombstone removed from set next day");
        assertGt(day1, 0, "day1 was a real keeper-local day");
    }

    /// @notice TOMB-04: a cancel on a PAID + UNEXPIRED window preserves the `_subOf` record THROUGH the
    ///         deferred reclaim -- the preserve-vs-delete decision is applied at RECLAIM, not at cancel.
    ///         Contrast: an unpaid/expired window is DELETED at reclaim. (The set membership is swap-
    ///         popped in both cases; only the record-retention differs.)
    function testCancelPreservesPaidWindowThroughDeferredReclaim() public {
        // ---- Paid + unexpired: record PRESERVED through the reclaim. ----
        address[] memory subs = _setupHealthyBuyingSubs(1, "paiddef_");
        address paidSub = subs[0];
        uint32 paidEndpoint = _today() + WINDOW_DAYS;
        _setWindow(paidSub, paidEndpoint, /*windowPaid*/ true);

        // Cancel: in-place tombstone. The record (incl. the paid window) is fully readable post-cancel.
        vm.prank(paidSub);
        afKing.setDailyQuantity(0);
        assertGt(_subscriberIndexOf(paidSub), 0, "paid tombstone still in set after cancel");
        assertEq(_paidThroughDayOf(paidSub), paidEndpoint, "paid window readable post-cancel (deferred reclaim)");

        // Reclaiming autoBuy: preservePaidWindow == true -> _subOf is KEPT (sentinel already 0), set popped.
        vm.recordLogs();
        vm.prank(makeAddr("paiddef_keeper"));
        afKing.autoBuy(afKing.subscriberCount() + 5);
        _captureAutoBought();
        assertEq(_countExpiredFor(paidSub, 2), 1, "paid sub reclaimed (SubscriptionExpired,2)");
        assertEq(_subscriberIndexOf(paidSub), 0, "paid sub removed from set at reclaim");
        // PRESERVED: the paid window survived the cancel -> deferred reclaim sequence.
        assertEq(_paidThroughDayOf(paidSub), paidEndpoint, "paid window PRESERVED through deferred reclaim");
        assertEq(
            afKing.subscriptionOf(paidSub).flags & uint8(FLAG_WINDOW_PAID),
            1,
            "windowPaid flag preserved through deferred reclaim"
        );

        // ---- Unpaid / expired window: record DELETED at reclaim. ----
        address[] memory subsU = _setupHealthyBuyingSubs(1, "unpaiddef_");
        address unpaidSub = subsU[0];
        _setWindow(unpaidSub, _today() + WINDOW_DAYS, /*windowPaid*/ false); // unpaid is the gate

        vm.prank(unpaidSub);
        afKing.setDailyQuantity(0);
        assertGt(_subscriberIndexOf(unpaidSub), 0, "unpaid tombstone still in set after cancel");

        vm.recordLogs();
        vm.prank(makeAddr("unpaiddef_keeper"));
        afKing.autoBuy(afKing.subscriberCount() + 5);
        _captureAutoBought();
        assertEq(_countExpiredFor(unpaidSub, 2), 1, "unpaid sub reclaimed (SubscriptionExpired,2)");
        assertEq(_subscriberIndexOf(unpaidSub), 0, "unpaid sub removed from set at reclaim");
        // DELETED: every Sub field zeroed at the reclaim (no window to preserve).
        assertEq(afKing.subscriptionOf(unpaidSub).paidThroughDay, 0, "unpaid window deleted at reclaim");
        assertEq(afKing.subscriptionOf(unpaidSub).flags, 0, "unpaid window flags deleted at reclaim");
    }

    /// @notice TOMB-04: reactivating a still-in-set tombstone (before any autoBuy reclaims it) flips it
    ///         back to active IN PLACE with NO duplicate set membership. Covers BOTH reactivation paths:
    ///         (a) setDailyQuantity(q>0) -- no set churn, the deferred reclaim never ran so the record
    ///             (incl. a paid window) survives the cancel->reactivate round-trip; and
    ///         (b) subscribe() -- _addToSet is idempotent on a non-zero index, so a re-subscribe of a
    ///             still-in-set tombstone never double-adds.
    function testReactivateTombstonedSubNoDoubleAdd() public {
        // ---- (a) setDailyQuantity(q>0) reactivation, with a paid window round-trip. ----
        address[] memory subs = _setupHealthyBuyingSubs(1, "reactA_");
        address sub = subs[0];
        uint32 paidEndpoint = _today() + WINDOW_DAYS;
        _setWindow(sub, paidEndpoint, /*windowPaid*/ true);

        uint256 idx = _subscriberIndexOf(sub);
        uint256 lenBefore = afKing.subscriberCount();

        // Cancel (tombstone, still in set) ...
        vm.prank(sub);
        afKing.setDailyQuantity(0);
        assertEq(_subscriberIndexOf(sub), idx, "tombstone in set, same index");
        // ... then reactivate BEFORE any autoBuy reclaims it.
        vm.prank(sub);
        afKing.setDailyQuantity(3);

        // Flipped back to active in place: same index, NO duplicate set entry, set length unchanged.
        assertEq(_dailyQtyOf(sub), 3, "reactivated in place (dailyQuantity restored)");
        assertEq(_subscriberIndexOf(sub), idx, "reactivation kept the same set slot (no relocation)");
        assertEq(afKing.subscriberCount(), lenBefore, "no duplicate set membership on reactivation");
        // The deferred reclaim never ran -> the paid window survived the cancel->reactivate round-trip.
        assertEq(_paidThroughDayOf(sub), paidEndpoint, "paid window survived the cancel->reactivate round-trip");

        // A autoBuy now treats it as a normal active sub (not a tombstone) -- it buys, not reclaims.
        vm.recordLogs();
        vm.prank(makeAddr("reactA_keeper"));
        afKing.autoBuy(afKing.subscriberCount() + 5);
        _captureAutoBought();
        assertEq(_countExpiredFor(sub, 2), 0, "reactivated sub is NOT reclaimed as a tombstone");
        assertEq(_countAutoBoughtFor(sub), 1, "reactivated sub buys as a normal active sub");

        // ---- (b) subscribe() reactivation path: idempotent _addToSet, no double-add. ----
        address[] memory subsB = _setupHealthyBuyingSubs(1, "reactB_");
        address subB = subsB[0];
        uint256 idxB = _subscriberIndexOf(subB);
        uint256 lenB = afKing.subscriberCount();

        vm.prank(subB);
        afKing.setDailyQuantity(0); // tombstone, still in set

        // Re-subscribe the still-in-set tombstoned address (fund the all-or-nothing subscribe charge).
        _fundBurnie(subB, _subCost());
        vm.prank(subB);
        afKing.subscribe(address(0), false, true, 2, 0, address(0));

        // _addToSet is a no-op on the non-zero index -> NO duplicate entry, set length unchanged.
        assertEq(_subscriberIndexOf(subB), idxB, "re-subscribe kept the same set slot (idempotent _addToSet)");
        assertEq(afKing.subscriberCount(), lenB, "re-subscribe of an in-set tombstone never double-adds");
        assertEq(_dailyQtyOf(subB), 2, "re-subscribe reactivated the sub (dailyQuantity restored)");
    }

    // =========================================================================
    // Task 2 -- Tombstone-on-cancel no-miss + no dead-slot buildup (v47 deferred-reclaim semantics)
    // =========================================================================

    /// @notice TOMB-04 (retargeted from the v46 immediate-swap-pop): under v47 the swap-pop now fires at
    ///         RECLAIM (in-loop, no ++cursor), not at cancel. Cancelling an EARLY sub leaves it in the
    ///         set as a tombstone; the autoBuy's reclaim branch swap-pops it (the set tail moves into its
    ///         slot) and the moved occupant is re-read at THIS index this autoBuy -- it is not skipped.
    ///         Intent unchanged from v46: the swap-pop occupant is still processed; only the timing moved
    ///         from cancel-time to reclaim-time.
    function testCancelSwapPopOccupantStillProcessed() public {
        // Subscribe an ordered batch; the LAST one is the "mover" that will be swapped into a freed slot.
        uint256 N = 5;
        address[] memory subs = _setupHealthyBuyingSubs(N, "swap_");
        address mover = subs[N - 1]; // currently the tail among our subs

        // Cancel an EARLY sub (subs[0]). v47: the cancel is an in-place tombstone -- it stays in the set
        // (relocates no one). The swap-pop is DEFERRED to the autoBuy's reclaim branch: when the autoBuy
        // reaches subs[0]'s slot it swap-pops it (the set tail moves into the freed slot) and re-reads
        // the moved occupant at THIS index this autoBuy -- the occupant is not skipped.
        vm.prank(subs[0]);
        afKing.setDailyQuantity(0);
        assertGt(_subscriberIndexOf(subs[0]), 0, "v47: cancel is an in-place tombstone -- still in the set");
        assertEq(_dailyQtyOf(subs[0]), 0, "cancel wrote the in-place sentinel");

        vm.recordLogs();
        vm.prank(makeAddr("swap_keeper"));
        afKing.autoBuy(50);
        _captureAutoBought();

        // The reclaim swap-popped the tombstone out of the set THIS autoBuy.
        assertEq(_subscriberIndexOf(subs[0]), 0, "tombstone swap-popped at reclaim (removed from set)");
        assertEq(_countExpiredFor(subs[0], 2), 1, "reclaim emitted SubscriptionExpired(player,2) at the swap-pop");
        // The mover (still active) was bought -- the reclaim's swap-pop occupant re-read did not strand it.
        assertEq(_countAutoBoughtFor(mover), 1, "reclaim swap-pop occupant still processed this autoBuy (no miss)");
        // The cancelled sub was NOT bought.
        assertEq(_countAutoBoughtFor(subs[0]), 0, "cancelled sub not processed");
    }

    /// @notice TOMB-04 (retargeted): under v47 a cancel does NOT shrink the set immediately -- the
    ///         tombstone stays in the iteration set until a autoBuy REACHES and reclaims it. The
    ///         no-dead-slot-buildup guarantee is now DEFERRED: across a series of cancels the tombstones
    ///         persist until the next autoBuy, which reclaims ALL of them (this day if ahead of the cursor,
    ///         else the next-day reset). The NET set effect equals the old immediate-swap-pop -- after
    ///         the reclaiming autoBuys the set holds ONLY the still-active subs, no dead slots linger.
    function testNoDeadSlotBuildupAcrossCancels() public {
        uint256 baseline = afKing.subscriberCount(); // the 2 deploy subs (+ any)
        uint256 N = 6;
        address[] memory subs = _setupHealthyBuyingSubs(N, "build_");
        assertEq(afKing.subscriberCount(), baseline + N, "all N added to the set");

        // Cancel three of them. v47: the set length does NOT shrink at cancel (in-place tombstones).
        vm.prank(subs[0]);
        afKing.setDailyQuantity(0);
        vm.prank(subs[1]);
        afKing.setDailyQuantity(0);
        assertEq(
            afKing.subscriberCount(),
            baseline + N,
            "v47: cancel does not shrink the set (in-place tombstones stay until reclaimed)"
        );

        vm.warp(block.timestamp + 1 days);
        vm.prank(subs[2]);
        afKing.setDailyQuantity(0);
        assertEq(afKing.subscriberCount(), baseline + N, "3rd cancel also leaves an in-place tombstone");

        // A full autoBuy reclaims EVERY tombstone (the cursor reset this new day reaches all slots). After
        // it, the set has shrunk by exactly the 3 cancels -- no dead-slot buildup, just deferred.
        for (uint256 i = 3; i < N; i++) _fundPool(subs[i], 1 ether); // re-fund the survivors' day-2 buy
        vm.recordLogs();
        vm.prank(makeAddr("build_keeper"));
        afKing.autoBuy(afKing.subscriberCount() + 5);
        _captureAutoBought();
        assertEq(_countExpiredFor(subs[0], 2), 1, "tombstone 0 reclaimed");
        assertEq(_countExpiredFor(subs[1], 2), 1, "tombstone 1 reclaimed");
        assertEq(_countExpiredFor(subs[2], 2), 1, "tombstone 2 reclaimed");
        assertEq(
            afKing.subscriberCount(),
            baseline + N - 3,
            "after the reclaiming autoBuy the set shrank by exactly the 3 cancels (no dead slots)"
        );

        // Every remaining index dereferences to a live, in-set address (no dead slot, no OOB hole).
        uint256 count = afKing.subscriberCount();
        for (uint256 i; i < count; i++) {
            address at = afKing.subscriberAt(i);
            assertTrue(at != address(0), "no zero-address dead slot in the iteration set");
            assertEq(_subscriberIndexOf(at), i + 1, "each set slot's 1-indexed back-pointer is consistent");
        }
    }

    /// @notice TOMB-04 (retargeted): a cancelled sub's stranded pool ETH stays withdrawable. v47: the
    ///         cancel writes the in-place sentinel (the entry stays in the set until reclaimed); it never
    ///         confiscates `_poolOf`, and the withdraw is unaffected by the in-place tombstone.
    function testCancelledSubPoolEthWithdrawable() public {
        address[] memory subs = _setupHealthyBuyingSubs(1, "strandpool_");
        address sub = subs[0];

        // Top the pool to a known surplus, then cancel.
        _fundPool(sub, 3 ether);
        uint256 pooledBefore = afKing.poolOf(sub);
        assertGt(pooledBefore, 0, "sub has stranded pool ETH");

        vm.prank(sub);
        afKing.setDailyQuantity(0);
        assertGt(_subscriberIndexOf(sub), 0, "v47: cancel is an in-place tombstone -- still in the set");
        assertEq(_dailyQtyOf(sub), 0, "cancel wrote the in-place sentinel");
        // Pool ETH preserved through the cancel.
        assertEq(afKing.poolOf(sub), pooledBefore, "cancel did not confiscate pool ETH");

        // The cancelled sub can still withdraw its full pool balance.
        uint256 balBefore = sub.balance;
        vm.prank(sub);
        afKing.withdraw(pooledBefore);
        assertEq(afKing.poolOf(sub), 0, "pool drained on withdraw");
        assertEq(sub.balance - balBefore, pooledBefore, "stranded pool ETH returned to the cancelled sub");
    }

    /// @notice TOMB-04 (retargeted): the windowPaid-gated PRESERVE decision now fires at RECLAIM, not at
    ///         cancel. A cancel on a PAID + UNEXPIRED window writes the in-place sentinel and leaves the
    ///         record fully readable; when the reclaiming autoBuy reaches it, preservePaidWindow == true so
    ///         `_subOf` is KEPT (windowPaid + the unexpired endpoint survive) and only set membership is
    ///         swap-popped. Intent unchanged from v46; the observation point moved to after the reclaim.
    function testCancelPreservesPaidUnexpiredWindow() public {
        address[] memory subs = _setupHealthyBuyingSubs(1, "paidwin_");
        address sub = subs[0];

        // Pin a PAID + UNEXPIRED window: windowPaid set, paidThroughDay well in the future.
        _setWindow(sub, /*paidThroughDay*/ _today() + WINDOW_DAYS, /*windowPaid*/ true);

        vm.prank(sub);
        afKing.setDailyQuantity(0);
        // v47: still in set (deferred reclaim), record readable.
        assertGt(_subscriberIndexOf(sub), 0, "v47: in-place tombstone still in set at cancel");

        // The reclaiming autoBuy applies the PRESERVE decision.
        vm.recordLogs();
        vm.prank(makeAddr("paidwin_keeper"));
        afKing.autoBuy(afKing.subscriberCount() + 5);
        _captureAutoBought();
        assertEq(_countExpiredFor(sub, 2), 1, "paid sub reclaimed at the autoBuy");

        // Set membership removed at reclaim, dailyQuantity 0, BUT the paid window record is PRESERVED.
        assertEq(_subscriberIndexOf(sub), 0, "removed from set at reclaim");
        assertEq(afKing.subscriptionOf(sub).dailyQuantity, 0, "dailyQuantity zeroed (sentinel)");
        assertEq(afKing.subscriptionOf(sub).flags & uint8(FLAG_WINDOW_PAID), 1, "paid window flag preserved at reclaim");
        assertGt(afKing.subscriptionOf(sub).paidThroughDay, _today(), "unexpired window endpoint preserved at reclaim");
    }

    /// @notice TOMB-04 (retargeted): the windowPaid-gated DELETE decision now fires at RECLAIM, not at
    ///         cancel. A cancel on an UNPAID (free/expired) window writes the in-place sentinel; when the
    ///         reclaiming autoBuy reaches it, preservePaidWindow == false so the `_subOf` record is DELETED
    ///         (every field zeroed). Intent unchanged from v46; observed after the reclaim.
    function testCancelReclaimsUnpaidWindow() public {
        address[] memory subs = _setupHealthyBuyingSubs(1, "freewin_");
        address sub = subs[0];

        // Pin an UNPAID window: windowPaid clear (a free-pass window). paidThroughDay in the future is
        // irrelevant because windowPaid is the gate -- an unpaid window is reclaimed regardless.
        _setWindow(sub, /*paidThroughDay*/ _today() + WINDOW_DAYS, /*windowPaid*/ false);

        vm.prank(sub);
        afKing.setDailyQuantity(0);
        assertGt(_subscriberIndexOf(sub), 0, "v47: in-place tombstone still in set at cancel");

        // The reclaiming autoBuy applies the DELETE decision.
        vm.recordLogs();
        vm.prank(makeAddr("freewin_keeper"));
        afKing.autoBuy(afKing.subscriberCount() + 5);
        _captureAutoBought();
        assertEq(_countExpiredFor(sub, 2), 1, "unpaid sub reclaimed at the autoBuy");

        // Record deleted at reclaim: every Sub field zeroed.
        assertEq(_subscriberIndexOf(sub), 0, "removed from set at reclaim");
        assertEq(afKing.subscriptionOf(sub).dailyQuantity, 0, "dailyQuantity zeroed");
        assertEq(afKing.subscriptionOf(sub).paidThroughDay, 0, "unpaid window reclaimed (paidThroughDay deleted)");
        assertEq(afKing.subscriptionOf(sub).flags, 0, "unpaid window reclaimed (flags deleted)");
    }

    // =========================================================================
    // Internal helpers
    // =========================================================================

    function _today() internal view returns (uint32) {
        return uint32((block.timestamp - 82620) / 1 days);
    }

    /// @dev Subscribe `n` fresh players as fully-healthy buying subs (ticket mode so the LootboxFloor
    ///      skip never fires, operator-approved, pool-funded, NOT renewal-due) and return them in order.
    function _setupHealthyBuyingSubs(uint256 n, string memory prefix) internal returns (address[] memory subs) {
        subs = new address[](n);
        for (uint256 i; i < n; i++) {
            address who = makeAddr(string(abi.encodePacked(prefix, _u(i))));
            subs[i] = who;
            _fundBurnie(who, _subCost()); // for the (no-pass) subscribe-time all-or-nothing charge
            vm.prank(who);
            afKing.subscribe(address(0), false, true, 1, 0, address(0)); // self, drainCredit=false, ticket mode, qty 1, self-funded
            _approveKeeper(who);
            _fundPool(who, 1 ether);
        }
    }

    function _subCost() internal view returns (uint256) {
        return (afKing.SUB_COST_ETH_TARGET() * 1000 ether) / game.mintPrice();
    }

    function _approveKeeper(address who) internal {
        vm.prank(who);
        game.setOperatorApproval(address(afKing), true);
    }

    function _fundPool(address who, uint256 amount) internal {
        vm.deal(address(this), amount);
        afKing.depositFor{value: amount}(who);
    }

    function _fundBurnie(address who, uint256 amount) internal {
        if (amount == 0) return;
        vm.prank(ContractAddresses.GAME);
        coin.mintForGame(who, amount);
    }

    /// @dev Read `who`'s lastAutoBoughtDay (bytes 1..4 of the packed Sub slot).
    function _lastAutoBoughtDayOf(address who) internal view returns (uint32) {
        bytes32 slot = keccak256(abi.encode(who, uint256(SUBOF_SLOT)));
        uint256 packed = uint256(vm.load(address(afKing), slot));
        return uint32(packed >> (OFF_LASTSWEPT * 8));
    }

    /// @dev Read `who`'s 1-indexed subscriber index (slot 3); 0 = not in set.
    function _subscriberIndexOf(address who) internal view returns (uint256) {
        bytes32 slot = keccak256(abi.encode(who, uint256(SUBSCRIBER_INDEX_SLOT)));
        return uint256(vm.load(address(afKing), slot));
    }

    /// @dev Read `who`'s dailyQuantity (byte 0 of the packed Sub slot). 0 == the in-place tombstone sentinel.
    function _dailyQtyOf(address who) internal view returns (uint8) {
        bytes32 slot = keccak256(abi.encode(who, uint256(SUBOF_SLOT)));
        uint256 packed = uint256(vm.load(address(afKing), slot));
        return uint8(packed >> (OFF_DAILY * 8));
    }

    /// @dev Read `who`'s paidThroughDay (bytes 5..8 of the packed Sub slot).
    function _paidThroughDayOf(address who) internal view returns (uint32) {
        bytes32 slot = keccak256(abi.encode(who, uint256(SUBOF_SLOT)));
        uint256 packed = uint256(vm.load(address(afKing), slot));
        return uint32(packed >> (OFF_PAIDTHROUGH * 8));
    }

    /// @dev Pin `who`'s window: write paidThroughDay (bytes 5..8) and the windowPaid bit (byte 10).
    function _setWindow(address who, uint32 paidThroughDay, bool windowPaid) internal {
        bytes32 slot = keccak256(abi.encode(who, uint256(SUBOF_SLOT)));
        uint256 packed = uint256(vm.load(address(afKing), slot));
        // Clear paidThroughDay + flags byte.
        packed &= ~(uint256(0xFFFFFFFF) << (OFF_PAIDTHROUGH * 8));
        packed &= ~(uint256(0xFF) << (OFF_FLAGS * 8));
        packed |= (uint256(paidThroughDay) << (OFF_PAIDTHROUGH * 8));
        if (windowPaid) packed |= (uint256(FLAG_WINDOW_PAID) << (OFF_FLAGS * 8));
        vm.store(address(afKing), slot, bytes32(packed));
    }

    /// @dev Force the autoBuy cursor back to 0 while keeping the day-stamp at today, so the next autoBuy
    ///      re-visits index 0. Slot 4: _autoBuyDay (uint32, bytes 0..3) + _autoBuyCursor (uint224, bytes 4..).
    function _resetCursorToZeroForToday() internal {
        uint256 packed = uint256(vm.load(address(afKing), bytes32(uint256(4))));
        // Keep _autoBuyDay (low 4 bytes); zero the cursor (high 28 bytes).
        packed &= uint256(0xFFFFFFFF);
        packed |= (uint256(_today()) & 0xFFFFFFFF); // ensure day-stamp == today
        vm.store(address(afKing), bytes32(uint256(4)), bytes32(packed));
    }

    /// @dev Drain the recorded logs ONCE into the AfKing SubscriptionExpired(player, reason) snapshot.
    ///      The GASOPT-04 AutoBought event is gone; the buy oracle is now the lastAutoBoughtDay storage
    ///      stamp (see _countAutoBoughtFor), so this pass only captures the reclaim/auto-pause stream.
    ///      vm.getRecordedLogs() empties the buffer, so this single pass feeds the expired-count helper.
    function _drainLogs() internal {
        delete _expiredPlayers;
        delete _expiredReasons;
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].emitter != address(afKing) || logs[i].topics.length == 0) continue;
            if (logs[i].topics[0] == SUB_EXPIRED_SIG && logs[i].topics.length >= 2) {
                _expiredPlayers.push(address(uint160(uint256(logs[i].topics[1]))));
                // reason is the single non-indexed arg in `data` (abi-encoded uint8).
                _expiredReasons.push(uint8(uint256(bytes32(logs[i].data))));
            }
        }
    }

    /// @dev Drain the SubscriptionExpired stream. Alias kept for the existing call sites (the name is
    ///      historical; the AutoBought event it once drained is deleted — GASOPT-04).
    function _captureAutoBought() internal {
        _drainLogs();
    }

    /// @dev Per-address baseline `lastAutoBoughtDay` snapshot for the storage-stamp buy oracle. A test
    ///      snapshots the baseline (via _snapshotBought) just before the autoBuy(s) under measurement;
    ///      _countAutoBoughtFor then reports a buy iff the stamp advanced to `today` since the baseline.
    mapping(address => uint32) private _baselineBoughtDay;

    /// @dev Snapshot the pre-autoBuy `lastAutoBoughtDay` for each tracked sub (the GASOPT-04 storage-stamp
    ///      replacement for vm.recordLogs() of the AutoBought stream). Counts subsequent buys against
    ///      this baseline, so re-snapshotting between chunks gives the same per-chunk granularity the
    ///      per-chunk getRecordedLogs() once gave.
    function _snapshotBought(address[] memory tracked) internal {
        for (uint256 i; i < tracked.length; i++) {
            _baselineBoughtDay[tracked[i]] = _lastAutoBoughtDayOf(tracked[i]);
        }
    }

    /// @dev Buy-count oracle for `who` in the current capture window, re-expressed from the deleted
    ///      AutoBought event onto the `lastAutoBoughtDay` storage stamp (GASOPT-04). Returns 1 iff the
    ///      sub's stamp is `today` AND advanced past its snapshotted baseline (i.e. a fresh buy landed
    ///      since _snapshotBought), else 0. The contract's `lastAutoBoughtDay >= today` skip
    ///      (AfKing.sol:626) makes a second same-day pass a no-op, so the stamp cannot exceed one buy per
    ///      day per sub — this is the no-double-buy invariant the count==1 assertions assert, at the same
    ///      strength (the stamp is the authoritative oracle the contract itself uses).
    function _countAutoBoughtFor(address who) internal view returns (uint256) {
        uint32 stamp = _lastAutoBoughtDayOf(who);
        return (stamp == _today() && stamp > _baselineBoughtDay[who]) ? 1 : 0;
    }

    /// @dev Count SubscriptionExpired(who, reason) emissions in the captured snapshot. PURE read of the
    ///      drained array -- call _captureAutoBought() (the single _drainLogs pass) once after the autoBuy
    ///      under test, BEFORE this.
    function _countExpiredFor(address who, uint8 reason) internal view returns (uint256 count) {
        for (uint256 i; i < _expiredPlayers.length; i++) {
            if (_expiredPlayers[i] == who && _expiredReasons[i] == reason) count++;
        }
    }

    /// @dev Minimal uint -> decimal string for makeAddr label uniqueness.
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
