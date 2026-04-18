---
phase: 235-conservation-rng-commitment-re-proof-phase-transition
plan: 235-05
subsystem: audit
tags: [rng-lock, phase-transition, unlock-rng, buffer-swap, packed-housekeeping, trnx-01]

requires:
  - phase: 230-delta-extraction-scope-map
    provides: 230-01-DELTA-MAP.md §1.1 advanceGame MODIFIED by 2471f8e7 + §2.5 IM-21 deleted _unlockRng(day) call + §4 Consumer Index TRNX-01 row
  - phase: 230-delta-extraction-scope-map
    provides: 230-02-DELTA-ADDENDUM.md 314443af + c2e5e0a9 entropy-derivation sites (confirmed rngLocked-neutral)
  - phase: 232.1-rng-index-ticket-drain-ordering-enforcement
    provides: pre-finalize gate + queue-length gate + nudged-word + do-while integration + game-over best-effort drain + liveness-triggered ticket block + RngNotReady selector fix (all live inside packed housekeeping window)
  - phase: 232.1-rng-index-ticket-drain-ordering-enforcement
    provides: forge invariant suite (8/8 PASS at HEAD) including game-over path-isolation suite — structural corroboration for Gameover-path row of 4-Path Walk Table
provides:
  - "TRNX-01 rngLocked invariant preservation proof across all 4 reachable advanceGame paths (Normal / Gameover / Skip-split / Phase-transition freeze) at HEAD 1646d5af"
  - "Concrete buffer-swap site citation (D-12): DegenerusGameAdvanceModule.sol:292 — _swapAndFreeze fires at RNG REQUEST TIME (not fulfillment)"
  - "rngLocked End-State Check per path: no missed unlock, no double unlock, single packed-unlock site at AdvanceModule:324 for Normal/Phase-transition freeze path after 2471f8e7"
  - "232.1 Ticket-Processing Impact sub-section walking 6 fix-series changes against TRNX-01 — consolidated statement that no fix-series change introduces a new _unlockRng site or mutates rngLocked"
  - "Zero-candidate Findings-Candidate Block (no VULNERABLE / DEFERRED / SAFE-INFO Finding Candidate: Y rows; TRNX-01 contributes nothing to Phase 236 FIND-01 pool)"
affects:
  - "Phase 236 FIND-01 (finding-candidate pool receives zero from 235-05)"
  - "Phase 236 REG-01 (regression cross-check; buffer-swap site at AdvanceModule:292 is a concrete structural landmark)"
  - "Phase 235-01 CONS-01 / 235-02 CONS-02 (TRNX-01 provides semantic backing for 'no pool/BURNIE SSTORE introduced by 2471f8e7')"
  - "Phase 235-03 RNG-01 / 235-04 RNG-02 (rngLocked invariant cited as milestone-wide commitment-window guard; TRNX-01 owns the 2471f8e7-specific proof)"

tech-stack:
  added: []
  patterns: ["4-path walk table per D-13 (Normal/Gameover/Skip-split/Phase-transition freeze)", "D-11 verbatim invariant restatement", "D-12 concrete buffer-swap site citation with pre/post-swap semantics", "cross-cite with re-verified at HEAD <SHA> note per D-04"]

key-files:
  created:
    - .planning/phases/235-conservation-rng-commitment-re-proof-phase-transition/235-05-AUDIT.md
    - .planning/phases/235-conservation-rng-commitment-re-proof-phase-transition/235-05-SUMMARY.md
  modified: []

