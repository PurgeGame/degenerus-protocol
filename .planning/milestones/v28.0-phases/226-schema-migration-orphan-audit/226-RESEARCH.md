# Phase 226: Schema, Migration & Orphan Audit — Research

**Researched:** 2026-04-15
**Domain:** Drizzle ORM (PostgreSQL dialect) + hand-authored `.sql` migrations; catalog-only audit
**Confidence:** HIGH — all findings sourced from direct inspection of the target files in `/home/zak/Dev/PurgeGame/database/`

## Summary

Methodology and plan structure are locked by CONTEXT.md. This research closes the seven remaining tactical gaps the planner needs before writing plans 226-01..04:

1. **Parsing strategy** for the cumulative `.sql` ground truth.
2. **Drizzle schema TS extraction surface** (pgTable / index / uniqueIndex / foreignKey shape as actually used in this repo).
3. **`drizzle/meta/*.json` snapshot shape** as observed in `0006_snapshot.json`.
4. **Orphan-scan grep patterns** grounded in the import conventions already present in the audit target.
5. **`views.ts` structural audit approach** — this repo uses `pgMaterializedView(...).as((qb) => ...)` with embedded raw SQL; no CREATE VIEW DDL exists in the 7 migration files.
6. **Comment-extraction** for SCHEMA-02 — JSDoc lives at file-header + table-level; no column-level JSDoc and no `.comment()` runtime calls were found in the scout sample.
7. **Known drizzle-kit gotchas** that produce false drift.

**Primary recommendation:** Use hand-walked regex extraction (not AST, not `drizzle-kit introspect`) for both the `.sql` and `schema/*.ts` sides. The corpus is small (2,046 lines total; 7 migrations with 8 `CREATE TABLE` / `ALTER TABLE` statement classes; 30 schema files averaging 35 lines each), so regex + a per-table tally markdown is faster, auditable, and keeps the zero-infra constraint intact. Reserve `drizzle-kit` invocations for a single out-of-band sanity check on the `0007` anomaly (see §Gotchas).

## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-226-01:** Primary ground truth = cumulative `.sql` application; secondary cross-check = `drizzle/meta/0006_snapshot.json`. Zero DB spin-up; pure file audit.
- **D-226-02:** Four plans — 226-01 (SCHEMA-01 diff), 226-02 (SCHEMA-03 migration trace + meta cross-check), 226-03 (SCHEMA-02 column comments), 226-04 (SCHEMA-04 orphan scan).
- **D-226-03:** Orphan scan is bidirectional across `src/handlers/*.ts`, `src/indexer/*.ts`, `src/api/routes/*.ts`, `src/db/schema/views.ts`, `src/db/schema/indexes.ts`.
- **D-226-04:** Tier A/B comment threshold (inherited from D-225-04).
- **D-226-05:** Default finding direction `schema↔migration`.
- **D-226-06:** `F-28-226-01` pre-assigned to the `0007` snapshot anomaly in 226-02.
- **D-226-07:** `views.ts` in scope for SCHEMA-01 + SCHEMA-04; SCHEMA-05 (refresh semantics) deferred.
- **D-226-08:** Cross-repo READ-only on `/home/zak/Dev/PurgeGame/database/`.
- **D-226-09:** Finding IDs `F-28-226-01..NN`, fresh counter.
- **D-226-10:** Catalog-only; no runtime gate.

### Claude's Discretion
- Plan 226-01 vs 226-02 execution ordering.
- Severity promotion criteria for SCHEMA-01 findings.
- Exact grep patterns for orphan scan (recommendations in §Orphan Scan below).
- Whether `indexes.ts` gets a standalone SCHEMA-01 mini-finding.

### Deferred Ideas (OUT OF SCOPE)
- SCHEMA-05 view refresh/staleness semantics.
- Migration rollback / reverse-path testing.
- Schema-level CI gate (`drizzle-kit check` wire-up).
- Live Postgres introspection.

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| SCHEMA-01 | Every Drizzle table matches cumulative `.sql` columns / types / constraints / indexes | §Parsing Strategy, §Drizzle TS Extraction, §Meta JSON Shape, §Field Mapping Table |
| SCHEMA-02 | Column-level comments match actual column definition (Tier A/B) | §Comment Extraction — documents that NO column-level JSDoc exists in the sample; nearly all comments are file-header / table-level. The planner must decide how to treat table-level prose that describes columns. |
| SCHEMA-03 | Each migration is a rational diff from predecessor; every SQL change has a same-logical-unit TS change | §Parsing Strategy + §Meta JSON Shape (meta snapshots are the natural per-migration diff source) |
| SCHEMA-04 | Bidirectional orphan scan across handlers / indexer / routes / views | §Orphan Scan, §Known Imports sample |

