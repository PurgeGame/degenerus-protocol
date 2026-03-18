---
phase: 28-cross-cutting-verification
plan: "02"
subsystem: audit
tags: [solidity, invariants, security-audit, pool-accounting, claimablePool, INV-01, INV-02]

requires:
  - phase: 26-gameover-path-audit
    provides: 6 GAMEOVER claimablePool mutation sites with Phase 26 algebraic proofs
  - phase: 27-payout-claim-path-audit
    provides: 8 normal-gameplay claimablePool mutation sites with Phase 27 algebraic proofs

provides:
  - Unified standalone algebraic proof of claimablePool solvency (INV-01) at all 15 mutation sites
  - Pool accounting conservation proof (INV-02) for futurePrizePool, nextPrizePool, currentPrizePool, claimablePool
  - Identification and proof of DegeneretteModule:1158 as previously uncovered mutation site D1
  - baseFuturePool vs futurePoolLocal double-draw prevention verification
  - Cross-path interaction analysis (advanceGame/GAMEOVER/auto-rebuy)

affects:
  - 28-cross-cutting-verification (downstream invariant plans INV-03/04/05)
  - FINAL-FINDINGS-REPORT.md (INV-01/INV-02 PASS verdicts)

tech-stack:
  added: []
  patterns:
    - "Algebraic invariant proof per mutation site: pre-state, delta bound, post-state inequality"
    - "Pool conservation proof: increment site enumeration + decrement site enumeration + zero-sum check"

key-files:
  created:
    - audit/v3.0-cross-cutting-invariants-pool.md
  modified: []

key-decisions:
  - "INV-01 PASS: all 15 claimablePool mutation sites proven solvency-preserving (15 not 14 -- DegeneretteModule D1 added)"
  - "INV-02 PASS: all 4 pool variables have conservation proofs; auto-rebuy is zero-sum; coinflip economy fully isolated"
  - "DegeneretteModule:1158 is a real claimablePool mutation site not in Phase 26/27 scope; proven correct here"
  - "DegeneretteModule._addClaimableEth lacks auto-rebuy and gameOver check -- by design (degenerette uses simpler payout path); capped by ETH_WIN_CAP_BPS and prizePoolFrozen guard"
  - "baseFuturePool snapshot vs futurePoolLocal running total: BAF and x00 decimator draw from snapshot; normal decimator from running total; prevents double-draw"

patterns-established:
  - "Cross-cutting invariant proof: enumerate ALL mutation sites across all paths; prove each algebraically; prove cross-system interactions cannot compound violations"

requirements-completed: [INV-01, INV-02]

duration: 5min
completed: 2026-03-18
---

# Phase 28 Plan 02: Pool Invariant Proofs Summary

**Algebraic proofs for claimablePool solvency (INV-01) and pool accounting conservation (INV-02) at all 15 mutation sites across full protocol; DegeneretteModule:1158 identified as previously uncovered site D1 and proven correct**

## Performance

- **Duration:** 5 min
- **Started:** 2026-03-18T06:55:04Z
- **Completed:** 2026-03-18T07:00:05Z
- **Tasks:** 2 (INV-01 proof, INV-02 proof -- combined into single document)
- **Files modified:** 1

## Accomplishments

- Proved INV-01 at all 15 claimablePool mutation sites: 6 GAMEOVER (G1-G6), 8 normal-gameplay (N1-N8), and 1 previously-uncovered DegeneretteModule (D1). Each proof is algebraic and standalone.
- Proved INV-02 conservation for all 4 pool variables (futurePrizePool, nextPrizePool, currentPrizePool, claimablePool) with complete increment/decrement site enumeration.
- Identified DegeneretteModule:704/1158 as a real claimablePool mutation site not in Phase 26 or Phase 27 scope; proven correct (ETH_WIN_CAP_BPS and futurePrizePool pre-deduction ensure the invariant holds).
- Verified baseFuturePool snapshot vs futurePoolLocal running total distinction prevents double-drawing from the same ETH.
- Cross-path interaction analysis confirmed no interleaving, race conditions, or double-counting across GAMEOVER, normal gameplay, and auto-rebuy paths.

## Task Commits

1. **Tasks 1 + 2: INV-01 and INV-02 pool invariant proofs** - `be4129f9` (feat)

**Plan metadata:** committed with SUMMARY.md

## Files Created/Modified

- `audit/v3.0-cross-cutting-invariants-pool.md` -- Unified INV-01 and INV-02 proof document (861 lines, 15 mutation sites)

## Decisions Made

- DegeneretteModule:1158 is a genuine `claimablePool +=` mutation site that was out of scope for Phases 26-27. It passes INV-01 because: (1) `ethPortion` is capped at `ETH_WIN_CAP_BPS * futurePrizePool / 10_000`; (2) `futurePrizePool` is decremented before the call; (3) all ETH already held in-contract.
- DegeneretteModule's `_addClaimableEth` does NOT check `gameOver` and does NOT support auto-rebuy. This is intentional: Degenerette is a mini-game (not jackpot infrastructure) and uses a simpler payout model. The `prizePoolFrozen` guard at line 685 prevents concurrent access during jackpot computation.
- Auto-rebuy `claimablePool -= calc.ethSpent` (Site N6, DecimatorModule:494) is proven safe as a zero-sum internal reallocation: the pre-reservation at the pool resolution step ensures `claimablePool` already contains the funds being converted.
- G5 (DecimatorModule:936) does NOT directly mutate `claimablePool` at claim time -- the pre-reservation at G2 covers all terminal dec claims. The `_addClaimableEth` in DecimatorModule routes to `_creditClaimable` without a pool increment. This is correct and previously verified in Phase 26.

## Deviations from Plan

### Auto-fixed Issues

None.

**Deviation:** The plan specified Tasks 1 and 2 as separate tasks (INV-01 first, then INV-02 appended). Both were completed in a single write operation producing one commit, since the INV-02 content was fully derivable from the same contract reads already loaded for INV-01. This is a workflow optimization, not a scope change.

## Issues Encountered

None.

## Next Phase Readiness

- INV-01 and INV-02 have PASS verdicts with standalone algebraic proofs
- `audit/v3.0-cross-cutting-invariants-pool.md` ready for cross-reference in subsequent plans (INV-03/04/05)
- DegeneretteModule gap is documented and closed; no new findings above INFORMATIONAL severity
- Phase 28 Plan 03 can proceed with INV-03 (sDGNRS supply conservation)

---
*Phase: 28-cross-cutting-verification*
*Completed: 2026-03-18*
