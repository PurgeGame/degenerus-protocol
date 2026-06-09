---
phase: 381-invariant-fuzz-durable-property-net
plan: 02
subsystem: testing
tags: [foundry, invariant-fuzz, rng-freeze, vrf, storage-slots, v45-north-star]

# Dependency graph
requires:
  - phase: 380-foundation
    provides: green REGRESSION-BASELINE-v62, subject-locked contracts (c4d48008), authoritative storage layout (380-01-LAYOUT-KEY)
  - phase: 381-01
    provides: SolvencyActionHandler + V61SolvencyAfpay wiring pattern (targetContract, afterInvariant non-vacuity, falsifiability test exemplar)
provides:
  - RngWindowFreezeHandler — the FUZZ-02 in-window action handler (opens the VRF window, self-primes + fires placement/purchase/openBoxes in-window, snapshots the enumerated consumed-slot set at request time, isolation-checks freeze)
  - RngWindowFreeze.inv.t.sol — the canonical always-on RNG-FREEZE invariant over the enumerated in-window SLOAD set (256/128, non-vacuous, falsifiable)
affects: [382-prime, 383-asym, 385-vrf, council-sweeps]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Self-priming in-window action: each fuzzed in-window action calls _driveWindowOpen first so it ALWAYS executes inside an open VRF window — non-vacuity independent of fuzzer call ordering"
    - "Day-warp drive loop: _driveWindowOpen warps a full day per advance iteration so a fresh daily VRF request becomes due after a prior window closed (the heartbeat's natural rhythm)"
    - "Counter-neutral + excluded falsifiability seam: the seeded-violation hook is excluded from the fuzz campaign AND returns its detection (never touches the live property counter)"

key-files:
  created:
    - test/fuzz/invariant/RngWindowFreeze.inv.t.sol
  modified:
    - test/fuzz/handlers/RngWindowFreezeHandler.sol

key-decisions:
  - "Promoted scattered freeze SCENARIO proofs into ONE fuzzed invariant asserting the GENERAL property (no in-window mutation of any enumerated consumed slot), NOT a re-proof of the existing scenario guards (case b PROMOTE/EXTEND)"
  - "Enumerated set includes NON-VRF reads (dailyIdx slot0:3, lootboxRngPacked cursor slot36 low-48) alongside the VRF-derived word seeds (rngWordByDay[10], lootboxRngWordByIndex[37]) — a non-VRF in-window read is its own bug class (feedback_rng_window_storage_read_freshness)"
  - "advanceGame is the v45-exempt heartbeat mutator: the isolation check snapshots before / re-checks after the player action ALONE (no advance between), so only player-attributable changes are flagged"

patterns-established:
  - "Self-priming in-window action handlers guarantee non-vacuity regardless of fuzzer ordering"
  - "Day-warp inside the open-window drive loop crosses the JACKPOT_RESET_TIME boundary so the next daily VRF request is due"

requirements-completed: [FUZZ-02]

# Metrics
duration: ~75min
completed: 2026-06-08
---

# Phase 381 Plan 02: FUZZ-02 RNG-FREEZE Durable Invariant Summary

**Always-on fuzzed invariant proving every enumerated in-window SLOAD (rngWordByDay[10], lootboxRngWordByIndex[37], lootboxRngPacked cursor [36], dailyIdx [slot0:3]) is byte-frozen against any player-controllable action inside the VRF request→unlock window — non-vacuous (window opens + in-window actions fire) and falsifiable (a seeded in-window mutation is caught).**

## Performance

- **Duration:** ~75 min
- **Started:** 2026-06-08T02:20Z (RED commit)
- **Completed:** 2026-06-08T03:34Z
- **Tasks:** 2 (Task 1 handler build/refine, Task 2 invariant author) — TDD RED→GREEN
- **Files modified:** 2 (1 created, 1 refined)

