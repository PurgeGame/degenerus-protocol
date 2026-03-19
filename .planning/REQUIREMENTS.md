# Requirements: Degenerus Protocol v3.1

**Defined:** 2026-03-18
**Core Value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.

## v3.1 Requirements

### Comment Audit

- [x] **CMT-01**: All NatSpec and inline comments in core game contracts (DegenerusGame, GameStorage, DegenerusAdmin) are accurate and warden-ready
- [x] **CMT-02**: All NatSpec and inline comments in game modules batch A (MintModule, DegeneretteModule, WhaleModule, BoonModule, LootboxModule, PayoutUtils, MintStreakUtils) are accurate and warden-ready
- [x] **CMT-03**: All NatSpec and inline comments in game modules batch B (JackpotModule, DecimatorModule, EndgameModule, GameOverModule, AdvanceModule) are accurate and warden-ready
- [x] **CMT-04**: All NatSpec and inline comments in token contracts (BurnieCoin, StakedDegenerusStonk, DegenerusStonk, WrappedWrappedXRP) are accurate and warden-ready
- [ ] **CMT-05**: All NatSpec and inline comments in peripheral contracts (BurnieCoinflip, DegenerusAffiliate, DegenerusDeityPass, DegenerusQuests, DegenerusJackpots, DegenerusVault, DegenerusTraitUtils, DeityBoonViewer, ContractAddresses, Icons32Data) are accurate and warden-ready

### Intent Drift

- [x] **DRIFT-01**: Core game contracts reviewed for vestigial logic, unnecessary restrictions, and intent drift
- [x] **DRIFT-02**: Game modules batch A reviewed for vestigial logic, unnecessary restrictions, and intent drift
- [x] **DRIFT-03**: Game modules batch B reviewed for vestigial logic, unnecessary restrictions, and intent drift
- [x] **DRIFT-04**: Token contracts reviewed for vestigial logic, unnecessary restrictions, and intent drift
- [ ] **DRIFT-05**: Peripheral contracts reviewed for vestigial logic, unnecessary restrictions, and intent drift

### Deliverable

- [ ] **DEL-01**: Consolidated findings list produced with what/why/suggestion per item, categorized by severity

## Deferred (v3.2+)

### Formal Verification

- **FV-01**: Foundry fuzz invariant tests for governance (vote weight conservation, threshold monotonicity)
- **FV-02**: Formal verification of vote counting arithmetic via Halmos
- **FV-03**: Monte Carlo simulation of governance outcomes under various voter distributions

## Out of Scope

| Feature | Reason |
|---------|--------|
| Frontend code | Not in audit scope |
| Off-chain infrastructure | VRF coordinator is external |
| Gas optimization | Already covered in v2.0 |
| Code changes / fixes | Flag-only milestone — fixes are separate |
| v3.0 re-audit | Prior audit verdicts stand; this covers comments + intent only |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| CMT-01 | Phase 31 | Complete |
| CMT-02 | Phase 32 | Complete |
| CMT-03 | Phase 33 | Complete |
| CMT-04 | Phase 34 | Complete |
| CMT-05 | Phase 35 | In Progress (2 of 10 contracts) |
| DRIFT-01 | Phase 31 | Complete |
| DRIFT-02 | Phase 32 | Complete |
| DRIFT-03 | Phase 33 | Complete |
| DRIFT-04 | Phase 34 | Complete |
| DRIFT-05 | Phase 35 | In Progress (2 of 10 contracts) |
| DEL-01 | Phase 36 | Pending |

**Coverage:**
- v3.1 requirements: 11 total
- Mapped to phases: 11
- Unmapped: 0

---
*Requirements defined: 2026-03-18*
*Last updated: 2026-03-19 after Phase 34 completion -- CMT-04 and DRIFT-04 complete*
