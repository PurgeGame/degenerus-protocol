---
phase: 370-spec-design-lock-anchor-re-attestation-vs-2b26ec91-cov-01-se
plan: 02
subsystem: testing
tags: [xmodel, cross-model, gemini, solvency, audit, area-solvency, cov-01, 2b26ec91]

# Dependency graph
requires:
  - phase: 370-01 (design-lock SPEC)
    provides: the SOLV-01 variant (a) lock + SOLV-02 confirm-only fix + the producer-before-consumer edit order this re-run dedups CONFIRMED claims against
provides:
  - "COV-01 closed — the v58.0 area-solvency cross-model coverage gap (the Gemini Plan-Mode refusal) is filled by a genuine second-model frozen-source read"
  - "Independent second-model (Gemini) corroboration of F-03 (BAF whale-pass remainder) and F-04 (decimator whale-pass remainder) against frozen 2b26ec91"
  - "Confirmation that net-new solvency findings for the Phase-371 IMPL diff = 0 (no new IMPL absorption; 370-01 edit order unchanged)"
  - "A TERMINAL carry-forward note for 374 audit/FINDINGS-v59.0.md (AUDIT-01)"
affects: [371-impl, 374-terminal, findings-v59.0, audit-01]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Materialize-frozen-source-into-a-context-FILE so a Plan-Mode (git-shell-disabled) model can read frozen <SHA> as a file — defeats the v58 Gemini Plan-Mode refusal without granting shell access"
    - "Second-independent-model rule: the model must differ from the v58 leg (Codex excluded) AND actually read frozen source (not refuse)"

key-files:
  created:
    - .planning/phases/370-spec-design-lock-anchor-re-attestation-vs-2b26ec91-cov-01-se/370-02-COV01-ADJUDICATION.md
    - .planning/audit-v52/runs/v59/xmodel/prompts/area-solvency.v59.txt
    - .planning/audit-v52/runs/v59/xmodel/context/frozen-solvency-source.txt
    - .planning/audit-v52/runs/v59/xmodel/results/area-solvency.gemini.txt
    - .planning/audit-v52/runs/v59/xmodel/results/area-solvency.council.json
  modified: []

key-decisions:
  - "Second model = Gemini (gemini-3-pro-preview), NOT the v58 Codex leg — satisfies 'second independent model on the spine'"
  - "Mechanism = materialize frozen 2b26ec91 solvency modules into a single context FILE read in Plan Mode (the robust fix for the v58 git-shell-disabled refusal cause)"
  - "Claim 3 (yield over-distribution) is a CONFIRMED downstream consequence of F-04, not a separate finding — resolved by the SOLV-02 fix already in scope"
  - "K = 0 net-new solvency findings — all CONFIRMED concerns corroborate the already-locked F-03/F-04; no new IMPL absorption into the 370-01 edit order"

patterns-established:
  - "Pattern: parallel-verify every external claim against AS-FOUND frozen source (git show <SHA>:<path>) — Claude owns the verdict; cite exact frozen line numbers"
  - "Pattern: corroboration of an already-in-scope finding strengthens the close but adds no IMPL work; record disposition as ALREADY IN SCOPE"

requirements-completed: [COV-01]

# Metrics
duration: ~25min
completed: 2026-06-04
---

# Phase 370 Plan 02: COV-01 Second-Model Area-Solvency Re-Run Summary

**Closed the v58.0 area-solvency coverage gap — a second independent model (Gemini) genuinely read frozen `2b26ec91` via a materialized source pack and independently re-produced F-03 + F-04 with zero net-new solvency findings.**

## Performance

- **Duration:** ~25 min
- **Started:** 2026-06-04T22:08Z (this work window)
- **Completed:** 2026-06-04T22:32Z
- **Tasks:** 2
- **Files modified:** 8 created (7 harness artifacts + the adjudication doc), 0 contracts

## Accomplishments
- **Closed COV-01.** The v58.0 `area-solvency` Gemini leg refused via Plan Mode (never read frozen source). This re-run drove a SECOND independent model (Gemini `gemini-3-pro-preview`, distinct from the v58 Codex leg) against frozen `2b26ec91` via a materialized solvency source pack read as a FILE in Plan Mode — a genuine frozen-source read, defeating the refusal cause (Plan Mode disables the `git` shell).
- **Independent corroboration of F-03 + F-04.** The second model independently re-produced both in-scope solvency-identity breaks: F-03 (BAF whale-pass remainder bumps `claimablePool` at `PayoutUtils:58` but is excluded from the BAF `memFuture -= claimed` debit at `AdvanceModule:902`) and F-04 (decimator whale-pass remainder re-credited via `_creditClaimable(winner, remainder)` at `DecimatorModule:596` with no paired `claimablePool +=` after the full-portion debit at `:398`).
- **Every claim adjudicated against frozen source.** All 3 model concerns + 1 attestation parallel-verified against AS-FOUND `2b26ec91` (Claude owns the verdict). Claim 3 (yield over-distribution) = CONFIRMED downstream consequence of F-04. Salvage-relabel / `pullRedemptionReserve` attestation = upheld (identity-preserving).
- **K = 0 net-new findings.** No new solvency finding to absorb into the Phase-371 IMPL diff — the 370-01 design-lock edit order is unchanged. A TERMINAL carry-forward note was written for 374 `audit/FINDINGS-v59.0.md`.

