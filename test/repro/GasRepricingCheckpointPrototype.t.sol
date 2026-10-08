// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";

/// @notice Exploratory liveness mechanism, NOT a replacement production dispatcher.
/// @dev Extra fresh writes simulate underestimated work by causing actual EVM OOG.
///      This does not emulate Glamsterdam's gas schedule or state-gas reservoir.
///      Every route executes the same next canonical item. Caller controls only
///      throughput and child gas, never item identity, entropy, or skipping.
contract GasRepricingCheckpointPrototype {
    error OnlySelf();
    error NoWork();
    error InvariantFailure();
    error StepFailure(bytes4 selector);
    error BadResult();
    error InvalidMultiplier();

    uint256 public immutable total;
    uint256 public cursor;
    bytes32 public digest;
    mapping(uint256 => bytes32) public outcomes;
    mapping(uint256 => uint256) public extraWrites;
    mapping(uint256 => uint256) public scratch;
    uint256 public faultAt = type(uint256).max;

    constructor(uint256 count) { total = count; }

    // Fixture controls only; these are not proposed public production parameters.
    function setCost(uint256 item, uint256 writes) external { extraWrites[item] = writes; }
    function setFault(uint256 item) external { faultAt = item; }

    /// @dev Models today's same-frame loop with an out-of-date admission estimate.
    function runEstimated(uint256 maxSteps, uint256 allowance) external {
        MineFlipGas.Meter memory meter = MineFlipGas.start(allowance);
        for (uint256 n; n < maxSteps && cursor < total; ++n) {
            if (!MineFlipGas.canRun(meter, 100_000, 40_000)) break;
            _next();
        }
        MineFlipGas.finish(meter);
    }

    /// @dev Direct progress route: exactly one canonical unit, no calibrated gas
    ///      admission or post-work metering/reward tail. The caller funds this tx.
    function runOne() external { _next(); }

    /// @dev Count-bounded batch: one ordinary call can contain many canonical
    ///      items. The current node estimates the gas for this exact workload;
    ///      no gas schedule, gasleft delta, or per-item gas estimate is consulted.
    ///      OOG reverts this batch, which can be retried with more gas or fewer
    ///      items. This path demonstrates progress availability, not guaranteed
    ///      success of underfunded or stale-estimate transactions.
    function runCounted(uint256 maxSteps) external returns (uint256 completed) {
        while (completed < maxSteps && cursor < total) {
            _next();
            ++completed;
        }
    }

    /// @dev Greedy batch with caller-supplied next-unit and return estimates.
    ///      The loop still uses all safely admissible execution gas. Incorrect
    ///      estimates affect only the caller's attempt, never stored calibration.
    ///      Real workers need distinct bounds for their different atomic actions,
    ///      including every nested completion tail and mandatory external call.
    ///      This uses current gasleft directly; no monotonic-spending assumption.
    function runCalibrated(uint256 nextMax, uint256 returnReserve)
        external returns (uint256 completed)
    {
        uint256 required = nextMax + returnReserve;
        while (cursor < total && gasleft() >= required) {
            _next();
            ++completed;
        }
    }

    /// @dev Proposed simpler policy: estimates cannot refuse the first canonical
    ///      unit. After it completes, scaled bounds admit additional greedy work.
    ///      A bad estimate may OOG and revert this entire call; it cannot skip an
    ///      item or persist a bad multiplier. Real nested workers must propagate
    ///      the first-unit exemption down to the actual resumable operation.
    function runMultiplied(uint32 multiplierBps) external returns (uint256 completed) {
        if (multiplierBps < 10_000) revert InvalidMultiplier();
        _next();
        completed = 1;
        // Scale the operation, return tail and admission overhead together.
        // uint32 bounds the caller input; multiplication cannot overflow here.
        uint256 required = ((100_000 + 40_000 + 2_000) * uint256(multiplierBps) + 9_999) / 10_000;
        while (cursor < total && gasleft() >= required) {
            _next();
            ++completed;
        }
    }

    /// @dev Illustrates preserving a successful prefix after the next child OOG.
    ///      A production batch may contain several canonical items per child.
    ///      The quarter retained here is a prototype policy, not a universal proof
    ///      of sufficient parent gas under arbitrary future EVM repricing.
    function runIsolated(uint256 maxSteps, uint256 childGas)
        external returns (uint256 completed, bool stopped)
    {
        for (uint256 n; n < maxSteps && cursor < total; ++n) {
            uint256 available = gasleft();
            if (childGas > available - available / 4) return (completed, true);

            bytes memory data = abi.encodeCall(this.executeNext, ());
            bool ok;
            uint256 size;
            bytes32 answer;
            // Copy at most one word, including on failure. A failed child must
            // not consume the parent's reserve through unbounded returndata copy.
            assembly ("memory-safe") {
                ok := call(childGas, address(), 0, add(data, 32), mload(data), 0, 0)
                size := returndatasize()
                let count := size
                if gt(count, 32) { count := 32 }
                mstore(0, 0)
                returndatacopy(0, 0, count)
                answer := mload(0)
            }
            if (!ok) {
                // Empty data is not proof of OOG. It simply stops on this same
                // item; nothing is skipped or certified complete on a failure.
                if (size == 0) return (completed, true);
                revert StepFailure(bytes4(answer));
            }
            if (size != 32 || uint256(answer) != 1) revert BadResult();
            ++completed;
        }
    }

    function executeNext() external returns (bool) {
        if (msg.sender != address(this)) revert OnlySelf();
        _next();
        return true;
    }

    function _next() private {
        uint256 item = cursor;
        if (item == total) revert NoWork();
        if (item == faultAt) revert InvariantFailure();
        uint256 writes = extraWrites[item];
        for (uint256 j; j < writes; ++j) scratch[item * 1_000 + j] = j + 1;
        bytes32 outcome = keccak256(abi.encode(uint256(0xC0FFEE), item));
        outcomes[item] = outcome;
        digest = keccak256(abi.encode(digest, outcome));
        cursor = item + 1;
    }
}

