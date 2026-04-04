# Level Quest System -- Integration Map

**Phase:** 154-integration-mapping
**Author:** Agent (Phase 154-01)
**Status:** Complete
**Input:** 153-01-LEVEL-QUEST-SPEC.md (Phase 153 design spec)
**Requirements:** INTG-01, INTG-02

---

## 1. Contract Touchpoint Map (INTG-01)

### 1.1 DegenerusQuests.sol -- CHANGES NEEDED

**Path:** `contracts/DegenerusQuests.sol`
**Why:** Houses all daily quest logic; level quests are a parallel system with identical handler entry points.
**Spec reference:** Phase 153 Sections 2, 3, 4, 5, 6

**New Storage:**

| Variable | Type | Location | Purpose |
|---|---|---|---|
| `levelQuestType` | `mapping(uint24 => uint8)` | After `questVersionCounter` (line 277) | Global quest type per level |
| `levelQuestPlayerState` | `mapping(address => uint256)` | After `levelQuestType` | Packed per-player progress (24-bit questLevel + 128-bit progress + 1-bit completed) |

**New Internal Functions:**

| Function | Signature | Purpose |
|---|---|---|
| `_isLevelQuestEligible` | `(address player) -> bool` | Eligibility check: (levelStreak >= 5 OR pass) AND (levelUnits >= 4 this level) |
| `_levelQuestTargetValue` | `(uint8 questType, uint256 mintPrice) -> uint256` | Derive 10x target from type + mintPrice (no cap) |
| `_handleLevelQuestProgress` | `(address player, uint8 questType, uint256 delta, uint256 mintPrice) -> (uint256 levelReward)` | Shared level quest progress logic called by each handleX |
| `rollLevelQuest` | `(uint24 lvl, uint256 entropy) external onlyCoin` | Roll level quest type at level transition; stores `levelQuestType[lvl]` |

**Modified Functions (all 6 handlers):**

Each handleX function gains a level quest progress block AFTER the existing daily quest logic. The modification pattern is identical for all 6 handlers (see Section 5 for per-handler specifics).

| Function | Line | Modification |
|---|---|---|
| `handleMint` | 440 | Add level quest progress tracking after line 523 (daily quest return) |
| `handleFlip` | 538 | Add level quest progress tracking after line 578 (daily quest return) |
| `handleDecimator` | 593 | Add level quest progress tracking after line 630 (daily quest return) |
| `handleAffiliate` | 644 | Add level quest progress tracking after line 681 (daily quest return) |
| `handleLootBox` | 697 | Add level quest progress tracking after line 735 (daily quest return) |
| `handleDegenerette` | 750 | Add level quest progress tracking after line 788 (daily quest return) |

**Design rationale (resolves Phase 153 Section 8 Q1):** Storage and logic live in DegenerusQuests.sol because:
1. All 6 handleX entry points already live here -- no new cross-contract reads needed for quest type matching.
2. The existing `onlyCoin` access control pattern is already established.
3. The `questGame` immutable reference provides access to `mintPacked_`, `deityPassCount`, `mintPrice`, `level`, and `decWindowOpenFlag` for eligibility and target derivation.
4. Placing storage in DegenerusGameStorage.sol would require cross-contract reads from DegenerusQuests.sol to game storage, adding gas cost and complexity.

**Trade-off:** DegenerusQuests.sol is a standalone contract (not delegatecall). To call `creditFlip` from completion logic, the quest contract must be added to `onlyFlipCreditors` in BurnieCoinflip.sol. See Section 1.6 for the analysis of why Option C (direct creditFlip from quest contract) is recommended.

---

### 1.2 IDegenerusQuests.sol -- CHANGES NEEDED

**Path:** `contracts/interfaces/IDegenerusQuests.sol`
**Why:** New public functions and events for level quest system.
**Spec reference:** Phase 153 Sections 2, 6

**New Event:**

```solidity
event LevelQuestCompleted(
    address indexed player,
    uint24 indexed level,
    uint8 questType,
    uint256 reward
);
```

**New Functions:**

```solidity
/// @notice Roll the level quest for a given level using provided entropy.
/// @dev Called by BurnieCoin during level transition.
/// @param lvl The level to roll a quest for.
/// @param entropy VRF-derived entropy for quest type selection.
function rollLevelQuest(uint24 lvl, uint256 entropy) external;

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
```

**No changes to handler signatures:** Level quest progress piggybacks on existing handleX calls. The return values remain `(uint256 reward, uint8 questType, uint32 streak, bool completed)` -- these continue to reflect daily quest status only. Level quest reward information flows through a separate mechanism (see Section 7).

---

### 1.3 DegenerusGameAdvanceModule.sol -- CHANGES NEEDED

**Path:** `contracts/modules/DegenerusGameAdvanceModule.sol`
**Why:** Level quest roll must occur during level transition.
**Spec reference:** Phase 153 Section 2

**Modified Function: `advanceGame()` phaseTransitionActive block (lines 260-291)**

Insertion point: after FF drain completes (line 283), before `phaseTransitionActive = false` (line 284).

