---
phase: 313-tst-vrf-regression-freeze-invariant-fuzz-under-rotation-tst
plan: 06
subsystem: testing
tags: [solidity, foundry, chainlink-vrf, vrf-rotation, rng-lock, suite-verification, regression, freeze-invariant, agent-commit, degenerus]

# Dependency graph
requires:
  - phase: 313-tst-vrf-regression-freeze-invariant-fuzz-under-rotation-tst (313-01)
    provides: "test/fuzz/VrfRotationOrphanIndex.t.sol (VTST-01)"
  - phase: 313-tst-vrf-regression-freeze-invariant-fuzz-under-rotation-tst (313-02)
    provides: "test/fuzz/VrfRotationLiveness.t.sol (VTST-02)"
  - phase: 313-tst-vrf-regression-freeze-invariant-fuzz-under-rotation-tst (313-03)
    provides: "test/fuzz/RngLockRotationDeterminism.t.sol (VTST-03)"
  - phase: 313-tst-vrf-regression-freeze-invariant-fuzz-under-rotation-tst (313-04)
    provides: "test/fuzz/VrfWireOneShot.t.sol (VTST-04)"
  - phase: 313-tst-vrf-regression-freeze-invariant-fuzz-under-rotation-tst (313-05)
    provides: "Migrated fix-induced regressions (VRFStallEdgeCases / StallResilience / VRFCore / VRFPathCoverage)"
provides:
  - "Suite-wide SC-5 attestation: post-fix HEAD failing-function set is a STRICT SUBSET of the empirical pre-fix baseline (41546f16) failing set — ZERO new failures"
  - "Empirical pre-fix baseline comparison: temporary byte-identically-restored AdvanceModule.sol swap, full forge test at pre-fix vs HEAD, comm-diff of failing-function sets"
affects: [314-sweep, 315-terminal, vrf-rotation-regression-baseline]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Empirical SC-5 proof: swap the single fix-changed contract (AdvanceModule.sol) to its pre-fix blob, full-suite tally, restore byte-identical (sha256-verified), comm -23 head-fail vs prefix-fail = 0 new failures"

key-files:
  created:
    - .planning/phases/313-tst-vrf-regression-freeze-invariant-fuzz-under-rotation-tst/313-06-SUMMARY.md
  modified: []

key-decisions:
  - "SC-5 proven EMPIRICALLY (not just against the prose allow-list): ran the IDENTICAL HEAD test-tree against the pre-fix contract (AdvanceModule.sol from 41546f16, the only file a303ae18 changed) via a temporary working-tree swap restored byte-identically (sha256 cd665891... confirmed; git status contracts/ empty). The HEAD failing-function set (65) is a strict subset of the pre-fix failing-function set (80); comm -23 head\\prefix = 0 NEW failures."
  - "No new test code committed by 313-06: the four VTST files (313-01..04) and the four migrated regression files (313-05) were each AGENT-COMMITTED by their own plan; the Phase 313 test bundle was already complete in git. 313-06 is verify-only (files_modified: []); the bundle commit per D-43N-TEST-COMMITS-AUTO-01 was satisfied incrementally."
  - "Raw fail COUNT differs (HEAD 73 vs pre-fix 86) only because the cached invariant-failure replays were cleared before the pre-fix run (more invariants ran fresh); the authoritative SC-5 metric is the failing-FUNCTION-NAME set comparison, which shows 0 new failures."

requirements-completed: [VTST-01, VTST-02, VTST-03, VTST-04]

# Metrics
duration: ~18min
completed: 2026-05-23
---

# Phase 313 Plan 06: Suite-Wide Verification + AGENT-COMMIT Summary

**Suite-wide SC-5 verification for Phase 313: `forge build` exit 0, the four new VTST contracts (VrfRotationOrphanIndex, VrfRotationLiveness, RngLockRotationDeterminism, VrfWireOneShot) all PASS, the v43 RngLockDeterminism freeze-invariant harness still PASSES byte-identically, the 313-05 migrated fix-induced regressions all PASS, and — proven EMPIRICALLY via a temporary byte-identically-restored pre-fix contract swap — the post-fix HEAD failing-function set is a STRICT SUBSET of the pre-fix baseline (41546f16) failing set with ZERO new failures. ZERO contracts/ mutation across the whole phase.**

