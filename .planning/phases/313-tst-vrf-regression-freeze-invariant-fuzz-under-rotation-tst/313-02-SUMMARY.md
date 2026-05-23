---
phase: 313-tst-vrf-regression-freeze-invariant-fuzz-under-rotation-tst
plan: 02
subsystem: testing
tags: [solidity, foundry, chainlink-vrf, vrf-rotation, liveness, rng-lock, degenerus]

# Dependency graph
requires:
  - phase: 312-impl-vrf-rotation-fix-single-batched-user-approved-diff-impl
    provides: "AdvanceModule updateVrfCoordinatorAndSub 3-branch re-issue (mid-day / daily / short-circuit) + retryLootboxRng failsafe — the contract behavior these tests exercise"
  - phase: 313-tst-vrf-regression-freeze-invariant-fuzz-under-rotation-tst (313-01)
    provides: "VrfRotationOrphanIndex.t.sol authoritative-slot helper shapes (_setupForMidDayRng, _rotateMidFlight, slot 37/38 reads) modeled directly here"
provides:
  - "test/fuzz/VrfRotationLiveness.t.sol — VTST-02 liveness-after-rotation Foundry contract (6 tests, proves VRF-02)"
  - "Positive-outcome liveness pattern for rotation tests: drain reaches rngLocked()==false / day word set / re-issue fires on the new coordinator; RngNotReady() re-thrown not caught"
  - "Sentinel-collision discovery: rngWord==1 is the rngGate 'request new RNG' sentinel (AdvanceModule:298) — daily fuzz words must exclude {0,1}"
affects: [313-03, 313-05, 313-06, 314-sweep, 315-terminal]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "POSITIVE-outcome liveness assertion (no silent negative): drain loop reaches rngLocked()==false, day word set, re-issue lastRequestId()!=0 on the NEW coordinator"
    - "Selective revert tolerance: _advanceTolerant() breaks on NotTimeYet() but RE-THROWS RngNotReady() verbatim via assembly so the defect mode fails the test naturally"
    - "Active-coordinator tracking (_activeVRF/_coord) so drain helpers fulfil on the live coordinator after a rotation"

key-files:
  created:
    - "test/fuzz/VrfRotationLiveness.t.sol"
  modified: []

key-decisions:
  - "Single-file deliverable committed once (both plan tasks verified together) — splitting an already-complete one-file artifact into two commits would be artificial"
  - "Fuzz guards exclude {0,1}: rngWord==1 collides with the rngGate sentinel (AdvanceModule:298); real 256-bit VRF words collide with {0,1} only with cryptographically negligible probability"
  - "_advanceTolerant() catches ONLY NotTimeYet() and re-throws everything else (esp. RngNotReady) — preserves T-313-02-01: liveness never silently asserted"
  - "Used authoritative storage slots 37 (lootboxRngPacked) / 38 (lootboxRngWordByIndex), not the drifted analog 38/39"

patterns-established:
  - "Rotation-branch liveness coverage: mid-day re-issue / daily-not-delivered re-issue / daily-delivered short-circuit / nothing-in-flight no-op + retryLootboxRng failsafe"

requirements-completed: [VTST-02]

# Metrics
duration: ~50min
completed: 2026-05-23
---

# Phase 313 Plan 02: VTST-02 Liveness-After-Rotation Fuzz Summary

**`VrfRotationLiveness.t.sol` proves the protocol stays live after an emergency VRF rotation — all three `updateVrfCoordinatorAndSub` branches (mid-day re-issue, daily re-issue, delivered short-circuit / no-op) plus the `retryLootboxRng` failsafe drain to `rngLocked()==false` with no permanent `RngNotReady()` revert (VRF-02 by VTST-02).**

## Performance

- **Duration:** ~50 min
- **Completed:** 2026-05-23T10:27Z
- **Tasks:** 2 (TDD, combined into one verified single-file artifact)
- **Files modified:** 1 (created)

