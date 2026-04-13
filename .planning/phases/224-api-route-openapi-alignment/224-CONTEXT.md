# Phase 224 Context: API Route & OpenAPI Alignment

**Milestone:** v28.0 Database & API Intent Alignment Audit
**Phase number:** 224
**Phase name:** API Route & OpenAPI Alignment
**Requirements:** API-01, API-02
**Date:** 2026-04-13

## Phase Boundary

**In scope:** Bidirectional coverage audit between `database/src/api/routes/*.ts` and `database/docs/openapi.yaml` + `database/docs/API.md`. For every endpoint, verify the pair exists on both sides and that method + path + parameter **names** + request-body-shape **presence** agree.

**Explicitly NOT in scope for this phase:**
- Deep parameter-type or request/response schema comparison — that is **Phase 225** (API-04, API-05)
- Handler JSDoc/inline comment accuracy — that is **Phase 225** (API-03)
- Error-response / status-code audit — deferred as **API-06** (future)
- API.md example-snippet correctness — deferred as **API-07** (future)
- Schema file audit — **Phase 226**
- Indexer audit — **Phases 227/228**

Audit grades against three intent sources per milestone scope: `API.md`, `openapi.yaml`, and in-source comments (but comment correctness is Phase 225 — Phase 224 only uses comments as supporting context, not as an audit dimension).

## Current Observations (from scouting)

- **Route registrations in code:** 28 total across 8 files
  - `game.ts` (9), `health.ts` (2), `history.ts` (3), `leaderboards.ts` (3), `player.ts` (2), `replay.ts` (6), `tokens.ts` (1), `viewer.ts` (2)
- **Path entries in openapi.yaml:** 27 (one count short already — drift exists)
- **openapi.yaml is hand-maintained** — no zod-to-openapi or similar generator detected in `database/src/` or `database/scripts/`
- **Route files use `fastify-type-provider-zod`** — validation schemas live in `database/src/api/schemas/` and are imported into route files
- **database/ package.json** has `test: vitest run` — real test infrastructure, npm-script-based gates would be the natural fit if one were built

## Decisions

### D-224-01: Catalog-only; no regression gate shipped this phase

Phase 224 produces a PASS/FAIL catalog document and nothing else. No gate script is wired into any CI / test / Makefile target.

**Rationale:**
- Audit-phase precedent — most audit phases since v25.0 ship only catalog docs; gates (v27.0) were reserved for specific classes of runtime bugs (delegatecall, raw selectors, coverage)
- Cross-repo mechanical cost — a gate would live in either `degenerus-audit/scripts/` (awkward cross-repo path resolution) or `database/scripts/` (adds maintenance burden in a repo this milestone is only auditing)
- External tooling exists — `oasdiff`, `openapi-diff` etc. already solve this — a bespoke script would reinvent
- Drift already visible (28 vs 27) — findings will bubble to Phase 229, where resolution can include a backlog entry for a future gate if drift persists

**Consequence:** If drift reappears later, it will show up in a future audit cycle, not in CI. The milestone explicitly accepts that tradeoff for v28.0.

### D-224-02: Output is `224-01-API-ROUTE-MAP.md` in this phase directory

Single catalog document. No split across multiple plan files unless scope grows past 28 endpoints × 2 directions = 56 verdicts + summary (unlikely).

### D-224-03: Bidirectional verdict format

Two audit passes in one document:
- **Pass 1 — openapi→code:** for each `/path:` in `openapi.yaml`, find matching route registration; verdict `PAIRED` / `MISSING-IN-CODE`
- **Pass 2 — code→openapi+API.md:** for each route registration in code, find matching entry in `openapi.yaml` AND in `API.md`; verdict `PAIRED-BOTH` / `MISSING-OPENAPI` / `MISSING-APIMD` / `MISSING-BOTH`

For paired endpoints, a per-field check of (method, path normalization, parameter names present on both sides, request-body-shape presence) produces sub-verdicts.

### D-224-04: Severity default INFO, promotable on case basis

