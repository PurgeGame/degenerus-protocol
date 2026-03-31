# Requirements: Degenerus Protocol — v11.0 BURNIE Endgame Gate

**Defined:** 2026-03-31
**Core Value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.

## v11.0 Requirements

### Removal

- [ ] **REM-01**: 30-day BURNIE ticket purchase ban is fully removed from all levels

### Flag Lifecycle

- [ ] **FLAG-01**: On purchase-phase entry (L10+), compute whether remaining futurePool drip can cover the nextPool gap; if not, set the endgame flag
- [ ] **FLAG-02**: Each subsequent purchase-phase day, if the flag is active, re-check and clear it if drip projection now covers the gap
- [ ] **FLAG-03**: Auto-clear the flag at lastPurchaseDay regardless of projection state
- [ ] **FLAG-04**: Flag is not checked or set during levels 1-9 or outside purchase phase

### Drip Projection

- [ ] **DRIP-01**: Implement geometric series projection: total remaining drip = sum of futurePool * 0.0075 * 0.9925^i for i in 0..daysRemaining-1
- [ ] **DRIP-02**: Compare projected drip total against nextPool deficit (target - current balance) to determine flag state

### Enforcement

- [ ] **ENF-01**: When flag is active, BURNIE ticket purchases revert
- [ ] **ENF-02**: When flag is active, BURNIE lootbox purchases succeed but current-level ticket chance is redirected to far-future tickets
- [ ] **ENF-03**: ETH ticket purchases and ETH lootboxes are unaffected by the flag

### Audit

- [x] **AUD-01**: Delta adversarial audit of all changed functions — 0 open HIGH/MEDIUM/LOW
- [x] **AUD-02**: RNG commitment window re-verification for any changed paths
- [x] **AUD-03**: Gas ceiling analysis for drip projection computation

## Future Requirements

None — targeted contract change.

## Out of Scope

| Feature | Reason |
|---------|--------|
| Frontend changes | Not in audit scope |
| Changing drip rate (0.75%) | Existing parameter, not part of this change |
| BURNIE restrictions during jackpot/play phase | Game can't end once jackpot phase begins |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| REM-01 | Phase 151 | Pending |
| FLAG-01 | Phase 151 | Pending |
| FLAG-02 | Phase 151 | Pending |
| FLAG-03 | Phase 151 | Pending |
| FLAG-04 | Phase 151 | Pending |
| DRIP-01 | Phase 151 | Pending |
| DRIP-02 | Phase 151 | Pending |
| ENF-01 | Phase 151 | Pending |
| ENF-02 | Phase 151 | Pending |
| ENF-03 | Phase 151 | Pending |
| AUD-01 | Phase 152 | Complete |
| AUD-02 | Phase 152 | Complete |
| AUD-03 | Phase 152 | Complete |

**Coverage:**
- v11.0 requirements: 13 total
- Mapped to phases: 13
- Unmapped: 0

---
*Requirements defined: 2026-03-31*
*Last updated: 2026-03-31 after roadmap creation*
