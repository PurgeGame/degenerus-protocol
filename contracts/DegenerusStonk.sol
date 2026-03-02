// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {ContractAddresses} from "./ContractAddresses.sol";
import {MintPaymentKind} from "./interfaces/IDegenerusGame.sol";
import {IStETH} from "./interfaces/IStETH.sol";
import {GameTimeLib} from "./libraries/GameTimeLib.sol";

/// @notice Interface for game contract player-facing functions
interface IDegenerusGamePlayer {
    function advanceGame() external;
    function level() external view returns (uint24);
    function mintPrice() external view returns (uint256);
    function setAfKingMode(
        address player,
        bool enabled,
        uint256 ethTakeProfit,
        uint256 coinTakeProfit
    ) external;
    function purchase(
        address buyer,
        uint256 ticketQuantity,
        uint256 lootBoxAmount,
        bytes32 affiliateCode,
        MintPaymentKind payKind
    ) external payable;
    function openLootBox(address player, uint48 lootboxIndex) external;
    function placeFullTicketBets(
        address player,
        uint8 currency,
        uint128 amountPerTicket,
        uint8 ticketCount,
        uint32 customTicket,
        uint8 customSpecial
    ) external payable;
    function claimWinnings(address player) external;
    function claimWinningsStethFirst() external;
    function claimWhalePass(address player) external;
    function claimableWinningsOf(address player) external view returns (uint256);
    function isOperatorApproved(address owner, address operator) external view returns (bool);
    function rngLocked() external view returns (bool);
    function purchaseBurnieLootbox(address buyer, uint256 burnieAmount) external;
    function purchaseCoin(
        address buyer,
        uint256 ticketQuantity,
        uint256 lootBoxBurnieAmount
    ) external;
}

