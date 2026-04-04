# Level Quest System -- Design Specification

**Phase:** 153-core-design
**Author:** Agent (Phase 153-01)
**Status:** Complete
**Produced by:** 153-01-PLAN.md

---

## 1. Eligibility

**Decisions:** D-01, D-02, D-03
**Requirements:** ELIG-01, ELIG-02

### Boolean Expression

```
eligible = (
    (levelStreak >= 5)                                          // mintPacked_[player] bits 48-71
    OR
    (deityPassCount[player] > 0)                                // mapping(address => uint16) in DegenerusGameStorage
    OR
    (frozenUntilLevel > 0 AND whaleBundleType != 0)             // mintPacked_[player] bits 128-151 and 152-153
)
AND
(
    levelUnits >= 4                                              // mintPacked_[player] bits 228-243
    // ONLY valid when unitsLevel == current game level          // mintPacked_[player] bits 104-127
    // If unitsLevel != level: treat levelUnits as 0 (player has not minted this level)
)
```

### Storage Reads

| Read | Source | Type | Bit Position | Mask |
|------|--------|------|--------------|------|
| `levelStreak` | `mintPacked_[player]` | uint24 | bits 48-71 | `(packed >> 48) & 0xFFFFFF` |
| `frozenUntilLevel` | `mintPacked_[player]` | uint24 | bits 128-151 | `(packed >> 128) & 0xFFFFFF` |
| `whaleBundleType` | `mintPacked_[player]` | uint2 | bits 152-153 | `(packed >> 152) & 0x3` |
| `unitsLevel` | `mintPacked_[player]` | uint24 | bits 104-127 | `(packed >> 104) & 0xFFFFFF` |
| `levelUnits` | `mintPacked_[player]` | uint16 | bits 228-243 | `(packed >> 228) & 0xFFFF` |
| `deityPassCount` | `deityPassCount[player]` | uint16 | full slot | direct mapping read |

### SLOAD Count

- **Best case (1 SLOAD):** `mintPacked_[player]` satisfies both the loyalty gate (levelStreak >= 5 or whale/lazy pass) and the activity gate (unitsLevel == level AND levelUnits >= 4). Only one SLOAD needed; `deityPassCount` is not read.
- **Worst case (2 SLOADs):** `mintPacked_[player]` does NOT satisfy the loyalty gate (levelStreak < 5, no whale/lazy pass), so `deityPassCount[player]` is also read. Total: mintPacked_ (1 SLOAD) + deityPassCount (1 SLOAD) = 2 SLOADs.

### Gas Cost Estimate

| Scenario | SLOADs | Cold Cost | Hot Cost |
|----------|--------|-----------|----------|
| Best case (mintPacked_ short-circuits) | 1 | ~2,100 gas | ~100 gas |
| Worst case (deity pass fallback) | 2 | ~4,200 gas | ~200 gas |

Note: Cold SLOAD = 2,100 gas (EIP-2929). Hot SLOAD = 100 gas. In the quest handler hot path, `mintPacked_` is likely already warm from the mint operation that triggered the handler.

### Evaluation Logic (Pseudocode)

```solidity
function _isLevelQuestEligible(address player) internal view returns (bool) {
    uint256 packed = mintPacked_[player];

    // Activity gate: must have minted >= 4 ETH units THIS level
    uint24 unitsLvl = uint24(packed >> 104);
    if (unitsLvl != level) return false;  // no mint data for current level
    uint16 units = uint16(packed >> 228);
    if (units < 4) return false;

    // Loyalty gate: levelStreak >= 5 OR any active pass
    uint24 streak = uint24(packed >> 48);
    if (streak >= 5) return true;

    // Check whale/lazy pass from mintPacked_
    uint24 frozen = uint24(packed >> 128);
    uint8 bundle = uint8((packed >> 152) & 0x3);
    if (frozen > 0 && bundle != 0) return true;

    // Fallback: deity pass (separate mapping, costs 1 extra SLOAD)
    return deityPassCount[player] > 0;
}
```

### Pass Types Covered (per D-03)

