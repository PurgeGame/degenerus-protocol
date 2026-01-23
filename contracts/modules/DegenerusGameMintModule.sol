// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IDegenerusCoin} from "../interfaces/IDegenerusCoin.sol";
import {IDegenerusGamepieces} from "../interfaces/IDegenerusGamepieces.sol";
import {ContractAddresses} from "../ContractAddresses.sol";
import {DegenerusGameStorage} from "../storage/DegenerusGameStorage.sol";
import {DegenerusTraitUtils} from "../DegenerusTraitUtils.sol";

/**
 * @title DegenerusGameMintModule
 * @author Burnie Degenerus
 * @notice Delegate-called module handling mint history, airdrop math, and trait rebuilding.
 *
 * @dev This module is called via `delegatecall` from DegenerusGame, meaning all storage
 *      reads/writes operate on the game contract's storage.
 *
 * ## Functions
 *
 * - `recordMintData`: Track per-player mint history and calculate BURNIE rewards
 * - `calculateAirdropMultiplier`: Compute bonus multiplier for low-participation levels
 * - `purchaseTargetCountFromRaw`: Scale raw purchase count by airdrop multiplier
 * - `rebuildTraitCounts`: Reconstruct traitRemaining[] for new levels
 *
 * ## Activity Score System
 *
 * Player engagement is tracked through multiple loyalty metrics:
 * - **Level Count**: Total levels minted (lifetime participation)
 * - **Level Streak**: Consecutive level purchases
 * - **Quest Streak**: Daily quest completion streak (tracked in DegenerusQuests)
 * - **Affiliate Points**: Referral program bonus points (tracked in DegenerusAffiliate)
 * - **Whale Bundle**: Active bundle type (10-lvl or 100-lvl)
 *
 * ### Mint Data Bit Packing Layout (mintPacked_):
 *
 * ```
 * Bits 0-23:    lastLevel          - Last level with ETH mint
 * Bits 24-47:   levelCount         - Total levels minted (lifetime) [Activity Score]
 * Bits 48-71:   levelStreak        - Consecutive levels minted [Activity Score]
 * Bits 72-103:  lastMintDay        - Day index of last mint
 * Bits 104-127: unitsLevel         - Level index for levelUnits tracking
 * Bits 128-151: frozenUntilLevel   - Whale bundle: freeze stats until this level (0 = not frozen)
 * Bits 152-153: whaleBundleType    - Active bundle type (0=none, 1=10-lvl, 3=100-lvl) [Activity Score]
 * Bits 154-227: (reserved)         - Future use
 * Bits 228-243: levelUnits         - Units minted this level (1 gamepiece = 4 units)
 * Bit 244:      (deprecated)       - Previously used for bonus tracking
 * ```
 *
 * Note: Quest Streak and Affiliate Points are tracked separately in their respective contracts
 * (DegenerusQuests.questPlayerState and DegenerusAffiliate.affiliateBonusPointsBest).
 *
 * ## Trait Generation
 *
 * Traits are deterministically derived from tokenId via keccak256:
 * - Each token has 4 traits (one per quadrant: 0-63, 64-127, 128-191, 192-255)
 * - Uses 8×8 weighted grid for non-uniform distribution
 * - Higher-numbered sub-traits within each category are slightly rarer
 */
