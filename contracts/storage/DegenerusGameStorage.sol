// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {ContractAddresses} from "../ContractAddresses.sol";
import {IVRFCoordinator} from "../interfaces/IVRFCoordinator.sol";
import {IStakedDegenerusStonk} from "../interfaces/IStakedDegenerusStonk.sol";
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
 *   - DegenerusGameEndgameModule (delegatecall module)
 *   - DegenerusGameJackpotModule (delegatecall module)
 *   - DegenerusGameMintModule (delegatecall module)
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
 * | EVM SLOT 0 (32 bytes) — Timing, FSM, Cursors, Counters, Flags              |
 * +-----------------------------------------------------------------------------+
 * | [0:6]   levelStartTime           uint48   Timestamp when level opened       |
 * | [6:12]  dailyIdx                 uint48   Monotonic day counter             |
 * | [12:18] rngRequestTime           uint48   When last VRF request was fired   |
 * | [18:21] level                    uint24   Current jackpot level (starts at 0) |
 * | [21:22] jackpotPhaseFlag         bool     Phase: false=PURCHASE, true=JACKPOT|
 * | [22:23] jackpotCounter           uint8    Jackpots processed this level      |
 * | [23:24] earlyBurnPercent         uint8    Previous pool % in early burn      |
 * | [24:25] poolConsolidationDone    bool     Pool consolidation executed flag   |
 * | [25:26] lastPurchaseDay          bool     Prize target met flag              |
 * | [26:27] decWindowOpen            bool     Decimator window latch             |
 * | [27:28] rngLockedFlag            bool     Daily RNG lock (jackpot window)    |
 * | [28:29] phaseTransitionActive    bool     Level transition in progress       |
 * | [29:30] gameOver                 bool     Terminal state flag                |
 * | [30:31] dailyJackpotCoinTicketsPending bool Split jackpot pending flag       |
 * | [31:32] dailyEthBucketCursor     uint8    Bucket cursor for daily ETH dist   |
 * +-----------------------------------------------------------------------------+
 *   Total: 32 bytes (fully packed)
 *
 * +-----------------------------------------------------------------------------+
 * | EVM SLOT 1 (32 bytes) — ETH Phase, Price, Double-Buffer Fields             |
 * +-----------------------------------------------------------------------------+
 * | [0:1]   dailyEthPhase            uint8    0=current level, 1=carryover       |
 * | [1:2]   compressedJackpotFlag    uint8    0=normal, 1=compressed (3d), 2=turbo (1d) |
 * | [2:8]   purchaseStartDay         uint48   Day index when purchase phase began|
 * | [8:24]  price                    uint128  Current mint price in wei          |
 * | [24:25] ticketWriteSlot          uint8    Double-buffer write index (0 or 1) |
 * | [25:26] ticketsFullyProcessed    bool     Read slot fully drained flag       |
 * | [26:27] prizePoolFrozen          bool     Prize pool freeze active flag      |
 * | [27:32] <padding>                         5 bytes unused                     |
 * +-----------------------------------------------------------------------------+
 *   Total: 27 bytes used (5 bytes padding)
 *
 * +-----------------------------------------------------------------------------+
 * | EVM SLOT 2 (32 bytes) — Current Prize Pool                                  |
 * +-----------------------------------------------------------------------------+
 * | [0:32]  currentPrizePool         uint256  Active prize pool for current level|
 * +-----------------------------------------------------------------------------+
 *
 * SLOTS 3+ — Full-width variables, arrays, and mappings
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
 *    - levelStartTime = deploy timestamp (set in constructor)
 *    - jackpotPhaseFlag = false (purchase phase)
 *    - decWindowOpen = false (opens at level 4 jackpot phase start)
 *    - price = 0.01 ether (initial mint price)
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
abstract contract DegenerusGameStorage {
    // =========================================================================
    // CONSTANTS
    // =========================================================================

    /// @dev Conversion factor for BURNIE token amounts.
    ///      BURNIE uses 18 decimals, so 1000 BURNIE = 1e21 base units.
    ///      Used in price calculations: price / PRICE_COIN_UNIT = BURNIE per mint.
    uint256 internal constant PRICE_COIN_UNIT = 1000 ether;

    /// @dev Scale factor for fractional ticket calculations (2 decimal places).
    ///      100 means 1 ticket = 100 scaled units.
    uint256 internal constant TICKET_SCALE = 100;

    /// @dev ETH threshold for whale pass claim eligibility from lootbox wins.
    uint256 internal constant LOOTBOX_CLAIM_THRESHOLD =
        5 ether;

    /// @dev Bootstrap value for prize pool target at level 1 (before any level completes).
    ///      levelPrizePool[0] is initialized to this value conceptually.
    uint256 internal constant BOOTSTRAP_PRIZE_POOL =
        50 ether;

    /// @dev Level at which earlybird DGNRS rewards end (exclusive).
    uint24 internal constant EARLYBIRD_END_LEVEL = 3;

    /// @dev Total ETH target for earlybird DGNRS emission curve.
    uint256 internal constant EARLYBIRD_TARGET_ETH =
        1_000 ether;

    /// @dev Current-pool daily jackpot percentage is rolled in JackpotModule.
    ///      Days 1-4 use a random 6%-14% slice of remaining currentPrizePool.
    ///      Day 5 pays 100% of the remaining currentPrizePool.

    /// @dev Bit mask for ticket queue double-buffer key encoding.
    ///      Set bit 23 of the uint24 level key to distinguish write/read slots.
    ///      Max real level: 2^23 - 1 = 8,388,607 (game would take millennia).
    uint24 internal constant TICKET_SLOT_BIT = 1 << 23;

    /// @dev Hours before gameover liveness guard at which distress mode activates.
    uint48 internal constant DISTRESS_MODE_HOURS = 6;

    /// @dev Deploy idle timeout in days (mirrors DegenerusGame / AdvanceModule).
    uint48 internal constant _DEPLOY_IDLE_TIMEOUT_DAYS = 365;

    /// @dev True when gameover liveness guard would fire within DISTRESS_MODE_HOURS.
    ///      Used to activate distress-mode lootbox behaviour: 100% nextpool allocation
    ///      and 25% ticket bonus on the distress-bought portion.
    function _isDistressMode() internal view returns (bool) {
        if (gameOver) return false;
        uint48 lst = levelStartTime;
        uint48 ts = uint48(block.timestamp);
        if (level == 0) {
            return uint256(ts) + uint256(DISTRESS_MODE_HOURS) * 1 hours >
                uint256(lst) + uint256(_DEPLOY_IDLE_TIMEOUT_DAYS) * 1 days;
        }
        return uint256(ts) + uint256(DISTRESS_MODE_HOURS) * 1 hours > uint256(lst) + 120 days;
    }

    // =========================================================================
    // Errors
    // =========================================================================

    /// @dev Gas-minimal revert signal. Matches codebase convention (DegenerusGame, modules).
    error E();

    // =========================================================================
    // SLOT 0: Level Timing, Batching, and Finite State Machine
    // =========================================================================
    // These variables pack into a single 32-byte storage slot for gas efficiency.
    // Order matters: EVM packs from low to high within a slot.

    /// @dev Timestamp when the current level opened for purchase phase.
    ///      Initialized to block.timestamp in the constructor (deploy time).
    ///      Used for inactivity guard timing and purchase-phase daily jackpots.
    ///
    ///      SECURITY: uint48 holds timestamps until year 8.9 million — safe for any
    ///      realistic game lifetime. Overflow is not a concern.
    uint48 internal levelStartTime;

    /// @dev Monotonically increasing "day" counter derived from block timestamps.
    ///      Incremented during game progression; used to key RNG words and track
    ///      daily jackpot eligibility. NOT tied to calendar days — it's game-relative.
    ///
    ///      SECURITY: uint48 allows ~281 trillion increments — effectively unlimited.
    uint48 internal dailyIdx;

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

    /// @dev Percentage of previous prize pool carried into early burn reward.
    ///      Range 0-255 (but practically 0-100%). Used for early burn bonus
    ///      calculations in the jackpot module.
    uint8 internal earlyBurnPercent;

    /// @dev True once prize pool consolidation has been executed for the
    ///      current purchase phase. Prevents double-execution.
    ///
    ///      SECURITY: Critical for pool integrity. Reset at level transition.
    bool internal poolConsolidationDone;

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

    /// @dev Cursor for daily jackpot ETH distribution (bucket order index, 0..3).
    ///      Used with dailyEthWinnerCursor for mid-bucket resume.
    uint8 internal dailyEthBucketCursor;

    // =========================================================================
    // EVM SLOT 1: ETH Phase, Price, and Double-Buffer Fields
    // =========================================================================
    // Packs into EVM Slot 1: dailyEthPhase through prizePoolFrozen (27 bytes used, 5 bytes padding).

    /// @dev Daily jackpot ETH phase.
    ///      0 = current level, 1 = carryover.
    uint8 internal dailyEthPhase;

    /// @dev Jackpot compression tier: 0=normal (5d), 1=compressed (3d), 2=turbo (1d).
    ///      Set when purchase-phase target is met quickly, signaling high player interest.
    ///      Turbo (2): target met within 1 day — entire jackpot in 1 physical day.
    ///      Compressed (1): target met within 3 days — 5 logical days in 3 physical.
    ///      Cleared at phase end.
    uint8 internal compressedJackpotFlag;

    /// @dev Game day index when the current purchase phase opened.
    ///      Used to determine whether the purchase target was met quickly enough
    ///      to trigger compressed jackpot mode. Default 0 works for level 0 since
    ///      the first daily advance is day 1, giving day - 0 = 1 ≤ 3.
    uint48 internal purchaseStartDay;

    /// @dev Base price unit in wei. One unit covers 4 scaled ticket entries.
    ///      uint128 supports up to ~340 undecillion wei (~3.4e20 ETH) — far
    ///      beyond any realistic price point.
    ///
    ///      Default 0.01 ether = 10 finney = initial launch price.
    ///
    ///      SECURITY: Price updates are game-controlled. uint128 prevents
    ///      overflow in multiplication with reasonable quantities.
    uint128 internal price =
        uint128(0.01 ether);

    /// @dev Active write buffer index for ticket queue double-buffering (0 or 1).
    ///      Toggled via XOR (`ticketWriteSlot ^= 1`) during queue slot swaps.
    ///      Write path uses this value; read path uses the opposite.
    ///
    ///      SECURITY: uint8 (not bool) required for XOR toggle arithmetic.
    ///      Only values 0 and 1 are valid; _swapTicketSlot enforces this.
    uint8 internal ticketWriteSlot;

    /// @dev True when the read slot has been fully drained (all tickets processed).
    ///      Gate for RNG requests and jackpot logic in advanceGame daily path.
    ///
    ///      SECURITY: Must be set to true before any jackpot/phase logic executes.
    ///      Reset to false on every queue slot swap.
    bool internal ticketsFullyProcessed;

    /// @dev True when purchase revenue redirects to pending accumulators.
    ///      Set at daily RNG request time; cleared by _unfreezePool().
    ///
    ///      SECURITY: Persists across jackpot phase days. All 5 jackpot payouts
    ///      use pre-freeze pool values. _unfreezePool is the single control point.
    bool internal prizePoolFrozen;

    // =========================================================================
    // SLOTS 3+: Full-Width Balances and Pools
    // =========================================================================
    // Each uint256 occupies its own 32-byte slot. These track ETH/token flows.

    /// @dev Active prize pool for the current level.
    ///      Accumulated from mint fees and distributed via jackpots.
    uint256 internal currentPrizePool;

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

    /// @dev Daily jackpot ETH pool budget for current-level distribution.
    ///      Stored to keep bucket sizing deterministic across split calls.
    uint256 internal dailyEthPoolBudget;

    // =========================================================================
    // Token State and Jackpot Mechanics
    // =========================================================================

    /// @dev ETH claimable by players from jackpot winnings.
    ///      Credited by jackpot logic; withdrawn via claim function.
    ///
    ///      SECURITY: Pull pattern — players withdraw their own funds.
    ///      Prevents reentrancy by separating credit from transfer.
    mapping(address => uint256) internal claimableWinnings;

    /// @dev Aggregate ETH liability across all claimableWinnings entries.
    ///      Used for solvency checks: game must hold >= claimablePool ETH.
    ///
    ///      INVARIANT: claimablePool >= sum(claimableWinnings[*])
    ///      Maintained by crediting/debiting both in tandem.
    ///      NOTE: During decimator settlement, the full pool is reserved in claimablePool
    ///      before individual claims are credited, temporarily breaking equality.
    uint256 internal claimablePool;

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
    ///      Layout defined by ETH_* constants in DegenerusGame:
    ///      - Tracks mint counts, bonuses, and eligibility flags.
    ///      - Single SLOAD/SSTORE for all mint-related player data.
    ///
    ///      SECURITY: Packing reduces gas and storage footprint.
    ///      Bit manipulation requires careful masking (done in DegenerusGame).
    mapping(address => uint256) internal mintPacked_;

    // =========================================================================
    // RNG History
    // =========================================================================

    /// @dev VRF random words keyed by dailyIdx.
    ///      0 means "not yet recorded" (no request fulfilled for that day).
    ///      Historical words enable verifiable replay of past randomness.
    ///
    ///      SECURITY: Immutable once written; provides audit trail for RNG.
    mapping(uint48 => uint256) internal rngWordByDay;

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
    // Daily Jackpot Resume State
    // =========================================================================

    /// @dev Resume cursor within the current daily jackpot bucket (winner index).
    ///      0 = start of bucket, >0 = resume at this winner index.
    uint16 internal dailyEthWinnerCursor;

    /// @dev Carryover ETH pool reserved after daily phase 0 completes.
    ///      Stored to avoid re-deducting the future pool across split calls.
    uint256 internal dailyCarryoverEthPool;

    /// @dev Remaining winner cap for carryover buckets (DAILY_ETH_MAX_WINNERS - daily winners).
    uint16 internal dailyCarryoverWinnerCap;

    // =========================================================================
    // Ticket Queue Helpers
    // =========================================================================

    /// @notice Emitted when traits are generated for a player's ticket batch.
    ///         Records the exact parameters needed to replay trait generation off-chain.
    event TraitsGenerated(
        address indexed player,
        uint24 indexed level,
        uint32 queueIdx,
        uint32 startIndex,
        uint32 count,
        uint256 entropy
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

    /// @dev Queues whole tickets for a buyer at a target level.
    ///      If buyer has no existing tickets at that level, adds them to the queue.
    ///      Caps at uint32 max to prevent overflow.
    /// @param buyer Address to receive tickets.
    /// @param targetLevel Level for which tickets are queued.
    /// @param quantity Number of tickets to queue.
    function _queueTickets(
        address buyer,
        uint24 targetLevel,
        uint32 quantity
    ) internal {
        if (quantity == 0) return;
        emit TicketsQueued(buyer, targetLevel, quantity);
        uint24 wk = _tqWriteKey(targetLevel);
        uint40 packed = ticketsOwedPacked[wk][buyer];
        uint32 owed = uint32(packed >> 8);
        uint8 rem = uint8(packed);
        if (owed == 0 && rem == 0) {
            ticketQueue[wk].push(buyer);
        }
        uint256 newOwed;
        unchecked {
            newOwed = uint256(owed) + quantity;
        }
        if (newOwed > type(uint32).max) {
            newOwed = type(uint32).max;
        }
        if (newOwed != owed) {
            ticketsOwedPacked[wk][buyer] =
                (uint40(uint32(newOwed)) << 8) |
                uint40(rem);
        }
    }

    /// @dev Queues scaled tickets (with 2 decimal places) for fractional ticket purchases.
    ///      Handles remainder accumulation and promotes to whole tickets when remainder >= TICKET_SCALE.
    /// @param buyer Address to receive tickets.
    /// @param targetLevel Level for which tickets are queued.
    /// @param quantityScaled Scaled ticket amount (multiply by 100 for whole tickets).
    function _queueTicketsScaled(
        address buyer,
        uint24 targetLevel,
        uint32 quantityScaled
    ) internal {
        if (quantityScaled == 0) return;
        emit TicketsQueuedScaled(buyer, targetLevel, quantityScaled);
        uint24 wk = _tqWriteKey(targetLevel);
        uint40 packed = ticketsOwedPacked[wk][buyer];
        uint32 owed = uint32(packed >> 8);
        uint8 rem = uint8(packed);
        if (owed == 0 && rem == 0) {
            ticketQueue[wk].push(buyer);
        }

        uint32 whole = uint32(uint256(quantityScaled) / TICKET_SCALE);
        uint8 frac = uint8(uint256(quantityScaled) % TICKET_SCALE);
        if (whole != 0) {
            uint256 newOwed;
            unchecked {
                newOwed = uint256(owed) + whole;
            }
            if (newOwed > type(uint32).max) {
                newOwed = type(uint32).max;
            }
            if (newOwed != owed) {
                owed = uint32(newOwed);
            }
        }

        if (frac != 0) {
            uint16 newRem;
            unchecked {
                newRem = uint16(rem) + uint16(frac);
            }
            if (newRem >= TICKET_SCALE) {
                if (owed < type(uint32).max) {
                    unchecked {
                        owed += 1;
                    }
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
        uint32 ticketsPerLevel
    ) internal {
        emit TicketsQueuedRange(buyer, startLevel, numLevels, ticketsPerLevel);
        uint24 lvl = startLevel;
        for (uint24 i = 0; i < numLevels; ) {
            uint24 wk = _tqWriteKey(lvl);
            uint40 packed = ticketsOwedPacked[wk][buyer];
            uint32 owed = uint32(packed >> 8);
            uint8 rem = uint8(packed);
            if (owed == 0 && rem == 0) {
                ticketQueue[wk].push(buyer);
            }
            uint256 newOwed;
            unchecked {
                newOwed = uint256(owed) + ticketsPerLevel;
            }
            if (newOwed > type(uint32).max) {
                newOwed = type(uint32).max;
            }
            if (newOwed != owed) {
                ticketsOwedPacked[wk][buyer] =
                    (uint40(uint32(newOwed)) << 8) |
                    uint40(rem);
            }

            unchecked {
                ++lvl;
                ++i;
            }
        }
    }

    /// @dev Queues lootbox tickets with 2-decimal precision (remainder rolled at assignment).
    /// @param buyer Address to receive tickets.
    /// @param targetLevel Level for which tickets are queued.
    /// @param quantityScaled Scaled ticket amount (multiply by 100 for whole tickets).
    function _queueLootboxTickets(
        address buyer,
        uint24 targetLevel,
        uint256 quantityScaled
    ) internal {
        if (quantityScaled == 0) return;
        if (quantityScaled > type(uint32).max) {
            quantityScaled = type(uint32).max;
        }
        _queueTicketsScaled(buyer, targetLevel, uint32(quantityScaled));
    }

    // =========================================================================
    // Packed Prize Pool Helpers
    // =========================================================================

    function _setPrizePools(uint128 next, uint128 future) internal {
        prizePoolsPacked = uint256(future) << 128 | uint256(next);
    }

    function _getPrizePools() internal view returns (uint128 next, uint128 future) {
        uint256 packed = prizePoolsPacked;
        next = uint128(packed);
        future = uint128(packed >> 128);
    }

    function _setPendingPools(uint128 next, uint128 future) internal {
        prizePoolPendingPacked = uint256(future) << 128 | uint256(next);
    }

    function _getPendingPools() internal view returns (uint128 next, uint128 future) {
        uint256 packed = prizePoolPendingPacked;
        next = uint128(packed);
        future = uint128(packed >> 128);
    }

    // =========================================================================
    // Ticket Queue Key Encoding
    // =========================================================================

    /// @dev Compute the ticket queue key for the write slot.
    ///      Slot 0 uses raw level, slot 1 sets bit 23.
    function _tqWriteKey(uint24 level) internal view returns (uint24) {
        return ticketWriteSlot != 0 ? level | TICKET_SLOT_BIT : level;
    }

    /// @dev Compute the ticket queue key for the read slot (opposite of write).
    function _tqReadKey(uint24 level) internal view returns (uint24) {
        return ticketWriteSlot == 0 ? level | TICKET_SLOT_BIT : level;
    }

    // =========================================================================
    // Queue Swap and Prize Pool Freeze
    // =========================================================================

    /// @dev Swap the active ticket queue buffer. Reverts if read slot is not drained.
    ///      Resets ticketsFullyProcessed to false for the new read slot.
    function _swapTicketSlot(uint24 purchaseLevel) internal {
        uint24 rk = _tqReadKey(purchaseLevel);
        if (ticketQueue[rk].length != 0) revert E();
        ticketWriteSlot ^= 1;
        ticketsFullyProcessed = false;
    }

    /// @dev Swap queue buffer AND activate prize pool freeze (daily RNG path only).
    ///      If not already frozen, zeros pending accumulators.
    ///      If already frozen (jackpot phase), accumulators keep growing.
    function _swapAndFreeze(uint24 purchaseLevel) internal {
        _swapTicketSlot(purchaseLevel);
        if (!prizePoolFrozen) {
            prizePoolFrozen = true;
            prizePoolPendingPacked = 0;
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
    // Loot Box State & Presale Toggle
    // =========================================================================

    /// @dev Loot box ETH per RNG index per player (amount may accumulate within an index).
    ///      Packed: [232 bits: amount] [24 bits: purchase level]
    ///      Purchase level locked at buy time - if you open late, you lose it.
    mapping(uint48 => mapping(address => uint256)) internal lootboxEth;

    /// @dev Presale mode toggle (starts true, one-way: can only be turned off).
    ///      When true: loot boxes give 62% bonus BURNIE, presale lootbox splits active.
    ///      When false: normal loot box rewards.
    ///      Auto-ends at the first phase transition where 200 ETH mint-lootbox cap is met or level >= 3.
    bool internal lootboxPresaleActive = true;

    /// @dev Total ETH spent on lootboxes across all players and indices.
    uint256 internal lootboxEthTotal;

    /// @dev Total ETH allocated to lootboxes from regular mints only (excludes pass lootboxes).
    ///      Used to trigger presale auto-end at 200 ETH cap.
    uint256 internal lootboxPresaleMintEth;

    // =========================================================================
    // Game Over State
    // =========================================================================

    /// @dev Timestamp when game over was triggered (0 if game is still active).
    ///      Used to enforce 1-month delay before final vault sweep.
    uint48 internal gameOverTime;

    /// @dev True once the final gameover jackpot has been paid out.
    ///      Prevents duplicate payouts of the gameover prize pool.
    bool internal gameOverFinalJackpotPaid;

    /// @dev True once the 30-day post-gameover final sweep has executed.
    ///      All remaining funds (including unclaimed winnings) are forfeited.
    bool internal finalSwept;

    // =========================================================================
    // Whale Pass Claims (Deferred >5 ETH lootboxes)
    // =========================================================================

    /// @dev Pending whale pass claims from large lootbox wins (>5 ETH).
    ///      Stores number of half whale passes (100 tickets each = 50 levels × 2 tickets).
    ///      Unified storage for all deferred lootbox rewards (BAF, jackpot, decimator).
    mapping(address => uint256) internal whalePassClaims;

    // =========================================================================
    // Coinflip Boon (Lootbox Bonus)
    // =========================================================================

    // Coinflip boon tiers are stored in coinflipBoonBps (5%/10%/25%).
    // Awarded randomly from lootboxes (2%/0.5%/0.1% per ETH by tier).
    // Consumed on next coinflip: adds bps to stake (max 5k/10k/25k BURNIE).
    // EXPIRES: Must be used within 2 days (172800 seconds) of award.
    //
    // SECURITY: Single-use consumable; prevents stacking/hoarding.
    // Expiration prevents indefinite storage.

    /// @dev Day index when coinflip boon was awarded (per player).
    ///      Used to enforce 2-day expiration window (expires at jackpot reset).
    mapping(address => uint48) internal coinflipBoonDay;

    // =========================================================================
    // Lootbox Boost Boons
    // =========================================================================

    /// @dev Lootbox 5% boost boon active flag per player (simple on/off).
    ///      Awarded randomly from lootboxes (2% chance per ETH spent).
    ///      Consumed on next lootbox: adds 5% to lootbox value (max 10 ETH lootbox).
    ///      EXPIRES: Must be used within 2 days (172800 seconds) of award.
    ///
    ///      SECURITY: Single-use consumable; prevents stacking/hoarding.
    ///      Simple boolean prevents accumulation.
    mapping(address => bool) internal lootboxBoon5Active;

    /// @dev Day index when lootbox 5% boost boon was awarded (per player).
    ///      Used to enforce 2-day expiration window (expires at jackpot reset).
    mapping(address => uint48) internal lootboxBoon5Day;

    /// @dev Lootbox 15% boost boon active flag per player (simple on/off).
    ///      Awarded randomly from lootboxes (0.5% chance per ETH spent).
    ///      Consumed on next lootbox: adds 15% to lootbox value (max 10 ETH lootbox).
    ///      EXPIRES: Must be used within 2 days (172800 seconds) of award.
    ///
    ///      SECURITY: Single-use consumable; prevents stacking/hoarding.
    ///      Simple boolean prevents accumulation.
    mapping(address => bool) internal lootboxBoon15Active;

    /// @dev Day index when lootbox 15% boost boon was awarded (per player).
    ///      Used to enforce 2-day expiration window (expires at jackpot reset).
    mapping(address => uint48) internal lootboxBoon15Day;

    /// @dev Lootbox 25% boost boon active flag per player (simple on/off).
    ///      Awarded randomly from lootboxes (0.1% chance per ETH spent).
    ///      Consumed on next lootbox: adds 25% to lootbox value (max 10 ETH lootbox).
    ///      EXPIRES: Must be used within 2 days (172800 seconds) of award.
    ///
    ///      SECURITY: Single-use consumable; prevents stacking/hoarding.
    ///      Simple boolean prevents accumulation.
    mapping(address => bool) internal lootboxBoon25Active;

    /// @dev Day index when lootbox 25% boost boon was awarded (per player).
    ///      Used to enforce 2-day expiration window (expires at jackpot reset).
    mapping(address => uint48) internal lootboxBoon25Day;

    // =========================================================================
    // Whale Bundle Boon
    // =========================================================================

    /// @dev Day when whale bundle boon was awarded (per player).
    ///      Allows purchasing 100-level whale bundle at any level with tiered discount.
    ///      EXPIRES: Must be used within 4 days of award (cleared on use or expiry).
    mapping(address => uint48) internal whaleBoonDay;

    /// @dev Discount tier (in BPS) for whale bundle boon (per player).
    ///      Set when boon is awarded: 1000 = 10%, 2500 = 25%, 5000 = 50%.
    mapping(address => uint16) internal whaleBoonDiscountBps;

    // =========================================================================
    // Activity Boons (Mint/Quest Streak Boosts)
    // =========================================================================

    /// @dev Pending activity boon bonus levels per player.
    ///      Applied on lootbox open via game call; expires if not opened within 2 days.
    mapping(address => uint24) internal activityBoonPending;

    /// @dev Day index when activity boon was last assigned (per player).
    ///      Used to enforce 2-day expiration window (expires at jackpot reset).
    mapping(address => uint48) internal activityBoonDay;

    // =========================================================================
    // Auto-Rebuy + afKing Mode (Packed)
    // =========================================================================

    /// @dev Packed auto-rebuy/afKing state per player to reduce SLOADs.
    ///      takeProfit is in wei for ETH auto-rebuy (0 = rebuy all).
    ///      Note: coinflip auto-rebuy take profit amounts are stored in BurnieCoinflip.
    struct AutoRebuyState {
        /// @dev ETH amount to take profit before auto-rebuy (wei). 0 = rebuy all winnings.
        uint128 takeProfit;
        /// @dev Level at which afKing mode was activated. Used for lock period calculation. Reset to 0 when deactivated.
        uint24 afKingActivatedLevel;
        /// @dev True if auto-rebuy is enabled for this player.
        bool autoRebuyEnabled;
        /// @dev True if afKing mode is active (enhanced auto-rebuy with lock period).
        bool afKingMode;
    }

    /// @dev Auto-rebuy toggle and afKing mode state (packed into one slot per player).
    ///      When auto-rebuy is enabled, the remainder (after reserving take profit)
    ///      is converted to tickets for next level or next+1 (50/50) during jackpot
    ///      award flow. ETH goes to next prize pool for next-level tickets or to
    ///      future prize pool for next+1 tickets, and tickets are queued per level.
    mapping(address => AutoRebuyState) internal autoRebuyState;

    /// @dev Decimator auto-rebuy toggle (true = disabled). Default is enabled (false).
    mapping(address => bool) internal decimatorAutoRebuyDisabled;

    // =========================================================================
    // Purchase / Burn Boosts (One-Off)
    // =========================================================================

    /// @dev Purchase boost basis points (5%/15%/25%), one-time, time-limited.
    mapping(address => uint16) internal purchaseBoostBps;

    /// @dev Day index when purchase boost was awarded (expires at jackpot reset).
    mapping(address => uint48) internal purchaseBoostDay;

    /// @dev Decimator burn boost basis points (10%/25%/50%), one-time, no expiry.
    mapping(address => uint16) internal decimatorBoostBps;

    /// @dev Coinflip boon boost basis points (5%/10%/25%), one-time, time-limited.
    mapping(address => uint16) internal coinflipBoonBps;

    // =========================================================================
    // Daily Jackpot Trait Tracking (Coin Jackpot Reuse)
    // =========================================================================

    /// @dev Winning traits for the last daily/early jackpot (packed uint32, 8 bits per trait).
    uint32 internal lastDailyJackpotWinningTraits;

    /// @dev Level for which lastDailyJackpotWinningTraits was computed.
    uint24 internal lastDailyJackpotLevel;

    /// @dev Day index for lastDailyJackpotWinningTraits.
    uint48 internal lastDailyJackpotDay;

    /// @dev Base (pre-boost) lootbox ETH per RNG index per player.
    ///      Tracks unboosted amounts so boosts apply at purchase time, not open time.
    mapping(uint48 => mapping(address => uint256)) internal lootboxEthBase;

    // =========================================================================
    // Operator Approvals
    // =========================================================================

    /// @dev owner => operator => approved (game-wide delegated control).
    mapping(address => mapping(address => bool)) internal operatorApprovals;

    // =========================================================================
    // ETH Perk Burn Tracking
    // =========================================================================

    /// @dev Level associated with the current ETH perk burn counter.
    uint24 internal ethPerkLevel;

    /// @dev Count of ETH perk tokens burned this level.
    uint16 internal ethPerkBurnCount;

    /// @dev Level associated with the current BURNIE perk burn counter.
    uint24 internal burniePerkLevel;

    /// @dev Count of BURNIE perk tokens burned this level.
    uint16 internal burniePerkBurnCount;

    /// @dev Level associated with the current DGNRS perk burn counter.
    uint24 internal dgnrsPerkLevel;

    /// @dev Count of DGNRS perk tokens burned this level.
    uint16 internal dgnrsPerkBurnCount;

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
    // Special Perk Expected Count
    // =========================================================================

    /// @dev Expected special perk burn count for the current level (1% of purchase count).
    uint24 internal perkExpectedCount;

    // =========================================================================
    // Deity Pass (Perma Whale) Grants
    // =========================================================================

    /// @dev Count of deity passes per player (0 or 1).
    mapping(address => uint16) internal deityPassCount;

    /// @dev Count of deity passes purchased (excludes grants).
    mapping(address => uint16) internal deityPassPurchasedCount;

    /// @dev Total ETH paid per buyer for deity passes.
    mapping(address => uint256) internal deityPassPaidTotal;

    /// @dev List of deity pass owners for iteration.
    address[] internal deityPassOwners;

    /// @dev Symbol assigned to each deity pass holder (0-31). 0 is valid (Bitcoin).
    mapping(address => uint8) internal deityPassSymbol;

    /// @dev Reverse lookup: symbol ID (0-31) → current owner address.
    mapping(uint8 => address) internal deityBySymbol;

    // =========================================================================
    // DGNRS Earlybird Rewards
    // =========================================================================

    /// @dev Initial earlybird pool balance snapshot (set on first payout).
    uint256 internal earlybirdDgnrsPoolStart;

    /// @dev Total purchase ETH counted toward earlybird emission.
    uint256 internal earlybirdEthIn;

    // =========================================================================
    // Internal Helpers
    // =========================================================================

    /// @dev Awards earlybird DGNRS tokens to buyers during early levels (< EARLYBIRD_END_LEVEL).
    ///      Uses a quadratic emission curve that decreases rewards as more ETH is spent.
    ///      No-op if buyer is zero address, purchaseWei is 0, or earlybird target is reached.
    /// @param buyer Address to receive DGNRS tokens.
    /// @param purchaseWei ETH amount spent on this purchase.
    /// @param currentLevel Current game level (must be < EARLYBIRD_END_LEVEL for rewards).
    function _awardEarlybirdDgnrs(
        address buyer,
        uint256 purchaseWei,
        uint24 currentLevel
    ) internal {
        if (purchaseWei == 0) return;
        if (buyer == address(0)) return;
        if (currentLevel >= EARLYBIRD_END_LEVEL) {
            // One-shot: dump remaining earlybird pool into lootbox pool
            if (earlybirdDgnrsPoolStart != type(uint256).max) {
                earlybirdDgnrsPoolStart = type(uint256).max;
                IStakedDegenerusStonk dgnrsContract = IStakedDegenerusStonk(
                    ContractAddresses.SDGNRS
                );
                uint256 earlybirdRemaining = dgnrsContract.poolBalance(
                    IStakedDegenerusStonk.Pool.Earlybird
                );
                if (earlybirdRemaining != 0) {
                    dgnrsContract.transferBetweenPools(
                        IStakedDegenerusStonk.Pool.Earlybird,
                        IStakedDegenerusStonk.Pool.Lootbox,
                        earlybirdRemaining
                    );
                }
            }
            return;
        }

        uint256 poolStart = earlybirdDgnrsPoolStart;
        if (poolStart == 0) {
            uint256 poolBalance = IStakedDegenerusStonk(ContractAddresses.SDGNRS)
                .poolBalance(IStakedDegenerusStonk.Pool.Earlybird);
            if (poolBalance == 0) return;
            poolStart = poolBalance;
            earlybirdDgnrsPoolStart = poolBalance;
        }

        uint256 totalEth = EARLYBIRD_TARGET_ETH;
        uint256 ethIn = earlybirdEthIn;
        if (ethIn >= totalEth) return;

        uint256 remaining = totalEth - ethIn;
        uint256 delta = purchaseWei > remaining ? remaining : purchaseWei;
        if (delta == 0) return;

        uint256 nextEthIn = ethIn + delta;
        uint256 denom = totalEth * totalEth;
        uint256 totalEth2 = totalEth * 2;
        uint256 d1 = (ethIn * totalEth2) - (ethIn * ethIn);
        uint256 d2 = (nextEthIn * totalEth2) - (nextEthIn * nextEthIn);
        uint256 payout = (poolStart * (d2 - d1)) / denom;

        earlybirdEthIn = nextEthIn;
        if (payout == 0) return;

        IStakedDegenerusStonk(ContractAddresses.SDGNRS).transferFromPool(
            IStakedDegenerusStonk.Pool.Earlybird,
            buyer,
            payout
        );
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

        uint32 day = _currentMintDay();
        data = _setMintDay(
            data,
            day,
            BitPackingLib.DAY_SHIFT,
            BitPackingLib.MASK_32
        );

        mintPacked_[player] = data;

        _queueTicketRange(player, ticketStartLevel, 10, ticketsPerLevel);
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

        uint32 day = _currentMintDay();
        data = _setMintDay(
            data,
            day,
            BitPackingLib.DAY_SHIFT,
            BitPackingLib.MASK_32
        );
        mintPacked_[player] = data;
    }

    /// @dev Returns the current day index.
    function _simulatedDayIndex() internal view returns (uint48) {
        return GameTimeLib.currentDayIndex();
    }

    /// @dev Returns the day index for a specific timestamp.
    function _simulatedDayIndexAt(uint48 ts) internal pure returns (uint48) {
        return GameTimeLib.currentDayIndexAt(ts);
    }

    /// @dev Gets the current mint day from dailyIdx or calculates from timestamp.
    function _currentMintDay() internal view returns (uint32) {
        uint48 day = dailyIdx;
        if (day == 0) {
            day = _simulatedDayIndex();
        }
        return uint32(day);
    }

    /// @dev Updates the day field in packed mint data if changed.
    function _setMintDay(
        uint256 data,
        uint32 day,
        uint256 dayShift,
        uint256 dayMask
    ) internal pure returns (uint256) {
        uint32 prevDay = uint32((data >> dayShift) & dayMask);
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
    // Lootbox RNG Indexing
    // =========================================================================

    /// @dev Current lootbox RNG index for new purchases (1-based).
    uint48 internal lootboxRngIndex = 1;

    /// @dev Accumulated lootbox ETH toward the RNG request threshold.
    uint256 internal lootboxRngPendingEth;

    /// @dev ETH threshold that triggers a lootbox RNG request (wei).
    uint256 internal lootboxRngThreshold =
        1 ether;

    /// @dev Minimum LINK balance required to allow manual lootbox RNG rolls.
    ///      Defaults to ~2 weeks of daily VRF (assumes ~1 LINK/day).
    uint256 internal lootboxRngMinLinkBalance = 14 ether;

    /// @dev RNG words keyed by lootbox RNG index.
    mapping(uint48 => uint256) internal lootboxRngWordByIndex;

    /// @dev VRF requestId => lootbox RNG index mapping.
    ///      Index is 1-based; 0 means "not a lootbox RNG request".
    mapping(uint256 => uint48) internal lootboxRngRequestIndexById;

    /// @dev Lootbox purchase day per RNG index and player.
    mapping(uint48 => mapping(address => uint48)) internal lootboxDay;

    /// @dev Lootbox base level at purchase time, packed as (level + 1).
    ///      0 means no lootbox purchased at this index.
    mapping(uint48 => mapping(address => uint24))
        internal lootboxBaseLevelPacked;

    /// @dev Lootbox activity score at purchase time, packed as (score + 1).
    ///      0 means no activity score recorded.
    mapping(uint48 => mapping(address => uint16)) internal lootboxEvScorePacked;

    /// @dev Per-player queue of lootbox RNG indices for auto-open processing.
    mapping(address => uint48[]) internal lootboxIndexQueue;

    // =========================================================================
    // Lootbox Bonus Tracking & BURNIE Lootboxes
    // =========================================================================

    /// @dev BURNIE lootbox amounts keyed by lootbox RNG index and player.
    mapping(uint48 => mapping(address => uint256)) internal lootboxBurnie;

    /// @dev Refundable deity pass ETH per buyer before level 1 starts.
    mapping(address => uint256) internal deityPassRefundable;

    // =========================================================================
    // Lootbox Module Storage (for delegatecall modules)
    // =========================================================================

    /// @dev Total pending BURNIE lootbox amount for manual RNG trigger threshold.
    uint256 internal lootboxRngPendingBurnie;

    /// @dev Last resolved lootbox RNG word — always a real VRF value after first daily advance.
    ///      Set by _finalizeLootboxRng (daily) and advanceGame mid-day path (from lootboxRngWordByIndex).
    ///      Used by processTicketBatch for trait-assignment entropy.
    uint256 internal lastLootboxRngWord;

    /// @dev True when requestLootboxRng swapped the ticket buffer and mid-day ticket
    ///      processing is pending. Cleared by advanceGame after tickets are fully drained.
    bool internal midDayTicketRngPending;

    // =========================================================================
    // Deity Boon Tracking
    // =========================================================================

    /// @dev Day when deity's boon slots were assigned.
    mapping(address => uint48) internal deityBoonDay;

    /// @dev Bitmask of used slots for the current day (bit i = slot i used).
    mapping(address => uint8) internal deityBoonUsedMask;

    /// @dev Day when recipient last received a deity boon (prevents double-receipt).
    mapping(address => uint48) internal deityBoonRecipientDay;

    /// @dev Day when deity-granted coinflip boon was issued.
    mapping(address => uint48) internal deityCoinflipBoonDay;

    /// @dev Day when deity-granted 5% lootbox boost was issued.
    mapping(address => uint48) internal deityLootboxBoon5Day;

    /// @dev Day when deity-granted 15% lootbox boost was issued.
    mapping(address => uint48) internal deityLootboxBoon15Day;

    /// @dev Day when deity-granted 25% lootbox boost was issued.
    mapping(address => uint48) internal deityLootboxBoon25Day;

    /// @dev Day when deity-granted purchase boost was issued.
    mapping(address => uint48) internal deityPurchaseBoostDay;

    /// @dev Day when deity-granted decimator boost was issued.
    mapping(address => uint48) internal deityDecimatorBoostDay;

    /// @dev Day when deity-granted whale boon was issued.
    mapping(address => uint48) internal deityWhaleBoonDay;

    /// @dev Day when deity-granted activity boon was issued.
    mapping(address => uint48) internal deityActivityBoonDay;

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
    // Deity Pass Purchase Boon (Lootbox Reward)
    // =========================================================================

    /// @dev Deity pass purchase boon tier per player.
    ///      0 = none, 1 = 10% discount, 2 = 25% discount, 3 = 50% discount.
    ///      Awarded randomly from lootboxes; extremely rare.
    mapping(address => uint8) internal deityPassBoonTier;

    /// @dev Day index when deity pass boon was awarded (4-day expiry for lootbox-rolled).
    mapping(address => uint48) internal deityPassBoonDay;

    /// @dev Day when deity-granted deity pass boon was issued (1-day expiry).
    mapping(address => uint48) internal deityDeityPassBoonDay;

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
    // Lazy Pass Boon State
    // =========================================================================

    /// @dev Day when lazy pass boon was awarded.
    ///      Allows discounted lazy pass purchase for 4 days.
    mapping(address => uint48) internal lazyPassBoonDay;
    /// @dev Lazy pass boon discount in BPS (1000/2500/5000).
    mapping(address => uint16) internal lazyPassBoonDiscountBps;
    /// @dev Deity-sourced day index (expires when day changes). 0 for lootbox-sourced boons.
    mapping(address => uint48) internal deityLazyPassBoonDay;

    // =========================================================================
    // Degenerette Hero Wager Tracking (Daily)
    // =========================================================================

    /// @dev Daily hero symbol wagers (ETH only), indexed by day.
    ///      Key: day index (from GameTimeLib). Value: 4 packed uint256s.
    ///      Each uint256 packs 8 × 32-bit amounts (one per symbol in that quadrant).
    ///      Amounts stored in units of 1e12 wei (0.000001 ETH) to fit 32 bits
    ///      (max ~4,295 ETH per symbol per day).
    mapping(uint48 => uint256[4]) internal dailyHeroWagers;

    // =========================================================================
    // Degenerette Per-Player Per-Level ETH Wagered
    // =========================================================================

    /// @dev Total ETH wagered on degenerette per player per level (in wei).
    mapping(address => mapping(uint24 => uint256))
        internal playerDegeneretteEthWagered;

    /// @dev Top degenerette player per level.
    ///      Packed: [96 bits: amount in 1e12 units] [160 bits: address]
    mapping(uint24 => uint256) internal topDegeneretteByLevel;

    // =========================================================================
    // Distress-Mode Lootbox Tracking
    // =========================================================================

    /// @dev ETH portion of a lootbox purchased during distress mode (final 6 hours
    ///      before gameover liveness guard). Used at open time to apply a 25% ticket
    ///      bonus proportional to the distress fraction of the total lootbox value.
    mapping(uint48 => mapping(address => uint256)) internal lootboxDistressEth;

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

    /// @dev The x00 level the centuryBonusUsed mapping applies to.
    ///      When targetLevel differs, all per-player values are stale (treated as 0).
    uint24 internal centuryBonusLevel;

    /// @dev Bonus entries awarded per player at the current x00 level.
    ///      Used to enforce the 10 ETH cap across multiple purchases.
    mapping(address => uint256) internal centuryBonusUsed;

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

    /// @dev Per-player terminal decimator entry. Packed into a single 256-bit slot (232/256 bits).
    ///      totalBurn: pre-time-multiplier cumulative burn (capped at DECIMATOR_MULTIPLIER_CAP).
    ///      weightedBurn: post-time-multiplier cumulative burn (used for claim share calculation).
    ///      bucket: bucket denominator (2-12), computed from activity score using lvl 100 rules.
    ///      subBucket: deterministic from keccak256(player, level, bucket).
    ///      burnLevel: which level this entry belongs to (stale detection for lazy reset).
    struct TerminalDecEntry {
        uint80  totalBurn;
        uint88  weightedBurn;
        uint8   bucket;
        uint8   subBucket;
        uint48  burnLevel;
    }
    mapping(address => TerminalDecEntry) internal terminalDecEntries;

    /// @dev Per-bucket aggregates for terminal decimator.
    ///      Key: keccak256(abi.encode(level, denom, subBucket)) -> total weighted burn.
    mapping(bytes32 => uint256) internal terminalDecBucketBurnTotal;

    /// @dev Resolution snapshot for terminal decimator claims (set at GAMEOVER).
    ///      Packed into a single 256-bit slot (248/256 bits).
    ///      No rngWord needed — claims are 100% ETH post-GAMEOVER (auto-rebuy skipped).
    struct TerminalDecClaimRound {
        uint24  lvl;
        uint96  poolWei;
        uint128 totalBurn;
    }
    TerminalDecClaimRound internal lastTerminalDecClaimRound;
}
