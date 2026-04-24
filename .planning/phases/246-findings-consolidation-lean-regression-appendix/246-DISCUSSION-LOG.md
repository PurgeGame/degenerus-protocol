# Phase 246: Findings Consolidation + Lean Regression Appendix — Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in `246-CONTEXT.md` — this log preserves the alternatives considered.

**Date:** 2026-04-24
**Phase:** 246-findings-consolidation-lean-regression-appendix
**Areas discussed:** Plan Split topology, REG-02 SUPERSEDED sweep scope
**Areas auto-decided (user did not select; Claude's Discretion with v30 Phase 242 precedent):** REG-01 touched-by-deltas criteria, FIND-01 deliverable shape (zero-findings variant)

---

## Gray Area Selection (initial multiSelect)

| Option | Description | Selected |
|--------|-------------|----------|
| Plan split topology | 1 / 2 / 3 plan options for FIND + REG + closure | ✓ |
| REG-01 'touched-by-deltas' criteria | Inclusion rule for prior findings to spot-check | |
| REG-02 SUPERSEDED sweep scope | Exhaustive vs explicit candidate list | ✓ |
| FIND-01 deliverable shape (zero-findings variant) | Mirror v30 vs LEAN attestation vs hybrid | |

**User selected:** Plan Split topology + REG-02 SUPERSEDED sweep scope
**Auto-decided per Claude's Discretion:** REG-01 inclusion rule (D-08 domain-cite + delta-surface mapping; F-29-04 named) + FIND-01 zero-findings shape (D-13 mirror v30 verbatim with zero-rows)

---

## Plan Split Topology

### Q1: How many plans for Phase 246?

| Option | Description | Selected |
|--------|-------------|----------|
| 1 plan (single consolidation) | Mirrors v30 Phase 242 — single 246-01-PLAN.md with sequential tasks | ✓ |
| 2 plans (FIND + REG split) | 246-01 FIND, 246-02 REG; single-wave parallel matching Phase 245 D-02 | |
| 3 plans (FIND + REG + closure) | Maximum decomposition; closure plan depends on 01+02 (2-wave) | |

**User's choice:** 1 plan (single consolidation)
**Notes:** Matches v30 Phase 242 single-plan precedent. 5 REQs + zero-finding-candidate input + LEAN regression scope fit comfortably in one plan.

### Q2: Working file pattern within the single plan?

| Option | Description | Selected |
|--------|-------------|----------|
| Direct write to FINDINGS-v31.0.md (no working file) | Plan writes directly to audit/FINDINGS-v31.0.md across atomic commits; READ-only flip on final | ✓ |
| Working file then consolidate | Plan writes to audit/v31-246-WORK.md then consolidates to FINDINGS-v31.0.md | |

**User's choice:** Direct write to FINDINGS-v31.0.md (no working file)
**Notes:** Matches v30 Phase 242 pattern. Zero-finding-candidate input means no heavy reorganization needed; working file would be over-engineered.

### Q3: Commit atomicity within the plan?

| Option | Description | Selected |
|--------|-------------|----------|
| Per-task atomic commits | Each task closes with its own commit; matches Phase 244-04 / 245-02 multi-commit-within-single-plan pattern | ✓ |
| 2-3 grouped commits | Group tasks into 2-3 commits; lower commit count | |
| Single SUMMARY commit | All work in single SUMMARY commit at plan close; matches v30 Phase 242 single-commit precedent | |

**User's choice:** Per-task atomic commits
**Notes:** Each commit independently reviewable. Selected over v30 Phase 242 single-commit shape because per-task atomicity matches Phase 244/245 in-milestone pattern.

### Q4: Task decomposition within the single plan?

| Option | Description | Selected |
|--------|-------------|----------|
| 6 tasks (1 per major artifact section) | Setup / per-phase sections / F-31-NN block / regression appendix / KI gating walk / closure attestation + READ-only flip | ✓ |
| 4 tasks (grouped by REQ family) | FIND-01/02 / REG-01/02 / FIND-03 / closure attestation | |
| 3 tasks (FIND / REG / closure) | All FIND together / All REG together / closure | |

**User's choice:** 6 tasks (1 per major artifact section)
**Notes:** Highest reviewability per atomic commit. Maps 1:1 to `audit/FINDINGS-v31.0.md` section structure. Captured in CONTEXT.md D-02.

### Q5: Continue or move to next area?

| Option | Description | Selected |
|--------|-------------|----------|
| Move to REG-02 SUPERSEDED scope | Plan split locked; advance | ✓ |
| More questions about Plan Split | Stay on plan split | |

**User's choice:** Move to REG-02 SUPERSEDED scope

---

## REG-02 SUPERSEDED Sweep Scope

### Q1: REG-02 sweep methodology?

| Option | Description | Selected |
|--------|-------------|----------|
| Explicit candidate list (LEAN) | Bounded list of supersession candidates upfront | ✓ |
| Exhaustive sweep across all prior milestones | Walk every v25-v30 finding (~50 rows) | |
| Delta-driven sweep | For each delta, walk only touched finding-domains (~5-15 rows) | |

**User's choice:** Explicit candidate list (LEAN)
**Notes:** Matches LEAN milestone scope per ROADMAP. Cost-effective rigor — same philosophy as 244 D-02 / 245 D-12.

### Q2: If explicit candidate list, what's the inclusion rule?

| Option | Description | Selected |
|--------|-------------|----------|
| Candidates pre-identified at plan-time | Plan freezes candidate list in 246-01-PLAN.md frontmatter; reviewable before execution | ✓ |
| Discovered during regression walk | Task 4 derives REG-02 candidates from REG-01 walk patterns | |
| Both — frozen baseline + discovered additions | Plan freezes baseline; discoveries added during execution | |

**User's choice:** Candidates pre-identified at plan-time
**Notes:** Frozen frontmatter pattern (illustrative example shown to user). Stable, reviewable, bounds work scope upfront.

### Q3: Hand-off format if a candidate closes SUPERSEDED?

| Option | Description | Selected |
|--------|-------------|----------|
| Per-row verdict in REG-02 table + cross-cite to delta | Matches v30 REG-02 table shape (5-column verdict per row) | ✓ |
| Prose-only narrative section | One paragraph per candidate; no table | |
| Both — table for verdicts + prose narrative for SUPERSEDED rows | Heaviest formatting, maximum reviewability | |

**User's choice:** Per-row verdict in REG-02 table + cross-cite to delta
**Notes:** v30 REG-02 (29 rows all PASS) used exact same column shape. Captured in CONTEXT.md D-12.

### Q4: Continue or ready to write CONTEXT.md?

| Option | Description | Selected |
|--------|-------------|----------|
| Ready to write CONTEXT.md | REG-02 scope locked: methodology, inclusion rule, format | ✓ |
| More questions about REG-02 | Stay on REG-02 | |

**User's choice:** Ready to write CONTEXT.md

---

## Claude's Discretion (areas user did not select)

### REG-01 'touched-by-deltas' criteria
**Auto-decision (D-08):** A prior finding is "directly touched by deltas" iff its evidence cites a consumer / path / site / state-var / event / interface method touched by ≥1 of the 5 v31.0 deltas. F-29-04 explicitly NAMED in REQ. Phase 243 §6 Consumer Index provides authoritative consumer-to-delta mapping. Preliminary candidate set (planner refines): F-29-04 (RE_VERIFIED), F-30-001, F-30-005, F-30-007, F-30-015, F-30-017. Verdict taxonomy: `PASS / REGRESSED / SUPERSEDED` (D-09). Rationale: Defensible default that lets the planner walk each F-30-NNN row applying the inclusion rule with documented exclusion rationale. Matches 244 D-07 / 245 D-09 Claude's-Discretion-with-floor pattern.

### FIND-01 deliverable shape (zero-findings variant)
**Auto-decision (D-13):** Mirror v30 FINDINGS-v30.0.md 10-section shape verbatim with zero-rows where applicable. Severity counts 0/0/0/0/0. F-31-NN block one-paragraph zero-attestation prose. Non-Promotion Ledger zero-row table with explanatory header. Per-phase sections condensed summaries pointing to source artifacts. Rationale: Maximizes Phase 246 reviewability + future-reader benefit (v32+ phases see consistent v30/v31 artifact shapes). Defensible default given user-locked D-01 single-plan-precedent commitment to v30 Phase 242 mirror.

---

## Deferred Ideas

The following ideas were noted for future phases (see CONTEXT.md `<deferred>` section for full list):

- Full v30.0 31-row regression sweep — replaced by REG-01 LEAN spot-check per ROADMAP
- Exhaustive REG-02 SUPERSEDED sweep across all prior milestones — replaced by explicit candidate list
- Per-finding NUMERIC severity scoring (CVSS / DREAD) — qualitative D-08 5-bucket carries
- Automated FIND-01 deliverable generation from working files — hand-authored in v31.0
- KI gating predicate refinement (4-predicate / weighted) — 3-predicate AND carries from v30
- Cross-milestone finding-ID re-numbering — F-NN-NN scheme retained per milestone

---

*Discussion duration:* ~3 question rounds across 2 user-selected gray areas + 2 Claude's Discretion auto-decisions
*Total decisions captured:* 25 D-NN entries in CONTEXT.md (D-01 through D-25)
*Phase boundary cleanly defined; ready for `/gsd-plan-phase 246`.*
