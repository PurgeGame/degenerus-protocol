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
 *      2. `payDailyJackpot` — Handles early-burn rewards during purchase phase and rolling dailies at EOL.
 *      3. `payDailyCoinJackpot` — BURNIE jackpot distribution to near-future ticket holders.
 *      4. `processTicketBatch` — Batched airdrop processing with gas budgeting to stay block-safe.
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

    /// @param remainder Amount returned to claimableWinnings (reserved + dust).
    event AutoRebuyProcessed(
        address indexed player,
        uint24 targetLevel,
        uint32 ticketCount,
        uint256 ethSpent,
        uint256 remainder
    );

    /// @dev Emitted when a far-future ticket holder (5-99 levels ahead) wins the daily BURNIE jackpot.
    ///      These winners are drawn from ticketQueue (traits not yet assigned).
    event FarFutureCoinJackpotWinner(
        address indexed winner,
        uint24 indexed currentLevel,
        uint24 indexed winnerLevel,
        uint256 amount
    );

    /// @dev Emitted for each jackpot winner draw.
    ///      ticketIndex is the index in traitBurnTicket[level][traitId], uint256.max for deity, 0 for non-trait paths.
    ///      awardType: 0=ETH, 1=BURNIE, 2=TICKETS, 3=DGNRS, 4=WHALE_PASS
    event JackpotTicketWinner(
        address indexed winner,
        uint24 indexed level,
        uint8 indexed traitId,
        uint256 amount,
        uint256 ticketIndex,
        uint8 awardType
    );

    /// @notice Emitted after BAF/decimator jackpot resolution with final pool values.
    /// @dev Enables indexers to track pool changes from reward jackpots without
    ///      replaying on-chain leaderboard/ticket state. Only emitted when pools change.
    /// @param lvl The level that just completed (indexed for Advance event correlation).
    /// @param futurePool Authoritative post-resolution future prize pool value.
    /// @param claimableDelta Total ETH moved to claimable during resolution.
    event RewardJackpotsSettled(
        uint24 indexed lvl,
        uint256 futurePool,
        uint256 claimableDelta
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

    /// @dev Max forward offset for carryover source selection (lvl+1..lvl+4).
    uint8 private constant DAILY_CARRYOVER_MAX_OFFSET = 4;

    /// @dev Current-pool daily jackpot percentage bounds for days 1-4 (6%-14%).
    uint16 private constant DAILY_CURRENT_BPS_MIN = 600;
    uint16 private constant DAILY_CURRENT_BPS_MAX = 1400;

    // -------------------------------------------------------------------------
    // Constants — Gas Budgeting (Ticket Batch Processing)
    // -------------------------------------------------------------------------

    /// @dev Default SSTORE budget for processTicketBatch to stay safely under 15M gas.
    uint32 private constant WRITES_BUDGET_SAFE = 550;

    /// @dev LCG multiplier for deterministic trait generation (Knuth's MMIX constant).
    uint64 private constant TICKET_LCG_MULT = 0x5851F42D4C957F2D;

    /// @dev Portion of DGNRS reward pool paid to the day-5 solo bucket winner (1%).
    uint16 private constant FINAL_DAY_DGNRS_BPS = 100;

    /// @dev Portion of purchase-phase reward-pool jackpots converted to loot boxes (3/4).
    uint16 private constant PURCHASE_REWARD_JACKPOT_LOOTBOX_BPS = 7500;

    /// @dev Max winners per single trait bucket (must fit in uint8 for _randTraitTicket).
    ///      Set to 250 to allow all ticket winners in single trait if others are empty.
    uint8 private constant MAX_BUCKET_WINNERS = 250;

    /// @dev Award type constants for JackpotTicketWinner event.
    uint8 private constant AWARD_ETH = 0;
    uint8 private constant AWARD_BURNIE = 1;
    uint8 private constant AWARD_TICKETS = 2;
    uint8 private constant AWARD_DGNRS = 3;
    uint8 private constant AWARD_WHALE_PASS = 4;

    // -------------------------------------------------------------------------
    // Constants — Jackpot Bucket Scaling (Gas Guardrails)
    // -------------------------------------------------------------------------

    /// @dev Maximum total winners per jackpot payout (including solo bucket).
    uint16 private constant JACKPOT_MAX_WINNERS = 300;

    /// @dev Maximum total ETH winners across daily + carryover jackpots.
    uint16 private constant DAILY_ETH_MAX_WINNERS = 321;

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

    /// @dev Maximum scale for bucket sizing (4x at 200 ETH+).
    uint16 private constant JACKPOT_SCALE_MAX_BPS = 40_000;

    /// @dev Daily jackpot max scale (6.6667x) to allow up to DAILY_ETH_MAX_WINNERS.
    uint32 private constant DAILY_JACKPOT_SCALE_MAX_BPS = 66_667;

    // -------------------------------------------------------------------------
    // Structs
    // -------------------------------------------------------------------------

    /// @dev Mutable context passed through ETH distribution loops to track cumulative state.
    ///      Using a struct avoids stack-too-deep and makes the flow explicit.
    struct JackpotEthCtx {
        uint256 entropyState; // Rolling entropy for winner selection.
        uint256 liabilityDelta; // Cumulative claimable liability added this run.
        uint256 totalPaidEth; // Total ETH paid out (including ticket conversions).
        uint24 lvl; // Current level.
    }

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

        uint32 winningTraitsPacked = _rollWinningTraits(rngWord, true);
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

        paidWei = _distributeJackpotEth(
            targetLvl,
            poolWei,
            entropy,
            traitIds,
            shareBps,
            bucketCounts
        );
    }

    /// @notice Pays early-burn jackpots during purchase phase OR rolling daily jackpots at level end.
    /// @dev Called by the parent game contract via delegatecall. Two distinct paths:
    ///
    ///      DAILY PATH (isDaily=true):
    ///      - Day 1-4: Distributes a random 6%-14% slice of remaining currentPrizePool.
    ///      - Day 5: Distributes 100% of remaining currentPrizePool.
    ///      - Day 1 also runs the early-bird lootbox jackpot (from futurePrizePool).
    ///      - On day 2-4, takes 0.5% of futurePrizePool and buys current-level tickets
    ///        for winners from a random source level in [lvl+1, lvl+4], deposited into nextPool.
    ///      - Increments jackpotCounter on completion.
    ///
    ///      EARLY-BURN PATH (isDaily=false):
    ///      - Triggered during purchase phase when early burns occur.
    ///      - Rolls random (non-burn-weighted) winning traits and runs trait-based jackpot.
    ///      - Every purchase day (except day 1): adds a 1% futurePrizePool ETH slice
    ///        with 75% converted to lootbox tickets and remainder distributed as ETH.
    ///      - Day 1 of each level: no early-burn distribution (ethDaySlice=0, _executeJackpot no-ops on empty pool).
    ///
    /// @param isDaily True for scheduled daily jackpot, false for early-burn jackpot.
    /// @param lvl Current game level.
    /// @param randWord VRF entropy for winner selection and trait derivation.
    function payDailyJackpot(
        bool isDaily,
        uint24 lvl,
        uint256 randWord
    ) external {
        uint48 questDay = _calculateDayIndex();
        uint32 winningTraitsPacked;

        if (isDaily) {
            winningTraitsPacked = _rollWinningTraits(randWord, true);
            _syncDailyWinningTraits(lvl, winningTraitsPacked, questDay);

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
                uint256 dailyLootboxBudget = _validateTicketBudget(
                    budget / 5,
                    lvl,
                    winningTraitsPacked
                );
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
                    isFinalPhysicalDay_
                );
                if (isFinalPhysicalDay_) {
                    uint256 unpaidDailyEth = dailyEthBudget - paidDailyEth;
                    _setCurrentPrizePool(_getCurrentPrizePool() - dailyEthBudget);
                    if (unpaidDailyEth != 0) {
                        _setFuturePrizePool(_getFuturePrizePool() + unpaidDailyEth);
                    }
                } else {
                    _setCurrentPrizePool(_getCurrentPrizePool() - paidDailyEth);
                }
            }

            dailyJackpotCoinTicketsPending = true;
            return;
        }

        // Non-daily (early-burn) path - BURNIE and ETH bonuses on non-day-1 levels
        winningTraitsPacked = _rollWinningTraits(randWord, false);
        _syncDailyWinningTraits(lvl, winningTraitsPacked, questDay);

        bool isEthDay = questDay > purchaseStartDay && lvl > 1; // daily 1% drip from futurePrizePool
        uint256 ethDaySlice;
        if (isEthDay) {
            uint256 poolBps = 100; // 1% daily drip from futurePool
            ethDaySlice = (_getFuturePrizePool() * poolBps) / 10_000;
        }

        uint256 ethPool = ethDaySlice;
        uint256 lootboxBudget;
        if (ethPool != 0) {
            lootboxBudget = _validateTicketBudget(
                (ethPool * PURCHASE_REWARD_JACKPOT_LOOTBOX_BPS) / 10_000,
                lvl,
                winningTraitsPacked
            );
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
            _setFuturePrizePool(_getFuturePrizePool() - lootboxBudget - paidEth);
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
    ///      Uses stored values from Phase 1:
    ///      - lastDailyJackpotLevel: The level when jackpot was triggered
    ///      - lastDailyJackpotWinningTraits: Packed winning trait IDs
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

        // Retrieve stored state from ETH phase
        uint24 lvl = lastDailyJackpotLevel;
        uint32 winningTraitsPacked = lastDailyJackpotWinningTraits;
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
                    winningTraitsPacked,
                    coinEntropy
                );
                if (targetLevel != 0) {
                    _awardDailyCoinToTraitWinners(
                        targetLevel,
                        winningTraitsPacked,
                        nearBudget,
                        coinEntropy
                    );
                }
            }
        }

        // --- Ticket Distribution ---
        // Distribute daily tickets to current level trait winners
        if (dailyTicketUnits != 0) {
            _distributeTicketJackpot(
                lvl,
                lvl + 1,
                winningTraitsPacked,
                dailyTicketUnits,
                entropyDaily,
                LOOTBOX_MAX_WINNERS,
                241
            );
        }

        // Distribute carryover tickets: winners from source level, tickets at current level
        // (or lvl+1 on final day since current level is about to end).
        if (carryoverTicketUnits != 0) {
            bool isFinalDay = jackpotCounter + counterStep >= JACKPOT_LEVEL_CAP;
            _distributeTicketJackpot(
                sourceLevel,
                isFinalDay ? lvl + 1 : lvl,
                winningTraitsPacked,
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
            address[] memory winners = _randTraitTicket(
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
                        emit JackpotTicketWinner(
                            winner,
                            baseLevel + levelOffset,
                            traitId,
                            ticketCount,
                            0,
                            AWARD_TICKETS
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
            uint256 claimableDelta =
                _addClaimableEth(
                    ContractAddresses.VAULT,
                    quarterShare,
                    rngWord
                ) +
                _addClaimableEth(
                    ContractAddresses.SDGNRS,
                    quarterShare,
                    rngWord
                ) +
                _addClaimableEth(
                    ContractAddresses.GNRUS,
                    quarterShare,
                    rngWord
                );
            if (claimableDelta != 0) claimablePool += claimableDelta;
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
    ) private returns (uint256 claimableDelta) {
        if (weiAmount == 0) return 0;

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
        return weiAmount;
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
    ) private returns (uint256 claimableDelta) {
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
            return newAmount;
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

        emit AutoRebuyProcessed(
            player,
            calc.targetLevel,
            calc.ticketCount,
            calc.ethSpent,
            calc.reserved
        );
        return calc.reserved;
    }

    /// @dev Returns true if any of the packed traits have tickets (or virtual deity entries) at the given level.
    function _hasTraitTickets(
        uint24 lvl,
        uint32 packedTraits
    ) private view returns (bool) {
        uint8[4] memory traitIds = JackpotBucketLib.unpackWinningTraits(
            packedTraits
        );
        for (uint8 i; i < 4; ) {
            uint8 trait = traitIds[i];
            if (traitBurnTicket[lvl][trait].length != 0) return true;
            // Check virtual deity entries
            uint8 fullSymId = (trait >> 6) * 8 + (trait & 0x07);
            if (fullSymId < 32 && deityBySymbol[fullSymId] != address(0))
                return true;
            unchecked {
                ++i;
            }
        }
        return false;
    }

    /// @dev Zeros budget if no trait tickets exist for the given level/traits.
    function _validateTicketBudget(
        uint256 budget,
        uint24 lvl,
        uint32 packedTraits
    ) private view returns (uint256) {
        return
            (budget != 0 && !_hasTraitTickets(lvl, packedTraits)) ? 0 : budget;
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
                LOOTBOX_MAX_WINNERS,
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
        if (count > MAX_BUCKET_WINNERS) count = MAX_BUCKET_WINNERS;
        address[] memory winners = _randTraitTicket(
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
                emit JackpotTicketWinner(
                    winner,
                    queueLvl,
                    traitId,
                    units,
                    0,
                    AWARD_TICKETS
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
    ///      This is the unified entry point for daily and early-burn jackpots.
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

    /// @dev Simple ETH flow for jackpot ETH distribution.
    function _runJackpotEthFlow(
        JackpotParams memory jp,
        uint8[4] memory traitIds,
        uint16[4] memory shareBps
    ) private returns (uint256 totalPaidEth) {
        uint16[4] memory baseBucketCounts = JackpotBucketLib.traitBucketCounts(
            jp.entropy
        );
        uint16[4] memory bucketCounts = JackpotBucketLib
            .scaleTraitBucketCountsWithCap(
                baseBucketCounts,
                jp.ethPool,
                jp.entropy,
                JACKPOT_MAX_WINNERS,
                JACKPOT_SCALE_MAX_BPS
            );
        return
            _distributeJackpotEth(
                jp.lvl,
                jp.ethPool,
                jp.entropy,
                traitIds,
                shareBps,
                bucketCounts
            );
    }

    // =========================================================================
    // Daily Jackpot ETH — Distribution
    // =========================================================================

    /// @dev Processes daily jackpot ETH distribution across all 4 trait buckets.
    ///      Iterates each bucket, selects winners proportional to shareBps,
    ///      pays out ETH via _addClaimableEth, and processes auto-rebuy.
    /// @param lvl The level whose winners are being paid.
    /// @param ethPool Total ETH to distribute across all buckets.
    /// @param entropy VRF-derived random word for winner selection.
    /// @param traitIds The 4 winning trait IDs for this daily jackpot.
    /// @param shareBps Basis-point share for each of the 4 buckets.
    /// @param bucketCounts Number of holders in each trait bucket.
    /// @return paidEth Total ETH actually paid out (may be less than ethPool if buckets empty).
    function _processDailyEth(
        uint24 lvl,
        uint256 ethPool,
        uint256 entropy,
        uint8[4] memory traitIds,
        uint16[4] memory shareBps,
        uint16[4] memory bucketCounts,
        bool isFinalDay
    ) private returns (uint256 paidEth) {
        if (ethPool == 0) {
            return 0;
        }

        uint256 unit = PriceLookupLib.priceForLevel(lvl + 1) >> 2;
        uint8 remainderIdx = JackpotBucketLib.soloBucketIndex(entropy);
        uint256[4] memory shares = JackpotBucketLib.bucketShares(
            ethPool,
            shareBps,
            bucketCounts,
            remainderIdx,
            unit
        );

        uint8[4] memory order = JackpotBucketLib.bucketOrderLargestFirst(
            bucketCounts
        );

        uint256 entropyState = entropy;
        uint256 liabilityDelta;

        for (uint8 j; j < 4; ++j) {
            uint8 traitIdx = order[j];
            uint16 count = bucketCounts[traitIdx];
            uint256 share = shares[traitIdx];
            if (count == 0 || share == 0) {
                continue;
            }

            entropyState = EntropyLib.entropyStep(
                entropyState ^ (uint256(traitIdx) << 64) ^ share
            );

            uint16 totalCount = count;
            if (totalCount > MAX_BUCKET_WINNERS)
                totalCount = MAX_BUCKET_WINNERS;

            (
                address[] memory winners,
                uint256[] memory ticketIndexes
            ) = _randTraitTicketWithIndices(
                    traitBurnTicket[lvl],
                    entropyState,
                    traitIds[traitIdx],
                    uint8(totalCount),
                    uint8(200 + traitIdx)
                );
            if (winners.length == 0) {
                continue;
            }

            uint256 perWinner = share / totalCount;
            if (perWinner == 0) {
                continue;
            }

            uint256 len = winners.length;
            for (uint256 i; i < len; ) {
                address w = winners[i];

                if (w != address(0)) {
                    uint256 claimableDelta = _addClaimableEth(
                        w,
                        perWinner,
                        entropyState
                    );
                    emit JackpotTicketWinner(
                        w,
                        lvl,
                        traitIds[traitIdx],
                        perWinner,
                        ticketIndexes[i],
                        AWARD_ETH
                    );
                    paidEth += perWinner;
                    liabilityDelta += claimableDelta;

                    if (isFinalDay && traitIdx == remainderIdx) {
                        uint256 dgnrsPool = dgnrs.poolBalance(IStakedDegenerusStonk.Pool.Reward);
                        uint256 reward = (dgnrsPool * FINAL_DAY_DGNRS_BPS) / 10_000;
                        if (reward != 0) {
                            dgnrs.transferFromPool(IStakedDegenerusStonk.Pool.Reward, w, reward);
                            emit JackpotTicketWinner(w, lvl, traitIds[traitIdx], reward, ticketIndexes[i], AWARD_DGNRS);
                        }
                    }
                }

                unchecked {
                    ++i;
                }
            }
        }

        if (liabilityDelta != 0) {
            claimablePool += liabilityDelta;
        }
        return paidEth;
    }

    function _distributeJackpotEth(
        uint24 lvl,
        uint256 ethPool,
        uint256 entropy,
        uint8[4] memory traitIds,
        uint16[4] memory shareBps,
        uint16[4] memory bucketCounts
    ) private returns (uint256 totalPaidEth) {
        JackpotEthCtx memory ctx;
        ctx.entropyState = entropy;
        ctx.lvl = lvl;

        uint256 unit = PriceLookupLib.priceForLevel(lvl + 1) >> 2;
        uint8 remainderIdx = JackpotBucketLib.soloBucketIndex(entropy);
        uint256[4] memory shares = JackpotBucketLib.bucketShares(
            ethPool,
            shareBps,
            bucketCounts,
            remainderIdx,
            unit
        );

        for (uint8 traitIdx; traitIdx < 4; ) {
            _processOneBucket(ctx, traitIdx, traitIds, shares, bucketCounts);
            unchecked {
                ++traitIdx;
            }
        }

        if (ctx.liabilityDelta != 0) {
            claimablePool += ctx.liabilityDelta;
        }
        return ctx.totalPaidEth;
    }

    /// @dev Processes a single bucket in ETH distribution.
    function _processOneBucket(
        JackpotEthCtx memory ctx,
        uint8 traitIdx,
        uint8[4] memory traitIds,
        uint256[4] memory shares,
        uint16[4] memory bucketCounts
    ) private {
        uint256 share = shares[traitIdx];

        (
            uint256 newEntropyState,
            uint256 ethDelta,
            uint256 bucketLiability,
            uint256 ticketSpent
        ) = _resolveTraitWinners(
                false,
                ctx.lvl,
                traitIds[traitIdx],
                traitIdx,
                share,
                ctx.entropyState,
                bucketCounts[traitIdx]
            );

        ctx.entropyState = newEntropyState;
        ctx.totalPaidEth += ethDelta + ticketSpent;
        ctx.liabilityDelta += bucketLiability;
    }

    // =========================================================================
    // Internal Helpers — Winner Resolution
    // =========================================================================

    /// @dev Resolves winners for a single trait bucket and distributes ETH or COIN.
    ///
    ///      FLOW:
    ///      1. Early exit if no share or no winners.
    ///      2. Select random ticket holders from the trait's burn ticket pool.
    ///      3. Credit ETH payouts to claimableWinnings (with optional loot box conversion).
    ///
    /// @param payCoin If true, pay COIN; if false, pay ETH.
    /// @param lvl Current level for ticket pool lookup.
    /// @param traitId Which trait's ticket pool to draw from.
    /// @param traitIdx Bucket index (0-3) for entropy derivation.
    /// @param traitShare Total ETH/COIN allocated to this bucket.
    /// @param entropy Current entropy state.
    /// @param winnerCount Number of winners to select.
    /// @return entropyState Updated entropy after selection.
    /// @return ethDelta ETH credited to claimable balances.
    /// @return liabilityDelta Total claimable liability added.
    /// @return ticketSpent Whale pass ETH routed to futurePrizePool.
    function _resolveTraitWinners(
        bool payCoin,
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
        ) = _randTraitTicketWithIndices(
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
        if (payCoin) {
            for (uint256 i; i < len; ) {
                _creditJackpot(true, winners[i], perWinner, entropyState);
                if (winners[i] != address(0)) {
                    emit JackpotTicketWinner(
                        winners[i],
                        lvl,
                        traitId,
                        perWinner,
                        ticketIndexes[i],
                        AWARD_BURNIE
                    );
                }

                unchecked {
                    ++i;
                }
            }
            return (entropyState, 0, 0, 0);
        }

        // Special handling for solo bucket (winnerCount == 1)
        bool isSoloBucket = (winnerCount == 1);

        uint256 totalPayout;
        uint256 totalWhalePassSpent;
        uint256 totalLiability;
        for (uint256 i; i < len; ) {
            address w = winners[i];
            if (w != address(0)) {
                if (isSoloBucket) {
                    (
                        uint256 claimDelta,
                        uint256 paid,
                        uint256 wpSpent,
                        uint256 newEntropy
                    ) = _processSoloBucketWinner(w, perWinner, entropyState);
                    if (paid != 0) {
                        emit JackpotTicketWinner(
                            w,
                            lvl,
                            traitId,
                            paid,
                            ticketIndexes[i],
                            AWARD_ETH
                        );
                    }
                    totalLiability += claimDelta;
                    totalPayout += paid;
                    totalWhalePassSpent += wpSpent;
                    entropyState = newEntropy;
                } else {
                    // Normal bucket: pay full amount
                    uint256 claimableDelta = _addClaimableEth(
                        w,
                        perWinner,
                        entropyState
                    );
                    emit JackpotTicketWinner(
                        w,
                        lvl,
                        traitId,
                        perWinner,
                        ticketIndexes[i],
                        AWARD_ETH
                    );
                    totalPayout += perWinner;
                    totalLiability += claimableDelta;
                }
            }
            unchecked {
                ++i;
            }
        }
        if (totalPayout == 0 && totalWhalePassSpent == 0)
            return (entropyState, 0, 0, 0);

        liabilityDelta = totalLiability;
        ethDelta = totalPayout;
        ticketSpent = totalWhalePassSpent;

        return (entropyState, ethDelta, liabilityDelta, ticketSpent);
    }

    // =========================================================================
    // Internal Helpers — Quest & Credit
    // =========================================================================

    /// @dev Credits a jackpot winner with COIN or ETH; no-op if beneficiary is invalid.
    /// @return claimableDelta Amount to add to claimablePool for this credit.
    function _creditJackpot(
        bool payInCoin,
        address beneficiary,
        uint256 amount,
        uint256 entropy
    ) private returns (uint256 claimableDelta) {
        if (payInCoin) {
            coinflip.creditFlip(beneficiary, amount);
            return 0;
        } else {
            // Liability is tracked by the caller to avoid per-winner SSTORE cost.
            return _addClaimableEth(beneficiary, amount, entropy);
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

            claimableDelta = _creditJackpot(false, winner, ethAmount, entropy);
            ethPaid = ethAmount;

            whalePassClaims[winner] += whalePassCount;
            _setFuturePrizePool(_getFuturePrizePool() + whalePassCost);
            whalePassSpent = whalePassCost;
        } else {
            // 25% too small for a whale pass — pay full amount as ETH
            claimableDelta = _creditJackpot(false, winner, perWinner, entropy);
            ethPaid = perWinner;
        }
    }

    /// @dev Derives daily winning traits.
    ///      Base path uses fixed symbol-0 with random color in Q0/Q1/Q2 and
    ///      fully random in Q3.
    ///
    ///      Hero override:
    ///      - If a top hero symbol exists for the current day, that symbol auto-wins
    ///        its own quadrant (with random color), replacing only that quadrant.
    function _getWinningTraits(
        uint256 randomWord
    ) private view returns (uint8[4] memory w) {
        uint8 sym;

        w[0] = (uint8(randomWord & 7) << 3) | sym;
        w[1] = 64 + ((uint8((randomWord >> 3) & 7) << 3) | sym);
        w[2] = 128 + ((uint8((randomWord >> 6) & 7) << 3) | sym);
        w[3] = 192 + uint8((randomWord >> 9) & 63);

        // Top daily hero symbol auto-wins its own quadrant with random color.
        (
            bool hasHeroWinner,
            uint8 heroQuadrant,
            uint8 heroSymbol
        ) = _topHeroSymbol(_calculateDayIndex());
        if (!hasHeroWinner) return w;

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
        uint48 day
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
    // External Entry Point — Ticket Batch Processing
    // =========================================================================

    /// @notice Processes a batch of tickets for a specific level with gas-bounded iteration.
    /// @dev Called iteratively until all tickets for the level are processed. Uses a writes budget
    ///      to stay within block gas limits. The first batch in a new level round is
    ///      scaled down by 35% to account for cold storage access costs.
    ///
    ///      GAS BUDGETING:
    ///      - Each ticket entry requires ~2 SSTOREs (trait ticket + count update).
    ///      - Budget defaults to WRITES_BUDGET_SAFE (550).
    ///
    /// @param lvl Level whose tickets should be processed.
    /// @return finished True if all tickets for this level have been fully processed.
    function processTicketBatch(uint24 lvl) external returns (bool finished) {
        uint24 rk = _tqReadKey(lvl);
        address[] storage queue = ticketQueue[rk];
        uint256 total = queue.length;

        // Check if we need to switch to this level or if already complete
        if (ticketLevel != lvl) {
            ticketLevel = lvl;
            ticketCursor = 0;
        }

        uint256 idx = ticketCursor;
        if (idx >= total) {
            // All done for this level
            delete ticketQueue[rk];
            ticketCursor = 0;
            ticketLevel = 0;
            return true;
        }

        uint32 writesBudget = WRITES_BUDGET_SAFE;
        if (idx == 0) {
            writesBudget -= (writesBudget * 35) / 100; // 65% scaling for cold storage
        }

        uint32 used;
        uint256 entropy = lootboxRngWordByIndex[lootboxRngIndex - 1];
        uint32 processed;

        while (idx < total && used < writesBudget) {
            (uint32 writesUsed, bool advance) = _processOneTicketEntry(
                queue[idx],
                lvl,
                rk,
                writesBudget - used,
                processed,
                entropy,
                idx
            );
            if (writesUsed == 0 && !advance) break; // Budget exhausted
            unchecked {
                used += writesUsed;
                if (advance) {
                    ++idx;
                    processed = 0;
                } else {
                    processed += writesUsed >> 1; // Approximate tickets processed
                }
            }
        }

        ticketCursor = uint32(idx);

        if (idx >= total) {
            // Cleanup when done
            delete ticketQueue[rk];
            ticketCursor = 0;
            ticketLevel = 0;
            return true;
        }
        return false;
    }

    /// @dev Resolves the zero-owed remainder case for ticket processing (rolls remainder).
    ///      Returns (newPacked, skip) where skip=true means player should be skipped.
    function _resolveZeroOwedRemainder(
        uint40 packed,
        uint24,
        uint24 rk,
        address player,
        uint256 entropy,
        uint256 rollSalt
    ) private returns (uint40 newPacked, bool skip) {
        uint8 rem = uint8(packed);
        if (rem == 0) {
            if (packed != 0) {
                ticketsOwedPacked[rk][player] = 0;
            }
            return (0, true);
        }

        bool win = _rollRemainder(entropy, rollSalt, rem);
        if (!win) {
            ticketsOwedPacked[rk][player] = 0;
            return (0, true);
        }

        newPacked = uint40(1) << 8;
        if (newPacked != packed) {
            ticketsOwedPacked[rk][player] = newPacked;
        }
        return (newPacked, false);
    }

    /// @dev Processes a single ticket entry, returning writes used and whether to advance.
    function _processOneTicketEntry(
        address player,
        uint24 lvl,
        uint24 rk,
        uint32 room,
        uint32 processed,
        uint256 entropy,
        uint256 queueIdx
    ) private returns (uint32 writesUsed, bool advance) {
        uint40 packed = ticketsOwedPacked[rk][player];
        uint32 owed = uint32(packed >> 8);
        uint256 rollSalt = (uint256(lvl) << 224) |
            (queueIdx << 192) |
            (uint256(uint160(player)) << 32);

        // Handle zero-owed case
        if (owed == 0) {
            bool skip;
            (packed, skip) = _resolveZeroOwedRemainder(
                packed,
                lvl,
                rk,
                player,
                entropy,
                rollSalt
            );
            // Charge one budget unit even when skipping so sparse/remainder-only
            // queues cannot bypass the per-call work cap.
            if (skip) return (1, true);
            owed = 1;
        }

        // Calculate overhead and batch size
        uint32 baseOv = (processed == 0 && owed <= 2) ? 4 : 2;
        if (room <= baseOv) return (0, false);
        uint32 take;
        {
            uint32 availRoom = room - baseOv;
            uint32 maxT = (availRoom <= 256)
                ? (availRoom >> 1)
                : (availRoom - 256);
            take = owed > maxT ? maxT : owed;
        }
        if (take == 0) return (0, false);

        // Generate trait tickets
        _generateTicketBatch(player, lvl, processed, take, entropy, queueIdx);

        // Calculate writes and finalize
        writesUsed =
            ((take <= 256) ? (take << 1) : (take + 256)) +
            baseOv +
            (take == owed ? 1 : 0);
        advance = _finalizeTicketEntry(
            rk,
            player,
            packed,
            owed,
            take,
            entropy,
            rollSalt
        );
        return (writesUsed, advance);
    }

    /// @dev Wrapper for _raritySymbolBatch to reduce stack usage.
    function _generateTicketBatch(
        address player,
        uint24 lvl,
        uint32 processed,
        uint32 take,
        uint256 entropy,
        uint256 queueIdx
    ) private {
        uint256 baseKey = (uint256(lvl) << 224) |
            (queueIdx << 192) |
            (uint256(uint160(player)) << 32);
        _raritySymbolBatch(player, baseKey, processed, take, entropy);
        emit TraitsGenerated(
            player,
            lvl,
            uint32(queueIdx),
            processed,
            take,
            entropy
        );
    }

    /// @dev Finalizes ticket entry after processing, rolling remainder dust.
    function _finalizeTicketEntry(
        uint24 rk,
        address player,
        uint40 packed,
        uint32 owed,
        uint32 take,
        uint256 entropy,
        uint256 rollSalt
    ) private returns (bool done) {
        uint8 rem = uint8(packed);
        uint32 remainingOwed;
        unchecked {
            remainingOwed = owed - take;
        }
        if (remainingOwed == 0 && rem != 0) {
            if (_rollRemainder(entropy, rollSalt, rem)) {
                remainingOwed = 1;
            }
            rem = 0;
        }
        uint40 newPacked = (uint40(remainingOwed) << 8) | uint40(rem);
        if (newPacked != packed) {
            ticketsOwedPacked[rk][player] = newPacked;
        }
        return remainingOwed == 0;
    }

    /// @dev Roll remainder chance for a fractional ticket (0-99).
    function _rollRemainder(
        uint256 entropy,
        uint256 rollSalt,
        uint8 rem
    ) private pure returns (bool win) {
        uint256 rollEntropy = EntropyLib.entropyStep(entropy ^ rollSalt);
        return (rollEntropy % TICKET_SCALE) < rem;
    }

    // =========================================================================
    // Internal Helpers — Batch Trait Generation
    // =========================================================================

    /// @dev Generates trait tickets in batch for a player's ticket awards using LCG-based PRNG.
    ///      Uses inline assembly for gas-efficient bulk storage writes.
    ///
    ///      ALGORITHM:
    ///      1. Generate traits in groups of 16 using LCG stepping.
    ///      2. Track unique traits touched and their occurrence counts in memory.
    ///      3. Batch-write all occurrences to storage in a single pass per trait.
    ///
    /// @param player Address receiving the trait tickets.
    /// @param baseKey Encoded key containing level, index, and player address.
    /// @param startIndex Starting position within this player's owed tickets.
    /// @param count Number of ticket entries to process this batch.
    /// @param entropyWord VRF entropy for trait generation.
    function _raritySymbolBatch(
        address player,
        uint256 baseKey,
        uint32 startIndex,
        uint32 count,
        uint256 entropyWord
    ) private {
        // Memory arrays to track which traits were generated and how many times.
        uint32[256] memory counts;
        uint8[256] memory touchedTraits;
        uint16 touchedLen;

        uint32 endIndex;
        unchecked {
            endIndex = startIndex + count;
        }
        uint32 i = startIndex;

        // Generate traits in groups of 16, using LCG for deterministic randomness.
        while (i < endIndex) {
            uint32 groupIdx = i >> 4; // Group index (per 16 symbols)

            uint256 seed;
            unchecked {
                seed = (baseKey + groupIdx) ^ entropyWord;
            }
            uint64 s = uint64(seed) | 1; // Ensure odd for full LCG period
            uint8 offset = uint8(i & 15);
            unchecked {
                s = s * (TICKET_LCG_MULT + uint64(offset)) + uint64(offset);
            }

            for (uint8 j = offset; j < 16 && i < endIndex; ) {
                unchecked {
                    s = s * TICKET_LCG_MULT + 1; // LCG step

                    // Generate trait using weighted distribution, add quadrant offset.
                    uint8 traitId = DegenerusTraitUtils.traitFromWord(s) +
                        (uint8(i & 3) << 6);

                    // Track first occurrence of each trait for batch writing.
                    if (counts[traitId]++ == 0) {
                        touchedTraits[touchedLen++] = traitId;
                    }
                    ++i;
                    ++j;
                }
            }
        }

        // Extract level from baseKey for storage slot calculation.
        uint24 lvl = uint24(baseKey >> 224);

        // Calculate the storage slot for this level's trait arrays.
        // Layout assumption: traitBurnTicket is mapping(uint24 => address[][256]).
        // Solidity stores mapping(key => fixedArray) as keccak256(key . slot) + index,
        // with dynamic array elements at keccak256(keccak256(key . slot) + index).
        // This relies on the standard Solidity storage layout (stable since 0.4.x).
        // Safe here because the contract is non-upgradeable.
        uint256 levelSlot;
        assembly ("memory-safe") {
            mstore(0x00, lvl)
            mstore(0x20, traitBurnTicket.slot)
            levelSlot := keccak256(0x00, 0x40)
        }

        // Batch-write trait tickets to storage using assembly for gas efficiency.
        for (uint16 u; u < touchedLen; ) {
            uint8 traitId = touchedTraits[u];
            uint32 occurrences = counts[traitId];

            assembly ("memory-safe") {
                // Get array length slot and current length.
                let elem := add(levelSlot, traitId)
                let len := sload(elem)
                let newLen := add(len, occurrences)
                sstore(elem, newLen)

                // Calculate data slot and write player address `occurrences` times.
                mstore(0x00, elem)
                let data := keccak256(0x00, 0x20)
                let dst := add(data, len)
                for {
                    let k := 0
                } lt(k, occurrences) {
                    k := add(k, 1)
                } {
                    sstore(dst, player)
                    dst := add(dst, 1)
                }
            }
            unchecked {
                ++u;
            }
        }
    }

    // =========================================================================
    // Internal Helpers — Winner Selection
    // =========================================================================

    /// @dev Selects random winners from a trait's ticket pool.
    ///      NOTE: Duplicates are intentionally allowed — more tickets = more chances to win multiple times.
    ///
    /// @param traitBurnTicket_ Storage reference to the trait ticket mapping.
    /// @param randomWord VRF entropy for selection.
    /// @param trait Trait ID to select from.
    /// @param numWinners Number of winners to select.
    /// @param salt Additional entropy to differentiate calls.
    /// @return winners Array of selected winner addresses (may contain duplicates).
    function _randTraitTicket(
        address[][256] storage traitBurnTicket_,
        uint256 randomWord,
        uint8 trait,
        uint8 numWinners,
        uint8 salt
    ) private view returns (address[] memory winners) {
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
            return new address[](0);
        }

        winners = new address[](numWinners);
        for (uint256 i; i < numWinners; ) {
            uint256 idx = uint256(keccak256(abi.encode(randomWord, trait, salt, i))) % effectiveLen;
            winners[i] = idx < len ? holders[idx] : deity;
            unchecked {
                ++i;
            }
        }
    }

    /// @dev Same selection as _randTraitTicket plus winner ticket indices.
    function _randTraitTicketWithIndices(
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
            uint256 idx = uint256(keccak256(abi.encode(randomWord, trait, salt, i))) % effectiveLen;
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

    /// @dev Calculate current day index with testnet offset applied.
    ///      Day 1 = deploy day. Days reset at JACKPOT_RESET_TIME (22:57 UTC).
    /// @return Day index (1-indexed from deploy day).
    function _calculateDayIndex() private view returns (uint48) {
        return _simulatedDayIndex();
    }

    /// @notice Pays daily BURNIE jackpot to random ticket holders.
    /// @dev Runs every day in its own transaction. Awards 0.5% of prize pool target in BURNIE.
    ///      75% goes to near-future trait-matched winners ([lvl, lvl+4]).
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

        uint48 questDay = _calculateDayIndex();
        (uint32 winningTraitsPacked, bool valid) = _loadDailyWinningTraits(
            lvl,
            questDay
        );
        if (!valid) {
            bool useBurn = jackpotPhaseFlag;
            winningTraitsPacked = _rollWinningTraits(randWord, useBurn);
            _syncDailyWinningTraits(lvl, winningTraitsPacked, questDay);
        }

        uint256 entropy = randWord ^
            (uint256(lvl) << 192) ^
            uint256(COIN_JACKPOT_TAG);
        uint24 targetLevel = _selectDailyCoinTargetLevel(
            lvl,
            winningTraitsPacked,
            entropy
        );
        if (targetLevel == 0) return;

        _awardDailyCoinToTraitWinners(
            targetLevel,
            winningTraitsPacked,
            nearBudget,
            entropy
        );
    }

    /// @dev Pick one random level in [lvl, lvl+4] — pure 1-in-5 chance per level.
    ///      Returns 0 (skip) if the chosen level has no eligible trait tickets.
    function _selectDailyCoinTargetLevel(
        uint24 lvl,
        uint32 winningTraitsPacked,
        uint256 entropy
    ) private view returns (uint24 targetLevel) {
        uint24 candidate = lvl + uint24(entropy % 5);
        if (_hasTraitTickets(candidate, winningTraitsPacked)) {
            return candidate;
        }
        return 0;
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

        address[3] memory batchPlayers;
        uint256[3] memory batchAmounts;
        uint256 batchCount;

        for (uint8 traitIdx; traitIdx < 4; ) {
            uint16 count = counts[traitIdx];
            if (count != 0) {
                entropy = EntropyLib.entropyStep(
                    entropy ^ (uint256(traitIdx) << 64) ^ coinBudget
                );

                if (count > MAX_BUCKET_WINNERS) count = MAX_BUCKET_WINNERS;
                (
                    address[] memory bucketWinners,
                    uint256[] memory bucketTicketIndexes
                ) = _randTraitTicketWithIndices(
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
                        emit JackpotTicketWinner(
                            winner,
                            lvl,
                            traitIds[traitIdx],
                            amount,
                            bucketTicketIndexes[i],
                            AWARD_BURNIE
                        );
                        batchPlayers[batchCount] = winner;
                        batchAmounts[batchCount] = amount;
                        unchecked {
                            ++batchCount;
                        }
                        if (batchCount == 3) {
                            coinflip.creditFlipBatch(
                                batchPlayers,
                                batchAmounts
                            );
                            batchCount = 0;
                        }
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

        if (batchCount != 0) {
            for (uint256 i = batchCount; i < 3; ) {
                batchPlayers[i] = address(0);
                batchAmounts[i] = 0;
                unchecked {
                    ++i;
                }
            }
            coinflip.creditFlipBatch(batchPlayers, batchAmounts);
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

        address[3] memory batchPlayers;
        uint256[3] memory batchAmounts;
        uint256 batchCount;

        for (uint8 i; i < found; ) {
            emit FarFutureCoinJackpotWinner(
                winners[i],
                lvl,
                winnerLevels[i],
                perWinner
            );

            batchPlayers[batchCount] = winners[i];
            batchAmounts[batchCount] = perWinner;
            unchecked {
                ++batchCount;
            }

            if (batchCount == 3) {
                coinflip.creditFlipBatch(batchPlayers, batchAmounts);
                batchCount = 0;
            }

            unchecked {
                ++i;
            }
        }

        if (batchCount != 0) {
            for (uint256 j = batchCount; j < 3; ) {
                batchPlayers[j] = address(0);
                batchAmounts[j] = 0;
                unchecked {
                    ++j;
                }
            }
            coinflip.creditFlipBatch(batchPlayers, batchAmounts);
        }
    }

    /// @dev Roll or derive the packed winning traits for a given level.
    ///      When burn counts are used, applies hero override (if any).
    function _rollWinningTraits(
        uint256 randWord,
        bool useBurnCounts
    ) private view returns (uint32 packed) {
        if (useBurnCounts) {
            packed = JackpotBucketLib.packWinningTraits(
                _getWinningTraits(randWord)
            );
        } else {
            packed = JackpotBucketLib.packWinningTraits(
                JackpotBucketLib.getRandomTraits(randWord)
            );
        }
    }

    function _syncDailyWinningTraits(
        uint24 lvl,
        uint32 packed,
        uint48 questDay
    ) private {
        lastDailyJackpotWinningTraits = packed;
        lastDailyJackpotLevel = lvl;
        lastDailyJackpotDay = questDay;
    }

    function _loadDailyWinningTraits(
        uint24 lvl,
        uint48 questDay
    ) private view returns (uint32 packed, bool valid) {
        packed = lastDailyJackpotWinningTraits;
        valid = (lastDailyJackpotDay == questDay &&
            lastDailyJackpotLevel == lvl);
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
        (
            address[] memory winnersArr,
            uint256[] memory amountsArr,

        ) = jackpots.runBafJackpot(poolWei, lvl, rngWord);

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
                claimableDelta += _addClaimableEth(winner, ethPortion, rngWord);
                emit JackpotTicketWinner(winner, lvl, 0, ethPortion, 0, AWARD_ETH);

                // Lootbox half: small amounts awarded immediately, large deferred
                if (lootboxPortion <= LOOTBOX_CLAIM_THRESHOLD) {
                    // Small lootbox: award immediately (2 rolls, probabilistic targeting)
                    rngWord = _awardJackpotTickets(
                        winner,
                        lootboxPortion,
                        lvl,
                        rngWord
                    );
                    emit JackpotTicketWinner(winner, lvl, 0, lootboxPortion, 0, AWARD_TICKETS);
                } else {
                    // Large lootbox: defer to claim (whale pass equivalent)
                    _queueWhalePassClaimCore(winner, lootboxPortion);
                    emit JackpotTicketWinner(winner, lvl, 0, lootboxPortion, 0, AWARD_WHALE_PASS);
                }
            }
            // Small winners: alternate between 100% ETH and 100% lootbox for gas efficiency
            else if (i % 2 == 0) {
                // Even index: 100% ETH (immediate liquidity)
                claimableDelta += _addClaimableEth(winner, amount, rngWord);
                emit JackpotTicketWinner(winner, lvl, 0, amount, 0, AWARD_ETH);
            } else {
                // Odd index: 100% lootbox (upside exposure)
                rngWord = _awardJackpotTickets(winner, amount, lvl, rngWord);
                emit JackpotTicketWinner(winner, lvl, 0, amount, 0, AWARD_TICKETS);
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
