---
phase: 144-contract-scan
plan: 01
subsystem: audit
tags: [solidity, abi-cleanup, static-analysis, forwarding-wrappers, unused-views]

# Dependency graph
requires: []
provides:
  - Categorized ABI cleanup candidate list with forwarding wrappers and unused view/pure functions
  - Completeness proof: every external/public function across 25 contracts accounted for
affects: [145-manual-review, 146-execute-removals]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Forwarding wrapper detection: entire body is single call with identical params, no added logic"
    - "On-chain caller search: grep for contractVar.functionName( across all .sol files"

key-files:
  created:
    - .planning/phases/144-contract-scan/144-01-CANDIDATES.md
  modified: []

key-decisions:
  - "Excluded DegenerusGame delegatecall wrappers from forwarding candidates -- they ARE the public API, not wrappers"
  - "Excluded DegenerusVault game* proxy functions -- all add onlyVaultOwner + parameter transformation"
  - "Excluded BurnieCoin creditFlip/creditFlipBatch -- onlyFlipCreditors access control makes them routing hubs, not pure wrappers"
  - "Identified 3 duplicate view functions (futurePrizePoolView/futurePrizePoolTotalView/rewardPoolView) returning identical value"

patterns-established:
  - "Forwarding wrapper: body is single call to another contract, identical params, no access control/events/state beyond forward"
  - "Unused view: zero cross-contract call sites in any .sol file; functions only consumed off-chain"

requirements-completed: [SCAN-01, SCAN-02, SCAN-03]

# Metrics
duration: 8min
completed: 2026-03-30
---

# Phase 144 Plan 01: Contract Scan Summary

**Systematic ABI sweep of 25 production contracts identifying 8 forwarding wrappers and 54 unused view/pure functions for user review**

## Performance

- **Duration:** 8 min
- **Started:** 2026-03-30T02:46:10Z
- **Completed:** 2026-03-30T02:54:30Z
- **Tasks:** 1
- **Files created:** 1

## Accomplishments
- Scanned all 25 production contracts (~225 external/public functions examined, excluding interface declarations)
- Identified 8 forwarding wrappers: BurnieCoin (4), DegenerusAdmin (2), DegenerusStonk (1), StakedDegenerusStonk (2 overlapping with unused views)
- Identified 54 unused view/pure functions with zero on-chain callers, 36 on DegenerusGame alone
- Found 3 duplicate view functions returning identical _getFuturePrizePool() (futurePrizePoolView, futurePrizePoolTotalView, rewardPoolView)
- Documented why every non-candidate function is NOT a candidate, proving completeness

## Task Commits

1. **Task 1: Scan all production contracts and produce candidate list** - `fe26875b` (feat)

## Files Created/Modified
- `.planning/phases/144-contract-scan/144-01-CANDIDATES.md` - Complete categorized candidate list with forwarding wrappers, unused views, non-candidates proof, and methodology

## Decisions Made
- Excluded Game delegatecall wrappers: they route to modules executing in Game's storage context; removing them removes the public interface
- Excluded Vault game* proxy functions: all add onlyVaultOwner access control and parameter transformation (address(this) substitution, _combinedValue)
- Excluded BurnieCoin creditFlip/creditFlipBatch: onlyFlipCreditors modifier makes them access-control routing hubs called by Affiliate and Game
- Standard ERC20 functions (totalSupply, etc.) noted as candidates but flagged for external tooling expectations

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Known Stubs

None.

## Next Phase Readiness
- 144-01-CANDIDATES.md is ready for Phase 145 manual review gate
- User must review each candidate and decide keep/remove before Phase 146 can proceed
- Forwarding wrappers (8) and unused views (54) are clearly categorized with risk notes

## Self-Check: PASSED

---
*Phase: 144-contract-scan*
*Completed: 2026-03-30*
