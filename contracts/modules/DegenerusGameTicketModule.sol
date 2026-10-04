// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {GoldSixLib} from "../libraries/GoldSixLib.sol";

import {MineFlipGasBounds as GasBounds} from "../libraries/MineFlipGasBounds.sol";

import {DegenerusGameStorage} from "../storage/DegenerusGameStorage.sol";
import {ContractAddresses} from "../ContractAddresses.sol";
import {DegenerusTraitUtils} from "../DegenerusTraitUtils.sol";
import {MineFlipGas} from "../libraries/MineFlipGas.sol";
import {TicketEntropy} from "../libraries/TicketEntropy.sol";
import {EntropyLib} from "../libraries/EntropyLib.sol";
import {TicketWorkPlan} from "../libraries/JackpotTicketPlan.sol";
import {PackedTicketShuffle} from "../libraries/PackedTicketShuffle.sol";
import {PackedTicketSampleLib} from "../libraries/PackedTicketSampleLib.sol";
import {DegenerusGameJackpotDrawUtils} from "./DegenerusGameJackpotDrawUtils.sol";

import {IDegenerusGameFoilPackModule} from "../interfaces/IDegenerusGameModules.sol";

/// @notice Materializes a committed ticket/foil cohort under one immutable word.
/// @dev Available transaction gas selects a
///      safe checkpoint. Owner streams and complete seated rounds are independent
///      of that partition. The miner dispatcher owns
///      admission/publication and must not replace the word before this work ends.
contract DegenerusGameTicketModule is DegenerusGameJackpotDrawUtils {
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

    uint256 private constant DIRECT_TICKET_DOMAIN = uint256(keccak256("DEGENERUS_DIRECT_JACKPOT_TICKETS_V1"));
    // Eight packed draws (3.4k each cold) with seven padding redraws (2.5k each), cached
    // deity ID, batch award event and loop work: 52k. Trait writes have the round bound.
    uint256 internal constant DIRECT_GROUP_GAS = 65_000;
    // Bucket writes dominate a round. Sixteen fresh common groups: 0.80M measured. Each
    // rare group adds 0.19M; two rare colours in every quadrant (eight groups): 2.30M.
    uint256 internal constant DIRECT_ROUND_GAS_MAX = 2_800_000;

    event JackpotTicketWin(
        address indexed winner, uint24 indexed lvl, uint16 indexed trait,
        uint32 tickets, uint24 sourceLvl, uint256 entryIndex, bool roundedUp
    );

    /// @dev Packed IDs are permanent zero-based registry indices, eight per word.
    ///      Source index uint32.max denotes a virtual deity occurrence.
    event JackpotTicketBatchWin(
        uint24 indexed sourceLvl, uint24 indexed targetLvl, uint16 indexed trait,
        uint16 firstWinner, uint8 count, uint32 entriesEach,
        uint256[4] owners, uint256[4] sourceIndices
    );
    /// @dev One whole-ticket reveal per valid lane. Each uint32 trait lane contains
    ///      the four trait bytes, low quadrant first, matching the owner lane.
    event JackpotTicketBatchTraits(uint24 indexed lvl, uint8 count, uint256[4] owners, uint256[4] traits);

    struct DirectTicketGroup {
        uint256[4] lanes;
        uint256 count;
        uint256[4] indices;
    }

    /// @dev Direct L -> L+1 delivery. The jackpot worker owns pricing, passes
    ///      and completion. Source buckets remain frozen; the target is already live.
    ///      Each checkpoint completes all four quadrants, with one reveal per ticket.
    function runJackpotTicketAwards(TicketWorkPlan calldata plan, uint256 allowance)
        external returns (MineFlipGas.Result memory result)
    {
        JackpotWork storage work = jackpotWork;
        MineFlipGas.Meter memory meter = MineFlipGas.start(allowance);
        // The direct lane needs a live target buffer, unscaled entries and registered
        // deities; otherwise the queued path finishes the draw from the same cursor. Both
        // paths draw winner i of quadrant q from the same seed, so completed groups are not
        // drawn again. A group whose rounds were only partly materialized is skipped: its
        // winners keep the rounds they received and the rest stays as nextPrizePool backing.
        // Every input here is state, so caller gas never chooses the delivery mode.
        if (work.directTickets && (work.kind != 6 || plan.sourceLvl != work.lvl
            || plan.queueLvl != work.lvl + 1 || _ticketBufferLevel(plan.queueLvl) != plan.queueLvl
            || _snapShiftFor(plan.queueLvl) != 0 || !_deitiesRegistered(plan))) {
            work.directTickets = false;
            if (work.directTicketRound != 0) {
                work.directTicketRound = 0;
                uint8 sq = work.quadrant;
                uint256 si = work.winner;
                uint256 scount = sq < 4 ? plan.counts[sq] : 0;
                if (si < scount) {
                    uint256 sn = scount - si;
                    if (sn > 32) sn = 32;
                    si += sn;
                    if (si >= scount) { si = 0; ++sq; }
                    work.quadrant = sq;
                    work.winner = uint16(si);
                }
            }
        }
        if (!work.directTickets) {
            _resumeQueuedJackpotTickets(work, plan, meter, result);
            result.done = work.quadrant == 4;
            MineFlipGas.finish(meter);
            return result;
        }
        uint8 q = work.quadrant;
        uint256 i = work.winner;
        uint32 round = work.directTicketRound;
        uint256 rounds = plan.entriesEach / 4;
        while (q < 4) {
            uint256 count = plan.counts[q];
            if (count == 0) {
                if (!MineFlipGas.canRun(meter, 10_000, TAIL)) break;
                ++q;
                result.progressed = true;
                continue;
            }
            while (i < count) {
                uint256 n = count - i;
                if (n > 32) n = 32;
                // Four source words at a time. Preserve fixed batch geometry across
                // checkpoints; caller gas never chooses how players are mixed.
                uint256 roundBound = DIRECT_ROUND_GAS_MAX + ((n + 7) / 8) * DIRECT_GROUP_GAS;
                if (!MineFlipGas.canRun(meter, roundBound, TAIL)) break;
                _assertReadableTicketLevel(plan.sourceLvl);
                DirectTicketGroup memory group = _directTicketGroup(plan, q, i, n);
                // All randomness keys off the frozen word, source group and award round.
                // In particular neither the global queue round nor caller gas is an input.
                do {
                    uint256 seed = EntropyLib.hash4(DIRECT_TICKET_DOMAIN, plan.entropy,
                        (uint256(q) << 32) | i, round);
                    _materializeJackpotRound(plan.queueLvl, group.lanes, group.count, seed);
                    ++round;
                    result.progressed = true;
                } while (round < rounds && MineFlipGas.canRun(meter, roundBound, TAIL));
                if (round < rounds) break;
                emit JackpotTicketBatchWin(plan.sourceLvl, plan.queueLvl, plan.traits[q],
                    uint16(i), uint8(group.count), uint32(plan.entriesEach), group.lanes, group.indices);
                result.rewardBasis += n;
                round = 0;
                i += n;
            }
            if (i < count) break;
            i = 0;
            ++q;
        }
        if (q != work.quadrant) work.quadrant = q;
        if (i != work.winner) work.winner = uint16(i);
        if (round != work.directTicketRound) work.directTicketRound = round;
        result.done = q == 4;
        MineFlipGas.finish(meter);
    }

    /// @dev Winner `i` depends only on the frozen bucket, the quadrant seed and `i`, and each
    ///      group of eight positions reads one packed word, so a call draws only the groups it
    ///      awards and a resumed quadrant repeats no draw. Checkpoints sit on group starts.
    ///      Awarded tickets only enter a queue; they never mutate these source buckets.
    ///      Awards run in fixed groups: caller gas picks how many run, never their size.
    function _resumeQueuedJackpotTickets(JackpotWork storage work, TicketWorkPlan calldata plan,
        MineFlipGas.Meter memory meter, MineFlipGas.Result memory result) private
    {
        uint8 q = work.quadrant;
        uint256 i = work.winner;
        while (q < 4) {
            uint256 count = plan.counts[q];
            if (count == 0) {
                if (!MineFlipGas.canRun(meter, 10_000, GasBounds.JACKPOT_TAIL_GAS)) break;
                ++q;
                result.progressed = true;
                continue;
            }
            uint8 trait = plan.traits[q];
            uint256 len = plan.lens[q];
            address deity = plan.deities[q];
            uint256 effectiveLen = len + _deityVirtualCount(trait, len, deity);
            uint256 seed = EntropyLib.hash2(plan.entropy, q);
            uint8 salt = uint8(plan.salt + q);
            PackedTicketSampleLib.Cursor memory cursor;
            while (i < count) {
                uint256 end = i + GasBounds.JACKPOT_TICKET_AWARD_CHUNK;
                if (end > count) end = count;
                if (!MineFlipGas.canRun(meter,
                    (end - i) * (GasBounds.JACKPOT_TICKET_DRAW_GAS_MAX + GasBounds.JACKPOT_TICKET_AWARD_GAS_MAX), GasBounds.JACKPOT_TAIL_GAS)) break;
                if (i == 0) _assertReadableTicketLevel(plan.sourceLvl);
                result.progressed = true;
                result.rewardBasis += end - i;
                for (; i < end; ++i) {
                    (address winner, uint256 index) = _drawBucketEntry(
                        plan.sourceLvl, trait, len, effectiveLen, deity, seed, salt, i, cursor
                    );
                    if (winner != address(0)) {
                        _queueEntries(winner, plan.queueLvl, uint32(plan.entriesEach), true);
                        emit JackpotTicketWin(winner, plan.queueLvl, trait, uint32(plan.entriesEach),
                            plan.sourceLvl, index, false);
                    }
                }
            }
            if (i < count) break;
            i = 0;
            ++q;
        }
        if (q != work.quadrant) work.quadrant = q;
        if (i != work.winner) work.winner = uint16(i);
    }

    /// @dev Every deity a drawn quadrant can pay must hold a registry ID, which the direct
    ///      lane writes in place of an address.
    function _deitiesRegistered(TicketWorkPlan calldata plan) private view returns (bool) {
        for (uint256 q; q < 4; ++q) {
            address deity = plan.deities[q];
            if (deity != address(0) && plan.counts[q] != 0 && ticketOwnerId[deity] == 0) return false;
        }
        return true;
    }

    function _directTicketGroup(TicketWorkPlan calldata plan, uint8 q, uint256 start, uint256 n)
        private view returns (DirectTicketGroup memory group)
    {
        uint8 trait = plan.traits[q];
        uint256 len = plan.lens[q];
        address deity = plan.deities[q];
        uint256 effectiveLen = len + _deityVirtualCount(trait, len, deity);
        uint256 seed = EntropyLib.hash2(plan.entropy, q);
        // Paid and genesis deities acquire permanent IDs with their initial ticket
        // grants. Resolve once per batch; ordinary sampled lanes need no lookup.
        uint256 deityIdx = deity == address(0) ? 0 : uint256(ticketOwnerId[deity]) - 1;
        PackedTicketSampleLib.Cursor memory cursor;
        for (uint256 j; j < n; ++j) {
            if (cursor.used == 0) {
                uint256 base = PackedTicketSampleLib.begin(cursor, effectiveLen,
                    EntropyLib.hash4(seed, trait, uint8(plan.salt + q), start + j));
                if (base < len) cursor.word = _bucketWordAtUnchecked(plan.sourceLvl, trait, base);
            }
            (uint256 index, bool redrawn) = PackedTicketSampleLib.next(cursor, effectiveLen);
            uint256 ownerIdx;
            if (index >= len) {
                ownerIdx = deityIdx;
                index = type(uint32).max;
            } else {
                uint256 word = redrawn ? _bucketWordAtUnchecked(plan.sourceLvl, trait, index) : cursor.word;
                ownerIdx = uint32(word >> ((index & 7) << 5));
            }
            uint256 position = group.count++;
            group.lanes[position >> 3] |= ownerIdx << (32 * (position & 7));
            group.indices[position >> 3] |= index << (32 * (position & 7));
        }
    }

    /// @dev Four packed writes per common quadrant, with cheap memory shuffles
    ///      between quadrants. Accumulate traits in original-player order and
    ///      emit each completed ticket once. No queue, per-quadrant owner lookup,
    ///      or per-quadrant checkpoint/event overhead.
    function _materializeJackpotRound(uint24 lvl, uint256[4] memory lanes, uint256 count, uint256 seed)
        internal
    {
        if (count == 0) return;
        uint256[4] memory mixed = [lanes[0], lanes[1], lanes[2], lanes[3]];
        uint256 order;
        for (uint256 j; j < count; ++j) order |= j << (8 * j);
        uint256[4] memory reveals;
        uint256 levelSlot = _traitBufferBase(lvl);
        for (uint256 q; q < 4; ++q) {
            if (q != 0) {
                uint256 entropy = EntropyLib.hash2(seed, q + 4);
                if (count == 32) order = PackedTicketShuffle.shuffle(mixed, order, entropy);
                else {
                    // Shuffle only valid positions in a smaller final batch.
                    for (uint256 left = count; left > 1; --left) {
                        entropy = EntropyLib.hash2(entropy, left);
                        uint256 a = 8 * (left - 1);
                        uint256 b = 8 * (entropy % left);
                        uint256 diff = ((order >> a) ^ (order >> b)) & 0xff;
                        order ^= (diff << a) | (diff << b);
                    }
                    for (uint256 g; g < 4; ++g) mixed[g] = 0;
                    for (uint256 j; j < count; ++j) {
                        uint256 pos = uint8(order >> (8 * j));
                        mixed[j >> 3] |= uint256(uint32(lanes[pos >> 3] >> (32 * (pos & 7)))) << (32 * (j & 7));
                    }
                }
            }
            for (uint256 base; base < count; base += 8) {
                uint256 n = count - base;
                if (n > 8) n = 8;
                uint256 traits = _directQuadrant(lvl, levelSlot, mixed[base >> 3], n,
                    EntropyLib.hash2(seed, base / 8), q);
                for (uint256 j; j < n; ++j) {
                    uint256 pos = uint8(order >> (8 * (base + j)));
                    reveals[pos >> 3] |= uint256(uint32(traits >> (32 * j))) << (32 * (pos & 7));
                }
            }
        }
        emit JackpotTicketBatchTraits(lvl, uint8(count), lanes, reveals);
    }

    function _directQuadrant(uint24 lvl, uint256 levelSlot, uint256 lanes, uint256 count, uint256 seed, uint256 q)
        private returns (uint256 traits)
    {
        uint8 trait = DegenerusTraitUtils.traitFromWord(uint64(seed >> (64 * q))) | uint8(q << 6);
        if (((trait >> 3) & 7) < ROUND_SPLIT_COLOR) {
            _bucketAppendLanes(levelSlot, trait, lanes, count, lvl);
            return (uint256(trait) << (8 * q)) *
                0x0000000100000001000000010000000100000001000000010000000100000001;
        }
        // Rare colors retain the ordinary generator's symbol splitting and cap.
        RoundSeats memory st;
        st.lvl = lvl;
        st.seated = count;
        for (uint256 j; j < count; ++j) {
            st.ownerIdx[j] = uint32(lanes >> (32 * j));
            st.owed[j] = 4;
        }
        (traits,) = _runQuadrant(st, levelSlot, seed, q);
    }

    function runTicketWork(uint24 anchor, uint256 allowance) external returns (MineFlipGas.Result memory) {
        return _runTicketWork(anchor, allowance);
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

    uint64 private constant TICKET_LCG_MULT = 6364136223846793005;

    /// @dev Per-entry trait generation in the Game's storage context, called by the ticket worker.
    ///      A versioned immutable identity seeds each aligned group of sixteen. The caller
    ///      reserves generation plus the complete bucket flush, prepares the full level and
    ///      validates ownerIdx. This writer makes no external calls.
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
