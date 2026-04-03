---
phase: 178-consolidation-regression-check
plan: 01
subsystem: audit
tags: [findings, natspec, comments, consolidation, v17.1]

requires:
  - phase: 176-core-game-token-contract-comment-sweep
    provides: 175-01 through 175-05 and 176-01 through 176-03 FINDINGS.md files
  - phase: 177-infrastructure-libraries-misc-comment-sweep
    provides: 177-01 through 177-04 FINDINGS.md files

provides:
  - v17.1-comment-findings-consolidated.md: master findings register for all 12 per-plan sweep outputs
  - 30 LOW + 42 INFO findings categorized, deduped, and formatted for developer consumption
  - False positive 175-02-002 documented and excluded from counts
  - 5 cross-cutting patterns documented for systemic analysis
  - Regression Findings stub section ready for Plan 02 to append

affects:
  - 178-02-PLAN (appends regression findings to this document)
  - developer fix workflow (this document is the primary input)

tech-stack:
  added: []
  patterns:
    - "ID disambiguation pattern: BCF-IMPL-01 vs BCF-IFACE-01 for same reused ID across phases"
    - "Unnumbered Phase 175-03 findings assigned IDs: LB-01 through LB-04, MS-01"

key-files:
  created:
    - .planning/phases/178-consolidation-regression-check/v17.1-comment-findings-consolidated.md
  modified: []

key-decisions:
  - "BCF-01 disambiguation: Phase 176-02 implementation finding becomes BCF-IMPL-01; Phase 177-03 interface finding becomes BCF-IFACE-01 to avoid ID collision"
  - "ADV-CMT-04 and ADV-CMT-05 excluded from findings count — both verified accurate in 175-01"
  - "Phase 175-03 Finding 2 (boon restriction) classified INFO not LOW — upgrade semantics exist per category, comment misleads about rolling constraint only"
  - "BCF-05 retained as INFO — 156% absolute max is technically correct even if uncommon"
  - "Plan says 13 source FINDINGS.md files; actual count is 12 (5+3+4). Consolidated from all 12."

requirements-completed:
  - CON-01

duration: 45min
completed: 2026-04-03
---

# Phase 178 Plan 01: Consolidation — Master Findings Register

**72-finding master register for v17.1 comment correctness sweep: 30 LOW + 42 INFO across 12 contracts/interfaces/libraries, with 5 cross-cutting systemic patterns**

## Performance

- **Duration:** ~45 min
- **Started:** 2026-04-03T23:10:00Z
- **Completed:** 2026-04-03T23:55:00Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments

- Read all 12 source FINDINGS.md files (Phases 175-177) and merged into a single master document
- 1650-line consolidated register with Executive Summary, Known False Positive section, per-phase verbatim findings, Master Summary Table, and Cross-Cutting Patterns
- All 30 LOW findings appear before 42 INFO findings in Master Summary Table, sorted alphabetically by contract short name within each tier
- False positive 175-02-002 documented in dedicated section and excluded from counts
- BCF-01 ID collision resolved: BCF-IMPL-01 (BurnieCoinflip implementation, Phase 176-02) vs BCF-IFACE-01 (IBurnieCoinflip interface, Phase 177-03)
- 5 cross-cutting patterns identified for developer prioritization

## Task Commits

1. **Task 1: Create consolidated findings document** - `e54df28e` (feat)

## Files Created/Modified

- `.planning/phases/178-consolidation-regression-check/v17.1-comment-findings-consolidated.md` — 1650-line master findings register

## Decisions Made

- BCF-01 appeared in two phases referring to two different files (BurnieCoinflip.sol implementation vs IBurnieCoinflip.sol interface). Disambiguated as BCF-IMPL-01 and BCF-IFACE-01 per plan instruction.
- Phase 175-03 findings had no assigned IDs in source. Assigned LB-01 through LB-04 (LootboxModule findings) and MS-01 (MintStreakUtils finding) per plan instruction.
- ADV-CMT-04 and ADV-CMT-05 from Phase 175-01 are documented as "verified accurate" findings in source — not actual discrepancies. Excluded from findings count and table.
- IBurnieCoinflip `claimCoinflipsForRedemption` appears in both 176-02 (as BCF-04) and 177-03 (as BCF-IFACE-02). These cover the same behavioral issue from different angles (implementation vs interface comment) — both retained as distinct findings because they point to different comment locations needing fixes.
- IDegenerusGame findings from 177-03 use `DGM-IFACE-01` to distinguish from DegenerusGame.sol findings `DGM-01/02/03` from Phase 176-01.

## Deviations from Plan

None — plan executed exactly as written. The only note is that the plan mentions "13 source FINDINGS.md files" but the read_first list contains 12 paths (5 from Phase 175, 3 from Phase 176, 4 from Phase 177). All 12 files were read and consolidated.

## Issues Encountered

None.

## Next Phase Readiness

- `v17.1-comment-findings-consolidated.md` is complete and ready for Plan 02 (regression check)
- Plan 02 will append findings to the "Regression Findings (Plan 02)" stub section
- The document passes all automated verification checks (72 findings, 34 LOW rows in table, all 16 spot-check IDs present)

---
*Phase: 178-consolidation-regression-check*
*Completed: 2026-04-03*