/// @notice Interface for BURNIE coin contract player-facing functions
interface IDegenerusCoinPlayer {
    function depositCoinflip(address player, uint256 amount) external;
    function decimatorBurn(address player, uint256 amount) external;
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IBurnieCoinflipPlayer {
    function claimCoinflips(address player, uint256 amount) external returns (uint256 claimed);
    function previewClaimCoinflips(address player) external view returns (uint256 mintable);
}

interface IWrappedWrappedXRP {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}

/// @notice Minimal quest view interface for streak queries
interface IDegenerusQuestsView {
    function playerQuestStates(address player) external view returns (
        uint32 streak, uint32 lastCompletedDay, uint128[2] memory progress, bool[2] memory completed
    );
}

/**
 * @title DegenerusStonk (DGNRS)
 * @notice Standalone token backed by ETH, stETH, and BURNIE reserves
 * @dev Receives ETH/stETH from game distributions; rewards are distributed from pre-minted pools
 *
 * ARCHITECTURE:
 * - Receives ETH deposits from game distributions
 * - Receives stETH deposits from game distributions
 * - Accrues BURNIE backing via manual transfers and coinflip claimables (withdrawn on burn)
 * - Pre-minted supply split into creator allocation + reward pools
 * - Game distributes DGNRS to players by drawing down pools
 * - Users burn DGNRS to claim proportional ETH + stETH + BURNIE
 */
contract DegenerusStonk {
    // =====================================================================
    //                              ERRORS
    // =====================================================================

    /// @notice Thrown when caller is not authorized for the operation
    error Unauthorized();

    /// @notice Thrown when amount exceeds available balance or allowance
    error Insufficient();

    /// @notice Thrown when zero address is provided where not allowed
    error ZeroAddress();

    /// @notice Thrown when ETH or token transfer fails
    error TransferFailed();

    /// @notice Thrown when caller has no DGNRS token balance
    error NotHolder();

    /// @notice Thrown when action amount exceeds holder's proportional limit
    error ActionLimitExceeded();

    /// @notice Thrown when caller is not approved to act on behalf of player
    error NotApproved();

    /// @notice Thrown when trying to transfer locked tokens
    error TokensLocked();

    /// @notice Thrown when caller has no locked tokens for spending actions
    error NoLockedTokens();

    /// @notice Thrown when trying to unlock tokens before level change
    error LockStillActive();



    // =====================================================================
    //                              EVENTS
    // =====================================================================

    /// @notice Emitted when tokens are transferred between addresses
    /// @param from Source address (address(0) for mints)
    /// @param to Destination address (address(0) for burns)
    /// @param amount Amount of tokens transferred
    event Transfer(address indexed from, address indexed to, uint256 amount);

    /// @notice Emitted when spending allowance is granted
    /// @param owner Token owner granting allowance
    /// @param spender Address authorized to spend
    /// @param amount Amount of allowance granted
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    /// @notice Emitted when DGNRS is burned to claim backing assets
    /// @param from Address that burned tokens
    /// @param amount Amount of DGNRS burned
    /// @param ethOut ETH received
    /// @param stethOut stETH received
    /// @param burnieOut BURNIE received
    event Burn(address indexed from, uint256 amount, uint256 ethOut, uint256 stethOut, uint256 burnieOut);

    /// @notice Emitted when WWXRP is paid out on burn.
    /// @param from Address that burned tokens.
    /// @param wwxrpOut WWXRP amount paid.
    event BurnWwxrp(address indexed from, uint256 wwxrpOut);

    /// @notice Emitted when backing assets are deposited into reserves
    /// @param from Address that deposited
    /// @param ethAmount ETH deposited
    /// @param stethAmount stETH deposited
    /// @param burnieAmount BURNIE amount (always 0; BURNIE arrives via manual transfers or coinflip claims)
    event Deposit(address indexed from, uint256 ethAmount, uint256 stethAmount, uint256 burnieAmount);

    /// @notice Emitted when a purchase rebates BURNIE from claimable reserves.
    /// @param buyer Address that paid ETH.
    /// @param ethValue ETH value used for rebate calculation.
    /// @param burnieOut BURNIE paid out.
    event BurnieRebate(address indexed buyer, uint256 ethValue, uint256 burnieOut);

    /// @notice Emitted when DGNRS is transferred from a reward pool
    /// @param pool Pool from which tokens were transferred
    /// @param to Recipient address
    /// @param amount Amount transferred
    event PoolTransfer(Pool indexed pool, address indexed to, uint256 amount);

    /// @notice Emitted when DGNRS is moved between reward pools
    /// @param from Source pool
    /// @param to Destination pool
    /// @param amount Amount transferred
    event PoolRebalance(Pool indexed from, Pool indexed to, uint256 amount);

    /// @notice Emitted when a DGNRS holder is rewarded for completing a quest on behalf of the contract
    /// @param contributor The holder who made the purchase that completed the quest
    /// @param amount DGNRS reward transferred from the Reward pool
    /// @param newStreak The DGNRS contract's quest streak after completion
    event QuestContributionReward(address indexed contributor, uint256 amount, uint32 newStreak);

    /// @notice Emitted when tokens are locked for DGNRS actions
    /// @param holder Address that locked tokens
    /// @param amount Amount of tokens locked
    /// @param level Level at which tokens were locked
    event Locked(address indexed holder, uint256 amount, uint24 level);

    /// @notice Emitted when locked tokens are released
    /// @param holder Address that unlocked tokens
    /// @param amount Amount of tokens unlocked
    event Unlocked(address indexed holder, uint256 amount);

    // =====================================================================
    //                          ERC20 METADATA
    // =====================================================================

    /// @notice Token name
    string public constant name = "Degenerus Stonk";

    /// @notice Token symbol
    string public constant symbol = "DGNRS";

    /// @notice Token decimals
    uint8 public constant decimals = 18;

    // =====================================================================
    //                          ERC20 STATE
    // =====================================================================

    /// @notice Total supply of DGNRS tokens
    uint256 public totalSupply;

    /// @notice Token balance for each address
    mapping(address => uint256) public balanceOf;

    /// @notice Spending allowances: owner => spender => amount
    mapping(address => mapping(address => uint256)) public allowance;

    // =====================================================================
    //                          RESERVES
    // =====================================================================

    /// @notice ETH backing for DGNRS tokens
    uint256 public ethReserve;

    /// @notice stETH backing for DGNRS tokens
    uint256 public stethReserve;

    // =====================================================================
    //                          POOL STATE
    // =====================================================================

    /// @notice Enumeration of reward pools
    enum Pool {
        Whale,
        Affiliate,
        Lootbox,
        Reward,
        Earlybird
    }

    /// @notice Balances for each reward pool
    uint256[5] private poolBalances;

    // =====================================================================
    //                          CONSTANTS
    // =====================================================================

    /// @notice Initial supply (1 trillion tokens)
    uint256 private constant INITIAL_SUPPLY = 1_000_000_000_000 * 1e18;

    /// @dev Basis points denominator (100%)
    uint16 private constant BPS_DENOM = 10_000;

    /// @dev Creator allocation (20%)
    uint16 private constant CREATOR_BPS = 2000;

    /// @dev Base unit: 1000 BURNIE (18 decimals) per mint at priceWei.
    uint256 private constant PRICE_COIN_UNIT = 1000 ether;

    /// @dev BURNIE payout rate for ETH purchases (70% of value).
    uint16 private constant BURNIE_ETH_BUY_BPS = 7000;

    /// @dev Non-creator pools are reweighted after exterminator removal:
    ///      original [10,30,10,10,10] over 70% -> [1143,3428,1143,1143,1143] over 80%.
    uint16 private constant WHALE_POOL_BPS = 1143;
    uint16 private constant AFFILIATE_POOL_BPS = 3428;
    uint16 private constant LOOTBOX_POOL_BPS = 1143;
    uint16 private constant REWARD_POOL_BPS = 1143;
    uint16 private constant EARLYBIRD_POOL_BPS = 1143;

    /// @dev Affiliate code used for DGNRS purchases
    bytes32 private constant AFFILIATE_CODE_DGNRS = bytes32("DGNRS");

    /// @dev Reward for completing a quest on behalf of the contract (0.05% of remaining Reward pool).
    uint16 private constant QUEST_CONTRIBUTION_BPS = 5;


    /// @notice Amount of DGNRS locked by each address for DGNRS actions
    mapping(address => uint256) public lockedBalance;

    /// @notice Level at which each address locked their tokens
    mapping(address => uint24) public lockedLevel;

    /// @notice Cumulative ETH spent this level by each address (against locked balance)
    mapping(address => uint256) private ethSpentThisLevel;

    /// @notice Cumulative BURNIE spent this level by each address
    mapping(address => uint256) private burnieSpentThisLevel;

    /// @dev Game contract reference for player actions and claimable queries
    IDegenerusGamePlayer private constant game = IDegenerusGamePlayer(ContractAddresses.GAME);

    /// @dev BURNIE token reference for payout accounting
    IDegenerusCoinPlayer private constant coin = IDegenerusCoinPlayer(ContractAddresses.COIN);
    /// @dev Coinflip contract for claimable BURNIE withdrawals during burns
    IBurnieCoinflipPlayer private constant coinflip =
        IBurnieCoinflipPlayer(ContractAddresses.COINFLIP);

    /// @dev WWXRP token reference for proportional burn payouts
    IWrappedWrappedXRP private constant wwxrp =
        IWrappedWrappedXRP(ContractAddresses.WWXRP);

    /// @dev Quest contract reference for streak queries
    IDegenerusQuestsView private constant quests =
        IDegenerusQuestsView(ContractAddresses.QUESTS);

    /// @dev stETH token reference
    IStETH private constant steth = IStETH(ContractAddresses.STETH_TOKEN);

    // =====================================================================
    //                          MODIFIERS
    // =====================================================================

    /// @dev Restricts function to game contract only
    modifier onlyGame() {
        if (msg.sender != ContractAddresses.GAME) revert Unauthorized();
        _;
    }

    /// @dev Restricts function to DGNRS token holders only
    modifier onlyHolder() {
        if (balanceOf[msg.sender] == 0) revert NotHolder();
        _;
    }

    /// @dev Checks if msg.sender is player or an approved operator
    /// @param player The player address to check approval for
    function _requireApproved(address player) private view {
        if (msg.sender != player && !game.isOperatorApproved(player, msg.sender)) {
            revert NotApproved();
        }
    }


    // =====================================================================
    //                          CONSTRUCTOR
    // =====================================================================

    /// @notice Initializes token supply, distributes to pools, and claims whale pass for DGNRS
    /// @dev Mints creator allocation to CREATOR address and pool allocations to this contract
    constructor() {
        uint256 creatorAmount = (INITIAL_SUPPLY * CREATOR_BPS) / BPS_DENOM;
        uint256 whaleAmount = (INITIAL_SUPPLY * WHALE_POOL_BPS) / BPS_DENOM;
        uint256 earlybirdAmount = (INITIAL_SUPPLY * EARLYBIRD_POOL_BPS) / BPS_DENOM;
        uint256 affiliateAmount = (INITIAL_SUPPLY * AFFILIATE_POOL_BPS) / BPS_DENOM;
        uint256 lootboxAmount = (INITIAL_SUPPLY * LOOTBOX_POOL_BPS) / BPS_DENOM;
        uint256 rewardAmount = (INITIAL_SUPPLY * REWARD_POOL_BPS) / BPS_DENOM;
        uint256 totalAllocated = creatorAmount + whaleAmount + earlybirdAmount + affiliateAmount + lootboxAmount + rewardAmount;
        if (totalAllocated < INITIAL_SUPPLY) {
            uint256 dust;
            unchecked {
                dust = INITIAL_SUPPLY - totalAllocated;
            }
            lootboxAmount += dust;
        }
        uint256 poolTotal =
            whaleAmount + earlybirdAmount + affiliateAmount + lootboxAmount + rewardAmount;

        _mint(ContractAddresses.CREATOR, creatorAmount);
        _mint(address(this), poolTotal);

        poolBalances[uint8(Pool.Whale)] = whaleAmount;
        poolBalances[uint8(Pool.Affiliate)] = affiliateAmount;
        poolBalances[uint8(Pool.Lootbox)] = lootboxAmount;
        poolBalances[uint8(Pool.Reward)] = rewardAmount;
        poolBalances[uint8(Pool.Earlybird)] = earlybirdAmount;

        game.claimWhalePass(address(0));
        game.setAfKingMode(
            address(0),
            true,
            10 ether,
            0
        );
    }

    // =====================================================================
    //                          ERC20 FUNCTIONS
    // =====================================================================

    /// @notice Approve spender to transfer tokens on behalf of msg.sender
    /// @param spender Address to authorize
    /// @param amount Amount to authorize
    /// @return True on success
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    /// @notice Transfer tokens from msg.sender to recipient
    /// @param to Recipient address
    /// @param amount Amount to transfer
    /// @return True on success
    /// @custom:reverts ZeroAddress If to is zero address
    /// @custom:reverts Insufficient If sender balance is insufficient
    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    /// @notice Transfer tokens on behalf of another address
    /// @dev COIN contract is trusted and bypasses allowance checks
    /// @param from Source address
    /// @param to Destination address
    /// @param amount Amount to transfer
    /// @return True on success
    /// @custom:reverts Insufficient If allowance or balance is insufficient
    /// @custom:reverts ZeroAddress If to or from is zero address
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        // BurnieCoin is a trusted spender inside the ecosystem; skip allowance checks.
        if (msg.sender != ContractAddresses.COIN) {
            uint256 allowed = allowance[from][msg.sender];
            if (allowed != type(uint256).max) {
                if (allowed < amount) revert Insufficient();
                uint256 newAllowance;
                unchecked {
                    newAllowance = allowed - amount;
                    allowance[from][msg.sender] = newAllowance;
                }
                emit Approval(from, msg.sender, newAllowance);
            }
        }
        _transfer(from, to, amount);
        return true;
    }

