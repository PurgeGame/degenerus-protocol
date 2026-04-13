---
phase: 223-findings-consolidation
milestone: v27.0
created: 2026-04-13
status: discussed
---

# Phase 223: Findings Consolidation — Context

**Phase goal (from ROADMAP):** All v27.0 audit findings are severity-classified and rolled up into `audit/FINDINGS-v27.0.md`; design-decision items are promoted to `KNOWN-ISSUES.md`; v27.0 is marked SHIPPED.

**Requirements:** CSI-12 (FINDINGS-v27.0.md), CSI-13 (KNOWN-ISSUES.md), CSI-14 (MILESTONES.md + PROJECT.md)

**Depends on:** Phases 220, 221, 222 (all complete and verified).

---

## Prior Context (Not Re-Discussed)

### From PROJECT.md and MILESTONES.md
- **v27.0 theme:** Call-Site Integrity Audit — extends the lessons from the mintPackedFor incident (interface declared, no impl, silent staticcall revert). Three phases covered three axes of call-site integrity: delegatecall alignment (220), raw selector safety (221), external-function classification coverage (222).
- **Prior audit cycle templates:** v25.0 established the `FINDINGS-v<milestone>.md` structure (Executive Summary severity table, per-phase finding subsections with field tables, regression appendix). v26.0 shipped without a separate findings doc (2 phases / 4 plans / design-focused).
- **MILESTONES.md format:** `## v<N>.<M> <Title> (Shipped: <date>)` + "Phases completed: N phases, M plans, K tasks" + "Key accomplishments:" bulleted narrative.

### From phase 220-222 verifications
- **Phase 220 (passed 9/9):** 220-REVIEW.md has 3 Warnings (WR-220-01 CONTRACTS_DIR trailing-slash filter bypass, WR-220-02 mapping preflight scope, WR-220-03 10-line window fragility) + 5 Info items.
- **Phase 221 (passed 13/13):** 221-REVIEW.md has 2 Warnings — **both RESOLVED in-cycle** (WR-221-01 CONTRACTS_DIR error handling, WR-221-02 warn_total increment) + 3 Info items.
- **Phase 222 (resolved 4/4):** 222-REVIEW.md has 4 Warnings — **WR-222-02/03/04 RESOLVED in-cycle by Plan 222-03** (test quality, drift scoping, tautological assertion), WR-222-01 remains open (patchContractAddresses.js VRF_KEY_HASH regex — deployment-pipeline robustness, not runtime risk) + 6 Info items.
- **222-VERIFICATION.md Gap 1 (CSI-11 test quality) + Gap 2 (CSI-10 drift scoping):** both `status: resolved` by Plan 222-03 (commits ef83c5cd, e0a1aa3e). Audit-trail note to appear in FINDINGS.

