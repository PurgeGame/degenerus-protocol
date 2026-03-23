---
phase: 87-other-jackpots
plan: 03
subsystem: audit
tags: [solidity, jackpot, decimator, terminal-decimator, death-bet, burn-tracking, pro-rata, bucket-migration]

# Dependency graph
requires:
  - phase: 81-ticket-creation-queue
    provides: ticket queue mechanics and auto-rebuy context for decimator claim paths
provides:
  - Regular decimator full lifecycle trace (burn tracking with bucket migration, resolution with packed subbucket offsets, pro-rata claims with 50/50 ETH/lootbox split)
  - Terminal decimator full lifecycle trace (activity-score bucket, time multiplier with day-10 discontinuity, GAMEOVER resolution, 100% ETH claims)
  - decBucketOffsetPacked collision analysis -- DEC-01 FALSE POSITIVE (regular decimator never resolves at stalled level; poolWei == 0 guard prevents access)
  - 7 INFO findings (DEC-02 through DEC-08) after DEC-01 withdrawal
affects: [88-rng-variable-reverification, 89-consolidated-findings]

# Tech tracking
tech-stack:
  added: []
  patterns: [per-player-burn-tracking-audit, bucket-migration-pattern, packed-offset-storage-audit, collision-analysis-methodology]

key-files:
  created:
    - audit/v4.0-other-jackpots-decimator.md
  modified: []

key-decisions:
  - "decBucketOffsetPacked collision between regular and terminal decimator at same level is a FALSE POSITIVE -- regular decimator never resolves at a stalled level; decClaimRounds[lvl].poolWei == 0 guard (DM:275) prevents access to overwritten packed offsets"
  - "Terminal decimator time multiplier discontinuity at day 10 (2.75x drops to 2x) is intentional per NatSpec at DM:902"
  - "uint96 truncation in lastTerminalDecClaimRound.poolWei capped at ~79.2B ETH -- benign (unreachable in practice)"

patterns-established:
  - "Per-player burn tracking with bucket migration on better bucket (lower denom)"
  - "Pro-rata claim calculation: (poolWei * playerBurn) / totalBurn"
  - "Packed offset storage: 4 bits per denom in uint64 decBucketOffsetPacked"

requirements-completed: [OJCK-03, OJCK-06]

# Metrics
duration: 12min
completed: 2026-03-23
---

# Phase 87 Plan 03: Decimator Jackpot Audit Summary

**Regular decimator (burn/resolution/claim with bucket migration and packed subbucket offsets) and terminal decimator (activity-score bucket, time multiplier, GAMEOVER resolution) fully traced with 323 file:line citations; DEC-01 decBucketOffsetPacked collision analyzed and withdrawn as FALSE POSITIVE; 7 INFO findings (DEC-02 through DEC-08)**

## Performance

- **Duration:** 12 min
- **Started:** 2026-03-23T10:14:30Z
- **Completed:** 2026-03-23T10:14:42Z
- **Tasks:** 2/2
- **Files created:** 1 (audit/v4.0-other-jackpots-decimator.md, 801 lines)

## Accomplishments

- Traced regular decimator burn tracking (recordDecBurn): bucket assignment (denom 2-12), deterministic subbucket via hash, bucket migration on better bucket, effective amount with 200-mint cap, uint192 saturation, subbucket aggregate updates
- Traced regular decimator resolution (runDecimatorJackpot): per-denom winning subbucket selection, 4-bit packed offset storage in decBucketOffsetPacked, double-snapshot guard, DecClaimRound snapshot
- Traced regular decimator claims (claimDecimatorJackpot): prizePoolFrozen guard, winning subbucket match, pro-rata calculation, 50/50 ETH/lootbox split (normal mode) vs 100% ETH (GAMEOVER mode)
- Traced terminal decimator burn tracking (recordTerminalDecBurn): activity-score bucket (not player-chosen), time restriction (blocked when <= 1 day remaining), time multiplier with intentional day-10 discontinuity, lazy reset on level change
- Traced terminal decimator resolution (runTerminalDecimatorJackpot): same subbucket selection as regular, decBucketOffsetPacked shared write, lastTerminalDecClaimRound snapshot (uint96 poolWei)
- Traced terminal decimator claims: always 100% ETH (GAMEOVER context), weightedBurn zeroed as claim flag
- Analyzed decBucketOffsetPacked collision: initially flagged as DEC-01 MEDIUM, then withdrawn as FALSE POSITIVE after verifying regular decimator's poolWei == 0 guard prevents access to overwritten packed offsets
- Documented complete storage layout for both regular and terminal decimator with struct field types and slot references

## Task Commits

Each task was committed atomically:

1. **Task 1: Audit regular decimator burn tracking, resolution, and claims** - `de80ab7a` (docs)
2. **Task 2: Audit terminal decimator and cross-cutting analysis** - `de80ab7a` (docs, same commit -- both sections in single audit document)

## Files Created/Modified

- `audit/v4.0-other-jackpots-decimator.md` - Decimator jackpot audit with 5 sections (regular decimator, terminal decimator, collision analysis, storage layout, findings summary), 323 file:line citations (241 DM, 19 EM, 44 GS, 19 GOVM)

## Decisions Made

- decBucketOffsetPacked collision (DEC-01) withdrawn as FALSE POSITIVE: regular decimator never resolves at a stalled level because the level transition must complete before GAMEOVER can trigger, and the decClaimRounds[lvl].poolWei == 0 guard prevents accessing overwritten packed offsets
- Terminal decimator time multiplier discontinuity at day 10 (2.75x drops to 2x between day 11 and day 10) is intentional per NatSpec at DM:902 -- documented as DEC-02 INFO
- uint96 truncation of lastTerminalDecClaimRound.poolWei (capped at ~79.2B ETH) is benign since ETH total supply is nowhere near this value -- documented as DEC-03 INFO

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Known Stubs

None - all sections contain verified code citations, no placeholder data.

## Next Phase Readiness

- Decimator auto-rebuy in _addClaimableEth confirmed (DM:414-424) -- provides comparison point for degenerette audit (87-04)
- DEC-01 FALSE POSITIVE methodology (analyzing shared packed storage collision with guard analysis) established as pattern for future collision analysis
- 7 INFO findings documented; none blocking

## Self-Check: PASSED

- audit/v4.0-other-jackpots-decimator.md: FOUND (801 lines, 323 citations)
- Commit de80ab7a: FOUND

---
*Phase: 87-other-jackpots*
*Completed: 2026-03-23*
