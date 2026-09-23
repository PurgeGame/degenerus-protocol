// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

// =============================================================================
// TicketQueueReleaseGas.t.sol
// -----------------------------------------------------------------------------
// Regression for the unbounded-queue-release liveness hazard: `delete` on a
// dynamic storage array compiles into a loop zeroing every element slot
// (~5,054 gas each against committed storage — measured: 15.16M gas for a
// 3,000-entry queue, past the 16.7M ceiling near ~3,300 entries). The batch
// processing loops are write-budgeted, but a `delete`'s compiler-generated
// clear is not, so the finishing call of a long queue would exceed the block
// gas limit and permanently stall advancement (the cursor reset reverts with
// it, so every retry re-hits the same clear).
//
// The production release primitive is `_releaseTicketQueue` (DegenerusGameStorage),
// which zeroes ONLY the array length slot: O(1) regardless of queue length.
// This test commits a 3,000-entry queue (vm.store = committed, original-nonzero
// storage — the state under which the old `delete` cost its full ~5k/slot) and
// asserts the finishing call on BOTH production release sites stays far below
// the ceiling: the far-future release inside the private `_processFutureTicketBatch`
// (reachable only through `processTicketBatch`'s lastPurchaseDay continuation, since
// the standalone external `processFutureTicketBatch` entry point was removed — it is
// now `_processFutureTicketBatch`, private, always targeting the far-future key, no
// near/read-key mode) and the read-window release inside `processTicketBatch` itself.
//
// Execution mechanic (same as MintModuleDivergenceAcrossSplit.t.sol): the
// batch functions run via delegatecall from DegenerusGame in production; here
// they are invoked directly on the deployed MintModule, whose own storage is a
// valid host because every module inherits the identical DegenerusGameStorage
// layout.
// =============================================================================

import {TicketQueueStorage} from "./helpers/TicketQueueStorage.sol";

import {DeployProtocol} from "./helpers/DeployProtocol.sol";

