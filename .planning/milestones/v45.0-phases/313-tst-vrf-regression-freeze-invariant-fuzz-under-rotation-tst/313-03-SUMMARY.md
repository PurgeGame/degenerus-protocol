---
phase: 313-tst-vrf-regression-freeze-invariant-fuzz-under-rotation-tst
plan: 03
subsystem: vrf-rotation-freeze-invariant
tags: [solidity, foundry, chainlink-vrf, vrf-rotation, rng-lock, freeze-invariant, fuzz, determinism, degenerus]
requirements: [VTST-03]
dependency_graph:
  requires:
    - "Phase 312 fix at contract HEAD a303ae18 (AdvanceModule updateVrfCoordinatorAndSub re-issue-in-flight + :1793 rawFulfillRandomWords requestId guard)"
    - "test/fuzz/RngLockDeterminism.t.sol (v43 canonical freeze-invariant harness — pattern source, NOT modified)"
    - "test/fuzz/VrfRotationLiveness.t.sol (313-02 — slot/helper conventions reused: slots 37/38, _advanceTolerant, _rotateTo->_rotateMidWindow, _setupForMidDayRng, {0,1} exclusion)"
  provides:
    - "test/fuzz/RngLockRotationDeterminism.t.sol — VTST-03 freeze-invariant fuzz under rotation: perturbed-rotation vs no-rotation byte-identical VRF-derived output (daily + mid-day branches)"
  affects:
    - "Phase 313 plan 06 (suite-verify) — adds RngLockRotationDeterminism to the green-suite count"
tech_stack:
  added: []
  patterns:
    - "v43 snapshot/revert (_snapshotPreLock/_revertToPreLock) + byte-identity-digest (_assertVrfOutputByteIdentity = assertEq) comparison shape"
    - "Rotation-as-perturbation: updateVrfCoordinatorAndSub mid-window, deliver SAME word on the re-issued request on the NEW coordinator (newVRF.lastRequestId())"
    - "_advanceTolerant catches NotTimeYet only, re-throws RngNotReady verbatim so a defect mode fails the test naturally"
key_files:
  created:
    - "test/fuzz/RngLockRotationDeterminism.t.sol"
  modified: []
decisions:
  - "Used authoritative storage slots 37 (lootboxRngPacked / LR_INDEX) and 38 (lootboxRngWordByIndex), NOT the drifted 38/39 in LootboxRngLifecycle.t.sol"
  - "Daily branch excludes vrfWord ∈ {0,1} (0 zero-guarded to 1 at :1796; 1 is the rngGate sentinel at :298 that livelocks the drain); mid-day branch excludes only 0 (mid-day write is not subject to the daily rngGate==1 sentinel, so 1 is a legal mid-day word)"
  - "_revertToPreLock resets _activeVRF + _lastFulfilledReqId so the baseline run delivers on the ORIGINAL coordinator after vm.revertTo"
  - "rotSeed fuzzes newKeyHash (bytes32(seed)) AND newSubId (seed%4 burned subscriptions) — the freeze invariant requires neither to affect the VRF-derived digest"
metrics:
  duration: "~9 min"
  completed: "2026-05-23"
  tasks: 2
  files: 1
  fuzz_runs: "1000 per function (2 functions)"
---

# Phase 313 Plan 03: Freeze-Invariant Fuzz Under Rotation Summary

VTST-03 (proves VRF-03): a new additive Foundry fuzz harness asserting that an emergency VRF coordinator/subscription rotation injected between a VRF request and its fulfilment yields a VRF-derived output byte-identical to the no-rotation baseline given the SAME delivered word — for both the daily and mid-day branches — extending the v43 RngLockDeterminism snapshot/revert + byte-identity-digest pattern, with zero contracts/ mutation.

## What Was Built

`test/fuzz/RngLockRotationDeterminism.t.sol` (`contract RngLockRotationDeterminism is DeployProtocol`), two fuzz functions, 1000 runs each:

- **`testFuzz_RotationFreezeInvariant_Daily(uint256 vrfWord, uint256 rotSeed)`** — From a common pre-request snapshot: Run A fires the daily VRF request, rotates the coordinator mid-window via `updateVrfCoordinatorAndSub` (the `rngWordCurrent==0` daily re-issue branch at AdvanceModule:1733), delivers `vrfWord` on the NEW coordinator's re-issued request (`newVRF.lastRequestId()`), drains, captures a digest over `(currentDayView, rngWordForDay(today), rngWordCurrent)`. Run B reverts and delivers the SAME `vrfWord` on the ORIGINAL coordinator with no rotation. `assertEq(digestA, digestB)`.

