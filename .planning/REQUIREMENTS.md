# Requirements: Degenerus Protocol — Far-Future Ticket Fix

**Defined:** 2026-03-23
**Core Value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.

## v3.9 Requirements

Requirements for far-future ticket stranding fix. Each maps to roadmap phases.

### Storage Layer

- [x] **STORE-01**: A third key space constant (TICKET_FAR_FUTURE_BIT = 1 << 22) exists in DegenerusGameStorage with helper function _tqFarFutureKey(lvl)
- [x] **STORE-02**: The three key spaces (Slot 0, Slot 1, Far Future) are non-colliding for all valid level values

### Ticket Routing (Central Fix)

- [x] **ROUTE-01**: _queueTickets and _queueTicketsScaled route to _tqFarFutureKey when targetLevel > level + 6 -- single fix point covering ALL callers (lootbox, whale, vault, endgame, decimator, jackpot auto-rebuy)
- [x] **ROUTE-02**: Tickets targeting level + 0 through level + 6 continue routing to _tqWriteKey (unchanged near-future behavior)
- [x] **ROUTE-03**: _queueTickets reverts when writing to the FF key while rngLocked is true, EXCEPT for calls originating from advanceGame (which holds the lock and queues vault/sDGNRS perpetual tickets as part of the advance flow)

### Ticket Processing

- [x] **PROC-01**: processFutureTicketBatch drains the far-future key for each level after the read-side queue is fully drained
- [x] **PROC-02**: Cursor state tracking distinguishes read-side vs far-future processing (ticketLevel with FF bit)
- [x] **PROC-03**: processFutureTicketBatch returns finished = true only when both queues (read-side + far-future) are drained

### Jackpot Eligibility

- [x] **JACK-01**: _awardFarFutureCoinJackpot selects winners from both write-side buffer AND far-future key combined
- [x] **JACK-02**: Winner index is computed over the combined pool length (len + ffLen) with correct routing to the right queue

### RNG Safety

- [x] **RNG-01**: No permissionless action during the VRF commitment window can influence which player wins a far-future coin jackpot draw -- the FF key is either frozen, guarded, or proven irrelevant to outcome selection when the RNG word is consumed
- [x] **RNG-02**: The rngLocked guard in _queueTickets prevents all permissionless far-future ticket writes during the commitment window (lootbox opens, whale purchases, endgame/decimator rolls) while allowing advanceGame-origin writes to pass through

### Edge Cases

- [x] **EDGE-01**: Far-future tickets opened after their target level enters the +2 to +6 near-future window are handled correctly (no double-counting or stranding)
- [x] **EDGE-02**: Far-future tickets that are already processed by processFutureTicketBatch cannot be re-processed if a new lootbox adds more tickets to the same FF key level
- [x] **EDGE-03**: The TQ-01 fix (_tqWriteKey -> _tqReadKey at JM:2544) is included or superseded by the JACK-01 combined pool approach

### Verification

- [x] **TEST-01**: Unit test confirms far-future tickets from ALL sources (lootbox, whale, vault, endgame) land in FF key, not write key
- [x] **TEST-02**: Unit test confirms processFutureTicketBatch drains FF key entries and mints traits
- [x] **TEST-03**: Unit test confirms _awardFarFutureCoinJackpot finds winners from FF key entries
- [x] **TEST-04**: Unit test confirms _queueTickets reverts for FF key writes when rngLocked is true (permissionless callers) but allows advanceGame-origin writes
- [ ] **TEST-05**: Integration test advances through multiple levels and verifies far-future tickets from all sources are processed correctly (no stranding)

## Future Requirements

### Deferred

- **GOV-FUZZ-01**: Foundry fuzz invariant tests for governance
- **GOV-FORMAL-01**: Formal verification of vote counting arithmetic via Halmos
- **GOV-SIM-01**: Monte Carlo simulation of governance outcomes

## Out of Scope

| Feature | Reason |
|---------|--------|
| Frontend code | Not in audit scope |
| Near-future ticket routing (+0 to +6) | Already handled by _prepareFutureTickets |
| _rollTargetLevel changes | Roll distribution unchanged |
| _swapTicketSlot / _swapAndFreeze | Double-buffer mechanics unchanged |
| Constructor pre-queue (levels 1-100) | One-time deploy, already in both buffers |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| STORE-01 | Phase 74 | Complete |
| STORE-02 | Phase 74 | Complete |
| ROUTE-01 | Phase 75 | Complete |
| ROUTE-02 | Phase 75 | Complete |
| ROUTE-03 | Phase 75 | Complete |
| PROC-01 | Phase 76 | Complete |
| PROC-02 | Phase 76 | Complete |
| PROC-03 | Phase 76 | Complete |
| JACK-01 | Phase 77 | Complete |
| JACK-02 | Phase 77 | Complete |
| RNG-01 | Phase 79 | Complete |
| RNG-02 | Phase 75 | Complete |
| EDGE-01 | Phase 78 | Complete |
| EDGE-02 | Phase 78 | Complete |
| EDGE-03 | Phase 77 | Complete |
| TEST-01 | Phase 80 | Complete |
| TEST-02 | Phase 80 | Complete |
| TEST-03 | Phase 80 | Complete |
| TEST-04 | Phase 80 | Complete |
| TEST-05 | Phase 80 | Pending |

**Coverage:**
- v3.9 requirements: 20 total
- Mapped to phases: 20
- Unmapped: 0

---
*Requirements defined: 2026-03-23*
*Updated: 2026-03-23 — expanded scope to all far-future ticket sources + advanceGame exemption*
