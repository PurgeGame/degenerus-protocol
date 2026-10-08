// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {MineFlipGasBounds as GasBounds} from "../libraries/MineFlipGasBounds.sol";

import {DegenerusGamePayoutUtils} from "./DegenerusGamePayoutUtils.sol";
import {PriceLookupLib} from "../libraries/PriceLookupLib.sol";

import {DegenerusGameJackpotDrawUtils} from "./DegenerusGameJackpotDrawUtils.sol";
import {ContractAddresses} from "../ContractAddresses.sol";
import {EntropyLib} from "../libraries/EntropyLib.sol";
import {PackedTicketSampleLib} from "../libraries/PackedTicketSampleLib.sol";
import {JackpotBucketLib} from "../libraries/JackpotBucketLib.sol";
import {JackpotBattleFieldLib} from "../libraries/JackpotBattleFieldLib.sol";
import {FlipRoundLib} from "../libraries/FlipRoundLib.sol";
import {MineFlipGas} from "../libraries/MineFlipGas.sol";
import {IJackpotBattle} from "../interfaces/IJackpotBattle.sol";
import {IDegenerusJackpots} from "../interfaces/IDegenerusJackpots.sol";

interface IJackpotBattleMeter {
    function runDailyBattleWork(uint256 allowance) external returns (MineFlipGas.Result memory);
}

