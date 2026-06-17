---
phase: 394-legacy-debt
plan: 02
subsystem: audit / cross-model-council (v51 legacy-debt slice)
tags: [audit-only, council, net-1, legacy-debt, v51, claimBingo, bingo-module, pool-reward, freeze-safety]
requires:
  - 394-02-COUNCIL-PROMPT-V51.md (the neutral v51 council prompt)
  - council.sh + ask-gemini.sh + ask-codex.sh (the cross-model runner)
  - frozen subject a8b702a7 (read-only via git show)
provides:
  - "NET 1 (cross-model council) ON RECORD for the v51 legacy-debt slice (LEGACY-03 + LEGACY-04)"
  - "394-02-COUNCIL-NET.md — the raw council capture record + leads routed to 394-04 Wave-2 adjudication"
  - "council/v51.codex.txt — codex's full traced per-item audit (0 findings; all three break-targets VERIFIED SOUND)"
affects:
  - 394-04 (Wave-2 Claude net + v51 adjudication → audit/FINDINGS-v51.0.md) folds these leads in before any per-item verdict
  - 396 (terminal) carries a post-responsive gemini second-source re-run for this slice
tech-stack:
  added: []
  patterns: [cross-model-council-net-1, neutral-charged-prompt, byte-frozen-subject-read-only, single-model-on-record-with-skip-documented]
key-files:
  created:
    - .planning/phases/394-legacy-debt/394-02-COUNCIL-PROMPT-V51.md
    - .planning/phases/394-legacy-debt/394-02-COUNCIL-NET.md
    - .planning/phases/394-legacy-debt/council/v51.council.json
    - .planning/phases/394-legacy-debt/council/v51.codex.txt
    - .planning/phases/394-legacy-debt/council/v51.codex.err
    - .planning/phases/394-legacy-debt/council/v51.gemini.err
  modified: []
decisions:
  - "gemini non-responsive (no output within an 8-min hard cap on 2 successive runs) → recorded in skipped[]; codex (real traced audit) satisfies council-on-record with the skip documented; post-responsive gemini re-run flagged → 396"
  - "council.json constructed to match council.sh's exact manifest shape from the true on-disk state (codex available / gemini skipped) after the background council.sh tree was harness-killed mid-gemini-wait — no contract or subject mutation"
metrics:
  duration: ~2h (dominated by gemini non-response / 57-min hang + 8-min retry cap)
  completed: 2026-06-15
  tasks: 2
  files: 6
---

# Phase 394 Plan 02: v51 Legacy-Debt Council NET 1 Summary

NET 1 (the cross-model council) is on record for the full v51 legacy-debt slice — codex returned a fully-traced
per-item audit verifying `claimBingo`/BingoModule freeze-safety + 3-tier precedence + `(level,quadrant)` dedup
(LEGACY-03), the sDGNRS `Pool.Reward` rebalance split-conservation + no-over-draw (LEGACY-04a), and the
jackpot final-day backing-conservation (LEGACY-04b) all SOUND with 0 findings, while gemini was non-responsive
and is documented as a skip with a 396 second-source re-run flagged.

## What was done

**Task 1 — authored the neutral v51 council prompt** (`394-02-COUNCIL-PROMPT-V51.md`, 257 lines):
- Charged NEUTRALLY ("here is what we believe is true about the v51 surface — find where it breaks") against
  the byte-frozen subject `a8b702a7`, instructing the council to read the EXACT frozen source via
  `git show a8b702a7:contracts/<File>.sol`.
- Three dedicated numbered break-targets: (1) LEGACY-03 `claimBingo`/BingoModule — freeze-safe
  `traitBurnTicket` read (backward-trace to the commitment point) + tier-precedence suppression + `(level,
  quadrant)` dedup + empty-pool no-op + `gameOver` cutoff; (2) LEGACY-04a the `Pool.Reward` rebalance
  (AFFILIATE 3000 / REWARD 1000 bps) split-conservation + no-over-draw + no-stale-split-hardcode; (3)
  LEGACY-04b the jackpot final-day `Pool.Reward` deletion — no-strand / no-double-spend / no-ordering-hazard.
- Threat-priority line encoded (claimBingo freeze break DOMINANT / Pool.Reward conservation + final-day
  deletion SPINE / CEI-reentrancy confirmatory); KNOWN-BY-DESIGN exclusion list encoded (claimBingo
  no-level-guard by-design, RTP/WWXRP/whale-pass economics by-design, lootbox/claim timing not a player edge,
  genesis self-break a non-finding); per-finding output format (FINDING vs VERIFIED SOUND with the settling
  cite); no verdict pre-stated.
- All frozen line-cites re-verified at `a8b702a7` before authoring (BingoModule claimBingo body, StakedStonk
  BPS constants + seeding + transfer fns, AdvanceModule final-day affiliate draw, JackpotModule final-day
  bucket distribution, the Reward consumers) — several planning-note cites drifted by a few lines and the
  prompt flags the known drifts so the council pins the right code.

