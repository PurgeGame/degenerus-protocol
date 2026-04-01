# Requirements: Degenerus Protocol — v12.0 Level Quests

**Defined:** 2026-03-31
**Core Value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.

## v12.0 Requirements

### Eligibility Design

- [x] **ELIG-01**: Define storage layout for level quest eligibility check (levelStreak >= 5 OR any active pass) AND (ETH mint >= 4 units this level)
- [x] **ELIG-02**: Specify how eligibility is evaluated — which existing storage reads are needed, gas cost of the eligibility check

### Quest Mechanics Design

- [x] **MECH-01**: Define global level quest roll mechanism — when during advanceGame level transition, which VRF entropy source, how quest type + target are stored
- [x] **MECH-02**: Specify 10x target values for all 8 quest types with edge case analysis (e.g., 10x ETH mint price capped? Decimator availability across level duration?)
- [x] **MECH-03**: Define level quest progress tracking storage — per-player state, version invalidation at level boundary, completion mask
- [x] **MECH-04**: Specify level quest completion flow — how completion triggers 800 BURNIE creditFlip, once-per-level guard

### Storage Design

- [x] **STOR-01**: Design storage layout for level quest state (global quest type/target per level, per-player progress/completion)
- [x] **STOR-02**: Assess storage slot impact — new slots needed, packing opportunities, SLOAD/SSTORE budget

### Integration Design

- [x] **INTG-01**: Map all contract touchpoints — which contracts need modification, which interfaces change
- [x] **INTG-02**: Identify all handleX() call sites in DegenerusQuests.sol that need level quest progress tracking added

### Economic Analysis

- [ ] **ECON-01**: Model BURNIE inflation impact of 800 BURNIE/level/player — worst-case (all eligible players complete every level) and expected case
- [ ] **ECON-02**: Assess interaction with gameOverPossible flag — does level quest payout affect endgame drip projection?

### Gas Analysis

- [ ] **GAS-01**: Estimate gas overhead of eligibility check in the quest handler hot path
- [ ] **GAS-02**: Estimate gas overhead of level quest roll in advanceGame level transition path

## Future Requirements

- [ ] Contract implementation of level quests (separate implementation milestone)
- [ ] Test suite for level quest mechanics
- [ ] Delta adversarial audit of level quest changes

## Out of Scope

| Feature | Reason |
|---------|--------|
| Contract implementation | Planning only — implementation is a future milestone |
| Level quest streaks | Explicitly excluded from design |
| Different quest weights for level quests | Same pool and weights as daily quests |
| Level quest interaction with daily quests | Completely independent systems |
| Frontend/UI for level quests | Not in audit scope |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| ELIG-01 | Phase 153 | Complete |
| ELIG-02 | Phase 153 | Complete |
| MECH-01 | Phase 153 | Complete |
| MECH-02 | Phase 153 | Complete |
| MECH-03 | Phase 153 | Complete |
| MECH-04 | Phase 153 | Complete |
| STOR-01 | Phase 153 | Complete |
| STOR-02 | Phase 153 | Complete |
| INTG-01 | Phase 154 | Complete |
| INTG-02 | Phase 154 | Complete |
| ECON-01 | Phase 155 | Pending |
| ECON-02 | Phase 155 | Pending |
| GAS-01 | Phase 155 | Pending |
| GAS-02 | Phase 155 | Pending |

**Coverage:**
- v12.0 requirements: 14 total
- Mapped to phases: 14
- Unmapped: 0

---
*Requirements defined: 2026-03-31*
*Last updated: 2026-03-31 -- phase mappings added*
