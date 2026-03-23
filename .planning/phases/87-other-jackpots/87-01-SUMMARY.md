---
phase: 87-other-jackpots
plan: 01
subsystem: audit
tags: [solidity, jackpot, early-bird, lootbox, final-day-dgnrs, trait-ticket, entropy]

# Dependency graph
requires:
  - phase: 81-ticket-creation-queue
    provides: ticket queue mechanics, _queueTickets behavior, traitBurnTicket storage understanding
provides:
  - Early-bird lootbox jackpot full trace (trigger, 3% allocation, 100-winner loop, _randTraitTicket baseline)
  - Final-day DGNRS distribution full trace (trigger, 1% Reward pool, solo bucket, sDGNRS transfer)
  - _randTraitTicket winner selection pattern documented as baseline for other jackpot types
  - 8 INFO findings (EB-01 through EB-04, FD-01 through FD-04)
affects: [87-02-baf, 87-03-decimator, 87-04-degenerette, 88-rng-variable-reverification]

# Tech tracking
tech-stack:
  added: []
  patterns: [exhaustive-code-trace-with-citations, cross-reference-discrepancy-tagging, trait-based-winner-selection-audit]

key-files:
  created:
    - audit/v4.0-other-jackpots-earlybird-finaldgnrs.md
  modified: []

key-decisions:
  - "Early-bird operates on lvl+1 trait bucket; 3% futurePrizePool inline constant (no named BPS); DSC-02 confirmed non-applicable to final-day DGNRS"
  - "traitId = uint8(entropy) yields 0-255 for 32 traits (0-31); _randTraitTicket returns 0 for out-of-range traitId, meaning ~87.5% of 100 iterations find no winner -- by design"
  - "Final-day DGNRS depends on lastDailyJackpotWinningTraits being set by Day 5 payDailyJackpot; turbo mode uses Day 1 traits instead of Day 5 -- FD-04 INFO"

patterns-established:
  - "_randTraitTicket winner selection traced as baseline pattern reused across all trait-based jackpot types"
  - "EntropyLib.entropyStep xorshift PRNG derivation documented for entropy chain analysis"

requirements-completed: [OJCK-01, OJCK-05, OJCK-06]

# Metrics
duration: 7min
completed: 2026-03-23
---

# Phase 87 Plan 01: Early-Bird Lootbox + Final-Day DGNRS Audit Summary

**Early-bird lootbox trigger, 3% futurePrizePool allocation, 100-winner loop with EntropyLib.entropyStep, and final-day DGNRS 1% Reward pool distribution traced with 122 file:line citations; 8 INFO findings (EB-01 through EB-04, FD-01 through FD-04), DSC-02 confirmed non-applicable**

## Performance

- **Duration:** 7 min
- **Started:** 2026-03-23T10:14:00Z
- **Completed:** 2026-03-23T10:14:39Z
- **Tasks:** 2/2
- **Files created:** 1 (audit/v4.0-other-jackpots-earlybird-finaldgnrs.md, 379 lines)

## Accomplishments

- Traced early-bird lootbox trigger path from AdvanceModule through payDailyJackpot into _runEarlyBirdLootboxJackpot with exact conditions and line numbers (AM + JM citations)
- Documented 3% futurePrizePool allocation, perWinnerEth integer division, nextPrizePool recycling, and 100-winner loop with EntropyLib.entropyStep RNG derivation
- Analyzed traitId = uint8(entropy) modular bias: values 0-255 for 32 traits means ~87.5% of iterations miss (traitId >= 32 returns no winner) -- by design
- Traced final-day DGNRS trigger (jackpotCounter >= JACKPOT_LEVEL_CAP = 5), 1% Reward pool allocation, solo bucket derivation, and _randTraitTicket winner selection
- Documented lastDailyJackpotWinningTraits dependency: must be set by Day 5 payDailyJackpot before awardFinalDayDgnrsReward is called
- Cross-referenced DSC-02 (sampleFarFutureTickets _tqWriteKey issue) -- confirmed non-applicable to early-bird and final-day DGNRS since both use traitBurnTicket[lvl] directly, not sampleFarFutureTickets
- Established _randTraitTicket winner selection as the baseline pattern for BAF, decimator, and degenerette audits

## Task Commits

Each task was committed atomically:

1. **Task 1: Audit early-bird lootbox jackpot mechanics** - `168c0e43` (docs)
2. **Task 2: Audit final-day DGNRS distribution mechanics** - `168c0e43` (docs, same commit -- both sections in single audit document)

## Files Created/Modified

- `audit/v4.0-other-jackpots-earlybird-finaldgnrs.md` - Early-bird lootbox and final-day DGNRS audit with 3 sections (early-bird mechanics, final-day DGNRS, cross-cutting analysis), 122 file:line citations (93 JM, 16 AM, 13 GS)

## Decisions Made

- Early-bird operates on lvl+1 trait bucket with 3% futurePrizePool as inline constant (no named BPS constant like other allocations)
- DSC-02 (sampleFarFutureTickets _tqWriteKey) confirmed non-applicable to final-day DGNRS -- it uses traitBurnTicket[lvl] directly via _randTraitTicket
- Turbo mode uses Day 1 traits for final-day DGNRS reward (FD-04) -- by design since turbo mode compresses 5 days into 1

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Known Stubs

None - all sections contain verified code citations, no placeholder data.

## Next Phase Readiness

- _randTraitTicket winner selection pattern documented as baseline for BAF scatter (87-02), decimator claims (87-03), and degenerette comparisons (87-04)
- 8 INFO findings documented; none blocking

## Self-Check: PASSED

- audit/v4.0-other-jackpots-earlybird-finaldgnrs.md: FOUND (379 lines, 122 citations)
- Commit 168c0e43: FOUND

---
*Phase: 87-other-jackpots*
*Completed: 2026-03-23*
