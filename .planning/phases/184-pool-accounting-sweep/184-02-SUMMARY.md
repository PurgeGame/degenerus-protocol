---
phase: 184-pool-accounting-sweep
plan: 02
subsystem: audit
tags: [pool-accounting, nextPool, claimablePool, claimableWinnings, debit-credit-trace]

requires:
  - phase: 184-pool-accounting-sweep
    provides: "Phase context and canonical pool storage references"
provides:
  - "Complete debit/credit trace for nextPool (20 sites) and claimablePool (16 sites) across all modules"
  - "claimableWinnings invariant analysis (9 patterns verified)"
  - "DecimatorModule double-debit proof (CL-14 + CL-15 disjoint)"
affects: [184-03, pool-fixes, adversarial-audit]

tech-stack:
  added: []
  patterns: ["SITE-XX-NN audit entry format with counterpart verification"]

key-files:
  created:
    - ".planning/phases/184-pool-accounting-sweep/184-nextPool-claimablePool-audit.md"
  modified: []

key-decisions:
  - "SITE-NP-16 lootbox triple-BPS split has negligible dust leak (up to 2 wei per purchase) -- accepted as non-issue"
  - "claimablePool invariant HOLDS across all paths including sentinel, auto-rebuy, and terminal zeroing"
  - "DecimatorModule CL-14 and CL-15 debits are disjoint (ethPortion vs lootboxPortion) -- no double-counting"

patterns-established:
  - "SITE-NP-NN: nextPool mutation audit entry format"
  - "SITE-CL-NN: claimablePool mutation audit entry format"
  - "SITE-CW-NN: claimableWinnings pattern audit entry format"

requirements-completed: [SWEEP-02, SWEEP-03]

duration: 10min
completed: 2026-04-04
---

# Phase 184 Plan 02: nextPool + claimablePool Audit Summary

**Complete debit/credit trace of 45 pool mutation sites across 9 contracts -- 0 gaps found, claimablePool invariant verified**

## Performance

- **Duration:** 10 min
- **Started:** 2026-04-04T19:32:11Z
- **Completed:** 2026-04-04T19:42:15Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments
- Traced all 20 nextPool mutation sites (_setNextPrizePool + dual _setPrizePools writes) with counterpart verification -- all 20 verified YES
- Traced all 16 claimablePool mutation sites (credits and debits) with ETH source/destination tracking -- all 16 verified YES
- Documented 9 claimableWinnings patterns and verified each pairs correctly with claimablePool operations
- Proved claimablePool >= sum(claimableWinnings) invariant holds across normal, auto-rebuy, sentinel, and terminal paths
- Explicitly analyzed DecimatorModule double-debit risk (CL-14 ethSpent + CL-15 lootboxPortion) -- confirmed disjoint, no double-counting

## Task Commits

Each task was committed atomically:

1. **Task 1: Trace all nextPool mutation sites** - `29513161` (docs)
2. **Task 2: Trace all claimablePool and claimableWinnings mutation sites** - `e7eacfcf` (docs)

## Files Created/Modified
- `.planning/phases/184-pool-accounting-sweep/184-nextPool-claimablePool-audit.md` - Complete debit/credit trace for nextPool (20 sites), claimablePool (16 sites), claimableWinnings (9 patterns), summary table, and invariant analysis

## Decisions Made
- SITE-NP-16 (MintModule lootbox triple-BPS split): up to 2 wei dust per purchase stays in contract balance but enters no tracked pool. Accepted as negligible.
- Sentinel 1-wei accounting in _claimWinningsInternal: claimablePool slightly over-reserved (safe direction). Not a gap.
- claimablePool invariant verdict: HOLDS across all paths.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- nextPool and claimablePool audit complete
- Ready for 184-03 (futurePool/currentPool/reservePool sweep) which will complete the full pool accounting picture
- One minor finding (SITE-NP-16 dust leak) documented but accepted as non-issue

---
*Phase: 184-pool-accounting-sweep*
*Completed: 2026-04-04*
