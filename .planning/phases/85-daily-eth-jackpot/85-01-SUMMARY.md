---
phase: 85-daily-eth-jackpot
plan: 01
subsystem: audit
tags: [solidity, jackpot, bps, prize-pool, carryover, chunked-distribution]

# Dependency graph
requires:
  - phase: 81-ticket-creation-queue
    provides: ticket queue mechanics and trait ticket understanding for winner selection context
provides:
  - Daily ETH jackpot BPS allocation table (all 5 days, 3 modes) with file:line citations
  - Phase 0 vs Phase 1 comparison table (14 properties)
  - Early-burn path documented as distinct mechanism
  - Budget split logic (20/80 lootbox/ETH, carryover 1% drip, early-bird 3%)
  - 10 cross-reference discrepancies documented against v3.2, v3.8, PAYOUT-SPECIFICATION
affects: [85-02-daily-eth-jackpot, 86-daily-coin-ticket-jackpot, 87-other-jackpots, 84-prize-pool-flow, 88-rng-variable-reverification]

# Tech tracking
tech-stack:
  added: []
  patterns: [exhaustive-code-trace-with-citations, phase-comparison-table, cross-reference-discrepancy-tagging]

key-files:
  created:
    - audit/v4.0-daily-eth-jackpot.md
  modified: []

key-decisions:
  - "PAY-02 payout specification conflates day 5 shares with all-day shares -- documented as INFO discrepancy"
  - "v3.8 dailyEthPhase slot offset wrong (claims Slot 0:31, actual Slot 1:0) -- documented as INFO"
  - "v3.8 dailyCarryoverEthPool and dailyCarryoverWinnerCap R/W patterns mischaracterized as W-only -- documented as INFO"
  - "CMT-V32-001 remains unresolved (ticketSpent NatSpec); CMT-V32-002 confirmed resolved"

patterns-established:
  - "Three distinct distribution paths: daily Phase 0, daily Phase 1 (carryover), early-burn (purchase phase)"
  - "Pre-deduction model for carryover: futurePrizePool deducted upfront, paidEth return discarded"
  - "Undistributed carryover ETH becomes unattributed contract balance (solvency buffer)"

requirements-completed: [DETH-01, DETH-02, DETH-05]

# Metrics
duration: 7min
completed: 2026-03-23
---

# Phase 85 Plan 01: Daily ETH Jackpot -- BPS Allocation, Phase 0/1 Behavior, and Early-Burn Path Summary

**Daily ETH jackpot entry points, BPS allocation table (5 days x 3 modes), Phase 0 vs Phase 1 comparison (14 properties), early-burn path, and budget split logic documented with 286 file:line citations; 10 cross-reference discrepancies found against prior audit documentation**

## Performance

- **Duration:** 7 min
- **Started:** 2026-03-23T15:05:44Z
- **Completed:** 2026-03-23T15:13:20Z
- **Tasks:** 2/2
- **Files created:** 1 (audit/v4.0-daily-eth-jackpot.md, 1130 lines)

## Accomplishments

- Traced all 4 advanceGame call sites into payDailyJackpot/payDailyJackpotCoinAndTickets with exact conditions and line numbers
- Documented complete BPS allocation table across normal, compressed, and turbo modes (all 5 logical days)
- Documented all daily ETH constants (21 constants from JM:104-224) with exact Solidity declarations
- Budget split logic traced: 20/80 lootbox/ETH for daily, 50/50 for carryover, 75/25 for early-burn, 3% early-bird on day 1
- Phase 0 (current level) and Phase 1 (carryover) fully documented with 14-property comparison table, every row citing JM:{line}
- Early-burn path documented as distinct mechanism with its own BPS, caps (300 vs 321), and non-chunked distribution
- Cross-referenced against v3.2 (CMT-V32-001 CONFIRMED, CMT-V32-002 RESOLVED), v3.8 Section 1.7 (3 discrepancies), and PAY-01/PAY-02 (4 discrepancies)

## Task Commits

Each task was committed atomically:

1. **Task 1: Trace payDailyJackpot entry points and BPS allocation table** - `d3295f57` (feat)
2. **Task 2: Document Phase 0 vs Phase 1 behavior and early-burn path** - `6f8aa5ef` (feat)

## Files Created/Modified

- `audit/v4.0-daily-eth-jackpot.md` - Daily ETH jackpot audit document with 9 sections covering call sites, constants, BPS allocation, budget split, cross-reference, Phase 0, Phase 1, comparison table, and early-burn path

## Decisions Made

- PAY-02 payout specification conflates FINAL_DAY_SHARES_PACKED values with all-day shares and claims "4 winners per draw" when actual system supports up to 321 winners across 4 buckets -- documented as INFO severity discrepancies rather than findings since the specification is a simplified reference
- v3.8 commitment window inventory has 3 inaccuracies: dailyEthPhase slot offset (Slot 0:31 vs actual Slot 1:0), and dailyCarryoverEthPool/dailyCarryoverWinnerCap R/W characterization (listed as W-only but both are R/W)
- CMT-V32-001 (_resolveTraitWinners @return ticketSpent NatSpec inaccuracy) confirmed still unresolved in current code
- CMT-V32-002 (inline "BURNIE only" comment) confirmed resolved -- updated to "BURNIE and ETH bonuses on non-day-1 levels"

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Known Stubs

None - all sections contain verified code citations, no placeholder data.

## Next Phase Readiness

- Plan 02 can build upon this document for the algorithmic deep-dive into _processDailyEthChunk, bucket/cursor mechanics, and carryover edge cases
- Phase 0 vs Phase 1 comparison table and early-burn path comparison table provide the structural foundation for Plan 02's detailed tracing
- 10 cross-reference discrepancies documented as INFO -- none blocking

## Self-Check: PASSED

- audit/v4.0-daily-eth-jackpot.md: FOUND (1130 lines, 286 citations)
- Commit d3295f57: FOUND
- Commit 6f8aa5ef: FOUND

---
*Phase: 85-daily-eth-jackpot*
*Completed: 2026-03-23*
