// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title DegenerusGame
 * @author Burnie Degenerus
 * @notice Core gamepiece game contract managing state machine, VRF integration, ContractAddresses.JACKPOTS, and prize pools.
 *
 * @dev ARCHITECTURE:
 *      - 3-state FSM: SETUP(1) → PURCHASE(2) → BURN(3) → SETUP(1) → (cycle)
 *      - GAMEOVER(86) is terminal
 *      - Presale is a toggle (lootboxPresaleActive), not a state
 *      - Chainlink VRF for randomness with RNG lock to prevent manipulation
 *      - Delegatecall modules: endgame, jackpot, mint (must inherit DegenerusGameStorage)
 *      - Prize pool flow: futurePrizePool (unified reserve) → nextPrizePool → currentPrizePool → claimableWinnings
 *
 * @dev CRITICAL INVARIANTS:
 *      - address(this).balance + steth.balanceOf(this) >= claimablePool
 *      - gameState transitions: 1→2→3→1→2 (starts at 1, 86 = terminal)
 *      - lootboxPresaleActive starts true, auto-ends at PURCHASE→BURN or via admin (one-way: never re-enables)
 *
 * @dev SECURITY:
 *      - Pull pattern for ETH/stETH withdrawals (claimWinnings)
 *      - RNG lock prevents state manipulation during VRF callback window
 *      - Access control via msg.sender checks
 *      - Delegatecall modules use constant addresses from ContractAddresses
 *      - 18h VRF timeout, 3-day stall detection, 365-day inactivity guard
 */

import {IDegenerusGamepieces} from "./interfaces/IDegenerusGamepieces.sol";
import {IDegenerusCoin} from "./interfaces/IDegenerusCoin.sol";
import {IBurnieCoinflip} from "./interfaces/IBurnieCoinflip.sol";
import {IBurnieLootbox} from "./interfaces/IBurnieLootbox.sol";
import {IDegenerusAffiliate} from "./interfaces/IDegenerusAffiliate.sol";
import {IDegenerusJackpots} from "./interfaces/IDegenerusJackpots.sol";
import {IDegenerusStonk} from "./interfaces/IDegenerusStonk.sol";
import {IDegenerusLazyPass} from "./interfaces/IDegenerusLazyPass.sol";
import {IDegenerusTrophies} from "./interfaces/IDegenerusTrophies.sol";
import {IStETH} from "./interfaces/IStETH.sol";
import {
    IDegenerusGameAdvanceModule,
    IDegenerusGameEndgameModule,
    IDegenerusGameGameOverModule,
    IDegenerusGameJackpotModule,
    IDegenerusGameDecimatorModule,
    IDegenerusGameMintModule,
    IDegenerusGameWhaleModule
} from "./interfaces/IDegenerusGameModules.sol";
import {MintPaymentKind} from "./interfaces/IDegenerusGame.sol";
import {DegenerusGameStorage} from "./storage/DegenerusGameStorage.sol";
import {ContractAddresses} from "./ContractAddresses.sol";

/*+==============================================================================+
  |                     EXTERNAL INTERFACE DEFINITIONS                           |
  +==============================================================================+
  |  Minimal interfaces for external contracts this contract interacts with.     |
  |  These are defined locally to avoid circular import dependencies.            |
  +==============================================================================+*/

/// @notice Interface for reading player quest states.
interface IDegenerusQuestView {
    /// @notice Get a player's quest progress and streak information.
    function playerQuestStates(
        address player
    )
        external
        view
        returns (
            uint32 streak,
            uint32 lastCompletedDay,
            uint128[2] memory progress,
            bool[2] memory completed
        );
}

/// @notice Minimal ERC721 interface for trophy balance checks.
interface IERC721BalanceOf {
    /// @notice Get gamepiece count for an owner.
    function balanceOf(address owner) external view returns (uint256);
}

// ===========================================================================
// Contract
// ===========================================================================

/**
 * @title DegenerusGame
 * @author Burnie Degenerus
 * @notice Core gamepiece game contract implementing the game state machine, VRF integration,
 *         and orchestration of all gameplay mechanics.
 * @dev Inherits DegenerusGameStorage for shared storage layout with delegate modules.
 *      Uses delegatecall pattern for complex logic (endgame, jackpot, mint modules).
 * @custom:security-contact burnie@degener.us
 */
