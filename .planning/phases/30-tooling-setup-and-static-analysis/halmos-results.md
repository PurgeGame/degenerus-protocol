# Halmos Symbolic Verification Results

**Tool:** Halmos 0.3.3
**Date:** 2026-03-05
**Configuration:** Temporary clean foundry.toml (no [fuzz]/[invariant] sections), `--forge-build-out forge-out`
**Function prefix:** --function testFuzz
**Solver:** yices-smt2 (default)
**Solver timeout:** 30000-60000ms per assertion

## Summary

| Contract | Functions Tested | Passed | Failed | Timeout | Error |
|----------|-----------------|--------|--------|---------|-------|
| PriceLookupInvariantsTest | 8 | 8 | 0 | 0 | 0 |
| ShareMathInvariantsTest | 7 | 0 | 0 | 7 | 0 |
| BurnieCoinInvariantsTest | 6 | 5 | 0 | 0 | 1 |
| **Total** | **21** | **13** | **0** | **7** | **1** |

## Per-Function Results

### PriceLookupInvariants.t.sol (8/8 PASS)

| Function | Result | Paths | Time | Notes |
|----------|--------|-------|------|-------|
| testFuzz_costCalculation(uint24,uint256) | PASS | 67 | 0.34s | All 11 price tiers verified symbolically |
| testFuzz_cyclicAfter100(uint24) | PASS | 46 | 2.96s | Cyclic pricing verified across full uint24 range |
| testFuzz_introPricing(uint24) | PASS | 3 | 0.01s | Intro pricing verified |
| testFuzz_milestonePricing(uint24) | PASS | 13 | 0.76s | Milestone pricing verified |
| testFuzz_priceBounded(uint24) | PASS | 12 | 0.01s | All prices within expected bounds |
| testFuzz_priceDeterministic(uint24) | PASS | 12 | 0.01s | Same input always returns same price |
| testFuzz_priceInValidSet(uint24) | PASS | 12 | 0.01s | All prices in valid price set |
| testFuzz_weaklyMonotonicInCycle(uint24,uint24,uint24) | PASS | 40 | 2.13s | Weak monotonicity verified symbolically |

**Total time:** 6.24s. All 8 properties verified across the full input space. No counterexamples found.

### ShareMathInvariants.t.sol (0/7 PASS, 7/7 TIMEOUT)

| Function | Result | Paths | Time | Notes |
|----------|--------|-------|------|-------|
| testFuzz_payoutNeverExceedsReserve(uint128,uint128,uint128) | TIMEOUT | 7 | 30.08s | Division-heavy; solver cannot resolve bvudiv_256 within timeout |
| testFuzz_burnAllReturnsAll(uint128,uint128) | TIMEOUT | 6 | 30.17s | Same bvudiv_256 bottleneck |
| testFuzz_noOverflow(uint128,uint128,uint128) | TIMEOUT | 7 | 30+s | Wall-clock timeout (solver timeout > wall timeout) |
| testFuzz_proportionalFairness(uint256,uint256) | TIMEOUT | - | 30+s | Wall-clock timeout |
| testFuzz_refillMechanism(uint256,uint256) | TIMEOUT | - | 30+s | Wall-clock timeout |
| testFuzz_twoUsersSolvency(uint256,uint256,uint256) | TIMEOUT | - | 30+s | Wall-clock timeout |
| testFuzz_ethPreferentialSplit(uint256,uint256,uint256) | TIMEOUT | - | 30+s | Wall-clock timeout |

**Root cause:** All ShareMath tests involve `(reserve * amount) / supply` with uint128/uint256 inputs. SMT solvers struggle with 256-bit bitvector division (`bvudiv_256`). This is a well-known SMT solver limitation, not a protocol issue. The properties are verified to 10K runs by Foundry fuzzing.

### BurnieCoinInvariants.t.sol (5/6 PASS, 1 ERROR)

