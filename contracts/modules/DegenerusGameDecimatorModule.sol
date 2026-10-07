// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {MineFlipGasBounds as GasBounds} from "../libraries/MineFlipGasBounds.sol";

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
import {DecimatorSamplingLib as Sampling} from "../libraries/DecimatorSamplingLib.sol";
import {MineFlipGas} from "../libraries/MineFlipGas.sol";
import {Craps} from "../Craps.sol";
import {DecimatorJackpotTerms} from "../interfaces/IDegenerusGameModules.sol";

interface IDecimatorBoardPreference {
    function preferredBoardOf(uint32 walletId) external view returns (uint32 chips);
}

/// @dev Pinned stateless engine. The pure ABI ensures a STATICCALL from the Game context.
interface IDecimatorCrapsEngine {
    function settleSlipBounded(
        uint256 packedChips,
        uint256 chipFlip,
        uint256 scatterHash,
        uint256 scatterCount,
        bytes32 seed,
        uint256 bankroll,
        uint256 salt,
        uint256 boost,
        uint256 bounds
    ) external pure returns (Craps.SlipResult memory);
}

/// @notice Shared-dice Decimator battle. All runs, ranking and ETH credits execute on chain.
/// @dev Delegatecalled by Game. A sealed round finishes on the active session word before
///      the next request can replace it. No transaction walks the unbounded entrant population.
contract DegenerusGameDecimatorModule is DegenerusGameStorage {
    // Pure engine amounts retain fractional simulation precision independently of FLIP decimals.
    uint256 private constant SCALE = 3000 * 1e18;
    bytes32 private constant DICE_TAG = keccak256("decimator.battle.dice.v1");
    bytes32 private constant BOARD_TAG = keccak256("decimator.battle.board.v1");
    bytes32 private constant TIE_TAG = keccak256("decimator.battle.tie.v1");
    bytes32 private constant GEN_PLAYER_TAG = keccak256("decimator.battle.generated.player.v1");
    bytes32 private constant GEN_DRAW_TAG = keccak256("decimator.battle.generated.recipient.v1");

    // Admission bounds cover one indivisible run/rank/payment, not a debited currency.
    // Actual elapsed gas determines how much allowance remains after each operation.
    uint256 private constant RUN_GAS_MAX = GasBounds.DECIMATOR_RUN_GAS_MAX;
    uint256 private constant RANK_GAS_MAX = GasBounds.DECIMATOR_RANK_GAS_MAX;
    uint256 private constant PAYMENT_GAS_MAX = GasBounds.DECIMATOR_PAYMENT_GAS_MAX;
    uint256 private constant WORK_TAIL_GAS = GasBounds.DECIMATOR_WORK_TAIL_GAS;

    // A run stops at bust, after 48 shooters, or at exactly 511 rolls, the longest cut the engine
    // makes exactly (a roll budget of 512 or more is judged between shooters). A safety bound for
    // the budget, not a rule of play: none of 200,000 simulated shared-dice runs over every board
    // size came near it (the longest ran 430 rolls and 36 shooters), and 70 of 286 million engine
    // runs across every strategy reached 511 rolls. The complete run remains atomic across keeper checkpoints.
    uint256 private constant RUN_BOUNDS = (511 << 16) | 48;

    // An entry word: owner in bits 0..159, the chosen board's thirty chip bits at 160, and the
    // stack in whole FLIP of virtual chips in the top 66 bits.
    uint256 private constant CHIPS_SHIFT = 160;
    uint256 private constant STACK_SHIFT = 190;
    // A node's score sits above the 64-bit id. With ten 60-FLIP chips, at most 511 rolls,
    // 48 shooters (escalation <= 2^27) and at most 30% boost, peak < 2^110.
    // Even a full 66-bit stack therefore produces a score below the 192-bit lane.

    event DecBurnRecorded(
        uint32 indexed player,
        uint24 indexed lvl,
        uint64 indexed entryId,
        uint256 baseAmount,
        uint256 credited,
        uint256 stack,
        uint32 chips
    );
    event DecimatorResolved(uint24 indexed lvl, uint256 rngWord, uint256 poolWei, uint64 entrants);
    event DecimatorReferenceUpdated(uint24 indexed lvl, uint64 totalCreditedStack, uint40 entrants);
    event DecimatorFieldBound(uint24 indexed lvl, uint40 fieldEntries, uint8 capacity);
    event DecimatorJackpotPlan(
        uint24 indexed lvl, uint256 word, uint96 originalPool, uint64 originalStack, uint40 originalCount,
        uint128 availableBudget, uint96 funding, uint128 soloAmount, uint32 traits,
        uint40 generatedEntries, uint64 weights
    );
    /// @dev Sampled generated entries only; survivors replay from the plan and sealed word.
    event DecimatorGenerated(
        uint24 indexed lvl, uint64 indexed id, uint32 indexed recipientId, uint8 quadrant,
        uint32 chips, uint256 normalizedPeak, uint256 score
    );
    /// @dev Sampled original runs only; losers are never visited.
    event DecimatorRun(uint24 indexed lvl, uint64 indexed entryId, uint256 normalizedPeak);
    event DecimatorRanked(uint24 indexed lvl, uint64 champion, uint8 winners);
    /// @dev `amountWei` is the ETH credited; `halfPasses` the half whale passes queued instead.
    event DecimatorClaimed(
        uint32 indexed walletId, uint24 indexed lvl, uint64 indexed entryId, uint256 amountWei, uint256 halfPasses
    );

    /// @param chips The entry's board as a normal battle takes it: ten three-bit leg counts naming
    ///        zero to seven chips; the dice scatter the rest of the ten. Each burn sets it.
    function recordDecBurn(uint32 playerId, uint24 lvl, uint256 baseAmount, uint256 multBps, uint32 chips)
        public
        returns (uint64 id)
    {
        if (msg.sender != ContractAddresses.COIN) revert E();
        _checkBoard(chips);
        DecBattleRound storage round = decBattleRounds[lvl];
        if (
            gameOver || !_decWindowOpen() || lvl != level + 1 || round.phase != 0 || playerId == 0
                || baseAmount == 0 || multBps < 10_000 || multBps > 20_000
        ) revert E();
        uint24 day = _simulatedDayIndex();
        if (round.openedDay == 0 || day < round.openedDay) revert E();
        // FLIP has already registered the burner and supplies its allocated ID.
        uint256 factor = _dayFactor(day - round.openedDay);
        // Round once to whole FLIP. The uint64 aggregate bound keeps every accepted numerator below 2^138.
        uint256 credited = baseAmount * (factor * multBps) / (1 ether * 10_000);
        if (credited == 0) revert E();
        // The wallet slot finds a top-up; a new window's first burn overwrites it. Settlement reads
        // only the entry, so an older round still in the queue keeps its own.
        uint256 latest = decBattlePlayers[playerId];
        uint256 stack;
        if (uint24(latest >> 64) == lvl) {
            id = uint64(latest);
            stack = decBattleEntries[_entryKey(lvl, id)] >> STACK_SHIFT;
        } else {
            id = ++round.count;
            decBattlePlayers[playerId] = (uint256(lvl) << 64) | id;
        }
        // The checked 64-bit aggregate also bounds each stack inside its 66-bit entry lane.
        uint256 total = uint256(round.totalCreditedStack) + credited;
        if (total > type(uint64).max) revert E();
        stack += credited;
        round.totalCreditedStack = uint64(total);
        decBattleEntries[_entryKey(lvl, id)] =
            (stack << STACK_SHIFT) | (uint256(chips) << CHIPS_SHIFT) | uint256(playerId);
        emit DecBurnRecorded(playerId, lvl, id, baseAmount, credited, stack, chips);
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
        // A seal the session cannot take hands the pool back unsealed: the round keeps its
        // entries at phase 0, the pool stays with the caller and no entrant is paid.
        if (_decWindowOpen() || poolWei > type(uint96).max || decBattleQueue != 0
            || rngWord <= RNG_WORD_WAITING || rngWord != _lootboxWord(_rngReadBuffer())) return poolWei;
        _setRngComplete(false);
        round.poolWei = uint96(poolWei);
        decPreviousStack = round.totalCreditedStack;
        decPreviousCount = round.count;
        emit DecimatorReferenceUpdated(lvl, round.totalCreditedStack, round.count);
        round.capacity = _quota(round.count);
        if (lvl % 10 == 5 && lvl % 100 != 95 && poolWei != 0) {
            decJackpotPlans[lvl].mode = 1;
        } else {
            emit DecimatorFieldBound(lvl, round.count, round.capacity);
        }
        round.phase = 1;
        decBattleQueue = uint256(lvl) | (uint256(lvl) << 24);
        emit DecimatorResolved(lvl, rngWord, poolWei, round.count);
    }

    /// @dev Only the trusted Jackpot delegate dispatcher can reach this entry in Game context.
    ///      Funding and JackpotWork.paid are owned here; the caller must not debit them again.
    function runDecimatorJackpotAwards(DecimatorJackpotTerms calldata terms, uint256 allowance)
        external returns (MineFlipGas.Result memory result, uint256 soloAmount)
    {
        MineFlipGas.Meter memory meter = MineFlipGas.start(allowance);
        uint24 lvl = jackpotWork.lvl;
        DecBattleRound storage round = decBattleRounds[lvl];
        DecJackpotPlan storage plan = decJackpotPlans[lvl];
        if (plan.mode == 1) {
            if (!MineFlipGas.canRun(meter, GasBounds.DECIMATOR_PLAN_GAS_MAX, WORK_TAIL_GAS)) return (result, 0);
            _initializeJackpot(lvl, round, plan, terms);
            result.progressed = true;
            ++result.rewardBasis;
        }
        Sampling.Field memory field = Sampling.field(terms.word, lvl, uint256(round.count) + plan.generatedEntries);
        if (plan.generatedEntries == 0) field.count = 0;
        // Each entry commits before reusing temporary ABI/engine memory.
        uint256 free;
        assembly ("memory-safe") { free := mload(0x40) }
        while (plan.cursor < field.count) {
            uint64 id = Sampling.sample(terms.word, lvl, field, plan.cursor);
            bool generated = id > round.count;
            if (!MineFlipGas.canRun(meter, generated ? GasBounds.DECIMATOR_GENERATED_GAS_MAX
                : GasBounds.DECIMATOR_SAMPLE_SKIP_GAS_MAX, WORK_TAIL_GAS)) break;
            if (generated) _runGenerated(lvl, round, plan, terms.word, id - round.count);
            ++plan.cursor;
            ++result.rewardBasis;
            result.progressed = true;
            assembly ("memory-safe") { mstore(0x40, free) }
        }
        result.done = plan.cursor == field.count;
        soloAmount = plan.soloAmount;
        MineFlipGas.finish(meter);
    }

    function _initializeJackpot(
        uint24 lvl, DecBattleRound storage round, DecJackpotPlan storage plan, DecimatorJackpotTerms calldata terms
    ) private {
        uint256 activeNonSolo;
        uint64 weights;
        for (uint8 q; q < 4; ++q) {
            if (q == terms.solo) continue;
            uint8 trait = uint8(jackpotWork.traits >> (uint256(q) * 8));
            uint256 len = _bucketLengthUnchecked(lvl, trait);
            uint32 deity = _traitDeity(trait);
            bool active = len + _deityVirtualCount(trait, len, deity) != 0;
            uint256 share = active ? terms.shares[q] : 0;
            uint16 weight = share == 0 ? 0 : terms.targets[q];
            activeNonSolo += share;
            weights |= uint64(weight) << (uint256(q) * 16);
        }
        uint256 soloShare = terms.shares[terms.solo];
        uint256 floor = (terms.shares[0] + terms.shares[1] + terms.shares[2] + terms.shares[3]) * 35 / 100;
        uint256 available = activeNonSolo + (soloShare > floor ? soloShare - floor : 0);
        uint256 n = round.count;
        uint96 originalPool = round.poolWei;
        // available <= uint128 and n <= uint40; both products fit ordinary uint256 math.
        // An empty generated cohort cannot spend even the solo contribution.
        uint256 entries = weights == 0 ? 0 : available * n / originalPool;
        if (entries > n) entries = n;
        uint256 funding = (entries * originalPool + n - 1) / n;
        uint256 pool = uint256(originalPool) + funding;
        if (pool > type(uint96).max) revert E();
        uint256 solo = activeNonSolo + soloShare - funding;
        if (solo > soloShare) solo = soloShare;
        plan.generatedEntries = uint40(entries);
        plan.soloAmount = uint128(solo);
        plan.weights = weights;
        plan.mode = 2;
        round.poolWei = uint96(pool);
        round.capacity = _quota(n + entries);
        if (funding != 0) {
            _setCurrentPrizePool(_getCurrentPrizePool() - funding);
            claimablePool += uint128(funding);
            jackpotWork.paid += uint128(funding);
        }
        emit DecimatorJackpotPlan(lvl, terms.word, originalPool, round.totalCreditedStack, round.count,
            uint128(available), uint96(funding), plan.soloAmount, jackpotWork.traits, plan.generatedEntries, weights);
    }

    function _runGenerated(uint24 lvl, DecBattleRound storage round, DecJackpotPlan storage plan,
        uint256 word, uint64 ordinal)
        private
    {
        uint64 weights = plan.weights;
        uint256 totalWeight = uint256(uint16(weights)) + uint16(weights >> 16)
            + uint16(weights >> 32) + uint16(weights >> 48);
        uint8 q;
        uint256 cumulative = uint16(weights);
        while (q < 3 && ordinal > uint256(plan.generatedEntries) * cumulative / totalWeight) {
            ++q;
            cumulative += uint16(weights >> (uint256(q) * 16));
        }
        uint8 trait = uint8(jackpotWork.traits >> (uint256(q) * 8));
        uint256 len = _bucketLengthUnchecked(lvl, trait);
        uint32 deity = _traitDeity(trait);
        uint256 effectiveLen = len + _deityVirtualCount(trait, len, deity);
        // Allocation selects a nonempty cohort; the daily lock preserves it through every entry.
        uint64 id = uint64(round.count) + ordinal;
        uint256 index = uint256(keccak256(abi.encode(GEN_DRAW_TAG, word, lvl, id, q, trait))) % effectiveLen;
        uint32 owner = index < len ? _bucketIdAtUnchecked(lvl, trait, index) : deity;
        // Every lane and deity holds a nonzero wallet ID; Craps validates boards when saving them.
        uint32 chips = IDecimatorBoardPreference(ContractAddresses.CRAPS).preferredBoardOf(owner);
        // A generated entry is not a wallet: its survival salt is a 160-bit hash of its own id.
        Craps.SlipResult memory run = _settleRun(
            chips, uint256(keccak256(abi.encode(BOARD_TAG, word, lvl, id))),
            keccak256(abi.encode(DICE_TAG, word, lvl)),
            uint160(uint256(keccak256(abi.encode(GEN_PLAYER_TAG, word, lvl, id))))
        );
        uint256 score = uint256(round.totalCreditedStack) * run.peakBankroll / round.count;
        (uint256 winners, bool retained) = _insert(lvl, word, round.capacity, round.winners, (score << 64) | id);
        round.winners = uint8(winners);
        if (retained) decGeneratedOwners[ordinal] = owner;
        emit DecimatorGenerated(lvl, id, owner, q, chips, run.peakBankroll, score);
    }

    /// @notice Resolve the next Decimator obligation within its available gas.
    function runDecimatorWork(uint256 gasAllowance) external returns (MineFlipGas.Result memory) {
        return _runDecimatorWork(gasAllowance);
    }

    function _runDecimatorWork(uint256 gasAllowance) private returns (MineFlipGas.Result memory result) {
        MineFlipGas.Meter memory meter = MineFlipGas.start(gasAllowance);
        uint24 lvl = uint24(decBattleQueue);
        if (lvl == 0) { result.done = true; return result; }
        if (_rngConsumerStage() != 5) return result;
        DecBattleRound storage round = decBattleRounds[lvl];
        uint256 word = _lootboxWord(_rngReadBuffer());
        DecJackpotPlan storage plan = decJackpotPlans[lvl];
        if (round.phase == 1) {
            uint64 cursor = round.cursor;
            Sampling.Field memory field = Sampling.field(word, lvl, uint256(round.count) + plan.generatedEntries);
            if (cursor < field.count) {
                uint256 capacity = round.capacity;
                uint256 winners = round.winners;
                uint256 winnersBefore = winners;
                bytes32 seed = keccak256(abi.encode(DICE_TAG, word, lvl));
                uint256 free;
                assembly ("memory-safe") { free := mload(0x40) }
                while (cursor < field.count) {
                    uint64 id = Sampling.sample(word, lvl, field, cursor);
                    bool original = id <= round.count;
                    if (!MineFlipGas.canRun(meter, original ? RUN_GAS_MAX
                        : GasBounds.DECIMATOR_SAMPLE_SKIP_GAS_MAX, WORK_TAIL_GAS)) break;
                    if (original) winners = _run(lvl, id, word, seed, capacity, winners);
                    ++cursor;
                    ++result.rewardBasis;
                    assembly ("memory-safe") { mstore(0x40, free) }
                }
                if (cursor != round.cursor) {
                    round.cursor = cursor;
                    result.progressed = true;
                }
                if (winners != winnersBefore) round.winners = uint8(winners);
            }
            // Phase boundaries are gas checkpoints: finish the simulation's writes before
            // ranking, then continue into payments whenever their existing bounds fit.
            if (cursor == field.count && MineFlipGas.canRun(meter, RANK_GAS_MAX, WORK_TAIL_GAS)) {
                _rank(lvl, round, word);
                result.progressed = true;
                ++result.rewardBasis;
            }
        }
        // Zero capacity finishes at phase 3, without zero-winner division.
        if (round.phase == 2) {
            uint256 winners = round.winners;
            uint256 paid = round.paid;
            (uint256 base, uint256 champ, uint256 champPasses, uint256 perEth,, bool passMode) = _payTerms(round);
            mapping(uint256 => uint256) storage heap = decBattleHeap;
            while (paid < winners) {
                if (!MineFlipGas.canRun(meter, PAYMENT_GAS_MAX, WORK_TAIL_GAS)) break;
                uint64 id = uint64(heap[paid]);
                uint32 owner = id > round.count ? decGeneratedOwners[id - round.count]
                    : uint32(decBattleEntries[_entryKey(lvl, id)]);
                if (paid == 0) {
                    if (champPasses != 0) _addHalfPasses(owner, champPasses);
                    uint256 eth = champ - champPasses * HALF_WHALE_PASS_PRICE;
                    _creditClaimable(owner, eth);
                    emit DecimatorClaimed(owner, lvl, id, eth, champPasses);
                } else if (passMode && paid & 1 == 0) {
                    uint256 halfPasses = base / HALF_WHALE_PASS_PRICE;
                    _addHalfPasses(owner, halfPasses);
                    emit DecimatorClaimed(owner, lvl, id, 0, halfPasses);
                } else {
                    _creditClaimable(owner, base + perEth);
                    emit DecimatorClaimed(owner, lvl, id, base + perEth, 0);
                }
                ++paid;
                ++result.rewardBasis;
            }
            if (paid != round.paid) {
                round.paid = uint8(paid);
                result.progressed = true;
            }
            if (paid == winners && MineFlipGas.canRun(meter, 30_000, WORK_TAIL_GAS)) {
                _finish(round);
                result.progressed = true;
            }
        }
        result.done = decBattleQueue == 0;
        MineFlipGas.finish(meter);
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
        returns (uint256)
    {
        // Only sampled survivors reach the engine; original IDs are never scanned.
        uint256 entry = decBattleEntries[_entryKey(lvl, id)];
        // The board was checked at burn, so settlement only counts its named chips. The owner's
        // wallet ID, committed with the burn, salts the survival coin.
        uint256 chips = (entry >> CHIPS_SHIFT) & 0x3FFFFFFF;
        Craps.SlipResult memory run = _settleRun(
            chips, uint256(keccak256(abi.encode(BOARD_TAG, word, lvl, id))), seed, uint32(entry)
        );
        emit DecimatorRun(lvl, id, run.peakBankroll);
        uint256 score = (entry >> STACK_SHIFT) * run.peakBankroll;
        (uint256 retained,) = _insert(lvl, word, capacity, winners, (score << 64) | id);
        return retained;
    }

    /// @dev Ten 60-FLIP chips, ordinary scatter/boost and shared dice. Normalize only engine
    ///      units; callers weight the peak by the original stack or the frozen original mean.
    function _settleRun(uint256 chips, uint256 board, bytes32 seed, uint256 salt)
        private pure returns (Craps.SlipResult memory)
    {
        uint256 named = _named(chips);
        return IDecimatorCrapsEngine(ContractAddresses.CRAPS_ENGINE).settleSlipBounded(
            chips, 60, board, 10 - named, seed, SCALE, salt,
            (0x050c070c0a0c0e0c120c140c190c1e0c >> (named << 4)) & 0xFFFF, RUN_BOUNDS
        );
    }

    function _quota(uint256 entries) private pure returns (uint8) {
        uint256 places = (entries + 9) / 10;
        if (places < 20) places = 20;
        if (places > entries / 2) places = entries / 2;
        return uint8(places > 200 ? 200 : places);
    }

    /// @dev Min heap: the weakest retained eligible entry is at the root. At most 200 nodes. A
    ///      filling insert takes the next position; the first round ever to reach it pays for
    ///      fresh slots, every later round reuses them.
    function _insert(uint24 lvl, uint256 word, uint256 capacity, uint256 size, uint256 node)
        private
        returns (uint256, bool)
    {
        if (capacity == 0) return (0, false);
        mapping(uint256 => uint256) storage heap = decBattleHeap;
        uint256 pos;
        if (size < capacity) {
            pos = size;
            ++size;
            while (pos != 0) {
                uint256 parent = (pos - 1) / 2;
                uint256 p = heap[parent];
                if (!_less(word, lvl, node, p)) break;
                heap[pos] = p;
                pos = parent;
            }
        } else {
            if (!_less(word, lvl, heap[0], node)) return (size, false);
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
            }
        }
        heap[pos] = node;
        return (size, true);
    }

    /// @dev Score order (the bits above the id), then the random tiebreak, then the entry id.
    function _less(uint256 word, uint24 lvl, uint256 a, uint256 b) private pure returns (bool) {
        if (a >> 64 != b >> 64) return a >> 64 < b >> 64;
        return _tieKey(word, lvl, uint64(a)) < _tieKey(word, lvl, uint64(b));
    }

    function _tieKey(uint256 word, uint24 lvl, uint64 id) private pure returns (uint256) {
        return (uint256(keccak256(abi.encode(TIE_TAG, word, lvl, id))) & ~uint256(type(uint64).max)) | id;
    }

    function _rank(uint24 lvl, DecBattleRound storage round, uint256 word) private {
        uint256 winners = round.winners;
        if (winners == 0) {
            _releaseToFuture(round.poolWei);
            _finish(round);
            emit DecimatorRanked(lvl, 0, 0);
            return;
        }
        mapping(uint256 => uint256) storage heap = decBattleHeap;
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
        emit DecimatorRanked(lvl, round.champion, uint8(winners));
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
        _tryCompleteRng();
    }

    function _entryKey(uint24 lvl, uint64 id) private pure returns (uint256) {
        return (uint256(lvl) << 64) | id;
    }
}
