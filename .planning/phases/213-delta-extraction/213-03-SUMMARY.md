---
phase: 213-delta-extraction
plan: 03
subsystem: audit
tags: [cross-module-interaction-map, delta-extraction, scope-definition, delegatecall, pool-accounting, rng]

# Dependency graph
requires:
  - phase: 213-01
    provides: "Module and storage function-level changelog"
  - phase: 213-02
    provides: "Core contract function-level changelog"
provides:
  - "Cross-module interaction map with 99 categorised call chains (56 SM, 20 EF, 11 RNG, 12 RO)"
  - "Unified delta extraction document as single entry point for all audit scope"
  - "Concrete scope definitions for Phase 214 (adversarial), 215 (RNG), 216 (pool accounting)"
affects: [214-adversarial-audit, 215-rng-fresh-eyes, 216-pool-eth-accounting]

# Tech tracking
tech-stack:
  added: []
  patterns: ["Chain ID tagging (SM-XX, EF-XX, RNG-XX, RO-XX) for cross-referencing in downstream audits"]

key-files:
  created:
    - ".planning/phases/213-delta-extraction/213-DELTA-EXTRACTION.md"
  modified: []

key-decisions:
  - "Categorised chains into 4 groups mapping to downstream phases: state-mutation (214), ETH-flow (216), RNG (215), read-only (lower priority)"
  - "Mapped delegatecall + self-call + external call mechanisms separately to capture reentrancy boundaries"
  - "Included the new Game.runBafJackpot() self-call pattern (AdvanceModule delegatecall -> Game self-call -> JackpotModule delegatecall) as a distinct architectural interaction requiring audit"

patterns-established:
  - "Chain ID convention: SM-XX for state-mutation, EF-XX for ETH-flow, RNG-XX for RNG, RO-XX for read-only"
  - "Scope definitions reference chain IDs so downstream phases can trace back to this extraction"

requirements-completed: [DELTA-03]

# Metrics
duration: 7min
completed: 2026-04-10
---

# Phase 213 Plan 03: Cross-Module Interaction Map Summary

**99 cross-module call chains mapped and categorised across 4 audit-relevant groups, with concrete scope definitions for adversarial (214), RNG (215), and pool accounting (216) audit phases**

## Performance

- **Duration:** 7 min
- **Started:** 2026-04-10T21:29:27Z
- **Completed:** 2026-04-10T21:36:29Z
- **Tasks:** 1
- **Files created:** 1

## Accomplishments
- Built complete cross-module interaction map: 56 state-mutation chains, 20 ETH-flow chains, 11 RNG chains, 12 read-only chains
- Identified key architectural patterns requiring audit attention: EndgameModule elimination redistribution, pool consolidation write batching, two-call jackpot split mid-execution state, GNRUS integration points
- Created concrete scope definitions listing every changed function and chain ID for Phase 214, 215, and 216 planners

## Task Commits

Each task was committed atomically:

1. **Task 1: Build cross-module interaction map from changelogs and contract source** - `d92d9ecb` (docs)

**Plan metadata:** [pending final commit]

## Files Created/Modified
- `.planning/phases/213-delta-extraction/213-DELTA-EXTRACTION.md` - Unified delta extraction document with interaction map, summary statistics, architectural impact narrative, and downstream scope definitions

## Decisions Made
- Categorised all chains into 4 groups that directly map to the 3 downstream audit phases plus a read-only bucket. State-mutation chains (SM) target Phase 214 adversarial audit. ETH-flow chains (EF) target Phase 216 pool accounting. RNG chains target Phase 215 fresh-eyes audit. Read-only chains are lower priority but tracked for completeness.
- Mapped the new self-call pattern (Game.runBafJackpot) as a distinct chain because it introduces a delegatecall -> self-call -> delegatecall nesting that crosses reentrancy boundaries differently than a simple delegatecall.
- Included GNRUS interactions (burn redemption pulling from game.claimWinnings, pickCharity at level transitions, burnAtGameOver) as new ETH-flow chains since GNRUS is an entirely new contract with ETH/stETH custody.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Phase 213 (Delta Extraction) is now complete: all 3 plans delivered
- The unified document `213-DELTA-EXTRACTION.md` serves as the single scope reference for Phase 214, 215, and 216 planners
- Phases 214 (adversarial), 215 (RNG fresh eyes), and 216 (pool accounting) can now proceed in parallel per the roadmap

## Self-Check: PASSED

- FOUND: `.planning/phases/213-delta-extraction/213-DELTA-EXTRACTION.md`
- FOUND: `.planning/phases/213-delta-extraction/213-03-SUMMARY.md`
- FOUND: commit `d92d9ecb`

---
*Phase: 213-delta-extraction*
*Completed: 2026-04-10*
