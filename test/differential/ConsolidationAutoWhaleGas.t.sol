// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {SdgnrsWhaleBuyStageGas} from "../gas/SdgnrsWhaleBuyStageGas.t.sol";
import {MineFlipGasBounds as GasBounds} from "../../contracts/libraries/MineFlipGasBounds.sol";

/// @notice Keep the automatic-whale purchase comparison on a coherent production deployment.
/// @dev The P1 baseline (50ea3c778, solc 0.8.34, via-IR, 1000 runs, Osaka) measured
///      531619 execution / 1667039 modeled state-inclusive gas for the 1000-pass increment.
///      Its old separate module runtimes cannot be etched onto P7's aliased module pins:
///      that creates a mixed protocol with incompatible entrypoints. The historical values
///      are reported explicitly; the live checkpoint must satisfy its current declared bound.
contract ConsolidationAutoWhaleGas is SdgnrsWhaleBuyStageGas {
    function test_CurrentWhaleCheckpointAgainstRecordedBaseline() public {
        uint256 snapshot = vm.snapshotState();
        uint256 empty = _measureFirstAdvanceOfDay(10 ether, 10 ether, 0);
        uint256 emptyRepriced = _lastRepriced;
        assertTrue(vm.revertToState(snapshot));
        uint256 funded = _measureFirstAdvanceOfDay(16010 ether, 0, 1000);
        uint256 repriced = _lastRepriced - emptyRepriced;
        uint256 increment = funded - empty;
        emit log_named_uint("P1 recorded execution increment", 531619);
        emit log_named_uint("P1 recorded modeled state-inclusive increment", 1667039);
        emit log_named_uint("final execution increment", increment);
        emit log_named_uint("final modeled state-inclusive increment", repriced);
        assertGt(increment, 0, "the live purchase did work");
        assertLe(increment, GasBounds.SUBSCRIBER_WHALE_GAS, "execution fits declared checkpoint bound");
        assertLe(repriced, GasBounds.SUBSCRIBER_WHALE_GAS, "state-inclusive work fits declared checkpoint bound");
    }
}
