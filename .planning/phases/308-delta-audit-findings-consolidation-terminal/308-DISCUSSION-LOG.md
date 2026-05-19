# Phase 308: Delta Audit + Findings Consolidation (TERMINAL) - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-19
**Phase:** 308-delta-audit-findings-consolidation-terminal
**Areas discussed:** INV/EDGE count reconciliation, §4 adversarial disposition granularity, §3.A delta-surface depth, task split / wave shape

---

## INV/EDGE Count Reconciliation (§3.F + §3.C + §9 verdict)

| Option | Description | Selected |
|--------|-------------|----------|
| Attest reality (13 INV / 20 EDGE) | §3.F + §3.C enumerate INV-01..13; §9 reads "13 of 13 INVARIANTS PROVEN; 20 of 20 EDGE_CASES TESTED". Diverge from ROADMAP §9 template; the matrix and verdict reflect what Phase 306 actually proved. Phase 307 CHARGE already uses INV-01..13. | ✓ |
| Stick to ROADMAP (12 INV / 18 EDGE) | §3.F lists INV-01..12 verbatim; INV-13 + EDGE-19..20 documented as v44-emergent supporting tests in a separate "Emergent coverage" §3.F.1 sub-section. §9 verdict uses ROADMAP-locked 12/12 + 18/18 string verbatim. Preserves verdict-template fidelity. | |
| Attest 13/20 + amend §9 verdict template | Update REQUIREMENTS.md AUDIT-09 verdict string mid-flight to "13 of 13 + 20 of 20" + add a one-line "verdict-template amended at Phase 308 plan-time per Phase 306 actual coverage" attestation row in §3.F. | |

**User's choice:** Attest reality (13 INV / 20 EDGE)
**Notes:** Diverging from ROADMAP verdict template is in-band documented per `D-308-INV-COUNT-01`. Phase 305 added INV-13 emergent from `D-305-SENTINEL-01`; Phase 306 extended EDGE enumeration from 18 to 20 fuzz fns to cover transfer-mid-pending + approve-mid-stall perturbations. §3.F + §3.C + §9 emit Phase 306 actual coverage.

---

## §4 Adversarial Disposition Granularity

| Option | Description | Selected |
|--------|-------------|----------|
| Condensed: SWP-01..05 + 5 augments + beyond-charge | ~17 hypothesis rows (5 SWP + 5 augments + 7 beyond-charge); each row cites the per-skill MD verdict + Skeptic-Filter Discarded count + Severity-Downgrade rationale. Mirrors v41 P284 + v43 P303 §4 condensed style. Easier to read; cross-references LOG for full detail. | ✓ |
| Verbatim 72-row LOG transcription | Copy `307-01-ADVERSARIAL-LOG.md` integrated Disposition table verbatim into §4 (72 rows). Maximum audit-trail; no information loss. Heavier reading; redundant with LOG which is already AGENT-COMMITTED at `.planning/phases/307-*/`. | |
| 3-table per-skill summary | §4.A contract-auditor (22 rows) + §4.B zero-day-hunter (22 rows) + §4.C economic-analyst (28 rows) — each as a self-contained per-skill table. Preserves per-skill provenance; easier to spot-check; 3× the visual weight of condensed. | |

**User's choice:** Condensed: SWP-01..05 + 5 augments + beyond-charge
**Notes:** Per `D-308-ADVERSARIAL-DISP-01`. Audit-trail completeness preserved via the LOG cross-reference column on each row; the LOG is the authoritative detail and is AGENT-COMMITTED at `.planning/phases/307-adversarial-sweep-sweep/307-01-ADVERSARIAL-LOG.md`. Mirrors v41 P284 + v43 P303 condensed precedent.

---

## §3.A Delta-Surface Enumeration Depth

| Option | Description | Selected |
|--------|-------------|----------|
| Load-bearing only (~7-8 rows) | Phase 304 SPEC commits aggregated to 1 row; Phase 305 contract commit `213f9184` 1 row; Phase 306 test commits aggregated by plan (5 rows); Phase 307 LOG bundle 1 row. Total ~7-8 rows. Mirrors v43 P303 §3.A audit-only-posture row density. | ✓ |
| Per-commit verbatim (~28 rows) | Every AGENT-COMMITTED docs(NNN-NN), every test() commit, and the contract commit each get their own row with SHA + commit subject + classification + delta-class. Maximum delta-surface visibility. | |
| Hybrid: per-phase summary + drill-down | Top-level 5 rows (Phase 304/305/306/307 + cross-phase state) with per-row commit-SHA range; nested sub-rows enumerate only contract+test commits explicitly. Planning-doc commits stay summarized. | |

