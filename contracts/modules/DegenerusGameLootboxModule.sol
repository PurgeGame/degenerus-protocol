// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IDegenerusAffiliate} from "../interfaces/IDegenerusAffiliate.sol";
import {IDegenerusCoin} from "../interfaces/IDegenerusCoin.sol";
import {IDegenerusGamepieces} from "../interfaces/IDegenerusGamepieces.sol";
import {IDegenerusGame, MintPaymentKind} from "../interfaces/IDegenerusGame.sol";
import {IDegenerusGameJackpotModule} from "../interfaces/IDegenerusGameModules.sol";
import {IDegenerusLazyPass} from "../interfaces/IDegenerusLazyPass.sol";
import {IDegenerusQuests} from "../interfaces/IDegenerusQuests.sol";
import {IDegenerusStonk} from "../interfaces/IDegenerusStonk.sol";
import {IVRFCoordinator, VRFRandomWordsRequest} from "../interfaces/IVRFCoordinator.sol";
import {ContractAddresses} from "../ContractAddresses.sol";
import {DegenerusGameStorage} from "../storage/DegenerusGameStorage.sol";

interface IWrappedWrappedXRP {
    function mintPrize(address to, uint256 amount) external;
}

interface IDegenerusAdminLink {
    function _linkAmountToEth(uint256 amount) external view returns (uint256);
}