contract DegenerusGameMintModule is DegenerusGameStorage {
    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    /// @notice Generic revert for overflow conditions.
    error E();
    /// @notice VRF word not ready for loot box reveal.
    error RngNotReady();

    struct LootboxRollState {
        uint256 burniePresale;
        uint256 burnieNoMultiplier;
        uint32 futureTickets;
        bool megaJackpotHit;
        bool lazyPassAwarded;
        bool tokenRewarded;
        uint256 entropy;
    }

    // -------------------------------------------------------------------------
    // External Contract References (compile-time constants)
    // -------------------------------------------------------------------------

    IDegenerusCoin internal constant coin = IDegenerusCoin(ContractAddresses.COIN);
    IDegenerusGamepieces internal constant gamepieces =
        IDegenerusGamepieces(ContractAddresses.GAMEPIECES);

    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    /// @notice Time offset for day calculation (matches game's jackpot reset time).
    uint48 private constant JACKPOT_RESET_TIME = 82620;

    /// @notice Default tokens to process per rebuildTraitCounts call.
    uint32 private constant TRAIT_REBUILD_TOKENS_PER_TX = 2500;

    /// @notice Reduced batch size for level 1 (smaller initial supply).
    uint32 private constant TRAIT_REBUILD_TOKENS_LEVEL1 = 1800;

    /// @dev Max players processed per future-ticket activation batch.
    uint32 private constant FUTURE_TICKET_PLAYER_BATCH_SIZE = 96;
    uint32 private constant FUTURE_TICKET_WORK_CAP = 3000; // Max tickets processed per batch
    uint32 private constant WRITES_BUDGET_SAFE = 780; // Safe write budget for gas control
    uint32 private constant WRITES_BUDGET_MIN = 8; // Minimum writes to ensure progress
    uint64 private constant TICKET_LCG_MULT = 6364136223846793005; // LCG multiplier for trait generation

    /// @dev Loot box minimum purchase amount (0.01 ETH / COST_DIVISOR for testnet).
    uint256 private constant LOOTBOX_MIN = 0.01 ether / ContractAddresses.COST_DIVISOR;
    /// @dev Max loot box ETH per level that can receive bonus multiplier (scaled for testnet).
    uint256 private constant LOOTBOX_MULTIPLIER_CAP = 5 ether / ContractAddresses.COST_DIVISOR;
    /// @dev Loot box auto-open lookback window in days.
    uint48 private constant LOOTBOX_DECAY_DAYS = 7;

    /// @dev Loot box per-roll payouts (basis points) - balanced for size-independent EV.
    ///      Distribution: 55% tickets (100% EV), 10% DGNRS, 10% WWXRP (joke prize), 25% large BURNIE.
    ///      Plus 0.2% mega jackpot (25 ETH in tickets).
    ///      Tickets give 100% EV when rolled, BURNIE scaled to maintain ~78% total EV.
    uint16 private constant LOOTBOX_TICKET_ROLL_BPS = 12_720; // 127.2% (gives 100% after 0.786 multiplier)
    /// @dev Ticket variance (5-tier), expected ~0.786x.
    uint16 private constant LOOTBOX_TICKET_VARIANCE_TIER1_CHANCE_BPS = 100; // 1%
    uint16 private constant LOOTBOX_TICKET_VARIANCE_TIER2_CHANCE_BPS = 400; // 4%
    uint16 private constant LOOTBOX_TICKET_VARIANCE_TIER3_CHANCE_BPS = 2000; // 20%
    uint16 private constant LOOTBOX_TICKET_VARIANCE_TIER4_CHANCE_BPS = 4500; // 45%
    uint16 private constant LOOTBOX_TICKET_VARIANCE_TIER5_CHANCE_BPS = 3000; // 30%
    uint16 private constant LOOTBOX_TICKET_VARIANCE_TIER1_BPS = 46_000; // 4.6x
    uint16 private constant LOOTBOX_TICKET_VARIANCE_TIER2_BPS = 23_000; // 2.3x
    uint16 private constant LOOTBOX_TICKET_VARIANCE_TIER3_BPS = 11_000; // 1.1x
    uint16 private constant LOOTBOX_TICKET_VARIANCE_TIER4_BPS = 6_510; // 0.651x
    uint16 private constant LOOTBOX_TICKET_VARIANCE_TIER5_BPS = 4_500; // 0.45x
    /// @dev DGNRS payout: variable % of remaining lootbox pool (10% chance), scaled by ETH amount.
    ///      Distribution: 79.5% small, 15% medium, 5% large, 0.5% mega.
    uint16 private constant LOOTBOX_DGNRS_POOL_SMALL_PPM = 10; // 0.001% of pool per 1 ETH (79.5% of hits)
    uint16 private constant LOOTBOX_DGNRS_POOL_MEDIUM_PPM = 390; // 0.039% of pool per 1 ETH (15% of hits)
    uint16 private constant LOOTBOX_DGNRS_POOL_LARGE_PPM = 800; // 0.08% of pool per 1 ETH (5% of hits)
    uint16 private constant LOOTBOX_DGNRS_POOL_MEGA_PPM = 8000; // 0.8% of pool per 1 ETH (0.5% of hits)
    uint256 private constant LOOTBOX_DGNRS_MEGA_CAP = 5 ether / ContractAddresses.COST_DIVISOR;
    /// @dev WWXRP payout: 0.1 WWXRP flat prize (valued at 0 for EV)
    uint256 private constant LOOTBOX_WWXRP_PRIZE = 0.1 ether; // 0.1 WWXRP (18 decimals)
    /// @dev Coinflip boon: 2% chance per ETH to award next-flip bonus
    uint16 private constant LOOTBOX_BOON_CHANCE_PER_ETH_BPS = 200; // 2% per ETH
    uint16 private constant LOOTBOX_BOON_BONUS_BPS = 500; // 5% bonus to coinflip stake
    uint256 private constant LOOTBOX_BOON_MAX_BONUS = 5000 ether; // Max 5,000 BURNIE bonus (5% tier)
    uint16 private constant LOOTBOX_COINFLIP_10_CHANCE_PER_ETH_BPS = 50; // 0.5% per ETH for 10% boost
    uint16 private constant LOOTBOX_COINFLIP_10_BONUS_BPS = 1000; // 10% bonus to coinflip stake
    uint16 private constant LOOTBOX_COINFLIP_25_CHANCE_PER_ETH_BPS = 10; // 0.1% per ETH for 25% boost
    uint16 private constant LOOTBOX_COINFLIP_25_BONUS_BPS = 2500; // 25% bonus to coinflip stake
    uint48 private constant LOOTBOX_BOON_EXPIRY_SECONDS = 172800; // 2 days (48 hours)
    uint48 private constant PURCHASE_BOOST_EXPIRY_SECONDS = 345600; // 4 days (96 hours)
    /// @dev Burn boon: 1% chance per ETH to award gamepiece burn bonus
    uint16 private constant LOOTBOX_BURN_BOON_CHANCE_PER_ETH_BPS = 100; // 1% per ETH
    uint256 private constant LOOTBOX_BURN_BOON_BONUS = 100 ether; // 100 BURNIE bonus on burn
    /// @dev Lootbox boost boons: enhance next lootbox value
    uint16 private constant LOOTBOX_BOOST_5_CHANCE_PER_ETH_BPS = 200; // 2% per ETH for 5% boost
    uint16 private constant LOOTBOX_BOOST_5_BONUS_BPS = 500; // 5% boost to lootbox value
    uint16 private constant LOOTBOX_BOOST_15_CHANCE_PER_ETH_BPS = 50; // 0.5% per ETH for 15% boost
    uint16 private constant LOOTBOX_BOOST_15_BONUS_BPS = 1500; // 15% boost to lootbox value
    /// @dev Purchase boost boons: boost next gamepiece/ticket purchase (5%/15%/25%).
    uint16 private constant LOOTBOX_PURCHASE_BOOST_5_CHANCE_PER_ETH_BPS = 200; // 2% per ETH for 5% boost
    uint16 private constant LOOTBOX_PURCHASE_BOOST_5_BONUS_BPS = 500; // 5% boost to purchase quantity
    uint16 private constant LOOTBOX_PURCHASE_BOOST_15_CHANCE_PER_ETH_BPS = 50; // 0.5% per ETH for 15% boost
    uint16 private constant LOOTBOX_PURCHASE_BOOST_15_BONUS_BPS = 1500; // 15% boost to purchase quantity
    uint16 private constant LOOTBOX_PURCHASE_BOOST_25_CHANCE_PER_ETH_BPS = 10; // 0.1% per ETH for 25% boost
    uint16 private constant LOOTBOX_PURCHASE_BOOST_25_BONUS_BPS = 2500; // 25% boost to purchase quantity
    uint256 private constant LOOTBOX_BOOST_MAX_VALUE = 10 ether / ContractAddresses.COST_DIVISOR; // Max 10 ETH lootbox for boost calc
    uint48 private constant LOOTBOX_BOOST_EXPIRY_SECONDS = 172800; // 2 days (48 hours)
    /// @dev Whale boon: 1% chance per ETH to allow discounted 100-level bundle at any level (4 day expiry)
    uint16 private constant LOOTBOX_WHALE_BOON_CHANCE_PER_ETH_BPS = 100; // 1% per ETH
    /// @dev Decimator burn boost boons: boost next decimator burn (10%/25%/50%).
    uint16 private constant LOOTBOX_DECIMATOR_10_CHANCE_PER_ETH_BPS = 50; // 0.5% per ETH for 10% boost
    uint16 private constant LOOTBOX_DECIMATOR_10_BONUS_BPS = 1000; // 10% boost to decimator burn
    uint16 private constant LOOTBOX_DECIMATOR_25_CHANCE_PER_ETH_BPS = 10; // 0.1% per ETH for 25% boost
    uint16 private constant LOOTBOX_DECIMATOR_25_BONUS_BPS = 2500; // 25% boost to decimator burn
    uint16 private constant LOOTBOX_DECIMATOR_50_CHANCE_PER_ETH_BPS = 3; // 0.025% per ETH (rounded)
    uint16 private constant LOOTBOX_DECIMATOR_50_BONUS_BPS = 5000; // 50% boost to decimator burn
    /// @dev Activity streak boons: add +10/+25/+50 to mint streak, mint count, and quest streak.
    uint16 private constant LOOTBOX_ACTIVITY_BOON_10_CHANCE_PER_ETH_BPS = 100; // 1% per ETH
    uint16 private constant LOOTBOX_ACTIVITY_BOON_25_CHANCE_PER_ETH_BPS = 30; // 0.3% per ETH
    uint16 private constant LOOTBOX_ACTIVITY_BOON_50_CHANCE_PER_ETH_BPS = 10; // 0.1% per ETH
    uint24 private constant LOOTBOX_ACTIVITY_BOON_10_BONUS = 10;
    uint24 private constant LOOTBOX_ACTIVITY_BOON_25_BONUS = 25;
    uint24 private constant LOOTBOX_ACTIVITY_BOON_50_BONUS = 50;
    /// @dev DGNRS valuation: 1.5x backing, minimum 10000 ETH / supply
    uint256 private constant DGNRS_VALUE_MULTIPLIER_BPS = 15_000; // 1.5x
    uint256 private constant DGNRS_MIN_BACKING_ETH = 10_000 ether;
    /// @dev Whale pass DGNRS pool distribution (ppm of remaining pool).
    uint32 private constant DGNRS_WHALE_REWARD_PPM_SCALE = 1_000_000;
    uint32 private constant DGNRS_WHALE_MINTER_PPM = 9_000; // 0.9%
    uint32 private constant DGNRS_WHALE_AFFILIATE_PPM = 800; // 0.08%
    uint32 private constant DGNRS_WHALE_UPLINE_PPM = 150; // 0.015%
    uint32 private constant DGNRS_WHALE_UPLINE2_PPM = 50; // 0.005%
    /// @dev Large BURNIE variance: scaled to maintain ~79% total EV with 60% ticket contribution.
    uint32 private constant LOOTBOX_LARGE_BURNIE_MAX_BPS = 31_458; // 314.58% (5% of large rolls)
    uint16 private constant LOOTBOX_LARGE_BURNIE_LOW_BPS = 7_216; // 72.16% (18/20 outcomes)
    uint16 private constant LOOTBOX_LARGE_BURNIE_MID_BPS = 8_755; // 87.55% (1/20 outcomes)
    /// @dev Whale pass jackpot: 2 tickets per level for 100 levels + stats boost.
    ///      Chance uses a fixed price to target 5% EV contribution.
    uint8 private constant LOOTBOX_WHALE_PASS_LEVELS = 100;
    uint16 private constant LOOTBOX_WHALE_PASS_EV_BPS = 500; // 5% target EV
    /// @dev Fixed whale pass price used for jackpot EV calculations.
    uint256 private constant LOOTBOX_WHALE_PASS_PRICE = 3.4 ether / ContractAddresses.COST_DIVISOR;
    /// @dev Lazy pass lootbox jackpot EV (10-level pass).
    uint16 private constant LOOTBOX_LAZY_PASS_EV_BPS = 200; // 2% target EV

    /// @dev BURNIE scaling targets (size-independent EV, amounts up to 10 ETH).
    ///      Bonus mapping: 0% -> 60% EV, 50% -> 100% EV, 110% -> 110% EV, 265% -> 128% EV.
    ///      Activity Score can exceed 265% with whale/trophy bonuses; lootbox rewards damp bonus above 110%
    ///      and the curve continues linearly beyond 265% on the damped value.
    ///      Quest streak now 1% per quest (max 100%), mint streak 1% per level (max 25%).
    ///      Curve reaches break-even at 50% Activity Score and continues beyond 128% EV past 265%.
    ///      Presale mode: 150% base + whale bonus (160% or 190%), BURNIE scaled (no whale 1.8x, whale 2.5x/3.0x).
    uint16 private constant LOOTBOX_BURNIE_BASE_SCALE_BPS = 8_500; // 0.85x (0% bonus = 60% EV)
    uint16 private constant LOOTBOX_BURNIE_FACTOR_50_BPS = 14_160; // 1.416x at 50% bonus (100% EV)
    uint16 private constant LOOTBOX_BURNIE_FACTOR_110_BPS = 15_580; // 1.558x at 110% bonus (110% EV)
    uint16 private constant LOOTBOX_BURNIE_FACTOR_265_BPS = 18_130; // 1.813x at 265% bonus (128% EV max)
    uint16 private constant LOOTBOX_BONUS_50_BPS = 5_000;
    uint16 private constant LOOTBOX_BONUS_110_BPS = 11_000;
    uint16 private constant LOOTBOX_BONUS_265_BPS = 26_500;
    /// @dev Damp the bonus above 110% for lootbox rewards (85% of the excess).
    uint16 private constant LOOTBOX_BONUS_EXCESS_DAMP_BPS = 8_500;
    /// @dev Presale lootbox bonus: Fixed 150% base + whale bundle bonus (10% or 40%).
    ///      No whale: 150% bonus → 1.8x presale multiplier.
    ///      10-lvl whale: 160% → 2.5x multiplier, 100-lvl whale: 190% → 3.0x multiplier.
    uint16 private constant LOOTBOX_BONUS_PRESALE_BPS = 15_000; // 150% base bonus
    uint16 private constant LOOTBOX_PRESALE_NO_WHALE_MULTIPLIER_BPS = 18_000; // 1.8x
    uint16 private constant LOOTBOX_PRESALE_WHALE_10_MULTIPLIER_BPS = 25_000; // 2.5x
    uint16 private constant LOOTBOX_PRESALE_WHALE_100_MULTIPLIER_BPS = 30_000; // 3.0x
    /// @dev Share of bonus applied to future tickets (keeps total EV near previous curve).
    uint16 private constant LOOTBOX_TICKET_BONUS_SHARE_BPS = 3_000;

    /// @dev Loot box amount split threshold (two rolls when exceeded, scaled for testnet).
    uint256 private constant LOOTBOX_SPLIT_THRESHOLD = 0.5 ether / ContractAddresses.COST_DIVISOR;

    /// @dev Loot box pool split (basis points of total ETH).
    uint16 private constant LOOTBOX_SPLIT_FUTURE_BPS = 6000;
    uint16 private constant LOOTBOX_SPLIT_NEXT_BPS = 2000;

    /// @dev Loot box presale pool split (basis points of total ETH).
    ///      10% future, 30% next, 30% vault, 30% reward (remainder)
    uint16 private constant LOOTBOX_PRESALE_SPLIT_FUTURE_BPS = 1000;
    uint16 private constant LOOTBOX_PRESALE_SPLIT_NEXT_BPS = 3000;
    uint16 private constant LOOTBOX_PRESALE_SPLIT_VAULT_BPS = 3000;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event LootBoxPurchased(
        address indexed buyer,
        uint48 indexed day,
        uint256 amount,
        bool presale,
        uint256 futureShare,
        uint256 nextPrizeShare,
        uint256 vaultShare,
        uint256 rewardShare
    );

    event LootBoxOpened(
        address indexed player,
        uint48 indexed day,
        uint256 amount,
        uint24 futureLevel,
        uint32 futureTickets,
        uint32 currentTickets,
        uint256 burnie,
        uint256 bonusBurnie
    );
    event LootBoxDecayed(
        address indexed player,
        uint48 indexed day,
        uint256 originalAmount,
        uint256 decayedAmount
    );

    event LootBoxWhalePassJackpot(
        address indexed player,
        uint48 indexed day,
        uint256 lootboxAmount,
        uint24 targetLevel,
        uint32 tickets,
        uint24 statsBoost,
        uint24 frozenUntilLevel
    );
    event LootBoxLazyPassAwarded(
        address indexed player,
        uint48 indexed day,
        uint256 lootboxAmount,
        uint24 passLevel,
        bool activatedNow
    );

    event LazyPassActivated(address indexed player, uint24 passLevel);

    event LootBoxDgnrsReward(
        address indexed player,
        uint48 indexed day,
        uint256 lootboxAmount,
        uint256 dgnrsAmount,
        uint256 dgnrsValue
    );

    event LootBoxWwxrpReward(
        address indexed player,
        uint48 indexed day,
        uint256 lootboxAmount,
        uint256 wwxrpAmount
    );

    event LootBoxBoonAwarded(
        address indexed player,
        uint48 indexed day,
        uint256 lootboxAmount,
        uint256 boonAmount
    );

    event LootBoxBurnBoonAwarded(
        address indexed player,
        uint48 indexed day,
        uint256 lootboxAmount,
        uint256 bonusAmount
    );

    event LootBoxBoost5Awarded(
        address indexed player,
        uint48 indexed day,
        uint256 lootboxAmount,
        uint16 boostBps
    );

    event LootBoxBoost15Awarded(
        address indexed player,
        uint48 indexed day,
        uint256 lootboxAmount,
        uint16 boostBps
    );

    event LootBoxGamepieceBoostAwarded(
        address indexed player,
        uint48 indexed day,
        uint256 lootboxAmount,
        uint16 boostBps
    );

    event LootBoxTicketBoostAwarded(
        address indexed player,
        uint48 indexed day,
        uint256 lootboxAmount,
        uint16 boostBps
    );

    event LootBoxDecimatorBoostAwarded(
        address indexed player,
        uint48 indexed day,
        uint256 lootboxAmount,
        uint16 boostBps
    );

    event LootBoxWhaleBoonAwarded(
        address indexed player,
        uint48 indexed day,
        uint256 lootboxAmount,
        uint48 expiryDay
    );

    event LootBoxActivityBoonAwarded(
        address indexed player,
        uint48 indexed day,
        uint256 lootboxAmount,
        uint24 bonusLevels
    );

    event LootBoxBoostConsumed(
        address indexed player,
        uint48 indexed day,
        uint256 originalAmount,
        uint256 boostedAmount,
        uint16 boostBps
    );

    // -------------------------------------------------------------------------
    // Bit Packing Masks and Shifts
    // -------------------------------------------------------------------------

    /// @notice Mask for 24-bit fields.
    uint256 private constant MINT_MASK_24 = (uint256(1) << 24) - 1;

    /// @notice Mask for 16-bit fields.
    uint256 private constant MINT_MASK_16 = (uint256(1) << 16) - 1;

    /// @notice Mask for 32-bit fields.
    uint256 private constant MINT_MASK_32 = (uint256(1) << 32) - 1;

    /// @notice Bit shift for last minted level (24 bits at position 0).
    uint256 private constant ETH_LAST_LEVEL_SHIFT = 0;

    /// @notice Bit shift for level count (24 bits at position 24).
    uint256 private constant ETH_LEVEL_COUNT_SHIFT = 24;

    /// @notice Bit shift for consecutive level streak (24 bits at position 48).
    uint256 private constant ETH_LEVEL_STREAK_SHIFT = 48;

    /// @notice Bit shift for last mint day (32 bits at position 72).
    uint256 private constant ETH_DAY_SHIFT = 72;

    /// @notice Bit shift for units-level marker (24 bits at position 104).
    uint256 private constant ETH_LEVEL_UNITS_LEVEL_SHIFT = 104;

    /// @notice Bit shift for level units counter (16 bits at position 228).
    uint256 private constant ETH_LEVEL_UNITS_SHIFT = 228;

    /// @notice Bit shift for bonus-paid flag (1 bit at position 244).
    uint256 private constant ETH_LEVEL_BONUS_SHIFT = 244;

    /// @notice Bit shift for frozen-until-level (24 bits at position 128).
    ///         Used for whale bundle presales: freezes streak/count updates until specified level.
    uint256 private constant ETH_FROZEN_UNTIL_LEVEL_SHIFT = 128;

    /// @notice Bit shift for whale bundle type (2 bits at position 152).
    ///         Tracks active bundle: 0=none, 1=10-level, 3=100-level.
    uint256 private constant ETH_WHALE_BUNDLE_TYPE_SHIFT = 152;

    // -------------------------------------------------------------------------
    // Mint Data Recording
    // -------------------------------------------------------------------------

    /**
     * @notice Record mint metadata and update Activity Score metrics.
     * @dev Called via delegatecall from DegenerusGame during recordMint().
     *      Updates the player's Activity Score metrics for tracking engagement.
     *
     * @param player Address of the player making the purchase.
     * @param lvl Current game level.
     * @param mintUnits Units purchased (1 gamepiece = 4 units, 1 ticket = 1 unit).
     * @return coinReward BURNIE amount to credit as coinflip stake (currently 0).
     *
     * ## Activity Score State Updates
     *
     * - `mintPacked_[player]` updated with level count, streak, whale bonuses, milestones
     * - Only writes to storage if data actually changed
     *
     * ## Level Transition Logic
     *
     * - Same level: Just update units
     * - New level with <4 units: Only track units, don't count as "minted"
     * - New level with ≥4 units: Update streak and total
     * - Century boundary (level 100, 200...): Total continues to accumulate
     */
    function recordMintData(
        address player,
        uint24 lvl,
        uint32 mintUnits
    ) external payable returns (uint256 coinReward) {
        // Load previous packed data
        uint256 prevData = mintPacked_[player];
        uint256 data;

        // ---------------------------------------------------------------------
        // Unpack previous state
        // ---------------------------------------------------------------------

        uint24 prevLevel = uint24((prevData >> ETH_LAST_LEVEL_SHIFT) & MINT_MASK_24);
        uint24 total = uint24((prevData >> ETH_LEVEL_COUNT_SHIFT) & MINT_MASK_24);
        uint24 streak = uint24((prevData >> ETH_LEVEL_STREAK_SHIFT) & MINT_MASK_24);
        uint24 unitsLevel = uint24((prevData >> ETH_LEVEL_UNITS_LEVEL_SHIFT) & MINT_MASK_24);

        bool sameLevel = prevLevel == lvl;
        bool sameUnitsLevel = unitsLevel == lvl;

        // ---------------------------------------------------------------------
        // Handle level units
        // ---------------------------------------------------------------------

        // Get previous level units (reset on level change)
        uint256 levelUnitsBefore = sameUnitsLevel ? ((prevData >> ETH_LEVEL_UNITS_SHIFT) & MINT_MASK_16) : 0;

        // Calculate new level units (capped at 16-bit max)
        uint256 levelUnitsAfter = levelUnitsBefore + uint256(mintUnits);
        if (levelUnitsAfter > MINT_MASK_16) {
            levelUnitsAfter = MINT_MASK_16;
        }

        // ---------------------------------------------------------------------
        // Early exit: New level with <4 units (not counted as "minted")
        // ---------------------------------------------------------------------

        if (!sameLevel && levelUnitsAfter < 4) {
            // Just update units, don't update level/streak/total
            data = _setPacked(prevData, ETH_LEVEL_UNITS_SHIFT, MINT_MASK_16, levelUnitsAfter);
            data = _setPacked(data, ETH_LEVEL_UNITS_LEVEL_SHIFT, MINT_MASK_24, lvl);
            if (data != prevData) {
                mintPacked_[player] = data;
            }
            return coinReward;
        }

        // ---------------------------------------------------------------------
        // Update mint day
        // ---------------------------------------------------------------------

        uint32 day = _currentMintDay();
        data = _setMintDay(prevData, day, ETH_DAY_SHIFT, MINT_MASK_32);

        // ---------------------------------------------------------------------
        // Same level: Just update units
        // ---------------------------------------------------------------------

        if (sameLevel) {
            data = _setPacked(data, ETH_LEVEL_UNITS_SHIFT, MINT_MASK_16, levelUnitsAfter);
            data = _setPacked(data, ETH_LEVEL_UNITS_LEVEL_SHIFT, MINT_MASK_24, lvl);
            if (data != prevData) {
                mintPacked_[player] = data;
            }
            return coinReward;
        }

        // ---------------------------------------------------------------------
        // New level with ≥4 units: Full state update
        // ---------------------------------------------------------------------

        // Check for whale bundle frozen state
        uint24 frozenUntilLevel = uint24((prevData >> ETH_FROZEN_UNTIL_LEVEL_SHIFT) & MINT_MASK_24);
        bool isFrozen = frozenUntilLevel > 0 && lvl < frozenUntilLevel;

        // If frozen, skip updating total and streak (they're pre-set)
        // If we've reached the frozen level, clear the flag and resume normal tracking
        if (frozenUntilLevel > 0 && lvl >= frozenUntilLevel) {
            // Clear frozen flag and whale bundle type - resume normal tracking from here
            data = _setPacked(data, ETH_FROZEN_UNTIL_LEVEL_SHIFT, MINT_MASK_24, 0);
            data = _setPacked(data, ETH_WHALE_BUNDLE_TYPE_SHIFT, 3, 0); // Clear bundle type
            frozenUntilLevel = 0;
            isFrozen = false;
        }

        if (!isFrozen) {
            // Update total (lifetime count)
            if (total < type(uint24).max) {
                unchecked {
                    total = uint24(total + 1);
                }
            }

            // Update streak (consecutive levels) or reset
            if (prevLevel != 0 && prevLevel + 1 == lvl) {
                // Consecutive level - increment streak
                if (streak < type(uint24).max) {
                    unchecked {
                        streak = uint24(streak + 1);
                    }
                }
            } else {
                // Gap or first mint - reset streak
                streak = 1;
            }
        }

        // Pack all updated fields
        data = _setPacked(data, ETH_LAST_LEVEL_SHIFT, MINT_MASK_24, lvl);
        data = _setPacked(data, ETH_LEVEL_COUNT_SHIFT, MINT_MASK_24, total);
        data = _setPacked(data, ETH_LEVEL_STREAK_SHIFT, MINT_MASK_24, streak);
        data = _setPacked(data, ETH_LEVEL_UNITS_SHIFT, MINT_MASK_16, levelUnitsAfter);
        data = _setPacked(data, ETH_LEVEL_UNITS_LEVEL_SHIFT, MINT_MASK_24, lvl);
        // Frozen flag is already set in data if it was modified above

        // ---------------------------------------------------------------------
        // Commit to storage (only if changed)
        // ---------------------------------------------------------------------

        if (data != prevData) {
            mintPacked_[player] = data;
        }
        return coinReward;
    }

    // -------------------------------------------------------------------------
    // Airdrop Multiplier
    // -------------------------------------------------------------------------

    /**
     * @notice Calculate airdrop multiplier for low-participation levels.
     * @dev Pure function - no state changes. Creates a floor for trait distribution.
     *
     * @param prePurchaseCount Raw count before purchase phase (eligible for multiplier).
     * @param purchasePhaseCount Raw count during purchase phase (not multiplied).
     * @param lvl Current game level.
     * @return Multiplier to apply to purchase count (1 = no bonus).
     *
     * ## Logic
     *
     * - Target: 5,000 tokens (or 10,000 for levels ending in 8)
     * - If total purchases ≥ target: multiplier = 1 (no bonus)
     * - If prePurchaseCount == 0: multiplier = ceiling(target / purchasePhaseCount)
     * - Otherwise: multiplier = ceiling((target - purchasePhaseCount) / prePurchaseCount)
     *
     * ## Examples (purchasePhaseCount = 0)
     *
     * | Purchases | Level %10 | Target | Multiplier |
     * |-----------|-----------|--------|------------|
     * | 100       | 0-7,9     | 5,000  | 50x        |
     * | 500       | 0-7,9     | 5,000  | 10x        |
     * | 1,000     | 8         | 10,000 | 10x        |
     * | 5,000+    | any       | -      | 1x         |
     */
    function calculateAirdropMultiplier(
        uint32 prePurchaseCount,
        uint32 purchasePhaseCount,
        uint24 lvl
    ) external pure returns (uint32) {
        // Higher target for levels ending in 8
        uint256 target = (lvl % 10 == 8) ? 10_000 : 5_000;

        uint256 total = uint256(prePurchaseCount) + uint256(purchasePhaseCount);
        if (total >= target) {
            return 1;
        }

        if (prePurchaseCount == 0) {
            if (purchasePhaseCount == 0) {
                return 1;
            }
            // Ceiling division: (target + purchasePhaseCount - 1) / purchasePhaseCount
            uint256 purchaseNumerator = target + uint256(purchasePhaseCount) - 1;
            return uint32(purchaseNumerator / uint256(purchasePhaseCount));
        }

        // Remaining needed after purchase-phase purchases
        uint256 remaining = target - uint256(purchasePhaseCount);

        // Ceiling division: (remaining + prePurchaseCount - 1) / prePurchaseCount
        uint256 remainingNumerator = remaining + uint256(prePurchaseCount) - 1;
        return uint32(remainingNumerator / prePurchaseCount);
    }

    /**
     * @notice Scale raw purchase count by stored airdrop multiplier.
     * @dev View function - reads airdropMultiplier from storage.
     *
     * @param prePurchaseCount Raw count before purchase phase (eligible for multiplier).
     * @param purchasePhaseCount Raw count during purchase phase (not multiplied).
     * @return Scaled count (pre × airdropMultiplier + purchase phase; if prePurchaseCount==0, purchasePhaseCount is multiplied).
     */
    function purchaseTargetCountFromRaw(
        uint32 prePurchaseCount,
        uint32 purchasePhaseCount
    ) external view returns (uint32) {
        if (prePurchaseCount == 0 && purchasePhaseCount == 0) {
            return 0;
        }

        uint32 multiplier = airdropMultiplier;
        uint256 scaled;
        if (prePurchaseCount == 0) {
            scaled = uint256(purchasePhaseCount) * uint256(multiplier);
        } else {
            scaled = uint256(prePurchaseCount) * uint256(multiplier) + uint256(purchasePhaseCount);
        }

        // Overflow protection
        if (scaled > type(uint32).max) revert E();

        return uint32(scaled);
    }

    // -------------------------------------------------------------------------
    // Trait Count Rebuilding
    // -------------------------------------------------------------------------

    /**
     * @notice Rebuild traitRemaining[] by scanning scheduled token traits.
     * @dev Called during advanceGame state 2 to prepare trait counts for burn phase.
     *      Processes tokens in batches to stay within gas limits.
     *
     * @param tokenBudget Max tokens to process this call (0 = default 2,500).
     * @param target Total tokens expected for this level (pre-scaled).
     * @param baseTokenId Starting token ID for this level.
     * @return finished True when all tokens have been processed.
     *
     * ## Batching Strategy
     *
     * - Level 1: 1,800 tokens per batch (smaller initial supply)
     * - Other levels: 2,500 tokens per batch
     * - Can be called multiple times until finished
     *
     * ## State Updates
     *
     * - `traitRemaining[0-255]`: Overwritten on first slice, accumulated after
     * - `traitRebuildCursor`: Tracks progress through token list
     *
     * ## Trait Derivation
     *
     * Each token's 4 traits are deterministically computed from its tokenId:
     * - trait0: Quadrant 0 (0-63)
     * - trait1: Quadrant 1 (64-127)
     * - trait2: Quadrant 2 (128-191)
     * - trait3: Quadrant 3 (192-255)
     */
    function rebuildTraitCounts(
        uint32 tokenBudget,
        uint32 target,
        uint256 baseTokenId
    ) external returns (bool finished) {
        uint32 cursor = traitRebuildCursor;

        // Already complete
        if (cursor >= target) return true;

        // ---------------------------------------------------------------------
        // Determine batch size
        // ---------------------------------------------------------------------

        uint32 batch = (tokenBudget == 0) ? TRAIT_REBUILD_TOKENS_PER_TX : tokenBudget;
        bool startingSlice = cursor == 0;

        if (startingSlice) {
            // First batch: use level-appropriate size
            uint32 firstBatch = (level == 1) ? TRAIT_REBUILD_TOKENS_LEVEL1 : TRAIT_REBUILD_TOKENS_PER_TX;
            batch = firstBatch;
        }

        // Don't exceed remaining tokens
        uint32 remaining = target - cursor;
        if (batch > remaining) batch = remaining;

        // ---------------------------------------------------------------------
        // Scan tokens and count traits (in-memory)
        // ---------------------------------------------------------------------

        uint32[256] memory localCounts;

        for (uint32 i; i < batch; ) {
            uint32 tokenOffset = cursor + i;

            // Compute 4 traits for this token (deterministic from tokenId)
            uint32 traitPack = _traitsForToken(baseTokenId + tokenOffset);
            uint8 t0 = uint8(traitPack);
            uint8 t1 = uint8(traitPack >> 8);
            uint8 t2 = uint8(traitPack >> 16);
            uint8 t3 = uint8(traitPack >> 24);

            unchecked {
                ++localCounts[t0];
                ++localCounts[t1];
                ++localCounts[t2];
                ++localCounts[t3];
                ++i;
            }
        }

        // ---------------------------------------------------------------------
        // Commit counts to storage
        // ---------------------------------------------------------------------

        uint32[256] storage remainingCounts = traitRemaining;

        for (uint16 traitId; traitId < 256; ) {
            uint32 incoming = localCounts[traitId];
            if (incoming != 0) {
                if (startingSlice) {
                    // First slice: overwrite stale counts from previous level
                    remainingCounts[traitId] = incoming;
                } else {
                    // Subsequent slices: accumulate
                    remainingCounts[traitId] += incoming;
                }
            }
            unchecked {
                ++traitId;
            }
        }

        // ---------------------------------------------------------------------
        // Update cursor and return status
        // ---------------------------------------------------------------------

        traitRebuildCursor = cursor + batch;
        finished = (traitRebuildCursor == target);
    }

    // -------------------------------------------------------------------------
    // Future Reward Queueing
    // -------------------------------------------------------------------------

    

    // -------------------------------------------------------------------------
    // Future Ticket Activation
    // -------------------------------------------------------------------------

    function processFutureTicketBatch(
        uint32 writesBudget,
        uint24 lvl
    ) external returns (bool worked, bool finished) {
        address[] storage queue = ticketQueue[lvl];
        uint256 total = queue.length;
        if (total > type(uint32).max) revert E();
        if (total == 0) {
            ticketCursor = 0;
            ticketLevel = 0;
            return (false, true);
        }

        if (ticketLevel != lvl) {
            ticketLevel = lvl;
            ticketCursor = 0;
        }

        uint256 idx = ticketCursor;
        if (idx >= total) {
            delete ticketQueue[lvl];
            ticketCursor = 0;
            ticketLevel = 0;
            return (false, true);
        }

        // Set up write budget with cold storage scaling on first batch
        if (writesBudget == 0) {
            writesBudget = WRITES_BUDGET_SAFE;
        } else if (writesBudget < WRITES_BUDGET_MIN) {
            writesBudget = WRITES_BUDGET_MIN;
        }

        if (idx == 0) {
            writesBudget -= (writesBudget * 35) / 100; // 65% scaling for cold storage
        }

        uint32 used;
        uint32 processed; // Track within-player progress

        while (idx < total && used < writesBudget) {
            address player = queue[idx];
            uint32 owed = ticketsOwed[lvl][player];
            uint8 remainder = ticketsOwedFrac[lvl][player];
            if (owed == 0) {
                if (remainder == 0) {
                    unchecked { ++idx; }
                    processed = 0;
                    continue;
                }
                uint256 roll = uint256(keccak256(abi.encode(rngWordCurrent, lvl, player, remainder)));
                ticketsOwedFrac[lvl][player] = 0;
                if ((roll % TICKET_SCALE) >= remainder) {
                    unchecked { ++idx; }
                    processed = 0;
                    continue;
                }
                owed = 1;
                ticketsOwed[lvl][player] = 1;
                remainder = 0;
            }
            if (owed == 0) {
                unchecked { ++idx; }
                processed = 0;
                continue;
            }

            uint32 room = writesBudget - used;
            uint32 baseOv = (processed == 0 && owed <= 2) ? 4 : 2;
            if (room <= baseOv) break;
            room -= baseOv;

            uint32 maxT = (room <= 256) ? (room / 2) : (room - 256);
            uint32 take = owed > maxT ? maxT : owed;
            if (take == 0) break;

            uint256 baseKey = (uint256(lvl) << 224) | (idx << 192) | (uint256(uint160(player)) << 32);
            _raritySymbolBatch(player, baseKey, processed, take, rngWordCurrent);

            // Calculate actual write cost
            uint32 writesThis = (take <= 256) ? (take * 2) : (take + 256);
            writesThis += baseOv;
            if (take == owed) writesThis += 1;

            uint32 remainingOwed;
            unchecked {
                remainingOwed = owed - take;
            }
            if (remainingOwed == 0 && remainder != 0) {
                uint256 roll = uint256(keccak256(abi.encode(rngWordCurrent, lvl, player, owed, remainder)));
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
                unchecked { ++idx; }
                processed = 0;
            }
        }

        worked = (used > 0);
        ticketCursor = uint32(idx);
        finished = (idx >= total);
        if (finished) {
            delete ticketQueue[lvl];
            ticketCursor = 0;
            ticketLevel = 0;
        }
    }

    /// @dev Generates trait tickets in batch for a player's ticket awards using LCG-based PRNG.
    ///      Uses inline assembly for gas-efficient bulk storage writes.
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

    // -------------------------------------------------------------------------
    // Purchases and Loot Boxes
    // -------------------------------------------------------------------------

    

    

    

    

    /// @notice Resolve a lootbox directly (decimator claims) using provided RNG.
    /// @dev Access: ContractAddresses.JACKPOTS contract only. Presale is always false.
    ///      Does not touch lootbox purchase storage; uses current day for event tagging.
    /// @param player Player to receive lootbox rewards.
    /// @param amount Lootbox ETH amount to resolve.
    /// @param rngWord VRF random word from decimator jackpot resolution.
    

    

    

    

    

    

    

    

    

    

    

    

    

    

    

    

    

    

    

    

    

    

    

    

    

    // -------------------------------------------------------------------------
    // Internal Helpers
    // -------------------------------------------------------------------------

    /**
     * @notice Get current day index for mint tracking.
     * @dev Returns day index relative to deploy time (day 1 = deploy day).
     *      Days reset at JACKPOT_RESET_TIME (22:57 UTC), not midnight.
     * @return Day index (1-indexed from deploy day).
     */
    function _currentMintDay() private view returns (uint32) {
        uint48 day = dailyIdx;
        if (day == 0) {
            // Calculate from timestamp if not yet set
            uint48 currentDayBoundary = uint48((block.timestamp - JACKPOT_RESET_TIME) / 1 days);
            day = currentDayBoundary - ContractAddresses.DEPLOY_DAY_BOUNDARY + 1;
        }
        return uint32(day);
    }

    /**
     * @notice Update day field in packed data (only if changed).
     * @param data Current packed data.
     * @param day New day value.
     * @param dayShift Bit position of day field.
     * @param dayMask Mask for day field.
     * @return Updated packed data.
     */
    function _setMintDay(uint256 data, uint32 day, uint256 dayShift, uint256 dayMask) private pure returns (uint256) {
        uint32 prevDay = uint32((data >> dayShift) & dayMask);
        if (prevDay == day) {
            return data; // No change needed
        }
        uint256 clearedDay = data & ~(dayMask << dayShift);
        return clearedDay | (uint256(day) << dayShift);
    }

    /**
     * @notice Set a field in packed data.
     * @param data Current packed data.
     * @param shift Bit position of field.
     * @param mask Mask for field width.
     * @param value New value for field.
     * @return Updated packed data.
     */
    function _setPacked(uint256 data, uint256 shift, uint256 mask, uint256 value) private pure returns (uint256) {
        return (data & ~(mask << shift)) | ((value & mask) << shift);
    }

    // -------------------------------------------------------------------------
    // Trait Generation
    // -------------------------------------------------------------------------

    /**
     * @notice Convert random value to weighted trait index (0-7).
     * @dev Non-uniform distribution - higher values slightly rarer.
     *
     * Weight distribution (out of 75 possible values):
     * - 0: 10 values (13.3%)
     * - 1: 10 values (13.3%)
     * - 2: 10 values (13.3%)
     * - 3: 10 values (13.3%)
     * - 4: 9 values (12.0%)
     * - 5: 9 values (12.0%)
     * - 6: 9 values (12.0%)
     * - 7: 8 values (10.7%)
     *
     * @param rnd Random 32-bit value.
     * @return Trait weight (0-7).
     */
    function _traitWeight(uint32 rnd) private pure returns (uint8) {
        unchecked {
            // Scale to 0-74 range
            uint32 scaled = uint32((uint64(rnd) * 75) >> 32);
            if (scaled < 10) return 0;
            if (scaled < 20) return 1;
            if (scaled < 30) return 2;
            if (scaled < 40) return 3;
            if (scaled < 49) return 4;
            if (scaled < 58) return 5;
            if (scaled < 67) return 6;
            return 7;
        }
    }

    /**
     * @notice Derive a single trait from 64 bits of randomness.
     * @dev Combines category (0-7) and sub-trait (0-7) into trait ID (0-63).
     *
     * @param rnd 64-bit random value.
     * @return Trait ID within quadrant (0-63).
     */
    function _deriveTrait(uint64 rnd) private pure returns (uint8) {
        uint8 category = _traitWeight(uint32(rnd));
        uint8 sub = _traitWeight(uint32(rnd >> 32));
        return (category << 3) | sub; // 8×8 grid = 64 possibilities
    }

    /**
     * @notice Compute all 4 traits for a token deterministically.
     * @dev Each trait is assigned to a quadrant (0-63, 64-127, 128-191, 192-255).
     *
     * @param tokenId Token ID to derive traits for.
     * @return packed Four traits packed as bytes: [trait3][trait2][trait1][trait0].
     *
     * ## Derivation
     *
     * ```
     * rand = keccak256(tokenId)
     * trait0 = deriveTrait(rand[0:64])         // Quadrant 0: 0-63
     * trait1 = deriveTrait(rand[64:128]) | 64  // Quadrant 1: 64-127
     * trait2 = deriveTrait(rand[128:192]) | 128 // Quadrant 2: 128-191
     * trait3 = deriveTrait(rand[192:256]) | 192 // Quadrant 3: 192-255
     * ```
     */
    function _traitsForToken(uint256 tokenId) private pure returns (uint32 packed) {
        uint256 rand = uint256(keccak256(abi.encodePacked(tokenId)));

        // Derive trait for each quadrant (each uses 64 bits of entropy)
        uint8 trait0 = _deriveTrait(uint64(rand));
        uint8 trait1 = _deriveTrait(uint64(rand >> 64)) | 64;   // Quadrant 1 offset
        uint8 trait2 = _deriveTrait(uint64(rand >> 128)) | 128; // Quadrant 2 offset
        uint8 trait3 = _deriveTrait(uint64(rand >> 192)) | 192; // Quadrant 3 offset

        // Pack into single uint32: [trait3][trait2][trait1][trait0]
        packed = uint32(trait0) | (uint32(trait1) << 8) | (uint32(trait2) << 16) | (uint32(trait3) << 24);
    }
}