| Pass Type | Detection | Source |
|-----------|-----------|--------|
| Deity Pass | `deityPassCount[player] > 0` | `mapping(address => uint16)` in DegenerusGameStorage |
| Whale Bundle (10-level) | `frozenUntilLevel > 0 AND whaleBundleType == 1` | mintPacked_ bits 128-153 |
| Whale Bundle (100-level) | `frozenUntilLevel > 0 AND whaleBundleType == 3` | mintPacked_ bits 128-153 |
| Lazy Pass (frozen whale) | Same as whale -- frozenUntilLevel preserves bundle type | mintPacked_ bits 128-153 |

Note: `whaleBundleType` encoding: 0 = none, 1 = 10-level, 3 = 100-level. Any non-zero value with `frozenUntilLevel > 0` indicates an active pass.

---

## 2. Global Quest Roll Mechanism

**Decisions:** D-04, D-05, D-06
**Requirement:** MECH-01

### When

During `advanceGame()` level transition, specifically inside the `phaseTransitionActive` block in AdvanceModule (lines 260-291). The roll occurs AFTER `_processPhaseTransition(purchaseLevel)` completes and BEFORE `phaseTransitionActive = false` is set.

Insertion point in the advanceGame flow:

```
advanceGame() -> phaseTransitionActive block:
  1. _processPhaseTransition(purchaseLevel)   // existing: vault tickets, autoStake
  2. FF drain loop                            // existing: far-future ticket promotion
  3. >>> LEVEL QUEST ROLL HERE <<<            // NEW: roll quest for purchaseLevel
  4. phaseTransitionActive = false             // existing
  5. _unlockRng(day)                          // existing
  6. purchaseStartDay = day                   // existing
  7. _evaluateGameOverPossible(...)            // existing
```

This location is chosen because:
- The VRF word (`rngWord`) is already available (rngGate returned it earlier in the same advanceGame call).
- `purchaseLevel` (= level + 1) is the new level being entered.
- All phase transition housekeeping is complete.
- This runs exactly once per level transition.

### VRF Entropy Source

```solidity
uint256 questEntropy = uint256(keccak256(abi.encodePacked(rngWordByDay[day], "LEVEL_QUEST")));
```

This follows the existing "full consumer" pattern from the VRF bit allocation map (AdvanceModule lines 791-808). Full consumers use keccak256 mixing to derive independent entropy, avoiding bit-level overlap concerns with bits 0 and 8+ (coinflip and redemption roll).

The `rngWordByDay[day]` mapping stores the VRF word for the current day. Using a unique salt (`"LEVEL_QUEST"`) ensures statistical independence from all other entropy consumers.

SLOAD cost: `rngWordByDay[day]` is already loaded during the advanceGame flow by rngGate. Cost is 0 additional SLOADs (warm read).

### Quest Type Selection

Reuse the exact weight table from `_bonusQuestType` in DegenerusQuests.sol (per D-05):

| Quest Type | ID | Weight | Notes |
|---|---|---|---|
| MINT_BURNIE | 0 | 10 | Highest weight -- most accessible |
| MINT_ETH | 1 | 1 | Base weight |
| FLIP | 2 | 4 | Second-highest weight |
| AFFILIATE | 3 | 1 | Base weight |
| RESERVED | 4 | 0 | Skipped (retired type) |
| DECIMATOR | 5 | 4 (when eligible) / 0 (otherwise) | Only when `decWindowOpen && eligible level` |
| LOOTBOX | 6 | 3 | Third-highest weight |
| DEGENERETTE_ETH | 7 | 1 | Base weight |
| DEGENERETTE_BURNIE | 8 | 1 | Base weight |

**Total weight (no decimator):** 10 + 1 + 4 + 1 + 3 + 1 + 1 = **21**
**Total weight (with decimator):** 21 + 4 = **25**

Selection algorithm:
```
roll = questEntropy % totalWeight
Scan types 0..8 in order, accumulating weights. First type where accumulated weight > roll is selected.
```

Decimator eligibility at level quest roll time: `_canRollDecimatorQuest()` checks `decWindowOpen` and level constraints (X5 levels except X95, or X00 levels). At the moment of level transition, `decWindowOpen` reflects the OUTGOING level's state. Since the quest roll happens before `phaseTransitionActive = false`, the window state is from the just-completed jackpot phase.

