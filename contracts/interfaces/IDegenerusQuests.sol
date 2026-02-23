// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

/// @notice Requirements for completing a quest
struct QuestRequirements {
    /// @notice Number of mints required (whole tickets)
    uint32 mints;
    /// @notice Token amount required - BURNIE in base units (18 decimals) for token quests, wei for ETH quests
    uint256 tokenAmount;
}

/// @notice Information about a single quest
struct QuestInfo {
    /// @notice The day this quest is active (unix day)
    uint48 day;
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
    uint32 lastCompletedDay;
    /// @notice The player's base streak count before shields
    uint32 baseStreak;
}

/// @title IDegenerusQuests
/// @notice Interface for the daily quest system that rewards players for game actions
/// @dev Quests reset daily and track player progress across mint, flip, and other actions
interface IDegenerusQuests {
    /// @notice Rolls the daily quest for a given day using provided entropy
    /// @dev Called by the game contract to determine which quests are active
    /// @param day The unix day to roll quests for
    /// @param entropy Random entropy used to determine quest types and difficulty
    /// @return rolled Whether a new quest was rolled (false if already rolled for this day)
    /// @return questTypes The two quest types that were selected
    /// @return highDifficulty Whether this is a high difficulty day
    function rollDailyQuest(uint48 day, uint256 entropy)
        external
        returns (bool rolled, uint8[2] memory questTypes, bool highDifficulty);

    /// @notice Records player minting activity and checks quest completion
    /// @dev Called by the game contract when a player mints tickets
    /// @param player The address of the player who minted
    /// @param quantity The number of tickets minted
    /// @param paidWithEth Whether the mint was paid for with ETH (vs tokens)
    /// @return reward The quest reward amount earned (0 if quest not completed)
    /// @return questType The type of quest that was completed
    /// @return streak The player's current quest streak
    /// @return completed Whether a quest was completed by this action
    function handleMint(address player, uint32 quantity, bool paidWithEth)
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

    /// @notice Records player lootbox activity and checks quest completion
    /// @dev Called by the game contract when a player opens a lootbox
    /// @param player The address of the player
    /// @param amountWei The amount of ETH spent on the lootbox in wei
    /// @return reward The quest reward amount earned (0 if quest not completed)
    /// @return questType The type of quest that was completed
    /// @return streak The player's current quest streak
    /// @return completed Whether a quest was completed by this action
    function handleLootBox(address player, uint256 amountWei)
        external
        returns (uint256 reward, uint8 questType, uint32 streak, bool completed);

    /// @notice Records player Degenerette activity and checks quest completion
    /// @dev Called by the game contract when a player places a Degenerette bet
    /// @param player The address of the player
    /// @param amount The bet amount (wei for ETH, base units for BURNIE)
    /// @param paidWithEth True if the bet was paid with ETH, false if paid with BURNIE
    /// @return reward The quest reward amount earned (0 if quest not completed)
    /// @return questType The type of quest that was completed
    /// @return streak The player's current quest streak
    /// @return completed Whether a quest was completed by this action
    function handleDegenerette(address player, uint256 amount, bool paidWithEth)
        external
        returns (uint256 reward, uint8 questType, uint32 streak, bool completed);

    /// @notice Awards bonus streak days to a player
    /// @dev Directly increases the player's streak count
    /// @param player The address of the player to award bonus to
    /// @param amount The number of bonus streak days to award
    /// @param currentDay The current unix day for tracking purposes
    function awardQuestStreakBonus(address player, uint16 amount, uint48 currentDay) external;

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
            uint32 lastCompletedDay,
            uint128[2] memory progress,
            bool[2] memory completed
        );

}
