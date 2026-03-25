# Requirements: Degenerus Protocol Audit — v4.2

**Defined:** 2026-03-24
**Core Value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.

## v4.2 Requirements

Requirements for milestone v4.2: Daily Jackpot Chunk Removal + Gas Optimization.

### Delta Verification

- [ ] **DELTA-01**: All Hardhat tests pass with zero regressions after chunk removal
- [ ] **DELTA-02**: Zero remaining references to removed symbols in Solidity code (dailyEthBucketCursor, dailyEthWinnerCursor, _skipEntropyToBucket, _winnerUnits, DAILY_JACKPOT_UNITS_SAFE, DAILY_JACKPOT_UNITS_AUTOREBUY)
- [x] **DELTA-03**: Behavioral equivalence proven — _processDailyEthChunk produces identical payout distribution and entropy chain as before (same winners, same amounts, same order)
- [ ] **DELTA-04**: All Foundry tests pass (invariant + fuzz + integration)

### Gas Ceiling

- [x] **CEIL-01**: Worst-case gas for _processDailyEthChunk profiled (321 winners, all auto-rebuy, 4 populated buckets)
- [x] **CEIL-02**: Worst-case gas for payDailyJackpot profiled (Phase 0 + Phase 1 combined, final physical day)
- [x] **CEIL-03**: All profiled paths SAFE under 14M gas ceiling with headroom documented

### Gas Optimization

- [x] **GOPT-01**: Daily jackpot code path audited for unnecessary SLOADs
- [x] **GOPT-02**: Loop bodies audited for redundant computation that can be hoisted
- [ ] **GOPT-03**: Any identified optimizations implemented and verified

### Comments

- [ ] **CMT-01**: NatSpec and inline comments accurate for all modified functions

## Out of Scope

| Feature | Reason |
|---------|--------|
| Non-daily-jackpot gas optimization | Separate milestone; v3.5 already covered full gas sweep |
| New feature implementation | This is verification + optimization only |
| Governance invariant tests | Deferred backlog item, unrelated to daily jackpot |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| DELTA-01 | Phase 95 | Partial — needs verification |
| DELTA-02 | Phase 95 | Partial — needs verification |
| DELTA-03 | Phase 95 | Pending — Plan 03 not executed |
| DELTA-04 | Phase 95 | Partial — needs verification |
| CEIL-01 | Phase 96 | Complete |
| CEIL-02 | Phase 96 | Complete |
| CEIL-03 | Phase 96 | Complete |
| GOPT-01 | Phase 96 | Complete |
| GOPT-02 | Phase 96 | Complete |
| GOPT-03 | Phase 96 | Pending |
| CMT-01 | Phase 97 | Pending |

**Coverage:**
- v4.2 requirements: 11 total
- Mapped to phases: 11
- Unmapped: 0

---
*Requirements defined: 2026-03-24*
*Last updated: 2026-03-24 after gap closure planning (audit reset partial requirements)*
