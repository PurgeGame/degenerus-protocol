---
plan: 101-01
phase: 101-bug-fix
status: complete
started: 2026-03-25
completed: 2026-03-25
duration: 5min
one_liner: "Delta reconciliation fix for runRewardJackpots cache-overwrite bug — 3 lines added, no signature changes"
requirements_completed: BAF-01,BAF-02,SCAN-03
tasks_completed: 3
files_modified: 1
key-files:
  created: []
  modified:
    - contracts/modules/DegenerusGameEndgameModule.sol
---

# Plan 101-01: BAF Cache-Overwrite Bug Fix

## What Was Done

Applied a 3-line delta reconciliation fix to `runRewardJackpots` in `DegenerusGameEndgameModule.sol` (lines 239-240). The fix reads `futurePrizePool` from storage immediately before the final write-back, computes `rebuyDelta = _getFuturePrizePool() - baseFuturePool`, and writes `futurePoolLocal + rebuyDelta` instead of the stale `futurePoolLocal`.

## Fix Details

**Before:**
```solidity
if (futurePoolLocal != baseFuturePool) {
    _setFuturePrizePool(futurePoolLocal);
}
```

**After:**
```solidity
if (futurePoolLocal != baseFuturePool) {
    uint256 rebuyDelta = _getFuturePrizePool() - baseFuturePool;
    _setFuturePrizePool(futurePoolLocal + rebuyDelta);
}
```

## Arithmetic Proof (BAF-02)

Let F0 = `baseFuturePool` (storage at entry), R = total auto-rebuy contributions, totalJackpotSpend = net BAF + Decimator spend.

| Path | R | rebuyDelta | Write-back | Correct? |
|------|---|------------|------------|----------|
| Zero-rebuy | 0 | 0 | F0 - totalJackpotSpend | Yes (identical to pre-fix) |
| Single auto-rebuy (r1) | r1 | r1 | F0 - totalJackpotSpend + r1 | Yes (r1 preserved) |
| Multiple auto-rebuy | r1+...+rN | R | F0 - totalJackpotSpend + R | Yes (all preserved) |

**Underflow safety:** `_getFuturePrizePool() >= baseFuturePool` invariant holds because auto-rebuy only adds to `futurePrizePool`. Solidity 0.8+ checked arithmetic provides safety net.

## SCAN-03 Compliance

Phase 100 protocol-wide pattern scan found exactly 1 VULNERABLE instance across all 29 protocol contracts (12 candidates examined, 11 SAFE, 1 VULNERABLE). This fix addresses the sole VULNERABLE instance (`runRewardJackpots` in EndgameModule). No additional instances to fix or defer.

## Requirements

| Requirement | Status | Evidence |
|-------------|--------|----------|
| BAF-01 | COMPLETE | Delta reconciliation applied at EndgameModule line 239-240 |
| BAF-02 | COMPLETE | 4-path arithmetic proof above; underflow safety argument |
| SCAN-03 | COMPLETE | Phase 100 found 1 VULNERABLE instance; this fix addresses it; 0 deferrals |

## Notes

- No function signatures changed
- No external interfaces changed
- Contract left unstaged for user diff review before committing
- forge build passes clean (lint warnings only, no errors)
