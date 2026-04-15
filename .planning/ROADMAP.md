# Roadmap: Degenerus Protocol Audit

## Milestones

- ✅ **v1.0 Initial RNG Security Audit** — Phases 1-5 (shipped 2026-03-14)
- ✅ **v2.0 Adversarial Audit** — Phases 6-18 (shipped 2026-03-17)
- ✅ **v3.0-v24.1** — Phases 19-212 (shipped 2026-04-10)
- ✅ **v25.0 Full Audit (Post-v5.0 Delta + Fresh RNG)** — Phases 213-217 (shipped 2026-04-11)
- ✅ **v26.0 Bonus Jackpot Split** — Phases 218-219 (shipped 2026-04-12)
- ✅ **v27.0 Call-Site Integrity Audit** — Phases 220-223 (shipped 2026-04-13)
- ⏳ **v28.0 Database & API Intent Alignment Audit** — Phases 224-229 (in progress — 2/6 phases complete)

## Phases

<details>
<summary>✅ v25.0 Full Audit (Phases 213-217) — SHIPPED 2026-04-11</summary>

- [x] Phase 213: Delta Extraction (3/3 plans) — completed 2026-04-10
- [x] Phase 214: Adversarial Audit (5/5 plans) — completed 2026-04-10
- [x] Phase 215: RNG Fresh Eyes (5/5 plans) — completed 2026-04-11
- [x] Phase 216: Pool & ETH Accounting (3/3 plans) — completed 2026-04-11
- [x] Phase 217: Findings Consolidation (2/2 plans) — completed 2026-04-11

</details>

<details>
<summary>✅ v26.0 Bonus Jackpot Split (Phases 218-219) — SHIPPED 2026-04-12</summary>

- [x] Phase 218: Bonus Split Implementation (2/2 plans) — completed 2026-04-12
- [x] Phase 219: Delta Audit & Gas Verification (2/2 plans) — completed 2026-04-12

</details>

<details>
<summary>✅ v27.0 Call-Site Integrity Audit (Phases 220-223) — SHIPPED 2026-04-13</summary>

- [x] Phase 220: Delegatecall Target Alignment (2/2 plans) — completed 2026-04-12
- [x] Phase 221: Raw Selector & Calldata Audit (2/2 plans) — completed 2026-04-12
- [x] Phase 222: External Function Coverage Gap (3/3 plans) — completed 2026-04-13
- [x] Phase 223: Findings Consolidation (2/2 plans) — completed 2026-04-13

</details>

### v28.0 Database & API Intent Alignment Audit (In Progress)

**Milestone Goal:** Verify that the sibling `database/` repo (API handlers, DB schema + migrations, indexer) delivers exactly what its documented intent claims — where "intent" spans `database/docs/API.md`, `database/docs/openapi.yaml`, and in-source comments — and produce a consolidated findings document. Four mismatch directions are flagged: docs→code, code→docs, comment→code, and Drizzle schema↔applied migration.

- [x] **Phase 224: API Route & OpenAPI Alignment** - Audit bidirectional coverage between `database/src/api/routes/*.ts` and `database/docs/openapi.yaml` (method, path, params, body shape) — completed 2026-04-13 (27/27/27 triple alignment, 1 INFO meta-stub)
- [x] **Phase 225: API Handler Behavior & Validation Schema Alignment** - Verify handler JSDoc/inline comments, response shapes, and Fastify request-validation schemas match openapi.yaml + handler bodies (completed 2026-04-13)
- [ ] **Phase 226: Schema, Migration & Orphan Audit** - Reconcile Drizzle schemas (`database/src/db/schema/*.ts`) against applied migrations (`database/drizzle/*.sql`), validate column-comment semantics, and detect orphan tables
- [ ] **Phase 227: Indexer Event Processing Correctness** - Verify every contract event consumed by `database/src/indexer/event-processor.ts` is registered and maps args to schema fields per documented semantics
- [ ] **Phase 228: Cursor, Reorg & View Refresh State Machines** - Audit `cursor-manager.ts`, `reorg-detector.ts`, and `view-refresh.ts` against documented block-ordering, reorg-depth, and staleness behaviors
- [ ] **Phase 229: Findings Consolidation** - Roll up phase 224-228 findings into `audit/FINDINGS-v28.0.md` with severity + direction + resolution status, following v27.0 consolidated-findings structure

## Phase Details

