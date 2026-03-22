---
phase: 64-lootbox-rng-lifecycle
plan: 02
subsystem: audit
tags: [findings, lootbox, rng, vrf, entropy, c4a, solidity]

# Dependency graph
requires:
  - phase: 64-lootbox-rng-lifecycle
    plan: 01
    provides: 21 Foundry fuzz/unit tests covering LBOX-01 through LBOX-05, test evidence for findings
  - phase: 63-vrf-request-fulfillment-core
    plan: 02
    provides: v3.7-vrf-core-findings.md format template, V37-001/V37-002 ID namespace
provides:
  - audit/v3.7-lootbox-rng-findings.md -- Phase 64 lootbox RNG lifecycle findings document (2 INFO, 5 requirements VERIFIED)
  - Updated audit/KNOWN-ISSUES.md with Phase 64 results section
  - V37-003 and V37-004 finding IDs cataloged
affects: [future VRF stall edge case phases, C4A audit preparation]

# Tech tracking
tech-stack:
  added: []
  patterns: [findings document with per-requirement verification sections, mutation site audit table, write site audit table, zero-guard inventory]

key-files:
  created: [audit/v3.7-lootbox-rng-findings.md]
  modified: [audit/KNOWN-ISSUES.md]

key-decisions:
  - "D-01: Classified V37-003 (_getHistoricalRngFallback missing zero guard) as INFO not LOW -- probability 2^-256, gameover-only fallback path, trivial fix available but not security-critical"
  - "D-02: Documented V37-004 (mid-day lastLootboxRngWord update) as INFO design documentation -- correct by design, documented to prevent false-positive C4A submissions"
  - "D-03: Grand total carried forward at 84 (82 prior + 2 new Phase 64 INFO findings)"

patterns-established:
  - "Findings document follows v3.7-vrf-core-findings.md section structure: Executive Summary, ID Assignment, Master Findings, per-topic audit sections, Per-Requirement Verification Summary, Cross-Cutting Observations, Requirement Traceability"
  - "Each requirement VERIFIED section includes test function names from the corresponding test file as evidence"

requirements-completed: [LBOX-01, LBOX-02, LBOX-03, LBOX-04, LBOX-05]

# Metrics
duration: 4min
completed: 2026-03-22
---

# Phase 64 Plan 02: Lootbox RNG Findings Summary

**C4A-ready findings document with 2 INFO findings (V37-003: _getHistoricalRngFallback missing zero guard, V37-004: mid-day lastLootboxRngWord design note), all 5 LBOX requirements VERIFIED with 21-test evidence, and KNOWN-ISSUES.md updated with Phase 64 results**

## Performance

- **Duration:** 4 min
- **Started:** 2026-03-22T16:36:14Z
- **Completed:** 2026-03-22T16:40:44Z
- **Tasks:** 2
- **Files created:** 1 (audit/v3.7-lootbox-rng-findings.md -- 464 lines)
- **Files modified:** 1 (audit/KNOWN-ISSUES.md -- 9 lines added)

## Accomplishments

- Created comprehensive findings document covering all 5 LBOX requirements with detailed audit sections: index mutation mapping (4 sites), word-to-index write audit (5 sites), zero-state guard inventory (4/5 guarded), entropy derivation analysis (keccak256 preimage proof), and full 6-step lifecycle trace
- Identified and cataloged 2 INFO findings: V37-003 (defense-in-depth zero guard gap) and V37-004 (mid-day lastLootboxRngWord update documentation)
- Updated KNOWN-ISSUES.md with Phase 64 summary entry preserving all existing content
- Verified all contract line numbers against actual source (AdvanceModule, LootboxModule, MintModule)

## Task Commits

Each task was committed atomically:

1. **Task 1: Create v3.7 lootbox RNG findings document** - `59bc178b` (feat)
2. **Task 2: Update KNOWN-ISSUES.md with Phase 64 results** - `4fd2b393` (feat)

## Files Created/Modified

- `audit/v3.7-lootbox-rng-findings.md` - Phase 64 findings document with 2 INFO findings, all 5 LBOX requirements VERIFIED, 21 test evidence references
- `audit/KNOWN-ISSUES.md` - Added Phase 64 results section with V37-003 and V37-004 summaries

## Decisions Made

- **D-01:** Classified V37-003 as INFO (not LOW) -- the missing zero guard in `_getHistoricalRngFallback` has probability 2^-256 of triggering. It is on the gameover-only fallback path (VRF dead for 3+ days). While the fix is trivial (`if (word == 0) word = 1`), the risk is negligible and does not warrant LOW severity.
- **D-02:** Documented V37-004 as INFO design documentation -- `rawFulfillRandomWords` mid-day branch not updating `lastLootboxRngWord` is correct by design. The variable is only consumed by ticket processing in `advanceGame`, which reads the word via the mid-day drain path when needed. Documenting this prevents false-positive C4A submissions.
- **D-03:** Grand total carried forward at 84 findings (82 prior milestones + 2 new Phase 64 INFO) -- consistent with the carry-forward accounting established in v3.7-vrf-core-findings.md.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Phase 64 complete: both plans (fuzz test suite + findings document) delivered
- 84 total findings across all milestones (16 LOW, 68 INFO), 0 HIGH/MEDIUM
- LBOX-01 through LBOX-05 all VERIFIED -- lootbox RNG lifecycle audit complete
- Ready for next v3.7 phase (coinflip RNG path, advanceGame day RNG, or VRF stall edge cases)

## Self-Check: PASSED

- [x] audit/v3.7-lootbox-rng-findings.md exists (464 lines)
- [x] audit/KNOWN-ISSUES.md updated with Phase 64 entry
- [x] Task 1 commit 59bc178b exists
- [x] Task 2 commit 4fd2b393 exists
- [x] 64-02-SUMMARY.md exists

---
*Phase: 64-lootbox-rng-lifecycle*
*Completed: 2026-03-22*