### Prior findings corpus (for regression appendix)
- **v25.0 `audit/FINDINGS-v25.0.md`:** 13 INFO findings F-25-01 .. F-25-13 (plus v25.0 regression appendix covering v5.0's F-* + I-* series).
- **v26.0:** no separate findings doc; accomplishments documented in MILESTONES.md only.

### From memory
- `feedback_no_contract_commits.md` — contracts/ and test/ edits require explicit user approval. FINDINGS/KNOWN-ISSUES are docs under `audit/` and `KNOWN-ISSUES.md` — unblocked.
- `feedback_no_history_in_comments.md` — doc prose describes what IS; source artifact sections (plan/phase references) are acceptable because they're explicit traceability, not history narration.

---

## Decisions (What Is Locked)

### D-01: Finding-naming convention → `F-27-NN`
Mirrors v25.0's `F-25-NN` pattern. Single monotonic numbering across all three phases (220/221/222), grouped in subsections by source phase. No per-phase prefix (keeps finding IDs short enough for cross-references and tables).

### D-02: Inclusion scope → **All warnings + all info items** (comprehensive)
**Decision:** Every WR-* and IN-* item in the three REVIEW.md files becomes a formal F-27-NN finding. Expected count: ~15 findings (3 + 5 + 2 + 3 + 4 + 6 = 23 raw items across three phases, de-duped and consolidated where two reviews describe the same underlying observation — target ~15 unique findings after normalization).

**Why:** Mirrors v25.0's inclusive audit pattern (13 INFO = every phase-level observation documented). External auditors benefit from seeing every reviewer observation with verdict classification, even when resolved in-cycle.

**How to apply (for downstream agents):**
- Phase 220 items → subsection `### Phase 220: Delegatecall Target Alignment (N findings)`
- Phase 221 items → subsection `### Phase 221: Raw Selector & Calldata Audit (N findings)`
- Phase 222 items → subsection `### Phase 222: External Function Coverage Gap (N findings)`
- Duplicate observations (same underlying issue recorded in two REVIEW.md files) → single finding with both source citations.

### D-03: Resolved-in-cycle items → include with explicit status
**Decision:** Warnings and info items that were fixed during v27.0 (WR-221-01, WR-221-02, WR-222-02, WR-222-03, WR-222-04, and the two VERIFICATION gaps) appear as formal findings with `**Status:** Resolved in v27.0 (commit <sha>)` in their field table.

**Why:** Audit trail — external reviewers can trace the closure of every identified issue. Matches the v25.0 pattern where `INFO` items include both observations and documented design decisions.

**How to apply:** Use the severity-justification field to cite the resolving commit sha. For gap-closure cases (222-03 commits ef83c5cd and e0a1aa3e), reference both the in-cycle resolution and the VERIFICATION re-check at 4/4.

### D-04: Severity mapping for items across phases
**Decision:** All v27.0 findings are expected to be **INFO** unless an explicit code-correctness issue (not style/robustness) is identified during consolidation. Target severity distribution: 0 CRITICAL / 0 HIGH / 0 MEDIUM / 0-1 LOW / ~14-15 INFO.

**Why:** The three source phases produced zero VULNERABLE verdicts. Every WR-* and IN-* item is either a script/test quality observation (resolved or acceptable trade-off) or a deployment-tooling robustness note. None represents a runtime security or correctness risk on production contracts.

**How to apply:** Default severity for every WR-*/IN-* = INFO. If the consolidator discovers a specific finding that represents a real bug risk (e.g., an open WR affecting a deployment/CI path with concrete production impact), escalate to LOW and document the reasoning in the severity-justification field.

### D-05: Regression appendix → verify v25.0 findings still hold
**Decision:** Include a `## Regression Appendix` section verifying all 13 v25.0 findings (F-25-01 .. F-25-13) against the current codebase. For each, record: `HOLDS` (still applies as-is) / `SUPERSEDED` (code path restructured but conclusion stands) / `FIXED` (code change made the finding moot) / `INVALIDATED` (changed circumstances invalidate the INFO-level observation).

**Why:** v25.0 set the precedent — its regression appendix verified v5.0's F-* + I-* series. Continuing the chain provides cycle-over-cycle auditor confidence and catches regressions introduced by v26.0/v27.0 work.

**How to apply:** Walk each F-25-NN systematically. For findings about modules/files that didn't change between v25.0 → v27.0 (grep the commit log for files touched by 217+ commits), expected result is `HOLDS` with a one-line git-history pointer. For findings on code that did change, verify the underlying assertion manually.

### D-06: No v26.0 regression appendix needed
**Decision:** v26.0 did not produce a separate FINDINGS-v26.0.md doc — its 2 phases were design-focused (bonus jackpot split mechanism) and MILESTONES.md captures its accomplishments. No prior findings to regression-check.

**Why:** v26.0's scope was intentionally narrow (bonus split implementation); the audit cycle producing formal findings resumed with v27.0's Call-Site Integrity work.

**How to apply:** Regression appendix covers only v25.0. Note this explicitly in the appendix preamble so future auditors don't wonder about the gap.

### D-07: v27.0 scope framing
**Decision:** `audit/FINDINGS-v27.0.md` header states: *"Call-site integrity audit covering three axes — delegatecall target alignment (Phase 220), raw selector and hand-rolled calldata safety (Phase 221), external function classification coverage (Phase 222). Scope: post-v26.0 delta; the v25.0 Master Delta Report (`audit/FINDINGS-v25.0.md`) and the v5.0 baseline (`audit/FINDINGS.md`) remain prior references."*

**Why:** Mirrors v25.0's explicit-scope statement. Distinguishes "call-site integrity" (audit theme) from the prior "adversarial/RNG/pool" (v25.0) and "bonus jackpot" (v26.0) themes.

### D-08: KNOWN-ISSUES.md promotion criteria
**Decision:** Promote an F-27-NN item to KNOWN-ISSUES.md if ALL of the following hold:
1. Severity is INFO or LOW.
2. The item is a **design decision** or **accepted trade-off** (not a bug awaiting fix).
3. An external user or auditor reading only KNOWN-ISSUES.md would benefit from the context.

**Why:** Keeps KNOWN-ISSUES.md a forward-facing "design intent" doc rather than a bug backlog. v25.0 promoted 3 design-decision items — the pattern continues.

**How to apply:** Expected promotion candidates from v27.0: WR-222-01 (deployment-tooling robustness accepted as non-runtime risk), any IN-* item documenting a deliberate script trade-off (e.g., IN-220-02 `set -o pipefail` interaction), and the two VERIFICATION gaps resolved in-cycle (summary-form only, full detail in FINDINGS).

### D-09: MILESTONES.md v27.0 entry format
**Decision:** Mirror v26.0's format (top-level `## v27.0 Call-Site Integrity Audit (Shipped: 2026-04-13)`, "Phases completed:" count, "Key accomplishments:" bulleted narrative). Expected totals: 4 phases (220, 221, 222, 223), 7 plans, ~15 tasks.

**Why:** Consistency with the milestone retrospective pattern already established through v16.0, v24.1, v25.0, v26.0 entries.

**How to apply:** Derive counts from ROADMAP.md completion table + phase SUMMARY.md files. Plan 222-03 counts as one plan. Bulleted accomplishments should emphasize: interface-coverage gate, delegatecall alignment gate, raw-selector gate, external-function classification matrix, coverage-check.sh gate, and test-quality improvements.

### D-10: PROJECT.md v27.0 update
**Decision:** Move "Current Milestone" from v27.0 to whatever the next roadmap cycle is (check ROADMAP.md next-milestone section; if none defined, leave "Current Milestone" empty with a `TBD — pending roadmap planning` note). Add `v27.0 Call-Site Integrity Audit` to the "Completed Milestone" list with one-line summary matching the MILESTONES.md entry.

**Why:** Required by success criterion 4 (CSI-14).

---

## Deferred Ideas

*(Capture any scope-creep ideas for later cycles — don't act on them in Phase 223)*

- **External-auditor prompt doc for v27.0** — similar to `audit/EXTERNAL-AUDIT-PROMPT.md` from prior cycles. Useful for C4A or external review engagement. Defer to separate backlog item.
- **v27.1 follow-up for WR-222-01** — the patchContractAddresses.js VRF_KEY_HASH regex fix is a deployment-pipeline cleanup. If it remains INFO in this cycle, consider a minor v27.1 to land the fix cleanly.
- **Coverage-matrix snapshot automation** — auto-refresh `222-01-COVERAGE-MATRIX.md` each milestone so the drift-check has current ground truth. Defer to v28.0+ roadmap discussion.

---

## Non-Decisions (Claude's Discretion)

The following implementation details are **not locked** — researcher and planner can choose the best approach:

- Exact wording of each F-27-NN finding narrative (beyond the field-table schema from v25.0).
- How to group or order findings within each phase subsection (severity-first, source-line-first, or topical).
- Whether to include code snippets inline in FINDINGS (v25.0 was text-only; v27.0 may follow or selectively embed where context helps).
- Whether the regression appendix uses a tabular summary or per-finding prose (v25.0 used per-finding prose).
- Exact bullet phrasing for MILESTONES.md (as long as format/length matches v26.0).

---

## Handoff to Research / Planning

- **Researcher scope:** No technical research required — this phase is pure documentation consolidation. If the planner determines a research pass is useful, it would be limited to verifying v25.0 regression-appendix conclusions against current code (i.e., reading the contracts and confirming F-25-NN observations still hold). Research for Phase 223 is likely skippable; proceed directly to planning.
- **Planner scope:** Produce 2-3 plans (suggested breakdown):
  - **Plan 223-01 — FINDINGS-v27.0.md authoring:** Read all three REVIEW.md files + VERIFICATION.md files + relevant AUDIT.md catalogs. Produce 15 F-27-NN findings in v25.0 structure. Include regression appendix verifying F-25-01 .. F-25-13.
  - **Plan 223-02 — KNOWN-ISSUES.md + MILESTONES.md + PROJECT.md updates:** Promote per-D-08 criteria to KNOWN-ISSUES. Write MILESTONES v27.0 entry per D-09. Move v27.0 in PROJECT.md per D-10.
- **Commit boundaries:** Each plan = one commit (pure docs, atomic). No contract edits.
- **Success gate:** All 4 ROADMAP success criteria pass + CSI-12/13/14 checkboxes flipped to `[x]`.

_Discussed: 2026-04-13_
_Discussant: Claude (via /gsd-discuss-phase)_
