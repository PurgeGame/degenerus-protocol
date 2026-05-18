---
phase: 299
plan: 01
subsystem: fixrec-cluster-a
tags: [fixrec, rng-lock, audit-only, dailyHeroWagers, autoRebuyState]
requires:
  - .planning/RNGLOCK-CATALOG.md §16 (V-003..V-005, V-009..V-013)
  - .planning/phases/299-fix-recommendation-document-fixrec/299-CONTEXT.md (D-299-FIXREC-LAYOUT-01, D-299-SUB-AGENT-PROMPT-01)
  - .planning/milestones/v41.0-phases/288-*/288-01-DESIGN-INTENT-TRACE.md (dailyIdx structural-snapshot precedent)
provides:
  - Per-VIOLATION FIXREC entries for Cluster A (8 logical VIOLATIONs)
  - v44.0 handoff anchors D-43N-V44-HANDOFF-01..08
affects:
  - .planning/phases/299-fix-recommendation-document-fixrec/299-01-FIXREC-cluster.md (created)
tech-stack:
  added: []
  patterns:
    - Per-VIOLATION 4-sub-section analytical entry (§N.A design-intent + §N.B actor-walk + §N.C tactic+rationale+impact + §N.D handoff anchor)
    - Phase 288 dailyIdx snapshot-anchor precedent extended to dailyHeroWagers writer-side gating
    - rngLockedFlag-gated revert template (mirrors :1513 / :1528 / :1575) for autoRebuyState writers
key-files:
  created:
    - .planning/phases/299-fix-recommendation-document-fixrec/299-01-FIXREC-cluster.md
    - .planning/phases/299-fix-recommendation-document-fixrec/299-01-SUMMARY.md
  modified: []
decisions:
  - "Cluster-A scope = S-02 dailyHeroWagers (3 callsites V-003..V-005) + S-05 autoRebuyState (5 writers V-009..V-013)"
  - "Tactic mix: 3× (b) snapshot/anchor (V-003..V-005) + 5× (a) rngLockedFlag-gated revert (V-009..V-013)"
  - "V-009..V-011 gates PRESENT — Phase 299 deliverable is FUZZ-301 coverage attestation, not gate install"
  - "V-012..V-013 gates MISSING — v44.0 sub-phase installs one-line `if (rngLockedFlag) revert RngLocked();` at DegenerusGame.sol:1641 and :1654"
  - "v44.0 H-01+H-02+H-03 collapse into ONE source diff (same SSTORE site DegeneretteModule.sol:499)"
metrics:
  duration: ~25 min
  completed-date: 2026-05-18
  violations-covered: 8
  subsections-total: 32 (4 per VIOLATION)
  handoff-anchors: 8 (H-01..H-08)
  source-tree-mutations: 0
---

# Phase 299 Plan 01: FIXREC Cluster A (dailyHeroWagers + autoRebuyState) Summary

Authored per-VIOLATION FIXREC entries for Cluster A — 8 logical VIOLATIONs covering the `dailyHeroWagers[day][q]` (S-02) cross-consumer slot family (V-003, V-004, V-005) and the `autoRebuyState[beneficiary]` (S-05) writer family (V-009, V-010, V-011, V-012, V-013).

## What was built

Single AGENT-COMMITTED analytical artifact at `.planning/phases/299-fix-recommendation-document-fixrec/299-01-FIXREC-cluster.md` (489 lines, ~57 KB). Eight `## §N` sections, each containing the four mandated sub-sections:

- **§N.A** — Design-intent backward-trace citing the slot's storage-declaration line, the Phase 288 dailyIdx structural-snapshot precedent for V-003..V-005, and the existing-gate / missing-gate diagnostic for V-009..V-013.
- **§N.B** — Actor game-theory walk enumerating exploit-actor class, action sequence during the rngLock window, EV magnitude (MEDIUM for V-003/V-004; HIGH for V-005/V-009/V-010/V-011/V-012/V-013), and economic-likelihood disposition.
- **§N.C** — Recommended tactic ((b) snapshot/anchor for V-003..V-005; (a) rngLockedFlag-gated revert for V-009..V-013) + 3-5 sentence rationale + bytecode/storage/public-ABI impact estimate per `D-298-RECOMMEND-DEPTH-01` extended to per-VIOLATION depth.
- **§N.D** — v44.0 handoff anchor `D-43N-V44-HANDOFF-NN` matching the catalog §16 row's anchor (H-01..H-08), with file:line citation and 1-line plan-phase-consumable summary.

## Tactic mix

| Tactic | Count | V-NNN |
|--------|-------|-------|
| (b) snapshot/anchor | 3 | V-003, V-004, V-005 |
| (a) rngLockedFlag-gated revert | 5 | V-009, V-010, V-011, V-012, V-013 |

## EV-tier distribution

