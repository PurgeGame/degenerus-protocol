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
