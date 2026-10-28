// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DegenerusGameFoilCore} from "./DegenerusGameFoilCore.sol";
import {MineFlipGas} from "../libraries/MineFlipGas.sol";

abstract contract DegenerusGameFoilWorkerModule is DegenerusGameFoilCore {
    function queuePerpetualTickets(uint24 targetLevel) external {
        _foilQueuePerpetualTickets(targetLevel);
    }

    function runFoilWork(uint256 allowance) external returns (MineFlipGas.Result memory) {
        return _runFoilWork(allowance);
    }
}