## Scope Inventory (measured 2026-04-15)

- **Migrations:** 7 files, 859 non-blank lines. Distribution: `0000`=32L, `0001`=303L, `0002`=258L, `0003`=24L, `0004`=12L, `0005`=0L (empty file — itself worth noting), `0006`=209L, `0007`=21L.
- **Schema TS:** 30 files, 2,046 lines (incl. `index.ts` barrel, `indexes.ts`, `views.ts`). 29 registered in `drizzle.config.ts`; `indexes.ts` is NOT registered.
- **Meta snapshots:** 7 (`0000..0006`). `0007_snapshot.json` **missing** — this is F-28-226-01 per D-226-06.
- **Handlers / indexer / routes:** 27 handler files + 8 route files + ~9 indexer files = orphan-scan surface.
- **Empty migration:** `0005_red_doctor_octopus.sql` is zero-length. Worth a context note in 226-02 even if benign (drizzle-kit can emit empty migrations when only meta-only changes are generated; still warrants explicit coverage).

## Parsing Strategy for Cumulative `.sql` Ground Truth

**Recommendation: regex-walked table-state accumulator, authored as a markdown catalog.**

**Rejected alternatives:**

| Option | Why Rejected |
|--------|--------------|
| `drizzle-kit introspect` | Requires a live Postgres; violates D-226-01's zero-infra constraint. |
| `drizzle-kit generate --dry-run` | Runs against the schema files, not `.sql`; tells us what drizzle *would* generate, not what *did* run. Useful only as an adjunct for the D-226-06 anomaly. |
| `pg-query-parser` (libpg_query Node bindings) | Overkill for 859 lines of DDL; introduces a dep; SQL produced by drizzle-kit is mechanical (one statement per `--> statement-breakpoint`) and trivially regex-parseable. |
| Throwaway SQLite | Dialect translation (identity columns, `USING btree`) breaks on SQLite. Would require pg container, violating D-226-08. |
| Full AST parse of TS side | Over-engineered; schema files follow a strictly regular shape — see §Drizzle TS Extraction. |

**Regex-walked accumulator process (per plan 226-01):**

1. **Split each `.sql` on `--> statement-breakpoint`** — drizzle-kit's authoritative statement delimiter. Each fragment is exactly one DDL statement.
2. **Classify fragment by leading token:** `CREATE TABLE`, `ALTER TABLE`, `CREATE (UNIQUE )?INDEX`, `CREATE MATERIALIZED VIEW`, `DROP ...`, `ADD CONSTRAINT`, etc.
3. **Maintain an in-document accumulator table** per migration:

    | Table | Op | Field/Constraint | Resulting state after this migration |
    |-------|----|------------------|--------------------------------------|
    | `raw_events` | CREATE | col `id integer identity` | columns: id,blockNumber,...,removed; pk=id; uniq(`raw_events_unique`) |
    | `raw_events` | ALTER ADD | col `new_field text` | columns extended; nothing else changed |

4. **Final cumulative state** = read the last row per `(table, field)` pair. This is the ground truth to diff against `schema/*.ts`.

**Grep helpers:**

```bash
# Enumerate every DDL statement classified by leading keyword
rg -n --no-heading '^(CREATE (UNIQUE |MATERIALIZED )?(TABLE|INDEX|VIEW)|ALTER TABLE|DROP (TABLE|INDEX|COLUMN|CONSTRAINT)|ADD CONSTRAINT)' \
  /home/zak/Dev/PurgeGame/database/drizzle/*.sql

# Per-migration statement count sanity check
for f in /home/zak/Dev/PurgeGame/database/drizzle/*.sql; do
  echo "$f $(grep -c -F 'statement-breakpoint' "$f")"
done
```

**Output artifact:** `226-01-SCHEMA-MIGRATION-DIFF.md` carries one section per table (30-ish tables) with a 4-column row per column/index/FK: `Side: SQL | Side: TS | Match? | Finding-stub`.

## Drizzle Schema TS Extraction

**Conventions observed across 30 files** (`decimator.ts`, `trait-burn-tickets.ts`, `views.ts` inspected; rest follow the same shape):