contract GasRepricingCheckpointPrototypeTest is Test {
    function test_MultiplierCannotRefuseFirstCanonicalChunk() public {
        GasRepricingCheckpointPrototype h = new GasRepricingCheckpointPrototype(3);
        assertEq(h.runMultiplied{gas: 500_000}(50_000), 1,
            "fivefold estimate exceeds supplied gas but actual first unit fits");
        assertEq(h.runMultiplied{gas: 500_000}(type(uint32).max), 1,
            "even the largest multiplier cannot refuse the next first unit");
        assertEq(h.cursor(), 2);
        assertEq(h.runMultiplied{gas: 500_000}(10_000), 1);
        vm.expectRevert(GasRepricingCheckpointPrototype.NoWork.selector);
        h.runMultiplied(10_000);
    }

    function test_MultiplierRetainsGreedyLargeBatching() public {
        GasRepricingCheckpointPrototype small = new GasRepricingCheckpointPrototype(100);
        GasRepricingCheckpointPrototype large = new GasRepricingCheckpointPrototype(100);
        uint256 smallCount = small.runMultiplied{gas: 500_000}(10_000);
        uint256 largeCount = large.runMultiplied{gas: 2_000_000}(10_000);
        assertGt(smallCount, 1);
        assertGt(largeCount, smallCount * 3);
        assertLt(largeCount, 100);
    }

    function test_BadMultiplierRollsBackAttemptAndAnotherCallerResumes() public {
        GasRepricingCheckpointPrototype h = new GasRepricingCheckpointPrototype(20);
        GasRepricingCheckpointPrototype referenceRun = new GasRepricingCheckpointPrototype(20);
        for (uint256 i; i < 20; ++i) h.setCost(i, 12);
        assertEq(h.runMultiplied{gas: 600_000}(50_000), 1);
        bytes32 prefix = h.digest();
        (bool ok,) = address(h).call{gas: 1_100_000}(abi.encodeCall(h.runMultiplied, (10_000)));
        assertFalse(ok, "underestimated continuation consumes the attempt's gas");
        assertEq(h.cursor(), 1, "previous successful call survives, failed attempt rolls back");
        assertEq(h.digest(), prefix);
        assertEq(h.outcomes(1), bytes32(0));
        assertEq(h.scratch(1_000), 0);
        vm.prank(address(0xBEEF));
        assertGt(h.runMultiplied{gas: 2_000_000}(50_000), 1);
        while (h.cursor() < 20) h.runMultiplied{gas: 2_000_000}(50_000);
        referenceRun.runCounted{gas: 1_000_000}(20);
        assertEq(h.digest(), referenceRun.digest());
    }

    function test_MultiplierCannotMakeUnderfundedFirstChunkCommit() public {
        GasRepricingCheckpointPrototype h = new GasRepricingCheckpointPrototype(1);
        h.setCost(0, 60);
        (bool ok,) = address(h).call{gas: 200_000}(abi.encodeCall(h.runMultiplied, (50_000)));
        assertFalse(ok);
        assertEq(h.cursor(), 0);
        assertEq(h.scratch(0), 0);
        assertEq(h.runMultiplied{gas: 2_000_000}(50_000), 1);
    }

    function test_MultiplierDoesNotSwallowSemanticFailure() public {
        GasRepricingCheckpointPrototype h = new GasRepricingCheckpointPrototype(3);
        h.setFault(1);
        vm.expectRevert(GasRepricingCheckpointPrototype.InvariantFailure.selector);
        h.runMultiplied{gas: 1_000_000}(10_000);
        assertEq(h.cursor(), 0);
        assertEq(h.outcomes(0), bytes32(0));
    }

    function testFuzz_MultiplierChangesThroughputNotOutcomes(uint32 multiplierSeed, uint8 costSeed) public {
        GasRepricingCheckpointPrototype split = new GasRepricingCheckpointPrototype(9);
        GasRepricingCheckpointPrototype referenceRun = new GasRepricingCheckpointPrototype(9);
        uint32 multiplierBps = uint32(bound(uint256(multiplierSeed), 10_000, type(uint32).max));
        for (uint256 i; i < 9; ++i) split.setCost(i, uint256(costSeed) % 6);
        while (split.cursor() < 9) {
            assertGe(split.runMultiplied{gas: 800_000}(multiplierBps), 1);
        }
        referenceRun.runCounted{gas: 1_000_000}(9);
        assertEq(split.digest(), referenceRun.digest());
        for (uint256 i; i < 9; ++i) assertEq(split.outcomes(i), referenceRun.outcomes(i));
    }

    function test_GreedyCalibrationStillFillsLargeCallerGasBudget() public {
        GasRepricingCheckpointPrototype small = new GasRepricingCheckpointPrototype(100);
        GasRepricingCheckpointPrototype large = new GasRepricingCheckpointPrototype(100);
        uint256 smallCount = small.runCalibrated{gas: 500_000}(100_000, 40_000);
        uint256 largeCount = large.runCalibrated{gas: 2_000_000}(100_000, 40_000);
        assertGt(smallCount, 1, "normal execution remains batched");
        assertGt(largeCount, smallCount * 3, "more gas automatically buys a much larger batch");
        assertLt(largeCount, 100, "fixture stops on gas admission, not empty work");
        small.runCounted{gas: 4_000_000}(100);
        large.runCounted{gas: 4_000_000}(100);
        assertEq(small.digest(), large.digest());
    }

    function test_GreedyCalibrationAdaptsAfterCostsInvalidateOldEstimate() public {
        GasRepricingCheckpointPrototype h = new GasRepricingCheckpointPrototype(20);
        GasRepricingCheckpointPrototype referenceRun = new GasRepricingCheckpointPrototype(20);
        for (uint256 i; i < 20; ++i) h.setCost(i, 12);
        (bool ok,) = address(h).call{gas: 1_100_000}(
            abi.encodeCall(h.runCalibrated, (100_000, 40_000))
        );
        assertFalse(ok, "old per-step estimate allows a fatal next item");
        assertEq(h.cursor(), 0);
        uint256 completed = h.runCalibrated{gas: 1_000_000}(400_000, 40_000);
        assertGt(completed, 1, "corrected estimate preserves useful batching");
        assertLt(completed, 20);
        while (h.cursor() < 20) {
            assertGt(h.runCalibrated{gas: 2_000_000}(400_000, 40_000), 0);
        }
        referenceRun.runCounted{gas: 1_000_000}(20);
        assertEq(h.digest(), referenceRun.digest());
    }

    function test_OverstatedCalibrationCannotPersistentlyBlockOtherCallers() public {
        GasRepricingCheckpointPrototype h = new GasRepricingCheckpointPrototype(20);
        assertEq(h.runCalibrated{gas: 1_000_000}(100_000_000, 40_000), 0);
        assertEq(h.cursor(), 0);
        vm.prank(address(0xBEEF));
        assertGt(h.runCalibrated{gas: 1_000_000}(100_000, 40_000), 1);
    }

    function test_CountBudgetKeepsLargeBatchByIncreasingTransactionGas() public {
        GasRepricingCheckpointPrototype cheap = new GasRepricingCheckpointPrototype(24);
        GasRepricingCheckpointPrototype expensive = new GasRepricingCheckpointPrototype(24);
        for (uint256 i; i < 24; ++i) expensive.setCost(i, 12);
        assertEq(cheap.runCounted{gas: 1_000_000}(24), 24);
        (bool ok,) = address(expensive).call{gas: 1_000_000}(
            abi.encodeCall(expensive.runCounted, (24))
        );
        assertFalse(ok, "old supplied gas no longer funds this workload");
        assertEq(expensive.cursor(), 0);
        assertEq(expensive.runCounted{gas: 12_000_000}(24), 24,
            "same large batch succeeds without changing contract estimates");
        assertEq(expensive.digest(), cheap.digest());
    }

    function test_CountBudgetCanChangeBatchSizeWithinSameTransactionGas() public {
        GasRepricingCheckpointPrototype h = new GasRepricingCheckpointPrototype(6);
        GasRepricingCheckpointPrototype referenceRun = new GasRepricingCheckpointPrototype(6);
        for (uint256 i; i < 6; ++i) h.setCost(i, 60);
        (bool ok,) = address(h).call{gas: 4_000_000}(abi.encodeCall(h.runCounted, (6)));
        assertFalse(ok);
        assertEq(h.cursor(), 0);
        for (uint256 i; i < 3; ++i) assertEq(h.runCounted{gas: 4_000_000}(2), 2);
        referenceRun.runCounted{gas: 1_000_000}(6);
        assertEq(h.cursor(), 6);
        assertEq(h.digest(), referenceRun.digest());
    }

    function test_CountBudgetAdaptsToCostChangeAfterPriorBatchCommitted() public {
        GasRepricingCheckpointPrototype h = new GasRepricingCheckpointPrototype(12);
        GasRepricingCheckpointPrototype referenceRun = new GasRepricingCheckpointPrototype(12);
        assertEq(h.runCounted{gas: 1_000_000}(6), 6);
        bytes32 prefix = h.digest();
        for (uint256 i = 6; i < 12; ++i) h.setCost(i, 12);
        (bool ok,) = address(h).call{gas: 1_000_000}(abi.encodeCall(h.runCounted, (6)));
        assertFalse(ok);
        assertEq(h.cursor(), 6, "failed batch does not affect prior transaction");
        assertEq(h.digest(), prefix);
        assertEq(h.runCounted{gas: 3_000_000}(6), 6);
        referenceRun.runCounted{gas: 1_000_000}(12);
        assertEq(h.digest(), referenceRun.digest());
    }

    function test_StaleEstimateOogRollsBackEarlierSameFrameCheckpoints() public {
        GasRepricingCheckpointPrototype h = new GasRepricingCheckpointPrototype(2);
        h.setCost(1, 60);
        (bool ok,) = address(h).call{gas: 700_000}(
            abi.encodeCall(h.runEstimated, (2, 650_000))
        );
        assertFalse(ok, "second item exhausts the enclosing call");
        assertEq(h.cursor(), 0, "earlier SSTORE checkpoint rolled back too");
        assertEq(h.outcomes(0), bytes32(0));
    }

    function test_ChildOogPreservesPrefixAndRollsBackOnlyFailedItem() public {
        GasRepricingCheckpointPrototype h = new GasRepricingCheckpointPrototype(2);
        h.setCost(1, 60);
        (uint256 done, bool stopped) = h.runIsolated{gas: 750_000}(2, 200_000);
        assertEq(done, 1);
        assertTrue(stopped);
        assertEq(h.cursor(), 1);
        assertTrue(h.outcomes(0) != bytes32(0));
        assertEq(h.outcomes(1), bytes32(0));
        assertEq(h.scratch(1_000), 0, "failed child storage was rolled back");
        h.runOne{gas: 2_000_000}();
        assertEq(h.cursor(), 2, "larger one-step call resumes the same item");
        assertEq(h.scratch(1_059), 60);
    }

    function test_FailedFirstItemDoesNotPretendToMakeProgressOrSkip() public {
        GasRepricingCheckpointPrototype h = new GasRepricingCheckpointPrototype(2);
        h.setCost(0, 60);
        (uint256 done, bool stopped) = h.runIsolated{gas: 750_000}(2, 200_000);
        assertEq(done, 0);
        assertTrue(stopped);
        assertEq(h.cursor(), 0);
        h.runOne{gas: 2_000_000}();
        assertEq(h.cursor(), 1);
        assertEq(h.outcomes(1), bytes32(0));
    }

    function test_OneStepIgnoresStaleAdmissionAllowance() public {
        GasRepricingCheckpointPrototype h = new GasRepricingCheckpointPrototype(1);
        h.runEstimated{gas: 500_000}(1, 120_000);
        assertEq(h.cursor(), 0, "compiled admission refuses even funded caller");
        h.runOne{gas: 150_000}();
        assertEq(h.cursor(), 1);
    }

    function test_LargeMandatoryGroupCanFailWhileEveryOneStepFits() public {
        GasRepricingCheckpointPrototype h = new GasRepricingCheckpointPrototype(6);
        for (uint256 i; i < 6; ++i) h.setCost(i, 60);
        (bool ok,) = address(h).call{gas: 4_000_000}(
            abi.encodeCall(h.runEstimated, (6, 3_900_000))
        );
        assertFalse(ok);
        assertEq(h.cursor(), 0);
        for (uint256 i; i < 6; ++i) {
            h.runOne{gas: 2_000_000}();
            assertEq(h.cursor(), i + 1);
        }
    }

    function test_SemanticFailureBubblesWithoutSkippingTheItem() public {
        GasRepricingCheckpointPrototype h = new GasRepricingCheckpointPrototype(2);
        h.setFault(1);
        vm.expectRevert(abi.encodeWithSelector(
            GasRepricingCheckpointPrototype.StepFailure.selector,
            GasRepricingCheckpointPrototype.InvariantFailure.selector
        ));
        h.runIsolated{gas: 750_000}(2, 200_000);
        assertEq(h.cursor(), 0, "semantic failure still fails loudly");
        h.runOne{gas: 150_000}();
        vm.expectRevert(GasRepricingCheckpointPrototype.InvariantFailure.selector);
        h.runOne{gas: 150_000}();
        assertEq(h.cursor(), 1);
    }

    function test_InternalTrampolineRejectsExternalCalls() public {
        GasRepricingCheckpointPrototype h = new GasRepricingCheckpointPrototype(1);
        vm.expectRevert(GasRepricingCheckpointPrototype.OnlySelf.selector);
        h.executeNext();
        assertEq(h.cursor(), 0);
    }

    function test_AtomicStepStillNeedsEnoughGas() public {
        GasRepricingCheckpointPrototype h = new GasRepricingCheckpointPrototype(1);
        h.setCost(0, 60);
        (bool ok,) = address(h).call{gas: 200_000}(abi.encodeCall(h.runOne, ()));
        assertFalse(ok, "no design can execute an underfunded indivisible step");
        assertEq(h.cursor(), 0);
        h.runOne{gas: 2_000_000}();
        assertEq(h.cursor(), 1);
    }

    function testFuzz_PartitionAndCostDoNotChangeCanonicalOutcomes(uint8 splitSeed, uint8 costSeed) public {
        GasRepricingCheckpointPrototype batched = new GasRepricingCheckpointPrototype(9);
        GasRepricingCheckpointPrototype split = new GasRepricingCheckpointPrototype(9);
        uint256 writes = uint256(costSeed) % 8;
        for (uint256 i; i < 9; ++i) {
            batched.setCost(i, writes);
            split.setCost(i, writes);
        }
        (uint256 done, bool stopped) = batched.runIsolated{gas: 5_000_000}(9, 400_000);
        assertEq(done, 9);
        assertFalse(stopped);
        uint256 chunk = uint256(splitSeed) % 4 + 1;
        while (split.cursor() < 9) {
            if (split.cursor() % 2 == 0) split.runOne{gas: 400_000}();
            else split.runIsolated{gas: 2_500_000}(chunk, 400_000);
        }
        assertEq(split.cursor(), batched.cursor());
        assertEq(split.digest(), batched.digest());
        for (uint256 i; i < 9; ++i) assertEq(split.outcomes(i), batched.outcomes(i));
    }
}
