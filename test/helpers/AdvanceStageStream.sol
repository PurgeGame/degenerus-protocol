// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";

/// @title AdvanceStageStream — attribute the engine's logs to the daily stage that produced them.
/// @notice mineFlip composes every admitted checkpoint into one call, so a call boundary no longer
///         separates the daily stages. Each stage's work emits its logs and then its
///         `Advance(stage, lvl)` marker, so the ordered log stream splits exactly: the logs up to
///         and including a run of identical markers belong to that stage. `_nextStageRun` drives
///         calls (each given the smallest rung of a realistic allowance ladder that admits work,
///         which keeps indivisible actions and later stages in separate calls wherever their
///         admissions allow) until the next run is closed by a different marker, by the end of
///         the daily lock, or by the engine running out of work.
abstract contract AdvanceStageStream is DeployProtocol {
    bytes32 internal constant STREAM_ADVANCE_SIG = keccak256("Advance(uint8,uint24)");

    /// @dev Every log the driven calls emitted, in order, with the index of the call that emitted it.
    Vm.Log[] internal streamLogs;
    uint256[] internal streamLogCall;
    /// @dev Gas used by each driven call (intrinsic included), and whether the daily lock was
    ///      held when the call returned.
    uint256[] internal streamCallGas;
    bool[] internal streamLockedAfter;
    /// @dev First log not yet returned by `_nextStageRun`.
    uint256 internal streamCursor;

    /// @dev Realistic allowances, smallest first. A rung below an action's admission reverts with
    ///      InsufficientExecutionGas and changes nothing, so the next rung is tried.
    function _streamLadder() internal pure virtual returns (uint256[12] memory ladder) {
        ladder = [
            uint256(1_500_000), 2_000_000, 2_500_000, 3_000_000, 3_500_000, 4_000_000,
            4_500_000, 5_000_000, 6_000_000, 8_000_000, 10_000_000, 16_700_000
        ];
    }

    /// @dev One driven call at the smallest admitting rung. False when the engine had no work
    ///      (NoWork / RngNotReady) at every rung.
    function _streamCall() internal returns (bool ok) {
        uint256[12] memory ladder = _streamLadder();
        for (uint256 r; r < ladder.length; ++r) {
            vm.recordLogs();
            bytes memory err;
            (ok, err) = address(game).call{gas: ladder[r]}(abi.encodeWithSignature("mineFlip(uint32)", uint32(0)));
            uint256 used = vm.lastCallGas().gasTotalUsed;
            Vm.Log[] memory logs = vm.getRecordedLogs();
            if (ok) {
                if (!vm.envOr("FOUNDRY_ISOLATE", false)) used += 21_192;
                uint256 callIndex = streamCallGas.length;
                streamCallGas.push(used);
                streamLockedAfter.push(game.rngLocked());
                for (uint256 i; i < logs.length; ++i) {
                    streamLogs.push(logs[i]);
                    streamLogCall.push(callIndex);
                }
                return true;
            }
            if (bytes4(err) != MineFlipGas.InsufficientExecutionGas.selector) return false;
        }
        revert("stream: no realistic allowance admits the next action");
    }

    function _isMarker(uint256 i) internal view returns (bool) {
        Vm.Log storage l = streamLogs[i];
        return l.emitter == address(game) && l.topics.length == 1 && l.topics[0] == STREAM_ADVANCE_SIG;
    }

    function _markerStage(uint256 i) internal view returns (uint8 stage) {
        (stage,) = abi.decode(streamLogs[i].data, (uint8, uint24));
    }

    /// @dev The next stage run: logs [from, to] (inclusive) close with the run's last marker.
    ///      `maxGas` is the largest call that emitted any of them.
    function _nextStageRun(uint256 maxCalls)
        internal
        returns (uint8 stage, uint256 from, uint256 to, uint256 maxGas)
    {
        from = streamCursor;
        bool started;
        uint256 lastMarker;
        uint256 scanned = from;
        bool closed;
        for (uint256 calls; ; ++calls) {
            for (; scanned < streamLogs.length; ++scanned) {
                if (!_isMarker(scanned)) continue;
                uint8 s = _markerStage(scanned);
                if (!started) {
                    started = true;
                    stage = s;
                    lastMarker = scanned;
                } else if (s == stage) {
                    lastMarker = scanned;
                } else {
                    closed = true;
                    break;
                }
            }
            if (closed) break;
            if (started && !game.rngLocked()) break;
            require(calls < maxCalls, "stream: the stage never closed");
            if (!_streamCall()) {
                require(started, "stream: no stage ran");
                break;
            }
        }
        to = lastMarker;
        streamCursor = lastMarker + 1;
        for (uint256 i = from; i <= to; ++i) {
            uint256 g = streamCallGas[streamLogCall[i]];
            if (g > maxGas) maxGas = g;
        }
    }

    /// @dev Drive calls until a `stage` marker appears past the cursor. The run [from, to] ends
    ///      at that marker; later logs stay for the next run.
    function _runThroughMarker(uint8 stage, uint256 maxCalls) internal returns (uint256 from, uint256 to, uint256 maxGas) {
        from = streamCursor;
        uint256 scanned = from;
        for (uint256 calls; ; ++calls) {
            for (; scanned < streamLogs.length; ++scanned) {
                if (_isMarker(scanned) && _markerStage(scanned) == stage) {
                    to = scanned;
                    streamCursor = scanned + 1;
                    for (uint256 i = from; i <= to; ++i) {
                        uint256 g = streamCallGas[streamLogCall[i]];
                        if (g > maxGas) maxGas = g;
                    }
                    return (from, to, maxGas);
                }
            }
            require(calls < maxCalls, "stream: the marker never appeared");
            require(_streamCall(), "stream: the engine ran out of work before the marker");
        }
    }

    /// @dev True when a progress marker follows log `to` in the stream.
    function _markerAfter(uint256 to) internal view returns (bool) {
        for (uint256 i = to + 1; i < streamLogs.length; ++i) if (_isMarker(i)) return true;
        return false;
    }

    /// @dev Logs in [from, to] whose first topic is `sig`.
    function _streamCount(uint256 from, uint256 to, bytes32 sig) internal view returns (uint256 n) {
        for (uint256 i = from; i <= to; ++i) {
            if (streamLogs[i].topics.length != 0 && streamLogs[i].topics[0] == sig) ++n;
        }
    }
}
