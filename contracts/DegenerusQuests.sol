// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import "./interfaces/IDegenerusQuests.sol";
import "./interfaces/IDegenerusGame.sol";
import {ICoinflip} from "./interfaces/ICoinflip.sol";
import {ContractAddresses} from "./ContractAddresses.sol";

/**
 * @title DegenerusQuests
 * @author Burnie Degenerus
 * @notice Tracks two rotating daily quests and validates player progress against Degenerus game actions.
 *
 * @dev Architecture Overview
 * -----------------------------------------------------------------------------
 * This contract operates as an external standalone contract (NOT delegatecall)
 * called by the Degenerus ContractAddresses.COIN contract. It manages:
 *   1. Daily quest rolling using VRF entropy
 *   2. Per-player progress tracking with day-gated resets
 *   3. Streak accounting with fixed rewards/targets
 *
 * Security Model
 * -----------------------------------------------------------------------------
 * • All player-action handlers are ContractAddresses.COIN-gated via `onlyCoin` modifier
 * • Quest normalization allows ContractAddresses.COIN OR game to trigger via `onlyCoinOrGame`
 * • Game address fixed at deploy time
 * • No external calls to untrusted contracts — only reads trusted `questGame`
 * • No ETH handling or callbacks — reentrancy is not a concern
 *
 * Quest Lifecycle
 * -----------------------------------------------------------------------------
 * 1. Coin calls `rollDailyQuest()` with VRF entropy at day transition
 * 2. Slot 0 is always a fixed "deposit new ETH" quest (mint with ETH)
 * 3. Slot 1 is a weighted-random quest from the remaining quest types
 * 4. Player actions trigger handle* functions (handleMint, handleFlip, etc.)
 * 5. Progress accumulates until target is met; each completion (primary, secondary, level) credits streak
 *
 * Progress Freshness
 * -----------------------------------------------------------------------------
 * Player progress is tagged with the day it was recorded; when that day no longer
 * matches the active quest day, stale progress is reset via `_questSyncProgress`.
 * Because a slot is only ever re-seeded on a day change, the day tag alone is
 * sufficient — no per-player version copy is kept.
 *
 * Streak System
 * -----------------------------------------------------------------------------
 * • Every quest completion increments the streak — primary, secondary, and level
 *   quests credit independently (0.5% activity score each, uncapped)
 * • The secondary is gated behind the primary, so the missed-day reset stays keyed
 *   to the primary; while afking the funded auto-buy stands in for the primary
 * • No tiers or difficulty variance; targets are fixed
 * • Missing a day resets streak to zero
 */
