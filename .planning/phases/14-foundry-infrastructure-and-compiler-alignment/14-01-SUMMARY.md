---
phase: 14-foundry-infrastructure-and-compiler-alignment
plan: 01
status: complete
started: "2026-03-05"
completed: "2026-03-05"
---

# Summary: Compiler Alignment (14-01)

## What was done

1. **Updated foundry.toml** for solc 0.8.34: replaced `solc_version = "0.8.26"` with explicit binary path to Hardhat-cached solc 0.8.34, set `auto_detect_solc = false`, added `forge-std/` remapping, expanded `[invariant]` config with depth=128, shrink_run_limit=5000, show_metrics=true, dictionary tuning.

2. **Fixed pragma in 3 fuzz test files**: Changed `pragma solidity 0.8.26` to `pragma solidity ^0.8.26` in BurnieCoinInvariants.t.sol, PriceLookupInvariants.t.sol, and ShareMathInvariants.t.sol.

## Results

- `forge build --force`: Compiles 78 files with Solc 0.8.34 in ~14s, zero errors
- `forge test --match-path "test/fuzz/**"`: 21 tests passed, 0 failed across 3 suites
- Forge lint warnings present (unsafe-typecast, divide-before-multiply, unwrapped-modifier-logic) -- these are informational, not compilation errors

## Key files

- `foundry.toml` -- Updated config
- `test/fuzz/BurnieCoinInvariants.t.sol` -- Pragma fixed
- `test/fuzz/PriceLookupInvariants.t.sol` -- Pragma fixed
- `test/fuzz/ShareMathInvariants.t.sol` -- Pragma fixed

## Commits

- `025d709` feat(14-01): align Foundry compiler with solc 0.8.34

## Self-Check: PASSED

- [x] forge build compiles all production contracts with solc 0.8.34
- [x] All 3 existing fuzz invariant tests pass under 0.8.34
- [x] foundry.toml contains auto_detect_solc = false
- [x] All 3 test files contain ^0.8.26 pragma