Current flow at lines 277-291:
```
277: (bool ffWorked, bool ffFinished, ) = _processFutureTicketBatch(ffLevel);
280: if (ffWorked || !ffFinished) { stage = STAGE_TRANSITION_WORKING; break; }
283: // (implicit: FF drain complete)
284: phaseTransitionActive = false;
285: _unlockRng(day);
286: purchaseStartDay = day;
287: jackpotPhaseFlag = false;
288: _evaluateGameOverPossible(lvl, purchaseLevel);
```

New flow:
```
283: // FF drain complete
>>>: coin.rollLevelQuest(purchaseLevel, questEntropy);  // NEW
284: phaseTransitionActive = false;
```

Where `questEntropy` is derived from `rngWordByDay[day]`:
```solidity
uint256 questEntropy = uint256(keccak256(abi.encodePacked(rngWordByDay[day], "LEVEL_QUEST")));
```

`rngWordByDay[day]` is already warm from `rngGate()` earlier in the same `advanceGame()` call. Cost: 0 additional SLOADs for the read, plus keccak256 computation (~36 gas).

**New import or interface usage:** Needs to call `coin.rollLevelQuest()`. The AdvanceModule already has access to `coin` via delegatecall context (BurnieCoin address via ContractAddresses.COIN). The call follows the same pattern as `coin.rollDailyQuest()`.

---

### 1.4 DegenerusGameStorage.sol -- NO CHANGES NEEDED

**Path:** `contracts/storage/DegenerusGameStorage.sol`
**Why not:** Level quest storage lives in DegenerusQuests.sol (see Section 1.1 rationale). No new storage variables needed in the delegatecall storage layout.

**Confirmed:** `mintPacked_[player]` (bits 48-71 levelStreak, 104-127 unitsLevel, 128-151 frozenUntilLevel, 152-153 whaleBundleType, 228-243 levelUnits) and `deityPassCount[player]` are read-only from DegenerusQuests.sol via `questGame` interface calls. No writes to game storage from level quest logic.

---

### 1.5 BurnieCoin.sol -- CHANGES NEEDED

**Path:** `contracts/BurnieCoin.sol`
**Why:** Routing function for level quest roll (analogous to `rollDailyQuest` at line 642), and level quest reward handling in quest wrapper functions.
**Spec reference:** Phase 153 Sections 2, 6

**New Function:**

```solidity
/// @notice Roll the level quest during level transition.
/// @dev Access: game contract only. Called by AdvanceModule during phaseTransitionActive block.
/// @param lvl The level to roll a quest for.
/// @param entropy VRF-derived entropy.
function rollLevelQuest(uint24 lvl, uint256 entropy) external onlyDegenerusGameContract {
    questModule.rollLevelQuest(lvl, entropy);
}
```

This mirrors the existing `rollDailyQuest` pattern (line 642) where BurnieCoin routes to the quest module.

**Modified Functions -- quest wrapper handlers:**

Under **Option C** (recommended, see Section 7): NO changes to BurnieCoin wrapper functions. The 800 BURNIE creditFlip is called directly from DegenerusQuests.sol, so `notifyQuestMint`, `notifyQuestLootBox`, `notifyQuestDegenerette`, `affiliateQuestReward`, and `decimatorBurn` do not need modification.

Under Option A (alternative, see Section 7): Each BurnieCoin wrapper function would need to handle a second reward value returned from handleX for level quest completion. This adds complexity to 5 wrapper functions.

**Summary of BurnieCoin changes:**
- 1 new function: `rollLevelQuest`
- 0 modified functions (under Option C)

---

### 1.6 BurnieCoinflip.sol -- CHANGES NEEDED (minor)

**Path:** `contracts/BurnieCoinflip.sol`
**Why:** `onlyFlipCreditors` modifier must include DegenerusQuests address for direct creditFlip calls.
**Spec reference:** Phase 153 Section 6

**Modified: `onlyFlipCreditors` modifier (lines 194-203)**

Current allowed callers: GAME, COIN, AFFILIATE, ADMIN.

New allowed caller: QUESTS (`ContractAddresses.QUESTS`).

```solidity
modifier onlyFlipCreditors() {
    address sender = msg.sender;
    if (
        sender != ContractAddresses.GAME &&
        sender != ContractAddresses.COIN &&
        sender != ContractAddresses.AFFILIATE &&
        sender != ContractAddresses.ADMIN &&
        sender != ContractAddresses.QUESTS  // NEW: level quest rewards
    ) revert OnlyFlipCreditors();
    _;
}
```

This is needed only under Option C (recommended). Under Option A, no change to BurnieCoinflip is needed (rewards would route through BurnieCoin, which is already a flip creditor).

**Security note:** DegenerusQuests is a trusted protocol contract at a fixed address. Adding it to flip creditors follows the same trust model as the existing AFFILIATE entry. The quest contract can only credit 800 BURNIE per level per player (once-per-level guard at bit 152 of levelQuestPlayerState).

---

### 1.7 DegenerusGameMintModule.sol -- NO CHANGES NEEDED

**Path:** `contracts/modules/DegenerusGameMintModule.sol`
**Why not:** Quest calls flow through BurnieCoin wrapper functions. MintModule calls `coin.notifyQuestMint()` (lines 804, 910, 944, 1049) and `coin.notifyQuestLootBox()` (line 810). These wrappers call `module.handleMint()` / `module.handleLootBox()` on DegenerusQuests, where level quest tracking is added. No MintModule changes required.

