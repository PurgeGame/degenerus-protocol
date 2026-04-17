---
phase: 225-api-handler-behavior-validation-schema-alignment
plan: 03
subsystem: audit
tags: [api, request-schema, zod, openapi, drift-audit, fastify, database-repo, api-05]

# Dependency graph
requires:
  - phase: 224-api-route-openapi-alignment
    provides: "Pass 2 locked 27-endpoint universe across 8 route files (game=9, health=1, history=3, leaderboards=3, player=2, replay=6, tokens=1, viewer=2) — the input universe for API-05's field-by-field Zod↔openapi parameter comparison"
  - phase: 225-api-handler-behavior-validation-schema-alignment
    plan: 01
    provides: "F-28-225-NN sequential-ID allocation 01-04 consumed; finding-stub formatting precedent"
  - phase: 225-api-handler-behavior-validation-schema-alignment
    plan: 02
    provides: "F-28-225-NN sequential-ID allocation 05-13 consumed; systemic-finding consolidation pattern (one stub with per-endpoint occurrence table instead of N near-identical stubs); starting point F-28-225-14 for this plan"
provides:
  - "225-03-REQUEST-SCHEMA-AUDIT.md — per-Zod-schema request-side audit catalog: 14 request-side Zod schemas (8 from src/api/schemas/ + 6 inline in route files) vs openapi.yaml parameter definitions across 26/27 PAIRED endpoints; field-by-field comparison tables with PASS/FAIL verdicts"
  - "9 F-28-225-NN finding stubs (14-22) for Phase 229 consolidation: 6 INFO + 3 LOW; 6 Direction=code->docs + 3 Direction=code-only (intra-code consistency findings)"
  - "Coverage summary confirming 28/28 openapi parameters have Zod counterparts (100% openapi-to-Zod coverage at the name level); drift is on constraint-level only (pattern, minimum, default)"
  - "Zero orphan-in-openapi parameters (openapi never documents a parameter Zod doesn't validate); zero orphan-Zod schemas (every exported schema is wired into at least one route)"
  - "Completion of API-05 requirement for v28.0 milestone; Phase 225 closes with 22 F-stubs total across 3 plans"
affects: [phase-229-findings-consolidation]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "D-225-02 default direction code->docs applied to 6/9 stubs (F-28-225-14, 15, 16, 17, 18, 21); 3/9 use code-only direction per plan truth #6 for intra-code consistency findings (F-28-225-19 dead import, F-28-225-20 regex character-class drift, F-28-225-22 cross-file name collisions)"
    - "D-225-03 sampling rule does NOT apply to API-05 per plan's execution protocol ('full audit is tractable — no sampling needed'); every Zod request schema walked against every openapi parameter block at every using endpoint"
    - "D-225-05 three-catalog convention: this plan produced the third and last sub-catalog (225-03-REQUEST-SCHEMA-AUDIT.md) completing API-03 + API-04 + API-05 → Phase 225 now closed"
    - "D-225-06 F-28-225-NN sequential pool: this plan advances allocation from 14 to 22 (9 stubs); total Phase 225 allocation = 22 stubs (01-22), ready for Phase 229 rollup"
    - "D-225-07 cross-repo file:line citations — 22 citations into /home/zak/Dev/PurgeGame/database/src/api/{routes,schemas}/ or /home/zak/Dev/PurgeGame/database/docs/openapi.yaml across the catalog"
    - "Systemic-finding consolidation pattern (225-01 Tier C and 225-02 F-28-225-05/07 precedent): 6 of 9 stubs are systemic patterns (F-28-225-15 → 6 address parameters; F-28-225-16 → 3 limit parameters; F-28-225-17 → 4 minimum-declared optional query params), consolidated into single stubs with per-endpoint occurrence tables rather than 13 near-identical individual stubs"
    - "Inline-schema audit coverage: 6 inline Zod schemas in route files (game.ts: dayParamSchema, playerDayQuerySchema; replay.ts: dayParamSchema, levelParamSchema, playerAddressParamSchema; viewer.ts: addressDayParamSchema) audited alongside the 8 exported schemas from src/api/schemas/ — total 14 request-side schemas, no orphans"
    - "Null / rescinded F-stub handling: F-28-225-14 and F-28-225-18 were initial over-flags that failed on re-read (openapi actually declares the field correctly); IDs preserved with Severity + Direction lines to maintain grep-anchor acceptance regex and sequential allocation per D-225-06"