contract DegenerusQuests is IDegenerusQuests {
    // =========================================================================
    //                              CUSTOM ERRORS
    // =========================================================================

    /// @notice Thrown when caller is not an authorized contract (COIN, COINFLIP, GAME, or AFFILIATE).
    error OnlyCoin();

    /// @notice Thrown when caller is not the authorized GAME contract.
    error OnlyGame();

    // =========================================================================
    //                                EVENTS
    // =========================================================================

    /// @notice Emitted when a quest slot is rolled for a new day.
    event QuestSlotRolled(
        uint24 indexed day,
        uint8 indexed slot,
        uint8 questType,
        uint8 flags,
        uint24 version
    );

    /// @notice Emitted when player quest progress is updated.
    event QuestProgressUpdated(
        address indexed player,
        uint24 indexed day,
        uint8 indexed slot,
        uint8 questType,
        uint128 progress,
        uint256 target
    );

    /// @notice Emitted when a quest slot is completed.
    event QuestCompleted(
        address indexed player,
        uint24 indexed day,
        uint8 indexed slot,
        uint8 questType,
        uint32 streak,
        uint256 reward
    );

    /// @notice Emitted when quest streak shields are consumed on missed days.
    event QuestStreakShieldUsed(
        address indexed player,
        uint16 used,
        uint16 remaining,
        uint24 currentDay
    );

    /// @notice Emitted when quest streak shields are granted (e.g. by a lootbox boon).
    event QuestStreakShieldGranted(
        address indexed player,
        uint16 amount,
        uint8 newTotal
    );

    /// @notice Emitted when quest streak is manually increased.
    event QuestStreakBonusAwarded(
        address indexed player,
        uint16 amount,
        uint24 newStreak,
        uint24 currentDay
    );

    /// @notice Emitted when quest streak resets due to missed days.
    event QuestStreakReset(
        address indexed player,
        uint24 previousStreak,
        uint24 currentDay
    );

    /// @notice Emitted when a player completes the level quest.
    event LevelQuestCompleted(
        address indexed player,
        uint24 indexed level,
        uint8 questType,
        uint256 reward
    );

    // =========================================================================
    //                              CONSTANTS
    // =========================================================================

    // -------------------------------------------------------------------------
    // Unit Conversions
    // -------------------------------------------------------------------------

    /// @dev Price unit for reward calculations (1000 FLIP).
    uint256 private constant PRICE_COIN_UNIT = 1000 ether;

    // -------------------------------------------------------------------------
    // Quest Type Constants
    // -------------------------------------------------------------------------

    /// @dev Number of concurrent quest slots per day.
    uint8 private constant QUEST_SLOT_COUNT = 2;

    /// @dev Fixed reward for the slot 0 quest.
    uint256 private constant QUEST_SLOT0_REWARD = 100 ether;

    /// @dev Fixed reward for the random (slot 1) quest.
    uint256 private constant QUEST_RANDOM_REWARD = 100 ether;

    /// @dev Milestone streak-shield grant: +1 shield each time the quest streak reaches a
    ///      new multiple of this interval (100, 200, …). Idempotent via shieldCenturyHighWater.
    uint16 private constant CENTURY_SHIELD_INTERVAL = 100;

    /// @dev Held-balance cap for the century milestone grant: the milestone path never lifts a
    ///      player's streakShield above this. Other shield sources (lootbox/deity boons) are
    ///      unaffected and keep their own uint8-saturating semantics.
    uint8 private constant CENTURY_SHIELD_MAX_HELD = 10;

    /// @dev Streak bump granted on a LEVEL quest completion. A daily quest completion advances the
    ///      quest streak by 1; finishing the harder per-level quest advances it by this amount.
    ///      Applied identically off a run (manual `state.streak`, saturating at uint16 max) and
    ///      while afking (the Sub streak base, via recordAfkingSecondary).
    uint16 private constant LEVEL_QUEST_STREAK_BONUS = 5;

    /// @dev Quest type: mint tickets using ETH.
    uint8 private constant QUEST_TYPE_MINT_ETH = 1;

    /// @dev Quest type: stake FLIP in the coinflip mechanism.
    uint8 private constant QUEST_TYPE_FLIP = 2;

    /// @dev Quest type: earn affiliate commissions.
    uint8 private constant QUEST_TYPE_AFFILIATE = 3;

    /// @dev Quest type: buy a foil pack. Forced into slot 1 on the first purchase
    ///      day of a level (rollDailyQuest forceFoil) and excluded from the random
    ///      pool everywhere else, so it only ever lands on that day.
    uint8 private constant QUEST_TYPE_FOIL = 4;

    /// @dev Quest type: participate in decimator burns.
    uint8 private constant QUEST_TYPE_DECIMATOR = 5;

    /// @dev Quest type: purchase loot boxes.
    uint8 private constant QUEST_TYPE_LOOTBOX = 6;

    /// @dev Quest type: place Degenerette bets using ETH.
    uint8 private constant QUEST_TYPE_DEGENERETTE_ETH = 7;

    /// @dev Quest type: place Degenerette bets using FLIP.
    uint8 private constant QUEST_TYPE_DEGENERETTE_FLIP = 8;

    /// @dev Quest type: mint tickets using FLIP tokens. Value 9 avoids collision
    ///      with Solidity's default mapping value (0), which signals "no quest rolled".
    uint8 private constant QUEST_TYPE_MINT_FLIP = 9;

    /// @dev Total number of quest types for iteration bounds.
    uint8 private constant QUEST_TYPE_COUNT = 10;

    // -------------------------------------------------------------------------
    // Quest Targets (fixed)
    // -------------------------------------------------------------------------

    /// @dev Fixed mint target in whole tickets (1 ticket = 1000 FLIP).
    uint32 private constant QUEST_MINT_TARGET = 1;

    /// @dev Fixed foil-pack target in whole packs (buy one foil pack).
    uint32 private constant QUEST_FOIL_TARGET = 1;

    /// @dev Fixed FLIP target for flip/affiliate/decimator quests (2x price in FLIP).
    uint256 private constant QUEST_FLIP_TARGET = 2 * PRICE_COIN_UNIT;

    /// @dev Fixed ETH multiplier for lootbox quests (2x current mint price).
    uint256 private constant QUEST_LOOTBOX_TARGET_MULTIPLIER = 2;

    /// @dev Fixed ETH multiplier for deposit quest (1x current mint price).
    uint256 private constant QUEST_DEPOSIT_ETH_TARGET_MULTIPLIER = 1;

    /// @dev Hard cap for ETH quest requirements (safeguard).
    uint256 private constant QUEST_ETH_TARGET_CAP = 0.5 ether;

    /// @dev Level boundary for special decimator quest availability.
    uint24 private constant DECIMATOR_SPECIAL_LEVEL = 100;

    // =========================================================================
    //                           IMMUTABLE ADDRESSES
    // =========================================================================

    /// @dev Reference to the Degenerus game contract for state queries.
    IDegenerusGame internal constant questGame = IDegenerusGame(ContractAddresses.GAME);

    /// @dev Reference to the coinflip contract for crediting flip stakes.
    ICoinflip internal constant coinflip = ICoinflip(ContractAddresses.COINFLIP);

    // =========================================================================
    //                                 STRUCTS
    // =========================================================================

    /**
     * @notice Definition of a quest that is active for the current day.
     * @dev In-memory working shape; both active quests are persisted together in the
     *      single packed `activeQuestsPacked` slot (64 bits per quest record).
     *
     * Record layout (low to high bits):
     * +-------------+----------+
     * | day (24b)   | type(8b) |
     * +-------------+----------+
     */
    struct DailyQuest {
        uint24 day;       // Quest day identifier (derived by caller, not block timestamp)
        uint8 questType;  // One of the QUEST_TYPE_* constants
    }

    /**
     * @notice Progress and streak bookkeeping per player.
     * @dev Stored per-player in `questPlayerState` mapping.
     *
     * Streak Mechanics:
     * - `streak` increments on every completion (primary, secondary, level credit
     *   independently; each slot is deduped to once per day by `completionMask`)
     * - `baseStreak` snapshots streak at day start for consistent view rendering
     * - `lastActiveDay` tracks slot-0 (the funded primary mint) — the reset anchor
     * - Missing a day (gap > 1 between lastActiveDay and currentDay) resets streak;
     *   suppressed while afking, where the run keeps it alive via the funded high-water
     *
     * Progress Freshness:
     * - `lastProgressDay{0,1}` must match the active quest day
     * - Mismatch triggers automatic progress reset via `_questSyncProgress`
     *
     * Completion Mask Layout:
     * +---------+---------+
     * | bit 1   | bit 0   |
     * | slot 1  | slot 0  |
     * +---------+---------+
     */
    // All fields pack into a single 32-byte slot (25 bytes used). The per-slot day and
    // progress markers are flattened from fixed arrays — Solidity reserves a fresh slot
    // per fixed array, so the arrays are what forced the old 5-slot layout. Daily progress
    // is held in a compact per-family unit (see `_progressUnit`) so it fits uint16.
    struct PlayerQuestState {
        uint24 lastCompletedDay;   // Last day the primary (slot 0) completed — reset anchor alongside lastActiveDay
        uint24 lastActiveDay;      // Last day where slot-0 (funded mint) completed
        uint24 lastSyncDay;        // Day we last reset progress/completionMask
        uint16 streak;             // Running quest-completion streak (primary + secondary + level); uint16-capped, bounded downstream by the activity-score hard cap
        uint16 baseStreak;         // Snapshot of streak at start of day (for rewards)
        bool afkingActive;         // While set (GAME-only, subscribe→finalize): slot-0 completions are streak-neutral and pay no immediate reward (the afking compute-on-read owns the primary); a secondary/level completion bumps the afking sub's streak base (recordAfkingSecondary) so the unified score reflects it
        uint24 lastProgressDay0;   // Slot 0: day when progress was recorded
        uint24 lastProgressDay1;   // Slot 1: day when progress was recorded
        uint16 progress0;          // Slot 0: accumulated progress in stored units (milli-ETH / whole-FLIP / ticket count)
        uint16 progress1;          // Slot 1: accumulated progress in stored units
        uint8 completionMask;      // Bits 0-1: per-slot completion (deduped once-per-day; every completion credits the streak)
        uint8 streakShield;        // Stackable quest-streak shields, consumed on missed days to preserve streak
        uint8 shieldCenturyHighWater; // Highest streak-century credited a milestone shield this run; re-arms down on a streak reset so a genuine re-climb re-earns, while preventing double-credit of a century already passed within the run
    }

    // =========================================================================
    //                              QUEST STORAGE
    // =========================================================================

    /// @notice Active quests for the current day, packed into a single slot.
    ///         Each quest record is 64 bits: day (24b) | questType (8b), upper record bits unused,
    ///         with slot 0 in bits 0-63 and slot 1 in bits 64-127 (upper 128 bits unused).
    ///         Read/written via `_loadActiveQuests` / `_storeActiveQuests` (one SLOAD/SSTORE per pair).
    uint256 private activeQuestsPacked;

    /// @notice Per-player quest state including progress, streak, and streak shields.
    mapping(address => PlayerQuestState) private questPlayerState;

    /// @notice Active level quest type (1-9). Zero means no quest active.
    ///         Zeroed at level transition RNG request, set when RNG arrives.
    ///         Packs with levelQuestVersion in one slot.
    uint8 private levelQuestType;

    /// @notice Version counter for level quest invalidation. Bumps on each rollLevelQuest.
    ///         Player state stores this value; mismatch resets progress + completed.
    uint8 private levelQuestVersion;

    /// @notice Per-player level quest state.
    ///         Packed: version (8b) | progress (128b) | completed (1b at bit 136).
    mapping(address => uint256) private levelQuestPlayerState;

    // =========================================================================
    //                       ACTIVE-QUEST PACK / UNPACK
    // =========================================================================

    /// @dev Materializes both active quests from the packed slot with a single SLOAD.
    function _loadActiveQuests() private view returns (DailyQuest[QUEST_SLOT_COUNT] memory quests) {
        uint256 packed = activeQuestsPacked;
        quests[0] = _unpackQuestRecord(uint64(packed));
        quests[1] = _unpackQuestRecord(uint64(packed >> 64));
    }

    /// @dev Persists both active quests into the packed slot with a single SSTORE.
    function _storeActiveQuests(DailyQuest[QUEST_SLOT_COUNT] memory quests) private {
        activeQuestsPacked =
            uint256(_packQuestRecord(quests[0])) |
            (uint256(_packQuestRecord(quests[1])) << 64);
    }

    /// @dev Decodes one 64-bit quest record: day (24b) | questType (8b).
    function _unpackQuestRecord(uint64 record) private pure returns (DailyQuest memory quest) {
        quest.day = uint24(record);
        quest.questType = uint8(record >> 24);
    }

    /// @dev Encodes one quest into its 64-bit record: day (24b) | questType (8b).
    function _packQuestRecord(DailyQuest memory quest) private pure returns (uint64) {
        return uint64(quest.day) | (uint64(quest.questType) << 24);
    }

    // =========================================================================
    //                              MODIFIERS
    // =========================================================================

    /// @dev Restricts access to authorized COIN, COINFLIP, GAME, or AFFILIATE contracts.
    modifier onlyCoin() {
        address sender = msg.sender;
        if (
            sender != ContractAddresses.COIN &&
            sender != ContractAddresses.COINFLIP &&
            sender != ContractAddresses.GAME &&
            sender != ContractAddresses.AFFILIATE
        ) revert OnlyCoin();
        _;
    }

    modifier onlyGame() {
        if (msg.sender != ContractAddresses.GAME) revert OnlyGame();
        _;
    }

    // =========================================================================
    //                            QUEST ROLLING
    // =========================================================================

    /// @notice Roll the daily quest set. Slot 0 is always MINT_ETH; slot 1 is random, except on the
    ///         first purchase day (forced FOIL) and the first jackpot day (forced MINT_FLIP).
    /// @dev Idempotent per day. Called by AdvanceModule when RNG word is available.
    /// @param day Quest day identifier.
    /// @param entropy VRF entropy word.
    /// @param forceMintFlip When true, slot 1 is MINT_FLIP (the FLIP redeem window is live this
    ///        day); when false, MINT_FLIP is excluded from the slot 1 roll so a player is never handed
    ///        a daily FLIP-mint quest they cannot complete while the window is shut.
    /// @param forceFoil When true (the first purchase day of a level), slot 1 is the buy-a-foil-pack
    ///        quest. Takes precedence over forceMintFlip; the two never coincide (opposite cycle ends).
    function rollDailyQuest(uint24 day, uint256 entropy, bool forceMintFlip, bool forceFoil)
        external
        onlyGame
    {
        DailyQuest[QUEST_SLOT_COUNT] memory quests = _loadActiveQuests();
        if (quests[0].day == day) return;

        // Slot 0: always MINT_ETH — just stamp the day
        _seedQuestType(quests[0], day, QUEST_TYPE_MINT_ETH);

        // Slot 1: FOIL forced on the first purchase day, else MINT_FLIP on the first jackpot day
        // (redeem window live), else a weighted random distinct from slot 0. Neither FOIL nor
        // MINT_FLIP is in the random pool (see _bonusQuestType), so each only lands on its forced day.
        uint8 bonusType;
        if (forceFoil) {
            bonusType = QUEST_TYPE_FOIL;
        } else if (forceMintFlip) {
            bonusType = QUEST_TYPE_MINT_FLIP;
        } else {
            uint256 bonusEntropy = (entropy >> 128) | (entropy << 128);
            bonusType = _bonusQuestType(
                bonusEntropy,
                QUEST_TYPE_MINT_ETH,
                _canRollDecimatorQuest()
            );
        }
        _seedQuestType(quests[1], day, bonusType);
        _storeActiveQuests(quests);

        // The version position carries the day tag — the freshness marker for the roll.
        emit QuestSlotRolled(day, 0, QUEST_TYPE_MINT_ETH, 0, day);
        emit QuestSlotRolled(day, 1, bonusType, 0, day);
    }

    /**
     * @notice Award quest streak bonus to a player.
     * @dev Access: GAME contract only.
     *      Does not alter per-day completion snapshots.
     *      Silently returns if player is zero address, amount is zero, or currentDay is zero.
     *      Clamps at uint24 max on overflow.
     * @param player The player to receive the streak bonus.
     * @param amount Number of streak days to add.
     * @param currentDay The current quest day for state synchronization.
     * @custom:reverts OnlyGame When caller is not GAME contract.
     */
    function awardQuestStreakBonus(address player, uint16 amount, uint24 currentDay) external onlyGame {
        if (player == address(0) || amount == 0 || currentDay == 0) return;

        PlayerQuestState storage state = questPlayerState[player];
        _questSyncState(state, player, currentDay);

        // While afking the manual streak is dormant and finalizeAfking overwrites it; writing it
        // here would discard the bonus at finalize and orphan a century shield granted off the
        // soon-overwritten value (which the high-water re-arm then lets a later re-climb re-grant).
        // Route the bonus into the afking sub streak base, as the daily (+1) and level-quest
        // secondary completions already do, so it is reconciled into the earned streak and the
        // century shield is granted once off the reconciled value at finalize.
        if (state.afkingActive) {
            questGame.recordAfkingSecondary(player, amount);
            return;
        }

        uint16 prevStreak = state.streak;
        uint32 updated = uint32(prevStreak) + uint32(amount);
        uint16 newStreak = updated > type(uint16).max ? type(uint16).max : uint16(updated);
        state.streak = newStreak;
        _grantCenturyShield(player, state);

        uint24 currentDay24 = uint24(currentDay);
        if (state.lastActiveDay < currentDay24) {
            state.lastActiveDay = currentDay24;
        }
        emit QuestStreakBonusAwarded(player, amount, newStreak, currentDay);
    }

    /// @dev A foil purchase guarantees a quest streak of at least this floor.
    uint16 internal constant FOIL_STREAK_FLOOR = 12;

    /**
     * @notice Raise a player's quest streak to a floor of 12 as a foil-pack benefit.
     * @dev Called from handleFoilPurchase (GAME-gated) AFTER the buy's own primary + secondary
     *      quest completions, so it applies on top of them. Unconditional on quest state (a foil
     *      purchase boosts the streak even if no daily quest completed); never lowers an already-
     *      higher streak. Syncs the day-lapse state first (idempotent — the foil leg already
     *      synced today), so a foil buy restores the streak floor even after a missed-day reset.
     *      For a mid-run afker, whose reward streak is the afking sub base plus funded delivered
     *      days (independent of state.streak), the same floor is applied to that base via the
     *      afking module — before the manual-streak early-return below, so it reaches the afker
     *      even when their manual streak is already at the floor.
     * @param player The player who bought the foil pack.
     */
    function _foilStreakFloor(address player) private {
        if (player == address(0)) return;
        uint24 currentDay = _currentQuestDay(_loadActiveQuests());
        if (currentDay == 0) return;
        PlayerQuestState storage state = questPlayerState[player];
        _questSyncState(state, player, currentDay);
        if (state.afkingActive) {
            questGame.floorAfkingStreakBase(player, FOIL_STREAK_FLOOR);
        }
        uint16 prev = state.streak;
        if (prev >= FOIL_STREAK_FLOOR) return;
        state.streak = FOIL_STREAK_FLOOR;
        if (state.lastActiveDay < currentDay) {
            state.lastActiveDay = currentDay;
        }
        emit QuestStreakBonusAwarded(player, FOIL_STREAK_FLOOR - prev, FOIL_STREAK_FLOOR, currentDay);
    }

    /**
     * @notice Grant quest streak shields to a player. Each shield absorbs one missed day,
     *         preserving the streak instead of resetting it (consumed in `_questSyncState`).
     * @dev Access: GAME contract only (the lootbox quest-shield boon routes through GAME).
     *      Silently returns on zero address / zero amount. The shield count is a uint8 and
     *      saturates at 255 — far above any reachable balance.
     * @param player The player to receive shields.
     * @param amount Number of shields to add.
     * @custom:reverts OnlyGame When caller is not GAME contract.
     */
    function awardQuestStreakShield(address player, uint16 amount) external onlyGame {
        if (player == address(0) || amount == 0) return;
        PlayerQuestState storage state = questPlayerState[player];
        uint256 updated = uint256(state.streakShield) + amount;
        uint8 newShield = updated > type(uint8).max ? type(uint8).max : uint8(updated);
        state.streakShield = newShield;
        emit QuestStreakShieldGranted(player, amount, newShield);
    }

    /// @dev Milestone streak-shield grant. Called after every write to `state.streak`: each
    ///      newly-reached streak-century (100, 200, …) grants +1 shield, but never lifts the held
    ///      balance above CENTURY_SHIELD_MAX_HELD — a player already at or above the cap gets
    ///      nothing. `shieldCenturyHighWater` tracks the highest century already credited and
    ///      re-arms DOWN when the streak drops below it (a reset/decay), so a player who loses the
    ///      streak and genuinely re-climbs earns each century marker again. Within a run it prevents
    ///      double-crediting a century already passed. Reuses streakShield consumed in `_questSyncState`.
    function _grantCenturyShield(address player, PlayerQuestState storage state) private {
        uint256 century = uint256(state.streak) / CENTURY_SHIELD_INTERVAL;
        uint256 highWater = state.shieldCenturyHighWater;
        if (century < highWater) {
            state.shieldCenturyHighWater = uint8(century);
            return;
        }
        if (century == highWater) return;
        uint256 owed = century - highWater;
        state.shieldCenturyHighWater = century > type(uint8).max ? type(uint8).max : uint8(century);
        uint256 held = state.streakShield;
        if (held >= CENTURY_SHIELD_MAX_HELD) return;
        uint256 granted = held + owed > CENTURY_SHIELD_MAX_HELD
            ? CENTURY_SHIELD_MAX_HELD - held
            : owed;
        uint8 newShield = uint8(held + granted);
        state.streakShield = newShield;
        emit QuestStreakShieldGranted(player, uint16(granted), newShield);
    }

    /**
     * @notice Begins an afking run for a subscriber: snapshots the (gap-synced) streak and
     *         flips the afking flag so subsequent slot-0 completions are streak-neutral.
     * @dev GAME-only. While afking, the afking compute-on-read (Game-side, off the Sub slot)
     *      owns the player's quest streak; the manual `state.streak` is dormant and is
     *      overwritten by `finalizeAfking` when the run ends. Returns the synced streak so the
     *      caller can base the run's snapshot on it.
     *
     *      Syncs day-reset state first (applying any pending gap-decay) so the snapshot is
     *      honest, then sets `afkingActive`. Does not touch the slot-1 quest.
     * @param player The subscriber starting an afking run.
     * @param currentDay The current quest day for state synchronization.
     * @return streak The player's gap-synced streak at the start of the run.
     * @custom:reverts OnlyGame When caller is not GAME contract.
     */
    function beginAfking(address player, uint24 currentDay)
        external
        onlyGame
        returns (uint24 streak)
    {
        if (player == address(0)) return 0;
        PlayerQuestState storage state = questPlayerState[player];
        if (currentDay != 0) _questSyncState(state, player, currentDay);
        streak = state.streak;
        state.afkingActive = true;
    }

    /**
     * @notice Ends an afking run: hands the afking-computed streak back to the manual quest
     *         system. Idempotent — a no-op unless the player is currently afking.
     * @dev GAME-only, called on every sub-ending path (cancel / cancel-reclaim / pass-eviction
     *      / funding-kill) BEFORE the Sub slot is deleted. The last valid mint day is the later of
     *      the afking funded high-water (`afkingCoveredDay`, Game-side) and `lastActiveDay` (which
     *      captures manual completions during the run — slot completions still bump it even though
     *      they are streak-neutral while afking). Keeps the Game-computed `earnedStreak` if a valid
     *      mint landed no earlier than yesterday; else a full prior day was missed with NO valid
     *      mint (afking or manual) → zero (decay). Anchors `lastActiveDay`/`lastCompletedDay` at
     *      that day so the manual gap-reset is honest from there, and clears `afkingActive`. A
     *      double-call (cancel then in-stage reclaim) is safe: the second finds `afkingActive`
     *      already false and returns.
     * @param player The subscriber whose run is ending.
     * @param earnedStreak The run's earned streak (snapshot + funded delivered days), Game-computed.
     * @param afkingCoveredDay The afking funded high-water day (Game-side).
     * @param currentDay The current quest day (the decay reference).
     * @custom:reverts OnlyGame When caller is not GAME contract.
     */
    function finalizeAfking(
        address player,
        uint24 earnedStreak,
        uint24 afkingCoveredDay,
        uint24 currentDay
    ) external onlyGame {
        if (player == address(0)) return;
        PlayerQuestState storage state = questPlayerState[player];
        if (!state.afkingActive) return; // idempotent: already finalized / never afking
        uint24 lastValid = afkingCoveredDay;
        if (state.lastActiveDay > lastValid) lastValid = state.lastActiveDay;
        uint24 finalStreak = (currentDay == 0 || lastValid + 1 >= currentDay)
            ? earnedStreak
            : 0;
        state.streak = finalStreak > type(uint16).max ? type(uint16).max : uint16(finalStreak);
        _grantCenturyShield(player, state);
        uint24 d = lastValid;
        state.lastActiveDay = d;
        state.lastCompletedDay = d;
        state.afkingActive = false;
        emit QuestStreakBonusAwarded(player, 0, finalStreak, lastValid);
    }

    // =========================================================================
    //                      PROGRESS HANDLERS (COIN-ONLY)
    // =========================================================================
    // All handle* functions follow a common pattern:
    // 1. Early-exit if player/amount invalid or no active quest day
    // 2. Sync player state (reset streak if day missed, snapshot baseStreak)
    // 3. Find matching quest slot for the action type
    // 4. Sync slot progress (reset if day changed)
    // 5. Accumulate progress and check against fixed target
    // 6. On completion, credit rewards and check if other slot also completes
    //
    // Return values are consistent across all handlers:
    // - reward: FLIP tokens to credit (in base units, 18 decimals)
    // - questType: The type of quest that was processed
    // - streak: Player's current streak after this action
    // - completed: True if a quest was completed by this action

    /**
     * @notice Handle mint progress for a player; covers both FLIP and ETH paid mints.
     * @dev Access: COIN or COINFLIP contract only.
     *      Slot 0 is always the MINT_ETH quest and the slot-1 bonus roll excludes the
     *      primary type, so each mint kind checks exactly one slot.
     * @param player The player who performed the mint.
     * @param quantity Number of tickets minted.
     * @param paidWithEth True if ETH was used (MINT_ETH quest), false for FLIP (MINT_FLIP).
     * @return reward FLIP tokens earned (in base units, 18 decimals).
     * @return questType The type of quest that was processed.
     * @return streak Player's current streak after this action.
     * @return completed True if a quest was completed by this action.
     * @custom:reverts OnlyCoin When caller is not COIN or COINFLIP contract.
     */
    function handleMint(
        address player,
        uint32 quantity,
        bool paidWithEth,
        uint256 mintPrice
    )
        external
        onlyCoin
        returns (uint256 reward, uint8 questType, uint32 streak, bool completed)
    {
        DailyQuest[QUEST_SLOT_COUNT] memory quests = _loadActiveQuests();
        uint24 currentDay = _currentQuestDay(quests);
        PlayerQuestState storage state = questPlayerState[player];
        if (player == address(0) || quantity == 0 || currentDay == 0) {
            return (0, quests[0].questType, state.streak, false);
        }

        _questSyncState(state, player, currentDay);

        uint8 outQuestType = paidWithEth ? QUEST_TYPE_MINT_ETH : QUEST_TYPE_MINT_FLIP;
        uint32 outStreak = state.streak;

        // Slot 0 is always the MINT_ETH quest and the slot-1 bonus roll excludes the
        // primary type, so each mint kind can only ever match one fixed slot:
        // MINT_ETH -> slot 0, MINT_FLIP -> slot 1.
        uint8 slot = paidWithEth ? 0 : 1;
        DailyQuest memory quest = quests[slot];
        if (quest.day == currentDay && quest.questType == outQuestType) {
            uint256 delta = paidWithEth ? uint256(quantity) * mintPrice : quantity;
            uint256 target = _questTargetValue(quest, slot, mintPrice);
            (reward, questType, streak, completed) = _questHandleProgressSlot(
                player,
                state,
                quests,
                quest,
                slot,
                delta,
                target,
                currentDay,
                mintPrice,
                outQuestType,
                delta,
                mintPrice
            );
            if (completed) {
                if (!paidWithEth && reward != 0) {
                    coinflip.creditFlip(player, reward);
                }
                return (reward, questType, streak, true);
            }
        } else if (paidWithEth) {
            // No daily quest slot matched — still credit level quest progress
            _handleLevelQuestProgress(player, QUEST_TYPE_MINT_ETH, uint256(quantity) * mintPrice, mintPrice);
        } else {
            _handleLevelQuestProgress(player, QUEST_TYPE_MINT_FLIP, quantity, 0);
        }
        return (0, outQuestType, outStreak, false);
    }

    /**
     * @notice Handle flip/unstake progress credited in FLIP base units (18 decimals).
     * @dev Access: COIN or COINFLIP contract only.
     *      Progress tracks cumulative flip volume for the day.
     * @param player The player who staked/unstaked.
     * @param flipCredit Amount of FLIP staked/unstaked (in base units).
     * @return reward FLIP tokens earned (in base units, 18 decimals).
     * @return questType The type of quest that was processed.
     * @return streak Player's current streak after this action.
     * @return completed True if a quest was completed by this action.
     * @custom:reverts OnlyCoin When caller is not COIN or COINFLIP contract.
     */
    function handleFlip(
        address player,
        uint256 flipCredit
    )
        external
        onlyCoin
        returns (uint256 reward, uint8 questType, uint32 streak, bool completed)
    {
        DailyQuest[QUEST_SLOT_COUNT] memory quests = _loadActiveQuests();
        uint24 currentDay = _currentQuestDay(quests);
        PlayerQuestState storage state = questPlayerState[player];
        if (player == address(0) || flipCredit == 0 || currentDay == 0) {
            return (0, quests[0].questType, state.streak, false);
        }
        _questSyncState(state, player, currentDay);
        _handleLevelQuestProgress(player, QUEST_TYPE_FLIP, flipCredit, 0);

        (DailyQuest memory quest, uint8 slotIndex) = _currentDayQuestOfType(quests, currentDay, QUEST_TYPE_FLIP);
        if (slotIndex == type(uint8).max) {
            return (0, QUEST_TYPE_FLIP, state.streak, false);
        }

        uint16 progressAfter = _clampedAddU16(
            _questSyncProgress(state, slotIndex, currentDay),
            _toStoredProgress(quest.questType, flipCredit)
        );
        _setProgressOf(state, slotIndex, progressAfter);
        uint256 target = _questTargetValue(quest, slotIndex, 0);
        emit QuestProgressUpdated(
            player,
            currentDay,
            slotIndex,
            quest.questType,
            uint128(_toNativeProgress(quest.questType, progressAfter)),
            _toNativeProgress(quest.questType, target)
        );
        if (progressAfter < target) {
            return (0, quest.questType, state.streak, false);
        }
        if (_secondaryLocked(state, slotIndex)) {
            return (0, quest.questType, state.streak, false);
        }

        return _questCompleteWithPair(player, state, quests, slotIndex, quest, currentDay, 0);
    }

    /**
     * @notice Handle decimator burns counted in FLIP base units (18 decimals).
     * @dev Access: COIN or COINFLIP contract only.
     *      Decimator quests share the same FLIP target as flip quests (2000 FLIP).
     * @param player The player who performed the decimator burn.
     * @param burnAmount Amount of FLIP burned (in base units).
     * @return reward FLIP tokens earned (in base units, 18 decimals).
     * @return questType The type of quest that was processed.
     * @return streak Player's current streak after this action.
     * @return completed True if a quest was completed by this action.
     * @custom:reverts OnlyCoin When caller is not COIN or COINFLIP contract.
     */
    function handleDecimator(
        address player,
        uint256 burnAmount
    )
        external
        onlyCoin
        returns (uint256 reward, uint8 questType, uint32 streak, bool completed)
    {
        DailyQuest[QUEST_SLOT_COUNT] memory quests = _loadActiveQuests();
        uint24 currentDay = _currentQuestDay(quests);
        PlayerQuestState storage state = questPlayerState[player];
        if (player == address(0) || burnAmount == 0 || currentDay == 0) {
            return (0, quests[0].questType, state.streak, false);
        }
        _questSyncState(state, player, currentDay);
        _handleLevelQuestProgress(player, QUEST_TYPE_DECIMATOR, burnAmount, 0);

        (DailyQuest memory quest, uint8 slotIndex) = _currentDayQuestOfType(quests, currentDay, QUEST_TYPE_DECIMATOR);
        if (slotIndex == type(uint8).max) {
            return (0, QUEST_TYPE_DECIMATOR, state.streak, false);
        }
        uint16 progressAfter = _clampedAddU16(
            _questSyncProgress(state, slotIndex, currentDay),
            _toStoredProgress(quest.questType, burnAmount)
        );
        _setProgressOf(state, slotIndex, progressAfter);
        uint256 target = _questTargetValue(quest, slotIndex, 0);
        emit QuestProgressUpdated(
            player,
            currentDay,
            slotIndex,
            quest.questType,
            uint128(_toNativeProgress(quest.questType, progressAfter)),
            _toNativeProgress(quest.questType, target)
        );
        if (progressAfter < target) {
            return (0, quest.questType, state.streak, false);
        }
        if (_secondaryLocked(state, slotIndex)) {
            return (0, quest.questType, state.streak, false);
        }
        (reward, questType, streak, completed) = _questCompleteWithPair(player, state, quests, slotIndex, quest, currentDay, 0);
        if (completed && reward != 0) {
            coinflip.creditFlip(player, reward);
        }
    }

    /// @dev Foil secondary-quest progression (see handleFoilPurchase). Private so the streak
    ///      floor runs unconditionally after it, across all of its early-return paths.
    function _handleFoilPackQuest(
        address player
    )
        private
        returns (uint256 reward, uint8 questType, uint32 streak, bool completed)
    {
        DailyQuest[QUEST_SLOT_COUNT] memory quests = _loadActiveQuests();
        uint24 currentDay = _currentQuestDay(quests);
        PlayerQuestState storage state = questPlayerState[player];
        if (player == address(0) || currentDay == 0) {
            return (0, quests[0].questType, state.streak, false);
        }
        _questSyncState(state, player, currentDay);

        (DailyQuest memory quest, uint8 slotIndex) = _currentDayQuestOfType(
            quests,
            currentDay,
            QUEST_TYPE_FOIL
        );
        if (slotIndex == type(uint8).max) {
            return (0, QUEST_TYPE_FOIL, state.streak, false);
        }
        uint16 progressAfter = _clampedAddU16(
            _questSyncProgress(state, slotIndex, currentDay),
            uint16(_toStoredProgress(quest.questType, 1))
        );
        _setProgressOf(state, slotIndex, progressAfter);
        uint256 target = _questTargetValue(quest, slotIndex, 0);
        emit QuestProgressUpdated(
            player,
            currentDay,
            slotIndex,
            quest.questType,
            uint128(_toNativeProgress(quest.questType, progressAfter)),
            _toNativeProgress(quest.questType, target)
        );
        if (progressAfter < target) {
            return (0, quest.questType, state.streak, false);
        }
        if (_secondaryLocked(state, slotIndex)) {
            return (0, quest.questType, state.streak, false);
        }
        (reward, questType, streak, completed) = _questCompleteWithPair(
            player,
            state,
            quests,
            slotIndex,
            quest,
            currentDay,
            0
        );
        if (completed && reward != 0) {
            coinflip.creditFlip(player, reward);
        }
    }

    /**
     * @notice Handle affiliate earnings credited in FLIP base units (18 decimals).
     * @dev Access: COIN or COINFLIP contract only.
     * @param player The affiliate who earned commission.
     * @param amount FLIP earned from affiliate referrals (in base units).
     * @return reward FLIP tokens earned (in base units, 18 decimals).
     * @return questType The type of quest that was processed.
     * @return streak Player's current streak after this action.
     * @return completed True if a quest was completed by this action.
     * @custom:reverts OnlyCoin When caller is not COIN or COINFLIP contract.
     */
    function handleAffiliate(
        address player,
        uint256 amount
    )
        external
        onlyCoin
        returns (uint256 reward, uint8 questType, uint32 streak, bool completed)
    {
        DailyQuest[QUEST_SLOT_COUNT] memory quests = _loadActiveQuests();
        uint24 currentDay = _currentQuestDay(quests);
        PlayerQuestState storage state = questPlayerState[player];
        if (player == address(0) || amount == 0 || currentDay == 0) {
            return (0, quests[0].questType, state.streak, false);
        }
        _questSyncState(state, player, currentDay);
        _handleLevelQuestProgress(player, QUEST_TYPE_AFFILIATE, amount, 0);

        (DailyQuest memory quest, uint8 slotIndex) = _currentDayQuestOfType(quests, currentDay, QUEST_TYPE_AFFILIATE);
        if (slotIndex == type(uint8).max) {
            return (0, QUEST_TYPE_AFFILIATE, state.streak, false);
        }
        uint16 progressAfter = _clampedAddU16(
            _questSyncProgress(state, slotIndex, currentDay),
            _toStoredProgress(quest.questType, amount)
        );
        _setProgressOf(state, slotIndex, progressAfter);
        uint256 target = _questTargetValue(quest, slotIndex, 0);
        emit QuestProgressUpdated(
            player,
            currentDay,
            slotIndex,
            quest.questType,
            uint128(_toNativeProgress(quest.questType, progressAfter)),
            _toNativeProgress(quest.questType, target)
        );
        if (progressAfter < target) {
            return (0, quest.questType, state.streak, false);
        }
        if (_secondaryLocked(state, slotIndex)) {
            return (0, quest.questType, state.streak, false);
        }
        return _questCompleteWithPair(player, state, quests, slotIndex, quest, currentDay, 0);
    }

    /**
     * @notice Handle combined purchase-path activity (mint tickets + lootbox) in a single call.
     * @dev Access: COIN or COINFLIP contract only.
     *      Combines the mint + lootbox quest legs for the purchase path.
     *      FLIP mint rewards are creditFlipped internally; ETH mint and lootbox rewards are
     *      returned for the caller to batch (the caller credits the lootbox reward exactly
     *      once). Returns streak for compute-once score forwarding.
     * @param player The player who purchased.
     * @param ethMintSpendWei Gross ETH-denominated spend on tickets + lootbox in wei
     *        (fresh + recycled), credited 1:1 to MINT_ETH quest.
     * @param flipMintQty FLIP-paid ticket-equivalent mint units.
     * @param lootBoxAmount ETH spent on lootbox in wei (full amount, fresh + recycled).
     * @param mintPrice Current ticket price in wei (purchaseLevel price for daily targets).
     * @param levelQuestPrice Price for level quest targets (level+1 price).
     * @return reward FLIP tokens earned (in base units, 18 decimals).
     * @return questType The type of quest that was processed.
     * @return streak Player's current streak after this action.
     * @return completed True if a quest was completed by this action.
     * @custom:reverts OnlyCoin When caller is not COIN or COINFLIP contract.
     */
    function handlePurchase(
        address player,
        uint256 ethMintSpendWei,
        uint32 flipMintQty,
        uint256 lootBoxAmount,
        uint256 mintPrice,
        uint256 levelQuestPrice
    )
        external
        onlyCoin
        returns (uint256 reward, uint8 questType, uint32 streak, bool completed)
    {
        return _handlePurchase(
            player, ethMintSpendWei, flipMintQty, lootBoxAmount, mintPrice, levelQuestPrice
        );
    }

    /**
     * @notice Foil-pack purchase handler: the shared primary purchase legs, then the foil
     *         secondary quest and streak floor, in one GAME call.
     * @dev Access: GAME contract only (the foil module runs in GAME's context). Runs the
     *      shared primary purchase legs, snapshots the reward streak, then the foil secondary
     *      quest and streak floor. The returned streakSnapshot is the reward streak AFTER the
     *      primary legs but BEFORE the secondary quest and streak floor — the basis the
     *      foil-EV boost freezes against.
     *      The secondary self-credits its FLIP reward; only the primary leg's reward/type/
     *      completion are returned (the caller batches the primary reward).
     * @param player The player who bought the foil pack.
     * @param ethMintSpendWei Gross ETH-denominated foil spend in wei, credited 1:1 to MINT_ETH.
     * @param flipMintQty FLIP-paid ticket-equivalent mint units.
     * @param lootBoxAmount ETH spent on lootbox in wei.
     * @param mintPrice Current ticket price in wei (daily targets).
     * @param levelQuestPrice Price for level quest targets (level+1 price).
     * @return reward Primary-leg FLIP reward (0 if not completed).
     * @return questType The primary quest type processed.
     * @return completed True if the primary quest completed by this action.
     * @return streakSnapshot Pre-floor reward streak for the foil-EV activity score.
     * @custom:reverts OnlyGame When caller is not GAME contract.
     */
    function handleFoilPurchase(
        address player,
        uint256 ethMintSpendWei,
        uint32 flipMintQty,
        uint256 lootBoxAmount,
        uint256 mintPrice,
        uint256 levelQuestPrice
    )
        external
        onlyGame
        returns (uint256 reward, uint8 questType, bool completed, uint32 streakSnapshot)
    {
        (reward, questType, , completed) = _handlePurchase(
            player, ethMintSpendWei, flipMintQty, lootBoxAmount, mintPrice, levelQuestPrice
        );
        // Snapshot the reward streak post-primary, pre-floor: the foil-EV boost freezes
        // against this streak, captured before the secondary quest and streak floor below
        // mutate it.
        streakSnapshot = _effectiveBaseStreak(
            questPlayerState[player],
            _currentQuestDay(_loadActiveQuests())
        );
        _handleFoilPackQuest(player);
        _foilStreakFloor(player);
    }

    /// @dev Shared purchase-path quest legs (mint ETH/FLIP + lootbox). Modifier-less core
    ///      behind handlePurchase (COIN-gated) and handleFoilPurchase (GAME-gated).
    function _handlePurchase(
        address player,
        uint256 ethMintSpendWei,
        uint32 flipMintQty,
        uint256 lootBoxAmount,
        uint256 mintPrice,
        uint256 levelQuestPrice
    )
        private
        returns (uint256 reward, uint8 questType, uint32 streak, bool completed)
    {
        DailyQuest[QUEST_SLOT_COUNT] memory quests = _loadActiveQuests();
        uint24 currentDay = _currentQuestDay(quests);
        PlayerQuestState storage state = questPlayerState[player];
        if (player == address(0) || currentDay == 0) {
            return (0, quests[0].questType, state.streak, false);
        }
        if (ethMintSpendWei == 0 && flipMintQty == 0 && lootBoxAmount == 0) {
            return (0, quests[0].questType, state.streak, false);
        }

        _questSyncState(state, player, currentDay);

        uint256 ethMintReward;
        uint256 flipMintReward;
        uint256 lootboxReward;
        bool anyCompleted;
        uint8 outQuestType;
        uint32 outStreak = state.streak;

        // --- ETH mint quest progress ---
        // Gross ETH spend on tickets + lootboxes (fresh + recycled) is credited 1:1
        // in wei to the MINT_ETH quest. Slot 0 is always the MINT_ETH quest, so only
        // that slot can match.
        if (ethMintSpendWei != 0) {
            DailyQuest memory quest = quests[0];
            if (quest.day == currentDay && quest.questType == QUEST_TYPE_MINT_ETH) {
                outQuestType = QUEST_TYPE_MINT_ETH;
                uint256 target = _questTargetValue(quest, 0, mintPrice);
                (uint256 r, uint8 qt, uint32 s, bool c) = _questHandleProgressSlot(
                    player, state, quests, quest, 0,
                    ethMintSpendWei, target, currentDay, mintPrice,
                    QUEST_TYPE_MINT_ETH, ethMintSpendWei,
                    levelQuestPrice
                );
                if (c) {
                    ethMintReward += r;
                    outQuestType = qt;
                    outStreak = s;
                    anyCompleted = true;
                }
            } else {
                _handleLevelQuestProgress(player, QUEST_TYPE_MINT_ETH, ethMintSpendWei, levelQuestPrice);
            }
        }

        // --- FLIP mint quest progress ---
        // The slot-1 bonus roll excludes the primary MINT_ETH type, so MINT_FLIP
        // can only ever be the slot-1 quest.
        if (flipMintQty != 0) {
            DailyQuest memory quest = quests[1];
            if (quest.day == currentDay && quest.questType == QUEST_TYPE_MINT_FLIP) {
                outQuestType = QUEST_TYPE_MINT_FLIP;
                uint256 target = _questTargetValue(quest, 1, 0);
                (uint256 r, uint8 qt, uint32 s, bool c) = _questHandleProgressSlot(
                    player, state, quests, quest, 1,
                    flipMintQty, target, currentDay, 0,
                    QUEST_TYPE_MINT_FLIP, flipMintQty,
                    levelQuestPrice
                );
                if (c) {
                    flipMintReward += r;
                    outQuestType = qt;
                    outStreak = s;
                    anyCompleted = true;
                }
            } else {
                _handleLevelQuestProgress(player, QUEST_TYPE_MINT_FLIP, flipMintQty, levelQuestPrice);
            }
        }

        // --- Lootbox quest progress ---
        if (lootBoxAmount != 0) {
            _handleLevelQuestProgress(player, QUEST_TYPE_LOOTBOX, lootBoxAmount, levelQuestPrice);

            (DailyQuest memory quest, uint8 slotIndex) = _currentDayQuestOfType(quests, currentDay, QUEST_TYPE_LOOTBOX);
            if (slotIndex != type(uint8).max) {
                uint16 progressAfter = _clampedAddU16(
                    _questSyncProgress(state, slotIndex, currentDay),
                    _toStoredProgress(quest.questType, lootBoxAmount)
                );
                _setProgressOf(state, slotIndex, progressAfter);
                uint256 target = _questTargetValue(quest, slotIndex, mintPrice);
                emit QuestProgressUpdated(
                    player, currentDay, slotIndex, quest.questType,
                    uint128(_toNativeProgress(quest.questType, progressAfter)),
                    _toNativeProgress(quest.questType, target)
                );

                if (progressAfter >= target) {
                    bool canComplete = !_secondaryLocked(state, slotIndex);
                    if (canComplete) {
                        (uint256 r, uint8 qt, uint32 s, bool c) = _questCompleteWithPair(
                            player, state, quests, slotIndex, quest, currentDay, mintPrice
                        );
                        if (c) {
                            lootboxReward += r;
                            outQuestType = qt;
                            outStreak = s;
                            anyCompleted = true;
                        }
                    }
                }
            }
        }

        // Reward routing: MINT_ETH, LOOTBOX and MINT_FLIP are quest TYPES, not
        // payout currencies — every quest reward is paid as a FLIP flip stake.
        // No reward is credited here; the full earned amount is returned to the
        // caller, which adds it to lootboxFlipCredit and credits it exactly once.
        uint256 totalReturned = ethMintReward + lootboxReward + flipMintReward;
        if (anyCompleted) {
            return (totalReturned, outQuestType, outStreak, true);
        }
        return (0, outQuestType != 0 ? outQuestType : quests[0].questType, outStreak, false);
    }

    /**
     * @notice Handle Degenerette bet progress for a player.
     * @dev Access: COIN or COINFLIP contract only.
     * @param player The player who placed the Degenerette bet.
     * @param amount The bet amount (wei for ETH, base units for FLIP).
     * @param paidWithEth True if bet was paid with ETH, false for FLIP.
     * @param mintPrice Current ticket price in wei (0 for FLIP bets).
     * @return reward FLIP tokens earned (in base units, 18 decimals).
     * @return questType The type of quest that was processed.
     * @return streak Player's current streak after this action.
     * @return completed True if a quest was completed by this action.
     * @custom:reverts OnlyCoin When caller is not COIN or COINFLIP contract.
     */
    function handleDegenerette(
        address player,
        uint256 amount,
        bool paidWithEth,
        uint256 mintPrice
    )
        external
        onlyCoin
        returns (uint256 reward, uint8 questType, uint32 streak, bool completed)
    {
        DailyQuest[QUEST_SLOT_COUNT] memory quests = _loadActiveQuests();
        uint24 currentDay = _currentQuestDay(quests);
        PlayerQuestState storage state = questPlayerState[player];
        if (player == address(0) || amount == 0 || currentDay == 0) {
            return (0, quests[0].questType, state.streak, false);
        }
        _questSyncState(state, player, currentDay);

        uint8 targetType = paidWithEth ? QUEST_TYPE_DEGENERETTE_ETH : QUEST_TYPE_DEGENERETTE_FLIP;
        (DailyQuest memory quest, uint8 slotIndex) = _currentDayQuestOfType(quests, currentDay, targetType);
        if (slotIndex == type(uint8).max) {
            _handleLevelQuestProgress(player, targetType, amount, mintPrice);
            return (0, targetType, state.streak, false);
        }

        uint256 target = _questTargetValue(quest, slotIndex, mintPrice);
        (reward, questType, streak, completed) = _questHandleProgressSlot(
            player,
            state,
            quests,
            quest,
            slotIndex,
            amount,
            target,
            currentDay,
            mintPrice,
            targetType,
            amount,
            mintPrice
        );
        if (completed && reward != 0) {
            coinflip.creditFlip(player, reward);
        }
    }

    // =========================================================================
    //                            VIEW FUNCTIONS
    // =========================================================================

    /**
     * @notice View helper for frontends; returns quest baselines.
     * @dev Frontends should use `getPlayerQuestView` for player-specific progress.
     *      Quest types are returned exactly as stored for the current day.
     * @return quests Array of QuestInfo structs with type, day, and requirements.
     */
    function getActiveQuests() external view returns (QuestInfo[2] memory quests) {
        DailyQuest[QUEST_SLOT_COUNT] memory local = _materializeActiveQuestsForView();
        uint24 currentDay = _currentQuestDay(local);
        PlayerQuestState memory emptyState;
        for (uint8 slot; slot < QUEST_SLOT_COUNT; ) {
            (quests[slot], , ) = _questViewData(local[slot], emptyState, slot, currentDay);
            unchecked {
                ++slot;
            }
        }
    }

    /**
     * @dev Returns active quests as stored (no in-memory conversions).
     * @return local Memory copy of the active quest pair.
     */
    function _materializeActiveQuestsForView() private view returns (DailyQuest[QUEST_SLOT_COUNT] memory local) {
        local = _loadActiveQuests();
    }

    /**
     * @notice Returns raw player quest state for debugging/analytics.
     * @param player The player address to query.
     * @return streak Current streak count.
     * @return lastCompletedDay Last day where a streak was credited (first slot completion).
     * @return progress Per-slot progress values (only valid if the day matches).
     * @return completed Per-slot completion flags for current day.
     */
    function playerQuestStates(
        address player
    )
        external
        view
        override
        returns (uint32 streak, uint24 lastCompletedDay, uint128[2] memory progress, bool[2] memory completed)
    {
        DailyQuest[QUEST_SLOT_COUNT] memory local = _loadActiveQuests();
        PlayerQuestState memory state = questPlayerState[player];
        uint24 currentDay = _currentQuestDay(local);
        streak = state.streak;
        lastCompletedDay = state.lastCompletedDay;
        for (uint8 slot; slot < QUEST_SLOT_COUNT; ) {
            DailyQuest memory quest = local[slot];
            // Only return progress if it's valid for the current quest day
            progress[slot] = _questProgressValid(state, quest, slot, currentDay)
                ? uint128(_toNativeProgress(quest.questType, _progressOfMem(state, slot)))
                : 0;
            completed[slot] = _questCompleted(state, quest, slot);
            unchecked {
                ++slot;
            }
        }
    }

    /**
     * @notice Per-slot completion flags for the active quest day — the lean form of
     *         `playerQuestStates` for callers that need only the flags. Costs one
     *         packed quest-pair SLOAD plus one player-state SLOAD; no streak,
     *         progress-validity, or native-unit conversion work.
     * @param player The player address to query.
     * @return slot0 True if the player has completed quest slot 0 for its active day.
     * @return slot1 True if the player has completed quest slot 1 for its active day.
     */
    function questCompletionToday(address player) external view returns (bool slot0, bool slot1) {
        DailyQuest[QUEST_SLOT_COUNT] memory local = _loadActiveQuests();
        PlayerQuestState memory state = questPlayerState[player];
        slot0 = _questCompleted(state, local[0], 0);
        slot1 = _questCompleted(state, local[1], 1);
    }

    /**
     * @notice Player-specific view of quests with fixed requirements and progress.
     * @dev Handles streak decay preview: if player missed a day (gap > 1), the effective
     *      streak shown is 0, matching what would happen on their next action.
     *      This is the recommended view function for frontends displaying quest UI.
     * @param player The player address to query.
     * @return viewData Comprehensive view including quests, progress, completion, and streak.
     */
    function getPlayerQuestView(address player) external view returns (PlayerQuestView memory viewData) {
        DailyQuest[QUEST_SLOT_COUNT] memory local = _materializeActiveQuestsForView();
        uint24 currentDay = _currentQuestDay(local);
        PlayerQuestState memory state = questPlayerState[player];

        viewData.lastCompletedDay = state.lastCompletedDay;
        viewData.baseStreak = _effectiveBaseStreak(state, currentDay);

        for (uint8 slot; slot < QUEST_SLOT_COUNT; ) {
            (viewData.quests[slot], viewData.progress[slot], viewData.completed[slot]) = _questViewData(
                local[slot],
                state,
                slot,
                currentDay
            );
            unchecked {
                ++slot;
            }
        }
    }

    /// @notice The player's decay-aware effective reward streak — the value getPlayerQuestView
    ///         exposes as baseStreak, computed WITHOUT materializing the per-quest view structs
    ///         (a cheap read for reward scaling). A streak lapsed past its shields reads 0, so a
    ///         stale-high raw streak (built then abandoned with no quest sync) can't inflate
    ///         downstream reward scaling — terminal-decimator weight, lootbox EV, or sDGNRS claims.
    /// @param player The player address to query.
    /// @return The effective (decay-applied) reward streak.
    function effectiveBaseStreak(address player) external view returns (uint32) {
        return _effectiveBaseStreak(
            questPlayerState[player],
            _currentQuestDay(_materializeActiveQuestsForView())
        );
    }

    /// @notice effectiveBaseStreak plus the player's afking-run flag, from the single quest-state
    ///         read, so a Game-side caller can skip its Sub-slot lookup for the common (non-afking)
    ///         player and only an afking player pays the extra Sub read.
    /// @param player The player address to query.
    /// @return streak The effective (decay-applied) reward streak.
    /// @return afking True while the player is mid afking-run.
    function effectiveBaseStreakAndAfking(address player) external view returns (uint32 streak, bool afking) {
        PlayerQuestState memory state = questPlayerState[player];
        streak = _effectiveBaseStreak(state, _currentQuestDay(_materializeActiveQuestsForView()));
        afking = state.afkingActive;
    }

    // =========================================================================
    //                           INTERNAL HELPERS
    // =========================================================================

    /// @dev Single source of truth for the effective reward streak (getPlayerQuestView.baseStreak
    ///      and effectiveBaseStreak). A streak lapsed past its shields reads 0; once active today
    ///      the synced start-of-day baseStreak snapshot is used.
    function _effectiveBaseStreak(
        PlayerQuestState memory state,
        uint24 currentDay
    ) private pure returns (uint32) {
        uint32 effectiveStreak = state.streak;
        uint24 anchorDay = state.lastActiveDay != 0 ? state.lastActiveDay : state.lastCompletedDay;
        if (anchorDay != 0 && currentDay > anchorDay + 1) {
            uint32 missedDays = currentDay - anchorDay - 1;
            if (missedDays > uint32(state.streakShield)) {
                effectiveStreak = 0;
            }
        }
        return (state.lastSyncDay == currentDay) ? state.baseStreak : effectiveStreak;
    }

    // -------------------------------------------------------------------------
    // View Data Assembly
    // -------------------------------------------------------------------------

    /**
     * @dev Shared helper for view functions to pack quest info/progress consistently.
     * @param quest The quest definition to pack.
     * @param state Player's quest state (can be empty for baseline views).
     * @param slot Slot index (0 or 1).
     * @param currentDay The active quest day.
     * @return info Packed QuestInfo struct.
     * @return progress Player's current progress (0 if invalid/stale).
     * @return completed True if player has completed this slot today.
     */
    function _questViewData(
        DailyQuest memory quest,
        PlayerQuestState memory state,
        uint8 slot,
        uint24 currentDay
    ) private view returns (QuestInfo memory info, uint128 progress, bool completed) {
        info = QuestInfo({
            day: quest.day,
            questType: quest.questType,
            highDifficulty: false,
            requirements: _questRequirements(quest, slot)
        });
        if (_questProgressValid(state, quest, slot, currentDay)) {
            progress = uint128(_toNativeProgress(quest.questType, _progressOfMem(state, slot)));
        }
        completed = _questCompleted(state, quest, slot);
    }

    /**
     * @dev Decode quest requirements (fixed targets, no tiers or difficulty variance).
     *      Different quest types use different requirement fields:
     *      - MINT_FLIP, FOIL → req.mints (small integer count)
     *      - MINT_ETH, LOOTBOX → req.tokenAmount (ETH wei)
     *      - FLIP, DECIMATOR, AFFILIATE → req.tokenAmount (FLIP base units)
     * @param quest The quest to calculate requirements for.
     * @return req Requirements struct with either mints count or tokenAmount.
     */
    function _questRequirements(DailyQuest memory quest, uint8 slot) private view returns (QuestRequirements memory req) {
        uint8 qType = quest.questType;
        if (qType == QUEST_TYPE_MINT_FLIP || qType == QUEST_TYPE_FOIL) {
            req.mints = uint32(_questTargetValue(quest, slot, 0));
        } else {
            uint256 currentPrice = 0;
            if (
                qType == QUEST_TYPE_MINT_ETH ||
                qType == QUEST_TYPE_LOOTBOX ||
                qType == QUEST_TYPE_DEGENERETTE_ETH
            ) {
                currentPrice = questGame.mintPrice();
            }
            req.tokenAmount = _toNativeProgress(qType, _questTargetValue(quest, slot, currentPrice));
        }
    }

    // -------------------------------------------------------------------------
    // Quest Lookup
    // -------------------------------------------------------------------------

    /**
     * @dev Returns the active quest of a given type for the current day, if present.
     * @param quests Memory array of active quests.
     * @param currentDay The current quest day.
     * @param questType The type to search for.
     * @return quest The matching quest (empty if not found).
     * @return slotIndex The slot index (type(uint8).max if not found).
     */
    function _currentDayQuestOfType(
        DailyQuest[QUEST_SLOT_COUNT] memory quests,
        uint24 currentDay,
        uint8 questType
    ) private pure returns (DailyQuest memory quest, uint8 slotIndex) {
        slotIndex = type(uint8).max; // Sentinel for "not found"
        for (uint8 slot; slot < QUEST_SLOT_COUNT; ) {
            DailyQuest memory candidate = quests[slot];
            if (candidate.day == currentDay && candidate.questType == questType) {
                quest = candidate;
                slotIndex = slot;
                return (quest, slotIndex);
            }
            unchecked {
                ++slot;
            }
        }
    }

    // -------------------------------------------------------------------------
    // Game State Queries
    // -------------------------------------------------------------------------

    /**
     * @dev Decimator quests are unlocked at specific level boundaries.
     *
     *      Availability Rules:
     *      1. decWindow() must be true (set by game during decimator windows)
     *      2. Level 100, 200, 300... (multiples of DECIMATOR_SPECIAL_LEVEL)
     *      3. Level 5, 15, 25, 35... ending in 5 (except 95, 195, etc.)
     * @return True if decimator quests can be rolled.
     */
    function _canRollDecimatorQuest() private view returns (bool) {
        IDegenerusGame game_ = questGame;
        if (!game_.decWindow()) return false;
        uint24 lvl = game_.level();
        // Always available at 100-level milestones
        if (lvl != 0 && (lvl % DECIMATOR_SPECIAL_LEVEL) == 0) return true;
        // Available at X5 levels (5, 15, 25, 35...) except X95
        if (lvl < 5) return false;
        return (lvl % 10) == 5 && (lvl % 100) != 95;
    }

    // -------------------------------------------------------------------------
    // Arithmetic Utilities
    // -------------------------------------------------------------------------

    /**
     * @dev Adds delta to current, clamping at uint128 max to prevent overflow.
     *      Uses unchecked block for gas efficiency since we manually handle overflow.
     * @param current The current progress value.
     * @param delta The amount to add.
     * @return The sum, capped at type(uint128).max.
     */
    function _clampedAdd128(uint128 current, uint256 delta) private pure returns (uint128) {
        unchecked {
            uint256 sum = uint256(current) + delta;
            if (sum > type(uint128).max) {
                sum = type(uint128).max;
            }
            return uint128(sum);
        }
    }

    /**
     * @dev Adds delta to a uint16 daily-progress field, clamping at uint16 max.
     *      All daily targets are <= 2000 stored units, so the clamp never blocks completion.
     */
    function _clampedAddU16(uint16 current, uint256 delta) private pure returns (uint16) {
        unchecked {
            uint256 sum = uint256(current) + delta;
            if (sum > type(uint16).max) {
                sum = type(uint16).max;
            }
            return uint16(sum);
        }
    }

    // -------------------------------------------------------------------------
    // Progress Unit Conversion
    // -------------------------------------------------------------------------
    // Daily progress is stored in a compact per-family unit so it fits uint16:
    //   ETH-value quests    -> milli-ETH   (wei / 1e15; target <= 500)
    //   FLIP-value quests -> whole FLIP (wei / 1e18; target = 2000)
    //   MINT_FLIP         -> ticket count (already a count; target = 1)
    // Accumulation converts the native delta to stored units before adding, and the
    // stored target compares against it like-for-like. View/event surfaces convert
    // back so the external ABI keeps reporting native wei / counts.

    /// @dev Stored-unit divisor for a quest family.
    function _progressUnit(uint8 questType) private pure returns (uint256) {
        if (
            questType == QUEST_TYPE_MINT_ETH ||
            questType == QUEST_TYPE_LOOTBOX ||
            questType == QUEST_TYPE_DEGENERETTE_ETH
        ) {
            return 1e15; // milli-ETH
        }
        if (questType == QUEST_TYPE_MINT_FLIP || questType == QUEST_TYPE_FOIL) {
            return 1; // ticket / foil-pack count
        }
        return 1e18; // whole FLIP: FLIP / DECIMATOR / AFFILIATE / DEGENERETTE_FLIP
    }

    /// @dev Native delta (wei / count) -> stored progress units. Truncates toward zero.
    function _toStoredProgress(uint8 questType, uint256 nativeDelta) private pure returns (uint256) {
        return nativeDelta / _progressUnit(questType);
    }

    /// @dev Stored progress units -> native (wei / count) for views and events.
    function _toNativeProgress(uint8 questType, uint256 storedAmount) private pure returns (uint256) {
        return storedAmount * _progressUnit(questType);
    }

    // -------------------------------------------------------------------------
    // Flattened Slot Accessors (progress / lastProgressDay, slot in {0,1})
    // -------------------------------------------------------------------------

    function _progressOf(PlayerQuestState storage s, uint8 slot) private view returns (uint16) {
        return slot == 0 ? s.progress0 : s.progress1;
    }

    function _setProgressOf(PlayerQuestState storage s, uint8 slot, uint16 v) private {
        if (slot == 0) {
            s.progress0 = v;
        } else {
            s.progress1 = v;
        }
    }

    function _progressOfMem(PlayerQuestState memory s, uint8 slot) private pure returns (uint16) {
        return slot == 0 ? s.progress0 : s.progress1;
    }

    function _lastProgressDayOf(PlayerQuestState storage s, uint8 slot) private view returns (uint24) {
        return slot == 0 ? s.lastProgressDay0 : s.lastProgressDay1;
    }

    function _setLastProgressDayOf(PlayerQuestState storage s, uint8 slot, uint24 v) private {
        if (slot == 0) {
            s.lastProgressDay0 = v;
        } else {
            s.lastProgressDay1 = v;
        }
    }

    function _lastProgressDayOfMem(PlayerQuestState memory s, uint8 slot) private pure returns (uint24) {
        return slot == 0 ? s.lastProgressDay0 : s.lastProgressDay1;
    }

    // -------------------------------------------------------------------------
    // Progress Handling
    // -------------------------------------------------------------------------

    /**
     * @dev Processes progress against a given quest slot, updating progress and returning rewards.
     * @param player Player address for event emission.
     * @param state Storage reference to player's quest state.
     * @param quests Memory copy of active quests (for pair completion check).
     * @param quest The specific quest being processed.
     * @param slot The slot index (0 or 1).
     * @param delta Progress delta to add (units depend on quest type).
     * @param target Target to complete the quest (units depend on quest type).
     * @param currentDay Current quest day (for paired completion checks).
     * @param mintPrice Cached mint price (wei) for daily ETH-based quests, 0 if unused.
     * @param handlerQuestType The quest type this handler tracks for level quest routing.
     * @param levelDelta Progress delta to forward to level quest handler (0 to skip).
     * @param levelQuestPrice Price for level quest target (level+1 price during purchase).
     * @return reward FLIP tokens earned (in base units).
     * @return questType The completed quest type.
     * @return streak Player's streak after completion.
     * @return completed True if completion was successful.
     */
    function _questHandleProgressSlot(
        address player,
        PlayerQuestState storage state,
        DailyQuest[QUEST_SLOT_COUNT] memory quests,
        DailyQuest memory quest,
        uint8 slot,
        uint256 delta,
        uint256 target,
        uint24 currentDay,
        uint256 mintPrice,
        uint8 handlerQuestType,
        uint256 levelDelta,
        uint256 levelQuestPrice
    ) private returns (uint256 reward, uint8 questType, uint32 streak, bool completed) {
        uint16 progressAfter = _clampedAddU16(
            _questSyncProgress(state, slot, quest.day),
            _toStoredProgress(quest.questType, delta)
        );
        _setProgressOf(state, slot, progressAfter);
        emit QuestProgressUpdated(
            player,
            quest.day,
            slot,
            quest.questType,
            uint128(_toNativeProgress(quest.questType, progressAfter)),
            _toNativeProgress(quest.questType, target)
        );
        _handleLevelQuestProgress(player, handlerQuestType, levelDelta, levelQuestPrice);
        if (progressAfter >= target) {
            if (_secondaryLocked(state, slot)) {
                return (0, quest.questType, state.streak, false);
            }
            return _questCompleteWithPair(player, state, quests, slot, quest, currentDay, mintPrice);
        }
        return (0, quest.questType, state.streak, false);
    }

    // -------------------------------------------------------------------------
    // State Synchronization
    // -------------------------------------------------------------------------

    /**
     * @dev Resets per-day bookkeeping and streak if a day was missed.
     *
     *      Streak Reset Logic:
     *      - Uses lastActiveDay if set (any slot completion), else lastCompletedDay
     *      - If gap > 1 day, streak resets unless shields cover every missed day
     *      - On new day, resets completionMask and snapshots baseStreak
     *
     *      baseStreak Snapshot:
     *      - Captures streak at start of day for consistent view rendering
     * @param state Storage reference to player's quest state.
     * @param player Player address for event emission and streak shield lookup.
     * @param currentDay The current quest day.
     */
    function _questSyncState(PlayerQuestState storage state, address player, uint24 currentDay) private {
        uint16 prevStreak = state.streak;
        uint24 anchorDay = state.lastActiveDay != 0 ? state.lastActiveDay : state.lastCompletedDay;
        if (anchorDay != 0 && currentDay > anchorDay + 1) {
            uint32 missedDays = currentDay - anchorDay - 1;
            uint16 shields = state.streakShield;
            if (shields != 0) {
                uint32 used = missedDays > uint32(shields) ? uint32(shields) : missedDays;
                state.streakShield = uint8(shields - uint16(used));
                if (used != 0) {
                    emit QuestStreakShieldUsed(
                        player,
                        uint16(used),
                        state.streakShield,
                        currentDay
                    );
                }
                if (missedDays > uint32(shields)) {
                    state.streak = 0; // Missed more days than shields available
                }
            } else {
                state.streak = 0; // Full miss (no quest completion) for at least one day
            }
        }
        if (prevStreak != 0 && state.streak == 0) {
            state.shieldCenturyHighWater = 0; // streak broke — re-arm so a genuine re-climb re-earns each century shield
            emit QuestStreakReset(player, prevStreak, currentDay);
        }
        uint24 currentDay24 = uint24(currentDay);
        if (state.lastSyncDay != currentDay24) {
            state.lastSyncDay = currentDay24;
            state.completionMask = 0;
            state.baseStreak = state.streak; // Snapshot for consistent rewards
        }
    }

    /**
     * @dev Syncs a slot's progress day-tag and returns the effective current progress.
     *      When the tracked day differs from the active day, stale progress is discarded:
     *      only the day tag is written here and 0 is returned — every caller
     *      unconditionally stores its updated progress right after, so the zero never
     *      needs its own store. A slot is only ever re-seeded on a day change
     *      (rollDailyQuest is idempotent per day), so the day tag alone invalidates
     *      stale progress — progress from a previous day cannot be applied to today's
     *      quest.
     * @param state Storage reference to player's quest state.
     * @param slot The slot index to sync.
     * @param currentDay The current quest day.
     * @return The effective progress base for the slot (0 when stale).
     */
    function _questSyncProgress(
        PlayerQuestState storage state,
        uint8 slot,
        uint24 currentDay
    ) private returns (uint16) {
        if (_lastProgressDayOf(state, slot) != currentDay) {
            _setLastProgressDayOf(state, slot, currentDay);
            return 0;
        }
        return _progressOf(state, slot);
    }

    /**
     * @dev Progress is only valid when it matches the active quest day.
     * @param state Player's quest state (memory copy for view functions).
     * @param quest The quest to validate against.
     * @param slot The slot index.
     * @param currentDay The current quest day.
     * @return True if progress is valid and should be displayed/used.
     */
    function _questProgressValid(
        PlayerQuestState memory state,
        DailyQuest memory quest,
        uint8 slot,
        uint24 currentDay
    ) private pure returns (bool) {
        if (quest.day == 0 || quest.day != currentDay) {
            return false;
        }
        uint24 questDay = uint24(quest.day);
        return _lastProgressDayOfMem(state, slot) == questDay;
    }

    /**
     * @dev Completion is bound to the quest day and per-slot completion mask.
     * @param state Player's quest state.
     * @param quest The quest to check.
     * @param slot The slot index.
     * @return True if this slot is marked complete for today.
     */
    function _questCompleted(
        PlayerQuestState memory state,
        DailyQuest memory quest,
        uint8 slot
    ) private pure returns (bool) {
        if (quest.day == 0) {
            return false;
        }
        uint24 questDay = uint24(quest.day);
        return state.lastSyncDay == questDay && (state.completionMask & uint8(1 << slot)) != 0;
    }

    /// @dev The secondary (slot 1) requires the primary (slot 0) completed that day — except
    ///      while afking, where the run's funded auto-buy stands in for the primary, so the
    ///      player can complete the secondary without a manual ETH mint.
    function _secondaryLocked(PlayerQuestState storage state, uint8 slot) private view returns (bool) {
        return slot == 1 && (state.completionMask & 1) == 0 && !state.afkingActive;
    }

    // -------------------------------------------------------------------------
    // Target Calculations
    // -------------------------------------------------------------------------

    /**
     * @dev Fixed targets by quest type (no tiers or difficulty variance).
     * @param quest The quest definition.
     * @param slot The slot index (0 or 1).
     * @param mintPrice Cached mint price in wei (0 if not applicable).
     * @return Target value in the same units as progress for that quest type.
     */
    function _questTargetValue(
        DailyQuest memory quest,
        uint8 slot,
        uint256 mintPrice
    ) private pure returns (uint256) {
        uint8 qType = quest.questType;
        uint256 nativeTarget;
        if (qType == QUEST_TYPE_MINT_ETH) {
            uint256 mult = slot == 0
                ? QUEST_DEPOSIT_ETH_TARGET_MULTIPLIER
                : QUEST_LOOTBOX_TARGET_MULTIPLIER;
            nativeTarget = mintPrice * mult;
            if (nativeTarget > QUEST_ETH_TARGET_CAP) nativeTarget = QUEST_ETH_TARGET_CAP;
        } else if (qType == QUEST_TYPE_LOOTBOX || qType == QUEST_TYPE_DEGENERETTE_ETH) {
            nativeTarget = mintPrice * QUEST_LOOTBOX_TARGET_MULTIPLIER;
            if (nativeTarget > QUEST_ETH_TARGET_CAP) nativeTarget = QUEST_ETH_TARGET_CAP;
        } else if (qType == QUEST_TYPE_MINT_FLIP) {
            nativeTarget = QUEST_MINT_TARGET;
        } else if (qType == QUEST_TYPE_FOIL) {
            nativeTarget = QUEST_FOIL_TARGET;
        } else if (
            qType == QUEST_TYPE_FLIP ||
            qType == QUEST_TYPE_DECIMATOR ||
            qType == QUEST_TYPE_AFFILIATE ||
            qType == QUEST_TYPE_DEGENERETTE_FLIP
        ) {
            nativeTarget = QUEST_FLIP_TARGET;
        } else {
            return 0;
        }
        // Convert to the stored unit that daily progress accumulates in (milli-ETH /
        // whole-FLIP / ticket count) so `progress >= target` compares like-for-like.
        return nativeTarget / _progressUnit(qType);
    }

    // -------------------------------------------------------------------------
    // Quest Type Selection
    // -------------------------------------------------------------------------

    /**
     * @dev Select the bonus quest type (slot 1), distinct from primary.
     *
     *      Key Differences from Primary:
     *      - Excludes the primary type (no duplicate quests)
     *      - Base weight is 1 for all types (more uniform)
     *      - FLIP gets 4x weight
     *      - MINT_FLIP is never rolled here — it is auto-assigned as the slot-1 daily on the first
     *        jackpot day (rollDailyQuest) and excluded from the random pool everywhere else
     *      - DEGENERETTE_ETH and DEGENERETTE_FLIP use base weight (1x)
     *      - Decimator gets 4x weight when allowed
     *      - Lootbox gets 3x weight
     * @param entropy VRF entropy (typically swapped halves of primary entropy).
     * @param primaryType The primary quest type (to exclude from selection).
     * @param decAllowed True if decimator quests can be rolled.
     * @return The selected quest type.
     */
    function _bonusQuestType(
        uint256 entropy,
        uint8 primaryType,
        bool decAllowed
    ) private pure returns (uint8) {
        uint16[QUEST_TYPE_COUNT] memory weights;
        uint16 total;

        for (uint8 candidate; candidate < QUEST_TYPE_COUNT; ) {
            // Skip primary type (no duplicates)
            if (candidate == primaryType) {
                unchecked {
                    ++candidate;
                }
                continue;
            }
            // Skip sentinel value 0 (unrolled marker) and FOIL (type 4) — FOIL is
            // forced onto slot 1 only on the first purchase day, never rolled randomly.
            if (candidate == 0 || candidate == QUEST_TYPE_FOIL) {
                unchecked {
                    ++candidate;
                }
                continue;
            }
            // Skip disabled types
            if (!decAllowed && candidate == QUEST_TYPE_DECIMATOR) {
                unchecked {
                    ++candidate;
                }
                continue;
            }
            // MINT_FLIP is never rolled randomly — it is auto-assigned as the slot-1 daily on the
            // first jackpot day (rollDailyQuest) and excluded from the pool everywhere else.
            if (candidate == QUEST_TYPE_MINT_FLIP) {
                unchecked {
                    ++candidate;
                }
                continue;
            }
            // Apply type-specific weights
            uint16 weight = 1;
            if (candidate == QUEST_TYPE_FLIP) {
                weight = 4;
            } else if (candidate == QUEST_TYPE_DECIMATOR && decAllowed) {
                weight = 4;
            } else if (candidate == QUEST_TYPE_LOOTBOX) {
                weight = 3;
            }

            weights[candidate] = weight;
            total += weight;

            unchecked {
                ++candidate;
            }
        }

        // Fallback if no valid types (shouldn't happen in practice)
        if (total == 0) {
            return primaryType == QUEST_TYPE_MINT_ETH ? QUEST_TYPE_AFFILIATE : QUEST_TYPE_MINT_ETH;
        }

        // Weighted random selection
        uint256 roll = entropy % uint256(total);
        for (uint8 candidate; candidate < QUEST_TYPE_COUNT; ) {
            uint16 weight = weights[candidate];
            if (weight != 0) {
                if (roll < weight) {
                    return candidate;
                }
                roll -= weight;
            }
            unchecked {
                ++candidate;
            }
        }

        return primaryType == QUEST_TYPE_MINT_ETH ? QUEST_TYPE_AFFILIATE : QUEST_TYPE_MINT_ETH;
    }

    // -------------------------------------------------------------------------
    // Quest Completion & Rewards
    // -------------------------------------------------------------------------

    /**
     * @dev Completes a quest slot, credits the streak, and returns rewards.
     *
     *      Streak Logic:
     *      - Each slot completion adds +1 (slots are deduped to once per day by completionMask)
     *      - Off a run both slots credit `state.streak`; while afking slot 0 is streak-neutral
     *        and slot 1 bumps the afking sub's streak base via recordAfkingSecondary
     *      - lastCompletedDay updates only on the primary (slot 0), keying the reset to it
     *
     *      Reward Calculation:
     *      - Slot 0 (deposit ETH) pays a fixed 100 FLIP
     *      - Slot 1 (random quest) pays a fixed 200 FLIP
     * @param state Storage reference to player's quest state.
     * @param slot The slot index being completed.
     * @param quest The quest being completed.
     * @return reward FLIP tokens earned (in base units).
     * @return questType The completed quest type.
     * @return streak Player's streak after completion.
     * @return completed True if completion was successful.
     */
    function _questComplete(
        address player,
        PlayerQuestState storage state,
        uint8 slot,
        DailyQuest memory quest
    )
        private
        returns (uint256 reward, uint8 questType, uint32 streak, bool completed)
    {
        uint8 mask = state.completionMask;
        uint8 slotMask = uint8(1 << slot);

        // Already completed this slot today
        if ((mask & slotMask) != 0) {
            return (0, quest.questType, state.streak, false);
        }

        // While afking, the compute-on-read owns the streak (off the Game-side Sub slot), so
        // a completion of EITHER slot is streak-neutral here, and the slot-0 reward is the
        // per-delivered-day pendingFlip accrual (paying it here too would double-credit). The
        // slot-1 (manual) quest stays fully accessible and pays its reward normally.
        bool afking = state.afkingActive;

        // Mark slot as complete
        mask |= slotMask;
        uint24 questDay24 = uint24(quest.day);
        // `lastActiveDay` tracks ONLY a normal funded mint (slot 0 is always MINT_ETH) — a
        // slot-1 completion never advances it. This keeps it the honest "last funded manual
        // mint day": the afking finalize's no-zero protection keys on max(afkCovered,
        // lastActiveDay), so a cheap slot-1 quest can no longer hold a lapsed afking streak
        // alive. During an active afking run with no manual mint, lastActiveDay stays put and
        // the afking machinery (afkCoveredThroughDay) carries the streak.
        if (slot == 0 && questDay24 > state.lastActiveDay) {
            state.lastActiveDay = questDay24;
        }
        // Persist the completion before the afking Sub-bump's external call (clean CEI; the
        // callback makes no re-entrant call into this contract).
        state.completionMask = mask;

        uint32 newStreak = uint32(state.streak);

        // Every quest completion adds to the streak; each slot completes at most once per day
        // (the completionMask check above dedups), so the primary and the secondary credit
        // independently. Off a run, both credit the manual `state.streak`. While afking the
        // compute-on-read streak owns the run: the PRIMARY rides the funded delivered days (slot 0
        // stays streak-neutral here) and a SECONDARY the player completes bumps the Sub streak base
        // via recordAfkingSecondary, so the run's unified score reflects it. lastCompletedDay tracks
        // only the primary, keeping the missed-day reset keyed to it.
        if (!afking) {
            if (newStreak < type(uint16).max) {
                newStreak += 1;
            }
            state.streak = uint16(newStreak);
            _grantCenturyShield(player, state);
            if (slot == 0) {
                state.lastCompletedDay = questDay24;
            }
        } else if (slot == 1) {
            questGame.recordAfkingSecondary(player, 1);
        }

        uint256 rewardShare = slot == 1
            ? QUEST_RANDOM_REWARD
            : (afking ? 0 : QUEST_SLOT0_REWARD);
        emit QuestCompleted(
            player,
            quest.day,
            slot,
            quest.questType,
            newStreak,
            rewardShare
        );
        return (rewardShare, quest.questType, newStreak, true);
    }

    /**
     * @dev Completes a quest and checks if the paired quest can also complete.
     *      This function enables "combo completion" where completing one quest
     *      can automatically complete the other if its progress already meets target.
     *      This is a UX optimization to avoid requiring separate transactions.
     * @param state Storage reference to player's quest state.
     * @param quests Memory copy of active quests.
     * @param slot The slot being completed.
     * @param quest The quest being completed.
     * @param currentDay Current quest day for pair checks.
     * @param mintPrice Optional cached mint price in wei for ETH-based quests (0 to fetch).
     * @return reward FLIP tokens earned (in base units).
     * @return questType The completed quest type.
     * @return streak Player's streak after completion.
     * @return completed True if completion was successful.
     */
    function _questCompleteWithPair(
        address player,
        PlayerQuestState storage state,
        DailyQuest[QUEST_SLOT_COUNT] memory quests,
        uint8 slot,
        DailyQuest memory quest,
        uint24 currentDay,
        uint256 mintPrice
    )
        private
        returns (uint256 reward, uint8 questType, uint32 streak, bool completed)
    {
        (reward, questType, streak, completed) = _questComplete(
            player,
            state,
            slot,
            quest
        );
        if (!completed) {
            return (reward, questType, streak, false);
        }

        // A slot-1 completion is only reachable once slot 0 is already completed
        // (every caller gates on completionMask bit 0), so there is no other slot
        // left to complete.
        if (slot == 1) {
            return (reward, questType, streak, true);
        }

        // Check the other slot; if it already meets the target, complete it now
        uint8 otherSlot = slot ^ 1; // XOR to flip 0↔1
        (
            uint256 extraReward,
            uint8 extraType,
            uint32 extraStreak,
            bool extraCompleted
        ) = _maybeCompleteOther(player, state, quests, otherSlot, currentDay, mintPrice);

        // Aggregate rewards from paired completion
        if (extraCompleted) {
            reward += extraReward;
            questType = extraType;
            streak = extraStreak;
        }
        // completed is already true if we reached here
        return (reward, questType, streak, true);
    }

    /**
     * @dev Attempts to complete the other slot if its progress meets the target.
     * @param state Storage reference to player's quest state.
     * @param quests Memory copy of active quests.
     * @param slot The slot to check for completion.
     * @param currentDay Current quest day for validation.
     * @param mintPrice Optional cached mint price in wei for ETH-based quests (0 to fetch).
     * @return reward FLIP tokens earned (in base units).
     * @return questType The completed quest type.
     * @return streak Player's streak after completion.
     * @return completed True if completion was successful.
     */
    function _maybeCompleteOther(
        address player,
        PlayerQuestState storage state,
        DailyQuest[QUEST_SLOT_COUNT] memory quests,
        uint8 slot,
        uint24 currentDay,
        uint256 mintPrice
    )
        private
        returns (uint256 reward, uint8 questType, uint32 streak, bool completed)
    {
        DailyQuest memory quest = quests[slot];

        // Skip if quest is not for today
        if (quest.day == 0 || quest.day != currentDay) {
            return (0, quest.questType, state.streak, false);
        }
        // Skip if already completed
        if ((state.completionMask & uint8(1 << slot)) != 0) {
            return (0, quest.questType, state.streak, false);
        }

        if (!_questReady(state, quest, slot, mintPrice)) {
            return (0, quest.questType, state.streak, false);
        }

        return _questComplete(player, state, slot, quest);
    }

    /**
     * @dev Checks if a quest slot's progress meets or exceeds the target.
     * @param state Storage reference to player's quest state.
     * @param quest The quest to check.
     * @param slot The slot index.
     * @param mintPrice Optional cached mint price in wei for ETH-based quests (0 to fetch).
     * @return True if progress >= target.
     */
    function _questReady(
        PlayerQuestState storage state,
        DailyQuest memory quest,
        uint8 slot,
        uint256 mintPrice
    ) private view returns (bool) {
        // The sole caller (_maybeCompleteOther) has already verified
        // quest.day == currentDay != 0, so progress freshness only needs the
        // player's day-tag to match the quest day.
        if (_lastProgressDayOf(state, slot) != quest.day) return false;
        uint256 progress = _progressOf(state, slot);
        uint256 currentPrice = mintPrice;
        if (
            currentPrice == 0 &&
            (
                quest.questType == QUEST_TYPE_MINT_ETH ||
                quest.questType == QUEST_TYPE_LOOTBOX ||
                quest.questType == QUEST_TYPE_DEGENERETTE_ETH
            )
        ) {
            currentPrice = questGame.mintPrice();
        }
        uint256 target = _questTargetValue(quest, slot, currentPrice);
        if (target == 0) return false;
        return progress >= target;
    }

    // -------------------------------------------------------------------------
    // Quest Seeding
    // -------------------------------------------------------------------------

    /**
     * @dev Seeds a quest slot with a new quest definition (in memory; the caller
     *      persists the pair via `_storeActiveQuests`). The new day tag invalidates
     *      any stale player progress.
     * @param quest Memory reference to the quest slot being composed.
     * @param day The quest day identifier.
     * @param questType The quest type to seed.
     */
    function _seedQuestType(
        DailyQuest memory quest,
        uint24 day,
        uint8 questType
    ) private pure {
        quest.day = day;
        quest.questType = questType;
    }

    /**
     * @dev Helper to read the active day from either slot.
     * @param quests Memory array of active quests.
     * @return The current quest day (prefers slot 0 if both are set).
     */
    function _currentQuestDay(DailyQuest[QUEST_SLOT_COUNT] memory quests) private pure returns (uint24) {
        uint24 day0 = quests[0].day;
        if (day0 != 0) return day0;
        return quests[1].day;
    }

    // =========================================================================
    //                         LEVEL QUESTS
    // =========================================================================

    /// @notice Roll the level quest for the current level.
    /// @dev Selects a quest type, bumps version to invalidate stale player progress.
    /// @param entropy VRF-derived entropy for quest type selection.
    function rollLevelQuest(uint256 entropy) external override onlyGame {
        bool decAllowed = _canRollDecimatorQuest();
        levelQuestType = _bonusQuestType(entropy, type(uint8).max, decAllowed);
        unchecked { ++levelQuestVersion; }
    }

    /// @dev Checks if a player is eligible for the level quest.
    ///      Requires (levelStreak >= 5 OR any active pass) AND (levelUnits >= 4 this level).
    /// @param player The player address to check.
    /// @param lvl The current game level (fetched once by the caller).
    /// @return True if the player meets both gates.
    function _isLevelQuestEligible(address player, uint24 lvl) internal view returns (bool) {
        uint256 packed = questGame.mintPackedFor(player);

        // Activity gate: 4+ units minted this level
        uint24 unitsLvl = uint24(packed >> 104);
        if (unitsLvl != lvl + 1) return false;
        uint16 units = uint16(packed >> 228);
        if (units < 4) return false;

        // Loyalty gate: levelStreak >= 5 OR any active pass
        uint24 streak = uint24(packed >> 48);
        if (streak >= 5) return true;

        // Whale/lazy pass from mintPacked_
        uint24 frozen = uint24(packed >> 128);
        uint8 passType = uint8((packed >> 152) & 0x3);
        if (frozen > 0 && passType != 0) return true;

        // Deity pass fallback (separate SLOAD)
        return questGame.hasDeityPass(player);
    }

    /// @dev Returns the 10x target for a level quest type.
    ///      MINT_FLIP targets 10 tickets, MINT_ETH targets mintPrice * 10,
    ///      LOOTBOX and DEGENERETTE_ETH target mintPrice * 20,
    ///      FLIP-denominated types target 20,000 FLIP.
    ///      No ETH cap applied (unlike daily quests).
    /// @param questType The quest type constant (1-9, 0 reserved as unrolled sentinel).
    /// @param mintPrice Current mint price in wei.
    /// @return Target value in the same units as handler progress deltas.
    function _levelQuestTargetValue(uint8 questType, uint256 mintPrice) internal pure returns (uint256) {
        if (questType == QUEST_TYPE_MINT_FLIP) return 10;
        if (questType == QUEST_TYPE_MINT_ETH) return mintPrice * 10;
        if (questType == QUEST_TYPE_LOOTBOX || questType == QUEST_TYPE_DEGENERETTE_ETH) {
            return mintPrice * 20;
        }
        if (
            questType == QUEST_TYPE_FLIP ||
            questType == QUEST_TYPE_DECIMATOR ||
            questType == QUEST_TYPE_AFFILIATE ||
            questType == QUEST_TYPE_DEGENERETTE_FLIP
        ) {
            return 20_000 ether;
        }
        return 0;
    }

    /// @dev Shared level quest progress handler called by each of the 6 handlers.
    ///      Reads levelQuestType and levelQuestVersion (packed in one slot)
    ///      to get both level and type. Short-circuits on type mismatch before any
    ///      player state read. Eligibility is deferred to the completion boundary —
    ///      ineligible players accumulate phantom progress that can never complete.
    /// @param player The player earning progress.
    /// @param handlerQuestType The quest type this handler tracks.
    /// @param delta The progress delta (units match quest type).
    /// @param mintPrice Current mint price in wei (for ETH-based targets; 0 for FLIP types).
    function _handleLevelQuestProgress(
        address player,
        uint8 handlerQuestType,
        uint256 delta,
        uint256 mintPrice
    ) internal {
        uint8 lqType = levelQuestType;

        // Type mismatch or no quest active — exit before any player SLOAD
        if (lqType != handlerQuestType) return;

        uint8 currentVersion = levelQuestVersion;
        uint256 packed = levelQuestPlayerState[player];
        uint8 playerVersion = uint8(packed);

        // Version mismatch: reset stale progress from previous level's quest
        if (playerVersion != currentVersion) {
            packed = uint256(currentVersion);
        }

        // Already completed this level's quest
        if ((packed >> 136) & 1 == 1) return;

        uint128 progress = uint128(packed >> 8);
        progress = _clampedAdd128(progress, delta);

        uint256 target = _levelQuestTargetValue(lqType, mintPrice);
        if (uint256(progress) >= target) {
            // Gate eligibility only at completion; the level is fetched once and
            // shared with the completion event.
            uint24 lvl = questGame.level();
            if (!_isLevelQuestEligible(player, lvl)) {
                packed = uint256(currentVersion) | (uint256(progress) << 8);
                levelQuestPlayerState[player] = packed;
                return;
            }
            packed = uint256(currentVersion)
                   | (uint256(progress) << 8)
                   | (uint256(1) << 136);
            levelQuestPlayerState[player] = packed;

            // Level-quest completion advances the quest streak by LEVEL_QUEST_STREAK_BONUS (a daily
            // quest is +1) without touching the primary reset anchor (lastActiveDay), so the
            // missed-day reset stays keyed to the daily primary. Off a run it credits the manual
            // streak (saturating at uint16 max, mirroring awardQuestStreakBonus); while afking it
            // bumps the Sub streak base by the same amount so the unified score reflects it. The
            // calling handler synced the player state for the current day before this runs.
            PlayerQuestState storage qs = questPlayerState[player];
            if (qs.afkingActive) {
                questGame.recordAfkingSecondary(player, LEVEL_QUEST_STREAK_BONUS);
            } else {
                uint32 bumped = uint32(qs.streak) + LEVEL_QUEST_STREAK_BONUS;
                qs.streak = bumped > type(uint16).max ? type(uint16).max : uint16(bumped);
                _grantCenturyShield(player, qs);
            }

            coinflip.creditFlip(player, 800 ether);
            emit LevelQuestCompleted(player, lvl + 1, lqType, 800 ether);
        } else {
            packed = uint256(currentVersion) | (uint256(progress) << 8);
            levelQuestPlayerState[player] = packed;
        }
    }

    /// @notice Returns a player's level quest state for frontend display.
    /// @dev Reads levelQuestType, levelQuestVersion, and levelQuestPlayerState for the player's current level.
    /// @param player The player address to query.
    function getPlayerLevelQuestView(address player)
        external
        view
        override
        returns (uint8 questType, uint128 progress, uint256 target, bool completed, bool eligible)
    {
        questType = levelQuestType;

        uint256 packed = levelQuestPlayerState[player];
        uint8 playerVersion = uint8(packed);

        if (playerVersion == levelQuestVersion && questType != 0) {
            progress = uint128(packed >> 8);
            completed = (packed >> 136) & 1 == 1;
        }

        target = _levelQuestTargetValue(questType, questGame.mintPrice());
        eligible = _isLevelQuestEligible(player, questGame.level());
    }
}
