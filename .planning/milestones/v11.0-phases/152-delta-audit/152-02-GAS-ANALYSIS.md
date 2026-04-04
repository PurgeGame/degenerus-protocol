# Phase 152-02: Gas Ceiling Analysis for Drip Projection Computation

**Date:** 2026-03-31
**Requirement:** AUD-03
**Baseline:** Phase 147 gas analysis (advanceGame ceiling: 14M block, WRITES_BUDGET_SAFE=550)

---

## 1. _wadPow Gas Profile (D-09)

**Function:** `DegenerusGameAdvanceModule._wadPow(uint256 base, uint256 exp)` (lines 1616-1626)

Repeated-squaring exponentiation in WAD (1e18) scale.

**Worst-case input:** `exp = 120` (maximum daysRemaining from the 120-day liveness guard).

120 in binary = `1111000` = 7 bits = **7 loop iterations**, of which 4 have the odd-exponent branch (`exp & 1 == 1`).

### Per-iteration gas breakdown

| Operation | Gas | When |
|-----------|-----|------|
| `exp > 0` comparison | 3 | Every iteration |
| `exp & 1` bitwise AND | 3 | Every iteration |
| Conditional branch | 3 | Every iteration |
| `result * base` MUL | 5 | Odd iterations only (4 of 7) |
| `/ 1 ether` DIV | 5 | Odd iterations only (4 of 7) |
| `base * base` MUL | 5 | Every iteration |
| `/ 1 ether` DIV | 5 | Every iteration |
| `exp >>= 1` SHR | 3 | Every iteration |
| Loop overhead (JUMP, stack) | ~5 | Every iteration |

**Per even iteration:** ~27 gas
**Per odd iteration:** ~37 gas

**Total for exp=120 (7 iterations, 4 odd):** 3 * 27 + 4 * 37 = 81 + 148 = **~229 gas**

Rounding up with function call overhead: **~250 gas**

### Overflow analysis

Intermediate product: `base * base` where `base <= 1e18` (WAD scale).
Maximum intermediate: `(1e18)^2 = 1e36`, well within `uint256` range (`2^256 ~ 1.16e77`).
For `DECAY_RATE = 0.9925e18`: `0.9925e18 * 0.9925e18 = ~0.985e36`, divided by `1e18` = `~0.985e18`. All intermediate values stay in WAD range.

**No overflow risk.**

---

## 2. _projectedDrip Gas Profile

**Function:** `DegenerusGameAdvanceModule._projectedDrip(uint256 futurePool, uint256 daysRemaining)` (lines 1630-1637)

### Worst-case path (daysRemaining > 0)

| Operation | Gas | Notes |
|-----------|-----|-------|
| `daysRemaining == 0` check | 3 | Comparison |
| `_wadPow(DECAY_RATE, daysRemaining)` | ~250 | See Section 1 |
| `1 ether - decayN` SUB | 3 | |
| `futurePool * (...)` MUL | 5 | |
| `/ 1 ether` DIV | 5 | |
| Function call overhead | ~10 | |
| **Total** | **~276** | |

**Rounded:** **~280 gas**

### Edge case: daysRemaining == 0

Early return costs ~10 gas (comparison + JUMP + return).

### Underflow analysis

`DECAY_RATE = 0.9925e18 < 1e18`, so `_wadPow(0.9925e18, n)` always returns a value `< 1e18` for any `n > 0`. Therefore `1 ether - decayN > 0` always holds. No underflow risk in the SUB.

**No underflow risk.**

---

## 3. _evaluateGameOverPossible Gas Profile (D-10)

**Function:** `DegenerusGameAdvanceModule._evaluateGameOverPossible(uint24 lvl, uint24 purchaseLevel)` (lines 1642-1659)

### Worst-case path: flag gets set (all operations execute)

| Operation | Gas (warm) | Gas (cold) | Notes |
|-----------|-----------|-----------|-------|
| `lvl < 10` comparison | 3 | 3 | Always executed |
| `_getNextPrizePool()` SLOAD | 100 | 2,100 | Packed Slot 1 — warm from advanceGame entry reads |
| `levelPrizePool[purchaseLevel-1]` SLOAD | 100 | 2,100 | Mapping read |
| `nextPool >= target` comparison | 3 | 3 | |
| `target - nextPool` SUB | 3 | 3 | Deficit arithmetic |
| `levelStartTime` read | 100 | 2,100 | Packed Slot 0 — warm from advanceGame entry |
| daysRemaining arithmetic (ADD+SUB+DIV) | 15 | 15 | Constant folding on `120 days` |
| `_getFuturePrizePool()` SLOAD | 100 | 2,100 | Packed slot — warm from advanceGame context |
| `_projectedDrip()` call | 280 | 280 | Pure computation (Section 2) |
| `gameOverPossible` SSTORE | 100-20,000 | 20,000 | See SSTORE analysis below |
| Function call overhead | ~20 | ~20 | |
| **Total (warm, dirty slot)** | **~824** | | Typical advanceGame context |
| **Total (warm, 0->nonzero SSTORE)** | **~20,724** | | Worst-case SSTORE |
| **Total (cold)** | **~28,724** | | First call only (unrealistic) |

