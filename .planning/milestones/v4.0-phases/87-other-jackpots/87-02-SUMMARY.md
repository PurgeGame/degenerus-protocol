---
phase: 87-other-jackpots
plan: 02
subsystem: audit
tags: [solidity, jackpot, baf, scatter, endgame, two-contract, winner-mask, far-future]

# Dependency graph
requires:
  - phase: 81-ticket-creation-queue
    provides: DSC-02 sampleFarFutureTickets _tqWriteKey finding for BAF fairness assessment
  - phase: 87-01-earlybird-finaldgnrs
    provides: _randTraitTicket baseline pattern for trait-based winner selection
provides:
  - BAF jackpot full trace across two-contract system (DegenerusJackpots + EndgameModule)
  - 7-slice prize distribution documented with percentages and file:line (10% top BAF, 5% top coinflip, 5% random 3rd/4th, 5%+5% far-future, 45% scatter 1st, 25% scatter 2nd)
  - Scatter mechanics (50 rounds, level targeting, trait sampling, top-2 selection) documented
  - BAF payout processing (large/small threshold, ETH/lootbox split, auto-rebuy) documented
  - DSC-02 impact on BAF assessed (~10% of pool recycled as refund)
  - winnerMask confirmed as dead code (constructed but discarded by EndgameModule)
  - 2 INFO findings (BAF-01, BAF-02) + 1 cross-ref (DSC-02)
affects: [88-rng-variable-reverification, 89-consolidated-findings]

# Tech tracking
tech-stack:
  added: []
  patterns: [two-contract-audit-trace, cross-contract-delegation-pattern, dead-code-identification]

key-files:
  created:
    - audit/v4.0-other-jackpots-baf.md
  modified: []

key-decisions:
  - "BAF is a two-contract system: DegenerusJackpots handles winner selection, EndgameModule handles payout processing via delegatecall"
  - "winnerMask is dead code -- constructed with up to 40 iterations in DegenerusJackpots but return value discarded by EndgameModule (EM:361)"
  - "DSC-02 affects ~10% of BAF pool: far-future slices D and D2 (5%+5%) return as refund because sampleFarFutureTickets reads from _tqWriteKey instead of _tqFarFutureKey"

patterns-established:
  - "7-slice prize distribution traced through external contract with percentage verification (10+5+5+5+5+45+25 = 100%)"
  - "Large/small winner threshold pattern (5% of pool) with alternating ETH/lootbox for small winners"

requirements-completed: [OJCK-02, OJCK-06]

# Metrics
duration: 8min
completed: 2026-03-23
---

# Phase 87 Plan 02: BAF Jackpot Audit Summary

**BAF two-contract jackpot traced across DegenerusJackpots and EndgameModule: 7-slice prize distribution (100% verified), 50-round scatter mechanics, large/small payout split, DSC-02 impact assessed (~10% recycled), winnerMask confirmed dead code; 161 file:line citations, 2 INFO findings + 1 cross-ref**

## Performance

- **Duration:** 8 min
- **Started:** 2026-03-23T10:11:00Z
- **Completed:** 2026-03-23T10:11:25Z
- **Tasks:** 2/2
- **Files created:** 1 (audit/v4.0-other-jackpots-baf.md, 532 lines)

## Accomplishments

- Traced BAF trigger path from advanceGame through runRewardJackpots to two-contract dispatch (EndgameModule -> DegenerusJackpots.runBafJackpot -> EndgameModule payout)
- Documented all 7 prize distribution slices with exact percentages and file:line citations: Slice A (10% top BAF), A2 (5% top coinflip), B (5% random 3rd/4th), D (5% FF 1st draw), D2 (5% FF 2nd draw), E-1st (45% scatter 1st), E-2nd (25% scatter 2nd)
- Verified slice sum: 10+5+5+5+5+45+25 = 100% with any unawarded amounts returned as refund
- Traced 50-round scatter mechanics: level targeting (non-century uses lvl+1 to +4 weighted, century uses past 99 levels), sampleTraitTicketsAtLevel, top-2 by BAF score per round
- Documented BAF leaderboard tracking: recordBafFlip, bafTotals, _updateBafTop insertion sort, epoch-based lazy reset, _clearBafTop cleanup
- Assessed DSC-02 impact on BAF: sampleFarFutureTickets reads _tqWriteKey (post-swap empty), causing Slices D and D2 (~10% of pool) to recycle as refund -- INFO severity (no funds lost, minor fairness skew)
- Confirmed winnerMask is dead code: constructed across up to 40 scatter iterations (DJ:501-513) but return value discarded at EM:361 -- BAF-02 INFO (wasted gas)
- Documented payout processing: large winner threshold (5% of pool), large winners get 50/50 ETH/lootbox with auto-rebuy, small winners alternate 100% ETH or 100% lootbox

## Task Commits

Each task was committed atomically:

1. **Task 1: Audit BAF winner selection in DegenerusJackpots.sol** - `843f5319` (docs)
2. **Task 2: Audit BAF payout processing in EndgameModule and cleanup** - `843f5319` (docs, same commit -- both sections in single audit document)

## Files Created/Modified

- `audit/v4.0-other-jackpots-baf.md` - BAF jackpot audit with 7 sections (overview, prize distribution, DSC-02 impact, winnerMask analysis, payout processing, cleanup, findings summary), 161 file:line citations (100 DJ, 50 EM, 5 DG, 6 AM)

## Decisions Made

- BAF is a two-contract system: DegenerusJackpots for winner selection (runBafJackpot), EndgameModule for payout processing (_runBafJackpot) via delegatecall
- winnerMask confirmed dead code -- NatSpec claims scatter winners get "ticket routing" treatment but no consuming code exists (BAF-02)
- DSC-02 from Phase 81 affects ~10% of BAF pool (far-future slices D and D2) -- assessed as INFO since the ETH recycles as refund, not lost

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Known Stubs

None - all sections contain verified code citations, no placeholder data.

## Next Phase Readiness

- BAF payout processing pattern (large/small threshold, auto-rebuy) provides comparison baseline for degenerette _addClaimableEth audit (87-04)
- DSC-02 cross-reference established -- will carry to consolidated findings (Phase 89)
- 2 INFO findings + 1 cross-ref documented; none blocking

## Self-Check: PASSED

- audit/v4.0-other-jackpots-baf.md: FOUND (532 lines, 161 citations)
- Commit 843f5319: FOUND

---
*Phase: 87-other-jackpots*
*Completed: 2026-03-23*
