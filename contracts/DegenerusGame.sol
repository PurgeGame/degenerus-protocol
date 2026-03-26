// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/**
 * @title DegenerusGame
 * @author Burnie Degenerus
 * @notice Core game contract managing state machine, VRF integration, jackpots, and prize pools.
 *
 * @dev ARCHITECTURE:
 *      - 2-state FSM: PURCHASE(false) ↔ JACKPOT(true) → (cycle)
 *      - gameOver flag is terminal
 *      - Presale is a toggle (lootboxPresaleActive), not a state
 *      - Chainlink VRF for randomness with RNG lock to prevent manipulation
 *      - Delegatecall modules: endgame, jackpot, mint (must inherit DegenerusGameStorage)
 *      - Prize pool flow: futurePrizePool (unified reserve) → nextPrizePool → currentPrizePool → claimableWinnings
 *
 * @dev CRITICAL INVARIANTS:
 *      - address(this).balance + steth.balanceOf(this) >= claimablePool
 *      - jackpotPhaseFlag transitions: false(PURCHASE) ↔ true(JACKPOT); gameOver is terminal
 *      - lootboxPresaleActive starts true, auto-ends at PURCHASE→JACKPOT or via admin (one-way: never re-enables)
 *
 * @dev SECURITY:
 *      - Pull pattern for ETH/stETH withdrawals (claimWinnings)
 *      - RNG lock prevents state manipulation during VRF callback window
 *      - Access control via msg.sender checks
 *      - Delegatecall modules use constant addresses from ContractAddresses
 *      - 12h VRF timeout, 3-day stall detection, 120-day inactivity guard
 */

import {IDegenerusCoin} from "./interfaces/IDegenerusCoin.sol";
import {IBurnieCoinflip} from "./interfaces/IBurnieCoinflip.sol";
import {IDegenerusAffiliate} from "./interfaces/IDegenerusAffiliate.sol";
import {IStakedDegenerusStonk} from "./interfaces/IStakedDegenerusStonk.sol";
import {IStETH} from "./interfaces/IStETH.sol";
import {
    IDegenerusGameAdvanceModule,
    IDegenerusGameEndgameModule,
    IDegenerusGameDecimatorModule,
    IDegenerusGameJackpotModule,
    IDegenerusGameMintModule,
    IDegenerusGameWhaleModule,
    IDegenerusGameLootboxModule,
    IDegenerusGameBoonModule,
    IDegenerusGameDegeneretteModule
} from "./interfaces/IDegenerusGameModules.sol";
import {MintPaymentKind} from "./interfaces/IDegenerusGame.sol";
import {
    DegenerusGameMintStreakUtils
} from "./modules/DegenerusGameMintStreakUtils.sol";
import {ContractAddresses} from "./ContractAddresses.sol";
import {BitPackingLib} from "./libraries/BitPackingLib.sol";

/*+==============================================================================+
  |                     EXTERNAL INTERFACE DEFINITIONS                           |
  +==============================================================================+
  |  Minimal interfaces for external contracts this contract interacts with.     |
  |  These are defined locally to avoid circular import dependencies.            |
  +==============================================================================+*/

/// @notice Interface for reading player quest states.
interface IDegenerusQuestView {
    /// @notice Get a player's quest progress and streak information.
    /// @param player The player address to query.
    /// @return streak The player's consecutive quest completion streak.
    /// @return lastCompletedDay The day index when the player last completed a quest.
    /// @return progress Array of progress values for active quests.
    /// @return completed Array of completion flags for active quests.
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

// ===========================================================================
// Contract
// ===========================================================================

/**
 * @title DegenerusGame
 * @author Burnie Degenerus
 * @notice Core game contract implementing the game state machine, VRF integration,
 *         and orchestration of all gameplay mechanics.
 * @dev Inherits DegenerusGameStorage for shared storage layout with delegate modules.
 *      Uses delegatecall pattern for complex logic (endgame, jackpot, mint modules).
 * @custom:security-contact burnie@degener.us
 */
contract DegenerusGame is DegenerusGameMintStreakUtils {
    /*+======================================================================+
      |                              ERRORS                                  |
      +======================================================================+
      |  Custom errors for gas-efficient reverts. Each error maps to a       |
      |  specific failure condition in the game flow.                        |
      +======================================================================+*/

    // error E() — inherited from DegenerusGameStorage

    // error RngLocked() — inherited from DegenerusGameStorage

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

    /// @notice Emitted when the lootbox RNG request threshold is updated.
    /// @param previous Previous threshold in wei.
    /// @param current New threshold in wei.
    event LootboxRngThresholdUpdated(uint256 previous, uint256 current);
    /// @notice Emitted when a player approves or revokes an operator.
    /// @param owner The player granting approval.
    /// @param operator The approved operator.
    /// @param approved True if approved, false if revoked.
    event OperatorApproval(
        address indexed owner,
        address indexed operator,
        bool approved
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

    /// @notice Lido stETH token contract.
    /// @dev Used for staking ETH and managing yield.
    IStETH internal constant steth = IStETH(ContractAddresses.STETH_TOKEN);

    /// @notice Affiliate program contract for bonus points and referrers.
    IDegenerusAffiliate internal constant affiliate =
        IDegenerusAffiliate(ContractAddresses.AFFILIATE);

    /// @notice sDGNRS token contract for affiliate pool rewards.
    IStakedDegenerusStonk internal constant dgnrs =
        IStakedDegenerusStonk(ContractAddresses.SDGNRS);

    /// @notice Quest module view interface for streak lookups.
    IDegenerusQuestView internal constant questView =
        IDegenerusQuestView(ContractAddresses.QUESTS);

    /*+======================================================================+
      |                           CONSTANTS                                  |
      +======================================================================+
      |  Game parameters and bit manipulation constants. All constants are   |
      |  private to prevent external dependency on specific values.          |
      +======================================================================+*/

    /// @dev Deploy idle timeout in days (for efficient day-index comparison).
    uint48 private constant DEPLOY_IDLE_TIMEOUT_DAYS = 365; // 1 year

    /// @dev Minimum take profit for afKing ETH auto-rebuy (5 ETH).
    uint256 private constant AFKING_KEEP_MIN_ETH = 5 ether;

    /// @dev Minimum take profit for afKing coin auto-rebuy (20,000 BURNIE).
    uint256 private constant AFKING_KEEP_MIN_COIN = 20_000 ether;

    /// @dev Number of levels afKing mode is locked after activation.
    uint24 private constant AFKING_LOCK_LEVELS = 5;

    /// @dev Share of ticket purchases routed to future prize pool (10%).
    uint16 private constant PURCHASE_TO_FUTURE_BPS = 1000;

    /// @dev DGNRS bounty share for biggest flip payout (0.2% of reward pool).
    uint16 private constant COINFLIP_BOUNTY_DGNRS_BPS = 20;
    uint256 private constant COINFLIP_BOUNTY_DGNRS_MIN_BET = 50_000 ether;
    uint256 private constant COINFLIP_BOUNTY_DGNRS_MIN_POOL = 20_000 ether;

    /// @dev Bonus BURNIE flip credit for deity pass affiliate claims (20% of payout).
    uint16 private constant AFFILIATE_DGNRS_DEITY_BONUS_BPS = 2000;

    /// @dev Max deity bonus per level, denominated in ETH (converted to BURNIE at current price).
    uint256 private constant AFFILIATE_DGNRS_DEITY_BONUS_CAP_ETH = 5 ether;

    /// @dev Minimum affiliate score (approx 10 ETH of referral volume).
    uint256 private constant AFFILIATE_DGNRS_MIN_SCORE = 10 ether;

    /// @dev Deity pass activity score bonus (80%).
    uint16 private constant DEITY_PASS_ACTIVITY_BONUS_BPS = 8000;
    /// @dev Active pass minimum streak points (max streak, assumes always active).
    uint16 private constant PASS_STREAK_FLOOR_POINTS = 50;
    /// @dev Active pass minimum mint count points (max participation, assumes always active).
    uint16 private constant PASS_MINT_COUNT_FLOOR_POINTS = 25;

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
      |  [154-159] (reserved)       - 6 unused bits                           |
      |  [160-183] mintStreakLast  - Mint streak last completed level (24b)   |
      |  [184-227] (reserved)      - 44 unused bits                          |
      |  [228-243] unitsAtLevel    - Mints at current level                  |
      |  [244]    (deprecated)     - Previously used for bonus tracking      |
      +======================================================================+*/

    /*+======================================================================+
      |                          CONSTRUCTOR                                 |
      +======================================================================+
      |  Initialize storage wiring and set up initial approvals.             |
      |  The constructor wires together the entire game ecosystem.           |
      +======================================================================+*/

    /**
     * @notice Initialize the game with precomputed contract references.
     * @dev All addresses and deploy day boundary are compile-time constants from ContractAddresses.
     *      levelStartTime is initialized here to the deploy timestamp.
     *      Deploy day boundary determines which calendar day is "day 1" in the game.
     */
    constructor() {
        levelStartTime = uint48(block.timestamp);
        levelPrizePool[0] = BOOTSTRAP_PRIZE_POOL;
        // Vault addresses get deity-equivalent score boost (no symbol, not in deityPassOwners)
        deityPassCount[ContractAddresses.SDGNRS] = 1;
        deityPassCount[ContractAddresses.VAULT] = 1;
        // Pre-queue vault perpetual tickets for levels 1-100 (advance module handles 101+)
        for (uint24 i = 1; i <= 100; ) {
            _queueTickets(ContractAddresses.SDGNRS, i, 16);
            _queueTickets(ContractAddresses.VAULT, i, 16);
            unchecked {
                ++i;
            }
        }
    }

    /*+======================================================================+
      |                           MODIFIERS                                  |
      +======================================================================+*/

    /*+========================================================================================+
      |                    CORE STATE MACHINE: advanceGame()                                   |
      +========================================================================================+
      |  The heart of the game. This function progresses the state machine                     |
      |  through its 2 active phases: PURCHASE (jackpotPhaseFlag=false), JACKPOT (jackpotPhaseFlag=true). |
      |  Each call performs one "tick" of work. gameOver is terminal.                          |
      |                                                                                        |
      |  State Transitions:                                                                    |
      |  • PURCHASE (jackpotPhaseFlag=false): Process ticket batches until target met, then → JACKPOT|
      |  • JACKPOT (jackpotPhaseFlag=true): Pay daily jackpots, wait for burns, then → PURCHASE      |
      |  • GAMEOVER (gameOver=true): Terminal state, no transitions                             |
      |                                                                                        |
      |  Gating (tiered bypass):                                                                |
      |  • Deity pass holder — always bypasses                                                 |
      |  • Anyone — bypasses after 30+ min since level start                                   |
      |  • Pass holder (lazy/whale) — bypasses after 15+ min                                   |
      |  • DGVE majority holder — always bypasses (last resort, external call)                 |
      |  • RNG must be ready (not locked) or recently stale (18h timeout)                      |
      |                                                                                        |
      |  Presale: lootboxPresaleActive toggle (orthogonal to state machine)                    |
      |  • Starts active: 62% bonus BURNIE from loot boxes, bonusFlip active                    |
      |  • Auto-ends when PURCHASE→JACKPOT, or admin can end manually (one-way, cannot re-enable) |
      +========================================================================================+*/

    /// @notice Advance the game state machine by one tick.
    /// @dev Anyone can call, but standard flows require an ETH mint today.
    ///      This is the primary driver of game progression - called repeatedly
    ///      to move through states and process batched operations.
    ///
    ///      FLOW OVERVIEW:
    ///      1. Check liveness guards (1yr deploy timeout, 120-day inactivity)
    ///      2. Apply tiered daily gate (deity > anyone after 30min > pass after 15min > DGVE majority)
    ///      3. Process transition housekeeping during jackpot→purchase transition
    ///      4. Gate on RNG readiness (request new VRF if needed)
    ///      5. Process ticket batches
    ///      6. Execute state-specific logic:
    ///         - TRANSITION: Housekeeping + near-future ticket prep after burn completes
    ///         - PURCHASE/JACKPOT: Process phase-specific logic
    ///      7. Credit caller with BURNIE bounty during jackpot time when not requesting or unlocking RNG
    ///
    ///      SECURITY:
    ///      - Liveness guards prevent abandoned game lockup
    ///      - Daily gate prevents non-participants from advancing
    ///      - RNG gating ensures fairness (no manipulation during VRF window)
    ///      - Batched processing prevents DoS from large queues
    ///
    function advanceGame() external {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_ADVANCE_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameAdvanceModule.advanceGame.selector
                )
            );
        if (!ok) _revertDelegate(data);
    }

