// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DegenerusGame} from "../../contracts/DegenerusGame.sol";

/// @dev Backed winnings, excluding the registration sentinel exposed by the raw balance view.
function claimableBalance(DegenerusGame game, address player) view returns (uint256) {
    uint256 balance = game.claimableWinningsOf(player);
    return balance > 1 ? balance - 1 : 0;
}
