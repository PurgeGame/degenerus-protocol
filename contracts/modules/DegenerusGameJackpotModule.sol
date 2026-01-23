// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IDegenerusCoinModule} from "../interfaces/DegenerusGameModuleInterfaces.sol";
import {IDegenerusStonk} from "../interfaces/IDegenerusStonk.sol";
import {IStETH} from "../interfaces/IStETH.sol";
import {DegenerusGameStorage} from "../storage/DegenerusGameStorage.sol";
import {DegenerusTraitUtils} from "../DegenerusTraitUtils.sol";
import {ContractAddresses} from "../ContractAddresses.sol";

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
 *      1. `calcPrizePoolForLevelJackpot` — Computes pool splits (reward vs prize vs level jackpot) at level start.
 *      2. `payLevelJackpotLootbox` / `payLevelJackpotEth` — Distributes the level jackpot after purchases close.
 *      3. `payDailyJackpot` — Handles early-burn rewards during purchase phase and rolling dailies at EOL.
 *      4. Legacy: `payExterminationJackpot` (unused in current flow).
 *      5. `processTicketBatch` — Batched airdrop processing with gas budgeting to stay block-safe.
 *
 *      FUND ACCOUNTING:
 *      - ETH flows through `futurePrizePool` (unified reserve), `currentPrizePool`,
 *        `nextPrizePool`, `claimablePool`.
 *      - The remainder goes to the exterminated trait bucket when set; otherwise the solo bucket absorbs dust.
 *      - `claimableWinnings` tracks per-player ETH; `claimablePool` is the aggregate liability.
 *
 *      RANDOMNESS:
 *      - All entropy originates from VRF words passed by the parent contract.
 *      - Internal `_entropyStep` provides deterministic derivation for sub-selections.
 *      - Winner selection intentionally allows duplicates (more tickets = more chances).
 */
