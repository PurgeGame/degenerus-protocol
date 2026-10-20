// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {ContractAddresses} from "../ContractAddresses.sol";
import {DegenerusVault} from "../DegenerusVault.sol";
import {DegenerusAdmin} from "../DegenerusAdmin.sol";
import {DegenerusGame} from "../DegenerusGame.sol";
import {WWXRP} from "../WWXRP.sol";
import {CrapsBattle} from "../CrapsBattle.sol";
import {GNRUS} from "../GNRUS.sol";
import {Icons32Data} from "../Icons32Data.sol";
import {DegenerusDeityPass} from "../DegenerusDeityPass.sol";
import {DegenerusRecordBounty} from "../DegenerusRecordBounty.sol";
import {AFKingSubscriptionToken} from "../AFKingSubscriptionToken.sol";

/// @notice Immutable owner call surface. No token custody operations or executor self-calls.
/// @dev Target-side conditions and the Vault's nested player allowlist still apply.
library OwnerActions {
    function isAllowed(address target, bytes4 selector) internal pure returns (bool) {
        if (target == ContractAddresses.VAULT) {
            return selector == DegenerusVault.playerAction.selector
                || selector == DegenerusVault.spendDegenesis.selector
                || selector == DegenerusVault.setLiquidationBuyFallback.selector
                || selector == DegenerusVault.crapsComp.selector
                || selector == DegenerusVault.crapsCompDonate.selector
                || selector == DegenerusVault.setCrapsCompAllowance.selector
                || selector == DegenerusVault.wwxrpMint.selector
                || selector == DegenerusVault.afkingSeatMint.selector
                || selector == DegenerusVault.dgnrsUnwrapTo.selector
                || selector == DegenerusVault.sweepToken.selector
                || selector == DegenerusVault.sweepNft.selector;
        }
        if (target == ContractAddresses.ADMIN) {
            return selector == DegenerusAdmin.retryGameRng.selector
                || selector == DegenerusAdmin.retrySubCancel.selector
                || selector == DegenerusAdmin.propose.selector
                || selector == DegenerusAdmin.proposeFeedSwap.selector
                || selector == DegenerusAdmin.swapGameEthForStEth.selector;
        }
        if (target == ContractAddresses.GAME) {
            return selector == DegenerusGame.setLootboxRngThreshold.selector
                || selector == DegenerusGame.setMiddayMaxBasefee.selector
                || selector == DegenerusGame.setThanosLevel.selector
                || selector == DegenerusGame.raiseSmurfBaseAllowance.selector
                || selector == DegenerusGame.adminStakeEthForStEth.selector;
        }
        if (target == ContractAddresses.WWXRP) {
            return selector == WWXRP.setGameMintScale.selector || selector == WWXRP.setTrustedMinter.selector
                || selector == WWXRP.vaultMintTo.selector;
        }
        if (target == ContractAddresses.CRAPS) {
            return selector == CrapsBattle.createBattle.selector || selector == CrapsBattle.setBattleCreator.selector;
        }
        if (target == ContractAddresses.GNRUS) {
            return selector == GNRUS.setCharity.selector || selector == GNRUS.vaultRedeemFor.selector
                || selector == GNRUS.sweepResidualToVault.selector;
        }
        if (target == ContractAddresses.ICONS_32) {
            return selector == Icons32Data.setPaths.selector || selector == Icons32Data.setSymbols.selector
                || selector == Icons32Data.finalize.selector;
        }
        if (target == ContractAddresses.DEITY_PASS) {
            return selector == DegenerusDeityPass.setRenderer.selector || selector == DegenerusDeityPass.setRenderColors.selector;
        }
        if (target == ContractAddresses.RECORD_BOUNTY) {
            return selector == DegenerusRecordBounty.setRenderer.selector || selector == DegenerusRecordBounty.setRenderColors.selector;
        }
        if (target == ContractAddresses.AFKING_SUB_TOKEN) {
            return selector == AFKingSubscriptionToken.setRenderer.selector;
        }
        return false;
    }
}