---

### 1.8 DegenerusGameLootboxModule.sol -- NO CHANGES NEEDED

**Path:** `contracts/modules/DegenerusGameLootboxModule.sol`
**Why not:** Lootbox quest calls flow through `coin.notifyQuestLootBox()` (called from MintModule). No direct quest module interaction from LootboxModule.

---

### 1.9 DegenerusGameDegeneretteModule.sol -- NO CHANGES NEEDED

**Path:** `contracts/modules/DegenerusGameDegeneretteModule.sol`
**Why not:** Degenerette quest calls flow through `coin.notifyQuestDegenerette()` (lines 446, 448). The wrapper calls `module.handleDegenerette()` on DegenerusQuests. No module changes required.

---

### 1.10 DegenerusDegenerette.sol -- NO CHANGES NEEDED

**Path:** `contracts/DegenerusDegenerette.sol`
**Why not:** No quest integration in this contract. Degenerette bet handlers route through DegeneretteModule, which calls BurnieCoin wrappers.

---

## 2. Interface Changes (INTG-01)

### 2.1 IDegenerusQuests.sol

| Change | Type | Details |
|---|---|---|
| `LevelQuestCompleted` event | NEW | `(address indexed player, uint24 indexed level, uint8 questType, uint256 reward)` |
| `rollLevelQuest` function | NEW | `(uint24 lvl, uint256 entropy) external` |
| `getPlayerLevelQuestView` function | NEW | `(address player) external view returns (uint8, uint128, uint256, bool, bool)` |

No existing signatures change. Handler return types remain `(uint256 reward, uint8 questType, uint32 streak, bool completed)` reflecting daily quest status.

### 2.2 IDegenerusCoin.sol (or BurnieCoin direct)

| Change | Type | Details |
|---|---|---|
| `rollLevelQuest` function | NEW | `(uint24 lvl, uint256 entropy) external` |

This routing function mirrors the existing `rollDailyQuest` pattern. If IDegenerusCoin.sol exists as a formal interface, the new function should be added there. Otherwise, BurnieCoin.sol adds it directly (same as `rollDailyQuest` at line 642).

### 2.3 IBurnieCoinflip.sol -- NO CHANGES

No interface changes. `creditFlip(address, uint256)` signature is unchanged. Only the `onlyFlipCreditors` modifier implementation changes (adding QUESTS address).

---

## 3. New Cross-Contract Calls (INTG-01)

### 3.1 Level Quest Roll Path

```
AdvanceModule.advanceGame()
  [phaseTransitionActive block, after FF drain, line 283]
    |
    |-- (delegatecall context as GAME)
    |
    v
BurnieCoin.rollLevelQuest(purchaseLevel, questEntropy)
  [new function, onlyDegenerusGameContract]
    |
    v
DegenerusQuests.rollLevelQuest(purchaseLevel, questEntropy)
  [new function, onlyCoin]
    |
    |-- questEntropy = keccak256(abi.encodePacked(rngWordByDay[day], "LEVEL_QUEST"))
    |   (entropy derivation done in AdvanceModule before call)
    |-- bool decAllowed = _canRollDecimatorQuest()
    |-- uint8 selectedType = _bonusQuestType(questEntropy, type(uint8).max, decAllowed)
    |   (no exclusion -- type(uint8).max ensures no candidate is skipped as "primary")
    |-- levelQuestType[purchaseLevel] = selectedType  (1 SSTORE, 22,100 gas cold)
    v
  return
```

**Gas cost of roll path:** ~25,000 gas total (22,100 SSTORE + 2,100 SLOAD for `_canRollDecimatorQuest` reads + ~800 computation). Occurs exactly once per level transition.

### 3.2 Level Quest Reward Path (Option C -- Recommended)

```
handleX() in DegenerusQuests.sol
  [after daily quest processing]
    |
    |-- Read levelQuestType[level]      (1 SLOAD)
    |-- Read levelQuestPlayerState[player] (1 SLOAD)
    |-- _isLevelQuestEligible(player)   (1-2 SLOADs via questGame)
    |-- Accumulate progress, check target
    |
    |-- IF completed:
    |     |
    |     v
    |   IBurnieCoinflip(COINFLIP).creditFlip(player, 800 ether)
    |     [DegenerusQuests is onlyFlipCreditors]
    |   emit LevelQuestCompleted(player, level, questType, 800 ether)
    |   Write levelQuestPlayerState[player] (1 SSTORE)
    |
    |-- IF not completed:
    |   Write levelQuestPlayerState[player] (1 SSTORE, progress update)
    v
  return (original daily quest return values unchanged)
```

**No new external call from callers of handleX:** BurnieCoin wrapper functions (`notifyQuestMint`, etc.) and BurnieCoinflip (`flip` function) continue to receive the same return values. The 800 BURNIE creditFlip for level quest completion is an internal concern of DegenerusQuests.sol.

---

## 4. Handler Site Inventory (INTG-02)

### 4.1 handleMint (line 440)

**Signature:** `handleMint(address player, uint32 quantity, bool paidWithEth) external onlyCoin returns (uint256 reward, uint8 questType, uint32 streak, bool completed)`

