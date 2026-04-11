---
phase: 215-rng-fresh-eyes
plan: 03
subsystem: audit
tags: [rng, vrf, commitment-window, rngLockedFlag, prevrandao, lootbox]

requires:
  - phase: 213-delta-extraction
    provides: RNG chain definitions (RNG-01 through RNG-11) and cross-module interaction map
  - phase: 215-01
    provides: VRF lifecycle trace (request/fulfillment paths, state mutations, rngLockedFlag set/clear)
  - phase: 215-02
    provides: Backward trace (commitment points for all RNG consumers)
provides:
  - Commitment window analysis for all 4 VRF windows (daily, lootbox, between-day, gameover)
  - Per-function rngLockedFlag classification for every external/public function on DegenerusGame
  - Threat register disposition for T-215-07, T-215-08, T-215-09
affects: [215-05-rng-synthesis, rng-audit, security-findings]

tech-stack:
  added: []
  patterns: [attacker-model-window-analysis, per-function-guard-enumeration]

key-files:
  created:
    - .planning/phases/215-rng-fresh-eyes/215-03-COMMITMENT-WINDOW.md
  modified: []

key-decisions:
  - "3 SAFE + 1 INFO windows; zero VULNERABLE. rngLockedFlag provides effective mutual exclusion for daily VRF; lootbox relies on index advance isolation"
  - "Gameover prevrandao 1-bit proposer bias accepted as design tradeoff (terminal fallback only)"

patterns-established:
  - "Window analysis: define open/close, enumerate controllable state, classify per-function as BLOCKED/NOT BLOCKED/CONCERN"

requirements-completed: [RNG-03]

duration: 6min
completed: 2026-04-11
---

# Phase 215 Plan 03: Commitment Window Analysis Summary

**Per-path VRF window analysis: 9 rngLockedFlag guard sites, 4 isolation mechanisms, all external functions classified -- 3 SAFE + 1 INFO windows, zero VULNERABLE**

## Performance

- **Duration:** 6 min
- **Started:** 2026-04-11T00:12:27Z
- **Completed:** 2026-04-11T00:19:02Z
- **Tasks:** 1
- **Files created:** 1

## Accomplishments

- Analyzed all 4 commitment windows: daily VRF (rngLockedFlag + double-buffer + index advance + pool freeze), lootbox VRF (index advance isolation only), between-day (atomic consumption in same tx), gameover (prevrandao with 1-bit proposer bias)
- Enumerated every external/public function on DegenerusGame.sol with BLOCKED/NOT BLOCKED classification and risk assessment
- Identified 9 rngLockedFlag guard sites across 5 contracts (Game L1480, L1495, L1542, L1882; Storage L566, L596, L650; Whale L543; Advance L908)
- Confirmed 4 independent isolation mechanisms: (1) rngLockedFlag mutual exclusion, (2) ticket queue double-buffer via _swapAndFreeze, (3) lootbox index advance at VRF request, (4) prize pool freeze via prizePoolFrozen flag

## Task Commits

Each task was committed atomically:

1. **Task 1: Analyze player-controllable state in every VRF request-to-fulfillment window** - `b7808c69` (feat)

## Files Created/Modified

- `.planning/phases/215-rng-fresh-eyes/215-03-COMMITMENT-WINDOW.md` - Commitment window analysis for daily, lootbox, between-day, and gameover VRF paths with per-function classification tables and risk matrix

## Decisions Made

- Classified lootbox VRF window as SAFE despite rngLockedFlag not being set -- index advance at line 971 plus degenerette bet guard at line 430 provide equivalent isolation
- Classified between-day window as SAFE (zero duration) -- word revelation and consumption are atomic within the same advanceGame transaction
- Classified gameover prevrandao as INFO (not CONCERN) -- terminal one-time event with 3+ day VRF stall prerequisite; 1-bit proposer bias is economically irrelevant at level 0 and diluted by historical VRF words at higher levels

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- 215-04 (word derivation) and 215-05 (rngLocked synthesis) can proceed
- Commitment window analysis provides the "what state can change" complement to 215-02's "was word unknown at commitment" analysis
- All 4 windows documented with risk matrix for synthesis in plan 05

---
*Phase: 215-rng-fresh-eyes*
*Completed: 2026-04-11*
