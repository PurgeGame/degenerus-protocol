# DegenerusQuests.sol -- Function-Level Audit

**Contract:** DegenerusQuests
**File:** contracts/DegenerusQuests.sol
**Lines:** 1603
**Solidity:** 0.8.34
**Implements:** IDegenerusQuests
**Audit date:** 2026-03-07

## Summary

Daily quest system with 2 concurrent quest slots (slot 0 fixed MINT_ETH, slot 1 weighted-random), 9 quest types across 6 handler functions (mint, flip, decimator, affiliate, lootbox, degenerette), seed-based quest type generation via VRF entropy, version-gated progress tracking, combo/pair completion, streak bonuses with uint24 clamping, streak shield consumption on missed days, and player quest view assembly for frontend UI. No ETH handling -- rewards are denominated in BURNIE token units and returned to caller (BurnieCoin) for application.

---

## Function Audit

### External -- Quest Admin

---

### `rollDailyQuest(uint48 day, uint256 entropy)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function rollDailyQuest(uint48 day, uint256 entropy) external onlyCoin returns (bool rolled, uint8[2] memory questTypes, bool highDifficulty)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `day` (uint48): quest day identifier; `entropy` (uint256): VRF entropy word |
| **Returns** | `rolled` (bool): always true; `questTypes` (uint8[2]): two quest types rolled; `highDifficulty` (bool): always false |

**State Reads:** None directly (delegates to `_rollDailyQuest`)
**State Writes:** None directly (delegates to `_rollDailyQuest`)

**Callers:** BurnieCoin contract (external, via onlyCoin gate)
**Callees:** `_rollDailyQuest(day, entropy)`

**ETH Flow:** None
**Invariants:** Only COIN or COINFLIP can call. Day monotonicity enforced by caller, not by this contract.
**NatSpec Accuracy:** NatSpec says COIN or COINFLIP only -- matches modifier. States entropy usage for two slots -- accurate. Says `rolled` always true -- correct. Says `highDifficulty` always false -- correct (difficulty feature removed).
**Gas Flags:** None -- thin wrapper delegating to private function.
**Verdict:** CORRECT

---

### `resetQuestStreak(address player)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function resetQuestStreak(address player) external onlyGame` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player whose streak to reset |
| **Returns** | None |

**State Reads:** `questPlayerState[player]`
**State Writes:** `questPlayerState[player].streak = 0`, `questPlayerState[player].baseStreak = 0`

**Callers:** DegenerusGame contract (external, via onlyGame gate)
**Callees:** None

**ETH Flow:** None
**Invariants:** Only GAME contract can reset streaks. Does not emit an event.
**NatSpec Accuracy:** No NatSpec provided for this function. Missing documentation.
**Gas Flags:** No event emitted on streak reset -- intentional for gas savings but inconsistent with `_questSyncState` which emits `QuestStreakReset`.
**Verdict:** CONCERN (informational) -- No NatSpec and no event emission. The `_questSyncState` function emits `QuestStreakReset` when streak goes to 0, but this explicit reset path does not. Off-chain indexers tracking streak resets may miss game-initiated resets. Functionally correct.

---

### `awardQuestStreakBonus(address player, uint16 amount, uint48 currentDay)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function awardQuestStreakBonus(address player, uint16 amount, uint48 currentDay) external onlyGame` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): recipient; `amount` (uint16): streak days to add; `currentDay` (uint48): current quest day |
| **Returns** | None |

**State Reads:** `questPlayerState[player].streak`, `questPlayerState[player].lastActiveDay`, plus reads from `_questSyncState`
**State Writes:** `questPlayerState[player].streak` (incremented, clamped at uint24 max), `questPlayerState[player].lastActiveDay` (updated if < currentDay24), plus writes from `_questSyncState`

**Callers:** DegenerusGame contract (external, via onlyGame gate)
**Callees:** `_questSyncState(state, player, currentDay)`

**ETH Flow:** None
**Invariants:** Silently returns on zero address, zero amount, or zero currentDay. Streak clamped at uint24 max (16,777,215). `_questSyncState` is called first, so missed-day streak reset happens before bonus is applied.
**NatSpec Accuracy:** Accurate. States clamp at uint24 max -- correct (code checks `updated > type(uint24).max`). States silent return on zero inputs -- correct.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### External -- Quest Handlers

---

### `handleMint(address player, uint32 quantity, bool paidWithEth)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function handleMint(address player, uint32 quantity, bool paidWithEth) external onlyCoin returns (uint256 reward, uint8 questType, uint32 streak, bool completed)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): minter; `quantity` (uint32): tickets minted; `paidWithEth` (bool): ETH vs BURNIE payment |
| **Returns** | `reward` (uint256): BURNIE earned; `questType` (uint8): quest type processed; `streak` (uint32): current streak; `completed` (bool): whether quest completed |

**State Reads:** `activeQuests`, `questPlayerState[player]`, reads from `_questSyncState`, `_questSyncProgress`, `_questHandleProgressSlot`
**State Writes:** Via `_questSyncState`, `_questSyncProgress`, `_questHandleProgressSlot`, `_questComplete`

**Callers:** BurnieCoin / BurnieCoinflip (external, via onlyCoin)
**Callees:** `_currentQuestDay`, `_questSyncState`, `_questTargetValue`, `_questHandleProgressSlot`, `questGame.mintPrice()` (only if paidWithEth)

