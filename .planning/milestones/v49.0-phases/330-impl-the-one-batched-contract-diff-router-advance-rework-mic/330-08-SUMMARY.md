---
phase: 330-impl-the-one-batched-contract-diff-router-advance-rework-mic
plan: 08
subsystem: testing
tags: [foundry, rename, oracle-migration, gasopt]

requires:
  - phase: 330-impl-the-one-batched-contract-diff-router-advance-rework-mic
    provides: "330-03 degeneretteResolve rename; 330-06 AutoBought removal + lastAutoBoughtDay oracle; 330-07 doWork/escape surface"
provides:
  - "the 5-file autoResolve→degeneretteResolve rename (incl. CrankLeversAndPacking literal source-string assertions)"
  - "the AutoBought-event oracle migrated to lastAutoBoughtDay/pool-balance-delta across the 4 AfKing-family + 2 collision files"
  - "a compiling suite under the renamed contract surface (the deep behavioral router rework is Phase 332)"
affects: [332]

tech-stack:
  added: []
  patterns:
    - "Storage-stamp + pool-delta oracle replacing an emitted-event log drain for a no-double-buy assertion"

key-files:
  created: []
  modified:
    - test/fuzz/CrankFaucetResistance.t.sol
    - test/fuzz/CrankNonBrick.t.sol
    - test/fuzz/RngFreezeAndRemovalProofs.t.sol
    - test/gas/CrankResolveBetWorstCaseGas.t.sol
    - test/gas/CrankLeversAndPacking.t.sol
    - test/fuzz/AfKingConcurrency.t.sol
    - test/gas/SweepPerPlayerWorstCaseGas.t.sol
    - test/fuzz/AfKingFundingWaterfall.t.sol
    - test/fuzz/AfKingSubscription.t.sol

key-decisions:
  - "The no-double-buy invariant `_countAutoBoughtFor(sub)==1` is re-expressed in lastAutoBoughtDay + pool-balance-delta terms (the storage stamp is the authoritative oracle the contract itself reads at :627) without weakening SAFE-03 / H-CANCEL-SWAP."
  - "Residual `AutoBought` tokens in 3 AfKing-family files are explanatory comments / helper-name prose only — the live `keccak256(\"AutoBought(...)\")` topic-match + getRecordedLogs() drain were removed."
  - "This plan's job is rename/oracle parity + keeping the suite COMPILING; the deep behavioral router proofs (one-rewarded-category, no-double-pay, mult-honored, non-widening) are TST-02/03/04 at Phase 332."

patterns-established: []

requirements-completed: [GASOPT-04]

duration: part of BATCH-02
completed: 2026-05-27
---

# Phase 330 Plan 08: test rename + AutoBought oracle migration — Summary

**The 9 affected test files are brought into lock-step with the renamed `degeneretteResolve` and the removed `AutoBought` event in the same batched diff, so the suite compiles under the redesign — with the deep behavioral router rework explicitly carried to Phase 332.**

## Performance
- **Mode:** applied as part of the single USER-approved BATCH-02 diff (commit `63bc16ca`)
- **Completed:** 2026-05-27
- **Tasks:** 2
- **Files modified:** 9

## Accomplishments
- **Rename (5 files):** every `autoResolve`/`_autoResolveBet` → `degeneretteResolve`/`_degeneretteResolveBet`, including the `CrankLeversAndPacking.t.sol` literal source-string assertions (`_countOccurrences(game_, "function degeneretteResolve(")`) — 0 residual old symbols across all 5.
- **AutoBought oracle migration (4 AfKing-family + 2 collision):** the `keccak256("AutoBought(...)")` topic-match + `getRecordedLogs()` drain replaced by `lastAutoBoughtDay`/pool-balance-delta assertions; the no-double-buy / SAFE-03 / H-CANCEL-SWAP proofs preserved at ≥ the same strength. Residual `AutoBought` tokens (AfKingConcurrency/Sweep/FundingWaterfall) are comments + helper-name prose only — no live event reference remains.
- **Surface parity:** old-shape `autoBuy(maxCount) returns (bountyEarned)` call-sites updated to the new parameterless `doWork()` + UNREWARDED `autoBuy(count)` surface so the files compile.

## Task Commits
Test files are AGENT-committable, but rode the SAME single batched diff `63bc16ca` so the suite is coherent at the hand-review (BATCH-02 gate, 330-09).

## Files Created/Modified
- 5 rename files + 4 AutoBought-oracle files (2 overlap) — see frontmatter.

## Deviations / deferred
- **16 reward-rehoming behavioral tests now fail and are INTENTIONALLY deferred to Phase 332 TST.** They assert the SUPERSEDED reward shape (per-item summed crank reward / per-leg in-callee creditFlip), e.g. `CrankLeversAndPacking::testCrankBetsEmitsExactlyOneCreditFlipForManyItems` (asserts the in-memory SUM of 3 item rewards — now a flat-per-tx doWork bounty) and `testCrankBoxesEmitsExactlyOneCreditFlipForManyBoxes` (asserts an autoOpen-side creditFlip — now pulled into doWork). These are reworked by the TST-02/03/04 deep router proofs at Phase 332, not patched here. Suite outcome: **616 passed / 58 failed** vs the v48.0 632/42 baseline = exactly +16 flipped (the reward-rehoming set); the rest of the 58 are the unchanged pre-existing v48 VRF-path/invariant baseline failures.

## Self-Check: PASSED (with documented deferral)
- 0 `autoResolve`/`_autoResolveBet` across the 5 rename files; live `AutoBought` event drains removed across the 6 oracle files; suite compiles + runs (616/58). The +16 failing reward-rehoming tests are documented and carried to Phase 332 per the plan's "compile + parity, deep proofs at 332" scope.
