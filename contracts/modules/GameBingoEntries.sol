// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {MintPaymentKind} from "../interfaces/IDegenerusGame.sol";
import {ContractAddresses} from "../ContractAddresses.sol";
import {GameBingo} from "./GameBingo.sol";

abstract contract GameBingoEntries is GameBingo {
    function claimBingo(uint32 id, uint24 lvl, uint8 symbol, uint32[8] calldata slots) external {
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();
        _claimBingo(id, lvl, symbol, slots);
    }

    function claimAffiliateDgnrs(uint32 id) external {
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();
        _claimAffiliateDgnrs(id);
    }
}
