# Requirements: v21.0 Day-Index Clock Migration

**Defined:** 2026-04-05
**Core Value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.

## v21.0 Requirements

Requirements for replacing timestamp-based `levelStartTime` with day-index `purchaseStartDay`.

### Clock Migration

- [ ] **CLK-01**: Replace `levelStartTime` constructor init with `purchaseStartDay = GameTimeLib.currentDayIndex()`
- [ ] **CLK-02**: `_isDistressMode` uses day-based arithmetic with 6-hour precision preserved
- [ ] **CLK-03**: `_handleGameOverPath` uses day-based liveness check (no timestamp params)
- [ ] **CLK-04**: Future take curve (`_nextToFutureBps`) thresholds convert from seconds to days
- [ ] **CLK-05**: Gap day extension uses `purchaseStartDay += gapCount` (not timestamp)
- [ ] **CLK-06**: `_evaluateGameOverAndTarget` uses day-based days-remaining calculation
- [ ] **CLK-07**: `_terminalDecDaysRemaining` in DecimatorModule uses day-based arithmetic
- [ ] **CLK-08**: Dead `levelStartTime = ts` write at jackpot-phase entry removed

### Storage Repack

- [ ] **STG-01**: `levelStartTime` removed from slot 0 declaration
- [ ] **STG-02**: `purchaseStartDay` moved from slot 1 into slot 0 [0:6]
- [ ] **STG-03**: Slot 1 gap closed after `purchaseStartDay` removal
- [ ] **STG-04**: Storage layout identical across all 10 delegatecall modules (verified via `forge inspect`)

### Delta Audit

- [x] **DELTA-01**: Behavioral equivalence verified — death clock, future take, distress mode produce same outcomes for all level transition paths
- [x] **DELTA-02**: No storage accounting gaps introduced
- [x] **DELTA-03**: Test suites green (Foundry + Hardhat, zero unexpected regressions)
- [x] **DELTA-04**: All modules compile under 24KB

## Future Requirements

None — this is a scoped mechanical migration.

## Out of Scope

| Feature | Reason |
|---------|--------|
| Changing distress mode precision beyond 6-hour | Existing behavior preserved intentionally |
| Modifying death clock day counts (120 days, DEPLOY_IDLE_TIMEOUT_DAYS) | Constants unchanged, only arithmetic method changes |
| Changing future take curve BPS values | Only converting thresholds from seconds to days |
| purchaseStartDay semantic change | Clock still resets at level transitions; shift from jackpot-phase to purchase-phase entry is the only behavioral change |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| CLK-01 | 188 | Pending |
| CLK-02 | 188 | Pending |
| CLK-03 | 188 | Pending |
| CLK-04 | 188 | Pending |
| CLK-05 | 188 | Pending |
| CLK-06 | 188 | Pending |
| CLK-07 | 188 | Pending |
| CLK-08 | 188 | Pending |
| STG-01 | 188 | Pending |
| STG-02 | 188 | Pending |
| STG-03 | 188 | Pending |
| STG-04 | 188 | Pending |
| DELTA-01 | 189 | Complete |
| DELTA-02 | 189 | Complete |
| DELTA-03 | 189 | Complete |
| DELTA-04 | 189 | Complete |

**Coverage:**
- v21.0 requirements: 16 total
- Mapped to phases: 16
- Unmapped: 0

---
*Requirements defined: 2026-04-05*
*Last updated: 2026-04-05 after roadmap creation*
