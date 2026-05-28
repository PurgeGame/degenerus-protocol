// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @title AfKingConcurrency -- Proves SAFE-03 autoBuy concurrency-correctness for the AF_KING keeper:
///        two same-block autoBuy(maxCount) callers self-partition via the advancing `_autoBuyCursor`
///        plus the per-entry `lastAutoBoughtDay` idempotency backstop, AND (TOMB-04 / v50.0
///        AFSUB-05) the in-place cancel-tombstone + in-autoBuy deferred reclaim relocates no one
///        (resolving H-CANCEL-SWAP-MISS), leaves no dead-slot buildup, and skips no active subscriber.
///
/// @notice The autoBuy is PERMISSIONLESS and CONCURRENT -- multiple keepers/craners can call autoBuy in
///         the SAME block. SAFE-03 is the concurrency floor:
///   - Same-block self-partition (Task 1, SUB-03): with N active subs and two autoBuy(maxCount) calls
///     in the same block (each maxCount < N so neither covers all at once), every subscriber is
///     bought EXACTLY ONCE across the two autoBuys.
///   - Daily cursor reset: the first autoBuy of a NEW keeper-local day restarts the cursor at 0, and
///     the per-entry lastAutoBoughtDay gates the fresh-day buy (one buy per sub per day).
///   - lastAutoBoughtDay backstop alone: even if a autoBuy re-visits an index already bought today
///     (cursor position notwithstanding), the day-stamp prevents a second buy.
///   - In-place cancel-tombstone no-miss (TOMB-04 / Task 2, SUB-07): v47 setDailyQuantity(0) is a
///     TRUE in-place tombstone -- it writes the dailyQuantity=0 sentinel and relocates NO ONE (the
///     entry stays in the iterable set). The swap-pop is DEFERRED to a top-of-loop reclaim branch in
///     autoBuy() that does NOT advance the cursor, so the swap-pop occupant is re-read at the freed
///     index THIS autoBuy -- no active sub is skipped. Because the cancel moves nothing, it can
///     never push a still-pending tail entry behind the chunked cursor (H-CANCEL-SWAP-MISS resolved).
///   - v50.0 AFSUB-05: the same swap-pop / tombstone shape also handles the AFSUB-03 EVICT path
///     (a no-pass crossing eviction), routing the eviction through `dailyQuantity = 0; _removeFromSet`
///     -- Pitfall P6 / 334-DESIGN-LOCK-AFKING §6.3. The cancel-reclaim path (the in-autoBuy reclaim
///     of an externally-cancelled `dailyQuantity == 0` tombstone) under v50.0 ALWAYS deletes _subOf:
///     the v47 `preservePaidWindow` branch is DROPPED (AFSUB-01 retired the BURNIE-prepaid window
///     so there is no window-state to preserve through a deferred reclaim).
///
/// @dev Builds on the 318-01-repaired DeployProtocol fixture (AfKing live at AF_KING; the two SUB-09
///      self-subscribes VAULT + SDGNRS already in the set). Test subs are driven through the public
///      subscribe() API. Test-only: no contracts/*.sol mutated.
///
/// @dev v50.0 D-IMPL-02 storage migration: the v49 day-keyed renewal field at Sub offset 5 is
///      repurposed in place to `Sub.validThroughLevel` (same offset, same uint32 width — Plan
///      335-04 Task 1). The slot-poke helpers (`_setValidThroughLevel`) work against the renamed
///      field. `flags` bit 0 (the v49 FLAG_WINDOW_PAID) is FREED under AFSUB-01 — tests that
///      previously asserted against it migrate to assert ONLY the post-reclaim record state.
contract AfKingConcurrency is DeployProtocol {
    // -------------------------------------------------------------------------
    // AfKing pinned 4-slot layout + Sub packed-field offsets (per AfKing.sol)
    // -------------------------------------------------------------------------
    uint256 private constant SUBOF_SLOT = 1;          // _subOf mapping root (address => Sub, one slot)
    uint256 private constant SUBSCRIBER_INDEX_SLOT = 3; // _subscriberIndex mapping root (1-indexed)

    // Sub packed-field byte offsets re-derived from the post-AFSUB layout: slot offset 5 is
    // repurposed in-place to `uint32 validThroughLevel` (v50.0 / Plan 335-04). The two standalone
    // bools were collapsed into `flags` (v47 OPENE-01) and a 20-byte `fundingSource` appended at 11.
    uint256 private constant OFF_DAILY = 0;             // uint8  dailyQuantity      (byte 0)
    uint256 private constant OFF_LASTSWEPT = 1;         // uint32 lastAutoBoughtDay  (bytes 1..4)
    uint256 private constant OFF_VALIDTHROUGHLEVEL = 5; // uint32 validThroughLevel  (bytes 5..8)
    uint256 private constant OFF_REINVEST = 9;          // uint8  reinvestPct        (byte 9)
    uint256 private constant OFF_FLAGS = 10;            // uint8  flags              (byte 10; bit 0 freed under AFSUB-01)
    uint256 private constant OFF_FUNDING_SOURCE = 11;   // address fundingSource     (bytes 11..30)

    bytes32 private constant SUB_UPDATED_SIG =
        keccak256("SubscriptionUpdated(address,uint8,bool,bool,uint8,address)");
    /// @dev SubscriptionExpired(address indexed player, uint8 reason). reason 2 = CancelReclaim;
    ///      reason 1 = AutoPause (funding-skip kill OR v50.0 AFSUB-03 pass-eviction).
    bytes32 private constant SUB_EXPIRED_SIG = keccak256("SubscriptionExpired(address,uint8)");

    /// @dev GASOPT-04 oracle migration: the per-player `AutoBought(address,uint32,uint256)` event was
    ///      DELETED. The no-double-buy / "bought today exactly once" oracle is now the authoritative
    ///      `lastAutoBoughtDay` storage stamp.
    uint32 private _boughtBaselineDay;

    /// @dev Snapshot of SubscriptionExpired(player, reason) emissions, drained by the single _drainLogs()
    ///      pass.
    address[] private _expiredPlayers;
    uint8[] private _expiredReasons;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
    }

    // =========================================================================
    // Task 1 -- Same-block cursor self-partition: exactly-once, no double-buy, no miss
    // =========================================================================

    /// @notice SAFE-03 core: with N healthy subscribers and TWO autoBuy(maxCount) calls in the SAME
    ///         block (each maxCount < N), every subscriber is bought EXACTLY ONCE.
    function testSameBlockTwoAutoBuysExactlyOnce() public {
        uint256 N = 6;
        address[] memory subs = _setupHealthyBuyingSubs(N, "split_");

        // Cursor starts at 0 for this fresh day (no autoBuy yet today).
        (, uint256 cursor0) = afKing.autoBuyProgress();
        assertEq(cursor0, 0, "cursor starts at 0 for a fresh day");

        _snapshotBought(subs); // GASOPT-04 storage-stamp baseline

        vm.prank(makeAddr("keeper_A"));
        afKing.autoBuy(4);
        (, uint256 cursorAfterA) = afKing.autoBuyProgress();

        vm.prank(makeAddr("keeper_B"));
        afKing.autoBuy(4);
        (, uint256 cursorAfterB) = afKing.autoBuyProgress();

        assertGt(cursorAfterA, 0, "first same-block autoBuy advanced the cursor");
        assertGe(cursorAfterB, cursorAfterA, "second autoBuy resumed from the advanced cursor (monotonic)");

        uint32 today = _today();
        for (uint256 i; i < N; i++) {
            assertEq(_lastAutoBoughtDayOf(subs[i]), today, "sub processed exactly this day");
            assertEq(_countAutoBoughtFor(subs[i]), 1, "sub bought EXACTLY ONCE across the two same-block autoBuys");
        }
    }

    /// @notice SAFE-03: a SINGLE autoBuy with maxCount < N processes only the first chunk and advances
    ///         the cursor; a SECOND same-block autoBuy picks up the rest with NO overlap.
    function testSameBlockNoOverlapBetweenChunks() public {
        uint256 N = 5;
        address[] memory subs = _setupHealthyBuyingSubs(N, "noov_");

        _snapshotBought(subs);
        vm.prank(makeAddr("chunk1_keeper"));
        afKing.autoBuy(3);
        bool[] memory boughtInChunk1 = new bool[](N);
        uint256 chunk1Count;
        for (uint256 i; i < N; i++) {
            if (_countAutoBoughtFor(subs[i]) == 1) {
                boughtInChunk1[i] = true;
                chunk1Count++;
            }
        }

        _snapshotBought(subs);
        vm.prank(makeAddr("chunk2_keeper"));
        afKing.autoBuy(10);
        for (uint256 i; i < N; i++) {
            uint256 c2 = _countAutoBoughtFor(subs[i]);
            if (boughtInChunk1[i]) {
                assertEq(c2, 0, "a chunk-1 sub is NOT re-autoBought in the same-block chunk 2 (no overlap)");
            }
        }

        uint32 today = _today();
        for (uint256 i; i < N; i++) {
            assertEq(_lastAutoBoughtDayOf(subs[i]), today, "every sub processed across the two chunks");
        }
    }

    /// @notice SAFE-03 daily reset: after a full autoBuy today, advancing one keeper-local day resets
    ///         the cursor to 0 on the next autoBuy.
    function testCursorResetsPerDayAndEachSubBuysOncePerDay() public {
        uint256 N = 4;
        address[] memory subs = _setupHealthyBuyingSubs(N, "daily_");

        vm.prank(makeAddr("day1_keeper"));
        afKing.autoBuy(50);
        uint32 day1 = _today();
        for (uint256 i; i < N; i++) {
            assertEq(_lastAutoBoughtDayOf(subs[i]), day1, "day-1 buy stamped");
        }

        for (uint256 i; i < N; i++) _fundPool(subs[i], 1 ether);

        vm.warp(block.timestamp + 1 days);
        uint32 day2 = _today();
        assertGt(day2, day1, "a keeper-local day elapsed");

        _snapshotBought(subs);
        vm.prank(makeAddr("day2_keeper"));
        afKing.autoBuy(50);

        (uint32 progDay, ) = afKing.autoBuyProgress();
        assertEq(progDay, day2, "autoBuyProgress day-stamp tracks the new keeper-local day");

        for (uint256 i; i < N; i++) {
            assertEq(_lastAutoBoughtDayOf(subs[i]), day2, "fresh day-2 buy stamped (one per day)");
            assertEq(_countAutoBoughtFor(subs[i]), 1, "exactly one fresh buy on the new day");
        }
    }

    /// @notice SAFE-03 backstop: the per-entry lastAutoBoughtDay idempotency stamp alone prevents a
    ///         repeat buy.
    function testLastAutoBoughtDayBackstopBlocksRepeatBuyOnCursorRevisit() public {
        address[] memory subs = _setupHealthyBuyingSubs(1, "backstop_");
        address sub = subs[0];

        address[] memory one = new address[](1);
        one[0] = sub;
        _snapshotBought(one);
        vm.prank(makeAddr("first_keeper"));
        afKing.autoBuy(50);
        assertEq(_countAutoBoughtFor(sub), 1, "first autoBuy bought the sub once");
        assertEq(_lastAutoBoughtDayOf(sub), _today(), "lastAutoBoughtDay stamped today");

        _fundPool(sub, 1 ether);
        _resetCursorToZeroForToday();

        _snapshotBought(one);
        vm.prank(makeAddr("revisit_keeper"));
        afKing.autoBuy(50);
        assertEq(_countAutoBoughtFor(sub), 0, "lastAutoBoughtDay backstop: NO second buy on a cursor re-visit");
        assertEq(_lastAutoBoughtDayOf(sub), _today(), "lastAutoBoughtDay unchanged by the re-visit skip");
    }

    /// @notice SAFE-03 fuzz: over an arbitrary same-block split (k, then the rest), every subscriber
    ///         is bought EXACTLY ONCE.
    function testFuzzSameBlockSplitExactlyOnce(uint8 firstChunk) public {
        uint256 N = 6;
        address[] memory subs = _setupHealthyBuyingSubs(N, "fuzz_");

        uint256 total = afKing.subscriberCount();
        uint256 k = (uint256(firstChunk) % (total + 1));
        if (k == 0) k = 1;

        _snapshotBought(subs);
        vm.prank(makeAddr("fuzz_keeperA"));
        afKing.autoBuy(k);

        vm.prank(makeAddr("fuzz_keeperB"));
        afKing.autoBuy(total + 1);

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

    /// @notice TOMB-04 / H-CANCEL-SWAP-MISS direct repro. The OLD swap-pop-at-cancel relocated the
    ///         set TAIL into a freed slot; if that freed slot sat BEHIND the chunked-autoBuy cursor,
    ///         the relocated tail (still pending today) was pushed behind the cursor and SKIPPED for
    ///         the day. v47's in-place tombstone moves no one, so the still-pending tail is never
    ///         relocated.
    function testCancelBehindCursorDoesNotStrandPendingTail() public {
        uint256 N = 8;
        address[] memory subs = _setupHealthyBuyingSubs(N, "strand_");

        vm.recordLogs();
        vm.prank(makeAddr("strand_keeperA"));
        afKing.autoBuy(4);
        _captureAutoBought();
        (, uint256 cursorMid) = afKing.autoBuyProgress();
        assertGt(cursorMid, 0, "first chunk advanced the cursor partway");
        assertLt(cursorMid, afKing.subscriberCount(), "cursor sits mid-set with a pending tail behind it");

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

        vm.prank(behindCursorAutoBought);
        afKing.setDailyQuantity(0);
        assertEq(_dailyQtyOf(behindCursorAutoBought), 0, "cancel wrote the in-place sentinel");
        assertGt(_subscriberIndexOf(behindCursorAutoBought), 0, "v47: cancel relocates no one -- still in set");

        vm.recordLogs();
        vm.prank(makeAddr("strand_keeperB"));
        afKing.autoBuy(afKing.subscriberCount() + 5);
        _captureAutoBought();

        assertEq(_countAutoBoughtFor(pendingTail), 1, "H-CANCEL-SWAP-MISS resolved: pending tail still bought");
        assertEq(_lastAutoBoughtDayOf(pendingTail), today, "pending tail's daily buy landed (no missed day)");

        uint256 activeBought;
        for (uint256 i; i < N; i++) {
            if (subs[i] == behindCursorAutoBought) continue;
            assertEq(_lastAutoBoughtDayOf(subs[i]), today, "every active sub processed (no miss)");
            activeBought++;
        }
        assertEq(activeBought, N - 1, "all N-1 still-active subs bought this day");
    }

    /// @notice TOMB-04: a cancelled sub is an in-place tombstone (still in the set) until the next
    ///         autoBuy that REACHES its slot reclaims it.
    function testCancelTombstoneReclaimedByNextAutoBuy() public {
        // ---- Sub-case (a): tombstone AHEAD of the cursor -> reclaimed THIS autoBuy. ----
        uint256 N = 6;
        address[] memory subs = _setupHealthyBuyingSubs(N, "reclaimA_");

        address ahead = subs[2];
        uint256 idxBefore = _subscriberIndexOf(ahead);
        uint256 setLenBefore = afKing.subscriberCount();
        vm.prank(ahead);
        afKing.setDailyQuantity(0);
        assertEq(_subscriberIndexOf(ahead), idxBefore, "tombstone still in set after cancel (no relocation)");
        assertEq(afKing.subscriberCount(), setLenBefore, "set length unchanged by cancel (in-place tombstone)");

        vm.recordLogs();
        vm.prank(makeAddr("reclaimA_keeper"));
        afKing.autoBuy(afKing.subscriberCount() + 5);
        _captureAutoBought();
        assertEq(_countExpiredFor(ahead, 2), 1, "reclaim emitted SubscriptionExpired(player,2) this autoBuy");
        assertEq(_subscriberIndexOf(ahead), 0, "tombstone reclaimed: removed from the set this autoBuy");

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
        vm.prank(makeAddr("reclaimB_keeperD1"));
        afKing.autoBuy(afKing.subscriberCount() + 5);
        uint32 day1 = _today();
        address behind = subsB[1];
        vm.prank(behind);
        afKing.setDailyQuantity(0);
        assertGt(_subscriberIndexOf(behind), 0, "behind-cursor tombstone not reclaimed same day (still in set)");

        vm.warp(block.timestamp + 1 days);
        for (uint256 i; i < N; i++) _fundPool(subsB[i], 1 ether);
        vm.recordLogs();
        vm.prank(makeAddr("reclaimB_keeperD2"));
        afKing.autoBuy(afKing.subscriberCount() + 5);
        _captureAutoBought();
        assertEq(_countExpiredFor(behind, 2), 1, "behind-cursor tombstone reclaimed on the next-day reset");
        assertEq(_subscriberIndexOf(behind), 0, "behind-cursor tombstone removed from set next day");
        assertGt(day1, 0, "day1 was a real keeper-local day");
    }

    /// @notice v50.0 AFSUB-01 reclaim shape: under v50.0 the cancel-reclaim branch in autoBuy
    ///         ALWAYS does `delete _subOf[player]` (the v47 `preservePaidWindow` carve-out is
    ///         DROPPED — AFSUB-01 retired the BURNIE-prepaid window). Asserts: a cancelled sub
    ///         whose record holds any non-zero stored value (validThroughLevel, fundingSource, etc.)
    ///         has those values zeroed at the deferred reclaim, with no opt-in preservation path.
    /// @dev    Replaces the v47 `testCancelPreservesPaidWindowThroughDeferredReclaim` /
    ///         `testCancelReclaimsUnpaidWindow` pair (windowPaid + the day-keyed renewal field are
    ///         GONE under AFSUB-01; the preserve-vs-delete fork has collapsed to always-delete).
    function testCancelReclaimAlwaysDeletesSubRecord() public {
        address[] memory subs = _setupHealthyBuyingSubs(1, "reclaim_delete_");
        address sub = subs[0];

        // Stamp a non-zero validThroughLevel into the sub (the v50.0 analog of the v49 paid window
        // endpoint) so we can verify the reclaim deletes the FULL record.
        _setValidThroughLevel(sub, 999);
        assertEq(_validThroughLevelOf(sub), 999, "pre-cancel: validThroughLevel = 999");

        vm.prank(sub);
        afKing.setDailyQuantity(0);
        // Pre-reclaim: tombstone still in set, validThroughLevel still readable (deferred reclaim).
        assertGt(_subscriberIndexOf(sub), 0, "tombstone in set after cancel (deferred reclaim)");
        assertEq(_validThroughLevelOf(sub), 999, "pre-reclaim: validThroughLevel readable");

        vm.recordLogs();
        vm.prank(makeAddr("reclaim_delete_keeper"));
        afKing.autoBuy(afKing.subscriberCount() + 5);
        _captureAutoBought();
        assertEq(_countExpiredFor(sub, 2), 1, "reclaim emitted SubscriptionExpired(player,2)");
        assertEq(_subscriberIndexOf(sub), 0, "sub removed from set at reclaim");

        // v50.0 AFSUB-01: the FULL record is deleted at reclaim (no preserve-vs-delete fork).
        assertEq(afKing.subscriptionOf(sub).dailyQuantity, 0, "dailyQuantity zeroed at reclaim");
        assertEq(afKing.subscriptionOf(sub).validThroughLevel, 0, "validThroughLevel zeroed at reclaim (no preserve path)");
        assertEq(afKing.subscriptionOf(sub).flags, 0, "flags zeroed at reclaim");
        assertEq(afKing.subscriptionOf(sub).fundingSource, address(0), "fundingSource zeroed at reclaim");
    }

    /// @notice TOMB-04: reactivating a still-in-set tombstone (before any autoBuy reclaims it) flips
    ///         it back to active IN PLACE with NO duplicate set membership.
    /// @dev    v50.0 AFSUB-01 simplification: the v47 "paid window survives the cancel->reactivate
    ///         round-trip" sub-assertion is dropped (no BURNIE-prepaid window exists anymore). The
    ///         load-bearing property — idempotent _addToSet, no double-add — survives unchanged.
    function testReactivateTombstonedSubNoDoubleAdd() public {
        // ---- (a) setDailyQuantity(q>0) reactivation, no double-add. ----
        address[] memory subs = _setupHealthyBuyingSubs(1, "reactA_");
        address sub = subs[0];

        uint256 idx = _subscriberIndexOf(sub);
        uint256 lenBefore = afKing.subscriberCount();

        vm.prank(sub);
        afKing.setDailyQuantity(0);
        assertEq(_subscriberIndexOf(sub), idx, "tombstone in set, same index");
        vm.prank(sub);
        afKing.setDailyQuantity(3);

        assertEq(_dailyQtyOf(sub), 3, "reactivated in place (dailyQuantity restored)");
        assertEq(_subscriberIndexOf(sub), idx, "reactivation kept the same set slot (no relocation)");
        assertEq(afKing.subscriberCount(), lenBefore, "no duplicate set membership on reactivation");

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

        // Re-subscribe the still-in-set tombstoned address. Under AFSUB-01 no BURNIE pre-fund needed.
        vm.prank(subB);
        afKing.subscribe(address(0), false, true, 2, 0, address(0));

        assertEq(_subscriberIndexOf(subB), idxB, "re-subscribe kept the same set slot (idempotent _addToSet)");
        assertEq(afKing.subscriberCount(), lenB, "re-subscribe of an in-set tombstone never double-adds");
        assertEq(_dailyQtyOf(subB), 2, "re-subscribe reactivated the sub (dailyQuantity restored)");
    }

    // =========================================================================
    // Task 2 -- Tombstone-on-cancel no-miss + no dead-slot buildup (deferred-reclaim semantics)
    // =========================================================================

    /// @notice TOMB-04: under v47/v50 the swap-pop fires at RECLAIM (in-loop, no ++cursor), not at
    ///         cancel. Cancelling an EARLY sub leaves it in the set as a tombstone; the autoBuy's
    ///         reclaim branch swap-pops it and the moved occupant is re-read at THIS index this
    ///         autoBuy -- it is not skipped.
    function testCancelSwapPopOccupantStillProcessed() public {
        uint256 N = 5;
        address[] memory subs = _setupHealthyBuyingSubs(N, "swap_");
        address mover = subs[N - 1];

        vm.prank(subs[0]);
        afKing.setDailyQuantity(0);
        assertGt(_subscriberIndexOf(subs[0]), 0, "v47: cancel is an in-place tombstone -- still in the set");
        assertEq(_dailyQtyOf(subs[0]), 0, "cancel wrote the in-place sentinel");

        vm.recordLogs();
        vm.prank(makeAddr("swap_keeper"));
        afKing.autoBuy(50);
        _captureAutoBought();

        assertEq(_subscriberIndexOf(subs[0]), 0, "tombstone swap-popped at reclaim (removed from set)");
        assertEq(_countExpiredFor(subs[0], 2), 1, "reclaim emitted SubscriptionExpired(player,2) at the swap-pop");
        assertEq(_countAutoBoughtFor(mover), 1, "reclaim swap-pop occupant still processed this autoBuy (no miss)");
        assertEq(_countAutoBoughtFor(subs[0]), 0, "cancelled sub not processed");
    }

    /// @notice TOMB-04: under v47/v50 a cancel does NOT shrink the set immediately. Across a series
    ///         of cancels the tombstones persist until the next autoBuy. The NET set effect equals
    ///         the old immediate-swap-pop.
    function testNoDeadSlotBuildupAcrossCancels() public {
        uint256 baseline = afKing.subscriberCount();
        uint256 N = 6;
        address[] memory subs = _setupHealthyBuyingSubs(N, "build_");
        assertEq(afKing.subscriberCount(), baseline + N, "all N added to the set");

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

        for (uint256 i = 3; i < N; i++) _fundPool(subs[i], 1 ether);
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

        uint256 count = afKing.subscriberCount();
        for (uint256 i; i < count; i++) {
            address at = afKing.subscriberAt(i);
            assertTrue(at != address(0), "no zero-address dead slot in the iteration set");
            assertEq(_subscriberIndexOf(at), i + 1, "each set slot's 1-indexed back-pointer is consistent");
        }
    }

    /// @notice TOMB-04: a cancelled sub's stranded pool ETH stays withdrawable.
    function testCancelledSubPoolEthWithdrawable() public {
        address[] memory subs = _setupHealthyBuyingSubs(1, "strandpool_");
        address sub = subs[0];

        _fundPool(sub, 3 ether);
        uint256 pooledBefore = afKing.poolOf(sub);
        assertGt(pooledBefore, 0, "sub has stranded pool ETH");

        vm.prank(sub);
        afKing.setDailyQuantity(0);
        assertGt(_subscriberIndexOf(sub), 0, "v47: cancel is an in-place tombstone -- still in the set");
        assertEq(_dailyQtyOf(sub), 0, "cancel wrote the in-place sentinel");
        assertEq(afKing.poolOf(sub), pooledBefore, "cancel did not confiscate pool ETH");

        uint256 balBefore = sub.balance;
        vm.prank(sub);
        afKing.withdraw(pooledBefore);
        assertEq(afKing.poolOf(sub), 0, "pool drained on withdraw");
        assertEq(sub.balance - balBefore, pooledBefore, "stranded pool ETH returned to the cancelled sub");
    }

    // =========================================================================
    // v50.0 AFSUB-05 -- swap-pop invariant under pass-eviction (H-CANCEL-SWAP-MISS re-derivation)
    // =========================================================================

    /// @notice v50.0 AFSUB-05: the v49 swap-pop invariant (membership ⟺ packed != 0) holds under
    ///         AFSUB-03 pass-eviction too. A no-pass crossing eviction routes through the same
    ///         tombstone-then-reclaim shape as cancel: `sub.dailyQuantity = 0; _removeFromSet(player);
    ///         emit SubscriptionExpired(player, 1)` (continuing WITHOUT advancing the cursor —
    ///         AfKing._autoBuy:638-645). The H-CANCEL-SWAP-MISS class structurally cannot reproduce
    ///         under pass-eviction because the swap-pop occupant is processed at this slot this
    ///         autoBuy (Pitfall P6).
    function testPassEvictionPreservesSwapPopInvariant() public {
        uint256 N = 6;
        address[] memory subs = _setupHealthyBuyingSubs(N, "evict_swap_");

        // No deity bit granted -> lazyPassHorizon(subs[i]) = 0 for all i. Force the crossing on
        // ALL of them: validThroughLevel = 0, bump game.level to 1. Every sub will EVICT this autoBuy
        // (not refresh).
        for (uint256 i; i < N; i++) _setValidThroughLevel(subs[i], 0);
        _bumpGameLevelToAtLeastOne();

        // Identify the tail sub PRE-autoBuy (the one swap-pop will move into a freed slot).
        address tail = subs[N - 1];
        uint256 tailIdxBefore = _subscriberIndexOf(tail);
        assertGt(tailIdxBefore, 0, "tail sub starts in the iterable set");

        vm.recordLogs();
        vm.prank(makeAddr("evict_swap_keeper"));
        afKing.autoBuy(afKing.subscriberCount() + 5); // MUST NOT revert despite the evictions
        _captureAutoBought();

        // Every test sub evicted: the swap-pop occupant at each freed slot was re-evaluated this
        // same autoBuy (the continue WITHOUT cursor advance — Pitfall P6 enforcement).
        for (uint256 i; i < N; i++) {
            assertEq(_countExpiredFor(subs[i], 1), 1, "AFSUB-03 pass-eviction emitted SubscriptionExpired(.,1)");
            assertEq(_subscriberIndexOf(subs[i]), 0, "evicted sub swap-popped out of the iterable set");
            assertEq(afKing.subscriptionOf(subs[i]).dailyQuantity, 0, "evicted sub dailyQuantity zeroed (tombstoned)");
        }
        // membership ⟺ packed != 0 invariant: every evicted sub has dailyQuantity == 0 AND index == 0;
        // VAULT/SDGNRS (the deploy-time SUB-09 entries) have a different pass state — VAULT carries
        // the permanent deity bit and survives the crossing, so VAULT stays in the set (the assertion
        // here is only on the N test subs we explicitly forced into eviction).
    }

    /// @notice v50.0 AFSUB-05: H-CANCEL-SWAP-MISS re-derivation under pass-eviction. Begin a chunked
    ///         autoBuy so the cursor sits partway, then force a pass-eviction on a behind-cursor sub.
    ///         Under the swap-pop-at-eviction shape the relocated tail (the swap-pop occupant) would
    ///         have been pushed behind the cursor and SKIPPED. Under v50.0's tombstone-then-reclaim
    ///         shape the eviction relocates no one mid-sweep and the pending tail is processed.
    /// @dev    Note: under v50.0 the EVICT branch routes through `sub.dailyQuantity = 0;
    ///         _removeFromSet(player); continue` -- the `_removeFromSet` here IS a swap-pop, but it
    ///         fires INSIDE the autoBuy loop at the cursor's current slot, with a `continue` that
    ///         does NOT advance the cursor (AfKing._autoBuy:642-645). So the swap-pop occupant is
    ///         re-read at THIS index this same autoBuy iteration — preserving the v49 invariant.
    function testPassEvictionBehindCursorDoesNotStrandPendingTail() public {
        uint256 N = 8;
        address[] memory subs = _setupHealthyBuyingSubs(N, "evict_strand_");

        // Grant deity to ODD-indexed subs only so they survive the crossing (REFRESH branch); EVEN
        // indices have no pass and EVICT.
        for (uint256 i = 1; i < N; i += 2) _grantDeityPass(subs[i]);
        // Force the crossing for all: validThroughLevel = 0, bump game.level.
        for (uint256 i; i < N; i++) _setValidThroughLevel(subs[i], 0);
        _bumpGameLevelToAtLeastOne();

        // First chunk: advance the cursor partway.
        vm.recordLogs();
        vm.prank(makeAddr("evict_strand_keeperA"));
        afKing.autoBuy(4);
        _captureAutoBought();
        (, uint256 cursorMid) = afKing.autoBuyProgress();
        assertGt(cursorMid, 0, "first chunk advanced the cursor partway");

        // Finish the autoBuy. The pass-eviction swap-pop never strands a pending tail.
        vm.recordLogs();
        vm.prank(makeAddr("evict_strand_keeperB"));
        afKing.autoBuy(afKing.subscriberCount() + 5);
        _captureAutoBought();

        // Every odd-indexed (deity-holding) sub survived and bought this day; every even-indexed sub
        // is evicted with dailyQuantity zeroed and out of the set.
        uint32 today = _today();
        for (uint256 i; i < N; i++) {
            if (i % 2 == 1) {
                assertEq(_lastAutoBoughtDayOf(subs[i]), today, "deity-holding sub processed (no miss from eviction swap-pop)");
                assertGt(_subscriberIndexOf(subs[i]), 0, "deity-holding sub stays in set");
            } else {
                assertEq(afKing.subscriptionOf(subs[i]).dailyQuantity, 0, "no-pass sub evicted (tombstone)");
                assertEq(_subscriberIndexOf(subs[i]), 0, "no-pass sub swap-popped out");
            }
        }
    }

    // =========================================================================
    // Internal helpers
    // =========================================================================

    function _today() internal view returns (uint32) {
        return uint32((block.timestamp - 82620) / 1 days);
    }

    /// @dev Subscribe `n` fresh players as fully-healthy buying subs (ticket mode, operator-approved,
    ///      pool-funded, NOT at the crossing). Under v50.0 AFSUB-01 there is no BURNIE pre-fund.
    function _setupHealthyBuyingSubs(uint256 n, string memory prefix) internal returns (address[] memory subs) {
        subs = new address[](n);
        for (uint256 i; i < n; i++) {
            address who = makeAddr(string(abi.encodePacked(prefix, _u(i))));
            subs[i] = who;
            vm.prank(who);
            afKing.subscribe(address(0), false, true, 1, 0, address(0)); // self, ticket mode, qty 1
            _approveKeeper(who);
            _fundPool(who, 1 ether);
        }
    }

    function _approveKeeper(address who) internal {
        vm.prank(who);
        game.setOperatorApproval(address(afKing), true);
    }

    function _fundPool(address who, uint256 amount) internal {
        vm.deal(address(this), amount);
        afKing.depositFor{value: amount}(who);
    }

    /// @dev Grant `who` the permanent deity-pass bit so lazyPassHorizon(who) = type(uint24).max.
    function _grantDeityPass(address who) internal {
        bytes32 slot = keccak256(abi.encode(who, uint256(9)));
        uint256 packed = uint256(vm.load(address(game), slot));
        packed |= (uint256(1) << 184);
        vm.store(address(game), slot, bytes32(packed));
    }

    /// @dev Bump game.level (uint24 packed at slot-0 bytes 14..16) from 0 to 1 if needed, so a sub
    ///      with validThroughLevel = 0 triggers the AFSUB-03 crossing predicate `currentLevel > 0`.
    /// @dev DegenerusGameStorage slot 0 layout: bytes 0..3 purchaseStartDay, bytes 4..7 dailyIdx,
    ///      bytes 8..13 rngRequestTime, bytes 14..16 level (uint24). Plan 335-06 helper-fix replaces
    ///      the v49-era assumption that `level` lived at the low 24 bits — write at byte offset 14.
    function _bumpGameLevelToAtLeastOne() internal {
        uint256 slot0 = uint256(vm.load(address(game), bytes32(uint256(0))));
        uint256 levelMask = uint256(0xFFFFFF) << (14 * 8);
        if (uint24((slot0 & levelMask) >> (14 * 8)) == 0) {
            slot0 = (slot0 & ~levelMask) | (uint256(1) << (14 * 8));
            vm.store(address(game), bytes32(uint256(0)), bytes32(slot0));
        }
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

    /// @dev Read `who`'s dailyQuantity (byte 0 of the packed Sub slot).
    function _dailyQtyOf(address who) internal view returns (uint8) {
        bytes32 slot = keccak256(abi.encode(who, uint256(SUBOF_SLOT)));
        uint256 packed = uint256(vm.load(address(afKing), slot));
        return uint8(packed >> (OFF_DAILY * 8));
    }

    /// @dev Read `who`'s validThroughLevel (bytes 5..8 of the packed Sub slot — v50.0 in-place
    ///      repurpose of the v49 day-keyed renewal slot).
    function _validThroughLevelOf(address who) internal view returns (uint32) {
        bytes32 slot = keccak256(abi.encode(who, uint256(SUBOF_SLOT)));
        uint256 packed = uint256(vm.load(address(afKing), slot));
        return uint32(packed >> (OFF_VALIDTHROUGHLEVEL * 8));
    }

    /// @dev Pin `who`'s validThroughLevel (bytes 5..8). Used to force the AFSUB-03 crossing
    ///      predicate (currentLevel > validThroughLevel) or, with a high value, to keep the per-iter
    ///      check satisfied.
    function _setValidThroughLevel(address who, uint32 level) internal {
        bytes32 slot = keccak256(abi.encode(who, uint256(SUBOF_SLOT)));
        uint256 packed = uint256(vm.load(address(afKing), slot));
        packed &= ~(uint256(0xFFFFFFFF) << (OFF_VALIDTHROUGHLEVEL * 8));
        packed |= (uint256(level) << (OFF_VALIDTHROUGHLEVEL * 8));
        vm.store(address(afKing), slot, bytes32(packed));
    }

    /// @dev Force the autoBuy cursor back to 0 while keeping the day-stamp at today.
    function _resetCursorToZeroForToday() internal {
        uint256 packed = uint256(vm.load(address(afKing), bytes32(uint256(4))));
        packed &= uint256(0xFFFFFFFF);
        packed |= (uint256(_today()) & 0xFFFFFFFF);
        vm.store(address(afKing), bytes32(uint256(4)), bytes32(packed));
    }

    /// @dev Drain the recorded logs ONCE into the SubscriptionExpired snapshot.
    function _drainLogs() internal {
        delete _expiredPlayers;
        delete _expiredReasons;
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].emitter != address(afKing) || logs[i].topics.length == 0) continue;
            if (logs[i].topics[0] == SUB_EXPIRED_SIG && logs[i].topics.length >= 2) {
                _expiredPlayers.push(address(uint160(uint256(logs[i].topics[1]))));
                _expiredReasons.push(uint8(uint256(bytes32(logs[i].data))));
            }
        }
    }

    /// @dev Alias kept for the existing call sites (historical name).
    function _captureAutoBought() internal {
        _drainLogs();
    }

    /// @dev Per-address baseline `lastAutoBoughtDay` snapshot for the storage-stamp buy oracle.
    mapping(address => uint32) private _baselineBoughtDay;

    function _snapshotBought(address[] memory tracked) internal {
        for (uint256 i; i < tracked.length; i++) {
            _baselineBoughtDay[tracked[i]] = _lastAutoBoughtDayOf(tracked[i]);
        }
    }

    function _countAutoBoughtFor(address who) internal view returns (uint256) {
        uint32 stamp = _lastAutoBoughtDayOf(who);
        return (stamp == _today() && stamp > _baselineBoughtDay[who]) ? 1 : 0;
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
