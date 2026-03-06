---
phase: 04-eth-token-accounting-integrity
plan: 02
subsystem: testing
tags: [accounting, invariant, claimablePool, ETH, stETH, manual-trace, audit]

# Dependency graph
requires:
  - phase: 04-eth-token-accounting-integrity
    provides: "04-RESEARCH.md with complete claimablePool mutation site inventory"
provides:
  - "ACCT-01 PASS verdict with per-site evidence for all 18 claimablePool sites"
  - "Decimator pre-reservation lifecycle documentation"
  - "Auto-rebuy dust handling analysis"
  - "Verified line-number references for all mutation sites"
affects: [04-04-reentrancy-analysis, 04-06-game-over-settlement]

# Tech tracking
tech-stack:
  added: []
  patterns: [manual-source-trace, invariant-verification, pre-reservation-pattern]

key-files:
  created:
    - ".planning/phases/04-eth-token-accounting-integrity/04-02-FINDINGS-invariant-manual-trace.md"
  modified: []

key-decisions:
  - "ACCT-01 PASS: claimablePool invariant holds across all 18 mutation sites"
  - "Decimator unclaimed funds lock is INFORMATIONAL, not a security issue"
  - "Auto-rebuy dust strengthens invariant (untracked ETH stays in contract)"
  - "Research inventory corrected: 6 decrements (not 5), MintModule:658 was missing"

patterns-established:
  - "Pre-reservation pattern: claimablePool incremented before individual claimableWinnings credits (decimator jackpot)"
  - "Liability delta pattern: _addClaimableEth returns amount to accumulate before batch claimablePool update"

requirements-completed: [ACCT-01]

# Metrics
duration: 7min
completed: 2026-03-06
---

# Phase 04 Plan 02: Invariant Manual Trace Summary

**Complete manual trace of 18 claimablePool mutation sites across 7 modules confirms ACCT-01 PASS: the solvency invariant holds at every transaction boundary**

## Performance

- **Duration:** 7 min
- **Started:** 2026-03-06T19:36:13Z
- **Completed:** 2026-03-06T19:43:22Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments
- Traced all 18 claimablePool sites (6 decrements, 10 increments, 2 read-only guards) with per-site verdicts
- Verified auto-rebuy path end-to-end: take-profit credited to claimablePool, rebuy to prize pools, dust stays untracked
- Documented decimator pre-reservation lifecycle: temporary asymmetry resolves after claims, unclaimed funds safely locked
- Corrected line number references from research to match current source code
- Discovered 6th decrement site (MintModule.sol:658) not in original research inventory

## Task Commits

Each task was committed atomically:

1. **Task 1: Trace all claimablePool mutation sites for symmetry and backing** - `2e73637` (docs)

## Files Created/Modified
- `.planning/phases/04-eth-token-accounting-integrity/04-02-FINDINGS-invariant-manual-trace.md` - Complete per-site analysis with verdicts, open question resolutions, and ACCT-01 PASS verdict

## Decisions Made
- ACCT-01 verdict is PASS based on exhaustive trace of all claimablePool mutation sites
- Decimator unclaimed funds lock classified as INFORMATIONAL (not security): ETH is locked in claimablePool but cannot be exploited
- Auto-rebuy dust classified as INFORMATIONAL: untracked ETH strengthens the invariant
- stETH transfer rounding (Lido 1-2 wei) classified as INFORMATIONAL: contract retains slightly more than owed

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Corrected line number references throughout findings document**
- **Found during:** Task 1
- **Issue:** Research inventory listed line numbers from an older codebase revision (e.g., Game.sol:1081 was actually :1042, JackpotModule.sol:894 was actually :948)
- **Fix:** Updated all line references to match current source via direct verification
- **Files modified:** 04-02-FINDINGS-invariant-manual-trace.md
- **Verification:** Each line number verified against actual grep results

**2. [Rule 2 - Missing Critical] Added 6th decrement site missed by research**
- **Found during:** Task 1
- **Issue:** Research listed 5 decrement sites; exhaustive grep found a 6th at MintModule.sol:658 (lootbox shortfall from claimable)
- **Fix:** Added D6 analysis with full trace, confirmed SAFE
- **Files modified:** 04-02-FINDINGS-invariant-manual-trace.md
- **Verification:** Symmetric decrement verified (claimableWinnings -= shortfall paired with claimablePool -= shortfall)

**3. [Rule 1 - Bug] Corrected GameOverModule I10 entry**
- **Found during:** Task 1
- **Issue:** Research listed "GameOverModule.sol:183,219 -- BAF/Decimator jackpot" but current code has only one claimablePool increment at line 133 (decimator). The BAF terminal jackpot goes through runTerminalJackpot -> JackpotModule._distributeJackpotEth (I7).
- **Fix:** Split I10 into correct scope (decimator only at line 133), documented that BAF game-over path updates claimablePool via I7
- **Files modified:** 04-02-FINDINGS-invariant-manual-trace.md

---

**Total deviations:** 3 auto-fixed (2 bug corrections, 1 missing site)
**Impact on plan:** All corrections necessary for accuracy. Total site count updated from 16 to 18 (6 decrements + 10 increments + 2 read-only). No scope creep.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- ACCT-01 PASS provides baseline confidence for remaining Phase 4 plans
- Decimator pre-reservation analysis feeds into 04-06 (game-over settlement)
- CEI analysis in 04-04 can reference the claimablePool/claimableWinnings state model documented here

---
*Phase: 04-eth-token-accounting-integrity*
*Completed: 2026-03-06*
