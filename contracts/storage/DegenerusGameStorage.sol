// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ContractAddresses} from "../ContractAddresses.sol";
import {IVRFCoordinator} from "../interfaces/IVRFCoordinator.sol";
import {IDegenerusStonk} from "../interfaces/IDegenerusStonk.sol";

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
 * | SLOT 0 (32 bytes) — Timing, Batching, FSM                                   |
 * +-----------------------------------------------------------------------------+
 * | [0:6]   levelStartTime           uint48   Timestamp when level opened       |
 * | [6:12]  dailyIdx                 uint48   Monotonic day counter             |
 * | [12:18] rngRequestTime           uint48   When last VRF request was fired   |
 * | [18:22] (unused)                 uint32   Previously airdropTicketsProcessedCount |
 * | [22:26] (unused)                 uint32   Previously airdropIndex           |
 * | [26:29] level                    uint24   Current game level (1-indexed)    |
 * | [29:31] lastExterminatedTrait    uint16   Last level's exterminated trait (420=sentinel) |
 * | [31:32] gameState                uint8    FSM: 1-3,86 (setup/purc/burn/gameover) |
 * +-----------------------------------------------------------------------------+
 *   Total: 6+6+6+4+4+3+2+1 = 32 bytes ✓ (perfectly packed)
 *
 * +-----------------------------------------------------------------------------+
 * | SLOT 1 (32 bytes) — Cursors, Counters, Boolean Flags                        |
 * +-----------------------------------------------------------------------------+
 * | [0:4]   traitRebuildCursor       uint32   Cursor for trait count reseeding  |
 * | [4:8]   airdropMultiplier        uint32   Bonus multiplier (scaled)         |
 * | [8:9]   jackpotCounter           uint8    Jackpots processed this level     |
 * | [9:10]  earlyBurnPercent         uint8    Previous pool % in early burn     |
 * | [10:11] levelJackpotPaid         bool     Level jackpot executed flag       |
 * | [11:12] lastPurchaseDay          bool     Prize target met flag             |
 * | [12:13] decWindowOpen            bool     Decimator window latch            |
 * | [13:14] rngLockedFlag            bool     Waiting for VRF fulfillment       |
 * | [14:15] rngFulfilled             bool     VRF lifecycle tracker             |
 * | [15:16] traitCountsSeedQueued    bool     Initial traits staged flag        |
 * | [16:17] decimatorHundredReady    bool     Level %100 special primed         |
 * | [17:18] exterminationInvertFlag  bool     Exterminator bonus inversion      |
 * | [18:19] ticketJackpotType        uint8    0=none, 1=daily, 2=purchase       |
 * | [19:20] lastLevelJackpotCount    uint8    Jackpots processed last level     |
 * | [20:21] endgameJackpotPhase      uint8    Current endgame jackpot phase     |
 * | [21:32] <padding>                         11 bytes unused                   |
 * +-----------------------------------------------------------------------------+
 *   Total: 4+4+13 = 21 bytes (11 bytes padding)
 *
 * +-----------------------------------------------------------------------------+
 * | SLOT 2 (32 bytes) — Price                                                   |
 * +-----------------------------------------------------------------------------+
 * | [0:16]  price                    uint128  Current mint price in wei         |
 * | [16:32] <padding>                         16 bytes unused                   |
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
 *    - levelStartTime = type(uint48).max (sentinel: game not started)
 *    - lastExterminatedTrait = 420 (sentinel: no trait exterminated last level)
 *    - gameState = 1 (initialized to SETUP state)
 *    - decWindowOpen = true (decimator window starts open)
 *    - rngFulfilled = true (no pending request at deploy)
 *    - price = 0.025 ether (initial mint price)
 *    - lastPrizePool = 125 ether (bootstrap value for % calculations)
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
    /// @dev Scale for fractional ticket purchases (2 decimals).
    uint256 internal constant TICKET_SCALE = 100;
    uint8 internal constant GAME_STATE_SETUP = 1;
    uint8 internal constant GAME_STATE_PURCHASE = 2;
    uint8 internal constant GAME_STATE_BURN = 3;
    uint8 internal constant GAME_STATE_GAMEOVER = 86;
    uint256 internal constant LOOTBOX_CLAIM_THRESHOLD = 5 ether;
    uint24 internal constant EARLYBIRD_END_LEVEL = 3;
    uint256 internal constant EARLYBIRD_TARGET_ETH =
        1_000 ether / ContractAddresses.COST_DIVISOR;
    /// @dev Packed daily jackpot remaining-based BPS values (16 bits each, idx 0..9).
    ///      Values: 526, 666, 833, 1038, 1304, 1666, 2200, 3076, 4444, 10000.
    ///      Apply to currentPrizePool each day; last day pays 100% of remaining.
    uint256 internal constant DAILY_JACKPOT_BPS_PACKED =
        uint256(526)
        | (uint256(666) << 16)
        | (uint256(833) << 32)
        | (uint256(1038) << 48)
        | (uint256(1304) << 64)
        | (uint256(1666) << 80)
        | (uint256(2200) << 96)
        | (uint256(3076) << 112)
        | (uint256(4444) << 128)
        | (uint256(10000) << 144);

    // =========================================================================
    // SLOT 0: Level Timing, Batching, and Finite State Machine
    // =========================================================================
    // These variables pack into a single 32-byte storage slot for gas efficiency.
    // Order matters: EVM packs from low to high within a slot.

    /// @dev Timestamp when the current level opened for purchase phase.
    ///      Initialized to uint48.max as a sentinel indicating "game not started".
    ///      Used for inactivity guard timing and purchase-phase 3-day ETH jackpots.
    ///
    ///      SECURITY: uint48 holds timestamps until year 8.9 million — safe for any
    ///      realistic game lifetime. Overflow is not a concern.
    uint48 internal levelStartTime = type(uint48).max;

    /// @dev Monotonically increasing "day" counter derived from block timestamps.
    ///      Incremented during game progression; used to key RNG words and track
    ///      daily jackpot eligibility. NOT tied to calendar days — it's game-relative.
    ///
    ///      SECURITY: uint48 allows ~281 trillion increments — effectively unlimited.
    uint48 internal dailyIdx;

    /// @dev Timestamp when the last VRF (Chainlink) request was submitted.
    ///      Used for timeout detection: if rngRequestTime + timeout < now and
    ///      rngLockedFlag is still true, the game can recover via fallback RNG.
    ///
    ///      SECURITY: Timeout mechanism prevents permanent lockup if VRF fails.
    uint48 internal rngRequestTime;

    /// @dev [REMOVED] Previously airdropTicketsProcessedCount - immediate ticket system removed.
    ///      Now using unified ticket system (ticketQueue/ticketsOwed).
    // uint32 internal airdropTicketsProcessedCount;

    /// @dev [REMOVED] Previously airdropIndex - immediate ticket system removed.
    ///      Now using unified ticket system (ticketQueue/ticketsOwed).
    // uint32 internal airdropIndex;

    /// @dev Current game level (1-indexed). Levels progress through purchase and
    ///      burn phases, with jackpots at various milestones.
    ///
    ///      PUBLIC: Exposed for frontend/analytics. Read-only externally.
    ///
    ///      SECURITY: uint24 supports ~16M levels — game would take millennia
    ///      to overflow at realistic progression rates.
    uint24 public level = 1;

    /// @dev The last level's exterminated trait ID.
    ///      420 is a sentinel value meaning "no extermination last level".
    ///      Valid trait IDs are 0-255, so 420 is unambiguously a sentinel.
    ///
    ///      DESIGN: Easter egg reference (420). Functional as a clear sentinel.
    uint16 internal lastExterminatedTrait = 420;

    /// @dev Finite State Machine for game phases:
    ///      1 = setup (awaiting start or between major phases)
    ///      2 = purchase (mint/airdrop phase; purchases always allowed)
    ///      3 = burn window (extermination phase)
    ///      86 = game over (terminal)
    ///
    ///      PUBLIC: Exposed for frontend state queries.
    ///
    ///      SECURITY: State transitions are guarded by modifiers in DegenerusGame.
    ///      Invalid state transitions revert, preventing exploitation.
    uint8 public gameState = GAME_STATE_SETUP;

    // =========================================================================
    // SLOT 1: Cursors, Counters, and Boolean Flags
    // =========================================================================
    // Boolean flags pack efficiently (1 byte each in EVM). Total: 21 bytes used (11 bytes padding).

    /// @dev Progress cursor for reseeding trait counts at level start.
    ///      Used in batched trait initialization to avoid gas limits.
    uint32 internal traitRebuildCursor;

    /// @dev Airdrop bonus multiplier (scaled integer representation).
    ///      Applied during ticket award calculations for promotional events.
    uint32 internal airdropMultiplier;

    /// @dev Count of jackpots processed within the current level.
    ///      Capped at 10 (JACKPOT_LEVEL_CAP in JackpotModule); triggers level
    ///      advancement when reached. Reset at level start.
    ///
    ///      SECURITY: uint8 is sufficient (max 255, only need 0-10).
    uint8 internal jackpotCounter;

    /// @dev Percentage of previous prize pool carried into early burn reward.
    ///      Range 0-255 (but practically 0-100%). Used for early burn bonus
    ///      calculations in the jackpot module.
    uint8 internal earlyBurnPercent;

    /// @dev True once the level jackpot has been executed for the
    ///      current purchase phase. Prevents double-payment.
    ///
    ///      SECURITY: Critical for jackpot integrity. Reset at level transition.
    bool internal levelJackpotPaid;

    /// @dev True once the level jackpot lootbox distribution has been executed.
    ///      Used for phased execution: lootbox first, then ETH.
    ///      Reset at level transition along with levelJackpotPaid.
    bool internal levelJackpotLootboxPaid;

    /// @dev True once the prize target is met for current level.
    ///      When true, next tick skips normal daily/jackpot prep and proceeds
    ///      to burn window. Allows early level completion on high activity.
    bool internal lastPurchaseDay;

    /// @dev Latch to hold decimator window open until RNG is requested.
    ///      Set true at level start; cleared when decimator phase begins.
    ///      Default true ensures first decimator window is properly gated.
    bool internal decWindowOpen = true;

    /// @dev True while waiting for VRF (Chainlink) fulfillment.
    ///      Prevents duplicate RNG requests and gates state transitions
    ///      that depend on randomness.
    ///
    ///      SECURITY: Critical for RNG integrity. Prevents re-entrancy
    ///      attacks on RNG-dependent operations.
    bool internal rngLockedFlag;

    /// @dev Tracks VRF lifecycle; true when no pending request exists.
    ///      Default true because at deploy, no request is outstanding.
    ///      Set false when requesting, true when fulfilled.
    ///
    ///      SECURITY: Works with rngLockedFlag to ensure RNG consistency.
    bool internal rngFulfilled = true;

    /// @dev True if initial trait counts were staged and await overwrite.
    ///      Used during level initialization to handle batched seeding.
    bool internal traitCountsSeedQueued;

    /// @dev True when level % 100 decimator special is primed and ready.
    ///      Milestone levels (100, 200, etc.) have special decimator rewards.
    bool internal decimatorHundredReady;

    /// @dev Toggles inversion of exterminator bonus on certain levels.
    ///      Adds variety to extermination mechanics across levels.
    bool internal exterminationInvertFlag;

    /// @dev Unified ticket jackpot pending type. Daily and purchase ticket jackpots are
    ///      mutually exclusive, so a single enum tracks which (if any) is queued:
    ///      0 = none, 1 = daily, 2 = purchase.
    ///      Timeout is computed on-the-fly from jackpotCounter >= JACKPOT_LEVEL_CAP.
    uint8 internal ticketJackpotType;

    /// @dev Snapshot of how many daily jackpots ran in the level that just ended.
    ///      Kept for analytics/future scheduling decisions.
    uint8 internal lastLevelJackpotCount;

    /// @dev Current phase of endgame jackpot processing (State 1).
    ///      Allows splitting multiple jackpots across separate transactions to avoid gas limits.
    ///      0 = complete/not started
    ///      1 = extermination settlement (exterminator + jackpot + purchase rewards, ~8M gas)
    ///      2 = reward jackpot (BAF or Decimator, bounded <16M)
    ///      3 = carryover jackpot (ETH + lootbox for next level, ~13M gas)
    ///      Reset to 0 when transitioning out of State 1.
    uint8 internal endgameJackpotPhase;

    // =========================================================================
    // SLOT 2: Mint Price
    // =========================================================================

    /// @dev Current price to mint one gamepiece, in wei.
    ///      uint128 supports up to ~340 undecillion wei (~3.4e20 ETH) — far
    ///      beyond any realistic price point.
    ///
    ///      Default 0.025 ether = 25 finney = initial launch price.
    ///
    ///      SECURITY: Price updates are game-controlled. uint128 prevents
    ///      overflow in multiplication with reasonable quantities.
    uint128 internal price =
        uint128(0.025 ether / ContractAddresses.COST_DIVISOR);

    // =========================================================================
    // SLOTS 3+: Full-Width Balances and Pools
    // =========================================================================
    // Each uint256 occupies its own 32-byte slot. These track ETH/token flows.

    /// @dev Prize pool snapshot from the previous level.
    ///      Used as denominator for early burn percentage calculations.
    ///      Bootstrap value of 125 ether (divided by COST_DIVISOR on testnet) ensures non-zero denominator at launch.
    ///
    ///      SECURITY: Never zero after initialization, preventing division by zero.
    uint256 internal lastPrizePool = 125 ether / ContractAddresses.COST_DIVISOR;

    /// @dev Active prize pool for the current level.
    ///      Accumulated from mint fees and distributed via jackpots.
    uint256 internal currentPrizePool;

    /// @dev Pre-funded prize pool for the next level.
    ///      Allows carryover mechanics and smooth level transitions.
    uint256 internal nextPrizePool;

    /// @dev [DEPRECATED] Legacy reward pool slot (kept for storage layout stability).
    ///      Unified reserve now tracked in futurePrizePool.
    uint256 internal rewardPool;

    /// @dev Snapshot of the daily ETH pool at level start (informational only).
    ///      Daily jackpots now scale off currentPrizePool each day.
    uint256 internal dailyJackpotBase;

    /// @dev Reserved pool for the level-100 decimator special reward.
    ///      Accumulated separately to ensure milestone payouts are funded.
    uint256 internal decimatorHundredPool;

    /// @dev Reserved pool for the BAF (Burn and Flip?) 100-level special.
    ///      Similar to decimatorHundredPool for a different milestone reward.
    uint256 internal bafHundredPool;

    /// @dev Latest VRF random word, or 0 if a request is pending.
    ///      Written by VRF callback; consumed by game logic for randomness.
    ///
    ///      SECURITY: 0 indicates pending state. Game logic checks rngFulfilled
    ///      flag rather than checking for non-zero to avoid edge cases.
    uint256 internal rngWordCurrent;

    /// @dev Last VRF request ID, used to match fulfillment callbacks.
    ///      Prevents processing stale or mismatched VRF responses.
    ///
    ///      SECURITY: Request ID matching prevents replay attacks on RNG.
    uint256 internal vrfRequestId;

    /// @dev Number of reverse flips purchased against current RNG word.
    ///      Tracks flip activity for jackpot sizing adjustments.
    uint256 internal totalFlipReversals;

    // =========================================================================
    // Minting and Airdrop Queues
    // =========================================================================

    /// @dev [REMOVED] Previously pendingTicketMints - immediate ticket system removed.
    ///      Now using unified ticket system: all tickets queue into ticketQueue[level].
    // address[] internal pendingTicketMints;

    /// @dev [REMOVED] Previously playerTicketMintsOwed - immediate ticket system removed.
    ///      Now using unified ticket system: ticketsOwed[level][player].
    // mapping(address => uint32) internal playerTicketMintsOwed;

    /// @dev Per-level exterminator addresses (key = level).
    ///      Records who performed the final extermination for each level.
    ///      Used for cosmetic/trophy purposes.
    mapping(uint24 => address) internal levelExterminators;

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
    ///      SECURITY: Array growth bounded by total gamepiece supply per level.
    mapping(uint24 => address[][256]) internal traitBurnTicket;

    /// @dev Per-day trait hit counters used for jackpot trait selection.
    ///      Index layout: [0-7] symbols, [8-15] colors, [16-79] combined traits.
    ///      80 elements * 4 bytes = 320 bytes = 10 storage slots (packed).
    ///
    ///      SECURITY: Fixed-size array prevents unbounded growth.
    ///      uint32 per counter supports ~4B burns per trait per day.
    uint32[80] internal dailyBurnCount;

    /// @dev Remaining supply per trait ID (0-255).
    ///      Decremented on burns; used for extermination detection.
    ///      256 elements * 4 bytes = 1024 bytes = 32 storage slots (packed).
    ///
    ///      SECURITY: Fixed-size, bounded by initial supply seeding.
    uint32[256] internal traitRemaining;

    /// @dev Supply per trait ID at burn phase start.
    ///      Snapshot taken at mint→burn transition; used to calculate
    ///      purchase vs burn ticket splits for jackpot fairness.
    ///
    ///      SECURITY: Snapshot prevents manipulation during burn phase.
    uint32[256] internal traitStartRemaining;

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

    /// @dev The first VRF word ever received (set once, never changed).
    ///      Used as ultimate fallback for gameover entropy if VRF is totally broken
    ///      and no historical rngWordByDay entries exist. Prevents falling back to
    ///      exploitable blockhash/prevrandao.
    ///
    ///      SECURITY: VRF-derived randomness is cryptographically secure. This ensures
    ///      we always have at least one secure random seed, even in catastrophic VRF failure.
    uint256 internal firstEverRngWord;

    // =========================================================================
    // Coinflip Statistics (Last Purchase Day)
    // =========================================================================

    /// @dev Total coinflip deposits during lastPurchaseDay = true (current level).
    ///      Used to adjust coinflip payout based on flip activity.
    uint256 internal lastPurchaseDayFlipTotal;

    /// @dev Previous level's lastPurchaseDay coinflip deposits.
    ///      Compared with current to detect activity trends for payout tuning.
    uint256 internal lastPurchaseDayFlipTotalPrev;

    /// @dev Winning traits for level jackpot, stored for phased execution.
    ///      Packed uint32 format: [trait3|trait2|trait1|trait0] (4 bytes).
    ///      Set during lootbox phase, used during ETH phase.
    uint32 internal levelJackpotWinningTraits;

    /// @dev ETH pool for level jackpot after lootbox budget deduction.
    ///      Stored during lootbox phase, used during ETH distribution phase.
    uint256 internal levelJackpotEthPool;

    /// @dev Ticket units for the pending ticket jackpot (slot 1).
    ///      For daily: units for current-level draw.
    ///      For purchase: the only units slot used.
    ///      Units are computed at scheduling time to avoid price drift.
    uint256 internal ticketJackpotUnits1;

    /// @dev Ticket units for the pending ticket jackpot (slot 2).
    ///      For daily: units for carryover (next-level) draw.
    ///      For purchase: unused (remains 0).
    uint256 internal ticketJackpotUnits2;

    // =========================================================================
    // Future Mint Awards
    // =========================================================================

    /// @dev Unified reserve pool (formerly "future + reward").
    ///      Funds jackpots, carryover, and time-based level splits.
    uint256 internal futurePrizePool;

    /// @dev Last level that drew down the future prize pool.
    uint24 internal futurePoolLastLevel;

    /// @dev Queue of players with tickets (purchase/burn/gamepiece sources) per level.
    ///      All tickets (purchases, lootbox rewards, etc.) queue here.
    ///
    ///      PROCESSING SCHEDULE:
    ///      - Current level tickets: Processed continuously during advanceGame (each call)
    ///      - Next level tickets: Activated at END of purchase phase (before level jackpot)
    ///
    ///      EXAMPLE (Level 5 purchase phase):
    ///      - lvlOffset=0 → ticketQueue[5] → Processed continuously throughout level 5
    ///      - lvlOffset=1 → ticketQueue[6] → Activated at end of purchase phase (before level jackpot)
    ///
    ///      This allows lootbox tickets to participate in early-bird jackpots at burn phase start.
    mapping(uint24 => address[]) internal ticketQueue;

    /// @dev Owed tickets per level per player (whole tickets only).
    ///      Fractional remainders are tracked in ticketsOwedFrac.
    mapping(uint24 => mapping(address => uint32)) internal ticketsOwed;
    /// @dev Fractional ticket remainder (0-99) per level per player.
    mapping(uint24 => mapping(address => uint8)) internal ticketsOwedFrac;

    /// @dev Cursor and level for processing ticket queues.
    ///      Tracks progress through ticketQueue during batch processing.
    uint32 internal ticketCursor;
    uint24 internal ticketLevel;

    /// @dev Cursor for multi-level ticket processing at level transitions.
    ///      Tracks which near-future level (0-3) is currently being processed.
    ///      0 = not in multi-level processing, 1-4 = processing level offset.
    uint8 internal nearFutureLevelCursor;

    // =========================================================================
    // Ticket Queue Helpers
    // =========================================================================

    function _effectiveTicketLevel(uint24 targetLevel) internal view returns (uint24) {
        if (gameState == GAME_STATE_BURN && targetLevel == level) {
            if (level + 1 == 100) {
                return targetLevel;
            }
            unchecked {
                return level + 1;
            }
        }
        return targetLevel;
    }

    function _queueTickets(address buyer, uint24 targetLevel, uint32 quantity) internal {
        uint24 effectiveLevel = _effectiveTicketLevel(targetLevel);
        uint32 owed = ticketsOwed[effectiveLevel][buyer];
        uint8 rem = ticketsOwedFrac[effectiveLevel][buyer];
        if (owed == 0 && rem == 0) {
            ticketQueue[effectiveLevel].push(buyer);
        }
        uint256 newOwed = uint256(owed) + quantity;
        if (newOwed > type(uint32).max) {
            newOwed = type(uint32).max;
        }
        ticketsOwed[effectiveLevel][buyer] = uint32(newOwed);
    }

    /// @dev Queue scaled tickets (2 decimals) for fractional ticket purchases.
    function _queueTicketsScaled(address buyer, uint24 targetLevel, uint32 quantityScaled) internal {
        if (quantityScaled == 0) return;
        uint24 effectiveLevel = _effectiveTicketLevel(targetLevel);
        uint32 owed = ticketsOwed[effectiveLevel][buyer];
        uint8 rem = ticketsOwedFrac[effectiveLevel][buyer];
        if (owed == 0 && rem == 0) {
            ticketQueue[effectiveLevel].push(buyer);
        }

        uint32 whole = uint32(uint256(quantityScaled) / TICKET_SCALE);
        uint8 frac = uint8(uint256(quantityScaled) % TICKET_SCALE);
        if (whole != 0) {
            uint256 newOwed = uint256(owed) + whole;
            if (newOwed > type(uint32).max) {
                newOwed = type(uint32).max;
            }
            owed = uint32(newOwed);
            ticketsOwed[effectiveLevel][buyer] = owed;
        }

        if (frac != 0) {
            uint16 newRem = uint16(rem) + uint16(frac);
            if (newRem >= TICKET_SCALE) {
                if (owed < type(uint32).max) {
                    unchecked {
                        owed += 1;
                    }
                    ticketsOwed[effectiveLevel][buyer] = owed;
                }
                newRem -= uint16(TICKET_SCALE);
            }
            ticketsOwedFrac[effectiveLevel][buyer] = uint8(newRem);
        }
    }

    /// @dev Queue tickets for a contiguous range of levels with same quantity per level.
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
        uint24 lvl = startLevel;
        for (uint24 i = 0; i < numLevels; ) {
            uint24 effectiveLevel = _effectiveTicketLevel(lvl);
            uint32 owed = ticketsOwed[effectiveLevel][buyer];
            uint8 rem = ticketsOwedFrac[effectiveLevel][buyer];
            if (owed == 0 && rem == 0) {
                ticketQueue[effectiveLevel].push(buyer);
            }
            uint256 newOwed = uint256(owed) + ticketsPerLevel;
            if (newOwed > type(uint32).max) {
                newOwed = type(uint32).max;
            }
            ticketsOwed[effectiveLevel][buyer] = uint32(newOwed);

            unchecked {
                ++lvl;
                ++i;
            }
        }
    }

    function _queueLootboxTickets(
        address buyer,
        uint24 targetLevel,
        uint256 fullTickets,
        uint256 remainder,
        uint256 targetPrice,
        uint256 remainderEntropy
    ) internal {
        if (fullTickets != 0 && fullTickets <= type(uint32).max) {
            _queueTickets(buyer, targetLevel, uint32(fullTickets));
        }
        if (remainder != 0 && remainderEntropy % targetPrice < remainder) {
            _queueTickets(buyer, targetLevel, 1);
        }
    }

    /// @dev Award tickets immediately as jackpot draw entries using RNG to assign traits.
    ///      Used for lootbox tickets for near-future levels (+0 to +4) with limit of 100 for gas.
    /// @param player Address receiving the tickets.
    /// @param targetLevel Level for the tickets.
    /// @param quantity Number of tickets to award.
    /// @param entropy RNG seed from lootbox.
    /// @param currentLvl Current game level for range checking.
    /// @return success True if tickets were awarded immediately, false if should queue instead.
    function _awardImmediateTickets(
        address player,
        uint24 targetLevel,
        uint32 quantity,
        uint256 entropy,
        uint24 currentLvl
    ) internal returns (bool success) {
        // Only award immediately for near-future levels (+0 to +4) and reasonable quantity
        if (quantity == 0 || quantity > 100) {
            return false;
        }

        // Check if targetLevel is within +0 to +4 range
        if (targetLevel < currentLvl || targetLevel > currentLvl + 4) {
            return false;
        }

        // Use RNG to assign each ticket to a random trait
        for (uint32 i = 0; i < quantity; ) {
            entropy = uint256(keccak256(abi.encode(entropy, i)));
            uint8 traitId = uint8(entropy % 256);
            traitBurnTicket[targetLevel][traitId].push(player);
            unchecked {
                ++i;
            }
        }

        return true;
    }

    // =========================================================================
    // Loot Box State & Presale Toggle
    // =========================================================================

    /// @dev Loot box ETH per RNG index per player (amount may accumulate within an index).
    ///      Packed: [232 bits: amount] [24 bits: purchase level]
    ///      Purchase level locked at buy time - if you open late, you lose it.
    mapping(uint48 => mapping(address => uint256)) internal lootboxEth;

    /// @dev True if the loot box for a given RNG index was purchased during presale mode.
    ///      Loot boxes opened from presale purchases give 2x BURNIE rewards.
    mapping(uint48 => mapping(address => bool)) internal lootboxPresale;

    /// @dev Presale mode toggle (starts true, one-way: can only be turned off).
    ///      When true: loot boxes give 2x BURNIE, bonusFlip mode is active.
    ///      When false: normal loot box rewards, bonusFlip mode disabled.
    ///      Auto-ends when purchase phase ends (gameState → BURN) or via admin toggle.
    bool internal lootboxPresaleActive = true;

    /// @dev Total ETH spent on lootboxes.
    uint256 internal lootboxEthTotal;

    // =========================================================================
    // Game Over State
    // =========================================================================

    /// @dev Timestamp when game over was triggered (0 if game is still active).
    ///      Used to enforce 1-month delay before final vault sweep.
    uint48 internal gameOverTime;

    /// @dev True once the final gameover jackpot has been paid out.
    ///      Prevents duplicate payouts of the gameover prize pool.
    bool internal gameOverFinalJackpotPaid;

    // =========================================================================
    // Whale Pass Claims (Deferred >5 ETH lootboxes)
    // =========================================================================

    /// @dev Pending whale pass claims from large lootbox wins (>5 ETH).
    ///      Stores number of half whale passes (100 tickets each = 50 levels × 2 tickets).
    ///      Remainder roll done at award time using VRF RNG for security.
    ///      Unified storage for all deferred lootbox rewards (BAF, jackpot, decimator).
    mapping(address => uint256) internal whalePassClaims;

    // =========================================================================
    // Coinflip Boon (Lootbox Bonus)
    // =========================================================================

    /// @dev Coinflip boon tiers stored in coinflipBoonBps (5%/10%/25%).
    ///      Awarded randomly from lootboxes (2%/0.5%/0.1% per ETH by tier).
    ///      Consumed on next coinflip: adds bps to stake (max 5k/10k/25k BURNIE).
    ///      EXPIRES: Must be used within 2 days (172800 seconds) of award.
    ///
    ///      SECURITY: Single-use consumable; prevents stacking/hoarding.
    ///      Expiration prevents indefinite storage.
    ///      coinflipBoonActive is deprecated; retained for storage layout only.
    mapping(address => bool) internal coinflipBoonActive;

    /// @dev Timestamp when coinflip boon was awarded (per player).
    ///      Used to enforce 2-day expiration window.
    ///      If block.timestamp > coinflipBoonTimestamp + 2 days, boon is expired.
    mapping(address => uint48) internal coinflipBoonTimestamp;

    // =========================================================================
    // Burn Boon (Lootbox Bonus)
    // =========================================================================

    /// @dev Burn boon active flag per player (simple on/off).
    ///      Awarded randomly from lootboxes (1% chance per ETH spent).
    ///      Consumed on next gamepiece burn: adds 100 BURNIE bonus to burn reward.
    ///      EXPIRES: Valid only until the end of the level in which it was awarded.
    ///
    ///      SECURITY: Single-use consumable; prevents stacking/hoarding.
    ///      Simple boolean prevents accumulation.
    ///      Level-based expiration ensures timely usage.
    mapping(address => bool) internal burnBoonActive;

    /// @dev Level when burn boon was awarded (per player).
    ///      Used to enforce end-of-level expiration.
    ///      If current level > burnBoonLevel, boon is expired.
    mapping(address => uint24) internal burnBoonLevel;

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

    /// @dev Timestamp when lootbox 5% boost boon was awarded (per player).
    ///      Used to enforce 2-day expiration window.
    mapping(address => uint48) internal lootboxBoon5Timestamp;

    /// @dev Lootbox 15% boost boon active flag per player (simple on/off).
    ///      Awarded randomly from lootboxes (0.5% chance per ETH spent).
    ///      Consumed on next lootbox: adds 15% to lootbox value (max 10 ETH lootbox).
    ///      EXPIRES: Must be used within 2 days (172800 seconds) of award.
    ///
    ///      SECURITY: Single-use consumable; prevents stacking/hoarding.
    ///      Simple boolean prevents accumulation.
    mapping(address => bool) internal lootboxBoon15Active;

    /// @dev Timestamp when lootbox 15% boost boon was awarded (per player).
    ///      Used to enforce 2-day expiration window.
    mapping(address => uint48) internal lootboxBoon15Timestamp;

    // =========================================================================
    // Whale Bundle Boon
    // =========================================================================

    /// @dev Day when whale bundle boon was awarded (per player).
    ///      Allows purchasing 100-level whale bundle at any level with 10% discount.
    ///      EXPIRES: Must be used within 4 days of award (cleared on use or expiry).
    mapping(address => uint48) internal whaleBoonDay;

    // =========================================================================
    // Activity Boons (Mint/Quest Streak Boosts)
    // =========================================================================

    /// @dev Pending activity boon bonus levels per player.
    ///      Applied on open via game call; expires if not opened within 2 days.
    mapping(address => uint24) internal activityBoonPending;

    /// @dev Timestamp when activity boon was last assigned (per player).
    ///      Used to enforce 2-day expiration window.
    mapping(address => uint48) internal activityBoonTimestamp;

    // =========================================================================
    // Auto-Rebuy Toggle
    // =========================================================================

    /// @dev Auto-rebuy toggle mapping: true = auto-convert winnings to tickets.
    ///      When enabled, the remainder (after reserving keep-multiples) is
    ///      converted to tickets for the next level during jackpot award flow.
    ///      ETH goes to nextPrizePool, tickets to ticketsOwed[level][player].
    ///      Applies fixed 30% bonus for gas efficiency.
    mapping(address => bool) internal autoRebuyEnabled;

    // =========================================================================
    // afKing Mode (Auto-Mode with Activity Bonus)
    // =========================================================================

    /// @dev afKing mode active flag per player.
    ///      Requires: autoRebuyEnabled = true, autoFlipEnabled = true,
    ///                claimable balance >= 2 ETH, BURNIE balance >= 50k,
    ///                active lazy pass (10 or 100 level).
    ///      Benefit: +2% activity score per level (max 50% at 25 levels).
    ///      Deactivates if: auto mode disabled, lazy pass expires, or manual deactivation.
    ///      Does NOT deactivate from claiming threshold amounts.
    mapping(address => bool) internal afKingMode;

    /// @dev Level at which player activated afKing mode.
    ///      Used to calculate how many consecutive levels player has been in afKing mode.
    ///      Reset to 0 when afKing mode is deactivated.
    mapping(address => uint24) internal afKingActivatedLevel;

    /// @dev Auto-flip toggle: true = auto-flip coinflips on loss.
    ///      Part of afKing mode requirements.
    ///      When enabled, losing coinflips automatically retry with same stake (up to configured limit).
    mapping(address => bool) internal autoFlipEnabled;

    // =========================================================================
    // Purchase / Burn Boosts (One-Off)
    // =========================================================================

    /// @dev Gamepiece purchase boost (5%/15%/25%), one-time, time-limited.
    mapping(address => uint16) internal gamepieceBoostBps;
    /// @dev Timestamp when gamepiece boost was awarded.
    mapping(address => uint48) internal gamepieceBoostTimestamp;

    /// @dev Ticket purchase boost (5%/15%/25%), one-time, time-limited.
    mapping(address => uint16) internal ticketBoostBps;
    /// @dev Timestamp when ticket boost was awarded.
    mapping(address => uint48) internal ticketBoostTimestamp;

    /// @dev Decimator burn boost (10%/25%/50%), one-time, no expiry.
    mapping(address => uint16) internal decimatorBoostBps;

    /// @dev Coinflip boon boost basis points (5%/10%/25%), one-time, time-limited.
    mapping(address => uint16) internal coinflipBoonBps;

    // =========================================================================
    // Current-Level Extermination Tracking
    // =========================================================================

    /// @dev Current level's exterminated trait ID (0-255) or 420 sentinel if none yet.
    uint16 internal currentExterminatedTrait = 420;

    /// @dev True once the exterminator payout has been processed for the current level.
    bool internal exterminationPaidThisLevel;

    // =========================================================================
    // Daily Jackpot Trait Tracking (Coin Jackpot Reuse)
    // =========================================================================

    /// @dev Winning traits for the last daily/early jackpot (packed uint32).
    uint32 internal lastDailyJackpotWinningTraits;

    /// @dev Level for which lastDailyJackpotWinningTraits was computed.
    uint24 internal lastDailyJackpotLevel;

    /// @dev Day index for lastDailyJackpotWinningTraits.
    uint48 internal lastDailyJackpotDay;

    // =========================================================================
    // Auto-Rebuy Config (ETH)
    // =========================================================================

    /// @dev Auto-rebuy keep multiple for ETH winnings (wei).
    ///      If set, complete multiples remain claimable; remainder is auto-rebought.
    mapping(address => uint256) internal autoRebuyKeepMultiple;

    /// @dev Base (pre-boost) lootbox ETH per RNG index per player.
    ///      Tracks unboosted amounts so boosts apply at purchase time, not open time.
    mapping(uint48 => mapping(address => uint256)) internal lootboxEthBase;

    // =========================================================================
    // Operator Approvals
    // =========================================================================

    /// @dev owner => operator => approved (game-wide delegated control).
    mapping(address => mapping(address => bool)) internal operatorApprovals;

    // =========================================================================
    // ETH Perk Burn Tracking (Special Gamepieces)
    // =========================================================================

    /// @dev Level associated with the current ETH perk burn counter.
    uint24 internal ethPerkLevel;

    /// @dev Count of ETH perk gamepieces burned this level (pre-extermination only).
    uint16 internal ethPerkBurnCount;

    /// @dev Level associated with the current BURNIE perk burn counter.
    uint24 internal burniePerkLevel;

    /// @dev Count of BURNIE perk gamepieces burned this level (pre-extermination only).
    uint16 internal burniePerkBurnCount;

    /// @dev Level associated with the current DGNRS perk burn counter.
    uint24 internal dgnrsPerkLevel;

    /// @dev Count of DGNRS perk gamepieces burned this level (pre-extermination only).
    uint16 internal dgnrsPerkBurnCount;

    /// @dev Tribute address for orange-king burns (0 = disabled).
    address internal tributeAddress =
        0x5be9a4959308A0D0c7bC0870E319314d8D957dBB;

    // =========================================================================
    // Affiliate DGNRS Claims
    // =========================================================================

    /// @dev Per-level prize pool snapshot used for affiliate DGNRS weighting.
    mapping(uint24 => uint256) internal affiliateDgnrsPrizePool;

    /// @dev Per-level per-affiliate claim tracking (true if claimed).
    mapping(uint24 => mapping(address => bool)) internal affiliateDgnrsClaimedBy;

    // =========================================================================
    // Special Perk Expected Count
    // =========================================================================

    /// @dev Deprecated: previously tracked the level for perkExpectedCount.
    uint24 internal perkExpectedLevel;

    /// @dev Expected special perk burn count for the current level (1% of purchase count).
    uint16 internal perkExpectedCount;

    /// @dev Deprecated: previously stored total gamepieces expected for the current level.
    uint32 internal levelMintedCount;

    // =========================================================================
    // Purchase Phase Timing
    // =========================================================================

    /// @dev Timestamp when the purchase target was first reached for the level.
    ///      Used for time-based pool splitting at level start.
    uint48 internal purchaseTargetReachedTime;

    // =========================================================================
    // Deity Pass (Perma Whale) Grants
    // =========================================================================

    /// @dev Count of deity (perma whale) passes per player.
    ///      Each pass grants 4 tickets per level for a rolling 100-level window.
    mapping(address => uint16) internal deityPassCount;

    /// @dev List of deity pass owners for auto-refresh processing.
    address[] internal deityPassOwners;

    /// @dev Giftable 10-level whale bundle credits granted by deity passes.
    mapping(address => uint16) internal whaleBundle10PassCredits;

    /// @dev Next level to top up for deity pass refresh (0 = no refresh pending).
    uint24 internal deityPassRefreshStartLevel;

    /// @dev Cursor into deityPassOwners for batched refresh processing.
    uint32 internal deityPassRefreshOwnerCursor;

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

    function _awardEarlybirdDgnrs(address buyer, uint256 purchaseWei) internal {
        if (purchaseWei == 0) return;
        if (buyer == address(0)) return;
        if (level >= EARLYBIRD_END_LEVEL) return;

        uint256 poolStart = earlybirdDgnrsPoolStart;
        if (poolStart == 0) {
            uint256 poolBalance = IDegenerusStonk(ContractAddresses.DGNRS).poolBalance(
                IDegenerusStonk.Pool.Earlybird
            );
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

        IDegenerusStonk(ContractAddresses.DGNRS).transferFromPool(
            IDegenerusStonk.Pool.Earlybird,
            buyer,
            payout
        );
    }

    // =========================================================================
    // VRF Configuration (moved from DegenerusGame for module access)
    // =========================================================================

    /// @notice Chainlink VRF V2.5 coordinator contract.
    /// @dev Mutable for emergency rotation; see updateVrfCoordinatorAndSub().
    IVRFCoordinator internal vrfCoordinator;

    /// @notice VRF key hash identifying the oracle and gas lane.
    /// @dev Rotatable with coordinator; determines gas price tier.
    bytes32 internal vrfKeyHash;

    /// @notice VRF subscription ID for LINK billing.
    /// @dev Mutable to allow subscription rotation without redeploying.
    uint256 internal vrfSubscriptionId;

    // =========================================================================
    // Lootbox RNG Indexing
    // =========================================================================

    /// @dev Current lootbox RNG index for new purchases (1-based).
    uint48 internal lootboxRngIndex = 1;

    /// @dev Accumulated lootbox ETH toward the RNG request threshold.
    uint256 internal lootboxRngPendingEth;

    /// @dev ETH threshold that triggers a lootbox RNG request (wei).
    uint256 internal lootboxRngThreshold = 1 ether / ContractAddresses.COST_DIVISOR;

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

    /// @dev Per-player queue of lootbox RNG indices for auto-open processing.
    mapping(address => uint48[]) internal lootboxIndexQueue;

    /// @dev Cursor into lootboxIndexQueue for auto-open processing.
    mapping(address => uint32) internal lootboxIndexCursor;

    // =========================================================================
    // Lootbox Bonus Tracking & BURNIE Lootboxes
    // =========================================================================

    /// @dev Per-level lootbox bonus cap usage (ETH amount eligible for activity bonus).
    mapping(uint24 => mapping(address => uint128)) internal lootboxBonusUsed;

    /// @dev BURNIE lootbox amounts keyed by lootbox RNG index and player.
    mapping(uint48 => mapping(address => uint256)) internal lootboxBurnie;

    /// @dev Tracks whether the top affiliate reward has been paid for a level.
    mapping(uint24 => bool) internal affiliateTopRewardPaid;

    /// @dev Escrowed ETH from deity pass purchases before level 1 starts.
    uint256 internal deityPassEscrow;

    /// @dev Refundable deity pass ETH per buyer before level 1 starts.
    mapping(address => uint256) internal deityPassRefundable;
}
