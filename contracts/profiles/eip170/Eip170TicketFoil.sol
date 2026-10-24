// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DegenerusGameTicketModule} from "../../modules/DegenerusGameTicketModule.sol";
import {DegenerusGameFoilWorkerModule} from "../../modules/DegenerusGameFoilWorkerModule.sol";
import {MineFlipGas} from "../../libraries/MineFlipGas.sol";

contract Eip170TicketFoil is DegenerusGameTicketModule, DegenerusGameFoilWorkerModule {
    function _ticketFoilWork(uint256 allowance) internal override returns (MineFlipGas.Result memory) { return _runFoilWork(allowance); }
}
