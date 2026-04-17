# Phase 225 Context: API Handler Behavior & Validation Schema Alignment

**Milestone:** v28.0 Database & API Intent Alignment Audit
**Phase number:** 225
**Phase name:** API Handler Behavior & Validation Schema Alignment
**Requirements:** API-03, API-04, API-05
**Date:** 2026-04-13
**Input phase:** 224 (27/27/27 PAIRED-BOTH matrix in `224-01-API-ROUTE-MAP.md` — all endpoints structurally aligned; this phase only deepens into type/behavior correctness)

## Phase Boundary

**In scope for this phase:**
- **API-03** — JSDoc/inline comments on HTTP handlers in `database/src/api/routes/*.ts` accurately describe handler body behavior (preconditions, side effects, return shape)
- **API-04** — Actual response shapes returned by handlers match `openapi.yaml` response schemas (field names, types, optionality, enum values)
- **API-05** — Fastify request-validation schemas in `database/src/api/schemas/*.ts` match `openapi.yaml` parameter definitions

**Explicitly NOT in scope for this phase:**
- **`src/handlers/*.ts`** directory (27 files, 4,367 lines) — these are **indexer event handlers**, not HTTP handlers. Their JSDoc audit belongs to **Phase 227** (IDX-03). Confirmed by inspection: these files work on `ctx.args` (event args), write to schema tables via Drizzle, and are dispatched by `src/indexer/event-processor.ts`. See D-225-01 below.
- Structural endpoint coverage — Phase 224 already did that (locked 27/27/27).
- Error-response / status-code audit — deferred API-06 (future milestone).
- API.md example-snippet correctness — deferred API-07 (future milestone).
- Schema / migrations / indexer — Phases 226/227/228.

## Current Observations (from scouting)

- **HTTP handlers live inline in route files** `database/src/api/routes/*.ts`. Example pattern from `leaderboards.ts`:
  ```ts
  fastify.get('/coinflip', {
    schema: {
      querystring: coinflipQuerySchema,
      response: { 200: coinflipResponseSchema }
    }
  }, async (request, reply) => { ... })
  ```
  The `schema:` option is passed through `fastify-type-provider-zod`, which enforces the Zod schemas at runtime.

- **Zod schemas in `database/src/api/schemas/`** (6 files, ~400 lines total): `common.ts`, `game.ts`, `history.ts`, `leaderboard.ts`, `player.ts`, `tokens.ts`. These are **the runtime source of truth** — both for request validation AND response serialization.

- **`database/docs/openapi.yaml`** is hand-maintained (no zod-to-openapi generator detected). It describes, but does not enforce.

- **`database/src/handlers/*.ts`** is the indexer-side event handler directory — 27 files including `affiliate.ts`, `baf-jackpot.ts`, `coinflip.ts`, `decimator.ts`, `deity-boons.ts`, `jackpot.ts`, `lootbox.ts`, `quests.ts`, `sdgnrs.ts`, `tickets.ts`, `vault.ts`, etc. These are dispatched by `src/indexer/event-processor.ts` and NOT callable from HTTP. Out of scope for Phase 225.

## Decisions

### D-225-01: Scope `src/handlers/*.ts` OUT of this phase; defer to Phase 227 (IDX-03)

The literal text of API-03 in REQUIREMENTS.md lists both `database/src/handlers/*.ts` and `database/src/api/routes/*.ts`. On inspection, `src/handlers/*.ts` is the indexer event-handler directory. Phase 227 requirement IDX-03 ("Indexer comments describing processing semantics — idempotency, reorg safety, backfill behavior, view-refresh triggers — match the actual behavior of the code") is where that scope naturally lives.

**Action:** Phase 225 audits comments only in `database/src/api/routes/*.ts` (HTTP handlers). When Phase 227 runs, IDX-03's scope is extended to cover `src/handlers/*.ts` (already implied by that phase's description).

**Consequence:** API-03 for this phase will produce findings only for route-file comments. If Phase 229 finds this leaves a coverage gap, it can re-scope in a future milestone.

### D-225-02: Zod schemas are source of truth; openapi.yaml is the side that lags

Because Fastify runtime validation enforces the Zod schemas directly (via `fastify-type-provider-zod`), any disagreement between `openapi.yaml` and a Zod schema means **openapi.yaml is wrong, not the code**. All API-04 and API-05 findings default direction is **code→docs** (openapi lagging behind Zod). Default resolution target is **RESOLVED-DOC** (openapi.yaml patched to match Zod), not **RESOLVED-CODE**.

