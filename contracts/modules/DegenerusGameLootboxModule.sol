// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {IsDGNRS} from "../interfaces/IsDGNRS.sol";
import {IStETH} from "../interfaces/IStETH.sol";

import {IDegenerusGameBoonModule, IDegenerusGameDegeneretteModule} from "../interfaces/IDegenerusGameModules.sol";
import {IDegenerusQuests} from "../interfaces/IDegenerusQuests.sol";
import {ContractAddresses} from "../ContractAddresses.sol";
import {DegenerusGameStorage} from "../storage/DegenerusGameStorage.sol";
import {BitPackingLib} from "../libraries/BitPackingLib.sol";
import {EntropyLib} from "../libraries/EntropyLib.sol";
import {PriceLookupLib} from "../libraries/PriceLookupLib.sol";

/// @notice Interface for minting WWXRP prize tokens
interface IWWXRP {
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
 * - Box opening (openBox, resolveLootboxDirect, resolveRedemptionLootbox)
 * - Deity boon system (issueDeityBoon)
 */
contract DegenerusGameLootboxModule is DegenerusGameStorage {
    // =========================================================================
    // Errors
    // =========================================================================

    // error E() — inherited from DegenerusGameStorage
    error MsgValueExceedsAmount(); // msg.value exceeds the declared lootbox or credit amount
    error SelfBoon(); // deity attempted to issue a boon to themselves
    error InvalidSlot(); // deity boon slot index is >= DEITY_DAILY_BOON_COUNT
    error RecipientAlreadyBoonedToday(); // recipient already received a deity boon on the current day
    error RecipientBoonCapReached(); // recipient hit the lifetime cap on boons from this deity
    error SlotAlreadyUsed(); // deity boon slot has already been used on the current day

    /// @notice RNG word has not been set for the requested lootbox index
    error RngNotReady();


    // =========================================================================
    // Events
    // =========================================================================


    /// @notice Emitted when an ETH lootbox is successfully opened
    /// @param player The player who opened the lootbox
    /// @param lootboxIndex The per-player storage index of the opened lootbox
    /// @param amount The ETH amount of the lootbox (in wei)
    /// @param futureLevel The target level for future tickets
    /// @param futureTickets The pre-Bernoulli scaled (× QTY_SCALE) future ticket count
    /// @param flip The total FLIP tokens awarded (in wei)
    /// @param roundedUp True iff the Bernoulli round-up incremented the awarded
    ///        whole-ticket count by 1
    event LootBoxOpened(
        address indexed player,
        uint48 indexed lootboxIndex,
        uint256 amount,
        uint24 futureLevel,
        uint32 futureTickets,
        uint256 flip,
        bool roundedUp
    );

    /// @notice Emitted when a lootbox awards a whale pass jackpot
    /// @param player The player who won the jackpot
    /// @param lootboxAmount The ETH amount of the lootbox
    /// @param targetLevel Level AT BOX-OPEN TIME (`level + 1`), reported for
    ///        downstream indexers. Ticket queuing is deferred to the player-paid
    ///        `claimWhalePass` endpoint; tickets actually get queued at the level
    ///        when the beneficiary calls `claimWhalePass`, which may be greater
    ///        than this value (the player can delay the claim).
    /// @param entriesPerLevel Entries per level the materialized whale pass grants
    /// @param statsBoost Reserved for future use (always 0)
    /// @param frozenUntilLevel Reserved for future use (always 0)
    event LootBoxWhalePassJackpot(
        address indexed player,
        uint256 lootboxAmount,
        uint24 targetLevel,
        uint32 entriesPerLevel,
        uint24 statsBoost,
        uint24 frozenUntilLevel
    );

    /// @notice Emitted when a lootbox awards DGNRS tokens
    /// @param player The player who received the reward
    /// @param lootboxAmount The ETH amount of the lootbox
    /// @param dgnrsAmount The amount of DGNRS tokens awarded
    event LootBoxDgnrsReward(
        address indexed player,
        uint256 lootboxAmount,
        uint256 dgnrsAmount
    );

    /// @notice Emitted when a coin-presale box is resolved.
    /// @param player The box owner.
    /// @param index The box's RNG index.
    /// @param amount The box ETH resolved.
    /// @param flip FLIP credited (0 if not a FLIP roll).
    /// @param dgnrs DGNRS paid (roll award + any closing-box sweep).
    /// @param wwxrp WWXRP minted (0 unless the 10% dud roll).
    /// @param closing True iff this was the 50-ETH-crossing closing box.
    event PresaleBoxOpened(
        address indexed player,
        uint48 indexed index,
        uint256 amount,
        uint256 flip,
        uint256 dgnrs,
        uint256 wwxrp,
        bool closing
    );

    /// @notice Unified lootbox reward event for boon awards
    /// @param player The player receiving the reward
    /// @param rewardType The type of reward (2=CoinflipBoon, 4=Boost5, 5=Boost15, 6=Boost25/Purchase, 8=DecimatorBoost, 9=WhaleBoon, 10=ActivityBoon/DeityPassBoon, 11=LazyPassBoon)
    /// @param lootboxAmount The lootbox amount spent (ETH-equivalent for FLIP lootboxes)
    /// @param amount Primary reward amount (varies by type: BPS for boosts, token amount for boons)
    event LootBoxReward(
        address indexed player,
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
        uint24 indexed day,
        uint8 slot,
        uint8 boonType
    );

    // =========================================================================
    // External Contract References
    // =========================================================================

    /// @notice Reference to the WWXRP token contract
    IWWXRP internal constant wwxrp = IWWXRP(ContractAddresses.WWXRP);

    /// @notice Reference to the stETH token (redemption-direct stETH-remainder pull)
    IStETH internal constant steth = IStETH(ContractAddresses.STETH_TOKEN);


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

    /// @dev Whale boon discount tiers 1/2/3 (10%, 20%, 35%). The _25/_50 suffixes name the
    ///      tier slot, not the literal percentage.
    uint16 private constant LOOTBOX_WHALE_BOON_DISCOUNT_10_BPS = 1000;
    uint16 private constant LOOTBOX_WHALE_BOON_DISCOUNT_25_BPS = 2000;
    uint16 private constant LOOTBOX_WHALE_BOON_DISCOUNT_50_BPS = 3500;
    /// @dev Lazy pass boon discount tiers (10%, 25%, 50%).
    uint16 private constant LOOTBOX_LAZY_PASS_DISCOUNT_10_BPS = 1000;
    uint16 private constant LOOTBOX_LAZY_PASS_DISCOUNT_25_BPS = 2500;
    uint16 private constant LOOTBOX_LAZY_PASS_DISCOUNT_50_BPS = 5000;
    /// @dev Tier identifier for 10% deity pass discount boon (1000 bps)
    uint8 private constant DEITY_PASS_BOON_TIER_10 = 1;
    /// @dev Tier identifier for the tier-2 deity pass discount boon (20%, 2000 bps)
    uint8 private constant DEITY_PASS_BOON_TIER_25 = 2;
    /// @dev Tier identifier for the tier-3 deity pass discount boon (35%, 3500 bps)
    uint8 private constant DEITY_PASS_BOON_TIER_50 = 3;
    /// @dev Threshold used by deity-pass discount boon availability logic.
    uint32 private constant DEITY_PASS_MAX_TOTAL = 32;

    // Boon bonus values
    /// @dev 5% bonus in basis points for coinflip boon
    uint16 private constant LOOTBOX_BOON_BONUS_BPS = 500;
    /// @dev Maximum bonus amount for coinflip boon (5000 FLIP)
    uint256 private constant LOOTBOX_BOON_MAX_BONUS = 5000 ether;
    /// @dev Coinflip boon cap for max deposit (100k FLIP) used in EV estimation.
    uint256 private constant COINFLIP_BOON_MAX_DEPOSIT = 100_000 ether;
    /// @dev Decimator boon cap for base amount (50k FLIP) used in EV estimation.
    uint256 private constant DECIMATOR_BOON_CAP = 50_000 ether;
    /// @dev Whale pass standard price (used for whale discount boon EV estimation).
    uint256 private constant WHALE_PASS_STANDARD_PRICE =
        4 ether;
    /// @dev Whale pass standard tickets per level. Reported in the
    ///      LootBoxWhalePassJackpot event for downstream indexers; the
    ///      actual ticket materialization happens in claimWhalePass.
    uint32 private constant WHALE_PASS_ENTRIES_PER_LEVEL = 2;
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
    /// @dev Quest-streak shields granted per quest-shield boon
    uint16 private constant LOOTBOX_QUEST_SHIELD_GRANT = 1;

    // Lootbox roll constants
    /// @dev Base ticket roll budget in BPS (~155% EV after variance, 45% chance path).
    ///      Sized so the 45%-frequency ticket path distributes the same aggregate ETH
    ///      value as the prior 55%-frequency path (16_100 * 11 / 9).
    uint16 private constant LOOTBOX_TICKET_ROLL_BPS = 19_678;
    /// @dev Budget weighting by target-level distance, applied to the ticket roll budget.
    ///      Far-future ticket rolls (20% of ticket rolls) capture 30% of the aggregate
    ///      ticket budget at 1.5x; near rolls take 0.875x. EV-neutral across the 20%/80%
    ///      far/near split (0.8*0.875 + 0.2*1.5 = 1.0), so total ticket value is unchanged.
    uint16 private constant LOOTBOX_TICKET_FAR_BUDGET_BPS = 15_000;
    uint16 private constant LOOTBOX_TICKET_NEAR_BUDGET_BPS = 8_750;
    /// @dev 1% chance for tier 1 ticket variance (5.25x mean)
    uint16 private constant LOOTBOX_TICKET_VARIANCE_TIER1_CHANCE_BPS = 100;
    /// @dev 4% chance for tier 2 ticket variance (2.75x mean)
    uint16 private constant LOOTBOX_TICKET_VARIANCE_TIER2_CHANCE_BPS = 400;
    /// @dev 20% chance for tier 3 ticket variance (1.30x mean)
    uint16 private constant LOOTBOX_TICKET_VARIANCE_TIER3_CHANCE_BPS = 2000;
    /// @dev 45% chance for tier 4 ticket variance (0.792x mean)
    uint16 private constant LOOTBOX_TICKET_VARIANCE_TIER4_CHANCE_BPS = 4500;
    /// @dev Per-tier multiplier ranges (BPS). Each [LOW, HIGH] band is symmetric about its
    ///      per-tier mean; across the tier chances the overall variance EV is ~0.941x. The
    ///      position within a tier reuses the same varianceRoll that selected the tier
    ///      (uniform within the tier's chance window), so no extra entropy is drawn. Tier 5
    ///      (default, ~30%) covers the remaining window.
    uint16 private constant LOOTBOX_TICKET_VARIANCE_TIER1_LOW_BPS = 40_000; // 4.00x
    uint16 private constant LOOTBOX_TICKET_VARIANCE_TIER1_HIGH_BPS = 65_000; // 6.50x
    uint16 private constant LOOTBOX_TICKET_VARIANCE_TIER2_LOW_BPS = 20_000; // 2.00x
    uint16 private constant LOOTBOX_TICKET_VARIANCE_TIER2_HIGH_BPS = 35_000; // 3.50x
    uint16 private constant LOOTBOX_TICKET_VARIANCE_TIER3_LOW_BPS = 10_000; // 1.00x
    uint16 private constant LOOTBOX_TICKET_VARIANCE_TIER3_HIGH_BPS = 16_000; // 1.60x
    uint16 private constant LOOTBOX_TICKET_VARIANCE_TIER4_LOW_BPS = 5_923; // 0.5923x
    uint16 private constant LOOTBOX_TICKET_VARIANCE_TIER4_HIGH_BPS = 9_923; // 0.9923x
    uint16 private constant LOOTBOX_TICKET_VARIANCE_TIER5_LOW_BPS = 3_600; // 0.36x
    uint16 private constant LOOTBOX_TICKET_VARIANCE_TIER5_HIGH_BPS = 7_200; // 0.72x
    /// @dev 0.001% of DGNRS pool per ETH for small tier
    uint16 private constant LOOTBOX_DGNRS_POOL_SMALL_PPM = 10;
    /// @dev 0.039% of DGNRS pool per ETH for medium tier
    uint16 private constant LOOTBOX_DGNRS_POOL_MEDIUM_PPM = 390;
    /// @dev 0.08% of DGNRS pool per ETH for large tier
    uint16 private constant LOOTBOX_DGNRS_POOL_LARGE_PPM = 800;
    /// @dev 0.8% of DGNRS pool per ETH for mega tier
    uint16 private constant LOOTBOX_DGNRS_POOL_MEGA_PPM = 8000;
    /// @dev Fixed WWXRP prize amount (1 token); staked as the bet for the WWXRP spin roll.
    uint256 private constant LOOTBOX_WWXRP_PRIZE = 1 ether;
    /// @dev Cold-bust consolation magnitude (1 token). Paid on a manual lootbox open
    ///      whose ticket-path produced non-zero scaled tickets but the Bernoulli
    ///      round-up failed to award a whole ticket. Magnitude-equal to
    ///      LOOTBOX_WWXRP_PRIZE — the consolation trigger is much rarer than the
    ///      10%-path WWXRP win, so 1:1 magnitude is intentional.
    uint256 private constant LOOTBOX_WWXRP_CONSOLATION = 1 ether;
    /// @dev Domain-separation tags mixed (via hash2) into the box seed to derive each
    ///      Degenerette-spin sub-seed. Counter-tagged off the primary chunk, so the spins
    ///      consume no primary-chunk bits and never collide with the box's own draws.
    uint256 private constant BOX_WWXRP_SPIN_TAG = 0x57777872705370696e; // "WwxrpSpin"
    uint256 private constant BOX_FLIP_SPIN_TAG = 0x4275726e69655370696e; // "FlipSpin"
    uint256 private constant BOX_ETH_SPIN_TAG = 0x4574685370696e; // "EthSpin"
    /// @dev Base BPS for low FLIP path (43.88%)
    uint16 private constant LOOTBOX_LARGE_FLIP_LOW_BASE_BPS = 4_388;
    /// @dev Step increase in BPS for low FLIP path (3.60% per step)
    uint16 private constant LOOTBOX_LARGE_FLIP_LOW_STEP_BPS = 360;
    /// @dev Base BPS for high FLIP path (231.99%)
    uint16 private constant LOOTBOX_LARGE_FLIP_HIGH_BASE_BPS = 23_199;
    /// @dev Step increase in BPS for high FLIP path (71.25% per step)
    uint16 private constant LOOTBOX_LARGE_FLIP_HIGH_STEP_BPS = 7_125;
    /// @dev Stake haircut (70.60%) applied to the FLIP-spins branch (roll 17-18) on top of
    ///      the reduced large-FLIP ladder, so the flat FLIP branch carries more of the FLIP
    ///      EV (flat:spins split 68:32 within FLIP). The flat FLIP roll (14-16) is not haircut.
    uint16 private constant LOOTBOX_FLIP_SPINS_STAKE_BPS = 7_060;

    // ---- Coin-presale-box FLIP band (lootbox band recentered on a 400% branch mean) ----
    // E[largeFlipBps] = 0.8*lowMean + 0.2*highMean = 40000 (400% of box ETH on the
    // FLIP branch -> 200% all-boxes average since FLIP rolls 50%).
    /// @dev Base BPS for low presale-box FLIP path (rolls 0-15, p=80%).
    uint32 private constant PRESALE_BOX_FLIP_LOW_BASE_BPS = 14_098;
    /// @dev Step BPS per roll for low presale-box FLIP path.
    uint32 private constant PRESALE_BOX_FLIP_LOW_STEP_BPS = 1_158;
    /// @dev Base BPS for high presale-box FLIP path (rolls 16-19, p=20%).
    uint32 private constant PRESALE_BOX_FLIP_HIGH_BASE_BPS = 74_534;
    /// @dev Step BPS per roll for high presale-box FLIP path.
    uint32 private constant PRESALE_BOX_FLIP_HIGH_STEP_BPS = 22_890;

    // ---- Coin-presale-box DGNRS curve (5 tiers x 10 ETH cumulative box volume) ----
    // Relative DGNRS-per-ETH rates [3.0, 2.5, 2.0, 1.5, 1.0] x base, base = poolStart/40.
    // Over 50 ETH the full deterministic draw sums to 100*base = 2.5*poolStart; with the
    // ~40% DGNRS branch rate the pool drains through the boxes (closing sweep clamps to dust).
    /// @dev DGNRS tier multipliers in tenths (3.0x .. 1.0x), by cumulative box volume.
    uint16 private constant PRESALE_BOX_DGNRS_TIER1_TENTHS = 30;
    uint16 private constant PRESALE_BOX_DGNRS_TIER2_TENTHS = 25;
    uint16 private constant PRESALE_BOX_DGNRS_TIER3_TENTHS = 20;
    uint16 private constant PRESALE_BOX_DGNRS_TIER4_TENTHS = 15;
    uint16 private constant PRESALE_BOX_DGNRS_TIER5_TENTHS = 10;
    /// @dev Cumulative box-ETH width of each DGNRS tier (10 ETH).
    uint256 private constant PRESALE_BOX_DGNRS_TIER_WIDTH = 10 ether;

    /// @dev Whale pass price (200 tickets over levels 10-109)
    uint256 private constant LOOTBOX_WHALE_PASS_PRICE =
        4.50 ether;
    /// @dev Threshold above which lootbox is split into two rolls (0.5 ETH scaled)
    uint256 private constant LOOTBOX_SPLIT_THRESHOLD =
        0.5 ether;

    /// @dev Distress-mode ticket bonus in basis points (25%).
    uint16 private constant DISTRESS_TICKET_BONUS_BPS = 2500;

    /// @dev Probability scale for granular boon rolls (ppm = 1e6).
    uint256 private constant BOON_PPM_SCALE = 1_000_000;

    // Boon categories — players may hold one boon per category simultaneously.
    // Within a category, upgrade semantics apply (higher tier replaces lower).

    // Deity boon constants
    /// @dev Number of boon slots available per deity per day
    uint8 private constant DEITY_DAILY_BOON_COUNT = 3;

    /// @dev Lifetime cap on deity boons a single deity may issue to a single recipient
    uint8 private constant DEITY_RECIPIENT_BOON_CAP = 10;

    /// @dev Boon type: 5% coinflip bonus
    uint8 private constant BOON_COINFLIP_5 = 1;
    /// @dev Boon type: 10% coinflip bonus
    uint8 private constant BOON_COINFLIP_10 = 2;
    /// @dev Boon type: 25% coinflip bonus
    uint8 private constant BOON_COINFLIP_25 = 3;
    /// @dev Boon type: grant one quest-streak shield
    uint8 private constant BOON_QUEST_SHIELD = 4;
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
    /// @dev Boon type: tier-2 whale discount (20%)
    uint8 private constant BOON_WHALE_25 = 23;
    /// @dev Boon type: tier-3 whale discount (35%)
    uint8 private constant BOON_WHALE_50 = 24;
    /// @dev Boon type: 10% deity pass discount
    uint8 private constant BOON_DEITY_PASS_10 = 25;
    /// @dev Boon type: tier-2 deity pass discount (20%)
    uint8 private constant BOON_DEITY_PASS_25 = 26;
    /// @dev Boon type: tier-3 deity pass discount (35%)
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
    /// @dev Weight for tier-2 whale boon (20%)
    uint16 private constant BOON_WEIGHT_WHALE_25 = 10;
    /// @dev Weight for tier-3 whale boon (35%)
    uint16 private constant BOON_WEIGHT_WHALE_50 = 2;
    /// @dev Weight for 10% deity pass discount boon
    uint16 private constant BOON_WEIGHT_DEITY_PASS_10 = 28;
    /// @dev Weight for tier-2 deity pass discount boon (20%)
    uint16 private constant BOON_WEIGHT_DEITY_PASS_25 = 10;
    /// @dev Weight for tier-3 deity pass discount boon (35%)
    uint16 private constant BOON_WEIGHT_DEITY_PASS_50 = 2;
    /// @dev Weight for 10 point activity boon
    uint16 private constant BOON_WEIGHT_ACTIVITY_10 = 100;
    /// @dev Weight for 25 point activity boon
    uint16 private constant BOON_WEIGHT_ACTIVITY_25 = 30;
    /// @dev Weight for 50 point activity boon
    uint16 private constant BOON_WEIGHT_ACTIVITY_50 = 8;
    /// @dev Weight for the quest-streak-shield boon
    uint16 private constant BOON_WEIGHT_QUEST_SHIELD = 200;
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
    /// @dev Total weight sum when decimator boons are allowed (includes the +200 quest-shield weight)
    uint16 private constant BOON_WEIGHT_TOTAL = 1498;
    /// @dev Total weight sum when decimator boons are not allowed
    uint16 private constant BOON_WEIGHT_TOTAL_NO_DECIMATOR = 1448;

    // =========================================================================
    // Lootbox Opening Functions
    // =========================================================================

    /// @dev Apply EV multiplier with per-account per-level cap of 10 ETH.
    ///      Tracks how much benefit has been used and only applies EV adjustment
    ///      to the uncapped portion. Remainder gets 100% EV (neutral).
    /// @param player Player address
    /// @param lvl Current game level
    /// @param amount Lootbox ETH amount
    /// @param evMultiplierBps EV multiplier in basis points (9000-14500)
    /// @return scaledAmount Amount after EV adjustment
    function _applyEvMultiplierWithCap(
        address player,
        uint24 lvl,
        uint256 amount,
        uint256 evMultiplierBps
    ) private returns (uint256 scaledAmount) {
        // Bonus-only cap: penalty (< NEUTRAL) and neutral (== NEUTRAL) boxes apply the
        // multiplier on the full amount and draw nothing from the cap. Only a bonus box
        // (> NEUTRAL) falls through to the cap-draw branch below.
        if (evMultiplierBps <= LOOTBOX_EV_NEUTRAL_BPS) {
            return (amount * evMultiplierBps) / 10_000;
        }

        // Check how much EV benefit capacity remains for this level
        uint256 usedBenefit = _lootboxEvUsedFor(player, lvl);
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
        _setLootboxEvUsedFor(player, lvl, usedBenefit + adjustedPortion);

        // Calculate scaled amount:
        // - adjustedPortion gets the full EV multiplier
        // - neutralPortion gets 100% EV
        uint256 adjustedValue = (adjustedPortion * evMultiplierBps) / 10_000;
        scaledAmount = adjustedValue + neutralPortion;
    }

    /// @dev Open the ETH-lootbox leg of an index for a player, if one is queued. Applies the
    ///      frozen activity-score EV multiplier (the 10 ETH cap was drawn at deposit). Returns
    ///      false (no-op) when no lootbox is queued, so the unified open path can still resolve
    ///      the presale leg; the manual `openBox` shell turns an all-empty index into a revert.
    /// @param player Player address to open the lootbox for.
    /// @param index The RNG index of the lootbox.
    /// @return opened True if a lootbox leg was resolved.
    /// @custom:reverts RngNotReady When the lootbox is queued but its RNG word is not yet set.
    function _openLootBoxLeg(address player, uint48 index) internal returns (bool opened) {
        uint256 packed = lootboxEth[index][player];
        // Early-out before the rngWord SLOAD when no lootbox leg is queued (the presale leg
        // loads the word itself).
        if ((packed & LB_AMOUNT_MASK) == 0) return false;
        return _openLootBoxLegWith(player, index, packed, lootboxRngWordByIndex[index]);
    }

    /// @dev Lootbox-leg body operating on pre-loaded values: `packed` is the player's
    ///      lootboxEth word at `index`, `rngWord` the index's committed VRF word. The
    ///      sweep (`openHumanBoxes`) loads both once per entry/index and threads them down;
    ///      the manual shell (`_openLootBoxLeg`) loads them itself. Values cannot go stale
    ///      between load and use: no callee on this path hands control to player code, and
    ///      a lootboxEth write at a worded index is unreachable from the buy path.
    /// @custom:reverts RngNotReady When a lootbox is queued but `rngWord` is zero.
    function _openLootBoxLegWith(
        address player,
        uint48 index,
        uint256 packed,
        uint256 rngWord
    ) internal returns (bool opened) {
        (uint256 amount, uint64 adj, uint16 score, uint256 distressUnits) =
            _unpackLootbox(packed);
        if (amount == 0) return false;

        if (rngWord == 0) revert RngNotReady();

        uint24 currentLevel = level + 1;
        // The box rolls from the LIVE level at open — no stored purchase-level basis, no grace
        // window. Auto-open (the permissionless openBoxes bounty) opens every ready box ASAP and a
        // holder cannot prevent it, so the open level is NOT player-timable: the holder can never
        // steer the box to a level they prefer, whichever way the level cuts. The EV multiplier
        // stays FROZEN at deposit (`score`) — that is the anti-gaming knob. One unified roll
        // basis with `resolveAfkingBox` / `resolveLootboxDirect`. amount, adj, score, and the
        // distress fraction all ride in the single packed lootboxEth word.

        // Seed = the per-index VRF anchor `rngWord` (fixed at the index's advance, never knowable at
        // deposit) + player + amount. No day term: the box binds to the index word for uniqueness and
        // freeze-safety, so a day adds nothing — and a day keyed to the OPEN day would be re-rollable
        // by timing the open. The boon path reads its own live day internally.
        uint256 seed = uint256(keccak256(abi.encode(rngWord, player, amount)));
        uint24 targetLevel = _rollTargetLevel(currentLevel, seed);

        // Apply the activity score EV multiplier to the reward amount (90% to 145%).
        // score is the raw activity-score snapshot written at first deposit on every
        // ETH-lootbox allocation path and frozen thereafter; the multiplier uses the
        // committed score.
        uint256 evMultiplierBps = _lootboxEvMultiplierFromScore(uint256(score));
        // Frozen application: penalty/neutral boxes scale the full amount; a bonus box
        // scales only the cap-eligible adjustedPortion (frozen at deposit time) and pays
        // the remainder at 100%. No cap SLOAD/SSTORE here — the cap was drawn at deposit.
        uint256 scaledAmount = evMultiplierBps <= LOOTBOX_EV_NEUTRAL_BPS
            ? (amount * evMultiplierBps) / 10_000
            : (uint256(adj) * evMultiplierBps) / 10_000 + (amount - uint256(adj));

        // distress was stored at 0.01-ETH granularity; restore to wei for the bonus ratio.
        uint256 distressEth = distressUnits * LB_DISTRESS_SCALE;

        // Clear amount, adj, score, and distress in one SSTORE of the whole word.
        lootboxEth[index][player] = 0;
        _resolveLootboxCommon(
            player,
            index,
            scaledAmount,
            targetLevel,
            currentLevel,
            seed,
            true,
            distressEth,
            amount,
            true,
            score,
            true
        );
        return true;
    }

    /// @notice Open every box queued at an RNG index for a player — the ETH-lootbox leg, the
    ///         coin-presale-box leg, or both (one committed word, two domain-separated draws,
    ///         each leg robust to being empty). The unified manual open entrypoint.
    /// @param player Player that owns the box(es) (resolved by the entrypoint).
    /// @param index The shared RNG index the box(es) queued at.
    /// @custom:reverts NothingToClaim When neither leg has a box queued at this index for the player.
    /// @custom:reverts RngNotReady When a queued leg's committed RNG word is not yet set.
    function openBox(address player, uint48 index) external {
        // Permissionless: box rewards always credit the owner, so any caller may open any
        // player's ready boxes (zero address = caller).
        if (player == address(0)) player = msg.sender;
        // Probe the presale leg until the sweep has drained presale (free slot-0 read of the flag).
        if (!_openBoxBoth(player, index, !presaleDrained)) revert NothingToClaim();
    }

    /// @dev Both-leg open body for the manual `openBox` entrypoint (the sweep threads
    ///      pre-loaded values into `_openLootBoxLegWith` directly). Resolves the lootbox leg
    ///      (if queued) then, when `checkPresale`, the presale-box leg (if queued); each robust
    ///      to being empty. The `player` is the resolved owner — `openBox` maps the zero address
    ///      to msg.sender, and the sweep passes a concrete owner. Runs in the game's storage context.
    /// @param player Box owner (already resolved).
    /// @param index The shared RNG index.
    /// @param checkPresale Whether to probe the presale-box leg — the caller passes `!presaleDrained`,
    ///        skipping the cold presaleBoxEth SLOAD once presale is fully drained.
    /// @return any True if at least one leg was resolved.
    function _openBoxBoth(address player, uint48 index, bool checkPresale) internal returns (bool any) {
        // Lootbox leg: resolves (and reports) only if one is queued — its own seed derivation.
        if (_openLootBoxLeg(player, index)) any = true;
        // Presale-box leg: probed only while presale boxes are outstanding. Boon-less, own
        // resolution (NOT a _resolveLootboxCommon caller): a credit-funded box can never mint a
        // whale pass. 50/40/10 FLIP/DGNRS/WWXRP.
        if (checkPresale) {
            uint256 stored = presaleBoxEth[index][player];
            if (stored != 0) {
                uint256 rngWord = lootboxRngWordByIndex[index];
                if (rngWord == 0) revert RngNotReady();
                presaleBoxEth[index][player] = 0; // dequeue
                _resolvePresaleBox(player, index, stored, rngWord);
                any = true;
            }
        }
    }

    /// @notice Human-box leg of openBoxes(): a permissionless, gas-bounded MULTI-INDEX sweep.
    /// @dev Delegatecall entrypoint from DegenerusGame.openBoxes — runs in the Game's storage
    ///      context, mirroring the afking leg's drainAfkingBoxes delegatecall. Walks the open
    ///      frontier from boxCursorIndex up to LR_INDEX-1 (the finalized indices — words land at
    ///      LR_INDEX-1, one behind the pre-incremented active index), opening every ready box at
    ///      each index, then advancing to the next. `budget` bounds the ENTRIES scanned this call:
    ///      opens AND skips each cost one step, so a long skip-prefix (already-opened or
    ///      presale-only entries) can never gas-wall the tx — progress is monotonic and persists
    ///      across calls via (boxCursorIndex, boxCursor). Each entry resolves BOTH legs
    ///      (lootbox + presale, robust to either empty) from values loaded once per entry —
    ///      the skip-check reads are threaded into the opens. Orphan-index
    ///      coupling: the sweep STOPS at any index whose VRF word has not landed
    ///      (orphaned mid-day by a coordinator rotation) instead of advancing past it, so its boxes
    ///      are never marooned — it resumes once the re-issued word lands. Every leg is O(1)
    ///      (whale-pass materialization is deferred to claimWhalePass).
    /// @param budget Maximum entries (opens + skips + index-headers) scanned this call.
    /// @return opened Total human boxes opened this call.
    function openHumanBoxes(uint256 budget) external returns (uint256 opened) {
        // Entry-gate: the open path's revert sources — rngLock and the terminal-jackpot
        // liveness control — are excluded pre-loop so the loop body is guaranteed-non-reverting.
        if (rngLockedFlag || _livenessTriggered()) return 0;

        uint48 active = uint48(_lrRead(LR_INDEX_SHIFT, LR_INDEX_MASK));
        if (active <= 1) return 0; // no finalized index yet (LR_INDEX is genesis-1, monotonic)
        uint48 finalized = active - 1; // highest openable index — where the word lands

        uint48 idx = boxCursorIndex;
        if (idx == 0) idx = 1; // index 0 is unused; the genesis box index is 1
        uint256 cur = boxCursor;
        // Free slot-0 read (the entry-gate above already SLOAD'd slot 0 for rngLockedFlag): probe
        // the presale leg until presale is fully drained. The flag is flipped (below) once this
        // sweep advances past presaleCloseIndex, after which every entry skips the cold
        // presaleBoxEth SLOAD. Cached once per call.
        bool checkPresale = !presaleDrained;

        uint256 steps; // entries + index-headers scanned this call — bounds the tx gas
        while (idx <= finalized && steps < budget) {
            unchecked {
                ++steps; // each index visit costs a step (bounds an empty-index crawl)
            }
            // Orphan-index coupling: never advance past an un-worded index, or its boxes maroon.
            // The word is loaded once per index and threaded into every open below.
            uint256 word = lootboxRngWordByIndex[idx];
            if (word == 0) break;

            address[] storage queue = boxPlayers[idx];
            uint256 qlen = queue.length;
            while (cur < qlen && steps < budget) {
                address player = queue[cur];
                unchecked {
                    ++cur;
                    ++steps;
                }
                // Open if EITHER leg is still owed: the lootbox leg (lootboxEth amount) or the
                // presale leg (presaleBoxEth, probed only while boxes are outstanding). Both are
                // zeroed on open, so a zero/zero entry is already-drained (or never carried a box
                // of this type) and is skipped. Each leg's word is loaded ONCE here and threaded
                // into its open — the skip-check values double as the open's inputs.
                uint256 packed = lootboxEth[idx][player];
                uint256 stored = checkPresale ? presaleBoxEth[idx][player] : 0;
                if ((packed & LB_AMOUNT_MASK) == 0 && stored == 0) continue;
                // Guaranteed-non-reverting under the entry-gate + the word!=0 index gate above:
                // resolves the lootbox AND presale legs (each robust to being empty). The cached
                // values cannot go stale across the lootbox leg's external calls: no callee on
                // that path hands control to player code, and a presaleBoxEth write at a worded
                // index is unreachable from the buy path.
                _openLootBoxLegWith(player, idx, packed, word);
                if (stored != 0) {
                    presaleBoxEth[idx][player] = 0; // dequeue before resolution
                    _resolvePresaleBox(player, idx, stored, word);
                }
                unchecked {
                    ++opened;
                }
            }

            if (cur < qlen) break; // budget hit mid-index — resume here next call
            unchecked {
                ++idx; // index fully swept — advance the open frontier (this index is now complete)
            }
            cur = 0;
        }

        boxCursorIndex = idx;
        boxCursor = uint48(cur);
        // Presale is fully drained once the cursor has advanced PAST the close index (every box at
        // indices <= presaleCloseIndex is now opened). One-way, sweep-only; gated on presaleOver so
        // it never fires before the close index is meaningful (zero while presale is open / never
        // closed). Thereafter every open path skips the cold presaleBoxEth SLOAD.
        if (presaleOver && !presaleDrained && idx > presaleCloseIndex) presaleDrained = true;
    }

    /// @dev Resolve a presale box: 50% FLIP / 40% DGNRS / 10% WWXRP off the salted
    ///      committed word. The closing box also sweeps the Pool.PresaleBox remainder.
    /// @param player Box owner.
    /// @param index The box's RNG index (event tag).
    /// @param stored Packed record: [bit255 closing][96:191 soldBefore][0:95 amount].
    /// @param rngWord The committed daily word for this index (frozen at buy).
    function _resolvePresaleBox(
        address player,
        uint48 index,
        uint256 stored,
        uint256 rngWord
    ) private {
        // A queued record always carries non-zero amount bits (the buy path packs
        // applied >= the box minimum), so a non-zero `stored` implies amount != 0.
        uint256 amount = stored & PRESALE_BOX_AMOUNT_MASK;
        uint256 soldBefore = (stored >> PRESALE_BOX_SOLD_SHIFT) & PRESALE_BOX_AMOUNT_MASK;
        bool closing = (stored & PRESALE_BOX_CLOSING_FLAG) != 0;

        // Domain-separated draw off the committed word + the box's immutable buy data
        // (player + amount). No new mutable SLOAD enters the roll (RNG freeze).
        uint256 seed = uint256(
            keccak256(
                abi.encodePacked(rngWord, keccak256("PRESALE_BOX"), player, amount)
            )
        );

        uint256 outcome = uint16(seed) % 100;
        uint256 flipOut;
        uint256 dgnrsOut;
        uint256 wwxrpOut;
        if (outcome < 50) {
            // 50% FLIP: variance band recentered on a 400% branch mean.
            uint256 varianceRoll = uint16(seed >> 80) % 20;
            uint256 flipBps;
            if (varianceRoll < 16) {
                flipBps = PRESALE_BOX_FLIP_LOW_BASE_BPS +
                    varianceRoll * PRESALE_BOX_FLIP_LOW_STEP_BPS;
            } else {
                flipBps = PRESALE_BOX_FLIP_HIGH_BASE_BPS +
                    (varianceRoll - 16) * PRESALE_BOX_FLIP_HIGH_STEP_BPS;
            }
            // priceForLevel returns a non-zero constant for every level.
            uint256 priceWei = PriceLookupLib.priceForLevel(level + 1);
            uint256 flipBudget = (amount * flipBps) / 10_000;
            flipOut = (flipBudget * PRICE_COIN_UNIT) / priceWei;
            // Floor to whole FLIP (1 FLIP = 1 ether), mirroring the lootbox.
            flipOut = (flipOut / 1 ether) * 1 ether;
            if (flipOut != 0) {
                coinflip.creditFlip(player, flipOut);
            }
        } else if (outcome < 90) {
            // 40% DGNRS: 5-tier %-of-pool curve keyed on the FROZEN buy-time cumulative.
            dgnrsOut = _presaleBoxDgnrsReward(player, amount, soldBefore);
        } else {
            // 10% WWXRP: 1 token flavor "dud".
            wwxrpOut = LOOTBOX_WWXRP_PRIZE;
            wwxrp.mintPrize(player, wwxrpOut);
        }

        // Closing box: sweep ALL remaining Pool.PresaleBox DGNRS to this buyer, ON TOP
        // of the roll, regardless of outcome — zeroes the pool for a clean wrap-up.
        uint256 swept;
        if (closing) {
            uint256 remaining = dgnrs.poolBalance(
                IsDGNRS.Pool.PresaleBox
            );
            if (remaining != 0) {
                swept = dgnrs.transferFromPool(
                    IsDGNRS.Pool.PresaleBox,
                    player,
                    remaining
                );
                dgnrsOut += swept;
            }
        }

        emit PresaleBoxOpened(player, index, amount, flipOut, dgnrsOut, wwxrpOut, closing);
    }

    /// @dev Presale-box DGNRS award: tierMultiplier x base x boxEth, base = poolStart/40,
    ///      tier by the FROZEN buy-time cumulative box volume (5 tiers x 10 ETH).
    ///      Snapshots Pool.PresaleBox into presaleBoxDgnrsPoolStart on first resolution.
    /// @param player Box owner to credit.
    /// @param amount Box ETH for this resolution.
    /// @param soldBefore Cumulative box ETH before this box's buy (tier selector).
    /// @return paid Actual DGNRS transferred from the pool.
    function _presaleBoxDgnrsReward(
        address player,
        uint256 amount,
        uint256 soldBefore
    ) private returns (uint256 paid) {
        uint256 poolStart = presaleBoxDgnrsPoolStart;
        if (poolStart == 0) {
            poolStart = dgnrs.poolBalance(IsDGNRS.Pool.PresaleBox);
            if (poolStart == 0) return 0;
            presaleBoxDgnrsPoolStart = poolStart;
        }
        // base = poolStart / 40 DGNRS per ETH; tier multiplier in tenths.
        uint256 tierTenths = _presaleBoxDgnrsTierTenths(soldBefore);
        // amount (wei) * (poolStart/40) per ETH * tier/10:
        //   = poolStart * tierTenths * amount / (40 * 10 * 1 ether)
        uint256 dgnrsAmount = (poolStart * tierTenths * amount) / (400 * 1 ether);
        if (dgnrsAmount == 0) return 0;
        paid = dgnrs.transferFromPool(
            IsDGNRS.Pool.PresaleBox,
            player,
            dgnrsAmount
        );
    }

    /// @dev DGNRS tier multiplier (tenths) by buy-time cumulative box volume.
    ///      [0,10) -> 3.0x, [10,20) -> 2.5x, [20,30) -> 2.0x, [30,40) -> 1.5x, >=40 -> 1.0x.
    /// @param soldBefore Cumulative box ETH before the buy.
    /// @return tenths Tier multiplier x10.
    function _presaleBoxDgnrsTierTenths(
        uint256 soldBefore
    ) private pure returns (uint256 tenths) {
        if (soldBefore < PRESALE_BOX_DGNRS_TIER_WIDTH) {
            tenths = PRESALE_BOX_DGNRS_TIER1_TENTHS;
        } else if (soldBefore < 2 * PRESALE_BOX_DGNRS_TIER_WIDTH) {
            tenths = PRESALE_BOX_DGNRS_TIER2_TENTHS;
        } else if (soldBefore < 3 * PRESALE_BOX_DGNRS_TIER_WIDTH) {
            tenths = PRESALE_BOX_DGNRS_TIER3_TENTHS;
        } else if (soldBefore < 4 * PRESALE_BOX_DGNRS_TIER_WIDTH) {
            tenths = PRESALE_BOX_DGNRS_TIER4_TENTHS;
        } else {
            tenths = PRESALE_BOX_DGNRS_TIER5_TENTHS;
        }
    }

    /// @notice Resolve a lootbox directly for decimator/degenerette wins (no RNG wait needed)
    /// @dev Rolls full boons + passes via the common resolver (passes still gated by real
    ///      game-state: lazyPassValue != 0 / deity eligibility). Emits the per-box
    ///      `LootBoxOpened` summary like every box path; no cold-bust consolation on this
    ///      auto-resolve path.
    /// @param player Player address to resolve for
    /// @param amount ETH amount for the lootbox resolution
    /// @param rngWord RNG word to use for resolution
    /// @param activityScore Whole-point activity score frozen at commitment by the caller — decimator
    ///        claims pass the min score of the winning decimator bucket (sealed at burn);
    ///        degenerette passes the score snapshotted at bet time. Never a live read.
    // payable: reachable from the payable redemption path via an ETH-spin's recirc
    // (`resolveEthSpinFromBox` -> `_resolveLootboxDirect`); delegatecall preserves the
    // in-flight msg.value, so a non-payable callvalue guard here would revert the claim.
    function resolveLootboxDirect(address player, uint256 amount, uint256 rngWord, uint16 activityScore) external payable {
        // Delegatecall-only: address(this) == GAME under the nested dispatch. A direct call on the
        // deployed module would trap the in-flight msg.value (the amount==0 early-return path).
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();
        if (amount == 0) return;

        uint24 currentLevel = level + 1;
        // Freeze-safe seed: only the committed rngWord — which the caller domain-separates per
        // resolution (Degenerette mixes the immutable betId, the decimator passes its per-level
        // word) — and the player feed it. No live, post-word-reveal input enters the seed, so
        // neither claim timing nor a futurePrizePool nudge can re-roll the outcome. No live day is
        // read here either — boon expiry uses the boon path's own currentDay.
        uint256 seed = EntropyLib.hash2(rngWord, uint256(uint160(player)));
        uint24 targetLevel = _rollTargetLevel(currentLevel, seed);

        uint256 evMultiplierBps = _lootboxEvMultiplierFromScore(uint256(activityScore));
        uint256 scaledAmount = _applyEvMultiplierWithCap(player, currentLevel, amount, evMultiplierBps);

        // allowEthSpin=false: this is the recirc entry, called inside resolveDegeneretteBets' deferred
        // ETH-pool flush window — an ETH-spin RMW here would be clobbered by that flush. Roll
        // 19 awards tickets instead. Every box itemizes its contents, so this path emits the
        // `LootBoxOpened` summary unconditionally (gated only by the spin suppression downstream).
        _resolveLootboxCommon(
            player,
            0,
            scaledAmount,
            targetLevel,
            currentLevel,
            seed,
            false,
            0,
            0,
            true,
            activityScore,
            false
        );
    }

    /// @notice Resolve redemption lootboxes for an sDGNRS gambling burn claim.
    /// @dev Delegatecall target of the Game's resolveRedemptionLootbox stub, so msg.sender
    ///      (sDGNRS), msg.value, and address(this) (the Game) are all the caller's. The owed value
    ///      arrives as forwarded ETH (msg.value) plus a stETH top-up for any remainder: msg.value
    ///      covers 0..amount and the rest is pulled via transferFrom (sDGNRS pre-approves GAME for
    ///      max). This lets a partial- or zero-ETH sDGNRS (mid-game depletion) still settle — an
    ///      ETH-only forward would revert and strand the whole claim. Both media credit
    ///      futurePrizePool and count toward the game's claimablePool backing identically. No
    ///      claimableWinnings[SDGNRS] debit occurs — the value was already pulled out of claimable
    ///      at submit via pullRedemptionReserve, so reclassifying claimable here would double-spend
    ///      it. Splits into 5 ETH boxes resolved by plain internal calls inside this one
    ///      delegatecall frame (same Game storage context, identical per-chunk seed-rehash chain).
    /// @param player Player receiving lootbox rewards
    /// @param amount Total lootbox value to resolve (msg.value ETH + the stETH remainder pulled here)
    /// @param rngWord RNG entropy for lootbox resolution
    /// @param activityScore Snapshotted activity score (whole points) from burn submission
    function resolveRedemptionLootbox(address player, uint256 amount, uint256 rngWord, uint16 activityScore) external payable {
        if (msg.sender != ContractAddresses.SDGNRS) revert OnlySDGNRS();
        if (amount == 0) return;
        // Forwarded ETH (msg.value) funds the leg; any remainder is pulled as stETH so a
        // partial-ETH sDGNRS can still settle. msg.value must not exceed the leg amount.
        if (msg.value > amount) revert MsgValueExceedsAmount();
        uint256 stethPortion;
        unchecked { stethPortion = amount - msg.value; }
        if (stethPortion != 0) {
            if (!steth.transferFrom(msg.sender, address(this), stethPortion)) revert TransferFailed();
        }

        // Credit the just-arrived value to the future prize pool (respects freeze state). The
        // value was segregated out of claimableWinnings[SDGNRS] at submit, so there is no
        // claimable debit here — only a real-value-in credit.
        if (prizePoolFrozen) {
            (uint128 pNext, uint128 pFuture) = _getPendingPools();
            _setPendingPools(pNext, pFuture + uint128(amount));
        } else {
            (uint128 next, uint128 future) = _getPrizePools();
            _setPrizePools(next, future + uint128(amount));
        }

        // Resolve lootboxes in 5 ETH chunks
        uint256 remaining = amount;
        while (remaining != 0) {
            uint256 box = remaining > 5 ether ? 5 ether : remaining;
            _resolveRedemptionChunk(player, box, rngWord, activityScore);
            remaining -= box;
            rngWord = EntropyLib.hash1(rngWord);
        }
    }

    /// @dev Resolve one redemption lootbox chunk (≤ 5 ETH, never 0) with a snapshotted activity
    ///      score. Uses the provided score instead of reading current (snapshotted at submission).
    /// @param player Player address to resolve for
    /// @param amount ETH amount for this chunk's resolution
    /// @param rngWord RNG word to use for resolution
    /// @param activityScore Raw activity score (whole points) snapshotted at burn submission
    function _resolveRedemptionChunk(address player, uint256 amount, uint256 rngWord, uint16 activityScore) private {
        uint24 currentLevel = level + 1;
        // Freeze-safe seed with NO live day: claim timing must not re-roll the outcome (rngWord,
        // frozen at submission, already domain-separates). No live day is read here — boon expiry
        // uses the boon path's own currentDay, and the event day is unused for this claim.
        uint256 seed = uint256(keccak256(abi.encode(rngWord, player, amount)));
        uint24 targetLevel = _rollTargetLevel(currentLevel, seed);

        uint256 evMultiplierBps = _lootboxEvMultiplierFromScore(uint256(activityScore));
        uint256 scaledAmount = _applyEvMultiplierWithCap(player, currentLevel, amount, evMultiplierBps);

        // Each chunk emits its own itemized LootBoxOpened so the per-chunk FLIP datum (otherwise
        // lost in the commingled creditFlip) is recoverable — every box, including a redemption
        // chunk, leaves exactly one settlement event. payColdBustConsolation stays false (no WWXRP
        // on a redemption cold-bust).
        // allowEthSpin=true: redemption credits the pool to storage before this loop, so each
        // chunk's ETH-spin reads/writes fresh storage — no deferred memory-accumulator to race.
        _resolveLootboxCommon(
            player,
            0,
            scaledAmount,
            targetLevel,
            currentLevel,
            seed,
            false,
            0,
            0,
            true,
            activityScore,
            true
        );
    }

    /// @notice Credit the direct half of an sDGNRS redemption claim to `player`'s claimable winnings.
    /// @dev Delegatecall target of the Game's creditRedemptionDirect stub, so msg.sender (sDGNRS),
    ///      msg.value, and address(this) (the Game) are all the caller's. The value arrives with the
    ///      same funding mix as resolveRedemptionLootbox — msg.value covers 0..amount and the rest is
    ///      pulled as stETH (sDGNRS pre-approves GAME for max) — so a mid-game ETH-depleted sDGNRS
    ///      still settles. The credit rides the claimable reserve (claimablePool in tandem); the
    ///      arriving value backs it and the player withdraws via the access-gated claimWinnings.
    /// @param player Claimant credited.
    /// @param amount Total direct-half value (msg.value ETH + the stETH remainder pulled here).
    function creditRedemptionDirect(address player, uint256 amount) external payable {
        if (msg.sender != ContractAddresses.SDGNRS) revert OnlySDGNRS();
        if (msg.value > amount) revert MsgValueExceedsAmount();
        if (amount == 0) return;
        uint256 stethPortion;
        unchecked { stethPortion = amount - msg.value; }
        if (stethPortion != 0) {
            if (!steth.transferFrom(msg.sender, address(this), stethPortion)) revert TransferFailed();
        }
        _creditClaimable(player, amount);
        claimablePool += uint128(amount);
    }

    /// @notice Resolve an AfKing-subscription box at the LIVE level from a caller-passed
    ///         frozen-day word.
    /// @dev The afking open route: the LIVE-LEVEL twin of `resolveLootboxDirect` — identical
    ///      resolution shape (derive the seed, roll the target level from the LIVE level, do
    ///      the SINGLE `_applyEvMultiplierWithCap` RMW at open, then `_resolveLootboxCommon`)
    ///      — with exactly TWO deviations from `resolveLootboxDirect`:
    ///
    ///        1. the RNG `rngWord` is a CALLER-PASSED param (the GameAfkingModule open-leg
    ///           passes the frozen stamp day's word), NOT read from any index-keyed map; and
    ///        2. the seed `day` is the FROZEN stamped process day (a passed param), NOT the
    ///           live `_simulatedDayIndex()` — the day MUST stay frozen in the seed or a
    ///           self-keepering player could grind the seed by open-timing.
    ///
    ///      Everything else is IDENTICAL to `resolveLootboxDirect`: `currentLevel = level +
    ///      1` LIVE, `targetLevel = _rollTargetLevel(currentLevel, seed)` rolls from the LIVE
    ///      level (NO stored baseLevel floor — auto-open removes the player's ability to time
    ///      the level, so the level freeze is unnecessary),
    ///      and the SINGLE `_applyEvMultiplierWithCap(player, currentLevel, amount,
    ///      evMultiplierBps)` RMW — the sole residual live-read, a benign monotonic
    ///      down-clamp, keyed on the SAME per-level window of
    ///      `lootboxEvCapPacked[player]` the human buy-time write uses
    ///      so the human + afking boxes share the one per-level 10-ETH EV budget.
    ///      The buy-time EV write is bypassed for afking boxes (the process pass STAMPS only),
    ///      so this is the single draw (no double-draw). The cap hard-clamps at 10 ETH with the
    ///      no-write 100%-EV short-circuit ⇒ NO revert. The seed carries ZERO `block.*`
    ///      entropy.
    ///
    ///      Boons OFF for afking boxes ⇒ `amount` IS the spend exactly (there is no
    ///      boosted-amount freeze field — the stamped `amount` is the unboosted box value).
    ///      The boon/pass ROLL inside `_resolveLootboxCommon` still runs on every ETH-lootbox
    ///      path (gated by real game-state, identical to the auto-resolve callers); the
    ///      boons-off rule governs the AMOUNT field, not the roll.
    ///
    ///      Tail flags match the HUMAN box open (`_openLootBoxLeg`) for outcome parity (an afking box must be
    ///      identical to a normal box in every way that matters): it emits the `LootBoxOpened`
    ///      summary like any box open, and `payColdBustConsolation = true` (a
    ///      bust pays the same WWXRP consolation a human box does). The ONE intentional
    ///      exception is the distress bonus — `distressEth = 0` / `totalPackedEth = 0`: the
    ///      human value is frozen at buy in the packed lootboxEth distress field, which the
    ///      stamp-only afking box never writes. Deliberately omitted as a mega-niche
    ///      end-game feature (active only the final day before game-over, by which point
    ///      afking subscribers are gone). No `RngNotReady` guard here — the caller (the
    ///      GameAfkingModule open leg `_autoOpen`) pre-gates on a landed `rngWordByDay[day] != 0`,
    ///      so a zero word never reaches this function. Sole caller: the GameAfkingModule open-leg, via the
    ///      GAME_LOOTBOX_MODULE delegatecall (the box materialization is private to this
    ///      module — `resolveAfkingBox` is the one freeze-correct seam; `resolveLootboxDirect`
    ///      derives the seed from the LIVE day and would not freeze the seed `day`).
    /// @param player Box owner (resolved by the GameAfkingModule open-leg from the sub).
    /// @param amount The stamped spend in wei (boons OFF ⇒ amount == spend).
    /// @param day The boundary-pinned PROCESS day stamped at process (frozen in the seed).
    /// @param rngWord The frozen stamp day's word `rngWordByDay[day]`, passed by the caller.
    /// @param activityScore The stamped activity score in whole points (the FROZEN EV input).
    function resolveAfkingBox(
        address player,
        uint256 amount,
        uint24 day,
        uint256 rngWord,
        uint16 activityScore
    ) external {
        if (amount == 0) return;

        // Byte-identical to the human box open (`_openLootBoxLeg`) / resolveLootboxDirect: the
        // abi.encode preimage — with the FROZEN stamped `day` (prevents seed-grinding by
        // open-timing) and the CALLER-PASSED frozen-day word `rngWordByDay[day]`.
        uint256 seed = uint256(keccak256(abi.encode(rngWord, player, day, amount)));

        // LIVE level, exactly like resolveLootboxDirect: auto-open removes the
        // player's ability to time the level, so the box rolls from the live level with
        // NO stored baseLevel floor.
        uint24 currentLevel = level + 1;
        uint24 targetLevel = _rollTargetLevel(currentLevel, seed);

        // The SINGLE EV-cap RMW at open — the sole residual live-read, a benign
        // monotonic down-clamp, keyed [player][currentLevel] on the SAME
        // per-level 10-ETH budget map the human buy-time write uses. Fed the FROZEN
        // evMultiplierBps from the stamped activityScore. Hard-clamped, no revert.
        uint256 evMultiplierBps = _lootboxEvMultiplierFromScore(uint256(activityScore));
        uint256 scaledAmount = _applyEvMultiplierWithCap(player, currentLevel, amount, evMultiplierBps);

        _resolveLootboxCommon(
            player,
            0,
            scaledAmount,
            targetLevel,
            currentLevel,
            seed,
            true,
            0,
            0,
            false,
            activityScore,
            true
        );
    }

    // =========================================================================
    // Deity Boon Functions
    // =========================================================================

    /// @notice Issue a deity boon to a recipient
    /// @dev Deity can issue up to 3 boons per day, one per recipient per day.
    ///      A deity can issue at most DEITY_RECIPIENT_BOON_CAP boons to any one
    ///      recipient over the game's lifetime.
    /// @param deity The deity pass holder issuing the boon
    /// @param recipient The player receiving the boon
    /// @param slot The slot index (0-2) to use
    /// @custom:reverts ZeroAddress When deity or recipient is zero address
    /// @custom:reverts SelfBoon When deity tries to issue boon to themselves
    /// @custom:reverts InvalidSlot When slot is >= 3
    /// @custom:reverts Unauthorized When deity does not own a deity pass
    /// @custom:reverts RngNotReady When no RNG is available for the day
    /// @custom:reverts RecipientAlreadyBoonedToday When recipient already received a boon today
    /// @custom:reverts RecipientBoonCapReached When this deity has hit the lifetime boon cap for the recipient
    /// @custom:reverts SlotAlreadyUsed When slot was already used today
    function issueDeityBoon(address deity, address recipient, uint8 slot) external {
        if (deity == address(0) || recipient == address(0)) revert ZeroAddress();
        if (deity == recipient) revert SelfBoon();
        if (slot >= DEITY_DAILY_BOON_COUNT) revert InvalidSlot();
        if (mintPacked_[deity] >> BitPackingLib.HAS_DEITY_PASS_SHIFT & 1 == 0) revert Unauthorized();

        uint24 day = _simulatedDayIndex();
        uint256 rngWord = rngWordByDay[day];
        if (rngWord == 0) revert RngNotReady();
        // Day + used-mask share one slot (deityBoonPacked). On a day rollover the mask
        // starts empty: a stale day's mask is never read (every reader gates on the day
        // matching), and the single packed write below re-stamps the day with the fresh
        // mask in one store.
        uint32 boonPacked = deityBoonPacked[deity];
        uint8 mask = uint24(boonPacked) == day ? uint8(boonPacked >> 24) : 0;
        // One boon per recipient per day, across all deities.
        if (deityBoonRecipientDay[recipient] == day) revert RecipientAlreadyBoonedToday();
        // Lifetime cap is per (deity, recipient) pair.
        uint8 pairBoonCount = deityRecipientBoonCount[deity][recipient];
        if (pairBoonCount >= DEITY_RECIPIENT_BOON_CAP) revert RecipientBoonCapReached();

        uint8 slotMask = uint8(1) << slot;
        if ((mask & slotMask) != 0) revert SlotAlreadyUsed();
        deityBoonPacked[deity] =
            uint32(day) |
            (uint32(mask | slotMask) << 24);
        deityBoonRecipientDay[recipient] = day;
        deityRecipientBoonCount[deity][recipient] = pairBoonCount + 1;

        bool decimatorAllowed = _isDecimatorWindow();
        bool deityPassAvailable = deityPassOwners.length < DEITY_PASS_MAX_TOTAL;
        uint8 boonType = _deityBoonForSlot(deity, day, slot, decimatorAllowed, deityPassAvailable, rngWord);
        _applyBoon(recipient, boonType, day, day, 0, true);

        emit DeityBoonIssued(deity, recipient, day, slot, boonType);
    }

    // =========================================================================
    // Internal Helper Functions
    // =========================================================================

    /// @dev Roll a target level for lootbox resolution.
    ///      80% chance: 0-4 levels above base. 20% chance: 5-50 levels above base.
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
        if (rangeRoll < 20) {
            // 20% chance: far future (5-50 levels ahead)
            uint256 farOffset = uint16(seed >> 24) % 46;
            targetLevel = baseLevel + uint24(farOffset + 5);
        } else {
            // 80% chance: near future (0-4 levels ahead)
            uint256 nearOffset = uint8(seed >> 16) % 5;
            targetLevel = baseLevel + uint24(nearOffset);
        }
    }

