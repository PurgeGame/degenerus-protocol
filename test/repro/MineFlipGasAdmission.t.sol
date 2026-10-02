// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";

/// @dev Fresh writes make each atomic chunk actually consume more than 10M gas.
contract LargeAtomicGasHarness {
    uint256 public completed;
    mapping(uint256 => uint256) public writes;

    function run(uint256 allowance, uint256 target) external returns (uint256) {
        MineFlipGas.Meter memory meter = MineFlipGas.start(allowance);
        while (completed < target) {
            if (!MineFlipGas.canRun(meter, 12_000_000, 100_000)) break;
            uint256 offset = completed * 512;
            for (uint256 i; i < 512; ++i) writes[offset + i] = 1;
            ++completed;
        }
        MineFlipGas.finish(meter);
        return completed;
    }
}

contract MineFlipGasAdmissionTest is Test {
    LargeAtomicGasHarness private h;

    function setUp() public { h = new LargeAtomicGasHarness(); }

    function test_TwelveMillionReservationRunsWithSixteenMillionSupplied() public {
        uint256 beforeGas = gasleft();
        assertEq(h.run{gas: 16_000_000}(15_000_000, 1), 1);
        uint256 used = beforeGas - gasleft();
        assertGt(used, 10_000_000, "actual atomic execution exceeds the sizing guideline");
        assertLt(used, 12_100_000, "actual work fits its chunk and return reservation");
        assertEq(h.writes(511), 1, "the whole chunk committed");
    }

    function test_LowCallerGasStopsBeforeChunkAndLargerCallResumes() public {
        assertEq(h.run{gas: 10_000_000}(15_000_000, 1), 0);
        assertEq(h.writes(0), 0, "unadmitted chunk has no writes");
        assertEq(h.run{gas: 16_000_000}(15_000_000, 1), 1);
    }

    function test_ParentAllowanceStillLimitsAWellFundedChild() public {
        assertEq(h.run{gas: 16_000_000}(10_000_000, 1), 0);
        assertEq(h.writes(0), 0);
    }

    function test_ChunkCannotConsumeTheCheckpointTail() public {
        assertEq(h.run{gas: 16_000_000}(12_050_000, 1), 0);
        assertEq(h.writes(0), 0);
    }

    function test_ActualSpendingStopsTheNextChunkAtItsCheckpoint() public {
        assertEq(h.run{gas: 16_000_000}(15_000_000, 2), 1);
        assertEq(h.writes(511), 1);
        assertEq(h.writes(512), 0, "second chunk waits for sufficient remaining gas");
        vm.cool(address(h));
        assertEq(h.run{gas: 16_000_000}(15_000_000, 2), 2);
        assertEq(h.writes(1023), 1);
    }
}
