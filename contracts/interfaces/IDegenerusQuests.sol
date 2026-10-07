// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/*
 * TERMS OF INTERACTION — submitting a transaction to this contract accepts them.
 *
 * THIS IS GAMBLING. Outcomes are decided by chance. You can lose everything you put in
 * simply by being unlucky. That is the software working exactly as intended. Do not
 * commit funds you are not prepared to lose entirely.
 *
 * The deployed bytecode is the entire agreement and the exclusive source of truth; any
 * comment, name, document or statement that disagrees with it is in error. It has been
 * audited but is not proven correct: it may contain defects the author did not find, and
 * by interacting with it you accept that risk in full.
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

/// @notice Requirements for completing a quest
struct QuestRequirements {
    /// @notice Count required for count-based quests: whole tickets (MINT_FLIP), foil packs (FOIL)
    ///         or craps actions (CRAPS_*)
    uint32 mints;
    /// @notice Token amount required - FLIP in base units (18 decimals) for token quests, wei for ETH quests
    uint256 tokenAmount;
}

/// @notice Information about a single quest
struct QuestInfo {
    /// @notice The day this quest is active (deploy-relative day index; Day 1 = deploy day)
    uint24 day;
    /// @notice The type of quest (mint, flip, affiliate, etc.)
    uint8 questType;
    /// @notice Reserved; always false — no path in the quest system sets it
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
    /// @notice The last day the player completed the primary (slot 0) quest
    uint24 lastCompletedDay;
    /// @notice The player's effective (gap/shield-decayed) base streak
    uint32 baseStreak;
}

/// @title IDegenerusQuests
/// @notice Interface for the daily quest system that rewards players for game actions
/// @dev Quests reset daily and track player progress across mint, flip, and other actions.
///      Every per-player quest record is keyed by the caller-supplied uint32 wallet ID; Quests
///      has no player entry points and resolves no address except at a level-quest completion
///      (eligibility reads the wallet's mint word through the wallet table). Wallet ID 0 means
///      "no wallet". Callers always pass a nonzero ID they hold (Game modules, Coinflip's
///      forward word, FLIP after registration, Affiliate's stored IDs, Parimutuel's
///      `marketBetGates`). No handler reverts on any ID, and a view of an untouched ID
///      (including 0) returns its zero/default result.
interface IDegenerusQuests {
    /// @notice Rolls the daily quest for a given day using provided entropy.
    /// @dev Called by AdvanceModule (via GAME delegatecall) to determine which quests are active.
    /// @param day The deploy-relative day index to roll quests for (Day 1 = deploy day)
    /// @param entropy Random entropy used to determine the slot 1 quest type
    /// @param forceMintFlip Force slot 1 to MINT_FLIP (the first jackpot day, when the FLIP
    ///        redeem window is live); otherwise MINT_FLIP is excluded from the slot 1 roll.
    /// @param forceFoil Force slot 1 to FOIL (the day the purchase phase opens); otherwise FOIL
    ///        is excluded from the slot 1 roll.
    /// @param forceDecimator Force slot 1 to DECIMATOR (the day a decimator burn window is
    ///        armed). Outranks the other two.
    function rollDailyQuest(
        uint24 day,
        uint256 entropy,
        bool forceMintFlip,
        bool forceFoil,
        bool forceDecimator
    ) external;

    /// @notice Records player flip activity and checks quest completion
    /// @dev Called by COINFLIP when a player stakes a coinflip (onlyCoin admits COIN, COINFLIP, GAME and AFFILIATE).
    ///      The quest belongs to the FUNDER of the deposit (the depositor for self and operator
    ///      deposits, the paying sender for a gift); Coinflip folds the returned reward into the
    ///      staked player's deposit.
    /// @param id Wallet ID of the funder whose quest progresses
    /// @param flipCredit The amount of flip credit used
    /// @return reward The quest reward amount earned (0 if quest not completed)
    /// @return questType The type of quest that was completed
    /// @return streak The player's current quest streak
    /// @return completed Whether a quest was completed by this action
    function handleFlip(uint32 id, uint256 flipCredit)
        external
        returns (uint256 reward, uint8 questType, uint32 streak, bool completed);

