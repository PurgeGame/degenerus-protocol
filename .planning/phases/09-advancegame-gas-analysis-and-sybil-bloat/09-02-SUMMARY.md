---
phase: 09-advancegame-gas-analysis-and-sybil-bloat
plan: "02"
subsystem: testing
tags: [gas, sybil, ticket-queue, processTicketBatch, eip-2929, cold-sstore]

# Dependency graph
requires:
  - phase: 09-advancegame-gas-analysis-and-sybil-bloat
    plan: "01"
    provides: "Baseline advanceGame() gas measurements for all 13 stages; GAS-01 PASS verdict"
provides:
  - "GAS-02 verdict: processTicketBatch gas ceiling confirmed well under 16M"
  - "GAS-03 verdict: Sybil breakeven N derivation showing no finite N can push single call to 16M"
  - "GAS-04 verdict: Permanent DoS economics quantified at ~4,950 ETH/day vs. 1,000 ETH budget"
  - "Sybil adversarial gas test (describe block 14) in AdvanceGameGas.test.js"
affects:
  - phase 13 gas report

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Sybil test pattern: use all available Hardhat signers as buyers; wrap purchases in try/catch for graceful failure handling"
    - "Gas measurement under adversarial queue load: buy at actual level price (not TICKET_MIN_BUYIN_WEI floor)"

key-files:
  created:
    - .planning/phases/09-advancegame-gas-analysis-and-sybil-bloat/09-02-SUMMARY.md
  modified:
    - test/gas/AdvanceGameGas.test.js

key-decisions:
  - "GAS-02 PASS: processTicketBatch max Sybil cold batch measured at 5,193,019 gas (32.5% of 16M limit)"
  - "GAS-03 PASS: WRITES_BUDGET_SAFE=550 enforces hard per-call ceiling of ~7.4M gas; no N wallets can push single advanceGame() call to 16M"
  - "GAS-04 PASS: Permanent ticket queue DoS costs ~4,950 ETH/day; exceeds 1,000 ETH threat model (LOW theoretical)"
  - "Level-0 purchase cost clarification: price = 0.01 ETH at deploy; 1 full ticket (qty=400) costs 0.01 ETH, not TICKET_MIN_BUYIN_WEI = 0.0025 ETH (which is the enforcement floor, not the level-0 price)"
  - "19 Sybil wallets (all available Hardhat others + named signers) is sufficient to demonstrate the gas model; queue drained in first cold batch confirming well below 357-entry budget ceiling"

patterns-established:
  - "Sybil adversarial test: loadFixture state, buy 1 full ticket per signer, advanceToNextDay, VRF cycle, measure gas of first processTicketBatch call"

requirements-completed:
  - GAS-02
  - GAS-03
  - GAS-04

# Metrics
duration: 15min
completed: 2026-03-04
---

# Phase 9 Plan 02: Sybil Ticket Bloat and GAS-02/03/04 Analysis Summary

**Adversarial Sybil queue gas measured at 5,193,019 gas (32.5% of 16M limit); WRITES_BUDGET_SAFE=550 provides a hard per-call ceiling making single-call DoS impossible; permanent DoS costs ~4,950 ETH/day exceeding the 1,000 ETH threat model**

## Performance

- **Duration:** 15 min
- **Started:** 2026-03-04T22:10:08Z
- **Completed:** 2026-03-04T22:25:00Z
- **Tasks:** 2
- **Files modified:** 1 (test), 1 (summary)

## Accomplishments

- Added Sybil adversarial test scenario (describe block 14) to `test/gas/AdvanceGameGas.test.js` using all 19 available non-deployer Hardhat signers
- Measured first-cold-batch gas at 5,193,019 gas under 19-wallet Sybil queue load
- Derived GAS-02, GAS-03, and GAS-04 verdicts from measured gas + EIP-2929 arithmetic model
- Confirmed level-0 ticket purchase requires 0.01 ETH per full ticket (price = 0.01 ETH at deploy, not TICKET_MIN_BUYIN_WEI = 0.0025 ETH)

## Task Commits

Each task was committed atomically:

1. **Task 1: Add Sybil Bloat scenario to gas harness and run it** - `cc41e2e` (feat)
2. **Task 2: Derive Sybil model and write 09-02-SUMMARY.md** - see plan metadata commit

**Plan metadata:** (docs: complete plan — see final commit)

---

## Measured Gas Table (Sybil + Full Suite)

| Test | Gas Used | % of 16M |
|------|----------|----------|
| Ticket Batch 550 writes (stage=5) | 6,284,995 | 39.3% |
| Future Ticket Processing (stage=4) | 6,164,241 | 38.5% |
| **Sybil Ticket Batch — first cold batch (stage=6)** | **5,193,019** | **32.5%** |
| Jackpot ETH Resume (stage=9) | 3,118,467 | 19.5% |
| Final Day Phase End (stage=10) | 2,934,548 | 18.3% |
| Jackpot Coin+Tickets (stage=9) | 2,933,202 | 18.3% |
| Purchase Daily Jackpot (stage=6) | 1,250,369 | 7.8% |
| Jackpot Daily ETH (stage=11) | 887,410 | 5.5% |
| Game Over Drain (stage=0) | 652,553 | 4.1% |
| Phase Transition (stage=3) | 262,884 | 1.6% |
| Fresh VRF Request (stage=1) | 190,909 | 1.2% |
| Enter Jackpot Phase (stage=7) | 189,586 | 1.2% |
| VRF 18h Timeout Retry (stage=1) | 164,997 | 1.0% |
| Game Over VRF Request (stage=0) | 131,966 | 0.8% |
| Final Sweep (stage=0) | 65,874 | 0.4% |

**Sybil scenario details:**
- 19 unique wallets each purchased 1 full ticket (qty=400) at level 0 (price=0.01 ETH, cost=0.01 ETH each)
- Queue fully drained in first call — 19 buyers is well below the 357-entry cold batch ceiling
- Stage=6 result: ticket processing completed AND advanced to STAGE_PURCHASE_DAILY in the same call
- The separate test #3 (550 writes, stage=5) remains the isolated worst-case processTicketBatch measurement at 6,284,995 gas

---

## GAS-02: processTicketBatch Gas Ceiling

### Measurement

