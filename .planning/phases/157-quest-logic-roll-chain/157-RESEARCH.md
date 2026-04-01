# Phase 157: Quest Logic & Roll Chain - Research

**Researched:** 2026-03-31
**Domain:** Solidity smart contract logic implementation -- DegenerusQuests.sol core functions + AdvanceModule roll trigger wiring
**Confidence:** HIGH

## Summary

Phase 157 fills five function bodies in DegenerusQuests.sol (`rollLevelQuest`, `_isLevelQuestEligible`, `_levelQuestTargetValue`, `_handleLevelQuestProgress`, and `getPlayerLevelQuestView`) and inserts a 2-line roll trigger in DegenerusGameAdvanceModule.sol. All storage, interfaces, access control, and stubs were laid by Phase 156 and verified. The work is fully specified by the Phase 153 design spec and Phase 154 integration map, with exact pseudocode, bit layouts, and gas budgets.

A critical finding is that ROLL-01 in REQUIREMENTS.md ("BurnieCoin.rollLevelQuest routing function") is obsolete. The Phase 157 CONTEXT.md decision D-12 supersedes it: AdvanceModule calls `quests.rollLevelQuest()` directly with `onlyGame` access control. BurnieCoin has no `rollLevelQuest` function in the current codebase. The planner must treat D-12 as authoritative and ROLL-01 as satisfied by the direct route.

A new view function is needed on IDegenerusGame / DegenerusGame to expose `mintPacked_` fields for the eligibility check, since DegenerusQuests is a standalone contract that cannot read game storage directly.

**Primary recommendation:** Implement in dependency order: (1) new mintPacked view on DegenerusGame, (2) pure/view functions in DegenerusQuests (`_levelQuestTargetValue`, `_isLevelQuestEligible`), (3) state-writing functions (`rollLevelQuest`, `_handleLevelQuestProgress`, completion flow, `getPlayerLevelQuestView`), (4) AdvanceModule roll trigger wiring.

<user_constraints>

## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** `rollLevelQuest(uint24 lvl, uint256 entropy)` uses `_bonusQuestType(entropy, type(uint8).max, decAllowed)` -- sentinel ensures no type excluded. All 8 real types eligible.
- **D-02:** Decimator eligibility via existing `_canRollDecimatorQuest()`. Reflects outgoing level's decimator window state.
- **D-03:** Write `levelQuestType[lvl] = selectedType` after selection. One cold SSTORE.
- **D-04:** `_isLevelQuestEligible(address player)` per Phase 153 spec Section 1 pseudocode. Returns true when (levelStreak >= 5 OR any active pass) AND (levelUnits >= 4 this level).
- **D-05:** New view function on IDegenerusGame/DegenerusGame to expose mintPacked_ fields. DegenerusQuests cannot read mintPacked_ directly. Interface shape is Claude's discretion.
- **D-06:** Activity gate evaluates first (cheap), short-circuits before loyalty gate + deity pass fallback.
- **D-07:** `_levelQuestTargetValue(uint8 questType, uint256 mintPrice)` per Phase 153 spec Section 3. 10x daily targets. No ETH cap. MINT_BURNIE returns 10, MINT_ETH returns mintPrice * 10, LOOTBOX/DEGENERETTE_ETH return mintPrice * 20, BURNIE types return 20_000 ether.
- **D-08:** Completion: set bit 152, call `coinflip.creditFlip(player, 800 ether)`, emit `LevelQuestCompleted`. One packed SSTORE.
- **D-09:** `coinflip` reference: `IBurnieCoinflip(ContractAddresses.COINFLIP)`. QUESTS already in `onlyFlipCreditors`.
- **D-10:** `_handleLevelQuestProgress(address player, uint8 questType, uint256 delta, uint256 mintPrice)` as shared internal function. Reads levelQuestType, checks match, reads playerState, validates level boundary, checks eligibility, accumulates, checks completion.
- **D-11:** Level-boundary invalidation: compare questLevel (bits 0-23) with current game level. Mismatch resets to current level with zero progress.
- **D-12:** AdvanceModule calls `quests.rollLevelQuest(purchaseLevel, questEntropy)` DIRECTLY (no BurnieCoin hop). Insertion point: after FF drain, before `phaseTransitionActive = false` (line 283). Uses `onlyGame` modifier.
- **D-13:** Entropy: `uint256 questEntropy = uint256(keccak256(abi.encodePacked(rngWordByDay[day], "LEVEL_QUEST")))`. Unique salt for statistical independence.
- **D-14:** AdvanceModule needs `IDegenerusQuests` import and `quests` constant (same pattern as JackpotModule lines 6, 101-102).
- **D-15:** Replace 3 phase-referencing stub comments (lines 1610, 1614, 1618) with descriptive NatSpec. Comments describe what IS, not what changed.