    // =====================================================================
    //                          PLAYER ACTIONS
    // =====================================================================

    /// @notice Lock DGNRS tokens to gain DGNRS action rights for the current level
    /// @dev Locked tokens cannot be transferred until level changes. Spending limits
    ///      are based on locked amount. Can increase lock within same level.
    /// @param amount Amount of DGNRS to lock (added to existing lock if same level)
    /// @custom:reverts Insufficient If amount exceeds available (unlocked) balance
    function lockForLevel(uint256 amount) external {
        uint24 currentLevel = game.level();
        uint256 currentLocked = lockedBalance[msg.sender];
        uint24 currentLockedLevel = lockedLevel[msg.sender];

        // If locked at a different level, auto-unlock first
        if (currentLocked > 0 && currentLockedLevel != currentLevel) {
            emit Unlocked(msg.sender, currentLocked);
            currentLocked = 0;
            ethSpentThisLevel[msg.sender] = 0;
            burnieSpentThisLevel[msg.sender] = 0;
        }

        uint256 available = balanceOf[msg.sender] - currentLocked;
        if (amount > available) revert Insufficient();

        uint256 newLocked = currentLocked + amount;
        lockedBalance[msg.sender] = newLocked;
        lockedLevel[msg.sender] = currentLevel;

        emit Locked(msg.sender, amount, currentLevel);
    }

