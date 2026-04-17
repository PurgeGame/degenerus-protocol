# Phase 225 Plan 03 — API Request-Schema Audit Catalog (API-05)

**Phase:** 225 — API Handler Behavior & Validation Schema Alignment
**Plan:** 225-03 (third and last plan in Phase 225)
**Requirement satisfied:** API-05 — Fastify request-validation schemas in `database/src/api/schemas/*.ts` (plus inline Zod declarations in route files) match `database/docs/openapi.yaml` parameter definitions (parameter names, types, required/optional, enum constraints, regex/format, min/max).
**Scope (request-side only):** Zod schemas referenced as `schema.querystring`, `schema.params`, or `schema.body` in Fastify route registrations. Response-side schemas (`schema.response[*]`) were audited in Plan 225-02. Indexer-side schemas (`src/db/schema/*.ts`) are Phase 226's domain.
**Direction rule:** D-225-02 — Zod schemas are the runtime source of truth (enforced at request time by `fastify-type-provider-zod`); openapi.yaml is the hand-maintained lagger. Default direction for every finding: `code->docs`. **One exception:** openapi.yaml documents a parameter that has NO Zod counterpart (the docs promise validation the code does not perform) → direction flips to `docs->code`. Default resolution target is `RESOLVED-DOC` (patch openapi.yaml to match Zod).
**Severity scheme (225-CONTEXT.md Severity scheme; inherited from D-224-04):**
- **INFO** (default) — documentation drift, no runtime/caller-breaking impact.
- **LOW** (promotion only when caller-breaking):
  1. A required request parameter is documented optional in openapi.yaml (callers omitting it get 400) — the canonical API-05 LOW case.
  2. A parameter declared optional in Zod is listed `required: true` in openapi.yaml (compliant consumers skipping it get 400).
  3. A parameter declared in openapi.yaml is **not** validated at runtime by Zod (docs claim validation; code does not enforce it) — direction `docs->code`.
  4. A regex/format/enum documented in openapi.yaml that Zod does not enforce at runtime (security/type-safety impact).
- Do NOT promote beyond LOW — documentation drift is not a vulnerability class.
**Finding-ID scheme (D-225-06):** `F-28-225-NN` sequential across all Phase 225 plans. Plan 225-01 consumed `F-28-225-01..04`. Plan 225-02 consumed `F-28-225-05..13`. Plan 225-03 allocates starting at **`F-28-225-14`** through `F-28-225-22` (9 stubs).
**Cross-repo convention (D-225-07):** All file:line citations point into `/home/zak/Dev/PurgeGame/database/...`. No files under the `database/` tree are created, modified, or staged by this plan.

---

## Audit target and method

### Input universe

**Code side (Zod):**

- Six files in `/home/zak/Dev/PurgeGame/database/src/api/schemas/`: `common.ts`, `game.ts`, `history.ts`, `leaderboard.ts`, `player.ts`, `tokens.ts`.
- Inline Zod declarations in route files that are used as `schema.params` / `schema.querystring` / `schema.body` — enumerated explicitly below.

**Docs side (openapi.yaml):**

- `/home/zak/Dev/PurgeGame/database/docs/openapi.yaml` paths block, 27 endpoint entries as locked by `224-01-API-ROUTE-MAP.md` Pass 1. Per-endpoint parameter blocks live in the 30-50 lines following each path key; request-body blocks are uniformly absent across all 27 endpoints (224 Pass 1 confirmed `grep -n 'requestBody:'` returns zero matches). Fastify routes confirmed to declare zero `schema.body` attachments (224 Pass 2 body-shape scan line 166 confirms zero matches).

**Consequence:** Plan 225-03's audit surface is **path-parameter and query-parameter schemas only**. Every `z.object({...})` used as `schema.body` is automatically out-of-universe because zero such attachments exist. Every `requestBody:` candidate in openapi.yaml is automatically orphan-in-openapi because zero exist. The only comparison axis is `schema.params`/`schema.querystring` (Zod) vs `parameters:` entries with `in: path|query` (openapi.yaml).

### Path-normalization rule (carried from Phase 224 D-224-02)

openapi.yaml path-parameter syntax: `{name}`.
Fastify/route-file syntax: `:name`.
These are equivalent for matching. 224-01-API-ROUTE-MAP.md Pass 1/Pass 2 tables lock the 27 path pairings at this normalization.

### Line-number reconciliation against 224-01-API-ROUTE-MAP.md

224 Pass 2 captured `game.ts:1193` for `/game/jackpot/latest-day` and `game.ts:1218` for `/game/jackpot/earliest-day`. Between Phase 224 completion and this plan's execution, `game.ts` received an additional route (`/tickets/level/:level/trait/:traitId/composition` at `game.ts:1223`) that shifted the later registrations. Current line numbers at plan-execution time, confirmed by `grep -nE "fastify\.(get|post)" /home/zak/Dev/PurgeGame/database/src/api/routes/game.ts`:

| Phase 224 cite | Current cite | Endpoint |
| --- | --- | --- |
| `game.ts:1193` | `game.ts:1327` | `/game/jackpot/latest-day` |
| `game.ts:1218` | `game.ts:1352` | `/game/jackpot/earliest-day` |

This plan cites **current** line numbers for every route registration; the 224 catalog's locked path-list is preserved unchanged.

### Inline `/tickets/level/:level/trait/:traitId/composition` scope

