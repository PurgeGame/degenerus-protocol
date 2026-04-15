---
phase: 228
plan: 01
subsystem: indexer
tags: [IDX-04, cursor, reorg, state-machine, catalog-audit, read-only]
requirements: [IDX-04]
requirements_addressed: [IDX-04]
dependency_graph:
  requires: [227-03 deferrals #1/#2/#4, 228-CONTEXT D-228-01..11, 228-RESEARCH M-matrix]
  provides: [Phase 229 finding consolidation inputs F-28-228-01..04]
  affects: []
tech_stack:
  added: []
  patterns: [catalog-audit, behavioral verification, control-flow trace, assumption-check worklist, reserved finding-ID block, spot-recheck]
key_files:
  created:
    - .planning/phases/228-cursor-reorg-view-refresh-state-machines/228-01-CURSOR-REORG-TRACE.md
    - .planning/phases/228-cursor-reorg-view-refresh-state-machines/228-01-SUMMARY.md
  modified: []
finding_id_block: F-28-228-01..99
findings_consumed: [F-28-228-01, F-28-228-02, F-28-228-03, F-28-228-04]
next_available_finding_id: F-28-228-05
decisions: []
metrics:
  duration_minutes: ~18
  completed_date: 2026-04-15
  rows_audited: 11
  pass: 7
  pass_with_info: 3
  pass_with_low: 2
  fail: 0
---

# Phase 228 Plan 01: Cursor & Reorg State-Machine Trace (IDX-04) — Summary

Produced `228-01-CURSOR-REORG-TRACE.md` — a per-state-transition behavioral audit of `cursor-manager.ts`, `reorg-detector.ts`, and their orchestration via `main.ts`. Audited 11 rows (10 pre-assigned M-matrix rows + 1 intra-batch edge case E1). All 3 Phase 227 deferrals (#1 cursor rewind, #2 reorg overwrite ordering, #4 backfill-gate `<=` boundary) resolved as annotated rows. Assumptions A1/A2/A3 verified against live code. 4 finding stubs emitted in the reserved `F-28-228-01..99` block for Phase 229 consolidation.

## Verdict Counts

| Verdict | Count | Rows |
|---------|-------|------|
| PASS (clean) | 7 | M3, M4, M5, M6, M7, M8, (SC-4 file-touch rows all covered) |
| PASS-with-INFO | 2 | M2, M13, M14 (3 rows, 2 without findings emitted counted once; M14 is PASS-with-INFO no-finding, M2+M13 emit INFO findings) |
| PASS-with-LOW | 2 | M1, E1 |
| FAIL | 0 | — |

Reconciliation (explicit): M1 = PASS-with-LOW (finding F-28-228-01); M2 = PASS-with-INFO (finding F-28-228-02); M3 = PASS; M4 = PASS; M5 = PASS; M6 = PASS; M7 = PASS; M8 = PASS; M13 = PASS-with-INFO (finding F-28-228-03); M14 = PASS-with-INFO (no finding — implicit-by-construction); E1 = PASS-with-LOW (finding F-28-228-04). Total 11 rows.

## Findings Consumed

**Reserved block:** `F-28-228-01..99` per D-228-10 (disjoint from 228-02's `F-28-228-101+`).

| Finding ID | Severity | Direction | File:line | Origin row | Resolution (proposed) |
|------------|----------|-----------|-----------|------------|------------------------|
| F-28-228-01 | LOW | comment→code | cursor-manager.ts:45 | M1 (227-deferral-1) | RESOLVED-DOC or RESOLVED-CODE-FUTURE |
| F-28-228-02 | INFO | comment→code | cursor-manager.ts:70 | M2 | INFO-ACCEPTED or RESOLVED-CODE-FUTURE |
| F-28-228-03 | INFO | docs→code | main.ts:216-220 (ROADMAP IDX-04) | M13 | RESOLVED-DOC or RESOLVED-CODE-FUTURE |
| F-28-228-04 | LOW | docs→code | main.ts:155 (anvil confirmations=0) | E1 | RESOLVED-CODE-FUTURE or INFO-ACCEPTED (dev-only) |

**Severity distribution:** 2 INFO, 2 LOW, 0 MEDIUM. No HIGH/CRITICAL per D-228-11 (reserved for Phase 229 promotion).

**Next available finding ID:** `F-28-228-05` (well below the `F-28-228-101` reserved boundary for 228-02).

## Assumption Resolutions (A1 / A2 / A3)

| # | Assumption | Resolution | File:line |
|---|------------|------------|-----------|
| A1 | `processBlockBatch` invokes `storeBlock` | PASS | `storeBlock` imported at event-processor.ts:21; called at event-processor.ts:151 inside the blockHeaders loop (lines 149-158) |
| A2 | `advanceCursor` called inside a tx | PASS | `advanceCursor` imported at event-processor.ts:20; called at event-processor.ts:161 with the tx passed in from main.ts:188 `db.transaction(async (tx) => ... processBlockBatch(tx, ...))` |
| A3 | `config.confirmations` default ≥ 1 | MIXED — mainnet=64, sepolia=5, **anvil=0** | /home/zak/Dev/PurgeGame/database/src/config/chains.ts:11-13 |

A3 mixed resolution is what calibrated E1 to LOW (self-healing on next iteration) rather than MEDIUM — no permanent corruption possible because the next iteration's detectReorg walk-back restores correct state.

## Absorbed 227 Deferrals

All 3 deferrals assigned to 228-01 resolved as annotated audit rows with PASS/PASS-with-LOW verdicts and finding stubs where warranted:

| 227 Deferral | 228 Row | Verdict | Finding |
|--------------|---------|---------|---------|
| #1 cursor-manager.ts:45 rewind guardrail | M1 | PASS-with-LOW (behavioral PASS; comment overclaim) | F-28-228-01 |
| #2 reorg-detector.ts:33 storeBlock ON CONFLICT ordering | M3 + M4 | PASS (ordering strict; idempotent construct) | — |
| #4 main.ts:211 backfill gate `<=` boundary | M8 | PASS (`<=` is correct inclusive boundary) | — |

## Phase 229 Handoff

For consolidation into flat `F-28-NN` namespace:

- **F-28-228-01** (cursor rewind docstring) — candidate for RESOLVED-DOC; trivial comment patch closes it.
- **F-28-228-02** (advanceCursor tx-enforcement) — INFO-ACCEPTED unless Phase 229 decides to harden the type system.
- **F-28-228-03** (ROADMAP "recovery-after-stall" unbacked) — policy decision: narrow the requirement (RESOLVED-DOC) or add a watchdog (RESOLVED-CODE-FUTURE).
- **F-28-228-04** (intra-batch reorg on anvil) — dev-chain-only; Phase 229 may INFO-ACCEPT or promote if production chains ever configure confirmations=0.

No finding requires HIGH/CRITICAL promotion based on 228-01 evidence alone.

## SC-4 Indexer-File Coverage

5 of 9 indexer files audit-touched by 228-01 (per SC-4 File-Touch Evidence in 228-01-CURSOR-REORG-TRACE.md):

| File | Touched by 228-01 | Notes |
|------|-------------------|-------|
| cursor-manager.ts | ✓ | M1, M2 |
| reorg-detector.ts | ✓ | M3, M4, M5, M6, M7 |
| main.ts | ✓ | M4, M8, E1, M13, A2 |
| block-fetcher.ts | ✓ | fetchLogs at main.ts:164; getLatestBlockNumber at main.ts:140 |
| purge-block-range.ts | ✓ | PURGEABLE_TABLES iterated by rollbackToBlock (M7); purgeBlockRange invoked by main.ts:129 |
| event-processor.ts | (227-03 primary) | storeBlock/advanceCursor call-sites A1/A2 confirmed here |
| view-refresh.ts | (228-02 primary) | — |
| (index.ts barrel, if any) | (228-02) | — |
| (delegated handler files) | (227-02/03 primary) | — |

Remaining 4 indexer files are audit-touched by 227-02/03 and 228-02 per the milestone SC-4 distribution.

## Scope-Boundary Reminder

- **D-228-01/02:** Cross-repo READ-only, catalog-only. Zero writes to `/home/zak/Dev/PurgeGame/database/` — `git -C /home/zak/Dev/PurgeGame/database status` verified clean.
- **D-228-11:** All 4 findings INFO or LOW. HIGH/CRITICAL reserved for Phase 229 promotion if cross-phase analysis elevates them.
- **D-228-10:** Finding IDs `F-28-228-01..04` consumed; next available `F-28-228-05`; `F-28-228-101+` block reserved and untouched for 228-02.

## Acceptance Criteria Check

- [x] 228-01-CURSOR-REORG-TRACE.md and 228-01-SUMMARY.md exist.
- [x] All 10 M-rows (M1, M2, M3, M4, M5, M6, M7, M8, M13, M14) + E1 edge case present with non-TBD Final Verdict + Rationale + File:line evidence.
- [x] 3 absorbed 227 deferrals annotated (`227-deferral-1`, `227-deferral-2`, `227-deferral-4`).
- [x] Assumption-Check worklist A1/A2/A3 resolved with File:line citations.
- [x] 4 F-28-228-NN finding stubs emitted, contiguous from F-28-228-01, all below F-28-228-101.
- [x] All findings cite absolute paths under `/home/zak/Dev/PurgeGame/database/`.
- [x] All findings severity ∈ {INFO, LOW} — no MEDIUM/HIGH/CRITICAL emitted.
- [x] SC-4 File-Touch Evidence table has concrete File:line for all 5 indexer files.
- [x] Spot-Recheck Log has 2 re-verifications (M4, M8).
- [x] Zero writes outside `.planning/phases/228-cursor-reorg-view-refresh-state-machines/`.

## Self-Check: PASSED

- File `.planning/phases/228-cursor-reorg-view-refresh-state-machines/228-01-CURSOR-REORG-TRACE.md` exists ✓
- File `.planning/phases/228-cursor-reorg-view-refresh-state-machines/228-01-SUMMARY.md` exists ✓
- Task 1 commit `1e081441` present in `git log` ✓
- Finding IDs F-28-228-01..04 contiguous; next-available F-28-228-05; no collision with 228-02's F-28-228-101+ block ✓
- 10 M-rows + E1 + 3 deferral annotations verified in TRACE ✓
- 2 spot-rechecks logged ✓
- A1/A2/A3 resolved with absolute File:line ✓
- SC-4 touches 5 indexer files (cursor-manager, reorg-detector, main, block-fetcher, purge-block-range) ✓
- `git -C /home/zak/Dev/PurgeGame/database status` clean (zero writes to audit target) ✓

## PLAN COMPLETE
