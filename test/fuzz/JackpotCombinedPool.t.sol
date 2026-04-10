// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";

/// @title JackpotCombinedPoolHarness -- Replicates PROPOSED combined pool selection logic
/// @dev Since _awardFarFutureCoinJackpot is private (not internal), we replicate the
///      proposed combined pool selection in a standalone harness extending DegenerusGameStorage.
///      This follows the same pattern as TicketRouting.t.sol (Phase 75) and
///      TicketProcessingFF.t.sol (Phase 76).
contract JackpotCombinedPoolHarness is DegenerusGameStorage {

    // -- State setters --

    /// @dev Push `count` addresses into ticketQueue[key] as address(uint160(i+1))
    function setTicketQueue(uint24 key, uint256 count) external {
        for (uint256 i = 0; i < count; i++) {
            ticketQueue[key].push(address(uint160(i + 1)));
        }
    }

    /// @dev Set ticketWriteSlot for read key computation
    function setTicketWriteSlot(bool v) external {
        ticketWriteSlot = v;
    }

    // -- Key helpers (exposed) --

    function tqReadKey(uint24 lvl) external view returns (uint24) {
        return _tqReadKey(lvl);
    }

    function tqWriteKey(uint24 lvl) external view returns (uint24) {
        return _tqWriteKey(lvl);
    }

    function tqFarFutureKey(uint24 lvl) external pure returns (uint24) {
        return _tqFarFutureKey(lvl);
    }

    // -- Queue inspection --

    function getQueueLength(uint24 key) external view returns (uint256) {
        return ticketQueue[key].length;
    }

    function getQueueEntry(uint24 key, uint256 idx) external view returns (address) {
        return ticketQueue[key][idx];
    }

    // -- Combined pool selection (core under test) --

    /// @dev PROPOSED combined pool logic -- matches 77-RESEARCH.md code example exactly.
    ///      Reads from both the frozen read buffer (_tqReadKey) and the FF key (_tqFarFutureKey).
    function selectWinner(uint24 candidate, uint256 entropy)
        external view returns (address winner, bool found)
    {
        (winner, found) = _selectWinner(candidate, entropy);
    }

    function _selectWinner(uint24 candidate, uint256 entropy)
        internal view returns (address winner, bool found)
    {
        address[] storage readQueue = ticketQueue[_tqReadKey(candidate)];
        uint256 readLen = readQueue.length;
        address[] storage ffQueue = ticketQueue[_tqFarFutureKey(candidate)];
        uint256 ffLen = ffQueue.length;
        uint256 combinedLen = readLen + ffLen;

        if (combinedLen != 0) {
            uint256 idx = (entropy >> 32) % combinedLen;
            winner = idx < readLen
                ? readQueue[idx]
                : ffQueue[idx - readLen];
            found = (winner != address(0));
        }
    }

    // -- Entropy step replica --

    function _entropyStep(uint256 state) private pure returns (uint256) {
        unchecked {
            state ^= state << 7;
            state ^= state >> 9;
            state ^= state << 8;
        }
        return state;
    }

    // -- Full loop simulation --

    /// @dev Replicates the full _awardFarFutureCoinJackpot entropy chain and winner selection
    function simulateJackpot(uint24 lvl, uint256 rngWord)
        external view returns (address[10] memory winners, uint24[10] memory levels, uint8 found)
    {
        uint256 entropy = rngWord ^ (uint256(lvl) << 192) ^ uint256(keccak256("far-future-coin"));
        for (uint8 s; s < 10; ) {
            entropy = _entropyStep(entropy ^ uint256(s));
            uint24 candidate = lvl + 5 + uint24(entropy % 95);
            (address winner, bool ok) = _selectWinner(candidate, entropy);
            if (ok) {
                winners[found] = winner;
                levels[found] = candidate;
                unchecked { ++found; }
            }
            unchecked { ++s; }
        }
    }
}

