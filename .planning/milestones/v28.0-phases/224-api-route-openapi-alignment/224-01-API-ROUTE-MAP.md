# Phase 224 Plan 01 — API Route & OpenAPI Alignment Catalog

**Phase:** 224 — API Route and OpenAPI Alignment
**Plan:** 01 (single-plan phase)
**Milestone:** v28.0 Database & API Intent Alignment Audit
**Requirements satisfied:** API-01 (every openapi endpoint has a matching route), API-02 (every implemented route is documented in both openapi.yaml AND API.md)
**Executed:** 2026-04-13

## Audit-target source-of-truth files

All paths are under `/home/zak/Dev/PurgeGame/database/` (sibling repo, read-only cross-repo audit per D-224-05):

- Code routes (8 files): `src/api/routes/{game,health,history,leaderboards,player,replay,tokens,viewer}.ts`
- Prefix composition: `src/api/server.ts` lines 37-44 (`app.register(xxxRoutes, { prefix: '/...' })`)
- OpenAPI spec: `docs/openapi.yaml` (1708 lines, 27 path entries)
- Prose docs: `docs/API.md` (883 lines, 27 endpoint headings)

No files in `database/` are modified by this audit. No files are created under `scripts/` (per D-224-01: catalog-only, no gate shipped this phase).

## Verdict legend

Pass 1 (openapi→code) and Pass 2 (code→openapi+API.md) share a common verdict vocabulary:

| Verdict | Meaning |
| --- | --- |
| `PAIRED` | openapi entry has a matching code route (Pass 1) |
| `PAIRED-BOTH` | code route has a matching openapi entry AND a matching API.md heading (Pass 2) |
| `MISSING-IN-CODE` | openapi entry with no matching `fastify.<method>(...)` registration |
| `MISSING-OPENAPI` | code route with no matching `openapi.yaml paths:` key |
| `MISSING-APIMD` | code route with no matching `### METHOD /path` heading in API.md |
| `MISSING-BOTH` | code route missing from both openapi.yaml AND API.md |
| `JUSTIFIED` | intentional drift with inline rationale column (per D-224-06) |

Sub-verdicts for PAIRED / PAIRED-BOTH rows:

| Sub-verdict | Meaning |
| --- | --- |
| METHOD match | `get`/`post`/etc. in openapi == `fastify.get`/`post`/etc. in code |
| path match | openapi path equals full code path after prefix composition |
| params present (both sides) | every parameter NAME (path/query) in openapi appears in the route's Zod `params:`/`querystring:` schema, and vice versa (NAME-level only, no type comparison — Phase 225 owns types) |
| body shape presence | `requestBody:` block in openapi (YES/NO) == `body:` key in route schema (YES/NO). Field-level comparison is Phase 225 |

## Severity legend (per D-224-04)

Default severity for all findings: **INFO**.

Promote to **LOW** when any of:

1. An implemented endpoint missing from `openapi.yaml` accepts unvalidated user input — contract gap.
2. An `openapi.yaml` endpoint has no matching implementation — dead contract / broken consumer promise.
3. Method/path mismatch (e.g., openapi declares `GET /x`, code has `POST /x`) — caller-breaking.

Missing parameter declaration on one side is INFO unless the parameter is security-relevant. This phase does not escalate to MEDIUM / HIGH (per D-224-04: doc drift is not a vulnerability class).

---

## Pass 1: openapi->code

This pass indexes every top-level path key under `paths:` in `openapi.yaml`, records its declared parameters (NAMES only) and request-body presence, and — in the bidirectional verdict matrix below — looks for a matching `fastify.<method>(...)` registration in the code routes.

### Input enumeration

Extracted via `grep -nE "^  /" /home/zak/Dev/PurgeGame/database/docs/openapi.yaml`. Parameter names extracted by reading the ~30-50 lines following each path key and collecting `- name: X` entries under `parameters:`. Request-body presence determined by searching for `requestBody:` within each path's block (global `grep -n 'requestBody:'` across the file returns zero matches, confirming no endpoint in openapi.yaml declares a request body).

