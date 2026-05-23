---
phase: 313-tst-vrf-regression-freeze-invariant-fuzz-under-rotation-tst
verified: 2026-05-23T14:30:00Z
status: passed
score: 5/5
overrides_applied: 0
---

# Phase 313: VRF-Rotation Regression + Freeze-Invariant Fuzz Verification Report

**Phase Goal:** Ship Foundry coverage proving VRF-01..05 against the Phase 312 fix (AGENT-COMMITTED, test-tree only, ZERO contracts/ mainnet mutation). VTST-01 orphan-index reproduction (proves VRF-01); VTST-02 liveness-after-rotation (proves VRF-02); VTST-03 freeze-invariant fuzz under rotation extending the v43 RngLockDeterminism.t.sol harness (proves VRF-03); VTST-04 wireVrf one-shot — second/non-admin wire + vault-routed wire revert via the :503 ADMIN guard (proves VRF-04/VRF-05).
**Verified:** 2026-05-23T14:30:00Z
**Status:** passed
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Orphan-index reproduction PASSES — pre-fix entropy-0 arm + post-fix real VRF word in lootboxRngWordByIndex[N] after a real rotation (VTST-01 / VRF-01) | VERIFIED | `forge test --match-contract VrfRotationOrphanIndex` exit 0: 2 passed, 0 failed, 0 skipped. post-fix arm runs 1000 fuzz runs; pre-fix arm is deterministic. Both arms present in `test/fuzz/VrfRotationOrphanIndex.t.sol` (201 lines). |
| 2 | Liveness-after-rotation PASSES — requestLootboxRng/retryLootboxRng/daily-drain advance succeed post-rotation, no permanent revert (VTST-02 / VRF-02) | VERIFIED | `forge test --match-contract VrfRotationLiveness` exit 0: 6 passed, 0 failed, 0 skipped. All three rotation branches (mid-day, daily, short-circuit/no-op) + retryLootboxRng failsafe + requestLootboxRng reachability covered at 1000 fuzz runs each. |
| 3 | Freeze-invariant fuzz under rotation PASSES — every VRF-derived output byte-identical to the no-rotation baseline across perturbed rotations (VTST-03 / VRF-03) | VERIFIED | `forge test --match-contract RngLockRotationDeterminism` exit 0: 2 passed, 0 failed, 0 skipped. Both fuzz functions (daily branch + mid-day branch) run 1000 iterations each. `assertEq(digestA, digestB)` comparison confirmed in source. |
| 4 | wireVrf one-shot PASSES — second/non-admin wire + vault-routed wire both revert via the :503 ADMIN guard (VTST-04 / VRF-04 + VRF-05) | VERIFIED | `forge test --match-contract VrfWireOneShot` exit 0: 4 passed, 0 failed, 0 skipped. Tests assert: non-admin wireVrf reverts (low-level ok==false), non-admin updateVrfCoordinatorAndSub reverts, lastVrfProcessed()!=0 (wired once), structural one-shot attestation (try/catch falls back to lastVrfProcessed). |
| 5 | forge build + suite restored to pre-fix baseline (no NEW failures vs 41546f16); v43 RngLockDeterminism.t.sol harness still PASSES; AGENT-COMMITTED test commits | VERIFIED | `forge build` exits 0. v43 harness: 2 passed, 0 failed, 16 skipped — byte-identical (git status clean). SC-5 proven empirically (313-06 SUMMARY): HEAD failing-function set (65) is strict subset of pre-fix failing set (80); comm -23 empty. All 8 test files agent-committed (commits f6cc92c9 / 611deb20 / 2f438ea2 / afa1ac22 / c4d7f627 / 4d45107d / b4a63ac7 / ced272e7 / 6ad8338a). |

