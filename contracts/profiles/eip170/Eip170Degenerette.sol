// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DegenerusGameDegeneretteModule} from "../../modules/DegenerusGameDegeneretteModule.sol";
import {GameBetEntries} from "../../modules/GameBetEntries.sol";

contract Eip170Degenerette is DegenerusGameDegeneretteModule, GameBetEntries {
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
