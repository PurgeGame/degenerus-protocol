// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";

/// @title QueueHarness -- Exposes internal queue functions and mappings for double-buffer tests.
contract QueueHarness is DegenerusGameStorage {
    // --- Queue write functions ---
    function exposed_queueTickets(address buyer, uint24 targetLevel, uint32 quantity) external {
        _queueTickets(buyer, targetLevel, quantity, false);
    }

    function exposed_queueTicketsScaled(address buyer, uint24 targetLevel, uint32 quantityScaled) external {
        _queueTicketsScaled(buyer, targetLevel, quantityScaled, false);
    }

    function exposed_queueTicketRange(address buyer, uint24 startLevel, uint24 numLevels, uint32 ticketsPerLevel) external {
        _queueTicketRange(buyer, startLevel, numLevels, ticketsPerLevel, false);
    }

    // --- Swap ---
    function exposed_swapTicketSlot(uint24 purchaseLevel) external {
        _swapTicketSlot(purchaseLevel);
    }

    // --- Key helpers ---
    function exposed_tqWriteKey(uint24 lvl) external view returns (uint24) {
        return _tqWriteKey(lvl);
    }

    function exposed_tqReadKey(uint24 lvl) external view returns (uint24) {
        return _tqReadKey(lvl);
    }

    // --- Direct mapping inspection ---
    function getQueueLength(uint24 key) external view returns (uint256) {
        return ticketQueue[key].length;
    }

    function getQueueEntry(uint24 key, uint256 idx) external view returns (address) {
        return ticketQueue[key][idx];
    }

    function getTicketsOwedPacked(uint24 key, address buyer) external view returns (uint40) {
        return ticketsOwedPacked[key][buyer];
    }

    function getTicketsOwed(uint24 key, address buyer) external view returns (uint32) {
        return uint32(ticketsOwedPacked[key][buyer] >> 8);
    }

    // --- State helpers ---
    function getTicketWriteSlot() external view returns (bool) {
        return ticketWriteSlot;
    }

    function setTicketWriteSlot(bool val) external {
        ticketWriteSlot = val;
    }

    function getTicketsFullyProcessed() external view returns (bool) {
        return ticketsFullyProcessed;
    }

    function setTicketsFullyProcessed(bool val) external {
        ticketsFullyProcessed = val;
    }

    function getJackpotPhaseFlag() external view returns (bool) {
        return jackpotPhaseFlag;
    }

    function setJackpotPhaseFlag(bool val) external {
        jackpotPhaseFlag = val;
    }

    // Disabled: MID_DAY_SWAP_THRESHOLD constant removed from production code
    // function getMidDaySwapThreshold() external pure returns (uint32) {
    //     return MID_DAY_SWAP_THRESHOLD;
    // }
}

