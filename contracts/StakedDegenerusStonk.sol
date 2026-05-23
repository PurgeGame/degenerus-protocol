// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {ContractAddresses} from "./ContractAddresses.sol";
import {IStETH} from "./interfaces/IStETH.sol";


/// @notice Interface for game contract player-facing functions used by sDGNRS.
interface IDegenerusGamePlayer {
    /// @notice Advance the game to the next level/day.
    function advanceGame() external;
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
    /// @notice Configure auto-rebuy mode for coinflips (player == self for sDGNRS).
    function setCoinflipAutoRebuy(address player, bool enabled, uint256 takeProfit) external;
}

/// @notice Interface for the AfKing subscription keeper used by sDGNRS.
interface IAfKingSubscribe {
    /// @notice Start or extend a daily subscription for `player` (self when 0/msg.sender).
    function subscribe(
        address player,
        bool drainGameCreditFirst,
        bool useTickets,
        uint8 dailyQuantity,
        uint8 reinvestPct
    ) external payable;
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

    /// @notice Thrown when a player tries to claim with no pending redemption
    error NoClaim();

    /// @notice Thrown when a player tries to claim before the period is resolved
    error NotResolved();

    /// @notice Thrown when a gambling burn would exceed 160 ETH daily EV cap per wallet
    error ExceedsDailyRedemptionCap();

    /// @notice Thrown when a gambling burn is attempted while a prior day's pool remains unresolved.
    /// @dev Enforces the single-pool invariant (INV-13): at most one day's gambling-burn pool
    ///      can be unresolved at any time. Prevents multi-day pool accumulation during RNG stalls.
    error PriorDayUnresolved();