**ETH Flow:** None
**Invariants:** Early exit on zero player/quantity/day. Iterates both slots since MINT_BURNIE could be in slot 0 or 1 (though in practice slot 0 is always MINT_ETH). For ETH mints, delta = quantity * mintPrice. For BURNIE mints, delta = quantity (whole ticket count). Aggregates rewards from both slots if both match.
**NatSpec Accuracy:** Accurate. States it covers both BURNIE and ETH paid mints -- correct. States iteration over both slots -- correct.
**Gas Flags:** When paidWithEth is false, `mintPrice` is uninitialized (0) and passed to `_questTargetValue`. For MINT_BURNIE quest type, `_questTargetValue` returns `QUEST_MINT_TARGET` (1) without using mintPrice -- safe. But mintPrice=0 is also passed to `_questHandleProgressSlot` which passes it to `_questCompleteWithPair` -> `_maybeCompleteOther` -> `_questReady`. In `_questReady`, if the other slot is an ETH-type quest, it would fetch mintPrice from game (the `currentPrice == 0` branch). So this is correct but involves an extra external call in the combo path.
**Verdict:** CORRECT

---

### `handleFlip(address player, uint256 flipCredit)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function handleFlip(address player, uint256 flipCredit) external onlyCoin returns (uint256 reward, uint8 questType, uint32 streak, bool completed)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): staker/unstaker; `flipCredit` (uint256): BURNIE amount in base units |
| **Returns** | `reward` (uint256): BURNIE earned; `questType` (uint8): quest type; `streak` (uint32): streak; `completed` (bool): completion flag |

**State Reads:** `activeQuests`, `questPlayerState[player]`
**State Writes:** `questPlayerState[player].progress[slotIndex]`, via `_questSyncProgress`, `_questCompleteWithPair`

**Callers:** BurnieCoin / BurnieCoinflip (external, via onlyCoin)
**Callees:** `_currentQuestDay`, `_questSyncState`, `_currentDayQuestOfType`, `_questSyncProgress`, `_clampedAdd128`, `_questTargetValue`, `_questCompleteWithPair`

**ETH Flow:** None
**Invariants:** Early exit on zero player/flipCredit/day. Returns early if no FLIP quest active today. Slot 1 completion requires slot 0 already complete (completionMask bit 0 check). Progress is clamped at uint128 max.
**NatSpec Accuracy:** Accurate. Says BURNIE base units -- correct.
**Gas Flags:** Emits `QuestProgressUpdated` even when target not met (intentional for frontend tracking). Calls `_questTargetValue` with mintPrice=0 -- for FLIP type this returns `QUEST_BURNIE_TARGET` without using mintPrice, so safe.
**Verdict:** CORRECT

---

### `handleDecimator(address player, uint256 burnAmount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function handleDecimator(address player, uint256 burnAmount) external onlyCoin returns (uint256 reward, uint8 questType, uint32 streak, bool completed)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): burner; `burnAmount` (uint256): BURNIE burned in base units |
| **Returns** | `reward` (uint256): BURNIE earned; `questType` (uint8): quest type; `streak` (uint32): streak; `completed` (bool): completion flag |

**State Reads:** `activeQuests`, `questPlayerState[player]`
**State Writes:** `questPlayerState[player].progress[slotIndex]`, via `_questSyncProgress`, `_questCompleteWithPair`

**Callers:** BurnieCoin / BurnieCoinflip (external, via onlyCoin)
**Callees:** `_currentQuestDay`, `_questSyncState`, `_currentDayQuestOfType`, `_questSyncProgress`, `_clampedAdd128`, `_questTargetValue`, `_questCompleteWithPair`

**ETH Flow:** None
**Invariants:** Same pattern as handleFlip. Early exit on zero inputs. Returns early if no DECIMATOR quest active. Slot 1 requires slot 0 complete. Target is QUEST_BURNIE_TARGET (2000 BURNIE).
**NatSpec Accuracy:** Accurate. States BURNIE base units and same target as flip (2000 BURNIE) -- correct.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `handleAffiliate(address player, uint256 amount)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function handleAffiliate(address player, uint256 amount) external onlyCoin returns (uint256 reward, uint8 questType, uint32 streak, bool completed)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): affiliate earner; `amount` (uint256): BURNIE earned from referrals |
| **Returns** | `reward` (uint256): BURNIE earned; `questType` (uint8): quest type; `streak` (uint32): streak; `completed` (bool): completion flag |

**State Reads:** `activeQuests`, `questPlayerState[player]`
**State Writes:** `questPlayerState[player].progress[slotIndex]`, via `_questSyncProgress`, `_questCompleteWithPair`

**Callers:** BurnieCoin / BurnieCoinflip (external, via onlyCoin)
**Callees:** `_currentQuestDay`, `_questSyncState`, `_currentDayQuestOfType`, `_questSyncProgress`, `_clampedAdd128`, `_questTargetValue`, `_questCompleteWithPair`

**ETH Flow:** None
**Invariants:** Same pattern as handleFlip/handleDecimator. Target is QUEST_BURNIE_TARGET (2000 BURNIE).
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `handleLootBox(address player, uint256 amountWei)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function handleLootBox(address player, uint256 amountWei) external onlyCoin returns (uint256 reward, uint8 questType, uint32 streak, bool completed)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): lootbox buyer; `amountWei` (uint256): ETH spent in wei |
| **Returns** | `reward` (uint256): BURNIE earned; `questType` (uint8): quest type; `streak` (uint32): streak; `completed` (bool): completion flag |

**State Reads:** `activeQuests`, `questPlayerState[player]`
**State Writes:** `questPlayerState[player].progress[slotIndex]`, via `_questSyncProgress`, `_questCompleteWithPair`

**Callers:** BurnieCoin / BurnieCoinflip (external, via onlyCoin)
**Callees:** `_currentQuestDay`, `_questSyncState`, `_currentDayQuestOfType`, `_questSyncProgress`, `_clampedAdd128`, `questGame.mintPrice()`, `_questTargetValue`, `_questCompleteWithPair`

