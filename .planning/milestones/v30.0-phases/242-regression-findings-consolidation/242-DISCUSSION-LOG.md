# Phase 242: Regression + Findings Consolidation - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-19
**Phase:** 242-regression-findings-consolidation
**Areas discussed:** Plan split (only)
**Areas deferred to Claude's Discretion:** Severity rubric, Per-consumer table granularity, Regression layout

---

## Gray Area Selection

| Option | Description | Selected |
|--------|-------------|----------|
| Severity rubric | How to map findings to CRITICAL/HIGH/MEDIUM/LOW/INFO (SC-1 mandates 5 buckets, no rubric exists yet). 17 candidates from Phase 237 are all currently flagged INFO — keep as-is or re-evaluate against an exploitability-frame rubric (D-05 from 241)? | |
| Plan split | ROADMAP suggests 2 plans (Plan 01 = forward consolidation; Plan 02 = regression + KI promotions). Phase 241 chose single-consolidated. Phase 242 has 5 requirements (REG-01/02 + FIND-01/02/03) and crosses 4 prior milestones — confirm 2-plan split or go single-consolidated. | ✓ |
| Per-consumer table | SC-1 mandates a per-consumer proof table covering INV+BWD+FWD+RNG+GO. Granularity choice: 146-row INV-keyed (1 row per consumer × 4 verdict columns from 238/239/240) — wide & dense; or row-per-finding (sparse, only EXCEPTION rows expanded)? | |
| Regression layout | REG-01 (v29.0 F-29-03/F-29-04 = 2 finding subjects) + REG-02 (29 v25.0/v3.7/v3.8 rngLocked rows). Organize the regression appendix: by milestone (oldest first), by topic family (rngLocked / VRF-path / commitment-window / stall), or chronological-then-topic hybrid? | |

**User's choice:** Plan split (single area selected for deep discussion)
**Notes:** Other 3 areas resolved at Claude's Discretion in CONTEXT.md (D-08 severity rubric / D-10 per-consumer table / D-12 regression layout) with rationale tied to ROADMAP literals and Phase 237-241 precedent.

---

## Plan split

### Q1 — How many plans for Phase 242?

| Option | Description | Selected |
|--------|-------------|----------|
| 2 plans (ROADMAP default) | Plan 01 = forward consolidation (FIND-01 exec summary + per-consumer proof table + gameover section + F-30-NN blocks). Plan 02 = backward + KI (REG-01 + REG-02 regression appendix + FIND-02 attach + FIND-03 KI promotions). Matches 236-01/236-02 and 217-01/217-02 precedent ROADMAP cites. | |
| 1 plan (Phase 241 pattern) | Single consolidated plan with all 5 requirements as sequential tasks. Matches Phase 241 D-01 single-plan justification. Risks: larger context budget, no clean checkpoint between forward & backward streams, harder to parallelize. | ✓ |
| 3 plans (max separation) | Plan 01 = FIND-01 forward consolidation. Plan 02 = REG-01 + REG-02 regression appendix only. Plan 03 = FIND-03 KI promotions (touches `KNOWN-ISSUES.md` — only Phase 242 plan that writes outside `audit/`). Tightest scope-isolation; KI write is the only non-`audit/` write across the whole milestone. | |

**User's choice:** 1 plan (Phase 241 pattern)
**Notes:** Captured as D-01. Single-plan rationale: the 5 requirements all consolidate into the same single deliverable file — 2-plan split would create cross-plan file-merge coordination risk without parallelization gain. Matches Phase 241 D-01 narrow-scope precedent. ROADMAP "expected 2 plans" hint explicitly overridden.

### Q2 — Output file shape — single canonical file or per-plan intermediates?

| Option | Description | Selected |
|--------|-------------|----------|
| Single file only (Phase 241 pattern) | Each plan writes directly into `audit/FINDINGS-v30.0.md` (Plan 01 creates skeleton + forward sections; Plan 02 appends regression appendix + KI cross-refs). No intermediates. Matches ROADMAP SC-1 literal naming. Risk: cross-plan file-merge coordination. | ✓ |
| Per-plan intermediates + final consolidation (Phase 237/238/240 pattern) | Plan 01 writes `audit/v30-242-01-FINDINGS-FORWARD.md`; Plan 02 writes `audit/v30-242-02-REGRESSION.md` (+ KI promotions to `KNOWN-ISSUES.md` if 3-plan); a final consolidation task assembles `audit/FINDINGS-v30.0.md`. Cleaner plan boundaries, audit-trail of intermediate state. Risk: 4 audit files vs 1. | |

