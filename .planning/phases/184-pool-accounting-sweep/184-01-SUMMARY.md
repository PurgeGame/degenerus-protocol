---
phase: 184-pool-accounting-sweep
plan: 01
subsystem: audit
tags: [solidity, futurePool, currentPool, pool-accounting, debit-credit-trace, ETH-conservation]

# Dependency graph
requires:
  - phase: 183-jackpot-eth-fix
    provides: deferred futurePool SSTORE capturing paidEth return value (baseline fix)
provides:
  - complete debit/credit trace for futurePool (23 sites) and currentPool (6 sites) across all modules
  - verification that all reserve contributions (reserveSlice, reserveContribution, reserved drawdown) are traced to nextPool
  - confirmation that Phase 183 deferred-SSTORE fix closes the only accounting gap
affects: [184-pool-accounting-sweep, nextPool-audit, claimablePool-audit]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "pool-audit-format: SITE-XX-NN numbered entries with Operation, Source/Dest, Counterpart verified, Remainder risk, Notes"

key-files:
  created:
    - .planning/phases/184-pool-accounting-sweep/184-futurePool-currentPool-audit.md
  modified: []

key-decisions:
  - "Audit traces committed code (pre-Phase-183) and documents the Phase 183 fix as the correct baseline"
  - "Triple-division dust in MintModule lootbox split (up to 2 wei/purchase) rated INFO -- captured by yield surplus distribution"
  - "Freeze-state dual paths verified as equivalent for all sites -- no separate SITE entries needed for frozen path"

patterns-established:
  - "SITE-XX-NN audit entry format for pool accounting traces"
  - "Cross-referencing between futurePool and currentPool entries for shared operations (consolidatePrizePools, GameOver zeroing)"

requirements-completed: [SWEEP-01, SWEEP-04]

# Metrics
duration: 7min
completed: 2026-04-04
---

# Phase 184 Plan 01: futurePool + currentPool Debit/Credit Audit Summary

**Complete debit/credit trace of 29 pool mutation sites (23 futurePool + 6 currentPool) across 8 contracts with 0 accounting gaps when Phase 183 fix is applied**

## Performance

- **Duration:** 7 min
- **Started:** 2026-04-04T19:31:51Z
- **Completed:** 2026-04-04T19:38:57Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments
- Traced all 23 futurePool mutation sites across JackpotModule (8), AdvanceModule (2), DecimatorModule (2), DegeneretteModule (2), GameOverModule (2), WhaleModule (3), MintModule (1), DegenerusGame (3) with counterpart verification
- Traced all 6 currentPool mutation sites across JackpotModule (4) and GameOverModule (2)
- Confirmed Phase 183 deferred-SSTORE fix closes the only accounting gap (SITE-FP-02: paidEth return value discarded in committed code)
- Verified all 3 reserve contribution flows (SWEEP-04): reserveSlice (0.5% daily carryover), reserveContribution (3% early-bird lootbox), reserved (15% drawdown) -- all traced to nextPool
- Identified 1 INFO finding: MintModule triple-division truncation dust (up to 2 wei/purchase, captured by yield surplus)
- Verified runRewardJackpots accumulator + rebuyDelta reconciliation pattern is correct
- Verified consolidatePrizePools is a balanced multi-step transfer (nextPool -> currentPool exact, futurePool -> currentPool via keep-roll)

## Task Commits

1. **Task 1: Trace all futurePool mutation sites** - `a17bd3e7` (docs)
2. **Task 2: Trace all currentPool mutation sites and produce combined audit table** - `36e17157` (docs)

## Files Created/Modified
- `.planning/phases/184-pool-accounting-sweep/184-futurePool-currentPool-audit.md` - Complete debit/credit trace with 29 SITE entries and combined summary table

## Decisions Made
- **Committed code vs Phase 183 fix:** Audit documents both states. The committed code has 1 PARTIAL verification (FP-02 discards paidEth). With Phase 183 fix applied, all 29 sites are fully verified. The Phase 183 fix is the correct baseline.
- **MintModule dust rated INFO:** Triple-division in lootbox split (`futureBps`, `nextBps`, `vaultBps` each divided independently) can leave up to 2 wei untracked per purchase. This is captured by `_distributeYieldSurplus` which treats `totalBal - obligations` as yield. No practical risk.
- **Freeze-state paths not separately numbered:** All dual-path sites (frozen/unfrozen) use identical amounts via `_setPendingPools`/`_setPrizePools`. `_unfreezePool` applies pending atomically. Noted in each entry rather than creating separate SITE entries.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- futurePool and currentPool fully audited; ready for nextPool and claimablePool sweep (if planned as 184-02/03)
- Phase 183 fix must be committed before the accounting is considered fully clean
- The INFO finding (MintModule dust) does not require a code change

---
*Phase: 184-pool-accounting-sweep*
*Completed: 2026-04-04*
