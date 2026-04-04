---
phase: 175-game-module-comment-sweep
plan: 04
subsystem: audit
tags: [comment-audit, natspec, boon, degenerette, decimator, terminal-decimator]

requires: []
provides:
  - "175-04-FINDINGS.md: comment audit findings for BoonModule, DegeneretteModule, DecimatorModule"
affects: [175-game-module-comment-sweep]

tech-stack:
  added: []
  patterns: []

key-files:
  created:
    - .planning/phases/175-game-module-comment-sweep/175-04-FINDINGS.md
  modified: []

key-decisions:
  - "4 LOW + 5 INFO findings across 3 contracts; terminal decimator rescaling comment is accurate"

patterns-established: []

requirements-completed: [CMT-01]

duration: 5min
completed: 2026-04-03
---

# Phase 175 Plan 04: BoonModule, DegeneretteModule, DecimatorModule Comment Sweep Summary

**9 findings (4 LOW, 5 INFO) across 3 contracts — wrong @notice on resolveBets is the highest-priority fix; terminal decimator rescaling comments are accurate**

## Performance

- **Duration:** 5 min
- **Started:** 2026-04-03T21:20:55Z
- **Completed:** 2026-04-03T21:25:55Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments
- Read DegenerusGameBoonModule (329 lines), DegenerusGameDegeneretteModule (1122 lines), DegenerusGameDecimatorModule (928 lines) in full
- Identified 9 comment discrepancies; none are security-impacting
- Verified terminal decimator rescaling (20x@120d → 1x@10d, block ≤7d) matches all inline comments and NatSpec
- Confirmed no stale `currentPrizePool as uint256` references in any of the three contracts

## Task Commits

Each task was committed atomically:

1. **Task 1: Sweep BoonModule and DegeneretteModule comments** - `d42e40ed` (feat) — includes full file with DecimatorModule section
2. **Task 2: Sweep DecimatorModule and finalize** — captured in same commit (file written in single pass)

**Plan metadata:** (docs commit below)

## Files Created/Modified
- `.planning/phases/175-game-module-comment-sweep/175-04-FINDINGS.md` — 9 findings across 3 contracts

## Decisions Made
None — analysis only; no code changes.

## Finding Summary

| ID | Severity | Contract | Description |
|----|----------|----------|-------------|
| B-01 | LOW | BoonModule | @notice claims "lootbox view functions" but no such functions exist |
| B-02 | INFO | BoonModule | @dev uses historical "Split from" language instead of current-state description |
| B-03 | INFO | BoonModule | Activity boon expiry uses `COINFLIP_BOON_EXPIRY_DAYS` — misleading constant name |
| D-01 | LOW | DegeneretteModule | `resolveBets` has duplicate @notice; first is pasted from a placement function |
| D-02 | INFO | DegeneretteModule | WWXRP bonus factor comment references payout table (1.78x for 2 matches) that doesn't exist in code (code uses 1.90x) |
| D-03 | INFO | DegeneretteModule | Inline comment uses "178 = 1.78x" example but 2-match base payout is 190 (1.90x) |
| D-04 | INFO | DegeneretteModule | "For backwards compatibility" describes history rather than current design intent |
| C-01 | LOW | DecimatorModule | NatSpec says "player burn resets" on bucket improvement but burn carries over intact |
| C-02 | LOW | DecimatorModule | Banner says "Always-open burn" but burns are blocked within 7 days of death clock |
| C-03 | INFO | DecimatorModule | Terminal dec multiplier comment slightly ambiguous at the day-10 boundary |

## Deviations from Plan

None — plan executed exactly as written. Both tasks completed in a single write pass (all three contracts read before writing any findings).

## Issues Encountered

None.

## Next Phase Readiness
- 175-04-FINDINGS.md ready for protocol team review
- 4 LOW findings warrant fixes before C4A submission (B-01, D-01, C-01, C-02)
- 5 INFO findings are low-priority polish items

---
*Phase: 175-game-module-comment-sweep*
*Completed: 2026-04-03*
