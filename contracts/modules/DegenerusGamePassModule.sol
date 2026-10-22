// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DegenerusGameWhaleModule} from "./DegenerusGameWhaleModule.sol";
import {DegenerusGameTicketModule} from "./DegenerusGameTicketModule.sol";
import {DegenerusGameFoilWorkerModule} from "./DegenerusGameFoilWorkerModule.sol";
import {MineFlipGas} from "../libraries/MineFlipGas.sol";

/// @notice Pass purchases and ticket materialization in Game storage.
contract DegenerusGamePassModule is DegenerusGameWhaleModule, DegenerusGameTicketModule, DegenerusGameFoilWorkerModule {
    function _ticketFoilWork(uint256 allowance) internal override returns (MineFlipGas.Result memory) {
        return _runFoilWork(allowance);
    }
}
