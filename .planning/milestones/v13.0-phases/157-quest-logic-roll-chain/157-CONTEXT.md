# Phase 157: Quest Logic & Roll Chain - Context

**Gathered:** 2026-03-31
**Status:** Ready for planning

<domain>
## Phase Boundary

Implement the quest roll, eligibility check, target calculation, and completion flow inside DegenerusQuests.sol, and wire the AdvanceModule-to-DegenerusQuests roll trigger that fires at level transitions. No handler modifications in this phase (that's Phase 158).

</domain>

<decisions>
## Implementation Decisions

### Quest Roll (`rollLevelQuest`)
- **D-01:** Fill the `rollLevelQuest(uint24 lvl, uint256 entropy)` stub (currently a TODO at line 1613) with quest type selection logic. Use `_bonusQuestType(entropy, type(uint8).max, decAllowed)` — the `type(uint8).max` sentinel never matches any candidate, so no type is excluded (all 8 real types eligible). This follows the integration map Section 6.4 recommendation.
- **D-02:** Decimator eligibility: call existing `_canRollDecimatorQuest()` which reads `questGame.decWindowOpenFlag()` and checks level constraints. At level transition, this reflects the outgoing level's decimator window state.
- **D-03:** Write `levelQuestType[lvl] = selectedType` after selection. One cold SSTORE (22,100 gas).

### Eligibility Check (`_isLevelQuestEligible`)
- **D-04:** Implement `_isLevelQuestEligible(address player)` in DegenerusQuests.sol per Phase 153 spec Section 1 pseudocode. Returns true when (levelStreak >= 5 OR any active pass) AND (levelUnits >= 4 this level).
- **D-05:** DegenerusQuests cannot read `mintPacked_[player]` directly (standalone contract, not delegatecall). A new view function on IDegenerusGame/DegenerusGame must expose the needed packed fields (levelStreak, unitsLevel, levelUnits, frozenUntilLevel, whaleBundleType). The `deityPassCountFor(address)` view already exists on IDegenerusGame (line 353). Researcher/planner determines optimal interface shape (single struct return vs. raw uint256).
- **D-06:** Activity gate evaluates first (cheap: reads from same packed word), short-circuits before loyalty gate + deity pass fallback (saves up to 1 SLOAD).

### Target Calculation (`_levelQuestTargetValue`)
- **D-07:** Implement `_levelQuestTargetValue(uint8 questType, uint256 mintPrice)` per Phase 153 spec Section 3. Returns 10x daily targets. No ETH cap applied (explicitly NOT using QUEST_ETH_TARGET_CAP). MINT_BURNIE returns 10 (ticket count), MINT_ETH returns mintPrice * 10, LOOTBOX/DEGENERETTE_ETH return mintPrice * 20, BURNIE-denominated types return 20_000 ether.

### Completion Flow
- **D-08:** When progress >= target AND completed bit (152) is false: set completed bit, call `coinflip.creditFlip(player, 800 ether)`, emit `LevelQuestCompleted(player, level, questType, 800 ether)`. One packed SSTORE (progress + completed in same word).
- **D-09:** `coinflip` reference: `IBurnieCoinflip(ContractAddresses.COINFLIP)`. QUESTS is already in `onlyFlipCreditors` (Phase 156 ACL-01).

### Shared Progress Handler (`_handleLevelQuestProgress`)
- **D-10:** Implement `_handleLevelQuestProgress(address player, uint8 questType, uint256 delta, uint256 mintPrice)` as shared internal function. Called by each of the 6 handlers (Phase 158). Reads `levelQuestType[level]`, checks type match, reads `levelQuestPlayerState[player]`, validates level boundary (invalidates stale data), checks eligibility, accumulates progress, checks completion.
- **D-11:** Level-boundary invalidation: compare `questLevel` (bits 0-23 of packed state) with current game level. If mismatch, reset to current level with zero progress.

### AdvanceModule Roll Trigger
- **D-12:** AdvanceModule calls `quests.rollLevelQuest(purchaseLevel, questEntropy)` directly at the insertion point: after FF drain completes, before `phaseTransitionActive = false` (line 283 of AdvanceModule). No BurnieCoin hop — the routing cleanup is already done (rollLevelQuest uses `onlyGame` modifier, BurnieCoin forwarding removed).
- **D-13:** Entropy derivation: `uint256 questEntropy = uint256(keccak256(abi.encodePacked(rngWordByDay[day], "LEVEL_QUEST")))`. Uses unique salt for statistical independence from other entropy consumers.
- **D-14:** AdvanceModule needs `IDegenerusQuests` import and `quests` constant (same pattern as JackpotModule lines 6, 101-102).

### Stub Cleanup
- **D-15:** Replace the 3 phase-referencing comments in Phase 156 stubs (lines 1610, 1614, 1618) with descriptive NatSpec when filling function bodies. Comments must describe what the function IS, not what phase added it (per `feedback_no_history_in_comments`).

### Claude's Discretion
- Exact interface design for the new mintPacked_ view function on DegenerusGame (struct vs. raw uint256 vs. individual getters)
- Whether `_handleLevelQuestProgress` returns the reward amount or handles it internally
- Internal code organization and helper function naming
- NatSpec documentation detail level on new functions

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Level Quest Design Spec (PRIMARY)
- `.planning/phases/153-core-design/153-01-LEVEL-QUEST-SPEC.md` — Complete spec: eligibility (Section 1), quest roll (Section 2), 10x targets (Section 3), per-player progress (Section 4), storage (Section 5), completion flow (Section 6)

### Integration Map (PRIMARY)
- `.planning/phases/154-integration-mapping/154-01-INTEGRATION-MAP.md` — Contract touchpoints, exact line numbers, handler integration pattern (Section 5), roll path (Section 6), storage decisions (Section 7)

### Phase 156 Foundation
- `.planning/phases/156-interfaces-storage-access-control/156-VERIFICATION.md` — Current state verification: storage at lines 280/283, rollLevelQuest stub at line 1613, onlyGame modifier, BurnieCoinflip QUESTS creditor at line 201

### Contract References
- `contracts/DegenerusQuests.sol` — Quest logic home: storage (280-283), modifiers (290-299), rollLevelQuest stub (1613), getPlayerLevelQuestView stub (1620), _bonusQuestType (1299-1369), _canRollDecimatorQuest (1008-1017), _questTargetValue (existing daily quest targets for reference)
- `contracts/modules/DegenerusGameAdvanceModule.sol` — Roll trigger insertion point: phaseTransitionActive block (260-292), specifically between FF drain completion and line 284 (`phaseTransitionActive = false`)
- `contracts/modules/DegenerusGameJackpotModule.sol` lines 6, 101-102 — Pattern for `quests` constant import (IDegenerusQuests + ContractAddresses.QUESTS)
- `contracts/interfaces/IDegenerusGame.sol` — Existing view functions: level() (line 18), mintPrice() (line 32), deityPassCountFor() (line 353), decWindowOpenFlag() (line 42)
- `contracts/storage/DegenerusGameStorage.sol` — mintPacked_ bit layout: levelStreak (48-71), unitsLevel (104-127), frozenUntilLevel (128-151), whaleBundleType (152-153), levelUnits (228-243)
- `contracts/BurnieCoinflip.sol` — creditFlip function, onlyFlipCreditors with QUESTS at line 201

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `_bonusQuestType(entropy, primaryType, decAllowed)`: Exact weight table needed for level quests. Call with `type(uint8).max` sentinel to include all types.
- `_canRollDecimatorQuest()`: Reads game state for decimator window eligibility. Reusable as-is.
- `_clampedAdd128(a, b)`: Overflow-safe uint128 addition. Used by daily quests, reusable for level quest progress.
- `questGame` constant: `IDegenerusGame(ContractAddresses.GAME)` already wired for mintPrice(), level(), decWindowOpenFlag() reads.
- `ContractAddresses.COINFLIP`: Already used by daily quest reward path; reusable for level quest creditFlip call.

### Established Patterns
- Daily quest handlers: read quest type → check match → read player state → accumulate progress → check completion → credit reward. Level quest follows identical flow.
- Packed uint256 state: daily quests use PlayerQuestState struct; level quests use raw uint256 with bit-level packing (simpler: no struct needed, just bit shifts).
- Access control: `onlyGame` modifier for functions called by game modules via delegatecall context.
- Entropy derivation: `keccak256(abi.encodePacked(rngWord, salt))` for independent entropy streams.

### Integration Points
- AdvanceModule phaseTransitionActive block (line 283): insert quest roll call
- DegenerusQuests rollLevelQuest stub (line 1613): fill with selection logic
- DegenerusQuests getPlayerLevelQuestView stub (line 1620): fill with state read logic
- IDegenerusGame: add new view function for mintPacked_ field access
- DegenerusGame: implement the new view function

</code_context>

<specifics>
## Specific Ideas

- The integration map (Section 6.4) explicitly recommends `type(uint8).max` sentinel over QUEST_TYPE_RESERVED for the primaryType exclusion bypass. This is cleaner because QUEST_TYPE_RESERVED has weight 0 and is separately skipped, so using it as primaryType would technically work but conflates two different skip reasons.
- The integration map (Section 5.1) provides a complete pseudocode template for `_handleLevelQuestProgress` showing the exact read-check-accumulate-complete sequence with gas annotations.
- Phase 156 verification notes that contract files may be unstaged — user should verify working tree state before Phase 157 execution begins.

</specifics>

<deferred>
## Deferred Ideas

None -- discussion stayed within phase scope

</deferred>

---

*Phase: 157-quest-logic-roll-chain*
*Context gathered: 2026-03-31*
