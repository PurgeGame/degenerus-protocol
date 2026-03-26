# Phase 50: Skim Redesign Audit - Research

**Researched:** 2026-03-21
**Domain:** Solidity arithmetic correctness, ETH conservation, smart contract audit methodology
**Confidence:** HIGH

## Summary

Phase 50 audits the redesigned `_applyTimeBasedFutureTake` function (DegenerusGameAdvanceModule.sol, lines 985-1055) and its helper `_nextToFutureBps` (lines 955-983). The function implements a 5-step pipeline that moves ETH from the next prize pool to the future prize pool at each level transition. The redesign (commit b06d80a8) replaced the old growth adjustment + flat variance approach with: (1) deterministic bps from a U-curve + x9 bonus + ratio adjustment + overshoot surcharge, (2) additive random 0-10% on bps, (3) uncapped take computation, (4) triangular multiplicative variance, (5) hard cap at 80% of nextPool. A 1% insurance skim goes to yieldAccumulator.

An existing 22-test fuzz suite in FuturepoolSkim.t.sol covers conservation, take cap, insurance, variance shape, additive bounds, bit-window independence, and pipeline ordering. All 22 tests pass (verified). The audit must produce line-level verdicts for each arithmetic step, prove ETH conservation algebraically, verify insurance precision, and assess overshoot economic behavior. Several potential findings were identified during research that need formal write-up.

**Primary recommendation:** Structure the audit as three plans: (1) arithmetic correctness of each pipeline step with line-ref verdicts, (2) ETH conservation + insurance skim proof, (3) overshoot economic analysis + level-1 safety. Each plan produces a findings document with safe/finding verdicts.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| SKIM-01 | Overshoot surcharge formula is monotonic and capped at 35% | Lines 1012-1019: hyperbolic formula `(excess * 4000) / (excess + 10000)`, capped at OVERSHOOT_CAP_BPS=3500. Monotonicity provable via calculus on f(x)=4000x/(x+10000). Code and test at lines 510-516 ready for formal verdict. |
| SKIM-02 | Ratio adjustment is bounded +/-400 bps and drives bps to 0 (not negative) | Lines 1000-1008: bump capped at 400, penalty capped at 400, `bps = penalty >= bps ? 0 : bps - penalty` prevents underflow. Test at lines 489-504. |
| SKIM-03 | Additive random consumes bits [0:63] only; variance rolls use [64:191] and [192:255] with no overlap | **POTENTIAL FINDING**: Line 1023 uses `rngWord % 1001` which consumes ALL 256 bits of rngWord, not just [0:63]. Lines 1036-1037 shift right by 64 and 192 respectively. Roll1 (bits [64:255]) and roll2 (bits [192:255]) share the top 64 bits. Functional independence still holds via modulo, but literal bit isolation per the requirement does not. |
| SKIM-04 | Triangular variance cannot underflow take (subtraction is safe) | Lines 1033+1040-1044: `halfWidth` is clamped to `<= take`, `combined` is in `[0, halfWidth*2]`, so `halfWidth - combined` in subtraction path has `combined < halfWidth <= take`, making `take -= (halfWidth - combined)` safe. Formal proof needed. |
| SKIM-05 | Take cap at 80% of nextPool holds under all input combinations | Lines 1047-1049: `maxTake = (nextPoolBefore * 8000) / 10000`, take clamped. Fuzz test `testFuzz_G2_takeCapped` passes 1000 runs. |
| SKIM-06 | ETH conservation: nextPool + futurePool + yieldAccumulator is invariant | Lines 1051-1054: `next -= take + insurance`, `future += take`, `yield += insurance`. Algebraically: sum_after = (next - take - ins) + (future + take) + (yield + ins) = next + future + yield = sum_before. Fuzz test `testFuzz_conservation` passes 1000 runs. |
| SKIM-07 | Insurance skim is always exactly 1% of nextPoolBefore | Line 1051: `insuranceSkim = (nextPoolBefore * 100) / 10000`. Integer division truncates. For `nextPoolBefore < 100 wei`, insurance = 0 (1 wei loss). Fuzz test `testFuzz_insuranceAlways1Pct` checks this. Need to assess if sub-100-wei pools are realistic. |
| ECON-01 | Overshoot surcharge correctly accelerates futurepool growth during fast levels | Lines 1012-1019: when `rBps > 12500` (nextPool > 1.25x lastPool), surcharge adds bps, increasing take from next to future. Test B (R=3.0) confirms higher skim. |
| ECON-02 | Stall escalation still functions (no regression from growth adjustment removal) | Lines 976-980 in `_nextToFutureBps`: elapsed > 28 days enters stall escalation: `FAST + lvlBonus + ((elapsed-28d)/1w)*100`. No dependency on removed growth adjustment. Test D (60-day stall) confirms non-zero take. |
| ECON-03 | Level 1 (lastPool=0) is safe -- overshoot dormant, no division by zero | Line 1012: `if (lastPool != 0)` guards overshoot block. **BUT**: in production, `levelPrizePool[0] = BOOTSTRAP_PRIZE_POOL = 50 ether` (DegenerusGame.sol:252), so at level 1, lastPool is 50 ether, NOT zero. Overshoot CAN fire at level 1 if nextPool > 62.5 ether. The test uses lastPool=0 which is unreachable in production. Need to verify whether overshoot at level 1 is intentional/acceptable. |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Foundry (forge) | latest | Solidity fuzz testing framework | Already configured in foundry.toml, 22 tests exist |
| Solidity | 0.8.34 | Smart contract language | Project compiler version, overflow protection built-in |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| forge-std/Test.sol | latest | Test utilities (assertEq, bound, vm) | All fuzz tests inherit from this |

