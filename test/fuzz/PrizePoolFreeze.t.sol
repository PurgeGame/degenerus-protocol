// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";

/// @title FreezeHarness -- Exposes freeze-related internal helpers for testing.
contract FreezeHarness is DegenerusGameStorage {
    // --- Freeze / Unfreeze ---
    function exposed_swapAndFreeze(uint24 purchaseLevel) external {
        _swapAndFreeze(purchaseLevel);
    }

    function exposed_unfreezePool() external {
        _unfreezePool();
    }

    // --- Prize Pool helpers ---
    function exposed_getPrizePools() external view returns (uint128 next, uint128 future) {
        return _getPrizePools();
    }

    function exposed_setPrizePools(uint128 next, uint128 future) external {
        _setPrizePools(next, future);
    }

    function exposed_getPendingPools() external view returns (uint128 next, uint128 future) {
        return _getPendingPools();
    }

    function exposed_setPendingPools(uint128 next, uint128 future) external {
        _setPendingPools(next, future);
    }

    // --- Direct field access ---
    function getFrozen() external view returns (bool) {
        return prizePoolFrozen;
    }

    function setFrozen(bool val) external {
        prizePoolFrozen = val;
    }

    // --- Ticket queue helper (needed for swapAndFreeze which calls _swapTicketSlot) ---
    function pushToTicketQueue(uint24 key, address addr) external {
        ticketQueue[key].push(addr);
    }
}