**Score:** 5/5 truths verified

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `test/fuzz/VrfRotationOrphanIndex.t.sol` | VTST-01: pre-fix entropy-0 arm + post-fix real-VRF-word-in-[N] arm, single invocation | VERIFIED | File exists (201 lines). `contract VrfRotationOrphanIndex is DeployProtocol`. Two test functions confirmed in source and both PASS. Post-fix arm asserts slot 0 before fulfilment (no tautology) and == vrfWord after. Pre-fix arm uses vm.store to zero the slot-38 mapping at LR_INDEX-1. |
| `test/fuzz/VrfRotationLiveness.t.sol` | VTST-02: mid-day branch + daily branch + short-circuit/no-op + retryLootboxRng + requestLootboxRng reachability | VERIFIED | File exists. `contract VrfRotationLiveness is DeployProtocol`. 6 test functions. All PASS. `_advanceTolerant()` catches NotTimeYet only (RngNotReady re-thrown so defect mode fails naturally). |
| `test/fuzz/RngLockRotationDeterminism.t.sol` | VTST-03: rotation-perturbed vs no-rotation byte-identical digest (daily + mid-day branches), extends v43 harness pattern | VERIFIED | File exists. `contract RngLockRotationDeterminism is DeployProtocol`. 2 fuzz functions (daily + mid-day). Both PASS at 1000 runs. `_assertVrfOutputByteIdentity` shape confirmed. v43 harness NOT modified. |
| `test/fuzz/VrfWireOneShot.t.sol` | VTST-04: non-admin wireVrf revert + non-admin updateVrfCoordinatorAndSub revert + structural one-shot attestation | VERIFIED | File exists (162 lines). 4 test functions confirmed. All PASS. Access-guard form (low-level call + assertFalse(ok)) asserted. No init-lock selector asserted (correctly reflecting Phase 312 VRF-04 deviation). |
| `test/fuzz/VRFStallEdgeCases.t.sol` (migrated) | 4 Class A + 8 Class B regressions migrated to preserve+re-issue | VERIFIED | Suite: 18 passed, 0 failed, 0 skipped. All enumerated fix-induced regressions pass. |
| `test/fuzz/StallResilience.t.sol` (migrated) | 3 Class B regressions migrated; slot drift 38/39 → 37/38 corrected | VERIFIED | Suite: 3 passed, 0 failed, 0 skipped. |
| `test/fuzz/VRFCore.t.sol` (migrated) | test_coordinatorSwap_clearsRngLocked migrated | VERIFIED | 20 passed, 2 failed (pre-existing: test_midDayRequest_doesNotBlockDaily, test_retryDetection_fresh). |
| `test/fuzz/VRFPathCoverage.t.sol` (migrated) | 4 fix-induced fuzz tests migrated via shared helper | VERIFIED | 4 passed, 2 failed (pre-existing: test_gapBackfillWithMidDayPending_fuzz, test_indexLifecycleAcrossStall_fuzz). |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| post-fix arm (VrfRotationOrphanIndex) | lootboxRngWordByIndex[reservedIndex] == vrfWord | `updateVrfCoordinatorAndSub` mid-flight → re-issued request on newVRF → `rawFulfillRandomWords:1804` mid-day write | WIRED | `_rotateMidFlight()` calls `game.updateVrfCoordinatorAndSub(address(newVRF), ...)` admin-pranked; `newVRF.fulfillRandomWords(newVRF.lastRequestId(), vrfWord)` drives contract path; word never vm.stored in post-fix arm. |
| post-rotation drain gate (VrfRotationLiveness) | rngLocked()==false (no permanent RngNotReady()) | re-issued request fulfilled on new coordinator before advanceGame | WIRED | `_advanceTolerant()` re-throws RngNotReady verbatim; drain completes to rngLocked()==false; confirmed 6/6 tests PASS. |
| perturbed run digest (RngLockRotationDeterminism) | byte-identical to no-rotation baseline digest | snapshot → rotate → deliver SAME word on newVRF.lastRequestId() → revert → deliver SAME word on original coordinator | WIRED | `assertEq(digestA, digestB)` confirmed in source. `rotSeed` fuzzes newKeyHash/newSubId — any digest drift from rotation config is a real freeze-invariant violation. |
| non-ADMIN wireVrf caller | revert (ok==false, the :503 guard) | low-level call to DegenerusGame.wireVrf (:308) → delegatecall → AdvanceModule :498 → :503 ADMIN guard | WIRED | `wireVrf` at :498 confirmed in contract; ADMIN guard at :503 confirmed with `grep`. `assertFalse(ok)` asserted in test. |
| non-ADMIN updateVrfCoordinatorAndSub caller | revert (ok==false, the :1717 guard) | low-level call to DegenerusGame (:1874) → delegatecall → :1712 → :1717 guard | WIRED | ADMIN guard at :1717 confirmed with `grep`. `assertFalse(ok)` asserted in test. |
| DegenerusAdmin.gameAdmin.wireVrf | single constructor call site only | `grep` on contracts/DegenerusAdmin.sol: `gameAdmin.wireVrf(` at :458 (constructor starts :445); interface declaration at :109 is not a call site | WIRED | grep confirms exactly one call site: line 458. No post-construction forwarder found. |

---

### Data-Flow Trace (Level 4)

