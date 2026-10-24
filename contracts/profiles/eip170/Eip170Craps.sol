// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {CrapsBattleCore} from "../../modules/CrapsBattleCore.sol";
import {CrapsLifecycleRouter} from "../../modules/CrapsLifecycleRouter.sol";

contract Eip170Craps is CrapsBattleCore, CrapsLifecycleRouter {}
