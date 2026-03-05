# Halmos Symbolic Verification Results v2

**Tool:** Halmos 0.3.3
**Date:** 2026-03-05
**Configuration:** Temporary clean foundry.toml (no [fuzz]/[invariant] sections), `--forge-build-out forge-out`, `test = "test"` (to include test/halmos/ directory)
**Function prefix:** --function check
**Solver:** yices-smt2 (default)
**Solver timeout:** 60000ms per assertion

## Summary

| Contract | Functions Tested | Passed | Failed | Timeout | Error |
|----------|-----------------|--------|--------|---------|-------|
| ArithmeticSymbolicTest | 12 | 9 | 0 | 3 | 0 |
| GameFSMSymbolicTest | 8 | 5 | 3* | 0 | 0 |
| NewPropertiesTest | 4 | 1 | 0 | 3 | 0 |
| **Total (v2 check_ run)** | **24** | **15** | **3*** | **6** | **0** |

*\*GameFSM "failures" are expected -- see explanation below.*

### Combined Results (Phase 30 testFuzz_ + Phase 35 check_)

| Contract | Functions | Passed | Failed | Timeout | Error |
|----------|-----------|--------|--------|---------|-------|
| PriceLookupInvariantsTest (Phase 30) | 8 | 8 | 0 | 0 | 0 |
| BurnieCoinInvariantsTest (Phase 30) | 6 | 5 | 0 | 0 | 1 |
| ShareMathInvariantsTest (Phase 30) | 7 | 0 | 0 | 7 | 0 |
| ArithmeticSymbolicTest (Phase 35) | 12 | 9 | 0 | 3 | 0 |
| GameFSMSymbolicTest (Phase 35) | 8 | 5 | 3* | 0 | 0 |
| NewPropertiesTest (Phase 35) | 4 | 1 | 0 | 3 | 0 |
| **Grand Total** | **45** | **28** | **3*** | **13** | **1** |

**Verified properties: 28/45 (62%).** 13 timeouts are unresolved (covered by Foundry fuzzing at 10K runs). 3 GameFSM "failures" are model-level artifacts, not protocol bugs. 1 BurnieCoin error is a Halmos cheatcode limitation.

---

## Per-Function Results

### ArithmeticSymbolicTest (12 properties: 9 PASS, 3 TIMEOUT)

| Function | Result | Paths | Time | Notes |
|----------|--------|-------|------|-------|
| check_price_in_valid_set(uint24) | **PASS** | 12 | 0.01s | All price values in valid set {0.01..0.24} ETH |
| check_price_bounded(uint24) | **PASS** | 12 | 0.01s | Price within [0.01, 0.24] ETH bounds |
| check_price_cyclic(uint24) | **PASS** | 28 | 2.86s | price(n) == price(n+100) for n >= 100 |
| check_price_weakly_monotonic_in_cycle(uint24,uint24,uint24) | **PASS** | 36 | 2.33s | Weak monotonicity within cycle segments |
| check_bps_split_bounded(uint256,uint16) | **PASS** | 7 | 0.02s | BPS split conservation: share + remainder == amount |
| check_bps_two_split(uint256,uint16) | **PASS** | 7 | 0.01s | Two-way BPS split sums to original |
| check_deity_tn_no_overflow(uint256) | **PASS** | 3 | 0.01s | T(n)=n*(n+1)/2 no overflow for n<=1000 |
| check_deity_tn_monotonic(uint256) | **PASS** | 6 | 1.12s | T(n+1) > T(n) for all n in [1, 1000] |
| check_cost_bounded(uint24,uint32) | **PASS** | 37 | 0.23s | Cost bounded by 100 * priceWei |
| check_cost_no_overflow(uint24,uint256) | **TIMEOUT** | 46 | 60.28s | Division by ticketQuantity triggers solver timeout on uint256 |
| check_autorebuy_ethspent_bounded(uint256,uint24) | **TIMEOUT** | 46 | 60.30s | PriceLookup division by 4 + general division chain |
| check_takeprofit_multiple(uint256,uint256) | **TIMEOUT** | 8 | 60.15s | 256-bit division (weiAmount / takeProfit) |

