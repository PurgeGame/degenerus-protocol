// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/*
 * TERMS OF INTERACTION — submitting a transaction to this contract accepts them.
 *
 * THIS IS GAMBLING. Outcomes are decided by chance. You can lose everything you put in
 * simply by being unlucky. That is the software working exactly as intended. Do not
 * commit funds you are not prepared to lose entirely.
 *
 * The deployed bytecode is the entire agreement, and controls over every comment, name,
 * document and statement made about it. It has been audited but is not proven correct:
 * it may contain defects the author did not find, and by interacting with it you accept
 * that risk in full.
 *
 * Any state transition the code permits is authorised — including one that exploits a
 * defect, and including sequences the author did not intend or foresee. A bug is not a
 * breach of these terms. There is no unwritten rule behind the code for a permitted
 * transaction to violate, and no unauthorised access to this contract.
 *
 * You bear all resulting loss, whether it follows from chance or from a defect. There is
 * no refund, no rollback and no privileged party able to restore a position.
 *
 * Provided AS IS, without warranty of any kind. Full text: TERMS.md
 */

import {ContractAddresses} from "../ContractAddresses.sol";
import {IVRFCoordinator} from "../interfaces/IVRFCoordinator.sol";
import {IsDGNRS} from "../interfaces/IsDGNRS.sol";
import {IDegenerusAffiliate} from "../interfaces/IDegenerusAffiliate.sol";
import {IDegenerusCoin} from "../interfaces/IDegenerusCoin.sol";
import {ICoinflip} from "../interfaces/ICoinflip.sol";
import {IDegenerusParimutuel} from "../interfaces/IDegenerusParimutuel.sol";
import {IDegenerusQuests} from "../interfaces/IDegenerusQuests.sol";
import {BitPackingLib} from "../libraries/BitPackingLib.sol";
import {GameTimeLib} from "../libraries/GameTimeLib.sol";
import {ActivityCurveLib} from "../libraries/ActivityCurveLib.sol";
import {PriceLookupLib} from "../libraries/PriceLookupLib.sol";
import {MintPaymentKind} from "../interfaces/IDegenerusGame.sol";

/**
 * @title DegenerusGameStorage
 * @author Burnie Degenerus
 * @notice Shared storage layout between DegenerusGame and its delegatecall modules.
 *
 * @dev ARCHITECTURE OVERVIEW
 * -----------------------------------------------------------------------------
 * This contract defines the canonical storage layout for the Degenerus game ecosystem.
 * It is inherited by:
 *   - DegenerusGame (main contract, holds actual state)
 *   - DegenerusGameAdvanceModule (delegatecall module)
 *   - DegenerusGameJackpotModule (delegatecall module)
 *   - DegenerusGameMintModule (delegatecall module)
 *   - DegenerusGameLootboxModule (delegatecall module)
 *   - DegenerusGameWhaleModule (delegatecall module)
 *   - DegenerusGameBoonModule (delegatecall module)
 *   - DegenerusGameDecimatorModule (delegatecall module)
 *   - DegenerusGameDegeneretteModule (delegatecall module)
 *   - DegenerusGameGameOverModule (delegatecall module)
 *   - DegenerusGameBingoModule (delegatecall module)
 *   - GameAfkingModule (delegatecall module)
 *   - DegenerusGameFoilPackModule (delegatecall module)
 *
 * DELEGATECALL PATTERN:
 * When DegenerusGame calls `module.delegatecall(...)`, the module's code executes
 * in the context of DegenerusGame's storage. This means:
 *   1. Storage slots MUST match exactly between the main contract and all modules.
 *   2. This contract ensures slot alignment by providing a single source of truth.
 *   3. Never add storage variables to module contracts — they would collide with game storage.
 *
 * STORAGE SLOT LAYOUT (EVM assigns slots sequentially):
 * -----------------------------------------------------------------------------
 *
 * +---------------------------------------------------------------------------------+
 * | EVM SLOT 0 (32 bytes) -- Timing, per-level flags, counters, buffer, freeze      |
 * +---------------------------------------------------------------------------------+
 * | [0:3]   purchaseStartDay         uint24   Deploy-relative day idx level began   |
 * | [3:6]   dailyIdx                 uint24   Deploy-rel day idx of last sealed day |
 * | [6:12]  rngRequestTime           uint48   When last VRF request was fired       |
 * | [12:15] level                    uint24   Current jackpot level (starts at 0)   |
 * | [15:16] jackpotPhaseFlag         bool     Payout mode: purchase(F)/jackpot(T)   |
 * | [16:17] jackpotCounter           uint8    Jackpots processed this level         |
 * | [17:18] lastPurchaseDay          bool     Prize target met flag                 |
 * | [18:19] decWindowOpen            bool     Decimator window latch                |
 * | [19:20] rngLockedFlag            bool     Daily RNG lock (jackpot window)       |
 * | [20:21] phaseTransitionActive    bool     Level transition in progress          |
 * | [21:22] gameOver                 bool     Terminal state flag                   |
 * | [22:23] dailyJackpotCoinTicketsPending bool Split jackpot pending flag          |
 * | [23:24] compressedJackpotFlag    uint8    0=norm 1=comp 2=turbo 3=turbo+owed    |
 * | [24:25] ticketsFullyProcessed    bool     Read slot fully drained flag          |
 * | [25:26] ticketWriteSlot          bool     Double-buffer write toggle            |
 * | [26:27] prizePoolFrozen          bool     Prize pool freeze active flag         |
 * | [27:28] presaleOver              bool     Coin-presale-box terminal latch       |
 * | [28:29] subsFullyProcessed       bool     Afking STAGE drain-complete flag      |
 * | [29:30] presaleDrained           bool     All presale boxes opened (sweep)      |
 * | [30:31] ticketRedemptionOpen     bool     FLIP ticket purchase window latch     |
 * | [31:32] decDayOneActive          bool     Decimator day-one burn bonus latch    |
 * +---------------------------------------------------------------------------------+
 *   Total: 32 bytes used (0 bytes padding -- FULL)
 *
 * +---------------------------------------------------------------------------------+
 * | EVM SLOT 1 (32 bytes) -- Prize Pools                                            |
 * +---------------------------------------------------------------------------------+
 * | [0:16]  currentPrizePool         uint128  Active prize pool for current level   |
 * | [16:32] claimablePool            uint128  Aggregate ETH liability for claims    |
 * +---------------------------------------------------------------------------------+
 *   Total: 32 bytes used (0 bytes padding -- FULL)
 *
 * SLOTS 2+ -- Full-width variables, arrays, and mappings
 * -----------------------------------------------------------------------------
 * Each uint256, array length, or mapping root occupies its own slot.
 * Dynamic arrays: length at slot N, data at keccak256(N).
 * Mappings: value at keccak256(key . slot).
 *
 * SECURITY CONSIDERATIONS
 * -----------------------------------------------------------------------------
 * 1. SLOT STABILITY: Never reorder, remove, or change types of existing variables.
 *    Append-only additions are safe for non-upgradeable contracts.
 *
 * 2. DELEGATECALL SAFETY: All modules inherit this exact layout. If a module
 *    declared its own storage variables, they would occupy the same slots as
 *    game data, causing catastrophic corruption.
 *
 * 3. ACCESS CONTROL: Most state is `internal`; `level`, `gameOver`, and `boonPacked` are `public`
 *    (auto-getters). Other external reads go through explicit getters in DegenerusGame.
 *
 * 4. INITIALIZATION: Default values are set inline. For critical variables:
 *    - purchaseStartDay = deploy day index (set in constructor via GameTimeLib.currentDayIndex())
 *    - jackpotPhaseFlag = false (purchase phase)
 *    - decWindowOpen = false (opens at level 4 jackpot phase start)
 *    - levelPrizePool[level] is the per-level ratchet target; levelPrizePool[0] is set to
 *      BOOTSTRAP_PRIZE_POOL (50 ether) in the constructor (also the zero-fallback in the view)
 *
 * 5. OVERFLOW PROTECTION: Solidity 0.8+ provides automatic overflow checks.
 *    `unchecked` blocks in modules are intentional optimizations for safe ops.
 *
 * 6. MAPPING COLLISION: Mappings use keccak256(key . slot), making collisions
 *    computationally infeasible. The lvlTraitEntry nested mapping uses
 *    keccak256(traitId . keccak256(level . slot)) for data location.
 *
 * UPGRADE NOTES
 * -----------------------------------------------------------------------------
 * This contract is NOT upgradeable (no proxy pattern).
 *
 * VARIABLE DOCUMENTATION
 * -----------------------------------------------------------------------------
 * See inline comments for each variable group below.
 */

