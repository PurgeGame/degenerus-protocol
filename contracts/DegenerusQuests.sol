// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import "./interfaces/IDegenerusQuests.sol";
import "./interfaces/IDegenerusGame.sol";
import {IBurnieCoinflip} from "./interfaces/IBurnieCoinflip.sol";
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
 *   2. Per-player progress tracking with version-gated resets
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
 * 5. Progress accumulates until target is met; completing either slot credits streak once per day
 *
 * Progress Versioning
 * -----------------------------------------------------------------------------
 * Each quest has a monotonic `version` field. When a quest is seeded for a new day,
 * the version bumps and stale player progress is automatically reset via
 * `_questSyncProgress`.
 *
 * Streak System
 * -----------------------------------------------------------------------------
 * • Streaks increment on the first quest completion of a day
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
        uint32 indexed day,
        uint8 indexed slot,
        uint8 questType,
        uint8 flags,
        uint24 version
    );

    /// @notice Emitted when player quest progress is updated.
    event QuestProgressUpdated(
        address indexed player,
        uint32 indexed day,
        uint8 indexed slot,
        uint8 questType,
        uint128 progress,
        uint256 target
    );

    /// @notice Emitted when a quest slot is completed.
    event QuestCompleted(
        address indexed player,
        uint32 indexed day,
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
        uint32 currentDay
    );

    /// @notice Emitted when quest streak is manually increased.
    event QuestStreakBonusAwarded(
        address indexed player,
        uint16 amount,
        uint24 newStreak,
        uint32 currentDay
    );

    /// @notice Emitted when quest streak resets due to missed days.
    event QuestStreakReset(
        address indexed player,
        uint24 previousStreak,
        uint32 currentDay
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

    /// @dev Price unit for reward calculations (1000 BURNIE).
    uint256 private constant PRICE_COIN_UNIT = 1000 ether;

    // -------------------------------------------------------------------------
    // Quest Type Constants
    // -------------------------------------------------------------------------

    /// @dev Number of concurrent quest slots per day.
    uint8 private constant QUEST_SLOT_COUNT = 2;

    /// @dev Fixed reward for the slot 0 quest.
    uint256 private constant QUEST_SLOT0_REWARD = 100 ether;

    /// @dev Fixed reward for the random (slot 1) quest.
    uint256 private constant QUEST_RANDOM_REWARD = 200 ether;

    /// @dev Quest type: mint tickets using ETH.
    uint8 private constant QUEST_TYPE_MINT_ETH = 1;

    /// @dev Quest type: stake BURNIE in the coinflip mechanism.
    uint8 private constant QUEST_TYPE_FLIP = 2;

    /// @dev Quest type: earn affiliate commissions.
    uint8 private constant QUEST_TYPE_AFFILIATE = 3;

    /// @dev Retired quest type id kept reserved for compatibility.
    uint8 private constant QUEST_TYPE_RESERVED = 4;

    /// @dev Quest type: participate in decimator burns.
    uint8 private constant QUEST_TYPE_DECIMATOR = 5;

    /// @dev Quest type: purchase loot boxes.
    uint8 private constant QUEST_TYPE_LOOTBOX = 6;

    /// @dev Quest type: place Degenerette bets using ETH.
    uint8 private constant QUEST_TYPE_DEGENERETTE_ETH = 7;

    /// @dev Quest type: place Degenerette bets using BURNIE.
    uint8 private constant QUEST_TYPE_DEGENERETTE_BURNIE = 8;

    /// @dev Quest type: mint tickets using BURNIE tokens. Value 9 avoids collision
    ///      with Solidity's default mapping value (0), which signals "no quest rolled".
    uint8 private constant QUEST_TYPE_MINT_BURNIE = 9;

    /// @dev Total number of quest types for iteration bounds.
    uint8 private constant QUEST_TYPE_COUNT = 10;

    // -------------------------------------------------------------------------
    // Streak Constants
    // -------------------------------------------------------------------------

    /// @dev Flag bit indicating streak was already credited this day.
    uint8 private constant QUEST_STATE_STREAK_CREDITED = 1 << 7;

    // -------------------------------------------------------------------------
    // Quest Targets (fixed)
    // -------------------------------------------------------------------------

    /// @dev Fixed mint target in whole tickets (1 ticket = 1000 BURNIE).
    uint32 private constant QUEST_MINT_TARGET = 1;

    /// @dev Fixed BURNIE target for flip/affiliate/decimator quests (2x price in BURNIE).
    uint256 private constant QUEST_BURNIE_TARGET = 2 * PRICE_COIN_UNIT;

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
    IBurnieCoinflip internal constant coinflip = IBurnieCoinflip(ContractAddresses.COINFLIP);

    // =========================================================================
    //                                 STRUCTS
    // =========================================================================

    /**
     * @notice Definition of a quest that is active for the current day.
     * @dev Stored in the `activeQuests` array (one per slot).
     *
     * Layout (memory):
     * +-------------+----------+-------+---------+
     * | day (32b)   | type(8b) | flags | version |
     * +-------------+----------+-------+---------+
     *
     * Version Semantics:
     * - Increments when quest is first seeded each day
     * - Player progress is invalidated when version mismatches
     */
    struct DailyQuest {
        uint32 day;       // Quest day identifier (derived by caller, not block timestamp)
        uint8 questType;  // One of the QUEST_TYPE_* constants
        uint8 flags;      // Difficulty flags (HIGH/VERY_HIGH)
        uint24 version;     // Bumped when quest mutates mid-day to reset stale player progress
        // 16 bits free
    }

    /**
     * @notice Progress and streak bookkeeping per player.
     * @dev Stored per-player in `questPlayerState` mapping.
     *
     * Streak Mechanics:
     * - `streak` increments on the first quest slot completion of a day (not both)
     * - `baseStreak` snapshots streak at day start for consistent view rendering
     * - `lastActiveDay` tracks any slot completion (not just full completion)
     * - Missing a day (gap > 1 between lastActiveDay and currentDay) resets streak
     *
     * Progress Versioning:
     * - `lastProgressDay[slot]` and `lastQuestVersion[slot]` must match active quest
     * - Mismatch triggers automatic progress reset via `_questSyncProgress`
     *
     * Completion Mask Layout:
     * +---------------------------------+---------+---------+
     * | bit 7: STREAK_CREDITED          | bit 1   | bit 0   |
     * | (prevents double streak credit) | slot 1  | slot 0  |
     * +---------------------------------+---------+---------+
     */
    struct PlayerQuestState {
        uint24 lastCompletedDay;                    // Last day where a streak was credited (first slot completion)
        uint24 lastActiveDay;                       // Last day where ANY quest slot completed
        uint24 streak;                              // Current streak of days with full completion
        uint24 baseStreak;                          // Snapshot of streak at start of day (for rewards)
        uint24 lastSyncDay;                         // Day we last reset progress/completionMask
        uint24[QUEST_SLOT_COUNT] lastProgressDay;   // Per-slot: day when progress was recorded
        uint24[QUEST_SLOT_COUNT] lastQuestVersion;  // Per-slot: quest version when progress was recorded
        uint128[QUEST_SLOT_COUNT] progress;         // Per-slot: accumulated progress toward targets
        uint8 completionMask;                       // Bits 0-1: slot completion; bit 7: streak credited
    }

    // =========================================================================
    //                              QUEST STORAGE
    // =========================================================================

    /// @notice Active quests for the current day (indexed by slot 0/1).
    DailyQuest[QUEST_SLOT_COUNT] private activeQuests;

    /// @notice Per-player quest state including progress and streak.
    mapping(address => PlayerQuestState) private questPlayerState;

    /// @notice Quest streak shields per player (stackable, consumed on missed days).
    mapping(address => uint16) private questStreakShieldCount;

    /// @notice Monotonically increasing version counter for daily quest invalidation.
    uint24 private questVersionCounter = 1;

    /// @notice Active level quest type (1-9). Zero means no quest active.
    ///         Zeroed at level transition RNG request, set when RNG arrives.
    ///         Packs with questVersionCounter and levelQuestVersion in one slot.
    uint8 private levelQuestType;

    /// @notice Version counter for level quest invalidation. Bumps on each rollLevelQuest.
    ///         Player state stores this value; mismatch resets progress + completed.
    uint8 private levelQuestVersion;

    /// @notice Per-player level quest state.
    ///         Packed: version (8b) | progress (128b) | completed (1b at bit 136).
    mapping(address => uint256) private levelQuestPlayerState;

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

    /// @notice Roll the daily quest set. Slot 0 is always MINT_ETH; slot 1 is random.
    /// @dev Idempotent per day. Called by AdvanceModule when RNG word is available.
    /// @param day Quest day identifier.
    /// @param entropy VRF entropy word.
    function rollDailyQuest(uint32 day, uint256 entropy) external onlyGame {
        DailyQuest[QUEST_SLOT_COUNT] storage quests = activeQuests;
        if (quests[0].day == day) return;

        // Slot 0: always MINT_ETH — just bump day+version
        _seedQuestType(quests[0], day, QUEST_TYPE_MINT_ETH);

        // Slot 1: weighted random (distinct from slot 0)
        uint256 bonusEntropy = (entropy >> 128) | (entropy << 128);
        uint8 bonusType = _bonusQuestType(
            bonusEntropy,
            QUEST_TYPE_MINT_ETH,
            _canRollDecimatorQuest()
        );
        _seedQuestType(quests[1], day, bonusType);

        emit QuestSlotRolled(day, 0, QUEST_TYPE_MINT_ETH, 0, quests[0].version);
        emit QuestSlotRolled(day, 1, bonusType, 0, quests[1].version);
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
    function awardQuestStreakBonus(address player, uint16 amount, uint32 currentDay) external onlyGame {
        if (player == address(0) || amount == 0 || currentDay == 0) return;

        PlayerQuestState storage state = questPlayerState[player];
        _questSyncState(state, player, currentDay);

        uint24 prevStreak = state.streak;
        uint32 updated = uint32(prevStreak) + uint32(amount);
        if (updated > type(uint24).max) {
            state.streak = type(uint24).max;
        } else {
            state.streak = uint24(updated);
        }

        uint24 currentDay24 = uint24(currentDay);
        if (state.lastActiveDay < currentDay24) {
            state.lastActiveDay = currentDay24;
        }
        emit QuestStreakBonusAwarded(player, amount, state.streak, currentDay);
    }

    // =========================================================================
    //                      PROGRESS HANDLERS (COIN-ONLY)
    // =========================================================================
    // All handle* functions follow a common pattern:
    // 1. Early-exit if player/amount invalid or no active quest day
    // 2. Sync player state (reset streak if day missed, snapshot baseStreak)
    // 3. Find matching quest slot for the action type
    // 4. Sync slot progress (reset if day/version changed)
    // 5. Accumulate progress and check against fixed target
    // 6. On completion, credit rewards and check if other slot also completes
    //
    // Return values are consistent across all handlers:
    // - reward: BURNIE tokens to credit (in base units, 18 decimals)
    // - questType: The type of quest that was processed
    // - streak: Player's current streak after this action
    // - completed: True if a quest was completed by this action

    /**
     * @notice Handle mint progress for a player; covers both BURNIE and ETH paid mints.
     * @dev Access: COIN or COINFLIP contract only.
     *      Iterates both slots since both could theoretically match (though in practice
     *      the rolling logic ensures only one slot has each mint type).
     * @param player The player who performed the mint.
     * @param quantity Number of tickets minted.
     * @param paidWithEth True if ETH was used (MINT_ETH quest), false for BURNIE (MINT_BURNIE).
     * @return reward BURNIE tokens earned (in base units, 18 decimals).
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
        DailyQuest[QUEST_SLOT_COUNT] memory quests = activeQuests;
        uint32 currentDay = _currentQuestDay(quests);
        PlayerQuestState storage state = questPlayerState[player];
        if (player == address(0) || quantity == 0 || currentDay == 0) {
            return (0, quests[0].questType, state.streak, false);
        }

        _questSyncState(state, player, currentDay);

        uint256 totalReward;
        bool anyCompleted;
        uint8 outQuestType = paidWithEth ? QUEST_TYPE_MINT_ETH : QUEST_TYPE_MINT_BURNIE;
        uint32 outStreak = state.streak;

        // Check both slots for matching mint quest type.
        // Level quest progress is batched into the first matching slot call;
        // subsequent slots pass zero levelDelta to avoid double-counting.
        bool levelQuestHandled;
        for (uint8 slot; slot < QUEST_SLOT_COUNT; ) {
            DailyQuest memory quest = quests[slot];
            if (quest.day != currentDay) {
                unchecked {
                    ++slot;
                }
                continue;
            }
            if (
                (!paidWithEth && quest.questType == QUEST_TYPE_MINT_BURNIE) ||
                (paidWithEth && quest.questType == QUEST_TYPE_MINT_ETH)
            ) {
                outQuestType = quest.questType;
                if (paidWithEth) {
                    uint256 delta = uint256(quantity) * mintPrice;
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
                        QUEST_TYPE_MINT_ETH,
                        levelQuestHandled ? 0 : delta,
                        mintPrice
                    );
                } else {
                    uint256 target = _questTargetValue(quest, slot, mintPrice);
                    (reward, questType, streak, completed) = _questHandleProgressSlot(
                        player,
                        state,
                        quests,
                        quest,
                        slot,
                        quantity,
                        target,
                        currentDay,
                        mintPrice,
                        QUEST_TYPE_MINT_BURNIE,
                        levelQuestHandled ? 0 : quantity,
                        mintPrice
                    );
                }
                levelQuestHandled = true;
                if (completed) {
                    totalReward += reward;
                    outQuestType = questType;
                    outStreak = streak;
                    anyCompleted = true;
                }
            }
            unchecked {
                ++slot;
            }
        }
        // If no daily quest slot matched, still credit level quest progress
        if (!levelQuestHandled) {
            if (paidWithEth) {
                _handleLevelQuestProgress(player, QUEST_TYPE_MINT_ETH, uint256(quantity) * mintPrice, mintPrice);
            } else {
                _handleLevelQuestProgress(player, QUEST_TYPE_MINT_BURNIE, quantity, 0);
            }
        }
        if (anyCompleted) {
            if (!paidWithEth && totalReward != 0) {
                coinflip.creditFlip(player, totalReward);
            }
            return (totalReward, outQuestType, outStreak, true);
        }
        return (0, outQuestType, state.streak, false);
    }

    /**
     * @notice Handle flip/unstake progress credited in BURNIE base units (18 decimals).
     * @dev Access: COIN or COINFLIP contract only.
     *      Progress tracks cumulative flip volume for the day.
     * @param player The player who staked/unstaked.
     * @param flipCredit Amount of BURNIE staked/unstaked (in base units).
     * @return reward BURNIE tokens earned (in base units, 18 decimals).
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
        DailyQuest[QUEST_SLOT_COUNT] memory quests = activeQuests;
        uint32 currentDay = _currentQuestDay(quests);
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

        _questSyncProgress(state, slotIndex, currentDay, quest.version);
        uint128 progressAfter = _clampedAdd128(state.progress[slotIndex], flipCredit);
        state.progress[slotIndex] = progressAfter;
        uint256 target = _questTargetValue(quest, slotIndex, 0);
        emit QuestProgressUpdated(
            player,
            currentDay,
            slotIndex,
            quest.questType,
            progressAfter,
            target
        );
        if (progressAfter < target) {
            return (0, quest.questType, state.streak, false);
        }
        if (slotIndex == 1 && (state.completionMask & 1) == 0) {
            return (0, quest.questType, state.streak, false);
        }

        return _questCompleteWithPair(player, state, quests, slotIndex, quest, currentDay, 0);
    }

    /**
     * @notice Handle decimator burns counted in BURNIE base units (18 decimals).
     * @dev Access: COIN or COINFLIP contract only.
     *      Decimator quests share the same BURNIE target as flip quests (2000 BURNIE).
     * @param player The player who performed the decimator burn.
     * @param burnAmount Amount of BURNIE burned (in base units).
     * @return reward BURNIE tokens earned (in base units, 18 decimals).
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
        DailyQuest[QUEST_SLOT_COUNT] memory quests = activeQuests;
        uint32 currentDay = _currentQuestDay(quests);
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
        _questSyncProgress(state, slotIndex, currentDay, quest.version);
        state.progress[slotIndex] = _clampedAdd128(state.progress[slotIndex], burnAmount);
        uint256 target = _questTargetValue(quest, slotIndex, 0);
        emit QuestProgressUpdated(
            player,
            currentDay,
            slotIndex,
            quest.questType,
            state.progress[slotIndex],
            target
        );
        if (state.progress[slotIndex] < target) {
            return (0, quest.questType, state.streak, false);
        }
        if (slotIndex == 1 && (state.completionMask & 1) == 0) {
            return (0, quest.questType, state.streak, false);
        }
        (reward, questType, streak, completed) = _questCompleteWithPair(player, state, quests, slotIndex, quest, currentDay, 0);
        if (completed && reward != 0) {
            coinflip.creditFlip(player, reward);
        }
    }

    /**
     * @notice Handle affiliate earnings credited in BURNIE base units (18 decimals).
     * @dev Access: COIN or COINFLIP contract only.
     * @param player The affiliate who earned commission.
     * @param amount BURNIE earned from affiliate referrals (in base units).
     * @return reward BURNIE tokens earned (in base units, 18 decimals).
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
        DailyQuest[QUEST_SLOT_COUNT] memory quests = activeQuests;
        uint32 currentDay = _currentQuestDay(quests);
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
        _questSyncProgress(state, slotIndex, currentDay, quest.version);
        state.progress[slotIndex] = _clampedAdd128(state.progress[slotIndex], amount);
        uint256 target = _questTargetValue(quest, slotIndex, 0);
        emit QuestProgressUpdated(
            player,
            currentDay,
            slotIndex,
            quest.questType,
            state.progress[slotIndex],
            target
        );
        if (state.progress[slotIndex] < target) {
            return (0, quest.questType, state.streak, false);
        }
        if (slotIndex == 1 && (state.completionMask & 1) == 0) {
            return (0, quest.questType, state.streak, false);
        }
        return _questCompleteWithPair(player, state, quests, slotIndex, quest, currentDay, 0);
    }

    /**
     * @notice Handle loot box purchase progress in ETH value (wei).
     * @dev Access: COIN or COINFLIP contract only.
     *      Loot box quests track cumulative ETH spent on loot boxes.
     *      Target is 2x current ticket price, capped at QUEST_ETH_TARGET_CAP.
     * @param player The player who purchased the loot box.
     * @param amountWei ETH amount spent on the loot box (in wei).
     * @return reward BURNIE tokens earned (in base units, 18 decimals).
     * @return questType The type of quest that was processed.
     * @return streak Player's current streak after this action.
     * @return completed True if a quest was completed by this action.
     * @custom:reverts OnlyCoin When caller is not COIN or COINFLIP contract.
     */
    function handleLootBox(
        address player,
        uint256 amountWei,
        uint256 mintPrice
    )
        external
        onlyCoin
        returns (uint256 reward, uint8 questType, uint32 streak, bool completed)
    {
        DailyQuest[QUEST_SLOT_COUNT] memory quests = activeQuests;
        uint32 currentDay = _currentQuestDay(quests);
        PlayerQuestState storage state = questPlayerState[player];
        if (player == address(0) || amountWei == 0 || currentDay == 0) {
            return (0, quests[0].questType, state.streak, false);
        }
        _questSyncState(state, player, currentDay);
        _handleLevelQuestProgress(player, QUEST_TYPE_LOOTBOX, amountWei, mintPrice);

        (DailyQuest memory quest, uint8 slotIndex) = _currentDayQuestOfType(quests, currentDay, QUEST_TYPE_LOOTBOX);
        if (slotIndex == type(uint8).max) {
            return (0, QUEST_TYPE_LOOTBOX, state.streak, false);
        }
        _questSyncProgress(state, slotIndex, currentDay, quest.version);
        state.progress[slotIndex] = _clampedAdd128(state.progress[slotIndex], amountWei);
        uint256 target = _questTargetValue(quest, slotIndex, mintPrice);
        emit QuestProgressUpdated(
            player,
            currentDay,
            slotIndex,
            quest.questType,
            state.progress[slotIndex],
            target
        );
        if (state.progress[slotIndex] < target) {
            return (0, quest.questType, state.streak, false);
        }
        if (slotIndex == 1 && (state.completionMask & 1) == 0) {
            return (0, quest.questType, state.streak, false);
        }
        (reward, questType, streak, completed) = _questCompleteWithPair(player, state, quests, slotIndex, quest, currentDay, mintPrice);
        if (completed && reward != 0) {
            coinflip.creditFlip(player, reward);
        }
    }

    /**
     * @notice Handle combined purchase-path activity (mint tickets + lootbox) in a single call.
     * @dev Access: COIN or COINFLIP contract only.
     *      Combines handleMint + handleLootBox quest logic for the purchase path.
     *      ETH mint rewards are returned for caller batching. BURNIE mint and lootbox
     *      rewards are creditFlipped internally (matching standalone handler behavior).
     *      Returns streak for compute-once score forwarding.
     * @param player The player who purchased.
     * @param ethMintQty ETH-paid ticket-equivalent mint units (fresh-ETH scaled).
     * @param burnieMintQty BURNIE-paid ticket-equivalent mint units.
     * @param lootBoxAmount ETH spent on lootbox in wei (full amount, fresh + recycled).
     * @param mintPrice Current ticket price in wei (purchaseLevel price for daily targets).
     * @param levelQuestPrice Price for level quest targets (level+1 price).
     * @return reward BURNIE tokens earned (in base units, 18 decimals).
     * @return questType The type of quest that was processed.
     * @return streak Player's current streak after this action.
     * @return completed True if a quest was completed by this action.
     * @custom:reverts OnlyCoin When caller is not COIN or COINFLIP contract.
     */
    function handlePurchase(
        address player,
        uint32 ethMintQty,
        uint32 burnieMintQty,
        uint256 lootBoxAmount,
        uint256 mintPrice,
        uint256 levelQuestPrice
    )
        external
        onlyCoin
        returns (uint256 reward, uint8 questType, uint32 streak, bool completed)
    {
        DailyQuest[QUEST_SLOT_COUNT] memory quests = activeQuests;
        uint32 currentDay = _currentQuestDay(quests);
        PlayerQuestState storage state = questPlayerState[player];
        if (player == address(0) || currentDay == 0) {
            return (0, quests[0].questType, state.streak, false);
        }
        if (ethMintQty == 0 && burnieMintQty == 0 && lootBoxAmount == 0) {
            return (0, quests[0].questType, state.streak, false);
        }

        _questSyncState(state, player, currentDay);

        uint256 ethMintReward;
        uint256 burnieMintReward;
        uint256 lootboxReward;
        bool anyCompleted;
        uint8 outQuestType;
        uint32 outStreak = state.streak;

        // --- ETH mint quest progress ---
        if (ethMintQty != 0) {
            bool levelQuestHandled;
            uint256 delta = uint256(ethMintQty) * mintPrice;
            for (uint8 slot; slot < QUEST_SLOT_COUNT; ) {
                DailyQuest memory quest = quests[slot];
                if (quest.day == currentDay && quest.questType == QUEST_TYPE_MINT_ETH) {
                    outQuestType = QUEST_TYPE_MINT_ETH;
                    uint256 target = _questTargetValue(quest, slot, mintPrice);
                    (uint256 r, uint8 qt, uint32 s, bool c) = _questHandleProgressSlot(
                        player, state, quests, quest, slot,
                        delta, target, currentDay, mintPrice,
                        QUEST_TYPE_MINT_ETH, levelQuestHandled ? 0 : delta,
                        levelQuestPrice
                    );
                    levelQuestHandled = true;
                    if (c) {
                        ethMintReward += r;
                        outQuestType = qt;
                        outStreak = s;
                        anyCompleted = true;
                    }
                }
                unchecked { ++slot; }
            }
            if (!levelQuestHandled) {
                _handleLevelQuestProgress(player, QUEST_TYPE_MINT_ETH, delta, levelQuestPrice);
            }
        }

        // --- BURNIE mint quest progress ---
        if (burnieMintQty != 0) {
            bool levelQuestHandled;
            for (uint8 slot; slot < QUEST_SLOT_COUNT; ) {
                DailyQuest memory quest = quests[slot];
                if (quest.day == currentDay && quest.questType == QUEST_TYPE_MINT_BURNIE) {
                    outQuestType = QUEST_TYPE_MINT_BURNIE;
                    uint256 target = _questTargetValue(quest, slot, 0);
                    (uint256 r, uint8 qt, uint32 s, bool c) = _questHandleProgressSlot(
                        player, state, quests, quest, slot,
                        burnieMintQty, target, currentDay, 0,
                        QUEST_TYPE_MINT_BURNIE, levelQuestHandled ? 0 : burnieMintQty,
                        levelQuestPrice
                    );
                    levelQuestHandled = true;
                    if (c) {
                        burnieMintReward += r;
                        outQuestType = qt;
                        outStreak = s;
                        anyCompleted = true;
                    }
                }
                unchecked { ++slot; }
            }
            if (!levelQuestHandled) {
                _handleLevelQuestProgress(player, QUEST_TYPE_MINT_BURNIE, burnieMintQty, levelQuestPrice);
            }
        }

        // --- Lootbox quest progress ---
        if (lootBoxAmount != 0) {
            _handleLevelQuestProgress(player, QUEST_TYPE_LOOTBOX, lootBoxAmount, levelQuestPrice);

            (DailyQuest memory quest, uint8 slotIndex) = _currentDayQuestOfType(quests, currentDay, QUEST_TYPE_LOOTBOX);
            if (slotIndex != type(uint8).max) {
                _questSyncProgress(state, slotIndex, currentDay, quest.version);
                state.progress[slotIndex] = _clampedAdd128(state.progress[slotIndex], lootBoxAmount);
                uint256 target = _questTargetValue(quest, slotIndex, mintPrice);
                emit QuestProgressUpdated(player, currentDay, slotIndex, quest.questType, state.progress[slotIndex], target);

                if (state.progress[slotIndex] >= target) {
                    bool canComplete = !(slotIndex == 1 && (state.completionMask & 1) == 0);
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

        // Reward routing (match standalone handler behavior):
        // - BURNIE mint rewards: creditFlip internally (handleMint behavior for !paidWithEth)
        // - Lootbox rewards: creditFlip internally AND returned to caller (caller adds to lootboxFlipCredit)
        // - ETH mint rewards: returned to caller (handleMint behavior for paidWithEth)
        if (burnieMintReward != 0) {
            coinflip.creditFlip(player, burnieMintReward);
        }
        if (lootboxReward != 0) {
            coinflip.creditFlip(player, lootboxReward);
        }
        // Return ETH mint reward + lootbox reward (caller adds lootbox to lootboxFlipCredit)
        uint256 totalReturned = ethMintReward + lootboxReward;
        if (anyCompleted) {
            return (totalReturned, outQuestType, outStreak, true);
        }
        return (0, outQuestType != 0 ? outQuestType : quests[0].questType, state.streak, false);
    }

    /**
     * @notice Handle Degenerette bet progress for a player.
     * @dev Access: COIN or COINFLIP contract only.
     * @param player The player who placed the Degenerette bet.
     * @param amount The bet amount (wei for ETH, base units for BURNIE).
     * @param paidWithEth True if bet was paid with ETH, false for BURNIE.
     * @param mintPrice Current ticket price in wei (0 for BURNIE bets).
     * @return reward BURNIE tokens earned (in base units, 18 decimals).
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
        DailyQuest[QUEST_SLOT_COUNT] memory quests = activeQuests;
        uint32 currentDay = _currentQuestDay(quests);
        PlayerQuestState storage state = questPlayerState[player];
        if (player == address(0) || amount == 0 || currentDay == 0) {
            return (0, quests[0].questType, state.streak, false);
        }
        _questSyncState(state, player, currentDay);

        uint8 targetType = paidWithEth ? QUEST_TYPE_DEGENERETTE_ETH : QUEST_TYPE_DEGENERETTE_BURNIE;
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
        uint32 currentDay = _currentQuestDay(local);
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
     * @return local Memory copy of active quests array.
     */
    function _materializeActiveQuestsForView() private view returns (DailyQuest[QUEST_SLOT_COUNT] memory local) {
        local = activeQuests;
    }

    /**
     * @notice Returns raw player quest state for debugging/analytics.
     * @param player The player address to query.
     * @return streak Current streak count.
     * @return lastCompletedDay Last day where a streak was credited (first slot completion).
     * @return progress Per-slot progress values (only valid if day/version match).
     * @return completed Per-slot completion flags for current day.
     */
    function playerQuestStates(
        address player
    )
        external
        view
        override
        returns (uint32 streak, uint32 lastCompletedDay, uint128[2] memory progress, bool[2] memory completed)
    {
        DailyQuest[QUEST_SLOT_COUNT] memory local = activeQuests;
        PlayerQuestState memory state = questPlayerState[player];
        uint32 currentDay = _currentQuestDay(local);
        streak = state.streak;
        lastCompletedDay = state.lastCompletedDay;
        for (uint8 slot; slot < QUEST_SLOT_COUNT; ) {
            DailyQuest memory quest = local[slot];
            // Only return progress if it's valid for the current quest day/version
            progress[slot] = _questProgressValid(state, quest, slot, currentDay) ? state.progress[slot] : 0;
            completed[slot] = _questCompleted(state, quest, slot);
            unchecked {
                ++slot;
            }
        }
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
        uint32 currentDay = _currentQuestDay(local);
        PlayerQuestState memory state = questPlayerState[player];

        // Preview streak decay: if player missed days beyond available shields, show 0 streak
        uint32 effectiveStreak = state.streak;
        uint24 anchorDay = state.lastActiveDay != 0 ? state.lastActiveDay : state.lastCompletedDay;
        if (anchorDay != 0 && currentDay > anchorDay + 1) {
            uint32 missedDays = currentDay - anchorDay - 1;
            uint16 shields = questStreakShieldCount[player];
            if (missedDays > uint32(shields)) {
                effectiveStreak = 0;
            }
        }
        // Use synced baseStreak if already active today, otherwise preview effective streak
        uint24 currentDay24 = uint24(currentDay);
        uint32 effectiveBaseStreak = (state.lastSyncDay == currentDay24) ? state.baseStreak : effectiveStreak;

        viewData.lastCompletedDay = state.lastCompletedDay;
        viewData.baseStreak = effectiveBaseStreak;

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

    // =========================================================================
    //                           INTERNAL HELPERS
    // =========================================================================

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
        uint32 currentDay
    ) private view returns (QuestInfo memory info, uint128 progress, bool completed) {
        info = QuestInfo({
            day: quest.day,
            questType: quest.questType,
            highDifficulty: false,
            requirements: _questRequirements(quest, slot)
        });
        if (_questProgressValid(state, quest, slot, currentDay)) {
            progress = state.progress[slot];
        }
        completed = _questCompleted(state, quest, slot);
    }

    /**
     * @dev Decode quest requirements (fixed targets, no tiers or difficulty variance).
     *      Different quest types use different requirement fields:
     *      - MINT_BURNIE → req.mints (small integer count)
     *      - MINT_ETH, LOOTBOX → req.tokenAmount (ETH wei)
     *      - FLIP, DECIMATOR, AFFILIATE → req.tokenAmount (BURNIE base units)
     * @param quest The quest to calculate requirements for.
     * @return req Requirements struct with either mints count or tokenAmount.
     */
    function _questRequirements(DailyQuest memory quest, uint8 slot) private view returns (QuestRequirements memory req) {
        uint8 qType = quest.questType;
        if (qType == QUEST_TYPE_MINT_BURNIE) {
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
            req.tokenAmount = _questTargetValue(quest, slot, currentPrice);
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
        uint32 currentDay,
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
     * @dev Increments and returns the quest version counter.
     *      Used to invalidate stale progress when a new quest is seeded for the day.
     * @return newVersion The new version number.
     */
    function _nextQuestVersion() private returns (uint24 newVersion) {
        newVersion = questVersionCounter++;
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
     * @return reward BURNIE tokens earned (in base units).
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
        uint32 currentDay,
        uint256 mintPrice,
        uint8 handlerQuestType,
        uint256 levelDelta,
        uint256 levelQuestPrice
    ) private returns (uint256 reward, uint8 questType, uint32 streak, bool completed) {
        _questSyncProgress(state, slot, quest.day, quest.version);
        state.progress[slot] = _clampedAdd128(state.progress[slot], delta);
        emit QuestProgressUpdated(
            player,
            quest.day,
            slot,
            quest.questType,
            state.progress[slot],
            target
        );
        _handleLevelQuestProgress(player, handlerQuestType, levelDelta, levelQuestPrice);
        if (state.progress[slot] >= target) {
            if (slot == 1 && (state.completionMask & 1) == 0) {
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
    function _questSyncState(PlayerQuestState storage state, address player, uint32 currentDay) private {
        uint24 prevStreak = state.streak;
        uint24 anchorDay = state.lastActiveDay != 0 ? state.lastActiveDay : state.lastCompletedDay;
        if (anchorDay != 0 && currentDay > anchorDay + 1) {
            uint32 missedDays = currentDay - anchorDay - 1;
            uint16 shields = questStreakShieldCount[player];
            if (shields != 0) {
                uint32 used = missedDays > uint32(shields) ? uint32(shields) : missedDays;
                questStreakShieldCount[player] = shields - uint16(used);
                if (used != 0) {
                    emit QuestStreakShieldUsed(
                        player,
                        uint16(used),
                        questStreakShieldCount[player],
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
     * @dev Clears progress for a slot when the tracked day or quest version differs.
     *      This is the key anti-exploit mechanism:
     *      - Progress from a previous day cannot be applied to today's quest
     *      - Progress from a different quest version is invalidated
     * @param state Storage reference to player's quest state.
     * @param slot The slot index to sync.
     * @param currentDay The current quest day.
     * @param questVersion The current quest version.
     */
    function _questSyncProgress(
        PlayerQuestState storage state,
        uint8 slot,
        uint32 currentDay,
        uint24 questVersion
    ) private {
        uint24 currentDay24 = uint24(currentDay);
        if (state.lastProgressDay[slot] != currentDay24 || state.lastQuestVersion[slot] != questVersion) {
            state.lastProgressDay[slot] = currentDay24;
            state.lastQuestVersion[slot] = questVersion;
            state.progress[slot] = 0;
        }
    }

    /**
     * @dev Progress is only valid when it matches the active quest day and version.
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
        uint32 currentDay
    ) private pure returns (bool) {
        if (quest.day == 0 || quest.day != currentDay) {
            return false;
        }
        uint24 questDay = uint24(quest.day);
        return state.lastProgressDay[slot] == questDay && state.lastQuestVersion[slot] == quest.version;
    }

    /**
     * @dev Storage-aware variant of _questProgressValid to avoid copying state to memory.
     * @param state Player's quest state (storage).
     * @param quest The quest to validate against.
     * @param slot The slot index.
     * @param currentDay The current quest day.
     * @return True if progress is valid and should be used.
     */
    function _questProgressValidStorage(
        PlayerQuestState storage state,
        DailyQuest memory quest,
        uint8 slot,
        uint32 currentDay
    ) private view returns (bool) {
        if (quest.day == 0 || quest.day != currentDay) {
            return false;
        }
        uint24 questDay = uint24(quest.day);
        return state.lastProgressDay[slot] == questDay && state.lastQuestVersion[slot] == quest.version;
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
        if (qType == QUEST_TYPE_MINT_ETH) {
            uint256 mult = slot == 0
                ? QUEST_DEPOSIT_ETH_TARGET_MULTIPLIER
                : QUEST_LOOTBOX_TARGET_MULTIPLIER;
            uint256 target = mintPrice * mult;
            return target > QUEST_ETH_TARGET_CAP ? QUEST_ETH_TARGET_CAP : target;
        }
        if (qType == QUEST_TYPE_LOOTBOX || qType == QUEST_TYPE_DEGENERETTE_ETH) {
            uint256 target = mintPrice * QUEST_LOOTBOX_TARGET_MULTIPLIER;
            return target > QUEST_ETH_TARGET_CAP ? QUEST_ETH_TARGET_CAP : target;
        }
        if (qType == QUEST_TYPE_MINT_BURNIE) {
            return QUEST_MINT_TARGET;
        }
        if (
            qType == QUEST_TYPE_FLIP ||
            qType == QUEST_TYPE_DECIMATOR ||
            qType == QUEST_TYPE_AFFILIATE ||
            qType == QUEST_TYPE_DEGENERETTE_BURNIE
        ) {
            return QUEST_BURNIE_TARGET;
        }
        return 0;
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
     *      - MINT_BURNIE gets 10x weight
     *      - DEGENERETTE_ETH and DEGENERETTE_BURNIE use base weight (1x)
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
            // Skip sentinel value 0 (unrolled marker) and retired type 4
            if (candidate == 0 || candidate == QUEST_TYPE_RESERVED) {
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
            // Apply type-specific weights
            uint16 weight = 1;
            if (candidate == QUEST_TYPE_FLIP) {
                weight = 4;
            } else if (candidate == QUEST_TYPE_MINT_BURNIE) {
                weight = 10;
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
     * @dev Completes a quest slot, credits streak when all slots finish, and returns rewards.
     *
     *      Streak Logic:
     *      - Streak increments on the first quest completion of the day
     *      - QUEST_STATE_STREAK_CREDITED bit prevents double-crediting
     *      - lastCompletedDay updates on that first completion
     *
     *      Reward Calculation:
     *      - Slot 0 (deposit ETH) pays a fixed 100 BURNIE
     *      - Slot 1 (random quest) pays a fixed 200 BURNIE
     * @param state Storage reference to player's quest state.
     * @param slot The slot index being completed.
     * @param quest The quest being completed.
     * @return reward BURNIE tokens earned (in base units).
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

        // Mark slot as complete
        mask |= slotMask;
        uint24 questDay24 = uint24(quest.day);
        if (questDay24 > state.lastActiveDay) {
            state.lastActiveDay = questDay24;
        }

        uint32 newStreak = uint32(state.streak);

        // Streak is credited on the first quest completion of the day.
        if ((mask & QUEST_STATE_STREAK_CREDITED) == 0) {
            mask |= QUEST_STATE_STREAK_CREDITED;
            if (newStreak < type(uint24).max) {
                newStreak += 1;
            }
            state.streak = uint24(newStreak);
            state.lastCompletedDay = questDay24;
        }
        state.completionMask = mask;

        uint256 rewardShare = slot == 1 ? QUEST_RANDOM_REWARD : QUEST_SLOT0_REWARD;
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
     * @return reward BURNIE tokens earned (in base units).
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
        uint32 currentDay,
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
     * @return reward BURNIE tokens earned (in base units).
     * @return questType The completed quest type.
     * @return streak Player's streak after completion.
     * @return completed True if completion was successful.
     */
    function _maybeCompleteOther(
        address player,
        PlayerQuestState storage state,
        DailyQuest[QUEST_SLOT_COUNT] memory quests,
        uint8 slot,
        uint32 currentDay,
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
        if (!_questProgressValidStorage(state, quest, slot, quest.day)) return false;
        uint256 progress = state.progress[slot];
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
     * @dev Seeds a quest slot with a new quest definition.
     *      Always bumps version to invalidate any stale player progress.
     * @param quest Storage reference to the quest slot.
     * @param day The quest day identifier.
     * @param questType The quest type to seed.
     */
    function _seedQuestType(
        DailyQuest storage quest,
        uint32 day,
        uint8 questType
    ) private {
        quest.day = day;
        quest.questType = questType;
        quest.version = _nextQuestVersion();
    }

    /**
     * @dev Helper to read the active day from either slot.
     * @param quests Memory array of active quests.
     * @return The current quest day (prefers slot 0 if both are set).
     */
    function _currentQuestDay(DailyQuest[QUEST_SLOT_COUNT] memory quests) private pure returns (uint32) {
        uint32 day0 = quests[0].day;
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
    /// @return True if the player meets both gates.
    function _isLevelQuestEligible(address player) internal view returns (bool) {
        uint256 packed = questGame.mintPackedFor(player);

        // Activity gate: 4+ units minted this level
        uint24 unitsLvl = uint24(packed >> 104);
        if (unitsLvl != questGame.level() + 1) return false;
        uint16 units = uint16(packed >> 228);
        if (units < 4) return false;

        // Loyalty gate: levelStreak >= 5 OR any active pass
        uint24 streak = uint24(packed >> 48);
        if (streak >= 5) return true;

        // Whale/lazy pass from mintPacked_
        uint24 frozen = uint24(packed >> 128);
        uint8 bundle = uint8((packed >> 152) & 0x3);
        if (frozen > 0 && bundle != 0) return true;

        // Deity pass fallback (separate SLOAD)
        return questGame.hasDeityPass(player);
    }

    /// @dev Returns the 10x target for a level quest type.
    ///      MINT_BURNIE targets 10 tickets, MINT_ETH targets mintPrice * 10,
    ///      LOOTBOX and DEGENERETTE_ETH target mintPrice * 20,
    ///      BURNIE-denominated types target 20,000 BURNIE.
    ///      No ETH cap applied (unlike daily quests).
    /// @param questType The quest type constant (1-9, 0 reserved as unrolled sentinel).
    /// @param mintPrice Current mint price in wei.
    /// @return Target value in the same units as handler progress deltas.
    function _levelQuestTargetValue(uint8 questType, uint256 mintPrice) internal pure returns (uint256) {
        if (questType == QUEST_TYPE_MINT_BURNIE) return 10;
        if (questType == QUEST_TYPE_MINT_ETH) return mintPrice * 10;
        if (questType == QUEST_TYPE_LOOTBOX || questType == QUEST_TYPE_DEGENERETTE_ETH) {
            return mintPrice * 20;
        }
        if (
            questType == QUEST_TYPE_FLIP ||
            questType == QUEST_TYPE_DECIMATOR ||
            questType == QUEST_TYPE_AFFILIATE ||
            questType == QUEST_TYPE_DEGENERETTE_BURNIE
        ) {
            return 20_000 ether;
        }
        return 0;
    }

    /// @dev Shared level quest progress handler called by each of the 6 handlers.
    ///      Reads levelQuestType and levelQuestVersion (share slot with questVersionCounter)
    ///      to get both level and type. Short-circuits on type mismatch before any
    ///      player state read. Eligibility is deferred to the completion boundary —
    ///      ineligible players accumulate phantom progress that can never complete.
    /// @param player The player earning progress.
    /// @param handlerQuestType The quest type this handler tracks.
    /// @param delta The progress delta (units match quest type).
    /// @param mintPrice Current mint price in wei (for ETH-based targets; 0 for BURNIE types).
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
            // Gate eligibility only at completion
            if (!_isLevelQuestEligible(player)) {
                packed = uint256(currentVersion) | (uint256(progress) << 8);
                levelQuestPlayerState[player] = packed;
                return;
            }
            packed = uint256(currentVersion)
                   | (uint256(progress) << 8)
                   | (uint256(1) << 136);
            levelQuestPlayerState[player] = packed;
            coinflip.creditFlip(player, 800 ether);
            emit LevelQuestCompleted(player, questGame.level() + 1, lqType, 800 ether);
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
        eligible = _isLevelQuestEligible(player);
    }
}