    /// @notice Records player decimator activity and checks quest completion
    /// @dev Called by FLIP when a player burns into the decimator (onlyCoin admits COIN, COINFLIP, GAME and AFFILIATE).
    ///      FLIP obtains the burner's ID first (Game `playerActivityScoreCached`, then
    ///      `registerWallet(caller, true)` on zero). Quests credits the reward itself by ID.
    /// @param id Wallet ID of the burner
    /// @param burnAmount The amount of tokens burned in the decimator
    /// @return reward The quest reward amount earned (0 if quest not completed)
    /// @return questType The type of quest that was completed
    /// @return streak The player's current quest streak
    /// @return completed Whether a quest was completed by this action
    function handleDecimator(uint32 id, uint256 burnAmount)
        external
        returns (uint256 reward, uint8 questType, uint32 streak, bool completed);

    /// @notice Foil-pack purchase handler: shared primary purchase legs, then the foil
    ///         secondary quest and streak floor, in one GAME call
    /// @dev Called by the game's foil module (GAME context) on a foil-pack buy. Runs the
    ///      shared primary purchase legs, the streak snapshot, then the foil secondary quest
    ///      and streak floor. Credits the foil-quest reward itself by ID and floors an afking
    ///      buyer's streak through Game `floorAfkingStreakBase(id, ...)`.
    /// @param id Wallet ID of the buyer
    /// @param ethMintSpendWei Gross ETH-denominated foil spend in wei (credited 1:1 to MINT_ETH)
    /// @param flipMintQty FLIP-paid ticket-equivalent mint units
    /// @param lootBoxAmount ETH spent on lootbox in wei
    /// @param mintPrice Current ticket price in wei (daily targets)
    /// @param levelQuestPrice Price for level quest targets (level+1 price)
    /// @return reward Primary-leg FLIP reward (0 if not completed)
    /// @return questType The primary quest type processed
    /// @return completed Whether the primary quest completed by this action
    /// @return streakSnapshot Pre-floor reward streak for the foil-EV activity score
    /// @return afking Whether the buyer has an afking run (live streak resolved by Game)
    function handleFoilPurchase(
        uint32 id,
        uint256 ethMintSpendWei,
        uint32 flipMintQty,
        uint256 lootBoxAmount,
        uint256 mintPrice,
        uint256 levelQuestPrice
    ) external returns (uint256 reward, uint8 questType, bool completed, uint32 streakSnapshot, bool afking);

    /// @notice Records player affiliate activity and checks quest completion
    /// @dev Called by AFFILIATE when an affiliate's earnings are credited (onlyCoin admits COIN,
    ///      COINFLIP, GAME and AFFILIATE). AFFILIATE passes the winning owner's or upline's
    ///      stored ID (no decode); a level-quest completion resolves the wallet's address once
    ///      through the wallet table. Affiliate credits the returned reward.
    /// @param id Wallet ID of the affiliate (code owner or upline) earning the reward
    /// @param amount The amount of affiliate rewards earned
    /// @return reward The quest reward amount earned (0 if quest not completed)
    /// @return questType The type of quest that was completed
    /// @return streak The player's current quest streak
    /// @return completed Whether a quest was completed by this action
    function handleAffiliate(uint32 id, uint256 amount)
        external
        returns (uint256 reward, uint8 questType, uint32 streak, bool completed);

    /// @notice Records player Degenerette activity and checks quest completion
    /// @dev Called by the game contract when a player places a Degenerette bet. The quest and
    ///      the reward (credited here by ID) belong to the bet's FUNDER.
    /// @param id Wallet ID of the funder
    /// @param amount The bet amount (wei for ETH, base units for FLIP)
    /// @param paidWithEth True if the bet was paid with ETH, false if paid with FLIP
    /// @param mintPrice Current ticket price in wei (0 for FLIP bets)
    /// @return reward The quest reward amount earned (0 if quest not completed)
    /// @return questType The type of quest that was completed
    /// @return streak The player's current quest streak
    /// @return completed Whether a quest was completed by this action
    function handleDegenerette(uint32 id, uint256 amount, bool paidWithEth, uint256 mintPrice)
        external
        returns (uint256 reward, uint8 questType, uint32 streak, bool completed);

