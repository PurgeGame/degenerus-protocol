# Phase 50 Plan 02: ETH Conservation & Insurance Skim Analysis

**Phase:** 50 (Skim Redesign Audit)
**Plan:** 02
**Date:** 2026-03-21
**Contract:** `contracts/modules/DegenerusGameAdvanceModule.sol`
**Function:** `_applyTimeBasedFutureTake` (lines 985-1055)

---

## SKIM-06: ETH Conservation Proof

### Definitions

Let the three pool variables at function entry be:

- `N = nextPoolBefore` (line 996: `_getNextPrizePool()`)
- `F = futurePoolBefore` (line 997: `_getFuturePrizePool()`)
- `Y = yieldAccumulator` (storage variable, line 1542 of DegenerusGameStorage.sol)

Let the two computed values be:

- `T = take` (computed through steps 0-5, final value after cap at line 1049)
- `I = insuranceSkim = (N * 100) / 10_000` (line 1051, constant `INSURANCE_SKIM_BPS = 100`)

### The Three State Updates (lines 1052-1054)

```solidity
_setNextPrizePool(nextPoolBefore - take - insuranceSkim);   // line 1052: nextPool' = N - T - I
_setFuturePrizePool(futurePoolBefore + take);                // line 1053: futurePool' = F + T
yieldAccumulator += insuranceSkim;                           // line 1054: yield' = Y + I
```

### Algebraic Proof

```
sum_before = N + F + Y

sum_after  = nextPool' + futurePool' + yield'
           = (N - T - I) + (F + T) + (Y + I)
           = N - T - I + F + T + Y + I
           = N + F + Y    (T and I cancel exactly)

sum_after  = sum_before    QED
```

The T and I terms cancel completely. This holds for ANY values of T and I, regardless of how they were computed in steps 0-5 of the pipeline. The conservation property is a consequence of the update structure alone, independent of the skim algorithm.

### Precondition: Can N - T - I Underflow?

For the first state update `N - T - I` to be safe, we need `T + I <= N`.

**Bound on T:**
- T is capped at `maxTake = (N * NEXT_TO_FUTURE_BPS_MAX) / 10_000 = (N * 8000) / 10_000 = 0.8N` (line 1048-1049)
- After cap: `T <= 0.8N`

**Bound on I:**
- `I = (N * 100) / 10_000 = 0.01N` (line 1051)
- Integer truncation: `I <= 0.01N` (floor division can only reduce)

**Combined:**
```
T + I <= 0.8N + 0.01N = 0.81N <= N    (for any N >= 0)
```

Therefore `N - T - I >= N - 0.81N = 0.19N >= 0`. No underflow is possible.

Note: Solidity 0.8.34 uses checked arithmetic and would revert on underflow, but the condition is unreachable regardless.

### Getter/Setter Verification

The prize pool accessors in `DegenerusGameStorage.sol` (lines 675-771) are pure packing/unpacking operations:

**`_setPrizePools(uint128 next, uint128 future)`** (line 675-677):
```solidity
prizePoolsPacked = uint256(future) << 128 | uint256(next);
```
Pure bit-packing. No arithmetic, no rounding, no side effects.

**`_getPrizePools()`** (lines 679-683):
```solidity
uint256 packed = prizePoolsPacked;
next = uint128(packed);
future = uint128(packed >> 128);
```
Pure bit-unpacking. Inverse of the setter.

**`_setNextPrizePool(uint256 val)`** (lines 756-758): Reads current future, packs with new next via `_setPrizePools(uint128(val), future)`.

**`_setFuturePrizePool(uint256 val)`** (lines 768-770): Reads current next, packs with new future via `_setPrizePools(next, uint128(val))`.

**Truncation analysis:** The cast `uint128(val)` truncates if `val >= 2^128 = 3.4 * 10^38`. Pool values are in wei; even 10,000 ether = 10^22 wei, which is 16 orders of magnitude below the uint128 maximum. Truncation is impossible at any realistic pool size.

**Side effect analysis:** None of the getters/setters perform external calls, emit events, or modify any state beyond `prizePoolsPacked`. They are pure storage slot operations.

### Fuzz Evidence

`testFuzz_conservation` (test/fuzz/FuturepoolSkim.t.sol, line 404-422) runs with random inputs:
- `nextPool` bounded to [1 ether, 10_000 ether]
- `futurePool` bounded to [0, 50_000 ether]
- `lvl` bounded to [1, 200]
- `lastPool` bounded to [0.01 ether, 10_000 ether]
- `elapsed` bounded to [0, 120 days]
- `rngWord` fully random 256-bit

The assertion `_assertConservation(nextPool, futurePool, nextAfter, futureAfter, yieldAfter)` confirms `nextAfter + futureAfter + yieldAfter == nextBefore + futureBefore + yieldBefore`. All iterations pass, providing empirical confirmation of the algebraic proof.

### Division by Zero: Ratio Calculation (line 1001)

The formula `(futurePoolBefore * 100) / nextPoolBefore` divides by `nextPoolBefore`. This would revert if `nextPoolBefore == 0`.

**Calling context analysis (line 314-316):**
```solidity
levelPrizePool[purchaseLevel] = _getNextPrizePool();    // line 315
_applyTimeBasedFutureTake(ts, purchaseLevel, rngWord);   // line 316
```

