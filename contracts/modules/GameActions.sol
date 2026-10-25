// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {GameFacade, IDegenerusVaultOwnerGame} from "./GameFacade.sol";
import {GameHooks} from "./GameHooks.sol";
import {GameRngNudge} from "./GameRngNudge.sol";
import {DegenerusGamePayoutUtils} from "./DegenerusGamePayoutUtils.sol";
import {GameAfkingClaims} from "./GameAfkingClaims.sol";
import {ContractAddresses} from "../ContractAddresses.sol";
import {IStETH} from "../interfaces/IStETH.sol";
import {IsDGNRS} from "../interfaces/IsDGNRS.sol";

/// @dev Account administration and custody entries, with the original caller preserved.
abstract contract GameActions is GameRngNudge, GameHooks, DegenerusGamePayoutUtils, GameAfkingClaims {
    IStETH private constant actionSteth = IStETH(ContractAddresses.STETH_TOKEN);
    IDegenerusVaultOwnerGame private constant actionVault = IDegenerusVaultOwnerGame(ContractAddresses.VAULT);
    uint256 private constant RECORD_SDGNRS_SCALE_DIV = 500;
    function _claimWinningsWithCurse(uint32 id, uint256 maxClaim) private {
        address payee;
        (id, payee) = _resolveAccountPayee(id);
        _claimWinningsInternal(id, payee, false, maxClaim);
        _maybeCurse(id);
    }

    function _claimWinningsInternal(uint32 id, address payee, bool stethFirst, uint256 maxClaim) private {
        if (_goRead(GO_SWEPT_SHIFT, GO_SWEPT_MASK) != 0) revert AlreadySwept();
        if (gameOver && id == SDGNRS_WALLET_ID) _releaseRedemptionReserve();
        // One packed load: claimable is the low half, afking the high half. The read reuse
        // below and the debit both ride this single SLOAD (no external call intervenes). An
        // address with no wallet ID reads the always-empty ID-0 word and reverts below.
        uint256 packed = balancesPacked[id];
        uint256 amount = uint128(packed);
        // Post-gameOver the claim ALSO pays the caller's prepaid
        // afking ETH (lazy per-player merge — no unbounded loop). Pre-gameOver afkingFunding
        // stays its own bucket (spent by afking auto-buys / reclaimed via withdrawAfkingFunding).
        // Both this merge and withdrawAfkingFunding zero the SAME bucket → no double-spend.
        uint256 afking = gameOver ? (packed >> 128) : 0;
        uint256 claimDebit;
        unchecked {
            if (amount > 1) {
                claimDebit = amount - 1; // available, leaving the 1-wei sentinel
            }
        }
        // Cap the claimable draw to maxClaim (partial cashout), after game over too.
        if (claimDebit > maxClaim) {
            claimDebit = maxClaim;
        }
        uint256 payout;
        unchecked {
            payout = claimDebit + afking;
        }
        if (payout == 0) revert NothingToClaim();
        // Debit both halves in one store from the load above. _debitClaimableAndAfking's two
        // Insolvent guards are provably dead here: claimDebit <= amount-1 < uint128(packed), and
        // afking is packed>>128 (or 0) — neither half can borrow, so the subtraction is
        // byte-identical to the helper's (which stays for its other callers).
        balancesPacked[id] = packed - claimDebit - (afking << 128);
        claimablePool -= uint128(payout); // CEI: update state before external call (checked math)
        emit GameFacade.WinningsClaimed(id, payout, uint128(amount - claimDebit));
        if (stethFirst) {
            _payoutWithEthFallback(payee, payout);
        } else {
            _payoutWithStethFallback(payee, payout);
        }
    }

    function _payoutWithEthFallback(address to, uint256 amount) private {
        if (amount == 0) return;

        uint256 stBal = actionSteth.balanceOf(address(this));
        uint256 stSend = amount <= stBal ? amount : stBal;
        _transferSteth(to, stSend);

        uint256 remaining = amount - stSend;
        if (remaining == 0) return;

        uint256 ethBal = address(this).balance;
        if (ethBal < remaining) revert Insolvent();
        (bool ok, ) = payable(to).call{value: remaining}("");
        if (!ok) revert TransferFailed();
    }

    function _actionDrainAffiliateBases(uint256 ids, uint256 uplines) internal returns (uint256, uint256, uint256) {
        return _drainAffiliateBases(ids, uplines);
        }

    function _actionRegisterWallet_g9539(address owner, bool allocate) internal returns (uint32 id) {
        return _registerWallet(owner, allocate);
        }

    function _actionRegisterWalletIdentity(address owner) internal returns (uint32 id) {
        return _registerWalletIdentity(owner);
        }

    function _actionRecordAfkingSecondary(uint32 id, uint16 amount) internal  {
        _recordAfkingSecondary(id, amount);
        }

    function _actionFloorAfkingStreakBase(uint32 id, uint16 floor) internal  {
        _floorAfkingStreakBase(id, floor);
        }

    function _actionPayRecordSdgnrs(
        uint32 id,
        uint256 shareBps
    ) internal returns (uint256 paid, address payee) {
        if (msg.sender != ContractAddresses.COINFLIP) revert Unauthorized();
        payee = _payee(_walletElement(id));
        if (shareBps == 0) return (0, payee);
        uint256 payout = (dgnrs.poolBalance(IsDGNRS.Pool.Reward) * shareBps) /
            (10_000 * RECORD_SDGNRS_SCALE_DIV);
        if (payout != 0) paid = dgnrs.transferFromPool(IsDGNRS.Pool.Reward, payee, payout);
        }

    function _actionSetOperatorApproval(uint32 id, address operator, bool approved) internal  {
        if (operator == address(0)) revert ZeroAddress();
        if (id == 0) {
            id = _requireWalletId(msg.sender);
        } else {
            (, address payee) = _accountKeys(id);
            if (payee != msg.sender) revert NotApproved();
        }
        operatorApprovals[id][operator] = approved;
        emit GameFacade.OperatorApproval(id, operator, approved);
        }

    function _actionSetLootboxRngThreshold(uint256 newThreshold) internal  {
        if (!actionVault.isVaultOwner(msg.sender)) revert OnlyVault();
        if (newThreshold == 0) revert ZeroValue();
        uint256 prev = _unpackMilliEthToWei(uint64(_lrRead(LR_THRESHOLD_SHIFT, LR_THRESHOLD_MASK)));
        if (newThreshold == prev) {
            emit GameFacade.LootboxRngThresholdUpdated(prev, newThreshold);
            return;
        }
        _lrWrite(LR_THRESHOLD_SHIFT, LR_THRESHOLD_MASK, _packEthToMilliEth(newThreshold));
        emit GameFacade.LootboxRngThresholdUpdated(prev, newThreshold);
        }

    function _actionSetMiddayMaxBasefee(uint256 newGwei) internal  {
        if (!actionVault.isVaultOwner(msg.sender)) revert OnlyVault();
        if (newGwei > MIDDAY_MAX_BASEFEE_GWEI_CAP) revert GameFacade.OutOfBounds();
        uint256 prev = _lrRead(LR_MAX_BASEFEE_SHIFT, LR_MAX_BASEFEE_MASK);
        _lrWrite(LR_MAX_BASEFEE_SHIFT, LR_MAX_BASEFEE_MASK, newGwei);
        emit MiddayMaxBasefeeUpdated(prev, newGwei);
        }

    function _actionClaimWinnings(uint32 id) internal  {
        _claimWinningsWithCurse(id, type(uint256).max);
        }

    function _actionClaimWinnings(uint32 id, uint256 amount) internal  {
        _claimWinningsWithCurse(id, amount);
        }

    function _actionClaimWinningsStethFirst() internal  {
        if (msg.sender != ContractAddresses.VAULT) revert OnlyVault();
        _claimWinningsInternal(VAULT_WALLET_ID, msg.sender, true, type(uint256).max);
        }

    function _actionDepositAfkingFunding(uint32 id) internal  {
        if (gameOver) revert GameOver();
        _requireAllocated(id);
        _creditAfkingValue(id, msg.value);
        }

    function _actionAdminSwapEthForStEth(
        address recipient,
        uint256 amount
    ) internal  {
        if (msg.sender != ContractAddresses.ADMIN) revert OnlyAdmin();
        if (recipient == address(0)) revert ZeroAddress();
        if (amount == 0 || msg.value != amount) revert GameFacade.ValueMismatch();

        uint256 stBal = actionSteth.balanceOf(address(this));
        if (stBal < amount) revert Insolvent();
        if (!actionSteth.transfer(recipient, amount)) revert TransferFailed();
        emit AdminSwapEthForStEth(recipient, amount);
        }

    function _actionAdminStakeEthForStEth(uint256 amount) internal  {
        if (!actionVault.isVaultOwner(msg.sender)) revert OnlyVault();
        if (amount == 0) revert ZeroValue();

        uint256 ethBal = address(this).balance;
        if (ethBal < amount) revert Insolvent();
        // Vault and sDGNRS claimable (including its redemption reserve) can be settled in stETH
        uint256 stethSettleable = _claimableOf(VAULT_WALLET_ID) +
            _claimableOf(SDGNRS_WALLET_ID) + _redemptionReserve();
        uint256 reserve = claimablePool > stethSettleable
            ? claimablePool - stethSettleable
            : 0;
        reserve += _vrfNativeTarget();
        if (ethBal <= reserve) revert Insolvent();
        uint256 stakeable = ethBal - reserve;
        if (amount > stakeable) revert Insolvent();

        // submit() returns shares minted, not a stETH amount, and the value is intentionally
        // ignored: nothing here validates the mint. Relies on Lido minting stETH ~1:1 for ETH.
        try actionSteth.submit{value: amount}(address(0)) returns (uint256) {} catch {
            revert TransferFailed();
        }
        emit AdminStakeEthForStEth(amount);
        }

    function _actionReverseFlip(uint256 expectedCost) internal  {
        if (rngLockedFlag) revert RngLocked();
        // A nudge shifts the next word by +1, and the terminal path applies pending
        // nudges to the word it publishes. Past the liveness trigger that word is the
        // committed terminal word, already public and already known to select the
        // winning traits, so a nudge bought here is a post-reveal steer of the final
        // payout rather than an influence on an unknown future word.
        if (_livenessTriggered()) revert E();
        uint256 reversals = _nudgeCount();
        if (reversals >= RNG_NUDGE_CAP) revert GameFacade.NudgeCapReached();
        uint256 cost = _currentNudgeCost(reversals);
        if (cost != expectedCost) revert GameFacade.NudgeCostChanged();
        coin.burnCoin(msg.sender, cost);
        uint256 newCount = reversals + 1;
        // The 255 cap fits the low byte; the packed setter preserves neighboring flags.
        _setNudgeCount(newCount);
        emit GameFacade.ReverseFlip(msg.sender, newCount, cost);
        }
}
