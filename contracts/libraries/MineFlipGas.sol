// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/// @notice Gas admission at deterministic checkpoints in the permissionless game engine.
/// @dev Estimates admit continuations, never veto the first mandatory checkpoint.
///      Work budgets carry call-local calibration, not stored protocol configuration.
library MineFlipGas {
    uint256 internal constant MIN_REWARDED_GAS = 1_000_000;
    uint256 internal constant CHECK_RESERVE = 2_000;
    uint256 internal constant CALL_RESERVE = 12_000;
    uint32 internal constant DEFAULT_MULTIPLIER = 10_000;
    uint256 private constant CONTEXT_TAG = 1 << 255;
    uint256 private constant FIRST_BIT = 1 << 224;
    uint256 private constant ALLOWANCE_MASK = type(uint192).max;

    error InsufficientExecutionGas();
    error WorkGasBound();
    error InvalidGasMultiplier();
    /// @dev Same signature as the Game's EmptyRevert(), raised for an empty module revert.
    error EmptyRevert();

    struct Meter {
        uint256 start;
        uint256 floor;
        uint32 multiplierBps;
        bool mustProgress;
    }

    struct Result {
        bool progressed;
        bool done;
        uint256 rewardBasis;
    }

    function available() internal view returns (uint256) {
        return gasleft();
    }

    function normalize(uint32 multiplierBps) internal pure returns (uint32) {
        if (multiplierBps == 0) return DEFAULT_MULTIPLIER;
        if (multiplierBps < DEFAULT_MULTIPLIER) revert InvalidGasMultiplier();
        return multiplierBps;
    }

    /// @dev ABI transport in the existing worker budget word: low 192 bits are
    /// actual gas, bits 192..223 calibration, bit 224 first-progress permission.
    /// Bit 255 distinguishes context from legacy uncalibrated worker allowances.
    /// Never pass this encoded word as a CALL gas operand or subtract from it.
    function budget(uint256 allowance, uint32 multiplierBps, bool mustProgress) internal pure returns (uint256) {
        if (multiplierBps == 0) return allowance;
        if (allowance > ALLOWANCE_MASK) allowance = ALLOWANCE_MASK;
        return CONTEXT_TAG | (uint256(multiplierBps) << 192) | (mustProgress ? FIRST_BIT : 0) | allowance;
    }

    /// @dev The local allowance retains the parent's return gas across nested work;
    ///      it is derived from gas actually available, without a transaction ceiling.
    function start(uint256 allowance) internal view returns (Meter memory meter) {
        uint256 entry = gasleft();
        if (allowance & CONTEXT_TAG != 0) {
            // The root validates once; only trusted workers forward this context.
            meter.multiplierBps = uint32(allowance >> 192);
            meter.mustProgress = allowance & FIRST_BIT != 0;
            allowance &= ALLOWANCE_MASK;
        }
        meter.start = entry;
        // The mandatory path uses the actual forwarded frame, not a soft estimate.
        meter.floor = meter.mustProgress || allowance >= entry ? 0 : entry - allowance;
    }

    function spent(Meter memory meter) internal view returns (uint256) {
        return consumed(meter.start, gasleft());
    }

    function consumed(uint256 beforeGas, uint256 afterGas) internal pure returns (uint256) {
        return beforeGas > afterGas ? beforeGas - afterGas : 0;
    }

    function remaining(Meter memory meter) internal view returns (uint256) {
        uint256 current = gasleft();
        return current > meter.floor ? current - meter.floor : 0;
    }

    function scale(Meter memory meter, uint256 estimate) internal pure returns (uint256) {
        uint256 multiplier = meter.multiplierBps;
        if (multiplier == 0 || multiplier == DEFAULT_MULTIPLIER) return estimate;
        if (estimate > (type(uint256).max - 9_999) / multiplier) return type(uint256).max;
        // The saturation check above proves both operations fit.
        unchecked { return (estimate * multiplier + 9_999) / DEFAULT_MULTIPLIER; }
    }

    /// @dev Call only after a canonical unit or one-time setup has progressed.
    function markProgress(Meter memory meter) internal pure {
        meter.mustProgress = false;
    }

    /// @dev `nextMax` includes the entire next indivisible operation. `tail`
    ///      includes every accumulated flush, checkpoint write and return cost.
    function canRun(Meter memory meter, uint256 nextMax, uint256 tail) internal view returns (bool) {
        if (meter.mustProgress) return true;
        return canRunAfterFirst(meter, nextMax, tail);
    }

    /// @dev Size optional aggregation without spending the first-unit permission.
    function canRunAfterFirst(Meter memory meter, uint256 nextMax, uint256 tail) internal view returns (bool) {
        uint256 required = scale(meter, nextMax + tail + CHECK_RESERVE);
        if (required > remaining(meter)) return false;
        return gasleft() >= required;
    }

    function forwardable(Meter memory meter, uint256 tail) internal view returns (uint256) {
        uint256 left = remaining(meter);
        if (meter.mustProgress) return left;
        uint256 reserve = scale(meter, tail + CALL_RESERVE);
        return left > reserve ? left - reserve : 0;
    }

    function child(Meter memory meter, uint256 tail) internal view returns (uint256) {
        return budget(forwardable(meter, tail), meter.multiplierBps, meter.mustProgress);
    }

    /// @dev Available child gas after retaining the caller's complete return tail.
    ///      This is only a checkpoint/call envelope, never an entropy input or fixed tx cap.
    function forwardable(uint256 allowance, uint256 tail) internal view returns (uint256) {
        uint256 available = gasleft();
        uint256 reserve = tail + CALL_RESERVE;
        if (available <= reserve || allowance <= reserve) return 0;
        available -= reserve;
        allowance -= reserve;
        return available < allowance ? available : allowance;
    }

    /// @dev Guarantees a fixed-stipend call its whole stipend after EIP-150 retention, so a
    ///      failure it returns is the callee's own refusal, never caller-withheld gas.
    function requireStipend(uint256 stipend) internal view {
        if (gasleft() < stipend + stipend / 63 + 2 * CALL_RESERVE) revert InsufficientExecutionGas();
    }

    function finish(Meter memory meter) internal view {
        if (gasleft() < meter.floor) revert WorkGasBound();
    }

    /// @dev Metering failures must never be swallowed by a semantic fallback. The Game
    ///      re-raises an empty module revert (a module call out of gas) as EmptyRevert().
    function rethrowGasFailure(bytes memory reason) internal pure {
        if (reason.length == 0) revert InsufficientExecutionGas();
        bytes4 selector;
        assembly ("memory-safe") { selector := mload(add(reason, 32)) }
        if (selector == InsufficientExecutionGas.selector || selector == WorkGasBound.selector
            || selector == EmptyRevert.selector) {
            assembly ("memory-safe") { revert(add(reason, 32), mload(reason)) }
        }
    }
}
