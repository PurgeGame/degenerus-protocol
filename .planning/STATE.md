---
gsd_state_version: 1.0
milestone: v4.0
milestone_name: Ticket Lifecycle & RNG-Dependent Variable Re-Audit
status: Ready to plan
stopped_at: Completed 85-01-PLAN.md
last_updated: "2026-03-23T15:15:46.311Z"
progress:
  total_phases: 8
  completed_phases: 3
  total_plans: 16
  completed_plans: 7
---

# State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-23)

**Core value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.
**Current focus:** Phase 89 — consolidated-findings (COMPLETE)

## Current Position

Phase: 87
Plan: Not started

## Accumulated Context

### Decisions

- [Phase 81]: 16 ticket creation paths traced (expanded from 14 in research) with file:line citations
- [Phase 81]: DSC-01: v3.9 RNG proof stale (combined pool -> FF-only revert in 2bf830a2), INFO severity
- [Phase 81]: DSC-02: sampleFarFutureTickets uses _tqWriteKey instead of _tqFarFutureKey, INFO severity
- [Phase 83]: Two ticketQueue winner-selection reads confirmed: _awardFarFutureCoinJackpot (JM:2543, FF key) and sampleFarFutureTickets (DG:2681, write key)
- [Phase 83]: All 6 trait-based winner selections route through _randTraitTicket or _randTraitTicketWithIndices helpers
- [Phase 89]: v4.0 consolidated findings finalized: 3 INFO (DSC-01, DSC-02, DSC-03), grand total 86 (16 LOW, 70 INFO), KNOWN-ISSUES.md updated
- [Phase 82]: Two distinct entropy sources confirmed: processTicketBatch reads lastLootboxRngWord (JM:1915), processFutureTicketBatch reads rngWordCurrent (MM:301)
- [Phase 82]: Mid-day entropy divergence confirmed: lastLootboxRngWord can hold mid-day lootbox VRF word (AM:159-162) -- by design, not a vulnerability
- [Phase 82]: LCG constant identity verified: JM:170 hex 0x5851F42D4C957F2D == MM:83 decimal 6364136223846793005
- [Phase 86]: NF-01: Duplicate winners from _randTraitTicket assessed as intentional gas-efficient design
- [Phase 86]: NF-02: Early-bird lootbox level arithmetic (price lvl+1, select lvl, target lvl+1) confirmed correct
- [Phase 86]: NF-03: Phase 81 Path #12 references non-existent _distributeTicketScatter; actual function is _distributeTicketsToBucket
- [Phase 83]: _resolveTraitWinners is correct function name (research used stale _processJackpotBucket)
- [Phase 83]: Only _awardFarFutureCoinJackpot selects winners from ticketQueue; all other jackpots use traitBurnTicket
- [Phase 86]: DCJ-03: Near-future coin budget silent skip assessed as intentional design per NatSpec at JM:2403-2404
- [Phase 86]: DCJ-01: v3.8 stale far-future key claim (readKey -> _tqFarFutureKey) classified INFO
- [Phase 88]: Slot shifts (27 of 42 DGS) are INFO-level -- caused by v3.8 Phase 73 boon packing, not security issues
- [Phase 88]: All 55 v3.8 verdicts CONFIRMED SAFE -- v3.9 changes expanded protection (FF key space + rngLockedFlag guard), never weakened it
- [Phase 85]: PAY-02 payout specification conflates FINAL_DAY shares with all-day shares and claims 4 winners; actual: 321 max across 4 buckets with two share packings
- [Phase 85]: v3.8 dailyEthPhase slot offset wrong (Slot 0:31 vs actual Slot 1:0); dailyCarryoverEthPool and dailyCarryoverWinnerCap are R/W not W-only
- [Phase 85]: CMT-V32-001 still unresolved (ticketSpent NatSpec); CMT-V32-002 resolved (inline comment updated)
- [Phase 84]: 6 currentPrizePool write sites and 5 read sites confirmed with file:line; forge inspect confirmed slots 2/3/14
- [Phase 84]: 13 prizePoolFrozen check sites classified: 8 REDIRECT, 3 REVERT, 2 SET/CLEAR
- [Phase 84]: 3 v3.8 slot numbers incorrect (INFO): yieldAccumulator 100->71, levelPrizePool 45->30, autoRebuyState 36->25
- [Phase 84]: VRF safety CONFIRMED: rawFulfillRandomWords does not read any prize pool variable
- [Phase 84]: consolidatePrizePools NatSpec omits x00 yield dump step (INFO)
- [Phase 87]: Early-bird lootbox: 100-winner loop with EntropyLib.entropyStep, trait selection, level offset roll, budget recycled to nextPrizePool
- [Phase 87]: Final-day DGNRS: 1% Reward pool via soloBucketIndex + lastDailyJackpotWinningTraits dependency verified correct ordering
- [Phase 87]: BAF-01: Inconsistent zero-score handling between far-future (allows) and scatter (strict) selection, INFO
- [Phase 87]: BAF-02: winnerMask constructed by DJ but discarded by EM at EM:361 — dead code with wasted gas, INFO
- [Phase 87]: DEC-01: decBucketOffsetPacked collision — terminal decimator overwrites regular decimator packed offsets at same level, MEDIUM
- [Phase 87]: DGN-01: Off-by-one in degenerette claimable balance check at DDM:552 (<=  should be <)
- [Phase 87]: DGN-02: Degenerette _addClaimableEth bypasses auto-rebuy unlike JM/EM/DM versions

### Pending Todos

None.

### Blockers/Concerns

- BOON-06: Test verification functionally confirmed but Plan 03 not formally executed (carried from v3.8)

## Session Continuity

Last session: 2026-03-23T15:14:54.908Z
Stopped at: Completed 85-01-PLAN.md
Resume file: None
