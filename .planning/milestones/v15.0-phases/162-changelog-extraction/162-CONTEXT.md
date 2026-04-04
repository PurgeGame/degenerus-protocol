# Phase 162: Changelog Extraction - Context

**Gathered:** 2026-04-02
**Status:** Ready for planning

<domain>
## Phase Boundary

Catalogue every functional change across v11.0-v14.0 (git range `v10.3..HEAD`) by contract, function, and nature of change (new/modified/removed). Output is a structured changelog document that Phase 165 (adversarial audit) uses as its scope boundary.

</domain>

<decisions>
## Implementation Decisions

### D-01: Git range
The audit scope is `v10.3..HEAD` — everything after the last delta audit (v10.3, shipped 2026-03-30). This covers v11.0, v12.0, v13.0, and v14.0.

### D-02: Scope — contracts/ only
Only `contracts/` directory changes matter. Test files, deploy scripts, and planning docs are out of scope.

### D-03: Output format
Structured markdown organized by contract file. For each contract:
- List of functions: new, modified, or removed
- One-line description of what changed
- Which milestone introduced the change (v11.0/v12.0/v13.0/v14.0)

### D-04: Change classification
- **New**: Function did not exist in v10.3 codebase
- **Modified**: Function existed but signature, body, or behavior changed
- **Removed**: Function existed in v10.3 but no longer exists
- **Storage**: Storage variable added, removed, or repacked
- Changes that are purely comment/NatSpec updates are noted but not audited

### D-05: Extraction method
Use `git diff v10.3..HEAD -- contracts/` for the full diff, then read each changed contract to classify individual function changes. Do NOT rely on commit messages alone — read the actual code diffs.

### Claude's Discretion
- Grouping strategy within each contract (alphabetical vs logical)
- Whether to include line numbers (useful for Phase 165 auditors)
- Whether to flag high-risk changes (functions touching ETH, RNG, access control)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Git range
- `git diff v10.3..HEAD -- contracts/` — the complete diff (21 files, 1337 insertions, 1542 deletions)
- `git log --oneline v10.3..HEAD --no-merges -- contracts/` — 11 commits

### Milestone boundaries
- v11.0: Phases 151-152 (endgame gate)
- v12.0: Phases 153-155 (level quest design — no contract changes)
- v13.0: Phases 156-158.1 (level quest implementation + carryover redesign)
- v14.0: Phases 159-161 (score optimization + purchase path correctness + SLOAD dedup)

</canonical_refs>

<code_context>
## Existing Code Insights

### Changed contracts (21 files)
The full list comes from `git diff --stat v10.3..HEAD -- contracts/`. Key contracts with heavy changes:
- DegenerusGameMintModule.sol — purchase path, score, quest integration, SLOAD dedup
- DegenerusQuests.sol — handlePurchase consolidation, level quest system, quest pricing split
- DegenerusGameAdvanceModule.sol — endgame flag, quest roll, price removal
- DegenerusGameStorage.sol — new storage vars, price removal, packing changes
- BurnieCoin.sol — quest handler rewiring
- DegenerusGameEndgameModule.sol — carryover redesign

</code_context>

<specifics>
## Specific Ideas

No specific requirements — mechanical extraction per git diff.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 162-changelog-extraction*
*Context gathered: 2026-04-02*