**ETH Flow:** None (tracks ETH amounts but does not transfer ETH)
**Invariants:** Same handler pattern. Fetches mintPrice from game for target calculation. Target = mintPrice * 2, capped at 0.5 ETH. Slot 1 requires slot 0 complete.
**NatSpec Accuracy:** Accurate. States ETH target is 2x mint price capped at QUEST_ETH_TARGET_CAP -- correct.
**Gas Flags:** Always fetches mintPrice even if lootbox quest is not active (fetch happens after quest lookup, so only when quest found -- actually it is fetched unconditionally at line 725 before the target check). This means one external call even if progress < target. Minor gas informational.
**Verdict:** CORRECT

---

### `handleDegenerette(address player, uint256 amount, bool paidWithEth)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function handleDegenerette(address player, uint256 amount, bool paidWithEth) external onlyCoin returns (uint256 reward, uint8 questType, uint32 streak, bool completed)` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): bettor; `amount` (uint256): bet amount (wei for ETH, base units for BURNIE); `paidWithEth` (bool): payment type |
| **Returns** | `reward` (uint256): BURNIE earned; `questType` (uint8): quest type; `streak` (uint32): streak; `completed` (bool): completion flag |

**State Reads:** `activeQuests`, `questPlayerState[player]`
**State Writes:** Via `_questHandleProgressSlot`, `_questSyncProgress`, `_questComplete`

**Callers:** BurnieCoin / BurnieCoinflip (external, via onlyCoin)
**Callees:** `_currentQuestDay`, `_questSyncState`, `_currentDayQuestOfType`, `questGame.mintPrice()` (only if paidWithEth), `_questTargetValue`, `_questHandleProgressSlot`

**ETH Flow:** None
**Invariants:** Dispatches to either DEGENERETTE_ETH or DEGENERETTE_BURNIE quest type based on paidWithEth flag. For ETH, target = mintPrice * 2, capped at 0.5 ETH. For BURNIE, target = 2000 BURNIE. Uses `_questHandleProgressSlot` (shared progress path) rather than inline progress like other handlers.
**NatSpec Accuracy:** Accurate. States wei for ETH, base units for BURNIE -- correct.
**Gas Flags:** mintPrice only fetched when paidWithEth -- efficient.
**Verdict:** CORRECT

---

### External -- View Functions

---

### `getActiveQuests()` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function getActiveQuests() external view returns (QuestInfo[2] memory quests)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | None |
| **Returns** | `quests` (QuestInfo[2]): active quest info with type, day, requirements |

**State Reads:** `activeQuests` (via `_materializeActiveQuestsForView`)
**State Writes:** None

**Callers:** Frontend / any external caller
**Callees:** `_materializeActiveQuestsForView`, `_currentQuestDay`, `_questViewData`

**ETH Flow:** None
**Invariants:** Returns baseline quest data without player-specific progress. Creates an empty PlayerQuestState for the view data call, so progress is always 0 and completed is always false.
**NatSpec Accuracy:** Accurate. States frontends should use `getPlayerQuestView` for player-specific data -- correct.
**Gas Flags:** Calls `questGame.mintPrice()` for each ETH-type quest via `_questRequirements` -> `_questTargetValue`. This is 1-2 external calls per view.
**Verdict:** CORRECT

---

### `playerQuestStates(address player)` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function playerQuestStates(address player) external view override returns (uint32 streak, uint32 lastCompletedDay, uint128[2] memory progress, bool[2] memory completed)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | `player` (address): player to query |
| **Returns** | `streak` (uint32): current streak; `lastCompletedDay` (uint32): last full completion day; `progress` (uint128[2]): per-slot progress; `completed` (bool[2]): per-slot completion |

**State Reads:** `activeQuests`, `questPlayerState[player]`
**State Writes:** None

**Callers:** Frontend / any external caller, implements IDegenerusQuests
**Callees:** `_currentQuestDay`, `_questProgressValid`, `_questCompleted`

**ETH Flow:** None
**Invariants:** Returns raw state without streak decay preview. Progress zeroed if day/version mismatch. Completion uses `_questCompleted` which checks lastSyncDay and completionMask. Returns streak without decay preview (unlike `getPlayerQuestView`).
**NatSpec Accuracy:** States "raw player quest state for debugging/analytics" -- accurate. NatSpec on `lastCompletedDay` says "Last day where both quests were completed" -- but code uses `lastCompletedDay` which is set on first quest completion per day (not both). This is a NatSpec inaccuracy: the field tracks last day with ANY quest completed (streak credited), not BOTH.
**Gas Flags:** None.
**Verdict:** CONCERN (informational) -- NatSpec says `lastCompletedDay` is "Last day where BOTH quests completed" but it is actually set on the first quest completion of the day (when STREAK_CREDITED bit is set in `_questComplete`). The field name is misleading but functionally the code is correct.

---

### `getPlayerQuestView(address player)` [external view]

| Field | Value |
|-------|-------|
| **Signature** | `function getPlayerQuestView(address player) external view returns (PlayerQuestView memory viewData)` |
| **Visibility** | external |
| **Mutability** | view |
| **Parameters** | `player` (address): player to query |
| **Returns** | `viewData` (PlayerQuestView): comprehensive view with quests, progress, completion, streak |

**State Reads:** `activeQuests`, `questPlayerState[player]`, `questStreakShieldCount[player]`
**State Writes:** None

**Callers:** Frontend / any external caller (recommended view function)
**Callees:** `_materializeActiveQuestsForView`, `_currentQuestDay`, `_questViewData`

**ETH Flow:** None
**Invariants:** Previews streak decay: if player missed days beyond shield coverage, shows effectiveStreak=0. Uses `lastActiveDay` as anchor (falls back to `lastCompletedDay`). If already synced today, uses `baseStreak`; otherwise previews effective streak.
**NatSpec Accuracy:** Accurate. States streak decay preview -- correct.
**Gas Flags:** May call `questGame.mintPrice()` 1-2 times through `_questViewData` -> `_questRequirements`. View function gas cost acceptable.
**Verdict:** CORRECT

