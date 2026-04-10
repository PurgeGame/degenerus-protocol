---
phase: 213-delta-extraction
plan: "01"
subsystem: audit-delta
tags: [delta-extraction, modules, storage, changelog]
dependency_graph:
  requires: []
  provides: [module-classification, function-changelog, storage-variable-map]
  affects: [213-02, 213-03, 214, 215, 216]
tech_stack:
  added: []
  patterns: [fresh-diff-analysis, contract-classification, function-level-changelog]
key_files:
  created:
    - .planning/phases/213-delta-extraction/213-01-DELTA-MODULES.md
  modified: []
decisions:
  - Used tabular format for both classification and function changelog for scanability
  - Tracked MOVED functions bidirectionally (source and destination) for EndgameModule elimination
  - Included storage variable changes as a dedicated subsection within Storage changelog
metrics:
  duration: 6m
  completed: "2026-04-10T21:19:37Z"
  tasks: 1
  files_created: 1
---

# Phase 213 Plan 01: Delta Extraction - Modules + Storage Summary

Contract classification and function-level changelog for all 13 module and storage contracts covering v5.0-to-HEAD delta, produced from fresh git diff analysis.

## What Was Done

### Task 1: Classify module and storage contracts and build function-level changelog

Created `213-01-DELTA-MODULES.md` with:

- **Contract classification table**: All 13 contracts classified (11 MODIFIED, 1 DELETED, 0 NEW/UNCHANGED)
- **Function-level changelog**: Every changed/added/removed/moved function catalogued across all contracts
- **EndgameModule redistribution**: All 8 functions tracked to their destination modules (AdvanceModule, JackpotModule, WhaleModule)
- **Storage variable changes**: Full slot 0/1 repack documented, 15 removed variables, 8 added packed fields, type narrowings

Key findings from the diff:
- **EndgameModule eliminated**: rewardTopAffiliate and runRewardJackpots inlined into AdvanceModule; BAF/ticket functions moved to JackpotModule; claimWhalePass moved to WhaleModule
- **Pool consolidation inlined**: Separate _applyTimeBasedFutureTake, _consolidatePrizePools, _drawDownFuturePrizePool merged into single _consolidatePoolsAndRewardJackpots with memory-batched SSTORE
- **Jackpot two-call split**: Daily ETH distribution can split across two advanceGame calls via resumeEthPool and SPLIT_CALL1/CALL2 mode
- **processTicketBatch moved**: From JackpotModule to MintModule (with _raritySymbolBatch assembly code)
- **Storage repack**: Slot 0 repacked (30/32 bytes), currentPrizePool+claimablePool packed as uint128 pair in slot 1, price variable removed (PriceLookupLib), 6 packed uint256 fields replace ~15 individual variables
- **WXRP removal**: Post-v24.1 commit d912ddbc removed WXRP wrapping throughout (consolation prizes, distress mode, etc.)
- **Drip projection**: New _evaluateGameOverAndTarget + _projectedDrip + _wadPow in AdvanceModule for gameOverPossible flag
- **External contract refs centralized**: coin, coinflip, quests, affiliate, dgnrs constants moved from individual modules to DegenerusGameStorage
- **Boon category exclusion removed**: Players can now hold one boon per category simultaneously (was one boon total)

## Deviations from Plan

None - plan executed exactly as written.

## Self-Check: PASSED

- [x] File exists: `.planning/phases/213-delta-extraction/213-01-DELTA-MODULES.md`
- [x] Contains `## Contract Classification` with markdown table (all 13 contracts)
- [x] Contains `## Function-Level Changelog` (1 occurrence)
- [x] DegenerusGameEndgameModule appears 2+ times (classification + changelog)
- [x] Every MODIFIED contract has function-level subsection
- [x] DELETED contract shows redistribution destinations
- [x] Storage variable changes catalogued
- [x] No prior milestone changelog references
- [x] Commit 779f0088 exists
