# Coverage Baseline — Phase 120

**Date:** 2026-03-26
**Purpose:** Document test suite baselines before any v6.0 contract changes.

## Test Suite Results

| Suite | Tests | Passed | Failed | Time |
|-------|-------|--------|--------|------|
| Foundry | 369 | 369 | 0 | ~4m |
| Hardhat | 1242 | 1242 | 0 | ~4m |
| **Total** | **1611** | **1611** | **0** | |

## LCOV Coverage Reports

**Status:** Not feasible for this codebase.

Both `forge coverage` and `npx hardhat coverage` fail with "stack too deep" compiler errors during coverage instrumentation. The Degenerus Protocol contracts exceed the EVM stack depth limit when the Solidity compiler adds coverage tracking variables.

**Attempts:**
1. `forge coverage --report lcov` — Stack too deep in BurnieCoin.sol:948
2. `forge coverage --report lcov --via-ir` — Overridden by coverage mode, same error
3. `forge coverage --report lcov --ir-minimum` — Compiled but 1 gas test failed (IR changes gas profile), no LCOV generated
4. `npx hardhat coverage` — YulException stack too deep in DegeneretteModule.sol:1226

**Impact on Phase 125 (test pruning):** Redundancy analysis will use test file inspection and function-level coverage tracing instead of LCOV line-level reports. The 1611-test green baseline provides the regression safety net.

## Per-Suite File Counts

| Category | Foundry | Hardhat |
|----------|---------|---------|
| Test files | 29 | 44 |
| Test suites | 43 | ~40 |
| Helper files | DeployProtocol.sol + helpers/ | deployFixture.js + helpers/ |

---
*Generated: 2026-03-26 after Phase 120 test cleanup*