---

### `_materializeActiveQuestsForView()` [private view]

| Field | Value |
|-------|-------|
| **Signature** | `function _materializeActiveQuestsForView() private view returns (DailyQuest[QUEST_SLOT_COUNT] memory local)` |
| **Visibility** | private |
| **Mutability** | view |
| **Parameters** | None |
| **Returns** | `local` (DailyQuest[2]): memory copy of active quests |

**State Reads:** `activeQuests`
**State Writes:** None

**Callers:** `getActiveQuests`, `getPlayerQuestView`
**Callees:** None

**ETH Flow:** None
**Invariants:** Simple storage-to-memory copy.
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None. Provides consistent memory copy for view functions.
**Verdict:** CORRECT

---

### Private -- Quest Rolling

---

### `_rollDailyQuest(uint48 day, uint256 entropy)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _rollDailyQuest(uint48 day, uint256 entropy) private returns (bool rolled, uint8[2] memory questTypes, bool highDifficulty)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `day` (uint48): quest day; `entropy` (uint256): VRF entropy |
| **Returns** | `rolled` (bool): always true; `questTypes` (uint8[2]): selected types; `highDifficulty` (bool): always false |

**State Reads:** `activeQuests` (storage reference), reads from `_canRollDecimatorQuest`
**State Writes:** `activeQuests[0]`, `activeQuests[1]` (via `_seedQuestType`), `questVersionCounter` (via `_nextQuestVersion`)

**Callers:** `rollDailyQuest`
**Callees:** `_canRollDecimatorQuest`, `_bonusQuestType`, `_seedQuestType` (x2), `_nextQuestVersion` (x2 via _seedQuestType)

**ETH Flow:** None
**Invariants:** Slot 0 is always QUEST_TYPE_MINT_ETH. Slot 1 is weighted-random excluding the primary type. Entropy halves swapped for slot 1 to derive independent randomness. Two `QuestSlotRolled` events emitted. No day-overlap check (caller responsible for day monotonicity). Always overwrites existing quests regardless of whether already rolled for this day.
**NatSpec Accuracy:** Accurate. States slot 0 fixed to MINT_ETH, slot 1 weighted-random distinct from slot 0 -- correct.
**Gas Flags:** No guard against re-rolling same day (caller-enforced). Two version bumps per roll.
**Verdict:** CORRECT

---

### `_canRollDecimatorQuest()` [private view]

| Field | Value |
|-------|-------|
| **Signature** | `function _canRollDecimatorQuest() private view returns (bool)` |
| **Visibility** | private |
| **Mutability** | view |
| **Parameters** | None |
| **Returns** | `bool`: whether decimator quests can be rolled |

**State Reads:** None (reads from external contract)
**State Writes:** None

**Callers:** `_rollDailyQuest`
**Callees:** `questGame.decWindowOpenFlag()`, `questGame.level()`

**ETH Flow:** None
**Invariants:** Returns true when: (1) decWindowOpenFlag is true AND (2) level is a multiple of 100 (non-zero) OR level ends in 5 but not 95. Level 0 returns false. Level 5, 15, 25, 35 return true. Level 95, 195 return false. Level 100, 200 return true.
**NatSpec Accuracy:** Accurate. Documents availability rules clearly.
**Gas Flags:** Two external calls to questGame. View function, acceptable.
**Verdict:** CORRECT

---

### `_nextQuestVersion()` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _nextQuestVersion() private returns (uint24 newVersion)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | None |
| **Returns** | `newVersion` (uint24): the version number (pre-increment value) |

**State Reads:** `questVersionCounter`
**State Writes:** `questVersionCounter` (incremented by 1)

**Callers:** `_seedQuestType`
**Callees:** None

**ETH Flow:** None
**Invariants:** Monotonically increasing. Uses post-increment (returns current then increments). At uint24 max (16,777,215), the next increment wraps to 0 due to Solidity 0.8 overflow on uint24. However, this is unchecked arithmetic in the `++` operator -- actually in Solidity 0.8.34, `questVersionCounter++` is checked and would revert on overflow. This would brick quest rolling after 16M version bumps (~8M days at 2 per day = ~22,000 years). Not a practical concern.
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `_seedQuestType(DailyQuest storage quest, uint48 day, uint8 questType)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _seedQuestType(DailyQuest storage quest, uint48 day, uint8 questType) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `quest` (DailyQuest storage): slot to seed; `day` (uint48): quest day; `questType` (uint8): type to seed |
| **Returns** | None |

**State Reads:** None directly
**State Writes:** `quest.day`, `quest.questType`, `quest.version` (via `_nextQuestVersion`), `questVersionCounter` (indirectly)

**Callers:** `_rollDailyQuest`
**Callees:** `_nextQuestVersion`

**ETH Flow:** None
**Invariants:** Does not set `quest.flags` or `quest.difficulty` -- they retain previous values or default to 0. Since difficulty is "unused; retained for storage compatibility" per struct definition, this is intentional.
**NatSpec Accuracy:** Accurate. States version bump invalidates stale progress -- correct.
**Gas Flags:** Does not clear `flags` or `difficulty` fields. Pre-existing values persist but are not used. Minor storage efficiency note.
**Verdict:** CORRECT

---

### `_bonusQuestType(uint256 entropy, uint8 primaryType, bool decAllowed)` [private pure]

| Field | Value |
|-------|-------|
| **Signature** | `function _bonusQuestType(uint256 entropy, uint8 primaryType, bool decAllowed) private pure returns (uint8)` |
| **Visibility** | private |
| **Mutability** | pure |
| **Parameters** | `entropy` (uint256): VRF-derived entropy; `primaryType` (uint8): type to exclude; `decAllowed` (bool): decimator eligibility |
| **Returns** | `uint8`: selected bonus quest type |

**State Reads:** None (pure)
**State Writes:** None (pure)

**Callers:** `_rollDailyQuest`
**Callees:** None

**ETH Flow:** None
**Invariants:** Excludes primary type and QUEST_TYPE_RESERVED (4). Weights: MINT_BURNIE=10, FLIP=4, DECIMATOR=4 (if allowed), LOOTBOX=3, all others=1. Total weight when all types available (excluding primary MINT_ETH and RESERVED): 10+4+1+4+3+1+1 = 24. When decimator disabled: 10+4+1+3+1+1 = 20. Weighted random selection uses modulo. Fallback returns AFFILIATE if primary is MINT_ETH, else MINT_ETH.
**NatSpec Accuracy:** Accurate. Weights documented correctly. States DEGENERETTE_ETH and DEGENERETTE_BURNIE use base weight (1x) -- confirmed in code.
**Gas Flags:** Allocates a memory array of 9 uint16s for weights. Two loop iterations over QUEST_TYPE_COUNT. Efficient for the operation.
**Verdict:** CORRECT

---

### Private -- Quest Progress

---

### `_questHandleProgressSlot(...)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _questHandleProgressSlot(address player, PlayerQuestState storage state, DailyQuest[QUEST_SLOT_COUNT] memory quests, DailyQuest memory quest, uint8 slot, uint256 delta, uint256 target, uint48 currentDay, uint256 mintPrice) private returns (uint256 reward, uint8 questType, uint32 streak, bool completed)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player; `state` (storage): player state; `quests` (memory): active quests; `quest` (memory): specific quest; `slot` (uint8): slot index; `delta` (uint256): progress to add; `target` (uint256): completion target; `currentDay` (uint48): current day; `mintPrice` (uint256): cached mint price |
| **Returns** | `reward`, `questType`, `streak`, `completed` |

