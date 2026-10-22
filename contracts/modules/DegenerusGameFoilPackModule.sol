// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DegenerusGameFoilUserModule} from "./DegenerusGameFoilUserModule.sol";
import {DegenerusGameFoilWorkerModule} from "./DegenerusGameFoilWorkerModule.sol";

contract DegenerusGameFoilPackModule is DegenerusGameFoilUserModule, DegenerusGameFoilWorkerModule {}