    /*+========================================================================================+
      |                    ADMIN VRF FUNCTIONS                                                 |
      +========================================================================================+
      |  One-time VRF setup function called by ADMIN during deployment phase.                  |
      +========================================================================================+*/

    /// @notice Wire VRF config from the VRF ADMIN contract.
    /// @dev Access: ADMIN only. Overwrites any existing config on each call.
    ///      SECURITY: Config can be changed via emergency rotation (updateVrfCoordinatorAndSub).
    /// @param coordinator_ Chainlink VRF V2.5 coordinator address.
    /// @param subId VRF subscription ID for LINK billing.
    /// @param keyHash_ VRF key hash identifying the oracle and gas lane.
    /// @custom:reverts E If caller is not ADMIN.
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
      |  Functions called by the game contract to record mints and process         |
      |  payments. ETH and claimable winnings can both fund purchases.       |
      +======================================================================+*/

    /// @notice Record a mint, funded by ETH or claimable winnings.
    /// @dev Access: self-call only (from delegate modules).
    ///      Payment modes:
    ///      - DirectEth: msg.value must be >= costWei (overage ignored for accounting)
    ///      - Claimable: deduct from claimableWinnings (msg.value must be 0)
    ///      - Combined: ETH first, then claimable for remainder
    ///
    ///      SECURITY: Validates minimum payment amounts; overage is ignored for accounting.
    ///      Prize contribution is split between nextPrizePool and futurePrizePool.
    ///
    /// @param player The player address to record mint for.
    /// @param lvl The level at which mint is occurring.
    /// @param costWei Total cost in wei for this mint.
    /// @param mintUnits Number of mint units purchased.
    /// @param payKind Payment method (DirectEth, Claimable, or Combined).
    /// @return newClaimableBalance Player's claimable balance after deduction (0 if DirectEth).
    /// @custom:reverts E If caller is not self-call context or payment validation fails.
    function recordMint(
        address player,
        uint24 lvl,
        uint256 costWei,
        uint32 mintUnits,
        MintPaymentKind payKind
    )
        external
        payable
        returns (uint256 newClaimableBalance)
    {
        if (msg.sender != address(this)) revert E();
        uint256 prizeContribution;
        (prizeContribution, newClaimableBalance) = _processMintPayment(
            player,
            costWei,
            payKind
        );
        if (prizeContribution != 0) {
            uint256 futureShare = (prizeContribution * PURCHASE_TO_FUTURE_BPS) /
                10_000;
            uint256 nextShare = prizeContribution - futureShare;
            if (prizePoolFrozen) {
                (uint128 pNext, uint128 pFuture) = _getPendingPools();
                _setPendingPools(
                    pNext + uint128(nextShare),
                    pFuture + uint128(futureShare)
                );
            } else {
                (uint128 next, uint128 future) = _getPrizePools();
                _setPrizePools(
                    next + uint128(nextShare),
                    future + uint128(futureShare)
                );
            }
        }

        _recordMintDataModule(player, lvl, mintUnits);
        uint256 earlybirdEth = 0;
        if (payKind == MintPaymentKind.DirectEth) {
            earlybirdEth = msg.value > costWei ? costWei : msg.value;
        } else if (payKind == MintPaymentKind.Combined) {
            earlybirdEth = msg.value;
        }
        _awardEarlybirdDgnrs(player, earlybirdEth, lvl);
    }

    /// @notice Record mint streak completion after a 1x price ETH quest completes.
    /// @dev Access: COIN contract only.
    /// @param player The player who completed the quest.
    function recordMintQuestStreak(address player) external {
        if (msg.sender != ContractAddresses.COIN) revert E();
        uint24 mintLevel = _activeTicketLevel();
        _recordMintStreakForLevel(player, mintLevel);
    }

    /// @notice Pay DGNRS bounty for the biggest flip record holder.
    /// @dev Access: COIN or COINFLIP contract only.
    ///      Pays a share of the remaining DGNRS reward pool.
    /// @param player Recipient of the DGNRS bounty.
    /// @custom:reverts E If caller is not COIN or COINFLIP contract.
    function payCoinflipBountyDgnrs(
        address player,
        uint256 winningBet,
        uint256 bountyPool
    ) external {
        if (
            msg.sender != ContractAddresses.COIN &&
            msg.sender != ContractAddresses.COINFLIP
        ) revert E();
        if (player == address(0)) return;
        if (winningBet < COINFLIP_BOUNTY_DGNRS_MIN_BET) return;
        if (bountyPool < COINFLIP_BOUNTY_DGNRS_MIN_POOL) return;
        uint256 poolBalance = dgnrs.poolBalance(
            IStakedDegenerusStonk.Pool.Reward
        );
        if (poolBalance == 0) return;
        uint256 payout = (poolBalance * COINFLIP_BOUNTY_DGNRS_BPS) / 10_000;
        if (payout == 0) return;
        dgnrs.transferFromPool(
            IStakedDegenerusStonk.Pool.Reward,
            player,
            payout
        );
    }

    /*+======================================================================+
      |                      OPERATOR APPROVALS                             |
      +======================================================================+*/

    /// @notice Approve or revoke an operator to act on your behalf.
    /// @param operator Address to approve or revoke.
    /// @param approved True to approve, false to revoke.
    /// @custom:reverts E If operator is the zero address.
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

    function _resolvePlayer(
        address player
    ) private view returns (address resolved) {
        if (player == address(0)) return msg.sender;
        if (player != msg.sender) _requireApproved(player);
        return player;
    }

    /*+======================================================================+
      |                       LOOT BOX CONTROLS                             |
      +======================================================================+*/

    /// @notice Current day index.
    function currentDayView() external view returns (uint48) {
        return _simulatedDayIndex();
    }

    /// @notice Update lootbox RNG request threshold (wei).
    /// @dev Access: ADMIN only.
    /// @param newThreshold New threshold in wei (must be non-zero).
    /// @custom:reverts E If caller is not ADMIN or newThreshold is zero.
    function setLootboxRngThreshold(uint256 newThreshold) external {
        if (msg.sender != ContractAddresses.ADMIN) revert E();
        if (newThreshold == 0) revert E();
        uint256 prev = lootboxRngThreshold;
        if (newThreshold == prev) {
            emit LootboxRngThresholdUpdated(prev, newThreshold);
            return;
        }
        lootboxRngThreshold = newThreshold;
        emit LootboxRngThresholdUpdated(prev, newThreshold);
    }

    /// @notice Purchase any combination of tickets and loot boxes with ETH or claimable.
    /// @dev Main entry point for all ETH/claimable purchases. For BURNIE purchases, use purchaseCoin().
    ///      Spending all claimable winnings earns a 10% bonus across the combined purchase.
    ///      Adds affiliate support for loot box purchases.
    ///      SECURITY: Blocked when RNG is locked.
    /// @param buyer Player address to receive purchases (address(0) = msg.sender).
    /// @param ticketQuantity Number of tickets to purchase (2 decimals, scaled by 100; 0 to skip).
    /// @param lootBoxAmount ETH amount for loot boxes, minimum 0.01 ETH (0 to skip).
    /// @param affiliateCode Affiliate/referral code for all purchases.
    /// @param payKind Payment method (DirectEth, Claimable, or Combined).
    function purchase(
        address buyer,
        uint256 ticketQuantity,
        uint256 lootBoxAmount,
        bytes32 affiliateCode,
        MintPaymentKind payKind
    ) external payable {
        buyer = _resolvePlayer(buyer);
        _purchaseFor(
            buyer,
            ticketQuantity,
            lootBoxAmount,
            affiliateCode,
            payKind
        );
    }

