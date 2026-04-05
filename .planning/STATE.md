---
gsd_state_version: 1.0
milestone: v22.0
milestone_name: BAF Simplification Delta Audit
status: defining_requirements
stopped_at: null
last_updated: "2026-04-05T21:00:00.000Z"
last_activity: 2026-04-05
progress:
  total_phases: 0
  completed_phases: 0
  total_plans: 0
  completed_plans: 0
  percent: 0
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-04-05)

**Core value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.
**Current focus:** Defining requirements for v22.0 BAF Simplification Delta Audit

## Current Position

Phase: Not started (defining requirements)
Plan: —
Status: Defining requirements
Last activity: 2026-04-05 — Milestone v22.0 started

## Performance Metrics

**Velocity:**

- Total plans completed: 5
- Average duration: —
- Total execution time: —

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 188 | 3 | - | - |
| 189 | 2 | - | - |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [v22.0]: runBafJackpot simplified from 3 returns to 1 (claimableDelta only); rebuy delta removed; RewardJackpotsSettled emitted unconditionally
- [v21.0]: Day-index clock migration complete — purchaseStartDay replaces levelStartTime
- [v20.0]: Pool consolidation into AdvanceModule with batched SSTOREs; JackpotModule exposes runBafJackpot with self-call guard

### Pending Todos

None yet.

### Blockers/Concerns

- ContractAddresses.sol has unstaged changes (different deploy addresses) — stash before test/tool runs
- JackpotModule at 22,858B after v20.0 — comfortable headroom

## Session Continuity

Last session: 2026-04-05
Stopped at: Milestone v22.0 started — defining requirements
Resume file: None
