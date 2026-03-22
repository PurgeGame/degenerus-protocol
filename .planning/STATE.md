---
gsd_state_version: 1.0
milestone: v3.6
milestone_name: VRF Stall Resilience
status: unknown
stopped_at: Completed 61-01-PLAN.md (stall resilience tests)
last_updated: "2026-03-22T13:32:58.698Z"
progress:
  total_phases: 4
  completed_phases: 3
  total_plans: 4
  completed_plans: 4
---

# State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-22)

**Core value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.
**Current focus:** Phase 61 — Stall Resilience Tests

## Current Position

Phase: 61 (Stall Resilience Tests) — EXECUTING
Plan: 1 of 1

## Accumulated Context

### Decisions

v3.6 context:

- VRF stall creates gap days where rngWordByDay[gapDay]=0 and lootboxRngWordByIndex[K]=0
- Fix: backfill gap day words from first post-gap VRF response using keccak256(vrfWord, gapDay)
- Coinflips and lootboxes then resolve naturally via existing claim paths
- No full advanceGame processing needed for gap days — just RNG backfill
- midDayTicketRngPending needs clearing on swap or first post-gap advance
- [Phase 59]: Gap days get zero nudges -- totalFlipReversals consumed only on current day
- [Phase 59]: resolveRedemptionPeriod skipped for gap days -- timer continued in real time during stall
- [Phase 59]: DailyRngApplied event reused with nudges=0 to distinguish backfilled days
- [Phase 59]: Orphaned index handled in updateVrfCoordinatorAndSub (not rngGate) -- resolves at exact moment of orphaning
- [Phase 59]: Fallback word derived from lastLootboxRngWord + orphanedIndex for unique entropy per index
- [Phase 60]: Used outgoingRequestId (captured before vrfRequestId=0 reset) as LootboxRngApplied emit argument for indexer traceability
- [Phase 60]: Comment-only NatSpec (not @dev tag) matching DegenerusAdmin.sol style for inline design rationale
- [Phase 61]: Used address(admin) from DeployProtocol for vm.prank -- same as ContractAddresses.ADMIN post-patch, avoids unused import
- [Phase 61]: Extracted _doCoordinatorSwap (no warp) from _stallAndSwap for incremental time-warp test patterns

### Pending Todos

None.

### Blockers/Concerns

None.

## Session Continuity

Last session: 2026-03-22T13:32:58.697Z
Stopped at: Completed 61-01-PLAN.md (stall resilience tests)
Resume file: None