    /// @notice Unlock DGNRS tokens after level has changed
    /// @dev Resets spending counters. Reverts if still at the same level as lock.
    /// @custom:reverts NoLockedTokens If caller has no locked tokens
    /// @custom:reverts LockStillActive If current level equals locked level
    function unlock() external {
        uint256 locked = lockedBalance[msg.sender];
        if (locked == 0) revert NoLockedTokens();

        uint24 currentLevel = game.level();
        if (lockedLevel[msg.sender] == currentLevel) revert LockStillActive();

        lockedBalance[msg.sender] = 0;
        ethSpentThisLevel[msg.sender] = 0;
        burnieSpentThisLevel[msg.sender] = 0;

        emit Unlocked(msg.sender, locked);
    }

    /// @notice Advance the game on behalf of DGNRS
    /// @dev Restricted to DGNRS holders
    /// @custom:reverts NotHolder If caller has no DGNRS balance
    function gameAdvance() external onlyHolder {
        game.advanceGame();
    }

    /// @notice Purchase tickets and lootboxes on behalf of DGNRS
    /// @dev Requires locked tokens. Limited by proportional stake of locked amount per level.
    /// @param ticketQuantity Number of tickets to purchase
    /// @param lootBoxAmount ETH amount to spend on lootboxes
    /// @param payKind Payment method (ETH, stETH, etc.)
    /// @custom:reverts NoLockedTokens If caller has no locked tokens at current level
    /// @custom:reverts ActionLimitExceeded If cumulative cost this level exceeds holder's limit
    function gamePurchase(
        uint256 ticketQuantity,
        uint256 lootBoxAmount,
        MintPaymentKind payKind
    ) external payable {
        uint256 priceWei = game.mintPrice();
        uint256 ticketCost = (priceWei * ticketQuantity) / (4 * 100);
        uint256 totalCost = ticketCost + lootBoxAmount;
        _checkAndRecordEthSpend(msg.sender, totalCost);

        // Snapshot DGNRS contract's quest streak before purchase
        (uint32 streakBefore, , , ) = quests.playerQuestStates(address(this));

        game.purchase{value: msg.value}(
            address(0),
            ticketQuantity,
            lootBoxAmount,
            AFFILIATE_CODE_DGNRS,
            payKind
        );

        uint256 ethValue = payKind == MintPaymentKind.DirectEth
            ? totalCost
            : msg.value;
        _rebateBurnieFromEthValue(ethValue);

        // Reward contributor if the purchase completed a quest (streak incremented)
        (uint32 streakAfter, , , ) = quests.playerQuestStates(address(this));
        if (streakAfter > streakBefore) {
            uint256 rewardAmount = (poolBalances[uint8(Pool.Reward)] * QUEST_CONTRIBUTION_BPS) / BPS_DENOM;
            if (rewardAmount != 0) {
                uint256 rewarded = _transferFromPoolInternal(Pool.Reward, msg.sender, rewardAmount);
                if (rewarded != 0) {
                    emit QuestContributionReward(msg.sender, rewarded, streakAfter);
                }
            }
        }
    }

    /// @notice Purchase BURNIE tickets on behalf of DGNRS
    /// @dev Requires locked tokens; enforces BURNIE spend limits.
    /// @param ticketQuantity Number of tickets to purchase (scaled per game rules).
    function gamePurchaseTicketsBurnie(uint256 ticketQuantity) external {
        if (ticketQuantity == 0) revert Insufficient();
        uint256 burnieCost = ticketQuantity * PRICE_COIN_UNIT;
        _checkAndRecordBurnieSpend(msg.sender, burnieCost);

        // Route through Game.purchaseCoin() - buyer is DGNRS contract (address(0) resolves to msg.sender in Game)
        game.purchaseCoin(address(0), ticketQuantity, 0);
    }

    /// @notice Purchase a BURNIE lootbox on behalf of DGNRS
    /// @dev Requires locked tokens; enforces BURNIE spend limits.
    /// @param burnieAmount Amount of BURNIE to burn (18 decimals).
    function gamePurchaseBurnieLootbox(uint256 burnieAmount) external {
        if (burnieAmount == 0) revert Insufficient();
        _checkAndRecordBurnieSpend(msg.sender, burnieAmount);
        game.purchaseBurnieLootbox(address(0), burnieAmount);
    }

