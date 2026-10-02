// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DegenerusGameStorage} from "../storage/DegenerusGameStorage.sol";
import {IsDGNRS} from "../interfaces/IsDGNRS.sol";
import {ContractAddresses} from "../ContractAddresses.sol";

/// @dev Daily and terminal entropy share identical recording, nudge and gap rules.
///      This base declares no storage; both delegate modules inline the same helpers.
abstract contract DegenerusGameRngUtils is DegenerusGameStorage {
    uint24 private constant GAP_BACKFILL_MAX_DAYS = _VRF_DEADMAN_DAYS + 1;

    /// @notice Finalized daily word and the nudges applied to its raw input.
    event DailyRngApplied(uint24 day, uint256 rawWord, uint256 nudges, uint256 finalWord);

    /// @dev Resolve the sentinel-stamped gambling-burn pool off `word`. Three call sites in this
    ///      module ran this identically; folded into one so the encoding is emitted once.
    function _resolvePendingRedemption(uint256 word) internal {
        IsDGNRS sdgnrs = IsDGNRS(ContractAddresses.SDGNRS);
        uint24 toResolve = sdgnrs.pendingResolveDay();
        if (toResolve != 0) {
            sdgnrs.resolveRedemptionPeriod(uint16(((word >> 8) % 151) + 25), toResolve);
            // The committed cohort consumes this session's final word before another
            // normal request is permitted, including recovery from a multi-day stall.
            sdgnrs.beginRedemptionSettlement(toResolve, word);
        }
    }

    function _swapTicketSlot() internal {
        ticketWriteSlot = !ticketWriteSlot;
        foilCursor = 0;
        foilGenerationDay = 0;
        foilFirstDrawDay = 0;
        ticketsFullyProcessed = false;
        _setRngComplete(false);
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
    ///      NOTE: resolveRedemptionPeriod is NOT called for backfilled gap days —
    ///      the redemption timer continued ticking in real time during the stall;
    ///      it resolves only on the current day via the normal rngGate path.
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