**Difference from daily quests:** Daily quests exclude the primary type (MINT_ETH in slot 0) from the slot 1 roll. Level quests have no exclusion -- all 8 types (excluding RESERVED) are eligible. This means MINT_ETH can appear as a level quest despite being the daily slot 0 quest.

### Global Storage

```solidity
mapping(uint24 => uint8) internal levelQuestType;
```

- Key: level number (uint24)
- Value: quest type ID (uint8, values 0-8 per QUEST_TYPE_* constants)
- Target is derived from type at evaluation time (not stored). Rationale: targets are deterministic from type + mintPrice. Storing the target would cost 1 extra SSTORE at roll time without saving any SLOAD at evaluation time (ETH-based types still need mintPrice).

SSTORE at roll time: 1 SSTORE to write `levelQuestType[purchaseLevel]` = cold write = 22,100 gas (new non-zero value).

---

## 3. Quest Targets at 10x

**Decisions:** D-07, D-08
**Requirement:** MECH-02

### Target Table

| Quest Type | ID | Daily Target | Level Quest Target (10x) | Units | Derivation |
|---|---|---|---|---|---|
| MINT_BURNIE | 0 | 1 ticket | **10 tickets** (10,000 BURNIE) | ticket count (uint32) | `QUEST_MINT_TARGET * 10 = 10` |
| MINT_ETH | 1 | `mintPrice * 1` (slot 0) or `mintPrice * 2` (slot 1) | **`mintPrice * 10`** | wei (uint256) | Unified: no slot distinction for level quests |
| FLIP | 2 | 2,000 BURNIE (2e21 base) | **20,000 BURNIE** (2e22 base) | BURNIE base units (18 dec) | `QUEST_BURNIE_TARGET * 10 = 20000e18` |
| AFFILIATE | 3 | 2,000 BURNIE (2e21 base) | **20,000 BURNIE** (2e22 base) | BURNIE base units (18 dec) | `QUEST_BURNIE_TARGET * 10 = 20000e18` |
| DECIMATOR | 5 | 2,000 BURNIE (2e21 base) | **20,000 BURNIE** (2e22 base) | BURNIE base units (18 dec) | `QUEST_BURNIE_TARGET * 10 = 20000e18` |
| LOOTBOX | 6 | `mintPrice * 2` | **`mintPrice * 20`** | wei (uint256) | `QUEST_LOOTBOX_TARGET_MULTIPLIER * 10 = 20` |
| DEGENERETTE_ETH | 7 | `mintPrice * 2` | **`mintPrice * 20`** | wei (uint256) | `QUEST_LOOTBOX_TARGET_MULTIPLIER * 10 = 20` |
| DEGENERETTE_BURNIE | 8 | 2,000 BURNIE (2e21 base) | **20,000 BURNIE** (2e22 base) | BURNIE base units (18 dec) | `QUEST_BURNIE_TARGET * 10 = 20000e18` |

### Key Design Rules

**No ETH cap (per D-07):** Daily quests cap ETH targets at `QUEST_ETH_TARGET_CAP = 0.5 ether`. Level quests explicitly do NOT use this cap. The 10x multiplier applies to raw `mintPrice * multiplier` without capping.

```solidity
// Daily quest (capped):    min(mintPrice * mult, 0.5 ether)
// Level quest (uncapped):  mintPrice * 10   (for MINT_ETH)
//                          mintPrice * 20   (for LOOTBOX, DEGENERETTE_ETH)
```

**Unified MINT_ETH target:** Daily quests use different multipliers per slot (1x for slot 0, 2x for slot 1). Level quests have ONE quest, not two slots. Level quest MINT_ETH target = `mintPrice * 10`. Not slot-dependent.

**Target evaluation is dynamic:** For ETH-based types, target = `mintPrice * multiplier` evaluated at completion-check time. If `mintPrice` increases during a level, the target increases. Progress is cumulative wei, so existing progress remains valid -- only the bar moves.

### Edge Case Analysis