- **Table declaration:** `export const <camelTableName> = pgTable('<snake_table_name>', { ... }, (t) => [ ... ]);`
- **Column declaration patterns:**
    - `colName: text()` → PG type `text` — name is camelCase in PG (no explicit snake_case mapping).
    - `snakeCol: text('snake_col')` → PG column named `snake_col`.
    - `id: integer().primaryKey().generatedAlwaysAsIdentity()` → PG `integer PRIMARY KEY GENERATED ALWAYS AS IDENTITY`.
    - `bigint({ mode: 'bigint' })` → PG `bigint`. (The `mode` is a runtime-only flag for the JS type; does NOT appear in SQL.)
    - `smallint()` → PG `smallint`.
    - `.notNull()` → `NOT NULL`.
    - `.default(<literal>)` or `.default(sql\`...\`)` → `DEFAULT ...`.
- **Table-level constraint/index declarations** (second-arg callback returning an array):
    - `primaryKey({ columns: [t.a, t.b] })` → composite PK (name auto-generated as `<table>_<col>_<col>_pk`).
    - `uniqueIndex('<name>').on(t.a, t.b)` → `CREATE UNIQUE INDEX "<name>" ON ... USING btree (...)`.
    - `index('<name>').on(t.a)` → `CREATE INDEX "<name>" ON ... USING btree (...)`.
    - `foreignKey({ columns: [...], foreignColumns: [...], name: '<name>' })` — no occurrences observed in the repo during scouting; verify during 226-01.

**Planner-grep patterns (drop into plan 226-01 as-is):**

```bash
# Every table in the schema dir (one row per table constant)
rg -n --no-heading "= pgTable\('([a-z_0-9]+)'" \
  /home/zak/Dev/PurgeGame/database/src/db/schema/ \
  --replace '$1'

# Every index/uniqueIndex (name + columns)
rg -n --no-heading "(unique)?[Ii]ndex\('([a-z_0-9]+)'\)\.on\(" \
  /home/zak/Dev/PurgeGame/database/src/db/schema/

# Every foreign key (expected zero; flag if found)
rg -n --no-heading 'foreignKey\(' /home/zak/Dev/PurgeGame/database/src/db/schema/

# Every materialized view
rg -n --no-heading "pgMaterializedView\('([a-z_0-9]+)'" \
  /home/zak/Dev/PurgeGame/database/src/db/schema/views.ts
```

**`drizzle-kit` helpers — when (not) to use:**

- `drizzle-kit generate` writes files to `./drizzle/` — this is a WRITE to the target repo, violating D-226-08. **Do not run.**
- `drizzle-kit check` performs journal integrity checks (collision/ordering) without touching the DB — *could* be used READ-only, but its output is opinionated for human review, not programmatic diffing. Value is marginal here; skip unless 226-02 needs a tie-breaker on the `0007` anomaly.
- `drizzle-kit introspect` requires live Postgres — skip.

## `drizzle/meta/*.json` Snapshot Shape (0006 verified)

Each snapshot is a single JSON object with this top-level shape (confirmed against `0006_snapshot.json`):

```jsonc
{
  "id": "<uuid>",                  // this snapshot's id
  "prevId": "<uuid>",              // prior snapshot's id — chain check
  "version": "7",
  "dialect": "postgresql",
  "tables": {
    "public.<table_name>": {
      "name": "<table_name>",
      "schema": "",
      "columns": {
        "<colName>": {
          "name": "<colName>",
          "type": "<pgType>",        // e.g. "integer", "bigint", "text", "timestamp"
          "primaryKey": <bool>,
          "notNull": <bool>,
          "default": <literal|undefined>,
          "identity": { "type": "always|byDefault", "name": "...", ... }   // optional
        }
      },
      "indexes": {
        "<index_name>": {
          "name": "<index_name>",
          "columns": [ { "expression": "<col>", "isExpression": false, "asc": true, "nulls": "last" } ],
          "isUnique": <bool>,
          "concurrently": false,
          "method": "btree",
          "with": {}
        }
      },
      "foreignKeys": { ... },         // by FK name
      "compositePrimaryKeys": { ... },// by PK name
      "uniqueConstraints": { ... },
      "policies": { ... },
      "checkConstraints": { ... }
    }
  },
  "enums": { ... },                // e.g. gamePhaseEnum from game-state.ts
  "schemas": { ... },
  "sequences": { ... },
  "roles": { ... },
  "policies": { ... },
  "views": { ... },
  "_meta": { "columns": {}, "schemas": {}, "tables": {} }
}
```

