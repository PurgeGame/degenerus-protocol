// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {IStETH} from "../interfaces/IStETH.sol";
import {DegenerusGamePayoutUtils} from "./DegenerusGamePayoutUtils.sol";
import {ContractAddresses} from "../ContractAddresses.sol";
import {EntropyLib} from "../libraries/EntropyLib.sol";
import {FlipRoundLib} from "../libraries/FlipRoundLib.sol";
import {PriceLookupLib} from "../libraries/PriceLookupLib.sol";
import {JackpotBucketLib} from "../libraries/JackpotBucketLib.sol";
import {IDegenerusJackpots} from "../interfaces/IDegenerusJackpots.sol";

/// @dev Minimal WWXRP surface for the golden-ticket consolation mint. The delegatecall
///      context makes msg.sender the Game, which is a whitelisted WWXRP minter.
interface IWwxrpMintPrize {
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
 *      3. `payDailyFlipJackpot` — FLIP jackpot distribution to near-future ticket holders.
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
contract DegenerusGameJackpotModule is DegenerusGamePayoutUtils {
    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    error OnlyGame();

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    /// @dev Emitted when a far-future ticket holder (5-99 levels ahead) wins the daily FLIP jackpot.
    ///      These winners are drawn from ticketQueue (traits not yet assigned).
    event FarFutureFlipJackpotWinner(
        address indexed winner,
        uint24 indexed currentLevel,
        uint24 indexed winnerLevel,
        uint256 amount
    );

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

    /// @dev Emitted once per daily drawing with both main and bonus winning traits.
    event DailyWinningTraits(
        uint24 indexed day,
        uint32 mainTraitsPacked,
        uint32 bonusTraitsPacked,
        uint24 bonusTargetLevel
    );

    /// @dev Whale pass awarded to solo bucket winner.
    event JackpotWhalePassWin(
        address indexed winner,
        uint24 indexed level,
        uint256 halfPassCount
    );

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
    ///      debit; wwxrpAmount is the 0-gold consolation.
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

    /// @dev Maximum number of daily jackpots per level before forcing level transition.
    uint8 private constant JACKPOT_LEVEL_CAP = 5;

    uint256 private constant SMALL_LOOTBOX_THRESHOLD = 0.5 ether;

    /// @dev Golden-ticket consolation when the bonus board shows 0 golds: 100 WWXRP.
    uint256 private constant GOLDEN_TICKET_WWXRP = 100 ether;

    /// @dev Golden-ticket routes, stamped on GoldenTicketWin. BOARD is the armed
    ///      cross-day board resolution; FOIL is a foil pack holding two or more
    ///      all-gold tickets, which takes the grand outright.
    uint8 private constant GOLDEN_TICKET_ROUTE_BOARD = 0;
    uint8 private constant GOLDEN_TICKET_ROUTE_FOIL = 1;

    /// @dev Sentinel traitId stamped on BAF jackpot payout events so indexers can
    ///      distinguish BAF wins from trait-bucketed daily/coin wins. Sits above
    ///      uint8.max (255) so it never collides with a real trait id.
    uint16 private constant BAF_TRAIT_SENTINEL = 420;

    // -------------------------------------------------------------------------
    // Constants — Share Distribution (Basis Points)
    // -------------------------------------------------------------------------

    /// @dev Day-5 trait bucket shares packed into 64 bits: [6000, 1333, 1333, 1334] = 10000 bps.
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

    /// @dev Domain separator for coin jackpot entropy derivation.
    bytes32 private constant FLIP_JACKPOT_TAG = keccak256("coin-jackpot");

    /// @dev Domain separator for per-pull level sampling in the daily coin jackpot.
    ///      Distinct from FLIP_JACKPOT_TAG so (randomWord, FLIP_JACKPOT_TAG, ·) and
    ///      (randomWord, FLIP_LEVEL_TAG, ·) keccaks cannot collide.
    bytes32 private constant FLIP_LEVEL_TAG = keccak256("coin-level");

    /// @dev Domain separator for rolling current-pool daily jackpot percentage.
    bytes32 private constant DAILY_CURRENT_BPS_TAG =
        keccak256("daily-current-bps");

    /// @dev Domain separator for selecting daily carryover source level.
    bytes32 private constant DAILY_CARRYOVER_SOURCE_TAG =
        keccak256("daily-carryover-source");

    /// @dev Domain separator for bonus trait derivation from same VRF word.
    bytes32 private constant BONUS_TRAITS_TAG = keccak256("BONUS_TRAITS");

    /// @dev Sentinel `excludeIdx` for `_rollHeroSymbol` meaning "no slot excluded":
    ///      any value >= 32 matches no real `(quadrant << 3) | symbol` slot, so the
    ///      roll runs over the full wager pool. The bonus draw instead passes the
    ///      main hero's packed slot to force a distinct hero.
    uint8 private constant _NO_HERO_EXCLUDE = 0xFF;

    /// @dev Sentinel for _rollHeroSymbol's banQuadrant param: no quadrant banned.
    uint8 private constant _NO_QUADRANT_BAN = 0xFF;

    /// @dev Sentinel for _computeBucketCounts' excludeIdx param: every bucket eligible.
    ///      Any value >= 4 matches no bucket index.
    uint8 private constant _NO_QUADRANT_EXCLUDE = 0xFF;

    /// @dev Max forward offset for carryover source selection (lvl+1..lvl+4).
    uint8 private constant DAILY_CARRYOVER_MAX_OFFSET = 4;

    /// @dev Current-pool daily jackpot percentage bounds for days 1-4 (6%-14%).
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
    ///      Set to 250 to allow all ticket winners in single trait if others are empty.
    uint8 private constant MAX_BUCKET_WINNERS = 250;

    // -------------------------------------------------------------------------
    // Constants — Jackpot Bucket Scaling (Gas Guardrails)
    // -------------------------------------------------------------------------

    /// @dev Maximum ticket winners for the purchase-phase drip ticket distribution.
    /// Higher than ETH winners because ticket distribution is cheaper per winner.
    uint16 private constant PURCHASE_PHASE_TICKET_MAX_WINNERS = 120;

    /// @dev Maximum winners for daily coin jackpot (all paid in one coinflip.creditFlipBatch call).
    uint16 private constant DAILY_COIN_MAX_WINNERS = 50;

    /// @dev Share of daily FLIP budget awarded to far-future ticket holders (25%).
    uint16 private constant FAR_FUTURE_FLIP_BPS = 2500;

    /// @dev Number of far-future levels to sample for FLIP jackpot (10 winners max).
    uint8 private constant FAR_FUTURE_FLIP_SAMPLES = 10;

    /// @dev Domain separator for far-future coin jackpot entropy derivation.
    bytes32 private constant FAR_FUTURE_FLIP_TAG = keccak256("far-future-coin");

    /// @dev Maximum winners per ticket jackpot distribution (gas safety);
    ///      the daily, carryover, and early-bird legs each apply it separately.
    uint16 private constant TICKET_JACKPOT_MAX_WINNERS = 100;

    /// @dev Entries per whole ticket. Jackpot budgets are denominated in entries
    ///      (quarter-tickets), but awards are paid in whole tickets only.
    uint256 private constant ENTRIES_PER_TICKET = 4;

    /// @dev Daily jackpot max scale (6.36x) producing bucket counts 159/95/50/1 at 200+ ETH.
    ///      All 305 winners (159 + 95 + 50 + 1) are paid in a single call.
    uint32 private constant DAILY_JACKPOT_SCALE_MAX_BPS = 63_600;

    // =========================================================================
    // External Entry Points (delegatecall targets)
    // =========================================================================

    /// @notice Terminal (game-over) jackpot: Day-5-style bucket distribution.
    /// @dev Called via IDegenerusGame(address(this)) from GameOverModule.
    ///      Uses FINAL_DAY_SHARES_PACKED (60/13/13/13) with trait-based bucket distribution.
    ///      Updates claimablePool internally — callers must NOT double-count.
    /// @param poolWei Total ETH to distribute.
    /// @param targetLvl Level to sample winners from (typically lvl+1).
    /// @param rngWord VRF entropy seed.
    /// @return paidWei Total ETH distributed (callers deduct from source pool).
    function runTerminalJackpot(
        uint256 poolWei,
        uint24 targetLvl,
        uint256 rngWord
    ) external returns (uint256 paidWei) {
        if (msg.sender != ContractAddresses.GAME) revert OnlyGame();

        uint32 winningTraitsPacked = _rollWinningTraits(rngWord, false);
        uint8[4] memory traitIds = JackpotBucketLib.unpackWinningTraits(
            winningTraitsPacked
        );
        uint256 effectiveEntropy = _soloAdjustedEntropy(
            traitIds,
            EntropyLib.hash2(rngWord, targetLvl)
        );

        uint16[4] memory bucketCounts = JackpotBucketLib.bucketCountsForPool(
            poolWei,
            effectiveEntropy,
            DAILY_JACKPOT_SCALE_MAX_BPS
        );
        uint16[4] memory shareBps = JackpotBucketLib.shareBpsByBucket(
            FINAL_DAY_SHARES_PACKED,
            uint8(effectiveEntropy & 3)
        );

        paidWei = _processDailyEth(
            targetLvl,
            poolWei,
            effectiveEntropy,
            traitIds,
            shareBps,
            bucketCounts,
            false, // not jackpot phase
            false, // no solo bucket, golden ticket never arms here
            PriceLookupLib.priceForLevel(targetLvl + 1) >> 2
        );
    }

    /// @notice Pays purchase phase jackpots OR rolling daily jackpots at level end.
    /// @dev Called by the parent game contract via delegatecall. Two distinct paths:
    ///
    ///      JACKPOT PHASE PATH (isJackpotPhase=true):
    ///      - Day 1-4: Distributes a random 6%-14% slice of remaining currentPrizePool.
    ///      - Day 5: Distributes 100% of remaining currentPrizePool.
    ///      - Day 1 also runs the early-bird ticket jackpot (from futurePrizePool).
    ///      - On every non-early-bird day (2-5), takes 0.5% of futurePrizePool and buys current-level tickets
    ///        for winners from a random source level in [lvl+1, lvl+4], deposited into nextPool.
    ///      - Increments jackpotCounter on completion.
    ///
    ///      PURCHASE PHASE PATH (isJackpotPhase=false):
    ///      - Triggered during purchase phase when burns occur.
    ///      - Rolls winning traits (random + hero override) and runs trait-based jackpot.
    ///      - Fixed winner counts [20, 12, 6, 1] = 39 ETH winners, up to 120 ticket winners.
    ///      - Adds a 1% futurePrizePool ETH slice every purchase day, split 75/23/2:
    ///        75% to the ticket leg (backing ETH → nextPrizePool, tickets to trait
    ///        winners), 2% skimmed to the yield accumulator, 23% distributed as ETH.
    ///
    /// @param isJackpotPhase True for jackpot phase dailies, false for purchase phase jackpot.
    /// @param lvl Current game level.
    /// @param randWord VRF entropy for winner selection and trait derivation.
    function payDailyJackpot(
        bool isJackpotPhase,
        uint24 lvl,
        uint256 randWord
    ) external {
        // The day being SEALED, not the wall day: dailyIdx has not advanced yet on this
        // path, so dailyIdx + 1 is the logical day this word resolves. The two diverge
        // when processing straddles the 22:57 break or the word lands a day late — the
        // advance clamps to the logical day, and a wall-day key here would write the foil
        // board (and the traits event) under the WRONG day, stranding that day's claims.
        uint24 questDay = dailyIdx + 1;
        // One VRF word drives both rolls; each rolls its OWN hero — the bonus hero is
        // forced distinct from the main hero (main slot excluded from the bonus roll).
        (
            uint32 winningTraitsPacked,
            uint32 bonusTraitsPacked
        ) = _rollWinningTraitsPair(randWord);

        // An armed golden ticket resolves against the first main board rolled after the
        // arm draw — this draw, whenever dailyIdx has advanced past the arm draw's
        // index. Runs before any pool math so the ladder's futurePrizePool debit is
        // visible to every later read in this call.
        {
            uint256 g = goldenTicket;
            if (
                (g >> 189) & 1 != 0 &&
                dailyIdx > uint24((g >> 165) & 0xFFFFFF)
            ) {
                _resolveGoldenTicket(g, winningTraitsPacked, lvl);
            }
        }

        if (isJackpotPhase) {
            uint256 dailyEthBudget;
            uint256 dailyUnit; // ticket unit from _budgetToEntries, threaded into _processDailyEth
            uint8 counterStep = 1;
            bool isFinalPhysicalDay;
            uint256 curPool;
            {
                uint8 counter = jackpotCounter;
                uint8 compressedFlag = compressedJackpotFlag;
                // Turbo (flag=2): all 5 logical days in 1 physical day.
                // Compressed (flag=1): 5 logical days in 3 physical days.
                if (compressedFlag == 2 && counter == 0) {
                    counterStep = JACKPOT_LEVEL_CAP;
                } else if (
                    compressedFlag == 1 &&
                    counter > 0 &&
                    counter < JACKPOT_LEVEL_CAP - 1
                ) {
                    counterStep = 2;
                }
                isFinalPhysicalDay = (counter + counterStep >=
                    JACKPOT_LEVEL_CAP);
                bool isEarlyBirdDay = (counter == 0);
                curPool = _getCurrentPrizePool();
                uint16 dailyBps;
                if (isFinalPhysicalDay) {
                    dailyBps = 10_000; // Final physical day: 100% of remaining pool
                } else {
                    dailyBps = _dailyCurrentPoolBps(counter, randWord);
                    // Double BPS on compressed days to combine two days' payouts.
                    if (counterStep == 2) {
                        dailyBps *= 2;
                    }
                }
                uint256 budget = (curPool * dailyBps) / 10_000;

                // Run the early-bird ticket jackpot on day 1 only.
                // This day replaces the normal daily carryover flow.
                if (isEarlyBirdDay) {
                    _runEarlyBirdTicketJackpot(lvl + 1, randWord);
                }

                // Gas optimization: 20% = 1/5 (cheaper than * 2000 / 10000)
                uint256 dailyTicketBudget = budget / 5;
                // Jackpot phase: the currentPrizePool floor (>= 10 ETH) dwarfs the ticket price, so
                // budget and dailyTicketBudget are always nonzero — no zero-guard needed.
                budget -= dailyTicketBudget;

                // Calculate daily ticket units (distributed in Phase 2 via payDailyJackpotCoinAndTickets)
                uint256 dailyEntries;
                (dailyEntries, dailyUnit) = _budgetToEntries(
                    dailyTicketBudget,
                    lvl + 1
                );
                // dailyEntries is always >= 1 in jackpot phase (the currentPrizePool floor dwarfs
                // the ticket price), so the daily-ticket credit is unconditional. Deduct from the
                // current pool to back the tickets; the matching next-pool credit is folded into the
                // carryover packed write below (or applied on its own in the early-bird branch), so
                // the daily add and the future->next move share one prizePoolsPacked RMW. curPool is
                // still exact: nothing above writes currentPrizePool.
                curPool -= dailyTicketBudget;
                _setCurrentPrizePool(curPool);

                uint8 sourceLevelOffset;
                uint24 sourceLevel;
                uint256 reserveSlice;
                uint256 carryoverEntries;
                if (!isEarlyBirdDay) {
                    sourceLevelOffset = uint8(
                        (uint256(
                            keccak256(
                                abi.encodePacked(
                                    randWord,
                                    DAILY_CARRYOVER_SOURCE_TAG,
                                    counter
                                )
                            )
                        ) % DAILY_CARRYOVER_MAX_OFFSET) + 1
                    );
                    sourceLevel = lvl + uint24(sourceLevelOffset);

                    // 0.5% of futurePrizePool reserved for carryover tickets, moved future -> next
                    // in one packed-slot read/write that also folds in the daily-ticket next credit
                    // (checked uint128 adds: both addends are < 2^128 and the sum reverts on overflow
                    // exactly as the two separate writes did).
                    (uint128 nextBal, uint128 futPool) = _getPrizePools();
                    reserveSlice = uint256(futPool) / 200;
                    _setPrizePools(
                        nextBal +
                            uint128(dailyTicketBudget) +
                            uint128(reserveSlice),
                        futPool - uint128(reserveSlice)
                    );
                    // Priced at the level these entries are queued at, the same basis the
                    // daily leg above uses: Phase 2 sends the final physical day's carryover
                    // to lvl + 1 because this level ends tonight. Pricing off the other level
                    // would size the award by the boundary price ratio instead of by the
                    // reserveSlice that backs it.
                    (carryoverEntries, ) = _budgetToEntries(
                        reserveSlice,
                        isFinalPhysicalDay ? lvl + 1 : lvl
                    );
                } else {
                    // Early-bird day skips the carryover move, so apply the daily-ticket next
                    // credit on its own here.
                    _addNextPrizePool(dailyTicketBudget);
                }

                // Store ticket units for Phase 2 distribution
                // Packing: [counterStep (8 bits)] [dailyEntries (64 bits @ 8)]
                // [carryoverEntries (64 bits @ 72)] [carryoverSourceOffset (8 bits @ 136)]
                dailyTicketBudgetsPacked = _packDailyTicketBudgets(
                    counterStep,
                    dailyEntries,
                    carryoverEntries,
                    sourceLevelOffset
                );

                dailyEthBudget = budget;
            }

            uint8[4] memory traitIdsDaily = JackpotBucketLib
                .unpackWinningTraits(winningTraitsPacked);
            uint256 effectiveEntropyDaily = _soloAdjustedEntropy(
                traitIdsDaily,
                EntropyLib.hash2(randWord, lvl)
            );
            bool armGold = _allGold(traitIdsDaily);

            if (dailyEthBudget != 0) {
                uint16[4] memory bucketCountsDaily = JackpotBucketLib
                    .bucketCountsForPool(
                        dailyEthBudget,
                        effectiveEntropyDaily,
                        DAILY_JACKPOT_SCALE_MAX_BPS
                    );

                // Final physical day uses weighted shares (60/13/13/13) for the big payout;
                // other days use equal shares (20/20/20/20).
                uint64 sharesPacked = isFinalPhysicalDay
                    ? FINAL_DAY_SHARES_PACKED
                    : DAILY_JACKPOT_SHARES_PACKED;
                uint16[4] memory shareBpsDaily = JackpotBucketLib
                    .shareBpsByBucket(sharesPacked, uint8(effectiveEntropyDaily & 3));

                uint256 paidDailyEth = _processDailyEth(
                    lvl,
                    dailyEthBudget,
                    effectiveEntropyDaily,
                    traitIdsDaily,
                    shareBpsDaily,
                    bucketCountsDaily,
                    true, // jackpot phase (solo bucket gets whale pass)
                    armGold,
                    dailyUnit
                );
                if (isFinalPhysicalDay) {
                    uint256 unpaidDailyEth = dailyEthBudget - paidDailyEth;
                    // curPool tracks the live value: nothing since the ticket
                    // deduction writes currentPrizePool.
                    _setCurrentPrizePool(curPool - dailyEthBudget);
                    if (unpaidDailyEth != 0) {
                        _addFuturePrizePool(unpaidDailyEth);
                    }
                } else {
                    _setCurrentPrizePool(curPool - paidDailyEth);
                }
            }

            _emitDailyWinningTraits(
                questDay,
                winningTraitsPacked,
                bonusTraitsPacked,
                randWord,
                lvl
            );

            dailyJackpotCoinTicketsPending = true;
            return;
        }

        // Purchase phase path - FLIP and ETH bonuses
        uint8[4] memory traitIds = JackpotBucketLib.unpackWinningTraits(winningTraitsPacked);
        uint256 effectiveEntropy = _soloAdjustedEntropy(
            traitIds,
            EntropyLib.hash2(randWord, lvl)
        );

        _emitDailyWinningTraits(
            questDay,
            winningTraitsPacked,
            bonusTraitsPacked,
            randWord,
            lvl
        );

        // Daily 1% drip from futurePrizePool every purchase day.
        uint256 futureBal = _getFuturePrizePool();
        uint256 ethDaySlice = futureBal / 100;

        uint256 ethPool = ethDaySlice;
        uint256 ticketLegBudget;
        uint256 insuranceCut;
        if (ethPool != 0) {
            // Both legs are sized off the whole slice, so the split is 75/23/2 and the
            // ETH leg keeps the two flooring remainders. Deducting before bucket sizing
            // leaves the day's whole-granule rounding working off the payable figure.
            ticketLegBudget = (ethPool * PURCHASE_REWARD_JACKPOT_TICKET_BPS) / 10_000;
            insuranceCut = (ethPool * PURCHASE_INSURANCE_BPS) / 10_000;
            ethPool -= ticketLegBudget + insuranceCut;
        }

        // Fixed bucket counts [20, 12, 6, 1] = 39 winners, rotated by entropy.
        uint256 paidEth;
        if (ethPool != 0) {
            uint16[4] memory shareBps = JackpotBucketLib.shareBpsByBucket(
                DAILY_JACKPOT_SHARES_PACKED,
                uint8(effectiveEntropy & 3)
            );
            uint16[4] memory bucketCounts;
            {
                uint16[4] memory base;
                base[0] = 20;
                base[1] = 12;
                base[2] = 6;
                base[3] = 1;
                uint8 offset = uint8(effectiveEntropy & 3);
                for (uint8 i; i < 4; ) {
                    bucketCounts[i] = base[(i + offset) & 3];
                    unchecked {
                        ++i;
                    }
                }
            }
            paidEth = _processDailyEth(
                lvl,
                ethPool,
                effectiveEntropy,
                traitIds,
                shareBps,
                bucketCounts,
                false, // not jackpot phase
                false, // no solo bucket, golden ticket never arms here
                PriceLookupLib.priceForLevel(lvl + 1) >> 2
            );
        }

        // Single packed-slot RMW folds every leg: credit the ticket leg's backing to nextPrizePool
        // and debit the future pool (drip consumed + ETH paid + insurance skim). ticketLegBudget and
        // insuranceCut are nonzero only when ethDaySlice is, so both ride this write;
        // _distributePoolBackedTickets below no longer credits next itself. futureBal is still exact —
        // nothing above writes prizePoolsPacked (purchase-phase distribution never reaches the solo
        // whale-pass leg). The ticket leg, the skim and the ETH leg partition ethDaySlice exactly and
        // paidEth never exceeds the ETH leg, so the three debits sum to at most the 1% slice and the
        // subtraction cannot underflow. The accumulator write touches its own slot, leaving the
        // packed read above exact.
        if (ethDaySlice != 0) {
            (uint128 nextBal, uint128 futBal) = _getPrizePools();
            _setPrizePools(
                nextBal + uint128(ticketLegBudget),
                futBal -
                    uint128(ticketLegBudget) -
                    uint128(paidEth) -
                    uint128(insuranceCut)
            );
            if (insuranceCut != 0) {
                yieldAccumulator += insuranceCut;
            }
        }

        if (ticketLegBudget != 0) {
            _distributePoolBackedTickets(
                lvl,
                winningTraitsPacked,
                ticketLegBudget,
                randWord,
                5_000 // 50% ticket conversion — improves pool/ticket backing ratio
            );
        }
    }

    /// @notice Phase 2 of daily jackpot: distributes coin jackpot AND tickets to trait winners.
    /// @dev Called by advanceGame when dailyJackpotCoinTicketsPending is true.
    ///      Gas optimization: Separating coin+ticket distribution from ETH distribution
    ///      keeps each advanceGame call under the 15M gas block limit.
    ///
    ///      Traits are derived inline from randWord (main via isBonus=false, bonus via isBonus=true).
    ///      Uses stored values from Phase 1:
    ///      - rngWordCurrent: VRF entropy for deterministic winner selection
    ///      - dailyTicketBudgetsPacked: Packed ticket units, counter step, and carryover source offset
    ///
    /// @param randWord VRF entropy (must match rngWordCurrent from Phase 1).
    function payDailyJackpotCoinAndTickets(uint256 randWord) external {
        if (!dailyJackpotCoinTicketsPending) return;

        // Unpack stored values
        (
            uint8 counterStep,
            uint256 dailyEntries,
            uint256 carryoverEntries,
            uint8 carryoverSourceOffset
        ) = _unpackDailyTicketBudgets(dailyTicketBudgetsPacked);

        // Derive traits inline from randWord; main and bonus each roll a distinct hero.
        uint24 lvl = level;
        (
            uint32 mainTraitsPacked,
            uint32 bonusTraitsPacked
        ) = _rollWinningTraitsPair(randWord);

        // --- Coin Jackpot ---
        _runFlipJackpot(lvl, lvl, lvl + 1, lvl + 4, bonusTraitsPacked, randWord);

        // --- Ticket Distribution ---
        // Distribute daily tickets to current level trait winners (main traits)
        if (dailyEntries != 0) {
            _distributeTicketJackpot(
                lvl,
                lvl + 1,
                mainTraitsPacked,
                dailyEntries,
                EntropyLib.hash2(randWord, lvl),
                TICKET_JACKPOT_MAX_WINNERS,
                241,
                true // main board: solo quadrant took the ETH remainder
            );
        }

        uint8 counterCached = jackpotCounter;

        // Distribute carryover tickets: winners from source level, tickets at current level
        // (or lvl+1 on final day since current level is about to end). Uses bonus traits.
        if (carryoverEntries != 0) {
            uint24 sourceLevel = lvl + uint24(carryoverSourceOffset);
            bool isFinalDay = counterCached + counterStep >= JACKPOT_LEVEL_CAP;
            _distributeTicketJackpot(
                sourceLevel,
                isFinalDay ? lvl + 1 : lvl,
                bonusTraitsPacked,
                carryoverEntries,
                EntropyLib.hash2(randWord, sourceLevel),
                TICKET_JACKPOT_MAX_WINNERS,
                240,
                false // bonus board: no ETH distribution, no solo quadrant
            );
        }

        // Complete the daily jackpot cycle
        unchecked {
            jackpotCounter = counterCached + counterStep;
        }

        // Clear pending state
        dailyJackpotCoinTicketsPending = false;
        dailyTicketBudgetsPacked = 0;
    }

    /// @dev Execute the early-bird ticket jackpot from the unified future pool.
    ///      Routes through the shared ticket distributor so the budget→ticket
    ///      conversion (`_budgetToEntries`, the same 4-entries-per-ticket basis
    ///      every other jackpot path uses) and the winner cap match the daily and
    ///      purchase-phase jackpots: `cap = min(entries, 100)` gives every drawn
    ///      winner >=1 unit (replacing the fixed-100 split that floored sub-100-ticket
    ///      budgets to zero), with the exact base+remainder rotation keeping the award
    ///      fully backed. Winners drawn from `lvlTraitEntry[lvl]`, tickets queued at
    ///      `lvl` (= outer level + 1). The full 3% budget always moves future→next.
    function _runEarlyBirdTicketJackpot(uint24 lvl, uint256 rngWord) private {
        (uint128 nextBal, uint128 futureBal) = _getPrizePools();
        uint256 totalBudget = (uint256(futureBal) * 300) / 10_000; // 3%
        if (totalBudget == 0) return;

        (uint256 entries, ) = _budgetToEntries(totalBudget, lvl);
        if (entries != 0) {
            _distributeTicketJackpot(
                lvl,
                lvl,
                _rollWinningTraits(rngWord, true),
                entries,
                EntropyLib.hash2(rngWord, lvl),
                TICKET_JACKPOT_MAX_WINNERS,
                239,
                false // bonus board: no ETH distribution, no solo quadrant
            );
        }

        // Single net move on the packed slot: future funds the budget,
        // next backs the queued tickets. Nothing above reads the slot.
        _setPrizePools(
            nextBal + uint128(totalBudget),
            futureBal - uint128(totalBudget)
        );
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

    /// @dev Distributes pool-backed tickets to trait winners. The sole caller folds the budget's
    ///      full nextPrizePool credit into its own packed-slot write, so this helper only queues the
    ///      tickets that credit backs.
    /// @param ticketConversionBps Fraction of budget used for ticket calculation (10000 = 100%).
    ///        The caller moves the full budget to nextPrizePool regardless of this parameter.
    function _distributePoolBackedTickets(
        uint24 lvl,
        uint32 winningTraitsPacked,
        uint256 budget,
        uint256 randWord,
        uint16 ticketConversionBps
    ) private {
        // Distribute tickets to winners (may use reduced basis for backing ratio)
        // Tickets are queued at the current purchase level (`lvl`), matching the
        // nextPrizePool credit the caller applied that backs them.
        uint256 ticketBasis = (budget * ticketConversionBps) / 10_000;
        (uint256 entries, ) = _budgetToEntries(ticketBasis, lvl);
        if (entries != 0) {
            _distributeTicketJackpot(
                lvl,
                lvl,
                winningTraitsPacked,
                entries,
                EntropyLib.hash2(randWord, lvl),
                PURCHASE_PHASE_TICKET_MAX_WINNERS,
                242,
                true // main board: solo quadrant took the ETH remainder
            );
        }
    }

    /// @dev Distributes ticket rewards to winners drawn from winning trait pools.
    /// @param excludeSolo True on main-board legs, where the solo quadrant already
    ///        pays the day's headline ETH prize to a single winner: that quadrant is
    ///        dropped from the ticket draw so matching it means the big prize or
    ///        nothing, never a consolation trickle. `entropy` is the pre-splice value
    ///        the ETH leg fed `_soloAdjustedEntropy`, so the pick reproduces exactly.
    ///        False on bonus-board legs, which run no ETH distribution.
    function _distributeTicketJackpot(
        uint24 sourceLvl,
        uint24 queueLvl,
        uint32 winningTraitsPacked,
        uint256 entries,
        uint256 entropy,
        uint16 maxWinners,
        uint8 saltBase,
        bool excludeSolo
    ) private {
        if (entries == 0) return;

        // Awards are whole tickets only. Flooring the winner count to the whole tickets
        // the budget covers makes every winner worth at least one ticket, so no winner is
        // ever queued a bare quarter and none is credited zero.
        uint256 tickets = entries / ENTRIES_PER_TICKET;
        if (tickets == 0) return;

        uint8[4] memory traitIds = JackpotBucketLib.unpackWinningTraits(
            winningTraitsPacked
        );
        uint16 cap = maxWinners;
        if (tickets < cap) cap = uint16(tickets);

        (
            uint16[4] memory counts,
            uint8 activeCount,
            uint256[4] memory lens,
            address[4] memory deities
        ) = _computeBucketCounts(
                sourceLvl,
                traitIds,
                cap,
                entropy,
                excludeSolo
                    ? _pickSoloQuadrant(traitIds, entropy)
                    : _NO_QUADRANT_EXCLUDE
            );
        if (activeCount == 0) return;

        // One figure for the whole distribution: every winner in every bucket takes the
        // SAME number of whole tickets. The `tickets % cap` leftover is not queued — two
        // winners comparing their awards must never find one short, and the event feed
        // carries a single number per draw.
        _distributeTicketsToBuckets(
            sourceLvl,
            queueLvl,
            traitIds,
            counts,
            lens,
            deities,
            (tickets / cap) * ENTRIES_PER_TICKET,
            entropy,
            saltBase
        );
    }

    /// @dev Distributes tickets across all buckets. `lens`/`deities` carry the
    ///      per-trait bucket lengths and deity addresses read once by
    ///      _computeBucketCounts (stable for the whole distribution: nothing on
    ///      this path writes lvlTraitEntry or deityBySymbol).
    function _distributeTicketsToBuckets(
        uint24 sourceLvl,
        uint24 queueLvl,
        uint8[4] memory traitIds,
        uint16[4] memory counts,
        uint256[4] memory lens,
        address[4] memory deities,
        uint256 entriesEach,
        uint256 entropy,
        uint8 saltBase
    ) private {
        for (uint8 traitIdx; traitIdx < 4; ) {
            if (counts[traitIdx] != 0) {
                entropy = uint256(
                    keccak256(abi.encode(entropy, traitIdx, entriesEach))
                );
                _distributeTicketsToBucket(
                    sourceLvl,
                    queueLvl,
                    traitIds[traitIdx],
                    counts[traitIdx],
                    entropy,
                    uint8(saltBase + traitIdx),
                    entriesEach,
                    lens[traitIdx],
                    deities[traitIdx]
                );
            }
            unchecked {
                ++traitIdx;
            }
        }
    }

    /// @dev Distributes tickets to winners in a single bucket. Every winner receives
    ///      `entriesEach` — a whole number of tickets, identical across the whole draw.
    function _distributeTicketsToBucket(
        uint24 sourceLvl,
        uint24 queueLvl,
        uint8 traitId,
        uint16 count,
        uint256 entropy,
        uint8 salt,
        uint256 entriesEach,
        uint256 bucketLen,
        address deity
    ) private {
        (
            address[] memory winners,
            uint256[] memory ticketIndexes
        ) = _randTraitTicket(
                lvlTraitEntry[sourceLvl],
                entropy,
                traitId,
                uint8(count),
                salt,
                bucketLen,
                deity
            );

        uint256 len = winners.length;
        for (uint256 i; i < len; ) {
            address winner = winners[i];
            if (winner != address(0)) {
                _queueEntries(winner, queueLvl, uint32(entriesEach), true);
                // ticketCount carries the entries count awarded (price/4 units;
                // _budgetToEntries already returns entries). It is always a whole
                // multiple of ENTRIES_PER_TICKET.
                emit JackpotTicketWin(
                    winner,
                    queueLvl,
                    traitId,
                    uint32(entriesEach),
                    sourceLvl,
                    ticketIndexes[i],
                    false
                );
            }
            unchecked {
                ++i;
            }
        }
    }

    /// @dev Computes bucket winner counts for active trait buckets (including virtual deity entries).
    ///      Also returns each trait's bucket length and deity address so the
    ///      distribution loop reuses them instead of re-reading storage.
    /// @param excludeIdx Bucket dropped from the draw, or `_NO_QUADRANT_EXCLUDE`.
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
            uint256 len = lvlTraitEntry[lvl][trait].length;
            lens[i] = len;
            uint8 fullSymId = (trait >> 6) * 8 + (trait & 0x07);
            address deity;
            if (fullSymId < 32) {
                deity = deityBySymbol[fullSymId];
                deities[i] = deity;
            }
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
        if (excludeIdx < 4 && (activeMask & uint8(1 << excludeIdx)) != 0) {
            uint8 kept = activeMask & ~uint8(1 << excludeIdx);
            if (kept != 0) {
                activeMask = kept;
                unchecked {
                    --activeCount;
                }
            }
        }

        if (activeCount == 0) return (counts, 0, lens, deities);

        uint16 baseCount = maxWinners / activeCount;
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
                    counts[idx] += 1;
                    unchecked {
                        --remainder;
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
    ///      When any winning trait has color==7 (gold tier), returns a uniformly-random
    ///      gold quadrant via bits 4+ of `entropy` (disjoint from the bucket-rotation
    ///      low 2 bits at `entropy & 3`). Otherwise returns the existing rotation index
    ///      `uint8((3 - (entropy & 3)) & 3)` matching `JackpotBucketLib.soloBucketIndex`.
    /// @param traits The 4 winning trait IDs (each [QQ][CCC][SSS] packed: quadrant 2 bits,
    ///        color 3 bits, symbol 3 bits).
    /// @param entropy VRF-derived entropy. Bits 0-1 drive bucket rotation; bits 4+ drive
    ///        gold tie-break (bits 2-3 unused by either path).
    /// @return Quadrant index 0-3 to receive the solo bucket assignment.
    function _pickSoloQuadrant(uint8[4] memory traits, uint256 entropy) internal pure returns (uint8) {
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
    /// @dev Delegatecall-only entry, invoked by the foil gold claim
    ///      (DegenerusGameFoilPackModule._settleGoldenTicket) so both routes share ONE
    ///      grand definition and can never drift. Runs in the Game's storage context:
    ///      the guard rejects a direct call on the deployed module, and no facade stub
    ///      exposes the selector, so the foil gold claim is the only reachable caller.
    ///      The armed-board state is untouched — a foil grand neither arms, resolves,
    ///      nor consumes an armed board, so a pending arm still resolves on its own
    ///      next draw.
    /// @param winner The foil buyer whose pack rolled the two all-gold tickets.
    /// @param lvl The pack's cycle level (the flip-credit rate's basis).
    /// @param golds The pack's total gold quadrants — 8, 12 or 16, since the grand
    ///        fires on two, three or four all-gold tickets. Stamped as the event's
    ///        goldCount; always above the board route's 0-4 range, so the two routes
    ///        never read alike even on the count alone.
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

    /// @dev Unified ETH distribution across trait buckets. All buckets are paid in a single
    ///      call. The winner total is bounded by the bucket geometry: base [25,15,8,1] at the
    ///      DAILY_JACKPOT_SCALE_MAX_BPS ceiling gives 159 + 95 + 50 + 1 = 305, and each bucket
    ///      is independently clamped to MAX_BUCKET_WINNERS in _processBucket.
    ///
    ///      JACKPOT PHASE vs PURCHASE/TERMINAL:
    ///      - Jackpot phase (isJackpotPhase=true): solo bucket routes its winner through the whale-pass handler (75% ETH / 25% half-passes).
    ///      - Purchase/terminal (isJackpotPhase=false): All buckets paid uniformly.
    ///
    /// @param lvl The level whose winners are being paid.
    /// @param ethPool Total ETH to distribute.
    /// @param entropy VRF-derived random word for winner selection.
    /// @param traitIds The 4 winning trait IDs.
    /// @param shareBps Basis-point share for each of the 4 buckets.
    /// @param bucketCounts Number of holders in each trait bucket.
    /// @param isJackpotPhase True during jackpot phase (solo bucket gets whale pass).
    /// @param armGold True when the main board rolled 4 golds — the solo bucket
    ///        winner becomes the armed golden-ticket candidate for the next draw.
    /// @return paidEth Total ETH actually paid out in this call.
    function _processDailyEth(
        uint24 lvl,
        uint256 ethPool,
        uint256 entropy,
        uint8[4] memory traitIds,
        uint16[4] memory shareBps,
        uint16[4] memory bucketCounts,
        bool isJackpotPhase,
        bool armGold,
        uint256 unit
    ) private returns (uint256 paidEth) {
        if (ethPool == 0) {
            return 0;
        }

        uint8 remainderIdx = JackpotBucketLib.soloBucketIndex(entropy);
        uint256[4] memory shares = JackpotBucketLib.bucketShares(
            ethPool, shareBps, bucketCounts, remainderIdx, unit
        );

        uint8[4] memory order = JackpotBucketLib.bucketOrderLargestFirst(
            bucketCounts
        );

        uint256 entropyState = entropy;
        uint256 liabilityDelta;

        for (uint8 j; j < 4; ) {
            uint8 traitIdx = order[j];

            uint16 count = bucketCounts[traitIdx];
            uint256 share = shares[traitIdx];
            if (count == 0 || share == 0) {
                unchecked {
                    ++j;
                }
                continue;
            }

            entropyState = uint256(
                keccak256(abi.encode(entropyState, traitIdx, share))
            );

            uint256 paidDelta;
            uint256 claimDelta;
            (paidDelta, claimDelta, entropyState) = _processBucket(
                lvl,
                traitIds[traitIdx],
                traitIdx,
                count,
                share,
                entropyState,
                isJackpotPhase && traitIdx == remainderIdx,
                armGold
            );
            paidEth += paidDelta;
            liabilityDelta += claimDelta;
            unchecked {
                ++j;
            }
        }

        if (liabilityDelta != 0) {
            claimablePool += uint128(liabilityDelta);
        }
    }

    /// @dev Resolves and pays one trait bucket. Selects up to MAX_BUCKET_WINNERS
    ///      ticket holders for the bucket and credits each winner. The solo path
    ///      (isSolo, jackpot phase only) routes the single winner through the
    ///      whale-pass handler; every other bucket pays 100% ETH.
    /// @return paidDelta ETH value paid out for this bucket.
    /// @return claimDelta Claimable-liability added for this bucket.
    /// @return newEntropy Updated entropy after winner selection.
    function _processBucket(
        uint24 lvl,
        uint8 traitId,
        uint8 traitIdx,
        uint16 count,
        uint256 share,
        uint256 entropy,
        bool isSolo,
        bool armGold
    ) private returns (uint256 paidDelta, uint256 claimDelta, uint256 newEntropy) {
        newEntropy = entropy;

        uint16 totalCount = count;
        if (totalCount > MAX_BUCKET_WINNERS) totalCount = MAX_BUCKET_WINNERS;

        (
            address[] memory winners,
            uint256[] memory ticketIndexes
        ) = _randTraitTicket(
                lvlTraitEntry[lvl],
                newEntropy,
                traitId,
                uint8(totalCount),
                uint8(200 + traitIdx)
            );
        if (winners.length == 0) return (0, 0, newEntropy);

        uint256 perWinner = share / totalCount;
        if (perWinner == 0) return (0, 0, newEntropy);

        if (isSolo) {
            // Solo bucket (jackpot phase): 75% ETH + 25% whale passes
            address w = winners[0];
            if (w != address(0)) {
                (claimDelta, paidDelta, newEntropy) = _handleSoloBucketWinner(
                    w, lvl, traitId, ticketIndexes[0],
                    perWinner, newEntropy, armGold
                );
            }
        } else {
            // Normal bucket: 100% ETH
            (paidDelta, claimDelta) = _payNormalBucket(
                winners, ticketIndexes, perWinner, lvl, traitId
            );
        }
    }

    // =========================================================================
    // Internal Helpers — Winner Resolution
    // =========================================================================

    /// @dev Thin wrapper called from _processDailyEth to avoid stack-too-deep.
    ///      Calls _processSoloBucketWinner, emits specialized events, and returns
    ///      only the three values the outer loop needs.
    function _handleSoloBucketWinner(
        address w,
        uint24 lvl,
        uint8 traitId,
        uint256 ticketIndex,
        uint256 perWinner,
        uint256 entropy,
        bool armGold
    )
        private
        returns (uint256 claimDelta, uint256 paidDelta, uint256 newEntropy)
    {
        (
            uint256 claimableDelta,
            uint256 paid,
            uint256 wpSpent,
            uint256 newEnt
        ) = _processSoloBucketWinner(w, perWinner, entropy);
        newEntropy = newEnt;
        claimDelta = claimableDelta;
        if (paid != 0) {
            emit JackpotEthWin(
                w,
                lvl,
                traitId,
                paid,
                ticketIndex
            );
            paidDelta += paid;
        }
        if (wpSpent != 0) {
            emit JackpotWhalePassWin(w, lvl, wpSpent / HALF_WHALE_PASS_PRICE);
            paidDelta += wpSpent;
        }
        if (armGold) {
            _armGoldenTicket(w, lvl, traitId);
        }
    }

    /// @dev Pays normal (non-solo) bucket winners. Extracted to avoid stack-too-deep in _processDailyEth.
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

    /// @dev Processes solo bucket winner: 75% ETH, 25% as whale passes (only if
    ///      the 25% covers at least one half-pass; otherwise 100% ETH).
    /// @return claimableDelta Amount to add to claimablePool.
    /// @return ethPaid Total ETH value credited.
    /// @return whalePassSpent Amount moved to futurePrizePool from whale pass conversion.
    /// @return newEntropy Updated entropy.
    function _processSoloBucketWinner(
        address winner,
        uint256 perWinner,
        uint256 entropy
    )
        private
        returns (
            uint256 claimableDelta,
            uint256 ethPaid,
            uint256 whalePassSpent,
            uint256 newEntropy
        )
    {
        // 75/25 split: whale pass only if 25% covers at least one half-pass
        uint256 quarterAmount = perWinner >> 2; // perWinner / 4
        uint256 whalePassCount = quarterAmount / HALF_WHALE_PASS_PRICE;
        newEntropy = entropy;

        if (whalePassCount != 0) {
            uint256 whalePassCost = whalePassCount * HALF_WHALE_PASS_PRICE;
            uint256 ethAmount = perWinner - whalePassCost;

            _creditClaimable(winner, ethAmount);
            claimableDelta = ethAmount;
            ethPaid = ethAmount;

            whalePassClaims[winner] += whalePassCount;
            _addFuturePrizePool(whalePassCost);
            whalePassSpent = whalePassCost;
        } else {
            // 25% too small for a whale pass — pay full amount as ETH
            _creditClaimable(winner, perWinner);
            claimableDelta = perWinner;
            ethPaid = perWinner;
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
            // three prize pools plus the segregated yield accumulator — all
            // written only by the advance path. Claimable is player money
            // already owed, and the pending accumulators move with in-window
            // purchases, so neither may size a VRF-derived award.
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

    /// @dev Replaces the winning quadrant's trait with a hero-symbol override sampled by
    ///      `_rollHeroSymbol` from the prior day's settled wager pool. Applied to all jackpot
    ///      paths (purchase phase + jackpot phase). Reads `dailyHeroWagers[dailyIdx]`:
    ///      `dailyIdx` is written only at `_unlockRng` (AdvanceModule), so during jackpot
    ///      processing it is frozen at the previous day's index — every consumer in a single
    ///      jackpot resolution therefore reads the same wager pool. Bets placed on day D
    ///      write to `dailyHeroWagers[D]`; day D+1's jackpot reads slot[D] via
    ///      `dailyIdx == D` (set by day D's `_unlockRng`).
    ///
    ///      `heroEntropy` is the raw VRF entropy word for the day. This applies the main draw's
    ///      hero; the bonus draw rolls a SEPARATE hero (main slot excluded) in
    ///      `_rollWinningTraitsPair`, so the two heroes never coincide. The symbol roll
    ///      consumes `keccak256(abi.encode(heroEntropy, day))`; colors are untouched by
    ///      the hero — each quadrant keeps its base-rolled color.
    function _applyHeroOverride(
        uint8[4] memory w,
        uint256 heroEntropy
    ) private view {
        (
            bool hasHeroWinner,
            uint8 heroQuadrant,
            uint8 heroSymbol
        ) = _rollHeroSymbol(
                dailyIdx,
                heroEntropy,
                _NO_HERO_EXCLUDE,
                // Terminal-only path (sole _applyHeroOverride caller): the gold
                // rush never arms, resolves, or bans on a terminal board.
                _NO_QUADRANT_BAN
            );
        _applyHeroResult(w, hasHeroWinner, heroQuadrant, heroSymbol);
    }

    /// @dev Applies a resolved hero (quadrant, symbol) to a trait set: the hero symbol
    ///      replaces the winning quadrant's symbol bits only. The quadrant keeps its
    ///      base-rolled color, so all four colors stay independent 1/8 draws
    ///      regardless of where (or whether) a hero lands.
    function _applyHeroResult(
        uint8[4] memory w,
        bool hasHeroWinner,
        uint8 heroQuadrant,
        uint8 heroSymbol
    ) private pure {
        if (!hasHeroWinner) return;
        w[heroQuadrant] = (w[heroQuadrant] & 0xF8) | heroSymbol;
    }

    /// @dev Samples the day's hero `(quadrant, symbol)` via a weighted random roll across
    ///      the 32 packed slots of `dailyHeroWagers[day]`. Pass 1 SLOADs the 4 packed
    ///      quadrants once, decodes 32 uint32 amounts, accumulates the total, and tracks
    ///      the largest-amount slot (first-seen on ties to match the scan order).
    ///      Pass 2 walks the cached weights with a cumulative cursor against
    ///      `pick = uint64(uint256(keccak256(abi.encode(entropy, day))) % effectiveTotal)`
    ///      and applies a `leaderBonus = maxAmount / 2` add at the largest-amount slot —
    ///      effective ×1.5 weight on the leader, no min-wager floor on any other slot.
    ///      Returns `(false, 0, 0)` when no slot has any wagers.
    ///
    ///      `excludeIdx` zeroes one slot's weight before the roll so the result can
    ///      never land on it and the leader is recomputed over the remaining slots:
    ///      the bonus draw passes the main hero's packed slot `(quadrant << 3) |
    ///      symbol` to force a distinct hero. Pass `_NO_HERO_EXCLUDE` (>= 32, matching
    ///      no real slot) for an unconstrained roll; when zeroing empties the pool the
    ///      result is `(false, 0, 0)` and the caller applies no hero (a pure-VRF set).
    ///
    ///      `banQuadrant` zeroes an entire quadrant's 8 slots the same way — main
    ///      rolls pass `_goldenTicketBanQuadrant()` so on a golden-ticket resolve day the
    ///      armed quadrant keeps its base-rolled symbol (hero wagers can neither
    ///      boost nor block the grand match). Pass `_NO_QUADRANT_BAN` otherwise.
    function _rollHeroSymbol(
        uint24 day,
        uint256 entropy,
        uint8 excludeIdx,
        uint8 banQuadrant
    )
        private
        view
        returns (bool hasWinner, uint8 winQuadrant, uint8 winSymbol)
    {
        uint32[32] memory weights;
        uint64 total;
        uint32 maxAmount;
        uint8 leaderIdx;

        for (uint8 q; q < 4; ) {
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
                uint32 amount = idx == excludeIdx
                    ? 0
                    : uint32((packed >> (uint256(s) * 32)) & 0xFFFFFFFF);
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
            uint256(keccak256(abi.encode(entropy, day))) % effectiveTotal
        );

        uint64 cumulative;
        for (uint8 idx; idx < 32; ) {
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

    /// @dev Virtual deity entry count for a trait bucket of size `len` (zero
    ///      when no deity holds the trait's symbol):
    ///        Gold tier (color == 7): flat 1 virtual entry.
    ///        Common tier (color in [0..6]): floor(2% of bucket), minimum 2.
    function _deityVirtualCount(
        uint8 trait,
        uint256 len,
        address deity
    ) private pure returns (uint256 virtualCount) {
        if (deity != address(0)) {
            if (((trait >> 3) & 7) == 7) {
                virtualCount = 1;
            } else {
                virtualCount = len / 50;
                if (virtualCount < 2) virtualCount = 2;
            }
        }
    }

    /// @dev Selects random winners from a trait's ticket pool, returning both addresses and indices.
    ///      Reads the bucket length and deity itself; distribution paths that
    ///      already hold them use the precomputed overload directly.
    function _randTraitTicket(
        address[][256] storage lvlTraitEntry_,
        uint256 randomWord,
        uint8 trait,
        uint8 numWinners,
        uint8 salt
    )
        private
        view
        returns (address[] memory winners, uint256[] memory ticketIndexes)
    {
        uint256 len = lvlTraitEntry_[trait].length;

        // traitId layout: (quadrant << 6) | (color << 3) | symIdx
        // fullSymId = quadrant * 8 + symIdx
        uint8 fullSymId = (trait >> 6) * 8 + (trait & 0x07);
        address deity;
        if (fullSymId < 32) {
            deity = deityBySymbol[fullSymId];
        }

        return
            _randTraitTicket(
                lvlTraitEntry_,
                randomWord,
                trait,
                numWinners,
                salt,
                len,
                deity
            );
    }

    /// @dev Winner-selection core with caller-supplied bucket length and deity.
    ///      Winners beyond the real bucket land on the deity's virtual entries.
    function _randTraitTicket(
        address[][256] storage lvlTraitEntry_,
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
        address[] storage holders = lvlTraitEntry_[trait];
        uint256 virtualCount = _deityVirtualCount(trait, len, deity);

        uint256 effectiveLen = len + virtualCount;
        if (effectiveLen == 0 || numWinners == 0) {
            return (new address[](0), new uint256[](0));
        }

        winners = new address[](numWinners);
        ticketIndexes = new uint256[](numWinners);
        for (uint256 i; i < numWinners; ) {
            uint256 idx = uint256(
                keccak256(abi.encode(randomWord, trait, salt, i))
            ) % effectiveLen;
            if (idx < len) {
                winners[i] = holders[idx];
                ticketIndexes[i] = idx;
            } else {
                winners[i] = deity;
                ticketIndexes[i] = type(uint256).max;
            }
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Pays daily FLIP jackpot to random ticket holders.
    /// @dev Runs every day in its own transaction. Awards 0.25% of prize pool target in FLIP.
    ///      75% goes to near-future trait-matched winners in [minLevel, maxLevel].
    ///      25% goes to far-future ticketQueue holders ([lvl+5, lvl+99]).
    /// @param lvl Current level.
    /// @param randWord VRF entropy for winner selection.
    /// @param minLevel Minimum target level for near-future coin distribution (inclusive).
    /// @param maxLevel Maximum target level for near-future coin distribution (inclusive).
    function payDailyFlipJackpot(uint24 lvl, uint256 randWord, uint24 minLevel, uint24 maxLevel) external {
        uint32 bonusTraitsPacked = _rollWinningTraits(randWord, true);
        _runFlipJackpot(lvl, level, minLevel, maxLevel, bonusTraitsPacked, randWord);
    }

    /// @dev Daily FLIP jackpot core: 25% of the budget to far-future
    ///      ticketQueue holders, 75% to near-future trait-matched winners in
    ///      [minLevel, maxLevel].
    /// @param lvl Level keying the prize pool snapshot for the budget.
    /// @param currLevel Current game level (storage `level` at call time), used
    ///        for FLIP pricing.
    function _runFlipJackpot(
        uint24 lvl,
        uint24 currLevel,
        uint24 minLevel,
        uint24 maxLevel,
        uint32 bonusTraitsPacked,
        uint256 randWord
    ) private {
        uint256 coinBudget = _calcDailyCoinBudget(lvl, currLevel);
        if (coinBudget == 0) return;

        // Split: 25% far-future, 75% near-future
        uint256 farBudget = (coinBudget * FAR_FUTURE_FLIP_BPS) / 10_000;
        _awardFarFutureCoinJackpot(lvl, farBudget, randWord);

        uint256 nearBudget = coinBudget - farBudget;
        if (nearBudget != 0) {
            _awardDailyCoinToTraitWinners(
                minLevel,
                maxLevel,
                bonusTraitsPacked,
                nearBudget,
                randWord
            );
        }
    }

    /// @dev Emit DailyWinningTraits without running any distribution.
    ///      Used at purchaseLevel==1 where payDailyJackpot is skipped and two coin
    ///      jackpots replace the ETH jackpot. First coin call (the "main") uses
    ///      bonus-derived traits from randWord. Second coin call uses traits from
    ///      a salted randWord (keccak256(randWord, BONUS_TRAITS_TAG)).
    /// @param bonusTargetLevel Target level for the first (main-equivalent) coin distribution.
    function emitDailyWinningTraits(uint24, uint256 randWord, uint24 bonusTargetLevel) external {
        if (msg.sender != ContractAddresses.GAME) revert OnlyGame();
        // The sealed day, matching payDailyJackpot: dailyIdx + 1, never the wall clock.
        uint24 questDay = dailyIdx + 1;
        uint32 mainTraitsPacked = _rollWinningTraits(randWord, true);
        uint256 saltedRng = EntropyLib.hash2(randWord, uint256(BONUS_TRAITS_TAG));
        uint32 bonusTraitsPacked = _rollWinningTraits(saltedRng, true);
        // Level-1 path: persist the two day-1 sets (level 1) so day-1 foil packs
        // can claim against the sets the day-1 coin jackpots actually used.
        dailyFoilDraw[questDay] = _packFoilDraw(mainTraitsPacked, bonusTraitsPacked, 1);
        emit DailyWinningTraits(questDay, mainTraitsPacked, bonusTraitsPacked, bonusTargetLevel);
    }

    /// @dev Awards FLIP to per-pull random ticket holders across [minLevel, maxLevel].
    ///      Each pull samples its own random level via keccak256(randomWord, FLIP_LEVEL_TAG, i)
    ///      and rotates trait deterministically via i % 4. The budget is split into whole
    ///      100-FLIP units and the pull count floored to the units available, so every
    ///      pull is worth at least one unit and every pull is worth the SAME; empty
    ///      (lvl', trait_i) buckets silently skip and their share is simply not minted.
    ///      The uneven-division leftover and the sub-100-FLIP budget remainder evaporate.
    ///      Per-trait deity addresses are cached at loop entry; the holder-index keccak is
    ///      keccak256(randomWord, trait_i, lvlPrime, i) so two pulls at the same (trait, i)
    ///      but different sampled levels do not collapse to the same holder index.
    function _awardDailyCoinToTraitWinners(
        uint24 minLevel,
        uint24 maxLevel,
        uint32 winningTraitsPacked,
        uint256 coinBudget,
        uint256 randomWord
    ) private {
        if (coinBudget == 0) return;
        // Flooring the pull count to the whole 100-FLIP units the budget covers makes
        // every pull worth at least one unit, so the split is plain integer arithmetic
        // and no winner is ever credited zero.
        uint256 units = coinBudget / FlipRoundLib.FLIP_ROUND_UNIT;
        uint256 cap = units < DAILY_COIN_MAX_WINNERS
            ? units
            : DAILY_COIN_MAX_WINNERS;
        if (cap == 0) return;

        uint8[4] memory traitIds = JackpotBucketLib.unpackWinningTraits(
            winningTraitsPacked
        );

        // Per-trait deity cache: deityBySymbol is level-independent, so one read per trait
        // serves all 50 pulls of that trait.
        address[4] memory deityCache;
        for (uint8 t; t < 4; ) {
            uint8 trait = traitIds[t];
            uint8 fullSymId = (trait >> 6) * 8 + (trait & 0x07);
            if (fullSymId < 32) {
                deityCache[t] = deityBySymbol[fullSymId];
            }
            unchecked { ++t; }
        }

        // Every paid pull carries the SAME amount. The `units % cap` leftover is simply
        // not minted: an equal share is worth more than a fully-spent budget, because no
        // winner can hold their pull against a neighbour's and find it short. The
        // discarded tail is under one unit per pull.
        uint256 amount = (units / cap) * FlipRoundLib.FLIP_ROUND_UNIT;
        uint24 range = maxLevel - minLevel + 1;

        // Winners accumulate into one creditFlipBatch call after the loop
        // (per-item semantics match creditFlip; empty slots are skipped).
        address[] memory batchPlayers = new address[](cap);
        uint256[] memory batchAmounts = new uint256[](cap);
        bool anyWinner;

        for (uint256 i; i < cap; ) {
            uint8 traitIdx = uint8(i % 4);
            uint8 trait_i = traitIds[traitIdx];

            uint24 lvlPrime = minLevel + uint24(uint256(keccak256(
                abi.encode(randomWord, FLIP_LEVEL_TAG, i)
            )) % range);

            address[] storage holders = lvlTraitEntry[lvlPrime][trait_i];
            uint256 len = holders.length;
            address deity = deityCache[traitIdx];
            uint256 effectiveLen = len + _deityVirtualCount(trait_i, len, deity);
            if (effectiveLen == 0) {
                unchecked {
                    ++i;
                }
                continue;
            }

            uint256 idx = uint256(keccak256(
                abi.encode(randomWord, trait_i, lvlPrime, i)
            )) % effectiveLen;
            address winner;
            uint256 ticketIdx;
            if (idx < len) {
                winner = holders[idx];
                ticketIdx = idx;
            } else {
                winner = deity;
                ticketIdx = type(uint256).max;
            }

            if (winner != address(0)) {
                emit JackpotFlipWin(
                    winner,
                    lvlPrime,
                    trait_i,
                    amount,
                    ticketIdx
                );
                batchPlayers[i] = winner;
                batchAmounts[i] = amount;
                anyWinner = true;
            }

            unchecked {
                ++i;
            }
        }

        if (anyWinner) {
            coinflip.creditFlipBatch(batchPlayers, batchAmounts);
        }
    }

    /// @dev Awards 25% of the FLIP coin budget to random ticket holders on far-future levels.
    ///      Samples up to 10 random levels in [lvl+5, lvl+99], picks 1 winner per level from
    ///      that level's ticketQueue (traits not yet assigned), and splits the budget into
    ///      whole 100-FLIP units across a prefix of them, an equal share each.
    function _awardFarFutureCoinJackpot(
        uint24 lvl,
        uint256 farBudget,
        uint256 rngWord
    ) private {
        if (farBudget == 0) return;

        uint256 entropy = uint256(
            keccak256(abi.encode(rngWord, lvl, FAR_FUTURE_FLIP_TAG))
        );

        // First pass: find up to FAR_FUTURE_FLIP_SAMPLES winners from ticketQueue
        address[10] memory winners;
        uint24[10] memory winnerLevels;
        uint8 found;

        for (uint8 s; s < FAR_FUTURE_FLIP_SAMPLES; ) {
            entropy = EntropyLib.hash2(entropy, s);

            // Pick a random level in [lvl+5, lvl+99]
            uint24 candidate = lvl + 5 + uint24(entropy % 95);

            address[] storage queue = ticketQueue[_tqFarFutureKey(candidate)];
            uint256 len = queue.length;

            if (len != 0) {
                address winner = queue[(entropy >> 32) % len];
                if (winner != address(0)) {
                    winners[found] = winner;
                    winnerLevels[found] = candidate;
                    unchecked {
                        ++found;
                    }
                }
            }

            unchecked {
                ++s;
            }
        }

        if (found == 0) return;

        // Split into whole 100-FLIP units and pay a prefix of the sampled winners, one
        // unit minimum each. `winners[]` is already ordered by its own VRF draw, so
        // truncating to `payCount` introduces no new choice. Every paid winner receives
        // the SAME amount; the `units % payCount` leftover and the sub-100-FLIP budget
        // remainder both evaporate.
        uint256 units = farBudget / FlipRoundLib.FLIP_ROUND_UNIT;
        uint256 payCount = units < found ? units : found;
        if (payCount == 0) return;

        uint256 amount = (units / payCount) * FlipRoundLib.FLIP_ROUND_UNIT;

        address[] memory batchPlayers = new address[](payCount);
        uint256[] memory batchAmounts = new uint256[](payCount);

        for (uint256 i; i < payCount; ) {
            emit FarFutureFlipJackpotWinner(
                winners[i],
                lvl,
                winnerLevels[i],
                amount
            );

            batchPlayers[i] = winners[i];
            batchAmounts[i] = amount;

            unchecked {
                ++i;
            }
        }

        coinflip.creditFlipBatch(batchPlayers, batchAmounts);
    }

    /// @dev Roll winning traits with hero symbol override.
    ///      All paths use fully random traits (6 bits per quadrant).
    ///      Hero override replaces the winning quadrant's trait if a top hero symbol exists.
    /// @param randWord VRF entropy.
    /// @param isBonus When true, applies keccak256 domain separation for independent bonus traits.
    function _rollWinningTraits(
        uint256 randWord,
        bool isBonus
    ) private view returns (uint32 packed) {
        if (!isBonus) {
            // Main draw — unchanged: base + hero both off the unsalted word.
            uint8[4] memory mTraits = JackpotBucketLib.getRandomTraits(randWord);
            _applyHeroOverride(mTraits, randWord);
            return JackpotBucketLib.packWinningTraits(mTraits);
        }
        // Bonus draw — base off the salted word, with its own hero rolled off the
        // salted word excluding the main hero's slot (main hero off the unsalted
        // word, matching _rollWinningTraitsPair so both producers agree).
        uint256 r = EntropyLib.hash2(randWord, uint256(BONUS_TRAITS_TAG));
        uint8[4] memory traits = JackpotBucketLib.getRandomTraits(r);
        // dailyIdx is frozen for this whole view (no writes/external calls between the reads),
        // so cache it once for both hero rolls and the ban-quadrant derivation.
        uint24 dIdx = dailyIdx;
        (bool mHas, uint8 mQ, uint8 mS) = _rollHeroSymbol(
            dIdx,
            randWord,
            _NO_HERO_EXCLUDE,
            _goldenTicketBanQuadrant(goldenTicket, dIdx)
        );
        uint8 excl = mHas ? ((mQ << 3) | mS) : _NO_HERO_EXCLUDE;
        (bool bHas, uint8 bQ, uint8 bS) = _rollHeroSymbol(
            dIdx,
            r,
            excl,
            _NO_QUADRANT_BAN
        );
        _applyHeroResult(traits, bHas, bQ, bS);
        packed = JackpotBucketLib.packWinningTraits(traits);
    }

    /// @dev Rolls main and bonus winning traits from one VRF word. The main draw
    ///      rolls its hero off the unsalted word; the bonus draw rolls its OWN hero
    ///      off the salted word with the main hero's slot excluded, so the two
    ///      heroes never coincide (an empty post-exclusion pool yields no bonus
    ///      hero). Base traits derive from each roll's own word (main: randWord;
    ///      bonus: keccak-salted with BONUS_TRAITS_TAG); heroes override symbol
    ///      bits only, leaving every quadrant's base-rolled color intact.
    function _rollWinningTraitsPair(
        uint256 randWord
    ) private view returns (uint32 mainPacked, uint32 bonusPacked) {
        // dailyIdx is frozen for this whole view (no writes/external calls between the reads),
        // so cache it once for both hero rolls and the ban-quadrant derivation.
        uint24 dIdx = dailyIdx;
        (
            bool hasHeroWinner,
            uint8 heroQuadrant,
            uint8 heroSymbol
        ) = _rollHeroSymbol(
                dIdx,
                randWord,
                _NO_HERO_EXCLUDE,
                _goldenTicketBanQuadrant(goldenTicket, dIdx)
            );

        uint8[4] memory traits = JackpotBucketLib.getRandomTraits(randWord);
        _applyHeroResult(traits, hasHeroWinner, heroQuadrant, heroSymbol);
        mainPacked = JackpotBucketLib.packWinningTraits(traits);

        uint256 rBonus = EntropyLib.hash2(randWord, uint256(BONUS_TRAITS_TAG));
        traits = JackpotBucketLib.getRandomTraits(rBonus);
        // The bonus draw rolls its own hero off the salted word, excluding the
        // main hero's slot so the two heroes can never coincide. An empty pool
        // (the main had no hero) yields no bonus hero either.
        uint8 excl = hasHeroWinner
            ? ((heroQuadrant << 3) | heroSymbol)
            : _NO_HERO_EXCLUDE;
        (bool bHas, uint8 bQ, uint8 bS) = _rollHeroSymbol(
            dIdx,
            rBonus,
            excl,
            _NO_QUADRANT_BAN
        );
        _applyHeroResult(traits, bHas, bQ, bS);
        bonusPacked = JackpotBucketLib.packWinningTraits(traits);
    }

    /// @dev Emits the daily winning-traits event with the bonus target level
    ///      derived from the day's VRF word (lvl+1 .. lvl+4).
    function _emitDailyWinningTraits(
        uint24 questDay,
        uint32 mainTraitsPacked,
        uint32 bonusTraitsPacked,
        uint256 randWord,
        uint24 lvl
    ) private {
        uint256 coinEntropy = uint256(
            keccak256(abi.encode(randWord, lvl, FLIP_JACKPOT_TAG))
        );
        uint24 bonusTargetLevel = lvl + 1 + uint24(coinEntropy % 4);
        // Persist the day's two winning sets + cycle level for the foil claim to
        // read (foil == jackpot by construction). One write per day.
        dailyFoilDraw[questDay] = _packFoilDraw(
            mainTraitsPacked,
            bonusTraitsPacked,
            lvl
        );
        emit DailyWinningTraits(
            questDay,
            mainTraitsPacked,
            bonusTraitsPacked,
            bonusTargetLevel
        );
    }

    /// @dev Calculate 0.25% of prize pool target in FLIP.
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

    function _packDailyTicketBudgets(
        uint8 counterStep,
        uint256 dailyEntries,
        uint256 carryoverEntries,
        uint8 carryoverSourceOffset
    ) private pure returns (uint256) {
        return
            uint256(counterStep) |
            (dailyEntries << 8) |
            (carryoverEntries << 72) |
            (uint256(carryoverSourceOffset) << 136);
    }

    function _unpackDailyTicketBudgets(
        uint256 packed
    )
        private
        pure
        returns (
            uint8 counterStep,
            uint256 dailyEntries,
            uint256 carryoverEntries,
            uint8 carryoverSourceOffset
        )
    {
        counterStep = uint8(packed);
        dailyEntries = uint64(packed >> 8);
        carryoverEntries = uint64(packed >> 72);
        carryoverSourceOffset = uint8(packed >> 136);
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
        uint24 ticketFloorLvl = compressedJackpotFlag >= 2 ? lvl + 1 : lvl;

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
                    (rngWord, cd) = _awardJackpotTickets(
                        winner,
                        lootboxPortion,
                        ticketFloorLvl,
                        rngWord
                    );
                    claimableDelta += cd;
                } else {
                    // Large lootbox: defer to claim (whale pass equivalent). The sub-half-pass
                    // remainder is folded into claimableDelta so the caller's memFuture debit
                    // and claimablePool credit both move it out of futurePool exactly once.
                    claimableDelta += _queueWhalePassClaimCore(winner, lootboxPortion);
                    emit JackpotWhalePassWin(
                        winner,
                        lvl,
                        lootboxPortion / HALF_WHALE_PASS_PRICE
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
                (rngWord, cd) = _awardJackpotTickets(
                    winner,
                    amount,
                    ticketFloorLvl,
                    rngWord
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
     * @dev Awards tickets using two-tier system:
     *      Small (0.5-5 ETH): Split in half, 2 probabilistic rolls
     *      Large (> 5 ETH): Whale pass equivalent (100-ticket chunks)
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
                minTargetLevel,
                amount / HALF_WHALE_PASS_PRICE
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
     *      Entropy bit allocation in the per-roll keccak word `entropy`
     *      (evolved via EntropyLib.hash2 on entry, so every bit — including
     *      the low bits read below — is full-diffusion keccak output):
     *        bits[0..12]     path/level selection — `entropy % 100` range roll,
     *                        `(entropy / 100) % 4` near offset,
     *                        `(entropy / 100) % 46` far offset
     *        bits[96..127]   jackpotTicketRoundUp % 100 — Bernoulli whole-ticket
     *                        collapse sub-roll (uint32 window, modulo bias ~2e-8)
     *      The two consumption windows are separated by 80+ bits of the same
     *      256-bit keccak word, so the round-up sub-roll is statistically
     *      independent of the path/level selection.
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
        // Saturate at the uint32 ceiling instead of wrapping: an award above ~42.9M scaled
        // whole-tickets in a single roll is only reachable at economically-impossible prize
        // sizes; a graceful cap avoids a silent modular wrap to a tiny count.
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
