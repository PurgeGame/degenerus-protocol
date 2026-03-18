---
phase: 28-cross-cutting-verification
plan: 03
subsystem: audit
tags: [smart-contract-audit, supply-invariants, burnie, sdgnrs, claimability, defi]

# Dependency graph
requires:
  - phase: 28-01
    provides: CHG-01 commit coverage map confirming no post-audit code changes invalidated prior proofs
  - phase: 27
    provides: All 19 payout/claim path verdicts (PASS) and coinflip economy analysis (PAY-07/08)
  - phase: 21
    provides: NOVEL-05 formal proof of sDGNRS supply conservation
requires:
  - phase: 28-01
    provides: CHG-01/02/03/04 regression baseline; confirms sDGNRS/BurnieCoin supply paths unchanged

provides:
  - INV-03 PASS: sDGNRS supply conservation formally proven valid across all 6 modification paths with CHG-01 regression confirmation
  - INV-04 PASS: BURNIE mint/burn lifecycle fully enumerated; virtual stake ledger proven consistent; no unbacked mint path
  - INV-05 PASS: 25 claim paths enumerated with expiry classification; all 9 expiring mechanisms documented in KNOWN-ISSUES.md; no locked funds
affects:
  - 28-04 (edge case analysis -- INV-05 provides claim path baseline for EDGE-01/02)
  - 28-05 (vulnerability ranking -- INV-03/04 supply paths inform which functions modify critical state)
  - 28-06 (consolidation -- all three invariants feed into final protocol assessment)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Exhaustive path enumeration for invariant proofs (extending NOVEL-05 methodology)"
    - "25-path claim enumeration with A/B/C/D classification (PERMANENT / EXPIRING-INTENTIONAL / EXPIRING-UNDOCUMENTED / UNCLAIMABLE)"
    - "Lifecycle closure proof: virtual stake ledger -> physical mint at claim time"

key-files:
  created:
    - audit/v3.0-cross-cutting-invariants-supply.md
  modified: []

key-decisions:
  - "INV-03 PASS: NOVEL-05 formal proof remains valid post CHG-01 regression; no new supply-modifying paths introduced since Phase 21"
  - "INV-04 PASS: BURNIE coinflip virtual stakes are never physically minted until claim; stake clearance on win/loss prevents double-claim"
  - "INV-05 PASS: Forfeited decimator claims do NOT lock ETH -- the backing remains as overcollateralization; expired coinflip virtual stakes were never minted"
  - "INV-05 PASS: 16 claim paths are PERMANENT (no expiry), 9 are EXPIRING-INTENTIONAL (documented in KNOWN-ISSUES.md)"
  - "WWXRP classified as PERMANENT claimability -- standard ERC20 held indefinitely; underlying wXRP backing is speculative by design"

patterns-established:
  - "Claim path classification (A/B/C/D) methodology for INV-05 analysis"
  - "Cross-reference virtual-vs-physical supply distinction for BURNIE lifecycle proofs"

requirements-completed: [INV-03, INV-04, INV-05]

# Metrics
duration: 3min
completed: 2026-03-18
---

# Phase 28 Plan 03: Supply Conservation and Claimability Invariants Summary

**sDGNRS supply conservation re-proven (NOVEL-05 still valid), BURNIE mint/burn lifecycle fully enumerated with virtual stake consistency proof, and 25 claim paths classified with 0 permanently locked or undocumented expiry paths found.**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-18T06:54:52Z
- **Completed:** 2026-03-18T06:57:52Z
- **Tasks:** 2 (INV-03/INV-04 in Task 1; INV-05 in Task 2)
- **Files modified:** 1

## Accomplishments

- INV-03 PASS: Re-verified NOVEL-05 formal proof of sDGNRS supply conservation. Confirmed all 6 modification paths preserve `totalSupply == SUM(balanceOf)`. Confirmed no new supply-modifying paths were introduced by CHG-01 commits.
- INV-04 PASS: Enumerated all BURNIE mint paths (4 physical mints) and burn paths (4 physical burns). Proved the virtual stake ledger is internally consistent -- stakes cleared on processing (win/loss), no double-claim path, physical minting only at claim time.
- INV-05 PASS: Enumerated all 25 claim paths in the protocol with expiry classification. Found 16 PERMANENT (no expiry), 9 EXPIRING-INTENTIONAL (all documented in KNOWN-ISSUES.md), 0 undocumented or unclaimable paths.

## Task Commits

1. **Tasks 1 + 2: INV-03, INV-04, INV-05 supply and claimability proofs** - `72664545` (feat)

**Plan metadata:** [pending final docs commit]

## Files Created/Modified

- `audit/v3.0-cross-cutting-invariants-supply.md` -- 402 lines: INV-03 formal proof, INV-04 lifecycle enumeration with virtual stake proof, INV-05 25-path claim enumeration with expiry classification and special case analysis

## Decisions Made

- **INV-03 methodology:** Extended NOVEL-05 proof rather than rebuilding from scratch. Confirmed no supply-modifying code changed since Phase 21. Valid reuse per research pitfall CP-02 guidance (present own analysis, can reference prior evidence).
- **INV-04 virtual stakes:** Explicitly traced the creditFlip -> claimCoinflips -> mintForCoinflip path to confirm physical minting only occurs at claim time. This resolves research open question Q5 (virtual stake ledger in proof).
- **INV-05 decimator clarification:** Forfeited decimator rewards do NOT permanently lock ETH. The backing remains in the contract as overcollateralization for remaining claimants. The player's individual `claimableWinnings` entry expires; the pool ETH is not locked.
- **INV-05 WWXRP classification:** Classified as PERMANENT from a claimability standpoint (ERC20 held indefinitely) even though wXRP backing is speculative. The token itself has no forced expiry.

## Deviations from Plan

None - plan executed exactly as written. Both tasks completed in a single document write since INV-03/04 and INV-05 were analyzed concurrently from the same contract reads.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- INV-03, INV-04, INV-05 all PASS with explicit verdicts
- Claim path enumeration (25 paths) provides a complete baseline for EDGE-01/02 edge case analysis in Plan 04
- Supply conservation proofs provide a reference for VULN ranking in Plan 05 (which functions modify critical supply state)
- No blockers

---
*Phase: 28-cross-cutting-verification*
*Completed: 2026-03-18*
