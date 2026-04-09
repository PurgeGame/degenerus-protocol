# Requirements: Degenerus Protocol Audit — v24.0 Gameover Flow

**Defined:** 2026-04-09
**Core Value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.

## v24.0 Requirements

Requirements for gameover flow audit and fix. Each maps to roadmap phases.

### Drain Fix

- [ ] **DFIX-01**: `handleGameOverDrain` reverts (not returns) if funds exist but `rngWordByDay[day] == 0`
- [ ] **DFIX-02**: Deity pass refunds execute exactly once per gameover
- [ ] **DFIX-03**: `burnAtGameOver` calls execute exactly once per gameover
- [ ] **DFIX-04**: `gameOver`/`gameOverTime` latch exactly once per gameover
- [ ] **DFIX-05**: All pool zeroing executes exactly once per gameover

### Trigger Audit

- [x] **TRIG-01**: Liveness guard conditions verified (365d L0, 120d L1+, safety abort)
- [x] **TRIG-02**: `_gameOverEntropy` three paths verified (VRF ready, fallback after 3d, pending)
- [x] **TRIG-03**: RNG word lifecycle from request through storage to consumption verified

### Drain Audit

- [x] **DRNA-01**: Fund split correctness (10% decimator / 90% terminal jackpot)
- [x] **DRNA-02**: Deity pass refund math verified (20 ETH/pass, FIFO, budget-capped)
- [x] **DRNA-03**: `claimablePool` accounting through entire drain is correct
- [x] **DRNA-04**: Remainder sweep to vault handles all edge cases

### Sweep Audit

- [x] **SWEP-01**: 30-day delay enforcement correct and non-manipulable
- [x] **SWEP-02**: `claimablePool` forfeiture and fund split (33/33/34) verified
- [x] **SWEP-03**: stETH-first transfer preference and hard-revert behavior verified
- [x] **SWEP-04**: VRF shutdown and LINK recovery verified

### Interaction Audit

- [ ] **IXNR-01**: Claims window correct (allowed between drain and sweep, blocked after `finalSwept`)
- [ ] **IXNR-02**: Post-gameover auto-rebuy bypass in `_addClaimableEth` verified
- [ ] **IXNR-03**: Post-gameover redemption deterministic payout path verified
- [ ] **IXNR-04**: All purchase/mint paths blocked by `gameOver` check verified
- [ ] **IXNR-05**: `gameOverPossible` flag lifecycle verified

### Delta Audit

- [ ] **DLTA-01**: Restructured `handleGameOverDrain` is behaviorally equivalent (except revert vs return)
- [ ] **DLTA-02**: No test suite regressions

## Out of Scope

| Feature | Reason |
|---------|--------|
| Normal-path advanceGame audit | Covered exhaustively in v15.0-v22.0 |
| Token burn mechanics | burnAtGameOver calls audited, not the burn logic itself (covered in v3.3) |
| VRF commitment window | Covered in v3.8; only gameover-specific RNG paths in scope |
| Gas optimization | Focus is correctness, not gas savings |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| DFIX-01 | Phase 203 | Pending |
| DFIX-02 | Phase 203 | Pending |
| DFIX-03 | Phase 203 | Pending |
| DFIX-04 | Phase 203 | Pending |
| DFIX-05 | Phase 203 | Pending |
| TRIG-01 | Phase 204 | Complete |
| TRIG-02 | Phase 204 | Complete |
| TRIG-03 | Phase 204 | Complete |
| DRNA-01 | Phase 204 | Complete |
| DRNA-02 | Phase 204 | Complete |
| DRNA-03 | Phase 204 | Complete |
| DRNA-04 | Phase 204 | Complete |
| SWEP-01 | Phase 205 | Complete |
| SWEP-02 | Phase 205 | Complete |
| SWEP-03 | Phase 205 | Complete |
| SWEP-04 | Phase 205 | Complete |
| IXNR-01 | Phase 205 | Pending |
| IXNR-02 | Phase 205 | Pending |
| IXNR-03 | Phase 205 | Pending |
| IXNR-04 | Phase 205 | Pending |
| IXNR-05 | Phase 205 | Pending |
| DLTA-01 | Phase 206 | Pending |
| DLTA-02 | Phase 206 | Pending |

**Coverage:**
- v24.0 requirements: 23 total
- Mapped to phases: 23
- Unmapped: 0

---
*Requirements defined: 2026-04-09*
*Last updated: 2026-04-09 after roadmap creation*