### Alternatives Considered
None -- this is an audit phase, not a development phase. The stack is fixed.

## Architecture Patterns

### Audit Methodology

The skim pipeline is a single internal function (71 lines) with a helper (29 lines). The audit should be structured as a line-by-line walkthrough producing verdicts for each arithmetic step.

### Pattern 1: Step-by-Step Verdict Document
**What:** Each arithmetic step gets a formal verdict (SAFE or FINDING) with the following structure:
- Step number and description
- Line references in DegenerusGameAdvanceModule.sol
- Arithmetic analysis (bounds, overflow potential, edge cases)
- Existing test coverage (which test covers this)
- Verdict: SAFE with justification, or FINDING with severity
**When to use:** For requirements SKIM-01 through SKIM-05

### Pattern 2: Conservation Proof
**What:** Algebraic proof that the sum `nextPool + futurePool + yieldAccumulator` is invariant across the function, then cross-reference with fuzz evidence
**When to use:** For SKIM-06 and SKIM-07

### Pattern 3: Economic Behavior Verification
**What:** Trace the economic effect of overshoot surcharge and stall escalation through specific scenarios, verify against design intent
**When to use:** For ECON-01, ECON-02, ECON-03

### Anti-Patterns to Avoid
- **Restating code without analysis:** Every line reference must include WHY it is safe or finding, not just what it does
- **Trusting tests as proof:** Fuzz tests provide evidence but are not proof. The audit must include analytical reasoning alongside fuzz coverage
- **Missing the calling context:** Line 315-316 shows `_applyTimeBasedFutureTake` is called after `levelPrizePool[purchaseLevel]` is set. The `lvl` parameter is `purchaseLevel`, not `purchaseLevel + 1`. This means `lastPool = levelPrizePool[purchaseLevel - 1]` reads the PREVIOUS level's snapshot, not the current one. Verify this is correct.

## Don't Hand-Roll

Not applicable -- this is an audit/analysis phase producing documents, not code.

## Common Pitfalls

### Pitfall 1: Bit-Field "Isolation" vs "Independence"
**What goes wrong:** The requirement SKIM-03 specifies that additive random "consumes bits [0:63] only." The code uses `rngWord % 1001` which is a function of ALL 256 bits, not just the low 64. This is not a security bug (the modulo operation is deterministic and safe), but it fails the literal requirement as stated.
**Why it happens:** Modulo on a 256-bit number is influenced by all bits. Only bit-shifting isolates specific windows.
**How to avoid:** The verdict should distinguish between "functionally independent" (different operations on different parts of the word) and "bit-isolated" (only reading specific bits). The additive step is NOT bit-isolated, but it IS functionally independent because it uses modulo rather than shift-and-mask.
**Warning signs:** Requirements specifying exact bit ranges when code uses modulo operations.