**Field-level mapping table** — the planner copies this into 226-01 and 226-02 as the diff contract:

| Concept | `.sql` DDL | `schema/*.ts` | `meta/*.json` (path) |
|---------|------------|----------------|-----------------------|
| Table exists | `CREATE TABLE "<t>"` | `pgTable('<t>', ...)` | `tables["public.<t>"]` |
| Column name | quoted ident inside `CREATE TABLE` / `ALTER ... ADD COLUMN` | key of first-arg object (or `text('snake_name')` override) | `tables[...].columns.<key>.name` |
| Column type | `text`, `integer`, `bigint`, `smallint`, `timestamp`, `boolean`, `jsonb`, identity spec | `text()` / `integer()` / `bigint({mode})` / `smallint()` / `boolean()` / timestamp modifier | `.type` string |
| NOT NULL | `NOT NULL` | `.notNull()` | `.notNull: true` |
| DEFAULT | `DEFAULT <expr>` | `.default(<lit>)` / `.default(sql\`...\`)` | `.default` string |
| PK (single col) | `PRIMARY KEY` on col | `.primaryKey()` | `.primaryKey: true` on column |
| PK (composite) | `CONSTRAINT "<n>" PRIMARY KEY("a","b")` | `primaryKey({columns:[t.a,t.b]})` in 2nd-arg array | `compositePrimaryKeys.<name>` |
| Identity / serial | `GENERATED {ALWAYS|BY DEFAULT} AS IDENTITY (SEQUENCE ...)` | `.generatedAlwaysAsIdentity()` / `.generatedByDefaultAsIdentity()` | `.identity` object |
| Unique index | `CREATE UNIQUE INDEX "<n>" ON "<t>" USING btree ("<c>")` | `uniqueIndex('<n>').on(t.c)` | `.indexes.<n>.isUnique: true` |
| Plain index | `CREATE INDEX "<n>" ...` | `index('<n>').on(t.c)` | `.indexes.<n>.isUnique: false` |
| Foreign key | `CONSTRAINT "<n>" FOREIGN KEY (...) REFERENCES ...` | `foreignKey({columns, foreignColumns, name})` or col-level `.references(...)` | `.foreignKeys.<n>` |
| Enum | `CREATE TYPE "<n>" AS ENUM ('a','b')` | `pgEnum('<n>', ['a','b'])` (see `game-state.ts`) | `enums.<n>` |
| Materialized view | `CREATE MATERIALIZED VIEW "<n>" AS ...` | `pgMaterializedView('<n>').as((qb) => ...)` | `views.<n>` (if generated) |

**Secondary cross-check (D-226-01):** For each table, compare `.sql`-derived state against `tables["public.<t>"]` in `0006_snapshot.json`. Disagreement is a 226-02 finding. Note: `0007_trait_burn_tickets.sql` adds two tables and two indexes that are NOT in any snapshot file — this is the known F-28-226-01 and sets the lower bound on snapshot-vs-SQL disagreements.

## Orphan Scan (SCHEMA-04)

**Verified import convention** in handlers (e.g. `handlers/lootbox.ts:19`, `handlers/decimator.ts:27-30`):

```ts
import { lootboxPurchases, lootboxResults, traitsGenerated } from '../db/schema/lootbox.js';
```

Key observations:
- Always a **named import from `../db/schema/<file>.js`** (note the `.js` extension — NodeNext ESM convention).
- Files can also import via the **barrel** `../db/schema/index.js` (verify during scan; scout sample was direct-file).
- Table **PG name** (e.g. `lootbox_purchases`) and the **JS binding** (e.g. `lootboxPurchases`) are distinct; orphan scan must support both.

**Recommended grep patterns (drop into plan 226-04):**

```bash
# (1) Direct file imports into any schema module (handler → schema)
rg -n --no-heading "from ['\"].*/db/schema/[a-z-]+(\.js)?['\"]" \
  /home/zak/Dev/PurgeGame/database/src/{handlers,indexer,api/routes}

# (2) Barrel imports (catches './schema/index.js' or package-root import)
rg -n --no-heading "from ['\"].*/db/schema(/index)?(\.js)?['\"]" \
  /home/zak/Dev/PurgeGame/database/src/{handlers,indexer,api/routes}

# (3) Raw SQL table-name references inside sql`...` template strings
#     (catches views.ts JOINs and any raw-SQL queries in handlers/indexer)
rg -n --no-heading -U "sql\`[^\`]*\b<TABLE_PG_NAME>\b[^\`]*\`" \
  /home/zak/Dev/PurgeGame/database/src/

# (4) JS binding reference count (after resolving import, count uses)
#     Run per-binding; low-hit bindings get manual review.
rg -n --no-heading -w "<jsBindingName>" \
  /home/zak/Dev/PurgeGame/database/src/{handlers,indexer,api/routes,db/schema/views.ts,db/schema/indexes.ts}
```

