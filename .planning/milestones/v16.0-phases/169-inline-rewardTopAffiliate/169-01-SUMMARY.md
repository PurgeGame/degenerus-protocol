---
phase: 169-inline-rewardTopAffiliate
plan: 01
subsystem: module-consolidation
tags: [solidity, delegatecall, module-elimination, affiliate]

requires:
  - phase: 168-storage-repack
    provides: stable storage layout
provides:
  - AdvanceModule with inlined affiliate reward logic (no delegatecall)
  - AffiliateDgnrsReward event + BPS constants in AdvanceModule
affects: [170-migrate-runRewardJackpots, 171-delete-endgamemodule]

tech-stack:
  added: []
  patterns: [inline delegatecall replacement]

key-files:
  created: []
  modified:
    - contracts/modules/DegenerusGameAdvanceModule.sol

key-decisions:
  - "EndgameModule rewardTopAffiliate left as dead code until Phase 171 deletes the entire module"
  - "IDegenerusGameEndgameModule import retained because _runRewardJackpots still uses it (removed in Phase 170)"

patterns-established: []

requirements-completed: [MOD-01]

duration: 5min
completed: 2026-04-02
---

# Phase 169 Plan 01: Inline rewardTopAffiliate Summary

**Replaced delegatecall wrapper with direct affiliate reward logic in AdvanceModule — one of three EndgameModule dependencies eliminated**

## Performance

- **Duration:** 5 min
- **Started:** 2026-04-03T00:10:00Z
- **Completed:** 2026-04-03T00:15:00Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments

- Replaced `_rewardTopAffiliate` delegatecall wrapper (11 lines) with inlined logic (28 lines)
- Added `AffiliateDgnrsReward` event declaration matching EndgameModule's event
- Added `AFFILIATE_POOL_REWARD_BPS` (100 = 1%) and `AFFILIATE_DGNRS_LEVEL_BPS` (500 = 5%) constants
- Direct calls to `affiliate.affiliateTop`, `dgnrs.poolBalance`, `dgnrs.transferFromPool` — no delegatecall
- `levelDgnrsAllocation[lvl]` write for 5% pool segregation
- All contracts compile cleanly

## Task Commits

1. **Task 1: Inline rewardTopAffiliate** - `9cd1b7f9` (feat)

## Acceptance Criteria Verification

| Check | Result |
|-------|--------|
| No delegatecall in affiliate path | PASS |
| affiliate.affiliateTop call present | PASS |
| AffiliateDgnrsReward event declared + emitted | PASS |
| BPS constants declared + used (4 lines) | PASS |
| levelDgnrsAllocation write present | PASS |
| Direct dgnrs.poolBalance + transferFromPool calls | PASS |
| No EndgameModule ref in affiliate path | PASS |
| forge build succeeds | PASS |

## Deviations from Plan

None.

## Known Stubs

None.

## Self-Check: PASSED

- Modified file exists on disk
- Commit 9cd1b7f9 verified in git log

---
*Phase: 169-inline-rewardTopAffiliate*
*Completed: 2026-04-02*
