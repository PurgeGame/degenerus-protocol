// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {MineFlipGas} from "./MineFlipGas.sol";

/// @notice External calls with bounded return data and explicit admission/reserve policies.
library BoundedCall {
    uint256 private constant CALL_OVERHEAD = 10_000;
    uint256 private constant VALUE_CALL_OVERHEAD = 45_000;
    uint256 private constant VALUE_STIPEND = 2_300;

    /// @dev Trusted dependency or immutable protocol call: no fixed ceiling. Reserve
    ///      the caller's tail, then offer all remaining gas (subject to EIP-150).
    ///      The minimum is admission only. Insufficient admission reverts the step;
    ///      callee failure is returned without copying or interpreting revert data.
    ///      As with call(), malformed successful output does not undo callee writes.
    function callRemaining(address target, uint256 minimum, uint256 reserve, bytes memory input, uint256 expected)
        internal returns (bool ok, bytes memory output)
    {
        output = new bytes(expected);
        uint256 operand = _remaining(minimum, reserve);
        assembly ("memory-safe") {
            ok := call(operand, target, 0, add(input, 32), mload(input), 0, 0)
            ok := and(ok, iszero(lt(returndatasize(), expected)))
            switch ok
            case 0 { mstore(output, 0) }
            default { returndatacopy(add(output, 32), 0, expected) }
        }
    }

    function staticcallRemaining(address target, uint256 minimum, uint256 reserve, bytes memory input, uint256 expected)
        internal view returns (bool ok, bytes memory output)
    {
        output = new bytes(expected);
        uint256 operand = _remaining(minimum, reserve);
        assembly ("memory-safe") {
            ok := staticcall(operand, target, add(input, 32), mload(input), 0, 0)
            ok := and(ok, iszero(lt(returndatasize(), expected)))
            switch ok
            case 0 { mstore(output, 0) }
            default { returndatacopy(add(output, 32), 0, expected) }
        }
    }

    function staticWordRemaining(address target, uint256 minimum, uint256 reserve, bytes memory input)
        internal view returns (bool ok, uint256 word)
    {
        bytes memory output;
        (ok, output) = staticcallRemaining(target, minimum, reserve, input, 32);
        if (ok) word = abi.decode(output, (uint256));
    }

    function callBoolRemaining(address target, uint256 minimum, uint256 reserve, bytes memory input)
        internal returns (bool)
    {
        (bool ok, bytes memory output) = callRemaining(target, minimum, reserve, input, 32);
        return ok && abi.decode(output, (uint256)) == 1;
    }

    function _remaining(uint256 minimum, uint256 reserve) private view returns (uint256 available) {
        available = gasleft();
        if (reserve > available || available - reserve < CALL_OVERHEAD) {
            revert MineFlipGas.InsufficientExecutionGas();
        }
        unchecked { available -= reserve + CALL_OVERHEAD; }
        // Conservative EIP-150 admission; the reserve is not counted toward the
        // minimum. The overhead also covers cold-account and instruction costs.
        if (minimum > available || available - minimum < minimum / 63) {
            revert MineFlipGas.InsufficientExecutionGas();
        }
    }

    /// @dev Copies exactly `expected` bytes on success; ignores any trailing data.
    ///      Failure returns an empty buffer and never interprets revert data.
    ///      A successful CALL with malformed output still commits the callee's writes.
    function call(address target, uint256 value, uint256 budget, bytes memory input, uint256 expected)
        internal returns (bool ok, bytes memory output)
    {
        output = new bytes(expected);
        uint256 operand = budget;
        uint256 overhead = CALL_OVERHEAD;
        if (value != 0) {
            if (budget < VALUE_STIPEND) revert MineFlipGas.InsufficientExecutionGas();
            unchecked { operand = budget - VALUE_STIPEND; }
            overhead = VALUE_CALL_OVERHEAD;
        }
        _requireGas(budget, overhead);
        assembly ("memory-safe") {
            ok := call(operand, target, value, add(input, 32), mload(input), 0, 0)
            ok := and(ok, iszero(lt(returndatasize(), expected)))
            switch ok
            case 0 { mstore(output, 0) }
            default { returndatacopy(add(output, 32), 0, expected) }
        }
    }

    function staticcall(address target, uint256 budget, bytes memory input, uint256 expected)
        internal view returns (bool ok, bytes memory output)
    {
        output = new bytes(expected);
        _requireGas(budget, CALL_OVERHEAD);
        assembly ("memory-safe") {
            ok := staticcall(budget, target, add(input, 32), mload(input), 0, 0)
            ok := and(ok, iszero(lt(returndatasize(), expected)))
            switch ok
            case 0 { mstore(output, 0) }
            default { returndatacopy(add(output, 32), 0, expected) }
        }
    }

    function callBool(address target, uint256 budget, bytes memory input) internal returns (bool) {
        (bool ok, bytes memory output) = call(target, 0, budget, input, 32);
        return ok && abi.decode(output, (uint256)) == 1;
    }

    function staticWord(address target, uint256 budget, bytes memory input)
        internal view returns (bool ok, uint256 word)
    {
        bytes memory output;
        (ok, output) = staticcall(target, budget, input, 32);
        if (ok) word = abi.decode(output, (uint256));
    }

    /// @dev Admission is unconditional, including a worker's first mandatory unit.
    ///      The margin covers a cold account, CALL setup, and the EIP-150 reduction;
    ///      value calls also cover value transfer and a newly created account.
    function _requireGas(uint256 budget, uint256 overhead) private view {
        uint256 available = gasleft();
        if (budget > available || available - budget < budget / 63 + overhead) {
            revert MineFlipGas.InsufficientExecutionGas();
        }
    }
}
