// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {NativeFailureExport} from "../helpers/NativeFailureExport.sol";
import {BoundedCall} from "../../contracts/libraries/BoundedCall.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";

contract ForwardedCallHarness {
    uint256 public marker;
    uint256 public prefix;

    function available() external view returns (uint256) { return gasleft(); }

    function readGas(uint256 minimum, uint256 reserve) external view returns (uint256 supplied) {
        (bool ok, uint256 word) = BoundedCall.staticWordRemaining(address(this), minimum, reserve,
            abi.encodeCall(this.available, ()));
        require(ok);
        return word;
    }

    function callGas(uint256 minimum, uint256 reserve) external returns (uint256 supplied) {
        (bool ok, bytes memory data) = BoundedCall.callRemaining(address(this), minimum, reserve,
            abi.encodeCall(this.available, ()), 32);
        require(ok);
        return abi.decode(data, (uint256));
    }

    function child(uint8 mode) external {
        require(msg.sender == address(this));
        marker = 0; // Refill-sensitive: parent created this slot in this transaction.
        if (mode == 1) revert("plain refusal");
        if (mode == 2) assembly ("memory-safe") { revert(0, 0) }
        if (mode == 3) assembly ("memory-safe") { invalid() }
        if (mode == 4) assembly ("memory-safe") { for {} 1 {} {} }
        if (mode == 5) {
            this.child(0);
            revert("intermediary refusal");
        }
        if (mode == 6) assembly ("memory-safe") {
            let p := mload(64)
            mstore(p, 1)
            revert(p, 65536)
        }
    }

    function scenario(uint8 mode) external returns (bool ok, uint256 retained) {
        prefix = 1;
        marker = 1;
        (ok,) = BoundedCall.callRemaining(address(this), 50_000, 100_000,
            abi.encodeCall(this.child, (mode)), 0);
        // Admission is before the call; this is only a test assertion about the
        // promised tail, never a failure classification used by production code.
        require(gasleft() >= 80_000, "tail reserve lost");
        retained = marker;
        prefix = 2;
    }

    function probe(uint8 mode, uint256 supplied) external returns (bool, uint256) {
        // Test-only child boundary: make exhaustion finite even when the fixture
        // exporter itself runs with the very large Foundry transaction limit.
        (bool ok, bytes memory result) = address(this).call{gas: supplied}(abi.encodeCall(this.scenario, (mode)));
        if (!ok) assembly ("memory-safe") { revert(add(result, 32), mload(result)) }
        return abi.decode(result, (bool, uint256));
    }
}

contract ForwardedCallTest is NativeFailureExport {
    ForwardedCallHarness private harness;
    function setUp() public { harness = new ForwardedCallHarness(); }

    function test_TrustedCallsForwardBeyondOldCapAndScaleWithTransaction() public {
        uint256 low = harness.callGas{gas: 2_000_000}(500_000, 100_000);
        uint256 high = harness.callGas{gas: 4_000_000}(500_000, 100_000);
        assertGt(low, 1_500_000); assertGt(high, low + 1_800_000);
        low = harness.readGas{gas: 2_000_000}(50_000, 100_000);
        high = harness.readGas{gas: 4_000_000}(50_000, 100_000);
        assertGt(low, 1_500_000); assertGt(high, low + 1_800_000);
    }

    function test_BelowFloorIsAdmissionFailure() public {
        vm.expectRevert(MineFlipGas.InsufficientExecutionGas.selector);
        harness.callGas{gas: 600_000}(500_000, 100_000);
        vm.expectRevert(MineFlipGas.InsufficientExecutionGas.selector);
        harness.readGas{gas: 150_000}(50_000, 100_000);
    }

    function test_RefillAndAllFailuresPreservePrefixAndTail() public {
        for (uint8 mode; mode <= 6; ++mode) {
            uint256 snapshot = vm.snapshotState();
            (bool ok, uint256 retained) = harness.probe(mode, 2_000_000);
            assertEq(ok, mode == 0);
            assertEq(retained, mode == 0 ? 0 : 1);
            assertEq(harness.prefix(), 2);
            require(vm.revertToState(snapshot));
            vm.deleteStateSnapshot(snapshot);
        }
    }

    function test_ExhaustionAtTwoBudgetsIsRetryable() public {
        for (uint256 supplied = 400_000; supplied <= 2_000_000; supplied += 1_600_000) {
            (bool ok, uint256 retained) = harness.probe(4, supplied);
            assertFalse(ok); assertEq(retained, 1); assertEq(harness.prefix(), 2);
        }
    }

    function test_NativeFixtures() public {
        _nativeCheckedFixture("remaining-low", address(this), address(harness),
            abi.encodeCall(harness.probe, (uint8(4), 400_000)));
        for (uint8 mode; mode <= 6; ++mode) {
            _nativeCheckedFixture(string.concat("remaining-", vm.toString(mode)), address(this), address(harness),
                abi.encodeCall(harness.probe, (mode, 2_000_000)));
        }
    }
}