    /// @dev Computes the lootbox value allocated to the boon/pass draw: a fixed BPS of
    ///      the resolution amount, capped at `LOOTBOX_BOON_MAX_BUDGET`.
    /// @param amount ETH-equivalent resolution amount
    /// @return boonBudget Amount allocated to the boon/pass draw
    function _lootboxBoonBudget(uint256 amount) private pure returns (uint256 boonBudget) {
        boonBudget = (amount * LOOTBOX_BOON_BUDGET_BPS) / 10_000;
        if (boonBudget > LOOTBOX_BOON_MAX_BUDGET) {
            boonBudget = LOOTBOX_BOON_MAX_BUDGET;
        }
    }

    /// @dev Common lootbox resolution logic shared by ETH and FLIP lootboxes.
    ///      Handles whale pass jackpots, lazy pass awards, ticket/FLIP rolls, and boons.
    /// @param player Player receiving rewards
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
    ///        bits[80..95]   varianceRoll % 20       (_resolveLootboxRoll large-FLIP)
    ///        bits[96..119]  ticketVariance % 10000  (_lootboxTicketCount)
    ///        bits[120..151] boon roll % BOON_PPM_SCALE (_rollLootboxBoons)
    ///        bits[224..255] fracRoundUp % 100      (_settleLootboxRoll ticket whole-collapse, per roll; uint32 window, bias ~2e-8)
    ///      Primary-chunk consumption: bits[0..151] (draws) + bits[224..255] (round-up); bits[152..223] free.
    ///      The split second roll uses seed2 = EntropyLib.hash2(seed, 1) (counter-tagged chunk 1,
    ///      collision-free vs primary chunk 0) for BOTH its reward draw AND its own re-rolled
    ///      target level (seed2 bits[0..39], unused by chunk 1's reward draw).
    ///      The Degenerette-spin rolls (WWXRP / FLIP-spins / ETH-spin) derive their sub-seeds
    ///      via hash2(seed, BOX_*_SPIN_TAG) — fresh tagged chunks that consume no primary bits.
    /// @param payColdBustConsolation Whether a ticket-path cold-bust (`whole == 0`) pays
    ///        the `LOOTBOX_WWXRP_CONSOLATION`; `true` for the manual caller `_openLootBoxLeg`
    ///        and `resolveAfkingBox`, `false` for the auto-resolve callers (`resolveLootboxDirect`,
    ///        `resolveRedemptionLootbox`), which stay silent on cold-bust
    /// @param distressEth Portion of lootbox ETH bought during distress mode (pre-EV-scaling basis)
    /// @param totalPackedEth Total packed lootbox ETH (pre-EV-scaling basis, denominator for distress fraction)
    /// @param allowSplit When true, a box over LOOTBOX_SPLIT_THRESHOLD resolves as two
    ///        independent rolls (the 2nd re-rolling its own target level); afking passes false
    ///        so afking boxes always resolve as a single roll (a bounded per-open cost).
    /// @param activityScore Frozen whole-point activity score threaded to the Degenerette spin rolls
    ///        (WWXRP / FLIP-spins / ETH-spin); identical to the score the box committed.
    /// @param allowEthSpin When false (recirc entry), the 5% ETH-spin roll awards tickets
    ///        instead — see `_resolveLootboxRoll`. Directly-opened boxes pass true.
    function _resolveLootboxCommon(
        address player,
        uint48 index,
        uint256 amount,
        uint24 targetLevel,
        uint24 currentLevel,
        uint256 seed,
        bool payColdBustConsolation,
        uint256 distressEth,
        uint256 totalPackedEth,
        bool allowSplit,
        uint16 activityScore,
        bool allowEthSpin
    ) private {
        uint256 boonBudget = _lootboxBoonBudget(amount);
        uint256 mainAmount = amount - boonBudget;
        uint256 amountFirst = mainAmount;
        uint256 amountSecond;
        // Boxes over the split threshold resolve as two independent rolls — UNLESS the caller
        // forbids it (afking boxes always resolve as one roll, for a bounded per-open cost).
        if (allowSplit && mainAmount > LOOTBOX_SPLIT_THRESHOLD) {
            amountFirst = mainAmount / 2;
            amountSecond = mainAmount - amountFirst;
        }

        // Box-level boon work runs ONCE (not per roll). Boons always roll on every ETH lootbox
        // path (the haircut above always pairs with a spent boon budget); pass-type boons stay
        // gated by real game-state inside the roll.
        _rollLootboxBoons(player, amount, boonBudget, currentLevel, seed);
        // consumeActivityBoon is a no-op unless a pending bonus is set; gate the BoonModule
        // delegatecall on a direct read of the (warm) pending field, skipping the call frame on
        // the common no-boon box.
        if (uint24(boonPacked[player].slot1 >> BP_ACTIVITY_PENDING_SHIFT) != 0) {
            (bool okAct, ) = ContractAddresses.GAME_BOON_MODULE.delegatecall(
                abi.encodeWithSelector(IDegenerusGameBoonModule.consumeActivityBoon.selector, player)
            );
            if (!okAct) revert EmptyRevert();
        }

        // Roll 1 settles at the caller-rolled `targetLevel` (from the primary seed).
        // A target >= base + 5 is a far-future roll (near offsets are 0-4), which weights
        // the ticket budget up.
        _settleLootboxRoll(
            player, index, amountFirst, amount, targetLevel, seed,
            payColdBustConsolation, distressEth, totalPackedEth,
            targetLevel >= currentLevel + 5, activityScore, allowEthSpin
        );

        // Roll 2 (split paths only) draws from the counter-tagged seed2 and RE-ROLLS its own
        // target level (seed2 bits[0..39], unused by roll 2's reward draw), so its tickets can
        // land at a different level than roll 1.
        if (amountSecond != 0) {
            uint256 seed2 = EntropyLib.hash2(seed, 1);
            uint24 level2 = _rollTargetLevel(currentLevel, seed2);
            _settleLootboxRoll(
                player, index, amountSecond, amount, level2, seed2,
                payColdBustConsolation, distressEth, totalPackedEth,
                level2 >= currentLevel + 5, activityScore, allowEthSpin
            );
        }
    }

