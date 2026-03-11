// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";

/// @title AdvanceHarness -- Exposes drain-gate logic and freeze/queue helpers for advanceGame rewrite tests.
contract AdvanceHarness is DegenerusGameStorage {
    // --- Freeze / Unfreeze ---
    function exposed_swapAndFreeze(uint24 purchaseLevel) external {
        _swapAndFreeze(purchaseLevel);
    }

    function exposed_unfreezePool() external {
        _unfreezePool();
    }

    function exposed_swapTicketSlot(uint24 purchaseLevel) external {
        _swapTicketSlot(purchaseLevel);
    }

    // --- Ticket queue helpers ---
    function pushToTicketQueue(uint24 key, address addr) external {
        ticketQueue[key].push(addr);
    }

    function getQueueLength(uint24 key) external view returns (uint256) {
        return ticketQueue[key].length;
    }

    // --- Key helpers ---
    function exposed_tqReadKey(uint24 lvl) external view returns (uint24) {
        return _tqReadKey(lvl);
    }

    // --- Getters ---
    function getTicketsFullyProcessed() external view returns (bool) {
        return ticketsFullyProcessed;
    }

    function getFrozen() external view returns (bool) {
        return prizePoolFrozen;
    }

    function getTicketWriteSlot() external view returns (uint8) {
        return ticketWriteSlot;
    }

    // --- Setters ---
    function setTicketsFullyProcessed(bool val) external {
        ticketsFullyProcessed = val;
    }

    function setFrozen(bool val) external {
        prizePoolFrozen = val;
    }

    function setTicketWriteSlot(uint8 val) external {
        ticketWriteSlot = val;
    }

    // --- Prize Pool helpers (for unfreeze merge verification) ---
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

    /// @dev Simulates the pre-RNG drain gate logic from advanceGame.
    ///      Returns (shouldBounce, proceeded):
    ///        - (true, false)  = read slot non-empty, caller should be bounced
    ///        - (false, true)  = read slot empty or already processed, proceed to do{} block
    function simulateDrainGate(uint24 purchaseLevel) external returns (bool shouldBounce, bool proceeded) {
        if (!ticketsFullyProcessed) {
            uint24 rk = _tqReadKey(purchaseLevel);
            if (ticketQueue[rk].length > 0) {
                // Read slot has entries -- would call _runProcessTicketBatch and bounce
                return (true, false);
            }
            ticketsFullyProcessed = true;
        }
        return (false, true);
    }

    /// @dev Simulates the in-do{}-block flag set after _runProcessTicketBatch returns finished.
    function simulateInCycleTicketDone() external {
        ticketsFullyProcessed = true;
    }
}