**State Reads:** Via `_questSyncProgress`
**State Writes:** `state.progress[slot]` (via `_clampedAdd128`), `state.lastProgressDay[slot]`, `state.lastQuestVersion[slot]` (via `_questSyncProgress`), plus writes from `_questCompleteWithPair`

**Callers:** `handleMint`, `handleDegenerette`
**Callees:** `_questSyncProgress`, `_clampedAdd128`, `_questCompleteWithPair`

**ETH Flow:** None
**Invariants:** Syncs progress first (resets if stale). Adds delta clamped at uint128 max. Emits `QuestProgressUpdated`. If progress >= target, checks slot-1-requires-slot-0 rule before completing. Returns incomplete (0 reward) if target not met.
**NatSpec Accuracy:** Accurate. Parameters well-documented.
**Gas Flags:** Uses `quest.day` for sync (not `currentDay`) in the event emission -- this is correct since quest.day is the active day.
**Verdict:** CORRECT

---

### `_questSyncState(PlayerQuestState storage state, address player, uint48 currentDay)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _questSyncState(PlayerQuestState storage state, address player, uint48 currentDay) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `state` (storage): player state; `player` (address): player for events/shield lookup; `currentDay` (uint48): current quest day |
| **Returns** | None |

**State Reads:** `state.streak`, `state.lastActiveDay`, `state.lastCompletedDay`, `questStreakShieldCount[player]`, `state.lastSyncDay`
**State Writes:** `questStreakShieldCount[player]` (decremented by used shields), `state.streak` (reset to 0 if days missed beyond shields), `state.lastSyncDay`, `state.completionMask` (reset to 0), `state.baseStreak` (snapshot of streak)

**Callers:** `awardQuestStreakBonus`, `handleMint`, `handleFlip`, `handleDecimator`, `handleAffiliate`, `handleLootBox`, `handleDegenerette`
**Callees:** None

**ETH Flow:** None
**Invariants:** Uses `lastActiveDay` as anchor (any slot completion), falls back to `lastCompletedDay`. If gap > 1 day, shields are consumed first. If missedDays > shields, streak resets to 0 (shields also fully consumed). On new day (lastSyncDay != currentDay), resets completionMask and snapshots baseStreak. Idempotent within same day (lastSyncDay check).
**NatSpec Accuracy:** Accurate. Streak reset logic documented correctly. baseStreak snapshot documented.
**Gas Flags:** Reads `questStreakShieldCount[player]` even when anchorDay == 0 (no-op path). Actually no -- the outer check `anchorDay != 0` gates the shield logic. Correct.
**Verdict:** CORRECT

---

### `_questSyncProgress(PlayerQuestState storage state, uint8 slot, uint48 currentDay, uint24 questVersion)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _questSyncProgress(PlayerQuestState storage state, uint8 slot, uint48 currentDay, uint24 questVersion) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `state` (storage): player state; `slot` (uint8): slot index; `currentDay` (uint48): current day; `questVersion` (uint24): current quest version |
| **Returns** | None |

**State Reads:** `state.lastProgressDay[slot]`, `state.lastQuestVersion[slot]`
**State Writes:** `state.lastProgressDay[slot]`, `state.lastQuestVersion[slot]`, `state.progress[slot]` (reset to 0 on mismatch)

**Callers:** `handleFlip`, `handleDecimator`, `handleAffiliate`, `handleLootBox`, `_questHandleProgressSlot`
**Callees:** None

**ETH Flow:** None
**Invariants:** Key anti-exploit mechanism. Resets progress to 0 when day or version changes. Prevents stale progress from a previous day or quest version from counting toward today's quest. Truncates currentDay to uint24 (safe since max uint48 day value is within uint24 range for ~45,000 years).
**NatSpec Accuracy:** Accurate. Describes anti-exploit purpose well.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `_questProgressValid(PlayerQuestState memory state, DailyQuest memory quest, uint8 slot, uint48 currentDay)` [private pure]

