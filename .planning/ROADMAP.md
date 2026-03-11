# Roadmap: Degenerus Protocol — Always-Open Purchases

## Overview

This milestone eliminates purchase downtime by implementing a double-buffered ticket queue and prize pool freeze/unfreeze system. The work flows strictly bottom-up: storage layout is established first (because all delegatecall modules compile it into their bytecode), then module helpers are migrated to packed pool accessors, then freeze branches are wired into every purchase path, then advanceGame is rewritten to drive the new state machine, and finally the rngLockedFlag purchase reverts are removed. That ordering is not arbitrary — each phase is a prerequisite for the next, and removing the lock before the preceding phases are complete would introduce invariant violations worse than the current lock.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Storage Foundation** - Add Slot 1 fields, packed pool slots, and all key/swap/freeze helpers to DegenerusGameStorage (completed 2026-03-11)
- [x] **Phase 2: Queue Double-Buffer** - Wire all queue functions to write/read key helpers; implement swap with hard drain gate (completed 2026-03-11)
- [x] **Phase 3: Prize Pool Freeze** - Add freeze branch to all 7 purchase-path pool addition sites; populate pending accumulators (completed 2026-03-11)
- [x] **Phase 4: advanceGame Rewrite** - Rewrite daily state machine with mid-day path, drain gates, swap/freeze, and unfreeze exit points (completed 2026-03-11)
- [ ] **Phase 5: Lock Removal** - Remove rngLockedFlag purchase reverts and validate full integration with fuzz suite

## Phase Details

### Phase 1: Storage Foundation
**Goal**: DegenerusGameStorage contains all new fields and helper functions; storage layout is verified correct before any module is touched
**Depends on**: Nothing (first phase)
**Requirements**: STOR-01, STOR-02, STOR-03, STOR-04
**Success Criteria** (what must be TRUE):
  1. `forge inspect DegenerusGameStorage storage-layout` shows `ticketWriteSlot` (uint8), `ticketsFullyProcessed` (bool), and `prizePoolFrozen` (bool) at bytes 24-26 of Slot 1 with no slot shifts in subsequent fields
  2. `prizePoolsPacked` (uint128+uint128) exists and `nextPrizePool`/`futurePrizePool` are removed from storage; all helper functions (`_getPrizePools`, `_setPrizePools`, `_getPendingPools`, `_setPendingPools`) compile cleanly
  3. `_tqWriteKey` and `_tqReadKey` produce different keys for the same input in all cases; a unit test asserts this invariant for both values of `ticketWriteSlot`
  4. `forge clean && forge build` succeeds with zero warnings about storage layout after the changes
**Plans:** 2/2 plans complete

Plans:
- [x] 01-01-PLAN.md — Add all storage fields, constants, packed pool vars, helper functions, and compatibility shims to DegenerusGameStorage.sol
- [x] 01-02-PLAN.md — Migrate 96 consumer references to shim calls, then create unit tests for all STOR requirements plus swap/freeze/unfreeze

### Phase 2: Queue Double-Buffer
**Goal**: All ticket queue operations use the correct slot key; a swap function with a hard drain gate exists and is the sole entry point for slot rotation
**Depends on**: Phase 1
**Requirements**: QUEUE-01, QUEUE-02, QUEUE-03, QUEUE-04
**Success Criteria** (what must be TRUE):
  1. Every `_queueTickets*` call site uses `_tqWriteKey()` — a grep for direct mapping key access in queue write functions returns zero results
  2. Every processing function uses `_tqReadKey()` — a grep for direct mapping key access in ticket processing loops returns zero results
  3. `_swapTicketSlot()` reverts with `ReadSlotNotDrained` when the read slot contains any entries; the revert is triggered in a unit test
  4. The mid-day swap fires when write queue length reaches 440 or when jackpot phase is active and write queue is non-empty
**Plans:** 2/2 plans complete

Plans:
- [x] 02-01-PLAN.md — Write-path and read-path key migration across Storage, JackpotModule, MintModule, and DegenerusGame + buffer isolation unit tests
- [x] 02-02-PLAN.md — Mid-day swap trigger path in advanceGame with MID_DAY_SWAP_THRESHOLD constant + mid-day unit tests