**Current flow:**
1. Load `activeQuests`, get `currentDay`, get player state
2. Early exit if player/quantity invalid or no quest day
3. Sync player state (streak reset on missed day)
4. Loop both slots: check if quest type matches MINT_BURNIE or MINT_ETH
5. For matching slot: compute delta (`quantity` or `quantity * mintPrice`), compute target, handle progress
6. Return daily quest reward info

**Caller chain:**
- `MintModule._mintTickets()` -> `coin.notifyQuestMint(player, quantity, paidWithEth)` (lines 804, 910, 944, 1049)
- `BurnieCoin.notifyQuestMint()` (line 665) -> `module.handleMint(player, quantity, paidWithEth)` (line 677)
- Access control: `notifyQuestMint` checks `msg.sender == GAME`; `handleMint` checks `onlyCoin`

**Level quest type match:**
- QUEST_TYPE_MINT_BURNIE (0): when `!paidWithEth`
- QUEST_TYPE_MINT_ETH (1): when `paidWithEth`

**Progress delta:**
- MINT_BURNIE: `quantity` (ticket count, uint32)
- MINT_ETH: `quantity * mintPrice` (wei, uint256)

**mintPrice needed:** Only when `paidWithEth` AND quest type is MINT_ETH (already loaded at line 464 for daily quest).

---

### 4.2 handleFlip (line 538)

**Signature:** `handleFlip(address player, uint256 flipCredit) external onlyCoin returns (uint256 reward, uint8 questType, uint32 streak, bool completed)`

**Current flow:**
1. Load `activeQuests`, get `currentDay`, get player state
2. Early exit if player/flipCredit invalid or no quest day
3. Sync player state, find FLIP quest slot
4. If no FLIP slot active: early return
5. Sync progress, accumulate `flipCredit`, check target
6. Return daily quest reward info

**Caller chain:**
- `BurnieCoinflip.flip()` (line 279) -> `module.handleFlip(caller, amount)` (direct call, line 279)
- Access control: `handleFlip` checks `onlyCoin` (BurnieCoinflip is COINFLIP, allowed by `onlyCoin` modifier at line 286)

**Level quest type match:**
- QUEST_TYPE_FLIP (2)

**Progress delta:** `flipCredit` (BURNIE base units, 18 decimals)

**mintPrice needed:** No (fixed BURNIE target: 20,000e18).

---

### 4.3 handleDecimator (line 593)

**Signature:** `handleDecimator(address player, uint256 burnAmount) external onlyCoin returns (uint256 reward, uint8 questType, uint32 streak, bool completed)`

**Current flow:**
1. Load `activeQuests`, get `currentDay`, get player state
2. Early exit if player/burnAmount invalid or no quest day
3. Sync player state, find DECIMATOR quest slot
4. If no DECIMATOR slot active: early return
5. Sync progress, accumulate `burnAmount`, check target
6. Return daily quest reward info

**Caller chain:**
- `BurnieCoin.decimatorBurn()` (line 799) -> `questModule.handleDecimator(caller, amount)` (direct call on quest module)
- Access control: `handleDecimator` checks `onlyCoin` (BurnieCoin is COIN, allowed)

**Level quest type match:**
- QUEST_TYPE_DECIMATOR (5)

**Progress delta:** `burnAmount` (BURNIE base units, 18 decimals)

**mintPrice needed:** No (fixed BURNIE target: 20,000e18).

**Edge case:** Decimator quest can be rolled at level transition even if the current level has no decimator window. Progress is zero for that level. This is intentional per Phase 153 spec edge case analysis.

---

### 4.4 handleAffiliate (line 644)

**Signature:** `handleAffiliate(address player, uint256 amount) external onlyCoin returns (uint256 reward, uint8 questType, uint32 streak, bool completed)`

**Current flow:**
1. Load `activeQuests`, get `currentDay`, get player state
2. Early exit if player/amount invalid or no quest day
3. Sync player state, find AFFILIATE quest slot
4. If no AFFILIATE slot active: early return
5. Sync progress, accumulate `amount`, check target
6. Return daily quest reward info

**Caller chain:**
- `BurnieCoin.affiliateQuestReward()` (line 607) -> `module.handleAffiliate(player, amount)` (line 619)
- Access control: `affiliateQuestReward` checks `msg.sender == AFFILIATE`; `handleAffiliate` checks `onlyCoin`

**Level quest type match:**
- QUEST_TYPE_AFFILIATE (3)

**Progress delta:** `amount` (BURNIE base units, 18 decimals)

**mintPrice needed:** No (fixed BURNIE target: 20,000e18).

---

### 4.5 handleLootBox (line 697)

**Signature:** `handleLootBox(address player, uint256 amountWei) external onlyCoin returns (uint256 reward, uint8 questType, uint32 streak, bool completed)`

**Current flow:**
1. Load `activeQuests`, get `currentDay`, get player state
2. Early exit if player/amountWei invalid or no quest day
3. Sync player state, find LOOTBOX quest slot
4. If no LOOTBOX slot active: early return
5. Sync progress, accumulate `amountWei`, load `mintPrice` (line 719), check target
6. Return daily quest reward info

