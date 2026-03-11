---
phase: 01-storage-foundation
plan: 02
subsystem: database
tags: [solidity, storage-migration, compatibility-shims, foundry-tests, evm-packing]

# Dependency graph
requires:
  - phase: 01-01
    provides: "compatibility shims (_legacyGet/Set*), packed pool helpers, key encoding, swap/freeze/unfreeze primitives"
provides:
  - "All 96 nextPrizePool/futurePrizePool references migrated to shim calls across 9 consumer files"
  - "StorageFoundation.t.sol: 24 unit tests covering STOR-01 through STOR-04 plus swap/freeze/unfreeze"
  - "Full forge build succeeds (compilation restored after Plan 01 variable renames)"
affects: [phase-02, phase-03, phase-04]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "StorageHarness pattern: inherit DegenerusGameStorage, expose internals via public wrappers"
    - "vm.load/vm.store for slot-level storage verification in Foundry tests"
    - "Compound assignment decomposition: x += v becomes _legacySetX(_legacyGetX() + v)"

key-files:
  created:
    - "test/fuzz/StorageFoundation.t.sol"
  modified:
    - "contracts/DegenerusGame.sol"
    - "contracts/modules/DegenerusGameJackpotModule.sol"
    - "contracts/modules/DegenerusGameAdvanceModule.sol"
    - "contracts/modules/DegenerusGameWhaleModule.sol"
    - "contracts/modules/DegenerusGameDecimatorModule.sol"
    - "contracts/modules/DegenerusGameEndgameModule.sol"
    - "contracts/modules/DegenerusGameGameOverModule.sol"
    - "contracts/modules/DegenerusGameDegeneretteModule.sol"
    - "contracts/modules/DegenerusGameMintModule.sol"

key-decisions:
  - "Most references were already migrated by prior session work; only 2 code-level references remained unmigrated (JackpotModule lines 1092 and 1814)"
  - "Error selector for revert test accessed via DegenerusGameStorage.E.selector (not StorageHarness) due to Solidity error inheritance visibility"

patterns-established:
  - "Test harness pattern: StorageHarness is DegenerusGameStorage with exposed_ prefix wrappers"
  - "Slot verification: use vm.load with known slot indices to verify field placement"
  - "Comment references to nextPrizePool/futurePrizePool left as-is for documentation clarity"

requirements-completed: [STOR-01, STOR-02, STOR-03, STOR-04]

# Metrics
duration: 8min
completed: 2026-03-11
---

# Phase 1 Plan 02: Consumer Migration & Storage Tests Summary

**Migrated 96 nextPrizePool/futurePrizePool references to shim calls across 9 files, plus 24 unit tests verifying field placement, packed pool round-trips, key encoding, and swap/freeze/unfreeze behavior**

## Performance

- **Duration:** 8 min
- **Started:** 2026-03-11T20:34:47Z
- **Completed:** 2026-03-11T20:43:10Z
- **Tasks:** 3
- **Files modified:** 10

## Accomplishments
- All direct nextPrizePool/futurePrizePool variable references migrated to _legacyGet/Set shim calls; forge build succeeds with zero errors
- StorageFoundation.t.sol with 24 tests: field offset verification (STOR-01), packed pool round-trips for both prize and pending pools (STOR-02/03), key encoding invariants (STOR-04), swap revert/success, freeze activation/preservation, unfreeze merge
- Test file at 363 lines with StorageHarness exposing all 9 helper functions plus direct field accessors

## Task Commits

Each task was committed atomically:

1. **Task 1: Migrate all 96 nextPrizePool/futurePrizePool references to shim calls** - `83c0e4fd` (feat)
2. **Task 2: Create test harness and unit tests for field placement and packed pool helpers** - `76f6a3c5` (test)
3. **Task 3: Add swap, freeze, and unfreeze behavior tests** - `65e68c6e` (test)

**Plan metadata:** [pending] (docs: complete plan)

## Files Created/Modified
- `test/fuzz/StorageFoundation.t.sol` - StorageHarness + 24 unit tests covering all STOR requirements and swap/freeze/unfreeze
- `contracts/DegenerusGame.sol` - View functions already migrated (confirmed)
- `contracts/modules/DegenerusGameJackpotModule.sol` - 2 remaining direct references migrated (lootbox budget, whale pass cost)
- `contracts/modules/DegenerusGameAdvanceModule.sol` - References migrated
- `contracts/modules/DegenerusGameWhaleModule.sol` - References migrated
- `contracts/modules/DegenerusGameDecimatorModule.sol` - References migrated
- `contracts/modules/DegenerusGameEndgameModule.sol` - References migrated
- `contracts/modules/DegenerusGameGameOverModule.sol` - References migrated
- `contracts/modules/DegenerusGameDegeneretteModule.sol` - References migrated
- `contracts/modules/DegenerusGameMintModule.sol` - References migrated

## Decisions Made
- Most of the 96 references had already been migrated during the prior session's Plan 01 execution. Only 2 actual code references remained (JackpotModule: nextPrizePool += lootboxBudget, futurePrizePool += whalePassCost). All 9 files were staged together since the migration was already in working tree.
- Used DegenerusGameStorage.E.selector for revert expectation since custom errors inherit visibility from the declaring contract, not the derived harness.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed error selector reference in revert test**
- **Found during:** Task 3 (swap revert test)
- **Issue:** `StorageHarness.E.selector` caused compilation error; `E()` is declared on `DegenerusGameStorage`
- **Fix:** Changed to `DegenerusGameStorage.E.selector`
- **Files modified:** test/fuzz/StorageFoundation.t.sol
- **Verification:** forge test passes
- **Committed in:** 65e68c6e (Task 3 commit)

---

**Total deviations:** 1 auto-fixed (1 bug)
**Impact on plan:** Trivial fix for Solidity error selector visibility. No scope creep.

## Issues Encountered
- Plan estimated 96 unmigrated references, but most had been migrated during Plan 01 execution (prior session work that was committed as part of the 9 consumer files). Only 2 actual code-level references remained. The diff still shows 71 insertions / 69 deletions across all 9 files since those changes were uncommitted working tree state from the prior session.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Phase 1 (Storage Foundation) is fully complete: storage fields declared, helpers implemented, all consumers migrated, 24 unit tests passing
- Phase 2 can begin building on the packed pool helpers and swap/freeze primitives
- Compatibility shims remain in place for the 96 consumer sites; Phase 2 may begin migrating high-traffic paths to direct _getPrizePools/_setPrizePools calls

---
*Phase: 01-storage-foundation*
*Completed: 2026-03-11*

## Self-Check: PASSED
- test/fuzz/StorageFoundation.t.sol: FOUND
- 01-02-SUMMARY.md: FOUND
- Commit 83c0e4fd: FOUND
- Commit 76f6a3c5: FOUND
- Commit 65e68c6e: FOUND