    /// @notice Place a Degenerette bet using ETH (or claimable ETH).
    /// @dev Requires locked tokens; enforces ETH spend limits.
    function gameDegeneretteBetEth(
        uint128 amountPerTicket,
        uint8 ticketCount,
        uint32 customTicket,
        uint8 customSpecial
    ) external payable {
        uint256 totalBet = uint256(amountPerTicket) * uint256(ticketCount);
        _checkAndRecordEthSpend(msg.sender, totalBet);
        game.placeFullTicketBets{value: msg.value}(
            address(0),
            0,
            amountPerTicket,
            ticketCount,
            customTicket,
            customSpecial
        );
    }

    /// @notice Place a Degenerette bet using BURNIE.
    /// @dev Requires locked tokens; enforces BURNIE spend limits.
    function gameDegeneretteBetBurnie(
        uint128 amountPerTicket,
        uint8 ticketCount,
        uint32 customTicket,
        uint8 customSpecial
    ) external {
        uint256 totalBet = uint256(amountPerTicket) * uint256(ticketCount);
        _checkAndRecordBurnieSpend(msg.sender, totalBet);
        game.placeFullTicketBets(
            address(0),
            1,
            amountPerTicket,
            ticketCount,
            customTicket,
            customSpecial
        );
    }

    /// @notice Open a lootbox on behalf of DGNRS
    /// @dev Restricted to DGNRS holders
    /// @param lootboxIndex Index of the lootbox to open
    /// @custom:reverts NotHolder If caller has no DGNRS balance
    function gameOpenLootBox(uint48 lootboxIndex) external onlyHolder {
        game.openLootBox(address(0), lootboxIndex);
    }

    /// @notice Claim whale pass on behalf of DGNRS
    /// @dev Restricted to DGNRS holders
    /// @custom:reverts NotHolder If caller has no DGNRS balance
    function gameClaimWhalePass() external onlyHolder {
        game.claimWhalePass(address(0));
    }

    /// @notice Burn BURNIE in decimator on behalf of DGNRS
    /// @dev Requires locked tokens at current level and enforces burnie spend limits.
    /// @param amount Amount of BURNIE to burn (18 decimals).
    function coinDecimatorBurn(uint256 amount) external {
        _checkAndRecordBurnieSpend(msg.sender, amount);
        coin.decimatorBurn(address(this), amount);
    }

    /// @dev Rebate BURNIE based on ETH value, paying from balance first then claimable.
    ///      If insufficient or RNG locked for claimables, rebate is skipped.
    function _rebateBurnieFromEthValue(uint256 ethValue) private {
        if (ethValue == 0) return;

        uint256 priceWei = game.mintPrice();
        if (priceWei == 0) return;

        uint256 burnieValue = (ethValue * PRICE_COIN_UNIT) / priceWei;
        uint256 burnieOut = (burnieValue * BURNIE_ETH_BUY_BPS) / BPS_DENOM;
        if (burnieOut == 0) return;

        uint256 burnieBal = coin.balanceOf(address(this));
        if (burnieBal < burnieOut) {
            if (game.rngLocked()) return;
            uint256 remainder = burnieOut - burnieBal;
            uint256 claimable = coinflip.previewClaimCoinflips(address(this));
            if (claimable < remainder) return;
            uint256 claimed = coinflip.claimCoinflips(address(this), remainder);
            if (claimed < remainder) return;
        }

        if (!coin.transfer(msg.sender, burnieOut)) revert TransferFailed();
        emit BurnieRebate(msg.sender, ethValue, burnieOut);
    }

    // =====================================================================
    //                          DEPOSITS (Game Only)
    // =====================================================================

    /// @notice Receive ETH deposit from game contract
    /// @dev Only callable by game contract. Adds ETH to reserve without minting new tokens.
    /// @custom:reverts Unauthorized If caller is not game contract
    receive() external payable onlyGame {
        emit Deposit(msg.sender, msg.value, 0, 0);
    }

    /// @notice Receive stETH deposit from game contract
    /// @dev Only callable by game contract. Transfers stETH from caller and adds to reserve.
    /// @param amount Amount of stETH to deposit
    /// @custom:reverts Unauthorized If caller is not game contract
    /// @custom:reverts TransferFailed If stETH transfer fails
    function depositSteth(uint256 amount) external onlyGame {
        if (!steth.transferFrom(msg.sender, address(this), amount)) revert TransferFailed();
        emit Deposit(msg.sender, 0, amount, 0);
    }

    // =====================================================================
    //                          POOL SPENDING (Game Only)
    // =====================================================================

    /// @notice Get remaining balance for a reward pool
    /// @param pool Pool identifier
    /// @return Remaining pool balance
    function poolBalance(Pool pool) external view returns (uint256) {
        return poolBalances[_poolIndex(pool)];
    }

    /// @notice Transfer DGNRS from a reward pool to a recipient
    /// @dev Only callable by game contract. Transfers up to available balance if requested amount exceeds pool.
    /// @param pool Pool identifier
    /// @param to Recipient address
    /// @param amount Requested amount of DGNRS to transfer
    /// @return transferred Actual amount transferred (may be less than requested if pool depleted)
    /// @custom:reverts Unauthorized If caller is not game contract
    /// @custom:reverts ZeroAddress If to is zero address
    function transferFromPool(Pool pool, address to, uint256 amount) external onlyGame returns (uint256 transferred) {
        if (amount == 0) return 0;
        uint8 idx = _poolIndex(pool);
        uint256 available = poolBalances[idx];
        if (available == 0) return 0;
        if (amount > available) {
            amount = available;
        }
        unchecked {
            poolBalances[idx] = available - amount;
        }
        _transfer(address(this), to, amount);
        emit PoolTransfer(pool, to, amount);
        return amount;
    }

