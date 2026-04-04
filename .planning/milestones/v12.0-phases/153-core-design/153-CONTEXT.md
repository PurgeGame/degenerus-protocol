# Phase 153: Core Design - Context

**Gathered:** 2026-03-31
**Status:** Ready for planning

<domain>
## Phase Boundary

Produce a complete specification for level quest eligibility, mechanics, and storage. Output is a design document — no Solidity implementation. The spec should have zero ambiguity so an implementer can write the code without design questions.

</domain>

<decisions>
## Implementation Decisions

### Eligibility (ELIG-01, ELIG-02)
- **D-01:** Eligibility criteria: (levelStreak >= 5 from mintPacked_ OR any active pass: deity/lazy/whale) AND (ETH mint >= 4 units this level from mintPacked_.levelUnits)
- **D-02:** Use the same eligibility check patterns as daily quests — follow existing DegenerusQuests.sol conventions for storage reads and boolean evaluation
- **D-03:** Pass detection reads: deityPassCount[player] > 0 (deity), frozenUntilLevel > 0 with whaleBundleType != 0 (whale/lazy) from mintPacked_

### Quest Roll (MECH-01)
- **D-04:** Global roll at level start during advanceGame level transition — same quest type for all players that level
- **D-05:** Same 8 quest types and same weight table as daily quests
- **D-06:** Quest type + target stored globally per level (not per player)

### Quest Targets (MECH-02)
- **D-07:** 10x the daily quest target values for each type. No caps — if 10x is expensive, that's intentional
- **D-08:** Edge cases (decimator availability, ETH price sensitivity) should be analyzed but not capped or excluded

### Progress Tracking (MECH-03)
- **D-09:** Per-player progress tracking, completely independent from daily quest progress
- **D-10:** Follow daily quest storage patterns — use version/level-based invalidation at level boundaries

### Completion (MECH-04)
- **D-11:** Once per level per player. 800 BURNIE payout via creditFlip on completion
- **D-12:** Single completion — no slot system like daily quests (just one quest, one completion)

### Storage (STOR-01, STOR-02)
- **D-13:** Follow existing questPlayerState mapping pattern for per-player state
- **D-14:** New global storage for level quest type/target per active level

### Claude's Discretion
- VRF entropy source selection for the level quest roll (use whatever word is available during advanceGame level transition)
- Exact storage packing layout (follow existing bit-packing conventions)
- Level boundary invalidation mechanism (version counter vs level-based check)
- Whether to store quest target as a value or derive from type at evaluation time
- Gas optimization tradeoffs within the spec

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Quest System
- `contracts/DegenerusQuests.sol` — Full daily quest implementation: rolling, eligibility, progress, completion, rewards
- `contracts/interfaces/IDegenerusQuests.sol` — Quest interface definitions

### Storage Patterns
- `contracts/storage/DegenerusGameStorage.sol` — Game storage with mintPacked_, boonPacked, deityPassCount
- `contracts/modules/DegenerusGameMintModule.sol` — mintPacked_ bit layout (levelStreak at bits 48-71, levelUnits at bits 228-243, frozenUntilLevel at bits 128-151, whaleBundleType at bits 152-153)

### Level Transition
- `contracts/modules/DegenerusGameAdvanceModule.sol` — advanceGame level transition logic, VRF entropy consumption

### Payout Mechanism
- `contracts/BurnieCoin.sol` — mintForGame function
- `contracts/BurnieCoinflip.sol` — creditFlip mechanism for quest rewards

### Boon/Pass System
- `contracts/modules/DegenerusGameBoonModule.sol` — Pass activation, boonPacked layout
- `contracts/DegenerusDeityPass.sol` — Deity pass (soulbound NFT, deityPassCount)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `questPlayerState` mapping pattern — per-player quest state with completion masks and progress tracking
- Version-based invalidation — daily quests use version counters to reset progress; adapt for level boundaries
- `creditFlip()` — existing reward payout mechanism used by daily quests
- Weight table and quest type constants — reusable as-is for level quest roll

### Established Patterns
- Bit-packed storage: mintPacked_ (256-bit), questPlayerState (packed per-slot), boonPacked (2 slots)
- VRF entropy derivation: keccak256 of random word + salt for different use cases
- advanceGame level transition already has structured housekeeping sequence

### Integration Points
- advanceGame level transition — where global quest roll would insert
- Quest handleX() functions — where level quest progress tracking would hook in
- creditFlip — existing reward crediting mechanism

</code_context>

<specifics>
## Specific Ideas

- Daily quest targets for reference (from DegenerusQuests.sol):
  - MINT_BURNIE: 1 ticket (1000 BURNIE) → Level quest: 10 tickets (10000 BURNIE)
  - MINT_ETH slot 0: 1x mint price → Level quest: 10x mint price
  - MINT_ETH slot 1: 2x mint price → Level quest: 20x mint price
  - FLIP/DECIMATOR/AFFILIATE: 2000 BURNIE → Level quest: 20000 BURNIE
  - LOOTBOX: 2x mint price → Level quest: 20x mint price
  - DEGENERETTE_ETH: 2x mint price → Level quest: 20x mint price
  - DEGENERETTE_BURNIE: 2000 BURNIE → Level quest: 20000 BURNIE

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 153-core-design*
*Context gathered: 2026-03-31*