    /// @dev Settle ONE reward roll: the reward-type draw, then (for a ticket roll) the distress
    ///      bonus + single Bernoulli whole-collapse + queue at `rollLevel`, the whole-FLIP
    ///      floor + creditFlip, and one LootBoxOpened. `fullAmount` (the box's pre-split amount)
    ///      feeds the reward calc and the event's amount field, so an UNSPLIT box settles and
    ///      emits exactly as a single combined resolution did; a split box runs this twice, each
    ///      half at its own re-rolled level with its own event.
    /// @param rollAmount This roll's ETH chunk (the whole main amount, or one split half).
    /// @param fullAmount The box's full ETH-equivalent amount (reward basis + event amount).
    /// @param rollLevel The target level this roll's tickets queue at.
    /// @param rollSeed This roll's seed (primary `seed` for roll 1, `seed2` for roll 2).
    /// @param isFarFuture True when rollLevel is far-future (>= base + 5) — weights the ticket budget.
    function _settleLootboxRoll(
        address player,
        uint48 index,
        uint256 rollAmount,
        uint256 fullAmount,
        uint24 rollLevel,
        uint256 rollSeed,
        bool payColdBustConsolation,
        uint256 distressEth,
        uint256 totalPackedEth,
        bool isFarFuture,
        uint16 activityScore,
        bool allowEthSpin
    ) private {
        if (rollAmount == 0) return;
        // priceForLevel returns a non-zero constant for every level, so targetPrice is
        // always a safe divisor downstream. It prices the TICKET legs (the level the
        // tickets queue at); the FLIP legs derive their own next-level price inside
        // _largeFlipOut.
        uint256 targetPrice = PriceLookupLib.priceForLevel(rollLevel);

        (uint256 flipOut, uint32 scaledWholeTickets, bool wasSpin) =
            _resolveLootboxRoll(player, rollAmount, fullAmount, targetPrice, rollSeed, isFarFuture, activityScore, allowEthSpin);

        // Floored to whole-FLIP (1 FLIP = 1 ether); sub-1-FLIP residue evaporates.
        uint256 flipAmount = (flipOut / 1 ether) * 1 ether;

        bool roundedUp;
        if (scaledWholeTickets != 0) {
            // Distress-mode ticket bonus: 25% extra on the distress-bought fraction.
            if (distressEth != 0 && totalPackedEth != 0) {
                uint256 bonus = (uint256(scaledWholeTickets) * distressEth * DISTRESS_TICKET_BONUS_BPS)
                    / (totalPackedEth * 10_000);
                if (bonus != 0) {
                    // Saturate at the uint32 ceiling instead of wrapping (see _lootboxTicketCount).
                    uint256 boosted = uint256(scaledWholeTickets) + bonus;
                    scaledWholeTickets = boosted > type(uint32).max ? type(uint32).max : uint32(boosted);
                }
            }
            // Collapse scaled tickets to whole via a single Bernoulli round-up on bits[224..255]
            // of THIS roll's seed — a uint32 window, negligible % QTY_SCALE modulo bias (~2e-8);
            // `scaledWholeTickets` stays at the scaled value for the event emit.
            uint32 whole = scaledWholeTickets / uint32(QTY_SCALE);
            uint32 frac = scaledWholeTickets % uint32(QTY_SCALE);
            if (frac != 0 && (uint32(rollSeed >> 224) % uint32(QTY_SCALE)) < frac) {
                unchecked { whole += 1; }
                roundedUp = true;
            }
            // `_queueEntries` early-returns on `whole == 0`. The manual caller (`_openLootBoxLeg`)
            // pays the WWXRP cold-bust consolation here; auto-resolve callers stay silent.
            _queueEntries(player, rollLevel, wholeTicketsToEntries(whole), false);
            if (payColdBustConsolation && whole == 0) {
                wwxrp.mintPrize(player, LOOTBOX_WWXRP_CONSOLATION);
            }
        }

        if (flipAmount != 0) {
            coinflip.creditFlip(player, flipAmount);
        }

        // Every box roll emits exactly one settlement event. Spin rolls (WWXRP / FLIP-spins /
        // ETH-spin) are recorded by their own single BoxSpin event from the Degenerette module, so
        // the (all-zero) LootBoxOpened is suppressed for them; every other roll emits LootBoxOpened.
        if (!wasSpin) {
            emit LootBoxOpened(
                player,
                index,
                fullAmount,
                rollLevel,
                scaledWholeTickets,
                flipAmount,
                roundedUp
            );
        }
    }

