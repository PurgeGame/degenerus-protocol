// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DegenerusGameFoilCore} from "./DegenerusGameFoilCore.sol";
import {MintPaymentKind} from "../interfaces/IDegenerusGame.sol";

abstract contract DegenerusGameFoilUserModule is DegenerusGameFoilCore {
    function purchaseWithFoil(
        uint32 buyerId,
        uint256 entryQuantityScaled,
        uint256 boxOrder,
        bytes32 affiliateCode,
        MintPaymentKind payKind
    ) external payable {
        _foilPurchaseWithFoil(buyerId, entryQuantityScaled, boxOrder, affiliateCode, payKind);
    }

    function claimFoilMatch(
        uint32 id,
        uint256 day,
        uint256 ticketIndex
    ) external {
        _foilClaimFoilMatch(id, day, ticketIndex);
    }

    function claimGoldenTicket(uint32 accountId, uint24 lvl) external {
        _foilClaimGoldenTicket(accountId, lvl);
    }

    function claimFoilMatchMany(
        uint32[] calldata ids,
        uint24[] calldata drawDays,
        uint8[] calldata ticketIndexes
    ) external {
        _foilClaimFoilMatchMany(ids, drawDays, ticketIndexes);
    }
}
