// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DegenerusGameBoonModule} from "../../modules/DegenerusGameBoonModule.sol";
import {GameBoonActionsEntries} from "../../modules/GameBoonActionsEntries.sol";

contract Eip170Boon is DegenerusGameBoonModule, GameBoonActionsEntries {
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
}
