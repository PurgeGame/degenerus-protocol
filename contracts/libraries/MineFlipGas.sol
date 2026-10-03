// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/// @notice Gas admission at deterministic checkpoints in the permissionless game engine.
/// @dev Caller gas may select a safe checkpoint, never an outcome. Each operation
///      must fit its caller's available gas and return reservation. A transaction may
///      run many admitted operations, but no single operation's bound exceeds 10M gas.
library MineFlipGas {
    uint256 internal constant MIN_REWARDED_GAS = 1_000_000;
    uint256 internal constant CHECK_RESERVE = 2_000;
    uint256 internal constant CALL_RESERVE = 12_000;

    error InsufficientExecutionGas();
    error WorkGasBound();

    struct Meter {
        uint256 start;
        uint256 allowance;
    }

    struct Result {
        bool progressed;
        bool done;
        uint256 rewardBasis;
    }

    function available() internal view returns (uint256) {
        return gasleft();
    }

    /// @dev The local allowance retains the parent's return gas across nested work;
    ///      it is derived from gas actually available, without a transaction ceiling.
    function start(uint256 allowance) internal view returns (Meter memory meter) {
        meter = Meter({start: gasleft(), allowance: allowance});
    }

    function spent(Meter memory meter) internal view returns (uint256) {
        return meter.start - gasleft();
    }

    function remaining(Meter memory meter) internal view returns (uint256) {
        uint256 used = spent(meter);
        return used < meter.allowance ? meter.allowance - used : 0;
    }

    /// @dev `nextMax` includes the entire next indivisible operation. `tail`
    ///      includes every accumulated flush, checkpoint write and return cost.
    function canRun(Meter memory meter, uint256 nextMax, uint256 tail) internal view returns (bool) {
        uint256 required = nextMax + tail + CHECK_RESERVE;
        if (required > remaining(meter)) return false;
        return gasleft() >= required;
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
        if (spent(meter) > meter.allowance) revert WorkGasBound();
    }

    /// @dev Metering failures must never be swallowed by a semantic fallback.
    function rethrowGasFailure(bytes memory reason) internal pure {
        if (reason.length == 0) revert InsufficientExecutionGas();
        bytes4 selector;
        assembly ("memory-safe") { selector := mload(add(reason, 32)) }
        if (selector == InsufficientExecutionGas.selector || selector == WorkGasBound.selector) {
            assembly ("memory-safe") { revert(add(reason, 32), mload(reason)) }
        }
    }
}
