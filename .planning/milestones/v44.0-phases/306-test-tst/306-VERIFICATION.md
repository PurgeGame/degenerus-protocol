---
phase: 306-test-tst
verified: 2026-05-19T15:27:51Z
status: passed
score: 13/13 must-haves verified
overrides_applied: 0
deferred:
  - truth: "REQUIREMENTS.md `[ ]` checkboxes and Traceability `Pending` rows updated for INV-01..12, TST-02, TST-07, EDGE-01..18"
    addressed_in: "Phase 308 TERMINAL"
    evidence: "REQUIREMENTS.md Traceability table line 160-205 marks INV-NN/EDGE-NN as 'attest at 308 §3.F'; FINDINGS-v44.0.md §3.C + §3.F is the closure-attestation pass that flips these rows. Phase 308 success criteria 1 (REQUIREMENTS.md §3.C INV-01..12 attested as proven by specific test IDs) addresses this gap."
  - truth: "REQUIREMENTS.md entries created for INV-13, EDGE-19, EDGE-20 (Phase 305 additions not back-ported into the requirements register)"
    addressed_in: "Phase 308 TERMINAL"
    evidence: "These IDs are Phase-305 emergent additions documented in 305-01-SUMMARY.md and ROADMAP §306 Plan 01/02; Phase 308 TERMINAL §3.F INV attestation matrix is where they receive their requirement-row formalization. Plan 306-01-SUMMARY.md cites D-306-01-INV-13-PROVEN-01 in STATE.md as the load-bearing v44.0 closure assertion."
---

# Phase 306: Test (TST) Verification Report

**Phase Goal:** Foundry TST closure for v44.0 sStonk per-day source — mechanize all 13 INV-NN formal accounting properties + 20 EDGE-NN scenarios + 6 ROADMAP-canonical per-function fuzz functions + V-184 byte-identity assertion (vm.skip flip) + 2 gas regression assertions (burn ≤ v43+5%, claim ≤ v43+0%).

