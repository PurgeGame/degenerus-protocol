// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {ContractAddresses} from "../ContractAddresses.sol";
import {IDegenerusGame} from "../interfaces/IDegenerusGame.sol";
import {ICoinflip} from "../interfaces/ICoinflip.sol";
import {IDegenerusCoin} from "../interfaces/IDegenerusCoin.sol";
import {IDegenerusParimutuel} from "../interfaces/IDegenerusParimutuel.sol";
import {IsDGNRS} from "../interfaces/IsDGNRS.sol";
import {IDegenerusAffiliate} from "../interfaces/IDegenerusAffiliate.sol";
import {IDegenerusJackpots} from "../interfaces/IDegenerusJackpots.sol";
import {CrapsBattle} from "../CrapsBattle.sol";
import {WWXRP} from "../WWXRP.sol";
import {DGNRS} from "../DGNRS.sol";
import {AFKingSubscriptionToken} from "../AFKingSubscriptionToken.sol";
import {GNRUS} from "../GNRUS.sol";
import {ILinkTokenLike} from "../DegenerusAdmin.sol";
import {
    IVaultWinnings, IVaultPartialWinnings, IVaultAffiliateClaim, IVaultBatchAffiliateClaim
} from "../interfaces/IVaultPlayerActions.sol";

/// @notice Fixed player-call surface for the Vault. No configurable targets or selectors.
/// @dev The canonical selectors and overload aliases are ABI-checked by check-vault-player-actions.js. The destination enforces account
///      authorization, payment, timing and protocol-account restrictions. Reserve-token
///      transfers/approvals, loans, privileged settlement hooks and delegatecalls are absent.
///      Admin is absent too: sDGNRS.votingSupply excludes the Vault's treasury allocation, so the
///      Vault never proposes or votes. Seats move through the Vault's sweepNft.
library VaultPlayerActions {
    function isAllowed(address target, bytes4 selector) internal pure returns (bool) {
        if (target == ContractAddresses.GAME) {
            return selector == IDegenerusGame.mineFlip.selector || selector == IDegenerusGame.subscribe.selector
                || selector == IDegenerusGame.purchase.selector || selector == IDegenerusGame.redeemFlip.selector
                || selector == IDegenerusGame.buyDegenesisBox.selector
                || selector == IDegenerusGame.purchaseWhalePass.selector
                || selector == IDegenerusGame.purchaseLazyPass.selector
                || selector == IDegenerusGame.purchaseDeityPass.selector
                || selector == IDegenerusGame.placeDegeneretteBet.selector
                || selector == IDegenerusGame.reverseFlip.selector || selector == IDegenerusGame.decurse.selector
                || selector == IDegenerusGame.smite.selector || selector == IDegenerusGame.issueDeityBoon.selector
                || selector == IDegenerusGame.createSmurf.selector
                || selector == IDegenerusGame.setOperatorApproval.selector
                || selector == IDegenerusGame.sweepAccounts.selector
                || selector == IDegenerusGame.depositAfkingFunding.selector
                || selector == IDegenerusGame.withdrawAfkingFunding.selector
                || selector == IVaultWinnings.claimWinnings.selector
                || selector == IVaultPartialWinnings.claimWinnings.selector
                || selector == IDegenerusGame.claimWinningsStethFirst.selector
                || selector == IDegenerusGame.claimAfkingFlip.selector
                || selector == IDegenerusGame.claimBingo.selector
                || selector == IDegenerusGame.claimDeadVrf.selector
                || selector == IDegenerusGame.claimFoilMatch.selector
                || selector == IDegenerusGame.claimFoilMatchMany.selector
                || selector == IDegenerusGame.claimGoldenTicket.selector
                || selector == IDegenerusGame.claimWhalePass.selector
                || selector == IVaultAffiliateClaim.claimAffiliateDgnrs.selector
                || selector == IVaultBatchAffiliateClaim.claimAffiliateDgnrs.selector;
        }
        if (target == ContractAddresses.COINFLIP) {
            return selector == ICoinflip.depositCoinflip.selector
                || selector == ICoinflip.claimCoinflips.selector
                || selector == ICoinflip.claimCoinflipCarry.selector
                || selector == ICoinflip.setCoinflipAutoRebuy.selector
                || selector == ICoinflip.setCoinflipAutoRebuyTakeProfit.selector;
        }
        if (target == ContractAddresses.COIN) {
            return selector == IDegenerusCoin.decimatorBurn.selector;
        }
        if (target == ContractAddresses.CRAPS) {
            return selector == CrapsBattle.setPreferredBoard.selector
                || selector == CrapsBattle.amendSlip.selector
                || selector == CrapsBattle.createBattle.selector
                || selector == CrapsBattle.enterBattle.selector
                || selector == CrapsBattle.closeBattle.selector
                || selector == CrapsBattle.applyCrapsPasses.selector
                || selector == CrapsBattle.buyFutureCrapsDays.selector
                || selector == CrapsBattle.convertNormalToHigh.selector
                || selector == CrapsBattle.upgradeReservedDay.selector
                || selector == CrapsBattle.upgradeDayWindows.selector
                || selector == CrapsBattle.openBonusDay.selector
                || selector == CrapsBattle.enterBonusBattle.selector
                || selector == CrapsBattle.enterBonusDay.selector;
        }
        if (target == ContractAddresses.PARIMUTUEL) {
            return selector == IDegenerusParimutuel.placeBet.selector;
        }
        if (target == ContractAddresses.WWXRP) {
            return selector == WWXRP.withdraw.selector
                || selector == WWXRP.withdrawAcquired.selector
                || selector == WWXRP.enter.selector || selector == WWXRP.claim.selector;
        }
        if (target == ContractAddresses.SDGNRS) {
            return selector == IsDGNRS.burn.selector || selector == IsDGNRS.burnWrapped.selector
                || selector == IsDGNRS.claimRedemption.selector;
        }
        if (target == ContractAddresses.DGNRS) {
            return selector == DGNRS.burn.selector
                || selector == DGNRS.claimVested.selector
                || selector == DGNRS.yearSweep.selector;
        }
        if (target == ContractAddresses.AFFILIATE) {
            return selector == IDegenerusAffiliate.createAffiliateCode.selector
                || selector == IDegenerusAffiliate.referPlayer.selector
                || selector == IDegenerusAffiliate.claim.selector;
        }
        if (target == ContractAddresses.JACKPOTS) {
            return selector == IDegenerusJackpots.claimBafConsolation.selector;
        }
        if (target == ContractAddresses.AFKING_SUB_TOKEN) {
            return selector == AFKingSubscriptionToken.setSeatTraits.selector
                || selector == AFKingSubscriptionToken.approve.selector
                || selector == AFKingSubscriptionToken.setApprovalForAll.selector;
        }
        if (target == ContractAddresses.GNRUS) {
            return selector == GNRUS.vote.selector || selector == GNRUS.burn.selector;
        }
        // LINK is a foreign, sweepable token. This lets the Vault itself earn the LINK
        // donation credit; it grants no approval or access to stETH/FLIP reserves.
        if (target == ContractAddresses.LINK_TOKEN) {
            return selector == ILinkTokenLike.transferAndCall.selector;
        }
        return false;
    }
}
