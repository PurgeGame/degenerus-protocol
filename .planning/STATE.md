---
gsd_state_version: 1.0
milestone: v22.0
milestone_name: BAF Simplification Delta Audit
status: executing
stopped_at: Phase 191 context gathered
last_updated: "2026-04-06T00:25:34.161Z"
last_activity: 2026-04-05
progress:
  total_phases: 2
  completed_phases: 1
  total_plans: 2
  completed_plans: 2
  percent: 100
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-04-05)

**Core value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.
**Current focus:** Phase 190 — ETH Flow + Rebuy Delta + Event Audit

## Current Position

Phase: 191
Plan: Not started
Status: Executing Phase 190
Last activity: 2026-04-05

Progress: [░░░░░░░░░░] 0%

## Performance Metrics

**Velocity:**

- Total plans completed: 2
- Average duration: --
- Total execution time: --

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 190 | 2 | - | - |
| 191 | 0 | - | - |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [v22.0]: runBafJackpot simplified from 3 returns to 1 (claimableDelta only); rebuy delta removed; RewardJackpotsSettled emitted unconditionally
- [v21.0]: Day-index clock migration complete -- purchaseStartDay replaces levelStartTime
- [v20.0]: Pool consolidation into AdvanceModule with batched SSTOREs; JackpotModule exposes runBafJackpot with self-call guard

### Pending Todos

None yet.

### Blockers/Concerns

- ContractAddresses.sol has unstaged changes (different deploy addresses) -- stash before test/tool runs
- JackpotModule at 22,858B after v20.0 -- comfortable headroom

## Session Continuity

Last session: 2026-04-06T00:25:34.159Z
Stopped at: Phase 191 context gathered
Resume file: .planning/phases/191-layout-regression-testing/191-CONTEXT.md
