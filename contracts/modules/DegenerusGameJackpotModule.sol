// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {IDegenerusCoin} from "../interfaces/IDegenerusCoin.sol";
import {IBurnieCoinflip} from "../interfaces/IBurnieCoinflip.sol";
import {IDegenerusQuests} from "../interfaces/IDegenerusQuests.sol";
import {IStakedDegenerusStonk} from "../interfaces/IStakedDegenerusStonk.sol";
import {IStETH} from "../interfaces/IStETH.sol";
import {DegenerusGamePayoutUtils} from "./DegenerusGamePayoutUtils.sol";
import {DegenerusTraitUtils} from "../DegenerusTraitUtils.sol";
import {ContractAddresses} from "../ContractAddresses.sol";
import {EntropyLib} from "../libraries/EntropyLib.sol";
import {PriceLookupLib} from "../libraries/PriceLookupLib.sol";
import {JackpotBucketLib} from "../libraries/JackpotBucketLib.sol";
import {IDegenerusJackpots} from "../interfaces/IDegenerusJackpots.sol";
import {IDegenerusGame} from "../interfaces/IDegenerusGame.sol";

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
 *      3. `payDailyCoinJackpot` — BURNIE jackpot distribution to near-future ticket holders.
 *
 *      FUND ACCOUNTING:
 *      - ETH flows through `futurePrizePool` (unified reserve), `currentPrizePool`,
 *        `nextPrizePool`, `claimablePool`.
 *      - The remainder goes to the entropy-selected solo bucket.
 *      - `claimableWinnings` tracks per-player ETH; `claimablePool` is the aggregate liability.
 *
 *      RANDOMNESS:
 *      - All entropy originates from VRF words passed by the parent contract.
 *      - EntropyLib.entropyStep provides deterministic derivation for sub-selections.
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

    /// @dev Emitted when a far-future ticket holder (5-99 levels ahead) wins the daily BURNIE jackpot.
    ///      These winners are drawn from ticketQueue (traits not yet assigned).
    event FarFutureCoinJackpotWinner(
        address indexed winner,
        uint24 indexed currentLevel,
        uint24 indexed winnerLevel,
        uint256 amount
    );

    /// @dev ETH jackpot win. rebuyLevel/rebuyTickets are 0 when auto-rebuy didn't fire.
    event JackpotEthWin(
        address indexed winner,
        uint24 indexed level,
        uint8 indexed traitId,
        uint256 amount,
        uint256 ticketIndex,
        uint24 rebuyLevel,
        uint32 rebuyTickets
    );

    /// @dev Ticket jackpot win.
    event JackpotTicketWin(
        address indexed winner,
        uint24 indexed ticketLevel,
        uint8 indexed traitId,
        uint32 ticketCount,
        uint24 sourceLevel,
        uint256 ticketIndex
    );

    /// @dev BURNIE coin win (near-future, trait-matched).
    event JackpotBurnieWin(
        address indexed winner,
        uint24 indexed level,
        uint8 indexed traitId,
        uint256 amount,
        uint256 ticketIndex
    );

    /// @dev Emitted once per daily drawing with both main and bonus winning traits.
    event DailyWinningTraits(
        uint32 indexed day,
        uint32 mainTraitsPacked,
        uint32 bonusTraitsPacked,
        uint24 bonusTargetLevel
    );

    /// @dev DGNRS reward to solo bucket winner on final day.
    event JackpotDgnrsWin(address indexed winner, uint256 amount);

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
    bytes32 private constant COIN_JACKPOT_TAG = keccak256("coin-jackpot");

    /// @dev Domain separator for rolling current-pool daily jackpot percentage.
    bytes32 private constant DAILY_CURRENT_BPS_TAG =
        keccak256("daily-current-bps");

    /// @dev Domain separator for selecting daily carryover source level.
    bytes32 private constant DAILY_CARRYOVER_SOURCE_TAG =
        keccak256("daily-carryover-source");

    /// @dev Domain separator for bonus trait derivation from same VRF word.
    bytes32 private constant BONUS_TRAITS_TAG = keccak256("BONUS_TRAITS");

    /// @dev Max forward offset for carryover source selection (lvl+1..lvl+4).
    uint8 private constant DAILY_CARRYOVER_MAX_OFFSET = 4;

    /// @dev Current-pool daily jackpot percentage bounds for days 1-4 (6%-14%).
    uint16 private constant DAILY_CURRENT_BPS_MIN = 600;
    uint16 private constant DAILY_CURRENT_BPS_MAX = 1400;

    // -------------------------------------------------------------------------
    // Constants — Split Mode (ETH Distribution)
    // -------------------------------------------------------------------------

    /// @dev All 4 buckets in a single call; no resumeEthPool write.
    uint8 private constant SPLIT_NONE = 0;
    /// @dev Call 1: largest + solo buckets only; writes resumeEthPool for call 2.
    uint8 private constant SPLIT_CALL1 = 1;
    /// @dev Call 2: mid buckets only; reads and clears resumeEthPool.
    uint8 private constant SPLIT_CALL2 = 2;

    /// @dev Portion of DGNRS reward pool paid to the day-5 solo bucket winner (1%).
    uint16 private constant FINAL_DAY_DGNRS_BPS = 100;

    /// @dev Portion of purchase-phase reward-pool jackpots converted to loot boxes (3/4).
    uint16 private constant PURCHASE_REWARD_JACKPOT_LOOTBOX_BPS = 7500;

    /// @dev Max winners per single trait bucket (must fit in uint8 for _randTraitTicket).
    ///      Set to 250 to allow all ticket winners in single trait if others are empty.
    uint8 private constant MAX_BUCKET_WINNERS = 250;

    // -------------------------------------------------------------------------
    // Constants — Jackpot Bucket Scaling (Gas Guardrails)
    // -------------------------------------------------------------------------

    /// @dev Maximum total winners per daily jackpot payout (including solo bucket).
    /// Also serves as the skip-split threshold for daily jackpots.
    uint16 private constant JACKPOT_MAX_WINNERS = 160;

    /// @dev Maximum ticket winners for purchase phase lootbox distribution.
    /// Higher than ETH winners because ticket distribution is cheaper per winner.
    uint16 private constant PURCHASE_PHASE_TICKET_MAX_WINNERS = 120;

    /// @dev Maximum total ETH winners across daily + carryover jackpots.
    ///      At max scale (6.36x, 200+ ETH pool): 159 + 95 + 50 + 1 = 305.
    uint16 private constant DAILY_ETH_MAX_WINNERS = 305;

    /// @dev Maximum winners for daily coin jackpot (coinflip.creditFlip is 1 external call each).
    uint16 private constant DAILY_COIN_MAX_WINNERS = 50;

    /// @dev Salt base for daily coin jackpot winner selection.
    uint8 private constant DAILY_COIN_SALT_BASE = 252;

    /// @dev Share of daily BURNIE budget awarded to far-future ticket holders (25%).
    uint16 private constant FAR_FUTURE_COIN_BPS = 2500;

    /// @dev Number of far-future levels to sample for BURNIE jackpot (10 winners max).
    uint8 private constant FAR_FUTURE_COIN_SAMPLES = 10;

    /// @dev Domain separator for far-future coin jackpot entropy derivation.
    bytes32 private constant FAR_FUTURE_COIN_TAG = keccak256("far-future-coin");

    /// @dev Maximum winners for lootbox jackpot distributions (gas safety).
    ///      Lower than JACKPOT_MAX_WINNERS because lootboxes do multiple rolls per winner.
    uint16 private constant LOOTBOX_MAX_WINNERS = 100;

    /// @dev Daily jackpot max scale (6.36x) producing bucket counts 159/95/50/1 at 200+ ETH.
    ///      Two-call split: call 1 processes largest (159) + solo (1) = 160 winners,
    ///      call 2 processes mid buckets (95 + 50) = 145 winners.
    uint32 private constant DAILY_JACKPOT_SCALE_MAX_BPS = 63_600;

    // -------------------------------------------------------------------------
    // Structs
    // -------------------------------------------------------------------------

    /// @dev Mutable context passed through ETH distribution loops to track cumulative state.
    ///      Using a struct avoids stack-too-deep and makes the flow explicit.
    /// @dev Packed parameters for a single jackpot execution. Keeps external call surface lean
    ///      and avoids passing 6+ parameters through multiple internal functions.
    struct JackpotParams {
        uint24 lvl; // Current game level (1-indexed).
        uint256 ethPool; // ETH available for this jackpot.
        uint256 entropy; // VRF-derived entropy for winner selection.
        uint32 winningTraitsPacked; // 4 trait IDs packed into 32 bits (8 bits each).
        uint64 traitShareBpsPacked; // 4 share percentages packed (16 bits each).
    }

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
        uint256 entropy = rngWord ^ (uint256(targetLvl) << 192);
        uint8[4] memory traitIds = JackpotBucketLib.unpackWinningTraits(
            winningTraitsPacked
        );

        uint16[4] memory bucketCounts = JackpotBucketLib.bucketCountsForPoolCap(
            poolWei,
            entropy,
            DAILY_ETH_MAX_WINNERS,
            DAILY_JACKPOT_SCALE_MAX_BPS
        );
        uint16[4] memory shareBps = JackpotBucketLib.shareBpsByBucket(
            FINAL_DAY_SHARES_PACKED,
            uint8(entropy & 3)
        );

        paidWei = _processDailyEth(
            targetLvl,
            poolWei,
            entropy,
            traitIds,
            shareBps,
            bucketCounts,
            false, // not final day
            SPLIT_NONE,
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
    ///      - At level 1+: adds a 1% futurePrizePool ETH slice every purchase day
    ///        with 75% converted to lootbox tickets and remainder distributed as ETH.
    ///      - Level 0: no ETH distribution (BURNIE/ticket rewards only).
    ///
    /// @param isJackpotPhase True for jackpot phase dailies, false for purchase phase jackpot.
    /// @param lvl Current game level.
    /// @param randWord VRF entropy for winner selection and trait derivation.
    function payDailyJackpot(
        bool isJackpotPhase,
        uint24 lvl,
        uint256 randWord
    ) external {
        uint32 questDay = _simulatedDayIndex();
        uint32 winningTraitsPacked;

        if (isJackpotPhase) {
            // Resume check: call 2 of two-call daily ETH split.
            if (resumeEthPool != 0) {
                _resumeDailyEth(lvl, randWord);
                return;
            }

            winningTraitsPacked = _rollWinningTraits(randWord, false);

            uint256 dailyEthBudget;
            {
                uint8 counter = jackpotCounter;
                uint8 counterStep = 1;
                // Turbo (flag=2): all 5 logical days in 1 physical day.
                // Compressed (flag=1): 5 logical days in 3 physical days.
                if (compressedJackpotFlag == 2 && counter == 0) {
                    counterStep = JACKPOT_LEVEL_CAP;
                } else if (
                    compressedJackpotFlag == 1 &&
                    counter > 0 &&
                    counter < JACKPOT_LEVEL_CAP - 1
                ) {
                    counterStep = 2;
                }
                bool isFinalPhysicalDay = (counter + counterStep >=
                    JACKPOT_LEVEL_CAP);
                bool isEarlyBirdDay = (counter == 0);
                uint256 poolSnapshot = _getCurrentPrizePool();
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
                uint256 budget = (poolSnapshot * dailyBps) / 10_000;

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
                    // Deduct from current pool and add to next pool to back tickets
                    _setCurrentPrizePool(
                        _getCurrentPrizePool() - dailyLootboxBudget
                    );
                    _setNextPrizePool(_getNextPrizePool() + dailyLootboxBudget);
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

                    // 0.5% of futurePrizePool reserved for carryover tickets
                    uint256 futurePoolBal = _getFuturePrizePool();
                    reserveSlice = futurePoolBal / 200;
                    _setFuturePrizePool(futurePoolBal - reserveSlice);
                    _setNextPrizePool(_getNextPrizePool() + reserveSlice);
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

            uint256 entropyDaily = randWord ^ (uint256(lvl) << 192);
            uint8[4] memory traitIdsDaily = JackpotBucketLib
                .unpackWinningTraits(winningTraitsPacked);
            (uint8 counterStep_, , , ) = _unpackDailyTicketBudgets(
                dailyTicketBudgetsPacked
            );
            bool isFinalPhysicalDay_ = (jackpotCounter + counterStep_ >=
                JACKPOT_LEVEL_CAP);

            if (dailyEthBudget != 0) {
                uint16[4] memory bucketCountsDaily = JackpotBucketLib
                    .bucketCountsForPoolCap(
                        dailyEthBudget,
                        entropyDaily,
                        DAILY_ETH_MAX_WINNERS,
                        DAILY_JACKPOT_SCALE_MAX_BPS
                    );

                // Skip-split: when total scaled winners fit in one call, process
                // all 4 buckets without writing resumeEthPool.
                uint8 splitMode;
                {
                    uint32 totalWinners;
                    for (uint8 b; b < 4; ++b) totalWinners += bucketCountsDaily[b];
                    splitMode = (totalWinners <= JACKPOT_MAX_WINNERS)
                        ? SPLIT_NONE
                        : SPLIT_CALL1;
                }

                // Final physical day uses weighted shares (60/13/13/13) for the big payout;
                // other days use equal shares (20/20/20/20).
                uint64 sharesPacked = isFinalPhysicalDay_
                    ? FINAL_DAY_SHARES_PACKED
                    : DAILY_JACKPOT_SHARES_PACKED;
                uint16[4] memory shareBpsDaily = JackpotBucketLib
                    .shareBpsByBucket(sharesPacked, uint8(entropyDaily & 3));

                uint256 paidDailyEth = _processDailyEth(
                    lvl,
                    dailyEthBudget,
                    entropyDaily,
                    traitIdsDaily,
                    shareBpsDaily,
                    bucketCountsDaily,
                    isFinalPhysicalDay_,
                    splitMode,
                    true // jackpot phase (solo bucket gets whale pass)
                );
                if (isFinalPhysicalDay_) {
                    uint256 unpaidDailyEth = dailyEthBudget - paidDailyEth;
                    _setCurrentPrizePool(
                        _getCurrentPrizePool() - dailyEthBudget
                    );
                    if (unpaidDailyEth != 0) {
                        _setFuturePrizePool(
                            _getFuturePrizePool() + unpaidDailyEth
                        );
                    }
                } else {
                    _setCurrentPrizePool(_getCurrentPrizePool() - paidDailyEth);
                }
            }

            {
                uint32 bonusTraitsPacked = _rollWinningTraits(randWord, true);
                uint256 coinEntropy = randWord ^ (uint256(lvl) << 192) ^ uint256(COIN_JACKPOT_TAG);
                uint24 bonusTargetLevel = _selectDailyCoinTargetLevel(lvl, coinEntropy);
                emit DailyWinningTraits(questDay, winningTraitsPacked, bonusTraitsPacked, bonusTargetLevel);
            }

            dailyJackpotCoinTicketsPending = true;
            return;
        }

        // Purchase phase path - BURNIE and ETH bonuses at level 1+
        winningTraitsPacked = _rollWinningTraits(randWord, false);

        {
            uint32 bonusTraitsPacked = _rollWinningTraits(randWord, true);
            uint256 coinEntropy = randWord ^ (uint256(lvl) << 192) ^ uint256(COIN_JACKPOT_TAG);
            uint24 bonusTargetLevel = _selectDailyCoinTargetLevel(lvl, coinEntropy);
            emit DailyWinningTraits(questDay, winningTraitsPacked, bonusTraitsPacked, bonusTargetLevel);
        }

        bool isEthDay = lvl > 0; // daily 1% drip from futurePrizePool every purchase day
        uint256 ethDaySlice;
        if (isEthDay) {
            uint256 poolBps = 100; // 1% daily drip from futurePool
            ethDaySlice = (_getFuturePrizePool() * poolBps) / 10_000;
        }

        uint256 ethPool = ethDaySlice;
        uint256 lootboxBudget;
        if (ethPool != 0) {
            lootboxBudget = (ethPool * PURCHASE_REWARD_JACKPOT_LOOTBOX_BPS) / 10_000;
            if (lootboxBudget != 0) ethPool -= lootboxBudget;
        }
        uint256 paidEth = _executeJackpot(
            JackpotParams({
                lvl: lvl,
                ethPool: ethPool,
                entropy: randWord ^ (uint256(lvl) << 192),
                winningTraitsPacked: winningTraitsPacked,
                traitShareBpsPacked: DAILY_JACKPOT_SHARES_PACKED
            })
        );

        // Deferred deduction: deduct only what was actually consumed
        if (ethDaySlice != 0) {
            _setFuturePrizePool(
                _getFuturePrizePool() - lootboxBudget - paidEth
            );
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

        // Derive traits inline from randWord (DJT storage removed)
        uint24 lvl = level;
        uint32 mainTraitsPacked = _rollWinningTraits(randWord, false);
        uint32 bonusTraitsPacked = _rollWinningTraits(randWord, true);
        uint256 entropyDaily = randWord ^ (uint256(lvl) << 192);
        uint24 sourceLevel = lvl + uint24(carryoverSourceOffset);
        uint256 entropyNext = randWord ^ (uint256(sourceLevel) << 192);

        // --- Coin Jackpot ---
        uint256 coinBudget = _calcDailyCoinBudget(lvl);
        if (coinBudget != 0) {
            // Split: 25% far-future, 75% near-future
            uint256 farBudget = (coinBudget * FAR_FUTURE_COIN_BPS) / 10_000;
            _awardFarFutureCoinJackpot(lvl, farBudget, randWord);

            uint256 nearBudget = coinBudget - farBudget;
            if (nearBudget != 0) {
                uint256 coinEntropy = randWord ^
                    (uint256(lvl) << 192) ^
                    uint256(COIN_JACKPOT_TAG);
                uint24 targetLevel = _selectDailyCoinTargetLevel(
                    lvl,
                    coinEntropy
                );
                {
                    _awardDailyCoinToTraitWinners(
                        targetLevel,
                        bonusTraitsPacked,
                        nearBudget,
                        coinEntropy
                    );
                }
            }
        }

        // --- Ticket Distribution ---
        // Distribute daily tickets to current level trait winners (main traits)
        if (dailyTicketUnits != 0) {
            _distributeTicketJackpot(
                lvl,
                lvl + 1,
                mainTraitsPacked,
                dailyTicketUnits,
                entropyDaily,
                LOOTBOX_MAX_WINNERS,
                241
            );
        }

        // Distribute carryover tickets: winners from source level, tickets at current level
        // (or lvl+1 on final day since current level is about to end). Uses bonus traits.
        if (carryoverTicketUnits != 0) {
            bool isFinalDay = jackpotCounter + counterStep >= JACKPOT_LEVEL_CAP;
            _distributeTicketJackpot(
                sourceLevel,
                isFinalDay ? lvl + 1 : lvl,
                bonusTraitsPacked,
                carryoverTicketUnits,
                entropyNext,
                LOOTBOX_MAX_WINNERS,
                240
            );
        }

        // Complete the daily jackpot cycle
        unchecked {
            jackpotCounter += counterStep;
        }

        // Clear pending state
        dailyJackpotCoinTicketsPending = false;
        dailyTicketBudgetsPacked = 0;
    }

    /// @dev Execute the early-bird lootbox jackpot from the unified future pool.
    function _runEarlyBirdLootboxJackpot(uint24 lvl, uint256 rngWord) private {
        // Take 3% from unified reserve
        uint256 futurePoolLocal = _getFuturePrizePool();
        uint256 reserveContribution = (futurePoolLocal * 300) / 10_000; // 3%
        uint256 totalBudget = reserveContribution;

        // Deduct from reserve
        _setFuturePrizePool(futurePoolLocal - reserveContribution);

        if (totalBudget == 0) {
            return;
        }

        // 100 winners max, even split of budget
        uint256 maxWinners = 100;
        uint256 perWinnerEth = totalBudget / maxWinners;
        uint256 entropy = rngWord;
        uint24 baseLevel = lvl;
        uint256[5] memory levelPrices;
        for (uint8 l; l < 5; ) {
            levelPrices[l] = PriceLookupLib.priceForLevel(
                baseLevel + uint24(l)
            );
            unchecked {
                ++l;
            }
        }

        // Process each winner (uniform trait selection; no weighting by ticket counts)
        for (uint256 i; i < maxWinners; ) {
            entropy = EntropyLib.entropyStep(entropy);
            uint8 traitId = uint8(entropy);
            (
                address[] memory winners,
                uint256[] memory ticketIndexes
            ) = _randTraitTicket(
                    traitBurnTicket[lvl],
                    entropy,
                    traitId,
                    1,
                    uint8(i)
                );
            address winner = winners.length != 0 ? winners[0] : address(0);
            if (winner != address(0)) {
                // Roll for level offset 0-4 (20% chance each)
                entropy = EntropyLib.entropyStep(entropy);
                uint24 levelOffset = uint24(entropy % 5);
                uint256 ticketPrice = levelPrices[levelOffset];
                if (ticketPrice != 0) {
                    uint32 ticketCount = uint32(perWinnerEth / ticketPrice);
                    if (ticketCount != 0) {
                        _queueTickets(
                            winner,
                            baseLevel + levelOffset,
                            ticketCount,
                            true
                        );
                        emit JackpotTicketWin(
                            winner,
                            baseLevel + levelOffset,
                            traitId,
                            ticketCount,
                            baseLevel,
                            ticketIndexes[0]
                        );
                    }
                }
            }
            unchecked {
                ++i;
            }
        }

        // All budget goes to nextPrizePool (like purchases during purchase phase)
        // This will be merged into currentPrizePool at next level's jackpot calculation
        _setNextPrizePool(_getNextPrizePool() + totalBudget);
    }

    /// @notice Distribute yield surplus (stETH appreciation) to stakeholders.
    /// @dev Entry point for AdvanceModule delegatecall.
    ///      23% each to sDGNRS, vault, and charity (GNRUS) claimable, 23% yield accumulator (~8% buffer).
    /// @param rngWord VRF entropy for auto-rebuy targeting.
    function distributeYieldSurplus(uint256 rngWord) external {
        uint256 stBal = steth.balanceOf(address(this));
        uint256 totalBal = address(this).balance + stBal;
        uint256 obligations = _getCurrentPrizePool() +
            _getNextPrizePool() +
            claimablePool +
            _getFuturePrizePool() +
            yieldAccumulator;

        if (totalBal <= obligations) return;

        uint256 yieldPool = totalBal - obligations;
        uint256 quarterShare = (yieldPool * 2300) / 10_000;

        if (quarterShare != 0) {
            (uint256 d0, , ) = _addClaimableEth(
                ContractAddresses.VAULT,
                quarterShare,
                rngWord
            );
            (uint256 d1, , ) = _addClaimableEth(
                ContractAddresses.SDGNRS,
                quarterShare,
                rngWord
            );
            (uint256 d2, , ) = _addClaimableEth(
                ContractAddresses.GNRUS,
                quarterShare,
                rngWord
            );
            uint256 claimableDelta = d0 + d1 + d2;
            if (claimableDelta != 0) claimablePool += uint128(claimableDelta);
            yieldAccumulator += quarterShare;
        }
    }

    // =========================================================================
    // Internal Helpers — Claimable ETH
    // =========================================================================

    /// @dev Credits ETH to a player's claimable balance. Uses unchecked arithmetic because
    ///      uint256 overflow is practically impossible with real ETH amounts.
    ///      With auto-rebuy enabled, reserves full take profit for claim and
    ///      converts the remainder to tickets. Fractional dust is ignored.
    /// @param beneficiary Address to credit.
    /// @param weiAmount Wei to add to their claimable balance.
    /// @param entropy RNG seed for fractional ticket roll.
    /// @return claimableDelta Amount to add to claimablePool for this credit.
    function _addClaimableEth(
        address beneficiary,
        uint256 weiAmount,
        uint256 entropy
    )
        private
        returns (uint256 claimableDelta, uint24 rebuyLevel, uint32 rebuyTickets)
    {
        if (weiAmount == 0) return (0, 0, 0);

        // Auto-rebuy: convert winnings to tickets if enabled.
        // Skip when game is over — tickets are worthless post-game.
        if (!gameOver) {
            AutoRebuyState memory state = autoRebuyState[beneficiary];
            if (state.autoRebuyEnabled) {
                return
                    _processAutoRebuy(beneficiary, weiAmount, entropy, state);
            }
        }

        // Normal claimable winnings path
        // SAFETY: uint256 max is ~10^77 wei; overflow impossible in practice.
        _creditClaimable(beneficiary, weiAmount);
        return (weiAmount, 0, 0);
    }

    /// @dev Converts winnings to tickets for next level or next+1 (50/50).
    ///      Processes only the new amount; existing claimable remains untouched.
    ///      Applies fixed 30% bonus by default, 45% when afKing is active.
    ///      Fractional dust is dropped unconditionally.
    ///
    /// @param player Player receiving winnings.
    /// @param newAmount New winnings amount in wei.
    /// @param entropy RNG seed for fractional ticket roll.
    function _processAutoRebuy(
        address player,
        uint256 newAmount,
        uint256 entropy,
        AutoRebuyState memory state
    )
        private
        returns (uint256 claimableDelta, uint24 rebuyLevel, uint32 rebuyTickets)
    {
        AutoRebuyCalc memory calc = _calcAutoRebuy(
            player,
            newAmount,
            entropy,
            state,
            level,
            13_000,
            14_500
        );
        if (!calc.hasTickets) {
            _creditClaimable(player, newAmount);
            return (newAmount, 0, 0);
        }

        _queueTickets(player, calc.targetLevel, calc.ticketCount, true);

        if (calc.toFuture) {
            _setFuturePrizePool(_getFuturePrizePool() + calc.ethSpent);
        } else {
            _setNextPrizePool(_getNextPrizePool() + calc.ethSpent);
        }

        if (calc.reserved != 0) {
            _creditClaimable(player, calc.reserved);
        }

        return (calc.reserved, calc.targetLevel, calc.ticketCount);
    }

    /// @dev Converts an ETH budget to ticket units. Tickets cost ticketPrice/4.
    function _budgetToTicketUnits(
        uint256 budget,
        uint24 lvl
    ) private pure returns (uint256) {
        if (budget == 0) return 0;
        uint256 ticketPrice = PriceLookupLib.priceForLevel(lvl);
        return ticketPrice == 0 ? 0 : (budget << 2) / ticketPrice;
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
        _setNextPrizePool(_getNextPrizePool() + lootboxBudget);

        // Distribute tickets to winners (may use reduced basis for backing ratio)
        uint256 ticketBasis = (lootboxBudget * ticketConversionBps) / 10_000;
        uint256 ticketUnits = _budgetToTicketUnits(ticketBasis, lvl + 1);
        if (ticketUnits != 0) {
            _distributeTicketJackpot(
                lvl,
                lvl + 1,
                winningTraitsPacked,
                ticketUnits,
                randWord ^ (uint256(lvl) << 192),
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

        (uint16[4] memory counts, uint8 activeCount) = _computeBucketCounts(
            sourceLvl,
            traitIds,
            cap,
            entropy
        );
        if (activeCount == 0) return;

        _distributeTicketsToBuckets(
            sourceLvl,
            queueLvl,
            traitIds,
            counts,
            ticketUnits,
            entropy,
            cap,
            saltBase
        );
    }

    /// @dev Distributes tickets across all buckets.
    function _distributeTicketsToBuckets(
        uint24 sourceLvl,
        uint24 queueLvl,
        uint8[4] memory traitIds,
        uint16[4] memory counts,
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
                entropy = EntropyLib.entropyStep(
                    entropy ^ (uint256(traitIdx) << 64) ^ ticketUnits
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
                    globalIdx
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
        uint256 startIdx
    ) private returns (uint256 endIdx) {
        (
            address[] memory winners,
            uint256[] memory ticketIndexes
        ) = _randTraitTicket(
                traitBurnTicket[sourceLvl],
                entropy,
                traitId,
                uint8(count),
                salt
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
                emit JackpotTicketWin(
                    winner,
                    queueLvl,
                    traitId,
                    uint32(units),
                    sourceLvl,
                    ticketIndexes[i]
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
    function _computeBucketCounts(
        uint24 lvl,
        uint8[4] memory traitIds,
        uint16 maxWinners,
        uint256 entropy
    ) private view returns (uint16[4] memory counts, uint8 activeCount) {
        uint8 activeMask;
        for (uint8 i; i < 4; ) {
            uint8 trait = traitIds[i];
            bool hasEntries = traitBurnTicket[lvl][trait].length != 0;
            if (!hasEntries) {
                uint8 fullSymId = (trait >> 6) * 8 + (trait & 0x07);
                hasEntries =
                    fullSymId < 32 &&
                    deityBySymbol[fullSymId] != address(0);
            }
            if (hasEntries) {
                activeMask |= uint8(1 << i);
                unchecked {
                    ++activeCount;
                }
            }
            unchecked {
                ++i;
            }
        }
        if (activeCount == 0) return (counts, 0);

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

    /// @dev Core jackpot execution: distributes ETH to winners.
    ///      This is the unified entry point for daily and purchase phase jackpots.
    ///      COIN jackpots are handled separately by _executeCoinJackpot.
    ///      Pool debits are handled by the caller.
    ///
    /// @param jp Packed jackpot parameters.
    /// @return paidEth Total ETH paid out (for pool accounting).
    function _executeJackpot(
        JackpotParams memory jp
    ) private returns (uint256 paidEth) {
        uint8[4] memory traitIds = JackpotBucketLib.unpackWinningTraits(
            jp.winningTraitsPacked
        );
        uint16[4] memory shareBps = JackpotBucketLib.shareBpsByBucket(
            jp.traitShareBpsPacked,
            uint8(jp.entropy & 3)
        );

        if (jp.ethPool != 0) {
            paidEth = _runJackpotEthFlow(jp, traitIds, shareBps);
        }
    }

    /// @dev ETH flow for purchase phase jackpots (via _executeJackpot).
    ///      Fixed bucket counts [20, 12, 6, 1] = 39 winners, rotated by entropy.
    function _runJackpotEthFlow(
        JackpotParams memory jp,
        uint8[4] memory traitIds,
        uint16[4] memory shareBps
    ) private returns (uint256 totalPaidEth) {
        uint8 offset = uint8(jp.entropy & 3);
        uint16[4] memory base;
        base[0] = 20;
        base[1] = 12;
        base[2] = 6;
        base[3] = 1;
        uint16[4] memory bucketCounts;
        for (uint8 i; i < 4; ) {
            bucketCounts[i] = base[(i + offset) & 3];
            unchecked { ++i; }
        }
        return
            _processDailyEth(
                jp.lvl,
                jp.ethPool,
                jp.entropy,
                traitIds,
                shareBps,
                bucketCounts,
                false, // not final day
                SPLIT_NONE,
                false // not jackpot phase
            );
    }

    // =========================================================================
    // Daily Jackpot ETH — Distribution
    // =========================================================================

    /// @dev Call 2 of the daily ETH two-call split. Reconstructs params from
    ///      stored state and processes the mid buckets that call 1 skipped.
    function _resumeDailyEth(uint24 lvl, uint256 randWord) private {
        uint256 entropy = randWord ^ (uint256(lvl) << 192);
        (uint8 cs, , , ) = _unpackDailyTicketBudgets(dailyTicketBudgetsPacked);
        bool isFinal = (jackpotCounter + cs >= JACKPOT_LEVEL_CAP);
        uint256 paidEth2 = _processDailyEth(
            lvl, 0, entropy,
            JackpotBucketLib.unpackWinningTraits(_rollWinningTraits(randWord, false)),
            JackpotBucketLib.shareBpsByBucket(
                isFinal ? FINAL_DAY_SHARES_PACKED : DAILY_JACKPOT_SHARES_PACKED,
                uint8(entropy & 3)
            ),
            JackpotBucketLib.bucketCountsForPoolCap(
                uint256(resumeEthPool), entropy,
                DAILY_ETH_MAX_WINNERS, DAILY_JACKPOT_SCALE_MAX_BPS
            ),
            isFinal, SPLIT_CALL2,
            true // jackpot phase
        );
        if (paidEth2 != 0) {
            if (isFinal) {
                _setFuturePrizePool(_getFuturePrizePool() - paidEth2);
            } else {
                _setCurrentPrizePool(_getCurrentPrizePool() - paidEth2);
            }
        }
    }

    /// @dev Unified ETH distribution across trait buckets.
    ///      Handles jackpot-phase (with optional two-call split) and purchase/terminal paths.
    ///
    ///      SPLIT MODES:
    ///      - SPLIT_NONE:  All 4 buckets in one call. No resumeEthPool write.
    ///      - SPLIT_CALL1: Largest + solo buckets only. Writes resumeEthPool for call 2.
    ///      - SPLIT_CALL2: Mid buckets only. Reads and clears resumeEthPool.
    ///
    ///      JACKPOT PHASE vs PURCHASE/TERMINAL:
    ///      - Jackpot phase (isJackpotPhase=true): Solo bucket gets whale pass + DGNRS on final day.
    ///        Uses ordered iteration with call1 mask for split routing.
    ///      - Purchase/terminal (isJackpotPhase=false): All buckets paid uniformly.
    ///        Always uses SPLIT_NONE.
    ///
    /// @param lvl The level whose winners are being paid.
    /// @param ethPool Total ETH to distribute (ignored when splitMode=SPLIT_CALL2).
    /// @param entropy VRF-derived random word for winner selection.
    /// @param traitIds The 4 winning trait IDs.
    /// @param shareBps Basis-point share for each of the 4 buckets.
    /// @param bucketCounts Number of holders in each trait bucket.
    /// @param isFinalDay True on the last physical jackpot day (controls DGNRS in solo bucket).
    /// @param splitMode SPLIT_NONE, SPLIT_CALL1, or SPLIT_CALL2.
    /// @param isJackpotPhase True during jackpot phase (solo bucket gets whale pass).
    /// @return paidEth Total ETH actually paid out in this call.
    function _processDailyEth(
        uint24 lvl,
        uint256 ethPool,
        uint256 entropy,
        uint8[4] memory traitIds,
        uint16[4] memory shareBps,
        uint16[4] memory bucketCounts,
        bool isFinalDay,
        uint8 splitMode,
        bool isJackpotPhase
    ) private returns (uint256 paidEth) {
        if (splitMode == SPLIT_CALL2) {
            ethPool = uint256(resumeEthPool);
            resumeEthPool = 0;
        }
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

        // Build call1 mask for split routing (only used when splitMode != SPLIT_NONE).
        bool[4] memory call1Bucket;
        if (splitMode != SPLIT_NONE) {
            call1Bucket[order[0]] = true;
            if (order[0] == remainderIdx) {
                call1Bucket[order[1]] = true;
            } else {
                call1Bucket[remainderIdx] = true;
            }
        }

        uint256 entropyState = entropy;
        uint256 liabilityDelta;

        for (uint8 j; j < 4; ++j) {
            uint8 traitIdx = order[j];

            // In split mode, skip buckets not assigned to this call.
            if (splitMode == SPLIT_CALL1 && !call1Bucket[traitIdx]) continue;
            if (splitMode == SPLIT_CALL2 && call1Bucket[traitIdx]) continue;

            uint16 count = bucketCounts[traitIdx];
            uint256 share = shares[traitIdx];
            if (count == 0 || share == 0) continue;

            entropyState = EntropyLib.entropyStep(
                entropyState ^ (uint256(traitIdx) << 64) ^ share
            );

            uint16 totalCount = count;
            if (totalCount > MAX_BUCKET_WINNERS) totalCount = MAX_BUCKET_WINNERS;

            (
                address[] memory winners,
                uint256[] memory ticketIndexes
            ) = _randTraitTicket(
                    traitBurnTicket[lvl],
                    entropyState,
                    traitIds[traitIdx],
                    uint8(totalCount),
                    uint8(200 + traitIdx)
                );
            if (winners.length == 0) continue;

            uint256 perWinner = share / totalCount;
            if (perWinner == 0) continue;

            if (traitIdx == remainderIdx && isJackpotPhase) {
                // Solo bucket (jackpot phase): whale pass + DGNRS on final day
                address w = winners[0];
                if (w != address(0)) {
                    (
                        uint256 claimDelta,
                        uint256 paidDelta,
                        uint256 newEntropy
                    ) = _handleSoloBucketWinner(
                            w, lvl, traitIds[traitIdx], ticketIndexes[0],
                            perWinner, entropyState, isFinalDay
                        );
                    entropyState = newEntropy;
                    paidEth += paidDelta;
                    liabilityDelta += claimDelta;
                }
            } else {
                // Normal bucket: 100% ETH
                (uint256 bucketPaid, uint256 bucketLiability) = _payNormalBucket(
                    winners, ticketIndexes, perWinner, lvl, traitIds[traitIdx], entropyState
                );
                paidEth += bucketPaid;
                liabilityDelta += bucketLiability;
            }
        }

        if (liabilityDelta != 0) {
            claimablePool += uint128(liabilityDelta);
        }

        // Only write resumeEthPool when splitting across two calls.
        if (splitMode == SPLIT_CALL1) {
            resumeEthPool = uint128(ethPool);
        }
    }

    // =========================================================================
    // Internal Helpers — Winner Resolution
    // =========================================================================

    /// @dev Resolves winners for a single trait bucket and distributes ETH.
    ///
    ///      FLOW:
    ///      1. Early exit if no share or no winners.
    ///      2. Select random ticket holders from the trait's burn ticket pool.
    ///      3. Credit ETH payouts to claimableWinnings (with optional loot box conversion).
    ///
    /// @param lvl Current level for ticket pool lookup.
    /// @param traitId Which trait's ticket pool to draw from.
    /// @param traitIdx Bucket index (0-3) for entropy derivation.
    /// @param traitShare Total ETH allocated to this bucket.
    /// @param entropy Current entropy state.
    /// @param winnerCount Number of winners to select.
    /// @return entropyState Updated entropy after selection.
    /// @return ethDelta ETH credited to claimable balances.
    /// @return liabilityDelta Total claimable liability added.
    /// @return ticketSpent Whale pass ETH routed to futurePrizePool.
    function _resolveTraitWinners(
        uint24 lvl,
        uint8 traitId,
        uint8 traitIdx,
        uint256 traitShare,
        uint256 entropy,
        uint16 winnerCount
    )
        private
        returns (
            uint256 entropyState,
            uint256 ethDelta,
            uint256 liabilityDelta,
            uint256 ticketSpent
        )
    {
        entropyState = entropy;

        // Early exits for edge cases.
        if (traitShare == 0) return (entropyState, 0, 0, 0);

        uint16 totalCount = winnerCount;
        if (totalCount == 0) return (entropyState, 0, 0, 0);

        // Cap to MAX_BUCKET_WINNERS to fit in uint8 and bound gas.
        if (totalCount > MAX_BUCKET_WINNERS) totalCount = MAX_BUCKET_WINNERS;

        // Derive sub-entropy and select winners from the trait's ticket pool.
        entropyState = EntropyLib.entropyStep(
            entropyState ^ (uint256(traitIdx) << 64) ^ traitShare
        );
        (
            address[] memory winners,
            uint256[] memory ticketIndexes
        ) = _randTraitTicket(
                traitBurnTicket[lvl],
                entropyState,
                traitId,
                uint8(totalCount),
                uint8(200 + traitIdx) // Salt to differentiate trait buckets
            );
        if (winners.length == 0) return (entropyState, 0, 0, 0);

        uint256 perWinner = traitShare / totalCount;
        if (perWinner == 0) return (entropyState, 0, 0, 0);

        uint256 len = winners.length;

        uint256 totalPayout;
        uint256 totalLiability;
        for (uint256 i; i < len; ) {
            address w = winners[i];
            if (w != address(0)) {
                (
                    uint256 claimableDelta,
                    uint24 rebuyLevel,
                    uint32 rebuyTickets
                ) = _addClaimableEth(w, perWinner, entropyState);
                emit JackpotEthWin(
                    w,
                    lvl,
                    traitId,
                    perWinner,
                    ticketIndexes[i],
                    rebuyLevel,
                    rebuyTickets
                );
                totalPayout += perWinner;
                totalLiability += claimableDelta;
            }
            unchecked {
                ++i;
            }
        }
        if (totalPayout == 0) return (entropyState, 0, 0, 0);

        liabilityDelta = totalLiability;
        ethDelta = totalPayout;

        return (entropyState, ethDelta, liabilityDelta, 0);
    }

    // =========================================================================
    // Internal Helpers — Quest & Credit
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
        bool isFinalDay
    )
        private
        returns (uint256 claimDelta, uint256 paidDelta, uint256 newEntropy)
    {
        (
            uint256 claimableDelta,
            uint256 paid,
            uint256 wpSpent,
            uint256 newEnt,
            uint24 rebuyLevel,
            uint32 rebuyTickets
        ) = _processSoloBucketWinner(w, perWinner, entropy);
        newEntropy = newEnt;
        claimDelta = claimableDelta;
        if (paid != 0) {
            emit JackpotEthWin(
                w,
                lvl,
                traitId,
                paid,
                ticketIndex,
                rebuyLevel,
                rebuyTickets
            );
            paidDelta += paid;
        }
        if (wpSpent != 0) {
            emit JackpotWhalePassWin(w, lvl, wpSpent / HALF_WHALE_PASS_PRICE);
            paidDelta += wpSpent;
        }
        if (isFinalDay) {
            uint256 dgnrsPool = dgnrs.poolBalance(
                IStakedDegenerusStonk.Pool.Reward
            );
            uint256 reward = (dgnrsPool * FINAL_DAY_DGNRS_BPS) / 10_000;
            if (reward != 0) {
                dgnrs.transferFromPool(
                    IStakedDegenerusStonk.Pool.Reward,
                    w,
                    reward
                );
                emit JackpotDgnrsWin(w, reward);
            }
        }
    }

    /// @dev Pays normal (non-solo) bucket winners. Extracted to avoid stack-too-deep in _processDailyEth.
    function _payNormalBucket(
        address[] memory winners,
        uint256[] memory ticketIndexes,
        uint256 perWinner,
        uint24 lvl,
        uint8 traitId,
        uint256 entropy
    ) private returns (uint256 totalPaid, uint256 totalLiability) {
        uint256 len = winners.length;
        for (uint256 i; i < len; ) {
            address w = winners[i];
            if (w != address(0)) {
                (uint256 claimableDelta, uint24 rebuyLevel, uint32 rebuyTickets) =
                    _addClaimableEth(w, perWinner, entropy);
                emit JackpotEthWin(w, lvl, traitId, perWinner, ticketIndexes[i], rebuyLevel, rebuyTickets);
                totalPaid += perWinner;
                totalLiability += claimableDelta;
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
            uint256 newEntropy,
            uint24 rebuyLevel,
            uint32 rebuyTickets
        )
    {
        // 75/25 split: whale pass only if 25% covers at least one half-pass
        uint256 quarterAmount = perWinner >> 2; // perWinner / 4
        uint256 whalePassCount = quarterAmount / HALF_WHALE_PASS_PRICE;
        newEntropy = entropy;

        if (whalePassCount != 0) {
            uint256 whalePassCost = whalePassCount * HALF_WHALE_PASS_PRICE;
            uint256 ethAmount = perWinner - whalePassCost;

            (claimableDelta, rebuyLevel, rebuyTickets) = _addClaimableEth(
                winner,
                ethAmount,
                entropy
            );
            ethPaid = ethAmount;

            whalePassClaims[winner] += whalePassCount;
            _setFuturePrizePool(_getFuturePrizePool() + whalePassCost);
            whalePassSpent = whalePassCost;
        } else {
            // 25% too small for a whale pass — pay full amount as ETH
            (claimableDelta, rebuyLevel, rebuyTickets) = _addClaimableEth(
                winner,
                perWinner,
                entropy
            );
            ethPaid = perWinner;
        }
    }

    /// @dev If a top hero symbol exists for the current day, that symbol auto-wins
    ///      its own quadrant (with random color), replacing only that quadrant.
    ///      Applied to all jackpot paths (purchase phase + jackpot phase).
    function _applyHeroOverride(
        uint8[4] memory w,
        uint256 randomWord
    ) private view {
        (
            bool hasHeroWinner,
            uint8 heroQuadrant,
            uint8 heroSymbol
        ) = _topHeroSymbol(_simulatedDayIndex());
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

    /// @dev Returns the top hero symbol for a day across all quadrants.
    ///      Tie-breaker is deterministic first-seen order (q asc, symbol asc).
    function _topHeroSymbol(
        uint32 day
    )
        private
        view
        returns (bool hasWinner, uint8 winQuadrant, uint8 winSymbol)
    {
        uint32 topAmount;
        for (uint8 q; q < 4; ) {
            uint256 packed = dailyHeroWagers[day][q];
            for (uint8 s; s < 8; ) {
                uint32 amount = uint32(
                    (packed >> (uint256(s) * 32)) & 0xFFFFFFFF
                );
                if (amount > topAmount) {
                    topAmount = amount;
                    winQuadrant = q;
                    winSymbol = s;
                }
                unchecked {
                    ++s;
                }
            }
            unchecked {
                ++q;
            }
        }
        hasWinner = topAmount != 0;
    }

    // =========================================================================
    // Internal Helpers — Winner Selection
    // =========================================================================

    /// @dev Selects random winners from a trait's ticket pool, returning both addresses and indices.
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
        address[] storage holders = traitBurnTicket_[trait];
        uint256 len = holders.length;

        // Virtual deity entries: floor(2% of bucket tickets), minimum 2, if a deity exists for this symbol.
        // traitId layout: (quadrant << 6) | (color << 3) | symIdx
        // fullSymId = quadrant * 8 + symIdx
        uint8 fullSymId = (trait >> 6) * 8 + (trait & 0x07);
        address deity;
        uint256 virtualCount;
        if (fullSymId < 32) {
            deity = deityBySymbol[fullSymId];
            if (deity != address(0)) {
                virtualCount = len / 50;
                if (virtualCount < 2) virtualCount = 2;
            }
        }

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

    /// @notice Pays daily BURNIE jackpot to random ticket holders.
    /// @dev Runs every day in its own transaction. Awards 0.5% of prize pool target in BURNIE.
    ///      75% goes to near-future trait-matched winners ([lvl+1, lvl+4]).
    ///      25% goes to far-future ticketQueue holders ([lvl+5, lvl+99]).
    /// @param lvl Current level.
    /// @param randWord VRF entropy for winner selection.
    function payDailyCoinJackpot(uint24 lvl, uint256 randWord) external {
        uint256 coinBudget = _calcDailyCoinBudget(lvl);
        if (coinBudget == 0) return;

        // Split: 25% far-future, 75% near-future
        uint256 farBudget = (coinBudget * FAR_FUTURE_COIN_BPS) / 10_000;
        uint256 nearBudget = coinBudget - farBudget;

        // --- Far-future portion (ticketQueue-based, no traits) ---
        _awardFarFutureCoinJackpot(lvl, farBudget, randWord);

        // --- Near-future portion (trait-matched) ---
        if (nearBudget == 0) return;

        uint32 bonusTraitsPacked = _rollWinningTraits(randWord, true);

        uint256 entropy = randWord ^
            (uint256(lvl) << 192) ^
            uint256(COIN_JACKPOT_TAG);
        uint24 targetLevel = _selectDailyCoinTargetLevel(
            lvl,
            entropy
        );

        _awardDailyCoinToTraitWinners(
            targetLevel,
            bonusTraitsPacked,
            nearBudget,
            entropy
        );
    }

    /// @dev Pick one random level in [lvl+1, lvl+4] for near-future BURNIE distribution.
    function _selectDailyCoinTargetLevel(
        uint24 lvl,
        uint256 entropy
    ) private pure returns (uint24 targetLevel) {
        return lvl + 1 + uint24(entropy % 4);
    }

    /// @dev Awards BURNIE to random winners from the packed winning traits at a target level.
    function _awardDailyCoinToTraitWinners(
        uint24 lvl,
        uint32 winningTraitsPacked,
        uint256 coinBudget,
        uint256 entropy
    ) private {
        if (coinBudget == 0) return;
        uint16 cap = DAILY_COIN_MAX_WINNERS;
        if (cap > coinBudget) cap = uint16(coinBudget);

        uint8[4] memory traitIds = JackpotBucketLib.unpackWinningTraits(
            winningTraitsPacked
        );
        (uint16[4] memory counts, uint8 activeCount) = _computeBucketCounts(
            lvl,
            traitIds,
            cap,
            entropy
        );
        if (activeCount == 0) return;

        uint256 baseAmount = coinBudget / cap;
        uint256 extra = coinBudget % cap;
        uint256 cursor = entropy % cap;

        for (uint8 traitIdx; traitIdx < 4; ) {
            uint16 count = counts[traitIdx];
            if (count != 0) {
                entropy = EntropyLib.entropyStep(
                    entropy ^ (uint256(traitIdx) << 64) ^ coinBudget
                );

                (
                    address[] memory bucketWinners,
                    uint256[] memory bucketTicketIndexes
                ) = _randTraitTicket(
                        traitBurnTicket[lvl],
                        entropy,
                        traitIds[traitIdx],
                        uint8(count),
                        uint8(DAILY_COIN_SALT_BASE + traitIdx)
                    );

                uint256 len = bucketWinners.length;
                for (uint256 i; i < len; ) {
                    uint256 amount = baseAmount;
                    if (extra != 0 && cursor < extra) {
                        amount += 1;
                    }

                    address winner = bucketWinners[i];
                    if (winner != address(0) && amount != 0) {
                        emit JackpotBurnieWin(
                            winner,
                            lvl,
                            traitIds[traitIdx],
                            amount,
                            bucketTicketIndexes[i]
                        );
                        coinflip.creditFlip(winner, amount);
                    }

                    unchecked {
                        ++cursor;
                        if (cursor == cap) cursor = 0;
                        ++i;
                    }
                }
            }

            unchecked {
                ++traitIdx;
            }
        }
    }

    /// @dev Awards 25% of the BURNIE coin budget to random ticket holders on far-future levels.
    ///      Samples up to 10 random levels in [lvl+5, lvl+99], picks 1 winner per level from
    ///      that level's ticketQueue (traits not yet assigned), and splits the budget evenly.
    function _awardFarFutureCoinJackpot(
        uint24 lvl,
        uint256 farBudget,
        uint256 rngWord
    ) private {
        if (farBudget == 0) return;

        uint256 entropy = rngWord ^
            (uint256(lvl) << 192) ^
            uint256(FAR_FUTURE_COIN_TAG);

        // First pass: find up to FAR_FUTURE_COIN_SAMPLES winners from ticketQueue
        address[10] memory winners;
        uint24[10] memory winnerLevels;
        uint8 found;

        for (uint8 s; s < FAR_FUTURE_COIN_SAMPLES; ) {
            entropy = EntropyLib.entropyStep(entropy ^ uint256(s));

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

        // Distribute evenly among found winners
        uint256 perWinner = farBudget / found;
        if (perWinner == 0) return;

        address[] memory batchPlayers = new address[](found);
        uint256[] memory batchAmounts = new uint256[](found);

        for (uint8 i; i < found; ) {
            emit FarFutureCoinJackpotWinner(
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
        uint256 r = isBonus
            ? uint256(keccak256(abi.encodePacked(randWord, BONUS_TRAITS_TAG)))
            : randWord;
        uint8[4] memory traits = JackpotBucketLib.getRandomTraits(r);
        _applyHeroOverride(traits, r);
        packed = JackpotBucketLib.packWinningTraits(traits);
    }

    /// @dev Calculate 0.5% of prize pool target in BURNIE.
    function _calcDailyCoinBudget(uint24 lvl) private view returns (uint256) {
        uint256 priceWei = PriceLookupLib.priceForLevel(level);
        if (priceWei == 0) return 0;
        return (levelPrizePool[lvl - 1] * PRICE_COIN_UNIT) / (priceWei * 200);
    }

    /// @dev Current-pool daily jackpot share:
    ///      - Days 1-4: random 6%-14% (avg 10%)
    ///      - Day 5: 100% of remaining currentPrizePool
    function _dailyCurrentPoolBps(
        uint8 counter,
        uint256 randWord
    ) private pure returns (uint16 bps) {
        if (counter >= JACKPOT_LEVEL_CAP - 1) return 10_000;

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
        if (msg.sender != address(this)) revert E();
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
                {
                    (uint256 cd, uint24 rl, uint32 rt) = _addClaimableEth(
                        winner,
                        ethPortion,
                        rngWord
                    );
                    claimableDelta += cd;
                    emit JackpotEthWin(winner, lvl, 0, ethPortion, 0, rl, rt);
                }

                // Lootbox half: small amounts awarded immediately, large deferred
                if (lootboxPortion <= LOOTBOX_CLAIM_THRESHOLD) {
                    // Small lootbox: award immediately (2 rolls, probabilistic targeting)
                    rngWord = _awardJackpotTickets(
                        winner,
                        lootboxPortion,
                        lvl,
                        rngWord
                    );
                    emit JackpotTicketWin(winner, lvl, 0, 0, lvl, 0);
                } else {
                    // Large lootbox: defer to claim (whale pass equivalent)
                    _queueWhalePassClaimCore(winner, lootboxPortion);
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
                (uint256 cd, uint24 rl, uint32 rt) = _addClaimableEth(
                    winner,
                    amount,
                    rngWord
                );
                claimableDelta += cd;
                emit JackpotEthWin(winner, lvl, 0, amount, 0, rl, rt);
            } else {
                // Odd index: 100% lootbox (upside exposure)
                rngWord = _awardJackpotTickets(winner, amount, lvl, rngWord);
                emit JackpotTicketWin(winner, lvl, 0, 0, lvl, 0);
            }

            unchecked {
                ++i;
            }
        }

        // Refund + lootbox + whale pass ETH stays in futurePool implicitly:
        // caller only deducts claimableDelta from memFuture. No storage write needed.
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
     * @return Updated entropy state.
     */
    function _awardJackpotTickets(
        address winner,
        uint256 amount,
        uint24 minTargetLevel,
        uint256 entropy
    ) private returns (uint256) {
        // Large amounts (> 5 ETH): defer to whale pass claim system
        if (amount > LOOTBOX_CLAIM_THRESHOLD) {
            _queueWhalePassClaimCore(winner, amount);
            return entropy;
        }

        // Very small amounts (<= 0.5 ETH): single roll
        if (amount <= SMALL_LOOTBOX_THRESHOLD) {
            return _jackpotTicketRoll(winner, amount, minTargetLevel, entropy);
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

        return entropy;
    }

    /**
     * @notice Resolve a single jackpot ticket roll into ticket awards.
     * @dev Selects target level based on probability, then awards tickets.
     *      Uses actual game pricing for the selected target level.
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
        entropy = EntropyLib.entropyStep(entropy);

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
        _queueLootboxTickets(winner, targetLevel, quantityScaled, true);

        return entropy;
    }
}
