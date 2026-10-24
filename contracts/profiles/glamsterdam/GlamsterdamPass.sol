// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DegenerusGameWhaleModule} from "../../modules/DegenerusGameWhaleModule.sol";
import {DegenerusGameTicketModule} from "../../modules/DegenerusGameTicketModule.sol";
import {DegenerusGameFoilWorkerModule} from "../../modules/DegenerusGameFoilWorkerModule.sol";
import {MineFlipGas} from "../../libraries/MineFlipGas.sol";

/// @notice Pass purchases and ticket materialization in Game storage.
contract GlamsterdamPass is DegenerusGameWhaleModule, DegenerusGameTicketModule, DegenerusGameFoilWorkerModule {
    function _ticketFoilWork(uint256 allowance) internal override returns (MineFlipGas.Result memory) {
        return _runFoilWork(allowance);
    }
}
