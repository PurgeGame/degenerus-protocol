// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DegenerusGameStorage} from "../storage/DegenerusGameStorage.sol";

abstract contract GameRngNudge is DegenerusGameStorage {
    uint256 private constant RNG_NUDGE_BASE_COST = 100;
    function _currentNudgeCost(
        uint256 reversals
    ) internal pure returns (uint256 cost) {
        cost = RNG_NUDGE_BASE_COST;
        while (reversals != 0) {
            cost = (cost * 15) / 10;
            unchecked {
                --reversals;
            }
        }
    }
}
