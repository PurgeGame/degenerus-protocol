// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";

/// @title TicketEdgeCasesHarness -- Combines routing (Phase 75) and simplified processing (Phase 76)
///        to exercise cross-cutting edge cases around EDGE-01 and EDGE-02.
/// @dev Routing via _queueTickets (uses isFarFuture check at deposit time) and
///      simplified processBatch (dual-queue drain with FF bit) from TicketProcessingFFHarness.
contract TicketEdgeCasesHarness is DegenerusGameStorage {
    uint32 public constant BUDGET = 10;

    // -- Routing wrapper (from TicketRoutingHarness pattern) --

    function queueTickets(address buyer, uint24 targetLevel, uint32 quantity) external {
        _queueTickets(buyer, targetLevel, quantity);
    }

    // -- State setters --

    function setLevel(uint24 lvl) external {
        level = lvl;
    }

    function setTicketQueue(uint24 key, uint256 count) external {
        for (uint256 i = 0; i < count; i++) {
            ticketQueue[key].push(address(uint160(i + 1)));
        }
    }

    function setTicketLevel(uint24 v) external {
        ticketLevel = v;
    }

    function setTicketCursor(uint32 v) external {
        ticketCursor = v;
    }

    function setTicketWriteSlot(uint8 v) external {
        ticketWriteSlot = v;
    }

    function setRngWordCurrent(uint256 v) external {
        rngWordCurrent = v;
    }

    // -- State getters --

    function getTicketLevel() external view returns (uint24) {
        return ticketLevel;
    }

    function getTicketCursor() external view returns (uint32) {
        return ticketCursor;
    }

    function getQueueLength(uint24 key) external view returns (uint256) {
        return ticketQueue[key].length;
    }

    function getTicketsOwedPacked(uint24 key, address player) external view returns (uint40) {
        return ticketsOwedPacked[key][player];
    }

    // -- Key helpers (exposed) --

    function tqWriteKey(uint24 lvl) external view returns (uint24) {
        return _tqWriteKey(lvl);
    }

    function tqReadKey(uint24 lvl) external view returns (uint24) {
        return _tqReadKey(lvl);
    }

    function tqFarFutureKey(uint24 lvl) external pure returns (uint24) {
        return _tqFarFutureKey(lvl);
    }

    // -- Simplified processBatch replicating dual-queue drain logic --
    // Copied verbatim from TicketProcessingFFHarness (Phase 76).
    // Each queue entry costs 1 write unit. Budget = BUDGET (10).
    // Returns (worked, finished).

    function processBatch(uint24 lvl) external returns (bool worked, bool finished) {
        // Phase detection: are we resuming FF processing?
        bool inFarFuture = (ticketLevel == (lvl | TICKET_FAR_FUTURE_BIT));
        uint24 rk = inFarFuture ? _tqFarFutureKey(lvl) : _tqReadKey(lvl);
        address[] storage queue = ticketQueue[rk];
        uint256 total = queue.length;

        // Exit point 1: current queue empty
        if (total == 0) {
            if (!inFarFuture) {
                uint24 ffk = _tqFarFutureKey(lvl);
                if (ticketQueue[ffk].length > 0) {
                    ticketLevel = lvl | TICKET_FAR_FUTURE_BIT;
                    ticketCursor = 0;
                    return (false, false); // FF queue pending
                }
            }
            ticketCursor = 0;
            ticketLevel = 0;
            return (false, true); // Both empty
        }

        // Level switch (read-side only)
        if (!inFarFuture && ticketLevel != lvl) {
            ticketLevel = lvl;
            ticketCursor = 0;
        }

        uint256 idx = ticketCursor;

        // Exit point 2: cursor past end
        if (idx >= total) {
            delete ticketQueue[rk];
            if (!inFarFuture) {
                uint24 ffk = _tqFarFutureKey(lvl);
                if (ticketQueue[ffk].length > 0) {
                    ticketLevel = lvl | TICKET_FAR_FUTURE_BIT;
                    ticketCursor = 0;
                    return (false, false);
                }
            }
            ticketCursor = 0;
            ticketLevel = 0;
            return (false, true);
        }

        // Simplified batch loop: each entry = 1 write unit
        uint32 used;
        while (idx < total && used < BUDGET) {
            unchecked {
                ++idx;
                ++used;
            }
        }

        worked = (used > 0);
        ticketCursor = uint32(idx);

        // Exit point 3: post-loop
        finished = (idx >= total);
        if (finished) {
            delete ticketQueue[rk];
            if (!inFarFuture) {
                uint24 ffk = _tqFarFutureKey(lvl);
                if (ticketQueue[ffk].length > 0) {
                    ticketLevel = lvl | TICKET_FAR_FUTURE_BIT;
                    ticketCursor = 0;
                    finished = false;
                } else {
                    ticketCursor = 0;
                    ticketLevel = 0;
                }
            } else {
                ticketCursor = 0;
                ticketLevel = 0;
            }
        }
    }
}