**Verified:** 2026-05-19T15:27:51Z
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| #   | Truth                                                                                                                            | Status     | Evidence                                                                                                                                                  |
| --- | -------------------------------------------------------------------------------------------------------------------------------- | ---------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | All 5 plans have SUMMARY.md (and 306-05-GAS-BASELINE.md for plan 5)                                                              | VERIFIED   | `ls .planning/phases/306-test-tst/` shows 306-01-SUMMARY.md through 306-05-SUMMARY.md + 306-05-GAS-BASELINE.md                                            |
| 2   | All 5 plans' files_modified declarations match actual git-tracked file changes                                                  | VERIFIED   | git log shows 5 test commits (`de75f620`, `333c803f`+`3143ea9c`, `d24a2487`, `b102bc0f`, `e0f7d77e`) touching only test/* + planning/* — see Artifacts table |
| 3   | 13 invariant_INV_NN_* function names present in test/invariant/RedemptionAccounting.t.sol                                       | VERIFIED   | `grep -oE "invariant_INV_[0-9]{2}_[A-Za-z]+" \| sort -u` returns all 13 names verbatim (INV_01_WriteOnceRoll through INV_13_SinglePoolPending)             |
| 4   | All 13 INV invariants PASS at FOUNDRY_PROFILE=deep                                                                              | VERIFIED   | Live `forge test` run: 13 passed; 0 failed; 0 skipped; 22.28s; per-invariant 256 runs × 128 depth × 32768 calls; per-action ~6500 calls each              |
| 5   | 20 testFuzz_EDGE_NN_* function names present in test/fuzz/RedemptionEdgeCases.t.sol                                            | VERIFIED   | `grep -oE "testFuzz_EDGE_[0-9]{2}_[A-Za-z0-9_]+" \| sort -u` returns all 20 names verbatim including EDGE-07 V184AttackReproductionStructuralClosure       |
| 6   | All 20 EDGE fuzz functions PASS at 10k runs                                                                                     | VERIFIED   | Live `forge test` run: 20 passed; 0 failed; 0 skipped; 2.37s; each fn 10000 runs                                                                          |
| 7   | EDGE-07 V-184 byte-identity assertion present                                                                                   | VERIFIED   | RedemptionEdgeCases.t.sol:687 `assertEq(uint256(rollPostAttack), uint256(rollPre), ...)` + lines 651, 669 capture rollPre / rollMid; sentinel checks at 656, 673 |
| 8   | 6 ROADMAP-canonical + 2 ACL/sentinel per-function tests in test/fuzz/StakedStonkRedemption.t.sol                                 | VERIFIED   | `grep` returns 8 testFuzz_* names — all 6 ROADMAP-canonical + testFuzz_ResolveRevertsForNonGame + testFuzz_BurnSetsSentinelOnFirstBurnOfDay              |
| 9   | All 8 per-function fuzz tests PASS at 10k runs                                                                                  | VERIFIED   | Live `forge test` run: 8 passed; 0 failed; 0 skipped; 741ms                                                                                              |
| 10  | vm.skip(true) at test/fuzz/RngLockDeterminism.t.sol line 1278 removed; testFuzz_RngLockDeterminism_StakedStonkRedemption PASSES | VERIFIED   | Line 1277 contains "FLIPPED at v44.0" natspec; line 1278 = `vm.assume(vrfWord != 0);` (no vm.skip); Live `forge test` run: 1 passed (1000 runs, 439ms)    |
| 11  | test_gas_regression_burn + test_gas_regression_claim present with theoretical-worst-case derivation                              | VERIFIED   | RedemptionGas.t.sol:29-42 has 4 baseline constants; lines 194 + 222 define the 2 regression fns; 306-05-GAS-BASELINE.md §2.1+§2.2 derive worst case      |
| 12  | Both gas regression assertions PASS                                                                                              | VERIFIED   | Live `forge test`: actual_burn_gas=198109 ≤ BURN_LIMIT_V44=282257 (-29.8% vs v43); actual_claim_gas=154823 ≤ CLAIM_LIMIT_V44=364565 (-57.5% vs v43)        |
| 13  | Zero contracts/*.sol mutations across all 5 phase-306 commits                                                                    | VERIFIED   | `git diff --stat 213f9184..HEAD -- 'contracts/*.sol'` returns EMPTY; phase-305 closure HEAD 213f9184 → current HEAD 8336670d shows zero contract churn   |

**Score:** 13/13 truths verified

### Deferred Items

| # | Item | Addressed In | Evidence |
|---|------|--------------|----------|
| 1 | REQUIREMENTS.md `[ ]` checkboxes and Traceability `Pending` rows for INV-01..12, TST-02, TST-07, EDGE-01..18 | Phase 308 TERMINAL | REQUIREMENTS.md Traceability table line 160-205 marks INV-NN/EDGE-NN as "attest at 308 §3.F"; Phase 308 §3.C INV attestation + §3.F invariant attestation matrix is the closure-flip pass |
| 2 | REQUIREMENTS.md entries created for INV-13, EDGE-19, EDGE-20 (Phase 305 additions) | Phase 308 TERMINAL | Phase 305 emergent IDs are documented in 305-01-SUMMARY.md + ROADMAP §306 Plan 01/02 + STATE.md `D-306-01-INV-13-PROVEN-01`; Phase 308 §3.F is the canonical attestation register |

### Required Artifacts

| Artifact                                              | Expected                                                                                       | Status     | Details                                                                                          |
| ----------------------------------------------------- | ---------------------------------------------------------------------------------------------- | ---------- | ------------------------------------------------------------------------------------------------ |
| `test/invariant/RedemptionAccounting.t.sol`           | 13 invariant_INV_NN_* fns; PASS at deep                                                        | VERIFIED   | NEW, 25241 bytes, 13/13 PASS at 256×128                                                          |
| `test/fuzz/handlers/RedemptionHandler.sol`            | v44 refresh: 6 SLOT_* constants, 10 per-day ghosts, 5 action selectors                         | VERIFIED   | REWRITTEN, 26841 bytes; supports invariant harness                                               |
| `test/fuzz/RedemptionEdgeCases.t.sol`                 | 20 testFuzz_EDGE_NN_* fns; PASS at 10k runs                                                    | VERIFIED   | NEW, 79255 bytes, 20/20 PASS; EDGE-07 V-184 byte-identity assertion at line 687                  |
| `test/fuzz/StakedStonkRedemption.t.sol`               | 6 ROADMAP-canonical + 2 ACL/sentinel testFuzz_*; PASS at 10k runs                              | VERIFIED   | NEW, 41279 bytes, 8/8 PASS                                                                       |
| `test/fuzz/RngLockDeterminism.t.sol`                  | vm.skip flipped at line 1278; testFuzz_RngLockDeterminism_StakedStonkRedemption PASSES        | VERIFIED   | Line 1277 FLIPPED natspec; vm.skip count 17→16 (one fewer than v43.0 baseline); 1/1 PASS         |
| `test/fuzz/RedemptionGas.t.sol`                       | test_gas_regression_burn + test_gas_regression_claim with theoretical-worst-case derivation    | VERIFIED   | EXTENDED 149→259 lines; 4 baseline constants; both regression assertions PASS                    |
| `.planning/phases/306-test-tst/306-05-GAS-BASELINE.md`| Theoretical worst-case + v43 baseline capture                                                  | VERIFIED   | NEW, contains §2.1 + §2.2 per-line per-op attribution tables; assertion limits documented        |
| `foundry.toml`                                        | `test = "test"` (widened from `test/fuzz` to include test/invariant)                          | VERIFIED   | Plan-01 decision D-306-01-FOUNDRY-TEST-DIR-01; confirmed `test = "test"` at line 3              |

### Key Link Verification

| From                                                                                   | To                                            | Via                                              | Status   | Details                                                                                  |
| -------------------------------------------------------------------------------------- | --------------------------------------------- | ------------------------------------------------ | -------- | ---------------------------------------------------------------------------------------- |
| RedemptionAccounting.t.sol::invariant_INV_13_SinglePoolPending                         | sdgnrs.pendingResolveDay()                    | scans daysWritten; asserts ≤1 non-empty + sentinel | WIRED    | PROVEN at 256 runs × 128 depth × 32768 calls; zero ghost drift                          |
| RedemptionAccounting.t.sol::invariant_INV_01_WriteOnceRoll                             | handler.ghost_perDay_firstRoll[D]             | assertEq across resolved days                    | WIRED    | PROVEN at 32k calls; first-write latched in handler ghosts                              |
| RedemptionHandler.sol::action_burn                                                     | ghost_perDay_ethBase + sentinel ghost         | per-day composite-keyed ghost update             | WIRED    | 6547 successful burn calls in invariant run; ghost updates verified by INV-02/INV-04   |
| RedemptionEdgeCases.t.sol::testFuzz_EDGE_07                                            | redemptionPeriods[D].roll byte-identity        | assertEq(rollPostAttack, rollPre)                | WIRED    | 10000 fuzz runs PASS; V-184 attack vector exercised + structural closure confirmed       |
| RedemptionEdgeCases.t.sol::testFuzz_EDGE_19                                            | sdgnrs.pendingResolveDay()                    | sentinel-pre + sentinel-mid + sentinel-post-clear | WIRED    | 7 hits on sdgnrs.pendingResolveDay() across EDGE-19 body; multi-day stall covered       |
| RedemptionEdgeCases.t.sol::testFuzz_EDGE_20                                            | BurnTooSmall revert                           | vm.expectRevert(BurnTooSmall.selector)            | WIRED    | 2 hits in EDGE-20 body (sub-min boundary + exact MIN_BURN_AMOUNT-1)                     |
| RngLockDeterminism.t.sol::testFuzz_RngLockDeterminism_StakedStonkRedemption           | _captureStonkRedemptionOutputs                | byte-identity keccak(pendingRedemptionEthValue + balance) | WIRED  | 1000-run PASS at default fuzz; v44 bound-adjustments allow legitimate exercise            |
| RedemptionGas.t.sol::test_gas_regression_burn                                          | BURN_LIMIT_V44 constant                       | assertLe(actualGas, BURN_LIMIT_V44)              | WIRED    | actual 198109 ≤ 282257; -29.8% under v43 baseline                                       |
| RedemptionGas.t.sol::test_gas_regression_claim                                         | CLAIM_LIMIT_V44 constant                      | assertLe(actualGas, CLAIM_LIMIT_V44)             | WIRED    | actual 154823 ≤ 364565; -57.5% under v43 baseline                                       |

### Behavioral Spot-Checks

| Behavior                                                              | Command                                                                                              | Result                          | Status   |
| --------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- | ------------------------------- | -------- |
| 13 INV invariants PASS                                                | `forge test --match-path "test/invariant/RedemptionAccounting.t.sol"`                                | 13 passed; 0 failed; 22.28s     | PASS     |
| 20 EDGE fuzz functions PASS                                           | `forge test --match-path "test/fuzz/RedemptionEdgeCases.t.sol"`                                      | 20 passed; 0 failed; 2.37s      | PASS     |
| 8 per-function fuzz tests PASS                                        | `forge test --match-path "test/fuzz/StakedStonkRedemption.t.sol"`                                    | 8 passed; 0 failed; 741ms       | PASS     |
| V-184 flipped strict-assertion test PASSES                            | `forge test --match-path "test/fuzz/RngLockDeterminism.t.sol" --match-test "testFuzz_RngLockDeterminism_StakedStonkRedemption"` | 1 passed; 0 failed; 1000 runs | PASS     |
| 2 gas regression assertions PASS                                      | `forge test --match-path "test/fuzz/RedemptionGas.t.sol" --match-test "test_gas_regression"`         | 2 passed; burn -29.8%; claim -57.5% | PASS  |
| forge build clean                                                     | `forge build 2>&1 \| tail -3`                                                                        | exit 0; lint warnings only      | PASS     |
| Zero contracts/*.sol mutations across phase 306                       | `git diff --stat 213f9184..HEAD -- 'contracts/*.sol'`                                                | empty                           | PASS     |

### Requirements Coverage

Cross-referenced against REQUIREMENTS.md + ROADMAP §306 + plan frontmatter requirements arrays.

| Requirement | Source Plan        | Description                                                                       | Status     | Evidence                                                                                            |
| ----------- | ------------------ | --------------------------------------------------------------------------------- | ---------- | --------------------------------------------------------------------------------------------------- |
| TST-01      | 306-03             | Per-function fuzz coverage at StakedStonkRedemption.t.sol                         | SATISFIED  | 6 ROADMAP-canonical names verbatim present; 8/8 PASS at 10k                                         |
| TST-02      | 306-01             | Foundry invariant test harness at RedemptionAccounting.t.sol                      | SATISFIED  | 13/13 INV-NN PASS at deep; INV-01..12 + INV-13 superset                                            |
| TST-03      | 306-02             | Edge-case coverage at RedemptionEdgeCases.t.sol                                   | SATISFIED  | 20/20 EDGE PASS at 10k                                                                              |
| TST-04      | 306-02             | V-184 attack reproduction (EDGE-07)                                               | SATISFIED  | testFuzz_EDGE_07_V184AttackReproductionStructuralClosure PASS at 10k; assertEq byte-identity present |
| TST-05      | 306-04             | Phase 301 vm.skip flip → strict byte-identity                                     | SATISFIED  | line 1278 vm.skip removed; testFuzz_RngLockDeterminism_StakedStonkRedemption PASSES                  |
| TST-06      | 306-05             | Gas regression: burn ≤ +5% v43, claim ≤ +0% v43                                  | SATISFIED  | burn 198109 ≤ 282257 (-29.8%); claim 154823 ≤ 364565 (-57.5%)                                       |
| TST-07      | 306-01             | Build + full test suite                                                            | SATISFIED  | forge build exit 0; phase 306 test suites all PASS                                                  |
| INV-01..12  | 306-01             | 12 SPEC-locked accounting invariants                                              | SATISFIED  | 12 named invariant_INV_NN_* fns present + PROVEN at 256×128 depth                                  |
| INV-13      | 306-01             | Single-pool invariant (Phase 305 addition)                                        | SATISFIED  | invariant_INV_13_SinglePoolPending PROVEN at deep                                                   |
| EDGE-01..18 | 306-02             | 18 SPEC-locked edge scenarios                                                     | SATISFIED  | 18 named testFuzz_EDGE_NN_* fns PASS at 10k                                                         |
| EDGE-19     | 306-02             | Multi-day RNG stall sentinel correctness (Phase 305 addition)                    | SATISFIED  | testFuzz_EDGE_19_MultiDayRngStallStaleClaimRecovery PASS at 10k                                     |
| EDGE-20     | 306-02             | MIN_BURN_AMOUNT dust floor (Phase 305 addition)                                   | SATISFIED  | testFuzz_EDGE_20_BurnTooSmall PASS at 10k                                                           |
| REG-01      | 306-04             | v43.0 NON-WIDENING attestation                                                    | SATISFIED  | git diff scope per 306-04-SUMMARY.md table: only the 4 prescribed edits + Phase 305 cascade fix    |

**Note on requirements-bookkeeping deferral:** REQUIREMENTS.md still shows `[ ]` (unchecked) checkboxes and `Pending` Traceability rows for INV-01..12, TST-02, TST-07, and EDGE-01..18 even though their underlying artifacts are PROVEN in code. Per the REQUIREMENTS.md Traceability annotation ("attest at 308 §3.F"), these rows flip at Phase 308 TERMINAL. INV-13, EDGE-19, EDGE-20 are not registered in REQUIREMENTS.md as standalone rows (they are Phase 305 emergent additions documented elsewhere — see Deferred Items). Both items are deferred to Phase 308 TERMINAL.

### Anti-Patterns Found

| File                                        | Line | Pattern                | Severity | Impact                            |
| ------------------------------------------- | ---- | ---------------------- | -------- | --------------------------------- |
| (none across the 6 phase-306 modified files) | -    | TBD/FIXME/XXX scan returned 0; TODO/HACK/placeholder scan returned 0 | -        | clean                             |

### Human Verification Required

None — every truth was checked programmatically through forge test, grep, and git diff. The 13 INV invariants, 20 EDGE fuzz tests, 8 per-function fuzz tests, 1 V-184 strict assertion, and 2 gas regression assertions all PASSED live during this verification. Zero contract mutations confirmed via git diff.

### Gaps Summary

No gaps blocking goal achievement. The phase goal — "mechanize all 13 INV-NN formal accounting properties + 20 EDGE-NN scenarios + 6 ROADMAP-canonical per-function fuzz functions + V-184 byte-identity assertion (vm.skip flip) + 2 gas regression assertions" — is fully achieved with all artifacts PROVEN in the codebase via live test runs at this verification.

**Two minor bookkeeping deferrals** (REQUIREMENTS.md checkbox/traceability flips for INV-01..12 + TST-02 + TST-07 + EDGE-01..18, and explicit row creation for INV-13 + EDGE-19 + EDGE-20) are deferred to Phase 308 TERMINAL per the explicit "attest at 308 §3.F" annotation in REQUIREMENTS.md Traceability. These do not block goal achievement at Phase 306.

**Notes on bonus deliveries (above the must-have baseline):**

1. **INV-13 + EDGE-19 + EDGE-20** — these 3 properties were added during Phase 305 IMPL execution as load-bearing structural-closure mechanisms. Phase 306 mechanized them alongside the SPEC-locked INV-01..12 + EDGE-01..18, yielding 13 INV + 20 EDGE rather than 12 INV + 18 EDGE.
2. **2 augment per-function tests** (testFuzz_ResolveRevertsForNonGame + testFuzz_BurnSetsSentinelOnFirstBurnOfDay) — added beyond the 6 ROADMAP-canonical names for ACL + INV-13 sentinel-lifecycle per-function coverage.
3. **Gas regression OVER-PERFORMS targets** — burn is -29.8% under v43 baseline (target was ≤ +5%); claim is -57.5% under v43 (target was ≤ +0%). The 1-slot DayPending packing (D-305-STRUCT-TIGHTEN-01) and gwei-snap (D-305-GWEI-SNAP-01) produce substantial gas reductions.

**HANDOFF-111..117 closure attribution** (cited in 306-04-SUMMARY.md): 1 vm.skip block flipped to strict assertion (HANDOFF-111 explicit) + 6 catalog rows close structurally via FIXREC §0.6 subsumption (HANDOFF-112..117 — V-186/V-188/V-190/V-191/V-192/V-193). Phase 308 §3.D RESOLVED-AT-V44 attestation can cite this 7-row closure via TST-04 (EDGE-07) + TST-05 (flipped strict assertion) + INV-13 (single-pool invariant).

---

_Verified: 2026-05-19T15:27:51Z_
_Verifier: Claude (gsd-verifier)_
