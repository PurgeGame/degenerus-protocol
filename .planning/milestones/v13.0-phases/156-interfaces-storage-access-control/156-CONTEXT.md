# Phase 156: Interfaces, Storage & Access Control - Context

**Gathered:** 2026-03-31
**Status:** Ready for planning

<domain>
## Phase Boundary

All interface files, storage declarations, and access control changes compile cleanly so that downstream quest logic (Phase 157) and handler integration (Phase 158) can build on stable type signatures. No quest logic or handler modifications in this phase.

</domain>

<decisions>
## Implementation Decisions

### Interface Declarations
- **D-01:** IDegenerusQuests.sol gets: `LevelQuestCompleted(address indexed player, uint24 indexed level, uint8 questType, uint256 reward)` event, `rollLevelQuest(uint24 lvl, uint256 entropy)` external function, and `getPlayerLevelQuestView(address player)` view function returning (uint8 questType, uint128 progress, uint256 target, bool completed, bool eligible)
- **D-02:** IDegenerusCoinModule in `DegenerusGameModuleInterfaces.sol` gets `rollLevelQuest(uint24 lvl, uint256 entropy)` external function declaration (mirrors existing rollDailyQuest pattern — no IBurnieCoin.sol needed)

### Storage Declarations
- **D-03:** DegenerusQuests.sol gets two new storage variables appended after `questVersionCounter` (line 277): `mapping(uint24 => uint8) private levelQuestType` first, then `mapping(address => uint256) private levelQuestPlayerState` — mirrors the global-before-per-player ordering of activeQuests/questPlayerState
- **D-04:** levelQuestPlayerState packed layout per Phase 153 spec Section 4: questLevel (24b, bits 0-23) | progress (128b, bits 24-151) | completed (1b, bit 152) | unused (103b, bits 153-255)

### Access Control
- **D-05:** BurnieCoinflip `onlyFlipCreditors` modifier adds `ContractAddresses.QUESTS` as a fifth valid creditor (after existing GAME, COIN, AFFILIATE, ADMIN)
- **D-06:** DegenerusQuests.rollLevelQuest uses existing `onlyCoin` modifier (BurnieCoin is the caller, mirroring rollDailyQuest pattern)

### BurnieCoin Routing Stub
- **D-07:** BurnieCoin.sol gets a `rollLevelQuest(uint24 lvl, uint256 entropy)` function that forwards to `IDegenerusQuests(ContractAddresses.QUESTS).rollLevelQuest(lvl, entropy)` — mirrors rollDailyQuest routing at line 642. Implementation body can be a stub that just forwards; actual quest logic is Phase 157.

### Claude's Discretion
- NatSpec documentation style and detail level for new declarations
- Whether to add the BurnieCoin.rollLevelQuest implementation as a complete forwarding function or a minimal stub
- Exact positioning of new interface declarations within IDegenerusQuests.sol (before/after existing declarations)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Level Quest Design Spec (PRIMARY)
- `.planning/phases/153-core-design/153-01-LEVEL-QUEST-SPEC.md` — Complete design spec: eligibility, mechanics, storage layout (Section 4 packed layout), completion flow
- `.planning/phases/154-integration-mapping/154-01-INTEGRATION-MAP.md` — Contract touchpoint map with exact modification sites and line numbers

### Interface Pattern Reference
- `contracts/interfaces/IDegenerusQuests.sol` — Existing quest interface (lines 42-150): function signatures, structs, events to match style
- `contracts/interfaces/DegenerusGameModuleInterfaces.sol` — IDegenerusCoinModule interface (lines 8-20): where rollLevelQuest declaration goes

### Storage Pattern Reference
- `contracts/DegenerusQuests.sol` lines 268-277 — Existing storage declarations (activeQuests, questPlayerState, questStreakShieldCount, questVersionCounter)
- `contracts/DegenerusQuests.sol` lines 223-261 — DailyQuest and PlayerQuestState struct definitions for style reference

### Access Control Reference
- `contracts/BurnieCoinflip.sol` lines 194-201 — onlyFlipCreditors modifier (current 4 creditors)
- `contracts/BurnieCoin.sol` lines 642-649 — rollDailyQuest forwarding pattern to DegenerusQuests

### Routing Chain Reference
- `contracts/modules/DegenerusGameJackpotModule.sol` line 640 — How JackpotModule calls coin.rollDailyQuest (pattern for AdvanceModule calling coin.rollLevelQuest)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `IDegenerusCoinModule` interface: Add rollLevelQuest alongside existing rollDailyQuest and vaultEscrow
- `onlyCoin` modifier in DegenerusQuests.sol: Reuse for rollLevelQuest access control
- `ContractAddresses.QUESTS` constant: Already exists and is used by BurnieCoin, Game, BurnieCoinflip, etc.
- `rollDailyQuest` forwarding pattern: BurnieCoin.rollDailyQuest → DegenerusQuests.rollDailyQuest (exact template for level quest routing)

### Established Patterns
- Interface declarations in IDegenerusQuests.sol use structs for complex returns (QuestRequirements, QuestInfo, PlayerQuestView)
- Storage variables in DegenerusQuests.sol are private with NatSpec
- BurnieCoinflip creditor check uses explicit address comparisons (no array/mapping)
- Module interfaces are in DegenerusGameModuleInterfaces.sol, not separate IBurnieCoin.sol

### Integration Points
- IDegenerusQuests.sol: Add new event + 2 function signatures
- DegenerusGameModuleInterfaces.sol: Add rollLevelQuest to IDegenerusCoinModule
- DegenerusQuests.sol: Append 2 storage mappings after line 277
- BurnieCoinflip.sol: Add one line to onlyFlipCreditors modifier
- BurnieCoin.sol: Add rollLevelQuest forwarding function

</code_context>

<specifics>
## Specific Ideas

- The rollLevelQuest forwarding in BurnieCoin.sol should be a complete function (not a stub) since it's just a 1-line forward — identical pattern to rollDailyQuest at line 642
- Phase 157 will add the actual quest logic inside DegenerusQuests.rollLevelQuest; Phase 156 just needs the empty function shell with correct signature and access control
- getPlayerLevelQuestView is a read-only view — can have full implementation in Phase 156 since it just reads storage (or can be stubbed with Phase 158 filling in the body)

</specifics>

<deferred>
## Deferred Ideas

None -- discussion stayed within phase scope

</deferred>

---

*Phase: 156-interfaces-storage-access-control*
*Context gathered: 2026-03-31*
