# Phase 163: Level System Documentation - Context

**Gathered:** 2026-04-02
**Status:** Ready for planning

<domain>
## Phase Boundary

Produce a complete reference document covering how the level system works end-to-end: level advancement, price derivation, purchaseLevel semantics, quest target calculation, lootbox baseline, and jackpot ticket routing. The document must be accurate against current code (post-v14.0) so Phase 165 auditors can trace any level-dependent behavior without reading contract source.

</domain>

<decisions>
## Implementation Decisions

### D-01: Output format
Single reference document at `.planning/phases/163-level-system-documentation/163-LEVEL-SYSTEM.md`. Organized by subsystem with cross-references between sections.

### D-02: Sections required
1. **Level advancement** — what triggers `level` to increment (advanceGame in AdvanceModule), state transitions, who can call it
2. **Price derivation** — PriceLookupLib.priceForLevel pure function, tier table, how it replaces the old price storage variable
3. **purchaseLevel semantics** — `jackpotPhaseFlag ? level : level + 1`, when each phase applies, how it affects ticket routing
4. **Quest target calculation** — daily quest targets use `priceForLevel(purchaseLevel)`, level quest targets use `priceForLevel(level + 1)`, multipliers per quest type
5. **Lootbox baseline** — always `level + 1` regardless of jackpot phase, lootboxBaseLevelPacked, lootboxEth packing
6. **Jackpot ticket routing** — normal vs jackpot phase routing, last-day override, far-future key space, carryover tickets

### D-03: Source of truth
Read current contract code directly — NOT git history or phase summaries. The document must reflect what the code says NOW, not what changed.

### D-04: Code references
Include specific function names, line ranges, and contract paths so auditors can verify claims against source.

### Claude's Discretion
- Diagrams or flowcharts (text-based if included)
- Cross-reference format between sections
- Whether to include worked examples (e.g., "at level 5 during jackpot phase, purchaseLevel=5, price=0.02 ETH...")

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Core contracts to read
- `contracts/modules/DegenerusGameAdvanceModule.sol` — level advancement, advanceGame
- `contracts/modules/DegenerusGameMintModule.sol` — purchaseLevel, _purchaseFor, _callTicketPurchase, lootbox block
- `contracts/libraries/PriceLookupLib.sol` — price-for-level pure function
- `contracts/DegenerusQuests.sol` — handlePurchase, quest target calculation, level quest vs daily quest pricing
- `contracts/storage/DegenerusGameStorage.sol` — level variable, jackpotPhaseFlag, slot layout
- `contracts/modules/DegenerusGameJackpotModule.sol` — jackpot ticket routing, carryover

### Phase 162 changelog
- `.planning/phases/162-changelog-extraction/162-CHANGELOG.md` — complete list of what changed, useful for identifying all level-related touchpoints

</canonical_refs>

<code_context>
## Existing Code Insights

### Key variables
- `level` (Slot 0, uint24) — only written in AdvanceModule.advanceGame
- `jackpotPhaseFlag` (Slot 0, bool) — determines purchase vs jackpot phase
- `purchaseLevel` — local in _purchaseFor: `jackpotPhaseFlag ? level : level + 1`

### Key functions
- `PriceLookupLib.priceForLevel(uint24)` — pure, returns price in wei for any level
- `_purchaseFor` — main purchase path, sets purchaseLevel, splits price for quests
- `handlePurchase` — 6 params including mintPrice + levelQuestPrice
- `_levelQuestTargetValue` — 10x multipliers using levelQuestPrice

</code_context>

<specifics>
## Specific Ideas

User specifically asked for "a full description of how the level relates to price and quest completion and such" — this is the primary deliverable.

</specifics>

<deferred>
## Deferred Ideas

None — documentation phase, self-contained scope

</deferred>

---

*Phase: 163-level-system-documentation*
*Context gathered: 2026-04-02*
