---
phase: 167-integration-test-baseline
plan: 01
subsystem: testing
tags: [call-graph, cross-contract, interface-verification, stale-reference-audit]

# Dependency graph
requires:
  - phase: 162-changelog-extraction
    provides: Complete list of 36 removed/renamed/re-signed symbols from v11.0-v14.0
provides:
  - Cross-contract call graph verification report (36 symbol checks + 5 interface checks)
  - Compiler confirmation (Hardhat + Foundry both pass)
affects: [167-integration-test-baseline]

# Tech tracking
tech-stack:
  added: []
  patterns: [systematic-grep-audit, interface-implementation-consistency-check]

key-files:
  created:
    - .planning/phases/167-integration-test-baseline/167-01-CALL-GRAPH-AUDIT.md
  modified: []

key-decisions:
  - "BurnieCoinflip _questApplyReward and onlyDegenerusGameContract are independent symbols not in BurnieCoin rename scope"
  - "DailyQuestRolled event was eliminated entirely (not relocated) -- no event emission for quest rolling in new architecture"
  - "_activeTicketLevel correctly resolves via inheritance from MintStreakUtils"
  - "handleLootBox has no standalone callers -- lootbox quest handling routed through handlePurchase"

patterns-established:
  - "Symbol audit: grep -rn excluding comment-only lines, verify definition site vs call site"

requirements-completed: [INTEG-01]

# Metrics
duration: 12min
completed: 2026-04-02
---

# Phase 167 Plan 01: Call Graph Audit Summary

**36 removed/renamed symbols verified CLEAN across all contracts, 5 interface consistency checks PASS, both compilers confirm zero broken references**

## Performance

- **Duration:** 12 min
- **Started:** 2026-04-02T15:07:31Z
- **Completed:** 2026-04-02T15:19:44Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments
- All 36 removed/renamed/re-signed symbols from 162-CHANGELOG verified with zero stale references in production code
- 5 interface files verified consistent with implementations (IDegenerusCoin, IDegenerusGame, IDegenerusQuests, IDegenerusGameModules, ContractAddresses)
- Hardhat compilation: 61 files compiled successfully; Foundry compilation: pass (no changes)
- Detailed findings documented for 6 symbols requiring nuanced analysis (BurnieCoinflip _questApplyReward, _activeTicketLevel inheritance, DailyQuestRolled elimination, QuestCompleted relocation, onlyDegenerusGameContract scope, parameter count changes)

## Task Commits

Each task was committed atomically:

1. **Task 1: Verify no stale references to removed functions** - `ac8c813c` (feat)
2. **Task 2: Verify interface-implementation consistency** - `ec56ce42` (feat)

## Files Created/Modified
- `.planning/phases/167-integration-test-baseline/167-01-CALL-GRAPH-AUDIT.md` - Cross-contract call graph verification report with 36 symbol checks, 5 interface checks, and compilation results

## Decisions Made
- BurnieCoinflip.sol retains its own `_questApplyReward` (line 1095) and `onlyDegenerusGameContract` (line 187) -- these are independent implementations in a separate contract, not stale references to the removed BurnieCoin versions
- `DailyQuestRolled` event was eliminated entirely in the codebase (not relocated to DegenerusQuests) -- quest rolling no longer emits a dedicated event
- `handleLootBox` has no standalone callers post-v14.0; lootbox quest handling is routed through the combined `handlePurchase` entry point
- `_activeTicketLevel` calls in DegenerusGame.sol resolve through inheritance from DegenerusGameMintStreakUtils (no local definition needed)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Worktree behind main branch -- merged to get v13.0/v14.0 contract changes**
- **Found during:** Task 1
- **Issue:** Worktree was at commit 1019f928 (v12.0 era) while main was at 53e3a1b9 (v14.0 era). All 36 symbols showed as still present because the v13.0/v14.0 removals had not been applied.
- **Fix:** Merged main into worktree to get the committed contract state
- **Files modified:** All contracts updated to match main branch
- **Verification:** Re-ran all 36 grep checks, all CLEAN

---

**Total deviations:** 1 auto-fixed (Rule 3 - blocking)
**Impact on plan:** Necessary to get the correct contract state for auditing. No scope creep.

## Issues Encountered
- Foundry initially failed to find node_modules (worktree missing symlink); resolved by symlinking to main repo's node_modules

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Call graph verification complete; ready for integration test suite development (167-02)
- All cross-contract interfaces verified consistent -- test harness can safely import all interfaces

## Self-Check: PASSED

- 167-01-CALL-GRAPH-AUDIT.md: FOUND
- 167-01-SUMMARY.md: FOUND
- Commit ac8c813c (Task 1): FOUND
- Commit ec56ce42 (Task 2): FOUND
- 47 CLEAN verdicts in audit report
- 27 PASS verdicts in interface checks

---
*Phase: 167-integration-test-baseline*
*Completed: 2026-04-02*
