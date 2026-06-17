---
phase: 390-solvency-spine
plan: 01
subsystem: testing
tags: [audit, cross-model-council, gemini, codex, solvency-spine, claimablePool, sdgnrs-backing, byte-freeze]

# Dependency graph
requires:
  - phase: 388-foundation-subject-freeze-green-baseline
    provides: "byte-frozen subject a8b702a7, the FC-390-01..07 finding-candidate intake ledger + the inherited cross-refs FC-389-02/-08, FC-392-08, FC-393-02/-03"
  - phase: 389-packing-identity
    provides: "the proven NET-1 council-prompt + COUNCIL-NET capture shape to match; the FC-389-02/-08 narrowing-cast solvency-conservation half routed forward to 390"
provides:
  - "NET 1 (cross-model council) ON RECORD for the SOLVENCY-SPINE surface (SOLV-01..07 + FC-390-01..07 + the inherited cross-refs)"
  - "One neutral SOLVENCY council prompt charged against frozen a8b702a7"
  - "Raw gemini + codex output (2 files) + the solv.council.json manifest"
  - "390-01-COUNCIL-NET.md capture record with byte-freeze attestation + the raw leads/divergences (the SOLV-07 whalePassCost cross-model divergence) for 390-02 to fold in"
affects: [390-02-adjudication, solvency-spine-verdict, both-nets-on-record-gate]

# Tech tracking
tech-stack:
  added: []
  patterns: ["dual-net audit: NET 1 council fan-out captured raw before the Claude net + adjudication (390-02)"]

key-files:
  created:
    - .planning/phases/390-solvency-spine/390-01-COUNCIL-PROMPT-SOLV.md
    - .planning/phases/390-solvency-spine/council/solv.gemini.txt
    - .planning/phases/390-solvency-spine/council/solv.codex.txt
    - .planning/phases/390-solvency-spine/council/solv.council.json
    - .planning/phases/390-solvency-spine/390-01-COUNCIL-NET.md
  modified: []

key-decisions:
  - "Ran ONE council slice (solv) = ONE fan-out (gemini + codex parallel internally) per the single-invocation pacing rule"
  - "Captured raw council output verbatim without adjudication — adjudication is 390-02's job"
  - "Routed the cross-model SOLV-07 divergence (gemini HIGH whalePassCost double-credit lead vs codex VERIFIED SOUND) + the codex decimator pre-reservation INFO caveat forward as RAW leads for 390-02 (not adjudicated here)"

patterns-established:
  - "Pattern: a no-finding sweep verdict requires BOTH nets on record; NET 1 council captured first, RAW, then 390-02 folds it against the Claude net"

requirements-completed: [SOLV-01, SOLV-02, SOLV-03, SOLV-04, SOLV-05, SOLV-06, SOLV-07]

# Metrics
duration: 8min
completed: 2026-06-15
---

# Phase 390 Plan 01: SOLVENCY-SPINE NET 1 (Cross-Model Council) Summary

**NET 1 (gemini + codex) on record for the SOLVENCY-SPINE surface (SOLV-01..07 + FC-390-01..07 + the inherited cross-refs) against byte-frozen `a8b702a7` — 0 CLIs skipped, the slice fanned, raw output captured, subject byte-frozen throughout; the one material cross-model divergence (a SOLV-07 whalePassCost double-credit lead) routed to 390-02.**

## Performance

- **Duration (this continuation, Task 2):** ~8 min (council fan-out ~7m12s + capture)
- **Started (continuation):** 2026-06-15T01:20Z
- **Completed:** 2026-06-15T01:30Z
- **Tasks:** 2 (Task 1 authored + committed in a prior session at `562c3abc`; Task 2 = this continuation)
- **Files created:** 5 (.planning/ only; no contract source touched)