contract DegenerusGameJackpotModule is DegenerusGameStorage {
    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    /// @notice Emitted when ETH is credited to a player's claimable balance.
    /// @param player The original winner (ticket holder).
    /// @param recipient The address receiving the credit (same as player in current impl).
    /// @param amount Wei credited.
    event PlayerCredited(address indexed player, address indexed recipient, uint256 amount);

    /// @notice Emitted when auto-rebuy converts winnings to tickets.
    /// @param player Player whose winnings were converted.
    /// @param targetLevel Level for which tickets were purchased.
    /// @param ticketCount Number of tickets credited.
    /// @param ethSpent Amount of ETH spent on tickets (added to futurePrizePool).
    /// @param remainder Amount returned to claimableWinnings.
    event AutoRebuyProcessed(
        address indexed player,
        uint24 targetLevel,
        uint32 ticketCount,
        uint256 ethSpent,
        uint256 remainder
    );

    /// @notice Generic revert for invalid values.
    error E();

    // -------------------------------------------------------------------------
    // External Contract References (compile-time constants)
    // -------------------------------------------------------------------------

    IDegenerusCoinModule internal constant coin = IDegenerusCoinModule(ContractAddresses.COIN);
    IStETH internal constant steth = IStETH(ContractAddresses.STETH_TOKEN);
    IDegenerusStonk internal constant dgnrs = IDegenerusStonk(ContractAddresses.DGNRS);

    // -------------------------------------------------------------------------
    // Constants — Timing & Thresholds
    // -------------------------------------------------------------------------

    /// @dev Seconds offset from midnight UTC for daily jackpot reset boundary (22:57 UTC).
    uint48 private constant JACKPOT_RESET_TIME = 82620;

    /// @dev Maximum number of daily jackpots per level before forcing level transition.
    uint8 private constant JACKPOT_LEVEL_CAP = 10;

    // -------------------------------------------------------------------------
    // Constants — Share Distribution (Basis Points)
    // -------------------------------------------------------------------------

    /// @dev Level jackpot trait bucket shares packed into 64 bits: [6000, 1333, 1333, 1334] = 10000 bps.
    ///      With rotation, the 60% share is assigned to the solo (1-winner) bucket.
    uint64 private constant LEVEL_JACKPOT_SHARES_PACKED =
        (uint64(6000)) | (uint64(1333) << 16) | (uint64(1333) << 32) | (uint64(1334) << 48);

    /// @dev Daily jackpot trait bucket shares: 2000 bps each × 4 = 8000 bps (remaining 20% goes to exterminated trait when set).
    uint64 private constant DAILY_JACKPOT_SHARES_PACKED = uint64(2000) * 0x0001000100010001;

    // -------------------------------------------------------------------------
    // Constants — Entropy Salts
    // -------------------------------------------------------------------------

    /// @dev Domain separator for coin jackpot entropy derivation.
    bytes32 private constant COIN_JACKPOT_TAG = keccak256("coin-jackpot");

    /// @dev Target future/next ratio in bps (2.0x = 20000 bps).
    uint16 private constant FUTURE_NEXT_TARGET_BPS = 20_000;

    /// @dev Max skew applied to next-pool rebalancing (±3%).
    uint16 private constant FUTURE_NEXT_SKEW_MAX_BPS = 300;

    /// @dev Random jitter around the mean skew (±1%).
    uint16 private constant FUTURE_NEXT_SKEW_JITTER_BPS = 100;

    /// @dev Max adjustment from future/next ratio (±1.5%).
    uint16 private constant FUTURE_NEXT_RATIO_ADJUST_MAX_BPS = 150;

    /// @dev Time thresholds for skew curve.
    uint48 private constant FUTURE_NEXT_TIME_FAST = 1 days;
    uint48 private constant FUTURE_NEXT_TIME_PEAK = 14 days;
    uint48 private constant FUTURE_NEXT_TIME_DECAY = 28 days;

    /// @dev Sentinel value for "no extermination yet" / "no last level extermination".
    uint16 private constant TRAIT_ID_TIMEOUT = 420;

    /// @dev Sentinel value for levelStartTime indicating "not started".
    uint48 private constant LEVEL_START_SENTINEL = type(uint48).max;

    /// @dev Domain separator for future/next skew roll derivation.
    bytes32 private constant FUTURE_NEXT_SKEW_TAG = keccak256("future-next-skew");

    /// @dev Domain separator for rare future-pool dump roll derivation.
    bytes32 private constant FUTURE_DUMP_TAG = keccak256("future-dump");

    /// @dev Domain separator for level-100 future pool keep roll derivation.
    bytes32 private constant FUTURE_KEEP_TAG = keccak256("future-keep");

    /// @dev 1 in 1 quadrillion chance for a 90% future->current dump on normal levels.
    uint256 private constant FUTURE_DUMP_ODDS = 1_000_000_000_000_000;

    // -------------------------------------------------------------------------
    // Constants — Gas Budgeting (Ticket Batch Processing)
    // -------------------------------------------------------------------------

    /// @dev Default SSTORE budget for processTicketBatch to stay safely under 15M gas.
    uint32 private constant WRITES_BUDGET_SAFE = 780;

    /// @dev Minimum writes budget to ensure progress even with very low caps.
    uint32 private constant WRITES_BUDGET_MIN = 8;

    /// @dev LCG multiplier for deterministic trait generation (Knuth's MMIX constant).
    uint64 private constant TICKET_LCG_MULT = 0x5851F42D4C957F2D;

    /// @dev Portion of level jackpot ETH converted to tickets (20%).
    uint16 private constant LEVEL_JACKPOT_TICKET_BPS = 2000;

    /// @dev Portion of DGNRS reward pool paid to the level jackpot big winner (1%).
    uint16 private constant LEVEL_JACKPOT_DGNRS_BPS = 100;

    /// @dev Portion of daily jackpot ETH converted to tickets (20%).
    uint16 private constant DAILY_JACKPOT_TICKET_BPS = 2000;

    /// @dev Portion of reward-pool-funded daily jackpot ETH converted to loot boxes (50%).
    uint16 private constant DAILY_REWARD_JACKPOT_LOOTBOX_BPS = 5000;

    /// @dev Portion of purchase-phase reward-pool jackpots converted to loot boxes (3/4).
    uint16 private constant PURCHASE_REWARD_JACKPOT_LOOTBOX_BPS = 7500;

    /// @dev Max winners per single trait bucket (must fit in uint8 for _randTraitTicket).
    ///      Set to 250 to allow all ticket winners in single trait if others are empty.
    uint8 private constant MAX_BUCKET_WINNERS = 250;

    /// @dev Loot box EV configuration (basis points of total ETH).
    ///      Tickets are rolled 5/6 of the time; burnie is rolled 1/6.
    uint16 private constant LOOTBOX_TICKET_EV_BPS = 9000;
    uint16 private constant LOOTBOX_BURNIE_EV_BPS = 1500;

    /// @dev Per-roll payout scaling to preserve expected EV across 1–6 outcomes.
    uint16 private constant LOOTBOX_TICKET_ROLL_BPS = uint16((uint256(LOOTBOX_TICKET_EV_BPS) * 6) / 5);
    uint16 private constant LOOTBOX_BURNIE_ROLL_BPS = uint16(uint256(LOOTBOX_BURNIE_EV_BPS) * 6);

    /// @dev Loot box amount split threshold (two rolls when exceeded).
    uint256 private constant LOOTBOX_SPLIT_THRESHOLD = 0.5 ether;

    // -------------------------------------------------------------------------
    // Constants — Jackpot Bucket Scaling (Gas Guardrails)
    // -------------------------------------------------------------------------

    /// @dev Maximum total winners per jackpot payout (including solo bucket).
    uint16 private constant JACKPOT_MAX_WINNERS = 300;

    /// @dev Maximum total ETH winners across daily + carryover jackpots.
    uint16 private constant DAILY_ETH_MAX_WINNERS = 321;

    /// @dev Maximum winners for daily coin jackpot (coin.creditFlip is 1 external call each).
    uint16 private constant DAILY_COIN_MAX_WINNERS = 50;

    /// @dev Salt base for daily coin jackpot winner selection.
    uint8 private constant DAILY_COIN_SALT_BASE = 252;

    /// @dev Maximum winners for lootbox jackpot distributions (gas safety).
    ///      Lower than JACKPOT_MAX_WINNERS because lootboxes do multiple rolls per winner.
    uint16 private constant LOOTBOX_MAX_WINNERS = 100;

    /// @dev Maximum rolls per lootbox winner (gas safety).
    ///      Worst case: 100 winners × 2 rolls = 200 total rolls = ~7M gas (safe under 16M target).
    uint8 private constant LOOTBOX_MAX_ROLLS = 2;

    /// @dev Minimum pool size before scaling kicks in.
    uint256 private constant JACKPOT_SCALE_MIN_WEI = 10 ether;

    /// @dev First scale target (2x) by this pool size.
    uint256 private constant JACKPOT_SCALE_FIRST_WEI = 50 ether;

    /// @dev Second scale target (4x) by this pool size; cap beyond.
    uint256 private constant JACKPOT_SCALE_SECOND_WEI = 200 ether;

    /// @dev Scale values in basis points.
    uint16 private constant JACKPOT_SCALE_BASE_BPS = 10_000;
    uint16 private constant JACKPOT_SCALE_FIRST_BPS = 20_000;
    uint16 private constant JACKPOT_SCALE_MAX_BPS = 40_000;

    // -------------------------------------------------------------------------
    // Structs
    // -------------------------------------------------------------------------

    /// @dev Mutable context passed through ETH distribution loops to track cumulative state.
    ///      Using a struct avoids stack-too-deep and makes the flow explicit.
    struct JackpotEthCtx {
        uint256 entropyState; // Rolling entropy for winner selection.
        uint256 liabilityDelta; // Cumulative claimable liability added this run.
        uint256 totalPaidEth; // Total ETH paid out (including ticket conversions).
    }

    /// @dev Packed parameters for a single jackpot execution. Keeps external call surface lean
    ///      and avoids passing 6+ parameters through multiple internal functions.
    struct JackpotParams {
        uint24 lvl; // Current game level (1-indexed).
        uint256 ethPool; // ETH available for this jackpot.
        uint256 coinPool; // COIN available for this jackpot.
        uint256 entropy; // VRF-derived entropy for winner selection.
        uint32 winningTraitsPacked; // 4 trait IDs packed into 32 bits (8 bits each).
        uint64 traitShareBpsPacked; // 4 share percentages packed (16 bits each).
    }

    // =========================================================================
    // External Entry Points (delegatecall targets)
    // =========================================================================

    /// @notice Pays early-burn jackpots during purchase phase OR rolling daily jackpots at level end.
    /// @dev Called by the parent game contract via delegatecall. Two distinct paths:
    ///
    ///      DAILY PATH (isDaily=true):
    ///      - Distributes an escalating slice of the remaining currentPrizePool to trait-based winners.
    ///      - Seeds next level's carryover jackpot at flat 0.5% from the unified future pool.
    ///      - Distributes loot boxes immediately to winners (50% of carryover budget).
    ///      - Increments jackpotCounter; clears dailyBurnCount on completion.
    ///
    ///      EARLY-BURN PATH (isDaily=false):
    ///      - Triggered during purchase phase when early burns occur.
    ///      - Pays BURNIE only (0.5% of coin-equivalent lastPrizePool).
    ///      - 1/3 chance: Awards BURNIE to random future ticket holders:
    ///        * 75% of budget to levels +2 to +5 (up to 40 winners per level)
    ///        * 25% of budget to levels +6 to +50 (up to 2 winners per level)
    ///      - 2/3 chance: Awards BURNIE to trait-based winners (normal path).
    ///      - No ETH bonuses from reward/futurePool during purchase phase.
    ///
    /// @param isDaily True for scheduled daily jackpot, false for early-burn jackpot.
    /// @param lvl Current game level.
    /// @param randWord VRF entropy for winner selection and trait derivation.
    function payDailyJackpot(bool isDaily, uint24 lvl, uint256 randWord) external {
        uint48 questDay = _calculateDayIndex();
        uint32 winningTraitsPacked;

        if (isDaily) {
            winningTraitsPacked = _packWinningTraits(_getWinningTraits(randWord, dailyBurnCount));
            winningTraitsPacked = _applyExterminatedTraitPacked(winningTraitsPacked, lvl);
            lastDailyJackpotWinningTraits = winningTraitsPacked;
            lastDailyJackpotLevel = lvl;
            lastDailyJackpotDay = questDay;
            uint8 counter = jackpotCounter;
            uint8 counterStep = 1;
            uint256 poolSnapshot = currentPrizePool;
            uint16 dailyBps = uint16(DAILY_JACKPOT_BPS_PACKED >> (uint256(counter) * 16));
            uint256 budget = (poolSnapshot * dailyBps) / 10_000;
            if (
                currentExterminatedTrait != TRAIT_ID_TIMEOUT &&
                (counter + 2) < JACKPOT_LEVEL_CAP
            ) {
                uint16 nextBps = uint16(DAILY_JACKPOT_BPS_PACKED >> (uint256(counter + 1) * 16));
                uint256 remaining = poolSnapshot - budget;
                budget += (remaining * nextBps) / 10_000;
                counterStep = 2;
            }

            // Gas optimization: 20% = 1/5 (cheaper than * 2000 / 10000)
            // DAILY_JACKPOT_TICKET_BPS = 2000 = 20%, so budget * 2000 / 10000 = budget / 5
            uint256 dailyLootboxBudget = budget / 5;
            if (dailyLootboxBudget != 0 && !_hasTraitTickets(lvl, winningTraitsPacked)) {
                dailyLootboxBudget = 0;
            }
            if (dailyLootboxBudget != 0) {
                budget -= dailyLootboxBudget;
            }

            uint256 entropyDaily = randWord ^ (uint256(lvl) << 192);
            (, uint16[4] memory bucketCountsDaily) = _bucketCountsForPool(
                budget,
                entropyDaily
            );
            bucketCountsDaily = _capBucketCounts(bucketCountsDaily, DAILY_ETH_MAX_WINNERS, entropyDaily);

            uint8[4] memory traitIdsDaily = _unpackWinningTraits(winningTraitsPacked);
            uint16[4] memory shareBpsDaily = _shareBpsByBucket(
                DAILY_JACKPOT_SHARES_PACKED,
                uint8(entropyDaily & 3)
            );
            uint256 paidDailyEth = _distributeJackpotEth(
                lvl,
                budget,
                entropyDaily,
                traitIdsDaily,
                shareBpsDaily,
                bucketCountsDaily,
                0,
                0
            );
            currentPrizePool -= paidDailyEth;

            // Distribute daily ticket budget to current level winners
            if (dailyLootboxBudget != 0) {
                // Gas optimization: Avoid division-before-division precision loss
                // Tickets cost price/4, so units = budget / (price/4) = (budget * 4) / price
                uint256 ticketUnits = (dailyLootboxBudget * 4) / uint256(price);
                if (ticketUnits != 0) {
                    // Deduct from current pool and add to next pool to back tickets
                    currentPrizePool -= dailyLootboxBudget;
                    nextPrizePool += dailyLootboxBudget;

                    // Distribute tickets to current level trait winners
                    _distributeTicketJackpot(
                        lvl,
                        winningTraitsPacked,
                        ticketUnits,
                        entropyDaily,
                        LOOTBOX_MAX_WINNERS,
                        241,
                        false // asLootbox=false (already added to nextPrizePool)
                    );
                }
            }

            uint24 nextLevel = lvl + 1;

            // Gas optimization: 1% = 1/100 (cheaper than * 100 / 10000)
            // Unified reserve slice
            uint256 reserveSlice = futurePrizePool / 100;

            // Deduct immediately (upfront model)
            futurePrizePool -= reserveSlice;

            uint256 futureEthPool = reserveSlice;
            uint16 carryoverLootboxBps = DAILY_REWARD_JACKPOT_LOOTBOX_BPS;

            // Calculate loot box budget instead of tickets
            uint256 carryoverLootboxBudget = (futureEthPool * carryoverLootboxBps) / 10_000;
            if (carryoverLootboxBudget != 0 && !_hasTraitTickets(nextLevel, winningTraitsPacked)) {
                carryoverLootboxBudget = 0;
            }
            if (carryoverLootboxBudget != 0) {
                futureEthPool -= carryoverLootboxBudget;
                // Pools already deducted upfront; just add lootbox budget to nextPrizePool
                nextPrizePool += carryoverLootboxBudget;
            }

            uint256 entropyNext = randWord ^ (uint256(nextLevel) << 192);
            (, uint16[4] memory bucketCountsNext) = _bucketCountsForPool(futureEthPool, entropyNext);
            uint256 totalDailyWinners = _sumBucketCounts(bucketCountsDaily);
            uint16 remainingCap = totalDailyWinners >= DAILY_ETH_MAX_WINNERS
                ? 0
                : uint16(DAILY_ETH_MAX_WINNERS - totalDailyWinners);
            bucketCountsNext = _capBucketCounts(bucketCountsNext, remainingCap, entropyNext);

            uint256 paidCarryEth;
            if (futureEthPool != 0) {
                uint8[4] memory traitIds = _unpackWinningTraits(winningTraitsPacked);
                uint16[4] memory shareBps = _shareBpsByBucket(DAILY_JACKPOT_SHARES_PACKED, uint8(entropyNext & 3));
                paidCarryEth = _distributeJackpotEth(
                    nextLevel,
                    futureEthPool,
                    entropyNext,
                    traitIds,
                    shareBps,
                    bucketCountsNext,
                    0,
                    0
                );
            }
            // Pools already deducted upfront; no additional deduction needed

            // Distribute tickets instead of lootboxes
            if (carryoverLootboxBudget != 0) {
                // Gas optimization: (budget * 4) / price instead of budget / (price/4)
                uint256 ticketUnits = (carryoverLootboxBudget * 4) / uint256(price);
                if (ticketUnits != 0) {
                    _distributeTicketJackpot(
                        nextLevel,
                        winningTraitsPacked,
                        ticketUnits,
                        entropyNext,
                        LOOTBOX_MAX_WINNERS,
                        240,
                        false // asLootbox=false (we already added to nextPrizePool)
                    );
                }
            }

            unchecked {
                jackpotCounter = counter + counterStep;
            }
            _clearDailyBurnCount();

            _rollQuestForJackpot(randWord, false, questDay);
            return;
        }

        // Non-daily (early-burn) path - BURNIE only, no ETH bonuses
        winningTraitsPacked = _packWinningTraits(_getRandomTraits(randWord));
        lastDailyJackpotWinningTraits = winningTraitsPacked;
        lastDailyJackpotLevel = lvl;
        lastDailyJackpotDay = questDay;

        bool isEthDay = false;
        uint48 startTime = levelStartTime;
        if (startTime != type(uint48).max) {
            uint48 startDayBoundary = uint48((startTime - JACKPOT_RESET_TIME) / 1 days);
            uint48 startDay = startDayBoundary - ContractAddresses.DEPLOY_DAY_BOUNDARY + 1;
            if (questDay > startDay) {
                uint48 daysSince = questDay - startDay;
                isEthDay = (daysSince % 3) == 0 && lvl != 1;  // Skip every-3rd-day ETH jackpot at level 1
            }
        }
        uint256 ethDaySlice;
        if (isEthDay) {
            uint256 poolBps = 100; // 1% from each pool every third day
            ethDaySlice = (futurePrizePool * poolBps) / 10_000;

            // Deduct immediately (upfront model)
            futurePrizePool -= ethDaySlice;
        }

        uint256 ethPool = ethDaySlice;
        uint256 lootboxBudget;
        if (ethPool != 0) {
            lootboxBudget = (ethPool * PURCHASE_REWARD_JACKPOT_LOOTBOX_BPS) / 10_000;
            if (lootboxBudget != 0 && !_hasTraitTickets(lvl, winningTraitsPacked)) {
                lootboxBudget = 0;
            }
            if (lootboxBudget != 0) {
                ethPool -= lootboxBudget;
            }
        }
        // NOTE: Coin jackpots now handled separately via payDailyCoinJackpot()
        _executeJackpot(
            JackpotParams({
                lvl: lvl,
                ethPool: ethPool,
                coinPool: 0, // Coin jackpots moved to separate daily transaction
                entropy: randWord ^ (uint256(lvl) << 192),
                winningTraitsPacked: winningTraitsPacked,
                traitShareBpsPacked: DAILY_JACKPOT_SHARES_PACKED
            }),
            false,
            false,
            0
        );

        // Pools already deducted upfront on isEthDay; no additional deduction needed
        if (lootboxBudget != 0) {
            // Add lootbox budget to nextPrizePool
            nextPrizePool += lootboxBudget;

            // Distribute tickets to winners
            // Gas optimization: (budget * 4) / price instead of budget / (price/4)
            uint256 ticketUnits = (lootboxBudget * 4) / uint256(price);
            if (ticketUnits != 0) {
                _distributeTicketJackpot(
                    lvl,
                    winningTraitsPacked,
                    ticketUnits,
                    randWord ^ (uint256(lvl) << 192),
                    LOOTBOX_MAX_WINNERS,
                    242,
                    false // asLootbox=false (we already added to nextPrizePool)
                );
            }
        }
        _rollQuestForJackpot(randWord, false, questDay);
    }

    /// @notice Pays a trait-restricted jackpot during extermination phase.
    /// @dev Called when a trait is being exterminated. All four bucket slots use the SAME trait ID
    ///      so that only holders of the exterminated trait can win. Uses daily jackpot share/bucket
    ///      sizing but draws exclusively from the single trait's ticket pool.
    ///
    /// @param lvl Current game level.
    /// @param traitId The trait being exterminated (0-255).
    /// @param randWord VRF entropy for winner selection.
    /// @param ethPool ETH allocated for this extermination jackpot.
    /// @return paidEth Actual ETH distributed to winners.
    function payExterminationJackpot(
        uint24 lvl,
        uint8 traitId,
        uint256 randWord,
        uint256 ethPool
    ) external returns (uint256 paidEth) {
        // Pack the same trait into all 4 slots — ensures all buckets draw from the same trait pool.
        uint32 packedTrait = uint32(traitId);
        packedTrait |= uint32(traitId) << 8;
        packedTrait |= uint32(traitId) << 16;
        packedTrait |= uint32(traitId) << 24;

        paidEth = _executeJackpot(
            JackpotParams({
                lvl: lvl,
                ethPool: ethPool,
                coinPool: 0,
                entropy: randWord ^ (uint256(lvl) << 192),
                winningTraitsPacked: packedTrait,
                traitShareBpsPacked: DAILY_JACKPOT_SHARES_PACKED
            }),
            false,
            false,
            0
        );
    }

    /// @notice Pays purchase reward tickets to extermination jackpot winners.
    /// @dev Returns winners with individual ETH amounts for unified lootbox processing.
    ///      Awards tickets to trait ticket holders from the purchase reward pool (20% of jackpot).
    ///
    /// @param lvl The level that just completed.
    /// @param traitId The exterminated trait whose holders are rewarded.
    /// @param randWord VRF entropy for winner selection.
    /// @param poolWei ETH pool to distribute as lootbox tickets.
    /// @return winners Array of winner addresses.
    /// @return ethAmounts Array of ETH amounts for each winner (for individual lootbox rolls).
    function payPurchaseRewardLootbox(
        uint24 lvl,
        uint8 traitId,
        uint256 randWord,
        uint256 poolWei
    ) external view returns (address[] memory winners, uint256[] memory ethAmounts) {
        if (poolWei == 0) return (new address[](0), new uint256[](0));

        // Select from previous level's ticket holders (just completed level)
        uint24 targetLevel = lvl;

        // Pack trait into all 4 buckets (all winners from same trait)
        uint32 packedTrait = uint32(traitId);
        packedTrait |= uint32(traitId) << 8;
        packedTrait |= uint32(traitId) << 16;
        packedTrait |= uint32(traitId) << 24;

        // Get winners with individual ETH amounts for lootbox processing
        return _getJackpotWinnersWithAmounts(
            targetLevel,
            packedTrait,
            poolWei,
            randWord ^ (uint256(lvl) << 192),
            LOOTBOX_MAX_WINNERS,
            248
        );
    }

    /// @notice Pay level jackpot ticket distribution (phase 1).
    /// @dev Called first, before payLevelJackpotEth. Stores winning traits and ethPool for ETH phase.
    ///      Combined with early bird jackpot to stay under 15M gas.
    /// @param lvl Current level.
    /// @param rngWord VRF random word.
    /// @param effectiveWei Total prize pool amount for this level jackpot.
    function payLevelJackpotLootbox(uint24 lvl, uint256 rngWord, uint256 effectiveWei) external {
        uint8[4] memory winningTraits = _getRandomTraits(rngWord);
        uint32 winningTraitsPacked = _packWinningTraits(winningTraits);

        uint256 ethPool = effectiveWei;
        uint256 ticketBudget;
        if (ethPool != 0) {
            ticketBudget = (ethPool * LEVEL_JACKPOT_TICKET_BPS) / 10_000;
            if (ticketBudget != 0 && !_hasTraitTickets(lvl, winningTraitsPacked)) {
                ticketBudget = 0;
            }
            if (ticketBudget != 0) {
                ethPool -= ticketBudget;
                // Add ticket budget to nextPrizePool
                nextPrizePool += ticketBudget;
            }
        }

        // Store for ETH phase
        levelJackpotWinningTraits = winningTraitsPacked;
        levelJackpotEthPool = ethPool;

            // Distribute tickets to winners immediately
        if (ticketBudget != 0) {
            // Gas optimization: (budget * 4) / price instead of budget / (price/4)
            uint256 ticketUnits = (ticketBudget * 4) / uint256(price);
            if (ticketUnits != 0) {
                _distributeTicketJackpot(
                    lvl,
                    winningTraitsPacked,
                    ticketUnits,
                    rngWord,
                    LOOTBOX_MAX_WINNERS,
                    250,
                    false // asLootbox=false (we already added to nextPrizePool)
                );
            }
        }
    }

    /// @notice Pay level jackpot ETH distribution (phase 2).
    /// @dev Called after payLevelJackpotLootbox. Uses stored winning traits and ethPool.
    /// @param lvl Current level.
    /// @param rngWord VRF random word.
    function payLevelJackpotEth(uint24 lvl, uint256 rngWord) external {
        uint256 ethPool = levelJackpotEthPool;
        uint32 winningTraitsPacked = levelJackpotWinningTraits;

        (, uint16[4] memory bucketCounts) = _bucketCountsForPool(ethPool, rngWord);

        // Main jackpot flow (ETH only).
        uint8[4] memory traitIds = _unpackWinningTraits(winningTraitsPacked);
        uint16[4] memory shareBps = _shareBpsByBucket(
            LEVEL_JACKPOT_SHARES_PACKED,
            uint8(rngWord & 3)
        );
        uint256 dgnrsReward = 0;
        if (ethPool != 0) {
            uint256 dgnrsPool = dgnrs.poolBalance(IDegenerusStonk.Pool.Reward);
            dgnrsReward = (dgnrsPool * LEVEL_JACKPOT_DGNRS_BPS) / 10_000;
        }
        uint256 paidEth = _distributeJackpotEth(
            lvl,
            ethPool,
            rngWord,
            traitIds,
            shareBps,
            bucketCounts,
            0,
            dgnrsReward
        );
        currentPrizePool += (ethPool - paidEth);

        uint48 questDay = _calculateDayIndex();
        _rollQuestForJackpot(rngWord, true, questDay);
    }

    /// @notice Early Bird Lootbox Jackpot - rewards players who got tickets from lootboxes.
    /// @dev Called after next-level tickets are activated at end of purchase phase.
    ///      Takes 3% from the unified future pool.
    ///      Awards tickets to 100 winners with even ETH split.
    ///      ETH goes to nextPrizePool (like purchases during this phase).
    ///
    /// @param lvl The level whose tickets were just activated.
    /// @param rngWord VRF entropy for sampling winners.
    function payEarlyBirdLootboxJackpot(uint24 lvl, uint256 rngWord) external {
        // Take 3% from unified reserve
        uint256 reserveContribution = (futurePrizePool * 300) / 10_000; // 3%
        uint256 totalBudget = reserveContribution;

        // Deduct from reserve
        futurePrizePool -= reserveContribution;

        // Get ticket holders for this level (just activated)
        uint256[256] memory sizes;
        uint256 totalTickets = _collectTraitTicketSizes(lvl, sizes);

        if (totalTickets == 0) {
            // No tickets, put funds into nextPrizePool (where purchases go at end of purchase phase)
            nextPrizePool += totalBudget;
            return;
        }

        // 100 winners max, even split of budget
        uint256 maxWinners = totalTickets < 100 ? totalTickets : 100;
        uint256 perWinnerEth = totalBudget / maxWinners;
        uint256 entropy = rngWord;

        // Process each winner (sampling with replacement)
        for (uint256 i = 0; i < maxWinners; ) {
            entropy = _entropyStep(entropy);
            address winner = _selectTraitTicketWinner(lvl, sizes, totalTickets, entropy);
            if (winner == address(0)) {
                unchecked { ++i; }
                continue;
            }

            // Roll for level offset 0-4 (20% chance each)
            entropy = _entropyStep(entropy);
            uint24 levelOffset = uint24(entropy % 5); // 0, 1, 2, 3, or 4 levels ahead
            uint24 targetLevel = lvl + levelOffset;

            // Convert ETH share to tickets at target level's price
            uint256 ticketPrice = _priceForLevel(targetLevel);
            uint32 ticketCount = uint32(perWinnerEth / ticketPrice);

            if (ticketCount > 0) {
                _queueTickets(winner, targetLevel, ticketCount);
            }

            unchecked {
                ++i;
            }
        }

        // All budget goes to nextPrizePool (like purchases during purchase phase)
        // This will be merged into currentPrizePool at next level's jackpot calculation
        nextPrizePool += totalBudget;
    }

    /// @notice Computes and applies prize pool splits at the start of a new level's jackpot phase.
    /// @dev This is the "budgeting" function that determines how ETH flows between pools:
    ///
    ///      FLOW:
    ///      1. Merge nextPrizePool into currentPrizePool.
    ///      2. Rebalance between future/current based on elapsed time (primary), ratio (secondary), and RNG (±1%),
    ///         unless a rare 1-in-1e15 dump moves 90% of future into current. Level 100 uses a special keep roll.
    ///      3. Split current into level jackpot (20-40%) and daily jackpot pool.
    ///      4. On level % 100, optionally add yield surplus (stETH appreciation) to the future pool.
    ///
    /// @param lvl Current game level.
    /// @param rngWord VRF entropy for percentage rolls.
    /// @return effectiveWei ETH allocated for the level jackpot.
    function calcPrizePoolForLevelJackpot(uint24 lvl, uint256 rngWord) external returns (uint256 effectiveWei) {
        // Consolidate pools for this level's jackpot calculations.
        uint256 nextPoolSnapshot = nextPrizePool;
        currentPrizePool += nextPrizePool;
        nextPrizePool = 0;

        if ((lvl % 100) == 0) {
            uint256 keepBps = _futureKeepBps(rngWord);
            if (keepBps < 10_000 && futurePrizePool != 0) {
                uint256 keepWei = (futurePrizePool * keepBps) / 10_000;
                uint256 moveWei = futurePrizePool - keepWei;
                if (moveWei != 0) {
                    futurePrizePool = keepWei;
                    currentPrizePool += moveWei;
                }
            }
        } else if (_shouldFutureDump(rngWord)) {
            if (futurePrizePool != 0) {
                uint256 moveWei = (futurePrizePool * 9000) / 10_000;
                if (moveWei != 0) {
                    futurePrizePool -= moveWei;
                    currentPrizePool += moveWei;
                }
            }
        } else if (nextPoolSnapshot != 0) {
            uint48 elapsed = _futureNextElapsed();
            int256 skewBps = _futureNextSkewBps(
                futurePrizePool,
                nextPoolSnapshot,
                elapsed,
                rngWord
            );
            if (skewBps != 0) {
                uint256 moveBps = uint256(skewBps > 0 ? skewBps : -skewBps);
                uint256 moveWei = (nextPoolSnapshot * moveBps) / 10_000;
                if (moveWei != 0) {
                    if (skewBps > 0) {
                        if (moveWei > futurePrizePool) moveWei = futurePrizePool;
                        futurePrizePool -= moveWei;
                        currentPrizePool += moveWei;
                    } else {
                        if (moveWei > currentPrizePool) moveWei = currentPrizePool;
                        currentPrizePool -= moveWei;
                        futurePrizePool += moveWei;
                    }
                }
            }
        }

        uint256 levelJackpotPct = _levelJackpotPercent(lvl, rngWord);
        uint256 levelJackpotWei = (currentPrizePool * levelJackpotPct) / 100;
        uint256 mainWei;
        unchecked {
            mainWei = currentPrizePool - levelJackpotWei;
        }

        lastPrizePool = currentPrizePool;
        _creditDgnrsCoinflipAndVault(lastPrizePool);
        currentPrizePool = mainWei;
        dailyJackpotBase = mainWei;

        effectiveWei = levelJackpotWei;

        {
            uint256 stBal = steth.balanceOf(address(this));
            uint256 totalBal = address(this).balance + stBal;
            uint256 obligations = currentPrizePool + nextPrizePool + claimablePool + futurePrizePool;
            uint256 bafPool = bafHundredPool;
            if (bafPool != 0) {
                unchecked {
                    obligations += bafPool;
                }
            }
            uint256 decPool = decimatorHundredPool;
            if (decPool != 0) {
                unchecked {
                    obligations += decPool;
                }
            }

            if (totalBal > obligations) {
                uint256 yieldPool = totalBal - obligations;

                // Yield distribution (all levels): 23% DGNRS claimable, 23% vault claimable, 46% futurePool.
                // Remaining yield stays unallocated as surplus.
                uint256 dgnrsShare = (yieldPool * 2300) / 10_000; // 23%
                uint256 vaultShare = (yieldPool * 2300) / 10_000; // 23%
                uint256 futureShare = (yieldPool * 4600) / 10_000; // 46%

                uint256 claimableDelta;
                if (vaultShare != 0) {
                    claimableDelta += _addClaimableEth(ContractAddresses.VAULT, vaultShare, rngWord);
                }
                if (dgnrsShare != 0) {
                    claimableDelta += _addClaimableEth(ContractAddresses.DGNRS, dgnrsShare, rngWord);
                }
                if (claimableDelta != 0) {
                    claimablePool += claimableDelta;
                }
                if (futureShare != 0) {
                    futurePrizePool += futureShare;
                }
            }
        }
    }

    // =========================================================================
    // Internal Helpers — Claimable ETH
    // =========================================================================

    /// @dev Credits ETH to a player's claimable balance. Uses unchecked arithmetic because
    ///      uint256 overflow is practically impossible with real ETH amounts.
    ///      With auto-rebuy enabled, reserves full keep-multiples for claim and
    ///      converts the remainder to tickets, rolling fractional dust into a chance
    ///      for one extra ticket.
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

        // Auto-rebuy: convert winnings to tickets if enabled
        if (autoRebuyEnabled[beneficiary]) {
            return _processAutoRebuy(beneficiary, weiAmount, entropy);
        }

        // Normal claimable winnings path
        // SAFETY: uint256 max is ~10^77 wei; overflow impossible in practice.
        unchecked {
            claimableWinnings[beneficiary] += weiAmount;
        }
        emit PlayerCredited(beneficiary, beneficiary, weiAmount);
        return weiAmount;
    }

    /// @dev Converts winnings to tickets for next level.
    ///      Processes only the new amount; existing claimable remains untouched.
    ///      Applies fixed 30% bonus by default, 45% when afKing is active.
    ///      Fractional dust rolls into a chance for +1 base ticket.
    ///
    /// @param player Player receiving winnings.
    /// @param newAmount New winnings amount in wei.
    /// @param entropy RNG seed for fractional ticket roll.
    function _processAutoRebuy(
        address player,
        uint256 newAmount,
        uint256 entropy
    ) private returns (uint256 claimableDelta) {
        // Reserve full keep-multiples from the new amount; rebuy remainder.
        uint256 keepMultiple = autoRebuyKeepMultiple[player];
        uint256 reserved;
        uint256 rebuyAmount = newAmount;
        if (keepMultiple != 0) {
            reserved = (newAmount / keepMultiple) * keepMultiple;
            rebuyAmount = newAmount - reserved;
        }

        // Award tickets for current level unless in BURN phase (then next level)
        uint24 currLvl = level;
        uint24 targetLevel = (gameState == GAME_STATE_BURN) ? currLvl + 1 : currLvl;

        // Get ticket price for target level
        uint256 ticketPrice = _priceForLevel(targetLevel) / 4; // Ticket = 25% of gamepiece

        // Calculate base tickets from ETH
        uint256 baseTickets = rebuyAmount / ticketPrice;
        uint256 ethSpent = baseTickets * ticketPrice;
        uint256 dustRemainder = rebuyAmount - ethSpent;

        // Roll fractional remainder into a chance for +1 base ticket.
        if (dustRemainder != 0) {
            uint256 rollSeed = _entropyStep(
                entropy ^
                    uint256(uint160(player)) ^
                    rebuyAmount ^
                    ticketPrice
            );
            if ((rollSeed % ticketPrice) < dustRemainder) {
                ++baseTickets;
                ethSpent = rebuyAmount;
                dustRemainder = 0;
            }
        }

        if (baseTickets == 0) {
            // Nothing converted; keep as claimable.
            unchecked {
                claimableWinnings[player] += newAmount;
            }
            emit PlayerCredited(player, player, newAmount);
            return newAmount;
        }

        // Apply auto-rebuy bonus (30% default, 45% in afKing mode)
        uint256 bonusBps = afKingMode[player] ? 14500 : 13000;
        uint256 bonusTickets = (baseTickets * bonusBps) / 10000;
        uint32 ticketCount = bonusTickets > type(uint32).max ? type(uint32).max : uint32(bonusTickets);

        // Add tickets to player's ticketsOwed and queue if needed
        _queueTickets(player, targetLevel, ticketCount);

        // Credit ETH to next prize pool (backs next level tickets)
        nextPrizePool += ethSpent;

        // Handle remainder - add to claimableWinnings and claimablePool
        uint256 totalRemainder = reserved + dustRemainder;
        if (totalRemainder > 0) {
            unchecked {
                claimableWinnings[player] += totalRemainder;
                claimablePool += totalRemainder;
            }
        }

        emit AutoRebuyProcessed(
            player,
            targetLevel,
            ticketCount,
            ethSpent,
            totalRemainder
        );
        return 0;
    }

    /// @dev Queue future lootbox rewards without funding pools.
    function _queueFutureLootboxTickets(address buyer, uint24 targetLevel, uint32 quantity) private {
        _queueTickets(buyer, targetLevel, quantity);
    }

    /// @dev Queue deferred whale pass claims for large lootbox wins.
    ///      Calculates half-passes from ETH amount with VRF remainder roll.
    /// @param winner Address to receive whale pass claim.
    /// @param amount ETH amount to convert to half whale passes.
    /// @param entropy VRF-derived entropy for remainder roll.
    /// @return Updated entropy after remainder roll (if needed).
    function _queueWhalePassClaim(
        address winner,
        uint256 amount,
        uint256 entropy
    ) private returns (uint256) {
        if (winner == address(0) || amount == 0) return entropy;

        uint256 HALF_WHALE_PASS_PRICE = 1.75 ether / ContractAddresses.COST_DIVISOR;
        uint256 fullHalfPasses = amount / HALF_WHALE_PASS_PRICE;
        uint256 remainder = amount - (fullHalfPasses * HALF_WHALE_PASS_PRICE);

        // Probabilistic roll for +1 half pass using VRF RNG
        if (remainder > 0) {
            entropy = uint256(keccak256(abi.encodePacked(entropy, winner, amount)));
            uint256 chanceBps = (remainder * 10000) / HALF_WHALE_PASS_PRICE;
            uint256 roll = entropy % 10000;
            if (roll < chanceBps) {
                unchecked { ++fullHalfPasses; }
            }
        }

        // Store half-pass count
        whalePassClaims[winner] += fullHalfPasses;
        return entropy;
    }

    /// @dev Queue tickets using unified ticket system.
    function _queueRewardTickets(address buyer, uint32 quantity) private {
        if (quantity == 0) return;
        // Queue reward tickets for current level using unified ticket system
        uint24 currentLevel = level;
        _queueTickets(buyer, currentLevel, quantity);
    }

    /// @dev Immediately resolve a loot box award using the current RNG entropy.
    function _awardLootBoxNow(
        address winner,
        uint256 amount,
        uint24 purchaseLevel,
        uint256 entropy
    ) private returns (uint256 nextEntropy) {
        nextEntropy = entropy;
        if (winner == address(0) || amount == 0) return nextEntropy;

        if (_priceForLevel(purchaseLevel) == 0) return nextEntropy;

        if (amount > LOOTBOX_CLAIM_THRESHOLD) {
            return _queueWhalePassClaim(winner, amount, nextEntropy);
        }

        uint24 baseLevel = purchaseLevel + 1;
        uint256 amountFirst = amount;
        uint256 amountSecond = 0;
        if (amount > LOOTBOX_SPLIT_THRESHOLD) {
            amountFirst = amount / 2;
            amountSecond = amount - amountFirst;
        }

        uint256 burnieAmount;
        (uint256 burnieOut, uint256 entropyAfter) =
            _resolveLootboxRollNow(winner, amountFirst, baseLevel, nextEntropy);
        if (burnieOut != 0) {
            burnieAmount += burnieOut;
        }
        nextEntropy = entropyAfter;

        if (amountSecond != 0) {
            (burnieOut, entropyAfter) =
                _resolveLootboxRollNow(winner, amountSecond, baseLevel, nextEntropy);
            if (burnieOut != 0) {
                burnieAmount += burnieOut;
            }
            nextEntropy = entropyAfter;
        }

        if (burnieAmount != 0) {
            coin.creditFlip(winner, burnieAmount);
        }
    }

    function _resolveLootboxRollNow(
        address winner,
        uint256 amount,
        uint24 baseLevel,
        uint256 entropy
    ) private returns (uint256 burnieOut, uint256 nextEntropy) {
        nextEntropy = entropy;
        if (amount == 0) return (0, nextEntropy);

        nextEntropy = _entropyStep(nextEntropy);
        uint256 roll = nextEntropy % 6;
        uint24 targetLevel = baseLevel + uint24(roll);
        uint256 targetPrice = _priceForLevel(targetLevel);

        if (roll < 5) {
            uint256 ticketBudget = (amount * LOOTBOX_TICKET_ROLL_BPS) / 10_000;
            (uint32 tickets, uint256 entropyAfter) = _lootboxTicketCount(ticketBudget, targetPrice, nextEntropy);
            nextEntropy = entropyAfter;
            if (tickets != 0) {
                _queueFutureLootboxTickets(winner, targetLevel, tickets);
            }
        } else {
            uint256 burnieBudget = (amount * LOOTBOX_BURNIE_ROLL_BPS) / 10_000;
            burnieOut = (burnieBudget * PRICE_COIN_UNIT) / targetPrice;
        }
    }

    /// @dev Awards jackpot loot box rewards (tickets only, no BURNIE).
    ///      Probabilities: 5% next level ticket, 18% next level gamepiece tickets,
    ///      18% each for +2 to +5 levels ahead, 5% for +6 to +51 levels ahead (rare).
    ///      All ETH goes to futurePrizePool (funded from currentPrizePool).
    ///      Rolls multiple times: 1 base + 1 per ETH, capped at LOOTBOX_MAX_ROLLS.
    ///      Large amounts defer to claim to keep gas bounded.
    ///      Note: "next level" = currentLevel + 1, activated at current burn phase start.

    /// @dev Pay a jackpot winner with ETH (ticket conversion removed).
    function _payJackpotWinnerWithTickets(
        address winner,
        uint256 amount,
        uint16,
        uint24,
        uint256 entropy
    ) private returns (uint256 ethPaid, uint256 lootboxSpent, uint256 claimableDelta, uint256 nextEntropy) {
        nextEntropy = entropy;
        if (winner == address(0) || amount == 0) return (0, 0, 0, nextEntropy);

        // Ticket conversion removed: pay full amount as ETH.
        claimableDelta = _addClaimableEth(winner, amount, entropy);
        ethPaid = amount;
    }

    /// @dev Returns true if any of the packed traits have tickets at the given level.
    function _hasTraitTickets(uint24 lvl, uint32 packedTraits) private view returns (bool) {
        uint8[4] memory traitIds = _unpackWinningTraits(packedTraits);
        for (uint8 i; i < 4; ) {
            if (traitBurnTicket[lvl][traitIds[i]].length != 0) return true;
            unchecked {
                ++i;
            }
        }
        return false;
    }

    // =========================================================================
    // Internal Helpers — Ticket Rewards
    // =========================================================================

    /// @dev Distributes ticket rewards to winners drawn from winning trait pools.
    ///      When asLootbox is true, awards loot box outcomes and credits futurePrizePool.
    ///      When false, awards raw ticket units as reward tickets.
    function _distributeTicketJackpot(
        uint24 lvl,
        uint32 winningTraitsPacked,
        uint256 ticketUnits,
        uint256 entropy,
        uint16 maxWinners,
        uint8 saltBase,
        bool asLootbox
    ) private {
        if (ticketUnits == 0) return;

        uint256 ticketPrice;
        if (asLootbox) {
            ticketPrice = uint256(price) / 4;
            futurePrizePool += ticketUnits * ticketPrice;
        }

        uint8[4] memory traitIds = _unpackWinningTraits(winningTraitsPacked);
        uint16[4] memory counts;
        uint8 activeCount;
        uint8 activeMask;

        for (uint8 i; i < 4; ) {
            if (traitBurnTicket[lvl][traitIds[i]].length != 0) {
                activeMask |= uint8(1 << i);
                unchecked {
                    ++activeCount;
                }
            }
            unchecked {
                ++i;
            }
        }
        if (activeCount == 0) return;

        uint256 cap = maxWinners;
        if (ticketUnits < cap) {
            cap = ticketUnits;
        }

        uint16 baseCount = uint16(cap / activeCount);
        uint16 remainder = uint16(cap - uint256(baseCount) * activeCount);

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

        uint256 total = cap;
        uint256 baseUnits = ticketUnits / total;
        uint256 extra = ticketUnits % total;
        uint256 offset = entropy % total;

        uint256 globalIndex;
        uint256 entropyState = entropy;

        for (uint8 traitIdx; traitIdx < 4; ) {
            uint16 count = counts[traitIdx];
            if (count != 0) {
                // Cap to MAX_BUCKET_WINNERS to fit in uint8 and bound gas.
                if (count > MAX_BUCKET_WINNERS) count = MAX_BUCKET_WINNERS;

                entropyState = _entropyStep(entropyState ^ (uint256(traitIdx) << 64) ^ ticketUnits);
                address[] memory winners = _randTraitTicket(
                    traitBurnTicket[lvl],
                    entropyState,
                    traitIds[traitIdx],
                    uint8(count),
                    uint8(saltBase + traitIdx)
                );
                uint256 len = winners.length;
                for (uint256 i; i < len; ) {
                    address winner = winners[i];
                    uint256 units = baseUnits;
                    if (extra != 0) {
                        uint256 idx = (globalIndex + offset) % total;
                        if (idx < extra) {
                            units += 1;
                        }
                    }
                    if (winner != address(0) && units != 0) {
                        if (asLootbox) {
                            uint256 lootboxAmount = units * ticketPrice;
                            entropyState = _awardLootBoxNow(winner, lootboxAmount, lvl, entropyState);
                        } else {
                            if (units > type(uint32).max) {
                                units = type(uint32).max;
                            }
                            _queueRewardTickets(winner, uint32(units));
                        }
                    }
                    unchecked {
                        ++globalIndex;
                        ++i;
                    }
                }
            }
            unchecked {
                ++traitIdx;
            }
        }
    }

    /// @dev Extracts winners and their individual ETH amounts for jackpot ticket distributions.
    ///      Used for unified lootbox system where each winner gets individual probabilistic rolls.
    /// @param lvl Level to select ticket holders from.
    /// @param winningTraitsPacked Packed trait IDs (same trait in all 4 buckets for Purchase Rewards).
    /// @param poolWei Total ETH pool to distribute.
    /// @param entropy VRF-derived randomness for winner selection.
    /// @param maxWinners Maximum number of winners to select.
    /// @param saltBase Salt offset for RNG domain separation.
    /// @return winners Array of winner addresses (may contain duplicates).
    /// @return ethAmounts Array of ETH amounts for each winner (proportional shares).
    function _getJackpotWinnersWithAmounts(
        uint24 lvl,
        uint32 winningTraitsPacked,
        uint256 poolWei,
        uint256 entropy,
        uint16 maxWinners,
        uint8 saltBase
    ) private view returns (address[] memory winners, uint256[] memory ethAmounts) {
        if (poolWei == 0) return (new address[](0), new uint256[](0));

        uint8[4] memory traitIds = _unpackWinningTraits(winningTraitsPacked);
        uint16[4] memory counts;
        uint8 activeCount;
        uint8 activeMask;

        // Identify which trait buckets have ticket holders
        for (uint8 i; i < 4; ) {
            if (traitBurnTicket[lvl][traitIds[i]].length != 0) {
                activeMask |= uint8(1 << i);
                unchecked {
                    ++activeCount;
                }
            }
            unchecked {
                ++i;
            }
        }
        if (activeCount == 0) return (new address[](0), new uint256[](0));

        // Determine winner cap and distribute among active buckets
        uint256 cap = maxWinners;
        if (cap > poolWei) cap = poolWei; // Safety: don't select more winners than we have wei

        uint16 baseCount = uint16(cap / activeCount);
        uint16 remainder = uint16(cap - uint256(baseCount) * activeCount);

        for (uint8 i; i < 4; ) {
            if ((activeMask & uint8(1 << i)) != 0) {
                counts[i] = baseCount;
            }
            unchecked {
                ++i;
            }
        }

        // Distribute remainder winners
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

        // Calculate per-winner ETH amounts
        uint256 total = cap;
        uint256 baseAmount = poolWei / total;
        uint256 extra = poolWei % total;
        uint256 offset = entropy % total;

        // Allocate arrays for results
        winners = new address[](total);
        ethAmounts = new uint256[](total);

        uint256 globalIndex;
        uint256 entropyState = entropy;

        // Select winners from each trait bucket
        for (uint8 traitIdx; traitIdx < 4; ) {
            uint16 count = counts[traitIdx];
            if (count != 0) {
                // Cap to MAX_BUCKET_WINNERS for gas safety
                if (count > MAX_BUCKET_WINNERS) count = MAX_BUCKET_WINNERS;

                entropyState = _entropyStep(entropyState ^ (uint256(traitIdx) << 64) ^ poolWei);
                address[] memory bucketWinners = _randTraitTicket(
                    traitBurnTicket[lvl],
                    entropyState,
                    traitIds[traitIdx],
                    uint8(count),
                    uint8(saltBase + traitIdx)
                );

                uint256 len = bucketWinners.length;
                for (uint256 i; i < len; ) {
                    address winner = bucketWinners[i];
                    uint256 amount = baseAmount;

                    // Distribute extra wei to first N winners (rotated by offset)
                    if (extra != 0) {
                        uint256 idx = (globalIndex + offset) % total;
                        if (idx < extra) {
                            amount += 1;
                        }
                    }

                    winners[globalIndex] = winner;
                    ethAmounts[globalIndex] = amount;

                    unchecked {
                        ++globalIndex;
                        ++i;
                    }
                }
            }
            unchecked {
                ++traitIdx;
            }
        }
    }

    // =========================================================================
    // Internal Helpers — Bucket Sizing
    // =========================================================================

    /// @dev Computes base winner counts for each of the 4 trait buckets.
    ///      Base counts [25, 15, 8, 1] are rotated by entropy for fairness.
    ///
    /// @param entropy Used for rotation offset (bottom 2 bits).
    /// @return counts Winner counts for each bucket [bucket0, bucket1, bucket2, bucket3].
    function _traitBucketCounts(uint256 entropy) private pure returns (uint16[4] memory counts) {
        uint16[4] memory base;
        base[0] = 25; // Large bucket
        base[1] = 15; // Mid bucket
        base[2] = 8; // Small bucket
        base[3] = 1; // Solo bucket (receives the 60% share via rotation)

        // Rotate bucket assignments based on entropy for fairness across traits.
        uint8 offset = uint8(entropy & 3);
        for (uint8 i; i < 4; ) {
            counts[i] = base[(i + offset) & 3];
            unchecked {
                ++i;
            }
        }
    }

    /// @dev Scales base bucket counts by jackpot size (excluding solo) with a hard cap.
    ///      1x under 10 ETH, linearly to 2x by 50 ETH, linearly to 4x by 200 ETH, then capped.
    function _scaleTraitBucketCounts(
        uint16[4] memory baseCounts,
        uint256 ethPool,
        uint256 entropy
    ) private pure returns (uint16[4] memory counts) {
        counts = baseCounts;

        if (ethPool < JACKPOT_SCALE_MIN_WEI) return counts;

        uint256 scaleBps;
        if (ethPool < JACKPOT_SCALE_FIRST_WEI) {
            uint256 range = JACKPOT_SCALE_FIRST_WEI - JACKPOT_SCALE_MIN_WEI;
            uint256 progress = ethPool - JACKPOT_SCALE_MIN_WEI;
            scaleBps = JACKPOT_SCALE_BASE_BPS + (progress * (JACKPOT_SCALE_FIRST_BPS - JACKPOT_SCALE_BASE_BPS)) / range;
        } else if (ethPool < JACKPOT_SCALE_SECOND_WEI) {
            uint256 range = JACKPOT_SCALE_SECOND_WEI - JACKPOT_SCALE_FIRST_WEI;
            uint256 progress = ethPool - JACKPOT_SCALE_FIRST_WEI;
            scaleBps = JACKPOT_SCALE_FIRST_BPS + (progress * (JACKPOT_SCALE_MAX_BPS - JACKPOT_SCALE_FIRST_BPS)) / range;
        } else {
            scaleBps = JACKPOT_SCALE_MAX_BPS;
        }

        if (scaleBps != JACKPOT_SCALE_BASE_BPS) {
            for (uint8 i; i < 4; ) {
                uint16 baseCount = counts[i];
                if (baseCount > 1) {
                    uint256 scaled = (uint256(baseCount) * scaleBps) / 10_000;
                    if (scaled < baseCount) scaled = baseCount;
                    if (scaled > type(uint16).max) scaled = type(uint16).max;
                    counts[i] = uint16(scaled);
                }
                unchecked {
                    ++i;
                }
            }
        }

        return _capBucketCounts(counts, JACKPOT_MAX_WINNERS, entropy);
    }

    /// @dev Computes base + scaled bucket counts for a given pool; returns zeroes when pool is empty.
    function _bucketCountsForPool(
        uint256 ethPool,
        uint256 entropy
    ) private pure returns (uint16[4] memory baseCounts, uint16[4] memory bucketCounts) {
        if (ethPool == 0) return (baseCounts, bucketCounts);
        baseCounts = _traitBucketCounts(entropy);
        bucketCounts = _scaleTraitBucketCounts(baseCounts, ethPool, entropy);
    }

    /// @dev Sums the bucket counts.
    function _sumBucketCounts(uint16[4] memory counts) private pure returns (uint256 total) {
        total = uint256(counts[0]) + counts[1] + counts[2] + counts[3];
    }

    /// @dev Caps total winners while keeping the solo bucket fixed at 1 when present.
    function _capBucketCounts(
        uint16[4] memory counts,
        uint16 maxTotal,
        uint256 entropy
    ) private pure returns (uint16[4] memory capped) {
        capped = counts;
        if (maxTotal == 0) {
            capped[0] = 0;
            capped[1] = 0;
            capped[2] = 0;
            capped[3] = 0;
            return capped;
        }

        uint256 total = _sumBucketCounts(counts);
        if (total == 0) {
            capped[0] = 0;
            capped[1] = 0;
            capped[2] = 0;
            capped[3] = 0;
            return capped;
        }
        if (maxTotal == 1) {
            capped[0] = 0;
            capped[1] = 0;
            capped[2] = 0;
            capped[3] = 0;
            capped[_soloBucketIndex(entropy)] = 1;
            return capped;
        }
        if (total <= maxTotal) return capped;

        uint256 nonSoloCap = uint256(maxTotal) - 1;
        uint256 nonSoloTotal = total - 1;
        uint256 scaledTotal;

        for (uint8 i; i < 4; ) {
            uint16 bucketCount = counts[i];
            if (bucketCount > 1) {
                uint256 scaled = (uint256(bucketCount) * nonSoloCap) / nonSoloTotal;
                if (scaled == 0) scaled = 1;
                capped[i] = uint16(scaled);
                scaledTotal += scaled;
            }
            unchecked {
                ++i;
            }
        }

        uint256 remainder = nonSoloCap - scaledTotal;
        if (remainder != 0) {
            uint8 offset = uint8((entropy >> 24) & 3);
            for (uint8 i; i < 4 && remainder != 0; ) {
                uint8 idx = uint8((uint256(offset) + i) & 3);
                if (capped[idx] > 1) {
                    capped[idx] += 1;
                    unchecked {
                        --remainder;
                    }
                }
                unchecked {
                    ++i;
                }
            }
        }

        return capped;
    }

    // =========================================================================
    // Internal Helpers — Dice Rolls
    // =========================================================================

    /// @dev Generic dice roll: sum of `dice` rolls of `sides`-sided dice (1 to sides each).
    /// @param rngWord Base entropy.
    /// @param salt Domain separator for this roll type.
    /// @param sides Number of sides per die (e.g., 4 for d4).
    /// @param dice Number of dice to roll.
    /// @return Sum of all dice (range: dice to dice*sides).
    function _rollSum(uint256 rngWord, bytes32 salt, uint8 sides, uint8 dice) private pure returns (uint256) {
        uint256 seed = uint256(keccak256(abi.encodePacked(rngWord, salt)));
        uint256 result;
        unchecked {
            for (uint8 i; i < dice; ++i) {
                result += (seed % sides) + 1;
                seed >>= 16;
            }
        }
        return result;
    }

    /// @dev Zero-based dice roll: sum of `dice` rolls of `sides`-sided dice (0 to sides-1 each).
    function _rollZeroSum(uint256 rngWord, bytes32 salt, uint8 sides, uint8 dice) private pure returns (uint256) {
        uint256 seed = uint256(keccak256(abi.encodePacked(rngWord, salt)));
        uint256 result;
        unchecked {
            for (uint8 i; i < dice; ++i) {
                result += (seed % sides);
                seed >>= 16;
            }
        }
        return result;
    }

    /// @dev Determines what percentage of the jackpot base goes to the level jackpot.
    ///      Fixed at 40% for "big" levels (6, 16, 26, 36, 46...); otherwise 20-40% random.
    function _levelJackpotPercent(uint24 lvl, uint256 rngWord) private pure returns (uint256) {
        if (lvl % 10 == 6) return 40; // Big level jackpot levels get fixed 40%
        return 20 + (rngWord % 21); // Otherwise 20-40% random
    }

    /// @dev Level-100 keep roll: 5 dice with zeros (0-3), mapped to 0-100% keep (avg 50%).
    function _futureKeepBps(uint256 rngWord) private pure returns (uint256) {
        uint256 total = _rollZeroSum(rngWord, FUTURE_KEEP_TAG, 4, 5); // 0..15
        return (total * 10_000) / 15;
    }

    /// @dev Rare roll: 1 in 1e15 chance to dump 90% of future into current on normal levels.
    function _shouldFutureDump(uint256 rngWord) private pure returns (bool) {
        uint256 seed = uint256(keccak256(abi.encodePacked(rngWord, FUTURE_DUMP_TAG)));
        return seed % FUTURE_DUMP_ODDS == 0;
    }

    /// @dev Compute signed skew based on elapsed time (primary), ratio (secondary), and jitter.
    function _futureNextSkewBps(
        uint256 futurePool,
        uint256 nextPool,
        uint48 elapsed,
        uint256 rngWord
    ) private pure returns (int256) {
        int256 mean = _futureNextTimeMeanBps(elapsed) + _futureNextRatioAdjustBps(futurePool, nextPool);
        int256 skew = mean;
        if (FUTURE_NEXT_SKEW_JITTER_BPS != 0) {
            uint256 seed = uint256(keccak256(abi.encodePacked(rngWord, FUTURE_NEXT_SKEW_TAG)));
            uint256 range = (uint256(FUTURE_NEXT_SKEW_JITTER_BPS) * 2) + 1;
            int256 jitter = int256(seed % range) - int256(uint256(FUTURE_NEXT_SKEW_JITTER_BPS));
            skew = mean + jitter;
        }
        int256 maxSkew = int256(uint256(FUTURE_NEXT_SKEW_MAX_BPS));
        if (skew > maxSkew) return maxSkew;
        if (skew < -maxSkew) return -maxSkew;
        return skew;
    }

    /// @dev Compute mean skew from elapsed time (fast/slow favor future, peak at 2 weeks).
    function _futureNextTimeMeanBps(uint48 elapsed) private pure returns (int256) {
        int256 minSkew = -int256(uint256(FUTURE_NEXT_SKEW_MAX_BPS));
        int256 maxSkew = int256(uint256(FUTURE_NEXT_SKEW_MAX_BPS));

        if (elapsed <= FUTURE_NEXT_TIME_FAST) {
            return minSkew;
        }
        if (elapsed <= FUTURE_NEXT_TIME_PEAK) {
            uint256 span = FUTURE_NEXT_TIME_PEAK - FUTURE_NEXT_TIME_FAST;
            uint256 elapsedAfter = elapsed - FUTURE_NEXT_TIME_FAST;
            int256 delta = maxSkew - minSkew; // 600 bps span
            int256 add = (delta * int256(uint256(elapsedAfter))) / int256(uint256(span));
            return minSkew + add;
        }
        if (elapsed <= FUTURE_NEXT_TIME_DECAY) {
            uint256 span = FUTURE_NEXT_TIME_DECAY - FUTURE_NEXT_TIME_PEAK;
            uint256 elapsedAfter = elapsed - FUTURE_NEXT_TIME_PEAK;
            int256 delta = minSkew - maxSkew; // -600 bps span
            int256 add = (delta * int256(uint256(elapsedAfter))) / int256(uint256(span));
            return maxSkew + add;
        }
        return minSkew;
    }

    /// @dev Compute ratio-based adjustment (2x target, ±1.5% cap).
    function _futureNextRatioAdjustBps(uint256 futurePool, uint256 nextPool) private pure returns (int256) {
        if (nextPool == 0) return 0;
        uint256 ratioBps = (futurePool * 10_000) / nextPool; // 1.0x = 10000 bps
        int256 diff = int256(ratioBps) - int256(uint256(FUTURE_NEXT_TARGET_BPS));
        int256 adjust = (diff * int256(uint256(FUTURE_NEXT_RATIO_ADJUST_MAX_BPS))) / 10_000;
        int256 maxAdjust = int256(uint256(FUTURE_NEXT_RATIO_ADJUST_MAX_BPS));
        if (adjust > maxAdjust) return maxAdjust;
        if (adjust < -maxAdjust) return -maxAdjust;
        return adjust;
    }

    function _futureNextElapsed() private view returns (uint48 elapsed) {
        uint48 start = levelStartTime;
        if (start == LEVEL_START_SENTINEL) return 0;
        uint48 end = purchaseTargetReachedTime;
        if (end <= start) {
            end = uint48(block.timestamp);
        }
        if (end <= start) return 0;
        return end - start;
    }

    // =========================================================================
    // Internal Helpers — Jackpot Execution
    // =========================================================================

    /// @dev Core jackpot execution: distributes ETH and/or COIN to winners, then debits pools.
    ///      This is the unified entry point for daily, early-burn, and extermination jackpots.
    ///
    /// @param jp Packed jackpot parameters.
    /// @param fromPrizePool If true, debit paidEth from currentPrizePool.
    /// @param fromRewardPool If true, debit paidEth from the unified future pool.
    /// @param ticketBps Basis points of ETH payout to convert into tickets.
    /// @return paidEth Total ETH paid out (for pool accounting).
    function _executeJackpot(
        JackpotParams memory jp,
        bool fromPrizePool,
        bool fromRewardPool,
        uint16 ticketBps
    ) private returns (uint256 paidEth) {
        uint8[4] memory traitIds = _unpackWinningTraits(jp.winningTraitsPacked);
        uint16[4] memory shareBps = _shareBpsByBucket(jp.traitShareBpsPacked, uint8(jp.entropy & 3));

        if (jp.ethPool != 0) {
            paidEth = _runJackpotEthFlow(jp, traitIds, shareBps, ticketBps);
        }

        if (jp.coinPool != 0) {
            _runJackpotCoinFlow(jp, traitIds, shareBps);
        }

        // Debit the appropriate pool(s) based on caller specification.
        if (fromPrizePool) {
            currentPrizePool -= paidEth;
        }
        if (fromRewardPool) {
            futurePrizePool -= paidEth;
        }
    }

    /// @dev Simple ETH flow for daily/extermination jackpots.
    function _runJackpotEthFlow(
        JackpotParams memory jp,
        uint8[4] memory traitIds,
        uint16[4] memory shareBps,
        uint16 ticketBps
    ) private returns (uint256 totalPaidEth) {
        uint16[4] memory baseBucketCounts = _traitBucketCounts(jp.entropy);
        uint16[4] memory bucketCounts = _scaleTraitBucketCounts(baseBucketCounts, jp.ethPool, jp.entropy);
        return _distributeJackpotEth(
            jp.lvl,
            jp.ethPool,
            jp.entropy,
            traitIds,
            shareBps,
            bucketCounts,
            ticketBps,
            0
        );
    }

    function _runJackpotCoinFlow(JackpotParams memory jp, uint8[4] memory traitIds, uint16[4] memory shareBps) private {
        // Do not scale coin jackpots by level; scale by size using coin->ETH equivalent.
        uint16[4] memory baseBucketCounts = _traitBucketCounts(jp.entropy);
        uint256 coinPoolEth;
        uint256 priceWei = price;
        if (jp.coinPool != 0 && priceWei != 0) {
            coinPoolEth = (jp.coinPool * priceWei) / PRICE_COIN_UNIT;
        }
        uint16[4] memory bucketCounts = _scaleTraitBucketCounts(baseBucketCounts, coinPoolEth, jp.entropy);
        uint8 remainderIdx = _remainderBucketIndex(jp.entropy);
        _distributeJackpotCoin(
            jp.lvl,
            jp.coinPool,
            jp.entropy ^ uint256(COIN_JACKPOT_TAG),
            traitIds,
            shareBps,
            bucketCounts,
            remainderIdx
        );
    }

    function _distributeJackpotEth(
        uint24 lvl,
        uint256 ethPool,
        uint256 entropy,
        uint8[4] memory traitIds,
        uint16[4] memory shareBps,
        uint16[4] memory bucketCounts,
        uint16 ticketBps,
        uint256 dgnrsReward
    ) private returns (uint256 totalPaidEth) {
        // Each trait bucket gets a slice; the remainder bucket absorbs dust. totalPaidEth counts ETH plus ticket spend.
        JackpotEthCtx memory ctx;
        ctx.entropyState = entropy;
        uint256 unit = uint256(price) / 4;
        uint8 remainderIdx = _remainderBucketIndex(entropy);
        uint8 soloIdx = 0;
        if (dgnrsReward != 0) {
            soloIdx = _soloBucketIndex(entropy);
        }
        uint256[4] memory shares = _bucketShares(ethPool, shareBps, bucketCounts, remainderIdx, unit);

        for (uint8 traitIdx; traitIdx < 4; ) {
            uint16 bucketCount = bucketCounts[traitIdx];
            uint256 share = shares[traitIdx];
            uint256 penalty;
            if (_shouldPenalizeExterminatedTrait(traitIds[traitIdx])) {
                penalty = share / 2;
                share -= penalty;
                if (penalty != 0) {
                    futurePrizePool += penalty;
                }
            }
            {
                uint256 bucketDgnrsReward = (dgnrsReward != 0 && traitIdx == soloIdx) ? dgnrsReward : 0;
                (uint256 newEntropyState, uint256 ethDelta, uint256 bucketLiability, uint256 ticketSpent) = _resolveTraitWinners(
                    false,
                    lvl,
                    traitIds[traitIdx],
                    traitIdx,
                    share,
                    ctx.entropyState,
                    bucketCount,
                    ticketBps,
                    bucketDgnrsReward
                );
                ctx.entropyState = newEntropyState;
                ctx.totalPaidEth += ethDelta + ticketSpent + penalty;
                ctx.liabilityDelta += bucketLiability;
            }
            unchecked {
                ++traitIdx;
            }
        }

        if (ctx.liabilityDelta != 0) {
            unchecked {
                claimablePool += ctx.liabilityDelta;
            }
        }

        return ctx.totalPaidEth;
    }

    function _distributeJackpotCoin(
        uint24 lvl,
        uint256 coinPool,
        uint256 entropy,
        uint8[4] memory traitIds,
        uint16[4] memory shareBps,
        uint16[4] memory bucketCounts,
        uint8 remainderIdx
    ) private {
        uint256 unit = PRICE_COIN_UNIT / 4;
        uint256[4] memory shares = _bucketShares(coinPool, shareBps, bucketCounts, remainderIdx, unit);
        for (uint8 traitIdx; traitIdx < 4; ) {
            uint16 bucketCount = bucketCounts[traitIdx];
            uint256 share = shares[traitIdx];
            uint8 traitId = traitIds[traitIdx];
            (entropy, , , ) = _resolveTraitWinners(
                true,
                lvl,
                traitId,
                traitIdx,
                share,
                entropy,
                bucketCount,
                0,
                0
            );
            unchecked {
                ++traitIdx;
            }
        }
    }

    function _rotatedShareBps(uint64 packed, uint8 offset, uint8 traitIdx) private pure returns (uint16) {
        uint8 baseIndex = uint8((uint256(traitIdx) + uint256(offset) + 1) & 3);
        return uint16(packed >> (baseIndex * 16));
    }

    function _soloBucketIndex(uint256 entropy) private pure returns (uint8) {
        return uint8((uint256(3) - (entropy & 3)) & 3);
    }

    function _remainderBucketIndex(uint256 entropy) private view returns (uint8) {
        uint16 exTrait = currentExterminatedTrait;
        if (exTrait < 256) {
            return uint8(exTrait >> 6);
        }
        return _soloBucketIndex(entropy);
    }

    function _shouldPenalizeExterminatedTrait(uint8 traitId) private view returns (bool) {
        if (!exterminationInvertFlag) return false;
        uint16 exTrait = currentExterminatedTrait;
        if (exTrait >= 256) return false;
        return traitId == uint8(exTrait);
    }

    function _bucketShares(
        uint256 pool,
        uint16[4] memory shareBps,
        uint16[4] memory bucketCounts,
        uint8 remainderIdx,
        uint256 unit
    ) private pure returns (uint256[4] memory shares) {
        // Round non-solo buckets to unit * winnerCount; remainder goes to the override bucket.
        uint256 distributed;
        for (uint8 i; i < 4; ) {
            if (i != remainderIdx) {
                uint16 count = bucketCounts[i];
                uint256 share = (pool * shareBps[i]) / 10_000;
                if (count != 0) {
                    if (unit != 0) {
                        uint256 unitBucket = unit * count;
                        share = (share / unitBucket) * unitBucket;
                    }
                    shares[i] = share;
                }
                distributed += share;
            }
            unchecked {
                ++i;
            }
        }
        shares[remainderIdx] = pool - distributed;
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
    /// @param ticketBps Basis points of ETH payout to convert into loot box awards.
    /// @param dgnrsReward DGNRS reward for the solo bucket winner (level jackpot only).
    /// @return entropyState Updated entropy after selection.
    /// @return ethDelta ETH credited to claimable balances.
    /// @return liabilityDelta Total claimable liability added.
    /// @return ticketSpent ETH converted into loot box awards (added to nextPrizePool).
    function _resolveTraitWinners(
        bool payCoin,
        uint24 lvl,
        uint8 traitId,
        uint8 traitIdx,
        uint256 traitShare,
        uint256 entropy,
        uint16 winnerCount,
        uint16 ticketBps,
        uint256 dgnrsReward
    ) private returns (uint256 entropyState, uint256 ethDelta, uint256 liabilityDelta, uint256 ticketSpent) {
        entropyState = entropy;

        // Early exits for edge cases.
        if (traitShare == 0) return (entropyState, 0, 0, 0);

        uint16 totalCount = winnerCount;
        if (totalCount == 0) return (entropyState, 0, 0, 0);

        // Cap to MAX_BUCKET_WINNERS to fit in uint8 and bound gas.
        if (totalCount > MAX_BUCKET_WINNERS) totalCount = MAX_BUCKET_WINNERS;

        // Derive sub-entropy and select winners from the trait's ticket pool.
        entropyState = _entropyStep(entropyState ^ (uint256(traitIdx) << 64) ^ traitShare);
        address[] memory winners = _randTraitTicket(
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

                unchecked {
                    ++i;
                }
            }
            return (entropyState, 0, 0, 0);
        }

        // Special handling for solo bucket (winnerCount == 1)
        bool isSoloBucket = (winnerCount == 1);
        bool payDgnrsReward = (!payCoin && isSoloBucket && dgnrsReward != 0);
        bool dgnrsPaid;

        uint256 totalPayout;
        uint256 totalLootboxSpent;
        uint256 totalLiability;
        for (uint256 i; i < len; ) {
            address w = winners[i];
            if (w != address(0)) {
                if (payDgnrsReward && !dgnrsPaid) {
                    dgnrs.transferFromPool(
                        IDegenerusStonk.Pool.Reward,
                        w,
                        dgnrsReward
                    );
                    dgnrsPaid = true;
                }
                if (isSoloBucket) {
                    // Solo winner: give half as ETH payout, half as future level tickets
                    uint256 ethAmount = perWinner / 2;
                    uint256 futureTicketsAmount = perWinner - ethAmount;

                    // Pay half as ETH (no ticket conversion - pure ETH)
                    uint256 claimableDelta = _creditJackpot(
                        false,
                        w,
                        ethAmount,
                        entropyState
                    );
                    totalPayout += ethAmount;
                    totalLiability += claimableDelta;

                    // Award future level tickets for other half
                    // <= 50 ETH: 1 ETH per level for up to 50 levels
                    // > 50 ETH: Scale up amount per level, cap at 50 levels
                    if (futureTicketsAmount > 0) {
                        _awardSoloFutureLevelTickets(w, futureTicketsAmount, lvl);
                        // Fund futurePrizePool with the future tickets amount (spread across many levels)
                        futurePrizePool += futureTicketsAmount;
                        totalLootboxSpent += futureTicketsAmount;
                    }
                } else {
                    // Normal bucket: pay full amount
                    (uint256 ethPaid, uint256 lootboxPaid, uint256 claimableDelta, uint256 newEntropy) =
                        _payJackpotWinnerWithTickets(w, perWinner, ticketBps, lvl, entropyState);
                    entropyState = newEntropy;
                    totalPayout += ethPaid;
                    totalLootboxSpent += lootboxPaid;
                    totalLiability += claimableDelta;
                }
            }
            unchecked {
                ++i;
            }
        }
        if (totalPayout == 0 && totalLootboxSpent == 0) return (entropyState, 0, 0, 0);

        liabilityDelta = totalLiability;
        ethDelta = totalPayout;
        ticketSpent = totalLootboxSpent;

        return (entropyState, ethDelta, liabilityDelta, ticketSpent);
    }

    // =========================================================================
    // Internal Helpers — Entropy
    // =========================================================================

    /// @dev XOR-shift PRNG step for deterministic entropy derivation.
    ///      Creates new pseudo-random state from the current state without
    ///      requiring additional VRF calls. Not cryptographically secure on
    ///      its own, but adequate when seeded with VRF output.
    function _entropyStep(uint256 state) private pure returns (uint256) {
        unchecked {
            state ^= state << 7;
            state ^= state >> 9;
            state ^= state << 8;
        }
        return state;
    }

    function _lootboxTicketCount(
        uint256 budgetWei,
        uint256 priceWei,
        uint256 entropy
    ) private pure returns (uint32 count, uint256 nextEntropy) {
        if (budgetWei == 0 || priceWei == 0) {
            return (0, entropy);
        }

        uint256 base = budgetWei / priceWei;
        uint256 remainder = budgetWei - (base * priceWei);
        nextEntropy = entropy;
        if (remainder != 0) {
            nextEntropy = _entropyStep(entropy);
            if (nextEntropy % priceWei < remainder) {
                unchecked {
                    ++base;
                }
            }
        }

        if (base > type(uint32).max) revert E();
        count = uint32(base);
    }

    function _priceForLevel(uint24 targetLevel) private pure returns (uint256) {
        // First 10 levels (0-9) start at lower price
        if (targetLevel < 10) return 0.025 ether;

        uint256 cycleOffset = targetLevel % 100;

        // Price changes at specific points in the 100-level cycle
        if (cycleOffset == 0) {
            return 0.25 ether; // Levels 100, 200, 300...
        } else if (cycleOffset >= 80) {
            return 0.125 ether; // Levels 80-99, 180-199...
        } else if (cycleOffset >= 40) {
            return 0.1 ether; // Levels 40-79, 140-179...
        } else {
            // Levels 10-39, 110-139... = 0.05 ether
            return 0.05 ether;
        }
    }

    // =========================================================================
    // Internal Helpers — Quest & Credit
    // =========================================================================

    /// @dev Triggers the daily quest roll after a jackpot. Level jackpots force ETH+Degenerus quests.
    function _rollQuestForJackpot(uint256 entropySource, bool forceMintEthAndDegenerus, uint48 questDay) private {
        if (forceMintEthAndDegenerus) {
            coin.rollDailyQuestWithOverrides(questDay, entropySource, true, true);
        } else {
            coin.rollDailyQuest(questDay, entropySource);
        }
    }

    /// @dev Credits a jackpot winner with COIN or ETH; no-op if beneficiary is invalid.
    /// @return claimableDelta Amount to add to claimablePool for this credit.
    function _creditJackpot(
        bool payInCoin,
        address beneficiary,
        uint256 amount,
        uint256 entropy
    ) private returns (uint256 claimableDelta) {
        if (beneficiary == address(0) || amount == 0) return 0;
        if (payInCoin) {
            coin.creditFlip(beneficiary, amount);
            return 0;
        } else {
            // Liability is tracked by the caller to avoid per-winner SSTORE cost.
            return _addClaimableEth(beneficiary, amount, entropy);
        }
    }

    /// @dev Awards future level tickets to ETH jackpot solo winners.
    ///      Distributes 1 ETH worth of tickets per level for up to 50 levels.
    ///      If more than 50 ETH, scales up tickets per level instead of increasing level count.
    ///
    ///      Called for the solo bucket winner (winnerCount == 1) in ETH jackpots.
    ///      Solo winner gets half their reward as normal ETH payout, half as future tickets.
    ///
    ///      GAS IMPACT: Up to 50 fresh ticket queues × ~42k gas = ~2.1M gas per solo winner.
    ///      (Fresh = new level/player pair: cold SLOAD + array push + mapping write)
    ///      Since solo bucket has exactly 1 winner, this adds ~2.1M to ETH jackpot TX.
    ///      This is part of the main ETH jackpot transaction, not the lootbox transaction.
    ///
    /// @param winner The solo winner receiving future tickets.
    /// @param amount ETH amount to convert into future tickets.
    /// @param startLevel Current level (tickets start at startLevel + 1).
    function _awardSoloFutureLevelTickets(
        address winner,
        uint256 amount,
        uint24 startLevel
    ) private {
        if (amount == 0 || winner == address(0)) return;

        uint256 numLevels;
        uint256 amountPerLevel;

        if (amount <= 50 ether) {
            // <= 50 ETH: 1 ETH per level, for (amount / 1 ether) levels
            numLevels = amount / 1 ether;
            if (numLevels == 0) return; // Less than 1 ETH, award nothing
            amountPerLevel = 1 ether;
        } else {
            // > 50 ETH: scale up amount per level, cap at 50 levels
            numLevels = 50;
            amountPerLevel = amount / 50;
        }

        // Award tickets for each future level
        for (uint256 i = 0; i < numLevels; i++) {
            uint24 targetLevel = startLevel + uint24(i + 1); // Start at startLevel + 1

            // Get price for this level
            uint256 targetPrice = _priceForLevel(targetLevel);
            if (targetPrice == 0) continue; // Skip invalid levels

            // Calculate tickets for this level
            uint256 fullTickets = amountPerLevel / targetPrice;

            if (fullTickets > 0 && fullTickets <= type(uint32).max) {
                _queueFutureLootboxTickets(winner, targetLevel, uint32(fullTickets));
            }

            // Note: We don't handle fractional tickets for simplicity (small dust amounts)
        }
    }

    /// @dev Distributes jackpot loot box rewards to winners based on trait buckets.
    ///      Awards tickets only (no BURNIE) using jackpot loot box mechanics.

    // _awardFutureTicketCoinJackpot removed - replaced by payDailyCoinJackpot()

    // =========================================================================
    // Internal Helpers — Trait Packing/Unpacking
    // =========================================================================

    /// @dev Packs 4 trait IDs (0-255 each) into a single uint32.
    function _packWinningTraits(uint8[4] memory traits) private pure returns (uint32 packed) {
        packed = uint32(traits[0]) | (uint32(traits[1]) << 8) | (uint32(traits[2]) << 16) | (uint32(traits[3]) << 24);
    }

    /// @dev Unpacks a uint32 into 4 trait IDs.
    function _unpackWinningTraits(uint32 packed) private pure returns (uint8[4] memory traits) {
        traits[0] = uint8(packed);
        traits[1] = uint8(packed >> 8);
        traits[2] = uint8(packed >> 16);
        traits[3] = uint8(packed >> 24);
    }

    /// @dev If an extermination occurred this level, force that trait in its quadrant.
    function _applyExterminatedTraitPacked(uint32 packed, uint24 lvl) private view returns (uint32) {
        uint16 exTrait = currentExterminatedTrait;
        if (exTrait >= 256 || lvl != level) return packed;

        uint8[4] memory traits = _unpackWinningTraits(packed);
        uint8 quadrant = uint8(exTrait >> 6);
        traits[quadrant] = uint8(exTrait);
        return _packWinningTraits(traits);
    }

    /// @dev Unpacks share BPS from packed uint64 with rotation offset for fairness.
    function _shareBpsByBucket(uint64 packed, uint8 offset) private pure returns (uint16[4] memory shares) {
        unchecked {
            for (uint8 i; i < 4; ++i) {
                shares[i] = _rotatedShareBps(packed, offset, i);
            }
        }
    }

    // =========================================================================
    // Internal Helpers — Trait Selection
    // =========================================================================

    /// @dev Derives 4 random trait IDs from entropy. Each quadrant uses 6 bits (0-63 range).
    ///      Quadrant offsets: 0, 64, 128, 192.
    function _getRandomTraits(uint256 rw) private pure returns (uint8[4] memory w) {
        w[0] = uint8(rw & 0x3F); // Quadrant 0: 0-63
        w[1] = 64 + uint8((rw >> 6) & 0x3F); // Quadrant 1: 64-127
        w[2] = 128 + uint8((rw >> 12) & 0x3F); // Quadrant 2: 128-191
        w[3] = 192 + uint8((rw >> 18) & 0x3F); // Quadrant 3: 192-255
    }

    /// @dev Derives winning traits based on daily burn activity counters.
    ///      Favors the most-burned traits to reward active participation.
    ///
    ///      SELECTION LOGIC:
    ///      - Trait 0: Most-burned symbol (0-7) combined with random color.
    ///      - Trait 1: Most-burned color (0-7) combined with random symbol.
    ///      - Trait 2: Most-burned overall trait (0-63).
    ///      - Trait 3: Fully random from quadrant 3.
    function _getWinningTraits(
        uint256 randomWord,
        uint32[80] storage counters
    ) private view returns (uint8[4] memory w) {
        uint8 sym = _maxIdxInRange(counters, 0, 8); // Most-burned symbol

        uint8 col0 = uint8(randomWord & 7); // Random color
        w[0] = (col0 << 3) | sym;

        uint8 maxColor = _maxIdxInRange(counters, 8, 8); // Most-burned color
        uint8 randSym = uint8((randomWord >> 3) & 7); // Random symbol
        w[1] = 64 + ((maxColor << 3) | randSym);

        uint8 maxTrait = _maxIdxInRange(counters, 16, 64); // Most-burned overall
        w[2] = 128 + maxTrait;

        w[3] = 192 + uint8((randomWord >> 6) & 63); // Fully random
    }

    /// @dev Finds the index with maximum value in a slice of the counters array.
    /// @param counters Daily burn count array (80 elements).
    /// @param base Starting index in the array.
    /// @param len Number of elements to scan.
    /// @return Relative index (0 to len-1) of the maximum value.
    function _maxIdxInRange(uint32[80] storage counters, uint8 base, uint8 len) private view returns (uint8) {
        if (len == 0 || base >= 80) return 0;

        uint256 end = uint256(base) + uint256(len);
        if (end > 80) end = 80;

        uint8 maxRel = 0;
        uint32 maxVal = counters[base];

        for (uint256 i = uint256(base) + 1; i < end; ) {
            uint32 v = counters[i];
            if (v > maxVal) {
                maxVal = v;
                maxRel = uint8(i) - base;
            }
            unchecked {
                ++i;
            }
        }
        return maxRel;
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
    ///      - Budget defaults to WRITES_BUDGET_SAFE (780) if not specified.
    ///      - Minimum budget is WRITES_BUDGET_MIN (8) to ensure progress.
    ///
    /// @param writesBudget Maximum SSTORE writes allowed this call (0 = use default).
    /// @param lvl Level whose tickets should be processed.
    /// @return finished True if all tickets for this level have been fully processed.
    function processTicketBatch(uint32 writesBudget, uint24 lvl) public returns (bool finished) {
        address[] storage queue = ticketQueue[lvl];
        uint256 total = queue.length;

        // Check if we need to switch to this level or if already complete
        if (ticketLevel != lvl) {
            ticketLevel = lvl;
            ticketCursor = 0;
        }

        uint256 idx = ticketCursor;
        if (idx >= total) {
            // All done for this level
            delete ticketQueue[lvl];
            ticketCursor = 0;
            ticketLevel = 0;
            return true;
        }

        if (writesBudget == 0) {
            writesBudget = WRITES_BUDGET_SAFE;
        } else if (writesBudget < WRITES_BUDGET_MIN) {
            writesBudget = WRITES_BUDGET_MIN;
        }

        bool firstBatch = (idx == 0);
        if (firstBatch) {
            writesBudget -= (writesBudget * 35) / 100; // 65% scaling for cold storage
        }

        uint32 used = 0;
        uint256 entropy = rngWordCurrent;
        uint32 processed = 0; // Track within-player progress

        while (idx < total && used < writesBudget) {
            address player = queue[idx];
            uint32 owed = ticketsOwed[lvl][player];
            uint8 remainder = ticketsOwedFrac[lvl][player];
            if (owed == 0) {
                if (remainder == 0) {
                    unchecked {
                        ++idx;
                    }
                    processed = 0;
                    continue;
                }
                uint256 roll = uint256(keccak256(abi.encode(entropy, lvl, player, remainder)));
                ticketsOwedFrac[lvl][player] = 0;
                if ((roll % TICKET_SCALE) >= remainder) {
                    unchecked {
                        ++idx;
                    }
                    processed = 0;
                    continue;
                }
                owed = 1;
                ticketsOwed[lvl][player] = 1;
                remainder = 0;
            }
            if (owed == 0) {
                unchecked {
                    ++idx;
                }
                processed = 0;
                continue;
            }

            uint32 room = writesBudget - used;

            uint32 baseOv = 2;
            if (processed == 0 && owed <= 2) {
                baseOv += 2;
            }
            if (room <= baseOv) break;
            room -= baseOv;

            uint32 maxT = (room <= 256) ? (room / 2) : (room - 256);
            uint32 take = owed > maxT ? maxT : owed;
            if (take == 0) break;

            uint256 baseKey = (uint256(lvl) << 224) | (idx << 192) | (uint256(uint160(player)) << 32);
            _raritySymbolBatch(player, baseKey, processed, take, entropy);

            uint32 writesThis = (take <= 256) ? (take * 2) : (take + 256);
            writesThis += baseOv;
            if (take == owed) {
                writesThis += 1;
            }

            uint32 remainingOwed;
            unchecked {
                remainingOwed = owed - take;
            }
            if (remainingOwed == 0 && remainder != 0) {
                uint256 roll = uint256(keccak256(abi.encode(entropy, lvl, player, owed, remainder)));
                ticketsOwedFrac[lvl][player] = 0;
                if ((roll % TICKET_SCALE) < remainder && owed < type(uint32).max) {
                    remainingOwed = 1;
                }
            }
            ticketsOwed[lvl][player] = remainingOwed;
            unchecked {
                processed += take;
                used += writesThis;
            }
            if (remainingOwed == 0) {
                unchecked {
                    ++idx;
                }
                processed = 0;
            }
        }

        ticketCursor = uint32(idx);

        if (idx >= total) {
            // Cleanup when done
            delete ticketQueue[lvl];
            ticketCursor = 0;
            ticketLevel = 0;
            return true;
        }
        return false;
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
                    uint8 traitId = DegenerusTraitUtils.traitFromWord(s) + (uint8(i & 3) << 6);

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

    /// @dev Clears all 80 daily burn counters using assembly for gas efficiency.
    ///      The counters are packed 8 per slot (10 slots total).
    function _clearDailyBurnCount() private {
        assembly ("memory-safe") {
            let slot := dailyBurnCount.slot
            let end := add(slot, 10)
            for {
                let s := slot
            } lt(s, end) {
                s := add(s, 1)
            } {
                sstore(s, 0)
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
        if (len == 0 || numWinners == 0) return new address[](0);

        winners = new address[](numWinners);
        // XOR in trait and salt to create unique entropy per call.
        uint256 slice = randomWord ^ (uint256(trait) << 128) ^ (uint256(salt) << 192);
        for (uint256 i; i < numWinners; ) {
            uint256 idx = slice % len;
            winners[i] = holders[idx];
            unchecked {
                ++i;
                // Rotate bits to get different indices for subsequent winners.
                slice = (slice >> 16) | (slice << 240);
            }
        }
    }

    /// @dev Collects per-trait ticket counts for a level.
    /// @param lvl Level to inspect.
    /// @param sizes Output array of ticket counts per trait (0-255).
    /// @return totalTickets Sum of all trait ticket counts for the level.
    function _collectTraitTicketSizes(
        uint24 lvl,
        uint256[256] memory sizes
    ) private view returns (uint256 totalTickets) {
        for (uint256 traitId; traitId < 256; ++traitId) {
            uint256 len = traitBurnTicket[lvl][traitId].length;
            sizes[traitId] = len;
            totalTickets += len;
        }
    }

    /// @dev Selects a random ticket holder across all traits for a level.
    /// @param lvl Level to select from.
    /// @param sizes Per-trait ticket counts (from _collectTraitTicketSizes).
    /// @param totalTickets Total tickets across all traits.
    /// @param entropy VRF-derived entropy for selection.
    function _selectTraitTicketWinner(
        uint24 lvl,
        uint256[256] memory sizes,
        uint256 totalTickets,
        uint256 entropy
    ) private view returns (address winner) {
        if (totalTickets == 0) return address(0);

        uint256 idx = entropy % totalTickets;
        for (uint256 traitId; traitId < 256; ++traitId) {
            uint256 len = sizes[traitId];
            if (len == 0) continue;
            if (idx < len) {
                return traitBurnTicket[lvl][traitId][idx];
            }
            unchecked {
                idx -= len;
            }
        }
        return address(0);
    }

    /// @dev Calculate current day index from timestamp.
    ///      Day 1 = deploy day. Days reset at JACKPOT_RESET_TIME (22:57 UTC).
    /// @return Day index (1-indexed from deploy day).
    function _calculateDayIndex() private view returns (uint48) {
        uint48 currentDayBoundary = uint48((block.timestamp - JACKPOT_RESET_TIME) / 1 days);
        return currentDayBoundary - ContractAddresses.DEPLOY_DAY_BOUNDARY + 1;
    }

    function _creditDgnrsCoinflipAndVault(uint256 prizePoolWei) private {
        uint256 priceWei = price;
        if (priceWei == 0) return;
        uint256 coinAmount = (prizePoolWei * PRICE_COIN_UNIT) / (priceWei * 20);
        if (coinAmount == 0) return;
        coin.creditFlip(ContractAddresses.DGNRS, coinAmount);
        coin.vaultEscrow(coinAmount);
    }

    /// @notice Pays daily BURNIE jackpot to random ticket holders from winning traits.
    /// @dev Runs every day in its own transaction. Awards 0.5% of lastPrizePool in BURNIE.
    ///      Uses winning traits from the daily/early jackpot when available; otherwise rolls
    ///      with the same logic. Picks a random level in [lvl, lvl+4] and pays winners from
    ///      those trait-level tickets.
    /// @param lvl Current level.
    /// @param randWord VRF entropy for winner selection.
    function payDailyCoinJackpot(uint24 lvl, uint256 randWord) external {
        // Calculate 0.5% of lastPrizePool in BURNIE
        uint256 priceWei = price;
        if (priceWei == 0) return; // Can't calculate coin equivalent without price

        // Gas optimization: Combine divisions (0.5% = 1/200)
        // Old: coinEquivalent = (lastPrizePool * PRICE_COIN_UNIT) / priceWei; coinBudget = coinEquivalent / 200
        // New: coinBudget = (lastPrizePool * PRICE_COIN_UNIT) / (priceWei * 200)
        uint256 coinBudget = (lastPrizePool * PRICE_COIN_UNIT) / (priceWei * 200);
        if (coinBudget == 0) return;

        uint48 questDay = _calculateDayIndex();
        uint32 winningTraitsPacked = lastDailyJackpotWinningTraits;
        if (lastDailyJackpotDay != questDay || lastDailyJackpotLevel != lvl) {
            // Fallback: roll traits using the same logic as the normal jackpot path.
            if (gameState == GAME_STATE_BURN) {
                winningTraitsPacked = _packWinningTraits(_getWinningTraits(randWord, dailyBurnCount));
                winningTraitsPacked = _applyExterminatedTraitPacked(winningTraitsPacked, lvl);
            } else {
                winningTraitsPacked = _packWinningTraits(_getRandomTraits(randWord));
            }
            lastDailyJackpotWinningTraits = winningTraitsPacked;
            lastDailyJackpotLevel = lvl;
            lastDailyJackpotDay = questDay;
        }

        uint256 entropy = randWord ^ (uint256(lvl) << 192) ^ uint256(COIN_JACKPOT_TAG);
        uint24 targetLevel = _selectDailyCoinTargetLevel(lvl, winningTraitsPacked, entropy);
        if (targetLevel == 0) return;

        _awardDailyCoinToTraitWinners(
            targetLevel,
            winningTraitsPacked,
            coinBudget,
            entropy
        );
    }

    /// @dev Pick a random target level in [lvl, lvl+4] that has winners for the packed traits.
    ///      Falls back to 0 (skip) if none of the five levels has eligible tickets.
    function _selectDailyCoinTargetLevel(
        uint24 lvl,
        uint32 winningTraitsPacked,
        uint256 entropy
    ) private view returns (uint24 targetLevel) {
        uint8 startOffset = uint8(entropy % 5);
        for (uint8 i; i < 5; ) {
            uint8 offset = uint8((startOffset + i) % 5);
            uint24 candidate = lvl + uint24(offset);
            if (_hasTraitTickets(candidate, winningTraitsPacked)) {
                return candidate;
            }
            unchecked {
                ++i;
            }
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
        (
            address[] memory winners,
            uint256[] memory amounts
        ) = _getJackpotWinnersWithAmounts(
                lvl,
                winningTraitsPacked,
                coinBudget,
                entropy,
                DAILY_COIN_MAX_WINNERS,
                DAILY_COIN_SALT_BASE
            );

        uint256 len = winners.length;
        for (uint256 i; i < len; ) {
            address winner = winners[i];
            uint256 amount = amounts[i];
            if (winner != address(0) && amount != 0) {
                coin.creditFlip(winner, amount);
            }
            unchecked {
                ++i;
            }
        }
    }
}
