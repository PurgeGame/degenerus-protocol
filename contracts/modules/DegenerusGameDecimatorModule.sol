// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/*
 * TERMS OF INTERACTION — submitting a transaction to this contract accepts them.
 *
 * THIS IS GAMBLING. Outcomes are decided by chance. You can lose everything you put in
 * simply by being unlucky. That is the software working exactly as intended. Do not
 * commit funds you are not prepared to lose entirely.
 *
 * The deployed bytecode is the entire agreement and the exclusive source of truth; any
 * comment, name, document or statement that disagrees with it is in error. It has been
 * audited but is not proven correct: it may contain defects the author did not find, and
 * by interacting with it you accept that risk in full.
 *
 * Any state transition the code permits is authorised — including one that exploits a
 * defect, and including sequences the author did not intend or foresee. A bug is not a
 * breach of these terms. There is no unwritten rule behind the code for a permitted
 * transaction to violate, and no unauthorised access to this contract.
 *
 * You bear all resulting loss, whether it follows from chance or from a defect. There is
 * no refund, no rollback and no privileged party able to restore a position.
 *
 * Provided AS IS, without warranty of any kind. Full text: TERMS.md
 */

import {DegenerusGameStorage} from "../storage/DegenerusGameStorage.sol";
import {ContractAddresses} from "../ContractAddresses.sol";
import {Craps} from "../Craps.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @dev Pinned stateless engine. The pure ABI ensures a STATICCALL from the Game context.
interface IDecimatorCrapsEngine {
    function settleSlipBounded(
        uint256 packedChips,
        uint256 chipFlip,
        uint256 scatterHash,
        uint256 scatterCount,
        bytes32 seed,
        uint256 bankroll,
        address player,
        uint256 boost,
        uint256 bounds
    ) external pure returns (Craps.SlipResult memory);
}

