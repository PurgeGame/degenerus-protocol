---
phase: 336-tst-equivalence-freeze-safety-divergence-repro-non-widening-
plan: 04
subsystem: testing

tags: [foundry, forge-std, vm.expectCall, afking, lazyPassHorizon, afsub-02, tst-02, no-sload-oracle, hot-path-accurate, gasopt-05-no-regression]

# Dependency graph
requires:
  - phase: 335-impl-the-one-batched-contract-diff-whale-afsub-mintdiv-if-re
    provides: |
      The migrated AfKingSubscription.t.sol carrying the v50.0 pass-eviction-OR-refresh shape
      (sweep-while-valid / evict-at-crossing-no-pass / refresh-at-crossing-with-pass /
      OPEN-E re-attest / SUB-07 cancel-tombstone / swap-pop membership invariant) — and the
      non-crossing scaffold testNonCrossingPassHolderBuysWithoutRefresh at lines :182-199 used
      as the analog for staging.
  - phase: 334-spec-design-lock-mintdiv-reachability-proof-rngaudit-structu
    provides: |
      D-11 lazyPassHorizon view + the AFSUB-02 design lock — the non-crossing branch is a
      pure stored-field compare on Sub.validThroughLevel; the external pass read happens
      ONLY inside the crossing block (AfKing.sol:628).
  - phase: 336-tst-equivalence-freeze-safety-divergence-repro-non-widening-
    provides: |
      336-CONTEXT.md D-TST02-02 (vm.expectCall(count:0) oracle decision) +
      336-RESEARCH.md §4 / Pitfall 1 (staging-order trap) +
      336-PATTERNS.md §"D-TST02-02 addition pattern".
provides:
  - First-in-tree `vm.expectCall(IGame.lazyPassHorizon.selector, ..., 0)` oracle test in test/fuzz/AfKingSubscription.t.sol
  - Empirical attestation that the non-crossing AfKing autoBuy iteration performs ZERO external pass-horizon reads (closes the load-bearing TST-02 D-TST02-02 gap)
  - Re-attestation of the GASOPT-05-class no-regression invariant from v49 (no per-iter external pass read crept back in under AFSUB-02)
affects: [336-05, 336-06, 337, 338]

# Tech tracking
tech-stack:
  added: ["vm.expectCall cheatcode usage (forge-std) — first introduction into the project's test tree"]
  patterns:
    - "Hot-path-accurate no-call oracle: vm.expectCall(target, abi.encodeWithSelector(SEL), 0) with strict staging order"

key-files:
  created: []
  modified:
    - test/fuzz/AfKingSubscription.t.sol  # +1 import (IGame), +1 test function (~50 lines incl. docstring)

key-decisions:
  - "Honored Pitfall 1 staging-order: STAGE → vm.expectCall → vm.prank → autoBuy with NO statements between expectCall and autoBuy invocation."
  - "Used selector-only abi.encodeWithSelector encoding (matches ANY (address) arg) so any lazyPassHorizon call during the autoBuy sweep is counted, not just a specific player."
  - "Reused the existing _grantDeityPass / _subscribeTicketMode / _approveKeeper / _fundPool helpers verbatim (deity sentinel uint24.max guarantees non-crossing for the game's lifetime)."
  - "Added the IGame import alongside the existing imports rather than re-declaring a local minimal interface — IGame is the canonical interface AfKing itself uses, no shadowing risk in this file."

patterns-established:
  - "First-in-tree vm.expectCall pattern: documented Pitfall 1 staging-order in the test docstring so future TST authors can mirror the shape without re-deriving the trap."

requirements-completed: [TST-02]

# Metrics
duration: 8min
completed: 2026-05-28
---

# Phase 336 Plan 04: TST-02 D-TST02-02 vm.expectCall(count:0) no-SLOAD oracle — Summary

**First-in-tree vm.expectCall(IGame.lazyPassHorizon.selector, count:0) oracle empirically proving the non-crossing AfKing autoBuy iteration performs ZERO external pass-horizon reads (AFSUB-02 hot-path accurate, GASOPT-05-class no-regression invariant re-attested).**

## Performance

- **Duration:** ~8 min
- **Started:** 2026-05-28
- **Completed:** 2026-05-28
- **Tasks:** 1 / 1
- **Files modified:** 1

## Accomplishments

- Closed the explicit TST-02 D-TST02-02 oracle gap with the load-bearing no-SLOAD assertion the 4 migrated AfKing test files left for 336.
- Introduced the project's FIRST `vm.expectCall` usage (RESEARCH §Summary finding 1 — `grep -rn "vm.expectCall" test/` was previously empty for code invocations) without breaking adjacent tests.
- Empirically re-attested the AFSUB-02 hot-path invariant: when `currentLevel <= sub.validThroughLevel`, the autoBuy loop takes the cheap stored-field branch and never executes the `GAME.lazyPassHorizon(player)` call at AfKing.sol:628.
- Zero `contracts/*.sol` mutation (D-TST04-04 honored — `git diff e756a6f3 -- contracts/` returns empty).

## Task Commits

Each task was committed atomically:

1. **Task 1: Add testNonCrossingPathPerformsZeroLazyPassHorizonSloads** — `test(336-04)` (see git log for the per-task hash)

_Note: TDD-shape task — the RED step is implicit (the cheatcode auto-verifies; if the oracle line were placed AFTER `afKing.autoBuy(50)` it would fail vacuously per Pitfall 1; if the contract regressed and a non-crossing iteration started reading `lazyPassHorizon` the test would fail with `counted N of expected 0 calls`). The single commit lands the new test in its GREEN state directly because the implementation under test (AfKing.sol:627-647 at v50.0 IMPL HEAD `e756a6f3`) ALREADY satisfies the invariant — the test EMPIRICALLY PROVES it._