    /// @notice Thrown when a gambling burn amount is below the 1-whole-sDGNRS minimum (1e18 raw).
    /// @dev D-305-DUST-FLOOR-01: required by the 1-slot DayPending packing — `burned` is stored
    ///      in whole-token units (1e18 divisor), so sub-whole-token burns would either skip
    ///      cap accounting (INV-10 violation) or accumulate without bound.
    error BurnTooSmall();


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
        uint16  activityScore;  // snapshotted activity score + 1 (0 = not yet set)
    } // 96 + 96 + 16 = 208 bits (1 slot); composite outer key (player, day) carries the day reference per SPEC-02

    struct RedemptionPeriod {
        uint16  roll;           // 0 = unresolved, 25-175 = resolved
        uint32  flipDay;        // coinflip day for BURNIE gamble
    }

    /// @dev Per-day unresolved gambling-burn pool (SPEC-01, tightened per D-305-STRUCT-TIGHTEN-01
    ///      to 1 slot via denomination conversion).
    ///      All four fields packed into a single 256-bit slot:
    ///        bits 0-63   : ethBase    — gwei units (1e9 wei divisor)
    ///        bits 64-127 : burnieBase — gwei-equivalent units (1e9 raw BURNIE divisor)
    ///        bits 128-191: supplySnapshot — whole tokens (1e18 raw divisor)
    ///        bits 192-255: burned     — whole tokens (1e18 raw divisor)
    ///      Resolved days clear via `delete pendingByDay[day]` for storage refund.
    ///
    ///      Bounds (uint64.max = 1.844e19):
    ///        - ethBase: realistic per-day pool ≤ 10k wallets × 160 ETH cap = 1.6e15 gwei,
    ///          ~11500× under uint64.max. ETH dust sub-1-gwei truncated at write — cumulative
    ///          drift bounded by N×1 gwei per day, within INV-02 dust tolerance.
    ///        - burnieBase: same denomination, same headroom.
    ///        - supplySnapshot: INITIAL_SUPPLY = 1e12 whole tokens, 1.84e7× under uint64.max.
    ///        - burned: ≤ supplySnapshot/2, same headroom.
    ///
    ///      Min-burn floor (1 whole sDGNRS, `MIN_BURN_AMOUNT`) enforced via `BurnTooSmall` revert
    ///      so amount→burned ceiling-conversion always increments by ≥1, preserving INV-10.
    struct DayPending {
        uint64 ethBase;
        uint64 burnieBase;
        uint64 supplySnapshot;
        uint64 burned;
    }

    mapping(address => mapping(uint32 => PendingRedemption)) public pendingRedemptions;
    mapping(uint32 => RedemptionPeriod) public redemptionPeriods;

    uint256 public pendingRedemptionEthValue;      // total segregated ETH across all periods
    uint256 internal pendingRedemptionBurnie;       // total reserved BURNIE
    mapping(uint32 => DayPending) internal pendingByDay;

    /// @notice Wall-day of the currently-pending unresolved gambling-burn pool, or 0 if none.
    /// @dev Enforces INV-13 (single-pool invariant): at most one day's pool may be unresolved at
    ///      any time. Set by `_submitGamblingClaimFrom` on first burn of a day; cleared by
    ///      `resolveRedemptionPeriod` when that day's pool is resolved. Read by AdvanceModule to
    ///      derive `dayToResolve` directly — replaces the brittle `day - 1` derivation under
    ///      multi-day RNG stalls. Game day 0 is unreachable by construction
    ///      (`_simulatedDayIndexAt` underflows at day-1 → day 1 is the lowest legitimate value),
    ///      so 0 unambiguously means "no pool pending".
    uint32 public pendingResolveDay;

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

    /// @dev Minimum gambling-burn amount (1 whole sDGNRS = 1e18 raw). Required by the 1-slot
    ///      DayPending packing: `burned` is stored in whole-token units, so sub-whole-token burns
    ///      would either round to 0 in cap accounting (INV-10 violation) or require ceiling-up
    ///      semantics. Floor enforced via `BurnTooSmall` revert in `_submitGamblingClaimFrom`.
    uint256 private constant MIN_BURN_AMOUNT = 1e18;

    /// @dev Game contract reference for player actions and claimable queries
    IDegenerusGamePlayer private constant game = IDegenerusGamePlayer(ContractAddresses.GAME);

    /// @dev BURNIE token reference for payout accounting
    IDegenerusCoinPlayer private constant coin = IDegenerusCoinPlayer(ContractAddresses.COIN);
    /// @dev Coinflip contract for claimable BURNIE withdrawals during burns
    IBurnieCoinflipPlayer private constant coinflip =
        IBurnieCoinflipPlayer(ContractAddresses.COINFLIP);

    /// @dev AfKing subscription keeper for sDGNRS's protocol-owned self-subscription
    IAfKingSubscribe private constant afKing =
        IAfKingSubscribe(ContractAddresses.AF_KING);

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

        // SUB-09 protocol-owned self-subscription: claimable-only daily lootbox
        // buy of flat quantity 1 with a 2% claimable reinvest, plus full BURNIE-flip
        // recycle at the kept flat recycle rate. Self-consent — sDGNRS IS the player
        // (player == msg.sender). sDGNRS holds the permanent deity pass (granted in
        // the DegenerusGame constructor), so the keeper's pass-OR-pay gate takes the
        // free 30-day extend at zero cost.
        afKing.subscribe(address(this), true, false, 1, 2);
        coinflip.setCoinflipAutoRebuy(address(this), true, 0);
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

    /// @notice Check whether day `day` has an unresolved gambling-burn pool (SPEC-03).
    /// @param day Wall-clock day to query.
    /// @return True if `pendingByDay[day]` has non-zero ETH or BURNIE base.
    function hasPendingRedemptions(uint32 day) external view returns (bool) {
        return pendingByDay[day].ethBase != 0 || pendingByDay[day].burnieBase != 0;
    }

    /// @notice Called by game contract to resolve day `dayToResolve`'s gambling-burn pool with a dice roll (SPEC-03).
    /// @dev Per SPEC-04 (c): writes `redemptionPeriods[dayToResolve]`, emits `RedemptionResolved`,
    ///      then deletes `pendingByDay[dayToResolve]` for storage refund. Each day's mapping slot is
    ///      distinct, so no later resolve can overwrite a resolved day's roll (V-184 closure clause).
    /// @param roll The random roll result (range 25-175, applied as percentage).
    /// @param flipDay Coinflip day index used for BURNIE gamble resolution.
    /// @param dayToResolve Wall-clock day whose pool this call resolves.
    function resolveRedemptionPeriod(uint16 roll, uint32 flipDay, uint32 dayToResolve) external {
        if (msg.sender != ContractAddresses.GAME) revert Unauthorized();

        DayPending storage pool = pendingByDay[dayToResolve];
        // Convert pool fields from gwei back to wei for the cumulative-scalar reconciliation.
        // Drift vs claim-side sums bounded ≤ N gwei per day (INV-02 dust tolerance).
        uint256 ethBase = uint256(pool.ethBase) * 1e9;
        uint256 burnieBase = uint256(pool.burnieBase) * 1e9;
        if (ethBase == 0 && burnieBase == 0) return;

        // Adjust cumulative ETH segregation by roll for this day's pool
        uint256 rolledEth = (ethBase * roll) / 100;
        pendingRedemptionEthValue = pendingRedemptionEthValue - ethBase + rolledEth;

        // Compute rolled BURNIE (paid to redeemers via _payBurnie on claim)
        uint256 burnieToCredit = (burnieBase * roll) / 100;

        // Release cumulative BURNIE reservation for this day's pool
        pendingRedemptionBurnie -= burnieBase;

        // Store per-day result (write before emit before delete per SPEC-04 (c))
        redemptionPeriods[dayToResolve] = RedemptionPeriod({
            roll: roll,
            flipDay: flipDay
        });

        emit RedemptionResolved(dayToResolve, roll, burnieToCredit, flipDay);

        // Storage refund: 3 slots (ethBase, burnieBase, supplySnapshot+burned) free per SPEC-04 (c).
        delete pendingByDay[dayToResolve];

        // Clear the single-pool sentinel if this resolve targeted the stamped day (INV-13).
        if (pendingResolveDay == dayToResolve) pendingResolveDay = 0;
    }

    /// @notice Claim a resolved gambling-burn redemption for day `day` (SPEC-02).
    /// @dev Requires `redemptionPeriods[day].roll != 0` (period resolved). Reads composite-keyed
    ///      `pendingRedemptions[msg.sender][day]`; deletes that slot on full-claim path per SPEC-04 (d).
    ///      Partial-claim branch (coinflip unresolved) preserves the slot with `ethValueOwed = 0` so
    ///      BURNIE can still be claimed later. 50% of rolled ETH paid direct, 50% routed to Game as
    ///      lootbox rewards (internal accounting); post-gameOver, 100% paid as direct ETH.
    /// @param day Wall-clock day whose claim this caller is settling.
    function claimRedemption(uint32 day) external {
        address player = msg.sender;
        PendingRedemption storage claim = pendingRedemptions[player][day];
        if (claim.ethValueOwed == 0 && claim.burnieOwed == 0) revert NoClaim();

        RedemptionPeriod storage period = redemptionPeriods[day];
        if (period.roll == 0) revert NotResolved();

        uint16 roll = period.roll;
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
            // Full claim: clear the (player, day) slot entirely per SPEC-04 (d).
            delete pendingRedemptions[player][day];
        } else {
            // Partial claim: clear ETH portion, keep BURNIE for later
            claim.ethValueOwed = 0;
        }

        // Resolve lootboxes (Game debits from sDGNRS's claimable internally — no ETH transfer)
        if (lootboxEth != 0) {
            uint16 actScore = claimActivityScore > 0 ? claimActivityScore - 1 : 0;
            uint256 rngWord = game.rngWordForDay(day);
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
    ///      ETH/BURNIE value for beneficiary into the current wall-day's pool (SPEC-01).
    ///      Enforces 50% supply cap per day (SPEC-05 lazy-init) and 160 ETH per-(wallet, day) EV cap.
    ///      Per SPEC-02, writes the per-claim slot at composite key `pendingRedemptions[beneficiary][currentPeriod]`,
    ///      so a wallet can accumulate distinct claims across multiple unresolved days.
    function _submitGamblingClaimFrom(address beneficiary, address burnFrom, uint256 amount) private {
        uint256 bal = balanceOf[burnFrom];
        if (amount == 0 || amount > bal) revert Insufficient();
        if (amount < MIN_BURN_AMOUNT) revert BurnTooSmall();

        uint32 currentPeriod = game.currentDayView();

        // Single-pool invariant (INV-13): if any prior day still holds an unresolved pool,
        // block this burn. AdvanceModule resolves the stamped day on the next successful advance;
        // burns are only permitted to land in today's pool or onto an already-active today's pool.
        uint32 stamp = pendingResolveDay;
        if (stamp != 0 && stamp != currentPeriod) revert PriorDayUnresolved();
        if (stamp == 0) pendingResolveDay = currentPeriod;

        DayPending storage pool = pendingByDay[currentPeriod];

        // 50% supply cap per day — lazy-init the snapshot on the first burn of the day (SPEC-05).
        // supplySnapshot stored in whole tokens (1e18 raw divisor): INITIAL_SUPPLY = 1e30 → 1e12
        // whole tokens, comfortably under uint64.max (~1.84e19).
        if (pool.supplySnapshot == 0 && pool.burned == 0) {
            pool.supplySnapshot = uint64(totalSupply / 1e18);
        }
        // Ceiling-divide amount→whole tokens so cap accounting is conservative even when amount
        // isn't an exact multiple of 1e18. INV-10 (per-day supply cap) holds: pool.burned * 1e18
        // is always ≥ actual cumulative burns for the day.
        uint256 amountWhole = (amount + 1e18 - 1) / 1e18;
        if (uint256(pool.burned) + amountWhole > uint256(pool.supplySnapshot) / 2) revert Insufficient();
        pool.burned += uint64(amountWhole);

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

        // Snap to gwei at the source (D-305-GWEI-SNAP-01). Eliminates pool↔cumulative-scalar drift
        // by ensuring every downstream use of ethValueOwed/burnieOwed is a multiple of 1e9 — so
        // pool.ethBase × 1e9 reconstructs the exact sum-of-claims at resolve. Sub-gwei dust is
        // truncated per SPEC-04 (b) "zero-rounded ethValueOwed proceeds" semantics, applied
        // uniformly. Per-claim sub-roll floor-div dust (existing v43 behavior) is unchanged.
        unchecked {
            ethValueOwed = (ethValueOwed / 1e9) * 1e9;
            burnieOwed = (burnieOwed / 1e9) * 1e9;
        }

        // Burn sDGNRS
        unchecked {
            balanceOf[burnFrom] = bal - amount;
            totalSupply -= amount;
        }
        emit Transfer(burnFrom, address(0), amount);

        // Segregate — cumulative globals stay in wei (uint256); per-day pool bases denominated in
        // gwei (1e9 divisor) to fit uint64. Sub-gwei dust on the pool side bounded ≤ 1 gwei per
        // claim — drift across the cumulative scalar reconciliation at resolve is bounded by
        // N×1 gwei and remains within INV-02's dust tolerance (analyzed in 305-01-SUMMARY).
        pendingRedemptionEthValue += ethValueOwed;
        pool.ethBase += uint64(ethValueOwed / 1e9);
        pendingRedemptionBurnie += burnieOwed;
        pool.burnieBase += uint64(burnieOwed / 1e9);

        // Composite-keyed per-claim slot for (beneficiary, currentPeriod) (SPEC-02).
        PendingRedemption storage claim = pendingRedemptions[beneficiary][currentPeriod];

        // Enforce 160 ETH per-(wallet, day) EV cap (resets naturally on a new day under composite keying).
        if (claim.ethValueOwed + ethValueOwed > MAX_DAILY_REDEMPTION_EV) revert ExceedsDailyRedemptionCap();

        claim.ethValueOwed += uint96(ethValueOwed);
        // burnieOwed: uint96 safe — max realistic BURNIE is ~2e24, well below uint96.max (~7.9e28).
        claim.burnieOwed += uint96(burnieOwed);

        // Snapshot activity score on first burn of day (0 = not yet set, stored as score + 1)
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
