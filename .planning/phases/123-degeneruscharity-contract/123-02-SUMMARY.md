---
phase: 123-degeneruscharity-contract
plan: 02
subsystem: infra
tags: [deploy-pipeline, nonce-prediction, foundry, solidity]

# Dependency graph
requires:
  - phase: 123-degeneruscharity-contract
    provides: DegenerusCharity.sol contract and GNRUS constant in ContractAddresses.sol
provides:
  - GNRUS in DEPLOY_ORDER at N+23 for nonce prediction
  - DegenerusCharity deployment in DeployProtocol.sol (Foundry test helper)
  - GNRUS address assertion in DeployCanary.t.sol
  - patchForFoundry.js CLI output updated for 24-contract protocol
affects: [124-gnrus-funding-wiring, foundry-tests]

# Tech tracking
tech-stack:
  added: []
  patterns: [24-contract deployment sequence, nonce 29 for GNRUS]

key-files:
  modified:
    - scripts/lib/predictAddresses.js
    - scripts/lib/patchForFoundry.js
    - test/fuzz/helpers/DeployProtocol.sol
    - test/fuzz/DeployCanary.t.sol

key-decisions:
  - "GNRUS deployed at N+23 (nonce 29) -- last in deploy order, no constructor cross-calls"

patterns-established:
  - "24-contract protocol: all pipeline files updated from 23 to 24"

requirements-completed: []

# Metrics
duration: 2min
completed: 2026-03-26
---

# Phase 123 Plan 02: Deploy Pipeline Summary

**GNRUS (DegenerusCharity) added to deploy pipeline at nonce N+23 -- predictAddresses, patchForFoundry, DeployProtocol, DeployCanary all updated for 24-contract protocol**

## Performance

- **Duration:** 2 min
- **Started:** 2026-03-26T05:18:18Z
- **Completed:** 2026-03-26T05:20:41Z
- **Tasks:** 4
- **Files modified:** 4

## Accomplishments
- GNRUS added to DEPLOY_ORDER and KEY_TO_CONTRACT in predictAddresses.js at position N+23
- patchForFoundry.js CLI output updated to show GNRUS as last contract instead of ADMIN
- DeployProtocol.sol deploys DegenerusCharity at nonce 29 with import, state var, and constructor call
- DeployCanary.t.sol verifies GNRUS address matches patched ContractAddresses.GNRUS constant

## Task Commits

Each task was committed atomically:

1. **Task 1: predictAddresses.js** - `fc835535` (feat)
2. **Task 2: patchForFoundry.js** - `99443181` (feat)
3. **Task 3: DeployProtocol.sol** - `249563d9` (feat)
4. **Task 4: DeployCanary.t.sol** - `8b7f765b` (feat)

## Files Created/Modified
- `scripts/lib/predictAddresses.js` - GNRUS at N+23 in DEPLOY_ORDER + KEY_TO_CONTRACT mapping
- `scripts/lib/patchForFoundry.js` - CLI output last-contract changed from ADMIN to GNRUS
- `test/fuzz/helpers/DeployProtocol.sol` - Import, state var, deployment at nonce 29
- `test/fuzz/DeployCanary.t.sol` - Address match + code existence assertions for GNRUS

## Decisions Made
- GNRUS deployed last (N+23) since its constructor only self-mints 1T tokens with no cross-contract calls. All ContractAddresses references (STETH_TOKEN, SDGNRS, GAME, VAULT) are compile-time constants, not constructor dependencies.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] ContractAddresses.sol GNRUS constant and DegenerusCharity.sol**
- **Found during:** Task 3 (DeployProtocol.sol)
- **Issue:** This worktree lacked the GNRUS constant in ContractAddresses.sol and the DegenerusCharity.sol contract file, both needed for DeployProtocol.sol to compile
- **Fix:** Added GNRUS constant to worktree's ContractAddresses.sol and copied DegenerusCharity.sol from main repo. These files were not committed (contract commit guard) -- they exist in the main repo's commit e4833ac7.
- **Files modified:** contracts/ContractAddresses.sol, contracts/DegenerusCharity.sol (unstaged in worktree)
- **Verification:** DeployProtocol.sol import path resolves correctly

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** Necessary prerequisite for compilation. Contract files already committed in main repo.

## Issues Encountered
- Contract commit guard prevented committing contracts/ files directly. This is expected -- the contract files (DegenerusCharity.sol, ContractAddresses.sol with GNRUS) were already committed in the main repo by the parallel agent (commit e4833ac7). Only test/script infrastructure committed here.

## Known Stubs
None -- all pipeline files are fully wired.

## Next Phase Readiness
- Deploy pipeline ready for 24-contract protocol once worktrees merge
- DeployCanary test will validate GNRUS nonce prediction after patchForFoundry runs
- Phase 124 (GNRUS funding wiring) can proceed to wire ETH/stETH distributions

## Self-Check: PASSED

All 4 modified files exist. All 4 task commits verified in git log.

---
*Phase: 123-degeneruscharity-contract*
*Completed: 2026-03-26*