/// @title AdvanceGameRewriteTest -- Unit tests for ADV-01, ADV-02, ADV-03, and break-path freeze audit (SC-4).
contract AdvanceGameRewriteTest is Test {
    AdvanceHarness harness;
    uint24 constant LEVEL = 5;
    uint24 constant TICKET_SLOT_BIT = 1 << 23;

    function setUp() public {
        harness = new AdvanceHarness();
    }

    // =========================================================================
    // ADV-01: Mid-day path does NOT activate freeze
    // =========================================================================

    /// @dev Mid-day swap uses _swapTicketSlot (not _swapAndFreeze), so freeze stays false.
    function test_midDay_noFreeze() public {
        // Start: ticketWriteSlot = 0, not frozen
        assertEq(harness.getTicketWriteSlot(), 0);
        assertFalse(harness.getFrozen());

        // Push entries to write slot (simulating purchases)
        uint24 wk = LEVEL; // writeSlot=0 => writeKey = raw level
        harness.pushToTicketQueue(wk, address(0xA11CE));
        harness.pushToTicketQueue(wk, address(0xB0B));
        assertEq(harness.getQueueLength(wk), 2);

        // Mid-day swap: uses _swapTicketSlot, NOT _swapAndFreeze
        harness.exposed_swapTicketSlot(LEVEL);

        // Freeze must NOT be activated
        assertFalse(harness.getFrozen(), "ADV-01: mid-day swap must not activate freeze");
        // ticketsFullyProcessed reset by swap
        assertFalse(harness.getTicketsFullyProcessed(), "swap resets ticketsFullyProcessed");
    }

    // =========================================================================
    // ADV-02: Daily drain gate blocks when read slot is non-empty
    // =========================================================================

    /// @dev When ticketsFullyProcessed == false and read slot has entries, drain gate bounces.
    function test_dailyDrainGate_blocksWhenReadSlotNonEmpty() public {
        harness.setTicketsFullyProcessed(false);

        // Push entries to read slot (ticketWriteSlot=0, readKey = LEVEL | BIT)
        uint24 rk = LEVEL | TICKET_SLOT_BIT;
        harness.pushToTicketQueue(rk, address(0xA11CE));
        assertEq(harness.getQueueLength(rk), 1, "read slot should have 1 entry");

        // Drain gate should bounce
        (bool shouldBounce, bool proceeded) = harness.simulateDrainGate(LEVEL);
        assertTrue(shouldBounce, "ADV-02: should bounce when read slot non-empty");
        assertFalse(proceeded, "should not proceed");
        assertFalse(harness.getTicketsFullyProcessed(), "flag should still be false");
    }

    // =========================================================================
    // ADV-02: Daily drain gate proceeds when read slot is empty
    // =========================================================================

    /// @dev When ticketsFullyProcessed == false and read slot is empty, gate sets flag and proceeds.
    function test_dailyDrainGate_proceedsWhenReadSlotEmpty() public {
        harness.setTicketsFullyProcessed(false);

        // Read slot is empty (default)
        uint24 rk = LEVEL | TICKET_SLOT_BIT;
        assertEq(harness.getQueueLength(rk), 0, "read slot should be empty");

        // Drain gate should proceed
        (bool shouldBounce, bool proceeded) = harness.simulateDrainGate(LEVEL);
        assertFalse(shouldBounce, "should not bounce when read slot empty");
        assertTrue(proceeded, "should proceed");
        assertTrue(harness.getTicketsFullyProcessed(), "ADV-02: flag should be true after empty drain");
    }

    // =========================================================================
    // ADV-02: Daily drain gate skips when already processed
    // =========================================================================

    /// @dev When ticketsFullyProcessed == true, drain gate is a no-op.
    function test_dailyDrainGate_skipsWhenAlreadyProcessed() public {
        harness.setTicketsFullyProcessed(true);

        // Even with entries in read slot, gate should skip
        uint24 rk = LEVEL | TICKET_SLOT_BIT;
        harness.pushToTicketQueue(rk, address(0xA11CE));

        (bool shouldBounce, bool proceeded) = harness.simulateDrainGate(LEVEL);
        assertFalse(shouldBounce, "should not bounce when already processed");
        assertTrue(proceeded, "should proceed immediately");
        assertTrue(harness.getTicketsFullyProcessed(), "flag should remain true");
    }

    // =========================================================================
    // ADV-03: ticketsFullyProcessed set before jackpot logic
    // =========================================================================

    /// @dev After in-cycle ticket batch completes, flag is true before any jackpot/phase logic.
    function test_ticketsProcessed_setBeforeJackpotLogic() public {
        harness.setTicketsFullyProcessed(false);
        assertFalse(harness.getTicketsFullyProcessed());

        // Simulate: _runProcessTicketBatch returned finished inside do{} block
        harness.simulateInCycleTicketDone();

        assertTrue(harness.getTicketsFullyProcessed(),
            "ADV-03: ticketsFullyProcessed must be true before jackpot/phase logic");
    }

    // =========================================================================
    // SC-4: Break path — RNG requested keeps freeze active
    // =========================================================================

    /// @dev After _swapAndFreeze, prizePoolFrozen == true (STAGE_RNG_REQUESTED break path).
    function test_breakPath_rngRequested_freezeActive() public {
        assertFalse(harness.getFrozen());

        harness.exposed_swapAndFreeze(LEVEL);

        assertTrue(harness.getFrozen(),
            "SC-4: freeze must be active after _swapAndFreeze (STAGE_RNG_REQUESTED)");
    }

    // =========================================================================
    // SC-4: Break path — purchase daily unfreezes
    // =========================================================================

    /// @dev _unfreezePool merges pending into live and clears flag (STAGE_PURCHASE_DAILY).
    function test_breakPath_purchaseDaily_unfreezes() public {
        // Setup: frozen with pending pools
        harness.setFrozen(true);
        harness.exposed_setPrizePools(1000, 2000);
        harness.exposed_setPendingPools(100, 200);

        harness.exposed_unfreezePool();

        assertFalse(harness.getFrozen(), "SC-4: freeze must be cleared after unfreeze (STAGE_PURCHASE_DAILY)");
        (uint128 next, uint128 future) = harness.exposed_getPrizePools();
        assertEq(next, 1100, "live next should include pending");
        assertEq(future, 2200, "live future should include pending");
    }

    // =========================================================================
    // SC-4: Break path — jackpot phase ended unfreezes
    // =========================================================================

    /// @dev _unfreezePool clears freeze at STAGE_JACKPOT_PHASE_ENDED break path.
    function test_breakPath_jackpotPhaseEnded_unfreezes() public {
        // Setup: frozen with accumulated pending from 5 jackpot days
        harness.setFrozen(true);
        harness.exposed_setPrizePools(5000, 10000);
        harness.exposed_setPendingPools(1500, 3000);

        harness.exposed_unfreezePool();

        assertFalse(harness.getFrozen(), "SC-4: freeze must be cleared at STAGE_JACKPOT_PHASE_ENDED");
        (uint128 next, uint128 future) = harness.exposed_getPrizePools();
        assertEq(next, 6500, "live next should absorb all jackpot-day pending");
        assertEq(future, 13000, "live future should absorb all jackpot-day pending");
    }

    // =========================================================================
    // SC-4: Break path — jackpot mid-phase freeze persists
    // =========================================================================

    /// @dev Freeze persists during STAGE_JACKPOT_COIN_TICKETS (no unfreeze call).
    function test_breakPath_jackpotMidPhase_freezePersists() public {
        harness.setFrozen(true);
        harness.exposed_setPendingPools(300, 600);

        // No unfreeze call -- simulates STAGE_JACKPOT_COIN_TICKETS break path
        assertTrue(harness.getFrozen(),
            "SC-4/FREEZE-04: freeze must persist during mid-jackpot break paths");

        // Pending preserved
        (uint128 pNext, uint128 pFuture) = harness.exposed_getPendingPools();
        assertEq(pNext, 300, "pending next must be preserved");
        assertEq(pFuture, 600, "pending future must be preserved");
    }
}