## Accomplishments
- 6 fuzz tests, all PASS at 1000 runs each, ZERO `contracts/` mutation (audit-only per D-43N-AUDIT-ONLY-01).
- Task 1 — rotation-branch liveness: mid-day re-issue lands a real word in the reserved index `[N]` so the `:269` drain gate unblocks; daily re-issue fills `rngWordCurrent` so the `:271` gate unblocks and the day completes; `rngWordCurrent!=0` short-circuit preserves the delivered word with no re-issue; nothing-in-flight rotation is a pure config repoint.
- Task 2 — `retryLootboxRng` failsafe: a stalled re-issue on the NEW coordinator is rescued after `MIDDAY_RNG_RETRY_TIMEOUT` without double-advancing `lootboxRngIndex`; `requestLootboxRng` stays reachable (advances index + fires a request) after a completed rotation.
- Liveness proven by POSITIVE outcome only; the OLD-bug `RngNotReady()` permanent-revert mode is re-thrown by the drain helper (never swallowed), so the defect fails the test naturally.

## Task Commits

1. **Task 1 + Task 2: VrfRotationLiveness.t.sol (6 tests)** — `2f438ea2` (test)

_Both TDD tasks deliver into one file; the file was authored, built, and verified (6/6 PASS) before the single atomic test commit. No `contracts/` source exists to RED-against (audit-only) — these are characterization tests asserting the already-landed Phase 312 fix behaves correctly._

## Files Created/Modified
- `test/fuzz/VrfRotationLiveness.t.sol` — `contract VrfRotationLiveness is DeployProtocol`; 6 tests covering the 3 rotation branches + the 2 failsafe/reachability paths; authoritative-slot reads (37/38), `_activeVRF`/`_coord()` live-coordinator tracking, `_advanceTolerant()` selective revert handling.

## Decisions Made
- **Single commit for the one-file artifact.** The plan defines two TDD tasks against one file; committing the verified whole once is more honest than fabricating a half-file intermediate commit.
- **Exclude {0,1} from daily fuzz words.** Discovered during execution (see Issues): `rngWord==1` is the `rngGate` "request new RNG" sentinel, so a daily word delivered as `1` livelocks the drain. Excluded `{0,1}` with an explicit rationale comment on every guard.
- **Authoritative storage slots 37/38** per the phase-critical-context note (the analog `LootboxRngLifecycle.t.sol`/`StallResilience.t.sol` use drifted 38/39 and are among the regressions plan 313-05 migrates).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Excluded the rngGate sentinel value `1` from daily fuzz words**
- **Found during:** Task 1 (`test_dailyRotation_liveness` / `test_dailyAlreadyDelivered_shortCircuit` initially failed at "rngLocked()==false")
- **Issue:** The plan's `vm.assume(vrfWord != 0)` was insufficient. `rawFulfillRandomWords` converts a delivered `0`→`1`, and `rngGate` (AdvanceModule:298) treats `rngWord==1` as the "request new RNG" sentinel. A daily word of `1` therefore livelocks the post-fulfilment drain (never unlocks). Confirmed with a throwaway scratch test: word `2`/`0xCAFE` unlock in 1 advance, word `1` never unlocks.
- **Fix:** Strengthened every fuzz guard to `vm.assume(vrfWord != 0 && vrfWord != 1)` (plus `(vrfWord ^ 0xBEEF) != 1` where a derived next-day word is used), each with a comment citing AdvanceModule:298. This is a test-harness guard, not a contract defect — real 256-bit VRF words collide with `{0,1}` with negligible probability.
- **Files modified:** test/fuzz/VrfRotationLiveness.t.sol
- **Verification:** All daily-branch tests PASS at 1000 runs.
- **Committed in:** `2f438ea2`

