// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";

/// @notice Synthetic current-Osaka benchmark, not a production dispatcher.
/// @dev Models a fresh-slot workload with two state words cached until a batch
///      completes. Chunk size controls boundary frequency ONLY for measurement;
///      production scheduling would choose work from live state and gasleft().
contract GasRepricingBoundaryFixture {
    error OnlySelf();
    error InvalidResult();
    error WorkerFailure(bytes4 selector);
    error InvalidScale();

    uint256 public cursor = 1;
    bytes32 public digest = bytes32(uint256(1));
    mapping(uint256 => bytes32) public outcomes;
    uint256 public constant END = 401;

    function direct(uint256 nextMax, uint256 tail) external returns (uint256) {
        return _work(400, nextMax, tail);
    }

    function multiplied(uint256 nextMax, uint256 tail, uint256 multiplierBps) external returns (uint256) {
        if (multiplierBps < 10_000) revert InvalidScale();
        uint256 scaledNext = (nextMax * multiplierBps + 9999) / 10_000;
        uint256 scaledTail = (tail * multiplierBps + 9999) / 10_000;
        return _work(400, scaledNext, scaledTail);
    }

    function protectedBatches(uint256 chunkSize, uint256 nextMax, uint256 tail)
        external
        returns (uint256 completed, uint256 calls)
    {
        bytes memory data = abi.encodeCall(this.executeBatch, (chunkSize, nextMax, tail));
        while (cursor < END) {
            uint256 available = gasleft();
            // Benchmark reserve only, not a future-schedule liveness guarantee.
            if (available < 100_000) break;
            uint256 childGas = available - 50_000;
            bool ok;
            uint256 size;
            bytes32 answer;
            assembly ("memory-safe") {
                ok := call(childGas, address(), 0, add(data, 32), mload(data), 0, 0)
                size := returndatasize()
                let count := size
                if gt(count, 32) { count := 32 }
                mstore(0, 0)
                returndatacopy(0, 0, count)
                answer := mload(0)
            }
            ++calls;
            if (!ok) {
                if (size == 0) break;
                revert WorkerFailure(bytes4(answer));
            }
            if (size != 32 || uint256(answer) > chunkSize) revert InvalidResult();
            if (answer == bytes32(0)) break;
            completed += uint256(answer);
        }
    }

    function executeBatch(uint256 count, uint256 nextMax, uint256 tail) external returns (uint256) {
        if (msg.sender != address(this)) revert OnlySelf();
        return _work(count, nextMax, tail);
    }

    function _work(uint256 count, uint256 nextMax, uint256 tail) private returns (uint256 completed) {
        uint256 item = cursor;
        bytes32 running = digest;
        uint256 required = nextMax + tail;
        while (completed < count && item < END && gasleft() >= required) {
            // Reuse scratch space so resetting child memory does not artificially
            // save the quadratic cost of an ever-growing memory allocation.
            assembly ("memory-safe") {
                mstore(0, running)
                mstore(32, item)
                running := keccak256(0, 64)
            }
            outcomes[item] = running;
            ++item;
            ++completed;
        }
        if (completed != 0) {
            cursor = item;
            digest = running;
        }
    }
}

contract GasRepricingBoundaryGasTest is Test {
    GasRepricingBoundaryFixture private flat;
    GasRepricingBoundaryFixture private protectedRun;

    function setUp() public {
        // Setup precedes the measured test transaction, making initialized
        // checkpoint words nonzero original values rather than dirty slots.
        flat = new GasRepricingBoundaryFixture();
        protectedRun = new GasRepricingBoundaryFixture();
    }

    function test_Gas_OneProtectedBatch() public {
        _compare(400, 1);
    }

    function test_Gas_FourProtectedBatches() public {
        _compare(100, 4);
    }

    function test_Gas_EightProtectedBatches() public {
        _compare(50, 8);
    }

    function test_Gas_SixteenProtectedBatches() public {
        _compare(25, 16);
    }

    function test_Gas_MultiplierOne() public {
        _compareMultiplier(10_000);
    }

    function test_Gas_MultiplierFive() public {
        _compareMultiplier(50_000);
    }

    function _compareMultiplier(uint256 multiplierBps) private {
        vm.cool(address(flat));
        vm.cool(address(protectedRun));
        bytes memory flatData = abi.encodeCall(flat.direct, (40_000, 20_000));
        bytes memory scaledData = abi.encodeCall(protectedRun.multiplied, (40_000, 20_000, multiplierBps));
        (uint256 flatGas, uint256 flatCount,) = _measure(address(flat), flatData);
        (uint256 scaledGas, uint256 scaledCount,) = _measure(address(protectedRun), scaledData);
        assertEq(flatCount, 400);
        assertEq(scaledCount, 400);
        assertEq(flat.digest(), protectedRun.digest());
        emit log_named_uint("multiplier bps", multiplierBps);
        emit log_named_uint("flat execution gas", flatGas);
        emit log_named_uint("scaled execution gas", scaledGas);
        emit log_named_uint("extra gas", scaledGas - flatGas);
    }

    function _compare(uint256 chunkSize, uint256 expectedCalls) private {
        // Reset warmth before measuring first-touch costs.
        vm.cool(address(flat));
        vm.cool(address(protectedRun));

        bytes memory flatData = abi.encodeCall(flat.direct, (40_000, 20_000));
        bytes memory protectedData = abi.encodeCall(protectedRun.protectedBatches, (chunkSize, 40_000, 20_000));
        (uint256 flatGas, uint256 flatCount,) = _measure(address(flat), flatData);
        (uint256 protectedGas, uint256 protectedCount, uint256 calls) = _measure(address(protectedRun), protectedData);

        assertEq(flatCount, 400);
        assertEq(protectedCount, 400);
        assertEq(flat.cursor(), 401);
        assertEq(protectedRun.cursor(), 401);
        assertEq(flat.digest(), protectedRun.digest());
        for (uint256 item = 1; item < 401; ++item) {
            assertEq(flat.outcomes(item), protectedRun.outcomes(item));
        }
        // All successful calls have enough gas to reach their count boundary.
        assertEq(calls, expectedCalls);
        assertGt(protectedGas, flatGas);
        emit log_named_uint("protected batches", expectedCalls);
        emit log_named_uint("flat execution gas", flatGas);
        emit log_named_uint("protected execution gas", protectedGas);
        emit log_named_uint("extra gas", protectedGas - flatGas);
    }

    function _measure(address target, bytes memory data) private returns (uint256 used, uint256 count, uint256 calls) {
        // Calldata allocation and all deployment/assertion costs are excluded.
        // Both paths include the same cold external entry call. Intrinsic tx
        // gas and additional transaction calldata pricing are not measured.
        uint256 beforeGas = gasleft();
        bool ok;
        assembly ("memory-safe") {
            ok := call(15000000, target, 0, add(data, 32), mload(data), 0, 0)
        }
        used = beforeGas - gasleft();
        assembly ("memory-safe") {
            if iszero(lt(returndatasize(), 32)) {
                returndatacopy(0, 0, 32)
                count := mload(0)
                if eq(returndatasize(), 64) {
                    returndatacopy(0, 32, 32)
                    calls := mload(0)
                }
            }
        }
        assertTrue(ok);
    }
}
