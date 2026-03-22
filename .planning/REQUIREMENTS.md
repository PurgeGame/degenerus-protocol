# Requirements: Degenerus Protocol — VRF Commitment Window Audit

**Defined:** 2026-03-22
**Core Value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.

## v3.8 Requirements

Requirements for VRF commitment window audit. Each maps to roadmap phases.

### Commitment Window Inventory

- [ ] **CW-01**: Every storage variable written or read by VRF fulfillment (rawFulfillRandomWords -> all downstream consumers) is cataloged with its slot, contract, and purpose
- [ ] **CW-02**: Every storage variable that feeds into VRF-dependent outcome computations is cataloged (backward trace from outcome to committed inputs)
- [ ] **CW-03**: For each cataloged variable, every external/public function that can mutate it is identified with call-graph depth (direct + indirect via internal calls)
- [ ] **CW-04**: Cross-reference proof that no external function callable by a non-admin actor can mutate any committed input between VRF request and fulfillment

### Mutation Analysis

- [ ] **MUT-01**: Each variable receives a binary verdict: SAFE (immutable in commitment window) or VULNERABLE (mutable by player action in window)
- [ ] **MUT-02**: Every VULNERABLE variable includes a specific fix recommendation with severity rating
- [ ] **MUT-03**: Call-graph analysis covers indirect mutation paths (function A -> internal B -> writes variable C) to at least 3 levels of depth

### Coinflip RNG Path

- [ ] **COIN-01**: Full coinflip lifecycle traced: bet placement -> RNG request -> fulfillment -> roll computation -> payout, with every state transition identified
- [ ] **COIN-02**: Commitment window analysis specific to coinflip: what player-controllable state exists between bet and resolution
- [ ] **COIN-03**: Multi-tx attack sequences modeled: bet + manipulate + claim patterns tested against commitment window

### advanceGame Day RNG

- [ ] **DAYRNG-01**: Daily VRF word flow traced through all consumers: jackpot selection, lootbox index assignment, coinflip resolution, with data dependency graph
- [ ] **DAYRNG-02**: Commitment window for advanceGame: what state can change between VRF request (in advanceGame) and fulfillment that affects outcome selection
- [ ] **DAYRNG-03**: Cross-day carry-over analysis: verify day N pending state doesn't leak into or contaminate day N+1 RNG outcomes

### Ticket Queue (Known Bug)

- [ ] **TQ-01**: Deep-dive on ticket queue swap during jackpot phase -- full exploitation scenario documented with attacker steps
- [ ] **TQ-02**: Identify and verify fix for the ticket queue commitment window violation
- [ ] **TQ-03**: Pattern scan for similar commitment window violations across all contracts (any state that shifts between request and use)

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
| Gas optimization | Not the focus of this audit |
| Governance | Fully audited in v2.1 |
| VRF pipeline internals | Audited in v3.7 (request/fulfillment/stall/recovery) |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| CW-01 | — | Pending |
| CW-02 | — | Pending |
| CW-03 | — | Pending |
| CW-04 | — | Pending |
| MUT-01 | — | Pending |
| MUT-02 | — | Pending |
| MUT-03 | — | Pending |
| COIN-01 | — | Pending |
| COIN-02 | — | Pending |
| COIN-03 | — | Pending |
| DAYRNG-01 | — | Pending |
| DAYRNG-02 | — | Pending |
| DAYRNG-03 | — | Pending |
| TQ-01 | — | Pending |
| TQ-02 | — | Pending |
| TQ-03 | — | Pending |

**Coverage:**
- v3.8 requirements: 16 total
- Mapped to phases: 0
- Unmapped: 16

---
*Requirements defined: 2026-03-22*
*Last updated: 2026-03-22 after initial definition*
