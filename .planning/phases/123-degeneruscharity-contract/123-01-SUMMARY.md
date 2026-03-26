---
phase: 123-degeneruscharity-contract
plan: 01
subsystem: contracts
tags: [solidity, soulbound, erc20, governance, burn-redemption, gnrus, charity]

# Dependency graph
requires: []
provides:
  - "DegenerusCharity.sol -- soulbound GNRUS token with burn redemption and sDGNRS governance"
  - "ISDGNRSSnapshot and IDegenerusGameCharity interfaces inline"
  - "Governance: propose/vote/resolveLevel with VAULT standing vote"
affects: [123-02 deploy-pipeline, 123-03 unit-tests, 124 game-integration]

# Tech tracking
tech-stack:
  added: []
  patterns: ["soulbound ERC20 with Transfer events for indexer compat", "per-level sDGNRS-weighted governance with snapshot on first proposal", "proportional dual-asset burn redemption (ETH + stETH)"]

key-files:
  created: ["contracts/DegenerusCharity.sol"]
  modified: []

key-decisions:
  - "Mirrored StakedDegenerusStonk section ordering for codebase consistency"
  - "Fixed variable shadowing in resolveLevel by hoisting start declaration and using block scope for VAULT vote loop"
  - "resolveLevel left permissionless per D-12 -- Phase 124 wires onlyGame"

patterns-established:
  - "Soulbound GNRUS: flat contract, balanceOf/totalSupply, Transfer events, no transfer/approve"
  - "Governance: flat proposal array with per-level start/count tracking"
  - "Burn redemption: proportional share of both ETH and stETH with last-holder sweep"

requirements-completed: [CHAR-01, CHAR-02, CHAR-03, CHAR-04]

# Metrics
duration: 9min
completed: 2026-03-25
---

# Phase 123 Plan 01: DegenerusCharity Contract Summary

**Soulbound GNRUS token (1T supply) with proportional ETH/stETH burn redemption and per-level sDGNRS-weighted governance (propose/vote/resolveLevel)**

## Performance

- **Duration:** 9 min
- **Started:** 2026-03-26T04:16:24Z
- **Completed:** 2026-03-26T04:26:12Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments
- Created DegenerusCharity.sol with full soulbound GNRUS token implementation
- Proportional burn-for-ETH/stETH redemption with last-holder sweep and 1 GNRUS minimum
- Per-level sDGNRS-weighted governance: propose (0.5% threshold + creator 5-cap), vote (approve/reject per proposal), resolveLevel (2% decay distribution)
- VAULT 5% standing vote on every proposal at resolve time
- claimYield() permissionless pull from game contract, receive() for direct ETH deposits
- All 18 acceptance criteria verified passing

## Task Commits

Each task was committed atomically:

1. **Task 1: Create DegenerusCharity.sol with soulbound GNRUS token, burn redemption, and sDGNRS governance** - `e55e82f4` (feat)

## Files Created/Modified
- `contracts/DegenerusCharity.sol` - Soulbound GNRUS token with burn redemption and sDGNRS governance (542 lines)

## Decisions Made
- Mirrored StakedDegenerusStonk.sol section ordering and naming conventions for consistency
- Fixed variable shadowing warning in resolveLevel: hoisted `start` declaration above VAULT vote block and used block scope
- Kept `name`, `symbol`, `decimals`, `steth`, `sdgnrs`, `game` as lowercase constants matching existing codebase convention (forge lint suggestions to uppercase intentionally ignored, matching sDGNRS)
- Left `resolveLevel` permissionless per D-12 -- Phase 124 wires `onlyGame` modifier

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed variable shadowing in resolveLevel**
- **Found during:** Task 1 (contract creation)
- **Issue:** `start` declared inside VAULT vote block shadowed outer `start` at find-winner section, causing Solidity warning
- **Fix:** Hoisted `start` declaration above both blocks, moved `count == 0` early-return before `start` assignment, used block scope for VAULT weight calculation
- **Files modified:** contracts/DegenerusCharity.sol
- **Verification:** `forge build` succeeds with zero DegenerusCharity-specific warnings
- **Committed in:** e55e82f4 (part of Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 bug)
**Impact on plan:** Minor restructuring of resolveLevel for clean compilation. No scope creep.

## Issues Encountered
- Worktree missing node_modules and lib (symlinked from main repo for forge build)
- forge lint suggestions for constant naming (lowercase -> UPPERCASE) intentionally ignored to match existing codebase patterns

## Known Stubs

None -- all functions are fully implemented with real logic.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- DegenerusCharity.sol compiles and is ready for deploy pipeline integration (Plan 02)
- ContractAddresses.sol needs CHARITY address added at nonce N+23 (Plan 02 scope)
- Unit tests can be written against the contract (Plan 03 scope)
- Phase 124 wires game integration (resolveLevel hook, yield routing, allowlist)

## Self-Check: PASSED

- contracts/DegenerusCharity.sol: FOUND
- 123-01-SUMMARY.md: FOUND
- Commit e55e82f4: FOUND

---
*Phase: 123-degeneruscharity-contract*
*Completed: 2026-03-25*