**User's choice:** Single file only (Phase 241 pattern)
**Notes:** Captured as D-02. Combined with Q1 (1 plan), the cross-plan file-merge risk dissolves — single plan + single file = single writer. Matches ROADMAP SC-1 literal naming `audit/FINDINGS-v30.0.md`. No per-task intermediates either (D-21).

### Q3 — Within the regression stream — REG-01 (2 v29.0 findings) and REG-02 (29 v25.0/v3.7/v3.8 rows) — same plan or separate?

| Option | Description | Selected |
|--------|-------------|----------|
| Same plan/task pairing | Regression is one stream regardless of source milestone; verdict taxonomy (PASS/REGRESSED/SUPERSEDED) is identical; REG-01 + REG-02 share one regression appendix in the deliverable. Lighter overhead. | ✓ |
| Separate tasks within same plan | REG-01 = 1 task (v29.0 F-29-03/F-29-04, the most recent prior milestone, contract tree byte-identical). REG-02 = 1 task (older milestones; needs more cross-milestone artifact reading). Same plan, isolated task SUMMARY for each. | |

**User's choice:** Same plan/task pairing
**Notes:** Captured as D-04. Tasks 3 and 4 still split (T3 = REG-01 / T4 = REG-02) for clean per-task SUMMARY granularity, but the OUTPUT is a single combined regression appendix — not two separate appendices. Verdict taxonomy is uniform per D-13.

### Q4 — FIND-03 KI promotions — expected count and gating rule?

| Option | Description | Selected |
|--------|-------------|----------|
| Expect 0 promotions (default) | Per STATE.md "FIND-03 KI promotions: 0 new KI-eligible items from Phase 241". The 17 candidates are all severity INFO and Phase 237-only — unlikely to qualify as accepted-design-decision / tolerable-non-uniformity / non-exploitable-asymmetry per SC-4 criteria. Plan 02 (or Plan 03) confirms 0 promotions, no `KNOWN-ISSUES.md` writes. | ✓ |
| Re-evaluate all 17 candidates against KI gating | Plan 02/03 walks each of the 17 Phase 237 INFO candidates against SC-4's KI-eligibility rubric (accepted design / theoretical non-uniformity / non-exploitable asymmetry). Any promoted item gets explicit KI entry + `F-30-NN` cross-ref. Even if expected count is 0, the walk produces an explicit non-promotion ledger. | |
| Defer KI write to a follow-up phase | If any item qualifies, defer to Phase 243+ (new phase for `KNOWN-ISSUES.md` write). Phase 242 stays READ-only on `KNOWN-ISSUES.md`. Tightest scope-isolation; risks dangling KI promotion across phases. | |