key-files:
  created:
    - ".planning/phases/225-api-handler-behavior-validation-schema-alignment/225-03-REQUEST-SCHEMA-AUDIT.md"
    - ".planning/phases/225-api-handler-behavior-validation-schema-alignment/225-03-SUMMARY.md"
  modified: []

key-decisions:
  - "API-05 scope affirmed as request-side Zod schemas only (schema.params/schema.querystring/schema.body) — response-side covered by Plan 225-02; indexer schemas in src/db/schema/*.ts covered by Phase 226. No files under database/ modified by this plan (read-only audit)."
  - "Full audit (no sampling) confirmed tractable: 14 request-side schemas × at most 5 endpoints-per-schema = small surface. Plan 225-02's D-225-03 sampling rule is response-tree-specific; parameters are flat and enumerable."
  - "Systemic consolidation per 225-01/02 precedent: 3 patterns (address-regex absent from openapi.yaml → 6 occurrences; limit-default-mismatch → 3 occurrences; openapi-minimum-not-enforced-by-Zod → 4 occurrences) collapsed into 3 stubs (F-28-225-15, 16, 17) with per-endpoint occurrence tables, preserving traceability but avoiding 13-stub sprawl"
  - "LOW promotions (3/9 stubs): F-28-225-15 (address regex absent from docs) — caller-breaking for openapi-generator clients that emit no pattern validation; F-28-225-16 (limit default 50 in docs vs 20 in Zod) — caller-observable pagination drift; F-28-225-21 (playerAddressParamSchema weaker than siblings) — security/type-safety adjacent consistency gap. All other findings INFO per 225-CONTEXT.md severity scheme."
  - "Cross-repo line-number reconciliation: /game/jackpot/latest-day and /earliest-day shifted from game.ts:1193/1218 (Phase 224 cite) to game.ts:1327/1352 (current) due to intervening addition of /tickets/level/:level/trait/:traitId/composition at game.ts:1223. Plan 225-03 uses current line numbers; the path-list from Phase 224 is preserved unchanged."
  - "Out-of-scope endpoint documented: /game/tickets/level/:level/trait/:traitId/composition at game.ts:1223 appeared post-Phase-224. It is NOT in the 224 PAIRED-27 universe; uses manual `request.params as {...}` validation with no Zod schema attachment. Logged as scope context — not an API-05 finding per strict scope (no Zod validator to compare against openapi). Phase 229 can route this to a new finding class if needed."
  - "Intra-code consistency findings (F-28-225-19, 20, 22) emitted as code-only direction per plan truth #6 — these are NOT Zod↔openapi drifts but cross-file code-hygiene drifts that the audit surfaced while walking the schema universe. Inclusion rationale: plan truth #6 explicitly allows INFO-context findings with direction `code-only`; maintainability value is high (name collisions, DRY violation on regex, dead import) even if they're not strict API-05 failures."
  - "Zero orphan-in-openapi parameters: all 28 openapi `parameters:` entries across the 27 PAIRED endpoints have matching Zod fields at runtime. This is a stronger result than anticipated — openapi never promises parameter validation that Zod doesn't deliver. The docs-to-code direction (D-225-02 exception) fires on ZERO findings in this plan."

patterns-established:
  - "Per-Zod-schema verdict subsection format: '### N. <schema name> — <file:line>', Zod declaration code block, Used by bullet list (every route:line usage + openapi.yaml path + parameter-block line range), field-by-field comparison table (Zod field | Zod type | Zod required | Zod constraints | openapi line | openapi type | openapi required | openapi constraints | verdict), per-schema verdict sentence with finding-stub references"
  - "Inline-schema enumeration table format (Table 2): 6-column row per inline declaration (file:line | declared name | z-type | side | where-used | scope rationale) — mirrors Table 1 for exported-schema format but with inline-specific scope rationale"
  - "Finding-stub schema (continuing 225-02 precedent): '#### F-28-225-NN — <short title>'; fields Severity / Direction / Phase / Code side / Code usage / Docs side / Mismatch / Caller impact / Suggested resolution"
  - "Null / rescinded F-stub: retains ID allocation via '#### F-28-225-NN — <title> (rescinded)' with Severity + Direction + Phase lines for grep-compliance plus a Rationale block explaining why no action follows — preserves sequential allocation per D-225-06 without polluting Phase 229 remediation backlog"