### SSTORE cost analysis for gameOverPossible

`gameOverPossible` lives in Slot 1 (packed bool at byte 25). In the advanceGame context:

- **Slot 1 already warm** from prior reads (level, jackpotPhaseFlag, lastPurchaseDay, etc.)
- **0 -> 1 transition** (false -> true): 20,000 gas per EIP-2200 (zero-to-nonzero)
- **1 -> 1 transition** (already true, re-setting): 100 gas (warm, same value)
- **1 -> 0 transition** (clearing): 100 gas + 4,800 refund under EIP-3529
- **Slot already dirty** from other Slot 1 writes in same tx: 100 gas (EIP-2200 dirty slot)

Worst-case SSTORE: **20,000 gas** (false -> true, slot not yet dirty at this byte).

However, the turbo path (line 154) writes `gameOverPossible = false` to Slot 1 early in advanceGame. If that path executes first, Slot 1 is already dirty, reducing cost to 100 gas. The two _evaluateGameOverPossible call sites are:

1. **Phase transition (line 289):** Slot 1 is likely dirty from `phaseTransitionActive = false` (line 284) and `jackpotPhaseFlag = false` (line 287) — both Slot 1 bools. Cost: **100 gas**.
2. **Daily re-check (line 327):** Only runs when `gameOverPossible` is already true (non-zero), so the SSTORE is either same-value (100 gas) or nonzero-to-zero (100 gas + refund).

**Realistic worst-case: ~21,000 gas** (phase transition path, conservative 0->nonzero SSTORE).

---

## 4. Impact on advanceGame Gas Ceiling (D-11, D-12)

### Phase 147 baseline

| Metric | Value |
|--------|-------|
| Block gas limit | 14,000,000 |
| WRITES_BUDGET_SAFE | 550 write-units |
| Worst-case first batch | ~4,562,500 gas |
| Worst-case subsequent batch | ~6,975,000 gas |
| Theoretical maximum cap | 1,112 write-units |
| Safety margin | 2.0x over 14M ceiling |

### Call frequency analysis

_evaluateGameOverPossible is called at most **ONCE** per advanceGame execution:

1. **Phase transition (line 289):** Only on the specific call that completes a phase transition. Sets `stage = STAGE_TRANSITION_DONE` and breaks.
2. **Daily re-check (line 327):** Only in the `!lastPurchaseDay` purchase path, and only when `gameOverPossible` is already true.

These two call sites are **mutually exclusive** within a single advanceGame execution because:
- Phase transition (line 289) is inside the `phaseTransitionActive` branch, which sets `stage = STAGE_TRANSITION_DONE` and breaks out of the switch.
- Daily re-check (line 327) is inside the `!inJackpot && !lastPurchaseDay` branch of the main purchase-phase path, which only executes when no phase transition is active.

The turbo path clear (line 154, `gameOverPossible = false`) is a simple warm SSTORE costing 100 gas (nonzero->zero gets 4,800 refund under EIP-3529).

### Updated gas ceiling

| Scenario | Phase 147 baseline | + _evaluateGameOverPossible | Delta |
|----------|-------------------|---------------------------|-------|
| Worst-case subsequent batch | 6,975,000 | 6,996,000 | +21,000 (+0.30%) |
| Worst-case first batch | 4,562,500 | 4,583,500 | +21,000 (+0.46%) |

**Updated safety margin:** 14,000,000 / 6,996,000 = **2.00x** (effectively unchanged from 2.0x baseline)

### Comparison to Phase 147 baseline

| Metric | Phase 147 | Phase 152 (updated) | Change |
|--------|-----------|-------------------|--------|
| Worst-case gas | 6,975,000 | 6,996,000 | +0.30% |
| Safety margin | 2.00x | 2.00x | No regression |
| WRITES_BUDGET_SAFE | 550 | 550 | Unchanged |
| Additional SLOADs | - | 0-3 (all warm) | Negligible |
| Additional SSTOREs | - | 1 (gameOverPossible) | +20,000 worst-case |

---

## 5. Verdict

The drip projection computation (`_wadPow` + `_projectedDrip` + `_evaluateGameOverPossible`) adds at most **~21,000 gas** to advanceGame under worst-case conditions (0->nonzero SSTORE for gameOverPossible). Against the 14M block gas ceiling and the existing ~7M worst-case budget, this is a **0.3% increase**.

The **2.0x safety margin is preserved**. No gas ceiling breach. No regression from Phase 147 baseline.

**AUD-03 SATISFIED.**

---

*Analysis date: 2026-03-31*
*Baseline: Phase 147 gas analysis*
*Contract: DegenerusGameAdvanceModule.sol (lines 1616-1659)*