Per v27.0 precedent, doc-drift findings default to INFO. Promotion criteria for LOW or higher:
- An implemented endpoint missing from `openapi.yaml` that accepts unvalidated user input → LOW (contract gap)
- An `openapi.yaml` endpoint with no matching implementation → LOW (dead contract / broken consumer promise)
- Method/path mismatch (e.g., openapi declares `GET /x` but code has `POST /x`) → LOW (caller-breaking)
- Missing parameter declaration on one side (e.g., code accepts `?day=` that openapi does not document) → INFO (unless it's a security-relevant parameter)

### D-224-05: Cross-repo path handling

Planning artifacts stay in `degenerus-audit/.planning/phases/224-*/`. All file:line references in findings point into `/home/zak/Dev/PurgeGame/database/...`. No files created in the `database/` repo for this phase (no scripts, no docs).

### D-224-06: Justified-mismatch mechanism = inline commentary in catalog

Intentional drift (e.g., health check endpoints some teams omit from public spec) is handled by a `JUSTIFIED` verdict in the catalog with a one-sentence rationale column. No separate allowlist file.

## Specifics

- **Audit target paths:**
  - Code: `/home/zak/Dev/PurgeGame/database/src/api/routes/*.ts` (8 files, 28 route registrations)
  - Spec: `/home/zak/Dev/PurgeGame/database/docs/openapi.yaml` (1708 lines, 27 path entries)
  - Prose: `/home/zak/Dev/PurgeGame/database/docs/API.md` (883 lines)
- **Route-registration detection pattern:** `fastify.(get|post|put|delete|patch)(...)` — scan all 8 route files
- **openapi.yaml path detection pattern:** top-level `paths:` map keys
- **API.md endpoint detection:** `###` or `####` headings naming `METHOD /path` — confirm by inspection before committing to pattern

## Canonical Refs

- `/home/zak/Dev/PurgeGame/degenerus-audit/.planning/REQUIREMENTS.md` — API-01, API-02 definitions
- `/home/zak/Dev/PurgeGame/degenerus-audit/.planning/ROADMAP.md` — Phase 224 goal and success criteria
- `/home/zak/Dev/PurgeGame/degenerus-audit/audit/FINDINGS-v27.0.md` — reference structure for finding catalog + severity scheme
- `/home/zak/Dev/PurgeGame/database/docs/openapi.yaml` — spec under audit
- `/home/zak/Dev/PurgeGame/database/docs/API.md` — prose docs under audit
- `/home/zak/Dev/PurgeGame/database/src/api/routes/game.ts` — largest route file (1242 lines, 9 registrations) — representative for scouting complexity
- `/home/zak/Dev/PurgeGame/database/src/api/schemas/` — Zod schemas referenced by routes (context for Phase 225 handoff, not audited here)

## Deferred Ideas

Captured so they aren't lost; not in scope for Phase 224.

- **Regression gate** — if doc-drift findings persist across v28.0 and a future milestone, build a gate. Options at that time: JS script in `database/scripts/check-api-doc-alignment.mjs` (most ergonomic), bash in `degenerus-audit/scripts/` (consistent with v27.0 pattern), or adopt `oasdiff`/`openapi-diff` as a dev-dep. Decision deferred.
- **Zod-to-OpenAPI generator** — if hand-maintained openapi.yaml becomes a recurring drift source, evaluate `@asteasolutions/zod-to-openapi` or similar to auto-generate openapi.yaml from the Zod schemas already in use. That eliminates an entire class of drift by construction but changes the docs-authoring workflow.
- **API.md example-snippet correctness (API-07)** — full curl/payload match is future work.
- **Error-response/status-code audit (API-06)** — future work.

## Downstream Agent Guidance

**For gsd-phase-researcher:**
Given the decisions above, research is minimal. Confirm (don't re-investigate):
- openapi.yaml parse approach (JS `js-yaml` if scripting, or a simple manual walk for a catalog-only audit)
- API.md endpoint-heading convention by sampling the file
- Whether any routes use Fastify's `fastify.route({...})` form (not just `fastify.get/post/...`) that would escape the simple regex
- Any route-path prefixing via `fastify.register({prefix: ...})` so paths compared to openapi are resolved to their full form

Do NOT research:
- Doc-drift tools (decision locked: no tool)
- Gate-script design (decision locked: no gate)
- Severity escalation philosophy (locked via D-224-04)

**For gsd-planner:**
This phase has a single expected plan: `224-01-PLAN.md` producing `224-01-API-ROUTE-MAP.md`. Task breakdown:
1. Enumerate openapi.yaml paths (flat key list from `paths:` block)
2. Enumerate route registrations across 8 route files (respect any `register({prefix:})` path composition)
3. Enumerate API.md endpoint headings
4. Cross-reference all three; produce three-column table (openapi / code / API.md) with per-row verdict
5. Summarize: total endpoints on each side, paired count, per-direction drift count, promoted-severity findings
6. Append finding candidates (F-28-NN-224-NN stubs) for Phase 229 rollup

Single plan unless complexity during research flags need for a split.
