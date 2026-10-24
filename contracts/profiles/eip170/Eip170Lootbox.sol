// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DegenerusGameLootboxModule} from "../../modules/DegenerusGameLootboxModule.sol";

contract Eip170Lootbox is DegenerusGameLootboxModule {
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
}
