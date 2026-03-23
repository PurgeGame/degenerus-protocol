---
phase: 85-daily-eth-jackpot
plan: 02
subsystem: audit
tags: [solidity, jackpot, bucket-algorithm, carryover, cursor-resume, cross-reference, rng-catalog]

# Dependency graph
requires:
  - phase: 85-daily-eth-jackpot (plan 01)
    provides: audit/v4.0-daily-eth-jackpot.md Sections 1-9 (BPS allocation, Phase 0/1, early-burn)
  - phase: 81-ticket-creation-queue
    provides: ticket queue mechanics and trait ticket understanding
provides:
  - JackpotBucketLib 8 functions documented (bucket sizing, shares, ordering) with JBL:{line} citations
  - _processDailyEthChunk line-by-line trace (gas budget, cursor save, empty bucket handling)
  - Resume logic proven deterministic via stored-state argument
  - Carryover source selection full decision tree (_selectCarryoverSourceOffset)
  - Carryover pool 1% drip formula with pre-deduction loss path flagged
  - Complete cross-reference against v3.2, v3.8, PAYOUT-SPECIFICATION, v4.0-ticket-creation (13 items)
  - RNG-dependent variables catalog (13 consumption points, all safe)
  - All 5 DETH requirements VERIFIED with evidence
affects: [86-daily-coin-ticket-jackpot, 87-other-jackpots, 84-prize-pool-flow, 88-rng-variable-reverification]

# Tech tracking
tech-stack:
  added: []
  patterns: [algorithmic-trace-with-determinism-proof, rng-consumption-catalog, comprehensive-cross-reference]

key-files:
  created: []
  modified:
    - audit/v4.0-daily-eth-jackpot.md

key-decisions:
  - "Chunked daily path (_processDailyEthChunk) does NOT use solo bucket 75/25 ETH/whale-pass split -- deliberate design for gas-predictable per-winner costs"
  - "Pre-deduction carryover loss path assessed as INFO severity (0.5% futurePrizePool, low frequency, improves solvency)"
  - "NF-V38-01: v3.8 omits whalePassClaims from payDailyJackpot scope -- INFO (early-burn path only, outside chunked daily scope)"
  - "All 13 RNG consumption points verified safe per VRF commitment window analysis"

patterns-established:
  - "Entropy fast-forward pattern: _skipEntropyToBucket replays LCG steps for cursor resume"
  - "Bucket ordering optimization: largest-first maximizes gas utilization per advanceGame call"
  - "Pre-deduction model for carryover: futurePrizePool deducted upfront, undistributed ETH becomes solvency buffer"

requirements-completed: [DETH-03, DETH-04, DETH-05]

# Metrics
duration: 10min
completed: 2026-03-23
---

# Phase 85 Plan 02: Daily ETH Jackpot -- Bucket Algorithm, Carryover Mechanics, Cross-Reference, and Requirement Verdicts Summary

**JackpotBucketLib 8 functions traced, _processDailyEthChunk line-by-line with determinism proof, carryover source selection decision tree, pre-deduction loss path flagged (INFO), 13-entry RNG catalog verified safe, comprehensive cross-reference (13 items, 11 INFO findings), all 5 DETH requirements VERIFIED**

## Performance

- **Duration:** 10 min
- **Started:** 2026-03-23T15:16:14Z
- **Completed:** 2026-03-23T15:26:14Z
- **Tasks:** 2/2
- **Files modified:** 1 (audit/v4.0-daily-eth-jackpot.md, 1130 -> 2250 lines, +1120 lines)

## Accomplishments

- Documented all 8 JackpotBucketLib functions (JBL:36-306) with full Solidity quotes and line citations: traitBucketCounts, scaleTraitBucketCountsWithCap, bucketCountsForPoolCap, capBucketCounts, bucketShares, soloBucketIndex, shareBpsByBucket, bucketOrderLargestFirst
- Traced _processDailyEthChunk (JM:1387-1509) line-by-line: gas budget via _winnerUnits (1x normal, 3x auto-rebuy), outer loop bucket iteration (largest-first), inner loop winner iteration with gas check, cursor save on exhaustion, empty bucket skip, liability batching
- Proved resume logic deterministic: all 7 inputs verified immutable during distribution, _skipEntropyToBucket replays entropy identically, traitBurnTicket stability proven via advance flow ordering guard
- Documented _selectCarryoverSourceOffset (JM:2708-2750) full decision tree: _hasActualTraitTickets -> _highestCarryoverSourceOffset -> random probe with wrap-around
- Flagged pre-deduction carryover loss path: when Phase 0 uses all 321 winners, 0.5% of futurePrizePool becomes unattributed (INFO severity -- low frequency, improves solvency)
- Cataloged all 13 RNG consumption points with VRF commitment window analysis (all safe)
- Cross-referenced 38+ items across v3.2, v3.8, PAYOUT-SPECIFICATION, v4.0-ticket-creation. Found 11 INFO findings (10 discrepancies + 1 new, 1 resolved)
- All 5 DETH requirements VERIFIED with evidence citations

## Task Commits

Each task was committed atomically:

1. **Task 1: Document bucket/cursor winner selection algorithm and resume logic** - `ce124cd9` (feat)
2. **Task 2: Document carryover mechanics, complete cross-reference, and compile verdicts** - `c27990b1` (feat)

## Files Created/Modified

- `audit/v4.0-daily-eth-jackpot.md` - Appended Sections 10-20: JackpotBucketLib functions, _processDailyEthChunk core loop, resume logic with determinism proof, carryover source selection, carryover pool calculation, carryover edge cases, complete cross-reference, RNG catalog, requirement verdicts, finding summary, audit metadata

## Decisions Made

- Chunked daily path does NOT use solo bucket 75/25 ETH/whale-pass split (only non-chunked _resolveTraitWinners path does) -- deliberate design for gas-predictable per-winner costs
- Pre-deduction carryover loss path assessed as INFO: requires 321+ Phase 0 winners (200+ ETH pool with max scaling), affects only 0.5% of futurePrizePool, and the ETH stays in contract improving solvency
- NF-V38-01: v3.8 Section 1.7 omits whalePassClaims and levelStartTime from payDailyJackpot scope -- assessed as INFO because these are only reachable via early-burn path, outside the chunked daily scope that v3.8 targets
- All 13 RNG consumption points verified safe: no player-controllable state can change between VRF request and fulfillment that affects daily ETH jackpot outcomes

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Known Stubs

None - all sections contain verified code citations, no placeholder data.

## Next Phase Readiness

- The complete audit/v4.0-daily-eth-jackpot.md (2250 lines, 726 file:line citations) covers all 5 DETH requirements exhaustively
- Phase 86 (daily coin + ticket jackpot) can reference the bucket/cursor mechanics documented here
- Phase 88 (RNG variable re-verification) can reference the 13-entry RNG catalog in Section 17
- Phase 84 (prize pool flow) can reference the carryover pre-deduction model documented in Section 15

## Self-Check: PASSED

- audit/v4.0-daily-eth-jackpot.md: FOUND (2250 lines, 726 citations)
- Commit ce124cd9: FOUND
- Commit c27990b1: FOUND

---
*Phase: 85-daily-eth-jackpot*
*Completed: 2026-03-23*