## Performance
- **Duration:** ~18 min
- **Completed:** 2026-05-23T11:23:52Z
- **Tasks:** 2 (both auto; verify-only)
- **Files modified:** 0 source/test (verification + planning docs only)

## Task 1 — Verification Battery (PASS)

### (a) Build
- `forge build` → exit 0. Only pre-existing lint notes (`divide-before-multiply` in DegenerusGamePayoutUtils.sol, `unsafe-typecast` across mocks/tests/payout-utils) — no compile errors, none introduced by this phase.

### (b) Four new VTST contracts — ALL PASS
| Contract | Plan | Result | Fuzz |
|----------|------|--------|------|
| VrfRotationOrphanIndex (VTST-01) | 313-01 | 2 passed, 0 failed | post-fix arm 1000 runs |
| VrfRotationLiveness (VTST-02) | 313-02 | 6 passed, 0 failed | 4 fuzz fns × 1000 runs |
| RngLockRotationDeterminism (VTST-03) | 313-03 | 2 passed, 0 failed | 2 fuzz fns × 1000 runs |
| VrfWireOneShot (VTST-04) | 313-04 | 4 passed, 0 failed | n/a (deterministic) |

### (c) v43 freeze-invariant harness — PASSES, byte-identical
- `forge test --match-contract RngLockDeterminism` → 2 passed, 0 failed, 16 skipped (18 total). The two live tests (`RetryLootboxRng`, `StakedStonkRedemption`) pass at 1000 runs each; the vm.skip count is 16 (unchanged from the v44 baseline — Phase 301 `b102bc0f` flipped 17→16).
- `git status --porcelain test/fuzz/RngLockDeterminism.t.sol` is empty → the v43 harness file is byte-identical to the pre-phase baseline (NOT modified by this phase). Mitigates T-313-06-01.

### (d) Migrated fix-induced regressions (313-05) — ALL enumerated tests PASS
| Suite | Result | Note |
|-------|--------|------|
| VRFStallEdgeCases | 18 passed, 0 failed | all 12 enumerated fix-induced tests pass |
| StallResilience | 3 passed, 0 failed | stallSwapResume, coinflipClaimsAcrossGapDays, lootboxOpenAfterOrphanedIndexBackfill |
| VRFCore | 20 passed, 2 failed | migrated `test_coordinatorSwap_clearsRngLocked` PASSES; 2 fails are documented baseline |
| VRFPathCoverage | 4 passed, 2 failed | all 4 fix-induced fuzz tests PASS; 2 fails are documented baseline |

The 4 VRFCore/VRFPathCoverage failures are exactly the documented baseline: `test_midDayRequest_doesNotBlockDaily`, `test_retryDetection_fresh` (VRFCore); `test_gapBackfillWithMidDayPending_fuzz`, `test_indexLifecycleAcrossStall_fuzz` (VRFPathCoverage).

### (e) ZERO contracts/ mutation across the whole phase
- `git diff --name-only 08c0f2aa..HEAD -- contracts/` → empty.
- `a303ae18` (the Phase 312 fix) touched exactly one contract file (`contracts/modules/DegenerusGameAdvanceModule.sol`); nothing under contracts/ has changed since the prior milestone closure `08c0f2aa`.

### (f) Full-suite SC-5 subset check — ZERO NEW failures (EMPIRICAL)
SC-5 was proven empirically rather than only against the prose allow-list:

