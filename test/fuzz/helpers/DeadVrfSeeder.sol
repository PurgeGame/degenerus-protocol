// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DegenerusGame} from "../../../contracts/DegenerusGame.sol";
import {TicketQueueStorage as TQ} from "./TicketQueueStorage.sol";
import {BucketSeed} from "../../helpers/BucketSeed.sol";

/// @dev Etch overlay to seed an exact dead-VRF terminal state; every measured call still runs
///      the production DegenerusGame runtime (restored after seeding).
contract DeadVrfSeeder is DegenerusGame, BucketSeed {
    function seedDeadStall(uint24 lvl) external {
        TQ.retireCompleted(address(this), lvl);
        uint24 day = _simulatedDayIndex();
        purchaseStartDay = day - 10;
        dailyIdx = day - 15;
        level = lvl;
        jackpotPhaseFlag = false;
        lastPurchaseDay = false;
        phaseTransitionActive = false;
        rngLockedFlag = true;
        rngWordCurrent = RNG_WORD_WAITING;
        vrfRequestId = 777;
        _setRngRequestActive(true);
        _setRngSessionPublished(false);
        rngRequestTime = uint48(block.timestamp - 15 days);
        ticketsFullyProcessed = true;
        prizePoolFrozen = false;
    }

    function seedCreated(uint24 lvl, uint8 trait, address player, uint256 n) external {
        _seedBucket(lvl, trait, player, n);
    }

    function seedQueued(uint24 lvl, bool writeSide, address player, uint32 entries, uint8 rem)
        external
        returns (uint32 posPlusOne)
    {
        uint24 rk = writeSide ? _tqWriteKey(lvl) : _tqReadKey(lvl);
        _seedQueued(rk, lvl, player, (uint80(entries) << 8) | uint80(rem));
        posPlusOne = _walletIdOf(player);
    }

    function seedFuture(uint24 lvl, address player, uint32 entries) external returns (uint32) {
        _seedQueued(_tqFarFutureKey(lvl), lvl, player, uint80(entries) << 8);
        return _walletIdOf(player);
    }

    function pendingWord(uint24 lvl, address player) external view returns (uint256) {
        return ticketPending[_walletIdOf(player)];
    }

    /// @dev Append a pack to cohort `resolveDay & 1` at that cohort's count (the foil queue is
    ///      manually addressed; its counts live in the foil cursor slot).
    function seedFoil(uint24 lvl, uint24 resolveDay, address player) external returns (uint256 index) {
        uint24 key = resolveDay & 1;
        uint256 id = uint256(_seedWallet(player));
        index = _foilCount(key);
        uint256 slot = _foilSlot(key, index);
        uint256 pack = (id << 192) | (uint256(lvl) << 160);
        assembly ("memory-safe") { sstore(slot, pack) }
        if (key == _foilWriteKey()) foilWriteCount = uint32(index + 1);
        else foilReadCount = uint32(index + 1);
    }

    function deadState()
        external
        view
        returns (uint256 pot, uint256 total, uint256 created, uint256 uncreated, uint256 traits, uint256 left)
    {
        return (deadPot, deadTotal, deadCreated, deadUncreated, deadTraitCount, deadUncreatedLeft);
    }

    function sealedDay() external view returns (uint24) {
        return dailyIdx;
    }

    /// @dev Day `s` (30 days ago) is stuck in processing with its word delivered (and, if
    ///      `applied`, already recorded); nothing has sealed since, so the deadman has fired.
    function seedStuckDay(uint24 lvl, uint256 word, bool applied) external returns (uint24 s) {
        uint24 day = _simulatedDayIndex();
        s = day - 30;
        purchaseStartDay = s - 5;
        dailyIdx = s - 1;
        level = lvl;
        jackpotPhaseFlag = false;
        lastPurchaseDay = false;
        phaseTransitionActive = false;
        rngLockedFlag = true;
        rngWordCurrent = word < 2 ? RNG_WORD_WAITING : word;
        vrfRequestId = 777;
        _setRngRequestActive(true);
        _setRngSessionPublished(false);
        rngRequestTime = uint48(block.timestamp - 30 days);
        _recordDailyRng(s, applied ? word : 0);
        if (applied) coinflip.processCoinflipPayouts(0, word, s);
        ticketsFullyProcessed = true;
        prizePoolFrozen = false;
        // The stuck request's reserved lootbox index, not yet worded.
        uint48 idx = _rngWriteBuffer();
        rngFlagsAndNudges = (rngFlagsAndNudges & ~(uint16(1) << 12)) | (uint16((idx + 1) & 1) << 12);
    }

    function vrfDeadView() external view returns (bool) {
        return _vrfDead();
    }

    /// @dev Past the purchase deadline at the start of a caught-up day with no word, VRF alive.
    ///      A mid-day request committed the read side and its lootbox word has landed.
    function seedDeadlineWithLandedCohort(uint24 lvl, uint256 boxWord) external {
        TQ.retireCompleted(address(this), lvl);
        uint24 day = _simulatedDayIndex();
        purchaseStartDay = day - 31;
        dailyIdx = day - 1;
        level = lvl;
        jackpotPhaseFlag = false;
        lastPurchaseDay = false;
        phaseTransitionActive = false;
        rngLockedFlag = false;
        rngWordCurrent = RNG_WORD_WAITING;
        vrfRequestId = 1;
        rngRequestTime = 1;
        _setRngRequestActive(false);
        ticketsFullyProcessed = true;
        prizePoolFrozen = false;
        // This fixture models an already requested, delivered cohort; index zero is unused.
        if (uint48(lootboxRngPacked) <= 1) rngFlagsAndNudges = (rngFlagsAndNudges & ~(uint16(1) << 12)) | (uint16((2) & 1) << 12);
        rngWordCurrent = boxWord; _setRngSessionPublished(true); _setRngComplete(false);
    }

    function terminalQueues(uint24 lvl) external view returns (uint256 readLen, uint256 writeLen, uint256 swapped) {
        return (
            _ticketQueueLength(_tqReadKey(lvl)),
            _ticketQueueLength(_tqWriteKey(lvl)),
            _lrRead(LR_GO_SWAP_SHIFT, LR_GO_SWAP_MASK)
        );
    }

    /// @dev Entries (and remainder) still owed at registry position `posPlusOne`.
    function owedAt(uint24 lvl, uint32 posPlusOne) external view returns (uint256) {
        uint256 mask = (uint256(1) << 40) - 1;
        return (_entryPacked(lvl, posPlusOne) & mask)
            + (_entryPacked(lvl | TICKET_SLOT_BIT, posPlusOne) & mask)
            + (_entryPacked(lvl | TICKET_FAR_FUTURE_BIT, posPlusOne) & mask);
    }
}
