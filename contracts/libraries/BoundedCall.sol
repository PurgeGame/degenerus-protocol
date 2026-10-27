// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {MineFlipGas} from "./MineFlipGas.sol";
import {IStETH} from "../interfaces/IStETH.sol";

/// @notice Return-data bounds and retryable gas admission for isolated dependencies.
library BoundedCall {
    uint256 private constant CALL_OVERHEAD = 10_000;
    uint256 private constant VALUE_CALL_OVERHEAD = 45_000;
    // The EVM adds this stipend to a value CALL operand. It is not a policy budget.
    uint256 private constant VALUE_STIPEND = 2_300;

    /// @dev Forward everything above the active meter floor and scaled caller tail.
    /// The scaled minimum is admission only. Never classify failures using gasleft.
    /// Malformed successful output does not undo callee writes: callers needing
    /// receipt atomicity must retain their separate rollback frame.
    /// @dev The mandatory first unit forwards all gas, so a coordinator call it cannot finish
    ///      must revert here, before the call: a failure after the call is a dependency refusal,
    ///      never a shortage of gas. The caller multiplier never scales the first unit.
    function admitFirst(MineFlipGas.Meter memory meter, uint256 minimum, uint256 reserve) internal view {
        if (meter.mustProgress && gasleft() < minimum + reserve) revert MineFlipGas.InsufficientExecutionGas();
    }

    function callRemaining(MineFlipGas.Meter memory meter, address target, uint256 minimum,
        uint256 reserve, bytes memory input, uint256 expected)
        internal returns (bool ok, bytes memory output)
    {
        return callValueRemaining(meter, target, 0, minimum, reserve, input, expected);
    }

    function callValueRemaining(MineFlipGas.Meter memory meter, address target, uint256 value,
        uint256 minimum, uint256 reserve, bytes memory input, uint256 expected)
        internal returns (bool ok, bytes memory output)
    {
        output = new bytes(expected);
        uint256 operand = _remaining(meter, minimum, reserve, value == 0 ? CALL_OVERHEAD : VALUE_CALL_OVERHEAD);
        if (value != 0) {
            if (operand < VALUE_STIPEND) revert MineFlipGas.InsufficientExecutionGas();
            unchecked { operand -= VALUE_STIPEND; }
        }
        assembly ("memory-safe") {
            ok := call(operand, target, value, add(input, 32), mload(input), 0, 0)
            ok := and(ok, iszero(lt(returndatasize(), expected)))
            switch ok
            case 0 { mstore(output, 0) }
            default { returndatacopy(add(output, 32), 0, expected) }
        }
    }

    function staticcallRemaining(MineFlipGas.Meter memory meter, address target, uint256 minimum,
        uint256 reserve, bytes memory input, uint256 expected)
        internal view returns (bool ok, bytes memory output)
    {
        output = new bytes(expected);
        uint256 operand = _remaining(meter, minimum, reserve, CALL_OVERHEAD);
        assembly ("memory-safe") {
            ok := staticcall(operand, target, add(input, 32), mload(input), 0, 0)
            ok := and(ok, iszero(lt(returndatasize(), expected)))
            switch ok
            case 0 { mstore(output, 0) }
            default { returndatacopy(add(output, 32), 0, expected) }
        }
    }

    function staticWordRemaining(MineFlipGas.Meter memory meter, address target, uint256 minimum,
        uint256 reserve, bytes memory input) internal view returns (bool ok, uint256 word)
    {
        bytes memory output;
        (ok, output) = staticcallRemaining(meter, target, minimum, reserve, input, 32);
        if (ok) word = abi.decode(output, (uint256));
    }

    /// @dev Callee execution allowance for a working stETH balanceOf (normally about 25k gas).
    ///      Admission must also cover cold-call overhead and EIP-150's retained caller gas.
    uint256 internal constant STETH_READ_MIN_GAS = 100_000;

    /// @dev stETH balance for trusted holder exits: 0 unless the call succeeds with a full word,
    ///      so a dead token never blocks an ETH-only payout. Forwards all gas, no cap; admission
    ///      reverts before the call when gas is short.
    function stethBalanceOrZero(address token, address account) internal view returns (uint256 balance) {
        if (gasleft() < STETH_READ_MIN_GAS + CALL_OVERHEAD + (STETH_READ_MIN_GAS + 62) / 63) {
            revert MineFlipGas.InsufficientExecutionGas();
        }
        (bool ok, bytes memory output) = token.staticcall(abi.encodeWithSelector(IStETH.balanceOf.selector, account));
        if (ok && output.length >= 32) balance = abi.decode(output, (uint256));
    }

    function callBoolRemaining(MineFlipGas.Meter memory meter, address target, uint256 minimum,
        uint256 reserve, bytes memory input) internal returns (bool)
    {
        (bool ok, bytes memory output) = callRemaining(meter, target, minimum, reserve, input, 32);
        return ok && abi.decode(output, (uint256)) == 1;
    }

    /// @dev Immediately after a failed call to immutable protocol code only.
    /// Preserve its gas refusal instead of applying an external-dependency policy.
    /// External token/coordinator errors never reach this helper unwrapped.
    function rethrowTrustedGasFailure() internal pure {
        bytes4 reason;
        uint256 size;
        assembly ("memory-safe") {
            size := returndatasize()
            if eq(size, 4) { returndatacopy(0, 0, 4) reason := mload(0) }
        }
        if (size == 0) revert MineFlipGas.InsufficientExecutionGas();
        if (reason == MineFlipGas.InsufficientExecutionGas.selector
            || reason == MineFlipGas.WorkGasBound.selector || reason == MineFlipGas.EmptyRevert.selector) {
            assembly ("memory-safe") { returndatacopy(0, 0, 4) revert(0, 4) }
        }
    }

    function _remaining(MineFlipGas.Meter memory meter, uint256 minimum, uint256 reserve, uint256 overhead)
        private view returns (uint256 available)
    {
        // The mandatory first unit owns all available gas, including its dependency calls.
        // Scaled minima and tail reservations admit optional continuation only.
        if (meter.mustProgress) return gasleft();
        minimum = MineFlipGas.scale(meter, minimum);
        reserve = MineFlipGas.scale(meter, reserve + overhead);
        available = gasleft();
        if (meter.floor > available || reserve > available - meter.floor) {
            revert MineFlipGas.InsufficientExecutionGas();
        }
        unchecked { available -= meter.floor + reserve; }
        // Conservative EIP-150 admission, independent of post-call gas/refills.
        if (minimum > available || available - minimum < minimum / 63) {
            revert MineFlipGas.InsufficientExecutionGas();
        }
    }
}
