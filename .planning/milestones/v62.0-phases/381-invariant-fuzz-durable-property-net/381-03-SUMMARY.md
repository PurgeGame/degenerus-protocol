---
phase: 381-invariant-fuzz-durable-property-net
plan: 03
subsystem: testing
tags: [foundry, gas-ceiling, eip-7825, advanceGame, gameseeder-etch, fuzz, composition, reusable-component]

# Dependency graph
requires:
  - phase: 380-foundation
    provides: green REGRESSION-BASELINE-v62, subject-locked contracts (c4d48008), authoritative storage layout (380-01-LAYOUT-KEY)
  - phase: 381-01
    provides: GameSeeder-etch + DeployProtocol fuzz scaffolding conventions
provides:
  - test/gas/AdvanceGasCeiling.sol — the REUSABLE EIP-7825 gas-ceiling property component (a parameterized GameSeeder seeder + AdvanceGasCeilingBase exposing _etchSeedRestore + _driveAndAssertUnderCap with per-tx assertLe(16_777_216) and a reachedHeavy non-vacuity report) that Phase 384 / COMPO-02 imports and parameterizes
  - test/gas/AdvanceGasCeilingFuzz.t.sol — fuzzes the property over MULTIPLE reachable worst-case advanceGame pre-states (fuzzed bucket geometry / level / owed sizes) + drives the v60 game-over composition regression THROUGH the extracted component
affects: [384-compo, council-sweeps]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Reusable etch-seed-restore + drive-and-measure base: factor the GameSeeder overlay + the per-tx gasleft drain loop into an abstract AdvanceGasCeilingBase so a fuzz AND Phase 384 consume one component instead of re-authoring the mechanism (FUZZ-03 SC3)"
    - "Heavy-but-finishing owed bound: owed sizes bounded into [120,175] (under the ~357 cold first-batch write budget) so each ticket round is a deep single-player drain that FINISHES in one batch — the worst-case fall-through branch where round1+round2+terminal-jackpot can compose in one tx, not a lighter split-batch shape"
    - "rngWord-driven geometry fuzz: fuzzing the rngWord fuzzes BOTH the winning-trait selection and (via effEntropy) the 305-winner bucket-count geometry the terminal jackpot rolls — one seed varies the whole reachable jackpot shape"

key-files:
  created:
    - test/gas/AdvanceGasCeilingFuzz.t.sol
    - test/gas/AdvanceGasCeiling.sol
  modified: []

key-decisions:
  - "Case (b) PROMOTE TO REUSABLE: factored the one-shot GameOverCompositionAdvanceGas mechanism (GameSeeder + _seedWorstCase + the gasleft drive loop) into AdvanceGasCeilingBase + a parameterized GameSeeder; did NOT duplicate the scenario — the one-shot stays as the named regression, now also driven through the extracted component"
  - "Worst-case-branch discipline: bounded the fuzzed owed sizes into the heavy-but-finishing regime ([120,175] vs the ~357 cold budget) so the measured tx exercises the composition fall-through (the real worst case), not a lighter split-batch shape; level fuzzed 10..4000 for deeper buckets"
  - "Non-vacuity hard-gated: reachedHeavy (set only inside game.gameOver() — i.e. once _handleGameOverPath ran the ticket double-drain + terminal jackpot) is assertTrue'd in BOTH cases so the per-tx EIP-7825 assertion is never vacuous"
  - "EIP-7825 cap is the HARD floor (assertLe per-tx inside the base); the 10M soft target is asserted on the deterministic regression and surfaced (not fatal) in the fuzz so a single unusually-heavy reachable geometry cannot red the durable cap property"

patterns-established:
  - "A gas-ceiling property authored as an importable abstract base + parameterized seeder, so the next phase parameterizes rather than re-authors"
  - "Per-tx gasleft measurement around the REAL production advanceGame() (etch GameSeeder -> seed -> restore real code) with the cap asserted on EACH tx in the drain loop"

requirements-completed: [FUZZ-03]

# Metrics
duration: ~35min
completed: 2026-06-08
---

# Phase 381 Plan 03: FUZZ-03 GAS-CEILING Reusable advanceGame Property Summary

**A reusable EIP-7825 gas-ceiling component (AdvanceGasCeilingBase + parameterized GameSeeder) that etch-seeds a worst-case advanceGame pre-state, drives the REAL advanceGame() to game-over, and assertLe's every single tx <= 16,777,216 — exercised over 1000 fuzzed reachable worst-case pre-states (max ~6.6M) and the named v60 game-over composition regression (3 txs, max 6.39M < the 10M soft target), with the heavy branch hard-gated as non-vacuous.**

## Performance

- **Duration:** ~35 min
- **Started:** 2026-06-08
- **Completed:** 2026-06-08
- **Tasks:** 2 (Task 1 component verify/refine — pre-existed from a crashed session, verified against live c4d48008 source; Task 2 author the fuzz + regression-through-component)
- **Files modified:** 2 (both new/untracked — AdvanceGasCeiling.sol from the prior session, AdvanceGasCeilingFuzz.t.sol new this session)

