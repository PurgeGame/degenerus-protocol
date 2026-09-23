// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {ChunkHarness} from "./RoundDrainChunkGas.t.sol";
import {DegenerusGameFoilPackModule} from "../../contracts/modules/DegenerusGameFoilPackModule.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @dev Preparation commits before the measured transaction. The full resume budget is exercised
///      against distinct owners, nonzero registry positions and a cold storage access list.
///
///      The measured path is the one far-future drain that exists: a level's unminted queue is
///      minted exactly once, as the frozen pool, inside processTicketBatch's continuation once
///      the previous level's last purchase day has latched and a cohort was committed after it
///      (`_frozenPoolDue`). The external `processFutureTicketBatch` (the removed transition
///      drain) is gone; `_processFutureTicketBatch` is its private worker. setUp() queues the
///      buyers through the production purchase sink onto TARGET_LVL's far-future key and puts
///      the harness in the post-last-purchase-request state (ChunkHarness.seedFrozenPool).
abstract contract QueueDrainColdFixture is Test {
    ChunkHarness internal h;

    /// @dev Mirror of DegenerusGameStorage.TICKET_FAR_FUTURE_BIT.
    uint24 internal constant TICKET_FAR_FUTURE_BIT = uint24(1) << 22;
    uint24 internal constant TARGET_LVL = 3;

    function _shape() internal pure virtual returns (uint256 n, uint32 scaled);

    function setUp() public {
        h = new ChunkHarness();
        vm.etch(ContractAddresses.GAME_FOILPACK_MODULE, address(new DegenerusGameFoilPackModule()).code);
        (uint256 n, uint32 scaled) = _shape();
        // warm = true: FF marker + cursor 1, so the chunk runs the full (non-derated) budget.
        h.seedFrozenPool(TARGET_LVL, n, scaled, 0xCD0000, true);
    }

    function test_ColdFullBudgetDrain() public {
        (uint256 n, ) = _shape();
        uint24 ffk = TARGET_LVL | TICKET_FAR_FUTURE_BIT;

        uint256 beforeGas = gasleft();
        // anchor = level = TARGET_LVL - 1 (the purchase level under the last-purchase lock); the
        // read window [TARGET_LVL-2 .. TARGET_LVL] is empty, so the call reaches the frozen-pool
        // continuation and mints one full-budget chunk of TARGET_LVL's far-future queue.
        (bool finishedOuter, bool worked) = h.processTicketBatch(TARGET_LVL - 1);
        uint256 used = beforeGas - gasleft();
        uint256 cursorAfter = h.cursor();
        emit log_named_uint("QUEUE_COLD_FULL_BUDGET_DRAIN", used);
        emit log_named_uint("QUEUE_DRAIN_CURSOR_AFTER", cursorAfter);
        assertTrue(worked, "fixture must exercise the drain");
        assertFalse(finishedOuter, "the sweep is not finished while frozen-pool entries remain");
        // Budget-bound, not queue-exhausted: the chunk stopped mid-queue (the worker stops only
        // at the write budget or when the next entry no longer fits in what is left of it), the
        // resume cursor moved past the pre-drained index 0, and the queue is not yet released.
        // This replaces the removed external entry point's `units >= 800` return value.
        assertGt(cursorAfter, 1, "chunk must advance the frozen-pool cursor");
        assertLt(cursorAfter, n, "fixture must be budget-bound, not queue-exhausted");
        assertEq(h.queueLength(ffk), n, "frozen pool is released only when fully minted");
        assertLt(used, 11_000_000, "cold drain must retain the proven ceiling");
    }
}

contract QueueDrainColdSingleTickets is QueueDrainColdFixture {
    function _shape() internal pure override returns (uint256, uint32) { return (2000, 400); }
}
contract QueueDrainColdDust is QueueDrainColdFixture {
    function _shape() internal pure override returns (uint256, uint32) { return (2000, 1); }
}
contract QueueDrainColdWhales is QueueDrainColdFixture {
    function _shape() internal pure override returns (uint256, uint32) { return (200, 100_000); }
}