### Pitfall 2: Roll1 and Roll2 Share Top 64 Bits
**What goes wrong:** `roll1 = (rngWord >> 64) % range` operates on bits [64:255] (192 bits in positions [0:191]). `roll2 = (rngWord >> 192) % range` operates on bits [192:255] (64 bits in positions [0:63]). The bits [192:255] appear in BOTH shifted values. This means roll1 and roll2 are not derived from fully independent bit windows.
**Why it happens:** The shift operations overlap -- shifting by 64 and by 192 both include the top 64 bits of the original word.
**How to avoid:** This is an INFO-level finding, not a vulnerability. The triangular distribution still works because `% range` makes the outputs effectively independent for any reasonably sized range. True bit isolation would use masking: `(rngWord >> 64) & ((1 << 128) - 1)` for roll1 and `(rngWord >> 192)` for roll2.
**Warning signs:** When bit ranges in comments/docs overlap in the actual shift operations.

### Pitfall 3: Level-1 Bootstrap Pool Contradicts Test Assumptions
**What goes wrong:** The test `test_level1_overshootDormant` passes `lastPool=0` for level 1, but in production `levelPrizePool[0] = 50 ether`. The test proves overshoot is dormant when lastPool=0 (correct -- the `if (lastPool != 0)` guard handles it), but does not test the actual production scenario where lastPool=50 ether.
**Why it happens:** Test harness allows arbitrary lastPool values without enforcing production constraints.
**How to avoid:** The ECON-03 verdict must address BOTH scenarios: (a) the guard correctly handles lastPool=0, and (b) at production level 1 with lastPool=50 ether, overshoot behavior is intentional/acceptable.
**Warning signs:** Test edge cases that cannot occur in production due to constructor initialization.

### Pitfall 4: Division by Zero in Ratio Calculation
**What goes wrong:** Line 1001: `(futurePoolBefore * 100) / nextPoolBefore` divides by `nextPoolBefore`. If the next prize pool is somehow zero, this reverts.
**Why it happens:** `_getNextPrizePool()` returns a uint128 unpacked from storage. After deductions from other systems, it could theoretically reach zero.
**How to avoid:** Verify that the calling context guarantees nextPoolBefore > 0 at the point of invocation. In practice, levelPrizePool[purchaseLevel] is set to the current nextPool right before calling (line 315), and advancing a level requires purchases that add ETH, making zero pools extremely unlikely. But the code has no explicit guard.
**Warning signs:** Division operations without zero-checks where the denominator comes from storage.

### Pitfall 5: Insurance Skim Rounding at Dust Amounts
**What goes wrong:** `insuranceSkim = (nextPoolBefore * 100) / 10_000` truncates to zero for `nextPoolBefore < 100 wei`. This means insurance gets nothing, and the "exactly 1%" property fails at dust.
**Why it happens:** Integer division truncation.
**How to avoid:** Determine whether `nextPoolBefore < 100 wei` is realistic. Given pools are in ether-scale (min realistic ~0.01 ether = 10^16 wei), this is not a practical concern. The fuzz test bounds nextPool to [1 ether, 10000 ether]. Document as INFO.
**Warning signs:** "Exactly X%" claims with integer division.

## Code Examples

