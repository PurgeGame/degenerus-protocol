// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @title AfKingConcurrency -- Proves SAFE-03 sweep concurrency-correctness for the AF_KING keeper:
///        two same-block sweep(maxCount) callers self-partition via the advancing `_sweepCursor` plus
///        the per-entry `lastSweptDay` idempotency backstop, and the tombstone-on-cancel swap-pop
///        leaves no dead-slot buildup and skips no active subscriber.
///
/// @notice The sweep is PERMISSIONLESS and CONCURRENT -- multiple keepers/craners can call sweep in
///         the SAME block. SAFE-03 is the concurrency floor:
///   - Same-block self-partition (Task 1, SUB-03): with N active subs and two sweep(maxCount) calls in
///     the same block (each maxCount < N so neither covers all at once), every subscriber is bought
///     EXACTLY ONCE across the two sweeps. The cursor advances across the first sweep; the second
///     sweep resumes from the advanced position. No subscriber is bought twice (the `lastSweptDay >=
///     today` backstop blocks a repeat) and none is left unprocessed once combined maxCount >= N.
///   - Daily cursor reset: the first sweep of a NEW keeper-local day restarts the cursor at 0, and the
///     per-entry lastSweptDay gates the fresh-day buy (one buy per sub per day).
///   - lastSweptDay backstop alone: even if a sweep re-visits an index already bought today (cursor
///     position notwithstanding), the day-stamp prevents a second buy.
///   - Tombstone-on-cancel no-miss (Task 2, SUB-07): a cancelled / funding-skip-killed NORMAL sub is
///     removed via in-sweep swap-pop WITHOUT advancing the cursor, so the occupant swapped into the
///     freed slot is still processed THIS sweep -- no active sub is skipped by the removal. After a
///     series of cancels, subscriberCount equals only the active subs (no dead-slot buildup), a
///     cancelled sub's stranded pool ETH stays withdrawable, and the windowPaid-gated reclaim rule
///     holds (a paid+unexpired window is preserved on cancel; an unpaid/expired one is reclaimed).
///
/// @dev Builds on the 318-01-repaired DeployProtocol fixture (AfKing live at AF_KING; the two SUB-09
///      self-subscribes VAULT + SDGNRS already in the set). Test subs are driven through the public
///      subscribe() API and made healthy (ticket mode, operator-approved, pool-funded, not renewal-due)
///      so each lands a clean buy. To isolate the new subscribers from the two deploy-time subs, every
///      assertion is keyed on per-player lastSweptDay / pool deltas / event counts rather than on the
///      raw subscriberCount of the whole set. Test-only: no contracts/*.sol mutated.
contract AfKingConcurrency is DeployProtocol {
    // -------------------------------------------------------------------------
    // AfKing pinned 4-slot layout + Sub packed-field offsets (per AfKing.sol)
    // -------------------------------------------------------------------------
    uint256 private constant SUBOF_SLOT = 1;          // _subOf mapping root (address => Sub, one slot)
    uint256 private constant SUBSCRIBER_INDEX_SLOT = 3; // _subscriberIndex mapping root (1-indexed)

    // Sub packed-field byte offsets re-derived from the post-OPEN-E repack (319.1-01 AFTER
    // layout): the two standalone bools collapsed into `flags` and a 20-byte `fundingSource`
    // address was appended, shifting lastSweptDay 3->1, paidThroughDay 7->5, flags 12->10.
    uint256 private constant OFF_DAILY = 0;          // uint8  dailyQuantity  (byte 0)
    uint256 private constant OFF_LASTSWEPT = 1;      // uint32 lastSweptDay    (bytes 1..4)
    uint256 private constant OFF_PAIDTHROUGH = 5;    // uint32 paidThroughDay  (bytes 5..8)
    uint256 private constant OFF_REINVEST = 9;       // uint8  reinvestPct     (byte 9)
    uint256 private constant OFF_FLAGS = 10;         // uint8  flags (bit 0 = windowPaid, byte 10)
    uint256 private constant OFF_FUNDING_SOURCE = 11; // address fundingSource (bytes 11..30)

    uint256 private constant FLAG_WINDOW_PAID = 1;
    uint32 private constant WINDOW_DAYS = 30;

    bytes32 private constant SWEPT_SIG = keccak256("Swept(address,uint32,uint256)");
    bytes32 private constant SUB_UPDATED_SIG =
        keccak256("SubscriptionUpdated(address,uint8,bool,bool,uint8)");

    /// @dev Snapshot of Swept(player,...) recipients drained from the recorded logs by _captureSwept().
    ///      vm.getRecordedLogs() CONSUMES the buffer, so we drain ONCE per assertion phase into this
    ///      array and count per-player from the snapshot (a per-player getRecordedLogs would see 0 on
    ///      every call after the first).
    address[] private _sweptSnapshot;

    function setUp() public {
        _deployProtocol();
        // Advance one keeper-local day off the deploy boundary so _currentDay() is a clean, stable
        // index for the whole test (mirrors AfKingSubscription.setUp()).
        vm.warp(block.timestamp + 1 days);
    }

    // =========================================================================
    // Task 1 -- Same-block cursor self-partition: exactly-once, no double-buy, no miss
    // =========================================================================

    /// @notice SAFE-03 core: with N healthy subscribers and TWO sweep(maxCount) calls in the SAME
    ///         block (each maxCount < N), every subscriber is bought EXACTLY ONCE. The cursor advances
    ///         across the first sweep and the second resumes from the advanced position; the combined
    ///         maxCount covers all N, none is double-bought (sum of buys == N, max per-player buys == 1).
    function testSameBlockTwoSweepsExactlyOnce() public {
        uint256 N = 6;
        address[] memory subs = _setupHealthyBuyingSubs(N, "split_");

        // Cursor starts at 0 for this fresh day (no sweep yet today).
        (, uint256 cursor0) = afKing.sweepProgress();
        assertEq(cursor0, 0, "cursor starts at 0 for a fresh day");

        // Two same-block sweeps: maxCount 4 then 4 (each < the full set so neither covers all in one).
        // The set also holds the 2 deploy subs (VAULT/SDGNRS) ahead/among ours; maxCount 4+4 = 8 and
        // the set is 8 (6 ours + 2 deploy), so the combined reach covers the whole set this day.
        vm.recordLogs();

        vm.prank(makeAddr("keeper_A"));
        afKing.sweep(4);
        (, uint256 cursorAfterA) = afKing.sweepProgress();

        vm.prank(makeAddr("keeper_B"));
        afKing.sweep(4);
        (, uint256 cursorAfterB) = afKing.sweepProgress();

        _captureSwept(); // drain the combined Swept stream once before counting

        // The cursor advanced monotonically (B resumed from A's advanced position).
        assertGt(cursorAfterA, 0, "first same-block sweep advanced the cursor");
        assertGe(cursorAfterB, cursorAfterA, "second sweep resumed from the advanced cursor (monotonic)");

        // Every one of OUR N subs was bought exactly once across the two same-block sweeps:
        //  - lastSweptDay == today for each (processed this day), and
        //  - exactly one Swept event per sub (no double-buy).
        uint32 today = _today();
        for (uint256 i; i < N; i++) {
            assertEq(_lastSweptDayOf(subs[i]), today, "sub processed exactly this day");
            assertEq(_countSweptFor(subs[i]), 1, "sub bought EXACTLY ONCE across the two same-block sweeps");
        }
    }

    /// @notice SAFE-03: a SINGLE sweep with maxCount < N processes only the first chunk and advances
    ///         the cursor; a SECOND same-block sweep picks up the rest with NO overlap (no sub appears
    ///         in both chunks' Swept stream). Proves the self-partition is by the shared advancing
    ///         cursor, not by luck.
    function testSameBlockNoOverlapBetweenChunks() public {
        uint256 N = 5;
        address[] memory subs = _setupHealthyBuyingSubs(N, "noov_");

        // First chunk: a small maxCount.
        vm.recordLogs();
        vm.prank(makeAddr("chunk1_keeper"));
        afKing.sweep(3);
        _captureSwept(); // drain chunk-1's Swept stream
        // Snapshot which of OUR subs were bought in chunk 1.
        bool[] memory boughtInChunk1 = new bool[](N);
        uint256 chunk1Count;
        for (uint256 i; i < N; i++) {
            if (_countSweptFor(subs[i]) == 1) {
                boughtInChunk1[i] = true;
                chunk1Count++;
            }
        }

        // Second chunk (same block): the rest.
        vm.recordLogs();
        vm.prank(makeAddr("chunk2_keeper"));
        afKing.sweep(10);
        _captureSwept(); // drain chunk-2's Swept stream (snapshot now holds ONLY chunk-2 buys)
        for (uint256 i; i < N; i++) {
            uint256 c2 = _countSweptFor(subs[i]);
            if (boughtInChunk1[i]) {
                // Already bought in chunk 1 -> NOT swept again in chunk 2 (no overlap / no double-buy).
                assertEq(c2, 0, "a chunk-1 sub is NOT re-swept in the same-block chunk 2 (no overlap)");
            }
        }

        // Union covers every sub exactly once for the day.
        uint32 today = _today();
        for (uint256 i; i < N; i++) {
            assertEq(_lastSweptDayOf(subs[i]), today, "every sub processed across the two chunks");
        }
    }

    /// @notice SAFE-03 daily reset: after a full sweep today, advancing one keeper-local day resets the
    ///         cursor to 0 on the next sweep, and each subscriber is eligible for exactly one fresh buy
    ///         (lastSweptDay advances to the new day; one Swept per sub on the new day).
    function testCursorResetsPerDayAndEachSubBuysOncePerDay() public {
        uint256 N = 4;
        address[] memory subs = _setupHealthyBuyingSubs(N, "daily_");

        // Day 1 full sweep.
        vm.prank(makeAddr("day1_keeper"));
        afKing.sweep(50);
        uint32 day1 = _today();
        for (uint256 i; i < N; i++) {
            assertEq(_lastSweptDayOf(subs[i]), day1, "day-1 buy stamped");
        }

        // Re-funding the pool so the day-2 buy can land (day-1 buy debited it).
        for (uint256 i; i < N; i++) _fundPool(subs[i], 1 ether);

        // Advance one day -> first sweep of the new day resets the cursor.
        vm.warp(block.timestamp + 1 days);
        uint32 day2 = _today();
        assertGt(day2, day1, "a keeper-local day elapsed");

        vm.recordLogs();
        vm.prank(makeAddr("day2_keeper"));
        afKing.sweep(50);
        _captureSwept();

        // Cursor day-stamp tracks the new day (first sweep of the day reset the index to 0 then advanced).
        (uint32 progDay, ) = afKing.sweepProgress();
        assertEq(progDay, day2, "sweepProgress day-stamp tracks the new keeper-local day");

        for (uint256 i; i < N; i++) {
            assertEq(_lastSweptDayOf(subs[i]), day2, "fresh day-2 buy stamped (one per day)");
            assertEq(_countSweptFor(subs[i]), 1, "exactly one fresh buy on the new day");
        }
    }

    /// @notice SAFE-03 backstop: the per-entry lastSweptDay idempotency stamp alone prevents a repeat
    ///         buy. Force a sub's lastSweptDay to today, reset the cursor to 0 so the sweep RE-VISITS
    ///         that index, and confirm the sub is skipped (PlayerSkipped reason 2) -- no second buy --
    ///         independent of the cursor position.
    function testLastSweptDayBackstopBlocksRepeatBuyOnCursorRevisit() public {
        address[] memory subs = _setupHealthyBuyingSubs(1, "backstop_");
        address sub = subs[0];

        // First sweep today buys the sub once.
        vm.recordLogs();
        vm.prank(makeAddr("first_keeper"));
        afKing.sweep(50);
        _captureSwept();
        assertEq(_countSweptFor(sub), 1, "first sweep bought the sub once");
        assertEq(_lastSweptDayOf(sub), _today(), "lastSweptDay stamped today");

        // Re-fund so a (hypothetical) second buy COULD land if the backstop were absent.
        _fundPool(sub, 1 ether);

        // Force the cursor back to 0 so the next sweep RE-VISITS the already-bought index.
        _resetCursorToZeroForToday();

        vm.recordLogs();
        vm.prank(makeAddr("revisit_keeper"));
        // Every active sub is already-swept-today now, so the whole chunk produces zero buys ->
        // NoSubscribersSwept. The point is the absence of a SECOND Swept for `sub`.
        try afKing.sweep(50) {
            // If it did not revert, still assert no second buy happened for our sub.
        } catch {
            // NoSubscribersSwept on an all-already-swept chunk is the expected atomic no-op.
        }
        _captureSwept();
        assertEq(_countSweptFor(sub), 0, "lastSweptDay backstop: NO second buy on a cursor re-visit");
        assertEq(_lastSweptDayOf(sub), _today(), "lastSweptDay unchanged by the re-visit skip");
    }

    /// @notice SAFE-03 fuzz: over an arbitrary same-block split (k, then the rest), every subscriber is
    ///         bought EXACTLY ONCE -- no double-buy, no miss -- regardless of where the first sweep's
    ///         maxCount lands.
    function testFuzzSameBlockSplitExactlyOnce(uint8 firstChunk) public {
        uint256 N = 6;
        address[] memory subs = _setupHealthyBuyingSubs(N, "fuzz_");

        // Total set size = N + 2 deploy subs. Bound the first chunk to (0, total) so the split is real.
        uint256 total = afKing.subscriberCount();
        uint256 k = (uint256(firstChunk) % (total + 1)); // 0..total
        if (k == 0) k = 1; // sweep(0) reverts EmptySweep; keep a real first chunk

        vm.recordLogs();
        vm.prank(makeAddr("fuzz_keeperA"));
        try afKing.sweep(k) {} catch {} // a tiny chunk that hits only deploy subs may still buy >=1

        vm.prank(makeAddr("fuzz_keeperB"));
        // The remainder, generously sized to drain the rest of the set this same block.
        try afKing.sweep(total + 1) {} catch {}

        _captureSwept(); // drain the combined two-sweep Swept stream once

        // Invariant: each of OUR subs swept exactly once for the day (sum == N, max-per == 1).
        uint32 today = _today();
        uint256 sumBuys;
        for (uint256 i; i < N; i++) {
            uint256 c = _countSweptFor(subs[i]);
            assertLe(c, 1, "no sub double-bought across any same-block split");
            assertEq(_lastSweptDayOf(subs[i]), today, "every sub processed across the split (no miss)");
            sumBuys += c;
        }
        assertEq(sumBuys, N, "sum of buys == N across the two same-block sweeps (exactly-once)");
    }

    // =========================================================================
    // Task 2 -- Tombstone-on-cancel no-miss + no dead-slot buildup
    // =========================================================================

    /// @notice SUB-07: cancelling a sub mid-set (setDailyQuantity(0) swap-pop) moves the last sub into
    ///         the freed slot. A subsequent sweep processes the moved occupant -- it is not skipped by
    ///         the removal. Here we cancel a sub that sits BEFORE the tail, then sweep and assert the
    ///         former-tail occupant is still bought this day.
    function testCancelSwapPopOccupantStillProcessed() public {
        // Subscribe an ordered batch; the LAST one is the "mover" that will be swapped into a freed slot.
        uint256 N = 5;
        address[] memory subs = _setupHealthyBuyingSubs(N, "swap_");
        address mover = subs[N - 1]; // currently the tail among our subs

        // Cancel an EARLY sub (subs[0]) -> swap-pop moves the global last element into subs[0]'s slot.
        // (The global tail may be `mover` or a later-added deploy sub; either way the occupant must be
        // processed.) We assert the `mover` -- still active, funded -- is bought this sweep.
        vm.prank(subs[0]);
        afKing.setDailyQuantity(0);
        assertEq(_subscriberIndexOf(subs[0]), 0, "cancelled sub removed from the iterable set");

        vm.recordLogs();
        vm.prank(makeAddr("swap_keeper"));
        afKing.sweep(50);
        _captureSwept();

        // The mover (still active) was bought -- the swap-pop did not strand it.
        assertEq(_countSweptFor(mover), 1, "swap-pop occupant still processed this sweep (no miss)");
        // The cancelled sub was NOT bought.
        assertEq(_countSweptFor(subs[0]), 0, "cancelled sub not processed");
    }

    /// @notice SUB-07: after a series of cancels across days, subscriberCount equals the count of
    ///         still-active subs -- no tombstoned/dead slots accumulate in the iteration set. Removal is
    ///         a true swap-pop (length shrinks), not a logical-delete that leaves a hole.
    function testNoDeadSlotBuildupAcrossCancels() public {
        uint256 baseline = afKing.subscriberCount(); // the 2 deploy subs (+ any)
        uint256 N = 6;
        address[] memory subs = _setupHealthyBuyingSubs(N, "build_");
        assertEq(afKing.subscriberCount(), baseline + N, "all N added to the set");

        // Cancel half of them, across two days, and assert the count shrinks by exactly the cancels --
        // no dead slots linger.
        vm.prank(subs[0]);
        afKing.setDailyQuantity(0);
        vm.prank(subs[1]);
        afKing.setDailyQuantity(0);
        assertEq(afKing.subscriberCount(), baseline + N - 2, "count shrank by 2 cancels (no tombstone slot)");

        vm.warp(block.timestamp + 1 days);
        vm.prank(subs[2]);
        afKing.setDailyQuantity(0);
        assertEq(afKing.subscriberCount(), baseline + N - 3, "count shrank by a 3rd cancel across a day");

        // Every remaining index dereferences to a live, in-set address (no dead slot, no OOB hole).
        uint256 count = afKing.subscriberCount();
        for (uint256 i; i < count; i++) {
            address at = afKing.subscriberAt(i);
            assertTrue(at != address(0), "no zero-address dead slot in the iteration set");
            assertEq(_subscriberIndexOf(at), i + 1, "each set slot's 1-indexed back-pointer is consistent");
        }
    }

    /// @notice SUB-07: a cancelled sub's stranded pool ETH stays withdrawable -- cancel only removes set
    ///         membership / writes the sentinel; it never confiscates `_poolOf`.
    function testCancelledSubPoolEthWithdrawable() public {
        address[] memory subs = _setupHealthyBuyingSubs(1, "strand_");
        address sub = subs[0];

        // Top the pool to a known surplus, then cancel.
        _fundPool(sub, 3 ether);
        uint256 pooledBefore = afKing.poolOf(sub);
        assertGt(pooledBefore, 0, "sub has stranded pool ETH");

        vm.prank(sub);
        afKing.setDailyQuantity(0);
        assertEq(_subscriberIndexOf(sub), 0, "cancelled");
        // Pool ETH preserved through the cancel.
        assertEq(afKing.poolOf(sub), pooledBefore, "cancel did not confiscate pool ETH");

        // The cancelled sub can still withdraw its full pool balance.
        uint256 balBefore = sub.balance;
        vm.prank(sub);
        afKing.withdraw(pooledBefore);
        assertEq(afKing.poolOf(sub), 0, "pool drained on withdraw");
        assertEq(sub.balance - balBefore, pooledBefore, "stranded pool ETH returned to the cancelled sub");
    }

    /// @notice SUB-07 windowPaid-gated reclaim: a cancel does NOT delete a PAID, UNEXPIRED window
    ///         (windowPaid set AND paidThroughDay > today preserved -- dailyQuantity zeroed but the rest
    ///         of the record kept). The set membership is still removed.
    function testCancelPreservesPaidUnexpiredWindow() public {
        address[] memory subs = _setupHealthyBuyingSubs(1, "paidwin_");
        address sub = subs[0];

        // Pin a PAID + UNEXPIRED window: windowPaid set, paidThroughDay well in the future.
        _setWindow(sub, /*paidThroughDay*/ _today() + WINDOW_DAYS, /*windowPaid*/ true);

        vm.prank(sub);
        afKing.setDailyQuantity(0);

        // Set membership removed, dailyQuantity zeroed, BUT the paid window record is preserved.
        assertEq(_subscriberIndexOf(sub), 0, "removed from set");
        assertEq(afKing.subscriptionOf(sub).dailyQuantity, 0, "dailyQuantity zeroed on cancel");
        assertEq(afKing.subscriptionOf(sub).flags & uint8(FLAG_WINDOW_PAID), 1, "paid window flag preserved");
        assertGt(afKing.subscriptionOf(sub).paidThroughDay, _today(), "unexpired window endpoint preserved");
    }

    /// @notice SUB-07 windowPaid-gated reclaim: a cancel on an UNPAID (free/expired) window DELETES the
    ///         `_subOf` record -- nothing to preserve (a free or expired window). paidThroughDay and the
    ///         flags clear to zero.
    function testCancelReclaimsUnpaidWindow() public {
        address[] memory subs = _setupHealthyBuyingSubs(1, "freewin_");
        address sub = subs[0];

        // Pin an UNPAID window: windowPaid clear (a free-pass window). paidThroughDay in the future is
        // irrelevant because windowPaid is the gate -- an unpaid window is reclaimed regardless.
        _setWindow(sub, /*paidThroughDay*/ _today() + WINDOW_DAYS, /*windowPaid*/ false);

        vm.prank(sub);
        afKing.setDailyQuantity(0);

        // Record deleted: every Sub field zeroed.
        assertEq(_subscriberIndexOf(sub), 0, "removed from set");
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

    /// @dev Read `who`'s lastSweptDay (bytes 3..6 of the packed Sub slot).
    function _lastSweptDayOf(address who) internal view returns (uint32) {
        bytes32 slot = keccak256(abi.encode(who, uint256(SUBOF_SLOT)));
        uint256 packed = uint256(vm.load(address(afKing), slot));
        return uint32(packed >> (OFF_LASTSWEPT * 8));
    }

    /// @dev Read `who`'s 1-indexed subscriber index (slot 3); 0 = not in set.
    function _subscriberIndexOf(address who) internal view returns (uint256) {
        bytes32 slot = keccak256(abi.encode(who, uint256(SUBSCRIBER_INDEX_SLOT)));
        return uint256(vm.load(address(afKing), slot));
    }

    /// @dev Pin `who`'s window: write paidThroughDay (bytes 7..10) and the windowPaid bit (byte 12).
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

    /// @dev Force the sweep cursor back to 0 while keeping the day-stamp at today, so the next sweep
    ///      re-visits index 0. Slot 4: _sweepDay (uint32, bytes 0..3) + _sweepCursor (uint224, bytes 4..).
    function _resetCursorToZeroForToday() internal {
        uint256 packed = uint256(vm.load(address(afKing), bytes32(uint256(4))));
        // Keep _sweepDay (low 4 bytes); zero the cursor (high 28 bytes).
        packed &= uint256(0xFFFFFFFF);
        packed |= (uint256(_today()) & 0xFFFFFFFF); // ensure day-stamp == today
        vm.store(address(afKing), bytes32(uint256(4)), bytes32(packed));
    }

    /// @dev Drain the recorded logs ONCE into `_sweptSnapshot` (the indexed Swept recipients emitted by
    ///      AfKing). Call this immediately after the sweep(s) under test, BEFORE any _countSweptFor.
    ///      vm.getRecordedLogs() empties the buffer, so a single drain feeds every subsequent count.
    function _captureSwept() internal {
        delete _sweptSnapshot;
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; i++) {
            if (
                logs[i].emitter == address(afKing) &&
                logs[i].topics.length >= 2 &&
                logs[i].topics[0] == SWEPT_SIG
            ) {
                _sweptSnapshot.push(address(uint160(uint256(logs[i].topics[1]))));
            }
        }
    }

    /// @dev Count Swept emissions for `who` in the captured snapshot. Pure read of the drained array.
    function _countSweptFor(address who) internal view returns (uint256 count) {
        for (uint256 i; i < _sweptSnapshot.length; i++) {
            if (_sweptSnapshot[i] == who) count++;
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
