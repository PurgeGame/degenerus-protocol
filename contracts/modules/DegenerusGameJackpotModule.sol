// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {GoldSixLib} from "../libraries/GoldSixLib.sol";

import {MineFlipGasBounds as GasBounds} from "../libraries/MineFlipGasBounds.sol";

import {MineFlipGas} from "../libraries/MineFlipGas.sol";

import {DegenerusGameJackpotDrawUtils} from "./DegenerusGameJackpotDrawUtils.sol";

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

import {IStETH} from "../interfaces/IStETH.sol";
import {DegenerusGamePayoutUtils} from "./DegenerusGamePayoutUtils.sol";
import {ContractAddresses} from "../ContractAddresses.sol";
import {EntropyLib} from "../libraries/EntropyLib.sol";
import {PackedTicketSampleLib} from "../libraries/PackedTicketSampleLib.sol";
import {FlipRoundLib} from "../libraries/FlipRoundLib.sol";
import {PriceLookupLib} from "../libraries/PriceLookupLib.sol";
import {JackpotBucketLib} from "../libraries/JackpotBucketLib.sol";
import {IDegenerusGameWhaleModule, IDegenerusGameJackpotDrawModule} from "../interfaces/IDegenerusGameModules.sol";
import {IDegenerusJackpots} from "../interfaces/IDegenerusJackpots.sol";

/// @dev Minimal WWXRP surface for the golden-ticket consolation mint. The delegatecall
///      context makes msg.sender the Game, which is a whitelisted WWXRP minter.
interface IWwxrpMintPrize {
    /// @notice Mint WWXRP to a recipient (WWXRP, authorized minters only).
    function mintPrize(address to, uint256 amount) external;
}

/**
 * @title DegenerusGameJackpotModule
 * @author Burnie Degenerus
 * @notice Delegate-called module that hosts the jackpot distribution logic for `DegenerusGame`.
 *
 * @dev ARCHITECTURE NOTES:
 *      - This contract is ONLY meant to be invoked via `delegatecall` from the main game contract.
 *      - Storage layout inherits from `DegenerusGameStorage` to ensure slot alignment with the parent.
 *      - All external functions lack access modifiers intentionally; the parent contract controls access.
 *      - DO NOT deploy this contract standalone or call it directly—state would be written to the
 *        module's own storage rather than the game's.
 *
 *      JACKPOT FLOW OVERVIEW:
 *      1. Pool consolidation at level transition (prize pool splits and merges).
 *      2. `payDailyJackpot` — Handles purchase phase jackpots and rolling dailies at EOL.
 *      3. The daily jackpot battle — the day's FLIP budget played as one closed craps battle among
 *         wallets drawn from unminted future levels; level 1's purchase days also run
 *         `payDailyFlipJackpot`, a trait-matched FLIP draw over level 1.
 *
 *      FUND ACCOUNTING:
 *      - ETH flows through `futurePrizePool` (unified reserve), `currentPrizePool`,
 *        `nextPrizePool`, `claimablePool`.
 *      - The remainder goes to the entropy-selected solo bucket.
 *      - `claimableWinnings` tracks per-player ETH; `claimablePool` is the aggregate liability.
 *
 *      RANDOMNESS:
 *      - All entropy originates from VRF words passed by the parent contract.
 *      - EntropyLib.hash2 provides full-diffusion keccak derivation for sub-selections.
 *      - Winner selection intentionally allows duplicates (more tickets = more chances).
 */