| # | openapi.yaml line | path | parameters (path/query) | has request body |
| --- | --- | --- | --- | --- |
|  1 |   49 | `/health`                                 | (none)                              | NO |
|  2 |   86 | `/game/state`                             | (none)                              | NO |
|  3 |  187 | `/game/jackpot/day/{day}/winners`         | `day` (path)                        | NO |
|  4 |  289 | `/game/jackpot/day/{day}/roll1`           | `day` (path)                        | NO |
|  5 |  332 | `/game/jackpot/day/{day}/roll2`           | `day` (path)                        | NO |
|  6 |  375 | `/game/jackpot/latest-day`                | (none)                              | NO |
|  7 |  395 | `/game/jackpot/earliest-day`              | (none)                              | NO |
|  8 |  415 | `/game/jackpot/{level}`                   | `level` (path)                      | NO |
|  9 |  486 | `/game/jackpot/{level}/overview`          | `level` (path)                      | NO |
| 10 |  573 | `/game/jackpot/{level}/player/{addr}`     | `level` (path), `addr` (path), `day` (query) | NO |
| 11 |  657 | `/player/{address}`                       | `address` (path)                    | NO |
| 12 |  809 | `/player/{address}/jackpot-history`       | `address` (path)                    | NO |
| 13 |  869 | `/replay/day/{day}`                       | `day` (path)                        | NO |
| 14 |  932 | `/replay/rng`                             | (none)                              | NO |
| 15 |  957 | `/replay/players`                         | (none)                              | NO |
| 16 |  978 | `/replay/tickets/{level}`                 | `level` (path)                      | NO |
| 17 | 1015 | `/replay/distributions/{level}`           | `level` (path)                      | NO |
| 18 | 1062 | `/replay/player-traits/{address}`         | `address` (path)                    | NO |
| 19 | 1092 | `/leaderboards/coinflip`                  | `day` (query)                       | NO |
| 20 | 1128 | `/leaderboards/affiliate`                 | `level` (query)                     | NO |
| 21 | 1164 | `/leaderboards/baf`                       | `level` (query)                     | NO |
| 22 | 1200 | `/history/jackpots`                       | `level` (query), `cursor` (query), `limit` (query) | NO |
| 23 | 1257 | `/history/levels`                         | `cursor` (query), `limit` (query)   | NO |
| 24 | 1299 | `/history/player/{address}`               | `address` (path), `cursor` (query), `limit` (query) | NO |
| 25 | 1344 | `/viewer/player/{address}/days`           | `address` (path)                    | NO |
| 26 | 1389 | `/viewer/player/{address}/day/{day}`      | `address` (path), `day` (path)      | NO |
| 27 | 1554 | `/tokens/analytics`                       | (none)                              | NO |

openapi.yaml path count: 27

Confirmation: `grep -c "^  /" /home/zak/Dev/PurgeGame/database/docs/openapi.yaml` returns **27**. Every row above cites a line that matches `^  /` in the target file (spot-checked rows 1, 10, 22: lines 49, 573, 1200 — all confirmed).

No `requestBody:` declarations exist anywhere in `openapi.yaml` (global grep returns zero matches). All 27 endpoints are GET-only, parameterless bodies. This is consistent with scouting (`<interfaces>` block of 224-01-PLAN.md) and means the "body shape presence" sub-verdict uniformly evaluates to `NO/NO = PASS` for every paired row.

---

## Pass 2: code->openapi+API.md

This pass indexes every `fastify.<method>(<relative>, ...)` registration across the 8 route files, composes the full URL path via the `src/api/server.ts` prefix map, and — in the bidirectional verdict matrix below — looks for matching entries in both `openapi.yaml` and `API.md`.

### Prefix map (src/api/server.ts:37-44)

Confirmed by reading `src/api/server.ts` lines 37-44:

| Route plugin | prefix |
| --- | --- |
| `playerRoutes`       | `/player` |
| `gameRoutes`         | `/game` |
| `healthRoutes`       | `` (no prefix — full path = relative path) |
| `leaderboardRoutes`  | `/leaderboards` |
| `tokenRoutes`        | `/tokens` |
| `historyRoutes`      | `/history` |
| `replayRoutes`       | `/replay` |
| `viewerRoutes`       | `/viewer` |

### Input enumeration

Extracted via `grep -nE "fastify\.(get|post|put|delete|patch)\(" <route_file>`. Parameter names extracted from each registration's Zod `schema.params` / `schema.querystring` references (following imports into `src/api/schemas/*.ts` and in-file `const xxxSchema = z.object({...})` literals). "has request body" is YES only when the registration's `schema` object contains a `body:` key.

Full-path column uses the prefix map above: full = `<prefix> + <relative>`. Health is the sole exception (no prefix: full = relative).

