---
phase: 313-tst-vrf-regression-freeze-invariant-fuzz-under-rotation-tst
reviewed: 2026-05-23T12:00:00Z
depth: deep
files_reviewed: 8
files_reviewed_list:
  - test/fuzz/VrfRotationOrphanIndex.t.sol
  - test/fuzz/VrfRotationLiveness.t.sol
  - test/fuzz/RngLockRotationDeterminism.t.sol
  - test/fuzz/VrfWireOneShot.t.sol
  - test/fuzz/VRFStallEdgeCases.t.sol
  - test/fuzz/StallResilience.t.sol
  - test/fuzz/VRFCore.t.sol
  - test/fuzz/VRFPathCoverage.t.sol
findings:
  critical: 2
  warning: 3
  info: 0
  total: 5
status: issues
---

# Phase 313: Code Review Report

**Reviewed:** 2026-05-23
**Depth:** deep (cross-file, storage-slot authoritative verification)
**Files Reviewed:** 8
**Status:** issues_found

## Summary

Four new test files (VTST-01 through VTST-04) and four modified regression files were reviewed against the authoritative storage layout produced by `forge inspect DegenerusGame storage-layout`. The authoritative slots are:

| Variable | Slot |
|---|---|
| lootboxRngPacked (contains LR_INDEX in low 48 bits) | 37 |
| lootboxRngWordByIndex (mapping) | 38 |
| lootboxDay (mapping) | 39 |
| rngWordCurrent | 3 |
| vrfRequestId | 4 |

The four new VTST files (VrfRotationOrphanIndex, VrfRotationLiveness, RngLockRotationDeterminism, VrfWireOneShot) all use correct storage slots and their core assertions are contract-derived (not tautological for the security-critical arms). The phase 313 regression migration correctly fixed StallResilience's slot references and updated VRFStallEdgeCases / VRFCore assertions for the preserve+re-issue behavior.

Two pre-existing slot bugs were NOT fixed by phase 313 and remain in modified files (VRFCore, VRFPathCoverage). These bugs cause some index-preservation assertions to be trivially vacuous and one test to fail outright, undermining the regression coverage they purport to provide.

---

## Critical Issues

### CR-01: VRFCore._lootboxRngIndex() reads slot 38 (mapping root — always 0)

**File:** `test/fuzz/VRFCore.t.sol:53-54`
**Issue:** `_lootboxRngIndex()` reads `vm.load(address(game), bytes32(uint256(38)))`. Slot 38 is the `lootboxRngWordByIndex` mapping declaration slot — EVM stores nothing at the mapping root, so this always returns 0. The correct slot is 37 (`lootboxRngPacked`, whose low 48 bits are LR_INDEX). This bug was present before phase 313 and was not fixed during the phase 313 migration (StallResilience was fixed; VRFCore was not).

Consequences:
- `test_retryDetection_fresh` (line 295-302): `indexBefore = 0`, `indexAfter = 0`, `assertEq(0, 0+1)` — this test **fails** with the wrong slot. The assertion that a fresh request increments LR_INDEX by 1 is broken.
- `test_retryDetection_timeout`, `test_retryDetection_fuzz`, `test_timeoutRetry_12h`, `test_timeoutRetry_lootboxIndexPreserved_fuzz`: all preservation assertions become `assertEq(0, 0)` — trivially vacuous. A broken fix that double-incremented LR_INDEX would still pass these tests.
- `test_coordinatorSwap_clearsRngLocked` (migrated in phase 313): does not use `_lootboxRngIndex()`, so the migration itself is not tainted.

**Fix:** Change slot 38 to slot 37 in `_lootboxRngIndex()`:
```solidity
/// @dev Read lootboxRngIndex directly from storage slot 37 (low 48 bits of lootboxRngPacked).
function _lootboxRngIndex() internal view returns (uint48) {
    return uint48(uint256(vm.load(address(game), bytes32(uint256(37)))));
}
```

---

### CR-02: VRFPathCoverage reads lootboxRngIndex from slot 38 and lootboxRngWordByIndex from slot 39 — both always return 0