### Phase 224: API Route & OpenAPI Alignment
**Goal**: Every endpoint in `database/docs/openapi.yaml` has a matching route implementation in `database/src/api/routes/*.ts` (with correct HTTP method, path, parameters, request body shape), and every implemented route is documented in both `openapi.yaml` and `API.md` — no undocumented endpoints and no documented-but-unimplemented endpoints
**Depends on**: Nothing (first phase of v28.0)
**Requirements**: API-01, API-02
**Success Criteria** (what must be TRUE):
  1. A route↔spec mapping catalog exists in `224-01-API-ROUTE-MAP.md` enumerating every entry from `database/docs/openapi.yaml` alongside the matching `database/src/api/routes/*.ts` handler, with a PASS/FAIL verdict per endpoint covering HTTP method, path, parameters, and request body shape
  2. Every route file in `database/src/api/routes/` (game, health, history, leaderboards, player, replay, tokens, viewer) is enumerated and cross-checked against both `openapi.yaml` AND `database/docs/API.md` with zero undocumented endpoints remaining uncatalogued
  3. Each docs-claim-vs-code-delivery mismatch is classified as docs→code (documented endpoint missing from code) or code→docs (implemented endpoint missing from docs) and added to the Phase 229 finding candidate pool with source file:line references
  4. Coverage totals reported: `{X endpoints in openapi.yaml} / {Y routes in code} / {Z missing either side}` with the bidirectional diff enumerated

**Plans:** 1 plan

Plans:
- [x] 224-01-PLAN.md — Bidirectional catalog: openapi.yaml ↔ route registrations ↔ API.md with PASS/FAIL/JUSTIFIED verdicts and F-28-224-NN finding stubs — completed 2026-04-13 (see `224-01-API-ROUTE-MAP.md` + `224-01-SUMMARY.md`)

### Phase 225: API Handler Behavior & Validation Schema Alignment
**Goal**: Handler bodies in `database/src/handlers/*.ts` and `database/src/api/routes/*.ts` behave exactly as their JSDoc/inline comments describe; actual response shapes match `openapi.yaml` response schemas field-for-field; Fastify request-validation schemas in `database/src/api/schemas/` match openapi.yaml parameter definitions
**Depends on**: Phase 224 (route↔spec map feeds handler-level audit; only confirmed-paired endpoints get handler body review)
**Requirements**: API-03, API-04, API-05
**Success Criteria** (what must be TRUE):
  1. A handler-comment audit catalog exists in `225-01-HANDLER-COMMENT-AUDIT.md` enumerating every handler in `database/src/handlers/*.ts` and `database/src/api/routes/*.ts` with a verdict on whether the JSDoc/inline comment accurately describes the handler body's preconditions, side effects, and return shape
  2. A response-shape audit catalog in `225-02-RESPONSE-SHAPE-AUDIT.md` compares actual handler return values against openapi.yaml response schemas for field names, types, optionality, and enum values — every mismatch recorded with file:line + openapi.yaml anchor
  3. A request-schema audit catalog in `225-03-REQUEST-SCHEMA-AUDIT.md` compares Fastify validation schemas in `database/src/api/schemas/` against openapi.yaml parameter definitions (parameter names, types, required/optional, enum constraints) with PASS/FAIL verdicts per schema file
  4. Each comment→code, code→docs, or docs→code mismatch is classified by direction and added to the Phase 229 finding candidate pool

**Plans:** 3/3 plans complete

