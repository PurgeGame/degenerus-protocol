# Requirements: Degenerus Protocol — v8.0 Pre-Audit Hardening

**Defined:** 2026-03-26
**Core Value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.

## v8.0 Requirements

Requirements for pre-audit hardening. Each maps to roadmap phases.

### Bot Race Pre-emption

- [x] **BOT-01**: Slither analysis run on all production contracts with findings triaged (fix or document)
- [x] **BOT-02**: 4naly3er analysis run on all production contracts with findings triaged
- [ ] **BOT-03**: All bot-detectable findings either fixed in code or added to KNOWN-ISSUES.md
- [ ] **BOT-04**: Known issues file comprehensive enough to invalidate automated warden submissions

### ERC-20 Compliance

- [x] **ERC-01**: DGNRS (DegenerusStonk) — ERC-20 interface compliance verified (transfer, approve, transferFrom, allowance edge cases)
- [x] **ERC-02**: sDGNRS (StakedDegenerusStonk) — soulbound transfer restrictions verified, ERC-20 view compliance
- [x] **ERC-03**: BURNIE (BurnieCoin) — ERC-20 interface compliance verified
- [x] **ERC-04**: GNRUS — soulbound transfer restrictions verified, ERC-20 view compliance

### Event Correctness

- [x] **EVT-01**: All state-changing functions emit appropriate events
- [x] **EVT-02**: Event parameter values match actual state changes (no stale/wrong values)
- [x] **EVT-03**: No missing events for off-chain indexer-critical state transitions

### Comment Re-scan

- [x] **CMT-01**: NatSpec accuracy verified across all contracts changed since v3.5
- [x] **CMT-02**: Inline comments match current code behavior (no drift from v6.0/v7.0 changes)
- [x] **CMT-03**: No stale references to removed/renamed functions, variables, or constants

## Future Requirements

None — this is the final pre-audit hardening pass.

## Out of Scope

| Feature | Reason |
|---------|--------|
| Gas optimization | Already covered in v3.3/v3.5/v4.2/v6.0 — diminishing returns |
| Formal verification expansion | Deferred items tracked in ROADMAP.md |
| Frontend code | Not in audit scope |
| Deployment script audit | Self-auditing — wrong addresses = nothing works |
| Non-financial-impact findings | Will be scoped out in C4A contest README |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| BOT-01 | Phase 130 | Complete |
| BOT-02 | Phase 130 | Complete |
| BOT-03 | Phase 134 | Pending |
| BOT-04 | Phase 134 | Pending |
| ERC-01 | Phase 131 | Complete |
| ERC-02 | Phase 131 | Complete |
| ERC-03 | Phase 131 | Complete |
| ERC-04 | Phase 131 | Complete |
| EVT-01 | Phase 132 | Complete |
| EVT-02 | Phase 132 | Complete |
| EVT-03 | Phase 132 | Complete |
| CMT-01 | Phase 133 | Complete |
| CMT-02 | Phase 133 | Complete |
| CMT-03 | Phase 133 | Complete |

**Coverage:**
- v8.0 requirements: 14 total
- Mapped to phases: 14
- Unmapped: 0

---
*Requirements defined: 2026-03-26*
*Last updated: 2026-03-26 after roadmap creation*