**File:** `test/fuzz/VRFPathCoverage.t.sol:55-63`
**Issue:** Two compounding slot errors:
1. `_lootboxRngIndex()` (line 57) reads slot 38 (mapping root, always 0) instead of slot 37.
2. `_lootboxRngWord()` (line 62) reads from slot 39 (`lootboxDay`, a nested mapping root, always 0) instead of slot 38.

These were introduced in phase 211 and were NOT corrected in phase 313 (the commit `6ad8338a` explicitly fixed `StallResilience` but left `VRFPathCoverage` with the wrong slots).

Consequences:
- `test_indexLifecycleAcrossStall_fuzz` (line 371-374): `assertTrue(_lootboxRngWord(initialIndex) != 0)` always reads 0 from the wrong slot — this test **fails unconditionally**. The index monotonicity assertions earlier in the test all become `assertEq(0, 0)` (vacuous).
- `test_gapBackfillWithMidDayPending_fuzz` (line 269-273): `assertTrue(indexAfterRecovery > indexBeforeStall)` compares `0 > 0` — always false, **always fails**.
- All `_lootboxRngIndex()` preservation checks in other tests (single-day, multi-day, max-gap) are `assertEq(0, 0)` — trivially vacuous.
- `_lootboxRngWord()` reads from `lootboxDay` (slot 39), a nested mapping; `keccak256(encode(index, 39))` is the outer mapping intermediate slot which EVM does not populate. Always 0.

**Fix:** Apply the same fix StallResilience received in phase 313:
```solidity
/// @dev Read lootboxRngIndex from lootboxRngPacked (storage slot 37, low bits = LR_INDEX).
function _lootboxRngIndex() internal view returns (uint48) {
    return uint48(uint256(vm.load(address(game), bytes32(uint256(37)))));
}

/// @dev Read lootboxRngWordByIndex[index] from storage (mapping at slot 38).
function _lootboxRngWord(uint48 index) internal view returns (uint256) {
    bytes32 slot = keccak256(abi.encode(uint256(index), uint256(38)));
    return uint256(vm.load(address(game), slot));
}
```

---

## Warnings

### WR-01: VRFStallEdgeCases._readVrfRequestId() comment says "slot 5" but SLOT_VRF_REQUEST_ID = 4

**File:** `test/fuzz/VRFStallEdgeCases.t.sol:94-96`
**Issue:** The function comment says "Read vrfRequestId directly from storage slot 5" but `SLOT_VRF_REQUEST_ID` is declared as 4 (line 16), and the authoritative layout confirms `vrfRequestId` is at slot 4. The code uses the constant (slot 4) correctly; the comment is stale and misleading.

**Fix:**
```solidity
/// @dev Read vrfRequestId directly from storage slot 4.
function _readVrfRequestId() internal view returns (uint256) {
    return uint256(vm.load(address(game), bytes32(uint256(SLOT_VRF_REQUEST_ID))));
}
```

---

### WR-02: VTST-01 pre-fix arm is tautological — vm.store(0) to a slot that is already 0

**File:** `test/fuzz/VrfRotationOrphanIndex.t.sol:185-199`
**Issue:** `test_preFix_orphanedZeroIndex_yieldsEntropyZero` calls `game.requestLootboxRng()` (which reserves but does NOT fill slot N), then `vm.store(keccak256(encode(reservedIndex, 38)), bytes32(0))` to write 0 to `lootboxRngWordByIndex[reservedIndex]`. That slot is already 0 (no `rawFulfillRandomWords` has been called). The `vm.store(0)` is a no-op, and the subsequent `assertEq(_readLootboxWord(reservedIndex), 0)` is `assertEq(0, 0)` — provable without any contract interaction.

The test does not prove that a pre-fix rotation left the slot at zero; it only proves that an unfulfilled reservation is zero (trivially true). The security-critical proof is entirely in the post-fix arm (`test_postFix_midDayRotation_landsRealWordInOrphanedIndex`), which is sound and contract-derived. The pre-fix arm is documentation-only but labeled as if it exercises a code path.

