// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Test} from "forge-std/Test.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";

abstract contract AtomicGasFixture {
    uint256 internal constant ATOMIC_WORK_GAS = 12_000_000;
    uint256 internal constant ATOMIC_TAIL_GAS = 100_000;
    uint256 internal constant SLOTS_PER_UNIT = 512;
    uint256 internal constant CALL_GAS = 16_000_000;
    uint256 internal constant WORK_ALLOWANCE = 15_000_000;
    uint256 internal constant CHECKPOINT_TARGET_GAS = 10_000_000;
    uint256 internal constant UNDERFUNDED_CALL_GAS = 1_000_000;
    // Independent expected API values, not aliases of the implementation under test.
    uint32 internal constant EXPECTED_MIN_MULTIPLIER = 2_500;
    uint32 internal constant EXPECTED_BASE_MULTIPLIER = 10_000;
}

/// @dev Fresh writes make each atomic chunk actually consume more than 10M gas.
contract LargeAtomicGasHarness is AtomicGasFixture {
    uint256 public completed;
    mapping(uint256 => uint256) public writes;

    function normalize(uint32 factor) external pure returns (uint32) {
        return MineFlipGas.normalize(factor);
    }

    function context(uint256 word) external view returns (uint32 factor, bool first, uint256 floor) {
        MineFlipGas.Meter memory meter = MineFlipGas.start(word);
        return (meter.multiplierBps, meter.mustProgress, meter.floor);
    }

    function run(uint256 allowance, uint256 target) external returns (uint256) {
        MineFlipGas.Meter memory meter = MineFlipGas.start(allowance);
        while (completed < target) {
            if (!MineFlipGas.canRun(meter, ATOMIC_WORK_GAS, ATOMIC_TAIL_GAS)) break;
            uint256 offset = completed * SLOTS_PER_UNIT;
            for (uint256 i; i < SLOTS_PER_UNIT; ++i) writes[offset + i] = 1;
            ++completed;
            MineFlipGas.markProgress(meter);
        }
        MineFlipGas.finish(meter);
        return completed;
    }
}

