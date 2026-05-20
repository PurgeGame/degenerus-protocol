// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {IDegenerusCoin} from "../interfaces/IDegenerusCoin.sol";
import {IBurnieCoinflip} from "../interfaces/IBurnieCoinflip.sol";
import {IDegenerusGame} from "../interfaces/IDegenerusGame.sol";
import {IStakedDegenerusStonk} from "../interfaces/IStakedDegenerusStonk.sol";

import {IDegenerusGameBoonModule} from "../interfaces/IDegenerusGameModules.sol";
import {ContractAddresses} from "../ContractAddresses.sol";
import {DegenerusGameStorage} from "../storage/DegenerusGameStorage.sol";
import {BitPackingLib} from "../libraries/BitPackingLib.sol";
import {EntropyLib} from "../libraries/EntropyLib.sol";
import {PriceLookupLib} from "../libraries/PriceLookupLib.sol";

/// @notice Interface for minting WWXRP prize tokens
interface IWrappedWrappedXRP {
    /// @notice Mint prize tokens to a recipient
    /// @param to The address to receive the prize
    /// @param amount The amount of tokens to mint
    function mintPrize(address to, uint256 amount) external;
}

/**
 * @title DegenerusGameLootboxModule
 * @author Burnie Degenerus
 * @notice Delegatecall module for lootbox opening, boon consumption, and deity boon system.
 *
 * @dev This module is called via `delegatecall` from DegenerusGame, meaning all storage
 *      reads/writes operate on the game contract's storage.
 *
 * ## Functions
 *
 * - Lootbox opening (openLootBox, openBurnieLootBox, resolveLootboxDirect, resolveRedemptionLootbox)
 * - Deity boon system (deityBoonSlots, issueDeityBoon)
 */
