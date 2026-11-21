// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Test} from "forge-std/Test.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {GlamsterdamReprice} from "./GlamsterdamReprice.sol";

/// @dev Glamsterdam repricing of calls measured through a meter contract whose first return word
///      is the gas it measured around the call. Isolated suites only: every top-level call is its
///      own transaction and starts cold.
///
///      State-diff recording loads each slot before the opcode that first touches it, so a
///      recorded call pays every first access warm, and recording continues after
///      `stopAndReturnStateDiff`. A recorded call's cold figure is therefore its measured gas plus
///      2,000 per slot first read and 2,100 per slot first written, and an unrecorded measurement
///      is cold only before the test's first recording.
abstract contract GlamsterdamMeterReplay is Test {
    struct Priced {
        uint256 osaka;
        uint256 exec;
        uint256 state;
    }

    /// @dev A Glamsterdam pass. `recording` is set once the pass has recorded a call.
    struct Pass {
        bool glam;
        bool recording;
    }

    /// @dev Replays a call measured cold, before any recording, from `snapshot` (its pre-state),
    ///      and checks that the recorded execution rebuilds the cold figure. The replay leaves the
    ///      measured call's post-state.
    function _reprice(uint256 snapshot, address meter, bytes memory data, uint256 osaka)
        internal returns (Priced memory p, bytes memory ret)
    {
        assertTrue(vm.revertToStateAndDelete(snapshot));
        (p, ret) = this.meterRecorded(meter, data, 0);
        assertEq(p.osaka, osaka, "recorded call plus its cold-access surcharges is the cold call");
    }

    /// @dev A Glamsterdam pass's measurement: recorded and repriced unless the records bound its
    ///      total at or below `floor` (then exec and state are zero). The pass's first call is also
    ///      measured unrecorded and cold from the same pre-state, which validates the rebuilt figure.
    function _recorded(address meter, bytes memory data, Pass memory pass, uint256 floor)
        internal returns (Priced memory p, bytes memory ret)
    {
        if (pass.recording) return this.meterRecorded(meter, data, floor);
        pass.recording = true;
        uint256 snapshot = vm.snapshotState();
        (bool ok, bytes memory cold) = meter.call(data);
        require(ok, "cold call");
        return _reprice(snapshot, meter, data, abi.decode(cold, (uint256)));
    }

    /// @dev One recorded call, as its own isolated transaction. Repricing in this frame releases
    ///      its tables before the next call; it is skipped when the records bound the total at or
    ///      below `floor`.
    function meterRecorded(address meter, bytes calldata data, uint256 floor)
        external returns (Priced memory p, bytes memory ret)
    {
        require(msg.sender == address(this), "recorded self-call");
        require(vm.envOr("FOUNDRY_ISOLATE", false), "requires isolation");
        vm.startStateDiffRecording();
        bool ok;
        (ok, ret) = meter.call(data);
        VmSafe.AccountAccess[] memory acc = vm.stopAndReturnStateDiff();
        vm.stopMappingRecording();
        require(ok, "recorded call");
        uint256 count;
        for (uint256 i; i < acc.length; ++i) {
            if (acc[i].account == address(vm)) continue;
            if (acc[i].account == address(this) && acc[i].kind != VmSafe.AccountAccessKind.Resume) continue;
            acc[count++] = acc[i];
        }
        assembly ("memory-safe") { mstore(acc, count) }
        (uint256 surcharge, uint256 bound) = _scan(acc);
        p.osaka = abi.decode(ret, (uint256)) + surcharge;
        if (p.osaka + bound <= floor) return (p, ret);
        GlamsterdamReprice.Result memory r = GlamsterdamReprice.reprice(p.osaka, acc, meter);
        (p.exec, p.state) = (r.glamsterdamExec, r.stateGas);
    }

    /// @dev The cold-access surcharges, and an upper bound of the repricing's increase: every write
    ///      a first change (+7,200), every slot zero at its first access and written a new slot,
    ///      every record a cold account and every value call one to a new account.
    function _scan(VmSafe.AccountAccess[] memory acc) private pure returns (uint256 surcharge, uint256 bound) {
        address[] memory accounts = new address[](1024);
        bytes32[] memory slots = new bytes32[](1024);
        uint256[] memory state = new uint256[](1024); // 1: zero at first access; 2: counted new
        uint256 n;
        for (uint256 i; i < acc.length; ++i) {
            VmSafe.AccountAccessKind kind = acc[i].kind;
            bound += 400;
            if (kind == VmSafe.AccountAccessKind.Call && acc[i].value != 0) bound += 2_300 + 183_600;
            if (kind == VmSafe.AccountAccessKind.Extcodesize || kind == VmSafe.AccountAccessKind.Extcodecopy) {
                bound += 100;
            }
            for (uint256 j; j < acc[i].storageAccesses.length; ++j) {
                VmSafe.StorageAccess memory a = acc[i].storageAccesses[j];
                uint256 k;
                while (k < n && (accounts[k] != a.account || slots[k] != a.slot)) ++k;
                if (k == n) {
                    require(n < 1024, "scan capacity");
                    (accounts[n], slots[n]) = (a.account, a.slot);
                    if (a.previousValue == bytes32(0)) state[n] = 1;
                    ++n;
                    surcharge += a.isWrite ? 2_100 : 2_000;
                }
                if (!a.isWrite) continue;
                bound += 7_200;
                if (state[k] == 1 && a.newValue != bytes32(0)) {
                    state[k] = 2;
                    bound += GlamsterdamReprice.NEW_SLOT_STATE_GAS;
                }
            }
        }
    }

    /// @dev The no-reservoir admission figure.
    function _glam(Priced memory p) internal pure returns (uint256) {
        return p.exec + p.state;
    }

    function _logPriced(string memory label, Priced memory p, uint256 bound) internal {
        emit log_named_string("unit", label);
        emit log_named_uint("  osaka", p.osaka);
        emit log_named_uint("  glamsterdam exec", p.exec);
        emit log_named_uint("  glamsterdam state", p.state);
        emit log_named_uint("  glamsterdam total", p.exec + p.state);
        emit log_named_uint("  bound", bound);
    }
}
