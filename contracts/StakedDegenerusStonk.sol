// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {ContractAddresses} from "./ContractAddresses.sol";
import {IStETH} from "./interfaces/IStETH.sol";


/// @notice Interface for game contract player-facing functions used by sDGNRS.
interface IDegenerusGamePlayer {
    /// @notice Advance the game to the next level/day.
    function advanceGame() external;
    /// @notice Configure afKing mode for a player.
    function setAfKingMode(
        address player,
        bool enabled,
        uint256 ethTakeProfit,
        uint256 coinTakeProfit
    ) external;
    /// @notice Claim accumulated ETH winnings for a player.
    function claimWinnings(address player) external;
    /// @notice Claim whale pass for a player.
    function claimWhalePass(address player) external;
    /// @notice View claimable ETH winnings for a player.
    function claimableWinningsOf(address player) external view returns (uint256);
    /// @notice Check if VRF request is pending (RNG locked).
    function rngLocked() external view returns (bool);
    /// @notice Check if game is over.
    function gameOver() external view returns (bool);
    /// @notice Check if the liveness-timeout game-over trigger is active (State 1 precursor).
    function livenessTriggered() external view returns (bool);
    /// @notice Get current day index.
    function currentDayView() external view returns (uint32);
    /// @notice Get RNG word for a specific day.
    function rngWordForDay(uint32 day) external view returns (uint256);
    /// @notice Get player's activity score.
    function playerActivityScore(address player) external view returns (uint256);
    /// @notice Resolve a redemption lootbox for a player.
    function resolveRedemptionLootbox(address player, uint256 amount, uint256 rngWord, uint16 activityScore) external;
}

/// @notice Interface for BURNIE coin contract player-facing functions used by sDGNRS.
interface IDegenerusCoinPlayer {
    /// @notice Get token balance for an address.
    function balanceOf(address account) external view returns (uint256);
    /// @notice Transfer tokens to a recipient.
    function transfer(address to, uint256 amount) external returns (bool);
}

/// @notice Interface for BurnieCoinflip contract methods used by sDGNRS.
interface IBurnieCoinflipPlayer {
    /// @notice Claim coinflip winnings for a player.
    function claimCoinflips(address player, uint256 amount) external returns (uint256 claimed);
    /// @notice Preview claimable coinflip winnings for a player.
    function previewClaimCoinflips(address player) external view returns (uint256 mintable);
    /// @notice Claim coinflip winnings for sDGNRS redemption (skips RNG lock).
    function claimCoinflipsForRedemption(address player, uint256 amount) external returns (uint256 claimed);
    /// @notice Get the result of a coinflip day.
    function getCoinflipDayResult(uint32 day) external view returns (uint16 rewardPercent, bool win);
}

/// @notice Interface for DGNRS wrapper contract used by sDGNRS.
interface IDegenerusStonkWrapper {
    /// @notice Burn DGNRS from a player on behalf of sDGNRS.
    function burnForSdgnrs(address player, uint256 amount) external;
}

/**
 * @title StakedDegenerusStonk (sDGNRS)
 * @notice Soulbound token backed by ETH, stETH, and BURNIE reserves
 * @dev Receives ETH/stETH from game distributions; rewards are distributed from pre-minted pools.
 *      Creator allocation is minted to the DGNRS wrapper contract; all other holders receive
 *      sDGNRS directly from reward pools (soulbound — no transfer function).
 *
 * ARCHITECTURE:
 * - Receives ETH deposits from game distributions
 * - Receives stETH deposits from game distributions
 * - Accrues BURNIE backing via manual transfers and coinflip claimables (withdrawn on burn)
 * - Pre-minted supply split into DGNRS wrapper allocation + reward pools
 * - Game distributes sDGNRS to players by drawing down pools
 * - Users burn sDGNRS to claim proportional ETH + stETH + BURNIE
 */