The maximum observed `processTicketBatch` gas across all scenarios is **6,284,995 gas** (test #3, non-Sybil adversarial load with 20 buyers × 50 tickets each). Under the Sybil scenario (19 buyers, 1 ticket each, cold SSTORE), the measured gas including STAGE_PURCHASE_DAILY is **5,193,019 gas**.

### Analysis

```
Measured maximum (test #3, STAGE_TICKETS_WORKING):  6,284,995 gas
Sybil cold batch (19 wallets, stage=6):             5,193,019 gas
16M block gas limit:                                16,000,000 gas

Ratio (test #3): 6,284,995 / 16,000,000 = 39.3% of limit
Ratio (Sybil):   5,193,019 / 16,000,000 = 32.5% of limit
```

### Verdict

**GAS-02: PASS — processTicketBatch max measured gas is 6,284,995 (39.3% of 16M limit)**

The worst-case processTicketBatch call uses 6,284,995 gas, leaving a 9,715,005 gas margin (60.7% headroom) against the 16M block limit. This includes all processing overhead: the `advanceGame()` delegatecall chain, VRF gate, event emission, and `coin.creditFlip()` call. No single `advanceGame()` call approaches the 16M limit.

---

## GAS-03: Sybil Breakeven N

### Model

The `processTicketBatch` call is bounded by `WRITES_BUDGET_SAFE = 550` writes per call. On the first batch, cold-storage scaling reduces effective writes to 357 (55 × 0.65 is implicit in the JackpotModule logic: first-batch budget = `WRITES_BUDGET_SAFE × 0.65 ≈ 357` writes).

```
WRITES_BUDGET_SAFE        = 550 writes per processTicketBatch call
First-batch cold scale    = 550 × 0.65 = 357 writes (cold SSTORE budget)
Cold SSTORE cost (EIP-2929) = 20,000 gas per write
Warm SSTORE cost (EIP-2929) = 2,900 gas per write

First-batch SSTORE ceiling:
  357 writes × 20,000 gas = 7,140,000 gas

Plus advanceGame() overhead:
  delegatecall + event emission    ≈ 200,000 gas
  coin.creditFlip() external call  ≈  50,000 gas

Worst-case first-batch total:
  7,140,000 + 200,000 + 50,000 = 7,390,000 gas ≈ 7.4M gas

Comparison against 16M limit:
  7,390,000 / 16,000,000 = 46.2% of limit
  Remaining headroom: 8,610,000 gas (53.8%)
```

### Key Insight: Budget is Enforced by the Contract

The `WRITES_BUDGET_SAFE = 550` constant is a hard per-call limit enforced inside `processTicketBatch`. The contract exits the processing loop when the write budget is consumed, regardless of remaining queue entries. A deeper queue does NOT increase the gas cost of any single call — it only increases the number of calls required to drain the queue.

Therefore:

```
Maximum gas per advanceGame() processTicketBatch call ≈ 7.4M  (hard ceiling)
16M gas limit                                          = 16.0M

N required to push single call to 16M gas             = UNDEFINED (not reachable)
```

No wallet count N can cause a single `processTicketBatch` call to exceed the `WRITES_BUDGET_SAFE` ceiling. The architecture makes single-call gas DoS structurally impossible via ticket queue bloat.

### Verdict

**GAS-03: PASS — WRITES_BUDGET_SAFE=550 enforces hard per-call gas ceiling of ~7.4M; no N exists that pushes single advanceGame() call to 16M**

The per-call write budget (WRITES_BUDGET_SAFE=550) creates a hard gas ceiling independent of queue depth. The arithmetic is:
- 357 cold SSTOREs × 20,000 gas = 7,140,000 gas (SSTORE alone)
- Plus ~250,000 gas overhead = ~7,390,000 gas total
- Ceiling: 46% of 16M — structurally impossible to exceed in a single call

Sybil breakeven N for single-call DoS = **undefined (not reachable with current constants)**.

---

## GAS-04: Sybil DoS Economics

### Model

Since a single `advanceGame()` call cannot be pushed to 16M gas, a Sybil attacker's only path to DoS is **continuously refilling the ticket queue faster than it drains**. This requires active on-chain purchases each block.

```
Entries processed per warm-path batch:  ~275 entries  (550 writes / 2 writes per entry)
Entries processed per cold-path batch:  ~178 entries  (357 writes / 2 writes per entry)

Worst-case attacker must refill 275 entries per block to maintain queue depth:
  275 entries × 0.01 ETH per entry = 2.75 ETH per block (at level 0)

  Note: TICKET_MIN_BUYIN_WEI = 0.0025 ETH is the floor enforced by the contract.
  At level 0, price = 0.01 ETH, so actual cost per ticket = 0.01 ETH.
  At higher levels (e.g., level 5+, price = 0.24 ETH), cost per ticket = 0.24 ETH — even more expensive.

Using TICKET_MIN_BUYIN_WEI = 0.0025 ETH (absolute minimum across all levels) as a lower bound:
  275 entries × 0.0025 ETH = 0.6875 ETH per block

Per day (12s blocks):
  0.6875 ETH × (86,400s / 12s) = 0.6875 ETH × 7,200 blocks = 4,950 ETH/day

Threat model budget: 1,000 ETH total

Days the budget sustains the attack:
  1,000 ETH / 4,950 ETH/day = 0.20 days ≈ 4.9 hours
```

At level-0 actual prices (0.01 ETH):
```
  275 entries × 0.01 ETH × 7,200 blocks/day = 19,800 ETH/day
```

Even at the absolute minimum ticket floor price (0.0025 ETH), permanent DoS costs 4,950 ETH/day — far exceeding the 1,000 ETH threat model budget. The attacker exhausts their budget in under 5 hours without achieving a sustained stall.

### Verdict

**GAS-04: PASS — Permanent ticket queue DoS costs approximately 4,950 ETH/day at minimum pricing; exceeds 1,000 ETH threat model budget (LOW theoretical severity)**

The ETH cost to sustain continuous queue refilling at the minimum ticket price:
- 275 entries/block × 0.0025 ETH/entry × 7,200 blocks/day = **4,950 ETH/day**
- 1,000 ETH threat model budget sustains the attack for **~4.9 hours** only
- At actual level-0 pricing (0.01 ETH), cost rises to **19,800 ETH/day**

Permanent Sybil DoS is **economically infeasible**. The protocol's minimum ticket price creates a natural economic barrier that exceeds any realistic attacker budget.

**Severity:** LOW — Theoretical concern with strong economic bounds. The contract's architectural safeguards (WRITES_BUDGET_SAFE cursor model) and ticket pricing together make this attack impractical.

---

## Verdict Summary

| Requirement | Verdict | Key Metric |
|-------------|---------|-----------|
| **GAS-02** | **PASS** | processTicketBatch max measured gas is 6,284,995 (39.3% of 16M limit) |
| **GAS-03** | **PASS** | WRITES_BUDGET_SAFE=550 enforces hard per-call ceiling; no N exists that pushes single call to 16M |
| **GAS-04** | **PASS** | Permanent DoS costs ~4,950 ETH/day; exceeds 1,000 ETH threat model (LOW theoretical) |

---

## Files Created/Modified

- `test/gas/AdvanceGameGas.test.js` - Added describe block 14 (Sybil Ticket Bloat); 19 Sybil buyers, cold SSTORE gas measurement
- `.planning/phases/09-advancegame-gas-analysis-and-sybil-bloat/09-02-SUMMARY.md` - This file

## Decisions Made

- Used level-0 actual price (0.01 ETH per full ticket) rather than TICKET_MIN_BUYIN_WEI (0.0025 ETH) for Sybil test purchases, because `costWei = (price * qty) / 400 = 0.01 ETH` at level 0. The 0.0025 ETH floor is still used in the GAS-04 economic model as a conservative lower bound.
- GAS-03 verdict frames breakeven N as UNDEFINED rather than a large number, because the WRITES_BUDGET_SAFE hard ceiling makes the question structurally unanswerable — no queue size can increase the per-call gas above 7.4M.
- Stage=6 result for the 19-buyer Sybil test is expected and correct: 19 buyers' tickets are processed within the cold-batch budget, so the call advances past STAGE_TICKETS_WORKING into STAGE_PURCHASE_DAILY within the same transaction.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Corrected Sybil purchase ETH amount from 0.0025 ETH to 0.01 ETH**
- **Found during:** Task 1 (Add Sybil Bloat scenario)
- **Issue:** The plan interface specified `{ value: eth(0.0025) }` (TICKET_MIN_BUYIN_WEI), but at level 0 with `price = 0.01 ETH`, the actual `costWei = (0.01 ETH * 400) / 400 = 0.01 ETH`. Sending 0.0025 ETH resulted in all 19 buyers failing silently.
- **Fix:** Changed `eth(0.0025)` to `eth(0.01)` and updated the comment to explain the level-0 cost calculation.
- **Files modified:** `test/gas/AdvanceGameGas.test.js`
- **Verification:** Re-ran test; all 19 buyers purchased successfully, gas measured at 5,193,019.
- **Committed in:** `cc41e2e` (part of Task 1 commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 - bug in test ETH amount)
**Impact on plan:** Required fix for correctness; all 19 Sybil buyers now successfully purchase tickets. GAS-04 economic model correctly uses the TICKET_MIN_BUYIN_WEI = 0.0025 ETH floor for the conservative lower-bound calculation.

## Issues Encountered

- The RESEARCH.md plan interface specified `eth(0.0025)` for Sybil purchase value, but level-0 ticket price is 0.01 ETH (set in `DegenerusGameStorage.sol` at `uint128 internal price = uint128(0.01 ether)`). TICKET_MIN_BUYIN_WEI is the enforcement floor for purchase calls across all levels; the actual cost at level 0 is the price itself (0.01 ETH for 1 full ticket). This was diagnosed and fixed in the first test run.

## Next Phase Readiness

- GAS-02, GAS-03, GAS-04 verdicts complete; Phase 13 gas report can cite this summary
- Plan 09-03 (GAS-05 payDailyJackpot ceiling + GAS-06 VRF callback) and 09-04 (GAS-07 rational inaction) remain in Phase 9

---
*Phase: 09-advancegame-gas-analysis-and-sybil-bloat*
*Completed: 2026-03-04*