/// @title JackpotCombinedPoolTest -- Proves combined pool selection correctness
/// @dev Tests JACK-01 (both queues read), JACK-02 (index routing), EDGE-03 (readKey not writeKey)
contract JackpotCombinedPoolTest is Test {
    JackpotCombinedPoolHarness harness;

    function setUp() public {
        harness = new JackpotCombinedPoolHarness();
        // ticketWriteSlot = 0 means:
        //   writeKey = raw level (slot 0)
        //   readKey  = level | TICKET_SLOT_BIT (slot 1)
        harness.setTicketWriteSlot(false);
    }

    // =========================================================================
    // Test 1: JACK-01 -- Combined pool reads both queues
    // =========================================================================
    function testCombinedPoolReadsBothQueues() public {
        uint24 lvl = 20;
        uint24 readKey = harness.tqReadKey(lvl);
        uint24 ffKey = harness.tqFarFutureKey(lvl);

        // Push 5 entries into read buffer, 3 into FF key
        harness.setTicketQueue(readKey, 5);
        harness.setTicketQueue(ffKey, 3);

        // combinedLen = 5 + 3 = 8
        // Craft entropy so (entropy >> 32) % 8 picks a valid index
        // Use targetIdx = 6 (falls in FF range [5, 8))
        uint256 entropy = uint256(6) << 32;

        (address winner, bool found) = harness.selectWinner(lvl, entropy);
        assertTrue(found, "winner should be found from combined pool");
        assertTrue(winner != address(0), "winner should be non-zero");

        // Verify queues are unchanged (read-only, no mutation)
        assertEq(harness.getQueueLength(readKey), 5, "read queue unchanged");
        assertEq(harness.getQueueLength(ffKey), 3, "ff queue unchanged");
    }

    // =========================================================================
    // Test 2: JACK-01 boundary -- Only read buffer has entries, FF empty
    // =========================================================================
    function testReadBufferOnlyWhenFFEmpty() public {
        uint24 lvl = 20;
        uint24 readKey = harness.tqReadKey(lvl);

        // Push 5 entries into read buffer, FF queue stays empty
        harness.setTicketQueue(readKey, 5);

        // combinedLen = 5, ffLen = 0
        // targetIdx = 2 (falls in read buffer range [0, 5))
        uint256 entropy = uint256(2) << 32;

        (address winner, bool found) = harness.selectWinner(lvl, entropy);
        assertTrue(found, "winner should be found from read buffer");
        // winner should be readQueue[2] = address(uint160(3))
        assertEq(winner, address(uint160(3)), "winner is readQueue[2]");
    }

    // =========================================================================
    // Test 3: JACK-01 boundary -- Only FF key has entries, read buffer empty
    // =========================================================================
    function testFFKeyOnlyWhenReadEmpty() public {
        uint24 lvl = 20;
        uint24 ffKey = harness.tqFarFutureKey(lvl);

        // FF queue has 4 entries, read buffer empty
        harness.setTicketQueue(ffKey, 4);

        // combinedLen = 4, readLen = 0
        // targetIdx = 1
        uint256 entropy = uint256(1) << 32;

        (address winner, bool found) = harness.selectWinner(lvl, entropy);
        assertTrue(found, "winner should be found from FF key");
        // idx=1 >= readLen=0, so reads ffQueue[1-0] = ffQueue[1] = address(uint160(2))
        assertEq(winner, address(uint160(2)), "winner is ffQueue[1]");
    }

    // =========================================================================
    // Test 4: Division safety -- Both queues empty, no revert
    // =========================================================================
    function testBothQueuesEmptyNoRevert() public view {
        uint24 lvl = 20;
        uint256 entropy = uint256(42) << 32;

        (address winner, bool found) = harness.selectWinner(lvl, entropy);
        assertFalse(found, "found should be false when both queues empty");
        assertEq(winner, address(0), "winner should be zero when both queues empty");
    }

    // =========================================================================
    // Test 5: JACK-02 -- Winner index routing to read buffer
    // =========================================================================
    function testWinnerIndexRoutingToReadBuffer() public {
        uint24 lvl = 20;
        uint24 readKey = harness.tqReadKey(lvl);
        uint24 ffKey = harness.tqFarFutureKey(lvl);

        // 10 entries in read buffer, 5 in FF key
        harness.setTicketQueue(readKey, 10);
        harness.setTicketQueue(ffKey, 5);

        // combinedLen = 15. Pick idx=7 (falls in read buffer range [0, 10))
        uint256 entropy = uint256(7) << 32;

        (address winner, bool found) = harness.selectWinner(lvl, entropy);
        assertTrue(found, "winner found in read buffer range");
        // readQueue[7] = address(uint160(8))
        assertEq(winner, address(uint160(8)), "winner is readQueue[7]");
    }

    // =========================================================================
    // Test 6: JACK-02 -- Winner index routing to FF key
    // =========================================================================
    function testWinnerIndexRoutingToFFKey() public {
        uint24 lvl = 20;
        uint24 readKey = harness.tqReadKey(lvl);
        uint24 ffKey = harness.tqFarFutureKey(lvl);

        // 10 entries in read buffer, 5 in FF key
        harness.setTicketQueue(readKey, 10);
        harness.setTicketQueue(ffKey, 5);

        // combinedLen = 15. Pick idx=12 (falls in FF range [10, 15))
        uint256 entropy = uint256(12) << 32;

        (address winner, bool found) = harness.selectWinner(lvl, entropy);
        assertTrue(found, "winner found in FF range");
        // ffQueue[12 - 10] = ffQueue[2] = address(uint160(3))
        assertEq(winner, address(uint160(3)), "winner is ffQueue[2]");
    }

    // =========================================================================
    // Test 7: JACK-02 boundary -- Winner index exactly at readLen boundary
    // =========================================================================
    function testWinnerIndexAtBoundary() public {
        uint24 lvl = 20;
        uint24 readKey = harness.tqReadKey(lvl);
        uint24 ffKey = harness.tqFarFutureKey(lvl);

        // 3 entries in read buffer, 4 in FF key
        harness.setTicketQueue(readKey, 3);
        harness.setTicketQueue(ffKey, 4);

        // combinedLen = 7. Pick idx=3 (exactly at readLen boundary)
        // idx=3 >= readLen=3, so routes to ffQueue[3-3] = ffQueue[0]
        uint256 entropy = uint256(3) << 32;

        (address winner, bool found) = harness.selectWinner(lvl, entropy);
        assertTrue(found, "winner found at boundary");
        // ffQueue[0] = address(uint160(1))
        assertEq(winner, address(uint160(1)), "boundary routes to ffQueue[0]");
    }

    // =========================================================================
    // Test 8: EDGE-03 -- Uses _tqReadKey not _tqWriteKey for double-buffer portion
    // =========================================================================
    function testUsesReadKeyNotWriteKey() public {
        uint24 lvl = 20;
        // With ticketWriteSlot = 0:
        //   writeKey(20) = 20 (raw level)
        //   readKey(20)  = 20 | TICKET_SLOT_BIT = 20 | (1 << 23) = 8388628
        uint24 writeKey = harness.tqWriteKey(lvl);
        uint24 readKey = harness.tqReadKey(lvl);
        uint24 ffKey = harness.tqFarFutureKey(lvl);

        // Verify keys are different
        assertTrue(writeKey != readKey, "write and read keys must differ");

        // Push 5 entries into the WRITE key (should be invisible to selectWinner)
        harness.setTicketQueue(writeKey, 5);

        // Push 3 entries into the FF key
        harness.setTicketQueue(ffKey, 3);

        // Read key is empty (0 entries). If selectWinner used _tqWriteKey,
        // combinedLen would be 5 + 3 = 8. But since it uses _tqReadKey,
        // combinedLen = 0 + 3 = 3 (only FF entries counted).
        uint256 entropy = uint256(1) << 32;

        (address winner, bool found) = harness.selectWinner(lvl, entropy);
        assertTrue(found, "winner found from FF key only");

        // The winner must come from the FF queue, not the write buffer.
        // ffQueue[1-0] = ffQueue[1] = address(uint160(2))
        assertEq(winner, address(uint160(2)), "winner is from FF key, not write buffer");

        // Verify that the function reads readKey (empty) not writeKey (5 entries)
        // If it read writeKey, idx=1 in range [0,5) would give writeQueue[1] = address(2)
        // which happens to match... so also verify with a different angle:
        // Check that combinedLen = 3 by trying idx that would be valid for 8 but invalid for 3
        // targetIdx = 5 would be valid for combinedLen=8 but maps to 5%3=2 for combinedLen=3
        uint256 entropy2 = uint256(5) << 32;
        (address winner2,) = harness.selectWinner(lvl, entropy2);
        // If combinedLen=8: idx=5 >= readLen=5 (write key has 5), so ffQueue[0] = address(1)
        // If combinedLen=3: idx=5%3=2, idx=2 >= readLen=0, so ffQueue[2] = address(3)
        assertEq(winner2, address(uint160(3)), "confirms combinedLen=3, not 8");
    }
}