/// @title TicketEdgeCasesTest -- Proves EDGE-01 (no double-counting) and EDGE-02 (no re-processing)
contract TicketEdgeCasesTest is Test {
    TicketEdgeCasesHarness harness;
    uint24 constant FF_BIT = 1 << 22;
    address constant BUYER = address(0xBEEF);

    function setUp() public {
        harness = new TicketEdgeCasesHarness();
        harness.setLevel(5);
        harness.setTicketWriteSlot(0);
    }

    // =========================================================================
    // Test 1 (EDGE-01): FF key and write key deposits for same level are
    // tracked independently -- no double-counting.
    // Scenario: player deposits to FF key at low level, same player deposits
    // to write key at higher level. ticketsOwedPacked entries are separate.
    // =========================================================================

    function testEdge01NoDoubleCount_FFThenWriteKey() public {
        // At level=5, target=15: isFarFuture = 15 > 5+6 = true -> FF key
        harness.queueTickets(BUYER, 15, 3);

        uint24 ffKey = harness.tqFarFutureKey(15);
        uint24 writeKey = harness.tqWriteKey(15);

        // Deposit went to FF key only
        assertEq(harness.getQueueLength(ffKey), 1, "FF key should have 1 entry");
        assertEq(harness.getQueueLength(writeKey), 0, "write key should be empty");

        // ticketsOwedPacked at FF key has owed=3
        uint40 ffPacked = harness.getTicketsOwedPacked(ffKey, BUYER);
        assertEq(uint32(ffPacked >> 8), 3, "FF key owed should be 3");

        // Advance level: now 15 <= 10+6=16, near-future
        harness.setLevel(10);

        // New deposit at level=10, target=15: isFarFuture = 15 > 10+6 = false -> write key
        harness.queueTickets(BUYER, 15, 5);

        // FF key unchanged
        assertEq(harness.getQueueLength(ffKey), 1, "FF key should still have 1 entry");
        uint40 ffPackedAfter = harness.getTicketsOwedPacked(ffKey, BUYER);
        assertEq(uint32(ffPackedAfter >> 8), 3, "FF key owed should still be 3 (unchanged)");

        // Write key has new entry
        assertEq(harness.getQueueLength(writeKey), 1, "write key should have 1 entry");
        uint40 writePacked = harness.getTicketsOwedPacked(writeKey, BUYER);
        assertEq(uint32(writePacked >> 8), 5, "write key owed should be 5");

        // Key assertion: the two key spaces are independent.
        // Depositing to write key did NOT modify FF key's owed count.
        assertTrue(ffKey != writeKey, "FF key and write key must be different keys");
    }

    // =========================================================================
    // Test 2 (EDGE-01): Both read-side and FF queues have entries for the
    // same level. processBatch drains both sequentially without
    // cross-contamination.
    // =========================================================================

    function testEdge01ProcessBothQueuesIndependently() public {
        uint24 lvl = 15;
        uint24 readKey = harness.tqReadKey(lvl);
        uint24 ffKey = harness.tqFarFutureKey(lvl);

        // Seed both queues: read-side 3 entries, FF 4 entries
        harness.setTicketQueue(readKey, 3);
        harness.setTicketQueue(ffKey, 4);

        // Call 1: drains read-side (3 entries, within budget 10)
        (bool worked1, bool finished1) = harness.processBatch(lvl);
        assertTrue(worked1, "Call 1 should have worked (read-side drained)");
        assertFalse(finished1, "Call 1 should NOT be finished (FF pending)");

        // After read-side drain: ticketLevel encodes FF bit, cursor reset
        assertEq(harness.getTicketLevel(), lvl | FF_BIT, "ticketLevel should encode FF bit");
        assertEq(harness.getTicketCursor(), 0, "cursor should reset for FF phase");

        // Read-side deleted, FF untouched
        assertEq(harness.getQueueLength(readKey), 0, "read-side queue should be deleted");
        assertEq(harness.getQueueLength(ffKey), 4, "FF queue should be untouched (4 entries)");

        // Call 2: drains FF queue (4 entries, within budget 10)
        (bool worked2, bool finished2) = harness.processBatch(lvl);
        assertTrue(worked2, "Call 2 should have worked (FF drained)");
        assertTrue(finished2, "Call 2 should be finished (both queues drained)");

        // After full drain: clean state
        assertEq(harness.getTicketLevel(), 0, "ticketLevel should be 0 after full drain");
        assertEq(harness.getTicketCursor(), 0, "cursor should be 0 after full drain");
        assertEq(harness.getQueueLength(ffKey), 0, "FF queue should be deleted");
    }

    // =========================================================================
    // Test 3 (EDGE-02): After FF key for level L is drained (requiring
    // currentLevel >= L-6), new deposits to level L go to write key, not FF
    // key. Monotonic level progression makes this permanent.
    // =========================================================================

    function testEdge02RoutingPreventsNewFFDeposits() public {
        // level=9: 15 <= 9+6=15, so level 15 is in near-future window (not far-future)
        harness.setLevel(9);
        harness.queueTickets(BUYER, 15, 2);

        uint24 writeKey = harness.tqWriteKey(15);
        uint24 ffKey = harness.tqFarFutureKey(15);

        // Deposit went to write key (isFarFuture = 15 > 9+6 = 15 > 15 = false)
        assertEq(harness.getQueueLength(writeKey), 1, "write key should have 1 entry");
        assertEq(harness.getQueueLength(ffKey), 0, "FF key should be empty");

        // Advance level further: level=15
        harness.setLevel(15);
        // 15 > 15+6 = false, so still goes to write key
        harness.queueTickets(BUYER, 15, 1);

        // Same player already has entry at writeKey, so queue push does not repeat
        // (owed was > 0), but owed increments
        assertEq(harness.getQueueLength(writeKey), 1, "write key still 1 entry (same player accumulated)");
        assertEq(harness.getQueueLength(ffKey), 0, "FF key still empty");

        uint40 writePacked = harness.getTicketsOwedPacked(writeKey, BUYER);
        assertEq(uint32(writePacked >> 8), 3, "write key owed should be 2+1=3 (accumulated)");

        // Key assertion: once level >= L-6 (here 9 >= 15-6=9), the isFarFuture
        // condition (targetLevel > level + 6) is permanently false for level L.
        // New deposits can never reach the FF key for already-near-future levels.
    }

    // =========================================================================
    // Test 4 (EDGE-02): After processBatch fully drains FF key, queue is
    // deleted and cursor/ticketLevel are reset to clean state.
    // =========================================================================

    function testEdge02CleanupAfterDrain() public {
        uint24 lvl = 8;
        uint24 ffKey = harness.tqFarFutureKey(lvl);

        // Set up: FF key for level 8 has 2 entries
        harness.setTicketQueue(ffKey, 2);

        // Pre-set ticketLevel to FF phase (as if read-side was already drained)
        harness.setTicketLevel(lvl | FF_BIT);

        // Drain FF queue (2 entries, within budget 10)
        (bool worked, bool finished) = harness.processBatch(lvl);
        assertTrue(worked, "Should have worked (FF drained)");
        assertTrue(finished, "Should be finished (FF fully drained)");

        // Verify clean state after drain
        assertEq(harness.getQueueLength(ffKey), 0, "FF queue should be deleted");
        assertEq(harness.getTicketLevel(), 0, "ticketLevel should be 0 after drain");
        assertEq(harness.getTicketCursor(), 0, "cursor should be 0 after drain");

        // Note: the simplified processBatch does not write ticketsOwedPacked
        // (it only simulates structural behavior). The full processing loop's
        // per-player zeroing of ticketsOwedPacked is verified by the RESEARCH.md
        // code trace (MintModule lines 418-420: newPacked = 0 when remainingOwed == 0).
    }

    // =========================================================================
    // Test 5 (EDGE-01 supplemental): Level was far-future and only received
    // FF deposits (no write-key deposits). processBatch handles empty
    // read-side correctly and processes FF entries.
    // =========================================================================

    function testEdge01FFOnlyQueue_NoReadSide() public {
        uint24 lvl = 20;
        uint24 readKey = harness.tqReadKey(lvl);
        uint24 ffKey = harness.tqFarFutureKey(lvl);

        // Only FF key has entries (5 entries). Read-side is empty.
        harness.setTicketQueue(ffKey, 5);
        assertEq(harness.getQueueLength(readKey), 0, "read-side should be empty");

        // Call 1: read-side empty, detects FF queue, transitions
        (bool worked1, bool finished1) = harness.processBatch(lvl);
        assertFalse(worked1, "Call 1 should not have worked (just transitioned)");
        assertFalse(finished1, "Call 1 should NOT be finished (FF pending)");
        assertEq(harness.getTicketLevel(), lvl | FF_BIT, "ticketLevel should encode FF bit");

        // Call 2: drains FF queue (5 entries, within budget 10)
        (bool worked2, bool finished2) = harness.processBatch(lvl);
        assertTrue(worked2, "Call 2 should have worked (FF drained)");
        assertTrue(finished2, "Call 2 should be finished (FF fully drained)");

        // Clean state after drain
        assertEq(harness.getTicketLevel(), 0, "ticketLevel should be 0 after FF drain");
        assertEq(harness.getQueueLength(ffKey), 0, "FF queue should be deleted");
    }
}
