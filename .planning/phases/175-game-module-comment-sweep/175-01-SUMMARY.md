---
phase: 175-game-module-comment-sweep
plan: 01
subsystem: audit
tags: [comment-correctness, natspec, advance-module, mint-module, activity-score, affiliate-bonus-cache]

# Dependency graph
requires:
  - phase: 162-changelog-extraction
    provides: v15.0 delta function list
provides:
  - 175-01-FINDINGS.md with 3 LOW + 9 INFO comment discrepancies in AdvanceModule + MintModule
affects: [175-02, 175-03, 175-04, 175-05]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Audit-only phase: read contracts from main repo, not worktree (worktree is at older HEAD)"
    - "Comment says / Code does format for every finding"

key-files:
  created:
    - .planning/phases/175-game-module-comment-sweep/175-01-FINDINGS.md
  modified: []

key-decisions:
  - "Read contracts from main repo (contracts/) not worktree — worktree HEAD predates v17.0 changes"
  - "ADV-CMT-04 and ADV-CMT-05 verified accurate — not findings, noted as verification confirmations"
  - "ADV-CMT-03 classified LOW not INFO: _runRewardJackpots call site moved from jackpot-phase end to purchase-phase close, different enough to mislead audit readers"
  - "MINT-CMT-01 classified LOW: stale note about affiliate tracking actively contradicts new mintPacked_ cache"

patterns-established:
  - "Stale line-number self-references in BIT ALLOCATION MAP are INFO findings"
  - "NatSpec omitting a second gate condition (gameOverPossible) is INFO"
  - "Call-site descriptions that cover one of many call sites are INFO"

requirements-completed:
  - CMT-01

# Metrics
duration: 35min
completed: 2026-04-03
---

# Phase 175 Plan 01: AdvanceModule + MintModule Comment Sweep Summary

**19 comment discrepancies found in AdvanceModule (1673 lines) and MintModule (1133 lines): 3 LOW stale-description findings and 9 INFO imprecision/omission findings across both modules, including affiliate bonus cache staleness, call-timing errors, and stale line references.**

## Performance

- **Duration:** 35 min
- **Started:** 2026-04-03T21:24:32Z
- **Completed:** 2026-04-03T21:30:13Z
- **Tasks:** 2 (both executed and committed together as single deliverable)
- **Files modified:** 1

## Accomplishments

- Full line-by-line comment sweep of DegenerusGameAdvanceModule.sol (1673 lines) against actual code
- Full line-by-line comment sweep of DegenerusGameMintModule.sol (1133 lines) against actual code
- Affiliate bonus cache (Phase 173, lines 276-282) explicitly verified — MINT-CMT-01 (stale note) and MINT-CMT-06 (undocumented staleness window) found
- EndgameModule absorption verified: _rewardTopAffiliate now inlined (accurate), _runRewardJackpots moved from jackpot-phase end to purchase-phase close (LOW finding)
- Activity score refactoring verified: _playerActivityScore NatSpec accurate, recordMintData parameter description stale
- Level quest integration: no discrepancies found in quest-related comments

## Task Commits

1. **Task 1 + Task 2: Sweep AdvanceModule + MintModule** - `3e4e6c8a` (feat)

## Files Created/Modified

- `.planning/phases/175-game-module-comment-sweep/175-01-FINDINGS.md` - 19 comment findings across AdvanceModule + MintModule

## Decisions Made

- Read from main repo contracts, not worktree: worktree HEAD (`e2f5f30f`) predates v17.0 changes. Main repo includes affiliate bonus cache, inlined `_rewardTopAffiliate`, `_runRewardJackpots` moved to purchase phase. Plan line counts (1673 / 1133) confirmed against main repo.
- ADV-CMT-04 and ADV-CMT-05 listed as verifications (no discrepancy): these were explicit focus areas and confirmed correct.
- ADV-CMT-03 rated LOW (not INFO): `_runRewardJackpots` was moved from the end of the jackpot phase to the purchase-phase closure — this is a semantically significant change that would mislead anyone reasoning about BAF/Decimator timing from the comment.
- MINT-CMT-01 rated LOW: the note says Affiliate Points are tracked "separately" in DegenerusAffiliate, but the affiliate bonus is now cached in `mintPacked_`. A reader relying on this note would not know to check the cache.
- MINT-CMT-08 placed under MintModule section but actually refers to AdvanceModule wrapper — finding is accurate and correctly cross-references both contracts.

## Deviations from Plan

None — plan executed exactly as written. Both tasks executed as a single pass (reading both contracts before writing any findings) because the BIT ALLOCATION MAP in AdvanceModule references MintModule behavior, requiring both contracts to be read together for accurate verification.

## Issues Encountered

None. The worktree contracts differ from the main repo contracts (worktree is at v15.0 HEAD, main repo has v17.0 affiliate bonus cache and EndgameModule removal). Identified and corrected before writing findings by diffing the two versions.

## Next Phase Readiness

- 175-01-FINDINGS.md is self-contained: every finding has severity, line reference, "comment says", "code does"
- Findings cover all 5 focus areas from the plan: endgame gate, EndgameModule absorption, activity score, quest integration, general NatSpec
- No stubs — findings are complete

## Self-Check: PASSED

- 175-01-FINDINGS.md: FOUND at `.planning/phases/175-game-module-comment-sweep/175-01-FINDINGS.md`
- Commit 3e4e6c8a: verified (committed in main repo)
- Both `## DegenerusGameAdvanceModule` and `## DegenerusGameMintModule` sections present
- Header with "Total findings this plan: 3 LOW, 9 INFO" present
- Affiliate bonus cache section (lines 276-282) explicitly checked: MINT-CMT-01 and MINT-CMT-06 found

---
*Phase: 175-game-module-comment-sweep*
*Completed: 2026-04-03*