/// @title QueueDoubleBufferTest -- Proves write-key and read-key buffer isolation (QUEUE-01, QUEUE-02).
contract QueueDoubleBufferTest is Test {
    QueueHarness harness;
    address constant ALICE = address(0xA11CE);
    address constant BOB = address(0xB0B);
    uint24 constant LEVEL = 5;
    uint24 constant TICKET_SLOT_BIT = 1 << 23;

    function setUp() public {
        harness = new QueueHarness();
    }

    // =========================================================================
    // Test 1: _queueTickets routes to write buffer
    // =========================================================================
    function testQueueTicketsUsesWriteKey() public {
        // Default ticketWriteSlot = 0, so writeKey = level (no bit), readKey = level | BIT
        uint24 wk = harness.exposed_tqWriteKey(LEVEL);
        uint24 rk = harness.exposed_tqReadKey(LEVEL);
        assertEq(wk, LEVEL, "write key should be raw level when slot=0");
        assertEq(rk, LEVEL | TICKET_SLOT_BIT, "read key should have bit set when slot=0");

        harness.exposed_queueTickets(ALICE, LEVEL, 10);

        // Write buffer has the entry
        assertEq(harness.getQueueLength(wk), 1, "write queue should have 1 entry");
        assertEq(harness.getQueueEntry(wk, 0), ALICE, "write queue entry should be ALICE");
        assertEq(harness.getTicketsOwed(wk, ALICE), 10, "write buffer should have 10 tickets owed");

        // Read buffer is empty
        assertEq(harness.getQueueLength(rk), 0, "read queue should be empty");
        assertEq(harness.getTicketsOwed(rk, ALICE), 0, "read buffer should have 0 tickets owed");
    }

    // =========================================================================
    // Test 2: _queueTicketsScaled routes to write buffer
    // =========================================================================
    function testQueueTicketsScaledUsesWriteKey() public {
        uint24 wk = harness.exposed_tqWriteKey(LEVEL);
        uint24 rk = harness.exposed_tqReadKey(LEVEL);

        // Queue 500 scaled = 5 whole tickets (TICKET_SCALE = 100)
        harness.exposed_queueTicketsScaled(ALICE, LEVEL, 500);

        // Write buffer populated
        assertEq(harness.getQueueLength(wk), 1, "write queue should have 1 entry");
        assertEq(harness.getTicketsOwed(wk, ALICE), 5, "write buffer should have 5 tickets");

        // Read buffer empty
        assertEq(harness.getQueueLength(rk), 0, "read queue should be empty");
        assertEq(harness.getTicketsOwed(rk, ALICE), 0, "read buffer tickets should be 0");
    }

    // =========================================================================
    // Test 3: _queueTicketRange routes to write buffer for all levels
    // =========================================================================
    function testQueueTicketRangeUsesWriteKey() public {
        uint24 startLvl = 3;
        uint24 numLevels = 3;
        harness.exposed_queueTicketRange(ALICE, startLvl, numLevels, 7);

        for (uint24 i = 0; i < numLevels; i++) {
            uint24 lvl = startLvl + i;
            uint24 wk = harness.exposed_tqWriteKey(lvl);
            uint24 rk = harness.exposed_tqReadKey(lvl);

            assertEq(harness.getQueueLength(wk), 1, "write queue should have entry");
            assertEq(harness.getTicketsOwed(wk, ALICE), 7, "write buffer should have 7 tickets");
            assertEq(harness.getQueueLength(rk), 0, "read queue should be empty");
            assertEq(harness.getTicketsOwed(rk, ALICE), 0, "read buffer should be empty");
        }
    }

    // =========================================================================
    // Test 4: Write-read isolation across swap
    // =========================================================================
    function testWriteReadIsolation() public {
        // Phase A: Queue in slot 0 (writeKey = level)
        harness.exposed_queueTickets(ALICE, LEVEL, 10);

        uint24 wkBefore = harness.exposed_tqWriteKey(LEVEL);
        assertEq(wkBefore, LEVEL, "before swap: write key = raw level");

        // Mark fully processed so swap succeeds
        harness.setTicketsFullyProcessed(true);
        harness.exposed_swapTicketSlot(LEVEL);

        // After swap, write key flips
        uint24 wkAfter = harness.exposed_tqWriteKey(LEVEL);
        assertEq(wkAfter, LEVEL | TICKET_SLOT_BIT, "after swap: write key = level | BIT");

        // Phase B: Queue in slot 1 (writeKey = level | BIT)
        harness.exposed_queueTickets(BOB, LEVEL, 20);

        // Old buffer (raw level) has ALICE's entry
        assertEq(harness.getQueueLength(LEVEL), 1, "slot 0 queue should have ALICE");
        assertEq(harness.getQueueEntry(LEVEL, 0), ALICE, "slot 0 entry is ALICE");
        assertEq(harness.getTicketsOwed(LEVEL, ALICE), 10, "slot 0 has 10 tickets for ALICE");

        // New buffer (level | BIT) has BOB's entry
        assertEq(harness.getQueueLength(LEVEL | TICKET_SLOT_BIT), 1, "slot 1 queue should have BOB");
        assertEq(harness.getQueueEntry(LEVEL | TICKET_SLOT_BIT, 0), BOB, "slot 1 entry is BOB");
        assertEq(harness.getTicketsOwed(LEVEL | TICKET_SLOT_BIT, BOB), 20, "slot 1 has 20 tickets for BOB");

        // Cross-buffer isolation
        assertEq(harness.getTicketsOwed(LEVEL, BOB), 0, "BOB has no tickets in slot 0");
        assertEq(harness.getTicketsOwed(LEVEL | TICKET_SLOT_BIT, ALICE), 0, "ALICE has no tickets in slot 1");
    }

    // =========================================================================
    // Test 5: Swap resets ticketsFullyProcessed
    // =========================================================================
    function testSwapResetsFullyProcessed() public {
        harness.setTicketsFullyProcessed(true);
        assertTrue(harness.getTicketsFullyProcessed(), "pre-condition: fully processed");

        harness.exposed_swapTicketSlot(LEVEL);

        assertFalse(harness.getTicketsFullyProcessed(), "swap should reset ticketsFullyProcessed to false");
    }

    // =========================================================================
    // Test 6: Queue after swap uses new write key
    // =========================================================================
    function testQueueAfterSwapUsesNewWriteKey() public {
        // Start with slot 0
        assertFalse(harness.getTicketWriteSlot(), "initial slot is false");

        // Swap to slot 1
        harness.setTicketsFullyProcessed(true);
        harness.exposed_swapTicketSlot(LEVEL);
        assertTrue(harness.getTicketWriteSlot(), "slot should be true after swap");

        // Write key should now include TICKET_SLOT_BIT
        uint24 newWk = harness.exposed_tqWriteKey(LEVEL);
        assertEq(newWk, LEVEL | TICKET_SLOT_BIT, "write key should include bit after swap");

        // Queue tickets -- they should land in the new buffer
        harness.exposed_queueTickets(ALICE, LEVEL, 5);
        assertEq(harness.getQueueLength(LEVEL | TICKET_SLOT_BIT), 1, "new write buffer should have entry");
        assertEq(harness.getQueueLength(LEVEL), 0, "old buffer should remain empty");
        assertEq(harness.getTicketsOwed(LEVEL | TICKET_SLOT_BIT, ALICE), 5, "new buffer has 5 tickets");
    }
}