**Fix (low priority):** Add a comment making the tautological nature explicit, or restructure to use a vm.store of a NONZERO sentinel to simulate the orphaned state (then assert it remains nonzero after rotate = old behavior, contrasting with the post-fix arm that changes it to the delivered word). Alternatively, remove the misleading pre-fix arm and rely solely on the post-fix arm for security assertions.

---

### WR-03: VTST-04 test_structuralOneShot_wireVrfOnlyFromConstructor always falls to catch branch — structural invariant unproven

**File:** `test/fuzz/VrfWireOneShot.t.sol:113-131`
**Issue:** `foundry.toml` has no `fs_permissions` entry, so `vm.readFile("contracts/DegenerusAdmin.sol")` always reverts. The test always takes the `catch` branch, which asserts `game.lastVrfProcessed() != 0` — the exact same assertion made in `test_wiringHappenedAtDeploy` (line 89). The structural one-shot invariant (exactly one call site in the constructor) is never verified.

The test comment acknowledges this ("If fs_permissions is ever granted...") but frames the catch branch as a meaningful fallback. It is not: it adds zero additional proof over `test_wiringHappenedAtDeploy`. An adversary adding a second `wireVrf` call site in `DegenerusAdmin` would not be detected by this test.

**Fix:** Either:
1. Add `fs_permissions = [{access = "read", path = "./contracts"}]` to `foundry.toml` so the source grep runs; or
2. Remove `test_structuralOneShot_wireVrfOnlyFromConstructor` and add a comment to `test_wiringHappenedAtDeploy` referencing the 312-01-SUMMARY call-graph trace as the structural attestation; or
3. Keep the test but add a `fail()` in the catch branch so the test fails when `fs_permissions` is absent, forcing the engineer to consciously enable it.

---

## New VTST Files — Assessment

The four new files (VTST-01 through VTST-04) are sound for the security-critical assertions reviewed:

**VTST-01 post-fix arm** (`test_postFix_midDayRotation_landsRealWordInOrphanedIndex`): The reserved slot is confirmed empty pre-fulfillment (line 135, 147), the word is delivered via `newVRF.fulfillRandomWords(newVRF.lastRequestId(), vrfWord)` through `rawFulfillRandomWords`, and the assertion at line 154 reads contract-derived state. Not tautological. The `vm.assume(vrfWord != 0)` guard correctly handles the zero-word guard at AdvanceModule:1796. Sound.

**VTST-02 liveness tests**: The `_advanceTolerant()` helper re-throws any revert other than `NotTimeYet()` (lines 114-125), ensuring `RngNotReady()` propagates as a test failure. Liveness is proven by positive outcomes (rngLocked()==false after drain). The retry-rescue test correctly distinguishes the stale reissue ID from the retry request ID. Sound.

**VTST-03 byte-identity fuzz**: Run A delivers vrfWord via the NEW coordinator's re-issued request; Run B delivers the same vrfWord on the original coordinator. The snapshot/revert pattern (vm.snapshot before requestLootboxRng) correctly isolates the two runs. The daily digest includes `rngWordForDay(today)` (contract-derived from the delivered word) — the freeze invariant is meaningfully tested. The `rngWordCurrent = 0` component of the daily digest is a constant in both runs (cleared by drain) and does not make the comparison vacuous. Sound.

**VTST-04 access-guard tests**: `assertFalse(ok)` via low-level call correctly catches the `:503` E() revert. The `assertTrue(nonAdmin != ContractAddresses.ADMIN)` sanity check at line 44 prevents a tautological pass. Sound (see WR-03 for the structural attestation weakness).

**Slot constants in new files**: All four new files use `SLOT_LOOTBOX_PACKED = 37` and `SLOT_LOOTBOX_WORD_MAP = 38` (with correct `keccak256(encode(key, 38))` for mapping lookups). These match the authoritative layout.

---

_Reviewed: 2026-05-23_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: deep_