    function _purchaseFor(
        address buyer,
        uint256 ticketQuantity,
        uint256 lootBoxAmount,
        bytes32 affiliateCode,
        MintPaymentKind payKind
    ) private {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_MINT_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameMintModule.purchase.selector,
                    buyer,
                    ticketQuantity,
                    lootBoxAmount,
                    affiliateCode,
                    payKind
                )
            );
        if (!ok) _revertDelegate(data);
    }

    /// @notice Purchase tickets and/or loot boxes with BURNIE.
    /// @dev Main entry point for all BURNIE purchases. Mirrors purchase() but for BURNIE payments.
    ///      SECURITY: Blocked when RNG is locked.
    /// @param buyer Player address to receive purchases (address(0) = msg.sender).
    /// @param ticketQuantity Number of tickets to purchase (2 decimals, scaled by 100; 0 to skip).
    /// @param lootBoxBurnieAmount BURNIE amount for loot box (0 to skip).
    function purchaseCoin(
        address buyer,
        uint256 ticketQuantity,
        uint256 lootBoxBurnieAmount
    ) external {
        buyer = _resolvePlayer(buyer);
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_MINT_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameMintModule.purchaseCoin.selector,
                    buyer,
                    ticketQuantity,
                    lootBoxBurnieAmount
                )
            );
        if (!ok) _revertDelegate(data);
    }

    /// @notice Purchase a low-EV loot box using BURNIE.
    /// @param buyer Player address to receive the loot box (address(0) = msg.sender).
    /// @param burnieAmount BURNIE amount to burn (18 decimals).
    function purchaseBurnieLootbox(
        address buyer,
        uint256 burnieAmount
    ) external {
        buyer = _resolvePlayer(buyer);
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_MINT_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameMintModule.purchaseBurnieLootbox.selector,
                    buyer,
                    burnieAmount
                )
            );
        if (!ok) _revertDelegate(data);
    }

    /// @notice Purchase whale bundle: boosts levelCount, queues 400 tickets, includes lootbox.
    /// @dev Available at any level. Can be purchased multiple times (1-100 per call).
    ///      Price: 2.4 ETH (levels 0-3), 4 ETH (levels 4+), or discounted with boon.
    ///      Queues 4 tickets for each of 100 levels [ticketStart, ticketStart+99].
    ///      Includes lootbox (20% of price during presale, 10% after).
    ///      Frozen stats don't increment until game reaches the frozen level.
    ///
    ///      Fund distribution - Level 0: 30% next / 70% future.
    ///      Fund distribution - Other levels: 5% next / 95% future.
    ///
    ///      Example at level 1: 4 tickets each for levels 1-100, stats boosted, frozen until 100.
    ///      Example at level 51: 4 tickets each for levels 51-150, stats boosted, frozen until 150.
    /// @param buyer Player address to receive bundle rewards (address(0) = msg.sender).
    /// @param quantity Number of bundles to purchase.
    function purchaseWhaleBundle(
        address buyer,
        uint256 quantity
    ) external payable {
        buyer = _resolvePlayer(buyer);
        _purchaseWhaleBundleFor(buyer, quantity);
    }

    function _purchaseWhaleBundleFor(address buyer, uint256 quantity) private {
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

    /// @notice Purchase a 10-level lazy pass (direct in-game activation).
    /// @dev Available at levels 0-2 or x9 (9, 19, 29...), or with a valid lazy pass boon.
    ///      Levels 0-2: flat 0.24 ETH. Levels 3+: sum of per-level ticket prices across 10-level window.
    /// @param buyer Player address to receive pass (address(0) = msg.sender).
    function purchaseLazyPass(address buyer) external payable {
        buyer = _resolvePlayer(buyer);
        _purchaseLazyPassFor(buyer);
    }

    function _purchaseLazyPassFor(address buyer) private {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_WHALE_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameWhaleModule.purchaseLazyPass.selector,
                    buyer
                )
            );
        if (!ok) _revertDelegate(data);
    }

    /// @notice Purchase a deity pass for a specific symbol (0-31).
    /// @param buyer Player address to receive pass (address(0) = msg.sender).
    /// @param symbolId Symbol to claim (0-31: Q0 Crypto 0-7, Q1 Zodiac 8-15, Q2 Cards 16-23, Q3 Dice 24-31).
    function purchaseDeityPass(address buyer, uint8 symbolId) external payable {
        buyer = _resolvePlayer(buyer);
        _purchaseDeityPassFor(buyer, symbolId);
    }

    function _purchaseDeityPassFor(address buyer, uint8 symbolId) private {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_WHALE_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameWhaleModule.purchaseDeityPass.selector,
                    buyer,
                    symbolId
                )
            );
        if (!ok) _revertDelegate(data);
    }

    /// @notice Open a loot box once RNG for its lootbox index is available.
    /// @param player Player address that owns the loot box (address(0) = msg.sender).
    /// @param lootboxIndex Lootbox RNG index assigned at purchase time.
    function openLootBox(address player, uint48 lootboxIndex) external {
        player = _resolvePlayer(player);
        _openLootBoxFor(player, lootboxIndex);
    }

    /// @notice Open a BURNIE loot box once RNG for its lootbox index is available.
    /// @param player Player address that owns the loot box (address(0) = msg.sender).
    /// @param lootboxIndex Lootbox RNG index assigned at purchase time.
    function openBurnieLootBox(address player, uint48 lootboxIndex) external {
        player = _resolvePlayer(player);
        _openBurnieLootBoxFor(player, lootboxIndex);
    }

    function _openLootBoxFor(address player, uint48 lootboxIndex) private {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_LOOTBOX_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameLootboxModule.openLootBox.selector,
                    player,
                    lootboxIndex
                )
            );
        if (!ok) _revertDelegate(data);
    }

    function _openBurnieLootBoxFor(
        address player,
        uint48 lootboxIndex
    ) private {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_LOOTBOX_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameLootboxModule.openBurnieLootBox.selector,
                    player,
                    lootboxIndex
                )
            );
        if (!ok) _revertDelegate(data);
    }

    /// @notice Place Full Ticket Degenerette bets (4 traits, match-based payouts).
    /// @param player The betting player (address(0) = msg.sender).
    /// @param currency Currency type (0=ETH, 1=BURNIE, 2=unsupported, 3=WWXRP).
    /// @param amountPerTicket Bet amount per ticket.
    /// @param ticketCount Number of spins (1-10). Each spin resolves independently.
    /// @param customTicket Custom packed traits.
    /// @param heroQuadrant Hero quadrant (0-3) for payout boost, or 0xFF for no hero.
    function placeFullTicketBets(
        address player,
        uint8 currency,
        uint128 amountPerTicket,
        uint8 ticketCount,
        uint32 customTicket,
        uint8 heroQuadrant
    ) external payable {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_DEGENERETTE_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameDegeneretteModule
                        .placeFullTicketBets
                        .selector,
                    _resolvePlayer(player),
                    currency,
                    amountPerTicket,
                    ticketCount,
                    customTicket,
                    heroQuadrant
                )
            );
        if (!ok) _revertDelegate(data);
    }

    /// @notice Resolve multiple Degenerette bets once RNG is available.
    /// @param player The betting player (address(0) = msg.sender).
    /// @param betIds Bet ids for the player.
    function resolveDegeneretteBets(
        address player,
        uint64[] calldata betIds
    ) external {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_DEGENERETTE_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameDegeneretteModule.resolveBets.selector,
                    _resolvePlayer(player),
                    betIds
                )
            );
        if (!ok) _revertDelegate(data);
    }

    /// @notice Consume coinflip boon for next coinflip stake bonus.
    /// @dev Access: COIN or COINFLIP contract only.
    /// @param player The player whose boon to consume.
    /// @return boostBps The boost in basis points to apply.
    /// @custom:reverts E If caller is not COIN or COINFLIP contract.
    function consumeCoinflipBoon(
        address player
    ) external returns (uint16 boostBps) {
        if (
            msg.sender != ContractAddresses.COIN &&
            msg.sender != ContractAddresses.COINFLIP
        ) revert E();
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_BOON_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameBoonModule.consumeCoinflipBoon.selector,
                    player
                )
            );
        if (!ok) _revertDelegate(data);
        return abi.decode(data, (uint16));
    }

    /// @notice Consume decimator boon for burn bonus.
    /// @dev Access: COIN contract only.
    /// @param player The player whose boon to consume.
    /// @return boostBps The boost in basis points to apply.
    /// @custom:reverts E If caller is not COIN contract.
    function consumeDecimatorBoon(
        address player
    ) external returns (uint16 boostBps) {
        if (msg.sender != ContractAddresses.COIN) revert E();
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_BOON_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameBoonModule.consumeDecimatorBoost.selector,
                    player
                )
            );
        if (!ok) _revertDelegate(data);
        return abi.decode(data, (uint16));
    }

    /// @notice Consume purchase boost for purchase bonus.
    /// @dev Access: self-call only (from delegate modules).
    /// @param player The player whose boost to consume.
    /// @return boostBps The boost in basis points to apply.
    /// @custom:reverts E If caller is not self-call context.
    function consumePurchaseBoost(
        address player
    ) external returns (uint16 boostBps) {
        if (msg.sender != address(this)) revert E();
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_BOON_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameBoonModule.consumePurchaseBoost.selector,
                    player
                )
            );
        if (!ok) _revertDelegate(data);
        return abi.decode(data, (uint16));
    }

    /// @notice Get raw deity boon state for off-chain or viewer contract computation.
    /// @param deity The deity address to query.
    /// @return dailySeed RNG seed for today's boon generation.
    /// @return day Current day index.
    /// @return usedMask Bitmask of slots already used (bit i = slot i used).
    /// @return decimatorOpen Whether decimator boons are available.
    /// @return deityPassAvailable Whether deity pass boons can be generated.
    function deityBoonData(
        address deity
    )
        external
        view
        returns (
            uint256 dailySeed,
            uint48 day,
            uint8 usedMask,
            bool decimatorOpen,
            bool deityPassAvailable
        )
    {
        day = _simulatedDayIndex();
        usedMask = deityBoonDay[deity] == day ? deityBoonUsedMask[deity] : 0;
        decimatorOpen = decWindowOpen;
        deityPassAvailable = deityPassOwners.length < 32; // DEITY_PASS_MAX_TOTAL (see LootboxModule)
        uint256 rngWord = rngWordByDay[day];
        if (rngWord == 0) rngWord = rngWordCurrent;
        if (rngWord == 0)
            rngWord = uint256(keccak256(abi.encodePacked(day, address(this))));
        dailySeed = rngWord;
    }

    /// @notice Issue a deity boon to a recipient.
    /// @param deity Deity issuing the boon (address(0) = msg.sender).
    /// @param recipient Recipient of the boon.
    /// @param slot Slot index (0-2).
    /// @custom:reverts E If deity attempts to issue boon to themselves.
    function issueDeityBoon(
        address deity,
        address recipient,
        uint8 slot
    ) external {
        deity = _resolvePlayer(deity);
        if (recipient == deity) revert E();
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_LOOTBOX_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameLootboxModule.issueDeityBoon.selector,
                    deity,
                    recipient,
                    slot
                )
            );
        if (!ok) _revertDelegate(data);
    }

    /// @dev Process mint payment and return amount contributed to prize pool.
    ///      Handles three payment modes with strict validation:
    ///
    ///      DirectEth: msg.value must be >= amount (overage ignored for accounting)
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
            // Direct ETH: allow overpay; ignore remainder for accounting
            if (msg.value < amount) revert E();
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
            emit ClaimableSpent(
                player,
                claimableUsed,
                newClaimableBalance,
                payKind,
                amount
            );
        }
    }

    /*+======================================================================+
      |                       TICKET QUEUEING                                |
      +======================================================================+
      |  Tickets are queued for batch processing rather than minted immediately.|
      |  This prevents gas exhaustion from large purchases.                  |
      +======================================================================+*/

    /*+================================================================================================================+
      |                    DELEGATE MODULE HELPERS                                                                     |
      +================================================================================================================+
      |  Internal functions that delegatecall into specialized modules.                                                |
      |  All modules MUST inherit DegenerusGameStorage for slot alignment.                                             |
      |                                                                                                                |
      |  Modules:                                                                                                      |
      |  • GAME_ADVANCE_MODULE      - Daily advance, VRF, daily processing                                             |
      |  • GAME_BOON_MODULE         - Deity boon effects and activation                                                |
      |  • GAME_DECIMATOR_MODULE    - Decimator claim credits and lootbox payouts                                       |
      |  • GAME_DEGENERETTE_MODULE  - Degenerette bet placement and resolution                                          |
      |  • GAME_ENDGAME_MODULE      - Endgame settlement (payouts, wipes, jackpots)                                     |
      |  • GAME_JACKPOT_MODULE      - Jackpot calculations and payouts                                                  |
      |  • GAME_LOOTBOX_MODULE      - Lootbox open, credit, and payout                                                  |
      |  • GAME_MINT_MODULE         - Mint data recording, airdrop multipliers                                          |
      |  • GAME_WHALE_MODULE        - Whale bundle purchases                                                            |
      |                                                                                                                |
      |  SECURITY: delegatecall executes module code in this contract's                                                |
      |  context, with access to all storage. Modules are constant addresses.                                          |
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
    ///      Updates player's mint history.
    /// @param player Player address being credited.
    /// @param lvl Level at which mint occurred.
    /// @param mintUnits Number of mint units purchased.
    function _recordMintDataModule(
        address player,
        uint24 lvl,
        uint32 mintUnits
    ) private {
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
    }

    /*+========================================================================================+
      |                    DECIMATOR JACKPOT LOGIC                                             |
      +========================================================================================+*/

    /// @notice Record a Decimator burn for jackpot eligibility.
    /// @dev Access: COIN contract only (enforced in module).
    /// @param player Address of the player.
    /// @param lvl Current game level.
    /// @param bucket Player's chosen denominator (2-12).
    /// @param baseAmount Burn amount before multiplier.
    /// @param multBps Multiplier in basis points (10000 = 1x).
    /// @return bucketUsed The bucket actually used (may differ from requested if not an improvement).
    function recordDecBurn(
        address player,
        uint24 lvl,
        uint8 bucket,
        uint256 baseAmount,
        uint256 multBps
    ) external returns (uint8 bucketUsed) {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_DECIMATOR_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameDecimatorModule.recordDecBurn.selector,
                    player,
                    lvl,
                    bucket,
                    baseAmount,
                    multBps
                )
            );
        if (!ok) _revertDelegate(data);
        if (data.length == 0) revert E();
        return abi.decode(data, (uint8));
    }

    /// @notice Snapshot Decimator jackpot winners for deferred claims.
    /// @dev Access: Game-only (self-call).
    /// @param poolWei Total ETH prize pool for this level.
    /// @param lvl Level number being resolved.
    /// @param rngWord VRF-derived randomness seed.
    /// @return returnAmountWei Amount to return (non-zero if no winners or already snapshotted).
    function runDecimatorJackpot(
        uint256 poolWei,
        uint24 lvl,
        uint256 rngWord
    ) external returns (uint256 returnAmountWei) {
        if (msg.sender != address(this)) revert E();
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_DECIMATOR_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameDecimatorModule.runDecimatorJackpot.selector,
                    poolWei,
                    lvl,
                    rngWord
                )
            );
        if (!ok) _revertDelegate(data);
        if (data.length == 0) revert E();
        return abi.decode(data, (uint256));
    }

    // -------------------------------------------------------------------------
    // Terminal Decimator (Death Bet)
    // -------------------------------------------------------------------------

    /// @notice Record a terminal decimator burn.
    /// @dev Delegatecalls to DecimatorModule. Access: coin contract only.
    function recordTerminalDecBurn(
        address player,
        uint24 lvl,
        uint256 baseAmount
    ) external {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_DECIMATOR_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameDecimatorModule.recordTerminalDecBurn.selector,
                    player,
                    lvl,
                    baseAmount
                )
            );
        if (!ok) _revertDelegate(data);
    }

    /// @notice Resolve terminal decimator at GAMEOVER.
    /// @dev Access: Game-only (self-call from handleGameOverDrain).
    function runTerminalDecimatorJackpot(
        uint256 poolWei,
        uint24 lvl,
        uint256 rngWord
    ) external returns (uint256 returnAmountWei) {
        if (msg.sender != address(this)) revert E();
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_DECIMATOR_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameDecimatorModule.runTerminalDecimatorJackpot.selector,
                    poolWei,
                    lvl,
                    rngWord
                )
            );
        if (!ok) _revertDelegate(data);
        if (data.length == 0) revert E();
        return abi.decode(data, (uint256));
    }

    /// @notice Terminal decimator window. Always open except lastPurchaseDay and gameOver.
    /// @return open True if terminal decimator burns are allowed.
    /// @return lvl Current game level.
    function terminalDecWindow() external view returns (bool open, uint24 lvl) {
        lvl = level;
        open = !gameOver && !lastPurchaseDay;
    }

    /// @notice Terminal jackpot for x00 levels: Day-5-style bucket distribution.
    /// @dev Access: Game-only (self-call). Delegatecalls to JackpotModule.
    ///      Updates claimablePool internally — callers must NOT double-count.
    /// @param poolWei Total ETH to distribute.
    /// @param targetLvl Level to sample winners from.
    /// @param rngWord VRF entropy seed.
    /// @return paidWei Total ETH distributed.
    function runTerminalJackpot(
        uint256 poolWei,
        uint24 targetLvl,
        uint256 rngWord
    ) external returns (uint256 paidWei) {
        if (msg.sender != address(this)) revert E();
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_JACKPOT_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameJackpotModule.runTerminalJackpot.selector,
                    poolWei,
                    targetLvl,
                    rngWord
                )
            );
        if (!ok) _revertDelegate(data);
        if (data.length == 0) revert E();
        return abi.decode(data, (uint256));
    }

    /// @notice Consume Decimator claim on behalf of player.
    /// @dev Access: Game-only (self-call).
    /// @param player Address to claim for.
    /// @param lvl Level to claim from.
    /// @return amountWei Pro-rata payout amount.
    function consumeDecClaim(
        address player,
        uint24 lvl
    ) external returns (uint256 amountWei) {
        if (msg.sender != address(this)) revert E();
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_DECIMATOR_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameDecimatorModule.consumeDecClaim.selector,
                    player,
                    lvl
                )
            );
        if (!ok) _revertDelegate(data);
        if (data.length == 0) revert E();
        return abi.decode(data, (uint256));
    }

    /// @notice Claim Decimator jackpot for caller.
    /// @param lvl Level to claim from (must be the last decimator).
    function claimDecimatorJackpot(uint24 lvl) external {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_DECIMATOR_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameDecimatorModule
                        .claimDecimatorJackpot
                        .selector,
                    lvl
                )
            );
        if (!ok) _revertDelegate(data);
    }

    /// @notice Check if player can claim Decimator jackpot for a level.
    /// @param player Address to check.
    /// @param lvl Level to check.
    /// @return amountWei Claimable amount (0 if not winner or already claimed).
    /// @return winner True if player is a winner for this level.
    function decClaimable(
        address player,
        uint24 lvl
    ) external view returns (uint256 amountWei, bool winner) {
        DecClaimRound storage round = decClaimRounds[lvl];
        if (round.poolWei == 0) {
            return (0, false);
        }

        uint256 totalBurn = uint256(round.totalBurn);
        if (totalBurn == 0) return (0, false);

        DecEntry storage e = decBurn[lvl][player];
        if (e.claimed != 0) return (0, false);

        uint8 denom = e.bucket;
        uint8 sub = e.subBucket;
        uint192 entryBurn = e.burn;
        if (denom == 0 || entryBurn == 0) return (0, false);

        uint64 packedOffsets = decBucketOffsetPacked[lvl];
        uint8 winningSub = _unpackDecWinningSubbucket(packedOffsets, denom);
        if (sub != winningSub) return (0, false);

        amountWei =
            (round.poolWei * uint256(entryBurn)) /
            totalBurn;
        winner = amountWei != 0;
    }

    /// @dev Unpack a winning subbucket from the packed uint64.
    /// @param packed Packed winning subbuckets.
    /// @param denom Denominator to unpack (2-12).
    /// @return Winning subbucket for this denom.
    function _unpackDecWinningSubbucket(
        uint64 packed,
        uint8 denom
    ) private pure returns (uint8) {
        if (denom < 2) return 0;
        uint8 shift = (denom - 2) << 2;
        return uint8((packed >> shift) & 0xF);
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
    event WinningsClaimed(
        address indexed player,
        address indexed caller,
        uint256 amount
    );

    /// @notice Emitted when claimable winnings are spent during a mint payment.
    /// @param player The player whose claimable balance was used.
    /// @param amount Amount of claimable ETH spent.
    /// @param newBalance Player's new claimable balance after spending.
    /// @param payKind Payment method used for the mint.
    /// @param costWei Total mint cost in wei.
    event ClaimableSpent(
        address indexed player,
        uint256 amount,
        uint256 newBalance,
        MintPaymentKind payKind,
        uint256 costWei
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
        player = _resolvePlayer(player);
        _claimWinningsInternal(player, false);
    }

    /// @notice Claim accrued ETH winnings with stETH-first payout.
    /// @dev Restricted to self-claims by the vault or DGNRS contract.
    function claimWinningsStethFirst() external {
        if (msg.sender != ContractAddresses.VAULT) revert E();
        _claimWinningsInternal(msg.sender, true);
    }

    function _claimWinningsInternal(address player, bool stethFirst) private {
        if (finalSwept) revert E();
        uint256 amount = claimableWinnings[player];
        if (amount <= 1) revert E();
        uint256 payout;
        unchecked {
            claimableWinnings[player] = 1; // Leave sentinel
            payout = amount - 1;
        }
        claimablePool -= payout; // CEI: update state before external call
        emit WinningsClaimed(player, msg.sender, payout);
        if (stethFirst) {
            _payoutWithEthFallback(player, payout);
        } else {
            _payoutWithStethFallback(player, payout);
        }
    }

    /// @notice Claim DGNRS affiliate rewards for the current level.
    /// @dev Requires a minimum affiliate score and allows one claim per level.
    ///      Draws from a segregated allocation (5% of the affiliate pool snapshotted
    ///      at level transition). All claimants for the same level share a fixed pot,
    ///      eliminating first-mover advantage. Uses totalAffiliateScore as the exact
    ///      denominator for score-proportional distribution.
    ///      Affiliate scores always route to level + 1 during gameplay, so at
    ///      transition time all scores for currLevel are frozen and immutable.
    /// @param player Affiliate address to claim for (address(0) = msg.sender).
    function claimAffiliateDgnrs(address player) external {
        player = _resolvePlayer(player);

        uint24 currLevel = level;
        if (currLevel == 0) revert E();

        if (affiliateDgnrsClaimedBy[currLevel][player]) revert E();

        uint256 score = affiliate.affiliateScore(currLevel, player);
        bool hasDeityPass = deityPassCount[player] != 0;
        if (!hasDeityPass && score < AFFILIATE_DGNRS_MIN_SCORE) revert E();

        uint256 denominator = affiliate.totalAffiliateScore(currLevel);
        if (denominator == 0) revert E();

        uint256 allocation = levelDgnrsAllocation[currLevel];
        if (allocation == 0) revert E();
        uint256 reward = (allocation * score) / denominator;
        if (reward == 0) revert E();

        uint256 paid = dgnrs.transferFromPool(
            IStakedDegenerusStonk.Pool.Affiliate,
            player,
            reward
        );
        if (paid == 0) revert E();

        levelDgnrsClaimed[currLevel] += paid;

        if (hasDeityPass && score != 0) {
            uint256 bonus = (score * AFFILIATE_DGNRS_DEITY_BONUS_BPS) / 10_000;
            uint256 cap = (AFFILIATE_DGNRS_DEITY_BONUS_CAP_ETH *
                PRICE_COIN_UNIT) / price;
            if (bonus > cap) {
                bonus = cap;
            }
            if (bonus != 0) {
                coin.creditFlip(player, bonus);
            }
        }

        affiliateDgnrsClaimedBy[currLevel][player] = true;
        emit AffiliateDgnrsClaimed(player, currLevel, msg.sender, score, paid);
    }

    /*+======================================================================+
      |                    AUTO-REBUY TOGGLE                                |
      +======================================================================+*/

    /// @notice Emitted when a player toggles auto-rebuy on or off.
    event AutoRebuyToggled(address indexed player, bool enabled);

    /// @notice Emitted when a player toggles decimator auto-rebuy on or off.
    event DecimatorAutoRebuyToggled(address indexed player, bool enabled);

    /// @notice Emitted when a player sets the auto-rebuy take profit.
    event AutoRebuyTakeProfitSet(address indexed player, uint256 takeProfit);

    /// @notice Emitted when a player toggles afKing mode on or off.
    event AfKingModeToggled(address indexed player, bool enabled);

    /// @notice Enable or disable auto-rebuy for claimable winnings.
    /// @dev When enabled, the remainder (after reserving take profit) is
    ///      converted to tickets for next level or next+1 (50/50) during jackpot award flow.
    ///      ETH goes to nextPrizePool for next-level tickets, or futurePrizePool for next+1.
    ///
    ///      BONUS: Applies fixed ticket bonus for auto-rebuy:
    ///      - 30% default (13000 bps)
    ///      - 45% when afKing mode is active (14500 bps)
    ///
    /// @param player Player address to configure (address(0) = msg.sender).
    /// @param enabled True to enable auto-rebuy, false to disable.
    function setAutoRebuy(address player, bool enabled) external {
        player = _resolvePlayer(player);
        _setAutoRebuy(player, enabled);
    }

    /// @notice Enable or disable auto-rebuy for decimator claims.
    /// @dev Default is enabled.
    /// @param player Player address to configure (address(0) = msg.sender).
    /// @param enabled True to enable auto-rebuy for decimator claims, false to disable.
    function setDecimatorAutoRebuy(address player, bool enabled) external {
        player = _resolvePlayer(player);
        if (rngLockedFlag) revert RngLocked();
        bool disabled = !enabled;
        if (decimatorAutoRebuyDisabled[player] != disabled) {
            decimatorAutoRebuyDisabled[player] = disabled;
        }
        emit DecimatorAutoRebuyToggled(player, enabled);
    }

    /// @notice Set the auto-rebuy take profit (amount reserved for manual claim).
    /// @dev Complete multiples remain claimable; remainder is eligible for auto-rebuy.
    /// @param player Player address to configure (address(0) = msg.sender).
    /// @param takeProfit Amount in wei; 0 means no reservation (rebuy all).
    function setAutoRebuyTakeProfit(
        address player,
        uint256 takeProfit
    ) external {
        player = _resolvePlayer(player);
        _setAutoRebuyTakeProfit(player, takeProfit);
    }

    function _setAutoRebuy(address player, bool enabled) private {
        if (rngLockedFlag) revert RngLocked();
        AutoRebuyState storage state = autoRebuyState[player];
        if (state.autoRebuyEnabled != enabled) {
            state.autoRebuyEnabled = enabled;
        }
        emit AutoRebuyToggled(player, enabled);
        if (!enabled) {
            _deactivateAfKing(player);
        }
    }

    function _setAutoRebuyTakeProfit(
        address player,
        uint256 takeProfit
    ) private {
        if (rngLockedFlag) revert RngLocked();
        AutoRebuyState storage state = autoRebuyState[player];
        uint128 takeProfitValue = uint128(takeProfit);
        if (state.takeProfit != takeProfitValue) {
            state.takeProfit = takeProfitValue;
        }
        emit AutoRebuyTakeProfitSet(player, takeProfit);
        if (takeProfit != 0 && takeProfit < AFKING_KEEP_MIN_ETH) {
            _deactivateAfKing(player);
        }
    }

    /// @notice Check if auto-rebuy is enabled for a player.
    /// @param player Player address to check.
    /// @return enabled True if auto-rebuy is enabled for this player.
    function autoRebuyEnabledFor(
        address player
    ) external view returns (bool enabled) {
        return autoRebuyState[player].autoRebuyEnabled;
    }

    /// @notice Check if decimator auto-rebuy is enabled for a player.
    /// @param player Player address to check.
    /// @return enabled True if decimator auto-rebuy is enabled for this player.
    function decimatorAutoRebuyEnabledFor(
        address player
    ) external view returns (bool enabled) {
        return !decimatorAutoRebuyDisabled[player];
    }

    /// @notice Check the auto-rebuy take profit for a player.
    /// @param player Player address to check.
    /// @return takeProfit Amount reserved as complete multiples (wei).
    function autoRebuyTakeProfitFor(
        address player
    ) external view returns (uint256 takeProfit) {
        return autoRebuyState[player].takeProfit;
    }

    /// @notice Enable or disable afKing mode.
    /// @dev Enabling afKing forces auto-rebuy on for ETH and coin and clamps take profit
    ///      to minimums (5 ETH / 20k BURNIE) unless set to 0. Requires a lazy pass.
    /// @param player Player address to configure (address(0) = msg.sender).
    /// @param enabled True to enable afKing mode, false to disable.
    /// @param ethTakeProfit Desired ETH take profit (wei).
    /// @param coinTakeProfit Desired coin take profit (BURNIE, 18 decimals).
    /// @custom:reverts RngLocked If RNG is locked.
    /// @custom:reverts E If enabling without a lazy pass.
    /// @custom:reverts AfKingLockActive If disabling during lock period.
    function setAfKingMode(
        address player,
        bool enabled,
        uint256 ethTakeProfit,
        uint256 coinTakeProfit
    ) external {
        player = _resolvePlayer(player);
        _setAfKingMode(player, enabled, ethTakeProfit, coinTakeProfit);
    }

    function _setAfKingMode(
        address player,
        bool enabled,
        uint256 ethTakeProfit,
        uint256 coinTakeProfit
    ) private {
        if (rngLockedFlag) revert RngLocked();
        if (!enabled) {
            _deactivateAfKing(player);
            return;
        }
        if (!_hasAnyLazyPass(player)) revert E();

        AutoRebuyState storage state = autoRebuyState[player];
        uint256 adjustedEthKeep = ethTakeProfit;
        if (adjustedEthKeep != 0 && adjustedEthKeep < AFKING_KEEP_MIN_ETH) {
            adjustedEthKeep = AFKING_KEEP_MIN_ETH;
        }
        uint256 adjustedCoinKeep = coinTakeProfit;
        if (adjustedCoinKeep != 0 && adjustedCoinKeep < AFKING_KEEP_MIN_COIN) {
            adjustedCoinKeep = AFKING_KEEP_MIN_COIN;
        }

        if (!state.autoRebuyEnabled) {
            state.autoRebuyEnabled = true;
            emit AutoRebuyToggled(player, true);
        }
        if (state.takeProfit != adjustedEthKeep) {
            state.takeProfit = uint128(adjustedEthKeep);
            emit AutoRebuyTakeProfitSet(player, adjustedEthKeep);
        }
        coinflip.setCoinflipAutoRebuy(player, true, adjustedCoinKeep);

        if (!state.afKingMode) {
            coinflip.settleFlipModeChange(player);
            state.afKingMode = true;
            state.afKingActivatedLevel = level;
            emit AfKingModeToggled(player, true);
        }
    }

    function _hasAnyLazyPass(address player) private view returns (bool) {
        if (deityPassCount[player] != 0) return true;

        uint24 frozenUntilLevel = uint24(
            (mintPacked_[player] >> BitPackingLib.FROZEN_UNTIL_LEVEL_SHIFT) &
                BitPackingLib.MASK_24
        );
        return frozenUntilLevel > level;
    }

    /// @notice Check if player has an active lazy pass.
    /// @param player Player address to check.
    /// @return True if player has frozenUntilLevel > current level OR deity pass.
    function hasActiveLazyPass(address player) external view returns (bool) {
        if (deityPassCount[player] != 0) return true;
        uint24 frozenUntilLevel = uint24(
            (mintPacked_[player] >> BitPackingLib.FROZEN_UNTIL_LEVEL_SHIFT) &
                BitPackingLib.MASK_24
        );
        return frozenUntilLevel > level;
    }

    /// @notice Check if afKing mode is active for a player.
    /// @param player Player address to check.
    /// @return active True if afKing mode is active.
    function afKingModeFor(address player) external view returns (bool active) {
        return autoRebuyState[player].afKingMode;
    }

    /// @notice Get the level when afKing mode was activated for a player.
    /// @param player Player address to check.
    /// @return activationLevel Level at which afKing mode was enabled (0 if inactive).
    function afKingActivatedLevelFor(
        address player
    ) external view returns (uint24 activationLevel) {
        return autoRebuyState[player].afKingActivatedLevel;
    }

    /// @notice Deactivate afKing mode for a player (coin/coinflip hook).
    /// @dev Access: COIN or COINFLIP contract only.
    /// @param player Player to deactivate.
    /// @custom:reverts E If caller is not COIN or COINFLIP contract.
    function deactivateAfKingFromCoin(address player) external {
        if (
            msg.sender != ContractAddresses.COIN &&
            msg.sender != ContractAddresses.COINFLIP
        ) revert E();
        _deactivateAfKing(player);
    }

    /// @notice Sync afKing lazy pass status and revoke if inactive (coinflip-only hook).
    /// @dev Access: COINFLIP contract only.
    /// @param player Player to sync.
    /// @return active True if afKing remains active after sync.
    /// @custom:reverts E If caller is not COINFLIP contract.
    function syncAfKingLazyPassFromCoin(
        address player
    ) external returns (bool active) {
        if (msg.sender != ContractAddresses.COINFLIP) revert E();
        AutoRebuyState storage state = autoRebuyState[player];
        if (!state.afKingMode) return false;
        if (_hasAnyLazyPass(player)) return true;

        // Note: settle not called here - it's already being called by the coinflip
        // operation that triggered this sync (deposit/claim calls _syncAfKingLazyPass)
        state.afKingMode = false;
        state.afKingActivatedLevel = 0;
        emit AfKingModeToggled(player, false);
        return false;
    }

    function _deactivateAfKing(address player) private {
        AutoRebuyState storage state = autoRebuyState[player];
        if (!state.afKingMode) return;
        uint24 activationLevel = state.afKingActivatedLevel;
        if (activationLevel != 0) {
            uint256 unlockLevel = uint256(activationLevel) + AFKING_LOCK_LEVELS;
            if (uint256(level) < unlockLevel) revert AfKingLockActive();
        }
        coinflip.settleFlipModeChange(player);
        state.afKingMode = false;
        state.afKingActivatedLevel = 0;
        emit AfKingModeToggled(player, false);
    }

    /*+======================================================================+
      |                    LOOTBOX CLAIMS                                   |
      +======================================================================+*/

    /// @notice Claim deferred whale pass rewards from large lootbox wins (>5 ETH).
    /// @dev Unified claim function for all large lootbox rewards.
    ///      Delegates to endgame module which uses whale pass pricing.
    /// @param player Player address to claim for (address(0) = msg.sender).
    function claimWhalePass(address player) external {
        player = _resolvePlayer(player);
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

    /*+======================================================================+
      |                    REDEMPTION LOOTBOX                               |
      +======================================================================+*/

    /// @notice Resolve redemption lootboxes for an sDGNRS gambling burn claim.
    /// @dev Called by sDGNRS during claimRedemption. Reclassifies ETH from sDGNRS's
    ///      claimableWinnings into futurePrizePool (no ETH transfer — internal accounting only).
    ///      Splits into 5 ETH boxes and resolves each via lootbox module delegatecall.
    /// @param player Player receiving lootbox rewards
    /// @param amount Total lootbox ETH amount to resolve
    /// @param rngWord RNG entropy for lootbox resolution
    /// @param activityScore Snapshotted activity score (bps) from burn submission
    function resolveRedemptionLootbox(
        address player,
        uint256 amount,
        uint256 rngWord,
        uint16 activityScore
    ) external {
        if (msg.sender != ContractAddresses.SDGNRS) revert E();
        if (amount == 0) return;

        // Debit from sDGNRS's claimable (ETH stays in Game's balance).
        // SAFETY: unchecked is safe because the only path that drains claimableWinnings[SDGNRS]
        // is _deterministicBurnFrom → game.claimWinnings(), which only fires at gameOver.
        // This function is only called during active game (lootboxEth = 0 when gameOver).
        // The two paths are mutually exclusive, so claimable >= amount always holds here.
        uint256 claimable = claimableWinnings[ContractAddresses.SDGNRS];
        unchecked {
            claimableWinnings[ContractAddresses.SDGNRS] = claimable - amount;
        }
        claimablePool -= amount;

        // Credit to future prize pool (respects freeze state)
        if (prizePoolFrozen) {
            (uint128 pNext, uint128 pFuture) = _getPendingPools();
            _setPendingPools(pNext, pFuture + uint128(amount));
        } else {
            (uint128 next, uint128 future) = _getPrizePools();
            _setPrizePools(next, future + uint128(amount));
        }

        // Resolve lootboxes in 5 ETH chunks via delegatecall to lootbox module
        uint256 remaining = amount;
        while (remaining != 0) {
            uint256 box = remaining > 5 ether ? 5 ether : remaining;
            (bool ok, bytes memory data) = ContractAddresses
                .GAME_LOOTBOX_MODULE
                .delegatecall(
                    abi.encodeWithSelector(
                        IDegenerusGameLootboxModule
                            .resolveRedemptionLootbox
                            .selector,
                        player,
                        box,
                        rngWord,
                        activityScore
                    )
                );
            if (!ok) _revertDelegate(data);
            remaining -= box;
            rngWord = uint256(keccak256(abi.encode(rngWord)));
        }
    }

    /*+===============================================================================================+
      |                    JACKPOT PAYOUT FUNCTIONS                                                   |
      +===============================================================================================+
      |  Functions for distributing jackpot winnings. Most jackpot logic                              |
      |  lives in the ContractAddresses.GAME_JACKPOT_MODULE (via delegatecall).                       |
      |                                                                                               |
      |  Jackpot Types:                                                                               |
      |  • Daily jackpot - Paid each day to burn ticket holders (day 5 = full pool payout)             |
      |  • Decimator - Special 100-level milestone jackpot (30% of pool)                              |
      |  • BAF - Big-ass-flip jackpot (20% of pool at L%100=0)                                        |
      +===============================================================================================+*/

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

    /// @notice Admin-only swap: caller sends ETH in and receives game-held stETH.
    /// @dev Used to rebalance when stETH yield should be converted to ETH.
    ///      Admin must send exact ETH amount equal to stETH received.
    ///      SECURITY: Value-neutral swap, ADMIN cannot extract funds.
    /// @param recipient Address to receive stETH.
    /// @param amount ETH amount to swap (must match msg.value).
    /// @custom:reverts E If caller is not ADMIN, recipient is zero, amount is zero,
    ///                   msg.value doesn't match amount, or insufficient stETH balance.
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
    ///      SECURITY: Must retain ETH to cover player claims, excluding vault/DGNRS
    ///      claimable (those addresses accept stETH payouts natively).
    /// @param amount ETH amount to stake.
    /// @custom:reverts E If caller is not ADMIN, amount is zero, insufficient ETH,
    ///                   or staking would dip into player-claim ETH reserve.
    function adminStakeEthForStEth(uint256 amount) external {
        if (msg.sender != ContractAddresses.ADMIN) revert E();
        if (amount == 0) revert E();

        uint256 ethBal = address(this).balance;
        if (ethBal < amount) revert E();
        // Vault and DGNRS claimable can be settled in stETH, so exclude from ETH reserve
        uint256 stethSettleable = claimableWinnings[ContractAddresses.VAULT] +
            claimableWinnings[ContractAddresses.SDGNRS];
        uint256 reserve = claimablePool > stethSettleable
            ? claimablePool - stethSettleable
            : 0;
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
      |  1. advanceGame() calls rngGate()                                    |
      |  2. If no valid RNG word, _requestRng() is called                    |
      |  3. Chainlink calls rawFulfillRandomWords() with random word         |
      |  4. Next advanceGame() uses the fulfilled word                       |
      |  5. After processing, _unlockRng() resets for next cycle             |
      |                                                                      |
      |  SECURITY:                                                           |
      |  • RNG lock prevents state manipulation during VRF window            |
      |  • 12-hour timeout allows recovery from stale requests               |
      |  • Governance-gated coordinator rotation via Admin                   |
      |  • Nudge system allows players to influence (not predict) RNG        |
      +======================================================================+*/

    /// @notice Emergency VRF coordinator rotation (governance-gated).
    /// @dev Access: ADMIN only. Stall duration enforced by Admin governance.
    /// @param newCoordinator New VRF coordinator address.
    /// @param newSubId New subscription ID.
    /// @param newKeyHash New key hash for the gas lane.
    /// @custom:reverts E If caller is not ADMIN.
    function updateVrfCoordinatorAndSub(
        address newCoordinator,
        uint256 newSubId,
        bytes32 newKeyHash
    ) external {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_ADVANCE_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameAdvanceModule
                        .updateVrfCoordinatorAndSub
                        .selector,
                    newCoordinator,
                    newSubId,
                    newKeyHash
                )
            );
        if (!ok) _revertDelegate(data);
    }

    /// @notice Request lootbox RNG when activity threshold and LINK conditions are met.
    /// @dev Callable by anyone. Reverts if daily RNG has not been consumed, if request
    ///      windows are locked, or if pending lootbox value is below threshold.
    function requestLootboxRng() external {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_ADVANCE_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameAdvanceModule.requestLootboxRng.selector
                )
            );
        if (!ok) _revertDelegate(data);
    }

    /// @notice Pay BURNIE to nudge the next RNG word by +1.
    /// @dev Cost scales +50% per queued nudge and resets after fulfillment.
    ///      Only available while RNG is unlocked (before VRF request is in-flight).
    ///      MECHANISM: Adds 1 to the VRF word for each nudge, changing outcomes.
    ///      SECURITY: Players cannot predict the base word, only influence it.
    /// @custom:reverts RngLocked If RNG is currently locked (VRF request pending).
    function reverseFlip() external {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_ADVANCE_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameAdvanceModule.reverseFlip.selector
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

    function _transferSteth(address to, uint256 amount) private {
        if (amount == 0) return;
        if (to == ContractAddresses.SDGNRS) {
            if (!steth.approve(ContractAddresses.SDGNRS, amount)) revert E();
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

    /// @notice Get the next-pool ratchet target for level progression.
    /// @dev Returns the pre-skim nextPrizePool captured at the previous level
    ///      transition. The current level must accumulate at least this much
    ///      in nextPrizePool to trigger lastPurchaseDay.
    ///      Threshold check uses levelPrizePool[purchaseLevel - 1] = levelPrizePool[level].
    /// @return The ratchet target value (ETH wei).
    function prizePoolTargetView() external view returns (uint256) {
        uint256 pool = levelPrizePool[level];
        return pool != 0 ? pool : BOOTSTRAP_PRIZE_POOL;
    }

    /// @notice Get the prize pool accumulated for the next level.
    /// @dev Mint fees flow into nextPrizePool until target is met.
    /// @return The nextPrizePool value (ETH wei).
    function nextPrizePoolView() external view returns (uint256) {
        return _getNextPrizePool();
    }

    /// @notice Get the unified future pool reserve.
    /// @return The futurePrizePool value (ETH wei).
    function futurePrizePoolView() external view returns (uint256) {
        return _getFuturePrizePool();
    }

    /// @notice Get the aggregate future pool reserve.
    /// @return The futurePrizePool value (ETH wei).
    function futurePrizePoolTotalView() external view returns (uint256) {
        return _getFuturePrizePool();
    }

    /// @notice Get queued future ticket rewards owed for a level.
    /// @param lvl Target level for the queued tickets.
    /// @param player Player address to query.
    /// @return The number of whole ticket rewards owed (fractional remainder resolves at batch time).
    function ticketsOwedView(
        uint24 lvl,
        address player
    ) external view returns (uint32) {
        return uint32(ticketsOwedPacked[_tqWriteKey(lvl)][player] >> 8);
    }

    /// @notice Get loot box status for a player/index.
    /// @param player Player address to query.
    /// @param lootboxIndex Lootbox RNG index assigned at purchase time.
    /// @return amount ETH amount recorded for the loot box (wei).
    /// @return presale True if presale mode is currently active.
    function lootboxStatus(
        address player,
        uint48 lootboxIndex
    ) external view returns (uint256 amount, bool presale) {
        // Direct storage access - lootboxEth stores packed amount in lower 232 bits
        uint256 packed = lootboxEth[lootboxIndex][player];
        amount = packed & ((1 << 232) - 1);
        presale = lootboxPresaleActive;
    }

    /// @notice View Degenerette packed bet info for a player/betId.
    /// @param player Player address to query.
    /// @param betId Bet identifier for the player.
    function degeneretteBetInfo(
        address player,
        uint64 betId
    ) external view returns (uint256 packed) {
        return degeneretteBets[player][betId];
    }

    /// @notice Check whether lootbox presale mode is currently active.
    /// @return active True if presale is active.
    function lootboxPresaleActiveFlag() external view returns (bool active) {
        return lootboxPresaleActive;
    }

    /// @notice Get the current lootbox RNG index for new purchases.
    /// @return index The current lootbox RNG index (1-based).
    function lootboxRngIndexView() external view returns (uint48 index) {
        return lootboxRngIndex;
    }

    /// @notice Get the VRF random word for a lootbox RNG index.
    /// @param lootboxIndex Lootbox RNG index to query.
    /// @return word VRF word (0 if not ready).
    function lootboxRngWord(
        uint48 lootboxIndex
    ) external view returns (uint256 word) {
        return lootboxRngWordByIndex[lootboxIndex];
    }

    /// @notice Get the lootbox RNG request threshold (wei).
    /// @return threshold The ETH threshold that triggers a lootbox RNG request.
    function lootboxRngThresholdView()
        external
        view
        returns (uint256 threshold)
    {
        return lootboxRngThreshold;
    }

    /// @notice Get minimum LINK balance required for manual lootbox RNG rolls.
    /// @return minBalance The minimum LINK balance required.
    function lootboxRngMinLinkBalanceView()
        external
        view
        returns (uint256 minBalance)
    {
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
        return _getFuturePrizePool();
    }

    /// @notice Get the claimable pool (reserved for player winnings claims).
    /// @return The claimablePool value (ETH wei).
    function claimablePoolView() external view returns (uint256) {
        if (finalSwept) return 0;
        return claimablePool;
    }

    /// @notice Check if the final sweep has executed (all funds forfeited).
    function isFinalSwept() external view returns (bool) {
        return finalSwept;
    }

    /// @notice Timestamp when gameover was triggered (0 if game still active).
    function gameOverTimestamp() external view returns (uint48) {
        return gameOverTime;
    }

    /// @notice Get the yield surplus (stETH appreciation above all pool obligations).
    /// @dev Calculated as: (ETH balance + stETH balance) - (current + next + claimable + future pools)
    /// @return The yield surplus value (ETH wei).
    function yieldPoolView() external view returns (uint256) {
        uint256 totalBalance = address(this).balance +
            steth.balanceOf(address(this));
        uint256 obligations = currentPrizePool +
            _getNextPrizePool() +
            claimablePool +
            _getFuturePrizePool() +
            yieldAccumulator;
        if (totalBalance <= obligations) return 0;
        return totalBalance - obligations;
    }

    /// @notice Get the yield accumulator balance (segregated stETH yield reserve).
    /// @return The yield accumulator balance (ETH wei).
    function yieldAccumulatorView() external view returns (uint256) {
        return yieldAccumulator;
    }

    /// @notice Get the current mint price in wei.
    /// @dev Price tiers: intro 0.01/0.02, then cycle 0.04/0.08/0.12/0.16/0.24 ETH.
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
    /// @return The random word for the most recent day (0 if none).
    function lastRngWord() external view returns (uint256) {
        return rngWordByDay[dailyIdx];
    }

    /// @notice Check if RNG is currently locked (daily jackpot resolution).
    /// @dev When locked, burns and certain operations are blocked.
    /// @return True if RNG lock is active.
    function rngLocked() external view returns (bool) {
        return rngLockedFlag;
    }

    /// @notice Check if VRF has been fulfilled for current request.
    /// @return True if random word is available for use.
    function isRngFulfilled() external view returns (bool) {
        return rngWordCurrent != 0;
    }

    /// @dev Check if there's a 3-consecutive-day gap in VRF words.
    ///      Used to detect VRF coordinator failures requiring emergency rotation.
    /// @param day The day index to check from.
    /// @return True if day, day-1, and day-2 all have no recorded VRF word.
    function _threeDayRngGap(uint48 day) private view returns (bool) {
        if (rngWordByDay[day] != 0) return false;
        if (rngWordByDay[day - 1] != 0) return false;
        if (day < 2 || rngWordByDay[day - 2] != 0) return false;
        return true;
    }

    /// @notice Check if VRF has stalled for 3 consecutive days.
    /// @dev Retained for monitoring/external use. Governance uses lastVrfProcessed() instead.
    /// @return True if no VRF word has been recorded for the last 3 day slots.
    function rngStalledForThreeDays() external view returns (bool) {
        return _threeDayRngGap(_simulatedDayIndex());
    }

    /// @notice Timestamp of the last successfully processed VRF word.
    /// @dev Used by governance contracts to detect VRF stalls (time-based).
    function lastVrfProcessed() external view returns (uint48) {
        return lastVrfProcessedTimestamp;
    }

    /*+======================================================================+
      |                   VIEW: DECIMATOR & PURCHASE INFO                    |
      +======================================================================+
      |  Status views for decimator window and purchase state.               |
      +======================================================================+*/

    /// @notice Check if decimator window is open and accessible.
    /// @dev Window is "on" if flag is set or gameover is imminent.
    ///      RNG lock only blocks during lastPurchaseDay (when jackpots resolve).
    ///      For x5 levels, window closes before lastPurchaseDay, so gate is redundant.
    ///      For x00 levels, window stays open until lastPurchaseDay, so gate is needed.
    /// @return on True if decimator entries are currently allowed.
    /// @return lvl Current game level.
    function decWindow() external view returns (bool on, uint24 lvl) {
        lvl = level;
        on =
            (decWindowOpen || _isGameoverImminent()) &&
            !(lastPurchaseDay && rngLockedFlag);
    }

    /// @notice Raw check of decimator window flag (ignores RNG lock).
    /// @return open True if decimator window flag is set or gameover is imminent.
    function decWindowOpenFlag() external view returns (bool open) {
        return decWindowOpen || _isGameoverImminent();
    }

    /// @notice Jackpot compression tier: 0=normal, 1=compressed (3d), 2=turbo (1d).
    function jackpotCompressionTier() external view returns (uint8) {
        return compressedJackpotFlag;
    }

    /// @dev True when gameover would trigger within ~5 days.
    ///      Used to allow decimator burns near liveness timeout.
    function _isGameoverImminent() private view returns (bool) {
        if (gameOver) return false;
        uint48 lst = levelStartTime;
        uint48 ts = uint48(block.timestamp);

        if (level == 0) {
            return
                uint256(ts) + 10 days >
                uint256(lst) + uint256(DEPLOY_IDLE_TIMEOUT_DAYS) * 1 days;
        }
        return uint256(ts) + 5 days > uint256(lst) + 120 days;
    }

    /// @dev Returns the active ticket level for direct ticket purchases.
    ///      During jackpot phase, direct tickets target the current level.
    ///      During purchase phase, direct tickets target the next level.
    function _activeTicketLevel() private view returns (uint24) {
        return jackpotPhaseFlag ? level : level + 1;
    }

    /// @notice Returns true when jackpot phase is active.
    function jackpotPhase() external view returns (bool) {
        return jackpotPhaseFlag;
    }

    /// @notice Comprehensive purchase info for UI consumption.
    /// @dev Bundles level, state, flags, and price into single call.
    ///      NOTE: lvl is the active direct-ticket level.
    /// @return lvl Active direct-ticket level.
    /// @return inJackpotPhase True if jackpot phase is active.
    /// @return lastPurchaseDay_ True if prize pool target is met.
    /// @return rngLocked_ True if VRF request is pending.
    /// @return priceWei Current mint price in wei.
    function purchaseInfo()
        external
        view
        returns (
            uint24 lvl,
            bool inJackpotPhase,
            bool lastPurchaseDay_,
            bool rngLocked_,
            uint256 priceWei
        )
    {
        inJackpotPhase = jackpotPhaseFlag;
        lastPurchaseDay_ = (!inJackpotPhase) && lastPurchaseDay;
        lvl = _activeTicketLevel();
        rngLocked_ = rngLockedFlag;
        priceWei = price;
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
                (mintPacked_[player] >> BitPackingLib.LAST_LEVEL_SHIFT) &
                    BitPackingLib.MASK_24
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
                (mintPacked_[player] >> BitPackingLib.LEVEL_COUNT_SHIFT) &
                    BitPackingLib.MASK_24
            );
    }

    /// @notice Get player's current consecutive ETH mint streak.
    /// @param player The player address to query.
    /// @return Number of consecutive levels with ETH mints.
    function ethMintStreakCount(address player) external view returns (uint24) {
        if (deityPassCount[player] != 0) {
            return level;
        }
        return _mintStreakEffective(player, _activeTicketLevel());
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
        levelCount = uint24(
            (packed >> BitPackingLib.LEVEL_COUNT_SHIFT) & BitPackingLib.MASK_24
        );
        streak = _mintStreakEffective(player, _activeTicketLevel());
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
      +======================================================================+*/

    /// @notice Calculate player's activity score in basis points.
    /// @dev Activity Score: 50% (streak) + 25% (count) + 100% (quest) + 50% (affiliate) + 40% (whale) = 265% max
    ///      Deity pass adds +80% in place of whale bundle bonus (305% max base).
    ///      Consumers apply their own caps (lootbox EV: 255%, degenerette ROI: 305%, decimator: 235%).
    /// @param player The player address to calculate for.
    /// @return scoreBps Total activity score in basis points.
    function playerActivityScore(
        address player
    ) external view returns (uint256 scoreBps) {
        return _playerActivityScore(player);
    }

    function _playerActivityScore(
        address player
    ) internal view returns (uint256 scoreBps) {
        if (player == address(0)) return 0;

        bool hasDeityPass = deityPassCount[player] != 0;
        uint256 packed = mintPacked_[player];
        uint24 levelCount = uint24(
            (packed >> BitPackingLib.LEVEL_COUNT_SHIFT) & BitPackingLib.MASK_24
        );
        uint24 streak = _mintStreakEffective(player, _activeTicketLevel());
        uint24 currLevel = level;
        uint24 frozenUntilLevel = uint24(
            (packed >> BitPackingLib.FROZEN_UNTIL_LEVEL_SHIFT) &
                BitPackingLib.MASK_24
        );
        uint8 bundleType = uint8(
            (packed >> BitPackingLib.WHALE_BUNDLE_TYPE_SHIFT) & 3
        );
        bool passActive = frozenUntilLevel > currLevel &&
            (bundleType == 1 || bundleType == 3);

        uint256 bonusBps;

        unchecked {
            if (hasDeityPass) {
                bonusBps = 50 * 100;
                bonusBps += 25 * 100;
            } else {
                // Mint streak: 1% per consecutive level minted, max 50%
                uint256 streakPoints = streak > 50 ? 50 : uint256(streak);
                // Mint count bonus: 1% each
                uint256 mintCountPoints = _mintCountBonusPoints(
                    levelCount,
                    currLevel
                );
                // Active pass = full participation credit (always had pass active)
                if (passActive) {
                    if (streakPoints < PASS_STREAK_FLOOR_POINTS) {
                        streakPoints = PASS_STREAK_FLOOR_POINTS;
                    }
                    if (mintCountPoints < PASS_MINT_COUNT_FLOOR_POINTS) {
                        mintCountPoints = PASS_MINT_COUNT_FLOOR_POINTS;
                    }
                }
                bonusBps = streakPoints * 100;
                bonusBps += mintCountPoints * 100;
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

            if (hasDeityPass) {
                bonusBps += DEITY_PASS_ACTIVITY_BONUS_BPS;
            } else if (frozenUntilLevel > currLevel) {
                // Whale pass bonus: varies by bundle type (only active while frozen)
                if (bundleType == 1) {
                    bonusBps += 1000; // +10% for 10-level bundle
                } else if (bundleType == 3) {
                    bonusBps += 4000; // +40% for 100-level bundle
                }
            }
        }

        scoreBps = bonusBps;
    }

    /// @dev Calculate mint count bonus points (max 25% for perfect participation).
    ///      Perfect participation (100% mints) always = 25 points (25%).
    ///      Level 2 with 2 mints (100%): 25 points
    ///      Level 10 with 10 mints (100%): 25 points
    ///      Level 10 with 7 mints (70%): (7 * 25) / 10 = 17 points
    ///      Level 30 with 30 mints (100%): 25 points
    /// @param mintCount Player's total level mint count.
    /// @param currLevel Current game level.
    /// @return Bonus points (0-25) scaled by participation percentage (integer division).
    function _mintCountBonusPoints(
        uint24 mintCount,
        uint24 currLevel
    ) private pure returns (uint256) {
        if (currLevel == 0) return 0;

        // Perfect participation (mintCount >= currLevel) = 25 points
        if (mintCount >= currLevel) return 25;

        // Otherwise: (mintCount * 25) / currLevel (truncates)
        // Example: level 10, 7 mints = (7 * 25) / 10 = 17 points
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
        if (finalSwept) return 0;
        uint256 stored = claimableWinnings[msg.sender];
        if (stored <= 1) return 0;
        unchecked {
            return stored - 1;
        }
    }

    /// @notice Get a player's raw claimable balance (includes the 1 wei sentinel).
    /// @param player Player address to query.
    /// @return Raw claimable balance in wei (includes 1 wei sentinel if any balance exists).
    function claimableWinningsOf(
        address player
    ) external view returns (uint256) {
        if (finalSwept) return 0;
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

    /// @notice Get deity pass count purchased via presale bundle for a player.
    /// @param player Player address to query.
    /// @return Count of presale-purchased deity passes.
    function deityPassPurchasedCountFor(
        address player
    ) external view returns (uint16) {
        return deityPassPurchasedCount[player];
    }

    /// @notice Get total deity passes issued across all sources.
    /// @return count Total count (capped at 32).
    function deityPassTotalIssuedCount() external view returns (uint32 count) {
        return uint32(deityPassOwners.length);
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

    /// @notice Sample up to 4 trait burn tickets from a specific level.
    /// @dev Simplified variant of sampleTraitTickets for targeted level sampling.
    ///      Used by BAF scatter to sample the next level's ticket holders.
    /// @param targetLvl The level to sample from.
    /// @param entropy Random seed (typically VRF word) for trait and offset selection.
    /// @return traitSel Selected trait ID.
    /// @return tickets Array of up to 4 ticket holder addresses.
    function sampleTraitTicketsAtLevel(
        uint24 targetLvl,
        uint256 entropy
    ) external view returns (uint8 traitSel, address[] memory tickets) {
        traitSel = uint8(entropy >> 24);
        address[] storage arr = traitBurnTicket[targetLvl][traitSel];
        uint256 len = arr.length;
        if (len == 0) {
            return (traitSel, new address[](0));
        }

        uint256 take = len > 4 ? 4 : len;
        tickets = new address[](take);
        uint256 start = (entropy >> 40) % len;
        for (uint256 i; i < take; ) {
            tickets[i] = arr[(start + i) % len];
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Sample up to 4 far-future ticket holders from ticketQueue.
    /// @dev View function for BAF far-future selection; samples levels [current+5, current+99].
    ///      Tries up to 10 random levels, returns however many non-zero holders are found (max 4).
    /// @param entropy Random entropy for sampling (typically from VRF).
    /// @return tickets Array of player addresses (length 0-4).
    function sampleFarFutureTickets(
        uint256 entropy
    ) external view returns (address[] memory tickets) {
        uint24 currentLvl = level;
        address[4] memory tmp;
        uint8 found;
        uint256 word = entropy;

        for (uint8 s; s < 10 && found < 4; ) {
            word = uint256(keccak256(abi.encodePacked(word, s)));
            uint24 candidate = currentLvl + 5 + uint24(word % 95);

            address[] storage queue = ticketQueue[_tqFarFutureKey(candidate)];
            uint256 len = queue.length;
            if (len != 0) {
                uint256 idx = (word >> 32) % len;
                address winner = queue[idx];
                if (winner != address(0)) {
                    tmp[found] = winner;
                    unchecked {
                        ++found;
                    }
                }
            }
            unchecked {
                ++s;
            }
        }

        tickets = new address[](found);
        for (uint8 i; i < found; ) {
            tickets[i] = tmp[i];
            unchecked {
                ++i;
            }
        }
    }

    /*+======================================================================+
      |                    VIEW: TRAIT TICKET QUERIES                         |
      +======================================================================+
      |  Read-only functions for querying trait state and game history.      |
      +======================================================================+*/

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

    /// @notice Get tickets owed to a player for the current level.
    /// @param player The player address.
    /// @return tickets Number of tickets owed for current level.
    function getPlayerPurchases(
        address player
    ) external view returns (uint32 tickets) {
        tickets = uint32(ticketsOwedPacked[_tqWriteKey(level)][player] >> 8);
    }

    /*+======================================================================+
      |                    DEGENERETTE TRACKING VIEWS                        |
      +======================================================================+*/

    /// @notice Get daily hero wager for a specific quadrant/symbol on a given day.
    /// @param day Day index (from GameTimeLib).
    /// @param quadrant Quadrant (0-3).
    /// @param symbol Symbol index within quadrant (0-7).
    /// @return wagerUnits Amount wagered in 1e12 wei units.
    function getDailyHeroWager(
        uint48 day,
        uint8 quadrant,
        uint8 symbol
    ) external view returns (uint256 wagerUnits) {
        if (quadrant >= 4 || symbol >= 8) return 0;
        uint256 packed = dailyHeroWagers[day][quadrant];
        wagerUnits = (packed >> (uint256(symbol) * 32)) & 0xFFFFFFFF;
    }

    /// @notice Get the winning hero symbol for a given day (most wagered across all quadrants).
    /// @param day Day index (from GameTimeLib).
    /// @return winQuadrant The winning quadrant.
    /// @return winSymbol The winning symbol within that quadrant.
    /// @return winAmount The wagered units for the winner.
    function getDailyHeroWinner(
        uint48 day
    )
        external
        view
        returns (uint8 winQuadrant, uint8 winSymbol, uint256 winAmount)
    {
        for (uint8 q = 0; q < 4; ++q) {
            uint256 packed = dailyHeroWagers[day][q];
            for (uint8 s = 0; s < 8; ++s) {
                uint256 amount = (packed >> (uint256(s) * 32)) & 0xFFFFFFFF;
                if (amount > winAmount) {
                    winAmount = amount;
                    winQuadrant = q;
                    winSymbol = s;
                }
            }
        }
    }

    /// @notice Get a player's total ETH wagered on degenerette at a specific level.
    /// @param player The player address.
    /// @param lvl The level to query.
    /// @return weiAmount Total ETH wagered in wei.
    function getPlayerDegeneretteWager(
        address player,
        uint24 lvl
    ) external view returns (uint256 weiAmount) {
        weiAmount = playerDegeneretteEthWagered[player][lvl];
    }

    /// @notice Get the top degenerette player for a given level.
    /// @param lvl The level to query.
    /// @return topPlayer The address of the top wagerer.
    /// @return amountUnits The wagered amount in 1e12 wei units.
    function getTopDegenerette(
        uint24 lvl
    ) external view returns (address topPlayer, uint256 amountUnits) {
        uint256 packed = topDegeneretteByLevel[lvl];
        topPlayer = address(uint160(packed));
        amountUnits = packed >> 160;
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
        if (gameOver) revert E();
        if (prizePoolFrozen) {
            (uint128 pNext, uint128 pFuture) = _getPendingPools();
            _setPendingPools(pNext, pFuture + uint128(msg.value));
        } else {
            (uint128 next, uint128 future) = _getPrizePools();
            _setPrizePools(next, future + uint128(msg.value));
        }
    }
}
