// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";

/// @title TicketRoutingHarness -- Exposes internal queue functions and state for routing/guard tests
contract TicketRoutingHarness is DegenerusGameStorage {
    // error RngLocked() — inherited from DegenerusGameStorage

    function queueTickets(address buyer, uint24 targetLevel, uint32 quantity) external {
        _queueTickets(buyer, targetLevel, quantity, false);
    }

    function queueTicketsWithBypass(address buyer, uint24 targetLevel, uint32 quantity) external {
        _queueTickets(buyer, targetLevel, quantity, true);
    }

    function queueTicketsScaled(address buyer, uint24 targetLevel, uint32 quantityScaled) external {
        _queueTicketsScaled(buyer, targetLevel, quantityScaled, false);
    }

    function queueTicketRange(address buyer, uint24 startLevel, uint24 numLevels, uint32 ticketsPerLevel) external {
        _queueTicketRange(buyer, startLevel, numLevels, ticketsPerLevel, false);
    }

    function setLevel(uint24 lvl) external {
        level = lvl;
    }

    function setRngLockedFlag(bool v) external {
        rngLockedFlag = v;
    }

    function setPhaseTransitionActive(bool v) external {
        phaseTransitionActive = v;
    }

    function getQueueLength(uint24 wk) external view returns (uint256) {
        return ticketQueue[wk].length;
    }

    function getQueueEntry(uint24 wk, uint256 idx) external view returns (address) {
        return ticketQueue[wk][idx];
    }

    function tqWriteKey(uint24 lvl) external view returns (uint24) {
        return _tqWriteKey(lvl);
    }

    function tqFarFutureKey(uint24 lvl) external pure returns (uint24) {
        return _tqFarFutureKey(lvl);
    }
}

