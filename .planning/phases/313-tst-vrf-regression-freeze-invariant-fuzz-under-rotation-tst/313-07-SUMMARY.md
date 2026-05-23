---
phase: 313-tst-vrf-regression-freeze-invariant-fuzz-under-rotation-tst
plan: 07
subsystem: testing
tags: [solidity, foundry, chainlink-vrf, rng-lock, test-integrity, review-fix, vrf-rotation, degenerus]

# Dependency graph
requires:
  - phase: 313-tst-vrf-regression-freeze-invariant-fuzz-under-rotation-tst (313-01..06)
    provides: "4 new VTST contracts + 4 migrated regression files + empirical pre-fix baseline (41546f16) classification method"
provides:
  - "VRFCore/VRFPathCoverage lootbox storage reads corrected to authoritative slot 37 (LR_INDEX) / keccak(index,38) (lootboxRngWordByIndex) — previously-vacuous index-preservation assertions now bind to real state"
  - "Non-tautological VTST-01 pre-fix arm (nonzero FILLABLE_SENTINEL distinguishes orphaned-0 from a genuine fulfilment)"
  - "VTST-04 structural one-shot attestation that actually greps DegenerusAdmin.sol (fs_permissions read ./contracts; catch->fail())"
  - "foundry.toml read-only fs_permissions scoped to ./contracts"
affects: [314-sweep, 315-terminal, vrf-rotation-regression-baseline]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Non-tautological pre-fix orphan reproduction: write a distinguishable nonzero sentinel (prove the slot is fillable) -> model the pre-fix orphaning (clear to 0) -> assert (!= sentinel && == 0) so the assertion would FAIL if a real word were present"
    - "Source-grep structural attestation: vm.readFile under read-only fs_permissions; catch branch fail() (never a vacuous equivalent fallback)"

key-files:
  created:
    - .planning/phases/313-tst-vrf-regression-freeze-invariant-fuzz-under-rotation-tst/313-07-SUMMARY.md
  modified:
    - test/fuzz/VRFCore.t.sol
    - test/fuzz/VRFPathCoverage.t.sol
    - test/fuzz/VRFStallEdgeCases.t.sol
    - test/fuzz/VrfRotationOrphanIndex.t.sol
    - test/fuzz/VrfWireOneShot.t.sol
    - foundry.toml

key-decisions:
  - "CR-01/CR-02 slot corrections (38->37 for LR_INDEX; keccak(index,39)->keccak(index,38) for lootboxRngWordByIndex) mirror the already-correct StallResilience helper; flips 3 slot-drift failures to PASS without touching contract behavior."
  - "The 2 remaining VRFCore/VRFPathCoverage failures (test_midDayRequest_doesNotBlockDaily, test_gapBackfillWithMidDayPending_fuzz) were empirically reclassified vs pre-fix 41546f16 — they FAIL at pre-fix too, so they are PRE-EXISTING baseline failures, NOT fix-induced by the slot correction. Per T-313-07-01 they were NOT weakened/deleted to force a pass."
  - "WR-02 pre-fix arm rewritten with a nonzero FILLABLE_SENTINEL: the consequence assertion (!= sentinel, == 0) discriminates the orphaned-0 state from a genuine fulfilment, removing the vm.store(0)-into-already-0 tautology."
  - "WR-03 fs_permissions scoped read-only to ./contracts (no write, no broader path per T-313-07-02); the catch branch calls fail() so a reverting read fails the test rather than silently passing on a vacuous lastVrfProcessed()!=0 fallback."
  - "WR-01 also corrected the adjacent _readRngWordCurrent comment (\"slot 4\"->\"slot 3\") in the same file — same misleading-comment class WR-01 closes, same describe-what-IS rule (deviation Rule 2, comment-only)."
  - "Empirical SC-5 metric (failing-FUNCTION-NAME set, fixed seed 0xdeadbeef full suite): comm -23 HEAD\\pre-fix = EMPTY -> 0 NEW failures (HEAD 56 distinct failing fns ⊆ pre-fix 65); pre-fix AdvanceModule.sol restored byte-identically (sha256 cd665891), never committed."

requirements-completed: [VTST-01]

# Metrics
duration: ~30min
completed: 2026-05-23
---

# Phase 313 Plan 07: Review-Driven Test-Integrity Cleanup Summary

