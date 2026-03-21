# Pipeline Arithmetic Verdicts -- Futurepool Skim Redesign

**Phase:** 50 (Skim Redesign Audit)
**Plan:** 01 (Pipeline Arithmetic)
**Date:** 2026-03-21
**Contract:** `contracts/modules/DegenerusGameAdvanceModule.sol`
**Function:** `_applyTimeBasedFutureTake` (lines 985-1055)
**Helper:** `_nextToFutureBps` (lines 955-983)
**Constants:** Lines 100-111

---

## SKIM-01: Overshoot Surcharge Monotonicity and Cap

**Lines:** 1012-1019 of DegenerusGameAdvanceModule.sol
**Constants:** `OVERSHOOT_THRESHOLD_BPS = 12500` (L108), `OVERSHOOT_CAP_BPS = 3500` (L109), `OVERSHOOT_COEFF = 4000` (L110)

### Code Under Analysis

```solidity
if (lastPool != 0) {
    uint256 rBps = (nextPoolBefore * 10_000) / lastPool;          // L1013
    if (rBps > OVERSHOOT_THRESHOLD_BPS) {                         // L1014
        uint256 excess = rBps - OVERSHOOT_THRESHOLD_BPS;          // L1015
        uint256 surcharge = (excess * OVERSHOOT_COEFF) / (excess + 10_000); // L1016
        if (surcharge > OVERSHOOT_CAP_BPS) surcharge = OVERSHOOT_CAP_BPS;   // L1017
        bps += surcharge;                                         // L1018
    }
}
```

### Arithmetic Analysis

**Formula:** `f(x) = (x * 4000) / (x + 10000)` where `x = excess = rBps - 12500`

**Monotonicity proof:**
The derivative of `f(x) = 4000x / (x + 10000)` is:
```
f'(x) = [4000 * (x + 10000) - 4000x * 1] / (x + 10000)^2
       = [4000 * 10000] / (x + 10000)^2
       = 40,000,000 / (x + 10000)^2
```
Since `(x + 10000)^2 > 0` for all `x >= 0`, `f'(x) > 0` for all valid inputs. Therefore `f` is **strictly monotonically increasing** over the domain `x >= 0`.

**Asymptotic limit:** As `x -> infinity`, `f(x) -> 4000`. The function approaches but never reaches 4000 bps (40%).

**Cap enforcement:** Line 1017 clamps `surcharge` at `OVERSHOOT_CAP_BPS = 3500` (35%). Since the asymptote is 4000 and the clamp is at 3500, the clamp will activate when:
```
3500 = (x * 4000) / (x + 10000)
3500 * (x + 10000) = 4000x
35,000,000 = 500x
x = 70,000
```
At `excess = 70000` (i.e., `rBps = 82500`, meaning nextPool is 8.25x lastPool), the cap activates. All higher R values produce exactly 3500 bps surcharge.

**Overflow analysis:**
- `nextPoolBefore * 10_000` (L1013): nextPoolBefore is uint256 from `_getNextPrizePool()` (max uint128 = ~3.4e38). `3.4e38 * 10000 = 3.4e42`, well within uint256 (max ~1.16e77). SAFE.
- `excess * OVERSHOOT_COEFF` (L1016): excess is at most `10000 * 10000 = 1e8` (when nextPool = 10000x lastPool, the bps return is capped to 10000 by `_nextToFutureBps`). Actually, rBps can be much larger if nextPoolBefore >> lastPool. In the extreme, rBps could approach `type(uint128).max * 10000 / 1`, but `excess * 4000` would still be within uint256. SAFE.
- `excess + 10_000` (L1016): Cannot be zero since `excess >= 1` (guard at L1014 ensures `rBps > 12500`, so `excess >= 1`). Division by zero impossible. SAFE.

**Spot check against test:**
- Test at L510: `_calcSurcharge(15000) = 800` -- excess=2500, `(2500*4000)/(2500+10000) = 10,000,000/12,500 = 800`. Correct.
- Test at L512: `_calcSurcharge(20000) = 1714` -- excess=7500, `(7500*4000)/(7500+10000) = 30,000,000/17,500 = 1714`. Correct (integer division).
- Test at L513: `_calcSurcharge(30000) = 2545` -- excess=17500, `(17500*4000)/(17500+10000) = 70,000,000/27,500 = 2545`. Correct.
- Test at L514: `_calcSurcharge(100000) = OVERSHOOT_CAP_BPS` -- excess=87500, unclamped = `(87500*4000)/(87500+10000) = 350,000,000/97,500 = 3589`, capped to 3500. Correct.
- Test at L515: `_calcSurcharge(12500) = 0` -- excess=0, guard fails (rBps not > 12500). Returns 0. Correct.