| # | route file:line | METHOD | relative path | full path | declared params (path/query) | has body |
| --- | --- | --- | --- | --- | --- | --- |
|  1 | `database/src/api/routes/game.ts:81`          | GET | `/state`                               | `/game/state`                           | (none)                                       | NO |
|  2 | `database/src/api/routes/game.ts:145`         | GET | `/jackpot/:level`                      | `/game/jackpot/:level`                  | path: `level` (via `levelParamSchema`)       | NO |
|  3 | `database/src/api/routes/game.ts:214`         | GET | `/jackpot/:level/overview`             | `/game/jackpot/:level/overview`         | path: `level` (via `levelParamSchema`)       | NO |
|  4 | `database/src/api/routes/game.ts:364`         | GET | `/jackpot/:level/player/:addr`         | `/game/jackpot/:level/player/:addr`     | path: `level`, `addr` (via `jackpotPlayerParamsSchema`); query: `day` (via `playerDayQuerySchema`) | NO |
|  5 | `database/src/api/routes/game.ts:716`         | GET | `/jackpot/day/:day/winners`            | `/game/jackpot/day/:day/winners`        | path: `day` (via in-file `dayParamSchema`)   | NO |
|  6 | `database/src/api/routes/game.ts:902`         | GET | `/jackpot/day/:day/roll1`              | `/game/jackpot/day/:day/roll1`          | path: `day` (via in-file `dayParamSchema`)   | NO |
|  7 | `database/src/api/routes/game.ts:1016`        | GET | `/jackpot/day/:day/roll2`              | `/game/jackpot/day/:day/roll2`          | path: `day` (via in-file `dayParamSchema`)   | NO |
|  8 | `database/src/api/routes/game.ts:1193`        | GET | `/jackpot/latest-day`                  | `/game/jackpot/latest-day`              | (none)                                       | NO |
|  9 | `database/src/api/routes/game.ts:1218`        | GET | `/jackpot/earliest-day`                | `/game/jackpot/earliest-day`            | (none)                                       | NO |
| 10 | `database/src/api/routes/health.ts:13`        | GET | `/health`                              | `/health`                               | (none)                                       | NO |
| 11 | `database/src/api/routes/history.ts:32`       | GET | `/jackpots`                            | `/history/jackpots`                     | query: `level`, `cursor`, `limit` (via `jackpotQuerySchema`) | NO |
| 12 | `database/src/api/routes/history.ts:85`       | GET | `/levels`                              | `/history/levels`                       | query: `cursor`, `limit` (via `levelQuerySchema`) | NO |
| 13 | `database/src/api/routes/history.ts:129`      | GET | `/player/:address`                     | `/history/player/:address`              | path: `address` (via `addressParamSchema`); query: `cursor`, `limit` (via `paginationQuerySchema`) | NO |
| 14 | `database/src/api/routes/leaderboards.ts:13`  | GET | `/coinflip`                            | `/leaderboards/coinflip`                | query: `day` (via `coinflipQuerySchema`)     | NO |
| 15 | `database/src/api/routes/leaderboards.ts:39`  | GET | `/affiliate`                           | `/leaderboards/affiliate`               | query: `level` (via `levelQuerySchema`)      | NO |
| 16 | `database/src/api/routes/leaderboards.ts:65`  | GET | `/baf`                                 | `/leaderboards/baf`                     | query: `level` (via `levelQuerySchema`)      | NO |
| 17 | `database/src/api/routes/player.ts:17`        | GET | `/:address`                            | `/player/:address`                      | path: `address` (via `addressParamSchema`)   | NO |
| 18 | `database/src/api/routes/player.ts:225`       | GET | `/:address/jackpot-history`            | `/player/:address/jackpot-history`      | path: `address` (via `addressParamSchema`)   | NO |
| 19 | `database/src/api/routes/replay.ts:72`        | GET | `/day/:day`                            | `/replay/day/:day`                      | path: `day` (via in-file `dayParamSchema`)   | NO |
| 20 | `database/src/api/routes/replay.ts:184`       | GET | `/tickets/:level`                      | `/replay/tickets/:level`                | path: `level` (via in-file `levelParamSchema`) | NO |
| 21 | `database/src/api/routes/replay.ts:215`       | GET | `/rng`                                 | `/replay/rng`                           | (none)                                       | NO |
| 22 | `database/src/api/routes/replay.ts:236`       | GET | `/players`                             | `/replay/players`                       | (none)                                       | NO |
| 23 | `database/src/api/routes/replay.ts:254`       | GET | `/distributions/:level`                | `/replay/distributions/:level`          | path: `level` (via in-file `levelParamSchema`) | NO |
| 24 | `database/src/api/routes/replay.ts:325`       | GET | `/player-traits/:address`              | `/replay/player-traits/:address`        | path: `address` (via in-file `playerAddressParamSchema`) | NO |
| 25 | `database/src/api/routes/tokens.ts:8`         | GET | `/analytics`                           | `/tokens/analytics`                     | (none)                                       | NO |
| 26 | `database/src/api/routes/viewer.ts:167`       | GET | `/player/:address/days`                | `/viewer/player/:address/days`          | path: `address` (via `addressParamSchema`)   | NO |
| 27 | `database/src/api/routes/viewer.ts:318`       | GET | `/player/:address/day/:day`            | `/viewer/player/:address/day/:day`      | path: `address`, `day` (via in-file `addressDayParamSchema` = `addressParamSchema.extend({day})`) | NO |

code route registration count: 27

Confirmation: `grep -hcE 'fastify\.(get|post|put|delete|patch)\(' /home/zak/Dev/PurgeGame/database/src/api/routes/*.ts | awk '{s+=$1} END {print s}'` returns **27** (game.ts:9, health.ts:1, history.ts:3, leaderboards.ts:3, player.ts:2, replay.ts:6, tokens.ts:1, viewer.ts:2 = 27). Every row's full-path column correctly composes prefix + relative: row 14 (leaderboards.ts:13 `/coinflip`) resolves to `/leaderboards/coinflip`; row 10 (health.ts:13 `/health`) correctly has no prefix and stays `/health`. All 8 route files appear in at least one row.

