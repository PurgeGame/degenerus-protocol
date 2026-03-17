# Requirements: Degenerus Protocol — C4A Audit Prep v2.0

**Defined:** 2026-03-16
**Core Value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.

## v2.0 Requirements

### Delta — sDGNRS/DGNRS Split Audit

- [x] **DELTA-01**: StakedDegenerusStonk reviewed for reentrancy, access control, reserve accounting
- [x] **DELTA-02**: DegenerusStonk wrapper reviewed for ERC20 edge cases, burn delegation, unwrapTo
- [x] **DELTA-03**: Cross-contract interaction between DGNRS↔sDGNRS verified (supply sync, burn-through)
- [x] **DELTA-04**: All game→sDGNRS callsites verified (pool transfers, deposits, burnRemainingPools)
- [x] **DELTA-05**: payCoinflipBountyDgnrs 3-arg gating logic verified
- [x] **DELTA-06**: Degenerette DGNRS reward math (6/7/8 match tiers) verified
- [x] **DELTA-07**: Earlybird→Lootbox pool dump verified (was Reward)
- [x] **DELTA-08**: Pool BPS rebalance impact on all downstream consumers verified

### Correctness — Docs, Comments, Tests

- [x] **CORR-01**: All NatDoc comments match implementation across changed contracts
- [x] **CORR-02**: All 10 audit docs verified against current code (no stale refs)
- [x] **CORR-03**: Test coverage for new/changed functions (sDGNRS, DGNRS, bounty, degenerette)
- [x] **CORR-04**: Fuzz test compilation and correctness for changed contracts

### Novel — Creative Attack Surface

- [x] **NOVEL-01**: Economic attack modeling on new DGNRS liquidity (MEV, sandwich, flash loan)
- [x] **NOVEL-02**: Composition attacks across sDGNRS+DGNRS+game+coinflip interaction chains
- [x] **NOVEL-03**: Griefing vectors (DoS, state bloat, gas limit) on new entry points
- [x] **NOVEL-04**: Edge case enumeration (zero amounts, max uint, dust, rounding)
- [x] **NOVEL-05**: Invariant analysis (supply conservation, backing >= obligations)
- [ ] **NOVEL-07**: Multi-agent adversarial simulation (3+ independent auditors cross-referencing findings)
- [x] **NOVEL-08**: Regression check — diff every prior audit finding against current code
- [x] **NOVEL-09**: Privilege escalation paths (can any non-game address trigger pool drains, burns, deposits?)
- [x] **NOVEL-10**: Oracle/price manipulation via sDGNRS burn timing (stETH rebasing + claimable ETH)
- [x] **NOVEL-11**: Game-over race conditions (burnRemainingPools vs concurrent burns, final sweep timing)
- [x] **NOVEL-12**: DGNRS wrapper as attack amplifier (transferable token enables strategies impossible with soulbound)

### Gas — Dead Code and Optimization

- [ ] **GAS-01**: Remove unreachable checks (guards on variables that can never be zero/overflow)
- [ ] **GAS-02**: Remove dead storage variables and unused state from all contracts
- [ ] **GAS-03**: Remove dead code paths and unreachable branches
- [ ] **GAS-04**: Identify redundant external calls and storage reads that can be cached

## Out of Scope

| Feature | Reason |
|---------|--------|
| Unchanged contract internals | Covered by v1.0-v1.2 audits, reuse results |
| Frontend/UI | Not in C4A audit scope |
| VRF coordinator internals | External Chainlink dependency |
| Gas optimizations that change behavior | Risk of introducing bugs pre-audit |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| DELTA-01 | Phase 19 | Complete (19-01) |
| DELTA-02 | Phase 19 | Complete (19-01) |
| DELTA-03 | Phase 19 | Complete (19-01) |
| DELTA-04 | Phase 19 | Complete |
| DELTA-05 | Phase 19 | Complete |
| DELTA-06 | Phase 19 | Complete |
| DELTA-07 | Phase 19 | Complete |
| DELTA-08 | Phase 19 | Complete |
| CORR-01 | Phase 20 | Complete |
| CORR-02 | Phase 20 | Complete |
| CORR-03 | Phase 20 | Complete |
| CORR-04 | Phase 20 | Complete |
| NOVEL-01 | Phase 21 | Complete |
| NOVEL-02 | Phase 21 | Complete |
| NOVEL-03 | Phase 21 | Complete |
| NOVEL-04 | Phase 21 | Complete |
| NOVEL-05 | Phase 21 | Complete |
| NOVEL-07 | Phase 22 | Pending |
| NOVEL-08 | Phase 22 | Complete |
| NOVEL-09 | Phase 21 | Complete |
| NOVEL-10 | Phase 21 | Complete |
| NOVEL-11 | Phase 21 | Complete |
| NOVEL-12 | Phase 21 | Complete |
| GAS-01 | Phase 23 | Pending |
| GAS-02 | Phase 23 | Pending |
| GAS-03 | Phase 23 | Pending |
| GAS-04 | Phase 23 | Pending |

**Coverage:**
- v2.0 requirements: 27 total
- Mapped to phases: 27
- Unmapped: 0 ✓

---
*Requirements defined: 2026-03-16*
