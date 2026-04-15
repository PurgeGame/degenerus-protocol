# Phase 226 Context: Schema, Migration & Orphan Audit

**Milestone:** v28.0 Database & API Intent Alignment Audit
**Phase number:** 226
**Phase name:** Schema, Migration & Orphan Audit
**Requirements:** SCHEMA-01, SCHEMA-02, SCHEMA-03, SCHEMA-04
**Date:** 2026-04-15

## Phase Boundary

**In scope for this phase:**

- **SCHEMA-01** — Every Drizzle table in `database/src/db/schema/*.ts` (29 files + `indexes.ts`) matches the columns/types/constraints/indexes produced by the cumulative application of `database/drizzle/*.sql` (7 applied migrations). Zero columns, FKs, or indexes present in one side and missing from the other.
- **SCHEMA-02** — Column comments (JSDoc or `.comment()` calls) on schema columns that describe purpose/units/nullability/FK semantics match the actual column definition. Tier A + Tier B threshold inherited from D-225-04 (material drift only).
- **SCHEMA-03** — Each of the 7 migration files represents a rational diff from its predecessor — every `ADD COLUMN`, `DROP COLUMN`, `ALTER`, index-add, or FK-add in `.sql` has a corresponding same-logical-unit change in `schema/*.ts`. Unjustified drift recorded as a finding candidate.
- **SCHEMA-04** — Bidirectional orphan scan: every table in `schema/*.ts` is referenced by at least one handler (`src/handlers/*.ts`) OR indexer file (`src/indexer/*.ts`) OR route file (`src/api/routes/*.ts`) OR view (`views.ts`); every table name referenced in code exists in the schema.

**Explicitly NOT in scope for this phase:**

- **SCHEMA-05** (views refresh/staleness semantics) — deferred future requirement. `views.ts` structural definition IS in scope (column shape must match), but view-refresh triggers / staleness semantics stay for Phase 228 + future.
- Indexer event-processing correctness — Phase 227 (IDX-01/02/03).
- Cursor/reorg/view-refresh state machines — Phase 228 (IDX-04/05).
- Database performance / query-plan tuning — out of milestone scope.
- Migration rollback coverage — deferred future (forward-only audit).
- `.env` / config file schema alignment — deferred future milestone.

## Current Observations (from scouting)

- **Schema files:** 30 TypeScript files in `database/src/db/schema/` (~1,187 lines total). 29 are registered in `drizzle.config.ts`; `indexes.ts` is NOT registered in drizzle-kit's schema list — potentially a drift signal.
- **Migration files:** 7 SQL migrations `0000_brown_justin_hammer.sql` through `0007_trait_burn_tickets.sql` in `database/drizzle/`.
- **Drizzle meta snapshots:** 7 snapshot JSON files `0000_snapshot.json` through `0006_snapshot.json` + `_journal.json` in `database/drizzle/meta/`. **Anomaly: `0007` SQL exists but no matching `0007_snapshot.json`.** The 7th migration was applied outside the normal `drizzle-kit generate` workflow — drizzle-kit's internal record is one migration behind reality.
- **drizzle.config.ts** — dialect PostgreSQL, 29 schema files explicitly listed; `indexes.ts` omitted.
- **Views:** `views.ts` (110 lines) defines materialized/regular views; `view-refresh.ts` in indexer triggers refreshes (out of scope — Phase 228).
- **No zod-to-drizzle or similar generator** — schema files are hand-authored TypeScript.

## Decisions

### D-226-01: Applied-state ground truth — hybrid cumulative .sql + drizzle/meta cross-check