**Analysis:** All 4 PriceLookup properties verified across full uint24 input space. BPS arithmetic verified. Deity pass T(n) formula verified. 3 timeouts involve 256-bit division operations -- same root cause as Phase 30 ShareMath timeouts (bvudiv_256 intractable for yices-smt2).

**Total time:** 187.35s

### GameFSMSymbolicTest (8 properties: 5 PASS, 3 "FAIL"*)

| Function | Result | Paths | Time | Notes |
|----------|--------|-------|------|-------|
| check_gameOver_terminal(bool,bool) | **FAIL*** | 5 | 0.11s | Counterexample: before=true, after=false |
| check_level_monotonic(uint24,uint24) | **FAIL*** | 4 | 0.11s | Counterexample: before=0x800000, after=0x00 |
| check_dailyIdx_monotonic(uint48,uint48) | **FAIL*** | 4 | 0.11s | Counterexample: before=0x800000000000, after=0x00 |
| check_sentinel_claim(uint256) | **PASS** | 4 | 0.11s | Sentinel=1 after claim, payout=amount-1 |
| check_claim_pool_accounting(uint256,uint256) | **PASS** | 7 | 0.02s | Pool decremented by exactly payout |
| check_credit_pool_balance(uint256,uint256,uint256) | **PASS** | 7 | 0.02s | Individual increment == pool increment |
| check_decimator_prereserve(uint256,uint256,uint256,uint256) | **PASS** | 9 | 0.03s | Pre-reserve then deduct = ethPortion only |
| check_autorebuy_split(uint256,uint256,uint256) | **PASS** | 8 | 0.03s | reserved + ethSpent + dust == weiAmount |

