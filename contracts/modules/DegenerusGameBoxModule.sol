// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {GameAfkingModule} from "./GameAfkingModule.sol";
import {DegenerusGameLootboxModule} from "./DegenerusGameLootboxModule.sol";
import {DegenerusGameBoonModule} from "./DegenerusGameBoonModule.sol";
import {DegenerusGameDegeneretteModule} from "./DegenerusGameDegeneretteModule.sol";

/// @notice Box, boon, AFKing, and Degenerette workers in Game storage.
contract DegenerusGameBoxModule is
    GameAfkingModule,
    DegenerusGameLootboxModule,
    DegenerusGameBoonModule,
    DegenerusGameDegeneretteModule
{}
