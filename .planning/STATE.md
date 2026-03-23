---
gsd_state_version: 1.0
milestone: v3.9
milestone_name: Far-Future Ticket Fix
status: Ready to plan
stopped_at: Completed 80-02-PLAN.md
last_updated: "2026-03-23T03:37:08Z"
progress:
  total_phases: 7
  completed_phases: 5
  total_plans: 5
  completed_plans: 5
---

# State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-23)

**Core value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.
**Current focus:** Phase 80 — Test Suite (Plan 02 complete)

## Current Position

Phase: 80
Plan: 2 of 2 (complete)

## Accumulated Context

### Decisions

- [v3.8 Phase 72]: TQ-01 severity MEDIUM (BURNIE not ETH). Fix Option A (_tqWriteKey -> _tqReadKey) recommended.
- [v3.8 Phase 72]: Both call paths affected: payDailyJackpotCoinAndTickets AND payDailyCoinJackpot.
- [v3.9 Roadmap]: EDGE-03 (TQ-01 fix) grouped with JACK-01/JACK-02 -- combined pool approach may supersede the simple _tqReadKey fix.
- [v3.9 Roadmap]: rngLocked guard (RNG-02) grouped with lootbox routing since the guard lives in the same code path as ticket routing.
- [Phase 74]: Bit 22 reserved for far-future key space, reducing max level from 2^23-1 to 2^22-1 (still millennia)
- [Phase 74]: _tqFarFutureKey is pure (not view) -- far-future keys are slot-independent
- [Phase 75]: Consolidate error RngLocked() in DegenerusGameStorage base, remove from inheriting contracts
- [Phase 75]: Cache level outside _queueTicketRange loop as currentLevel to avoid per-iteration SLOAD
- [Phase 76]: Return after read-side drain, start FF on next call (simplicity over intra-call transition)
- [Phase 76]: Strip FF bit in _prepareFutureTickets for resume (not in processFutureTicketBatch)
- [Phase 77]: Combined pool approach (read buffer + FF key) supersedes simple TQ-01 one-line fix
- [Phase 77]: Index routing uses strict less-than (idx < readLen) to avoid off-by-one at boundary
- [Phase 78]: EDGE-01 and EDGE-02 proven SAFE by existing Phases 74-76 implementation -- zero contract code changes needed
- [Phase 80]: ticketQueue stores unique addresses (not ticket counts) -- constructor pre-queues 2 entries (sDGNRS + VAULT) per FF level, not 32
- [Phase 80]: Prize pool seeding via vm.store(slot 3) to 49.9 ETH fast-tracks level transitions in integration tests
- [Phase 80]: gas_limit/block_gas_limit 30B added to foundry.toml for multi-level integration test support

### Pending Todos

None.

### Blockers/Concerns

- Phase 73 (Boon Storage Packing) Plan 03 not formally executed -- test verification pending from v3.8.

## Session Continuity

Last session: 2026-03-23T03:37:08Z
Stopped at: Completed 80-02-PLAN.md
Resume file: None