| EV tier | Count | V-NNN |
|---------|-------|-------|
| HIGH (CATASTROPHE-adjacent) | 5 | V-009, V-010, V-011, V-012, V-013 |
| HIGH (vault-amplified) | 1 | V-005 |
| MEDIUM | 2 | V-003, V-004 |

## Gate-coverage diagnostic (Cluster A autoRebuyState writers)

| V-NNN | Gate status | Phase 299 action | v44.0 deliverable |
|-------|-------------|------------------|-------------------|
| V-009 | PRESENT at DegenerusGame.sol:1513 | FUZZ coverage attestation | Phase 301 fuzz |
| V-010 | PRESENT at DegenerusGame.sol:1528 | FUZZ coverage attestation | Phase 301 fuzz |
| V-011 | PRESENT at DegenerusGame.sol:1575 | FUZZ coverage attestation | Phase 301 fuzz |
| V-012 | MISSING at DegenerusGame.sol:1641 | Add one-line gate (H-07) | v44.0 contract diff |
| V-013 | MISSING at DegenerusGame.sol:1654 | Add one-line gate (H-08) | v44.0 contract diff |

## Handoff anchors

Range: D-43N-V44-HANDOFF-01 through D-43N-V44-HANDOFF-08. All eight anchors cross-reference RNGLOCK-CATALOG.md §16 rows V-003 through V-013 by file:line and writer file:line.

## Decisions Made

- **Cluster scope locked to 8 logical VIOLATIONs** per the plan frontmatter. The dailyHeroWagers cluster collapses into a single underlying writer (DegeneretteModule.sol:499 SSTORE) reached via three distinct callsites; the autoRebuyState cluster spans five distinct writer functions in DegenerusGame.sol.
- **V-003 + V-004 + V-005 share one v44.0 diff** at the SSTORE site (or alternatively at the consumer site JackpotModule.sol:1653). The three handoff anchors are preserved per strict per-callsite catalog discipline but collapse into a single source-tree edit at the v44.0 sub-phase.
- **V-009 + V-010 + V-011 require ZERO contract changes** — gates are already installed. v44.0 deliverable is FUZZ coverage attestation (Phase 301 harness extension), not a contract patch.
- **V-012 + V-013 require ONE-LINE contract changes** — `if (rngLockedFlag) revert RngLocked();` inserted between the `msg.sender` access-control check and the writer-body SLOAD/SSTORE. The cross-contract reconciliation question (COIN/COINFLIP-side tolerance of the new revert path) is flagged for v44.0 sub-phase verification.
- **Tactic (b) for V-003..V-005 acknowledged as either (i) read-side snapshot at lock time OR (ii) write-side reject when `_simulatedDayIndex() == dailyIdx`**. Both options preserve the Phase 288 invariant; v44.0 sub-phase selects.
- **Tactic (a) for V-013 documented as STRICTLY required** (no (b) alternative) because the consumer SLOAD inside `JackpotModule.payDailyJackpot` reads `autoRebuyState[winner].afKingMode` inside the per-winner-iteration loop — snapshot at lock time is structurally infeasible because the winner set depends on VRF.

## Deviations from Plan

None — plan executed exactly as written. All `<read_first>` references were read or grep-verified; design-intent traces cite real Phase 288 artifacts (`288-01-DESIGN-INTENT-TRACE.md`); all 8 §N entries emitted with all 4 sub-sections.

## Verification

Plan automated-verify block (see `<verify><automated>` in `299-01-PLAN.md`):

- [x] `.planning/phases/299-fix-recommendation-document-fixrec/299-01-FIXREC-cluster.md` exists
- [x] All 8 V-NNN tokens (V-003 V-004 V-005 V-009 V-010 V-011 V-012 V-013) present
- [x] All 8 D-43N-V44-HANDOFF-NN anchors (HANDOFF-01..08) present
- [x] §N.A count ≥ 8 (actual: 16 — includes table-of-contents row + sub-section headings)
- [x] §N.B count ≥ 8 (actual: 21)
- [x] §N.C count ≥ 8 (actual: 20)
- [x] §N.D count ≥ 8 (actual: 8)
- [x] Zero `SAFE_BY_DESIGN` tokens (actual: 0)
- [x] `git status --porcelain contracts/ test/` returns empty (actual: empty)

## Self-Check: PASSED

- File `.planning/phases/299-fix-recommendation-document-fixrec/299-01-FIXREC-cluster.md`: FOUND
- File `.planning/phases/299-fix-recommendation-document-fixrec/299-01-SUMMARY.md`: FOUND
- Zero contracts/ + test/ tree mutations: VERIFIED
- All 8 V-NNN entries with all 4 sub-sections: VERIFIED
- All 8 H-NN handoff anchors: VERIFIED
- Zero SAFE_BY_DESIGN tokens: VERIFIED