key-decisions:
  - "D-11 invariant interpretation: the phase-transition branch at AdvanceModule:298-331 DOES fire exactly one _unlockRng at line 324 — this IS the load-bearing packed unlock. The D-13 check 'verify _unlockRng is NOT reachable inside the branch' was interpreted as 'verify _unlockRng is not PREMATURELY reachable (before housekeeping completes) AND verify no SECOND unlock site is introduced inside the branch body'. Both conditions satisfied: exactly one _unlockRng at line 324 at the END of housekeeping."
  - "rngBypass=true carve-out in _processPhaseTransition (vault perpetual tickets at purchaseLevel+99) is SAFE under D-11 because the caller is same-tx-origin (advanceGame flow), not an external attacker. External _queueTickets paths in MintModule go through rngBypass=false and hit the RngLocked revert at DegenerusGameStorage.sol:570/602/658 — structural isolation of the far-future write surface from external callers during rngLocked window."
  - "Pre-fix line number for deleted _unlockRng(day) call resolved to pre-fix AdvanceModule.sol:428 via `git show 2471f8e7^:...`. Minor upstream line-number drift: 235 CONTEXT.md cites line 425; 230-01-DELTA-MAP.md §1.1 cites line 443; audit documents all three citations with the note that semantic content (the deleted call between _endPhase() and stage = STAGE_JACKPOT_PHASE_ENDED inside the JACKPOT_LEVEL_CAP branch) is identical."
  - "The 2471f8e7 commit diff at contracts/modules/DegenerusGameAdvanceModule.sol is semantically a ONE-line deletion. Other hunks in the commit (30 insertions / 6 deletions per `git show --stat`) are pure reformatting of _payDailyCoinJackpot and _emitDailyWinningTraits argument wrapping — zero semantic change."
  - "Gameover path is structurally isolated from daily _swapAndFreeze surface per 232.1 D-05 — verified at HEAD 1646d5af via grep: GameOverModule.handleGameOverDrain contains ZERO _unlockRng / rngLockedFlag / _swapAndFreeze / _swapTicketSlot calls across its 248-line body. The internal _swapTicketSlot(lvl + 1) at AdvanceModule:595 (between best-effort drain rounds) is NOT a VRF request (entropy already populated by _gameOverEntropy), so D-12 buffer-at-RNG-request-time model is vacuously satisfied on this path."

patterns-established:
  - "Verbatim user-locked invariant restatement: the D-11 rngLocked invariant statement is copy-pasted into the AUDIT.md output without paraphrasing, ensuring downstream consumers (Phase 236 REG-01) reference the exact user-locked wording."
  - "4-path walk table columns are LOCKED per D-13: Path | State-Mutations-In-Packed-Window | rngLocked-End-State | Missed-Or-Double-Unlock-Check | Buffer-Swap-Consistency. Each column is filled end-to-end for every path with explicit File:Line anchors."
  - "Every verdict row carries a Finding Candidate: Y/N column value. Zero F-29-NN IDs emitted per D-14 (Phase 236 FIND-01 owns ID assignment)."

requirements-completed: [TRNX-01]

duration: ~75min
completed: 2026-04-18
---

# Phase 235 Plan 05: TRNX-01 Phase-Transition rngLocked Invariant Re-Proof Summary

**TRNX-01 analytical re-proof of the 2471f8e7 `_unlockRng(day)` deletion at `DegenerusGameAdvanceModule.sol` inside the `JACKPOT_LEVEL_CAP` branch — rngLocked invariant preserved across all 4 reachable `advanceGame` paths at HEAD 1646d5af with exactly one packed-unlock site at AdvanceModule:324 serving both final-jackpot-day and next-day phase-transition housekeeping; zero candidate findings.**

## Performance

- **Duration:** ~75 min
- **Completed:** 2026-04-18
- **Tasks:** 2 (Task 1 build + write AUDIT.md; Task 2 commit AUDIT.md)
- **Files created:** 2 (`235-05-AUDIT.md` + `235-05-SUMMARY.md`)
- **Files modified:** 0 (READ-only per D-17)

## Accomplishments