### Claude's Discretion
- Exact interface design for the new mintPacked_ view function on DegenerusGame (struct vs. raw uint256 vs. individual getters)
- Whether `_handleLevelQuestProgress` returns the reward amount or handles it internally
- Internal code organization and helper function naming
- NatSpec documentation detail level on new functions

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope

</user_constraints>

<phase_requirements>

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| QUEST-02 | `rollLevelQuest(uint24 lvl, uint256 entropy)` external function -- selects quest type via `_bonusQuestType` with no exclusion, writes `levelQuestType[lvl]` | Stub exists at DegenerusQuests.sol:1613 with `onlyGame` modifier. `_bonusQuestType` at line 1299 accepts `primaryType` param; `type(uint8).max` sentinel never matches any candidate. `_canRollDecimatorQuest()` at line 1008 is reusable as-is. |
| QUEST-03 | `_isLevelQuestEligible(address player)` internal view -- (levelStreak >= 5 OR pass) AND (levelUnits >= 4 this level) | Requires new view on DegenerusGame to expose mintPacked_ bits. Existing `deityPassCountFor()` at IDegenerusGame:353 already available. Pseudocode in spec Section 1 is implementer-ready. |
| QUEST-04 | `_levelQuestTargetValue(uint8 questType, uint256 mintPrice)` internal pure -- 10x targets, no ETH cap | Pure function, no external dependencies. Existing `_questTargetValue` at line 1248 provides reference pattern. Constants QUEST_MINT_TARGET=1, QUEST_BURNIE_TARGET=2000 ether, QUEST_LOOTBOX_TARGET_MULTIPLIER=2 all reusable with 10x multiplier. |
| QUEST-06 | Completion flow -- once-per-level guard (bit 152), direct `creditFlip(player, 800 ether)` to BurnieCoinflip, `LevelQuestCompleted` event | IBurnieCoinflip import needed in DegenerusQuests.sol (not present currently). QUESTS already whitelisted in `onlyFlipCreditors` (Phase 156 ACL-01). Event declared in IDegenerusQuests.sol:155. |
| ROLL-01 | **SUPERSEDED by D-12**: REQUIREMENTS.md says "BurnieCoin.rollLevelQuest routing function" but CONTEXT.md D-12 decided direct AdvanceModule-to-DegenerusQuests call. BurnieCoin has no rollLevelQuest function. The `onlyGame` modifier on the stub confirms the direct route. ROLL-01 is satisfied by the direct call path. | No BurnieCoin changes needed. AdvanceModule calls quests.rollLevelQuest() in delegatecall context (msg.sender = GAME), matching `onlyGame` modifier. |
| ROLL-02 | AdvanceModule insertion -- `quests.rollLevelQuest(purchaseLevel, questEntropy)` after FF drain, before `phaseTransitionActive = false`, with keccak256 entropy from `rngWordByDay[day]` | AdvanceModule:283 is the insertion point. `rngWordByDay[day]` is warm from `rngGate()`. AdvanceModule already imports `IDegenerusCoin` and has `coin` constant; needs `IDegenerusQuests` import + `quests` constant added (pattern from JackpotModule:6, 101-102). |

</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Solidity | 0.8.34 | Smart contract language | Project-wide compiler version |
| Hardhat | (project version) | Compilation and testing | Project build system |

No new dependencies. All work uses existing contract infrastructure.

## Architecture Patterns

### Contract Touch Points

```
contracts/
  DegenerusQuests.sol            # PRIMARY: fill 5 function bodies + new internal functions
  interfaces/IDegenerusGame.sol  # ADD: new view function signature for mintPacked_ fields
  DegenerusGame.sol              # ADD: implement new view function
  modules/DegenerusGameAdvanceModule.sol  # ADD: import, constant, 2-line roll trigger
```

### Pattern 1: Direct Cross-Contract Quest Roll (No BurnieCoin Hop)

**What:** AdvanceModule (delegatecall as GAME) calls DegenerusQuests.rollLevelQuest() directly. This differs from daily quest routing which goes through BurnieCoin.

