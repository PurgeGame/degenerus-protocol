// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {ContractAddresses} from "./ContractAddresses.sol";
import {IStETH} from "./interfaces/IStETH.sol";
import {EntropyLib} from "./libraries/EntropyLib.sol";
import {GameTimeLib} from "./libraries/GameTimeLib.sol";


/// @notice Interface for game contract player-facing functions used by sDGNRS.
interface IDegenerusGamePlayer {
    /// @notice Advance the game to the next level/day.
    function advanceGame() external;
    /// @notice Crank the unified keeper router (advance + box opens), paying any earned bounty.
    function mintBurnie() external;
    /// @notice Queue this caller's perpetual tickets for levels 1-100 (VAULT/SDGNRS only, once).
    function initPerpetualTickets() external;
    /// @notice Start or extend a daily afking subscription for `player` (self when 0/msg.sender).
    /// @dev v55.0 ARCH-03: the afking subscription surface is GAME-resident (AfKing dissolved).
    ///      sDGNRS self-subscribes (player == address(this) == msg.sender) so the GAME's
    ///      SUB-02 self-consent path passes with no operator approval.
    function subscribe(
        address player,
        bool drainGameCreditFirst,
        bool useTickets,
        uint8 dailyQuantity,
        uint8 reinvestPct,
        address fundingSource
    ) external payable;
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
    /// @notice Get RNG word for a specific day.
    function rngWordForDay(uint24 day) external view returns (uint256);
    /// @notice Current mint price in wei (the active ticket level's price).
    function mintPrice() external view returns (uint256);
    /// @notice Get player's activity score.
    function playerActivityScore(address player) external view returns (uint256);
    /// @notice Resolve a redemption lootbox (sDGNRS forwards ETH as msg.value; GAME pulls any stETH remainder).
    function resolveRedemptionLootbox(address player, uint256 amount, uint256 rngWord, uint16 activityScore) external payable;
    /// @notice Credit a redemption's direct half to `player`'s game claimable (same ETH + stETH-remainder funding).
    function creditRedemptionDirect(address player, uint256 amount) external payable;
    /// @notice Segregate redemption ETH out of claimableWinnings[SDGNRS] into the sDGNRS balance.
    function pullRedemptionReserve(uint256 amount) external;
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
    /// @notice Settle-then-read sDGNRS's redeemable coinflip backing (claimableStored + carry, disjoint).
    function redeemableCoinBacking() external returns (uint256 backing);
    /// @notice Remove `base` (wei) of sDGNRS's BURNIE backing at submit (held → claimable → carry).
    function withdrawRedeemedBurnie(uint256 base) external;
    /// @notice Read a coinflip day's result (rewardPercent 0 = unresolved; win is true only on a resolved win).
    function getCoinflipDayResult(uint24 day) external view returns (uint16 rewardPercent, bool win);
    /// @notice Read a player's auto-rebuy config; `carry` is the rolling BURNIE bankroll.
    function coinflipAutoRebuyInfo(address player) external view returns (bool enabled, uint256 stop, uint256 carry, uint24 startDay);
    /// @notice Credit a BURNIE flip stake to a player (sDGNRS is an authorized flip creditor).
    function creditFlip(address player, uint256 amount) external;
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

    /// @notice Thrown when a gambling burn is attempted before the current day's VRF word is recorded
    ///         (the pre-request window). Admitting it would stamp a not-yet-drawn day, leaving the
    ///         lootbox leg's rngWordForDay(day + 1) zero and fully predictable at claim.
    error BurnsBlockedBeforeDailyRng();

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
    /// @param burnieEscrowed BURNIE backing (wei) removed from sDGNRS at submit and escrowed,
    ///        contingent on the resolving day's coinflip (paid to the redeemer only on a win)
    event RedemptionSubmitted(address indexed player, uint256 sdgnrsAmount, uint256 ethValueOwed, uint256 burnieEscrowed, uint24 periodIndex);

    /// @notice Emitted when a redemption period is resolved with a roll
    event RedemptionResolved(uint24 indexed periodIndex, uint16 roll);

    /// @notice Emitted when a player claims their resolved redemption.
    /// @param burniePaid Escrowed BURNIE (wei) minted to the redeemer as a flip credit — nonzero only
    ///        on a winning resolving-day coinflip; 0 on a loss or after gameOver (BURNIE ignored).
    event RedemptionClaimed(address indexed player, uint16 roll, uint256 ethPayout, uint256 lootboxEth, uint256 burniePaid);

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

    /// @notice Total supply of sDGNRS tokens.
    /// @dev Narrowed to uint128 (<= INITIAL_SUPPLY 1e30 << uint128 max 3.4e38, monotonically
    ///      non-increasing after construction) and co-located with the two redemption-reservation
    ///      scalars so the compiler packs all three into slot 0 (128+96+24 = 248/256 bits). Each
    ///      access is an independent masked SLOAD/SSTORE — read-fresh/write-fresh, identical to
    ///      separate slots (no manual cached word survives across a call). The public `totalSupply()`
    ///      / `pendingRedemptionEthValue()` / `pendingResolveDay()` getters preserve the original ABI.
    uint128 private _totalSupply;

    /// @dev Total physically-segregated redemption ETH across all unresolved periods. uint96 holds
    ///      7.9e28 wei (~658x the total ETH supply) — real-ETH-bounded, safe. Packed into slot 0.
    uint96 private _pendingRedemptionEthValue;