    /// @notice Transfer DGNRS between two reward pools
    /// @dev Only callable by game contract. No token movement — just rebalances internal pool accounting.
    /// @param from Source pool
    /// @param to Destination pool
    /// @param amount Requested amount to move
    /// @return transferred Actual amount transferred (may be less if source pool has insufficient balance)
    function transferBetweenPools(Pool from, Pool to, uint256 amount) external onlyGame returns (uint256 transferred) {
        if (amount == 0) return 0;
        uint8 fromIdx = _poolIndex(from);
        uint8 toIdx = _poolIndex(to);
        uint256 available = poolBalances[fromIdx];
        if (available == 0) return 0;
        if (amount > available) {
            amount = available;
        }
        unchecked {
            poolBalances[fromIdx] = available - amount;
        }
        poolBalances[toIdx] += amount;
        emit PoolRebalance(from, to, amount);
        return amount;
    }

    /// @notice Burn DGNRS tokens for game bets
    /// @dev Only callable by game contract.
    /// @param from Address to burn from
    /// @param amount Amount to burn
    /// @custom:reverts Unauthorized If caller is not game contract
    /// @custom:reverts Insufficient If from balance is insufficient
    function burnForGame(address from, uint256 amount) external onlyGame {
        if (amount == 0) return;
        _burn(from, amount);
    }

    // =====================================================================
    //                          BURN (Public)
    // =====================================================================

    /// @notice Burn DGNRS to claim proportional share of backing assets
    /// @dev Includes claimable ETH from game. BURNIE is paid from the contract's
    ///      balance plus coinflip claimables (withdrawn on demand). Prioritizes
    ///      BURNIE first, then ETH over stETH for the remainder. Also pays a
    ///      proportional share of any WWXRP held by this contract.
    /// @param player Player address to burn for (address(0) defaults to msg.sender)
    /// @param amount Amount of DGNRS to burn
    /// @return ethOut ETH received
    /// @return stethOut stETH received
    /// @return burnieOut BURNIE received
    /// @custom:reverts NotApproved If caller is not player and not approved operator
    /// @custom:reverts Insufficient If amount is zero, exceeds balance, or reserves insufficient
    /// @custom:reverts TransferFailed If asset transfer fails
    function burn(
        address player,
        uint256 amount
    ) external returns (uint256 ethOut, uint256 stethOut, uint256 burnieOut) {
        if (player == address(0)) {
            player = msg.sender;
        } else if (player != msg.sender) {
            _requireApproved(player);
        }
        return _burnFor(player, amount);
    }

    /// @dev Internal burn implementation
    /// @param player Address to burn tokens from and send assets to
    /// @param amount Amount of DGNRS to burn
    /// @return ethOut ETH sent to player
    /// @return stethOut stETH sent to player
    /// @return burnieOut BURNIE sent to player
    function _burnFor(
        address player,
        uint256 amount
    ) private returns (uint256 ethOut, uint256 stethOut, uint256 burnieOut) {
        uint256 bal = balanceOf[player];
        if (amount == 0 || amount > bal) revert Insufficient();
        uint256 supplyBefore = totalSupply;

        uint256 ethBal = address(this).balance;
        uint256 stethBal = steth.balanceOf(address(this));
        uint256 claimableEth = _claimableWinnings();
        uint256 totalMoney = ethBal + stethBal + claimableEth;
        uint256 totalValueOwed = (totalMoney * amount) / supplyBefore;

        uint256 burnieBal = coin.balanceOf(address(this));
        uint256 claimableBurnie = coinflip.previewClaimCoinflips(address(this));
        uint256 totalBurnie = burnieBal + claimableBurnie;
        burnieOut = (totalBurnie * amount) / supplyBefore;

        uint256 wwxrpBal = wwxrp.balanceOf(address(this));
        uint256 wwxrpOut = (wwxrpBal * amount) / supplyBefore;

        _burnWithBalance(player, amount, bal);

        if (totalValueOwed > ethBal && claimableEth != 0) {
            game.claimWinnings(address(0));
            ethBal = address(this).balance;
            stethBal = steth.balanceOf(address(this));
        }

        if (totalValueOwed <= ethBal) {
            ethOut = totalValueOwed;
        } else {
            ethOut = ethBal;
            stethOut = totalValueOwed - ethOut;
            if (stethOut > stethBal) revert Insufficient();
        }

        uint256 remainingBurnie = burnieOut;
        if (remainingBurnie != 0) {
            uint256 payBal = remainingBurnie <= burnieBal ? remainingBurnie : burnieBal;
            if (payBal != 0) {
                remainingBurnie -= payBal;
                if (!coin.transfer(player, payBal)) revert TransferFailed();
            }
            if (remainingBurnie != 0) {
                coinflip.claimCoinflips(address(0), remainingBurnie);
                if (!coin.transfer(player, remainingBurnie)) revert TransferFailed();
            }
        }

        if (ethOut > 0) {
            (bool success, ) = player.call{value: ethOut}("");
            if (!success) revert TransferFailed();
        }
        if (stethOut > 0) {
            if (!steth.transfer(player, stethOut)) revert TransferFailed();
        }

        if (wwxrpOut > 0) {
            if (!wwxrp.transfer(player, wwxrpOut)) revert TransferFailed();
            emit BurnWwxrp(player, wwxrpOut);
        }

        emit Burn(player, amount, ethOut, stethOut, burnieOut);
    }

    // =====================================================================
    //                          VIEW FUNCTIONS
    // =====================================================================

