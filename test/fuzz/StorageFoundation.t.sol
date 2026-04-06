// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";

/// @title StorageHarness -- Exposes internal DegenerusGameStorage helpers for testing.
contract StorageHarness is DegenerusGameStorage {
    // --- Prize Pool helpers ---
    function exposed_setPrizePools(uint128 next, uint128 future) external {
        _setPrizePools(next, future);
    }

    function exposed_getPrizePools() external view returns (uint128 next, uint128 future) {
        return _getPrizePools();
    }

    function exposed_setPendingPools(uint128 next, uint128 future) external {
        _setPendingPools(next, future);
    }

    function exposed_getPendingPools() external view returns (uint128 next, uint128 future) {
        return _getPendingPools();
    }

    // --- Key Encoding helpers ---
    function exposed_tqWriteKey(uint24 lvl) external view returns (uint24) {
        return _tqWriteKey(lvl);
    }

    function exposed_tqReadKey(uint24 lvl) external view returns (uint24) {
        return _tqReadKey(lvl);
    }

    // --- Swap / Freeze / Unfreeze ---
    function exposed_swapTicketSlot(uint24 purchaseLevel) external {
        _swapTicketSlot(purchaseLevel);
    }

    function exposed_swapAndFreeze(uint24 purchaseLevel) external {
        _swapAndFreeze(purchaseLevel);
    }

    function exposed_unfreezePool() external {
        _unfreezePool();
    }

    // --- Direct field access ---
    function getTicketWriteSlot() external view returns (uint8) {
        return ticketWriteSlot;
    }

    function setTicketWriteSlot(uint8 val) external {
        ticketWriteSlot = val;
    }

    function getTicketsFullyProcessed() external view returns (bool) {
        return ticketsFullyProcessed;
    }

    function setTicketsFullyProcessed(bool val) external {
        ticketsFullyProcessed = val;
    }

    function getPrizePoolFrozen() external view returns (bool) {
        return prizePoolFrozen;
    }

    function setPrizePoolFrozen(bool val) external {
        prizePoolFrozen = val;
    }

    // --- Ticket queue helper for revert tests ---
    function pushToTicketQueue(uint24 key, address addr) external {
        ticketQueue[key].push(addr);
    }
}

