// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/*
 * TERMS OF INTERACTION — submitting a transaction to this contract accepts them.
 *
 * THIS IS GAMBLING. Outcomes are decided by chance. You can lose everything you put in
 * simply by being unlucky. That is the software working exactly as intended. Do not
 * commit funds you are not prepared to lose entirely.
 *
 * The deployed bytecode is the entire agreement, and controls over every comment, name,
 * document and statement made about it. It has been audited but is not proven correct:
 * it may contain defects the author did not find, and by interacting with it you accept
 * that risk in full.
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
import {IDegenerusJackpots} from "../interfaces/IDegenerusJackpots.sol";

/// @dev Minimal WWXRP surface for the golden-ticket consolation mint. The delegatecall
///      context makes msg.sender the Game, which is a whitelisted WWXRP minter.
interface IWwxrpMintPrize {
    /// @notice Mint WWXRP to a recipient (WWXRP, authorized minters only).
    function mintPrize(address to, uint256 amount) external;
}

/// @dev The craps doors a coin draw pays its craps half through, called BARE — no stipend, no
///      try/catch — on the daily advance: a whole day banks one pass (`creditPasses`, revert-free
///      and saturating); an opener seat goes through the comp door's window-ahead kind, which
///      burns nothing for the Game, and the Game vets the winner first (`extsload` of the
///      table's day claims, and never the vault or sDGNRS) so it cannot revert.
interface ICrapsCoinDrawSeat {
    /// @notice Read a raw CrapsBattle storage slot.
    function extsload(bytes32 slot) external view returns (bytes32 value);

    /// @notice GAME: bank pass credits, revert-free and saturating.
    function creditPasses(address player, uint32 normal, uint32 high) external returns (uint32 normalCredited);

    /// @notice Seat or reserve per the packed `code` (kind 5 = one window ahead).
    function vaultComp(uint256 code) external returns (uint256 charged);
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

    /// @notice Thrown when a function restricted to the game contract is called by another address.
    error OnlyGame();

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    /// @dev Emitted when an unminted future-level ticket holder (1-99 levels ahead of the
    ///      purchase level) wins the purchase-day FLIP fill draw. Drawn from ticketQueue
    ///      (traits not yet assigned).
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

    /// @notice A coin draw's craps-half winner. `fullDay` requests one banked normal craps pass
    ///         (see `CrapsPassesCredited`); otherwise the award seats tomorrow's opener.
    ///         `refused` means the winner received the award's FLIP value instead: an opener
    ///         could not be seated, or a full-day pass bank was saturated.
    ///         `winnerLevel` is the level the winner was drawn from.
    event CoinDrawCrapsWin(address indexed winner, uint24 indexed winnerLevel, bool fullDay, bool refused);

    /// @dev Emitted once per daily drawing with both main and bonus winning traits.
    ///      bonusTargetLevel is the level the bonus-trait coin draw reads (level + 1 on
    ///      jackpot days); 0 on purchase days, which have no bonus-trait draw (the bonus set
    ///      still feeds the day's foil claims).
    event DailyWinningTraits(
        uint24 indexed day,
        uint32 mainTraitsPacked,
        uint32 bonusTraitsPacked,
        uint24 bonusTargetLevel
    );

    /// @dev Whale pass awarded in place of an ETH or lootbox payout — otherwise the
    ///      `whalePassClaims` increment is silent. The award is a bare half-pass counter
    ///      binding to no level: claimWhalePass sets the target from the level standing at
    ///      claim time and reports it on WhalePassClaimed. The paying level is not carried
    ///      here either — every emit site sits in a receipt that already stamps it.
    ///      `source` is one of the WHALE_PASS_SRC_* constants.
    event JackpotWhalePassWin(
        address indexed winner,
        uint256 halfPassCount,
        uint8 source
    );

    /// @dev Yield surplus split three ways at the level transition. `perRecipientShare` is
    ///      credited to each of VAULT, sDGNRS and GNRUS — equal shares to pinned addresses,
    ///      so one field describes the whole distribution.
    event YieldSurplusDistributed(uint256 perRecipientShare);

    /// @dev `JackpotWhalePassWin.source` values.
    uint8 private constant WHALE_PASS_SRC_SOLO = 1;
    uint8 private constant WHALE_PASS_SRC_BAF_DIRECT = 2;
    uint8 private constant WHALE_PASS_SRC_AWARD_TICKETS = 3;

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

    /// @dev Small-lootbox threshold for the jackpot lootbox portion split.
    uint256 private constant SMALL_LOOTBOX_THRESHOLD = 0.5 ether;

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
    uint16 private constant BAF_TRAIT_SENTINEL = 420;

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

    uint256 private constant BAF_TICKET_TAG = 0x4261665469636b6574; // "BafTicket"
    bytes32 private constant HERO_SYMBOL_TAG = keccak256("degenerus.jackpot.hero-symbol");

    /// @dev Domain separator for per-pull level sampling in the daily coin jackpot.
    bytes32 private constant FLIP_LEVEL_TAG = keccak256("coin-level");

    /// @dev Domain separator for rolling current-pool daily jackpot percentage.
    bytes32 private constant DAILY_CURRENT_BPS_TAG =
        keccak256("daily-current-bps");

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