contract DegenerusGameLootboxModule is DegenerusGameStorage {
    // =========================================================================
    // Errors
    // =========================================================================

    // error E() — inherited from DegenerusGameStorage

    /// @notice RNG word has not been set for the requested lootbox index
    error RngNotReady();


    // =========================================================================
    // Events
    // =========================================================================

    /// @notice Emitted when ETH is credited to a player's claimable balance.
    /// @param player Winner address credited.
    /// @param recipient Recipient address (may differ from player for delegated claims).
    /// @param amount ETH amount credited (in wei).
    event PlayerCredited(address indexed player, address indexed recipient, uint256 amount);

    /// @notice Emitted when an ETH lootbox is successfully opened
    /// @param player The player who opened the lootbox
    /// @param lootboxIndex The per-player storage index of the opened lootbox
    /// @param day The day index when the lootbox was opened
    /// @param amount The ETH amount of the lootbox (in wei)
    /// @param futureLevel The target level for future tickets
    /// @param futureTickets The pre-Bernoulli scaled (× TICKET_SCALE) future ticket count
    /// @param burnie The total BURNIE tokens awarded (in wei)
    /// @param roundedUp True iff the Bernoulli round-up incremented the awarded
    ///        whole-ticket count by 1
    event LootBoxOpened(
        address indexed player,
        uint48 indexed lootboxIndex,
        uint32 day,
        uint256 amount,
        uint24 futureLevel,
        uint32 futureTickets,
        uint256 burnie,
        bool roundedUp
    );

    /// @notice Emitted when a BURNIE lootbox is successfully opened
    /// @param player The player who opened the lootbox
    /// @param index The RNG index of the lootbox
    /// @param burnieAmount The BURNIE amount used to open the lootbox
    /// @param ticketLevel The target level for tickets
    /// @param tickets The pre-Bernoulli scaled (× TICKET_SCALE) ticket count
    /// @param burnieReward The BURNIE reward amount
    /// @param roundedUp True iff the Bernoulli round-up incremented the awarded
    ///        whole-ticket count by 1
    event BurnieLootOpen(
        address indexed player,
        uint32 indexed index,
        uint256 burnieAmount,
        uint24 ticketLevel,
        uint32 tickets,
        uint256 burnieReward,
        bool roundedUp
    );

    /// @notice Emitted when a lootbox awards a whale pass jackpot
    /// @param player The player who won the jackpot
    /// @param day The day index of the jackpot
    /// @param lootboxAmount The ETH amount of the lootbox
    /// @param targetLevel The target level for the jackpot
    /// @param tickets Tickets per level granted by the whale pass reward
    /// @param statsBoost Reserved for future use (always 0)
    /// @param frozenUntilLevel Reserved for future use (always 0)
    event LootBoxWhalePassJackpot(
        address indexed player,
        uint32 indexed day,
        uint256 lootboxAmount,
        uint24 targetLevel,
        uint32 tickets,
        uint24 statsBoost,
        uint24 frozenUntilLevel
    );

    /// @notice Emitted when a lootbox awards DGNRS tokens
    /// @param player The player who received the reward
    /// @param day The day index of the reward
    /// @param lootboxAmount The ETH amount of the lootbox
    /// @param dgnrsAmount The amount of DGNRS tokens awarded
    event LootBoxDgnrsReward(
        address indexed player,
        uint32 indexed day,
        uint256 lootboxAmount,
        uint256 dgnrsAmount
    );

    /// @notice Unified lootbox reward event for boon awards
    /// @param player The player receiving the reward
    /// @param day The day index of the reward
    /// @param rewardType The type of reward (2=CoinflipBoon, 4=Boost5, 5=Boost15, 6=Boost25/Purchase, 8=DecimatorBoost, 9=WhaleBoon, 10=ActivityBoon/DeityPassBoon, 11=LazyPassBoon)
    /// @param lootboxAmount The lootbox amount spent (ETH-equivalent for BURNIE lootboxes)
    /// @param amount Primary reward amount (varies by type: BPS for boosts, token amount for boons)
    event LootBoxReward(
        address indexed player,
        uint32 indexed day,
        uint8 indexed rewardType,
        uint256 lootboxAmount,
        uint256 amount
    );

    /// @notice Emitted when a deity issues a boon to another player
    /// @param deity The deity pass holder issuing the boon
    /// @param recipient The player receiving the boon
    /// @param day The day index when the boon was issued
    /// @param slot The slot index (0-2) of the boon
    /// @param boonType The type of boon issued (1-31)
    event DeityBoonIssued(
        address indexed deity,
        address indexed recipient,
        uint32 indexed day,
        uint8 slot,
        uint8 boonType
    );

    // =========================================================================
    // External Contract References
    // =========================================================================

    /// @notice Reference to the WWXRP token contract
    IWrappedWrappedXRP internal constant wwxrp = IWrappedWrappedXRP(ContractAddresses.WWXRP);


    // =========================================================================
    // Constants
    // =========================================================================

    /// @dev Portion of lootbox EV reserved for boon/pass draw (10%)
    uint16 private constant LOOTBOX_BOON_BUDGET_BPS = 1000;
    /// @dev Maximum boon/pass budget per lootbox (1 ETH scaled)
    uint256 private constant LOOTBOX_BOON_MAX_BUDGET =
        1 ether;
    /// @dev Assumed utilization of max boon value (50%)
    uint16 private constant LOOTBOX_BOON_UTILIZATION_BPS = 5000;

    /// @dev Whale boon discount tiers (10%, 25%, 50%).
    uint16 private constant LOOTBOX_WHALE_BOON_DISCOUNT_10_BPS = 1000;
    uint16 private constant LOOTBOX_WHALE_BOON_DISCOUNT_25_BPS = 2500;
    uint16 private constant LOOTBOX_WHALE_BOON_DISCOUNT_50_BPS = 5000;
    /// @dev Lazy pass boon discount tiers (10%, 25%, 50%).
    uint16 private constant LOOTBOX_LAZY_PASS_DISCOUNT_10_BPS = 1000;
    uint16 private constant LOOTBOX_LAZY_PASS_DISCOUNT_25_BPS = 2500;
    uint16 private constant LOOTBOX_LAZY_PASS_DISCOUNT_50_BPS = 5000;
    /// @dev Tier identifier for 10% deity pass discount boon (1000 bps)
    uint8 private constant DEITY_PASS_BOON_TIER_10 = 1;
    /// @dev Tier identifier for 25% deity pass discount boon (2500 bps)
    uint8 private constant DEITY_PASS_BOON_TIER_25 = 2;
    /// @dev Tier identifier for 50% deity pass discount boon (5000 bps)
    uint8 private constant DEITY_PASS_BOON_TIER_50 = 3;
    /// @dev Threshold used by deity-pass discount boon availability logic.
    uint32 private constant DEITY_PASS_MAX_TOTAL = 32;

    // Boon bonus values
    /// @dev 5% bonus in basis points for coinflip boon
    uint16 private constant LOOTBOX_BOON_BONUS_BPS = 500;
    /// @dev Maximum bonus amount for coinflip boon (5000 BURNIE)
    uint256 private constant LOOTBOX_BOON_MAX_BONUS = 5000 ether;
    /// @dev Coinflip boon cap for max deposit (100k BURNIE) used in EV estimation.
    uint256 private constant COINFLIP_BOON_MAX_DEPOSIT = 100_000 ether;
    /// @dev Decimator boon cap for base amount (50k BURNIE) used in EV estimation.
    uint256 private constant DECIMATOR_BOON_CAP = 50_000 ether;
    /// @dev Whale bundle standard price (used for whale discount boon EV estimation).
    uint256 private constant WHALE_BUNDLE_STANDARD_PRICE =
        4 ether;
    /// @dev Whale pass standard tickets per level.
    uint32 private constant WHALE_PASS_TICKETS_PER_LEVEL = 2;
    /// @dev Whale pass bonus tickets per level for early levels.
    uint32 private constant WHALE_PASS_BONUS_TICKETS_PER_LEVEL = 40;
    /// @dev Last level eligible for whale pass bonus tickets.
    uint24 private constant WHALE_PASS_BONUS_END_LEVEL = 10;
    /// @dev Deity pass base price (used for deity discount boon EV estimation).
    uint256 private constant DEITY_PASS_BASE = 24 ether;
    /// @dev 10% bonus in basis points for coinflip boon
    uint16 private constant LOOTBOX_COINFLIP_10_BONUS_BPS = 1000;
    /// @dev 25% bonus in basis points for coinflip boon
    uint16 private constant LOOTBOX_COINFLIP_25_BONUS_BPS = 2500;
    /// @dev 5% lootbox boost in basis points
    uint16 private constant LOOTBOX_BOOST_5_BONUS_BPS = 500;
    /// @dev 15% lootbox boost in basis points
    uint16 private constant LOOTBOX_BOOST_15_BONUS_BPS = 1500;
    /// @dev 25% lootbox boost in basis points
    uint16 private constant LOOTBOX_BOOST_25_BONUS_BPS = 2500;
    /// @dev 5% purchase boost in basis points
    uint16 private constant LOOTBOX_PURCHASE_BOOST_5_BONUS_BPS = 500;
    /// @dev 15% purchase boost in basis points
    uint16 private constant LOOTBOX_PURCHASE_BOOST_15_BONUS_BPS = 1500;
    /// @dev 25% purchase boost in basis points
    uint16 private constant LOOTBOX_PURCHASE_BOOST_25_BONUS_BPS = 2500;
    /// @dev 10% decimator boost in basis points
    uint16 private constant LOOTBOX_DECIMATOR_10_BONUS_BPS = 1000;
    /// @dev 25% decimator boost in basis points
    uint16 private constant LOOTBOX_DECIMATOR_25_BONUS_BPS = 2500;
    /// @dev 50% decimator boost in basis points
    uint16 private constant LOOTBOX_DECIMATOR_50_BONUS_BPS = 5000;
    /// @dev 10 point activity boon bonus
    uint24 private constant LOOTBOX_ACTIVITY_BOON_10_BONUS = 10;
    /// @dev 25 point activity boon bonus
    uint24 private constant LOOTBOX_ACTIVITY_BOON_25_BONUS = 25;
    /// @dev 50 point activity boon bonus
    uint24 private constant LOOTBOX_ACTIVITY_BOON_50_BONUS = 50;

    // Lootbox roll constants
    /// @dev Base ticket roll budget in BPS (~127% EV after variance, 55% chance path)
    uint16 private constant LOOTBOX_TICKET_ROLL_BPS = 16_100;
    /// @dev 1% chance for tier 1 ticket variance (4.6x multiplier)
    uint16 private constant LOOTBOX_TICKET_VARIANCE_TIER1_CHANCE_BPS = 100;
    /// @dev 4% chance for tier 2 ticket variance (2.3x multiplier)
    uint16 private constant LOOTBOX_TICKET_VARIANCE_TIER2_CHANCE_BPS = 400;
    /// @dev 20% chance for tier 3 ticket variance (1.1x multiplier)
    uint16 private constant LOOTBOX_TICKET_VARIANCE_TIER3_CHANCE_BPS = 2000;
    /// @dev 45% chance for tier 4 ticket variance (0.651x multiplier)
    uint16 private constant LOOTBOX_TICKET_VARIANCE_TIER4_CHANCE_BPS = 4500;
    /// @dev 4.6x ticket multiplier for tier 1
    uint16 private constant LOOTBOX_TICKET_VARIANCE_TIER1_BPS = 46_000;
    /// @dev 2.3x ticket multiplier for tier 2
    uint16 private constant LOOTBOX_TICKET_VARIANCE_TIER2_BPS = 23_000;
    /// @dev 1.1x ticket multiplier for tier 3
    uint16 private constant LOOTBOX_TICKET_VARIANCE_TIER3_BPS = 11_000;
    /// @dev 0.651x ticket multiplier for tier 4
    uint16 private constant LOOTBOX_TICKET_VARIANCE_TIER4_BPS = 6_510;
    /// @dev 0.45x ticket multiplier for tier 5 (default)
    uint16 private constant LOOTBOX_TICKET_VARIANCE_TIER5_BPS = 4_500;
    /// @dev 0.001% of DGNRS pool per ETH for small tier
    uint16 private constant LOOTBOX_DGNRS_POOL_SMALL_PPM = 10;
    /// @dev 0.039% of DGNRS pool per ETH for medium tier
    uint16 private constant LOOTBOX_DGNRS_POOL_MEDIUM_PPM = 390;
    /// @dev 0.08% of DGNRS pool per ETH for large tier
    uint16 private constant LOOTBOX_DGNRS_POOL_LARGE_PPM = 800;
    /// @dev 0.8% of DGNRS pool per ETH for mega tier
    uint16 private constant LOOTBOX_DGNRS_POOL_MEGA_PPM = 8000;
    /// @dev Fixed WWXRP prize amount (1 token)
    uint256 private constant LOOTBOX_WWXRP_PRIZE = 1 ether;
    /// @dev Cold-bust consolation magnitude (1 token). Paid on a manual lootbox open
    ///      whose ticket-path produced non-zero scaled tickets but the Bernoulli
    ///      round-up failed to award a whole ticket. Magnitude-equal to
    ///      LOOTBOX_WWXRP_PRIZE — the consolation trigger is much rarer than the
    ///      10%-path WWXRP win, so 1:1 magnitude is intentional.
    uint256 private constant LOOTBOX_WWXRP_CONSOLATION = 1 ether;
    /// @dev Base BPS for low BURNIE path (58.1%)
    uint16 private constant LOOTBOX_LARGE_BURNIE_LOW_BASE_BPS = 5_808;
    /// @dev Step increase in BPS for low BURNIE path (4.77% per step)
    uint16 private constant LOOTBOX_LARGE_BURNIE_LOW_STEP_BPS = 477;
    /// @dev Base BPS for high BURNIE path (307%)
    uint16 private constant LOOTBOX_LARGE_BURNIE_HIGH_BASE_BPS = 30_705;
    /// @dev Step increase in BPS for high BURNIE path (94.3% per step)
    uint16 private constant LOOTBOX_LARGE_BURNIE_HIGH_STEP_BPS = 9_430;
    /// @dev Presale BURNIE bonus in BPS (62% bonus, reduced to keep presale total stable)
    uint16 private constant LOOTBOX_PRESALE_BURNIE_BONUS_BPS = 6_200;
    /// @dev Whale pass price (200 tickets over levels 10-109)
    uint256 private constant LOOTBOX_WHALE_PASS_PRICE =
        4.50 ether;
    /// @dev Half whale pass price (100 tickets over levels 10-109)
    uint256 private constant HALF_WHALE_PASS_PRICE =
        2.25 ether;
    /// @dev Threshold above which lootbox is split into two rolls (0.5 ETH scaled)
    uint256 private constant LOOTBOX_SPLIT_THRESHOLD =
        0.5 ether;

    /// @dev Distress-mode ticket bonus in basis points (25%).
    uint16 private constant DISTRESS_TICKET_BONUS_BPS = 2500;

    // Activity score EV multiplier constants (ETH lootbox only)
    /// @dev 60% activity score = neutral 100% EV
    uint16 private constant ACTIVITY_SCORE_NEUTRAL_BPS = 6_000;
    /// @dev 255%+ activity score = maximum 135% EV
    uint16 private constant ACTIVITY_SCORE_MAX_BPS = 25_500;
    /// @dev Minimum EV at 0% activity (80%)
    uint16 private constant LOOTBOX_EV_MIN_BPS = 8_000;
    /// @dev Neutral EV at 60% activity (100%)
    uint16 private constant LOOTBOX_EV_NEUTRAL_BPS = 10_000;
    /// @dev Maximum EV at 255%+ activity (135%)
    uint16 private constant LOOTBOX_EV_MAX_BPS = 13_500;
    /// @dev Maximum EV benefit cap per account per level (10 ETH scaled)
    uint256 private constant LOOTBOX_EV_BENEFIT_CAP =
        10 ether;

    /// @dev Probability scale for granular boon rolls (ppm = 1e6).
    uint256 private constant BOON_PPM_SCALE = 1_000_000;

    // Boon categories — players may hold one boon per category simultaneously.
    // Within a category, upgrade semantics apply (higher tier replaces lower).

    // Deity boon constants
    /// @dev Number of boon slots available per deity per day
    uint8 private constant DEITY_DAILY_BOON_COUNT = 3;

    /// @dev Boon type: 5% coinflip bonus
    uint8 private constant BOON_COINFLIP_5 = 1;
    /// @dev Boon type: 10% coinflip bonus
    uint8 private constant BOON_COINFLIP_10 = 2;
    /// @dev Boon type: 25% coinflip bonus
    uint8 private constant BOON_COINFLIP_25 = 3;
    /// @dev Boon type: 5% lootbox boost
    uint8 private constant BOON_LOOTBOX_5 = 5;
    /// @dev Boon type: 15% lootbox boost
    uint8 private constant BOON_LOOTBOX_15 = 6;
    /// @dev Boon type: 5% purchase boost
    uint8 private constant BOON_PURCHASE_5 = 7;
    /// @dev Boon type: 15% purchase boost
    uint8 private constant BOON_PURCHASE_15 = 8;
    /// @dev Boon type: 25% purchase boost
    uint8 private constant BOON_PURCHASE_25 = 9;
    /// @dev Boon type: 10% decimator boost
    uint8 private constant BOON_DECIMATOR_10 = 13;
    /// @dev Boon type: 25% decimator boost
    uint8 private constant BOON_DECIMATOR_25 = 14;
    /// @dev Boon type: 50% decimator boost
    uint8 private constant BOON_DECIMATOR_50 = 15;
    /// @dev Boon type: 10% whale discount
    uint8 private constant BOON_WHALE_10 = 16;
    /// @dev Boon type: 10 point activity bonus
    uint8 private constant BOON_ACTIVITY_10 = 17;
    /// @dev Boon type: 25 point activity bonus
    uint8 private constant BOON_ACTIVITY_25 = 18;
    /// @dev Boon type: 50 point activity bonus
    uint8 private constant BOON_ACTIVITY_50 = 19;
    /// @dev Boon type: 25% lootbox boost
    uint8 private constant BOON_LOOTBOX_25 = 22;
    /// @dev Boon type: 25% whale discount
    uint8 private constant BOON_WHALE_25 = 23;
    /// @dev Boon type: 50% whale discount
    uint8 private constant BOON_WHALE_50 = 24;
    /// @dev Boon type: 10% deity pass discount
    uint8 private constant BOON_DEITY_PASS_10 = 25;
    /// @dev Boon type: 25% deity pass discount
    uint8 private constant BOON_DEITY_PASS_25 = 26;
    /// @dev Boon type: 50% deity pass discount
    uint8 private constant BOON_DEITY_PASS_50 = 27;
    /// @dev Boon type: whale pass award
    uint8 private constant BOON_WHALE_PASS = 28;
    /// @dev Boon type: 10% lazy pass discount
    uint8 private constant BOON_LAZY_PASS_10 = 29;
    /// @dev Boon type: 25% lazy pass discount
    uint8 private constant BOON_LAZY_PASS_25 = 30;
    /// @dev Boon type: 50% lazy pass discount
    uint8 private constant BOON_LAZY_PASS_50 = 31;

    // Deity boon weights (used for weighted random selection)
    /// @dev Weight for 5% coinflip boon
    uint16 private constant BOON_WEIGHT_COINFLIP_5 = 200;
    /// @dev Weight for 10% coinflip boon
    uint16 private constant BOON_WEIGHT_COINFLIP_10 = 40;
    /// @dev Weight for 25% coinflip boon
    uint16 private constant BOON_WEIGHT_COINFLIP_25 = 8;
    /// @dev Weight for 5% lootbox boost boon
    uint16 private constant BOON_WEIGHT_LOOTBOX_5 = 200;
    /// @dev Weight for 15% lootbox boost boon
    uint16 private constant BOON_WEIGHT_LOOTBOX_15 = 30;
    /// @dev Weight for 25% lootbox boost boon
    uint16 private constant BOON_WEIGHT_LOOTBOX_25 = 8;
    /// @dev Weight for 5% purchase boost boon
    uint16 private constant BOON_WEIGHT_PURCHASE_5 = 400;
    /// @dev Weight for 15% purchase boost boon
    uint16 private constant BOON_WEIGHT_PURCHASE_15 = 80;
    /// @dev Weight for 25% purchase boost boon
    uint16 private constant BOON_WEIGHT_PURCHASE_25 = 16;
    /// @dev Weight for 10% decimator boost boon
    uint16 private constant BOON_WEIGHT_DECIMATOR_10 = 40;
    /// @dev Weight for 25% decimator boost boon
    uint16 private constant BOON_WEIGHT_DECIMATOR_25 = 8;
    /// @dev Weight for 50% decimator boost boon
    uint16 private constant BOON_WEIGHT_DECIMATOR_50 = 2;
    /// @dev Weight for 10% whale boon
    uint16 private constant BOON_WEIGHT_WHALE_10 = 28;
    /// @dev Weight for 25% whale boon
    uint16 private constant BOON_WEIGHT_WHALE_25 = 10;
    /// @dev Weight for 50% whale boon
    uint16 private constant BOON_WEIGHT_WHALE_50 = 2;
    /// @dev Weight for 10% deity pass discount boon
    uint16 private constant BOON_WEIGHT_DEITY_PASS_10 = 28;
    /// @dev Weight for 25% deity pass discount boon
    uint16 private constant BOON_WEIGHT_DEITY_PASS_25 = 10;
    /// @dev Weight for 50% deity pass discount boon
    uint16 private constant BOON_WEIGHT_DEITY_PASS_50 = 2;
    /// @dev Weight for 10 point activity boon
    uint16 private constant BOON_WEIGHT_ACTIVITY_10 = 100;
    /// @dev Weight for 25 point activity boon
    uint16 private constant BOON_WEIGHT_ACTIVITY_25 = 30;
    /// @dev Weight for 50 point activity boon
    uint16 private constant BOON_WEIGHT_ACTIVITY_50 = 8;
    /// @dev Weight for whale pass award
    uint16 private constant BOON_WEIGHT_WHALE_PASS = 8;
    /// @dev Weight for 10% lazy pass discount boon
    uint16 private constant BOON_WEIGHT_LAZY_PASS_10 = 30;
    /// @dev Weight for 25% lazy pass discount boon
    uint16 private constant BOON_WEIGHT_LAZY_PASS_25 = 8;
    /// @dev Weight for 50% lazy pass discount boon
    uint16 private constant BOON_WEIGHT_LAZY_PASS_50 = 2;
    /// @dev Combined weight of deity pass discount boons (10% + 25% + 50%)
    uint16 private constant BOON_WEIGHT_DEITY_PASS_ALL = 40;
    /// @dev Total weight sum when decimator boons are allowed
    uint16 private constant BOON_WEIGHT_TOTAL = 1298;
    /// @dev Total weight sum when decimator boons are not allowed
    uint16 private constant BOON_WEIGHT_TOTAL_NO_DECIMATOR = 1248;

    // =========================================================================
    // Lootbox Opening Functions
    // =========================================================================

    /// @dev Calculates EV multiplier based on activity score (ETH lootbox only).
    ///      Linear scaling: 0% activity → 80% EV, 60% activity → 100% EV, 255%+ activity → 135% EV.
    /// @param player The player address to calculate EV multiplier for
    /// @return The EV multiplier in basis points (8000-13500)
    function _lootboxEvMultiplierBps(address player) private view returns (uint256) {
        uint256 score = IDegenerusGame(address(this)).playerActivityScore(player);
        return _lootboxEvMultiplierFromScore(score);
    }

    /// @dev Calculates EV multiplier from a raw activity score.
    ///      Linear interpolation between thresholds.
    /// @param score The activity score in basis points
    /// @return The EV multiplier in basis points (8000-13500)
    function _lootboxEvMultiplierFromScore(
        uint256 score
    ) private pure returns (uint256) {
        if (score <= ACTIVITY_SCORE_NEUTRAL_BPS) {
            // Linear: 0% → 80% EV, 60% → 100% EV
            return LOOTBOX_EV_MIN_BPS +
                (score * (LOOTBOX_EV_NEUTRAL_BPS - LOOTBOX_EV_MIN_BPS)) /
                ACTIVITY_SCORE_NEUTRAL_BPS;
        }

        if (score >= ACTIVITY_SCORE_MAX_BPS) {
            return LOOTBOX_EV_MAX_BPS;
        }

        // Linear: 60% → 100% EV, 255% → 135% EV
        uint256 excess = score - ACTIVITY_SCORE_NEUTRAL_BPS;
        uint256 maxExcess = ACTIVITY_SCORE_MAX_BPS - ACTIVITY_SCORE_NEUTRAL_BPS;
        return
            LOOTBOX_EV_NEUTRAL_BPS +
            (excess * (LOOTBOX_EV_MAX_BPS - LOOTBOX_EV_NEUTRAL_BPS)) /
            maxExcess;
    }

    /// @dev Apply EV multiplier with per-account per-level cap of 10 ETH.
    ///      Tracks how much benefit has been used and only applies EV adjustment
    ///      to the uncapped portion. Remainder gets 100% EV (neutral).
    /// @param player Player address
    /// @param lvl Current game level
    /// @param amount Lootbox ETH amount
    /// @param evMultiplierBps EV multiplier in basis points (8000-13500)
    /// @return scaledAmount Amount after EV adjustment
    function _applyEvMultiplierWithCap(
        address player,
        uint24 lvl,
        uint256 amount,
        uint256 evMultiplierBps
    ) private returns (uint256 scaledAmount) {
        // If EV is exactly 100%, no tracking needed
        if (evMultiplierBps == LOOTBOX_EV_NEUTRAL_BPS) {
            return amount;
        }

        // Check how much EV benefit capacity remains for this level
        uint256 usedBenefit = lootboxEvBenefitUsedByLevel[player][lvl];
        uint256 remainingCap = usedBenefit >= LOOTBOX_EV_BENEFIT_CAP
            ? 0
            : LOOTBOX_EV_BENEFIT_CAP - usedBenefit;

        if (remainingCap == 0) {
            // Cap exhausted: apply 100% EV (neutral)
            return amount;
        }

        // Determine how much of this lootbox gets the EV adjustment
        uint256 adjustedPortion = amount > remainingCap ? remainingCap : amount;
        uint256 neutralPortion = amount - adjustedPortion;

        // Update tracking
        lootboxEvBenefitUsedByLevel[player][lvl] = usedBenefit + adjustedPortion;

        // Calculate scaled amount:
        // - adjustedPortion gets the full EV multiplier
        // - neutralPortion gets 100% EV
        uint256 adjustedValue = (adjustedPortion * evMultiplierBps) / 10_000;
        scaledAmount = adjustedValue + neutralPortion;
    }

    /// @notice Open an ETH lootbox once RNG is available
    /// @dev Applies activity score EV multiplier with a 10 ETH cap per account per level.
    /// @param player Player address to open lootbox for
    /// @param index The RNG index of the lootbox
    /// @custom:reverts E When lootbox amount is zero
    /// @custom:reverts RngNotReady When RNG word has not been set for this index
    function openLootBox(address player, uint48 index) external {

        uint256 packed = lootboxEth[index][player];
        uint256 amount = packed & ((1 << 232) - 1);
        if (amount == 0) revert E();

        uint24 purchaseLevel = uint24(packed >> 232);
        uint256 rngWord = lootboxRngWordByIndex[index];
        if (rngWord == 0) revert RngNotReady();

        uint32 currentDay = _simulatedDayIndex();
        uint32 day = lootboxDay[index][player];
        if (day == 0) {
            day = currentDay;
        }

        bool presale = _psRead(PS_ACTIVE_SHIFT, PS_ACTIVE_MASK) != 0;
        uint256 baseAmount = lootboxEthBase[index][player];
        if (baseAmount == 0) {
            baseAmount = amount;
        }

        uint24 currentLevel = level + 1;
        bool withinGracePeriod = currentDay <= day + 7;
        uint24 baseLevelPacked = lootboxBaseLevelPacked[index][player];
        uint24 graceLevel = baseLevelPacked == 0 ? currentLevel : baseLevelPacked - 1;
        uint24 baseLevel = withinGracePeriod ? graceLevel : purchaseLevel;

        uint256 seed = uint256(keccak256(abi.encode(rngWord, player, day, amount)));
        uint24 targetLevel = _rollTargetLevel(baseLevel, seed);

        if (targetLevel < currentLevel) {
            targetLevel = currentLevel;
        }

        // Apply activity score EV multiplier to reward amount (80% to 135%)
        // EV benefit (above/below 100%) is capped at 10 ETH per account per level.
        // evScorePacked is the score+1 snapshot written at first deposit on every
        // ETH-lootbox allocation path; raw activity score maxes at ~318%, so the
        // uint16 encoding is always >=1 and the multiplier uses the committed score.
        uint16 evScorePacked = lootboxEvScorePacked[index][player];
        uint256 evMultiplierBps = _lootboxEvMultiplierFromScore(uint256(evScorePacked - 1));
        uint256 scaledAmount = _applyEvMultiplierWithCap(
            player,
            currentLevel,
            amount,
            evMultiplierBps
        );

        uint256 distressEth = lootboxDistressEth[index][player];

        lootboxEth[index][player] = 0;
        lootboxEthBase[index][player] = 0;
        lootboxBaseLevelPacked[index][player] = 0;
        lootboxEvScorePacked[index][player] = 0;
        if (distressEth != 0) {
            lootboxDistressEth[index][player] = 0;
        }
        _resolveLootboxCommon(
            player,
            day,
            index,
            scaledAmount,
            targetLevel,
            currentLevel,
            seed,
            presale,
            true,
            true,
            true,
            true,
            distressEth,
            amount
        );
    }

    /// @notice Open a BURNIE lootbox once RNG is available
    /// @dev Converts BURNIE to ETH-equivalent value at 80% rate for resolution.
    /// @param player Player address to open lootbox for
    /// @param index The RNG index of the lootbox
    /// @custom:reverts E When lootbox amount is zero or price is zero
    /// @custom:reverts RngNotReady When RNG word has not been set for this index
    function openBurnieLootBox(address player, uint48 index) external {

        uint256 burnieAmount = lootboxBurnie[index][player];
        if (burnieAmount == 0) revert E();

        uint256 rngWord = lootboxRngWordByIndex[index];
        if (rngWord == 0) revert RngNotReady();

        lootboxBurnie[index][player] = 0;

        // Resolve using ETH-equivalent value at 80% rate without whale/presale bonuses
        uint256 priceWei = PriceLookupLib.priceForLevel(level);
        if (priceWei == 0) revert E();
        uint256 amountEth = (burnieAmount * priceWei * 80) / (PRICE_COIN_UNIT * 100);
        if (amountEth == 0) revert E();

        uint24 currentLevel = level + 1;
        uint32 day = lootboxDay[index][player];
        if (day == 0) {
            day = _simulatedDayIndex();
        }

        uint256 seed = uint256(keccak256(abi.encode(rngWord, player, day, amountEth)));
        uint24 targetLevel = _rollTargetLevel(currentLevel, seed);

        // ENF-02: When gameOverPossible, redirect current-level BURNIE lootbox
        // tickets to far-future key space. Near-future rolls land normally.
        if (gameOverPossible && targetLevel == currentLevel) {
            targetLevel = currentLevel | TICKET_FAR_FUTURE_BIT;
        }

        (uint32 tickets, uint256 burnieReward, bool roundedUp) = _resolveLootboxCommon(
            player,
            day,
            index,
            amountEth,
            targetLevel,
            currentLevel,
            seed,
            false,
            false,
            false,
            true,
            true,
            0,
            0
        );

        emit BurnieLootOpen(
            player,
            uint32(index),
            burnieAmount,
            targetLevel,
            tickets,
            burnieReward,
            roundedUp
        );
    }

    /// @notice Resolve a lootbox directly for decimator claims (no RNG wait needed)
    /// @dev Jackpot/claim lootboxes do not award boons (allowBoons=false).
    /// @param player Player address to resolve for
    /// @param amount ETH amount for the lootbox resolution
    /// @param rngWord RNG word to use for resolution
    function resolveLootboxDirect(address player, uint256 amount, uint256 rngWord) external {
        if (amount == 0) return;

        uint32 day = _simulatedDayIndex();
        uint24 currentLevel = level + 1;
        uint256 seed = uint256(keccak256(abi.encode(rngWord, player, day, amount)));
        uint24 targetLevel = _rollTargetLevel(currentLevel, seed);

        uint256 evMultiplierBps = _lootboxEvMultiplierBps(player);
        uint256 scaledAmount = _applyEvMultiplierWithCap(player, currentLevel, amount, evMultiplierBps);

        _resolveLootboxCommon(
            player,
            day,
            0,
            scaledAmount,
            targetLevel,
            currentLevel,
            seed,
            false,
            true,
            false,
            false,
            false,
            0,
            0
        );
    }

    /// @notice Resolve a redemption lootbox with a snapshotted activity score
    /// @dev Called via delegatecall from Game when sDGNRS sends lootbox ETH during claimRedemption.
    ///      Uses provided activity score instead of reading current (score was snapshotted at submission).
    /// @param player Player address to resolve for
    /// @param amount ETH amount for the lootbox resolution
    /// @param rngWord RNG word to use for resolution
    /// @param activityScore Raw activity score (bps) snapshotted at burn submission
    function resolveRedemptionLootbox(address player, uint256 amount, uint256 rngWord, uint16 activityScore) external {
        if (amount == 0) return;

        uint32 day = _simulatedDayIndex();
        uint24 currentLevel = level + 1;
        uint256 seed = uint256(keccak256(abi.encode(rngWord, player, day, amount)));
        uint24 targetLevel = _rollTargetLevel(currentLevel, seed);

        uint256 evMultiplierBps = _lootboxEvMultiplierFromScore(uint256(activityScore));
        uint256 scaledAmount = _applyEvMultiplierWithCap(player, currentLevel, amount, evMultiplierBps);

        _resolveLootboxCommon(
            player,
            day,
            0,
            scaledAmount,
            targetLevel,
            currentLevel,
            seed,
            false,
            true,
            false,
            false,
            false,
            0,
            0
        );
    }

    // =========================================================================
    // Deity Boon Functions
    // =========================================================================

    /// @notice Get a deity's available boon slots for the current day
    /// @dev Returns deterministically generated boon types based on deity address and day.
    ///      Decimator boons only appear when decimator window is open.
    /// @param deity The deity pass holder address
    /// @return slots Array of 3 boon types (1-31) for each slot
    /// @return usedMask Bitmask of which slots have been used today (bit 0 = slot 0, etc.)
    /// @return day The current day index
    function deityBoonSlots(
        address deity
    ) external view returns (uint8[3] memory slots, uint8 usedMask, uint32 day) {
        day = _simulatedDayIndex();
        if (rngWordByDay[day] == 0) return (slots, usedMask, day);
        if (deityBoonDay[deity] == day) {
            usedMask = deityBoonUsedMask[deity];
        }

        bool decimatorAllowed = _isDecimatorWindow();
        bool deityPassAvailable = deityPassOwners.length < DEITY_PASS_MAX_TOTAL;
        for (uint8 i = 0; i < DEITY_DAILY_BOON_COUNT; ) {
            slots[i] = _deityBoonForSlot(deity, day, i, decimatorAllowed, deityPassAvailable);
            unchecked { ++i; }
        }
    }

    /// @notice Issue a deity boon to a recipient
    /// @dev Deity can issue up to 3 boons per day, one per recipient per day.
    /// @param deity The deity pass holder issuing the boon
    /// @param recipient The player receiving the boon
    /// @param slot The slot index (0-2) to use
    /// @custom:reverts E When deity or recipient is zero address
    /// @custom:reverts E When deity tries to issue boon to themselves
    /// @custom:reverts E When slot is >= 3
    /// @custom:reverts E When deity has no purchased passes
    /// @custom:reverts E When no RNG is available for the day
    /// @custom:reverts E When recipient already received a boon today
    /// @custom:reverts E When slot was already used today
    function issueDeityBoon(address deity, address recipient, uint8 slot) external {
        if (deity == address(0) || recipient == address(0)) revert E();
        if (deity == recipient) revert E();
        if (slot >= DEITY_DAILY_BOON_COUNT) revert E();
        if (deityPassPurchasedCount[deity] == 0) revert E();

        uint32 day = _simulatedDayIndex();
        if (rngWordByDay[day] == 0) revert E();
        if (deityBoonDay[deity] != day) {
            deityBoonDay[deity] = day;
            deityBoonUsedMask[deity] = 0;
        }
        if (deityBoonRecipientDay[recipient] == day) revert E();

        uint8 mask = deityBoonUsedMask[deity];
        uint8 slotMask = uint8(1) << slot;
        if ((mask & slotMask) != 0) revert E();
        deityBoonUsedMask[deity] = mask | slotMask;
        deityBoonRecipientDay[recipient] = day;

        bool decimatorAllowed = _isDecimatorWindow();
        bool deityPassAvailable = deityPassOwners.length < DEITY_PASS_MAX_TOTAL;
        uint8 boonType = _deityBoonForSlot(deity, day, slot, decimatorAllowed, deityPassAvailable);
        _applyBoon(recipient, boonType, day, day, 0, true);

        emit DeityBoonIssued(deity, recipient, day, slot, boonType);
    }

    // =========================================================================
    // Internal Helper Functions
    // =========================================================================

    /// @dev Roll a target level for lootbox resolution.
    ///      90% chance: 0-4 levels above base. 10% chance: 5-50 levels above base.
    ///      Bit budget (consumed from `seed`):
    ///        - rangeRoll: bits[0..15]   via uint16(seed)         % 100   (bias 0.05%)
    ///        - near-level offset: bits[16..23] via uint8(seed >> 16) % 5 (bias 0.39%)
    ///        - far-level offset:  bits[24..39] via uint16(seed >> 24) % 46 (bias 0.05%)
    /// @param baseLevel The base level to roll from
    /// @param seed Per-resolution 256-bit keccak seed (derived once at _resolveLootboxCommon entry)
    /// @return targetLevel The rolled target level
    function _rollTargetLevel(
        uint24 baseLevel,
        uint256 seed
    ) private pure returns (uint24 targetLevel) {
        uint256 rangeRoll = uint16(seed) % 100;
        if (rangeRoll < 10) {
            // 10% chance: far future (5-50 levels ahead)
            uint256 farOffset = uint16(seed >> 24) % 46;
            targetLevel = baseLevel + uint24(farOffset + 5);
        } else {
            // 90% chance: near future (0-4 levels ahead)
            uint256 nearOffset = uint8(seed >> 16) % 5;
            targetLevel = baseLevel + uint24(nearOffset);
        }
    }

    /// @dev Computes the lootbox value allocated to the boon/pass draw: a fixed BPS of
    ///      the resolution amount, capped at `LOOTBOX_BOON_MAX_BUDGET` and never exceeding
    ///      the amount itself.
    /// @param amount ETH-equivalent resolution amount
    /// @return boonBudget Amount allocated to the boon/pass draw
    function _lootboxBoonBudget(uint256 amount) private pure returns (uint256 boonBudget) {
        boonBudget = (amount * LOOTBOX_BOON_BUDGET_BPS) / 10_000;
        if (boonBudget > LOOTBOX_BOON_MAX_BUDGET) {
            boonBudget = LOOTBOX_BOON_MAX_BUDGET;
        }
        if (boonBudget > amount) {
            boonBudget = amount;
        }
    }

    /// @dev Accumulates the one or two `_resolveLootboxRoll` invocations for a lootbox
    ///      resolution into presale / non-presale BURNIE totals and a scaled future-ticket
    ///      count. The second invocation runs only when `amountSecond != 0` and uses a
    ///      counter-tagged seed chunk (`EntropyLib.hash2(seed, 1)`) so the two invocations'
    ///      bit-slice ranges are collision-free.
    /// @param player Player receiving rewards
    /// @param amountFirst First (or whole) main-amount chunk
    /// @param amountSecond Second main-amount chunk; zero when the lootbox is not split
    /// @param amount Full ETH-equivalent amount for reward calculations
    /// @param targetPrice Price for the resolved target level
    /// @param day Day index for events
    /// @param seed Per-resolution 256-bit keccak seed
    /// @return burniePresale BURNIE awarded subject to the presale multiplier
    /// @return burnieNoMultiplier BURNIE awarded without the presale multiplier
    /// @return futureTickets Scaled (× TICKET_SCALE) future-ticket count
    function _accumulateLootboxRolls(
        address player,
        uint256 amountFirst,
        uint256 amountSecond,
        uint256 amount,
        uint256 targetPrice,
        uint32 day,
        uint256 seed
    )
        private
        returns (
            uint256 burniePresale,
            uint256 burnieNoMultiplier,
            uint32 futureTickets
        )
    {
        (
            uint256 burnieOut,
            uint32 ticketsOut,
            bool applyPresaleMultiplier
        ) = _resolveLootboxRoll(player, amountFirst, amount, targetPrice, day, seed);

        if (burnieOut != 0) {
            if (applyPresaleMultiplier) {
                burniePresale += burnieOut;
            } else {
                burnieNoMultiplier += burnieOut;
            }
        }
        if (ticketsOut != 0) {
            futureTickets = ticketsOut;
        }

        if (amountSecond != 0) {
            uint256 seed2 = EntropyLib.hash2(seed, 1);
            (burnieOut, ticketsOut, applyPresaleMultiplier) =
                _resolveLootboxRoll(player, amountSecond, amount, targetPrice, day, seed2);

            if (burnieOut != 0) {
                if (applyPresaleMultiplier) {
                    burniePresale += burnieOut;
                } else {
                    burnieNoMultiplier += burnieOut;
                }
            }
            if (ticketsOut != 0) {
                futureTickets += ticketsOut;
            }
        }
    }

    /// @dev Common lootbox resolution logic shared by ETH and BURNIE lootboxes.
    ///      Handles whale pass jackpots, lazy pass awards, ticket/BURNIE rolls, and boons.
    /// @param player Player receiving rewards
    /// @param day Day index for events
    /// @param index Per-player storage index of the lootbox being opened. Used purely as
    ///        the `lootboxIndex` identifier on the manual `LootBoxOpened` emit; auto-resolve
    ///        callers pass `0`.
    /// @param amount ETH-equivalent amount for reward calculations
    /// @param targetLevel Target level for future tickets
    /// @param currentLevel Current game level
    /// @param seed Per-resolution 256-bit keccak seed (single-source-of-entropy threaded through all sub-rolls and bit-sliced per-consumer)
    /// @dev Single-keccak-per-resolution entropy: caller derives `seed` once at entry
    ///      via keccak256(abi.encode(rngWord, player, day, amount)); thread through
    ///      downstream sub-rolls. Bit allocation in primary chunk (`seed`):
    ///        bits[0..15]    rangeRoll % 100         (_rollTargetLevel)
    ///        bits[16..23]   near-offset % 5         (_rollTargetLevel)
    ///        bits[24..39]   far-offset % 46         (_rollTargetLevel)
    ///        bits[40..55]   pathRoll % 20           (_resolveLootboxRoll)
    ///        bits[56..79]   tierRoll % 1000         (_lootboxDgnrsReward sub-call)
    ///        bits[80..95]   varianceRoll % 20       (_resolveLootboxRoll large-BURNIE)
    ///        bits[96..119]  ticketVariance % 10000  (_lootboxTicketCount)
    ///        bits[120..151] boon roll % BOON_PPM_SCALE (_rollLootboxBoons)
    ///        bits[152..167] fracRoundUp % 100      (_resolveLootboxCommon ticket whole-collapse on both manual + auto-resolve paths; bias 0.10%)
    ///      Total primary-chunk consumption: 168 bits / 256 available (bits[152..167] consumed on both manual + auto-resolve paths).
    ///      ETH-amount-second branch uses seed2 = EntropyLib.hash2(seed, 1)
    ///      (counter-tagged chunk 1; collision-free vs primary chunk 0).
    /// @param presale Whether this is a presale lootbox (62% bonus BURNIE multiplier)
    /// @param allowPasses Whether pass-type boons are eligible: the whale-pass jackpot
    ///        award and the lazy-pass discount awards. `true` for the manual and
    ///        auto-resolve ETH/BURNIE callers (`openLootBox`, `resolveLootboxDirect`,
    ///        `resolveRedemptionLootbox`), `false` for `openBurnieLootBox`
    /// @param emitLootboxEvent Whether to emit the `LootBoxOpened` event; `true` for
    ///        `openLootBox`, `false` for `openBurnieLootBox` (which emits its own
    ///        `BurnieLootOpen`) and for both auto-resolve callers
    /// @param payColdBustConsolation Whether a ticket-path cold-bust (`whole == 0`) pays
    ///        the `LOOTBOX_WWXRP_CONSOLATION`; `true` for the manual callers
    ///        (`openLootBox`, `openBurnieLootBox`), `false` for the auto-resolve callers
    ///        (`resolveLootboxDirect`, `resolveRedemptionLootbox`), which stay silent on
    ///        cold-bust
    /// @param allowBoons Whether to roll for boons
    /// @param distressEth Portion of lootbox ETH bought during distress mode (pre-EV-scaling basis)
    /// @param totalPackedEth Total packed lootbox ETH (pre-EV-scaling basis, denominator for distress fraction)
    /// @return futureTickets Pre-Bernoulli scaled (× TICKET_SCALE) future ticket count
    /// @return burnieAmount Total BURNIE awarded
    /// @return roundedUp True iff the Bernoulli round-up incremented the awarded
    ///         whole-ticket count by 1
    function _resolveLootboxCommon(
        address player,
        uint32 day,
        uint48 index,
        uint256 amount,
        uint24 targetLevel,
        uint24 currentLevel,
        uint256 seed,
        bool presale,
        bool allowPasses,
        bool emitLootboxEvent,
        bool payColdBustConsolation,
        bool allowBoons,
        uint256 distressEth,
        uint256 totalPackedEth
    )
        private
        returns (
            uint32 futureTickets,
            uint256 burnieAmount,
            bool roundedUp
        )
    {
        if (targetLevel < currentLevel) {
            targetLevel = currentLevel;
        }
        uint256 targetPrice = PriceLookupLib.priceForLevel(targetLevel);
        if (targetPrice == 0) revert E();

        uint256 amountFirst;
        uint256 amountSecond;
        {
            uint256 mainAmount = amount - _lootboxBoonBudget(amount);
            amountFirst = mainAmount;
            if (mainAmount > LOOTBOX_SPLIT_THRESHOLD) {
                amountFirst = mainAmount / 2;
                amountSecond = mainAmount - amountFirst;
            }
        }

        (
            uint256 burniePresale,
            uint256 burnieNoMultiplier,
            uint32 rolledTickets
        ) = _accumulateLootboxRolls(
            player,
            amountFirst,
            amountSecond,
            amount,
            targetPrice,
            day,
            seed
        );
        futureTickets = rolledTickets;

        burnieAmount = burnieNoMultiplier + burniePresale;
        if (presale && burniePresale != 0) {
            uint256 bonusBurnie = (burniePresale * LOOTBOX_PRESALE_BURNIE_BONUS_BPS) / 10_000;
            burnieAmount += bonusBurnie;
        }
        // Floored to whole-BURNIE (1 BURNIE = 1 ether); sub-1-BURNIE residue
        // evaporates. The floored value reaches the `creditFlip` arg, the
        // `LootBoxOpened.burnie` event field, and the return tuple.
        burnieAmount = (burnieAmount / 1 ether) * 1 ether;

        if (allowBoons) {
            _rollLootboxBoons(
                player,
                day,
                amount,
                _lootboxBoonBudget(amount),
                seed,
                allowPasses
            );
            // Nested delegatecall to BoonModule for activity boon consumption
            (bool okAct, ) = ContractAddresses.GAME_BOON_MODULE.delegatecall(
                abi.encodeWithSelector(IDegenerusGameBoonModule.consumeActivityBoon.selector, player)
            );
            if (!okAct) revert E();
        }

        if (futureTickets != 0) {
            // Distress-mode ticket bonus: 25% extra on the fraction bought during distress
            if (distressEth != 0 && totalPackedEth != 0) {
                uint256 bonus = (uint256(futureTickets) * distressEth * DISTRESS_TICKET_BONUS_BPS)
                    / (totalPackedEth * 10_000);
                if (bonus != 0) {
                    uint256 boosted = uint256(futureTickets) + bonus;
                    futureTickets = uint32(boosted);
                }
            }
            // Collapse scaled tickets to whole via a single Bernoulli round-up on
            // bits[152..167] of the per-resolution seed. Function-scope
            // `futureTickets` stays at the scaled value (consumed by the
            // `LootBoxOpened` emit below and returned to `openBurnieLootBox` as
            // `BurnieLootOpen.tickets`). The local `whole` carries the post-collapse
            // value into `_queueTickets`.
            uint32 whole = futureTickets / uint32(TICKET_SCALE);
            uint32 frac = futureTickets % uint32(TICKET_SCALE);
            if (frac != 0 && (uint16(seed >> 152) % uint16(TICKET_SCALE)) < uint16(frac)) {
                unchecked { whole += 1; }
                roundedUp = true;
            }
            // `_queueTickets` early-returns on `whole == 0`, so the cold-bust case
            // queues nothing. The manual callers (`openLootBox`, `openBurnieLootBox`)
            // pass `payColdBustConsolation = true` and pay the WWXRP consolation here;
            // the auto-resolve callers pass `false` and stay silent on cold-bust.
            _queueTickets(player, targetLevel, whole, false);
            if (payColdBustConsolation && whole == 0) {
                // Manual cold-bust: pay the LOOTBOX_WWXRP_CONSOLATION via the same
                // `mintPrize` interface used by the regular 10%-path WWXRP win.
                // Observable off-chain via the WWXRP ERC-20 `Transfer` event
                // (`0x0` -> player) together with same-tx context: a consolation
                // carries no same-tx ticket-path emission, unlike a regular win.
                wwxrp.mintPrize(player, LOOTBOX_WWXRP_CONSOLATION);
            }
        }

        if (burnieAmount != 0) {
            coinflip.creditFlip(player, burnieAmount);
        }

        if (emitLootboxEvent) {
            emit LootBoxOpened(
                player,
                index,
                day,
                amount,
                targetLevel,
                futureTickets,
                burnieAmount,
                roundedUp
            );
        }
        return (futureTickets, burnieAmount, roundedUp);
    }

    /// @dev Roll for lootbox boons. Lootbox can award at most one boon.
    ///      If a boon is already active, only refresh or upgrade that same category.
    ///      Uses a single roll with granular ppm-based probability and deity-weighted pool.
    ///      Bit budget (consumed from `seed`):
    ///        - boon roll: bits[120..151] via uint32(seed >> 120) % BOON_PPM_SCALE (bias 0.022%; BOON_PPM_SCALE = 1_000_000)
    /// @param player Player address
    /// @param day Current day index
    /// @param originalAmount Amount used for chance calculations
    /// @param boonBudget Amount of lootbox value allocated to boon/pass draw
    /// @param seed Per-resolution 256-bit keccak seed (sliced inline; no advance)
    /// @param allowPasses Whether pass-type boons are eligible: the whale-pass jackpot
    ///        award and the lazy-pass discount awards
    function _rollLootboxBoons(
        address player,
        uint32 day,
        uint256 originalAmount,
        uint256 boonBudget,
        uint256 seed,
        bool allowPasses
    ) private {
        if (player == address(0) || originalAmount == 0) return;

        // Nested delegatecall to BoonModule for expired boon cleanup
        (bool okClr, ) = ContractAddresses.GAME_BOON_MODULE.delegatecall(
            abi.encodeWithSelector(IDegenerusGameBoonModule.checkAndClearExpiredBoon.selector, player)
        );
        if (!okClr) revert E();

        uint32 currentDay = _simulatedDayIndex();
        uint24 currentLevel = level + 1;

        uint24 lazyPassLevel = currentLevel == 0 ? 1 : currentLevel + 1;
        uint256 lazyPassValue = allowPasses ? _lazyPassPriceForLevel(lazyPassLevel) : 0;

        bool decimatorAllowed = _isDecimatorWindow();
        bool deityEligible =
            (mintPacked_[player] >> BitPackingLib.HAS_DEITY_PASS_SHIFT & 1 == 0 && deityPassOwners.length < DEITY_PASS_MAX_TOTAL);

        (uint256 totalWeight, uint256 avgMaxValue) = _boonPoolStats(
            decimatorAllowed,
            deityEligible,
            allowPasses,
            lazyPassValue
        );
        if (totalWeight == 0 || avgMaxValue == 0) return;

        uint256 expectedPerBoon = (avgMaxValue * LOOTBOX_BOON_UTILIZATION_BPS) / 10_000;
        if (expectedPerBoon == 0) return;

        if (boonBudget == 0) return;

        uint256 totalChance = (boonBudget * BOON_PPM_SCALE) / expectedPerBoon;
        if (totalChance > BOON_PPM_SCALE) totalChance = BOON_PPM_SCALE;
        if (totalChance == 0) return;

        uint256 roll = uint32(seed >> 120) % BOON_PPM_SCALE;
        if (roll >= totalChance) return;

        uint8 boonType = _boonFromRoll(
            (roll * totalWeight) / totalChance,
            decimatorAllowed,
            deityEligible,
            allowPasses
        );

        _applyBoon(player, boonType, day, currentDay, originalAmount, false);
    }

    /// @dev Convert BURNIE amount to ETH value using current price.
    function _burnieToEthValue(
        uint256 burnieAmount,
        uint256 priceWei
    ) private pure returns (uint256 valueWei) {
        if (burnieAmount == 0 || priceWei == 0) return 0;
        valueWei = (burnieAmount * priceWei) / PRICE_COIN_UNIT;
    }

    /// @dev Activate a 100-level whale pass for a player.
    ///      Applies the same mint/streak bonuses as a whale bundle purchase.
    /// @return ticketStartLevel The first level tickets are queued for.
    function _activateWhalePass(
        address player
    ) private returns (uint24 ticketStartLevel) {
        uint24 passLevel = level + 1;

        ticketStartLevel = passLevel;

        _applyWhalePassStats(player, ticketStartLevel);

        // Queue tickets: 40/lvl for bonus levels (passLevel to 10), 2/lvl for the rest
        for (uint24 i = 0; i < 100; ) {
            uint24 lvl = ticketStartLevel + i;
            bool isBonus = (lvl >= passLevel && lvl <= WHALE_PASS_BONUS_END_LEVEL);
            _queueTickets(
                player,
                lvl,
                isBonus ? WHALE_PASS_BONUS_TICKETS_PER_LEVEL : WHALE_PASS_TICKETS_PER_LEVEL,
                false
            );
            unchecked { ++i; }
        }
    }

    /// @dev Calculate total weight and average max boon value (in ETH) for EV budgeting.
    ///      `allowPasses` gates both pass-type boons — the whale-pass jackpot and the
    ///      lazy-pass discount awards.
    function _boonPoolStats(
        bool decimatorAllowed,
        bool deityEligible,
        bool allowPasses,
        uint256 lazyPassValue
    ) private view returns (uint256 totalWeight, uint256 avgMaxValue) {
        uint256 weightedMax = 0;
        uint256 priceWei = PriceLookupLib.priceForLevel(level);

        // Coinflip boons (max bonus on 100k BURNIE deposit)
        uint256 coinflipMax5 = _burnieToEthValue(
            (COINFLIP_BOON_MAX_DEPOSIT * LOOTBOX_BOON_BONUS_BPS) / 10_000,
            priceWei
        );
        uint256 coinflipMax10 = _burnieToEthValue(
            (COINFLIP_BOON_MAX_DEPOSIT * LOOTBOX_COINFLIP_10_BONUS_BPS) / 10_000,
            priceWei
        );
        uint256 coinflipMax25 = _burnieToEthValue(
            (COINFLIP_BOON_MAX_DEPOSIT * LOOTBOX_COINFLIP_25_BONUS_BPS) / 10_000,
            priceWei
        );

        totalWeight += BOON_WEIGHT_COINFLIP_5;
        weightedMax += BOON_WEIGHT_COINFLIP_5 * coinflipMax5;
        totalWeight += BOON_WEIGHT_COINFLIP_10;
        weightedMax += BOON_WEIGHT_COINFLIP_10 * coinflipMax10;
        totalWeight += BOON_WEIGHT_COINFLIP_25;
        weightedMax += BOON_WEIGHT_COINFLIP_25 * coinflipMax25;

        // Lootbox boost boons (max 10 ETH)
        uint256 boostCap = 10 ether;
        uint256 lootboxMax5 = (boostCap * LOOTBOX_BOOST_5_BONUS_BPS) / 10_000;
        uint256 lootboxMax15 = (boostCap * LOOTBOX_BOOST_15_BONUS_BPS) / 10_000;
        uint256 lootboxMax25 = (boostCap * LOOTBOX_BOOST_25_BONUS_BPS) / 10_000;

        totalWeight += BOON_WEIGHT_LOOTBOX_5;
        weightedMax += BOON_WEIGHT_LOOTBOX_5 * lootboxMax5;
        totalWeight += BOON_WEIGHT_LOOTBOX_15;
        weightedMax += BOON_WEIGHT_LOOTBOX_15 * lootboxMax15;
        totalWeight += BOON_WEIGHT_LOOTBOX_25;
        weightedMax += BOON_WEIGHT_LOOTBOX_25 * lootboxMax25;

        // Purchase boost boons (max 10 ETH)
        uint256 purchaseMax5 = (boostCap * LOOTBOX_PURCHASE_BOOST_5_BONUS_BPS) / 10_000;
        uint256 purchaseMax15 = (boostCap * LOOTBOX_PURCHASE_BOOST_15_BONUS_BPS) / 10_000;
        uint256 purchaseMax25 = (boostCap * LOOTBOX_PURCHASE_BOOST_25_BONUS_BPS) / 10_000;

        totalWeight += BOON_WEIGHT_PURCHASE_5;
        weightedMax += BOON_WEIGHT_PURCHASE_5 * purchaseMax5;
        totalWeight += BOON_WEIGHT_PURCHASE_15;
        weightedMax += BOON_WEIGHT_PURCHASE_15 * purchaseMax15;
        totalWeight += BOON_WEIGHT_PURCHASE_25;
        weightedMax += BOON_WEIGHT_PURCHASE_25 * purchaseMax25;

        if (decimatorAllowed) {
            uint256 decMax10 = _burnieToEthValue(
                (DECIMATOR_BOON_CAP * LOOTBOX_DECIMATOR_10_BONUS_BPS) / 10_000,
                priceWei
            );
            uint256 decMax25 = _burnieToEthValue(
                (DECIMATOR_BOON_CAP * LOOTBOX_DECIMATOR_25_BONUS_BPS) / 10_000,
                priceWei
            );
            uint256 decMax50 = _burnieToEthValue(
                (DECIMATOR_BOON_CAP * LOOTBOX_DECIMATOR_50_BONUS_BPS) / 10_000,
                priceWei
            );
            totalWeight += BOON_WEIGHT_DECIMATOR_10;
            weightedMax += BOON_WEIGHT_DECIMATOR_10 * decMax10;
            totalWeight += BOON_WEIGHT_DECIMATOR_25;
            weightedMax += BOON_WEIGHT_DECIMATOR_25 * decMax25;
            totalWeight += BOON_WEIGHT_DECIMATOR_50;
            weightedMax += BOON_WEIGHT_DECIMATOR_50 * decMax50;
        }

        // Whale discount boons (10/25/50% off standard price)
        uint256 whaleMax10 = (WHALE_BUNDLE_STANDARD_PRICE * LOOTBOX_WHALE_BOON_DISCOUNT_10_BPS) / 10_000;
        uint256 whaleMax25 = (WHALE_BUNDLE_STANDARD_PRICE * LOOTBOX_WHALE_BOON_DISCOUNT_25_BPS) / 10_000;
        uint256 whaleMax50 = (WHALE_BUNDLE_STANDARD_PRICE * LOOTBOX_WHALE_BOON_DISCOUNT_50_BPS) / 10_000;
        totalWeight += BOON_WEIGHT_WHALE_10;
        weightedMax += BOON_WEIGHT_WHALE_10 * whaleMax10;
        totalWeight += BOON_WEIGHT_WHALE_25;
        weightedMax += BOON_WEIGHT_WHALE_25 * whaleMax25;
        totalWeight += BOON_WEIGHT_WHALE_50;
        weightedMax += BOON_WEIGHT_WHALE_50 * whaleMax50;

        // Deity pass discount boons (if eligible)
        if (deityEligible) {
            uint256 k = deityPassOwners.length;
            uint256 deityPrice = DEITY_PASS_BASE + (k * (k + 1) * 1 ether) / 2;
            uint256 deityMax10 = (deityPrice * 1000) / 10_000;
            uint256 deityMax25 = (deityPrice * 2500) / 10_000;
            uint256 deityMax50 = (deityPrice * 5000) / 10_000;
            totalWeight += BOON_WEIGHT_DEITY_PASS_10;
            weightedMax += BOON_WEIGHT_DEITY_PASS_10 * deityMax10;
            totalWeight += BOON_WEIGHT_DEITY_PASS_25;
            weightedMax += BOON_WEIGHT_DEITY_PASS_25 * deityMax25;
            totalWeight += BOON_WEIGHT_DEITY_PASS_50;
            weightedMax += BOON_WEIGHT_DEITY_PASS_50 * deityMax50;
        }

        // Activity boons (value assumed 0 for EV budgeting)
        totalWeight += BOON_WEIGHT_ACTIVITY_10;
        totalWeight += BOON_WEIGHT_ACTIVITY_25;
        totalWeight += BOON_WEIGHT_ACTIVITY_50;

        // Pass awards (lootbox-only unless enabled)
        if (allowPasses) {
            totalWeight += BOON_WEIGHT_WHALE_PASS;
            weightedMax += BOON_WEIGHT_WHALE_PASS * LOOTBOX_WHALE_PASS_PRICE;
        }
        if (allowPasses && lazyPassValue != 0) {
            uint256 lpMax10 = (lazyPassValue * LOOTBOX_LAZY_PASS_DISCOUNT_10_BPS) / 10_000;
            uint256 lpMax25 = (lazyPassValue * LOOTBOX_LAZY_PASS_DISCOUNT_25_BPS) / 10_000;
            uint256 lpMax50 = (lazyPassValue * LOOTBOX_LAZY_PASS_DISCOUNT_50_BPS) / 10_000;
            totalWeight += BOON_WEIGHT_LAZY_PASS_10;
            weightedMax += BOON_WEIGHT_LAZY_PASS_10 * lpMax10;
            totalWeight += BOON_WEIGHT_LAZY_PASS_25;
            weightedMax += BOON_WEIGHT_LAZY_PASS_25 * lpMax25;
            totalWeight += BOON_WEIGHT_LAZY_PASS_50;
            weightedMax += BOON_WEIGHT_LAZY_PASS_50 * lpMax50;
        }

        if (totalWeight == 0) return (0, 0);
        avgMaxValue = weightedMax / totalWeight;
    }

    /// @dev Convert a weighted roll into a lootbox boon type with eligibility filters.
    ///      `allowPasses` gates both pass-type boons — the whale-pass jackpot and the
    ///      lazy-pass discount awards.
    function _boonFromRoll(
        uint256 roll,
        bool decimatorAllowed,
        bool deityEligible,
        bool allowPasses
    ) private pure returns (uint8 boonType) {
        uint256 cursor = 0;
        cursor += BOON_WEIGHT_COINFLIP_5;
        if (roll < cursor) return BOON_COINFLIP_5;
        cursor += BOON_WEIGHT_COINFLIP_10;
        if (roll < cursor) return BOON_COINFLIP_10;
        cursor += BOON_WEIGHT_COINFLIP_25;
        if (roll < cursor) return BOON_COINFLIP_25;
        cursor += BOON_WEIGHT_LOOTBOX_5;
        if (roll < cursor) return BOON_LOOTBOX_5;
        cursor += BOON_WEIGHT_LOOTBOX_15;
        if (roll < cursor) return BOON_LOOTBOX_15;
        cursor += BOON_WEIGHT_LOOTBOX_25;
        if (roll < cursor) return BOON_LOOTBOX_25;
        cursor += BOON_WEIGHT_PURCHASE_5;
        if (roll < cursor) return BOON_PURCHASE_5;
        cursor += BOON_WEIGHT_PURCHASE_15;
        if (roll < cursor) return BOON_PURCHASE_15;
        cursor += BOON_WEIGHT_PURCHASE_25;
        if (roll < cursor) return BOON_PURCHASE_25;
        if (decimatorAllowed) {
            cursor += BOON_WEIGHT_DECIMATOR_10;
            if (roll < cursor) return BOON_DECIMATOR_10;
            cursor += BOON_WEIGHT_DECIMATOR_25;
            if (roll < cursor) return BOON_DECIMATOR_25;
            cursor += BOON_WEIGHT_DECIMATOR_50;
            if (roll < cursor) return BOON_DECIMATOR_50;
        }
        cursor += BOON_WEIGHT_WHALE_10;
        if (roll < cursor) return BOON_WHALE_10;
        cursor += BOON_WEIGHT_WHALE_25;
        if (roll < cursor) return BOON_WHALE_25;
        cursor += BOON_WEIGHT_WHALE_50;
        if (roll < cursor) return BOON_WHALE_50;
        if (deityEligible) {
            cursor += BOON_WEIGHT_DEITY_PASS_10;
            if (roll < cursor) return BOON_DEITY_PASS_10;
            cursor += BOON_WEIGHT_DEITY_PASS_25;
            if (roll < cursor) return BOON_DEITY_PASS_25;
            cursor += BOON_WEIGHT_DEITY_PASS_50;
            if (roll < cursor) return BOON_DEITY_PASS_50;
        }
        cursor += BOON_WEIGHT_ACTIVITY_10;
        if (roll < cursor) return BOON_ACTIVITY_10;
        cursor += BOON_WEIGHT_ACTIVITY_25;
        if (roll < cursor) return BOON_ACTIVITY_25;
        cursor += BOON_WEIGHT_ACTIVITY_50;
        if (roll < cursor) return BOON_ACTIVITY_50;
        if (allowPasses) {
            cursor += BOON_WEIGHT_WHALE_PASS;
            if (roll < cursor) return BOON_WHALE_PASS;
            cursor += BOON_WEIGHT_LAZY_PASS_10;
            if (roll < cursor) return BOON_LAZY_PASS_10;
            cursor += BOON_WEIGHT_LAZY_PASS_25;
            if (roll < cursor) return BOON_LAZY_PASS_25;
            cursor += BOON_WEIGHT_LAZY_PASS_50;
            if (roll < cursor) return BOON_LAZY_PASS_50;
        }
    }

    /// @dev Apply a boon to a player. Handles both lootbox-sourced and deity-sourced boons.
    ///      Both sources use upgrade semantics (only if higher tier/amount).
    ///      Lootbox boons: emit events, deity day = 0.
    ///      Deity boons: no events, deity day = day.
    ///      All boon state is stored in boonPacked[player] (2-slot packed struct).
    ///      Players can hold one boon per category simultaneously (up to 9 categories).
    ///      Isolated bit fields per category -- applying a boon in one category cannot
    ///      affect another category's bits (targeted bitmask operations: & ~mask | value).
    function _applyBoon(
        address player,
        uint8 boonType,
        uint32 day,
        uint32 currentDay,
        uint256 originalAmount,
        bool isDeity
    ) private {
        // Coinflip boons (types 1-3) — slot0
        if (boonType <= BOON_COINFLIP_25) {
            uint16 bps = boonType == BOON_COINFLIP_25
                ? LOOTBOX_COINFLIP_25_BONUS_BPS
                : (boonType == BOON_COINFLIP_10 ? LOOTBOX_COINFLIP_10_BONUS_BPS : LOOTBOX_BOON_BONUS_BPS);
            BoonPacked storage bp = boonPacked[player];
            uint256 s0 = bp.slot0;
            uint8 newTier = _coinflipBpsToTier(bps);
            uint8 existingTier = uint8(s0 >> BP_COINFLIP_TIER_SHIFT);
            if (newTier > existingTier) {
                s0 = (s0 & ~(uint256(BP_MASK_8) << BP_COINFLIP_TIER_SHIFT)) | (uint256(newTier) << BP_COINFLIP_TIER_SHIFT);
            }
            // Set coinflipDay = currentDay
            s0 = (s0 & ~(uint256(BP_MASK_24) << BP_COINFLIP_DAY_SHIFT)) | (uint256(uint24(currentDay)) << BP_COINFLIP_DAY_SHIFT);
            // Set deityCoinflipDay = isDeity ? day : 0
            uint24 deityDayVal = isDeity ? uint24(day) : uint24(0);
            s0 = (s0 & ~(uint256(BP_MASK_24) << BP_DEITY_COINFLIP_DAY_SHIFT)) | (uint256(deityDayVal) << BP_DEITY_COINFLIP_DAY_SHIFT);
            bp.slot0 = s0;
            if (!isDeity) emit LootBoxReward(player, day, 2, originalAmount, LOOTBOX_BOON_MAX_BONUS);
            return;
        }

        // Lootbox boost boons (types 5, 6, 22) — slot0, single tier field (BOON-05)
        if (boonType == BOON_LOOTBOX_5 || boonType == BOON_LOOTBOX_15 || boonType == BOON_LOOTBOX_25) {
            uint8 newTier = boonType == BOON_LOOTBOX_25 ? uint8(3) :
                            (boonType == BOON_LOOTBOX_15 ? uint8(2) : uint8(1));
            BoonPacked storage bp = boonPacked[player];
            uint256 s0 = bp.slot0;
            uint8 existingTier = uint8(s0 >> BP_LOOTBOX_TIER_SHIFT);
            // Both deity and lootbox: upgrade semantics — keep higher tier
            uint8 activeTier = newTier > existingTier ? newTier : existingTier;
            // Clear lootbox fields, set new values
            s0 = s0 & BP_LOOTBOX_CLEAR;
            s0 = s0 | (uint256(uint24(currentDay)) << BP_LOOTBOX_DAY_SHIFT);
            uint24 deityDayVal = isDeity ? uint24(day) : uint24(0);
            s0 = s0 | (uint256(deityDayVal) << BP_DEITY_LOOTBOX_DAY_SHIFT);
            s0 = s0 | (uint256(activeTier) << BP_LOOTBOX_TIER_SHIFT);
            bp.slot0 = s0;
            if (!isDeity) {
                // Map active tier back to BPS and rewardType for event
                uint16 activeBps = _lootboxTierToBps(activeTier);
                uint8 rewardType = activeTier == 3 ? 6 : (activeTier == 2 ? 5 : 4);
                emit LootBoxReward(player, day, rewardType, originalAmount, activeBps);
            }
            return;
        }

        // Purchase boost boons (types 7, 8, 9) — slot0
        if (boonType == BOON_PURCHASE_5 || boonType == BOON_PURCHASE_15 || boonType == BOON_PURCHASE_25) {
            uint16 bps = boonType == BOON_PURCHASE_25
                ? LOOTBOX_PURCHASE_BOOST_25_BONUS_BPS
                : (boonType == BOON_PURCHASE_15 ? LOOTBOX_PURCHASE_BOOST_15_BONUS_BPS : LOOTBOX_PURCHASE_BOOST_5_BONUS_BPS);
            BoonPacked storage bp = boonPacked[player];
            uint256 s0 = bp.slot0;
            uint8 newTier = _purchaseBpsToTier(bps);
            uint8 existingTier = uint8(s0 >> BP_PURCHASE_TIER_SHIFT);
            if (newTier > existingTier) {
                s0 = (s0 & ~(uint256(BP_MASK_8) << BP_PURCHASE_TIER_SHIFT)) | (uint256(newTier) << BP_PURCHASE_TIER_SHIFT);
            }
            // Set purchaseDay = currentDay
            s0 = (s0 & ~(uint256(BP_MASK_24) << BP_PURCHASE_DAY_SHIFT)) | (uint256(uint24(currentDay)) << BP_PURCHASE_DAY_SHIFT);
            // Set deityPurchaseDay
            uint24 deityDayVal = isDeity ? uint24(day) : uint24(0);
            s0 = (s0 & ~(uint256(BP_MASK_24) << BP_DEITY_PURCHASE_DAY_SHIFT)) | (uint256(deityDayVal) << BP_DEITY_PURCHASE_DAY_SHIFT);
            bp.slot0 = s0;
            if (!isDeity) {
                uint8 rewardType = bps == LOOTBOX_PURCHASE_BOOST_25_BONUS_BPS
                    ? 6 : (bps == LOOTBOX_PURCHASE_BOOST_15_BONUS_BPS ? 5 : 4);
                emit LootBoxReward(player, day, rewardType, originalAmount, bps);
            }
            return;
        }

        // Decimator boost boons (types 13, 14, 15) — slot0 (no award day, only tier + deity day)
        if (boonType == BOON_DECIMATOR_10 || boonType == BOON_DECIMATOR_25 || boonType == BOON_DECIMATOR_50) {
            uint16 bps = boonType == BOON_DECIMATOR_50
                ? LOOTBOX_DECIMATOR_50_BONUS_BPS
                : (boonType == BOON_DECIMATOR_25 ? LOOTBOX_DECIMATOR_25_BONUS_BPS : LOOTBOX_DECIMATOR_10_BONUS_BPS);
            BoonPacked storage bp = boonPacked[player];
            uint256 s0 = bp.slot0;
            uint8 newTier = _decimatorBpsToTier(bps);
            uint8 existingTier = uint8(s0 >> BP_DECIMATOR_TIER_SHIFT);
            if (newTier > existingTier) {
                s0 = (s0 & ~(uint256(BP_MASK_8) << BP_DECIMATOR_TIER_SHIFT)) | (uint256(newTier) << BP_DECIMATOR_TIER_SHIFT);
            }
            // Set deityDecimatorDay (no award day for decimator)
            uint24 deityDayVal = isDeity ? uint24(day) : uint24(0);
            s0 = (s0 & ~(uint256(BP_MASK_24) << BP_DEITY_DECIMATOR_DAY_SHIFT)) | (uint256(deityDayVal) << BP_DEITY_DECIMATOR_DAY_SHIFT);
            bp.slot0 = s0;
            if (!isDeity) emit LootBoxReward(player, day, 8, originalAmount, bps);
            return;
        }

        // Whale discount boons (types 16, 23, 24) — slot0
        if (boonType == BOON_WHALE_10 || boonType == BOON_WHALE_25 || boonType == BOON_WHALE_50) {
            uint16 bps = boonType == BOON_WHALE_50
                ? LOOTBOX_WHALE_BOON_DISCOUNT_50_BPS
                : (boonType == BOON_WHALE_25 ? LOOTBOX_WHALE_BOON_DISCOUNT_25_BPS : LOOTBOX_WHALE_BOON_DISCOUNT_10_BPS);
            BoonPacked storage bp = boonPacked[player];
            uint256 s0 = bp.slot0;
            uint8 newTier = _whaleBpsToTier(bps);
            uint8 existingTier = uint8(s0 >> BP_WHALE_TIER_SHIFT);
            if (newTier > existingTier) {
                s0 = (s0 & ~(uint256(BP_MASK_8) << BP_WHALE_TIER_SHIFT)) | (uint256(newTier) << BP_WHALE_TIER_SHIFT);
            }
            // whaleDay = isDeity ? day : currentDay (matching original behavior)
            uint24 whaleDayVal = isDeity ? uint24(day) : uint24(currentDay);
            s0 = (s0 & ~(uint256(BP_MASK_24) << BP_WHALE_DAY_SHIFT)) | (uint256(whaleDayVal) << BP_WHALE_DAY_SHIFT);
            // deityWhaleDay = isDeity ? day : 0
            uint24 deityDayVal = isDeity ? uint24(day) : uint24(0);
            s0 = (s0 & ~(uint256(BP_MASK_24) << BP_DEITY_WHALE_DAY_SHIFT)) | (uint256(deityDayVal) << BP_DEITY_WHALE_DAY_SHIFT);
            bp.slot0 = s0;
            if (!isDeity) emit LootBoxReward(player, day, 9, originalAmount, bps);
            return;
        }

        // Activity boons (types 17, 18, 19) — slot1
        if (boonType == BOON_ACTIVITY_10 || boonType == BOON_ACTIVITY_25 || boonType == BOON_ACTIVITY_50) {
            uint24 amt = boonType == BOON_ACTIVITY_50
                ? LOOTBOX_ACTIVITY_BOON_50_BONUS
                : (boonType == BOON_ACTIVITY_25 ? LOOTBOX_ACTIVITY_BOON_25_BONUS : LOOTBOX_ACTIVITY_BOON_10_BONUS);
            BoonPacked storage bp = boonPacked[player];
            uint256 s1 = bp.slot1;
            uint24 existingAmt = uint24(s1 >> BP_ACTIVITY_PENDING_SHIFT);
            if (amt > existingAmt) {
                s1 = (s1 & ~(uint256(BP_MASK_24) << BP_ACTIVITY_PENDING_SHIFT)) | (uint256(amt) << BP_ACTIVITY_PENDING_SHIFT);
            }
            // Set activityDay = currentDay
            s1 = (s1 & ~(uint256(BP_MASK_24) << BP_ACTIVITY_DAY_SHIFT)) | (uint256(uint24(currentDay)) << BP_ACTIVITY_DAY_SHIFT);
            // Set deityActivityDay
            uint24 deityDayVal = isDeity ? uint24(day) : uint24(0);
            s1 = (s1 & ~(uint256(BP_MASK_24) << BP_DEITY_ACTIVITY_DAY_SHIFT)) | (uint256(deityDayVal) << BP_DEITY_ACTIVITY_DAY_SHIFT);
            bp.slot1 = s1;
            if (!isDeity) emit LootBoxReward(player, day, 10, originalAmount, amt);
            return;
        }

        // Deity pass discount boons (types 25, 26, 27) — slot1
        if (boonType == BOON_DEITY_PASS_10 || boonType == BOON_DEITY_PASS_25 || boonType == BOON_DEITY_PASS_50) {
            uint8 tier = boonType == BOON_DEITY_PASS_50
                ? DEITY_PASS_BOON_TIER_50
                : (boonType == BOON_DEITY_PASS_25 ? DEITY_PASS_BOON_TIER_25 : DEITY_PASS_BOON_TIER_10);
            BoonPacked storage bp = boonPacked[player];
            uint256 s1 = bp.slot1;
            uint8 existingTier = uint8(s1 >> BP_DEITY_PASS_TIER_SHIFT);
            if (tier > existingTier) {
                s1 = (s1 & ~(uint256(BP_MASK_8) << BP_DEITY_PASS_TIER_SHIFT)) | (uint256(tier) << BP_DEITY_PASS_TIER_SHIFT);
            }
            // Set deityPassDay = currentDay
            s1 = (s1 & ~(uint256(BP_MASK_24) << BP_DEITY_PASS_DAY_SHIFT)) | (uint256(uint24(currentDay)) << BP_DEITY_PASS_DAY_SHIFT);
            // Set deityDeityPassDay
            uint24 deityDayVal = isDeity ? uint24(day) : uint24(0);
            s1 = (s1 & ~(uint256(BP_MASK_24) << BP_DEITY_DEITY_PASS_DAY_SHIFT)) | (uint256(deityDayVal) << BP_DEITY_DEITY_PASS_DAY_SHIFT);
            bp.slot1 = s1;
            if (!isDeity) {
                uint16 bps = tier == DEITY_PASS_BOON_TIER_50 ? 5000 : (tier == DEITY_PASS_BOON_TIER_25 ? 2500 : 1000);
                emit LootBoxReward(player, day, 10, originalAmount, bps);
            }
            return;
        }

        // Whale pass (type 28) — no boon mapping access, delegates to _activateWhalePass
        if (boonType == BOON_WHALE_PASS) {
            uint24 startLevel = _activateWhalePass(player);
            if (!isDeity) {
                emit LootBoxWhalePassJackpot(player, day, originalAmount, startLevel, WHALE_PASS_TICKETS_PER_LEVEL, 0, 0);
            }
            return;
        }

        // Lazy pass discount boons (types 29, 30, 31) — slot1
        if (boonType == BOON_LAZY_PASS_10 || boonType == BOON_LAZY_PASS_25 || boonType == BOON_LAZY_PASS_50) {
            uint16 bps = boonType == BOON_LAZY_PASS_50
                ? LOOTBOX_LAZY_PASS_DISCOUNT_50_BPS
                : (boonType == BOON_LAZY_PASS_25 ? LOOTBOX_LAZY_PASS_DISCOUNT_25_BPS : LOOTBOX_LAZY_PASS_DISCOUNT_10_BPS);
            BoonPacked storage bp = boonPacked[player];
            uint256 s1 = bp.slot1;
            uint8 newTier = _lazyPassBpsToTier(bps);
            uint8 existingTier = uint8(s1 >> BP_LAZY_PASS_TIER_SHIFT);
            if (newTier > existingTier) {
                s1 = (s1 & ~(uint256(BP_MASK_8) << BP_LAZY_PASS_TIER_SHIFT)) | (uint256(newTier) << BP_LAZY_PASS_TIER_SHIFT);
            }
            // lazyPassDay = isDeity ? day : currentDay (matching original behavior)
            uint24 lazyDayVal = isDeity ? uint24(day) : uint24(currentDay);
            s1 = (s1 & ~(uint256(BP_MASK_24) << BP_LAZY_PASS_DAY_SHIFT)) | (uint256(lazyDayVal) << BP_LAZY_PASS_DAY_SHIFT);
            // deityLazyPassDay = isDeity ? day : 0
            uint24 deityDayVal = isDeity ? uint24(day) : uint24(0);
            s1 = (s1 & ~(uint256(BP_MASK_24) << BP_DEITY_LAZY_PASS_DAY_SHIFT)) | (uint256(deityDayVal) << BP_DEITY_LAZY_PASS_DAY_SHIFT);
            bp.slot1 = s1;
            if (!isDeity) emit LootBoxReward(player, day, 11, originalAmount, bps);
        }
    }

    /// @dev Resolve a single lootbox roll to determine reward type.
    ///      55% tickets, 10% DGNRS, 10% WWXRP, 25% BURNIE.
    /// @param player Player receiving the reward
    /// @param amount Amount for this roll (may be half of total for split lootboxes)
    /// @param lootboxAmount Total lootbox amount (for events)
    /// @param targetPrice Price at target level
    /// @param day Current day index
    /// @param seed Per-resolution 256-bit keccak seed (sliced inline; first invocation uses primary chunk, ETH-amount-second branch uses seed2 = EntropyLib.hash2(seed, 1))
    /// @return burnieOut BURNIE tokens to award
    /// @return ticketsOut Tickets to queue for future level
    /// @return applyPresaleMultiplier Whether BURNIE should get presale multiplier
    /// @dev Bit budget (consumed from `seed`):
    ///        - pathRoll: bits[40..55]     via uint16(seed >> 40) % 20  (bias 0.02%)
    ///        - DGNRS tier sub-call slice: bits[56..79] (consumed by _lootboxDgnrsReward)
    ///        - large-BURNIE varianceRoll: bits[80..95]   via uint16(seed >> 80) % 20  (bias 0.02%)
    function _resolveLootboxRoll(
        address player,
        uint256 amount,
        uint256 lootboxAmount,
        uint256 targetPrice,
        uint32 day,
        uint256 seed
    )
        private
        returns (
            uint256 burnieOut,
            uint32 ticketsOut,
            bool applyPresaleMultiplier
        )
    {
        if (amount == 0) return (0, 0, false);

        uint256 roll = uint16(seed >> 40) % 20;
        if (roll < 11) {
            // 55% chance: tickets (returned as scaled × TICKET_SCALE)
            uint256 ticketBudget = (amount * LOOTBOX_TICKET_ROLL_BPS) / 10_000;
            uint32 ticketsScaled =
                _lootboxTicketCount(ticketBudget, targetPrice, seed);
            if (ticketsScaled != 0) {
                ticketsOut = ticketsScaled;
            }
            applyPresaleMultiplier = false;
        } else if (roll < 13) {
            // 10% chance: DGNRS tokens
            uint256 dgnrsAmount = _lootboxDgnrsReward(amount, seed);
            if (dgnrsAmount != 0) {
                uint256 paid = _creditDgnrsReward(player, dgnrsAmount);
                if (paid != 0) {
                    emit LootBoxDgnrsReward(
                        player,
                        day,
                        lootboxAmount,
                        paid
                    );
                }
            }
            applyPresaleMultiplier = false;
        } else if (roll < 15) {
            // 10% chance: WWXRP tokens. Payout via `wwxrp.mintPrize`; observable
            // off-chain through the WWXRP ERC-20 `Transfer` event (`0x0` -> player)
            // together with the same-tx lootbox context.
            uint256 wwxrpAmount = LOOTBOX_WWXRP_PRIZE;
            if (wwxrpAmount != 0) {
                wwxrp.mintPrize(player, wwxrpAmount);
            }
            applyPresaleMultiplier = false;
        } else {
            // 25% chance: large BURNIE reward with variance
            uint256 varianceRoll = uint16(seed >> 80) % 20;
            uint256 largeBurnieBps;
            if (varianceRoll < 16) {
                // Low path (80%): rolls 0-15, 58%-130% of value
                largeBurnieBps = LOOTBOX_LARGE_BURNIE_LOW_BASE_BPS +
                    varianceRoll * LOOTBOX_LARGE_BURNIE_LOW_STEP_BPS;
            } else {
                // High path (20%): rolls 16-19, 307%-590% of value
                largeBurnieBps = LOOTBOX_LARGE_BURNIE_HIGH_BASE_BPS +
                    (varianceRoll - 16) * LOOTBOX_LARGE_BURNIE_HIGH_STEP_BPS;
            }

            uint256 burnieBudget = (amount * largeBurnieBps) / 10_000;
            burnieOut = (burnieBudget * PRICE_COIN_UNIT) / targetPrice;
            applyPresaleMultiplier = true;
        }
    }

    /// @dev Calculate scaled ticket count from budget with variance tiers.
    ///      Returns count × TICKET_SCALE (100) for fractional ticket support.
    ///      1% get 4.6x, 4% get 2.3x, 20% get 1.1x, 45% get 0.651x, 30% get 0.45x.
    ///      Bit budget (consumed from `seed`):
    ///        - varianceRoll: bits[96..119] via uint24(seed >> 96) % 10_000 (bias 0.045%)
    /// @param budgetWei ETH budget for tickets
    /// @param priceWei Price per ticket at target level
    /// @param seed Per-resolution 256-bit keccak seed (sliced inline; no advance)
    /// @return countScaled Number of tickets × TICKET_SCALE
    function _lootboxTicketCount(
        uint256 budgetWei,
        uint256 priceWei,
        uint256 seed
    ) private pure returns (uint32 countScaled) {
        if (budgetWei == 0 || priceWei == 0) {
            return 0;
        }

        uint256 varianceRoll = uint24(seed >> 96) % 10_000;
        uint256 ticketBps;

        if (varianceRoll < LOOTBOX_TICKET_VARIANCE_TIER1_CHANCE_BPS) {
            ticketBps = LOOTBOX_TICKET_VARIANCE_TIER1_BPS;
        } else if (
            varianceRoll <
            LOOTBOX_TICKET_VARIANCE_TIER1_CHANCE_BPS +
                LOOTBOX_TICKET_VARIANCE_TIER2_CHANCE_BPS
        ) {
            ticketBps = LOOTBOX_TICKET_VARIANCE_TIER2_BPS;
        } else if (
            varianceRoll <
            LOOTBOX_TICKET_VARIANCE_TIER1_CHANCE_BPS +
                LOOTBOX_TICKET_VARIANCE_TIER2_CHANCE_BPS +
                LOOTBOX_TICKET_VARIANCE_TIER3_CHANCE_BPS
        ) {
            ticketBps = LOOTBOX_TICKET_VARIANCE_TIER3_BPS;
        } else if (
            varianceRoll <
            LOOTBOX_TICKET_VARIANCE_TIER1_CHANCE_BPS +
                LOOTBOX_TICKET_VARIANCE_TIER2_CHANCE_BPS +
                LOOTBOX_TICKET_VARIANCE_TIER3_CHANCE_BPS +
                LOOTBOX_TICKET_VARIANCE_TIER4_CHANCE_BPS
        ) {
            ticketBps = LOOTBOX_TICKET_VARIANCE_TIER4_BPS;
        } else {
            ticketBps = LOOTBOX_TICKET_VARIANCE_TIER5_BPS;
        }

        uint256 adjustedBudget = (budgetWei * ticketBps) / 10_000;
        uint256 base = (adjustedBudget * TICKET_SCALE) / priceWei;
        countScaled = uint32(base);
    }

    /// @dev Calculate DGNRS reward amount from the lootbox pool.
    ///      79.5% small tier, 15% medium, 5% large, 0.5% mega.
    ///      Bit budget (consumed from `entropy` — the threaded per-resolution seed):
    ///        - tierRoll: bits[56..79] via uint24(entropy >> 56) % 1000 (bias 0.0024%)
    /// @param amount ETH amount for calculation
    /// @param entropy Per-resolution 256-bit seed (sliced inline; no advance)
    /// @return dgnrsAmount DGNRS tokens to award
    function _lootboxDgnrsReward(
        uint256 amount,
        uint256 entropy
    ) private view returns (uint256 dgnrsAmount) {
        uint256 tierRoll = uint24(entropy >> 56) % 1000;
        uint256 ppm;
        if (tierRoll < 795) {
            ppm = LOOTBOX_DGNRS_POOL_SMALL_PPM;
        } else if (tierRoll < 945) {
            ppm = LOOTBOX_DGNRS_POOL_MEDIUM_PPM;
        } else if (tierRoll < 995) {
            ppm = LOOTBOX_DGNRS_POOL_LARGE_PPM;
        } else {
            ppm = LOOTBOX_DGNRS_POOL_MEGA_PPM;
        }

        uint256 poolBalance = dgnrs.poolBalance(IStakedDegenerusStonk.Pool.Lootbox);

        if (poolBalance == 0 || ppm == 0) return 0;
        dgnrsAmount = (poolBalance * ppm * amount) /
            (1_000_000 * 1 ether);
        if (dgnrsAmount > poolBalance) {
            dgnrsAmount = poolBalance;
        }
    }

    /// @dev Credit DGNRS reward to player from pool only.
    /// @param player Player to credit
    /// @param amount Requested DGNRS amount to credit
    /// @return paid Actual DGNRS amount paid from pool
    function _creditDgnrsReward(address player, uint256 amount) private returns (uint256 paid) {
        if (amount == 0) return 0;
        paid = dgnrs.transferFromPool(
            IStakedDegenerusStonk.Pool.Lootbox,
            player,
            amount
        );
    }

    /// @dev Get the value for a lazy pass at a specific level.
    ///      Value equals the sum of per-level ticket prices across 10 levels.
    /// @param passLevel The lazy pass start level
    /// @return The value in ETH (scaled by cost divisor), or 0 if invalid level
    function _lazyPassPriceForLevel(
        uint24 passLevel
    ) private pure returns (uint256) {
        if (passLevel == 0) return 0;
        uint256 total = 0;
        for (uint24 i = 0; i < 10; ) {
            total += PriceLookupLib.priceForLevel(passLevel + i);
            unchecked {
                ++i;
            }
        }
        return total;
    }

    /// @dev Check if decimator window is currently open.
    /// @return True if decimator boons can be awarded/used
    function _isDecimatorWindow() private view returns (bool) {
        return decWindowOpen;
    }

    /// @dev Deterministically generate a boon type for a deity's slot on a given day.
    /// @param deity The deity address
    /// @param day The day index
    /// @param slot The slot index (0-2)
    /// @param decimatorAllowed Whether decimator boons can be generated
    /// @param deityPassAvailable Whether deity passes are still available for purchase
    /// @return boonType The boon type (1-31)
    function _deityBoonForSlot(
        address deity,
        uint32 day,
        uint8 slot,
        bool decimatorAllowed,
        bool deityPassAvailable
    ) private view returns (uint8 boonType) {
        uint256 seed = uint256(keccak256(abi.encode(rngWordByDay[day], deity, day, slot)));
        uint256 total = decimatorAllowed
            ? BOON_WEIGHT_TOTAL
            : BOON_WEIGHT_TOTAL_NO_DECIMATOR;
        if (!deityPassAvailable) total -= BOON_WEIGHT_DEITY_PASS_ALL;
        uint256 roll = seed % total;
        return _boonFromRoll(roll, decimatorAllowed, deityPassAvailable, true);
    }

}