contract StakedDegenerusStonk {
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

    /// @notice Thrown when burns are attempted during RNG resolution
    error BurnsBlockedDuringRng();

    /// @notice Thrown when burns are attempted after liveness fires but before gameOver latches.
    ///         Gambling-path redemptions submitted in this window would resolve but the
    ///         reserved ETH is swept by handleGameOverDrain before claimRedemption can run.
    error BurnsBlockedDuringLiveness();

    /// @notice Thrown when a player tries to submit a new claim while one is unresolved
    error UnresolvedClaim();

    /// @notice Thrown when a player tries to claim with no pending redemption
    error NoClaim();

    /// @notice Thrown when a player tries to claim before the period is resolved
    error NotResolved();

    /// @notice Thrown when a gambling burn would exceed 160 ETH daily EV cap per wallet
    error ExceedsDailyRedemptionCap();


    // =====================================================================
    //                              EVENTS
    // =====================================================================

    /// @notice Emitted when tokens are transferred between addresses
    /// @param from Source address (address(0) for mints)
    /// @param to Destination address (address(0) for burns)
    /// @param amount Amount of tokens transferred
    event Transfer(address indexed from, address indexed to, uint256 amount);

    /// @notice Emitted when sDGNRS is burned to claim backing assets
    /// @param from Address that burned tokens
    /// @param amount Amount of sDGNRS burned
    /// @param ethOut ETH received
    /// @param stethOut stETH received
    /// @param burnieOut BURNIE received
    event Burn(address indexed from, uint256 amount, uint256 ethOut, uint256 stethOut, uint256 burnieOut);

    /// @notice Emitted when backing assets are deposited into reserves
    /// @param from Address that deposited
    /// @param ethAmount ETH deposited
    /// @param stethAmount stETH deposited
    /// @param burnieAmount BURNIE amount (always 0; BURNIE arrives via manual transfers or coinflip claims)
    event Deposit(address indexed from, uint256 ethAmount, uint256 stethAmount, uint256 burnieAmount);

    /// @notice Emitted when sDGNRS is transferred from a reward pool
    /// @param pool Pool from which tokens were transferred
    /// @param to Recipient address
    /// @param amount Amount transferred
    event PoolTransfer(Pool indexed pool, address indexed to, uint256 amount);

    /// @notice Emitted when sDGNRS is moved between reward pools
    /// @param from Source pool
    /// @param to Destination pool
    /// @param amount Amount transferred
    event PoolRebalance(Pool indexed from, Pool indexed to, uint256 amount);

    /// @notice Emitted when a player submits a gambling burn redemption
    event RedemptionSubmitted(address indexed player, uint256 sdgnrsAmount, uint256 ethValueOwed, uint256 burnieOwed, uint32 periodIndex);

    /// @notice Emitted when a redemption period is resolved with a roll
    event RedemptionResolved(uint32 indexed periodIndex, uint16 roll, uint256 rolledBurnie, uint32 flipDay);

    /// @notice Emitted when a player claims their resolved redemption
    event RedemptionClaimed(address indexed player, uint16 roll, bool flipResolved, uint256 ethPayout, uint256 burniePayout, uint256 lootboxEth);

    // =====================================================================
    //                          ERC20 METADATA
    // =====================================================================

    /// @notice Token name
    string public constant name = "Staked Degenerus Stonk";

    /// @notice Token symbol
    string public constant symbol = "sDGNRS";

    /// @notice Token decimals
    uint8 public constant decimals = 18;

    // =====================================================================
    //                          ERC20 STATE
    // =====================================================================

    /// @notice Total supply of sDGNRS tokens
    uint256 public totalSupply;

    /// @notice Token balance for each address
    mapping(address => uint256) public balanceOf;

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
    //                   GAMBLING BURN STATE
    // =====================================================================

    struct PendingRedemption {
        uint96  ethValueOwed;   // base (100%) ETH-equivalent owed (max ~79B ETH)
        uint96  burnieOwed;     // base (100%) BURNIE owed (max ~79B ETH-equiv)
        uint32  periodIndex;    // which daily period (dailyIdx at submission)
        uint16  activityScore;  // snapshotted activity score + 1 (0 = not yet set)
    } // 96 + 96 + 32 + 16 = 240 bits (1 slot)

    struct RedemptionPeriod {
        uint16  roll;           // 0 = unresolved, 25-175 = resolved
        uint32  flipDay;        // coinflip day for BURNIE gamble
    }

    mapping(address => PendingRedemption) public pendingRedemptions;
    mapping(uint32 => RedemptionPeriod) public redemptionPeriods;

    uint256 public pendingRedemptionEthValue;      // total segregated ETH across all periods
    uint256 internal pendingRedemptionBurnie;       // total reserved BURNIE
    uint256 internal pendingRedemptionEthBase;      // current unresolved period ETH base
    uint256 internal pendingRedemptionBurnieBase;   // current unresolved period BURNIE base

    uint256 internal redemptionPeriodSupplySnapshot;
    uint32  internal redemptionPeriodIndex;
    uint256 internal redemptionPeriodBurned;

    // =====================================================================
    //                          CONSTANTS
    // =====================================================================

    /// @notice Initial supply (1 trillion tokens)
    uint256 private constant INITIAL_SUPPLY = 1_000_000_000_000 * 1e18;

    /// @dev Basis points denominator (100%)
    uint16 private constant BPS_DENOM = 10_000;

    /// @dev Creator allocation (20%)
    uint16 private constant CREATOR_BPS = 2000;

    /// @dev Non-creator pool distribution (BPS of total supply).
    uint16 private constant WHALE_POOL_BPS = 1000;
    uint16 private constant AFFILIATE_POOL_BPS = 3500;
    uint16 private constant LOOTBOX_POOL_BPS = 2000;
    uint16 private constant REWARD_POOL_BPS = 500;
    uint16 private constant EARLYBIRD_POOL_BPS = 1000;

    /// @dev Maximum base ethValueOwed a single wallet can accumulate per day via gambling burns
    uint256 private constant MAX_DAILY_REDEMPTION_EV = 160 ether;

    /// @dev Game contract reference for player actions and claimable queries
    IDegenerusGamePlayer private constant game = IDegenerusGamePlayer(ContractAddresses.GAME);

    /// @dev BURNIE token reference for payout accounting
    IDegenerusCoinPlayer private constant coin = IDegenerusCoinPlayer(ContractAddresses.COIN);
    /// @dev Coinflip contract for claimable BURNIE withdrawals during burns
    IBurnieCoinflipPlayer private constant coinflip =
        IBurnieCoinflipPlayer(ContractAddresses.COINFLIP);

    /// @dev DGNRS wrapper contract for burning wrapped DGNRS to receive sDGNRS backing
    IDegenerusStonkWrapper private constant dgnrsWrapper = IDegenerusStonkWrapper(ContractAddresses.DGNRS);

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



    // =====================================================================
    //                          CONSTRUCTOR
    // =====================================================================

    /// @notice Initializes token supply, distributes to pools, and claims whale pass for sDGNRS
    /// @dev Mints creator allocation to DGNRS wrapper address and pool allocations to this contract
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

        _mint(ContractAddresses.DGNRS, creatorAmount);
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
    //                          WRAPPER FUNCTIONS
    // =====================================================================

    /// @notice Transfer sDGNRS from the wrapper to a recipient (wrapper only)
    /// @dev Called by DGNRS contract when creator unwraps DGNRS to soulbound sDGNRS.
    ///      Direct balance manipulation avoids modifying _transfer authorization.
    /// @param to Recipient address
    /// @param amount Amount to transfer
    /// @custom:reverts Unauthorized If caller is not DGNRS contract
    /// @custom:reverts ZeroAddress If to is zero address
    /// @custom:reverts Insufficient If wrapper balance is insufficient
    function wrapperTransferTo(address to, uint256 amount) external {
        if (msg.sender != ContractAddresses.DGNRS) revert Unauthorized();
        if (to == address(0)) revert ZeroAddress();
        uint256 bal = balanceOf[ContractAddresses.DGNRS];
        if (amount > bal) revert Insufficient();
        unchecked {
            balanceOf[ContractAddresses.DGNRS] = bal - amount;
            balanceOf[to] += amount;
        }
        emit Transfer(ContractAddresses.DGNRS, to, amount);
    }

    // =====================================================================
    //                          PLAYER ACTIONS
    // =====================================================================

    /// @notice Advance the game on behalf of sDGNRS
    function gameAdvance() external {
        game.advanceGame();
    }

    /// @notice Claim whale pass on behalf of sDGNRS
    function gameClaimWhalePass() external {
        game.claimWhalePass(address(0));
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

    /// @notice sDGNRS supply held by governance-eligible addresses.
    /// @dev Excludes undistributed pools (held by this contract), DGNRS wrapper, and vault.
    function votingSupply() external view returns (uint256) {
        return totalSupply
            - balanceOf[address(this)]
            - balanceOf[ContractAddresses.DGNRS]
            - balanceOf[ContractAddresses.VAULT];
    }

    /// @notice Transfer sDGNRS from a reward pool to a recipient
    /// @dev Only callable by game contract. Transfers up to available balance if requested amount exceeds pool.
    /// @param pool Pool identifier
    /// @param to Recipient address
    /// @param amount Requested amount of sDGNRS to transfer
    /// @return transferred Actual amount transferred (may be less than requested if pool depleted)
    /// @custom:reverts Unauthorized If caller is not game contract
    /// @custom:reverts ZeroAddress If to is zero address
    function transferFromPool(Pool pool, address to, uint256 amount) external onlyGame returns (uint256 transferred) {
        if (amount == 0) return 0;
        if (to == address(0)) revert ZeroAddress();
        uint8 idx = _poolIndex(pool);
        uint256 available = poolBalances[idx];
        if (available == 0) return 0;
        if (amount > available) {
            amount = available;
        }
        unchecked {
            poolBalances[idx] = available - amount;
            balanceOf[address(this)] -= amount;
        }
        if (to == address(this)) {
            // Self-win: burn instead of no-op transfer, increasing value per remaining token
            totalSupply -= amount;
            emit Transfer(address(this), address(0), amount);
        } else {
            balanceOf[to] += amount;
            emit Transfer(address(this), to, amount);
        }
        emit PoolTransfer(pool, to, amount);
        return amount;
    }

    /// @notice Transfer sDGNRS between two reward pools
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

    /// @notice Burn all undistributed pool tokens at game over
    /// @dev Only callable by game contract. Burns this contract's own balance.
    function burnAtGameOver() external onlyGame {
        uint256 bal = balanceOf[address(this)];
        if (bal == 0) return;
        unchecked {
            balanceOf[address(this)] = 0;
            totalSupply -= bal;
        }
        delete poolBalances;
        emit Transfer(address(this), address(0), bal);
    }

    // =====================================================================
    //                          BURN (Public)
    // =====================================================================

    /// @notice Burn sDGNRS to claim proportional share of backing assets
    /// @dev Post-gameOver: deterministic payout. During game: gambling path with RNG roll.
    ///      Returns (0,0,0) during game; player must call claimRedemption() after resolution.
    /// @param amount Amount of sDGNRS to burn
    /// @return ethOut ETH received (deterministic path only)
    /// @return stethOut stETH received (deterministic path only)
    /// @return burnieOut BURNIE received (deterministic path only)
    /// @custom:reverts BurnsBlockedDuringRng If called during active VRF request (rngLocked).
    /// @custom:reverts BurnsBlockedDuringLiveness If liveness fired but gameOver has not yet latched.
    function burn(uint256 amount) external returns (uint256 ethOut, uint256 stethOut, uint256 burnieOut) {
        if (game.gameOver()) {
            (ethOut, stethOut) = _deterministicBurn(msg.sender, amount);
            return (ethOut, stethOut, 0);
        }
        if (game.livenessTriggered()) revert BurnsBlockedDuringLiveness();
        if (game.rngLocked()) revert BurnsBlockedDuringRng();
        _submitGamblingClaim(msg.sender, amount);
        return (0, 0, 0);
    }

    /// @notice Burn wrapped DGNRS (held in the DGNRS contract) to claim proportional backing assets
    /// @dev Burns the DGNRS wrapper tokens, then burns the corresponding sDGNRS backing held by the DGNRS contract.
    ///      Post-gameOver: deterministic payout. During game: gambling path.
    /// @param amount Amount of sDGNRS-equivalent to burn (from DGNRS wrapper balance)
    /// @return ethOut ETH received (deterministic path only)
    /// @return stethOut stETH received (deterministic path only)
    /// @return burnieOut BURNIE received (deterministic path only)
    /// @custom:reverts BurnsBlockedDuringRng If called during active VRF request (rngLocked).
    /// @custom:reverts BurnsBlockedDuringLiveness If liveness fired but gameOver has not yet latched.
    function burnWrapped(uint256 amount) external returns (uint256 ethOut, uint256 stethOut, uint256 burnieOut) {
        if (game.livenessTriggered() && !game.gameOver()) revert BurnsBlockedDuringLiveness();
        dgnrsWrapper.burnForSdgnrs(msg.sender, amount);
        if (game.gameOver()) {
            (ethOut, stethOut) = _deterministicBurnFrom(msg.sender, ContractAddresses.DGNRS, amount);
            return (ethOut, stethOut, 0);
        }
        if (game.rngLocked()) revert BurnsBlockedDuringRng();
        _submitGamblingClaimFrom(msg.sender, ContractAddresses.DGNRS, amount);
        return (0, 0, 0);
    }

    /// @dev Deterministic burn: player burns their own sDGNRS and receives backing assets directly.
    function _deterministicBurn(address player, uint256 amount) private returns (uint256 ethOut, uint256 stethOut) {
        return _deterministicBurnFrom(player, player, amount);
    }

    /// @dev Deterministic burn parameterized by beneficiary and burnFrom.
    ///      Used for the wrapped case where sDGNRS is burned from DGNRS contract's balance
    ///      but ETH/stETH goes to beneficiary. No BURNIE payout (gameOver burns are pure ETH/stETH).
    ///      Deducts pendingRedemptionEthValue to exclude reserved gambling burn amounts from payout (CP-08).
    function _deterministicBurnFrom(address beneficiary, address burnFrom, uint256 amount) private returns (uint256 ethOut, uint256 stethOut) {
        uint256 bal = balanceOf[burnFrom];
        if (amount == 0 || amount > bal) revert Insufficient();
        uint256 supplyBefore = totalSupply;

        uint256 ethBal = address(this).balance;
        uint256 stethBal = steth.balanceOf(address(this));
        uint256 claimableEth = _claimableWinnings();
        uint256 totalMoney = ethBal + stethBal + claimableEth - pendingRedemptionEthValue;
        uint256 totalValueOwed = (totalMoney * amount) / supplyBefore;

        unchecked {
            balanceOf[burnFrom] = bal - amount;
            totalSupply -= amount;
        }
        emit Transfer(burnFrom, address(0), amount);

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

        if (stethOut > 0) {
            if (!steth.transfer(beneficiary, stethOut)) revert TransferFailed();
        }

        if (ethOut > 0) {
            (bool success, ) = beneficiary.call{value: ethOut}("");
            if (!success) revert TransferFailed();
        }

        // No BURNIE payout for gameOver burns — pure ETH/stETH only
        emit Burn(beneficiary, amount, ethOut, stethOut, 0);
    }

    // =====================================================================
    //                       GAMBLING BURN FUNCTIONS
    // =====================================================================

    /// @notice Check whether there are unresolved gambling burn redemptions pending
    /// @return True if the current period has unresolved ETH or BURNIE base
    function hasPendingRedemptions() external view returns (bool) {
        return pendingRedemptionEthBase != 0 || pendingRedemptionBurnieBase != 0;
    }

    /// @notice Called by game contract to resolve the current redemption period with a dice roll
    /// @dev Adjusts segregated ETH by roll and returns rolled BURNIE amount for event emission.
    /// @param roll The random roll result (range 25-175, applied as percentage)
    /// @param flipDay Coinflip day index used for BURNIE gamble resolution
    function resolveRedemptionPeriod(uint16 roll, uint32 flipDay) external {
        if (msg.sender != ContractAddresses.GAME) revert Unauthorized();

        uint32 period = redemptionPeriodIndex;
        if (pendingRedemptionEthBase == 0 && pendingRedemptionBurnieBase == 0) return;

        // Adjust ETH segregation by roll
        uint256 rolledEth = (pendingRedemptionEthBase * roll) / 100;
        pendingRedemptionEthValue = pendingRedemptionEthValue - pendingRedemptionEthBase + rolledEth;
        pendingRedemptionEthBase = 0;

        // Compute rolled BURNIE (paid to redeemers via _payBurnie on claim)
        uint256 burnieToCredit = (pendingRedemptionBurnieBase * roll) / 100;

        // Release BURNIE reservation (redeemers claim via _payBurnie which draws balance then coinflip pool)
        pendingRedemptionBurnie -= pendingRedemptionBurnieBase;
        pendingRedemptionBurnieBase = 0;

        // Store period result
        redemptionPeriods[period] = RedemptionPeriod({
            roll: roll,
            flipDay: flipDay
        });

        emit RedemptionResolved(period, roll, burnieToCredit, flipDay);
    }

    /// @notice Claim a resolved gambling burn redemption
    /// @dev Requires period resolved (roll != 0). ETH is always claimable once period resolved.
    ///      50% of rolled ETH paid direct, 50% routed to Game as lootbox rewards (internal accounting).
    ///      If game is over, 100% paid as direct ETH (no lootboxes post-gameOver).
    ///      BURNIE requires coinflip resolution: paid on win, forfeited on loss or if unresolved.
    ///      If coinflip is unresolved, ETH is paid and BURNIE portion is kept for a second claim.
    function claimRedemption() external {
        address player = msg.sender;
        PendingRedemption storage claim = pendingRedemptions[player];
        if (claim.periodIndex == 0) revert NoClaim();

        RedemptionPeriod storage period = redemptionPeriods[claim.periodIndex];
        if (period.roll == 0) revert NotResolved();

        uint16 roll = period.roll;
        uint32 claimPeriodIndex = claim.periodIndex;
        uint16 claimActivityScore = claim.activityScore;

        // Total rolled ETH. Per-claimant floor division may leave up to (n-1) wei
        // dust in pendingRedemptionEthValue per period — economically negligible.
        uint256 totalRolledEth = (claim.ethValueOwed * roll) / 100;

        // 50/50 split (unless gameOver → 100% direct)
        bool isGameOver = game.gameOver();
        uint256 ethDirect;
        uint256 lootboxEth;
        if (isGameOver) {
            ethDirect = totalRolledEth;
        } else {
            ethDirect = totalRolledEth / 2;
            lootboxEth = totalRolledEth - ethDirect;
        }

        // BURNIE payout: depends on coinflip resolution
        uint256 burniePayout;
        bool flipResolved;
        {
            (uint16 rewardPercent, bool flipWon) = coinflip.getCoinflipDayResult(period.flipDay);
            flipResolved = (rewardPercent != 0 || flipWon);
            if (flipResolved && flipWon) {
                burniePayout = (claim.burnieOwed * roll * (100 + rewardPercent)) / 10000;
            }
        }

        // Release full ETH segregation (both direct and lootbox portions leave sDGNRS)
        pendingRedemptionEthValue -= totalRolledEth;

        if (flipResolved) {
            // Full claim: clear entirely
            delete pendingRedemptions[player];
        } else {
            // Partial claim: clear ETH portion, keep BURNIE for later
            claim.ethValueOwed = 0;
        }

        // Resolve lootboxes (Game debits from sDGNRS's claimable internally — no ETH transfer)
        if (lootboxEth != 0) {
            uint16 actScore = claimActivityScore > 0 ? claimActivityScore - 1 : 0;
            uint256 rngWord = game.rngWordForDay(claimPeriodIndex);
            uint256 entropy = uint256(keccak256(abi.encode(rngWord, player)));
            game.resolveRedemptionLootbox(player, lootboxEth, entropy, actScore);
        }

        // Pay BURNIE first (token transfer, not raw ETH)
        if (burniePayout != 0) {
            _payBurnie(player, burniePayout);
        }

        emit RedemptionClaimed(player, roll, flipResolved, ethDirect, burniePayout, lootboxEth);

        // Pay direct ETH last (raw .call to untrusted address)
        _payEth(player, ethDirect);
    }

    // =====================================================================
    //                          VIEW FUNCTIONS
    // =====================================================================

    /// @notice Preview ETH, stETH, and BURNIE output for burning sDGNRS
    /// @dev Reflects ETH-preferential payout logic using current balances and claimables.
    ///      Deducts pendingRedemptionEthValue and pendingRedemptionBurnie to exclude reserved
    ///      gambling burn amounts (CP-08). GameOver burns pay no BURNIE (pure ETH/stETH).
    /// @param amount Amount of sDGNRS to burn
    /// @return ethOut ETH that would be received
    /// @return stethOut stETH that would be received
    /// @return burnieOut BURNIE that would be received (0 during gameOver)
    function previewBurn(uint256 amount) external view returns (uint256 ethOut, uint256 stethOut, uint256 burnieOut) {
        uint256 supply = totalSupply;
        if (amount == 0 || amount > supply) return (0, 0, 0);

        uint256 ethBal = address(this).balance;
        uint256 stethBal = steth.balanceOf(address(this));
        uint256 claimableEth = _claimableWinnings();
        uint256 totalMoney = ethBal + stethBal + claimableEth - pendingRedemptionEthValue;
        uint256 totalValueOwed = (totalMoney * amount) / supply;

        uint256 ethAvailable = ethBal + claimableEth;
        if (ethAvailable > pendingRedemptionEthValue) {
            ethAvailable -= pendingRedemptionEthValue;
        } else {
            ethAvailable = 0;
        }
        if (totalValueOwed <= ethAvailable) {
            ethOut = totalValueOwed;
        } else {
            ethOut = ethAvailable;
            stethOut = totalValueOwed - ethOut;
        }

        // GameOver burns pay no BURNIE
        if (!game.gameOver()) {
            uint256 burnieBal = coin.balanceOf(address(this));
            uint256 claimableBurnie = coinflip.previewClaimCoinflips(address(this));
            uint256 totalBurnie = burnieBal + claimableBurnie - pendingRedemptionBurnie;
            burnieOut = (totalBurnie * amount) / supply;
        }
    }


    /// @notice Get BURNIE backing available for new burns (balance + claimable coinflips minus reserved)
    /// @return BURNIE backing value net of pending redemption reserves
    function burnieReserve() external view returns (uint256) {
        uint256 burnieBal = coin.balanceOf(address(this));
        uint256 claimableBurnie = coinflip.previewClaimCoinflips(address(this));
        return burnieBal + claimableBurnie - pendingRedemptionBurnie;
    }

    // =====================================================================
    //                          INTERNAL HELPERS
    // =====================================================================

    /// @dev Submit a gambling burn claim on behalf of player burning their own sDGNRS.
    function _submitGamblingClaim(address player, uint256 amount) private {
        _submitGamblingClaimFrom(player, player, amount);
    }

    /// @dev Core gambling burn logic. Burns sDGNRS from burnFrom, segregates proportional
    ///      ETH/BURNIE value for beneficiary, and records into the current period.
    ///      Enforces 50% supply cap per period and 160 ETH daily EV cap per wallet.
    ///      Snapshots activity score on first burn of each period for lootbox EV.
    function _submitGamblingClaimFrom(address beneficiary, address burnFrom, uint256 amount) private {
        uint256 bal = balanceOf[burnFrom];
        if (amount == 0 || amount > bal) revert Insufficient();

        // 50% supply cap per period
        uint32 currentPeriod = game.currentDayView();
        if (redemptionPeriodIndex != currentPeriod) {
            redemptionPeriodSupplySnapshot = totalSupply;
            redemptionPeriodIndex = currentPeriod;
            redemptionPeriodBurned = 0;
        }
        if (redemptionPeriodBurned + amount > redemptionPeriodSupplySnapshot / 2) revert Insufficient();
        redemptionPeriodBurned += amount;

        uint256 supplyBefore = totalSupply;

        // Compute proportional ETH value (subtract already-segregated)
        uint256 ethBal = address(this).balance;
        uint256 stethBal = steth.balanceOf(address(this));
        uint256 claimableEth = _claimableWinnings();
        uint256 totalMoney = ethBal + stethBal + claimableEth - pendingRedemptionEthValue;
        uint256 ethValueOwed = (totalMoney * amount) / supplyBefore;

        // Compute proportional BURNIE (subtract already-reserved)
        uint256 burnieBal = coin.balanceOf(address(this));
        uint256 claimableBurnie = coinflip.previewClaimCoinflips(address(this));
        uint256 totalBurnie = burnieBal + claimableBurnie - pendingRedemptionBurnie;
        uint256 burnieOwed = (totalBurnie * amount) / supplyBefore;

        // Burn sDGNRS
        unchecked {
            balanceOf[burnFrom] = bal - amount;
            totalSupply -= amount;
        }
        emit Transfer(burnFrom, address(0), amount);

        // Segregate
        pendingRedemptionEthValue += ethValueOwed;
        pendingRedemptionEthBase += ethValueOwed;
        pendingRedemptionBurnie += burnieOwed;
        pendingRedemptionBurnieBase += burnieOwed;

        // Stack into existing claim or start new
        PendingRedemption storage claim = pendingRedemptions[beneficiary];
        if (claim.periodIndex != 0 && claim.periodIndex != currentPeriod) {
            revert UnresolvedClaim();
        }

        // Enforce 160 ETH daily EV cap per wallet
        if (claim.ethValueOwed + ethValueOwed > MAX_DAILY_REDEMPTION_EV) revert ExceedsDailyRedemptionCap();

        claim.ethValueOwed += uint96(ethValueOwed);
        // burnieOwed: uint96 safe — max realistic BURNIE is ~2e24, well below uint96.max (~7.9e28).
        claim.burnieOwed += uint96(burnieOwed);
        claim.periodIndex = currentPeriod;

        // Snapshot activity score on first burn of period (0 = not yet set, stored as score + 1)
        if (claim.activityScore == 0) {
            claim.activityScore = uint16(game.playerActivityScore(beneficiary)) + 1;
        }

        emit RedemptionSubmitted(beneficiary, amount, ethValueOwed, burnieOwed, currentPeriod);
    }

    /// @dev Pay ETH to player, falling back to stETH if ETH balance is insufficient.
    function _payEth(address player, uint256 amount) private {
        if (amount == 0) return;
        uint256 ethBal = address(this).balance;
        uint256 claimableEth = _claimableWinnings();

        if (amount > ethBal && claimableEth != 0) {
            game.claimWinnings(address(0));
            ethBal = address(this).balance;
        }

        if (amount <= ethBal) {
            (bool success, ) = player.call{value: amount}("");
            if (!success) revert TransferFailed();
        } else {
            uint256 ethOut = ethBal;
            uint256 stethOut = amount - ethOut;
            if (ethOut > 0) {
                (bool success, ) = player.call{value: ethOut}("");
                if (!success) revert TransferFailed();
            }
            if (!steth.transfer(player, stethOut)) revert TransferFailed();
        }
    }

    /// @dev Pay BURNIE to player, drawing from balance then coinflip claimables.
    function _payBurnie(address player, uint256 amount) private {
        uint256 burnieBal = coin.balanceOf(address(this));
        uint256 payBal = amount <= burnieBal ? amount : burnieBal;
        uint256 remaining = amount - payBal;
        if (payBal != 0) {
            if (!coin.transfer(player, payBal)) revert TransferFailed();
        }
        if (remaining != 0) {
            coinflip.claimCoinflipsForRedemption(address(this), remaining);
            if (!coin.transfer(player, remaining)) revert TransferFailed();
        }
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


}
