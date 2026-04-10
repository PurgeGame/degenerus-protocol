// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";

/// @title LockRemovalHarness -- Reproduces post-removal guard logic for LOCK-01 through LOCK-06.
/// @dev Extends DegenerusGameStorage to access internal state. Each guard function mirrors
///      the contract logic AFTER rngLockedFlag references are removed.
contract LockRemovalHarness is DegenerusGameStorage {
    // --- Setters ---
    function setRngLockedFlag(bool val) external {
        rngLockedFlag = val;
    }

    function setGameOver(bool val) external {
        gameOver = val;
    }

    function setLastPurchaseDay(bool val) external {
        lastPurchaseDay = val;
    }

    function setLevel(uint24 val) external {
        level = val;
    }

    function setRngRequestTime(uint48 val) external {
        rngRequestTime = val;
    }

    function setRngWordByDay(uint256 day, uint256 word) external {
        rngWordByDay[uint32(day)] = word;
    }

    // --- LOCK-01: _callTicketPurchase guard (MintModule:838-840 post-removal) ---
    function callTicketPurchaseGuard(uint256 quantity) external view {
        if (quantity == 0 || quantity > type(uint32).max) revert E();
        if (gameOver) revert E();
        // rngLockedFlag check REMOVED
    }

    // --- LOCK-02: _purchaseFor lootbox guard (MintModule:627 post-removal) ---
    function purchaseForLootboxGuard(uint256 lootBoxAmount) external view returns (bool blocked) {
        uint24 purchaseLevel = level + 1;
        blocked = (lootBoxAmount != 0 && lastPurchaseDay && (purchaseLevel % 5 == 0));
    }

    // --- LOCK-03: openLootBox guard (removed entirely) ---
    function openLootBoxGuard() external pure {
        // Guard removed entirely -- no rngLockedFlag check
    }

    // --- LOCK-04: openBurnieLootBox guard (removed entirely) ---
    function openBurnieLootBoxGuard() external pure {
        // Guard removed entirely -- no rngLockedFlag check
    }

    // --- LOCK-05: jackpotResolutionActive (DegeneretteModule:503 post-removal) ---
    function jackpotResolutionActive() external view returns (bool) {
        return lastPurchaseDay && ((level + 1) % 5 == 0);
    }

    // --- LOCK-06: requestLootboxRng guard (AdvanceModule:641-644 post-removal, line 643 deleted) ---
    function requestLootboxRngGuard(uint256 currentDay) external view {
        if (rngWordByDay[uint32(currentDay)] == 0) revert E();
        // rngLockedFlag check REMOVED (was line 643)
        if (rngRequestTime != 0) revert E();
    }
}

