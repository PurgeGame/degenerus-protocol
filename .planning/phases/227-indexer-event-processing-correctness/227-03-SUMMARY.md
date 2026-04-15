---
phase: 227
plan: 03
subsystem: indexer
tags: [IDX-03, comment-drift, catalog-audit, read-only]
requirements: [IDX-03]
dependency_graph:
  requires: [226-01-SCHEMA-MIGRATION-DIFF (raw_events unique index), 227-CONTEXT (D-227-10 scope guard)]
  provides: [Phase 228 deferred-items list for IDX-04/IDX-05 state-machine plan]
  affects: []
tech_stack:
  added: []
  patterns: [catalog-audit, comment→code verification, Tier A/B threshold, scope-guard deferral]
key_files:
  created:
    - .planning/phases/227-indexer-event-processing-correctness/227-03-INDEXER-COMMENT-AUDIT.md
    - .planning/phases/227-indexer-event-processing-correctness/227-03-SUMMARY.md
  modified: []
finding_id_block: F-28-227-201..299
findings_consumed: [F-28-227-201, F-28-227-202]
next_available_finding_id: F-28-227-203
decisions: []
metrics:
  duration_minutes: ~12
  completed_date: 2026-04-15
  rows_audited: 15
  seeds_covered: 8
  pass: 13
  fail: 2
  deferred_to_228: 4
---

# Phase 227 Plan 03: Indexer Comment Correctness Audit — Summary

Audited comment claims about idempotency / reorg safety / backfill / view-refresh trigger semantics across `database/src/indexer/*.ts` and `database/src/handlers/*.ts`; filed 2 Tier B comment-drift findings in the reserved `F-28-227-201+` block, deferred 4 behavioral claims to Phase 228 per D-227-10 scope guard.

## Tier Tallies

| Tier | Rule | Count |
|------|------|-------|
| A (invariant-mismatch) | Comment describes an invariant the code either doesn't implement or implements differently | 0 |
| B (partial / ambiguous / omits a branch) | Comment partially correct | 2 |
| C (missing comment) | Counted, not enumerated per D-227-03 | 0 systemic |
| D (typo / stale method name) | Skipped | 0 notable |

## Verdict Counts

| Verdict | Count | Notes |
|---------|-------|-------|
| PASS    | 13    | All 8 seeds + 5 sweep-expansion rows |
| FAIL    | 2     | rows 9, 10 in audit table |

## Findings Consumed

**Reserved block:** `F-28-227-201..299` (per D-227-11, disjoint from 227-01 `F-28-227-01+` and 227-02 `F-28-227-101+`).

| Finding ID | Severity | File:line | Claim summary |
|------------|----------|-----------|---------------|
| F-28-227-201 | INFO (Tier B) | `database/src/handlers/new-events.ts:4-5` | "No upsert, no composite logic" contradicted by `handleGameOverDrained` upserting `prize_pools` |
| F-28-227-202 | INFO (Tier B) | `database/src/handlers/lootbox.ts:5` | "All handlers are append-only" contradicted by `handleTraitsGenerated` composite branching into `trait_burn_tickets` upsert |

**Next available finding ID:** `F-28-227-203`.
**Collision check:** no overlap with 227-01 (`F-28-227-01..`) or 227-02 (`F-28-227-101..`). ✓

## Severity Breakdown

| Severity | Count |
|----------|-------|
| INFO     | 2     |
| LOW      | 0     |

Both findings resolve as RESOLVED-DOC (patch the comment, no code change required).

## Phase 228 Handoff (Deferred per D-227-10)

These 4 claims passed the comment→code accuracy check but raise behavioral questions that Phase 228 must address in its IDX-04 / IDX-05 state-machine audit:

| # | File:line | Deferred concern | Suggested 228 angle |
|---|-----------|------------------|---------------------|
| 1 | `indexer/cursor-manager.ts:45` | `initializeCursor` overwrites an existing `lastProcessedBlock` — "safely" is behavior-dependent | Cursor rewind guardrails: should re-init no-op when existing cursor > startBlock? |
| 2 | `indexer/reorg-detector.ts:33` | `storeBlock` ON CONFLICT DO UPDATE silently overwrites hash/parentHash for an existing blockNumber without rollback | Invariant: must `rollbackToBlock(forkBlock)` strictly precede any `storeBlock` on `blockNumber > forkBlock`? |
| 3 | `indexer/view-refresh.ts:5` | try/catch swallows refresh failures — only feedback is log.error | Staleness policy: metric/alerting for sustained refresh failures beyond one block? |
| 4 | `indexer/main.ts:211` | Backfill gate `lag <= config.batchSize` — edge case when cursor lands on `tip - batchSize` | Boundary verification: is the `<=` threshold exact, or should it be `<`? |

## Spot-Recheck Log (per 227-VALIDATION §Per-Task Verification Map)

2 randomly selected Tier-A/B-relevant claims re-verified by reading the full surrounding function body:

### Re-check 1 — Row 4: main.ts:111 "Ensure materialized view indexes exist (idempotent)"

Re-read `ensureViewIndexes` (view-refresh.ts:44-55) full body, then walked `VIEW_UNIQUE_INDEXES` (views.ts:105-110) + `ADDITIONAL_INDEXES` (indexes.ts:6-25). All 4 view indexes prefixed `CREATE UNIQUE INDEX IF NOT EXISTS`; all 9 additional indexes prefixed `CREATE INDEX IF NOT EXISTS`. 13/13 truly idempotent. Note the function throws on any error (line 51 `throw err`) — "idempotent" remains correct (an existing index will not cause IF NOT EXISTS to raise; other index-SQL errors are unrelated to idempotency and properly fatal at startup). **Verdict confirmed: PASS.**

### Re-check 2 — Row 9 (FAIL): new-events.ts:4-5 "No upsert, no composite logic"

Re-read new-events.ts in full. Confirmed: `handleDeityPassPurchased`, `handleGameOverDrained`, `handleFinalSwept`, `handleBoonConsumed`, admin handlers, `handleLinkEthFeedUpdated` all present. Of these, only `handleGameOverDrained` contains `.onConflictDoUpdate` (lines 67-96, writing to `prize_pools`). The contradiction is real and non-trivial — the file-level claim misstates the surface area by exactly one handler/one side-effect. **Verdict confirmed: FAIL, Tier B, F-28-227-201.**

## Scope-Boundary Reminder

This plan audited **COMMENT correctness only**. Cursor rewind, reorg-overwrite ordering, view-refresh debounce, and backfill-gate boundary **behavior** correctness are Phase 228 territory. The "Deferred to Phase 228" section above is a direct handoff for IDX-04 / IDX-05 planning.

## Acceptance Criteria Check

- [x] All 8 RESEARCH-seed rows have a PASS/FAIL verdict (all PASS).
- [x] Keyword sweep expansion executed across `indexer/` + `handlers/`; 7 additional rows classified (5 PASS + 2 FAIL).
- [x] Every FAIL row emits an `F-28-227-2NN` finding stub in the reserved block.
- [x] Tier C count recorded (0 systemic).
- [x] "Deferred to Phase 228" section written (4 entries).
- [x] Zero writes outside `.planning/phases/227-indexer-event-processing-correctness/`.
- [x] D-227-10 scope guard applied — all comment claims whose accuracy depended on state-machine behavior were either passed as-written (comment is technically true) and deferred, or failed on pure drift grounds (F-28-227-201/202).

## Self-Check: PASSED

- File `.planning/phases/227-indexer-event-processing-correctness/227-03-INDEXER-COMMENT-AUDIT.md` exists ✓
- File `.planning/phases/227-indexer-event-processing-correctness/227-03-SUMMARY.md` exists ✓
- Task 1 commit `4ab20be4` present in `git log` ✓
- Finding IDs `F-28-227-201` / `F-28-227-202` used; next-available `F-28-227-203`; no collision with 227-01 (01-block) or 227-02 (101-block) ✓
- 8 seed rows verified via grep (12 citation hits, ≥8) ✓
- 2 spot-rechecks logged ✓
- Phase 228 handoff section present (4 entries) ✓

## PLAN COMPLETE