/**
 * @title DegenerusGameLootboxModule
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
contract DegenerusGameLootboxModule is DegenerusGameStorage {
    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    /// @notice Generic revert for overflow conditions.
    error E();
    /// @notice VRF word not ready for loot box reveal.
    error RngNotReady();
    /// @notice LINK/ETH price unavailable for lootbox RNG roll cost.
    error LinkPriceUnavailable();
    /// @notice LINK balance too low to allow manual lootbox RNG roll.
    error LinkBalanceTooLow();
    /// @notice LINK balance check unavailable (VRF not wired or coordinator call failed).
    error LinkBalanceUnavailable();

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
    IDegenerusGamepieces internal constant gamepieces = IDegenerusGamepieces(ContractAddresses.GAMEPIECES);
    IDegenerusAffiliate internal constant affiliate = IDegenerusAffiliate(ContractAddresses.AFFILIATE);
    IDegenerusLazyPass internal constant lazyPass = IDegenerusLazyPass(ContractAddresses.LAZY_PASS);
    IDegenerusQuests internal constant quests = IDegenerusQuests(ContractAddresses.QUESTS);
    IDegenerusStonk internal constant dgnrs = IDegenerusStonk(ContractAddresses.DGNRS);
    IWrappedWrappedXRP internal constant wwxrp = IWrappedWrappedXRP(ContractAddresses.WWXRP);
    IDegenerusAdminLink internal constant admin = IDegenerusAdminLink(ContractAddresses.ADMIN);

    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    /// @notice Time offset for day calculation (matches game's jackpot reset time).
    uint48 private constant JACKPOT_RESET_TIME = 82620;

    uint32 private constant LOOTBOX_AUTOOPEN_MAX = 7; // Max lootboxes to auto-open per call
    uint32 private constant LOOTBOX_VRF_CALLBACK_GAS_LIMIT = 200_000;
    uint16 private constant LOOTBOX_VRF_REQUEST_CONFIRMATIONS = 10;
    /// @dev LINK amount used to price manual lootbox RNG rolls (1 LINK default).
    uint256 private constant LOOTBOX_RNG_LINK_COST = 1 ether;

    /// @dev Loot box minimum purchase amount (0.01 ETH / COST_DIVISOR for testnet).
    uint256 private constant LOOTBOX_MIN = 0.01 ether / ContractAddresses.COST_DIVISOR;
    /// @dev Max loot box ETH per level that can receive bonus multiplier (scaled for testnet).
    uint256 private constant LOOTBOX_MULTIPLIER_CAP = 5 ether / ContractAddresses.COST_DIVISOR;
    /// @dev BURNIE loot box minimum purchase amount (scaled for testnet).
    uint256 private constant BURNIE_LOOTBOX_MIN = 1000 ether;
    /// @dev BURNIE loot box ticket budget share (low EV by design).
    uint16 private constant BURNIE_LOOTBOX_TICKET_BPS = 6000;
    /// @dev BURNIE loot box BURNIE return share (low EV by design).
    uint16 private constant BURNIE_LOOTBOX_BURNIE_BPS = 1000;

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

    event LootBoxBuy(
        address indexed buyer,
        uint48 indexed day,
        uint256 amount,
        bool presale,
        uint256 futureShare,
        uint256 nextPrizeShare,
        uint256 vaultShare,
        uint256 rewardShare
    );
    event LootBoxIdx(
        address indexed buyer,
        uint48 indexed index,
        uint48 indexed day
    );
    event LootboxRngRolled(
        address indexed player,
        uint48 indexed index,
        uint256 burnieCost
    );
    event BurnieLootBuy(
        address indexed buyer,
        uint48 indexed index,
        uint256 burnieAmount
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
    event BurnieLootOpen(
        address indexed player,
        uint48 indexed day,
        uint256 burnieAmount,
        uint24 ticketLevel,
        uint32 tickets,
        uint256 burnieReward
    );
    event LootBoxDecayed(
        address indexed player,
        uint48 indexed day,
        uint256 originalAmount,
        uint256 decayedAmount
    );

    event WhaleJackpot(
        address indexed player,
        uint48 indexed day,
        uint256 lootboxAmount,
        uint24 targetLevel,
        uint32 tickets,
        uint24 statsBoost,
        uint24 frozenUntilLevel
    );
    event LazyPassWon(
        address indexed player,
        uint48 indexed day,
        uint256 lootboxAmount,
        uint24 passLevel,
        bool activatedNow
    );

    event LazyPassOn(address indexed player, uint24 passLevel);

    /// @notice Unified lootbox reward event.
    /// @param player The player receiving the reward.
    /// @param day The day of the reward.
    /// @param rewardType The type of reward (0=Dgnrs, 1=Wwxrp, 2=CoinflipBoon, 3=BurnBoon, 4=Boost5, 5=Boost15, 6=GamepieceBoost, 7=TicketBoost, 8=DecimatorBoost, 9=WhaleBoon, 10=ActivityBoon).
    /// @param lootboxAmount The lootbox amount spent.
    /// @param amount Primary reward amount (varies by type: DGNRS amount, WWXRP amount, boost BPS, expiry day, bonus levels, etc.).
    event LootBoxReward(
        address indexed player,
        uint48 indexed day,
        uint8 indexed rewardType,
        uint256 lootboxAmount,
        uint256 amount
    );

    event BoostUsed(
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

    /// @notice Purchase gamepieces, tickets, and loot boxes for a buyer.
    /// @dev Delegatecalled by DegenerusGame. Handles payment routing, affiliates, and queues.
    /// @param buyer Recipient of the purchased items.
    /// @param gamepieceQuantity Number of gamepieces to purchase.
    /// @param ticketQuantity Number of tickets to purchase (2 decimals, scaled by 100).
    /// @param lootBoxAmount Number of loot boxes to purchase.
    /// @param affiliateCode Referral code for affiliate attribution.
    /// @param payKind Payment kind selector (ETH/claimable/combined).
    function purchase(
        address buyer,
        uint256 gamepieceQuantity,
        uint256 ticketQuantity,
        uint256 lootBoxAmount,
        bytes32 affiliateCode,
        MintPaymentKind payKind
    ) external payable {
        _purchaseFor(
            buyer,
            gamepieceQuantity,
            ticketQuantity,
            lootBoxAmount,
            affiliateCode,
            payKind
        );
    }

    function _purchaseFor(
        address buyer,
        uint256 gamepieceQuantity,
        uint256 ticketQuantity,
        uint256 lootBoxAmount,
        bytes32 affiliateCode,
        MintPaymentKind payKind
    ) private {
        uint24 currentLevel = level;
        uint256 priceWei = price;

        if (lootBoxAmount != 0 && lootBoxAmount < LOOTBOX_MIN) revert E();

        uint256 gamepieceCost = 0;
        uint256 ticketCost = 0;

        if (gamepieceQuantity > 0) {
            if (gamepieceQuantity > type(uint32).max) revert E();
            gamepieceCost = priceWei * gamepieceQuantity;
        }

        if (ticketQuantity > 0) {
            if (ticketQuantity > type(uint32).max) revert E();
            ticketCost = (priceWei * ticketQuantity) / (4 * TICKET_SCALE);
        }

        uint256 totalCost = gamepieceCost + ticketCost + lootBoxAmount;
        if (totalCost == 0) revert E();

        uint256 initialClaimable = claimableWinnings[buyer];

        uint256 ethForGamepieces = 0;
        uint256 ethForTickets = 0;

        uint256 remainingEth = msg.value;
        if (remainingEth < lootBoxAmount) revert E();
        unchecked {
            remainingEth -= lootBoxAmount;
        }

        if (remainingEth > 0 && (gamepieceCost + ticketCost) > 0) {
            ethForGamepieces = (remainingEth * gamepieceCost) / (gamepieceCost + ticketCost);
            ethForTickets = remainingEth - ethForGamepieces;
        }

        if (gamepieceCost > 0 && gamepieceQuantity > 0) {
            (bool success, ) = ContractAddresses.GAMEPIECES.call{value: ethForGamepieces}(
                abi.encodeWithSignature(
                    "purchase((uint256,uint8,uint8,bool,bytes32))",
                    gamepieceQuantity,
                    uint8(0),
                    uint8(payKind),
                    false,
                    affiliateCode
                )
            );
            if (!success) revert E();
        }

        if (ticketCost > 0 && ticketQuantity > 0) {
            (bool success, ) = ContractAddresses.GAMEPIECES.call{value: ethForTickets}(
                abi.encodeWithSignature(
                    "purchase((uint256,uint8,uint8,bool,bytes32))",
                    ticketQuantity,
                    uint8(1),
                    uint8(payKind),
                    false,
                    affiliateCode
                )
            );
            if (!success) revert E();
        }

        if (lootBoxAmount > 0) {
            uint48 day = _currentDayIndex();
            uint48 index = lootboxRngIndex;
            bool presale = lootboxPresaleActive;

            uint256 packed = lootboxEth[index][buyer];
            uint256 existingAmount = packed & ((1 << 232) - 1);
            uint48 storedDay = lootboxDay[index][buyer];

            if (existingAmount == 0) {
                lootboxDay[index][buyer] = day;
                lootboxIndexQueue[buyer].push(index);
                emit LootBoxIdx(buyer, index, day);
                if (presale) {
                    lootboxPresale[index][buyer] = true;
                }
            } else {
                if (storedDay != day) revert E();
                if (lootboxPresale[index][buyer] != presale) revert E();
            }

            uint256 boostedAmount = _applyLootboxBoostOnPurchase(
                buyer,
                day,
                lootBoxAmount
            );
            uint256 existingBase = lootboxEthBase[index][buyer];
            if (existingAmount != 0 && existingBase == 0) {
                existingBase = existingAmount;
            }
            lootboxEthBase[index][buyer] = existingBase + lootBoxAmount;

            // Pack: [232 bits: amount] [24 bits: purchase level]
            uint24 purchaseLevel = level;
            uint256 newAmount = existingAmount + boostedAmount;
            lootboxEth[index][buyer] = (uint256(purchaseLevel) << 232) | newAmount;
            lootboxEthTotal += lootBoxAmount;
            _maybeRequestLootboxRng(lootBoxAmount);

            uint256 futureBps = presale ? LOOTBOX_PRESALE_SPLIT_FUTURE_BPS : LOOTBOX_SPLIT_FUTURE_BPS;
            uint256 nextBps = presale ? LOOTBOX_PRESALE_SPLIT_NEXT_BPS : LOOTBOX_SPLIT_NEXT_BPS;
            uint256 vaultBps = presale ? LOOTBOX_PRESALE_SPLIT_VAULT_BPS : 0;

            uint256 futureShare = (lootBoxAmount * futureBps) / 10_000;
            uint256 nextShare = (lootBoxAmount * nextBps) / 10_000;
            uint256 vaultShare = (lootBoxAmount * vaultBps) / 10_000;
            uint256 rewardShare;
            unchecked {
                rewardShare = lootBoxAmount - futureShare - nextShare - vaultShare;
            }

            if (futureShare != 0) {
                futurePrizePool += futureShare;
            }
            if (nextShare != 0) {
                nextPrizePool += nextShare;
            }
            if (vaultShare != 0) {
                (bool ok, ) = payable(ContractAddresses.VAULT).call{value: vaultShare}("");
                if (!ok) revert E();
            }
            if (rewardShare != 0) {
                futurePrizePool += rewardShare;
            }

            if (affiliateCode != bytes32(0)) {
                // Loot boxes are always paid with fresh ETH (msg.value), not claimable
                uint24 affiliateLevel = currentLevel;
                if (gameState == GAME_STATE_BURN) {
                    unchecked {
                        affiliateLevel = currentLevel + 1;
                    }
                }
                uint256 lootboxRakeback = affiliate.payAffiliate(
                    lootBoxAmount,
                    affiliateCode,
                    buyer,
                    affiliateLevel,
                    true // always fresh ETH for lootboxes
                );
                if (lootboxRakeback != 0) {
                    coin.creditFlip(buyer, lootboxRakeback);
                }
            }

            emit LootBoxBuy(buyer, day, lootBoxAmount, presale, futureShare, nextShare, vaultShare, rewardShare);

            coin.notifyQuestLootBox(buyer, lootBoxAmount);
            _awardEarlybirdDgnrs(buyer, lootBoxAmount);
        }

        uint256 finalClaimable = claimableWinnings[buyer];
        uint256 totalClaimableUsed = initialClaimable > finalClaimable ? initialClaimable - finalClaimable : 0;
        bool spentAllClaimable = (finalClaimable <= 1 && totalClaimableUsed > 0);

        if (spentAllClaimable && totalClaimableUsed >= priceWei * 3) {
            uint256 bonusAmount = (totalClaimableUsed * PRICE_COIN_UNIT * 10) / (priceWei * 100);
            if (bonusAmount > 0) {
                coin.creditFlip(buyer, bonusAmount);
            }
        }
    }

    /// @notice Purchase a low-EV loot box with BURNIE.
    /// @dev Uses the current lootbox RNG index; rewards are tickets + small BURNIE only.
    function purchaseBurnieLootbox(address buyer, uint256 burnieAmount) external {
        if (buyer == address(0)) revert E();
        _purchaseBurnieLootboxFor(buyer, burnieAmount);
    }

    function _purchaseBurnieLootboxFor(address buyer, uint256 burnieAmount) private {
        if (burnieAmount < BURNIE_LOOTBOX_MIN) revert E();
        uint48 index = lootboxRngIndex;
        if (index == 0) revert E();

        coin.burnCoin(buyer, burnieAmount);

        uint256 existingAmount = lootboxBurnie[index][buyer];
        uint256 newAmount = existingAmount + burnieAmount;
        if (newAmount < existingAmount) revert E();
        lootboxBurnie[index][buyer] = newAmount;

        uint256 priceWei = price;
        if (priceWei != 0) {
            uint256 virtualEth = (burnieAmount * priceWei) / PRICE_COIN_UNIT;
            if (virtualEth != 0) {
                _maybeRequestLootboxRng(virtualEth);
            }
        }

        emit BurnieLootBuy(buyer, index, burnieAmount);
    }



    function rollLootboxRng(address player) external {
        if (player == address(0)) revert E();
        uint48 index = lootboxRngIndex;
        if (index == 0) revert E();
        if (lootboxEth[index][player] == 0 && lootboxBurnie[index][player] == 0) revert E();
        if (lootboxEth[index][player] != 0 && lootboxDay[index][player] == 0) revert E();
        if (lootboxRngWordByIndex[index] != 0) revert E();

        _requireLootboxRngLinkBalance();
        uint256 burnieCost = _lootboxRngRollCost();
        coin.burnCoin(player, burnieCost);
        if (!_tryRequestLootboxRng(index)) revert E();

        uint256 threshold = lootboxRngThreshold;
        if (threshold == 0) {
            threshold = 1 ether / ContractAddresses.COST_DIVISOR;
        }
        uint256 pending = lootboxRngPendingEth;
        if (pending > threshold) {
            lootboxRngPendingEth = pending - threshold;
        } else {
            lootboxRngPendingEth = 0;
        }
        lootboxRngIndex = index + 1;
        emit LootboxRngRolled(player, index, burnieCost);
    }

    function _maybeRequestLootboxRng(uint256 lootBoxAmount) private {
        uint256 threshold = lootboxRngThreshold;
        if (threshold == 0) {
            threshold = 1 ether / ContractAddresses.COST_DIVISOR;
        }

        uint256 pending = lootboxRngPendingEth + lootBoxAmount;
        if (pending < threshold) {
            lootboxRngPendingEth = pending;
            return;
        }

        uint48 index = lootboxRngIndex;
        if (_tryRequestLootboxRng(index)) {
            lootboxRngPendingEth = pending - threshold;
            lootboxRngIndex = index + 1;
        } else {
            lootboxRngPendingEth = pending;
        }
    }

    function _tryRequestLootboxRng(uint48 index) private returns (bool requested) {
        if (index == 0) return false;
        if (lootboxRngWordByIndex[index] != 0) return false;
        if (
            address(vrfCoordinator) == address(0) ||
            vrfKeyHash == bytes32(0) ||
            vrfSubscriptionId == 0
        ) {
            return false;
        }

        try
            vrfCoordinator.requestRandomWords(
                VRFRandomWordsRequest({
                    keyHash: vrfKeyHash,
                    subId: vrfSubscriptionId,
                    requestConfirmations: LOOTBOX_VRF_REQUEST_CONFIRMATIONS,
                    callbackGasLimit: LOOTBOX_VRF_CALLBACK_GAS_LIMIT,
                    numWords: 1,
                    extraArgs: hex""
                })
            )
        returns (uint256 requestId) {
            lootboxRngRequestIndexById[requestId] = index;
            requested = true;
        } catch {}
    }

    function _lootboxRngRollCost() private view returns (uint256 cost) {
        uint256 priceWei = price;
        if (priceWei == 0) revert E();
        uint256 ethEquivalent;
        try admin._linkAmountToEth(LOOTBOX_RNG_LINK_COST) returns (uint256 ethAmount) {
            ethEquivalent = ethAmount;
        } catch {
            revert LinkPriceUnavailable();
        }
        if (ethEquivalent == 0) revert LinkPriceUnavailable();
        cost = (ethEquivalent * PRICE_COIN_UNIT) / priceWei;
        if (cost == 0) revert LinkPriceUnavailable();
    }

    function _requireLootboxRngLinkBalance() private view {
        uint256 minBalance = lootboxRngMinLinkBalance;
        if (minBalance == 0) return;

        uint256 subId = vrfSubscriptionId;
        address coordinator = address(vrfCoordinator);
        if (subId == 0 || coordinator == address(0)) revert LinkBalanceUnavailable();

        try
            IVRFCoordinator(coordinator).getSubscription(subId)
        returns (uint96 balance, uint96, uint64, address, address[] memory) {
            if (uint256(balance) < minBalance) revert LinkBalanceTooLow();
        } catch {
            revert LinkBalanceUnavailable();
        }
    }

    /// @dev Check and clear expired boost, return whether still active
    function _checkBoostExpired(bool hasBoost, uint48 timestamp) private view returns (bool) {
        if (!hasBoost) return false;
        return block.timestamp <= uint256(timestamp) + LOOTBOX_BOOST_EXPIRY_SECONDS;
    }

    /// @dev Calculate boost amount given base amount and bonus bps
    function _calculateBoost(uint256 amount, uint16 bonusBps) private pure returns (uint256) {
        uint256 cappedAmount = amount > LOOTBOX_BOOST_MAX_VALUE ? LOOTBOX_BOOST_MAX_VALUE : amount;
        return (cappedAmount * bonusBps) / 10_000;
    }

    function _applyLootboxBoostOnPurchase(
        address player,
        uint48 day,
        uint256 amount
    ) private returns (uint256 boostedAmount) {
        boostedAmount = amount;
        uint16 consumedBoostBps = 0;

        // Check 15% boost first (rarer, better boost)
        bool has15 = _checkBoostExpired(lootboxBoon15Active[player], lootboxBoon15Timestamp[player]);
        if (!has15 && lootboxBoon15Active[player]) {
            lootboxBoon15Active[player] = false;
        }
        if (has15) {
            boostedAmount += _calculateBoost(amount, LOOTBOX_BOOST_15_BONUS_BPS);
            consumedBoostBps = LOOTBOX_BOOST_15_BONUS_BPS;
            lootboxBoon15Active[player] = false;
        } else {
            // Check 5% boost if no 15% boost
            bool has5 = _checkBoostExpired(lootboxBoon5Active[player], lootboxBoon5Timestamp[player]);
            if (!has5 && lootboxBoon5Active[player]) {
                lootboxBoon5Active[player] = false;
            }
            if (has5) {
                boostedAmount += _calculateBoost(amount, LOOTBOX_BOOST_5_BONUS_BPS);
                consumedBoostBps = LOOTBOX_BOOST_5_BONUS_BPS;
                lootboxBoon5Active[player] = false;
            }
        }

        if (consumedBoostBps != 0) {
            emit BoostUsed(player, day, amount, boostedAmount, consumedBoostBps);
        }
    }







    function _currentDayIndex() private view returns (uint48) {
        uint48 currentDayBoundary = uint48((block.timestamp - JACKPOT_RESET_TIME) / 1 days);
        return currentDayBoundary - ContractAddresses.DEPLOY_DAY_BOUNDARY + 1;
    }











    function _entropyStep(uint256 state) private pure returns (uint256) {
        unchecked {
            state ^= state << 7;
            state ^= state >> 9;
            state ^= state << 8;
        }
        return state;
    }


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
}
