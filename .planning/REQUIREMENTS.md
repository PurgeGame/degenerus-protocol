# Requirements: Degenerus Protocol — v3.4 New Feature Audit

**Defined:** 2026-03-21
**Core Value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.

## v3.4 Requirements

### Skim Security

- [ ] **SKIM-01**: Overshoot surcharge formula is monotonic and capped at 35%
- [ ] **SKIM-02**: Ratio adjustment is bounded ±400 bps and drives bps to 0 (not negative)
- [ ] **SKIM-03**: Additive random consumes bits [0:63] only; variance rolls use [64:191] and [192:255] with no overlap
- [ ] **SKIM-04**: Triangular variance cannot underflow take (subtraction is safe)
- [ ] **SKIM-05**: Take cap at 80% of nextPool holds under all input combinations
- [x] **SKIM-06**: ETH conservation: nextPool + futurePool + yieldAccumulator is invariant
- [x] **SKIM-07**: Insurance skim is always exactly 1% of nextPoolBefore

### Skim Economic Analysis

- [ ] **ECON-01**: Overshoot surcharge correctly accelerates futurepool growth during fast levels
- [ ] **ECON-02**: Stall escalation still functions (no regression from growth adjustment removal)
- [ ] **ECON-03**: Level 1 (lastPool=0) is safe — overshoot dormant, no division by zero

### Redemption Lootbox Security

- [ ] **REDM-01**: 50/50 split correctly routes half to direct ETH, half to lootbox
- [ ] **REDM-02**: GameOver burns bypass lootbox (pure ETH/stETH, no BURNIE payout)
- [ ] **REDM-03**: 160 ETH daily cap per wallet enforced correctly
- [ ] **REDM-04**: Activity score snapshot at submission is immutable through resolution
- [ ] **REDM-05**: PendingRedemption slot packing is correct (uint96+uint96+uint48+uint16=256)
- [ ] **REDM-06**: Lootbox reclassification has no ETH transfer (internal accounting only)
- [ ] **REDM-07**: Cross-contract call from sDGNRS → Game → LootboxModule has correct access control

### Invariant Testing

- [ ] **INV-01**: Fuzz invariant: skim conservation holds across random inputs
- [ ] **INV-02**: Fuzz invariant: take never exceeds 80% of nextPool
- [ ] **INV-03**: Fuzz invariant: redemption lootbox split sums to total rolled ETH

### Consolidated Findings

- [ ] **FIND-01**: All v3.4 findings consolidated with severity, contract, line ref, and recommendation
- [ ] **FIND-02**: Outstanding v3.2 LOW/INFO findings included in master list for completeness
- [ ] **FIND-03**: Master findings table sorted by severity for manual triage before C4A

## Out of Scope

| Feature | Reason |
|---------|--------|
| Fixing v3.2 LOW/INFO findings | Doc-only issues; flagged for manual review, not auto-fixed |
| Frontend code | Not in audit scope |
| _nextToFutureBps U-curve | Unchanged — audited in v3.0 |
| Insurance skim logic | Unchanged — audited in v3.0 |
| Gas optimization | Correctness-first; gas is secondary for C4A |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| SKIM-01 | Phase 50 | Pending |
| SKIM-02 | Phase 50 | Pending |
| SKIM-03 | Phase 50 | Pending |
| SKIM-04 | Phase 50 | Pending |
| SKIM-05 | Phase 50 | Pending |
| SKIM-06 | Phase 50 | Complete |
| SKIM-07 | Phase 50 | Complete |
| ECON-01 | Phase 50 | Pending |
| ECON-02 | Phase 50 | Pending |
| ECON-03 | Phase 50 | Pending |
| REDM-01 | Phase 51 | Pending |
| REDM-02 | Phase 51 | Pending |
| REDM-03 | Phase 51 | Pending |
| REDM-04 | Phase 51 | Pending |
| REDM-05 | Phase 51 | Pending |
| REDM-06 | Phase 51 | Pending |
| REDM-07 | Phase 51 | Pending |
| INV-01 | Phase 52 | Pending |
| INV-02 | Phase 52 | Pending |
| INV-03 | Phase 52 | Pending |
| FIND-01 | Phase 53 | Pending |
| FIND-02 | Phase 53 | Pending |
| FIND-03 | Phase 53 | Pending |

**Coverage:**
- v3.4 requirements: 23 total
- Mapped to phases: 23
- Unmapped: 0

---
*Requirements defined: 2026-03-21*
*Last updated: 2026-03-21 after roadmap creation (traceability populated)*
