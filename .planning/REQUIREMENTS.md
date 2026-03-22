# Requirements: Degenerus Protocol — VRF Commitment Window Audit

**Defined:** 2026-03-22
**Core Value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.

## v3.8 Requirements

Requirements for VRF commitment window audit. Each maps to roadmap phases.

### Commitment Window Inventory

- [x] **CW-01**: Every storage variable written or read by VRF fulfillment (rawFulfillRandomWords -> all downstream consumers) is cataloged with its slot, contract, and purpose
- [x] **CW-02**: Every storage variable that feeds into VRF-dependent outcome computations is cataloged (backward trace from outcome to committed inputs)
- [x] **CW-03**: For each cataloged variable, every external/public function that can mutate it is identified with call-graph depth (direct + indirect via internal calls)
- [x] **CW-04**: Cross-reference proof that no external function callable by a non-admin actor can mutate any committed input between VRF request and fulfillment

### Mutation Analysis

- [x] **MUT-01**: Each variable receives a binary verdict: SAFE (immutable in commitment window) or VULNERABLE (mutable by player action in window)
- [x] **MUT-02**: Every VULNERABLE variable includes a specific fix recommendation with severity rating
- [x] **MUT-03**: Call-graph analysis covers indirect mutation paths (function A -> internal B -> writes variable C) to at least 3 levels of depth

### Coinflip RNG Path

- [x] **COIN-01**: Full coinflip lifecycle traced: bet placement -> RNG request -> fulfillment -> roll computation -> payout, with every state transition identified
- [x] **COIN-02**: Commitment window analysis specific to coinflip: what player-controllable state exists between bet and resolution
- [x] **COIN-03**: Multi-tx attack sequences modeled: bet + manipulate + claim patterns tested against commitment window

### advanceGame Day RNG

- [x] **DAYRNG-01**: Daily VRF word flow traced through all consumers: jackpot selection, lootbox index assignment, coinflip resolution, with data dependency graph
- [x] **DAYRNG-02**: Commitment window for advanceGame: what state can change between VRF request (in advanceGame) and fulfillment that affects outcome selection
- [ ] **DAYRNG-03**: Cross-day carry-over analysis: verify day N pending state doesn't leak into or contaminate day N+1 RNG outcomes

### Ticket Queue (Known Bug)

- [ ] **TQ-01**: Deep-dive on ticket queue swap during jackpot phase -- full exploitation scenario documented with attacker steps
- [ ] **TQ-02**: Identify and verify fix for the ticket queue commitment window violation
- [ ] **TQ-03**: Pattern scan for similar commitment window violations across all contracts (any state that shifts between request and use)

### Boon Storage Packing

- [x] **BOON-01**: All per-player boon state (currently 29 separate mappings) packed into a 2-slot struct using uint24 day fields (45,000+ year range) and uint8 lootboxTier
- [x] **BOON-02**: checkAndClearExpiredBoon rewritten to operate on packed struct with single SLOAD per slot instead of 29 separate SLOADs
- [x] **BOON-03**: _applyBoon rewritten to read-modify-write packed struct instead of individual mapping writes
- [x] **BOON-04**: All boon consumption functions (consumeCoinflipBoon, consumePurchaseBoost, consumeDecimatorBoost, consumeActivityBoon) updated for packed layout
- [x] **BOON-05**: Lootbox boost tier logic simplified from 3 separate bool+day+deityDay mappings to single tier field in packed struct
- [ ] **BOON-06**: All existing tests pass after storage layout change with equivalent behavior

## Future Requirements

### Deferred (v3.3+)

- **GOV-FUZZ-01**: Foundry fuzz invariant tests for governance (vote weight conservation, threshold monotonicity)
- **GOV-FORMAL-01**: Formal verification of vote counting arithmetic via Halmos
- **GOV-SIM-01**: Monte Carlo simulation of governance outcomes under various voter distributions
- **GAS-PACK-01**: Storage packing implementation -- 3 opportunities documented in v3.3 gas analysis (up to 66,300 gas savings)

## Out of Scope

| Feature | Reason |
|---------|--------|
| Frontend code | Not in audit scope |
| Off-chain infrastructure | VRF coordinator is external |
| Governance | Fully audited in v2.1 |
| VRF pipeline internals | Audited in v3.7 (request/fulfillment/stall/recovery) |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| CW-01 | Phase 68 | Complete |
| CW-02 | Phase 68 | Complete |
| CW-03 | Phase 68 | Complete |
| CW-04 | Phase 69 | Complete |
| MUT-01 | Phase 69 | Complete |
| MUT-02 | Phase 69 | Complete |
| MUT-03 | Phase 69 | Complete |
| COIN-01 | Phase 70 | Complete |
| COIN-02 | Phase 70 | Complete |
| COIN-03 | Phase 70 | Complete |
| DAYRNG-01 | Phase 71 | Complete |
| DAYRNG-02 | Phase 71 | Complete |
| DAYRNG-03 | Phase 71 | Pending |
| TQ-01 | Phase 72 | Pending |
| TQ-02 | Phase 72 | Pending |
| TQ-03 | Phase 72 | Pending |
| BOON-01 | Phase 73 | Complete |
| BOON-02 | Phase 73 | Complete |
| BOON-03 | Phase 73 | Complete |
| BOON-04 | Phase 73 | Complete |
| BOON-05 | Phase 73 | Complete |
| BOON-06 | Phase 73 | Pending |

**Coverage:**
- v3.8 requirements: 22 total
- Mapped to phases: 22
- Unmapped: 0

---
*Requirements defined: 2026-03-22*
*Last updated: 2026-03-22 after roadmap creation*