**User's choice:** Expect 0 promotions (default)
**Notes:** Captured as D-05. Conditional rule per D-16: if D-05 expectation breaks during Plan 242-01 Task 5 walk (an item satisfies all 3 of D-09's predicates), the conditional `KNOWN-ISSUES.md` write executes inside Task 5 — no separate phase needed. Phase 243+ deferral explicitly rejected. The 17-row Non-Promotion Ledger (per D-09) is produced regardless of count, since it's the auditable artifact of the gating walk.

### Q5 (follow-up) — Within the single plan, how should the 5 requirements (FIND-01/REG-01/REG-02/FIND-02/FIND-03) be carved into sequential tasks?

| Option | Description | Selected |
|--------|-------------|----------|
| 5 tasks (1 per requirement) (Recommended) | T1 FIND-01-A: exec summary + F-30-NN ID assignment for all 17 Phase 237 INFO candidates. T2 FIND-01-B: per-consumer proof table + dedicated gameover-jackpot section. T3 REG-01: v29.0 F-29-03/F-29-04 regression. T4 REG-02: v25.0/v3.7/v3.8 rngLocked items regression. T5 FIND-02 + FIND-03: assemble final + KI gating walk + 0-promotion attestation. Mirrors Phase 241 D-03 5-task pattern. | ✓ |
| 3 tasks (forward / regression / consolidate) | T1 Forward stream: FIND-01 exec summary + F-30-NN blocks + per-consumer proof table + gameover section. T2 Regression stream: REG-01 + REG-02 paired regression appendix. T3 Final consolidation + FIND-03 KI gating walk + 0-promotion attestation. Coarser but cleaner stream-isolation. | |
| 4 tasks (forward-A / forward-B / regression / KI-consolidate) | T1 FIND-01 exec summary + F-30-NN ID assignment. T2 per-consumer proof table + gameover section (the dense table-heavy work). T3 REG-01 + REG-02 regression appendix. T4 FIND-02 + FIND-03 + final attestation. Splits the table-heavy work from the F-30-NN ID-assignment work. | |

**User's choice:** 5 tasks (1 per requirement)
**Notes:** Captured as D-03. Follows Phase 241 D-03 5-task pattern exactly. Each task maps 1:1 to a requirement (FIND-01-A / FIND-01-B / REG-01 / REG-02 / FIND-02+FIND-03). Sequential within single wave per D-01.

### Q6 (follow-up) — F-30-NN finding ID format & ordering scheme?

| Option | Description | Selected |
|--------|-------------|----------|
| F-30-NNN three-digit (Recommended) | F-30-001..F-30-017. Three-digit zero-padded matches Row-ID convention from Phases 237 (`INV-237-NNN`) / 240 (`GO-NNN`/`GOVAR-240-NNN`/`GOTRIG-240-NNN`) / 241 (`EXC-241-NNN`). Order: by source phase + plan + emit order (237-01 candidates first → 237-02 → 237-03). | ✓ |
| F-30-NN two-digit (ROADMAP literal) | F-30-01..F-30-17. Two-digit per ROADMAP SC-3 literal (`F-30-NN`). Inconsistent with three-digit row-ID convention but matches v29.0 `F-29-NN` format (`F-29-03`, `F-29-04`). | |

**User's choice:** F-30-NNN three-digit
**Notes:** Captured as D-06. Three-digit format chosen for v30.0-internal naming consistency. ROADMAP SC-3 literal `F-30-NN` interpreted as schema-naming shorthand, not a digit-count constraint. v29.0 `F-29-NN` convention superseded for v30.0. Ordering per D-07: source-phase + plan + emit-order — `F-30-001`..`F-30-005` for 237-01, `F-30-006`..`F-30-012` for 237-02, `F-30-013`..`F-30-017` for 237-03.

### Q7 (wrap-up) — Ready for context?

| Option | Description | Selected |
|--------|-------------|----------|
| I'm ready for context | Write CONTEXT.md now with the captured Plan-split decisions + Claude's-Discretion defaults for the unselected gray areas. | ✓ |
| Explore more gray areas | Discuss Severity rubric, Per-consumer table granularity, or Regression layout before writing context. | |

**User's choice:** I'm ready for context
**Notes:** Plan-split discussion fully captured (1 plan / 5 tasks / single file / REG paired / 0 KI promotions / F-30-NNN three-digit). Other gray areas resolved at Claude's Discretion per documented defaults.

---

## Claude's Discretion

The following gray areas were resolved at Claude's Discretion (user did not select for deep discussion):

- **Severity rubric (D-08)** — 5-bucket SC-1 scheme + exploitability-frame mapping (Phase 241 D-05 inheritance). All 17 Phase 237 candidates default to severity `INFO`. Rubric appears explicitly in `audit/FINDINGS-v30.0.md` § 1.
- **KI gating rubric (D-09)** — 3-predicate test (accepted-design + non-exploitable + sticky). Expected 0/17 satisfy all 3.
- **Per-consumer proof table granularity (D-10)** — 146-row INV-keyed × 5 verdict columns (INV + BWD + FWD + RNG + GO). 124 SAFE rows fully populated; 22 EXCEPTION rows carry KI cross-ref. Total 730 cells, grep-stable.
- **Dedicated gameover-jackpot section (D-11)** — Header-level summary of GO-01..05 with cross-ref to Phase 240 838-line file (READ-only per D-15).
- **Regression appendix layout (D-12)** — Chronological-by-milestone outer (v3.7 → v3.8 → v25.0 → v29.0) / topic-family inner.
- **Regression verdict taxonomy (D-13)** — Closed PASS / REGRESSED / SUPERSEDED per ROADMAP SC-2 literal. Expected distribution: 31 PASS + 0 REGRESSED + 0 SUPERSEDED (tree byte-identical to v29.0).
- **Re-verified-at-HEAD note (D-14)** — Phase 241 D-13 inheritance; minimum ≥3 instances in regression appendix.
- **Plan task-level wave topology** — D-03 5-task sequence is fixed; sub-task granularity is plan author's call.
- **F-30-NNN finding block format** — D-23 § 5 names the section; plan author selects per-block schema (minimum: ID + severity + source phase + file:line + verdict + resolution status per SC-3).
- **Regression appendix row ID scheme** — D-22 names `REG-v{X}-NNN` convention; exact format per plan author.
- **KI Non-Promotion Ledger column count** — D-09 names 3-predicate distribution; plan author selects column ordering.

## Deferred Ideas

None — discussion stayed within phase scope. See CONTEXT.md `<deferred>` section for full rationale.