**\*FAIL Explanation:** The 3 "failed" properties (gameOver_terminal, level_monotonic, dailyIdx_monotonic) are **model-level properties that operate on arbitrary symbolic inputs**, not actual contract state transitions. They assert constraints like "if before=true then after=true" on unconstrained symbolic booleans/uints. Halmos correctly finds counterexamples because arbitrary inputs CAN violate these constraints. These properties would need to be connected to actual state transition functions (which exceeds Halmos solver capacity due to DegenerusGame's 10-module delegatecall architecture) to be meaningful.

**Verdict:** These are NOT protocol bugs. The 3 failed properties are architectural model tests, not functional tests. The actual contract code enforces these invariants through:
- `gameOver`: Only set to `true` in 2 code paths, never reset to `false` (verified by manual audit in Phase 33)
- `level`: Only incremented by `_endPhase()`, never decremented (verified by manual audit in Phase 33)
- `dailyIdx`: Derived from block.timestamp which only increases (verified in Phase 33 temporal analysis)

These invariants are additionally verified by Foundry invariant tests (GameFSM.inv.t.sol) at 1K+ runs.

**Total time:** 0.55s

### NewPropertiesTest (4 properties: 1 PASS, 3 TIMEOUT)

| Function | Result | Paths | Time | Notes |
|----------|--------|-------|------|-------|
| check_bps_split_exact(uint256,uint16) | **TIMEOUT** | 9 | 60.12s | ceil-div assertion triggers 256-bit division |
| check_lootbox_four_split(uint256,uint16,uint16,uint16) | **TIMEOUT** | 22 | 60.17s | Multiple BPS divisions on uint256 inputs |
| check_affiliate_reward_bounded(uint256,uint16) | **TIMEOUT** | 10 | 60.15s | ceil-div bound assertion triggers timeout |
| check_ticket_cost_nonzero(uint24,uint32) | **PASS** | 48 | 0.30s | Verified: cost > 0 for qty >= 400 at all price tiers |

**Analysis:** The ticket cost non-zero property was verified across the full input space (uint24 level x uint32 quantity). The 3 timeouts involve `(amount * bps + 9999) / 10000` ceil-div assertions on uint256 inputs -- the `+ 9999` creates complex bitvector arithmetic that exceeds yices-smt2 capacity. The simpler BPS properties in ArithmeticSymbolicTest (check_bps_split_bounded, check_bps_two_split) passed because they avoid ceil-div assertions.

**Note:** The ArithmeticSymbolicTest's `check_bps_split_bounded` and `check_bps_two_split` already verify the core BPS conservation property (`share + remainder == amount`) that NewPropertiesTest aimed to extend. The new properties added ceil-div bound assertions which triggered timeouts. The conservation property itself IS verified symbolically.

**Total time:** 180.75s

---

## Timeout Analysis

### Root Causes

All 13 timeouts (7 ShareMath Phase 30 + 3 Arithmetic + 3 NewProperties) share the same root cause: **256-bit bitvector division (`bvudiv_256`) is intractable for the yices-smt2 SMT solver within 60-second timeouts.**

Specific patterns that trigger timeouts:
1. `(a * b) / c` where `a`, `b`, `c` are symbolic uint256 values (ShareMath)
2. `a / b` where both are symbolic uint256 values (takeprofit_multiple, cost_no_overflow)
3. `(a * b + c) / d` ceil-div patterns on uint256 (bps_split_exact, affiliate_reward_bounded)
4. Multiple chained BPS divisions on uint256 inputs (lootbox_four_split)

### Timeout vs. Verified Coverage

| Property Area | Halmos Status | Alternative Coverage | Confidence |
|--------------|---------------|---------------------|------------|
| PriceLookup pricing | 12/12 PASS | N/A (fully verified) | FULL |
| BPS split conservation | 2/5 PASS | Foundry 10K fuzz DustAccumulation.t.sol | HIGH |
| Deity pass T(n) | 2/2 PASS | N/A (fully verified) | FULL |
| Cost calculation | 1/2 PASS | Foundry 10K fuzz PrecisionBoundary.t.sol | HIGH |
| Auto-rebuy | 0/1 PASS | Foundry 10K fuzz PrecisionBoundary.t.sol | HIGH |
| Take-profit | 0/1 PASS | Foundry 10K fuzz PrecisionBoundary.t.sol | HIGH |
| ShareMath | 0/7 PASS | Foundry 10K fuzz ShareMathInvariants.t.sol | MEDIUM-HIGH |
| Game FSM | 5/8 PASS* | Foundry invariant GameFSM.inv.t.sol 1K runs | HIGH |
| Ticket cost nonzero | 1/1 PASS | N/A (fully verified) | FULL |
| Lootbox split | 0/1 TIMEOUT | Foundry 10K fuzz DustAccumulation.t.sol | HIGH |
| Affiliate reward | 0/1 TIMEOUT | Foundry 10K fuzz DustAccumulation.t.sol | HIGH |

**IMPORTANT:** TIMEOUT does not mean "verified" or "no counterexample found." It means the solver could not explore the full state space within the time limit. These properties are unresolved symbolically and rely on Foundry fuzzing for coverage.

---

## Configuration Notes

### Changes from Phase 30

1. **Function prefix:** `--function check` (vs Phase 30's `--function testFuzz`)
2. **Test directory:** `test = "test"` (vs `test = "test/fuzz"`) to include test/halmos/ directory
3. **Solver timeout:** 60000ms (same as Phase 30)
4. **New:** Added NewPropertiesTest with 4 v5.0-targeted properties

### Procedure Used

```bash
cp foundry.toml foundry.toml.bak
node scripts/lib/patchForFoundry.js
# Write clean foundry.toml: [profile.default] only, test = "test", no [fuzz]/[invariant]
forge build --force
halmos --function check --contract ArithmeticSymbolicTest --forge-build-out forge-out --solver-timeout-assertion 60000
halmos --function check --contract GameFSMSymbolicTest --forge-build-out forge-out --solver-timeout-assertion 60000
halmos --function check --contract NewPropertiesTest --forge-build-out forge-out --solver-timeout-assertion 60000
mv foundry.toml.bak foundry.toml
node -e "import('./scripts/lib/patchForFoundry.js').then(m => m.restoreContractAddresses())"
```

---
*Results captured: 2026-03-05*
*Halmos 0.3.3, yices-smt2 solver, 60s timeout per assertion*