**Caller chain:**
- `MintModule._mintTickets()` -> `coin.notifyQuestLootBox(player, amountWei)` (line 810)
- `BurnieCoin.notifyQuestLootBox()` (line 697) -> `module.handleLootBox(player, amountWei)` (line 706)
- Access control: `notifyQuestLootBox` checks `msg.sender == GAME`; `handleLootBox` checks `onlyCoin`

**Level quest type match:**
- QUEST_TYPE_LOOTBOX (6)

**Progress delta:** `amountWei` (wei, uint256)

**mintPrice needed:** Yes (target = `mintPrice * 20`). Already loaded at line 719 for daily quest.

---

### 4.6 handleDegenerette (line 750)

**Signature:** `handleDegenerette(address player, uint256 amount, bool paidWithEth) external onlyCoin returns (uint256 reward, uint8 questType, uint32 streak, bool completed)`

**Current flow:**
1. Load `activeQuests`, get `currentDay`, get player state
2. Early exit if player/amount invalid or no quest day
3. Sync player state
4. Determine target type: DEGENERETTE_ETH (7) if `paidWithEth`, DEGENERETTE_BURNIE (8) otherwise
5. Find matching quest slot
6. If no matching slot: early return
7. Load `mintPrice` if `paidWithEth` (line 774-776), compute target, handle progress
8. Return daily quest reward info

**Caller chain:**
- `DegeneretteModule._resolveBet()` -> `coin.notifyQuestDegenerette(player, totalBet, paidWithEth)` (lines 446, 448)
- `BurnieCoin.notifyQuestDegenerette()` (line 724) -> `module.handleDegenerette(player, amount, paidWithEth)` (line 733)
- Access control: `notifyQuestDegenerette` checks `msg.sender == GAME`; `handleDegenerette` checks `onlyCoin`

**Level quest type match:**
- QUEST_TYPE_DEGENERETTE_ETH (7): when `paidWithEth`
- QUEST_TYPE_DEGENERETTE_BURNIE (8): when `!paidWithEth`

**Progress delta:** `amount` (wei for ETH, BURNIE base units for BURNIE)

**mintPrice needed:** Only for DEGENERETTE_ETH (target = `mintPrice * 20`). Already loaded at line 775 for daily quest when `paidWithEth`.

---

## 5. Per-Handler Level Quest Tracking Specification (INTG-02)

### 5.1 Shared Pattern

Every handler adds the following block AFTER the existing daily quest logic completes (just before the final return statement). The block runs regardless of whether the daily quest completed or not.

```solidity
// --- Level Quest Progress ---
{
    uint24 currentLevel = questGame.level();
    uint8 lqType = levelQuestType[currentLevel];         // 1 SLOAD (cold: 2,100 gas)

    if (lqType != 0 || currentLevel == 0) {
        // Only proceed if a level quest has been rolled for this level.
        // lqType == 0 with currentLevel > 0 means no quest rolled yet.
        // At level 0, type 0 (MINT_BURNIE) is a valid quest type,
        // but level 0 has no level quest (roll happens on transition TO a level).

        // Check if this handler's type matches the level quest type
        if (_handlerMatchesLevelQuestType(lqType, handlerQuestType)) {

            uint256 packed = levelQuestPlayerState[player]; // 1 SLOAD
            uint24 questLevel = uint24(packed);

            // Level-boundary invalidation
            if (questLevel != currentLevel) {
                packed = uint256(currentLevel); // reset: level set, progress=0, completed=false
            }

            bool completed = (packed >> 152) & 1 == 1;
            if (!completed) {
                // Eligibility check (1-2 SLOADs via questGame)
                if (_isLevelQuestEligible(player)) {
                    uint128 progress = uint128(packed >> 24);
                    progress = _clampedAdd128(progress, delta);

                    uint256 target = _levelQuestTargetValue(lqType, mintPrice);
                    if (progress >= target) {
                        // Complete!
                        packed = uint256(currentLevel)
                               | (uint256(progress) << 24)
                               | (uint256(1) << 152);
                        levelQuestPlayerState[player] = packed; // 1 SSTORE
                        IBurnieCoinflip(ContractAddresses.COINFLIP).creditFlip(player, 800 ether);
                        emit LevelQuestCompleted(player, currentLevel, lqType, 800 ether);
                    } else {
                        // Progress update
                        packed = uint256(currentLevel)
                               | (uint256(progress) << 24);
                        levelQuestPlayerState[player] = packed; // 1 SSTORE
                    }
                }
            }
        }
    }
}
```

**Gas budget for level quest block:**
- Best case (quest type mismatch): 1 SLOAD for `levelQuestType` + comparison = ~2,200 gas
- Typical case (type match, not complete): 2 SLOADs + eligibility (1-2 SLOADs) + 1 SSTORE = ~9,400-11,500 gas
- Completion case: above + `creditFlip` external call + event = ~15,000-17,000 gas

### 5.2 Level Quest Type Matching Helper

Each handler knows its own quest type(s). The match check is a simple comparison:

```solidity
function _handlerMatchesLevelQuestType(uint8 lqType, uint8 handlerType) private pure returns (bool) {
    return lqType == handlerType;
}
```

