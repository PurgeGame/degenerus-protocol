// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Test} from "forge-std/Test.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {GlamsterdamReprice} from "./GlamsterdamReprice.sol";

/// @notice Glamsterdam re-pricing of a call already measured cold (isolated suites only).
/// @dev The Osaka figure is the cold isolated call's transaction gas less its intrinsic gas; a
///      recorded run of the same call from the same state supplies the accesses and leaves the
///      post-state. Every cold measurement of a test runs before its first recorded run: later
///      calls in the test can find the accounts a recorded run touched warm.
abstract contract GlamsterdamFrameProbe is Test {
    uint256 internal constant GLAM_FRAME_CAP = 12_000_000;

    function _glamsterdamRecorded(address target, bytes memory data, uint256 osakaTx)
        internal
        returns (GlamsterdamReprice.Result memory r, VmSafe.AccountAccess[] memory acc, bytes memory ret)
    {
        require(vm.envOr("FOUNDRY_ISOLATE", false), "requires isolation");
        vm.startStateDiffRecording();
        bool ok;
        (ok, ret) = target.call{gas: GLAM_FRAME_CAP}(data);
        acc = _frameAccesses(vm.stopAndReturnStateDiff());
        vm.stopMappingRecording();
        require(ok, "the recorded run reverted");
        r = GlamsterdamReprice.reprice(osakaTx - _intrinsicGas(data), acc, target);
    }

    /// @dev Transaction intrinsic gas of a call carrying `data` (no access list).
    function _intrinsicGas(bytes memory data) internal pure returns (uint256 gas) {
        gas = 21_000;
        for (uint256 i; i < data.length; ++i) gas += data[i] == 0 ? 4 : 16;
    }

    /// @dev Drops the fixture's own and cheatcode records; the measured call is then the
    ///      shallowest recorded call.
    function _frameAccesses(VmSafe.AccountAccess[] memory acc) internal view returns (VmSafe.AccountAccess[] memory) {
        uint256 n;
        for (uint256 i; i < acc.length; ++i) {
            if (acc[i].account == address(vm)) continue;
            if (acc[i].account == address(this) && acc[i].kind != VmSafe.AccountAccessKind.Resume) continue;
            acc[n++] = acc[i];
        }
        assembly ("memory-safe") { mstore(acc, n) }
        return acc;
    }

    function _glamsterdamTotal(GlamsterdamReprice.Result memory r) internal pure returns (uint256) {
        return r.glamsterdamExec + r.stateGas;
    }

    function _logGlamsterdam(string memory label, GlamsterdamReprice.Result memory r, uint256 bound) internal {
        emit log_named_string("glamsterdam_unit", label);
        emit log_named_uint("  osaka_frame", r.osakaExec);
        emit log_named_uint("  glamsterdam_exec", r.glamsterdamExec);
        emit log_named_uint("  glamsterdam_state_peak", r.stateGas);
        emit log_named_uint("  glamsterdam_total", _glamsterdamTotal(r));
        emit log_named_uint("  new_slots", r.newSlots);
        emit log_named_uint("  bound", bound);
    }
}