| Field | Value |
|-------|-------|
| **Signature** | `function _questProgressValid(PlayerQuestState memory state, DailyQuest memory quest, uint8 slot, uint48 currentDay) private pure returns (bool)` |
| **Visibility** | private |
| **Mutability** | pure |
| **Parameters** | `state` (memory): player state; `quest` (memory): quest to validate; `slot` (uint8): slot index; `currentDay` (uint48): current day |
| **Returns** | `bool`: whether progress is valid |

**State Reads:** None (pure, uses memory params)
**State Writes:** None

**Callers:** `playerQuestStates`, `_questViewData`
**Callees:** None

**ETH Flow:** None
**Invariants:** Returns false if quest.day is 0 or doesn't match currentDay. Returns true only if player's lastProgressDay and lastQuestVersion match the quest for this slot.
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `_questProgressValidStorage(PlayerQuestState storage state, DailyQuest memory quest, uint8 slot, uint48 currentDay)` [private view]

| Field | Value |
|-------|-------|
| **Signature** | `function _questProgressValidStorage(PlayerQuestState storage state, DailyQuest memory quest, uint8 slot, uint48 currentDay) private view returns (bool)` |
| **Visibility** | private |
| **Mutability** | view |
| **Parameters** | `state` (storage): player state; `quest` (memory): quest to validate; `slot` (uint8): slot index; `currentDay` (uint48): current day |
| **Returns** | `bool`: whether progress is valid |

**State Reads:** `state.lastProgressDay[slot]`, `state.lastQuestVersion[slot]`
**State Writes:** None

**Callers:** `_questReady`
**Callees:** None

**ETH Flow:** None
**Invariants:** Identical logic to `_questProgressValid` but reads from storage instead of memory. Avoids copying full PlayerQuestState to memory when only checking validity.
**NatSpec Accuracy:** Accurate. Documents the storage-aware optimization.
**Gas Flags:** None. The storage variant is more gas-efficient than copying state to memory when only a validity check is needed.
**Verdict:** CORRECT

---

### `_questReady(PlayerQuestState storage state, DailyQuest memory quest, uint8 slot, uint256 mintPrice)` [private view]

| Field | Value |
|-------|-------|
| **Signature** | `function _questReady(PlayerQuestState storage state, DailyQuest memory quest, uint8 slot, uint256 mintPrice) private view returns (bool)` |
| **Visibility** | private |
| **Mutability** | view |
| **Parameters** | `state` (storage): player state; `quest` (memory): quest to check; `slot` (uint8): slot index; `mintPrice` (uint256): cached mint price (0 to auto-fetch) |
| **Returns** | `bool`: whether progress >= target |

**State Reads:** `state.progress[slot]`, `state.lastProgressDay[slot]`, `state.lastQuestVersion[slot]` (via `_questProgressValidStorage`)
**State Writes:** None

**Callers:** `_maybeCompleteOther`
**Callees:** `_questProgressValidStorage`, `questGame.mintPrice()` (conditional), `_questTargetValue`

**ETH Flow:** None
**Invariants:** Returns false if progress is invalid (stale). Auto-fetches mintPrice from game if not cached and quest type is ETH-based. Returns false if target is 0. Returns true if progress >= target.
**NatSpec Accuracy:** Accurate.
**Gas Flags:** Potential external call to `questGame.mintPrice()` if mintPrice=0 and quest is ETH-based. This is the combo-completion path where the paired quest's mint price may not have been cached by the calling handler.
**Verdict:** CORRECT

---

### Private -- Quest Completion

---

### `_questCompleted(PlayerQuestState memory state, DailyQuest memory quest, uint8 slot)` [private pure]

| Field | Value |
|-------|-------|
| **Signature** | `function _questCompleted(PlayerQuestState memory state, DailyQuest memory quest, uint8 slot) private pure returns (bool)` |
| **Visibility** | private |
| **Mutability** | pure |
| **Parameters** | `state` (memory): player state; `quest` (memory): quest to check; `slot` (uint8): slot index |
| **Returns** | `bool`: whether slot is complete |

**State Reads:** None (pure)
**State Writes:** None

**Callers:** `playerQuestStates`, `_questViewData`
**Callees:** None

