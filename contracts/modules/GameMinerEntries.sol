// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {MintPaymentKind} from "../interfaces/IDegenerusGame.sol";
import {ContractAddresses} from "../ContractAddresses.sol";
import {GameMiner} from "./GameMiner.sol";

abstract contract GameMinerEntries is GameMiner {
    function mineFlip(uint32 gasMultiplierBps) external {
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();
        _mineFlip(gasMultiplierBps);
    }

    function minerAction() external returns (uint8) {
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();
        return _minerAction();
    }
}
