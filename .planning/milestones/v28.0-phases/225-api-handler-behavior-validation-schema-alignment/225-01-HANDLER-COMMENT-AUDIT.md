# Phase 225 Plan 01 — HTTP Handler Comment Audit Catalog (API-03)

**Phase:** 225 — API Handler Behavior & Validation Schema Alignment
**Plan:** 225-01
**Requirement satisfied:** API-03 — JSDoc/inline comments on HTTP handlers accurately describe the handler body's behavior (preconditions, side effects, return shape). Restricted to HTTP handlers only per D-225-01 (split from the literal requirement wording).
**Scope exclusion (D-225-01):** `/home/zak/Dev/PurgeGame/database/src/handlers/*.ts` (27 files, 4,367 lines) is the indexer event-handler directory — dispatched by `src/indexer/event-processor.ts`, consumes `ctx.args` — and is **deferred to Phase 227 IDX-03**. No file under that path is audited here. The scope-exclusion note is re-stated in the Summary footer per the success criteria.
**Input universe (D-225-06 / Phase 224 Pass 2 locked count):** 27 HTTP handlers across 8 route files in `/home/zak/Dev/PurgeGame/database/src/api/routes/*.ts`. Counts per file: `game.ts = 9`, `health.ts = 1`, `history.ts = 3`, `leaderboards.ts = 3`, `player.ts = 2`, `replay.ts = 6`, `tokens.ts = 1`, `viewer.ts = 2`. Locked by `.planning/phases/224-api-route-openapi-alignment/224-01-API-ROUTE-MAP.md` Pass 2 (lines 128-156).
**Cross-repo convention (D-225-07):** All file:line references point into `/home/zak/Dev/PurgeGame/database/...`; no file under the `database/` tree is created, modified, or staged by this plan.
**Finding-ID scheme (D-225-06):** `F-28-225-NN` sequential across all three Phase 225 plans. Allocated in this plan: `F-28-225-01 .. F-28-225-04`. Plans 225-02 and 225-03 continue from `F-28-225-05`.

---

## Tier legend (D-225-04 verbatim)

**Tier A (always flag): Outright wrong.** The comment makes a factual claim the code contradicts. Examples: "returns users sorted by score desc" — code sorts asc; "paginates by cursor" — code has no cursor logic; "always returns 200" — code returns 404 when player not found; comment documents a parameter the code doesn't read.

**Tier B (flag when material): Stale/incomplete.** The comment documents some behavior but omits a meaningful side effect, branch, or post-condition. "Material" = a caller behaving on the comment alone would make a wrong decision. Examples: "returns player stats" — code also writes to a cache; "fetches jackpot history" — code filters to the caller's day silently; "lists two error codes" — code throws a third.

**Tier C (NOT flagged per-handler — counted only): Missing JSDoc.** Handler has NO `/** */` block above the `fastify.<method>(...)` registration. Absence is a style gap, not a drift finding. D-225-04 instructs: note counts as context, do not enumerate per-handler.

**Tier D (NOT flagged at all): Cosmetic/typos.** Stale parameter names after rename, grammar, typos. Low signal; high noise. Excluded entirely.

