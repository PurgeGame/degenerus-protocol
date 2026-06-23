// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/// @notice Requirements for completing a quest
struct QuestRequirements {
    /// @notice Number of mints required (whole tickets)
    uint32 mints;
    /// @notice Token amount required - FLIP in base units (18 decimals) for token quests, wei for ETH quests
    uint256 tokenAmount;
}

/// @notice Information about a single quest
struct QuestInfo {
    /// @notice The day this quest is active (unix day)
    uint24 day;
    /// @notice The type of quest (mint, flip, affiliate, etc.)
    uint8 questType;
    /// @notice Whether this is a high difficulty quest with increased requirements and rewards
    bool highDifficulty;
    /// @notice The requirements to complete this quest
    QuestRequirements requirements;
}

/// @notice Player-facing view of quest state including progress and completion status
struct PlayerQuestView {
    /// @notice The two active quests for today
    QuestInfo[2] quests;
    /// @notice Player's current progress on each quest
    uint128[2] progress;
    /// @notice Whether the player has completed each quest
    bool[2] completed;
    /// @notice The last day the player completed a quest
    uint24 lastCompletedDay;
    /// @notice The player's base streak count before shields
    uint32 baseStreak;
}

/// @title IDegenerusQuests
/// @notice Interface for the daily quest system that rewards players for game actions
/// @dev Quests reset daily and track player progress across mint, flip, and other actions
interface IDegenerusQuests {
    /// @notice Rolls the daily quest for a given day using provided entropy.
    /// @dev Called by AdvanceModule (via GAME delegatecall) to determine which quests are active.
    /// @param day The unix day to roll quests for
    /// @param entropy Random entropy used to determine the slot 1 quest type
    /// @param forceMintFlip Force slot 1 to MINT_FLIP (the first jackpot day, when the FLIP
    ///        redeem window is live); otherwise MINT_FLIP is excluded from the slot 1 roll.
    function rollDailyQuest(
        uint24 day,
        uint256 entropy,
        bool forceMintFlip,
        bool forceFoil
    ) external;

    /// @notice Records player minting activity and checks quest completion
    /// @dev Called by the game contract when a player mints tickets
    /// @param player The address of the player who minted
    /// @param quantity The number of tickets minted
    /// @param paidWithEth Whether the mint was paid for with ETH (vs tokens)
    /// @param mintPrice Current ticket price in wei (0 for FLIP mints)
    /// @return reward The quest reward amount earned (0 if quest not completed)
    /// @return questType The type of quest that was completed
    /// @return streak The player's current quest streak
    /// @return completed Whether a quest was completed by this action
    function handleMint(address player, uint32 quantity, bool paidWithEth, uint256 mintPrice)
        external
        returns (uint256 reward, uint8 questType, uint32 streak, bool completed);

    /// @notice Records player flip activity and checks quest completion
    /// @dev Called by the game contract when a player performs a coinflip
    /// @param player The address of the player who flipped
    /// @param flipCredit The amount of flip credit used
    /// @return reward The quest reward amount earned (0 if quest not completed)
    /// @return questType The type of quest that was completed
    /// @return streak The player's current quest streak
    /// @return completed Whether a quest was completed by this action
    function handleFlip(address player, uint256 flipCredit)
        external
        returns (uint256 reward, uint8 questType, uint32 streak, bool completed);

    /// @notice Records player decimator activity and checks quest completion
    /// @dev Called by the game contract when a player uses the decimator
    /// @param player The address of the player
    /// @param burnAmount The amount of tokens burned in the decimator
    /// @return reward The quest reward amount earned (0 if quest not completed)
    /// @return questType The type of quest that was completed
    /// @return streak The player's current quest streak
    /// @return completed Whether a quest was completed by this action
    function handleDecimator(address player, uint256 burnAmount)
        external
        returns (uint256 reward, uint8 questType, uint32 streak, bool completed);