Plans:
- [x] 225-01-PLAN.md — API-03 handler JSDoc/inline-comment vs body-behavior audit for all 27 HTTP handlers in src/api/routes/*.ts; Tier A + Tier B flagged per D-225-04; Tier C counted only; src/handlers/*.ts deferred to Phase 227
- [x] 225-02-PLAN.md — API-04 response-shape audit: 8 sampled endpoints (one per route file) with recursive Zod-response-tree vs openapi.yaml responses.200 field-by-field comparison; expansion rule on FAIL per D-225-03; extrapolation on all-PASS
- [x] 225-03-PLAN.md — API-05 request-schema audit: every exported Zod schema in src/api/schemas/*.ts plus inline route-file schemas, compared to openapi.yaml parameters; orphan-in-openapi parameters flagged as docs->code (exception to D-225-02 default)


### Phase 226: Schema, Migration & Orphan Audit
**Goal**: Every Drizzle table in `database/src/db/schema/*.ts` matches the columns/types/constraints/indexes in `database/drizzle/*.sql` applied migrations; every migration diff is rational and traceable to a schema-file change; column comments accurately describe the column definition; every table is referenced by handler/indexer code (no orphans) and every code-referenced table exists in the schema
**Depends on**: Nothing (parallel with 224-225 possible; schema audit is independent of API surface work)
**Requirements**: SCHEMA-01, SCHEMA-02, SCHEMA-03, SCHEMA-04
**Success Criteria** (what must be TRUE):
  1. A schema↔migration reconciliation table in `226-01-SCHEMA-MIGRATION-DIFF.md` enumerates every Drizzle table in `database/src/db/schema/*.ts` (~30 files) against the cumulative applied state from `database/drizzle/*.sql` (7 migration files), with per-column/per-constraint/per-index PASS/FAIL verdicts — zero columns, FKs, or indexes present in one side and missing from the other
  2. A migration-rationality trace in `226-02-MIGRATION-TRACE.md` walks each of the 7 migration files as a diff from its predecessor, and verifies every `ADD COLUMN`, `DROP COLUMN`, `ALTER`, index or FK change has a corresponding same-logical-unit change in the schema files — every unjustified drift recorded as a finding candidate
  3. A column-comment semantic audit in `226-03-COLUMN-COMMENT-AUDIT.md` spot-checks in-source comments describing semantics (purpose, units, nullability, FK meaning) against actual column definitions — every comment→code mismatch logged with file:line
  4. An orphan-table report in `226-04-ORPHAN-TABLES.md` enumerates every table in the schema and confirms at least one handler OR indexer OR docs reference; lists every handler-referenced or indexer-referenced table name and confirms each exists in the schema — zero orphans remaining uncatalogued

**Plans**: TBD

### Phase 227: Indexer Event Processing Correctness
**Goal**: Every contract event emitted by `degenerus-audit/contracts/*.sol` that the indexer claims to process has a registered case in `database/src/indexer/event-processor.ts`; every case handler correctly maps event args to schema fields per the target table's column semantics; indexer comments describing processing semantics (idempotency, reorg safety, backfill, view-refresh triggers) match the actual behavior of the code
**Depends on**: Phase 226 (schema reconciliation must be locked before arg-to-field mapping is audited — audit needs a trusted schema baseline)
**Requirements**: IDX-01, IDX-02, IDX-03
**Success Criteria** (what must be TRUE):
  1. An event-coverage catalog in `227-01-EVENT-COVERAGE-MATRIX.md` enumerates every event emitted by `degenerus-audit/contracts/*.sol` with a classification (PROCESSED with case in `event-processor.ts` / DELEGATED to named handler / INTENTIONALLY-SKIPPED with comment-justified rationale / UNHANDLED as finding candidate)
  2. An arg-to-field mapping audit in `227-02-EVENT-ARG-MAPPING.md` walks each `event-processor.ts` case and maps event args → schema-field writes with PASS/FAIL verdicts per case — covers field name, type, and coercion correctness; zero silent field-swap or truncation bugs
  3. An indexer-comment correctness audit in `227-03-INDEXER-COMMENT-AUDIT.md` verifies that in-source comments claiming idempotency, reorg safety, backfill behavior, or view-refresh triggers match the actual code behavior in `event-processor.ts` and delegated handler files — every comment→code mismatch logged with file:line
  4. Each unhandled event, arg-mapping bug, or comment-drift item is classified by direction and added to the Phase 229 finding candidate pool

**Plans**: TBD

### Phase 228: Cursor, Reorg & View Refresh State Machines
**Goal**: `cursor-manager.ts` and `reorg-detector.ts` behave as documented — block ordering, gap handling, maximum reorg depth, and recovery-after-stall all match in-source comment claims; `view-refresh.ts` triggers refreshes per the staleness model documented in the indexer comments and the schema view definitions
**Depends on**: Phase 227 (event processing must be audited first so state-machine audit can presume event-handler correctness when reasoning about cursor advancement)
**Requirements**: IDX-04, IDX-05
**Success Criteria** (what must be TRUE):
  1. A cursor/reorg state-machine trace in `228-01-CURSOR-REORG-TRACE.md` walks every state transition in `database/src/indexer/cursor-manager.ts` and `database/src/indexer/reorg-detector.ts` (advance, gap, reorg-detect, recovery-after-stall) with a PASS/FAIL verdict on whether the code path matches its comment-stated behavior — cites block-ordering guarantees, documented maximum reorg depth, and stall-recovery semantics
  2. A view-refresh audit in `228-02-VIEW-REFRESH-AUDIT.md` enumerates every refresh trigger in `database/src/indexer/view-refresh.ts` and cross-references each trigger condition against the staleness model documented in the view-refresh file comments AND the schema view definitions — mismatches logged as finding candidates
  3. Each state-machine deviation or view-refresh mismatch is classified by direction (comment→code drift, docs→code gap, etc.) and added to the Phase 229 finding candidate pool
  4. All 9 indexer files (block-fetcher, cursor-manager, event-processor, reorg-detector, view-refresh, purge-block-range, main, index, plus any delegated handler files) have been audit-touched across Phases 227+228 — no indexer file left unreviewed

**Plans**: TBD

### Phase 229: Findings Consolidation
**Goal**: All discrepancies surfaced in phases 224-228 are consolidated into `audit/FINDINGS-v28.0.md` with severity (HIGH / MEDIUM / LOW / INFO), direction (docs→code / code→docs / comment→code / schema↔migration), originating phase + file:line trace, and resolution status (RESOLVED-DOC / RESOLVED-CODE / DEFERRED with reason / INFO-ACCEPTED); milestone state is advanced to SHIPPED and `PROJECT.md` / `MILESTONES.md` / `KNOWN-ISSUES.md` are synced
**Depends on**: Phase 224, Phase 225, Phase 226, Phase 227, Phase 228 (needs every upstream phase's finding candidates)
**Requirements**: FIND-01, FIND-02, FIND-03
**Success Criteria** (what must be TRUE):
  1. `audit/FINDINGS-v28.0.md` exists following the `audit/FINDINGS-v27.0.md` structure — every finding from phases 224-228 has a stable `F-28-NN` ID, severity (HIGH/MEDIUM/LOW/INFO), direction label (docs→code / code→docs / comment→code / schema↔migration), and resolution status (RESOLVED-DOC / RESOLVED-CODE / DEFERRED / INFO-ACCEPTED)
  2. Every finding is traceable to (a) the originating phase, and (b) a specific `database/` repo file:line reference — or for indexer findings, a `contracts/` event + `database/src/db/schema/` table pair
  3. Every finding has a recorded resolution status with a one-sentence rationale; DEFERRED items name the deferral target milestone; INFO-ACCEPTED items are candidates for promotion to `KNOWN-ISSUES.md`
  4. `MILESTONES.md` has a v28.0 retrospective entry in v25.0/v26.0/v27.0 format; `PROJECT.md` moves v28.0 from "Current Milestone" to "Completed Milestone"; `REQUIREMENTS.md` traceability checkboxes flipped to `[x]` for every satisfied REQ-ID

**Plans**: TBD

## Progress

**Execution Order:**
Phase 224 first (establishes route↔spec map needed by 225). Phase 225 after 224. Phase 226 can run in parallel with 224/225 (independent of API surface). Phase 227 after 226 (needs locked schema baseline). Phase 228 after 227 (presumes event-handler correctness). Phase 229 last (needs all upstream finding candidates).

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 213. Delta Extraction | v25.0 | 3/3 | Complete | 2026-04-10 |
| 214. Adversarial Audit | v25.0 | 5/5 | Complete | 2026-04-10 |
| 215. RNG Fresh Eyes | v25.0 | 5/5 | Complete | 2026-04-11 |
| 216. Pool & ETH Accounting | v25.0 | 3/3 | Complete | 2026-04-11 |
| 217. Findings Consolidation | v25.0 | 2/2 | Complete | 2026-04-11 |
| 218. Bonus Split Implementation | v26.0 | 2/2 | Complete | 2026-04-12 |
| 219. Delta Audit & Gas Verification | v26.0 | 2/2 | Complete | 2026-04-12 |
| 220. Delegatecall Target Alignment | v27.0 | 2/2 | Complete | 2026-04-12 |
| 221. Raw Selector & Calldata Audit | v27.0 | 2/2 | Complete | 2026-04-12 |
| 222. External Function Coverage Gap | v27.0 | 3/3 | Complete | 2026-04-13 |
| 223. Findings Consolidation | v27.0 | 2/2 | Complete | 2026-04-13 |
| 224. API Route & OpenAPI Alignment | v28.0 | 1/1 | Complete | 2026-04-13 |
| 225. API Handler Behavior & Validation Schema Alignment | v28.0 | 3/3 | Complete   | 2026-04-13 |
| 226. Schema, Migration & Orphan Audit | v28.0 | 0/? | Not started | - |
| 227. Indexer Event Processing Correctness | v28.0 | 0/? | Not started | - |
| 228. Cursor, Reorg & View Refresh State Machines | v28.0 | 0/? | Not started | - |
| 229. Findings Consolidation | v28.0 | 0/? | Not started | - |