    /// @notice Wall-day of the currently-pending unresolved gambling-burn pool, or 0 if none.
    /// @dev Enforces INV-13 (single-pool invariant): at most one day's pool may be unresolved at any
    ///      time. Set by `_submitGamblingClaimFrom` on the first burn of a day; cleared by
    ///      `resolveRedemptionPeriod` when that day's pool resolves. Read by AdvanceModule to derive
    ///      `dayToResolve` directly. Game day 0 is unreachable by construction, so 0 unambiguously
    ///      means "no pool pending". Packed into slot 0.
    uint24 private _pendingResolveDay;

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
        PresaleBox
    }

    /// @notice Balances for each reward pool.
    /// @dev uint128 elements: the compiler packs the 5 lanes into 3 slots in index order
    ///      (Whale|Affiliate, Lootbox|Reward, PresaleBox), co-locating the warm whale/affiliate pair
    ///      debited together in a pass purchase. Each balance is <= INITIAL_SUPPLY (1e30) << uint128 max.
    uint128[5] private poolBalances;

    // =====================================================================
    //                   GAMBLING BURN STATE
    // =====================================================================

    struct PendingRedemption {
        uint96  ethValueOwed;   // base (100%) ETH-equivalent owed (max ~79B ETH)
        uint16  activityScore;  // snapshotted activity score + 1 (0 = not yet set)
        uint96  burnieEscrow;   // whole-token BURNIE removed from sDGNRS at submit; paid as a flip
                                // credit on a winning resolving-day coinflip (uint96 whole tokens ≫
                                // the uint128-bounded BURNIE supply ceiling), else forfeited.
    } // 96 + 16 + 96 = 208 bits (1 slot); composite outer key (player, day) carries the day reference per SPEC-02.

    /// @dev Per-day unresolved gambling-burn pool (SPEC-01, tightened per D-305-STRUCT-TIGHTEN-01
    ///      to 1 slot via denomination conversion).
    ///      Three fields packed into a single 256-bit slot (BURNIE is settled at submit, so no
    ///      per-day BURNIE base is tracked):
    ///        bits 0-63   : ethBase    — gwei units (1e9 wei divisor)
    ///        bits 64-127 : supplySnapshot — whole tokens (1e18 raw divisor)
    ///        bits 128-191: burned     — whole tokens (1e18 raw divisor)
    ///      Resolved days clear via `delete pendingByDay[day]` for storage refund.
    ///
    ///      Bounds (uint64.max = 1.844e19):
    ///        - ethBase: realistic per-day pool ≤ 10k wallets × 160 ETH cap = 1.6e15 gwei,
    ///          ~11500× under uint64.max. ETH dust sub-1-gwei truncated at write — cumulative
    ///          drift bounded by N×1 gwei per day, within INV-02 dust tolerance.
    ///        - supplySnapshot: INITIAL_SUPPLY = 1e12 whole tokens, 1.84e7× under uint64.max.
    ///        - burned: ≤ supplySnapshot/2, same headroom.
    ///
    ///      Min-burn floor (1 whole sDGNRS, `MIN_BURN_AMOUNT`) enforced via `BurnTooSmall` revert
    ///      so amount→burned ceiling-conversion always increments by ≥1, preserving INV-10.
    struct DayPending {
        uint64 ethBase;
        uint64 supplySnapshot;
        uint64 burned;
    }

    mapping(address => mapping(uint24 => PendingRedemption)) public pendingRedemptions;
    mapping(uint24 => uint16) public redemptionPeriods;   // day => resolved roll (0 = unresolved, 25-175 = resolved)

    mapping(uint24 => DayPending) internal pendingByDay;

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
    uint16 private constant AFFILIATE_POOL_BPS = 3000;
    uint16 private constant LOOTBOX_POOL_BPS = 2000;
    uint16 private constant REWARD_POOL_BPS = 1000;
    uint16 private constant PRESALE_BOX_POOL_BPS = 1000;

    /// @dev Maximum base ethValueOwed a single wallet can accumulate per day via gambling burns
    uint256 private constant MAX_DAILY_REDEMPTION_EV = 160 ether;

    /// @dev Maximum redemption roll (percent). The resolve roll is in [25, 175]; at submit the
    ///      MAX possible payout (base × MAX_ROLL / 100) is physically segregated out of
    ///      claimableWinnings[SDGNRS] into this contract so no concurrent claimable drain can
    ///      under-fund a later claim. Resolve lowers the reservation from MAX down to the rolled
    ///      amount (accounting only — the over-pull stays as free backing).
    uint256 private constant MAX_ROLL = 175;

    /// @dev Minimum gambling-burn amount (1 whole sDGNRS = 1e18 raw). Required by the 1-slot
    ///      DayPending packing: `burned` is stored in whole-token units, so sub-whole-token burns
    ///      would either round to 0 in cap accounting (INV-10 violation) or require ceiling-up
    ///      semantics. Floor enforced via `BurnTooSmall` revert in `_submitGamblingClaimFrom`.
    uint256 private constant MIN_BURN_AMOUNT = 1e18;

    /// @dev Minimum ETH size for a redemption lootbox (0.01 ETH). At claim the rolled value splits
    ///      50/50 into a direct-ETH leg and a lootbox leg; if the lootbox half lands below this floor
    ///      (i.e. total rolled value under ~0.02 ETH), the lootbox leg is dropped entirely. The player
    ///      keeps only the direct half plus the BURNIE share settled at submit; the dropped lootbox
    ///      value is NOT paid out to the player — it is forfeited back to sDGNRS's own claimable on the
    ///      Game as free backing, raising backing for remaining holders. Live-game only; gameOver claims
    ///      are already 100% direct.
    uint256 private constant MIN_REDEMPTION_LOOTBOX_ETH = 0.01 ether;

    /// @dev BURNIE base unit (1000 ETH worth) — the ETH→BURNIE conversion numerator for the keeper
    ///      box-bounty, matching the Game's PRICE_COIN_UNIT. BURNIE per ETH = PRICE_COIN_UNIT / mintPrice.
    uint256 private constant PRICE_COIN_UNIT = 1000 ether;

    /// @dev Keeper box-bounty target (ETH wei) per settled redemption claim. Sized so the BURNIE
    ///      bounty's ETH-value reimburses the ~48k-gas per-box settle at the ~0.5-gwei reference.
    ///      The reward is an illiquid coinflip credit, and every pending claim costs a real sDGNRS
    ///      gambling burn (>=1 whole token, one box per wallet per day) to create, so permissionlessly
    ///      cranking others' claims is liveness work rather than a clean farm.
    uint256 private constant BOX_BOUNTY_ETH_TARGET = 24_000_000_000_000;

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
        uint256 presaleBoxAmount = (INITIAL_SUPPLY * PRESALE_BOX_POOL_BPS) / BPS_DENOM;
        uint256 affiliateAmount = (INITIAL_SUPPLY * AFFILIATE_POOL_BPS) / BPS_DENOM;
        uint256 lootboxAmount = (INITIAL_SUPPLY * LOOTBOX_POOL_BPS) / BPS_DENOM;
        uint256 rewardAmount = (INITIAL_SUPPLY * REWARD_POOL_BPS) / BPS_DENOM;
        uint256 totalAllocated = creatorAmount + whaleAmount + presaleBoxAmount + affiliateAmount + lootboxAmount + rewardAmount;
        if (totalAllocated < INITIAL_SUPPLY) {
            uint256 dust;
            unchecked {
                dust = INITIAL_SUPPLY - totalAllocated;
            }
            lootboxAmount += dust;
        }
        uint256 poolTotal =
            whaleAmount + presaleBoxAmount + affiliateAmount + lootboxAmount + rewardAmount;

        _mint(ContractAddresses.DGNRS, creatorAmount);
        _mint(address(this), poolTotal);

        // Pool amounts are BPS slices of INITIAL_SUPPLY (1e30) << uint128 max — narrowing is safe.
        poolBalances[uint8(Pool.Whale)] = uint128(whaleAmount);
        poolBalances[uint8(Pool.Affiliate)] = uint128(affiliateAmount);
        poolBalances[uint8(Pool.Lootbox)] = uint128(lootboxAmount);
        poolBalances[uint8(Pool.Reward)] = uint128(rewardAmount);
        poolBalances[uint8(Pool.PresaleBox)] = uint128(presaleBoxAmount);

        game.claimWhalePass(address(0));

        // Queue this contract's perpetual tickets (levels 1-100). Moved out of the GAME
        // constructor so GAME's deploy stays under the per-tx gas cap.
        game.initPerpetualTickets();

        // SUB-09 protocol-owned self-subscription: claimable-only daily lootbox
        // buy of flat quantity 1 with a 2% claimable reinvest. Self-consent —
        // sDGNRS IS the player (player == msg.sender). sDGNRS holds the permanent
        // deity pass (granted in the DegenerusGame constructor), so the afking's
        // pass-OR-pay gate takes the free 30-day extend at zero cost.
        // v55.0 ARCH-03: the afking surface is GAME-resident (AfKing dissolved);
        // self-subscribe directly against the GAME (subscriber == msg.sender ⇒
        // the GAME's SUB-02 self-consent path, no operator approval needed).
        // Coinflip auto-rebuy is NOT enabled here: during the 20-day seed window
        // sDGNRS's daily flip wins mint to its wallet balance (redemption backing);
        // BurnieCoinflip arms perpetual auto-rebuy (0 take-profit) once the final
        // seeded day settles.
        game.subscribe(address(this), true, false, 1, 2, address(0));

        // Pre-approve GAME to pull stETH for both redemption claim legs. claimRedemption funds
        // each leg (resolveRedemptionLootbox / creditRedemptionDirect) with msg.value ETH and the
        // GAME pulls any remainder via transferFrom whenever liquid ETH is short, so the claim
        // can't strand mid-game on an ETH-only forward.
        steth.approve(ContractAddresses.GAME, type(uint256).max);
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

    /// @notice Crank the game keeper router on behalf of sDGNRS (advance + box opens)
    /// @dev Routes through mintBurnie so sDGNRS earns the keeper bounty for the work;
    ///      reverts NoWork() when nothing is due.
    function gameAdvance() external {
        game.mintBurnie();
    }

    /// @notice Claim whale pass on behalf of sDGNRS
    function gameClaimWhalePass() external {
        game.claimWhalePass(address(0));
    }

    // =====================================================================
    //                          DEPOSITS (Game Only)
    // =====================================================================

    /// @notice Receive ETH deposit from the game contract.
    /// @dev GAME deposits reserve ETH and the afking-funding claim/withdraw send-back (the Game's
    ///      `.call` has msg.sender == GAME). Accounting-safe: reserves are read live via
    ///      address(this).balance everywhere, so no running counter is kept here.
    /// @custom:reverts Unauthorized If caller is not the game contract.
    receive() external payable {
        if (msg.sender != ContractAddresses.GAME) revert Unauthorized();
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

    /// @notice Total supply of sDGNRS tokens (ERC20). ABI-preserving view over the packed slot-0 field.
    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    /// @notice Total physically-segregated redemption ETH across all unresolved periods (wei).
    /// @dev ABI-preserving view over the packed slot-0 field (cross-contract + harness readers).
    function pendingRedemptionEthValue() external view returns (uint256) {
        return _pendingRedemptionEthValue;
    }

    /// @notice Wall-day of the currently-pending unresolved gambling-burn pool, or 0 if none.
    /// @dev ABI-preserving view over the packed slot-0 field (AdvanceModule reads this to derive
    ///      `dayToResolve`).
    function pendingResolveDay() external view returns (uint24) {
        return _pendingResolveDay;
    }

    /// @notice sDGNRS supply held by governance-eligible addresses.
    /// @dev Excludes undistributed pools (held by this contract), DGNRS wrapper, and vault.
    function votingSupply() external view returns (uint256) {
        return _totalSupply
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
            poolBalances[idx] = uint128(available - amount);
            balanceOf[address(this)] -= amount;
        }
        if (to == address(this)) {
            // Self-win: burn instead of no-op transfer, increasing value per remaining token
            _totalSupply = uint128(_totalSupply - amount);
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
            poolBalances[fromIdx] = uint128(available - amount);
        }
        poolBalances[toIdx] = uint128(poolBalances[toIdx] + amount);
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
            _totalSupply = uint128(_totalSupply - bal);
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
        // burnForSdgnrs makes no external calls, so gameOver cannot change
        // between the gate and the branch — one read serves both.
        bool isOver = game.gameOver();
        if (!isOver && game.livenessTriggered()) revert BurnsBlockedDuringLiveness();
        dgnrsWrapper.burnForSdgnrs(msg.sender, amount);
        if (isOver) {
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
        uint256 supplyBefore = _totalSupply;

        uint256 ethBal = address(this).balance;
        uint256 stethBal = steth.balanceOf(address(this));
        uint256 claimableEth = _claimableWinnings();
        uint256 totalMoney = ethBal + stethBal + claimableEth - _pendingRedemptionEthValue;
        uint256 totalValueOwed = (totalMoney * amount) / supplyBefore;

        unchecked {
            balanceOf[burnFrom] = bal - amount;
            _totalSupply = uint128(_totalSupply - amount);
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
    /// @return True if `pendingByDay[day]` has a non-zero ETH base.
    function hasPendingRedemptions(uint24 day) external view returns (bool) {
        return pendingByDay[day].ethBase != 0;
    }

    /// @notice Called by game contract to resolve day `dayToResolve`'s gambling-burn pool with a dice roll (SPEC-03).
    /// @dev Per SPEC-04 (c): writes `redemptionPeriods[dayToResolve]`, emits `RedemptionResolved`,
    ///      then deletes `pendingByDay[dayToResolve]` for storage refund. Each day's mapping slot is
    ///      distinct, so no later resolve can overwrite a resolved day's roll (V-184 closure clause).
    ///      ETH-only: at submit the MAX (175%) payout was physically segregated and tracked in
    ///      pendingRedemptionEthValue; here that reservation is lowered from MAX to the rolled
    ///      amount (accounting only — the over-pull stays in this contract as free backing, no
    ///      transfer back to claimable). BURNIE is already fully settled at submit (no roll).
    /// @param roll The random roll result (range 25-175, applied as percentage).
    /// @param dayToResolve Wall-clock day whose pool this call resolves.
    function resolveRedemptionPeriod(uint16 roll, uint24 dayToResolve) external {
        if (msg.sender != ContractAddresses.GAME) revert Unauthorized();

        DayPending storage pool = pendingByDay[dayToResolve];
        // Convert ethBase from gwei back to wei for the cumulative-scalar reconciliation.
        // Drift vs claim-side sums bounded ≤ N gwei per day (INV-02 dust tolerance).
        uint256 ethBase = uint256(pool.ethBase) * 1e9;
        if (ethBase == 0) return;

        // Lower the cumulative segregation from the MAX (175%) pulled at submit down to the rolled
        // amount. The MAX − rolled difference is over-pulled ETH that stays as free backing.
        uint256 segregatedMax = (ethBase * MAX_ROLL) / 100;
        uint256 rolledEth = (ethBase * roll) / 100;
        // Checked arithmetic preserved (reverts on underflow as before); narrowing cast is safe.
        _pendingRedemptionEthValue = uint96(_pendingRedemptionEthValue - segregatedMax + rolledEth);

        // Store per-day result (write before emit before delete per SPEC-04 (c))
        redemptionPeriods[dayToResolve] = roll;

        emit RedemptionResolved(dayToResolve, roll);

        // Storage refund: free the day's pool slot per SPEC-04 (c).
        delete pendingByDay[dayToResolve];

        // Clear the single-pool sentinel if this resolve targeted the stamped day (INV-13).
        if (_pendingResolveDay == dayToResolve) _pendingResolveDay = 0;
    }

    /// @notice Claim a resolved gambling-burn redemption for `player` on day `day` (SPEC-02).
    /// @dev Requires `redemptionPeriods[day] != 0` (period resolved). Reads composite-keyed
    ///      `pendingRedemptions[player][day]`; deletes that slot per SPEC-04 (d).
    ///      ETH-only: BURNIE is fully settled at submit (no claim-time BURNIE leg).
    ///      Live game: PERMISSIONLESS — anyone may settle `player`'s claim, all value to `player`.
    ///      Both halves of the rolled ETH route to the Game (50% credits the player's claimable
    ///      winnings, 50% funds lootbox rewards), so a third-party trigger pushes no ETH and the
    ///      winner holds no exclusive timing control over the lootbox draw.
    ///      Post-gameOver: SELF-CLAIM only — 100% direct push with no lootbox leg (no timing
    ///      edge); a game-claimable credit would forfeit in the post-gameover sweep.
    /// @param player Claimant whose redemption to settle.
    /// @param day Wall-clock day whose claim to settle.
    function claimRedemption(address player, uint24 day) external {
        uint16 roll = redemptionPeriods[day];
        if (roll == 0) revert NotResolved();

        bool isGameOver = game.gameOver();
        if (isGameOver && player != msg.sender) revert Unauthorized();

        if (!_claimRedemptionFor(player, day, roll, isGameOver)) revert NoClaim();
    }

    /// @notice Claim resolved gambling-burn redemptions for a batch of players on day `day`.
    /// @dev Players with nothing pending for `day` are skipped, not reverted, so one stale
    ///      address can't poison a mass-claim sweep. Post-gameOver only the caller's own entry
    ///      settles (self-claim rule); all others are skipped.
    /// @param players Claimants whose redemptions to settle.
    /// @param day Wall-clock day whose claims to settle.
    function claimRedemptionMany(address[] calldata players, uint24 day) external {
        uint16 roll = redemptionPeriods[day];
        if (roll == 0) revert NotResolved();

        bool isGameOver = game.gameOver();
        uint256 settled;
        for (uint256 i; i < players.length; ++i) {
            address player = players[i];
            if (isGameOver && player != msg.sender) continue;
            if (_claimRedemptionFor(player, day, roll, isGameOver)) {
                unchecked {
                    ++settled;
                }
            }
        }

        // Keeper bounty: a small BURNIE flip-credit per box actually settled this call, paid to the
        // caller during a live game (no liveness need post-gameOver, where only self-claims settle).
        // Counts only settled boxes — empty (player, day) slots are skipped and earn nothing. The
        // ETH-value tracks the per-box settle gas at the 0.5-gwei reference (BURNIE per ETH =
        // PRICE_COIN_UNIT / mintPrice), so the credit holds its gas-reimbursement value across the
        // price curve. sDGNRS is an authorized flip creditor, so this credits AS sDGNRS.
        if (!isGameOver && settled != 0) {
            coinflip.creditFlip(
                msg.sender,
                (settled * BOX_BOUNTY_ETH_TARGET * PRICE_COIN_UNIT) / game.mintPrice()
            );
        }
    }

    /// @dev Shared settle core for the single and batch claim entry points. Callers must have
    ///      verified the period is resolved and (post-gameOver) the self-claim rule; the
    ///      pending-claim existence check lives here (one slot load), returning false on an
    ///      empty (player, day) slot so the batch path skips and the single path reverts.
    function _claimRedemptionFor(address player, uint24 day, uint16 roll, bool isGameOver) private returns (bool) {
        PendingRedemption memory claim = pendingRedemptions[player][day];
        // Existence: a live-game claim is reachable on a nonzero ETH base OR a nonzero BURNIE escrow
        // (a gwei-floored zero-ETH claim can still owe escrowed BURNIE). Post-gameOver BURNIE is
        // worthless and ignored, so only the ETH base keeps a claim alive.
        if (claim.ethValueOwed == 0 && (isGameOver || claim.burnieEscrow == 0)) return false;
        uint16 claimActivityScore = claim.activityScore;

        // Total rolled ETH. Per-claimant floor division may leave up to (n-1) wei
        // dust in pendingRedemptionEthValue per period — economically negligible.
        uint256 totalRolledEth = (claim.ethValueOwed * roll) / 100;

        // 50/50 split (unless gameOver → 100% direct)
        uint256 ethDirect;
        uint256 lootboxEth;
        uint256 forfeitEth;
        if (isGameOver) {
            ethDirect = totalRolledEth;
        } else {
            ethDirect = totalRolledEth / 2;
            lootboxEth = totalRolledEth - ethDirect;
            // Drop dust-sized lootboxes: when the lootbox half lands below the 0.01 ETH floor (rolled
            // value under ~0.02 ETH), the lootbox leg is dropped. Its value is NOT paid to the player
            // and NOT turned into a lootbox — it is forfeited back to sDGNRS's own claimable on the
            // Game (its canonical backing ledger), raising backing for remaining holders. The player
            // keeps only the direct half (plus the BURNIE share settled at submit). The lootbox leg
            // is then skipped by its `lootboxEth != 0` guard and the forfeit leg credits sDGNRS.
            if (lootboxEth < MIN_REDEMPTION_LOOTBOX_ETH) {
                forfeitEth = lootboxEth;
                lootboxEth = 0;
            }
        }

        // Release the rolled ETH segregation (both direct and lootbox portions leave sDGNRS).
        // The MAX − rolled over-pull (segregated at submit) stays in this contract as free backing.
        // Checked arithmetic preserved; narrowing cast is safe (result is the remaining segregated ETH).
        _pendingRedemptionEthValue = uint96(_pendingRedemptionEthValue - totalRolledEth);

        // Full claim: clear the (player, day) slot entirely per SPEC-04 (d).
        delete pendingRedemptions[player][day];

        // Contingent BURNIE escrow: the whole-token slice removed from sDGNRS's backing at submit is
        // minted to the redeemer as a flip credit ONLY if the resolving day's (day + 1) coinflip won;
        // a loss pays nothing (symmetric with the auto-rebuy carry zeroing for every holder on a
        // losing flip). Read the ABSOLUTE day+1 result, never a resolve-time word — stall-correct.
        // Post-gameOver BURNIE is worthless and skipped entirely. The slot is already cleared (CEI)
        // and creditFlip makes no callback into this contract.
        uint256 burniePaid;
        if (!isGameOver && claim.burnieEscrow != 0) {
            // In a live game day + 1 is normally resolved by claim time (resolveRedemptionPeriod for
            // `day` runs on the advance that settles day + 1). `win` is true only on a resolved win;
            // a resolved loss — or an unresolved day in the narrow level-0 gameOver pre-latch window,
            // where day + 1's coinflip is never stored — reads false and correctly pays nothing.
            (, bool burnieWon) = coinflip.getCoinflipDayResult(day + 1);
            if (burnieWon) {
                burniePaid = uint256(claim.burnieEscrow) * 1e18;
                coinflip.creditFlip(player, burniePaid);
            }
        }

        emit RedemptionClaimed(player, roll, ethDirect, lootboxEth, burniePaid);

        if (isGameOver) {
            // 100% direct push (self-claim enforced by callers; the untrusted .call comes after
            // the slot delete above — CEI).
            _payEth(player, ethDirect);
            return true;
        }

        // Live game: both legs move to the Game. Each leg mixes ETH and stETH like _payEth —
        // msg.value carries the ETH on hand, the GAME pulls any remainder as stETH — so a
        // mid-game ETH-depleted contract can't strand the claim on an ETH-only forward. The MAX
        // reservation guarantees ETH + stETH >= rolled, so the stETH remainder is always coverable.
        if (lootboxEth != 0) {
            uint16 actScore = claimActivityScore > 0 ? claimActivityScore - 1 : 0;
            // Key the lootbox draw to the NEXT day's word (day+1) - unknown when the burn was
            // submitted (day+1 isn't drawn yet), so a post-advance burn can't grind a known
            // draw. Only reached when !gameOver (lootboxEth != 0); in a live game day+1's word
            // is always set by claim time (the daily advance, or gap-backfill after a stall).
            uint256 rngWord = game.rngWordForDay(day + 1);
            uint256 entropy = EntropyLib.hash2(rngWord, uint256(uint160(player)));
            uint256 bal = address(this).balance;
            uint256 ethForLootbox = bal < lootboxEth ? bal : lootboxEth;
            game.resolveRedemptionLootbox{value: ethForLootbox}(player, lootboxEth, entropy, actScore);
        }

        // Direct half: credit into the player's game claimable (a permissionless trigger must
        // not push ETH at the player); the player withdraws via the access-gated claimWinnings.
        if (ethDirect != 0) {
            uint256 bal = address(this).balance;
            uint256 ethForDirect = bal < ethDirect ? bal : ethDirect;
            game.creditRedemptionDirect{value: ethForDirect}(player, ethDirect);
        }

        // Forfeited dust-lootbox half → sDGNRS's OWN claimable on the Game (player == address(this)),
        // using the same ETH/stETH funding mix as the direct leg. With this leg the full rolled amount
        // leaves the contract (direct half to the player, forfeited half to sDGNRS), so it reconciles
        // exactly with the pendingRedemptionEthValue release — no ETH is stranded in the contract.
        if (forfeitEth != 0) {
            uint256 bal = address(this).balance;
            uint256 ethForForfeit = bal < forfeitEth ? bal : forfeitEth;
            game.creditRedemptionDirect{value: ethForForfeit}(address(this), forfeitEth);
        }
        return true;
    }

    // =====================================================================
    //                          VIEW FUNCTIONS
    // =====================================================================

    /// @notice Preview ETH, stETH, and BURNIE output for burning sDGNRS
    /// @dev Reflects ETH-preferential payout logic using current balances and claimables.
    ///      Deducts pendingRedemptionEthValue to exclude the ETH physically segregated for
    ///      gambling-burn claimants (CP-08). GameOver burns pay no BURNIE (pure ETH/stETH).
    /// @param amount Amount of sDGNRS to burn
    /// @return ethOut ETH that would be received
    /// @return stethOut stETH that would be received
    /// @return burnieOut BURNIE that would be received (0 during gameOver)
    function previewBurn(uint256 amount) external view returns (uint256 ethOut, uint256 stethOut, uint256 burnieOut) {
        uint256 supply = _totalSupply;
        if (amount == 0 || amount > supply) return (0, 0, 0);

        uint256 ethBal = address(this).balance;
        uint256 stethBal = steth.balanceOf(address(this));
        uint256 claimableEth = _claimableWinnings();
        uint256 totalMoney = ethBal + stethBal + claimableEth - _pendingRedemptionEthValue;
        uint256 totalValueOwed = (totalMoney * amount) / supply;

        uint256 ethAvailable = ethBal + claimableEth;
        if (ethAvailable > _pendingRedemptionEthValue) {
            ethAvailable -= _pendingRedemptionEthValue;
        } else {
            ethAvailable = 0;
        }
        if (totalValueOwed <= ethAvailable) {
            ethOut = totalValueOwed;
        } else {
            ethOut = ethAvailable;
            stethOut = totalValueOwed - ethOut;
        }

        // GameOver burns pay no BURNIE. The full sDGNRS BURNIE backing is held wallet balance +
        // claimable coinflip winnings + the auto-rebuy carry (where sDGNRS's BURNIE lives post-day-20).
        // No reserve term: a submit removes its escrowed slice from this backing immediately, so these
        // live reads are already net of outstanding redemptions. Best-effort (the carry/claimable can
        // momentarily lag a stalled advance); truncated to whole BURNIE to match the settled submit path.
        if (!game.gameOver()) {
            uint256 burnieBal = coin.balanceOf(address(this));
            uint256 claimableBurnie = coinflip.previewClaimCoinflips(address(this));
            (, , uint256 carry, ) = coinflip.coinflipAutoRebuyInfo(address(this));
            uint256 totalBurnie = burnieBal + claimableBurnie + carry;
            burnieOut = ((totalBurnie * amount) / supply / 1e18) * 1e18;
        }
    }


    /// @notice Get BURNIE backing available for new burns (balance + claimable coinflips + carry).
    /// @dev No reserve subtraction: a submit removes its escrowed slice from this backing immediately,
    ///      so these live reads are already net of outstanding redemptions. Includes the auto-rebuy
    ///      carry, where sDGNRS's BURNIE lives once perpetual auto-rebuy arms post-day-20.
    /// @return BURNIE backing value (balance + claimable coinflips + auto-rebuy carry).
    function burnieReserve() external view returns (uint256) {
        uint256 burnieBal = coin.balanceOf(address(this));
        uint256 claimableBurnie = coinflip.previewClaimCoinflips(address(this));
        (, , uint256 carry, ) = coinflip.coinflipAutoRebuyInfo(address(this));
        return burnieBal + claimableBurnie + carry;
    }

    // =====================================================================
    //                          INTERNAL HELPERS
    // =====================================================================

    /// @dev Submit a gambling burn claim on behalf of player burning their own sDGNRS.
    function _submitGamblingClaim(address player, uint256 amount) private {
        _submitGamblingClaimFrom(player, player, amount);
    }

    /// @dev Core gambling burn logic. Burns sDGNRS from burnFrom, physically segregates the MAX
    ///      (175%) proportional ETH payout out of claimableWinnings[SDGNRS] into this contract's
    ///      balance (fail-closed if it cannot), and settles the proportional BURNIE share entirely
    ///      at submit as a conserved coinflip flip-credit (no reserve, no roll, no claim-time BURNIE).
    ///      Enforces 50% supply cap per day (SPEC-05 lazy-init) and 160 ETH per-(wallet, day) EV cap.
    ///      Per SPEC-02, writes the per-claim slot at composite key `pendingRedemptions[beneficiary][currentPeriod]`,
    ///      so a wallet can accumulate distinct claims across multiple unresolved days.
    function _submitGamblingClaimFrom(address beneficiary, address burnFrom, uint256 amount) private {
        uint256 bal = balanceOf[burnFrom];
        if (amount == 0 || amount > bal) revert Insufficient();
        if (amount < MIN_BURN_AMOUNT) revert BurnTooSmall();

        // Wall-clock day index computed locally: currentDayView() is a pure function of
        // block.timestamp (GameTimeLib), so this is identical to game.currentDayView() without the CALL.
        uint24 currentPeriod = GameTimeLib.currentDayIndex();

        // Admit gambling burns only once the current day's VRF word is recorded. The pre-request
        // window is blocked here; the request->fulfilment window is already blocked by the rngLocked
        // guard in burn()/burnWrapped(). This pins the stamp to a drawn day (currentPeriod ==
        // dailyIdx), so the pool always resolves on the NEXT day's draw and the lootbox leg's
        // rngWordForDay(currentPeriod + 1) reads that resolving word — never a not-yet-drawn (zero,
        // fully predictable) future word.
        if (game.rngWordForDay(currentPeriod) == 0) revert BurnsBlockedBeforeDailyRng();

        // Single-pool invariant (INV-13): if any prior day still holds an unresolved pool,
        // block this burn. AdvanceModule resolves the stamped day on the next successful advance;
        // burns are only permitted to land in today's pool or onto an already-active today's pool.
        uint24 stamp = _pendingResolveDay;
        if (stamp != 0 && stamp != currentPeriod) revert PriorDayUnresolved();
        if (stamp == 0) _pendingResolveDay = currentPeriod;

        DayPending storage pool = pendingByDay[currentPeriod];

        // 50% supply cap per day — lazy-init the snapshot on the first burn of the day (SPEC-05).
        // supplySnapshot stored in whole tokens (1e18 raw divisor): INITIAL_SUPPLY = 1e30 → 1e12
        // whole tokens, comfortably under uint64.max (~1.84e19).
        if (pool.supplySnapshot == 0 && pool.burned == 0) {
            pool.supplySnapshot = uint64(_totalSupply / 1e18);
        }
        // Ceiling-divide amount→whole tokens so cap accounting is conservative even when amount
        // isn't an exact multiple of 1e18. INV-10 (per-day supply cap) holds: pool.burned * 1e18
        // is always ≥ actual cumulative burns for the day.
        uint256 amountWhole = (amount + 1e18 - 1) / 1e18;
        if (uint256(pool.burned) + amountWhole > uint256(pool.supplySnapshot) / 2) revert Insufficient();
        pool.burned += uint64(amountWhole);

        uint256 supplyBefore = _totalSupply;

        // Compute proportional ETH base. pendingRedemptionEthValue is subtracted because that ETH
        // (already segregated into this contract's balance for prior gambling-burn claimants) is
        // owed and must not back a new claim.
        uint256 ethBal = address(this).balance;
        uint256 stethBal = steth.balanceOf(address(this));
        uint256 claimableEth = _claimableWinnings();
        uint256 totalMoney = ethBal + stethBal + claimableEth - _pendingRedemptionEthValue;
        uint256 ethValueOwed = (totalMoney * amount) / supplyBefore;

        // Compute the proportional BURNIE share of sDGNRS's full BURNIE backing: held wallet balance
        // + settled coinflip backing (claimableStored + auto-rebuy carry, where sDGNRS's BURNIE lives
        // post-day-20). redeemableCoinBacking settles sDGNRS to current so its two components are
        // disjoint. The share is truncated to whole BURNIE; the sub-token dust stays as backing for
        // remaining holders. No reserve subtraction: the slice is removed from the backing just below.
        uint256 burnieHeld = coin.balanceOf(address(this));
        uint256 coinBacking = coinflip.redeemableCoinBacking();
        uint256 burnieEscrowWhole = ((burnieHeld + coinBacking) * amount) / supplyBefore / 1e18;

        // Snap ETH base to gwei at the source (D-305-GWEI-SNAP-01). Eliminates pool↔cumulative-scalar
        // drift by ensuring pool.ethBase × 1e9 reconstructs the exact sum-of-claims at resolve.
        unchecked {
            ethValueOwed = (ethValueOwed / 1e9) * 1e9;
        }

        // Burn sDGNRS
        unchecked {
            balanceOf[burnFrom] = bal - amount;
            _totalSupply = uint128(_totalSupply - amount);
        }
        emit Transfer(burnFrom, address(0), amount);

        // === Reserve the MAX (175%) payout for this burn (pure ETH OR pure stETH) ===
        // Pull the MAX so no concurrent claimable drain (AfKing SUB-09 self-sub, a 2nd same-day
        // claimant, claimWinnings) can under-fund a later claim. pullRedemptionReserve segregates the
        // reservation as pure ETH (moved out of claimableWinnings[SDGNRS]) when the ETH side covers it,
        // else pure stETH backed by sDGNRS's own balance (no game-side move); it reverts fail-closed
        // only if NEITHER pure leg covers. pendingRedemptionEthValue below records the segregated MAX.
        //
        // The per-day pool tracks the BASE (100%) in gwei; resolve reconstructs the segregated MAX
        // as floor(poolBaseWei × MAX_ROLL / 100). To make the cumulative increment here reconcile
        // EXACTLY with that resolve-time subtraction (no rounding drift, no underflow), the per-claim
        // increment is the telescoping delta of floor(cumulativeBaseWei × MAX_ROLL / 100) before vs
        // after adding this claim's base. Summed over the day it equals the resolve value exactly.
        uint256 prevBaseWei = uint256(pool.ethBase) * 1e9;
        pool.ethBase += uint64(ethValueOwed / 1e9);
        uint256 newBaseWei = uint256(pool.ethBase) * 1e9;
        uint256 maxIncrement = (newBaseWei * MAX_ROLL) / 100 - (prevBaseWei * MAX_ROLL) / 100;
        if (maxIncrement != 0) {
            game.pullRedemptionReserve(maxIncrement);
        }
        // Checked add preserved; narrowing cast is safe (cumulative segregated ETH << uint96 max).
        _pendingRedemptionEthValue = uint96(_pendingRedemptionEthValue + maxIncrement);

        // === BURNIE: remove the escrowed share from sDGNRS's backing now; pay later on the flip ===
        // The whole-token slice is destroyed out of sDGNRS's backing (held → claimable → carry) and
        // escrowed against this (beneficiary, day) slot. It is minted to the beneficiary as a flip
        // credit ONLY if the resolving day's (currentPeriod + 1) coinflip wins — resolved at claim.
        // On a loss it pays nothing, symmetric with the auto-rebuy carry zeroing for every holder on a
        // losing flip. Removing it here keeps the next submit's backing read net of outstanding escrow.
        uint256 burnieEscrowWei;
        if (burnieEscrowWhole != 0) {
            burnieEscrowWei = burnieEscrowWhole * 1e18;
            coinflip.withdrawRedeemedBurnie(burnieEscrowWei);
        }

        // Composite-keyed per-claim slot for (beneficiary, currentPeriod) (SPEC-02): records the ETH
        // base and the contingent whole-token BURNIE escrow removed from sDGNRS's backing above.
        PendingRedemption storage claim = pendingRedemptions[beneficiary][currentPeriod];

        // Enforce 160 ETH per-(wallet, day) EV cap on the BASE (resets naturally on a new day under composite keying).
        if (claim.ethValueOwed + ethValueOwed > MAX_DAILY_REDEMPTION_EV) revert ExceedsDailyRedemptionCap();

        claim.ethValueOwed += uint96(ethValueOwed);
        if (burnieEscrowWhole != 0) {
            claim.burnieEscrow += uint96(burnieEscrowWhole);
        }

        // Snapshot activity score on first burn of day (0 = not yet set, stored as score + 1)
        if (claim.activityScore == 0) {
            claim.activityScore = uint16(game.playerActivityScore(beneficiary)) + 1;
        }

        emit RedemptionSubmitted(beneficiary, amount, ethValueOwed, burnieEscrowWei, currentPeriod);
    }

    /// @dev Pay the redemption from this contract's balance: ETH first, falling back to stETH if the
    ///      ETH balance is insufficient. No game.claimWinnings pull — at submit, pullRedemptionReserve
    ///      either physically moved the ETH out of claimableWinnings[SDGNRS] into this contract (ETH
    ///      leg) or left sDGNRS's own stETH backing the reservation (stETH leg); either way the
    ///      backing is already in this contract's balance.
    function _payEth(address player, uint256 amount) private {
        if (amount == 0) return;
        uint256 ethBal = address(this).balance;

        if (amount <= ethBal) {
            (bool success, ) = player.call{value: amount}("");
            if (!success) revert TransferFailed();
        } else {
            uint256 ethOut = ethBal;
            uint256 stethOut = amount - ethOut;
            // stETH first, untrusted ETH .call LAST (CEI): otherwise a reentrant burn()/claim in the
            // player's ETH hook sees the in-flight stETH (no longer reserved — claimRedemption already
            // decremented pendingRedemptionEthValue) as free backing and over-reserves, breaking SOLVENCY-01.
            if (!steth.transfer(player, stethOut)) revert TransferFailed();
            if (ethOut > 0) {
                (bool success, ) = player.call{value: ethOut}("");
                if (!success) revert TransferFailed();
            }
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
            // Only reached in the constructor (totals <= INITIAL_SUPPLY 1e30 << uint128 max).
            _totalSupply = uint128(_totalSupply + amount);
            balanceOf[to] += amount;
        }
        emit Transfer(address(0), to, amount);
    }


}
