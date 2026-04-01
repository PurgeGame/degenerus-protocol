---
phase: 45-invariant-test-suite
plan: 01
subsystem: contracts
tags: [solidity, smart-contracts, bug-fix, redemption, solvency, CEI]

# Dependency graph
requires:
  - phase: 44-delta-audit-redemption-correctness
    provides: finding verdicts (CP-08, CP-06, Seam-1, CP-07) with confirmed fixes
provides:
  - CP-08 fix: _deterministicBurnFrom consistent with previewBurn and _submitGamblingClaimFrom
  - CP-06 fix: _gameOverEntropy resolves pending redemptions in both VRF and fallback paths
  - Seam-1 fix: DegenerusStonk.burn() reverts during active game to prevent orphaned claims
  - CP-07 fix: claimRedemption pays ETH independently of coinflip resolution
  - QueueDoubleBuffer compilation blocker resolved
  - Clean forge build (zero errors)
affects: [45-02, 45-03, invariant-tests]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Split-claim pattern: ETH always claimable, BURNIE conditional on coinflip"
    - "Game-active guard: DGNRS.burn() reverts during active game"

key-files:
  created: []
  modified:
    - contracts/StakedDegenerusStonk.sol
    - contracts/DegenerusStonk.sol
    - contracts/modules/DegenerusGameAdvanceModule.sol
    - test/fuzz/QueueDoubleBuffer.t.sol

key-decisions:
  - "Seam-1: chose Option A (revert during active game) over Option B (burnFor) -- simplest, no sDGNRS changes needed"
  - "CP-07: split claim into ETH-always + BURNIE-conditional rather than emergency coinflip resolution"
  - "QueueDoubleBuffer: commented out MID_DAY_SWAP_THRESHOLD refs (constant removed from production) rather than adding local constant"
  - "Removed unused FlipNotResolved error declaration after CP-07 refactor"

patterns-established:
  - "Segregation deduction: all totalMoney/totalBurnie computations subtract pending redemption reserves"
  - "Redemption resolution parity: rngGate and _gameOverEntropy resolve redemptions identically"

requirements-completed: [INV-01, INV-02, INV-03, INV-04, INV-05, INV-06, INV-07]

# Metrics
duration: 6min
completed: 2026-03-21
---

# Phase 45 Plan 01: Code Fixes Summary

**Applied 4 Phase 44 confirmed fixes (3 HIGH, 1 MEDIUM) and resolved QueueDoubleBuffer compilation blocker for clean invariant test baseline**

## Performance

- **Duration:** 6 min
- **Started:** 2026-03-21T04:43:04Z
- **Completed:** 2026-03-21T04:49:45Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments
- Applied CP-08 double-spend fix: `_deterministicBurnFrom` now correctly subtracts `pendingRedemptionEthValue` and `pendingRedemptionBurnie`, consistent with `previewBurn` and `_submitGamblingClaimFrom`
- Applied CP-06 stuck-claims fix: `_gameOverEntropy` now resolves pending redemptions in both VRF-ready and fallback paths, mirroring `rngGate` lines 770-780
- Applied Seam-1 fund-trap fix: `DegenerusStonk.burn()` reverts with `GameNotOver()` during active game, preventing orphaned claims under DGNRS contract address
- Applied CP-07 split-claim fix: `claimRedemption()` pays ETH regardless of coinflip resolution; BURNIE paid only when flip resolved and won; partial claim path preserves BURNIE claim for later
- Resolved QueueDoubleBuffer compilation blocker by commenting out references to removed `MID_DAY_SWAP_THRESHOLD` constant

## Task Commits

Each task was committed atomically:

1. **Task 1: Apply CP-08, CP-06, Seam-1 fixes + QueueDoubleBuffer compilation fix** - `3f90e7d8` (fix)
2. **Task 2: Apply CP-07 fix -- split claimRedemption for ETH-independent payout** - `b6d860e7` (fix)

## Files Created/Modified
- `contracts/StakedDegenerusStonk.sol` - CP-08 fix (lines 477, 482), CP-07 split-claim refactor (lines 575-618), removed FlipNotResolved error
- `contracts/DegenerusStonk.sol` - Seam-1 fix: added gameOver() to IDegenerusGame interface, GameNotOver error, revert guard in burn()
- `contracts/modules/DegenerusGameAdvanceModule.sol` - CP-06 fix: added redemption resolution blocks to both VRF and fallback paths in _gameOverEntropy
- `test/fuzz/QueueDoubleBuffer.t.sol` - Commented out MID_DAY_SWAP_THRESHOLD harness function and test, replaced with literal 440

## Decisions Made
- **Seam-1 fix approach:** Chose Option A (revert during active game) over Option B (add burnFor) -- simplest fix with no sDGNRS contract changes needed; DGNRS holders already have burnWrapped() as the correct active-game path
- **CP-07 fix approach:** Split claim into ETH-always + BURNIE-conditional paths rather than adding emergency coinflip resolution at game-over -- simpler, preserves ETH claim availability with fair BURNIE degradation
- **FlipNotResolved removal:** After CP-07 refactor, the FlipNotResolved error was unused -- removed to keep the contract clean
- **QueueDoubleBuffer approach:** Commented out rather than adding a local constant, since the test was testing a production constant that no longer exists

## Deviations from Plan

None -- plan executed exactly as written.

## Known Stubs

None -- all changes are complete production code fixes.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- All 4 confirmed findings (CP-08, CP-06, Seam-1, CP-07) are fixed and compiling
- `forge build` passes with zero errors (only lint warnings)
- Codebase is ready for invariant test suite development (Plans 02 and 03)

---
*Phase: 45-invariant-test-suite*
*Completed: 2026-03-21*

## Self-Check: PASSED
- All 4 modified files exist on disk
- SUMMARY.md created at expected path
- Both task commits (3f90e7d8, b6d860e7) exist in git history