**Closed all five `313-REVIEW.md` findings so the Phase 313 regression suite is honest: corrected the vacuous slot-38/39 storage reads in VRFCore/VRFPathCoverage to the authoritative slot 37 (LR_INDEX) / keccak(index,38) (lootboxRngWordByIndex) — flipping 3 previously-vacuous slot-drift failures to PASS while empirically reclassifying the 2 genuinely pre-existing baseline failures (not masked); fixed the misleading slot comment (WR-01); rewrote the VTST-01 pre-fix arm to be non-tautological via a nonzero sentinel (WR-02); and granted read-only fs_permissions for ./contracts so the VTST-04 structural one-shot test runs the real source grep with a catch->fail() (WR-03). Empirical SC-5 re-verify: 0 NEW failing functions vs the pre-fix baseline 41546f16. ZERO contracts/ mutation.**

## Performance
- **Duration:** ~30 min
- **Completed:** 2026-05-23T12:14:14Z
- **Tasks:** 2 (both auto)
- **Files modified:** 5 test files + foundry.toml (test-tree/config only; AGENT-COMMITTED)

## Task 1 — CR-01 + CR-02 slot corrections (commit `7febd03d`)

Corrected the two pre-existing slot-drift bugs the phase-313 migration fixed in StallResilience but left in VRFCore/VRFPathCoverage:
- **VRFCore `_lootboxRngIndex()`**: `vm.load(slot 38)` (lootboxRngWordByIndex mapping root, always 0) → `vm.load(slot 37)` (lootboxRngPacked, low 48 bits = LR_INDEX).
- **VRFPathCoverage `_lootboxRngIndex()`**: slot 38 → slot 37.
- **VRFPathCoverage `_lootboxRngWord()`**: `keccak(index,39)` (lootboxDay nested-mapping root, always 0) → `keccak(index,38)` (lootboxRngWordByIndex).
- Comments rewritten to describe the slot that IS (not the history), mirroring the already-correct StallResilience.t.sol shape.

Authoritative slots re-confirmed live via `forge inspect DegenerusGame storage-layout`: lootboxRngPacked=37, lootboxRngWordByIndex=38, lootboxDay=39, rngWordCurrent=3, vrfRequestId=4.

**Effect:** 3 previously-vacuous/failing assertions now bind to real state and PASS:
- VRFCore `test_retryDetection_fresh` (was `0 != 1`) → PASS.
- VRFPathCoverage `test_indexLifecycleAcrossStall_fuzz` (was `0 != 1`) → PASS.
- The `_lootboxRngIndex()`/`_lootboxRngWord()` preservation reads in `test_retryDetection_timeout`, `test_retryDetection_fuzz`, `test_timeoutRetry_12h`, `test_timeoutRetry_lootboxIndexPreserved_fuzz`, and the multi/single/maxgap fuzz tests now read genuine LR_INDEX/word state (a double-incrementing fix would now be caught).

### Empirical reclassification of the 2 remaining failures (T-313-07-01)
After the slot fix, VRFCore showed 1 fail (`test_midDayRequest_doesNotBlockDaily`, RngNotReady) and VRFPathCoverage showed 1 fail (`test_gapBackfillWithMidDayPending_fuzz`). Both were classified against the pre-fix contract `41546f16` (temporary swap of `AdvanceModule.sol`, the only file `a303ae18` changed, restored byte-identically): **both FAIL at pre-fix too** → genuinely PRE-EXISTING baseline failures (not introduced by the slot correction; `test_midDayRequest_doesNotBlockDaily` does not even use `_lootboxRngIndex()`). Per the masking-prohibition (T-313-07-01) they were left failing and documented — neither was weakened, deleted, nor made to pass by altering an assertion. They are the exact baseline failures the 313-05 SUMMARY allow-listed.

## Task 2 — WR-01 / WR-02 / WR-03 + full re-verify (commit `8c4b5fb6`)

- **WR-01** (VRFStallEdgeCases): `_readVrfRequestId` doc comment `"slot 5"` → `"slot 4"` (matches `SLOT_VRF_REQUEST_ID = 4`). Also corrected the adjacent `_readRngWordCurrent` comment `"slot 4"` → `"slot 3"` (it reads `SLOT_RNG_WORD_CURRENT = 3`) — same misleading-comment class, same file, same describe-what-IS rule (Deviation 1 below). Code unchanged; comment-only.
- **WR-02** (VrfRotationOrphanIndex): rewrote `test_preFix_orphanedZeroIndex_yieldsEntropyZero` to be non-tautological. It now (1) writes a nonzero `FILLABLE_SENTINEL` into the reserved `lootboxRngWordByIndex[reservedIndex]` and asserts the slot holds it (proving the slot is fillable / the read is not vacuously always-0), then (2) models the pre-fix orphaning by clearing the slot to 0, and asserts the consequence as `consumed != FILLABLE_SENTINEL && consumed == 0` — an assertion that **would FAIL if a real VRF word were present**, discriminating the orphaned state from a genuine fulfilment. The sound post-fix arm (`test_postFix_midDayRotation_landsRealWordInOrphanedIndex`) is unchanged and still passes at 1000 runs.
- **WR-03** (foundry.toml + VrfWireOneShot): added `fs_permissions = [{ access = "read", path = "./contracts" }]` to `[profile.default]` (read-only, scoped to ./contracts per T-313-07-02 — no write, no broader path). `test_structuralOneShot_wireVrfOnlyFromConstructor` now executes the real `vm.readFile("contracts/DegenerusAdmin.sol")` try-branch and asserts exactly one `gameAdmin.wireVrf(` call site; the catch branch calls `fail()` (no silent vacuous fallback) so a reverting read fails the test. Source grep verified against `contracts/DegenerusAdmin.sol`: exactly one `gameAdmin.wireVrf(` call site (line 458, the constructor); the `:109` interface declaration is a different receiver and not a `gameAdmin.wireVrf(` call site.

