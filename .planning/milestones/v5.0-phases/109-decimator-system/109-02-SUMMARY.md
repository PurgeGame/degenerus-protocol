---
phase: 109-decimator-system
plan: 02
subsystem: audit-attack
tags: [mad-genius, attack-report, decimator, unit-07, baf-pattern]
dependency_graph:
  requires: [coverage-checklist-unit-07]
  provides: [attack-report-unit-07]
  affects: [109-03, 109-04]
tech_stack:
  patterns: [call-tree-expansion, storage-write-mapping, cached-local-check, ten-angle-attack]
key_files:
  created:
    - audit/unit-07/ATTACK-REPORT.md
decisions:
  - "BAF pattern in claimDecimatorJackpot: SAFE -- futurePrizePool read at L336 is fresh storage read"
  - "decBucketOffsetPacked collision: INVESTIGATE -- both B2 and B6 write to same slot"
  - "All other attack angles SAFE across all 7 Category B functions"
metrics:
  completed: 2026-03-25
---

# Phase 109 Plan 02: Mad Genius Attack Report Summary

Full adversarial analysis of 7 Category B functions in DegenerusGameDecimatorModule with complete recursive call trees, storage-write maps, cached-local-vs-storage checks, and 10-angle attack analysis -- BAF pattern in claimDecimatorJackpot confirmed SAFE, one INVESTIGATE finding on decBucketOffsetPacked collision.

## Deliverables

- `audit/unit-07/ATTACK-REPORT.md` -- Per-function attack analysis covering B1-B7, with dedicated section for the decBucketOffsetPacked collision.

## Key Findings

1. **BAF Pattern (Priority Investigation): SAFE.** The `_getFuturePrizePool()` read at line 336 of `claimDecimatorJackpot` is a fresh storage read after all subordinate auto-rebuy writes complete. No local variable caches futurePrizePool before the subordinate call. No stale-cache overwrite.

2. **decBucketOffsetPacked Collision: INVESTIGATE.** Both `runDecimatorJackpot` (L248) and `runTerminalDecimatorJackpot` (L817) write to the same `decBucketOffsetPacked[lvl]` mapping. If both execute at the same level (GAMEOVER level where regular decimator previously fired), the terminal resolution overwrites regular decimator winning subbuckets.

## Deviations from Plan

None -- plan executed exactly as written.
