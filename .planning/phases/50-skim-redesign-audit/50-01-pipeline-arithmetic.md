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