## Accomplishments
- Authored the neutral SOLVENCY council prompt ("here is what we believe is safe about the redemption-rework + dust-forfeit + CEI + JackpotModule-fold solvency accounting — find where it breaks"), instructing the council to read the EXACT frozen source at `a8b702a7` via `git show`, stating BOTH master invariants (the GAME `balance + stETH >= claimablePool` / `claimablePool == Σ balancesPacked` identity AND the sDGNRS `ETH + stETH + claimableWinnings[SDGNRS] − pendingRedemptionEthValue` backing identity), carrying the threat-priority line (SPINE = solvency, with SOLV-06 elevated as the serious V62-03 CEI class), the KNOWN-BY-DESIGN exclusion list (dust-forfeit policy itself, claim/open timing, BURNIE off the ETH spine), and the per-finding output format. Covers all of SOLV-01..07 + FC-390-01..07 + the inherited cross-refs FC-389-02/-08, FC-392-08, FC-393-02/-03, with the three §6-prime targets (liveness-gate SOLV-05/FC-390-01, dust-forfeit SOLV-04/FC-390-02, CEI SOLV-06) charged HARD as dedicated numbered break-targets with the multi-tx interleavings spelled out. (Task 1, committed `562c3abc` in a prior session.)
- Ran `council.sh --label solv` (ONE fan-out, gemini + codex in parallel internally). Both `gemini` and `codex` were available — `skipped[]` empty — so both model outputs were captured.
- Both models returned substantive, source-traced output. **codex:** no reachable solvency-spine finding — VERIFIED SOUND across ALL of SOLV-01..07 + all FC leads + cross-refs, with `file:line` anchors. **gemini:** VERIFIED SOUND on SOLV-01..06 but surfaced ONE HIGH-severity SOLV-07 lead (a `whalePassCost` double-credit in `_processSoloBucketWinner` / `payDailyJackpot`'s final-day budget). This is a genuine cross-model divergence on SOLV-07 — captured RAW and routed to 390-02.
- Verified the subject byte-frozen after the fan-out (`git diff a8b702a7 -- contracts/` and `git status --porcelain contracts/` both empty) and recorded the attestation + "NET 1 ON RECORD" in 390-01-COUNCIL-NET.md.

## Task Commits

1. **Task 1: Author the neutral council prompt for the SOLVENCY slice** - `562c3abc` (docs; prior session)
2. **Task 2: Run the council fan-out and record the council-net capture** - `e2e9e042` (docs)

## Files Created/Modified
- `390-01-COUNCIL-PROMPT-SOLV.md` - Neutral SOLV-01..07 + FC-390-01..07 + cross-ref council prompt; three prime targets charged hard (301 lines) [Task 1, `562c3abc`]
- `council/solv.gemini.txt`, `council/solv.codex.txt` - Raw SOLVENCY-slice council output
- `council/solv.council.json` - Manifest (models [gemini, codex], skipped [])
- `council/solv.gemini.err`, `council/solv.codex.err` - Per-model stderr (both 0 bytes; both models exited 0)
- `390-01-COUNCIL-NET.md` - Capture record: available/skipped, raw output paths, per-model one-line characterizations, the raw leads/divergences for 390-02 (the SOLV-07 whalePassCost divergence + the decimator pre-reservation INFO caveat), and the byte-freeze attestation (131 lines)

## Decisions Made
- ONE slice = ONE council fan-out (gemini + codex run in parallel internally), satisfying the single-invocation pacing rule `[[pace-runs-to-survive-5h-cap]]`.
- Captured council output verbatim and did NOT adjudicate — per the plan, 390-02 (Claude net + adjudication) owns the verdict. The COUNCIL-NET record flags the SOLV-07 cross-model divergence as the PRIORITY 390-02 item and notes the line-cite discrepancy (gemini ~1284 vs the prompt @1247 vs codex @1265-1275 for `_processSoloBucketWinner`) so 390-02 pins the exact frozen lines first; it also notes gemini self-flagged the SOLV-07 claim as a research-stage lead (not finalized) and that whale-pass routing is a prize-pool obligation OUTSIDE the `claimablePool` identity → the skeptic dual-gate must run before any elevation.

## Deviations from Plan

None - plan executed exactly as written. Task 1 was already authored + committed in a prior session (`562c3abc`); this continuation executed Task 2 (the fan-out + capture). Both verification gates passed, no contract source touched, no auto-fix rules triggered.

## Council leads routed to 390-02 (RAW — for adjudication, not refuted here)
1. **SOLV-07 cross-model divergence (PRIORITY) — `whalePassCost` double-credit.** gemini asserts a final-day-budget double-count (`whalePassCost → futurePrizePool` in `_processSoloBucketWinner` AND re-added via `payDailyJackpot`'s `unpaidDailyEth = dailyEthBudget − paidDailyEth`, with a non-final-day under-debit of `currentPrizePool`); codex asserts the solo whale-pass split is single-counted (only ETH enters `claimableDelta`). 390-02 MUST re-read `_processSoloBucketWinner` + `payDailyJackpot`'s final-day arithmetic at `a8b702a7` (pin the exact lines — cites differ), trace whether `paidDailyEth` includes the whale-pass-cost share, then run the skeptic dual-gate (note: whale-pass value is a prize-pool obligation, NOT inside the `claimablePool` identity). CONFIRMED-at-source → gated USER-hand-review fix; refuted → both-nets-SOUND on SOLV-07.
2. **Decimator pre-reservation exception (codex caveat, INFO).** `claimablePool` may pre-reserve an unclaimed decimator pool before winners are credited (DegenerusGameStorage.sol:356-366) — a documented over-reservation (more backing held than owed), not an underbacked path. 390-02 confirms the Claude net agrees it is conservative-only and distinct from the SOLV-07 daily-jackpot fold.
3. All other SOLV-01..06 thesis points + ALL FC-390-01..07 + the inherited cross-refs returned VERIFIED SOUND by both models with source traces — 390-02 confirms against the Claude net for both-nets-on-record on those items.

## Issues Encountered
None. Both CLIs were available; the `council.sh` background run completed cleanly (exit 0), monitored to completion via the council.json sentinel (~7m12s wall clock).

## User Setup Required
None - no external service configuration required (the gemini/codex CLIs were already authenticated at `~/.local/bin`).

## Next Phase Readiness
- NET 1 is on record for the full SOLVENCY-SPINE surface. 390-02 (the Claude net + adjudication) can now fold the council leads in — chiefly the SOLV-07 `whalePassCost` cross-model divergence — before issuing any per-item verdict, and confirm both-nets-on-record before a no-finding verdict.
- Subject remains byte-frozen at `a8b702a7`; no blockers.

## Self-Check: PASSED

- All 5 created files verified present on disk.
- Both task commits (`562c3abc` Task 1, `e2e9e042` Task 2) verified in git log.
- `git diff a8b702a7 -- contracts/` empty (subject byte-frozen).

---
*Phase: 390-solvency-spine*
*Completed: 2026-06-15*