**2. [Rule 3 - Blocking] Selective NotTimeYet() tolerance in drain helpers (RngNotReady NOT caught)**
- **Found during:** Task 2 (`test_requestLootboxRngReachableAfterRotation` failed with `NotTimeYet()`)
- **Issue:** After a day's work fully drains for a wall-clock instant, an extra `advanceGame()` reverts `NotTimeYet()` (AdvanceModule:238) while `rngLocked()` may still read true momentarily. The bare drain loop propagated this as a test failure.
- **Fix:** Added `_advanceTolerant()` which catches ONLY the `NotTimeYet()` selector and re-throws every other revert verbatim via `assembly { revert(...) }`. Critically, `RngNotReady()` — the OLD-bug permanent-revert failure mode — is NOT caught, preserving threat mitigation T-313-02-01 (liveness is never silently asserted).
- **Files modified:** test/fuzz/VrfRotationLiveness.t.sol
- **Verification:** All 6 tests PASS at 1000 runs; the daily/short-circuit tests still assert `rngLocked()==false` (drain genuinely reaches unlocked, not bypassed).
- **Committed in:** `2f438ea2`

**3. [Rule 1 - Bug] Fixed two malformed expressions written in the first draft**
- **Found during:** Task 2 authoring (pre-build self-review)
- **Issue:** `vrfWord ^ 0xBEEF == 0 ? ...` had wrong operator precedence (`^` binds looser than `==`), and `newVRF.fundSubscription(... ? 1 : 1, ...)` was a no-op ternary.
- **Fix:** Replaced with an explicit `nextDayWord` local + zero-guard, and a plain `fundSubscription(1, ...)` with a comment that fresh coordinators assign subId 1.
- **Files modified:** test/fuzz/VrfRotationLiveness.t.sol
- **Verification:** Build exit 0; tests pass.
- **Committed in:** `2f438ea2`

---

**Total deviations:** 3 auto-fixed (2 blocking, 1 bug)
**Impact on plan:** All auto-fixes were necessary for the tests to compile/pass correctly while preserving the plan's threat mitigations (especially T-313-02-01: RngNotReady is re-thrown, never swallowed). No scope creep — the file delivers exactly the six tests the plan specifies.

## Issues Encountered
- **rngGate sentinel livelock (resolved):** Diagnosed via a throwaway scratch test (created and removed in-session) that isolated the rotation flow and varied the delivered word — word `1` never unlocked, words `2`/`0xCAFE` unlocked in 1 advance. Root cause: `rngWord==1` is the rngGate sentinel. Resolved by the `{0,1}` fuzz guard (Deviation 1). Note: this also means the analog `StallResilience.t.sol` and several `VRFStallEdgeCases.t.sol` tests currently fail at HEAD (RngNotReady) for the post-fix preserve+re-issue semantics — those are the documented 17 fix-induced regressions plan 313-05 migrates, not regressions introduced here.

## Threat Flags
None — zero `contracts/` mutation; no new production surface. Test-integrity threats T-313-02-01/02/03 are mitigated as planned (positive-outcome liveness, new-coordinator `lastRequestId()` assertions, deterministic timeout boundary anchored to `rngRequestTime + MIDDAY_RNG_RETRY_TIMEOUT`).

## Known Stubs
None — every test asserts contract-derived state read from authoritative storage slots; no hardcoded/placeholder values flow to assertions.

## User Setup Required
None.

## Next Phase Readiness
- VTST-02 (VRF-02) coverage complete and passing. Ready for 313-03 (freeze-invariant fuzz), 313-04 (wireVrf one-shot), 313-05 (regression migration of the 17 fix-induced regressions), and 313-06 (suite-wide verify + AGENT-COMMIT).
- The `_advanceTolerant()` / `_activeVRF` / authoritative-slot helper shapes here are reusable models for 313-03/05.

## Self-Check: PASSED
- `test/fuzz/VrfRotationLiveness.t.sol` — FOUND
- Commit `2f438ea2` — FOUND (HEAD)
- `forge build` exit 0; `forge test --match-contract VrfRotationLiveness` 6/6 PASS
- `git diff --name-only HEAD~1 HEAD` — ONLY test/fuzz/VrfRotationLiveness.t.sol; ZERO contracts/ change; no deletions

---
*Phase: 313-tst-vrf-regression-freeze-invariant-fuzz-under-rotation-tst*
*Completed: 2026-05-23*