contract MineFlipGasAdmissionTest is Test, AtomicGasFixture {
    LargeAtomicGasHarness private h;

    function setUp() public { h = new LargeAtomicGasHarness(); }

    function test_TwelveMillionReservationRunsWithSixteenMillionSupplied() public {
        uint256 beforeGas = gasleft();
        assertEq(h.run{gas: CALL_GAS}(WORK_ALLOWANCE, 1), 1);
        uint256 used = beforeGas - gasleft();
        assertGt(used, CHECKPOINT_TARGET_GAS, "actual atomic execution exceeds the sizing guideline");
        assertLt(used, ATOMIC_WORK_GAS + ATOMIC_TAIL_GAS, "actual work fits its chunk and return reservation");
        assertEq(h.writes(SLOTS_PER_UNIT - 1), 1, "the whole chunk committed");
    }

    function test_LowCallerGasStopsBeforeChunkAndLargerCallResumes() public {
        assertEq(h.run{gas: CHECKPOINT_TARGET_GAS}(WORK_ALLOWANCE, 1), 0);
        assertEq(h.writes(0), 0, "unadmitted chunk has no writes");
        assertEq(h.run{gas: CALL_GAS}(WORK_ALLOWANCE, 1), 1);
    }

    function test_ParentAllowanceStillLimitsAWellFundedChild() public {
        assertEq(h.run{gas: CALL_GAS}(CHECKPOINT_TARGET_GAS, 1), 0);
        assertEq(h.writes(0), 0);
    }

    function test_ChunkCannotConsumeTheCheckpointTail() public {
        assertEq(h.run{gas: CALL_GAS}(ATOMIC_WORK_GAS + ATOMIC_TAIL_GAS / 2, 1), 0);
        assertEq(h.writes(0), 0);
    }

    function test_ActualSpendingStopsTheNextChunkAtItsCheckpoint() public {
        assertEq(h.run{gas: CALL_GAS}(WORK_ALLOWANCE, 2), 1);
        assertEq(h.writes(SLOTS_PER_UNIT - 1), 1);
        assertEq(h.writes(SLOTS_PER_UNIT), 0, "second chunk waits for sufficient remaining gas");
        vm.cool(address(h));
        assertEq(h.run{gas: CALL_GAS}(WORK_ALLOWANCE, 2), 2);
        assertEq(h.writes(2 * SLOTS_PER_UNIT - 1), 1);
    }
    function test_ExtremeCalibrationAlwaysAttemptsOneFundedAtomicChunk() public {
        uint256 budget = MineFlipGas.budget(WORK_ALLOWANCE, type(uint32).max, true);
        assertEq(h.run{gas: CALL_GAS}(budget, 2), 1);
        assertEq(h.run{gas: CALL_GAS}(budget, 2), 2);
    }

    function test_UnderfundedMandatoryChunkRollsBackAndCanRetry() public {
        uint256 budget = MineFlipGas.budget(WORK_ALLOWANCE, EXPECTED_BASE_MULTIPLIER, true);
        vm.expectRevert();
        h.run{gas: UNDERFUNDED_CALL_GAS}(budget, 1);
        assertEq(h.completed(), 0);
        assertEq(h.writes(0), 0);
        assertEq(h.run{gas: CALL_GAS}(budget, 1), 1);
    }

    function test_ScaleRoundsUpAndSaturates() public pure {
        MineFlipGas.Meter memory meter;
        meter.multiplierBps = 15_000;
        assertEq(MineFlipGas.scale(meter, 1), 2);
        assertEq(MineFlipGas.scale(meter, EXPECTED_BASE_MULTIPLIER), 15_000);
        assertEq(MineFlipGas.scale(meter, type(uint256).max), type(uint256).max);
        assertEq(MineFlipGas.normalize(0), EXPECTED_BASE_MULTIPLIER);
        assertEq(MineFlipGas.consumed(100, 200), 0);
        assertEq(MineFlipGas.consumed(200, 100), 100);
    }

    function test_SubBaselineOverrunRollsBackAndBaselineRetryProgresses() public {
        // At 0.25x, the second 12M unit is admitted into the roughly 4M remaining.
        // Its failure must roll back BOTH units; the same queue then succeeds at 1x.
        vm.expectRevert();
        h.run{gas: CALL_GAS}(MineFlipGas.budget(WORK_ALLOWANCE, EXPECTED_MIN_MULTIPLIER, true), 2);
        assertEq(h.completed(), 0);
        assertEq(h.writes(0), 0);
        assertEq(h.writes(SLOTS_PER_UNIT - 1), 0);
        assertEq(h.run{gas: CALL_GAS}(MineFlipGas.budget(WORK_ALLOWANCE, EXPECTED_BASE_MULTIPLIER, true), 2), 1);
        assertEq(h.writes(SLOTS_PER_UNIT), 0, "unprocessed unit remains available");
    }

    function testFuzz_SubBaselineScaleRoundsUp(uint192 estimate, uint16 rawFactor) public pure {
        uint32 factor = uint32(EXPECTED_MIN_MULTIPLIER + uint256(rawFactor) % (EXPECTED_BASE_MULTIPLIER - EXPECTED_MIN_MULTIPLIER));
        assertEq(MineFlipGas.normalize(factor), factor);
        MineFlipGas.Meter memory meter;
        meter.multiplierBps = factor;
        uint256 scaled = MineFlipGas.scale(meter, estimate);
        uint256 product = uint256(estimate) * factor;
        assertGe(scaled * EXPECTED_BASE_MULTIPLIER, product, "never round admission downward");
        if (scaled != 0) assertLt((scaled - 1) * EXPECTED_BASE_MULTIPLIER, product, "smallest covering integer");
        assertEq(MineFlipGas.scale(meter, type(uint256).max), type(uint256).max);
    }

    function testFuzz_BudgetPreservesFullMultiplierAndFirstBit(uint32 rawFactor, bool first) public view {
        uint32 factor = rawFactor < EXPECTED_MIN_MULTIPLIER ? EXPECTED_MIN_MULTIPLIER : rawFactor;
        uint256 word = MineFlipGas.budget(type(uint256).max, factor, first);
        (uint32 decoded, bool mandatory, uint256 floor) = h.context(word);
        assertEq(decoded, factor);
        assertEq(mandatory, first);
        assertEq(floor, 0, "saturated allowance has no floor");
        assertEq(word & type(uint192).max, type(uint192).max);
    }

    function testFuzz_RejectsOnlyNonzeroFactorsBelowFloor(uint16 rawFactor) public {
        uint32 factor = uint32(1 + uint256(rawFactor) % (EXPECTED_MIN_MULTIPLIER - 1));
        vm.expectRevert(MineFlipGas.InvalidGasMultiplier.selector);
        h.normalize(factor);
        assertEq(h.normalize(0), EXPECTED_BASE_MULTIPLIER);
        assertEq(h.normalize(EXPECTED_MIN_MULTIPLIER), EXPECTED_MIN_MULTIPLIER);
        assertEq(h.normalize(type(uint32).max), type(uint32).max);
    }

}
