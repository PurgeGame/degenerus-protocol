---
gsd_state_version: 1.0
milestone: v23.0
milestone_name: JackpotModule Delta Audit & Payout Reference
status: defining_requirements
stopped_at: null
last_updated: "2026-04-06"
last_activity: 2026-04-06
progress:
  total_phases: 0
  completed_phases: 0
  total_plans: 0
  completed_plans: 0
  percent: 0
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-04-06)

**Core value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.
**Current focus:** Defining requirements for v23.0

## Current Position

Phase: Not started (defining requirements)
Plan: —
Status: Defining requirements
Last activity: 2026-04-06 — Milestone v23.0 started

## Performance Metrics

**Velocity:**

- Total plans completed: 0
- Average duration: --
- Total execution time: --

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

Last session: 2026-04-06
Stopped at: Milestone v23.0 initialized
