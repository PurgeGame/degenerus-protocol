---
phase: 121-storage-and-gas-fixes
plan: 03
subsystem: contracts
tags: [solidity, boon, deity, downgrade-prevention, storage-packing]

# Dependency graph
requires:
  - phase: 73-boon-storage-packing
    provides: "boonPacked 2-slot struct and _applyBoon function"
provides:
  - "Downgrade prevention in _applyBoon for all 7 tiered boon categories"
  - "Unified upgrade-only semantics for both deity and lootbox boon sources"
affects: [testing, deity-pass, lootbox-module]

# Tech tracking
tech-stack:
  added: []
  patterns: ["upgrade-only boon application -- newTier > existingTier guard on all write paths"]

key-files:
  created: []
  modified:
    - "contracts/modules/DegenerusGameLootboxModule.sol"

key-decisions:
  - "Removed isDeity bypass from all 7 tier-comparison guards rather than adding separate deity-tier checks -- simpler, same semantics"
  - "Updated NatSpec to reflect both-sources-upgrade-only semantics"

patterns-established:
  - "Boon tier writes always guarded by newTier > existingTier regardless of source"

requirements-completed: [FIX-06]

# Metrics
duration: 14min
completed: 2026-03-26
---

# Phase 121 Plan 03: Deity Boon Downgrade Prevention Summary

**Removed isDeity tier-check bypass from all 7 tiered boon categories in _applyBoon, preventing deity boons from downgrading existing higher-tier boons**

## Performance

- **Duration:** 14 min
- **Started:** 2026-03-26T02:31:08Z
- **Completed:** 2026-03-26T02:45:17Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments
- Removed `isDeity ||` bypass from tier comparison in coinflip, purchase, decimator, whale, activity, deity pass, and lazy pass boon paths
- Unified lootbox boost branch -- removed `if (isDeity) { overwrite } else { upgrade }` branching to single upgrade-only path
- Preserved deity day-field tracking and event suppression (still key off `isDeity`)
- Whale pass (type 28) correctly left unchanged -- no tier to protect
- Updated NatSpec comment to accurately describe upgrade-only semantics
- Full test suite green: 369 tests passed, 0 failures

## Task Commits

Each task was committed atomically:

1. **Task 1: Add downgrade prevention to all deity boon paths in _applyBoon (FIX-06)** - `e4d13c92` (fix)

## Files Created/Modified
- `contracts/modules/DegenerusGameLootboxModule.sol` - Removed isDeity bypass from 7 tier-check guards in _applyBoon, unified lootbox boost branch, updated NatSpec

## Decisions Made
- Removed `isDeity ||` entirely from tier guards rather than adding separate deity-specific tier checks -- both approaches prevent downgrades, but removing the bypass is simpler and produces identical behavior since the tier comparison already handles both upgrade and no-op cases
- Updated the function's NatSpec doc to replace "Deity boons: overwrite" with "Both sources use upgrade semantics" to prevent future confusion

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] Updated stale NatSpec on _applyBoon**
- **Found during:** Task 1
- **Issue:** NatSpec said "Deity boons: overwrite" which is now factually wrong after the fix
- **Fix:** Changed to "Both sources use upgrade semantics (only if higher tier/amount)"
- **Files modified:** contracts/modules/DegenerusGameLootboxModule.sol
- **Verification:** Visual inspection of updated doc comment
- **Committed in:** e4d13c92 (part of task commit)

---

**Total deviations:** 1 auto-fixed (1 missing critical -- stale NatSpec)
**Impact on plan:** Essential for correctness of documentation. No scope creep.

## Issues Encountered
- `forge build` reports lint warnings (unsafe-typecast) -- these are pre-existing across the codebase, not related to this change. Compilation itself succeeds.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- All FIX-06 changes complete and tested
- _applyBoon now has consistent upgrade-only semantics across all boon sources
- No blockers for subsequent phases

## Self-Check: PASSED

- FOUND: 121-03-SUMMARY.md
- FOUND: commit e4d13c92
- VERIFIED: 0 instances of `isDeity ||` bypass pattern
- VERIFIED: 25 instances of `isDeity` remain (day fields, events)
- VERIFIED: 369/369 forge tests pass

---
*Phase: 121-storage-and-gas-fixes*
*Completed: 2026-03-26*