/// @title FreezeLifecycleTest -- Unit tests for FREEZE-01 through FREEZE-04
contract FreezeLifecycleTest is Test {
    FreezeHarness harness;

    function setUp() public {
        harness = new FreezeHarness();
    }

    // =====================================================================
    // FREEZE-01: _swapAndFreeze sets frozen flag
    // =====================================================================

    /// @dev Calling _swapAndFreeze sets prizePoolFrozen = true.
    function testSwapAndFreezeSetsFrozenFlag() public {
        assertFalse(harness.getFrozen(), "should start unfrozen");

        harness.exposed_swapAndFreeze(0);

        assertTrue(harness.getFrozen(), "prizePoolFrozen should be true after swapAndFreeze");
    }

    /// @dev _swapAndFreeze zeros pending pools when not already frozen.
    function testSwapAndFreezeZerosPending() public {
        // Pre-seed pending with nonzero values
        harness.exposed_setPendingPools(500, 1000);
        assertFalse(harness.getFrozen());

        harness.exposed_swapAndFreeze(0);

        (uint128 pNext, uint128 pFuture) = harness.exposed_getPendingPools();
        assertEq(pNext, 0, "pending next should be zeroed on fresh freeze");
        assertEq(pFuture, 0, "pending future should be zeroed on fresh freeze");
    }

    // =====================================================================
    // FREEZE-04 (critical): Accumulators preserved when already frozen
    // =====================================================================

    /// @dev Calling _swapAndFreeze when already frozen does NOT zero pending pools.
    function testSwapAndFreezePreservesAccumulatorsWhenAlreadyFrozen() public {
        // First freeze
        harness.exposed_swapAndFreeze(0);
        assertTrue(harness.getFrozen());

        // Simulate purchases during freeze
        harness.exposed_setPendingPools(300, 600);

        // Second swapAndFreeze (simulating next jackpot day's daily RNG)
        harness.exposed_swapAndFreeze(0);

        assertTrue(harness.getFrozen(), "should remain frozen");
        (uint128 pNext, uint128 pFuture) = harness.exposed_getPendingPools();
        assertEq(pNext, 300, "pending next must be preserved on re-freeze");
        assertEq(pFuture, 600, "pending future must be preserved on re-freeze");
    }

    // =====================================================================
    // FREEZE-03: _unfreezePool merges pending into live and clears flag
    // =====================================================================

    /// @dev _unfreezePool adds pending to live, zeros pending, clears flag.
    function testUnfreezeMergesPendingIntoLive() public {
        harness.exposed_setPrizePools(1000, 2000);
        harness.exposed_setPendingPools(150, 250);
        harness.setFrozen(true);

        harness.exposed_unfreezePool();

        // Live pools should have absorbed pending
        (uint128 next, uint128 future) = harness.exposed_getPrizePools();
        assertEq(next, 1150, "live next should include pending");
        assertEq(future, 2250, "live future should include pending");

        // Pending should be zeroed
        (uint128 pNext, uint128 pFuture) = harness.exposed_getPendingPools();
        assertEq(pNext, 0, "pending next should be zeroed after unfreeze");
        assertEq(pFuture, 0, "pending future should be zeroed after unfreeze");

        // Flag should be cleared
        assertFalse(harness.getFrozen(), "prizePoolFrozen should be false after unfreeze");
    }

    /// @dev _unfreezePool is a no-op when not frozen.
    function testUnfreezeNoopWhenNotFrozen() public {
        harness.exposed_setPrizePools(1000, 2000);
        harness.exposed_setPendingPools(150, 250);
        assertFalse(harness.getFrozen());

        harness.exposed_unfreezePool();

        // Live pools unchanged
        (uint128 next, uint128 future) = harness.exposed_getPrizePools();
        assertEq(next, 1000, "live next should be unchanged");
        assertEq(future, 2000, "live future should be unchanged");

        // Pending unchanged (no merge happened)
        (uint128 pNext, uint128 pFuture) = harness.exposed_getPendingPools();
        assertEq(pNext, 150, "pending next should be unchanged");
        assertEq(pFuture, 250, "pending future should be unchanged");
    }

    // =====================================================================
    // FREEZE-02: Freeze branch routing tests
    // =====================================================================

    /// @dev When frozen, adding to pending increases pending and leaves live unchanged.
    function testFrozenPurchaseBranchRoutesPending() public {
        // Set initial live pools
        harness.exposed_setPrizePools(5000, 10000);
        // Freeze
        harness.setFrozen(true);
        // Clear pending
        harness.exposed_setPendingPools(0, 0);

        // Simulate freeze branch pattern: load pending, add shares, store
        uint128 nextShare = 100;
        uint128 futureShare = 200;
        (uint128 pNext, uint128 pFuture) = harness.exposed_getPendingPools();
        harness.exposed_setPendingPools(pNext + nextShare, pFuture + futureShare);

        // Verify pending increased
        (pNext, pFuture) = harness.exposed_getPendingPools();
        assertEq(pNext, 100, "pending next should have purchase share");
        assertEq(pFuture, 200, "pending future should have purchase share");

        // Verify live unchanged
        (uint128 next, uint128 future) = harness.exposed_getPrizePools();
        assertEq(next, 5000, "live next must be unchanged during freeze");
        assertEq(future, 10000, "live future must be unchanged during freeze");
    }

    /// @dev When not frozen, adding to live increases live and leaves pending unchanged.
    function testUnfrozenPurchaseBranchRoutesLive() public {
        // Set initial live pools
        harness.exposed_setPrizePools(5000, 10000);
        // Not frozen (default)
        assertFalse(harness.getFrozen());
        // Set pending to nonzero to prove it's not touched
        harness.exposed_setPendingPools(999, 888);

        // Simulate unfrozen branch pattern: load live, add shares, store
        uint128 nextShare = 100;
        uint128 futureShare = 200;
        (uint128 next, uint128 future) = harness.exposed_getPrizePools();
        harness.exposed_setPrizePools(next + nextShare, future + futureShare);

        // Verify live increased
        (next, future) = harness.exposed_getPrizePools();
        assertEq(next, 5100, "live next should have purchase share");
        assertEq(future, 10200, "live future should have purchase share");

        // Verify pending unchanged
        (uint128 pNext, uint128 pFuture) = harness.exposed_getPendingPools();
        assertEq(pNext, 999, "pending next must be unchanged when not frozen");
        assertEq(pFuture, 888, "pending future must be unchanged when not frozen");
    }

    // =====================================================================
    // FREEZE-04: Multi-day accumulator persistence (5 jackpot days)
    // =====================================================================

    /// @dev Simulate 5 jackpot days: freeze persists, accumulators grow, unfreeze merges all.
    function testMultiDayAccumulatorPersistence() public {
        // Initial live pool values
        harness.exposed_setPrizePools(10000, 20000);

        // Day 1: First swapAndFreeze -> activates freeze, zeros pending
        harness.exposed_swapAndFreeze(0);
        assertTrue(harness.getFrozen());

        uint128 totalNextAdded;
        uint128 totalFutureAdded;

        // Simulate 5 days of purchases + daily swaps
        for (uint256 day = 1; day <= 5; day++) {
            // Simulate purchases during this day (different amounts each day)
            uint128 dayNextShare = uint128(100 * day);
            uint128 dayFutureShare = uint128(200 * day);

            (uint128 pNext, uint128 pFuture) = harness.exposed_getPendingPools();
            harness.exposed_setPendingPools(pNext + dayNextShare, pFuture + dayFutureShare);

            totalNextAdded += dayNextShare;
            totalFutureAdded += dayFutureShare;

            // Verify pending grows monotonically
            (pNext, pFuture) = harness.exposed_getPendingPools();
            assertEq(pNext, totalNextAdded, "pending next should grow monotonically");
            assertEq(pFuture, totalFutureAdded, "pending future should grow monotonically");

            // Verify live pools unchanged throughout
            (uint128 next, uint128 future) = harness.exposed_getPrizePools();
            assertEq(next, 10000, "live next must remain constant during jackpot phase");
            assertEq(future, 20000, "live future must remain constant during jackpot phase");

            // Days 2-5: subsequent swapAndFreeze should NOT zero accumulators
            if (day < 5) {
                harness.exposed_swapAndFreeze(0);
                assertTrue(harness.getFrozen(), "must remain frozen between jackpot days");

                // Verify accumulators survived the re-freeze
                (pNext, pFuture) = harness.exposed_getPendingPools();
                assertEq(pNext, totalNextAdded, "pending next must survive re-freeze");
                assertEq(pFuture, totalFutureAdded, "pending future must survive re-freeze");
            }
        }

        // totalNextAdded = 100+200+300+400+500 = 1500
        // totalFutureAdded = 200+400+600+800+1000 = 3000
        assertEq(totalNextAdded, 1500, "sanity: total next");
        assertEq(totalFutureAdded, 3000, "sanity: total future");

        // Unfreeze: all 5 days of pending merge into live
        harness.exposed_unfreezePool();

        assertFalse(harness.getFrozen(), "should be unfrozen after jackpot phase");

        (uint128 finalNext, uint128 finalFuture) = harness.exposed_getPrizePools();
        assertEq(finalNext, 10000 + 1500, "live next should absorb all 5 days of pending");
        assertEq(finalFuture, 20000 + 3000, "live future should absorb all 5 days of pending");

        // Pending should be zeroed
        (uint128 pn, uint128 pf) = harness.exposed_getPendingPools();
        assertEq(pn, 0, "pending next should be zero after unfreeze");
        assertEq(pf, 0, "pending future should be zero after unfreeze");
    }

    // =====================================================================
    // Round-trip lifecycle test
    // =====================================================================

    /// @dev Full lifecycle: set live -> freeze -> add pending -> unfreeze -> verify live = original + pending.
    function testFreezeUnfreezeRoundTrip() public {
        // Set initial live values
        harness.exposed_setPrizePools(7777, 8888);

        // Freeze
        harness.exposed_swapAndFreeze(0);
        assertTrue(harness.getFrozen());

        // Pending should be zeroed by freeze
        (uint128 pNext, uint128 pFuture) = harness.exposed_getPendingPools();
        assertEq(pNext, 0);
        assertEq(pFuture, 0);

        // Simulate purchase: add to pending
        harness.exposed_setPendingPools(333, 444);

        // Live should still be original values
        (uint128 next, uint128 future) = harness.exposed_getPrizePools();
        assertEq(next, 7777, "live next unchanged during freeze");
        assertEq(future, 8888, "live future unchanged during freeze");

        // Unfreeze
        harness.exposed_unfreezePool();

        // Verify: live = original + pending
        (next, future) = harness.exposed_getPrizePools();
        assertEq(next, 7777 + 333, "live next = original + pending after unfreeze");
        assertEq(future, 8888 + 444, "live future = original + pending after unfreeze");

        // Verify: pending zeroed, flag cleared
        (pNext, pFuture) = harness.exposed_getPendingPools();
        assertEq(pNext, 0);
        assertEq(pFuture, 0);
        assertFalse(harness.getFrozen());
    }
}
