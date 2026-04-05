# Requirements: v22.0 BAF Simplification Delta Audit

**Defined:** 2026-04-05
**Core Value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.

## v22.0 Requirements

Requirements for BAF Simplification Delta Audit. Each maps to roadmap phases.

### ETH Flow Verification

- [ ] **FLOW-01**: BAF claimable path produces identical `claimableDelta` for non-auto-rebuy winners
- [ ] **FLOW-02**: BAF auto-rebuy path produces identical ticket counts and pool state post-`_setPrizePools`
- [ ] **FLOW-03**: BAF lootbox ticket path produces identical ticket entries (stays in futurePool implicitly)
- [ ] **FLOW-04**: BAF whale pass path produces identical `whalePassClaims` and dust remainder
- [ ] **FLOW-05**: BAF refund path — unused pool ETH stays in futurePool correctly

### Rebuy Delta Removal

- [ ] **DELTA-01**: Auto-rebuy storage write during BAF is safely overwritten by `_setPrizePools` at function end
- [ ] **DELTA-02**: No other futurePool storage writes exist in the BAF/decimator self-call chain that depended on the delta

### Event + Layout

- [ ] **EVT-01**: Unconditional `RewardJackpotsSettled` emit has no downstream consumer that depends on conditional behavior
- [ ] **LAYOUT-01**: Storage layout identical across all changed contracts via `forge inspect`

### Regression

- [ ] **TEST-01**: Foundry test suite green with zero new failures
- [ ] **TEST-02**: Hardhat test suite green with zero new failures

## Future Requirements

None — delta audit is self-contained.

## Out of Scope

| Feature | Reason |
|---------|--------|
| Transient guard refactor | Gas analysis showed net negative savings; abandoned |
| MintModule self-call optimization | Separate scope, not part of BAF simplification |
| Auto-rebuy nextPool write loss (pre-existing) | Pre-existing issue unchanged by this commit |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| FLOW-01 | Phase 190 | Pending |
| FLOW-02 | Phase 190 | Pending |
| FLOW-03 | Phase 190 | Pending |
| FLOW-04 | Phase 190 | Pending |
| FLOW-05 | Phase 190 | Pending |
| DELTA-01 | Phase 190 | Pending |
| DELTA-02 | Phase 190 | Pending |
| EVT-01 | Phase 190 | Pending |
| LAYOUT-01 | Phase 191 | Pending |
| TEST-01 | Phase 191 | Pending |
| TEST-02 | Phase 191 | Pending |

**Coverage:**
- v22.0 requirements: 11 total
- Mapped to phases: 11
- Unmapped: 0 ✓

---
*Requirements defined: 2026-04-05*
*Last updated: 2026-04-05 after initial definition*
