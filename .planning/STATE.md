---
gsd_state_version: 1.0
milestone: v21.0
milestone_name: Jackpot Two-Call Split & Skip-Split Optimization
status: complete
stopped_at: Milestone v21.0 complete
last_updated: "2026-04-08T22:30:00.000Z"
last_activity: 2026-04-08
progress:
  total_phases: 4
  completed_phases: 4
  total_plans: 7
  completed_plans: 7
  percent: 100
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-04-08)

**Core value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.
**Current focus:** Planning next milestone

## Current Position

Milestone: v21.0 — Jackpot Two-Call Split & Skip-Split Optimization (complete)
Status: All 4 phases complete, ready for next milestone
Last activity: 2026-04-08

Progress: [██████████] 100%

## Performance Metrics

**Velocity:**

- Total plans completed: 6 (v20.0 milestone)
- Timeline: 1 day (2026-04-05)
- Git range: 5074a0f6..6d81a6b1 (15 commits)

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [v20.0]: Inline consolidatePrizePools + runRewardJackpots into AdvanceModule; batch SSTOREs
- [v20.0]: Expose runBafJackpot as external entry point with self-call guard (mirrors Decimator pattern)
- [v20.0]: Accept F-187-01 x100 trigger level shift as design improvement

### Pending Todos

None.

### Blockers/Concerns

- ContractAddresses.sol has unstaged changes (different deploy addresses) — stash before test/tool runs
- FuturepoolSkim.t.sol references restructured _applyTimeBasedFutureTake (pre-existing compilation failure)

## Session Continuity

Last session: 2026-04-08
Stopped at: Milestone v20.0 archived
