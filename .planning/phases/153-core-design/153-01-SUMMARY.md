---
phase: 153-core-design
plan: 01
subsystem: quest-system
tags: [level-quest, eligibility, storage-packing, VRF, creditFlip, mintPacked]

# Dependency graph
requires:
  - phase: 151-flag-impl
    provides: gameOverPossible flag, mintPacked_ layout, advanceGame transition flow
provides:
  - Complete level quest design specification covering eligibility, roll mechanism, targets, progress, storage, and completion
  - Implementer-ready pseudocode for all operations
  - SLOAD/SSTORE gas budget per operation
  - Traceability matrix linking 8 requirements to spec sections
affects: [154-integration-mapping, 155-economic-gas-analysis]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Level-based invalidation (cheaper than version counters for monotonic global state)"
    - "Packed uint256 for per-player quest state (24+128+1 = 153 bits)"
    - "VRF keccak mixing with unique salt for independent entropy derivation"

key-files:
  created:
    - .planning/phases/153-core-design/153-01-LEVEL-QUEST-SPEC.md
  modified: []

key-decisions:
  - "Store quest TYPE only (not target) per level -- targets derive from type + mintPrice at evaluation time, saving 22,100 gas SSTORE per level"
  - "Level-based invalidation over version counters -- levels are monotonic and never re-roll, saving 1 SLOAD per handler invocation"
  - "Activity gate checked FIRST in eligibility -- most players fail here (< 4 units), short-circuiting before the loyalty gate reads"
  - "No ETH target cap for level quests -- daily cap of 0.5 ETH is explicitly not applied"
  - "MINT_ETH uses unified 10x multiplier -- no slot distinction since level quests have only one quest"

patterns-established:
  - "Level quest packed state: bits 0-23 questLevel, bits 24-151 progress, bit 152 completed"
  - "Level quest roll insertion: after _processPhaseTransition, before phaseTransitionActive = false"
  - "Level quest entropy: keccak256(abi.encodePacked(rngWordByDay[day], 'LEVEL_QUEST'))"

requirements-completed: [ELIG-01, ELIG-02, MECH-01, MECH-02, MECH-03, MECH-04, STOR-01, STOR-02]

# Metrics
duration: 12min
completed: 2026-04-01
---

# Phase 153 Plan 01: Level Quest Spec Summary

**536-line design spec covering eligibility (levelStreak/pass + 4 ETH units), global VRF quest roll, 10x targets for 8 types, packed uint256 per-player state with level invalidation, and 800 BURNIE creditFlip completion**

## Performance

- **Duration:** 12 min
- **Started:** 2026-04-01T00:10:26Z
- **Completed:** 2026-04-01T00:22:00Z
- **Tasks:** 2
- **Files created:** 1

## Accomplishments
- Eligibility boolean with exact storage reads (mintPacked_ bits 48-71, 104-127, 128-153, 228-243 + deityPassCount), gas cost (1-2 SLOADs / 2,100-4,200 gas), and copy-pasteable pseudocode
- Global quest roll mechanism specifying exact insertion point in advanceGame (after _processPhaseTransition, before phaseTransitionActive = false), VRF entropy derivation via keccak256 mixing, and reused weight table (21 or 25 total weight)
- Complete 10x target table for all 8 quest types with edge case analysis (DECIMATOR window gaps, ETH price sensitivity, AFFILIATE difficulty)
- Per-player progress storage: packed uint256 (24-bit questLevel + 128-bit progress + 1-bit completed = 153 bits), level-based invalidation, independence from daily quests
- Completion flow: 6-step sequence ending in coinflip.creditFlip(player, 800 ether) with once-per-level guard
- Storage layout summary: 2 new mappings, SLOAD/SSTORE budgets per operation, collision analysis

## Task Commits

Each task was committed atomically:

1. **Task 1: Extract patterns and write spec** - `c68929e2` (feat)
2. **Task 2: Self-review for completeness** - no changes needed (spec was correct)

## Files Created/Modified
- `.planning/phases/153-core-design/153-01-LEVEL-QUEST-SPEC.md` - Complete level quest design specification (536 lines)

## Decisions Made
- Store quest type only (not target) per level: targets are deterministic from type + mintPrice. Saves 22,100 gas SSTORE per level transition.
- Level-based invalidation instead of version counters: levels are monotonic and never re-roll within a level, so comparing questLevel != level is sufficient. Saves 1 SLOAD per handler call.
- Activity gate checked first in eligibility: most players fail the 4-unit threshold, avoiding unnecessary loyalty gate reads.
- No ETH target cap: daily quests cap at 0.5 ether, level quests explicitly do not cap.
- Unified MINT_ETH 10x multiplier: no slot distinction since level quests have one quest, not two slots.

## Deviations from Plan

None -- plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required
None -- no external service configuration required.

## Next Phase Readiness
- Spec is complete and ready for Phase 154 (Integration Mapping)
- Three open design questions documented in Section 8 of the spec for Phase 154 to resolve:
  1. Contract location (DegenerusQuests.sol vs DegenerusGameStorage.sol)
  2. Handler routing (augment existing vs new entry points)
  3. Roll trigger path (via BurnieCoin or direct from AdvanceModule)

## Self-Check: PASSED

- 153-01-LEVEL-QUEST-SPEC.md: FOUND
- 153-01-SUMMARY.md: FOUND
- Commit c68929e2: FOUND

---
*Phase: 153-core-design*
*Completed: 2026-04-01*