### Phase 3: Prize Pool Freeze
**Goal**: All purchase-path pool additions branch on prizePoolFrozen; ETH received during a freeze lands in pending accumulators and is applied atomically at unfreeze
**Depends on**: Phase 2
**Requirements**: FREEZE-01, FREEZE-02, FREEZE-03, FREEZE-04
**Success Criteria** (what must be TRUE):
  1. `_swapAndFreeze()` is called at exactly one site — the daily RNG request in advanceGame — and sets `prizePoolFrozen = true` atomically with the slot swap
  2. An integration test exercising all 9 purchase paths under active freeze shows live pool values unchanged while pending accumulator values increase by the correct amounts
  3. `_unfreezePool()` is the only code path that clears `prizePoolFrozen`; a grep for direct `prizePoolFrozen = false` assignment returns zero results
  4. Freeze persists across all 5 jackpot draw days — a test simulating 5 sequential daily cycles with purchases between each confirms pending accumulators are not reset between draws
**Plans:** 2/2 plans complete

Plans:
- [x] 03-01-PLAN.md — Add freeze branching to all 7 purchase-path pool addition sites + wire _swapAndFreeze/_unfreezePool into advanceGame
- [x] 03-02-PLAN.md — FreezeHarness + freeze lifecycle unit tests covering FREEZE-01 through FREEZE-04

### Phase 4: advanceGame Rewrite
**Goal**: advanceGame drives the new state machine correctly — mid-day path processes the read slot and triggers a swap when qualified; daily path gates on ticketsFullyProcessed; freeze and unfreeze happen at the right points
**Depends on**: Phase 3
**Requirements**: ADV-01, ADV-02, ADV-03
**Success Criteria** (what must be TRUE):
  1. Mid-day advanceGame call processes the read slot and triggers `_swapTicketSlot()` (no freeze) when write queue >= 440 or jackpot phase active; a test confirms pools are not frozen after a mid-day call
  2. Daily RNG request does not proceed when `ticketsFullyProcessed == false`; a test with an non-empty read slot confirms the daily path blocks at the gate
  3. `ticketsFullyProcessed` is set to true before any jackpot or phase transition logic executes; a test confirms the flag is true at the point jackpot logic fires
  4. Every break path through the `do { } while(false)` structure either calls `_unfreezePool()` or is demonstrably unreachable under freeze; no path leaves freeze permanently active
**Plans:** 1/1 plans complete

Plans:
- [ ] 04-01-PLAN.md — Pre-RNG drain gate + ticketsFullyProcessed flag in AdvanceModule + AdvanceHarness with all ADV requirement tests

### Phase 5: Lock Removal
**Goal**: rngLockedFlag no longer blocks any ticket purchase path; the full test suite passes confirming always-open purchases are live
**Depends on**: Phase 4
**Requirements**: LOCK-01, LOCK-02, LOCK-03, LOCK-04, LOCK-05, LOCK-06
**Success Criteria** (what must be TRUE):
  1. A purchase transaction submitted while daily RNG processing is active does not revert — it succeeds and lands in the write slot
  2. A grep for `rngLockedFlag` in MintModule and LootboxModule purchase-path functions returns zero results for the six removed sites
  3. The Foundry fuzz suite passes with tests covering purchase-during-RNG-lock, mid-day threshold trigger, and jackpot-phase multi-day freeze persistence
  4. A gas snapshot confirms at least one fewer SSTORE per purchase compared to pre-milestone baseline (from packed pool helpers)
**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Storage Foundation | 2/2 | Complete   | 2026-03-11 |
| 2. Queue Double-Buffer | 2/2 | Complete   | 2026-03-11 |
| 3. Prize Pool Freeze | 2/2 | Complete   | 2026-03-11 |
| 4. advanceGame Rewrite | 1/1 | Complete   | 2026-03-11 |
| 5. Lock Removal | 0/? | Not started | - |