**Scouting drift note.** The plan's `<interfaces>` block (lines 71-72 of 224-01-PLAN.md) estimated `health.ts (581 bytes - expect ~2 registrations)`; the actual `health.ts` at `/home/zak/Dev/PurgeGame/database/src/api/routes/health.ts` has exactly 1 registration (`fastify.get('/health', ...)` at line 13) and is 581 bytes. This is not a finding — the estimate was wrong, the file is correct. The total 28 estimate was likewise a scouting estimate; the actual measured count is 27 which matches the 27 path entries in openapi.yaml and the 27 headings in API.md. The three enumerations agree at 27; any mismatches must therefore be path-level, not count-level.

**Alternate registration form scan.** `grep -nE 'fastify\.route\(' /home/zak/Dev/PurgeGame/database/src/api/routes/*.ts` returns zero matches, confirming that every registration uses the `fastify.<method>(path, opts, handler)` form — no registrations are silently missed by the enumeration regex.

**Body-shape detection.** `grep -nE '^[[:space:]]*body:[[:space:]]*' /home/zak/Dev/PurgeGame/database/src/api/routes/*.ts` returns zero matches. No registration declares a Fastify request-body schema. Combined with the zero-`requestBody:` count in openapi.yaml, the "body shape presence" sub-verdict evaluates to `NO == NO = PASS` uniformly across all 27 paired rows.

### API.md endpoint headings

Extracted via `grep -nE "^### (GET|POST|PUT|DELETE|PATCH) /" /home/zak/Dev/PurgeGame/database/docs/API.md`. Section-anchor column uses the GitHub-style slug for the heading text (lowercase; `/` and ` ` replaced with `-`; `{` and `}` stripped).

| # | API.md line | METHOD | full path | section anchor (slug) |
| --- | --- | --- | --- | --- |
|  1 |    9 | GET | `/health`                                  | `get-health` |
|  2 |   32 | GET | `/game/state`                              | `get-gamestate` |
|  3 |   69 | GET | `/game/jackpot/day/{day}/winners`          | `get-gamejackpotdaydaywinners` |
|  4 |  115 | GET | `/game/jackpot/day/{day}/roll1`            | `get-gamejackpotdaydayroll1` |
|  5 |  162 | GET | `/game/jackpot/day/{day}/roll2`            | `get-gamejackpotdaydayroll2` |
|  6 |  212 | GET | `/game/jackpot/latest-day`                 | `get-gamejackpotlatest-day` |
|  7 |  217 | GET | `/game/jackpot/earliest-day`               | `get-gamejackpotearliest-day` |
|  8 |  222 | GET | `/game/jackpot/{level}`                    | `get-gamejackpotlevel` |
|  9 |  255 | GET | `/game/jackpot/{level}/overview`           | `get-gamejackpotleveloverview` |
| 10 |  310 | GET | `/game/jackpot/{level}/player/{addr}`      | `get-gamejackpotlevelplayeraddr` |
| 11 |  374 | GET | `/player/{address}`                        | `get-playeraddress` |
| 12 |  416 | GET | `/player/{address}/jackpot-history`        | `get-playeraddressjackpot-history` |
| 13 |  447 | GET | `/replay/day/{day}`                        | `get-replaydayday` |
| 14 |  479 | GET | `/replay/rng`                              | `get-replayrng` |
| 15 |  492 | GET | `/replay/players`                          | `get-replayplayers` |
| 16 |  505 | GET | `/replay/tickets/{level}`                  | `get-replayticketslevel` |
| 17 |  525 | GET | `/replay/distributions/{level}`            | `get-replaydistributionslevel` |
| 18 |  559 | GET | `/replay/player-traits/{address}`          | `get-replayplayer-traitsaddress` |
| 19 |  581 | GET | `/leaderboards/coinflip`                   | `get-leaderboardscoinflip` |
| 20 |  601 | GET | `/leaderboards/affiliate`                  | `get-leaderboardsaffiliate` |
| 21 |  609 | GET | `/leaderboards/baf`                        | `get-leaderboardsbaf` |
| 22 |  621 | GET | `/history/jackpots`                        | `get-historyjackpots` |
| 23 |  651 | GET | `/history/levels`                          | `get-historylevels` |
| 24 |  668 | GET | `/history/player/{address}`                | `get-historyplayeraddress` |
| 25 |  692 | GET | `/viewer/player/{address}/days`            | `get-viewerplayeraddressdays` |
| 26 |  722 | GET | `/viewer/player/{address}/day/{day}`       | `get-viewerplayeraddressdayday` |
| 27 |  783 | GET | `/tokens/analytics`                        | `get-tokensanalytics` |

API.md endpoint heading count: 27

Confirmation: `grep -cE "^### (GET|POST|PUT|DELETE|PATCH) /" /home/zak/Dev/PurgeGame/database/docs/API.md` returns **27**. Every row cites a real `### METHOD /` heading line in that file (spot-checked rows 1, 13, 27: lines 9, 447, 783 — all confirmed).

**Non-endpoint `###` heading filter.** The regex `^### (GET|POST|PUT|DELETE|PATCH) /` deliberately excludes `###` headings that name concepts rather than endpoints. The tail of `API.md` (under the `## Key Semantic Clarifications` section starting at line 814) contains at least six such conceptual subsections:

- `### sourceLevel vs. level vs. purchaseLevel` at line 816
- `### Roll 1 vs. Roll 2 Classification` at line 824
- `### BURNIE vs. Tickets vs. ETH` at line 831
- `### traitId = null Semantics` at line 838
- `### hasBonus Flag` at line 843
- `### spreadBuckets Interpretation` at line 848

None of these begin with an HTTP verb + `/`, so the regex correctly excludes all six. This is intentional scoping, not accidental data loss: `API.md` uses `###` both as an endpoint-heading level and as a concept-heading level, and only the endpoint form belongs in the enumeration.

---

## Bidirectional verdict matrix

Each row reconciles one endpoint across all three sources: openapi.yaml (left), code route (center), API.md section (right), with four sub-verdicts (method / path / param-name presence / body-shape presence), an overall verdict from the legend, severity, and rationale.

Matrix-generation method:

- Path-equivalence rule: openapi `{name}` and Fastify `:name` are treated as equal after curly-brace normalization (both represent the same path parameter).
- Parameter-name comparison: strict symmetric-difference check on path and query parameter name sets (openapi `parameters:` block vs code Zod `params:`/`querystring:` schemas). Types are NOT compared (Phase 225 scope).
- Body-shape presence: YES if either side declares a body, NO if neither. Since global greps show zero `requestBody:` in openapi.yaml and zero `body:` in route schemas, every row evaluates to `NO == NO = PASS`.
- Method-match: openapi entry under path must have a key matching the code registration's `fastify.<method>`. All 27 openapi entries use `get:`; all 27 code registrations use `fastify.get(...)`.

Column header (single line, 10 columns):

`openapi.yaml | route file:line | API.md section | METHOD match | path match | params present (both sides) | body shape presence | verdict | severity | rationale`