1. Recorded the post-fix HEAD checksum of the single fix-changed file `contracts/modules/DegenerusGameAdvanceModule.sol` (`sha256 cd6658915da592837132da58b637bde2e71477b7af4bf56864f20a29db8b7d92`).
2. Temporarily swapped in the **pre-fix** blob from `41546f16` (`git show 41546f16:...` → `sha256 a0d99710...`, matching the git blob). Only `AdvanceModule.sol` showed modified; the rest of the test-tree (incl. all 313 deliverables) stayed at HEAD.
3. Ran the FULL `forge test` against the pre-fix contract → **431 passed, 86 failed, 16 skipped** (80 distinct failing functions).
4. **Restored the post-fix file byte-identically** — `sha256` re-matches `cd665891...`; `git status --porcelain contracts/` empty; `git diff --stat -- contracts/` empty. No committed contract change at any point.
5. Ran the FULL `forge test` at HEAD (post-fix) → **444 passed, 73 failed, 16 skipped** (65 distinct failing functions).
6. `comm -23 head-fail-funcs prefix-fail-funcs` → **EMPTY**: the HEAD failing-function set is a STRICT SUBSET of the pre-fix failing set. **0 new failures.** Mitigates T-313-06-02.

The reverse diff (`comm -13`, pre-fix-only) lists 15 functions FIXED by the phase — the migrated regressions plus the new rotation VTST tests that fail against the pre-fix contract:
`test_coordinatorSwapClearsMidDayPending`, `test_coordinatorSwap_clearsRngLocked`, `test_coordinatorSwapResetsAllVrfState`, `test_dailyAlreadyDelivered_shortCircuit`, `test_dailyRotation_liveness`, `testFuzz_RotationFreezeInvariant_Daily`, `testFuzz_RotationFreezeInvariant_MidDay`, `test_lootboxOpenAfterOrphanedIndexBackfill`, `test_manipulationWindowIdenticalToDaily`, `test_midDayRotation_liveness`, `test_postFix_midDayRotation_landsRealWordInOrphanedIndex`, `test_requestLootboxRngReachableAfterRotation`, `test_retryRescuesStalledReissueAfterRotation`, `test_tryRequestRngGuardBranches`, `test_zeroSeedAtGameStart`.

All five documented named baseline tests fail in BOTH runs (genuinely pre-existing, not masked): `test_retryDetection_fresh`, `test_midDayRequest_doesNotBlockDaily`, `test_gapBackfillWithMidDayPending_fuzz`, `test_indexLifecycleAcrossStall_fuzz`, `test_wordWriteMidDay`. No `RngLockDeterminism_*` function appears in either failing set.

#### Raw count vs function-set
The raw fail count differs (HEAD 73 vs pre-fix 86) because the cached `cache/invariant/failures` replays were cleared before the pre-fix run, so more invariants ran fresh and failed (e.g. solvency / VRFPathInvariants under fresh campaigns). `cache/` is gitignored, so this is non-committing and non-load-bearing. The authoritative SC-5 metric is the failing-FUNCTION-NAME set comparison (step 6) — and that shows 0 new failures.

## Task 2 — AGENT-COMMIT the Phase 313 Test Bundle

The Phase 313 test bundle was already AGENT-COMMITTED incrementally by the prior plans (D-43N-TEST-COMMITS-AUTO-01); 313-06 is verify-only (`files_modified: []`), so there is no new test code to stage:

| File | Last commit | Plan |
|------|-------------|------|
| test/fuzz/VrfRotationOrphanIndex.t.sol | `611deb20` | 313-01 |
| test/fuzz/VrfRotationLiveness.t.sol | `2f438ea2` | 313-02 |
| test/fuzz/RngLockRotationDeterminism.t.sol | `c4d7f627` | 313-03 |
| test/fuzz/VrfWireOneShot.t.sol | `b4a63ac7` | 313-04 |
| test/fuzz/VRFStallEdgeCases.t.sol | `ced272e7` | 313-05 |
| test/fuzz/VRFCore.t.sol | `ced272e7` | 313-05 |
| test/fuzz/StallResilience.t.sol | `6ad8338a` | 313-05 |
| test/fuzz/VRFPathCoverage.t.sol | `6ad8338a` | 313-05 |

- `git status --porcelain test/` empty before and after this plan → all eight files tracked and committed; nothing left to stage.
- `git status --porcelain contracts/` empty before and after → no mainnet contract change. The PreToolUse contract-commit guard did not fire (contracts/ clean); no `CONTRACTS_COMMIT_APPROVED` flag set or needed.
- This plan's only commit is the metadata/docs commit (this SUMMARY + STATE + ROADMAP), AGENT-COMMITTED with the planning docs force-added (`.planning/` is gitignored).

