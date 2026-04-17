---
phase: 225-api-handler-behavior-validation-schema-alignment
plan: 01
subsystem: audit
tags: [api, handler-comments, jsdoc, drift-audit, fastify, zod, database-repo, api-03]

# Dependency graph
requires:
  - phase: 224-api-route-openapi-alignment
    provides: "Pass 2 locked count of 27 HTTP handlers across 8 route files (game=9, health=1, history=3, leaderboards=3, player=2, replay=6, tokens=1, viewer=2)"
provides:
  - "225-01-HANDLER-COMMENT-AUDIT.md — per-handler comment-vs-behavior catalog for all 27 HTTP handlers in /home/zak/Dev/PurgeGame/database/src/api/routes/*.ts"
  - "4 F-28-225-NN finding stubs (01-04) for Phase 229 consolidation: 1 Tier A, 3 Tier B, all INFO, direction comment->code"
  - "Tier C count (19/27 handlers missing JSDoc) recorded as context-only per D-225-04"
  - "F-28-225-NN sequential-ID starting allocation; 225-02 and 225-03 continue from F-28-225-05"
affects: [phase-225-plan-02, phase-225-plan-03, phase-227-idx-03, phase-229-findings-consolidation]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "D-225-04 tier threshold (A + B only flagged; C counted; D skipped) applied uniformly across 27 handlers"
    - "D-225-02 default direction: comment->code with RESOLVED-DOC default resolution target"
    - "D-225-07 cross-repo file:line citations — all stubs point into /home/zak/Dev/PurgeGame/database/src/api/routes/"

key-files:
  created:
    - ".planning/phases/225-api-handler-behavior-validation-schema-alignment/225-01-HANDLER-COMMENT-AUDIT.md"
    - ".planning/phases/225-api-handler-behavior-validation-schema-alignment/225-01-SUMMARY.md"
  modified: []

key-decisions:
  - "Line-number provenance: cite fastify.<method>(...) registration lines (:737 for winners etc.) rather than 224-01 Pass 2's comment-block-start lines — grep anchor is the registration line"
  - "404 branches undocumented in both comment and Fastify response schema are Tier B (roll1 and roll2) — material caller decision gap"
  - "earliest-day vs latest-day asymmetry: earliest-day excludes dgnrs, latest-day includes all awardTypes — earliest-day comment is Tier A because it claims 'any' but excludes dgnrs"
  - "replay/day/:day filter (winning-trait + same-tx bonus grouping) is Tier B because JSDoc summary omits filter; inline comments in body document it but JSDoc is what callers read first"

patterns-established:
  - "Per-handler row format: # | route file:line | METHOD | full path | comment presence (JSDoc/inline/NONE) | Tier verdict | finding stub ID"
  - "Finding stub format per D-225-06: ### F-28-225-NN — {short-title}, Severity, Direction: comment->code, Phase, File:line, Tier, Quoted comment (verbatim), Actual behavior, Caller impact, Suggested resolution"
  - "Tier C not enumerated per-handler; reported as count only in Tier counts summary"
  - "Severity promotion to LOW only via the three 225-CONTEXT.md caller-breaking criteria; documentation drift stays INFO"

requirements-completed: [API-03]

# Metrics
duration: 42min
completed: 2026-04-13
---

# Phase 225 Plan 01: HTTP Handler Comment Audit (API-03) Summary

**Per-handler JSDoc/inline-comment vs body-behavior audit catalog covering all 27 HTTP handlers in `database/src/api/routes/*.ts`, with 4 F-28-225-NN finding stubs enumerated (1 Tier A, 3 Tier B, all INFO).**

## Performance