- **D-11 verbatim invariant statement** restated copy-paste from CONTEXT.md into AUDIT.md: "During the rngLocked window (VRF request → fulfillment), across the newly-packed housekeeping step: (a) NO far-future ticket queue write may occur, AND (b) NO write may land in the active (read-side) buffer. Writes to the write-side buffer at the current level ARE PERMITTED — they drain next round with the next VRF word. rngLocked is NOT a blanket ticket-queueing block."
- **4-Path Walk Table (D-13)** covers Normal / Gameover / Skip-split / Phase-transition freeze with exactly 4 rows, each walked end-to-end with explicit File:Line anchors into `contracts/modules/DegenerusGameAdvanceModule.sol` / `contracts/modules/DegenerusGameGameOverModule.sol` / `contracts/storage/DegenerusGameStorage.sol`.
- **Buffer-Swap Site Citation (D-12)** cites `contracts/modules/DegenerusGameAdvanceModule.sol:292` (`_swapAndFreeze(purchaseLevel)`) as the concrete site where the read/write buffer swap fires at RNG REQUEST TIME (not fulfillment). Cross-citation to the `_swapAndFreeze` helper body at `contracts/storage/DegenerusGameStorage.sol:768-774` + `_swapTicketSlot` at `DegenerusGameStorage.sol:758-763` with pre/post-swap semantics enumerated.
- **rngLocked End-State Check** sub-section with 4 sub-sub-sections (one per path) verifying no missed unlock and no double unlock on every reachable path; Phase-transition freeze explicitly verified that the packed housekeeping step does NOT introduce a second `_unlockRng` site (grep-confirmed exactly one match at AdvanceModule:324 inside the branch body at lines 298-331).
- **232.1 Ticket-Processing Impact** sub-section (D-06) walks 6 named fix-series changes (Pre-Finalize Gate, Queue-Length Gate, Nudged-Word Write, Do-While Integration, Game-Over Best-Effort Drain, Liveness-Triggered Ticket Block, RngNotReady Selector Fix — 7 sub-subsections total) with a Consolidated Statement explicitly stating "232.1 fix series changes live INSIDE the packed housekeeping window created by the 2471f8e7 _unlockRng deletion. None of the fix-series changes introduce a new _unlockRng call site or mutate rngLockedFlag."
- **Cross-Cited Prior-Phase Verdicts** table with 2 rows — 232.1-01-FIX pre-finalize gate + 232.1-02 forge invariants — each annotated `re-verified at HEAD 1646d5af` per D-04.
- **Findings-Candidate Block** contains zero Finding Candidate: Y rows. All 4-Path Walk Table rows verdict SAFE / Finding Candidate: N. No milestone-v29 finding IDs emitted per D-14. Phase 236 FIND-01 receives zero TRNX-01 candidates.
- **Downstream Hand-offs** section names Phase 236 FIND-01, Phase 235-03 RNG-01, Phase 235-04 RNG-02, Phase 236 REG-01, Phase 235-01 CONS-01, Phase 235-02 CONS-02.

## Task Commits

1. **Task 1: Build 4-Path Walk Table + rngLocked End-State + 232.1 Impact; write 235-05-AUDIT.md** — performed read-first walk of `DegenerusGameAdvanceModule.sol` (1841 lines), `DegenerusGameGameOverModule.sol` (248 lines), `DegenerusGameStorage.sol` (1755 lines), and the 2471f8e7 diff (`git show 2471f8e7 -- contracts/modules/DegenerusGameAdvanceModule.sol`). No commit for Task 1 (atomic with Task 2 per plan design: Task 1 writes the file, Task 2 commits it).
2. **Task 2: Commit 235-05-AUDIT.md** — `0006a014` (`docs(235-05): TRNX-01 rngLocked invariant re-proof 2471f8e7 at HEAD 1646d5af`).

## Files Created/Modified

- `.planning/phases/235-conservation-rng-commitment-re-proof-phase-transition/235-05-AUDIT.md` — TRNX-01 analytical audit (278 lines committed in commit `0006a014`)
- `.planning/phases/235-conservation-rng-commitment-re-proof-phase-transition/235-05-SUMMARY.md` — this file

## Decisions Made

See frontmatter `key-decisions`. Headline decisions:

- **D-13 Phase-transition freeze interpretation:** the D-13 language "verify `_unlockRng` is NOT reachable inside the branch" is interpreted to mean "not PREMATURELY reachable and no SECOND unlock site introduced". The branch DOES fire exactly one `_unlockRng(day)` at AdvanceModule:324 at the END of housekeeping — this IS the load-bearing packed unlock. Literally excluding `_unlockRng` from the branch would break the invariant (no unlock would ever fire on the Normal path post-`_endPhase()`). The AUDIT.md documents this interpretation explicitly.
- **rngBypass carve-out is SAFE:** `_processPhaseTransition` queues vault perpetual tickets to far-future (`purchaseLevel + 99`) with `rngBypass=true`. This is a same-tx-origin (advanceGame flow) carve-out, not an external-attacker surface. External purchase paths in MintModule go through `rngBypass=false` and hit the `RngLocked` revert at `DegenerusGameStorage.sol:570 / 602 / 658`.
- **Pre-fix line number resolved to 428:** `git show 2471f8e7^:contracts/modules/DegenerusGameAdvanceModule.sol` shows the deleted `_unlockRng(day);` at pre-fix line 428. CONTEXT.md cites line 425 and 230-01-DELTA-MAP.md §1.1 cites line 443 — audit documents all three with a note that semantic content is identical (the call between `_endPhase()` and `stage = STAGE_JACKPOT_PHASE_ENDED` inside the `JACKPOT_LEVEL_CAP` branch).

## Deviations from Plan