| Quest Type | Edge Case | Analysis | Outcome |
|---|---|---|---|
| MINT_BURNIE | Straightforward | 10 ticket purchases (10,000 BURNIE total) over an entire level (multiple days). Highly achievable. | No concern |
| MINT_ETH | Price sensitivity | At 0.01 ETH/mint, target = 0.1 ETH (10 mints). At 0.5 ETH/mint, target = 5 ETH. Progress is cumulative wei; target recalculates at evaluation time. Rising price makes completion harder for new depositors but doesn't invalidate prior progress. | Documented, not capped (D-07) |
| FLIP | Volume | 20,000 BURNIE in coinflip deposits across a level. Typical flip is 1,000+ BURNIE. ~20 flips over multiple days. Achievable for active players. | No concern |
| AFFILIATE | Difficulty | 20,000 BURNIE in affiliate commissions. Requires significant referral volume. Very hard for non-affiliates. Possible for players who earn commissions from others' referral activity. | Documented, not capped (D-08) |
| DECIMATOR | Window availability | Decimator windows only open at specific levels: X5 (except X95) and X00 milestones. If the level quest is DECIMATOR but the current level has no decimator window, progress is impossible during that level. Multi-day levels may span into the next level's decimator window, but progress resets at level boundary. | Documented, not excluded (D-08). Quest is uncompletable that level, which is intentional. |
| LOOTBOX | Price sensitivity | At 0.01 ETH/mint, target = 0.2 ETH in lootbox purchases. At 0.5 ETH/mint, target = 10 ETH. Same dynamic pricing behavior as MINT_ETH. | Documented, not capped (D-07) |
| DEGENERETTE_ETH | Price sensitivity | At 0.01 ETH/mint, target = 0.2 ETH in Degenerette bets. Same dynamic pricing as LOOTBOX. | Documented, not capped (D-07) |
| DEGENERETTE_BURNIE | Volume | 20,000 BURNIE in Degenerette bets. Same tier as FLIP/AFFILIATE. Achievable for active Degenerette players. | No concern |

### Target Derivation Function (Pseudocode)

```solidity
function _levelQuestTargetValue(uint8 questType, uint256 mintPrice) internal pure returns (uint256) {
    if (questType == QUEST_TYPE_MINT_BURNIE) {
        return 10;  // 10 tickets (progress counted in ticket units)
    }
    if (questType == QUEST_TYPE_MINT_ETH) {
        return mintPrice * 10;  // 10x mint price, uncapped
    }
    if (questType == QUEST_TYPE_LOOTBOX || questType == QUEST_TYPE_DEGENERETTE_ETH) {
        return mintPrice * 20;  // 20x mint price, uncapped
    }
    if (
        questType == QUEST_TYPE_FLIP ||
        questType == QUEST_TYPE_DECIMATOR ||
        questType == QUEST_TYPE_AFFILIATE ||
        questType == QUEST_TYPE_DEGENERETTE_BURNIE
    ) {
        return 20_000 ether;  // 20,000 BURNIE in base units (18 decimals)
    }
    return 0;
}
```

---

## 4. Per-Player Progress Tracking

**Decisions:** D-09, D-10, D-13
**Requirement:** MECH-03

### Storage Design

Following the existing `questPlayerState` mapping pattern (per D-13), but simplified:

```solidity
// Packed into a single uint256 for 1 SLOAD / 1 SSTORE
mapping(address => uint256) internal levelQuestPlayerState;
```

### Packed Bit Layout

```
Bits 0-23:    questLevel  (uint24)  -- Level this progress belongs to (invalidation key)
Bits 24-151:  progress    (uint128) -- Accumulated progress toward target
Bit 152:      completed   (bool)    -- Once-per-level completion flag
Bits 153-255: unused                -- 103 bits available for future use
```

Total: 24 + 128 + 1 = **153 bits** out of 256. Fits in a single uint256.

### Packing/Unpacking

```solidity
// Unpack
uint24  questLevel = uint24(packed);
uint128 progress   = uint128(packed >> 24);
bool    completed  = (packed >> 152) & 1 == 1;

// Pack
uint256 packed = uint256(questLevel)
               | (uint256(progress) << 24)
               | (completed ? (uint256(1) << 152) : 0);
```

### Level-Boundary Invalidation (per D-10)

When a handler reads `levelQuestPlayerState[player]`, check:

