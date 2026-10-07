// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {WalletSeed} from "../helpers/WalletSeed.sol";

/// @dev Exercises production near/far routing and owed records across a level transition.
contract TicketEdgeCasesHarness is WalletSeed {
    function queueTickets(address buyer, uint24 targetLevel, uint32 quantity) external {
        _queueEntries(_seedWallet(buyer), targetLevel, quantity, false);
    }

    function setLevel(uint24 lvl) external {
        level = lvl;
    }

    function setTicketWriteSlot(bool v) external {
        ticketWriteSlot = v;
    }

    function getQueueLength(uint24 key) external view returns (uint256) {
        return _ticketQueueLength(key);
    }

    function getTicketsOwedPacked(uint24 key, address player) external view returns (uint80) {
        return _owedOf(key, player);
    }

    function tqWriteKey(uint24 lvl) external view returns (uint24) {
        return _tqWriteKey(lvl);
    }

    function tqFarFutureKey(uint24 lvl) external pure returns (uint24) {
        return _tqFarFutureKey(lvl);
    }

}

contract TicketEdgeCasesTest is Test {
    TicketEdgeCasesHarness harness;
    uint24 constant FF_BIT = 1 << 22;
    address constant BUYER = address(0xBEEF);

    function setUp() public {
        // Warp past JACKPOT_RESET_TIME (82620s) so the inherited _queueEntries ->
        // _livenessTriggered -> GameTimeLib.currentDayIndexAt(block.timestamp) day math
        // does not underflow (ts - JACKPOT_RESET_TIME) at the default ts=1.
        vm.warp(block.timestamp + 1 days);
        harness = new TicketEdgeCasesHarness();
        harness.setLevel(5);
        harness.setTicketWriteSlot(false);
    }

    function testEdge01NoDoubleCount_FFThenWriteKey() public {
        // At level=5, target=15: isFarFuture = 15 > mintCeiling(5)=6 -> FF key
        harness.queueTickets(BUYER, 15, 3);

        uint24 ffKey = harness.tqFarFutureKey(15);
        uint24 writeKey = harness.tqWriteKey(15);

        // Deposit went to FF key only
        assertEq(harness.getQueueLength(ffKey), 1, "FF key should have 1 entry");
        assertEq(harness.getQueueLength(writeKey), 0, "write key should be empty");

        // entriesOwedPacked at FF key has owed=3
        uint80 ffPacked = harness.getTicketsOwedPacked(ffKey, BUYER);
        assertEq(uint32(ffPacked >> 8), 3, "FF key owed should be 3");

        // Advance level: now 15 <= mintCeiling(14)=15, near-future
        harness.setLevel(14);

        // New deposit at level=14, target=15: isFarFuture = 15 > mintCeiling(14)=15 -> false -> write key
        harness.queueTickets(BUYER, 15, 5);

        // FF key unchanged
        assertEq(harness.getQueueLength(ffKey), 1, "FF key should still have 1 entry");
        uint80 ffPackedAfter = harness.getTicketsOwedPacked(ffKey, BUYER);
        assertEq(uint32(ffPackedAfter >> 8), 3, "FF key owed should still be 3 (unchanged)");

        // Write key has new entry
        assertEq(harness.getQueueLength(writeKey), 1, "write key should have 1 entry");
        uint80 writePacked = harness.getTicketsOwedPacked(writeKey, BUYER);
        assertEq(uint32(writePacked >> 8), 5, "write key owed should be 5");

        // Key assertion: the two key spaces are independent.
        // Depositing to write key did NOT modify FF key's owed count.
        assertTrue(ffKey != writeKey, "FF key and write key must be different keys");
    }

    function testEdge02RoutingPreventsNewFFDeposits() public {
        // level=13: mintCeiling(13)=14, so level 14 is in the near-future window (not far-future)
        harness.setLevel(13);
        harness.queueTickets(BUYER, 14, 2);

        uint24 writeKey = harness.tqWriteKey(14);
        uint24 ffKey = harness.tqFarFutureKey(14);

        // Deposit went to write key (isFarFuture = 14 > mintCeiling(13)=14 -> false)
        assertEq(harness.getQueueLength(writeKey), 1, "write key should have 1 entry");
        assertEq(harness.getQueueLength(ffKey), 0, "FF key should be empty");

        // Advance level further: level=20
        harness.setLevel(20);
        // 14 > mintCeiling(20)=21 = false, so still goes to write key
        harness.queueTickets(BUYER, 14, 1);

        // Same player already has entry at writeKey, so queue push does not repeat
        // (owed was > 0), but owed increments
        assertEq(harness.getQueueLength(writeKey), 1, "write key still 1 entry (same player accumulated)");
        assertEq(harness.getQueueLength(ffKey), 0, "FF key still empty");

        uint80 writePacked = harness.getTicketsOwedPacked(writeKey, BUYER);
        assertEq(uint32(writePacked >> 8), 3, "write key owed should be 2+1=3 (accumulated)");

        // Key assertion: once level has passed a target level (here 20 >= 14), the
        // isFarFuture condition (targetLevel > mintCeiling) is permanently false for
        // that level. New deposits can never reach the FF key for already-near-future
        // levels.
    }

}
