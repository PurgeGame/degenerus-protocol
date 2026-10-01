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
    uint256 private constant MAX_BUDGET = 2500;
    bytes32 private constant DICE_TAG = keccak256("decimator.battle.dice.v1");
    bytes32 private constant BOARD_TAG = keccak256("decimator.battle.board.v1");
    bytes32 private constant COIN_TAG = keccak256("decimator.battle.final-coin.v1");
    bytes32 private constant TIE_TAG = keccak256("decimator.battle.tie.v1");

    // Keeper work units (4.7k gas each), charged after each piece of work from its outcome and
    // sized on worst cases: the call frame with a first cursor write (~37k inside mineFlip's
    // delegatecall), a tails coin (~0.8k), a heads run's fixed cost with its one entry read plus
    // its dice (<= 723 gas a roll on any board), a filling insert into a fresh or reused node
    // slot, a heap level, a root reject, a scanned leaf, an ETH credit to an empty balance
    // (~30.5k), and a half-pass award with its share of the pool move (~23k fresh, plus ~10k once
    // a call). DecimatorPricing.t.sol pins every call, real dice and worst heap shapes alike, at
    // or under 90% of its charge with each call's storage cold, as a keeper transaction finds it.
    uint256 private constant CALL_UNITS = 9;
    uint256 private constant TAILS_UNITS = 1;
    uint256 private constant RUN_UNITS = 4;
    uint256 private constant ROLLS_PER_UNIT = 6;
    uint256 private constant INSERT_UNITS = 2;
    uint256 private constant INSERT_FRESH_UNITS = 6;
    uint256 private constant MOVE_UNITS = 2;
    uint256 private constant REJECT_UNITS = 1;
    uint256 private constant RANK_UNITS = 8;
    uint256 private constant RANK_NODE_UNITS = 1;
    uint256 private constant CREDIT_UNITS = 8;
    uint256 private constant PASS_UNITS = 6;

    // A run stops at bust, after 48 shooters, or at exactly 511 rolls, the longest cut the engine
    // makes exactly (a roll budget of 512 or more is judged between shooters). A safety bound for
    // the budget, not a rule of play: none of 200,000 simulated shared-dice runs over every board
    // size came near it (the longest ran 430 rolls and 36 shooters), and 70 of 286 million engine
    // runs across every strategy reached 511 rolls. The pair bounds a heads run at 108 units,
    // per-shooter cost included.
    uint256 private constant RUN_BOUNDS = (511 << 16) | 48;

    // An entry word: owner in bits 0..159, the chosen board's thirty chip bits at 160, and the
    // stack in whole FLIP of virtual chips in the top 66 bits.
    uint256 private constant CHIPS_SHIFT = 160;
    uint256 private constant STACK_SHIFT = 190;
    uint256 private constant MAX_STACK = (1 << 66) - 1;
    // A node's score sits above the 64-bit id. The engine's roll and shooter bounds keep a peak far
    // below 2^126 wei, so no real score reaches the cap; stack and score saturate rather than wrap.
    uint256 private constant MAX_SCORE = (1 << 192) - 1;

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
            gameOver || !_decWindowOpen() || lvl != level + 1 || round.phase != 0 || player == address(0)
                || baseAmount == 0 || multBps < 10_000 || multBps > 20_000
        ) revert E();
        uint24 day = _simulatedDayIndex();
        if (round.openedDay == 0 || day < round.openedDay) revert E();
        uint256 factor = _dayFactor(day - round.openedDay);
        // Whole FLIP of chips. Multiply timing first to avoid overflow for very large, heavily
        // decayed burns.
        uint256 credited = Math.mulDiv(baseAmount, factor * multBps, 1 ether * 10_000 * 1 ether);
        if (credited == 0) revert E();
        // The wallet slot finds a top-up; a new window's first burn overwrites it. Settlement reads
        // only the entry, so an older round still in the queue keeps its own.
        uint256 latest = decBattlePlayers[player];
        uint256 stack;
        if (uint24(latest >> 64) == lvl) {
            id = uint64(latest);
            stack = decBattleEntries[_entryKey(lvl, id)] >> STACK_SHIFT;
        } else {
            id = ++round.count;
            decBattlePlayers[player] = (uint256(lvl) << 64) | id;
        }
        stack += credited;
        // 2^66 FLIP is far past FLIP's supply; saturating keeps any history out of the other fields.
        if (stack > MAX_STACK) stack = MAX_STACK;
        decBattleEntries[_entryKey(lvl, id)] =
            (stack << STACK_SHIFT) | (uint256(chips) << CHIPS_SHIFT) | uint256(uint160(player));
        emit DecBurnRecorded(player, lvl, id, baseAmount, credited * 1 ether, stack * 1 ether, chips);
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
        if (_decWindowOpen() || poolWei > type(uint128).max) revert E();
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
            mapping(uint256 => uint256) storage heap = decBattleHeap;
            while (paid < winners && unitsUsed < budgetUnits) {
                uint64 id = uint64(heap[paid]);
                address owner = address(uint160(decBattleEntries[_entryKey(lvl, id)]));
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
        uint256 entry = decBattleEntries[_entryKey(lvl, id)];
        address owner = address(uint160(entry));
        // The board was checked at burn, so settlement only counts its named chips.
        uint256 chips = (entry >> CHIPS_SHIFT) & 0x3FFFFFFF;
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
        (uint256 high, uint256 score) = Math.mul512(entry >> STACK_SHIFT, result.peakBankroll);
        if (high != 0 || score > MAX_SCORE) score = MAX_SCORE;
        (units, winners) = _insert(lvl, word, capacity, winners, (score << 64) | id);
        return (units + RUN_UNITS + (result.totalRolls + ROLLS_PER_UNIT - 1) / ROLLS_PER_UNIT, winners);
    }

    /// @dev Min heap: the weakest retained eligible entry is at the root. At most 100 nodes. A
    ///      filling insert takes the next position; the first round ever to reach it pays for
    ///      fresh slots, every later round reuses them.
    function _insert(uint24 lvl, uint256 word, uint256 capacity, uint256 size, uint256 node)
        private
        returns (uint256 units, uint256)
    {
        mapping(uint256 => uint256) storage heap = decBattleHeap;
        uint256 pos;
        uint256 base = INSERT_UNITS;
        if (size < capacity) {
            pos = size;
            if (heap[pos] == 0) base = INSERT_FRESH_UNITS;
            ++size;
            while (pos != 0) {
                uint256 parent = (pos - 1) / 2;
                uint256 p = heap[parent];
                if (!_less(word, lvl, node, p)) break;
                heap[pos] = p;
                pos = parent;
                units += MOVE_UNITS;
            }
        } else {
            if (!_less(word, lvl, heap[0], node)) return (REJECT_UNITS, size);
            while (true) {
                uint256 child = pos * 2 + 1;
                if (child >= size) break;
                uint256 c = heap[child];
                if (child + 1 < size) {
                    uint256 d = heap[child + 1];
                    if (_less(word, lvl, d, c)) {
                        ++child;
                        c = d;
                    }
                }
                if (!_less(word, lvl, c, node)) break;
                heap[pos] = c;
                pos = child;
                units += MOVE_UNITS;
            }
        }
        heap[pos] = node;
        return (units + base, size);
    }

    /// @dev Score order (the bits above the id), then the random tiebreak, then the entry id.
    function _less(uint256 word, uint24 lvl, uint256 a, uint256 b) private pure returns (bool) {
        if (a >> 64 != b >> 64) return a >> 64 < b >> 64;
        return _tieKey(word, lvl, uint64(a)) < _tieKey(word, lvl, uint64(b));
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
        mapping(uint256 => uint256) storage heap = decBattleHeap;
        uint256 word = round.rngWord;
        // Every internal node of the min-heap is below a child, so the maximum is a leaf.
        uint256 i = winners / 2;
        uint256 best = i;
        uint256 bestNode = heap[i];
        for (++i; i < winners; ++i) {
            uint256 node = heap[i];
            if (_less(word, lvl, bestNode, node)) {
                best = i;
                bestNode = node;
            }
        }
        // Payouts need no heap order: the champion takes position 0, where they pay it first.
        if (best != 0) {
            heap[best] = heap[0];
            heap[0] = bestNode;
        }
        round.champion = uint64(bestNode);
        round.phase = 2;
        (,,,, uint256 recycled,) = _payTerms(round);
        if (recycled != 0) _releaseToFuture(recycled);
        emit DecimatorRanked(lvl, uint64(bestNode), uint8(winners));
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