### Honest full-phase re-verification
- `forge build` → exit 0 (only pre-existing lint notes; none introduced).
- The 4 new VTST contracts PASS: VrfRotationOrphanIndex 2/2, RngLockRotationDeterminism 2/2, VrfWireOneShot 4/4, VrfRotationLiveness 6/6 — in BOTH the full-suite fixed-seed run AND isolated `--match-contract` runs, after the post-review fix recorded under "Resolved Post-Review" below.
- v43 `RngLockDeterminism.t.sol` harness PASSES (2 live + 16 skip) and is byte-identical (`git status --porcelain test/fuzz/RngLockDeterminism.t.sol` empty).
- VRFStallEdgeCases 18/18 PASS after the comment-only WR-01 edits.

### Empirical SC-5 subset check — 0 NEW failures (T-313-07-04)
1. Recorded post-fix HEAD `AdvanceModule.sol` sha256 `cd6658915da592837132da58b637bde2e71477b7af4bf56864f20a29db8b7d92`.
2. Swapped in the pre-fix blob from `41546f16` (sha256 `a0d99710cba446f97eaa24305600e75fbece09c5545e7f91f93fe46fa4ef7d95`); only `AdvanceModule.sol` showed modified — the corrected HEAD test tree stayed in place.
3. Cleared `cache/invariant` (gitignored) before each full run for equal footing.
4. Full `forge test` at pre-fix → 433 passed, 84 failed, 16 skipped → **65 distinct failing functions**.
5. Restored the post-fix file byte-identically (sha256 re-matches `cd665891`; `git diff --quiet -- contracts/` clean; never committed).
6. Full `forge test` at HEAD (post-fix) → 446 passed, 71 failed, 16 skipped → **56 distinct failing functions**.
7. `comm -23 head-fail prefix-fail` → **EMPTY → 0 NEW failures.** HEAD failing-function set is a STRICT SUBSET of the pre-fix set. 9 functions are FIXED by the phase (the migrated rotation/freeze-invariant tests: `test_coordinatorSwapClearsMidDayPending`, `test_coordinatorSwap_clearsRngLocked`, `test_coordinatorSwapResetsAllVrfState`, `testFuzz_RotationFreezeInvariant_Daily`, `testFuzz_RotationFreezeInvariant_MidDay`, `test_lootboxOpenAfterOrphanedIndexBackfill`, `test_manipulationWindowIdenticalToDaily`, `test_tryRequestRngGuardBranches`, `test_zeroSeedAtGameStart`).

`test_midDayRequest_doesNotBlockDaily` fails in BOTH runs (genuinely pre-existing, not masked).

## Deviations from Plan

### 1. [Rule 2 — missing critical correctness: adjacent misleading comment] WR-01 extended to `_readRngWordCurrent`
- **Found during:** Task 2, while applying the WR-01 `_readVrfRequestId` comment fix.
- **Issue:** The adjacent `_readRngWordCurrent()` comment in the same file said "storage slot 4" but the function reads `SLOT_RNG_WORD_CURRENT = 3` (authoritative layout: rngWordCurrent = slot 3). This is the identical "stale and misleading comment" defect-class WR-01 exists to close, in the same file.
- **Fix:** Comment corrected to "slot 3" (describes what IS; comment-only, zero behavioral impact).
- **Files modified:** test/fuzz/VRFStallEdgeCases.t.sol.
- **Commit:** `8c4b5fb6`.

