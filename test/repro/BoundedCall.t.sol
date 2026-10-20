// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {BoundedCall} from "../../contracts/libraries/BoundedCall.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";

contract BoundedCallTarget {
    fallback() external payable {
        assembly ("memory-safe") {
            switch calldataload(0)
            case 1 { revert(0, 0) }
            case 2 { for {} 1 {} {} }
            case 3 {
                mstore(0, 42)
                return(0, 31)
            }
            case 4 {
                let ptr := mload(64)
                mstore(ptr, 42)
                return(ptr, 32768)
            }
            case 5 {
                mstore(0, calldataload(32))
                revert(0, 4)
            }
            case 6 {
                mstore(0, 2)
                return(0, 32)
            }
            case 7 {
                sstore(0, 1)
                return(0, 0)
            }
            case 8 {
                mstore(0, shl(224, 0xdeadbeef))
                return(0, 4)
            }
            case 9 { return(0, 0) }
            case 10 {
                mstore(0, gas())
                return(0, 32)
            }
            case 11 {
                mstore(0, 1)
                return(0, 32)
            }
            case 12 {
                let ptr := mload(64)
                mstore(ptr, 42)
                revert(ptr, 32768)
            }
            default {
                mstore(0, 42)
                return(0, 32)
            }
        }
    }
}

contract BoundedCallHarness {
    receive() external payable {}

    function run(address target, uint256 value, uint256 budget, bytes memory input, uint256 expected)
        external returns (bool, bytes memory)
    {
        return BoundedCall.call(target, value, budget, input, expected);
    }

    function read(address target, uint256 budget, bytes memory input, uint256 expected)
        external view returns (bool, bytes memory)
    {
        return BoundedCall.staticcall(target, budget, input, expected);
    }

    function flag(address target, uint256 budget, bytes memory input) external returns (bool) {
        return BoundedCall.callBool(target, budget, input);
    }

    function word(address target, uint256 budget, bytes memory input) external view returns (bool, uint256) {
        return BoundedCall.staticWord(target, budget, input);
    }

    function firstUnit(address target, uint256 budget) external returns (bool, bytes memory) {
        MineFlipGas.Meter memory meter = MineFlipGas.start(MineFlipGas.budget(0, 10_000, true));
        require(MineFlipGas.canRun(meter, budget, 0));
        return BoundedCall.call(target, 0, budget, abi.encode(uint256(1)), 32);
    }
}