**ETH Flow:** None
**Invariants:** Returns false if quest.day is 0. Checks that player's lastSyncDay matches quest day and the completion mask bit for the slot is set.
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `_questComplete(address player, PlayerQuestState storage state, uint8 slot, DailyQuest memory quest)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _questComplete(address player, PlayerQuestState storage state, uint8 slot, DailyQuest memory quest) private returns (uint256 reward, uint8 questType, uint32 streak, bool completed)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): player; `state` (storage): player state; `slot` (uint8): slot index; `quest` (memory): completed quest |
| **Returns** | `reward` (uint256): BURNIE earned; `questType` (uint8): quest type; `streak` (uint32): streak; `completed` (bool): success |

**State Reads:** `state.completionMask`, `state.lastActiveDay`, `state.streak`
**State Writes:** `state.completionMask` (slot bit + STREAK_CREDITED), `state.lastActiveDay`, `state.streak` (incremented on first daily completion), `state.lastCompletedDay`

**Callers:** `_questCompleteWithPair`, `_maybeCompleteOther`
**Callees:** None

**ETH Flow:** None
**Invariants:** Idempotent -- returns (0, type, streak, false) if slot already completed. Streak incremented only once per day (STREAK_CREDITED bit). Streak clamped at uint24 max. Reward: slot 0 = 100 BURNIE, slot 1 = 200 BURNIE. Emits `QuestCompleted` event.
**NatSpec Accuracy:** Accurate. Documents streak logic and reward calculation.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `_questCompleteWithPair(address player, PlayerQuestState storage state, DailyQuest[QUEST_SLOT_COUNT] memory quests, uint8 slot, DailyQuest memory quest, uint48 currentDay, uint256 mintPrice)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _questCompleteWithPair(address player, PlayerQuestState storage state, DailyQuest[QUEST_SLOT_COUNT] memory quests, uint8 slot, DailyQuest memory quest, uint48 currentDay, uint256 mintPrice) private returns (uint256 reward, uint8 questType, uint32 streak, bool completed)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player`, `state`, `quests`, `slot`, `quest`, `currentDay`, `mintPrice` |
| **Returns** | `reward`, `questType`, `streak`, `completed` |

**State Reads:** Via `_questComplete`, `_maybeCompleteOther`
**State Writes:** Via `_questComplete`, `_maybeCompleteOther`

**Callers:** `handleFlip`, `handleDecimator`, `handleAffiliate`, `handleLootBox`, `_questHandleProgressSlot`
**Callees:** `_questComplete`, `_maybeCompleteOther`

**ETH Flow:** None
**Invariants:** Completes the current slot, then checks the other slot (XOR flip: 0->1, 1->0). If other slot's progress already meets target, completes it too ("combo completion"). Aggregates rewards from both completions. Returns completed=true even if only the primary slot completed.
**NatSpec Accuracy:** Accurate. Documents combo completion UX optimization.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `_maybeCompleteOther(address player, PlayerQuestState storage state, DailyQuest[QUEST_SLOT_COUNT] memory quests, uint8 slot, uint48 currentDay, uint256 mintPrice)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _maybeCompleteOther(address player, PlayerQuestState storage state, DailyQuest[QUEST_SLOT_COUNT] memory quests, uint8 slot, uint48 currentDay, uint256 mintPrice) private returns (uint256 reward, uint8 questType, uint32 streak, bool completed)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player`, `state`, `quests`, `slot`, `currentDay`, `mintPrice` |
| **Returns** | `reward`, `questType`, `streak`, `completed` |

**State Reads:** `state.completionMask`, via `_questReady`
**State Writes:** Via `_questComplete`

**Callers:** `_questCompleteWithPair`
**Callees:** `_questReady`, `_questComplete`

**ETH Flow:** None
**Invariants:** Skips if quest not for today or already completed. Uses `_questReady` to check if progress >= target with valid day/version. Only completes if ready.
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `_questTargetValue(DailyQuest memory quest, uint8 slot, uint256 mintPrice)` [private pure]

| Field | Value |
|-------|-------|
| **Signature** | `function _questTargetValue(DailyQuest memory quest, uint8 slot, uint256 mintPrice) private pure returns (uint256)` |
| **Visibility** | private |
| **Mutability** | pure |
| **Parameters** | `quest` (memory): quest definition; `slot` (uint8): slot index; `mintPrice` (uint256): current mint price in wei |
| **Returns** | `uint256`: target value in quest-type-specific units |

**State Reads:** None (pure)
**State Writes:** None

**Callers:** `handleMint`, `handleFlip`, `handleDecimator`, `handleAffiliate`, `handleLootBox`, `handleDegenerette`, `_questHandleProgressSlot`, `_questReady`, `_questRequirements`
**Callees:** None

**ETH Flow:** None
**Invariants:**
- MINT_ETH: slot 0 = mintPrice * 1 (deposit), slot 1 = mintPrice * 2 (lootbox multiplier). Capped at 0.5 ETH.
- LOOTBOX, DEGENERETTE_ETH: mintPrice * 2, capped at 0.5 ETH.
- MINT_BURNIE: 1 (one ticket).
- FLIP, DECIMATOR, AFFILIATE, DEGENERETTE_BURNIE: 2000 BURNIE (QUEST_BURNIE_TARGET).
- Unknown types: 0 (should never happen).
**NatSpec Accuracy:** Accurate. States "fixed targets" -- correct.
**Gas Flags:** The MINT_ETH path uses slot index to determine multiplier, which means slot 0 target = 1x mintPrice and slot 1 target = 2x mintPrice. In practice MINT_ETH is always slot 0 (primary), so the slot 1 multiplier for MINT_ETH should never be used. But if by any code change MINT_ETH appeared in slot 1, the target would be 2x. This is a defensive design, not a bug.
**Verdict:** CORRECT

---

### Private -- Utility

---

### `_questViewData(DailyQuest memory quest, PlayerQuestState memory state, uint8 slot, uint48 currentDay)` [private view]

| Field | Value |
|-------|-------|
| **Signature** | `function _questViewData(DailyQuest memory quest, PlayerQuestState memory state, uint8 slot, uint48 currentDay) private view returns (QuestInfo memory info, uint128 progress, bool completed)` |
| **Visibility** | private |
| **Mutability** | view |
| **Parameters** | `quest` (memory): quest data; `state` (memory): player state; `slot` (uint8): slot index; `currentDay` (uint48): current day |
| **Returns** | `info` (QuestInfo): packed quest info; `progress` (uint128): validated progress; `completed` (bool): completion flag |

**State Reads:** Via `_questRequirements` -> `questGame.mintPrice()` (for ETH-type quests)
**State Writes:** None

**Callers:** `getActiveQuests`, `getPlayerQuestView`
**Callees:** `_questRequirements`, `_questProgressValid`, `_questCompleted`

**ETH Flow:** None
**Invariants:** Packs quest into QuestInfo struct with requirements. Progress only included if valid. Completed checks slot mask.
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### `_questRequirements(DailyQuest memory quest, uint8 slot)` [private view]

| Field | Value |
|-------|-------|
| **Signature** | `function _questRequirements(DailyQuest memory quest, uint8 slot) private view returns (QuestRequirements memory req)` |
| **Visibility** | private |
| **Mutability** | view |
| **Parameters** | `quest` (memory): quest definition; `slot` (uint8): slot index |
| **Returns** | `req` (QuestRequirements): requirements with mints or tokenAmount |

**State Reads:** Via `questGame.mintPrice()` (for ETH-type quests)
**State Writes:** None

**Callers:** `_questViewData`
**Callees:** `_questTargetValue`, `questGame.mintPrice()`

**ETH Flow:** None
**Invariants:** For MINT_BURNIE, sets `req.mints` as uint32 of target (1). For all others, sets `req.tokenAmount`. Fetches mintPrice for ETH-based quest types (MINT_ETH, LOOTBOX, DEGENERETTE_ETH).
**NatSpec Accuracy:** Accurate. Documents which types use mints vs tokenAmount.
**Gas Flags:** External call to questGame.mintPrice() for each ETH-type quest in view context. Acceptable.
**Verdict:** CORRECT

---

### `_currentDayQuestOfType(DailyQuest[QUEST_SLOT_COUNT] memory quests, uint48 currentDay, uint8 questType)` [private pure]

| Field | Value |
|-------|-------|
| **Signature** | `function _currentDayQuestOfType(DailyQuest[QUEST_SLOT_COUNT] memory quests, uint48 currentDay, uint8 questType) private pure returns (DailyQuest memory quest, uint8 slotIndex)` |
| **Visibility** | private |
| **Mutability** | pure |
| **Parameters** | `quests` (memory): active quests; `currentDay` (uint48): current day; `questType` (uint8): type to find |
| **Returns** | `quest` (DailyQuest): matching quest; `slotIndex` (uint8): slot index (type(uint8).max if not found) |

**State Reads:** None (pure)
**State Writes:** None

**Callers:** `handleFlip`, `handleDecimator`, `handleAffiliate`, `handleLootBox`, `handleDegenerette`
**Callees:** None

**ETH Flow:** None
**Invariants:** Returns sentinel (type(uint8).max = 255) if no matching quest found for the current day. Iterates both slots, returns first match.
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None. Simple loop over 2 elements.
**Verdict:** CORRECT

---

### `_clampedAdd128(uint128 current, uint256 delta)` [private pure]

| Field | Value |
|-------|-------|
| **Signature** | `function _clampedAdd128(uint128 current, uint256 delta) private pure returns (uint128)` |
| **Visibility** | private |
| **Mutability** | pure |
| **Parameters** | `current` (uint128): current value; `delta` (uint256): amount to add |
| **Returns** | `uint128`: sum capped at uint128 max |

**State Reads:** None (pure)
**State Writes:** None

**Callers:** `handleFlip`, `handleDecimator`, `handleAffiliate`, `handleLootBox`, `_questHandleProgressSlot`
**Callees:** None

**ETH Flow:** None
**Invariants:** Uses unchecked block for gas efficiency. Widens to uint256, adds, caps at type(uint128).max. Cannot overflow uint256 since max(uint128) + max(uint256) = ~2^256 which wraps in unchecked, but the cap check at uint128 max means the result is always safe.

Wait -- in unchecked, `uint256(current) + delta` can overflow uint256 if delta is near max(uint256). However, the calling code passes concrete game amounts (BURNIE amounts, ETH amounts) that are nowhere near uint256 max. The cap check would fail silently on uint256 overflow (wrapping). This is a theoretical concern but practically impossible given real-world token amounts.

**NatSpec Accuracy:** Accurate. Documents unchecked gas optimization.
**Gas Flags:** Unchecked block is appropriate for the clamping pattern.
**Verdict:** CORRECT -- theoretical uint256 overflow is impossible in practice (delta comes from game amounts capped by token supply)

---

### `_currentQuestDay(DailyQuest[QUEST_SLOT_COUNT] memory quests)` [private pure]

| Field | Value |
|-------|-------|
| **Signature** | `function _currentQuestDay(DailyQuest[QUEST_SLOT_COUNT] memory quests) private pure returns (uint48)` |
| **Visibility** | private |
| **Mutability** | pure |
| **Parameters** | `quests` (memory): active quests array |
| **Returns** | `uint48`: current quest day (0 if no quests) |

**State Reads:** None (pure)
**State Writes:** None

**Callers:** `handleMint`, `handleFlip`, `handleDecimator`, `handleAffiliate`, `handleLootBox`, `handleDegenerette`, `getActiveQuests`, `getPlayerQuestView`, `playerQuestStates`
**Callees:** None

**ETH Flow:** None
**Invariants:** Prefers slot 0 day. Falls back to slot 1 day. Returns 0 if neither slot has a quest (triggers early exit in handlers).
**NatSpec Accuracy:** Accurate.
**Gas Flags:** None.
**Verdict:** CORRECT

---

### Modifiers

---

### `onlyCoin()` [modifier]

| Field | Value |
|-------|-------|
| **Signature** | `modifier onlyCoin()` |
| **Visibility** | N/A (modifier) |

**State Reads:** None (compares msg.sender against compile-time constants)
**State Writes:** None

**Callers:** Applied to: `rollDailyQuest`, `handleMint`, `handleFlip`, `handleDecimator`, `handleAffiliate`, `handleLootBox`, `handleDegenerette`
**Callees:** None

**Invariants:** Allows both COIN and COINFLIP contracts. Reverts with `OnlyCoin()`.
**NatSpec Accuracy:** NatSpec says "Restricts access to the authorized COIN or COINFLIP contract" -- accurate.
**Gas Flags:** Caches msg.sender in local variable for two comparisons -- minor gas optimization.
**Verdict:** CORRECT

---

### `onlyGame()` [modifier]

| Field | Value |
|-------|-------|
| **Signature** | `modifier onlyGame()` |
| **Visibility** | N/A (modifier) |

**State Reads:** None (compares msg.sender against compile-time constant)
**State Writes:** None

**Callers:** Applied to: `resetQuestStreak`, `awardQuestStreakBonus`
**Callees:** None

**Invariants:** Allows only GAME contract. Reverts with `OnlyGame()`.
**NatSpec Accuracy:** No NatSpec on the modifier itself, but usage is clear from function-level docs.
**Gas Flags:** None.
**Verdict:** CORRECT
