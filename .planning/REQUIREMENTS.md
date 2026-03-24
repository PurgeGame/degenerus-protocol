# Requirements: Ticket Lifecycle Integration Tests

**Defined:** 2026-03-23
**Core Value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.

## v4.1 Requirements

Requirements for Ticket Lifecycle Integration Tests milestone. Each maps to roadmap phases.

### Ticket Source Coverage

- [x] **SRC-01**: Direct ETH purchase during purchase phase queues to level+1 and is fully processed after level transition
- [x] **SRC-02**: Direct ETH purchase during jackpot phase (non-last day) queues to level and is fully processed
- [x] **SRC-03**: Direct ETH purchase on last jackpot day (rngLocked, jackpotCounter+step >= CAP) queues to level+1, not stranded after _endPhase
- [x] **SRC-04**: Lootbox open with near roll (offset 0-4) queues to write key and is processed by _prepareFutureTickets
- [x] **SRC-05**: Lootbox open with far roll (offset 5-50) queues to FF key and is eventually drained at phase transition
- [x] **SRC-06**: Whale bundle purchase queues tickets at purchaseLevel through purchaseLevel+9, all processed across transitions

### Edge Cases

- [x] **EDGE-01**: Tickets at exactly level+5 route to write key (near-future), not FF key
- [x] **EDGE-02**: Tickets at level+6 route to FF key
- [x] **EDGE-03**: FF tickets at level L+5 are drained during phase transition, not during daily cycle
- [x] **EDGE-04**: Jackpot-phase tickets at level appear in read slot after _swapAndFreeze and are processed by _runProcessTicketBatch(level)
- [x] **EDGE-05**: Constructor-queued FF tickets at levels 6-100 accumulate and drain one-per-transition as game advances
- [x] **EDGE-06**: Last jackpot day routing fix verified — rngLocked + jackpotCounter+step >= JACKPOT_LEVEL_CAP routes to level+1
- [x] **EDGE-07**: _prepareFutureTickets processes only read queues in +1..+4 range, does NOT touch FF keys
- [x] **EDGE-08**: After full level cycle (purchase -> jackpot -> transition), ALL read-slot queues for processed range are empty
- [x] **EDGE-09**: Write-slot tickets from current day survive _swapAndFreeze and appear in read slot on next cycle

### Zero-Stranding Assertions

- [x] **ZSA-01**: After each level transition, iterate levels 0..level+10 and assert ticketQueue[readKey].length == 0 for processed levels
- [x] **ZSA-02**: After each level transition, assert ticketQueue[ffKey].length == 0 for levels within FF drain range
- [x] **ZSA-03**: 3+ consecutive level transitions with continuous ticket buying from multiple sources yield zero stranding across all key spaces

### RNG Commitment Window Safety

- [x] **RNG-01**: No permissionless ticket path can mutate ticketQueue read-slot entries during VRF pending window (jackpot-resolution state frozen)
- [x] **RNG-02**: No permissionless ticket path can mutate traitBurnTicket entries used for jackpot winner selection during VRF pending window
- [x] **RNG-03**: rngLocked guard blocks FF key writes from all external callers (purchase, lootbox, whale bundle)
- [x] **RNG-04**: Purchase routing always creates entries in write slot (never read slot), regardless of rngLocked state — double-buffer is the structural guarantee

## Future Requirements

### Deferred (v3.3+)

- Foundry fuzz invariant tests for governance (vote weight conservation, threshold monotonicity)
- Formal verification of vote counting arithmetic via Halmos
- Monte Carlo simulation of governance outcomes under various voter distributions
- Storage packing implementation — 3 opportunities documented in v3.3 gas analysis (up to 66,300 gas savings)

### Deferred Ticket Sources

- Lazy pass purchase (4 tickets per level for 10 levels) — integration test deferred, edge cases covered
- Deity pass purchase (trait-targeted tickets) — integration test deferred, edge cases covered

## Out of Scope

| Feature | Reason |
|---------|--------|
| Gas benchmarking of ticket processing | Covered by v3.5 gas ceiling analysis |
| Lootbox RNG lifecycle tests | Covered by v3.7 LootboxRngLifecycle.t.sol |
| VRF core callback tests | Covered by v3.7 VRFCore.t.sol |
| Harness-level routing tests | Already exist in TicketRouting.t.sol, TicketEdgeCases.t.sol |
| Ticket processing state machine unit tests | Already exist in TicketProcessingFF.t.sol |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| SRC-01 | Phase 92 | Complete |
| SRC-02 | Phase 92 | Complete |
| SRC-03 | Phase 92 | Complete |
| SRC-04 | Phase 92 | Complete |
| SRC-05 | Phase 92 | Complete |
| SRC-06 | Phase 92 | Complete |
| EDGE-01 | Phase 93 | Complete |
| EDGE-02 | Phase 93 | Complete |
| EDGE-03 | Phase 93 | Complete |
| EDGE-04 | Phase 93 | Complete |
| EDGE-05 | Phase 92 | Complete |
| EDGE-06 | Phase 93 | Complete |
| EDGE-07 | Phase 92 | Complete |
| EDGE-08 | Phase 92 | Complete |
| EDGE-09 | Phase 92 | Complete |
| ZSA-01 | Phase 93 | Complete |
| ZSA-02 | Phase 93 | Complete |
| ZSA-03 | Phase 93 | Complete |
| RNG-01 | Phase 94 | Complete |
| RNG-02 | Phase 94 | Complete |
| RNG-03 | Phase 94 | Complete |
| RNG-04 | Phase 94 | Complete |

**Coverage:**
- v4.1 requirements: 22 total
- Mapped to phases: 22
- Unmapped: 0

---
*Requirements defined: 2026-03-23*
*Last updated: 2026-03-23 after roadmap creation*
