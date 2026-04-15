# Requirements: Degenerus Protocol Audit — v28.0 Database & API Intent Alignment Audit

**Defined:** 2026-04-13
**Core Value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.

## Milestone Goal

Verify that the sibling `database/` repo (API handlers, DB schema + migrations, indexer) delivers exactly what its documented intent claims — where "intent" spans the `API.md` prose docs, the `openapi.yaml` contract, and the in-source comments — and produce a consolidated findings document.

The audit grades code against three intent sources and flags four mismatch directions:

**Intent sources:**
- `database/docs/API.md` (883 lines) — prose endpoint docs
- `database/docs/openapi.yaml` (1708 lines) — OpenAPI spec
- In-source comments (JSDoc, inline) — stated intent of each function/handler/schema

**Mismatch directions:**
- Docs claim → code doesn't deliver
- Code does → docs don't mention
- Comment says → code does otherwise
- Drizzle schema ↔ applied migration reality

**Cross-repo scope:** planning lives in `degenerus-audit/.planning/`; audit target is `/home/zak/Dev/PurgeGame/database/`. Indexer correctness has shared surface with this repo's contracts (events emitted).

## v28.0 Requirements

### API Endpoint Alignment

- [x] **API-01**: Every endpoint documented in `database/docs/openapi.yaml` has a matching implemented route in `database/src/api/routes/` with correct HTTP method, path, parameters, and request body shape — verified Phase 224 (27 openapi entries ↔ 27 routes, all PAIRED)
- [x] **API-02**: Every implemented route in `database/src/api/routes/*.ts` is documented in both `openapi.yaml` and `API.md` — no undocumented endpoints — verified Phase 224 (27 routes ↔ 27 openapi entries ↔ 27 API.md headings, all PAIRED-BOTH)
- [x] **API-03**: JSDoc/inline comments on each handler (`database/src/handlers/*.ts` and `database/src/api/routes/*.ts`) accurately describe the handler body's behavior — preconditions, side effects, return shape
- [x] **API-04**: Actual response shapes returned by handlers match the `openapi.yaml` response schemas — field names, types, optionality, enum values
- [x] **API-05**: Fastify request-validation schemas in `database/src/api/schemas/` match the parameter definitions in `openapi.yaml` — parameter names, types, required/optional, enum constraints

### Schema ↔ Migrations ↔ Comments

- [ ] **SCHEMA-01**: Every Drizzle table definition in `database/src/db/schema/*.ts` matches the columns, types, constraints, and indexes in the applied migration SQL (`database/drizzle/*.sql`) — no columns, constraints, FKs, or indexes present in one and missing from the other
- [x] **SCHEMA-02**: In-source comments on schema columns describing semantics (purpose, units, nullability intent, FK meaning) accurately describe the actual column definition
- [x] **SCHEMA-03**: Each migration file in `database/drizzle/*.sql` represents a rational, justifiable diff from its predecessor — every `ADD COLUMN`, `DROP COLUMN`, `ALTER`, index, or FK change has a corresponding schema-file change in the same logical unit
- [ ] **SCHEMA-04**: Every table referenced in handler code, indexer code, or docs exists in the schema; every table in the schema is actually used (no orphan tables that handlers/indexer never touch)

### Indexer Correctness

- [ ] **IDX-01**: Every contract event emitted by `degenerus-audit/contracts/*.sol` that the indexer claims to process has a registered case in `database/src/indexer/event-processor.ts` (or an explicit delegating handler); intentionally skipped events are justified in comments
- [ ] **IDX-02**: Each `event-processor` case handler maps event args to the correct schema fields per the table's column semantics and the handler file's comments — no silent field-swap or type coercion bugs
- [x] **IDX-03**: Indexer comments describing processing semantics — idempotency, reorg safety, backfill behavior, view-refresh triggers — match the actual behavior of the code
- [ ] **IDX-04**: Cursor management (`cursor-manager.ts`) and reorg detection (`reorg-detector.ts`) behave as documented — block ordering, gap handling, maximum reorg depth, recovery-after-stall
- [ ] **IDX-05**: View refresh triggers in `view-refresh.ts` match the staleness model documented in comments and in schema view definitions