| openapi.yaml | route file:line | API.md section | METHOD match | path match | params present (both sides) | body shape presence | verdict | severity | rationale |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `:49 /health`                                 | `health.ts:13`          | `API.md:9 GET /health`                            | PASS | PASS | PASS (none / none)                                                 | PASS (NO / NO) | PAIRED-BOTH | INFO | Full triple alignment. |
| `:86 /game/state`                             | `game.ts:81`            | `API.md:32 GET /game/state`                       | PASS | PASS | PASS (none / none)                                                 | PASS (NO / NO) | PAIRED-BOTH | INFO | Full triple alignment. |
| `:187 /game/jackpot/day/{day}/winners`        | `game.ts:716`           | `API.md:69 GET /game/jackpot/day/{day}/winners`   | PASS | PASS | PASS (path `day` / path `day`)                                     | PASS (NO / NO) | PAIRED-BOTH | INFO | Full triple alignment. |
| `:289 /game/jackpot/day/{day}/roll1`          | `game.ts:902`           | `API.md:115 GET /game/jackpot/day/{day}/roll1`    | PASS | PASS | PASS (path `day` / path `day`)                                     | PASS (NO / NO) | PAIRED-BOTH | INFO | Full triple alignment. |
| `:332 /game/jackpot/day/{day}/roll2`          | `game.ts:1016`          | `API.md:162 GET /game/jackpot/day/{day}/roll2`    | PASS | PASS | PASS (path `day` / path `day`)                                     | PASS (NO / NO) | PAIRED-BOTH | INFO | Full triple alignment. |
| `:375 /game/jackpot/latest-day`               | `game.ts:1193`          | `API.md:212 GET /game/jackpot/latest-day`         | PASS | PASS | PASS (none / none)                                                 | PASS (NO / NO) | PAIRED-BOTH | INFO | Full triple alignment. |
| `:395 /game/jackpot/earliest-day`             | `game.ts:1218`          | `API.md:217 GET /game/jackpot/earliest-day`       | PASS | PASS | PASS (none / none)                                                 | PASS (NO / NO) | PAIRED-BOTH | INFO | Full triple alignment. |
| `:415 /game/jackpot/{level}`                  | `game.ts:145`           | `API.md:222 GET /game/jackpot/{level}`            | PASS | PASS | PASS (path `level` / path `level`)                                 | PASS (NO / NO) | PAIRED-BOTH | INFO | Full triple alignment. |
| `:486 /game/jackpot/{level}/overview`         | `game.ts:214`           | `API.md:255 GET /game/jackpot/{level}/overview`   | PASS | PASS | PASS (path `level` / path `level`)                                 | PASS (NO / NO) | PAIRED-BOTH | INFO | Full triple alignment. |
| `:573 /game/jackpot/{level}/player/{addr}`    | `game.ts:364`           | `API.md:310 GET /game/jackpot/{level}/player/{addr}` | PASS | PASS | PASS (path `level,addr`; query `day` / path `level,addr`; query `day`) | PASS (NO / NO) | PAIRED-BOTH | INFO | Full triple alignment; optional query `day` declared on both sides. |
| `:657 /player/{address}`                      | `player.ts:17`          | `API.md:374 GET /player/{address}`                | PASS | PASS | PASS (path `address` / path `address`)                             | PASS (NO / NO) | PAIRED-BOTH | INFO | Full triple alignment. |
| `:809 /player/{address}/jackpot-history`      | `player.ts:225`         | `API.md:416 GET /player/{address}/jackpot-history`| PASS | PASS | PASS (path `address` / path `address`)                             | PASS (NO / NO) | PAIRED-BOTH | INFO | Full triple alignment. |
| `:869 /replay/day/{day}`                      | `replay.ts:72`          | `API.md:447 GET /replay/day/{day}`                | PASS | PASS | PASS (path `day` / path `day`)                                     | PASS (NO / NO) | PAIRED-BOTH | INFO | Full triple alignment. |
| `:932 /replay/rng`                            | `replay.ts:215`         | `API.md:479 GET /replay/rng`                      | PASS | PASS | PASS (none / none)                                                 | PASS (NO / NO) | PAIRED-BOTH | INFO | Full triple alignment. |
| `:957 /replay/players`                        | `replay.ts:236`         | `API.md:492 GET /replay/players`                  | PASS | PASS | PASS (none / none)                                                 | PASS (NO / NO) | PAIRED-BOTH | INFO | Full triple alignment. |
| `:978 /replay/tickets/{level}`                | `replay.ts:184`         | `API.md:505 GET /replay/tickets/{level}`          | PASS | PASS | PASS (path `level` / path `level`)                                 | PASS (NO / NO) | PAIRED-BOTH | INFO | Full triple alignment. |
| `:1015 /replay/distributions/{level}`         | `replay.ts:254`         | `API.md:525 GET /replay/distributions/{level}`    | PASS | PASS | PASS (path `level` / path `level`)                                 | PASS (NO / NO) | PAIRED-BOTH | INFO | Full triple alignment. |
| `:1062 /replay/player-traits/{address}`       | `replay.ts:325`         | `API.md:559 GET /replay/player-traits/{address}`  | PASS | PASS | PASS (path `address` / path `address`)                             | PASS (NO / NO) | PAIRED-BOTH | INFO | Full triple alignment. |
| `:1092 /leaderboards/coinflip`                | `leaderboards.ts:13`    | `API.md:581 GET /leaderboards/coinflip`           | PASS | PASS | PASS (query `day` / query `day`)                                   | PASS (NO / NO) | PAIRED-BOTH | INFO | Full triple alignment. |
| `:1128 /leaderboards/affiliate`               | `leaderboards.ts:39`    | `API.md:601 GET /leaderboards/affiliate`          | PASS | PASS | PASS (query `level` / query `level`)                               | PASS (NO / NO) | PAIRED-BOTH | INFO | Full triple alignment. |
| `:1164 /leaderboards/baf`                     | `leaderboards.ts:65`    | `API.md:609 GET /leaderboards/baf`                | PASS | PASS | PASS (query `level` / query `level`)                               | PASS (NO / NO) | PAIRED-BOTH | INFO | Full triple alignment. |
| `:1200 /history/jackpots`                     | `history.ts:32`         | `API.md:621 GET /history/jackpots`                | PASS | PASS | PASS (query `level,cursor,limit` / query `level,cursor,limit`)     | PASS (NO / NO) | PAIRED-BOTH | INFO | Full triple alignment. |
| `:1257 /history/levels`                       | `history.ts:85`         | `API.md:651 GET /history/levels`                  | PASS | PASS | PASS (query `cursor,limit` / query `cursor,limit`)                 | PASS (NO / NO) | PAIRED-BOTH | INFO | Full triple alignment. |
| `:1299 /history/player/{address}`             | `history.ts:129`        | `API.md:668 GET /history/player/{address}`        | PASS | PASS | PASS (path `address`; query `cursor,limit` / path `address`; query `cursor,limit`) | PASS (NO / NO) | PAIRED-BOTH | INFO | Full triple alignment. |
| `:1344 /viewer/player/{address}/days`         | `viewer.ts:167`         | `API.md:692 GET /viewer/player/{address}/days`    | PASS | PASS | PASS (path `address` / path `address`)                             | PASS (NO / NO) | PAIRED-BOTH | INFO | Full triple alignment. |
| `:1389 /viewer/player/{address}/day/{day}`    | `viewer.ts:318`         | `API.md:722 GET /viewer/player/{address}/day/{day}` | PASS | PASS | PASS (path `address,day` / path `address,day`)                     | PASS (NO / NO) | PAIRED-BOTH | INFO | Full triple alignment. |
| `:1554 /tokens/analytics`                     | `tokens.ts:8`           | `API.md:783 GET /tokens/analytics`                | PASS | PASS | PASS (none / none)                                                 | PASS (NO / NO) | PAIRED-BOTH | INFO | Full triple alignment. |

**Matrix row count: 27** — every row from the Task 1 openapi.yaml input table AND every row from the Task 2 code input table AND every row from the Task 3 API.md input table are covered. Row-count reconciliation: 27 openapi rows == 27 code rows == 27 API.md rows == 27 matrix rows == 27 PAIRED-BOTH verdicts.