abstract contract DegenerusGameStorage {
    // =========================================================================
    // CONSTANTS
    // =========================================================================

    IDegenerusCoin internal constant coin =
        IDegenerusCoin(ContractAddresses.COIN);
    ICoinflip internal constant coinflip =
        ICoinflip(ContractAddresses.COINFLIP);
    IDegenerusQuests internal constant quests =
        IDegenerusQuests(ContractAddresses.QUESTS);
    IDegenerusAffiliate internal constant affiliate =
        IDegenerusAffiliate(ContractAddresses.AFFILIATE);
    IsDGNRS internal constant dgnrs =
        IsDGNRS(ContractAddresses.SDGNRS);
    IDegenerusParimutuel internal constant parimutuel =
        IDegenerusParimutuel(ContractAddresses.PARIMUTUEL);

    /// @dev Deity pass activity bonus (+80 points).
    uint16 internal constant DEITY_PASS_ACTIVITY_BONUS_POINTS = 80;

    /// @dev Hard ceiling on the total activity score (points). Quest completions are
    ///      uncapped, so this bounds the sum. Set one below uint16 max because the
    ///      sDGNRS redemption snapshot stores uint16(score) + 1 (a 0 = unset sentinel),
    ///      which would overflow at 65,535.
    uint16 internal constant ACTIVITY_SCORE_HARD_CAP_POINTS = 65_534;

    /// @dev Floor streak points for active pass holders (50 points).
    uint16 internal constant PASS_STREAK_FLOOR_POINTS = 50;

    /// @dev Floor mint count points for active pass holders (25 points).
    uint16 internal constant PASS_MINT_COUNT_FLOOR_POINTS = 25;

    /// @dev Conversion factor for FLIP token amounts.
    ///      FLIP uses 18 decimals, so 1000 FLIP = 1e21 base units.
    ///      Used in price calculations: price / PRICE_COIN_UNIT = FLIP per mint.
    uint256 internal constant PRICE_COIN_UNIT = 1000 ether;

    /// @dev Scale factor for fractional ticket calculations (2 decimal places).
    ///      100 means 1 ticket = 100 scaled units.
    uint256 internal constant QTY_SCALE = 100;

    /// @dev Marker bit on entriesOwedPacked values: set by the drain once a player's
    ///      owed balance has been divided by 2^snapShift, so a budget-split resume
    ///      never divides the same balance twice.
    uint48 internal constant SNAP_DONE_BIT = uint48(1) << 40;



    /// @dev ETH threshold for whale pass claim eligibility from lootbox wins.
    uint256 internal constant LOOTBOX_CLAIM_THRESHOLD = 5 ether;

    /// @dev Bootstrap value for prize pool target at level 1 (before any level completes).
    ///      levelPrizePool[0] is initialized to this value conceptually.
    uint256 internal constant BOOTSTRAP_PRIZE_POOL = 50 ether;

    /// @dev Current-pool daily jackpot percentage is rolled in JackpotModule.
    ///      Days 1-4 use a random 6%-14% slice of remaining currentPrizePool.
    ///      Day 5 pays 100% of the remaining currentPrizePool.

    /// @dev Bit mask for ticket queue double-buffer key encoding.
    ///      Set bit 23 of the uint24 level key to distinguish write/read slots.
    ///      Max real level: 2^22 - 1 = 4,194,303 (game would take millennia).
    uint24 internal constant TICKET_SLOT_BIT = 1 << 23;

    /// @dev Bit mask for far-future ticket key encoding.
    ///      Set bit 22 of the uint24 level key to create a third key space
    ///      disjoint from both double-buffer slots (bit 23).
    ///      Far-future = tickets targeting > currentLevel + 5.
    ///      Three key spaces: Slot0 [0x000000-0x3FFFFF], FF [0x400000-0x7FFFFF],
    ///      Slot1 [0x800000-0xBFFFFF]. Disjoint for all lvl < 2^22.
    uint24 internal constant TICKET_FAR_FUTURE_BIT = 1 << 22;

    /// @dev Deploy idle timeout in days (mirrors DegenerusGame / AdvanceModule).
    uint32 internal constant _DEPLOY_IDLE_TIMEOUT_DAYS = 365;

    /// @dev VRF stall duration that flips liveness from "grace" to "VRF-dead game-over".
    ///      Below this, liveness is suppressed so players can propose a coordinator rotation.
    ///      At or above, liveness fires so the game-over fallback path engages.
    uint48 internal constant _VRF_GRACE_PERIOD = 14 days;

    /// @dev RNG-stall length (in sealed days) past which the VRF-death deadman fires regardless
    ///      of phase. dailyIdx only advances on a successful day-seal, so currentDay - dailyIdx
    ///      counts days since the last good word; it freezes during ANY stall (dead coordinator,
    ///      unfilled LINK, request-from-zero revert) and clears only after game-over latches.
    ///      Far above the in-phase clocks, so it never fires on a healthy game.
    uint24 internal constant _VRF_DEADMAN_DAYS = 120;

    // =========================================================================
    // Errors
    // =========================================================================

    /// @dev Gas-minimal revert signal. Matches codebase convention (DegenerusGame, modules).
    error E();

    /// @dev Reverts when a permissionless far-future ticket write is attempted during VRF commitment window.
    error RngLocked();

    // Shared named reverts (inherited by every Game module). Each carries no data — the name
    // alone identifies the failing guard for off-chain decoding. Domain-specific reverts stay
    // declared locally in the module that owns them.
    error OnlyDelegatecall();   // nested-dispatch guard: address(this) != GAME
    error OnlySelf();           // caller must be the contract itself
    error OnlyAdmin();          // admin-only entrypoint
    error OnlyVault();          // vault / vault-owner entrypoint
    error OnlySDGNRS();         // sDGNRS-contract-only entrypoint
    error ThanosBounds();       // thanos declaration outside its sanity bounds
    error OnlyCoordinator();    // VRF-coordinator-only callback
    error Unauthorized();       // generic access-control failure
    error GameOver();           // the game has ended (or the liveness-timeout game-over trigger is active)
    error NotStarted();         // the game / phase has not started
    error EmptyRevert();        // a delegatecall reverted with empty returndata
    error EmptyReturn();        // a delegatecall returned empty data where a value was required
    error TransferFailed();     // a native / token transfer failed
    error Insolvent();          // a balance / pool draw would underflow the backing
    error Invariant();          // an internal invariant was violated
    error ZeroAddress();        // a required address argument was the zero address
    error ZeroValue();          // a required value argument was zero
    error NothingToClaim();     // no balance available to claim
    error AlreadySwept();       // the target was already swept / finalized
    error LengthMismatch();     // array-length arguments disagree

    // =========================================================================
    // SLOT 0: Timing, FSM, Counters, Flags, Buffer, Freeze
    // =========================================================================
    // These variables pack into a single 32-byte storage slot for gas efficiency.
    // Order matters: EVM packs from low to high within a slot.
    // All 32 bytes are used — see the SLOT 0 table in the file header for byte offsets.

    /// @dev Game day index when the purchase phase (or deploy) began.
    ///      Initialized to GameTimeLib.currentDayIndex() in the constructor.
    ///      Used for death clock, distress mode, future take curve, and gap extension.
    ///
    ///      SECURITY: uint24 holds day indices up to ~16.7 million — effectively unlimited
    ///      for day-granularity counters.
    uint24 internal purchaseStartDay;

    /// @dev Monotonically increasing "day" counter derived from block timestamps.
    ///      Incremented during game progression; used to key RNG words and track
    ///      daily jackpot eligibility. NOT tied to calendar days — it's the deploy-relative day index (frozen during a VRF stall).
    ///
    ///      SECURITY: uint24 holds day indices up to ~16.7 million — effectively unlimited
    ///      for day-granularity counters.
    uint24 internal dailyIdx;

    /// @dev Timestamp when the last VRF (Chainlink) request was submitted.
    ///      Used for timeout detection: rngRequestTime != 0 means a VRF request
    ///      is in-flight or awaiting processing.
    ///
    ///      SECURITY: Timeout mechanism prevents permanent lockup if VRF fails.
    ///      Note: rngLockedFlag (separate bool) controls the daily RNG lock state.
    ///      The LSB doubles as the daily retry-spent flag (0 = retry available, 1 = spent);
    ///      written only by DegenerusGameAdvanceModule (_finalizeRngRequest / coordinator swap).
    uint48 internal rngRequestTime;

    /// @notice Current jackpot level (starts at 0). Purchase phase targets level + 1.
    ///
    ///      SECURITY: uint24 supports ~16M levels — game would take millennia
    ///      to overflow at realistic progression rates.
    uint24 public level = 0;

    /// @notice Current game phase flag.
    ///      false = purchase phase
    ///      true  = jackpot phase
    ///
    ///      SECURITY: Phase transitions are guarded by advanceGame flow.
    bool internal jackpotPhaseFlag;

    // =========================================================================
    // EVM SLOT 0 (continued): Counters and Flags
    // =========================================================================

    /// @dev Count of jackpots processed within the current level.
    ///      Capped at 5 (JACKPOT_LEVEL_CAP in JackpotModule); triggers level
    ///      advancement when reached. Reset at level start.
    ///
    ///      SECURITY: uint8 is sufficient (max 255, only need 0-5).
    uint8 internal jackpotCounter;

    /// @dev True once the prize target is met for current level.
    ///      When true, next tick skips normal daily/jackpot prep and proceeds
    ///      to jackpot window. Allows early level completion on high activity.
    bool internal lastPurchaseDay;

    /// @dev Latch to hold decimator window open until RNG is requested.
    ///      Opens at jackpot phase start for levels 4, 14, 24... (not 94) or 99, 199...
    ///      Closes when RNG requested during lastPurchaseDay at resolution levels.
    bool internal decWindowOpen;

    /// @dev True when daily RNG is locked (jackpot resolution in progress).
    ///      Set when daily VRF is requested, cleared when daily processing completes.
    ///      Mid-day lootbox RNG does NOT set this flag.
    ///      Used to block burns/opens during jackpot resolution window.
    bool internal rngLockedFlag;

    /// @dev True while jackpot→purchase transition housekeeping is in progress.
    bool internal phaseTransitionActive;

    /// @dev True once gameover has been triggered (terminal state).
    bool public gameOver;

    /// @dev True when daily jackpot ETH phase completed but coin+tickets phase pending.
    ///      Gas optimization: splits daily jackpot into multiple advanceGame calls to
    ///      stay under the ~10M per-tx internal budget. Cleared after coin+ticket distribution.
    bool internal dailyJackpotCoinTicketsPending;

    /// @dev Jackpot compression tier: 0=normal (5d), 1=compressed (3d), 2=turbo (1d).
    ///      Set when purchase-phase target is met quickly, signaling high player interest.
    ///      Turbo (2): target met within 1 day — entire jackpot in 1 physical day. On a
    ///      non-x0 level the morning arm collapses the phase that same day; an x0 (BAF)
    ///      level latches 2 on the evening path instead, keeping a real last purchase
    ///      day (the BAF top-flipper board's feed day) before the one-day collapse.
    ///      Compressed (1): target met within 3 days — 5 logical days in 3 physical.
    ///      0/1 clear at phase end; 2 survives as the coinflip bonus-day latch and is
    ///      consumed by the next level's first purchase-day settlement in rngGate. When
    ///      that day itself arms the next turbo (back-to-back chain), the arm escalates
    ///      the latch to 3 = armed turbo + predecessor's bonus still owed; the day's
    ///      settlement pays the bonus and drops 3 back to 2.
    uint8 internal compressedJackpotFlag;

    /// @dev True when the read slot has been fully drained (all tickets processed).
    ///      Gate for RNG requests and jackpot logic in advanceGame daily path.
    ///
    ///      SECURITY: Must be set to true before any jackpot/phase logic executes.
    ///      Reset to false on every queue slot swap.
    bool internal ticketsFullyProcessed;

    // EVM SLOT 0 (continued): Double-Buffer + Freeze

    /// @dev Active write buffer toggle for ticket queue double-buffering.
    ///      Toggled via negation (`ticketWriteSlot = !ticketWriteSlot`) during queue slot swaps.
    ///      Write path uses this value; read path uses the opposite.
    ///
    ///      SECURITY: bool toggle via negation. Only values false/true are valid.
    bool internal ticketWriteSlot;

    /// @dev True when purchase revenue redirects to pending accumulators.
    ///      Set at daily RNG request time; cleared by _unfreezePool().
    ///
    ///      SECURITY: Persists across jackpot phase days. All 5 jackpot payouts
    ///      use pre-freeze pool values. _unfreezePool is the single control point.
    bool internal prizePoolFrozen;

    /// @dev Latching terminal for the coin-presale-box window. Set once, in the
    ///      box purchase that crosses the 50-ETH cumulative box cap. While false,
    ///      ETH buys accrue presaleBoxCredit; once true, no further box buys or
    ///      credit accrual occur. Packed into slot 0.
    bool internal presaleOver;

    /// @dev Afking process-STAGE drain-completion flag — the subscriber-drain sibling
    ///      of `ticketsFullyProcessed`. False while the STAGE is stamping the funded
    ///      subscriber set this day; set true once the set is fully drained; flipped back
    ///      to false forward-looking at the start of the next day (the advance's
    ///      `_afkingResetDay != day` gate), so it always reflects "afking done for the
    ///      current day". Packed into slot 0 alongside `level` / `rngLockedFlag` /
    ///      `ticketsFullyProcessed`, which the advance-path STAGE already SLOADs, so it
    ///      costs no additional cold slot access on that path.
    bool internal subsFullyProcessed;

    /// @dev One-way "all coin-presale boxes have been opened" flag. False until the auto-open sweep
    ///      has advanced its cursor PAST presaleCloseIndex — i.e. every box at indices <= the close
    ///      index is opened, so none can remain. Packed into slot 0, which every open path already
    ///      SLOADs (`level` / `rngLockedFlag`), so the gate `!presaleDrained` costs no additional
    ///      cold slot access: once set, the post-presale sweep AND manual opens skip the presaleBoxEth
    ///      SLOAD. Flipped only by the in-order sweep (never the manual path), so an out-of-order
    ///      manual open of the closing box cannot trip it early and strand a still-queued box.
    ///      The flip also pays the Pool.PresaleBox remainder to presaleCloser.
    bool internal presaleDrained;

    /// @dev FLIP ticket purchase window latch. redeemFlip lazily opens it the moment the prize
    ///      target is met in the purchase phase (_getNextPrizePool() > _prizePoolTarget(level + 1), with no
    ///      RNG in flight); it persists through the jackpot days and is cleared in the advance at the
    ///      final jackpot day's RNG request — the same boundary where new tickets route to the next
    ///      level. While closed, FLIP ticket purchases revert, so FLIP tickets only ever join a
    ///      happening jackpot, never an open/stalled purchase phase. Packed into slot 0, which the
    ///      purchase/advance paths already SLOAD, so the gate costs no additional cold slot access.
    bool internal ticketRedemptionOpen;

    /// @dev Decimator day-one burn bonus latch. Set by the RNG request that opens the
    ///      decimator window (the x4/x99 level increment); cleared by the next fresh daily
    ///      request (the same-day VRF retry does not clear it). While set, recordDecBurn
    ///      grants the day-one weight multiplier. Occupies slot-0 byte [31:32], which the
    ///      request path already writes, so set/clear ride existing slot-0 stores.
    bool internal decDayOneActive;

    // =========================================================================
    // EVM SLOT 1: Prize Pools
    // =========================================================================

    /// @dev Active prize pool for the current level.
    ///      Accumulated from mint fees and distributed via jackpots.
    ///      Packed into slot 1 as uint128 (max ~3.4e20 ETH, far exceeds total supply).
    ///      Access through _getCurrentPrizePool()/_setCurrentPrizePool() helpers.
    uint128 internal currentPrizePool;

    /// @dev Aggregate ETH liability across all packed balances (claimable + afking halves).
    ///      Used for solvency checks: game must hold >= claimablePool ETH.
    ///
    ///      INVARIANT: claimablePool >= Σ (claimable + afking halves of balancesPacked[*]).
    ///      Equality holds in steady state; decimator settlement reserves the full pool up front,
    ///      so claimablePool is transiently over-reserved (strictly greater) until per-winner
    ///      claims credit. Every component is credited/debited in tandem to maintain it.
    ///
    ///      uint128 max ~3.4e20 ETH — far exceeds total ETH supply.
    ///      Packed into slot 1 alongside currentPrizePool.
    uint128 internal claimablePool;

    // =========================================================================
    // SLOT 2+: Full-Width Balances and Pools
    // =========================================================================
    // Each uint256 occupies its own 32-byte slot. These track ETH/token flows.

    /// @dev Packed live prize pools:
    ///      [128:256] futurePrizePool | [0:128] nextPrizePool
    ///      uint128 max ~= 3.4e38 wei -- ~2.8e21x total ETH supply.
    ///      Saves 1 SSTORE on every purchase: both halves are written together, so the
    ///      pool split costs one RMW rather than two.
    ///
    ///      SECURITY: All access through _getPrizePools()/_setPrizePools() helpers.
    ///      Direct reads of this variable will get corrupted data.
    uint256 internal prizePoolsPacked;

    /// @dev Latest VRF random word, or 0 if a request is pending.
    ///      Written by VRF callback; consumed by game logic for randomness.
    ///
    ///      SECURITY: 0 indicates pending state. Game logic checks for non-zero.
    uint256 internal rngWordCurrent;

    /// @dev Last VRF request ID, used to match fulfillment callbacks.
    ///      Prevents processing stale or mismatched VRF responses.
    ///
    ///      SECURITY: Request ID matching prevents replay attacks on RNG.
    uint256 internal vrfRequestId;

    /// @dev Number of reverse flips purchased against current RNG word.
    ///      Tracks flip activity for jackpot sizing adjustments. Co-resident with
    ///      lastVrfProcessedTimestamp (both written in _applyDailyRng); bounded by
    ///      supply/RNG_NUDGE_BASE_COST << 2^64 since every nudge burns >= 100 FLIP.
    uint64 internal totalFlipReversals;

    /// @dev Timestamp of the last successfully processed VRF word.
    ///      Used by governance to detect VRF stalls (time-based vs day-gap-based).
    ///      Initialized in wireVrf(), updated in _applyDailyRng(). Shares the slot
    ///      with totalFlipReversals.
    uint48 internal lastVrfProcessedTimestamp;

    /// @dev Packed daily jackpot ticket data for two-phase execution.
    ///      Layout: [counterStep (8 bits @ 0)] [dailyEntries (64 bits @ 8)]
    ///              [carryoverEntries (64 bits @ 72)] [carryoverSourceOffset (8 bits @ 136)]
    ///      Set during ETH phase, consumed during coin+ticket phase.
    ///      Gas optimization: allows splitting daily jackpot across multiple advanceGame calls.
    uint256 internal dailyTicketBudgetsPacked;

    // =========================================================================
    // Token State and Jackpot Mechanics
    // =========================================================================

    /// @dev Per-player ETH balances packed into one slot: [afking:high128 | claimable:low128].
    ///      - claimable (low 128 bits): ETH claimable from jackpot winnings.
    ///      - afking (high 128 bits): prepaid AfKing subscription funding.
    ///      Both halves ride inside claimablePool (no separate aggregate); each mutation moves
    ///      claimablePool in tandem at the call site. Read and written only through the
    ///      _claimableOf / _afkingOf / _credit* / _debit* accessors, which split and recombine
    ///      the two halves; per-player ETH <= total supply (~1.2e26 wei << 2^128), so neither
    ///      half can overflow.
    ///
    ///      SECURITY: Pull pattern — players and funders withdraw their own funds (the claim
    ///      function / withdrawAfkingFunding), separating credit from transfer.
    mapping(address => uint256) internal balancesPacked;

    /// @dev Nested mapping: level -> trait ID (0-255) -> array of ticket holders.
    ///      Used for jackpot winner selection: random index into trait's array.
    ///
    ///      STRUCTURE: lvlTraitEntry[level][traitId] = address[]
    ///      Each burn adds the burner's address, allowing duplicate entries
    ///      (more burns = more tickets = higher win probability).
    ///
    ///      STORAGE: Slot for mapping root, then:
    ///        - keccak256(level . slot) gives the 256-element array of arrays
    ///        - Each inner array has length at its slot, data at keccak256(slot)
    ///
    ///      SECURITY: Array growth bounded by total ticket supply per level.
    mapping(uint24 => address[][256]) internal lvlTraitEntry;

    /// @dev Bit-packed mint history per player.
    ///      Layout defined by constants in BitPackingLib and MintStreakUtils.
    ///      Tracks mint counts, bonuses, eligibility flags, deity pass, and affiliate bonus cache.
    ///      Single SLOAD/SSTORE for all mint-related player data.
    ///
    ///      SECURITY: Packing reduces gas and storage footprint.
    ///      Bit manipulation requires careful masking (done via BitPackingLib shifts and masks).
    mapping(address => uint256) internal mintPacked_;

    // =========================================================================
    // RNG History
    // =========================================================================

    /// @dev VRF random words keyed by dailyIdx.
    ///      0 means "not yet recorded" (no request fulfilled for that day).
    ///      Historical words enable verifiable replay of past randomness.
    ///
    ///      SECURITY: Immutable once written; provides audit trail for RNG.
    mapping(uint24 => uint256) internal rngWordByDay;

    // =========================================================================
    // Future Mint Awards
    // =========================================================================

    /// @dev Packed pending accumulators for purchase revenue during prize pool freeze.
    ///      [128:256] futurePending | [0:128] nextPending
    ///      Accumulated while prizePoolFrozen == true; applied atomically by _unfreezePool().
    ///
    ///      SECURITY: Zeroed at freeze start (if not already frozen) and at unfreeze.
    ///      During multi-day jackpot phase, accumulators grow across all 5 days.
    uint256 internal prizePoolPendingPacked;

    /// @dev Queue of players with tickets (purchase/burn sources) per level.
    ///      All tickets (purchases, lootbox rewards, etc.) queue here.
    ///
    ///      PROCESSING SCHEDULE:
    ///      - Current level tickets: Processed continuously during advanceGame (each call)
    ///      - Next level tickets: Activated at END of purchase phase (before pool consolidation)
    ///
    ///      EXAMPLE (Level 5 purchase phase):
    ///      - lvlOffset=0 → ticketQueue[5] → Processed continuously throughout level 5
    ///      - lvlOffset=1 → ticketQueue[6] → Activated at end of purchase phase (before pool consolidation)
    ///
    ///      Keys are encoded: ticketQueue is indexed by (lvl | slotBit) — bit 23 selects the
    ///      double-buffer write/read half (ticketWriteSlot); tickets targeting > level+5 use the
    ///      disjoint far-future key space (bit 22). Raw-level indices above hold only when
    ///      ticketWriteSlot is false.
    ///
    ///      This allows lootbox tickets to participate in early-bird jackpots at jackpot phase start.
    mapping(uint24 => address[]) internal ticketQueue;

    /// @dev Packed owed entries per level per player.
    ///      Layout: [1 bit snap-done @ 40][32 bits owed][8 bits remainder].
    ///      `owed` is denominated in ENTRIES (each entry = price/4),
    ///      NOT whole tickets — 4 entries make one whole ticket (priceForLevel(level)).
    ///      The snap-done bit (SNAP_DONE_BIT) is set only by the drains; queue writers
    ///      run strictly before their key's drain window, so they never observe it.
    mapping(uint24 => mapping(address => uint48)) internal entriesOwedPacked;

    /// @dev Cursor for ticket queue processing (dual-purpose).
    ///      - SETUP phase: tracks near-future level progress (1-4), reset to 0 when done.
    ///      - PURCHASE phase: tracks mint batch progress through ticketQueue.
    ///      - JACKPOT phase: tracks jackpot batch progress through ticketQueue.
    ///      Phases are mutually exclusive, so cursor is reused safely.
    uint32 internal ticketCursor;

    /// @dev Current level being processed in ticket queue operations.
    uint24 internal ticketLevel;

    /// @dev Active snap divisor exponent: drained owed balances for levels below
    ///      snapLevel divide by 2^snapShift. Moves only at level commit, by folding
    ///      in a reached declaration. Zero outside runaway-demand states.
    uint8 internal snapShift;

    /// @dev Pending thanos declaration: levels >= snapLevel drain at snapPendingShift
    ///      instead of snapShift. Declared via setThanosLevel at least 6 levels ahead,
    ///      strictly before the target's first materialization (the far-future
    ///      promotion at the transition to target-5), so one level's entries always
    ///      share one exponent regardless of when they were bought or drained —
    ///      the invariant that keeps any declared change (raise or lower) EV-neutral.
    ///      snapLevel == 0 means no pending declaration.
    uint24 internal snapLevel;

    /// @dev Shift that applies from snapLevel onward. Folded into snapShift at the
    ///      level commit that reaches snapLevel.
    uint8 internal snapPendingShift;

    // =========================================================================
    // Ticket Queue Helpers
    // =========================================================================

    /// @notice Emitted when traits are generated for a player's ticket batch.
    ///         Records the encoded key + count needed to replay trait generation off-chain.
    event TraitsGenerated(
        address indexed player,
        uint256 baseKey,
        uint32 take
    );

    /// @notice Emitted when a future level is declared a thanos level.
    event ThanosLevelSet(uint24 targetLevel, uint8 shift);

    /// @notice Emitted when entries are queued for a buyer at a specific level.
    event EntriesQueued(
        address indexed buyer,
        uint24 targetLevel,
        uint32 entries
    );

    /// @notice Emitted when scaled entries (entries × QTY_SCALE) are queued for a buyer.
    event EntriesQueuedScaled(
        address indexed buyer,
        uint24 targetLevel,
        uint32 entriesScaled
    );

    /// @notice Emitted when entries are queued across a range of levels. Covered levels are
    ///         startLevel, startLevel + stride, ... (numLevels of them); stride 1 = contiguous.
    event EntriesQueuedRange(
        address indexed buyer,
        uint24 startLevel,
        uint24 numLevels,
        uint24 stride,
        uint32 entriesPerLevel
    );

    /// @notice Emitted when a deity pass is purchased.
    event DeityPassPurchased(
        address indexed buyer,
        uint8 symbolId,
        uint256 price,
        uint24 level
    );

    /// @notice Emitted when game-over drain processes terminal jackpots.
    event GameOverDrained(
        uint24 level,
        uint256 available,
        uint256 claimablePool
    );

    /// @notice Once-per-day snapshot of the prize-pool triple plus the claimable reserve, the
    ///         solvency total (ETH + stETH), and the yield accumulator, emitted at the conclusion
    ///         of each daily advance and once at game-over. Lets the off-chain indexer mirror the
    ///         pool balances — which are mutated at many sites with no per-delta event — and keep a
    ///         daily solvency checksum from logs alone. Field order/names are read by the indexer.
    ///         `day` is the sealed day the snapshot belongs to, so the reading side never
    ///         infers it from surrounding event order. It carries no level or phase: the
    ///         seal runs ahead of the stage-3 purchaseStartDay/jackpotPhaseFlag writes, so
    ///         those fields would report pre-transition state here.
    event PrizePoolDailySnapshot(
        uint256 next,
        uint256 future,
        uint256 current,
        uint256 claimable,
        uint256 totalBalance,
        uint256 yieldAccumulator,
        uint24 day
    );

    /// @notice Emitted when final sweep forfeits unclaimed winnings 30 days post-gameover.
    event FinalSwept(uint256 totalFunds);

    /// @dev Emitted when ETH is credited to a player's claimable balance.
    event PlayerCredited(address indexed player, uint256 amount);

    /// @dev Emitted when a VRF word is bound to a lootbox RNG index (mid-day finalize,
    ///      daily apply, or dead-man fallback). Emitted from both the Game callback and
    ///      the AdvanceModule, so it lives in the shared base.
    event LootboxRngApplied(uint48 index, uint256 word, uint256 requestId);

    /// @dev Emitted when a LINK donation adds mid-day RNG credit, in juels.
    ///      `balance` is the post-credit balance.
    event MiddayRngCredited(
        address indexed donor,
        uint256 added,
        uint256 balance
    );

    /// @dev Emitted when credit is charged to waive a mid-day request's pending-value
    ///      gates. `balance` is the post-charge balance. Emitted from the AdvanceModule,
    ///      paired with MiddayRngCredited from the Game, so both live in the shared base.
    event MiddayRngCreditSpent(
        address indexed spender,
        uint256 charged,
        uint256 balance
    );

    /// @dev Emitted when the vault owner retunes the mid-day basefee ceiling, in gwei.
    event MiddayMaxBasefeeUpdated(uint256 prev, uint256 next);

    /// @dev Emitted whenever prepaid afking ETH is spent to fund a buy (the afking-as-payment
    ///      waterfall's third tier) — full observability of where afking principal goes.
    event AfkingSpent(address indexed player, uint256 amount);

    /// @dev A mining crank paid in FLIP. The credit itself rides `coinflip.creditFlip`, which
    ///      emits nothing attributable, so without this the whole miner revenue stream is
    ///      readable only by scanning tx selectors. `kind` is one of the MINER_BOUNTY_*
    ///      constants below and is set explicitly per branch — the paying call sites converge
    ///      on a single credit and carry no category of their own. Emitted from both the
    ///      afking module and the Game, so it lives in the shared base.
    event MinerBounty(
        uint8 kind,
        address indexed miner,
        uint256 flipAmount
    );

    /// @dev `MinerBounty.kind` values.
    uint8 internal constant MINER_BOUNTY_ADVANCE = 1;
    uint8 internal constant MINER_BOUNTY_BOX_OPEN = 2;
    uint8 internal constant MINER_BOUNTY_DEGENERETTE_RESOLVE = 3;
    uint8 internal constant MINER_BOUNTY_CRAPS_KEEP = 4;

    /// @dev Emitted whenever a player's claimable balance is debited by the protocol. Covers
    ///      mint payments (MintPaymentKind.Claimable / Combined), lootbox/ticket shortfall
    ///      (Internal), foil pack shortfall (Internal), salvage debits (Internal), sDGNRS
    ///      redemption reserve (Internal), and game-over sweep (Internal). `amount` is the
    ///      exact claimable wei removed; `newBalance` is the post-debit claimable balance.
    event ClaimableSpent(
        address indexed player,
        uint256 amount,
        uint256 newBalance,
        MintPaymentKind payKind,
        uint256 costWei
    );

    /// @notice Emitted when a boon is consumed by a player.
    event BoonConsumed(address indexed player, uint8 boonType, uint16 boostBps);

    /// @notice Emitted when admin swaps game ETH for stETH.
    event AdminSwapEthForStEth(address indexed recipient, uint256 amount);

    /// @notice Emitted when admin stakes game ETH into Lido stETH.
    event AdminStakeEthForStEth(uint256 amount);

    /// @dev The logical ticket level the terminal game-over jackpot pays from. Purchase-phase
    ///      tickets normally target `lvl + 1`; jackpot-phase tickets target the current `lvl`.
    ///      The locked last-purchase transition is the one semantic exception: the RNG request has
    ///      already promoted `level`, so the purchase cohort committed before that request now sits
    ///      at `lvl`, while later write-buffer purchases target `lvl + 1`. Shared by the game-over
    ///      ticket DRAIN (AdvanceModule) and terminal-jackpot READ (GameOverModule), keeping the
    ///      materialized trait bucket and payout bucket identical in every terminal state.
    ///      The terminal path latches the answer on its first entry and every later read
    ///      returns the latch. That is what lets the terminal sequence hold the RNG lock:
    ///      the un-latched form infers "the last-purchase request already promoted level"
    ///      from rngLockedFlag, so a lock taken for terminal reasons would otherwise move
    ///      this level between transactions and split the drained cohort from the payout
    ///      bucket. `level` itself cannot move once the game-over path owns the advance.
    function _gameOverTicketLevel(uint24 lvl) internal view returns (uint24) {
        uint256 latched = _lrRead(LR_GO_LVL_SHIFT, LR_GO_LVL_MASK);
        if (latched != 0) return latched == 1 ? lvl : lvl + 1;
        return (jackpotPhaseFlag || (lastPurchaseDay && rngLockedFlag)) ? lvl : lvl + 1;
    }

    /// @dev O(1) advance-work discovery, shared by the external keeper view
    ///      (DegenerusGame.advanceDue) and the afking router's in-context predicate.
    ///      TRUE for a new-day advance (regardless of rngLock — advance is
    ///      liveness-critical) OR a mid-day partial-drain whose read window still holds
    ///      queued tickets or whose sealed foil bucket awaits its drain. The probe
    ///      mirrors the unified sweep's window [purchaseLevel-1 .. purchaseLevel+4]; a
    ///      fixed six-key scan, not unbounded.
    function _advanceDue() internal view returns (bool) {
        if (_simulatedDayIndex() != dailyIdx) return true;
        if (!ticketsFullyProcessed) {
            uint24 lvl = level;
            uint24 purchaseLevel = (!jackpotPhaseFlag &&
                lastPurchaseDay &&
                rngLockedFlag)
                ? lvl
                : lvl + 1;
            uint24 t = purchaseLevel == 0 ? 0 : purchaseLevel - 1;
            uint24 end = purchaseLevel + 4;
            for (; t <= end; ) {
                if (ticketQueue[_tqReadKey(t)].length > 0) return true;
                unchecked {
                    ++t;
                }
            }
            if (_foilDrainPending()) return true;
        }
        return false;
    }

    /// @dev True when gameover liveness guard would fire within ~1 day (day-granularity).
    ///      Used to activate distress-mode lootbox behaviour: 100% nextpool allocation
    ///      and 25% ticket bonus on the distress-bought portion.
    function _isDistressMode() internal view returns (bool) {
        if (gameOver) return false;
        uint24 psd = purchaseStartDay;
        uint24 currentDay = _simulatedDayIndex();
        if (level == 0) {
            // Distress fires on the final day before the liveness guard would trigger.
            return currentDay >= psd + _DEPLOY_IDLE_TIMEOUT_DAYS;
        }
        return currentDay >= psd + 120;
    }

    /// @dev Queues entries for a buyer at a target level. The `entries` arg is in
    ///      entry units (price/4 each), NOT whole tickets — 4 entries per
    ///      whole ticket. `owed` accumulates entries.
    ///      If buyer has no existing entries at that level, adds them to the queue.
    ///      `owed` accumulates unchecked in the packed slot's uint32 lane. That ceiling sits
    ///      at ~1.07 billion whole tickets for a single level (4 entries each), which no
    ///      reachable purchase or award volume approaches.
    /// @param buyer Address to receive entries.
    /// @param targetLevel Level for which entries are queued.
    /// @param entries Number of entries to queue (price/4 units).
    function _queueEntries(
        address buyer,
        uint24 targetLevel,
        uint32 entries,
        bool rngBypass
    ) internal {
        if (entries == 0) return;
        // No liveness gate here: tickets queued during the liveness-timeout window are harmless.
        // They are never processed (the game-over drain ends the game without a further daily
        // draw) or the resolving daily word has not been requested yet, so no terminal jackpot
        // can be manipulated by them. Player purchase paths gate liveness at their own entry; the
        // advance-chain daily-jackpot distribution also queues through this sink and must NOT be
        // reverted here, so the gate stays off the shared sink.
        bool isFarFuture = targetLevel > level + 5;
        if (isFarFuture && rngLockedFlag && !rngBypass) revert RngLocked();
        emit EntriesQueued(buyer, targetLevel, entries);
        uint24 wk = isFarFuture
            ? _tqFarFutureKey(targetLevel)
            : _tqWriteKey(targetLevel);
        uint48 packed = entriesOwedPacked[wk][buyer];
        uint32 owed = uint32(packed >> 8);
        uint8 rem = uint8(packed);
        if (packed == 0) {
            ticketQueue[wk].push(buyer);
        }
        unchecked {
            owed += entries;
        }
        entriesOwedPacked[wk][buyer] = (uint48(owed) << 8) | uint48(rem);
    }

    /// @dev Converts a post-Bernoulli whole-ticket count into the entries unit the
    ///      entriesOwedPacked sink accumulates. One whole ticket (priceForLevel(level))
    ///      is 4 entries (each = price/4), so entries = wholeTickets << 2.
    ///      The sole canonical whole->entries conversion both prize legs route through.
    ///      `wholeTickets` is provably <= ~42.9M (scaledWholeTickets/100, uint32-capped), so
    ///      `<< 2` <= ~171.8M fits uint32 (4.29e9) with a 25x margin — no overflow guard.
    /// @param wholeTickets Whole-ticket count (each = priceForLevel(level)).
    /// @return Entries count (each = price/4); 4 per whole ticket.
    function wholeTicketsToEntries(uint32 wholeTickets) internal pure returns (uint32) {
        return wholeTickets << 2;
    }

    /// @dev Snap exponent for a target level's drain: the pending declaration for
    ///      levels at or past snapLevel, the active snapShift below it. One warm
    ///      SLOAD (shares the ticketCursor slot) plus two compares. Shared by the
    ///      ticket drains (MintModule) and the foil buy gate (FoilPackModule).
    function _snapShiftFor(uint24 targetLvl) internal view returns (uint8) {
        uint24 pl = snapLevel;
        if (pl != 0 && targetLvl >= pl) return snapPendingShift;
        return snapShift;
    }

    /// @dev Queues scaled entries (2 decimal places) for fractional purchases.
    ///      Handles remainder accumulation and promotes to a whole owed entry when
    ///      remainder >= QTY_SCALE.
    /// @param buyer Address to receive entries.
    /// @param targetLevel Level for which entries are queued.
    /// @param entriesScaled Scaled entries (entries x 100); owed gains entriesScaled / QTY_SCALE entries.
    function _queueEntriesScaled(
        address buyer,
        uint24 targetLevel,
        uint32 entriesScaled,
        bool rngBypass
    ) internal {
        if (entriesScaled == 0) return;
        // No liveness gate (see _queueEntries): post-liveness queued tickets are harmless.
        bool isFarFuture = targetLevel > level + 5;
        if (isFarFuture && rngLockedFlag && !rngBypass) revert RngLocked();
        emit EntriesQueuedScaled(buyer, targetLevel, entriesScaled);
        uint24 wk = isFarFuture
            ? _tqFarFutureKey(targetLevel)
            : _tqWriteKey(targetLevel);
        uint48 packed = entriesOwedPacked[wk][buyer];
        uint32 owed = uint32(packed >> 8);
        uint8 rem = uint8(packed);
        if (packed == 0) {
            ticketQueue[wk].push(buyer);
        }

        uint32 whole = uint32(uint256(entriesScaled) / QTY_SCALE);
        uint8 frac = uint8(uint256(entriesScaled) % QTY_SCALE);
        unchecked {
            owed += whole;
        }

        if (frac != 0) {
            uint16 newRem;
            unchecked {
                newRem = uint16(rem) + uint16(frac);
            }
            if (newRem >= QTY_SCALE) {
                unchecked {
                    owed += 1;
                }
                newRem -= uint16(QTY_SCALE);
            }
            rem = uint8(newRem);
        }
        uint48 newPacked = (uint48(owed) << 8) | uint48(rem);
        if (newPacked != packed) {
            entriesOwedPacked[wk][buyer] = newPacked;
        }
    }

    /// @dev Queues tickets for a contiguous range of levels with same quantity per level.
    /// @param buyer Address to receive tickets.
    /// @param startLevel First level in range (inclusive).
    /// @param numLevels Number of consecutive levels.
    /// @param entriesPerLevel Entries to award per level (4 entries = 1 whole ticket).
    function _queueEntryRange(
        address buyer,
        uint24 startLevel,
        uint24 numLevels,
        uint32 entriesPerLevel,
        bool rngBypass
    ) internal {
        _queueEntryRangeStrided(
            buyer,
            startLevel,
            numLevels,
            1,
            entriesPerLevel,
            rngBypass
        );
    }

    /// @dev Queues entries at every `stride`-th level: startLevel, startLevel + stride, ...
    ///      (`numLevels` covered levels). Shared walk for contiguous (stride 1) and strided
    ///      whole-ticket awards; far-future routing, RNG-lock revert, and write-slot selection
    ///      are per-level, so skipped levels need no handling.
    /// @param buyer Address to receive tickets.
    /// @param startLevel First covered level (inclusive).
    /// @param numLevels Number of covered levels.
    /// @param stride Gap between covered levels (1 = contiguous).
    /// @param entriesPerLevel Entries to award per covered level (4 entries = 1 whole ticket).
    function _queueEntryRangeStridedCore(
        address buyer,
        uint24 startLevel,
        uint24 numLevels,
        uint24 stride,
        uint32 entriesPerLevel,
        bool rngBypass,
        uint24 currentLevel,
        bool rngLockedCached,
        uint24 writeSlotBit
    ) private {
        // No liveness gate (see _queueEntries): post-liveness queued tickets are harmless.
        emit EntriesQueuedRange(buyer, startLevel, numLevels, stride, entriesPerLevel);
        // level / rngLockedFlag / ticketWriteSlot are loop-invariant and threaded in by the
        // caller (read once per award, not per stride-leg); none has a writer reachable from
        // this body, so the per-level lock check observes the same value either way.
        uint24 lvl = startLevel;
        for (uint24 i = 0; i < numLevels; ) {
            bool isFarFuture = lvl > currentLevel + 5;
            if (isFarFuture && rngLockedCached && !rngBypass) revert RngLocked();
            uint24 wk = isFarFuture ? _tqFarFutureKey(lvl) : (lvl | writeSlotBit);
            uint48 packed = entriesOwedPacked[wk][buyer];
            uint32 owed = uint32(packed >> 8);
            uint8 rem = uint8(packed);
            if (packed == 0) {
                ticketQueue[wk].push(buyer);
            }
            unchecked {
                owed += entriesPerLevel;
            }
            entriesOwedPacked[wk][buyer] = (uint48(owed) << 8) | uint48(rem);

            unchecked {
                lvl += stride;
                ++i;
            }
        }
    }

    /// @dev Wrapper preserving the original single-range signature: reads the loop-invariant
    ///      slot-0 fields once and delegates to the core. Multi-leg awards (_queueHalfPassAward)
    ///      read the fields once and call the core per leg instead.
    function _queueEntryRangeStrided(
        address buyer,
        uint24 startLevel,
        uint24 numLevels,
        uint24 stride,
        uint32 entriesPerLevel,
        bool rngBypass
    ) internal {
        _queueEntryRangeStridedCore(
            buyer, startLevel, numLevels, stride, entriesPerLevel, rngBypass,
            level, rngLockedFlag, ticketWriteSlot ? TICKET_SLOT_BIT : uint24(0)
        );
    }

    /// @dev Queues a half-pass award (1 half-pass = 1 entry/level over the span) as
    ///      whole-ticket (4-entry) chunks so every chunk spans all four trait quadrants:
    ///      - base leg: (halfPasses / 4) * 4 entries on every level of the span;
    ///      - remainder 2: one whole ticket every 2nd level (offsets 0, 2, ...);
    ///      - remainder 1: one whole ticket every 4th level (offsets 0, 4, ...);
    ///      - remainder 3: both legs, the every-4th leg offset by +1 (offsets 1, 5, ...)
    ///        so the two remainder legs cover disjoint levels.
    ///      Covered-level counts round up on odd spans (at most one extra whole ticket
    ///      per leg, in the buyer's favor). Total queued entries = halfPasses × span for
    ///      stride-aligned spans (any span divisible by 4, incl. the 100-level claims).
    /// @param buyer Address to receive tickets.
    /// @param startLevel First level of the span (inclusive).
    /// @param span Number of levels the award covers.
    /// @param halfPasses Half-pass count (1 half-pass = 1 entry/level equivalent).
    function _queueHalfPassAward(
        address buyer,
        uint24 startLevel,
        uint24 span,
        uint256 halfPasses,
        bool rngBypass
    ) internal {
        // Read the loop-invariant slot-0 fields once for all <=3 legs — none is written by the
        // core body, so this is identical to each leg re-reading them, minus the repeated SLOADs.
        uint24 currentLevel = level;
        bool rngLockedCached = rngLockedFlag;
        uint24 writeSlotBit = ticketWriteSlot ? TICKET_SLOT_BIT : uint24(0);
        uint32 baseEntries = uint32((halfPasses / 4) * 4);
        if (baseEntries != 0) {
            _queueEntryRangeStridedCore(buyer, startLevel, span, 1, baseEntries, rngBypass, currentLevel, rngLockedCached, writeSlotBit);
        }
        uint256 rem = halfPasses % 4;
        if (rem == 0) return;
        if (rem >= 2) {
            _queueEntryRangeStridedCore(buyer, startLevel, (span + 1) / 2, 2, 4, rngBypass, currentLevel, rngLockedCached, writeSlotBit);
        }
        if (rem == 1) {
            _queueEntryRangeStridedCore(buyer, startLevel, (span + 3) / 4, 4, 4, rngBypass, currentLevel, rngLockedCached, writeSlotBit);
        } else if (rem == 3) {
            _queueEntryRangeStridedCore(buyer, startLevel + 1, (span + 2) / 4, 4, 4, rngBypass, currentLevel, rngLockedCached, writeSlotBit);
        }
    }

    // =========================================================================
    // Packed Prize Pool Helpers
    // =========================================================================

    /// @dev Bit offset of the future half inside both packed pool slots.
    uint256 internal constant POOL_FUTURE_SHIFT = 128;

    /// @dev Largest value either pool half holds, and the mask that extracts one.
    ///      uint128 ~= 3.4e38 wei, ~2.8e21x total ETH supply.
    uint256 internal constant POOL_HALF_MAX = type(uint128).max;

    /// @dev Writes both pool halves. Each half owns exactly half the slot, so the write
    ///      is a whole-word overwrite with nothing to preserve.
    function _setPrizePools(uint128 next, uint128 future) internal {
        prizePoolsPacked = (uint256(future) << POOL_FUTURE_SHIFT) | uint256(next);
    }

    function _getPrizePools()
        internal
        view
        returns (uint128 next, uint128 future)
    {
        uint256 packed = prizePoolsPacked;
        next = uint128(packed);
        future = uint128(packed >> POOL_FUTURE_SHIFT);
    }

    function _setPendingPools(uint128 next, uint128 future) internal {
        prizePoolPendingPacked =
            (uint256(future) << POOL_FUTURE_SHIFT) |
            uint256(next);
    }

    function _getPendingPools()
        internal
        view
        returns (uint128 next, uint128 future)
    {
        uint256 packed = prizePoolPendingPacked;
        next = uint128(packed);
        future = uint128(packed >> POOL_FUTURE_SHIFT);
    }

    /// @dev Add a combined prize contribution to the active accumulator in ONE RMW. The purchase
    ///      path computes each leg's next/future split (ticket and lootbox legs use different
    ///      ratios), sums the post-split totals, and lands both in a single packed slot — the
    ///      pending buffer while the pool is frozen, otherwise the live pools.
    ///
    ///      SATURATES rather than reverting. uint128 is ~2.8e21x the total ETH supply, so
    ///      neither half can reach the ceiling from real value — but the write sits on the
    ///      purchase hot path, and a revert there would brick the game outright rather than
    ///      degrade it. Clamping trades an impossible accounting error for guaranteed
    ///      liveness: past the ceiling the ledger would under-report what is owed, which
    ///      leaves the contract over-collateralised rather than insolvent, and every
    ///      solvency check still reads balance >= obligations.
    function _addPrizeContribution(uint128 nextAdd, uint128 futureAdd) internal {
        if (nextAdd == 0 && futureAdd == 0) return;
        bool frozen = prizePoolFrozen;
        uint256 slot = frozen ? prizePoolPendingPacked : prizePoolsPacked;

        // Masked and shifted operands keep both sums in uint256 — adding a uint128 half
        // to a uint128 addend would evaluate in uint128 and revert exactly where the
        // clamp is meant to catch it — so the clamp is the only ceiling either half
        // needs, and neither can carry into the other.
        uint256 next = (slot & POOL_HALF_MAX) + nextAdd;
        uint256 future = (slot >> POOL_FUTURE_SHIFT) + futureAdd;
        if (next > POOL_HALF_MAX) next = POOL_HALF_MAX;
        if (future > POOL_HALF_MAX) future = POOL_HALF_MAX;

        uint256 packed = (future << POOL_FUTURE_SHIFT) | next;
        if (frozen) {
            prizePoolPendingPacked = packed;
        } else {
            prizePoolsPacked = packed;
        }
    }

    // =========================================================================
    // Ticket Queue Key Encoding
    // =========================================================================

    /// @dev Compute the ticket queue key for the write slot.
    ///      Slot 0 uses raw level, slot 1 sets bit 23.
    function _tqWriteKey(uint24 lvl) internal view returns (uint24) {
        return ticketWriteSlot ? lvl | TICKET_SLOT_BIT : lvl;
    }

    /// @dev Compute the ticket queue key for the read slot (opposite of write).
    function _tqReadKey(uint24 lvl) internal view returns (uint24) {
        return !ticketWriteSlot ? lvl | TICKET_SLOT_BIT : lvl;
    }

    /// @dev Compute the ticket queue key for the far-future key space.
    ///      Always sets bit 22, independent of ticketWriteSlot.
    ///      Far-future tickets are not double-buffered; they persist until
    ///      drained by processFutureTicketBatch.
    function _tqFarFutureKey(uint24 lvl) internal pure returns (uint24) {
        return lvl | TICKET_FAR_FUTURE_BIT;
    }

    /// @dev Release a drained ticket queue in O(1): zero only the array's LENGTH
    ///      slot. `delete` on a dynamic storage array compiles into a loop zeroing
    ///      every element slot (~5k gas each against committed storage), so a long
    ///      queue would push the finishing batch past the block gas limit and brick
    ///      advancement — the batch loop is write-budgeted, but a `delete`'s
    ///      compiler-generated clear is not. Zeroing just the length keeps every
    ///      `.length` readiness gate exact while leaving stale element slots
    ///      behind; they are unreachable because all reads are length-gated and a
    ///      push overwrites slots from index 0 upward.
    function _releaseTicketQueue(uint24 rk) internal {
        address[] storage q = ticketQueue[rk];
        assembly ("memory-safe") {
            sstore(q.slot, 0)
        }
    }

    // =========================================================================
    // Single-Component Prize Pool Accessors
    // =========================================================================

    /// @dev Returns the next pool component.
    function _getNextPrizePool() internal view returns (uint256) {
        (uint128 next, ) = _getPrizePools();
        return uint256(next);
    }

    /// @dev Returns the future pool component.
    function _getFuturePrizePool() internal view returns (uint256) {
        (, uint128 future) = _getPrizePools();
        return uint256(future);
    }

    /// @dev Sets only the future pool component.
    function _setFuturePrizePool(uint256 val) internal {
        (uint128 next, ) = _getPrizePools();
        _setPrizePools(next, uint128(val));
    }

    /// @dev Century growth curve: an x00 level's target must reach a multiple of the
    ///      previous century's achieved pool — 2x by default, tapering as the game gets
    ///      huge (1.5x above 500k ETH, 1.3x above 1M ETH) so late centuries stay
    ///      reachable while still forcing real growth.
    uint256 internal constant CENTURY_FLOOR_BPS = 20_000;
    uint256 internal constant CENTURY_FLOOR_MID_BPS = 15_000;
    uint256 internal constant CENTURY_FLOOR_TOP_BPS = 13_000;
    uint256 internal constant CENTURY_FLOOR_MID_THRESHOLD = 500_000 ether;
    uint256 internal constant CENTURY_FLOOR_TOP_THRESHOLD = 1_000_000 ether;

    /// @dev Effective next-pool ratchet target for a purchase level: the previous
    ///      level's recorded pool, raised at century levels (x00) to at least the
    ///      curved multiple of the previous century's achieved pool — the newest entry
    ///      of centuryPrizePools. Every gate compares nextPrizePool strictly greater
    ///      than this target. The history is empty until the first century completes,
    ///      and a zero snapshot imposes no floor, so level 100 runs on the plain ratchet.
    function _prizePoolTarget(
        uint24 purchaseLvl
    ) internal view returns (uint256 target) {
        target = levelPrizePool[purchaseLvl - 1];
        if (purchaseLvl % 100 == 0) {
            uint256 completed = centuryPrizePools.length;
            uint256 snap = completed == 0
                ? 0
                : uint256(centuryPrizePools[completed - 1]);
            uint256 multBps = snap > CENTURY_FLOOR_TOP_THRESHOLD
                ? CENTURY_FLOOR_TOP_BPS
                : snap > CENTURY_FLOOR_MID_THRESHOLD
                    ? CENTURY_FLOOR_MID_BPS
                    : CENTURY_FLOOR_BPS;
            uint256 centuryFloor = (snap * multBps) / 10_000;
            if (centuryFloor > target) target = centuryFloor;
        }
    }

    // =========================================================================
    // Current Prize Pool Helpers
    // =========================================================================

    /// @dev Returns the current prize pool value as uint256.
    ///      Reads the uint128 packed variable and widens to uint256.
    function _getCurrentPrizePool() internal view returns (uint256) {
        return uint256(currentPrizePool);
    }

    /// @dev Sets the current prize pool value.
    ///      Narrows from uint256 to uint128. Safe because currentPrizePool
    ///      can never exceed total ETH supply (~1.2e26 wei << uint128 max ~3.4e38 wei).
    function _setCurrentPrizePool(uint256 val) internal {
        currentPrizePool = uint128(val);
    }

    /// @dev Canonical shortfall settle: cover `shortfall` wei from the buyer's own balances,
    ///      claimable first (only when `allowClaimable`) then prepaid afking. Tier 1 draws
    ///      claimable down to the STRICT 1-wei sentinel; tier 2 drains afking toward 0 (no
    ///      sentinel). The two tiers' draws pair a single aggregate `claimablePool` debit so
    ///      the solvency total stays exact, and an afking draw emits AfkingSpent. Reverts E()
    ///      when the two tiers together cannot cover the shortfall. Single sink so the sentinel
    ///      + the aggregate debit cannot drift across the ETH-in paths that accept claimable/
    ///      afking shortfall.
    /// @return claimableUsed Wei drawn from claimable. @return afkingUsed Wei drawn from afking.
    function _settleShortfall(address buyer, uint256 shortfall, bool allowClaimable)
        internal
        returns (uint256 claimableUsed, uint256 afkingUsed)
    {
        (claimableUsed, afkingUsed) = _settleShortfallNoPool(
            buyer,
            shortfall,
            allowClaimable
        );
        // One claimablePool RMW for both tiers — linear aggregate, same underflow domain as
        // the sequential per-tier debits; the per-player balance debits stay per-tier.
        uint256 poolDraw = claimableUsed + afkingUsed;
        if (poolDraw != 0) claimablePool -= uint128(poolDraw);
    }

    /// @dev Identical to _settleShortfall but WITHOUT the trailing claimablePool decrement, so a
    ///      combined ticket+lootbox purchase can fold both legs' pool draws into one RMW. The
    ///      per-player claimable/afking debits and the AfkingSpent emit still run here; the caller
    ///      MUST apply `claimablePool -= (claimableUsed + afkingUsed)` for the returned draw.
    function _settleShortfallNoPool(address buyer, uint256 shortfall, bool allowClaimable)
        internal
        returns (uint256 claimableUsed, uint256 afkingUsed)
    {
        if (shortfall == 0) return (0, 0);
        // Single packed load; both halves debited in one combined store below. No external call
        // in this body, so the cache cannot go stale between the reads and the write.
        uint256 packed = balancesPacked[buyer];
        if (allowClaimable) {
            uint256 claimable = uint128(packed);
            if (claimable > 1) {
                uint256 available = claimable - 1; // preserve the 1-wei sentinel
                claimableUsed = shortfall < available ? shortfall : available;
                if (claimableUsed != 0) {
                    // _debitClaimable's guard is dead here: claimableUsed <= claimable-1 < low half.
                    emit ClaimableSpent(buyer, claimableUsed, claimable - claimableUsed, MintPaymentKind.Internal, claimableUsed);
                }
            }
        }
        uint256 remaining = shortfall - claimableUsed;
        if (remaining != 0) {
            if ((packed >> 128) < remaining) revert Insolvent();
            afkingUsed = remaining;
            emit AfkingSpent(buyer, afkingUsed);
        }
        // One combined store == sequential _debitClaimable + _debitAfking: claimableUsed sits in
        // the low half (< it, no borrow) and afkingUsed in the high half (guarded >= above), so
        // neither borrows across halves. At least one is non-zero past the early return.
        if (claimableUsed != 0 || afkingUsed != 0) {
            balancesPacked[buyer] = packed - claimableUsed - (afkingUsed << 128);
        }
    }

    // =========================================================================
    // Balance accessors — claimable / afking (the only readers/writers of the
    // shared per-player slot). claimableWinnings and afkingFunding are folded
    // into one word per player; every balance flows through these so the
    // split/recombine stays consistent. claimablePool pairing is kept at the
    // call sites (the solvency total is maintained in tandem there).
    // =========================================================================

    /// @dev A player's claimable winnings balance (low 128 bits of the packed slot).
    function _claimableOf(address player) internal view returns (uint256) {
        return uint128(balancesPacked[player]);
    }

    /// @dev A player's prepaid afking balance (high 128 bits of the packed slot).
    function _afkingOf(address player) internal view returns (uint256) {
        return balancesPacked[player] >> 128;
    }

    /// @dev Credit claimable (the low half). A full-word add is safe: per-player ETH <= total
    ///      supply (~1.2e26 wei << 2^128), so claimable + amount never carries into the afking half.
    function _creditClaimable(address beneficiary, uint256 weiAmount) internal {
        if (weiAmount == 0) return;
        balancesPacked[beneficiary] += weiAmount;
        emit PlayerCredited(beneficiary, weiAmount);
    }

    /// @dev Debit claimable (the low half). Guard low >= amount so the subtraction never borrows
    ///      from the afking half — a low-half borrow would be invisible to 0.8's full-word check.
    function _debitClaimable(address player, uint256 weiAmount) internal {
        if (weiAmount == 0) return;
        if (uint128(balancesPacked[player]) < weiAmount) revert Insolvent();
        balancesPacked[player] -= weiAmount;
    }

    /// @dev Debit afking (the high half). Stands alone, unlike the credit side, because the
    ///      daily STAGE pass debits each sub in turn and the caller folds ONE aggregate
    ///      claimablePool move for the batch — there is no per-player site to pair against.
    ///      The full-word subtraction is naturally fail-loud: if afking < amount the whole word
    ///      underflows and 0.8 reverts (no silent low-half borrow).
    function _debitAfking(address player, uint256 weiAmount) internal {
        if (weiAmount == 0) return;
        balancesPacked[player] -= weiAmount << 128;
    }

    /// @dev Debit claimable (low half) and afking (high half) in ONE load + store. Each half is
    ///      guarded explicitly BEFORE the combined subtraction: a low-half borrow is invisible to
    ///      0.8's full-word check, and an oversized afking amount would silently truncate in the
    ///      unchecked-by-construction `<< 128` — the guards close both. Reverts match the
    ///      sequential _debitClaimable + _debitAfking exactly.
    function _debitClaimableAndAfking(
        address player,
        uint256 claimableAmount,
        uint256 afkingAmount
    ) internal {
        uint256 packed = balancesPacked[player];
        if (uint128(packed) < claimableAmount) revert Insolvent();
        if ((packed >> 128) < afkingAmount) revert Insolvent();
        balancesPacked[player] = packed - claimableAmount - (afkingAmount << 128);
    }

    /// @notice Emitted when ETH is credited to a player's prepaid afking balance.
    event AfkingFunded(address indexed player, uint256 amount);

    /// @dev Credit excess/stray ETH to a player's withdrawable prepaid afking balance,
    ///      preserving the solvency identity (claimablePool tracks the afking half). Used to
    ///      absorb purchase overpay and bare sends instead of reverting, stranding, or routing
    ///      to the prize pool — the ETH is already held by the contract, so this just records
    ///      the liability. Withdrawable via withdrawAfkingFunding (pre final sweep).
    ///
    ///      This is the ONLY afking credit: the per-player half, the claimablePool half and the
    ///      log move together or not at all. No bare credit primitive exists — an unpaired
    ///      credit raises obligations without the pool backing them (the SOLVENCY-01 break) and
    ///      touches no identifier the pool-write gate tracks. The debit twin stands alone only
    ///      because the daily STAGE pass debits each sub in a loop and folds ONE aggregate pool
    ///      move for the batch; credit is never batched, so it always pairs in place.
    ///
    ///      The full-word add is safe: afking + amount <= 2*supply << 2^128 (no overflow), and
    ///      amount << 128 leaves the claimable low half untouched.
    function _creditAfkingValue(address player, uint256 weiAmount) internal {
        if (weiAmount == 0) return;
        balancesPacked[player] += weiAmount << 128;
        claimablePool += uint128(weiAmount);
        emit AfkingFunded(player, weiAmount);
    }

    // =========================================================================
    // Loot Box State
    // =========================================================================

    /// @dev A player's box order for one RNG index, packed into one word. Four tiers, each a
    ///      COUNT against a size: small / medium / large take their size from `level`'s ticket
    ///      price (1x / 5x / 25x), the custom tier carries its own. Storing counts rather than
    ///      summed wei is what keeps an unlimited mix of boxes in a single slot, and keeps
    ///      `boxPlayers` bounded by unique buyers rather than by boxes.
    ///
    ///      `level`, `score` and `customSize` freeze on the period's first buy; later buys in
    ///      the same period only bump counts. The three bps lanes are running fractions of the
    ///      order's nominal value (which the counts themselves derive), not absolute wei —
    ///      `boostBps` because the boon uplift is capped per purchase and only the first buy in
    ///      a period carries one, `distressBps` because distress can toggle mid-period, and
    ///      `adjBps` because the EV cap is drawn against a per-level running total. All three
    ///      are only ever read as ratios, which is what lets them fit in 14 bits apiece.
    ///
    ///      Bit layout (LSB -> MSB), 209 bits used of 256:
    ///      - [0:24]     level        (uint24; frozen buy level, derives every preset size)
    ///      - [24:39]    score        (uint15; EV knob, clamped at ACTIVITY_EFFECTIVE_CAP_POINTS)
    ///      - [39:53]    boostBps     (uint14; boon uplift as a fraction of nominal order value)
    ///      - [53:67]    distressBps  (uint14; distress-bought fraction, the 25%-ticket-bonus basis)
    ///      - [67:81]    adjBps       (uint14; cap-eligible fraction that received the EV bonus)
    ///      - [81:89]    smallCount   (uint8)
    ///      - [89:97]    medCount     (uint8)
    ///      - [97:105]   largeCount   (uint8)
    ///      - [105:113]  customCount  (uint8)
    ///      - [113:161]  customSize   (uint48; per-box wei / LB_CUSTOM_SCALE)
    ///      - [161:209]  coverWei     (uint48; system-granted cover spend / LB_CUSTOM_SCALE)
    mapping(uint48 => mapping(address => uint256)) internal lootboxOrder;

    /// @dev Bit offsets / masks for the packed lootboxOrder word.
    uint256 internal constant LB_LEVEL_SHIFT = 0;
    uint256 internal constant LB_LEVEL_MASK = 0xFFFFFF;                           // 24 bits
    uint256 internal constant LB_SCORE_SHIFT = 24;
    uint256 internal constant LB_SCORE_MASK = 0x7FFF;                             // 15 bits
    uint256 internal constant LB_BOOST_SHIFT = 39;
    uint256 internal constant LB_DISTRESS_SHIFT = 53;
    uint256 internal constant LB_ADJ_SHIFT = 67;
    uint256 internal constant LB_BPS_MASK = 0x3FFF;                               // 14 bits, holds 0..10000
    uint256 internal constant LB_SMALL_SHIFT = 81;
    uint256 internal constant LB_MED_SHIFT = 89;
    uint256 internal constant LB_LARGE_SHIFT = 97;
    uint256 internal constant LB_CUSTOM_COUNT_SHIFT = 105;
    uint256 internal constant LB_COUNT_MASK = 0xFF;                               // 8 bits per tier
    uint256 internal constant LB_CUSTOM_SIZE_SHIFT = 113;
    uint256 internal constant LB_CUSTOM_SIZE_MASK = 0xFFFFFFFFFFFF;               // 48 bits
    /// @dev Whale-pass and afking covers grant box value the player did not choose and cannot
    ///      size, so it cannot be a count against a preset. It accumulates in its own lane and
    ///      resolves as ONE extra box — outside MAX_BOXES_PER_ORDER, since a cover must never
    ///      be able to lock a player out of buying, and never touching customSize.
    uint256 internal constant LB_COVER_SHIFT = 161;
    uint256 internal constant LB_COVER_MASK = 0xFFFFFFFFFFFF;                     // 48 bits

    /// @dev Custom-box wei is stored at 1e12 granularity — 0.0001% of the 0.01-ETH minimum
    ///      box, and 48 bits then span far past the ETH supply. The truncation is reward-side
    ///      only: the pool split at buy banks the exact wei paid, so it cannot move solvency.
    uint256 internal constant LB_CUSTOM_SCALE = 1e12;

    /// @dev Preset multipliers against the frozen level's ticket price.
    uint256 internal constant LB_MED_MULTIPLE = 5;
    uint256 internal constant LB_LARGE_MULTIPLE = 25;

    /// @dev Human-sweep walk weights, in the shared open-budget unit (1 unit ~= 4.7k gas, the
    ///      same unit the afking ring-scan skip is calibrated in).
    ///
    ///      Two weights, because an entry's cost is not linear in its boxes. MEASURED
    ///      (test/gas/BoxOrderOpenGas.t.sol): a one-box entry costs ~83.4k because it pays that
    ///      player's cold settlement slots, while each ADDITIONAL box in the same entry costs
    ///      ~15.2k at N=100 — the second box through the hundredth share every lane with the first. A
    ///      single rate would either starve the sweep on wide entries or blow the ceiling on
    ///      many narrow ones.
    ///
    ///      Sanity against the measurements: a 1920-unit sweep opened 90 one-box entries for
    ///      ~5.11M gas, and one maximum 100-box entry costs 15 + 100*6 = 615 units ~= 2.89M
    ///      against 2.37M for the most expensive measured shape.
    ///
    ///      BOX_WEIGHT is sized on the N=20 secant (~26k/box), not the N=100 one (~15k/box):
    ///      the true marginal is concave (ticket write-keys saturate with width), so a
    ///      100-fit weight under-charges every mid-width entry — the common shape — while
    ///      the 20-fit only over-charges very wide entries, the safe direction. Charged per
    ///      box INCLUDING the first, on top of the entry floor.
    uint256 internal constant OPEN_HUMAN_ENTRY_WEIGHT = 15; // ~70.5k, the per-entry floor
    uint256 internal constant OPEN_HUMAN_BOX_WEIGHT = 6;    // ~28k, per box, N=20 secant

    /// @dev Boxes one player may hold in one RNG index. Sized so a maximum entry — every box
    ///      rolled, plus one recirculated box per ETH spin — resolves inside a block alongside
    ///      the afking leg that shares the `mineFlip()` transaction. Not a spend limit: a
    ///      player wanting more exposure buys a larger custom, not more boxes.
    uint256 internal constant MAX_BOXES_PER_ORDER = 100;

    /// @dev Daily jackpots a level runs before it seals. Shared here because the active
    ///      ticket level below keys off it.
    uint8 internal constant JACKPOT_LEVEL_CAP = 5;

    /// @dev The level a ticket bought RIGHT NOW routes to — the single source of truth for the
    ///      purchase quote/charge, the ticket + foil delivery, participation/streak recording, and
    ///      every buy-now price view, so they can never diverge. Jackpot phase → current level;
    ///      purchase phase → next. Once the level's jackpots end this level seals no further daily
    ///      draw, so buys route to level + 1 — quoting the old level would strand the buyer's overpay
    ///      or misprice tickets in a level that has ended. Two states mark that sealed window: the
    ///      final jackpot day's RNG request (rngLocked, jackpot counter about to reach the cap), and
    ///      the span after _endPhase runs (phaseTransitionActive, jackpotCounter already zeroed, level
    ///      not yet incremented) while the transition drains. (Salvage/settlement callers are
    ///      rngLock-gated, so this branch is a no-op for them.)
    function _activeTicketLevel() internal view returns (uint24) {
        if (!jackpotPhaseFlag) return level + 1;
        // Transition underway: _endPhase set phaseTransitionActive and zeroed jackpotCounter, so the
        // counter test below can no longer key off the sealed level. phaseTransitionActive is the
        // standalone signal that this level's draws have ended, so buys route to the next level.
        if (phaseTransitionActive) return level + 1;
        if (rngLockedFlag) {
            uint8 cnt = jackpotCounter;
            uint8 comp = compressedJackpotFlag;
            uint8 step = comp == 2
                ? JACKPOT_LEVEL_CAP
                : (comp == 1 && cnt > 0 && cnt < JACKPOT_LEVEL_CAP - 1 ? 2 : 1);
            if (cnt + step >= JACKPOT_LEVEL_CAP) return level + 1;
        }
        return level;
    }

    /// @dev Read a field from a packed box order.
    function _lbGet(uint256 word, uint256 shift, uint256 mask) internal pure returns (uint256) {
        return (word >> shift) & mask;
    }

    /// @dev Write a field into a packed box order, masked to its width so an over-wide value
    ///      cannot alias a neighbour.
    function _lbSet(
        uint256 word,
        uint256 shift,
        uint256 mask,
        uint256 value
    ) internal pure returns (uint256) {
        return (word & ~(mask << shift)) | ((value & mask) << shift);
    }

    // =========================================================================
    // Coin-Presale-Box State
    // =========================================================================

    /// @dev Cumulative ETH spent on coin-presale boxes. Read+written per box buy
    ///      during the presale to enforce the 50-ETH cap and detect the crossing
    ///      (presaleOver latch + presaleCloser stamp). Never read after the
    ///      latch, so its cold-slot cost is confined to the presale window.
    uint96 internal presaleBoxEthSold;

    /// @dev Buyer of the 50-ETH-crossing box. Receives the Pool.PresaleBox remainder once the
    ///      auto-open sweep has advanced past presaleCloseIndex — after EVERY presale box has
    ///      drawn, so the remainder is variance dust and no open order can pull another box's
    ///      DGNRS into it. Packs into presaleBoxEthSold's slot (warm at the crossing buy).
    address internal presaleCloser;

    /// @dev Spendable presale-box credit accrued per player from ETH buys while
    ///      the presale is open (presaleBoxCredit += 0.25 * purchaseEth). Consumed
    ///      1:1 when a box is bought.
    mapping(address => uint256) internal presaleBoxCredit;

    /// @dev Presale-box record per RNG index per player. One box per (index, player).
    ///      A box always queues at the current lootbox RNG index and resolves off the
    ///      SAME committed word lootboxRngWordByIndex[index], domain-separated by the
    ///      "PRESALE_BOX" salt. A combined lootbox+box buy shares that one index.
    ///      Packed: [bit 255: closing][bits 96:191: soldBefore][bits 0:95: applied ETH].
    ///      soldBefore (cumulative box ETH before this buy) freezes the DGNRS-tier
    ///      curve input. Bit 255 (PRESALE_BOX_CLOSING_FLAG) marks the 50-ETH-crossing
    ///      box (event tag); its buyer is stamped in presaleCloser for the remainder sweep.
    mapping(uint48 => mapping(address => uint256)) internal presaleBoxEth;

    /// @dev Sentinel OR'd into presaleBoxEth marking the 50-ETH-crossing box.
    uint256 internal constant PRESALE_BOX_CLOSING_FLAG = 1 << 255;
    /// @dev Bit offset of the soldBefore (buy-time cumulative box ETH) field.
    uint256 internal constant PRESALE_BOX_SOLD_SHIFT = 96;
    /// @dev Mask for the 96-bit applied-ETH / soldBefore fields in presaleBoxEth.
    uint256 internal constant PRESALE_BOX_AMOUNT_MASK = 0xFFFFFFFFFFFFFFFFFFFFFFFF; // 96 bits

    // =========================================================================
    // Presale State
    // =========================================================================

    /// @dev Cumulative coin-presale-box ETH cap. The box buy crossing this latches
    ///      presaleOver.
    uint256 internal constant PRESALE_BOX_ETH_CAP = 50 ether;

    // =========================================================================
    // Game Over State (packed: 3 variables in 64/256 bits)
    // =========================================================================
    //
    // Layout (LSB -> MSB):
    //   [bits  0:47]  gameOverTime              uint48   Timestamp when gameover triggered (0 = active)
    //   [bits 48:55]  gameOverFinalJackpotPaid   uint8   1 = final jackpot paid
    //   [bits 56:63]  finalSwept                 uint8   1 = 30-day sweep executed

    /// @dev Packed game over state. See layout comment above.
    uint256 internal gameOverStatePacked;

    // ---- gameOverState shifts and masks ----
    uint256 internal constant GO_TIME_SHIFT = 0;
    uint256 internal constant GO_TIME_MASK = 0xFFFFFFFFFFFF;     // 48 bits
    uint256 internal constant GO_JACKPOT_PAID_SHIFT = 48;
    uint256 internal constant GO_JACKPOT_PAID_MASK = 0xFF;       // 8 bits
    uint256 internal constant GO_SWEPT_SHIFT = 56;
    uint256 internal constant GO_SWEPT_MASK = 0xFF;              // 8 bits

    /// @dev Read a field from the packed game over state.
    function _goRead(uint256 shift, uint256 mask) internal view returns (uint256) {
        return (gameOverStatePacked >> shift) & mask;
    }

    /// @dev Write a field to the packed game over state.
    function _goWrite(uint256 shift, uint256 mask, uint256 value) internal {
        gameOverStatePacked = (gameOverStatePacked & ~(mask << shift)) | ((value & mask) << shift);
    }

    // =========================================================================
    // Whale Pass Claims (Deferred >5 ETH lootboxes)
    // =========================================================================

    /// @dev Pending whale pass claims from large lootbox wins (>5 ETH).
    ///      Stores number of half whale passes (100 entries each = 100 levels × 1 entry per half-pass).
    ///      Unified storage for all deferred lootbox rewards (BAF, jackpot, decimator).
    mapping(address => uint256) internal whalePassClaims;

    /// @dev True once a WWXRP Degenerette jackpot in this level/10 bracket has
    ///      awarded its one whale halfpass. Rationed globally per bracket: the
    ///      first jackpot wins, later jackpots in the same bracket award nothing.
    mapping(uint256 => bool) internal wwxrpJackpotWhalePassBracketAwarded;

    // =========================================================================
    // Operator Approvals
    // =========================================================================

    /// @dev owner => operator => approved (game-wide delegated control).
    mapping(address => mapping(address => bool)) internal operatorApprovals;

    // =========================================================================
    // Affiliate DGNRS Claims
    // =========================================================================

    /// @dev Per-level prize pool snapshot used for affiliate DGNRS weighting.
    mapping(uint24 => uint256) internal levelPrizePool;

    /// @dev Per-level per-affiliate claim tracking (true if claimed).
    mapping(uint24 => mapping(address => bool))
        internal affiliateDgnrsClaimedBy;

    /// @dev Segregated DGNRS allocation + cumulative claimed per level, packed into one
    ///      slot: bits [0:128) = allocation (5% of affiliate pool, snapshot at transition),
    ///      bits [128:256) = cumulative claimed. Both are DGNRS base units, bounded by the
    ///      sDGNRS supply (~1e30) << uint128 (3.4e38). Claims draw against the fixed
    ///      allocation, not the live pool, eliminating first-mover advantage.
    mapping(uint24 => uint256) internal levelDgnrsPacked;

    /// @dev Unpack a level's (allocation, claimed) from the packed slot.
    function _getLevelDgnrs(uint24 lvl)
        internal
        view
        returns (uint256 allocation, uint256 claimed)
    {
        uint256 w = levelDgnrsPacked[lvl];
        allocation = uint128(w);
        claimed = w >> 128;
    }

    /// @dev Set a level's allocation half, preserving the claimed half.
    function _setLevelDgnrsAllocation(uint24 lvl, uint256 allocation) internal {
        uint256 w = levelDgnrsPacked[lvl];
        levelDgnrsPacked[lvl] =
            (w & (uint256(type(uint128).max) << 128)) |
            uint128(allocation);
    }

    /// @dev Add to a level's claimed half, preserving the allocation half. claimed is
    ///      monotone toward allocation (<= uint128), so the high half never overflows.
    function _addLevelDgnrsClaimed(uint24 lvl, uint256 add) internal {
        uint256 w = levelDgnrsPacked[lvl];
        uint256 newClaimed = (w >> 128) + add;
        levelDgnrsPacked[lvl] = uint128(w) | (newClaimed << 128);
    }

    // =========================================================================
    // Deity Pass (Perma Whale) Grants
    // =========================================================================

    /// @dev ETH paid for a buyer's (single) deity pass. The early-game-over refund is capped at
    ///      this, so a boon-discounted deity that paid < 20 ETH refunds only what it actually paid.
    ///      Ownership itself is tracked by the HAS_DEITY_PASS bit in mintPacked_.
    mapping(address => uint96) internal deityPassPricePaid;

    /// @dev List of deity pass owners for iteration.
    address[] internal deityPassOwners;

    /// @dev Reverse lookup: symbol ID (0-31) → current owner address.
    mapping(uint8 => address) internal deityBySymbol;

    // =========================================================================
    // Coin-Presale-Box DGNRS Curve
    // =========================================================================

    /// @dev Pool.PresaleBox DGNRS balance snapshot, set on the first box resolution.
    ///      The per-box DGNRS award uses base = presaleBoxDgnrsPoolStart / 100 and the
    ///      5-tier cumulative-volume multiplier curve [3.0, 2.5, 2.0, 1.5, 1.0].
    uint256 internal presaleBoxDgnrsPoolStart;

    // =========================================================================
    // Internal Helpers
    // =========================================================================


    /// @dev Front-load the LEVEL mint streak by a pass's freeze delta. Contiguity-aware: if the
    ///      prior completed run reaches the pass start with no gap, extend the streak by
    ///      `levelsToAdd`; otherwise reset to that span. `lastCompleted` advances to the pass
    ///      horizon and never regresses. `MASK_24`-saturating. Folds into the packed `data` word
    ///      before its single SSTORE — no ticket/freeze side effects.
    function _withPassStreakFrontLoad(
        uint256 data,
        uint24 startLevel,
        uint24 throughLevel,
        uint24 levelsToAdd
    ) internal pure returns (uint256) {
        if (levelsToAdd == 0) return data;
        uint24 lastCompleted = uint24(
            (data >> BitPackingLib.MINT_STREAK_LAST_COMPLETED_SHIFT) &
                BitPackingLib.MASK_24
        );
        uint256 prevStreak = (data >> BitPackingLib.LEVEL_STREAK_SHIFT) &
            BitPackingLib.MASK_24;
        // Continue the prior run while it is still alive. The streak decay rule tolerates one
        // un-minted level (alive at lastCompleted+1, breaks at +2), and startLevel == currentLevel+1,
        // so the run is alive at purchase iff startLevel <= lastCompleted+2. Otherwise a full level
        // lapsed with no mint — reset to this pass's span.
        uint256 newStreak = uint256(lastCompleted) + 2 >= startLevel
            ? prevStreak + levelsToAdd
            : levelsToAdd;
        if (newStreak > BitPackingLib.MASK_24) newStreak = BitPackingLib.MASK_24;
        uint24 newLastCompleted = throughLevel > lastCompleted
            ? throughLevel
            : lastCompleted;
        data = BitPackingLib.setPacked(
            data,
            BitPackingLib.MINT_STREAK_LAST_COMPLETED_SHIFT,
            BitPackingLib.MASK_24,
            newLastCompleted
        );
        data = BitPackingLib.setPacked(
            data,
            BitPackingLib.LEVEL_STREAK_SHIFT,
            BitPackingLib.MASK_24,
            uint24(newStreak)
        );
        return data;
    }

    /// @notice Emitted with the absolute post-write `mintPacked_` word whenever a
    ///         mint-lane path writes it (units/streak/count/day/affiliate-cache
    ///         records, the boon level-count grant, the deity/seat bit latches).
    ///         One data word carries every field — units + their level, mint streak
    ///         + last-completed, lifetime count, mint day, freeze window, pass type,
    ///         curse, affiliate cache — so indexers fold absolute state per log and
    ///         never accumulate deltas or replay price math. Pass activations carry
    ///         the same word on PassActivated, and curse writes carry their absolute
    ///         field on CurseChanged: between them the three cover every post-genesis
    ///         mintPacked_ write but one — the SEAT_ENCUMBERED bit, set on subscribe
    ///         and cleared on cancel (both beside SubscriptionUpdated) and cleared by
    ///         clearSeatEncumbrance (beside the token's SeatReclaimed). A folder
    ///         tracking that bit reads those; the next mint-lane log re-syncs it.
    /// @param player The player whose mintPacked_ record was written.
    /// @param packedAfter The full mintPacked_ word after the write (BitPackingLib layout).
    event MintRecorded(address indexed player, uint256 packedAfter);

    /// @notice Emitted on every pass activation (purchase AND award paths — this event
    ///         does not imply that the player bought the pass or received an AFKing seat).
    ///         It is the authoritative pass signal; the shared internals below and the whale
    ///         purchase's inline stats write all emit it). Carries the post-merge
    ///         freeze end so stacked/overlapping passes need no span heuristics,
    ///         plus the absolute post-write mintPacked_ word (the activation also
    ///         moves levelCount / passType / front-loaded streak).
    /// @param player The player the pass activates for.
    /// @param isWhale true = 100-level whale pass; false = 10-level lazy pass.
    /// @param startLevel First level of the pass's ticket range.
    /// @param frozenUntilAfter The FROZEN_UNTIL_LEVEL field after this activation
    ///        (max of the prior freeze and this pass's span end).
    /// @param packedAfter The full mintPacked_ word after the activation write.
    event PassActivated(
        address indexed player,
        bool isWhale,
        uint24 startLevel,
        uint24 frozenUntilAfter,
        uint256 packedAfter
    );

    /// @dev Activates a 10-level pass for a player. Shared logic for lazy pass purchases and awards.
    ///      Updates mintPacked_ (levelCount +10, frozenUntilLevel, passType, lastLevel, day)
    ///      and queues tickets for the 10-level range.
    /// @param player Address receiving the pass activation.
    /// @param ticketStartLevel First level of the 10-level range.
    /// @param entriesPerLevel Number of tickets to queue per level.
    function _activate10LevelPass(
        address player,
        uint24 ticketStartLevel,
        uint32 entriesPerLevel
    ) internal {
        uint256 prevData = mintPacked_[player];

        uint24 frozenUntilLevel = uint24(
            (prevData >> BitPackingLib.FROZEN_UNTIL_LEVEL_SHIFT) &
                BitPackingLib.MASK_24
        );
        uint24 lastLevel = uint24(
            (prevData >> BitPackingLib.LAST_LEVEL_SHIFT) & BitPackingLib.MASK_24
        );
        uint24 levelCount = uint24(
            (prevData >> BitPackingLib.LEVEL_COUNT_SHIFT) &
                BitPackingLib.MASK_24
        );
        uint24 baseLevelsToAdd = 10;

        uint24 targetFrozenLevel = ticketStartLevel + 9; // Freeze for 10 levels from pass start
        uint24 newFrozenLevel = frozenUntilLevel > targetFrozenLevel
            ? frozenUntilLevel
            : targetFrozenLevel;
        uint24 deltaFreeze = newFrozenLevel > frozenUntilLevel
            ? (newFrozenLevel - frozenUntilLevel)
            : 0;
        uint24 levelsToAdd = baseLevelsToAdd;
        if (levelsToAdd > deltaFreeze) {
            levelsToAdd = deltaFreeze;
        }

        uint24 newLevelCount = levelCount + levelsToAdd;

        uint8 currentPassType = uint8(
            (prevData >> BitPackingLib.WHALE_PASS_TYPE_SHIFT) & 3
        );
        uint24 lastLevelTarget = newFrozenLevel > lastLevel
            ? newFrozenLevel
            : lastLevel;

        uint256 data = prevData;
        data = BitPackingLib.setPacked(
            data,
            BitPackingLib.LEVEL_COUNT_SHIFT,
            BitPackingLib.MASK_24,
            newLevelCount
        );
        data = BitPackingLib.setPacked(
            data,
            BitPackingLib.FROZEN_UNTIL_LEVEL_SHIFT,
            BitPackingLib.MASK_24,
            newFrozenLevel
        );
        if (1 >= currentPassType) {
            data = BitPackingLib.setPacked(
                data,
                BitPackingLib.WHALE_PASS_TYPE_SHIFT,
                3,
                1
            );
        }
        data = BitPackingLib.setPacked(
            data,
            BitPackingLib.LAST_LEVEL_SHIFT,
            BitPackingLib.MASK_24,
            lastLevelTarget
        );

        uint24 day = _currentMintDay();
        data = _setMintDay(
            data,
            day,
            BitPackingLib.DAY_SHIFT,
            BitPackingLib.MASK_32
        );

        // Front-load the LEVEL mint streak by the same freeze delta (survives pass expiry).
        data = _withPassStreakFrontLoad(
            data,
            ticketStartLevel,
            newFrozenLevel,
            levelsToAdd
        );

        mintPacked_[player] = data;

        _queueEntryRange(player, ticketStartLevel, 10, entriesPerLevel, false);
        emit PassActivated(player, false, ticketStartLevel, newFrozenLevel, data);
    }

    /// @dev Apply whale pass stats (levelCount/freeze/passType/lastLevel/day) without queueing tickets.
    /// @param player Address receiving the whale pass stats.
    /// @param ticketStartLevel First level of the 100-level range for whale pass tickets.
    function _applyWhalePassStats(
        address player,
        uint24 ticketStartLevel
    ) internal {
        uint256 prevData = mintPacked_[player];

        uint24 frozenUntilLevel = uint24(
            (prevData >> BitPackingLib.FROZEN_UNTIL_LEVEL_SHIFT) &
                BitPackingLib.MASK_24
        );
        uint24 levelCount = uint24(
            (prevData >> BitPackingLib.LEVEL_COUNT_SHIFT) &
                BitPackingLib.MASK_24
        );

        // Calculate freeze extension and stat boost (delta-based, no double dipping)
        uint24 targetFrozenLevel = ticketStartLevel + 99;
        uint24 newFrozenLevel = frozenUntilLevel > targetFrozenLevel
            ? frozenUntilLevel
            : targetFrozenLevel;
        uint24 deltaFreeze = newFrozenLevel > frozenUntilLevel
            ? (newFrozenLevel - frozenUntilLevel)
            : 0;
        uint24 levelsToAdd = 100;
        if (levelsToAdd > deltaFreeze) {
            levelsToAdd = deltaFreeze;
        }

        uint24 newLevelCount = levelCount + levelsToAdd;

        uint256 data = prevData;
        data = BitPackingLib.setPacked(
            data,
            BitPackingLib.LEVEL_COUNT_SHIFT,
            BitPackingLib.MASK_24,
            newLevelCount
        );
        data = BitPackingLib.setPacked(
            data,
            BitPackingLib.FROZEN_UNTIL_LEVEL_SHIFT,
            BitPackingLib.MASK_24,
            newFrozenLevel
        );
        data = BitPackingLib.setPacked(
            data,
            BitPackingLib.WHALE_PASS_TYPE_SHIFT,
            3,
            3
        ); // 3 = 100-level pass
        data = BitPackingLib.setPacked(
            data,
            BitPackingLib.LAST_LEVEL_SHIFT,
            BitPackingLib.MASK_24,
            newFrozenLevel
        );

        uint24 day = _currentMintDay();
        data = _setMintDay(
            data,
            day,
            BitPackingLib.DAY_SHIFT,
            BitPackingLib.MASK_32
        );
        // Front-load the LEVEL mint streak by the same freeze delta (survives pass expiry).
        data = _withPassStreakFrontLoad(
            data,
            ticketStartLevel,
            newFrozenLevel,
            levelsToAdd
        );

        mintPacked_[player] = data;
        emit PassActivated(player, true, ticketStartLevel, newFrozenLevel, data);
    }

    /// @dev Returns the current day index.
    function _simulatedDayIndex() internal view returns (uint24) {
        return GameTimeLib.currentDayIndex();
    }

    /// @dev Whether the liveness-timeout game-over trigger is active.
    ///      Level 0: deploy idle timeout (365 days since purchaseStartDay).
    ///      Level 1+: 120-day inactivity timeout since purchaseStartDay.
    ///
    ///      Productive-phase pause: returns false while lastPurchaseDay or
    ///      jackpotPhaseFlag is set. The day clock would otherwise fire
    ///      inside the multi-call window between target-met and phase
    ///      transition close (when purchaseStartDay is finally updated to
    ///      the new level's start), but _handleGameOverPath is unreachable
    ///      in that window (gated by !inJackpot && !lastPurchase at
    ///      AdvanceModule:182), so a fire would deadlock _queueEntries calls
    ///      with no path to clear rngLockedFlag. phaseTransitionActive is
    ///      implied by jackpotPhaseFlag throughout — they clear together at
    ///      AdvanceModule:328-331.
    ///
    ///      Day math is evaluated first so mid-drain RNG requests (which set
    ///      rngRequestTime during _handleGameOverPath) cannot transiently flip
    ///      liveness back to false while the drain is in progress.
    ///
    ///      The day clock is the sole cause of death: nothing ends a level
    ///      before its deadline. Past the deadline, a request already in flight
    ///      SUPPRESSES the trigger for _VRF_GRACE_PERIOD rather than confirming
    ///      it, so a stall beginning near the deadline gets its full window to
    ///      recover — players can propose a coordinator rotation via
    ///      DegenerusAdmin, the 12h retry re-arms, and missed days are credited
    ///      back to purchaseStartDay in AdvanceModule.rngGate on fulfillment.
    ///      Once the stall outlives the window — genuine VRF death, or any bug
    ///      that bricks the cycle before _unlockRng — the trigger fires and the
    ///      historical-fallback path in _gameOverEntropy engages, letting funds
    ///      drain to players via terminal jackpot rather than staying trapped.
    ///      Suppression is bounded by the window, so terminal release is always
    ///      reachable within it.
    function _livenessTriggered() internal view returns (bool) {
        // Jackpot / last-purchase suppress the in-phase clocks (they would false-fire in the
        // productive window between target-met and phase-transition close), but the
        // phase-independent VRF-death deadman still fires here so a permanently-stalled game in
        // these phases reaches terminal fund release instead of bricking.
        if (lastPurchaseDay || jackpotPhaseFlag) return _vrfDeadmanFired();
        uint24 deadlineDay = purchaseStartDay +
            uint24(level == 0 ? _DEPLOY_IDLE_TIMEOUT_DAYS : 120);
        if (_simulatedDayIndex() <= deadlineDay) return false;
        // Past the deadline. A request already in flight when it passed SUPPRESSES the trigger
        // for the grace window instead of confirming it: the word can still land, and both the
        // 12h retry and a coordinator rotation re-arm inside that window. Only a pre-deadline
        // request suppresses — every later stamp is the terminal path's own request, which must
        // never flip the trigger back off while the multi-tx drain is in progress.
        uint48 rngStart = rngRequestTime;
        return
            rngStart == 0 ||
            block.timestamp - rngStart >= _VRF_GRACE_PERIOD ||
            _simulatedDayIndexAt(rngStart) > deadlineDay;
    }

    /// @dev VRF-death deadman: true once no day has sealed for _VRF_DEADMAN_DAYS. dailyIdx
    ///      advances only in _unlockRng (a completed day), so currentDay - dailyIdx counts days
    ///      since real progress and freezes during any stall — and stays frozen until game-over
    ///      latches (the terminal _unlockRng runs after gameOver is set), so it never evaporates
    ///      mid-drain. Phase-independent, unlike _livenessTriggered: advanceGame consults it to
    ///      reach terminal fund release even while jackpotPhaseFlag / lastPurchaseDay are set.
    function _vrfDeadmanFired() internal view returns (bool) {
        return _simulatedDayIndex() - dailyIdx > _VRF_DEADMAN_DAYS;
    }

    /// @dev Returns the day index for a specific timestamp.
    function _simulatedDayIndexAt(uint48 ts) internal pure returns (uint24) {
        return GameTimeLib.currentDayIndexAt(ts);
    }

    /// @dev Gets the current mint day from dailyIdx or calculates from timestamp.
    function _currentMintDay() internal view returns (uint24) {
        uint24 day = dailyIdx;
        if (day == 0) {
            day = _simulatedDayIndex();
        }
        return day;
    }

    /// @dev Updates the day field in packed mint data if changed.
    function _setMintDay(
        uint256 data,
        uint24 day,
        uint256 dayShift,
        uint256 dayMask
    ) internal pure returns (uint256) {
        uint24 prevDay = uint24((data >> dayShift) & dayMask);
        if (prevDay == day) return data;
        uint256 clearedDay = data & ~(dayMask << dayShift);
        return clearedDay | (uint256(day) << dayShift);
    }

    // =========================================================================
    // VRF Configuration (on the shared base for module access)
    // =========================================================================

    /// @dev Chainlink VRF V2.5 coordinator contract.
    ///      Mutable for emergency rotation; see updateVrfCoordinatorAndSub().
    IVRFCoordinator internal vrfCoordinator;

    /// @dev VRF key hash identifying the oracle and gas lane.
    ///      Rotatable with coordinator; determines gas price tier.
    bytes32 internal vrfKeyHash;

    /// @dev VRF subscription ID for LINK billing.
    ///      Mutable to allow subscription rotation without redeploying.
    uint256 internal vrfSubscriptionId;

    // =========================================================================
    // Lootbox RNG Packed Slot (7 variables in 240/256 bits)
    // =========================================================================
    //
    // Layout (LSB -> MSB):
    //   [bits   0:47]   lootboxRngIndex          uint48   (281T indices)
    //   [bits  48:111]  lootboxRngPendingEth     uint64   (scaled /1e15, 0.001 ETH res, far exceeds ETH supply)
    //   [bits 112:175]  lootboxRngThreshold      uint64   (scaled /1e15, 0.001 ETH res, far exceeds ETH supply)
    //   [bits 176:183]  middayMaxBasefeeGwei     uint8    (whole gwei, 0 disables the gate)
    //   [bits 184:223]  lootboxRngPendingFlip  uint40   (scaled /1e18, 1 FLIP res, max ~1.1T FLIP)
    //   [bits 224:231]  midDayTicketRngPending   uint8    (bool flag, 8 bits)
    //   [bits 232:239]  gameOverFallbackLatched  uint8    (bool flag, 8 bits)
    //   [bits 240:247]  gameOverDrainLevelLatch  uint8    (0=unset, 1=lvl, 2=lvl+1)
    //   [bits 248:255]  gameOverSwapConsumed     uint8    (bool flag, 8 bits)

    /// @dev Packed lootbox RNG state. See layout comment above.
    ///      Initialized with lootboxRngIndex=1, lootboxRngThreshold=1 ether (scaled=1000),
    ///      middayMaxBasefeeGwei=5.
    uint256 internal lootboxRngPacked =
        uint256(1)                                  // lootboxRngIndex = 1
        | (uint256(1000) << 112)                    // lootboxRngThreshold = 1 ether / 1e15 = 1000
        | (uint256(5) << 176);                      // middayMaxBasefeeGwei = 5

    // ---- lootboxRng shifts and masks ----
    uint256 internal constant LR_INDEX_SHIFT = 0;
    uint256 internal constant LR_INDEX_MASK = 0xFFFFFFFFFFFF;                // 48 bits
    uint256 internal constant LR_PENDING_ETH_SHIFT = 48;
    uint256 internal constant LR_PENDING_ETH_MASK = 0xFFFFFFFFFFFFFFFF;      // 64 bits
    uint256 internal constant LR_THRESHOLD_SHIFT = 112;
    uint256 internal constant LR_THRESHOLD_MASK = 0xFFFFFFFFFFFFFFFF;        // 64 bits
    uint256 internal constant LR_PENDING_FLIP_SHIFT = 184;
    uint256 internal constant LR_PENDING_FLIP_MASK = 0xFFFFFFFFFF;         // 40 bits
    uint256 internal constant LR_MID_DAY_SHIFT = 224;
    uint256 internal constant LR_MID_DAY_MASK = 0xFF;                       // 8 bits
    uint256 internal constant LR_MAX_BASEFEE_SHIFT = 176;
    uint256 internal constant LR_MAX_BASEFEE_MASK = 0xFF;                   // 8 bits
    uint256 internal constant LR_GO_FALLBACK_SHIFT = 232;
    uint256 internal constant LR_GO_FALLBACK_MASK = 0xFF;                   // 8 bits
    uint256 internal constant LR_GO_LVL_SHIFT = 240;
    uint256 internal constant LR_GO_LVL_MASK = 0xFF;                        // 8 bits
    uint256 internal constant LR_GO_SWAP_SHIFT = 248;
    uint256 internal constant LR_GO_SWAP_MASK = 0xFF;                       // 8 bits

    /// @dev Ceiling on the tunable mid-day basefee gate, in whole gwei (the field is 8
    ///      bits). Zero disables the gate, letting mid-day requests issue at any price.
    uint256 internal constant MIDDAY_MAX_BASEFEE_GWEI_CAP = 255;

    /// @dev Gas a mid-day fulfillment bills, summing the three terms the coordinator
    ///      charges for: the ~50k callback, mainnet's ~112k proof verification, and the
    ///      coordinator's own gasAfterPaymentCalculation of 38,900, which it adds to the
    ///      gas it measured. It bills gas actually used, not the request's
    ///      callbackGasLimit, so this tracks the real figure rather than the reservation.
    uint256 internal constant MIDDAY_RNG_BILLED_GAS = 201_000;

    /// @dev Multiple of the billed gas charged against a donor's credit: a 5x markup times
    ///      the coordinator's 20% LINK premium. Charging a multiple of what the request
    ///      actually costs — rather than a fixed price — keeps the charge tracking gas
    ///      with no stored rate to re-calibrate as gas or LINK/ETH drifts. The markup
    ///      holds while a fulfillment prices within 5x the request block's basefee and the
    ///      feed tracks the coordinator's own LINK valuation; outside that band a
    ///      redemption bills more than it charged. What bounds the subscription's exposure
    ///      is the mid-day LINK floor rather than this multiple — requests stop below
    ///      MIN_LINK_FOR_LOOTBOX_RNG, leaving that balance to the daily word, which is
    ///      never gated. The craps table answers to MIN_LINK_FOR_CRAPS_RNG instead, a
    ///      reserve sized to one daily word rather than to a queue that can wait for it.
    uint256 internal constant MIDDAY_RNG_CHARGE_MULT = 6;

    /// @dev Scale factor for ETH/LINK packing (0.001 resolution).
    uint256 internal constant LR_ETH_SCALE = 1e15;
    /// @dev Scale factor for FLIP packing (1 token resolution).
    uint256 internal constant LR_FLIP_SCALE = 1e18;

    // Activity score EV multiplier constants (ETH lootbox only)
    /// @dev 60-point activity score = neutral 100% EV
    uint16 internal constant LOOTBOX_EV_ACTIVITY_NEUTRAL_POINTS = 60;
    /// @dev 400-point activity score = the seg-A knee (~139.5% EV)
    uint16 internal constant LOOTBOX_EV_ACTIVITY_MAX_POINTS = 400;
    /// @dev Minimum EV at 0-point activity (90%)
    uint16 internal constant LOOTBOX_EV_MIN_BPS = 9_000;
    /// @dev Neutral EV at 60-point activity (100%)
    uint16 internal constant LOOTBOX_EV_NEUTRAL_BPS = 10_000;
    /// @dev EV at the seg-A knee (139.5%, 90% of the gain)
    uint16 internal constant LOOTBOX_EV_VA_BPS = 13_950;
    /// @dev EV at the seg-B knee (143.9%, 98% of the gain)
    uint16 internal constant LOOTBOX_EV_VB_BPS = 14_390;
    /// @dev Maximum EV (145%, reached at the effective cap)
    uint16 internal constant LOOTBOX_EV_MAX_BPS = 14_500;
    /// @dev Maximum EV benefit cap per account per level (10 ETH scaled)
    uint256 internal constant LOOTBOX_EV_BENEFIT_CAP =
        10 ether;

    /// @dev Read a field from the packed lootbox RNG slot.
    function _lrRead(uint256 shift, uint256 mask) internal view returns (uint256) {
        return (lootboxRngPacked >> shift) & mask;
    }

    /// @dev Write a field to the packed lootbox RNG slot.
    function _lrWrite(uint256 shift, uint256 mask, uint256 value) internal {
        lootboxRngPacked = (lootboxRngPacked & ~(mask << shift)) | ((value & mask) << shift);
    }

    /// @dev Add a delta to a field of the packed lootbox RNG slot in one load + store.
    ///      The summed field re-masks before the merge — the same wrap-on-mask
    ///      semantics as _lrWrite(shift, mask, _lrRead(shift, mask) + delta).
    function _lrAdd(uint256 shift, uint256 mask, uint256 delta) internal {
        uint256 packed = lootboxRngPacked;
        lootboxRngPacked =
            (packed & ~(mask << shift)) |
            (((((packed >> shift) & mask) + delta) & mask) << shift);
    }

    /// @dev Pack a wei amount to milli-ETH (divide by 1e15). 0.001 ETH resolution.
    function _packEthToMilliEth(uint256 wei_) internal pure returns (uint64) {
        return uint64(wei_ / LR_ETH_SCALE);
    }

    /// @dev Unpack milli-ETH to wei (multiply by 1e15).
    function _unpackMilliEthToWei(uint64 milli) internal pure returns (uint256) {
        return uint256(milli) * LR_ETH_SCALE;
    }

    /// @dev Pack a wei amount to whole FLIP (divide by 1e18). 1 FLIP resolution.
    function _packFlipToWhole(uint256 wei_) internal pure returns (uint40) {
        return uint40(wei_ / LR_FLIP_SCALE);
    }

    /// @dev Total boxes in a packed order — the four bought tiers plus the cover box, if any.
    ///      The sweep's skip check wants only this, and it runs per entry.
    function _boxOrderCount(uint256 word) internal pure returns (uint256) {
        unchecked {
            return ((word >> LB_SMALL_SHIFT) & LB_COUNT_MASK)
                + ((word >> LB_MED_SHIFT) & LB_COUNT_MASK)
                + ((word >> LB_LARGE_SHIFT) & LB_COUNT_MASK)
                + ((word >> LB_CUSTOM_COUNT_SHIFT) & LB_COUNT_MASK)
                + (((word >> LB_COVER_SHIFT) & LB_COVER_MASK) == 0 ? 0 : 1);
        }
    }

    /// @dev EV multiplier from a raw activity score (whole points).
    ///      Unchanged low anchor 90%→100% (0 to 60 points), then a steep ramp to vA
    ///      (139.5%) at the 400-point knee, a shallow leg to vB (143.9%) at the seg-B
    ///      knee, and a near-flat crawl to 145% at the effective cap.
    /// @param score The activity score in whole points
    /// @return The EV multiplier in basis points (9000-14500)
    function _lootboxEvMultiplierFromScore(
        uint256 score
    ) internal pure returns (uint256) {
        if (score <= LOOTBOX_EV_ACTIVITY_NEUTRAL_POINTS) {
            // Linear: 0-point → 90% EV, 60-point → 100% EV
            return LOOTBOX_EV_MIN_BPS +
                (score * (LOOTBOX_EV_NEUTRAL_BPS - LOOTBOX_EV_MIN_BPS)) /
                LOOTBOX_EV_ACTIVITY_NEUTRAL_POINTS;
        }
        if (score >= ActivityCurveLib.ACTIVITY_EFFECTIVE_CAP_POINTS) {
            return LOOTBOX_EV_MAX_BPS;
        }
        if (score <= LOOTBOX_EV_ACTIVITY_MAX_POINTS) {
            // seg A: 60-point → 100% EV, 400-point → 139.5% EV
            return
                LOOTBOX_EV_NEUTRAL_BPS +
                ((score - LOOTBOX_EV_ACTIVITY_NEUTRAL_POINTS) *
                    (LOOTBOX_EV_VA_BPS - LOOTBOX_EV_NEUTRAL_BPS)) /
                (LOOTBOX_EV_ACTIVITY_MAX_POINTS -
                    LOOTBOX_EV_ACTIVITY_NEUTRAL_POINTS);
        }
        if (score <= ActivityCurveLib.ACTIVITY_SEG_B_KNEE_POINTS) {
            // seg B: 400-point → 139.5% EV, seg-B knee → 143.9% EV
            return
                LOOTBOX_EV_VA_BPS +
                ((score - LOOTBOX_EV_ACTIVITY_MAX_POINTS) *
                    (LOOTBOX_EV_VB_BPS - LOOTBOX_EV_VA_BPS)) /
                (ActivityCurveLib.ACTIVITY_SEG_B_KNEE_POINTS -
                    LOOTBOX_EV_ACTIVITY_MAX_POINTS);
        }
        // seg C: seg-B knee → 143.9% EV, effective cap → 145% EV
        return
            LOOTBOX_EV_VB_BPS +
            ((score - ActivityCurveLib.ACTIVITY_SEG_B_KNEE_POINTS) *
                (LOOTBOX_EV_MAX_BPS - LOOTBOX_EV_VB_BPS)) /
            (ActivityCurveLib.ACTIVITY_EFFECTIVE_CAP_POINTS -
                ActivityCurveLib.ACTIVITY_SEG_B_KNEE_POINTS);
    }

    /// @dev RNG words keyed by lootbox RNG index.
    mapping(uint48 => uint256) internal lootboxRngWordByIndex;

    // =========================================================================
    // Deity Boon Tracking
    // =========================================================================

    /// @dev Per-deity boon assignment day + used-slot mask, packed into one slot:
    ///      bits [0:24) = day the boon slots were assigned, bits [24:32) = bitmask of
    ///      used slots for that day (bit i = slot i used). A stale day reads its mask
    ///      as irrelevant because every reader gates on the day matching; the day-roll
    ///      write re-stamps the day with a fresh (zero) mask in one store.
    mapping(address => uint32) internal deityBoonPacked;

    /// @dev Day when recipient last received a deity boon (prevents double-receipt
    ///      on the same day, regardless of which deity issues it).
    mapping(address => uint24) internal deityBoonRecipientDay;

    // =========================================================================
    // Degenerette (Roulette) Bets
    // =========================================================================

    /// @dev Bets keyed by player and bet id.
    /// Packed layout (LSB → MSB):
    /// - [0..31]    customTraits (packed 4×8-bit quadrants)
    /// - [32..39]   spinCount (uint8)
    /// - [40..41]   currency (0=ETH,1=FLIP,2=unsupported,3=WWXRP)
    /// - [42..169]  amountPerSpin (uint128)
    /// - [170..201] RNG index (uint32)
    /// - [202..217] activity score in whole points (uint16)
    /// - [218..219] heroQuadrant (always-on hero quadrant, 0..3)
    /// - [220..255] biggest-spin record bounty in WHOLE FLIP (0 = none), staked as its
    ///              own FLIP spin chain when the bet resolves
    mapping(address => mapping(uint64 => uint256)) internal degeneretteBets;

    /// @dev Per-player bet counters for Degenerette.
    mapping(address => uint64) internal degeneretteBetNonce;

    // =========================================================================
    // Lootbox EV Multiplier Cap Tracking
    // =========================================================================

    /// @dev Per-player lootbox EV-multiplier benefit used, two level-stamped windows in
    ///      one slot. At any instant only the keys {currentLevel, currentLevel+1} are live
    ///      (opens RMW currentLevel, deposits RMW level+1), so two windows hold the full
    ///      live set with no eviction of a live key. Each window: used (64 bits) + level
    ///      stamp (24 bits). `used` is clamped to LOOTBOX_EV_BENEFIT_CAP = 10 ether = 1e19
    ///      < 2^64 at every write. A non-matching stamp reads as 0 (a fresh allowance).
    ///      Window A: bits [0:64) used, [64:88) level. Window B: bits [88:152) used, [152:176) level.
    mapping(address => uint256) internal lootboxEvCapPacked;

    uint256 private constant _EV_USED_MASK = (uint256(1) << 64) - 1;
    uint256 private constant _EV_WINDOW_A_MASK = (uint256(1) << 88) - 1;
    uint256 private constant _EV_WINDOW_B_MASK =
        ((uint256(1) << 88) - 1) << 88;

    /// @dev A player's EV benefit used for `level`; 0 if neither window is stamped to it.
    function _lootboxEvUsedFor(address player, uint24 level)
        internal
        view
        returns (uint256)
    {
        uint256 packed = lootboxEvCapPacked[player];
        if (uint24(packed >> 64) == level) return packed & _EV_USED_MASK;
        if (uint24(packed >> 152) == level) return (packed >> 88) & _EV_USED_MASK;
        return 0;
    }

    /// @dev Record `used` for `level`: into the window already stamped to `level`, else
    ///      evict the smaller-level window (the older of the two; never a live key, since
    ///      the live set is {currentLevel, currentLevel+1}).
    function _setLootboxEvUsedFor(
        address player,
        uint24 level,
        uint256 used
    ) internal {
        uint256 packed = lootboxEvCapPacked[player];
        uint24 lvlA = uint24(packed >> 64);
        uint24 lvlB = uint24(packed >> 152);
        uint256 windowA = (uint256(level) << 64) | (used & _EV_USED_MASK);
        if (lvlA == level) {
            lootboxEvCapPacked[player] =
                (packed & ~_EV_WINDOW_A_MASK) |
                windowA;
        } else if (lvlB == level) {
            lootboxEvCapPacked[player] =
                (packed & ~_EV_WINDOW_B_MASK) |
                (windowA << 88);
        } else if (lvlA <= lvlB) {
            lootboxEvCapPacked[player] =
                (packed & ~_EV_WINDOW_A_MASK) |
                windowA;
        } else {
            lootboxEvCapPacked[player] =
                (packed & ~_EV_WINDOW_B_MASK) |
                (windowA << 88);
        }
    }

    // =========================================================================
    // Decimator Jackpot State
    // =========================================================================
    // All decimator logic is consolidated into the DecimatorModule.

    /// @dev Player's decimator burn entry per level.
    struct DecBet {
        /// @notice Total FLIP burned by player this level (capped at uint192.max).
        uint192 burn;
        /// @notice Player's denominator choice (2-12), may improve to lower denom during level.
        uint8 bucket;
        /// @notice Deterministic subbucket from hash(player, lvl, bucket), range 0..(bucket-1).
        uint8 subBucket;
        /// @notice Claim flag (0 = unclaimed, 1 = claimed).
        uint8 claimed;
    }

    /// @dev Snapshot of a decimator jackpot for claim processing. All three fields pack
    ///      into ONE slot (96 + 128 + 32 = 256 bits).
    struct DecClaimRound {
        /// @notice ETH prize pool available for claims. uint96 (7.9e28 wei = 7.9e10 ETH,
        ///         far above any reachable pool; mirrors TerminalDecClaimRound.poolWei).
        uint96 poolWei;
        /// @notice Total qualifying burn across winning subbuckets (denominator for
        ///         pro-rata). Sum of per-burn effective amounts (<= ~2.35x the FLIP
        ///         burned, supply-capped at uint128); realistic per-level totals sit
        ///         ~1e8x under uint128. Mirrors TerminalDecClaimRound.totalBurn.
        uint128 totalBurn;
        /// @notice Stored seed for the claim-time lootbox draw only. The winning subbuckets
        ///         are selected from the FULL VRF word at snapshot and stored separately in
        ///         decBucketOffsetPacked, so this never gates winner selection. Its sole
        ///         consumer (resolveLootboxDirect) combines it via keccak with frozen inputs
        ///         (winner address, sealed amount/evScore) — no player-controlled input — so
        ///         32 bits of post-fulfillment-revealed entropy cannot be ground or predicted.
        uint32 rngWord;
    }

    /// @dev Player decimator entries per level.
    ///      decBurn[lvl][player] = DecBet
    mapping(uint24 => mapping(address => DecBet)) internal decBurn;

    /// @dev Aggregated burn totals per level/denom/subbucket.
    ///      decBucketBurnTotal[lvl][denom][sub] = total burn in that subbucket.
    ///      Array sized [13][13] to allow direct indexing (denom 0-12, sub 0-12).
    mapping(uint24 => uint256[13][13]) internal decBucketBurnTotal;

    /// @dev Decimator claim round snapshots per level.
    ///      Claims persist indefinitely — no expiry on prior rounds.
    mapping(uint24 => DecClaimRound) internal decClaimRounds;

    /// @dev Packed winning subbucket per denominator for a level.
    ///      4 bits each for denom 2..12 (44 bits total, fits in uint64).
    ///      Layout: bits 0-3 = denom 2, bits 4-7 = denom 3, etc.
    mapping(uint24 => uint64) internal decBucketOffsetPacked;

    // =========================================================================
    // Degenerette Hero Wager Tracking (Daily)
    // =========================================================================

    /// @dev Daily hero symbol wagers (ETH only), indexed by day.
    ///      Key: day index (from GameTimeLib). Value: 4 packed uint256s.
    ///      Each uint256 packs 8 × 32-bit amounts (one per symbol in that quadrant).
    ///      Amounts stored in units of 1e14 wei (0.0001 ETH) to fit 32 bits
    ///      (max ~429,500 ETH per symbol per day).
    mapping(uint24 => uint256[4]) internal dailyHeroWagers;

    // =========================================================================
    // Segregated Yield Accumulator
    // =========================================================================

    /// @dev Segregated stETH yield accumulator.
    ///      Collects 23% of yield surplus each level transition (one of four 23% shares).
    ///      x00 milestones: 50% to currentPrizePool, 50% retained as terminal insurance.
    ///      INVARIANT: counted as obligation in yield surplus calculation.
    uint256 internal yieldAccumulator;

    // =========================================================================
    // Century (x00) Ticket Bonus Tracking
    // =========================================================================

    /// @dev Per-player century (x00) bonus usage, packed as (level << 224 | used).
    ///      The high bits stamp WHICH x00 level the usage applies to, so every
    ///      player is independent: a value stamped to a prior century reads as 0
    ///      (a fresh 20-ETH allowance) with no global reset. Enforces the
    ///      20-ETH-equivalent per-player cap across multiple buys at one level.
    mapping(address => uint256) internal centuryBonusUsed;

    uint256 private constant _CENTURY_USED_MASK = (uint256(1) << 224) - 1;

    /// @dev A player's century-bonus usage for the given x00 level; 0 if the
    ///      stored stamp belongs to a prior century (stale).
    function _centuryUsedFor(address player, uint256 level) internal view returns (uint256) {
        uint256 packed = centuryBonusUsed[player];
        return (packed >> 224) == level ? (packed & _CENTURY_USED_MASK) : 0;
    }

    /// @dev Records a player's century-bonus usage, stamped to the given x00 level.
    function _setCenturyUsedFor(address player, uint256 level, uint256 used) internal {
        centuryBonusUsed[player] = (level << 224) | (used & _CENTURY_USED_MASK);
    }

    // =========================================================================
    // Terminal Decimator (Always-Open Death Bet)
    // =========================================================================

    /// @dev Per-player terminal decimator entry. Packed into a single 256-bit slot (240/256 bits).
    ///      totalBurn: pre-time-multiplier cumulative burn (capped at DECIMATOR_MULTIPLIER_CAP).
    ///      weightedBurn: post-time-multiplier cumulative burn (used for claim share calculation).
    ///      bucket: bucket denominator (2-12), computed from activity score using lvl 100 rules.
    ///      subBucket: deterministic from keccak256(player, level, bucket).
    ///      burnLevel: which level this entry belongs to (stale detection for lazy reset).
    ///      boosted: set once a final-day streak boost has been applied this level (one-time).
    struct TerminalDecBet {
        uint80 totalBurn;
        uint88 weightedBurn;
        uint8 bucket;
        uint8 subBucket;
        uint48 burnLevel;
        bool boosted;
    }
    mapping(address => TerminalDecBet) internal terminalDecBets;

    /// @dev Per-bucket aggregates for terminal decimator.
    ///      Key: keccak256(abi.encode(level, denom, subBucket)) -> total weighted burn.
    mapping(bytes32 => uint256) internal terminalDecBucketBurnTotal;

    /// @dev Resolution snapshot for terminal decimator claims (set at GAMEOVER).
    ///      Packed into a single 256-bit slot (248/256 bits).
    ///      No rngWord needed — claims are 100% ETH post-GAMEOVER (auto-rebuy skipped).
    struct TerminalDecClaimRound {
        uint24 lvl;
        uint96 poolWei;
        uint128 totalBurn;
    }
    TerminalDecClaimRound internal lastTerminalDecClaimRound;

    // =========================================================================
    // Boon Packed Storage
    // =========================================================================

    /// @dev Packed boon state for a single player. 2 storage slots.
    ///
    /// Slot 0 (256 bits):
    ///   [0-23]    coinflipDay          uint24   Day coinflip boon was awarded
    ///   [24-47]   deityCoinflipDay     uint24   Deity-source day for coinflip boon
    ///   [48-55]   coinflipTier         uint8    0=none, 1=5%, 2=10%, 3=25%
    ///   [56-79]   lootboxBoostDay      uint24   Day lootbox boost was awarded
    ///   [80-103]  deityLootboxDay      uint24   Deity-source day for lootbox boost
    ///   [104-111] lootboxBoostTier     uint8    0=none, 1=5%, 2=15%, 3=25%
    ///   [112-135] purchaseDay          uint24   Day purchase boost was awarded
    ///   [136-159] deityPurchaseDay     uint24   Deity-source day for purchase boost
    ///   [160-167] purchaseTier         uint8    0=none, 1=5%, 2=15%, 3=25%
    ///   [168-175] decimatorTier        uint8    0=none, 1=10%, 2=25%, 3=50%
    ///   [176-199] deityDecimatorDay    uint24   Deity-source day for decimator
    ///   [200-223] whaleDay             uint24   Day whale boon was awarded
    ///   [224-247] deityWhaleDay        uint24   Deity-source day for whale boon
    ///   [248-255] whaleTier            uint8    0=none, 1=10%, 2=20%, 3=35%
    ///
    /// Slot 1 (bits 0-23 and 72-255 used; bits 24-71 free):
    ///   [0-23]    craps                uint24   Craps stake-boon lane (the LOW lane, so the
    ///                                           consumption hot path masks without shifting)
    ///   [24-71]   (free)                        Activity awards are credited to player
    ///                                           stats on award and hold no boon state
    ///   [72-79]   deityPassTier        uint8    0=none, 1=10%, 2=20%, 3=35%
    ///   [80-103]  deityPassDay         uint24   Day deity pass boon was awarded
    ///   [104-127] deityDeityPassDay    uint24   Deity-granted deity pass boon day
    ///   [128-151] lazyPassDay          uint24   Day lazy pass boon was awarded
    ///   [152-175] deityLazyPassDay     uint24   Deity-source day for lazy pass boon
    ///   [176-183] lazyPassTier         uint8    0=none, 1=10%, 2=25%, 3=50%
    ///   [184-207] degeneretteEth       uint24   ETH degenerette stake-boon lane
    ///   [208-231] degeneretteFlip      uint24   FLIP degenerette stake-boon lane
    ///   [232-255] degeneretteWwxrp     uint24   WWXRP degenerette stake-boon lane
    ///
    /// The craps lane and the three degenerette lanes share ONE 24-bit encoding:
    ///   [0-1]  tier    0=none, else 1..3 — the family decodes the size
    ///   [2]    isDeity deity-granted boons die at midnight of their day
    ///   [3-23] day     low 21 bits of the award day (lootbox-rolled boons live
    ///                  BOON_LANE_EXPIRY_DAYS past it; comparisons run on
    ///                  masked values, wrapping after ~5,700 years)
    ///
    /// Tier decode is per-family and NOT part of the encoding: a degenerette lane reads
    /// tier x 400 (+4/8/12%), the craps lane reads _coinflipTierToBps on the wire
    /// (500/1000/2500) and the craps table pays it at 5/10/15%.
    ///
    /// A degenerette lane is one INDEPENDENT per-currency stake boon — lanes coexist and only a
    /// boon of the same currency can displace one — and is spent by the next bet in its own
    /// currency. The craps lane is single and is spent by the next paid craps burn.
    struct BoonPacked {
        uint256 slot0;
        uint256 slot1;
    }

    /// @dev Per-player packed boon state. Public getter returns (uint256 slot0, uint256
    ///      slot1); bit layout above. UI readers combine with currentDayView() to compute
    ///      per-category expiry.
    mapping(address => BoonPacked) public boonPacked;

    // =========================================================================
    // claimBingo color-completion flags (claimBingo-EXCLUSIVE)
    //
    // Keyed by uint24 level. The ONLY reader/writer of these mappings is
    // DegenerusGameBingoModule.claimBingo.
    // =========================================================================

    /// @dev Whether a player has claimed their one bingo reward on a level.
    ///      bingoClaimed[level][player].
    mapping(uint24 => mapping(address => bool)) internal bingoClaimed;

    // ---- Slot 0 shifts ----
    uint256 internal constant BP_COINFLIP_DAY_SHIFT = 0;
    uint256 internal constant BP_DEITY_COINFLIP_DAY_SHIFT = 24;
    uint256 internal constant BP_COINFLIP_TIER_SHIFT = 48;
    uint256 internal constant BP_LOOTBOX_DAY_SHIFT = 56;
    uint256 internal constant BP_DEITY_LOOTBOX_DAY_SHIFT = 80;
    uint256 internal constant BP_LOOTBOX_TIER_SHIFT = 104;
    uint256 internal constant BP_PURCHASE_DAY_SHIFT = 112;
    uint256 internal constant BP_DEITY_PURCHASE_DAY_SHIFT = 136;
    uint256 internal constant BP_PURCHASE_TIER_SHIFT = 160;
    uint256 internal constant BP_DECIMATOR_TIER_SHIFT = 168;
    uint256 internal constant BP_DEITY_DECIMATOR_DAY_SHIFT = 176;
    uint256 internal constant BP_WHALE_DAY_SHIFT = 200;
    uint256 internal constant BP_DEITY_WHALE_DAY_SHIFT = 224;
    uint256 internal constant BP_WHALE_TIER_SHIFT = 248;

    // ---- Slot 1 shifts (the craps lane owns bits 0-23; bits 24-71 are free) ----
    uint256 internal constant BP_DEITY_PASS_TIER_SHIFT = 72;
    uint256 internal constant BP_DEITY_PASS_DAY_SHIFT = 80;
    uint256 internal constant BP_DEITY_DEITY_PASS_DAY_SHIFT = 104;
    uint256 internal constant BP_LAZY_PASS_DAY_SHIFT = 128;
    uint256 internal constant BP_DEITY_LAZY_PASS_DAY_SHIFT = 152;
    uint256 internal constant BP_LAZY_PASS_TIER_SHIFT = 176;
    uint256 internal constant BP_DEGEN_LANE0_SHIFT = 184;
    uint256 internal constant BP_LANE_MASK = 0xFFFFFF;
    uint256 internal constant BP_LANE_TIER_MASK = 0x3;
    uint256 internal constant BP_LANE_DEITY_BIT = 0x4;
    uint256 internal constant BP_LANE_DAY_SHIFT = 3;
    uint256 internal constant BP_LANE_DAY_MASK = 0x1FFFFF;
    /// @dev Days a lootbox-rolled lane boon lives past its stamp day. Shared by the degenerette
    ///      and craps lanes, which carry the same two-day life as the coinflip boon.
    uint24 internal constant BOON_LANE_EXPIRY_DAYS = 2;
    /// @dev Stake-bonus base caps for the degenerette boon (+4/8/12% of the bet's total,
    ///      up to the cap). WWXRP has NO cap — it is worthless by design, so an uncapped
    ///      percentage on it moves no real value. Shared by the Degenerette module (the
    ///      enforcement site) and the Boon module's closed-form EV normalization so the two
    ///      sites can never drift apart.
    uint256 internal constant DEGENERETTE_BOON_ETH_CAP = 10 ether;
    uint256 internal constant DEGENERETTE_BOON_FLIP_CAP = 100_000 ether;

    /// @dev What ONE Craps day pass is worth, as a lootbox denomination. This is the expected cost
    ///      of entering all seven of a day's scheduled windows at 1x — bankroll plus bounty — under
    ///      the shipped preset table, which comes to exactly 1,368,127/60 FLIP, rounded to the
    ///      nearest 100.
    ///
    ///      A DENOMINATION, NOT A QUOTE. The realised cost of any particular day is drawn from that
    ///      day's word and moves; the pass is committed before the word lands, and that is what
    ///      makes a fixed expected-value unit the honest way to price it.
    ///
    ///      ⚠ Tied to the preset table. Any edit to the scheduled bankroll or bounty distribution
    ///      must recompute the expectation, re-round to the nearest 100, and update this — see the
    ///      preset-change invariant in docs/LOOTBOX-CRAPS-DAY-PASS-SPEC.md.
    uint256 internal constant NORMAL_DAY_PASS_VALUE = 22_800 ether;

    /// @dev And what a HIGH-ROLLER day pass is worth: exactly nineteen normal ones. The day's
    ///      multiplier is 10 nine times in ten and 100 the tenth, so its expectation is 19 on the
    ///      nose — defined as the multiple rather than as a separately rounded figure, so the two
    ///      denominations can never drift out of proportion.
    uint256 internal constant HIGH_ROLLER_DAY_PASS_VALUE = 19 * NORMAL_DAY_PASS_VALUE;

    // ---- Masks ----
    uint256 internal constant BP_MASK_24 = 0xFFFFFF;
    uint256 internal constant BP_MASK_8 = 0xFF;

    // ---- Clear masks for boon categories (slot 0) ----
    // Coinflip: bits 0-55 (coinflipDay[24] + deityCoinflipDay[24] + coinflipTier[8])
    uint256 internal constant BP_COINFLIP_CLEAR = ~uint256((1 << 56) - 1);
    // Lootbox: bits 56-111 (lootboxDay[24] + deityLootboxDay[24] + lootboxTier[8])
    uint256 internal constant BP_LOOTBOX_CLEAR =
        ~(uint256((1 << 56) - 1) << 56);
    // Purchase: bits 112-167 (purchaseDay[24] + deityPurchaseDay[24] + purchaseTier[8])
    uint256 internal constant BP_PURCHASE_CLEAR =
        ~(uint256((1 << 56) - 1) << 112);
    // Decimator: bits 168-199 (decimatorTier[8] + deityDecimatorDay[24])
    uint256 internal constant BP_DECIMATOR_CLEAR =
        ~(uint256((1 << 32) - 1) << 168);
    // Whale: bits 200-255 (whaleDay[24] + deityWhaleDay[24] + whaleTier[8])
    uint256 internal constant BP_WHALE_CLEAR = ~(uint256((1 << 56) - 1) << 200);

    // ---- Clear masks for boon categories (slot 1) ----
    // Deity pass: bits 72-127 (deityPassTier[8] + deityPassDay[24] + deityDeityPassDay[24])
    uint256 internal constant BP_DEITY_PASS_CLEAR =
        ~(uint256((1 << 56) - 1) << 72);
    // Lazy pass: bits 128-183 (lazyPassDay[24] + deityLazyPassDay[24] + lazyPassTier[8])
    uint256 internal constant BP_LAZY_PASS_CLEAR =
        ~(uint256((1 << 56) - 1) << 128);

    // =========================================================================
    // Boon Tier <-> BPS Decode/Encode Helpers
    // =========================================================================

    /// @dev Decode coinflip tier to BPS. Tier: 0=0, 1=500, 2=1000, 3=2500.
    function _coinflipTierToBps(uint8 tier) internal pure returns (uint16) {
        if (tier == 3) return 2500;
        if (tier == 2) return 1000;
        if (tier == 1) return 500;
        return 0;
    }

    /// @dev Decode lootbox boost tier to BPS. Tier: 0=0, 1=500, 2=1500, 3=2500.
    function _lootboxTierToBps(uint8 tier) internal pure returns (uint16) {
        if (tier == 3) return 2500;
        if (tier == 2) return 1500;
        if (tier == 1) return 500;
        return 0;
    }

    /// @dev Decode purchase boost tier to BPS. Tier: 0=0, 1=500, 2=1500, 3=2500.
    function _purchaseTierToBps(uint8 tier) internal pure returns (uint16) {
        if (tier == 3) return 2500;
        if (tier == 2) return 1500;
        if (tier == 1) return 500;
        return 0;
    }

    /// @dev Decode decimator boost tier to BPS. Tier: 0=0, 1=1000, 2=2500, 3=5000.
    function _decimatorTierToBps(uint8 tier) internal pure returns (uint16) {
        if (tier == 3) return 5000;
        if (tier == 2) return 2500;
        if (tier == 1) return 1000;
        return 0;
    }

    /// @dev Decode whale boon tier to BPS. Tier: 0=0, 1=1000, 2=2000, 3=3500.
    function _whaleTierToBps(uint8 tier) internal pure returns (uint16) {
        if (tier == 3) return 3500;
        if (tier == 2) return 2000;
        if (tier == 1) return 1000;
        return 0;
    }

    /// @dev Shift of the degenerette lane for a bet currency (0=ETH, 1=FLIP, 3=WWXRP →
    ///      lanes 0/1/2). Callers validate the currency first; 2 is unsupported at
    ///      every call site.
    function _degeneretteLaneShift(uint8 currency) internal pure returns (uint256) {
        return BP_DEGEN_LANE0_SHIFT + uint256(currency == 3 ? 2 : currency) * 24;
    }

    /// @dev Decode a degenerette lane tier to BPS (0-3 → 0/400/800/1200).
    function _degeneretteTierToBps(uint8 tier) internal pure returns (uint16) {
        return uint16(tier) * 400;
    }

    /// @dev Is this degenerette lane's boon live on `currentDay`? A deity-granted boon
    ///      dies at midnight of its day; a lootbox-rolled one lives
    ///      BOON_LANE_EXPIRY_DAYS past its stamp (a day-0 stamp is exempt from
    ///      the stamp rule, mirroring the sibling families). Day fields are 21-bit, so
    ///      both sides compare masked.
    function _boonLaneLive(
        uint256 lane,
        uint24 currentDay
    ) internal pure returns (bool) {
        if (lane & BP_LANE_TIER_MASK == 0) return false;
        uint256 day = (lane >> BP_LANE_DAY_SHIFT) & BP_LANE_DAY_MASK;
        uint256 nowDay = currentDay & BP_LANE_DAY_MASK;
        if (lane & BP_LANE_DEITY_BIT != 0) return day == nowDay;
        return day == 0 || nowDay <= day + BOON_LANE_EXPIRY_DAYS;
    }

    /// @dev Decode lazy pass boon tier to BPS. Tier: 0=0, 1=1000, 2=2500, 3=5000.
    function _lazyPassTierToBps(uint8 tier) internal pure returns (uint16) {
        if (tier == 3) return 5000;
        if (tier == 2) return 2500;
        if (tier == 1) return 1000;
        return 0;
    }

    /// @dev Encode coinflip BPS to tier. 500->1, 1000->2, 2500->3, else 0.
    function _coinflipBpsToTier(uint16 bps) internal pure returns (uint8) {
        if (bps >= 2500) return 3;
        if (bps >= 1000) return 2;
        if (bps >= 500) return 1;
        return 0;
    }

    /// @dev Encode purchase BPS to tier. 500->1, 1500->2, 2500->3, else 0.
    function _purchaseBpsToTier(uint16 bps) internal pure returns (uint8) {
        if (bps >= 2500) return 3;
        if (bps >= 1500) return 2;
        if (bps >= 500) return 1;
        return 0;
    }

    /// @dev Encode decimator BPS to tier. 1000->1, 2500->2, 5000->3, else 0.
    function _decimatorBpsToTier(uint16 bps) internal pure returns (uint8) {
        if (bps >= 5000) return 3;
        if (bps >= 2500) return 2;
        if (bps >= 1000) return 1;
        return 0;
    }

    /// @dev Encode whale BPS to tier. 1000->1, 2000->2, 3500->3, else 0.
    function _whaleBpsToTier(uint16 bps) internal pure returns (uint8) {
        if (bps >= 3500) return 3;
        if (bps >= 2000) return 2;
        if (bps >= 1000) return 1;
        return 0;
    }

    /// @dev Encode lazy pass BPS to tier. 1000->1, 2500->2, 5000->3, else 0.
    function _lazyPassBpsToTier(uint16 bps) internal pure returns (uint8) {
        if (bps >= 5000) return 3;
        if (bps >= 2500) return 2;
        if (bps >= 1000) return 1;
        return 0;
    }

    /// @dev Calculate mint count bonus points (max 25% for perfect participation).
    ///      Perfect participation (100% mints) always = 25 points (25%).
    /// @param mintCount Player's total level mint count.
    /// @param currLevel Current game level.
    /// @return Bonus points (0-25) scaled by participation percentage (integer division).
    function _mintCountBonusPoints(
        uint24 mintCount,
        uint24 currLevel
    ) internal pure returns (uint256) {
        if (currLevel == 0) return 0;
        if (mintCount >= currLevel) return 25;
        return (uint256(mintCount) * 25) / uint256(currLevel);
    }

    // =========================================================================
    // AfKing Subscriptions (game-resident; shared with the GameAfkingModule
    // and the AdvanceModule process STAGE)
    // =========================================================================
    // The subscriber set lives on the shared base so the process/open passes
    // operate on it in-context (plain SLOADs), with the per-sub box stamp read
    // back from the same record at open. The systemwide afking ETH total is
    // already carried inside `claimablePool` via the `afkingFunding` ledger
    // (declared above); no separate aggregate is introduced.

    /// @notice Per-player AfKing subscription record: the per-buy box stamp plus the
    ///         in-slot per-sub accumulator.
    /// @dev Layout (Solidity packs sequentially) — fits in ONE 32-byte slot (224 bits used,
    ///      32 free at the top), so the whole record reads/writes as a single warm slot with no
    ///      extra cold slot:
    ///        config (16b):  dailyQuantity(8) + flags(8)
    ///        per-sub stamp (40b): score(16) + amount(24, milli-ETH)
    ///        markers (96b): lastAutoBoughtDay(24) + lastOpenedDay(24) + afkCoveredThroughDay(24) + afkingStartDay(24)
    ///        accumulator (72b): affiliateBase(32) + pendingFlip(24) + subStreakLatch(16)
    ///      There is NO per-day epoch: the box resolves at the LIVE level at open (no
    ///      stored roll floor) and sources its RNG word from
    ///      `rngWordByDay[lastAutoBoughtDay]`, so the only frozen-at-stamp inputs are the
    ///      two genuinely-per-sub fields — `score` (activity score) and `amount`
    ///      (mp×qty spend). `fundingSource` lives in the sparse `_fundingSourceOf` map
    ///      (absent ⇒ self, the common case stores nothing). `lastAutoBoughtDay`
    ///      double-duties as the success-marker AND the frozen seed `day`.
    ///      `amount` is stored in milli-ETH so it packs into uint32; the open unpacks it
    ///      back to wei before the box seed / EV-cap payout math. The stamp freezes the
    ///      box's SPEND and the seed `day`; the LEVEL and the EV-cap key read LIVE at
    ///      open, so the player cannot time the level. The milli-ETH round-down only
    ///      touches this recorded EV/seed input — the actual ETH/`claimablePool` debit
    ///      consumes the full wei `ethValue` and is never rounded.
    ///
    ///      Compute-on-read streak: `afkingStartDay` + `subStreakLatch`'s `streakAtAfkingStart`
    ///      (full uint16) frame the run; the effective afking quest streak is derived on read from
    ///      `afkCoveredThroughDay` (no DegenerusQuests STATICCALL on the buy path) and handed
    ///      back to the manual quest system on any sub-ending path (finalize).
    ///
    ///      In-slot accumulator (cheap per-buy; advanced by the per-buy accrue write into this
    ///      already-warm slot, so no new cold slot):
    ///        • `affiliateBase` — per-sub running unclaimed AFFILIATE balance, whole
    ///          FLIP; drained and paid out by `DegenerusAffiliate.claim`, zeroed there
    ///          so a re-claim finds 0.
    ///        • `pendingFlip` — per-sub running CLAIMABLE FLIP balance, whole FLIP,
    ///          accrued per delivered day (the slot-0 quest reward every mode + the
    ///          ticket-mode 10%/20% buyer bonus). Paid out only by the player-pull
    ///          `claimAfkingFlip`, zeroed there.
    ///        • `subStreakLatch` — the full uint16 afking-run streak base (snapshot + in-run secondaries).
    ///      `affiliateBase` is uint32 with a 100M-whole-FLIP saturating clamp and
    ///      `pendingFlip` is uint24 with a ~16.7M (2^24-1) saturating clamp at the accrue
    ///      write — each clamp binds before its field's type ceiling, and it can only ever
    ///      UNDER-credit a pathological high-volume whale (off the solvency path). The accumulator fields are written on
    ///      the buy-accrue path and the open markers (`lastOpenedDay`/`lastAutoBoughtDay`)
    ///      on the open path — disjoint fields in one warm slot, no collision.
    ///      There are no settle-day markers: the running balances self-mark, the pull has
    ///      no window, and the quest flush drains the counters so a double-fire finds 0.
    ///      `afkCoveredThroughDay` is a delivered-day high-water mark, not a settle
    ///      marker.
    struct Sub {
        // --- config (16 bits) ---
        /// @dev 0 = paused / never-subscribed; minimum 1 when active.
        uint8 dailyQuantity;
        /// @dev bit 0 free; bit 1 = drainGameCreditFirst; bit 2 = useTickets.
        uint8 flags;
        // --- per-sub stamp (40 bits) ---
        /// @dev Stamp: the frozen activity score (the EV multiplier input at open).
        ///      Genuinely per-sub (each subscriber's own activity score).
        uint16 score;
        /// @dev Stamp: spend in milli-ETH (0.001-ETH units; boons off, so amount ==
        ///      spend, = mp × effectiveQty). Milli-ETH in a uint24 (16,777 ETH/buy of
        ///      headroom — a single auto-buy never approaches it); packed via
        ///      `_packEthToMilliEth` at the stamp write and unpacked via
        ///      `_unpackMilliEthToWei` before the box seed / EV-cap payout math. The
        ///      round-down is on this recorded EV/seed input only — the actual ETH debit
        ///      still uses the full wei `ethValue`.
        uint24 amount;
        // --- markers (96 bits) ---
        /// @dev Success-marker AND the frozen seed `day` (the same process day):
        ///      day index of the last successful buy, written only after a successful
        ///      afkingFunding debit. The open sources the box word from
        ///      `rngWordByDay[lastAutoBoughtDay]` and freezes this `day` in the seed.
        ///      uint24 day index ~ 45,000 years of headroom.
        uint24 lastAutoBoughtDay;
        /// @dev Day-keyed no-double-open marker: the open leg materializes a box only
        ///      while `lastOpenedDay < lastAutoBoughtDay`; after the open it sets
        ///      `lastOpenedDay = lastAutoBoughtDay`, making the predicate false until
        ///      the next successful buy advances `lastAutoBoughtDay`. The no-orphan
        ///      guard (process stage) keys on the same two day fields.
        ///      uint24 day index, same width as lastAutoBoughtDay.
        uint24 lastOpenedDay;
        /// @dev Delivered-day high-water mark: monotone, advanced only on a day whose
        ///      ETH debit actually fired (a skipped/un-debited day does not advance it).
        ///      The afking quest streak is computed ON READ from this marker (no
        ///      DegenerusQuests STATICCALL on the buy path): the effective streak is
        ///      `streakAtAfkingStart + (afkCoveredThroughDay - afkingStartDay)` while the
        ///      last funded day is no older than yesterday, else 0 (decay-on-read). Advanced
        ///      in the same warm slot accrue write. uint24 day index.
        uint24 afkCoveredThroughDay;
        /// @dev Day the current afking run's streak snapshot was taken — the base day for the
        ///      compute-on-read `afkCoveredThroughDay - afkingStartDay` span. Set at subscribe
        ///      (the funded day-0) and re-based on a gap-resumed delivered day; cleared at
        ///      finalize when streak control hands back to the manual quest system. uint24 day
        ///      index, same width as the other day markers.
        uint24 afkingStartDay;
        // --- in-slot accumulator (72 bits) ---
        /// @dev Per-sub running unclaimed affiliate balance, whole FLIP. Accrued a flat
        ///      7% per buy (one warm in-slot `+=`); drained and paid out by
        ///      `DegenerusAffiliate.claim`, zeroed there so a re-claim finds 0. uint32
        ///      with a 100,000,000-whole-FLIP saturating clamp at the accrue write
        ///      (uint32 holds ~4.29e9 > 100M, so the clamp binds first); the clamp can
        ///      only ever under-credit, off the solvency path.
        uint32 affiliateBase;
        /// @dev Per-sub running CLAIMABLE FLIP balance, whole FLIP. Accrued per
        ///      delivered day by the warm in-slot buy accrue: the slot-0 quest reward
        ///      (every mode) plus the ticket-mode 10%/20% buyer bonus. Paid out only by the
        ///      player-pull `claimAfkingFlip` (one creditFlip, zeroed there so a re-claim
        ///      finds 0); the sub claims whenever, so there is no settle/claim-timing edge.
        ///      uint24 with a ~16.7M (2^24-1) saturating clamp + under-credit-only
        ///      behaviour, same in kind as `affiliateBase`.
        uint24 pendingFlip;
        /// @dev `streakAtAfkingStart` — the afking-run streak base (0..65535): the snapshot at run
        ///      start plus the secondary/level completions the player makes during the run
        ///      (bumped via recordAfkingSecondary). The compute-on-read effective streak adds the
        ///      funded delivered days `(afkCoveredThroughDay - afkingStartDay)` to this base. Read
        ///      per buy as a mask op, so `affiliateBase`/`pendingFlip` stay unmasked for the hot
        ///      accrue.
        uint16 subStreakLatch;
    }

    /// @dev `subStreakLatch` is the full uint16 — `streakAtAfkingStart` (0..65535). It carries the
    ///      run's pre-run snapshot plus the secondary/level completions the player makes during
    ///      the run (bumped via recordAfkingSecondary); the funded delivered days add on top of
    ///      this base. Clamped at uint16 max, far past where the activity-score caps make it matter.
    uint16 internal constant SUB_STREAK_MASK = 0xffff;

    /// @dev Read the afking-run streak base (the full packed latch uint16).
    function _streakBaseOf(Sub storage sub) internal view returns (uint16) {
        return sub.subStreakLatch & SUB_STREAK_MASK;
    }

    /// @dev Write the afking-run streak base, clamped to uint16 max so the live +1 bump
    ///      saturates instead of wrapping the field at the ceiling.
    function _setStreakBase(Sub storage sub, uint256 value) internal {
        sub.subStreakLatch = value > type(uint16).max ? type(uint16).max : uint16(value);
    }

    /// @dev Compute-on-read effective afking quest streak from the Sub slot — no DegenerusQuests
    ///      STATICCALL. The run's streak base (`streakAtAfkingStart`: snapshot + in-run
    ///      secondaries) plus the funded delivered days since the run's base day. A playable full
    ///      day without a funded delivery decays to 0; calendar days inside a pending unadvanced
    ///      gap are excluded because no subscriber could receive the daily delivery.
    function _afkingStreak(Sub storage sub, uint24 currentDay) internal view returns (uint32) {
        uint24 covered = sub.afkCoveredThroughDay;
        if (currentDay == 0) return 0;
        if (uint32(covered) + 1 < uint32(currentDay)) {
            uint24 sealedDay = dailyIdx;
            if (
                uint32(currentDay) <= uint32(sealedDay) + 1 ||
                covered < sealedDay ||
                rngWordByDay[sealedDay + 1] != 0
            ) return 0;
        }
        return uint32(_streakBaseOf(sub)) + uint32(covered - sub.afkingStartDay);
    }

    /// @dev The live (non-lapsed) afking streak for `player` if they are mid-run; otherwise
    ///      (false, 0). A genuinely lapsed run, a sub with no active run, and a non-subscriber all return
    ///      (false, 0) so callers fall back to the manual streak — a lapsed-but-still-minting sub
    ///      is never zeroed. No DegenerusQuests STATICCALL on the live-run path.
    function _liveAfkingStreak(address player) internal view returns (bool live, uint32 streak) {
        // `afkingStartDay` is set at run start and cleared at finalize (every sub-ending path),
        // and a non-subscriber's Sub slot is zero — so a non-zero start day alone identifies a
        // live run, off the single Sub-slot SLOAD _afkingStreak needs anyway (no _subscriberIndex
        // read). A paused/lapsed run keeps a start day but _afkingStreak decays it to 0 below.
        Sub storage sub = _subOf[player];
        if (sub.afkingStartDay != 0) {
            uint32 a = _afkingStreak(sub, _simulatedDayIndex());
            if (a != 0) return (true, a);
        }
        return (false, 0);
    }

    /// @dev Single source of truth for a player's effective quest streak, so the activity score
    ///      is one unified value everywhere it is read. A live afking sub reads the Sub-side
    ///      compute-on-read (carrying the run's funded days + in-run secondaries); everyone else
    ///      (and a lapsed run) reads the manual decay-aware streak.
    function _effectiveQuestStreak(address player) internal view returns (uint32) {
        // Most players are not afking subs, so learn the afking flag from the quest-streak read we
        // make anyway: a non-afker returns here with no Sub-slot lookup. Only an afking player pays
        // the extra Sub read for the compute-on-read (funded days + in-run secondaries); a lapsed
        // run falls back to the manual streak just read.
        (uint32 manualStreak, bool afking) = quests.effectiveBaseStreakAndAfking(player);
        if (!afking) return manualStreak;
        (bool live, uint32 a) = _liveAfkingStreak(player);
        return live ? a : manualStreak;
    }

    /// @dev Per-subscriber record (the iterable set's value): the per-sub stamp, the
    ///      day markers (incl. `afkingStartDay` / `afkCoveredThroughDay` for the compute-on-read
    ///      streak), and the in-slot accumulator (affiliateBase / pendingFlip / subStreakLatch).
    mapping(address => Sub) internal _subOf;

    /// @dev Sparse funder map — the wallet whose `afkingFunding` funds a sub.
    ///      Absent / address(0) ⇒ self-funded (the common case, which stores NOTHING).
    ///      Written at subscribe (set-if-nonzero / delete-if-self) and read once per
    ///      process iteration to resolve `src` (not needed at open — funding is already
    ///      debited at process).
    mapping(address => address) internal _fundingSourceOf;

    /// @dev Insertion-ordered iterable subscriber set (swap-pop tombstone on cancel).
    address[] internal _subscribers;

    /// @dev 1-indexed membership ⟺ packed-index map (0 = not in set); the
    ///      swap-pop bookkeeping for `_subscribers`.
    mapping(address => uint256) internal _subscriberIndex;

    /// @dev The two uint16 cursors + the uint24 afking reset-day pack into ONE slot
    ///      (16 + 16 + 24 = 56 bits). The cursors index `_subscribers` (the active set
    ///      is capped at 2005 — GameAfkingModule.SUBSCRIBER_CAP, well within uint16) and
    ///      are drained in chunks across advanceGame / router calls.
    /// @dev Process-STAGE cursor: the pre-RNG stamp pass position.
    uint16 internal _subCursor;

    /// @dev Open-leg cursor: the post-RNG box-open pass position (the
    ///      OPEN_BATCH-style router-category cursor).
    uint16 internal _subOpenCursor;

    /// @dev The day the process STAGE was last reset for. When the advance first enters
    ///      a new `day` (`_afkingResetDay != day`), it resets `subsFullyProcessed` + the
    ///      `_subCursor` ONCE, before that day's STAGE drains — a forward-looking reset
    ///      (at the start of the new day, not trailing after the prior day completes),
    ///      firing exactly once per day regardless of which RNG path runs.
    uint24 internal _afkingResetDay;

    // =========================================================================
    // Human-Box Auto-Open Sweep State
    // =========================================================================

    /// @dev Entry position within boxPlayers[boxCursorIndex] for the box auto-open sweep.
    ///      Persists across calls when a budget runs out mid-index; reset to zero each
    ///      time the sweep fully drains an index and advances the frontier.
    uint48 internal boxCursor;

    /// @dev The sweep's open frontier: the lowest lootbox RNG index not yet fully swept.
    ///      Monotonic — advances one index at a time as each queue drains, and never
    ///      moves past an index whose VRF word has not landed (orphan-index guard).
    uint48 internal boxCursorIndex;

    /// @dev RNG index of the coin-presale-box close (the 50-ETH-crossing buy) — the highest index
    ///      any presale box can occupy. Set once when presaleOver latches. Packs into the cursor
    ///      slot (free read in the sweep, which already loads boxCursorIndex); the sweep flips
    ///      presaleDrained once boxCursorIndex advances past it. Zero while presale never closes.
    uint48 internal presaleCloseIndex;

    /// @dev Once-per-level latch for the sDGNRS lootbox top-up: the level whose first
    ///      sDGNRS afking buy already took the 5%-of-claimable bonus. The process STAGE applies
    ///      the bonus once at its start (before the per-sub loop) while `level > _sdgnrsBonusLevel`,
    ///      then stamps the level here — so it fires once per level and never on a later chunk/tx.
    ///      Packs into the cursor slot (loaded for `_subCursor` every STAGE), so its read/write is
    ///      warm; a uint24 holds the full level range (matches `level`).
    uint24 internal _sdgnrsBonusLevel;

    /// @dev Count of stamped-but-unopened afking boxes (at most one per subscriber — the
    ///      no-orphan rule blocks re-stamping, eviction, reclaim, and funding-kill while a
    ///      box is pending, so the daily STAGE box stamps are the ONLY increments — batched
    ///      one add per STAGE chunk, plus the once-per-level sDGNRS bonus box inline — and
    ///      the box open the ONLY decrement). The rewarded open crank early-outs on zero, making a
    ///      drained-ring "any work?" check O(1) instead of a full ring scan; the unrewarded
    ///      openBoxes valve never consults it, so a counter fault can only cost gas (a walk
    ///      that finds nothing), never box liveness. Packs into the cursor slot (warm for
    ///      both writers); uint16 covers the 1000-subscriber cap.
    uint16 internal _pendingBoxCount;

    /// @dev Afking opens already knee-credited in the CURRENT forced-split bounty batch.
    ///      The weighted walk can split one logical drain across chunks (a long skip run eats
    ///      budget), and each split chunk would otherwise re-satisfy the
    ///      OPEN_KNEE and re-pay a full bounty. The rewarded crank credits only
    ///      min(carry + opened, KNEE) - min(carry, KNEE) toward the knee, carries the batch
    ///      total while the walk is budget-exhausted with boxes still pending (always < 80,
    ///      fits uint16), and the batch closes — carry zeroed — when the pending counter
    ///      drains to zero (any open path) or a chunk reaches the full OPEN_BATCH of opens.
    ///      Aggregate bounty over the split chunks equals the unsplit call's. Packs into the
    ///      cursor slot (warm for every reader/writer).
    uint16 internal _openBountyCarry;

    /// @dev Players with an open box queued per lootbox RNG index, enqueued once at
    ///      first deposit (the lootboxEth amount == 0 signal). Keyed on the lootbox index,
    ///      which re-couples to the VRF-rotation orphan-index keyspace — the box auto-open
    ///      walk MUST gate each open on lootboxRngWordByIndex[index] != 0 so an index
    ///      orphaned mid-day by an emergency coordinator rotation is skipped until the
    ///      detect-preserve-re-issue path lands the re-issued word.
    mapping(uint48 => address[]) internal boxPlayers;

    // =========================================================================
    // Foil Pack (v71)
    // =========================================================================

    /// @dev One packed record per (cycle level, player) — the surviving foil buy
    ///      for the cycle. The outer key is the active ticket level (the cycle the
    ///      buy bets into), the inner key the player, so distinct cycles are
    ///      independent records: a re-buy at the next cycle writes a different
    ///      outer key and never clobbers the prior cycle's record.
    ///      The buy writes all three fields at once: resolveDay (>= 1), multBps
    ///      (>= 20000), and the activity score frozen at buy. Presence (slot != 0) IS
    ///      the one-per-cycle cap. No match signatures are stored — the four match
    ///      lines are re-derived on claim from rngWordByDay[resolveDay] + multBps (the
    ///      SAME derivation the drain filed into the jackpot buckets), so the stored
    ///      record is just the derivation inputs plus the cap/no-look-back day.
    ///      Packed uint256 layout (LSB→MSB):
    ///        [0-23]    resolveDay    — the day whose sealed daily word
    ///                                (rngWordByDay[resolveDay]) both the drain and the
    ///                                claim derive the four match lines from, and the
    ///                                no-look-back floor (`day >= resolveDay`). Always
    ///                                >= 1, so every use site is additive (no underflow).
    ///        [24-39]   multBps       — the frozen foilBoostBps output (20000..60000)
    ///        [40-55]   activityScore — the buyer's activity score frozen at buy (the
    ///                                same value foilBoostBps was computed from), reused
    ///                                as the claim spin's RTP input. Freezing it makes
    ///                                the payout fully determined at buy (no claim-timing
    ///                                lever, consistent with the frozen multBps) and
    ///                                drops the live activity read from every claim.
    ///        [56-255]  reserved 0
    mapping(uint24 => mapping(address => uint256)) internal foilRecord;

    /// @dev Sparse double-claim marker, keyed by
    ///      keccak256(abi.encode(player, level, day, drawKind, ticketIndex)).
    ///      Set BEFORE any payout effect (CEI); a realized winning tuple is
    ///      claimable at most once per draw.
    mapping(bytes32 => bool) internal foilMatchClaimed;

    /// @dev The two daily winning trait sets the jackpot sealed for a day, plus
    ///      the cycle level active that day. Written once per day at the daily
    ///      seal; the foil claim reads these (never re-derives), so the foil
    ///      winning numbers equal the jackpot's. Presence (slot != 0) gates a
    ///      claim; the level field is the implicit eligibility upper bound (a day
    ///      maps to one cycle).
    ///      Packed uint256 layout (LSB→MSB):
    ///        [0-31]   mainSet  — the day's main winning set (uint32)
    ///        [32-63]  bonusSet — the day's bonus winning set (uint32)
    ///        [64-87]  level    — the active ticket level of that day (uint24)
    ///        [88-255] reserved 0
    mapping(uint24 => uint256) internal dailyFoilDraw;

    /// @dev Per-buy-day foil queue, keyed by resolveDay (= buyDay + 1), the
    ///      coinflip-by-day / degenerette-bucket analog. A foil buy pushes a packed
    ///      (cycle level << 160 | buyer) entry into the bucket for its resolveDay;
    ///      the drain processes a bucket only once rngWordByDay[resolveDay] is sealed,
    ///      so every entry's match lines derive from a word that was provably future
    ///      at buy. The packed level is the cycle the pack bet into (the foilRecord
    ///      and jackpot key), carried in the entry because the bucket is day-keyed and
    ///      one wall day can straddle a cycle transition.
    mapping(uint24 => uint256[]) internal foilBuyers;

    /// @dev Resumable foil drain cursors. foilDrainDay is the next resolveDay bucket
    ///      to drain (the low-water mark); foilCursor is the within-bucket index for a
    ///      budget-short deferral. The drain walks foilDrainDay forward over sealed
    ///      buckets up to foilLastResolveDay (the high-water mark = the latest
    ///      resolveDay any pack was bought into). foilLastResolveDay == 0 means no
    ///      foil was ever bought, so the readiness gate and drain short-circuit with a
    ///      single SLOAD and the common advance carries no foil cost.
    uint32 internal foilCursor;
    uint24 internal foilDrainDay;
    uint24 internal foilLastResolveDay;

    /// @dev Lifetime count of deity boons issued from a given deity to a given
    ///      recipient, keyed [deity][recipient]. Capped at DEITY_RECIPIENT_BOON_CAP
    ///      in issueDeityBoon.
    mapping(address => mapping(address => uint8)) internal deityRecipientBoonCount;

    /// @dev 75/25 next/future split for the foil leg (forked from the 90/10
    ///      ticket split's PURCHASE_TO_FUTURE_BPS = 1000).
    uint16 internal constant FOIL_TO_FUTURE_BPS = 2500;

    /// @dev A foil pack resolves a fixed 16 boosted entries (4 tickets x 4
    ///      quadrants). The drain resolves this many per queued buyer.
    uint32 internal constant FOIL_PACK_ENTRIES = 16;

    /// @dev The foil SKU is priced at ten ticket prices and records ten mint units
    ///      (price-equivalent activity, not the four packed tickets). Shared by the
    ///      mint-path cost computation and the foil delivery module.
    uint256 internal constant FOIL_PACK_TICKETS = 10;

    uint256 private constant _FOIL_RESOLVEDAY_MASK = (uint256(1) << 24) - 1;
    uint256 internal constant _FOIL_MULT_SHIFT = 24;
    uint256 private constant _FOIL_MULT_MASK = (uint256(1) << 16) - 1;
    uint256 internal constant _FOIL_SCORE_SHIFT = 40;
    uint256 private constant _FOIL_SCORE_MASK = (uint256(1) << 16) - 1;

    uint256 private constant _FOIL_DRAW_MAIN_MASK = (uint256(1) << 32) - 1;
    uint256 private constant _FOIL_DRAW_BONUS_SHIFT = 32;
    uint256 private constant _FOIL_DRAW_LEVEL_SHIFT = 64;
    uint256 private constant _FOIL_DRAW_LEVEL_MASK = (uint256(1) << 24) - 1;

    /// @dev Domain-separated seed for the drain-side match-line roll, so the foil
    ///      tuples derive from a keccak lane disjoint from the normal-ticket LCG
    ///      seeds and the daily winning-set derivation.
    bytes32 internal constant FOIL_SEED_TAG = keccak256("foil-seed");

    /// @dev Claim-side entropy lanes off the retained daily word — distinct keccak
    ///      domains from each other and from BONUS_TRAITS_TAG. FOIL_CCY_TAG rolls the
    ///      40/40/20 currency split; FOIL_SPIN_TAG seeds the Degenerette box-spin the
    ///      tier magnitude is staked into.
    bytes32 internal constant FOIL_CCY_TAG = keccak256("foil-currency");
    bytes32 internal constant FOIL_SPIN_TAG = keccak256("foil-spin");

    /// @dev A player's foil record for a cycle level (one SLOAD): the frozen boost
    ///      and the resolveDay both the drain and the claim derive the match lines
    ///      from. present = (slot != 0); resolveDay >= 1 on any bought pack, so the
    ///      claim feeds it directly as the no-look-back floor (`day >= resolveDay`)
    ///      and the derivation key (rngWordByDay[resolveDay]).
    function _foilRecordFor(address player, uint256 lvl)
        internal
        view
        returns (bool present, uint16 multBps, uint24 resolveDay, uint16 activityScore)
    {
        uint256 packed = foilRecord[uint24(lvl)][player];
        present = packed != 0;
        resolveDay = uint24(packed & _FOIL_RESOLVEDAY_MASK);
        multBps = uint16((packed >> _FOIL_MULT_SHIFT) & _FOIL_MULT_MASK);
        activityScore = uint16((packed >> _FOIL_SCORE_SHIFT) & _FOIL_SCORE_MASK);
    }

    /// @dev The frozen activity multiplier from a player's foil record for a cycle
    ///      level (one SLOAD); 0 when the player holds no pack for the cycle. The
    ///      queue drain reads only this field to boost the resolved entries.
    function _foilMultFor(address player, uint256 lvl) internal view returns (uint16) {
        return uint16(
            (foilRecord[uint24(lvl)][player] >> _FOIL_MULT_SHIFT) & _FOIL_MULT_MASK
        );
    }

    /// @dev True iff a sealed, un-drained foil bucket is waiting. The jackpot
    ///      readiness gate blocks on this so a day's boosted foil entries are filed
    ///      into the trait buckets before that day's jackpot samples winners. Cheap by
    ///      construction: no foil ever bought (foilLastResolveDay == 0) short-circuits
    ///      on one SLOAD; otherwise it is pending only while the low-water bucket is
    ///      at/below the high-water mark AND its daily word has sealed (a future-dated
    ///      bucket whose word is not yet sealed does not gate the current jackpot).
    ///      Under the terminal fallback regime an unsealed bucket is pending too: its day
    ///      will never be worded, and the drain settles it against the committed fallback
    ///      word instead of leaving those packs out of the terminal cohort. The latch read
    ///      sits behind the sealed-word test, so live play only reaches it for a
    ///      future-dated bucket, where the answer is false either way.
    function _foilDrainPending() internal view returns (bool) {
        uint24 last = foilLastResolveDay;
        if (last == 0) return false;
        uint24 dd = foilDrainDay;
        if (dd > last) return false;
        return
            rngWordByDay[dd] != 0 ||
            (_lrRead(LR_GO_FALLBACK_SHIFT, LR_GO_FALLBACK_MASK) != 0 &&
                rngWordCurrent != 0);
    }

    /// @dev The per-cycle one-pack cap: true iff the player already bought a foil
    ///      pack for this cycle. Keyed on the active ticket level — the same cycle
    ///      key the buy's record write and ticket queue use.
    function _foilBoughtThisLevel(address player, uint256 lvl) internal view returns (bool) {
        return foilRecord[uint24(lvl)][player] != 0;
    }

    /// @dev Pack a daily foil draw record (the two sealed winning sets + the cycle
    ///      level) for storage in dailyFoilDraw.
    function _packFoilDraw(uint32 mainSet, uint32 bonusSet, uint24 lvl)
        internal
        pure
        returns (uint256)
    {
        return uint256(mainSet)
            | (uint256(bonusSet) << _FOIL_DRAW_BONUS_SHIFT)
            | (uint256(lvl) << _FOIL_DRAW_LEVEL_SHIFT);
    }

    /// @dev Unpack the daily foil draw for a day (one SLOAD). present = (slot !=
    ///      0); a sealed day always has a nonzero level.
    function _foilDrawFor(uint256 day)
        internal
        view
        returns (bool present, uint32 mainSet, uint32 bonusSet, uint24 lvl)
    {
        uint256 packed = dailyFoilDraw[uint24(day)];
        present = packed != 0;
        mainSet = uint32(packed & _FOIL_DRAW_MAIN_MASK);
        bonusSet = uint32((packed >> _FOIL_DRAW_BONUS_SHIFT) & _FOIL_DRAW_MAIN_MASK);
        lvl = uint24((packed >> _FOIL_DRAW_LEVEL_SHIFT) & _FOIL_DRAW_LEVEL_MASK);
    }

    /// @dev Golden-ticket cross-day state, one packed slot (appended so every
    ///      prior slot keeps its index). Armed on a 4-gold main board (jackpot
    ///      phase); resolved by the next main-board draw. Written and read only
    ///      inside VRF fulfillment — players can never touch it.
    ///      Layout (LSB up):
    ///      [159:0]   armed winner (solo bucket winner of the arm day)
    ///      [161:160] armed solo quadrant
    ///      [164:162] armed solo symbol (official, post-hero)
    ///      [188:165] armedIdx — frozen dailyIdx during the arm draw
    ///      [189]     armed flag
    ///      [190]     resolve-day ban flag (keeps the hero ban stable for the
    ///                resolve day's later re-rolls after the armed fields are
    ///                cleared or overwritten by a same-day chain arm)
    ///      [192:191] resolve-day ban quadrant
    ///      [216:193] resolve-day ban idx — frozen dailyIdx of the resolve draw
    uint256 internal goldenTicket;

    /// @dev Unspent mid-day RNG credit per donor, in juels of donated LINK (appended so
    ///      every prior slot keeps its index). Held in LINK because LINK is what the
    ///      subscription is billed in, so a balance means exactly what it says: the LINK
    ///      this donor put in and has not yet spent against.
    ///      A redemption debits MIDDAY_RNG_CHARGE_MULT times what the request itself
    ///      bills, priced at redemption rather than banked at a fixed rate — so the
    ///      balance buys fewer requests when gas is expensive and more when it is cheap.
    mapping(address => uint256) internal middayRngCredit;

    /// @dev Achieved prize pool of every completed century level (x00) — the pre-skim
    ///      nextPrizePool recorded at each x00 purchase→jackpot transition — in completion
    ///      order, so century N sits at index N-1 (appended so every prior slot keeps its
    ///      index). levelPrizePool[x00] cannot serve as this history: _endPhase overwrites
    ///      it with futurePool/3 as the reachable x01 ratchet base, so the achieved value
    ///      survives only here.
    ///
    ///      Two readers, both needing the value past that overwrite. _prizePoolTarget
    ///      takes the newest entry as the century floor, so each century jackpot must
    ///      outgrow the last. _growthRatchet takes the entry for a specific century, so
    ///      the growth market prices a boundary round against real growth — and, because
    ///      an entry is written once and never revisited, a settled round's answer can
    ///      never change.
    uint128[] internal centuryPrizePools;

    /// @dev The ratchet entry for `lvl` as the growth market must see it: a century level
    ///      reads its pushed achieved pool rather than the overwritten levelPrizePool
    ///      entry, so growth across a century boundary measures the game and not the
    ///      reset artifact.
    ///
    ///      Returns 0 for a century that has not completed. That is the point: the market
    ///      treats a zero successor entry as "not settled yet", and a bare index would
    ///      revert out of bounds instead, bricking the read. Level 0 is excluded from the
    ///      century branch so the genesis round keeps reading BOOTSTRAP_PRIZE_POOL.
    function _growthRatchet(uint24 lvl) internal view returns (uint256) {
        if (lvl != 0 && lvl % 100 == 0) {
            uint256 idx = lvl / 100 - 1;
            return
                idx < centuryPrizePools.length
                    ? uint256(centuryPrizePools[idx])
                    : 0;
        }
        return levelPrizePool[lvl];
    }
}
