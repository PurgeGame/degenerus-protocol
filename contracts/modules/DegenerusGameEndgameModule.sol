// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DegenerusGameGameOverModule} from "./DegenerusGameGameOverModule.sol";
import {DegenerusGameDecimatorModule} from "./DegenerusGameDecimatorModule.sol";
import {DegenerusGameDegenesisModule} from "./DegenerusGameDegenesisModule.sol";
import {DegenerusGameFoilUserModule} from "./DegenerusGameFoilUserModule.sol";

import {GamePurchase} from "./GamePurchase.sol";
import {MintPaymentKind} from "../interfaces/IDegenerusGame.sol";

/// @notice Terminal settlement, Degenesis, Decimator and foil claims in Game storage.
contract DegenerusGameEndgameModule is DegenerusGameGameOverModule, DegenerusGameDecimatorModule,
    DegenerusGameDegenesisModule, DegenerusGameFoilUserModule, GamePurchase
{
    function _endgameSplitDegenesis() internal override {
        _endgameDegenesisSplit();
    }

    function _foilPurchaseWith(uint32 buyerId, uint256 quantity, uint256 boxOrder, bytes32 affiliateCode,
        MintPaymentKind payKind, uint256 fresh) internal override
    {
        _purchaseWith(buyerId, quantity, boxOrder, affiliateCode, payKind, fresh, 0);
    }

    function _degenesisPurchaseWith(uint32 recipientId, uint256 quantity, uint256 boxOrder) internal override {
        _purchaseWith(recipientId, quantity, boxOrder, bytes32(0), MintPaymentKind.Claimable, 0, VAULT_WALLET_ID);
    }

    function _accruePurchaseDegenesisCredit(uint32, uint256) internal override {}

    function _accrueAdapterDegenesisCredit(uint32 buyerId, uint256 cost, uint32 payerId) internal override {
        if (payerId != VAULT_WALLET_ID) _accrueDegenesisCredit(buyerId, cost);
    }
}