    /// @notice Foil-pack purchase handler: shared primary purchase legs, then the foil
    ///         secondary quest and streak floor, in one GAME call
    /// @dev Called by the game's foil module (GAME context) on a foil-pack buy. Runs the
    ///      shared primary purchase legs, the streak snapshot, then the foil secondary quest
    ///      and streak floor.
    /// @param player The address of the player who bought the foil pack
    /// @param ethMintSpendWei Gross ETH-denominated foil spend in wei (credited 1:1 to MINT_ETH)
    /// @param flipMintQty FLIP-paid ticket-equivalent mint units
    /// @param lootBoxAmount ETH spent on lootbox in wei
    /// @param mintPrice Current ticket price in wei (daily targets)
    /// @param levelQuestPrice Price for level quest targets (level+1 price)
    /// @return reward Primary-leg FLIP reward (0 if not completed)
    /// @return questType The primary quest type processed
    /// @return completed Whether the primary quest completed by this action
    /// @return streakSnapshot Pre-floor reward streak for the foil-EV activity score
    function handleFoilPurchase(
        address player,
        uint256 ethMintSpendWei,
        uint32 flipMintQty,
        uint256 lootBoxAmount,
        uint256 mintPrice,
        uint256 levelQuestPrice
    ) external returns (uint256 reward, uint8 questType, bool completed, uint32 streakSnapshot);

    /// @notice Records player affiliate activity and checks quest completion
    /// @dev Called by the game contract when a player earns affiliate rewards
    /// @param player The address of the player
    /// @param amount The amount of affiliate rewards earned
    /// @return reward The quest reward amount earned (0 if quest not completed)
    /// @return questType The type of quest that was completed
    /// @return streak The player's current quest streak
    /// @return completed Whether a quest was completed by this action
    function handleAffiliate(address player, uint256 amount)
        external
        returns (uint256 reward, uint8 questType, uint32 streak, bool completed);

    /// @notice Records player Degenerette activity and checks quest completion
    /// @dev Called by the game contract when a player places a Degenerette bet
    /// @param player The address of the player
    /// @param amount The bet amount (wei for ETH, base units for FLIP)
    /// @param paidWithEth True if the bet was paid with ETH, false if paid with FLIP
    /// @param mintPrice Current ticket price in wei (0 for FLIP bets)
    /// @return reward The quest reward amount earned (0 if quest not completed)
    /// @return questType The type of quest that was completed
    /// @return streak The player's current quest streak
    /// @return completed Whether a quest was completed by this action
    function handleDegenerette(address player, uint256 amount, bool paidWithEth, uint256 mintPrice)
        external
        returns (uint256 reward, uint8 questType, uint32 streak, bool completed);

    /// @notice Records combined purchase-path activity (mint tickets + lootbox) and checks quest completion
    /// @dev Called by MintModule for the unified purchase path. Combines the mint + lootbox
    ///      quest legs into a single cross-contract call. Returns streak for compute-once
    ///      score forwarding.
    /// @param player The address of the player
    /// @param ethMintSpendWei Gross ETH-denominated spend on tickets + lootbox in wei
    ///        (fresh + recycled), credited 1:1 to MINT_ETH quest
    /// @param flipMintQty FLIP-paid ticket-equivalent mint units
    /// @param lootBoxAmount ETH spent on lootbox in wei (full amount, fresh + recycled)
    /// @param mintPrice Current ticket price in wei (purchaseLevel price for daily targets)
    /// @param levelQuestPrice Price for level quest targets (level+1 price)
    /// @return reward The quest reward amount earned (0 if quest not completed)
    /// @return questType The type of quest that was processed
    /// @return streak The player's current quest streak (for score forwarding)
    /// @return completed Whether a quest was completed by this action
    function handlePurchase(
        address player,
        uint256 ethMintSpendWei,
        uint32 flipMintQty,
        uint256 lootBoxAmount,
        uint256 mintPrice,
        uint256 levelQuestPrice
    ) external returns (uint256 reward, uint8 questType, uint32 streak, bool completed);

    /// @notice Awards bonus streak days to a player
    /// @dev Directly increases the player's streak count
    /// @param player The address of the player to award bonus to
    /// @param amount The number of bonus streak days to award
    /// @param currentDay The current unix day for tracking purposes
    function awardQuestStreakBonus(address player, uint16 amount, uint24 currentDay) external;

