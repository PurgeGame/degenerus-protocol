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
- [x] **TEST-05**: Integration test advances through multiple levels and verifies far-future tickets from all sources are processed correctly (no stranding)

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
| TEST-05 | Phase 80 | Complete |

**Coverage:**
- v3.9 requirements: 20 total
- Mapped to phases: 20
- Unmapped: 0

## v4.0 Requirements

Requirements for ticket lifecycle and RNG-dependent variable re-audit. Each maps to roadmap phases.

### Ticket Creation & Queue Mechanics

- [x] **TKT-01**: Every external function that queues tickets is identified with file:line, caller chain, and storage reads/writes
- [x] **TKT-02**: For each ticket creation path: what determines ticket count, target level, and queue key selection
- [x] **TKT-03**: Every ticket creation path's rngLockedFlag and prizePoolFrozen behavior is documented
- [x] **TKT-04**: All callers of _queueTickets, _queueTicketsScaled, _queueTicketRange, and direct ticketQueue pushes are enumerated
- [x] **TKT-05**: Double-buffer formulas (_tqReadKey, _tqWriteKey, _tqFarFutureKey) documented with ticketWriteSlot relationship
- [x] **TKT-06**: _swapAndFreeze / _swapTicketSlot trigger conditions and complete code path list documented

### Discrepancy Detection

- [x] **DSC-01**: Every discrepancy between prior audit prose and actual code flagged with [DISCREPANCY] tag
- [x] **DSC-02**: Every new issue not in prior audits flagged with [NEW FINDING] tag

| Requirement | Phase | Status |
|-------------|-------|--------|
| TKT-01 | Phase 81 | Complete |
| TKT-02 | Phase 81 | Complete |
| TKT-03 | Phase 81 | Complete |
| TKT-04 | Phase 81 | Complete |
| TKT-05 | Phase 81 | Complete |
| TKT-06 | Phase 81 | Complete |
| DSC-01 | Phase 81 | Complete |
| DSC-02 | Phase 81 | Complete |

### Ticket Processing Mechanics

- [x] **TPROC-01**: processTicketBatch entry point, all callers, and trigger conditions identified with file:line
- [x] **TPROC-02**: processFutureTicketBatch entry point, dual-queue drain logic, FF key processing documented with file:line
- [x] **TPROC-03**: RNG word derivation chain for ticket trait generation documented (rawFulfillRandomWords → trait assignment)
- [ ] **TPROC-04**: Cursor management (ticketLevel, ticketCursor, ticketsFullyProcessed) full lifecycle traced with file:line
- [ ] **TPROC-05**: traitBurnTicket storage layout and all write/read paths documented
- [ ] **TPROC-06**: Every discrepancy between prior audit prose and actual code flagged with [DISCREPANCY] tag; every new issue flagged with [NEW FINDING] tag

### Ticket Consumption & Winner Selection

- [x] **TCON-01**: Every function reading from ticketQueue for winner selection identified with file:line
- [x] **TCON-02**: Every function reading traitBurnTicket for winner selection identified with file:line
- [ ] **TCON-03**: Winner index computation documented for each jackpot type (ETH, coin, ticket, FF coin)
- [ ] **TCON-04**: Every discrepancy and new finding tagged

### Prize Pool Flow & currentPrizePool Deep Dive

- [ ] **PPF-01**: currentPrizePool storage slot confirmed, all writers enumerated with file:line
- [ ] **PPF-02**: prizePoolsPacked storage layout documented (packed fields, bit positions, BPS allocations)
- [ ] **PPF-03**: prizePoolFrozen freeze/unfreeze lifecycle traced with all trigger conditions
- [ ] **PPF-04**: Prize pool consolidation mechanics documented with file:line
- [ ] **PPF-05**: All VRF-dependent readers of currentPrizePool documented
- [ ] **PPF-06**: Every discrepancy and new finding tagged

### Daily ETH Jackpot

- [ ] **DETH-01**: currentPrizePool source, BPS allocation table, and split logic documented with file:line
- [ ] **DETH-02**: Phase 0 vs Phase 1 jackpot behavior documented
- [ ] **DETH-03**: Bucket/cursor winner selection algorithm documented with file:line
- [ ] **DETH-04**: Carryover mechanics (unfilled buckets, excess, rollover) documented
- [ ] **DETH-05**: Every discrepancy and new finding tagged

### Daily Coin + Ticket Jackpot