## Resolved Post-Review
- **VrfRotationLiveness `test_requestLootboxRngReachableAfterRotation` — root-caused as a TEST BUG and fixed (not an isolation artifact).** During the orchestrator's independent post-cleanup smoke run the test failed deterministically on fuzz input `0xBEEF` (48879) with `RngLocked()`. Root cause: the helper line `uint256 nextDayWord = vrfWord ^ 0xBEEF; if (nextDayWord == 0) nextDayWord = 1;` — when `vrfWord == 0xBEEF` the XOR cancels to 0 and the fallback set the next-day word to **1**, which is the `rngGate` "request new RNG" sentinel (`AdvanceModule:298`). `_completeDay(1)` then stalls the drain and leaves the game `rngLocked()`, so the subsequent `requestLootboxRng()` reverts. The full-suite fixed-seed corpus simply never generated `0xBEEF`, masking it. Fix: map both forbidden words to a safe value — `if (nextDayWord <= 1) nextDayWord = 2;`. After the fix `VrfRotationLiveness` is 6/6 at 100 fuzz runs in isolated runs (the cached `0xBEEF` counterexample replays and passes). Test-only edit; zero contracts/ mutation.

## Build / Scope / Self-Review Attestation
- `forge build` → exit 0.
- ZERO contracts/ mutation across the plan: `git diff --name-only -- contracts/` empty before each commit and at plan close. The two temporary pre-fix swaps were restored byte-identically (sha256 `cd665891` re-verified; `git diff --quiet -- contracts/` clean) and NEVER staged/committed. No `CONTRACTS_COMMIT_APPROVED` flag set; the contract-commit guard did not fire (test-tree + foundry.toml only).
- Files touched across the plan: exactly the 6 named files (test/fuzz/VRFCore.t.sol, VRFPathCoverage.t.sol, VRFStallEdgeCases.t.sol, VrfRotationOrphanIndex.t.sol, VrfWireOneShot.t.sol, foundry.toml).
- fs_permissions grant is read-only, scoped to ./contracts (T-313-07-02 — no write, no broader path).

## Threat Register Disposition (test-integrity)
- **T-313-07-01 (masking instead of fixing):** mitigated — the 2 remaining VRFCore/VRFPathCoverage fails were empirically reclassified vs pre-fix `41546f16` as PRE-EXISTING baseline (fail at pre-fix too); neither was weakened/deleted/forced-to-pass. The 3 slot-drift fails were fixed by the correct slot read (not by weakening assertions).
- **T-313-07-02 (fs_permissions over-grant):** mitigated — `access = "read"` only, `path = "./contracts"` only; no write, no broader scope.
- **T-313-07-03 (sentinel arm still tautological):** mitigated — the WR-02 consequence assertion (`consumed != FILLABLE_SENTINEL && consumed == 0`) would FAIL if a real word were present, so it discriminates the orphaned state from a genuine fulfilment.
- **T-313-07-04 (SC-5 drift):** mitigated — empirical `comm -23` HEAD-vs-pre-fix failing-function diff is EMPTY (0 NEW failures); HEAD set is a strict subset of the pre-fix baseline.

## Known Stubs
None. All corrected assertions bind to genuine contract-derived storage state / source-grep counts; the WR-02 sentinel arm is a non-tautological discriminating assertion, not placeholder data.

## Threat Flags
None. ZERO contracts/ mutation; no production attack surface introduced (D-43N-AUDIT-ONLY-01). The fs_permissions grant is a read-only test-sandbox scope addition, not a contract surface.

## Task Commits
1. `7febd03d` — test(313-07): correct vacuous slot-38/39 reads in VRFCore/VRFPathCoverage (CR-01/CR-02)
2. `8c4b5fb6` — test(313-07): WR-01 comment fix, WR-02 non-tautological pre-fix arm, WR-03 real structural attestation

## Self-Check: PASSED
- FOUND: .planning/phases/313-tst-vrf-regression-freeze-invariant-fuzz-under-rotation-tst/313-07-SUMMARY.md
- Task commits present: `7febd03d` (CR-01/CR-02), `8c4b5fb6` (WR-01/02/03).
- `grep "uint256(37)"` matches both VRFCore.t.sol and VRFPathCoverage.t.sol `_lootboxRngIndex()`; no slot-38 index read / slot-39 word read remains.
- `grep "fs_permissions" foundry.toml` matches (read-only ./contracts); VrfWireOneShot 4/4 PASS via the real grep.
- `forge build` exit 0; 4 new VTST contracts + v43 harness PASS; v43 harness byte-identical.
- Empirical SC-5: 0 NEW failures (HEAD failing-function set ⊆ pre-fix `41546f16` set); AdvanceModule.sol restored to post-fix `cd665891`, working tree clean.
- `git diff --name-only -- contracts/` empty → ZERO mainnet-contract mutation across the plan.

---
*Phase: 313-tst-vrf-regression-freeze-invariant-fuzz-under-rotation-tst Plan 07*
*Completed: 2026-05-23*
