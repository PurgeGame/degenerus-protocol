// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {MintPaymentKind} from "../interfaces/IDegenerusGame.sol";
import {ContractAddresses} from "../ContractAddresses.sol";
import {GameBoonActions} from "./GameBoonActions.sol";

abstract contract GameBoonActionsEntries is GameBoonActions {
    function consumeCoinflipBoon_g2902(uint32 id) external returns (uint16) {
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();
        return _consumeActionBoon(id);
    }

    function consumeDecimatorBoon(uint32 id) external returns (uint16) {
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();
        return _consumeDecimatorBoost(id);
    }

    function giveBoon(uint32 deityId, uint32 recipientId, uint8 slot) external {
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();
        _issueDeityBoon(deityId, recipientId, slot);
    }
}