```solidity
uint256 packed = levelQuestPlayerState[player];
uint24 questLevel = uint24(packed);

if (questLevel != level) {
    // Stale data: player's progress is from a previous level.
    // Reset to current level with zero progress and not completed.
    packed = uint256(level);  // questLevel = level, progress = 0, completed = false
}
```

This is simpler than daily quest version-based invalidation because:

1. **Levels are global and monotonic.** All players share the same level. When level advances, ALL player progress becomes stale. No per-player version counter needed.
2. **No mid-level re-rolls.** Daily quests can change within a day (edge case requiring version counters). Level quests roll once per level and never change.
3. **Cheaper.** Level comparison uses the already-loaded `level` from Slot 0 (warm read, 100 gas). Version-based invalidation would require an additional version counter SLOAD.

### Independence from Daily Quests (per D-09)

- Level quest progress is stored in a completely separate mapping (`levelQuestPlayerState`) from daily quest progress (`questPlayerState` in DegenerusQuests.sol).
- Level quest completion does NOT affect daily quest streak.
- Daily quest completion does NOT affect level quest progress.
- Both systems can run simultaneously without interference.

### Progress Accumulation

Progress accumulates identically to daily quests:
- MINT_BURNIE: increment by ticket count (uint32 quantity)
- MINT_ETH: increment by `quantity * mintPrice` (wei)
- FLIP: increment by `flipCredit` (BURNIE base units)
- AFFILIATE: increment by `commission` (BURNIE base units)
- DECIMATOR: increment by `burnAmount` (BURNIE base units)
- LOOTBOX: increment by `lootboxCost` (wei)
- DEGENERETTE_ETH: increment by `betAmount` (wei)
- DEGENERETTE_BURNIE: increment by `betAmount` (BURNIE base units)

Progress is clamped at uint128 max on overflow (same `_clampedAdd128` pattern as daily quests).

---

## 5. Global Per-Level Quest Storage

**Decisions:** D-06, D-14
**Requirement:** STOR-01

### Mapping

```solidity
mapping(uint24 => uint8) internal levelQuestType;
```

- **Key:** Level number (uint24). Matches the `level` variable type in DegenerusGameStorage.
- **Value:** Quest type ID (uint8). Values 0-8 per `QUEST_TYPE_*` constants. Value 4 (RESERVED) is never written.
- **Location:** Whichever contract houses level quest state (DegenerusQuests.sol or DegenerusGameStorage.sol -- deferred to Phase 154).

### Why Store Only Type (Not Target)

Targets are deterministic from type + `mintPrice`:
- BURNIE-denominated types (MINT_BURNIE, FLIP, AFFILIATE, DECIMATOR, DEGENERETTE_BURNIE) have fixed targets: 10 or 20,000e18.
- ETH-denominated types (MINT_ETH, LOOTBOX, DEGENERETTE_ETH) derive targets from `mintPrice * multiplier` at evaluation time.

Storing the target would:
- Cost 1 extra SSTORE at roll time (22,100 gas for cold new value)
- Save 0 SLOADs at evaluation time (ETH types still need `mintPrice`)
- Add storage complexity (larger packed value or second mapping)

Decision: store type only. Derive target in `_levelQuestTargetValue()`.

### SLOAD Count

- Reading quest type for a level: 1 cold SLOAD (2,100 gas) or 1 warm SLOAD (100 gas).
- Mapping slot: `keccak256(abi.encode(level, slot_of_levelQuestType))`.

---

## 6. Completion Flow

**Decisions:** D-11, D-12
**Requirement:** MECH-04

### Sequence

1. **Progress handler** detects `progress >= target` after accumulation.
2. **Once-per-level guard:** Check `completed == false` in packed state (bit 152).
   - If `completed == true`: skip. Already completed this level.
3. **Set completed:** Write `completed = true` in packed state.
4. **Credit reward:** Call `coinflip.creditFlip(player, 800 ether)`.
   - 800 BURNIE = 800e18 base units.
   - `creditFlip` credits this as flip stake to the player's next coinflip day.
5. **Update storage:** Write packed state back (progress + completed flag in one SSTORE).
6. **Emit event:** `LevelQuestCompleted(player, level, questType, 800 ether)`.

### No Slot System (per D-12)