For handlers with two possible types (handleMint, handleDegenerette), the check branches on the `paidWithEth` flag to determine which type to match against.

### 5.3 handleMint Specifics

**Matches:** QUEST_TYPE_MINT_BURNIE (0) when `!paidWithEth`, QUEST_TYPE_MINT_ETH (1) when `paidWithEth`

**Delta:**
- MINT_BURNIE: `quantity` (ticket count)
- MINT_ETH: `quantity * mintPrice` (wei)

**mintPrice:** Already loaded at line 464 when `paidWithEth`. Reuse existing variable.

**Edge case:** The handler loops both daily quest slots. The level quest block runs once after the loop completes, using the same `quantity` and `mintPrice` values.

### 5.4 handleFlip Specifics

**Matches:** QUEST_TYPE_FLIP (2)

**Delta:** `flipCredit` (BURNIE base units)

**mintPrice:** Not needed. Pass 0 to `_levelQuestTargetValue` (returns fixed 20,000e18).

**Edge case:** None.

### 5.5 handleDecimator Specifics

**Matches:** QUEST_TYPE_DECIMATOR (5)

**Delta:** `burnAmount` (BURNIE base units)

**mintPrice:** Not needed. Pass 0 to `_levelQuestTargetValue` (returns fixed 20,000e18).

**Edge case:** If DECIMATOR is the level quest but no decimator window opens during the level, progress stays at zero. The quest is uncompletable that level. This is intentional per Phase 153 spec.

### 5.6 handleAffiliate Specifics

**Matches:** QUEST_TYPE_AFFILIATE (3)

**Delta:** `amount` (BURNIE base units)

**mintPrice:** Not needed. Pass 0 to `_levelQuestTargetValue` (returns fixed 20,000e18).

**Edge case:** None.

### 5.7 handleLootBox Specifics

**Matches:** QUEST_TYPE_LOOTBOX (6)

**Delta:** `amountWei` (wei)

**mintPrice:** Needed (target = `mintPrice * 20`). Already loaded at line 719 for daily quest. Reuse existing variable.

**Edge case:** None.

### 5.8 handleDegenerette Specifics

**Matches:** QUEST_TYPE_DEGENERETTE_ETH (7) when `paidWithEth`, QUEST_TYPE_DEGENERETTE_BURNIE (8) when `!paidWithEth`

**Delta:** `amount` (wei for ETH, BURNIE base units for BURNIE)

**mintPrice:** Needed only for DEGENERETTE_ETH (target = `mintPrice * 20`). Already loaded at line 775 when `paidWithEth`. Reuse existing variable.

**Edge case:** Handler already branches on `paidWithEth` for daily quest type selection (line 767). Level quest match also branches on this flag.

---

## 6. Level Quest Roll Path Specification (INTG-01)

### 6.1 Trigger

`AdvanceModule.advanceGame()` during `phaseTransitionActive` block (lines 260-291).

### 6.2 Insertion Point

After FF drain loop completes (line 283), before `phaseTransitionActive = false` (line 284).

```solidity
// Line 280: if (ffWorked || !ffFinished) { stage = STAGE_TRANSITION_WORKING; break; }
// Line 283: (implicit: FF drain complete, all transition housekeeping done)

// NEW: Roll level quest for the incoming level
uint256 questEntropy = uint256(keccak256(abi.encodePacked(rngWordByDay[day], "LEVEL_QUEST")));
IBurnieCoin(ContractAddresses.COIN).rollLevelQuest(purchaseLevel, questEntropy);

// Line 284: phaseTransitionActive = false;
```

### 6.3 Entropy

```solidity
uint256 questEntropy = uint256(keccak256(abi.encodePacked(rngWordByDay[day], "LEVEL_QUEST")));
```

- `rngWordByDay[day]` is already warm from `rngGate()` (SLOAD cost: ~100 gas, warm read).
- `"LEVEL_QUEST"` salt ensures statistical independence from all other VRF consumers (coinflip bit 0, redemption bits 8+, and all other keccak-mixed full consumers).
- Follows the existing "full consumer" pattern documented in the VRF bit allocation map (AdvanceModule lines 791-808).

### 6.4 Quest Type Selection

Reuse `_bonusQuestType` weight table with NO exclusion:

| Quest Type | ID | Weight |
|---|---|---|
| MINT_BURNIE | 0 | 10 |
| MINT_ETH | 1 | 1 |
| FLIP | 2 | 4 |
| AFFILIATE | 3 | 1 |
| RESERVED | 4 | 0 (skipped) |
| DECIMATOR | 5 | 4 (eligible) / 0 (not) |
| LOOTBOX | 6 | 3 |
| DEGENERETTE_ETH | 7 | 1 |
| DEGENERETTE_BURNIE | 8 | 1 |

**Total weight:** 21 (no decimator) or 25 (with decimator)

**Difference from daily quests:** Daily quests exclude the primary type (MINT_ETH) from slot 1. Level quests have no exclusion -- all types (except RESERVED) are eligible. To implement this, call `_bonusQuestType(entropy, type(uint8).max, decAllowed)` where `type(uint8).max` (255) is a sentinel that never matches any candidate, ensuring no type is excluded.