**No `MISSING-*` verdicts were issued** because all three enumerations reconcile 1-1 after path normalization (`{name}` ≡ `:name`). No `JUSTIFIED` verdicts were issued because no drift was found to justify.

**No LOW-severity promotions.** The three promotion criteria in D-224-04 each require some form of drift (missing code for an openapi entry, missing openapi for a code endpoint accepting unvalidated input, or a method/path mismatch). None occurred here, so every row stays at the default INFO severity.

**Scope discipline.** No rationale column inspects handler-body behavior, response-shape fields, or Zod-schema property types beyond name presence. Every rationale is a one-sentence structural confirmation ("Full triple alignment", "optional query `day` declared on both sides"). Handler comments, response schemas, and validation-schema types are explicitly out of scope for Phase 224 and are Phase 225's responsibility (API-03, API-04, API-05) — see the Phase boundary reminder at the end of this document.

---

## Summary

### Coverage totals (ROADMAP success criterion #4 format)

Coverage: 27 endpoints in openapi.yaml / 27 routes in code / 27 entries in API.md / 27 paired-both / 0 missing-either-side

### Per-direction drift counts

| direction | count | example endpoint |
| --- | --- | --- |
| docs-to-code (openapi entry with no code match)                       | 0 | (none — no drift in this direction) |
| code-to-docs.openapi (code route with no openapi entry)               | 0 | (none — no drift in this direction) |
| code-to-docs.apimd (code route with no API.md heading)                | 0 | (none — no drift in this direction) |
| method-mismatch (PAIRED rows with METHOD match = FAIL)                | 0 | (none — all 27 pairs agree on `get`) |
| path-mismatch (PAIRED rows with path match = FAIL after prefix comp.) | 0 | (none — all 27 pairs agree after `{name}` ≡ `:name` normalization) |
| param-name-mismatch (PAIRED rows with params present = FAIL)          | 0 | (none — all 27 pairs agree on path+query parameter name sets) |
| body-shape-presence-mismatch (PAIRED rows with body shape = FAIL)     | 0 | (none — neither side declares any body anywhere) |

### Severity-promoted findings

**LOW severity count: 0.** No row qualifies for D-224-04 promotion (no docs-to-code dead contracts, no code-to-docs unvalidated-input gaps, no method/path mismatches). All findings stay at default INFO severity — and because every row is PAIRED-BOTH, there are zero finding candidates in total for this phase. See Task 6 section for the finding-candidate rollup with the formal zero-count explanation.

### JUSTIFIED-drift count

**JUSTIFIED row count: 0.** No row needed a D-224-06 justified-drift disposition because no drift was found. The JUSTIFIED verdict mechanism is still defined in the legend for future milestones; it was simply not exercised this phase.

### ROADMAP Phase 224 success-criteria confirmation block

Each of the 4 success criteria from `.planning/ROADMAP.md` Phase 224 section is explicitly satisfied by a specific section of this catalog:

1. **SC1 — "A route↔spec mapping catalog exists in `224-01-API-ROUTE-MAP.md` enumerating every entry from `database/docs/openapi.yaml` alongside the matching `database/src/api/routes/*.ts` handler, with a PASS/FAIL verdict per endpoint covering HTTP method, path, parameters, and request body shape."**
   **Satisfied by:** the `## Bidirectional verdict matrix` section above (lines with column header `openapi.yaml | route file:line | API.md section | METHOD match | path match | params present (both sides) | body shape presence | verdict | severity | rationale`). All 27 matrix rows have sub-verdicts for method, path, params, and body shape presence, with a verdict column (27× `PAIRED-BOTH`).

2. **SC2 — "Every route file in `database/src/api/routes/` (game, health, history, leaderboards, player, replay, tokens, viewer) is enumerated and cross-checked against both `openapi.yaml` AND `database/docs/API.md` with zero undocumented endpoints remaining uncatalogued."**
   **Satisfied by:** the `### Input enumeration` subsection of `## Pass 2` — the table lists all 27 registrations across all 8 route files (game.ts ×9, health.ts ×1, history.ts ×3, leaderboards.ts ×3, player.ts ×2, replay.ts ×6, tokens.ts ×1, viewer.ts ×2). Every row has a corresponding PAIRED-BOTH entry in the verdict matrix (cross-checked against both openapi.yaml AND API.md). **Zero undocumented endpoints:** `code-to-docs.openapi` and `code-to-docs.apimd` both count 0 in the drift table.

3. **SC3 — "Each docs-claim-vs-code-delivery mismatch is classified as docs→code (documented endpoint missing from code) or code→docs (implemented endpoint missing from docs) and added to the Phase 229 finding candidate pool with source file:line references."**
   **Satisfied by:** the `## Finding candidates (Phase 229 rollup pool)` section below — enumerates every non-PAIRED row with `F-28-224-NN` IDs, direction labels, and `/home/zak/Dev/PurgeGame/database/...` file:line citations. **Zero non-PAIRED rows** means zero finding stubs in this phase; the section still exists with an explicit zero-count note so Phase 229 can confirm it received the pool (an empty pool is a valid result).