/// @title TicketRoutingTest -- Proves far-future routing and RNG guard behaviors
contract TicketRoutingTest is Test {
    TicketRoutingHarness harness;
    address buyer = address(0xBEEF);

    function setUp() public {
        harness = new TicketRoutingHarness();
        harness.setLevel(10);
    }

    // =========================================================================
    // ROUTE-01: Far-future tickets route to FF key
    // =========================================================================

    function testFarFutureRoutesToFFKey() public {
        // level=10, targetLevel=17 (17 > 10+5 = true, far-future)
        harness.queueTickets(buyer, 17, 1);
        uint24 ffKey = harness.tqFarFutureKey(17);
        uint24 writeKey = harness.tqWriteKey(17);
        assertEq(harness.getQueueLength(ffKey), 1, "FF key should have 1 entry");
        assertEq(harness.getQueueEntry(ffKey, 0), buyer, "FF key entry should be buyer");
        assertEq(harness.getQueueLength(writeKey), 0, "write key should be empty");
    }

    // =========================================================================
    // ROUTE-02: Near-future tickets route to write key
    // =========================================================================

    function testNearFutureRoutesToWriteKey() public {
        // level=10, targetLevel=15 (15 <= 10+5 = true, near-future)
        harness.queueTickets(buyer, 15, 1);
        uint24 ffKey = harness.tqFarFutureKey(15);
        uint24 writeKey = harness.tqWriteKey(15);
        assertEq(harness.getQueueLength(writeKey), 1, "write key should have 1 entry");
        assertEq(harness.getQueueEntry(writeKey, 0), buyer, "write key entry should be buyer");
        assertEq(harness.getQueueLength(ffKey), 0, "FF key should be empty");
    }

    // =========================================================================
    // ROUTE-01/02 Boundary: level+5 is near, level+6 is far
    // =========================================================================

    function testBoundaryLevel5RoutesToWriteKey() public {
        // level=10, targetLevel=15 (exactly level+5, near-future)
        harness.queueTickets(buyer, 15, 1);
        uint24 writeKey = harness.tqWriteKey(15);
        assertEq(harness.getQueueLength(writeKey), 1, "boundary level+5 must route to write key");
    }

    function testBoundaryLevel6RoutesToFFKey() public {
        // level=10, targetLevel=16 (exactly level+6, far-future)
        harness.queueTickets(buyer, 16, 1);
        uint24 ffKey = harness.tqFarFutureKey(16);
        assertEq(harness.getQueueLength(ffKey), 1, "boundary level+6 must route to FF key");
    }

    // =========================================================================
    // ROUTE-01 Scaled: _queueTicketsScaled routes far-future to FF key
    // =========================================================================

    function testScaledFarFutureRoutesToFFKey() public {
        // level=10, targetLevel=17 (17 > 10+5 = true, far-future), scaled quantity
        harness.queueTicketsScaled(buyer, 17, 100);
        uint24 ffKey = harness.tqFarFutureKey(17);
        assertEq(harness.getQueueLength(ffKey), 1, "scaled FF key should have 1 entry");
        assertEq(harness.getQueueEntry(ffKey, 0), buyer, "scaled FF key entry should be buyer");
    }

    function testScaledNearFutureRoutesToWriteKey() public {
        // level=10, targetLevel=15 (15 <= 10+5 = true, near-future), scaled quantity
        harness.queueTicketsScaled(buyer, 15, 100);
        uint24 writeKey = harness.tqWriteKey(15);
        assertEq(harness.getQueueLength(writeKey), 1, "scaled write key should have 1 entry");
        assertEq(harness.getQueueEntry(writeKey, 0), buyer, "scaled write key entry should be buyer");
    }

    // =========================================================================
    // ROUTE-01/02 Range: _queueTicketRange splits correctly
    // =========================================================================

    function testRangeRoutingSplitsCorrectly() public {
        // level=10, startLevel=13, numLevels=6 -> covers levels 13,14,15,16,17,18
        // levels 13,14,15 (<=10+5) -> write key
        // levels 16,17,18 (>10+5) -> FF key
        harness.queueTicketRange(buyer, 13, 6, 1);

        // Near-future levels (13, 14, 15) should be in write key
        for (uint24 lvl = 13; lvl <= 15; lvl++) {
            uint24 writeKey = harness.tqWriteKey(lvl);
            assertEq(harness.getQueueLength(writeKey), 1, "near-future level should be in write key");
        }
        // Far-future levels (16, 17, 18) should be in FF key
        for (uint24 lvl = 16; lvl <= 18; lvl++) {
            uint24 ffKey = harness.tqFarFutureKey(lvl);
            assertEq(harness.getQueueLength(ffKey), 1, "far-future level should be in FF key");
        }
    }

    // =========================================================================
    // RNG-02 / ROUTE-03: Guard reverts for FF key writes when rngLocked
    // =========================================================================

    function testRngGuardRevertsOnFFKey() public {
        // rngLocked=true, phaseTransitionActive=false, far-future target
        harness.setRngLockedFlag(true);
        harness.setPhaseTransitionActive(false);
        vm.expectRevert(DegenerusGameStorage.RngLocked.selector);
        harness.queueTickets(buyer, 17, 1);
    }

    function testRngGuardAllowsWithBypass() public {
        // rngLocked=true, rngBypass=true (advanceGame passes true during phase transition)
        harness.setRngLockedFlag(true);
        harness.queueTicketsWithBypass(buyer, 17, 1);
        uint24 ffKey = harness.tqFarFutureKey(17);
        assertEq(harness.getQueueLength(ffKey), 1, "rngBypass should exempt from guard");
    }

    function testRngGuardIgnoresNearFuture() public {
        // rngLocked=true, phaseTransitionActive=false, near-future target -> no revert
        harness.setRngLockedFlag(true);
        harness.setPhaseTransitionActive(false);
        harness.queueTickets(buyer, 15, 1);
        uint24 writeKey = harness.tqWriteKey(15);
        assertEq(harness.getQueueLength(writeKey), 1, "near-future unaffected by rngLocked");
    }

    // =========================================================================
    // RNG-02 Scaled: Guard reverts for scaled FF key writes
    // =========================================================================

    function testRngGuardScaledRevertsOnFFKey() public {
        // rngLocked=true, phaseTransitionActive=false, far-future scaled target
        harness.setRngLockedFlag(true);
        harness.setPhaseTransitionActive(false);
        vm.expectRevert(DegenerusGameStorage.RngLocked.selector);
        harness.queueTicketsScaled(buyer, 17, 100);
    }

    // =========================================================================
    // RNG-02 Range: Guard reverts on first FF level in range
    // =========================================================================

    function testRngGuardRangeRevertsOnFirstFFLevel() public {
        // rngLocked=true, phaseTransitionActive=false
        // range covers levels 14-19, first FF level is 16
        harness.setRngLockedFlag(true);
        harness.setPhaseTransitionActive(false);
        vm.expectRevert(DegenerusGameStorage.RngLocked.selector);
        harness.queueTicketRange(buyer, 14, 6, 1);
    }
}
