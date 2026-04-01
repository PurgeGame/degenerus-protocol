# Phase 128: Changed Contract Adversarial Audit - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-26
**Phase:** 128-changed-contract-adversarial-audit
**Areas discussed:** Audit partitioning, DegenerusAffiliate depth, Degenerette freeze fix scope, Cross-contract integration checks

---

## Audit Partitioning

| Option | Description | Selected |
|--------|-------------|----------|
| By originating phase | 4 plans grouped by v6.0 phase (121/122/124/unplanned) — internally coherent, shared design intent | ✓ |
| By contract | One plan per contract or small clusters — mirrors Phase 127 but awkward at 11 contracts | |
| By risk tier | High-risk first, then medium, then low — focuses attention but mixes unrelated contracts | |
| Hybrid: phase + risk | Merge smallest groups — e.g., combine 121+124 since they share contracts | |

**User's choice:** By originating phase
**Notes:** None — straightforward selection

---

## DegenerusAffiliate Depth

| Option | Description | Selected |
|--------|-------------|----------|
| Same depth as other plans | Standard Mad Genius/Skeptic/Taskmaster — three-agent system already catches issues | ✓ |
| Enhanced scrutiny | Standard plus full call-path trace, economic analysis of default referral codes, v5.0 cross-reference | |
| Standalone deep-dive | Dedicated plan like Phase 127 treated DegenerusCharity — extra attention to behavioral change | |

**User's choice:** Same depth as other plans
**Notes:** None

---

## Degenerette Freeze Fix Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Treat every touched function equally | Full Mad Genius on all 18 — simple rule, no risk of skipping hidden logic changes | |
| Triage first, then audit | Classify each as logic/formatting-only, full depth on logic, fast-track on cosmetic | ✓ |
| Audit all, note formatting-only in verdicts | Full analysis on everything, but verdicts note when change was cosmetic | |

**User's choice:** Triage first, then audit
**Notes:** None

---

## Cross-Contract Integration Checks

| Option | Description | Selected |
|--------|-------------|----------|
| Per-function only | Each plan audits in isolation; Phase 129 flags integration concerns | |
| Seam checks within each plan | Extended analysis on boundary-crossing functions, not a separate sweep | |
| Dedicated integration plan | 5th plan for cross-contract seams: fund split, yield surplus, yearSweep, access control, resolveLevel | ✓ |

**User's choice:** Dedicated integration plan
**Notes:** Results in 5 total plans (4 per-phase + 1 integration)

---

## Claude's Discretion

- Function assignment when touched by multiple phases
- BitPackingLib natspec-only handling
- Triage classification format for DegeneretteModule
- Taskmaster coverage matrix structure

## Deferred Ideas

None — discussion stayed within phase scope
