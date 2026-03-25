---
gsd_state_version: 1.0
milestone: v4.4
milestone_name: BAF Cache-Overwrite Bug Fix + Pattern Scan
status: Executing Phase 101
stopped_at: Roadmap created, Phase 100 not yet planned
last_updated: "2026-03-25T15:04:58.302Z"
progress:
  total_phases: 3
  completed_phases: 1
  total_plans: 2
  completed_plans: 1
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-25)

**Core value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.
**Current focus:** Phase 101 — bug-fix

## Current Position

Phase: 101 (bug-fix) — EXECUTING
Plan: 1 of 1

## Accumulated Context

### Decisions

- [v4.4]: BAF bug root cause: runRewardJackpots caches futurePrizePool into futurePoolLocal, but auto-rebuy inside _addClaimableEth writes directly to storage. Final _setFuturePrizePool(futurePoolLocal) overwrites auto-rebuy contributions.
- [v4.4]: Fix approach: Option A (delta reconciliation) — 3 lines, no signature changes. Compare storage to snapshot, fold delta into local before write-back.
- [v4.4]: Pattern scan required — same read-local / nested-write / stale-writeback pattern could exist elsewhere in the protocol.
- [v4.4]: Phase order: scan first (know the full scope), fix second (apply to known BAF instance + any scan discoveries), verify third (tests + comments).

### Pending Todos

None.

### Blockers/Concerns

- ContractAddresses.sol has unstaged changes (different deploy addresses) — stash before test runs

## Session Continuity

Last session: 2026-03-25
Stopped at: Roadmap created, Phase 100 not yet planned
Resume file: None
