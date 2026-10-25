// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {DegenerusGameAdvanceModule} from "../../contracts/modules/DegenerusGameAdvanceModule.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {WalletSeed} from "../helpers/WalletSeed.sol";
import {GameSlots} from "../helpers/GameSlots.sol";

/// @title FreezeHarness -- Exposes freeze-related internal helpers for testing.
contract FreezeHarness is DegenerusGameAdvanceModule, WalletSeed {
    // --- Freeze / Unfreeze ---
    function exposed_swapAndFreeze(uint24 /* purchaseLevel */) external {
        _swapTicketSlot();
        _freezePool();
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

    function rawPendingPools() external view returns (uint256) {
        return prizePoolPendingPacked;
    }

    function setRawPendingPools(uint256 raw) external {
        prizePoolPendingPacked = raw;
    }

    function addPrizeContribution(uint128 next, uint128 future) external {
        _addPrizeContribution(next, future);
    }

    function sentinel() external pure returns (uint256) {
        return POOL_PENDING_SENTINEL;
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
        _tqAppend(key, _seedWallet(addr));
    }
}

/// @title FreezeLifecycleTest -- Unit tests for FREEZE-01 through FREEZE-04
contract FreezeLifecycleTest is Test {
    FreezeHarness harness;
    uint256 internal constant SENTINEL = uint256(1) << 255;
    uint256 internal constant FUTURE_MAX = type(uint128).max >> 1;
    bytes32 internal constant PENDING_SLOT = bytes32(GameSlots.PRIZE_POOL_PENDING_PACKED);

    function setUp() public {
        // The freeze push calls the parimutuel at its fixed address; this harness deploys
        // no protocol, so give that address one STOP byte — the typed void call needs code
        // to pass the extcodesize check and returns success without any market logic.
        vm.etch(ContractAddresses.PARIMUTUEL, hex"00");
        harness = new FreezeHarness();
    }

    /// @dev The steady state every unfreeze leaves: the buffer holds only the sentinel.
    function _settle() internal {
        harness.setFrozen(true);
        harness.exposed_unfreezePool();
        assertEq(harness.rawPendingPools(), SENTINEL, "unfreeze leaves only the sentinel");
    }

    function testSentinelConstantIsTopBit() public view {
        assertEq(harness.sentinel(), SENTINEL);
    }

    function testPendingSlotPin() public {
        harness.setRawPendingPools(0xabc);
        assertEq(uint256(vm.load(address(harness), PENDING_SLOT)), 0xabc, "prizePoolPendingPacked is slot 8");
    }

    // =====================================================================
    // FREEZE-01: _freezePool sets the flag and touches nothing else
    // =====================================================================

    function testSwapAndFreezeSetsFrozenFlag() public {
        assertFalse(harness.getFrozen(), "should start unfrozen");

        harness.exposed_swapAndFreeze(0);

        assertTrue(harness.getFrozen(), "prizePoolFrozen should be true after swapAndFreeze");
    }

    /// @dev No seed: the freeze leaves the live pools and the (empty) buffer exactly as they were.
    function testFreezeLeavesPoolsAndBufferUntouched() public {
        harness.exposed_setPrizePools(10_000, 20_000);
        _settle();

        harness.exposed_swapAndFreeze(0);

        (uint128 next, uint128 future) = harness.exposed_getPrizePools();
        assertEq(next, 10_000, "live next untouched by the freeze");
        assertEq(future, 20_000, "live future untouched by the freeze: no seed");
        assertEq(harness.rawPendingPools(), SENTINEL, "freeze writes nothing to pending");
        (uint128 pNext, uint128 pFuture) = harness.exposed_getPendingPools();
        assertEq(pNext, 0);
        assertEq(pFuture, 0);
    }

    // =====================================================================
    // FREEZE-04 (critical): Accumulators preserved when already frozen
    // =====================================================================

    function testSwapAndFreezePreservesAccumulatorsWhenAlreadyFrozen() public {
        harness.exposed_swapAndFreeze(0);
        assertTrue(harness.getFrozen());

        harness.exposed_setPendingPools(300, 600);

        harness.exposed_swapAndFreeze(0);

        assertTrue(harness.getFrozen(), "should remain frozen");
        (uint128 pNext, uint128 pFuture) = harness.exposed_getPendingPools();
        assertEq(pNext, 300, "pending next must be preserved on re-freeze");
        assertEq(pFuture, 600, "pending future must be preserved on re-freeze");
    }

    // =====================================================================
    // FREEZE-03: _unfreezePool folds pending into live, leaves the sentinel, clears the flag
    // =====================================================================

    function testUnfreezeMergesPendingIntoLive() public {
        harness.exposed_setPrizePools(1000, 2000);
        harness.exposed_setPendingPools(150, 250);
        harness.setFrozen(true);

        harness.exposed_unfreezePool();

        (uint128 next, uint128 future) = harness.exposed_getPrizePools();
        assertEq(next, 1150, "live next should include pending");
        assertEq(future, 2250, "live future should include pending, sentinel excluded");

        (uint128 pNext, uint128 pFuture) = harness.exposed_getPendingPools();
        assertEq(pNext, 0, "pending next empty after unfreeze");
        assertEq(pFuture, 0, "pending future empty after unfreeze");
        assertEq(harness.rawPendingPools(), SENTINEL, "only the sentinel remains");

        assertFalse(harness.getFrozen(), "prizePoolFrozen should be false after unfreeze");
    }

    /// @dev A freeze that took no credit folds nothing and leaves both slots as they were.
    function testUnfreezeQuietFreezeLeavesSlots() public {
        harness.exposed_setPrizePools(1000, 2000);
        _settle();
        harness.exposed_swapAndFreeze(0);

        harness.exposed_unfreezePool();

        (uint128 next, uint128 future) = harness.exposed_getPrizePools();
        assertEq(next, 1000);
        assertEq(future, 2000);
        assertEq(harness.rawPendingPools(), SENTINEL);
        assertFalse(harness.getFrozen());
    }

    /// @dev A never-written slot (zero) still folds cleanly and comes out holding the sentinel.
    function testUnfreezeFromZeroWritesSentinel() public {
        harness.exposed_setPrizePools(1000, 2000);
        assertEq(harness.rawPendingPools(), 0);
        harness.setFrozen(true);

        harness.exposed_unfreezePool();

        (uint128 next, uint128 future) = harness.exposed_getPrizePools();
        assertEq(next, 1000);
        assertEq(future, 2000);
        assertEq(harness.rawPendingPools(), SENTINEL);
    }

    function testUnfreezeNoopWhenNotFrozen() public {
        harness.exposed_setPrizePools(1000, 2000);
        _settle();

        harness.exposed_unfreezePool();

        (uint128 next, uint128 future) = harness.exposed_getPrizePools();
        assertEq(next, 1000, "live next should be unchanged");
        assertEq(future, 2000, "live future should be unchanged");
        assertEq(harness.rawPendingPools(), SENTINEL);
    }

    // =====================================================================
    // Sentinel: set on every write, masked on every read
    // =====================================================================

    function testSetterOrsSentinelAndGetterMasksIt(uint128 next, uint128 future) public {
        future = uint128(bound(future, 0, FUTURE_MAX));
        harness.exposed_setPendingPools(next, future);

        uint256 raw = harness.rawPendingPools();
        assertEq(raw & SENTINEL, SENTINEL, "setter ORs the sentinel in");
        assertEq(raw, SENTINEL | (uint256(future) << 128) | next);
        (uint128 pNext, uint128 pFuture) = harness.exposed_getPendingPools();
        assertEq(pNext, next, "next half read exactly");
        assertEq(pFuture, future, "future half read without the sentinel");
    }

    function testContributionKeepsSentinel(uint128 a, uint128 b, uint128 c, uint128 d) public {
        a = uint128(bound(a, 0, 1e30));
        b = uint128(bound(b, 0, 1e30));
        c = uint128(bound(c, 0, 1e30));
        d = uint128(bound(d, 0, 1e30));
        _settle();
        harness.setFrozen(true);

        harness.addPrizeContribution(a, b);
        harness.addPrizeContribution(c, d);

        uint256 raw = harness.rawPendingPools();
        assertEq(raw & SENTINEL, SENTINEL, "read-add-write keeps the sentinel");
        (uint128 pNext, uint128 pFuture) = harness.exposed_getPendingPools();
        assertEq(pNext, uint256(a) + c);
        assertEq(pFuture, uint256(b) + d);
    }

    /// @dev The future half saturates below the sentinel and never carries into it.
    function testContributionFutureSaturatesBelowSentinel() public {
        harness.exposed_setPendingPools(7, uint128(FUTURE_MAX - 5));
        harness.setFrozen(true);

        harness.addPrizeContribution(1, 100);

        uint256 raw = harness.rawPendingPools();
        assertEq(raw & SENTINEL, SENTINEL, "sentinel intact at the ceiling");
        (uint128 pNext, uint128 pFuture) = harness.exposed_getPendingPools();
        assertEq(pNext, 8, "next half unaffected by the future clamp");
        assertEq(pFuture, FUTURE_MAX, "future clamps at 2^127 - 1");
    }

    /// @dev The fold adds the masked future half: the sentinel never reaches the live pools.
    function testFoldExcludesSentinel(uint128 liveNext, uint128 liveFuture, uint128 pNext, uint128 pFuture) public {
        liveNext = uint128(bound(liveNext, 0, 1e30));
        liveFuture = uint128(bound(liveFuture, 0, 1e30));
        pNext = uint128(bound(pNext, 0, 1e30));
        pFuture = uint128(bound(pFuture, 0, 1e30));
        harness.exposed_setPrizePools(liveNext, liveFuture);
        _settle();
        harness.exposed_swapAndFreeze(0);
        harness.addPrizeContribution(pNext, pFuture);

        harness.exposed_unfreezePool();

        (uint128 next, uint128 future) = harness.exposed_getPrizePools();
        assertEq(next, uint256(liveNext) + pNext);
        assertEq(future, uint256(liveFuture) + pFuture);
        assertEq(harness.rawPendingPools(), SENTINEL);
    }

    /// @dev After an unfreeze, the next freeze's first credit rewrites a nonzero slot: the
    ///      SSTORE is nonzero-to-nonzero, never a fresh zero-to-nonzero write.
    function testFirstFreezeCreditWritesNonzeroSlot() public {
        _settle();
        harness.exposed_swapAndFreeze(0);

        vm.startStateDiffRecording();
        harness.addPrizeContribution(100, 200);
        Vm.AccountAccess[] memory accesses = vm.stopAndReturnStateDiff();
        uint256 writes;
        for (uint256 i; i < accesses.length; ++i) {
            Vm.StorageAccess[] memory s = accesses[i].storageAccesses;
            for (uint256 j; j < s.length; ++j) {
                if (s[j].account != address(harness) || s[j].slot != PENDING_SLOT || !s[j].isWrite) continue;
                ++writes;
                assertEq(uint256(s[j].previousValue), SENTINEL, "the write lands on the sentinel-only slot");
                assertEq(uint256(s[j].newValue), SENTINEL | (uint256(200) << 128) | 100);
            }
        }
        assertEq(writes, 1, "one pending write");
    }

    // =====================================================================
    // FREEZE-02: Freeze branch routing tests
    // =====================================================================

    function testFrozenPurchaseBranchRoutesPending() public {
        harness.exposed_setPrizePools(5000, 10000);
        _settle();
        harness.setFrozen(true);

        harness.addPrizeContribution(100, 200);

        (uint128 pNext, uint128 pFuture) = harness.exposed_getPendingPools();
        assertEq(pNext, 100, "pending next should have purchase share");
        assertEq(pFuture, 200, "pending future should have purchase share");

        (uint128 next, uint128 future) = harness.exposed_getPrizePools();
        assertEq(next, 5000, "live next must be unchanged during freeze");
        assertEq(future, 10000, "live future must be unchanged during freeze");
    }

    function testUnfrozenPurchaseBranchRoutesLive() public {
        harness.exposed_setPrizePools(5000, 10000);
        _settle();

        harness.addPrizeContribution(100, 200);

        (uint128 next, uint128 future) = harness.exposed_getPrizePools();
        assertEq(next, 5100, "live next should have purchase share");
        assertEq(future, 10200, "live future should have purchase share");
        assertEq(harness.rawPendingPools(), SENTINEL, "unfrozen credit leaves the buffer empty");
    }

    function testPendingNeverCountedTwiceAcrossFreezeCycles() public {
        harness.exposed_setPrizePools(10000, 20000);
        for (uint128 cycle = 1; cycle <= 5; ++cycle) {
            (uint128 beforeNext, uint128 beforeFuture) = harness.exposed_getPrizePools();
            harness.exposed_swapAndFreeze(0);
            (uint128 pendingNext, uint128 pendingFuture) = harness.exposed_getPendingPools();
            assertEq(pendingNext, 0, "each freeze opens on an empty buffer");
            assertEq(pendingFuture, 0, "each freeze opens on an empty buffer");
            harness.addPrizeContribution(cycle * 100, cycle * 200);
            harness.exposed_unfreezePool();
            assertEq(harness.rawPendingPools(), SENTINEL, "unfreeze empties the buffer");
            harness.exposed_unfreezePool();
            harness.addPrizeContribution(10, 20);
            assertEq(harness.rawPendingPools(), SENTINEL, "unfrozen contributions leave it alone");
            (uint128 next, uint128 future) = harness.exposed_getPrizePools();
            assertEq(next, beforeNext + cycle * 100 + 10);
            assertEq(future, beforeFuture + cycle * 200 + 20);
        }
    }

    // =====================================================================
    // FREEZE-04: Multi-day accumulator persistence (5 jackpot days)
    // =====================================================================

    /// @dev Simulate 5 jackpot days: freeze persists, accumulators grow, unfreeze merges all.
    function testMultiDayAccumulatorPersistence() public {
        harness.exposed_setPrizePools(10000, 20000);

        harness.exposed_swapAndFreeze(0);
        assertTrue(harness.getFrozen());

        uint128 totalNextAdded;
        uint128 totalFutureAdded;

        for (uint256 day = 1; day <= 5; day++) {
            uint128 dayNextShare = uint128(100 * day);
            uint128 dayFutureShare = uint128(200 * day);

            (uint128 pNext, uint128 pFuture) = harness.exposed_getPendingPools();
            harness.exposed_setPendingPools(pNext + dayNextShare, pFuture + dayFutureShare);

            totalNextAdded += dayNextShare;
            totalFutureAdded += dayFutureShare;

            (pNext, pFuture) = harness.exposed_getPendingPools();
            assertEq(pNext, totalNextAdded, "pending next should grow monotonically");
            assertEq(pFuture, totalFutureAdded, "pending future should grow monotonically");

            (uint128 next, uint128 future) = harness.exposed_getPrizePools();
            assertEq(next, 10000, "live next must remain constant during jackpot phase");
            assertEq(future, 20000, "live future must remain constant during jackpot phase");

            if (day < 5) {
                harness.exposed_swapAndFreeze(0);
                assertTrue(harness.getFrozen(), "must remain frozen between jackpot days");

                (pNext, pFuture) = harness.exposed_getPendingPools();
                assertEq(pNext, totalNextAdded, "pending next must survive re-freeze");
                assertEq(pFuture, totalFutureAdded, "pending future must survive re-freeze");
            }
        }

        assertEq(totalNextAdded, 1500, "sanity: total next");
        assertEq(totalFutureAdded, 3000, "sanity: total future");

        harness.exposed_unfreezePool();

        assertFalse(harness.getFrozen(), "should be unfrozen after jackpot phase");

        (uint128 finalNext, uint128 finalFuture) = harness.exposed_getPrizePools();
        assertEq(finalNext, 10000 + 1500, "live next should absorb all 5 days of pending");
        assertEq(finalFuture, 20000 + 3000, "live future should absorb all 5 days of pending");

        (uint128 pn, uint128 pf) = harness.exposed_getPendingPools();
        assertEq(pn, 0, "pending next should be zero after unfreeze");
        assertEq(pf, 0, "pending future should be zero after unfreeze");
        assertEq(harness.rawPendingPools(), SENTINEL);
    }

    // =====================================================================
    // Round-trip lifecycle test
    // =====================================================================

    function testFreezeUnfreezeRoundTrip() public {
        harness.exposed_setPrizePools(7777, 8888);

        harness.exposed_swapAndFreeze(0);
        assertTrue(harness.getFrozen());

        (uint128 pNext, uint128 pFuture) = harness.exposed_getPendingPools();
        assertEq(pNext, 0);
        assertEq(pFuture, 0, "the freeze seeds nothing");

        (uint128 next, uint128 future) = harness.exposed_getPrizePools();
        assertEq(next, 7777, "live next unchanged during freeze");
        assertEq(future, 8888, "live future unchanged during freeze");

        harness.exposed_setPendingPools(333, 444);

        harness.exposed_unfreezePool();

        (next, future) = harness.exposed_getPrizePools();
        assertEq(next, 7777 + 333, "live next = original + pending after unfreeze");
        assertEq(future, 8888 + 444, "live future = original + pending after unfreeze");

        (pNext, pFuture) = harness.exposed_getPendingPools();
        assertEq(pNext, 0);
        assertEq(pFuture, 0);
        assertEq(harness.rawPendingPools(), SENTINEL);
        assertFalse(harness.getFrozen());
    }
}