contract TicketQueueReleaseGasTest is DeployProtocol {
    // ---- DegenerusGameStorage slot constants (see MintModuleDivergenceAcrossSplit) ----
    /// @dev ticketQueue (mapping(uint24 => uint256[])) — slot 12.
    uint256 private constant SLOT_TICKET_QUEUE = 12;
    /// @dev packed slot 14: ticketCursor (uint32) offset 0; ticketLevel (uint24) offset 4.
    uint256 private constant SLOT_TICKET_CURSOR_LEVEL = 14;
    /// @dev lootboxRngPacked — slot 33 (low 48 bits = lootboxRngIndex, defaults to 1).
    uint256 private constant SLOT_LOOTBOX_RNG_PACKED = 33;
    /// @dev lootboxRngWordByIndex (mapping(uint48 => uint256)) — slot 34.
    uint256 private constant SLOT_LOOTBOX_RNG_WORD_BY_INDEX = 34;
    /// @dev Slot 0: packed timing/level/flags word. level occupies byte offset 12 (3 bytes);
    ///      lastPurchaseDay is the single bit at byte offset 17; rngLockedFlag at byte 19
    ///      (see the DegenerusGameStorage slot-0 layout table).
    uint256 private constant SLOT_0 = 0;
    uint256 private constant LEVEL_BYTE_SHIFT = 12 * 8;
    uint256 private constant LAST_PURCHASE_DAY_BYTE_SHIFT = 17 * 8;
    uint256 private constant RNG_LOCKED_BYTE_SHIFT = 19 * 8;

    /// @dev Mirror of DegenerusGameStorage.TICKET_SLOT_BIT. With the default
    ///      ticketWriteSlot=false, _tqReadKey(lvl) = lvl | TICKET_SLOT_BIT.
    uint24 private constant TICKET_SLOT_BIT = uint24(1) << 23;
    /// @dev Mirror of DegenerusGameStorage.TICKET_FAR_FUTURE_BIT.
    uint24 private constant TICKET_FAR_FUTURE_BIT = uint24(1) << 22;

    uint24 private constant LVL = 1;
    uint256 private constant QUEUE_LEN = 3000;

    /// @dev Ceiling the finishing call must stay under. The pre-fix `delete`
    ///      cost ~15.16M at 3,000 entries (linear in length); the O(1) release
    ///      is a single length-slot write, orders of magnitude below this.
    uint256 private constant GAS_CEILING = 1_000_000;

    function setUp() public {
        _deployProtocol();
        vm.warp(vm.getBlockTimestamp() + 1 days);
        mockVRF.fundSubscription(1, 100e18);
    }

    function _queueLen(address host, uint24 key) private view returns (uint256) {
        return uint256(
            vm.load(host, keccak256(abi.encode(uint256(key), SLOT_TICKET_QUEUE)))
        );
    }

    function _armEntropy(address host) private {
        // Entropy word for processTicketBatch's lootboxRngWordByIndex[lrIndex-1]
        // read (lrIndex defaults to 1 → index 0).
        vm.store(
            host,
            keccak256(abi.encode(uint256(0), SLOT_LOOTBOX_RNG_WORD_BY_INDEX)),
            bytes32(uint256(keccak256("ticket-queue-release-gas-entropy")))
        );
    }

    /// @dev Finishing call of the private `_processFutureTicketBatch` on a fully-processed
    ///      3,000-entry far-future queue, reached only through `processTicketBatch`'s
    ///      lastPurchaseDay continuation (the standalone external entry point is gone).
    ///      Pins level=49 with lastPurchaseDay latched and RNG locked, so
    ///      `_mintCeiling()` (= level + 1) lands on far-future target level 50 — a level far
    ///      outside any protocol constructor pre-seeding, so the committed 3,000-entry count
    ///      is exact. Must release in O(1), far under the ceiling.
    function test_futureBatchFinishingCall_releasesLongQueueBounded() public {
        address host = address(mintModule);
        uint24 ffTargetLvl = 50;
        uint24 ffk = ffTargetLvl | TICKET_FAR_FUTURE_BIT;

        // Commit 3,000 registered owners as packed lanes before measuring O(1) release.
        for (uint256 i; i < QUEUE_LEN; ++i) {
            TicketQueueStorage.seed(host, ffk, ffTargetLvl, address(uint160(0x10000 + i)), 0);
        }
        assertEq(_queueLen(host, ffk), QUEUE_LEN, "seed: FF queue committed");

        // A committed post-seal word makes the frozen pool due. With the RNG lock
        // active, _mintCeiling() = level + 1 = 50 = ffTargetLvl.
        uint256 slot0 = uint256(vm.load(host, bytes32(SLOT_0)));
        slot0 = (slot0 & ~(uint256(0xFFFFFF) << LEVEL_BYTE_SHIFT)) | (uint256(49) << LEVEL_BYTE_SHIFT);
        slot0 |= uint256(1) << LAST_PURCHASE_DAY_BYTE_SHIFT;
        slot0 |= uint256(1) << RNG_LOCKED_BYTE_SHIFT;
        vm.store(host, bytes32(SLOT_0), bytes32(slot0));

        // Cursor already at end-of-queue (all entries processed on prior calls); ticketLevel
        // already carries the FF marker so processTicketBatch's FF continuation does not
        // reset the cursor before dispatching. This puts the very next call on the
        // finishing path — the release site inside `_processFutureTicketBatch`.
        vm.store(
            host,
            bytes32(SLOT_TICKET_CURSOR_LEVEL),
            bytes32((uint256(ffk) << 32) | QUEUE_LEN)
        );
        _armEntropy(host);

        uint256 g0 = gasleft();
        // anchor = level + 1; the read window [anchor-1..ceiling] = [49..50] scans only
        // empty read-side queues, so the FF continuation is reached with no near-side work.
        (bool finished, bool didWork) = mintModule.processTicketBatch(50);
        uint256 gasUsed = g0 - gasleft();

        assertFalse(didWork, "finishing call materializes no new ticket");
        // processTicketBatch's FF continuation always reports outer finished=false (it
        // defers the sweep-finished declaration to the foil-drain check on a later call);
        // the inner drain's own completion is observable via the cursor/level reset.
        assertFalse(finished, "outer sweep defers finished to a later call (FF continuation contract)");
        assertEq(
            uint256(vm.load(host, bytes32(SLOT_TICKET_CURSOR_LEVEL))),
            0,
            "ticketCursor/ticketLevel reset: FF drain fully finished"
        );
        assertEq(_queueLen(host, ffk), 0, "FF queue length released to 0");
        assertLt(gasUsed, GAS_CEILING, "release is O(1), not O(len)");
    }

    /// @dev Same property through processTicketBatch (the current-level entry point, the
    ///      idx>=total and drained-window release sites).
    function test_ticketBatchFinishingCall_releasesLongQueueBounded() public {
        address host = address(mintModule);
        uint24 rk = LVL | TICKET_SLOT_BIT; // _tqReadKey(LVL) with the default ticketWriteSlot=false

        // Commit 3,000 registered owners as packed lanes before measuring O(1) release.
        for (uint256 i; i < QUEUE_LEN; ++i) {
            TicketQueueStorage.seed(host, rk, LVL, address(uint160(0x10000 + i)), 0);
        }
        assertEq(_queueLen(host, rk), QUEUE_LEN, "seed: queue committed");

        // Cursor already at end-of-queue (all entries processed on prior txs);
        // ticketLevel = LVL so neither entry point resets the cursor. This puts
        // the very next call on the finishing path — the release site. The deploy-default
        // level = 0 gives _mintCeiling() = 1 = LVL, so the window [LVL-1..LVL] covers it.
        vm.store(
            host,
            bytes32(SLOT_TICKET_CURSOR_LEVEL),
            bytes32((uint256(LVL) << 32) | QUEUE_LEN)
        );
        _armEntropy(host);

        uint256 g0 = gasleft();
        (bool finished, ) = mintModule.processTicketBatch(LVL);
        uint256 gasUsed = g0 - gasleft();

        assertTrue(finished, "finishing call reports finished");
        assertEq(_queueLen(host, rk), 0, "queue length released to 0");
        assertLt(gasUsed, GAS_CEILING, "release is O(1), not O(len)");
    }
}
