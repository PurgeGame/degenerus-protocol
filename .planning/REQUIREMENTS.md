# Requirements: Degenerus Protocol Audit — v4.3

**Defined:** 2026-03-25
**Core Value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.

## v4.3 Requirements

Requirements for milestone v4.3: prizePoolsPacked Batching Optimization.

### Callsite Audit

- [ ] **CALL-01**: Every callsite of `_processAutoRebuy` is inventoried with current prize pool write behavior documented
- [ ] **CALL-02**: Every callsite of `_setFuturePrizePool` and `_setNextPrizePool` within auto-rebuy paths is mapped

### Implementation

- [ ] **BATCH-01**: `_processAutoRebuy` returns pool deltas instead of writing `prizePoolsPacked` directly
- [ ] **BATCH-02**: `_processDailyEth` accumulates deltas across the winner loop and performs a single batched write
- [ ] **BATCH-03**: All non-daily-ETH callers of `_processAutoRebuy` updated to handle return values and write accumulated deltas

### Verification

- [ ] **EQUIV-01**: Formal proof that batched writes produce identical final `prizePoolsPacked` state as sequential writes
- [ ] **EQUIV-02**: All existing Hardhat tests pass with zero regressions
- [ ] **EQUIV-03**: All existing Foundry tests pass with zero regressions
- [ ] **GAS-01**: Gas profiling confirms ~1.6M savings on the daily ETH jackpot worst-case path
- [ ] **GAS-02**: Gas ceiling re-profiled — all 3 stages still SAFE with updated headroom documented

### Comments

- [ ] **CMT-01**: NatSpec and inline comments accurate for all modified functions

## Out of Scope

| Feature | Reason |
|---------|--------|
| Non-prizePoolsPacked SSTORE optimizations | Warm SLOAD savings are marginal (0.2-0.5%); v4.2 Phase 96 rejected candidates 3-5 |
| Refactoring _processAutoRebuy callers beyond batching | Scope limited to pool delta return value pattern |
| New jackpot types or winner processing changes | This is optimization only, not feature work |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| CALL-01 | TBD | Pending |
| CALL-02 | TBD | Pending |
| BATCH-01 | TBD | Pending |
| BATCH-02 | TBD | Pending |
| BATCH-03 | TBD | Pending |
| EQUIV-01 | TBD | Pending |
| EQUIV-02 | TBD | Pending |
| EQUIV-03 | TBD | Pending |
| GAS-01 | TBD | Pending |
| GAS-02 | TBD | Pending |
| CMT-01 | TBD | Pending |

**Coverage:**
- v4.3 requirements: 11 total
- Mapped to phases: 0
- Unmapped: 11

---
*Requirements defined: 2026-03-25*
