---
phase: 57-cross-contract-verification
plan: 02
subsystem: audit
tags: [eth-flow, conservation, solvency, cross-contract, prize-pools, steth, lido]

# Dependency graph
requires:
  - phase: 50-eth-flow-modules
    provides: ETH mutation path maps for AdvanceModule, MintModule, JackpotModule
  - phase: 51-endgame-lifecycle-modules
    provides: ETH mutation path maps for EndgameModule, LootboxModule, GameOverModule
  - phase: 52-whale-player-modules
    provides: ETH mutation path maps for WhaleModule, DegeneretteModule, DecimatorModule, BoonModule
  - phase: 53-module-utilities-libraries
    provides: ETH mutation path maps for PayoutUtils, MintStreakUtils
  - phase: 54-token-economics-contracts
    provides: ETH mutation path maps for Vault, Stonk, BurnieCoin
  - phase: 55-pass-social-interface-contracts
    provides: ETH mutation path maps for Affiliate, DeityPass, Quests, Jackpots
  - phase: 56-admin-support-contracts
    provides: ETH mutation path maps for Admin, WWXRP
provides:
  - Protocol-wide ETH flow map with 72 unique paths
  - ETH conservation proof for all 9 major pools
  - Completeness verification against source code and audit data
affects: [57-cross-contract-verification, 58-synthesis]

# Tech tracking
tech-stack:
  added: []
  patterns: [ETH-entry/internal/exit taxonomy, pool conservation analysis]

key-files:
  created:
    - .planning/phases/57-cross-contract-verification/57-02-eth-flow-map.md
  modified: []

key-decisions:
  - "Classified 17 entry points, 38 internal movements, 17 exit points for complete protocol ETH coverage"
  - "Proxy entry points (Vault/DGNRS/Admin forwarding) documented separately from direct entry points"
  - "stETH conversion via Lido treated as ETH exit (native ETH leaves contract) with value preservation note"

patterns-established:
  - "Entry/Internal/Exit taxonomy: E1-E17, I1-I38, X1-X17 numbering for cross-referencing"
  - "Pool conservation table: entry paths, exit paths, conservation check per pool"

requirements-completed: [XREF-02]

# Metrics
duration: 6min
completed: 2026-03-07
---

# Phase 57 Plan 02: ETH Flow Map Summary

**Protocol-wide ETH flow map tracing 72 unique paths across 14 contracts/modules with zero conservation violations**

## Performance

- **Duration:** 6 min
- **Started:** 2026-03-07T12:43:18Z
- **Completed:** 2026-03-07T12:49:18Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments
- Mapped all 17 ETH entry points across 4 standalone contracts and 10 delegatecall modules
- Traced 38 internal pool-to-pool movements covering prize pools, claimable accounting, yield, game-over, and lootbox flows
- Documented all 17 ETH exit points with source pools, recipient addresses, and trigger conditions
- Created 6 ASCII flow diagrams for major lifecycle paths (mint-to-jackpot, whale pass, game-over, lootbox, yield, affiliate)
- Verified ETH conservation for all 9 major pools with 5 invariants (no creation, no destruction, solvency, pool sum, entry=exit)
- Cross-referenced 100% of Phase 50-56 audit ETH mutation paths against protocol-wide map
- Source code grep confirmed zero undocumented ETH flows

## Task Commits

Each task was committed atomically:

1. **Task 1: Map all ETH entry, internal movement, and exit paths** - `fd848f1` (feat)
2. **Task 2: ETH conservation analysis and completeness verification** - `6e4cb0b` (feat)

## Files Created/Modified
- `.planning/phases/57-cross-contract-verification/57-02-eth-flow-map.md` - Complete protocol-wide ETH flow map with 7 sections

## Decisions Made
- Proxy entry points (Vault gamePurchase, DGNRS gamePurchase, Admin swap relay) listed as separate ETH entry points because they represent distinct external caller interaction paths, even though ETH ultimately flows through the Game contract
- stETH conversions via Lido (autoStakeExcessEth, adminStakeEthForStEth) classified as ETH exits because native ETH physically leaves the contract, with value preservation notes
- BoonModule confirmed as only delegatecall module with zero ETH paths (modifies boon state that affects ETH flows in other modules)

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- ETH flow map complete, providing foundation for solvency verification in subsequent cross-contract plans
- All 72 ETH paths numbered (E1-E17, I1-I38, X1-X17) for cross-referencing in Phase 57 remaining plans
- Conservation invariants documented for Phase 58 synthesis

---
*Phase: 57-cross-contract-verification*
*Completed: 2026-03-07*
