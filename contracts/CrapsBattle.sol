// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Eip170Craps} from "./profiles/eip170/Eip170Craps.sol";
import {IFlipCoin, IGameCraps, ICoinflipStake, IReadCohortLifecycle} from "./CrapsInterfaces.sol";

contract CrapsBattle is Eip170Craps {}