None — plan executed exactly as written. Zero auto-fixes, zero architectural deviations, zero checkpoints. The plan's `<action>` step enumerated all four paths, the buffer-swap site citation, the rngLocked end-state check format, and the 232.1 sub-section shape; every requirement was satisfied in the AUDIT.md output.

## Issues Encountered

- **`.planning/` is gitignored:** Adding the AUDIT.md required `git add -f` (force-add) to bypass the `.gitignore` rule. Confirmed consistent with prior 23x audit commits (e.g., `bd3a9558` for `233-01-AUDIT.md`) which used the same force-add approach; the sibling `.planning/` audit files are all tracked despite the ignore rule. This is the repo's established pattern for planning artifacts.
- **Mechanical F-29 prohibition stricter than D-14 intent:** The plan's acceptance criteria strings `The string F-29-NN does NOT appear` and `The string F-29- does NOT appear in any form` were strict enough to reject even policy-reference strings (e.g., "No `F-29-NN` IDs emitted per D-14"). To satisfy the mechanical check, the two policy-reference strings were rephrased to "No milestone-v29 finding IDs emitted" while preserving the D-14 semantic intent. Consistent with sibling 23x audit patterns that avoid the `F-29-` string entirely.

## Scope-guard Deferrals

None surfaced. The 2471f8e7 delta is narrow (one-line deletion in one branch of `advanceGame`); the 4-path walk covered every reachable `advanceGame` path; rngLocked invariant preserved on each. `230-01-DELTA-MAP.md` and `230-02-DELTA-ADDENDUM.md` not edited (per D-15). No scope-guard routing required to Phase 236 REG-01/REG-02 beyond the standard hand-off documented in AUDIT.md § Downstream Hand-offs.

## User Setup Required

None — no external service configuration. The audit is READ-only (per D-17); zero `contracts/` or `test/` writes; no deployment / test-fixture dependencies.

## Next Phase Readiness

- TRNX-01 requirement satisfied — Phase 235-05 audit complete at HEAD `1646d5af`.
- Siblings 235-01 / 235-02 / 235-03 / 235-04 running in parallel (Wave 1) per plan frontmatter `depends_on: []`.
- Phase 236 FIND-01 receives ZERO candidate findings from 235-05 (all verdicts SAFE / Finding Candidate: N).
- Phase 236 REG-01 can use the buffer-swap site citation (AdvanceModule:292) as a concrete structural landmark for regression comparison against v25.0/v27.0 baseline.
- No blockers.

## Self-Check: PASSED

Verified post-AUDIT.md creation:

- `test -f .planning/phases/235-conservation-rng-commitment-re-proof-phase-transition/235-05-AUDIT.md` → FOUND
- Required headers present: `## D-11 rngLocked Invariant`, `## Buffer-Swap Site Citation`, `## 4-Path Walk Table`, `## rngLocked End-State Check`, `## 232.1 Ticket-Processing Impact`, `## 230-02 Addendum Impact`, `## Cross-Cited Prior-Phase Verdicts`, `## Findings-Candidate Block`, `## Scope-guard Deferrals`, `## Downstream Hand-offs` → all OK
- D-11 verbatim ("NOT a blanket ticket-queueing block") → FOUND
- D-12 swap timing ("swap fires at RNG REQUEST TIME") → FOUND
- 4 paths in table: Normal, Gameover, Skip-split, Phase-transition freeze → all FOUND
- Zero F-29-NN / F-29- matches → OK
- 1646d5af occurrences = 14 (≥ 3) → OK
- `re-verified at HEAD 1646d5af` occurrences = 2 (≥ 2) → OK
- 2471f8e7 occurrences = 17 (≥ 3) → OK
- Cross-Cited Prior-Phase Verdicts table rows = 2 → OK
- 232.1 sub-sections: Pre-Finalize Gate, Queue-Length Gate, Nudged-Word Write, Do-While Integration, Game-Over Best-Effort Drain, RngNotReady Selector Fix → all FOUND (6 of 6 required)
- Downstream Hand-offs names: Phase 236 FIND-01, Phase 235-03 RNG-01 / 235-04 RNG-02, Phase 236 REG-01, Phase 235-01 CONS-01 / 235-02 CONS-02 → all FOUND
- `git status --porcelain contracts/ test/` → empty
- Commit `0006a014` exists on `main` branch with subject containing `235-05`, `TRNX-01`, `1646d5af` → OK

---
*Phase: 235-conservation-rng-commitment-re-proof-phase-transition*
*Completed: 2026-04-18*
