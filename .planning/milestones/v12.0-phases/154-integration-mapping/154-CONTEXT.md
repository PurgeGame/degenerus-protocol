# Phase 154: Integration Mapping - Context

**Gathered:** 2026-04-01
**Status:** Ready for planning

<domain>
## Phase Boundary

Identify every contract and function that must change for level quests, with exact modification scope. Output is an integration map document — no Solidity implementation.

</domain>

<decisions>
## Implementation Decisions

### Contract Touchpoints (INTG-01)
- **D-01:** Map every contract that needs modification based on the Phase 153 spec (153-01-LEVEL-QUEST-SPEC.md)
- **D-02:** Document interface changes (new functions, modified signatures, new errors/events)
- **D-03:** Document new cross-contract calls introduced by level quests

### Handler Site Identification (INTG-02)
- **D-04:** List every handleX() call site in DegenerusQuests.sol that needs level quest progress tracking
- **D-05:** For each handler, specify what level quest progress tracking logic must be added (based on quest type → progress contribution mapping from Phase 153 spec)

### Claude's Discretion
- Grouping and organization of the integration map
- Whether to include line-number references (recommended for precision)
- Level of detail in modification scope descriptions

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 153 Spec (PRIMARY INPUT)
- `.planning/phases/153-core-design/153-01-LEVEL-QUEST-SPEC.md` — Complete level quest design spec (eligibility, mechanics, storage, completion flow)

### Contracts to Map
- `contracts/DegenerusQuests.sol` — All handleX() functions, daily quest roll, completion logic
- `contracts/interfaces/IDegenerusQuests.sol` — Quest interface
- `contracts/storage/DegenerusGameStorage.sol` — Storage declarations
- `contracts/modules/DegenerusGameAdvanceModule.sol` — Level transition (quest roll insertion point)
- `contracts/modules/DegenerusGameMintModule.sol` — Mint handlers that trigger quest progress
- `contracts/modules/DegenerusGameLootboxModule.sol` — Lootbox handlers
- `contracts/modules/DegenerusGameBoonModule.sol` — Pass detection
- `contracts/BurnieCoinflip.sol` — creditFlip for rewards
- `contracts/BurnieCoin.sol` — Mint/burn paths
- `contracts/DegenerusDegenerette.sol` — Degenerette bet handlers

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- Phase 153 spec already identifies the key integration points — this phase is mechanical mapping

### Established Patterns
- handleX() functions in DegenerusQuests.sol follow a consistent pattern: receive action data, update progress, check completion
- Cross-contract calls use interface-based addressing via ContractAddresses

### Integration Points
- advanceGame level transition → quest roll insertion
- Every game action that contributes to quest progress → handleX() sites

</code_context>

<specifics>
## Specific Ideas

No specific requirements — mechanical mapping from Phase 153 spec to contract code.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 154-integration-mapping*
*Context gathered: 2026-04-01*