/// @title LockRemovalTest -- Unit and fuzz tests for all six LOCK requirements.
contract LockRemovalTest is Test {
    LockRemovalHarness harness;

    function setUp() public {
        harness = new LockRemovalHarness();
    }

    // ========================================================================
    // LOCK-01: _callTicketPurchase no longer reverts on rngLockedFlag
    // ========================================================================

    function test_LOCK01_purchaseDuringRngLock() public {
        harness.setRngLockedFlag(true);
        // Must NOT revert
        harness.callTicketPurchaseGuard(1);
    }

    function test_LOCK01_purchaseStillRevertsOnGameOver() public {
        harness.setGameOver(true);
        vm.expectRevert(DegenerusGameStorage.E.selector);
        harness.callTicketPurchaseGuard(1);
    }

    function test_LOCK01_purchaseStillRevertsOnZeroQuantity() public {
        vm.expectRevert(DegenerusGameStorage.E.selector);
        harness.callTicketPurchaseGuard(0);
    }

    // ========================================================================
    // LOCK-02: _purchaseFor lootbox guard stripped of rngLockedFlag
    // ========================================================================

    function test_LOCK02_lootboxGuardStripped() public {
        harness.setRngLockedFlag(true);
        harness.setLastPurchaseDay(false);
        bool blocked = harness.purchaseForLootboxGuard(1);
        assertFalse(blocked, "Should not block when lastPurchaseDay=false");
    }

    function test_LOCK02_lootboxGuardBlocksOnJackpotLevel() public {
        harness.setLastPurchaseDay(true);
        harness.setLevel(4); // purchaseLevel = 5, 5%5 == 0
        bool blocked = harness.purchaseForLootboxGuard(1);
        assertTrue(blocked, "Should block on jackpot level + lastPurchaseDay");
    }

    function test_LOCK02_lootboxGuardPassesNonJackpot() public {
        harness.setLastPurchaseDay(true);
        harness.setLevel(5); // purchaseLevel = 6, 6%5 != 0
        bool blocked = harness.purchaseForLootboxGuard(1);
        assertFalse(blocked, "Should not block on non-jackpot level");
    }

    // ========================================================================
    // LOCK-03: openLootBox guard removed
    // ========================================================================

    function test_LOCK03_openLootBoxDuringLock() public {
        harness.setRngLockedFlag(true);
        // Must NOT revert
        harness.openLootBoxGuard();
    }

    // ========================================================================
    // LOCK-04: openBurnieLootBox guard removed
    // ========================================================================

    function test_LOCK04_openBurnieLootBoxDuringLock() public {
        harness.setRngLockedFlag(true);
        // Must NOT revert
        harness.openBurnieLootBoxGuard();
    }

    // ========================================================================
    // LOCK-05: jackpotResolutionActive ignores rngLockedFlag
    // ========================================================================

    function test_LOCK05_degeneretteJackpotResolution() public {
        harness.setRngLockedFlag(true);
        harness.setLastPurchaseDay(true);
        harness.setLevel(4); // (4+1)%5 == 0
        assertTrue(harness.jackpotResolutionActive(), "Should be active on jackpot level + lastPurchaseDay");
    }

    function test_LOCK05_degeneretteNotJackpotLevel() public {
        harness.setLastPurchaseDay(true);
        harness.setLevel(5); // (5+1)%5 != 0
        assertFalse(harness.jackpotResolutionActive(), "Should not be active on non-jackpot level");
    }

    // ========================================================================
    // LOCK-06: requestLootboxRng guard without rngLockedFlag
    // ========================================================================

    function test_LOCK06_lootboxRngRequestGate() public {
        harness.setRngLockedFlag(true);
        harness.setRngRequestTime(0);
        harness.setRngWordByDay(1, 12345); // rngWordByDay[1] != 0
        // Must NOT revert -- rngLockedFlag is true but guard is removed
        harness.requestLootboxRngGuard(1);
    }

    function test_LOCK06_lootboxRngStillBlocksOnActiveRequest() public {
        harness.setRngRequestTime(1); // Active VRF request
        harness.setRngWordByDay(1, 12345);
        vm.expectRevert(DegenerusGameStorage.E.selector);
        harness.requestLootboxRngGuard(1);
    }

    // ========================================================================
    // Fuzz: guards ignore rngLockedFlag entirely
    // ========================================================================

    function testFuzz_guardsIgnoreRngLockedFlag(bool rngLocked, uint24 lvl, bool lastDay) public {
        // Bound level to avoid uint24 overflow on lvl+1 (contract never reaches max level)
        lvl = uint24(bound(uint256(lvl), 0, type(uint24).max - 1));

        // Set rngLockedFlag to the fuzzed value
        harness.setRngLockedFlag(rngLocked);
        harness.setLastPurchaseDay(lastDay);
        harness.setLevel(lvl);

        // LOCK-01: purchase guard never reverts due to rngLockedFlag
        harness.callTicketPurchaseGuard(1);

        // LOCK-02: lootbox guard result is independent of rngLockedFlag
        bool blocked = harness.purchaseForLootboxGuard(1);
        uint24 purchaseLevel = lvl + 1;
        bool expectedBlocked = (lastDay && (purchaseLevel % 5 == 0));
        assertEq(blocked, expectedBlocked, "LOCK-02 guard must depend only on lastPurchaseDay and level");

        // LOCK-03 + LOCK-04: never revert
        harness.openLootBoxGuard();
        harness.openBurnieLootBoxGuard();

        // LOCK-05: jackpotResolutionActive depends only on lastPurchaseDay and level
        bool active = harness.jackpotResolutionActive();
        bool expectedActive = (lastDay && ((lvl + 1) % 5 == 0));
        assertEq(active, expectedActive, "LOCK-05 must depend only on lastPurchaseDay and level");
    }
}
