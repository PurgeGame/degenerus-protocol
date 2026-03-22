---
phase: 64-lootbox-rng-lifecycle
plan: 01
subsystem: testing
tags: [foundry, fuzz, vrf, lootbox, rng, entropy, solidity]

# Dependency graph
requires:
  - phase: 63-vrf-request-fulfillment-core
    provides: VRFCore.t.sol pattern, DeployProtocol/VRFHandler helpers, storage slot verification
provides:
  - 21 Foundry fuzz/unit tests covering lootbox RNG index lifecycle (LBOX-01 through LBOX-05)
  - Verified index mutation correctness across all 4 mutation/non-mutation sites
  - Verified word-to-index correctness across all 5 write paths
  - Verified zero-state guards at 3 VRF word injection points
  - Verified entropy uniqueness via keccak256 preimage analysis
  - Full purchase-to-open lifecycle traced end-to-end
affects: [64-02 findings document, future VRF stall edge case tests]

# Tech tracking
tech-stack:
  added: []
  patterns: [lootbox purchase helper (_makePurchase), lootboxRngWord public getter usage, lootboxStatus view for amount verification, absolute timestamp pattern for multi-day tests]

key-files:
  created: [test/fuzz/LootboxRngLifecycle.t.sol]
  modified: []

key-decisions:
  - "D-01: Used game.lootboxRngWord(index) public getter instead of vm.load storage slot computation for reading lootboxRngWordByIndex -- cleaner and less brittle"
  - "D-02: Used game.lootboxStatus(player, index) to read packed lootboxEth amounts for entropy verification -- avoids raw storage slot computation for nested mapping"
  - "D-03: Backfill tests require 2+ gap days (warp to day 4 after day 1 complete) because _backfillOrphanedLootboxIndices only fires in the gap day code path (day > dailyIdx + 1)"
  - "D-04: Entropy uniqueness tests verify keccak256 preimage distinctness (the contract's actual formula) rather than end-to-end prize outcome comparison"

patterns-established:
  - "_makePurchase helper: standardized lootbox purchase with vm.deal + vm.prank + game.purchase"
  - "Entropy preimage verification: compute keccak256(abi.encode(rngWord, player, day, amount)) in test and assert distinctness"
  - "Backfill test pattern: day 1 complete -> day 2 VRF request -> coordinator swap -> warp to day 4 -> complete day (triggers backfill via gap detection)"

requirements-completed: [LBOX-01, LBOX-02, LBOX-03, LBOX-04, LBOX-05]

# Metrics
duration: 8min
completed: 2026-03-22
---

# Phase 64 Plan 01: Lootbox RNG Lifecycle Summary

**21 Foundry fuzz/unit tests proving lootbox RNG index lifecycle correctness: 1:1 index-to-word mapping, zero-state guards at all VRF injection points, per-player entropy uniqueness via keccak256 preimage analysis, and full purchase-to-open lifecycle trace**

## Performance

- **Duration:** 8 min
- **Started:** 2026-03-22T16:24:31Z
- **Completed:** 2026-03-22T16:32:46Z
- **Tasks:** 2
- **Files created:** 1 (test/fuzz/LootboxRngLifecycle.t.sol -- 693 lines)

## Accomplishments

- LBOX-01: 5 tests verify index mutation behavior -- increments on fresh daily and mid-day requests, no increment on retry or coordinator swap, sequential increments across N days
- LBOX-02: 5 tests verify word-to-index correctness -- daily fulfillment, mid-day fulfillment, stale day redirect, orphaned index backfill, idempotent guard
- LBOX-03: 3 tests verify zero-state guards -- rawFulfillRandomWords(word=0)->1, backfill keccak256 path nonzero, mid-day rawFulfill(word=0)->1
- LBOX-04: 4 tests verify entropy uniqueness -- different players produce different entropy, different amounts, different days, and accumulation changes preimage
- LBOX-05: 4 tests trace full lifecycle -- daily purchase->VRF->open, mid-day purchase->request->VRF->open, RngNotReady revert on unfulfilled, multiple indices with correct respective words

## Task Commits

Each task was committed atomically:

1. **Task 1: LBOX-01 + LBOX-02 + LBOX-03 tests** - `e15157a5` (test)
2. **Task 2: LBOX-04 + LBOX-05 tests** - `aa4a3073` (test)

## Files Created/Modified

- `test/fuzz/LootboxRngLifecycle.t.sol` - 21 fuzz/unit tests for lootbox RNG index lifecycle covering all 5 LBOX requirements

## Decisions Made

- **D-01:** Used `game.lootboxRngWord(index)` public getter instead of raw `vm.load` storage slot computation for reading `lootboxRngWordByIndex` -- cleaner and less brittle than computing mapping slot offsets
- **D-02:** Used `game.lootboxStatus(player, index)` to read packed `lootboxEth` amounts for entropy verification -- avoids raw storage slot computation for doubly-nested mapping
- **D-03:** Backfill tests require 2+ gap days (warp to day 4 after day 1 complete) because `_backfillOrphanedLootboxIndices` only fires in the gap day code path (`day > dailyIdx + 1`), not when the next day is sequential
- **D-04:** Entropy uniqueness tests verify keccak256 preimage distinctness using the contract's actual formula `keccak256(abi.encode(rngWord, player, day, amount))` rather than comparing end-to-end prize outcomes (which depend on game state)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed backfill test gap day requirement**
- **Found during:** Task 1 (LBOX-02 test_wordWriteBackfill)
- **Issue:** Initial test warped only +1 day after coordinator swap, but `_backfillOrphanedLootboxIndices` only fires when `day > dailyIdx + 1` (gap day detection). Sequential day processing does not trigger backfill.
- **Fix:** Changed to use absolute timestamps with 2-day gap (warp to day 4 after day 1 complete) to ensure gap day path fires and triggers orphaned lootbox index backfill
- **Files modified:** test/fuzz/LootboxRngLifecycle.t.sol
- **Verification:** Both backfill tests pass (test_wordWriteBackfill, test_zeroGuardBackfill)
- **Committed in:** e15157a5 (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 bug fix)
**Impact on plan:** Auto-fix was necessary for correctness of the backfill test pattern. No scope creep.

## Issues Encountered

None -- all tests compiled and passed after the backfill gap-day fix.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- All 21 tests pass with 1000 fuzz runs
- Zero regressions in existing VRFCore.t.sol (22 tests still passing)
- Ready for Plan 02 (findings document) which will reference these test results
- LBOX-03 finding confirmed: `_getHistoricalRngFallback` has no explicit zero guard (INFO-level, probability ~2^-256) -- to be documented in findings

## Self-Check: PASSED

- [x] test/fuzz/LootboxRngLifecycle.t.sol exists (693 lines)
- [x] Task 1 commit e15157a5 exists
- [x] Task 2 commit aa4a3073 exists
- [x] 64-01-SUMMARY.md exists

---
*Phase: 64-lootbox-rng-lifecycle*
*Completed: 2026-03-22*
