---
gsd_state_version: 1.0
milestone: v24.1
milestone_name: Storage Layout Optimization
status: planning
stopped_at: Phase 211 context gathered
last_updated: "2026-04-10T16:33:28.879Z"
last_activity: 2026-04-10
progress:
  total_phases: 6
  completed_phases: 4
  total_plans: 14
  completed_plans: 14
  percent: 100
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-04-09)

**Core value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.
**Current focus:** Phase 211 — Test Suite Repair

## Current Position

Phase: 211 (Test Suite Repair) — NOT STARTED
Plan: 0 of 0
Milestone: v24.1 — Storage Layout Optimization
Status: Needs planning
Last activity: 2026-04-10

Progress: [██████░░░░] 66%

## Performance Metrics

**Velocity:**

- Total plans completed: 12 (v24.0 milestone)
- Timeline: 1 day (2026-04-09)

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [v24.1]: All day-index uint48 -> uint32; timestamps stay uint48; GNRUS governance uint48s unchanged
- [v24.1]: ticketWriteSlot converts from uint8 to bool (XOR toggle -> negation)
- [v24.1]: claimablePool downsized from uint256 to uint128 (340B ETH headroom)
- [v24.1]: Slot 0 absorbs ticketWriteSlot + prizePoolFrozen (30/32 bytes); slot 1 becomes currentPrizePool + claimablePool (32/32 bytes)
- [Phase 207]: uint32 for all day-index types; bool for ticketWriteSlot; uint128 for claimablePool; slot 0 absorbs buffer+freeze (30/32); slot 1 packs two uint128 pools (32/32)
- [Phase 207]: ETH/LINK scaled 1e15, BURNIE scaled 1e18 for lootboxRng packed slot
- [Phase 207]: 14 individual variables packed into 4 uint256 slots (lootboxRng, gameOver, dailyJackpotTraits, presale)
- [Phase 209]: JACKPOT_RESET_TIME kept as uint48 (time-in-seconds constant, not a day index)
- [Phase 209]: Removed intermediate uint48 casts in DegenerusQuests streak arithmetic -- uint32 currentDay minus uint24 anchorDay naturally produces uint32
- [Phase 209]: PendingRedemption packing drops from 256 to 240 bits; still fits one slot with 16 bits free
- [Phase 210]: 4 modules with pre-existing compilation errors documented as non-layout-drift; storage layout verified through shared inheritance
- [Phase 210]: Tightened GNRUS negative test pattern to avoid false positives from multi-variable event lines
- [Phase 210]: All test compilation failures are mechanical type mismatches (uint8->bool, uint48->uint32), not architectural regressions
- [Phase 210]: Cast uint48 index to uint32 at emit sites rather than narrowing local variable type
- [Phase 210]: Used assertTrue/assertFalse for bool ticketWriteSlot checks; left _dailyIdx() as uint48 with uint32 cast at assignment
- [Phase 210]: 113 test runtime failures (82 Foundry + 31 Hardhat) are assertion mismatches against pre-v24.1 layout, not contract regressions; need dedicated test-update plan

### Pending Todos

None.

### Blockers/Concerns

- ContractAddresses.sol has unstaged changes (different deploy addresses) — stash before test/tool runs
- FuturepoolSkim.t.sol references restructured _applyTimeBasedFutureTake (pre-existing compilation failure)

## Session Continuity

Last session: 2026-04-10T16:33:28.876Z
Stopped at: Phase 211 context gathered