### Findings Consolidation

- [ ] **FIND-01**: All discrepancies from API, SCHEMA, and IDX phases are consolidated into `audit/FINDINGS-v28.0.md` with severity (HIGH / MEDIUM / LOW / INFO), direction (docs→code / code→docs / comment→code / schema↔migration), and source reference
- [ ] **FIND-02**: Each finding is traceable to the originating phase + a specific `database/` file:line (or the contract event + database schema pair for indexer findings)
- [ ] **FIND-03**: Every finding has a recorded resolution status: `RESOLVED-DOC` (doc patched), `RESOLVED-CODE` (code patched), `DEFERRED` (with explicit reason), or `INFO-ACCEPTED` (design decision, no action needed)

## Future Requirements

Deferred to later milestones. Tracked but not in this roadmap.

### API Docs Polish (future)

- **API-06 (deferred)**: Documented error responses and HTTP status codes in `API.md`/`openapi.yaml` match actual error-path behavior in handlers (error body shape, status-code-to-condition mapping)
- **API-07 (deferred)**: `API.md` example snippets (curl, sample payloads, sample responses) match current handler behavior byte-for-byte

### Schema Coverage Extensions (future)

- **SCHEMA-05 (deferred)**: Views defined in `database/src/db/schema/views.ts` match the SQL that materializes them and their documented staleness/refresh semantics

### Infrastructure & Runtime Concerns (future)

- Auth/rate-limit behavior documentation match
- CORS policy alignment with docs
- Deployment config (`.env` / `src/config`) schema alignment
- Performance assertions from docs (latency budgets, page sizes) verified against handler implementations
- Migration rollback coverage — each forward migration has a tested reverse path

## Out of Scope (v28.0)

Explicit exclusions with reasoning:

- **Contract-side correctness of the events being indexed** — the contracts are the source of truth; v28.0 audits whether the indexer faithfully reflects those events. Contract correctness is covered by prior milestones (v25.0 full audit, v26.0 bonus jackpot, v27.0 call-site integrity) and the in-flight phase-transition fix.
- **Database performance / query-plan tuning** — correctness first; query optimization is a different risk class and a different skill set. Performance regressions that cause incorrect results are in scope; slow-but-correct queries are not.
- **Frontend consumers of the API** — this milestone audits the API surface and its documentation. How downstream consumers use it is out of scope.
- **Auth / rate limiting / CORS semantics** — deferred to a later milestone unless a finding in v28.0 reveals a documented behavior that the code violates.
- **Environment configuration schema** — `.env` / `src/config` alignment with docs deferred to a later milestone.
- **Migration rollback testing** — forward migrations are in scope (SCHEMA-01/03); reverse paths are deferred.

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| API-01 | Phase 224 | Complete (2026-04-13) |
| API-02 | Phase 224 | Complete (2026-04-13) |
| API-03 | Phase 225 | Complete (2026-04-13) |
| API-04 | Phase 225 | Complete (2026-04-13) |
| API-05 | Phase 225 | Complete (2026-04-13) |
| SCHEMA-01 | Phase 226 | Pending |
| SCHEMA-02 | Phase 226 | Complete |
| SCHEMA-03 | Phase 226 | Complete |
| SCHEMA-04 | Phase 226 | Pending |
| IDX-01 | Phase 227 | Pending |
| IDX-02 | Phase 227 | Pending |
| IDX-03 | Phase 227 | Complete |
| IDX-04 | Phase 228 | Pending |
| IDX-05 | Phase 228 | Pending |
| FIND-01 | Phase 229 | Pending |
| FIND-02 | Phase 229 | Pending |
| FIND-03 | Phase 229 | Pending |
