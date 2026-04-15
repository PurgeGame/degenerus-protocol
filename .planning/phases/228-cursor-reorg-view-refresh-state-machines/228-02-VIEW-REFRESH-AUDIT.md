# 228-02 View-Refresh Audit (IDX-05)

**Phase:** 228 | **Plan:** 02 | **Requirement:** IDX-05
**Deliverable for:** D-228-06 (228-02 deliverable)
**Finding block:** F-28-228-101+ (per D-228-10; disjoint from 228-01's F-28-228-01+)
**Severity taxonomy:** INFO / LOW / MEDIUM (per D-228-11)
**Cross-ref sources (D-228-08):** (1) in-source comments in view-refresh.ts + indexer/*.ts; (2) /home/zak/Dev/PurgeGame/database/src/db/schema/views.ts
**Out of scope:** downstream API consumers (per D-228-08 — Phase 224 already audited API routes)
**Scope:** cross-repo READ-only per D-228-01; catalog-only per D-228-02.
**Audit surface:** /home/zak/Dev/PurgeGame/database/src/indexer/view-refresh.ts + /home/zak/Dev/PurgeGame/database/src/db/schema/views.ts + /home/zak/Dev/PurgeGame/database/src/indexer/main.ts (trigger wiring at :112, :211-215)

## Absorbed Phase 227 Deferral (D-228-09)

| # | 227 deferral | File:line | Handled by row |
|---|--------------|-----------|----------------|
| 3 | view-refresh.ts:5 try/catch swallows refresh failures — only feedback is log.error | /home/zak/Dev/PurgeGame/database/src/indexer/view-refresh.ts:5 | M9 (annotated `227-deferral-3`); observability inventory table reproduced below |

## Trigger Map (exhaustive — from 228-RESEARCH.md §View-Refresh State Machine)

| Trigger site (File:line) | Condition | Views refreshed | Error handling | Debounce / rate-limit |
|--------------------------|-----------|-----------------|----------------|-----------------------|
| /home/zak/Dev/PurgeGame/database/src/indexer/main.ts:214 | `lag = Number(tip - batchEnd); lag <= config.batchSize` (follow-mode gate at main.ts:212-213) | ALL 4 via ALL_VIEWS loop at /home/zak/Dev/PurgeGame/database/src/indexer/view-refresh.ts:26-34 | per-view try/catch; log.error + continue | NONE |
| /home/zak/Dev/PurgeGame/database/src/indexer/main.ts:112 | Startup once (index bootstrap only; NOT a refresh trigger) | N/A — ensureViewIndexes | Fatal on error (throw) | N/A |

## Trigger-to-View Mapping (all 4 pgMaterializedViews per D-228-08 source 2)

| View name | views.ts definition | Triggered by | Per-view on-demand trigger? | Verdict |
|-----------|---------------------|--------------|------------------------------|---------|
| mv_player_summary | /home/zak/Dev/PurgeGame/database/src/db/schema/views.ts:16-40 | main.ts:214 via ALL_VIEWS loop (ALL_VIEWS[0] at views.ts:94) | No | PASS — trigger covers view |
| mv_coinflip_top10 | /home/zak/Dev/PurgeGame/database/src/db/schema/views.ts:45-56 | main.ts:214 via ALL_VIEWS loop (ALL_VIEWS[1] at views.ts:95) | No | PASS — trigger covers view |
| mv_affiliate_leaderboard | /home/zak/Dev/PurgeGame/database/src/db/schema/views.ts:61-72 | main.ts:214 via ALL_VIEWS loop (ALL_VIEWS[2] at views.ts:96) | No | PASS — trigger covers view |
| mv_baf_top4 | /home/zak/Dev/PurgeGame/database/src/db/schema/views.ts:77-88 | main.ts:214 via ALL_VIEWS loop (ALL_VIEWS[3] at views.ts:97) | No | PASS — trigger covers view |

## Observability Inventory (227-deferral-3 source)

| Channel | Present? | Notes |
|---------|----------|-------|
| log.error | ✓ | Pino-structured; `{view, err}` at view-refresh.ts:31 |
| Prometheus / metric counter | ✗ | None |
| Alert / PagerDuty / webhook | ✗ | None |
| Retry / backoff | ✗ | Only next follow-mode batch re-triggers |
| Per-view staleness timestamp in DB | ✗ | No view_refresh_state table |
| Health check / /healthz surface | ✗ | Not exposed |

## Audit Rows (M-matrix — verbatim from 228-RESEARCH.md)

| Row ID | Annotations | File:line | Claim | Code behavior | Expected verdict | Final verdict | Rationale | Finding ID (if FAIL/LOW) |
|--------|-------------|-----------|-------|---------------|------------------|---------------|-----------|---------------------------|
| M9 | 227-deferral-3 | /home/zak/Dev/PurgeGame/database/src/indexer/view-refresh.ts:4-5 | "Refresh is non-fatal — a stale view for one block is acceptable" | try/catch per view; no metric/alert/retry | LOW — staleness bound is not "one block" under sustained failure | PASS-with-LOW | Comment asserts "one block" as the staleness bound, but the implementation (view-refresh.ts:26-34) swallows errors with only `log.error` as signal. Under sustained refresh failure there is no metric, retry, alert, or DB staleness timestamp (see Observability Inventory — 5 of 6 channels absent). Best-case staleness is ≤ one batch; worst-case is indefinite. | F-28-228-101 |
| M10 | — | /home/zak/Dev/PurgeGame/database/src/db/schema/views.ts:9-10 | "UNIQUE index to enable REFRESH CONCURRENTLY" | VIEW_UNIQUE_INDEXES × 4; all CREATE UNIQUE INDEX; view-refresh.ts calls .concurrently() | PASS | PASS | Re-verified: views.ts:105-110 declares exactly 4 `CREATE UNIQUE INDEX IF NOT EXISTS` entries, one per materialized view (mv_player_summary_player_idx, mv_coinflip_top10_day_rank_idx, mv_affiliate_leaderboard_level_rank_idx, mv_baf_top4_level_rank_idx). view-refresh.ts:29 invokes `.concurrently()` inside the ALL_VIEWS loop; ensureViewIndexes (view-refresh.ts:44-55) applies all 4 indexes at startup before the indexer loop begins (main.ts:112). Precondition for CONCURRENTLY is satisfied. | — |
| M11 | — | /home/zak/Dev/PurgeGame/database/src/indexer/view-refresh.ts:1-8 | "Called after each block batch commit (outside the transaction)" | Call at main.ts:214 is after `await db.transaction(...)` closes at :201 | PASS | PASS | Re-verified: `await db.transaction(async (tx) => { ... })` opens at main.ts:188 and closes at :201. The refresh site at main.ts:214 passes `db` (not `tx`) and is guarded by `if (lag <= config.batchSize)` at :213. Execution reaches :214 only after the transaction has awaited to completion, so refresh runs outside the tx as documented. | — |
| M12 | — | (undocumented) | Per-view trigger granularity | All 4 views refreshed together, every trigger | INFO — design choice, no finding | PASS-with-INFO | view-refresh.ts:26-34 iterates `ALL_VIEWS` unconditionally; there is no per-view conditional trigger, debounce, or selective refresh. This is an intentional design choice (simplicity over granularity) — refresh of one view does not depend on events affecting that specific view. Not a defect under D-228-11 severity thresholds; documented here for Phase 229 consolidation context. No finding emitted. | — |
| V1 | info-context | /home/zak/Dev/PurgeGame/database/src/db/schema/views.ts:16-88 vs /home/zak/Dev/PurgeGame/database/drizzle/*.sql | views.ts declares 4 pgMaterializedView entries; no `CREATE MATERIALIZED VIEW` in any migration SQL (cited 226-01-SCHEMA-MIGRATION-DIFF.md:708-717) | Runtime materialization path unclear — drizzle-kit push/snapshot assumed | INFO — record context only; INFO-ACCEPTED or RESOLVED-CODE-FUTURE | INFO-ACCEPTED | Per 226-01-SCHEMA-MIGRATION-DIFF.md:708-717 and :778, all 4 pgMaterializedView declarations in views.ts (mv_player_summary:16, mv_coinflip_top10:45, mv_affiliate_leaderboard:61, mv_baf_top4:77) have no matching `CREATE MATERIALIZED VIEW` in any `.sql` migration file; runtime path is presumed drizzle-kit push/snapshot-replay. Per D-228-08 handoff this is recorded as INFO context, not a 228-02 finding — upstream migration-trace concern. | — |

## SC-4 File-Touch Evidence

| Indexer file | Touched by 228-02? | Where |
|--------------|--------------------|-------|
| view-refresh.ts | ✓ | M9, M11, Trigger Map, Observability Inventory |
| main.ts | ✓ | Trigger Map (main.ts:112, :214), M11 cross-ref |
| views.ts (db/schema) | ✓ | M10, Trigger-to-View Mapping (4 rows), V1 |

## Cross-Reference Validation (D-228-08 two sources)

### Source 1 — In-source comments (view-refresh.ts + indexer/*.ts)

Grep `rg -n 'stale|non-fatal|concurrently|refresh' /home/zak/Dev/PurgeGame/database/src/indexer/view-refresh.ts` yields the following hits (re-verified 2026-04-15 by direct Read):

| File:line | Comment / code token | Mapped to audit row |
|-----------|----------------------|---------------------|
| view-refresh.ts:2 | "Materialized view refresh logic" (header) | M11 |
| view-refresh.ts:4-5 | "Called after each block batch commit (outside the transaction)…Refresh is non-fatal — a stale view for one block is acceptable" | M9 + M11 |
| view-refresh.ts:8-9 | "bootstrapping UNIQUE indexes…required for REFRESH CONCURRENTLY" | M10 |
| view-refresh.ts:21 | "Refresh all materialized views concurrently" | M10 |
| view-refresh.ts:22 | "Non-fatal: logs errors and continues to next view" | M9 |
| view-refresh.ts:29 | `db.refreshMaterializedView(view).concurrently()` | M10 |
| view-refresh.ts:31 | `log.error({ view: name, err }, 'Failed to refresh materialized view')` | M9, Observability Inventory |
| main.ts:211 | "Refresh materialized views (skip during backfill to avoid redundant work)" | Trigger Map |

Every hit corresponds to an Audit Row; no orphan comment.

### Source 2 — Schema `views.ts` pgMaterializedView declarations

Grep `rg -n 'pgMaterializedView' /home/zak/Dev/PurgeGame/database/src/db/schema/views.ts` yields exactly 4 hits (re-verified 2026-04-15 by direct Read):

| File:line | View name | Trigger-to-View Mapping row |
|-----------|-----------|------------------------------|
| views.ts:16 | mv_player_summary | row 1 ✓ |
| views.ts:45 | mv_coinflip_top10 | row 2 ✓ |
| views.ts:61 | mv_affiliate_leaderboard | row 3 ✓ |
| views.ts:77 | mv_baf_top4 | row 4 ✓ |

Count matches (4 declarations ↔ 4 mapping rows). No orphan view, no extraneous mapping. `ALL_VIEWS` registry at views.ts:93-98 confirms the same 4 entries are iterated by view-refresh.ts:27.

## Spot-Recheck Log (per 228-VALIDATION.md sampling rate for 228-02: 2 of {M9, M10, M11, M12})

### Re-check 1 — M9 (view-refresh.ts:4-5 + :22 staleness claim)

Re-read `refreshMaterializedViews` (view-refresh.ts:26-34) full body including surrounding docstring (:20-25) and file header (:1-11). Confirmed:

- The try/catch sits inside a for-loop over ALL_VIEWS; each view is refreshed independently.
- On error, only `log.error({ view: name, err }, 'Failed to refresh materialized view')` fires (view-refresh.ts:31).
- No `throw`, no counter increment, no timestamp write, no retry state.
- The caller at main.ts:214 does not check any return value (function returns `Promise<void>`).
- Next trigger of `refreshMaterializedViews` is governed solely by the follow-mode gate at main.ts:213 (`lag <= config.batchSize`). There is no failure-driven re-trigger, no backoff, no dead-letter signal.

Worst-case staleness bound is therefore unbounded under sustained failure — contradicting "a stale view for one block is acceptable" which implicitly asserts ≤ 1 block. **Verdict confirmed: PASS-with-LOW; finding F-28-228-101 emitted.**

### Re-check 2 — M11 (view-refresh.ts:4 "outside the transaction" claim)

Re-read main.ts:188-215 (≥15 lines around cited trigger). Confirmed:

- `await db.transaction(async (tx: any) => { ... })` opens at main.ts:188 and awaits to completion at :201.
- `cursor = batchEnd` assignment at :203 happens after the tx resolves.
- The re-index short-circuit check at :206-209 may `break` the loop before refresh; when it does not, control proceeds to :211-215.
- At :213 the gate `lag <= config.batchSize` guards the refresh call at :214, which passes the top-level `db` — not `tx` — matching the docstring's explicit `@param db - Top-level Drizzle db instance (NOT a transaction)` (view-refresh.ts:24).

No code path exists that invokes `refreshMaterializedViews` inside the transaction callback. **Verdict confirmed: PASS.**

## Findings

#### F-28-228-101: Comment "stale view for one block is acceptable" misrepresents the sustained-failure staleness bound

- **Severity:** LOW
- **Direction:** comment→code
- **Phase:** 228
- **Requirement:** IDX-05
- **Origin row:** M9 (annotated `227-deferral-3`)
- **File:** /home/zak/Dev/PurgeGame/database/src/indexer/view-refresh.ts:4-5 (comment); /home/zak/Dev/PurgeGame/database/src/indexer/view-refresh.ts:30-32 (behavior)
- **Resolution (proposed):** RESOLVED-CODE-FUTURE
- **Evidence:** The per-view try/catch at view-refresh.ts:28-32 swallows refresh errors with only `log.error` as signal; there is no metric counter, no retry, no backoff, no DB staleness timestamp, no alert surface (Observability Inventory: 5 of 6 channels absent). Under sustained refresh failure the staleness bound becomes indefinite, not "one block". Resolves Phase 227 deferral #3. Per 228-CONTEXT.md Deferred Ideas, the alerting build-out is explicitly out of audit scope — finding documents the operational gap for downstream triage rather than proposing a fix within this phase.

## Verdict Counts

| Verdict | Count | Rows |
|---------|-------|------|
| PASS | 2 | M10, M11 |
| PASS-with-INFO | 1 | M12 |
| PASS-with-LOW | 1 | M9 |
| INFO-ACCEPTED | 1 | V1 |
| LOW | 0 | — |
| MEDIUM | 0 | — |

Trigger-to-View Mapping: 4/4 PASS (all 4 pgMaterializedViews are trigger-covered; no orphans).