- **`testFuzz_RotationFreezeInvariant_MidDay(uint256 vrfWord, uint256 rotSeed)`** — From a common pre-mid-day-request snapshot (after `_setupForMidDayRng`): Run A fires `requestLootboxRng` (buffer swap sets `LR_MID_DAY=1`, reserves slot N), rotates mid-flight (the `LR_MID_DAY!=0` branch at :1726 preserves `LR_INDEX`), delivers `vrfWord` on the NEW coordinator (mid-day write at :1804 lands in the preserved slot N), and asserts `lootboxRngWordByIndex[N] == vrfWord`. Run B reverts and delivers the SAME `vrfWord` on the ORIGINAL coordinator with no rotation. Asserts the reserved index N is identical across runs (LR_INDEX frozen) AND `keccak(N, lootboxRngWordByIndex[N])` byte-identical across runs.

The harness copies the v43 file-local helpers by semantics (slot constants, `_completeDay`, `_readRngWordCurrent`/`_readVrfRequestId`/`_readLootboxRngIndex`/`_lootboxRngWord`, `_advanceToVrfRequestBoundary`, `_deliverMockVrf`, `_snapshotPreLock`/`_revertToPreLock`/`_assertVrfOutputByteIdentity`) because they are file-local in `RngLockDeterminism.t.sol` and cannot be imported. Helpers are upgraded with the 313-02 active-coordinator (`_coord`/`_activeVRF`) + `_advanceTolerant` (NotTimeYet-only catch) discipline so they work pre- and post-rotation.

## Freeze-Invariant Lens (v45-vrf-freeze-invariant, 311-SPEC §3)

The abandoned old in-flight word is rejected by the `rawFulfillRandomWords:1793` guard (`requestId != vrfRequestId || rngWordCurrent != 0`) and never consumed; the re-issued word is the only word consumed this cycle. Admin rotation is EXEMPT-class vs PLAYERS. The byte-identity assertion proves rotation introduces no change to the consumed VRF-derived output beyond the legitimate VRF word substitution — given the SAME delivered word, rotation vs no-rotation yields identical outputs. `rotSeed` fuzzes the rotation `newKeyHash`/`newSubId` (which must NOT affect the output), so any digest drift is a real freeze-invariant violation, not flakiness.

## Verification

- `forge build` exits 0.
- `forge test --match-contract RngLockRotationDeterminism` exits 0 — both fuzz tests PASS, 1000 runs each (non-zero; vm.assume filters do not starve iterations).
- `git diff --stat` touches ONLY `test/fuzz/RngLockRotationDeterminism.t.sol`; `test/fuzz/RngLockDeterminism.t.sol` (v43 harness) NOT modified (`git status --short` shows 0 changes to it); ZERO contracts/ change (0 changes under `contracts/`).

## Threat Register Disposition (test-integrity)

- **T-313-03-01 (digest captures the wrong word)** — mitigated: both runs deliver the SAME `vrfWord`; the perturbed run delivers it via the re-issued request on the new coordinator (`newVRF.lastRequestId()`), so the digest reflects the consumed-this-cycle output, not the abandoned old word (rejected by :1793). The mid-day function additionally asserts the reserved slot is empty (`== 0`) before fulfilment, defeating a pre-satisfied tautology.
- **T-313-03-02 (false-pass via starved fuzz)** — mitigated: both functions report 1000 runs; the common-case setup is reachable so the byte-identity assertion executes.
- **T-313-03-03 (flaky fuzz)** — mitigated: determinism enforced by delivering the SAME `vrfWord` in both runs and `vm.snapshot`/`vm.revertTo` sharing identical pre-request state; `rotSeed` only varies the rotation config.

## Deviations from Plan

None — plan executed exactly as written. The plan suggested copying helpers verbatim; the active-coordinator/`_advanceTolerant` upgrade is required because the baseline-vs-perturbed comparison must fulfil on different coordinators, and is the same author-team convention used in 313-02 (consistent with the plan's phase-critical-context note pointing to the 313-02 helper shapes). The plan's behavior block mentioned `vm.assume(false)` filters mirroring the harness; these are implemented as `if (...) vm.assume(false);` guards and runs remained non-zero (1000 each).

## Known Stubs

None. Both fuzz functions execute the byte-identity assertion on the reachable common case (1000 runs each); no placeholder helpers return hardcoded values that bypass the assertion.

## Self-Check: PASSED

- FOUND: test/fuzz/RngLockRotationDeterminism.t.sol
- FOUND: commit afa1ac22 (Task 1 daily branch)
- FOUND: commit c4d7f627 (Task 2 mid-day branch)
- CONFIRMED: test/fuzz/RngLockDeterminism.t.sol (v43 harness) NOT modified
- CONFIRMED: ZERO contracts/ mutation