    /// @notice Preview ETH, stETH, and BURNIE output for burning DGNRS
    /// @dev Reflects ETH-preferential payout logic using current balances and claimables.
    ///      BURNIE includes claimable coinflip withdrawals.
    /// @param amount Amount of DGNRS to burn
    /// @return ethOut ETH that would be received
    /// @return stethOut stETH that would be received
    /// @return burnieOut BURNIE that would be received
    function previewBurn(uint256 amount) external view returns (uint256 ethOut, uint256 stethOut, uint256 burnieOut) {
        uint256 supply = totalSupply;
        if (amount == 0 || amount > supply) return (0, 0, 0);

        uint256 ethBal = address(this).balance;
        uint256 stethBal = steth.balanceOf(address(this));
        uint256 claimableEth = _claimableWinnings();
        uint256 totalMoney = ethBal + stethBal + claimableEth;
        uint256 totalValueOwed = (totalMoney * amount) / supply;

        uint256 ethAvailable = ethBal + claimableEth;
        if (totalValueOwed <= ethAvailable) {
            ethOut = totalValueOwed;
        } else {
            ethOut = ethAvailable;
            stethOut = totalValueOwed - ethOut;
        }

        uint256 burnieBal = coin.balanceOf(address(this));
        uint256 claimableBurnie = coinflip.previewClaimCoinflips(address(this));
        uint256 totalBurnie = burnieBal + claimableBurnie;
        burnieOut = (totalBurnie * amount) / supply;
    }

    /// @notice Get total backing value (ETH + stETH + claimable ETH + BURNIE backing)
    /// @dev Uses live balances plus claimable ETH/BURNIE to match burn payout math.
    /// @return Total backing value
    function totalBacking() external view returns (uint256) {
        uint256 ethBal = address(this).balance;
        uint256 stethBal = steth.balanceOf(address(this));
        uint256 claimableEth = _claimableWinnings();
        uint256 burnieBal = coin.balanceOf(address(this));
        uint256 claimableBurnie = coinflip.previewClaimCoinflips(address(this));
        return ethBal + stethBal + claimableEth + burnieBal + claimableBurnie;
    }

    /// @notice Get BURNIE backing (balance + claimable coinflips)
    /// @return BURNIE backing value
    function burnieReserve() external view returns (uint256) {
        uint256 burnieBal = coin.balanceOf(address(this));
        uint256 claimableBurnie = coinflip.previewClaimCoinflips(address(this));
        return burnieBal + claimableBurnie;
    }

    /// @notice Get spending limits and usage for an address based on their lock
    /// @param holder Address to check
    /// @return locked Amount of DGNRS locked
    /// @return lockLevel Level at which tokens are locked (0 if not locked or stale)
    /// @return ethLimit Maximum ETH spend allowed this level
    /// @return ethSpent ETH already spent this level
    /// @return burnieLimit Maximum BURNIE spend allowed this level
    /// @return burnieSpent BURNIE already spent this level
    /// @return canUnlock Whether the holder can unlock (level has changed)
    function getLockStatus(address holder) external view returns (
        uint256 locked,
        uint24 lockLevel,
        uint256 ethLimit,
        uint256 ethSpent,
        uint256 burnieLimit,
        uint256 burnieSpent,
        bool canUnlock
    ) {
        locked = lockedBalance[holder];
        lockLevel = lockedLevel[holder];
        uint24 currentLevel = game.level();

        if (locked > 0 && lockLevel == currentLevel) {
            (ethLimit, burnieLimit) = _lockedClaimableValues(locked);
            ethLimit *= 10;
            burnieLimit *= 10;
            ethSpent = ethSpentThisLevel[holder];
            burnieSpent = burnieSpentThisLevel[holder];
            canUnlock = false;
        } else if (locked > 0) {
            canUnlock = true;
        }
    }

    // =====================================================================
    //                          INTERNAL HELPERS
    // =====================================================================

    /// @dev Calculate maximum ETH action limit based on locked DGNRS (10x proportional ETH value)
    /// @param locked Amount of DGNRS locked
    /// @return maxEth Maximum ETH amount allowed for actions
    function _maxEthActionFromLocked(uint256 locked) private view returns (uint256 maxEth) {
        (uint256 ethValue, ) = _lockedClaimableValues(locked);
        unchecked {
            return ethValue * 10;
        }
    }

    /// @dev Calculate maximum BURNIE action limit based on locked DGNRS (10x proportional BURNIE value)
    /// @param locked Amount of DGNRS locked
    /// @return maxBurnie Maximum BURNIE amount allowed for actions
    function _maxBurnieActionFromLocked(uint256 locked) private view returns (uint256 maxBurnie) {
        (, uint256 burnieValue) = _lockedClaimableValues(locked);
        unchecked {
            return burnieValue * 10;
        }
    }

    /// @dev Calculate proportional ETH and BURNIE values for a locked amount
    /// @param locked Amount of DGNRS locked
    /// @return ethValue Proportional share of ETH + stETH + claimable winnings
    /// @return burnieValue Proportional share of BURNIE + claimable coinflips
    function _lockedClaimableValues(
        uint256 locked
    ) private view returns (uint256 ethValue, uint256 burnieValue) {
        uint256 supply = totalSupply;
        if (supply == 0 || locked == 0) return (0, 0);

        uint256 ethBal = address(this).balance;
        uint256 stethBal = steth.balanceOf(address(this));
        uint256 claimableEth = _claimableWinnings();
        uint256 totalMoney = ethBal + stethBal + claimableEth;
        ethValue = (totalMoney * locked) / supply;

        uint256 burnieBal = coin.balanceOf(address(this));
        uint256 claimableBurnie = coinflip.previewClaimCoinflips(address(this));
        uint256 totalBurnie = burnieBal + claimableBurnie;
        burnieValue = (totalBurnie * locked) / supply;
    }