**User's choice:** Load-bearing only (~7-8 rows)
**Notes:** Per `D-308-DELTA-SURFACE-DEPTH-01`. Eight rows enumerated: Phase 304 SPEC bundle / Phase 305 USER-APPROVED contract (`213f9184`) / Phase 305 planning bundle / Phase 306 Plan 01 invariant harness / Phase 306 Plans 02..03 EDGE fuzz / Phase 306 Plan 04 vm.skip flip (REG-01 anchor) / Phase 306 Plan 05 gas regression bench / Phase 307 SWEEP LOG bundle. The contract commit gets its own row so the USER-APPROVED diff is explicitly enumerated.

---

## Task Split / Wave Shape

| Option | Description | Selected |
|--------|-------------|----------|
| Mirror P303 — 1 plan / 13 tasks | Single `308-01-PLAN.md` with 13 tasks: 1 per §3.A/§3.B/§3.C/§3.D/§3.E/§3.F/§4/§5/§6/§7-9 + Task 11 Commit 1 + Task 12 Commit 2 + Task 13 state-update. Sequential main-context end-to-end per D-303-EXEC-SHAPE-01. Lowest coordination overhead. | ✓ |
| Split: deliverable plan + closure plan | Plan 01 = §1..§9 deliverable authoring (10 tasks ending at Commit 1 with placeholder). Plan 02 = closure-flip (Commit 2 + verbatim propagation + chmod 444 + atomic 5-doc closure flip + state-update). Clean separation between deliverable + closure orchestration; matches CLS-01 vs CLS-02 split. | |
| Compressed: 1 plan / 7 tasks | Single plan: 7 tasks compressing §-authoring + closure into fewer task boundaries. Fewer boundaries; relies on planner+executor to keep §-level provenance clean inside compound tasks. | |

**User's choice:** Mirror P303 — 1 plan / 13 tasks
**Notes:** Per `D-308-TASK-SPLIT-01`. D-303-TASK-SPLIT-01 is the proven template; v44 has the same 9-section deliverable shape + 2-commit closure. Single plan keeps the artifact bundle atomic. Commit 2's atomic 5-doc closure flip MUST run as a single `git commit` with all 5 files staged together per CLS-01 atomicity.

---

## Claude's Discretion

- **Per-§ sub-agent decomposition** — main-context end-to-end is the default per D-303-EXEC-SHAPE-01 carry. If §3.A or §4 cross-referencing becomes burdensome at execution time, planner may dispatch a sub-agent for that section.
- **Row ordering inside §3.F** — INV-NN sequential (1..13) is the default; since all 13 are PROVEN, sequential ordering is the expected emission.
- **§3.A row aggregation splits** — planner may split a row into two if the aggregation obscures a load-bearing distinction (e.g., split Phase 306 Plan 04 vm.skip flip from Plan 05 gas bench).
- **5 FINDINGS verbatim locations enumeration** — Phase 308 plan-time identifies the 5 sites inside `audit/FINDINGS-v44.0.md` where `<commit-1-sha>` placeholder appears; mirror v43 P303 5-site pattern.

## Deferred Ideas

- **MILESTONE-AUDIT.md authoring** — post-closure housekeeping; Phase 308 task or separate `/gsd:complete-milestone` invocation per `D-303-DEFER-01` precedent.
- **v45.0 plan-phase invocation** — explicitly OUT of v44 scope; v45 starts after v44 closure-flip lands. The 135-anchor §9d handoff register is v45.0+ primary input but Phase 308 does not consume it.
- **§3.F WAIVED or FAILING rows** — N/A per Phase 306 outcome (all 13 PROVEN). Future TERMINAL planners re-evaluate ordering + closure-block semantics if non-PROVEN status emerges.
- **Cross-milestone adversarial RE-PASS** — §5 REG-01 + §6 KI already cover v43-surface integrity; not needed.
- **Direct contracts/test mutations during Phase 308** — SOURCE-TREE FROZEN per ROADMAP success criterion #5.
- **Re-pinging user at Commit 2** — REJECTED per `D-44N-CLOSURE-PREAUTH-01`; pre-authorization holds.
