// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {EntropyLib} from "../libraries/EntropyLib.sol";
import {RngTags} from "../libraries/RngTags.sol";

import {DegenerusGameStorage} from "../storage/DegenerusGameStorage.sol";
import {IsDGNRS} from "../interfaces/IsDGNRS.sol";
import {MintPaymentKind} from "../interfaces/IDegenerusGame.sol";
import {ContractAddresses} from "../ContractAddresses.sol";

/// @dev Daily and terminal entropy share recording and nudge rules.
///      This base declares no storage; both delegate modules inline the same helpers.
abstract contract DegenerusGameRngUtils is DegenerusGameStorage {
    /// @notice Recorded daily word and the nudges added to it for the coinflip alone.
    event DailyRngApplied(uint24 day, uint256 word, uint256 nudges);

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

    /// @dev Record the raw word and clear its frozen nudge receipt. Nudges move only the
    ///      coinflip: the returned coin word is the raw word plus the frozen count, so each
    ///      nudge reverses the coin's win bit. A recorded day word is never 0 ("no word") or
    ///      1 (rngGate's "request sent" return); the callback refuses both.
    function _applyDailyRng(uint24 day, uint256 word) internal returns (uint256 coinWord) {
        uint256 nudges = _nudgeCount();
        unchecked { coinWord = word + nudges; }
        _clearAppliedNudges();
        _recordDailyRng(day, word);
        lastVrfProcessedTimestamp = uint48(block.timestamp);
        emit DailyRngApplied(day, word, nudges);
    }
    /// @dev Move fresh contributions to the pending pool while a daily commitment is frozen.
    ///      The buffer is already empty: the last unfreeze left only its sentinel.
    function _freezePool() internal {
        prizePoolFrozen = true;
    }


}
