// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {CrapsViews} from "./CrapsViews.sol";
import {CrapsEngine} from "../../contracts/CrapsEngine.sol";

/// @dev Outcome injection for payout/rollback tests; layout and lifecycle stay unchanged.
contract MockableCrapsViews is CrapsViews {
    function _crapsSettleBattle(uint256 betId, uint256 header, uint256 chipFlip, uint256 bankroll,
        uint256 goal, uint48 bound, uint256 field, uint256 word)
        internal pure override returns (SlipResult memory)
    {
        return CrapsEngine(address(0xC6A6)).settleBattle(
            betId, header, chipFlip, bankroll, goal, bound, field, word);
    }
}
