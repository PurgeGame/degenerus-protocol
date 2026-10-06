// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {IDegenerusGame} from "../../contracts/interfaces/IDegenerusGame.sol";

/// @dev The activity score alone (Game's `playerActivityScore` also returns the wallet ID).
function activityScoreOf(address game, address player) view returns (uint256 score) {
    (score,) = IDegenerusGame(game).playerActivityScore(player);
}