    /// @dev Roll for lootbox boons. Lootbox can award at most one boon.
    ///      If a boon is already active, only refresh or upgrade that same category.
    ///      Uses a single roll with granular ppm-based probability and deity-weighted pool.
    ///      Bit budget (consumed from `seed`):
    ///        - boon roll: bits[120..151] via uint32(seed >> 120) % BOON_PPM_SCALE (bias 0.022%; BOON_PPM_SCALE = 1_000_000)
    /// @param player Player address
    /// @param originalAmount Amount used for chance calculations
    /// @param boonBudget Amount of lootbox value allocated to boon/pass draw
    /// @param currentLevel Current game level (level + 1, threaded from the resolution caller)
    /// @param seed Per-resolution 256-bit keccak seed (sliced inline; no advance)
    function _rollLootboxBoons(
        address player,
        uint256 originalAmount,
        uint256 boonBudget,
        uint24 currentLevel,
        uint256 seed
    ) private {
        if (player == address(0) || originalAmount == 0) return;

        // Expiry cleanup is a no-op unless some boon bit is set (every clear branch is gated
        // on a non-zero tier/day field), so gate the BoonModule delegatecall on a direct read
        // of the two packed slots — the same SLOADs the sweep would do, minus the call frame
        // on the common no-boon box.
        BoonPacked storage bp = boonPacked[player];
        if (bp.slot0 != 0 || bp.slot1 != 0) {
            (bool okClr, ) = ContractAddresses.GAME_BOON_MODULE.delegatecall(
                abi.encodeWithSelector(IDegenerusGameBoonModule.checkAndClearExpiredBoon.selector, player)
            );
            if (!okClr) revert EmptyRevert();
        }

        uint24 currentDay = _simulatedDayIndex();

        uint256 lazyPassValue = _lazyPassPriceForLevel(currentLevel + 1);

        bool decimatorAllowed = _isDecimatorWindow();
        // The owner-count SLOAD stays short-circuited away when the player already
        // holds a deity pass; when read, the count is threaded into _boonPoolStats.
        uint256 deityPassCount;
        bool deityEligible;
        if (mintPacked_[player] >> BitPackingLib.HAS_DEITY_PASS_SHIFT & 1 == 0) {
            deityPassCount = deityPassOwners.length;
            deityEligible = deityPassCount < DEITY_PASS_MAX_TOTAL;
        }

        (uint256 totalWeight, uint256 avgMaxValue) = _boonPoolStats(
            decimatorAllowed,
            deityEligible,
            lazyPassValue,
            currentLevel,
            deityPassCount
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
            deityEligible
        );

        _applyBoon(player, boonType, 0, currentDay, originalAmount, false);
    }