**When to use:** Level quest roll happens once per level transition, not per daily jackpot. Direct routing is simpler and saves one external call hop.

**Key insight:** AdvanceModule executes via delegatecall, so `msg.sender` for any external call it makes is the GAME address. The `onlyGame` modifier on `rollLevelQuest` checks `msg.sender != ContractAddresses.GAME`, which is satisfied.

```solidity
// In AdvanceModule, inside phaseTransitionActive block, after FF drain:
uint256 questEntropy = uint256(keccak256(abi.encodePacked(rngWordByDay[day], "LEVEL_QUEST")));
quests.rollLevelQuest(purchaseLevel, questEntropy);
// Then: phaseTransitionActive = false;
```

### Pattern 2: Packed uint256 Bit Manipulation for Player State

**What:** Level quest player state packed into single uint256: questLevel (bits 0-23), progress (bits 24-151), completed (bit 152).

**Key operations:**
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

### Pattern 3: Sentinel Value for No-Exclusion Quest Roll

**What:** Calling `_bonusQuestType(entropy, type(uint8).max, decAllowed)` with `type(uint8).max` (255) as the `primaryType` parameter. Since no quest type has ID 255, the exclusion check `candidate == primaryType` never matches, making all types eligible.

**Why:** Cleaner than adding a separate function or boolean flag. Reuses existing weighted selection logic exactly.

### Pattern 4: New View Function for Cross-Contract mintPacked_ Access

**What:** DegenerusQuests needs to read 5 fields from `mintPacked_[player]` for eligibility (levelStreak, unitsLevel, levelUnits, frozenUntilLevel, whaleBundleType). As a standalone contract, it cannot read `mintPacked_` directly.

