---
phase: 04-eth-token-accounting-integrity
plan: 01
subsystem: accounting
tags: [eth-flow, pool-attribution, invariant, solidity-audit, remainder-pattern]

# Dependency graph
requires:
  - phase: 03a-core-eth-flow-modules
    provides: "Initial BPS split verification and remainder pattern confirmation"
  - phase: 03b-vrf-dependent-modules
    provides: "GO-F01 deity refund finding (now resolved by refundDeityPass removal)"
provides:
  - "Complete ETH inflow/outflow trace with line-by-line verification across current contract state"
  - "ACCT-01 core invariant verdict (PASS, unconditional)"
  - "ACCT-06 receive() routing verdict (PASS)"
  - "Documentation of refundDeityPass removal and its impact on invariant"
affects: [04-02-invariant-manual-trace, 04-04-reentrancy-analysis, 04-06-game-over-settlement]

# Tech tracking
tech-stack:
  added: []
  patterns: ["remainder-pattern for BPS splits (b = total - a, not b = total * bps / 10000)"]

key-files:
  created:
    - ".planning/phases/04-eth-token-accounting-integrity/04-01-FINDINGS-eth-flow-trace.md"
  modified: []

key-decisions:
  - "ACCT-01 verdict upgraded from PASS (conditional) to PASS (unconditional) due to refundDeityPass removal"
  - "refundDeityPass elimination resolves GO-F01 MEDIUM cross-path double-refund risk"
  - "receive() gameOver guard prevents post-gameOver unattributed ETH accumulation"

patterns-established:
  - "ETH inflow remainder pattern: all pool splits use b = total - a to guarantee zero dust"
  - "ETH outflow pattern: claimablePool reduced before external call (CEI), amount sent equals reduction"

requirements-completed: [ACCT-01, ACCT-06]

# Metrics
duration: 6min
completed: 2026-03-06
---

# Phase 04 Plan 01: ETH Flow Trace Summary

**Complete ETH inflow/outflow trace across 15 paths with ACCT-01 invariant PASS (unconditional) and ACCT-06 receive() routing PASS**

## Performance

- **Duration:** 6 min
- **Started:** 2026-03-06T19:36:20Z
- **Completed:** 2026-03-06T19:42:54Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments
- Traced all 7 ETH inflow paths (purchase, whaleBundle, deityPass, degenerette bets, receive, lazyPass, adminSwap) with updated line numbers against current 2812-line contract
- Traced all 5 ETH outflow paths (claimWinnings, adminSwapEthForStEth, handleGameOverDrain, handleFinalSweep) plus documented refundDeityPass removal
- Traced 3 internal conversion paths (_autoStakeExcessEth, adminStakeEthForStEth, degenerette _distributePayout)
- Upgraded ACCT-01 verdict from conditional to unconditional PASS (GO-F01 cross-path risk eliminated by refundDeityPass removal)
- Confirmed ACCT-06 PASS with documentation of new gameOver guard on receive()

## Task Commits

Both tasks write to the same artifact file (04-01-FINDINGS-eth-flow-trace.md), so they share a single commit:

1. **Task 1: Trace all 5 ETH inflow paths and verify pool attribution** - `ccc9af4` (feat)
2. **Task 2: Trace all 5 ETH outflow paths and verify pool reduction** - `ccc9af4` (same commit, same file)

## Files Created/Modified
- `.planning/phases/04-eth-token-accounting-integrity/04-01-FINDINGS-eth-flow-trace.md` - Complete ETH flow trace with per-path verdicts, ACCT-01 and ACCT-06 requirement assessments

## Decisions Made
- **ACCT-01 upgraded to unconditional PASS:** The prior audit's conditional qualifier (GO-F01 double deity refund) is resolved because `refundDeityPass()` was entirely removed from the contract. The only deity pass refund path is now `handleGameOverDrain()`, guarded by `gameOverFinalJackpotPaid`.
- **receive() gameOver guard documented:** The `receive()` function now reverts after `gameOver` (line 2809), preventing unattributed ETH from accumulating post-game. This is a security improvement over the prior unconditional version.
- **NatSpec inconsistency noted (INFO-02):** WhaleModule fund distribution percentages in DegenerusGame.sol NatSpec (50%/25%/25%) don't match actual code (70%/30% at level 0, 95%/5% otherwise). Code is self-consistent; documentation-only issue.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Updated refundDeityPass from active outflow to removed status**
- **Found during:** Task 2 (outflow trace)
- **Issue:** Plan expected refundDeityPass as outflow path 2, but the function has been removed from the contract
- **Fix:** Documented as "REMOVED / N/A" in findings, updated ACCT-01 verdict to unconditional PASS
- **Files modified:** 04-01-FINDINGS-eth-flow-trace.md
- **Verification:** `grep -r "refundDeityPass" contracts/` returns no matches
- **Committed in:** ccc9af4

**2. [Rule 1 - Bug] Updated receive() to reflect gameOver guard**
- **Found during:** Task 1 (inflow trace)
- **Issue:** Plan expected unconditional receive(), but current contract has `if (gameOver) revert E()` guard
- **Fix:** Documented gameOver guard in inflow trace and ACCT-06 verdict
- **Files modified:** 04-01-FINDINGS-eth-flow-trace.md
- **Verification:** Confirmed line 2809: `if (gameOver) revert E();`
- **Committed in:** ccc9af4

---

**Total deviations:** 2 auto-fixed (2 bug/contract-change updates)
**Impact on plan:** Both deviations reflect contract improvements since the plan was written. They strengthen the invariant assessment -- no scope creep.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- ETH flow map complete; ready for invariant harness (04-02), BPS fee split audit (04-03), and reentrancy analysis (04-04)
- refundDeityPass removal simplifies all downstream analyses (no cross-path double-refund concern)

---
*Phase: 04-eth-token-accounting-integrity*
*Completed: 2026-03-06*