    /// @dev Level picks the purchase-day fill draw may spend. A pick lands on an unvisited
    ///      level or is spent on a revisit, so empty levels cannot stretch the draw's gas.
    uint256 private constant FUTURE_FLIP_LEVEL_PICKS = 16;

    /// @dev Domain separator for the purchase-day future fill draw's entropy derivation.
    bytes32 private constant FAR_FUTURE_FLIP_TAG = keccak256("far-future-coin");

    /// @dev Winners in each half of a coin draw: up to this many craps seats, and up to this many
    ///      equal FLIP shares.
    uint256 private constant COIN_DRAW_HALF_SLOTS = 25;

    /// @dev What one coin-draw seat on tomorrow's opener costs the craps half — the opener's
    ///      expected bankroll plus bounty (2,433 FLIP), rounded to the draw's 100-FLIP unit.
    uint256 private constant CRAPS_OPENER_SEAT_VALUE = 2_400 ether;

    /// @dev CrapsBattle's `_daySeated` mapping slot (scripts/layout/golden/CrapsBattle.json; the
    ///      layout oracle fails the build on a move). A day's claims live under day * 8.
    uint256 private constant CRAPS_DAY_SEATED_SLOT = 8;

    /// @dev What turning an opener seat into tomorrow's whole day costs on top: the day pass's
    ///      value less the seat already paid for.
    uint256 private constant CRAPS_DAY_UPGRADE_VALUE = NORMAL_DAY_PASS_VALUE - CRAPS_OPENER_SEAT_VALUE;

    /// @dev Daily: 32 per non-solo quadrant. Carryover: 24 per quadrant.
    ///      Empty buckets redistribute the cap in whole groups of eight.
    uint16 private constant TICKET_JACKPOT_MAX_WINNERS = 96;

    /// @dev Early-bird cap: 32 winners per quadrant when all four buckets are active.
    uint16 private constant EARLY_BIRD_MAX_WINNERS = 128;

    /// @dev Entries per whole ticket. Jackpot budgets are denominated in entries
    ///      (quarter-tickets), but awards are paid in whole tickets only.
    uint256 private constant ENTRIES_PER_TICKET = 4;

    /// @dev Daily jackpot max scale (6.36x) producing bucket counts 152/104/48/1 at 200+ ETH.
    ///      All 305 winners (152 + 104 + 48 + 1) are paid in a single call.
    uint32 private constant DAILY_JACKPOT_SCALE_MAX_BPS = 63_600;

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
    ///      - Three-day schedule: 6%-14% of remaining currentPrizePool on day 1, 12%-28% on day 2.
    ///      - Final physical day (day 3, or day 1 for turbo): distributes the remaining currentPrizePool.
    ///      - Day 1 also runs the early-bird ticket jackpot (from futurePrizePool).
    ///      - On every non-early-bird day, takes 0.5% of futurePrizePool and buys tickets
    ///        at the current level (next level on the final day) for winners from level + 1, credited to nextPool.
    ///      - Increments jackpotCounter on completion.
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
            bool isFinalPhysicalDay;
            uint256 curPool;
            {
                uint8 counter = jackpotCounter;
                isFinalPhysicalDay = _isFinalJackpotDay(counter, jackpotFlags);
                bool isEarlyBirdDay = (counter == 0);
                curPool = _getCurrentPrizePool();
                uint16 dailyBps;
                if (isFinalPhysicalDay) {
                    dailyBps = 10_000; // Final physical day: 100% of remaining pool
                } else {
                    dailyBps = _dailyCurrentPoolBps(counter, randWord);
                    // The standard schedule pays a doubled slice on its middle day.
                    if (counter != 0) {
                        dailyBps *= 2;
                    }
                }
                uint256 budget = (curPool * dailyBps) / 10_000;

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
                    // The bonus board reads level + 1, the one future level already minted.
                    sourceLevelOffset = 1;
                    sourceLevel = lvl + 1;

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
                // Packing: [reserved (8 bits)] [dailyEntries (64 bits @ 8)]
                // [carryoverEntries (64 bits @ 72)] [carryoverSourceOffset (8 bits @ 136)]
                dailyTicketBudgetsPacked = _packDailyTicketBudgets(
                    dailyEntries,
                    carryoverEntries,
                    sourceLevelOffset
                );

                // Day 1 only: price the early-bird ticket jackpot (3% of futurePrizePool, moved
                // future -> next now) and latch its entries at bits 144..207 of the same word.
                // The winners (up to another 128) are drawn from the next advance's own stage
                // (payEarlyBirdTickets), so the day-1 ETH leg and the early-bird leg never
                // share a tx. Nothing since the golden-ticket resolve writes the future pool,
                // so the 3% is priced off the same basis it always was, ahead of the ETH leg.
                if (isEarlyBirdDay) {
                    dailyTicketBudgetsPacked |= _priceEarlyBirdTickets(lvl + 1) << 144;
                }

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
                lvl,
                lvl + 1
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
            lvl,
            0
        );

        // Daily 4% drip from futurePrizePool every ordinary purchase day.
        uint256 futureBal = _getFuturePrizePool();
        uint256 ethDaySlice = futureBal / 25;

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

