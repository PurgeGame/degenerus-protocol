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
// This test commits a 3,000-entry queue (vm.store in setUp = committed,
// original-nonzero storage — the state under which the old `delete` cost its
// full ~5k/slot) and asserts the finishing call on BOTH production entry
// points stays far below the ceiling.
//
// Execution mechanic (same as MintModuleDivergenceAcrossSplit.t.sol): the
// batch functions run via delegatecall from DegenerusGame in production; here
// they are invoked directly on the deployed MintModule, whose own storage is a
// valid host because every module inherits the identical DegenerusGameStorage
// layout.
// =============================================================================

import {DeployProtocol} from "./helpers/DeployProtocol.sol";

contract TicketQueueReleaseGasTest is DeployProtocol {
    // ---- DegenerusGameStorage slot constants (see MintModuleDivergenceAcrossSplit) ----
    /// @dev ticketQueue (mapping(uint24 => address[])) — slot 12.
    uint256 private constant SLOT_TICKET_QUEUE = 12;
    /// @dev packed slot 14: ticketCursor (uint32) offset 0; ticketLevel (uint24) offset 4.
    uint256 private constant SLOT_TICKET_CURSOR_LEVEL = 14;
    /// @dev lootboxRngPacked — slot 33 (low 48 bits = lootboxRngIndex, defaults to 1).
    uint256 private constant SLOT_LOOTBOX_RNG_PACKED = 33;
    /// @dev lootboxRngWordByIndex (mapping(uint48 => uint256)) — slot 34.
    uint256 private constant SLOT_LOOTBOX_RNG_WORD_BY_INDEX = 34;

    /// @dev Mirror of DegenerusGameStorage.TICKET_SLOT_BIT. With the default
    ///      ticketWriteSlot=false, _tqReadKey(lvl) = lvl | TICKET_SLOT_BIT.
    uint24 private constant TICKET_SLOT_BIT = uint24(1) << 23;

    uint24 private constant LVL = 1;
    uint256 private constant QUEUE_LEN = 3000;

    /// @dev Ceiling the finishing call must stay under. The pre-fix `delete`
    ///      cost ~15.16M at 3,000 entries (linear in length); the O(1) release
    ///      is a single length-slot write, orders of magnitude below this.
    uint256 private constant GAS_CEILING = 1_000_000;

    uint24 private rk; // read key for LVL

    function setUp() public {
        _deployProtocol();
        vm.warp(vm.getBlockTimestamp() + 1 days);
        mockVRF.fundSubscription(1, 100e18);

        rk = LVL | TICKET_SLOT_BIT;
        address host = address(mintModule);

        // Commit a 3,000-entry queue: length + 3,000 distinct nonzero element
        // slots, written in setUp (a prior tx), so the test tx sees them as
        // original-nonzero committed storage — the exact state under which the
        // old `delete` paid its full per-slot clearing cost.
        bytes32 lenSlot = keccak256(abi.encode(uint256(rk), SLOT_TICKET_QUEUE));
        uint256 dataSlot = uint256(keccak256(abi.encode(lenSlot)));
        vm.store(host, lenSlot, bytes32(QUEUE_LEN));
        for (uint256 i = 0; i < QUEUE_LEN; ++i) {
            vm.store(host, bytes32(dataSlot + i), bytes32(uint256(uint160(0x10000 + i))));
        }

        // Cursor already at end-of-queue (all entries processed on prior txs);
        // ticketLevel = LVL so neither entry point resets the cursor. This puts
        // the very next call on the finishing path — the release site.
        vm.store(
            host,
            bytes32(SLOT_TICKET_CURSOR_LEVEL),
            bytes32((uint256(LVL) << 32) | QUEUE_LEN)
        );

        // Entropy word for processTicketBatch's lootboxRngWordByIndex[lrIndex-1]
        // read (lrIndex defaults to 1 → index 0).
        vm.store(
            host,
            keccak256(abi.encode(uint256(0), SLOT_LOOTBOX_RNG_WORD_BY_INDEX)),
            bytes32(uint256(keccak256("ticket-queue-release-gas-entropy")))
        );
    }

    function _queueLen(address host) private view returns (uint256) {
        return uint256(
            vm.load(host, keccak256(abi.encode(uint256(rk), SLOT_TICKET_QUEUE)))
        );
    }

    /// @dev Finishing call of processFutureTicketBatch on a fully-processed
    ///      3,000-entry queue: must release in O(1), far under the ceiling.
    function test_futureBatchFinishingCall_releasesLongQueueBounded() public {
        address host = address(mintModule);
        assertEq(_queueLen(host), QUEUE_LEN, "seed: queue committed");

        uint256 g0 = gasleft();
        (, bool finished, ) = mintModule.processFutureTicketBatch(LVL, 1);
        uint256 gasUsed = g0 - gasleft();

        assertTrue(finished, "finishing call reports finished");
        assertEq(_queueLen(host), 0, "queue length released to 0");
        assertLt(gasUsed, GAS_CEILING, "release is O(1), not O(len)");
    }

    /// @dev Same property through processTicketBatch (the current-level entry
    ///      point, release sites at the idx>=total and drained paths).
    function test_ticketBatchFinishingCall_releasesLongQueueBounded() public {
        address host = address(mintModule);
        assertEq(_queueLen(host), QUEUE_LEN, "seed: queue committed");

        uint256 g0 = gasleft();
        (bool finished, ) = mintModule.processTicketBatch(LVL);
        uint256 gasUsed = g0 - gasleft();

        assertTrue(finished, "finishing call reports finished");
        assertEq(_queueLen(host), 0, "queue length released to 0");
        assertLt(gasUsed, GAS_CEILING, "release is O(1), not O(len)");
    }
}