**Cross-reference:** `test_overshootSurcharge_spotValues` at FuturepoolSkim.t.sol:510

**Verdict: SAFE** -- Monotonically increasing by calculus (f'(x) > 0 for all x >= 0). Hard-capped at 3500 bps by explicit clamp at line 1017. No overflow or division-by-zero risk. All spot-check values match.

---

## SKIM-02: Ratio Adjustment Bounded +/-400 bps

**Lines:** 1000-1008 of DegenerusGameAdvanceModule.sol

### Code Under Analysis

```solidity
// Ratio adjust: +/-4% based on future/next ratio (target 2:1)
uint256 ratioPct = (futurePoolBefore * 100) / nextPoolBefore;  // L1001
if (ratioPct < 200) {                                          // L1002
    uint256 bump = 200 - ratioPct;                             // L1003
    bps += (bump > 400 ? 400 : bump);                          // L1004
} else {                                                       // L1005
    uint256 penalty = ratioPct - 200;                          // L1006
    penalty = penalty > 400 ? 400 : penalty;                   // L1007
    bps = penalty >= bps ? 0 : bps - penalty;                  // L1008
}
```

### Arithmetic Analysis

**Bump path (ratioPct < 200):**
- `bump = 200 - ratioPct`: since `ratioPct < 200`, this is in `[1, 200]`. No underflow.
- `bump > 400 ? 400 : bump`: bump is at most 200 (when ratioPct = 0), so the cap at 400 never activates in this branch. But the cap is a safety net for clarity.
- Maximum bps increase: **+200 bps** (when futurePool = 0). The 400 cap is unreachable from this branch alone.
- Wait -- if `ratioPct = 0`, then `bump = 200`. If futurePool can be 0, bump is 200, not 400. Actually, for bump to reach 400 we'd need `ratioPct` to be negative, which is impossible for unsigned integers. So the **effective** bump range is [1, 200], and the cap at 400 is a defensive guard. Net bps change: **+[1, 200]**.

**Penalty path (ratioPct >= 200):**
- `penalty = ratioPct - 200`: since `ratioPct >= 200`, this is non-negative. No underflow.
- `penalty > 400 ? 400 : penalty`: caps penalty at 400. Maximum penalty = **400 bps**.
- `bps = penalty >= bps ? 0 : bps - penalty`: This is the critical underflow prevention. If penalty would cause bps to go negative, bps is floored at **0** instead. Since Solidity 0.8.34 has built-in overflow protection, the explicit ternary also prevents a panic revert on underflow.

**Bound proof:**
- Positive direction: bps increases by at most 200 (not 400 -- the 400 cap is unreachable). Even so, the plan requirement says "+/-400 bps" -- the constant CAP is 400, which is what the requirement refers to.
- Negative direction: bps decreases by at most `min(penalty, bps)`, clamped to 400. bps floors at 0. Underflow impossible.

**Division by zero (L1001):**
`(futurePoolBefore * 100) / nextPoolBefore` -- divides by `nextPoolBefore`. If `nextPoolBefore = 0`, this reverts (Solidity 0.8 div-by-zero panic).

**Calling context analysis:** Line 314-315 shows `levelPrizePool[purchaseLevel] = _getNextPrizePool()` is called immediately before `_applyTimeBasedFutureTake`. The function is only called during level transitions, which require player purchases that add ETH to the next pool. For `nextPoolBefore = 0`, the level could not have been reached (prize pool bootstraps at 50 ether and receives ETH from every ticket purchase). Zero pool is unreachable in production. The fuzz suite bounds `nextPool >= 1 ether` (FuturepoolSkim.t.sol:270).

**Cross-reference:** `test_ratioAdjust_cappedAt400` at FuturepoolSkim.t.sol:490

**Verdict: SAFE** -- Bounded at +/-400 bps (cap constant). Underflow prevented by `penalty >= bps ? 0 : bps - penalty` ternary floor at 0. Division by zero unreachable: level transitions require nonzero prize pool (bootstrap at 50 ether, purchases add ETH).

---

## SKIM-03: Bit-Field Consumption -- INFO Finding

**Lines:** 1023 (additive random), 1036-1037 (variance rolls) of DegenerusGameAdvanceModule.sol
**Constant:** `ADDITIVE_RANDOM_BPS = 1000` (L111)

### Code Under Analysis

```solidity
// Step 2: Additive random 0-10% on bps
bps += rngWord % (ADDITIVE_RANDOM_BPS + 1);                   // L1023
// ...
uint256 roll1 = (rngWord >> 64) % range;                      // L1036
uint256 roll2 = (rngWord >> 192) % range;                     // L1037
```

### Bit-Field Analysis

**Additive step (L1023):** `rngWord % 1001`
- The modulo operation on a uint256 is a function of **all 256 bits** of `rngWord`, not just bits [0:63].
- For the output to depend only on bits [0:63], the code would need: `(rngWord & 0xFFFFFFFFFFFFFFFF) % 1001` (mask to isolate low 64 bits).
- The current implementation produces values in [0, 1000] which is correct and safe -- but the value is influenced by the entire 256-bit word.

**Variance roll1 (L1036):** `(rngWord >> 64) % range`
- Right-shifting by 64 moves bits [64:255] into positions [0:191]. The result is a 192-bit value occupying the low 192 bits.
- Original bits consumed: **[64:255]** (192 bits).

**Variance roll2 (L1037):** `(rngWord >> 192) % range`
- Right-shifting by 192 moves bits [192:255] into positions [0:63]. The result is a 64-bit value occupying the low 64 bits.
- Original bits consumed: **[192:255]** (64 bits).

**Overlap identification:**
- roll1 consumes bits [64:255]
- roll2 consumes bits [192:255]
- **Bits [192:255] appear in BOTH roll1 and roll2**

```
Bit layout (original rngWord):
[0                63][64              191][192             255]
|--- additive (*)---|--- roll1 only -----|--- SHARED ------|
                    |--------- roll1 total ------------------|
                                         |---- roll2 total --|

(*) additive uses ALL 256 bits via modulo, not just [0:63]
```

### Functional Independence Assessment

Despite the bit overlap, the outputs are **functionally independent** for practical purposes:

1. **Additive vs. variance:** `rngWord % 1001` and `(rngWord >> 64) % range` compute different functions. Knowing the additive output does not reveal the variance output (modulo destroys the relationship for any non-trivial range).

2. **roll1 vs. roll2:** Both share bits [192:255] in their shifted inputs, but `% range` for any `range` value typical of the pipeline (range = halfWidth*2+1, where halfWidth is in the range of pool fractions) makes them effectively independent. The shared 64 bits contribute different amounts to each roll's modulo result.

3. **True bit isolation would require masking:**
   - Additive: `(rngWord & ((1 << 64) - 1)) % 1001`
   - roll1: `((rngWord >> 64) & ((1 << 128) - 1)) % range`
   - roll2: `(rngWord >> 192) % range`
   This would give three fully independent bit windows: [0:63], [64:191], [192:255].

### Impact Assessment

- **Security:** No vulnerability. The modulo operation produces well-distributed values regardless of which bits contribute. An attacker cannot exploit the bit overlap because they do not control the VRF word.
- **Distribution quality:** The triangular distribution test (`test_H_varianceTriangular`, FuturepoolSkim.t.sol:291) passes, confirming the distribution shape is correct despite the overlap.
- **Discrepancy:** The code does not match the stated bit-window design of [0:63], [64:191], [192:255] as described in commit b06d80a8 and the design documentation.

**Cross-reference:** `test_vrf_bitWindows_independent` at FuturepoolSkim.t.sol:565 -- tests functional independence (different low bits produce different additive results), but does not test literal bit isolation.

**Verdict: INFO** -- Not a security vulnerability. Outputs are functionally independent via modulo arithmetic. However, the implementation does not match the stated bit-window design: (1) the additive step consumes all 256 bits via `rngWord % 1001`, not just [0:63]; (2) roll1 and roll2 share bits [192:255] due to overlapping shift windows.

**Severity:** INFO
**Recommendation:** Either update NatSpec/comments to describe "functionally independent via modulo" rather than literal bit isolation, OR add bit masking (`rngWord & mask`) to achieve true window isolation per the documented design.

---

## SKIM-04: Triangular Variance Cannot Underflow Take

**Lines:** 1029-1044 of DegenerusGameAdvanceModule.sol
**Constants:** `NEXT_SKIM_VARIANCE_BPS = 2500` (L104), `NEXT_SKIM_VARIANCE_MIN_BPS = 1000` (L105)

### Code Under Analysis

```solidity
// Step 4: +/-25% multiplicative variance (triangular: avg of two uniform VRF rolls)
if (take != 0) {                                                  // L1029
    uint256 halfWidth = (take * NEXT_SKIM_VARIANCE_BPS) / 10_000; // L1030
    uint256 minWidth = (nextPoolBefore * NEXT_SKIM_VARIANCE_MIN_BPS) / 10_000; // L1031
    if (halfWidth < minWidth) halfWidth = minWidth;               // L1032
    if (halfWidth > take) halfWidth = take;                       // L1033

    uint256 range = halfWidth * 2 + 1;                            // L1035
    uint256 roll1 = (rngWord >> 64) % range;                      // L1036
    uint256 roll2 = (rngWord >> 192) % range;                     // L1037
    uint256 combined = (roll1 + roll2) / 2;                       // L1038

    if (combined >= halfWidth) {                                  // L1040
        take += combined - halfWidth;                             // L1041
    } else {                                                      // L1042
        take -= halfWidth - combined;                             // L1043
    }
}
```

### Bounds Chain Proof

**Step 1: halfWidth initial computation (L1030)**
- `halfWidth = (take * 2500) / 10000 = take / 4` (integer division)
- Since `take > 0` (guard at L1029), `halfWidth >= 0`
- For `take >= 4`, `halfWidth >= 1`

**Step 2: minWidth floor (L1031-1032)**
- `minWidth = (nextPoolBefore * 1000) / 10000 = nextPoolBefore / 10`
- If `halfWidth < minWidth`, halfWidth is raised to minWidth
- This can push halfWidth ABOVE `take / 4` -- potentially above take itself if nextPoolBefore is much larger than take

**Step 3: The critical clamp (L1033)**
- `if (halfWidth > take) halfWidth = take`
- **This guarantees: `halfWidth <= take`** regardless of how large minWidth pushed it
- This is the invariant that makes the subtraction path safe

**Step 4: Range computation (L1035)**
- `range = halfWidth * 2 + 1`
- Since `halfWidth <= take` and `take <= nextPoolBefore * 8000 / 10000` (from eventual cap), range is bounded
- `range >= 1` (since `halfWidth >= 0`, range >= 1). Division by zero in modulo impossible
- Overflow: `halfWidth * 2 + 1`. With `halfWidth <= take <= nextPoolBefore` and nextPoolBefore being uint128, `2 * type(uint128).max + 1` fits in uint256. SAFE

**Step 5: Roll bounds (L1036-1037)**
- `roll1 = (rngWord >> 64) % range` => `roll1 in [0, range-1] = [0, halfWidth * 2]`
- `roll2 = (rngWord >> 192) % range` => `roll2 in [0, range-1] = [0, halfWidth * 2]`

**Step 6: Combined computation (L1038)**
- `combined = (roll1 + roll2) / 2`
- Maximum: `(halfWidth*2 + halfWidth*2) / 2 = halfWidth * 2` (integer division of `4 * halfWidth / 2`)
- Minimum: `(0 + 0) / 2 = 0`
- Therefore: `combined in [0, halfWidth * 2]`

**Step 7: Subtraction path safety (L1042-1043)**
- Condition: `combined < halfWidth`
- Subtraction amount: `halfWidth - combined`
- Since `combined >= 0` and `combined < halfWidth`: `halfWidth - combined in [1, halfWidth]`
- Since `halfWidth <= take` (from Step 3): `halfWidth - combined <= halfWidth <= take`
- Therefore: `take -= (halfWidth - combined)` **cannot underflow**
- Resulting take: `take - (halfWidth - combined) >= take - halfWidth >= 0`

**Step 8: Addition path safety (L1040-1041)**
- Condition: `combined >= halfWidth`
- Addition amount: `combined - halfWidth`
- Since `combined <= halfWidth * 2`: `combined - halfWidth <= halfWidth`
- `take += combined - halfWidth` adds at most `halfWidth` to take
- Overflow: take is at most ~`nextPoolBefore * bps / 10000` + halfWidth. For uint256, this is negligible. SAFE

**Formal bound summary:**
```
Invariant: halfWidth <= take  (enforced by L1033)
Subtraction path: take -= (halfWidth - combined)
  where 0 <= halfWidth - combined <= halfWidth <= take
  => take_after >= take - halfWidth >= 0   QED (no underflow)
Addition path: take += (combined - halfWidth)
  where 0 <= combined - halfWidth <= halfWidth
  => take_after <= take + halfWidth         (no overflow concern for uint256)
```

**Cross-reference:**
- `testFuzz_G2_takeCapped` at FuturepoolSkim.t.sol:262 -- runs 1000 fuzz iterations across random `nextPool`, `futurePool`, `lvl`, `lastPool`, `elapsed`, `rngWord`. Never reverts, confirming no underflow panic across the entire pipeline including the variance step.
- `testFuzz_conservation` at FuturepoolSkim.t.sol:404 -- proves `nextPool + futurePool + yield` is conserved, implying no arithmetic errors create or destroy value in the variance step.

**Verdict: SAFE** -- The `if (halfWidth > take) halfWidth = take` clamp at line 1033 guarantees the subtraction path cannot underflow. Formal bound: subtraction amount = `halfWidth - combined <= halfWidth <= take`, therefore `take -= (halfWidth - combined) >= 0`. Confirmed by 1000-iteration fuzz test with no reverts.

---

## SKIM-05: Take Cap at 80% of nextPool

**Lines:** 1047-1049 of DegenerusGameAdvanceModule.sol
**Constant:** `NEXT_TO_FUTURE_BPS_MAX = 8000` (L111)

### Code Under Analysis

```solidity
// Step 5: Cap take at 80% of nextPool
uint256 maxTake = (nextPoolBefore * NEXT_TO_FUTURE_BPS_MAX) / 10_000; // L1048
if (take > maxTake) take = maxTake;                                    // L1049
```

### Arithmetic Analysis

**Cap computation (L1048):**
- `maxTake = (nextPoolBefore * 8000) / 10000 = 80% of nextPoolBefore`
- Integer division truncates, so `maxTake <= 80% of nextPoolBefore`. Rounding is conservative (caps slightly lower).
- Overflow: `nextPoolBefore * 8000`. nextPoolBefore is uint256 from `_getNextPrizePool()` (effective max uint128). `type(uint128).max * 8000 = ~2.7e42`, well within uint256. SAFE.

**Cap enforcement (L1049):**
- If `take > maxTake`, take is clamped to maxTake. Hard clamp, no exceptions.
- This cap is applied **AFTER** all variance operations (Steps 1-4), so no subsequent arithmetic can increase take above 80%.

**Post-cap operations (L1051-1054):**
```solidity
uint256 insuranceSkim = (nextPoolBefore * INSURANCE_SKIM_BPS) / 10_000; // L1051
_setNextPrizePool(nextPoolBefore - take - insuranceSkim);               // L1052
_setFuturePrizePool(futurePoolBefore + take);                           // L1053
yieldAccumulator += insuranceSkim;                                      // L1054
```

- Insurance skim: `nextPoolBefore * 100 / 10000 = 1% of nextPoolBefore`
- Total deduction from nextPool: `take + insuranceSkim <= 80% + 1% = 81% of nextPoolBefore`
- Remaining in nextPool: `nextPoolBefore - take - insuranceSkim >= 19% of nextPoolBefore`
- Underflow safety (L1052): `take <= 80%` and `insuranceSkim = 1%`, so `take + insuranceSkim <= 81%` of nextPoolBefore. Since `81% < 100%`, the subtraction `nextPoolBefore - take - insuranceSkim` cannot underflow. SAFE.

**Cross-reference:** `testFuzz_G2_takeCapped` at FuturepoolSkim.t.sol:262 -- asserts `take <= nextPoolBefore * 8000 / 10000` across 1000 fuzz runs with random inputs. Also asserts `nextAfter + yieldAfter <= nextPool` (next pool can only decrease). Both assertions pass.

**Verdict: SAFE** -- Hard cap at 80% of nextPool applied at line 1049 after all variance operations. No subsequent step modifies take. Combined with 1% insurance skim, nextPool retains at least 19%. No overflow or underflow risk. Confirmed by 1000-iteration fuzz test.

---

## Summary Table

| Requirement | Verdict | Severity | Lines | Key Mechanism |
|-------------|---------|----------|-------|---------------|
| SKIM-01 | SAFE | -- | 1012-1019 | f'(x) = 40M/(x+10000)^2 > 0; clamp at 3500 bps |
| SKIM-02 | SAFE | -- | 1000-1008 | Bump/penalty capped at 400; `penalty >= bps ? 0 : bps - penalty` floors at 0 |
| SKIM-03 | INFO | INFO | 1023, 1036-1037 | Modulo consumes all 256 bits; roll1/roll2 share [192:255]; functionally independent |
| SKIM-04 | SAFE | -- | 1029-1044 | `halfWidth > take` clamp ensures subtraction <= halfWidth <= take |
| SKIM-05 | SAFE | -- | 1047-1049 | `maxTake = nextPool * 8000 / 10000`; hard clamp post-variance |

**Overall:** 4 SAFE, 1 INFO. No HIGH, MEDIUM, or LOW findings. The pipeline arithmetic is correct with one informational discrepancy in bit-field documentation vs. implementation.