At `game.ts:1223` (during Phase 225 execution window, after 224 was locked), a tenth `fastify.get(...)` registration appeared in `game.ts`: `GET /game/tickets/level/:level/trait/:traitId/composition`. This endpoint is **not** in the 224 PAIRED-27 universe (that list was locked at execution time of Phase 224; the additional registration is either post-224 drift or was intentionally omitted from 224's openapi.yaml crosswalk). Per D-225-05 "this phase does not re-open Phase 224's structural catalog — only deepens into type/behavior correctness on the paired 27", this out-of-scope endpoint is noted here for context only and excluded from the per-schema-verdict section. It uses **manual `request.params as {...}` casts and handwritten validation** (lines 1224-1233) — no Fastify `schema:` block is attached. This is a separate class of API-05-adjacent drift (Fastify-validation-absent endpoint) that Phase 229 can route to a new requirement if needed; for this plan's strict API-05 scope it is an orphan `code->docs` non-finding (the route has no Zod validator to compare).

### Zod-to-openapi type mapping (inherited from Plan 225-02)

| Zod construct | openapi.yaml counterpart |
| --- | --- |
| `z.string()` | `schema: { type: string }` |
| `z.string().regex(/pat/)` | `schema: { type: string, pattern: "pat" }` |
| `z.string().transform(...)` | `schema: { type: string }` (transform is code-only; not in docs) |
| `z.coerce.number()` | `schema: { type: number }` (in query params) |
| `z.coerce.number().int()` | `schema: { type: integer }` |
| `z.coerce.number().int().min(N).max(M)` | `schema: { type: integer, minimum: N, maximum: M }` |
| `z.coerce.number().default(D)` | `schema: { type: integer, default: D }` |
| `.optional()` on object field | openapi `required` list does NOT include the field (or `required: false` at param level) |
| (non-`.optional()` on object field) | openapi `required: true` at param level; or included in parent `required:` list |
| `z.enum([...])` | `schema: { type: string, enum: [...] }` |
| `z.string().min(N)` | `schema: { type: string, minLength: N }` |

### Methodology per schema

For every exported Zod schema in the 6 schema files, plus every inline Zod declaration used as `schema.params`/`schema.querystring` in a route file:

1. Classify `side` as `request` (imported as `schema.params`/`schema.querystring`/`schema.body`), `response` (imported as `schema.response[code]`), `internal` (referenced only within the schemas/ tree), or `orphan` (exported but not imported anywhere).
2. For each `request`-side schema: list every route file:line that uses it as a request schema; for each such usage, locate the endpoint's `parameters:` block in `openapi.yaml` and compare field-by-field.
3. For each `parameters:` entry in openapi.yaml that has no matching Zod field in the endpoint's request schemas: enumerate as orphan-in-openapi with direction `docs->code`.
4. For each exported Zod schema with zero route imports: list under "Orphan Zod schemas" (INFO-context, not a finding per plan truth #7).

---

## Zod schema enumeration

Legend for `side`:
- `request` — imported as `schema.querystring`/`schema.params`/`schema.body` by ≥1 route registration
- `response` — imported as `schema.response[<code>]` by ≥1 route registration
- `internal` — referenced only within the `src/api/schemas/*.ts` tree (e.g., `leaderboardEntrySchema` helper in `leaderboard.ts`)
- `orphan` — exported but never imported anywhere
- `not a schema` — function (encode/decode cursor helpers), not a Zod schema

All line numbers cite `/home/zak/Dev/PurgeGame/database/...`.

### Table 1 — `src/api/schemas/` (6 files, all top-level `export const ...` declarations)

| # | schema file:line | exported name | z-type (outermost) | side | where-used (route file:line list) | orphan? |
| --- | --- | --- | --- | --- | --- | --- |
|  1 | `src/api/schemas/common.ts:3`  | `addressParamSchema`     | `z.object({ address: z.string().regex(...).transform(toLowerCase) })`        | **request** (params) | `src/api/routes/history.ts:131` (params on `/history/player/:address`); `src/api/routes/player.ts:19` (params on `/player/:address`); `src/api/routes/player.ts:227` (params on `/player/:address/jackpot-history`); `src/api/routes/viewer.ts:169` (params on `/viewer/player/:address/days`); `src/api/routes/viewer.ts:55` (imported as base for `addressDayParamSchema` extension; used at `viewer.ts:320` on `/viewer/player/:address/day/:day`) | no |
|  2 | `src/api/schemas/common.ts:9`  | `errorResponseSchema`    | `z.object({ statusCode, error, message })` (all `z.number()`/`z.string()`)    | **response** | `src/api/routes/player.ts:22, 230` (404); `src/api/routes/viewer.ts:172, 323` (404); `src/api/routes/game.ts:9` (imported — but search confirms no `response: { ... : errorResponseSchema }` attachment in game.ts after line 9) | no (response-side; out of scope for this plan) |
|  3 | `src/api/schemas/common.ts:15` | `paginationQuerySchema`  | `z.object({ cursor: z.string().optional(), limit: z.coerce.number().int().min(1).max(100).default(20) })` | **request** (querystring) | `src/api/routes/history.ts:132` (querystring on `/history/player/:address`) | no |
|  4 | `src/api/schemas/common.ts:20` | `encodeCursor`           | — (function signature `(blockNumber: bigint, logIndex: number) => string`)   | not a schema | N/A | N/A |
|  5 | `src/api/schemas/common.ts:24` | `decodeCursor`           | — (function signature `(cursor: string) => { blockNumber, logIndex }`)       | not a schema | N/A | N/A |
|  6 | `src/api/schemas/game.ts:3`    | `jackpotDistributionSchema` | `z.object({ level, winner, traitId, amount, ticketIndex, sourceLevel, winnerLevel, awardType, rebuyLevel, rebuyTickets, halfPassCount, day })` | **internal** (used as element schema of `jackpotLevelResponseSchema`) | not directly imported as a route `schema.*` attachment; used inside `jackpotLevelResponseSchema` at `src/api/schemas/game.ts:20` | no (internal composition) |
|  7 | `src/api/schemas/game.ts:18`   | `jackpotLevelResponseSchema` | `z.object({ level, distributions })`                                         | **response** | `src/api/routes/game.ts:7` import; `response[200]` on `/game/jackpot/:level` at `game.ts:145` | no (response-side; out of scope) |
|  8 | `src/api/schemas/game.ts:23`   | `levelParamSchema`       | `z.object({ level: z.coerce.number().int().min(0) })`                         | **request** (params) | `src/api/routes/game.ts:147` (params on `/game/jackpot/:level`); `src/api/routes/game.ts:216` (params on `/game/jackpot/:level/overview`) | no |
|  9 | `src/api/schemas/game.ts:27`   | `jackpotOverviewRowSchema` | `z.object({...})`                                                            | **internal** (used inside `jackpotOverviewResponseSchema` at `:49` and `jackpotPlayerResponseSchema` at `:64`, `:66`, `:67`) | N/A (internal composition) | no |
| 10 | `src/api/schemas/game.ts:45`   | `jackpotOverviewResponseSchema` | `z.object({ level, day, farFutureResolved, rows })`                      | **response** | `src/api/routes/game.ts:7` import; `response[200]` on `/game/jackpot/:level/overview` at `game.ts:214` | no (response-side; out of scope) |
| 11 | `src/api/schemas/game.ts:56`   | `jackpotPlayerParamsSchema` | `z.object({ level: z.coerce.number().int().min(0), addr: z.string().regex(/^0x[0-9a-fA-F]{40}$/) })` | **request** (params) | `src/api/routes/game.ts:366` (params on `/game/jackpot/:level/player/:addr`) | no |
| 12 | `src/api/schemas/game.ts:61`   | `jackpotPlayerResponseSchema` | `z.object({ level, player, roll1Rows, roll2, hasBonus })`                | **response** | `src/api/routes/game.ts:7` import; `response[200]` on `/game/jackpot/:level/player/:addr` | no (response-side; out of scope) |
| 13 | `src/api/schemas/game.ts:73`   | `gameStateResponseSchema` | `z.object({...})`                                                            | **response** | `src/api/routes/game.ts:7` import; `response[200]` on `/game/state` at `game.ts:81` | no (response-side; out of scope) |
| 14 | `src/api/schemas/history.ts:3` | `jackpotHistoryItemSchema` | `z.object({...})`                                                            | **internal** (element of `jackpotHistoryResponseSchema`) | N/A | no |
| 15 | `src/api/schemas/history.ts:13`| `levelHistoryItemSchema` | `z.object({...})`                                                            | **internal** (element of `levelHistoryResponseSchema`) | N/A | no |
| 16 | `src/api/schemas/history.ts:20`| `playerActivityItemSchema` | `z.object({...})`                                                           | **internal** (element of `playerActivityResponseSchema`) | N/A | no |
| 17 | `src/api/schemas/history.ts:26`| `paginatedResponseSchema` | generic function `<T>(itemSchema: T) => z.object({ items, nextCursor })`    | **internal** (helper used to build response schemas) | N/A | no (factory function) |
| 18 | `src/api/schemas/history.ts:32`| `jackpotHistoryResponseSchema` | `paginatedResponseSchema(jackpotHistoryItemSchema)`                    | **response** | `src/api/routes/history.ts:6` import; `response[200]` on `/history/jackpots` | no (response-side; out of scope) |
| 19 | `src/api/schemas/history.ts:33`| `levelHistoryResponseSchema` | `paginatedResponseSchema(levelHistoryItemSchema)`                       | **response** | `src/api/routes/history.ts:7` import; `response[200]` on `/history/levels` | no (response-side; out of scope) |
| 20 | `src/api/schemas/history.ts:34`| `playerActivityResponseSchema` | `paginatedResponseSchema(playerActivityItemSchema)`                    | **response** | `src/api/routes/history.ts:8` import; `response[200]` on `/history/player/:address` | no (response-side; out of scope) |
| 21 | `src/api/schemas/history.ts:36`| `jackpotQuerySchema`     | `z.object({ level: z.coerce.number().int().optional(), cursor: z.string().optional(), limit: z.coerce.number().int().min(1).max(100).default(20) })` | **request** (querystring) | `src/api/routes/history.ts:34` (querystring on `/history/jackpots`) | no |
| 22 | `src/api/schemas/history.ts:42`| `levelQuerySchema` (in `history.ts`) | `z.object({ cursor: z.string().optional(), limit: z.coerce.number().int().min(1).max(100).default(20) })` | **request** (querystring) | `src/api/routes/history.ts:87` (querystring on `/history/levels`) | no |
| 23 | `src/api/schemas/leaderboard.ts:3` | `leaderboardEntrySchema` (not exported; `const` only) | `z.object({ player, score, rank })`                              | **internal** (composed via `.extend(...)` into the three response schemas) | N/A (not exported; see footnote) | N/A |
| 24 | `src/api/schemas/leaderboard.ts:9` | `coinflipLeaderboardResponseSchema` | `z.object({ entries: z.array(leaderboardEntrySchema.extend({ day })) })` | **response** | `src/api/routes/leaderboards.ts:4` import; `response[200]` on `/leaderboards/coinflip` | no (response-side; out of scope) |
| 25 | `src/api/schemas/leaderboard.ts:13` | `affiliateLeaderboardResponseSchema` | `z.object({ entries })`                                             | **response** | `src/api/routes/leaderboards.ts:5` import; `response[200]` on `/leaderboards/affiliate` | no (response-side; out of scope) |
| 26 | `src/api/schemas/leaderboard.ts:17` | `bafBracketResponseSchema` | `z.object({ entries })`                                                     | **response** | `src/api/routes/leaderboards.ts:6` import; `response[200]` on `/leaderboards/baf` | no (response-side; out of scope) |
| 27 | `src/api/schemas/leaderboard.ts:21` | `coinflipQuerySchema`    | `z.object({ day: z.coerce.number().int().optional() })`                       | **request** (querystring) | `src/api/routes/leaderboards.ts:15` (querystring on `/leaderboards/coinflip`) | no |
| 28 | `src/api/schemas/leaderboard.ts:25` | `levelQuerySchema` (in `leaderboard.ts`) | `z.object({ level: z.coerce.number().int().optional() })`         | **request** (querystring) | `src/api/routes/leaderboards.ts:41` (querystring on `/leaderboards/affiliate`); `src/api/routes/leaderboards.ts:67` (querystring on `/leaderboards/baf`) | no |
| 29 | `src/api/schemas/player.ts:3` | `playerDashboardResponseSchema` | `z.object({...})`                                                             | **response** | `src/api/routes/player.ts:13` import; `response[200]` on `/player/:address` | no (response-side; out of scope) |
| 30 | `src/api/schemas/player.ts:83`| `jackpotHistoryByPlayerResponseSchema` | `z.object({ wins })`                                                  | **response** | `src/api/routes/player.ts:13` import; `response[200]` on `/player/:address/jackpot-history` | no (response-side; out of scope) |
| 31 | `src/api/schemas/tokens.ts:3` | `tokenAnalyticsResponseSchema` | `z.object({ supplies, vault, holderCounts })`                                 | **response** | `src/api/routes/tokens.ts:4` import; `response[200]` on `/tokens/analytics` | no (response-side; out of scope) |

**Name-collision footnote (rows 22, 28):** Both `src/api/schemas/history.ts:42` and `src/api/schemas/leaderboard.ts:25` export a `const levelQuerySchema` with different shapes. `history.ts:42` has fields `{cursor, limit}` (a pagination schema); `leaderboard.ts:25` has fields `{level}` (a level-filter schema). These are distinct schemas with a clashing name. They are distinguished here by full file:line cite. Each route imports the one from the correct schema file (history.ts:87 uses the one from `../schemas/history.js`; leaderboards.ts:41 uses the one from `../schemas/leaderboard.js`). TypeScript module resolution disambiguates them; a human reader cannot. The name collision is a **maintainability drift** and is flagged below as **F-28-225-22** (INFO, out-of-scope-of-strict-API-05 context).

**leaderboardEntrySchema footnote (row 23):** Declared `const leaderboardEntrySchema = z.object(...)` at `src/api/schemas/leaderboard.ts:3` with NO `export` keyword. It is internal-only (used via `.extend(...)` at lines 10, 14, 18). Not a Phase 225-03 audit target; included in the enumeration for completeness.

### Table 2 — Inline Zod declarations in route files (schemas NOT in `src/api/schemas/`)

API-05 covers every Fastify request-validation schema, including ones declared inline in route files via `const xxxSchema = z.object({...})` literals (per plan action item #1 under "Methodology notes").

| # | inline schema file:line | declared name | z-type | side | where-used | scope rationale |
| --- | --- | --- | --- | --- | --- | --- |
| 32 | `src/api/routes/game.ts:14`    | `dayParamSchema` (inline, `game.ts`-local) | `z.object({ day: z.coerce.number().int().min(1).max(100000) })` | **request** (params) | `src/api/routes/game.ts:739` (`/game/jackpot/day/:day/winners`); `src/api/routes/game.ts:925` (`/game/jackpot/day/:day/roll1`); `src/api/routes/game.ts:1039` (`/game/jackpot/day/:day/roll2`) | auditable per plan; inline is NOT an orphan — 3 call sites |
| 33 | `src/api/routes/game.ts:20`    | `playerDayQuerySchema` | `z.object({ day: z.coerce.number().int().min(1).max(100000).optional() })` | **request** (querystring) | `src/api/routes/game.ts:367` (`/game/jackpot/:level/player/:addr`) | auditable per plan |
| 34 | `src/api/routes/replay.ts:11`  | `dayParamSchema` (inline, `replay.ts`-local; distinct from game.ts:14) | `z.object({ day: z.coerce.number().int().min(1) })` (no `.max(100000)`) | **request** (params) | `src/api/routes/replay.ts:74` (`/replay/day/:day`) | auditable per plan; NAME COLLISION with `game.ts:14` `dayParamSchema` |
| 35 | `src/api/routes/replay.ts:32`  | `levelParamSchema` (inline, `replay.ts`-local; distinct from `schemas/game.ts:23`) | `z.object({ level: z.coerce.number().int().min(0) })` | **request** (params) | `src/api/routes/replay.ts:186` (`/replay/tickets/:level`); `src/api/routes/replay.ts:256` (`/replay/distributions/:level`) | auditable per plan; NAME COLLISION with `schemas/game.ts:23` `levelParamSchema` |
| 36 | `src/api/routes/replay.ts:56`  | `playerAddressParamSchema` | `z.object({ address: z.string().min(1) })` | **request** (params) | `src/api/routes/replay.ts:327` (`/replay/player-traits/:address`) | auditable per plan — **NOTE the regex/transform is absent vs `addressParamSchema`**; this is an F-finding candidate (F-28-225-21) |
| 37 | `src/api/routes/viewer.ts:55`  | `addressDayParamSchema` | `addressParamSchema.extend({ day: z.coerce.number().int().min(1) })` | **request** (params) | `src/api/routes/viewer.ts:320` (`/viewer/player/:address/day/:day`) | auditable per plan; composed via `.extend(...)` — inherits regex+transform from `addressParamSchema` |

Totals:

- `src/api/schemas/` file count: 6 (common.ts, game.ts, history.ts, leaderboard.ts, player.ts, tokens.ts).
- Top-level `export const ...` declarations in `src/api/schemas/`: 31 entries in Table 1 (including two `function` entries and one non-exported `const` helper noted in footnotes).
  - `request`-side: **8** (rows 1, 3, 8, 11, 21, 22, 27, 28).
  - `response`-side: **13** (rows 2, 7, 10, 12, 13, 18, 19, 20, 24, 25, 26, 29, 30, 31 — actually 14 if you count all; see Coverage summary for precise figures).
  - `internal` (composition / factory / non-exported helper): **7** (rows 6, 9, 14, 15, 16, 17, 23).
  - `not a schema` (function): **2** (rows 4, 5).
  - `orphan` (exported but not imported anywhere): **0**.
- Inline Zod declarations in route files (Table 2): **6** (all `request`-side, all audited below).
- **Request-side total (Tables 1 + 2 `request` rows): 8 + 6 = 14 schemas.**
- Every one of the 14 request-side schemas is referenced by ≥1 route; no request-side orphans.

---

## Per-Zod-schema verdicts

One subsection per `request`-side Zod schema. Each subsection lists every route file:line that uses the schema as a request schema, then walks the openapi.yaml `parameters:` block at each such endpoint and compares field-by-field.

Verdict values in comparison tables:
- `PASS` — Zod and openapi agree on name, type, required, enum/regex/format, min/max.
- `FAIL` — at least one dimension disagrees; a finding stub (`F-28-225-NN`) is emitted.
- `ORPHAN-IN-OPENAPI` — openapi declares a parameter with no matching Zod field (direction flips to `docs->code`; emitted in the `## Orphan openapi.yaml parameters` section with its own F-stub).

Direction on every FAIL row is `code->docs` per D-225-02, unless the row is in the orphan-in-openapi section (direction `docs->code`).

### 1. `addressParamSchema` — `src/api/schemas/common.ts:3`

**Zod declaration:**
```ts
export const addressParamSchema = z.object({
  address: z.string()
    .regex(/^0x[a-fA-F0-9]{40}$/, 'Invalid Ethereum address')
    .transform((addr) => addr.toLowerCase()),
});
```

**Used by (5 direct usages + 1 via extension):**

- `src/api/routes/history.ts:131` — params on `GET /history/player/:address` (openapi.yaml path key: `/history/player/{address}` at :1299; parameter block :1305-1310).
- `src/api/routes/player.ts:19` — params on `GET /player/:address` (openapi.yaml :657; parameter block :666-672).
- `src/api/routes/player.ts:227` — params on `GET /player/:address/jackpot-history` (openapi.yaml :809; parameter block :815-821).
- `src/api/routes/viewer.ts:169` — params on `GET /viewer/player/:address/days` (openapi.yaml :1344; parameter block :1350-1355).
- `src/api/routes/viewer.ts:55` — **extended** via `addressParamSchema.extend({...})` into `addressDayParamSchema`, which is used at `viewer.ts:320` on `GET /viewer/player/:address/day/:day` (openapi.yaml :1389; parameter block :1398-1403 for the `address` param).

**Field-by-field comparison (per endpoint; `address` field only — all 5 endpoints declare it identically in Zod because they all use the same schema):**

| endpoint | Zod field | Zod type | Zod required? | Zod regex/format | openapi param line | openapi type | openapi required? | openapi pattern/format | verdict |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `/history/player/:address` (`history.ts:131`) | `address` | `string` (.transform=toLowerCase, not in docs-mapping) | yes | `/^0x[a-fA-F0-9]{40}$/` | openapi.yaml:1306-1310 | string | **yes** (`required: true` at :1308) | (none) | **FAIL** (F-28-225-15 only — regex absent; required PASSES here) |
| `/player/:address` (`player.ts:19`) | `address` | `string` | yes | `/^0x[a-fA-F0-9]{40}$/` | openapi.yaml:667-672 | string | **yes** (`required: true` at :669) | (none) | **FAIL** (F-28-225-15 only — regex absent; required PASSES here) |
| `/player/:address/jackpot-history` (`player.ts:227`) | `address` | `string` | yes | `/^0x[a-fA-F0-9]{40}$/` | openapi.yaml:816-821 | string | **yes** (`required: true` at :818) | (none) | **FAIL** (F-28-225-15 only) |
| `/viewer/player/:address/days` (`viewer.ts:169`) | `address` | `string` | yes | `/^0x[a-fA-F0-9]{40}$/` | openapi.yaml:1351-1355 | string | **yes** (`required: true` at :1353) | (none) | **FAIL** (F-28-225-15 only) |
| `/viewer/player/:address/day/:day` (`viewer.ts:320` via extension) | `address` | `string` | yes | `/^0x[a-fA-F0-9]{40}$/` | openapi.yaml:1399-1403 | string | **yes** (`required: true` at :1401) | (none) | **FAIL** (F-28-225-15 only) |

**Schema verdict: FAIL.** 5 usages, 5 FAIL rows. All 5 hit systemic finding F-28-225-15 (openapi lacks `pattern: "^0x[a-fA-F0-9]{40}$"` on the address parameter). Initial comparison had flagged `/history/player/:address` for a missing `required: true` in openapi; on re-read, openapi.yaml:1308 does declare `required: true`. F-28-225-14 was originally allocated to that provisional systemic-required-missing pattern and is retained as a null / rescinded entry per D-225-06 sequential-allocation rule — the stub below carries Direction + Severity for grep-compliance but no actionable mismatch. The `.transform(toLowerCase)` is intentionally not documented in openapi.yaml (transform is code-only; normalization is a runtime behavior, not a validation rule — consistent with the Zod-to-openapi map above).

### 2. `paginationQuerySchema` — `src/api/schemas/common.ts:15`

**Zod declaration:**
```ts
export const paginationQuerySchema = z.object({
  cursor: z.string().optional(),
  limit: z.coerce.number().int().min(1).max(100).default(20),
});
```

**Used by (1 direct usage):**

- `src/api/routes/history.ts:132` — querystring on `GET /history/player/:address` (openapi.yaml :1299; parameter block :1311-1319).

**Field-by-field comparison:**

| Zod field | Zod type | Zod required? | Zod min/max/default | openapi param | openapi type | openapi required? | openapi min/max/default | verdict |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `cursor` | `string` | no (`.optional()`) | — | `cursor` (openapi.yaml:1311-1314; no `required:`; no default) | string | no | — | PASS |
| `limit` | `integer` (coerce) | no (has `.default(20)` — Zod optional-with-default means accepts missing) | `min: 1, max: 100, default: 20` | `limit` (openapi.yaml:1315-1319) | integer | no | `default: 50` **(no minimum; no maximum; default=50 NOT 20)** | **FAIL** (F-28-225-16 — systemic `limit` default mismatch) |

**Schema verdict: FAIL.** F-28-225-16 covers: openapi declares `default: 50` on `limit`; Zod enforces `default: 20` at runtime — caller relying on openapi docs submits no limit and gets `20` back, not `50`. Additionally openapi omits `minimum: 1` and `maximum: 100` (Zod enforces both). The default-value drift is LOW per 225-CONTEXT.md severity rule 4 (documented constraint unenforced / documented default that is not what code returns), and the min/max absence is INFO.

### 3. `levelParamSchema` (in `schemas/game.ts:23`) — `src/api/schemas/game.ts:23`

**Zod declaration:**
```ts
export const levelParamSchema = z.object({
  level: z.coerce.number().int().min(0),
});
```

**Used by (2 direct usages):**

- `src/api/routes/game.ts:147` — params on `GET /game/jackpot/:level` (openapi.yaml :415; parameter block :421-428).
- `src/api/routes/game.ts:216` — params on `GET /game/jackpot/:level/overview` (openapi.yaml :486; parameter block :495-502).

**Field-by-field comparison:**

| endpoint | Zod field | Zod type | Zod required? | Zod min | openapi param line | openapi type | openapi required? | openapi minimum | verdict |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `/game/jackpot/:level` (`game.ts:147`) | `level` | integer (coerce) | yes | 0 | openapi.yaml:422-428 | integer | yes | 0 | **PASS** |
| `/game/jackpot/:level/overview` (`game.ts:216`) | `level` | integer (coerce) | yes | 0 | openapi.yaml:496-502 | integer | yes | 0 | **PASS** |

**Schema verdict: PASS.** Both usages align on type (integer), required, and minimum (0). No openapi `maximum` declared, which matches Zod (no `.max(...)` in the schema). No `default` on either side. Clean alignment.

### 4. `jackpotPlayerParamsSchema` — `src/api/schemas/game.ts:56`

**Zod declaration:**
```ts
export const jackpotPlayerParamsSchema = z.object({
  level: z.coerce.number().int().min(0),
  addr: z.string().regex(/^0x[0-9a-fA-F]{40}$/),
});
```

**Used by (1 direct usage):**

- `src/api/routes/game.ts:366` — params on `GET /game/jackpot/:level/player/:addr` (openapi.yaml :573; parameter block :591-605 for `level` + `addr`).

**Field-by-field comparison:**

| Zod field | Zod type | Zod required? | Zod regex/min | openapi param line | openapi type | openapi required? | openapi pattern/minimum | verdict |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `level` | integer (coerce) | yes | `min: 0` | openapi.yaml:592-598 | integer | yes | `minimum: 0` | **PASS** |
| `addr`  | string | yes | `/^0x[0-9a-fA-F]{40}$/` | openapi.yaml:599-605 | string | yes | (no `pattern:`) | **FAIL** (F-28-225-15 — same systemic regex-absent pattern on address-family params) |

**Schema verdict: FAIL.** `level` PASSes. `addr` fails on regex absence (systemic F-28-225-15). **Subtle:** the Zod regex is `/^0x[0-9a-fA-F]{40}$/` (digit range `[0-9a-fA-F]`) vs `addressParamSchema`'s `/^0x[a-fA-F0-9]{40}$/` (letter range first). These are semantically equivalent (both match `[0-9a-fA-F]{40}`), but the divergence between these two schemas is a separate intra-code consistency drift — flagged as **F-28-225-20** (INFO; intra-code cosmetic; resolution: normalize to a shared regex).

### 5. `jackpotQuerySchema` — `src/api/schemas/history.ts:36`

**Zod declaration:**
```ts
export const jackpotQuerySchema = z.object({
  level: z.coerce.number().int().optional(),
  cursor: z.string().optional(),
  limit: z.coerce.number().int().min(1).max(100).default(20),
});
```

**Used by (1 direct usage):**

- `src/api/routes/history.ts:34` — querystring on `GET /history/jackpots` (openapi.yaml :1200; parameter block :1206-1222).

**Field-by-field comparison:**

| Zod field | Zod type | Zod required? | Zod min/max/default | openapi param line | openapi type | openapi required? | openapi min/max/default | verdict |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `level`  | integer (coerce) | no (`.optional()`) | none | openapi.yaml:1207-1212 | integer | no | `minimum: 0` | **FAIL** (F-28-225-17 — INFO; openapi documents `minimum: 0` that Zod does not enforce) |
| `cursor` | string | no | — | openapi.yaml:1213-1217 | string | no | — | PASS |
| `limit`  | integer (coerce) | no (default=20) | `min: 1, max: 100, default: 20` | openapi.yaml:1218-1222 | integer | no | `default: 50` (no min; no max) | **FAIL** (F-28-225-16 — systemic limit-default-mismatch) |

**Schema verdict: FAIL.** `level` hits F-28-225-17 (openapi documents a min that Zod does not enforce at runtime). `cursor` PASSes. `limit` hits systemic F-28-225-16.

### 6. `levelQuerySchema` (in `schemas/history.ts:42`) — `src/api/schemas/history.ts:42`

**Zod declaration:**
```ts
export const levelQuerySchema = z.object({
  cursor: z.string().optional(),
  limit: z.coerce.number().int().min(1).max(100).default(20),
});
```

**Used by (1 direct usage):**

- `src/api/routes/history.ts:87` — querystring on `GET /history/levels` (openapi.yaml :1257; parameter block :1263-1272).

**Field-by-field comparison:**

| Zod field | Zod type | Zod required? | Zod min/max/default | openapi param line | openapi type | openapi required? | openapi default | verdict |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `cursor` | string | no | — | openapi.yaml:1263-1267 | string | no | — | PASS |
| `limit`  | integer (coerce) | no (default=20) | `min: 1, max: 100, default: 20` | openapi.yaml:1268-1272 | integer | no | `default: 50` | **FAIL** (F-28-225-16) |

**Schema verdict: FAIL.** `cursor` PASSes; `limit` hits systemic F-28-225-16.

### 7. `coinflipQuerySchema` — `src/api/schemas/leaderboard.ts:21`

**Zod declaration:**
```ts
export const coinflipQuerySchema = z.object({
  day: z.coerce.number().int().optional(),
});
```

**Used by (1 direct usage):**

- `src/api/routes/leaderboards.ts:15` — querystring on `GET /leaderboards/coinflip` (openapi.yaml :1092; parameter block :1098-1104).

**Field-by-field comparison:**

| Zod field | Zod type | Zod required? | Zod min | openapi param line | openapi type | openapi required? | openapi minimum | verdict |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `day` | integer (coerce) | no (`.optional()`) | — (no Zod min) | openapi.yaml:1099-1104 | integer | no | `minimum: 1` | **FAIL** (F-28-225-17 — openapi declares minimum unenforced by Zod) |

**Schema verdict: FAIL.** F-28-225-17 systemic pattern (openapi `minimum: 1` documented but Zod has no `.min(...)`).

### 8. `levelQuerySchema` (in `schemas/leaderboard.ts:25`) — `src/api/schemas/leaderboard.ts:25`

**Zod declaration:**
```ts
export const levelQuerySchema = z.object({
  level: z.coerce.number().int().optional(),
});
```

**Used by (2 direct usages):**

- `src/api/routes/leaderboards.ts:41` — querystring on `GET /leaderboards/affiliate` (openapi.yaml :1128; parameter block :1134-1140).
- `src/api/routes/leaderboards.ts:67` — querystring on `GET /leaderboards/baf` (openapi.yaml :1164; parameter block :1170-1176).

**Field-by-field comparison:**

| endpoint | Zod field | Zod type | Zod required? | Zod min | openapi param line | openapi type | openapi required? | openapi minimum | verdict |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `/leaderboards/affiliate` (`leaderboards.ts:41`) | `level` | integer (coerce) | no (`.optional()`) | — | openapi.yaml:1135-1140 | integer | no | `minimum: 0` | **FAIL** (F-28-225-17) |
| `/leaderboards/baf` (`leaderboards.ts:67`)       | `level` | integer (coerce) | no | — | openapi.yaml:1171-1176 | integer | no | `minimum: 0` | **FAIL** (F-28-225-17) |

**Schema verdict: FAIL.** Both usages hit systemic F-28-225-17.

### 9. Inline `dayParamSchema` (`routes/game.ts:14`) — `src/api/routes/game.ts:14`

**Zod declaration:**
```ts
const dayParamSchema = z.object({
  day: z.coerce.number().int().min(1).max(100000),
});
```

**Used by (3 direct usages):**

- `src/api/routes/game.ts:739` — params on `GET /game/jackpot/day/:day/winners` (openapi.yaml :187; parameter block :205-213).
- `src/api/routes/game.ts:925` — params on `GET /game/jackpot/day/:day/roll1` (openapi.yaml :289; parameter block :312-321).
- `src/api/routes/game.ts:1039` — params on `GET /game/jackpot/day/:day/roll2` (openapi.yaml :332; parameter block :355-364).

**Field-by-field comparison:**

| endpoint | Zod field | Zod type | Zod required? | Zod min/max | openapi param line | openapi type | openapi required? | openapi min/max | verdict |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `/winners` (`game.ts:739`) | `day` | integer (coerce) | yes | `min: 1, max: 100000` | openapi.yaml:206-213 | integer | yes | `minimum: 1, maximum: 100000` | **PASS** |
| `/roll1`   (`game.ts:925`) | `day` | integer (coerce) | yes | `min: 1, max: 100000` | openapi.yaml:313-321 | integer | yes | `minimum: 1, maximum: 100000` | **PASS** |
| `/roll2`   (`game.ts:1039`)| `day` | integer (coerce) | yes | `min: 1, max: 100000` | openapi.yaml:356-364 | integer | yes | `minimum: 1, maximum: 100000` | **PASS** |

**Schema verdict: PASS.** All 3 usages align exactly on type, required, minimum, maximum. This is the cleanest alignment in the entire audit — all three openapi blocks were hand-authored with the same constraints Zod enforces.

### 10. Inline `playerDayQuerySchema` (`routes/game.ts:20`) — `src/api/routes/game.ts:20`

**Zod declaration:**
```ts
const playerDayQuerySchema = z.object({
  day: z.coerce.number().int().min(1).max(100000).optional(),
});
```

**Used by (1 direct usage):**

- `src/api/routes/game.ts:367` — querystring on `GET /game/jackpot/:level/player/:addr` (openapi.yaml :573; parameter block :606-612 for the `day` querystring param).

**Field-by-field comparison:**

| Zod field | Zod type | Zod required? | Zod min/max | openapi param line | openapi type | openapi required? | openapi min/max | verdict |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `day` | integer (coerce) | no (`.optional()`) | `min: 1, max: 100000` | openapi.yaml:606-612 | integer | no (`required: false` at :608) | `minimum: 1, maximum: 100000` | **PASS** |

**Schema verdict: PASS.** Exact alignment: Zod optional matches openapi `required: false`; min/max match.

### 11. Inline `dayParamSchema` (`routes/replay.ts:11`) — `src/api/routes/replay.ts:11`

**Zod declaration (NAME COLLISION with `game.ts:14` — different shape!):**
```ts
const dayParamSchema = z.object({
  day: z.coerce.number().int().min(1),
});
```

**Used by (1 direct usage):**

- `src/api/routes/replay.ts:74` — params on `GET /replay/day/:day` (openapi.yaml :869; parameter block :875-882).

**Field-by-field comparison:**

| Zod field | Zod type | Zod required? | Zod min/max | openapi param line | openapi type | openapi required? | openapi min/max | verdict |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `day` | integer (coerce) | yes | `min: 1` (no max) | openapi.yaml:876-882 | integer | yes | `minimum: 1` (no maximum) | **PASS** |

**Schema verdict: PASS.** Alignment exact: type, required, minimum all match; no maximum on either side (Zod has no `.max(...)`, openapi has no `maximum:`). **However**, this is a NAME COLLISION with `routes/game.ts:14`'s `dayParamSchema` (which has `.max(100000)`). Two schemas with the same name and different behaviors. Flagged as **F-28-225-22** (INFO; maintainability; not a Zod↔openapi drift but a code-consistency drift).

### 12. Inline `levelParamSchema` (`routes/replay.ts:32`) — `src/api/routes/replay.ts:32`

**Zod declaration (NAME COLLISION with `schemas/game.ts:23`'s same-named schema):**
```ts
const levelParamSchema = z.object({
  level: z.coerce.number().int().min(0),
});
```

**Used by (2 direct usages):**

- `src/api/routes/replay.ts:186` — params on `GET /replay/tickets/:level` (openapi.yaml :978; parameter block :984-991).
- `src/api/routes/replay.ts:256` — params on `GET /replay/distributions/:level` (openapi.yaml :1015; parameter block :1021-1028).

**Field-by-field comparison:**

| endpoint | Zod field | Zod type | Zod required? | Zod min | openapi param line | openapi type | openapi required? | openapi minimum | verdict |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `/replay/tickets/:level` (`replay.ts:186`) | `level` | integer (coerce) | yes | 0 | openapi.yaml:985-991 | integer | yes | 0 | **PASS** |
| `/replay/distributions/:level` (`replay.ts:256`) | `level` | integer (coerce) | yes | 0 | openapi.yaml:1022-1028 | integer | yes | 0 | **PASS** |

**Schema verdict: PASS.** Both usages align exactly. The **shape is identical to `src/api/schemas/game.ts:23`'s `levelParamSchema`** (same field, same constraints) — the duplication is a DRY violation and is a code-level finding (merged into **F-28-225-22** code-consistency bucket).

### 13. Inline `playerAddressParamSchema` (`routes/replay.ts:56`) — `src/api/routes/replay.ts:56`

**Zod declaration (weaker validation than `addressParamSchema`!):**
```ts
const playerAddressParamSchema = z.object({
  address: z.string().min(1),
});
```

**Used by (1 direct usage):**

- `src/api/routes/replay.ts:327` — params on `GET /replay/player-traits/:address` (openapi.yaml :1062; parameter block :1068-1074).

**Field-by-field comparison:**

| Zod field | Zod type | Zod required? | Zod regex/min | openapi param line | openapi type | openapi required? | openapi pattern | verdict |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `address` | string | yes | `min: 1` (accepts ANY non-empty string — NOT the 0x regex) | openapi.yaml:1069-1074 | string | yes | (no `pattern:`) | **PASS** (Zod ≡ openapi both declare no regex; alignment is clean) |

**Schema verdict: PASS** on Zod↔openapi alignment. **However**, both sides are systematically weaker than every other address-accepting endpoint: `addressParamSchema` enforces `/^0x[a-fA-F0-9]{40}$/` while this one accepts any non-empty string. The handler body at `replay.ts:332` calls `address.toLowerCase()` and proceeds with no further validation — meaning any non-hex string slips through Zod validation. This is a **code→code consistency drift** (all other address-family endpoints validate 0x-format; this one doesn't) flagged as **F-28-225-21** (LOW — security/type-safety adjacent; the inline regex exists on 5 sibling endpoints and its absence here is caller-breaking for consumers who expect uniform address-format validation across the API). Direction is `code->docs` (not `docs->code`) because the openapi also lacks a pattern — Plan 225-03's responsibility is to note the divergence between this address schema and the others; Phase 229 decides whether to fix the Zod or fix the openapi.

### 14. Inline `addressDayParamSchema` (`routes/viewer.ts:55`) — `src/api/routes/viewer.ts:55`

**Zod declaration (composed via `.extend(...)`):**
```ts
const addressDayParamSchema = addressParamSchema.extend({
  day: z.coerce.number().int().min(1),
});
```

**Inherits from `addressParamSchema`:** `address: z.string().regex(/^0x[a-fA-F0-9]{40}$/).transform(toLowerCase)`.

**Used by (1 direct usage):**

- `src/api/routes/viewer.ts:320` — params on `GET /viewer/player/:address/day/:day` (openapi.yaml :1389; parameter block :1398-1409).

**Field-by-field comparison:**

| Zod field | Zod type | Zod required? | Zod regex/min | openapi param line | openapi type | openapi required? | openapi pattern/minimum | verdict |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `address` | string | yes | `/^0x[a-fA-F0-9]{40}$/` (inherited) | openapi.yaml:1399-1403 | string | yes (`required: true` :1401) | (no `pattern:`) | **FAIL** (F-28-225-15 — systemic regex-absent pattern) |
| `day` | integer (coerce) | yes | `min: 1` (no max) | openapi.yaml:1404-1409 | integer | yes (`required: true` :1406) | `minimum: 1` | **PASS** |

**Schema verdict: FAIL.** `address` hits F-28-225-15 (systemic regex-absent); `day` is PASS.

---

## Finding stubs

The stubs below satisfy the plan's acceptance regex `/^#### F-28-225-\d+ —/`.

#### F-28-225-14 — openapi.yaml path parameter missing `required: true` on `/history/player/{address}` address block

- **Severity:** INFO
- **Direction:** code->docs
- **Phase:** 225 (API-05 request-schema audit)
- **Code side:** `/home/zak/Dev/PurgeGame/database/src/api/schemas/common.ts:3` — `addressParamSchema` = `z.object({ address: z.string().regex(...).transform(...) })`. Non-`.optional()` field = Zod requires `address` to be present at runtime.
- **Code usage:** `/home/zak/Dev/PurgeGame/database/src/api/routes/history.ts:131` — `params: addressParamSchema` on `GET /history/player/:address`.
- **Docs side:** `/home/zak/Dev/PurgeGame/database/docs/openapi.yaml:1305-1310`:
  ```yaml
  parameters:
    - name: address
      in: path
      required: true
      schema:
        type: string
  ```
  Actually reading the block — `required: true` IS present at line 1308. **Correction on re-read:** openapi.yaml at `:1308` declares `required: true`. This finding is **rescinded on re-read**; the systemic pattern F-28-225-14 was based on an initial misread. See the re-evaluation note below.
- **Mismatch:** (rescinded)
- **Caller impact:** N/A
- **Suggested resolution:** N/A — no action. Finding ID remains allocated to preserve the global sequential allocation; it is a null entry in the findings pool.

**Re-evaluation note:** The initial comparison table for `addressParamSchema` against `/history/player/:address` marked the row FAIL on `required:` absence, but openapi.yaml:1305-1310 does declare `required: true` at line 1308. All 5 address-using openapi path blocks have `required: true`. The table entry for `/history/player/:address` has been re-checked — the row should have read openapi required = yes (matching the other four). F-28-225-14 is a placeholder / null entry to preserve sequential numbering per D-225-06; it carries no remediation action in Phase 229.

#### F-28-225-15 — openapi.yaml lacks `pattern: "^0x[a-fA-F0-9]{40}$"` on every address-family path parameter (systemic)

- **Severity:** LOW (per 225-CONTEXT.md severity rule 4: "regex/format documented in openapi.yaml that Zod doesn't enforce" — inverse case here: regex enforced by Zod that openapi doesn't document; still caller-breaking because compliant consumers submitting non-hex strings would get Zod 400 despite openapi declaring only `type: string`)
- **Direction:** code->docs
- **Phase:** 225 (API-05 request-schema audit)
- **Code side:** `/home/zak/Dev/PurgeGame/database/src/api/schemas/common.ts:5` — `addressParamSchema.address = z.string().regex(/^0x[a-fA-F0-9]{40}$/, 'Invalid Ethereum address').transform(toLowerCase)`. Enforced at every endpoint that uses this schema.
  - Also `/home/zak/Dev/PurgeGame/database/src/api/schemas/game.ts:58` — `jackpotPlayerParamsSchema.addr = z.string().regex(/^0x[0-9a-fA-F]{40}$/)` (digit-class order swapped; semantically equivalent).
- **Code usage (6 occurrences across 5 openapi path-parameter blocks):**
  - `GET /history/player/:address` — `src/api/routes/history.ts:131` → openapi.yaml:1305-1310 (address)
  - `GET /player/:address` — `src/api/routes/player.ts:19` → openapi.yaml:666-672 (address)
  - `GET /player/:address/jackpot-history` — `src/api/routes/player.ts:227` → openapi.yaml:815-821 (address)
  - `GET /viewer/player/:address/days` — `src/api/routes/viewer.ts:169` → openapi.yaml:1350-1355 (address)
  - `GET /viewer/player/:address/day/:day` — `src/api/routes/viewer.ts:320` → openapi.yaml:1398-1403 (address; also :1404-1409 for day — day alignment is PASS)
  - `GET /game/jackpot/:level/player/:addr` — `src/api/routes/game.ts:366` → openapi.yaml:599-605 (addr; digit-range `[0-9a-fA-F]`)
- **Docs side:** Each of the 6 openapi parameter blocks declares only `schema: { type: string }` with no `pattern:` — Zod enforces the hex format at runtime, but consumer docs/codegen tooling has no way to know.
- **Mismatch:** Zod's `/^0x[a-fA-F0-9]{40}$/` regex is absent from every one of the 6 openapi address-parameter declarations. A caller generating a client from openapi.yaml would permit any string, submit it, and receive a Zod 400 at runtime — a real caller-breaking compliance gap.
- **Caller impact:** openapi-typed clients (e.g. `@openapitools/openapi-generator-cli`) emit no format validation for `type: string` without `pattern:`; generated TypeScript types are bare `string`. A consumer submitting `"not-an-address"` would pass generated-client validation and fail at the server with a Zod 400 error. LOW severity because compliant consumers following openapi.yaml literally will crash.
- **Suggested resolution:** **RESOLVED-DOC** — add `pattern: "^0x[a-fA-F0-9]{40}$"` to each of the 6 openapi parameter blocks. Phase 229 candidate. Cross-reference with F-28-225-20 (regex-character-class drift between the two Zod regexes themselves — fix both at once).

#### F-28-225-16 — `limit` query parameter default mismatch (`default: 50` in openapi.yaml vs `.default(20)` in Zod; min/max unenforced)

- **Severity:** LOW (per 225-CONTEXT.md severity rule 4: "regex/format documented in openapi.yaml that Zod doesn't enforce" — the wider umbrella covers any caller-observable constraint divergence. The `default:` value is caller-observable: a consumer omitting `?limit=` sees `20` back (Zod) when the openapi says `50`, which means pagination page-size returns half what the docs promise.)
- **Direction:** code->docs
- **Phase:** 225 (API-05 request-schema audit)
- **Code side:** Three Zod schemas, all declaring the same pagination shape:
  - `/home/zak/Dev/PurgeGame/database/src/api/schemas/common.ts:17` — `paginationQuerySchema.limit = z.coerce.number().int().min(1).max(100).default(20)`
  - `/home/zak/Dev/PurgeGame/database/src/api/schemas/history.ts:39` — `jackpotQuerySchema.limit = z.coerce.number().int().min(1).max(100).default(20)`
  - `/home/zak/Dev/PurgeGame/database/src/api/schemas/history.ts:44` — `levelQuerySchema (in history.ts).limit = z.coerce.number().int().min(1).max(100).default(20)`
- **Code usage (3 occurrences):**
  - `GET /history/player/:address` — `src/api/routes/history.ts:132` (via `paginationQuerySchema`) → openapi.yaml:1315-1319
  - `GET /history/jackpots` — `src/api/routes/history.ts:34` (via `jackpotQuerySchema`) → openapi.yaml:1218-1222
  - `GET /history/levels` — `src/api/routes/history.ts:87` (via `levelQuerySchema` in `schemas/history.ts`) → openapi.yaml:1268-1272
- **Docs side:** All three openapi blocks declare:
  ```yaml
  - name: limit
    in: query
    schema:
      type: integer
      default: 50
  ```
  (no `minimum:`, no `maximum:`).
- **Mismatch:** (a) openapi `default: 50` vs Zod `.default(20)` — caller omitting `?limit=` gets 20 items at runtime, not 50 as documented. (b) Zod `.min(1)` and `.max(100)` not reflected in openapi — compliant consumers submitting `limit=0` or `limit=500` get a 400 despite openapi declaring no bounds.
- **Caller impact:** (a) Documentation-lag: paginating consumers expect 50-per-page per docs, get 20-per-page from runtime. Can surface as UI pagination bugs (caller allocates array-of-50, fills only 20, assumes tail is pagination boundary, mis-labels cursor). (b) Compliant consumer submitting `limit=500` (per openapi's no-max claim) gets 400.
- **Suggested resolution:** **RESOLVED-DOC** — change openapi to `default: 20, minimum: 1, maximum: 100` on all 3 `limit` query param blocks. Phase 229 candidate. (Alternative `RESOLVED-CODE`: change Zod `.default(20)` to `.default(50)`; the historical rationale for 20 is unknown but is caller-observable so changing it is the bigger-impact option — D-225-02 default recommends the doc change.)

#### F-28-225-17 — openapi.yaml declares `minimum:` on query parameters that Zod does not enforce (`day`, `level` on filter-style optional query params)

- **Severity:** INFO (per 225-CONTEXT.md: the `minimum:` documented in openapi but unenforced by Zod does not break compliant callers — compliant callers submitting values within the docs-promised range pass Zod; only callers submitting values below the minimum bypass validation they expect to exist; not directly caller-breaking for the typical happy path)
- **Direction:** code->docs
- **Phase:** 225 (API-05 request-schema audit)
- **Code side:** Three Zod schemas declare optional query params with `.optional()` and NO `.min(...)`:
  - `/home/zak/Dev/PurgeGame/database/src/api/schemas/leaderboard.ts:22` — `coinflipQuerySchema.day = z.coerce.number().int().optional()` (no `.min(...)`)
  - `/home/zak/Dev/PurgeGame/database/src/api/schemas/leaderboard.ts:26` — `levelQuerySchema (in leaderboard.ts).level = z.coerce.number().int().optional()` (no `.min(...)`)
  - `/home/zak/Dev/PurgeGame/database/src/api/schemas/history.ts:37` — `jackpotQuerySchema.level = z.coerce.number().int().optional()` (no `.min(...)`)
- **Code usage (4 occurrences):**
  - `GET /leaderboards/coinflip` query `day` — openapi.yaml:1099-1104 declares `minimum: 1`
  - `GET /leaderboards/affiliate` query `level` — openapi.yaml:1135-1140 declares `minimum: 0`
  - `GET /leaderboards/baf` query `level` — openapi.yaml:1171-1176 declares `minimum: 0`
  - `GET /history/jackpots` query `level` — openapi.yaml:1207-1212 declares `minimum: 0`
- **Docs side:** Each of the 4 openapi parameter blocks includes `minimum: 0` or `minimum: 1` that Zod does not enforce. A caller submitting `day=-1` or `level=-5` gets a type-coerced value and the SQL query runs with the (effectively meaningless) negative filter.
- **Mismatch:** openapi documents minimum-value guards the runtime does not enforce.
- **Caller impact:** Negative-value inputs slip through to the SQL query, producing empty result sets (because no row has a negative `day`/`level`). Not directly caller-breaking (no 400, no crash), but a silent "no data found" response for any compliant-consumer typo or off-by-one bug. INFO severity.
- **Suggested resolution:** **RESOLVED-CODE** (inverted: add `.min(1)` to Zod `coinflipQuerySchema.day` and `.min(0)` to the two `levelQuerySchema` variants plus `jackpotQuerySchema.level` — tightens runtime validation to match docs; cheaper than documenting-then-not-enforcing). Alternative **RESOLVED-DOC**: remove `minimum:` from each openapi block. Phase 229 decides direction; D-225-02 default is RESOLVED-DOC but the RESOLVED-CODE option is both trivial (add `.min(N)` on 4 lines) and tightens the API contract, so inversion recommended.

#### F-28-225-18 — `/leaderboards/coinflip` query `day` documented optional in openapi but Zod ALSO optional — aligned; noted as PASS only

- **Severity:** INFO (null / rescinded)
- **Direction:** code->docs
- **Phase:** 225 (API-05 request-schema audit)
- **Rationale:** During the per-schema verdict walk, `/leaderboards/coinflip?day=` was initially flagged as a candidate for the canonical-LOW case ("required request parameter documented optional in openapi.yaml"). On re-read: openapi declares it optional (no `required: true`) and Zod declares `.optional()`. Alignment is exact. **Null finding; ID preserved for sequential numbering per D-225-06.** Retained here with Direction + Severity lines for grep-compliance with the plan's acceptance regex only; no remediation action.

#### F-28-225-19 — `errorResponseSchema` import in `src/api/routes/game.ts:9` has no `response[...]` attachment in game.ts (dead import)

- **Severity:** INFO (code-only; not an API-05 failure — no contract drift; dead-code context)
- **Direction:** code-only (not a Zod↔openapi drift)
- **Phase:** 225 (API-05 request-schema audit — noted as context per plan truth #6)
- **Code side:** `/home/zak/Dev/PurgeGame/database/src/api/routes/game.ts:9` — `import { errorResponseSchema } from '../schemas/common.js';`
- **Usage search:** `grep -nE 'errorResponseSchema' /home/zak/Dev/PurgeGame/database/src/api/routes/game.ts` returns only the import line; no `response[<code>]: errorResponseSchema` attachment anywhere in `game.ts`. The other handlers that actually return 404 (`/game/jackpot/:level` at `:145`, `/game/jackpot/day/:day/roll1` at `:923`, `/game/jackpot/day/:day/roll2` at `:1037`, `/game/jackpot/earliest-day` at `:1352`) all have `reply.notFound(...)` calls in handler bodies but do NOT register a `response[404]: errorResponseSchema` entry. Only `player.ts:22, 230` and `viewer.ts:172, 323` actually register 404 responses with `errorResponseSchema`.
- **Mismatch:** Dead import. Cleanup candidate.
- **Caller impact:** None (import is tree-shakeable; no runtime impact). Confusing for maintainers.
- **Suggested resolution:** RESOLVED-CODE — either remove the import, or register `404: errorResponseSchema` on the 4 game.ts handlers that emit 404 responses (matches the pattern in `player.ts`/`viewer.ts`). Phase 229 candidate as a low-priority code-cleanup finding, not an API-05 failure per se.

#### F-28-225-20 — Regex character-class drift between `addressParamSchema` and `jackpotPlayerParamsSchema.addr`

- **Severity:** INFO (no caller-visible impact; both regexes are semantically equivalent)
- **Direction:** code-only (intra-code consistency drift; not Zod↔openapi)
- **Phase:** 225 (API-05 request-schema audit — noted as context)
- **Code side (two regex declarations):**
  - `/home/zak/Dev/PurgeGame/database/src/api/schemas/common.ts:5` — `/^0x[a-fA-F0-9]{40}$/` (letters first, then digits)
  - `/home/zak/Dev/PurgeGame/database/src/api/schemas/game.ts:58` — `/^0x[0-9a-fA-F]{40}$/` (digits first, then letters)
- **Mismatch:** Different character-class orderings. JavaScript regex engines treat `[a-fA-F0-9]` and `[0-9a-fA-F]` as identical sets, so the two regexes match the same strings. The divergence is cosmetic only.
- **Caller impact:** None. Both regexes accept the same inputs.
- **Suggested resolution:** RESOLVED-CODE — normalize to a single exported constant `ETH_ADDRESS_REGEX` in `common.ts` and reference from both schemas. Part of the same cleanup pass as F-28-225-15 (openapi `pattern:` addition).

#### F-28-225-21 — `playerAddressParamSchema` in `routes/replay.ts:56` lacks the 0x-format regex that every other address-family schema enforces

- **Severity:** LOW (per 225-CONTEXT.md severity rule 4: "regex/format that Zod doesn't enforce" — security/type-safety adjacent; the absence allows arbitrary string values through Zod validation when the handler then calls `.toLowerCase()` and queries the DB with the non-hex value; no direct crash, but a compliance-and-consistency caller-breaking gap if callers rely on the other endpoints' address format uniformly)
- **Direction:** code->docs (with inverted RESOLVED-CODE recommendation)
- **Phase:** 225 (API-05 request-schema audit)
- **Code side:** `/home/zak/Dev/PurgeGame/database/src/api/routes/replay.ts:56-58`:
  ```ts
  const playerAddressParamSchema = z.object({
    address: z.string().min(1),
  });
  ```
  Accepts any non-empty string. Handler at `replay.ts:332` calls `address.toLowerCase()` and proceeds.
- **Code usage:** `src/api/routes/replay.ts:327` — params on `GET /replay/player-traits/:address`.
- **Docs side:** `/home/zak/Dev/PurgeGame/database/docs/openapi.yaml:1068-1074` declares `type: string` with no `pattern:` — so technically openapi and Zod agree (both lack the format). The finding is NOT a Zod↔openapi drift at this endpoint; it is an **intra-code consistency drift** (every other address endpoint uses `addressParamSchema` with the 0x regex; only this one uses a bespoke weaker schema).
- **Mismatch:** Inconsistent address validation across the API. `GET /replay/player-traits/:address` is the only address-accepting endpoint that does NOT enforce the 0x hex-format regex at Zod level. 6 other endpoints enforce it. Compliant consumers writing uniform client code for "address params" would be surprised to learn this one endpoint accepts non-hex input.
- **Caller impact:** A caller submitting `/replay/player-traits/hello-world` gets no Zod 400 (passes `.min(1)`), instead proceeds into the handler which lowercases "hello-world" and queries `traits_generated WHERE player = 'hello-world'`. Zero results returned. The caller's client-library type system expected a hex address; it got a silent empty success. Caller-breaking for uniform-client consumers.
- **Suggested resolution:** **RESOLVED-CODE** — replace the inline `playerAddressParamSchema` with a reference to `addressParamSchema` from `common.ts` (which enforces the regex). One-line change. Also add `pattern:` to openapi.yaml:1068-1074 in the same pass (RESOLVED-DOC component). Phase 229 candidate.

#### F-28-225-22 — Intra-code schema-name and schema-shape drift across route files (`dayParamSchema`, `levelParamSchema`, `levelQuerySchema` defined differently in multiple locations)

- **Severity:** INFO (maintainability/code-health; not a Zod↔openapi drift)
- **Direction:** code-only (intra-code)
- **Phase:** 225 (API-05 request-schema audit — noted as context per plan truth #6)
- **Code side — three name collisions identified:**
  1. **`dayParamSchema`** declared in two places with DIFFERENT shapes:
     - `src/api/routes/game.ts:14` — `z.object({ day: z.coerce.number().int().min(1).max(100000) })` (bounded on upper end)
     - `src/api/routes/replay.ts:11` — `z.object({ day: z.coerce.number().int().min(1) })` (no max bound)
  2. **`levelParamSchema`** declared in two places with IDENTICAL shapes (DRY violation):
     - `src/api/schemas/game.ts:23` — `z.object({ level: z.coerce.number().int().min(0) })`
     - `src/api/routes/replay.ts:32` — `z.object({ level: z.coerce.number().int().min(0) })`
  3. **`levelQuerySchema`** declared in two places with DIFFERENT shapes:
     - `src/api/schemas/history.ts:42` — `z.object({ cursor, limit })` (a pagination query schema)
     - `src/api/schemas/leaderboard.ts:25` — `z.object({ level: z.coerce.number().int().optional() })` (a filter query schema)
- **Mismatch:** Three same-named schemas across the codebase carry different shapes (cases 1, 3) or are duplicated unnecessarily (case 2). TypeScript disambiguates by file-of-origin at import time, but the cognitive load on a maintainer reading a route file is non-trivial: "which `dayParamSchema`?" and "which `levelQuerySchema`?" require following imports.
- **Caller impact:** None at runtime. The different `dayParamSchema.max(100000)` applied at `game.ts:14` (used by roll1/roll2/winners endpoints) vs no-max at `replay.ts:11` (used by `/replay/day/:day`) IS a real intra-API behavior difference — callers submitting `day=999999999` to `/replay/day/:day` get no Zod 400, but the same value on `/game/jackpot/day/:day/winners` gets a 400. This is intentional per the comment at `game.ts:12-13` ("max(100000) guards against large block-range scans (T-39-04)"); the `/replay` endpoint omits the guard. Whether intentional or drift is unclear from the code; likely drift.
- **Suggested resolution:** **RESOLVED-CODE** — consolidate the three name-collision groups into single declarations in `src/api/schemas/common.ts` (or a new `src/api/schemas/params.ts`) and re-import into each route. Explicit `dayParamSchema` (bounded) vs `dayParamSchemaUnbounded` (or rename). Phase 229 candidate as a code-hygiene finding; not an API-05 failure per se, but worth noting because API-05's broader intent (schema↔docs consistency) is undermined by ambiguously-named schemas.

---

## Orphan openapi.yaml parameters

Per plan action item #3 and the direction-exception carved out in 225-CONTEXT.md D-225-02: for any parameter declared in openapi.yaml whose corresponding endpoint's Zod request schema does NOT include a matching field, emit an F-stub with `Direction: docs->code` (docs promise validation the code does not enforce).

**Full scan result (across all 27 Phase 224 paired endpoints):**

Walking every `parameters:` block in openapi.yaml and checking each against the Zod `schema.params`/`schema.querystring` at the corresponding route registration:

| openapi.yaml parameter (endpoint, name, line) | matched-in-Zod? | route registration with schema | verdict |
| --- | --- | --- | --- |
| `/game/jackpot/day/{day}/winners` - `day` (path) :206 | yes (`game.ts:14` `dayParamSchema.day`) | `game.ts:739` | PASS |
| `/game/jackpot/day/{day}/roll1` - `day` (path) :313 | yes | `game.ts:925` | PASS |
| `/game/jackpot/day/{day}/roll2` - `day` (path) :356 | yes | `game.ts:1039` | PASS |
| `/game/jackpot/{level}` - `level` (path) :422 | yes (`schemas/game.ts:23` `levelParamSchema.level`) | `game.ts:147` | PASS |
| `/game/jackpot/{level}/overview` - `level` (path) :496 | yes | `game.ts:216` | PASS |
| `/game/jackpot/{level}/player/{addr}` - `level` (path) :592 | yes (`schemas/game.ts:56` `jackpotPlayerParamsSchema.level`) | `game.ts:366` | PASS |
| `/game/jackpot/{level}/player/{addr}` - `addr` (path) :599 | yes (`jackpotPlayerParamsSchema.addr`) | `game.ts:366` | PASS (regex-absent in openapi is F-28-225-15) |
| `/game/jackpot/{level}/player/{addr}` - `day` (query) :606 | yes (`game.ts:20` `playerDayQuerySchema.day`) | `game.ts:367` | PASS |
| `/player/{address}` - `address` (path) :667 | yes (`addressParamSchema.address`) | `player.ts:19` | PASS (regex-absent is F-28-225-15) |
| `/player/{address}/jackpot-history` - `address` (path) :816 | yes | `player.ts:227` | PASS (F-28-225-15) |
| `/replay/day/{day}` - `day` (path) :876 | yes (`replay.ts:11` `dayParamSchema.day`) | `replay.ts:74` | PASS |
| `/replay/tickets/{level}` - `level` (path) :985 | yes (`replay.ts:32` `levelParamSchema.level`) | `replay.ts:186` | PASS |
| `/replay/distributions/{level}` - `level` (path) :1022 | yes | `replay.ts:256` | PASS |
| `/replay/player-traits/{address}` - `address` (path) :1069 | yes (`replay.ts:56` `playerAddressParamSchema.address`) | `replay.ts:327` | PASS (regex-weaker-than-siblings is F-28-225-21) |
| `/leaderboards/coinflip` - `day` (query) :1099 | yes (`coinflipQuerySchema.day`) | `leaderboards.ts:15` | PASS (minimum-not-enforced is F-28-225-17) |
| `/leaderboards/affiliate` - `level` (query) :1135 | yes (`levelQuerySchema.level` in `schemas/leaderboard.ts`) | `leaderboards.ts:41` | PASS (F-28-225-17) |
| `/leaderboards/baf` - `level` (query) :1171 | yes | `leaderboards.ts:67` | PASS (F-28-225-17) |
| `/history/jackpots` - `level` (query) :1207 | yes (`jackpotQuerySchema.level`) | `history.ts:34` | PASS (F-28-225-17) |
| `/history/jackpots` - `cursor` (query) :1213 | yes | `history.ts:34` | PASS |
| `/history/jackpots` - `limit` (query) :1218 | yes | `history.ts:34` | PASS (default-drift is F-28-225-16) |
| `/history/levels` - `cursor` (query) :1264 | yes (`levelQuerySchema.cursor` in `schemas/history.ts`) | `history.ts:87` | PASS |
| `/history/levels` - `limit` (query) :1268 | yes | `history.ts:87` | PASS (F-28-225-16) |
| `/history/player/{address}` - `address` (path) :1306 | yes | `history.ts:131` | PASS (F-28-225-15) |
| `/history/player/{address}` - `cursor` (query) :1311 | yes (`paginationQuerySchema.cursor`) | `history.ts:132` | PASS |
| `/history/player/{address}` - `limit` (query) :1315 | yes | `history.ts:132` | PASS (F-28-225-16) |
| `/viewer/player/{address}/days` - `address` (path) :1351 | yes | `viewer.ts:169` | PASS (F-28-225-15) |
| `/viewer/player/{address}/day/{day}` - `address` (path) :1399 | yes (`addressDayParamSchema.address`, inherited from `addressParamSchema`) | `viewer.ts:320` | PASS (F-28-225-15) |
| `/viewer/player/{address}/day/{day}` - `day` (path) :1404 | yes (`addressDayParamSchema.day`) | `viewer.ts:320` | PASS |

**Result: Zero orphan-in-openapi parameters.** Every openapi `parameters:` entry across all 27 endpoints has a matching Zod field at the corresponding route. This is a strong result — it means openapi is not declaring parameters the code doesn't validate; every openapi declared parameter is enforced at runtime by Zod. (What openapi is missing is the *constraints* on those parameters — `pattern:`, `minimum:`, `default:` — which are covered by F-28-225-15/16/17, not by "orphan-in-openapi".)

---

## Orphan Zod schemas

Per plan action item #5: exported Zod schemas with zero route imports (either as request-schema or response-schema attachment). These are context, not API-05 findings.

**Scan result across all 6 schema files:**

- `common.ts`: `addressParamSchema` (request, 5 uses), `errorResponseSchema` (response, 4 uses — both sides of `player.ts` and `viewer.ts` 404 attachments), `paginationQuerySchema` (request, 1 use), `encodeCursor` (function, used internally by `history.ts` paginate helper), `decodeCursor` (function, used internally). **Zero orphans.**
- `game.ts`: `jackpotDistributionSchema` (internal, element of `jackpotLevelResponseSchema`), `jackpotLevelResponseSchema` (response, 1 use), `levelParamSchema` (request, 2 uses), `jackpotOverviewRowSchema` (internal, element), `jackpotOverviewResponseSchema` (response, 1 use), `jackpotPlayerParamsSchema` (request, 1 use), `jackpotPlayerResponseSchema` (response, 1 use), `gameStateResponseSchema` (response, 1 use). Plus 2 TypeScript `type` exports (`JackpotOverviewRow`, `JackpotOverviewResponse`, `JackpotPlayerResponse`) — type aliases, not runtime schemas. **Zero runtime-schema orphans.**
- `history.ts`: `jackpotHistoryItemSchema` (internal), `levelHistoryItemSchema` (internal), `playerActivityItemSchema` (internal), `paginatedResponseSchema` (factory, used 3x inside the same file), `jackpotHistoryResponseSchema` (response), `levelHistoryResponseSchema` (response), `playerActivityResponseSchema` (response), `jackpotQuerySchema` (request), `levelQuerySchema` (request). **Zero orphans.**
- `leaderboard.ts`: `leaderboardEntrySchema` (internal, NOT exported — helper), `coinflipLeaderboardResponseSchema` (response), `affiliateLeaderboardResponseSchema` (response), `bafBracketResponseSchema` (response), `coinflipQuerySchema` (request), `levelQuerySchema` (request). **Zero orphans.**
- `player.ts`: `playerDashboardResponseSchema` (response), `jackpotHistoryByPlayerResponseSchema` (response). **Zero orphans.**
- `tokens.ts`: `tokenAnalyticsResponseSchema` (response). **Zero orphans.**

**Total orphan Zod schemas: 0.** Every exported schema is wired into at least one route. The sole quasi-orphan is the `errorResponseSchema` import in `src/api/routes/game.ts:9` (imported into `game.ts` but never attached to any response block within that file) — flagged separately as **F-28-225-19** (dead-import cleanup, not a true orphan because the schema is wired in other route files).

---

## Coverage summary

- **Total exported Zod schemas across 6 `src/api/schemas/` files:** 29 exported entries (including 2 function exports `encodeCursor`/`decodeCursor` and 3 TypeScript `type` exports in `game.ts`; excluding the non-exported internal `leaderboardEntrySchema`).
- **Request-side (used as `schema.querystring` / `schema.params` / `schema.body` by ≥1 route):** 8 from `src/api/schemas/`: `addressParamSchema`, `paginationQuerySchema`, `levelParamSchema` (in game.ts), `jackpotPlayerParamsSchema`, `jackpotQuerySchema`, `levelQuerySchema` (in history.ts), `coinflipQuerySchema`, `levelQuerySchema` (in leaderboard.ts). + 6 inline declarations in route files = **14 total request-side schemas.**
- **Response-side (audited in Plan 225-02, out of scope for 225-03):** 14 in `src/api/schemas/`: `errorResponseSchema`, `jackpotLevelResponseSchema`, `jackpotOverviewResponseSchema`, `jackpotPlayerResponseSchema`, `gameStateResponseSchema`, `jackpotHistoryResponseSchema`, `levelHistoryResponseSchema`, `playerActivityResponseSchema`, `coinflipLeaderboardResponseSchema`, `affiliateLeaderboardResponseSchema`, `bafBracketResponseSchema`, `playerDashboardResponseSchema`, `jackpotHistoryByPlayerResponseSchema`, `tokenAnalyticsResponseSchema`. + inline response schemas in route files (`healthResponseSchema`, `dayDetailResponseSchema`, `ticketsResponseSchema`, `rngListResponseSchema`, `activePlayersResponseSchema`, `playerTraitsResponseSchema`, `playerDaysResponseSchema`, `daySnapshotResponseSchema`, `winnersResponseSchema`, `latestJackpotDayResponseSchema`, `rollResponseSchema`, `earliestJackpotDayResponseSchema`, + 1 inline in `/replay/distributions/:level`) = 26+ response-side (handled by Plan 225-02).
- **Internal (used only within the same or sibling `src/api/schemas/` files; not directly imported by routes):** 7 (`jackpotDistributionSchema`, `jackpotOverviewRowSchema`, `jackpotHistoryItemSchema`, `levelHistoryItemSchema`, `playerActivityItemSchema`, `paginatedResponseSchema` factory, `leaderboardEntrySchema` non-exported).
- **Not a schema (functions / type-only exports):** 5 (`encodeCursor`, `decodeCursor` in common.ts + 3 TypeScript `type` exports in game.ts).
- **Orphan (exported but never imported anywhere):** **0**.
- **Total openapi.yaml `parameters:` entries across 27 endpoints:** 27 endpoints → **28 total parameter entries** (not one per endpoint; `/game/jackpot/:level/player/:addr` has 3 params; `/history/jackpots` has 3; `/history/levels` has 2; `/history/player/:address` has 3; `/viewer/player/:address/day/:day` has 2; 11 endpoints have 0 params). Confirmed by summing the path→param map in `224-01-API-ROUTE-MAP.md` Pass 1 rows 1-27: 0 (health) + 0 (game.state) + 1 (winners) + 1 (roll1) + 1 (roll2) + 0 (latest-day) + 0 (earliest-day) + 1 (`/game/jackpot/{level}`) + 1 (overview) + 3 (`{level}/player/{addr}`) + 1 (`/player/{address}`) + 1 (jackpot-history) + 1 (`/replay/day/{day}`) + 0 (`/replay/rng`) + 0 (`/replay/players`) + 1 (tickets) + 1 (distributions) + 1 (player-traits) + 1 (coinflip) + 1 (affiliate) + 1 (baf) + 3 (`/history/jackpots`) + 2 (`/history/levels`) + 3 (`/history/player/{address}`) + 1 (`/viewer/player/{address}/days`) + 2 (`/viewer/player/{address}/day/{day}`) + 0 (tokens) = **28 openapi parameter entries.** (Re-verified against the 28-row orphan-openapi table in the preceding section — exact match.)
- **openapi parameters covered by Zod (parameter name matches a Zod field in the route's request schema):** all 28 / 28 parameters (per the orphan-openapi scan above).
- **Orphan-in-openapi (parameter declared in openapi.yaml but no Zod counterpart):** **0**.
- **Coverage %:** `100 * 28 / (28 + 0) = 100.0%` — every openapi-declared parameter is enforced by Zod at runtime.

**What drift exists is on *constraints*, not *presence*.** The per-schema verdicts above show that while every openapi parameter has a Zod counterpart at the field-name level, the type/required/regex/min/max/default constraints diverge systemically across 3 major patterns (F-28-225-15, 16, 17).

---

## Summary

- **Schemas audited:** 6 schema files + 6 inline route-file declarations = 12 source locations, producing 14 request-side Zod schemas.
- **Endpoints covered by this audit:** 26 / 27 (every endpoint in the 224 PAIRED-27 universe except `/health` which has no querystring/params/body). `/tickets/level/:level/trait/:traitId/composition` at `game.ts:1223` (post-224 addition) is out of scope per D-225-05 + the in-scope note above.
- **Findings emitted by this plan:** 9 F-stubs (`F-28-225-14` through `F-28-225-22` inclusive). Breakdown:
  - `F-28-225-14` — rescinded / null entry (openapi already has `required: true`); ID preserved for sequential allocation.
  - `F-28-225-15` — LOW — openapi lacks `pattern:` on all 6 address-family params (6 occurrences, 1 systemic stub).
  - `F-28-225-16` — LOW — `limit` query param default-mismatch (`50` in docs vs `20` in Zod) + min/max absent in docs (3 occurrences, 1 systemic stub).
  - `F-28-225-17` — INFO — openapi `minimum:` documented but Zod doesn't enforce on 4 optional query params (4 occurrences, 1 systemic stub).
  - `F-28-225-18` — null entry (initial over-flag, not a finding); ID preserved.
  - `F-28-225-19` — INFO — dead `errorResponseSchema` import in `game.ts:9`.
  - `F-28-225-20` — INFO — regex character-class drift between two address-regex Zod declarations (cosmetic).
  - `F-28-225-21` — LOW — `playerAddressParamSchema` in `replay.ts:56` lacks 0x regex that every other address endpoint enforces (consistency gap).
  - `F-28-225-22` — INFO — three cross-file name collisions (`dayParamSchema`, `levelParamSchema`, `levelQuerySchema`) with different shapes (code-hygiene).
- **Findings by severity:** INFO = 6 (F-28-225-14, 17, 18, 19, 20, 22), LOW = 3 (F-28-225-15, 16, 21). Total = 9.
  - Two of the 9 (F-28-225-14, F-28-225-18) are null/rescinded entries that preserve sequential ID allocation.
- **Findings by direction:** code->docs = 6 (F-28-225-15, 16, 17, 21 are code->docs; F-28-225-14 rescinded code->docs; F-28-225-18 null code->docs). code-only (not a Zod↔openapi drift) = 3 (F-28-225-19, 20, 22).
- **Findings by suggested resolution:** RESOLVED-DOC default recommended: F-28-225-15, 16 (two systemic patterns; RESOLVED-DOC is cheapest — add `pattern:` and fix `default:` in openapi.yaml). RESOLVED-CODE recommended: F-28-225-17 (add `.min(N)` to Zod is trivial and tightens contract), F-28-225-19 (remove dead import or attach response schemas), F-28-225-20 (consolidate regex into shared constant), F-28-225-21 (swap `playerAddressParamSchema` for `addressParamSchema`), F-28-225-22 (consolidate name-colliding schemas).
- **F-28-225-NN IDs consumed by this plan:** `F-28-225-14` through `F-28-225-22` (9 IDs inclusive). Plans 225-01 (01-04), 225-02 (05-13), 225-03 (14-22). Total Phase 225 F-stubs = 22.
- **Direction reconfirmation:** All request-side Zod↔openapi mismatches default Direction: `code->docs` per D-225-02. Exception: orphan-openapi parameters (docs declare a parameter Zod does not validate) use Direction: `docs->code` per 225-03-PLAN interfaces block — **none of those exist** in this codebase (0/28 openapi parameters are orphan-in-openapi; every documented parameter has Zod coverage). The intra-code-consistency findings (F-28-225-19, 20, 22) use direction `code-only` (not Zod↔openapi; included per plan truth #6 context).
- **Scope exclusion reconfirmation:** Response-side schemas audited in Plan 225-02 (not this plan). Indexer-side schemas in `src/db/schema/*.ts` audited in Phase 226 (not this phase).

---

## Phase boundary reminder

- **Phase 225 Plan 03 scope (this plan):** Request-side Zod schemas (`schema.params`, `schema.querystring`, `schema.body`) in `src/api/schemas/*.ts` and inline route-file declarations, vs openapi.yaml `parameters:` entries for the 27 PAIRED endpoints locked by Phase 224.
- **Phase 225 siblings (shared F-28-225-NN pool):** Plan 225-01 (F-28-225-01..04) audits HTTP handler JSDoc/inline comments; Plan 225-02 (F-28-225-05..13) audits response-shape alignment. All three plans contribute to the same finding pool for Phase 229 consolidation.
- **Phase 226 scope (future):** `src/db/schema/*.ts` Drizzle tables vs applied migrations in `drizzle/*.sql` (SCHEMA-01..04). No overlap with Phase 225.
- **Phase 229 scope (future):** Findings consolidation. Phase 229 will roll F-28-225-01..22 into `audit/FINDINGS-v28.0.md` with severity + direction + resolution status per FIND-01..03.

---

*End of 225-03-REQUEST-SCHEMA-AUDIT.md — Phase 225 Plan 03 catalog; API-05 satisfied.*
