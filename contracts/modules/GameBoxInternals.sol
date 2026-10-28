// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {GameComponentCall} from "./GameComponentCall.sol";
import {ContractAddresses} from "../ContractAddresses.sol";
import {IDegenerusGameLootboxModule, IDegenerusGameBoonModule, IDegenerusGameDegeneretteModule} from "../interfaces/IDegenerusGameModules.sol";

/// @dev Shared resolver signatures for Game-storage box components.
abstract contract GameBoxInternals is GameComponentCall {
    error RngNotReady();

    function _boxResolveHumanBoxOrder(uint48 buffer, uint256 position, uint256 entry, uint256 rngWord, uint24 currentLevel)
        internal virtual {
        _componentDelegate(ContractAddresses.GAME_LOOTBOX_MODULE, abi.encodeWithSelector(IDegenerusGameLootboxModule.resolveHumanBoxOrder.selector, buffer, position, entry, rngWord, currentLevel));
    }

    function _boxResolveAfkingBox(uint32 id, uint256 amount, uint24 day, uint256 rngWord, uint16 activityScore)
        internal virtual {
        _componentDelegate(ContractAddresses.GAME_LOOTBOX_MODULE, abi.encodeWithSelector(IDegenerusGameLootboxModule.resolveAfkingBox.selector, id, amount, day, rngWord, activityScore));
    }

    function _boxResolveLootboxDirect(uint32 id, uint256 amount, uint256 rngWord, uint16 activityScore)
        internal virtual {
        _componentDelegate(ContractAddresses.GAME_LOOTBOX_MODULE, abi.encodeWithSelector(IDegenerusGameLootboxModule.resolveLootboxDirect.selector, id, amount, rngWord, activityScore));
    }

    function _boxRollBoxBoons(
        uint32 id,
        uint256 perBoxBudget,
        uint256 boxCount,
        uint256 originalAmount,
        uint24 currentLevel,
        uint256 seed,
        uint256 nonceBase
    ) internal virtual {
        _componentDelegate(ContractAddresses.GAME_BOON_MODULE, abi.encodeWithSelector(IDegenerusGameBoonModule.rollBoxBoons.selector, id, perBoxBudget, boxCount, originalAmount, currentLevel, seed, nonceBase));
    }

    function _boxResolveWwxrpSpinFromBox(
        uint32 playerId,
        uint256 stake,
        uint16 activityScore,
        uint256 seed,
        uint8 symbol
    ) internal virtual returns (uint256 wwxrpOut) {
        return abi.decode(_componentDelegate(ContractAddresses.GAME_DEGENERETTE_MODULE, abi.encodeWithSelector(IDegenerusGameDegeneretteModule.resolveWwxrpSpinFromBox.selector, playerId, stake, activityScore, seed, symbol)), (uint256));
    }

    function _boxResolveFlipSpinsFromBox(
        uint32 playerId,
        uint256 totalStake,
        uint16 activityScore,
        uint256 seed,
        uint8 symbol
    ) internal virtual returns (uint256 flipOut) {
        return abi.decode(_componentDelegate(ContractAddresses.GAME_DEGENERETTE_MODULE, abi.encodeWithSelector(IDegenerusGameDegeneretteModule.resolveFlipSpinsFromBox.selector, playerId, totalStake, activityScore, seed, symbol)), (uint256));
    }

    function _boxResolveEthSpinFromBox(
        uint32 playerId,
        uint256 stake,
        uint16 activityScore,
        uint256 seed,
        uint8 symbol
    ) internal virtual {
        _componentDelegate(ContractAddresses.GAME_DEGENERETTE_MODULE, abi.encodeWithSelector(IDegenerusGameDegeneretteModule.resolveEthSpinFromBox.selector, playerId, stake, activityScore, seed, symbol));
    }
}