**Orphan-scan algorithm:**

1. **Build the table universe:** from `src/db/schema/index.ts` re-exports + `views.ts` `pgMaterializedView` names. Scout confirmed ~60 exports in `index.ts`. Each export = `{jsBinding, pgName}`. Extracting pgName requires reading each file (the `pgTable('<pg>', ...)` first-arg).
2. **Schema → code:** for each `(jsBinding, pgName)`, run pattern (4) and pattern (3). Zero hits across handlers + indexer + routes + `views.ts` + `indexes.ts` = orphan finding.
3. **Code → schema:** for every `from '.../db/schema/<file>.js'` import, confirm `<file>.ts` exists and the named import resolves to an exported table/view in `index.ts`. Imported-but-not-exported = finding.
4. **Raw SQL table-name references:** grep raw SQL strings in `views.ts` and `indexes.ts` for table names not in the universe = finding.

**False-positive traps (flag in the plan):**

- **`indexes.ts`** uses raw SQL strings referencing tables by PG name (`coinflip_leaderboard`, `affiliate_earnings`, `baf_flip_totals`, `jackpot_distributions`, `level_transitions`, `degenerette_bets`, `decimator_claims`, `vault_deposits`, `vault_claims`). These are legitimate references — pattern (3) must recognize them as usage for orphan-scan purposes.
- **`views.ts`** embeds raw SQL with table names inside `sql\`...\`` joins (e.g. `player_winnings`, `token_balances`, `coinflip_results`). Same — legitimate references.
- **String matches in comments** — the word `lootboxPurchases` can appear in a JSDoc block without being code usage. Restrict pattern (4) to TS source excluding block comments, or require the match to not be preceded by `*` / `//`.
- **Barrel import without downstream use:** a handler that imports from `../db/schema/index.js` but never references the binding still counts as an import-time dependency; scan the *binding-use site*, not just the import line.
- **Enums (`gamePhaseEnum`)** are exported through the same barrel. Exclude known enum/constant exports from the "orphan table" universe; they're not tables.
- **`indexes.ts` itself** is not registered in `drizzle.config.ts`. Per D-226-03 it IS a legitimate orphan-scan source. Per Claude's discretion it MAY also warrant a standalone SCHEMA-01 note (recommended: context-only mention in 226-01, no standalone finding unless downstream analysis surfaces a drift caused by its absence from `drizzle-kit`).

## `views.ts` Structural Audit Approach

**Observed convention** (from `views.ts:16-40`):

```ts
export const playerSummary = pgMaterializedView('mv_player_summary').as((qb) => {
  return qb.select({ ... }).from(sql`player_winnings pw LEFT JOIN token_balances tb_coin ON ...`);
});
```

**Critical finding for the planner:** none of the 7 `.sql` migration files contain `CREATE MATERIALIZED VIEW` DDL for `mv_player_summary` (or any other `mv_*` view). The views are defined in TS only. This means:

- Either the views are created at runtime by a separate bootstrap path (probably triggered by `view-refresh.ts` — out of scope per D-226-07), **or** drizzle-kit generates view DDL into migrations only under specific conditions and the current migrations predate view addition.
- For SCHEMA-01 structural alignment, the diff is between **TS view definitions** and **any view DDL in `.sql` or `meta/*.json.views`**. If there is no SQL-side view DDL at all, that is itself a finding candidate (view code exists but no migration creates it — what creates them in production?). Flag for 226-01 investigation.
- Do NOT chase runtime refresh semantics — D-226-07 defers that.

**Planner action:** Plan 226-01 includes a dedicated `### Views` subsection that enumerates every `pgMaterializedView(...)` in `views.ts`, checks for matching `CREATE MATERIALIZED VIEW` DDL in any `.sql`, checks for `views.*` entries in `0006_snapshot.json`, and records a finding if neither source contains the view.

## Comment Extraction for SCHEMA-02 (Tier A/B)

