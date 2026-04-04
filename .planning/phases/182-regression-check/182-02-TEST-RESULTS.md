# 182-02 Test Results: Hardhat + Foundry Regression Check

**Date:** 2026-04-04
**Context:** v16.0-v17.1 delta (Module consolidation, storage repack, affiliate bonus cache, comment correctness sweep)
**Purpose:** Verify no unexpected regressions after v16.0-v17.1 changes, compared against v15.0 baseline (167-02-TEST-BASELINE.md)

---

## HARDHAT TEST RESULTS

### Compilation

```
Compiled 60 Solidity files successfully (evm target: paris)
Solidity 0.8.34 (viaIR: true, optimizer: 200 runs)
```

**Status:** PASS -- all 60 files compile without error.

### Per-Directory Results

| Directory   | Passing | Failing | Pending | Total | Notes |
|-------------|---------|---------|---------|-------|-------|
| access      | 38      | 0       | 0       | 38    | All access control guards verified |
| deploy      | 13      | 0       | 0       | 13    | Full 23-contract deploy pipeline |
| unit        | 940     | 5       | 3       | 948   | 1 affiliate bonus rate + 4 WWXRP decimal scaling |
| integration | 55      | 0       | 0       | 55    | VRF, charity hooks, game lifecycle |
| edge        | 124     | 0       | 0       | 124   | Compressed jackpot, multi-boon, RNG stall, whale, game-over |
| gas         | 16      | 0       | 0       | 16    | advanceGame gas profiling |
| **Total**   | **1186**| **5**   | **3**   |**1194**| **All failures classified EXPECTED** |

**Note:** `test/adversarial/` directory does not exist in this codebase. `test/validation/` (1 test file) is not included in the standard `npm test` script.

### Failure Analysis

All 5 failures are **EXPECTED** -- they result from intentional v17.0-v17.1 contract changes. No test files were modified.

#### Failure 1: DegenerusAffiliate -- affiliateBonusPointsBest

| # | Test Name | File | Error | Classification |
|---|-----------|------|-------|----------------|
| 1 | affiliateBonusPointsBest accumulates over previous 5 levels | DegenerusAffiliate.test.js:811 | expected 27 to equal 10 | EXPECTED |

**Root cause:** The v17.0 affiliate bonus cache (Phase 173) doubled the affiliate bonus rate from 1 point per 1 ETH to 1 point per 0.5 ETH (with tiered rates: 4pt/ETH for first 5 ETH, 1.5pt/ETH for next 20 ETH). The test asserts old expected value of 10 points for 10 ETH across 5 levels, but the new tiered rate produces 27 points. The contract behavior is correct per the new spec -- the test needs updating to reflect the new bonus rate.

#### Failures 2-5: WrappedWrappedXRP -- Decimal Scaling

| # | Test Name | File | Error | Classification |
|---|-----------|------|-------|----------------|
| 2 | donate(): increases wXRPReserves and emits Donated | WrappedWrappedXRP.test.js:304 | expected 1e32 to equal 1e20 | EXPECTED |
| 3 | donate(): multiple donations accumulate in reserves | WrappedWrappedXRP.test.js:342 | expected 3e32 to equal 3e20 | EXPECTED |
| 4 | unwrap(): burns WWXRP and transfers wXRP back to user, emits Unwrapped | WrappedWrappedXRP.test.js:396 | expected 50000000 to equal 5e19 | EXPECTED |
| 5 | undercollateralization: first-come-first-served, second fails when reserves depleted | WrappedWrappedXRP.test.js:850 | Expected InsufficientReserves, but didn't revert | EXPECTED |

**Root cause:** The v17.1 comment correctness sweep (commit 9c3e31bd) discovered that WrappedWrappedXRP's `donate()` and `unwrap()` functions were silently mishandling the decimal mismatch between wXRP (6 decimals) and WWXRP (18 decimals). The fix introduced a `WXRP_SCALING = 1e12` constant:
- `donate()` now scales wXRP amounts up by 1e12 when adding to reserves (18-decimal tracking)
- `unwrap()` now divides by 1e12 when transferring wXRP back (6-decimal transfer)
The tests assert old 1:1 behavior. The contract behavior is correct per the decimal fix -- the tests need updating to reflect the scaling.

### v15.0 Baseline Comparison

All 13 v15.0 expected failures are now **FIXED** (tests pass):

| v15.0 Expected Failure | Status |
|------------------------|--------|
| AFF-05 through AFF-09 (9 taper tests) | NOW PASSING |
| DegenerusAffiliate taper (3 tests) | NOW PASSING |
| SecurityEconHardening CoinPurchaseCutoff (1 test) | NOW PASSING |

### Hardhat Verdict

**PASS** -- 1186/1194 tests passing. All 5 failures are EXPECTED results of intentional v17.0-v17.1 contract changes (1 affiliate bonus rate change, 4 WWXRP decimal scaling fix). Zero unexpected regressions detected. All 13 v15.0 baseline expected failures have been fixed and now pass.
