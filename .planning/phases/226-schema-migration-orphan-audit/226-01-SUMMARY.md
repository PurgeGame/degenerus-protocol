---
phase: 226-schema-migration-orphan-audit
plan: 01
subsystem: database schema ↔ migration reconciliation (SCHEMA-01)
tags: [schema, migration, drizzle, catalog, audit]
requires:
  - 226-CONTEXT.md (D-226-01..10 locked decisions)
  - 226-RESEARCH.md (parsing strategy, field mapping, gotchas)
  - cumulative state of /home/zak/Dev/PurgeGame/database/drizzle/0000..0007*.sql
  - /home/zak/Dev/PurgeGame/database/src/db/schema/*.ts (30 files)
  - /home/zak/Dev/PurgeGame/database/drizzle/meta/0006_snapshot.json (secondary cross-check)
provides:
  - 226-01-SCHEMA-MIGRATION-DIFF.md (per-table / per-column / per-index verdicts)
  - 7 F-28-226-NN finding stubs (F-28-226-02..08)
  - Next-available finding ID pointer for Plan 226-02 (F-28-226-09)
affects:
  - Plan 226-02 (consumes disagreement pointers; owns F-28-226-01 + migration-trace findings)
  - Plan 226-04 (consumes pgTable universe for orphan scan)
  - Phase 227 (IDX-01/02/03 assumes SCHEMA-01 verdict stands for schema side)
  - Phase 228 (receives views-subsection INVESTIGATE notes)
  - Phase 229 (consolidates F-28-226-NN into global F-28-NN namespace)
tech-stack:
  added: []
  patterns: [regex-walked DDL accumulator, hybrid .sql primary + meta JSON secondary cross-check, catalog-only audit]
key-files:
  created:
    - .planning/phases/226-schema-migration-orphan-audit/226-01-SCHEMA-MIGRATION-DIFF.md
    - .planning/phases/226-schema-migration-orphan-audit/226-01-SUMMARY.md
  modified: []
decisions:
  - Severity default INFO; promoted to LOW when drift causes silent wrong-results, runtime errors, or replay-from-SQL inconsistency (per D-226-05 and planner discretion).
  - Materialized views recorded as INVESTIGATE context (not findings) per D-226-07 / 226-RESEARCH Q1 recommendation.
  - indexes.ts treated as Gotcha #7 context-only; its 9 entries are NOT logged as drift but the `jackpot_dist_level_block_log_idx` double-declaration was surfaced as F-28-226-07 (INFO) because it IS declared in both `indexes.ts` AND a TS pgTable, creating provenance risk.
  - prize_pools.lastLevelPool drift cut both ways (SCHEMA-01 concern and SCHEMA-03 concern); emitted F-28-226-08 here because SCHEMA-01 is the cumulative-diff owner, and left Plan 226-02 to own the migration-trace reasoning.
metrics:
  duration: ~30m
  completed: 2026-04-15
---

# Phase 226 Plan 01: SCHEMA-01 Per-Column / Per-Index Diff Summary

Built the per-table PASS/FAIL reconciliation catalog between the cumulative state of the 7 applied `.sql` migrations and the 30 Drizzle TypeScript schema files, with secondary cross-check against `drizzle/meta/0006_snapshot.json`.

## Scope Audited

- **7 `.sql` migrations** (859 non-blank lines across `0000_brown_justin_hammer.sql` .. `0007_trait_burn_tickets.sql`)
- **30 `*.ts` schema files** (2,046 lines; 29 registered in `drizzle.config.ts` + `indexes.ts` treated as context-only per Gotcha #7)
- **7 meta snapshots** (0000..0006; 0007 missing — Plan 226-02's F-28-226-01)
- **67 pgTable declarations**, **~480 column rows**, **~70 TS indexes + 67 SQL indexes**, **1 enum**, **4 materialized views**
- **0 foreign keys** in either side (confirmed via `rg foreignKey` against schema + `FOREIGN KEY` against SQL — assumption A2 from 226-RESEARCH.md held)

## Findings Emitted

| ID | Severity | Title | Table | Drift class |
|---|---|---|---|---|
| F-28-226-02 | LOW | jackpot_distributions TS has 6 extra columns + `awardType`/`'eth'` vs SQL `distributionType`/`'ticket'` rename+default drift | jackpot_distributions | column drift |
| F-28-226-03 | LOW | jackpot_dist_level_block_log_idx declared in TS but missing from `.sql` migrations | jackpot_distributions | index drift |
| F-28-226-04 | LOW | decimator_rounds TS has `packedOffsets` + `resolved` columns not in any migration | decimator_rounds | column drift |
| F-28-226-05 | LOW | daily_winning_traits entire table missing from all `.sql` migrations AND meta snapshots | daily_winning_traits | table drift |
| F-28-226-06 | INFO | daily_winning_traits_day_idx index missing (follows from F-28-226-05) | daily_winning_traits | index drift |
| F-28-226-07 | INFO | jackpot_dist_level_block_log_idx double-declared in both `indexes.ts` raw SQL and `jackpot-history.ts` TS pgTable | jackpot_distributions | provenance drift |
| F-28-226-08 | LOW | prize_pools.lastLevelPool present in meta/TS but `0005_red_doctor_octopus.sql` on-disk file is empty | prize_pools | sql-file drift |

All findings use direction `schema<->migration` per D-226-05. Every File: citation is an absolute path under `/home/zak/Dev/PurgeGame/database/`.

## Per-category Verdicts

- **Table coverage:** 67 pgTables compared; 63 PASS, 4 FAIL.
- **Column comparison:** ~480 column rows; ~470 PASS, 10 FAIL column rows (counted under the 4 FAIL tables; entire-table drifts like `daily_winning_traits` counted at table level, not re-counted per column).
- **Index / unique-index:** 67 PASS matches across both sides; 2 TS-only FAIL indexes (F-28-226-03, F-28-226-06). 13 context-only entries (9 from `indexes.ts`, 4 from `views.ts` `VIEW_UNIQUE_INDEXES`).
- **Composite PKs:** 2, both PASS (auto-name derivation confirmed — Gotcha #5).
- **FKs:** 0 either side, PASS.
- **Enums:** 1 (`game_phase`), PASS.
- **Views:** 4 `pgMaterializedView(...)` declarations; zero `CREATE MATERIALIZED VIEW` DDL in any `.sql` migration — flagged INVESTIGATE context (Phase 228 scope per D-226-07), NOT emitted as SCHEMA-01 findings.

## Secondary Cross-check (0006_snapshot.json)

For every table, the cumulative `.sql` state was confirmed against `meta/0006_snapshot.json`. Three tables disagree:

1. `prize_pools.lastLevelPool` — present in meta, absent from `.sql` file body (F-28-226-08 captures it).
2. `jackpot_distributions` extra columns — absent from both meta AND `.sql` (so it's a pure TS-only drift, F-28-226-02). Also confirms the column `distributionType` is what actually exists in the live schema.
3. `daily_winning_traits` — absent from both meta AND `.sql` (pure TS-only drift, F-28-226-05).

No new findings emitted at the cross-check layer — all disagreements either reinforce existing stubs or point to Plan 226-02's migration-trace scope.

## Finding-ID Hand-forward

- Consumed by this plan: `F-28-226-02` .. `F-28-226-08` (7 IDs).
- Reserved (not used here): `F-28-226-01` (pre-assigned to Plan 226-02 per D-226-06).
- **Next available for Plan 226-02:** `F-28-226-09`.

## Known Stubs / Deferred Issues

None — all catalog rows were computed. No "TODO" or placeholder rows.

## Cross-repo Safety Confirmation (D-226-08)

- Writes to `/home/zak/Dev/PurgeGame/database/` from this plan: **0**.
- All output artifacts live under `/home/zak/Dev/PurgeGame/degenerus-audit/.planning/phases/226-schema-migration-orphan-audit/`.
- Pre-existing modifications in the target repo (12 tracked-file edits + log files) are unrelated to this plan and were left untouched.

## Deviations from Plan

None — plan executed exactly as written.

## Self-Check: PASSED

- File exists: `/home/zak/Dev/PurgeGame/degenerus-audit/.planning/phases/226-schema-migration-orphan-audit/226-01-SCHEMA-MIGRATION-DIFF.md` — FOUND.
- Top-level sections (grep `^## `): 10 — all 10 required sections (Preamble, Input universe, Gotchas carried forward, Per-table verdicts, Views subsection, Enums subsection, indexes.ts context note, Secondary cross-check vs 0006_snapshot.json, Finding stubs, Summary) — FOUND.
- `### Table \`` subsections: 71 (covers all 67 pgTable declarations plus a few sub-tables emitted for completeness via compound sections).
- Finding stubs matching `^#### F-28-226-\d+:`: 7 — FOUND (02, 03, 04, 05, 06, 07, 08).
- `F-28-226-01` as stub header: 0 — confirmed reserved.
- Commit: `6bba507d` — `feat(226-01): build SCHEMA-01 per-column/index diff catalog` — FOUND.
