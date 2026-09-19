// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {ChunkHarness} from "./RoundDrainChunkGas.t.sol";
import {DegenerusGameFoilPackModule} from "../../contracts/modules/DegenerusGameFoilPackModule.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @dev Preparation commits before the measured transaction. The full resume budget is exercised
///      against distinct owners, nonzero registry positions and a cold storage access list.
abstract contract QueueDrainColdFixture is Test {
    ChunkHarness internal h;
    function _shape() internal pure virtual returns (uint256 n, uint32 scaled);
    function setUp() public {
        h = new ChunkHarness();
        vm.etch(ContractAddresses.GAME_FOILPACK_MODULE, address(new DegenerusGameFoilPackModule()).code);
        (uint256 n, uint32 scaled) = _shape();
        h.seedViaPurchase(3, n, scaled, 0xCD0000, true);
    }
    function test_ColdFullBudgetDrain() public {
        uint256 beforeGas = gasleft();
        (bool worked,, uint32 units) = h.processFutureTicketBatch(3, uint256(keccak256("chunk-gas-entropy")) | 1);
        uint256 used = beforeGas - gasleft();
        emit log_named_uint("QUEUE_COLD_FULL_BUDGET_DRAIN", used);
        emit log_named_uint("QUEUE_DRAIN_UNITS", units);
        assertTrue(worked, "fixture must exercise the drain");
        assertGe(units, 800, "fixture must exercise most of the full budget");
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