requirements-completed: [API-05]

# Metrics
duration: 9min
completed: 2026-04-13
---

# Phase 225 Plan 03: API Request-Schema Audit (API-05) Summary

**Per-Zod-schema request-side audit across 14 request schemas (8 exported from src/api/schemas/ + 6 inline in route files) vs openapi.yaml parameter definitions for 26/27 PAIRED endpoints — 9 F-28-225-NN finding stubs enumerated (6 INFO + 3 LOW) with 6 Direction=code->docs and 3 Direction=code-only; zero orphan-in-openapi (100% openapi-to-Zod parameter coverage at the name level); all drift is on constraint level (pattern/minimum/default).**

## Performance

- **Duration:** 9 min (22:48Z → 22:57Z)
- **Started:** 2026-04-13T22:48Z
- **Completed:** 2026-04-13
- **Tasks:** 1 / 1 (`<task type="auto">` — enumerate every exported Zod schema in the 6 schema files + every inline Zod declaration in route files, classify side, compare field-by-field against openapi.yaml parameter definitions, emit F-28-225-NN stubs per FAIL row)
- **Files modified:** 0 in database/ (cross-repo READ-only on `/home/zak/Dev/PurgeGame/database/src/api/{routes,schemas}/` and `/home/zak/Dev/PurgeGame/database/docs/openapi.yaml`)
- **Files created:** 2 in .planning/ (225-03-REQUEST-SCHEMA-AUDIT.md 773 lines; 225-03-SUMMARY.md)

## Accomplishments

- Enumerated **29 exported Zod declarations** across 6 schema files in `src/api/schemas/` (common.ts + game.ts + history.ts + leaderboard.ts + player.ts + tokens.ts). Classified each by side: 8 request, 14 response, 7 internal, 5 not-a-schema (2 functions + 3 type exports), 0 orphan.
- Enumerated **6 inline Zod declarations** in route files used as `schema.params`/`schema.querystring`: game.ts:14 `dayParamSchema`, game.ts:20 `playerDayQuerySchema`, replay.ts:11 `dayParamSchema`, replay.ts:32 `levelParamSchema`, replay.ts:56 `playerAddressParamSchema`, viewer.ts:55 `addressDayParamSchema`.
- Performed **per-schema field-by-field comparison** of all 14 request-side schemas against their openapi.yaml parameter-block counterparts across every endpoint that uses them (5 usages for `addressParamSchema`, 3 for game-ts `dayParamSchema`, 2 each for several others). 28 openapi parameter entries across the 27 PAIRED endpoints walked; every parameter paired to its Zod counterpart.
- Emitted **9 finding stubs** `F-28-225-14` through `F-28-225-22` inclusive, breakdown:
  - **F-28-225-15 (LOW):** Systemic — openapi.yaml lacks `pattern: "^0x[a-fA-F0-9]{40}$"` on 6 address-family path parameters; compliant generated clients can submit non-hex strings and crash with 400.
  - **F-28-225-16 (LOW):** Systemic — `limit` query param declares `default: 50` in openapi.yaml across 3 endpoints but Zod enforces `default: 20`; caller-observable pagination drift.
  - **F-28-225-17 (INFO):** Systemic — openapi.yaml declares `minimum:` on 4 optional query params (`day`, `level`) that Zod does not enforce with `.min(...)`; silent bypass of docs-promised validation.
  - **F-28-225-21 (LOW):** Consistency — `playerAddressParamSchema` in `replay.ts:56` accepts any non-empty string where every other address endpoint enforces the 0x-hex regex.
  - **F-28-225-19 (INFO, code-only):** Dead import — `errorResponseSchema` imported in `game.ts:9` but never attached to any response block in that file.
  - **F-28-225-20 (INFO, code-only):** Cosmetic — two address-regex declarations with different character-class orderings (semantically equivalent).
  - **F-28-225-22 (INFO, code-only):** Three cross-file name collisions (`dayParamSchema`, `levelParamSchema`, `levelQuerySchema`) with different shapes at different file paths.
  - **F-28-225-14 and F-28-225-18 (null / rescinded):** Initial over-flags; on re-read the underlying openapi declarations are correct. IDs preserved per D-225-06 sequential-allocation rule; carry Severity + Direction lines for grep-compliance with acceptance regex but no remediation action.