**Recommended approach (Claude's discretion area):** Return raw `uint256` packed value via a single view function `mintPackedFor(address player)`. Let DegenerusQuests unpack the bits it needs. This is the most gas-efficient option (single SLOAD + single return value, no struct ABI overhead) and requires minimal interface surface area.

Alternative: Return a struct with named fields. More readable but costs more gas (ABI encoding of 5 fields vs 1 uint256) and adds a struct definition to the interface.

**Evidence:** The existing pattern in the codebase favors raw uint256 for packed data. `mintPacked_` is already a raw uint256 internally. Bit positions are well-documented in DegenerusGameStorage.sol:421-428 and the Phase 153 spec Section 1.

```solidity
// In IDegenerusGame.sol:
function mintPackedFor(address player) external view returns (uint256);

// In DegenerusGame.sol:
function mintPackedFor(address player) external view returns (uint256) {
    return mintPacked_[player];
}

// In DegenerusQuests._isLevelQuestEligible:
uint256 packed = questGame.mintPackedFor(player);
uint24 unitsLvl = uint24(packed >> 104);
// ... bit extraction as per spec Section 1
```

### Anti-Patterns to Avoid

- **Reading mintPacked_ fields individually:** Multiple view calls (getLevelStreak, getUnitsLevel, etc.) would cost N external calls vs 1. Use a single raw uint256 return.
- **Storing quest target alongside type:** Targets derive from type + mintPrice. Storing target wastes 22,100 gas SSTORE at roll time and saves nothing at read time.
- **Checking eligibility BEFORE type match:** Type match is a cheap comparison. Eligibility requires 1-2 cross-contract SLOADs. Always check type match first.
- **History in NatSpec comments:** Per project rules, comments describe what IS. No "replaced X with Y", "Phase 157 added this", etc.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Weighted random selection | Custom selection logic | `_bonusQuestType(entropy, type(uint8).max, decAllowed)` | Weight table already correct, tested, handles decimator eligibility |
| Overflow-safe uint128 add | Manual overflow check | `_clampedAdd128(current, delta)` at line 1030 | Already handles unchecked arithmetic correctly |
| Decimator window check | Manual level math | `_canRollDecimatorQuest()` at line 1008 | Already handles X5/X95/X00 level logic |
| mintPrice reads | Repeated external calls | `questGame.mintPrice()` (already used 4 times in DegenerusQuests) | Warm read pattern established |

## Common Pitfalls

### Pitfall 1: ROLL-01 vs CONTEXT.md D-12 Conflict
**What goes wrong:** Implementing BurnieCoin.rollLevelQuest routing as REQUIREMENTS.md ROLL-01 specifies, when the actual decision changed to direct AdvanceModule-to-DegenerusQuests routing.
**Why it happens:** REQUIREMENTS.md was written before the Phase 157 discussion refined the routing decision.
**How to avoid:** Treat CONTEXT.md D-12 as authoritative. The `onlyGame` modifier on the stub (not `onlyCoin`) confirms the direct route. BurnieCoin has no rollLevelQuest function.
**Warning signs:** If you find yourself adding a function to BurnieCoin.sol, something is wrong.

### Pitfall 2: Level 0 Edge Case in Type Check
**What goes wrong:** `levelQuestType[0]` returns 0 (QUEST_TYPE_MINT_BURNIE) because Solidity mappings default to 0. A handler at level 0 could incorrectly match MINT_BURNIE as the level quest.
**Why it happens:** Level quest roll occurs at level TRANSITION. Level 0 never had a transition (game starts at 0). So `levelQuestType[0]` is never written.
**How to avoid:** The integration map Section 5.1 pseudocode handles this: `if (lqType != 0 || currentLevel == 0)` with a comment explaining that at level 0 with type 0, there's no level quest. The `_handleLevelQuestProgress` function must guard against this.
**Warning signs:** If level 0 players show quest progress, the guard is missing.

### Pitfall 3: IBurnieCoinflip Import Missing
**What goes wrong:** DegenerusQuests.sol currently imports only IDegenerusQuests, IDegenerusGame, and ContractAddresses. The `creditFlip` call in the completion flow requires IBurnieCoinflip.
**Why it happens:** Phase 156 added stubs but not the import needed for the completion body.
**How to avoid:** Add `import {IBurnieCoinflip} from "./interfaces/IBurnieCoinflip.sol";` to DegenerusQuests.sol imports.
**Warning signs:** Compilation error on `IBurnieCoinflip(ContractAddresses.COINFLIP).creditFlip(...)`.

### Pitfall 4: Stale Phase-Reference Comments
**What goes wrong:** The 3 stub comments from Phase 156 (lines 1610, 1614, 1618) reference "Phase 156", "Phase 157", "Phase 158". Leaving these violates project feedback rules.
**Why it happens:** Stubs were scaffolding; NatSpec was placeholder.
**How to avoid:** D-15 explicitly requires replacing all 3 with descriptive NatSpec when filling bodies. Comments must describe what the function IS.
**Warning signs:** Any comment mentioning a phase number in the final code.

### Pitfall 5: Activity Gate Using Stale unitsLevel
**What goes wrong:** `levelUnits` (bits 228-243) is only valid when `unitsLevel` (bits 104-127) equals the current game level. If unitsLevel != level, the player has not minted this level and levelUnits is stale.
**Why it happens:** mintPacked_ stores both the level when units were counted and the count itself. They must be read together.
**How to avoid:** Check `unitsLevel == level` BEFORE reading `levelUnits`. If mismatch, treat as 0 units.
**Warning signs:** Players from previous levels appearing eligible without minting this level.

### Pitfall 6: Forgetting to Reset Packed State on Level Boundary
**What goes wrong:** Player accumulates progress in level N, level advances to N+1. If the handler doesn't detect the level mismatch and reset, stale progress carries over.
**Why it happens:** `levelQuestPlayerState[player]` persists across levels. Invalidation must be explicit.
**How to avoid:** D-11 specifies: compare `uint24(packed)` (questLevel) with current game level. If mismatch, reset packed to just `uint256(currentLevel)` (zero progress, not completed).
**Warning signs:** Players completing level N+1 quest instantly with progress from level N.

## Code Examples

### rollLevelQuest Body (D-01, D-02, D-03)

```solidity
// Source: Phase 153 spec Section 2 + Phase 154 integration map Section 6.4
function rollLevelQuest(uint24 lvl, uint256 entropy) external override onlyGame {
    bool decAllowed = _canRollDecimatorQuest();
    uint8 selectedType = _bonusQuestType(entropy, type(uint8).max, decAllowed);
    levelQuestType[lvl] = selectedType;
}
```

### _isLevelQuestEligible Body (D-04, D-05, D-06)

```solidity
// Source: Phase 153 spec Section 1 pseudocode
function _isLevelQuestEligible(address player) internal view returns (bool) {
    uint256 packed = questGame.mintPackedFor(player);  // new view function

    // Activity gate first (cheap: same packed word)
    uint24 unitsLvl = uint24(packed >> 104);
    if (unitsLvl != questGame.level()) return false;
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
    return questGame.deityPassCountFor(player) > 0;
}
```

### _levelQuestTargetValue Body (D-07)

```solidity
// Source: Phase 153 spec Section 3
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
```

### AdvanceModule Roll Trigger (D-12, D-13, D-14)

```solidity
// In AdvanceModule, after line 283 (FF drain complete), before line 284:
uint256 questEntropy = uint256(keccak256(abi.encodePacked(rngWordByDay[day], "LEVEL_QUEST")));
quests.rollLevelQuest(purchaseLevel, questEntropy);
```

With new constant and import:
```solidity
// Import (same pattern as JackpotModule line 6):
import {IDegenerusQuests} from "../interfaces/IDegenerusQuests.sol";

// Constant (same pattern as JackpotModule lines 101-102):
IDegenerusQuests internal constant quests =
    IDegenerusQuests(ContractAddresses.QUESTS);
```

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Hardhat + Solidity compilation |
| Config file | `hardhat.config.js` (existing) |
| Quick run command | `npx hardhat compile --force` |
| Full suite command | `npx hardhat compile --force` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| QUEST-02 | rollLevelQuest selects type and writes storage | manual-only | Compilation verification | N/A |
| QUEST-03 | _isLevelQuestEligible returns correct bool for all gate combinations | manual-only | Compilation verification | N/A |
| QUEST-04 | _levelQuestTargetValue returns correct 10x values for all 8 types | manual-only | Compilation verification | N/A |
| QUEST-06 | Completion sets bit 152, calls creditFlip, emits event | manual-only | Compilation verification | N/A |
| ROLL-01 | Direct AdvanceModule-to-DegenerusQuests roll path works | manual-only | Compilation verification | N/A |
| ROLL-02 | AdvanceModule insertion point correct with keccak256 entropy | manual-only | Compilation verification | N/A |

**Note:** Per REQUIREMENTS.md Out of Scope: "Test suite -- User will review code first, tests follow separately." Validation is compilation + manual code review by user. No automated test files are created in this phase.

### Sampling Rate
- **Per task commit:** `npx hardhat compile --force` (all 62 Solidity files must compile)
- **Per wave merge:** Same compilation check
- **Phase gate:** Compilation green + user code review

### Wave 0 Gaps
None -- test infrastructure is out of scope per requirements. Compilation is the automated gate.

## Open Questions

1. **mintPackedFor View Function Interface Shape**
   - What we know: DegenerusQuests needs 5 fields from mintPacked_[player]. A single view function returning raw uint256 is cheapest. A struct return is more readable but costs more gas.
   - What's unclear: Whether the user prefers the raw uint256 approach or a struct. Both work. The raw approach is recommended per gas efficiency.
   - Recommendation: Use raw `uint256` return. Add to IDegenerusGame.sol interface and DegenerusGame.sol implementation. One new function, one new interface line.

2. **_handleLevelQuestProgress Return Value**
   - What we know: This function either returns a reward amount for the caller to process, or handles the reward internally.
   - What's unclear: Whether the function should return anything.
   - Recommendation: Handle reward internally (call creditFlip + emit event inside the function). Callers don't need the reward value -- the daily quest return values are unchanged (per integration map Section 5.1). This simplifies all 6 handler integration points in Phase 158.

3. **Compilation Impact of New IDegenerusGame Function**
   - What we know: Adding a function to IDegenerusGame.sol requires DegenerusGame.sol to implement it. All contracts importing IDegenerusGame will see the new signature.
   - What's unclear: Whether any mock or test contracts implement IDegenerusGame and would need updating.
   - Recommendation: Verify compilation after adding the view function. If mocks exist, they may need a stub.

## Critical Architectural Finding: ROLL-01 Routing Conflict

The REQUIREMENTS.md ROLL-01 states:

> `BurnieCoin.rollLevelQuest(uint24 lvl, uint256 entropy)` routing function -- `onlyDegenerusGameContract`, forwards to `questModule.rollLevelQuest`

However, the actual codebase and CONTEXT.md D-12 show:

1. **BurnieCoin.sol has NO rollLevelQuest function** (confirmed via grep -- zero matches)
2. **DegenerusQuests.rollLevelQuest uses `onlyGame` modifier** (not `onlyCoin`), meaning it expects calls from GAME address, not COIN
3. **DegenerusGameModuleInterfaces.sol NatSpec explicitly states:** "Quest rolling is handled directly via IDegenerusQuests" (line 7)
4. **CONTEXT.md D-12 says:** "No BurnieCoin hop -- the routing cleanup is already done"

The planner MUST treat D-12 as the authoritative routing decision. ROLL-01 is satisfied by the direct path (AdvanceModule delegatecall as GAME -> DegenerusQuests.onlyGame). No BurnieCoin changes are needed.

## File Inventory (Changes Required)

| File | Change Type | Lines Affected | Description |
|------|-------------|---------------|-------------|
| `contracts/interfaces/IDegenerusGame.sol` | ADD | 1 new function signature | `mintPackedFor(address player)` view |
| `contracts/DegenerusGame.sol` | ADD | ~3 lines | Implement `mintPackedFor` returning raw `mintPacked_[player]` |
| `contracts/DegenerusQuests.sol` | MODIFY | Import section | Add `IBurnieCoinflip` import |
| `contracts/DegenerusQuests.sol` | FILL | Lines 1613-1615 | `rollLevelQuest` body (~3 lines) |
| `contracts/DegenerusQuests.sol` | ADD | New internal function | `_isLevelQuestEligible` (~15 lines) |
| `contracts/DegenerusQuests.sol` | ADD | New internal function | `_levelQuestTargetValue` (~15 lines) |
| `contracts/DegenerusQuests.sol` | ADD | New internal function | `_handleLevelQuestProgress` (~40 lines) |
| `contracts/DegenerusQuests.sol` | FILL | Lines 1620-1627 | `getPlayerLevelQuestView` body (~15 lines) |
| `contracts/DegenerusQuests.sol` | FIX | Lines 1609-1610, 1614, 1617-1618 | Replace phase-referencing NatSpec with descriptive comments |
| `contracts/modules/DegenerusGameAdvanceModule.sol` | ADD | Import section | Add `IDegenerusQuests` import |
| `contracts/modules/DegenerusGameAdvanceModule.sol` | ADD | Constants section | Add `quests` constant |
| `contracts/modules/DegenerusGameAdvanceModule.sol` | ADD | After line 283 | 2-line roll trigger (entropy + call) |

**Estimated total:** ~100 lines of new/modified Solidity across 5 files.

## Sources

### Primary (HIGH confidence)
- `contracts/DegenerusQuests.sol` -- Current stub code, existing functions (_bonusQuestType, _canRollDecimatorQuest, _clampedAdd128, _questTargetValue), storage layout, imports
- `contracts/modules/DegenerusGameAdvanceModule.sol` -- Current phaseTransitionActive block (lines 260-292), existing imports and constants
- `contracts/modules/DegenerusGameJackpotModule.sol` -- Pattern for IDegenerusQuests import (line 6) and quests constant (lines 101-102)
- `contracts/interfaces/IDegenerusQuests.sol` -- LevelQuestCompleted event, rollLevelQuest and getPlayerLevelQuestView signatures
- `contracts/interfaces/IDegenerusGame.sol` -- Existing view functions (level, mintPrice, deityPassCountFor, decWindowOpenFlag)
- `contracts/interfaces/DegenerusGameModuleInterfaces.sol` -- Confirms quest rolling is direct, not via BurnieCoin
- `.planning/phases/153-core-design/153-01-LEVEL-QUEST-SPEC.md` -- Complete spec with pseudocode for all functions
- `.planning/phases/154-integration-mapping/154-01-INTEGRATION-MAP.md` -- Integration pattern, handler sites, roll path, reward path
- `.planning/phases/156-interfaces-storage-access-control/156-VERIFICATION.md` -- Phase 156 verified: storage, stubs, ACL all in place
- `.planning/phases/157-quest-logic-roll-chain/157-CONTEXT.md` -- Authoritative decisions superseding REQUIREMENTS.md

### Secondary (MEDIUM confidence)
- `.planning/REQUIREMENTS.md` -- Phase requirement IDs, but ROLL-01 text is outdated per D-12

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- No new dependencies, all existing contract infrastructure
- Architecture: HIGH -- All patterns directly verified against current source code, pseudocode from spec is implementer-ready
- Pitfalls: HIGH -- All identified from actual code analysis (level 0 edge case, missing import, stale comments, unitsLevel check)

**Research date:** 2026-03-31
**Valid until:** 2026-04-30 (stable -- this is implementation of a finalized spec against verified stubs)
