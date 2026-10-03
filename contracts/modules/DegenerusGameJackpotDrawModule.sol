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
    event JackpotEthWin(address indexed winner, uint24 indexed level, uint16 indexed traitId,
        uint256 amount, uint256 entryIndex);
    event JackpotTicketWin(address indexed winner, uint24 indexed entryLevel, uint16 indexed traitId,
        uint32 entryCount, uint24 sourceLevel, uint256 entryIndex, bool roundedUp);

    bytes32 private constant FLIP_LEVEL_TAG = keccak256("coin-level");
    bytes32 private constant FAR_FUTURE_FLIP_TAG = keccak256("far-future-coin");
    uint256 private constant JACKPOT_BATTLE_ENTRANTS = JackpotBattleFieldLib.MAX_CHUNK;
    uint256 private constant COIN_DRAW_SHARES = 50;

    event JackpotFlipWin(address indexed winner, uint24 indexed level, uint8 indexed traitId,
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
        address[4] memory deityCache;
        for (uint8 t; t < 4; ) {
            uint8 trait = traitIds[t];
            deityCache[t] = _traitDeity(trait);
            unchecked { ++t; }
        }

        uint24 range = maxLevel - minLevel + 1;
        PackedTicketSampleLib.Cursor[] memory cursors = new PackedTicketSampleLib.Cursor[](uint256(range) * 4);

        address[] memory players = new address[](cap);
        uint256[] memory amounts = new uint256[](cap);
        uint256 paid;
        for (uint256 i; i < cap; ) {
            uint8 traitIdx = uint8(i & 3);
            uint8 trait_i = traitIds[traitIdx];
            (address winner, uint24 lvlPrime, uint256 ticketIdx) = _drawCoinEntry(
                minLevel, range, trait_i, deityCache[traitIdx], randomWord, i, cursors
            );
            if (winner != address(0)) {
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
        address deity,
        uint256 randomWord,
        uint256 pull,
        PackedTicketSampleLib.Cursor[] memory cursors
    ) private view returns (address winner, uint24 lvl, uint256 index) {
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
    ///      JACKPOT_BATTLE_ENTRANTS awarded entries (see _collectJackpotChunk), reads their saved
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
                uint256 childAllowance = MineFlipGas.forwardable(MineFlipGas.remaining(meter), 100_000);
                if (childAllowance == 0) return result;
                result = IJackpotBattleMeter(ContractAddresses.CRAPS).runDailyBattleWork(childAllowance);
            }
            if (result.done) {
                dailyTicketBudgetsPacked &= ~_JACKPOT_BATTLE_PENDING;
                result.progressed = true;
            }
            MineFlipGas.finish(meter);
            return result;
        }
        // Each checkpoint appends at most 50 seats. The bound includes all cold
        // recipient writes, the collision-heavy board dedupe, seal and credits.
        if (!MineFlipGas.canRun(meter, GasBounds.JACKPOT_BATTLE_DRAW, GasBounds.DAILY_PHASE_TAIL)) return result;
        uint256 battleWord = uint256(keccak256(abi.encode(rngWord, lvl, FAR_FUTURE_FLIP_TAG)));
        (uint256 word, uint256 cursor, uint256 remaining) = battle.prepareJackpotBattle(lvl, battleWord);
        do {
            (address[] memory winners, uint256 next, bool exhausted) = _collectJackpotChunk(lvl, word, cursor, remaining);
            uint256[] memory field = JackpotBattleFieldLib.prepare(winners);
            bool last = exhausted || winners.length == remaining;
            battle.appendJackpotBattle(field, next, last);
            result.progressed = true;
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

    /// @dev Snapshot the eligible levels once (99 bounded queue reads), then collect at most
    ///      JACKPOT_BATTLE_ENTRANTS seats per call by walking randomly selected levels. Repeated
    ///      wallets keep separate seats. Cursor: next visit ordinal [0:31], eligible-level bitset
    ///      [32:130], active level offset [131:137], next queue position [138:169], positions left
    ///      in the visit [170:201]. A chunk boundary never starts a new visit or changes its draw.
    ///      All registries and queues remain frozen under the daily lock, including across
    ///      midnight and retries. Packed queue words are loaded once per group of up to eight.
    function _collectJackpotChunk(uint24 lvl, uint256 word, uint256 cursor, uint256 remaining)
        internal view returns (address[] memory winners, uint256 next, bool exhausted)
    {
        uint256 eligible = (cursor >> 32) & ((uint256(1) << 99) - 1);
        uint24[99] memory levels;
        uint256 count;
        for (uint256 offset; offset < 99; ++offset) {
            uint24 candidate = lvl + 1 + uint24(offset);
            bool live = cursor == 0 ? _ticketQueueLength(_tqFarFutureKey(candidate)) != 0
                : eligible & (uint256(1) << offset) != 0;
            if (live) {
                eligible |= uint256(1) << offset;
                levels[count++] = candidate;
            }
        }
        uint256 wanted = remaining < JACKPOT_BATTLE_ENTRANTS ? remaining : JACKPOT_BATTLE_ENTRANTS;
        if (count == 0) return (new address[](0), 0, true);
        winners = new address[](wanted);
        JackpotDrawWalk memory walk = JackpotDrawWalk(
            uint32(cursor), (cursor >> 131) & 127, uint32(cursor >> 138), uint32(cursor >> 170)
        );
        uint256 i;
        while (i < wanted) {
            uint256 entropy;
            if (walk.left == 0) {
                entropy = EntropyLib.hash2(word, walk.ordinal++);
                walk.offset = levels[entropy % count] - lvl - 1;
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
                winners[i++] = _ticketOwnerAt(uint32(_tqWordAt(queue, 0)));
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
                    winners[i++] = _ticketOwnerAt(uint32(packed));
                    packed >>= 32;
                }
                walk.position += lanes;
                if (walk.position == len) walk.position = 0;
                take -= lanes;
            }
        }
        next = walk.ordinal | (eligible << 32) | (walk.offset << 131)
            | (walk.position << 138) | (walk.left << 170);
    }

    // -------------------------------------------------------------------------
    // Reward Jackpots (BAF + Decimator Dispatch)
    // -------------------------------------------------------------------------

    /**
     * @notice Execute BAF (Big-Ass Flip) jackpot distribution.
     * @dev Large winners (>=5% of pool) receive 50% ETH / 50% lootbox.
     *      Small winners (<5% of pool) alternate: even-index gets 100% ETH,
     *      odd-index gets 100% lootbox (gas-efficient batching).
     *
     * @param poolWei Total ETH for BAF distribution.
     * @param lvl Level triggering the BAF.
     * @param rngWord VRF entropy for winner selection.
     * @return claimableDelta ETH credited to claimable balances.
     *         Refund, lootbox, and whale pass ETH stay in futurePool implicitly.
     *
     * ## Payout Split
     *
     * | Winner Size        | Portion | Reward Type                              |
     * |--------------------|---------|------------------------------------------|
     * | Large (>=5% pool)  | 50%     | Claimable ETH (immediate)                |
     * | Large (>=5% pool)  | 50%     | Lootbox future tickets (claimWhalePass)  |
     * | Small even-index   | 100%    | Claimable ETH (immediate)                |
     * | Small odd-index    | 100%    | Lootbox future tickets                   |
     *
     * ## Lootbox Flow (Tiered by Amount)
     *
     * **All payouts:**
     * - Large lootbox payouts defer via `claimWhalePass` for gas safety
     *
     * All lootbox ETH stays in futurePrizePool (source pool).
     *
     */
    function runBafJackpot(
        uint256 poolWei,
        uint24 lvl,
        uint256 rngWord
    ) external returns (uint256 claimableDelta) {
        if (msg.sender != address(this)) revert OnlySelf();
        // Get winners and payout info from jackpots contract
        (address[] memory winnersArr, uint256[] memory amountsArr, ) = jackpots
            .runBafJackpot(poolWei, lvl, rngWord);

        // ---------------------------------------------------------------------
        // Process each winner with gas-optimized payout structure
        // Large winners (>=5% of pool): 50% ETH, 50% lootbox (balanced)
        // Small winners (<5% of pool): alternate 100% ETH or 100% lootbox (gas-efficient)
        // ---------------------------------------------------------------------

        uint256 largeWinnerThreshold = poolWei / 20; // 5% of total BAF pool

        // Ticket-roll floor. A roll can land on the floor level exactly (its 30% leg), and the
        // swap that would commit that queue already fired at this level's RNG request. A normal
        // phase swaps again on jackpot day 2 and drains lvl there, so the floor is lvl. Turbo
        // collapses the whole phase inside one lock — no further swap fires for the level, so
        // a floor-lvl award would be committed and materialized only after lvl's draws ended
        // (the trailing sweep reaches it, but drawless). Route the floor one level out so the
        // awards land where they still draw.
        uint24 ticketFloorLvl = (jackpotFlags & JACKPOT_TURBO) != 0 ? lvl + 1 : lvl;

        uint256 winnersLen = winnersArr.length;
        for (uint256 i; i < winnersLen; ) {
            address winner = winnersArr[i];
            uint256 amount = amountsArr[i];

            // Large winners: keep 50/50 split for balanced payout
            if (amount >= largeWinnerThreshold) {
                uint256 ethPortion = amount / 2;
                uint256 lootboxPortion = amount - ethPortion;

                // Credit ETH half to claimable balance
                _creditClaimable(winner, ethPortion);
                claimableDelta += ethPortion;
                emit JackpotEthWin(winner, lvl, BAF_TRAIT_SENTINEL, ethPortion, 0);

                // Lootbox half: small amounts awarded immediately, large deferred
                if (lootboxPortion <= LOOTBOX_CLAIM_THRESHOLD) {
                    // Small lootbox: award immediately (2 rolls, probabilistic targeting).
                    // JackpotTicketWin is emitted per-roll inside _jackpotTicketRoll
                    // with the real targetLevel and scaled ticketCount.
                    uint256 cd;
                    (, cd) = _awardJackpotTickets(
                        winner,
                        lootboxPortion,
                        ticketFloorLvl,
                        EntropyLib.hash4(rngWord, lvl, BAF_TICKET_TAG, i)
                    );
                    claimableDelta += cd;
                } else {
                    // Large lootbox: defer to claim (whale pass equivalent). The sub-half-pass
                    // remainder is folded into claimableDelta so the caller's memFuture debit
                    // and claimablePool credit both move it out of futurePool exactly once.
                    claimableDelta += _queueWhalePassClaimCore(winner, lootboxPortion);
                    emit JackpotWhalePassWin(
                        winner,
                        lootboxPortion / HALF_WHALE_PASS_PRICE,
                        WHALE_PASS_SRC_BAF_DIRECT
                    );
                }
            }
            // Small winners: alternate between 100% ETH and 100% lootbox for gas efficiency
            else if (i % 2 == 0) {
                // Even index: 100% ETH (immediate liquidity)
                _creditClaimable(winner, amount);
                claimableDelta += amount;
                emit JackpotEthWin(winner, lvl, BAF_TRAIT_SENTINEL, amount, 0);
            } else {
                // Odd index: 100% lootbox (upside exposure).
                // JackpotTicketWin is emitted per-roll inside _jackpotTicketRoll;
                // whale-pass fallback (amount > LOOTBOX_CLAIM_THRESHOLD) emits
                // JackpotWhalePassWin inside _awardJackpotTickets.
                uint256 cd;
                (, cd) = _awardJackpotTickets(
                    winner,
                    amount,
                    ticketFloorLvl,
                    EntropyLib.hash4(rngWord, lvl, BAF_TICKET_TAG, i)
                );
                claimableDelta += cd;
            }

            unchecked {
                ++i;
            }
        }

        // Ticket-leg lootbox ETH stays in futurePool implicitly. The ETH halves and the
        // whale-pass remainders are returned in claimableDelta, which the caller deducts
        // from memFuture and credits to claimablePool in one batch. No storage write here.
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
     * @param winner Address to receive rewards.
     * @param amount ETH amount for ticket conversion.
     * @param minTargetLevel Minimum target level for tickets.
     * @param entropy RNG state.
     * @return newEntropy Updated entropy state.
     * @return claimableDelta Wei credited to claimableWinnings on the whale-pass remainder leg
     *         (0 on the ticket-roll legs), folded by the caller into futurePool→claimablePool.
     */
    function _awardJackpotTickets(
        address winner,
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
        address winner,
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
