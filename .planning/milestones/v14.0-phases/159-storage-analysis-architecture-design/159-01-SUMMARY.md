---
phase: 159-storage-analysis-architecture-design
plan: 01
subsystem: gas-optimization
tags: [solidity, gas, sload, struct-packing, parameter-forwarding, activity-score, evm-paris]

# Dependency graph
requires:
  - phase: 158.1-carryover-redesign
    provides: stable codebase after v13.0 level quests implementation
provides:
  - "Complete architecture design spec for activity score and quest gas optimization"
  - "Score function input map with 7 inputs and gas costs"
  - "9-consumer catalog with per-consumer optimization action"
  - "deityPassCount packing into mintPacked_ at bits 184-199"
  - "Parameter forwarding chain for quest streak elimination"
  - "SLOAD deduplication catalog with 8 duplicate patterns"
  - "DegeneretteModule duplicate elimination via streakBaseLevel parameter"
  - "Phase dependency matrix with file ownership and MintModule conflict ordering"
affects: [phase-160-activity-score-consolidation, phase-161-quest-handler-merging, phase-162-sload-deduplication]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Parameter forwarding over transient storage for cross-function caching (Paris EVM)"
    - "Bit packing extension of existing mintPacked_ layout via unused bits"
    - "Streak base level parameterization to unify duplicate score implementations"

key-files:
  created:
    - ".planning/phases/159-storage-analysis-architecture-design/159-01-ARCHITECTURE-SPEC.md"
  modified: []

key-decisions:
  - "deityPassCount packed into mintPacked_ at bits 184-199 (saves 2,100 gas cold SLOAD per score call)"
  - "Combined score+quest packing rejected -- parameter forwarding strictly better for quest streak"
  - "Affiliate STATICCALL accepted -- co-location SSTORE cost exceeds savings"
  - "Post-action score accepted for lootbox path -- consistent with existing ticket-path behavior"
  - "Phase ordering locked: 160 first (score), 161 second (quest), 162 last (SLOAD dedup)"
  - "Shared score function moved to base contract with streakBaseLevel parameter for DegeneretteModule"

patterns-established:
  - "Parameter forwarding chain: quest handlers return streak, forwarded to score function"
  - "Compute-once pattern: score computed once per purchase, cached as local variable"
  - "Three-signature pattern: 3-arg internal (full), 2-arg internal (convenience), 1-arg external (backward-compatible)"

requirements-completed: [SCORE-01]

# Metrics
duration: 6min
completed: 2026-04-01
---

# Phase 159 Plan 01: Storage Analysis & Architecture Design Summary

**467-line architecture spec locking all gas optimization decisions: compute-once score caching (22K-36K gas savings per purchase), deityPassCount bit-packing, quest streak parameter forwarding, and SLOAD dedup catalog for Phases 160-162**

## Performance

- **Duration:** 6 min
- **Started:** 2026-04-01T21:24:41Z
- **Completed:** 2026-04-01T21:30:51Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments
- Complete score function input map: 7 inputs catalogued with gas costs (11,700-23,600 gas per cold call)
- All 9 playerActivityScore consumers enumerated with per-consumer optimization action (3 OPTIMIZE, 3 INDIRECT, 2 NO CHANGE, 1 ELIMINATE DUPLICATE)
- Packed struct analysis: deityPassCount into mintPacked_ bits 184-199 recommended (2,100 gas savings); combined score+quest packing rejected with justification
- Parameter forwarding chain fully specified: quest streak captured from handleMint/handleLootBox returns, forwarded to _playerActivityScore
- SLOAD dedup catalog: 8 duplicate read patterns with exact line numbers, read counts, caching method, and per-variable savings
- DegeneretteModule duplicate elimination: streakBaseLevel parameter design with 3-signature pattern
- Phase dependency matrix: file ownership per phase, MintModule conflict zone ordering (160 -> 161 -> 162)
- Total gas savings estimated: 22,800-35,800+ per lootbox purchase at x00 level

## Task Commits

Each task was committed atomically:

1. **Task 1: Write architecture design spec from source code analysis and research** - `0213d4bf` (feat)
2. **Task 2: Self-review spec for completeness, consistency, and decision traceability** - no commit (spec passed review without modifications)

## Files Created/Modified
- `.planning/phases/159-storage-analysis-architecture-design/159-01-ARCHITECTURE-SPEC.md` - 467-line architecture design spec with 10 major sections, traceability tables, and gas savings summary

## Decisions Made
- **deityPassCount packing:** Pack into mintPacked_ at bits 184-199 (50 unused bits available; 16 needed). Saves 2,100 gas cold SLOAD per score computation.
- **Combined score+quest packing rejected:** Parameter forwarding from handleMint/handleLootBox return values is strictly better (zero storage overhead vs 2,900-5,000 gas SSTORE overhead for co-location).
- **Affiliate STATICCALL accepted:** The affiliate address is warm on purchase path (100 gas base, not 2,600). Internal SLOADs are the real cost, and co-location SSTORE overhead exceeds savings.
- **Post-action score for lootbox path:** Score computed AFTER handleLootBox (not before as currently). Behavioral impact is at most 100 BPS (~0.2% EV), consistently rewards active players. Matches existing ticket-path behavior.
- **Phase ordering:** 160 first (changes signatures), 161 second (changes handler calls), 162 last (mechanical caching, independent of structural changes).
- **Score function placement:** Move to shared base contract (DegenerusGameStorage.sol or new utility) so DegeneretteModule can call internal 3-arg version with `level + 1` as streakBaseLevel.

## Deviations from Plan

None -- plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None -- no external service configuration required.

## Known Stubs

None -- this is a design-only plan producing an architecture spec document.

## Next Phase Readiness
- Architecture spec locked: Phases 160-162 can begin implementation with zero design ambiguity
- All 11 context decisions (D-01 through D-11) honored and traced
- All 4 ROADMAP success criteria addressed
- All 5 research pitfalls mitigated
- All 3 research open questions resolved
- File ownership per phase documented; MintModule conflict ordering specified

## Self-Check: PASSED

- FOUND: `.planning/phases/159-storage-analysis-architecture-design/159-01-ARCHITECTURE-SPEC.md`
- FOUND: `.planning/phases/159-storage-analysis-architecture-design/159-01-SUMMARY.md`
- FOUND: commit `0213d4bf` (Task 1: architecture spec)

---
*Phase: 159-storage-analysis-architecture-design*
*Completed: 2026-04-01*