### The Complete 5-Step Pipeline (lines 985-1055)
```solidity
// Source: contracts/modules/DegenerusGameAdvanceModule.sol:985-1055
function _applyTimeBasedFutureTake(uint48 reachedAt, uint24 lvl, uint256 rngWord) internal {
    uint48 start = levelStartTime + 11 days;
    if (reachedAt < start) reachedAt = start;                    // Clamp to 11-day offset

    uint256 bps = _nextToFutureBps(reachedAt - start, lvl);      // Step 0: U-curve bps
    if (lvl % 10 == 9) bps += NEXT_TO_FUTURE_BPS_X9_BONUS;       // x9 bonus (+200 bps)

    uint256 nextPoolBefore = _getNextPrizePool();
    uint256 futurePoolBefore = _getFuturePrizePool();
    uint256 lastPool = levelPrizePool[lvl - 1];

    // Step 1: Ratio adjustment +/-400 bps (target 2:1 future:next)
    uint256 ratioPct = (futurePoolBefore * 100) / nextPoolBefore;
    if (ratioPct < 200) {
        uint256 bump = 200 - ratioPct;
        bps += (bump > 400 ? 400 : bump);
    } else {
        uint256 penalty = ratioPct - 200;
        penalty = penalty > 400 ? 400 : penalty;
        bps = penalty >= bps ? 0 : bps - penalty;
    }

    // Step 1b: Overshoot surcharge (hyperbolic, R > 1.25x)
    if (lastPool != 0) {
        uint256 rBps = (nextPoolBefore * 10_000) / lastPool;
        if (rBps > OVERSHOOT_THRESHOLD_BPS) {
            uint256 excess = rBps - OVERSHOOT_THRESHOLD_BPS;
            uint256 surcharge = (excess * OVERSHOOT_COEFF) / (excess + 10_000);
            if (surcharge > OVERSHOOT_CAP_BPS) surcharge = OVERSHOOT_CAP_BPS;
            bps += surcharge;
        }
    }

    // Step 2: Additive random 0-10% on bps
    bps += rngWord % (ADDITIVE_RANDOM_BPS + 1);

    // Step 3: Compute take from uncapped bps
    uint256 take = (nextPoolBefore * bps) / 10_000;

    // Step 4: +/-25% multiplicative variance (triangular)
    if (take != 0) {
        uint256 halfWidth = (take * NEXT_SKIM_VARIANCE_BPS) / 10_000;
        uint256 minWidth = (nextPoolBefore * NEXT_SKIM_VARIANCE_MIN_BPS) / 10_000;
        if (halfWidth < minWidth) halfWidth = minWidth;
        if (halfWidth > take) halfWidth = take;
        uint256 range = halfWidth * 2 + 1;
        uint256 roll1 = (rngWord >> 64) % range;
        uint256 roll2 = (rngWord >> 192) % range;
        uint256 combined = (roll1 + roll2) / 2;
        if (combined >= halfWidth) {
            take += combined - halfWidth;
        } else {
            take -= halfWidth - combined;
        }
    }

    // Step 5: Cap take at 80% of nextPool
    uint256 maxTake = (nextPoolBefore * NEXT_TO_FUTURE_BPS_MAX) / 10_000;
    if (take > maxTake) take = maxTake;

    uint256 insuranceSkim = (nextPoolBefore * INSURANCE_SKIM_BPS) / 10_000;
    _setNextPrizePool(nextPoolBefore - take - insuranceSkim);
    _setFuturePrizePool(futurePoolBefore + take);
    yieldAccumulator += insuranceSkim;
}
```

### Constants (lines 100-111)
```solidity
// Source: contracts/modules/DegenerusGameAdvanceModule.sol:100-111
uint16 private constant NEXT_TO_FUTURE_BPS_FAST = 3000;       // 30% fast fill
uint16 private constant NEXT_TO_FUTURE_BPS_MIN = 1300;        // 13% U-curve trough
uint16 private constant NEXT_TO_FUTURE_BPS_WEEK_STEP = 100;   // +1% per week stall
uint16 private constant NEXT_TO_FUTURE_BPS_X9_BONUS = 200;    // +2% x9 levels
uint16 private constant NEXT_SKIM_VARIANCE_BPS = 2500;        // 25% variance halfWidth
uint16 private constant NEXT_SKIM_VARIANCE_MIN_BPS = 1000;    // 10% min variance floor
uint16 private constant INSURANCE_SKIM_BPS = 100;             // 1% insurance
uint16 private constant OVERSHOOT_THRESHOLD_BPS = 12500;      // R > 1.25x triggers
uint16 private constant OVERSHOOT_CAP_BPS = 3500;             // 35% max surcharge
uint16 private constant OVERSHOOT_COEFF = 4000;               // hyperbolic numerator
uint16 private constant NEXT_TO_FUTURE_BPS_MAX = 8000;        // 80% hard cap
uint16 private constant ADDITIVE_RANDOM_BPS = 1000;           // 0-10% random
```

### Calling Context (lines 314-317)
```solidity
// Source: contracts/modules/DegenerusGameAdvanceModule.sol:314-317
levelPrizePool[purchaseLevel] = _getNextPrizePool();
_applyTimeBasedFutureTake(ts, purchaseLevel, rngWord);
_consolidatePrizePools(purchaseLevel, rngWord);
poolConsolidationDone = true;
```

