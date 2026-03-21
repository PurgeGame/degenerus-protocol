# Economic Behavior Verdicts -- Futurepool Skim Redesign

**Phase:** 50 (Skim Redesign Audit)
**Plan:** 03 (Economic Analysis)
**Date:** 2026-03-21
**Contract:** `contracts/modules/DegenerusGameAdvanceModule.sol`
**Function:** `_applyTimeBasedFutureTake` (lines 985-1055)
**Helper:** `_nextToFutureBps` (lines 955-983)
**Constants:** Lines 100-111

---

## ECON-01: Overshoot Surcharge Accelerates Futurepool Growth During Fast Levels

**Lines:** 1012-1019 of DegenerusGameAdvanceModule.sol
**Constants:** `OVERSHOOT_THRESHOLD_BPS = 12500` (L107), `OVERSHOOT_CAP_BPS = 3500` (L108), `OVERSHOOT_COEFF = 4000` (L109)

### Economic Mechanism Trace

1. When a level fills fast, nextPool grows large relative to lastPool. The ratio `rBps = (nextPoolBefore * 10000) / lastPool` exceeds 12500 (1.25x threshold).
2. The surcharge `(excess * 4000) / (excess + 10000)` adds bps on top of the base U-curve bps.
3. More bps means larger `take = (nextPoolBefore * bps) / 10000`.
4. Larger take moves more ETH from nextPool to futurePool, accelerating future prize growth.

This is the intended economic design: fast-filling levels indicate strong player activity, and the overshoot surcharge ensures the prize pool ramp accelerates in response, keeping future prizes attractive.

### Numeric Walkthrough -- R=3.0 Scenario (nextPool = 3x lastPool)

```
rBps = (300 ether * 10000) / 100 ether = 30000
excess = 30000 - 12500 = 17500
surcharge = (17500 * 4000) / (17500 + 10000) = 70,000,000 / 27,500 = 2545 bps
If base bps = 3000 (fast fill, no stall bonus), total bps = 3000 + 2545 = 5545
take = nextPool * 5545 / 10000 = 55.45% of nextPool
```

This is substantially higher than the 30% base skim, demonstrating meaningful acceleration. The additional 25.45% of nextPool flows to futurePool, building a larger prize for the next level.

### Numeric Walkthrough -- R=1.5 Scenario (Modest Overshoot)

```
rBps = (150 ether * 10000) / 100 ether = 15000
excess = 15000 - 12500 = 2500
surcharge = (2500 * 4000) / (2500 + 10000) = 10,000,000 / 12,500 = 800 bps
If base bps = 3000, total bps = 3000 + 800 = 3800
take = nextPool * 3800 / 10000 = 38% of nextPool
```

Moderate acceleration -- 8 percentage points above base. The hyperbolic shape provides a gentle ramp-up near the threshold, avoiding discontinuities.

### Numeric Walkthrough -- R=1.24 (Just Below Threshold)

```
rBps = (124 ether * 10000) / 100 ether = 12400
12400 < 12500 → OVERSHOOT_THRESHOLD_BPS guard fails
Overshoot block does not execute
take stays at base bps only -- no acceleration
```

The threshold cleanly separates normal growth from overshoot. No discontinuity at the boundary (surcharge at R=1.25 would be `(0 * 4000) / (0 + 10000) = 0` if excess were 0, but the `>` guard means excess starts at 1 when rBps=12501).

### Cross-References

- **SKIM-01 verdict** (50-01-pipeline-arithmetic.md): Proves monotonicity via calculus -- `f'(x) = 40,000,000 / (x + 10000)^2 > 0` for all x >= 0. Larger R always produces larger surcharge. Hard-capped at 3500 bps by explicit clamp at line 1017.
- **`test_B_fastOvershoot_R3`** (FuturepoolSkim.t.sol line 135): Confirms R=3.0 (nextPool=300 ether, lastPool=100 ether) produces higher take than baseline. Assertion: `take > nextPool * 3000 / 10000` passes, proving overshoot adds on top of base skim.
- **`test_C_extremeOvershoot_R10`** (FuturepoolSkim.t.sol line 155): Confirms R=10.0 respects the 80% hard cap even with maximum surcharge, proving the pipeline bounds are maintained under extreme conditions.

### Verdict: SAFE

Overshoot surcharge correctly adds bps proportional to growth rate. Monotonicity (from SKIM-01) ensures faster levels always get higher surcharge -- there is no perverse incentive where growth rate increases but surcharge decreases. The hyperbolic shape `f(x) = 4000x / (x + 10000)` provides gentle ramp-up near the 1.25x threshold and an asymptotic cap approaching 4000 bps, with a hard clamp at 3500 bps (line 1017) for absolute safety. Economic impact: overshoot moves more ETH from nextPool to futurePool, which is the correct direction for sustaining prize growth during fast activity periods.

