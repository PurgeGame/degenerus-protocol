# Requirements: Degenerus Protocol — Full Audit (Post-v5.0 Delta + Fresh RNG)

**Defined:** 2026-04-10
**Core Value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.

## v25.0 Requirements

Requirements for this milestone. Each maps to roadmap phases.

### Delta Extraction

- [x] **DELTA-01**: Function-level changelog of all changed/new/deleted functions from v5.0 (phase 103) through v24.1 (phase 212)
- [x] **DELTA-02**: Contract-by-contract change classification (NEW / MODIFIED / DELETED / UNCHANGED)
- [ ] **DELTA-03**: Interaction map between changed functions identifying cross-module call chains

### Adversarial Audit

- [ ] **ADV-01**: Every changed/new function audited for reentrancy, access control, integer overflow, and state corruption
- [ ] **ADV-02**: Storage layout verified across all DegenerusGameStorage inheritors via forge inspect
- [ ] **ADV-03**: Cross-function attack chain analysis for composition bugs across the combined v6.0-v24.1 delta
- [ ] **ADV-04**: Call graph audit of all changed external/public entry points

### RNG (Fresh Eyes)

- [ ] **RNG-01**: VRF request/fulfillment lifecycle traced end-to-end with no reliance on prior audit conclusions
- [ ] **RNG-02**: Backward trace from every RNG consumer proving word was unknown at input commitment time
- [ ] **RNG-03**: Controllable-state window analysis between VRF request and fulfillment for every path
- [ ] **RNG-04**: Word derivation verification — every keccak/shift/mask producing a game outcome traced to its VRF source
- [ ] **RNG-05**: rngLocked mutual exclusion verification across all state-changing paths

### Pool & ETH Accounting

- [ ] **POOL-01**: ETH conservation proof across the restructured pool architecture (consolidated pools, write batching, two-call split)
- [ ] **POOL-02**: Pool mutation audit of all SSTORE sites touching prize pool / claimable pool / future pool
- [ ] **POOL-03**: Cross-module flow verification for jackpot payouts, redemption, and sweep paths

### Findings Consolidation

- [ ] **FIND-01**: All findings severity-classified (CRITICAL / HIGH / MEDIUM / LOW / INFO)
- [ ] **FIND-02**: KNOWN-ISSUES.md updated with any new entries
- [ ] **FIND-03**: Regression check against all prior findings (v3.3 through v24.1)

## Future Requirements

None — this is a terminal audit milestone.

## Out of Scope

| Feature | Reason |
|---------|--------|
| Test coverage gaps | User explicitly excluded test work from this milestone |
| Frontend code | Not in audit scope |
| Off-chain infrastructure | VRF coordinator is external |
| Gas optimization | Separate concern; covered in prior milestones |
| Unchanged functions (pre-v6.0) | Covered by v5.0 Ultimate Adversarial Audit |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| DELTA-01 | 213 | Complete |
| DELTA-02 | 213 | Complete |
| DELTA-03 | 213 | Pending |
| ADV-01 | 214 | Pending |
| ADV-02 | 214 | Pending |
| ADV-03 | 214 | Pending |
| ADV-04 | 214 | Pending |
| RNG-01 | 215 | Pending |
| RNG-02 | 215 | Pending |
| RNG-03 | 215 | Pending |
| RNG-04 | 215 | Pending |
| RNG-05 | 215 | Pending |
| POOL-01 | 216 | Pending |
| POOL-02 | 216 | Pending |
| POOL-03 | 216 | Pending |
| FIND-01 | 217 | Pending |
| FIND-02 | 217 | Pending |
| FIND-03 | 217 | Pending |

**Coverage:**
- v25.0 requirements: 18 total
- Mapped to phases: 18
- Unmapped: 0

---
*Requirements defined: 2026-04-10*
*Last updated: 2026-04-10 — traceability added after roadmap creation*
