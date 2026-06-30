// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {IStETH} from "../interfaces/IStETH.sol";
import {DegenerusGamePayoutUtils} from "./DegenerusGamePayoutUtils.sol";
import {ContractAddresses} from "../ContractAddresses.sol";
import {EntropyLib} from "../libraries/EntropyLib.sol";
import {PriceLookupLib} from "../libraries/PriceLookupLib.sol";
import {JackpotBucketLib} from "../libraries/JackpotBucketLib.sol";
import {IDegenerusJackpots} from "../interfaces/IDegenerusJackpots.sol";

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
        uint256 ticketIndex
    );

    /// @dev Ticket jackpot win. See JackpotEthWin for traitId sentinel semantics.
    ///      ticketCount is a whole-ticket count on all 3 paths and matches the
    ///      quantity queued by the adjacent _queueTickets call. roundedUp is
    ///      true iff the BAF _jackpotTicketRoll (traitId = BAF_TRAIT_SENTINEL)
    ///      Bernoulli sub-roll incremented the whole-ticket count; it is false
    ///      on the two trait-matched paths, which have a zero fractional part
    ///      by construction.
    event JackpotTicketWin(
        address indexed winner,
        uint24 indexed ticketLevel,
        uint16 indexed traitId,
        uint32 ticketCount,
        uint24 sourceLevel,
        uint256 ticketIndex,
        bool roundedUp
    );

    /// @dev FLIP coin win (near-future, trait-matched).
    event JackpotFlipWin(
        address indexed winner,
        uint24 indexed level,
        uint8 indexed traitId,
        uint256 amount,
        uint256 ticketIndex
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

    /// @dev Max forward offset for carryover source selection (lvl+1..lvl+4).
    uint8 private constant DAILY_CARRYOVER_MAX_OFFSET = 4;

    /// @dev Current-pool daily jackpot percentage bounds for days 1-4 (6%-14%).
    uint16 private constant DAILY_CURRENT_BPS_MIN = 600;
    uint16 private constant DAILY_CURRENT_BPS_MAX = 1400;

    /// @dev Portion of purchase-phase reward-pool jackpots converted to loot boxes (3/4).
    uint16 private constant PURCHASE_REWARD_JACKPOT_LOOTBOX_BPS = 7500;

    /// @dev Max winners per single trait bucket (must fit in uint8 for _randTraitTicket).
    ///      Set to 250 to allow all ticket winners in single trait if others are empty.
    uint8 private constant MAX_BUCKET_WINNERS = 250;

    // -------------------------------------------------------------------------
    // Constants — Jackpot Bucket Scaling (Gas Guardrails)
    // -------------------------------------------------------------------------

    /// @dev Maximum ticket winners for purchase phase lootbox distribution.
    /// Higher than ETH winners because ticket distribution is cheaper per winner.
    uint16 private constant PURCHASE_PHASE_TICKET_MAX_WINNERS = 120;

    /// @dev Maximum total ETH winners across daily + carryover jackpots.
    ///      At max scale (6.36x, 200+ ETH pool): 159 + 95 + 50 + 1 = 305.
    uint16 private constant DAILY_ETH_MAX_WINNERS = 305;

    /// @dev Maximum winners for daily coin jackpot (coinflip.creditFlip is 1 external call each).
    uint16 private constant DAILY_COIN_MAX_WINNERS = 50;

    /// @dev Share of daily FLIP budget awarded to far-future ticket holders (25%).
    uint16 private constant FAR_FUTURE_FLIP_BPS = 2500;

    /// @dev Number of far-future levels to sample for FLIP jackpot (10 winners max).
    uint8 private constant FAR_FUTURE_FLIP_SAMPLES = 10;

    /// @dev Domain separator for far-future coin jackpot entropy derivation.
    bytes32 private constant FAR_FUTURE_FLIP_TAG = keccak256("far-future-coin");

    /// @dev Maximum winners for lootbox jackpot distributions (gas safety).
    ///      Lower than the daily ETH winner ceiling because lootboxes do multiple rolls per winner.
    uint16 private constant LOOTBOX_MAX_WINNERS = 100;

    /// @dev Daily jackpot max scale (6.36x) producing bucket counts 159/95/50/1 at 200+ ETH.
    ///      All 305 winners (159 + 95 + 50 + 1) are paid in a single call.
    uint32 private constant DAILY_JACKPOT_SCALE_MAX_BPS = 63_600;

    // =========================================================================
    // External Entry Points (delegatecall targets)
    // =========================================================================

    /// @notice Terminal jackpot for x00 levels: Day-5-style bucket distribution.
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

        uint16[4] memory bucketCounts = JackpotBucketLib.bucketCountsForPoolCap(
            poolWei,
            effectiveEntropy,
            DAILY_ETH_MAX_WINNERS,
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
            false // not jackpot phase
        );
    }

    /// @notice Pays purchase phase jackpots OR rolling daily jackpots at level end.
    /// @dev Called by the parent game contract via delegatecall. Two distinct paths:
    ///
    ///      JACKPOT PHASE PATH (isJackpotPhase=true):
    ///      - Day 1-4: Distributes a random 6%-14% slice of remaining currentPrizePool.
    ///      - Day 5: Distributes 100% of remaining currentPrizePool.
    ///      - Day 1 also runs the early-bird lootbox jackpot (from futurePrizePool).
    ///      - On day 2-4, takes 0.5% of futurePrizePool and buys current-level tickets
    ///        for winners from a random source level in [lvl+1, lvl+4], deposited into nextPool.
    ///      - Increments jackpotCounter on completion.
    ///
    ///      PURCHASE PHASE PATH (isJackpotPhase=false):
    ///      - Triggered during purchase phase when burns occur.
    ///      - Rolls winning traits (random + hero override) and runs trait-based jackpot.
    ///      - Fixed winner counts [20, 12, 6, 1] = 39 ETH winners, up to 120 ticket winners.
    ///      - Adds a 1% futurePrizePool ETH slice every purchase day with 75%
    ///        converted to lootbox tickets and remainder distributed as ETH.
    ///
    /// @param isJackpotPhase True for jackpot phase dailies, false for purchase phase jackpot.
    /// @param lvl Current game level.
    /// @param randWord VRF entropy for winner selection and trait derivation.
    function payDailyJackpot(
        bool isJackpotPhase,
        uint24 lvl,
        uint256 randWord
    ) external {
        uint24 questDay = _simulatedDayIndex();
        // One hero pass serves both rolls: main and bonus traits share the same
        // (quadrant, symbol) hero result within a single resolution.
        (
            uint32 winningTraitsPacked,
            uint32 bonusTraitsPacked
        ) = _rollWinningTraitsPair(randWord);

        if (isJackpotPhase) {
            uint256 dailyEthBudget;
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

                // Run the early-bird lootbox jackpot on day 1 only.
                // This day replaces the normal daily carryover flow.
                if (isEarlyBirdDay) {
                    _runEarlyBirdLootboxJackpot(lvl + 1, randWord);
                }

                // Gas optimization: 20% = 1/5 (cheaper than * 2000 / 10000)
                uint256 dailyLootboxBudget = budget / 5;
                if (dailyLootboxBudget != 0) {
                    budget -= dailyLootboxBudget;
                }

                // Calculate daily ticket units (distributed in Phase 2 via payDailyJackpotCoinAndTickets)
                uint256 dailyTicketUnits = _budgetToTicketUnits(
                    dailyLootboxBudget,
                    lvl + 1
                );
                if (dailyTicketUnits != 0) {
                    // Deduct from current pool and add to next pool to back tickets.
                    // curPool is still exact: nothing above writes currentPrizePool.
                    curPool -= dailyLootboxBudget;
                    _setCurrentPrizePool(curPool);
                    _addNextPrizePool(dailyLootboxBudget);
                }

                uint8 sourceLevelOffset;
                uint24 sourceLevel;
                uint256 reserveSlice;
                uint256 carryoverTicketUnits;
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

                    // 0.5% of futurePrizePool reserved for carryover tickets,
                    // moved future -> next in one packed-slot read/write.
                    (uint128 nextBal, uint128 futPool) = _getPrizePools();
                    reserveSlice = uint256(futPool) / 200;
                    _setPrizePools(
                        nextBal + uint128(reserveSlice),
                        futPool - uint128(reserveSlice)
                    );
                    carryoverTicketUnits = _budgetToTicketUnits(
                        reserveSlice,
                        lvl
                    );
                }

                // Store ticket units for Phase 2 distribution
                // Packing: [counterStep (8 bits)] [dailyTicketUnits (64 bits @ 8)]
                // [carryoverTicketUnits (64 bits @ 72)] [carryoverSourceOffset (8 bits @ 136)]
                dailyTicketBudgetsPacked = _packDailyTicketBudgets(
                    counterStep,
                    dailyTicketUnits,
                    carryoverTicketUnits,
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

            if (dailyEthBudget != 0) {
                uint16[4] memory bucketCountsDaily = JackpotBucketLib
                    .bucketCountsForPoolCap(
                        dailyEthBudget,
                        effectiveEntropyDaily,
                        DAILY_ETH_MAX_WINNERS,
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
                    true // jackpot phase (solo bucket gets whale pass)
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
        uint256 lootboxBudget;
        if (ethPool != 0) {
            lootboxBudget = (ethPool * PURCHASE_REWARD_JACKPOT_LOOTBOX_BPS) / 10_000;
            if (lootboxBudget != 0) ethPool -= lootboxBudget;
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
                false // not jackpot phase
            );
        }

        // Deferred deduction: deduct only what was actually consumed.
        // futureBal is still exact: nothing above writes prizePoolsPacked
        // (purchase-phase distribution never reaches the solo whale-pass leg).
        if (ethDaySlice != 0) {
            _setFuturePrizePool(futureBal - lootboxBudget - paidEth);
        }

        if (lootboxBudget != 0) {
            _distributeLootboxAndTickets(
                lvl,
                winningTraitsPacked,
                lootboxBudget,
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
            uint256 dailyTicketUnits,
            uint256 carryoverTicketUnits,
            uint8 carryoverSourceOffset
        ) = _unpackDailyTicketBudgets(dailyTicketBudgetsPacked);

        // Derive traits inline from randWord; one hero pass serves both rolls.
        uint24 lvl = level;
        (
            uint32 mainTraitsPacked,
            uint32 bonusTraitsPacked
        ) = _rollWinningTraitsPair(randWord);

        // --- Coin Jackpot ---
        _runFlipJackpot(lvl, lvl, lvl + 1, lvl + 4, bonusTraitsPacked, randWord);

        // --- Ticket Distribution ---
        // Distribute daily tickets to current level trait winners (main traits)
        if (dailyTicketUnits != 0) {
            _distributeTicketJackpot(
                lvl,
                lvl + 1,
                mainTraitsPacked,
                dailyTicketUnits,
                EntropyLib.hash2(randWord, lvl),
                LOOTBOX_MAX_WINNERS,
                241
            );
        }

        uint8 counterCached = jackpotCounter;

        // Distribute carryover tickets: winners from source level, tickets at current level
        // (or lvl+1 on final day since current level is about to end). Uses bonus traits.
        if (carryoverTicketUnits != 0) {
            uint24 sourceLevel = lvl + uint24(carryoverSourceOffset);
            bool isFinalDay = counterCached + counterStep >= JACKPOT_LEVEL_CAP;
            _distributeTicketJackpot(
                sourceLevel,
                isFinalDay ? lvl + 1 : lvl,
                bonusTraitsPacked,
                carryoverTicketUnits,
                EntropyLib.hash2(randWord, sourceLevel),
                LOOTBOX_MAX_WINNERS,
                240
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

    /// @dev Execute the early-bird lootbox jackpot from the unified future pool.
    ///      Routes through the shared ticket distributor so the budget→ticket
    ///      conversion (`_budgetToTicketUnits`, the same 4-entries-per-ticket basis
    ///      every other jackpot path uses) and the winner cap match the daily and
    ///      purchase-phase jackpots: `cap = min(ticketUnits, 100)` gives every drawn
    ///      winner >=1 unit (replacing the fixed-100 split that floored sub-100-ticket
    ///      budgets to zero), with the exact base+remainder rotation keeping the award
    ///      fully backed. Winners drawn from `traitBurnTicket[lvl]`, tickets queued at
    ///      `lvl` (= outer level + 1). The full 3% budget always moves future→next.
    function _runEarlyBirdLootboxJackpot(uint24 lvl, uint256 rngWord) private {
        (uint128 nextBal, uint128 futureBal) = _getPrizePools();
        uint256 totalBudget = (uint256(futureBal) * 300) / 10_000; // 3%
        if (totalBudget == 0) return;

        uint256 ticketUnits = _budgetToTicketUnits(totalBudget, lvl);
        if (ticketUnits != 0) {
            _distributeTicketJackpot(
                lvl,
                lvl,
                _rollWinningTraits(rngWord, true),
                ticketUnits,
                EntropyLib.hash2(rngWord, lvl),
                LOOTBOX_MAX_WINNERS,
                239
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
    function _budgetToTicketUnits(
        uint256 budget,
        uint24 lvl
    ) private pure returns (uint256) {
        uint256 ticketPrice = PriceLookupLib.priceForLevel(lvl);
        return (budget << 2) / ticketPrice;
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

    /// @dev Distributes lootbox budget to next pool and tickets to trait winners.
    /// @param ticketConversionBps Fraction of budget used for ticket calculation (10000 = 100%).
    ///        Full budget always flows to nextPrizePool regardless of this parameter.
    function _distributeLootboxAndTickets(
        uint24 lvl,
        uint32 winningTraitsPacked,
        uint256 lootboxBudget,
        uint256 randWord,
        uint16 ticketConversionBps
    ) private {
        // Add lootbox budget to nextPrizePool
        _addNextPrizePool(lootboxBudget);

        // Distribute tickets to winners (may use reduced basis for backing ratio)
        uint256 ticketBasis = (lootboxBudget * ticketConversionBps) / 10_000;
        uint256 ticketUnits = _budgetToTicketUnits(ticketBasis, lvl + 1);
        if (ticketUnits != 0) {
            _distributeTicketJackpot(
                lvl,
                lvl + 1,
                winningTraitsPacked,
                ticketUnits,
                EntropyLib.hash2(randWord, lvl),
                PURCHASE_PHASE_TICKET_MAX_WINNERS,
                242
            );
        }
    }

    /// @dev Distributes ticket rewards to winners drawn from winning trait pools.
    function _distributeTicketJackpot(
        uint24 sourceLvl,
        uint24 queueLvl,
        uint32 winningTraitsPacked,
        uint256 ticketUnits,
        uint256 entropy,
        uint16 maxWinners,
        uint8 saltBase
    ) private {
        if (ticketUnits == 0) return;

        uint8[4] memory traitIds = JackpotBucketLib.unpackWinningTraits(
            winningTraitsPacked
        );
        uint16 cap = maxWinners;
        if (ticketUnits < cap) cap = uint16(ticketUnits);

        (
            uint16[4] memory counts,
            uint8 activeCount,
            uint256[4] memory lens,
            address[4] memory deities
        ) = _computeBucketCounts(sourceLvl, traitIds, cap, entropy);
        if (activeCount == 0) return;

        _distributeTicketsToBuckets(
            sourceLvl,
            queueLvl,
            traitIds,
            counts,
            lens,
            deities,
            ticketUnits,
            entropy,
            cap,
            saltBase
        );
    }

    /// @dev Distributes tickets across all buckets. `lens`/`deities` carry the
    ///      per-trait bucket lengths and deity addresses read once by
    ///      _computeBucketCounts (stable for the whole distribution: nothing on
    ///      this path writes traitBurnTicket or deityBySymbol).
    function _distributeTicketsToBuckets(
        uint24 sourceLvl,
        uint24 queueLvl,
        uint8[4] memory traitIds,
        uint16[4] memory counts,
        uint256[4] memory lens,
        address[4] memory deities,
        uint256 ticketUnits,
        uint256 entropy,
        uint16 cap,
        uint8 saltBase
    ) private {
        uint256 baseUnits = ticketUnits / cap;
        uint256 distParams = (ticketUnits % cap) | ((entropy % cap) << 128);
        uint256 globalIdx;

        for (uint8 traitIdx; traitIdx < 4; ) {
            if (counts[traitIdx] != 0) {
                entropy = uint256(
                    keccak256(abi.encode(entropy, traitIdx, ticketUnits))
                );
                globalIdx = _distributeTicketsToBucket(
                    sourceLvl,
                    queueLvl,
                    traitIds[traitIdx],
                    counts[traitIdx],
                    entropy,
                    uint8(saltBase + traitIdx),
                    baseUnits,
                    distParams,
                    cap,
                    globalIdx,
                    lens[traitIdx],
                    deities[traitIdx]
                );
            }
            unchecked {
                ++traitIdx;
            }
        }
    }

    /// @dev Distributes tickets to winners in a single bucket.
    function _distributeTicketsToBucket(
        uint24 sourceLvl,
        uint24 queueLvl,
        uint8 traitId,
        uint16 count,
        uint256 entropy,
        uint8 salt,
        uint256 baseUnits,
        uint256 distParams,
        uint16 cap,
        uint256 startIdx,
        uint256 bucketLen,
        address deity
    ) private returns (uint256 endIdx) {
        (
            address[] memory winners,
            uint256[] memory ticketIndexes
        ) = _randTraitTicket(
                traitBurnTicket[sourceLvl],
                entropy,
                traitId,
                uint8(count),
                salt,
                bucketLen,
                deity
            );

        uint256 extra = distParams & type(uint128).max;
        uint256 offset = distParams >> 128;
        uint256 len = winners.length;
        uint256 cursor = (startIdx + offset) % cap;
        for (uint256 i; i < len; ) {
            address winner = winners[i];
            uint256 units = baseUnits;
            if (extra != 0 && cursor < extra) {
                units += 1;
            }
            if (winner != address(0) && units != 0) {
                _queueTickets(winner, queueLvl, uint32(units), true);
                // ticketCount carries the entries count awarded (price/4 units;
                // _budgetToTicketUnits already returns entries).
                emit JackpotTicketWin(
                    winner,
                    queueLvl,
                    traitId,
                    uint32(units),
                    sourceLvl,
                    ticketIndexes[i],
                    false
                );
            }
            unchecked {
                ++cursor;
                if (cursor == cap) cursor = 0;
                ++startIdx;
                ++i;
            }
        }
        return startIdx;
    }

    /// @dev Computes bucket winner counts for active trait buckets (including virtual deity entries).
    ///      Also returns each trait's bucket length and deity address so the
    ///      distribution loop reuses them instead of re-reading storage.
    function _computeBucketCounts(
        uint24 lvl,
        uint8[4] memory traitIds,
        uint16 maxWinners,
        uint256 entropy
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
            uint256 len = traitBurnTicket[lvl][trait].length;
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

    // =========================================================================
    // Daily Jackpot ETH — Distribution
    // =========================================================================

    /// @dev Unified ETH distribution across trait buckets. All buckets are paid
    ///      in a single call (the full DAILY_ETH_MAX_WINNERS ceiling).
    ///
    ///      JACKPOT PHASE vs PURCHASE/TERMINAL:
    ///      - Jackpot phase (isJackpotPhase=true): Solo bucket gets whale pass + DGNRS on final day.
    ///      - Purchase/terminal (isJackpotPhase=false): All buckets paid uniformly.
    ///
    /// @param lvl The level whose winners are being paid.
    /// @param ethPool Total ETH to distribute.
    /// @param entropy VRF-derived random word for winner selection.
    /// @param traitIds The 4 winning trait IDs.
    /// @param shareBps Basis-point share for each of the 4 buckets.
    /// @param bucketCounts Number of holders in each trait bucket.
    /// @param isJackpotPhase True during jackpot phase (solo bucket gets whale pass).
    /// @return paidEth Total ETH actually paid out in this call.
    function _processDailyEth(
        uint24 lvl,
        uint256 ethPool,
        uint256 entropy,
        uint8[4] memory traitIds,
        uint16[4] memory shareBps,
        uint16[4] memory bucketCounts,
        bool isJackpotPhase
    ) private returns (uint256 paidEth) {
        if (ethPool == 0) {
            return 0;
        }

        uint256 unit = PriceLookupLib.priceForLevel(lvl + 1) >> 2;
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
                isJackpotPhase && traitIdx == remainderIdx
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
    ///      whale-pass + final-day DGNRS handler; every other bucket pays 100% ETH.
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
        bool isSolo
    ) private returns (uint256 paidDelta, uint256 claimDelta, uint256 newEntropy) {
        newEntropy = entropy;

        uint16 totalCount = count;
        if (totalCount > MAX_BUCKET_WINNERS) totalCount = MAX_BUCKET_WINNERS;

        (
            address[] memory winners,
            uint256[] memory ticketIndexes
        ) = _randTraitTicket(
                traitBurnTicket[lvl],
                newEntropy,
                traitId,
                uint8(totalCount),
                uint8(200 + traitIdx)
            );
        if (winners.length == 0) return (0, 0, newEntropy);

        uint256 perWinner = share / totalCount;
        if (perWinner == 0) return (0, 0, newEntropy);

        if (isSolo) {
            // Solo bucket (jackpot phase): whale pass + DGNRS on final day
            address w = winners[0];
            if (w != address(0)) {
                (claimDelta, paidDelta, newEntropy) = _handleSoloBucketWinner(
                    w, lvl, traitId, ticketIndexes[0],
                    perWinner, newEntropy
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
        uint256 entropy
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

    /// @dev Replaces the winning quadrant's trait with a hero-symbol override sampled by
    ///      `_rollHeroSymbol` from the prior day's settled wager pool. Applied to all jackpot
    ///      paths (purchase phase + jackpot phase). Reads `dailyHeroWagers[dailyIdx]`:
    ///      `dailyIdx` is written only at `_unlockRng` (AdvanceModule), so during jackpot
    ///      processing it is frozen at the previous day's index — every consumer in a single
    ///      jackpot resolution therefore reads the same wager pool. Bets placed on day D
    ///      write to `dailyHeroWagers[D]`; day D+1's jackpot reads slot[D] via
    ///      `dailyIdx == D` (set by day D's `_unlockRng`).
    ///
    ///      `heroEntropy` is the raw VRF entropy word for the day; the same value flows into
    ///      every `_applyHeroOverride` invocation within a jackpot resolution, so on days
    ///      that produce both regular and bonus trait rolls both rolls land on the same hero
    ///      `(quadrant, symbol)` pair (only the per-quadrant colors differ, sampled from
    ///      `randomWord`). Symbol entropy and color entropy live in orthogonal domains:
    ///      colors read bit-slices of `randomWord`; the symbol roll consumes
    ///      `keccak256(abi.encode(heroEntropy, day))`.
    function _applyHeroOverride(
        uint8[4] memory w,
        uint256 randomWord,
        uint256 heroEntropy
    ) private view {
        (
            bool hasHeroWinner,
            uint8 heroQuadrant,
            uint8 heroSymbol
        ) = _rollHeroSymbol(dailyIdx, heroEntropy, _NO_HERO_EXCLUDE);
        _applyHeroResult(w, randomWord, hasHeroWinner, heroQuadrant, heroSymbol);
    }

    /// @dev Applies a resolved hero (quadrant, symbol) to a trait set, sampling
    ///      the winning quadrant's color from `randomWord` (the per-roll word, so
    ///      colors stay independent across rolls that share one hero result).
    function _applyHeroResult(
        uint8[4] memory w,
        uint256 randomWord,
        bool hasHeroWinner,
        uint8 heroQuadrant,
        uint8 heroSymbol
    ) private pure {
        if (!hasHeroWinner) return;

        uint8 heroColor;
        if (heroQuadrant == 0) {
            heroColor = uint8(randomWord & 7);
        } else if (heroQuadrant == 1) {
            heroColor = uint8((randomWord >> 3) & 7);
        } else if (heroQuadrant == 2) {
            heroColor = uint8((randomWord >> 6) & 7);
        } else {
            heroColor = uint8((randomWord >> 9) & 7);
        }

        w[heroQuadrant] = uint8(
            (uint256(heroQuadrant) << 6) |
                (uint256(heroColor) << 3) |
                uint256(heroSymbol)
        );
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
    function _rollHeroSymbol(
        uint24 day,
        uint256 entropy,
        uint8 excludeIdx
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
        address[][256] storage traitBurnTicket_,
        uint256 randomWord,
        uint8 trait,
        uint8 numWinners,
        uint8 salt
    )
        private
        view
        returns (address[] memory winners, uint256[] memory ticketIndexes)
    {
        uint256 len = traitBurnTicket_[trait].length;

        // traitId layout: (quadrant << 6) | (color << 3) | symIdx
        // fullSymId = quadrant * 8 + symIdx
        uint8 fullSymId = (trait >> 6) * 8 + (trait & 0x07);
        address deity;
        if (fullSymId < 32) {
            deity = deityBySymbol[fullSymId];
        }

        return
            _randTraitTicket(
                traitBurnTicket_,
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
        address[][256] storage traitBurnTicket_,
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
        address[] storage holders = traitBurnTicket_[trait];
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
    /// @dev Runs every day in its own transaction. Awards 0.5% of prize pool target in FLIP.
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
        uint24 questDay = _simulatedDayIndex();
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
    ///      and rotates trait deterministically via i % 4. Each pull awards the floored
    ///      whole-FLIP `baseAmount` (1 FLIP = 1 ether); empty (lvl', trait_i) buckets
    ///      silently skip. Sub-1-FLIP residues — the `coinBudget % cap` remainder and any
    ///      sub-1-ether base — evaporate.
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
        uint16 cap = DAILY_COIN_MAX_WINNERS;
        if (cap > coinBudget) cap = uint16(coinBudget);

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

        uint256 baseAmount = ((coinBudget / cap) / 1 ether) * 1 ether;
        // Sub-1-FLIP per-pull budget: every pull would award 0, so the
        // selection loop has no effect — skip it entirely.
        if (baseAmount == 0) return;
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

            address[] storage holders = traitBurnTicket[lvlPrime][trait_i];
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

            uint256 amount = baseAmount;

            if (winner != address(0) && amount != 0) {
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
    ///      that level's ticketQueue (traits not yet assigned), and splits the budget evenly.
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

        // Distribute evenly among found winners, floored to whole-FLIP
        // (1 FLIP = 1 ether); sub-1-FLIP residue evaporates.
        uint256 perWinner = ((farBudget / found) / 1 ether) * 1 ether;
        if (perWinner == 0) return;

        address[] memory batchPlayers = new address[](found);
        uint256[] memory batchAmounts = new uint256[](found);

        for (uint8 i; i < found; ) {
            emit FarFutureFlipJackpotWinner(
                winners[i],
                lvl,
                winnerLevels[i],
                perWinner
            );

            batchPlayers[i] = winners[i];
            batchAmounts[i] = perWinner;

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
            _applyHeroOverride(mTraits, randWord, randWord);
            return JackpotBucketLib.packWinningTraits(mTraits);
        }
        // Bonus draw — base off the salted word, with its own hero rolled off the
        // salted word excluding the main hero's slot (main hero off the unsalted
        // word, matching _rollWinningTraitsPair so both producers agree).
        uint256 r = EntropyLib.hash2(randWord, uint256(BONUS_TRAITS_TAG));
        uint8[4] memory traits = JackpotBucketLib.getRandomTraits(r);
        (bool mHas, uint8 mQ, uint8 mS) = _rollHeroSymbol(
            dailyIdx,
            randWord,
            _NO_HERO_EXCLUDE
        );
        uint8 excl = mHas ? ((mQ << 3) | mS) : _NO_HERO_EXCLUDE;
        (bool bHas, uint8 bQ, uint8 bS) = _rollHeroSymbol(dailyIdx, r, excl);
        _applyHeroResult(traits, r, bHas, bQ, bS);
        packed = JackpotBucketLib.packWinningTraits(traits);
    }

    /// @dev Rolls main and bonus winning traits from one VRF word. The main draw
    ///      rolls its hero off the unsalted word; the bonus draw rolls its OWN hero
    ///      off the salted word with the main hero's slot excluded, so the two
    ///      heroes never coincide (an empty post-exclusion pool yields no bonus
    ///      hero). Base traits and hero colors derive from each roll's own word
    ///      (main: randWord; bonus: keccak-salted with BONUS_TRAITS_TAG).
    function _rollWinningTraitsPair(
        uint256 randWord
    ) private view returns (uint32 mainPacked, uint32 bonusPacked) {
        (
            bool hasHeroWinner,
            uint8 heroQuadrant,
            uint8 heroSymbol
        ) = _rollHeroSymbol(dailyIdx, randWord, _NO_HERO_EXCLUDE);

        uint8[4] memory traits = JackpotBucketLib.getRandomTraits(randWord);
        _applyHeroResult(traits, randWord, hasHeroWinner, heroQuadrant, heroSymbol);
        mainPacked = JackpotBucketLib.packWinningTraits(traits);

        uint256 rBonus = EntropyLib.hash2(randWord, uint256(BONUS_TRAITS_TAG));
        traits = JackpotBucketLib.getRandomTraits(rBonus);
        // The bonus draw rolls its own hero off the salted word, excluding the
        // main hero's slot so the two heroes can never coincide. An empty pool
        // (the main had no hero) yields no bonus hero either.
        uint8 excl = hasHeroWinner
            ? ((heroQuadrant << 3) | heroSymbol)
            : _NO_HERO_EXCLUDE;
        (bool bHas, uint8 bQ, uint8 bS) = _rollHeroSymbol(dailyIdx, rBonus, excl);
        _applyHeroResult(traits, rBonus, bHas, bQ, bS);
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

    /// @dev Calculate 0.5% of prize pool target in FLIP.
    /// @param lvl Level keying the prize pool snapshot (purchase level on the
    ///        payDailyFlipJackpot path, where it differs from the current level).
    /// @param currLevel Current game level, used for FLIP pricing.
    function _calcDailyCoinBudget(
        uint24 lvl,
        uint24 currLevel
    ) private view returns (uint256) {
        uint256 priceWei = PriceLookupLib.priceForLevel(currLevel);
        if (priceWei == 0) return 0;
        return (levelPrizePool[lvl - 1] * PRICE_COIN_UNIT) / (priceWei * 200);
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
        uint256 dailyTicketUnits,
        uint256 carryoverTicketUnits,
        uint8 carryoverSourceOffset
    ) private pure returns (uint256) {
        return
            uint256(counterStep) |
            (dailyTicketUnits << 8) |
            (carryoverTicketUnits << 72) |
            (uint256(carryoverSourceOffset) << 136);
    }

    function _unpackDailyTicketBudgets(
        uint256 packed
    )
        private
        pure
        returns (
            uint8 counterStep,
            uint256 dailyTicketUnits,
            uint256 carryoverTicketUnits,
            uint8 carryoverSourceOffset
        )
    {
        counterStep = uint8(packed);
        dailyTicketUnits = uint64(packed >> 8);
        carryoverTicketUnits = uint64(packed >> 72);
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
                        lvl,
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
                (rngWord, cd) = _awardJackpotTickets(winner, amount, lvl, rngWord);
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

        uint256 quantityScaled = (amount * TICKET_SCALE) / targetPrice;

        // Bernoulli-collapse the scaled count to a whole-ticket count: the
        // fractional part rounds up with probability frac/TICKET_SCALE using
        // bits[96..127] of the per-roll entropy word — a uint32 window, wide enough
        // that the % TICKET_SCALE modulo bias is negligible (~2e-8).
        uint32 scaledTickets = uint32(quantityScaled);
        uint32 whole = scaledTickets / uint32(TICKET_SCALE);
        uint32 frac = scaledTickets % uint32(TICKET_SCALE);
        bool roundedUp = false;
        if (frac != 0 && (uint32(entropy >> 96) % uint32(TICKET_SCALE)) < frac) {
            unchecked {
                whole += 1;
            }
            roundedUp = true;
        }
        _queueTickets(winner, targetLevel, wholeTicketsToEntries(whole), true);

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