    /// @notice Records combined purchase-path activity (mint tickets + lootbox) and checks quest completion
    /// @dev Called by MintModule for the unified purchase path. Combines the mint + lootbox
    ///      quest legs into a single cross-contract call. Returns streak for compute-once
    ///      score forwarding. The caller credits the returned reward.
    /// @param id Wallet ID of the buyer
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
    /// @return afking Whether the buyer has an afking run (live streak resolved by Game)
    function handlePurchase(
        uint32 id,
        uint256 ethMintSpendWei,
        uint32 flipMintQty,
        uint256 lootBoxAmount,
        uint256 mintPrice,
        uint256 levelQuestPrice
    ) external returns (uint256 reward, uint8 questType, uint32 streak, bool completed, bool afking);

    /// @notice Awards bonus streak days to a player
    /// @dev GAME only. Directly increases the player's streak count.
    /// @param id Wallet ID of the player to award bonus to
    /// @param amount The number of bonus streak days to award
    /// @param currentDay The caller's current calendar day; quest state pins to the newest rolled day
    function awardQuestStreakBonus(uint32 id, uint16 amount, uint24 currentDay) external;

    /// @notice Record a paid craps action: quest progress and the whole-day streak credit.
    /// @dev Access: COIN only. FLIP is the single reporter for the whole craps surface, so no
    ///      other quest handler gains a caller comparison. Carries no boon value — a craps boon
    ///      boosts the slip's bankroll return at settlement, never entry-time coinflip credit.
    ///      CRAPS obtains the buyer's ID before the bet body and FLIP forwards it from
    ///      `burnCoinForCraps`. Credits the join-quest reward itself by ID.
    /// @param id Wallet ID of the player who paid for the action.
    /// @param actionFlags Bit 0 paid join, bit 1 paid day pass, bit 2 normal day streak,
    ///        bit 3 high day streak.
    function recordCrapsAction(uint32 id, uint8 actionFlags) external;

    /// @notice Grant quest streak shields to a player (each absorbs one missed day)
    /// @dev GAME-only. Used by the lootbox quest-shield boon.
    /// @param id Wallet ID of the player to grant shields to
    /// @param amount The number of shields to add (uint8-saturating)
    function awardQuestStreakShield(uint32 id, uint16 amount) external;

    /// @notice Begins an afking run: snapshots the gap-synced streak and flips the afking flag
    /// @dev GAME-only. While afking, the Game-side compute-on-read owns the player's streak and
    ///      slot-0 completions are streak-neutral / reward-deferred; returns the synced streak
    ///      so the caller bases the run's snapshot on it.
    /// @param id Wallet ID of the subscriber starting an afking run
    /// @param currentDay The caller's current calendar day; quest state pins to the newest rolled day
    /// @return streak The player's gap-synced streak at the start of the run
    function beginAfking(uint32 id, uint24 currentDay) external returns (uint24 streak);

    /// @notice Ends an afking run: hands the afking-computed streak back to the manual system
    /// @dev GAME-only, called on every sub-ending path before the Sub slot is deleted.
    ///      Idempotent (a no-op unless the player is currently afking). Keeps the Game-computed
    ///      earned streak when no rolled quest day lies strictly between the newest valid mint
    ///      anchor and the current day; skipped stall days are never treated as playable misses.
    ///      Revert-free for any input (it runs on mineFlip sub-ending paths).
    /// @param id Wallet ID of the subscriber whose run is ending
    /// @param earnedStreak The run's earned streak (snapshot + funded delivered days), Game-computed
    /// @param afkingCoveredDay The Game-side handback anchor: the day before the sub ended,
    ///        floored at the afking funded high-water day
    /// @param currentDay The current calendar day (the decay reference)
    function finalizeAfking(uint32 id, uint24 earnedStreak, uint24 afkingCoveredDay, uint24 currentDay) external;

    /// @notice Returns the quest state for a specific player
    /// @dev Zero results for an untouched ID (including 0).
    /// @param id Wallet ID of the player to query
    /// @return streak The player's raw stored streak (not gap/shield-decayed; use getPlayerQuestView / effectiveBaseStreak for the effective value)
    /// @return lastCompletedDay The last day the player completed the primary (slot 0) quest
    /// @return progress The player's current progress on each of the two quests
    /// @return completed Whether the player has completed each of the two quests
    function playerQuestStates(uint32 id)
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

