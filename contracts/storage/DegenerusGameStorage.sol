// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {ContractAddresses} from "../ContractAddresses.sol";
import {IVRFCoordinator} from "../interfaces/IVRFCoordinator.sol";
import {IStakedDegenerusStonk} from "../interfaces/IStakedDegenerusStonk.sol";
import {IDegenerusAffiliate} from "../interfaces/IDegenerusAffiliate.sol";
import {IDegenerusCoin} from "../interfaces/IDegenerusCoin.sol";
import {IBurnieCoinflip} from "../interfaces/IBurnieCoinflip.sol";
import {IDegenerusQuests} from "../interfaces/IDegenerusQuests.sol";
import {BitPackingLib} from "../libraries/BitPackingLib.sol";
import {GameTimeLib} from "../libraries/GameTimeLib.sol";

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
 * +-----------------------------------------------------------------------------+
 * | EVM SLOT 0 (32 bytes) -- Timing, FSM, Counters, Flags, Buffer, Freeze       |
 * +-----------------------------------------------------------------------------+
 * | [0:3]   purchaseStartDay         uint24   Day index when purchase/deploy began|
 * | [3:6]   dailyIdx                 uint24   Monotonic day counter             |
 * | [6:12]  rngRequestTime           uint48   When last VRF request was fired   |
 * | [12:15] level                    uint24   Current jackpot level (starts at 0)|
 * | [15:16] jackpotPhaseFlag         bool     Phase: false=PURCHASE, true=JACKPOT|
 * | [16:17] jackpotCounter           uint8    Jackpots processed this level      |
 * | [17:18] lastPurchaseDay          bool     Prize target met flag              |
 * | [18:19] decWindowOpen            bool     Decimator window latch             |
 * | [19:20] rngLockedFlag            bool     Daily RNG lock (jackpot window)    |
 * | [20:21] phaseTransitionActive    bool     Level transition in progress       |
 * | [21:22] gameOver                 bool     Terminal state flag                |
 * | [22:23] dailyJackpotCoinTicketsPending bool Split jackpot pending flag       |
 * | [23:24] compressedJackpotFlag    uint8    0=normal, 1=compressed, 2=turbo    |
 * | [24:25] ticketsFullyProcessed    bool     Read slot fully drained flag       |
 * | [25:26] gameOverPossible         bool     Drip projection endgame flag       |
 * | [26:27] ticketWriteSlot          bool     Double-buffer write toggle         |
 * | [27:28] prizePoolFrozen          bool     Prize pool freeze active flag      |
 * | [28:29] presaleOver              bool     Coin-presale-box terminal latch    |
 * | [29:30] subsFullyProcessed       bool     Afking STAGE drain-complete flag    |
 * | [30:31] presaleDrained           bool     All presale boxes opened (sweep)    |
 * +-----------------------------------------------------------------------------+
 *   Total: 31 bytes used (1 byte padding)
 *
 * +-----------------------------------------------------------------------------+
 * | EVM SLOT 1 (32 bytes) -- Prize Pools                                        |
 * +-----------------------------------------------------------------------------+
 * | [0:16]  currentPrizePool         uint128  Active prize pool for current level|
 * | [16:32] claimablePool            uint128  Aggregate ETH liability for claims |
 * +-----------------------------------------------------------------------------+
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
 * 3. ACCESS CONTROL: All variables are `internal`, preventing external reads.
 *    Public getters in DegenerusGame expose only what's needed.
 *
 * 4. INITIALIZATION: Default values are set inline. For critical variables:
 *    - purchaseStartDay = deploy day index (set in constructor via GameTimeLib.currentDayIndex())
 *    - jackpotPhaseFlag = false (purchase phase)
 *    - decWindowOpen = false (opens at level 4 jackpot phase start)
 *    - levelPrizePool uses BOOTSTRAP_PRIZE_POOL (50 ether) as fallback for level 0
 *
 * 5. OVERFLOW PROTECTION: Solidity 0.8+ provides automatic overflow checks.
 *    `unchecked` blocks in modules are intentional optimizations for safe ops.
 *
 * 6. MAPPING COLLISION: Mappings use keccak256(key . slot), making collisions
 *    computationally infeasible. The traitBurnTicket nested mapping uses
 *    keccak256(traitId . keccak256(level . slot)) for data location.
 *
 * UPGRADE NOTES
 * -----------------------------------------------------------------------------
 * This contract is NOT upgradeable (no proxy pattern). However, if future
 * versions are deployed, they MUST preserve this exact layout to allow
 * state migration or fork compatibility. Document any additions here.
 *
 * VARIABLE DOCUMENTATION
 * -----------------------------------------------------------------------------
 * See inline comments for each variable group below.
 */