### U-Curve Helper (lines 955-983)
```solidity
// Source: contracts/modules/DegenerusGameAdvanceModule.sol:955-983
function _nextToFutureBps(uint48 elapsed, uint24 lvl) internal pure returns (uint16) {
    uint256 lvlBonus = (uint256(lvl % 100) / 10) * 100;
    uint256 bps;
    if (elapsed <= 1 days) {
        bps = NEXT_TO_FUTURE_BPS_FAST + lvlBonus;              // 30% + bonus
    } else if (elapsed <= 14 days) {
        // Descend from FAST to MIN over days 1-14
        uint256 elapsedAfterDay = elapsed - 1 days;
        uint256 delta = NEXT_TO_FUTURE_BPS_FAST + lvlBonus - NEXT_TO_FUTURE_BPS_MIN;
        bps = NEXT_TO_FUTURE_BPS_FAST + lvlBonus - (delta * elapsedAfterDay) / 13 days;
    } else if (elapsed <= 28 days) {
        // Ascend from MIN back to FAST over days 14-28
        uint256 elapsedAfterMin = elapsed - 14 days;
        uint256 delta = NEXT_TO_FUTURE_BPS_FAST + lvlBonus - NEXT_TO_FUTURE_BPS_MIN;
        bps = NEXT_TO_FUTURE_BPS_MIN + (delta * elapsedAfterMin) / 14 days;
    } else {
        // Stall escalation: +1% per week beyond 28 days
        bps = NEXT_TO_FUTURE_BPS_FAST + lvlBonus +
            ((elapsed - 28 days) / 1 weeks) * NEXT_TO_FUTURE_BPS_WEEK_STEP;
    }
    return uint16(bps > 10_000 ? 10_000 : bps);
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Growth adjustment + flat uniform variance | 5-step pipeline with overshoot surcharge + triangular variance | Commit b06d80a8 (2026-03-21) | Cleaner arithmetic, better economic behavior at extreme growth rates |
| Hard cap on bps | Hard cap on take (80% of nextPool) | Same commit | More intuitive cap -- directly limits ETH moved |
| Uniform +/-25% variance | Triangular +/-25% variance (avg of two rolls) | Same commit | Center-weighted distribution, more predictable outcomes |
| +/-200 bps ratio adjustment | +/-400 bps ratio adjustment | Same commit | Stronger pool rebalancing force |

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Foundry (forge) with Solidity 0.8.34 |
| Config file | foundry.toml |
| Quick run command | `forge test --match-contract FuturepoolSkimTest -x` |
| Full suite command | `forge test --match-contract FuturepoolSkimTest -vvv` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| SKIM-01 | Overshoot monotonic + 35% cap | unit | `forge test --match-test test_overshootSurcharge_spotValues -x` | Exists (line 510) |
| SKIM-02 | Ratio adjustment bounded +/-400 | unit | `forge test --match-test test_ratioAdjust_cappedAt400 -x` | Exists (line 490) |
| SKIM-03 | Bit-field isolation | unit | `forge test --match-test test_vrf_bitWindows_independent -x` | Exists (line 565) but tests independence not isolation |
| SKIM-04 | Triangular variance no underflow | unit+fuzz | `forge test --match-test testFuzz_G2_takeCapped -x` | Exists (line 262); implicit -- needs explicit underflow test |
| SKIM-05 | 80% take cap | fuzz | `forge test --match-test testFuzz_G2_takeCapped -x` | Exists (line 262) |
| SKIM-06 | ETH conservation | fuzz | `forge test --match-test testFuzz_conservation -x` | Exists (line 404) |
| SKIM-07 | Insurance exactly 1% | fuzz | `forge test --match-test testFuzz_insuranceAlways1Pct -x` | Exists (line 428) |
| ECON-01 | Overshoot accelerates growth | unit | `forge test --match-test test_B_fastOvershoot_R3 -x` | Exists (line 135) |
| ECON-02 | Stall escalation works | unit | `forge test --match-test test_D_stall_60day -x` | Exists (line 180) |
| ECON-03 | Level 1 safe | unit | `forge test --match-test test_level1_overshootDormant -x` | Exists (line 455) but uses unrealistic lastPool=0 |

### Sampling Rate
- **Per task commit:** `forge test --match-contract FuturepoolSkimTest -x`
- **Per wave merge:** `forge test --match-contract FuturepoolSkimTest -vvv`
- **Phase gate:** Full suite green + all 10 requirement verdicts documented

### Wave 0 Gaps
None -- existing 22-test infrastructure covers all phase requirements. The audit output is verdict documents, not new code.

## Open Questions

1. **SKIM-03: Is modulo on full word acceptable as "bit isolation"?**
   - What we know: `rngWord % 1001` is a function of all 256 bits, not just [0:63]. The commit message and requirement specify [0:63].
   - What's unclear: Whether the requirement intends literal bit isolation or functional independence.
   - Recommendation: Document as INFO finding. The additive step's output is functionally independent from variance rolls because it uses modulo rather than bit extraction. Suggest rewording the requirement or noting the discrepancy.

2. **SKIM-03: Roll1 and roll2 share the top 64 bits**
   - What we know: `(rngWord >> 64)` and `(rngWord >> 192)` both contain bits [192:255] from the original word. The bit windows are [64:255] and [192:255], overlapping in [192:255].
   - What's unclear: Whether this overlap meaningfully reduces the quality of the triangular distribution.
   - Recommendation: Document as INFO. For any practical `range` value, `% range` destroys the correlation. The triangular shape test passes. True isolation would require masking: `(rngWord >> 64) & ((1 << 128) - 1)`.

3. **ECON-03: Overshoot at level 1 with BOOTSTRAP_PRIZE_POOL**
   - What we know: In production, `levelPrizePool[0] = 50 ether`. At level 1, if nextPool > 62.5 ether, overshoot surcharge activates. The existing test bypasses this by setting lastPool=0.
   - What's unclear: Is overshoot activation at level 1 intentional design or an unintended consequence?
   - Recommendation: Ask protocol team. If intentional, document as SAFE. If not, this could be an INFO finding (not exploitable, but may cause slightly higher-than-expected skim on the first level transition).

4. **Division by zero in ratio calculation**
   - What we know: Line 1001 divides by `nextPoolBefore` without a zero-check. In practice, advancing a level requires purchases (which add ETH), making zero pools near-impossible.
   - What's unclear: Whether any edge path could drain nextPool to exactly zero before this function is called.
   - Recommendation: Audit the calling context. The `levelPrizePool[purchaseLevel] = _getNextPrizePool()` on line 315 confirms the pool is read right before the call. If it were zero, the level could not have been reached. Likely SAFE, but document the reasoning.

## Sources

### Primary (HIGH confidence)
- **DegenerusGameAdvanceModule.sol lines 985-1055** -- Complete `_applyTimeBasedFutureTake` implementation, read directly
- **DegenerusGameAdvanceModule.sol lines 955-983** -- Complete `_nextToFutureBps` U-curve implementation, read directly
- **DegenerusGameAdvanceModule.sol lines 100-111** -- All 12 pipeline constants, read directly
- **DegenerusGameAdvanceModule.sol lines 314-317** -- Calling context for level transitions, read directly
- **DegenerusGameStorage.sol lines 675-771** -- Prize pool getter/setter implementations, read directly
- **DegenerusGameStorage.sol line 137-138** -- `BOOTSTRAP_PRIZE_POOL = 50 ether`, read directly
- **DegenerusGame.sol line 252** -- `levelPrizePool[0] = BOOTSTRAP_PRIZE_POOL` constructor init, read directly
- **FuturepoolSkim.t.sol (612 lines)** -- Complete 22-test fuzz suite, read directly and executed (`forge test` -- all pass)
- **Commit b06d80a8** -- Skim redesign commit message with full change description, read directly

### Secondary (MEDIUM confidence)
None needed -- all analysis is from direct code reading.

### Tertiary (LOW confidence)
None.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - Direct code reading, no external dependencies to verify
- Architecture: HIGH - Single function audit, complete code available, all tests passing
- Pitfalls: HIGH - All 5 pitfalls identified from direct code analysis with line references
- Requirements coverage: HIGH - All 10 requirements mapped to specific code lines

**Research date:** 2026-03-21
**Valid until:** Indefinite (code is the source of truth; if code changes, re-research)