/// @notice Shared-dice Decimator battle. All runs, ranking and ETH credits execute on chain.
/// @dev Delegatecalled by Game. A FIFO of sealed rounds allows later windows to open while
///      keepers process older fields. No transaction walks the unbounded entrant population.
contract DegenerusGameDecimatorModule is DegenerusGameStorage {
    uint256 private constant SCALE = 3000 ether;
    uint256 private constant MAX_BUDGET = 1920;
    bytes32 private constant DICE_TAG = keccak256("decimator.battle.dice.v1");
    bytes32 private constant BOARD_TAG = keccak256("decimator.battle.board.v1");
    bytes32 private constant COIN_TAG = keccak256("decimator.battle.final-coin.v1");
    bytes32 private constant TIE_TAG = keccak256("decimator.battle.tie.v1");

    // Keeper work units (4.7k gas each), charged after each piece of work from its outcome and
    // sized on measured worst cases: the call frame with a first cursor write (~37k inside
    // mineFlip's delegatecall), a tails coin (~0.8k), a heads run's fixed cost (~18k) plus its
    // dice (<= 723 gas a roll on any board), a filling insert into fresh (~46k) or reused (~13k)
    // slots, a heap level (~14.5k), a root reject (~5k), a scanned leaf with tiebreaks (~5.3k)
    // an ETH credit to an empty balance (~30.5k), and a half-pass award with its share of the
    // pool move (~23k fresh, plus ~10k once a call). DecimatorPricing.t.sol pins every call,
    // real dice and worst heap shapes alike, at or under 90% of its charge.
    uint256 private constant CALL_UNITS = 9;
    uint256 private constant TAILS_UNITS = 1;
    uint256 private constant RUN_UNITS = 5;
    uint256 private constant ROLLS_PER_UNIT = 6;
    uint256 private constant INSERT_UNITS = 4;
    uint256 private constant INSERT_FRESH_UNITS = 11;
    uint256 private constant MOVE_UNITS = 4;
    uint256 private constant REJECT_UNITS = 2;
    uint256 private constant RANK_UNITS = 8;
    uint256 private constant RANK_NODE_UNITS = 2;
    uint256 private constant CREDIT_UNITS = 8;
    uint256 private constant PASS_UNITS = 6;

    // A run stops at bust, after 64 shooters, or at exactly 511 rolls. Sized on 200,000 simulated
    // shared-dice runs over every board size: none reached 64 shooters and 10 (5e-5, in 2 of 1,000
    // rounds) reached 511 rolls. The pair bounds a heads run at 126 units, per-shooter cost included.
    uint256 private constant RUN_BOUNDS = (511 << 16) | 64;

    // An entry word: id in bits 0..63, the chosen board's thirty chip bits at 64, the stack above.
    uint256 private constant CHIPS_SHIFT = 64;
    uint256 private constant STACK_SHIFT = 96;

    event DecBurnRecorded(
        address indexed player,
        uint24 indexed lvl,
        uint64 indexed entryId,
        uint256 baseAmount,
        uint256 credited,
        uint256 stack,
        uint32 chips
    );
    event DecimatorResolved(uint24 indexed lvl, uint256 rngWord, uint256 poolWei, uint64 entrants);
    /// @dev Heads runs only; a tails entry's coin and run both replay from the sealed word.
    event DecimatorRun(uint24 indexed lvl, uint64 indexed entryId, uint256 normalizedPeak);
    event DecimatorRanked(uint24 indexed lvl, uint64 champion, uint8 winners);
    /// @dev `amountWei` is the ETH credited; `halfPasses` the half whale passes queued instead.
    event DecimatorClaimed(
        address indexed player, uint24 indexed lvl, uint64 indexed entryId, uint256 amountWei, uint256 halfPasses
    );

    /// @param chips The entry's board as a normal battle takes it: ten three-bit leg counts naming
    ///        zero to seven chips; the dice scatter the rest of the ten. Each burn sets it.
    function recordDecBurn(address player, uint24 lvl, uint256 baseAmount, uint256 multBps, uint32 chips)
        external
        returns (uint64 id)
    {
        if (msg.sender != ContractAddresses.COIN) revert E();
        _checkBoard(chips);
        DecBattleRound storage round = decBattleRounds[lvl];
        if (
            gameOver || !decWindowOpen || lvl != level + 1 || round.phase != 0 || player == address(0)
                || baseAmount == 0 || multBps < 10_000 || multBps > 20_000
        ) revert E();
        uint24 day = _simulatedDayIndex();
        if (round.openedDay == 0 || day < round.openedDay) revert E();
        uint256 factor = _dayFactor(day - round.openedDay);
        // Multiply timing first to avoid overflow for very large, heavily decayed burns.
        uint256 credited = Math.mulDiv(baseAmount, factor * multBps, 1 ether * 10_000);
        if (credited == 0) revert E();
        mapping(address => uint256) storage entries = decBattleEntries[lvl];
        uint256 packed = entries[player];
        id = uint64(packed);
        if (id == 0) {
            id = ++round.count;
            decBattleOwners[_entryKey(lvl, id)] = player;
        }
        uint256 stack = (packed >> STACK_SHIFT) + credited;
        // 2^160 wei of chips is ~10^12 times FLIP's uint128 supply ceiling; the guard keeps the
        // packed word and the 512-bit score exact without bounding any realistic burn history.
        if (stack >> 160 != 0) revert E();
        entries[player] = (stack << STACK_SHIFT) | (uint256(chips) << CHIPS_SHIFT) | id;
        emit DecBurnRecorded(player, lvl, id, baseAmount, credited, stack, chips);
    }

    /// @dev A normal battle's board rules: at most three chips on a leg, seven named in all, and
    ///      never both the pass line and don't pass.
    function _checkBoard(uint256 chips) private pure {
        if (
            chips > 0x3FFFFFFF || (chips & 7 != 0 && chips >> 27 != 0) || (chips >> 2) & 0x9249249 != 0
                || _named(chips) > 7
        ) revert E();
    }

    /// @dev How many chips a board names across its ten three-bit legs.
    function _named(uint256 chips) private pure returns (uint256 named) {
        for (uint256 i; i < 30; i += 3) named += (chips >> i) & 7;
    }

    /// @dev Bounded by the 24-bit day count, including windows with no daily advancement.
    function _dayFactor(uint256 daysLate) private pure returns (uint256 factor) {
        factor = 1 ether;
        uint256 base = 0.9 ether;
        while (daysLate != 0) {
            if (daysLate & 1 != 0) factor = factor * base / 1 ether;
            daysLate >>= 1;
            if (daysLate != 0) base = base * base / 1 ether;
        }
    }

    function runDecimatorJackpot(uint256 poolWei, uint24 lvl, uint256 rngWord)
        external
        returns (uint256 returnAmountWei)
    {
        if (msg.sender != address(this)) revert E();
        DecBattleRound storage round = decBattleRounds[lvl];
        // An empty or already sealed event hands the pool back untouched.
        if (round.phase != 0 || round.count == 0) return poolWei;
        if (decWindowOpen || poolWei > type(uint128).max) revert E();
        round.rngWord = rngWord;
        round.poolWei = uint128(poolWei);
        uint256 places = (uint256(round.count) + 9) / 10;
        round.capacity = uint8(places > 100 ? 100 : places);
        round.phase = 1;
        uint24 tail = uint24(decBattleQueue >> 24);
        if (tail == 0) {
            decBattleQueue = uint256(lvl) | (uint256(lvl) << 24);
        } else {
            decBattleRounds[tail].next = lvl;
            decBattleQueue = uint24(decBattleQueue) | (uint256(lvl) << 24);
        }
        emit DecimatorResolved(lvl, rngWord, poolWei, round.count);
    }

    /// @notice Permissionless, deterministic progress. Budget affects batch size, never outcomes.
    ///         Idles once the game is over: a round still queued then keeps its reservation in
    ///         claimablePool, which the final sweep releases.
    /// @return settled Work items (runs, finalization or ETH credits), including losing runs.
    /// @return unitsUsed Conservative keeper work units; the final bounded run may overshoot.
    /// @return moved Whether the FIFO or a round's cursor advanced.
    function settleDecimatorWinners(uint256 budgetUnits)
        external
        returns (uint256 settled, uint256 unitsUsed, bool moved)
    {
        uint24 lvl = uint24(decBattleQueue);
        if (lvl == 0 || budgetUnits <= CALL_UNITS || gameOver) return (0, 0, false);
        if (budgetUnits > MAX_BUDGET) budgetUnits = MAX_BUDGET;
        DecBattleRound storage round = decBattleRounds[lvl];
        unitsUsed = CALL_UNITS;
        if (round.phase == 1) {
            uint64 cursor = round.cursor;
            uint64 count = round.count;
            if (cursor == count) return (1, unitsUsed + _rank(lvl, round), true);
            // The only external call is the pinned pure engine, which cannot touch Game storage, so
            // the batch keeps its progress on the stack and persists it once.
            uint256 word = round.rngWord;
            uint256 capacity = round.capacity;
            uint256 winners = round.winners;
            uint256 winnersBefore = winners;
            bytes32 seed = keccak256(abi.encode(DICE_TAG, word, lvl));
            uint256 free;
            assembly ("memory-safe") { free := mload(0x40) }
            while (cursor < count && unitsUsed < budgetUnits && settled < 256) {
                ++cursor;
                uint256 units;
                (units, winners) = _run(lvl, cursor, word, seed, capacity, winners);
                unitsUsed += units;
                ++settled;
                // Every engine result is dead before the next iteration.
                assembly ("memory-safe") { mstore(0x40, free) }
            }
            round.cursor = cursor;
            if (winners != winnersBefore) round.winners = uint8(winners);
        } else if (round.phase == 2) {
            uint256 winners = round.winners;
            uint256 paid = round.paid;
            (uint256 base, uint256 champ, uint256 champPasses, uint256 perEth,, bool passMode) = _payTerms(round);
            mapping(uint256 => DecBattleNode) storage heap = decBattleHeap;
            while (paid < winners && unitsUsed < budgetUnits) {
                uint64 id = uint64(heap[paid].head);
                address owner = decBattleOwners[_entryKey(lvl, id)];
                // Position 0 is the champion (moved there at ranking): half passes, the rest ETH.
                if (paid == 0) {
                    if (champPasses != 0) {
                        whalePassClaims[owner] += champPasses;
                        unitsUsed += PASS_UNITS;
                    }
                    uint256 eth = champ - champPasses * HALF_WHALE_PASS_PRICE;
                    _creditClaimable(owner, eth);
                    emit DecimatorClaimed(owner, lvl, id, eth, champPasses);
                } else if (passMode && paid & 1 == 0) {
                    uint256 halfPasses = base / HALF_WHALE_PASS_PRICE;
                    whalePassClaims[owner] += halfPasses;
                    unitsUsed += PASS_UNITS;
                    emit DecimatorClaimed(owner, lvl, id, 0, halfPasses);
                } else {
                    _creditClaimable(owner, base + perEth);
                    emit DecimatorClaimed(owner, lvl, id, base + perEth, 0);
                }
                ++paid;
                unitsUsed += CREDIT_UNITS;
                ++settled;
            }
            round.paid = uint8(paid);
            if (paid == winners) _finish(round);
        }
        moved = settled != 0;
    }

    /// @dev The payout's constant terms. The champion's amount is the 5% bonus plus its equal share
    ///      (and the division dust): half of it buys whole half whale passes, rounded down, and the
    ///      rest is ETH. Once an equal share buys a half pass too, the other places alternate ETH
    ///      and whole half passes. Only what buys passes leaves for the future prize pool
    ///      (`recycled`, moved once when the round is ranked): the other pass winners' leftovers top
    ///      up the other ETH winners (`perEth` each), and that split's own dust follows the passes.
    function _payTerms(DecBattleRound storage round)
        private
        view
        returns (uint256 base, uint256 champ, uint256 champPasses, uint256 perEth, uint256 recycled, bool passMode)
    {
        uint256 pool = round.poolWei;
        uint256 winners = round.winners;
        base = (pool - pool / 20) / winners;
        champ = pool - base * (winners - 1);
        champPasses = champ / 2 / HALF_WHALE_PASS_PRICE;
        recycled = champPasses * HALF_WHALE_PASS_PRICE;
        passMode = winners > 1 && base >= HALF_WHALE_PASS_PRICE;
        if (!passMode) return (base, champ, champPasses, 0, recycled, false);
        // Places 1..winners-1: odd ones take ETH, even ones whole half passes.
        uint256 passWinners = (winners - 1) / 2;
        uint256 ethWinners = winners - 1 - passWinners;
        uint256 leftover = passWinners * (base % HALF_WHALE_PASS_PRICE);
        perEth = leftover / ethWinners;
        recycled += passWinners * (base - base % HALF_WHALE_PASS_PRICE) + leftover - perEth * ethWinners;
    }

    function _run(uint24 lvl, uint64 id, uint256 word, bytes32 seed, uint256 capacity, uint256 winners)
        private
        returns (uint256 units, uint256)
    {
        // The final coin is independent of the run, so tails skips the engine: the run cannot place
        // and anyone can replay it from the sealed word with a free call to the pure engine.
        if (uint256(keccak256(abi.encode(COIN_TAG, word, lvl, id))) & 1 == 0) return (TAILS_UNITS, winners);
        address owner = decBattleOwners[_entryKey(lvl, id)];
        uint256 entry = decBattleEntries[lvl][owner];
        // The board was checked at burn, so settlement only counts its named chips.
        uint256 chips = uint32(entry >> CHIPS_SHIFT);
        uint256 named = _named(chips);
        // Exactly 1/5 starting bankroll on the ten-chip board: the named chips, the dice scattering
        // the rest, and the normal battles' shooter boost for that many named chips (the
        // Craps._shooterBoostTerms row). Normalize only engine units: multiplying the result by
        // the original stack preserves the absolute high point.
        Craps.SlipResult memory result = IDecimatorCrapsEngine(ContractAddresses.CRAPS_ENGINE).settleSlipBounded(
            chips,
            60,
            uint256(keccak256(abi.encode(BOARD_TAG, word, lvl, id))),
            10 - named,
            seed,
            SCALE,
            owner,
            (0x1205170618081D091D0B1D0C1D0E200F >> (named << 4)) & 0xFFFF,
            RUN_BOUNDS
        );
        emit DecimatorRun(lvl, id, result.peakBankroll);
        (uint256 high, uint256 low) = Math.mul512(entry >> STACK_SHIFT, result.peakBankroll);
        (units, winners) = _insert(lvl, word, capacity, winners, low, (high << 64) | id);
        return (units + RUN_UNITS + (result.totalRolls + ROLLS_PER_UNIT - 1) / ROLLS_PER_UNIT, winners);
    }

    /// @dev Min heap: the weakest retained eligible entry is at the root. At most 100 nodes. A
    ///      filling insert takes the next position; the first round ever to reach it pays for
    ///      fresh slots, every later round reuses them.
    function _insert(uint24 lvl, uint256 word, uint256 capacity, uint256 size, uint256 low, uint256 head)
        private
        returns (uint256 units, uint256)
    {
        mapping(uint256 => DecBattleNode) storage heap = decBattleHeap;
        uint256 pos;
        uint256 base = INSERT_UNITS;
        if (size < capacity) {
            pos = size;
            if (heap[pos].head == 0) base = INSERT_FRESH_UNITS;
            ++size;
            while (pos != 0) {
                uint256 parent = (pos - 1) / 2;
                uint256 pLow = heap[parent].low;
                uint256 pHead = heap[parent].head;
                if (!_less(word, lvl, low, head, pLow, pHead)) break;
                heap[pos].low = pLow;
                heap[pos].head = pHead;
                pos = parent;
                units += MOVE_UNITS;
            }
        } else {
            if (!_less(word, lvl, heap[0].low, heap[0].head, low, head)) return (REJECT_UNITS, size);
            while (true) {
                uint256 child = pos * 2 + 1;
                if (child >= size) break;
                uint256 cLow = heap[child].low;
                uint256 cHead = heap[child].head;
                if (child + 1 < size) {
                    uint256 dLow = heap[child + 1].low;
                    uint256 dHead = heap[child + 1].head;
                    if (_less(word, lvl, dLow, dHead, cLow, cHead)) {
                        ++child;
                        cLow = dLow;
                        cHead = dHead;
                    }
                }
                if (!_less(word, lvl, cLow, cHead, low, head)) break;
                heap[pos].low = cLow;
                heap[pos].head = cHead;
                pos = child;
                units += MOVE_UNITS;
            }
        }
        heap[pos].low = low;
        heap[pos].head = head;
        return (units + base, size);
    }

    /// @dev Exact 512-bit score order (the high 192 bits sit above the id in `head`), then the
    ///      random tiebreak, then the entry id.
    function _less(uint256 word, uint24 lvl, uint256 aLow, uint256 aHead, uint256 bLow, uint256 bHead)
        private
        pure
        returns (bool)
    {
        if (aHead >> 64 != bHead >> 64) return aHead >> 64 < bHead >> 64;
        if (aLow != bLow) return aLow < bLow;
        return _tieKey(word, lvl, uint64(aHead)) < _tieKey(word, lvl, uint64(bHead));
    }

    function _tieKey(uint256 word, uint24 lvl, uint64 id) private pure returns (uint256) {
        return (uint256(keccak256(abi.encode(TIE_TAG, word, lvl, id))) & ~uint256(type(uint64).max)) | id;
    }

    function _rank(uint24 lvl, DecBattleRound storage round) private returns (uint256 units) {
        uint256 winners = round.winners;
        units = RANK_UNITS;
        if (winners == 0) {
            _releaseToFuture(round.poolWei);
            _finish(round);
            emit DecimatorRanked(lvl, 0, 0);
            return units;
        }
        mapping(uint256 => DecBattleNode) storage heap = decBattleHeap;
        uint256 word = round.rngWord;
        // Every internal node of the min-heap is below a child, so the maximum is a leaf.
        uint256 i = winners / 2;
        uint256 best = i;
        uint256 bestLow = heap[i].low;
        uint256 bestHead = heap[i].head;
        for (++i; i < winners; ++i) {
            uint256 low = heap[i].low;
            uint256 head = heap[i].head;
            if (_less(word, lvl, bestLow, bestHead, low, head)) {
                best = i;
                bestLow = low;
                bestHead = head;
            }
        }
        // Payouts need no heap order: the champion takes position 0, where they pay it first.
        if (best != 0) {
            heap[best].low = heap[0].low;
            heap[best].head = heap[0].head;
            heap[0].low = bestLow;
            heap[0].head = bestHead;
        }
        round.champion = uint64(bestHead);
        round.phase = 2;
        (,,,, uint256 recycled,) = _payTerms(round);
        if (recycled != 0) _releaseToFuture(recycled);
        emit DecimatorRanked(lvl, uint64(bestHead), uint8(winners));
        return units + (winners - winners / 2) * RANK_NODE_UNITS;
    }

    /// @dev Move part of a sealed round's reservation back to future prizes (pending while frozen).
    function _releaseToFuture(uint256 amount) private {
        claimablePool -= uint128(amount);
        if (prizePoolFrozen) {
            (uint128 pendingNext, uint128 pendingFuture) = _getPendingPools();
            _setPendingPools(pendingNext, pendingFuture + uint128(amount));
        } else {
            _setFuturePrizePool(_getFuturePrizePool() + amount);
        }
    }

    function _finish(DecBattleRound storage round) private {
        uint24 next = round.next;
        round.phase = 3;
        decBattleQueue = next == 0 ? 0 : (decBattleQueue & (uint256(type(uint24).max) << 24)) | next;
    }

    function _entryKey(uint24 lvl, uint64 id) private pure returns (uint256) {
        return (uint256(lvl) << 64) | id;
    }
}
