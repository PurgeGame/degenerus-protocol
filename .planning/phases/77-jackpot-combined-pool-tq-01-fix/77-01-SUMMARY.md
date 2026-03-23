---
phase: 77-jackpot-combined-pool-tq-01-fix
plan: 01
subsystem: smart-contract
tags: [solidity, jackpot, ticket-queue, combined-pool, vrf-commitment-window, tq-01-fix]

# Dependency graph
requires:
  - phase: 74-far-future-key-space
    provides: "_tqFarFutureKey helper and TICKET_FAR_FUTURE_BIT constant"
  - phase: 75-ticket-routing-rng-guard
    provides: "rngLocked guard on FF key writes, far-future ticket routing"
  - phase: 76-ticket-processing-extension
    provides: "Dual-queue drain in processFutureTicketBatch with FF-bit cursor encoding"
provides:
  - "Combined pool winner selection in _awardFarFutureCoinJackpot (read buffer + FF key)"
  - "TQ-01 vulnerability eliminated (_tqWriteKey removed from jackpot draw)"
  - "8 Foundry tests proving JACK-01, JACK-02, EDGE-03"
affects: [jackpot-draws, commitment-window-safety, ticket-eligibility]

# Tech tracking
tech-stack:
  added: []
  patterns: ["combined pool index routing: idx < readLen ? readQueue[idx] : ffQueue[idx - readLen]"]

key-files:
  created:
    - test/fuzz/JackpotCombinedPool.t.sol
  modified:
    - contracts/modules/DegenerusGameJackpotModule.sol

key-decisions:
  - "Combined pool approach (read buffer + FF key) supersedes simple TQ-01 one-line fix"
  - "Index routing uses strict less-than (idx < readLen) to avoid off-by-one at boundary"

patterns-established:
  - "Combined pool selection: sum lengths from multiple key spaces, route index via partition boundaries"

requirements-completed: [JACK-01, JACK-02, EDGE-03]

# Metrics
duration: 6min
completed: 2026-03-23
---

# Phase 77 Plan 01: Jackpot Combined Pool + TQ-01 Fix Summary

**Combined pool winner selection reading frozen read buffer + FF key in _awardFarFutureCoinJackpot, eliminating TQ-01 write-buffer vulnerability**

## Performance

- **Duration:** 6 min
- **Started:** 2026-03-23T02:43:27Z
- **Completed:** 2026-03-23T02:50:07Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- _awardFarFutureCoinJackpot now selects winners from combined read buffer + FF key population (JACK-01)
- Winner index routes correctly: [0, readLen) to read buffer, [readLen, combinedLen) to FF key with offset subtraction (JACK-02)
- _tqWriteKey completely eliminated from _awardFarFutureCoinJackpot -- TQ-01 vulnerability fixed (EDGE-03)
- 8 Foundry tests proving all three requirements with boundary conditions and division safety

## Task Commits

Each task was committed atomically:

1. **Task 1: RED -- Foundry test harness and failing tests** - `e916e914` (test)
2. **Task 2: GREEN -- Apply combined pool fix to production** - `7dd5002a` (feat)

## Files Created/Modified
- `test/fuzz/JackpotCombinedPool.t.sol` - Harness replicating proposed combined pool logic + 8 tests for JACK-01/JACK-02/EDGE-03
- `contracts/modules/DegenerusGameJackpotModule.sol` - _awardFarFutureCoinJackpot inner loop body replaced with combined pool selection

## Decisions Made
- Combined pool approach (read buffer + FF key) supersedes the simple TQ-01 one-line fix (_tqWriteKey to _tqReadKey). The combined pool both fixes TQ-01 AND includes Phase 75 FF-routed tickets.
- Index routing uses strict less-than (`idx < readLen`) at the partition boundary, avoiding off-by-one where `idx == readLen` would incorrectly access read buffer out-of-bounds.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Jackpot draw now covers all eligible ticket populations (read buffer + FF key)
- TQ-01 (MEDIUM) is fixed -- can be moved from "Known Issues" to "Resolved"
- Ready for edge case coverage (lootbox opened after FF tickets processed at near-future boundary)
- Phase 75/76 tests pass with no regression (12/12 and 9/9 respectively)

## Self-Check: PASSED

- test/fuzz/JackpotCombinedPool.t.sol: FOUND
- 77-01-SUMMARY.md: FOUND
- Commit e916e914: FOUND
- Commit 7dd5002a: FOUND

---
*Phase: 77-jackpot-combined-pool-tq-01-fix*
*Completed: 2026-03-23*