interface IDegenerusQuestView {
    function playerQuestStates(
        address player
    )
        external
        view
        returns (
            uint32 streak,
            uint24 lastCompletedDay,
            uint128[2] memory progress,
            bool[2] memory completed
        );
}
abstract contract DegenerusGameStorage {
    // =========================================================================
    // CONSTANTS
    // =========================================================================

    IDegenerusCoin internal constant coin =
        IDegenerusCoin(ContractAddresses.COIN);
    IBurnieCoinflip internal constant coinflip =
        IBurnieCoinflip(ContractAddresses.COINFLIP);
    IDegenerusQuests internal constant quests =
        IDegenerusQuests(ContractAddresses.QUESTS);
    IDegenerusQuestView internal constant questView =
        IDegenerusQuestView(ContractAddresses.QUESTS);
    IDegenerusAffiliate internal constant affiliate =
        IDegenerusAffiliate(ContractAddresses.AFFILIATE);
    IStakedDegenerusStonk internal constant dgnrs =
        IStakedDegenerusStonk(ContractAddresses.SDGNRS);

    /// @dev Deity pass activity bonus (+80% in basis points).
    uint16 internal constant DEITY_PASS_ACTIVITY_BONUS_BPS = 8000;

    /// @dev Floor streak points for active pass holders (50 = 50%).
    uint16 internal constant PASS_STREAK_FLOOR_POINTS = 50;

    /// @dev Floor mint count points for active pass holders (25 = 25%).
    uint16 internal constant PASS_MINT_COUNT_FLOOR_POINTS = 25;

    /// @dev Conversion factor for BURNIE token amounts.
    ///      BURNIE uses 18 decimals, so 1000 BURNIE = 1e21 base units.
    ///      Used in price calculations: price / PRICE_COIN_UNIT = BURNIE per mint.
    uint256 internal constant PRICE_COIN_UNIT = 1000 ether;

    /// @dev Scale factor for fractional ticket calculations (2 decimal places).
    ///      100 means 1 ticket = 100 scaled units.
    uint256 internal constant TICKET_SCALE = 100;

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

    // =========================================================================
    // Errors
    // =========================================================================

    /// @dev Gas-minimal revert signal. Matches codebase convention (DegenerusGame, modules).
    error E();

    /// @dev Reverts when a permissionless far-future ticket write is attempted during VRF commitment window.
    error RngLocked();

    // =========================================================================
    // SLOT 0: Timing, FSM, Counters, Flags, Buffer, Freeze
    // =========================================================================
    // These variables pack into a single 32-byte storage slot for gas efficiency.
    // Order matters: EVM packs from low to high within a slot.
    // 31/32 bytes used (1 byte padding).

    /// @dev Game day index when the purchase phase (or deploy) began.
    ///      Initialized to GameTimeLib.currentDayIndex() in the constructor.
    ///      Used for death clock, distress mode, future take curve, and gap extension.
    ///
    ///      SECURITY: uint24 holds day indices up to ~16.7 million — effectively unlimited
    ///      for day-granularity counters.
    uint24 internal purchaseStartDay;

    /// @dev Monotonically increasing "day" counter derived from block timestamps.
    ///      Incremented during game progression; used to key RNG words and track
    ///      daily jackpot eligibility. NOT tied to calendar days — it's game-relative.
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
    ///      stay under 15M gas block limit. Cleared after coin+ticket distribution.
    bool internal dailyJackpotCoinTicketsPending;

    /// @dev Jackpot compression tier: 0=normal (5d), 1=compressed (3d), 2=turbo (1d).
    ///      Set when purchase-phase target is met quickly, signaling high player interest.
    ///      Turbo (2): target met within 1 day — entire jackpot in 1 physical day.
    ///      Compressed (1): target met within 3 days — 5 logical days in 3 physical.
    ///      Cleared at phase end.
    uint8 internal compressedJackpotFlag;

    /// @dev True when the read slot has been fully drained (all tickets processed).
    ///      Gate for RNG requests and jackpot logic in advanceGame daily path.
    ///
    ///      SECURITY: Must be set to true before any jackpot/phase logic executes.
    ///      Reset to false on every queue slot swap.
    bool internal ticketsFullyProcessed;

    /// @dev True when drip projection shows futurePool cannot cover nextPool deficit.
    ///      Evaluated in advanceGame at L10+ purchase-phase days.
    ///      When active: BURNIE ticket purchases revert, BURNIE lootbox current-level
    ///      tickets redirect to far-future key space.
    ///      Cleared when: drip re-covers deficit, lastPurchaseDay is set, or phase transition.
    bool internal gameOverPossible;

    // EVM SLOT 0 (continued): Double-Buffer + Freeze (moved from slot 1)

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
    ///      credit accrual occur. Occupies slot-0 padding byte [30:31].
    bool internal presaleOver;

    /// @dev Afking process-STAGE drain-completion flag — the subscriber-drain sibling
    ///      of `ticketsFullyProcessed`. False while the STAGE is stamping the funded
    ///      subscriber set this day; set true once the set is fully drained; flipped back
    ///      to false forward-looking at the start of the next day (the advance's
    ///      `_afkingResetDay != day` gate), so it always reflects "afking done for the
    ///      current day". Packed into slot-0 byte [31:32] alongside `level` /
    ///      `rngLockedFlag` / `ticketsFullyProcessed`, which the advance-path STAGE
    ///      already SLOADs, so its read/write is free.
    bool internal subsFullyProcessed;

    /// @dev One-way "all coin-presale boxes have been opened" flag. False until the auto-open sweep
    ///      has advanced its cursor PAST presaleCloseIndex — i.e. every box at indices <= the close
    ///      index is opened, so none can remain. Lives in slot-0 padding byte [30:31], which every
    ///      open path already SLOADs (`level` / `rngLockedFlag`), so the gate `!presaleDrained` is a
    ///      free read: once set, the post-presale sweep AND manual opens skip the cold presaleBoxEth
    ///      SLOAD. Flipped only by the in-order sweep (never the manual path), so an out-of-order
    ///      manual open of the closing box cannot trip it early and strand a still-queued box.
    bool internal presaleDrained;

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
    ///      INVARIANT: claimablePool == Σ (claimable + afking halves of balancesPacked[*])
    ///      Maintained by crediting/debiting every component in tandem.
    ///      NOTE: During decimator settlement, the full pool is reserved in claimablePool
    ///      before individual claims are credited, temporarily breaking equality.
    ///
    ///      uint128 max ~3.4e20 ETH — far exceeds total ETH supply.
    ///      Packed into slot 1 alongside currentPrizePool.
    uint128 internal claimablePool;

    // =========================================================================
    // SLOT 2+: Full-Width Balances and Pools
    // =========================================================================
    // Each uint256 occupies its own 32-byte slot. These track ETH/token flows.

    /// @dev Packed live prize pools: [128:256] futurePrizePool | [0:128] nextPrizePool
    ///      uint128 max ~= 3.4e20 ETH -- far exceeds total ETH supply.
    ///      Saves 1 SSTORE on every purchase (both written together).
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
    ///      Tracks flip activity for jackpot sizing adjustments.
    uint256 internal totalFlipReversals;

    /// @dev Packed daily jackpot ticket data for two-phase execution.
    ///      Layout: [counterStep (8 bits @ 0)] [dailyTicketUnits (64 bits @ 8)]
    ///              [carryoverTicketUnits (64 bits @ 72)] [carryoverSourceOffset (8 bits @ 136)]
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
    ///      STRUCTURE: traitBurnTicket[level][traitId] = address[]
    ///      Each burn adds the burner's address, allowing duplicate entries
    ///      (more burns = more tickets = higher win probability).
    ///
    ///      STORAGE: Slot for mapping root, then:
    ///        - keccak256(level . slot) gives the 256-element array of arrays
    ///        - Each inner array has length at its slot, data at keccak256(slot)
    ///
    ///      SECURITY: Array growth bounded by total ticket supply per level.
    mapping(uint24 => address[][256]) internal traitBurnTicket;

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
    ///      [128:256] futurePrizePoolPending (uint128) | [0:128] nextPrizePoolPending (uint128)
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
    ///      This allows lootbox tickets to participate in early-bird jackpots at jackpot phase start.
    mapping(uint24 => address[]) internal ticketQueue;

    /// @dev Packed owed tickets per level per player.
    ///      Layout: [32 bits owed][8 bits remainder].
    mapping(uint24 => mapping(address => uint40)) internal ticketsOwedPacked;

    /// @dev Cursor for ticket queue processing (dual-purpose).
    ///      - SETUP phase: tracks near-future level progress (1-4), reset to 0 when done.
    ///      - PURCHASE phase: tracks mint batch progress through ticketQueue.
    ///      - JACKPOT phase: tracks jackpot batch progress through ticketQueue.
    ///      Phases are mutually exclusive, so cursor is reused safely.
    uint32 internal ticketCursor;

    /// @dev Current level being processed in ticket queue operations.
    uint24 internal ticketLevel;

    // =========================================================================
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

    /// @notice Emitted when whole tickets are queued for a buyer at a specific level.
    event TicketsQueued(
        address indexed buyer,
        uint24 targetLevel,
        uint32 quantity
    );

    /// @notice Emitted when scaled (fractional) tickets are queued for a buyer.
    event TicketsQueuedScaled(
        address indexed buyer,
        uint24 targetLevel,
        uint32 quantityScaled
    );

    /// @notice Emitted when tickets are queued across a contiguous range of levels.
    event TicketsQueuedRange(
        address indexed buyer,
        uint24 startLevel,
        uint24 numLevels,
        uint32 ticketsPerLevel
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

    /// @notice Emitted when final sweep forfeits unclaimed winnings 30 days post-gameover.
    event FinalSwept(uint256 totalFunds);

    /// @dev Emitted when ETH is credited to a player's claimable balance.
    event PlayerCredited(address indexed player, address indexed recipient, uint256 amount);

    /// @dev Emitted whenever prepaid afking ETH is spent to fund a buy (the afking-as-payment
    ///      waterfall's third tier) — full observability of where afking principal goes.
    event AfkingSpent(address indexed player, uint256 amount);

    /// @notice Emitted when a boon is consumed by a player.
    event BoonConsumed(address indexed player, uint8 boonType, uint16 boostBps);

    /// @notice Emitted when admin swaps game ETH for stETH.
    event AdminSwapEthForStEth(address indexed recipient, uint256 amount);

    /// @notice Emitted when admin stakes game ETH into Lido stETH.
    event AdminStakeEthForStEth(uint256 amount);

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

    /// @dev Queues whole tickets for a buyer at a target level.
    ///      If buyer has no existing tickets at that level, adds them to the queue.
    ///      Caps at uint32 max to prevent overflow.
    /// @param buyer Address to receive tickets.
    /// @param targetLevel Level for which tickets are queued.
    /// @param quantity Number of tickets to queue.
    function _queueTickets(
        address buyer,
        uint24 targetLevel,
        uint32 quantity,
        bool rngBypass
    ) internal {
        if (quantity == 0) return;
        emit TicketsQueued(buyer, targetLevel, quantity);
        // Block new tickets once the liveness-timeout game-over trigger is
        // active -- terminal jackpot must not be manipulable by adding tickets
        // after the VRF word that resolves it becomes known.
        if (_livenessTriggered()) revert E();
        bool isFarFuture = targetLevel > level + 5;
        if (isFarFuture && rngLockedFlag && !rngBypass) revert RngLocked();
        uint24 wk = isFarFuture
            ? _tqFarFutureKey(targetLevel)
            : _tqWriteKey(targetLevel);
        uint40 packed = ticketsOwedPacked[wk][buyer];
        uint32 owed = uint32(packed >> 8);
        uint8 rem = uint8(packed);
        if (owed == 0 && rem == 0) {
            ticketQueue[wk].push(buyer);
        }
        unchecked {
            owed += quantity;
        }
        ticketsOwedPacked[wk][buyer] = (uint40(owed) << 8) | uint40(rem);
    }

    /// @dev Queues scaled tickets (with 2 decimal places) for fractional ticket purchases.
    ///      Handles remainder accumulation and promotes to whole tickets when remainder >= TICKET_SCALE.
    /// @param buyer Address to receive tickets.
    /// @param targetLevel Level for which tickets are queued.
    /// @param quantityScaled Scaled ticket amount (multiply by 100 for whole tickets).
    function _queueTicketsScaled(
        address buyer,
        uint24 targetLevel,
        uint32 quantityScaled,
        bool rngBypass
    ) internal {
        if (quantityScaled == 0) return;
        // Block new tickets once liveness-timeout is active (see _queueTickets).
        if (_livenessTriggered()) revert E();
        emit TicketsQueuedScaled(buyer, targetLevel, quantityScaled);
        bool isFarFuture = targetLevel > level + 5;
        if (isFarFuture && rngLockedFlag && !rngBypass) revert RngLocked();
        uint24 wk = isFarFuture
            ? _tqFarFutureKey(targetLevel)
            : _tqWriteKey(targetLevel);
        uint40 packed = ticketsOwedPacked[wk][buyer];
        uint32 owed = uint32(packed >> 8);
        uint8 rem = uint8(packed);
        if (owed == 0 && rem == 0) {
            ticketQueue[wk].push(buyer);
        }

        uint32 whole = uint32(uint256(quantityScaled) / TICKET_SCALE);
        uint8 frac = uint8(uint256(quantityScaled) % TICKET_SCALE);
        unchecked {
            owed += whole;
        }

        if (frac != 0) {
            uint16 newRem;
            unchecked {
                newRem = uint16(rem) + uint16(frac);
            }
            if (newRem >= TICKET_SCALE) {
                unchecked {
                    owed += 1;
                }
                newRem -= uint16(TICKET_SCALE);
            }
            rem = uint8(newRem);
        }
        uint40 newPacked = (uint40(owed) << 8) | uint40(rem);
        if (newPacked != packed) {
            ticketsOwedPacked[wk][buyer] = newPacked;
        }
    }

    /// @dev Queues tickets for a contiguous range of levels with same quantity per level.
    ///      Optimized for whale pass claims to minimize loop overhead.
    /// @param buyer Address to receive tickets.
    /// @param startLevel First level in range (inclusive).
    /// @param numLevels Number of consecutive levels.
    /// @param ticketsPerLevel Tickets to award per level.
    function _queueTicketRange(
        address buyer,
        uint24 startLevel,
        uint24 numLevels,
        uint32 ticketsPerLevel,
        bool rngBypass
    ) internal {
        // Block new tickets once liveness-timeout is active (see _queueTickets).
        if (_livenessTriggered()) revert E();
        emit TicketsQueuedRange(buyer, startLevel, numLevels, ticketsPerLevel);
        uint24 currentLevel = level; // cache outside loop to avoid repeated SLOAD
        uint24 lvl = startLevel;
        for (uint24 i = 0; i < numLevels; ) {
            bool isFarFuture = lvl > currentLevel + 5;
            if (isFarFuture && rngLockedFlag && !rngBypass) revert RngLocked();
            uint24 wk = isFarFuture ? _tqFarFutureKey(lvl) : _tqWriteKey(lvl);
            uint40 packed = ticketsOwedPacked[wk][buyer];
            uint32 owed = uint32(packed >> 8);
            uint8 rem = uint8(packed);
            if (owed == 0 && rem == 0) {
                ticketQueue[wk].push(buyer);
            }
            unchecked {
                owed += ticketsPerLevel;
            }
            ticketsOwedPacked[wk][buyer] = (uint40(owed) << 8) | uint40(rem);

            unchecked {
                ++lvl;
                ++i;
            }
        }
    }

    // =========================================================================
    // Packed Prize Pool Helpers
    // =========================================================================

    function _setPrizePools(uint128 next, uint128 future) internal {
        prizePoolsPacked = (uint256(future) << 128) | uint256(next);
    }

    function _getPrizePools()
        internal
        view
        returns (uint128 next, uint128 future)
    {
        uint256 packed = prizePoolsPacked;
        next = uint128(packed);
        future = uint128(packed >> 128);
    }

    function _setPendingPools(uint128 next, uint128 future) internal {
        prizePoolPendingPacked = (uint256(future) << 128) | uint256(next);
    }

    function _getPendingPools()
        internal
        view
        returns (uint128 next, uint128 future)
    {
        uint256 packed = prizePoolPendingPacked;
        next = uint128(packed);
        future = uint128(packed >> 128);
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

    // =========================================================================
    // Queue Swap and Prize Pool Freeze
    // =========================================================================

    /// @dev Swap the active ticket queue buffer. Reverts if read slot is not drained.
    ///      Resets ticketsFullyProcessed to false for the new read slot.
    function _swapTicketSlot(uint24 purchaseLevel) internal {
        uint24 rk = _tqReadKey(purchaseLevel);
        if (ticketQueue[rk].length != 0) revert E();
        ticketWriteSlot = !ticketWriteSlot;
        ticketsFullyProcessed = false;
    }

    /// @dev Swap queue buffer AND activate prize pool freeze (daily RNG path only).
    ///      If not already frozen, pre-seeds the pending future-pool buffer with
    ///      1% of futurePrizePool so Degenerette ETH wins can resolve during
    ///      freeze without waiting for bet inflow. Unconsumed remainder rolls
    ///      back to futurePool via _unfreezePool.
    ///      If already frozen (jackpot phase), accumulators keep growing.
    function _swapAndFreeze(uint24 purchaseLevel) internal {
        _swapTicketSlot(purchaseLevel);
        if (!prizePoolFrozen) {
            prizePoolFrozen = true;
            uint256 futureBal = _getFuturePrizePool();
            uint256 seed = futureBal / 100;
            if (seed != 0) {
                _setFuturePrizePool(futureBal - seed);
                _setPendingPools(0, uint128(seed));
            } else {
                prizePoolPendingPacked = 0;
            }
        }
    }

    /// @dev Apply pending accumulators to live pools and clear freeze.
    ///      No-op if not currently frozen.
    function _unfreezePool() internal {
        if (!prizePoolFrozen) return;
        (uint128 pNext, uint128 pFuture) = _getPendingPools();
        (uint128 next, uint128 future) = _getPrizePools();
        _setPrizePools(next + pNext, future + pFuture);
        prizePoolPendingPacked = 0;
        prizePoolFrozen = false;
    }

    // =========================================================================
    // Single-Component Prize Pool Accessors
    // =========================================================================

    /// @dev Returns the next pool component.
    function _getNextPrizePool() internal view returns (uint256) {
        (uint128 next, ) = _getPrizePools();
        return uint256(next);
    }

    /// @dev Sets only the next pool component.
    function _setNextPrizePool(uint256 val) internal {
        (, uint128 future) = _getPrizePools();
        _setPrizePools(uint128(val), future);
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
    ///      sentinel). Each debit pairs an equal `claimablePool` debit so the solvency total
    ///      stays exact, and an afking draw emits AfkingSpent. Reverts E() when the two tiers
    ///      together cannot cover the shortfall. Single sink so the sentinel + paired debits
    ///      cannot drift across the ETH-in paths that accept claimable/afking shortfall.
    /// @return claimableUsed Wei drawn from claimable. @return afkingUsed Wei drawn from afking.
    function _settleShortfall(address buyer, uint256 shortfall, bool allowClaimable)
        internal
        returns (uint256 claimableUsed, uint256 afkingUsed)
    {
        if (shortfall == 0) return (0, 0);
        if (allowClaimable) {
            uint256 claimable = _claimableOf(buyer);
            if (claimable > 1) {
                uint256 available = claimable - 1; // preserve the 1-wei sentinel
                claimableUsed = shortfall < available ? shortfall : available;
                if (claimableUsed != 0) {
                    _debitClaimable(buyer, claimableUsed);
                    claimablePool -= uint128(claimableUsed);
                }
            }
        }
        uint256 remaining = shortfall - claimableUsed;
        if (remaining != 0) {
            if (_afkingOf(buyer) < remaining) revert E();
            afkingUsed = remaining;
            _debitAfking(buyer, afkingUsed);
            claimablePool -= uint128(afkingUsed);
            emit AfkingSpent(buyer, afkingUsed);
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
        emit PlayerCredited(beneficiary, beneficiary, weiAmount);
    }

    /// @dev Debit claimable (the low half). Guard low >= amount so the subtraction never borrows
    ///      from the afking half — a low-half borrow would be invisible to 0.8's full-word check.
    function _debitClaimable(address player, uint256 weiAmount) internal {
        if (weiAmount == 0) return;
        if (uint128(balancesPacked[player]) < weiAmount) revert E();
        balancesPacked[player] -= weiAmount;
    }

    /// @dev Credit afking (the high half). A full-word add is safe: afking + amount <= 2*supply
    ///      << 2^128 (no overflow), and amount << 128 leaves the claimable low half untouched.
    function _creditAfking(address player, uint256 weiAmount) internal {
        if (weiAmount == 0) return;
        balancesPacked[player] += weiAmount << 128;
    }

    /// @dev Debit afking (the high half). The full-word subtraction is naturally fail-loud: if
    ///      afking < amount the whole word underflows and 0.8 reverts (no silent low-half borrow).
    function _debitAfking(address player, uint256 weiAmount) internal {
        if (weiAmount == 0) return;
        balancesPacked[player] -= weiAmount << 128;
    }

    /// @notice Emitted when ETH is credited to a player's prepaid afking balance.
    event AfkingFunded(address indexed player, uint256 amount);

    /// @dev Credit excess/stray ETH to a player's withdrawable prepaid afking balance,
    ///      preserving the solvency identity (claimablePool tracks the afking half). Used to
    ///      absorb purchase overpay and bare sends instead of reverting, stranding, or routing
    ///      to the prize pool — the ETH is already held by the contract, so this just records
    ///      the liability. Withdrawable via withdrawAfkingFunding (pre final sweep).
    function _creditAfkingValue(address player, uint256 weiAmount) internal {
        if (weiAmount == 0) return;
        _creditAfking(player, weiAmount);
        claimablePool += uint128(weiAmount);
        emit AfkingFunded(player, weiAmount);
    }

    // =========================================================================
    // Loot Box State & Presale Toggle
    // =========================================================================

    /// @dev Loot box state per RNG index per player, packed into one word. The amount may
    ///      accumulate within an index across deposits; the frozen-at-deposit EV inputs
    ///      (adjustedPortion, score+1) and the distress fraction ride alongside it so a box
    ///      lives in a single slot. All four fields are frozen at deposit and read-only at
    ///      open. distress is stored at 0.01-ETH granularity (distressEth / LB_DISTRESS_SCALE).
    ///      Bit layout (LSB -> MSB):
    ///      - [0:128]    amount        (uint128; boosted ETH in wei, drives the EV roll + pool credit)
    ///      - [128:192]  adjustedPortion (uint64; cap-eligible ETH that received the bonus, <= 10 ETH)
    ///      - [192:208]  score + 1     (uint16; 0 = unset; the frozen EV multiplier knob)
    ///      - [208:256]  distressUnits (uint48; distressEth / 1e16, the 25%-ticket-bonus basis)
    mapping(uint48 => mapping(address => uint256)) internal lootboxEth;

    /// @dev Bit offsets / masks for the packed lootboxEth word.
    uint256 internal constant LB_AMOUNT_MASK = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF; // 128 bits
    uint256 internal constant LB_ADJ_SHIFT = 128;
    uint256 internal constant LB_ADJ_MASK = 0xFFFFFFFFFFFFFFFF;                    // 64 bits
    uint256 internal constant LB_SCORE_SHIFT = 192;
    uint256 internal constant LB_SCORE_MASK = 0xFFFF;                             // 16 bits
    uint256 internal constant LB_DISTRESS_SHIFT = 208;
    uint256 internal constant LB_DISTRESS_MASK = 0xFFFFFFFFFFFF;                  // 48 bits
    /// @dev Distress ETH is stored at 0.01-ETH (1e16 wei) granularity in the packed slot.
    uint256 internal constant LB_DISTRESS_SCALE = 1e16;

    // =========================================================================
    // Coin-Presale-Box State
    // =========================================================================

    /// @dev Cumulative ETH spent on coin-presale boxes. Read+written per box buy
    ///      during the presale to enforce the 50-ETH cap and detect the crossing
    ///      (last-buyer DGNRS sweep + presaleOver latch). Never read after the
    ///      latch, so its cold-slot cost is confined to the presale window.
    uint96 internal presaleBoxEthSold;

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
    ///      box, whose resolution sweeps the Pool.PresaleBox remainder to that buyer.
    mapping(uint48 => mapping(address => uint256)) internal presaleBoxEth;

    /// @dev Sentinel OR'd into presaleBoxEth marking the 50-ETH-crossing box.
    uint256 internal constant PRESALE_BOX_CLOSING_FLAG = 1 << 255;
    /// @dev Bit offset of the soldBefore (buy-time cumulative box ETH) field.
    uint256 internal constant PRESALE_BOX_SOLD_SHIFT = 96;
    /// @dev Mask for the 96-bit applied-ETH / soldBefore fields in presaleBoxEth.
    uint256 internal constant PRESALE_BOX_AMOUNT_MASK = 0xFFFFFFFFFFFFFFFFFFFFFFFF; // 96 bits

    // =========================================================================
    // Presale State (packed: 2 variables in 136/256 bits)
    // =========================================================================
    //
    // Layout (LSB -> MSB):
    //   [bits   0:7]   lootboxPresaleActive   uint8    1 = presale active (starts true)
    //   [bits  8:135]  lootboxPresaleMintEth  uint128  ETH from regular mints (200 ETH cap)

    /// @dev Packed presale state. Initialized with lootboxPresaleActive = 1.
    uint256 internal presaleStatePacked = uint256(1);  // lootboxPresaleActive = true

    // ---- presaleState shifts and masks ----
    uint256 internal constant PS_ACTIVE_SHIFT = 0;
    uint256 internal constant PS_ACTIVE_MASK = 0xFF;                             // 8 bits
    uint256 internal constant PS_MINT_ETH_SHIFT = 8;
    uint256 internal constant PS_MINT_ETH_MASK = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;  // 128 bits

    /// @dev Presale auto-ends once cumulative mint-only lootbox ETH crosses this cap.
    uint256 internal constant LOOTBOX_PRESALE_ETH_CAP = 200 ether;

    /// @dev Cumulative coin-presale-box ETH cap. The box buy crossing this latches
    ///      presaleOver. Distinct from the 200-ETH mint-only LOOTBOX_PRESALE_ETH_CAP.
    uint256 internal constant PRESALE_BOX_ETH_CAP = 50 ether;

    /// @dev Read a field from the packed presale state.
    function _psRead(uint256 shift, uint256 mask) internal view returns (uint256) {
        return (presaleStatePacked >> shift) & mask;
    }

    /// @dev Write a field to the packed presale state.
    function _psWrite(uint256 shift, uint256 mask, uint256 value) internal {
        presaleStatePacked = (presaleStatePacked & ~(mask << shift)) | ((value & mask) << shift);
    }

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
    ///      Stores number of half whale passes (100 tickets each = 50 levels × 2 tickets).
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

    /// @dev Segregated DGNRS allocation per level (5% of affiliate pool at transition time).
    ///      Set during level transition in rewardTopAffiliate. Claims draw against this
    ///      fixed amount instead of the live pool balance, eliminating first-mover advantage.
    mapping(uint24 => uint256) internal levelDgnrsAllocation;

    /// @dev Cumulative DGNRS claimed per level from the segregated allocation.
    mapping(uint24 => uint256) internal levelDgnrsClaimed;

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

    /// @dev Activates a 10-level pass for a player. Shared logic for lazy pass purchases and awards.
    ///      Updates mintPacked_ (levelCount +10, frozenUntilLevel, bundleType, lastLevel, day)
    ///      and queues tickets for the 10-level range.
    /// @param player Address receiving the pass activation.
    /// @param ticketStartLevel First level of the 10-level range.
    /// @param ticketsPerLevel Number of tickets to queue per level.
    function _activate10LevelPass(
        address player,
        uint24 ticketStartLevel,
        uint32 ticketsPerLevel
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

        uint8 currentBundleType = uint8(
            (prevData >> BitPackingLib.WHALE_BUNDLE_TYPE_SHIFT) & 3
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
        if (1 >= currentBundleType) {
            data = BitPackingLib.setPacked(
                data,
                BitPackingLib.WHALE_BUNDLE_TYPE_SHIFT,
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

        _queueTicketRange(player, ticketStartLevel, 10, ticketsPerLevel, false);
    }

    /// @dev Apply whale pass stats (levelCount/freeze/bundleType/lastLevel/day) without queueing tickets.
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
            BitPackingLib.WHALE_BUNDLE_TYPE_SHIFT,
            3,
            3
        ); // 3 = 100-level bundle
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
    ///      AdvanceModule:182), so a fire would deadlock _queueTickets calls
    ///      with no path to clear rngLockedFlag. phaseTransitionActive is
    ///      implied by jackpotPhaseFlag throughout — they clear together at
    ///      AdvanceModule:328-331.
    ///
    ///      Day math is evaluated first so mid-drain RNG requests (which set
    ///      rngRequestTime during _handleGameOverPath) cannot transiently flip
    ///      liveness back to false while the drain is in progress.
    ///
    ///      Stalled-advance bailout: if day math has not yet been met, ANY
    ///      condition that leaves rngRequestTime non-zero for _VRF_GRACE_PERIOD
    ///      fires liveness. This covers genuine VRF death (callback never lands)
    ///      and any bug that prevents the advance state machine from reaching
    ///      _unlockRng — gas exhaustion, unexpected reverts in drain/jackpot
    ///      paths, or any other failure mode that bricks the cycle after a
    ///      fulfilled callback. In all cases the historical-fallback path in
    ///      _gameOverEntropy engages, letting funds drain to players via
    ///      terminal jackpot rather than remaining trapped. Below that
    ///      threshold, liveness stays false — players can propose a coordinator
    ///      rotation via DegenerusAdmin, and missed days are credited back to
    ///      purchaseStartDay in AdvanceModule.rngGate on fulfillment.
    function _livenessTriggered() internal view returns (bool) {
        if (lastPurchaseDay || jackpotPhaseFlag) return false;
        uint24 lvl = level;
        uint24 psd = purchaseStartDay;
        uint24 currentDay = _simulatedDayIndex();
        if (lvl == 0 && currentDay - psd > _DEPLOY_IDLE_TIMEOUT_DAYS) return true;
        if (lvl != 0 && currentDay - psd > 120) return true;
        uint48 rngStart = rngRequestTime;
        return rngStart != 0 && block.timestamp - rngStart >= _VRF_GRACE_PERIOD;
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
    // VRF Configuration (moved from DegenerusGame for module access)
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
    // Lootbox RNG Packed Slot (6 variables in 232/256 bits)
    // =========================================================================
    //
    // Layout (LSB -> MSB):
    //   [bits   0:47]   lootboxRngIndex          uint48   (281T indices)
    //   [bits  48:111]  lootboxRngPendingEth     uint64   (scaled /1e15, 0.001 ETH res, max ~18,446 ETH)
    //   [bits 112:175]  lootboxRngThreshold      uint64   (scaled /1e15, 0.001 ETH res, max ~18,446 ETH)
    //   [bits 176:183]  lootboxRngMinLinkBalance  uint8   (whole LINK, 0-255 LINK)
    //   [bits 184:223]  lootboxRngPendingBurnie  uint40   (scaled /1e18, 1 BURNIE res, max ~1.1T BURNIE)
    //   [bits 224:231]  midDayTicketRngPending   uint8    (bool flag, 8 bits)

    /// @dev Packed lootbox RNG state. See layout comment above.
    ///      Initialized with lootboxRngIndex=1, lootboxRngThreshold=1 ether (scaled=1000),
    ///      lootboxRngMinLinkBalance=14 LINK (whole).
    uint256 internal lootboxRngPacked =
        uint256(1)                                  // lootboxRngIndex = 1
        | (uint256(1000) << 112)                    // lootboxRngThreshold = 1 ether / 1e15 = 1000
        | (uint256(14) << 176);                     // lootboxRngMinLinkBalance = 14 LINK (whole)

    // ---- lootboxRng shifts and masks ----
    uint256 internal constant LR_INDEX_SHIFT = 0;
    uint256 internal constant LR_INDEX_MASK = 0xFFFFFFFFFFFF;                // 48 bits
    uint256 internal constant LR_PENDING_ETH_SHIFT = 48;
    uint256 internal constant LR_PENDING_ETH_MASK = 0xFFFFFFFFFFFFFFFF;      // 64 bits
    uint256 internal constant LR_THRESHOLD_SHIFT = 112;
    uint256 internal constant LR_THRESHOLD_MASK = 0xFFFFFFFFFFFFFFFF;        // 64 bits
    uint256 internal constant LR_MIN_LINK_SHIFT = 176;
    uint256 internal constant LR_MIN_LINK_MASK = 0xFF;                       // 8 bits
    uint256 internal constant LR_PENDING_BURNIE_SHIFT = 184;
    uint256 internal constant LR_PENDING_BURNIE_MASK = 0xFFFFFFFFFF;         // 40 bits
    uint256 internal constant LR_MID_DAY_SHIFT = 224;
    uint256 internal constant LR_MID_DAY_MASK = 0xFF;                       // 8 bits

    /// @dev Scale factor for ETH/LINK packing (0.001 resolution).
    uint256 internal constant LR_ETH_SCALE = 1e15;
    /// @dev Scale factor for BURNIE packing (1 token resolution).
    uint256 internal constant LR_BURNIE_SCALE = 1e18;

    // Activity score EV multiplier constants (ETH lootbox only)
    /// @dev 60% activity score = neutral 100% EV
    uint16 internal constant LOOTBOX_EV_ACTIVITY_NEUTRAL_BPS = 6_000;
    /// @dev 255%+ activity score = maximum 135% EV
    uint16 internal constant LOOTBOX_EV_ACTIVITY_MAX_BPS = 25_500;
    /// @dev Minimum EV at 0% activity (80%)
    uint16 internal constant LOOTBOX_EV_MIN_BPS = 8_000;
    /// @dev Neutral EV at 60% activity (100%)
    uint16 internal constant LOOTBOX_EV_NEUTRAL_BPS = 10_000;
    /// @dev Maximum EV at 255%+ activity (135%)
    uint16 internal constant LOOTBOX_EV_MAX_BPS = 13_500;
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

    /// @dev Pack a wei amount to milli-ETH (divide by 1e15). 0.001 ETH resolution.
    function _packEthToMilliEth(uint256 wei_) internal pure returns (uint64) {
        return uint64(wei_ / LR_ETH_SCALE);
    }

    /// @dev Unpack milli-ETH to wei (multiply by 1e15).
    function _unpackMilliEthToWei(uint64 milli) internal pure returns (uint256) {
        return uint256(milli) * LR_ETH_SCALE;
    }

    /// @dev Pack a wei amount to whole BURNIE (divide by 1e18). 1 BURNIE resolution.
    function _packBurnieToWhole(uint256 wei_) internal pure returns (uint40) {
        return uint40(wei_ / LR_BURNIE_SCALE);
    }

    /// @dev Unpack whole BURNIE to wei (multiply by 1e18).
    function _unpackWholeBurnieToWei(uint40 whole) internal pure returns (uint256) {
        return uint256(whole) * LR_BURNIE_SCALE;
    }

    /// @dev Pack a lootbox box into one uint256 word (the lootboxEth slot).
    ///      Layout: amount at [0:128], adjustedPortion at [128:192], score+1 at [192:208],
    ///      distressUnits at [208:256]. distressUnits is distressEth / LB_DISTRESS_SCALE,
    ///      already scaled by the caller. Each field is masked to its width before shifting
    ///      so an over-wide argument cannot alias an adjacent field.
    function _packLootbox(uint256 amount, uint64 adj, uint16 scorePlus1, uint256 distressUnits)
        internal pure returns (uint256) {
        return (amount & LB_AMOUNT_MASK)
            | (uint256(adj) & LB_ADJ_MASK) << LB_ADJ_SHIFT
            | (uint256(scorePlus1) & LB_SCORE_MASK) << LB_SCORE_SHIFT
            | (distressUnits & LB_DISTRESS_MASK) << LB_DISTRESS_SHIFT;
    }

    /// @dev Unpack a lootbox box word into its four fields. distressUnits is at
    ///      0.01-ETH granularity; multiply by LB_DISTRESS_SCALE for wei.
    function _unpackLootbox(uint256 word)
        internal pure returns (uint256 amount, uint64 adj, uint16 scorePlus1, uint256 distressUnits) {
        amount = word & LB_AMOUNT_MASK;
        adj = uint64((word >> LB_ADJ_SHIFT) & LB_ADJ_MASK);
        scorePlus1 = uint16((word >> LB_SCORE_SHIFT) & LB_SCORE_MASK);
        distressUnits = (word >> LB_DISTRESS_SHIFT) & LB_DISTRESS_MASK;
    }

    /// @dev Calculates EV multiplier from a raw activity score.
    ///      Linear interpolation between thresholds.
    /// @param score The activity score in basis points
    /// @return The EV multiplier in basis points (8000-13500)
    function _lootboxEvMultiplierFromScore(
        uint256 score
    ) internal pure returns (uint256) {
        if (score <= LOOTBOX_EV_ACTIVITY_NEUTRAL_BPS) {
            // Linear: 0% → 80% EV, 60% → 100% EV
            return LOOTBOX_EV_MIN_BPS +
                (score * (LOOTBOX_EV_NEUTRAL_BPS - LOOTBOX_EV_MIN_BPS)) /
                LOOTBOX_EV_ACTIVITY_NEUTRAL_BPS;
        }

        if (score >= LOOTBOX_EV_ACTIVITY_MAX_BPS) {
            return LOOTBOX_EV_MAX_BPS;
        }

        // Linear: 60% → 100% EV, 255% → 135% EV
        uint256 excess = score - LOOTBOX_EV_ACTIVITY_NEUTRAL_BPS;
        uint256 maxExcess = LOOTBOX_EV_ACTIVITY_MAX_BPS - LOOTBOX_EV_ACTIVITY_NEUTRAL_BPS;
        return
            LOOTBOX_EV_NEUTRAL_BPS +
            (excess * (LOOTBOX_EV_MAX_BPS - LOOTBOX_EV_NEUTRAL_BPS)) /
            maxExcess;
    }

    /// @dev RNG words keyed by lootbox RNG index.
    mapping(uint48 => uint256) internal lootboxRngWordByIndex;

    // =========================================================================
    // Deity Boon Tracking
    // =========================================================================

    /// @dev Day when deity's boon slots were assigned.
    mapping(address => uint24) internal deityBoonDay;

    /// @dev Bitmask of used slots for the current day (bit i = slot i used).
    mapping(address => uint8) internal deityBoonUsedMask;

    /// @dev Day when recipient last received a deity boon (prevents double-receipt).
    mapping(address => uint24) internal deityBoonRecipientDay;

    // =========================================================================
    // Degenerette (Roulette) Bets
    // =========================================================================

    /// @dev Bets keyed by player and bet id.
    /// Packed layout (LSB → MSB):
    /// - [0]        mode (1=full ticket)
    /// - [1]        isRandom
    /// - [2..33]    customTicket (packed 4×8-bit quadrants)
    /// - [34..41]   ticketCount (uint8, used as "spin count" for Degenerette)
    /// - [42..43]   currency (0=ETH,1=BURNIE,2=unsupported,3=WWXRP)
    /// - [44..171]  amountPerTicket (uint128)
    /// - [172..219] RNG index (uint48)
    /// - [220..235] activity score bps (uint16)
    /// - [236]      hasCustom
    mapping(address => mapping(uint64 => uint256)) internal degeneretteBets;

    /// @dev Per-player bet counters for Degenerette.
    mapping(address => uint64) internal degeneretteBetNonce;

    // =========================================================================
    // Lootbox EV Multiplier Cap Tracking
    // =========================================================================

    /// @dev Amount of lootbox ETH that has received EV multiplier benefit per player per level.
    ///      Capped at 10 ETH per account per level to prevent excessive EV boost exploitation.
    mapping(address => mapping(uint24 => uint256))
        internal lootboxEvBenefitUsedByLevel;

    // =========================================================================
    // Decimator Jackpot State
    // =========================================================================
    // Migrated from DegenerusJackpots to consolidate all decimator logic
    // into the DecimatorModule for cleaner architecture.

    /// @dev Player's decimator burn entry per level.
    struct DecEntry {
        /// @notice Total BURNIE burned by player this level (capped at uint192.max).
        uint192 burn;
        /// @notice Player's denominator choice (2-12), may improve to lower denom during level.
        uint8 bucket;
        /// @notice Deterministic subbucket from hash(player, lvl, bucket), range 0..(bucket-1).
        uint8 subBucket;
        /// @notice Claim flag (0 = unclaimed, 1 = claimed).
        uint8 claimed;
    }

    /// @dev Snapshot of a decimator jackpot for claim processing.
    struct DecClaimRound {
        /// @notice ETH prize pool available for claims.
        uint256 poolWei;
        /// @notice VRF random word for lootbox entropy derivation.
        uint256 rngWord;
        /// @notice Total qualifying burn across winning subbuckets (denominator for pro-rata).
        uint232 totalBurn;
    }

    /// @dev Player decimator entries per level.
    ///      decBurn[lvl][player] = DecEntry
    mapping(uint24 => mapping(address => DecEntry)) internal decBurn;

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
    ///      Collects 46% of yield surplus each level transition.
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
    // VRF Liveness Timestamp (Governance)
    // =========================================================================

    /// @dev Timestamp of the last successfully processed VRF word.
    ///      Used by governance to detect VRF stalls (time-based vs day-gap-based).
    ///      Initialized in wireVrf(), updated in _applyDailyRng().
    uint48 internal lastVrfProcessedTimestamp;

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
    struct TerminalDecEntry {
        uint80 totalBurn;
        uint88 weightedBurn;
        uint8 bucket;
        uint8 subBucket;
        uint48 burnLevel;
        bool boosted;
    }
    mapping(address => TerminalDecEntry) internal terminalDecEntries;

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
    // Boon Packed Storage (replaces 29 per-player boon mappings above)
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
    /// Slot 1 (256 bits, using 184):
    ///   [0-23]    activityPending      uint24   Pending activity bonus levels
    ///   [24-47]   activityDay          uint24   Day activity boon was awarded
    ///   [48-71]   deityActivityDay     uint24   Deity-source day for activity boon
    ///   [72-79]   deityPassTier        uint8    0=none, 1=10%, 2=20%, 3=35%
    ///   [80-103]  deityPassDay         uint24   Day deity pass boon was awarded
    ///   [104-127] deityDeityPassDay    uint24   Deity-granted deity pass boon day
    ///   [128-151] lazyPassDay          uint24   Day lazy pass boon was awarded
    ///   [152-175] deityLazyPassDay     uint24   Deity-source day for lazy pass boon
    ///   [176-183] lazyPassTier         uint8    0=none, 1=10%, 2=25%, 3=50%
    ///   [184-255] (unused, 72 bits)
    struct BoonPacked {
        uint256 slot0;
        uint256 slot1;
    }

    /// @dev Per-player packed boon state. Replaces the 29 individual boon mappings
    ///      (slots 25-41, 72-82, 85-87, 93-95) which remain as slot placeholders.
    ///      Public getter returns (uint256 slot0, uint256 slot1); bit layout above.
    ///      UI readers combine with currentDayView() to compute per-category expiry.
    mapping(address => BoonPacked) public boonPacked;

    // =========================================================================
    // claimBingo color-completion bitfields (v51.0 — claimBingo-EXCLUSIVE)
    //
    // Appended at the storage-layout tail; pre-launch redeploy-fresh, no migration.
    // Keyed by uint24 level (the traitBurnTicket precedent at :416). The ONLY
    // reader/writer of these three mappings is DegenerusGameBingoModule.claimBingo.
    // =========================================================================

    /// @dev Per-player 4-bit quadrant mask: which quadrants this player has already
    ///      claimed on a level (max 4 claims/player/level). bingoClaimed[level][player].
    mapping(uint24 => mapping(address => uint8)) internal bingoClaimed;

    /// @dev Systemwide 4-bit quadrant mask: which quadrants have had their first
    ///      bingo on a level (max 4 quadrant-firsts/level). firstQuadrant[level].
    mapping(uint24 => uint8) internal firstQuadrant;

    /// @dev Systemwide 32-bit symbol mask: which symbols (0-31) have had their first
    ///      bingo on a level (max 32 symbol-firsts/level). firstSymbol[level].
    mapping(uint24 => uint32) internal firstSymbol;

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

    // ---- Slot 1 shifts ----
    uint256 internal constant BP_ACTIVITY_PENDING_SHIFT = 0;
    uint256 internal constant BP_ACTIVITY_DAY_SHIFT = 24;
    uint256 internal constant BP_DEITY_ACTIVITY_DAY_SHIFT = 48;
    uint256 internal constant BP_DEITY_PASS_TIER_SHIFT = 72;
    uint256 internal constant BP_DEITY_PASS_DAY_SHIFT = 80;
    uint256 internal constant BP_DEITY_DEITY_PASS_DAY_SHIFT = 104;
    uint256 internal constant BP_LAZY_PASS_DAY_SHIFT = 128;
    uint256 internal constant BP_DEITY_LAZY_PASS_DAY_SHIFT = 152;
    uint256 internal constant BP_LAZY_PASS_TIER_SHIFT = 176;

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
    // Activity: bits 0-71 (activityPending[24] + activityDay[24] + deityActivityDay[24])
    uint256 internal constant BP_ACTIVITY_CLEAR = ~uint256((1 << 72) - 1);
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
    /// @dev Layout (Solidity packs sequentially) — fits EXACTLY in ONE 32-byte slot (256
    ///      bits, 0 free), so the whole record reads/writes as a single warm slot with no
    ///      extra cold slot:
    ///        config (40b):  dailyQuantity(8) + validThroughLevel(24) + reinvestPct(8) + flags(8)
    ///        per-sub stamp (40b): scorePlus1(16) + amount(24, milli-ETH)
    ///        markers (96b): lastAutoBoughtDay(24) + lastOpenedDay(24) + afkCoveredThroughDay(24) + afkingStartDay(24)
    ///        accumulator (72b): affiliateBase(32) + pendingBurnie(32) + subStreakLatch(8)
    ///      There is NO per-day epoch: the box resolves at the LIVE level at open (no
    ///      stored roll floor) and sources its RNG word from
    ///      `rngWordByDay[lastAutoBoughtDay]`, so the only frozen-at-stamp inputs are the
    ///      two genuinely-per-sub fields — `scorePlus1` (activity score) and `amount`
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
    ///      (bits 0-6) frame the run; the effective afking quest streak is derived on read from
    ///      `afkCoveredThroughDay` (no DegenerusQuests STATICCALL on the buy path) and handed
    ///      back to the manual quest system on any sub-ending path (finalize).
    ///
    ///      In-slot accumulator (cheap per-buy; advanced by the per-buy accrue write into this
    ///      already-warm slot, so no new cold slot):
    ///        • `affiliateBase` — per-sub running unclaimed AFFILIATE balance, whole
    ///          BURNIE; drained and paid out by `DegenerusAffiliate.claim`, zeroed there
    ///          so a re-claim finds 0.
    ///        • `pendingBurnie` — per-sub running CLAIMABLE BURNIE balance, whole BURNIE,
    ///          accrued per delivered day (the slot-0 quest reward every mode + the
    ///          ticket-mode 10%/20% buyer bonus). Paid out only by the player-pull
    ///          `claimAfkingBurnie`, zeroed there.
    ///        • `subStreakLatch` — bits 0-6 the afking-run streak snapshot (bit 7 unused).
    ///      `affiliateBase` and `pendingBurnie` are uint32 with a 100M-whole-BURNIE
    ///      saturating clamp at the accrue write — uint32 holds ~4.29e9 > 100M so the
    ///      clamp binds first, and it can only ever UNDER-credit a pathological
    ///      reinvest-whale (off the solvency path). The accumulator fields are written on
    ///      the buy-accrue path and the open markers (`lastOpenedDay`/`lastAutoBoughtDay`)
    ///      on the open path — disjoint fields in one warm slot, no collision.
    ///      There are no settle-day markers: the running balances self-mark, the pull has
    ///      no window, and the quest flush drains the counters so a double-fire finds 0.
    ///      `afkCoveredThroughDay` is a delivered-day high-water mark, not a settle
    ///      marker.
    struct Sub {
        // --- config (48 bits) ---
        /// @dev 0 = paused / never-subscribed; minimum 1 when active.
        uint8 dailyQuantity;
        /// @dev Game-level horizon through which the sub's pass coverage extends
        ///      (lazyPassHorizon snapshot at subscribe; refreshed on crossing;
        ///      deity sentinel = type(uint24).max; non-pass = 0). uint24 gives ~16.7M
        ///      levels of headroom and the deity sentinel type(uint24).max fits exactly.
        uint24 validThroughLevel;
        /// @dev Claimable reinvest percentage (0..100); 0 = no reinvest.
        uint8 reinvestPct;
        /// @dev bit 0 free; bit 1 = drainGameCreditFirst; bit 2 = useTickets.
        uint8 flags;
        // --- per-sub stamp (48 bits) ---
        /// @dev Stamp: frozen activityScore + 1 (the EV multiplier input at open).
        ///      Genuinely per-sub (each subscriber's own activity score).
        uint16 scorePlus1;
        /// @dev Stamp: spend in milli-ETH (0.001-ETH units; boons off, so amount ==
        ///      spend, = mp × effectiveQty). Milli-ETH in a uint24 (16,777 ETH/buy of
        ///      headroom — a single auto-buy never approaches it); packed via
        ///      `_packEthToMilliEth` at the stamp write and unpacked via
        ///      `_unpackMilliEthToWei` before the box seed / EV-cap payout math. The
        ///      round-down is on this recorded EV/seed input only — the actual ETH debit
        ///      still uses the full wei `ethValue`.
        uint24 amount;
        // --- markers (72 bits) ---
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
        /// @dev Per-sub running unclaimed affiliate balance, whole BURNIE. Accrued a flat
        ///      7% per buy (one warm in-slot `+=`); drained and paid out by
        ///      `DegenerusAffiliate.claim`, zeroed there so a re-claim finds 0. uint32
        ///      with a 100,000,000-whole-BURNIE saturating clamp at the accrue write
        ///      (uint32 holds ~4.29e9 > 100M, so the clamp binds first); the clamp can
        ///      only ever under-credit, off the solvency path.
        uint32 affiliateBase;
        /// @dev Per-sub running CLAIMABLE BURNIE balance, whole BURNIE. Accrued per
        ///      delivered day by the warm in-slot buy accrue: the slot-0 quest reward
        ///      (every mode) plus the ticket-mode 10%/20% buyer bonus. Paid out only by the
        ///      player-pull `claimAfkingBurnie` (one creditFlip, zeroed there so a re-claim
        ///      finds 0); the sub claims whenever, so there is no settle/claim-timing edge.
        ///      Same uint32 + 100M saturating clamp + under-credit-only behaviour as
        ///      `affiliateBase`.
        uint32 pendingBurnie;
        /// @dev `streakAtAfkingStart` — the quest streak snapshot at the start of the current
        ///      afking run (0..100, the score's effective cap; fits bits 0-6, bit 7 unused). The
        ///      compute-on-read effective streak adds the funded delivered days
        ///      `(afkCoveredThroughDay - afkingStartDay)` to this base. Written rarely (subscribe +
        ///      gap-resume); read per buy as a mask op, so `affiliateBase`/`pendingBurnie` stay
        ///      unmasked for the hot accrue.
        uint8 subStreakLatch;
    }

    /// @dev `subStreakLatch` bits 0-6 — `streakAtAfkingStart` (0..100, clamped on write).
    ///      Bit 7 is unused (formerly a first-sub latch, removed with the head-start).
    uint8 internal constant SUB_STREAK_MASK = 0x7f;

    /// @dev Read the afking-run streak snapshot (bits 0-6 of the packed latch byte).
    function _streakBaseOf(Sub storage sub) internal view returns (uint8) {
        return sub.subStreakLatch & SUB_STREAK_MASK;
    }

    /// @dev Write the afking-run streak snapshot, clamped to 100 (the score cap).
    function _setStreakBase(Sub storage sub, uint256 value) internal {
        sub.subStreakLatch = value > 100 ? 100 : uint8(value);
    }

    /// @dev Per-subscriber record (the iterable set's value): the per-sub stamp, the
    ///      day markers (incl. `afkingStartDay` / `afkCoveredThroughDay` for the compute-on-read
    ///      streak), and the in-slot accumulator (affiliateBase / pendingBurnie / subStreakLatch).
    mapping(address => Sub) internal _subOf;

    /// @dev Sparse funder map — the wallet whose `afkingFunding` funds a sub.
    ///      Absent / address(0) ⇒ self-funded (the common case, which stores NOTHING).
    ///      CONSENT-01 funder identity. Written at
    ///      subscribe (set-if-nonzero / delete-if-self) and read once per process
    ///      iteration to resolve `src` (and once at open is NOT needed — funding is
    ///      already debited at process). OPEN-E 4-protection unchanged.
    mapping(address => address) internal _fundingSourceOf;

    /// @dev Insertion-ordered iterable subscriber set (swap-pop tombstone on
    ///      cancel — the H-CANCEL-SWAP-MISS membership class).
    address[] internal _subscribers;

    /// @dev 1-indexed membership ⟺ packed-index map (0 = not in set); the
    ///      swap-pop bookkeeping for `_subscribers`.
    mapping(address => uint256) internal _subscriberIndex;

    /// @dev The two uint16 cursors + the uint24 afking reset-day pack into ONE slot
    ///      (16 + 16 + 24 = 56 bits). The cursors index `_subscribers` (the active set
    ///      is capped at 500 — GameAfkingModule.SUBSCRIBER_CAP, well within uint16) and
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

    /// @dev Cursor into the box auto-open queue for the current lootbox RNG index.
    ///      Concurrent same-tx callers self-partition via the advancing cursor.
    ///      Reset to zero when the active index advances (collision-free walk).
    uint48 internal boxCursor;

    /// @dev Index against which the cursor currently walks (boxCursor day-reset key).
    uint48 internal boxCursorIndex;

    /// @dev RNG index of the coin-presale-box close (the 50-ETH-crossing buy) — the highest index
    ///      any presale box can occupy. Set once when presaleOver latches. Packs into the cursor
    ///      slot (free read in the sweep, which already loads boxCursorIndex); the sweep flips
    ///      presaleDrained once boxCursorIndex advances past it. Zero while presale never closes.
    uint48 internal presaleCloseIndex;

    /// @dev Players with an open box queued per lootbox RNG index, enqueued once at
    ///      first deposit (the lootboxEth amount == 0 signal). Keyed on the lootbox index,
    ///      which re-couples to the VRF-rotation orphan-index keyspace — the box auto-open
    ///      walk MUST gate each open on lootboxRngWordByIndex[index] != 0 so an index
    ///      orphaned mid-day by an emergency coordinator rotation is skipped until the
    ///      a303ae18 detect-preserve-re-issue path lands the re-issued word.
    mapping(uint48 => address[]) internal boxPlayers;
}
