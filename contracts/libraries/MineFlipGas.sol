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
        uint256 floor;
        uint32 multiplierBps;
        bool mustProgress;
        bool bounded;
    }

    struct Result {
        bool progressed;
        bool done;
        uint256 rewardBasis;
    }

    function normalize(uint32 multiplierBps) internal pure returns (uint32) {
        if (multiplierBps == 0) return DEFAULT_MULTIPLIER;
        if (multiplierBps < DEFAULT_MULTIPLIER) revert InvalidGasMultiplier();
        return multiplierBps;
    }

    /// @dev ABI transport in the existing worker budget word: low 192 bits are the
    /// reserve-adjusted gas allowance, bits 192..223 calibration, bit 224 first-progress permission.
    /// Bit 255 distinguishes context from legacy uncalibrated worker allowances.
    /// Never pass this encoded word as a CALL gas operand or subtract from it.
    function budget(uint256 allowance, uint32 multiplierBps, bool mustProgress) internal pure returns (uint256) {
        if (multiplierBps == 0) return allowance;
        if (allowance > ALLOWANCE_MASK) allowance = ALLOWANCE_MASK;
        return CONTEXT_TAG | (uint256(multiplierBps) << 192) | (mustProgress ? FIRST_BIT : 0) | allowance;
    }

    /// @dev The local allowance retains the parent's return gas across nested work;
    ///      it is derived from gas actually available, without a transaction ceiling.
    ///      The floor always holds every ancestor's tail. The first unit may run below it;
    ///      once that unit marks progress, later units must fit above it again.
    function start(uint256 allowance) internal view returns (Meter memory meter) {
        uint256 entry = gasleft();
        if (allowance & CONTEXT_TAG != 0) {
            // The root validates once; only trusted workers forward this context.
            meter.multiplierBps = uint32(allowance >> 192);
            meter.mustProgress = allowance & FIRST_BIT != 0;
            allowance &= ALLOWANCE_MASK;
        }
        meter.floor = allowance >= entry ? 0 : entry - allowance;
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
        if (required > remaining(meter) || gasleft() < required) return false;
        // Work admitted on an estimate is held to the floor at finish.
        if (!meter.mustProgress) meter.bounded = true;
        return true;
    }

    /// @dev Gas to send a child call: everything for the first unit, else the allowance.
    function forwardable(Meter memory meter, uint256 tail) internal view returns (uint256) {
        if (meter.mustProgress) return gasleft();
        return _allowance(meter, tail);
    }

    /// @dev The child's context word always carries the reserve-adjusted allowance, so a
    ///      child that runs past its first unit still leaves every ancestor's tail.
    function child(Meter memory meter, uint256 tail) internal view returns (uint256) {
        return budget(_allowance(meter, tail), meter.multiplierBps, meter.mustProgress);
    }

    function _allowance(Meter memory meter, uint256 tail) private view returns (uint256) {
        uint256 left = remaining(meter);
        uint256 reserve = scale(meter, tail + CALL_RESERVE);
        return left > reserve ? left - reserve : 0;
    }

    /// @dev Only estimate-admitted work can overspend. A refused worker's fixed prelude
    ///      and a first unit that ran below the floor are not estimate failures.
    function finish(Meter memory meter) internal view {
        if (meter.bounded && gasleft() < meter.floor) revert WorkGasBound();
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
