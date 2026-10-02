// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {JackpotBattleFieldLib} from "../libraries/JackpotBattleFieldLib.sol";

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
import {IDegenerusGameWhaleModule} from "../interfaces/IDegenerusGameModules.sol";
import {IDegenerusJackpots} from "../interfaces/IDegenerusJackpots.sol";

/// @dev Minimal WWXRP surface for the golden-ticket consolation mint. The delegatecall
///      context makes msg.sender the Game, which is a whitelisted WWXRP minter.
interface IWwxrpMintPrize {
    /// @notice Mint WWXRP to a recipient (WWXRP, authorized minters only).
    function mintPrize(address to, uint256 amount) external;
}

import {IJackpotBattle} from "../interfaces/IJackpotBattle.sol";

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
contract DegenerusGameJackpotModule is DegenerusGamePayoutUtils {
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
    uint8 private constant WHALE_PASS_SRC_BAF_DIRECT = 2;
    uint8 private constant WHALE_PASS_SRC_AWARD_TICKETS = 3;
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

    /// @dev Domain separator for per-pull level sampling in level 1's trait-matched FLIP draw.
    bytes32 private constant FLIP_LEVEL_TAG = keccak256("coin-level");

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
    bytes32 private constant FAR_FUTURE_FLIP_TAG = keccak256("far-future-coin");

    /// @dev Most awarded entries one draw call collects: the chunk the battle accepts.
    uint256 private constant JACKPOT_BATTLE_ENTRANTS = JackpotBattleFieldLib.MAX_CHUNK;

    /// @dev Work units each settle call gives the jackpot battle's table resolver.
    uint64 private constant JACKPOT_BATTLE_SETTLE_UNITS = 1_500;

    /// @dev What the call that seals the field charges its own draw, in the same walk units, before
    ///      it settles on the rest: the level snapshot, board batch, seal and comp credit, then each
    ///      drawn entry's reads, write and log. Rounded up from ~496k plus ~44k per entry measured
    ///      at a full chunk, where the dedupe scan is dearest.
    uint256 private constant JACKPOT_DRAW_BASE_UNITS = 110;
    uint256 private constant JACKPOT_DRAW_ENTRY_UNITS = 10;

    /// @dev Most winners of level 1's trait-matched FLIP draw, each paid one equal share.
    uint256 private constant COIN_DRAW_SHARES = 50;

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

        // The gold rush never arms, resolves, or bans on a terminal board.
        uint32 winningTraitsPacked = _rollBoard(rngWord, _NO_QUADRANT_BAN);
        uint8[4] memory traitIds = JackpotBucketLib.unpackWinningTraits(
            winningTraitsPacked
        );
        uint256 effectiveEntropy = _soloAdjustedEntropy(
            traitIds,
            EntropyLib.hash2(rngWord, targetLvl)
        );

        // The winner geometry is always the full-size one, never scaled by the pot: the pot is
        // read from the balance, which anyone can raise once the terminal word is public, and
        // a pot-scaled count would let that choose how many winners are drawn.
        uint16[4] memory bucketCounts = JackpotBucketLib.bucketCountsForPool(
            poolWei == 0 ? 0 : JackpotBucketLib.JACKPOT_SCALE_SECOND_WEI,
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
            // Exact shares, no ticket-unit rounding: terminal winners are paid in ETH, and the
            // pot is read from the balance after the terminal word is public, so rounding to a
            // unit would let a forced-ETH or stETH nudge swing a whole unit between buckets.
            // Zero, written as a runtime value (targetLvl is a uint24, so the shift is always 0):
            // a literal would let the optimizer clone the whole helper for this one call site.
            uint256(targetLvl) >> 24
        );
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
        uint32 winningTraitsPacked = _rollMainTraits(randWord);

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
                // the ticket price), so the daily-ticket credit is unconditional: the budget moves
                // current -> next to back the tickets Phase 2 queues. curPool is still exact:
                // nothing above writes currentPrizePool.
                curPool -= dailyTicketBudget;
                _setCurrentPrizePool(curPool);
                _addNextPrizePool(dailyTicketBudget);

                // Store ticket units for Phase 2 distribution (dailyEntries at bits 8..71). The
                // jackpot battle's pending bit was latched at the request and has already cleared:
                // the battle completes before the daily runs.
                dailyTicketBudgetsPacked = dailyEntries << 8;

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
                    true, // jackpot phase: each quadrant can convert 25% to full passes
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

            _emitDailyWinningTraits(questDay, winningTraitsPacked, lvl, randWord);

            dailyJackpotCoinTicketsPending = true;
            return;
        }

        // Purchase phase path - ETH and ticket legs
        uint8[4] memory traitIds = JackpotBucketLib.unpackWinningTraits(winningTraitsPacked);
        uint256 effectiveEntropy = _soloAdjustedEntropy(
            traitIds,
            EntropyLib.hash2(randWord, lvl)
        );

        _emitDailyWinningTraits(questDay, winningTraitsPacked, lvl, randWord);

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
    /// @dev Called by advanceGame after the pricing and battle advances, with
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
        (, uint32 winningTraitsPacked, ) = _foilDrawFor(uint256(dailyIdx) + 1);
        uint256 entropy = EntropyLib.hash2(randWord, lvl);
        _distributeTicketJackpot(
            lvl,
            lvl,
            winningTraitsPacked,
            entries,
            entropy,
            PURCHASE_PHASE_TICKET_MAX_WINNERS,
            242,
            entropy // the ETH leg's own entropy picks the solo quadrant
        );
        dailyTicketBudgetsPacked = packed & ((uint256(1) << 208) - 1);
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
        if (!dailyJackpotCoinTicketsPending) return;

        uint256 dailyEntries = uint64(dailyTicketBudgetsPacked >> 8);
        uint24 lvl = level;
        uint32 mainTraitsPacked = _rollMainTraits(randWord);

        // --- Ticket Distribution ---
        // Distribute daily tickets to current level trait winners (main traits)
        if (dailyEntries != 0) {
            uint256 entropy = EntropyLib.hash2(randWord, lvl);
            _distributeTicketJackpot(
                lvl,
                lvl + 1,
                mainTraitsPacked,
                dailyEntries,
                entropy,
                TICKET_JACKPOT_MAX_WINNERS,
                241,
                entropy // the ETH leg's own entropy picks the solo quadrant
            );
        }

        // Complete the daily jackpot cycle: the counter advances in the tx that seals the day
        // or ends the level, so the ticket-routing predicate (which keys off the counter under
        // the lock) never sees it ahead of its seal.
        unchecked {
            jackpotCounter += 1;
        }
        dailyJackpotCoinTicketsPending = false;
        dailyTicketBudgetsPacked = 0;
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
        uint256 packed = dailyTicketBudgetsPacked;
        uint24 lvl = level + 1;
        uint32 traits = _rollMainTraits(randWord);
        uint256 soloEntropy = EntropyLib.hash2(randWord, level);
        _distributeTicketJackpot(
            lvl,
            lvl,
            traits,
            uint64(packed >> 144),
            EntropyLib.hash2(randWord, lvl),
            EARLY_BIRD_MAX_WINNERS,
            239,
            soloEntropy
        );
        dailyTicketBudgetsPacked = packed & ((uint256(1) << 144) - 1);
        uint256 halfPasses = earlyBirdWhalePasses;
        if (halfPasses != 0) {
            earlyBirdWhalePasses = 0;
            _awardWhalePass(
                lvl,
                traits,
                halfPasses,
                randWord,
                true,
                _pickSoloQuadrant(JackpotBucketLib.unpackWinningTraits(traits), soloEntropy)
            );
        }
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

    /// @dev Distributes ticket rewards to winners drawn from winning trait pools.
    /// @param sourceLvl Level whose ticket queue supplies candidate winners.
    /// @param queueLvl Level at which the awarded tickets are queued.
    /// @param winningTraitsPacked Packed winning trait IDs for the 4 buckets.
    /// @param entries Total entries backing this draw (converted to whole tickets).
    /// @param entropy RNG state driving winner selection.
    /// @param maxWinners Cap on the draw's total winner count (lowered to the whole tickets the
    ///        budget covers, rounded down to eight, then split across active buckets).
    /// @param saltBase Base salt for per-bucket entropy derivation.
    /// @param soloEntropy The pre-splice value the day's ETH leg fed `_soloAdjustedEntropy`,
    ///        so the solo pick reproduces exactly. The solo quadrant already pays the day's
    ///        headline ETH prize to a single winner, so it is dropped from every ticket draw
    ///        on the board: matching it means the big prize or nothing, never a consolation
    ///        trickle.
    function _distributeTicketJackpot(
        uint24 sourceLvl,
        uint24 queueLvl,
        uint32 winningTraitsPacked,
        uint256 entries,
        uint256 entropy,
        uint16 maxWinners,
        uint8 saltBase,
        uint256 soloEntropy
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
                _pickSoloQuadrant(traitIds, soloEntropy)
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
    ///      - Jackpot phase (isJackpotPhase=true): each bucket converts up to 25% to whole
    ///        whale passes for one fresh winner; the remaining budget pays the ETH draw.
    ///      - Purchase/terminal (isJackpotPhase=false): All buckets paid uniformly.
    ///
    /// @param lvl The level whose winners are being paid.
    /// @param ethPool Total ETH to distribute.
    /// @param entropy VRF-derived random word for winner selection.
    /// @param traitIds The 4 winning trait IDs.
    /// @param shareBps Basis-point share for each of the 4 buckets.
    /// @param bucketCounts Number of holders in each trait bucket.
    /// @param isJackpotPhase True during jackpot phase (all buckets eligible for conversion).
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
            (paidDelta, claimDelta) = _processBucket(
                lvl,
                traitIds[traitIdx],
                traitIdx,
                count,
                share,
                bucketEntropy,
                isJackpotPhase,
                armGold && isJackpotPhase && traitIdx == remainderIdx
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
        return _rollBoard(randWord, _goldenTicketBanQuadrant(goldenTicket, dailyIdx));
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
            if (base < len) cursor.word = _bucketWordAtUnchecked(lvl, trait, base);
        }
        bool redrawn;
        (index, redrawn) = PackedTicketSampleLib.next(cursor, effectiveLen);
        if (index >= len) return (deity, type(uint256).max);
        uint256 word = redrawn ? _bucketWordAtUnchecked(lvl, trait, index) : cursor.word;
        winner = _bucketOwnerFromWordUnchecked(lvl, word, index);
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
        _awardDailyCoinToTraitWinners(
            minLevel,
            maxLevel,
            _rollMainTraits(randWord),
            _calcDailyCoinBudget(lvl, level),
            randWord
        );
    }

    /// @notice One step of the daily jackpot battle, in either phase (see _playJackpotBattle).
    /// @dev Awards are drawn from the far-future queues of [lvl + 1, lvl + 99]; the field and its
    ///      Added were locked at the daily request.
    /// @param lvl The mint ceiling: the draw's levels start above it.
    /// @param randWord The day's recorded VRF word.
    function payPurchaseJackpotBattle(uint24 lvl, uint256 randWord) external {
        _playJackpotBattle(lvl, randWord);
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
            uint8 fullSymId = (trait >> 6) * 8 + (trait & 0x07);
            if (fullSymId < 32) {
                deityCache[t] = deityBySymbol[fullSymId];
            }
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
    ///      one bounded step per call. While the field is open a call draws up to
    ///      JACKPOT_BATTLE_ENTRANTS awarded entries (see _collectJackpotChunk), reads their saved
    ///      boards in one batch and appends them; the chunk that reaches the award target, or finds
    ///      no eligible level, seals the field and settles on whatever of JACKPOT_BATTLE_SETTLE_UNITS
    ///      its own draw left. After that each call settles seats on the full budget. The latch
    ///      clears once the field completes.
    function _playJackpotBattle(uint24 lvl, uint256 rngWord) private {
        IJackpotBattle battle = IJackpotBattle(ContractAddresses.CRAPS);
        (,, bool started, bool complete) = battle.jackpotProgress();
        if (started) {
            if (complete || battle.advanceJackpotBattle(JACKPOT_BATTLE_SETTLE_UNITS)) {
                dailyTicketBudgetsPacked &= ~_JACKPOT_BATTLE_PENDING;
            }
            return;
        }
        uint256 battleWord = uint256(keccak256(abi.encode(rngWord, lvl, FAR_FUTURE_FLIP_TAG)));
        (uint256 word, uint256 cursor, uint256 remaining) = battle.prepareJackpotBattle(lvl, battleWord);
        (address[] memory winners, uint256 next, bool exhausted) = _collectJackpotChunk(lvl, word, cursor, remaining);
        uint256[] memory field = JackpotBattleFieldLib.prepare(winners);
        bool last = exhausted || winners.length == remaining;
        battle.appendJackpotBattle(field, next, last);
        if (!last) return;
        uint256 drawUnits = JACKPOT_DRAW_BASE_UNITS + winners.length * JACKPOT_DRAW_ENTRY_UNITS;
        if (drawUnits < JACKPOT_BATTLE_SETTLE_UNITS
            && battle.advanceJackpotBattle(uint64(JACKPOT_BATTLE_SETTLE_UNITS - drawUnits))) {
            dailyTicketBudgetsPacked &= ~_JACKPOT_BATTLE_PENDING;
        }
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