Exception: if a Zod schema itself has a claim that contradicts what the Zod schema actually does (e.g., a comment on the Zod schema saying "validates X" but the schema doesn't), that's a comment→code issue under API-03, not a Zod-vs-openapi issue.

### D-225-03: Response shape audit depth — spot-check with extrapolation

27 endpoints × nested Zod response trees = thousands of potential field-level comparison rows. Full audit is high-cost-low-signal.

**Approach:** Audit 8 representative endpoints — **one per route file** (`game.ts`, `health.ts`, `history.ts`, `leaderboards.ts`, `player.ts`, `replay.ts`, `tokens.ts`, `viewer.ts`). For each, do a full Zod-tree walk vs openapi.yaml response-schema walk. Pick endpoints that exercise the non-trivial shapes in each file (skip health, use a representative from each larger file).

- **If all 8 sampled endpoints PASS:** record sample catalog with PASS verdicts and an extrapolation statement: "Sampled 8/27 endpoints; all PASS. Remaining 19 endpoints extrapolated PASS given the shared Zod schema infrastructure. Any future Zod↔openapi drift is expected to surface through TypeScript compile-time checks or Fastify runtime serialization errors." Stop here.
- **If any sampled endpoint FAILS:** expand audit to all endpoints in that route file. Continue until all failed-file endpoints are audited.

### D-225-04: Comment mismatch threshold = Tier A + Tier B only

Per user selection, flag these two tiers:

**Tier A (always flag): Outright wrong.**
The comment makes a factual claim the code contradicts. Examples:
- Comment: "returns users sorted by score desc" — code: sorts asc
- Comment: "paginates by cursor" — code: has no cursor logic
- Comment: "always returns 200" — code: returns 404 when player not found
- Comment: documents a parameter the code doesn't read

**Tier B (flag when material): Stale/incomplete.**
The comment documents some behavior but omits a meaningful side effect, branch, or post-condition. "Material" means a caller behaving on the comment alone would make a wrong decision. Examples:
- Comment: "returns player stats" — code also writes to a cache; cache stampedes on cold path
- Comment: "fetches jackpot history" — code filters to the caller's day silently
- Comment: lists two error codes — code throws a third

**Do NOT flag (skipped tiers):**
- **Tier C (missing JSDoc):** a handler with NO JSDoc at all. Absence is a style gap, not a drift finding. Note counts in the catalog summary as context, do not enumerate per-handler.
- **Tier D (cosmetic/typos):** stale parameter names after rename, grammar, typos. Low signal; high noise.

### D-225-05: Three sub-catalog documents

Following the success criteria in ROADMAP.md, produce three separate catalog documents (not a single monolithic catalog), one per API-0N requirement:

- `225-01-HANDLER-COMMENT-AUDIT.md` (API-03) — Tier A + Tier B findings per `src/api/routes/*.ts` handler
- `225-02-RESPONSE-SHAPE-AUDIT.md` (API-04) — 8 sampled endpoints, field-by-field Zod↔openapi response comparison
- `225-03-REQUEST-SCHEMA-AUDIT.md` (API-05) — 6 Zod schema files (`common/game/history/leaderboard/player/tokens`) vs openapi.yaml parameter/body definitions

Each catalog ends with its own finding-candidate stubs.

### D-225-06: Finding IDs = `F-28-225-NN`

Continue the F-28-NN-NN numbering scheme from Phase 224 (which used `F-28-224-NN`). Each catalog contributes to the same pool — IDs are globally sequential within the phase, not per-catalog. Phase 229 consolidates.

### D-225-07: Cross-repo path convention (carried forward from Phase 224)

- Planning artifacts in `degenerus-audit/.planning/phases/225-*/`
- All file:line references in findings point into `/home/zak/Dev/PurgeGame/database/...`
- No files created or modified in `database/` tree

## Specifics

- **Audit target paths (read-only):**
  - HTTP handlers: `/home/zak/Dev/PurgeGame/database/src/api/routes/*.ts` (8 files, ~2826 lines)
  - Zod schemas: `/home/zak/Dev/PurgeGame/database/src/api/schemas/*.ts` (6 files, ~400 lines)
  - OpenAPI spec: `/home/zak/Dev/PurgeGame/database/docs/openapi.yaml` (1708 lines)
  - Input catalog: `.planning/phases/224-api-route-openapi-alignment/224-01-API-ROUTE-MAP.md` (27 PAIRED-BOTH endpoints listed)

- **Severity scheme (carried from D-224-04):**
  - Default: INFO
  - Promote to LOW when caller-breaking:
    - Handler returns a field type that Zod schema says is `string` but actually is `number` (runtime serialization mismatch)
    - Required request parameter documented optional in openapi.yaml (callers omit it, get 400)
    - Response field documented in openapi.yaml that the handler never emits (callers expecting it crash)
  - Do NOT promote beyond LOW — documentation drift is not vulnerability.

- **Sampled endpoints for response-shape audit (D-225-03):**
  One per route file, chosen to exercise non-trivial response shapes. Researcher/executor selects based on line count and response schema complexity visible in route files. Starting suggestions:
  - `game.ts` — `/game/jackpots/overview` or `/game/day/:day/winners` (complex nested shapes)
  - `health.ts` — `/health` (trivial; confirms baseline)
  - `history.ts` — largest endpoint by line count
  - `leaderboards.ts` — `/leaderboards/coinflip` (already inspected, representative)
  - `player.ts` — the address-keyed endpoint with the most fields
  - `replay.ts` — the main replay streaming endpoint
  - `tokens.ts` — only endpoint in file
  - `viewer.ts` — viewer-state summary endpoint with widest surface

## Canonical Refs

- `/home/zak/Dev/PurgeGame/degenerus-audit/.planning/REQUIREMENTS.md` — API-03, API-04, API-05 definitions
- `/home/zak/Dev/PurgeGame/degenerus-audit/.planning/ROADMAP.md` — Phase 225 goal + 4 success criteria
- `/home/zak/Dev/PurgeGame/degenerus-audit/.planning/phases/224-api-route-openapi-alignment/224-01-API-ROUTE-MAP.md` — 27 PAIRED-BOTH endpoints, the input universe for this phase
- `/home/zak/Dev/PurgeGame/degenerus-audit/.planning/phases/224-api-route-openapi-alignment/224-CONTEXT.md` — severity + cross-repo + JUSTIFIED conventions carried forward
- `/home/zak/Dev/PurgeGame/database/src/api/routes/leaderboards.ts` — reference for `schema: { querystring, response }` attachment pattern (lines 1-30 show the pattern used in all route files)
- `/home/zak/Dev/PurgeGame/database/src/api/schemas/common.ts` — reference for Zod schema conventions (address regex, pagination cursor encoding)
- `/home/zak/Dev/PurgeGame/database/docs/openapi.yaml` — the spec under audit
- `/home/zak/Dev/PurgeGame/degenerus-audit/audit/FINDINGS-v27.0.md` — severity/format reference

## Deferred Ideas

- **`src/handlers/*.ts` JSDoc audit** — deferred to Phase 227 (IDX-03), per D-225-01.
- **Zod-to-OpenAPI generator** — if drift persists, adopt `@asteasolutions/zod-to-openapi` (or similar) to auto-generate openapi.yaml from Zod. Deferred; v28.0's scope is audit, not remediation architecture.
- **Tier C / Tier D comment findings** — missing JSDoc and typos were explicitly excluded. If a future milestone wants style enforcement, track counts separately.
- **Full (non-sampled) response-shape audit for the 19 unsampled endpoints** — deferred pending sampled-8 results; re-scope if sampling reveals systemic drift.
- **API-06 error-response audit** — future.
- **API-07 example-snippet audit** — future.

## Downstream Agent Guidance

**For gsd-phase-researcher:**

Research is minimal; CONTEXT.md locks most decisions. Confirm (do not re-investigate):
- Exact representative endpoints per route file for response-shape sampling (D-225-03). Verify each sampled endpoint has a non-trivial response schema (not just `z.object({})`).
- Zod-tree walking strategy for response-shape comparison — how to recursively match Zod schema fields to openapi.yaml response-schema fields. Confirm `z.object`, `z.array`, `z.nullable`, `z.optional`, `z.enum`, `z.coerce.number` all have documented openapi.yaml counterparts.
- Any routes using non-standard schema attachment (e.g., `fastify.route({...})` rather than `fastify.get/post/...`) that might skip the Zod schema path.

Do NOT research:
- Comment audit criteria (D-225-04 locks Tier A + Tier B)
- Scope of `src/handlers/` (D-225-01 locks "defer to Phase 227")
- Direction of Zod-vs-openapi findings (D-225-02 locks openapi lagging)
- Full-audit-vs-sample choice (D-225-03 locks sample with extrapolation)

**For gsd-planner:**

Three plans, likely one per sub-catalog, runnable in wave 1 with no dependencies between them (each reads independent input):

- **Plan 225-01** — `225-01-HANDLER-COMMENT-AUDIT.md`. Walk each HTTP handler in `src/api/routes/*.ts`. For each, compare JSDoc/inline comment claims against handler body. Flag Tier A + Tier B per D-225-04. Handler count per file from Phase 224 catalog: health=1, game=9, history=3, leaderboards=3, player=2, replay=6, tokens=1, viewer=2 (27 total).
- **Plan 225-02** — `225-02-RESPONSE-SHAPE-AUDIT.md`. Sample 8 endpoints per D-225-03. For each, do Zod-tree walk vs openapi.yaml response-schema walk. If any fail, expand file. Extrapolate otherwise.
- **Plan 225-03** — `225-03-REQUEST-SCHEMA-AUDIT.md`. Walk the 6 Zod schema files. For each exported schema, verify openapi.yaml parameter/request-body definition matches (name, type, required/optional, enum, regex/format).

Each plan contributes finding stubs to the shared `F-28-225-NN` pool, numbered sequentially across plans (plan 225-01 stubs might be 01-12, 225-02 might be 13-15, etc. — allocate at execution time based on find order).

All three plans write outputs only to `.planning/phases/225-*/`. No database/ repo writes.
