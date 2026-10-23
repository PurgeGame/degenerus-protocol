// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;
import {Test} from "forge-std/Test.sol";
import {NativeFailureExport} from "../helpers/NativeFailureExport.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {BoundedCall} from "../../contracts/libraries/BoundedCall.sol";

contract P7Dependency {
    uint256 public marker;
    fallback() external payable {
        (uint256 mode, uint256 factor) = abi.decode(msg.data, (uint256, uint256));
        if (mode == 0) assembly ("memory-safe") { for {} 1 {} {} }
        if (mode == 1) revert("refused");
        if (mode == 2) assembly ("memory-safe") { revert(0, 0) }
        if (mode == 3) assembly ("memory-safe") { invalid() }
        // A real storage/access/call workload, followed by synthetic repricing
        // padding proportional to its measured cost. Covers 2x through 5x.
        uint256 begin = gasleft();
        for (uint256 i; i < 8; ++i) {
            this.touch(i + 1);
        }
        uint256 cost = begin - gasleft();
        uint256 extra = cost * (factor - 1) + 1_200_000 * factor;
        begin = gasleft();
        while (begin - gasleft() < extra) {}
        assembly ("memory-safe") { mstore(0, 1) return(0, 32) }
    }
    function touch(uint256 value) external { marker = value; }
}
contract P7ForwardingHarness {
    uint256 public prefix;
    P7Dependency public target = new P7Dependency();
    receive() external payable {}
    function run(uint32 factor, uint256 mode, bool valueCall) external returns (bool ok, uint256 left) {
        // A nonzero ancestor reserve must survive the child even after progress.
        MineFlipGas.Meter memory meter = MineFlipGas.start(MineFlipGas.budget(gasleft() - 250_000 * factor, factor * 10_000, false));
        require(MineFlipGas.canRun(meter, 500_000, 100_000));
        prefix = 1;
        bytes memory result;
        (ok, result) = BoundedCall.callValueRemaining(meter, address(target), valueCall ? 1 : 0,
            50_000, 100_000, abi.encode(mode, uint256(factor)), 32);
        if (ok) require(abi.decode(result, (uint256)) == 1);
        // Exercise a scaled caller tail after success, revert and complete exhaustion.
        uint256 start = gasleft();
        while (start - gasleft() < 60_000 * factor) {}
        prefix = 2;
        MineFlipGas.finish(meter);
        left = gasleft();
        require(left >= meter.floor);
    }
    function invoke(uint32 factor, uint256 mode, bool valueCall) external returns (bool, uint256) {
        (bool ok, bytes memory data) = address(this).call{gas: 4_000_000 * factor}(
            abi.encodeCall(this.run, (factor, mode, valueCall)));
        if (!ok) assembly ("memory-safe") { revert(add(data, 32), mload(data)) }
        (bool succeeded,) = abi.decode(data, (bool, uint256));
        return (succeeded, 0);
    }
}
contract P7ForwardingTest is NativeFailureExport {
    P7ForwardingHarness harness;
    function setUp() public { harness = new P7ForwardingHarness(); vm.deal(address(harness), 1 ether); }
    function testScaledFloorTailAndOverBudgetCallee() public {
        for (uint32 factor = 1; factor <= 5; ++factor) {
            for (uint256 mode; mode <= 4; ++mode) {
                uint256 snap = vm.snapshotState();
                (bool ok,) = harness.invoke(factor, mode, false);
                assertEq(ok, mode == 4); assertEq(harness.prefix(), 2);
                assertTrue(vm.revertToState(snap)); vm.deleteStateSnapshot(snap);
            }
        }
    }
    function testValueCallStipendDoesNotSpendFloor() public {
        for (uint32 factor = 1; factor <= 5; ++factor) {
            uint256 beforeBalance = address(harness.target()).balance;
            (bool ok,) = harness.invoke(factor, 0, true);
            assertFalse(ok); assertEq(address(harness.target()).balance, beforeBalance);
            (ok,) = harness.invoke(factor, 4, true);
            assertTrue(ok);
        }
    }
    function testNativeRepricedFailuresAndSuccess() public {
        for (uint32 factor = 1; factor <= 5; ++factor) for (uint256 mode; mode <= 4; ++mode) {
            _nativeCheckedFixture(string.concat("p7-forward-", vm.toString(factor), "-", vm.toString(mode)),
                address(this), address(harness), abi.encodeCall(harness.invoke, (factor, mode, false)));
        }
    }
}