    /// @notice Credit the growth-bet participation quest for a player.
    /// @dev Called directly by PARIMUTUEL when a bet is placed, and gated on that identity.
    ///      Idempotence comes from PARIMUTUEL's one-bet-per-round gate, not this call itself —
    ///      the internal bit only short-circuits a repeat until level-quest progress rewrites
    ///      the word within the same version epoch. The address is kept because eligibility
    ///      reads `player`'s mint word on every rewarded bet; `id` keys the quest record and the
    ///      credit and must be the ID `marketBetGates(player, lvl)` returned in the same
    ///      transaction (PARIMUTUEL is trusted to pass that pair; `mayBet` implies it is nonzero).
    /// @param id Wallet ID of the bettor (from `marketBetGates`).
    /// @param player The bettor's address (its mint word is the eligibility source).
    /// @param lvl The level the bet was placed on, which the caller already read from the
    ///        game in this same call — passing it through saves re-reading it.
    /// @param reward FLIP to credit on first completion this level.
    /// @return paid The FLIP actually credited (0 when ineligible or already completed).
    function recordGrowthBet(uint32 id, address player, uint24 lvl, uint256 reward) external returns (uint256 paid);

    /// @notice The two gates the parimutuel growth market applies to a bet.
    /// @dev Read-only. earnsReward is recordGrowthBet's eligibility; mayBet is the weaker
    ///      lifetime bar — has this address ever bought anything. The wallet ID rides the mint
    ///      word this view already reads (bits 224-255). Every door that writes a nonzero mint
    ///      field registers the wallet first, so mayBet implies id != 0.
    /// @param player The player to test.
    /// @param lvl The level to test against.
    /// @return mayBet True if the player may place a bet at all.
    /// @return earnsReward True if the placement also earns the growth quest.
    /// @return id The player's wallet ID (0 if unregistered; never allocates).
    function marketBetGates(address player, uint24 lvl)
        external
        view
        returns (bool mayBet, bool earnsReward, uint32 id);

    /// @notice Returns a player's level quest state for frontend display.
    /// @dev `eligible` resolves the wallet's address through the wallet table and reads its
    ///      mint word. Zero results for an untouched ID (including 0).
    /// @param id Wallet ID of the player to query.
    /// @return questType The active level quest type (1-8, or 11 for the craps day-pass quest).
    /// @return progress The player's accumulated progress.
    /// @return target The target value for completion.
    /// @return completed Whether the player has completed the quest this level.
    /// @return eligible Whether the player is eligible for level quests.
    function getPlayerLevelQuestView(uint32 id)
        external
        view
        returns (uint8 questType, uint128 progress, uint256 target, bool completed, bool eligible);

    /// @notice Returns the player's daily quest view, including the effective
    ///         (gap/shield-decayed) base streak. A pure view — no mutation.
    /// @dev Per-player fields are zero for an untouched ID (including 0).
    /// @param id Wallet ID of the player to query.
    /// @return viewData The player's quest view with the effective baseStreak.
    function getPlayerQuestView(uint32 id)
        external
        view
        returns (PlayerQuestView memory viewData);

    /// @notice The player's decay-aware effective reward streak (getPlayerQuestView's baseStreak),
    ///         computed without materializing the per-quest view structs — a cheap read for scoring.
    /// @param id Wallet ID of the player to query (0 returns 0).
    /// @return The effective (decay-applied) reward streak.
    function effectiveBaseStreak(uint32 id) external view returns (uint32);

    /// @notice effectiveBaseStreak plus the player's afking-run flag, from one quest-state read.
    /// @dev Game's activity score passes the ID from the mint word it already holds.
    /// @param id Wallet ID of the player to query (0 returns (0, false)).
    /// @return streak The effective (decay-applied) reward streak.
    /// @return afking True while the player is mid afking-run.
    function effectiveBaseStreakAndAfking(uint32 id) external view returns (uint32 streak, bool afking);

}
