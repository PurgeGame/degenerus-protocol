// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";

/// @title TicketProcessingFFHarness -- Simplified harness for dual-queue drain + cursor encoding tests
/// @dev Replicates the PROPOSED processFutureTicketBatch logic (dual-queue drain with FF bit)
///      and the PROPOSED _prepareFutureTickets (with FF bit stripping for resume).
///      Uses a simplified batch processing model: each queue entry = 1 write unit, budget = 10.
///      This isolates the structural extension logic from the trait-generation internals.
contract TicketProcessingFFHarness is DegenerusGameStorage {
    uint32 public constant BUDGET = 10;

    // -- State setters --

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

    function setRngWordCurrent(uint256 v) external {
        rngWordCurrent = v;
    }

    function setTicketWriteSlot(bool v) external {
        ticketWriteSlot = v;
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

    // -- Key helpers (exposed) --

    function tqReadKey(uint24 lvl) external view returns (uint24) {
        return _tqReadKey(lvl);
    }

    function tqFarFutureKey(uint24 lvl) external pure returns (uint24) {
        return _tqFarFutureKey(lvl);
    }

    // -- Simplified processBatch replicating PROPOSED dual-queue drain logic --
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

    // -- Simplified _prepareFutureTickets replicating PROPOSED resume fix --
    // Calls processBatch for levels lvl+2..lvl+6 with FF bit stripping for resume.
    // Returns true when all target levels fully processed.

    function prepareFutureTicketsTest(uint24 lvl) external returns (bool finished) {
        uint24 startLevel = lvl + 2;
        uint24 endLevel = lvl + 6;
        uint24 resumeLevel = ticketLevel;
        // Strip FF bit to get base level for range comparison
        uint24 baseResume = resumeLevel & ~uint24(TICKET_FAR_FUTURE_BIT);

        // Continue an in-flight future level first to preserve progress
        if (baseResume >= startLevel && baseResume <= endLevel) {
            (bool worked, bool levelFinished) = this.processBatch(baseResume);
            if (worked || !levelFinished) return false;
        }

        // Then probe remaining target levels in order
        for (uint24 target = startLevel; target <= endLevel; ) {
            if (target != baseResume) {
                (bool worked, bool levelFinished) = this.processBatch(target);
                if (worked || !levelFinished) return false;
            }
            unchecked {
                ++target;
            }
        }
        return true;
    }
}

/// @title TicketProcessingFFTest -- Proves dual-queue drain + cursor encoding + resume behaviors
contract TicketProcessingFFTest is Test {
    TicketProcessingFFHarness harness;
    uint24 constant FF_BIT = 1 << 22;

    function setUp() public {
        harness = new TicketProcessingFFHarness();
        // ticketWriteSlot = 0 by default, so readKey = lvl | SLOT_BIT (bit 23)
    }

    // =========================================================================
    // Test 1 (PROC-01 + PROC-03): Read-side non-empty, FF non-empty
    // Drains read-side first, returns finished=false, then FF, returns finished=true
    // =========================================================================

    function testDualQueueDrain_ReadSideThenFF() public {
        uint24 lvl = 5;
        uint24 rk = harness.tqReadKey(lvl);
        uint24 ffk = harness.tqFarFutureKey(lvl);

        // Seed both queues: 3 entries each (well within budget of 10)
        harness.setTicketQueue(rk, 3);
        harness.setTicketQueue(ffk, 3);

        // Call 1: should drain read-side queue (3 entries, budget=10), then signal FF pending
        (bool worked1, bool finished1) = harness.processBatch(lvl);
        assertTrue(worked1, "Call 1 should have worked (read-side drained)");
        assertFalse(finished1, "Call 1 should NOT be finished (FF queue pending)");
        assertEq(harness.getTicketLevel(), lvl | FF_BIT, "ticketLevel should encode FF bit after read-side drain");
        assertEq(harness.getTicketCursor(), 0, "cursor should reset for FF phase");
        assertEq(harness.getQueueLength(rk), 0, "read-side queue should be deleted");

        // Call 2: should drain FF queue
        (bool worked2, bool finished2) = harness.processBatch(lvl);
        assertTrue(worked2, "Call 2 should have worked (FF drained)");
        assertTrue(finished2, "Call 2 should be finished (both queues drained)");
        assertEq(harness.getTicketLevel(), 0, "ticketLevel should be 0 after full drain");
        assertEq(harness.getTicketCursor(), 0, "cursor should be 0 after full drain");
        assertEq(harness.getQueueLength(ffk), 0, "FF queue should be deleted");
    }

    // =========================================================================
    // Test 2 (PROC-01): Read-side empty, FF non-empty
    // Transitions to FF immediately, next call processes FF
    // =========================================================================

    function testEmptyReadSide_TransitionsToFF() public {
        uint24 lvl = 8;
        uint24 ffk = harness.tqFarFutureKey(lvl);

        // Only FF queue has entries
        harness.setTicketQueue(ffk, 5);

        // Call 1: read-side empty, should transition to FF
        (bool worked1, bool finished1) = harness.processBatch(lvl);
        assertFalse(worked1, "Call 1 should not have worked (just transitioned)");
        assertFalse(finished1, "Call 1 should NOT be finished (FF pending)");
        assertEq(harness.getTicketLevel(), lvl | FF_BIT, "ticketLevel should encode FF bit");

        // Call 2: should process FF queue
        (bool worked2, bool finished2) = harness.processBatch(lvl);
        assertTrue(worked2, "Call 2 should have worked (FF processed)");
        assertTrue(finished2, "Call 2 should be finished");
        assertEq(harness.getTicketLevel(), 0, "ticketLevel should be 0");
    }

    // =========================================================================
    // Test 3 (PROC-03): Read-side non-empty, FF empty
    // Drains read-side and returns finished=true (no FF phase needed)
    // =========================================================================

    function testReadSideOnly_NoFFPhase() public {
        uint24 lvl = 3;
        uint24 rk = harness.tqReadKey(lvl);

        harness.setTicketQueue(rk, 4);

        (bool worked, bool finished) = harness.processBatch(lvl);
        assertTrue(worked, "Should have worked");
        assertTrue(finished, "Should be finished (FF queue empty)");
        assertEq(harness.getTicketLevel(), 0, "ticketLevel should be 0");
        assertEq(harness.getTicketCursor(), 0, "cursor should be 0");
        assertEq(harness.getQueueLength(rk), 0, "read-side queue should be deleted");
    }

    // =========================================================================
    // Test 4 (PROC-03): Both queues empty
    // Returns (false, true) immediately
    // =========================================================================

    function testBothQueuesEmpty_ImmediateFinish() public {
        uint24 lvl = 10;

        (bool worked, bool finished) = harness.processBatch(lvl);
        assertFalse(worked, "Should not have worked (nothing to process)");
        assertTrue(finished, "Should be finished (both empty)");
        assertEq(harness.getTicketLevel(), 0, "ticketLevel should be 0");
        assertEq(harness.getTicketCursor(), 0, "cursor should be 0");
    }

    // =========================================================================
    // Test 5 (PROC-02): After read-side drain with FF pending,
    //   ticketLevel == lvl | TICKET_FAR_FUTURE_BIT
    // =========================================================================

    function testTicketLevelEncodesFFBit_AfterReadSideDrain() public {
        uint24 lvl = 12;
        uint24 rk = harness.tqReadKey(lvl);
        uint24 ffk = harness.tqFarFutureKey(lvl);

        harness.setTicketQueue(rk, 2);
        harness.setTicketQueue(ffk, 2);

        // Drain read-side
        harness.processBatch(lvl);

        // Verify ticketLevel encoding
        uint24 expectedLevel = lvl | FF_BIT;
        assertEq(harness.getTicketLevel(), expectedLevel, "ticketLevel must have FF bit set");
        assertEq(harness.getTicketLevel() & FF_BIT, FF_BIT, "FF bit must be set");
        assertEq(harness.getTicketLevel() & ~uint24(FF_BIT), lvl, "base level must be preserved");
    }

    // =========================================================================
    // Test 6 (PROC-02): During FF processing ticketLevel has FF bit;
    //   after FF drain, ticketLevel == 0
    // =========================================================================

    function testTicketLevelEncoding_DuringAndAfterFF() public {
        uint24 lvl = 7;
        uint24 ffk = harness.tqFarFutureKey(lvl);

        // Set up: directly in FF phase (skip read-side by pre-setting ticketLevel)
        harness.setTicketQueue(ffk, 15); // More than budget (10), so first call won't finish
        harness.setTicketLevel(lvl | FF_BIT);

        // Call 1: processes 10 entries (budget), FF not drained yet
        (bool worked1, bool finished1) = harness.processBatch(lvl);
        assertTrue(worked1, "Should have worked");
        assertFalse(finished1, "Should NOT be finished (5 entries remaining)");
        assertEq(harness.getTicketLevel() & FF_BIT, FF_BIT, "FF bit should still be set during FF processing");
        assertEq(harness.getTicketCursor(), 10, "cursor should be at 10");

        // Call 2: processes remaining 5 entries
        (bool worked2, bool finished2) = harness.processBatch(lvl);
        assertTrue(worked2, "Should have worked");
        assertTrue(finished2, "Should be finished");
        assertEq(harness.getTicketLevel(), 0, "ticketLevel should be 0 after FF drain");
        assertEq(harness.getTicketCursor(), 0, "cursor should be 0 after FF drain");
    }

    // =========================================================================
    // Test 7 (PROC-02): _prepareFutureTickets correctly resumes when
    //   ticketLevel has FF bit (baseResume in range)
    // =========================================================================

    function testPrepareFutureTickets_ResumesFFEncoded() public {
        // Setup: level = 4, so _prepareFutureTickets probes levels 6..10
        uint24 lvl = 4;
        uint24 targetLvl = 8; // within range [6, 10]
        uint24 ffk = harness.tqFarFutureKey(targetLvl);

        // Pre-set: we're mid-FF-processing for level 8
        harness.setTicketQueue(ffk, 3);
        harness.setTicketLevel(targetLvl | FF_BIT);

        // prepareFutureTicketsTest should strip FF bit and resume processing level 8
        bool finished = harness.prepareFutureTicketsTest(lvl);

        // With 3 entries (budget=10), should finish in one call
        // But prepareFutureTickets returns false if worked==true (even if levelFinished)
        // because: "if (worked || !levelFinished) return false"
        // worked=true after draining 3 entries, so returns false
        assertFalse(finished, "Should not be fully finished (worked=true causes early return)");

        // The FF queue for level 8 should be drained
        assertEq(harness.getQueueLength(ffk), 0, "FF queue for level 8 should be drained");
        // ticketLevel should be 0 after draining both queues for level 8
        assertEq(harness.getTicketLevel(), 0, "ticketLevel should be 0 after completing level 8");
    }

    // =========================================================================
    // Test 8: Mid-batch budget exhaustion during read-side preserves cursor
    // =========================================================================

    function testBudgetExhaustion_ReadSide_PreservesCursor() public {
        uint24 lvl = 6;
        uint24 rk = harness.tqReadKey(lvl);

        // 25 entries > budget of 10, so first call processes 10
        harness.setTicketQueue(rk, 25);

        // Call 1: processes 10 entries
        (bool worked1, bool finished1) = harness.processBatch(lvl);
        assertTrue(worked1, "Should have worked");
        assertFalse(finished1, "Should NOT be finished (15 entries remaining)");
        assertEq(harness.getTicketCursor(), 10, "cursor should be at 10");
        assertEq(harness.getTicketLevel(), lvl, "ticketLevel should be set to lvl");

        // Call 2: processes next 10
        (bool worked2, bool finished2) = harness.processBatch(lvl);
        assertTrue(worked2, "Should have worked");
        assertFalse(finished2, "Should NOT be finished (5 entries remaining)");
        assertEq(harness.getTicketCursor(), 20, "cursor should be at 20");

        // Call 3: processes remaining 5, finishes
        (bool worked3, bool finished3) = harness.processBatch(lvl);
        assertTrue(worked3, "Should have worked");
        assertTrue(finished3, "Should be finished");
        assertEq(harness.getTicketCursor(), 0, "cursor should be 0 after drain");
        assertEq(harness.getTicketLevel(), 0, "ticketLevel should be 0 after drain");
    }

    // =========================================================================
    // Test 9: Mid-batch budget exhaustion during FF phase preserves cursor
    // =========================================================================

    function testBudgetExhaustion_FFPhase_PreservesCursor() public {
        uint24 lvl = 9;
        uint24 ffk = harness.tqFarFutureKey(lvl);

        // Set up directly in FF phase with 25 entries
        harness.setTicketQueue(ffk, 25);
        harness.setTicketLevel(lvl | FF_BIT);

        // Call 1: processes 10 entries
        (bool worked1, bool finished1) = harness.processBatch(lvl);
        assertTrue(worked1, "Should have worked");
        assertFalse(finished1, "Should NOT be finished");
        assertEq(harness.getTicketCursor(), 10, "cursor should be at 10");
        assertEq(harness.getTicketLevel(), lvl | FF_BIT, "ticketLevel should retain FF bit");

        // Call 2: processes next 10
        (bool worked2, bool finished2) = harness.processBatch(lvl);
        assertTrue(worked2, "Should have worked");
        assertFalse(finished2, "Should NOT be finished");
        assertEq(harness.getTicketCursor(), 20, "cursor should be at 20");
        assertEq(harness.getTicketLevel(), lvl | FF_BIT, "ticketLevel should still have FF bit");

        // Call 3: processes remaining 5, finishes
        (bool worked3, bool finished3) = harness.processBatch(lvl);
        assertTrue(worked3, "Should have worked");
        assertTrue(finished3, "Should be finished (FF fully drained)");
        assertEq(harness.getTicketCursor(), 0, "cursor should be 0");
        assertEq(harness.getTicketLevel(), 0, "ticketLevel should be 0");
    }
}
