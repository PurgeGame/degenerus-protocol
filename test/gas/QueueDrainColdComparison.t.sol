// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {ChunkHarness, TicketChunkProbe} from "./RoundDrainChunkGas.t.sol";
import {DegenerusGameTicketModule} from "../../contracts/modules/DegenerusGameTicketModule.sol";
import {DegenerusGameFoilPackModule} from "../../contracts/modules/DegenerusGameFoilPackModule.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";

/// @dev Preparation commits before the measured transaction. The resumed frozen-pool drain is
///      exercised against distinct owners, nonzero registry positions and a cold storage access
///      list.
///
///      The measured path is the one far-future drain that exists: a level's unminted queue is
///      minted exactly once, as the frozen pool, inside the ticket worker's continuation once
///      the previous level's last purchase day has latched and a cohort was committed after it
///      (`_frozenPoolDue`). setUp() queues the buyers through the production purchase sink onto
///      TARGET_LVL's far-future key and puts the harness in the post-last-purchase-request state
///      (ChunkHarness.seedFrozenPool).
///
///      The worker spends whatever gas it is given, so the cold call is driven with a realistic
///      10M and, separately, the 16.7M EIP-7825 cap: each must not run out of gas, must make
///      progress and must stop on the supplied gas with the pool still pending. The per-chunk
///      property is the smallest allowance admitting the first frozen-pool round, which must be
///      below 10M with the call completing inside it.
abstract contract QueueDrainColdFixture is TicketChunkProbe {
    /// @dev Mirror of DegenerusGameStorage.TICKET_FAR_FUTURE_BIT.
    uint24 internal constant TICKET_FAR_FUTURE_BIT = uint24(1) << 22;
    uint24 internal constant TARGET_LVL = 3;

    function _shape() internal pure virtual returns (uint256 n, uint32 scaled);

    function setUp() public {
        h = new ChunkHarness();
        vm.etch(ContractAddresses.GAME_TICKET_MODULE, address(new DegenerusGameTicketModule()).code);
        vm.etch(ContractAddresses.GAME_FOILPACK_MODULE, address(new DegenerusGameFoilPackModule()).code);
        (uint256 n, uint32 scaled) = _shape();
        // warm = true: FF marker + cursor 1, so the chunk resumes mid-pool.
        h.seedFrozenPool(TARGET_LVL, n, scaled, 0xCD0000, true);
    }

    function _coldChunk(uint256 gasLimit, string memory tag) internal {
        (uint256 n, ) = _shape();
        uint24 ffk = TARGET_LVL | TICKET_FAR_FUTURE_BIT;
        _cool();
        uint256 beforeGas = gasleft();
        // anchor = level = TARGET_LVL - 1 (the purchase level under the last-purchase lock); the
        // read window [TARGET_LVL-2 .. TARGET_LVL] is empty, so the call reaches the frozen-pool
        // continuation and mints TARGET_LVL's far-future queue on the supplied gas.
        MineFlipGas.Result memory r = h.runTicketWork{gas: gasLimit}(TARGET_LVL - 1, gasLimit);
        (bool finishedOuter, bool worked) = (r.done, r.progressed);
        uint256 used = beforeGas - gasleft();
        uint256 cursorAfter = h.cursor();
        emit log_named_uint(tag, used);
        emit log_named_uint(string.concat(tag, "_CURSOR_AFTER"), cursorAfter);
        assertTrue(worked, "fixture must exercise the drain");
        assertFalse(finishedOuter, "the sweep is not finished while frozen-pool entries remain");
        // Gas-bound, not queue-exhausted: the call stopped mid-queue (the worker stops only when
        // the next step no longer fits what is left of the supplied gas), the resume cursor moved
        // past the pre-drained logical index 0, and the queue is not yet released.
        assertGt(cursorAfter, 1, "chunk must advance the frozen-pool cursor");
        assertLt(cursorAfter, n, "fixture must be gas-bound, not queue-exhausted");
        assertEq(h.queueLength(ffk), n, "frozen pool is released only when fully minted");
    }

    function test_ColdFullBudgetDrain() public {
        uint256 snap = vm.snapshotState();
        _coldChunk(GAS_TARGET, "QUEUE_COLD_FULL_BUDGET_DRAIN");
        assertTrue(vm.revertToState(snap));
        _coldChunk(EIP7825_TX_GAS_CAP, "QUEUE_COLD_FULL_BUDGET_DRAIN_16P7M");
        assertTrue(vm.revertToStateAndDelete(snap));
        _oneChunk(TARGET_LVL - 1, "QUEUE_COLD_FROZEN_POOL_ROUND", Step.Round);
    }
}

contract QueueDrainColdSingleTickets is QueueDrainColdFixture {
    function _shape() internal pure override returns (uint256, uint32) { return (2000, 400); }
}
/// @dev Far-future lanes hold whole entries only (no QTY remainder field; `_setEntryOwed`
///      rejects a far-future remainder and every production far-future source queues whole
///      entries), so a fractional "dust" far-future queue is unreachable. The cheapest reachable
///      far-future walk is one whole entry per owner: every round exhausts and re-seats all
///      eight seats, the seat-heavy shape closest to the old dust walk.
contract QueueDrainColdDust is QueueDrainColdFixture {
    function _shape() internal pure override returns (uint256, uint32) { return (2000, 100); }
}
contract QueueDrainColdWhales is QueueDrainColdFixture {
    function _shape() internal pure override returns (uint256, uint32) { return (200, 100_000); }
}
