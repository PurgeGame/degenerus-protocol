---
phase: 171-delete-endgamemodule
plan: 01
subsystem: modules
tags: [solidity, delegatecall, module-graph, cleanup]

# Dependency graph
requires:
  - phase: 169-inline-rewardTopAffiliate
    provides: "rewardTopAffiliate inlined into AdvanceModule"
  - phase: 170-migrate-runRewardJackpots
    provides: "runRewardJackpots migrated to JackpotModule"
provides:
  - "claimWhalePass in WhaleModule via delegatecall"
  - "EndgameModule fully deleted (contract + interface)"
  - "Zero stale EndgameModule references in contracts/"
affects: [deploy-scripts, contract-addresses]

# Tech tracking
tech-stack:
  added: []
  patterns: ["NonceBurner placeholder for deleted module in test deploy"]

key-files:
  created: []
  modified:
    - contracts/modules/DegenerusGameWhaleModule.sol
    - contracts/interfaces/IDegenerusGameModules.sol
    - contracts/DegenerusGame.sol
    - contracts/modules/DegenerusGameAdvanceModule.sol
    - contracts/modules/DegenerusGameJackpotModule.sol
    - contracts/storage/DegenerusGameStorage.sol
    - test/fuzz/helpers/DeployProtocol.sol
    - test/fuzz/DeployCanary.t.sol
    - test/fuzz/BafRebuyReconciliation.t.sol

key-decisions:
  - "NonceBurner empty contract replaces EndgameModule in fuzz test deploy to preserve nonce ordering"
  - "Stale JackpotModule NatSpec (line 242) referencing EndgameModule was in JackpotModule not WhaleModule as plan stated"

patterns-established:
  - "NonceBurner pattern: when deleting a nonce-positioned module, deploy an empty contract to preserve all subsequent nonce-derived addresses"

requirements-completed: [MOD-03, MOD-04, MOD-05, MOD-06]

# Metrics
duration: 12min
completed: 2026-04-03
---

# Phase 171 Plan 01: Delete EndgameModule Summary

**claimWhalePass moved to WhaleModule, EndgameModule deleted, all references scrubbed across 9 files**

## Performance

- **Duration:** 12 min
- **Started:** 2026-04-03T01:23:27Z
- **Completed:** 2026-04-03T01:35:30Z
- **Tasks:** 3
- **Files modified:** 9

## Accomplishments
- Moved claimWhalePass (function + WhalePassClaimed event) from EndgameModule to WhaleModule with identical behavior
- Rewired DegenerusGame._claimWhalePassFor delegatecall from GAME_ENDGAME_MODULE to GAME_WHALE_MODULE
- Deleted DegenerusGameEndgameModule.sol entirely (576 lines removed)
- Deleted IDegenerusGameEndgameModule interface from IDegenerusGameModules.sol
- Scrubbed all EndgameModule references from imports, module comment blocks, and NatSpec across 6 contract files
- Updated fuzz test deploy helper with NonceBurner placeholder to preserve nonce ordering
- All contracts compile cleanly; WhaleModule at 11,649 bytes (12,927 byte margin)

## Task Commits

Each task was committed atomically:

1. **Task 1: Move claimWhalePass to WhaleModule + update interface** - `5d8a9b44` (feat)
2. **Task 2: Rewire delegatecall + delete EndgameModule + scrub references** - `617c1b20` (feat)
3. **Task 3: Compile verification + test helper fixes** - `802810d5` (chore)

