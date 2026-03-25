---
gsd_state_version: 1.0
milestone: v4.4
milestone_name: BAF Cache-Overwrite Bug Fix + Pattern Scan
status: Defining requirements
stopped_at: null
last_updated: "2026-03-25T16:00:00.000Z"
progress:
  total_phases: 0
  completed_phases: 0
  total_plans: 0
  completed_plans: 0
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-25)

**Core value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.
**Current focus:** Defining requirements for v4.4

## Current Position

Phase: Not started (defining requirements)
Plan: —
Status: Defining requirements
Last activity: 2026-03-25 — Milestone v4.4 started

## Accumulated Context

### Decisions

- [v4.4]: BAF bug root cause: runRewardJackpots caches futurePrizePool into futurePoolLocal, but auto-rebuy inside _addClaimableEth writes directly to storage. Final _setFuturePrizePool(futurePoolLocal) overwrites auto-rebuy contributions.
- [v4.4]: Fix approach: Option A (delta reconciliation) — 3 lines, no signature changes. Compare storage to snapshot, fold delta into local before write-back.
- [v4.4]: Pattern scan required — same read-local / nested-write / stale-writeback pattern could exist elsewhere in the protocol.

### Pending Todos

None.

### Blockers/Concerns

- ContractAddresses.sol has unstaged changes (different deploy addresses) — stash before test runs

## Session Continuity

Last session: 2026-03-25
Stopped at: Milestone v4.4 initialized
Resume file: None
