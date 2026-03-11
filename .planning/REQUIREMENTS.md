# Requirements: Degenerus Protocol — Always-Open Purchases

**Defined:** 2026-03-11
**Core Value:** Players can purchase tickets at any time — no downtime during RNG processing or jackpot payouts

## v1 Requirements

Requirements for v1.0 milestone. Each maps to roadmap phases.

### Storage Infrastructure

- [ ] **STOR-01**: Slot 1 gets `ticketWriteSlot` (uint8), `ticketsFullyProcessed` (bool), `prizePoolFrozen` (bool) at bytes 18-20
- [ ] **STOR-02**: `nextPrizePool` + `futurePrizePool` replaced with `prizePoolsPacked` (uint128+uint128) and `_getPrizePools()`/`_setPrizePools()` helpers
- [ ] **STOR-03**: `prizePoolPendingPacked` added with `_getPendingPools()`/`_setPendingPools()` helpers
- [ ] **STOR-04**: `TICKET_SLOT_BIT` constant, `_tqWriteKey()`, `_tqReadKey()` helpers added

### Queue Double-Buffer

- [ ] **QUEUE-01**: All `_queueTickets*` functions use `_tqWriteKey()` for mapping keys
- [ ] **QUEUE-02**: All processing functions use `_tqReadKey()` for mapping keys
- [ ] **QUEUE-03**: `_swapTicketSlot()` with hard gate (revert if read slot non-empty)
- [ ] **QUEUE-04**: Mid-day swap trigger when write queue >= 440 or jackpot phase

### Prize Pool Freeze

- [ ] **FREEZE-01**: `_swapAndFreeze()` called at daily RNG request only
- [ ] **FREEZE-02**: All 9 purchase-path pool additions branch on `prizePoolFrozen`
- [ ] **FREEZE-03**: `_unfreezePool()` at correct exit points (purchase daily, phase end, transition end)
- [ ] **FREEZE-04**: Freeze persists across all 5 jackpot days — accumulators not reset between draws

### advanceGame Rewrite

- [ ] **ADV-01**: Mid-day path: process read slot, trigger swap (no freeze) when qualified
- [ ] **ADV-02**: Daily path gates RNG request behind `ticketsFullyProcessed`
- [ ] **ADV-03**: `ticketsFullyProcessed` set before jackpot/phase logic executes

### Lock Removal

- [ ] **LOCK-01**: Remove `rngLockedFlag` revert from `_callTicketPurchase` (MintModule:839)
- [ ] **LOCK-02**: Remove `rngLockedFlag` revert from `_purchaseFor` lootbox gate (MintModule:627)
- [ ] **LOCK-03**: Remove `rngLockedFlag` revert from `openLootBox` (LootboxModule:558)
- [ ] **LOCK-04**: Remove `rngLockedFlag` revert from `openBurnieLootBox` (LootboxModule:641)
- [ ] **LOCK-05**: Remove `rngLockedFlag` from `jackpotResolutionActive` in Degenerette (DegeneretteModule:504)
- [ ] **LOCK-06**: Remove redundant `rngLockedFlag` check from lootbox RNG request gate (AdvanceModule:599)

## v2 Requirements

None — this milestone is self-contained infrastructure.

## Out of Scope

| Feature | Reason |
|---------|--------|
| New game mechanics | Infrastructure-only milestone |
| Frontend changes | Contract-level only |
| DGNRS token changes | Already soulbound, separate concern |
| Gas optimization beyond packed pools | Separate effort |
| Remove rngLockedFlag from autorebuy/takeprofit/afking | Keep locked during jackpots — not critical to have available all the time |
| Remove rngLockedFlag from decimator autorebuy | Same — keep locked |
| 440-entry threshold tuning | Runtime constant, empirical tuning after deploy |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| STOR-01 | Phase 1 | Pending |
| STOR-02 | Phase 1 | Pending |
| STOR-03 | Phase 1 | Pending |
| STOR-04 | Phase 1 | Pending |
| QUEUE-01 | Phase 2 | Pending |
| QUEUE-02 | Phase 2 | Pending |
| QUEUE-03 | Phase 2 | Pending |
| QUEUE-04 | Phase 2 | Pending |
| FREEZE-01 | Phase 3 | Pending |
| FREEZE-02 | Phase 3 | Pending |
| FREEZE-03 | Phase 3 | Pending |
| FREEZE-04 | Phase 3 | Pending |
| ADV-01 | Phase 4 | Pending |
| ADV-02 | Phase 4 | Pending |
| ADV-03 | Phase 4 | Pending |
| LOCK-01 | Phase 5 | Pending |
| LOCK-02 | Phase 5 | Pending |
| LOCK-03 | Phase 5 | Pending |
| LOCK-04 | Phase 5 | Pending |
| LOCK-05 | Phase 5 | Pending |
| LOCK-06 | Phase 5 | Pending |

**Coverage:**
- v1 requirements: 21 total
- Mapped to phases: 21
- Unmapped: 0

---
*Requirements defined: 2026-03-11*
*Last updated: 2026-03-11 after roadmap creation — all 21 requirements mapped*