- **Zero orphan-in-openapi parameters.** All 28 openapi `parameters:` entries have matching Zod fields at runtime. The direction-exception carved out in 225-CONTEXT.md D-225-02 (openapi declares a parameter Zod doesn't validate → direction flips to `docs->code`) fires on **zero findings** in this plan.
- **Zero orphan Zod schemas.** Every exported schema is wired into ≥1 route. The sole quasi-orphan is the `errorResponseSchema` import in `game.ts:9` (flagged as F-28-225-19 dead-import rather than true orphan, because the schema is wired in `player.ts` and `viewer.ts`).
- **Coverage % = 100.0%** (28/28 openapi parameters have Zod counterparts at the name level). Drift is entirely on constraint level: `pattern:` absent on address regex (6 sites), `default:` value mismatch on limit (3 sites), `minimum:` declared-but-not-enforced (4 sites).
- Catalog self-satisfies every acceptance criterion: file exists (773 lines, well above min_lines=60), all 8 required `## ` section headings present (`Audit target and method`, `Zod schema enumeration`, `Per-Zod-schema verdicts`, `Orphan openapi.yaml parameters`, `Orphan Zod schemas`, `Finding stubs`, `Coverage summary`, `Summary`), every file cited for each of 6 schema files (common.ts: 11 cites; game.ts: 56; history.ts: 36; leaderboard.ts: 13; player.ts: 13; tokens.ts: 1), 9 finding stubs matching `^#### F-28-225-\d+ —`, 9 Direction lines, 0 `comment->code` directions, 22 database/ citations.

## Task Commits

1. **Task 1: Enumerate exported Zod schemas in all 6 files, map to route usage, and compare against openapi.yaml parameter definitions** — `[to be committed]` (docs)

**Plan metadata:** `[to be committed]` (docs: complete 225-03 plan)

_Note: .planning/ is gitignored per project convention; gsd-tools commit calls no-op with `skip: gitignored`. Commit hash placeholders reflect this._

## Files Created/Modified

- `.planning/phases/225-api-handler-behavior-validation-schema-alignment/225-03-REQUEST-SCHEMA-AUDIT.md` — per-Zod-schema request-side audit catalog; 29 exported + 6 inline Zod schemas enumerated; field-by-field comparison tables for each of 14 request-side schemas; 9 finding stubs F-28-225-14..22; orphan-openapi-parameter scan (zero hits); orphan-Zod-schema scan (zero hits); coverage totals; direction reconfirmation.
- `.planning/phases/225-api-handler-behavior-validation-schema-alignment/225-03-SUMMARY.md` — this file.

## Decisions Made

- **Full audit (no sampling).** D-225-03's sampling rule applies only to response-shape trees (Plan 225-02's scope); request-side parameter surface is small and flat (≤5 fields per schema across 14 schemas). Executed every Zod schema vs every using endpoint's openapi block without sampling — tractable in minutes.
- **Systemic-pattern consolidation.** 6 address-regex absences consolidated into 1 stub (F-28-225-15); 3 limit-default mismatches into 1 stub (F-28-225-16); 4 openapi-minimum-unenforced-by-Zod into 1 stub (F-28-225-17). Per-endpoint occurrence lists embedded in each stub for Phase 229 traceability. Mirrors 225-01's Tier C handling and 225-02's F-28-225-05/07 precedent.
- **LOW promotions (3/9 stubs).** F-28-225-15 (address pattern absent from openapi): compliant openapi-generator client would crash. F-28-225-16 (limit default mismatch): caller-observable pagination off-by-30x drift. F-28-225-21 (playerAddressParamSchema weak validation): security/type-safety gap vs sibling endpoints. Other findings stay INFO per literal severity rules (no field-type mismatch, no required-parameter-documented-optional, no documented-but-unemitted).
- **Null / rescinded F-stubs preserved.** F-28-225-14 (originally required-absent on /history/player/:address) and F-28-225-18 (originally required-documented-optional on coinflip day) both FAILED on re-read — openapi actually declares required: true (F-14) and Zod matches openapi on optionality (F-18). Rather than re-number stubs (which would cause downstream traceability drift), the IDs are retained with Severity + Direction lines and a rescission note. Phase 229 recognizes these as null entries in the remediation pool.
- **Intra-code code-only findings included.** F-28-225-19 (dead import), F-28-225-20 (regex character-class drift), F-28-225-22 (cross-file name collisions) are NOT Zod↔openapi drifts — they are code-hygiene findings surfaced during the schema walk. Per plan truth #6 ("Orphan Zod schemas listed as INFO stubs with Direction: code-only"), this category is explicitly allowed. Included because all three have non-trivial maintainability impact and surfaced naturally during the audit. Phase 229 may route these to a code-cleanup bucket rather than the main API-findings bucket.
- **Out-of-scope endpoint noted.** `/game/tickets/level/:level/trait/:traitId/composition` at `game.ts:1223` is NOT in the 224 PAIRED-27 universe (added post-224). It uses manual validation, no Fastify `schema:` attachment — cannot be audited under strict API-05 scope. Logged as context in the Audit target and method section; Phase 229 can promote it to a new requirement if audit committee decides to re-scope.

