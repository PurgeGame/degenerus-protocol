---
phase: 226-schema-migration-orphan-audit
plan: 04
subsystem: audit/schema
tags: [schema, orphan-scan, drizzle, database-audit]
requires: [SCHEMA-04]
provides: [226-04-ORPHAN-TABLES.md]
affects: []
tech-stack:
  added: []
  patterns: [bidirectional-orphan-scan, pattern3-raw-sql-match, pattern4-binding-word-boundary, barrel-reexport-universe]
key-files:
  created:
    - .planning/phases/226-schema-migration-orphan-audit/226-04-ORPHAN-TABLES.md
    - .planning/phases/226-schema-migration-orphan-audit/226-04-SUMMARY.md
  modified: []
decisions:
  - "Universe = 75 entries (71 pgTable + 4 pgMaterializedView) from src/db/schema/index.ts barrel; enums and non-table constants excluded."
  - "views.ts and indexes.ts raw-SQL template strings count as LEGITIMATE references per false-positive traps #1–#2."
  - "__tests__/, cli/, and api/plugins/ are OUT of the 5 scoped surfaces; references there do not count toward orphan rescue but were spot-checked."
metrics:
  duration: "~15m"
  completed: "2026-04-15"
---

# Phase 226 Plan 04: SCHEMA-04 Orphan Table + Code-Reference Scan Summary

**One-liner:** Bidirectional orphan + code-reference scan across 75 Drizzle schema entries (71 tables + 4 materialized views) and 77 import sites in handlers/indexer/routes/views.ts/indexes.ts — zero orphans, zero missing-in-schema, SCHEMA-04 PASS.

## What Shipped

- `226-04-ORPHAN-TABLES.md` (catalog) — full table universe, schema→code reference counts (pattern-4 binding hits + pattern-3 raw-SQL pg-name hits), code→schema import resolution table, raw-SQL table-name validity check, finding-stub section (empty), and final `## Summary` with 7 required subsections.
- Reserved finding-ID block `F-28-226-301..` declared but NOT consumed — zero findings produced.

## Scan Results

- **Universe size:** 75 (71 `pgTable` + 4 `pgMaterializedView`).
- **Schema-side orphans:** 0. Minimum reference count across all 75 entries = 5.
- **Code-side missing-in-schema references:** 0.
- **Import sites scanned:** 77 (all resolved, 100%).
- **Raw-SQL unresolved identifiers:** 0 (13 distinct PG table names in `sql\`...\`` blocks, all resolve; 3 non-table identifiers — `information_schema.columns`, `day_range`, `ranked` — correctly excluded as system catalog / CTE aliases).
- **Finding IDs consumed:** none (reserved block `F-28-226-301..` unused).
- **Severity distribution:** 0 INFO, 0 LOW.

## False-Positive Traps Handled

All six traps from 226-RESEARCH.md §Orphan Scan honored:

1. `indexes.ts` raw-SQL → counted as legitimate references (9 PG names cross-verified).
2. `views.ts` raw-SQL JOINs → counted as legitimate references (6 PG names cross-verified).
3. Comment-text hits → filtered via word-boundary + manual inspection (no comment-only hits surfaced).
4. Barrel-import-without-use → binding USE sites (not import lines) counted.
5. Enum / non-table exports (`gamePhaseEnum`, `ALL_VIEWS`, `VIEW_UNIQUE_INDEXES`, `ADDITIONAL_INDEXES`) → excluded from universe.
6. `indexes.ts` itself not in `drizzle.config.ts` → still counted as a legitimate orphan-scan SOURCE per D-226-03.

## Deviations from Plan

None — plan executed exactly as written. All acceptance criteria met, all scoped surfaces scanned, all false-positive traps respected, D-226-08 cross-repo READ-only constraint honored (zero writes to `/home/zak/Dev/PurgeGame/database/`).

## Key Decisions Made

- Reserved finding-ID block `F-28-226-301..` per wave-2 parallel execution safety (disjoint from 226-02/03 counters); recorded in `## Summary` of catalog.
- `__tests__/` directories under handlers and api treated as OUT-of-scope for orphan-rescue (they are not one of the 5 scoped surfaces per D-226-03), but spot-checked for the single table with lowest in-scope p4 file count (`dailyWinningTraits` — confirmed 1 production handler write + 3 raw-SQL reads in `api/routes/game.ts`, comfortably above the orphan threshold).

## Files Modified

### Created
- `.planning/phases/226-schema-migration-orphan-audit/226-04-ORPHAN-TABLES.md`
- `.planning/phases/226-schema-migration-orphan-audit/226-04-SUMMARY.md`

### Modified
- (none)

## Verification

- File present: YES.
- Required section headings (`^## `): 10 present (Preamble, Scope surfaces, False-positive traps handled, Table universe, Schema → code references, Code → schema imports, Raw-SQL table-name references, Finding stubs, Summary, + Self-Check).
- `## Summary` subheadings: 7 required (Universe size, Schema-side orphan count, Code-side missing-in-schema count, Import resolution totals, Raw-SQL unresolved-identifier count, Finding IDs allocated, Severity distribution) — all present.
- Universe row count (75) matches `pgTable` + `pgMaterializedView` grep results.
- Zero writes to audit-target repo (D-226-08 OK).

## Self-Check: PASSED

- Catalog artifact created and committed to `.planning/phases/226-schema-migration-orphan-audit/`.
- Structural requirements from plan `<acceptance_criteria>` satisfied.
- Finding-ID reserved block explicitly noted as unconsumed.
- Summary is the last content section before the Self-Check footer.
