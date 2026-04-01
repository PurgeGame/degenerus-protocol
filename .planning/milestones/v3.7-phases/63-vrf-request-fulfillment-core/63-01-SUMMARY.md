---
phase: 63-vrf-request-fulfillment-core
plan: 01
subsystem: testing
tags: [foundry, fuzz, vrf, chainlink, solidity, gas-budget, rng]

# Dependency graph
requires:
  - phase: 61-stall-resilience-tests
    provides: DeployProtocol, VRFHandler, MockVRFCoordinator test infrastructure
provides:
  - 22 Foundry fuzz/unit tests proving VRF request/fulfillment correctness (VRFC-01 through VRFC-04)
  - Gas budget proof for daily and mid-day VRF callback paths (both under 300k)
  - Retry detection proof: lootboxRngIndex never double-increments across timeout retries
  - rngLockedFlag mutual exclusion proof: no daily/mid-day collision path exists
affects: [63-02, lootbox-rng-lifecycle]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Storage slot inspection via vm.load for internal state verification"
    - "Absolute timestamp warping for cross-day boundary tests"

key-files:
  created:
    - test/fuzz/VRFCore.t.sol
  modified: []

key-decisions:
  - "Storage slots verified via forge inspect (slot 4 rngWordCurrent, slot 5 vrfRequestId) -- research assumed slot 5/6"
  - "Cross-day tests use absolute timestamps to avoid Foundry vm.warp relative-timestamp subtlety"
  - "Gas budget tests measure full mock overhead (28k total) confirming ~6x safety margin on 300k limit"

patterns-established:
  - "vm.load storage inspection pattern for DegenerusGame packed slot 0 (rngRequestTime at bits 96-143)"
  - "Absolute day boundary timestamps (N * 86400) for reliable cross-day tests"

requirements-completed: [VRFC-01, VRFC-02, VRFC-03, VRFC-04]

# Metrics
duration: 11min
completed: 2026-03-22
---

# Phase 63 Plan 01: VRF Request/Fulfillment Core Summary

**22 Foundry fuzz/unit tests proving VRF callback revert-safety, gas budget, requestId lifecycle, rngLockedFlag mutual exclusion, and 12h timeout retry correctness across all 4 VRFC requirements**

## Performance

- **Duration:** 11 min
- **Started:** 2026-03-22T15:41:53Z
- **Completed:** 2026-03-22T15:53:00Z
- **Tasks:** 2
- **Files created:** 1 (616 lines)

## Accomplishments

- All 4 VRF requirements (VRFC-01 through VRFC-04) proven by automated tests
- Callback gas budget confirmed: rawFulfillRandomWords uses ~28k gas total (daily path), well under 300k limit
- Retry detection verified: lootboxRngIndex never double-increments across 1000+ fuzz runs
- Cross-day stale word redirect proven: rngGate correctly detects requestDay < currentDay and fires fresh request
- Storage slot constants verified against forge inspect output (corrected research assumption of slots 5/6 to actual slots 4/5)

## Task Commits

Each task was committed atomically:

1. **Task 1: VRFC-01 + VRFC-02 tests** - `c912e419` (test)
   - 7 callback revert-safety and gas budget tests
   - 5 requestId lifecycle and retry detection tests
2. **Task 2: VRFC-03 + VRFC-04 tests** - `a6429f70` (test)
   - 5 mutual exclusion tests
   - 5 timeout retry tests

## Files Created/Modified

- `test/fuzz/VRFCore.t.sol` -- 22 fuzz/unit tests covering VRFC-01 through VRFC-04 with helpers for day completion, storage slot reading, coordinator swap, and mid-day RNG setup

## Test Coverage by Requirement