## Deviations from Plan

### 1. [Process — verify-only plan] No standalone test commit for 313-06
- **Found during:** Task 2.
- **Issue:** Task 2 reads "AGENT-COMMIT the Phase 313 test bundle", but `files_modified: []` and all eight bundle files were already committed by 313-01..05's own AGENT commits.
- **Resolution:** No new test commit is honest here — staging already-committed files would produce an empty commit. The bundle-commit obligation (D-43N-TEST-COMMITS-AUTO-01) was satisfied incrementally; 313-06 records the verification + the docs commit. The acceptance criterion "a `test(313): ...` commit exists at HEAD with the bundle files" is met by the prior `test(313-01..05)` commits collectively.

### 2. [Methodology upgrade] SC-5 proven empirically, not just against the prose allow-list
- **Found during:** Task 1 step (f).
- **Rationale:** The plan's allow-list mixes named tests with category descriptions ("affiliate E(), solvency, arithmetic panics, InvalidBet, etc."). Rather than rely on category matching, ran the IDENTICAL HEAD test-tree against the pre-fix `AdvanceModule.sol` (the only file a303ae18 changed) and proved the HEAD failing set is a strict subset of the pre-fix failing set (0 new failures). Stronger than the planned subset-vs-prose check; same conclusion. Temporary swap restored byte-identically with sha256 + git-status proof — ZERO committed contract change.

## Known Stubs
None. All verification is on live `forge test` output; no placeholder/weakened assertions.

## Threat Flags
None. ZERO contracts/ mutation; no production attack surface introduced (D-43N-AUDIT-ONLY-01). The temporary pre-fix swap was a working-tree-only, byte-identically-restored, never-committed verification step.

## Threat Register Disposition (test-integrity)
- **T-313-06-01 (v43 harness silently modified / regressed):** mitigated — `git status` shows RngLockDeterminism.t.sol byte-identical AND it still PASSES (2/2 live + 16 skip).
- **T-313-06-02 (new failure masked as pre-existing):** mitigated — empirical `comm -23` HEAD-vs-pre-fix failing-function diff is EMPTY (0 new failures); the HEAD set is a strict subset.
- **T-313-06-03 (contract change sneaks into the test commit):** mitigated — `git status --porcelain contracts/` empty before/after; the temporary swap was restored byte-identically (sha256-verified) and never staged/committed; this plan commits only docs.
- **T-313-06-SC (slopcheck):** n/a — NO package installs; verification + git only.

## Phase 313 Joint Success-Criteria Roll-Up
With plans 313-01..04 (VTST-01..04 proving VRF-01..05) and 313-05 (regression migration), all five ROADMAP Phase 313 success criteria are jointly satisfied:
- forge build exit 0 + full suite restored to pre-fix baseline (0 new failures) — SC-5 PROVEN here.
- v43 RngLockDeterminism.t.sol harness still PASSES.
- AGENT-COMMITTED test bundle per D-43N-TEST-COMMITS-AUTO-01.

## Self-Check: PASSED
- FOUND: .planning/phases/313-tst-vrf-regression-freeze-invariant-fuzz-under-rotation-tst/313-06-SUMMARY.md
- All 8 bundle test files tracked & committed (611deb20 / 2f438ea2 / c4d7f627 / b4a63ac7 / ced272e7 / 6ad8338a).
- `forge build` exit 0; 4 VTST contracts PASS; v43 harness PASS (byte-identical); 313-05 migrations PASS.
- Empirical SC-5: 0 new failures (HEAD failing set ⊆ pre-fix 41546f16 failing set).
- `git diff --name-only 08c0f2aa..HEAD -- contracts/` empty → ZERO mainnet-contract mutation across the phase.
- AdvanceModule.sol sha256 restored to post-fix `cd665891...`; working tree clean.

---
*Phase: 313-tst-vrf-regression-freeze-invariant-fuzz-under-rotation-tst Plan 06*
*Completed: 2026-05-23*