The function is only called during level advancement, which requires ticket purchases that add ETH to the pool. Furthermore, `levelPrizePool[0] = BOOTSTRAP_PRIZE_POOL = 50 ether` (DegenerusGame.sol line 252, DegenerusGameStorage.sol line 137-138), so even the very first level transition starts with at least 50 ether. After skim, the remaining pool is at least 0.19N (19% of pre-skim value), which for a 50 ether bootstrap is 9.5 ether. A zero pool is unreachable through normal game flow.

**Verdict: SAFE** -- ETH conservation holds by algebraic identity. The T and I terms cancel exactly in the three state updates. No rounding, no truncation, no ETH created or destroyed. The underflow `N - T - I` is impossible because `T + I <= 0.81N`. Getter/setter operations are pure packing with no value transformation. Division by zero at line 1001 is unreachable via calling context constraints.

---

## SKIM-07: Insurance Skim Precision

### Formula (line 1051)

```solidity
uint256 insuranceSkim = (nextPoolBefore * INSURANCE_SKIM_BPS) / 10_000;
// where INSURANCE_SKIM_BPS = 100 (line 106)
```

This simplifies to `insuranceSkim = (nextPoolBefore * 100) / 10_000 = nextPoolBefore / 100` via integer division.

The result is `floor(nextPoolBefore / 100)`.

### Precision Analysis

**For `nextPoolBefore >= 100 wei`:**
- `insuranceSkim = floor(nextPoolBefore / 100)`
- The exact 1% value is `nextPoolBefore / 100` (real division)
- The integer truncation error is at most 1 wei (floor rounds down by at most 99/10000 < 1 wei)
- For any realistic pool (>= 0.01 ether = 10^16 wei), the relative error is at most `1 / 10^16 = 10^-16`, which is negligible

**For `nextPoolBefore < 100 wei`:**
- `insuranceSkim = 0` (integer division truncates to zero)
- The "exactly 1%" property fails: 1% of 99 wei should be ~1 wei, but the formula returns 0
- Maximum absolute loss: 1 wei (the insurance skim that should have been collected)

**For `nextPoolBefore = 0`:**
- `insuranceSkim = 0` (correct -- 1% of 0 is 0)

### Reachability of Sub-100-Wei Pools

The minimum realistic pool is the bootstrap: `BOOTSTRAP_PRIZE_POOL = 50 ether` (DegenerusGameStorage.sol lines 137-138, initialized at DegenerusGame.sol line 252).

**Level transitions add ETH:** Each level advancement requires ticket purchases which add ETH to the next pool. The pool never starts a level with less than the bootstrap value.

**Maximum depletion per skim:** After a maximum skim (80% take + 1% insurance = 81%), a pool retains 19% of its pre-skim value:
- 50 ether * 0.19 = 9.5 ether = 9.5 * 10^18 wei -- vastly above 100 wei

**Repeated maximum skims (theoretical worst case):**
```
After n consecutive maximum skims: pool = 50 ether * 0.19^n

To reach 100 wei:
  50 * 10^18 * 0.19^n = 100
  0.19^n = 100 / (5 * 10^19) = 2 * 10^-18
  n = log(2 * 10^-18) / log(0.19) = ~24.6

  => ~25 consecutive maximum skims at minimum pool
```

Each skim requires a level transition, which requires ticket purchases adding ETH. In practice, pools grow between levels. Reaching 25 consecutive maximum skims at the minimum possible pool size is impossible in normal gameplay.

### Fuzz Evidence

`testFuzz_insuranceAlways1Pct` (test/fuzz/FuturepoolSkim.t.sol, lines 428-449) bounds `nextPool` to [1 ether, 10_000 ether] and asserts:
```solidity
assertEq(yieldAfter, uint256(nextPool) * INSURANCE_SKIM_BPS / 10_000,
         "insurance must be exactly 1% of nextPool");
```

All iterations pass, confirming the formula is correctly implemented within realistic bounds. The fuzz range [1 ether, 10_000 ether] covers the entire realistic pool size space.

### Division by Zero in Insurance Formula

The formula `(nextPoolBefore * 100) / 10_000` uses a constant divisor (10,000). Division by zero is impossible regardless of input values.

Note: The ratio calculation at line 1001 (`(futurePoolBefore * 100) / nextPoolBefore`) DOES divide by `nextPoolBefore` -- this is addressed under SKIM-06 preconditions above (unreachable via calling context).

**Verdict: SAFE** -- Insurance skim is exactly `floor(nextPoolBefore / 100)`. The only precision loss is integer truncation at sub-100-wei pools, which is unreachable in production (minimum bootstrap = 50 ether, minimum post-skim retention = 19%). No rounding edge cases exist at realistic pool sizes (>= 0.01 ether).

---

## Summary Table

| Requirement | Verdict | Severity | Lines | Key Evidence |
|-------------|---------|----------|-------|--------------|
| SKIM-06 | SAFE | -- | 1051-1054 | Algebraic cancellation of T and I; fuzz confirms |
| SKIM-07 | SAFE | -- | 1051 | floor(N/100) exact above 100 wei; sub-100 unreachable |