        // Fixed bucket counts [24, 16, 8, 1] = 49 winners, rotated by entropy.
        uint256 paidEth;
        if (ethPool != 0) {
            uint16[4] memory shareBps = JackpotBucketLib.shareBpsByBucket(
                DAILY_JACKPOT_SHARES_PACKED,
                uint8(effectiveEntropy & 3)
            );
            uint16[4] memory bucketCounts;
            {
                uint16[4] memory base;
                base[0] = 24;
                base[1] = 16;
                base[2] = 8;
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
        // the deferred ticket stage does not credit next itself. futureBal is still exact —
        // nothing above writes prizePoolsPacked (purchase-phase distribution never reaches the solo
        // whale-pass leg). The ticket leg, the skim and the ETH leg partition ethDaySlice exactly and
        // paidEth never exceeds the ETH leg, so the three debits sum to at most the 4% slice and the
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

        // Price the ticket leg here and pay it from its own advance stage
        // (payPurchaseDailyTickets): the 120-winner cold draw is the heaviest block of
        // the purchase daily, so it never shares a transaction with the ETH and FLIP
        // legs. The packed-slot write above already moved the whole budget to
        // nextPrizePool; only the entries it backs wait in the top field of
        // dailyTicketBudgetsPacked. A 50% conversion keeps the pool/ticket backing
        // ratio. The day stays locked until that stage seals it.
        if (ticketLegBudget != 0) {
            (uint256 entries, ) = _budgetToEntries(ticketLegBudget / 2, lvl);
            // Awards are whole tickets, so a leg under one ticket pays nobody: seal now
            // rather than spend a crank on an empty stage.
            if (entries >= ENTRIES_PER_TICKET) dailyTicketBudgetsPacked = entries << 208;
        }
    }

    /// @notice The ticket leg of the purchase-phase daily, from its own advance stage.
    /// @dev Called by advanceGame on the advance after payDailyJackpot(false) priced it, with
    ///      the same day's recorded word. The main board is the one the pricing stage rolled
    ///      and recorded in dailyFoilDraw for the day it priced (dailyIdx has not moved: the
    ///      pricing stage does not seal while this leg is pending), and the winner entropy is
    ///      the value the single-tx form used, so the draw is unchanged by the split. Tickets
    ///      queue at the purchase level, which the held lock keeps un-promoted between the two
    ///      stages. Clears the field it consumes; the caller seals the day.
    /// @param randWord VRF entropy (the day's recorded word).
    function payPurchaseDailyTickets(uint256 randWord) external {
        uint256 packed = dailyTicketBudgetsPacked;
        uint256 entries = packed >> 208;
        uint24 lvl = level + 1;
        (, uint32 winningTraitsPacked, , ) = _foilDrawFor(uint256(dailyIdx) + 1);
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
        dailyTicketBudgetsPacked = packed & ((uint256(1) << 208) - 1);
    }

    /// @notice Phase 2 of the daily jackpot: the coin jackpot and the day's own ticket leg.
    /// @dev Called by advanceGame when dailyJackpotCoinTicketsPending is true. The daily is a
    ///      chain of advance txs so each stays under the per-tx gas cap: Phase 1 pays the ETH,
    ///      on day 1 the early-bird ticket leg (up to 128 winners) runs from its own stage
    ///      before this one (payEarlyBirdTickets), this stage pays FLIP and the main-board
    ///      tickets, and the carryover ticket leg (up to another 96 winners) runs from its own
    ///      stage on the next advance (payCarryoverTickets). Phase 1's packed budgets stay in
    ///      place for that stage when a carryover was priced; otherwise they are cleared here.
    ///
    ///      Traits are derived inline from randWord (main via isBonus=false, bonus via isBonus=true).
    ///      Uses stored values from Phase 1:
    ///      - rngWordCurrent: VRF entropy for deterministic winner selection
    ///      - dailyTicketBudgetsPacked: Packed ticket units and carryover source offset
    ///
    /// @param randWord VRF entropy (must match rngWordCurrent from Phase 1).
    /// @return carryoverPending True when a carryover leg was priced and waits for the next advance.
    function payDailyJackpotCoinAndTickets(uint256 randWord) external returns (bool carryoverPending) {
        if (!dailyJackpotCoinTicketsPending) return false;

        // Unpack stored values
        (
            uint256 dailyEntries,
            uint256 carryoverEntries,

        ) = _unpackDailyTicketBudgets(dailyTicketBudgetsPacked);

        // Derive traits inline from randWord; main and bonus each roll a distinct hero.
        uint24 lvl = level;
        (
            uint32 mainTraitsPacked,
            uint32 bonusTraitsPacked
        ) = _rollWinningTraitsPair(randWord);

        // --- Coin Jackpot ---
        // Bonus traits on level + 1, minted on the last-purchase word before this phase.
        _runFlipJackpot(lvl, lvl, lvl + 1, lvl + 1, bonusTraitsPacked, randWord);

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

        // Complete the daily jackpot cycle. The counter advances with the day seal: here when
        // this stage seals the day (no carryover) or ends the level, otherwise in
        // payCarryoverTickets, which seals the day. The ticket-routing predicate keys off the
        // counter under the lock to spot the final daily's request, and the lock spans the
        // carryover stage, so a counter advanced ahead of its seal would route buys to the
        // next level for one advance.
        uint8 counterCached = jackpotCounter;
        carryoverPending = carryoverEntries != 0;
        if (!carryoverPending || _isFinalJackpotDay(counterCached, jackpotFlags)) {
            unchecked {
                jackpotCounter = counterCached + 1;
            }
        }

        // Clear pending state. A priced carryover keeps Phase 1's budgets for its own stage.
        dailyJackpotCoinTicketsPending = false;
        if (!carryoverPending) dailyTicketBudgetsPacked = 0;
    }

    /// @notice The carryover ticket leg of the daily jackpot, from its own advance stage.
    /// @dev Called by advanceGame on the advance after payDailyJackpotCoinAndTickets left it
    ///      pending, with the same day's word from rngGate. Winners come from the source level's
    ///      buckets on the day's bonus traits (re-rolled from the word: the hero pool and the
    ///      golden-ticket ban read the same on every roll of a board, as Phase 2's re-roll of
    ///      Phase 1's board already relies on); tickets queue at the current level, or lvl+1
    ///      once _endPhase has closed the level. The lock held since the request keeps every
    ///      input frozen until the day seals after this leg.
    /// @param randWord VRF entropy (the day's recorded word).
    function payCarryoverTickets(uint256 randWord) external {
        (, uint256 carryoverEntries, uint8 carryoverSourceOffset) = _unpackDailyTicketBudgets(
            dailyTicketBudgetsPacked
        );
        uint24 lvl = level;
        uint24 sourceLevel = lvl + uint24(carryoverSourceOffset);
        (, uint32 bonusTraitsPacked) = _rollWinningTraitsPair(randWord);
        _distributeTicketJackpot(
            sourceLevel,
            phaseTransitionActive ? lvl + 1 : lvl,
            bonusTraitsPacked,
            carryoverEntries,
            EntropyLib.hash2(randWord, sourceLevel),
            TICKET_JACKPOT_MAX_WINNERS,
            240,
            false // bonus board: no ETH distribution, no solo quadrant
        );
        dailyTicketBudgetsPacked = 0;
        // A non-final daily advances the counter here, with its seal; the final daily advanced
        // it in the coin+tickets stage so _endPhase could fire there (which then zeroed it).
        if (!phaseTransitionActive) {
            unchecked {
                ++jackpotCounter;
            }
        }
    }

    /// @dev Prices the early-bird ticket jackpot from the unified future pool: the full 3%
    ///      budget always moves future -> next (a single net move on the packed slot; future
    ///      funds the budget, next backs the queued tickets), converted on the same
    ///      4-entries-per-ticket basis every other jackpot path uses (`_budgetToEntries`).
    /// @param lvl The level the early-bird tickets are priced and queued at (outer level + 1).
    /// @return entries The early-bird entry count payEarlyBirdTickets distributes.
    function _priceEarlyBirdTickets(uint24 lvl) private returns (uint256 entries) {
        (uint128 nextBal, uint128 futureBal) = _getPrizePools();
        uint256 totalBudget = (uint256(futureBal) * 300) / 10_000; // 3%
        if (totalBudget == 0) return 0;
        (entries, ) = _budgetToEntries(totalBudget, lvl);
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
    ///      Winners come from `lvlTraitEntry[level + 1]` on the day's bonus traits, re-rolled
    ///      from the word exactly as the carryover stage re-rolls its board; tickets queue at
    ///      level + 1. Clears its own field and leaves the rest of the packed budgets for the
    ///      coin+tickets stage. The lock held since the request keeps every input frozen.
    /// @param randWord VRF entropy (the day's recorded word).
    function payEarlyBirdTickets(uint256 randWord) external {
        uint256 packed = dailyTicketBudgetsPacked;
        uint24 lvl = level + 1;
        _distributeTicketJackpot(
            lvl,
            lvl,
            _rollWinningTraits(randWord, true),
            uint64(packed >> 144),
            EntropyLib.hash2(randWord, lvl),
            EARLY_BIRD_MAX_WINNERS,
            239,
            false // bonus board: no ETH distribution, no solo quadrant
        );
        dailyTicketBudgetsPacked = packed & ((uint256(1) << 144) - 1);
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

    /// @dev Distributes ticket rewards to winners drawn from winning trait pools.
    /// @param sourceLvl Level whose ticket queue supplies candidate winners.
    /// @param queueLvl Level at which the awarded tickets are queued.
    /// @param winningTraitsPacked Packed winning trait IDs for the 4 buckets.
    /// @param entries Total entries backing this draw (converted to whole tickets).
    /// @param entropy RNG state driving winner selection.
    /// @param maxWinners Cap on the draw's total winner count (lowered to the whole tickets the
    ///        budget covers, rounded down to eight, then split across active buckets).
    /// @param saltBase Base salt for per-bucket entropy derivation.
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
        // Full packed-word draws whenever the budget funds eight winners. Tiny
        // budgets keep their individual slots instead of losing the draw entirely.
        if (cap >= 8) cap &= ~uint16(7);

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
                // Award size prices the result; only the draw and bucket identify its seed.
                // Derive each bucket independently so skipping another bucket cannot reroll it.
                uint256 bucketEntropy = EntropyLib.hash2(entropy, traitIdx);
                _distributeTicketsToBucket(
                    sourceLvl,
                    queueLvl,
                    traitIds[traitIdx],
                    counts[traitIdx],
                    bucketEntropy,
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
                sourceLvl,
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
    /// @param lvl Level whose trait entry queues are counted.
    /// @param traitIds Winning trait IDs for the 4 buckets.
    /// @param maxWinners Total slots, a multiple of eight or fewer than eight. Split full
    ///        groups across active buckets; rotate leftover groups from an entropy-picked start.
    /// @param entropy RNG state for rotation and scaling.
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

    /// @dev Unified ETH distribution across trait buckets. All buckets are paid in a single
    ///      call. The winner total is bounded by the bucket geometry: base [24,16,8,1] at the
    ///      DAILY_JACKPOT_SCALE_MAX_BPS ceiling gives 152 + 104 + 48 + 1 = 305, and each bucket
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
    /// @param unit Per-winner rounding unit; non-solo bucket shares round down to a
    ///        multiple of unit * winnerCount (0 skips rounding).
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

            // Keep winner selection independent of the pool and other buckets' payouts.
            uint256 bucketEntropy = EntropyLib.hash2(entropy, traitIdx);

            uint256 paidDelta;
            uint256 claimDelta;
            (paidDelta, claimDelta,) = _processBucket(
                lvl,
                traitIds[traitIdx],
                traitIdx,
                count,
                share,
                bucketEntropy,
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
                lvl,
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
            emit JackpotWhalePassWin(
                w,
                wpSpent / HALF_WHALE_PASS_PRICE,
                WHALE_PASS_SRC_SOLO
            );
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

    /// @dev Replaces the winning quadrant's trait with a hero-symbol override sampled by
    ///      `_rollHeroSymbol` from the prior day's settled wager pool. Applied to all jackpot
    ///      paths (purchase phase + jackpot phase). Reads `dailyHeroWagers[dailyIdx]`:
    ///      `dailyIdx` moves only at `_unlockRng` and at rngGate's gap skip (AdvanceModule),
    ///      both outside jackpot processing, so here it is frozen at the previous day's
    ///      index — every consumer in a single
    ///      jackpot resolution therefore reads the same wager pool. Bets placed on day D
    ///      write to `dailyHeroWagers[D]`; day D+1's jackpot reads slot[D] via
    ///      `dailyIdx == D` (set by day D's `_unlockRng`).
    ///
    ///      `heroEntropy` is the raw VRF entropy word for the day. This applies the main draw's
    ///      hero; the bonus draw rolls a SEPARATE hero (main slot excluded) in
    ///      `_rollWinningTraitsPair`, so the two heroes never coincide. The symbol roll
    ///      consumes `keccak256(abi.encode(heroEntropy, HERO_SYMBOL_TAG, day))`; colors are untouched by
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
    ///      `pick = uint64(uint256(keccak256(abi.encode(entropy, HERO_SYMBOL_TAG, day))) % effectiveTotal)`
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
            uint256(keccak256(abi.encode(entropy, HERO_SYMBOL_TAG, day))) % effectiveTotal
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
    ///        Colors 5/6: floor(1% of bucket), minimum 1.
    ///        Colors 0..4: floor(2% of bucket), minimum 2.
    function _deityVirtualCount(
        uint8 trait,
        uint256 len,
        address deity
    ) private pure returns (uint256 virtualCount) {
        if (deity != address(0)) {
            uint8 color = (trait >> 3) & 7;
            if (color == 7) {
                virtualCount = 1;
            } else if (color >= 5) {
                virtualCount = len / 100;
                if (virtualCount == 0) virtualCount = 1;
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
        uint256 len = lvlTraitEntry[lvl][trait].length;

        // traitId layout: (quadrant << 6) | (color << 3) | symIdx
        // fullSymId = quadrant * 8 + symIdx
        uint8 fullSymId = (trait >> 6) * 8 + (trait & 0x07);
        address deity;
        if (fullSymId < 32) {
            deity = deityBySymbol[fullSymId];
        }

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

    /// @dev A cursor belongs to exactly one (level, trait) bucket. It caches a packed word
    ///      for eight outputs even when other buckets' draws are interleaved. Callers gate
    ///      empty pools; no storage writer can change these buckets during a draw.
    function _drawBucketEntry(
        uint24 lvl,
        uint8 trait,
        uint256 len,
        uint256 effectiveLen,
        address deity,
        uint256 randomWord,
        uint256 salt,
        uint256 pull,
        PackedTicketSampleLib.Cursor memory cursor
    ) private view returns (address winner, uint256 index) {
        if (cursor.used == 0) {
            uint256 base = PackedTicketSampleLib.begin(
                cursor, effectiveLen, EntropyLib.hash4(randomWord, trait, salt, pull)
            );
            if (base < len) cursor.word = _bucketWordAt(lvl, trait, base);
        }
        bool redrawn;
        (index, redrawn) = PackedTicketSampleLib.next(cursor, effectiveLen);
        if (index >= len) return (deity, type(uint256).max);
        uint256 word = redrawn ? _bucketWordAt(lvl, trait, index) : cursor.word;
        winner = _bucketOwnerFromWord(lvl, word, index);
    }

    /// @notice Pays daily FLIP jackpot to random ticket holders.
    /// @dev Runs in the purchase-phase daily advance, in the same transaction as the daily
    ///      jackpot. Awards 0.25% of the previous level's recorded prize pool
    ///      (`levelPrizePool[lvl - 1]`, the ratchet target before any century floor), converted
    ///      to FLIP at the current level's ticket price.
    ///      Winners are trait-matched ticket holders in [minLevel, maxLevel], which must be
    ///      minted levels: half the budget seats winners on tomorrow's craps opener or whole
    ///      day, the rest (and whatever the seats leave) pays equal FLIP shares.
    /// @param lvl Current level.
    /// @param randWord VRF entropy for winner selection.
    /// @param minLevel Minimum target level for the coin distribution (inclusive).
    /// @param maxLevel Maximum target level for the coin distribution (inclusive).
    function payDailyFlipJackpot(uint24 lvl, uint256 randWord, uint24 minLevel, uint24 maxLevel) external {
        uint32 bonusTraitsPacked = _rollWinningTraits(randWord, true);
        _runFlipJackpot(lvl, level, minLevel, maxLevel, bonusTraitsPacked, randWord);
    }

    /// @notice Purchase-day FLIP fill draw: the daily coin budget over unminted future levels.
    /// @dev Budget as payDailyFlipJackpot; winners come from the far-future queues of
    ///      [lvl + 1, lvl + 99] (see _awardFutureCoinFill).
    /// @param lvl Purchase level (the minted level whose day this is).
    /// @param randWord VRF entropy for level picks and walk starts.
    function payDailyFutureFlipJackpot(uint24 lvl, uint256 randWord) external {
        _awardFutureCoinFill(lvl, _calcDailyCoinBudget(lvl, level), randWord);
    }

    /// @dev Daily coin draw core over trait-matched winners in [minLevel, maxLevel].
    /// @param lvl Level keying the prize pool snapshot for the budget.
    /// @param currLevel Current game level (storage `level` at call time), used
    ///        for FLIP pricing.
    /// @param minLevel Minimum target level for the coin distribution (inclusive).
    /// @param maxLevel Maximum target level for the coin distribution (inclusive).
    /// @param bonusTraitsPacked Packed winning trait IDs for the draw.
    /// @param randWord VRF entropy for winner selection.
    function _runFlipJackpot(
        uint24 lvl,
        uint24 currLevel,
        uint24 minLevel,
        uint24 maxLevel,
        uint32 bonusTraitsPacked,
        uint256 randWord
    ) private {
        _awardDailyCoinToTraitWinners(
            minLevel,
            maxLevel,
            bonusTraitsPacked,
            _calcDailyCoinBudget(lvl, currLevel),
            randWord
        );
    }

    /// @dev Emit DailyWinningTraits without running any distribution.
    ///      Used at purchaseLevel==1 where payDailyJackpot is skipped and two coin
    ///      jackpots replace the ETH jackpot. First coin call (the "main") uses
    ///      bonus-derived traits from randWord. Second coin call uses traits from
    ///      a salted randWord (keccak256(randWord, BONUS_TRAITS_TAG)).
    /// @param randWord VRF entropy for both trait rolls.
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

    /// @dev Awards a coin draw over trait-matched ticket holders across [minLevel, maxLevel].
    ///      Each pull samples its own random level via keccak256(randomWord, FLIP_LEVEL_TAG, i)
    ///      and rotates trait deterministically via i % 4. The CRAPS half runs first, on pulls
    ///      0 .. _crapsPulls(budget) - 1; the COIN half on pulls COIN_DRAW_HALF_SLOTS onward,
    ///      as many as it has whole equal shares for (_coinDrawPlan). Empty (lvl', trait_i)
    ///      buckets skip; an unfilled coin share is not minted. Per-trait deity addresses are
    ///      cached at loop entry. Each (level, trait) owns an independent eight-lane cursor.
    function _awardDailyCoinToTraitWinners(
        uint24 minLevel,
        uint24 maxLevel,
        uint32 winningTraitsPacked,
        uint256 coinBudget,
        uint256 randomWord
    ) private {
        if (coinBudget == 0) return;

        uint8[4] memory traitIds = JackpotBucketLib.unpackWinningTraits(
            winningTraitsPacked
        );

        // Per-trait deity cache: deityBySymbol is level-independent, so one read per trait
        // serves every pull of that trait.
        address[4] memory deityCache;
        for (uint8 t; t < 4; ) {
            uint8 trait = traitIds[t];
            uint8 fullSymId = (trait >> 6) * 8 + (trait & 0x07);
            if (fullSymId < 32) {
                deityCache[t] = deityBySymbol[fullSymId];
            }
            unchecked { ++t; }
        }

        uint24 range = maxLevel - minLevel + 1;
        PackedTicketSampleLib.Cursor[] memory cursors = new PackedTicketSampleLib.Cursor[](uint256(range) * 4);

        uint256 pulls = _crapsPulls(coinBudget);
        address[] memory craps = new address[](pulls);
        uint24[] memory crapsLvls = new uint24[](pulls);
        uint256 n;
        for (uint256 i; i < pulls; ) {
            (address winner, uint24 lvlPrime, ) = _drawCoinEntry(
                minLevel, range, traitIds[i & 3], deityCache[i & 3], randomWord, i, cursors
            );
            if (winner != address(0)) {
                craps[n] = winner;
                crapsLvls[n] = lvlPrime;
                unchecked { ++n; }
            }
            unchecked { ++i; }
        }
        assembly ("memory-safe") {
            mstore(craps, n)
            mstore(crapsLvls, n)
        }

        (uint256 fullDays, uint256 amount, uint256 cap) = _coinDrawPlan(coinBudget, n);
        address[] memory coin = new address[](cap);
        uint256 paid;
        for (uint256 i = COIN_DRAW_HALF_SLOTS; i < COIN_DRAW_HALF_SLOTS + cap; ) {
            uint8 traitIdx = uint8(i & 3);
            uint8 trait_i = traitIds[traitIdx];
            (address winner, uint24 lvlPrime, uint256 ticketIdx) = _drawCoinEntry(
                minLevel, range, trait_i, deityCache[traitIdx], randomWord, i, cursors
            );
            if (winner != address(0)) {
                emit JackpotFlipWin(winner, lvlPrime, trait_i, amount, ticketIdx);
                coin[paid] = winner;
                unchecked { ++paid; }
            }
            unchecked { ++i; }
        }
        _finishCoinDraw(craps, crapsLvls, fullDays, coin, 0, paid, amount);
    }

    /// @dev How many craps-half pulls a budget draws: one per whole opener seat its craps half
    ///      covers, at most COIN_DRAW_HALF_SLOTS.
    function _crapsPulls(uint256 budget) private pure returns (uint256 pulls) {
        pulls = (budget >> 1) / CRAPS_OPENER_SEAT_VALUE;
        if (pulls > COIN_DRAW_HALF_SLOTS) pulls = COIN_DRAW_HALF_SLOTS;
    }

    /// @dev Split a coin draw once its `n` craps winners are known. The craps half seats every
    ///      one of them on tomorrow's opener (n never exceeds what the half covers) and spends
    ///      what is left upgrading seats to tomorrow's whole day, CRAPS_DAY_UPGRADE_VALUE each.
    ///      Whatever the craps half does not spend joins the coin half, which pays up to
    ///      COIN_DRAW_HALF_SLOTS winners one equal whole-unit share each; the sub-share remainder
    ///      is not minted, so no share can be short.
    /// @return fullDays Seats upgraded to the whole day, taken from the front.
    /// @return amount   One coin winner's share, in whole FLIP_ROUND_UNITs.
    /// @return cap      How many coin shares the budget funds.
    function _coinDrawPlan(uint256 budget, uint256 n)
        private
        pure
        returns (uint256 fullDays, uint256 amount, uint256 cap)
    {
        unchecked {
            uint256 left = (budget >> 1) - n * CRAPS_OPENER_SEAT_VALUE;
            fullDays = left / CRAPS_DAY_UPGRADE_VALUE;
            if (fullDays > n) fullDays = n;
            uint256 units = (budget - n * CRAPS_OPENER_SEAT_VALUE - fullDays * CRAPS_DAY_UPGRADE_VALUE)
                / FlipRoundLib.FLIP_ROUND_UNIT;
            cap = units < COIN_DRAW_HALF_SLOTS ? units : COIN_DRAW_HALF_SLOTS;
            if (cap != 0) amount = (units / cap) * FlipRoundLib.FLIP_ROUND_UNIT;
        }
    }

    /// @dev Pay a drawn coin draw: seat each craps winner on tomorrow (the first `fullDays` for
    ///      the whole day, the rest on its opener), then credit, in one batch, the `paid` coin
    ///      winners at coin[coinOff ..] their share and every refused Craps winner the award's
    ///      value (a full-day award normally banks a pass, see _seatOnTable) — a refusal
    ///      changes the form the winner holds the value in, not how much the draw pays.
    function _finishCoinDraw(
        address[] memory craps,
        uint24[] memory crapsLvls,
        uint256 fullDays,
        address[] memory coin,
        uint256 coinOff,
        uint256 paid,
        uint256 amount
    ) private {
        uint256 n = craps.length;
        address[] memory players = new address[](paid + n);
        uint256[] memory amounts = new uint256[](paid + n);
        uint256 k;
        unchecked {
            for (; k < paid; ++k) {
                players[k] = coin[coinOff + k];
                amounts[k] = amount;
            }
            for (uint256 i; i < n; ++i) {
                address w = craps[i];
                bool day = i < fullDays;
                uint256 flipOwed = _seatOnTable(w, day);
                emit CoinDrawCrapsWin(w, crapsLvls[i], day, flipOwed != 0);
                if (flipOwed != 0) {
                    players[k] = w;
                    amounts[k] = flipOwed;
                    ++k;
                }
            }
        }
        if (k != 0) {
            assembly ("memory-safe") {
                mstore(players, k)
                mstore(amounts, k)
            }
            coinflip.creditFlipBatch(players, amounts);
        }
    }

    /// @dev Pay one craps winner. A whole day banks one normal pass (spendable only
    ///      on a future day whose word does not exist yet); if its bank is saturated,
    ///      the winner takes its full value in FLIP. An opener is a seat on tomorrow's opener — the first
    ///      window no word has drawn — through the comp door as kind 5, period 0, count one; it
    ///      is refused, and owed CRAPS_OPENER_SEAT_VALUE (the opener's expected cost) in FLIP,
    ///      for the vault or sDGNRS (`openBonusDay` seats both for the whole day, which an opener
    ///      claim would stand down) and for any claim on tomorrow in the table's
    ///      `_daySeated[tomorrow * 8]`, including a seat this same draw just wrote.
    /// @return flipOwed Zero if delivered; the refused award's value otherwise.
    function _seatOnTable(address w, bool day) private returns (uint256 flipOwed) {
        ICrapsCoinDrawSeat table = ICrapsCoinDrawSeat(ContractAddresses.CRAPS);
        if (day) {
            return table.creditPasses(w, 1, 0) == 0 ? NORMAL_DAY_PASS_VALUE : 0;
        }
        uint256 tomorrow = uint256(_simulatedDayIndex()) + 1;
        bytes32 claims = keccak256(abi.encode(tomorrow * 8, CRAPS_DAY_SEATED_SLOT));
        if (
            w == ContractAddresses.VAULT || w == ContractAddresses.SDGNRS
                || table.extsload(keccak256(abi.encode(w, claims))) != 0
        ) return CRAPS_OPENER_SEAT_VALUE;
        table.vaultComp(uint256(uint160(w)) | (tomorrow << 176) | (uint256(1) << 200) | (uint256(5) << 160));
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
        uint256 len = lvlTraitEntry[lvl][trait].length;
        uint256 effectiveLen = len + _deityVirtualCount(trait, len, deity);
        if (effectiveLen != 0) {
            (winner, index) = _drawBucketEntry(
                lvl, trait, len, effectiveLen, deity, randomWord, lvl, pull,
                cursors[uint256(offset) * 4 + (trait >> 6)]
            );
        }
    }

    /// @dev Purchase-day coin draw over unminted future levels. Wallets are drawn level by level:
    ///      pick an unvisited level in [lvl + 1, lvl + 99], walk its far-future queue from a random
    ///      lane (one lane per wallet registration, each taken at most once) until the draw has
    ///      its wallets or the level is exhausted, then pick again. Every wallet on a walked level
    ///      is equally likely to be included. At most FUTURE_FLIP_LEVEL_PICKS picks, so empty
    ///      levels bound the gas. The first _crapsPulls(budget) wallets are the craps half, the
    ///      rest the coin half (see _coinDrawPlan).
    function _awardFutureCoinFill(uint24 lvl, uint256 coinBudget, uint256 rngWord) private {
        if (coinBudget == 0) return;
        uint256 entropy = uint256(keccak256(abi.encode(rngWord, lvl, FAR_FUTURE_FLIP_TAG)));

        uint256 pulls = _crapsPulls(coinBudget);
        uint256 want = pulls + COIN_DRAW_HALF_SLOTS;
        address[] memory winners = new address[](want);
        uint24[] memory winnerLevels = new uint24[](want);
        uint256 found;
        uint256 visited;
        for (uint256 pick; pick < FUTURE_FLIP_LEVEL_PICKS && found < want; ) {
            entropy = EntropyLib.hash2(entropy, pick);
            uint256 offset = entropy % 99;
            if ((visited >> offset) & 1 == 0) {
                visited |= uint256(1) << offset;
                uint24 candidate = lvl + 1 + uint24(offset);
                uint256[] storage queue = ticketQueue[_tqFarFutureKey(candidate)];
                uint256 len = queue.length;
                if (len != 0) {
                    uint256 take = want - found;
                    if (take > len) take = len;
                    uint256 idx = (entropy >> 128) % len;
                    uint256 word = _tqWordAt(queue, idx);
                    for (uint256 k; k < take; ) {
                        winners[found] = address(uint160(
                            _entryRecord(candidate, uint32(word >> ((idx & 7) << 5)))
                        ));
                        winnerLevels[found] = candidate;
                        unchecked {
                            ++found;
                            ++k;
                            ++idx;
                        }
                        if (idx == len) idx = 0;
                        if (idx & 7 == 0 && k < take) word = _tqWordAt(queue, idx);
                    }
                }
            }
            unchecked { ++pick; }
        }
        if (found == 0) return;

        uint256 n = found < pulls ? found : pulls;
        address[] memory craps = new address[](n);
        uint24[] memory crapsLvls = new uint24[](n);
        for (uint256 i; i < n; ) {
            craps[i] = winners[i];
            crapsLvls[i] = winnerLevels[i];
            unchecked { ++i; }
        }
        (uint256 fullDays, uint256 amount, uint256 cap) = _coinDrawPlan(coinBudget, n);
        uint256 paid = found - n;
        if (paid > cap) paid = cap;
        for (uint256 i; i < paid; ) {
            emit FarFutureFlipJackpotWinner(winners[n + i], lvl, winnerLevels[n + i], amount);
            unchecked { ++i; }
        }
        _finishCoinDraw(craps, crapsLvls, fullDays, winners, n, paid, amount);
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

    /// @dev Emits the daily winning-traits event (bonusTargetLevel: see DailyWinningTraits).
    function _emitDailyWinningTraits(
        uint24 questDay,
        uint32 mainTraitsPacked,
        uint32 bonusTraitsPacked,
        uint24 lvl,
        uint24 bonusTargetLevel
    ) private {
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

    /// @dev The day-1 early-bird entries ride bits 144..207 of the same word; payDailyJackpot
    ///      ORs them in after this pack and payEarlyBirdTickets reads and clears them.
    function _packDailyTicketBudgets(
        uint256 dailyEntries,
        uint256 carryoverEntries,
        uint8 carryoverSourceOffset
    ) private pure returns (uint256) {
        return
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
            uint256 dailyEntries,
            uint256 carryoverEntries,
            uint8 carryoverSourceOffset
        )
    {
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
