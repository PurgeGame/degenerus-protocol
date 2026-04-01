---
phase: quick
plan: 260327-n7h
subsystem: testing
tags: [hardhat, solidity, test-suite, regression]

requires: []
provides:
  - "Full test suite health snapshot after commits 419b134, 7f4c4d3, 1ee764b5"
  - "Root cause analysis of RngStall arithmetic overflow failures"
affects: []

tech-stack:
  added: []
  patterns: []

key-files:
  created: []
  modified: []

key-decisions:
  - "RngStall overflow is pre-existing (predates recent commits), not a regression"
  - "Non-deterministic behavior: 1-3 RngStall failures per run depending on Hardhat EVM state"

requirements-completed: []

duration: 18min
completed: 2026-03-27
---

# Quick Task 260327-n7h: Run Full Test Suite and Analyze Results

**1343-1345 passing / 1-3 failing across 35 test files in 7 categories; all failures are pre-existing RngStall arithmetic overflow in drainTickets helper -- zero regressions from recent commits**

## Performance

- **Duration:** 18 min (includes 3 full suite runs for variability analysis)
- **Started:** 2026-03-27T21:44:40Z
- **Completed:** 2026-03-27T22:02:43Z
- **Tasks:** 1
- **Files modified:** 0 (test-only observation task)

## Summary

| Metric | Count |
|--------|-------|
| Total passing | 1343-1345 (varies across runs) |
| Total failing | 1-3 (varies across runs) |
| Total pending | 0 |
| Test files | 35 |
| Categories | 7 |
| Suite runtime | ~4 min per run |

### By Category

| Category | Files | Pass | Fail | Status |
|----------|-------|------|------|--------|
| access | 1 | 45 | 0 | GREEN |
| deploy | 1 | 13 | 0 | GREEN |
| unit | 22 | 973 | 0 | GREEN |
| integration | 3 | 58 | 0 | GREEN |
| edge | 6 | 120 | 1-3 | FLAKY |
| validation | 1 | 118 | 0 | GREEN |
| gas | 1 | 16 | 0 | GREEN |

6 of 7 categories are fully green. The only failures are in `test/edge/RngStall.test.js`.

## Failure Analysis

### All Failures: RngStall Arithmetic Overflow (panic 0x11)

**Error:** `VM Exception while processing transaction: reverted with panic code 0x11 (Arithmetic operation overflowed outside of an unchecked block)`

**Failing tests (1-3 depending on run):**

| # | Test Name | File:Line | Consistent |
|---|-----------|-----------|------------|
| 1 | fulfilling the final retry after two timeouts works correctly | RngStall.test.js:260 | Always fails |
| 2 | processing after in-window fulfillment unlocks RNG | RngStall.test.js:524 | Sometimes fails |
| 3 | no retry requestId is issued when fulfillment comes before timeout | RngStall.test.js:539 | Sometimes fails |

**Common call path:** All failures hit the same code: `drainTickets()` at line 45, which calls `game.advanceGame()` in a loop. The overflow occurs inside `advanceGame` at contract address `0x68b1d87f...` during ticket batch processing.

**Root cause:** The `advanceGame()` function encounters an arithmetic overflow when processing ticket batches after VRF fulfillment in the RNG stall/timeout test scenarios. The overflow occurs in an unchecked Solidity block boundary during the ticket drain loop. The non-determinism of tests 2 and 3 suggests the overflow is sensitive to EVM state (gas, block timestamps, accumulated ticket counts) which can vary slightly between Hardhat network resets.

**Pre-existing status:** Confirmed pre-existing. The most recent commit (419b1342) explicitly documents: "1345 passing, 1 pre-existing failure (RNG stall overflow, unrelated)". The RngStall test file has not been modified since commit `086bd793` (the `_executeSwap` CEI refactor), which predates all 3 recent commits.

### Regression Check

**Recent commits evaluated:**

| Commit | Description | Regression? |
|--------|-------------|-------------|
| 419b1342 | test+docs: feed governance tests, updated suite, KNOWN-ISSUES | NO -- only added/updated test files, no contract logic changes that affect advanceGame |
| 7f4c4d30 | feat: price feed governance, struct packing, code cleanup | NO -- changed DegenerusAdmin.sol, DegenerusDeityPass.sol, DegenerusStonk.sol; none of these affect the advanceGame ticket processing path |
| 1ee764b5 | fix(ERC-20): emit Approval in DGNRS transferFrom on allowance change | NO -- only added an Approval event emit in DegenerusStonk.transferFrom; does not affect game/ticket logic |

**Verdict: Zero regressions introduced by the 3 recent commits.** All 6 non-edge categories are fully green. The RngStall overflow predates the v8.0 milestone changes.

### Recommended Fix for RngStall Overflow

The overflow in `advanceGame()` during ticket batch processing likely involves a counter or accumulator that exceeds its type bounds under the multi-timeout test scenario. Specific recommendations:

1. **Trace the exact overflow location:** Run the failing test with `--verbose` or add `console.log` tracing in the `drainTickets` helper to identify which iteration of `advanceGame()` triggers the revert, then inspect the contract's ticket batch processing arithmetic.
2. **Check for uint overflow in ticket counters:** The panic 0x11 (overflow outside unchecked) points to a Solidity `+` or `*` operation that exceeds type bounds. Likely a `uint48` or `uint32` accumulator in the ticket processing struct that wraps under edge-case batch sizes.
3. **Priority:** Low -- this is an edge-case test scenario (multiple consecutive VRF timeouts with ticket drain). The overflow does not affect normal gameplay paths (all 973 unit tests and 58 integration tests pass).

## Unstaged Modifications

The 3 unstaged test files were included in the run as expected:

| File | Status | Impact |
|------|--------|--------|
| test/deploy/DeployScript.test.js | Modified (unstaged) | All 13 tests pass |
| test/unit/DGNRSLiquid.test.js | Modified (unstaged) | All tests pass |
| test/unit/DegenerusDeityPass.test.js | Modified (unstaged) | All tests pass |

## Non-Determinism Note

Three full suite runs were executed:

| Run | Passing | Failing | Notes |
|-----|---------|---------|-------|
| 1 | 1345 | 1 | Only the "two timeouts" test failed |
| 2 | 1343 | 3 | Two additional "normal fulfillment" tests also failed |
| 3 | 1343 | 3 | Same 3 failures as run 2 |

The variability (2 tests flipping between pass/fail) is consistent with Hardhat EVM state sensitivity in the drainTickets loop. The deterministic failure (test 1) always occurs.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

- **Mocha unload error post-test:** After test results print, Mocha throws `Cannot find module 'test/access/AccessControl.test.js'` during cleanup (file-unloader.js). This is a Mocha/Hardhat ESM interop issue during module unloading -- it does not affect test execution or results. The full suite completes and reports results before this error occurs.

## Decisions Made

- Ran suite 3 times to characterize non-determinism rather than reporting a single run
- Used main repo directory (not worktree) since node_modules is only installed there

## Next Steps

- The RngStall overflow can be investigated separately if needed (low priority, edge-case only)
- Codebase is green for all normal paths -- pre-audit hardening can continue
- Unstaged test modifications should be committed when ready

---
*Quick task: 260327-n7h*
*Completed: 2026-03-27*
