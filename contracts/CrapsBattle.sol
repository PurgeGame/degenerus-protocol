// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {SelectedCraps} from "./profiles/Selected.sol";
import {ICrapsEngine, IFlipCoin, IVaultOwnership, IGameCraps, IHighRollerReserve, ICoinflipStake, IReadCohortLifecycle} from "./CrapsInterfaces.sol";

contract CrapsBattle is SelectedCraps {}