contract BoundedCallTest is Test {
    uint256 private constant BUDGET = 100_000;
    BoundedCallHarness private harness;
    BoundedCallTarget private target;

    function setUp() public {
        harness = new BoundedCallHarness();
        target = new BoundedCallTarget();
        vm.deal(address(harness), 1 ether);
    }

    function _call(uint256 mode) private returns (bool, bytes memory) {
        return harness.run(address(target), 0, BUDGET, abi.encode(mode), 32);
    }

    function _read(uint256 mode) private view returns (bool, bytes memory) {
        return harness.read(address(target), BUDGET, abi.encode(mode), 32);
    }

    function _failure(uint256 mode) private {
        (bool ok, bytes memory output) = _call(mode);
        assertFalse(ok);
        assertEq(output.length, 0);
        (ok, output) = _read(mode);
        assertFalse(ok);
        assertEq(output.length, 0);
    }

    function testExactWord() public {
        (bool ok, bytes memory output) = _call(0);
        assertTrue(ok);
        assertEq(abi.decode(output, (uint256)), 42);
        (ok, output) = _read(0);
        assertTrue(ok);
        assertEq(abi.decode(output, (uint256)), 42);
    }

    function testEmptyRevertIsFailure() public { _failure(1); }
    function testExhaustionIsFailure() public { _failure(2); }
    function testShortReturnIsFailure() public { _failure(3); }
    function testEmptyReturnIsFailure() public { _failure(9); }
    function testOversizedRevertIsFailure() public { _failure(12); }

    function testOversizedSuccessCopiesOnlyPrefix() public {
        (bool ok, bytes memory output) = _call(4);
        assertTrue(ok);
        assertEq(output.length, 32);
        assertEq(abi.decode(output, (uint256)), 42);
        (ok, output) = _read(4);
        assertTrue(ok);
        assertEq(output.length, 32);
        assertEq(abi.decode(output, (uint256)), 42);
    }

    function testSpoofedMeteringErrorsAreFailures() public {
        bytes4[3] memory selectors = [
            MineFlipGas.InsufficientExecutionGas.selector,
            MineFlipGas.WorkGasBound.selector,
            MineFlipGas.EmptyRevert.selector
        ];
        for (uint256 i; i < selectors.length; ++i) {
            bytes memory input = abi.encode(uint256(5), selectors[i]);
            (bool ok, bytes memory output) = harness.run(address(target), 0, BUDGET, input, 32);
            assertFalse(ok);
            assertEq(output.length, 0);
            (ok, output) = harness.read(address(target), BUDGET, input, 32);
            assertFalse(ok);
            assertEq(output.length, 0);
        }
    }

    function testBoolRejectsNonCanonicalAndAcceptsOne() public {
        assertFalse(harness.flag(address(target), BUDGET, abi.encode(uint256(6))));
        assertFalse(harness.flag(address(target), BUDGET, abi.encode(uint256(1))));
        assertTrue(harness.flag(address(target), BUDGET, abi.encode(uint256(11))));
    }

    function testStaticWordFailureReadsZero() public {
        (bool ok, uint256 word) = harness.word(address(target), BUDGET, abi.encode(uint256(3)));
        assertFalse(ok);
        assertEq(word, 0);
    }

    function testStaticStateChangeFails() public view {
        (bool ok, bytes memory output) = harness.read(address(target), BUDGET, abi.encode(uint256(7)), 0);
        assertFalse(ok);
        assertEq(output.length, 0);
    }

    function testSelectorCopiesFourBytes() public view {
        (bool ok, bytes memory output) = harness.read(address(target), BUDGET, abi.encode(uint256(8)), 4);
        assertTrue(ok);
        assertEq(output, hex"deadbeef");
    }

    function testNoReturnCall() public {
        (bool ok, bytes memory output) = harness.run(address(target), 0, BUDGET, abi.encode(uint256(9)), 0);
        assertTrue(ok);
        assertEq(output.length, 0);
    }

    function testUnderfundedCallRevertsBeforeFailureBranch() public {
        bytes memory input = abi.encodeCall(harness.run, (address(target), 0, BUDGET, abi.encode(uint256(1)), 32));
        (bool ok, bytes memory output) = address(harness).call{gas: BUDGET + 5_000}(input);
        assertFalse(ok);
        assertEq(output, abi.encodeWithSelector(MineFlipGas.InsufficientExecutionGas.selector));
    }

    function testUnderfundedStaticcallRevertsBeforeFailureBranch() public view {
        bytes memory input = abi.encodeCall(harness.read, (address(target), BUDGET, abi.encode(uint256(1)), 32));
        (bool ok, bytes memory output) = address(harness).staticcall{gas: BUDGET + 5_000}(input);
        assertFalse(ok);
        assertEq(output, abi.encodeWithSelector(MineFlipGas.InsufficientExecutionGas.selector));
    }

    function testFirstUnitCannotBypassAdmission() public {
        (bool ok, bytes memory output) = address(harness).call{gas: BUDGET + 5_000}(
            abi.encodeCall(harness.firstUnit, (address(target), BUDGET))
        );
        assertFalse(ok);
        assertEq(output, abi.encodeWithSelector(MineFlipGas.InsufficientExecutionGas.selector));
    }

    function testValueTransferUsesSameFixedBudget() public {
        (bool ok, bytes memory output) = harness.run(address(target), 0, BUDGET, abi.encode(uint256(10)), 32);
        assertTrue(ok);
        uint256 noValueGas = abi.decode(output, (uint256));
        (ok, output) = harness.run(address(target), 1, BUDGET, abi.encode(uint256(10)), 32);
        assertTrue(ok);
        assertEq(abi.decode(output, (uint256)), noValueGas);
        assertEq(address(target).balance, 1);
    }

    function testValueTransferColdNewAccount() public {
        address recipient = address(0x12345678);
        (bool ok, ) = harness.run(recipient, 1, BUDGET, "", 0);
        assertTrue(ok);
        assertEq(recipient.balance, 1);
    }

    function testUnderfundedValueCallRevertsBeforeTransfer() public {
        bytes memory input = abi.encodeCall(harness.run, (address(target), 1, BUDGET, abi.encode(uint256(1)), 32));
        (bool ok, bytes memory output) = address(harness).call{gas: BUDGET + 35_000}(input);
        assertFalse(ok);
        assertEq(output, abi.encodeWithSelector(MineFlipGas.InsufficientExecutionGas.selector));
        assertEq(address(target).balance, 0);
    }

    function testFuzzAdmittedCallGetsFullBudget(uint32 supplied) public {
        uint256 callGas = bound(supplied, BUDGET - 5_000, BUDGET + 80_000);
        (bool referenceOk, bytes memory referenceOutput) = _call(10);
        assertTrue(referenceOk);
        bytes memory input = abi.encodeCall(harness.run, (address(target), 0, BUDGET, abi.encode(uint256(10)), 32));
        (bool ok, bytes memory output) = address(harness).call{gas: callGas}(input);
        if (!ok) {
            assertEq(output, abi.encodeWithSelector(MineFlipGas.InsufficientExecutionGas.selector));
            return;
        }
        (bool callOk, bytes memory result) = abi.decode(output, (bool, bytes));
        assertTrue(callOk);
        assertEq(result, referenceOutput);
    }
}