Alternatively, a new `_levelQuestType(entropy, decAllowed)` function can be written that omits the exclusion logic entirely. This is cleaner but duplicates weight table code.

**Decimator eligibility:** `_canRollDecimatorQuest()` checks `decWindowOpen` and level constraints. At the moment of level transition (inside `phaseTransitionActive` block), `decWindowOpen` reflects the outgoing level's state. The decimator window may or may not be open at the transitioning level.

### 6.5 Storage Write

```solidity
levelQuestType[purchaseLevel] = selectedType;
```

- 1 SSTORE: 22,100 gas (cold, new non-zero value)
- Mapping slot: `keccak256(abi.encode(purchaseLevel, slot_of_levelQuestType))`

---

## 7. Reward Payout Path (INTG-01)

### 7.1 Option Analysis

Three approaches for the 800 BURNIE creditFlip payout on level quest completion:

**Option A: Add separate return values to handleX for level quest reward**

- handleX returns `(uint256 reward, uint8 questType, uint32 streak, bool completed, uint256 levelQuestReward)`
- BurnieCoin wrappers (`notifyQuestMint`, etc.) check `levelQuestReward != 0` and call `creditFlip`

Pros:
- No change to `onlyFlipCreditors`
- Reward routing visible in wrapper functions

Cons:
- Changes the IDegenerusQuests interface (6 handler signatures change)
- Requires modifying 5 BurnieCoin wrapper functions + 1 BurnieCoinflip handler
- Adds a 5th return value to all handler calls (extra gas for ABI encoding/decoding)
- The handleFlip call in BurnieCoinflip (line 279) must also handle the new return value

**Option B: Sum level quest reward into existing reward return value**

- handleX returns reward = dailyQuestReward + levelQuestReward in the single `reward` field

Pros:
- Zero interface changes

Cons:
- Conflates daily and level quest rewards -- callers cannot distinguish which quest completed
- Event emission for daily quest would show combined reward, making indexing ambiguous
- BurnieCoin `_questApplyReward` already processes the reward; mixing in 800 BURNIE would inflate daily quest events

**Option C: DegenerusQuests calls creditFlip directly (RECOMMENDED)**

- On level quest completion, DegenerusQuests calls `IBurnieCoinflip(COINFLIP).creditFlip(player, 800 ether)` directly
- Requires adding `ContractAddresses.QUESTS` to `onlyFlipCreditors`

Pros:
- Zero interface changes to handleX signatures
- Zero changes to BurnieCoin wrapper functions
- Zero changes to BurnieCoinflip.flip() handler
- Level quest reward is self-contained within DegenerusQuests
- Clean separation: daily quest rewards flow through callers, level quest rewards flow directly
- Emits `LevelQuestCompleted` event from the same contract that detects completion

Cons:
- Adds DegenerusQuests to `onlyFlipCreditors` (1 line in modifier)
- DegenerusQuests gains an external call to BurnieCoinflip (new cross-contract dependency)

### 7.2 Recommendation: Option C

Option C is recommended because:
1. **Minimal blast radius:** Only 2 contracts change for the reward path (DegenerusQuests adds the call, BurnieCoinflip adds the creditor). All other contracts are untouched.
2. **No interface changes:** The 6 handler signatures remain stable. No downstream callers need modification.
3. **CEI safety:** The creditFlip call occurs after all state updates (packed write to `levelQuestPlayerState`). The external call to `creditFlip` is safe because BurnieCoinflip._addDailyFlip is non-reentrant by design (it updates internal state atomically with no callbacks).
4. **Precedent:** The existing `_questApplyReward` pattern in BurnieCoin shows that quest rewards already flow to `creditFlip`. Adding a parallel path from DegenerusQuests for level quest rewards follows the same trust model.

### 7.3 Reward Flow Diagram (Option C)

```
handleX() in DegenerusQuests.sol
    |-- [daily quest logic -- existing, unchanged]
    |-- [return daily quest values to caller]
    |
    |-- [level quest progress block -- NEW]
    |     |
    |     v
    |   if (progress >= target && !completed):
    |     levelQuestPlayerState[player] = packed | (1 << 152)  // SSTORE
    |     IBurnieCoinflip(COINFLIP).creditFlip(player, 800 ether)
    |     emit LevelQuestCompleted(...)
    v
  return (dailyReward, dailyQuestType, streak, dailyCompleted)
```

**Important structural note:** The level quest block must execute BEFORE the handler returns the daily quest values. In practice, the level quest logic is inserted into the handler body, not after the return statement. The handler return values reflect daily quest status only; level quest completion is signaled via the `LevelQuestCompleted` event and the direct `creditFlip` call.

---

## 8. Open Design Questions Resolved

### Q1: Contract Location

**Decision:** DegenerusQuests.sol

**Rationale:**
- All 6 handleX entry points already live in DegenerusQuests.sol. Placing level quest storage here means progress tracking and eligibility checks happen in the same contract, with zero additional cross-contract reads.
- The `questGame` immutable reference (`IDegenerusGame(ContractAddresses.GAME)`) provides read access to `mintPacked_`, `deityPassCount`, `mintPrice`, `level`, and `decWindowOpenFlag` -- everything needed for eligibility and target derivation.
- DegenerusGameStorage.sol alternative would require DegenerusQuests.sol to make additional external calls to read level quest type from game storage, adding gas and complexity.
- The only trade-off is adding DegenerusQuests to `onlyFlipCreditors` for the 800 BURNIE reward (1 line change in BurnieCoinflip.sol).

