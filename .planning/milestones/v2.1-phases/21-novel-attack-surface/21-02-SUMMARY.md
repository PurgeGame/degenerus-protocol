---
phase: 21-novel-attack-surface
plan: 02
subsystem: security-audit
tags: [composition-attacks, griefing, edge-cases, sDGNRS, DGNRS, stETH-rounding, CEI, reentrancy, cross-contract]

# Dependency graph
requires:
  - phase: 19-sdgnrs-dgnrs-delta
    provides: "Core contract audit (DELTA-01 through DELTA-03), reentrancy analysis, supply invariant proof"
  - phase: 20-correctness-verification
    provides: "Edge case tests (7 in DGNRSLiquid.test.js), NatDoc coverage, audit doc completeness"
provides:
  - "5 cross-contract call chain traces with state change ordering and CEI assessment"
  - "6 griefing vectors with cost/impact analysis and severity verdicts"
  - "15-entry edge case matrix covering all sDGNRS/DGNRS public functions"
  - "stETH 1-2 wei rounding revert scenario deep analysis"
  - "claimWinnings mid-burn stETH fallback path discovery and accounting verification"
affects: [21-03, 21-04, novel-05-invariants, novel-10-steth-rebasing, novel-11-race-conditions]

# Tech tracking
tech-stack:
  added: []
  patterns: ["C4A warden-style call chain tracing with file:line citations", "Griefing severity table (cost/impact/verdict)", "Edge case matrix with test coverage cross-reference"]

key-files:
  created:
    - "audit/novel-02-composition-griefing-edges.md"
  modified: []

key-decisions:
  - "claimWinnings stETH fallback path confirmed: game _payoutWithStethFallback routes stETH to sDGNRS via depositSteth, properly accounted for by post-claim re-reads"
  - "stETH rounding revert at sDGNRS burn line 415 only triggers for near-100% supply burns with ETH-depleted game; accepted as conservative safety check"
  - "Forced ETH donation via selfdestruct is a net loss for attackers holding <100% supply; classified as negligible griefing"

patterns-established:
  - "Cross-contract state consistency verification: map all read-then-call patterns, verify re-reads or pre-counting"
  - "Griefing vector analysis format: description, cost, impact, code path, duration, verdict, mitigation"

requirements-completed: [NOVEL-02, NOVEL-03, NOVEL-04]

# Metrics
duration: 7min
completed: 2026-03-17
---

# Phase 21 Plan 02: Composition, Griefing, and Edge Cases Summary

**Cross-contract call chain mapping across sDGNRS+DGNRS+game+coinflip with 6 griefing vectors and 15-entry edge case matrix including stETH rounding deep-dive**

## Performance

- **Duration:** 7 min
- **Started:** 2026-03-17T00:03:56Z
- **Completed:** 2026-03-17T00:11:16Z
- **Tasks:** 2/2
- **Files modified:** 1

## Accomplishments
- Mapped all 5 cross-contract call chains with complete state change ordering, CEI compliance, and reentrancy assessment -- all SAFE
- Discovered and documented that game.claimWinnings can deposit stETH (not just ETH) into sDGNRS via the _payoutWithStethFallback path at DegenerusGame.sol:1954-1956, confirmed properly handled by post-claim re-reads at StakedDegenerusStonk.sol:406-407
- Enumerated 6 griefing vectors: 2 BLOCKED (gas limit, pool racing), 3 NEGLIGIBLE (dust spam, block stuffing, forced donation), 1 KNOWN (ERC20 approve race)
- Built 15-entry edge case matrix covering all public functions with test coverage cross-reference; identified stETH rounding revert conditions (only affects near-100% supply burns)

## Task Commits

Each task was committed atomically:

1. **Task 1: NOVEL-02 -- Composition attack mapping** - `d02d3eb9` (feat)
2. **Task 2: NOVEL-03 + NOVEL-04 -- Griefing vectors + Edge case matrix** - `92536ed7` (feat)

## Files Created/Modified
- `audit/novel-02-composition-griefing-edges.md` - 474-line C4A warden-style analysis with composition attack traces, griefing severity table, edge case matrix, and stETH rounding deep-dive

## Decisions Made
- claimWinnings stETH fallback path confirmed safe: the game's `_payoutWithStethFallback` can route stETH to sDGNRS via `depositSteth()` when the game contract has insufficient ETH. This was not explicitly called out in the Phase 19 audit (which focused on the ETH-only path). The post-claim re-reads at lines 406-407 correctly capture both ETH and stETH balance changes.
- stETH rounding revert at line 415 is a conservative safety check that only triggers for the very last burner when the game has forced stETH fallback -- classified as informational, no code change recommended.
- Forced ETH via selfdestruct creates a donation to all holders proportionally -- net loss for attacker, classified as NEGLIGIBLE griefing.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- NOVEL-02, NOVEL-03, NOVEL-04 requirements complete
- stETH rounding analysis feeds into NOVEL-10 (oracle/price manipulation via stETH rebasing)
- Cross-contract state consistency findings feed into NOVEL-05 (invariant analysis) and NOVEL-11 (race conditions)
- Ready for remaining Phase 21 plans (21-03, 21-04)

## Self-Check: PASSED

- audit/novel-02-composition-griefing-edges.md: FOUND (474 lines)
- .planning/phases/21-novel-attack-surface/21-02-SUMMARY.md: FOUND
- Commit d02d3eb9 (Task 1): FOUND
- Commit 92536ed7 (Task 2): FOUND

---
*Phase: 21-novel-attack-surface*
*Completed: 2026-03-17*
