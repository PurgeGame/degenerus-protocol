# Phase 133: Comment Re-scan - Context

**Gathered:** 2026-03-27
**Status:** Ready for planning

<domain>
## Phase Boundary

Delta NatSpec and inline comment sweep across all production contracts and interfaces changed since v3.5. FIX all comment issues directly in contract code. Verify zero stale references to removed/renamed entities across the production+interface codebase. Close out the 116 bot-race comment instances routed from Phase 130.

</domain>

<decisions>
## Implementation Decisions

### Fix vs Document Policy
- **D-01:** FIX all comment issues directly in contract code. Unlike Phases 130-132 which were DOCUMENT-only, comments are zero-risk to contract behavior and incorrect/stale comments actively mislead auditors.
- **D-02:** Fix scope includes: wrong @param/@return names, stale NatSpec referencing deleted/renamed entities, incorrect inline comments describing outdated logic, missing NatSpec on public/external functions, and magic number documentation.

### Scope Boundary
- **D-03:** Production contracts + interfaces, skip mocks. Wardens read interfaces but not mocks.
- **D-04:** CMT-01 and CMT-02 are delta-scoped: only contracts changed since v3.5 tag.
- **D-05:** CMT-03 (stale references) is a full sweep of all production .sol files + interfaces for references to removed/renamed functions, variables, or constants. This catches cross-file staleness.
- **D-06:** GNRUS.sol is in scope (new in v6.0, post-v3.5).

### Output Format
- **D-07:** Commit-per-contract (or small batch) with descriptive commit messages. The fixes ARE the deliverable.
- **D-08:** Lightweight summary document (`audit/comment-rescan-summary.md`) listing what was fixed per contract — Phase 134 reference, not a full audit doc.
- **D-09:** Bot-race appendix section in the summary mapping all 116 routed instances (NC-18/19/20/34) to dispositions (FIXED or rationale for not fixing).

### Claude's Discretion
- Grouping strategy for commits (per-contract vs batching small files)
- Whether to add NatSpec to functions the bot flagged but that are arguably self-documenting
- Magic number handling — add named constants vs add inline comments

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Bot-Race Findings (Phase 130 handoff)
- `audit/bot-race/4naly3er-triage.md` — Lines 426-430: four NC categories routed to Phase 133 (NC-18: 83, NC-19: 19, NC-20: 6, NC-34: 8, ~116 instances)
- `audit/bot-race/4naly3er-report.md` — Raw 4naly3er output with per-instance locations

### Prior Comment Sweeps (baseline)
- v3.5 Phase 54: Full 46-file comment sweep (26 findings: 7 LOW, 19 INFO)
- v3.2 Phase 39-41: Comment scan of game modules, core + token, peripheral
- v6.0/v7.0: Delta sweeps of changed contracts

### Contract Scope
- `contracts/*.sol` — Top-level production contracts (exclude mocks/)
- `contracts/modules/*.sol` — Game modules
- `contracts/storage/*.sol` — Shared storage
- `contracts/libraries/*.sol` — Libraries
- `contracts/interfaces/*.sol` — Interfaces (in scope for stale reference sweep)
- Git tag `v3.5` — Baseline for delta detection

### Requirements
- `.planning/REQUIREMENTS.md` — CMT-01, CMT-02, CMT-03 definitions

</canonical_refs>

<code_context>
## Existing Code Insights

### Delta Since v3.5
- ~30 production contracts + modules changed since v3.5 tag
- Major changes in v6.0: DegenerusCharity (GNRUS), game hooks, storage fixes, test cleanup
- Major changes in v7.0: Delta audit fixes (no new contracts, minor corrections)
- v4.0-v4.4: Ticket lifecycle, jackpot chunk removal, BAF cache-overwrite fix

### NatSpec Patterns
- Protocol uses `+===...===+` box-drawing decorators for section headers
- Bit allocation maps documented via inline NatSpec in storage contracts
- Some internal helpers intentionally omit NatSpec when self-documenting

### Integration Points
- Fixes committed directly to contract files
- Summary output: `audit/comment-rescan-summary.md`
- Bot-race appendix closes the Phase 130 handoff for comment findings
- Feeds into Phase 134 KNOWN-ISSUES.md consolidation

</code_context>

<specifics>
## Specific Ideas

- Since we're FIXING not documenting, the commit history is the primary deliverable — Phase 134 reads git log to see what changed
- The lightweight summary exists for quick Phase 134 reference, not as an audit artifact
- Full stale-reference grep catches things like interface comments pointing to renamed production functions

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 133-comment-re-scan*
*Context gathered: 2026-03-27*