| Requirement | Tests | What is Proven |
|-------------|-------|----------------|
| VRFC-01 | 7 | Callback never reverts (daily, stale ID, duplicate), unauthorized sender reverts, gas < 300k (daily + midday), zero-guard stores 1 |
| VRFC-02 | 5 | vrfRequestId set on request / cleared after processing (daily + midday), fresh request increments lootboxRngIndex, retry does not, fuzz over retry scenario |
| VRFC-03 | 5 | rngLocked blocks mid-day request, mid-day does not block daily, fulfillment clears state, 15-min pre-reset guard, coordinator swap clears lock |
| VRFC-04 | 5 | 12h timeout fires retry, before 12h reverts RngNotReady, stale word discarded after retry, lootboxRngIndex preserved (fuzz), cross-day stale word redirected |

## Decisions Made

1. **Storage slots corrected from research estimates** -- Research document assumed rngWordCurrent at slot 5 and vrfRequestId at slot 6. `forge inspect DegenerusGame storage-layout` confirmed actual slots are 4 and 5 respectively (due to `currentPrizePool` at slot 2 and `prizePoolsPacked` at slot 3 preceding them).

2. **Absolute timestamps for cross-day tests** -- Relative `vm.warp(block.timestamp + 1 days)` produced unexpected results in certain test sequences. Switched to absolute timestamps (`N * 86400`) for reliable day boundary crossing.

3. **Gas measurement includes mock overhead** -- The `test_callbackGasBudget_*` tests measure gas across the full `mockVRF.fulfillRandomWords()` call (including mock bookkeeping). The 28k total (daily path) vs 300k budget confirms a ~10x safety margin. The research's opcode-level analysis of ~33k (daily) is consistent.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed storage slot constants**
- **Found during:** Task 1 (TDD RED phase)
- **Issue:** Research document assumed vrfRequestId at slot 6 and rngWordCurrent at slot 5; actual layout has them at slots 5 and 4
- **Fix:** Ran `forge inspect DegenerusGame storage-layout` to get authoritative slot numbers, updated constants
- **Files modified:** test/fuzz/VRFCore.t.sol
- **Verification:** All 12 Task 1 tests pass with corrected slot numbers

**2. [Rule 1 - Bug] Fixed arithmetic overflow in duplicate fulfillment test**
- **Found during:** Task 1 (TDD RED phase)
- **Issue:** `randomWord + 1` overflows when fuzzer provides type(uint256).max
- **Fix:** Used XOR-based different word generation (`randomWord ^ 0xDEAD`) instead of addition
- **Files modified:** test/fuzz/VRFCore.t.sol
- **Verification:** Fuzz test passes across full uint256 range including max value

**3. [Rule 1 - Bug] Fixed cross-day test using relative timestamps**
- **Found during:** Task 2 (cross-day stale word test)
- **Issue:** `vm.warp(block.timestamp + 1 days)` evaluated to same timestamp as previous warp in certain Foundry test sequences
- **Fix:** Used absolute timestamps (`2 * 86400`, `3 * 86400`) for day boundary warps
- **Files modified:** test/fuzz/VRFCore.t.sol
- **Verification:** Cross-day detection path correctly fires with absolute timestamps

---

**Total deviations:** 3 auto-fixed (3 bugs in test code)
**Impact on plan:** All auto-fixes corrected test code issues. No scope creep. Contract code untouched.

## Issues Encountered

None beyond the auto-fixed deviations above.

## User Setup Required

None - no external service configuration required.

## Known Stubs

None - all tests fully wired with real contract interactions.

## Next Phase Readiness

- VRF core requirements (VRFC-01 through VRFC-04) fully tested and proven
- Test infrastructure (helpers, storage readers) available for Plan 02 if additional VRF tests are needed
- All 22 tests pass with 1000 fuzz runs

## Self-Check: PASSED

- test/fuzz/VRFCore.t.sol: FOUND
- Commit c912e419 (Task 1): FOUND
- Commit a6429f70 (Task 2): FOUND
- 63-01-SUMMARY.md: FOUND

---
*Phase: 63-vrf-request-fulfillment-core*
*Completed: 2026-03-22*
