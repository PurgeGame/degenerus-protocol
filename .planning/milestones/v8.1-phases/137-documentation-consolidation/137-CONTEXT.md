# Phase 137: Documentation + Consolidation - Context

**Gathered:** 2026-03-28
**Status:** Ready for planning

<domain>
## Phase Boundary

Update KNOWN-ISSUES.md with post-v8.0 design decisions, finalize C4A contest README (remove DRAFT status), and produce a v8.1 delta findings document. Requirements: DOC-01, DOC-02, DOC-03.

</domain>

<decisions>
## Implementation Decisions

### KNOWN-ISSUES.md Updates (DOC-01)
- **D-01:** Add entries for price feed governance design decisions (already partially present — verify completeness)
- **D-02:** Add entries for boon coexistence behavior (multi-category boons active simultaneously after exclusivity removal)
- **D-03:** Add entries for recycling bonus changes (total claimable vs fresh mintable, rate reduction from 1% to 0.75%)
- **D-04:** Source: Phase 135 consolidated findings (6 INFO findings, all DOCUMENT disposition)

### C4A Contest README (DOC-02)
- **D-05:** Remove DRAFT status from `audit/C4A-CONTEST-README-DRAFT.md`
- **D-06:** Rename to `audit/C4A-CONTEST-README.md` (drop -DRAFT suffix)
- **D-07:** Incorporate post-v8.0 contract changes into the README (price feed governance, boon coexistence, recycling bonus)
- **D-08:** Verify contract list, scope section, and known issues references are current

### Delta Findings Document (DOC-03)
- **D-09:** The consolidated findings document already exists from Phase 135 (`135-03-CONSOLIDATED-FINDINGS.md`). DOC-03 requires it to exist as a v8.1 delta findings deliverable — verify it's complete and copy/reference appropriately.

### Claude's Discretion
- Whether to create a separate v8.1 findings doc or reference the Phase 135 consolidation directly
- KNOWN-ISSUES.md entry format (follow existing patterns in the file)
- C4A README section ordering and depth of change descriptions

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Input Documents
- `.planning/phases/135-delta-adversarial-audit/135-03-CONSOLIDATED-FINDINGS.md` — Master findings from Phase 135 (6 INFO, 0 actionable)
- `.planning/phases/135-delta-adversarial-audit/135-01-ADMIN-GOVERNANCE-AUDIT.md` — DegenerusAdmin governance audit details
- `.planning/phases/135-delta-adversarial-audit/135-02-CHANGED-CONTRACTS-AUDIT.md` — Changed contracts audit details
- `.planning/phases/135-delta-adversarial-audit/135-03-STORAGE-VERIFICATION.md` — Storage layout verification

### Output Documents
- `KNOWN-ISSUES.md` — Known issues registry for C4A wardens
- `audit/C4A-CONTEST-README-DRAFT.md` — C4A contest README (to be finalized)

### Requirements
- `.planning/REQUIREMENTS.md` — DOC-01 through DOC-03

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- KNOWN-ISSUES.md already has 30+ entries with established format (Design Decisions section, Automated Tool Findings section)
- C4A README draft already has structure (About, priorities, Out of Scope, Known Issues, contracts table)

### Established Patterns
- KNOWN-ISSUES.md uses descriptive paragraphs with detector IDs in parentheses
- C4A README uses tables for contract scope and known issues

### Integration Points
- KNOWN-ISSUES.md is referenced by C4A README — updates must be consistent
- Phase 135 findings feed directly into both documents

</code_context>

<specifics>
## Specific Ideas

No specific requirements — follow established document patterns and incorporate Phase 135 findings.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 137-documentation-consolidation*
*Context gathered: 2026-03-28*
