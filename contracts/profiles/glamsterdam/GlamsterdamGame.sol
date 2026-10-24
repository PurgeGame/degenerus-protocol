// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;
import {GameActions} from "../../modules/GameActions.sol";

import {GameFacade, IDegenerusVaultOwnerGame} from "../../modules/GameFacade.sol";
import {GamePurchase} from "../../modules/GamePurchase.sol";
import {GameMiner} from "../../modules/GameMiner.sol";
import {GameDegeneretteBet} from "../../modules/GameDegeneretteBet.sol";
import {GameBingo} from "../../modules/GameBingo.sol";
import {MintPaymentKind} from "../../interfaces/IDegenerusGame.sol";

/// @notice Combined Game shell. All behavior lives in the shared components.
contract GlamsterdamGame is GameActions, GameFacade, GamePurchase, GameMiner, GameDegeneretteBet, GameBingo {
    function _gamePurchase(uint32 buyerId, uint256 entryQuantityScaled, uint256 boxOrder, bytes32 affiliateCode, MintPaymentKind payKind) internal override {
        _purchase(buyerId, entryQuantityScaled, boxOrder, affiliateCode, payKind);
    }

    function _gameCreateSmurf(bytes32 affiliateCode, MintPaymentKind payKind) internal override returns (uint32) {
        return _createSmurf(affiliateCode, payKind);
    }

    function _gameRedeemFlip(uint32 id, uint256 entryQuantityScaled) internal override {
        _redeemFlip(id, entryQuantityScaled);
    }

    function _gameWithdrawAfkingFunding(uint32 id, uint256 amount) internal override {
        _withdrawAfkingFunding(id, amount);
    }

    function _gameBorrow(uint32 id, uint24 dueLevel, uint256 amount, uint256 minEthOut) internal override {
        _borrow(id, dueLevel, amount, minEthOut);
    }

    function _gameRepay(uint32 id) internal override {
        _repay(id);
    }

    function _gameSweepAccounts(uint32[] calldata ids) internal override returns (uint256, uint256) {
        return _sweepAccounts(ids);
    }

    function _gameMineFlip(uint32 gasMultiplierBps) internal override {
        _mineFlip(gasMultiplierBps);
    }

    function _gameMinerAction() internal override returns (uint8) {
        return _minerAction();
    }

    function _gameClaimBingo(uint32 id, uint24 lvl, uint8 symbol, uint32[8] calldata slots) internal override {
        _claimBingo(id, lvl, symbol, slots);
    }

    function _gameClaimAffiliateDgnrs(uint32 id) internal override {
        _claimAffiliateDgnrs(id);
    }

    function _gamePlaceBet(uint32 id, uint8 currency, uint128 amountPerSpin, uint8 spinCount, uint8 symbol) internal override {
        _placeBet(id, currency, amountPerSpin, spinCount, symbol);
    }

    function _gameConsumeActionBoon(uint32 id) internal override returns (uint16) {
        return _consumeActionBoon(id);
    }

    function _gameConsumeDecimatorBoost(uint32 id) internal override returns (uint16) {
        return _consumeDecimatorBoost(id);
    }

    function _gameIssueDeityBoon(uint32 deityId, uint32 recipientId, uint8 slot) internal override {
        _issueDeityBoon(deityId, recipientId, slot);
    }
    function _gameRaiseSmurfBaseAllowance(uint32 mainId, uint16 newBase) internal override {
        _raiseSmurfBaseAllowance(mainId, newBase);
    }
    function _gameDrainAffiliateBases(uint256 ids, uint256 uplines) internal override returns (uint256, uint256, uint256) {
        return _actionDrainAffiliateBases(ids, uplines);
    }

    function _gameRegisterWallet_g9539(address owner, bool allocate) internal override returns (uint32 id) {
        return _actionRegisterWallet_g9539(owner, allocate);
    }

    function _gameRegisterWalletIdentity(address owner) internal override returns (uint32 id) {
        return _actionRegisterWalletIdentity(owner);
    }

    function _gameRecordAfkingSecondary(uint32 id, uint16 amount) internal override {
        _actionRecordAfkingSecondary(id, amount);
    }

    function _gameFloorAfkingStreakBase(uint32 id, uint16 floor) internal override {
        _actionFloorAfkingStreakBase(id, floor);
    }

    function _gamePayRecordSdgnrs(
        uint32 id,
        uint256 shareBps
    ) internal override returns (uint256 paid, address payee) {
        return _actionPayRecordSdgnrs(id, shareBps);
    }

    function _gameSetOperatorApproval(uint32 id, address operator, bool approved) internal override {
        _actionSetOperatorApproval(id, operator, approved);
    }

    function _gameSetLootboxRngThreshold(uint256 newThreshold) internal override {
        _actionSetLootboxRngThreshold(newThreshold);
    }

    function _gameSetMiddayMaxBasefee(uint256 newGwei) internal override {
        _actionSetMiddayMaxBasefee(newGwei);
    }

    function _gameClaimWinnings(uint32 id) internal override {
        _actionClaimWinnings(id);
    }

    function _gameClaimWinnings(uint32 id, uint256 amount) internal override {
        _actionClaimWinnings(id, amount);
    }

    function _gameClaimWinningsStethFirst() internal override {
        _actionClaimWinningsStethFirst();
    }

    function _gameDepositAfkingFunding(uint32 id) internal override {
        _actionDepositAfkingFunding(id);
    }

    function _gameAdminSwapEthForStEth(
        address recipient,
        uint256 amount
    ) internal override {
        _actionAdminSwapEthForStEth(recipient, amount);
    }

    function _gameAdminStakeEthForStEth(uint256 amount) internal override {
        _actionAdminStakeEthForStEth(amount);
    }

    function _gameReverseFlip(uint256 expectedCost) internal override {
        _actionReverseFlip(expectedCost);
    }
}