**Empirical finding — scope is smaller than CONTEXT.md implies.**

Scouting three schema files (`trait-burn-tickets.ts`, `decimator.ts`, `views.ts`):

- **File-header JSDoc blocks** describe the *table's* purpose (e.g. `trait-burn-tickets.ts:1-12` — describes both tables in the file + semantics). Not per-column.
- **No column-level JSDoc** (no `/** ... */` immediately preceding a column declaration) was observed.
- **No `.comment('...')` runtime calls** were observed. drizzle-kit does not have a stable `.comment()` fluent API on columns as of v0.3x (migration-time comments come from raw SQL `COMMENT ON COLUMN`, which also does not appear in any `.sql` migration).
- **Inline `//` comments** occasionally appear on a column line (verify during audit).

**Implications for plan 226-03:**

1. The Tier A/B threshold applied to "column comments" is effectively applied to **table-level JSDoc prose that describes columns** (e.g. "`ticket_count` aggregates per `(level, traitId, player)`"). Treat each *claim about a column* inside a table-header JSDoc as a Tier A/B candidate.
2. Expected catalog size is small — on the order of 30 tables × 2-5 columns-claims-per-table = 60-150 rows max. Full enumeration (not sampling) is tractable.
3. If no prose comments make column-level claims, Tier A/B count can legitimately be 0. Tier C (no comments at all) is context-only per D-226-04.
4. Any `//` inline comment on a column line gets audited.

**Extraction pattern:**

```bash
# Header JSDoc blocks per schema file
rg -n --no-heading -U '/\*\*[\s\S]*?\*/' \
  /home/zak/Dev/PurgeGame/database/src/db/schema/ -g '*.ts'

# Inline comments co-located with a column declaration
rg -n --no-heading '//.*$' \
  /home/zak/Dev/PurgeGame/database/src/db/schema/ -g '*.ts' \
  | rg -v '^[^:]+:[0-9]+://\s*$'
```

## Known drizzle-kit Gotchas (false-drift sources)

These are cases where `.sql` and `schema/*.ts` *look* different but are semantically identical — do not log as findings:

1. **Identity column spelling.** SQL: `integer PRIMARY KEY GENERATED ALWAYS AS IDENTITY (SEQUENCE NAME "<t>_id_seq" INCREMENT BY 1 MINVALUE 1 MAXVALUE 2147483647 START WITH 1 CACHE 1)`. TS: `integer().primaryKey().generatedAlwaysAsIdentity()`. The sequence parameters (`MINVALUE 1 MAXVALUE 2147483647 START WITH 1 CACHE 1`) are drizzle-kit defaults — divergence here is noise, not drift.
2. **Timestamp modes.** `timestamp()` (TS) → PG `timestamp` (no tz). `timestamp({ mode: 'date' })` and `timestamp({ mode: 'string' })` produce the SAME SQL (`timestamp`); `mode` is a runtime JS-type flag. Do not compare `mode`.
3. **`bigint({ mode: 'bigint' | 'number' })`.** Same — PG-side is `bigint`, TS-side `mode` is a JS-type flag.
4. **Default-value representation.** `.default(0)` → `DEFAULT 0`. `.default(sql\`now()\`)` → `DEFAULT now()`. `.default('0')` on a `text` col → `DEFAULT '0'`. Compare normalized literal, not string-exact.
5. **Auto-generated constraint names.** Composite PKs in TS use `primaryKey({columns:[t.a,t.b]})` without a name; the SQL names them `<table>_<col>_<col>_pk` (seen in `0007`: `"trait_burn_tickets_level_trait_id_player_pk"`). The name is derived, not authored — do not flag as drift when TS lacks an explicit name.
6. **Camel vs snake column names.** `blockNumber: bigint()` in TS → column named `blockNumber` in SQL (quoted, camelCase). `traitId: smallint('trait_id')` in TS → `trait_id` in SQL (snake_case). The `text('explicit_name')` override IS the snake-case signal. Confirm by reading the first-arg string, not by assuming snake_case.
7. **`indexes.ts` is NOT in `drizzle.config.ts`.** The `ADDITIONAL_INDEXES` array of raw SQL is applied outside drizzle-kit's tracked lifecycle — these indexes will appear in Postgres but NOT in any `.sql` migration file and NOT in any `meta/*.json`. Before logging "index exists in code, not in SQL" as a finding, check whether the index name appears in `indexes.ts`'s `ADDITIONAL_INDEXES` array.
8. **Empty migration `0005_red_doctor_octopus.sql` (0 bytes).** Drizzle-kit emits empty SQL when the snapshot-to-snapshot diff was meta-only (or trivially empty). Check `meta/0005_snapshot.json` vs `meta/0004_snapshot.json` — if `prevId`/`id` are consistent and table shapes are identical, the empty `.sql` is legitimate. Otherwise, it's a finding candidate for 226-02.
9. **`0007` anomaly (F-28-226-01 — pre-assigned).** `0007_trait_burn_tickets.sql` exists, `0007_snapshot.json` does not, and `_journal.json` has no `idx: 7` entry. Any diff tooling that trusts `meta/_journal.json` as the source of truth will silently omit the `trait_burn_tickets` tables. This is exactly why D-226-01 designates `.sql` as primary.
10. **`CREATE MATERIALIZED VIEW` absent from all `.sql` files despite `views.ts` defining four mat-views.** See §Views — investigate creation path before logging as finding.

