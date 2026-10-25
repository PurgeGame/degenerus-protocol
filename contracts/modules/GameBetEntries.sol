// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {MintPaymentKind} from "../interfaces/IDegenerusGame.sol";
import {ContractAddresses} from "../ContractAddresses.sol";
import {GameDegeneretteBet} from "./GameDegeneretteBet.sol";

abstract contract GameBetEntries is GameDegeneretteBet {
    function betDegenerette(uint32 id, uint8 currency, uint128 amountPerSpin, uint8 spinCount, uint8 symbol) external payable {
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();
        _placeBet(id, currency, amountPerSpin, spinCount, symbol);
    }
}