## Accomplishments
- `test/gas/AdvanceGasCeiling.sol` is the REUSABLE FUZZ-03 component: a parameterized `GameSeeder is DegenerusGame` seeder (seedAdvanceWorstCase + the verbatim-equivalent seedGameOverWorstCase) + an abstract `AdvanceGasCeilingBase is DeployProtocol` exposing `EIP7825_TX_GAS_CAP = 16_777_216`, `GAS_TARGET = 10_000_000`, `_etchSeedRestore(...)` (etch -> seed-from-params -> restore real code -> fund + warp) and `_driveAndAssertUnderCap(maxTxIters) -> (maxTxGas, reachedHeavy)` (per-tx `assertLe(used, 16_777_216)` + max tracking + non-vacuity report). All seeder storage symbols re-verified against live c4d48008 source (ticketQueue / ticketsOwedPacked / traitBurnTicket / rngWordByDay / levelPrizePool / purchaseStartDay / dailyIdx / _tqReadKey/_tqWriteKey / _lrWrite / LR_INDEX_SHIFT/MASK / _simulatedDayIndex).
- `testFuzz_advanceGame_everyTxUnderCap` GREEN over the [fuzz] 1000-run profile: every advanceGame tx in the game-over drain <= 16,777,216 across fuzzed bucket geometry (rngWord), level (10..4000) and per-round owed sizes; heavy branch reached every run (non-vacuous); observed run max ~6.63M.
- `test_gameOverComposition_regression_underCap` GREEN: the EXACT v60 game-over composition (the gasceil shape fixed 6d2c8d0c — LVL 110, the gasceil word, 170/170 owed, base 0x5_0000_0000) driven THROUGH the extracted component drains across 3 txs (6.19M / 4.99M / 6.39M), game-over completes, every tx < cap, max 6.39M < the 10M soft target (matches the v60 post-fix ~6.37M profile).
- ZERO contracts/*.sol mutation (`git status --short -- contracts/` empty; `git diff c4d48008 -- contracts/` empty).

## Task Commits

1. **Task 1 + Task 2 (test):** the atomic `test(381-03)` commit at HEAD (test) — the reusable AdvanceGasCeiling component (verified against live source) + the AdvanceGasCeilingFuzz fuzz/regression driving it; both green. (Single atomic commit also carries the SUMMARY + STATE/ROADMAP/REQUIREMENTS.)

_Note: the component pre-existed from a crashed prior session; this session verified it against live c4d48008 source and authored the fuzz + regression that exercise it. A single atomic test commit (the component + its exercising tests are one durable property)._

## Files Created/Modified
- `test/gas/AdvanceGasCeiling.sol` (created prior session, verified this session, 229 lines) — the reusable component: parameterized GameSeeder + AdvanceGasCeilingBase (_etchSeedRestore + _driveAndAssertUnderCap, per-tx 16,777,216 assertLe, reachedHeavy non-vacuity report, GAS_TARGET surfaced).
- `test/gas/AdvanceGasCeilingFuzz.t.sol` (created, 134 lines) — extends AdvanceGasCeilingBase: testFuzz_advanceGame_everyTxUnderCap (1000-run fuzz over reachable worst-case pre-states, heavy-but-finishing owed bound, rngWord-driven geometry fuzz, level 10..4000) + test_gameOverComposition_regression_underCap (the v60 composition driven through the component).

## Decisions Made
- **Promote to reusable (case b), not duplicate:** the one-shot's mechanism was factored into the base + parameterized seeder; the one-shot file stays as the named regression and its EXACT pre-state is re-driven through the extracted component in the fuzz test.
- **Heavy-but-finishing owed bound [120,175]:** sits under the ~357 cold first-batch write budget (WRITES_BUDGET_SAFE 550, −35% cold) so each round is a deep single-player drain that FINISHES in one batch — the composition fall-through worst case, per the measure-the-worst-case-branch repo rule. A larger owed would split the batch into lighter per-tx work (not the worst case).
- **EIP-7825 cap = hard floor; 10M = soft:** the per-tx `assertLe(used, 16_777_216)` inside the base is the durable hard floor on every fuzzed tx; the 10M soft target is asserted on the deterministic regression and surfaced (non-fatal) in the fuzz so the durable cap property is not flaky against a single unusually-heavy reachable geometry.

## Deviations from Plan

None - plan executed as written. (Task 1's component was already authored in a crashed prior session; this session verified it against live c4d48008 source rather than rewriting from scratch, per the prompt's reuse-don't-rewrite directive. No contract changes; no scope changes.)

## Issues Encountered
None. The pre-existing component compiled and ran correctly against the live subject on first exercise; the regression reproduced the known v60 post-fix gas profile (3 txs, max 6.39M).

## User Setup Required
None - test-only; no external service configuration.

## Next Phase Readiness
- FUZZ-03 (GAS-CEILING) is a durable AND reusable property: Phase 384 / COMPO-02 imports `AdvanceGasCeilingBase` and parameterizes `_etchSeedRestore` + `_driveAndAssertUnderCap` against its own fuzzed reachable states — it does NOT re-author the GameSeeder or the per-tx measure loop (SC3 satisfied).
- Wave-1 progress: 381-01 (FUZZ-01) + 381-02 (FUZZ-02) + 381-03 (FUZZ-03) green. Remaining: 381-04 (ENQUEUE), 381-05 (POOL-CONSERVATION), then 381-06 (council, autonomous:false — HARD STOP).
- HARD CONSTRAINT honored: targeted tests only; no contract edits; no advance to 382.

## Self-Check: PASSED

- FOUND: test/gas/AdvanceGasCeiling.sol
- FOUND: test/gas/AdvanceGasCeilingFuzz.t.sol
- FOUND: .planning/phases/381-invariant-fuzz-durable-property-net/381-03-SUMMARY.md
- FOUND commit: the atomic `test(381-03)` commit at HEAD (both test files + SUMMARY + STATE/ROADMAP/REQUIREMENTS)
- Mainnet protocol sources clean (`git status --short -- contracts/` empty; `git diff c4d48008 -- contracts/` empty)
- Post-commit deletion check: no tracked-file deletions in HEAD

---
*Phase: 381-invariant-fuzz-durable-property-net*
*Completed: 2026-06-08*
