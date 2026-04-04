# Phase 179: Change Surface Inventory - Context

**Gathered:** 2026-04-03
**Status:** Ready for planning

<domain>
## Phase Boundary

Inventory every line changed in `contracts/` since the v15.0 audit baseline (Phase 167, shipped 2026-04-02). Attribute each change to its originating milestone or manual edit. Produce file:line citations and SAFE/INFO/LOW+ verdicts for every added or modified function.

</domain>

<decisions>
## Implementation Decisions

### Diff Strategy
- **D-01:** Use `git diff` from the last commit of v15.0 (Phase 167) to HEAD to capture ALL changes — including GSD-tracked milestones (v16.0, v17.0, v17.1) AND any manual edits or hotfixes
- **D-02:** Organize diff output by contract file, not by milestone — downstream consumers need per-file analysis

### Verdict Format
- **D-03:** Follow existing v15.0 Phase 165 format: function name, file:line citation, verdict (SAFE/INFO/LOW+), one-line rationale
- **D-04:** Attribution column: tag each change with its source (v16.0-repack, v16.0-endgame-delete, v17.0-affiliate-cache, v17.1-comments, rngBypass-refactor, manual)

### Claude's Discretion
- Grouping strategy for the findings document (by contract vs by milestone vs by change type)
- Level of detail in rationale — brief for obvious changes, detailed for security-sensitive ones
- Whether to include unchanged-but-adjacent lines for context in citations

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Prior Audit Baseline
- `.planning/milestones/v15.0-phases/165-per-function-adversarial-audit/165-04-FINDINGS.md` — v15.0 function-level findings (76 SAFE verdicts)
- `.planning/milestones/v15.0-phases/167-integration-test-baseline/167-01-CALL-GRAPH-AUDIT.md` — v15.0 call graph

### Change Sources
- `.planning/milestones/v16.0-phases/168-storage-repack/` — Storage repack changes
- `.planning/milestones/v16.0-phases/170-migrate-runRewardJackpots/` — runRewardJackpots migration
- `.planning/milestones/v16.0-phases/171-delete-endgamemodule/` — EndgameModule deletion
- `.planning/milestones/v17.0-phases/173-implementation/` — Affiliate bonus cache

### Current Requirements
- `.planning/REQUIREMENTS.md` — DELTA-01 and DELTA-05 define this phase's deliverables

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `forge inspect DegenerusGame storage-layout` — verified storage layout tool used in prior milestones
- Prior findings format from v15.0 Phase 165 — reuse same table structure for consistency

### Established Patterns
- Verdicts use SAFE/INFO/LOW/MEDIUM/HIGH severity scale
- File:line citations use `ContractName.sol:NNN` format
- Attribution uses milestone version tags (v16.0, v17.0, etc.)

### Integration Points
- Git history between v15.0 final commit and HEAD contains all changes
- `contracts/` directory is the audit scope — exclude test/, scripts/, .planning/

</code_context>

<specifics>
## Specific Ideas

- The rngBypass refactor (this session) touched 9 contract files — ensure all are captured
- ContractAddresses.sol was modified by patchForFoundry.js — the production version is in git, the test version is generated
- v17.1 was comment-only changes — these should be tagged but don't need security verdicts

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 179-change-surface-inventory*
*Context gathered: 2026-04-03*
