# Requirements: Degenerus Protocol Audit — v4.4

**Defined:** 2026-03-25
**Core Value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.

## v4.4 Requirements

Requirements for milestone v4.4: BAF Cache-Overwrite Bug Fix + Pattern Scan.

### Bug Fix

- [ ] **BAF-01**: `runRewardJackpots` reconciles auto-rebuy's `futurePrizePool` storage writes before final write-back (Option A delta reconciliation)
- [ ] **BAF-02**: Arithmetic proof that the delta reconciliation preserves both `runRewardJackpots`' adjustments and auto-rebuy contributions under all execution paths

### Pattern Scan

- [ ] **SCAN-01**: Every function across all contracts that caches a storage variable locally, calls nested functions that write to the same slot, then writes back the local is inventoried
- [ ] **SCAN-02**: Each instance found is classified as VULNERABLE (stale overwrite possible) or SAFE (with reasoning)
- [ ] **SCAN-03**: Any additional vulnerable instances are fixed or documented with fix recommendations

### Verification

- [ ] **TEST-01**: Foundry test proving the BAF fix: auto-rebuy contributions survive the `runRewardJackpots` write-back
- [ ] **TEST-02**: All existing Hardhat tests pass with zero regressions
- [ ] **TEST-03**: All existing Foundry tests pass with zero regressions

### Comments

- [ ] **CMT-01**: NatSpec and inline comments accurate for the fix and any other modified code

## Out of Scope

| Feature | Reason |
|---------|--------|
| Option B structural refactor | Option A is sufficient — 3 lines vs 5+ location changes |
| Refactoring other modules' auto-rebuy patterns | Only fix confirmed vulnerable instances |
| Gas optimization of the fix | Delta reconciliation adds ~200 gas (1 SLOAD + arithmetic), negligible |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| BAF-01 | TBD | Pending |
| BAF-02 | TBD | Pending |
| SCAN-01 | TBD | Pending |
| SCAN-02 | TBD | Pending |
| SCAN-03 | TBD | Pending |
| TEST-01 | TBD | Pending |
| TEST-02 | TBD | Pending |
| TEST-03 | TBD | Pending |
| CMT-01 | TBD | Pending |

**Coverage:**
- v4.4 requirements: 9 total
- Mapped to phases: 0
- Unmapped: 9

---
*Requirements defined: 2026-03-25*