## Accomplishments
- `invariant_inWindowSloadsFrozen` GREEN over the default [invariant] profile (runs=256, depth=128, 32768 calls, 0 reverts): no player action inside the VRF window mutated any enumerated consumed slot.
- Enumerated in-window SLOAD set traced BACKWARD from each consumer and includes a NON-VRF read (dailyIdx + lootbox cursor), not only the word seeds.
- Non-vacuity GATED at end-of-campaign (`afterInvariant`: ghost_windowsOpened > 0 AND ghost_inWindowActions > 0) + a focused deterministic non-vacuity test (`test_freezeWindowIsExercised_nonVacuous`).
- Falsifiability proven (`test_invariantCatchesSeededInWindowMutation`): the detector fires on a seeded in-window mutation of an enumerated consumed slot, and the seam is counter-neutral (never pollutes the live property).
- advanceGame distinguished as the v45-exempt heartbeat mutator via before/after isolation snapshots — only player-attributable changes are flagged.
- ZERO contracts/*.sol mutation (`git diff c4d48008 -- contracts/` empty).

## Task Commits

1. **Task 1+2 RED: falsifiability hook authored failing** - `ba21a4b3` (test) — handler + invariant referencing a not-yet-exposed `debugSeedInWindowMutationAndCheck` seam → compile fails → RED.
2. **Task 1+2 GREEN: invariant + handler fixes** - `7d073d6a` (test) — all 4 tests green over 256/128.

_TDD: a single RED→GREEN cycle for the plan-level feature (the invariant + its handler are one durable property)._

## Files Created/Modified
- `test/fuzz/invariant/RngWindowFreeze.inv.t.sol` (created, 193 lines) — the canonical RNG-FREEZE invariant: `invariant_inWindowSloadsFrozen` (the property), `invariant_freezeWindowExercised` (surveillance), `afterInvariant` (non-vacuity gate), `test_freezeWindowIsExercised_nonVacuous` (focused non-vacuity), `test_invariantCatchesSeededInWindowMutation` (falsifiability). Excludes the falsifiability seam from the campaign.
- `test/fuzz/handlers/RngWindowFreezeHandler.sol` (refined, 414 lines) — opens the VRF window, self-primes + fires placement/purchase/openBoxes in-window, snapshots the enumerated consumed set at request time and isolation-checks freeze; closeWindow drives _unlockRng; counter-neutral falsifiability seam.

## Decisions Made
- **Case (b) PROMOTE/EXTEND, not re-proof:** the invariant asserts the GENERAL freeze property over the player-controllable in-window action space rather than re-proving RngFreezeAndRemovalProofs' placement/resolve scenario guards.
- **Enumerated (not seed-only) set:** included the non-VRF cursors (dailyIdx, lootbox index) read alongside the word — a distinct bug class per the RNG methodology memory.
- **Self-priming over fuzzer-luck:** in-window actions open the window themselves so the property is deterministically non-vacuous, not dependent on the fuzzer happening to order open→action→(no close).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] closeWindow did not clear rngLocked()**
- **Found during:** Task 2 (first campaign + focused non-vacuity run)
- **Issue:** `closeWindow` only called `vrf.fulfillRandomWords`, which (per AdvanceModule.rawFulfillRandomWords) only BUFFERS the daily word into `rngWordCurrent` while leaving `rngLockedFlag` set; the lock clears in `_unlockRng`, reached only on a subsequent `advanceGame`. The focused test's "lock cleared" assertion failed.
- **Fix:** `closeWindow` now fulfills THEN advances (capped) until `rngLocked()` falls — the exempt heartbeat completing.
- **Files modified:** test/fuzz/handlers/RngWindowFreezeHandler.sol
- **Verification:** `test_freezeWindowIsExercised_nonVacuous` asserts `!game.rngLocked()` after closeWindow — passes.
- **Committed in:** 7d073d6a

**2. [Rule 1 - Bug] Campaign was vacuous — in-window actions never fired (ghost_inWindowActions == 0)**
- **Found during:** Task 2 (default-profile campaign afterInvariant)
- **Issue:** After the first window closed, the game sat on the same day; `advanceGame` fires a daily VRF request only at a NEW day boundary, so `_driveWindowOpen` never re-latched within its 8-iteration cap (no time passed). The in-window actions (which only run inside an open window) thus never fired across 32768 calls → afterInvariant non-vacuity gate failed.
- **Fix:** (a) factored the open-window drive into `_driveWindowOpen` and made the in-window actions SELF-PRIME (call it first) so they always run inside an open window regardless of fuzzer ordering; (b) `_driveWindowOpen` warps a full day per advance iteration so a fresh daily request becomes due.
- **Files modified:** test/fuzz/handlers/RngWindowFreezeHandler.sol
- **Verification:** probe run showed inWindowActions == every in-window call (16/16); the real campaign's afterInvariant non-vacuity gate now passes (windowsOpened > 0 AND inWindowActions > 0).
- **Committed in:** 7d073d6a

**3. [Rule 1 - Bug] Falsifiability seam polluted the live property when the fuzzer called it**
- **Found during:** Task 2 (first campaign — invariant flagged ghost_frozenSlotMutations == 1 from a `debugSeedInWindowMutationAndCheck` call)
- **Issue:** the seam was a public function on the targetContract, so the fuzzer invoked it and its seeded violation incremented the live `ghost_frozenSlotMutations` counter.
- **Fix:** the seam now RETURNS its detection (instead of mutating the campaign counter) and is `excludeSelector`-excluded from the fuzz campaign; the falsifiability test asserts the boolean return + counter-neutrality.
- **Files modified:** test/fuzz/handlers/RngWindowFreezeHandler.sol, test/fuzz/invariant/RngWindowFreeze.inv.t.sol
- **Verification:** `test_invariantCatchesSeededInWindowMutation` asserts `detected == true` AND the live counter is unchanged — passes; the campaign no longer sees the seam.
- **Committed in:** 7d073d6a

---

**Total deviations:** 3 auto-fixed (all Rule 1 — test-harness bugs in the handler/invariant wiring; ZERO contract changes)
**Impact on plan:** All three were necessary to make the durable invariant genuinely green, non-vacuous, and falsifiable. No scope creep; the asserted property is exactly the plan's FUZZ-02 freeze property.

## Issues Encountered
- Diagnosing the vacuity required isolating openWindow (latches fine) from in-window actions (never fired) via throwaway probe invariants (removed before commit) — root cause was the missing day-warp, not the handler logic (which worked deterministically in unit probes from the start).

## User Setup Required
None - test-only; no external service configuration.

## Next Phase Readiness
- FUZZ-02 (RNG-FREEZE) is now a durable always-on net for the council sweeps (382 PRIME / 383 ASYM / 385 VRF) — they have a freeze oracle, not point tests.
- Wave-1 (381-01 FUZZ-01 + 381-02 FUZZ-02) durable invariants both green. Remaining: 381-03..05 (rest of Wave-1/2) then 381-06 (council, autonomous:false — HARD STOP).
- HARD CONSTRAINT honored: no contract edits; no advance to 382.

## Self-Check: PASSED

- FOUND: test/fuzz/handlers/RngWindowFreezeHandler.sol
- FOUND: test/fuzz/invariant/RngWindowFreeze.inv.t.sol
- FOUND: .planning/phases/381-invariant-fuzz-durable-property-net/381-02-SUMMARY.md
- FOUND commit: ba21a4b3 (RED)
- FOUND commit: 7d073d6a (GREEN)
- Mainnet .sol clean (`git diff c4d48008` over the protocol sources is empty)

---
*Phase: 381-invariant-fuzz-durable-property-net*
*Completed: 2026-06-08*