## Task Commits

Each task was committed atomically:

1. **Task 1: Run the area-solvency leg with a second independent model against `2b26ec91`** - `4f5c2658` (docs) — PONG smoke-test recorded, frozen solvency pack materialized, Gemini run persisted to `runs/v59/xmodel/results/`, adjudication doc opened with the run record.
2. **Task 2: Adjudicate every returned claim against frozen source + routing dispositions** - `ea217437` (docs) — per-claim verdicts (CONFIRMED / CONFIRMED-known / attestation-upheld), disposition summary, K=0 verdict line, TERMINAL carry-forward note.

## Files Created/Modified
- `370-02-COV01-ADJUDICATION.md` (267 lines) — the COV-01 run record + per-claim Claude adjudication + dispositions + the TERMINAL carry-forward note.
- `.planning/audit-v52/runs/v59/xmodel/prompts/area-solvency.v59.txt` — the v59 prompt (re-uses the v58 `_preamble.txt` + `solvency-focus.txt`, instructs the model to read the materialized pack as a FILE).
- `.planning/audit-v52/runs/v59/xmodel/context/frozen-solvency-source.txt` (8,125 lines) — every in-scope solvency module at frozen `2b26ec91`, line-numbered to match `git show`.
- `.planning/audit-v52/runs/v59/xmodel/results/area-solvency.gemini.txt` — the raw second-model result (a genuine read; opens `FROZEN SUBJECT — commit 2b26ec91`).
- `.planning/audit-v52/runs/v59/xmodel/results/area-solvency.council.json` — the run manifest (model, mechanism, smoke-test, Codex exclusion + reason).

## Decisions Made
- **Second model = Gemini, not Codex.** Codex was the v58 area-solvency leg (produced F-03); a genuine "second independent model on the spine" must differ → Codex excluded in the manifest.
- **Mechanism = materialize frozen source into a context FILE.** The v58 refusal cause was Plan Mode disabling the `git` shell while the prompt forbade the working tree. Materializing the frozen modules into a file the model reads with its file tool removes the need for a shell entirely — the robust fix.
- **Claim 3 = downstream of F-04, not a new finding.** `distributeYieldSurplus`'s obligations math is correct; it reads `claimablePool` as the liability anchor, so the F-04 under-report propagates into over-distribution. The F-04 (SOLV-02) fix closes it with no separate change.
- **K = 0.** The only solvency-identity breaks the second model found are exactly the already-locked F-03 (SOLV-01 variant (a)) and F-04 (SOLV-02). No cross-dependency on the 370-01 edit order beyond the already-mapped SOLV-01/SOLV-02 edits.

## Deviations from Plan

None - plan executed exactly as written. Tasks 1 and 2 were carried out per the plan's pacing
discipline (external leg concurrency 1, prompt in a FILE, read-only/plan mode, raw output persisted
to disk before adjudication). The external harness run (Task 1) had already been executed and
persisted in a prior work window; this session verified the on-disk result was a genuine
frozen-source read (not a Plan-Mode refusal), then completed the doc-record and the full
adjudication — exactly the resume-from-on-disk-output path the plan's pacing notes describe.

## Authentication Gates
None.

## Issues Encountered
None. The external leg was already on disk from a prior session; this is the intended resumable
pacing behavior (Task 2 resumes from the persisted raw output, losing nothing).

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- **371 IMPL:** the F-03/F-04 corrections it folds into the ONE batched diff are now backed by an independent second-model read on the solvency spine. K = 0 → no new IMPL work to absorb; the 370-01 SOLV-01 variant (a) + SOLV-02 edit order stands unchanged.
- **374 TERMINAL:** the COV-01 carry-forward note is ready for `audit/FINDINGS-v59.0.md` (AUDIT-01) to fold in.
- No blockers. ZERO `contracts/*.sol` touched.

## Self-Check: PASSED

All created files verified present on disk; both task commits (`4f5c2658`, `ea217437`) verified in
git history. ZERO `contracts/*.sol` modified (`git status --porcelain contracts/` empty).

---
*Phase: 370-spec-design-lock-anchor-re-attestation-vs-2b26ec91-cov-01-se*
*Completed: 2026-06-04*