contract DegenerusGameJackpotModule is DegenerusGamePayoutUtils, DegenerusGameJackpotDrawUtils {
    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    /// @notice Thrown when a function restricted to the game contract is called by another address.
    error OnlyGame();

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    /// @dev ETH jackpot win.
    ///      traitId is uint16: values 0-255 are real trait IDs; values ≥256 are
    ///      sentinels for non-trait sources (e.g. BAF_TRAIT_SENTINEL = 420).
    event JackpotEthWin(
        address indexed winner,
        uint24 indexed level,
        uint16 indexed traitId,
        uint256 amount,
        uint256 entryIndex
    );

    /// @dev Ticket jackpot win. See JackpotEthWin for traitId sentinel semantics.
    ///      entryCount is an entries count on all 3 paths and matches the
    ///      entries queued by the adjacent _queueEntries call. roundedUp is
    ///      true iff the BAF _jackpotTicketRoll (traitId = BAF_TRAIT_SENTINEL)
    ///      Bernoulli sub-roll incremented the whole-ticket count; it is false
    ///      on the two trait-matched paths, which have a zero fractional part
    ///      by construction.
    event JackpotTicketWin(
        address indexed winner,
        uint24 indexed entryLevel,
        uint16 indexed traitId,
        uint32 entryCount,
        uint24 sourceLevel,
        uint256 entryIndex,
        bool roundedUp
    );

    /// @dev FLIP coin win (near-future, trait-matched).
    event JackpotFlipWin(
        address indexed winner,
        uint24 indexed level,
        uint8 indexed traitId,
        uint256 amount,
        uint256 entryIndex
    );

    /// @dev Emitted once per daily drawing with the day's one winning board.
    event DailyWinningTraits(uint24 indexed day, uint32 mainTraitsPacked);

    /// @dev Yield surplus split three ways at the level transition. `perRecipientShare` is
    ///      credited to each of VAULT, sDGNRS and GNRUS — equal shares to pinned addresses,
    ///      so one field describes the whole distribution.
    event YieldSurplusDistributed(uint256 perRecipientShare);

    /// @dev `JackpotWhalePassWin.source` values.
    // Source 1 was the retired solo-only half-pass conversion.
    // Sources 4 (early bird) and 5 (quadrant conversion) are emitted by WhaleModule.

    /// @dev Golden ticket armed: the main board rolled 4 gold colors and the solo bucket
    ///      winner awaits the next main-board draw. `quadrant`/`symbol` are the solo
    ///      bucket's official (post-hero) values — the target the resolve board must
    ///      repeat (with 4 golds) for the grand.
    event GoldenTicketArmed(
        address indexed winner,
        uint24 indexed level,
        uint8 quadrant,
        uint8 symbol
    );

    /// @dev Golden-ticket payout. `route` names which of the two routes won:
    ///      GOLDEN_TICKET_ROUTE_BOARD (0) is the cross-day board resolution — the draw
    ///      after an armed 4-gold day pays the armed winner by this board's gold count,
    ///      and `grand` is true when this board also rolled 4 golds AND repeated the
    ///      armed quadrant's symbol (the hero is banned from the armed quadrant on this
    ///      draw, so that symbol is the raw base roll). GOLDEN_TICKET_ROUTE_FOIL (1) is
    ///      the foil-pack route — a pack whose drain rolled two all-gold tickets takes
    ///      the grand outright, so `grand` is always true there. `goldCount` is the
    ///      resolve board's gold count on the board route and the qualifying pack's gold
    ///      quadrant count on the foil route. ethAmount moved futurePrizePool -> winner
    ///      claimable; halfPassCount and flipCredit are face-value credits with no pool
    ///      debit; wwxrpAmount is the 0-gold consolation, before WWXRP's gameMintScale.
    event GoldenTicketWin(
        address indexed winner,
        uint24 indexed level,
        uint8 route,
        uint8 goldCount,
        bool grand,
        uint256 ethAmount,
        uint256 halfPassCount,
        uint256 flipCredit,
        uint256 wwxrpAmount
    );

    // -------------------------------------------------------------------------
    // External Contract References (compile-time constants)
    // -------------------------------------------------------------------------

    IStETH internal constant steth = IStETH(ContractAddresses.STETH_TOKEN);
    IDegenerusJackpots internal constant jackpots =
        IDegenerusJackpots(ContractAddresses.JACKPOTS);

    // -------------------------------------------------------------------------
    // Constants — Timing & Thresholds
    // -------------------------------------------------------------------------

    /// @dev Small-lootbox threshold for the jackpot lootbox portion split.

    /// @dev Golden-ticket consolation when the armed ticket's resolving main board shows 0 golds: 100 WWXRP.
    uint256 private constant GOLDEN_TICKET_WWXRP = 100 ether;

    /// @dev Golden-ticket routes, stamped on GoldenTicketWin. BOARD is the armed
    ///      cross-day board resolution; FOIL is a foil pack holding two or more
    ///      all-gold tickets, which takes the grand outright.
    uint8 private constant GOLDEN_TICKET_ROUTE_BOARD = 0;
    uint8 private constant GOLDEN_TICKET_ROUTE_FOIL = 1;

    /// @dev Sentinel traitId stamped on BAF jackpot payout events so indexers can
    ///      distinguish BAF wins from trait-bucketed daily/coin wins. Sits above
    ///      uint8.max (255) so it never collides with a real trait id.

    // -------------------------------------------------------------------------
    // Constants — Share Distribution (Basis Points)
    // -------------------------------------------------------------------------

    /// @dev Final-day trait bucket shares packed into 64 bits: [6000, 1333, 1333, 1334] = 10000 bps.
    ///      With rotation, the 60% share is assigned to the solo (1-winner) bucket.
    uint64 private constant FINAL_DAY_SHARES_PACKED =
        (uint64(6000)) |
            (uint64(1333) << 16) |
            (uint64(1333) << 32) |
            (uint64(1334) << 48);

    /// @dev Daily jackpot trait bucket shares: 2000 bps each × 4 = 8000 bps.
    ///      Remaining 20% is assigned to the entropy-selected solo bucket.
    uint64 private constant DAILY_JACKPOT_SHARES_PACKED =
        uint64(2000) * 0x0001000100010001;

    // -------------------------------------------------------------------------
    // Constants — Entropy Salts
    // -------------------------------------------------------------------------

    bytes32 private constant HERO_SYMBOL_TAG = keccak256("degenerus.jackpot.hero-symbol");

    /// @dev Domain separator for per-pull level sampling in level 1's trait-matched FLIP draw.

    /// @dev Domain separator for rolling current-pool daily jackpot percentage.
    bytes32 private constant DAILY_CURRENT_BPS_TAG =
        keccak256("daily-current-bps");

    /// @dev Sentinel for _rollHeroSymbol's banQuadrant param: no quadrant banned.
    uint8 private constant _NO_QUADRANT_BAN = 0xFF;

    /// @dev Sentinel quadrant for a whale-pass award that skips none (the quadrant
    ///      conversion, which names its one trait). Any value >= 4 matches no quadrant.
    uint8 private constant _NO_QUADRANT_EXCLUDE = 0xFF;


    /// @dev Base current-pool jackpot percentage bounds (6%-14%); doubled on the middle day.
    uint16 private constant DAILY_CURRENT_BPS_MIN = 600;
    uint16 private constant DAILY_CURRENT_BPS_MAX = 1400;

    /// @dev Portion of the purchase-phase drip routed to the ticket leg (3/4):
    ///      backing ETH moves to nextPrizePool, tickets go to trait winners.
    uint16 private constant PURCHASE_REWARD_JACKPOT_TICKET_BPS = 7500;

    /// @dev Portion of the purchase-phase drip skimmed to the yield accumulator (2%),
    ///      splitting the day's slice 75 ticket / 23 ETH / 2 insurance. Sized off the
    ///      whole drip alongside the ticket leg and taken before bucket sizing, so it
    ///      never reaches a winner. The move is obligation-neutral: futurePrizePool and
    ///      the accumulator both sit in the yield-surplus obligation set, so the skim
    ///      shifts the wei between two liabilities without freeing any surplus.
    uint16 private constant PURCHASE_INSURANCE_BPS = 200;

    /// @dev Max winners per single trait bucket (must fit in uint8 for _randTraitTicket).
    ///      Set to 248 (31 packed words); covers the largest ETH and ticket buckets.
    uint8 private constant MAX_BUCKET_WINNERS = 248;

    // -------------------------------------------------------------------------
    // Constants — Jackpot Bucket Scaling (Gas Guardrails)
    // -------------------------------------------------------------------------

    /// @dev Maximum ticket winners for the purchase-phase drip ticket distribution.
    /// Higher than ETH winners because ticket distribution is cheaper per winner.
    uint16 private constant PURCHASE_PHASE_TICKET_MAX_WINNERS = 120;

    /// @dev Domain separator for the daily future jackpot battle's entropy derivation.

    /// @dev Most awarded entries one draw call collects: the chunk the battle accepts.

    /// @dev Most winners of level 1's trait-matched FLIP draw, each paid one equal share.

    /// @dev Daily: 32 per non-solo quadrant. Empty buckets redistribute the cap in whole
    ///      groups of eight.
    uint16 private constant TICKET_JACKPOT_MAX_WINNERS = 96;

    /// @dev Early-bird cap, split in groups of eight across the three non-solo quadrants
    ///      (40, 40 and 48 when all three are active).
    uint16 private constant EARLY_BIRD_MAX_WINNERS = 128;

    /// @dev Large early-bird prizes retain 45 whole tickets per slot. Only a surplus
    ///      covering a full pass converts; its ETH still goes to nextPrizePool.
    uint256 private constant EARLY_BIRD_TICKETS_PER_WINNER = 45;

    /// @dev Entries per whole ticket. Jackpot budgets are denominated in entries
    ///      (quarter-tickets), but awards are paid in whole tickets only.
    uint256 private constant ENTRIES_PER_TICKET = 4;

    /// @dev Daily jackpot max scale (6.36x) producing bucket counts 152/104/48/1 at 200+ ETH.
    ///      The four quadrants can span calls; their original payout order is fixed.
    uint32 private constant DAILY_JACKPOT_SCALE_MAX_BPS = 63_600;

    error JackpotWorkMismatch();

    uint256 private constant JACKPOT_SETUP_GAS = GasBounds.JACKPOT_SETUP_GAS;
    uint256 private constant JACKPOT_PLAN_GAS = GasBounds.JACKPOT_PLAN_GAS;
    uint256 private constant JACKPOT_FINAL_GAS = GasBounds.JACKPOT_FINAL_GAS;
    uint256 private constant JACKPOT_TAIL_GAS = GasBounds.JACKPOT_TAIL_GAS;
    uint256 private constant ETH_WINNER_GAS_MAX = GasBounds.JACKPOT_ETH_WINNER_GAS_MAX;
    uint256 private constant TICKET_DRAW_GAS_MAX = GasBounds.JACKPOT_TICKET_DRAW_GAS_MAX;
    uint256 private constant TICKET_AWARD_GAS_MAX = GasBounds.JACKPOT_TICKET_AWARD_GAS_MAX;

    // =========================================================================
    // External Entry Points (delegatecall targets)
    // =========================================================================

    /// @notice Terminal (game-over) jackpot: Final-day bucket distribution.
    /// @dev Called via IDegenerusGame(address(this)) from GameOverModule.
    ///      Uses FINAL_DAY_SHARES_PACKED (60/13/13/13) with trait-based bucket distribution.
    ///      Updates claimablePool internally — callers must NOT double-count.
    /// @param poolWei Total ETH to distribute.
    /// @param targetLvl Level to sample winners from (typically lvl+1).
    /// @param rngWord VRF entropy seed.
    /// @return paidWei Total ETH distributed (callers deduct from source pool).
    function runTerminalJackpot(uint256 poolWei, uint24 targetLvl, uint256 rngWord)
        external returns (uint256 paidWei)
    {
        (, paidWei) = _runTerminalJackpot(poolWei, targetLvl, rngWord, MineFlipGas.available());
    }

    function runTerminalJackpotWork(uint256 poolWei, uint24 targetLvl, uint256 rngWord, uint256 allowance)
        external returns (MineFlipGas.Result memory result, uint256 paidDelta)
    {
        return _runTerminalJackpot(poolWei, targetLvl, rngWord, allowance);
    }

    function _runTerminalJackpot(uint256 poolWei, uint24 targetLvl, uint256 rngWord, uint256 allowance)
        private returns (MineFlipGas.Result memory result, uint256 paidDelta)
    {
        if (msg.sender != ContractAddresses.GAME) revert OnlyGame();
        MineFlipGas.Meter memory meter = MineFlipGas.start(allowance);
        JackpotWork storage work = jackpotWork;
        if (work.kind == 0 || (work.kind == 3 && work.quadrant == 255)) {
            if (!MineFlipGas.canRun(meter, JACKPOT_SETUP_GAS, JACKPOT_TAIL_GAS)) return (result, 0);
            if (work.kind == 0) {
                work.kind = 3;
                work.lvl = targetLvl;
                work.budget = uint128(poolWei);
            } else if (work.lvl != targetLvl) revert JackpotWorkMismatch();
            work.quadrant = 0;
            work.traits = _rollBoard(rngWord, _NO_QUADRANT_BAN);
            work.finalDay = true;
            result.progressed = true;
        } else if (work.kind != 3 || work.lvl != targetLvl) revert JackpotWorkMismatch();
        uint256 beforePaid = work.paid;
        _resumeEth(work, rngWord, meter, result);
        paidDelta = uint256(work.paid) - beforePaid;
        if (result.done) delete jackpotWork;
        MineFlipGas.finish(meter);
    }

    /// @notice Pays purchase phase jackpots OR rolling daily jackpots at level end.
    /// @dev Called by the parent game contract via delegatecall. Two distinct paths:
    ///
    ///      JACKPOT PHASE PATH (isJackpotPhase=true):
    ///      - Three-day schedule: 6%-14% of remaining currentPrizePool on day 1, 12%-28% on day 2.
    ///      - Final physical day (day 3, or day 1 for turbo): distributes the remaining currentPrizePool.
    ///      - Day 1 also runs the early-bird ticket jackpot (from futurePrizePool).
    ///      - The day's jackpot battle is latched at the daily request and plays in its own
    ///        stage (payPurchaseJackpotBattle), not here.
    ///      - The coin+tickets stage increments jackpotCounter on completion.
    ///
    ///      PURCHASE PHASE PATH (isJackpotPhase=false):
    ///      - Triggered during purchase phase when burns occur.
    ///      - Rolls winning traits (random + hero override) and runs trait-based jackpot.
    ///      - Fixed winner counts [24, 16, 8, 1] = 49 ETH winners, up to 120 ticket winners.
    ///      - Adds a 4% futurePrizePool ETH slice every purchase day, split 75/23/2:
    ///        75% to the ticket leg (backing ETH → nextPrizePool, tickets to trait
    ///        winners), 2% skimmed to the yield accumulator, 23% distributed as ETH.
    ///
    /// @param isJackpotPhase True for jackpot phase dailies, false for purchase phase jackpot.
    /// @param lvl Current game level.
    /// @param randWord VRF entropy for winner selection and trait derivation.
    function payDailyJackpot(bool isJackpotPhase, uint24 lvl, uint256 randWord) external {
        _runDailyJackpot(isJackpotPhase, lvl, randWord, MineFlipGas.available());
    }

    function runDailyJackpot(bool isJackpotPhase, uint24 lvl, uint256 randWord, uint256 allowance)
        external returns (MineFlipGas.Result memory result)
    {
        return _runDailyJackpot(isJackpotPhase, lvl, randWord, allowance);
    }

    function _runDailyJackpot(bool isJackpotPhase, uint24 lvl, uint256 randWord, uint256 allowance)
        private returns (MineFlipGas.Result memory result)
    {
        MineFlipGas.Meter memory meter = MineFlipGas.start(allowance);
        JackpotWork storage work = jackpotWork;
        uint8 kind = isJackpotPhase ? 2 : 1;
        if (work.kind == 0) {
            if (!MineFlipGas.canRun(meter, JACKPOT_SETUP_GAS, JACKPOT_TAIL_GAS)) return result;
            _startDailyEth(work, kind, lvl, randWord);
            result.progressed = true;
        } else if (work.kind != kind || work.lvl != lvl) revert JackpotWorkMismatch();
        _resumeEth(work, randWord, meter, result);
        if (result.done) {
            if (isJackpotPhase) {
                if (work.finalDay) {
                    uint256 unpaid = uint256(work.budget) - work.paid;
                    _setCurrentPrizePool(_getCurrentPrizePool() - unpaid);
                    if (unpaid != 0) _addFuturePrizePool(unpaid);
                }
                _emitDailyWinningTraits(dailyIdx + 1, work.traits, lvl, randWord);
                dailyJackpotCoinTicketsPending = true;
            }
            delete jackpotWork;
        }
        MineFlipGas.finish(meter);
    }

    /// @dev Price once. Every later quadrant debits its source and credits its
    ///      liability in the same call, including across transaction boundaries.
    function _startDailyEth(JackpotWork storage work, uint8 kind, uint24 lvl, uint256 word) private {
        work.kind = kind;
        work.lvl = lvl;
        uint32 traits = _rollMainTraits(word);
        work.traits = traits;
        uint256 g = goldenTicket;
        if ((g >> 189) & 1 != 0 && dailyIdx > uint24((g >> 165) & 0xFFFFFF)) {
            _resolveGoldenTicket(g, traits, lvl);
        }
        uint256 ticketBudget;
        uint256 budget;
        uint256 unit;
        if (kind == 2) {
            uint8 counter = jackpotCounter;
            bool finalDay = _isFinalJackpotDay(counter, jackpotFlags);
            work.finalDay = finalDay;
            uint256 current = _getCurrentPrizePool();
            uint256 bps = finalDay ? 10_000 : _dailyCurrentPoolBps(counter, word);
            if (!finalDay && counter != 0) bps *= 2;
            budget = current * bps / 10_000;
            ticketBudget = budget / 5;
            budget -= ticketBudget;
            uint256 entries;
            (entries, unit) = _budgetToEntries(ticketBudget, lvl + 1);
            _setCurrentPrizePool(current - ticketBudget);
            _addNextPrizePool(ticketBudget);
            dailyTicketBudgetsPacked = entries << 8;
            if (counter == 0) dailyTicketBudgetsPacked |= _priceEarlyBirdTickets(lvl + 1) << 144;
        } else {
            _emitDailyWinningTraits(dailyIdx + 1, traits, lvl, word);
            uint256 slice = _getFuturePrizePool() / 25;
            ticketBudget = slice * PURCHASE_REWARD_JACKPOT_TICKET_BPS / 10_000;
            uint256 insurance = slice * PURCHASE_INSURANCE_BPS / 10_000;
            budget = slice - ticketBudget - insurance;
            unit = PriceLookupLib.priceForLevel(lvl + 1) >> 2;
            if (slice != 0) {
                (uint128 next, uint128 future) = _getPrizePools();
                _setPrizePools(next + uint128(ticketBudget), future - uint128(ticketBudget + insurance));
                if (insurance != 0) yieldAccumulator += insurance;
            }
            if (ticketBudget != 0) {
                (uint256 entries,) = _budgetToEntries(ticketBudget / 2, lvl);
                if (entries >= ENTRIES_PER_TICKET) dailyTicketBudgetsPacked = entries << 208;
            }
        }
        work.budget = uint128(budget);
        work.unit = uint128(unit);
    }

    /// @dev The next quadrant is always the original largest-first quadrant.
    ///      Winner selection, pass conversion and gold arming remain indivisible.
    function _resumeEth(JackpotWork storage work, uint256 word, MineFlipGas.Meter memory meter,
        MineFlipGas.Result memory result) private
    {
        if (!MineFlipGas.canRun(meter, JACKPOT_PLAN_GAS, JACKPOT_TAIL_GAS)) return;
        uint8[4] memory traits = JackpotBucketLib.unpackWinningTraits(work.traits);
        uint256 entropy = _soloAdjustedEntropy(traits, EntropyLib.hash2(word, work.lvl));
        uint16[4] memory counts;
        if (work.kind == 1) {
            uint16[4] memory base = [uint16(24), 16, 8, 1];
            for (uint8 q; q < 4; ++q) counts[q] = base[(q + uint8(entropy & 3)) & 3];
        } else {
            uint256 sizing = work.kind == 3
                ? (work.budget == 0 ? 0 : JackpotBucketLib.JACKPOT_SCALE_SECOND_WEI)
                : work.budget;
            counts = JackpotBucketLib.bucketCountsForPool(sizing, entropy, DAILY_JACKPOT_SCALE_MAX_BPS);
        }
        uint16[4] memory bps = JackpotBucketLib.shareBpsByBucket(
            work.finalDay ? FINAL_DAY_SHARES_PACKED : DAILY_JACKPOT_SHARES_PACKED, uint8(entropy & 3)
        );
        uint8 remainder = JackpotBucketLib.soloBucketIndex(entropy);
        uint256[4] memory shares = JackpotBucketLib.bucketShares(work.budget, bps, counts, remainder, work.unit);
        uint8[4] memory order = JackpotBucketLib.bucketOrderLargestFirst(counts);
        bool jackpotPhase = work.kind == 2;
        bool armGold = jackpotPhase && _allGold(traits);
        uint8 cursor = work.quadrant;
        while (cursor < 4) {
            uint8 q = order[cursor];
            uint256 bound = shares[q] == 0 || counts[q] == 0
                ? 10_000 : 160_000 + uint256(counts[q]) * ETH_WINNER_GAS_MAX;
            if (!MineFlipGas.canRun(meter, bound, JACKPOT_TAIL_GAS)) break;
            if (shares[q] != 0 && counts[q] != 0) {
                (uint256 paid, uint256 liability) = _processBucket(
                    work.lvl, traits[q], q, counts[q], shares[q], EntropyLib.hash2(entropy, q),
                    jackpotPhase, armGold && q == remainder
                );
                work.paid += uint128(paid);
                if (liability != 0) claimablePool += uint128(liability);
                if (jackpotPhase) _setCurrentPrizePool(_getCurrentPrizePool() - paid);
                else if (work.kind == 1 && paid != 0) {
                    (uint128 next, uint128 future) = _getPrizePools();
                    _setPrizePools(next, future - uint128(paid));
                }
            }
            ++cursor;
            ++result.rewardBasis;
            result.progressed = true;
        }
        if (cursor != work.quadrant) work.quadrant = cursor;
        result.done = cursor == 4;
    }

    /// @notice The ticket leg of the purchase-phase daily, from its own advance stage.
    /// @dev Called by advanceGame after the pricing and battle advances, with
    ///      the same day's recorded word. The main board is the one the pricing stage rolled
    ///      and recorded in dailyFoilDraw for the day it priced (dailyIdx has not moved: the
    ///      pricing stage does not seal while this leg is pending), and the winner entropy is
    ///      the value the single-tx form used, so the draw is unchanged by the split. Tickets
    ///      queue at the purchase level, which the held lock keeps un-promoted between the two
    ///      stages. Clears the field it consumes; the caller seals the day.
    /// @param randWord VRF entropy (the day's recorded word).
    function payPurchaseDailyTickets(uint256 randWord) external {
        _runTicketWork(4, randWord, MineFlipGas.available());
    }

    function runPurchaseDailyTickets(uint256 word, uint256 allowance)
        external returns (MineFlipGas.Result memory)
    {
        return _runTicketWork(4, word, allowance);
    }

    /// @notice Phase 2 of the daily jackpot: the day's own ticket leg.
    /// @dev Called by advanceGame when dailyJackpotCoinTicketsPending is true. The daily is a
    ///      chain of advance txs so each stays under the per-tx gas cap: Phase 1 pays the ETH,
    ///      on day 1 the early-bird ticket leg (up to 128 winners) runs from its own stage
    ///      (payEarlyBirdTickets), the jackpot battle runs from its own stage (payPurchaseJackpotBattle), and
    ///      this stage, the last, pays the main-board tickets. It advances the counter and the
    ///      caller seals the day (or ends the level) in the same tx.
    ///
    ///      The main board is re-rolled from the word exactly as Phase 1 rolled it (see
    ///      `_rollMainTraits`).
    /// @param randWord VRF entropy (the day's recorded word, the one Phase 1 used).
    function payDailyJackpotCoinAndTickets(uint256 randWord) external {
        _runTicketWork(6, randWord, MineFlipGas.available());
    }

    function runDailyJackpotTickets(uint256 word, uint256 allowance)
        external returns (MineFlipGas.Result memory)
    {
        return _runTicketWork(6, word, allowance);
    }

    /// @dev Prices the early-bird ticket jackpot from the unified future pool: the full 3%
    ///      budget always moves future -> next (a single net move on the packed slot; future
    ///      funds the budget, next backs the queued tickets), converted on the same
    ///      4-entries-per-ticket basis every other jackpot path uses (`_budgetToEntries`).
    ///      If the ordinary prize exceeds 45 whole tickets per slot and the pooled
    ///      surplus buys at least one full pass, cap tickets and latch the pass units.
    ///      Surplus uses the exact wei budget, including ordinary distribution dust.
    /// @param lvl The level the early-bird tickets are priced and queued at (outer level + 1).
    /// @return entries The early-bird entry count payEarlyBirdTickets distributes.
    function _priceEarlyBirdTickets(uint24 lvl) private returns (uint256 entries) {
        (uint128 nextBal, uint128 futureBal) = _getPrizePools();
        uint256 totalBudget = (uint256(futureBal) * 300) / 10_000; // 3%
        earlyBirdWhalePasses = 0;
        if (totalBudget == 0) return 0;
        uint256 unit;
        (entries, unit) = _budgetToEntries(totalBudget, lvl);
        // A draw below the 128-slot cap pays at most one ticket per slot. Thus
        // more than 45 each implies the full cap, with no small-draw division.
        if (entries / (EARLY_BIRD_MAX_WINNERS * ENTRIES_PER_TICKET) > EARLY_BIRD_TICKETS_PER_WINNER) {
            uint256 ticketEntries = EARLY_BIRD_MAX_WINNERS * EARLY_BIRD_TICKETS_PER_WINNER * ENTRIES_PER_TICKET;
            uint256 surplus = totalBudget - ticketEntries * unit;
            uint256 fullPasses = surplus / (2 * HALF_WHALE_PASS_PRICE);
            if (fullPasses != 0) {
                entries = ticketEntries;
                earlyBirdWhalePasses = fullPasses * 2;
            }
        }
        _setPrizePools(
            nextBal + uint128(totalBudget),
            futureBal - uint128(totalBudget)
        );
    }

    /// @notice The early-bird ticket leg of the day-1 daily jackpot, from its own advance stage.
    /// @dev Called by advanceGame on the advance after payDailyJackpot priced it (the top field
    ///      of dailyTicketBudgetsPacked), with the same day's word from rngGate, ahead of the
    ///      coin+tickets stage. Phase 1 already moved the full 3% budget future -> next; this
    ///      distributes the latched entries through the shared ticket distributor with
    ///      `cap = min(wholeTickets, 128)`, floored to eight unless below eight:
    ///      every drawn winner takes the same `tickets / cap` whole tickets, the `tickets % cap`
    ///      leftover is not queued, and leftover groups rotate between active buckets.
    ///      Winners come from `lvlTraitEntry[level + 1]` on the day's main board, re-rolled
    ///      from the word exactly as Phase 1 rolled it, across its three non-solo quadrants:
    ///      the solo quadrant is the one the ETH leg picked (from its own entropy,
    ///      hash2(word, level)), and it carries only the solo ETH prize. Tickets queue at
    ///      level + 1. A capped draw also awards all surplus full passes to one fresh winner
    ///      outside the solo quadrant, preferring eligible gold. No pool moves in this stage.
    ///      Clears its own field and leaves the rest of the packed budgets for the battle and
    ///      coin+tickets stages. The lock held since the request keeps every input frozen.
    /// @param randWord VRF entropy (the day's recorded word).
    function payEarlyBirdTickets(uint256 randWord) external {
        _runTicketWork(5, randWord, MineFlipGas.available());
    }

    function runEarlyBirdTickets(uint256 word, uint256 allowance)
        external returns (MineFlipGas.Result memory)
    {
        return _runTicketWork(5, word, allowance);
    }

    struct TicketWorkPlan {
        uint24 sourceLvl;
        uint24 queueLvl;
        uint8 salt;
        uint256 entropy;
        uint256 entriesEach;
        uint8[4] traits;
        uint16[4] counts;
        uint256[4] lens;
        address[4] deities;
    }

    function _runTicketWork(uint8 kind, uint256 word, uint256 allowance)
        private returns (MineFlipGas.Result memory result)
    {
        MineFlipGas.Meter memory meter = MineFlipGas.start(allowance);
        JackpotWork storage work = jackpotWork;
        if (work.kind == 0) {
            if (kind == 6 && !dailyJackpotCoinTicketsPending) { result.done = true; return result; }
            if (!MineFlipGas.canRun(meter, JACKPOT_SETUP_GAS, JACKPOT_TAIL_GAS)) return result;
            work.kind = kind;
            work.lvl = kind == 6 ? level : level + 1;
            uint256 packed = dailyTicketBudgetsPacked;
            work.budget = kind == 4 ? uint128(packed >> 208)
                : uint128(uint64(packed >> (kind == 5 ? 144 : 8)));
            if (kind == 4) (, work.traits,) = _foilDrawFor(uint256(dailyIdx) + 1);
            else work.traits = _rollMainTraits(word);
            result.progressed = true;
        } else if (work.kind != kind) revert JackpotWorkMismatch();
        if (MineFlipGas.canRun(meter, JACKPOT_PLAN_GAS, JACKPOT_TAIL_GAS)) {
            TicketWorkPlan memory plan = _ticketWorkPlan(work, word);
            _resumeTicketWork(work, plan, meter, result);
        }
        if (work.quadrant == 4 && MineFlipGas.canRun(meter, JACKPOT_FINAL_GAS, JACKPOT_TAIL_GAS)) {
            if (kind == 4) dailyTicketBudgetsPacked &= (uint256(1) << 208) - 1;
            else if (kind == 5) {
                dailyTicketBudgetsPacked &= (uint256(1) << 144) - 1;
                uint256 halfPasses = earlyBirdWhalePasses;
                if (halfPasses != 0) {
                    earlyBirdWhalePasses = 0;
                    _awardWhalePass(work.lvl, work.traits, halfPasses, word, true,
                        _pickSoloQuadrant(JackpotBucketLib.unpackWinningTraits(work.traits), EntropyLib.hash2(word, level)));
                }
            } else {
                unchecked { ++jackpotCounter; }
                dailyJackpotCoinTicketsPending = false;
                dailyTicketBudgetsPacked = 0;
            }
            delete jackpotWork;
            result.progressed = true;
            result.done = true;
        }
        MineFlipGas.finish(meter);
    }

    function _ticketWorkPlan(JackpotWork storage work, uint256 word)
        private view returns (TicketWorkPlan memory plan)
    {
        plan.sourceLvl = work.lvl;
        plan.queueLvl = work.kind == 6 ? work.lvl + 1 : work.lvl;
        plan.salt = work.kind == 4 ? 242 : work.kind == 5 ? 239 : 241;
        plan.entropy = EntropyLib.hash2(word, work.lvl);
        plan.traits = JackpotBucketLib.unpackWinningTraits(work.traits);
        uint256 tickets = work.budget / ENTRIES_PER_TICKET;
        if (tickets == 0) return plan;
        uint16 cap = work.kind == 4 ? PURCHASE_PHASE_TICKET_MAX_WINNERS
            : work.kind == 5 ? EARLY_BIRD_MAX_WINNERS : TICKET_JACKPOT_MAX_WINNERS;
        if (tickets < cap) cap = uint16(tickets);
        if (cap >= 8) cap &= ~uint16(7);
        uint256 soloEntropy = work.kind == 5 ? EntropyLib.hash2(word, level) : plan.entropy;
        (plan.counts,, plan.lens, plan.deities) = _computeBucketCounts(
            work.lvl, plan.traits, cap, plan.entropy, _pickSoloQuadrant(plan.traits, soloEntropy)
        );
        plan.entriesEach = (tickets / cap) * ENTRIES_PER_TICKET;
    }

    /// @dev Regenerating the frozen source draw has no side effects. Awarded
    ///      tickets only enter a queue; they never mutate these source buckets.
    function _resumeTicketWork(JackpotWork storage work, TicketWorkPlan memory plan,
        MineFlipGas.Meter memory meter, MineFlipGas.Result memory result) private
    {
        uint8 q = work.quadrant;
        while (q < 4) {
            uint16 count = plan.counts[q];
            if (count == 0) {
                if (!MineFlipGas.canRun(meter, 10_000, JACKPOT_TAIL_GAS)) break;
                ++q;
                result.progressed = true;
                continue;
            }
            uint256 drawBound = 50_000 + uint256(count) * TICKET_DRAW_GAS_MAX;
            if (!MineFlipGas.canRun(meter, drawBound + TICKET_AWARD_GAS_MAX, JACKPOT_TAIL_GAS)) break;
            (address[] memory winners, uint256[] memory indexes) = _randTraitTicket(
                plan.sourceLvl, EntropyLib.hash2(plan.entropy, q), plan.traits[q], uint8(count),
                uint8(plan.salt + q), plan.lens[q], plan.deities[q]
            );
            uint256 i = work.winner;
            while (i < winners.length) {
                if (!MineFlipGas.canRun(meter, TICKET_AWARD_GAS_MAX, JACKPOT_TAIL_GAS)) break;
                address winner = winners[i];
                if (winner != address(0)) {
                    _queueEntries(winner, plan.queueLvl, uint32(plan.entriesEach), true);
                    emit JackpotTicketWin(winner, plan.queueLvl, plan.traits[q], uint32(plan.entriesEach),
                        plan.sourceLvl, indexes[i], false);
                }
                ++i;
                ++result.rewardBasis;
                result.progressed = true;
            }
            if (i != winners.length) { work.winner = uint16(i); break; }
            work.winner = 0;
            ++q;
        }
        if (q != work.quadrant) work.quadrant = q;
    }

    /// @dev Bounded sibling-module award. Early bird passes latched claim units and the
    ///      board's solo quadrant, which its winner is drawn outside of; quadrant conversion
    ///      passes its original ETH share (and no quadrant to skip) and gets the spend back.
    function _awardWhalePass(
        uint24 lvl, uint32 traits, uint256 amount, uint256 randWord, bool earlyBird, uint8 soloQuadrant
    ) private returns (uint256 spent) {
        (bool ok, bytes memory data) = ContractAddresses.GAME_WHALE_MODULE.delegatecall(
            abi.encodeWithSelector(
                IDegenerusGameWhaleModule.awardWhalePass.selector,
                lvl, traits, amount, randWord, earlyBird, soloQuadrant
            )
        );
        if (!ok) {
            assembly ("memory-safe") { revert(add(data, 32), mload(data)) }
        }
        spent = abi.decode(data, (uint256));
    }

    /// @notice Distribute yield surplus (stETH appreciation) to stakeholders.
    /// @dev Entry point for AdvanceModule delegatecall. The selector-dispatched
    ///      signature carries the day's VRF word for delegatecall-shape stability;
    ///      the surplus split is deterministic and consumes no entropy.
    ///      23% each to sDGNRS, vault, and charity (GNRUS) claimable, 23% yield accumulator (~8% buffer).
    function distributeYieldSurplus(uint256) external {
        uint256 stBal = steth.balanceOf(address(this));
        uint256 totalBal = address(this).balance + stBal;
        (uint128 nextPool, uint128 futurePool) = _getPrizePools();
        uint128 claimablePoolCached = claimablePool;
        uint256 yieldAccCached = yieldAccumulator;
        uint256 obligations = _getCurrentPrizePool() +
            uint256(nextPool) +
            claimablePoolCached +
            uint256(futurePool) +
            yieldAccCached;

        // Pending buffer is a live liability backed by ETH already in balance:
        // freeze-window revenue lands in balance but routes to prizePoolPendingPacked
        // (outside the live pools above) until _unfreezePool folds it back. Without
        // this, that ETH is misread as yield surplus and over-distributed.
        // Reads 0 when not frozen.
        (uint128 pNext, uint128 pFuture) = _getPendingPools();
        obligations += uint256(pNext) + uint256(pFuture);

        if (totalBal <= obligations) return;

        uint256 yieldPool = totalBal - obligations;
        uint256 quarterShare = (yieldPool * 2300) / 10_000;

        if (quarterShare != 0) {
            _creditClaimable(ContractAddresses.VAULT, quarterShare);
            _creditClaimable(ContractAddresses.SDGNRS, quarterShare);
            _creditClaimable(ContractAddresses.GNRUS, quarterShare);
            // _creditClaimable writes only balancesPacked, so the cached
            // claimablePool / yieldAccumulator values are still exact here.
            claimablePool = claimablePoolCached + uint128(quarterShare * 3);
            yieldAccumulator = yieldAccCached + quarterShare;
            // The three credits above are the only ones in the protocol with no domain
            // event of their own to pair with in the receipt. One marker names them;
            // the recipients are pinned constants and all three take the same share.
            emit YieldSurplusDistributed(quarterShare);
        }
    }

    // =========================================================================
    // Internal Helpers — Ticket Budgeting
    // =========================================================================

    /// @dev Converts an ETH budget to ticket units. Tickets cost ticketPrice/4.
    function _budgetToEntries(
        uint256 budget,
        uint24 lvl
    ) private pure returns (uint256 entries, uint256 unit) {
        uint256 ticketPrice = PriceLookupLib.priceForLevel(lvl);
        // `unit` (ticketPrice >> 2, a quarter-ticket) is the same value the jackpot-phase
        // _processDailyEth derives from priceForLevel(lvl+1); returned so the caller can thread
        // it in and skip the recompute.
        unit = ticketPrice >> 2;
        entries = (budget << 2) / ticketPrice;
    }

    // =========================================================================
    // Internal Helpers — Packed Prize Pool Credits
    // =========================================================================

    /// @dev Credits the next pool with a single packed-slot read + write.
    function _addNextPrizePool(uint256 amount) private {
        (uint128 nextBal, uint128 futureBal) = _getPrizePools();
        _setPrizePools(nextBal + uint128(amount), futureBal);
    }

    /// @dev Credits the future pool with a single packed-slot read + write.
    function _addFuturePrizePool(uint256 amount) private {
        (uint128 nextBal, uint128 futureBal) = _getPrizePools();
        _setPrizePools(nextBal, futureBal + uint128(amount));
    }

    // =========================================================================
    // Internal Helpers — Ticket Rewards
    // =========================================================================

    /// @dev Computes bucket winner counts for active trait buckets (including virtual deity entries).
    ///      Also returns each trait's bucket length and deity address so the
    ///      distribution loop reuses them instead of re-reading storage.
    /// @param lvl Level whose trait entry queues are counted.
    /// @param traitIds Winning trait IDs for the 4 buckets.
    /// @param maxWinners Total slots, a multiple of eight or fewer than eight. Split full
    ///        groups across active buckets; rotate leftover groups from an entropy-picked start.
    /// @param entropy RNG state for rotation and scaling.
    /// @param excludeIdx Bucket dropped from the draw (the board's solo quadrant).
    ///        Dropping is skipped when it would leave no active bucket, so the
    ///        award is never stranded against backing already moved to nextPrizePool.
    function _computeBucketCounts(
        uint24 lvl,
        uint8[4] memory traitIds,
        uint16 maxWinners,
        uint256 entropy,
        uint8 excludeIdx
    )
        private
        view
        returns (
            uint16[4] memory counts,
            uint8 activeCount,
            uint256[4] memory lens,
            address[4] memory deities
        )
    {
        uint8 activeMask;
        for (uint8 i; i < 4; ) {
            uint8 trait = traitIds[i];
            uint256 len = _bucketLength(lvl, trait);
            lens[i] = len;
            address deity = _traitDeity(trait);
            deities[i] = deity;
            if (len != 0 || deity != address(0)) {
                activeMask |= uint8(1 << i);
                unchecked {
                    ++activeCount;
                }
            }
            unchecked {
                ++i;
            }
        }

        // Drop the excluded bucket unless it is the only active one. Everything
        // below keys off activeMask, so the base split and the remainder rotation
        // both route its winners to the surviving buckets; maxWinners is unchanged,
        // so the same total entries go out across fewer quadrants.
        if ((activeMask & uint8(1 << excludeIdx)) != 0) {
            uint8 kept = activeMask & ~uint8(1 << excludeIdx);
            if (kept != 0) {
                activeMask = kept;
                unchecked {
                    --activeCount;
                }
            }
        }

        if (activeCount == 0) return (counts, 0, lens, deities);

        uint16 group = maxWinners >= 8 ? 8 : 1;
        uint16 baseCount = (maxWinners / group / activeCount) * group;
        uint16 remainder = maxWinners - baseCount * activeCount;

        for (uint8 i; i < 4; ) {
            if ((activeMask & uint8(1 << i)) != 0) {
                counts[i] = baseCount;
            }
            unchecked {
                ++i;
            }
        }

        if (remainder != 0) {
            uint8 idx = uint8(entropy & 3);
            while (remainder != 0) {
                if ((activeMask & uint8(1 << idx)) != 0) {
                    counts[idx] += group;
                    unchecked {
                        remainder -= group;
                    }
                }
                idx = uint8((idx + 1) & 3);
            }
        }
    }

    // =========================================================================
    // Internal Helpers — Jackpot Execution
    // =========================================================================

    /// @dev Picks the solo bucket quadrant for ETH-distribution rotation.
    ///      A surviving gold six always assigns the solo pool to Dice. Otherwise,
    ///      when any winning trait has color==7 (gold tier), returns a uniformly-random
    ///      gold quadrant via bits 4+ of `entropy` (disjoint from the bucket-rotation
    ///      low 2 bits at `entropy & 3`). Otherwise returns the existing rotation index
    ///      `uint8((3 - (entropy & 3)) & 3)` matching `JackpotBucketLib.soloBucketIndex`.
    /// @param traits The 4 winning trait IDs (each [QQ][CCC][SSS] packed: quadrant 2 bits,
    ///        color 3 bits, symbol 3 bits).
    /// @param entropy VRF-derived entropy. Bits 0-1 drive bucket rotation; bits 4+ drive
    ///        gold tie-break (bits 2-3 unused by either path).
    /// @return Quadrant index 0-3 to receive the solo bucket assignment.
    function _pickSoloQuadrant(uint8[4] memory traits, uint256 entropy) internal pure returns (uint8) {
        if (traits[3] == GoldSixLib.TRAIT) return 3;
        // Pack gold quadrant indices into a uint256 (4 slots × 8 bits each).
        // Each slot holds a quadrant index 0-3. Pure-stack representation —
        // no memory allocation per call.
        uint256 goldQuads;
        uint8 goldCount;
        for (uint8 i; i < 4; ) {
            if (((traits[i] >> 3) & 7) == 7) {
                goldQuads |= uint256(i) << (goldCount * 8);
                unchecked { ++goldCount; }
            }
            unchecked { ++i; }
        }
        if (goldCount == 0) {
            return uint8((3 - (entropy & 3)) & 3);
        }
        uint8 idx = uint8((entropy >> 4) % goldCount);
        return uint8((goldQuads >> (idx * 8)) & 0xFF);
    }

    /// @dev Splices the solo-quadrant selection into the low 2 bits of `entropy`
    ///      so `JackpotBucketLib.soloBucketIndex` lands on the picked quadrant.
    function _soloAdjustedEntropy(
        uint8[4] memory traitIds,
        uint256 entropy
    ) private pure returns (uint256) {
        uint8 soloQuadrant = _pickSoloQuadrant(traitIds, entropy);
        return (entropy & ~uint256(3)) | uint256((3 - soloQuadrant) & 3);
    }

    /// @dev True when all 4 quadrant colors are gold (color 7). Colors are never
    ///      hero-touched, so this reads the same on the official and base boards.
    function _allGold(uint8[4] memory traits) private pure returns (bool) {
        for (uint8 i; i < 4; ) {
            if (((traits[i] >> 3) & 7) != 7) return false;
            unchecked {
                ++i;
            }
        }
        return true;
    }

    /// @dev Quadrant the hero is banned from for the current draw, or
    ///      _NO_QUADRANT_BAN. On the resolve draw (any draw after the arm draw) the
    ///      armed quadrant cannot receive a hero, so its official symbol is the raw
    ///      base roll — hero wagers placed during the suspense window can neither
    ///      boost nor block the grand symbol match. The resolve-day ban fields keep
    ///      the answer identical for later re-rolls of the same board (phase 2)
    ///      after `_resolveGoldenTicket` clears the armed fields or a chain arm
    ///      overwrites them.
    function _goldenTicketBanQuadrant(uint256 g, uint24 d) private pure returns (uint8) {
        if (g == 0) return _NO_QUADRANT_BAN;
        if ((g >> 189) & 1 != 0 && d > uint24((g >> 165) & 0xFFFFFF)) {
            return uint8((g >> 160) & 3);
        }
        if ((g >> 190) & 1 != 0 && d == uint24((g >> 193) & 0xFFFFFF)) {
            return uint8((g >> 191) & 3);
        }
        return _NO_QUADRANT_BAN;
    }

    /// @dev Arms the golden ticket for the solo bucket winner of a 4-gold main board.
    ///      Stores winner, solo quadrant, official symbol, and the arm draw's frozen
    ///      dailyIdx; the resolve-day ban fields are preserved so a chain arm (a
    ///      resolve day that itself rolls 4 golds) keeps the current day's hero ban
    ///      intact for later re-rolls of this board.
    function _armGoldenTicket(address winner, uint24 lvl, uint8 traitId) private {
        uint8 quadrant = traitId >> 6;
        uint8 symbol = traitId & 7;
        goldenTicket =
            (goldenTicket & ~((uint256(1) << 190) - 1)) |
            uint256(uint160(winner)) |
            (uint256(quadrant) << 160) |
            (uint256(symbol) << 162) |
            (uint256(dailyIdx) << 165) |
            (uint256(1) << 189);
        emit GoldenTicketArmed(winner, lvl, quadrant, symbol);
    }

    /// @dev Resolves an armed golden ticket against this draw's official main board:
    ///      the board's gold count picks the ladder rung; 4 golds AND the armed
    ///      quadrant repeating the armed symbol is the grand. Rewrites the slot to
    ///      resolve-day ban fields only (armed cleared, ban pinned to this dailyIdx)
    ///      before paying, so re-rolls of this board and any chain arm stay
    ///      consistent and the payout can never double-fire.
    function _resolveGoldenTicket(
        uint256 g,
        uint32 mainTraitsPacked,
        uint24 lvl
    ) private {
        uint8[4] memory traits = JackpotBucketLib.unpackWinningTraits(
            mainTraitsPacked
        );
        uint8 golds;
        for (uint8 i; i < 4; ) {
            if (((traits[i] >> 3) & 7) == 7) {
                unchecked {
                    ++golds;
                }
            }
            unchecked {
                ++i;
            }
        }
        uint8 quadrant = uint8((g >> 160) & 3);
        bool grand = golds == 4 &&
            (traits[quadrant] & 7) == uint8((g >> 162) & 7);
        goldenTicket =
            (uint256(1) << 190) |
            (uint256(quadrant) << 191) |
            (uint256(dailyIdx) << 193);
        _payGoldenTicket(
            address(uint160(g)),
            lvl,
            GOLDEN_TICKET_ROUTE_BOARD,
            golds,
            grand
        );
    }

    /// @notice Pay the golden-ticket grand to a foil pack holding two all-gold
    ///         tickets — the second route into the same top rung the armed board pays.
    /// @dev Delegatecall-only entry, invoked by the foil drain
    ///      (DegenerusGameFoilPackModule._pushFoilGrand, inside advanceGame as the pack's
    ///      sixteen entries are filed) so both routes share ONE grand definition and can
    ///      never drift. Runs in the Game's storage context: the guard rejects a direct
    ///      call on the deployed module, and no facade stub exposes the selector, so the
    ///      foil drain is the only reachable caller — the grand lands at advance time,
    ///      never on a player's claim.
    ///      The armed-board state is untouched — a foil grand neither arms, resolves,
    ///      nor consumes an armed board, so a pending arm still resolves on its own
    ///      next draw.
    /// @param winner The foil buyer whose pack rolled the two all-gold tickets.
    /// @param lvl The pack's cycle level (the flip-credit rate's basis).
    /// @param golds The pack's total gold quadrants — 8 to 16, since the grand fires on
    ///        two or more all-gold tickets and the remaining tickets hold 0-3 golds each.
    ///        Stamped as the event's goldCount; always above the board route's 0-4 range,
    ///        so the two routes never read alike even on the count alone.
    function payGoldenTicketGrand(
        address winner,
        uint24 lvl,
        uint8 golds
    ) external {
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();
        _payGoldenTicket(winner, lvl, GOLDEN_TICKET_ROUTE_FOIL, golds, true);
    }

    // =========================================================================
    // Daily Jackpot ETH — Distribution
    // =========================================================================

    /// @dev Resolves and pays one trait bucket. Selects up to MAX_BUCKET_WINNERS
    ///      ticket holders for the bucket and credits each winner. Jackpot-phase
    ///      conversion uses the original bucket share and its own recipient draw;
    ///      neither the ETH winner count nor its sampling inputs change.
    /// @return paidDelta ETH value paid out for this bucket.
    /// @return claimDelta Claimable-liability added for this bucket.
    function _processBucket(
        uint24 lvl,
        uint8 traitId,
        uint8 traitIdx,
        uint16 count,
        uint256 share,
        uint256 entropy,
        bool isJackpotPhase,
        bool armGold
    ) private returns (uint256 paidDelta, uint256 claimDelta) {
        uint16 totalCount = count;
        if (totalCount > MAX_BUCKET_WINNERS) totalCount = MAX_BUCKET_WINNERS;

        (
            address[] memory winners,
            uint256[] memory ticketIndexes
        ) = _randTraitTicket(
                lvl,
                entropy,
                traitId,
                uint8(totalCount),
                uint8(200 + traitIdx)
            );
        if (winners.length == 0) return (0, 0);

        if (share / totalCount == 0) return (0, 0);

        uint256 passSpent;
        if (isJackpotPhase && share >= 8 * HALF_WHALE_PASS_PRICE) {
            passSpent = _awardWhalePass(lvl, traitId, share, entropy, false, _NO_QUADRANT_EXCLUDE);
        }
        (paidDelta, claimDelta) = _payNormalBucket(
            winners, ticketIndexes, (share - passSpent) / totalCount, lvl, traitId
        );
        paidDelta += passSpent;
        if (armGold && winners[0] != address(0)) {
            _armGoldenTicket(winners[0], lvl, traitId);
        }
    }

    // =========================================================================
    // Internal Helpers — Winner Resolution
    // =========================================================================

    /// @dev Pays the original ETH draw, including the solo bucket, after any pass conversion.
    function _payNormalBucket(
        address[] memory winners,
        uint256[] memory ticketIndexes,
        uint256 perWinner,
        uint24 lvl,
        uint8 traitId
    ) private returns (uint256 totalPaid, uint256 totalLiability) {
        uint256 len = winners.length;
        for (uint256 i; i < len; ) {
            address w = winners[i];
            if (w != address(0)) {
                _creditClaimable(w, perWinner);
                emit JackpotEthWin(w, lvl, traitId, perWinner, ticketIndexes[i]);
                totalPaid += perWinner;
                totalLiability += perWinner;
            }
            unchecked {
                ++i;
            }
        }
    }

    /// @dev Pays the golden-ticket ladder. On the board route the resolve board's gold
    ///      count picks the rung; the foil route enters at `grand` directly (its
    ///      `golds` is the pack's gold quadrant count, above every rung boundary, so it
    ///      falls through to the grand branch). ETH rungs move futurePrizePool into
    ///      the winner's claimable (the only real ETH leg); half-pass and flip-credit
    ///      rungs are face-value credits with no pool debit — pass dilution is
    ///      absorbed by future prize pools and the flip credit stakes the next day's
    ///      coinflip. The grand pays 25% of futurePrizePool in ETH and denominates
    ///      the rest of the headline (the three prize pools plus the yield accumulator —
    ///      claimable is player money already owed and is excluded) 75% in half-passes at
    ///      HALF_WHALE_PASS_PRICE and 25% in flip credit at the level's ticket rate.
    function _payGoldenTicket(
        address winner,
        uint24 lvl,
        uint8 route,
        uint8 golds,
        bool grand
    ) private {
        uint256 ethAward;
        uint256 halfPasses;
        uint256 flipValueWei;
        uint256 wwxrpAward;
        (uint128 nextBal, uint128 futBal) = _getPrizePools();

        if (golds == 0) {
            wwxrpAward = GOLDEN_TICKET_WWXRP;
        } else if (golds == 1) {
            halfPasses = 2; // one whole whale pass
        } else if (golds == 2) {
            ethAward = futBal / 50; // 2% of futurePrizePool
            halfPasses = ethAward / HALF_WHALE_PASS_PRICE; // equal value, rounded down
        } else if (golds == 3) {
            ethAward = futBal / 20; // 5% of futurePrizePool
            halfPasses = ethAward / HALF_WHALE_PASS_PRICE;
        } else if (!grand) {
            ethAward = futBal / 10; // 10% of futurePrizePool
            halfPasses = (2 * ethAward) / HALF_WHALE_PASS_PRICE; // double the ETH leg
            flipValueWei = futBal / 20; // 5% of futurePrizePool as flip credit
        } else {
            // Grand: 25% of futurePrizePool in ETH; the rest of the headline owed
            // 75% in half-passes / 25% in flip credit. The headline counts the
            // three prize pools plus the segregated yield accumulator — all frozen to the
            // advance path for the VRF window this runs in (in-window purchases land in the
            // pending accumulators). Claimable is player money already owed, and the pending
            // accumulators move with in-window purchases, so neither may size a VRF-derived award.
            ethAward = futBal / 4;
            uint256 headline = _getCurrentPrizePool() +
                nextBal +
                futBal +
                yieldAccumulator;
            uint256 remainder = headline - ethAward;
            uint256 passValue = (remainder * 3) / 4;
            halfPasses = passValue / HALF_WHALE_PASS_PRICE;
            flipValueWei = remainder - passValue;
        }

        if (ethAward != 0) {
            _setPrizePools(nextBal, uint128(futBal - ethAward));
            _creditClaimable(winner, ethAward);
            claimablePool += uint128(ethAward);
        }
        if (halfPasses != 0) {
            whalePassClaims[winner] += halfPasses;
        }
        uint256 flipCredit;
        if (flipValueWei != 0) {
            flipCredit =
                (flipValueWei * PRICE_COIN_UNIT) /
                PriceLookupLib.priceForLevel(lvl + 1);
            // Truncate to a whole 100-FLIP multiple. This leg is 5% of futurePrizePool on
            // the 4-gold rung and a quarter of the grand's non-ETH remainder, so the
            // discarded tail is under 1% at any pool worth winning and the path needs no
            // VRF seed threaded into it to pay a round number. The event carries the
            // truncated figure, which is what the winner receives.
            flipCredit =
                (flipCredit / FlipRoundLib.FLIP_ROUND_UNIT) *
                FlipRoundLib.FLIP_ROUND_UNIT;
            if (flipCredit != 0) {
                coinflip.creditFlip(winner, flipCredit);
            }
        }
        if (wwxrpAward != 0) {
            IWwxrpMintPrize(ContractAddresses.WWXRP).mintPrize(
                winner,
                wwxrpAward
            );
        }
        emit GoldenTicketWin(
            winner,
            lvl,
            route,
            golds,
            grand,
            ethAward,
            halfPasses,
            flipCredit,
            wwxrpAward
        );
    }

    /// @dev Rolls a board off one VRF word: fully random base traits (6 bits per quadrant),
    ///      then the hero sampled by `_rollHeroSymbol` from the prior day's settled wager
    ///      pool replaces the winning quadrant's symbol bits only. The quadrant keeps its
    ///      base-rolled color, so all four colors stay independent 1/8 draws regardless of
    ///      where (or whether) a hero lands. Reads `dailyHeroWagers[dailyIdx]`: `dailyIdx`
    ///      moves only at `_unlockRng` and at rngGate's gap skip (AdvanceModule), both outside
    ///      jackpot processing, so here it is frozen at the previous day's index. Bets placed
    ///      on day D write to `dailyHeroWagers[D]`; day D+1's jackpot reads slot[D] via
    ///      `dailyIdx == D` (set by day D's `_unlockRng`).
    /// @param banQuadrant Quadrant the hero may not land in, or `_NO_QUADRANT_BAN`.
    function _rollBoard(uint256 randWord, uint8 banQuadrant) private view returns (uint32) {
        uint8[4] memory traits = JackpotBucketLib.getRandomTraits(randWord);
        (bool hasHero, uint8 heroQuadrant, uint8 heroSymbol) = _rollHeroSymbol(
            dailyIdx,
            randWord,
            banQuadrant
        );
        if (hasHero) {
            traits[heroQuadrant] = (traits[heroQuadrant] & 0xF8) | heroSymbol;
        }
        return JackpotBucketLib.packWinningTraits(traits);
    }

    /// @dev The day's one winning board. The hero is banned from the golden ticket's armed
    ///      quadrant on its resolve draw (see `_goldenTicketBanQuadrant`). A day's later legs
    ///      re-roll it from the same word and get the same board: the hero pool and the ban
    ///      read the same on every roll of a day, the resolve-day ban fields holding the ban
    ///      after the resolve clears the armed ones.
    function _rollMainTraits(uint256 randWord) private view returns (uint32) {
        uint32 board = _rollBoard(randWord, _goldenTicketBanQuadrant(goldenTicket, dailyIdx));
        uint8 dice = GoldSixLib.daily(uint8(board >> 24), randWord);
        return (board & 0x00ffffff) | (uint32(dice) << 24);
    }

    /// @dev Samples the day's hero `(quadrant, symbol)` via a weighted random roll across
    ///      the 24 eligible slots of `dailyHeroWagers[day]`; Dice never receive a boost.
    ///      Pass 1 SLOADs the 3 eligible packed quadrants once, decodes their uint32
    ///      amounts, accumulates the total, and tracks
    ///      the largest-amount slot (first-seen on ties to match the scan order).
    ///      Pass 2 walks the cached weights with a cumulative cursor against
    ///      `pick = uint64(uint256(keccak256(abi.encode(entropy, HERO_SYMBOL_TAG, day))) % effectiveTotal)`
    ///      and applies a `leaderBonus = maxAmount / 2` add at the largest-amount slot —
    ///      effective ×1.5 weight on the leader, no min-wager floor on any other slot.
    ///      Returns `(false, 0, 0)` when no slot has any wagers.
    ///
    ///      `banQuadrant` zeroes an entire quadrant's 8 slots before the roll, so the
    ///      result can never land there and the leader is recomputed over the rest — main
    ///      rolls pass `_goldenTicketBanQuadrant()` so on a golden-ticket resolve day the
    ///      armed quadrant keeps its base-rolled symbol (hero wagers can neither boost nor
    ///      block the grand match). Pass `_NO_QUADRANT_BAN` otherwise; when the ban empties
    ///      the pool the result is `(false, 0, 0)` and the caller applies no hero.
    function _rollHeroSymbol(
        uint24 day,
        uint256 entropy,
        uint8 banQuadrant
    )
        private
        view
        returns (bool hasWinner, uint8 winQuadrant, uint8 winSymbol)
    {
        uint32[24] memory weights;
        uint64 total;
        uint32 maxAmount;
        uint8 leaderIdx;

        for (uint8 q; q < DEGENERETTE_HERO_COUNT / 8; ) {
            if (q == banQuadrant) {
                unchecked {
                    ++q;
                }
                continue;
            }
            uint256 packed = dailyHeroWagers[day][q];
            for (uint8 s; s < 8; ) {
                uint8 idx;
                unchecked {
                    idx = (q << 3) | s;
                }
                uint32 amount = uint32((packed >> (uint256(s) * 32)) & 0xFFFFFFFF);
                weights[idx] = amount;
                total += uint64(amount);
                if (amount > maxAmount) {
                    maxAmount = amount;
                    leaderIdx = idx;
                }
                unchecked {
                    ++s;
                }
            }
            unchecked {
                ++q;
            }
        }

        if (total == 0) {
            return (false, 0, 0);
        }

        uint64 leaderBonus = uint64(maxAmount) / 2;
        uint64 effectiveTotal = total + leaderBonus;
        uint64 pick = uint64(
            uint256(keccak256(abi.encode(entropy, HERO_SYMBOL_TAG, day))) % effectiveTotal
        );

        uint64 cumulative;
        for (uint8 idx; idx < DEGENERETTE_HERO_COUNT; ) {
            cumulative += uint64(weights[idx]);
            if (idx == leaderIdx) {
                cumulative += leaderBonus;
            }
            if (cumulative > pick) {
                return (true, uint8(idx >> 3), uint8(idx & 7));
            }
            unchecked {
                ++idx;
            }
        }
    }

    // =========================================================================
    // Internal Helpers — Winner Selection
    // =========================================================================

    /// @dev Selects random winners from a trait's ticket pool, returning both addresses and indices.
    ///      Reads the bucket length and deity itself; distribution paths that
    ///      already hold them use the precomputed overload directly.
    function _randTraitTicket(
        uint24 lvl,
        uint256 randomWord,
        uint8 trait,
        uint8 numWinners,
        uint8 salt
    )
        private
        view
        returns (address[] memory winners, uint256[] memory ticketIndexes)
    {
        uint256 len = _bucketLength(lvl, trait);

        // traitId layout: (quadrant << 6) | (color << 3) | symIdx
        // fullSymId = quadrant * 8 + symIdx
        address deity = _traitDeity(trait);

        return
            _randTraitTicket(
                lvl,
                randomWord,
                trait,
                numWinners,
                salt,
                len,
                deity
            );
    }

    /// @dev Winner-selection core with caller-supplied bucket length and deity.
    ///      Each group draws up to eight lanes of one random packed word. Padding is
    ///      redrawn uniformly; virtual deity entries retain their per-entry weight.
    function _randTraitTicket(
        uint24 lvl,
        uint256 randomWord,
        uint8 trait,
        uint8 numWinners,
        uint8 salt,
        uint256 len,
        address deity
    )
        private
        view
        returns (address[] memory winners, uint256[] memory ticketIndexes)
    {
        _assertReadableTicketLevel(lvl);
        uint256 virtualCount = _deityVirtualCount(trait, len, deity);

        uint256 effectiveLen = len + virtualCount;
        if (effectiveLen == 0 || numWinners == 0) {
            return (new address[](0), new uint256[](0));
        }

        winners = new address[](numWinners);
        ticketIndexes = new uint256[](numWinners);
        PackedTicketSampleLib.Cursor memory cursor;
        for (uint256 i; i < numWinners; ) {
            (winners[i], ticketIndexes[i]) = _drawBucketEntry(
                lvl, trait, len, effectiveLen, deity, randomWord, salt, i, cursor
            );
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Level 1's trait-matched FLIP draw over level-1 ticket holders.
    /// @dev Runs in level 1's purchase-day advance, after emitDailyWinningTraits rolled and
    ///      recorded the day's main board, which it re-rolls from the same word. Awards 0.25% of
    ///      the previous level's recorded prize pool (`levelPrizePool[lvl - 1]`, the ratchet
    ///      target before any century floor), converted to FLIP at the current level's ticket
    ///      price, as up to COIN_DRAW_SHARES equal whole-unit shares to trait-matched ticket
    ///      holders in [minLevel, maxLevel], which must be minted levels.
    /// @param lvl Level keying the prize pool snapshot for the budget.
    /// @param randWord VRF entropy for the board and winner selection.
    /// @param minLevel Minimum target level for the coin distribution (inclusive).
    /// @param maxLevel Maximum target level for the coin distribution (inclusive).
    function payDailyFlipJackpot(uint24 lvl, uint256 randWord, uint24 minLevel, uint24 maxLevel) external {
        _delegateJackpotDraw(abi.encodeWithSelector(
            IDegenerusGameJackpotDrawModule.awardDailyFlipJackpot.selector,
            minLevel, maxLevel, _rollMainTraits(randWord), _calcDailyCoinBudget(lvl, level), randWord
        ));
    }

    /// @notice One step of the daily jackpot battle, in either phase (see _playJackpotBattle).
    /// @dev Awards are drawn from the far-future queues of [lvl + 1, lvl + 99]; the field and its
    ///      Added were locked at the daily request.
    /// @param lvl The mint ceiling: the draw's levels start above it.
    /// @param randWord The day's recorded VRF word.
    function payPurchaseJackpotBattle(uint24 lvl, uint256 randWord) external {
        _delegateJackpotDraw(abi.encodeWithSelector(
            IDegenerusGameJackpotDrawModule.runPurchaseJackpotBattle.selector, lvl, randWord, MineFlipGas.available()
        ));
    }

    function runPurchaseJackpotBattle(uint24, uint256, uint256)
        external returns (MineFlipGas.Result memory)
    {
        return abi.decode(_delegateJackpotDraw(msg.data), (MineFlipGas.Result));
    }

    function _delegateJackpotDraw(bytes memory callData) private returns (bytes memory data) {
        bool ok;
        (ok, data) = ContractAddresses.GAME_JACKPOT_DRAW_MODULE.delegatecall(callData);
        if (!ok) assembly ("memory-safe") { revert(add(data, 32), mload(data)) }
    }

    /// @notice Roll, record and emit level 1's purchase-day board without running any
    ///         distribution.
    /// @dev Used at purchaseLevel == 1, where payDailyJackpot is skipped: the day's coin budget
    ///      pays level 1's trait-matched FLIP draw and the jackpot battle instead. Records the board
    ///      for foil claims.
    /// @param randWord VRF entropy for the board.
    function emitDailyWinningTraits(uint256 randWord) external {
        if (msg.sender != ContractAddresses.GAME) revert OnlyGame();
        // The sealed day, matching payDailyJackpot: dailyIdx + 1, never the wall clock.
        _emitDailyWinningTraits(dailyIdx + 1, _rollMainTraits(randWord), 1, randWord);
    }

    /// @dev Records the day's board in the two-slot draw ring for foil claims
    ///      (foil == jackpot by construction; one write per day) and emits it.
    function _emitDailyWinningTraits(uint24 questDay, uint32 mainTraitsPacked, uint24 lvl, uint256 randWord) private {
        uint24 slot = questDay & 1;
        uint24 storedDay = uint24(dailyFoilDraw[slot] >> _FOIL_DRAW_DAY_SHIFT);
        // A retry or stale callback must neither replace a newer sealed draw nor
        // interrupt the advance. An unused slot has day zero; draw days are nonzero.
        if (storedDay >= questDay) return;
        dailyFoilDraw[slot] = _packFoilDraw(mainTraitsPacked, lvl, questDay, randWord);
        emit DailyWinningTraits(questDay, mainTraitsPacked);
    }

    /// @dev Calculate 0.25% of the previous level's recorded prize pool (`levelPrizePool[lvl - 1]`,
    ///      the ratchet target before any century floor), converted to FLIP at the current
    ///      level's ticket price.
    /// @param lvl Level keying the prize pool snapshot (purchase level on the
    ///        payDailyFlipJackpot path, where it differs from the current level).
    /// @param currLevel Current game level, used for FLIP pricing.
    function _calcDailyCoinBudget(
        uint24 lvl,
        uint24 currLevel
    ) private view returns (uint256) {
        uint256 priceWei = PriceLookupLib.priceForLevel(currLevel);
        if (priceWei == 0) return 0;
        return (levelPrizePool[lvl - 1] * PRICE_COIN_UNIT) / (priceWei * 400);
    }

    /// @dev Current-pool daily jackpot share for non-final days: random 6%-14%
    ///      (avg 10%). The sole caller gates on !isFinalPhysicalDay; the final
    ///      physical day assigns 100% directly without consulting this.
    function _dailyCurrentPoolBps(
        uint8 counter,
        uint256 randWord
    ) private pure returns (uint16 bps) {
        uint16 range = DAILY_CURRENT_BPS_MAX - DAILY_CURRENT_BPS_MIN + 1;
        uint256 seed = uint256(
            keccak256(
                abi.encodePacked(randWord, DAILY_CURRENT_BPS_TAG, counter)
            )
        );
        return uint16(DAILY_CURRENT_BPS_MIN + (seed % range));
    }

    /// @notice The BAF draw and its ordered payouts share the cold draw module.
    function runBafJackpot(uint256, uint24, uint256) external returns (uint256 claimableDelta) {
        if (msg.sender != address(this)) revert OnlySelf();
        return abi.decode(_delegateJackpotDraw(msg.data), (uint256));
    }
}