## Files Created/Modified

- `test/fuzz/AfKingSubscription.t.sol` — added 1 import (`{IGame} from "../../contracts/AfKing.sol"`) and 1 test function `testNonCrossingPathPerformsZeroLazyPassHorizonSloads` (~50 lines incl. multi-paragraph docstring documenting TST-02 D-TST02-02 intent, the crossing-site cite, the first-in-tree marker, and the Pitfall 1 mitigation).

## Decisions Made

- **Cheatcode encoding:** used `abi.encodeWithSelector(IGame.lazyPassHorizon.selector)` (selector-only, matches ANY (address) arg) over `abi.encodeCall(IGame.lazyPassHorizon, (someAddr))` (selector + specific arg). The selector-only form is the strictly stronger oracle — counts ALL `lazyPassHorizon` calls during the sweep regardless of which player they target.
- **Staging order:** chosen exactly per Pitfall 1 — STAGE (grant deity / subscribe / approve / fund) FIRST, THEN `vm.expectCall(..., 0)`, THEN `vm.prank`, THEN `afKing.autoBuy(50)`. Verified the cheatcode line is on the line BEFORE the `vm.prank` and there are no statements between the cheatcode and the autoBuy invocation.
- **Insertion point:** placed immediately after `testNonCrossingPassHolderBuysWithoutRefresh` (the closest analog), so reviewers reading the file find the two non-crossing tests adjacent.
- **Docstring scope:** included the FIRST-IN-TREE marker plus the staging-order trap explanation in the docstring so future TST authors mirroring this pattern see the trap without needing to re-read RESEARCH.md.

## Deviations from Plan

None — plan executed exactly as written. The plan's `<action>` block specified the exact 5-step shape (STAGE → expectCall → prank → autoBuy → end) and the `IGame` import addition; both landed verbatim. No Rule-1/2/3/4 triggers.

## Verification

**Per-task verification** (the plan's `<verify><automated>` command):

```
forge test --match-path test/fuzz/AfKingSubscription.t.sol --match-test testNonCrossingPathPerformsZeroLazyPassHorizonSloads -vv
```

Result: **PASS** (gas 675_203, 6.38ms suite time).

**Full-file verification:** all 10 tests in `AfKingSubscription.t.sol` PASS (the 9 pre-existing + the 1 new oracle). No regression in adjacent tests:

| Test | Status |
|------|--------|
| testAutoBuyZeroMaxCountUsesDefaultBatch | PASS |
| testCrossingNoPassEvictedViaTombstone | PASS |
| testCrossingPassHolderRefreshedNotEvicted | PASS |
| testDoWorkEmitsExactlyOneBuyBounty | PASS |
| testNonCrossingPassHolderBuysWithoutRefresh | PASS (unchanged) |
| testNonCrossingPathPerformsZeroLazyPassHorizonSloads | **PASS (NEW)** |
| testRevokeDoesNotStopActiveSubButDefundDoes | PASS |
| testSubscribeNoBurnieChargeRegardlessOfPass | PASS |
| testUnapprovedFundingSourceRefusedThenHonored | PASS |
| testZeroBuyAutoBuyIsNoOp | PASS |

**Acceptance-criteria mechanical checks:**

| Criterion | Result |
|-----------|--------|
| `forge build` exits 0 | EXIT=0 ✓ |
| `grep -c "testNonCrossingPathPerformsZeroLazyPassHorizonSloads" test/fuzz/AfKingSubscription.t.sol` ≥ 1 | 1 ✓ |
| `grep -c "vm.expectCall" test/fuzz/AfKingSubscription.t.sol` ≥ 1 (with 1 actual code invocation; the other matches are docstring references to the cheatcode name) | 5 total (1 code + 4 docstring) ✓ |
| `grep -rn "vm.expectCall" test/` whole-tree code invocations | 1 actual code invocation (the new oracle) ✓ |
| `grep -c "lazyPassHorizon.selector" test/fuzz/AfKingSubscription.t.sol` ≥ 1 | 1 ✓ |
| `forge test --match-test testNonCrossingPathPerformsZeroLazyPassHorizonSloads -vv` EXITS 0 | EXIT=0, PASS ✓ |
| Pre-existing `testNonCrossingPassHolderBuysWithoutRefresh` still PASSES | PASS ✓ |
| `git diff e756a6f3 -- contracts/` returns empty | 0 lines ✓ |
| Strict staging-order: last staging call before `vm.expectCall` is `_fundPool`; first line after `vm.expectCall(...)` block is `vm.prank(...)`; next is `afKing.autoBuy(50)` | ✓ (verified in file body lines :230-:248) |

## Issues Encountered

None.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- **Wave 5 (336-05)** ready to proceed: TST-03 cross-path equality test for MINTDIV-02 (the byte-identical-traits-across-split regression). The pattern-mapper picks the file home (likely a new `test/fuzz/MintModuleDivergenceAcrossSplit.t.sol`).
- **Wave 6 (336-06)** TST-04 NON-WIDENING ledger remains the autonomous:false USER-gated terminal commit per D-CC-03.
- **No blockers** for the remaining 336 waves. The first-in-tree `vm.expectCall` pattern is now precedent for any future TST that needs a hot-path call-count oracle.

---

## Self-Check: PASSED

- File `test/fuzz/AfKingSubscription.t.sol` exists and contains the new test function (verified via grep above).
- The 1 atomic commit will be made together with this SUMMARY per D-CC-01 (sequential-on-main, no-worktrees, normal commit with hooks — per the orchestrator's sequential_execution directive).
- All acceptance criteria mechanically verified above; all 10 tests in the file pass.

---

*Phase: 336-tst-equivalence-freeze-safety-divergence-repro-non-widening-*
*Completed: 2026-05-28*