    /// @dev Transfer DGNRS from a pool to a recipient (internal, no access control)
    /// @param pool Pool to transfer from
    /// @param to Recipient address
    /// @param amount Requested amount
    /// @return transferred Actual amount transferred
    function _transferFromPoolInternal(Pool pool, address to, uint256 amount) private returns (uint256 transferred) {
        if (amount == 0) return 0;
        uint8 idx = _poolIndex(pool);
        uint256 available = poolBalances[idx];
        if (available == 0) return 0;
        if (amount > available) {
            amount = available;
        }
        unchecked {
            poolBalances[idx] = available - amount;
        }
        _transfer(address(this), to, amount);
        emit PoolTransfer(pool, to, amount);
        return amount;
    }

    /// @dev Check and record ETH spend based on locked balance
    /// @param holder Address spending ETH
    /// @param amount Amount of ETH being spent
    function _checkAndRecordEthSpend(address holder, uint256 amount) private {
        uint24 currentLevel = game.level();
        uint256 locked = lockedBalance[holder];

        // Must have tokens locked at current level
        if (locked == 0 || lockedLevel[holder] != currentLevel) revert NoLockedTokens();

        uint256 newTotal = ethSpentThisLevel[holder] + amount;
        if (newTotal > _maxEthActionFromLocked(locked)) revert ActionLimitExceeded();
        ethSpentThisLevel[holder] = newTotal;
    }

    /// @dev Check and record BURNIE spend based on locked balance
    /// @param holder Address spending BURNIE
    /// @param amount Amount of BURNIE being spent
    function _checkAndRecordBurnieSpend(address holder, uint256 amount) private {
        uint24 currentLevel = game.level();
        uint256 locked = lockedBalance[holder];

        // Must have tokens locked at current level
        if (locked == 0 || lockedLevel[holder] != currentLevel) revert NoLockedTokens();

        uint256 newTotal = burnieSpentThisLevel[holder] + amount;
        if (newTotal > _maxBurnieActionFromLocked(locked)) revert ActionLimitExceeded();
        burnieSpentThisLevel[holder] = newTotal;
    }

    /// @dev Get claimable game winnings, accounting for dust (returns 0 if stored <= 1)
    /// @return claimable Claimable winnings minus 1 wei dust
    function _claimableWinnings() private view returns (uint256 claimable) {
        uint256 stored = game.claimableWinningsOf(address(this));
        if (stored <= 1) return 0;
        return stored - 1;
    }

    /// @dev Convert Pool enum to array index
    /// @param pool Pool enum value
    /// @return Index into poolBalances array
    function _poolIndex(Pool pool) private pure returns (uint8) {
        return uint8(pool);
    }

    /// @dev Internal transfer implementation
    /// @param from Source address
    /// @param to Destination address
    /// @param amount Amount to transfer
    function _transfer(address from, address to, uint256 amount) private {
        if (to == address(0)) revert ZeroAddress();
        uint256 bal = balanceOf[from];
        if (amount > bal) revert Insufficient();

        // Enforce lock: can only transfer unlocked portion
        uint256 locked = lockedBalance[from];
        if (locked > 0 && lockedLevel[from] == game.level()) {
            uint256 transferable = bal - locked;
            if (amount > transferable) revert TokensLocked();
        }

        unchecked {
            balanceOf[from] = bal - amount;
            balanceOf[to] += amount;
        }
        emit Transfer(from, to, amount);
    }

    /// @dev Reduce active lock when tokens are burned in the same level
    function _reduceActiveLock(address holder, uint256 amount) private {
        if (lockedLevel[holder] != game.level()) return;
        uint256 locked = lockedBalance[holder];
        if (locked == 0) return;
        if (amount >= locked) {
            lockedBalance[holder] = 0;
        } else {
            unchecked {
                lockedBalance[holder] = locked - amount;
            }
        }
    }

    /// @dev Internal mint implementation
    /// @param to Recipient address
    /// @param amount Amount to mint
    function _mint(address to, uint256 amount) private {
        if (to == address(0)) revert ZeroAddress();
        unchecked {
            totalSupply += amount;
            balanceOf[to] += amount;
        }
        emit Transfer(address(0), to, amount);
    }

    /// @dev Internal burn implementation
    /// @param from Address to burn from
    /// @param amount Amount to burn
    function _burn(address from, uint256 amount) private {
        uint256 bal = balanceOf[from];
        if (amount > bal) revert Insufficient();
        _reduceActiveLock(from, amount);
        unchecked {
            balanceOf[from] = bal - amount;
            totalSupply -= amount;
        }
        emit Transfer(from, address(0), amount);
    }

    /// @dev Optimized burn when balance is already known
    /// @param from Address to burn from
    /// @param amount Amount to burn
    /// @param bal Pre-fetched balance of from address (caller must ensure amount <= bal)
    function _burnWithBalance(address from, uint256 amount, uint256 bal) private {
        _reduceActiveLock(from, amount);
        unchecked {
            balanceOf[from] = bal - amount;
            totalSupply -= amount;
        }
        emit Transfer(from, address(0), amount);
    }
}
