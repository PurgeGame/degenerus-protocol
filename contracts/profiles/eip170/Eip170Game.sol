// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {GameFacade} from "../../modules/GameFacade.sol";
import {GameBoonActions} from "../../modules/GameBoonActions.sol";

contract Eip170Game is GameFacade, GameBoonActions {
    function _gameConsumeActionBoon(uint32 id) internal override returns (uint16) {
        return _consumeActionBoon(id);
    }
}
