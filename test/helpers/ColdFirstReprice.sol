// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {VmSafe} from "forge-std/Vm.sol";
import {GlamsterdamReprice} from "./GlamsterdamReprice.sol";
import {MinerloopGasProbe} from "./MinerloopGasProbe.sol";

/// @dev After a recorded replay, later isolated calls in the same test see warm storage, so a
///      test that reprices several pre-states measures every one cold before recording any, then
///      rebuilds each pre-state deterministically for its recorded replay.
abstract contract ColdFirstReprice is MinerloopGasProbe {
    /// @dev Phase one: the cold frame gas of the call from the current state, which it commits.
    ///      No recording.
    function _coldFrame(address target, address sender, bytes memory data, uint256 cap)
        internal returns (uint256 used, bytes memory result)
    {
        (used, result) = this.minerloopMeasured(target, sender, data, cap);
    }

    /// @dev Phase two, in its own frame: replay from the rebuilt pre-state with recording and
    ///      reprice the phase-one cold figure. Leaves the pre-state in place.
    function coldFirstReplay(address target, address sender, bytes calldata data, uint256 cap, uint256 used,
        bytes32 resultHash) external returns (GlamsterdamReprice.Result memory r)
    {
        require(msg.sender == address(this), "measurement self-call");
        uint256 snap = vm.snapshotState();
        vm.startStateDiffRecording();
        (, bytes memory replay) = this.minerloopMeasured(target, sender, data, cap);
        VmSafe.AccountAccess[] memory acc = vm.stopAndReturnStateDiff();
        vm.stopMappingRecording();
        assertEq(keccak256(replay), resultHash, "replay returns the cold result");
        uint256 count;
        for (uint256 i; i < acc.length; ++i) {
            if (acc[i].account == address(vm)) continue;
            if (acc[i].account == address(this) && acc[i].kind != VmSafe.AccountAccessKind.Resume) continue;
            assertFalse(acc[i].reverted, "repricing assumes successful frames");
            acc[count++] = acc[i];
        }
        assembly ("memory-safe") { mstore(acc, count) }
        r = GlamsterdamReprice.reprice(used, acc, target);
        assertTrue(vm.revertToState(snap));
        vm.deleteStateSnapshot(snap);
    }
}
