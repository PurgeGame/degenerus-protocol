# Phase 185: Test Suite Regression Check

## Foundry Results

**Command:** `forge test`
**Date:** 2026-04-04
**Baseline:** Phase 182 -- 382 passing, 2 expected failures (384 total)

### Summary

| Metric | Count |
|--------|-------|
| Passing | 382 |
| Failing | 2 |
| Skipped | 0 |
| **Total** | **384** |

### Failure Classification

| # | Suite | Test | Error | Classification | Baseline Match |
|---|-------|------|-------|----------------|----------------|
| 1 | TicketRouting.t.sol | testRngGuardAllowsWithPhaseTransition | RngLocked() | EXPECTED | Yes -- same as Phase 182 failure #1 |
| 2 | Composition.inv.t.sol | invariant_gapBitsAlwaysZero | mintPacked_ gap bits nonzero (replay) | EXPECTED | Yes -- same as Phase 182 failure #2 |

**Failure 1 root cause:** v16.0 module consolidation replaced inline `phaseTransitionActive` check with explicit `rngBypass` parameter. Test sets `phaseTransitionActive=true` but new guard checks `rngBypass`. Test needs updating to pass `rngBypass=true`.

**Failure 2 root cause:** v17.0 affiliate bonus cache stores data in mintPacked_ bits [185-214]. Composition invariant's gap-bit check covers bits 154-227, overlapping the new cache. The cached counterexample causes instant replay. Invariant handler needs updating to exclude the cache range.

### Foundry Verdict

**PASS** -- 382/384 tests passing. Both failures are EXPECTED (identical to Phase 182 baseline). Zero unexpected regressions from Phase 183 fixes.

---

## Hardhat Results

**Command:** `npx hardhat test`
**Date:** 2026-04-04
**Baseline:** Phase 182 -- 1184 passing, 7 expected failures, 3 pending (1194 total)

### Summary

| Metric | Count |
|--------|-------|
| Passing | 1304 |
| Failing | 5 |
| Pending | 3 |
| **Total** | **1312** |

### Baseline Comparison

| Metric | Phase 182 Baseline | Phase 185 Current | Delta |
|--------|-------------------|-------------------|-------|
| Passing | 1184 | 1304 | +120 |
| Failing | 7 | 5 | -2 (improvement) |
| Pending | 3 | 3 | 0 |
| Total | 1194 | 1312 | +118 |

The +120 passing / +118 total increase reflects new tests added between v17.1 and the current codebase (affiliate hardening, edge cases, GNRUS governance, deity pass, VRF integration tests).

The -2 failure reduction: Phase 182 had 2 GameOver NotTimeYet() failures (advanceGame after gameOver handleFinalSweep path; advanceGame before 30 days no sweep). These are no longer present in the failure list, indicating they were resolved by intervening test or contract updates.

### Failure Classification

| # | Suite | Test | Error | Classification | Baseline Match |
|---|-------|------|-------|----------------|----------------|
| 1 | DegenerusAffiliate | affiliateBonusPointsBest accumulates over previous 5 levels | expected 27 to equal 10 | EXPECTED | Yes -- same as Phase 182 failure #1 |
| 2 | WrappedWrappedXRP | donate() increases wXRPReserves and emits Donated | expected 1e32 to equal 1e20 | EXPECTED | Yes -- same as Phase 182 failure #2 |
| 3 | WrappedWrappedXRP | donate() multiple donations accumulate in reserves | expected 3e32 to equal 3e20 | EXPECTED | Yes -- same as Phase 182 failure #3 |
| 4 | WrappedWrappedXRP | unwrap() burns WWXRP and transfers wXRP back | expected 5e7 to equal 5e19 | EXPECTED | Yes -- same as Phase 182 failure #4 |
| 5 | WrappedWrappedXRP | undercollateralization first-come-first-served | Expected InsufficientReserves revert, didn't revert | EXPECTED | Yes -- same as Phase 182 failure #5 |

**Failure 1 root cause:** v17.0 affiliate bonus cache doubled the bonus rate (tiered: 4pt/ETH first 5 ETH, 1.5pt/ETH next 20 ETH). Test expects old accumulation value of 10 but contract returns 27.

**Failures 2-5 root cause:** WrappedWrappedXRP is a post-v15.0 contract. Tests use wrong decimal expectations (mismatch between wXRP token decimals and 18-decimal assumptions in test assertions).

### Pending Tests (3)

| Test Name | Reason |
|-----------|--------|
| accumulates flip progress and emits QuestProgressUpdated | Skipped (pending hook) |
| completing FLIP quest after MINT_ETH earns QUEST_RANDOM_REWARD | Skipped (pending hook) |
| slot 1 FLIP cannot complete before slot 0 | Skipped (pending hook) |

### Mocha Cleanup Error

After all tests complete, mocha's file-unloader throws `Cannot find module 'test/access/AccessControl.test.js'`. This is a test runner cleanup issue (the access control tests run under a different file path), not a test failure. All 1312 tests execute and report results before this error. This same error is pre-existing and unrelated to Phase 183 changes.

### Hardhat Verdict

**PASS** -- 1304/1312 tests passing. All 5 failures are EXPECTED (subset of Phase 182 baseline -- 2 GameOver failures resolved). Zero unexpected regressions from Phase 183 fixes.

---

## Combined Results

### Summary

| Framework | Passing | Expected Failures | Unexpected Failures | Pending | Total |
|-----------|---------|-------------------|---------------------|---------|-------|
| Foundry   | 382     | 2                 | 0                   | 0       | 384   |
| Hardhat   | 1304    | 5                 | 0                   | 3       | 1312  |
| **Total** | **1686**| **7**             | **0**               | **3**   |**1696**|

### Phase 182 vs Phase 185 Comparison

| Metric | Phase 182 (v18.0) | Phase 185 (v18.0 + Phase 183 fixes) | Delta |
|--------|-------------------|--------------------------------------|-------|
| Foundry passing | 382 | 382 | 0 |
| Foundry expected failures | 2 | 2 | 0 |
| Hardhat passing | 1184 | 1304 | +120 |
| Hardhat expected failures | 7 | 5 | -2 |
| Hardhat pending | 3 | 3 | 0 |
| **Combined passing** | **1566** | **1686** | **+120** |
| **Combined expected failures** | **9** | **7** | **-2** |
| **Combined unexpected** | **0** | **0** | **0** |

The +120 passing increase and -2 failure reduction are from new tests added post-Phase 182 and 2 GameOver test fixes -- both unrelated to Phase 183. The Phase 183 changes (deferred SSTORE + variable renames) introduced zero new failures.

## Combined Verdict

**DELTA-03: VERIFIED** -- Foundry 382 passing / 2 expected failures, Hardhat 1304 passing / 5 expected failures. Zero unexpected regressions from Phase 183 fixes (paidEth capture, deferred futurePool SSTORE, futurePoolBal/futurePoolLocal variable renames). All 7 expected failures are pre-existing and match the Phase 182 baseline (or are resolved subsets of it).
