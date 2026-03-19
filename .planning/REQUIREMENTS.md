# Requirements: Degenerus Protocol Audit

**Defined:** 2026-03-19
**Core Value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.

## v3.2 Requirements

Requirements for RNG Delta Audit + Comment Re-scan + Governance Fresh Eyes.

### RNG Security (Delta)

- [x] **RNG-01**: Removing rngLocked from coinflip claim paths does not open manipulation windows (carry never enters claimable pool verified)
- [x] **RNG-02**: BAF epoch-based guard is sufficient as sole coinflip claim protection during resolution windows
- [x] **RNG-03**: Persistent decimator claims across rounds do not create RNG-exploitable state
- [x] **RNG-04**: Cross-contract RNG data flow remains safe with all recent changes combined (no new manipulation vectors)

### Comment Correctness (Fresh Scan)

- [x] **CMT-01**: Game module contracts — all NatSpec, inline, and block comments verified (9 modules)
- [x] **CMT-02**: Core game contracts — all comments verified (DegenerusGame, GameStorage, DegenerusAdmin)
- [x] **CMT-03**: Token contracts — all comments verified (BurnieCoin, DegenerusStonk, StakedDegenerusStonk, WrappedWrappedXRP)
- [x] **CMT-04**: Peripheral contracts — all comments verified (BurnieCoinflip, DegenerusVault, DegenerusAffiliate, DegenerusQuests, DegenerusJackpots)
- [x] **CMT-05**: Remaining contracts — all comments verified (DeityPass, TraitUtils, DeityBoonViewer, ContractAddresses, Icons32Data)
- [ ] **CMT-06**: Cross-cutting patterns identified and documented
- [ ] **CMT-07**: Consolidated findings deliverable with severity classification

### VRF Governance (Fresh Eyes)

- [ ] **GOV-01**: VRF swap governance flow audited from fresh perspective — all attack surfaces catalogued
- [ ] **GOV-02**: Governance edge cases and timing attacks re-evaluated against current code
- [ ] **GOV-03**: Cross-contract governance interactions verified (Admin, GameStorage, AdvanceModule, DegenerusStonk)

## Future Requirements

### Deferred (v3.3+)

- **FUZZ-01**: Foundry fuzz invariant tests for governance (vote weight conservation, threshold monotonicity)
- **FUZZ-02**: Formal verification of vote counting arithmetic via Halmos
- **FUZZ-03**: Monte Carlo simulation of governance outcomes under various voter distributions

## Out of Scope

| Feature | Reason |
|---------|--------|
| Frontend code | Not in audit scope |
| Off-chain infrastructure | VRF coordinator is external |
| Gas optimization | Already covered in v2.0, not the focus here |
| Full governance re-audit | v2.1 was comprehensive; v3.2 is a fresh-eyes sanity check only |
| Comment auto-fix | Findings list is the deliverable — protocol team decides fixes |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| RNG-01 | Phase 38 | Complete |
| RNG-02 | Phase 38 | Complete |
| RNG-03 | Phase 38 | Complete |
| RNG-04 | Phase 38 | Complete |
| CMT-01 | Phase 39 | Complete |
| CMT-02 | Phase 40 | Complete |
| CMT-03 | Phase 40 | Complete |
| CMT-04 | Phase 41 | Complete |
| CMT-05 | Phase 41 | Complete |
| CMT-06 | Phase 43 | Pending |
| CMT-07 | Phase 43 | Pending |
| GOV-01 | Phase 42 | Pending |
| GOV-02 | Phase 42 | Pending |
| GOV-03 | Phase 42 | Pending |

**Coverage:**
- v3.2 requirements: 14 total
- Mapped to phases: 14
- Unmapped: 0

---
*Requirements defined: 2026-03-19*
*Last updated: 2026-03-19 after roadmap creation — all requirements mapped to phases*
