# Requirements: Degenerus Protocol — v3.5 Final Polish

**Defined:** 2026-03-21
**Core Value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.

## v3.5 Requirements

### Comment Correctness

- [x] **CMT-01**: Every NatSpec tag (@param, @return, @dev, @notice) across all 34 contracts matches current code behavior
- [x] **CMT-02**: No stale references to removed features, renamed variables, or changed semantics
- [x] **CMT-03**: Inline comments accurately describe the code they annotate
- [x] **CMT-04**: All findings documented with contract, line ref, and fix recommendation

### Gas Optimization

- [ ] **GAS-01**: All storage variables confirmed alive (read + write in reachable code paths)
- [ ] **GAS-02**: No redundant checks, dead branches, or unreachable code
- [ ] **GAS-03**: Storage packing opportunities identified with estimated gas savings
- [ ] **GAS-04**: All findings documented with contract, line ref, and estimated impact

### Gas Ceiling Analysis

- [ ] **CEIL-01**: advanceGame worst-case gas profiled across every code path (jackpot, transition, daily, gameover)
- [ ] **CEIL-02**: Maximum jackpot payouts per path computed such that no path exceeds 14M gas
- [ ] **CEIL-03**: Ticket minting (purchase) worst-case gas profiled
- [ ] **CEIL-04**: Maximum ticket batch size computed such that purchase never exceeds 14M gas
- [ ] **CEIL-05**: Current headroom documented (how far below 14M each worst-case path sits today)

### Consolidated Findings

- [ ] **FIND-01**: All v3.5 comment, gas, and ceiling findings in a master table sorted by severity
- [ ] **FIND-02**: Fix recommendations actionable (one-line description of what to change)

## Out of Scope

| Feature | Reason |
|---------|--------|
| Code changes / fixes | Flag-only — protocol team decides what to fix |
| Test coverage | Tests are not in audit scope |
| Formal verification | Out of scope for all milestones |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| CMT-01 | Phase 54 | Complete |
| CMT-02 | Phase 54 | Complete |
| CMT-03 | Phase 54 | Complete |
| CMT-04 | Phase 54 | Complete |
| GAS-01 | Phase 55 | Pending |
| GAS-02 | Phase 55 | Pending |
| GAS-03 | Phase 55 | Pending |
| GAS-04 | Phase 55 | Pending |
| CEIL-01 | Phase 57 | Pending |
| CEIL-02 | Phase 57 | Pending |
| CEIL-03 | Phase 57 | Pending |
| CEIL-04 | Phase 57 | Pending |
| CEIL-05 | Phase 57 | Pending |
| FIND-01 | Phase 58 | Pending |
| FIND-02 | Phase 58 | Pending |

**Coverage:**
- v3.5 requirements: 15 total
- Mapped to phases: 15
- Unmapped: 0

---
*Requirements defined: 2026-03-21*
*Last updated: 2026-03-21 after initial definition*
