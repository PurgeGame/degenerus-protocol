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
{
    function _boxResolveHumanBoxOrder(uint48 buffer, uint256 position, uint256 entry, uint256 rngWord, uint24 currentLevel)
        internal virtual override {
        _localboxResolveHumanBoxOrder(buffer, position, entry, rngWord, currentLevel);
    }

    function _boxResolveAfkingBox(uint32 id, uint256 amount, uint24 day, uint256 rngWord, uint16 activityScore)
        internal virtual override {
        _localboxResolveAfkingBox(id, amount, day, rngWord, activityScore);
    }

    function _boxResolveLootboxDirect(uint32 id, uint256 amount, uint256 rngWord, uint16 activityScore)
        internal virtual override {
        _localboxResolveLootboxDirect(id, amount, rngWord, activityScore);
    }

    function _boxRollBoxBoons(
        uint32 id,
        uint256 perBoxBudget,
        uint256 boxCount,
        uint256 originalAmount,
        uint24 currentLevel,
        uint256 seed,
        uint256 nonceBase
    ) internal virtual override {
        _localboxRollBoxBoons(id, perBoxBudget, boxCount, originalAmount, currentLevel, seed, nonceBase);
    }

    function _boxResolveWwxrpSpinFromBox(
        uint32 playerId,
        uint256 stake,
        uint16 activityScore,
        uint256 seed,
        uint8 symbol
    ) internal virtual override returns (uint256 wwxrpOut) {
        return _localboxResolveWwxrpSpinFromBox(playerId, stake, activityScore, seed, symbol);
    }

    function _boxResolveFlipSpinsFromBox(
        uint32 playerId,
        uint256 totalStake,
        uint16 activityScore,
        uint256 seed,
        uint8 symbol
    ) internal virtual override returns (uint256 flipOut) {
        return _localboxResolveFlipSpinsFromBox(playerId, totalStake, activityScore, seed, symbol);
    }

    function _boxResolveEthSpinFromBox(
        uint32 playerId,
        uint256 stake,
        uint16 activityScore,
        uint256 seed,
        uint8 symbol
    ) internal virtual override {
        _localboxResolveEthSpinFromBox(playerId, stake, activityScore, seed, symbol);
    }
}
