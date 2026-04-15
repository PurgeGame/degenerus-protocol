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
| mv_player_summary | /home/zak/Dev/PurgeGame/database/src/db/schema/views.ts:16-40 | main.ts:214 via ALL_VIEWS loop | No | TBD-Task2 |
| mv_coinflip_top10 | /home/zak/Dev/PurgeGame/database/src/db/schema/views.ts:45-56 | main.ts:214 via ALL_VIEWS loop | No | TBD-Task2 |
| mv_affiliate_leaderboard | /home/zak/Dev/PurgeGame/database/src/db/schema/views.ts:61-72 | main.ts:214 via ALL_VIEWS loop | No | TBD-Task2 |
| mv_baf_top4 | /home/zak/Dev/PurgeGame/database/src/db/schema/views.ts:77-88 | main.ts:214 via ALL_VIEWS loop | No | TBD-Task2 |

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
| M9 | 227-deferral-3 | /home/zak/Dev/PurgeGame/database/src/indexer/view-refresh.ts:4-5 | "Refresh is non-fatal — a stale view for one block is acceptable" | try/catch per view; no metric/alert/retry | LOW — staleness bound is not "one block" under sustained failure | TBD-Task2 | TBD | TBD |
| M10 | — | /home/zak/Dev/PurgeGame/database/src/db/schema/views.ts:9-10 | "UNIQUE index to enable REFRESH CONCURRENTLY" | VIEW_UNIQUE_INDEXES × 4; all CREATE UNIQUE INDEX; view-refresh.ts calls .concurrently() | PASS | TBD | TBD | TBD |
| M11 | — | /home/zak/Dev/PurgeGame/database/src/indexer/view-refresh.ts:1-8 | "Called after each block batch commit (outside the transaction)" | Call at main.ts:214 is after `await db.transaction(...)` closes at :201 | PASS | TBD | TBD | TBD |
| M12 | — | (undocumented) | Per-view trigger granularity | All 4 views refreshed together, every trigger | INFO — design choice, no finding | TBD | TBD | TBD |
| V1 | info-context | /home/zak/Dev/PurgeGame/database/src/db/schema/views.ts:16-88 vs /home/zak/Dev/PurgeGame/database/drizzle/*.sql | views.ts declares 4 pgMaterializedView entries; no `CREATE MATERIALIZED VIEW` in any migration SQL (cited 226-01-SCHEMA-MIGRATION-DIFF.md:708-717) | Runtime materialization path unclear — drizzle-kit push/snapshot assumed | INFO — record context only; INFO-ACCEPTED or RESOLVED-CODE-FUTURE | TBD | TBD | TBD |

## SC-4 File-Touch Evidence

| Indexer file | Touched by 228-02? | Where |
|--------------|--------------------|-------|
| view-refresh.ts | ✓ | M9, M11, Trigger Map, Observability Inventory |
| main.ts | ✓ | Trigger Map (main.ts:112, :214), M11 cross-ref |
| views.ts (db/schema) | ✓ | M10, Trigger-to-View Mapping (4 rows), V1 |