The "applied state" baseline for comparison against `schema/*.ts` is built from **cumulative application of the 7 `.sql` migration files** (primary ground truth — this is what actually ran against Postgres), with **`drizzle/meta/*.json` snapshots loaded as a secondary cross-check** (Drizzle's internal record of what state each migration should have produced).

- **Primary diff:** cumulative `.sql` state ↔ `schema/*.ts` declared state.
- **Secondary cross-check:** cumulative `.sql` state ↔ `drizzle/meta/0006_snapshot.json`. Disagreements between these two "applied state" sources are themselves findings (drizzle-kit internal record vs. actual SQL) and feed into Plan 226-02.

**Rationale:**
- `.sql` is what actually executed; meta JSON is a projection of what drizzle-kit *thought* ran.
- The `0007` anomaly (SQL without meta snapshot) proves the two sources can diverge.
- Pure-file audit — zero infrastructure, no DB spin-up, no `drizzle-kit introspect` dependency.
- Keeps cross-repo READ-only constraint (D-225-07) intact.

**Claude's Discretion (per user):** user deferred the methodology choice entirely. This hybrid is the Claude-picked default.

### D-226-02: Four plans mirroring the four ROADMAP success criteria

| Plan | Requirement | Deliverable |
|---|---|---|
| 226-01 | SCHEMA-01 | `226-01-SCHEMA-MIGRATION-DIFF.md` — per-table, per-column/FK/index PASS/FAIL catalog |
| 226-02 | SCHEMA-03 | `226-02-MIGRATION-TRACE.md` — migration-by-migration diff rationale + drizzle-meta cross-check |
| 226-03 | SCHEMA-02 | `226-03-COLUMN-COMMENT-AUDIT.md` — Tier A/B material comment drift |
| 226-04 | SCHEMA-04 | `226-04-ORPHAN-TABLES.md` — bidirectional orphan + code-reference scan |

Same per-plan granularity shape used in Phase 225 (one plan per requirement). Plans can run sequentially or in parallel — 226-01 and 226-02 share tooling (both parse the same 7 `.sql` files + schema/*.ts), so they're natural neighbors. 226-03 depends only on schema files. 226-04 depends on schema/*.ts + handler/indexer/route/view files.

### D-226-03: Orphan scan — bidirectional, broad reach

SCHEMA-04 orphan scan covers both directions across all code surfaces that touch the database:

- **Schema → code direction:** every table defined in `schema/*.ts` must have at least one referrer in `src/handlers/*.ts` OR `src/indexer/*.ts` OR `src/api/routes/*.ts` OR `src/db/schema/views.ts` OR `src/db/schema/indexes.ts`. Tables with no referrer = orphan finding.
- **Code → schema direction:** every table name referenced in handler/indexer/route/view/index files (grepping for imports from `src/db/schema/` and for table names in query builders) must exist in the schema. Missing-in-schema = finding.

Views (`views.ts`) are treated as tables for orphan purposes — a view that nothing queries is still an orphan. View-refresh triggers are out of scope (Phase 228).

### D-226-04: Column-comment audit — Tier A/B threshold (inherited from D-225-04)

Apply the same Tier A (outright wrong) + Tier B (materially incomplete) threshold used in Phase 225. Skip Tier C (columns without comments — counted not enumerated) and Tier D (cosmetic drift — not flagged).

- **Tier A example:** column comment says "UNIX seconds" but type is `timestamp` (stores ISO datetime).
- **Tier B example:** column comment says "FK to players" but omits that it's nullable with a default of NULL.

### D-226-05: Default finding direction — `schema↔migration` (milestone's 4th mismatch type)

Per v28.0 milestone scope, this phase's findings default to direction `schema↔migration`. The mismatch subject determines the resolution target:

- **Drift in a drizzle-generated column** → RESOLVED-CODE in schema file (code is where Drizzle generates from — fix the schema).
- **Drift from a hand-authored migration** → case-by-case: if the migration reflects intended state and schema drifted, schema file is fixed (RESOLVED-CODE). If the migration is the drift, next migration fixes it (RESOLVED-CODE in new migration file).

Orphan findings (SCHEMA-04) default to direction `code↔schema` and resolution INFO-ACCEPTED (legitimate unused tables) or RESOLVED-CODE (remove the orphan, either side).

### D-226-06: `0007` snapshot anomaly → explicit finding in 226-02

`database/drizzle/0007_trait_burn_tickets.sql` applied without a matching `drizzle/meta/0007_snapshot.json`. This is already a confirmed artifact (not speculative). Plan 226-02 opens with this as `F-28-226-01` — drizzle-kit workflow bypass, direction `schema↔migration`, INFO severity, resolution RESOLVED-CODE (regenerate snapshot via `drizzle-kit generate --custom` or equivalent).

### D-226-07: `views.ts` in scope; SCHEMA-05 (refresh semantics) stays deferred

`views.ts` (110 lines) is audited in Phase 226 as part of SCHEMA-01 (structural alignment — column shapes of views match any SQL-level view definition in migrations) and SCHEMA-04 (orphan scan — views that nothing queries). View refresh / staleness semantics (SCHEMA-05 future) remain out of scope — those sit in `view-refresh.ts` and are Phase 228 territory.

### D-226-08: Cross-repo READ-only (inherited from D-225-07)

All reads target `/home/zak/Dev/PurgeGame/database/`. Zero writes to `database/`. Every finding `File:line` cites the absolute path inside `/home/zak/Dev/PurgeGame/database/`. Planning artifacts and findings live in `/home/zak/Dev/PurgeGame/degenerus-audit/.planning/phases/226-schema-migration-orphan-audit/`.

### D-226-09: Finding IDs F-28-226-NN, fresh counter from 01

Finding IDs this phase: `F-28-226-01` through `F-28-226-NN`. Global v28.0 pool continues from prior phases (224 used `F-28-224-01`, 225 used `F-28-225-01..22`). No gap continuation — 226 starts its own 01-NN sequence. Phase 229 consolidates all phase-prefixed IDs into the final `F-28-NN` flat namespace.

### D-226-10: Catalog-only; no runtime gate (inherited from D-224-01)

No CI / Makefile / npm-script gate shipped this phase. Deliverables are 4 catalog markdown files plus per-plan SUMMARY.md. If schema drift becomes a recurring class of bug, a gate can be backlogged for a future milestone — `drizzle-kit check` already exists upstream and would be the natural fit.

### Claude's Discretion

- **Exact ordering of 226-01 vs 226-02 execution** — both read the same files; planner decides if they run as waves or sequentially.
- **Severity promotion criteria for SCHEMA-01 findings** — apply Phase 225 caller-breaking heuristic; default INFO, LOW if a drift would cause silent data-corruption or a query to return wrong results.
- **Exact grep patterns for orphan scan code-side** — planner chooses between `import from '@/db/schema/tablename'`, raw table-name references, or SQL string pattern match (or all three).
- **Whether `indexes.ts` gets a special SCHEMA-01 mini-finding** — it's in the schema dir but not in drizzle.config.ts. Leaning: note it in 226-01 context, no standalone finding unless downstream analysis shows indexes drift as a result.

## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Upstream audit context (this milestone)

- `/home/zak/Dev/PurgeGame/degenerus-audit/.planning/ROADMAP.md` § Phase 226 — goal, success criteria, requirement map
- `/home/zak/Dev/PurgeGame/degenerus-audit/.planning/REQUIREMENTS.md` § SCHEMA-01..04 — full requirement text
- `/home/zak/Dev/PurgeGame/degenerus-audit/.planning/phases/224-api-route-openapi-alignment/224-CONTEXT.md` — catalog-only precedent (D-224-01), INFO severity default (D-224-04), cross-repo paths
- `/home/zak/Dev/PurgeGame/degenerus-audit/.planning/phases/225-api-handler-behavior-validation-schema-alignment/225-CONTEXT.md` — Tier A/B comment-audit threshold (D-225-04), cross-repo READ-only (D-225-07), finding-ID sequencing (D-225-06)

### Audit target (sibling repo)

- `/home/zak/Dev/PurgeGame/database/drizzle.config.ts` — canonical schema-file list (29 files); `indexes.ts` absence from this list is a scout observation
- `/home/zak/Dev/PurgeGame/database/drizzle/meta/_journal.json` — drizzle-kit's migration journal (authoritative record of what drizzle-kit tracked)
- `/home/zak/Dev/PurgeGame/database/drizzle/meta/0000_snapshot.json` through `0006_snapshot.json` — drizzle-kit's internal snapshot after each migration (secondary cross-check source, D-226-01)
- `/home/zak/Dev/PurgeGame/database/drizzle/0000_brown_justin_hammer.sql` through `0007_trait_burn_tickets.sql` — primary applied-state source (D-226-01)
- `/home/zak/Dev/PurgeGame/database/src/db/schema/*.ts` — 30 schema files (29 registered + `indexes.ts`); declared-state side of the diff
- `/home/zak/Dev/PurgeGame/database/src/handlers/*.ts` — 27 indexer event handlers (orphan scan code-reference source)
- `/home/zak/Dev/PurgeGame/database/src/indexer/*.ts` — indexer core (orphan scan source)
- `/home/zak/Dev/PurgeGame/database/src/api/routes/*.ts` — 8 route files (orphan scan source)

### External docs (for reference if planner wants tool awareness)

- Drizzle ORM docs — `drizzle-kit` migration lifecycle + meta snapshot format (planner may consult Context7 if deeper understanding needed)

## Existing Code Insights

### Reusable Assets

- **Catalog markdown format from Phases 224 + 225** — per-row tables with file:line, verdict, finding-stub refs. Tier A/B severity block. Re-use exactly.
- **Finding-stub header format** — `#### F-28-226-NN: {title}` with `- **Severity:**`, `- **Direction:**`, `- **Phase:**`, `- **File:** `, `- **Resolution:** ` (grep-compliant with v27.0 acceptance regex).
- **Cross-repo path prefix** — every finding cites `/home/zak/Dev/PurgeGame/database/...`.

### Established Patterns

- **Catalog-only phases** — no runtime gate, no code writes to audit target; v25.0/v26.0 precedent, reaffirmed in 224/225.
- **Sampling-with-expansion when scope is large** — D-225-03 pattern. Applies to 226-01 if per-column audit exceeds ~300 rows; planner decides sampling strategy.
- **Tier A/B comment threshold** — D-225-04 applied to 225-01 handler comments; same threshold re-used for 226-03 column comments.

### Integration Points

- **Phase 227 (IDX-01/02/03)** — consumes 226's finalized schema model. When 227 audits `event-processor.ts` arg-to-field mappings, it assumes the schema side is correct per 226.
- **Phase 228 (IDX-04/05)** — consumes `views.ts` structural audit from 226; adds refresh-trigger correctness on top.
- **Phase 229** — consolidates F-28-226-NN findings into global `F-28-NN` namespace for `audit/FINDINGS-v28.0.md`.

## Specific Ideas

- **`0007_trait_burn_tickets.sql` missing `0007_snapshot.json`** — first finding of the phase (F-28-226-01). Proves the comparison method choice (D-226-01) pays off — `.sql` as primary catches what meta JSON misses.
- **`indexes.ts` not in `drizzle.config.ts`** — noted as scouting context; may surface as a secondary finding depending on whether `indexes.ts` actually produces table/index definitions drizzle-kit should know about.

## Deferred Ideas

- **SCHEMA-05 (view refresh/staleness semantics)** — explicitly future per REQUIREMENTS.md; unchanged.
- **Migration rollback testing (reverse paths)** — future milestone per REQUIREMENTS.md Out of Scope § 6.
- **Schema-level CI gate** — `drizzle-kit check` exists upstream; if schema drift recurs, backlog a gate wire-up in a future milestone.
- **Postgres-live introspect audit** — rejected in favor of D-226-01 hybrid; can be revisited if the pure-file audit produces ambiguous findings.

---

*Phase: 226-schema-migration-orphan-audit*
*Context gathered: 2026-04-15*