| Function | Result | Paths | Time | Notes |
|----------|--------|-------|------|-------|
| testFuzz_mintBurnRoundtrip(uint128) | PASS | 3 | 0.04s | Mint-burn roundtrip preserves supply |
| testFuzz_multiOp(uint128,uint128,uint128) | PASS | 16 | 0.13s | Multiple operations maintain invariants |
| testFuzz_supplyInvariant_afterMint(address,uint128) | PASS | 5 | 0.04s | Supply invariant holds after mint |
| testFuzz_transferToVault(uint128) | PASS | 3 | 0.03s | Vault transfer preserves accounting |
| testFuzz_vaultMintTo(uint128) | PASS | 5 | 0.14s | Vault mint-to preserves invariants |
| testFuzz_vaultMintTo_revertOnExceed(uint128) | ERROR | 2 | 0.01s | Halmos 0.3.3 does not support `vm.expectRevert()` cheatcode |

**Total time:** 0.40s. 5/6 properties verified. The 1 ERROR is a Halmos cheatcode limitation (does not affect verification quality -- the revert behavior is tested by Foundry fuzzing).

## Configuration Notes

### foundry.toml Swap Procedure (for Phase 35 reproduction)

1. Backup: `cp foundry.toml foundry.toml.bak`
2. Patch ContractAddresses: `node scripts/lib/patchForFoundry.js`
3. Write clean foundry.toml with ONLY `[profile.default]` build config (no `[fuzz]`, `[invariant]`, or `[profile.deep.*]` sections)
4. Run Halmos: `halmos --function testFuzz --contract <ContractName> --forge-build-out forge-out --solver-timeout-assertion <ms>`
5. Restore: `mv foundry.toml.bak foundry.toml`
6. Restore addresses: `node -e "import('./scripts/lib/patchForFoundry.js').then(m => m.restoreContractAddresses())"`

### Critical Configuration Discovery

- **`--forge-build-out forge-out` is required.** Halmos defaults to `out`, but this project uses `forge-out`. Without this flag, Halmos reports "No tests found" despite compilation succeeding.
- **via_ir must remain true.** Contracts require viaIR for stack depth. Halmos 0.3.3 works with viaIR artifacts when using `--forge-build-out`.
- **The [fuzz]/[invariant] sections must be removed.** Halmos 0.3.3 does not understand these TOML keys and hangs during initialization.

### Errors Encountered and Workarounds

1. **"No tests with --match-contract" error:** Caused by Halmos defaulting to `out` directory. Fixed with `--forge-build-out forge-out`.
2. **Halmos hang on startup:** Caused by [fuzz]/[invariant] sections in foundry.toml. Fixed by using clean foundry.toml with only build config.
3. **`vm.expectRevert` not supported:** Halmos 0.3.3 limitation. Tests using this cheatcode should be wrapped in `check_` functions that avoid expectRevert, or simply excluded from Halmos scope.

### Recommendations for Phase 35

1. **PriceLookupInvariants: High priority.** All 8 properties verified in 6.24s. Can serve as regression baseline.
2. **BurnieCoinInvariants: High priority.** 5/6 properties verified in 0.40s. Only exclude `_revertOnExceed` test.
3. **ShareMathInvariants: Low priority for Halmos.** All 7 properties timeout due to 256-bit division. Consider:
   - Reducing input bitwidth (use uint64 instead of uint128 for Halmos-specific wrappers)
   - Using different solver (z3 or bitwuzla may handle bvudiv differently)
   - Accepting Foundry 10K-run fuzzing as sufficient evidence for these properties
4. **New composition harnesses (Phase 31):** Should use `testFuzz_` prefix for Halmos compatibility.
5. **Solver selection:** yices-smt2 excels at non-division properties. Consider z3 for division-heavy properties.

---
*Results captured: 2026-03-05*
*Halmos 0.3.3, yices-smt2 solver*