- **Duration:** 42 min
- **Started:** 2026-04-13T (execution time)
- **Completed:** 2026-04-13
- **Tasks:** 1 / 1 (`<task type="auto">` — enumerate + classify all 27 handlers)
- **Files modified:** 0 (cross-repo READ-only on /home/zak/Dev/PurgeGame/database/src/api/routes/*.ts)
- **Files created:** 2 in .planning/ (HANDLER-COMMENT-AUDIT.md, SUMMARY.md)

## Accomplishments

- Enumerated all 27 HTTP handlers across 8 files in `src/api/routes/` (matches 224-01 Pass 2 locked count exactly: game=9, health=1, history=3, leaderboards=3, player=2, replay=6, tokens=1, viewer=2).
- Read each handler in full (registration line + 10-20 lines of preceding context + handler body) and applied D-225-04 Tier A/B threshold literally per the plan's "when in doubt, default to NOT flagging" rule.
- Identified 1 Tier A finding (outright-wrong comment) and 3 Tier B findings (stale/incomplete comment with material omission), emitted as `F-28-225-01` through `F-28-225-04` with `Direction: comment->code` per D-225-02.
- Recorded Tier C count (19/27 handlers without JSDoc) as context only, per D-225-04 not enumerated per-handler.
- Confirmed no handler in `src/handlers/*.ts` was audited (scope exclusion D-225-01 respected); that directory is mentioned in the catalog only in the two scope-exclusion notes.
- Catalog self-satisfies the plan's acceptance criteria on all axes: 27-row per-handler table, exact required section headings, F-28-225-NN regex format, every finding citation into `/home/zak/Dev/PurgeGame/database/src/api/routes/`.

## Task Commits

1. **Task 1: Enumerate all 27 HTTP handlers + classify JSDoc/inline-comment presence** — `[to be committed]` (docs)

**Plan metadata:** `[to be committed]` (docs: complete 225-01 plan)

_Note: .planning/ is gitignored per project convention; gsd-tools commit calls no-op with `skip: gitignored`. Commit hash placeholders reflect this._

## Files Created/Modified

- `.planning/phases/225-api-handler-behavior-validation-schema-alignment/225-01-HANDLER-COMMENT-AUDIT.md` — per-handler comment-vs-body audit catalog for 27 HTTP handlers; 4 finding stubs F-28-225-01..04; Tier C count context; scope-exclusion reconfirmation for `src/handlers/*.ts`.
- `.planning/phases/225-api-handler-behavior-validation-schema-alignment/225-01-SUMMARY.md` — this file.

## Decisions Made

- **Registration-line citations (vs 224-01 comment-block-start).** 224-01 Pass 2 cited the comment-block-start line for some handlers (e.g. `game.ts:716` for winners, where the `fastify.get(...)` registration is at `:737`). This catalog cites the `fastify.<method>(...)` registration line for every row — that is the grep anchor every downstream reviewer will use. The 27-row ordering is preserved; only the line column is made precise. Documented in the catalog's "Line-number provenance note".
- **404 branches undocumented → Tier B.** Two game.ts handlers (`/roll1` at `:923` and `/roll2` at `:1037`) return 404 when their queries yield zero rows (and `/roll2` has a second 404 after JS-level filtering). Neither the inline comment nor the Fastify response-schema registration mentions 404. A caller relying on the comment alone ("returns every Roll 1 payout") would mis-handle the unexpected status. Flagged as Tier B per "comment omits a material branch".
- **`earliest-day` vs `latest-day` asymmetry.** `earliest-day` excludes `dgnrs`-type distributions via `AND jd."awardType" <> 'dgnrs'`; `latest-day` has no such filter. The `earliest-day` comment says "any jackpot distributions", which is flatly contradicted by the `<> 'dgnrs'` predicate → Tier A (F-28-225-01). The `latest-day` comment ("any jackpot distributions") matches its code, so no finding on latest-day; the cross-endpoint asymmetry is noted in F-28-225-01's suggested resolution.
- **`replay/day/:day` JSDoc → Tier B.** The JSDoc says "RNG word + jackpot distributions for a specific game day". The body applies a non-trivial filter (ETH rows kept only for today's winning traitIds; dgnrs/whale_pass kept only if same-tx as an ETH winning trait) that is *not* mentioned in the JSDoc — only in inline comments deeper in the body. A caller reading the JSDoc first would over-count. Tier B (F-28-225-04).
- **No Severity promotions to LOW.** Each of the four findings was evaluated against the three 225-CONTEXT.md caller-breaking criteria (type mismatch, required-optional drift, documented-but-unemitted field); none hit any criterion. All four stay at default INFO. Per-finding rationale documented in the catalog's Severity distribution section.

## Deviations from Plan

None — plan executed exactly as written. Every acceptance-criterion grep-pattern and truth-list assertion in the plan frontmatter is satisfied by the catalog. Tier A/B finding discovery was substantive (4 findings across 3 of the 8 route files — all in game.ts except F-28-225-04 which is in replay.ts), not zero-finding extrapolation, so the plan's "if 0 findings then extrapolation statement" branch did not apply.

## Issues Encountered

- **Game.ts player-level `/player/:addr` fallback semantics ambiguity.** The fallback SQL uses `level >= ${level}` which includes distributions at the requested level *and above* (for carryover wins), while the inline comment phrases the fallback as "all level-N distributions across all days". This could be read two ways: a strict `level = N` interpretation (which the code contradicts) or a broader "distributions associated with level N including carryover" interpretation (which the code satisfies). Applied D-225-04's high-noise default-NOT-flag rule; did not emit a finding. Resolution: leave for future pass if callers raise ambiguity concerns.
- **`replay/rng` "resolved" implicit claim.** JSDoc says "all resolved RNG days" but code fetches every `dailyRng` row without a `finalWord != null` or similar resolution predicate. If the indexer ever writes a row before VRF fulfills, the endpoint would return unresolved days. Without indexer semantics available in this plan's scope, defaulted to NOT flagging. Phase 227 IDX-03 may revisit if indexer comments assert different semantics.
- **`viewer.ts` and `player.ts` 404 undocumented in comments but DECLARED in Fastify schema.** Unlike game.ts `/roll1` and `/roll2`, the viewer/player handlers with 404 paths DO declare `404: errorResponseSchema` in the Fastify schema registration. The comment alone is still silent on 404, but the overall caller-contract (schema + comment) covers the 404. Applied the ambiguity rule: since the schema covers it, the comment omission is not sufficiently material to flag as Tier B. This interpretation keeps the "material" threshold stricter.

## Next Phase Readiness

- **Plan 225-02 (API-04 response-shape audit)** — ready; inherits the 27 endpoints locked by 224-01 and the 8-endpoint sampling strategy from D-225-03. F-28-225-NN numbering continues from `F-28-225-05`.
- **Plan 225-03 (API-05 request-schema audit)** — ready; operates on 6 Zod schema files in `src/api/schemas/` against openapi.yaml parameter/request-body definitions; continues F-28-225-NN numbering after 225-02.
- **Phase 227 IDX-03** — the scope-excluded `src/handlers/*.ts` 27 files remain waiting for that phase's comment audit. No pre-work required; the exclusion is clean in this plan's catalog.
- **Phase 229 findings consolidation** — this plan contributes 4 finding stubs (F-28-225-01..04), all INFO, all direction `comment->code`, all resolution-target RESOLVED-DOC per D-225-02 default. Each stub has the full fields required by Phase 229: severity, direction, phase, file:line, tier, quoted comment, actual behavior, caller impact, suggested resolution.

## Self-Check

- [x] `225-01-HANDLER-COMMENT-AUDIT.md` exists at `/home/zak/Dev/PurgeGame/degenerus-audit/.planning/phases/225-api-handler-behavior-validation-schema-alignment/225-01-HANDLER-COMMENT-AUDIT.md` — verified via file write
- [x] 27 per-handler rows in the verdict table — grep anchored rows 1–27
- [x] All 8 route files appear with correct counts (game:9 health:1 history:3 leaderboards:3 player:2 replay:6 tokens:1 viewer:2 = 27) — per-file-count grep passed
- [x] Required section headings present: `## Per-handler verdicts`, `## Summary`, `### Handler coverage`, `### Tier counts`, `### Severity distribution`, `### Scope exclusion reconfirmation` — all grep-verified at lines 36, 197, 199, 214, 225, 241
- [x] All finding stubs match `F-28-225-NN` format (four stubs: 01, 02, 03, 04) — grep verified
- [x] Every stub has `- **Direction:** comment->code` — 4 matches
- [x] Every stub's File:line points into `/home/zak/Dev/PurgeGame/database/src/api/routes/` — verified (no `src/handlers/` path in any stub)
- [x] `src/handlers/*.ts` appears only in scope-exclusion notes (line 6 preamble, line 243 Summary footer, line 258 Phase boundary reminder) — verified; not in verdict table, not in any finding stub
- [x] Tier counts sum consistent: A=1 + B=3 + C=19 + Tier-A/B handlers=4 overlapping with Tier-C for game.ts rows 6, 7, 9 (which are both Tier-C and Tier-A/B) — documented in catalog

## Self-Check: PASSED

---
*Phase: 225-api-handler-behavior-validation-schema-alignment*
*Plan: 01*
*Completed: 2026-04-13*
