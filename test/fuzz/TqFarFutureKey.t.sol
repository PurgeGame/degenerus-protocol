// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";

/// @title TqFarFutureKeyHarness -- Exposes internal key functions for testing
contract TqFarFutureKeyHarness is DegenerusGameStorage {
    function tqWriteKey(uint24 lvl) external view returns (uint24) {
        return _tqWriteKey(lvl);
    }

    function tqReadKey(uint24 lvl) external view returns (uint24) {
        return _tqReadKey(lvl);
    }

    function tqFarFutureKey(uint24 lvl) external pure returns (uint24) {
        return _tqFarFutureKey(lvl);
    }

    function SLOT_BIT() external pure returns (uint24) {
        return TICKET_SLOT_BIT;
    }

    function FF_BIT() external pure returns (uint24) {
        return TICKET_FAR_FUTURE_BIT;
    }

    function setTicketWriteSlot(bool val) external {
        ticketWriteSlot = val;
    }
}

/// @title TqFarFutureKeyTest -- Proves three key spaces never collide
contract TqFarFutureKeyTest is Test {
    TqFarFutureKeyHarness harness;

    function setUp() public {
        harness = new TqFarFutureKeyHarness();
    }

    function testFarFutureBitConstant() public view {
        assertEq(harness.FF_BIT(), 1 << 22, "FF_BIT must be 1 << 22");
        assertEq(harness.FF_BIT(), 4_194_304, "FF_BIT must be 4194304");
    }

    function testFarFutureKeyPure() public view {
        assertEq(harness.tqFarFutureKey(0), 4_194_304);
        assertEq(harness.tqFarFutureKey(1), 4_194_305);
        assertEq(harness.tqFarFutureKey(100), 4_194_404);
    }

    function testFarFutureKeyBitOrthogonality(uint24 lvl) public view {
        vm.assume(lvl < (1 << 22));
        uint24 ffKey = harness.tqFarFutureKey(lvl);
        // Bit 22 is set
        assertTrue(ffKey & uint24(1 << 22) != 0, "bit 22 must be set");
        // Bit 23 is NOT set
        assertTrue(ffKey & uint24(1 << 23) == 0, "bit 23 must not be set");
        // Lower 22 bits match input
        assertEq(ffKey & uint24((1 << 22) - 1), lvl, "lower bits must match lvl");
    }

    function testFarFutureKeyNoCollision_Slot0(uint24 lvl) public {
        vm.assume(lvl < (1 << 22));
        harness.setTicketWriteSlot(false);
        uint24 writeKey = harness.tqWriteKey(lvl);   // slot 0: raw lvl
        uint24 readKey  = harness.tqReadKey(lvl);     // slot 0: lvl | SLOT_BIT
        uint24 ffKey    = harness.tqFarFutureKey(lvl);
        assertTrue(ffKey != writeKey, "FF must not collide with write (slot 0)");
        assertTrue(ffKey != readKey,  "FF must not collide with read (slot 0)");
        assertTrue(writeKey != readKey, "write must not collide with read (slot 0)");
    }

    function testFarFutureKeyNoCollision_Slot1(uint24 lvl) public {
        vm.assume(lvl < (1 << 22));
        harness.setTicketWriteSlot(true);
        uint24 writeKey = harness.tqWriteKey(lvl);   // slot 1: lvl | SLOT_BIT
        uint24 readKey  = harness.tqReadKey(lvl);     // slot 1: raw lvl
        uint24 ffKey    = harness.tqFarFutureKey(lvl);
        assertTrue(ffKey != writeKey, "FF must not collide with write (slot 1)");
        assertTrue(ffKey != readKey,  "FF must not collide with read (slot 1)");
        assertTrue(writeKey != readKey, "write must not collide with read (slot 1)");
    }
}
