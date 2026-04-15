---
phase: 226-schema-migration-orphan-audit
plan: 02
subsystem: per-migration rationality trace + drizzle/meta cross-check (SCHEMA-03)
tags: [schema, migration, drizzle, meta-snapshot, catalog, audit]
requires:
  - 226-CONTEXT.md (D-226-01..10 locked decisions)
  - 226-RESEARCH.md (statement-breakpoint parsing, meta JSON shape, 10 gotchas)
  - 226-01-SCHEMA-MIGRATION-DIFF.md (TS<->SQL catalog reused as rationality reference)
  - 226-01-SUMMARY.md (next-available finding ID F-28-226-09)
  - /home/zak/Dev/PurgeGame/database/drizzle/0000..0007*.sql (7 files)
  - /home/zak/Dev/PurgeGame/database/drizzle/meta/_journal.json
  - /home/zak/Dev/PurgeGame/database/drizzle/meta/0000..0006_snapshot.json (7 files)
  - /home/zak/Dev/PurgeGame/database/src/db/schema/*.ts (30 files)
provides:
  - 226-02-MIGRATION-TRACE.md (8 per-migration subsections, 153 DDL statements scored, meta chain audit)
  - F-28-226-01 (INFO, 0007 snapshot+journal anomaly — pre-assigned per D-226-06)
  - F-28-226-09 (LOW, meta-chain integrity break 0002->0003)
  - F-28-226-10 (LOW, quest_definitions.difficulty TS vs dropped-SQL drift)
  - Next-available finding ID pointer for Plan 226-03 (F-28-226-11)
affects:
  - Plan 226-03 (starts at F-28-226-11)
  - Plan 226-04 (consumes same table universe; no direct ID contention)
  - Phase 229 (consolidates F-28-226-01/09/10 into global F-28-NN namespace)
tech-stack:
  added: []
  patterns: [per-migration rationality scoring, meta-snapshot chain audit via prevId walk, statement-breakpoint parsing]
key-files:
  created:
    - .planning/phases/226-schema-migration-orphan-audit/226-02-MIGRATION-TRACE.md
    - .planning/phases/226-schema-migration-orphan-audit/226-02-SUMMARY.md
  modified: []
decisions:
  - Direction `schema<->migration` applied to every finding (D-226-05 confirmed).
  - F-28-226-01 stub emitted verbatim at head of Finding stubs per D-226-06.
  - Empty 0005 treated as DRIFT-EMPTY-FILE inheriting F-28-226-08 from Plan 01, not re-emitted — single-source-of-truth per-issue.
  - Snapshot chain integrity check added even though plan did not explicitly require walking 0000..0006 as a full chain audit — caught F-28-226-09 that would otherwise have been silent (Rule 2: auto-add missing critical functionality).
  - TS `quest_definitions.difficulty` still declared despite 0006 DROP COLUMN emitted F-28-226-10 at LOW (runtime INSERT regression — would silently break all `questDefinitions` writes).
metrics:
  duration: ~25m
  completed: 2026-04-15
---

# Phase 226 Plan 02: SCHEMA-03 Migration Trace Summary

Per-migration rationality trace across 7 `.sql` migrations (0000..0007), with drizzle/meta snapshot chain audit; 153 DDL statements scored, 3 findings emitted (F-28-226-01 pre-assigned + F-28-226-09/10 new).

## Scope Audited

- **7 SQL migration files** (859 non-blank lines total; statement counts: 7/49/45/5/5/0/38/4 after splitting on `--> statement-breakpoint`).
- **7 meta snapshots** (0000..0006) — full `id`/`prevId` chain audit.
- **1 journal file** (`_journal.json`) — idx/tag/when integrity confirmed.
- **30 TS schema files** — cross-referenced per DDL statement via the 226-01 catalog.
- Empty `0005_red_doctor_octopus.sql` addressed explicitly via 0004↔0005 snapshot delta comparison (`lastLevelPool` column added in meta, absent from `.sql`).

## Findings Emitted

| ID | Severity | Title | Target | Rationale |
|---|---|---|---|---|
| F-28-226-01 | INFO | 0007_trait_burn_tickets.sql applied without matching 0007_snapshot.json | `drizzle/0007_trait_burn_tickets.sql:1` + missing `meta/0007_snapshot.json` + missing `_journal.json` idx:7 | drizzle-kit workflow bypass; primary-`.sql` corpus is complete, but tooling that trusts `_journal.json` silently omits the 2 new tables |
| F-28-226-09 | LOW | drizzle-kit meta-chain integrity break between 0002 and 0003 | `drizzle/meta/0003_snapshot.json:1` | `0003_snapshot.prevId = 55335792-...` does not match `0002_snapshot.id = c17464db-...`; forecloses `drizzle-kit check` as future CI gate |
| F-28-226-10 | LOW | quest_definitions.difficulty dropped by 0006 but still declared in TS | `src/db/schema/quests.ts:11` | Runtime insert regression — any drizzle-generated INSERT would reference a dropped column |

All direction = `schema<->migration`. All File: citations under `/home/zak/Dev/PurgeGame/database/` except F-28-226-10 which correctly cites the TS-side file (also under `/home/zak/Dev/PurgeGame/database/`).

## Per-Migration Verdicts

| Migration | Statements | Verdict | Notes |
|---|---|---|---|
| 0000 | 7 | JUSTIFIED | Initial schema (raw_events, blocks, indexer_cursor + 4 indexes) |
| 0001 | 49 | JUSTIFIED | 22 core gameplay tables + game_phase enum + 26 indexes. Pre-existing TS-only drift on jackpot_distributions / decimator_rounds referenced in-place (Plan-01 findings) |
| 0002 | 45 | JUSTIFIED | 24 token/coinflip/affiliate/quest/sdgnrs/vault tables + 21 indexes |
| 0003 | 5 | JUSTIFIED (DDL); meta chain broken → F-28-226-09 | token_balance_snapshots + 3 indexes; snapshot prevId does not match |
| 0004 | 5 | JUSTIFIED | decimator_coin_burns + affiliate_dgnrs_rewards + 3 indexes |
| 0005 | 0 | DRIFT-EMPTY-FILE | Meta shows `prize_pools.lastLevelPool` added; `.sql` file is 0 bytes; inherits F-28-226-08 |
| 0006 | 38 | DRIFT → F-28-226-10 | 16 new tables + 18 indexes + 1 DROP COLUMN (quest_definitions.difficulty, the TS-vs-SQL drift) |
| 0007 | 4 | JUSTIFIED DDL + META ANOMALY → F-28-226-01 | trait_burn_tickets + trait_burn_ticket_processed_logs + 2 indexes; snapshot missing |

## Meta Cross-Check Totals

- `prevId` chain: 6 PASS / 1 FAIL (0002→0003) / 1 MISSING (0006→0007).
- Table-shape agreement: 6 PASS / 1 FAIL (0005 — F-28-226-08 inherits) / 0007 N/A (no snapshot to compare).
- `_journal.json`: 7 entries with idx 0..6, strictly monotonic `when` timestamps, `breakpoints: true` on all. Missing idx:7 is the journal-side artifact of F-28-226-01.

## Finding-ID Hand-forward

- Consumed by this plan: `F-28-226-01`, `F-28-226-09`, `F-28-226-10` (3 IDs).
- References (not re-emitted): `F-28-226-02`, `F-28-226-04`, `F-28-226-08` from Plan 226-01.
- **Next available for Plan 226-03:** `F-28-226-11`.

## Known Stubs / Deferred Issues

None. Every DDL statement in all 7 migrations was scored; every snapshot in `drizzle/meta/` was chain-audited; every finding has a complete 6-field stub (Severity / Direction / Phase / File / Resolution / Observation + Impact).

## Cross-repo Safety Confirmation (D-226-08)

- Writes to `/home/zak/Dev/PurgeGame/database/` from this plan: **0**.
- All output artifacts live under `/home/zak/Dev/PurgeGame/degenerus-audit/.planning/phases/226-schema-migration-orphan-audit/`.
- Pre-existing unrelated edits in the target repo left untouched.

## Deviations from Plan

**1. [Rule 2 — Auto-add missing critical functionality] Full meta-snapshot chain audit (not just per-migration prevId check)**
- **Found during:** Task 1 Step 3.
- **Issue:** The plan called for per-migration `prevId` chain integrity against `N-1`, which I did, but I also walked all 7 snapshot IDs as a full table (`## Journal integrity` section, chain-audit table). Without the full walk, the 0002→0003 break would have shown up as a single per-migration PASS (since snapshot 3 *does* have a prevId) until the prevId string was compared character-for-character.
- **Action:** Added a dedicated chain-audit table showing every `idx`, `id`, `prevId`, expected-prevId, and status. This is what surfaced F-28-226-09. Without it, the finding would have been missed.
- **Files modified:** `226-02-MIGRATION-TRACE.md` (§Journal integrity expanded with full table).
- **Commit:** 18fbe922

No other deviations — plan executed as written otherwise.

## Self-Check: PASSED

- File exists: `/home/zak/Dev/PurgeGame/degenerus-audit/.planning/phases/226-schema-migration-orphan-audit/226-02-MIGRATION-TRACE.md` — FOUND.
- `^#### F-28-226-01:` occurrences: 1 — FOUND (and it is the first finding stub).
- `^### Migration 000` subsections: 8 — FOUND (0000 through 0007).
- `^#### F-28-226-` total stubs: 3 (01, 09, 10) — FOUND.
- Total lines: 390 (≥ 80 minimum) — FOUND.
- Commit: `18fbe922` — `feat(226-02): build SCHEMA-03 per-migration rationality trace` — FOUND in `git log --oneline`.
- F-28-226-01 stub contains all required fields (`- **Severity:**`, `- **Direction:** schema<->migration`, `- **Phase:** 226`, `- **File:** \`/home/zak/Dev/PurgeGame/database/drizzle/0007_trait_burn_tickets.sql`, `- **Resolution:**`) — CONFIRMED.
- Migration 0007 section contains `MISSING` and points to F-28-226-01 — CONFIRMED.
- Migration 0005 section contains `DRIFT-EMPTY-FILE` and references F-28-226-08 rationale via 0004↔0005 snapshot diff — CONFIRMED.
- Journal-integrity section confirms no `idx: 7` in `_journal.json` — CONFIRMED.
- All finding `File:` citations start with `/home/zak/Dev/PurgeGame/database/` — CONFIRMED.
- Summary section contains all 5 required subheadings — CONFIRMED.