**Task 2 — ran the v51 council fan-out + recorded the capture** (`394-02-COUNCIL-NET.md` + `council/v51.*`):
- `council.sh --label v51` fanned the prompt to gemini+codex. **codex returned OK** with a substantive 19-line
  fully-traced per-item audit (`v51.codex.txt`, 0-byte clean `.err`). **gemini ran ~57 min without producing
  output** then the background `council.sh` tree was harness-killed before its `wait` completed; a second
  isolated gemini run under a hard 8-min cap also produced nothing (rc=124).
- Recorded gemini as `skipped[]` (non-responsive), removed the single empty `v51.gemini.txt`, wrote the
  non-response reason to `v51.gemini.err`, and constructed `v51.council.json` to byte-match council.sh's
  manifest shape from the true on-disk state (`models:["codex"]`, `skipped:["gemini"]`).
- Byte-freeze attested after the fan-out: `git diff a8b702a7 -- contracts/` empty; `git status --porcelain
  contracts/` empty; full tree shows only the pre-existing untracked `PLAYER-PURCHASE-REWARDS.html`. The
  council wrote only to its out-dir.

## Council outcome (RAW — adjudication is 394-04)

**codex: LEGACY-03 / LEGACY-04a / LEGACY-04b all VERIFIED SOUND — 0 findings**, with `file:line` cites at
`a8b702a7`. Notable refinement on LEGACY-04b: **codex found NO sDGNRS `Pool.Reward` final-day deletion/draw
path at all** — the jackpot final-day code mutates only ETH prize-pool state (`currentPrizePool` /
`claimablePool` / `prizePoolsPacked`), not `poolBalances[Pool.Reward]`; `Pool.Reward` appears only in seeding +
Bingo + Degenerette + the coinflip bounty. codex also flagged a **stale comment** at `JackpotModule:1047`
("solo bucket gets DGNRS on final day") that the frozen code does not implement.

These are RAW leads routed to 394-04 for the independent Claude net + the skeptic dual-gate vs the frozen
source before any per-item verdict and the deferred `audit/FINDINGS-v51.0.md`.

## Deviations from Plan

**Auto-handled (Rule 3 — blocking issue worked around without contract/subject mutation):**

**1. [Rule 3 - Blocking] gemini non-responsive → recorded as skip; council.json built deterministically**
- **Found during:** Task 2 (the council fan-out)
- **Issue:** gemini (`gemini-3-pro-preview`) produced no output within ~57 min, then the background
  `council.sh` process tree was killed by the orchestration harness before its internal `wait` completed, so
  `council.sh` never reached its manifest-build step and `v51.council.json` was not written by the script. A
  second isolated gemini run under a hard 8-min cap also produced nothing (rc=124, timeout). The plan
  explicitly anticipates a skipped CLI (codex was expected to skip under a cap; here the roles inverted —
  codex returned, gemini did not).
- **Fix:** Removed the single specific empty `v51.gemini.txt` (NOT a blanket clean), recorded the gemini
  non-response reason in `v51.gemini.err`, and constructed `v51.council.json` to match council.sh's exact
  manifest shape from the true on-disk state (`models:["codex"]`, `skipped:["gemini"]`) — council.sh
  re-derives availability from the non-empty `.txt` files, so this manifest is byte-shape-identical to what
  the script would have emitted given the same files. No re-invocation of the already-completed codex.
- **Files modified:** `council/v51.gemini.err` (skip reason), `council/v51.council.json` (manifest)
- **Commit:** `20608579`
- **Why this is in-spec, not a failure:** the plan's both-unavailable rule (and the 393-01 precedent) makes a
  single available council model with the skip documented satisfy "council on record"; codex IS on record with
  a real traced audit, and the gemini second-source is flagged → 396. The dual-NET is satisfied by codex +
  the Wave-2 Claude net (394-04).

No other deviations. No contract source touched; the subject is byte-frozen throughout.

## Auth gates

None.

## Known Stubs

None — this is an audit-only capture plan; no code/data wiring.

## Verification

- The council prompt exists, is neutral, charged against `a8b702a7`, covers LEGACY-03 + LEGACY-04 with the
  three break-targets, the threat-priority line, and the by-design exclusions — automated grep verify passed
  (257 lines).
- `council.sh` ran for `--label v51`; `v51.council.json` exists; codex `.txt` non-empty; gemini in `skipped[]`.
- `394-02-COUNCIL-NET.md` records the available/skipped + raw output paths + the byte-freeze attestation + an
  explicit "NET 1 ON RECORD" line + the post-responsive gemini re-run flag → 396 — automated verify passed
  (242 lines).
- `git diff a8b702a7 -- contracts/` empty; `git status --porcelain contracts/` empty.

## Self-Check: PASSED

- Created files: `394-02-COUNCIL-PROMPT-V51.md`, `394-02-COUNCIL-NET.md`, `council/v51.council.json`,
  `council/v51.codex.txt`, `council/v51.codex.err`, `council/v51.gemini.err` — all FOUND on disk.
- Commits: `2ed86cce` (Task 1 prompt), `20608579` (Task 2 capture + outputs) — both FOUND in git log.
- Subject byte-frozen: `git diff a8b702a7 -- contracts/` EMPTY.