## Runtime State Inventory

Not applicable — catalog-only phase, no rename / refactor / migration. No writes occur to the audit target.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| ripgrep (`rg`) | All plans (grep patterns above) | ✓ | present on Linux dev host | — |
| Node / npx | Only needed if drizzle-kit invoked as adjunct | likely ✓ in `/home/zak/Dev/PurgeGame/database/` | — | Skip drizzle-kit helpers; plans don't require them |
| Postgres | NOT required (D-226-01) | N/A | — | N/A |

No blocking dependencies. All plans can execute with standard CLI file-reading tools.

## Validation Architecture

`.planning/config.json` was not re-read during this research; the phase is a pure catalog audit. Validation here means **spot-re-check of a finding sample** rather than unit/integration tests. Suggested sampling for the planner:

| Property | Value |
|----------|-------|
| Framework | N/A (catalog audit) |
| Quick run command | `rg -n --no-heading 'F-28-226-' .planning/phases/226-schema-migration-orphan-audit/*.md \| wc -l` (finding-count sanity) |
| Spot-check | For 3 random findings per plan, re-open the cited `File:line` and verify the diff claim |
| Phase gate | `/gsd-verify-work` re-reads all four catalog files + cross-checks that every `F-28-226-NN` appears in the rollup pool |

### Wave 0 Gaps
None — no test infrastructure required.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | No `.comment()` runtime calls or column-level JSDoc exist anywhere in the 30 schema files | §Comment Extraction | [ASSUMED] Scout sampled 3 files. If other files use column-level comments, SCHEMA-02 catalog grows. Low risk — plan 226-03 re-greps all 30 files as its first step. |
| A2 | `foreignKey(...)` is not used anywhere in the schema | §Drizzle TS Extraction | [ASSUMED] Scout grep not yet executed. If FKs exist, SCHEMA-01 must add FK comparison rows. Low risk — grep pattern given above is the first audit step. |
| A3 | The four `mv_*` materialized views are created by a path outside the 7 `.sql` migrations | §views.ts | [ASSUMED] Not verified. Could be runtime-bootstrapped (e.g. `view-refresh.ts` idempotent CREATE) or a missing-migration finding. Plan 226-01 must investigate before verdict. |
| A4 | `indexes.ts` is applied at runtime (not via drizzle-kit) and its indexes appear in PG but not in `.sql`/`meta` | §Gotchas #7 | [ASSUMED] Inferred from file header comment ("Applied via raw SQL") and absence from `drizzle.config.ts`. Consumer wire-up not traced in this research. Low risk — plan 226-04 will encounter the callsite during orphan scan. |
| A5 | Empty `0005_red_doctor_octopus.sql` is a legitimate drizzle-kit emission | §Gotchas #8 | [ASSUMED] Compare `meta/0004_snapshot.json` ↔ `meta/0005_snapshot.json` in plan 226-02 to confirm. |

## Open Questions

1. **What creates the four `pgMaterializedView`s in production?** No `CREATE MATERIALIZED VIEW` in any `.sql`. Answer likely lies in `view-refresh.ts` or a bootstrap script outside this phase's scope, but the answer affects whether "view in TS but not in SQL" is a finding. **Recommendation:** plan 226-01 records this as an INFO-severity context note, not a finding, until 228 dispositions it.
2. **Are barrel imports used?** Scout saw only direct-file imports (`from '../db/schema/lootbox.js'`). If barrel imports exist, pattern (2) in §Orphan Scan catches them. **Recommendation:** planner instructs 226-04 to run both patterns unconditionally.
3. **Is `indexes.ts::ADDITIONAL_INDEXES` actually invoked at runtime?** The file defines an array but doesn't apply it. Something else must `sql.raw(...)` over the array. Orphan scan will surface the caller. Not a 226 blocker.