Daily quests have 2 slots (slot 0 = MINT_ETH, slot 1 = random) with a completion mask (bits 0-1 per slot, bit 7 for streak credited). Level quests have exactly ONE quest per level. No completion mask needed -- just the single `completed` bool (bit 152 in packed state).

### No Streak Interaction

Level quest completion does NOT interact with daily quest streak. The systems are completely independent (per D-09). There is no level quest streak -- no consecutive-level tracking for the quest itself.

### creditFlip Details

```solidity
coinflip.creditFlip(player, 800 ether);
```

- `coinflip` = `IBurnieCoinflip(ContractAddresses.COINFLIP)`
- `creditFlip` signature: `function creditFlip(address player, uint256 amount) external onlyFlipCreditors`
- `onlyFlipCreditors` requires the caller to be in the flip creditors whitelist.
- If level quest logic lives in DegenerusQuests.sol (standalone contract): the quest contract address must be added to flip creditors.
- If level quest logic lives in a DegenerusGame module (delegatecall): the call executes in the game's context, and the game address is already a flip creditor.
- Decision on which contract houses the logic is deferred to Phase 154 (Integration Mapping).

### Completion Pseudocode

```solidity
function _checkLevelQuestCompletion(
    address player,
    uint256 packed,
    uint8 questType,
    uint256 mintPrice
) internal returns (uint256 updatedPacked) {
    uint128 progress = uint128(packed >> 24);
    bool completed = (packed >> 152) & 1 == 1;

    if (completed) return packed;  // already done this level

    uint256 target = _levelQuestTargetValue(questType, mintPrice);
    if (target == 0 || progress < target) return packed;

    // Complete!
    updatedPacked = packed | (uint256(1) << 152);  // set completed bit
    coinflip.creditFlip(player, 800 ether);
    emit LevelQuestCompleted(player, level, questType, 800 ether);
    return updatedPacked;
}
```

---

## 7. Storage Layout Summary

**Requirements:** STOR-01, STOR-02

### New Storage Variables

| Variable | Type | Slot Impact | Location (deferred to Phase 154) |
|---|---|---|---|
| `levelQuestType` | `mapping(uint24 => uint8)` | 1 new mapping root slot | DegenerusQuests.sol or DegenerusGameStorage.sol |
| `levelQuestPlayerState` | `mapping(address => uint256)` | 1 new mapping root slot | Same contract as above |

### SLOAD Budget Per Operation

