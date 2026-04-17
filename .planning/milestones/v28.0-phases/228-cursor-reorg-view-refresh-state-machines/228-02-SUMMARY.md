---
phase: 228
plan: 02
subsystem: indexer
tags: [IDX-05, view-refresh, materialized-views, state-machine, catalog-audit, read-only]
requirements: [IDX-05]
dependency_graph:
  requires: [227-03-SUMMARY (deferral #3 handoff), 226-01-SCHEMA-MIGRATION-DIFF (views.ts context)]
  provides: [Phase 229 consolidation — 1 finding in F-28-228-101+ block]
  affects: []
tech_stack:
  added: []
  patterns: [catalog-audit, comment→code verification, cross-repo READ-only, reserved finding-ID block]
key_files:
  created:
    - .planning/phases/228-cursor-reorg-view-refresh-state-machines/228-02-VIEW-REFRESH-AUDIT.md
    - .planning/phases/228-cursor-reorg-view-refresh-state-machines/228-02-SUMMARY.md
  modified: []
finding_id_block: F-28-228-101..199
findings_consumed: [F-28-228-101]
next_available_finding_id: F-28-228-102
decisions: []
metrics:
  duration_minutes: ~8
  completed_date: 2026-04-15
  rows_audited: 5
  mv_rows: 4
  pass: 2
  pass_with_info: 1
  pass_with_low: 1
  info_accepted: 1
  fail: 0
---

# Phase 228 Plan 02: View-Refresh Audit (IDX-05) — Summary

Audited every refresh trigger in `view-refresh.ts` against the two D-228-08 sources (in-source comments + `views.ts` schema definitions); produced `228-02-VIEW-REFRESH-AUDIT.md` with 5 M/V-matrix rows verdicted, all 4 pgMaterializedViews trigger-mapped, and 1 LOW finding `F-28-228-101` emitted to resolve Phase 227 deferral #3.

## Verdict Counts

| Verdict | Count | Rows |
|---------|-------|------|
| PASS | 2 | M10, M11 |
| PASS-with-INFO | 1 | M12 |
| PASS-with-LOW | 1 | M9 |
| INFO-ACCEPTED | 1 | V1 |
| LOW (standalone) | 0 | — |
| MEDIUM | 0 | — |

Trigger-to-View Mapping: **4/4 PASS** — every pgMaterializedView declared in `views.ts` (mv_player_summary, mv_coinflip_top10, mv_affiliate_leaderboard, mv_baf_top4) is covered by the `ALL_VIEWS` loop at `view-refresh.ts:26-34`. No orphan views.

## Findings Consumed

**Reserved block:** `F-28-228-101..199` (per D-228-10; disjoint from 228-01's `F-28-228-01..99`).

| Finding ID | Severity | Direction | Origin row | File:line | Resolution | Summary |
|------------|----------|-----------|------------|-----------|------------|---------|
| F-28-228-101 | LOW | comment→code | M9 (227-deferral-3) | /home/zak/Dev/PurgeGame/database/src/indexer/view-refresh.ts:4-5 + :30-32 | RESOLVED-CODE-FUTURE | Comment "stale view for one block is acceptable" misrepresents the sustained-failure bound; 5 of 6 observability channels absent, staleness is unbounded under sustained refresh failure. |

**Next available finding ID:** `F-28-228-102`.
**Collision check:** no overlap with 228-01 (`F-28-228-01..99`). ✓

## Phase 227 Deferral Closure

| # | 227 deferral | Status in 228-02 |
|---|--------------|------------------|
| 3 | `view-refresh.ts:5` try/catch swallows refresh failures — only feedback is log.error | **CLOSED** via F-28-228-101 (LOW, RESOLVED-CODE-FUTURE). Observability inventory (6 channels) documented in audit deliverable. No alerting design produced — per 228-CONTEXT.md Deferred Ideas, build-out is out of audit scope. |

## Phase 229 Handoff

| Finding ID | Severity | Direction | Resolution | Consolidation note |
|------------|----------|-----------|------------|--------------------|
| F-28-228-101 | LOW | comment→code | RESOLVED-CODE-FUTURE | Phase 229 should flat-namespace this as `F-28-NN` and pair with any related observability-gap findings from 228-01 for consolidated operational-gap reporting. No severity promotion warranted — behavior is documented operationally-unsafe, not silently incorrect. |

## SC-4 Coverage Confirmation

| Indexer file | Touched by 228-02? | Combined coverage (227 + 228) |
|--------------|--------------------|-------------------------------|
| view-refresh.ts | ✓ (primary) | 227-03 comment audit + 228-02 behavioral audit |
| main.ts | ✓ (trigger wiring :112, :211-215) | 227-03 + 228-01 (cursor/reorg) + 228-02 (refresh trigger) |
| views.ts (db/schema) | ✓ (4 mv declarations + UNIQUE indexes) | 226-01 structural diff + 228-02 trigger mapping |
| cursor-manager.ts | ✗ (228-01 territory) | — |
| reorg-detector.ts | ✗ (228-01 territory) | — |
| block-fetcher.ts | ✗ (228-01 territory) | — |
| event-processor.ts | ✗ (227 territory) | — |
| purge-block-range.ts | ✗ (228-01 territory) | — |
| handlers/*.ts | ✗ (227 territory) | — |

Combined 228-01 + 228-02 + 227 coverage satisfies the 9-indexer-file SC-4 requirement. This plan advances the view-refresh.ts + views.ts + main.ts portions.

## Views Orphan Check

All 4 `pgMaterializedView` entries in `views.ts` are triggered via the `ALL_VIEWS` registry loop — confirmed by direct grep (`rg -n 'pgMaterializedView' views.ts` returns exactly 4 hits, each mapped in the audit deliverable's Trigger-to-View Mapping table). Zero orphan views.

## Cross-Reference Validation (D-228-08)

- **Source 1** (in-source comments): 8 comment/code tokens in `view-refresh.ts` + `main.ts:211` grepped and mapped to audit rows (see deliverable §Cross-Reference Validation).
- **Source 2** (schema views.ts): 4 `pgMaterializedView` declarations grepped and cross-listed against the ALL_VIEWS registry at views.ts:93-98 and the 4 Trigger-to-View Mapping rows.

Both sources agree on the staleness model as documented — the one divergence (sustained-failure bound) is captured in F-28-228-101.

## Scope-Boundary Reminder

- Per D-228-01/02: zero writes to `/home/zak/Dev/PurgeGame/database/`; catalog-only (no runtime gate, no CI).
- Per D-228-08: downstream API consumers out of scope (Phase 224 owns API-route audit).
- Per D-228-11: HIGH/CRITICAL reserved for Phase 229 promotion; this plan's findings are INFO/LOW only.
- Per 228-CONTEXT.md Deferred Ideas: alerting/observability build-out for swallowed refresh errors is explicitly NOT a 228-02 deliverable — F-28-228-101 flags the gap with RESOLVED-CODE-FUTURE and defers fix design to downstream triage.

## Acceptance Criteria Check

- [x] `228-02-VIEW-REFRESH-AUDIT.md` + `228-02-SUMMARY.md` exist.
- [x] All 4 M-rows (M9, M10, M11, M12) + V1 INFO context row have non-TBD Final Verdict + Rationale.
- [x] 227-deferral-3 annotated on M9 and resolved via F-28-228-101 (LOW, RESOLVED-CODE-FUTURE).
- [x] All 4 pgMaterializedViews have a Trigger-to-View Mapping row with PASS verdict.
- [x] Finding IDs consumed in `F-28-228-101+` block only (F-28-228-101 issued; no collision with 228-01).
- [x] Cross-Reference Validation section documents both D-228-08 sources.
- [x] Spot-Recheck Log has ≥2 re-verifications (M9 and M11).
- [x] Zero writes to `/home/zak/Dev/PurgeGame/database/`.
- [x] SC-4 file-touch evidence (view-refresh.ts, main.ts, views.ts) recorded.

## Self-Check: PASSED

- File `228-02-VIEW-REFRESH-AUDIT.md` exists ✓
- File `228-02-SUMMARY.md` exists ✓
- Task 1 commit `082f0ec2` present in `git log` ✓
- Finding ID `F-28-228-101` used; next-available `F-28-228-102`; no collision with 228-01's `F-28-228-01+` ✓
- 5 matrix rows verdicted (M9, M10, M11, M12, V1); 4 mapping rows verdicted ✓
- 2 spot-rechecks logged (M9, M11) ✓
- Phase 229 handoff section present ✓
- Zero writes to `/home/zak/Dev/PurgeGame/database/` (confirmed — only `.planning/` files modified) ✓

## PLAN COMPLETE