## Sources

### Primary (HIGH confidence — direct file inspection, 2026-04-15)
- `/home/zak/Dev/PurgeGame/database/drizzle.config.ts` — 29 registered schema files, PG dialect.
- `/home/zak/Dev/PurgeGame/database/drizzle/meta/_journal.json` — 7 entries (0000..0006); no 0007 entry confirms F-28-226-01.
- `/home/zak/Dev/PurgeGame/database/drizzle/meta/0006_snapshot.json` — snapshot JSON shape (top-level keys, per-table shape).
- `/home/zak/Dev/PurgeGame/database/drizzle/0000_brown_justin_hammer.sql` and `/home/zak/Dev/PurgeGame/database/drizzle/0007_trait_burn_tickets.sql` — statement-breakpoint delimiter, identity-column SQL spelling, composite-PK auto-name pattern.
- `/home/zak/Dev/PurgeGame/database/src/db/schema/trait-burn-tickets.ts`, `decimator.ts`, `views.ts`, `indexes.ts`, `index.ts` — TS conventions, barrel structure, index-array pattern.
- `/home/zak/Dev/PurgeGame/database/src/handlers/lootbox.ts:19`, `decimator.ts:27-30`, `jackpot.ts:12`, `handlers/index.ts:34-37` — verified import convention for orphan-scan patterns.

### Secondary (MEDIUM confidence)
- Drizzle ORM / drizzle-kit conventions for identity columns, timestamp modes, bigint modes, composite PK naming — based on training knowledge of drizzle-kit v0.2x-0.3x (consistent with what appears in the observed SQL/TS).

### Tertiary (LOW confidence)
- Exact drizzle-kit version that generated these migrations is not read from `package.json` in this research; if gotcha #1 (identity sequence defaults) proves divergent, check `package.json` for drizzle-kit version and consult its changelog.

## Metadata

**Confidence breakdown:**
- Parsing strategy / TS extraction / meta JSON shape / orphan patterns: HIGH — verified against actual files.
- `views.ts` disposition: MEDIUM — open question on mat-view creation path, but research surfaces it explicitly and defers verdict to the plan.
- Comment extraction scope: MEDIUM — 3-file sample, re-verified in 226-03.
- Gotchas list: HIGH for items 1-8 (verified from samples); MEDIUM for item 10 (views).

**Research date:** 2026-04-15
**Valid until:** 2026-05-15 (stable — catalog target files won't change; only drizzle-kit version would invalidate).

## RESEARCH COMPLETE

**Phase:** 226 — Schema, Migration & Orphan Audit
**Confidence:** HIGH

### Key Findings

- **Regex-walked parsing beats every alternative** for a 859-line SQL + 2,046-line TS corpus with zero-infra constraint. Drop `drizzle-kit introspect` / throwaway-DB ideas.
- **Field-level mapping table** (§Meta JSON Shape) is the diff contract plans 226-01 and 226-02 apply row-by-row. Copy it verbatim.
- **Orphan-scan import convention confirmed:** `from '../db/schema/<file>.js'` with named bindings. Four grep patterns ready to drop into plan 226-04.
- **`views.ts` has no SQL-side DDL in any migration** — investigate (likely runtime-bootstrapped via `view-refresh.ts`, but unverified here). Don't pre-declare as a finding; record as INFO context.
- **Comment-audit scope is smaller than feared** — no column-level JSDoc and no `.comment()` calls in the sample. Tier A/B catalog likely 60-150 rows max, fully enumerable.
- **10 drizzle-kit gotchas** catalogued that produce false drift — the plan should include them as "skip/note only" criteria.
- **5 assumptions** logged (A1-A5) that the plans verify in their first step; none are load-bearing.

### File Created
`/home/zak/Dev/PurgeGame/degenerus-audit/.planning/phases/226-schema-migration-orphan-audit/226-RESEARCH.md`

### Ready for Planning
Planner has: parsing approach + exact regex/grep commands, field-level diff contract, orphan-scan patterns with false-positive list, views-handling plan, comment-audit scope reality-check, and 10 anti-drift gotchas. All four plans (226-01..04) can be written without further investigation.