    /// @dev Convert FLIP amount to ETH value using current price (`priceWei` is
    ///      always a non-zero price-table constant).
    function _flipToEthValue(
        uint256 flipAmount,
        uint256 priceWei
    ) private pure returns (uint256 valueWei) {
        if (flipAmount == 0) return 0;
        valueWei = (flipAmount * priceWei) / PRICE_COIN_UNIT;
    }

    /// @dev Activate a 100-level whale pass for a player by recording an O(1)
    ///      pending claim. Opens are uniform O(1) regardless of pass status.
    ///      Materialization (stats + 100 levels × tickets) is deferred to the
    ///      player-paid `claimWhalePass` endpoint, where the stats helper is
    ///      applied immediately after the read-then-zero of `whalePassClaims[player]`.
    function _activateWhalePass(address player) private {
        // O(1) record of one half-pass claim.
        whalePassClaims[player] += 1;
    }

    /// @dev Calculate total weight and average max boon value (in ETH) for EV budgeting.
    ///      The two pass-type boons (the whale-pass jackpot and the lazy-pass discount
    ///      awards) are always included; the lazy-pass weights are gated by a non-zero
    ///      `lazyPassValue` (real game-state).
    /// @param currentLevel Current game level (level + 1, threaded from the caller)
    /// @param deityPassCount Deity-pass owner count, loaded by the caller; meaningful
    ///        only when `deityEligible`
    function _boonPoolStats(
        bool decimatorAllowed,
        bool deityEligible,
        uint256 lazyPassValue,
        uint24 currentLevel,
        uint256 deityPassCount
    ) private pure returns (uint256 totalWeight, uint256 avgMaxValue) {
        uint256 weightedMax = 0;
        // currentLevel == level + 1, so this is the price at the stored `level`.
        uint256 priceWei = PriceLookupLib.priceForLevel(currentLevel - 1);

        // Coinflip boons (max bonus on 100k FLIP deposit)
        uint256 coinflipMax5 = _flipToEthValue(
            (COINFLIP_BOON_MAX_DEPOSIT * LOOTBOX_BOON_BONUS_BPS) / 10_000,
            priceWei
        );
        uint256 coinflipMax10 = _flipToEthValue(
            (COINFLIP_BOON_MAX_DEPOSIT * LOOTBOX_COINFLIP_10_BONUS_BPS) / 10_000,
            priceWei
        );
        uint256 coinflipMax25 = _flipToEthValue(
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
            uint256 decMax10 = _flipToEthValue(
                (DECIMATOR_BOON_CAP * LOOTBOX_DECIMATOR_10_BONUS_BPS) / 10_000,
                priceWei
            );
            uint256 decMax25 = _flipToEthValue(
                (DECIMATOR_BOON_CAP * LOOTBOX_DECIMATOR_25_BONUS_BPS) / 10_000,
                priceWei
            );
            uint256 decMax50 = _flipToEthValue(
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

        // Whale discount boons (10/20/35% off standard price)
        uint256 whaleMax10 = (WHALE_PASS_STANDARD_PRICE * LOOTBOX_WHALE_BOON_DISCOUNT_10_BPS) / 10_000;
        uint256 whaleMax25 = (WHALE_PASS_STANDARD_PRICE * LOOTBOX_WHALE_BOON_DISCOUNT_25_BPS) / 10_000;
        uint256 whaleMax50 = (WHALE_PASS_STANDARD_PRICE * LOOTBOX_WHALE_BOON_DISCOUNT_50_BPS) / 10_000;
        totalWeight += BOON_WEIGHT_WHALE_10;
        weightedMax += BOON_WEIGHT_WHALE_10 * whaleMax10;
        totalWeight += BOON_WEIGHT_WHALE_25;
        weightedMax += BOON_WEIGHT_WHALE_25 * whaleMax25;
        totalWeight += BOON_WEIGHT_WHALE_50;
        weightedMax += BOON_WEIGHT_WHALE_50 * whaleMax50;

        // Deity pass discount boons (if eligible)
        if (deityEligible) {
            uint256 k = deityPassCount;
            uint256 deityPrice = DEITY_PASS_BASE + (k * (k + 1) * 1 ether) / 2;
            uint256 deityMax10 = (deityPrice * 1000) / 10_000;
            uint256 deityMax25 = (deityPrice * 2000) / 10_000;
            uint256 deityMax50 = (deityPrice * 3500) / 10_000;
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

        // Quest-streak-shield boon (value assumed 0 for EV budgeting, like activity)
        totalWeight += BOON_WEIGHT_QUEST_SHIELD;

        // Pass awards (now eligible on every ETH lootbox path)
        totalWeight += BOON_WEIGHT_WHALE_PASS;
        weightedMax += BOON_WEIGHT_WHALE_PASS * LOOTBOX_WHALE_PASS_PRICE;
        if (lazyPassValue != 0) {
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
    ///      The two pass-type boons (the whale-pass jackpot and the lazy-pass discount
    ///      awards) are always reachable; weight inclusion is handled in `_boonPoolStats`.
    function _boonFromRoll(
        uint256 roll,
        bool decimatorAllowed,
        bool deityEligible
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
        cursor += BOON_WEIGHT_QUEST_SHIELD;
        if (roll < cursor) return BOON_QUEST_SHIELD;
        cursor += BOON_WEIGHT_WHALE_PASS;
        if (roll < cursor) return BOON_WHALE_PASS;
        cursor += BOON_WEIGHT_LAZY_PASS_10;
        if (roll < cursor) return BOON_LAZY_PASS_10;
        cursor += BOON_WEIGHT_LAZY_PASS_25;
        if (roll < cursor) return BOON_LAZY_PASS_25;
        cursor += BOON_WEIGHT_LAZY_PASS_50;
        if (roll < cursor) return BOON_LAZY_PASS_50;
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
        uint24 day,
        uint24 currentDay,
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
            // Only a genuine tier upgrade applies the boon and (re)sets its expiry; an
            // ignored lower/equal-tier roll is a no-op and must not refresh the timer
            // (nor zero a held deity boon's same-day flag).
            if (newTier > existingTier) {
                s0 = (s0 & ~(uint256(BP_MASK_8) << BP_COINFLIP_TIER_SHIFT)) | (uint256(newTier) << BP_COINFLIP_TIER_SHIFT);
                // Set coinflipDay = currentDay
                s0 = (s0 & ~(uint256(BP_MASK_24) << BP_COINFLIP_DAY_SHIFT)) | (uint256(uint24(currentDay)) << BP_COINFLIP_DAY_SHIFT);
                // Set deityCoinflipDay = isDeity ? day : 0
                uint24 deityDayVal = isDeity ? uint24(day) : uint24(0);
                s0 = (s0 & ~(uint256(BP_MASK_24) << BP_DEITY_COINFLIP_DAY_SHIFT)) | (uint256(deityDayVal) << BP_DEITY_COINFLIP_DAY_SHIFT);
                bp.slot0 = s0;
            }
            if (!isDeity) emit LootBoxReward(player, 2, originalAmount, LOOTBOX_BOON_MAX_BONUS);
            return;
        }

        // Lootbox boost boons (types 5, 6, 22) — slot0, single tier field
        if (boonType == BOON_LOOTBOX_5 || boonType == BOON_LOOTBOX_15 || boonType == BOON_LOOTBOX_25) {
            uint8 newTier = boonType == BOON_LOOTBOX_25 ? uint8(3) :
                            (boonType == BOON_LOOTBOX_15 ? uint8(2) : uint8(1));
            BoonPacked storage bp = boonPacked[player];
            uint256 s0 = bp.slot0;
            uint8 existingTier = uint8(s0 >> BP_LOOTBOX_TIER_SHIFT);
            // Both deity and lootbox: upgrade semantics — keep higher tier
            uint8 activeTier = newTier > existingTier ? newTier : existingTier;
            // Only a genuine tier upgrade applies the boon and (re)sets its expiry; an
            // ignored lower/equal-tier roll is a no-op and must not refresh the timer.
            if (newTier > existingTier) {
                // Clear lootbox fields, set new values
                s0 = s0 & BP_LOOTBOX_CLEAR;
                s0 = s0 | (uint256(uint24(currentDay)) << BP_LOOTBOX_DAY_SHIFT);
                uint24 deityDayVal = isDeity ? uint24(day) : uint24(0);
                s0 = s0 | (uint256(deityDayVal) << BP_DEITY_LOOTBOX_DAY_SHIFT);
                s0 = s0 | (uint256(activeTier) << BP_LOOTBOX_TIER_SHIFT);
                bp.slot0 = s0;
            }
            if (!isDeity) {
                // Map active tier back to BPS and rewardType for event
                uint16 activeBps = _lootboxTierToBps(activeTier);
                uint8 rewardType = activeTier == 3 ? 6 : (activeTier == 2 ? 5 : 4);
                emit LootBoxReward(player, rewardType, originalAmount, activeBps);
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
            // Only a genuine tier upgrade applies the boon and (re)sets its expiry; an
            // ignored lower/equal-tier roll is a no-op and must not refresh the timer.
            if (newTier > existingTier) {
                s0 = (s0 & ~(uint256(BP_MASK_8) << BP_PURCHASE_TIER_SHIFT)) | (uint256(newTier) << BP_PURCHASE_TIER_SHIFT);
                // Set purchaseDay = currentDay
                s0 = (s0 & ~(uint256(BP_MASK_24) << BP_PURCHASE_DAY_SHIFT)) | (uint256(uint24(currentDay)) << BP_PURCHASE_DAY_SHIFT);
                // Set deityPurchaseDay
                uint24 deityDayVal = isDeity ? uint24(day) : uint24(0);
                s0 = (s0 & ~(uint256(BP_MASK_24) << BP_DEITY_PURCHASE_DAY_SHIFT)) | (uint256(deityDayVal) << BP_DEITY_PURCHASE_DAY_SHIFT);
                bp.slot0 = s0;
            }
            if (!isDeity) {
                uint8 rewardType = bps == LOOTBOX_PURCHASE_BOOST_25_BONUS_BPS
                    ? 6 : (bps == LOOTBOX_PURCHASE_BOOST_15_BONUS_BPS ? 5 : 4);
                emit LootBoxReward(player, rewardType, originalAmount, bps);
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
            // Only a genuine tier upgrade applies the boon and (re)sets its deity-day; an
            // ignored lower/equal-tier roll is a no-op and must not zero a held deity boon.
            if (newTier > existingTier) {
                s0 = (s0 & ~(uint256(BP_MASK_8) << BP_DECIMATOR_TIER_SHIFT)) | (uint256(newTier) << BP_DECIMATOR_TIER_SHIFT);
                // Set deityDecimatorDay (no award day for decimator)
                uint24 deityDayVal = isDeity ? uint24(day) : uint24(0);
                s0 = (s0 & ~(uint256(BP_MASK_24) << BP_DEITY_DECIMATOR_DAY_SHIFT)) | (uint256(deityDayVal) << BP_DEITY_DECIMATOR_DAY_SHIFT);
                bp.slot0 = s0;
            }
            if (!isDeity) emit LootBoxReward(player, 8, originalAmount, bps);
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
            // Only a genuine tier upgrade applies the boon and (re)sets its expiry; an
            // ignored lower/equal-tier roll is a no-op and must not refresh the timer.
            if (newTier > existingTier) {
                s0 = (s0 & ~(uint256(BP_MASK_8) << BP_WHALE_TIER_SHIFT)) | (uint256(newTier) << BP_WHALE_TIER_SHIFT);
                // whaleDay = isDeity ? day : currentDay
                uint24 whaleDayVal = isDeity ? uint24(day) : uint24(currentDay);
                s0 = (s0 & ~(uint256(BP_MASK_24) << BP_WHALE_DAY_SHIFT)) | (uint256(whaleDayVal) << BP_WHALE_DAY_SHIFT);
                // deityWhaleDay = isDeity ? day : 0
                uint24 deityDayVal = isDeity ? uint24(day) : uint24(0);
                s0 = (s0 & ~(uint256(BP_MASK_24) << BP_DEITY_WHALE_DAY_SHIFT)) | (uint256(deityDayVal) << BP_DEITY_WHALE_DAY_SHIFT);
                bp.slot0 = s0;
            }
            if (!isDeity) emit LootBoxReward(player, 9, originalAmount, bps);
            return;
        }

        // Quest-streak-shield boon (type 4) — instant grant, no boon-mapping state.
        // Runs in GAME's delegatecall context, so the call to QUESTS is GAME-authorized.
        if (boonType == BOON_QUEST_SHIELD) {
            IDegenerusQuests(ContractAddresses.QUESTS).awardQuestStreakShield(player, LOOTBOX_QUEST_SHIELD_GRANT);
            if (!isDeity) emit LootBoxReward(player, 12, originalAmount, LOOTBOX_QUEST_SHIELD_GRANT);
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
            // Only a genuine increase applies the boon and (re)sets its expiry; an ignored
            // lower/equal roll is a no-op and must not refresh the timer.
            if (amt > existingAmt) {
                s1 = (s1 & ~(uint256(BP_MASK_24) << BP_ACTIVITY_PENDING_SHIFT)) | (uint256(amt) << BP_ACTIVITY_PENDING_SHIFT);
                // Set activityDay = currentDay
                s1 = (s1 & ~(uint256(BP_MASK_24) << BP_ACTIVITY_DAY_SHIFT)) | (uint256(uint24(currentDay)) << BP_ACTIVITY_DAY_SHIFT);
                // Set deityActivityDay
                uint24 deityDayVal = isDeity ? uint24(day) : uint24(0);
                s1 = (s1 & ~(uint256(BP_MASK_24) << BP_DEITY_ACTIVITY_DAY_SHIFT)) | (uint256(deityDayVal) << BP_DEITY_ACTIVITY_DAY_SHIFT);
                bp.slot1 = s1;
            }
            if (!isDeity) emit LootBoxReward(player, 10, originalAmount, amt);
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
            // Only a genuine tier upgrade applies the boon and (re)sets its expiry; an
            // ignored lower/equal-tier roll is a no-op and must not refresh the timer.
            if (tier > existingTier) {
                s1 = (s1 & ~(uint256(BP_MASK_8) << BP_DEITY_PASS_TIER_SHIFT)) | (uint256(tier) << BP_DEITY_PASS_TIER_SHIFT);
                // Set deityPassDay = currentDay
                s1 = (s1 & ~(uint256(BP_MASK_24) << BP_DEITY_PASS_DAY_SHIFT)) | (uint256(uint24(currentDay)) << BP_DEITY_PASS_DAY_SHIFT);
                // Set deityDeityPassDay
                uint24 deityDayVal = isDeity ? uint24(day) : uint24(0);
                s1 = (s1 & ~(uint256(BP_MASK_24) << BP_DEITY_DEITY_PASS_DAY_SHIFT)) | (uint256(deityDayVal) << BP_DEITY_DEITY_PASS_DAY_SHIFT);
                bp.slot1 = s1;
            }
            if (!isDeity) {
                uint16 bps = tier == DEITY_PASS_BOON_TIER_50 ? 3500 : (tier == DEITY_PASS_BOON_TIER_25 ? 2000 : 1000);
                emit LootBoxReward(player, 10, originalAmount, bps);
            }
            return;
        }

        // Whale pass (type 28) — no boon mapping access, delegates to _activateWhalePass
        if (boonType == BOON_WHALE_PASS) {
            _activateWhalePass(player);
            if (!isDeity) {
                // `level + 1` records the level AT BOX-OPEN TIME for indexers;
                // actual ticket queuing is deferred to claim-time, so the queued
                // tickets start at the level when the player calls claimWhalePass —
                // not necessarily `level + 1` here.
                emit LootBoxWhalePassJackpot(player, originalAmount, level + 1, WHALE_PASS_ENTRIES_PER_LEVEL, 0, 0);
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
            // Only a genuine tier upgrade applies the boon and (re)sets its expiry; an
            // ignored lower/equal-tier roll is a no-op and must not refresh the timer.
            if (newTier > existingTier) {
                s1 = (s1 & ~(uint256(BP_MASK_8) << BP_LAZY_PASS_TIER_SHIFT)) | (uint256(newTier) << BP_LAZY_PASS_TIER_SHIFT);
                // lazyPassDay = isDeity ? day : currentDay
                uint24 lazyDayVal = isDeity ? uint24(day) : uint24(currentDay);
                s1 = (s1 & ~(uint256(BP_MASK_24) << BP_LAZY_PASS_DAY_SHIFT)) | (uint256(lazyDayVal) << BP_LAZY_PASS_DAY_SHIFT);
                // deityLazyPassDay = isDeity ? day : 0
                uint24 deityDayVal = isDeity ? uint24(day) : uint24(0);
                s1 = (s1 & ~(uint256(BP_MASK_24) << BP_DEITY_LAZY_PASS_DAY_SHIFT)) | (uint256(deityDayVal) << BP_DEITY_LAZY_PASS_DAY_SHIFT);
                bp.slot1 = s1;
            }
            if (!isDeity) emit LootBoxReward(player, 11, originalAmount, bps);
        }
    }

    /// @dev Resolve a single lootbox roll to determine reward type. Split (roll % 20):
    ///      40% tickets, 15% DGNRS, 15% WWXRP-spin, 15% FLIP (flat),
    ///      10% FLIP-spins ×3, 5% ETH-spin. The three spin rolls dispatch into the
    ///      Degenerette module; their sub-seeds are hash2-tagged off `seed` (no primary-
    ///      chunk bits consumed). The ETH-spin only fires on directly-opened boxes
    ///      (`allowEthSpin`); on recirc boxes roll 19 awards tickets instead, which keeps
    ///      every box resolved inside `resolveDegeneretteBets` (the only ETH-pool memory-accumulator
    ///      context) free of an ETH-pool read-modify-write.
    /// @param player Player receiving the reward
    /// @param amount Amount for this roll (may be half of total for split lootboxes)
    /// @param lootboxAmount Total lootbox amount (for events)
    /// @param targetPrice Price at the rolled target level (ticket legs only)
    /// @param seed Per-resolution 256-bit keccak seed (sliced inline; first invocation uses primary chunk, ETH-amount-second branch uses seed2 = EntropyLib.hash2(seed, 1))
    /// @param isFarFuture True when this roll's target level is far-future (>= base + 5),
    ///        weighting the ticket budget up (1.5x) vs near (0.875x).
    /// @param activityScore Frozen whole-point activity score threaded from the box commitment;
    ///        scales the spin ROI / EV exactly as a regular bet's snapshot does.
    /// @param allowEthSpin When false (recirc boxes), roll 19 awards tickets instead of an
    ///        ETH spin — no ETH-pool RMW can race a deferred `resolveDegeneretteBets` pool flush.
    /// @return flipOut FLIP tokens to award
    /// @return ticketsOut Tickets to queue for future level
    /// @dev Bit budget (consumed from `seed`):
    ///        - pathRoll: bits[40..55]     via uint16(seed >> 40) % 20  (bias 0.02%)
    ///        - DGNRS tier sub-call slice: bits[56..79] (consumed by _lootboxDgnrsReward)
    ///        - large-FLIP varianceRoll: bits[80..95]   via uint16(seed >> 80) % 20  (bias 0.02%)
    ///      Spin sub-seeds use hash2-tagged chunks (BOX_*_SPIN_TAG), counter-tagged and
    ///      collision-free vs the primary chunk, so they consume no additional primary bits.
    function _resolveLootboxRoll(
        address player,
        uint256 amount,
        uint256 lootboxAmount,
        uint256 targetPrice,
        uint256 seed,
        bool isFarFuture,
        uint16 activityScore,
        bool allowEthSpin
    )
        private
        returns (uint256 flipOut, uint32 ticketsOut, bool wasSpin)
    {
        if (amount == 0) return (0, 0, false);

        uint256 roll = uint16(seed >> 40) % 20;
        if (roll < 8) {
            // 40% chance: tickets (returned as scaled × QTY_SCALE).
            ticketsOut = _lootboxTicketCount(
                _ticketBudget(amount, isFarFuture),
                targetPrice,
                seed
            );
        } else if (roll < 11) {
            // 15% chance: DGNRS tokens
            uint256 dgnrsAmount = _lootboxDgnrsReward(amount, seed);
            if (dgnrsAmount != 0) {
                uint256 paid = _creditDgnrsReward(player, dgnrsAmount);
                if (paid != 0) {
                    emit LootBoxDgnrsReward(
                        player,
                        lootboxAmount,
                        paid
                    );
                }
            }
        } else if (roll < 14) {
            // 15% chance: one WWXRP Degenerette spin staking the standard WWXRP prize.
            _callWwxrpSpin(
                player,
                LOOTBOX_WWXRP_PRIZE,
                activityScore,
                EntropyLib.hash2(seed, BOX_WWXRP_SPIN_TAG)
            );
            wasSpin = true;
        } else if (roll < 17) {
            // 15% chance: large FLIP reward with variance (flat → creditFlip).
            flipOut = _largeFlipOut(amount, seed);
        } else if (roll < 19) {
            // 10% chance: three FLIP Degenerette spins under one survival flip. Stake = the
            // would-be large FLIP haircut to 70.60% (LOOTBOX_FLIP_SPINS_STAKE_BPS). Mint-only
            // (no pool / recirc) → safe on every box path.
            uint256 stake = (_largeFlipOut(amount, seed) *
                LOOTBOX_FLIP_SPINS_STAKE_BPS) / 10_000;
            if (stake != 0) {
                _callFlipSpins(
                    player,
                    stake,
                    activityScore,
                    EntropyLib.hash2(seed, BOX_FLIP_SPIN_TAG)
                );
                wasSpin = true;
            }
        } else {
            // 5% chance: one ETH Degenerette spin (direct boxes only). On recirc boxes
            // (allowEthSpin=false) this awards tickets instead, so no ETH-pool RMW occurs
            // inside a deferred-flush context. Stake = the ticket budget it replaces
            // (EV-equal to those tickets), in wei.
            if (allowEthSpin) {
                uint256 ethStake = (_ticketBudget(amount, isFarFuture) *
                    _ticketVarianceBps(seed)) / 10_000;
                if (ethStake != 0) {
                    _callEthSpin(
                        player,
                        ethStake,
                        activityScore,
                        EntropyLib.hash2(seed, BOX_ETH_SPIN_TAG)
                    );
                    wasSpin = true;
                }
            } else {
                ticketsOut = _lootboxTicketCount(
                    _ticketBudget(amount, isFarFuture),
                    targetPrice,
                    seed
                );
            }
        }
    }

    /// @dev The ticket-roll ETH budget: the base ticket-roll BPS of `amount`, weighted by the
    ///      far/near target-distance factor. Shared by the ticket roll and the ETH-spin stake
    ///      (which is EV-equal to the tickets roll 19 replaces).
    function _ticketBudget(uint256 amount, bool isFarFuture)
        private
        pure
        returns (uint256)
    {
        uint256 ticketBudget = (amount * LOOTBOX_TICKET_ROLL_BPS) / 10_000;
        return
            (ticketBudget *
                (isFarFuture
                    ? LOOTBOX_TICKET_FAR_BUDGET_BPS
                    : LOOTBOX_TICKET_NEAR_BUDGET_BPS)) / 10_000;
    }

    /// @dev The large-FLIP output for a roll: variance-tiered BPS of `amount`, converted to
    ///      FLIP at the next-level ticket price (the box's own denomination) — FLIP is
    ///      level-less and spends at the live peg, so the rolled ticket level plays no part.
    ///      Shared by the flat FLIP roll and the FLIP-spins stake.
    function _largeFlipOut(
        uint256 amount,
        uint256 seed
    ) private view returns (uint256) {
        uint256 varianceRoll = uint16(seed >> 80) % 20;
        uint256 largeFlipBps;
        if (varianceRoll < 16) {
            // Low path (80%): rolls 0-15, 43.88%-97.88% of value
            largeFlipBps = LOOTBOX_LARGE_FLIP_LOW_BASE_BPS +
                varianceRoll * LOOTBOX_LARGE_FLIP_LOW_STEP_BPS;
        } else {
            // High path (20%): rolls 16-19, 231.99%-445.74% of value
            largeFlipBps = LOOTBOX_LARGE_FLIP_HIGH_BASE_BPS +
                (varianceRoll - 16) * LOOTBOX_LARGE_FLIP_HIGH_STEP_BPS;
        }
        uint256 flipBudget = (amount * largeFlipBps) / 10_000;
        return
            (flipBudget * PRICE_COIN_UNIT) /
            PriceLookupLib.priceForLevel(level + 1);
    }

    /// @dev Delegatecall the Degenerette module's WWXRP box-spin resolver (Game storage context).
    function _callWwxrpSpin(
        address player,
        uint256 stake,
        uint16 activityScore,
        uint256 seed
    ) private {
        (bool ok, ) = ContractAddresses.GAME_DEGENERETTE_MODULE.delegatecall(
            abi.encodeWithSelector(
                IDegenerusGameDegeneretteModule.resolveWwxrpSpinFromBox.selector,
                player,
                stake,
                activityScore,
                seed,
                uint32(0)
            )
        );
        if (!ok) revert EmptyRevert();
    }

    /// @dev Delegatecall the Degenerette module's triple-FLIP box-spin resolver.
    function _callFlipSpins(
        address player,
        uint256 stake,
        uint16 activityScore,
        uint256 seed
    ) private {
        (bool ok, ) = ContractAddresses.GAME_DEGENERETTE_MODULE.delegatecall(
            abi.encodeWithSelector(
                IDegenerusGameDegeneretteModule.resolveFlipSpinsFromBox.selector,
                player,
                stake,
                activityScore,
                seed,
                uint32(0)
            )
        );
        if (!ok) revert EmptyRevert();
    }

    /// @dev Delegatecall the Degenerette module's ETH box-spin resolver.
    function _callEthSpin(
        address player,
        uint256 stake,
        uint16 activityScore,
        uint256 seed
    ) private {
        (bool ok, ) = ContractAddresses.GAME_DEGENERETTE_MODULE.delegatecall(
            abi.encodeWithSelector(
                IDegenerusGameDegeneretteModule.resolveEthSpinFromBox.selector,
                player,
                stake,
                activityScore,
                seed,
                uint32(0)
            )
        );
        if (!ok) revert EmptyRevert();
    }

    /// @dev Calculate scaled ticket count from budget with ranged variance tiers.
    ///      Returns count × QTY_SCALE (100) for fractional ticket support. The tier
    ///      chances are 1% / 4% / 20% / 45% / 30%, and each tier draws a multiplier
    ///      uniformly across a symmetric BPS band about its per-tier mean; the overall
    ///      variance EV is ~0.941x:
    ///        1% -> 4.00x-6.50x, 4% -> 2.00x-3.50x, 20% -> 1.00x-1.60x,
    ///        45% -> 0.5923x-0.9923x, 30% -> 0.360x-0.720x.
    ///      The within-tier position reuses the SAME varianceRoll that selects the tier
    ///      (uniform within the tier's chance window), so no extra entropy is drawn.
    ///      Bit budget (consumed from `seed`):
    ///        - varianceRoll: bits[96..119] via uint24(seed >> 96) % 10_000 (bias 0.045%)
    /// @param budgetWei ETH budget for tickets
    /// @param priceWei Price per ticket at target level (a non-zero price-table constant)
    /// @param seed Per-resolution 256-bit keccak seed (sliced inline; no advance)
    /// @return scaledWholeTickets Scaled whole-ticket count (whole x QTY_SCALE), collapsed to entries at queue via wholeTicketsToEntries
    function _lootboxTicketCount(
        uint256 budgetWei,
        uint256 priceWei,
        uint256 seed
    ) private pure returns (uint32 scaledWholeTickets) {
        if (budgetWei == 0) {
            return 0;
        }
        uint256 adjustedBudget = (budgetWei * _ticketVarianceBps(seed)) / 10_000;
        uint256 scaled = (adjustedBudget * QTY_SCALE) / priceWei;
        // Saturate at the uint32 ceiling instead of wrapping. The ceiling (~42.9M scaled
        // whole-tickets in a single roll) is only reachable at economically-impossible box
        // sizes; a graceful cap avoids a silent modular wrap to a tiny count.
        scaledWholeTickets = scaled > type(uint32).max ? type(uint32).max : uint32(scaled);
    }

    /// @dev Draw the within-budget ticket multiplier (BPS) from the variance tiers. Extracted
    ///      from `_lootboxTicketCount` so the ETH-spin stake can reuse the SAME multiplier the
    ///      tickets it replaces would have drawn (EV-equal). Consumes bits[96..119] of `seed`.
    function _ticketVarianceBps(uint256 seed) private pure returns (uint256 ticketBps) {
        uint256 varianceRoll = uint24(seed >> 96) % 10_000;
        uint256 c1 = LOOTBOX_TICKET_VARIANCE_TIER1_CHANCE_BPS;
        uint256 c2 = c1 + LOOTBOX_TICKET_VARIANCE_TIER2_CHANCE_BPS;
        uint256 c3 = c2 + LOOTBOX_TICKET_VARIANCE_TIER3_CHANCE_BPS;
        uint256 c4 = c3 + LOOTBOX_TICKET_VARIANCE_TIER4_CHANCE_BPS;

        if (varianceRoll < c1) {
            ticketBps = _ticketRangeBps(
                varianceRoll, 0, c1,
                LOOTBOX_TICKET_VARIANCE_TIER1_LOW_BPS,
                LOOTBOX_TICKET_VARIANCE_TIER1_HIGH_BPS
            );
        } else if (varianceRoll < c2) {
            ticketBps = _ticketRangeBps(
                varianceRoll, c1, c2,
                LOOTBOX_TICKET_VARIANCE_TIER2_LOW_BPS,
                LOOTBOX_TICKET_VARIANCE_TIER2_HIGH_BPS
            );
        } else if (varianceRoll < c3) {
            ticketBps = _ticketRangeBps(
                varianceRoll, c2, c3,
                LOOTBOX_TICKET_VARIANCE_TIER3_LOW_BPS,
                LOOTBOX_TICKET_VARIANCE_TIER3_HIGH_BPS
            );
        } else if (varianceRoll < c4) {
            ticketBps = _ticketRangeBps(
                varianceRoll, c3, c4,
                LOOTBOX_TICKET_VARIANCE_TIER4_LOW_BPS,
                LOOTBOX_TICKET_VARIANCE_TIER4_HIGH_BPS
            );
        } else {
            ticketBps = _ticketRangeBps(
                varianceRoll, c4, 10_000,
                LOOTBOX_TICKET_VARIANCE_TIER5_LOW_BPS,
                LOOTBOX_TICKET_VARIANCE_TIER5_HIGH_BPS
            );
        }
    }

    /// @dev Linearly map a uniform `roll` within [windowLow, windowHigh) onto the inclusive
    ///      BPS range [bpsLow, bpsHigh]: the window's first index maps to bpsLow, its last to
    ///      bpsHigh. A roll uniform over the window yields a uniform multiplier whose mean is
    ///      the range midpoint, i.e. the tier's per-tier mean.
    function _ticketRangeBps(
        uint256 roll,
        uint256 windowLow,
        uint256 windowHigh,
        uint256 bpsLow,
        uint256 bpsHigh
    ) private pure returns (uint256) {
        uint256 span = windowHigh - windowLow - 1;
        if (span == 0) return bpsLow;
        return bpsLow + ((roll - windowLow) * (bpsHigh - bpsLow)) / span;
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

        uint256 poolBalance = dgnrs.poolBalance(IsDGNRS.Pool.Lootbox);

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
            IsDGNRS.Pool.Lootbox,
            player,
            amount
        );
    }

    /// @dev Get the value for a lazy pass at a specific level.
    ///      Value equals the sum of per-level ticket prices across 10 levels.
    /// @param passLevel The lazy pass start level
    /// @return The value in ETH (scaled by cost divisor)
    function _lazyPassPriceForLevel(
        uint24 passLevel
    ) private pure returns (uint256) {
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
    /// @param rngWord The day's VRF word (`rngWordByDay[day]`, nonzero-checked by the caller)
    /// @return boonType The boon type (1-31)
    function _deityBoonForSlot(
        address deity,
        uint24 day,
        uint8 slot,
        bool decimatorAllowed,
        bool deityPassAvailable,
        uint256 rngWord
    ) private pure returns (uint8 boonType) {
        uint256 seed = uint256(keccak256(abi.encode(rngWord, deity, day, slot)));
        uint256 total = decimatorAllowed
            ? BOON_WEIGHT_TOTAL
            : BOON_WEIGHT_TOTAL_NO_DECIMATOR;
        if (!deityPassAvailable) total -= BOON_WEIGHT_DEITY_PASS_ALL;
        uint256 roll = seed % total;
        return _boonFromRoll(roll, decimatorAllowed, deityPassAvailable);
    }

}