---

## ECON-02: Stall Escalation Functions Without Growth Adjustment

**Lines:** 976-980 of DegenerusGameAdvanceModule.sol
**Constants:** `NEXT_TO_FUTURE_BPS_FAST = 3000` (L100), `NEXT_TO_FUTURE_BPS_WEEK_STEP = 100` (L102)

### Code Under Analysis

The stall escalation path in `_nextToFutureBps` (lines 975-981):

```solidity
} else {
    // elapsed > 28 days
    bps =
        NEXT_TO_FUTURE_BPS_FAST +
        lvlBonus +
        ((elapsed - 28 days) / 1 weeks) *
        NEXT_TO_FUTURE_BPS_WEEK_STEP;
}
```

This formula decomposes to:
- `bps = 3000 + lvlBonus + weeksStalled * 100`
- Where `lvlBonus = (lvl % 100 / 10) * 100` ranges from 0 to 900 (line 959)
- And `weeksStalled = (elapsed - 28 days) / 1 weeks`

### Independence from Removed Growth Adjustment

**Key observation:** This formula has NO reference to any growth adjustment variable. The old growth adjustment was removed in commit b06d80a8 and replaced with the overshoot surcharge. The stall path is purely a function of `elapsed` and `lvl` -- both of which are unchanged by the redesign.

The stall escalation path is a completely self-contained formula:
1. It does not read `lastPool` or `nextPool` -- no growth ratio dependency
2. It does not reference any state variable added or modified by the skim redesign
3. It is a pure function of time elapsed and level number
4. The `NEXT_TO_FUTURE_BPS_FAST` and `NEXT_TO_FUTURE_BPS_WEEK_STEP` constants were not changed in the redesign

### Regression Check

Stall escalation behavior across time boundaries:

| Elapsed | Path | bps (lvlBonus=0) | bps (lvlBonus=500) |
|---------|------|-------------------|---------------------|
| 1 day | Fast (L961-962) | 3000 | 3500 |
| 7 days | Decay (L963-968) | ~2077 | ~2577 |
| 14 days | Minimum (L969-974) | 1300 | 1300 |
| 21 days | Recovery (L969-974) | ~2150 | ~2650 |
| 28 days | Stall start (L975-980) | 3000 | 3500 |
| 35 days | +1 week stall | 3100 | 3600 |
| 42 days | +2 weeks stall | 3200 | 3700 |
| 60 days | +4.57 weeks stall | 3400 | 3900 |

- The stall path starts at elapsed > 28 days, producing bps = 3000 + lvlBonus (same as fast fill)
- Each additional week adds 100 bps (1% more skim per week of stall)
- At 60 days stall: weeksStalled = (60 days - 28 days) / 1 weeks = 32 days / 7 days = 4 (integer division), bps = 3000 + lvlBonus + 400
- Return value capped at 10000 by line 982: `return uint16(bps > 10_000 ? 10_000 : bps)`
- Time to saturation (bps=10000) with lvlBonus=0: (10000 - 3000) / 100 = 70 weeks beyond 28 days = approximately 98 weeks total

### Economic Rationale

The escalation pressure is correct: as a level stalls, the skim percentage increases, moving a larger fraction of the stagnant nextPool into futurePool. This economically incentivizes advancement by making the current level's prize less attractive (more is being skimmed away) while making future prizes more attractive (futurePool grows faster). The 100 bps/week rate is gradual enough to avoid sudden prize pool depletion but firm enough to prevent indefinite stagnation.

### Cross-References

- **`test_D_stall_60day`** (FuturepoolSkim.t.sol line 180): Confirms stall at 60 days (nextPool=100 ether, lastPool=100 ether, R=1.0) produces non-zero take with escalated bps. The test was written for the redesigned code and passes.
- **Commit b06d80a8:** Removed the old growth adjustment variable. The stall path was preserved unchanged in this commit.

### Verdict: SAFE

Stall escalation is completely independent of the removed growth adjustment. The formula `NEXT_TO_FUTURE_BPS_FAST + lvlBonus + weeksStalled * NEXT_TO_FUTURE_BPS_WEEK_STEP` is self-contained and produces monotonically increasing bps with stall duration, correctly pressuring stalled pools. No reference to any variable introduced, modified, or removed by the skim redesign. The 100 bps/week escalation rate and 10000 bps cap are both correct and unchanged.