Ambiguity rule (from 225-CONTEXT.md "Current Observations" and the plan's high-noise warning): when in doubt between Tier B and Tier D, default to NOT flagging.

## Severity legend (225-CONTEXT.md "Severity scheme", inherited from D-224-04)

- **INFO** (default) — documentation drift, no runtime or caller-breaking impact.
- **LOW** (promotion required; only three caller-breaking conditions apply):
  1. Handler returns a field type Zod says is `string` but actually is `number` (runtime serialization mismatch).
  2. Required request parameter documented optional in openapi.yaml (callers omit it, get 400).
  3. Response field documented in openapi.yaml that the handler never emits (callers expecting it crash).
- LOW promotions are justified inline on the finding stub with a one-sentence rationale per D-224-04. Do NOT promote beyond LOW — documentation drift is not a vulnerability class.

---

## Per-handler verdicts

Comment-presence legend: `JSDoc` = `/** */` block immediately above the `fastify.<method>(...)` registration; `inline` = only `//` line-comments (above the registration or inside the handler body) with no JSDoc block; `NONE` = no comments at all within the handler scope.

Verdict legend: `PASS` = comment (or absence thereof) is not materially misleading; `TIER-A` = outright-wrong comment; `TIER-B` = stale/incomplete comment with material omission; `TIER-C` = missing JSDoc (counted only, per D-225-04 not a finding).

| # | route file:line | METHOD | full path | comment presence | Tier verdict | finding stub (if any) |
| --- | --- | --- | --- | --- | --- | --- |
|  1 | `database/src/api/routes/game.ts:81`          | GET | `/game/state`                               | NONE   | TIER-C (no JSDoc)            | — |
|  2 | `database/src/api/routes/game.ts:145`         | GET | `/game/jackpot/:level`                      | inline | TIER-C (no JSDoc); inline PASS | — |
|  3 | `database/src/api/routes/game.ts:214`         | GET | `/game/jackpot/:level/overview`             | inline | TIER-C (no JSDoc); inline PASS | — |
|  4 | `database/src/api/routes/game.ts:364`         | GET | `/game/jackpot/:level/player/:addr`         | inline | TIER-C (no JSDoc); inline PASS | — |
|  5 | `database/src/api/routes/game.ts:737`         | GET | `/game/jackpot/day/:day/winners`            | inline | TIER-C (no JSDoc); inline PASS | — |
|  6 | `database/src/api/routes/game.ts:923`         | GET | `/game/jackpot/day/:day/roll1`              | inline | TIER-C (no JSDoc); TIER-B on inline block | F-28-225-02 |
|  7 | `database/src/api/routes/game.ts:1037`        | GET | `/game/jackpot/day/:day/roll2`              | inline | TIER-C (no JSDoc); TIER-B on inline block | F-28-225-03 |
|  8 | `database/src/api/routes/game.ts:1214`        | GET | `/game/jackpot/latest-day`                  | inline | TIER-C (no JSDoc); inline PASS | — |
|  9 | `database/src/api/routes/game.ts:1239`        | GET | `/game/jackpot/earliest-day`                | inline | TIER-C (no JSDoc); TIER-A on inline block | F-28-225-01 |
| 10 | `database/src/api/routes/health.ts:13`        | GET | `/health`                                   | NONE   | TIER-C (no JSDoc)            | — |
| 11 | `database/src/api/routes/history.ts:32`       | GET | `/history/jackpots`                         | NONE   | TIER-C (no JSDoc)            | — |
| 12 | `database/src/api/routes/history.ts:85`       | GET | `/history/levels`                           | NONE   | TIER-C (no JSDoc)            | — |
| 13 | `database/src/api/routes/history.ts:129`      | GET | `/history/player/:address`                  | NONE   | TIER-C (no JSDoc)            | — |
| 14 | `database/src/api/routes/leaderboards.ts:13`  | GET | `/leaderboards/coinflip`                    | NONE   | TIER-C (no JSDoc)            | — |
| 15 | `database/src/api/routes/leaderboards.ts:39`  | GET | `/leaderboards/affiliate`                   | NONE   | TIER-C (no JSDoc)            | — |
| 16 | `database/src/api/routes/leaderboards.ts:65`  | GET | `/leaderboards/baf`                         | NONE   | TIER-C (no JSDoc)            | — |
| 17 | `database/src/api/routes/player.ts:17`        | GET | `/player/:address`                          | inline | TIER-C (no JSDoc); inline PASS | — |
| 18 | `database/src/api/routes/player.ts:225`       | GET | `/player/:address/jackpot-history`          | NONE   | TIER-C (no JSDoc)            | — |
| 19 | `database/src/api/routes/replay.ts:72`        | GET | `/replay/day/:day`                          | JSDoc  | TIER-B                       | F-28-225-04 |
| 20 | `database/src/api/routes/replay.ts:184`       | GET | `/replay/tickets/:level`                    | JSDoc  | PASS                         | — |
| 21 | `database/src/api/routes/replay.ts:215`       | GET | `/replay/rng`                               | JSDoc  | PASS                         | — |
| 22 | `database/src/api/routes/replay.ts:236`       | GET | `/replay/players`                           | JSDoc  | PASS                         | — |
| 23 | `database/src/api/routes/replay.ts:254`       | GET | `/replay/distributions/:level`              | JSDoc  | PASS                         | — |
| 24 | `database/src/api/routes/replay.ts:325`       | GET | `/replay/player-traits/:address`            | JSDoc  | PASS                         | — |
| 25 | `database/src/api/routes/tokens.ts:8`         | GET | `/tokens/analytics`                         | inline | TIER-C (no JSDoc); inline PASS | — |
| 26 | `database/src/api/routes/viewer.ts:167`       | GET | `/viewer/player/:address/days`              | JSDoc  | PASS                         | — |
| 27 | `database/src/api/routes/viewer.ts:318`       | GET | `/viewer/player/:address/day/:day`          | JSDoc  | PASS                         | — |

**Per-file count reconciliation:** `game.ts = 9` (rows 1–9), `health.ts = 1` (row 10), `history.ts = 3` (rows 11–13), `leaderboards.ts = 3` (rows 14–16), `player.ts = 2` (rows 17–18), `replay.ts = 6` (rows 19–24), `tokens.ts = 1` (row 25), `viewer.ts = 2` (rows 26–27). Total = 27, matching `224-01-API-ROUTE-MAP.md` Pass 2 locked count.

**Line-number provenance note.** Some rows in `224-01-API-ROUTE-MAP.md` Pass 2 cite the *comment-block-start* line rather than the `fastify.get(...)` registration line (e.g. row 5 of Pass 2 cites `game.ts:716` for the winners endpoint where the actual registration is at `game.ts:737`). This catalog cites the `fastify.<method>(...)` registration line for every row — the grep anchor used by every downstream reviewer. The locked 27-row ordering is preserved; only the line column is made precise.

---

## Tier A findings

Findings where the comment makes a factual claim the code contradicts.

### F-28-225-01 — `/game/jackpot/earliest-day` comment claims "any distributions" but code excludes `dgnrs`

- **Severity:** INFO (no type mismatch, no required-param miss, no documented-but-unemitted field — stays INFO per 225-CONTEXT.md severity rules)
- **Direction:** comment->code
- **Phase:** 225 (API-03 handler comment audit)
- **File:line:** `/home/zak/Dev/PurgeGame/database/src/api/routes/game.ts:1236` (comment block `:1235-1238`; registration `:1239`)
- **Tier:** A
- **Quoted comment (lines 1235-1238):**
  > ```
  > // GET /game/jackpot/earliest-day
  > // Returns the lowest day that has any jackpot distributions.
  > // Used by the scrubber to set its lower bound — daily_rng starts at day 2 and
  > // not every day has distributions, so hardcoding minDay=1 always shows an empty day.
  > ```
- **Actual behavior:** The SQL in the handler body (`/home/zak/Dev/PurgeGame/database/src/api/routes/game.ts:1244-1256`) computes `SELECT MIN(day) FROM daily_rng WHERE EXISTS (SELECT 1 FROM jackpot_distributions jd WHERE jd."blockNumber" >= daily_rng."blockNumber" AND jd."blockNumber" < COALESCE(...) AND jd."awardType" <> 'dgnrs')`. The explicit `jd."awardType" <> 'dgnrs'` predicate at line 1254 excludes `dgnrs`-type distributions from the "has any distributions" existence check. A day whose only distributions are `dgnrs` is therefore *not* returned as earliest, contradicting the comment's "any jackpot distributions" claim. The sibling handler `/game/jackpot/latest-day` at `:1239` ... sorry, at `:1214`, registration `:1219-1229`, has *no* such filter — it accepts every awardType — so the asymmetry is latent only in `earliest-day`, not in both.
- **Caller impact:** The UI scrubber consumer (documented on line 1237: "Used by the scrubber to set its lower bound") would position its lower bound above a day whose distributions are all `dgnrs`, silently skipping it. A caller relying on the comment alone would incorrectly conclude that `dgnrs`-only days are included, leading to off-by-one lower-bound bugs in the scrubber whenever such a day exists.
- **Suggested resolution (Phase 229):** **RESOLVED-DOC** — update the comment to "Returns the lowest day that has any jackpot distributions excluding `dgnrs` awards" (aligns comment with code); asymmetry with `latest-day` (which does include `dgnrs`) should also be noted in the doc or reconciled in code. The `RESOLVED-CODE` alternative (drop the `<> 'dgnrs'` filter so earliest-day matches latest-day) is available if the scrubber intent is "any data at all"; D-225-02 default direction is comment→code so default is to fix the comment.

---

## Tier B findings

Findings where the comment documents some behavior but materially omits a side effect, branch, or post-condition.

### F-28-225-02 — `/game/jackpot/day/:day/roll1` comment omits the 404 branch on empty-day

- **Severity:** INFO (no Zod type mismatch, no required-param drift, no documented-but-unemitted response field — stays INFO)
- **Direction:** comment->code
- **Phase:** 225 (API-03 handler comment audit)
- **File:line:** `/home/zak/Dev/PurgeGame/database/src/api/routes/game.ts:920` (comment block `:920-922`; registration `:923`)
- **Tier:** B
- **Quoted comment (lines 920-922):**
  > ```
  > // GET /game/jackpot/day/:day/roll1
  > // Returns every Roll 1 payout for the given day: main-daily tickets, ETH, whale_pass, dgnrs.
  > // Excludes early-bird lootbox tickets (level >= sourceLevel) and all Roll 2 award types.
  > ```
- **Actual behavior:** The handler body at `/home/zak/Dev/PurgeGame/database/src/api/routes/game.ts:1007-1009` returns `reply.notFound("No roll1 distributions for day {day}")` when the roll1 query yields zero rows. The Fastify registration at `:923-927` only declares `response: { 200: rollResponseSchema }` — the `404` branch is neither in the schema nor mentioned in the comment. A caller reading the comment expects "returns every Roll 1 payout" (with an empty-array fallback on a day that has no Roll 1 payouts), but instead receives HTTP 404 — a code path the caller may handle differently (e.g. treat as "day not found" rather than "no Roll 1 this day").
- **Caller impact:** The UI would need to distinguish "404 because day is invalid" vs "404 because day exists but has no Roll 1 payouts" — the comment provides no guidance, so callers relying on the comment will either crash on the unexpected 404 or misclassify empty-data days as invalid-day errors.
- **Suggested resolution (Phase 229):** **RESOLVED-DOC** — update the comment to note "returns 404 when the day has no Roll 1 distributions" and, for full documentation hygiene, also add `404: errorResponseSchema` to the Fastify response registration (parallel to the pattern already used by `/player/:address` at `routes/player.ts:22` and `/viewer/player/:address/days` at `routes/viewer.ts:172`). The latter is a Phase 225 Plan 02 (API-04) / Plan 03 (API-05) concern; the comment update is the minimal fix for API-03.

### F-28-225-03 — `/game/jackpot/day/:day/roll2` comment omits the 404 branch on empty-day

- **Severity:** INFO (no type mismatch, no required-param drift, no documented-but-unemitted field — stays INFO)
- **Direction:** comment->code
- **Phase:** 225 (API-03 handler comment audit)
- **File:line:** `/home/zak/Dev/PurgeGame/database/src/api/routes/game.ts:1034` (comment block `:1034-1036`; registration `:1037`)
- **Tier:** B
- **Quoted comment (lines 1034-1036):**
  > ```
  > // GET /game/jackpot/day/:day/roll2
  > // Returns every Roll 2 bonus payout for the day: carryover tickets, near-future BURNIE,
  > // far-future BURNIE (center diamond).
  > ```
- **Actual behavior:** The handler body has *two* 404 return sites:
  - `/home/zak/Dev/PurgeGame/database/src/api/routes/game.ts:1141-1143` returns 404 when the raw SQL query yields zero rows;
  - `/home/zak/Dev/PurgeGame/database/src/api/routes/game.ts:1203-1205` returns 404 when the post-filter `wins` array is empty (after applying the JS-level `isBonusTrait` / `isFarFutureBurnie` / `isNearFutureBurnie` filters at `:1150-1199`).
  
  The Fastify registration at `:1037-1041` only declares `response: { 200: rollResponseSchema }`. Like F-28-225-02, the 404 branch is in neither the schema nor the comment. Moreover, the post-filter 404 path (`:1203-1205`) is especially subtle: the DB may return rows, but after bonusTraits filtering the response can still be empty → 404. A caller relying solely on the comment ("returns every Roll 2 bonus payout") has no cue for either branch.
- **Caller impact:** As with F-28-225-02, the caller must handle an undocumented 404. Additionally, the post-filter 404 at `:1203` is caller-impactful because the filter depends on whether `daily_winning_traits.bonusTraitsPacked` exists for the day — so the same day may 404 or return 200 depending on indexer state. The comment gives the caller no basis to diagnose this.
- **Suggested resolution (Phase 229):** **RESOLVED-DOC** — update the comment to document both 404 paths ("returns 404 when no Roll 2 distributions exist in the raw query *or* when all rows are filtered out by the bonusTraits predicate"). As with F-28-225-02, adding `404: errorResponseSchema` to the response registration is the API-04/API-05 counterpart fix and is out of scope for this plan.

### F-28-225-04 — `/replay/day/:day` JSDoc omits the winning-trait-and-transaction filter applied to distributions

- **Severity:** INFO (no Zod type mismatch, no required-param drift, no documented-but-unemitted response field — stays INFO)
- **Direction:** comment->code
- **Phase:** 225 (API-03 handler comment audit)
- **File:line:** `/home/zak/Dev/PurgeGame/database/src/api/routes/replay.ts:69` (JSDoc block `:69-71`; registration `:72`)
- **Tier:** B
- **Quoted comment (lines 69-71):**
  > ```
  > /**
  >  * GET /replay/day/:day — RNG word + jackpot distributions for a specific game day.
  >  */
  > ```
- **Actual behavior:** The handler body fetches *all* jackpot_distributions in the day's block range (`/home/zak/Dev/PurgeGame/database/src/api/routes/replay.ts:123-137`) and then applies a non-trivial filter at `:139-161`: only ETH distributions whose `traitId` is in the day's four winning trait IDs are kept; `tickets` and `burnie` are kept entirely; `dgnrs`/`whale_pass` (null `traitId`) are kept *only if* their `transactionHash` matches one of the ETH-winning-trait transactions. The filter's purpose is documented inline (lines 90-92 and 139-146) because "a single advanceGame tx can process multiple jackpot days", but the JSDoc itself — the summary a caller typically reads — makes no mention of the filter.
- **Caller impact:** A caller expecting the `distributions` response field to reflect every distribution whose block falls in the day's RNG-bounded block range would be materially wrong: ETH rows for cross-day multi-call advanceGame transactions are silently excluded, and some `dgnrs`/`whale_pass` rows are excluded based on transaction grouping. The response schema (`dayDetailResponseSchema` at `replay.ts:15-30`) gives no hint either — it just lists a `distributions: z.array(...)` field. A replay-focused caller reconstructing day-level distribution totals from this endpoint would under-count without knowing the filter exists.
- **Suggested resolution (Phase 229):** **RESOLVED-DOC** — extend the JSDoc to describe the filter: "Distributions are filtered to today's winning-trait ETH wins plus all ticket/burnie rows plus non-trait bonus awards in the same transaction as a winning-trait ETH distribution. Cross-day rows in a multi-call advanceGame transaction are excluded unless they fall in the same-tx bonus group." The inline comment at `:139-146` already states this; the fix lifts that guidance into the handler's public JSDoc.

---

## Tier C summary (handlers with no JSDoc — not enumerated per D-225-04)

Per D-225-04 Tier C is *not* flagged per-handler. Count is reported as context only.

**Tier C count: 19 / 27 handlers have no JSDoc block above the `fastify.<method>(...)` registration.**

Breakdown for context (no individual finding IDs):

- `game.ts:81 /game/state` — no comments whatsoever (row 1)
- `game.ts:145 /game/jackpot/:level` — inline only (row 2)
- `game.ts:214 /game/jackpot/:level/overview` — inline only (row 3)
- `game.ts:364 /game/jackpot/:level/player/:addr` — inline only (row 4)
- `game.ts:737 /game/jackpot/day/:day/winners` — inline only (row 5)
- `game.ts:923 /game/jackpot/day/:day/roll1` — inline only (row 6; Tier B flagged separately as F-28-225-02)
- `game.ts:1037 /game/jackpot/day/:day/roll2` — inline only (row 7; Tier B flagged separately as F-28-225-03)
- `game.ts:1214 /game/jackpot/latest-day` — inline only (row 8)
- `game.ts:1239 /game/jackpot/earliest-day` — inline only (row 9; Tier A flagged separately as F-28-225-01)
- `health.ts:13 /health` — no comments (row 10)
- `history.ts:32 /history/jackpots` — no handler-level comments (row 11)
- `history.ts:85 /history/levels` — no handler-level comments (row 12)
- `history.ts:129 /history/player/:address` — no handler-level comments (row 13)
- `leaderboards.ts:13 /leaderboards/coinflip` — no comments (row 14)
- `leaderboards.ts:39 /leaderboards/affiliate` — no comments (row 15)
- `leaderboards.ts:65 /leaderboards/baf` — no comments (row 16)
- `player.ts:17 /player/:address` — inline section-marker comments only, no JSDoc (row 17)
- `player.ts:225 /player/:address/jackpot-history` — no comments (row 18)
- `tokens.ts:8 /tokens/analytics` — inline "Get all token supplies" / "Get vault state" / "Get holder counts" only, no JSDoc (row 25)

Handlers **with** JSDoc (context; Tier-A/Tier-B evaluated against JSDoc content): 8 / 27. These are rows 19–24 (all six `replay.ts` handlers) and rows 26–27 (both `viewer.ts` handlers). Of the 8, one (row 19, `/replay/day/:day`) is a Tier B finding (F-28-225-04); the other 7 are PASS.

Tier D (cosmetic/typos): **not counted, not flagged** — per D-225-04.

---

## Summary

### Handler coverage

Total handlers audited: **27 / 27** — matches `224-01-API-ROUTE-MAP.md` Pass 2 locked count. Per-file audit coverage (one row per locked handler):

- `game.ts`: **9 / 9** (rows 1–9 of the per-handler verdict table)
- `health.ts`: **1 / 1** (row 10)
- `history.ts`: **3 / 3** (rows 11–13)
- `leaderboards.ts`: **3 / 3** (rows 14–16)
- `player.ts`: **2 / 2** (rows 17–18)
- `replay.ts`: **6 / 6** (rows 19–24)
- `tokens.ts`: **1 / 1** (row 25)
- `viewer.ts`: **2 / 2** (rows 26–27)

Sum = 9 + 1 + 3 + 3 + 2 + 6 + 1 + 2 = **27**. Per-file-sum reconciles exactly with the plan's truth #1 locked enumeration and with the 224-01 Pass 2 row count.

### Tier counts

| Tier | Count | Notes |
| --- | --- | --- |
| A (outright wrong) | **1** | F-28-225-01 on `game.ts:1239` `/game/jackpot/earliest-day` |
| B (stale/incomplete, material) | **3** | F-28-225-02 on `game.ts:923` `/roll1`; F-28-225-03 on `game.ts:1037` `/roll2`; F-28-225-04 on `replay.ts:72` `/replay/day/:day` |
| C (missing JSDoc — counted as context only, per D-225-04 not enumerated) | **19** | 19 / 27 handlers have no `/** */` block above the registration |
| D (cosmetic/typos) | **not counted** | Per D-225-04 Tier D is not flagged anywhere |

Invariant check: `A + B + C = 1 + 3 + 19 = 23 ≤ 27`, satisfying the plan's `N + M + P ≤ 27` truth. Remaining `27 − 23 = 4` handlers (rows 20–24 minus row 19, plus rows 26–27) are PASS with JSDoc that neither triggers Tier A/B nor counts as Tier C (because JSDoc is present). Total F-28-225-NN stubs emitted by this plan: **4** (`F-28-225-01` through `F-28-225-04` inclusive).

### Severity distribution

| Severity | Count | Finding IDs |
| --- | --- | --- |
| INFO | 4 | F-28-225-01, F-28-225-02, F-28-225-03, F-28-225-04 |
| LOW  | 0 | — (no promotions; see rationale below) |

**LOW promotion rationale (per-finding).** Each of the four findings was evaluated against the three caller-breaking criteria in 225-CONTEXT.md "Severity scheme":

- **F-28-225-01** (earliest-day comment): not a Zod `string`/actual-`number` mismatch (criterion 1 fail); not a request-parameter optionality drift (criterion 2 fail); the `dgnrs` filter does not cause a documented response field to be missing (criterion 3 fail). Stays **INFO**.
- **F-28-225-02** (roll1 comment omits 404): undeclared 404 is a response-code issue, not a response-field-type mismatch (criterion 1 fail); no request parameter involved (criterion 2 fail); no documented response field is missing — the 200 response shape is fully emitted when 200 returns (criterion 3 fail). Stays **INFO**. Note: the missing `404:` entry in the Fastify response-schema registration is an API-04/API-05 concern to be picked up by Plans 225-02/03; for API-03, only the comment-vs-code drift is in scope.
- **F-28-225-03** (roll2 comment omits 404): same reasoning as F-28-225-02 — additional post-filter 404 does not elevate to LOW because it's still a status-code/comment-drift issue, not a type mismatch or missing-field crash. Stays **INFO**.
- **F-28-225-04** (replay/day JSDoc omits filter): the filter affects *which rows appear in the distributions array*, not the *type* of any field (criterion 1 fail); no request parameter drift (criterion 2 fail); no documented field is missing — every field in `dayDetailResponseSchema` is emitted, even if the array contains fewer rows (criterion 3 fail). Stays **INFO**.

Do not promote beyond LOW — 225-CONTEXT.md explicitly bars that ("documentation drift is not vulnerability").

### Scope exclusion reconfirmation

`src/handlers/*.ts` is **NOT** audited in this plan; it is deferred to **Phase 227 IDX-03** per D-225-01. No file under `/home/zak/Dev/PurgeGame/database/src/handlers/` appears in the per-handler verdict table, in any finding stub's `File:line` field, or as a reference anywhere else in this catalog — the directory is mentioned exclusively in this scope-exclusion note and in the Phase boundary reminder below.

### Extrapolation note

Per the plan's acceptance criteria: if Tier A = 0 *and* Tier B = 0 across all 27 handlers, a "27/27 handlers pass; API-03 satisfied" extrapolation statement would apply. In this plan Tier A = 1 and Tier B = 3, so **extrapolation does not apply**. Every flagged finding is enumerated individually above as an `F-28-225-NN` stub; each represents a concrete, located, comment-vs-code drift in `src/api/routes/*.ts`. API-03 satisfaction for the HTTP handler surface is conditional on the four findings being resolved (RESOLVED-DOC in each case per D-225-02 default direction) in Phase 229.

### Finding-ID range consumed by this plan

**`F-28-225-01` through `F-28-225-04` (inclusive).** Plans 225-02 and 225-03 continue the sequential allocation from `F-28-225-05`.

---

## Phase boundary reminder

- **Phase 225 scope (this plan):** HTTP handler JSDoc / inline-comment audit for the 8 files under `/home/zak/Dev/PurgeGame/database/src/api/routes/` only.
- **Phase 227 IDX-03 scope (future):** The 27 files under `/home/zak/Dev/PurgeGame/database/src/handlers/` (indexer event handlers dispatched by `src/indexer/event-processor.ts`, consuming `ctx.args`). Comment audit for that directory is explicitly deferred per D-225-01.
- **Phase 225 Plans 02 / 03 (sibling waves, shared F-28-225-NN pool):** Plan 225-02 audits response-shape (API-04; Zod vs openapi.yaml response schemas, 8 sampled endpoints per D-225-03). Plan 225-03 audits request-schema (API-05; 6 Zod schema files in `src/api/schemas/` vs openapi.yaml parameter and request-body definitions). Both plans continue the `F-28-225-NN` numbering from `F-28-225-05`.