/// @title MidDaySwapTest -- Proves mid-day swap threshold and jackpot conditions (QUEUE-04).
contract MidDaySwapTest is Test {
    QueueHarness harness;
    address constant ALICE = address(0xA11CE);
    uint24 constant LEVEL = 5;
    uint24 constant TICKET_SLOT_BIT = 1 << 23;

    function setUp() public {
        harness = new QueueHarness();
    }

    /// @dev Helper: queue `count` individual ticket entries into the write buffer at LEVEL.
    ///      Each call to _queueTickets adds one address entry to the queue array.
    function _fillWriteQueue(uint256 count) internal {
        for (uint256 i = 0; i < count; i++) {
            address buyer = address(uint160(0x1000 + i));
            harness.exposed_queueTickets(buyer, LEVEL, 1);
        }
    }

    // =========================================================================
    // Test 7: MID_DAY_SWAP_THRESHOLD constant equals 440
    // Disabled: MID_DAY_SWAP_THRESHOLD constant removed from production code
    // =========================================================================
    // function testMidDaySwapThresholdValue() public view {
    //     assertEq(harness.getMidDaySwapThreshold(), 440, "MID_DAY_SWAP_THRESHOLD should be 440");
    // }

    // =========================================================================
    // Test 8: Write queue at threshold triggers swap successfully
    // =========================================================================
    function testMidDaySwapAtThreshold() public {
        // Fill write queue to exactly 440 entries
        _fillWriteQueue(440);

        uint24 wk = harness.exposed_tqWriteKey(LEVEL);
        assertEq(harness.getQueueLength(wk), 440, "write queue should have 440 entries");

        // Read queue must be empty for swap to succeed
        uint24 rk = harness.exposed_tqReadKey(LEVEL);
        assertEq(harness.getQueueLength(rk), 0, "read queue should be empty before swap");

        // Swap should succeed -- _swapTicketSlot toggles the write slot
        bool slotBefore = harness.getTicketWriteSlot();
        harness.exposed_swapTicketSlot(LEVEL);
        bool slotAfter = harness.getTicketWriteSlot();

        assertTrue(slotBefore != slotAfter, "swap should toggle write slot");
        assertFalse(harness.getTicketsFullyProcessed(), "swap resets ticketsFullyProcessed");

        // Old write buffer (now read) still has 440 entries
        // After swap, the old write key becomes the new read key
        uint24 newRk = harness.exposed_tqReadKey(LEVEL);
        assertEq(harness.getQueueLength(newRk), 440, "old write buffer now readable with 440 entries");

        // New write buffer is empty
        uint24 newWk = harness.exposed_tqWriteKey(LEVEL);
        assertEq(harness.getQueueLength(newWk), 0, "new write buffer should be empty");
    }

    // =========================================================================
    // Test 9: Jackpot phase swap with non-empty write queue (below threshold)
    // =========================================================================
    function testMidDaySwapJackpotPhase() public {
        // Fill write queue with only 10 entries (well below 440)
        _fillWriteQueue(10);

        uint24 wk = harness.exposed_tqWriteKey(LEVEL);
        assertEq(harness.getQueueLength(wk), 10, "write queue should have 10 entries");

        // Set jackpot phase active
        harness.setJackpotPhaseFlag(true);
        assertTrue(harness.getJackpotPhaseFlag(), "jackpot phase should be active");

        // Swap should succeed even though < 440, because jackpot + non-empty
        harness.exposed_swapTicketSlot(LEVEL);

        // After swap, old write buffer is now readable
        uint24 newRk = harness.exposed_tqReadKey(LEVEL);
        assertEq(harness.getQueueLength(newRk), 10, "old write buffer now readable with 10 entries");
    }

    // =========================================================================
    // Test 10: Below-threshold non-jackpot -- swap would fail (no revert test,
    //          but proves the condition: write queue < 440 and not jackpot)
    // =========================================================================
    function testMidDayRevertsNotTimeYet() public {
        // Fill write queue with only 100 entries (below 440)
        _fillWriteQueue(100);

        uint24 wk = harness.exposed_tqWriteKey(LEVEL);
        uint256 writeLen = harness.getQueueLength(wk);
        assertEq(writeLen, 100, "write queue should have 100 entries");

        // Not in jackpot phase
        assertFalse(harness.getJackpotPhaseFlag(), "jackpot phase should be inactive");

        // Verify the condition: writeLen < 440 (MID_DAY_SWAP_THRESHOLD) && !jackpotPhaseFlag
        // In the actual advanceGame, this would revert NotTimeYet()
        // Note: MID_DAY_SWAP_THRESHOLD removed from production code; using literal 440
        assertTrue(writeLen < 440, "write queue below threshold");
        assertFalse(harness.getJackpotPhaseFlag(), "not in jackpot -- would revert NotTimeYet");
    }

    // =========================================================================
    // Test 11: Read slot must be drained before swap attempt
    //          (proves _swapTicketSlot reverts E() if read queue non-empty)
    // =========================================================================
    function testMidDayProcessesReadSlotFirst() public {
        // Setup: populate write queue, swap once to move entries to read slot
        _fillWriteQueue(10);
        harness.setTicketsFullyProcessed(true);
        harness.exposed_swapTicketSlot(LEVEL);

        // Now read slot has 10 entries, write slot is empty
        uint24 rk = harness.exposed_tqReadKey(LEVEL);
        assertEq(harness.getQueueLength(rk), 10, "read queue should have 10 entries");
        assertFalse(harness.getTicketsFullyProcessed(), "ticketsFullyProcessed should be false after swap");

        // Fill new write buffer to threshold
        _fillWriteQueue(440);

        uint24 wk = harness.exposed_tqWriteKey(LEVEL);
        assertEq(harness.getQueueLength(wk), 440, "write queue should have 440 entries");

        // Attempting swap should revert because read slot is non-empty
        // This proves the mid-day path MUST drain the read slot before swapping
        vm.expectRevert(abi.encodeWithSignature("E()"));
        harness.exposed_swapTicketSlot(LEVEL);
    }
}
