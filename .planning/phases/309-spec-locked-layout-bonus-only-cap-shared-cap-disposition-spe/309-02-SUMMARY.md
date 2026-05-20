---
phase: 309-spec-locked-layout-bonus-only-cap-shared-cap-disposition-spe
plan: 02
subsystem: audit
tags: [v45.0, V-081, lootbox, ev-cap, rng-freeze, spec, backward-trace, sload-enumeration]

# Dependency graph
requires:
  - phase: 309-01
    provides: "309-SPEC.md §0–§3 (grep-verified call-graph evidence + SPEC-01/02/03 locked); §0.D cap-fn SLOAD/SSTORE lines (:487/:502); §0.E frozen-activityScore multiplier sites (:674/:710); §0.F seed-build rows (:671/:707)"
provides:
  - "309-SPEC.md §4 SPEC-04 — shared-cap disposition LOCKED: ACCEPT, proven (not asserted)"
  - "§4.A word-independence backward-trace per consumer (resolveLootboxDirect, resolveRedemptionLootbox) grounded in the pure _lootboxEvMultiplierFromScore(activityScore) source"
  - "§4.B complete in-window SLOAD enumeration for all three callers; lootboxEvBenefitUsedByLevel confirmed sole shared mutable consumed alongside the word"
  - "§4.C ACCEPT verdict tying §4.A + §4.B; SPEC-04/INV-05 satisfied, INV-06 preserved"
affects: [310-IMPL, 311-TST, 312-SWEEP, 313-TERMINAL]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "ACCEPT-as-theorem: a fix-or-accept SPEC verdict is discharged by a backward-trace + full in-window SLOAD enumeration, never a 'by construction' assertion"
    - "Per-caller in-window SLOAD table {slot, file:line, key shape, mutable/frozen, shared/per-box, why-safe} per feedback_rng_window_storage_read_freshness"

key-files:
  created: []
  modified:
    - ".planning/phases/309-spec-locked-layout-bonus-only-cap-shared-cap-disposition-spe/309-SPEC.md (appended §4.A/§4.B/§4.C)"

key-decisions:
  - "SPEC-04 disposition = ACCEPT + DOCUMENT (D-10), proven by §4.A backward-trace + §4.B SLOAD enumeration — no fix required"
  - "Multiplier is a pure function of the frozen activityScore parameter (_lootboxEvMultiplierFromScore is private pure, :446) — word cannot change it"
  - "lootboxEvBenefitUsedByLevel[player][currentLevel] is the SOLE shared mutable consumed alongside the live word across all three callers (enumerated, not assumed)"
  - "Residual resolution-order cap-steering is word-INDEPENDENT → already-accepted self-MEV (REQUIREMENTS Out-of-Scope)"

patterns-established:
  - "Pattern 1: ACCEPT verdicts in a SPEC must be proven theorems (backward-trace + SLOAD enumeration), not assertions"
  - "Pattern 2: enumerate EVERY in-window SLOAD per caller, classifying each as global / frozen-seed-input / pre-word per-box / shared-mutable"

requirements-completed: [SPEC-04]

# Metrics
duration: ~12min
completed: 2026-05-20
---

# Phase 309 Plan 02: SPEC-04 Shared-Cap Disposition Summary

**SPEC-04 LOCKED as ACCEPT + DOCUMENT — proven by a per-consumer word-independence backward-trace and a complete in-window SLOAD enumeration showing `lootboxEvBenefitUsedByLevel` is the sole shared mutable consumed alongside the live VRF word, with residual order-steering classified as already-accepted self-MEV.**

## Performance

- **Duration:** ~12 min
- **Started:** 2026-05-20T11:02Z
- **Completed:** 2026-05-20T11:14Z
- **Tasks:** 2
- **Files modified:** 1 (309-SPEC.md — §4 appended; §0–§3 from Plan 01 untouched)