/// @title StorageFoundationTest -- Unit tests for STOR-01 through STOR-04
contract StorageFoundationTest is Test {
    StorageHarness harness;

    uint24 constant TICKET_SLOT_BIT = 1 << 23;

    function setUp() public {
        harness = new StorageHarness();
    }

    // =====================================================================
    // STOR-01: Field Placement Tests
    // =====================================================================

    /// @dev Verify ticketWriteSlot at Slot 1, offset 6; prizePoolFrozen at offset 7.
    ///      ticketsFullyProcessed moved to Slot 0 offset 30; gameOverPossible to Slot 0 offset 31.
    function testSlot1FieldOffsets() public {
        // Set ticketWriteSlot = 1
        harness.setTicketWriteSlot(1);
        bytes32 slot1 = vm.load(address(harness), bytes32(uint256(1)));
        // offset 6 means byte 6 from the RIGHT in the 32-byte word (little-endian packing)
        // In EVM storage packing, offset N means bits [N*8, (N+1)*8)
        // So ticketWriteSlot at offset 6 = bits [48, 56)
        assertEq(uint8(uint256(slot1) >> 48), 1, "ticketWriteSlot not at offset 6");

        // Reset and set prizePoolFrozen = true (offset 7 = bits [56, 64))
        harness.setTicketWriteSlot(0);
        harness.setPrizePoolFrozen(true);
        slot1 = vm.load(address(harness), bytes32(uint256(1)));
        assertEq(uint8(uint256(slot1) >> 56), 1, "prizePoolFrozen not at offset 7");

        // Verify ticketsFullyProcessed is in slot 0 at offset 30 = bits [240, 248)
        harness.setPrizePoolFrozen(false);
        harness.setTicketsFullyProcessed(true);
        bytes32 slot0 = vm.load(address(harness), bytes32(uint256(0)));
        assertEq(uint8(uint256(slot0) >> 240), 1, "ticketsFullyProcessed not at slot 0 offset 30");
    }

    /// @dev Verify prizePoolsPacked at Slot 2 and prizePoolPendingPacked at Slot 12.
    function testPackedPoolSlotsUnshifted() public {
        // Write a known value to Slot 2 via vm.store, then read back via harness getter
        uint256 sentinel2 = 0xDEADBEEF00000000000000000000000100000000000000000000000000000002;
        vm.store(address(harness), bytes32(uint256(2)), bytes32(sentinel2));
        (uint128 next2, uint128 future2) = harness.exposed_getPrizePools();
        assertEq(uint256(next2), sentinel2 & type(uint128).max, "prizePoolsPacked not at slot 2 (next)");
        assertEq(uint256(future2), sentinel2 >> 128, "prizePoolsPacked not at slot 2 (future)");

        // Write a known value to Slot 12 via vm.store, then read back via harness getter
        uint256 sentinel12 = 0x0000000000000000000000000000000300000000000000000000000000000004;
        vm.store(address(harness), bytes32(uint256(12)), bytes32(sentinel12));
        (uint128 next12, uint128 future12) = harness.exposed_getPendingPools();
        assertEq(uint256(next12), sentinel12 & type(uint128).max, "prizePoolPendingPacked not at slot 12 (next)");
        assertEq(uint256(future12), sentinel12 >> 128, "prizePoolPendingPacked not at slot 12 (future)");
    }

    // =====================================================================
    // STOR-02: Prize Pool Packing Round-Trip Tests
    // =====================================================================

    function testPrizePoolPackingZero() public {
        harness.exposed_setPrizePools(0, 0);
        (uint128 n, uint128 f) = harness.exposed_getPrizePools();
        assertEq(n, 0);
        assertEq(f, 0);
    }

    function testPrizePoolPackingMaxNext() public {
        harness.exposed_setPrizePools(type(uint128).max, 0);
        (uint128 n, uint128 f) = harness.exposed_getPrizePools();
        assertEq(n, type(uint128).max);
        assertEq(f, 0);
    }

    function testPrizePoolPackingMaxFuture() public {
        harness.exposed_setPrizePools(0, type(uint128).max);
        (uint128 n, uint128 f) = harness.exposed_getPrizePools();
        assertEq(n, 0);
        assertEq(f, type(uint128).max);
    }

    function testPrizePoolPackingMaxBoth() public {
        harness.exposed_setPrizePools(type(uint128).max, type(uint128).max);
        (uint128 n, uint128 f) = harness.exposed_getPrizePools();
        assertEq(n, type(uint128).max);
        assertEq(f, type(uint128).max);
    }

    function testPrizePoolPackingArbitrary() public {
        harness.exposed_setPrizePools(12345, 67890);
        (uint128 n, uint128 f) = harness.exposed_getPrizePools();
        assertEq(n, 12345);
        assertEq(f, 67890);
    }

    // =====================================================================
    // STOR-03: Pending Pool Packing Round-Trip Tests
    // =====================================================================

    function testPendingPoolPackingZero() public {
        harness.exposed_setPendingPools(0, 0);
        (uint128 n, uint128 f) = harness.exposed_getPendingPools();
        assertEq(n, 0);
        assertEq(f, 0);
    }

    function testPendingPoolPackingMaxNext() public {
        harness.exposed_setPendingPools(type(uint128).max, 0);
        (uint128 n, uint128 f) = harness.exposed_getPendingPools();
        assertEq(n, type(uint128).max);
        assertEq(f, 0);
    }

    function testPendingPoolPackingMaxFuture() public {
        harness.exposed_setPendingPools(0, type(uint128).max);
        (uint128 n, uint128 f) = harness.exposed_getPendingPools();
        assertEq(n, 0);
        assertEq(f, type(uint128).max);
    }

    function testPendingPoolPackingMaxBoth() public {
        harness.exposed_setPendingPools(type(uint128).max, type(uint128).max);
        (uint128 n, uint128 f) = harness.exposed_getPendingPools();
        assertEq(n, type(uint128).max);
        assertEq(f, type(uint128).max);
    }

    function testPendingPoolPackingArbitrary() public {
        harness.exposed_setPendingPools(12345, 67890);
        (uint128 n, uint128 f) = harness.exposed_getPendingPools();
        assertEq(n, 12345);
        assertEq(f, 67890);
    }

    // =====================================================================
    // STOR-04: Key Encoding Tests
    // =====================================================================

    function testTicketSlotKeysDifferSlot0() public {
        // Default ticketWriteSlot is 0
        assertEq(harness.getTicketWriteSlot(), 0);
        uint24 wk = harness.exposed_tqWriteKey(5);
        uint24 rk = harness.exposed_tqReadKey(5);
        assertTrue(wk != rk, "write key must differ from read key (slot 0)");
    }

    function testTicketSlotKeysDifferSlot1() public {
        harness.setTicketWriteSlot(1);
        uint24 wk = harness.exposed_tqWriteKey(5);
        uint24 rk = harness.exposed_tqReadKey(5);
        assertTrue(wk != rk, "write key must differ from read key (slot 1)");
    }

    function testTicketSlotKeyBit23Slot0() public {
        // ticketWriteSlot=0: write key = level, read key = level | BIT
        assertEq(harness.getTicketWriteSlot(), 0);
        assertEq(harness.exposed_tqWriteKey(5), 5, "slot0 writeKey should be raw level");
        assertEq(harness.exposed_tqReadKey(5), 5 | TICKET_SLOT_BIT, "slot0 readKey should have bit23 set");
    }

    function testTicketSlotKeyBit23Slot1() public {
        harness.setTicketWriteSlot(1);
        assertEq(harness.exposed_tqWriteKey(5), 5 | TICKET_SLOT_BIT, "slot1 writeKey should have bit23 set");
        assertEq(harness.exposed_tqReadKey(5), 5, "slot1 readKey should be raw level");
    }

    function testTicketSlotKeyMultipleLevels() public {
        uint24[4] memory levels = [uint24(0), uint24(1), uint24(100), uint24(8388607)];

        // Test with ticketWriteSlot = 0
        for (uint256 i = 0; i < levels.length; i++) {
            assertEq(harness.exposed_tqWriteKey(levels[i]), levels[i], "slot0 writeKey mismatch");
            assertEq(harness.exposed_tqReadKey(levels[i]), levels[i] | TICKET_SLOT_BIT, "slot0 readKey mismatch");
        }

        // Test with ticketWriteSlot = 1
        harness.setTicketWriteSlot(1);
        for (uint256 i = 0; i < levels.length; i++) {
            assertEq(harness.exposed_tqWriteKey(levels[i]), levels[i] | TICKET_SLOT_BIT, "slot1 writeKey mismatch");
            assertEq(harness.exposed_tqReadKey(levels[i]), levels[i], "slot1 readKey mismatch");
        }
    }

    // =====================================================================
    // Swap Tests
    // =====================================================================

    /// @dev Empty read queue -> swap succeeds, ticketWriteSlot toggles, ticketsFullyProcessed resets.
    function testSwapTicketSlotSuccess() public {
        assertEq(harness.getTicketWriteSlot(), 0);
        harness.setTicketsFullyProcessed(true);

        // Read slot for level 0, ticketWriteSlot=0 is 0|TICKET_SLOT_BIT -- empty by default
        harness.exposed_swapTicketSlot(0);

        assertEq(harness.getTicketWriteSlot(), 1, "ticketWriteSlot should toggle to 1");
        assertFalse(harness.getTicketsFullyProcessed(), "ticketsFullyProcessed should reset");
    }

    /// @dev Read queue has entries -> revert E().
    function testSwapTicketSlotRevertsNonEmpty() public {
        // ticketWriteSlot=0, readKey(0) = 0|TICKET_SLOT_BIT
        uint24 rk = 0 | TICKET_SLOT_BIT;
        harness.pushToTicketQueue(rk, address(0xBEEF));

        vm.expectRevert(DegenerusGameStorage.E.selector);
        harness.exposed_swapTicketSlot(0);
    }

    /// @dev Two swaps return ticketWriteSlot to 0.
    function testSwapTicketSlotDoubleToggle() public {
        assertEq(harness.getTicketWriteSlot(), 0);

        // First swap: 0 -> 1 (read slot = TICKET_SLOT_BIT|0, empty)
        harness.exposed_swapTicketSlot(0);
        assertEq(harness.getTicketWriteSlot(), 1);

        // Second swap: 1 -> 0 (read slot = 0 (raw level), empty)
        harness.exposed_swapTicketSlot(0);
        assertEq(harness.getTicketWriteSlot(), 0);
    }

    // =====================================================================
    // Freeze Tests
    // =====================================================================

    /// @dev First freeze: sets prizePoolFrozen=true, zeros pending accumulators.
    function testSwapAndFreezeActivates() public {
        harness.exposed_setPendingPools(100, 200);
        assertFalse(harness.getPrizePoolFrozen());

        harness.exposed_swapAndFreeze(0);

        assertTrue(harness.getPrizePoolFrozen(), "prizePoolFrozen should be true");
        (uint128 pn, uint128 pf) = harness.exposed_getPendingPools();
        assertEq(pn, 0, "pending next should be zeroed on first freeze");
        assertEq(pf, 0, "pending future should be zeroed on first freeze");
    }

    /// @dev Already frozen: swap succeeds, pending accumulators preserved.
    function testSwapAndFreezeAlreadyFrozen() public {
        harness.setPrizePoolFrozen(true);
        harness.exposed_setPendingPools(100, 200);

        harness.exposed_swapAndFreeze(0);

        assertTrue(harness.getPrizePoolFrozen(), "prizePoolFrozen should remain true");
        (uint128 pn, uint128 pf) = harness.exposed_getPendingPools();
        assertEq(pn, 100, "pending next should be preserved on re-freeze");
        assertEq(pf, 200, "pending future should be preserved on re-freeze");
    }

    // =====================================================================
    // Unfreeze Tests
    // =====================================================================

    /// @dev Pending applied to live, pending zeroed, freeze cleared.
    function testUnfreezePoolMerges() public {
        harness.exposed_setPrizePools(1000, 2000);
        harness.exposed_setPendingPools(100, 200);
        harness.setPrizePoolFrozen(true);

        harness.exposed_unfreezePool();

        (uint128 n, uint128 f) = harness.exposed_getPrizePools();
        assertEq(n, 1100, "live next should include pending");
        assertEq(f, 2200, "live future should include pending");

        (uint128 pn, uint128 pf) = harness.exposed_getPendingPools();
        assertEq(pn, 0, "pending next should be zeroed after unfreeze");
        assertEq(pf, 0, "pending future should be zeroed after unfreeze");

        assertFalse(harness.getPrizePoolFrozen(), "prizePoolFrozen should be cleared");
    }

    /// @dev No-op when not frozen.
    function testUnfreezePoolNoop() public {
        harness.exposed_setPrizePools(1000, 2000);
        assertFalse(harness.getPrizePoolFrozen());

        harness.exposed_unfreezePool();

        (uint128 n, uint128 f) = harness.exposed_getPrizePools();
        assertEq(n, 1000, "live next should be unchanged");
        assertEq(f, 2000, "live future should be unchanged");
    }
}
