---
phase: 38-rng-delta-security
plan: 01
subsystem: security-audit
tags: [rng, coinflip, carry-isolation, baf-guard, vrf, solidity, security]

# Dependency graph
requires: []
provides:
  - "RNG-01 carry isolation trace and formal invariant for rngLocked removal safety"
  - "RNG-02 BAF epoch-based guard sufficiency analysis with full condition matrix"
  - "sDGNRS BAF ineligibility proof at both caller and callee layers"
  - "Attacker model evaluations (MEV-aware, compromised VRF) for both findings"
  - "INFO finding: balanceOfWithClaimable UX inconsistency"
affects: [38-02, 41-comment-scan]

# Tech tracking
tech-stack:
  added: []
  patterns: ["formal invariant derivation from code trace", "7-condition guard matrix analysis"]

key-files:
  created:
    - "audit/v3.2-rng-delta-findings.md"
  modified: []

key-decisions:
  - "RNG-01 SAFE: carry isolation holds by construction via rebuyActive branching, not rngLocked guard"
  - "RNG-02 SAFE: BAF guard covers exact resolution window, sDGNRS truly ineligible at both layers"
  - "balanceOfWithClaimable inconsistency classified as INFO severity (conservative direction, no funds at risk)"

patterns-established:
  - "Two-layer BAF protection: deposit lock (_coinflipLockedDuringTransition) + inline BAF guard"
  - "sDGNRS dual exclusion: caller-side skip (BurnieCoinflip) + callee-side early return (DegenerusJackpots)"

requirements-completed: [RNG-01, RNG-02]

# Metrics
duration: 4min
completed: 2026-03-19
---

# Phase 38 Plan 01: RNG Delta Security Findings Summary

**Carry isolation formal invariant and BAF guard condition matrix proving rngLocked removal safety for coinflip claim paths**

## Performance

- **Duration:** 4 min
- **Started:** 2026-03-19T13:21:37Z
- **Completed:** 2026-03-19T13:26:20Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments
- Full carry isolation trace: all 3 write paths to autoRebuyCarry and all 3 write paths to claimableStored traced with exact line numbers, proving carry never enters mintable while auto-rebuy is enabled
- Formal invariant stated and proven from code: the rebuyActive branch (lines 416-421, 498-508) is the isolation mechanism, not the rngLocked guard
- Complete BAF guard condition matrix: all 7 conditions documented with bypass enumeration, each condition analyzed for attacker exploitability
- sDGNRS BAF ineligibility proven at two independent layers: BurnieCoinflip line 542 (caller-side skip) and DegenerusJackpots line 175 (callee-side early return)
- Reentrancy, timing, and deposit-lock analyses completed for BAF guard
- Both attacker models (MEV-aware, compromised VRF) evaluated for both RNG-01 and RNG-02 with 1000 ETH budget

## Task Commits

Each task was committed atomically:

1. **Task 1: Carry isolation trace and formal invariant (RNG-01)** - `b0d474ba` (feat)
2. **Task 2: BAF guard analysis and sDGNRS ineligibility proof (RNG-02)** - `b1a3717f` (feat)

## Files Created/Modified
- `audit/v3.2-rng-delta-findings.md` - Complete RNG-01 and RNG-02 audit findings with code traces, formal invariant, condition matrices, bypass enumerations, and attacker model evaluations

## Decisions Made
- RNG-01 Verdict: SAFE -- carry isolation is structural (code branching), not temporal (rngLocked guard)
- RNG-02 Verdict: SAFE -- BAF guard covers exact resolution window, no bypass via reentrancy/timing/state manipulation
- balanceOfWithClaimable UX inconsistency classified as INFO (conservative view function, no security impact)

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- RNG-01 and RNG-02 sections complete in audit/v3.2-rng-delta-findings.md
- Ready for Plan 02 (RNG-03 decimator claim persistence and RNG-04 cross-contract dependency matrix)
- The audit document structure is established for Plan 02 to append additional sections

---
*Phase: 38-rng-delta-security*
*Completed: 2026-03-19*
