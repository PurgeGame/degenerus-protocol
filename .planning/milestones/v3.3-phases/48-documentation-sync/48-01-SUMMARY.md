---
phase: 48-documentation-sync
plan: 01
subsystem: documentation
tags: [natspec, solidity, error-names, vrf, bit-allocation]

# Dependency graph
requires:
  - phase: 44-redemption-delta
    provides: "CP-08, CP-06, Seam-1, CP-07 code fixes requiring doc sync"
  - phase: 45-invariant-test-suite
    provides: "Code fixes applied to contracts, test infrastructure"
provides:
  - "Correct error names matching access control semantics (DOC-03)"
  - "VRF bit allocation map documenting all RNG word consumers (DOC-02)"
  - "Verified NatSpec across 6 changed files matching post-fix implementation (DOC-01)"
affects: [48-documentation-sync, audit-docs]

# Tech tracking
tech-stack:
  added: []
  patterns: ["@custom:reverts tags for documenting revert conditions"]

key-files:
  created: []
  modified:
    - contracts/BurnieCoinflip.sol
    - contracts/interfaces/IBurnieCoinflip.sol
    - contracts/modules/DegenerusGameAdvanceModule.sol
    - contracts/StakedDegenerusStonk.sol
    - contracts/DegenerusStonk.sol
    - contracts/interfaces/IStakedDegenerusStonk.sol
    - test/unit/BurnieCoinflip.test.js

key-decisions:
  - "Kept OnlyBurnieCoin error for legitimate BurnieCoin modifier uses; added separate OnlyStakedDegenerusStonk error"
  - "Added @custom:reverts NotApproved to claimCoinflips interface since _resolvePlayer now uses NotApproved"
  - "Added NatSpec to rngGate() function which had no documentation despite being a critical entry point"

patterns-established:
  - "@custom:reverts tag pattern for documenting revert conditions on interface and implementation functions"
  - "CP-XX fix references in @dev NatSpec for traceability to audit findings"

requirements-completed: [DOC-01, DOC-02, DOC-03]

# Metrics
duration: 11min
completed: 2026-03-21
---

# Phase 48 Plan 01: Documentation Sync Summary

**Error rename (OnlyBurnieCoin to semantic names), VRF bit allocation map above rngGate, and full NatSpec verification across 6 changed files with CP-08/CP-06/Seam-1 traceability**

## Performance

- **Duration:** 11 min
- **Started:** 2026-03-21T05:24:38Z
- **Completed:** 2026-03-21T05:35:38Z
- **Tasks:** 2
- **Files modified:** 7

## Accomplishments

- Renamed misleading OnlyBurnieCoin error: claimCoinflipsForRedemption now uses OnlyStakedDegenerusStonk, _resolvePlayer now uses NotApproved
- Added comprehensive VRF bit allocation map comment (15 lines) above rngGate documenting all 10 RNG word consumers with their operations and source locations
- Verified and corrected NatSpec across all 6 files changed by Phase 44/45 code fixes, adding @custom:reverts tags, CP-08 deduction documentation, roll range 25-175, and GameNotOver documentation

## Task Commits

Each task was committed atomically:

1. **Task 1: Error rename (DOC-03) + bit allocation map (DOC-02)** - `45d73859` (fix)
2. **Task 2: NatSpec verification and correction across 6 changed files (DOC-01)** - `5adbda9e` (docs)

## Files Created/Modified

- `contracts/BurnieCoinflip.sol` - Added OnlyStakedDegenerusStonk error, renamed reverts in claimCoinflipsForRedemption and _resolvePlayer
- `contracts/interfaces/IBurnieCoinflip.sol` - Updated NatSpec with @custom:reverts OnlyStakedDegenerusStonk and NotApproved
- `contracts/modules/DegenerusGameAdvanceModule.sol` - Added BIT ALLOCATION MAP comment, NatSpec on rngGate and _gameOverEntropy
- `contracts/StakedDegenerusStonk.sol` - Added @custom:reverts BurnsBlockedDuringRng, CP-08 deduction docs, roll range, supply cap docs
- `contracts/DegenerusStonk.sol` - Added @custom:reverts GameNotOver and Seam-1 context to burn()
- `contracts/interfaces/IStakedDegenerusStonk.sol` - Added hasPendingRedemptions and resolveRedemptionPeriod interface declarations
- `test/unit/BurnieCoinflip.test.js` - Updated test assertion from OnlyBurnieCoin to NotApproved

## Decisions Made

- Kept OnlyBurnieCoin error declaration and its use in the onlyBurnieCoin modifier (line 204) since those are legitimate BurnieCoin access checks
- Added @custom:reverts NotApproved to IBurnieCoinflip.claimCoinflips since _resolvePlayer now uses NotApproved for unapproved operators
- Added NatSpec to the previously undocumented rngGate() function describing its role in daily RNG processing
- Included IStakedDegenerusStonk.sol interface update (hasPendingRedemptions + resolveRedemptionPeriod) as it was a pre-existing uncommitted change required for compilation

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed malformed NatSpec comment on consumeCoinflipsForBurn**
- **Found during:** Task 2 (NatSpec verification)
- **Issue:** Line 363 of BurnieCoinflip.sol had a malformed `/// @dev` comment (rendering issue in grep output, but verified correct via cat -A)
- **Fix:** Verified the comment was actually well-formed (3 slashes present); no fix needed
- **Files modified:** None
- **Verification:** cat -A confirmed UTF-8 em-dash, not malformed comment

**2. [Rule 2 - Missing Critical] Added @custom:reverts NotApproved to claimCoinflips interface**
- **Found during:** Task 2 (NatSpec verification)
- **Issue:** IBurnieCoinflip.claimCoinflips lacked @custom:reverts NotApproved despite _resolvePlayer now using that error
- **Fix:** Added `@custom:reverts NotApproved If caller is not the player and not an approved operator`
- **Files modified:** contracts/interfaces/IBurnieCoinflip.sol
- **Verification:** forge build passes
- **Committed in:** 5adbda9e (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 missing critical NatSpec)
**Impact on plan:** Auto-fix was necessary for NatSpec completeness. No scope creep.

## Issues Encountered

- 9 pre-existing Foundry test failures (AffiliatePayout E() errors, StorageFoundation slot test) confirmed unrelated to this plan's changes by testing against the base branch

## Known Stubs

None - all changes are documentation/NatSpec corrections with no stub patterns.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- All NatSpec on the 6 changed files verified correct for post-fix implementation
- Error names now match semantic access control meaning throughout BurnieCoinflip
- VRF bit allocation map provides warden-readable documentation of RNG word usage
- Ready for Phase 48 Plan 02 (audit doc sync)

## Self-Check: PASSED

All 7 modified files exist. Both task commits (45d73859, 5adbda9e) verified in git log. SUMMARY.md created.

---
*Phase: 48-documentation-sync*
*Completed: 2026-03-21*
