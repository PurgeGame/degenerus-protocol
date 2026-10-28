// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DegenerusGameGameOverModule} from "../../modules/DegenerusGameGameOverModule.sol";
import {DegenerusGameDecimatorModule} from "../../modules/DegenerusGameDecimatorModule.sol";
import {DegenerusGameDegenesisModule} from "../../modules/DegenerusGameDegenesisModule.sol";
import {DegenerusGameFoilUserModule} from "../../modules/DegenerusGameFoilUserModule.sol";
import {DegenerusGameMintModule} from "../../modules/DegenerusGameMintModule.sol";
import {MintPaymentKind} from "../../interfaces/IDegenerusGame.sol";

/// @notice Terminal settlement, Degenesis, Decimator, foil claims and their explicit-value
///         purchases in Game storage.
contract GlamsterdamEndgame is DegenerusGameGameOverModule, DegenerusGameDecimatorModule,
    DegenerusGameDegenesisModule, DegenerusGameFoilUserModule, DegenerusGameMintModule
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
}
