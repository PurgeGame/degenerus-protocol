// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DegenerusGameStorage} from "../storage/DegenerusGameStorage.sol";
import {IsDGNRS} from "../interfaces/IsDGNRS.sol";
import {MintPaymentKind} from "../interfaces/IDegenerusGame.sol";
import {ContractAddresses} from "../ContractAddresses.sol";

/// @dev Daily and terminal entropy share identical recording, nudge and gap rules.
///      This base declares no storage; both delegate modules inline the same helpers.
abstract contract DegenerusGameRngUtils is DegenerusGameStorage {
    uint24 private constant GAP_BACKFILL_MAX_DAYS = _VRF_DEADMAN_DAYS + 1;

    /// @notice Finalized daily word and the nudges applied to its raw input.
    event DailyRngApplied(uint24 day, uint256 rawWord, uint256 nudges, uint256 finalWord);

    /// @dev Isolate the whole priced pull from ordinary spending. Only settlement legs may
    ///      consume the reserve; it remains inside claimablePool until paid or recycled.
    function _closeRedemptionBatch() internal {
        // Requests need the read certificate, so the previous batch has finished settling.
        _releaseRedemptionReserve();
        uint256 claimable = _claimableOf(SDGNRS_WALLET_ID);
        uint256 pull = IsDGNRS(ContractAddresses.SDGNRS).closeRedemptionBatch(claimable);
        if (pull == 0) return;
        _debitClaimable(SDGNRS_WALLET_ID, pull);
        _setRedemptionReserve(pull);
        emit ClaimableSpent(SDGNRS_WALLET_ID, pull, claimable - pull, MintPaymentKind.Internal, pull);
    }

    function _swapTicketSlot() internal {
        ticketWriteSlot = !ticketWriteSlot;
        ticketsFullyProcessed = false;
        _setRngComplete(false);
    }

    /// @dev Daily request and the one terminal swap only: a mid-day request never moves
    ///      foil packs, so every pack generates from a daily word. The two counts swap with
    ///      their cohorts; a drained read cohort's zero count becomes the new write count.
    function _swapFoilSlot() internal {
        foilWriteSlot = !foilWriteSlot;
        foilCursor = 0;
        foilGenerationDay = 0;
        foilFirstDrawDay = 0;
        (foilWriteCount, foilReadCount) = (foilReadCount, foilWriteCount);
    }

    function _finalizeLootboxRng(uint256 rngWord) internal {
        uint48 index = _rngReadBuffer();
        if (_rngSessionPublished()) return;
        _setRngSessionPublished(true);
        emit LootboxRngApplied(index, rngWord, vrfRequestId);
    }

    /// @dev Fill packed coinflip results and settle funding for gap days
    ///      caused by VRF stall. Coinflip uses double-or-nothing payouts and raw win bits
    ///      1..31, anchored at startDay;
    ///      other daily consumers retain the final gap day's keccak256(vrfWord, gapDay).
    ///      NOTE: Gap days get zero nudges (totalFlipReversals not consumed).
    ///      NOTE: sDGNRS redemption batches are keyed by request, not by day, so gap days
    ///      resolve none; the batch the request closed settles on its word.
    /// @param vrfWord The first post-gap VRF random word.
    /// @param startDay First gap day (dailyIdx + 1).
    /// @param endDay Current day (exclusive — not backfilled, handled by normal path).
    function _backfillGapDays(uint256 vrfWord, uint24 startDay, uint24 endDay) internal {
        // Bound the number of per-day settlements. A live gap never reaches the bound (the deadman ends the game
        // first); on the normal ending the days past it hold no ticket or foil entry.
        if (endDay - startDay > GAP_BACKFILL_MAX_DAYS) endDay = startDay + GAP_BACKFILL_MAX_DAYS;
        coinflip.processCoinflipGap(vrfWord, startDay, endDay);
        // Retain just the last derived word in the two-slot ring.
        if (endDay > startDay) {
            uint24 yesterday = endDay - 1;
            uint256 word = uint256(keccak256(abi.encodePacked(vrfWord, yesterday)));
            _recordDailyRng(yesterday, word == 0 ? 1 : word);
        }
    }

    /// @dev Record the callback-finalized word and clear its frozen nudge receipt. A recorded
    ///      day word is never 0 ("no word") or 1 (rngGate's "request sent" return): a
    ///      callback-finalized word of 0/1 is refused and recovered by the existing retry.
    function _applyDailyRng(uint24 day, uint256 finalWord) internal returns (uint256) {
        uint256 nudges = _nudgeCount();
        uint256 rawWord = _rawDailyRngWord(finalWord);
        _clearAppliedNudges();
        _recordDailyRng(day, finalWord);
        lastVrfProcessedTimestamp = uint48(block.timestamp);
        emit DailyRngApplied(day, rawWord, nudges, finalWord);
        return finalWord;
    }
    /// @dev Move fresh contributions to the pending pool while a daily commitment is frozen.
    function _freezePool() internal {
        if (!prizePoolFrozen) {
            prizePoolFrozen = true;
            uint256 futureBal = _getFuturePrizePool();
            uint256 seed = futureBal / 100;
            _setFuturePrizePool(futureBal - seed);
            // The seed opens the pending buffer; buys route here until the unfreeze.
            _setPendingPools(0, uint128(seed));
        }
    }


}
