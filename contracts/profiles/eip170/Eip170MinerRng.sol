// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {GameMinerEntries} from "../../modules/GameMinerEntries.sol";
import {DegenerusGameRngModule} from "../../modules/DegenerusGameRngModule.sol";

contract Eip170MinerRng is GameMinerEntries, DegenerusGameRngModule {}
