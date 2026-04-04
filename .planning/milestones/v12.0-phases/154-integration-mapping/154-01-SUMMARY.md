---
phase: 154-integration-mapping
plan: 01
subsystem: documentation
tags: [integration-map, level-quests, quest-handlers, cross-contract-calls]

# Dependency graph
requires:
  - phase: 153-core-design
    provides: Level quest design spec (eligibility, mechanics, storage, completion flow)
provides:
  - Complete integration map identifying all contract touchpoints for level quest implementation
  - Handler site inventory with per-handler tracking specifications
  - Resolved open design questions from Phase 153 (contract location, handler routing, roll trigger path)
  - Reward payout path analysis with Option C recommendation
affects: [155-implementation, 156-implementation, level-quest-implementation]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Level quest progress tracking piggybacks on existing handleX handler entry points"
    - "Direct creditFlip from quest contract (Option C) for reward isolation"
    - "Roll routing via BurnieCoin hub mirrors daily quest rollDailyQuest pattern"

key-files:
  created:
    - .planning/phases/154-integration-mapping/154-01-INTEGRATION-MAP.md
  modified: []

key-decisions:
  - "Storage location: DegenerusQuests.sol (not DegenerusGameStorage) -- handlers already live there, avoids cross-contract reads"
  - "Handler routing: augment existing handleX functions with parallel level quest block (not new entry points)"
  - "Roll trigger: AdvanceModule -> BurnieCoin.rollLevelQuest -> DegenerusQuests.rollLevelQuest (mirrors daily quest pattern)"
  - "Reward path: Option C (direct creditFlip from quest contract) -- zero interface changes, minimal blast radius"
  - "BurnieCoinflip: add QUESTS to onlyFlipCreditors (1 line) for Option C reward path"

patterns-established:
  - "Level quest block in each handler: read type, read player state, check eligibility, accumulate, check completion"
  - "Level-boundary invalidation via questLevel field in packed state (simpler than daily quest version counters)"

requirements-completed: [INTG-01, INTG-02]

# Metrics
duration: 5min
completed: 2026-04-01
---

# Phase 154 Plan 01: Integration Map Summary

**Complete integration map covering 10 contracts (5 modified, 5 unchanged), all 6 handleX handler sites with level quest tracking specs, 3 Phase 153 open questions resolved, Option C reward path recommended**

## Performance

- **Duration:** 5 min
- **Started:** 2026-04-01T00:49:45Z
- **Completed:** 2026-04-01T00:55:02Z
- **Tasks:** 1
- **Files created:** 1

## Accomplishments

- Mapped all 10 contracts from CONTEXT.md with explicit change/no-change verdicts: DegenerusQuests.sol (new storage + functions + handler mods), IDegenerusQuests.sol (new event + functions), AdvanceModule (roll insertion), BurnieCoin (routing function), BurnieCoinflip (creditor expansion)
- Documented all 6 handler sites (handleMint, handleFlip, handleDecimator, handleAffiliate, handleLootBox, handleDegenerette) with exact line numbers, caller chains, quest type matches, delta values, and mintPrice needs
- Resolved all 3 Phase 153 open design questions with rationale
- Analyzed 3 reward payout options; recommended Option C (direct creditFlip from quest contract) for zero interface changes and minimal blast radius

## Task Commits

Each task was committed atomically:

1. **Task 1: Produce the integration map document** - `f2ed7078` (feat)

## Files Created/Modified

- `.planning/phases/154-integration-mapping/154-01-INTEGRATION-MAP.md` - Complete integration map with 9 sections: touchpoint map, interface changes, cross-contract calls, handler inventory, per-handler tracking specs, roll path, reward path, design questions resolved, summary table

## Decisions Made

1. **Storage in DegenerusQuests.sol** -- All 6 handlers and the quest game reference already live here. Placing storage in DegenerusGameStorage.sol would require cross-contract reads, adding gas and complexity.
2. **Augment existing handlers** -- Adding a parallel level quest block inside each handleX avoids doubling external call overhead that separate entry points would incur.
3. **Roll via BurnieCoin routing** -- Mirrors the daily quest `rollDailyQuest` pattern where BurnieCoin acts as the access-control hub between game modules and the quest contract.
4. **Option C reward path** -- DegenerusQuests calls `creditFlip` directly. Only 2 contracts change for the reward path (quest contract adds the call, coinflip adds the creditor). All 6 handler signatures remain stable.
5. **No changes to 5 contracts** -- DegenerusGameStorage, MintModule, LootboxModule, DegeneretteModule, and DegenerusDegenerette require zero modifications because quest calls flow through existing BurnieCoin wrappers.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Integration map is complete and implementation-ready
- An implementer can open 154-01-INTEGRATION-MAP.md and know exactly which files to modify, which functions to add, and which interfaces change
- Phase 155 (or next implementation phase) can proceed with zero ambiguity

## Self-Check: PASSED

- FOUND: .planning/phases/154-integration-mapping/154-01-INTEGRATION-MAP.md
- FOUND: .planning/phases/154-integration-mapping/154-01-SUMMARY.md
- FOUND: commit f2ed7078

---
*Phase: 154-integration-mapping*
*Completed: 2026-04-01*
