# Requirements: Degenerus Protocol — v1.2 RNG Security Audit

**Defined:** 2026-03-14
**Core Value:** Players can purchase tickets at any time — no downtime during RNG processing or jackpot payouts

## v1.2 Requirements

Requirements for RNG security audit. Each maps to roadmap phases.

### RNG Variable Inventory

- [x] **RVAR-01**: Every storage variable that holds a VRF word or derived entropy is catalogued with slot, type, and lifecycle
- [x] **RVAR-02**: Every storage variable that influences RNG outcome selection (bucket composition, ticket counts, queue indices) is catalogued
- [ ] **RVAR-03**: Data flow diagram from VRF callback → `rngWordCurrent` / `lootboxRngWordByIndex` → every downstream consumer
- [x] **RVAR-04**: `lastLootboxRngWord` and `midDayTicketRngPending` fully traced — who writes, who reads, when

### RNG Function Inventory

- [x] **RFN-01**: Every function that reads or writes RNG state is catalogued with access pattern (read/write/gate)
- [x] **RFN-02**: Every external/public entry point that can modify RNG-dependent state is identified
- [ ] **RFN-03**: Call graph from each external entry point to RNG state mutations
- [x] **RFN-04**: Guard analysis — which functions check `rngLockedFlag`, `prizePoolFrozen`, or other RNG-gating conditions

### Delta Verification

- [ ] **DELTA-01**: All 8 attack scenarios from v1.0 audit re-verified against current contract code
- [ ] **DELTA-02**: Every changed line in the 8 modified contract files assessed for RNG impact
- [ ] **DELTA-03**: New attack surfaces from `lastLootboxRngWord`, `midDayTicketRngPending`, and coinflip lock changes identified and analyzed
- [ ] **DELTA-04**: Prior FIX-1 (`claimDecimatorJackpot` freeze guard) confirmed still present and correct

### Manipulation Window Analysis

- [ ] **WINDOW-01**: For each RNG consumption point, complete enumeration of state that can change between VRF callback and consumption
- [ ] **WINDOW-02**: Adversarial timeline for block builder + VRF front-running covering both daily and mid-day paths
- [ ] **WINDOW-03**: Inter-block manipulation windows — what can change between `advanceGame` calls during the 5-day jackpot sequence
- [ ] **WINDOW-04**: Verdict table: each manipulation window rated (BLOCKED / SAFE BY DESIGN / EXPLOITABLE) with evidence

### Ticket Creation & Mid-Day RNG

- [ ] **TICKET-01**: Full trace of ticket creation → buffer assignment → trait assignment with entropy source at each step
- [ ] **TICKET-02**: Mid-day `requestLootboxRng` → buffer swap → `processTicketBatch` flow verified for manipulation resistance
- [ ] **TICKET-03**: Verify no trait/outcome can be influenced when `lastLootboxRngWord` value is known (e.g., from prior block)
- [ ] **TICKET-04**: Coinflip lock timing verified — `_coinflipLockedDuringTransition` windows align with RNG-sensitive periods

## Future Requirements

None — audit milestone produces analysis documents, not code.

## Out of Scope

| Feature | Reason |
|---------|--------|
| Affiliate RNG selection | User-specified exclusion — non-critical RNG path |
| Gas optimization | Separate effort, not security-relevant |
| Frontend changes | Contract-level analysis only |
| Code fixes | This milestone produces audit findings; fixes are a separate milestone |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| RVAR-01 | Phase 12 | Complete |
| RVAR-02 | Phase 12 | Complete |
| RVAR-03 | Phase 12 | Pending |
| RVAR-04 | Phase 12 | Complete |
| RFN-01 | Phase 12 | Complete |
| RFN-02 | Phase 12 | Complete |
| RFN-03 | Phase 12 | Pending |
| RFN-04 | Phase 12 | Complete |
| DELTA-01 | Phase 13 | Pending |
| DELTA-02 | Phase 13 | Pending |
| DELTA-03 | Phase 13 | Pending |
| DELTA-04 | Phase 13 | Pending |
| WINDOW-01 | Phase 14 | Pending |
| WINDOW-02 | Phase 14 | Pending |
| WINDOW-03 | Phase 14 | Pending |
| WINDOW-04 | Phase 14 | Pending |
| TICKET-01 | Phase 15 | Pending |
| TICKET-02 | Phase 15 | Pending |
| TICKET-03 | Phase 15 | Pending |
| TICKET-04 | Phase 15 | Pending |

**Coverage:**
- v1.2 requirements: 20 total
- Mapped to phases: 20
- Unmapped: 0

---
*Requirements defined: 2026-03-14*
*Last updated: 2026-03-14 after roadmap creation*