| Operation | SLOADs | Detail |
|---|---|---|
| **Eligibility check** | 1-2 | `mintPacked_[player]` (1 SLOAD) + `deityPassCount[player]` (0-1 SLOAD, only if mintPacked_ doesn't satisfy loyalty gate) |
| **Quest roll** (level transition) | 0 extra | `rngWordByDay[day]` is already warm from rngGate. Quest type write = 1 SSTORE. |
| **Progress handler** (hot path) | 2 | `levelQuestType[level]` (1 SLOAD) + `levelQuestPlayerState[player]` (1 SLOAD) |
| **Completion check** | 0 extra | `levelQuestPlayerState[player]` is already loaded from progress check |
| **Target derivation** | 0-1 | BURNIE types: 0 (constant). ETH types: `mintPrice` from Slot 1 (likely warm, 0 extra) |

**Total hot-path cost (progress handler with completion):** 2 SLOADs + 1 SSTORE = ~4,300 gas cold (2,100 + 2,100 + 100 SSTORE-existing) or ~22,300 gas cold-with-new-value.

### SSTORE Budget Per Operation

| Operation | SSTOREs | Detail | Cost |
|---|---|---|---|
| **Quest roll** | 1 | `levelQuestType[purchaseLevel] = type` | 22,100 gas (new non-zero) |
| **Progress update** | 1 | `levelQuestPlayerState[player]` packed write | 5,000 gas (dirty slot) or 22,100 gas (new) |
| **Completion** | 0 extra | Same packed word as progress (already dirty) | 0 gas (included in progress write) |

### Collision Analysis

Both new mappings occupy their own keccak256-derived slot spaces:
- `levelQuestType`: slot derived from `keccak256(level_key . mapping_slot_number)`
- `levelQuestPlayerState`: slot derived from `keccak256(player_address . mapping_slot_number)`

**No collision with existing storage:**
- Mappings are inherently isolated by definition (keccak256 preimage includes the mapping's slot number).
- If placed in **DegenerusQuests.sol**: append after existing `questVersionCounter` (slot 4+). New mapping root slots occupy previously unused sequential slots.
- If placed in **DegenerusGameStorage.sol**: append at end of storage layout. New mapping root slots follow all existing declarations. No reorder of existing variables.

**Delegatecall safety:** If placed in DegenerusGameStorage, all modules that inherit the storage layout must include the new declarations at the same position. This is standard for the existing module pattern.

---

## 8. Open Design Questions for Phase 154

The following questions must be resolved during Phase 154 (Integration Mapping):

1. **Contract location:** Which contract houses level quest state -- DegenerusQuests.sol (standalone, called via external call) or DegenerusGameStorage.sol (accessible by delegatecall modules)?
   - DegenerusQuests.sol: simpler isolation, but requires adding it to `onlyFlipCreditors` for creditFlip. Quest handlers already live here.
   - DegenerusGameStorage.sol: natural for delegatecall modules, creditFlip already authorized via game address. But quest handlers in DegenerusQuests.sol would need cross-contract reads.

2. **Handler routing:** How do `handleX()` functions detect level quest type and route progress? Options:
   - Augment existing `handleMint`, `handleFlip`, etc. with parallel level quest progress tracking.
   - Create new `handleLevelQuest*()` entry points called separately.
   - Single combined handler that processes both daily and level quests.

3. **Roll trigger path:** Does the level quest roll go through BurnieCoin (like daily quests use `coin.rollDailyQuest`) or directly from AdvanceModule?
   - Daily quests: Coin calls `rollDailyQuest` during `payDailyJackpot` and `_payDailyCoinJackpot` in JackpotModule.
   - Level quests: One roll per level transition, not per day. Direct call from AdvanceModule during `phaseTransitionActive` block may be simpler.

---

## Traceability

### Decision Coverage

| Decision | Section | Value Documented |
|---|---|---|
| D-01 | 1. Eligibility | levelStreak >= 5, pass detection, 4 ETH units |
| D-02 | 1. Eligibility | Same storage read patterns as daily quests |
| D-03 | 1. Eligibility | deityPassCount, frozenUntilLevel + whaleBundleType |
| D-04 | 2. Global Quest Roll | Global roll at level start in advanceGame |
| D-05 | 2. Global Quest Roll | Same 8 types and weight table |
| D-06 | 2. Global Quest Roll, 5. Storage | Quest type stored globally per level |
| D-07 | 3. Quest Targets | 10x targets, no caps |
| D-08 | 3. Quest Targets | Edge cases analyzed, not capped or excluded |
| D-09 | 4. Per-Player Progress | Independent from daily quests |
| D-10 | 4. Per-Player Progress | Level-based invalidation at boundaries |
| D-11 | 6. Completion Flow | Once per level, 800 BURNIE creditFlip |
| D-12 | 6. Completion Flow | No slot system, single completion |
| D-13 | 4. Per-Player Progress | Follows questPlayerState mapping pattern |
| D-14 | 5. Global Per-Level Storage | New global mapping for type per level |

### Requirement Coverage

| Requirement | Section(s) | Status |
|---|---|---|
| ELIG-01 | 1. Eligibility (storage layout, bit positions, masks) | Covered |
| ELIG-02 | 1. Eligibility (SLOAD count, gas cost table, pseudocode) | Covered |
| MECH-01 | 2. Global Quest Roll (when, VRF source, weight table, storage) | Covered |
| MECH-02 | 3. Quest Targets (10x table, edge cases, derivation function) | Covered |
| MECH-03 | 4. Per-Player Progress (packed layout, invalidation, independence) | Covered |
| MECH-04 | 6. Completion Flow (sequence, guard, creditFlip, event) | Covered |
| STOR-01 | 5. Global Per-Level Storage, 7. Storage Layout Summary | Covered |
| STOR-02 | 7. Storage Layout Summary (SLOAD/SSTORE budgets, collision analysis) | Covered |

---

*Specification produced by Phase 153 Plan 01. Implementer-ready: all values are concrete, all storage reads are specified with exact bit positions, all operations have SLOAD/SSTORE budgets.*
