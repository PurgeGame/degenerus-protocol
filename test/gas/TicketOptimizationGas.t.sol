// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.33;
import {RoundDrainChunkGas, ChunkHarness} from "./RoundDrainChunkGas.t.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @notice Fixed-work comparisons for the packed-tail optimization, including event digests.
/// @dev Cooling resets access warmth between chunks, but does not create separate transactions
///      or reset original storage values for SSTORE pricing. These are synthetic comparative
///      measurements, excluding transaction intrinsic gas, rather than live fee estimates.
contract TicketOptimizationGas is RoundDrainChunkGas {
    function _full(uint256 n, uint32 owed) internal {
        h.seed(LVL, n, owed, 0x70000, false);
        uint256 totalGas;
        uint256 peak;
        uint256 calls;
        bool done;
        vm.recordLogs();
        while (!done && calls < 1000) {
            vm.cool(address(h));
            vm.cool(ContractAddresses.GAME_FOILPACK_MODULE);
            uint256 beforeGas = gasleft();
            (done,) = h.processTicketBatch(LVL + 1);
            uint256 used = beforeGas - gasleft();
            totalGas += used;
            if (used > peak) peak = used;
            ++calls;
        }
        bytes32 events = keccak256(abi.encode(vm.getRecordedLogs()));
        assertTrue(done);
        for (uint256 i; i < n; ++i) {
            assertEq(h.owedOf(LVL, address(uint160(0x70001 + i))), 0);
        }
        emit log_named_uint("total_gas", totalGas);
        emit log_named_uint("peak_gas", peak);
        emit log_named_uint("calls", calls);
        emit log_named_bytes32("events_digest", events);
    }

    function test_Full_Crowd() public {
        _full(600, 8);
    }

    function test_Full_Whale() public {
        _full(1, 5000);
    }

    function test_Full_EightWhales() public {
        _full(8, 2000);
    }
}
