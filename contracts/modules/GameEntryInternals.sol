// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {MintPaymentKind} from "../interfaces/IDegenerusGame.sol";
import {ContractAddresses} from "../ContractAddresses.sol";
import {GameComponentCall} from "./GameComponentCall.sol";
import {IGamePurchaseModule, IGameMinerModule, IGameBingoModule, IGameBetModule, IGameBoonActionsModule} from "../interfaces/IGameEntryModules.sol";

abstract contract GameEntryInternals is GameComponentCall {
    function _gamePurchase(uint32 buyerId, uint256 entryQuantityScaled, uint256 boxOrder, bytes32 affiliateCode, MintPaymentKind payKind) internal virtual {
        _componentDelegate(ContractAddresses.GAME_PURCHASE_MODULE, abi.encodeWithSelector(IGamePurchaseModule.purchase.selector, buyerId, entryQuantityScaled, boxOrder, affiliateCode, payKind));
    }

    function _gameCreateSmurf(bytes32 affiliateCode, MintPaymentKind payKind) internal virtual returns (uint32) {
        return abi.decode(_componentDelegate(ContractAddresses.GAME_PURCHASE_MODULE, abi.encodeWithSelector(IGamePurchaseModule.createSmurf.selector, affiliateCode, payKind)), (uint32));
    }

    function _gameRedeemFlip(uint32 id, uint256 entryQuantityScaled) internal virtual {
        _componentDelegate(ContractAddresses.GAME_PURCHASE_MODULE, abi.encodeWithSelector(IGamePurchaseModule.redeemFlip.selector, id, entryQuantityScaled));
    }

    function _gameWithdrawAfkingFunding(uint32 id, uint256 amount) internal virtual {
        _componentDelegate(ContractAddresses.GAME_PURCHASE_MODULE, abi.encodeWithSelector(IGamePurchaseModule.withdrawAfkingFunding.selector, id, amount));
    }

    function _gameBorrow(uint32 id, uint24 dueLevel, uint256 amount, uint256 minEthOut) internal virtual {
        _componentDelegate(ContractAddresses.GAME_PURCHASE_MODULE, abi.encodeWithSelector(IGamePurchaseModule.borrow.selector, id, dueLevel, amount, minEthOut));
    }

    function _gameRepay(uint32 id) internal virtual {
        _componentDelegate(ContractAddresses.GAME_PURCHASE_MODULE, abi.encodeWithSelector(IGamePurchaseModule.repay.selector, id));
    }

    function _gameSweepAccounts(uint32[] calldata ids) internal virtual returns (uint256, uint256) {
        return abi.decode(_componentDelegate(ContractAddresses.GAME_PURCHASE_MODULE, abi.encodeWithSelector(IGamePurchaseModule.sweepAccounts.selector, ids)), (uint256, uint256));
    }

    function _gameMineFlip(uint32 gasMultiplierBps) internal virtual {
        _componentDelegate(ContractAddresses.GAME_MINER_MODULE, abi.encodeWithSelector(IGameMinerModule.mineFlip.selector, gasMultiplierBps));
    }

    function _gameMinerAction() internal virtual returns (uint8) {
        return abi.decode(_componentDelegate(ContractAddresses.GAME_MINER_MODULE, abi.encodeWithSelector(IGameMinerModule.minerAction.selector)), (uint8));
    }

    function _gameClaimBingo(uint32 id, uint24 lvl, uint8 symbol, uint32[8] calldata slots) internal virtual {
        _componentDelegate(ContractAddresses.GAME_BINGO_MODULE, abi.encodeWithSelector(IGameBingoModule.claimBingo.selector, id, lvl, symbol, slots));
    }

    function _gameClaimAffiliateDgnrs(uint32 id) internal virtual {
        _componentDelegate(ContractAddresses.GAME_BINGO_MODULE, abi.encodeWithSelector(IGameBingoModule.claimAffiliateDgnrs.selector, id));
    }

    function _gamePlaceBet(uint32 id, uint8 currency, uint128 amountPerSpin, uint8 spinCount, uint8 symbol) internal virtual {
        _componentDelegate(ContractAddresses.GAME_DEGENERETTE_MODULE, abi.encodeWithSelector(IGameBetModule.placeDegeneretteBet.selector, id, currency, amountPerSpin, spinCount, symbol));
    }

    function _gameConsumeActionBoon(uint32 id) internal virtual returns (uint16) {
        return abi.decode(_componentDelegate(ContractAddresses.GAME_BOON_MODULE, abi.encodeWithSelector(IGameBoonActionsModule.consumeCoinflipBoon_g2902.selector, id)), (uint16));
    }

    function _gameConsumeDecimatorBoost(uint32 id) internal virtual returns (uint16) {
        return abi.decode(_componentDelegate(ContractAddresses.GAME_BOON_MODULE, abi.encodeWithSelector(IGameBoonActionsModule.consumeDecimatorBoon.selector, id)), (uint16));
    }

    function _gameIssueDeityBoon(uint32 deityId, uint32 recipientId, uint8 slot) internal virtual {
        _componentDelegate(ContractAddresses.GAME_BOON_MODULE, abi.encodeWithSelector(IGameBoonActionsModule.issueDeityBoon.selector, deityId, recipientId, slot));
    }
    function _gameRaiseSmurfBaseAllowance(uint32 mainId, uint16 newBase) internal virtual {
        _componentDelegate(ContractAddresses.GAME_PURCHASE_MODULE, abi.encodeWithSelector(IGamePurchaseModule.raiseSmurfBaseAllowance.selector, mainId, newBase));
    }
}
