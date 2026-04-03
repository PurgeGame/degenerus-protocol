---
phase: 178-consolidation-regression-check
plan: "02"
subsystem: audit-documentation
tags: [regression-check, comment-sweep, v17.1, consolidation]
dependency_graph:
  requires: [178-01]
  provides: [v17.1-complete-deliverable]
  affects: [v17.1-comment-findings-consolidated.md]
tech_stack:
  added: []
  patterns: [backward-trace-regression-check, prior-sweep-spot-check]
key_files:
  created: []
  modified:
    - .planning/phases/178-consolidation-regression-check/v17.1-comment-findings-consolidated.md
decisions:
  - "All 7 priority v3.1/v3.5 regression checks passed — no regressions found in current source"
  - "IDegenerusGameModules resolveBets interface NatSpec is corrected; duplicate @notice in DegenerusGameDegeneretteModule is already captured as D-01"
metrics:
  duration: "~5 minutes"
  completed: "2026-04-03T23:22:49Z"
  tasks_completed: 1
  tasks_total: 1
  files_modified: 1
---

# Phase 178 Plan 02: Regression Check Summary

**One-liner:** Spot-checked 7 priority v3.1/v3.5 fixed comment findings against current v17.1 source — all fixes remain intact, no regressions found.

---

## Tasks Completed

| Task | Name | Commit | Files Modified |
|------|------|--------|----------------|
| 1 | Spot-check v3.1 and v3.5 fixed findings against current source | 2211733e | v17.1-comment-findings-consolidated.md |

---

## Regression Check Results

All 7 priority checks passed. The "## Regression Findings (Plan 02)" section has been appended to the consolidated document with a full spot-check table.

| Check | Prior Finding | Current State | Status |
|-------|--------------|---------------|--------|
| DegenerusAdmin.sol threshold ~line 38 | v3.1 CMT-001 / v3.5 CMT-V35-04-001 | "50% → 5% over 7 days" present | FIXED |
| DegenerusAdmin.sol death clock ~line 41 | v3.1 CMT-002 / v3.5 CMT-V35-04-002 | No "death clock pauses" text anywhere in file | FIXED |
| DegenerusVault.sol transferFrom @custom:reverts | v3.5 CMT-V35-04-003 | "@custom:reverts ZeroAddress If to is address(0)" | FIXED |
| StakedDegenerusStonk RedemptionClaimed event | v3.5 CMT-V35-01-001 | Decl (line 157) and emit (line 670) both use `flipResolved` | FIXED |
| DegenerusGameLootboxModule header | v3.5 CMT-V35-02-003 | `resolveLootboxRng` absent from header | FIXED |
| IDegenerusGameModules finalizeEndgame NatSpec | v3.5 CMT-V35-03-004 | No occurrence of `finalizeEndgame` in file | FIXED |
| IDegenerusGameModules resolveBets NatSpec | v3.5 CMT-V35-03-005 | Interface NatSpec corrected; module duplicate already logged as D-01 | ALREADY-FOUND |

Skipped per plan: DGM-03 (18h VRF timeout) and ADM-01 (_applyVote return count) — both already in consolidated doc as current findings.

---

## Decisions Made

- No new regression findings. The v3.1/v3.5 Phase 133 fixes all survived the v16.0 module consolidation and v17.0 affiliate bonus cache changes.
- The resolveBets NatSpec situation: the v3.5 original issue (corrupted NatSpec in the interface file) is fixed; the current D-01 finding is a separate paste artifact in the implementation module (`DegenerusGameDegeneretteModule.sol`), already logged.

---

## Deviations from Plan

None — plan executed exactly as written. The consolidated document's stub was replaced with full regression check results.

---

## Known Stubs

None. The consolidated document is now the complete v17.1 deliverable with no outstanding stubs.

---

## Self-Check: PASSED

- [x] `v17.1-comment-findings-consolidated.md` has `## Regression Findings (Plan 02)` section with full table
- [x] Stub "To be appended" is absent from the regression section
- [x] Commit `2211733e` exists and staged only the planning doc
- [x] All 7 checks documented with FIXED or ALREADY-FOUND status
- [x] No contracts/ files were committed