    /// @notice Grant quest streak shields to a player (each absorbs one missed day)
    /// @dev GAME-only. Used by the lootbox quest-shield boon.
    /// @param player The address of the player to grant shields to
    /// @param amount The number of shields to add (uint8-saturating)
    function awardQuestStreakShield(address player, uint16 amount) external;

    /// @notice Begins an afking run: snapshots the gap-synced streak and flips the afking flag
    /// @dev GAME-only. While afking, the Game-side compute-on-read owns the player's streak and
    ///      slot-0 completions are streak-neutral / reward-deferred; returns the synced streak
    ///      so the caller bases the run's snapshot on it.
    /// @param player The subscriber starting an afking run
    /// @param currentDay The current quest day for state synchronization
    /// @return streak The player's gap-synced streak at the start of the run
    function beginAfking(address player, uint24 currentDay) external returns (uint24 streak);

    /// @notice Ends an afking run: hands the afking-computed streak back to the manual system
    /// @dev GAME-only, called on every sub-ending path before the Sub slot is deleted.
    ///      Idempotent (a no-op unless the player is currently afking). Keeps the Game-computed
    ///      earned streak if a valid mint (afking high-water or manual completion) landed no
    ///      earlier than yesterday, else zeroes it (decay); anchors the gap-reset at that day.
    /// @param player The subscriber whose run is ending
    /// @param earnedStreak The run's earned streak (snapshot + funded delivered days), Game-computed
    /// @param afkingCoveredDay The afking funded high-water day (Game-side)
    /// @param currentDay The current quest day (the decay reference)
    function finalizeAfking(address player, uint24 earnedStreak, uint24 afkingCoveredDay, uint24 currentDay) external;

    /// @notice Returns the quest state for a specific player
    /// @param player The address of the player to query
    /// @return streak The player's current quest streak
    /// @return lastCompletedDay The last day the player completed a quest
    /// @return progress The player's current progress on each of the two quests
    /// @return completed Whether the player has completed each of the two quests
    function playerQuestStates(address player)
        external
        view
        returns (
            uint32 streak,
            uint24 lastCompletedDay,
            uint128[2] memory progress,
            bool[2] memory completed
        );

    /// @notice Roll the level quest using provided entropy.
    /// @dev Called by AdvanceModule (via GAME delegatecall) during level transition.
    /// @param entropy VRF-derived entropy for quest type selection.
    function rollLevelQuest(uint256 entropy) external;

    /// @notice Returns a player's level quest state for frontend display.
    /// @param player The player address to query.
    /// @return questType The active level quest type (0-8).
    /// @return progress The player's accumulated progress.
    /// @return target The target value for completion.
    /// @return completed Whether the player has completed the quest this level.
    /// @return eligible Whether the player is eligible for level quests.
    function getPlayerLevelQuestView(address player)
        external
        view
        returns (uint8 questType, uint128 progress, uint256 target, bool completed, bool eligible);

    /// @notice Returns the player's daily quest view, including the effective
    ///         (gap/shield-decayed) base streak. A pure view — no mutation.
    /// @param player The player address to query.
    /// @return viewData The player's quest view with the effective baseStreak.
    function getPlayerQuestView(address player)
        external
        view
        returns (PlayerQuestView memory viewData);

    /// @notice The player's decay-aware effective reward streak (getPlayerQuestView's baseStreak),
    ///         computed without materializing the per-quest view structs — a cheap read for scoring.
    /// @param player The player address to query.
    /// @return The effective (decay-applied) reward streak.
    function effectiveBaseStreak(address player) external view returns (uint32);

    /// @notice effectiveBaseStreak plus the player's afking-run flag, from one quest-state read.
    /// @param player The player address to query.
    /// @return streak The effective (decay-applied) reward streak.
    /// @return afking True while the player is mid afking-run.
    function effectiveBaseStreakAndAfking(address player) external view returns (uint32 streak, bool afking);

}