## Files Created/Modified
- `contracts/modules/DegenerusGameWhaleModule.sol` - Added WhalePassClaimed event + claimWhalePass function
- `contracts/interfaces/IDegenerusGameModules.sol` - Added claimWhalePass to IDegenerusGameWhaleModule, deleted IDegenerusGameEndgameModule
- `contracts/DegenerusGame.sol` - Rewired _claimWhalePassFor to GAME_WHALE_MODULE, removed EndgameModule import + comment
- `contracts/modules/DegenerusGameAdvanceModule.sol` - Removed EndgameModule import + comment line
- `contracts/modules/DegenerusGameJackpotModule.sol` - Fixed stale NatSpec referencing EndgameModule
- `contracts/storage/DegenerusGameStorage.sol` - Removed EndgameModule from module list comment
- `contracts/modules/DegenerusGameEndgameModule.sol` - DELETED
- `test/fuzz/helpers/DeployProtocol.sol` - Replaced EndgameModule with NonceBurner
- `test/fuzz/DeployCanary.t.sol` - Updated assertion for endgameModuleSlot
- `test/fuzz/BafRebuyReconciliation.t.sol` - Fixed stale NatSpec comments

## Decisions Made
- Used NonceBurner empty contract in fuzz test deploy to preserve nonce ordering (EndgameModule was at nonce 12; removing it would shift all subsequent addresses)
- Fixed stale JackpotModule NatSpec at line 242 that referenced EndgameModule (plan listed WhaleModule line 242 but the reference was actually in JackpotModule)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Fixed fuzz test compilation failure from deleted EndgameModule import**
- **Found during:** Task 3 (Compile verification)
- **Issue:** test/fuzz/helpers/DeployProtocol.sol imported the deleted DegenerusGameEndgameModule.sol, causing forge build to fail
- **Fix:** Removed import, replaced DegenerusGameEndgameModule variable with address placeholder, deployed NonceBurner empty contract at nonce 12 to preserve address ordering
- **Files modified:** test/fuzz/helpers/DeployProtocol.sol, test/fuzz/DeployCanary.t.sol, test/fuzz/BafRebuyReconciliation.t.sol
- **Verification:** forge build succeeds with 0 errors
- **Committed in:** 802810d5

**2. [Rule 1 - Bug] Fixed stale NatSpec in JackpotModule referencing EndgameModule**
- **Found during:** Task 2 (Scrub all references)
- **Issue:** DegenerusGameJackpotModule.sol line 242 referenced "EndgameModule" as a caller of runTerminalJackpot. Plan listed this as WhaleModule line 242 but it was actually in JackpotModule.
- **Fix:** Updated NatSpec to "from JackpotModule (runRewardJackpots) and GameOverModule"
- **Files modified:** contracts/modules/DegenerusGameJackpotModule.sol
- **Verification:** grep confirms zero EndgameModule references in contracts/ (excluding ContractAddresses.sol)
- **Committed in:** 617c1b20

---

**Total deviations:** 2 auto-fixed (1 blocking, 1 bug)
**Impact on plan:** Both auto-fixes necessary for compilation and correctness. No scope creep.

## Issues Encountered
None beyond the deviations above.

## User Action Required

**GAME_ENDGAME_MODULE in ContractAddresses.sol (line 16):** This constant still exists per project convention (ContractAddresses.sol is user-managed). Remove the `GAME_ENDGAME_MODULE` constant when ready.

**Stale JS references (non-blocking):**
- `scripts/lib/predictAddresses.js` line 55: `GAME_ENDGAME_MODULE: "DegenerusGameEndgameModule"` -- address prediction mapping
- `test/helpers/deployFixture.js` line 138: `endgameModule: contracts.GAME_ENDGAME_MODULE` -- JS test fixture

These reference the ContractAddresses constant (not the deleted .sol file) and do not affect Solidity compilation.

## Contract Sizes

| Contract | Runtime (B) | Margin (B) |
|---|---|---|
| DegenerusGameWhaleModule | 11,649 | 12,927 |
| DegenerusGameJackpotModule | 24,212 | 364 |

## Known Stubs
None -- all functionality is fully wired.

## Next Phase Readiness
- EndgameModule fully eliminated from the module graph
- Module count reduced by 1 deployment address
- User must clean up ContractAddresses.sol and JS scripts when ready

## Self-Check: PASSED

All 9 modified files confirmed present. Deleted file confirmed absent. All 3 commit hashes verified in git log.

---
*Phase: 171-delete-endgamemodule*
*Completed: 2026-04-03*