contract DegenerusGame is DegenerusGameStorage {
    /*+======================================================================+
      |                              ERRORS                                  |
      +======================================================================+
      |  Custom errors for gas-efficient reverts. Each error maps to a       |
      |  specific failure condition in the game flow.                        |
      +======================================================================+*/

    /// @notice Generic guard error for failed validation checks.
    /// @dev Used in multiple paths where specific error context isn't critical.
    error E();

    /// @notice Caller must have completed an ETH mint today before advancing.
    /// @dev Gate prevents advancing without skin-in-the-game (except when cap != 0).
    error MustMintToday();

    /// @notice Called in a phase where the action is not permitted.
    /// @dev Game state machine enforces phase-specific operations.
    error NotTimeYet();

    /// @notice VRF request is still pending; cannot proceed.
    /// @dev Operations requiring randomness must wait for VRF fulfillment.
    error RngNotReady();

    /// @notice RNG is locked (VRF pending); nudge operations blocked.
    /// @dev reverseFlip() is only available before RNG request starts.
    error RngLocked();

    /// @notice Invalid quantity for burn or other batched operations.
    /// @dev Enforces bounds: 1-75 tokens per burn call.
    error InvalidQuantity();

    /// @notice VRF coordinator swap not allowed yet.
    /// @dev Requires 3-day RNG stall before emergency rotation is permitted.
    error VrfUpdateNotReady();

    /// @notice afKing mode cannot be disabled yet (lock period active).
    error AfKingLockActive();

    /// @notice Caller is not approved to act for the requested player.
    error NotApproved();

    /*+======================================================================+
      |                              EVENTS                                  |
      +======================================================================+
      |  Events for off-chain indexers and UIs. All critical state changes   |
      |  emit events for transparency and auditability.                      |
      +======================================================================+*/

    /// @notice Emitted when ETH winnings are credited to a player's claimable balance.
    /// @param player The original beneficiary (may be same as recipient).
    /// @param recipient The address receiving the credit.
    /// @param amount The wei amount credited.
    event PlayerCredited(
        address indexed player,
        address indexed recipient,
        uint256 amount
    );

    /// @notice Emitted when a player burns tokens for jackpot tickets.
    /// @param player The player who burned the tokens.
    /// @param tokenIds Array of token IDs that were burned.
    event Degenerus(address indexed player, uint256[] tokenIds);

    /// @notice Emitted each time the game advances (state machine tick).
    /// @param gameState The current game state after advancement.
    event Advance(uint8 gameState);

    /// @notice Emitted when a player pays BURNIE to nudge the next RNG word.
    /// @param caller The player who paid for the nudge.
    /// @param totalQueued Total nudges queued for next fulfillment.
    /// @param cost The BURNIE cost paid for this nudge.
    event ReverseFlip(
        address indexed caller,
        uint256 totalQueued,
        uint256 cost
    );

    /// @notice Emitted when the VRF coordinator is rotated (emergency or initial wire).
    /// @param previous The previous coordinator address (address(0) if first wire).
    /// @param current The new coordinator address.
    event VrfCoordinatorUpdated(
        address indexed previous,
        address indexed current
    );

    /// @notice Emitted when a loot box purchase is recorded.
    /// @param buyer Loot box purchaser.
    /// @param day Purchase day index.
    /// @param amount Total ETH contributed.
    /// @param presale True if purchased during loot box presale mode.
    /// @param futureShare ETH reserved for future prize pool funding.
    /// @param nextPrizeShare ETH added to nextPrizePool.
    /// @param vaultShare ETH forwarded to the vault (presale only).
    /// @param rewardShare ETH added to future pool (unified reserve).
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
    /// @notice Emitted when a loot box RNG index is assigned to a buyer.
    /// @param buyer Loot box purchaser.
    /// @param index Lootbox RNG index assigned at purchase time.
    /// @param day Purchase day index.
    event LootBoxIndexAssigned(
        address indexed buyer,
        uint48 indexed index,
        uint48 indexed day
    );
    /// @notice Emitted when a BURNIE loot box purchase is recorded.
    /// @param buyer Loot box purchaser.
    /// @param index Lootbox RNG index assigned at purchase time.
    /// @param burnieAmount Total BURNIE burned.
    event BurnieLootBoxPurchased(
        address indexed buyer,
        uint48 indexed index,
        uint256 burnieAmount
    );

    /// @notice Emitted when a loot box is opened.
    /// @param player Loot box owner.
    /// @param day Purchase day index.
    /// @param amount ETH amount resolved.
    /// @param futureLevel Base future level (currentLevel + offset at open time, not purchase).
    /// @param futureTickets Total future tickets awarded across futureLevel..futureLevel+4.
    /// @param currentTickets Current-level tickets awarded (always 0 for loot box rolls).
    /// @param burnie BURNIE credited for loot box EV.
    /// @param bonusBurnie Bonus BURNIE from presale or player multiplier (if any).
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
    /// @notice Emitted when a BURNIE loot box is opened.
    /// @param player Loot box owner.
    /// @param day Resolve day index.
    /// @param burnieAmount Total BURNIE resolved.
    /// @param ticketLevel Ticket level for any awards.
    /// @param tickets Total tickets awarded.
    /// @param burnieReward BURNIE credited from the loot box.
    event BurnieLootBoxOpened(
        address indexed player,
        uint48 indexed day,
        uint256 burnieAmount,
        uint24 ticketLevel,
        uint32 tickets,
        uint256 burnieReward
    );
    /// @notice Emitted when a loot box decays (value halved).
    /// @param player Loot box owner.
    /// @param day Purchase day index.
    /// @param originalAmount Original ETH amount.
    /// @param decayedAmount Halved ETH amount applied to rewards.
    event LootBoxDecayed(
        address indexed player,
        uint48 indexed day,
        uint256 originalAmount,
        uint256 decayedAmount
    );

    /// @notice Emitted when loot box presale mode is toggled.
    /// @param active True if presale mode is active.
    event LootBoxPresaleStatus(bool active);

    /// @notice Emitted when the lootbox RNG request threshold is updated.
    /// @param previous Previous threshold in wei.
    /// @param current New threshold in wei.
    event LootboxRngThresholdUpdated(uint256 previous, uint256 current);
    /// @notice Emitted when the lootbox RNG min LINK balance is updated.
    /// @param previous Previous minimum LINK balance.
    /// @param current New minimum LINK balance.
    event LootboxRngMinLinkBalanceUpdated(uint256 previous, uint256 current);
    /// @notice Emitted when a player forces a lootbox RNG roll.
    /// @param player Player who paid the BURNIE cost.
    /// @param index Lootbox RNG index requested.
    /// @param burnieCost BURNIE cost burned to request RNG.
    event LootboxRngRolled(
        address indexed player,
        uint48 indexed index,
        uint256 burnieCost
    );

    /// @notice Emitted when a player approves or revokes an operator.
    /// @param owner The player granting approval.
    /// @param operator The approved operator.
    /// @param approved True if approved, false if revoked.
    event OperatorApproval(
        address indexed owner,
        address indexed operator,
        bool approved
    );

    event TributeAddressUpdated(
        address indexed previous,
        address indexed current
    );

    /*+=======================================================================+
      |                   PRECOMPUTED ADDRESSES (CONSTANT)                    |
      +=======================================================================+
      |  Core contract references are read from ContractAddresses and baked   |
      |  into bytecode. They cannot change after deployment.                  |
      +=======================================================================+*/

    /// @notice The BURNIE ERC20 token contract.
    /// @dev Trusted for creditCoin, burnCoin, quest notifications, etc.
    IDegenerusCoin internal constant coin =
        IDegenerusCoin(ContractAddresses.COIN);

    /// @notice The BurnieCoinflip contract for coinflip wagering.
    /// @dev Trusted for processCoinflipPayouts, recordAfKingRng, creditFlip, etc.
    IBurnieCoinflip internal constant coinflip =
        IBurnieCoinflip(ContractAddresses.COINFLIP);

    /// @notice The BurnieLootbox contract for lootbox purchases and rewards.
    /// @dev Standalone contract handling all lootbox logic and boon management.
    IBurnieLootbox internal constant lootbox =
        IBurnieLootbox(ContractAddresses.LOOTBOX);

    /// @notice The gamepieces contract (ERC721).
    /// @dev Trusted for mint/burn/metadata operations.
    IDegenerusGamepieces internal constant gamepieces =
        IDegenerusGamepieces(ContractAddresses.GAMEPIECES);

    /// @notice Lido stETH token contract.
    /// @dev Used for staking ETH and managing yield.
    IStETH internal constant steth = IStETH(ContractAddresses.STETH_TOKEN);

    /// @notice DegenerusJackpots contract for decimator/BAF jackpots.
    IDegenerusJackpots internal constant jackpots =
        IDegenerusJackpots(ContractAddresses.JACKPOTS);

    /// @notice Affiliate program contract for bonus points and referrers.
    IDegenerusAffiliate internal constant affiliate =
        IDegenerusAffiliate(ContractAddresses.AFFILIATE);

    /// @notice DGNRS token contract for affiliate pool rewards.
    IDegenerusStonk internal constant dgnrs =
        IDegenerusStonk(ContractAddresses.DGNRS);

    /// @notice Quest module view interface for streak lookups.
    IDegenerusQuestView internal constant questView =
        IDegenerusQuestView(ContractAddresses.QUESTS);

    /// @notice Trophy contract for balance checks.
    IERC721BalanceOf internal constant trophies =
        IERC721BalanceOf(ContractAddresses.TROPHIES);
    /// @notice Trophy contract for mint/burn operations.
    IDegenerusTrophies internal constant trophyMinter =
        IDegenerusTrophies(ContractAddresses.TROPHIES);

    /// @notice Lazy pass token contract (10-level pass credits).
    IDegenerusLazyPass internal constant lazyPass =
        IDegenerusLazyPass(ContractAddresses.LAZY_PASS);

    /*+======================================================================+
      |                           CONSTANTS                                  |
      +======================================================================+
      |  Game parameters and bit manipulation constants. All constants are   |
      |  private to prevent external dependency on specific values.          |
      +======================================================================+*/

    /// @dev Maximum idle time before game-over drain (2.5 years = 912.5 days).
    ///      Triggers if game is deployed but never started.
    uint256 private constant DEPLOY_IDLE_TIMEOUT = (365 days * 5) / 2;

    /// @dev Deploy idle timeout in days (for efficient day-index comparison).
    uint48 private constant DEPLOY_IDLE_TIMEOUT_DAYS = 912; // 2.5 years

    /// @dev Deity pass refund window (24 months) if level 1 never starts.
    uint48 private constant DEITY_PASS_REFUND_DAYS = 730;

    /// @dev Deity pass price (kept in sync with whale module).
    uint256 private constant DEITY_PASS_PRICE = 25 ether / ContractAddresses.COST_DIVISOR;

    /// @dev Sentinel value for levelStartTime indicating "not started".
    uint48 private constant LEVEL_START_SENTINEL = type(uint48).max;

    /// @dev Anchor timestamp for day window calculations.
    ///      Days are offset from unix midnight by this value (~23 hours).
    uint48 private constant JACKPOT_RESET_TIME = 82620;
    /// @dev Coinflip boon expiry window.
    uint48 private constant COINFLIP_BOON_EXPIRY_SECONDS = 172800;
    /// @dev Purchase boost expiry window (gamepieces/tickets).
    uint48 private constant PURCHASE_BOOST_EXPIRY_SECONDS = 345600;

    /// @dev Minimum wait before using fallback entropy in game-over mode.
    uint48 private constant GAMEOVER_RNG_FALLBACK_DELAY = 3 days;

    /// @dev Maximum ContractAddresses.JACKPOTS per level before forced advancement.
    uint8 private constant JACKPOT_LEVEL_CAP = 10;

    /// @dev Ticket jackpot type: no ticket jackpot pending.
    uint8 private constant TICKET_JACKPOT_NONE = 0;

    /// @dev Sentinel value for "no extermination yet" / "no last level extermination".
    uint16 private constant TRAIT_ID_TIMEOUT = 420;

    /// @dev Gas limit for VRF callback (200k is sufficient for simple fulfillment).
    uint32 private constant VRF_CALLBACK_GAS_LIMIT = 200_000;

    /// @dev Block confirmations required before VRF result is final.
    uint16 private constant VRF_REQUEST_CONFIRMATIONS = 10;

    /// @dev Base BURNIE cost for reverseFlip() nudge (100 BURNIE).
    ///      Compounds +50% per queued nudge.
    uint256 private constant RNG_NUDGE_BASE_COST = 100 ether;

    /// @dev Auto-rebuy bonus in basis points (30% = 13000).
    uint16 private constant AUTO_REBUY_BONUS_BPS = 13000;

    /// @dev afKing auto-rebuy bonus in basis points (45% = 14500).
    uint16 private constant AFKING_AUTO_REBUY_BONUS_BPS = 14500;

    /// @dev Minimum keep-multiple for afKing ETH auto-rebuy (5 ETH, testnet-scaled).
    uint256 private constant AFKING_KEEP_MIN_ETH =
        5 ether / ContractAddresses.COST_DIVISOR;

    /// @dev Minimum keep-multiple for afKing coin auto-rebuy (20,000 BURNIE).
    uint256 private constant AFKING_KEEP_MIN_COIN = 20_000 ether;

    /// @dev Number of levels afKing mode is locked after activation.
    uint24 private constant AFKING_LOCK_LEVELS = 5;

    /// @dev Time-based split: next → future pool bps when target is hit quickly.
    uint16 private constant NEXT_TO_FUTURE_BPS_FAST = 2000; // 20%

    /// @dev Time-based split: minimum next → future pool bps (~2 weeks).
    uint16 private constant NEXT_TO_FUTURE_BPS_MIN = 300; // 3%

    /// @dev Time-based split: post-4w increase (1% per week).
    uint16 private constant NEXT_TO_FUTURE_BPS_WEEK_STEP = 100; // 1%

    /// @dev Bonus bps for x9 levels (retains extra in future pool).
    uint16 private constant NEXT_TO_FUTURE_BPS_X9_BONUS = 200; // 2%

    /// @dev Share of gamepiece/ticket purchases routed to future prize pool (10%).
    uint16 private constant PURCHASE_TO_FUTURE_BPS = 1000;

    /// @dev Domain separator for next-skim variance.
    bytes32 private constant NEXT_SKIM_VARIANCE_TAG =
        keccak256("next-skim-variance");

    /// @dev Variance band for next-skim amount (bps of base take).
    uint16 private constant NEXT_SKIM_VARIANCE_BPS = 1000; // +/-10%

    /// @dev Minimum variance band for next-skim amount (bps of nextPrizePool).
    uint16 private constant NEXT_SKIM_VARIANCE_MIN_BPS = 1000; // +/-10%

    /// @dev Total share of currentPrizePool reserved for ETH perk burns (5%).
    uint16 private constant ETH_PERK_TOTAL_BPS = 500;

    /// @dev Bonus multiplier for ETH perk payouts when Q0 symbol is Ethereum (1.25x = 12,500 bps).
    uint16 private constant ETH_PERK_BONUS_BPS = 12_500;

    /// @dev Total share of lastPrizePool reserved for BURNIE perk burns (5%).
    uint16 private constant BURNIE_PERK_TOTAL_BPS = 500;

    /// @dev Total share of DGNRS reward pool reserved for lazy-pass perk burns (5%).
    uint16 private constant DGNRS_PERK_TOTAL_BPS = 500;

    /// @dev Bonus multiplier for DGNRS perk payouts when Q1 symbol is Aquarius (1.25x = 12,500 bps).
    uint16 private constant DGNRS_PERK_AQUARIUS_BONUS_BPS = 12_500;

    /// @dev Bonus multiplier for BURNIE perk payouts when Q0 symbol is Ethereum or WWXRP (1.25x).
    uint16 private constant BURNIE_PERK_SYMBOL_BONUS_BPS = 12_500;

    /// @dev Max share of affiliate DGNRS pool distributed per level (5%).
    uint16 private constant AFFILIATE_DGNRS_LEVEL_BPS = 500;

    /// @dev DGNRS bounty share for biggest flip payout (0.5% of reward pool).
    uint16 private constant COINFLIP_BOUNTY_DGNRS_BPS = 50;

    /// @dev Bonus BURNIE flip credit for deity pass affiliate claims (20% of payout).
    uint16 private constant AFFILIATE_DGNRS_DEITY_BONUS_BPS = 2000;

    /// @dev Minimum affiliate score (approx 10 ETH of referral volume).
    uint256 private constant AFFILIATE_DGNRS_MIN_SCORE =
        10 ether / ContractAddresses.COST_DIVISOR;

    /// @dev Deity pass activity score bonus (80%).
    uint16 private constant DEITY_PASS_ACTIVITY_BONUS_BPS = 8000;

    /// @dev Q0 symbol index for Ethereum in the crypto quadrant.
    uint8 private constant ETH_SYMBOL_INDEX = 6;

    /// @dev Q0 symbol index for WWXRP in the crypto quadrant.
    uint8 private constant WWXRP_SYMBOL_INDEX = 0;

    /// @dev Q1 symbol index for Aquarius in the zodiac quadrant.
    uint8 private constant AQUARIUS_SYMBOL_INDEX = 7;

    /// @dev Cards quadrant: orange king (color 5, symbol 1).
    uint8 private constant ORANGE_KING_COLOR = 5;
    uint8 private constant ORANGE_KING_SYMBOL = 1;

    /// @dev Tribute per orange-king burn (25 BURNIE).
    uint256 private constant ORANGE_KING_TRIBUTE = 25 ether;

    /// @dev ETH perk selection odds (1 / 100).
    uint8 private constant ETH_PERK_ODDS = 100;

    /// @dev ETH perk selection remainder (keccak % 100 == 0).
    uint8 private constant ETH_PERK_REMAINDER = 0;

    /// @dev BURNIE perk selection remainder (keccak % 100 == 1).
    uint8 private constant BURNIE_PERK_REMAINDER = 1;

    /// @dev DGNRS perk selection remainder (keccak % 100 == 2).
    uint8 private constant DGNRS_PERK_REMAINDER = 2;

    /// @dev Salt mixed into ETH perk selection hash (ASCII "ETH").
    uint256 private constant ETH_PERK_SALT = 0x455448;

    /*+======================================================================+
      |                    MINT PACKED BIT LAYOUT                            |
      +======================================================================+
      |  Player mint history is packed into a single uint256 for gas         |
      |  efficiency. Layout (LSB first):                                     |
      |                                                                      |
      |  [0-23]   lastEthLevel     - Last level where player minted with ETH |
      |  [24-47]  ethLevelCount    - Total levels with ETH mints             |
      |  [48-71]  ethLevelStreak   - Consecutive levels with ETH mints       |
      |  [72-103] lastEthDay       - Day index of last ETH mint              |
      |  [104-127] unitsLevel      - Level index for unitsAtLevel tracking   |
      |  [128-151] frozenUntilLevel - Whale bundle freeze level (0 = none)   |
      |  [152-153] whaleBundleType  - Bundle type (0=none,1=10,3=100)        |
      |  [154-227] reserved        - Reserved for forward compatibility      |
      |  [228-243] unitsAtLevel    - Mints at current level                  |
      |  [244]    (deprecated)     - Previously used for bonus tracking      |
      +======================================================================+*/

    /// @dev Bit mask for 24-bit fields.
    uint256 private constant MINT_MASK_24 = (uint256(1) << 24) - 1;

    /// @dev Bit mask for 32-bit fields.
    uint256 private constant MINT_MASK_32 = (uint256(1) << 32) - 1;

    /// @dev Bit shift for lastEthLevel field.
    uint256 private constant ETH_LAST_LEVEL_SHIFT = 0;

    /// @dev Bit shift for ethLevelCount field.
    uint256 private constant ETH_LEVEL_COUNT_SHIFT = 24;

    /// @dev Bit shift for ethLevelStreak field.
    uint256 private constant ETH_LEVEL_STREAK_SHIFT = 48;

    /// @dev Bit shift for lastEthDay field.
    uint256 private constant ETH_DAY_SHIFT = 72;

    /// @dev Bit shift for frozen-until-level field.
    uint256 private constant ETH_FROZEN_UNTIL_LEVEL_SHIFT = 128;

    /// @dev Bit shift for whale bundle type field (2 bits).
    uint256 private constant ETH_WHALE_BUNDLE_TYPE_SHIFT = 152;

    /*+======================================================================+
      |                          CONSTRUCTOR                                 |
      +======================================================================+
      |  Initialize storage wiring and set up initial approvals.             |
      |  The constructor wires together the entire game ecosystem.           |
      +======================================================================+*/

    /**
     * @notice Initialize the game with precomputed contract references.
     * @dev All addresses and deploy day boundary are compile-time constants from ContractAddresses.
     *      gameState and levelStartTime are initialized at declaration in DegenerusGameStorage.
     *      Deploy day boundary determines which calendar day is "day 1" in the game.
     */
    constructor() {
        whalePassClaims[ContractAddresses.DGNRS] = 1;
        deityPassCount[ContractAddresses.DGNRS] = 1;
        deityPassOwners.push(ContractAddresses.DGNRS);
        deityPassCount[ContractAddresses.VAULT] = 1;
        deityPassOwners.push(ContractAddresses.VAULT);
    }

    /*+======================================================================+
      |                           MODIFIERS                                  |
      +======================================================================+*/

    /*+========================================================================================+
      |                    CORE STATE MACHINE: advanceGame()                                   |
      +========================================================================================+
      |  The heart of the game. This function progresses the state machine                     |
      |  through its 3 states: SETUP(1), PURCHASE(2), DEGENERUS(3).                            |
      |  Each call performs one "tick" of work. GAMEOVER(86) is terminal.                      |
      |                                                                                        |
      |  State Transitions:                                                                    |
      |  • State 1 (SETUP): Run endgame settlement, then → 2                                   |
      |  • State 2 (PURCHASE): Process airdrops until target met, then → 3                     |
      |  • State 3 (DEGENERUS): Pay daily ContractAddresses.JACKPOTS, wait for burns, then → 1 |
      |  • State 86 (GAMEOVER): Terminal state, no transitions                                 |
      |                                                                                        |
      |  Gating:                                                                               |
      |  • Standard calls require caller to have minted today (skin-in-game)                   |
      |  • cap != 0 bypasses gate but forfeits BURNIE reward                                   |
      |  • RNG must be ready (not locked) or recently stale (18h timeout)                      |
      |                                                                                        |
      |  Presale: lootboxPresaleActive toggle (orthogonal to state machine)                    |
      |  • Starts active: 2x BURNIE from loot boxes, bonusFlip active                          |
      |  • Auto-ends when PURCHASE→BURN, or admin can end manually (one-way, cannot re-enable)|
      +========================================================================================+*/

    /// @notice Advance the game state machine by one tick.
    /// @dev Anyone can call, but standard flows require an ETH mint today.
    ///      This is the primary driver of game progression - called repeatedly
    ///      to move through states and process batched operations.
    ///
    ///      FLOW OVERVIEW:
    ///      1. Check liveness guards (2.5yr deploy timeout, 365-day inactivity)
    ///      2. Apply daily gate (must have minted today unless cap != 0)
    ///      3. Process dormant cleanup if in setup state
    ///      4. Gate on RNG readiness (request new VRF if needed)
    ///      5. Process ticket batches
    ///      6. Execute state-specific logic:
    ///         - SETUP: Run endgame settlement and queue prep before advancing to PURCHASE
    ///         - PURCHASE/BURN: Process phase-specific logic
    ///      7. Credit caller with BURNIE reward (if cap == 0)
    ///
    ///      SECURITY:
    ///      - Liveness guards prevent abandoned game lockup
    ///      - Daily gate prevents non-participants from advancing
    ///      - RNG gating ensures fairness (no manipulation during VRF window)
    ///      - Batched processing prevents DoS from large queues
    ///
    /// @param cap Gas budget override for batched operations.
    ///            0 = standard flow with BURNIE reward.
    ///            >0 = emergency unstuck mode (no BURNIE reward).
    function advanceGame(uint32 cap) external {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_ADVANCE_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameAdvanceModule.advanceGame.selector,
                    cap
                )
            );
        if (!ok) _revertDelegate(data);
    }

    /*+========================================================================================+
      |                    ADMIN VRF FUNCTIONS                                                 |
      +========================================================================================+
      |  One-time VRF setup function called by ContractAddresses.ADMIN during deployment phase.|
      +========================================================================================+*/

    /// @notice One-time wiring of VRF config from the VRF ContractAddresses.ADMIN contract.
    /// @dev Access: ContractAddresses.ADMIN only. Idempotent after first wire (repeats must match).
    ///      SECURITY: Once wired, config cannot be changed except via emergency rotation.
    /// @param coordinator_ Chainlink VRF V2.5 coordinator address.
    /// @param subId VRF subscription ID for LINK billing.
    /// @param keyHash_ VRF key hash identifying the oracle and gas lane.
    function wireVrf(
        address coordinator_,
        uint256 subId,
        bytes32 keyHash_
    ) external {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_ADVANCE_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameAdvanceModule.wireVrf.selector,
                    coordinator_,
                    subId,
                    keyHash_
                )
            );
        if (!ok) _revertDelegate(data);
    }

    /*+======================================================================+
      |                       MINT RECORDING                                 |
      +======================================================================+
      |  Functions called by the gamepiece contract to record mints and process    |
      |  payments. ETH and claimable winnings can both fund purchases.       |
      +======================================================================+*/

    /// @notice Record a mint, funded by ETH or claimable winnings.
    /// @dev Access: gamepieces contract only.
    ///      Payment modes:
    ///      - DirectEth: msg.value must exactly equal costWei
    ///      - Claimable: deduct from claimableWinnings (msg.value must be 0)
    ///      - Combined: ETH first, then claimable for remainder
    ///
    ///      SECURITY: Validates exact payment amounts to prevent over/underpayment.
    ///      Prize contribution is split between nextPrizePool and futurePrizePool.
    ///
    /// @param player The player address to record mint for.
    /// @param lvl The level at which mint is occurring.
    /// @param costWei Total cost in wei for this mint.
    /// @param mintUnits Number of mint units purchased.
    /// @param payKind Payment method (DirectEth, Claimable, or Combined).
    /// @return coinReward BURNIE reward credited for this mint.
    /// @return newClaimableBalance Player's claimable balance after deduction (0 if DirectEth).
    function recordMint(
        address player,
        uint24 lvl,
        uint256 costWei,
        uint32 mintUnits,
        MintPaymentKind payKind
    )
        external
        payable
        returns (uint256 coinReward, uint256 newClaimableBalance)
    {
        if (msg.sender != ContractAddresses.GAMEPIECES) revert E();
        uint256 prizeContribution;
        (prizeContribution, newClaimableBalance) = _processMintPayment(
            player,
            costWei,
            payKind
        );
        if (prizeContribution != 0) {
            uint256 futureShare = (prizeContribution * PURCHASE_TO_FUTURE_BPS) / 10_000;
            if (futureShare != 0) {
                futurePrizePool += futureShare;
            }
            uint256 nextShare = prizeContribution - futureShare;
            if (nextShare != 0) {
                nextPrizePool += nextShare;
            }
        }

        coinReward = _recordMintDataModule(player, lvl, mintUnits);
        _awardEarlybirdDgnrs(player, msg.value);
    }

    /// @notice Track coinflip deposits for payout tuning on last purchase day.
    /// @dev Access: coin contract only.
    ///      Coinflip activity on last purchase day affects coinflip payout.
    /// @param amount The wei amount deposited to coinflip.
    function recordCoinflipDeposit(uint256 amount) external {
        if (msg.sender != ContractAddresses.COIN) revert E();
        if (gameState == GAME_STATE_PURCHASE && lastPurchaseDay) {
            lastPurchaseDayFlipTotal += amount;
        }
    }

    /// @notice Pay DGNRS bounty for the biggest flip record holder.
    /// @dev Access: coin contract only.
    ///      Pays a share of the remaining DGNRS reward pool.
    /// @param player Recipient of the DGNRS bounty.
    function payCoinflipBountyDgnrs(address player) external {
        if (msg.sender != ContractAddresses.COIN) revert E();
        if (player == address(0)) return;
        uint256 poolBalance = dgnrs.poolBalance(IDegenerusStonk.Pool.Reward);
        if (poolBalance == 0) return;
        uint256 payout = (poolBalance * COINFLIP_BOUNTY_DGNRS_BPS) / 10_000;
        if (payout == 0) return;
        dgnrs.transferFromPool(IDegenerusStonk.Pool.Reward, player, payout);
    }

    /*+======================================================================+
      |                      OPERATOR APPROVALS                             |
      +======================================================================+*/

    /// @notice Approve or revoke an operator to act on your behalf.
    /// @param operator Address to approve.
    /// @param approved True to approve, false to revoke.
    function setOperatorApproval(address operator, bool approved) external {
        if (operator == address(0)) revert E();
        operatorApprovals[msg.sender][operator] = approved;
        emit OperatorApproval(msg.sender, operator, approved);
    }

    /// @notice Check if an operator is approved to act for a player.
    /// @param owner The player who granted approval.
    /// @param operator The operator address.
    /// @return approved True if operator is approved.
    function isOperatorApproved(
        address owner,
        address operator
    ) external view returns (bool approved) {
        return operatorApprovals[owner][operator];
    }

    function _requireApproved(address player) private view {
        if (msg.sender != player && !operatorApprovals[player][msg.sender]) {
            revert NotApproved();
        }
    }

    /*+======================================================================+
      |                       LOOT BOX CONTROLS                             |
      +======================================================================+*/

    /// @notice End loot box presale mode manually (auto-ends when purchase phase ends).
    /// @dev Access: ContractAddresses.CREATOR only. One-way: cannot be re-enabled.
    ///      Presale starts active by default and auto-ends when gameState → BURN.
    function endLootboxPresale() external {
        if (msg.sender != ContractAddresses.CREATOR) revert E();
        if (!lootboxPresaleActive) revert E();

        lootboxPresaleActive = false;
        emit LootBoxPresaleStatus(false);
    }

    /// @notice Update lootbox RNG request threshold (wei).
    /// @dev Access: ContractAddresses.ADMIN only.
    function setLootboxRngThreshold(uint256 newThreshold) external {
        if (msg.sender != ContractAddresses.ADMIN) revert E();
        if (newThreshold == 0) revert E();
        uint256 prev = lootboxRngThreshold;
        lootboxRngThreshold = newThreshold;
        emit LootboxRngThresholdUpdated(prev, newThreshold);
    }

    /// @notice Update minimum LINK balance required for manual lootbox RNG rolls.
    /// @dev Access: ContractAddresses.ADMIN only.
    function setLootboxRngMinLinkBalance(uint256 newMinBalance) external {
        if (msg.sender != ContractAddresses.ADMIN) revert E();
        if (newMinBalance == 0) revert E();
        uint256 prev = lootboxRngMinLinkBalance;
        lootboxRngMinLinkBalance = newMinBalance;
        emit LootboxRngMinLinkBalanceUpdated(prev, newMinBalance);
    }

    /// @notice Purchase any combination of gamepieces, tickets, and loot boxes with ETH or claimable.
    /// @dev Main entry point for all ETH/claimable purchases. For BURNIE purchases, use DegenerusGamepieces.purchase().
    ///      Spending all claimable winnings earns a 10% bonus across the combined purchase.
    ///      Adds affiliate support for loot box purchases.
    ///      SECURITY: Blocked when RNG is locked.
    /// @param buyer Player address to receive purchases (address(0) = msg.sender).
    /// @param gamepieceQuantity Number of gamepieces to purchase (0 to skip).
    /// @param ticketQuantity Number of tickets to purchase (2 decimals, scaled by 100; 0 to skip).
    /// @param lootBoxAmount ETH amount for loot boxes, minimum 0.01 ETH (0 to skip).
    /// @param affiliateCode Affiliate/referral code for all purchases.
    /// @param payKind Payment method (DirectEth, Claimable, or Combined).
    function purchase(
        address buyer,
        uint256 gamepieceQuantity,
        uint256 ticketQuantity,
        uint256 lootBoxAmount,
        bytes32 affiliateCode,
        MintPaymentKind payKind
    ) external payable {
        if (buyer == address(0)) {
            buyer = msg.sender;
        } else if (buyer != msg.sender) {
            _requireApproved(buyer);
        }
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
        lootbox.purchase{value: msg.value}(
            buyer,
            gamepieceQuantity,
            ticketQuantity,
            lootBoxAmount,
            affiliateCode,
            payKind
        );
    }

    /// @notice Purchase a low-EV loot box using BURNIE.
    /// @param buyer Player address to receive the loot box (address(0) = msg.sender).
    /// @param burnieAmount BURNIE amount to burn (18 decimals).
    function purchaseBurnieLootbox(address buyer, uint256 burnieAmount) external {
        if (buyer == address(0)) {
            buyer = msg.sender;
        } else if (buyer != msg.sender) {
            _requireApproved(buyer);
        }
        _purchaseBurnieLootboxFor(buyer, burnieAmount);
    }

    function _purchaseBurnieLootboxFor(
        address buyer,
        uint256 burnieAmount
    ) private {
        lootbox.purchaseBurnieLootbox(buyer, burnieAmount);
    }

    /// @notice Purchase whale bundle: sets streak/levelCount to 100 and gives 400 tickets + 1 ETH lootbox.
    /// @dev Available when the effective bundle level is %50 == 1 (levels 1, 51, 101, 151...).
    ///      Effective level is current level in setup/purchase, or current level + 1 in burn,
    ///      so the window opens during the previous level's burn and closes at purchase end.
    ///      Can be purchased multiple times. Fixed cost: 6 ETH.
    ///      Sets mint streak and level count to 100, frozen until (bundle level + 99).
    ///      Queues 4 tickets for each of levels [bundle level, bundle level+99] (400 tickets total).
    ///      Includes 1 ETH lootbox for all purchases.
    ///      Frozen stats don't increment until game reaches the frozen level.
    ///
    ///      Fund distribution - Level 1: 50% next/25% reward/25% future.
    ///      Fund distribution - Other levels: 50% future/45% reward/5% next.
    ///
    ///      Example at level 1: 4 tickets each for levels 1-100, stats=100, frozen until 100, 1 ETH lootbox.
    ///      Example at level 51: 4 tickets each for levels 51-150, stats=100, frozen until 150, 1 ETH lootbox.
    /// @param buyer Player address to receive bundle rewards (address(0) = msg.sender).
    /// @param quantity Number of bundles to purchase.
    function purchaseWhaleBundle(
        address buyer,
        uint256 quantity
    ) external payable {
        if (buyer == address(0)) {
            buyer = msg.sender;
        } else if (buyer != msg.sender) {
            _requireApproved(buyer);
        }
        _purchaseWhaleBundleFor(buyer, quantity);
    }

    function _purchaseWhaleBundleFor(
        address buyer,
        uint256 quantity
    ) private {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_WHALE_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameWhaleModule.purchaseWhaleBundle.selector,
                    buyer,
                    quantity
                )
            );
        if (!ok) _revertDelegate(data);
    }

    /// @param buyer Player address to receive bundle rewards (address(0) = msg.sender).
    /// @param quantity Number of bundles to purchase.
    function purchaseWhaleBundle10(
        address buyer,
        uint256 quantity
    ) external payable {
        if (buyer == address(0)) {
            buyer = msg.sender;
        } else if (buyer != msg.sender) {
            _requireApproved(buyer);
        }
        _purchaseWhaleBundle10For(buyer, quantity);
    }

    function _purchaseWhaleBundle10For(
        address buyer,
        uint256 quantity
    ) private {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_WHALE_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameWhaleModule.purchaseWhaleBundle10.selector,
                    buyer,
                    quantity
                )
            );
        if (!ok) _revertDelegate(data);
    }

    /// @notice Purchase a deity pass (perma whale pass with bundled perks).
    /// @param buyer Player address to receive pass (address(0) = msg.sender).
    /// @param quantity Number of passes to purchase.
    function purchaseDeityPass(address buyer, uint256 quantity) external payable {
        if (buyer == address(0)) {
            buyer = msg.sender;
        } else if (buyer != msg.sender) {
            _requireApproved(buyer);
        }
        _purchaseDeityPassFor(buyer, quantity);
    }

    /// @notice Refund deity pass purchases if level 1 has not started after 24 months.
    /// @param buyer Buyer receiving the refund (address(0) = msg.sender).
    function refundDeityPass(address buyer) external {
        if (buyer == address(0)) {
            buyer = msg.sender;
        } else if (buyer != msg.sender) {
            _requireApproved(buyer);
        }
        if (levelStartTime != LEVEL_START_SENTINEL) revert E();
        uint48 day = _currentDayIndex();
        if (day <= DEITY_PASS_REFUND_DAYS) revert E();

        uint256 refundAmount = deityPassRefundable[buyer];
        if (refundAmount == 0) revert E();
        if (refundAmount % DEITY_PASS_PRICE != 0) revert E();

        uint256 refundQty = refundAmount / DEITY_PASS_PRICE;
        uint16 passCount = deityPassCount[buyer];
        if (refundQty > passCount) revert E();
        uint16 refundQty16 = uint16(refundQty);
        deityPassCount[buyer] = passCount - refundQty16;

        trophyMinter.burnDeityTrophies(buyer, refundQty);

        deityPassRefundable[buyer] = 0;

        uint256 remaining = refundAmount;
        uint256 futurePool = futurePrizePool;
        if (futurePool >= remaining) {
            futurePrizePool = futurePool - remaining;
            remaining = 0;
        } else {
            futurePrizePool = 0;
            remaining -= futurePool;
            uint256 nextPool = nextPrizePool;
            if (nextPool < remaining) revert E();
            nextPrizePool = nextPool - remaining;
        }

        emit DeityPassRefunded(buyer, refundAmount, refundQty);
        _payoutWithStethFallback(buyer, refundAmount);
    }

    function _purchaseDeityPassFor(address buyer, uint256 quantity) private {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_WHALE_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameWhaleModule.purchaseDeityPass.selector,
                    buyer,
                    quantity
                )
            );
        if (!ok) _revertDelegate(data);
    }

    /// @notice Redeem giftable 10-level whale bundle credits (no lootbox).
    /// @param player Player address to redeem for (address(0) = msg.sender).
    /// @param quantity Number of passes to redeem.
    function redeemWhaleBundle10Pass(
        address player,
        uint256 quantity
    ) external {
        if (player == address(0)) {
            player = msg.sender;
        } else if (player != msg.sender) {
            _requireApproved(player);
        }
        _redeemWhaleBundle10PassFor(player, quantity);
    }

    function _redeemWhaleBundle10PassFor(
        address player,
        uint256 quantity
    ) private {
        if (quantity == 0 || quantity > type(uint16).max) revert E();
        uint16 qty = uint16(quantity);
        uint16 balance = whaleBundle10PassCredits[player];
        if (balance < qty) revert E();
        whaleBundle10PassCredits[player] = balance - qty;

        (bool ok, bytes memory data) = ContractAddresses
            .GAME_WHALE_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameWhaleModule.redeemWhaleBundle10Pass.selector,
                    player,
                    quantity
                )
            );
        if (!ok) _revertDelegate(data);
    }

    /// @notice Transfer giftable 10-level whale bundle credits to another player.
    /// @param from Pass owner (address(0) = msg.sender).
    /// @param to Recipient address.
    /// @param quantity Number of passes to transfer.
    function transferWhaleBundle10Pass(
        address from,
        address to,
        uint256 quantity
    ) external {
        if (to == address(0)) revert E();
        if (from == address(0)) {
            from = msg.sender;
        } else if (from != msg.sender) {
            _requireApproved(from);
        }
        if (quantity == 0 || quantity > type(uint16).max) revert E();

        uint16 qty = uint16(quantity);
        uint16 balance = whaleBundle10PassCredits[from];
        if (balance < qty) revert E();

        whaleBundle10PassCredits[from] = balance - qty;
        whaleBundle10PassCredits[to] += qty;
    }

    /// @notice Activate a lazy pass token (called by the lazy pass contract).
    /// @dev Access: LAZY_PASS contract only.
    ///      Assigns tickets for the 10-level window containing the current effective level.
    /// @param player Player receiving lazy pass tickets.
    /// @return passLevel Start level of the 10-level window.
    function activateLazyPass(address player) external returns (uint24 passLevel) {
        if (msg.sender != ContractAddresses.LAZY_PASS) revert E();
        if (player == address(0)) revert E();

        passLevel = _lazyPassStartLevel(level);
        _activateLazyPassFor(player, passLevel);
        emit LazyPassActivated(player, passLevel);
    }

    /// @notice Activate a lazy pass for a specific level window.
    /// @dev Access: LAZY_PASS contract only.
    ///      Assigns tickets for the 10-level window starting at passLevel.
    /// @param player Player receiving lazy pass tickets.
    /// @param passLevel Start level of the 10-level window.
    function activateLazyPassAtLevel(address player, uint24 passLevel) external {
        if (msg.sender != ContractAddresses.LAZY_PASS) revert E();
        if (player == address(0)) revert E();
        if (passLevel == 0) revert E();
        _activateLazyPassFor(player, passLevel);
        emit LazyPassActivated(player, passLevel);
    }


    /// @notice Open a loot box once RNG for its lootbox index is available.
    /// @param player Player address that owns the loot box (address(0) = msg.sender).
    /// @param lootboxIndex Lootbox RNG index assigned at purchase time.
    function openLootBox(address player, uint48 lootboxIndex) external {
        if (player == address(0)) {
            player = msg.sender;
        } else if (player != msg.sender) {
            _requireApproved(player);
        }
        _openLootBoxFor(player, lootboxIndex);
    }

    /// @notice Open a BURNIE loot box once RNG for its lootbox index is available.
    /// @param player Player address that owns the loot box (address(0) = msg.sender).
    /// @param lootboxIndex Lootbox RNG index assigned at purchase time.
    function openBurnieLootBox(address player, uint48 lootboxIndex) external {
        if (player == address(0)) {
            player = msg.sender;
        } else if (player != msg.sender) {
            _requireApproved(player);
        }
        _openBurnieLootBoxFor(player, lootboxIndex);
    }

    function _openLootBoxFor(address player, uint48 lootboxIndex) private {
        lootbox.openLootBox(player, lootboxIndex);
    }

    function _openBurnieLootBoxFor(address player, uint48 lootboxIndex) private {
        lootbox.openBurnieLootBox(player, lootboxIndex);
    }

    /// @notice Consume coinflip boon for next coinflip stake bonus.
    /// @dev Access: COIN contract only.
    function consumeCoinflipBoon(address player) external returns (uint16 boostBps) {
        if (msg.sender != ContractAddresses.COIN) revert E();
        return lootbox.consumeCoinflipBoon(player);
    }

    /// @notice Consume decimator boon for burn bonus.
    /// @dev Access: COIN contract only.
    function consumeDecimatorBoon(address player) external returns (uint16 boostBps) {
        if (msg.sender != ContractAddresses.COIN) revert E();
        return lootbox.consumeDecimatorBoost(player);
    }

    /// @notice Consume ticket boost for purchase bonus.
    /// @dev Access: GAMEPIECES contract only.
    function consumeTicketBoost(address player) external returns (uint16 boostBps) {
        if (msg.sender != ContractAddresses.GAMEPIECES) revert E();
        return lootbox.consumeTicketBoost(player);
    }

    /// @notice Consume gamepiece boost for purchase bonus.
    /// @dev Access: GAMEPIECES contract only.
    function consumeGamepieceBoost(address player) external returns (uint16 boostBps) {
        if (msg.sender != ContractAddresses.GAMEPIECES) revert E();
        return lootbox.consumeGamepieceBoost(player);
    }

    function _lazyPassStartLevel(uint24 effectiveLevel) private pure returns (uint24) {
        if (effectiveLevel == 0) return 1;
        uint24 offset = uint24((effectiveLevel - 1) % 10);
        return effectiveLevel - offset;
    }

    function _activateLazyPassFor(address player, uint24 passLevel) private {
        uint256 prevData = mintPacked_[player];

        uint24 frozenUntilLevel = uint24(
            (prevData >> ETH_FROZEN_UNTIL_LEVEL_SHIFT) & MINT_MASK_24
        );

        uint24 lastLevel = uint24((prevData >> ETH_LAST_LEVEL_SHIFT) & MINT_MASK_24);
        uint24 levelCount = uint24((prevData >> ETH_LEVEL_COUNT_SHIFT) & MINT_MASK_24);
        uint24 streak = uint24((prevData >> ETH_LEVEL_STREAK_SHIFT) & MINT_MASK_24);

        bool alreadyMintedAtPassLevel = lastLevel == passLevel;
        uint24 levelsToAdd = alreadyMintedAtPassLevel ? 9 : 10;

        uint24 newLevelCount = levelCount + levelsToAdd;
        uint24 newStreak = streak + levelsToAdd;
        uint24 newFrozenLevel = passLevel + 9;
        if (frozenUntilLevel > newFrozenLevel) {
            newFrozenLevel = frozenUntilLevel;
        }

        uint8 currentBundleType = uint8(
            (prevData >> ETH_WHALE_BUNDLE_TYPE_SHIFT) & 3
        );
        uint24 lastLevelTarget = newFrozenLevel > lastLevel
            ? newFrozenLevel
            : lastLevel;

        uint256 data = prevData;
        data = _setPacked(data, ETH_LEVEL_COUNT_SHIFT, MINT_MASK_24, newLevelCount);
        data = _setPacked(data, ETH_LEVEL_STREAK_SHIFT, MINT_MASK_24, newStreak);
        data = _setPacked(data, ETH_FROZEN_UNTIL_LEVEL_SHIFT, MINT_MASK_24, newFrozenLevel);
        if (1 >= currentBundleType) {
            data = _setPacked(data, ETH_WHALE_BUNDLE_TYPE_SHIFT, 3, 1);
        }
        data = _setPacked(data, ETH_LAST_LEVEL_SHIFT, MINT_MASK_24, lastLevelTarget);

        uint32 day = _currentMintDay();
        data = _setMintDay(data, day, ETH_DAY_SHIFT, MINT_MASK_32);

        mintPacked_[player] = data;

        _queueTicketRange(player, passLevel, 10, 4);
    }

    function _currentMintDay() private view returns (uint32) {
        uint48 day = dailyIdx;
        if (day == 0) {
            day = _currentDayIndex();
        }
        return uint32(day);
    }

    function _setMintDay(
        uint256 data,
        uint32 day,
        uint256 dayShift,
        uint256 dayMask
    ) private pure returns (uint256) {
        uint32 prevDay = uint32((data >> dayShift) & dayMask);
        if (prevDay == day) {
            return data;
        }
        uint256 clearedDay = data & ~(dayMask << dayShift);
        return clearedDay | (uint256(day) << dayShift);
    }

    function _setPacked(
        uint256 data,
        uint256 shift,
        uint256 mask,
        uint256 value
    ) private pure returns (uint256) {
        return (data & ~(mask << shift)) | ((value & mask) << shift);
    }

    /// @dev Process mint payment and return amount contributed to prize pool.
    ///      Handles three payment modes with strict validation:
    ///
    ///      DirectEth: msg.value must exactly match amount
    ///      Claimable: msg.value must be 0, deduct from claimableWinnings
    ///      Combined: ETH first (any amount ≤ cost), then claimable for rest
    ///
    ///      SECURITY: Leaves 1 wei sentinel in claimable to prevent zeroing.
    ///      INVARIANT: claimablePool is decremented by claimableUsed.
    ///
    /// @param player Player whose claimable balance to check/deduct.
    /// @param amount Total cost in wei to cover.
    /// @param payKind Payment method enum.
    /// @return prizeContribution Amount contributing to next/future prize pools.
    /// @return newClaimableBalance Player's claimable balance after deduction (0 if DirectEth).
    function _processMintPayment(
        address player,
        uint256 amount,
        MintPaymentKind payKind
    ) private returns (uint256 prizeContribution, uint256 newClaimableBalance) {
        uint256 claimableUsed;
        if (payKind == MintPaymentKind.DirectEth) {
            // Direct ETH: exact match required
            if (msg.value != amount) revert E();
            prizeContribution = amount;
            // newClaimableBalance stays 0 (caller checks claimableUsed first)
        } else if (payKind == MintPaymentKind.Claimable) {
            // Pure claimable: no ETH allowed, must have sufficient balance
            if (msg.value != 0) revert E();
            uint256 claimable = claimableWinnings[player];
            // Require claimable > amount to preserve 1 wei sentinel (prevents cold→warm SSTORE)
            if (claimable <= amount) revert E();
            unchecked {
                newClaimableBalance = claimable - amount;
            }
            claimableWinnings[player] = newClaimableBalance;
            claimableUsed = amount;
            prizeContribution = amount;
        } else if (payKind == MintPaymentKind.Combined) {
            // Combined: ETH first, then fill remainder from claimable
            if (msg.value > amount) revert E();
            uint256 remaining = amount - msg.value;
            if (remaining != 0) {
                uint256 claimable = claimableWinnings[player];
                if (claimable > 1) {
                    uint256 available = claimable - 1; // Preserve 1 wei sentinel
                    claimableUsed = remaining < available
                        ? remaining
                        : available;
                    if (claimableUsed != 0) {
                        unchecked {
                            newClaimableBalance = claimable - claimableUsed;
                        }
                        claimableWinnings[player] = newClaimableBalance;
                        remaining -= claimableUsed;
                    }
                }
            }
            if (remaining != 0) revert E(); // Must fully cover cost
            prizeContribution = msg.value + claimableUsed;
        } else {
            revert E();
        }
        // Update claimablePool accounting
        if (claimableUsed != 0) {
            claimablePool -= claimableUsed;
        }
    }

    /*+======================================================================+
      |                       TICKET QUEUEING                                |
      +======================================================================+
      |  Tickets are queued for batch processing rather than minted immediately.|
      |  This prevents gas exhaustion from large purchases.                  |
      +======================================================================+*/

    /// @notice Queue tickets after gamepiece-side processing.
    /// @dev Access: gamepieces contract only.
    ///      All tickets queue into ticketQueue[level] and are processed during advanceGame.
    /// @param buyer Player to credit tickets to.
    /// @param quantityScaled Number of tickets to queue (2 decimals, scaled by 100).
    /// @param lvlOffset Level offset: 0 for current level, >0 for future level.
    ///                  During burn, lvlOffset=0 queues for next level instead.
    function enqueueTickets(
        address buyer,
        uint32 quantityScaled,
        uint24 lvlOffset
    ) external {
        if (msg.sender != ContractAddresses.GAMEPIECES) revert E();
        if (quantityScaled == 0) return;

        // Calculate target level
        uint24 targetLevel = level + lvlOffset;

        // Queue tickets for target level (unified system)
        _queueTicketsScaled(buyer, targetLevel, quantityScaled);
    }

    /*+======================================================================+
      |                       gamepiece BURNING (DEGENERUS)                        |
      +======================================================================+
      |  Players burn gamepieces to earn jackpot tickets and potentially trigger   |
      |  trait extermination (marks a winner, does not end the level).        |
      |                                                                      |
      |  Each burned token:                                                  |
      |  • Adds 4 tickets (one per trait) to the trait burn ticket pools     |
      |  • Decrements each trait's remaining count                           |
      |  • May trigger extermination if a trait count hits 0 (or 1 on L%10=7)|
      |  • Awards bonus BURNIE for matching colors or carrying prev trait    |
      |                                                                      |
      |  SECURITY:                                                           |
      |  • RNG must not be locked (prevents manipulation during VRF window)  |
      |  • Can only burn in State 3 (DEGENERUS)                              |
      |  • Max 75 tokens per call (gas limit protection)                     |
      +======================================================================+*/

    /// @notice Burn gamepieces for jackpot tickets, potentially triggering extermination.
    /// @dev Access: any player during State 3 (DEGENERUS) when RNG is not locked.
    ///
    ///      For each token burned:
    ///      1. Extract 4 traits from token ID (deterministic hash)
    ///      2. Add ticket to each trait's burn pool for this level
    ///      3. Decrement trait remaining counts
    ///      4. Check for extermination (trait count hits threshold)
    ///      5. Track daily burn counts for jackpot calculations
    ///      6. Award bonus BURNIE for matching colors / carrying prev trait
    ///
    ///      BONUSES:
    ///      • +4.9x BURNIE if all 4 traits share the same color category
    ///      • +0.4x BURNIE if token has previous exterminated trait (or inverse on L90)
    ///      • 2x ticket count on L%10=2 (double count step)
    ///
    ///      EXTERMINATION:
    ///      • Normally triggered when trait count = 0
    ///      • On L%10=7, triggered when trait count = 1 (early end)
    ///      • Extermination triggers once per level; later burns continue
    ///
    /// @param player Player address that owns the tokens (address(0) = msg.sender).
    /// @param tokenIds Array of token IDs to burn (1-75 tokens).
    function burnTokens(address player, uint256[] calldata tokenIds) external {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_DECIMATOR_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameDecimatorModule.burnTokens.selector,
                    player,
                    tokenIds
                )
            );
        if (!ok) _revertDelegate(data);
    }

    /*+================================================================================================================+
      |                    DELEGATE MODULE HELPERS                                                                     |
      +================================================================================================================+
      |  Internal functions that delegatecall into specialized modules.                                                |
      |  All modules MUST inherit DegenerusGameStorage for slot alignment.                                             |
      |                                                                                                                |
      |  Modules:                                                                                                      |
      |  • ContractAddresses.GAME_DECIMATOR_MODULE - Decimator claim credits and lootbox payouts                       |
      |  • ContractAddresses.GAME_ENDGAME_MODULE  - Endgame settlement (payouts, wipes, ContractAddresses.JACKPOTS)    |
      |  • ContractAddresses.GAME_MINT_MODULE     - Mint data recording, airdrop multipliers                           |
      |  • ContractAddresses.GAME_WHALE_MODULE    - Whale bundle purchases                                              |
      |  • ContractAddresses.GAME_JACKPOT_MODULE  - Jackpot calculations and payouts                                   |
      |                                                                                                                |
      |  SECURITY: delegatecall executes module code in this contract's                                                |
      |  context, with access to all storage. Modules are constant.                                                    |
      +================================================================================================================+*/

    /// @dev Bubble up revert reason from delegatecall failure.
    ///      Uses assembly to preserve original error data.
    /// @param reason The error bytes from failed delegatecall.
    function _revertDelegate(bytes memory reason) private pure {
        if (reason.length == 0) revert E();
        assembly ("memory-safe") {
            revert(add(32, reason), mload(reason))
        }
    }

    /// @dev Record mint data via mint module delegatecall.
    ///      Updates player's mint history and calculates BURNIE reward.
    /// @param player Player address being credited.
    /// @param lvl Level at which mint occurred.
    /// @param mintUnits Number of mint units purchased.
    /// @return coinReward BURNIE tokens to credit to player.
    function _recordMintDataModule(
        address player,
        uint24 lvl,
        uint32 mintUnits
    ) private returns (uint256 coinReward) {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_MINT_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameMintModule.recordMintData.selector,
                    player,
                    lvl,
                    mintUnits
                )
            );
        if (!ok) _revertDelegate(data);
        if (data.length == 0) revert E();
        return abi.decode(data, (uint256));
    }

    /*+========================================================================================+
      |                    DECIMATOR JACKPOT CREDITS                                           |
      +========================================================================================+
      |  Credits from decimator/BAF jackpot wins flow through these                            |
      |  functions. Called by the ContractAddresses.JACKPOTS contract.                         |
      +========================================================================================+*/

    /// @notice Batch variant: credit multiple decimator claims (ETH-only during gameover).
    /// @dev Access: ContractAddresses.JACKPOTS contract only.
    ///      Gas-optimized for multiple credits in single transaction.
    ///      Each claim splits 50/50 by default; during GAMEOVER credits 100% ETH.
    ///      Uses VRF randomness from jackpot resolution for lootbox derivation.
    /// @param accounts Array of player addresses to credit.
    /// @param amounts Array of corresponding wei amounts (total before split).
    /// @param rngWord VRF random word from jackpot resolution.
    function creditDecJackpotClaimBatch(
        address[] calldata accounts,
        uint256[] calldata amounts,
        uint256 rngWord
    ) external {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_DECIMATOR_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameDecimatorModule
                        .creditDecJackpotClaimBatch
                        .selector,
                    accounts,
                    amounts,
                    rngWord
                )
            );
        if (!ok) _revertDelegate(data);
    }

    /*+========================================================================================+
      |                    CLAIMING WINNINGS (ETH)                                             |
      +========================================================================================+
      |  Players claim accumulated winnings from ContractAddresses.JACKPOTS, affiliates,       |
      |  and endgame payouts through the claimWinnings() function.                              |
      |                                                                                        |
      |  SECURITY:                                                                             |
      |  • Uses CEI pattern (Checks-Effects-Interactions)                                      |
      |  • Leaves 1 wei sentinel for gas optimization on future credits                        |
      |  • Falls back to stETH if ETH balance insufficient                                     |
      |  • claimablePool is decremented before external call                                   |
      +========================================================================================+*/

    /// @notice Emitted when claimable ETH winnings are paid out.
    /// @param player Player whose balance is claimed.
    /// @param caller Address that initiated the claim.
    /// @param amount ETH amount paid (excludes 1 wei sentinel).
    event WinningsClaimed(address indexed player, address indexed caller, uint256 amount);

    /// @notice Emitted when whale pass rewards are claimed.
    /// @param player Player receiving tickets.
    /// @param caller Address that initiated the claim.
    /// @param halfPasses Half-pass count used for ticket awards.
    /// @param startLevel Level where ticket awards begin.
    event WhalePassClaimed(
        address indexed player,
        address indexed caller,
        uint256 halfPasses,
        uint24 startLevel
    );

    /// @notice Emitted when a lazy pass is activated.
    /// @param player Player receiving the lazy pass tickets.
    /// @param passLevel Start level for the 10-level window.
    event LazyPassActivated(address indexed player, uint24 passLevel);

    /// @notice Emitted when a deity pass refund is paid.
    /// @param buyer Buyer receiving the refund.
    /// @param amount ETH amount refunded.
    /// @param quantity Number of passes refunded.
    event DeityPassRefunded(
        address indexed buyer,
        uint256 amount,
        uint256 quantity
    );

    /// @notice Emitted when an affiliate claims DGNRS for the previous level.
    /// @param affiliate Affiliate receiving DGNRS.
    /// @param level Level the claim is for (previous level).
    /// @param caller Address that initiated the claim.
    /// @param score Affiliate score used for the claim.
    /// @param amount DGNRS amount paid.
    event AffiliateDgnrsClaimed(
        address indexed affiliate,
        uint24 indexed level,
        address indexed caller,
        uint256 score,
        uint256 amount
    );

    /// @notice Claim accrued ETH winnings.
    /// @dev Aggregates all winnings: affiliates, ContractAddresses.JACKPOTS, endgame payouts.
    ///      Uses pull pattern for security (CEI: check balance, update state, then transfer).
    ///
    ///      GAS OPTIMIZATION: Leaves 1 wei sentinel so subsequent credits remain
    ///      non-zero → cheaper SSTORE (cold→warm vs cold→zero→warm).
    ///
    ///      SECURITY: Reverts if balance ≤ 1 wei (nothing to claim).
    /// @param player Player address to claim for (address(0) = msg.sender).
    function claimWinnings(address player) external {
        if (player == address(0)) {
            player = msg.sender;
        } else if (player != msg.sender) {
            _requireApproved(player);
        }
        _claimWinnings(player);
    }

    /// @notice Claim accrued ETH winnings with stETH-first payout.
    /// @dev Restricted to self-claims by the vault or DGNRS contract.
    function claimWinningsStethFirst() external {
        address player = msg.sender;
        if (player != ContractAddresses.VAULT && player != ContractAddresses.DGNRS) revert E();
        _claimWinningsStethFirst(player);
    }

    function _claimWinnings(address player) private {
        uint256 amount = claimableWinnings[player];
        if (amount <= 1) revert E();
        uint256 payout;
        unchecked {
            claimableWinnings[player] = 1; // Leave sentinel
            payout = amount - 1;
        }
        claimablePool -= payout; // CEI: update state before external call
        emit WinningsClaimed(player, msg.sender, payout);
        _payoutWithStethFallback(player, payout);
    }

    function _claimWinningsStethFirst(address player) private {
        uint256 amount = claimableWinnings[player];
        if (amount <= 1) revert E();
        uint256 payout;
        unchecked {
            claimableWinnings[player] = 1; // Leave sentinel
            payout = amount - 1;
        }
        claimablePool -= payout; // CEI: update state before external call
        emit WinningsClaimed(player, msg.sender, payout);
        _payoutWithEthFallback(player, payout);
    }

    /// @notice Claim DGNRS affiliate rewards for the previous level.
    /// @dev Requires a minimum affiliate score and allows one claim per level.
    ///      Uses the per-level prize pool snapshot (lastPrizePool) as an approximate
    ///      denominator and pays a proportional share of 5% of the remaining
    ///      affiliate DGNRS pool.
    /// @param player Affiliate address to claim for (address(0) = msg.sender).
    function claimAffiliateDgnrs(address player) external {
        if (player == address(0)) {
            player = msg.sender;
        } else if (player != msg.sender) {
            _requireApproved(player);
        }

        uint24 currLevel = level;
        if (currLevel <= 1) revert E();
        uint24 prevLevel = currLevel - 1;

        if (affiliateDgnrsClaimedBy[prevLevel][player]) revert E();

        uint256 score = affiliate.affiliateScore(prevLevel, player);
        bool hasDeityPass = deityPassCount[player] != 0;
        if (!hasDeityPass && score < AFFILIATE_DGNRS_MIN_SCORE) revert E();

        uint256 denominator = affiliateDgnrsPrizePool[prevLevel];
        if (denominator == 0) {
            denominator = lastPrizePool;
        }
        if (denominator == 0) revert E();

        uint256 poolBalance = dgnrs.poolBalance(IDegenerusStonk.Pool.Affiliate);
        uint256 levelShare = (poolBalance * AFFILIATE_DGNRS_LEVEL_BPS) / 10_000;
        if (levelShare == 0) revert E();
        uint256 reward = (levelShare * score) / denominator;
        if (reward == 0) revert E();

        uint256 paid = dgnrs.transferFromPool(
            IDegenerusStonk.Pool.Affiliate,
            player,
            reward
        );
        if (paid == 0) revert E();

        if (hasDeityPass && score != 0) {
            uint256 burnieBase = (score * PRICE_COIN_UNIT) / 1 ether;
            uint256 bonus = (burnieBase * AFFILIATE_DGNRS_DEITY_BONUS_BPS) / 10_000;
            if (bonus != 0) {
                coin.creditFlip(player, bonus);
            }
        }

        affiliateDgnrsClaimedBy[prevLevel][player] = true;
        emit AffiliateDgnrsClaimed(player, prevLevel, msg.sender, score, paid);
    }

    /*+======================================================================+
      |                    AUTO-REBUY TOGGLE                                |
      +======================================================================+*/

    /// @notice Emitted when a player toggles auto-rebuy on or off.
    event AutoRebuyToggled(address indexed player, bool enabled);

    /// @notice Emitted when a player sets the auto-rebuy keep multiple.
    event AutoRebuyKeepMultipleSet(
        address indexed player,
        uint256 keepMultiple
    );

    /// @notice Emitted when auto-rebuy converts winnings to tickets.
    event AutoRebuyProcessed(
        address indexed player,
        uint24 targetLevel,
        uint32 ticketsAwarded,
        uint256 ethSpent,
        uint256 remainder
    );

    /// @notice Emitted when afKing mode is toggled.
    event AfKingModeToggled(address indexed player, bool enabled);

    /// @notice Enable or disable auto-rebuy for claimable winnings.
    /// @dev When enabled, the remainder (after reserving full keep-multiples) is
    ///      converted to tickets for one of the next 5 levels during jackpot award flow.
    ///      ETH goes to futurePrizePool, tickets to ticketsOwed[level][player].
    ///
    ///      BONUS: Applies fixed ticket bonus for auto-rebuy:
    ///      - 30% default (13000 bps)
    ///      - 45% when afKing mode is active (14500 bps)
    ///
    /// @param player Player address to configure (address(0) = msg.sender).
    /// @param enabled True to enable auto-rebuy, false to disable.
    function setAutoRebuy(address player, bool enabled) external {
        if (player == address(0)) {
            player = msg.sender;
        } else if (player != msg.sender) {
            _requireApproved(player);
        }
        _setAutoRebuy(player, enabled);
    }

    /// @notice Set the auto-rebuy keep multiple (amount reserved for manual claim).
    /// @dev Complete multiples remain claimable; remainder is eligible for auto-rebuy.
    /// @param player Player address to configure (address(0) = msg.sender).
    /// @param keepMultiple Amount in wei; 0 means no reservation (rebuy all).
    function setAutoRebuyKeepMultiple(
        address player,
        uint256 keepMultiple
    ) external {
        if (player == address(0)) {
            player = msg.sender;
        } else if (player != msg.sender) {
            _requireApproved(player);
        }
        _setAutoRebuyKeepMultiple(player, keepMultiple);
    }

    function _setAutoRebuy(address player, bool enabled) private {
        if (rngLockedFlag) revert RngLocked();
        autoRebuyEnabled[player] = enabled;
        emit AutoRebuyToggled(player, enabled);
        if (!enabled) {
            _deactivateAfKing(player);
        }
    }

    function _setAutoRebuyKeepMultiple(
        address player,
        uint256 keepMultiple
    ) private {
        if (rngLockedFlag) revert RngLocked();
        autoRebuyKeepMultiple[player] = keepMultiple;
        emit AutoRebuyKeepMultipleSet(player, keepMultiple);
        if (keepMultiple != 0 && keepMultiple < AFKING_KEEP_MIN_ETH) {
            _deactivateAfKing(player);
        }
    }

    /// @notice Check if auto-rebuy is enabled for a player.
    /// @param player Player address to check.
    /// @return enabled True if auto-rebuy is enabled for this player.
    function autoRebuyEnabledFor(address player) external view returns (bool enabled) {
        return autoRebuyEnabled[player];
    }

    /// @notice Check the auto-rebuy keep multiple for a player.
    /// @param player Player address to check.
    /// @return keepMultiple Amount reserved as complete multiples (wei).
    function autoRebuyKeepMultipleFor(
        address player
    ) external view returns (uint256 keepMultiple) {
        return autoRebuyKeepMultiple[player];
    }

    /// @notice Enable or disable afKing mode.
    /// @dev Enabling afKing forces auto-rebuy on for ETH and coin and clamps keep-multiples
    ///      to minimums (2 ETH / 20k BURNIE) unless set to 0. Requires a lazy pass.
    /// @param player Player address to configure (address(0) = msg.sender).
    /// @param enabled True to enable afKing mode, false to disable.
    /// @param ethKeepMultiple Desired ETH keep multiple (wei).
    /// @param coinKeepMultiple Desired coin keep multiple (BURNIE, 18 decimals).
    function setAfKingMode(
        address player,
        bool enabled,
        uint256 ethKeepMultiple,
        uint256 coinKeepMultiple
    ) external {
        if (player == address(0)) {
            player = msg.sender;
        } else if (player != msg.sender) {
            _requireApproved(player);
        }
        _setAfKingMode(player, enabled, ethKeepMultiple, coinKeepMultiple);
    }

    function _setAfKingMode(
        address player,
        bool enabled,
        uint256 ethKeepMultiple,
        uint256 coinKeepMultiple
    ) private {
        if (rngLockedFlag) revert RngLocked();
        if (!enabled) {
            _deactivateAfKing(player);
            return;
        }
        if (!_hasAnyLazyPass(player)) revert E();

        uint256 adjustedEthKeep = ethKeepMultiple;
        if (adjustedEthKeep != 0 && adjustedEthKeep < AFKING_KEEP_MIN_ETH) {
            adjustedEthKeep = AFKING_KEEP_MIN_ETH;
        }
        uint256 adjustedCoinKeep = coinKeepMultiple;
        if (adjustedCoinKeep != 0 && adjustedCoinKeep < AFKING_KEEP_MIN_COIN) {
            adjustedCoinKeep = AFKING_KEEP_MIN_COIN;
        }

        if (!autoRebuyEnabled[player]) {
            autoRebuyEnabled[player] = true;
            emit AutoRebuyToggled(player, true);
        }
        if (autoRebuyKeepMultiple[player] != adjustedEthKeep) {
            autoRebuyKeepMultiple[player] = adjustedEthKeep;
            emit AutoRebuyKeepMultipleSet(player, adjustedEthKeep);
        }
        coinflip.setCoinflipAutoRebuy(player, true, adjustedCoinKeep);

        if (!afKingMode[player]) {
            afKingMode[player] = true;
            afKingActivatedLevel[player] = level;
            emit AfKingModeToggled(player, true);
        }
    }

    function _hasAnyLazyPass(address player) private view returns (bool) {
        if (deityPassCount[player] != 0) return true;

        uint24 frozenUntilLevel = uint24(
            (mintPacked_[player] >> ETH_FROZEN_UNTIL_LEVEL_SHIFT) & MINT_MASK_24
        );
        if (frozenUntilLevel > level) return true;

        return lazyPass.inactiveBalanceOf(player) != 0;
    }

    /// @notice Check if afKing mode is active for a player.
    /// @param player Player address to check.
    /// @return active True if afKing mode is active.
    function afKingModeFor(address player) external view returns (bool active) {
        return afKingMode[player];
    }

    /// @notice Deactivate afKing mode for a player (coin-only hook).
    /// @param player Player to deactivate.
    function deactivateAfKingFromCoin(address player) external {
        if (msg.sender != ContractAddresses.COIN) revert E();
        _deactivateAfKing(player);
    }

    function _deactivateAfKing(address player) private {
        if (!afKingMode[player]) return;
        uint24 activationLevel = afKingActivatedLevel[player];
        if (activationLevel != 0) {
            uint256 unlockLevel = uint256(activationLevel) +
                AFKING_LOCK_LEVELS;
            if (uint256(level) < unlockLevel) revert AfKingLockActive();
        }
        afKingMode[player] = false;
        afKingActivatedLevel[player] = 0;
        emit AfKingModeToggled(player, false);
    }

    /*+======================================================================+
      |                    LOOTBOX CLAIMS                                   |
      +======================================================================+*/

    /// @notice Claim deferred whale pass rewards from large lootbox wins.
    /// @dev Unified claim function for all large lootbox rewards (>5 ETH).
    ///      Delegates to endgame module which uses whale pass pricing.
    /// @notice Claim whale pass rewards.
    /// @param player Player address to claim for (address(0) = msg.sender).
    function claimWhalePass(address player) external {
        if (player == address(0)) {
            player = msg.sender;
        } else if (player != msg.sender) {
            _requireApproved(player);
        }
        _claimWhalePassFor(player);
    }

    function _claimWhalePassFor(address player) private {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_ENDGAME_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameEndgameModule.claimWhalePass.selector,
                    player
                )
            );
        if (!ok) _revertDelegate(data);
    }

    /*+===============================================================================================+
      |                    JACKPOT PAYOUT FUNCTIONS                                                   |
      +===============================================================================================+
      |  Functions for distributing jackpot winnings. Most jackpot logic                              |
      |  lives in the ContractAddresses.GAME_JACKPOT_MODULE (via delegatecall).                       |
      |                                                                                               |
      |  Jackpot Types:                                                                               |
      |  • Daily jackpot - Paid each day to burn ticket holders                                       |
      |  • Level jackpot - Paid when prize pool target is met                                         |
      |  • Decimator - Special 100-level milestone jackpot (30% of pool)                              |
      |  • BAF - Big-ass-flip jackpot (10% of pool at L%100=0)                                        |
      |  • (Extermination jackpots removed; exterminator paid on next daily)                          |
      +===============================================================================================+*/

    /// @notice Admin-only update of the orange-king tribute address.
    /// @dev Set to address(0) to disable tribute payments.
    function setTributeAddress(address newAddress) external {
        if (msg.sender != ContractAddresses.ADMIN) revert E();
        address prev = tributeAddress;
        tributeAddress = newAddress;
        emit TributeAddressUpdated(prev, newAddress);
    }
    /*+======================================================================+
      |                    ADMIN: REWARD VAULT & LIQUIDITY                   |
      +======================================================================+
      |  Admin-only functions for managing ETH/stETH liquidity.              |
      |  Used to optimize yield and maintain sufficient ETH for payouts.     |
      |                                                                      |
      |  SECURITY:                                                           |
      |  • Admin-only access (VRF owner contract)                            |
      |  • Cannot touch claimablePool reserve (protected for player claims)  |
      |  • All operations are value-preserving (no fund extraction)          |
      +======================================================================+*/

    /// @notice Admin-only swap: owner sends ETH in and receives game-held stETH.
    /// @dev Used to rebalance when stETH yield should be converted to ETH.
    ///      Admin must send exact ETH amount equal to stETH received.
    ///      SECURITY: Value-neutral swap, ContractAddresses.ADMIN cannot extract funds.
    /// @param recipient Address to receive stETH.
    /// @param amount ETH amount to swap (must match msg.value).
    function adminSwapEthForStEth(
        address recipient,
        uint256 amount
    ) external payable {
        if (msg.sender != ContractAddresses.ADMIN) revert E();
        if (recipient == address(0)) revert E();
        if (amount == 0 || msg.value != amount) revert E();

        uint256 stBal = steth.balanceOf(address(this));
        if (stBal < amount) revert E();
        if (!steth.transfer(recipient, amount)) revert E();
    }

    /// @notice Admin-only stake of game-held ETH into stETH via Lido.
    /// @dev Used to earn yield on excess ETH held by the game.
    ///      SECURITY: Cannot stake ETH reserved for player claims (claimablePool).
    /// @param amount ETH amount to stake.
    function adminStakeEthForStEth(uint256 amount) external {
        if (msg.sender != ContractAddresses.ADMIN) revert E();
        if (amount == 0) revert E();

        uint256 ethBal = address(this).balance;
        if (ethBal < amount) revert E();
        uint256 reserve = claimablePool;
        if (ethBal <= reserve) revert E();
        uint256 stakeable = ethBal - reserve;
        if (amount > stakeable) revert E();

        // stETH return value intentionally ignored: Lido mints 1:1 for ETH, validated by input checks
        try steth.submit{value: amount}(address(0)) returns (uint256) {} catch {
            revert E();
        }
    }

    /*+======================================================================+
      |                    VRF (CHAINLINK) INTEGRATION                       |
      +======================================================================+
      |  Chainlink VRF V2.5 integration for provably fair randomness.        |
      |                                                                      |
      |  LIFECYCLE:                                                          |
      |  1. advanceGame() calls rngAndTimeGate()                             |
      |  2. If no valid RNG word, _requestRng() is called                    |
      |  3. Chainlink calls rawFulfillRandomWords() with random word         |
      |  4. Next advanceGame() uses the fulfilled word                       |
      |  5. After processing, _unlockRng() resets for next cycle             |
      |                                                                      |
      |  SECURITY:                                                           |
      |  • RNG lock prevents state manipulation during VRF window            |
      |  • 18-hour timeout allows recovery from stale requests               |
      |  • 3-day stall enables emergency coordinator rotation                |
      |  • Nudge system allows players to influence (not predict) RNG        |
      +======================================================================+*/

    /// @notice Emergency VRF coordinator rotation after 3-day stall.
    /// @dev Access: ContractAddresses.ADMIN only. Only available when VRF has stalled for 3+ days.
    ///      This is a recovery mechanism for Chainlink outages.
    ///      SECURITY: Requires 3-day gap to prevent abuse.
    /// @param newCoordinator New VRF coordinator address.
    /// @param newSubId New subscription ID.
    /// @param newKeyHash New key hash for the gas lane.
    function updateVrfCoordinatorAndSub(
        address newCoordinator,
        uint256 newSubId,
        bytes32 newKeyHash
    ) external {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_ADVANCE_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameAdvanceModule.updateVrfCoordinatorAndSub.selector,
                    newCoordinator,
                    newSubId,
                    newKeyHash
                )
            );
        if (!ok) _revertDelegate(data);
    }

    /// @notice Pay BURNIE to nudge the next RNG word by +1.
    /// @dev Cost scales +50% per queued nudge and resets after fulfillment.
    ///      Only available while RNG is unlocked (before VRF request is in-flight).
    ///      MECHANISM: Adds 1 to the VRF word for each nudge, changing outcomes.
    ///      SECURITY: Players cannot predict the base word, only influence it.
    /// @param player Player address paying for the nudge (address(0) = msg.sender).
    function reverseFlip(address player) external {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_ADVANCE_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameAdvanceModule.reverseFlip.selector,
                    player
                )
            );
        if (!ok) _revertDelegate(data);
    }

    /// @notice Chainlink VRF callback for random word fulfillment.
    /// @dev Access: VRF coordinator only.
    ///      Applies any queued nudges before storing the word.
    ///      SECURITY: Validates requestId and coordinator address.
    /// @param requestId The request ID to match.
    /// @param randomWords Array containing the random word (length 1).
    function rawFulfillRandomWords(
        uint256 requestId,
        uint256[] calldata randomWords
    ) external {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_ADVANCE_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameAdvanceModule.rawFulfillRandomWords.selector,
                    requestId,
                    randomWords
                )
            );
        if (!ok) _revertDelegate(data);
    }

    /*+======================================================================+
      |                    PAYMENT HELPERS                                   |
      +======================================================================+
      |  Internal functions for ETH/stETH payouts.                           |
      |  Implements fallback logic when one asset is insufficient.           |
      +======================================================================+*/

    function _creditDgnrsCoinflipAndVault(uint256 prizePoolWei) private {
        uint256 priceWei = price;
        if (priceWei == 0) return;
        uint256 coinAmount = (prizePoolWei * PRICE_COIN_UNIT) / (priceWei * 20);
        if (coinAmount == 0) return;
        coin.creditFlip(ContractAddresses.DGNRS, coinAmount);
        coin.vaultEscrow(coinAmount);
    }

    /// @dev Transfer stETH to recipient. Uses DGNRS deposit path to keep reserves in sync.
    function _transferSteth(address to, uint256 amount) private {
        if (amount == 0) return;
        if (to == ContractAddresses.DGNRS) {
            if (!steth.approve(ContractAddresses.DGNRS, amount)) revert E();
            dgnrs.depositSteth(amount);
            return;
        }
        if (!steth.transfer(to, amount)) revert E();
    }

    /// @dev Send ETH first, then stETH for remainder.
    ///      Used for player claim payouts (ETH preferred).
    ///      Includes retry logic if stETH is short but ETH arrives.
    /// @param to Recipient address.
    /// @param amount Total wei to send.
    function _payoutWithStethFallback(address to, uint256 amount) private {
        if (amount == 0) return;

        // Try ETH first (preferred for player claims)
        uint256 ethBal = address(this).balance;
        uint256 ethSend = amount <= ethBal ? amount : ethBal;
        if (ethSend != 0) {
            (bool okEth, ) = payable(to).call{value: ethSend}("");
            if (!okEth) revert E();
        }
        uint256 remaining = amount - ethSend;
        if (remaining == 0) return;

        // Fall back to stETH for remainder
        uint256 stBal = steth.balanceOf(address(this));
        uint256 stSend = remaining <= stBal ? remaining : stBal;
        _transferSteth(to, stSend);

        // Retry ETH for any remaining (handles edge cases)
        uint256 leftover = remaining - stSend;
        if (leftover != 0) {
            // Retry with any refreshed ETH (e.g., if stETH was short but ETH arrived).
            uint256 ethRetry = address(this).balance;
            if (ethRetry < leftover) revert E();
            (bool ok, ) = payable(to).call{value: leftover}("");
            if (!ok) revert E();
        }
    }

    /// @dev Send stETH first, then ETH for remainder.
    ///      Used for vault/DGNRS reserve claims (stETH preferred).
    /// @param to Recipient address.
    /// @param amount Total wei to send.
    function _payoutWithEthFallback(address to, uint256 amount) private {
        if (amount == 0) return;

        uint256 stBal = steth.balanceOf(address(this));
        uint256 stSend = amount <= stBal ? amount : stBal;
        _transferSteth(to, stSend);

        uint256 remaining = amount - stSend;
        if (remaining == 0) return;

        uint256 ethBal = address(this).balance;
        if (ethBal < remaining) revert E();
        (bool ok, ) = payable(to).call{value: remaining}("");
        if (!ok) revert E();
    }

    /*+======================================================================+
      |                   VIEW: GAME STATUS & STATE                          |
      +======================================================================+
      |  Lightweight view functions for UI/frontend consumption. These       |
      |  provide read-only access to game state without gas costs.           |
      +======================================================================+*/

    /// @notice Get the prize pool target for the current 100-level cycle.
    /// @dev Target is reset at level % 100 == 0 based on future pool size.
    /// @return The lastPrizePool value (ETH wei).
    function prizePoolTargetView() external view returns (uint256) {
        return lastPrizePool;
    }

    /// @notice Get the prize pool accumulated for the next level.
    /// @dev Mint fees flow into nextPrizePool until target is met.
    /// @return The nextPrizePool value (ETH wei).
    function nextPrizePoolView() external view returns (uint256) {
        return nextPrizePool;
    }

    /// @notice Get the unified future pool reserve.
    /// @param lvl Unused; retained for interface compatibility.
    /// @return The futurePrizePool value (ETH wei).
    function futurePrizePoolView(uint24 lvl) external view returns (uint256) {
        lvl;
        return futurePrizePool;
    }

    /// @notice Get the aggregate future pool reserve.
    /// @return The futurePrizePool value (ETH wei).
    function futurePrizePoolTotalView() external view returns (uint256) {
        return futurePrizePool;
    }

    /// @notice Get queued future ticket rewards owed for a level.
    /// @param lvl Target level for the queued tickets.
    /// @param player Player address to query.
    /// @return The number of whole ticket rewards owed (fractional remainder resolves at batch time).
    function ticketsOwedView(
        uint24 lvl,
        address player
    ) external view returns (uint32) {
        return ticketsOwed[lvl][player];
    }

    /// @notice Get loot box status for a player/index.
    /// @param player Player address to query.
    /// @param lootboxIndex Lootbox RNG index assigned at purchase time.
    /// @return amount ETH amount recorded for the loot box (wei).
    /// @return presale True if the loot box was purchased during presale mode.
    function lootboxStatus(
        address player,
        uint48 lootboxIndex
    ) external view returns (uint256 amount, bool presale) {
        amount = lootbox.lootboxAmountFor(player, lootboxIndex);
        // TODO: Presale tracking needs to be added to lootbox contract
        presale = false;
    }

    /// @notice Check whether lootbox presale mode is currently active.
    /// @return active True if presale is active.
    function lootboxPresaleActiveFlag() external view returns (bool active) {
        // TODO: Presale tracking needs to be moved to lootbox contract
        return lootboxPresaleActive;
    }

    /// @notice Get the current lootbox RNG index for new purchases.
    function lootboxRngIndexView() external view returns (uint48 index) {
        return lootbox.currentLootboxIndex();
    }

    /// @notice Get the VRF random word for a lootbox RNG index.
    /// @param lootboxIndex Lootbox RNG index to query.
    /// @return word VRF word (0 if not ready).
    function lootboxRngWord(uint48 lootboxIndex) external view returns (uint256 word) {
        return lootbox.lootboxRngWordForIndex(lootboxIndex);
    }

    /// @notice Get the lootbox RNG request threshold (wei).
    function lootboxRngThresholdView() external view returns (uint256 threshold) {
        // TODO: RNG threshold tracking needs to be moved to lootbox contract
        return lootboxRngThreshold;
    }

    /// @notice Get minimum LINK balance required for manual lootbox RNG rolls.
    function lootboxRngMinLinkBalanceView() external view returns (uint256 minBalance) {
        // TODO: RNG min balance tracking needs to be moved to lootbox contract
        return lootboxRngMinLinkBalance;
    }

    /// @notice Get the current prize pool (jackpots are paid from this).
    /// @return The currentPrizePool value (ETH wei).
    function currentPrizePoolView() external view returns (uint256) {
        return currentPrizePool;
    }

    /// @notice Get the unified future pool (reserve for jackpots and carryover).
    /// @return The futurePrizePool value (ETH wei).
    function rewardPoolView() external view returns (uint256) {
        return futurePrizePool;
    }

    /// @notice Get the claimable pool (reserved for player winnings claims).
    /// @return The claimablePool value (ETH wei).
    function claimablePoolView() external view returns (uint256) {
        return claimablePool;
    }

    /// @notice Get the untracked yield pool (excess ETH+stETH available for operations).
    /// @dev Calculated as: (ETH balance + stETH balance) - claimablePool
    /// @return The yieldPool value (ETH wei).
    function yieldPoolView() external view returns (uint256) {
        uint256 totalBalance = address(this).balance +
            steth.balanceOf(address(this));
        uint256 tracked = claimablePool;
        if (totalBalance <= tracked) return 0;
        return totalBalance - tracked;
    }

    /// @notice Get the current mint price in wei.
    /// @dev Price varies by level cycle: 0.05/0.05/0.1/0.25 ETH (no 0.15 tier).
    /// @return Current price in wei.
    function mintPrice() external view returns (uint256) {
        return price;
    }

    /// @notice Get the VRF random word recorded for a specific day.
    /// @dev Days are indexed from deploy time (day 1 = deploy day).
    /// @param day The day index to query.
    /// @return The random word (0 if no word recorded for that day).
    function rngWordForDay(uint48 day) external view returns (uint256) {
        return rngWordByDay[day];
    }

    /// @notice Get the most recently recorded RNG word.
    /// @dev Uses dailyIdx to locate the last completed day.
    function lastRngWord() external view returns (uint256) {
        return rngWordByDay[dailyIdx];
    }

    /// @notice Check if RNG is currently locked (VRF request pending).
    /// @dev When locked, burns and certain operations are blocked.
    /// @return True if RNG lock is active.
    function rngLocked() public view returns (bool) {
        return rngLockedFlag;
    }

    /// @notice Check if VRF has been fulfilled for current request.
    /// @return True if random word is available for use.
    function isRngFulfilled() external view returns (bool) {
        return rngFulfilled;
    }

    /// @dev Calculate current day index from block timestamp.
    ///      Day 1 = deploy day. Days reset at JACKPOT_RESET_TIME (22:57 UTC), not midnight.
    /// @return Current day index since deploy (1-indexed).
    function _currentDayIndex() private view returns (uint48) {
        // Calculate day boundaries with JACKPOT_RESET_TIME offset
        uint48 currentDayBoundary = uint48(
            (block.timestamp - JACKPOT_RESET_TIME) / 1 days
        );
        return currentDayBoundary - ContractAddresses.DEPLOY_DAY_BOUNDARY + 1;
    }

    /// @dev Check if there's a 3-consecutive-day gap in VRF words.
    ///      Used to detect VRF coordinator failures requiring emergency rotation.
    /// @param day The day index to check from.
    /// @return True if day, day-1, and day-2 all have no recorded VRF word.
    function _threeDayRngGap(uint48 day) private view returns (bool) {
        if (rngWordByDay[day] != 0) return false;
        if (day == 0 || rngWordByDay[day - 1] != 0) return false;
        if (day < 2 || rngWordByDay[day - 2] != 0) return false;
        return true;
    }

    /// @notice Check if VRF has stalled for 3 consecutive days.
    /// @dev Enables emergency VRF coordinator rotation via updateVrfCoordinatorAndSub().
    /// @return True if no VRF word has been recorded for the last 3 day slots.
    function rngStalledForThreeDays() external view returns (bool) {
        return _threeDayRngGap(_currentDayIndex());
    }



    /*+======================================================================+
      |                   VIEW: DECIMATOR & PURCHASE INFO                    |
      +======================================================================+
      |  Status views for decimator window and purchase state.               |
      +======================================================================+*/

    /// @notice Check if decimator window is open and accessible.
    /// @dev Window is "on" if flag is set or gameover is imminent, and RNG is not locked.
    /// @return on True if decimator entries are currently allowed.
    /// @return lvl Current game level.
    function decWindow() external view returns (bool on, uint24 lvl) {
        on = (decWindowOpen || _isGameoverImminent()) && !rngLockedFlag;
        lvl = level;
    }

    /// @notice Raw check of decimator window flag (ignores RNG lock).
    /// @return open True if decimator window flag is set or gameover is imminent.
    function decWindowOpenFlag() external view returns (bool open) {
        return decWindowOpen || _isGameoverImminent();
    }

    /// @dev True when gameover would trigger within ~10 days.
    ///      Used to allow decimator burns near liveness timeout.
    function _isGameoverImminent() private view returns (bool) {
        if (gameState == GAME_STATE_GAMEOVER) return false;
        uint48 lst = levelStartTime;
        uint48 day = _currentDayIndex();
        uint48 ts = uint48(block.timestamp);

        if (level == 1 && lst == LEVEL_START_SENTINEL) {
            return day + 10 > DEPLOY_IDLE_TIMEOUT_DAYS;
        }
        if (lst != LEVEL_START_SENTINEL) {
            return uint256(ts) + 10 days > uint256(lst) + 365 days;
        }
        return false;
    }

    /// @notice Comprehensive purchase info for UI consumption.
    /// @dev Bundles level, state, flags, and price into single call.
    ///      NOTE: lvl is incremented in state 3 to show "next level" being played.
    /// @return lvl Current level (or next level if in degenerus state).
    /// @return gameState_ Current game state (0-3, 86 for game over).
    /// @return lastPurchaseDay_ True if prize pool target is met.
    /// @return rngLocked_ True if VRF request is pending.
    /// @return priceWei Current mint price in wei.
    function purchaseInfo()
        external
        view
        returns (
            uint24 lvl,
            uint8 gameState_,
            bool lastPurchaseDay_,
            bool rngLocked_,
            uint256 priceWei
        )
    {
        lvl = level;
        gameState_ = gameState;
        lastPurchaseDay_ =
            (gameState_ == GAME_STATE_PURCHASE) &&
            lastPurchaseDay;
        rngLocked_ = rngLockedFlag;
        priceWei = price;

        if (gameState_ == GAME_STATE_BURN) {
            unchecked {
                ++lvl;
            }
        }
    }

    /// @notice Return last-purchase-day coinflip totals for payout tuning.
    /// @return prevTotal Previous level's lastPurchaseDay coinflip deposits.
    /// @return currentTotal Current level's lastPurchaseDay coinflip deposits.
    function lastPurchaseDayFlipTotals()
        external
        view
        returns (uint256 prevTotal, uint256 currentTotal)
    {
        prevTotal = lastPurchaseDayFlipTotalPrev;
        currentTotal = lastPurchaseDayFlipTotal;
    }



    /*+======================================================================+
      |                   VIEW: PLAYER MINT STATISTICS                       |
      +======================================================================+
      |  Unpack player mint history from the bit-packed mintPacked_ storage. |
      |  See MINT PACKED BIT LAYOUT above for field positions.               |
      +======================================================================+*/

    /// @notice Get the last level where player minted with ETH.
    /// @param player The player address to query.
    /// @return The level number (0 if never minted).
    function ethMintLastLevel(address player) external view returns (uint24) {
        if (deityPassCount[player] != 0) {
            return level;
        }
        return
            uint24(
                (mintPacked_[player] >> ETH_LAST_LEVEL_SHIFT) & MINT_MASK_24
            );
    }

    /// @notice Get total count of levels where player minted with ETH.
    /// @param player The player address to query.
    /// @return Number of distinct levels with ETH mints.
    function ethMintLevelCount(address player) external view returns (uint24) {
        if (deityPassCount[player] != 0) {
            return level;
        }
        return
            uint24(
                (mintPacked_[player] >> ETH_LEVEL_COUNT_SHIFT) & MINT_MASK_24
            );
    }

    /// @notice Get player's current consecutive ETH mint streak.
    /// @param player The player address to query.
    /// @return Number of consecutive levels with ETH mints.
    function ethMintStreakCount(address player) external view returns (uint24) {
        if (deityPassCount[player] != 0) {
            return level;
        }
        return
            uint24(
                (mintPacked_[player] >> ETH_LEVEL_STREAK_SHIFT) & MINT_MASK_24
            );
    }

    /// @notice Get combined mint statistics for a player.
    /// @dev Batches multiple stats into single call for gas efficiency.
    /// @param player The player address to query.
    /// @return lvl Current game level.
    /// @return levelCount Total levels with ETH mints.
    /// @return streak Consecutive level mint streak.
    function ethMintStats(
        address player
    ) external view returns (uint24 lvl, uint24 levelCount, uint24 streak) {
        if (deityPassCount[player] != 0) {
            uint24 currLevel = level;
            return (currLevel, currLevel, currLevel);
        }
        uint256 packed = mintPacked_[player];
        lvl = level;
        levelCount = uint24((packed >> ETH_LEVEL_COUNT_SHIFT) & MINT_MASK_24);
        streak = uint24((packed >> ETH_LEVEL_STREAK_SHIFT) & MINT_MASK_24);
    }



    /*+======================================================================+
      |                  VIEW: ACTIVITY SCORE CALCULATION                    |
      +======================================================================+
      |  Player activity score multiplier determines airdrop rewards.        |
      |                                                                      |
      |  Activity Score Components (player engagement/loyalty metrics):      |
      |  • Mint streak: +1% per consecutive level minted (cap 50%)           |
      |  • Mint count: +25% for 100% participation, scaled proportionally    |
      |  • Quest streak: +1% per consecutive quest (cap 100%)                |
      |  • Affiliate points: +1% per affiliate point (cap 50%)               |
      |  • Whale pass bonus (active only while frozen):                      |
      |    - 10-level bundle: +10%                                           |
      |    - 100-level bundle: +40%                                          |
      |  • Deity pass bonus: +80% (always active)                            |
      |                                                                      |
      |  Additional Bonus:                                                   |
      |  • Trophy bonus: +10% per trophy (cap 50%)                           |
      +======================================================================+*/

    /// @notice Calculate player's activity score multiplier in basis points.
    /// @dev 10000 bps = 1.0x multiplier. Max theoretical 355% (35500 bps).
    ///      Activity Score: 50% (streak) + 25% (count) + 100% (quest) + 50% (affiliate) + 40% (whale) = 265% max
    ///      Deity pass adds +80% in place of whale bundle bonus (305% max base).
    ///      Trophy bonus: 50% max
    ///      Total: 305% + 50% = 355% theoretical max (realistic ~220-300%).
    /// @param player The player address to calculate for.
    /// @return multiplierBps Total multiplier in basis points.
    function playerActivityScore(
        address player
    ) public view returns (uint256 multiplierBps) {
        if (player == address(0)) return 10000;

        bool hasDeityPass = deityPassCount[player] != 0;
        uint256 packed = mintPacked_[player];
        uint24 levelCount = uint24(
            (packed >> ETH_LEVEL_COUNT_SHIFT) & MINT_MASK_24
        );
        uint24 streak = uint24(
            (packed >> ETH_LEVEL_STREAK_SHIFT) & MINT_MASK_24
        );
        uint24 currLevel = level;

        uint256 bonusBps;

        unchecked {
            if (hasDeityPass) {
                bonusBps = 50 * 100;
                bonusBps += 25 * 100;
            } else {
                // Mint streak: 1% per consecutive level minted, max 50%
                uint256 streakPoints = streak > 50 ? 50 : uint256(streak);
                bonusBps = streakPoints * 100;
                // Mint count bonus: 1% each
                bonusBps += _mintCountBonusPoints(levelCount, currLevel) * 100;
            }

            // Quest streak: 1% per quest streak, max 100%

            (uint32 questStreakRaw, , , ) = questView.playerQuestStates(player);
            uint256 questStreak = questStreakRaw > 100
                ? 100
                : uint256(questStreakRaw);
            bonusBps += questStreak * 100;

            // Affiliate bonus: only if currLevel >= 1 and affiliate is set

            bonusBps +=
                affiliate.affiliateBonusPointsBest(currLevel, player) *
                100;

            // Trophy bonus: +10% per trophy, capped at +50%

            uint256 trophyCount = trophies.balanceOf(player);
            if (trophyCount > 5) trophyCount = 5;
            bonusBps += trophyCount * 1000;

            if (hasDeityPass) {
                bonusBps += DEITY_PASS_ACTIVITY_BONUS_BPS;
            } else {
                // Whale pass bonus: varies by bundle type (only active while frozen)
                uint24 frozenUntilLevel = uint24((packed >> ETH_FROZEN_UNTIL_LEVEL_SHIFT) & MINT_MASK_24);
                if (frozenUntilLevel > currLevel) {
                    uint8 bundleType = uint8((packed >> ETH_WHALE_BUNDLE_TYPE_SHIFT) & 3);
                    if (bundleType == 1) {
                        bonusBps += 1000; // +10% for 10-level bundle
                    } else if (bundleType == 3) {
                        bonusBps += 4000; // +40% for 100-level bundle
                    }
                }
            }
        }

        multiplierBps = 10000 + bonusBps;
    }

    /// @dev Calculate streak bonus points (max 50% for perfect participation).
    ///      Perfect streak (100% participation) always = 50 points (50%).
    ///      Level 2 with streak 2 (100%): 50 points (50%)
    ///      Level 10 with streak 10 (100%): 50 points (50%)
    ///      Level 10 with streak 5 (50%): 25 points (25%)
    ///      Level 30 with streak 30 (100%): 50 points (50%)
    /// @param streak Player's consecutive mint streak.
    /// @param currLevel Current game level.
    /// @return Bonus points (0-25) scaled by participation percentage.
    function _streakBonusPoints(
        uint24 streak,
        uint24 currLevel
    ) private pure returns (uint256) {
        if (currLevel == 0) return 0;

        // Perfect streak (streak >= currLevel) = 50 points
        if (streak >= currLevel) return 50;

        // Otherwise: (streak / currLevel) * 50
        // Example: level 10, streak 5 = (5 * 50) / 10 = 25 points
        return (uint256(streak) * 50) / uint256(currLevel);
    }

    /// @dev Calculate mint count bonus points (max 25% for perfect participation).
    ///      Perfect participation (100% mints) always = 25 points (25%).
    ///      Level 2 with 2 mints (100%): 25 points (25%)
    ///      Level 10 with 10 mints (100%): 25 points (25%)
    ///      Level 10 with 7 mints (70%): 17.5 points (17.5%)
    ///      Level 30 with 30 mints (100%): 25 points (25%)
    /// @param mintCount Player's total level mint count.
    /// @param currLevel Current game level.
    /// @return Bonus points (0-25) scaled by participation percentage.
    function _mintCountBonusPoints(
        uint24 mintCount,
        uint24 currLevel
    ) private pure returns (uint256) {
        if (currLevel == 0) return 0;

        // Perfect participation (mintCount >= currLevel) = 25 points
        if (mintCount >= currLevel) return 25;

        // Otherwise: (mintCount / currLevel) * 25
        // Example: level 10, 7 mints = (7 * 25) / 10 = 17.5 points
        return (uint256(mintCount) * 25) / uint256(currLevel);
    }



    /*+======================================================================+
      |                   VIEW: CLAIMS & LOOTBOX COUNTS                      |
      +======================================================================+
      |  Read-only accessors for claim balances and deferred lootbox totals. |
      +======================================================================+*/

    /// @notice Get the caller's claimable winnings balance.
    /// @dev Returns 0 if balance is only the 1 wei sentinel.
    /// @return Claimable amount in wei (excludes sentinel).
    function getWinnings() external view returns (uint256) {
        uint256 stored = claimableWinnings[msg.sender];
        if (stored <= 1) return 0;
        return stored - 1;
    }

    /// @notice Get a player's raw claimable balance (includes the 1 wei sentinel).
    function claimableWinningsOf(
        address player
    ) external view returns (uint256) {
        return claimableWinnings[player];
    }

    /// @notice Get pending whale pass claim amount for a player.
    /// @param player Player address to query.
    /// @return Amount of ETH claimable as whale pass tickets.
    function whalePassClaimAmount(
        address player
    ) external view returns (uint256) {
        return whalePassClaims[player];
    }

    /// @notice Get deity pass count for a player.
    /// @param player Player address to query.
    /// @return Count of deity passes owned.
    function deityPassCountFor(address player) external view returns (uint16) {
        return deityPassCount[player];
    }

    /// @notice Get giftable 10-level whale bundle credits for a player.
    /// @param player Player address to query.
    /// @return Credits available for redemption.
    function whaleBundle10PassCreditsFor(
        address player
    ) external view returns (uint16) {
        uint256 balance = lazyPass.inactiveBalanceOf(player);
        if (balance > type(uint16).max) return type(uint16).max;
        return uint16(balance);
    }



    /*+======================================================================+
      |                    TRAIT TICKET SAMPLING                             |
      +======================================================================+
      |  View function for sampling burn ticket holders from recent levels.  |
      |  Used for scatter draws and promotional mechanics.                   |
      +======================================================================+*/

    /// @notice Sample up to 4 trait burn tickets from a random trait and recent level.
    /// @dev Samples from last 20 levels. Uses entropy to select level, trait, and offset.
    ///      Returns empty array if no tickets exist for selected level/trait.
    /// @param entropy Random seed (typically VRF word) for selection.
    /// @return lvlSel Selected level.
    /// @return traitSel Selected trait ID.
    /// @return tickets Array of up to 4 ticket holder addresses.
    function sampleTraitTickets(
        uint256 entropy
    )
        external
        view
        returns (uint24 lvlSel, uint8 traitSel, address[] memory tickets)
    {
        uint24 currentLvl = level;
        if (currentLvl <= 1) {
            return (0, 0, new address[](0));
        }

        uint24 maxOffset = currentLvl - 1;
        if (maxOffset > 20) maxOffset = 20;

        uint256 word = entropy;
        uint24 offset;
        unchecked {
            offset = uint24(word % maxOffset) + 1; // 1..maxOffset
            lvlSel = currentLvl - offset;
        }

        traitSel = uint8(word >> 24); // use a disjoint byte from the VRF word
        address[] storage arr = traitBurnTicket[lvlSel][traitSel];
        uint256 len = arr.length;
        if (len == 0) {
            return (lvlSel, traitSel, new address[](0));
        }

        uint256 take = len > 4 ? 4 : len; // only need a small sample for scatter draws
        tickets = new address[](take);
        uint256 start = (word >> 40) % len; // consume another slice for the start offset
        for (uint256 i; i < take; ) {
            tickets[i] = arr[(start + i) % len];
            unchecked {
                ++i;
            }
        }
    }



    /*+======================================================================+
      |                    VIEW: TRAIT & EXTERMINATOR QUERIES                |
      +======================================================================+
      |  Read-only functions for querying trait state and game history.      |
      +======================================================================+*/

    /// @notice Get the exterminator address for a level.
    /// @param lvl The level to query.
    /// @return The address that triggered extermination (address(0) if timeout or not reached).
    function levelExterminator(uint24 lvl) external view returns (address) {
        if (lvl == 0) return address(0);
        return levelExterminators[lvl];
    }

    /// @notice Get the starting trait count for a trait at current level.
    /// @param traitId The trait ID to query.
    /// @return The count at level start.
    function startTraitRemaining(uint8 traitId) external view returns (uint32) {
        return traitStartRemaining[traitId];
    }

    /// @notice Get remaining counts for 4 traits at once.
    /// @dev Batched for gas efficiency when checking token traits.
    /// @param traitIds Array of 4 trait IDs.
    /// @return lastExterminated The current level's exterminated trait if set, otherwise last level's (or TRAIT_ID_TIMEOUT).
    /// @return currentLevel Current game level.
    /// @return remaining Array of remaining counts for each trait.
    function getTraitRemainingQuad(
        uint8[4] calldata traitIds
    )
        external
        view
        returns (
            uint16 lastExterminated,
            uint24 currentLevel,
            uint32[4] memory remaining
        )
    {
        (lastExterminated, currentLevel, remaining, ) = _getTraitRemainingQuad(traitIds);
    }

    function getTraitRemainingQuadExt(
        uint8[4] calldata traitIds
    )
        external
        view
        returns (
            uint16 lastExterminated,
            uint24 currentLevel,
            uint32[4] memory remaining,
            bool exOpen
        )
    {
        return _getTraitRemainingQuad(traitIds);
    }

    function _getTraitRemainingQuad(
        uint8[4] calldata traitIds
    )
        private
        view
        returns (
            uint16 lastExterminated,
            uint24 currentLevel,
            uint32[4] memory remaining,
            bool exOpen
        )
    {
        currentLevel = level;
        uint16 currentEx = currentExterminatedTrait;
        exOpen = currentEx == TRAIT_ID_TIMEOUT;
        lastExterminated = currentEx < 256 ? currentEx : lastExterminatedTrait;
        remaining[0] = traitRemaining[traitIds[0]];
        remaining[1] = traitRemaining[traitIds[1]];
        remaining[2] = traitRemaining[traitIds[2]];
        remaining[3] = traitRemaining[traitIds[3]];
    }

    /// @notice Count a player's tickets for a specific trait and level.
    /// @dev Paginated for large ticket arrays.
    /// @param trait The trait ID.
    /// @param lvl The level to query.
    /// @param offset Starting index for pagination.
    /// @param limit Maximum entries to scan.
    /// @param player The player address to count.
    /// @return count Number of tickets found in this page.
    /// @return nextOffset Next offset for pagination.
    /// @return total Total tickets in the array.
    function getTickets(
        uint8 trait,
        uint24 lvl,
        uint32 offset,
        uint32 limit,
        address player
    ) external view returns (uint24 count, uint32 nextOffset, uint32 total) {
        address[] storage a = traitBurnTicket[lvl][trait];
        total = uint32(a.length);
        if (offset >= total) return (0, total, total);

        uint256 end = offset + limit;
        if (end > total) end = total;

        for (uint256 i = offset; i < end; ) {
            if (a[i] == player) count++;
            unchecked {
                ++i;
            }
        }
        nextOffset = uint32(end);
    }

    /// @notice Get pending gamepiece mints and tickets owed to a player.
    /// @param player The player address.
    /// @return mints Number of gamepiece mints owed.
    /// @return tickets Number of tickets owed for current level.
    function getPlayerPurchases(
        address player
    ) external view returns (uint32 mints, uint32 tickets) {
        mints = gamepieces.tokensOwed(player);
        tickets = ticketsOwed[level][player];
    }

    /*+======================================================================+
      |                    TESTING FUNCTIONS                                 |
      +======================================================================+
      |  Admin-only functions for testing and simulation purposes.           |
      |  WARNING: These functions should NEVER be deployed to mainnet.       |
      +======================================================================+*/

    /*+======================================================================+
      |                    RECEIVE FUNCTION                                  |
      +======================================================================+
      |  Accept plain ETH transfers and route to reward pool.                |
      |  This allows external contributions to jackpot rewards.              |
      +======================================================================+*/

    /// @notice Accept ETH and add to the future pool reserve.
    /// @dev Plain ETH transfers are routed to jackpot reserves.
    receive() external payable {
        futurePrizePool += msg.value;
    }
}