4. **SC4 — "Coverage totals reported: `{X endpoints in openapi.yaml} / {Y routes in code} / {Z missing either side}` with the bidirectional diff enumerated."**
   **Satisfied by:** the `### Coverage totals` line above (`Coverage: 27 endpoints in openapi.yaml / 27 routes in code / 27 entries in API.md / 27 paired-both / 0 missing-either-side`) and the `### Per-direction drift counts` table enumerating both directions (docs-to-code, code-to-docs.openapi, code-to-docs.apimd) plus sub-verdict drift classes (method, path, params, body).

All 4 success criteria are explicitly addressable via the specific catalog sections cited above.

---

## Finding candidates (Phase 229 rollup pool)

**Functional-drift stub count: 0.** The Task 5 drift table shows 0 across every direction (docs-to-code, code-to-docs.openapi, code-to-docs.apimd) and 0 across every sub-verdict class (method, path, params, body). Zero non-PAIRED matrix rows and zero PAIRED rows with FAIL sub-verdicts means zero functional-drift finding stubs. No JUSTIFIED rows were issued (count: 0), so the formula `(non-PAIRED) + (PAIRED with FAIL) - (JUSTIFIED inline)` = `0 + 0 - 0 = 0`.

**Meta-observational stub count: 1.** One stub is recorded below to document a scouting-vs-reality count reconciliation (plan's `<interfaces>` block at 224-01-PLAN.md lines 71-72 estimated 2 registrations in `health.ts`; actual is 1). This is a planning-artifact observation, not a code/docs drift — health.ts is correct; the scouting estimate was a pre-plan best-guess that reality fine-tuned. It is recorded here at INFO severity with direction `code-to-docs` (broad sense: the plan scouting doc was a pre-execution description of the code, and the code turned out to be correct while the scouting artifact was approximate). Phase 229 can mark this `INFO-ACCEPTED` (no action needed) or `RESOLVED-DOC` if anyone retroactively patches the scouting block.

Total stubs below: **1** (the single meta-observational row). This is fewer than one might expect, but that is precisely because the audit itself succeeded — full triple-alignment is the intended end state, not a failure mode.

### F-28-224-01: health.ts has 1 registration, scouting estimate was ~2

- **Severity:** INFO
- **Direction:** code-to-docs
- **Source:** `/home/zak/Dev/PurgeGame/database/src/api/routes/health.ts:13` (the sole `fastify.get('/health', ...)` registration in a file scouted as having "~2 registrations")
- **Catalog row:** Pass 2 input table row 10 (full path `/health`, registered at `health.ts:13`). Matrix verdict: PAIRED-BOTH, all sub-verdicts PASS.
- **Resolution status:** OPEN — pending Phase 229 disposition
- **Description:** The Phase 224 plan file (`224-01-PLAN.md` lines 71-72) scouted `health.ts` as "581 bytes - expect ~2 registrations". The file is exactly 581 bytes and contains exactly 1 `fastify.get(...)` registration (`/health`, at line 13). The one-registration count reconciles with openapi.yaml (1 `/health:` entry) and API.md (1 `### GET /health` heading) — all three sources agree at 1. This is a pre-execution scouting approximation, not a functional bug: health.ts is correct, the plan's estimate was off by one, and the drift is entirely confined to the planning artifact. Phase 229 should classify as `INFO-ACCEPTED` (scouting estimates are explicitly approximations; reality-first execution corrects them) unless a concurrent planning-hygiene pass wants to retroactively patch the scouting note, in which case `RESOLVED-DOC` applies.

---

## Phase boundary reminder

This catalog grades only **method**, **path** (after `{name}` ≡ `:name` normalization), **parameter-NAME presence on both sides** (path + query), and **request-body-shape presence** per the Phase 224 CONTEXT.md scope (D-224-03). Every other dimension — parameter types, query validation semantics, response schema field-level matching, handler JSDoc/inline comment accuracy, error-response shape, status-code mapping, and `API.md` example-snippet correctness — is explicitly **out of scope** for Phase 224 and is the responsibility of:

- **Phase 225 / API-03** — handler JSDoc/inline-comment accuracy (preconditions, side effects, return shape)
- **Phase 225 / API-04** — response-shape field-for-field audit (field names, types, optionality, enum values)
- **Phase 225 / API-05** — Fastify request-validation schema deep comparison (parameter types, required/optional, enum constraints)
- **API-06 (future milestone)** — error-response / HTTP-status-code audit
- **API-07 (future milestone)** — `API.md` example-snippet byte-for-byte correctness

Phase 225 consumers of this catalog can treat the 27× PAIRED-BOTH rows as a locked input set: no row in this catalog will be renumbered, reclassified, or redirected by subsequent Phase 224 work. All 27 endpoints are confirmed triple-documented at the structural level; Phase 225 picks up from here to verify type-level and behavioral conformance.
