---
gsd_state_version: 1.0
milestone: v4.0
milestone_name: Ticket Lifecycle & RNG-Dependent Variable Re-Audit
status: Phase 89 complete — milestone ready for closure
stopped_at: Completed 82-01-PLAN.md
last_updated: "2026-03-23T15:08:07.094Z"
progress:
  total_phases: 8
  completed_phases: 1
  total_plans: 16
  completed_plans: 2
---

# State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-23)

**Core value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.
**Current focus:** Phase 89 — consolidated-findings (COMPLETE)

## Current Position

Phase: 89 (consolidated-findings) — COMPLETE
Plan: 1/1 — done

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

### Pending Todos

None.

### Blockers/Concerns

- BOON-06: Test verification functionally confirmed but Plan 03 not formally executed (carried from v3.8)

## Session Continuity

Last session: 2026-03-23T15:08:07.091Z
Stopped at: Completed 82-01-PLAN.md
Resume file: None
