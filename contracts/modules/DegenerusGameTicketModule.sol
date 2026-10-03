// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {GoldSixLib} from "../libraries/GoldSixLib.sol";

import {MineFlipGasBounds as GasBounds} from "../libraries/MineFlipGasBounds.sol";

import {DegenerusGameStorage} from "../storage/DegenerusGameStorage.sol";
import {ContractAddresses} from "../ContractAddresses.sol";
import {DegenerusTraitUtils} from "../DegenerusTraitUtils.sol";
import {MineFlipGas} from "../libraries/MineFlipGas.sol";
import {TicketEntropy} from "../libraries/TicketEntropy.sol";

import {IDegenerusGameFoilPackModule} from "../interfaces/IDegenerusGameModules.sol";

/// @notice Materializes a committed ticket/foil cohort under one immutable word.
/// @dev Available transaction gas selects a
///      safe checkpoint. Owner streams and complete seated rounds are independent
///      of that partition. The miner dispatcher owns
///      admission/publication and must not replace the word before this work ends.
contract DegenerusGameTicketModule is DegenerusGameStorage {
    // Each bound includes cold writes. TAIL covers all cursor/seat persistence,
    // queue release, completion flags and the return after the last admitted item.
    uint256 internal constant TAIL = GasBounds.TICKET_TAIL;
    uint256 internal constant SELECT_MAX = GasBounds.TICKET_SELECT_MAX;
    uint256 internal constant SEAT_MAX = GasBounds.TICKET_SEAT_MAX;
    uint256 internal constant RELOAD_MAX = GasBounds.TICKET_RELOAD_MAX;
    uint256 internal constant ROUND_MAX = GasBounds.TICKET_ROUND_MAX;
    uint256 internal constant SOLO_BASE = GasBounds.TICKET_SOLO_BASE;
    uint256 internal constant ENTRY_MAX = GasBounds.TICKET_ENTRY_MAX;
    uint256 internal constant SOLO_MAX_ENTRIES = GasBounds.TICKET_SOLO_MAX_ENTRIES;
    uint256 internal constant FOIL_CALL_MAX = GasBounds.TICKET_FOIL_CALL_MAX;
    uint256 internal constant CALL_OVERHEAD = GasBounds.TICKET_CALL_OVERHEAD;

    function runTicketWork(uint24 anchor, uint256 allowance) external returns (MineFlipGas.Result memory) {
        return _runTicketWork(anchor, allowance);
    }

    /// @dev Transitional callers receive the same available gas.
    function processTicketBatch(uint24 anchor) external returns (bool finished, bool didWork) {
        MineFlipGas.Result memory result = _runTicketWork(anchor, MineFlipGas.available());
        return (result.done, result.progressed);
    }

    function processTicketBatchBudgeted(uint24 anchor, uint256)
        external returns (bool finished, bool didWork, uint256 charged)
    {
        MineFlipGas.Result memory result = _runTicketWork(anchor, MineFlipGas.available());
        return (result.done, result.progressed, 0);
    }

    function _runTicketWork(uint24 anchor, uint256 allowance) private returns (MineFlipGas.Result memory result) {
        MineFlipGas.Meter memory meter = MineFlipGas.start(allowance);
        uint256 entropy = _lootboxWord(_rngReadBuffer());
        while (MineFlipGas.canRun(meter, SELECT_MAX, TAIL)) {
            (uint24 rk, bool foil, bool pending) = _selectProducer(anchor);
            if (!pending) {
                result.done = true;
                result.progressed = result.progressed || ticketCursor != 0 || ticketLevel != 0 || ticketSoloOffset != 0;
                ticketCursor = 0;
                ticketLevel = 0;
                ticketSoloOffset = 0;
                if (_lrRead(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK) == MID_DAY_FUTURE_POOL) {
                    _lrWrite(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK, 1);
                    result.progressed = true;
                    // The isolated pool's word does not commit the ordinary write queue.
                    result.done = !rngLockedFlag && !_foilDrainPending();
                }
                break;
            }
            if (entropy == 0) break;
            if (foil) {
                if (!MineFlipGas.canRun(meter, FOIL_CALL_MAX, TAIL)) break;
                uint256 body = MineFlipGas.remaining(meter) - TAIL - CALL_OVERHEAD;
                (bool ok, bytes memory data) = ContractAddresses.GAME_FOILPACK_MODULE.delegatecall(
                    abi.encodeWithSelector(IDegenerusGameFoilPackModule.runFoilWork.selector, body)
                );
                if (!ok) _revertTicket(data);
                MineFlipGas.Result memory step = abi.decode(data, (MineFlipGas.Result));
                result.progressed = result.progressed || step.progressed;
                result.rewardBasis += step.rewardBasis;
                if (!step.progressed) break;
                continue;
            }
            uint24 lvl = rk & ~(TICKET_SLOT_BIT | TICKET_FAR_FUTURE_BIT);
            if (!_prepareTicketLevelAfterFoil(lvl)) revert E();
            (bool moved, bool done, uint256 emitted) = _drainQueue(rk, lvl, entropy, meter);
            result.progressed = result.progressed || moved;
            result.rewardBasis += emitted;
            if (!done) break;
        }
        MineFlipGas.finish(meter);
    }

    /// @dev A started foil prerequisite has priority until its FIFO finishes.
    ///      The only allowed interruption is its exact parity-blocking old queue.
    ///      Readiness of a buffer prepared by the first pack cannot change priority.
    function _selectProducer(uint24 anchor) private view returns (uint24 rk, bool foil, bool pending) {
        bool terminal = anchor & TICKET_SLOT_BIT != 0;
        uint24 bareAnchor = anchor & ~TICKET_SLOT_BIT;
        if (_foilDrainPending() && foilGenerationDay != 0) return _foilProducer(terminal);
        if (!terminal && _lrRead(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK) == MID_DAY_FUTURE_POOL) {
            rk = _tqFarFutureKey(earlyTicketLevel);
            if (_ticketQueueLength(rk) != 0) return _queueProducer(rk, terminal);
        } else {
            uint24 first = terminal || bareAnchor == 0 ? bareAnchor : bareAnchor - 1;
            uint24 last = terminal ? bareAnchor : _mintCeiling();
            for (uint24 lvl = first; lvl <= last; ++lvl) {
                rk = _tqReadKey(lvl);
                if (_ticketQueueLength(rk) != 0) return _queueProducer(rk, terminal);
            }
            if (!terminal && _frozenPoolDue()) {
                rk = _tqFarFutureKey(_mintCeiling());
                if (_ticketQueueLength(rk) != 0) return _queueProducer(rk, terminal);
            }
        }
        if (_foilDrainPending()) return _foilProducer(terminal);
        return (0, false, false);
    }

    function _queueProducer(uint24 rk, bool terminal) private view returns (uint24, bool, bool) {
        uint24 lvl = rk & ~(TICKET_SLOT_BIT | TICKET_FAR_FUTURE_BIT);
        uint24 old = _ticketBufferLevel(lvl);
        if (!terminal && old != 0 && old != lvl && _foilDrainPending()) return _foilProducer(false);
        return (rk, false, true);
    }

    function _foilProducer(bool terminal) private view returns (uint24, bool, bool) {
        uint256[] storage packs = foilQueue[_foilReadKey()];
        if (foilCursor >= packs.length) return (0, false, false);
        uint24 lvl = uint24(packs[foilCursor] >> 160);
        uint24 old = _ticketBufferLevel(lvl);
        if (!terminal && old != 0 && old < lvl) {
            uint24 readKey = _tqReadKey(old);
            if (_ticketQueueLength(readKey) != 0) return (readKey, false, true);
            uint24 futureKey = _tqFarFutureKey(old);
            if (_ticketQueueLength(futureKey) != 0) {
                // A future queue is consumable only if this request committed it.
                if (!_frozenPoolDue() || old != _mintCeiling()) revert E();
                return (futureKey, false, true);
            }
        }
        return (0, true, true);
    }

    function _drainQueue(uint24 rk, uint24 lvl, uint256 entropy, MineFlipGas.Meter memory meter)
        private returns (bool progressed, bool done, uint256 emitted)
    {
        uint24 marker = lvl | (rk & (TICKET_FAR_FUTURE_BIT | TICKET_SLOT_BIT));
        if (ticketLevel != marker) {
            // Terminal selection may intentionally abandon another level; never
            // reset a continuation of the same authenticated old read cohort.
            ticketLevel = marker;
            ticketCursor = 0;
            ticketSeats = 0;
            ticketSoloOffset = 0;
        }
        uint256 total = _ticketQueueLength(rk);
        uint256 idx = ticketCursor;
        uint8 shift = _snapShiftFor(lvl);
        if (ticketSeats != 0 || total - idx >= ROUND_MIN_SEATS) {
            (idx, progressed, emitted) = _roundPhase(rk, lvl, idx, total, entropy, shift, meter);
            if (idx != total || _seatCount(ticketSeats) >= ROUND_MIN_SEATS) {
                ticketCursor = uint32(idx);
                return (progressed, false, emitted);
            }
        }
        uint256 start = TicketEntropy.queueStart(rk, total, entropy);
        uint256[] storage queue = ticketQueue[_ticketQueueStorageKey(rk)];
        while (ticketSeats != 0 || idx < total) {
            uint256 seats = ticketSeats;
            uint256 qi = TicketEntropy.queueIndex(seats != 0 ? (seats & 0xffffffff) - 1 : idx, start, total);
            (bool moved, bool complete, uint256 count) = _solo(
                _tqPositionAt(queue, qi), rk, lvl, qi, entropy, shift, meter
            );
            if (!moved) break;
            progressed = true;
            emitted += count;
            if (complete) {
                if (seats != 0) ticketSeats = seats >> 32;
                else ++idx;
            }
        }
        done = idx == total && ticketSeats == 0;
        if (done) {
            _releaseTicketQueue(rk);
            ticketCursor = 0;
            ticketLevel = 0;
            ticketSoloOffset = 0;
        } else ticketCursor = uint32(idx);
    }

    function _seatCount(uint256 seats) private pure returns (uint256 n) {
        while (seats != 0) { ++n; seats >>= 32; }
    }

    function _solo(uint32 ownerPos, uint24 rk, uint24 lvl, uint256 qi, uint256 entropy, uint8 shift,
        MineFlipGas.Meter memory meter) private returns (bool moved, bool complete, uint256 emitted)
    {
        if (!MineFlipGas.canRun(meter, SOLO_BASE + ENTRY_MAX, TAIL)) return (false, false, 0);
        uint256 record = _entryRecord(rk, ownerPos);
        address player = address(uint160(record));
        uint80 packed = uint80(record >> 160);
        uint80 snapDone = shift == 0 ? 0 : SNAP_DONE_BIT;
        uint32 owed;
        uint8 rem;
        (packed, owed, rem) = _readOwed(packed, snapDone, shift, rk, lvl, qi, player, entropy);
        uint256 stream = TicketEntropy.identity(rk, lvl, qi, player);
        uint256 available = MineFlipGas.remaining(meter);
        // A low-gas miner may commit a shorter aligned prefix. Never consume
        // any of the reserve needed to write its complete continuation state.
        uint256 actual = gasleft();
        if (actual < available) available = actual;
        if (available <= TAIL + SOLO_BASE + MineFlipGas.CHECK_RESERVE) return (false, false, 0);
        uint256 maxCount = (available - TAIL - SOLO_BASE - MineFlipGas.CHECK_RESERVE) / ENTRY_MAX;
        // Larger supplied gas resumes more aligned runs, never one larger chunk.
        if (maxCount > SOLO_MAX_ENTRIES) maxCount = SOLO_MAX_ENTRIES;
        uint256 whole = owed;
        bool finalTail = whole + (rem == 0 ? 0 : 1) <= maxCount;
        if (!finalTail) {
            whole = maxCount < whole ? maxCount : whole;
            whole &= ~uint256(15);
            if (whole == owed && rem != 0) whole = whole >= 16 ? whole - 16 : 0;
            if (whole == 0) return (false, false, 0);
        }
        // Reserve the possible fractional occurrence before examining its result.
        uint256 maximum = whole + (finalTail && rem != 0 ? 1 : 0);
        if (!MineFlipGas.canRun(meter, SOLO_BASE + maximum * ENTRY_MAX, TAIL)) return (false, false, 0);
        emitted = whole;
        if (finalTail && rem != 0 && TicketEntropy.remainder(stream, entropy, rem)) ++emitted;
        uint32 offset = ticketSoloOffset;
        if (emitted != 0) {
            bool goldSixTaken = _goldSixTaken(lvl);
            uint256 replayFlag = goldSixTaken ? TicketEntropy.GOLD_SIX_TAKEN : 0;
            _generateTraitRun(stream, offset, uint32(emitted), entropy, uint256(ownerPos) - 1, goldSixTaken);
            emit TraitsGenerated(player, stream | uint256(offset) | replayFlag, uint32(emitted));
        }
        complete = finalTail;
        if (complete) {
            _setEntryOwed(rk, ownerPos, 0);
            ticketSoloOffset = 0;
        } else {
            uint80 remaining = (uint80(owed - uint32(whole)) << 8) | uint80(rem) | snapDone | (packed & OWNER_IDX_MASK);
            _setEntryOwed(rk, ownerPos, remaining);
            ticketSoloOffset = uint32(uint256(offset) + whole);
        }
        return (true, complete, emitted);
    }

    /// @dev The one read of an entry's owed balance for both drain paths: snap it once, then
    ///      resolve a far-future fraction to a whole entry so no far-future remainder survives.
    function _readOwed(uint80 packed, uint80 snapDone, uint8 shift, uint24 rk, uint24 lvl,
        uint256 qi, address player, uint256 entropy) private pure returns (uint80, uint32 owed, uint8 rem)
    {
        if (snapDone != 0 && packed != 0 && packed & SNAP_DONE_BIT == 0) packed = _snapOwedPacked(packed, shift);
        owed = uint32(packed >> 8);
        rem = uint8(packed);
        if (rk & TICKET_FAR_FUTURE_BIT != 0 && rem != 0) {
            if (TicketEntropy.remainder(TicketEntropy.identity(rk, lvl, qi, player), entropy, rem)) ++owed;
            rem = 0;
        }
        return (packed, owed, rem);
    }

    function _revertTicket(bytes memory data) private pure {
        if (data.length == 0) revert MineFlipGas.InsufficientExecutionGas();
        assembly ("memory-safe") { revert(add(data, 32), mload(data)) }
    }
    /// @dev Seats of the round drain, kept in queue order so a vacated seat is refilled by
    ///      the next entry and the seated set is always the first unexhausted entries from
    ///      the cursor — the property a budget-split resume rebuilds from storage alone.
    struct RoundSeats {
        address[8] player;
        uint32[8] queueIdx;
        uint32[8] owed;
        uint8[8] rem;
        uint256[8] ownerIdx;
        uint256 seated;
        uint256 cur;
        uint24 lvl;
        uint24 rk;
        // Queue lanes are read-only during the call; adjacent seats share this cached word.
        uint256 queueBase;
        uint256 queueWordIndex;
        uint256 queueWord;
        uint256 queueStart;
        uint256 queueTotal;
    }

    /// @notice Per-entry trait generation in the Game's storage context, called by Mint.
    /// @dev A versioned immutable identity seeds each aligned group of sixteen.
    ///      Caller reserves generation plus the complete bucket flush, prepares the
    ///      full level and validates ownerIdx. This writer makes no external calls.
    uint64 private constant TICKET_LCG_MULT = 6364136223846793005;

    function generateTraitRun(uint256 stream, uint32 offset, uint32 count, uint256 entropy, uint256 ownerIdx)
        external returns (uint256 writes)
    {
        return _generateTraitRun(stream, offset, count, entropy, ownerIdx,
            _goldSixTaken(uint24(stream >> 224)));
    }

    function _generateTraitRun(
        uint256 baseKey,
        uint32 startIndex,
        uint32 count,
        uint256 entropyWord,
        uint256 ownerIdx,
        bool goldSixTaken
    ) private returns (uint256 writes) {
        uint32[256] memory counts;
        uint8[256] memory touchedTraits;
        uint16 touchedLen;

        if (uint32(baseKey) != 0 || startIndex & 15 != 0) revert E();
        uint256 endIndex = uint256(startIndex) + count;
        if (endIndex > uint256(type(uint32).max) + 1) revert E();
        uint256 i = startIndex;
        uint24 lvl = uint24(baseKey >> 224);

        // Generate traits in groups of 16, using LCG for deterministic randomness.
        while (i < endIndex) {
            uint256 groupIdx = i >> 4;

            // Hash all inputs so player address (stored in baseKey bits 191-32)
            // reaches the low 32 bits of s. LCG iteration preserves low-bit
            // independence, so the category bucket — derived from the low 32
            // bits of s — inherits whatever entropy the seed's low bits carry.
            uint256 seed = uint256(
                keccak256(abi.encode(baseKey, entropyWord, groupIdx))
            );
            uint64 s = uint64(seed) | 1;
            uint8 offset = uint8(i & 15);
            unchecked {
                s = s * (TICKET_LCG_MULT + uint64(offset)) + uint64(offset);
            }

            for (uint8 j = offset; j < 16 && i < endIndex; ) {
                unchecked {
                    s = s * TICKET_LCG_MULT + 1; // LCG step

                    // Generate trait using weighted distribution, add quadrant offset.
                    uint8 traitId = DegenerusTraitUtils.traitFromWord(s) +
                        (uint8(i & 3) << 6);

                    if (traitId == GoldSixLib.TRAIT) {
                        if (goldSixTaken) traitId = GoldSixLib.replacement(s);
                        else goldSixTaken = true;
                    }

                    // Track first occurrence of each trait for batch writing.
                    if (counts[traitId]++ == 0) {
                        touchedTraits[touchedLen++] = traitId;
                    }
                    ++i;
                    ++j;
                }
            }
        }

        // Calculate the storage slot for this level's trait buckets.
        // Solidity stores mapping(key => fixedArray) as keccak256(key . slot) + index,
        // with dynamic array elements at keccak256(keccak256(key . slot) + index).
        // This relies on the standard Solidity storage layout (stable since 0.4.x).
        // Safe here because the contract is non-upgradeable.
        uint256 levelSlot = _traitBufferBase(lvl);

        // Batch-write the packed lanes, one run per distinct trait.
        for (uint16 u; u < touchedLen; ) {
            uint8 traitId = touchedTraits[u];
            uint32 occurrences = counts[traitId];
            (uint256 f, uint256 d) = _bucketAppendRun(levelSlot, traitId, ownerIdx, occurrences, lvl);
            unchecked {
                writes += f * 3 + d;
                ++u;
            }
        }
    }

    /// @dev Legacy diagnostic selector; public unit selection is retired.
    function drainRounds(uint24 rk, uint24 lvl, uint32, uint256 idx, uint256 total, uint256 entropy, uint8 shift)
        external returns (uint256 nextIdx, uint32 used)
    {
        MineFlipGas.Meter memory meter = MineFlipGas.start(MineFlipGas.available());
        (nextIdx,,) = _roundPhase(rk, lvl, idx, total, entropy, shift, meter);
        MineFlipGas.finish(meter);
        used = 0;
    }

    function _roundPhase(uint24 rk, uint24 lvl, uint256 idx, uint256 total, uint256 entropy, uint8 shift,
        MineFlipGas.Meter memory meter) private returns (uint256 nextIdx, bool progressed, uint256 emitted)
    {
        if (ticketSoloOffset != 0) return (idx, false, 0);
        if (!MineFlipGas.canRun(meter, RELOAD_MAX, TAIL)) return (idx, false, 0);
        uint256[] storage queue = ticketQueue[_ticketQueueStorageKey(rk)];
        RoundSeats memory st;
        st.lvl = lvl;
        st.rk = rk;
        st.cur = idx;
        st.queueStart = TicketEntropy.queueStart(rk, total, entropy);
        st.queueTotal = total;
        uint256 queueBase;
        assembly ("memory-safe") {
            mstore(0, queue.slot)
            queueBase := keccak256(0, 32)
        }
        st.queueBase = queueBase;
        st.queueWordIndex = type(uint256).max;
        uint80 snapDone = shift == 0 ? 0 : SNAP_DONE_BIT;
        uint256 levelSlot = _traitBufferBase(lvl);
        uint32 round = ticketRound;
        uint256 seats = ticketSeats;
        while (seats != 0) {
            _seatEntry(st, (seats & 0xffffffff) - 1, lvl, entropy, snapDone, shift);
            seats >>= 32;
        }
        while (true) {
            while (st.seated < ROUND_SEATS && st.cur < total) {
                if (!MineFlipGas.canRun(meter, SEAT_MAX, TAIL)) break;
                _seatEntry(st, st.cur, lvl, entropy, snapDone, shift);
                ++st.cur;
                progressed = true;
            }
            // Complete canonical selection before rolling. A partial fill must
            // neither roll with four seats nor fall through to later solo owners.
            if (st.cur < total && st.seated < ROUND_SEATS) break;
            if (st.seated < ROUND_MIN_SEATS || !MineFlipGas.canRun(meter, ROUND_MAX, TAIL)) break;
            for (uint256 j; j < st.seated; ++j) emitted += st.owed[j] > 4 ? 4 : st.owed[j];
            _runRound(st, lvl, levelSlot, round, entropy);
            unchecked { ++round; }
            progressed = true;
        }
        if (ticketRound != round) ticketRound = round;
        uint256 word;
        for (uint256 j; j < st.seated; ++j) {
            _setEntryOwed(rk, uint32(st.ownerIdx[j] + 1),
                uint80((st.ownerIdx[j] + 1) << OWNER_IDX_SHIFT) |
                (uint80(st.owed[j]) << 8) | uint80(st.rem[j]) | snapDone);
            word |= (uint256(st.queueIdx[j]) + 1) << (32 * j);
        }
        if (word != ticketSeats) ticketSeats = word;
        return (st.cur, progressed, emitted);
    }

    /// @dev Seat queue entry `qi` if it still owes anything. Zero-owed entries resolve their
    ///      remainder roll here (skipped or seated with one entry) exactly as the per-entry
    ///      path does; a fully drained entry is skipped without a write.
    function _seatEntry(
        RoundSeats memory st,
        uint256 qi,

        uint24 lvl,
        uint256 entropy,
        uint80 snapDone,
        uint8 shift
    ) private {
        uint256 physical = TicketEntropy.queueIndex(qi, st.queueStart, st.queueTotal);
        uint256 wordIndex = physical >> 3;
        if (wordIndex != st.queueWordIndex) {
            uint256 queueBase = st.queueBase;
            uint256 lanes;
            assembly ("memory-safe") { lanes := sload(add(queueBase, wordIndex)) }
            st.queueWord = lanes;
            st.queueWordIndex = wordIndex;
        }
        uint32 ownerPos = uint32(st.queueWord >> ((physical & 7) << 5));
        uint256 record = _entryRecord(st.rk, ownerPos);
        address p = address(uint160(record));
        uint80 packed = uint80(record >> 160);
        uint32 owed;
        uint8 rem;
        (packed, owed, rem) = _readOwed(packed, snapDone, shift, st.rk, lvl, physical, p, entropy);
        if (owed == 0) {
            bool win = rem != 0 && TicketEntropy.remainder(
                TicketEntropy.identity(st.rk, lvl, physical, p), entropy, rem
            );
            if (!win) {
                if (packed != 0) _setEntryOwed(st.rk, ownerPos, 0);
                return;
            }
            owed = 1;
            rem = 0;
            _setEntryOwed(st.rk, ownerPos, (packed & OWNER_IDX_MASK) | snapDone | (uint80(1) << 8));
        }
        uint256 j = st.seated;
        st.player[j] = p;
        st.queueIdx[j] = uint32(qi);
        st.owed[j] = owed;
        st.rem[j] = rem;
        // _entryRecord authenticated ownerPos as a nonzero, in-range global ID.
        unchecked { st.ownerIdx[j] = uint256(ownerPos) - 1; }
        st.seated = j + 1;
    }

    /// @dev One quadrant of a round: roll its trait off the seed slice, write one lane word
    ///      (or eight single lanes across the symbols for a rare color), returning
    ///      this quadrant's contribution to the seat-trait word and mask.
    function _runQuadrant(
        RoundSeats memory st,
        uint256 levelSlot,
        uint256 seed,
        uint256 q
    ) private returns (uint256 traitBits, uint32 maskBits) {
        uint64 slice = uint64(seed >> (64 * q));
        uint8 base = DegenerusTraitUtils.traitFromWord(slice) | uint8(q << 6);
        bool split = ((base >> 3) & 7) >= ROUND_SPLIT_COLOR;
        // Bits 40..42 of the slice are unused by traitFromWord: the split rotation.
        uint256 rot = (slice >> 40) & 7;
        uint256 lanes;
        uint256 n;
        uint256 seated = st.seated;
        for (uint256 j; j < seated; ) {
            if (st.owed[j] > q) {
                uint8 trait = base;
                if (split) {
                    trait = (base & 0xF8) | uint8((n + rot) & 7);
                    // Seated entries flush immediately: query the cap only for an
                    // actual gold-six candidate, with no eager read on common rounds.
                    if (trait == GoldSixLib.TRAIT && _goldSixTaken(st.lvl)) {
                        trait = GoldSixLib.replacement(seed);
                    }
                    _bucketAppendRun(levelSlot, trait, st.ownerIdx[j], 1, st.lvl);
                } else {
                    lanes |= st.ownerIdx[j] << (32 * n);
                }
                traitBits |= uint256(trait) << (32 * j + 8 * q);
                maskBits |= uint32(1) << uint32(4 * j + q);
                unchecked {
                    ++n;
                }
            }
            unchecked {
                ++j;
            }
        }
        if (!split && n != 0) {
            _bucketAppendLanes(levelSlot, base, lanes, n, st.lvl);
        }
    }

    /// @dev One round: roll, write the four quadrant words, emit, consume, compact.
    function _runRound(
        RoundSeats memory st,
        uint24 lvl,
        uint256 levelSlot,
        uint32 round,
        uint256 entropy
    ) private {
        uint256 seed = uint256(keccak256(abi.encode(lvl, round, entropy)));
        uint256 seated = st.seated;
        uint256 seatTraits;
        uint32 seatMask;

        for (uint256 q; q < 4; ) {
            (uint256 traitBits, uint32 maskBits) = _runQuadrant(st, levelSlot, seed, q);
            seatTraits |= traitBits;
            seatMask |= maskBits;
            unchecked {
                ++q;
            }
        }

        _emitEntryTraits(st, lvl, seatTraits, seatMask, 0);
        if (seated > 4) _emitEntryTraits(st, lvl, seatTraits >> 128, seatMask >> 16, 4);

        // Consume one ticket per seat; exhausted seats roll their remainder, then leave.
        uint256 k;
        for (uint256 j; j < seated; ) {
            uint32 owed = st.owed[j];
            uint8 rem = st.rem[j];
            unchecked {
                owed -= owed > 4 ? 4 : owed;
            }
            if (owed == 0) {
                if (rem != 0) {
                    uint256 stream = TicketEntropy.identity(st.rk, lvl, TicketEntropy.queueIndex(st.queueIdx[j], st.queueStart, st.queueTotal), st.player[j]);
                    if (TicketEntropy.remainder(stream, entropy, rem)) owed = 1;
                    rem = 0;
                }
                if (owed == 0) {
                    _setEntryOwed(st.rk, uint32(st.ownerIdx[j] + 1), 0);
                    unchecked {
                        ++j;
                    }
                    continue;
                }
            }
            if (k != j) {
                st.player[k] = st.player[j];
                st.queueIdx[k] = st.queueIdx[j];
                st.ownerIdx[k] = st.ownerIdx[j];
            }
            st.owed[k] = owed;
            st.rem[k] = rem;
            unchecked {
                ++k;
                ++j;
            }
        }
        st.seated = k;
    }

    /// @dev One ABI word carries sixteen trait bytes plus their sixteen presence bits.
    ///      Unused trailing seats have zero topics even when compaction left stale memory.
    function _emitEntryTraits(
        RoundSeats memory st,
        uint24 lvl,
        uint256 traits,
        uint32 mask,
        uint256 offset
    ) private {
        uint256 prefix = uint256(lvl) << 160;
        uint256 p0 = prefix | uint160(st.player[offset]);
        uint256 p1 = offset + 1 < st.seated ? prefix | uint160(st.player[offset + 1]) : 0;
        uint256 p2 = offset + 2 < st.seated ? prefix | uint160(st.player[offset + 2]) : 0;
        uint256 p3 = offset + 3 < st.seated ? prefix | uint160(st.player[offset + 3]) : 0;
        emit EntryTraitsRevealed(p0, p1, p2, p3, uint144(uint128(traits)) | (uint144(uint16(mask)) << 128));
    }

}