### Q2: Handler Routing

**Decision:** Augment existing handleX functions with parallel level quest progress tracking.

**Rationale:**
- Each handleX function already receives the exact parameters needed for level quest progress (player, delta, paidWithEth).
- A parallel tracking block after the daily quest logic adds ~2,200-17,000 gas depending on whether the quest type matches and progress is updated.
- Creating separate `handleLevelQuest*()` entry points would require callers to make additional external calls (2x gas for external call overhead per action).
- A single combined handler is rejected because daily and level quests have fundamentally different state management (version-based vs level-based invalidation).

### Q3: Roll Trigger Path

**Decision:** AdvanceModule -> BurnieCoin.rollLevelQuest -> DegenerusQuests.rollLevelQuest

**Rationale:**
- Mirrors the daily quest rolling path (`coin.rollDailyQuest` at BurnieCoin line 642, called from JackpotModule).
- BurnieCoin acts as the routing hub with `onlyDegenerusGameContract` access control, maintaining the established pattern where all quest module calls go through BurnieCoin.
- Direct call from AdvanceModule to DegenerusQuests would bypass BurnieCoin's role as the access-control hub and break the consistent routing pattern.
- The BurnieCoin routing function is trivial (3 lines) and adds minimal gas overhead (~2,600 gas for the external call hop).

---

## 9. Summary Table

| # | Contract | Changes | Lines Affected | New Functions | New Storage | New Events |
|---|---|---|---|---|---|---|
| 1 | DegenerusQuests.sol | New storage, new internal/external functions, 6 handler modifications | 440, 538, 593, 644, 697, 750 (+ new sections) | `rollLevelQuest`, `_isLevelQuestEligible`, `_levelQuestTargetValue`, `_handleLevelQuestProgress`, `getPlayerLevelQuestView` | `levelQuestType`, `levelQuestPlayerState` | `LevelQuestCompleted` |
| 2 | IDegenerusQuests.sol | New event, 2 new function signatures | Interface additions | `rollLevelQuest`, `getPlayerLevelQuestView` | -- | `LevelQuestCompleted` |
| 3 | DegenerusGameAdvanceModule.sol | Level quest roll call in phaseTransitionActive block | 283-284 (insertion) | -- | -- | -- |
| 4 | BurnieCoin.sol | New routing function | New section | `rollLevelQuest` | -- | -- |
| 5 | BurnieCoinflip.sol | Add QUESTS to onlyFlipCreditors | 194-203 | -- | -- | -- |
| 6 | DegenerusGameStorage.sol | No changes | -- | -- | -- | -- |
| 7 | DegenerusGameMintModule.sol | No changes | -- | -- | -- | -- |
| 8 | DegenerusGameLootboxModule.sol | No changes | -- | -- | -- | -- |
| 9 | DegenerusGameDegeneretteModule.sol | No changes | -- | -- | -- | -- |
| 10 | DegenerusDegenerette.sol | No changes | -- | -- | -- | -- |

**Total: 5 contracts modified, 5 contracts unchanged.**

---

## Traceability

### Requirement Coverage

| Requirement | Section(s) | Status |
|---|---|---|
| INTG-01 | 1 (touchpoint map), 2 (interface changes), 3 (cross-contract calls), 6 (roll path), 7 (reward path), 8 (Q1-Q3 resolved), 9 (summary table) | Covered |
| INTG-02 | 4 (handler site inventory), 5 (per-handler tracking specification) | Covered |

### Phase 153 Spec Cross-Reference

| Spec Section | Integration Map Section | Notes |
|---|---|---|
| 1. Eligibility | 5.1 (shared pattern), 1.1 (`_isLevelQuestEligible`) | Eligibility check called from level quest block in each handler |
| 2. Global Quest Roll | 6 (roll path), 1.3 (AdvanceModule insertion point) | Roll at level transition via BurnieCoin routing |
| 3. Quest Targets at 10x | 5.1 (shared pattern), 1.1 (`_levelQuestTargetValue`) | 10x targets, no cap, derived from type + mintPrice |
| 4. Per-Player Progress | 5.1 (shared pattern), 1.1 (`levelQuestPlayerState`) | Packed uint256 with level-boundary invalidation |
| 5. Global Per-Level Storage | 1.1 (`levelQuestType`), 6.5 (storage write) | mapping(uint24 => uint8) in DegenerusQuests.sol |
| 6. Completion Flow | 5.1 (completion in shared pattern), 7 (reward path) | creditFlip from DegenerusQuests (Option C) |
| 7. Storage Layout | 1.1 (new storage section), 1.4 (no GameStorage changes) | 2 new mapping root slots in DegenerusQuests.sol |
| 8. Open Questions | 8 (all 3 questions resolved) | Contract location, handler routing, roll trigger path |

---

*Integration map produced by Phase 154 Plan 01. An implementer can open this document and know exactly which files to modify, which functions to add, and which interfaces change -- zero ambiguity.*