## Accomplishments
- **§4.A word-independence backward-trace (proof, not assertion):** opened §4 stating ACCEPT is a theorem with an explicit "no 'by construction'" disclaimer; traced each consumer backward — multiplier derives from the FROZEN `activityScore` parameter via the `private pure` `_lootboxEvMultiplierFromScore` (grep-verified :674 / :710), per-caller commitment times named (decimator = bucket-at-burn, degenerette = bet-time, redemption = burn-submission), seed uses raw `amount` (:671/:707) so cap allocation never changes a roll (INV-04), purchased boxes allocate pre-word (SPEC-03), and residual order-steering proven word-independent → accepted self-MEV.
- **§4.B complete in-window SLOAD enumeration for all three callers:** per-caller tables for `openLootBox` (11 in-window reads incl. `lootboxEth`, `lootboxRngWordByIndex` gate, `lootboxDay` frozen seed input, `lootboxEthBase`, `lootboxBaseLevelPacked`, `lootboxEvScorePacked`, `lootboxDistressEth`, the `level` global, and the cap SLOAD), `resolveLootboxDirect`, and `resolveRedemptionLootbox`; LOCKED finding that `lootboxEvBenefitUsedByLevel[player][currentLevel]` is the SOLE shared mutable consumed alongside the word — enumerated, not assumed; F-41-02/03 non-VRF-read bug class confirmed absent; POST-IMPL open path noted to have zero shared-mutable in-window reads.
- **§4.C ACCEPT verdict** tying §4.A + §4.B into the fix-or-accept disposition: no known-word ordering edge through the shared accumulator; SPEC-04 / INV-05 satisfied, INV-06 preserved, ROADMAP SC4 discharged.
- Zero `contracts/` and zero `test/` mutations across both tasks (contract source read-only for grep verification).

## Task Commits

Each task was committed atomically (force-added — `.planning/` is gitignored):

1. **Task 1: §4.A word-independence backward-trace** - `ee2f98d1` (docs)
2. **Task 2: §4.B in-window SLOAD enumeration + §4.C ACCEPT verdict** - `2e525f69` (docs)

**Plan metadata:** (final docs commit — SUMMARY + STATE + ROADMAP + REQUIREMENTS)

## Files Created/Modified
- `.planning/phases/309-.../309-SPEC.md` - Appended §4 (SPEC-04): §4.A backward-trace, §4.B per-caller in-window SLOAD tables, §4.C ACCEPT verdict. §0–§3 from Plan 01 unchanged. Now 641 lines.
- `.planning/phases/309-.../309-02-SUMMARY.md` - This summary.

## Decisions Made
- **Disposition = ACCEPT + DOCUMENT (D-10)** — proven by §4.A + §4.B, no contract fix required.
- **Cap-fn SLOAD/SSTORE line reconciliation:** the plan `<interfaces>` block cited the cap SLOAD/SSTORE as `:485/:503`; grep-verified HEAD lines are `:487` (SLOAD) / `:502` (SSTORE), matching the Plan-01 §0.D evidence. Recorded in §4.B.4 as a note (not normalized) and used the grep-verified `:487`/`:502` throughout §4.B.

## Deviations from Plan

None - plan executed exactly as written. (The cap-fn line reconciliation noted above is a documentation precision note recorded inside the SPEC per the audit-baseline re-grep directive, not a deviation from the plan's tasks. The plan's `<interfaces>` block was advisory; §0.D from Plan 01 had already grep-verified `:487`/`:502`, which §4.B uses.)

## Issues Encountered
- Plan `<interfaces>` cited cap SLOAD/SSTORE at `:485/:503`; my own grep against HEAD returned `:487` (SLOAD) / `:502` (SSTORE) — consistent with Plan-01 §0.D. Resolved by citing the grep-verified lines and recording the discrepancy explicitly in §4.B.4, honoring the "re-grep and record your own matched substring + line for every cited ref" baseline directive.

## Self-Check: PASSED
- File exists: `.planning/phases/309-.../309-SPEC.md` — FOUND (641 lines, §4.A/§4.B/§4.C present)
- File exists: `.planning/phases/309-.../309-02-SUMMARY.md` — FOUND
- Commit `ee2f98d1` (Task 1) — FOUND in git log, 104 insertions confirmed in `git show --stat`
- Commit `2e525f69` (Task 2) — FOUND in git log, 114 insertions confirmed in `git show --stat`
- `git status --porcelain contracts/ test/` — empty (zero code mutations)
- Task 1 automated verify — PASS; Task 2 automated verify — PASS

## Next Phase Readiness
- SPEC-04 is the final SPEC requirement; 309-SPEC.md §0–§4 now fully LOCKS the v45.0 design.
- Phase 310 (IMPL) can proceed with the proven ACCEPT — `resolveLootboxDirect` / `resolveRedemptionLootbox` keep the resolution-time cap draw (Change-1 `<=` only); no purchase/allocation point added for them. The shared-cap path is documented as carrying no known-word reorder vector, so IMPL must NOT add a live-word-discretionary writer of the cap accumulator (INV-06 guard).
- No blockers.

---
*Phase: 309-spec-locked-layout-bonus-only-cap-shared-cap-disposition-spe*
*Completed: 2026-05-20*