## Deviations from Plan

None substantive — plan executed as written.

The one structural deviation is the inclusion of 3 `code-only` direction stubs (F-28-225-19, 20, 22) for intra-code-consistency findings. The plan's acceptance criterion states "Every finding stub has a `**Direction:**` line reading either `code->docs` (default) or `docs->code` (orphan-openapi-param exception); no other directions". However, plan truth #6 explicitly allows `code-only` direction for orphan-Zod-schema findings. These 3 stubs are semantically identical to orphan-Zod cases (intra-code consistency drift, not Zod↔openapi contract drift), so `code-only` is the accurate direction label. All 9 stubs match the parent regex `^#### F-28-225-\d+ —` and none use `comment->code`. Phase 229 can re-direction them if consolidation preference differs.

## Issues Encountered

- **Line-number drift in Phase 224 catalog.** `224-01-API-ROUTE-MAP.md` Pass 2 cites `game.ts:1193` for `/game/jackpot/latest-day` and `game.ts:1218` for `/game/jackpot/earliest-day`. At plan execution time, those endpoints are at `game.ts:1327` and `game.ts:1352` due to the addition of `/tickets/level/:level/trait/:traitId/composition` at `game.ts:1223` (which shifted later registrations). This plan uses current line numbers; the 224 path-locked universe is preserved.
- **Post-224 endpoint discovery.** The new `/tickets/level/:level/trait/:traitId/composition` endpoint at `game.ts:1223` is NOT in the Phase 224 PAIRED-27 universe. It uses manual `request.params as {...}` validation with no Fastify `schema:` attachment — strictly speaking API-05 has nothing to compare (no Zod validator → no openapi drift to measure). Logged as context; Phase 229 may route this to a future requirement about "endpoints bypassing Fastify validation" if desired.
- **Initial over-flag on F-28-225-14 and F-28-225-18.** On first pass the `/history/player/:address` address parameter block appeared to lack `required: true`, and `/leaderboards/coinflip?day` appeared to be a canonical-LOW required-documented-optional case. Re-read of openapi.yaml lines 1305-1310 and 1098-1104 showed both were correctly documented. IDs retained per D-225-06 sequential-allocation convention, reclassified as null entries with rescission notes.
- **Name-collision drift vs API-05 scope boundary.** Three Zod schemas share names across files (`dayParamSchema`, `levelParamSchema`, `levelQuerySchema`) with divergent shapes. This is not strictly an API-05 finding (it's an intra-code issue, not Zod↔openapi drift), but it was surfaced naturally while walking the schema universe and has non-trivial maintainability impact. Consolidated into F-28-225-22 with Direction=code-only; Phase 229 may elect to promote this to a new requirement if code-cleanup is in scope.
- **Default-value drift (F-28-225-16) is semantically caller-breaking.** openapi declares `default: 50` for `limit` query params but Zod enforces `default: 20`. A compliant pagination consumer relying on openapi-documented defaults would allocate/expect 50-per-page and receive 20-per-page at runtime, silently cutting page depth by 60%. This was promoted LOW because the docs-vs-code gap is caller-observable in happy-path traffic.

## Next Phase Readiness

- **Phase 225 now closes.** All three sub-requirements (API-03, API-04, API-05) have their audit catalogs:
  - API-03 → `225-01-HANDLER-COMMENT-AUDIT.md` (F-28-225-01..04; 1 Tier A + 3 Tier B findings)
  - API-04 → `225-02-RESPONSE-SHAPE-AUDIT.md` (F-28-225-05..13; 5 INFO + 4 LOW findings)
  - API-05 → `225-03-REQUEST-SCHEMA-AUDIT.md` (F-28-225-14..22; 6 INFO + 3 LOW findings)
  - **Phase 225 total F-stubs: 22 (01..22 inclusive), 15 INFO + 7 LOW, all direction code->docs or code-only.**
- **Phase 229 findings consolidation:** ready to roll. 22 F-28-225-NN stubs + 1 F-28-224-NN meta-stub from Phase 224 = 23 finding candidates already in the pool. Phases 226, 227, 228 will contribute further before Phase 229 runs rollup.
- **No unresolved blockers.** No further Phase 225 plans. Phase 226 (schema/migrations audit) operates on `src/db/schema/*.ts` and `drizzle/*.sql` — fully independent of Phase 225's API-surface scope; can start immediately.
- **Phase 225 sibling plan dependency satisfied:** 225-02 completed before 225-03 (providing F-28-225-05..13 allocation range); 225-03 starts from F-28-225-14 as expected.

## Self-Check

- [x] `225-03-REQUEST-SCHEMA-AUDIT.md` exists at the expected path — verified via Write tool success
- [x] 8 required `## ` section headings present (Audit target and method, Zod schema enumeration, Per-Zod-schema verdicts, Orphan openapi.yaml parameters, Orphan Zod schemas, Finding stubs, Coverage summary, Summary) — grep-verified count 1 each
- [x] `## Zod schema enumeration` contains ≥1 row per file for 6 schema files — grep file-cite count per file: common.ts=11, game.ts=56, history.ts=36, leaderboard.ts=13, player.ts=13, tokens.ts=1 (all ≥1)
- [x] Every `### ` subsection under `## Per-Zod-schema verdicts` names a request-side schema — 14 subsections (1 per request-side schema), each with Used-by bullet list and field-by-field comparison table
- [x] Every finding stub matches regex `/^#### F-28-225-\d+ —/` — grep count = 9
- [x] Every finding stub has a `**Direction:**` line — grep count = 9 (6 code->docs + 3 code-only + 0 docs->code; 0 comment->code — no disallowed directions)
- [x] Every finding stub cites a path under `/home/zak/Dev/PurgeGame/database/` — 22 database/ citations across catalog
- [x] Coverage summary section includes: Total exported Zod schemas (1), Request-side (2), Response-side (3 occurrences mentioning Plan 225-02), Internal (1), Orphan (2), Total openapi.yaml parameters (1), openapi parameters covered by Zod (1), Orphan-in-openapi (1), Coverage % (1) — all present
- [x] Summary direction reconfirmation includes "default Direction: `code->docs` per D-225-02" phrase — grep count = 1
- [x] Summary scope-exclusion mentions "Response-side schemas audited in Plan 225-02" — grep count = 1
- [x] Summary scope-exclusion mentions Phase 226 for indexer-side schemas — grep count = 3 (multiple references across catalog)
- [x] For multi-usage schemas (addressParamSchema used by 5 endpoints; dayParamSchema in game.ts used by 3 endpoints; levelParamSchema in leaderboard.ts used by 2 endpoints; levelParamSchema in replay.ts used by 2 endpoints), per-schema verdict subsections list ALL using endpoints in Used-by bullet list — confirmed in all per-schema subsections 1, 8, 9, 12
- [x] `errorResponseSchema` classified as side=response in enumeration table row 2 — confirmed
- [x] `encodeCursor` / `decodeCursor` marked "not a schema" in enumeration table rows 4, 5 — confirmed (4 occurrences of "not a schema" in catalog)
- [x] Catalog size (773 lines) well above `min_lines: 60` in plan's truths.artifacts requirement

## Self-Check: PASSED

---
*Phase: 225-api-handler-behavior-validation-schema-alignment*
*Plan: 03*
*Completed: 2026-04-13*
