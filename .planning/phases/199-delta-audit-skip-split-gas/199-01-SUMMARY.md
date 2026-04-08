---
phase: 199-delta-audit-skip-split-gas
plan: 01
status: complete
subsystem: gas-derivation
tags: [gas, audit, skip-split, jackpot, advanceGame]
dependency_graph:
  requires: [196-01-GAS-DERIVATION.md, 198-01-SUMMARY.md]
  provides: [199-01-GAS-DERIVATION.md]
  affects: [DegenerusGameJackpotModule.sol, DegenerusGameAdvanceModule.sol]
tech_stack:
  added: []
  patterns: [theoretical-gas-derivation, per-opcode-cost-analysis]
key_files:
  created:
    - .planning/phases/199-delta-audit-skip-split-gas/199-01-GAS-DERIVATION.md
  modified: []
decisions:
  - "creditFlip external call costs ~32K gas per call (includes _addDailyFlip SSTOREs inside BurnieCoinflip), not the 10K assumed in 196 derivation"
  - "Early-burn path can have autorebuy enabled (gameOver=false), making its worst case 13.36M not 5.04M"
  - "Solo bucket worst case includes isFinalDay DGNRS transfer path at 125K gas"
metrics:
  duration: 16m
  completed: "2026-04-08T22:54:00Z"
  tasks: 2
  files: 1
commits:
  - hash: 1e55f5f0
    message: "feat(199-01): derive theoretical worst-case gas for all advanceGame jackpot stages"
  - hash: 40dcf88d
    message: "fix(199-01): cross-check gas derivation -- correct creditFlip and caller overhead estimates"
requirements: [GAS-01, GAS-02, GAS-03, GAS-04]
---

# Phase 199 Plan 01: Theoretical Worst-Case Gas Derivation Summary

Theoretical worst-case gas for all advanceGame jackpot stages derived from EIP-2929/3529 opcode costs applied to unified _processDailyEth code paths, proving all paths under 16M with 15.7% minimum margin.

## What Was Built

Complete gas derivation document (`199-01-GAS-DERIVATION.md`) covering 6 worst-case paths:

| Path | Worst-Case Gas | Margin |
|------|---------------|--------|
| Daily call 1 -- SPLIT_CALL1 (160, autorebuy+dust) | 13,487,000 | 15.7% |
| Daily call 1 -- SPLIT_NONE (160, autorebuy+dust) | 13,474,000 | 15.8% |
| Daily call 2 -- SPLIT_CALL2 (145, autorebuy+dust) | 12,108,000 | 24.3% |
| Coin+Tickets (50 coin + 200 ticket) | 12,591,800 | 21.3% |
| Early-burn -- SPLIT_NONE (160, autorebuy+dust) | 13,361,000 | 16.5% |
| Terminal -- SPLIT_NONE (305, no autorebuy) | 9,514,000 | 40.5% |

## Key Findings

1. **SPLIT_NONE skip-split is 13K cheaper than SPLIT_CALL1** -- no resumeEthPool SSTORE (22,100) and no call1Bucket mask build (300), partially offset by processing 4 buckets instead of 2.

2. **creditFlip external call costs ~32K per call**, not the 10K estimated in 196 derivation. The _addDailyFlip function in BurnieCoinflip performs cold SLOAD + 0->nonzero SSTORE for coinflipBalance plus _updateTopDayBettor overhead.

3. **Early-burn CAN have autorebuy** (gameOver=false during purchase phase), making its worst case 13.36M gas, not the 5.04M assumed without autorebuy. Still under 16M.

4. **Solo bucket isFinalDay path** adds ~14K gas for dgnrs.poolBalance() + dgnrs.transferFromPool() external calls, bringing solo worst case to 125K.

5. **Skip-split threshold of 160 is correct** (GAS-04): at 160 winners with autorebuy+dust, gas is 13.47M (15.8% margin). At 305 winners with autorebuy+dust, gas would be 25.3M -- confirming splitting is necessary above 160.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Corrected creditFlip gas estimate**
- **Found during:** Task 2 (cross-check)
- **Issue:** Per-call estimate of 10,000 gas missed internal SSTOREs in BurnieCoinflip._addDailyFlip (coinflipBalance 0->nonzero = 22,100 + _updateTopDayBettor)
- **Fix:** Updated to 32,000 per call; recalculated all dependent totals
- **Files modified:** 199-01-GAS-DERIVATION.md
- **Commit:** 40dcf88d

**2. [Rule 1 - Bug] Corrected early-burn bucket count display**
- **Found during:** Task 2 (cross-check)
- **Issue:** Table showed [100, 59, 0, 1] = 160 for early-burn max scaled counts; actual 4x scale produces [100, 60, 32, 1] = 193 which capBucketCounts reduces to 160
- **Fix:** Updated table to show uncapped scale result with cap notation
- **Files modified:** 199-01-GAS-DERIVATION.md
- **Commit:** 40dcf88d

**3. [Rule 1 - Bug] Added missing AdvanceModule post-call overhead to section 5a**
- **Found during:** Task 2 (cross-check)
- **Issue:** Caller overhead for STAGE_JACKPOT_DAILY_STARTED omitted emit Advance (750) and coinflip.creditFlip (32,000) that run after payDailyJackpot returns
- **Fix:** Added to section 5a; recalculated 6a and 6b totals
- **Files modified:** 199-01-GAS-DERIVATION.md
- **Commit:** 40dcf88d

## Requirements Satisfied

- **GAS-01:** STAGE_JACKPOT_DAILY_STARTED worst case: 13,487,000 (SPLIT_CALL1) / 13,474,000 (SPLIT_NONE) < 16M
- **GAS-02:** STAGE_JACKPOT_ETH_RESUME worst case: 12,108,000 < 16M
- **GAS-03:** Skip-split path (SPLIT_NONE, 160 winners): 13,474,000 < 16M
- **GAS-04:** Threshold 160 verified correct -- single-call autorebuy+dust at 160 winners = 13.47M (safe); at 305 winners = 25.3M (exceeds 16M, confirming split is necessary)