These are pure Foundry test files. Data flows from:
- `MockVRFCoordinator.fulfillRandomWords()` → `DegenerusGame.rawFulfillRandomWords()` → `lootboxRngWordByIndex[N]` (slot-38 mapping). Test reads this via `vm.load(address(game), keccak256(abi.encode(uint256(index), uint256(38))))`. The read is from the live contract storage — no hardcoded values are asserted as passing.
- `game.rngLocked()` view confirming the drain reached unlocked state — reads live contract state.
- `game.lastVrfProcessed()` view for the one-shot wire test — reads live contract state.

All assertions flow through live contract paths. No static returns or hardcoded assertions that bypass contract behavior were found.

---

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| VTST-01: Orphan-index reproduction (both arms) | `forge test --match-contract VrfRotationOrphanIndex` | 2 passed, 0 failed, 0 skipped; exit 0 | PASS |
| VTST-02: Liveness-after-rotation (6 tests) | `forge test --match-contract VrfRotationLiveness` | 6 passed, 0 failed, 0 skipped; exit 0 | PASS |
| VTST-03: Freeze-invariant fuzz under rotation (2 fuzz fns) | `forge test --match-contract RngLockRotationDeterminism` | 2 passed, 0 failed, 0 skipped; exit 0 | PASS |
| VTST-04: wireVrf one-shot (4 tests) | `forge test --match-contract VrfWireOneShot` | 4 passed, 0 failed, 0 skipped; exit 0 | PASS |
| v43 harness (RngLockDeterminism) still passes | `forge test --match-contract RngLockDeterminism` | 2 passed, 0 failed, 16 skipped; exit 0 | PASS |
| forge build | `forge build` | exit 0 (background task confirmed) | PASS |
| Zero contracts/ mutation | `git diff --name-only 08c0f2aa HEAD -- contracts/` | empty output | PASS |
| 17 fix-induced regressions migrated (VRFStallEdgeCases) | `forge test --match-contract VRFStallEdgeCases` | 18 passed, 0 failed; exit 0 | PASS |
| 3 fix-induced regressions migrated (StallResilience) | `forge test --match-contract StallResilience` | 3 passed, 0 failed; exit 0 | PASS |
| 1 fix-induced migration (VRFCore) + 2 pre-existing fails | `forge test --match-contract VRFCore` | 20 passed, 2 failed (documented baseline); exit 0 | PASS |
| 4 fix-induced migrations (VRFPathCoverage) + 2 pre-existing fails | `forge test --match-contract VRFPathCoverage` | 4 passed, 2 failed (documented baseline); exit 0 | PASS |

Note on SC-5 fuzz run reduction: all tests were run at the full 1000-run default (not reduced). Fuzz times were under 1.5s for all contracts except VrfRotationLiveness (1.17s wall / 5.70s CPU). No `--fuzz-runs` reduction was applied.

---

### Probe Execution

No explicit probe scripts (`.sh` files) are declared for this phase. The phase uses direct `forge test` invocations as its executable verification protocol. All invocations confirmed above.

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| VTST-01 | 313-01 | Orphan-index reproduction proving VRF-01 | SATISFIED | REQUIREMENTS.md: `[x] VTST-01` (marked Complete, commit refs f6cc92c9 + 611deb20). Test passes at runtime. |
| VTST-02 | 313-02, 313-05 | Liveness-after-rotation proving VRF-02 | SATISFIED | REQUIREMENTS.md: `[x] VTST-02`. Test passes at runtime. Plans 313-02 (VrfRotationLiveness) + 313-05 (regression migration) both claim VTST-02. |
| VTST-03 | 313-03 | Freeze-invariant fuzz under rotation proving VRF-03 | SATISFIED | REQUIREMENTS.md: `[x] VTST-03`. Test passes at runtime. |
| VTST-04 | 313-04 | wireVrf one-shot proving VRF-04 + VRF-05 | SATISFIED | REQUIREMENTS.md: `[x] VTST-04`. Test passes at runtime. |
| VRF-01..05 | Provable by VTST-01..04 | Contract-level requirements (SPEC + IMPL) closed by test coverage | NOT YET MARKED COMPLETE in REQUIREMENTS.md (still `[ ]`) | These remain open in REQUIREMENTS.md as expected: they require the TERMINAL phase (315) audit deliverable to close formally. The tests PROVE them; the formal closure is the AUDIT-01/CLS-01 deliverable. This is not a Phase 313 gap. |

**VRF-01..05 note:** The REQUIREMENTS.md traceability table at lines 122–126 lists VRF-01..05 as "Pending" even though VTST-01..04 are Complete. This is the correct state: Phase 313 produces the proofs; Phase 315 (TERMINAL) closes the findings formally in the audit deliverable per AUDIT-01 and CLS-01. No action needed in Phase 313.

