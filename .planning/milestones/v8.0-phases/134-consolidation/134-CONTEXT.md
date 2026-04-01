# Phase 134: Consolidation - Context

**Gathered:** 2026-03-27
**Status:** Ready for planning

<domain>
## Phase Boundary

All bot-race, ERC-20, event, and comment findings from Phases 130-133 are either fixed in code or comprehensively documented in KNOWN-ISSUES.md so wardens cannot file them. Produce a v8.0 findings summary and draft the C4A contest README scoping language.

</domain>

<decisions>
## Implementation Decisions

### KNOWN-ISSUES.md Structure
- **D-01:** Organize by severity/category, not by audit source. Keep existing 2 sections (Intentional Design, Design Mechanics) and add new sections: "Automated Tool Findings (Pre-disclosed)", "ERC-20 Deviations", "Event Design Decisions".
- **D-02:** 2-3 sentences per entry. Title + explanation of what the tool flags and why it's intentional. Enough to invalidate a warden filing, not a novel.
- **D-03:** Include Slither/4naly3er detector IDs in each entry (e.g., `arbitrary-send-eth`, `[M-2]`) so wardens can map their own tool output instantly.

### Fix-vs-Document Triage
- **D-04:** DOC-03 (dead code `_lootboxBpsToTier`) — FIX. Delete the unused function. One clean removal.
- **D-05:** GAS-10 (10 constructor-only variables not `immutable`) — MANUAL REVIEW. List all 10 candidates with locations for user approval/rejection before any code changes.
- **D-06:** Everything else stays DOCUMENT. No other code changes.

### Summary Format
- **D-07:** Full v8.0 findings summary in `audit/v8.0-findings-summary.md` (follows v5.0/v7.0 pattern). Counts by category (bot/ERC/event/comment), disposition breakdown (fixed/documented/FP), cross-references to phase artifacts.
- **D-08:** Brief stats line at top of KNOWN-ISSUES.md for warden context (e.g., "Pre-audited with Slither + 4naly3er. N categories triaged, M documented below.").

### C4A Contest README
- **D-09:** Draft C4A contest README "out of scope" section in Phase 134. Core message: "I care about three things — RNG integrity, gas ceiling safety, and money correctness. Everything else is noise."
- **D-10:** Explicitly scope out: non-financial-impact findings (gas optimization, code style, NatSpec quality, naming), known automated tool findings (reference KNOWN-ISSUES.md), deployment/infrastructure (scripts, off-chain VRF, frontend), formal verification gaps (deferred items tracked separately).
- **D-11:** Tone should be direct and concise — solo developer who cares about correctness, not code beauty. Gets the point across without corporate padding.

### Claude's Discretion
- Grouping/deduplication of overlapping findings (e.g., M-5/M-6/L-19 all cover the same "no SafeERC20" pattern)
- Whether to merge L-13/L-14 (rounding/precision) into the existing KNOWN-ISSUES stETH entry or keep separate
- Exact wording of C4A README scoping language
- How to handle the 1,054 GAS-7 (unchecked arithmetic) instances — likely a single grouped entry

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 130 Outputs (Bot Race)
- `audit/bot-race/slither-triage.md` — 5 DOCUMENT findings (DOC-01 through DOC-05), 27 FP categories
- `audit/bot-race/4naly3er-triage.md` — 22 DOCUMENT categories, 57 FP categories, cross-reference notes for Phase 132/133/134
- `KNOWN-ISSUES.md` — Current known issues (5 entries, needs expansion)

### Phase 131 Outputs (ERC-20 Compliance)
- `audit/erc-20-compliance.md` — Per-token compliance report with 5 ready-to-paste KNOWN-ISSUES entries for DGNRS+BURNIE deviations

### Phase 132 Outputs (Event Correctness)
- `audit/event-correctness.md` — 30 INFO findings (all DOCUMENT), 108 bot instances mapped with dispositions

### Phase 133 Outputs (Comment Re-scan)
- `audit/comment-rescan-summary.md` — Summary of fixes applied, bot-race appendix with 116 NC instance dispositions (72 FIXED, 12 JUSTIFIED, 32 FP)

### Target Files
- `KNOWN-ISSUES.md` — Primary consolidation target
- `audit/v8.0-findings-summary.md` — New: v8.0 findings summary
- `audit/EXTERNAL-AUDIT-PROMPT.md` — May need updating or replacement with C4A README draft

### Requirements
- `.planning/REQUIREMENTS.md` — BOT-03, BOT-04 definitions (the two remaining requirements)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- Existing KNOWN-ISSUES.md structure (Intentional Design + Design Mechanics sections) — extend, don't replace
- All four phase audit documents already have findings with full reasoning — harvest and condense
- `audit/EXTERNAL-AUDIT-PROMPT.md` — existing external audit prompt that may serve as template for C4A README

### Established Patterns
- Phase 130 triage docs use consistent format: detector ID, severity, instances, locations, reasoning
- Phase 131 ERC-20 report has ready-to-paste entries
- Phase 132/133 have appendix sections that close out bot-race handoff loops

### Integration Points
- KNOWN-ISSUES.md at repo root — the warden-facing deliverable
- audit/ directory — internal reference documents
- C4A contest README — new deliverable, draft only (user will finalize)

### Dead Code to Remove
- `DegenerusGameStorage._lootboxBpsToTier(uint16)` at DegenerusGameStorage.sol L1570-1575 — unused since v3.8 boon simplification

</code_context>

<specifics>
## Specific Ideas

- User's core philosophy for C4A: "I care about three things — RNG integrity, gas ceiling safety, and money correctness. Everything else is noise." This should permeate both KNOWN-ISSUES.md framing and the contest README.
- User is a solo amateur developer releasing code publicly for the first time — the README tone should be honest and direct, not corporate
- Detector IDs in KNOWN-ISSUES entries serve a specific purpose: wardens will run Slither/4naly3er on day 1 and ctrl+F the output against known issues
- GAS-10 immutable candidates need manual review — present a table of all 10 for the user to approve/reject before touching any code

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 134-consolidation*
*Context gathered: 2026-03-27*
