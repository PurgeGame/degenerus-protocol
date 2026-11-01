// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Test} from "forge-std/Test.sol";
import {DegenerusGameAdvanceModule} from "../../contracts/modules/DegenerusGameAdvanceModule.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {WalletSeed} from "../helpers/WalletSeed.sol";

/// @title AdvanceHarness -- Exposes the production ticket-slot swap, pool freeze and queue helpers.
contract AdvanceHarness is DegenerusGameAdvanceModule, WalletSeed {
    // --- Freeze / Unfreeze ---
    function exposed_swapAndFreeze(uint24 /* purchaseLevel */) external {
        _swapTicketSlot();
        _freezePool();
    }

    function exposed_unfreezePool() external {
        _unfreezePool();
    }

    function exposed_swapTicketSlot(uint24 /* purchaseLevel */) external {
        _swapTicketSlot();
    }

    // --- Ticket queue helpers ---
    function pushToTicketQueue(uint24 key, address addr) external {
        _tqAppend(key, _seedWallet(addr));
    }

    function getQueueLength(uint24 key) external view returns (uint256) {
        return _ticketQueueLength(key);
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

    function getTicketWriteSlot() external view returns (bool) {
        return ticketWriteSlot;
    }

    // --- Setters ---
    function setTicketsFullyProcessed(bool val) external {
        ticketsFullyProcessed = val;
    }

    function setFrozen(bool val) external {
        prizePoolFrozen = val;
    }

    function setTicketWriteSlot(bool val) external {
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
}

/// @title AdvanceGameRewriteTest -- Ticket-slot swap and pool freeze/unfreeze transitions.
contract AdvanceGameRewriteTest is Test {
    AdvanceHarness harness;
    uint24 constant LEVEL = 5;
    uint24 constant TICKET_SLOT_BIT = 1 << 23;

    function setUp() public {
        // The freeze push calls the parimutuel at its fixed address; this harness deploys
        // no protocol, so give that address one STOP byte — the typed void call needs code
        // to pass the extcodesize check and returns success without any market logic.
        vm.etch(ContractAddresses.PARIMUTUEL, hex"00");
        harness = new AdvanceHarness();
    }

    // =========================================================================
    // Mid-day path does NOT activate freeze
    // =========================================================================

    /// @dev Mid-day swap uses _swapTicketSlot alone (the daily request also runs _freezePool), so freeze stays false.
    function test_midDay_noFreeze() public {
        // Start: ticketWriteSlot = 0, not frozen
        assertFalse(harness.getTicketWriteSlot());
        assertFalse(harness.getFrozen());

        // Push entries to write slot (simulating purchases)
        uint24 wk = LEVEL; // writeSlot=0 => writeKey = raw level
        harness.pushToTicketQueue(wk, address(0xA11CE));
        harness.pushToTicketQueue(wk, address(0xB0B));
        assertEq(harness.getQueueLength(wk), 2);

        // Mid-day swap: uses _swapTicketSlot, NOT the swap-and-freeze pair
        harness.exposed_swapTicketSlot(LEVEL);

        // Freeze must NOT be activated
        assertFalse(harness.getFrozen(), "mid-day swap must not activate freeze");
        // ticketsFullyProcessed reset by swap
        assertFalse(harness.getTicketsFullyProcessed(), "swap resets ticketsFullyProcessed");
    }

    // =========================================================================
    // Break path — RNG requested keeps freeze active
    // =========================================================================

    /// @dev After _swapAndFreeze, prizePoolFrozen == true (STAGE_RNG_REQUESTED break path).
    function test_breakPath_rngRequested_freezeActive() public {
        assertFalse(harness.getFrozen());

        harness.exposed_swapAndFreeze(LEVEL);

        assertTrue(harness.getFrozen(),
            "freeze must be active after _swapAndFreeze (STAGE_RNG_REQUESTED)");
    }

    // =========================================================================
    // Break path — purchase daily unfreezes
    // =========================================================================

    /// @dev _unfreezePool merges pending into live and clears flag (STAGE_PURCHASE_DAILY).
    function test_breakPath_purchaseDaily_unfreezes() public {
        // Setup: frozen with pending pools
        harness.setFrozen(true);
        harness.exposed_setPrizePools(1000, 2000);
        harness.exposed_setPendingPools(100, 200);

        harness.exposed_unfreezePool();

        assertFalse(harness.getFrozen(), "freeze must be cleared after unfreeze (STAGE_PURCHASE_DAILY)");
        (uint128 next, uint128 future) = harness.exposed_getPrizePools();
        assertEq(next, 1100, "live next should include pending");
        assertEq(future, 2200, "live future should include pending");
    }

    // =========================================================================
    // Break path — jackpot phase ended unfreezes
    // =========================================================================

    /// @dev _unfreezePool clears freeze at STAGE_JACKPOT_PHASE_ENDED break path.
    function test_breakPath_jackpotPhaseEnded_unfreezes() public {
        // Setup: frozen with accumulated pending from 5 jackpot days
        harness.setFrozen(true);
        harness.exposed_setPrizePools(5000, 10000);
        harness.exposed_setPendingPools(1500, 3000);

        harness.exposed_unfreezePool();

        assertFalse(harness.getFrozen(), "freeze must be cleared at STAGE_JACKPOT_PHASE_ENDED");
        (uint128 next, uint128 future) = harness.exposed_getPrizePools();
        assertEq(next, 6500, "live next should absorb all jackpot-day pending");
        assertEq(future, 13000, "live future should absorb all jackpot-day pending");
    }

    // =========================================================================
    // Break path — jackpot mid-phase freeze persists
    // =========================================================================

    /// @dev Freeze persists during STAGE_JACKPOT_COIN_TICKETS (no unfreeze call).
    function test_breakPath_jackpotMidPhase_freezePersists() public {
        harness.setFrozen(true);
        harness.exposed_setPendingPools(300, 600);

        // No unfreeze call -- simulates STAGE_JACKPOT_COIN_TICKETS break path
        assertTrue(harness.getFrozen(),
            "freeze must persist during mid-jackpot break paths");

        // Pending preserved
        (uint128 pNext, uint128 pFuture) = harness.exposed_getPendingPools();
        assertEq(pNext, 300, "pending next must be preserved");
        assertEq(pFuture, 600, "pending future must be preserved");
    }
}