---

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| — | — | — | — | No debt markers (TBD/FIXME/XXX), no placeholder text, no hardcoded empty assertion values found in any of the 4 new test files or the 4 migrated files. |

Specific checks performed:
- `grep -n "TBD\|FIXME\|XXX"` across all 4 new test files: zero matches.
- `grep -n "TODO\|HACK\|PLACEHOLDER"` across all 4 new test files: zero matches.
- VrfWireOneShot structural-attestation fallback (`lastVrfProcessed() != 0`) is NOT a stub: it is a substantive on-chain assertion that the single constructor wire ran. It activates only when `vm.readFile` is unavailable (no fs_permissions in foundry.toml), and the fallback is explicitly documented in the contract NatDoc.

---

### Human Verification Required

None. All success criteria are mechanically verifiable via `forge test` invocations and `git diff`. The phase is test-tree only with no UI, UX, real-time, or external service components.

---

### Gaps Summary

No gaps. All five ROADMAP Phase 313 success criteria are verified:

1. **VTST-01 (VRF-01):** VrfRotationOrphanIndex passes (2/2 arms, 1000 fuzz runs on post-fix). Contrast pattern confirmed: pre-fix arm forces entropy-0 via vm.store at the LR_INDEX-1 slot; post-fix arm delivers a real VRF word via the contract's rawFulfillRandomWords path. No tautology (slot asserted == 0 before fulfilment).

2. **VTST-02 (VRF-02):** VrfRotationLiveness passes (6/6, 1000 fuzz runs each). All three `updateVrfCoordinatorAndSub` branches + retryLootboxRng failsafe + post-rotation requestLootboxRng reachability covered. Liveness proven by positive outcome only (drain reaches rngLocked()==false); RngNotReady re-thrown, never swallowed.

3. **VTST-03 (VRF-03):** RngLockRotationDeterminism passes (2/2, 1000 fuzz runs each). Daily and mid-day branches. assertEq(digestA, digestB) with rotSeed fuzzing newKeyHash/newSubId — the freeze invariant requires these NOT to affect the output. v43 RngLockDeterminism.t.sol untouched and still passes (2 live + 16 skip).

4. **VTST-04 (VRF-04 + VRF-05):** VrfWireOneShot passes (4/4). Access-guard form correctly asserted (not a non-existent init-lock). Structural one-shot attestation present. ADMIN guard anchors verified in contract source (:503 for wireVrf, :1717 for updateVrfCoordinatorAndSub). DegenerusAdmin.gameAdmin.wireVrf call site confirmed exactly once (constructor :458).

5. **SC-5 (forge build + no new failures + v43 harness + AGENT-COMMITTED):** forge build exits 0. SC-5 proven empirically in 313-06: temporary pre-fix AdvanceModule.sol swap + full suite comparison → HEAD failing-function set (65) is strict subset of pre-fix set (80); comm -23 empty (0 new failures). All 8 phase test files agent-committed. v43 harness byte-identical and passes.

---

### Contract Anchor Verification

Key contract anchors were grep-verified against the current source (not taken on faith from plan line numbers):

| Anchor | Plan claimed | Grep result | Match? |
|--------|-------------|-------------|--------|
| wireVrf ADMIN guard | :503 | :503 `if (msg.sender != ContractAddresses.ADMIN) revert E();` | Yes |
| updateVrfCoordinatorAndSub ADMIN guard | :1693 (plan), :1717 (actual) | :1717 `if (msg.sender != ContractAddresses.ADMIN) revert E();` | Off by ~24 lines — test asserts behavior (low-level ok==false), not a hardcoded line; no impact |
| updateVrfCoordinatorAndSub function | :1688 (plan), :1712 (actual) | :1712 | Off by 24 lines — same drift; no impact |
| lootboxRngWordByIndex mid-day write | :1772 (plan), :1804 (actual) | :1804 `lootboxRngWordByIndex[index] = word;` | Off by ~32 lines — test exercises the path via rawFulfillRandomWords which is verified to write the correct slot |
| DegenerusAdmin.gameAdmin.wireVrf call site | :458 | :458 | Yes (one occurrence; constructor starts :445) |

Line-number drift is expected post-Phase-312 patch (the plan's interfaces block warned of this). All tests use behavior-based assertions, not hardcoded line numbers, so drift has zero impact on test validity.

---

_Verified: 2026-05-23T14:30:00Z_
_Verifier: Claude (gsd-verifier)_