- [ ] **DCOIN-01**: Coin jackpot winner selection path documented with file:line (including _awardFarFutureCoinJackpot)
- [x] **DCOIN-02**: Ticket jackpot winner selection path documented with file:line
- [ ] **DCOIN-03**: jackpotCounter lifecycle (initialization, increment, read, reset) fully traced
- [x] **DCOIN-04**: Every discrepancy and new finding tagged

### Other Jackpots

- [ ] **OJCK-01**: Early-bird lootbox jackpot mechanics documented with file:line
- [ ] **OJCK-02**: BAF (Buy and Flip) jackpot mechanics documented with file:line
- [ ] **OJCK-03**: Decimator jackpot mechanics documented with file:line
- [ ] **OJCK-04**: Degenerette jackpot mechanics documented with file:line
- [ ] **OJCK-05**: Final day DGNRS distribution mechanics documented with file:line
- [ ] **OJCK-06**: Every discrepancy and new finding tagged

### RNG-Dependent Variable Re-verification

- [ ] **RDV-01**: Every variable from v3.8 commitment window inventory Section 4 re-verified against current Solidity with storage slot confirmation
- [ ] **RDV-02**: Missing variables identified — state that should be in the RNG-dependent catalog but was missed
- [ ] **RDV-03**: Delta assessment — variables that changed behavior since v3.8 audit documented
- [ ] **RDV-04**: Every discrepancy and new finding tagged

### Consolidated Findings

- [ ] **CFND-01**: All v4.0 findings (phases 81-88) deduplicated and severity-ranked
- [ ] **CFND-02**: KNOWN-ISSUES.md updated with any new findings above INFO
- [ ] **CFND-03**: Cross-phase consistency verified — no contradictions between phase audit documents

| Requirement | Phase | Status |
|-------------|-------|--------|
| TKT-01 | Phase 81 | Complete |
| TKT-02 | Phase 81 | Complete |
| TKT-03 | Phase 81 | Complete |
| TKT-04 | Phase 81 | Complete |
| TKT-05 | Phase 81 | Complete |
| TKT-06 | Phase 81 | Complete |
| DSC-01 | Phase 81 | Complete |
| DSC-02 | Phase 81 | Complete |
| TPROC-01 | Phase 82 | Not started |
| TPROC-02 | Phase 82 | Not started |
| TPROC-03 | Phase 82 | Not started |
| TPROC-04 | Phase 82 | Not started |
| TPROC-05 | Phase 82 | Not started |
| TPROC-06 | Phase 82 | Not started |
| TCON-01 | Phase 83 | Not started |
| TCON-02 | Phase 83 | Not started |
| TCON-03 | Phase 83 | Not started |
| TCON-04 | Phase 83 | Not started |
| PPF-01 | Phase 84 | Not started |
| PPF-02 | Phase 84 | Not started |
| PPF-03 | Phase 84 | Not started |
| PPF-04 | Phase 84 | Not started |
| PPF-05 | Phase 84 | Not started |
| PPF-06 | Phase 84 | Not started |
| DETH-01 | Phase 85 | Not started |
| DETH-02 | Phase 85 | Not started |
| DETH-03 | Phase 85 | Not started |
| DETH-04 | Phase 85 | Not started |
| DETH-05 | Phase 85 | Not started |
| DCOIN-01 | Phase 86 | Not started |
| DCOIN-02 | Phase 86 | Not started |
| DCOIN-03 | Phase 86 | Not started |
| DCOIN-04 | Phase 86 | Not started |
| OJCK-01 | Phase 87 | Not started |
| OJCK-02 | Phase 87 | Not started |
| OJCK-03 | Phase 87 | Not started |
| OJCK-04 | Phase 87 | Not started |
| OJCK-05 | Phase 87 | Not started |
| OJCK-06 | Phase 87 | Not started |
| RDV-01 | Phase 88 | Not started |
| RDV-02 | Phase 88 | Not started |
| RDV-03 | Phase 88 | Not started |
| RDV-04 | Phase 88 | Not started |
| CFND-01 | Phase 89 | Not started |
| CFND-02 | Phase 89 | Not started |
| CFND-03 | Phase 89 | Not started |

**Coverage:**
- v4.0 requirements: 46 total
- Mapped to phases: 46
- Unmapped: 0

---
*Requirements defined: 2026-03-23*
*Updated: 2026-03-23 — v4.0 full milestone requirements added (phases 82-89)*
