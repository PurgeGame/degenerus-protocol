---
phase: 215-rng-fresh-eyes
plan: 01
subsystem: rng-audit
tags: [vrf, chainlink, rng, lifecycle, delegatecall, prevrandao, keccak, lootbox]

# Dependency graph
requires:
  - phase: 213-delta-extraction
    provides: RNG chain definitions (RNG-01 through RNG-11) and cross-module interaction map
provides:
  - End-to-end VRF lifecycle trace covering daily VRF, lootbox VRF, gap day backfill, and gameover fallback
  - Line-number-backed proof of every RNG state mutation in the request/fulfillment cycle
  - Threat model verification for T-215-01 (caller spoofing) and T-215-02 (word overwrite)
affects: [215-02, 215-03, 215-04, 215-05]

# Tech tracking
tech-stack:
  added: []
  patterns: [forward-trace-with-line-numbers, per-section-verdict, write-once-word-storage]

key-files:
  created:
    - .planning/phases/215-rng-fresh-eyes/215-01-VRF-LIFECYCLE.md
  modified: []

key-decisions:
  - "Daily VRF uses 10 confirmations, mid-day lootbox uses 4 -- intentional latency/speed tradeoff"
  - "rngLockedFlag only set for daily VRF, not for mid-day lootbox requests -- lootbox RNG does not block game operations"
  - "Gameover fallback uses historical VRF words + prevrandao after 3-day delay -- acceptable 1-bit validator bias for dead-VRF scenario"

patterns-established:
  - "VRF word is write-once per day: rngWordByDay[day] != 0 guard at rngGate entry, rngWordCurrent != 0 guard at callback"
  - "Staging pattern: VRF delivers to rngWordCurrent, _applyDailyRng writes to rngWordByDay[day] with nudges"

requirements-completed: [RNG-01]

# Metrics
duration: 6min
completed: 2026-04-11
---

# Phase 215 Plan 01: VRF Lifecycle Summary

**End-to-end VRF lifecycle trace covering daily request/fulfillment, lootbox request/fulfillment, gap day backfill, orphaned index recovery, and gameover fallback -- 17 verdicts across 6 sections, all TRACED, zero CONCERN**

## Performance

- **Duration:** 6 min
- **Started:** 2026-04-10T23:55:12Z
- **Completed:** 2026-04-11T00:01:33Z
- **Tasks:** 1
- **Files created:** 1

## Accomplishments
- Traced daily VRF request path from advanceGame through _requestRng to Chainlink VRF coordinator with all parameters (10 confirmations, 300K gas, single word)
- Traced daily VRF fulfillment from rawFulfillRandomWords through delegatecall validation (msg.sender == vrfCoordinator), staging in rngWordCurrent, and permanent storage via _applyDailyRng to rngWordByDay
- Traced lootbox VRF as separate mid-day path with 4 confirmations, per-index word storage via lootboxRngWordByIndex, and midDayTicketRngPending flag lifecycle
- Traced gap day backfill via keccak256(vrfWord, gapDay) derivation with 120-day cap and companion orphaned lootbox index recovery
- Traced gameover fallback with 3-day timeout, historical VRF + prevrandao entropy, and RngNotReady revert gate
- Verified threat model: T-215-01 (caller spoofing) mitigated by msg.sender check in delegatecall context; T-215-02 (word overwrite) mitigated by write-once guards

## Task Commits

Each task was committed atomically:

1. **Task 1: Trace daily VRF request/fulfillment lifecycle and gap day backfill** - `7da585d7` (feat)

## Files Created/Modified
- `.planning/phases/215-rng-fresh-eyes/215-01-VRF-LIFECYCLE.md` - Complete VRF lifecycle trace with 6 sections, line-number-backed proof, and summary table

## Decisions Made
- Documented the rngLockedFlag asymmetry: set for daily VRF requests but NOT for mid-day lootbox requests -- this is intentional design, not a gap
- Noted that _applyDailyRng applies nudges (totalFlipReversals) before storing, making the stored word differ from the raw VRF word
- Identified that gap day backfill skips nudges and redemption resolution -- intentional per NatSpec comments

## Deviations from Plan

None -- plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required
None -- no external service configuration required.

## Next Phase Readiness
- VRF lifecycle trace provides the foundation for 215-02 (backward trace from every RNG consumer)
- All word storage locations (rngWordByDay, lootboxRngWordByIndex, rngWordCurrent) documented with line numbers for consumer tracing
- rngGate control flow branches documented for commitment window analysis in 215-03

---
*Phase: 215-rng-fresh-eyes*
*Completed: 2026-04-11*