/// @notice Frozen daily FLIP draws and the separately metered jackpot-battle field.
/// @dev Delegate-called by JackpotModule; uses the same GAME storage and session.
contract DegenerusGameJackpotDrawModule is DegenerusGamePayoutUtils, DegenerusGameJackpotDrawUtils {
    IDegenerusJackpots private constant jackpots = IDegenerusJackpots(ContractAddresses.JACKPOTS);
    uint8 private constant WHALE_PASS_SRC_BAF_DIRECT = 2;
    uint8 private constant WHALE_PASS_SRC_AWARD_TICKETS = 3;
    uint256 private constant SMALL_LOOTBOX_THRESHOLD = 0.5 ether;
    uint16 private constant BAF_TRAIT_SENTINEL = 420;
    uint256 private constant BAF_TICKET_TAG = 0x4261665469636b6574;
    uint256 private constant BAF_ROUNDS = 48;
    /// @dev Scatter rounds double at each fourfold step of the BAF pool above this anchor.
    uint256 private constant BAF_ROUNDS_ANCHOR = 125 ether;
    uint256 private constant BAF_ROUNDS_MAX_MULTIPLIER = 32;
    event JackpotEthWin(uint32 indexed walletId, uint24 indexed level, uint16 indexed traitId,
        uint256 amount, uint256 entryIndex);
    event JackpotTicketWin(uint32 indexed walletId, uint24 indexed entryLevel, uint16 indexed traitId,
        uint32 entryCount, uint24 sourceLevel, uint256 entryIndex, bool roundedUp);

    /// @notice Every sampled near-level spot, including zero-score candidates and score-check losers.
    /// @dev Array order identifies each spot; wallet IDs may repeat. Empty arrays mean empty buckets.
    event BafCandidates(uint24 indexed level, uint24 indexed day, uint16 indexed round,
        uint24 sourceLevel, uint8 traitId, uint32[] candidates);

    bytes32 private constant FLIP_LEVEL_TAG = keccak256("coin-level");
    bytes32 private constant FAR_FUTURE_FLIP_TAG = keccak256("far-future-coin");
    uint256 private constant JACKPOT_BATTLE_ENTRANTS = JackpotBattleFieldLib.MAX_CHUNK;
    uint256 private constant COIN_DRAW_SHARES = 50;

    event JackpotFlipWin(uint32 indexed walletId, uint24 indexed level, uint8 indexed traitId,
        uint256 amount, uint256 entryIndex);

    function awardDailyFlipJackpot(uint24 minLevel, uint24 maxLevel, uint32 traits, uint256 budget, uint256 word) external {
        _awardDailyCoinToTraitWinners(minLevel, maxLevel, traits, budget, word);
    }

    function runPurchaseJackpotBattle(uint24 lvl, uint256 word, uint256 allowance)
        external returns (MineFlipGas.Result memory)
    {
        return _runPurchaseJackpotBattle(lvl, word, allowance);
    }

    /// @dev Awards a FLIP draw over trait-matched ticket holders across [minLevel, maxLevel]:
    ///      up to COIN_DRAW_SHARES winners, one equal whole-unit share each. Each pull samples
    ///      its own random level via keccak256(randomWord, FLIP_LEVEL_TAG, i) and rotates trait
    ///      deterministically via i % 4. Empty (lvl', trait_i) buckets skip, and neither an
    ///      unfilled share nor the sub-share remainder is minted, so no share can be short.
    ///      Per-trait deity addresses are cached at loop entry. Each (level, trait) owns an
    ///      independent eight-lane cursor.
    function _awardDailyCoinToTraitWinners(
        uint24 minLevel,
        uint24 maxLevel,
        uint32 winningTraitsPacked,
        uint256 coinBudget,
        uint256 randomWord
    ) private {
        uint256 units = coinBudget / FlipRoundLib.FLIP_ROUND_UNIT;
        if (units == 0) return;
        uint256 cap = units < COIN_DRAW_SHARES ? units : COIN_DRAW_SHARES;
        uint256 amount = (units / cap) * FlipRoundLib.FLIP_ROUND_UNIT;

        uint8[4] memory traitIds = JackpotBucketLib.unpackWinningTraits(
            winningTraitsPacked
        );

        // Per-trait deity cache: deityBySymbol is level-independent, so one read per trait
        // serves every pull of that trait.
        uint32[4] memory deityCache;
        for (uint8 t; t < 4; ) {
            uint8 trait = traitIds[t];
            deityCache[t] = _traitDeity(trait);
            unchecked { ++t; }
        }

        uint24 range = maxLevel - minLevel + 1;
        PackedTicketSampleLib.Cursor[] memory cursors = new PackedTicketSampleLib.Cursor[](uint256(range) * 4);

        uint32[] memory players = new uint32[](cap);
        uint256[] memory amounts = new uint256[](cap);
        uint256 paid;
        for (uint256 i; i < cap; ) {
            uint8 traitIdx = uint8(i & 3);
            uint8 trait_i = traitIds[traitIdx];
            (uint32 winner, uint24 lvlPrime, uint256 ticketIdx) = _drawCoinEntry(
                minLevel, range, trait_i, deityCache[traitIdx], randomWord, i, cursors
            );
            if (winner != 0) {
                emit JackpotFlipWin(winner, lvlPrime, trait_i, amount, ticketIdx);
                players[paid] = winner;
                amounts[paid] = amount;
                unchecked { ++paid; }
            }
            unchecked { ++i; }
        }
        if (paid != 0) {
            assembly ("memory-safe") {
                mstore(players, paid)
                mstore(amounts, paid)
            }
            coinflip.creditFlipBatch(players, amounts);
        }
    }

    /// @dev Keep the existing independent level draw for each pull. Only repeated draws
    ///      from the same (level, trait) consume further lanes of its cached random word.
    function _drawCoinEntry(
        uint24 minLevel,
        uint24 range,
        uint8 trait,
        uint32 deity,
        uint256 randomWord,
        uint256 pull,
        PackedTicketSampleLib.Cursor[] memory cursors
    ) private view returns (uint32 winner, uint24 lvl, uint256 index) {
        uint24 offset = uint24(uint256(keccak256(abi.encode(randomWord, FLIP_LEVEL_TAG, pull))) % range);
        lvl = minLevel + offset;
        uint256 len = _bucketLength(lvl, trait);
        uint256 effectiveLen = len + _deityVirtualCount(trait, len, deity);
        if (effectiveLen != 0) {
            (winner, index) = _drawBucketEntry(
                lvl, trait, len, effectiveLen, deity, randomWord, lvl, pull,
                cursors[uint256(offset) * 4 + (trait >> 6)]
            );
        }
    }

    /// @dev The daily jackpot battle over unminted future levels, played as one closed craps battle,
    ///      one bounded group per checkpoint. While the field is open a call draws groups of up to
    ///      JACKPOT_BATTLE_ENTRANTS awarded entries (see _collectJackpotChunkWithLevels), reads their saved
    ///      boards in one batch and appends them while another group fits; the chunk that reaches the award target, or finds
    ///      no eligible level, seals the field. Settlement starts in its own subsequent call;
    ///      its available execution gas never stacks on top of field construction. The latch
    ///      clears once the field completes.
    function _runPurchaseJackpotBattle(uint24 lvl, uint256 rngWord, uint256 allowance)
        private returns (MineFlipGas.Result memory result)
    {
        MineFlipGas.Meter memory meter = MineFlipGas.start(allowance);
        IJackpotBattle battle = IJackpotBattle(ContractAddresses.CRAPS);
        (,, bool started, bool complete) = battle.jackpotProgress();
        if (started) {
            if (complete) result.done = true;
            else {
                uint256 childAllowance = MineFlipGas.child(meter, 100_000);
                if (childAllowance == 0) return result;
                result = IJackpotBattleMeter(ContractAddresses.CRAPS).runDailyBattleWork(childAllowance);
            }
            if (result.done) {
                dailyTicketBudgetsPacked &= ~_JACKPOT_BATTLE_PENDING;
                result.progressed = true;
                MineFlipGas.markProgress(meter);
            }
            MineFlipGas.finish(meter);
            return result;
        }
        // Each checkpoint appends at most 50 seats. The bound includes all cold
        // recipient writes, the collision-heavy board dedupe, seal and credits.
        if (!MineFlipGas.canRun(meter, GasBounds.JACKPOT_BATTLE_DRAW, GasBounds.DAILY_PHASE_TAIL)) return result;
        uint256 battleWord = uint256(keccak256(abi.encode(rngWord, lvl, FAR_FUTURE_FLIP_TAG)));
        (uint256 word, uint256 cursor, uint256 remaining) = battle.prepareJackpotBattle(lvl, battleWord);
        JackpotDrawLevels memory levels = _jackpotDrawLevels(lvl, cursor);
        do {
            (uint32[] memory winners, uint256 next, bool exhausted) =
                _collectJackpotChunkWithLevels(lvl, word, cursor, remaining, levels);
            uint256[] memory field = JackpotBattleFieldLib.prepare(winners);
            bool last = exhausted || winners.length == remaining;
            battle.appendJackpotBattle(field, next, last);
            result.progressed = true;
            MineFlipGas.markProgress(meter);
            result.rewardBasis += winners.length;
            if (last) break;
            // Append persists the exact walk position. Read the accepted-unit count back
            // from the battle, then admit another group only while its full bound fits.
            (word, cursor, remaining) = battle.prepareJackpotBattle(lvl, battleWord);
        } while (MineFlipGas.canRun(meter, GasBounds.JACKPOT_BATTLE_DRAW, GasBounds.DAILY_PHASE_TAIL));
        ++result.rewardBasis;
        // Field construction and simulation are distinct bounded phases even if
        // this append seals an empty field. The next call observes completion.
        MineFlipGas.finish(meter);
    }

    /// @dev A visit walks one level once, starting at a random queue position and wrapping.
    ///      Levels are drawn WITH replacement, so later visits can award the same wallets again.
    ///      Memory only; the continuation fits in JackpotRound.drawCursor without new storage.
    struct JackpotDrawWalk {
        uint256 ordinal;
        uint256 offset;
        uint256 position;
        uint256 left;
    }

    struct JackpotDrawLevels {
        uint24[99] levels;
        uint256 count;
        uint256 eligible;
    }

    /// @dev Build the ascending eligible-level list once per worker invocation. The first
    ///      invocation snapshots 99 bounded queue reads; resumptions rebuild from the frozen
    ///      cursor bitmap. Appending seats changes only battle state, so later chunks in the
    ///      same invocation can reuse this list without rescanning or allocating it again.
    function _jackpotDrawLevels(uint24 lvl, uint256 cursor)
        internal view returns (JackpotDrawLevels memory snapshot)
    {
        uint256 eligible = (cursor >> 32) & ((uint256(1) << 99) - 1);
        uint256 count;
        uint24[99] memory levels = snapshot.levels;
        for (uint256 offset; offset < 99; ++offset) {
            uint24 candidate = lvl + 1 + uint24(offset);
            bool live = cursor == 0 ? _ticketQueueLength(_tqFarFutureKey(candidate)) != 0
                : eligible & (uint256(1) << offset) != 0;
            if (live) {
                eligible |= uint256(1) << offset;
                levels[count++] = candidate;
            }
        }
        snapshot.eligible = eligible;
        snapshot.count = count;
    }

    /// @dev Collect at most JACKPOT_BATTLE_ENTRANTS seats by walking randomly selected levels. Repeated
    ///      wallets keep separate seats. Cursor: next visit ordinal [0:31], eligible-level bitset
    ///      [32:130], active level offset [131:137], next queue position [138:169], positions left
    ///      in the visit [170:201]. A chunk boundary never starts a new visit or changes its draw.
    ///      All registries and queues remain frozen under the daily lock, including across
    ///      midnight and retries. Packed queue words are loaded once per group of up to eight.
    function _collectJackpotChunkWithLevels(
        uint24 lvl, uint256 word, uint256 cursor, uint256 remaining, JackpotDrawLevels memory snapshot
    )
        internal view returns (uint32[] memory winners, uint256 next, bool exhausted)
    {
        uint256 wanted = remaining < JACKPOT_BATTLE_ENTRANTS ? remaining : JACKPOT_BATTLE_ENTRANTS;
        if (snapshot.count == 0) return (new uint32[](0), 0, true);
        winners = new uint32[](wanted);
        JackpotDrawWalk memory walk = JackpotDrawWalk(
            uint32(cursor), (cursor >> 131) & 127, uint32(cursor >> 138), uint32(cursor >> 170)
        );
        uint256 i;
        while (i < wanted) {
            uint256 entropy;
            if (walk.left == 0) {
                entropy = EntropyLib.hash2(word, walk.ordinal++);
                walk.offset = snapshot.levels[entropy % snapshot.count] - lvl - 1;
            }
            uint24 candidate = lvl + 1 + uint24(walk.offset);
            uint256[] storage queue = ticketQueue[_ticketQueueStorageKey(_tqFarFutureKey(candidate))];
            uint256 len = _ticketQueueLength(_tqFarFutureKey(candidate));
            // An unexpectedly emptied level forfeits one award and ends this visit. Charging a
            // position keeps even that fail-open path bounded when selection uses replacement.
            if (len == 0) {
                walk.left = 0;
                ++i;
                continue;
            }
            // A singleton completes its visit immediately; it needs no circular-walk setup.
            if (len == 1) {
                winners[i++] = uint32(_tqWordAt(queue, 0));
                walk.position = 0;
                walk.left = 0;
                continue;
            }
            if (walk.left == 0) {
                walk.position = (entropy >> 128) % len;
                walk.left = len;
            }
            uint256 take = wanted - i;
            if (take > walk.left) take = walk.left;
            walk.left -= take;
            while (take != 0) {
                uint256 packed = _tqWordAt(queue, walk.position) >> ((walk.position & 7) << 5);
                uint256 lanes = 8 - (walk.position & 7);
                if (lanes > len - walk.position) lanes = len - walk.position;
                if (lanes > take) lanes = take;
                for (uint256 j; j < lanes; ++j) {
                    winners[i++] = uint32(packed);
                    packed >>= 32;
                }
                walk.position += lanes;
                if (walk.position == len) walk.position = 0;
                take -= lanes;
            }
        }
        next = walk.ordinal | (snapshot.eligible << 32) | (walk.offset << 131)
            | (walk.position << 138) | (walk.left << 170);
    }

    // -------------------------------------------------------------------------
    // Reward Jackpots (BAF + Decimator Dispatch)
    // -------------------------------------------------------------------------

    /// @notice Arms the BAF award stage at the x0 consolidation and returns the ETH it reserves.
    /// @dev Accounting order. The award schedule is a pure function of the pool: 2R scatter awards
    ///      (`_bafRounds`; a round's best takes (P/2)/R, its second ((P*30)/100)/R) and three
    ///      head awards (P/10, P/20, P/20). Consolidation debits futurePool and credits
    ///      claimablePool by the schedule's ETH term (`_bafReservation`) in this transaction, so
    ///      the Decimator seal, the keep roll and the settled pools do not depend on who wins.
    ///      `runBafAwards` then draws and pays each award from the reservation in groups; the ETH
    ///      term of an unfilled award (no candidate) returns to the pending future pool when the
    ///      stage completes. The bracket's resolution day is recorded here; its board and epoch close
    ///      at completion so every group reads the same frozen scores. The ticket-roll floor is
    ///      latched here: turbo routes it one level out because no further swap fires for the
    ///      level inside the collapsed phase.
    /// @return claimableDelta ETH reserved in claimablePool for the award schedule.
    function runBafJackpot(
        uint256 poolWei,
        uint24 lvl,
        uint256
    ) external returns (uint256 claimableDelta) {
        if (msg.sender != address(this)) revert OnlySelf();
        // BAF levels are even. Prepare both buffers once, including empty levels, so
        // the sampler can use its current/next flag directly without stale tickets.
        if (!_prepareTicketLevelAfterFoil(lvl) || !_prepareTicketLevelAfterFoil(lvl + 1)) revert E();
        jackpots.beginBaf();
        uint256 rounds = _bafRounds(poolWei);
        claimableDelta = _bafReservation(poolWei, rounds);
        JackpotWork storage work = jackpotWork;
        work.budget = uint128(poolWei);
        work.paid = uint128(claimableDelta);
        work.traits = uint32(2 * rounds + 3);
        work.lvl = lvl;
        work.winner = 0;
        work.kind = 7;
        work.quadrant = (jackpotFlags & JACKPOT_TURBO) != 0 ? 1 : 0;
        work.finalDay = false;
        work.directTicketRound = 0;
        work.directTickets = false;
    }

    /// @notice Draws and pays the BAF awards in index order in fixed groups of eight.
    /// @dev Positions 0..2R-1 are the scatter rounds, four per round pair (each round's best then
    ///      its second); a pair's four awards are drawn together when the pair starts, from the
    ///      frozen bracket, the locked word, the pair index and the bucket and queue entries at that
    ///      point (ticket awards paid earlier in the stage can add far-future lanes a later pair
    ///      samples). Positions 2R..2R+2 are the head awards. Groups hold whole pairs and the state
    ///      a group starts from is the same under every call partition, so a resumed stage redraws
    ///      nothing already paid; gas selects only how many groups run.
    ///      Per award: a large winner (at least a twentieth of the pool) takes half as claimable ETH
    ///      and half as lootbox tickets or, above the claim threshold, whale-pass halves; a small
    ///      scatter award is all ETH or all tickets, the leg alternating by round and by rank.
    ///      `work.paid` tracks the reserved ETH not yet credited; the last group returns what no
    ///      candidate took to the pending future pool, closes the bracket and deletes the work
    ///      record. The game-over latch releases the reservation instead.
    function runBafAwards(uint256 word, uint256 allowance, uint8[3] calldata traits)
        external returns (MineFlipGas.Result memory result)
    {
        MineFlipGas.Meter memory meter = MineFlipGas.start(allowance);
        JackpotWork storage work = jackpotWork;
        if (work.kind != 7) {
            result.done = true;
            return result;
        }
        uint256 n = work.traits;
        uint256 i = work.winner;
        uint24 lvl = work.lvl;
        uint256 pool = work.budget;
        uint256 rounds = (n - 3) / 2;
        uint24 floorLvl = lvl + work.quadrant;
        uint256 credited;
        uint32[4] memory drawn;
        while (i < n) {
            if (!MineFlipGas.canRun(meter, GasBounds.BAF_AWARD_GROUP, GasBounds.BAF_AWARD_TAIL)) break;
            uint256 end = i + GasBounds.JACKPOT_ETH_AWARD_CHUNK;
            if (end > n) end = n;
            for (; i < end; ) {
                uint32 winner;
                uint256 amount;
                if (i < 2 * rounds) {
                    if (i & 3 == 0) drawn = _drawBafPair(work, word, i, traits);
                    winner = drawn[i & 3];
                    amount = i & 1 == 0 ? (pool / 2) / rounds : ((pool * 30) / 100) / rounds;
                } else {
                    uint8 slot = uint8(i - 2 * rounds);
                    winner = jackpots.bafHeadWinner(lvl, word, slot);
                    amount = slot == 0 ? pool / 10 : pool / 20;
                }
                credited += _payBafAward(winner, amount, i, lvl, pool / 20, floorLvl, word);
                unchecked {
                    ++i;
                }
            }
            ++result.rewardBasis;
            MineFlipGas.markProgress(meter);
        }
        if (i != work.winner) {
            work.paid -= uint128(credited);
            work.winner = uint16(i);
            result.progressed = true;
            MineFlipGas.markProgress(meter);
        }
        if (i == n) {
            uint256 residue = work.paid;
            if (residue != 0) _releaseBafReserve(residue);
            jackpots.finalizeBaf(lvl);
            delete jackpotWork;
            result.done = true;
            result.progressed = true;
            MineFlipGas.markProgress(meter);
        }
        MineFlipGas.finish(meter);
    }

    /// @dev Draw and record each near-level pair once, when its first award executes.
    function _drawBafPair(JackpotWork storage work, uint256 word, uint256 i, uint8[3] calldata traits)
        private returns (uint32[4] memory winners)
    {
        uint256 rounds = (work.traits - 3) / 2;
        IDegenerusJackpots.BafRound[2] memory draws;
        (winners, draws) = jackpots.bafPairWinners(work.lvl, word, i >> 2, rounds, traits);
        if (i < rounds) {
            uint24 sourceLevel = work.lvl + (i >= rounds / 2 ? 1 : 0);
            for (uint256 j; j < 2; ++j) {
                emit BafCandidates(work.lvl, rngRequestDay, uint16((i >> 1) + j), sourceLevel,
                    draws[j].trait, draws[j].candidates);
            }
        }
    }

    /// @dev BAF_ROUNDS below 4 anchors, doubled at each fourfold step of `pool` from there (96 at
    ///      500 ETH, 192 at 2,000, ... 1,536 at 128,000). Always a multiple of 8.
    function _bafRounds(uint256 pool) private pure returns (uint256 rounds) {
        rounds = BAF_ROUNDS;
        for (
            uint256 step = 4 * BAF_ROUNDS_ANCHOR;
            rounds < BAF_ROUNDS * BAF_ROUNDS_MAX_MULTIPLIER && pool >= step;
            step *= 4
        ) rounds *= 2;
    }

    /// @dev A small scatter award pays ETH when its round parity equals its rank parity
    ///      (best of an even round, second of an odd round) and tickets otherwise.
    function _bafEthLeg(uint256 i) private pure returns (bool) {
        return ((i >> 1) ^ i) & 1 == 0;
    }

    /// @dev The ETH an award credits to claimable: a large winner's half plus the sub-half-pass
    ///      remainder of a deferred lootbox half, a small ETH-leg award in full, or the
    ///      sub-half-pass remainder of a small ticket-leg award above the claim threshold.
    function _bafEthTerm(uint256 amount, uint256 threshold, bool ethLeg) private pure returns (uint256) {
        if (amount >= threshold) {
            uint256 lootboxPortion = amount - amount / 2;
            return amount / 2 + (lootboxPortion > LOOTBOX_CLAIM_THRESHOLD ? lootboxPortion % HALF_WHALE_PASS_PRICE : 0);
        }
        if (ethLeg) return amount;
        return amount > LOOTBOX_CLAIM_THRESHOLD ? amount % HALF_WHALE_PASS_PRICE : 0;
    }

    /// @dev The ETH term of the whole award schedule for pool `pool` and `rounds` scatter rounds.
    function _bafReservation(uint256 pool, uint256 rounds) private pure returns (uint256 reserve) {
        uint256 threshold = pool / 20;
        uint256 perFirst = (pool / 2) / rounds;
        uint256 perSecond = ((pool * 30) / 100) / rounds;
        uint256 evenRounds = (rounds + 1) / 2;
        uint256 oddRounds = rounds / 2;
        reserve = evenRounds * (_bafEthTerm(perFirst, threshold, true) + _bafEthTerm(perSecond, threshold, false))
            + oddRounds * (_bafEthTerm(perFirst, threshold, false) + _bafEthTerm(perSecond, threshold, true))
            + _bafEthTerm(pool / 10, threshold, true) + 2 * _bafEthTerm(pool / 20, threshold, true);
    }

    /// @dev Pays one drawn award. Returns the ETH credited to claimable, equal to `_bafEthTerm`
    ///      for the award; an empty slot (wallet ID 0) or a zero amount pays nothing, and its
    ///      reserved ETH returns through _releaseBafReserve. Every BAF entrant holds a wallet ID.
    function _payBafAward(
        uint32 winner,
        uint256 amount,
        uint256 i,
        uint24 lvl,
        uint256 threshold,
        uint24 floorLvl,
        uint256 word
    ) private returns (uint256 credited) {
        if (winner == 0 || amount == 0) return 0;
        if (amount >= threshold) {
            uint256 ethPortion = amount / 2;
            uint256 lootboxPortion = amount - ethPortion;
            _creditClaimable(winner, ethPortion);
            credited = ethPortion;
            emit JackpotEthWin(winner, lvl, BAF_TRAIT_SENTINEL, ethPortion, 0);
            if (lootboxPortion <= LOOTBOX_CLAIM_THRESHOLD) {
                uint256 cd;
                (, cd) = _awardJackpotTickets(
                    winner, lootboxPortion, floorLvl, EntropyLib.hash4(word, lvl, BAF_TICKET_TAG, i)
                );
                credited += cd;
            } else {
                credited += _queueWhalePassClaimCore(winner, lootboxPortion);
                emit JackpotWhalePassWin(winner, lootboxPortion / HALF_WHALE_PASS_PRICE, WHALE_PASS_SRC_BAF_DIRECT);
            }
        } else if (_bafEthLeg(i)) {
            _creditClaimable(winner, amount);
            credited = amount;
            emit JackpotEthWin(winner, lvl, BAF_TRAIT_SENTINEL, amount, 0);
        } else {
            (, credited) = _awardJackpotTickets(
                winner, amount, floorLvl, EntropyLib.hash4(word, lvl, BAF_TICKET_TAG, i)
            );
        }
    }

    /// @dev Returns reserved BAF ETH that no candidate took: out of claimablePool and into the
    ///      pending future pool. The stage runs only under the daily lock, so the pools are frozen.
    function _releaseBafReserve(uint256 amount) private {
        claimablePool -= uint128(amount);
        (uint128 pendingNext, uint128 pendingFuture) = _getPendingPools();
        _setPendingPools(pendingNext, pendingFuture + uint128(amount));
    }

    /**
     * @notice Unified jackpot ticket award function for all jackpots.
     * @dev Awards tickets by amount tier:
     *      Very small (<= 0.5 ETH): one probabilistic roll
     *      Medium (0.5-5 ETH): split in half, 2 probabilistic rolls
     *      Large (> 5 ETH): whale-pass half-passes at 2.25 ETH each (100 entries = 25 tickets
     *      per half-pass); the sub-half-pass remainder is credited as claimable ETH
     *      Uses actual game ticket pricing for target levels.
     *
     * @param winner Wallet ID to receive rewards.
     * @param amount ETH amount for ticket conversion.
     * @param minTargetLevel Minimum target level for tickets.
     * @param entropy RNG state.
     * @return newEntropy Updated entropy state.
     * @return claimableDelta Wei credited to claimableWinnings on the whale-pass remainder leg
     *         (0 on the ticket-roll legs), folded by the caller into futurePool→claimablePool.
     */
    function _awardJackpotTickets(
        uint32 winner,
        uint256 amount,
        uint24 minTargetLevel,
        uint256 entropy
    ) private returns (uint256 newEntropy, uint256 claimableDelta) {
        // Large amounts (> 5 ETH): defer to whale pass claim system
        if (amount > LOOTBOX_CLAIM_THRESHOLD) {
            claimableDelta = _queueWhalePassClaimCore(winner, amount);
            emit JackpotWhalePassWin(
                winner,
                amount / HALF_WHALE_PASS_PRICE,
                WHALE_PASS_SRC_AWARD_TICKETS
            );
            return (entropy, claimableDelta);
        }

        // Very small amounts (<= 0.5 ETH): single roll
        if (amount <= SMALL_LOOTBOX_THRESHOLD) {
            return (_jackpotTicketRoll(winner, amount, minTargetLevel, entropy), 0);
        }

        // Medium amounts (0.5-5 ETH): split in half, 2 rolls
        uint256 halfAmount = amount / 2;

        // First roll
        entropy = _jackpotTicketRoll(
            winner,
            halfAmount,
            minTargetLevel,
            entropy
        );

        // Second roll (with remainder if amount was odd)
        uint256 secondAmount = amount - halfAmount;
        entropy = _jackpotTicketRoll(
            winner,
            secondAmount,
            minTargetLevel,
            entropy
        );

        return (entropy, 0);
    }

    /**
     * @notice Resolve a single jackpot ticket roll into ticket awards.
     * @dev Selects target level based on probability, then Bernoulli-collapses
     *      the scaled ticket count to a whole-ticket count before queueing.
     *      Uses actual game pricing for the selected target level.
     *      Entropy use in the per-roll keccak word `entropy` (evolved via
     *      EntropyLib.hash2 on entry, so it is full-diffusion keccak output):
     *        full word        path/level selection — `entropy % 100` range roll,
     *                         `(entropy / 100) % 4` near offset,
     *                         `(entropy / 100) % 46` far offset (modular reductions
     *                         of the whole 256-bit value)
     *        bits[96..127]    jackpotTicketRoundUp % 100 — Bernoulli whole-ticket
     *                         collapse sub-roll (uint32 window, modulo bias ~2e-8)
     *      The round-up slice is a 32-bit window of a word whose full-width residues
     *      drive the path roll; with keccak diffusion the correlation between the two
     *      is negligible.
     * @param winner Address to receive tickets.
     * @param amount ETH amount for this roll.
     * @param minTargetLevel Minimum target level (usually current level during SETUP phase).
     * @param entropy RNG state.
     * @return Updated entropy state.
     */
    function _jackpotTicketRoll(
        uint32 winner,
        uint256 amount,
        uint24 minTargetLevel,
        uint256 entropy
    ) private returns (uint256) {
        entropy = EntropyLib.hash2(entropy, entropy);

        // Roll for outcome (0-99 for percentage-based probabilities)
        uint256 entropyDiv100 = entropy / 100;
        uint256 roll = entropy - (entropyDiv100 * 100);
        uint24 targetLevel;

        if (roll < 30) {
            // 30% chance: minimum level ticket
            targetLevel = minTargetLevel;
        } else if (roll < 95) {
            // 65% chance: +1 to +4 levels ahead
            uint256 offset = 1 + (entropyDiv100 % 4); // 1-4 inclusive
            targetLevel = minTargetLevel + uint24(offset);
        } else {
            // 5% chance: +5 to +50 levels ahead (rare)
            uint256 offset = 5 + (entropyDiv100 % 46); // 5-50 inclusive
            targetLevel = minTargetLevel + uint24(offset);
        }

        // Calculate tickets for target level
        uint256 targetPrice = PriceLookupLib.priceForLevel(targetLevel);

        uint256 wholeTicketsScaled = (amount * QTY_SCALE) / targetPrice;

        // Bernoulli-collapse the scaled count to a whole-ticket count: the
        // fractional part rounds up with probability frac/QTY_SCALE using
        // bits[96..127] of the per-roll entropy word — a uint32 window, wide enough
        // that the % QTY_SCALE modulo bias is negligible (~2e-8).
        // Saturate at the uint32 ceiling instead of wrapping: an award above 4,294,967,295
        // scaled units (~42.9M whole tickets) in a single roll is only reachable at
        // economically-impossible prize sizes; a graceful cap avoids a silent modular wrap
        // to a tiny count.
        uint32 scaledWholeTickets = wholeTicketsScaled > type(uint32).max
            ? type(uint32).max
            : uint32(wholeTicketsScaled);
        uint32 whole = scaledWholeTickets / uint32(QTY_SCALE);
        uint32 frac = scaledWholeTickets % uint32(QTY_SCALE);
        bool roundedUp = false;
        if (frac != 0 && (uint32(entropy >> 96) % uint32(QTY_SCALE)) < frac) {
            unchecked {
                whole += 1;
            }
            roundedUp = true;
        }
        _queueEntries(winner, targetLevel, wholeTicketsToEntries(whole), true);

        // ticketCount is the entries count (whole<<2, 4 per whole ticket) queued above;
        // roundedUp is true iff the bits[96..127] Bernoulli sub-roll incremented the
        // underlying whole-ticket count.
        emit JackpotTicketWin(
            winner,
            targetLevel,
            BAF_TRAIT_SENTINEL,
            wholeTicketsToEntries(whole),
            minTargetLevel,
            0,
            roundedUp
        );

        return entropy;
    }
}
