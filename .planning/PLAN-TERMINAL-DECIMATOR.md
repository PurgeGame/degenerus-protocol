# Plan: Terminal Decimator — Always-Open Death Bet

**Status:** Draft

## Concept

A separate decimator that is always open. Players burn BURNIE betting the protocol will die (GAMEOVER). If GAMEOVER fires, they split 10% of all remaining money. If the level completes normally, total loss.

Early conviction rewarded via time multiplier based on days remaining on death clock. 200k BURNIE cap equalizes bankroll — timing is the only differentiator.

---

## Storage — DegenerusGameStorage.sol

Append at tail of storage (safe for delegatecall layout):

```solidity
// Per-player terminal decimator entry (232 bits — single slot)
struct TerminalDecEntry {
    uint80  totalBurn;     // cumulative pre-time-mult burn, capped at 200k (max 2e23, uint80 max 1.2e24)
    uint88  weightedBurn;  // cumulative post-time-mult burn, for claim share (max 6e24, uint88 max 3e26)
    uint8   bucket;        // chosen bucket denominator (2-12)
    uint8   subBucket;     // deterministic from keccak256(player, level, bucket)
    uint48  burnLevel;     // which level this entry belongs to (stale detection)
}
mapping(address => TerminalDecEntry) internal terminalDecEntries;

// Per-bucket aggregates: keccak256(level, denom, subBucket) -> total weighted burn
mapping(bytes32 => uint256) internal terminalDecBucketBurnTotal;

// Global terminal decimator state
uint256 internal terminalDecTotalBurn;   // total weighted burns across all buckets
uint24  internal terminalDecLevel;       // level being tracked (lazy reset detection)

// Resolution snapshot (set at GAMEOVER)
struct TerminalDecClaimRound {
    uint24  lvl;
    uint256 poolWei;
    uint256 totalBurn;
    uint256 rngWord;
}
TerminalDecClaimRound internal lastTerminalDecClaimRound;
```

### Packing rationale

`TerminalDecEntry` fits in one slot (232/256 bits, 24 spare):
- `totalBurn` uint80: max 1.2e24, need 200k * 1e18 = 2e23 → 6x headroom
- `weightedBurn` uint88: max 3e26, need 200k * 30x * 1e18 = 6e24 → 51x headroom
- `bucket` uint8: values 2-12
- `subBucket` uint8: values 0-255
- `burnLevel` uint48: level number (matches existing `uint24 level` with massive headroom)

`totalBurn` enforces the 200k cap (pre-time-multiplier). `weightedBurn` accumulates the time-weighted score used for claim payout calculation. Both needed because you can't reconstruct the weighted total from the capped total (player may burn at different times with different multipliers).

---

## Time Multiplier

```solidity
function _terminalDecMultiplierBps(uint256 daysRemaining) private pure returns (uint256) {
    if (daysRemaining > 10) {
        return daysRemaining * 2500;  // daysRemaining / 4 in BPS
    }
    // Linear: 2x at day 10, 1x at day 1
    return 10000 + ((daysRemaining - 1) * 10000) / 9;
}
```

| Days remaining | Multiplier | BPS |
|---------------|------------|-----|
| 120 (full clock) | 30x | 300,000 |
| 40 | 10x | 100,000 |
| 20 | 5x | 50,000 |
| 11 | 2.75x | 27,500 |
| 10 | 2x | 20,000 |
| 5 | ~1.44x | 14,444 |
| 1 (last day) | 1x | 10,000 |

Intentional discontinuity at day 10 (2.75x → 2x) as regime-change signal.

### Days remaining calculation

```solidity
uint256 timeout = level == 0
    ? uint256(DEPLOY_IDLE_TIMEOUT_DAYS) * 1 days
    : 120 days;
uint256 deadline = uint256(levelStartTime) + timeout;
uint256 remaining = deadline > block.timestamp ? deadline - block.timestamp : 0;
uint256 daysRemaining = remaining / 1 days;
if (daysRemaining == 0) daysRemaining = 1;  // minimum 1x on last day
```

---

## Burn Flow — DecimatorModule

### `recordTerminalDecBurn(address player, uint24 lvl, uint256 baseAmount, uint256 activityMultBps)`

Bucket is computed inside from activity score using lvl 100 rules (`minBucket = 2`, same as `_adjustDecimatorBucket(bonusBps, 2)`). Player does not choose.

```
1. Lazy reset: if entry.burnLevel != lvl → zero out entry, reset aggregates
2. Compute bucket: _adjustDecimatorBucket(bonusBps, DECIMATOR_MIN_BUCKET_100)
3. Apply activity multiplier:  effectiveAmount = baseAmount * activityMultBps / BPS
4. Cap check: if entry.totalBurn + effectiveAmount > CAP → effectiveAmount = CAP - entry.totalBurn
5. If effectiveAmount == 0 → revert (already capped)
6. entry.totalBurn += uint80(effectiveAmount)
7. Compute time multiplier: timeMultBps = _terminalDecMultiplierBps(daysRemaining)
8. weightedAmount = effectiveAmount * timeMultBps / BPS
9. entry.weightedBurn += uint88(weightedAmount)
10. Assign bucket + subbucket (if first burn): entry.bucket = bucket, entry.subBucket = uint8(keccak256(player, lvl, bucket))
11. Update bucket aggregate: terminalDecBucketBurnTotal[key] += weightedAmount
12. Update global: terminalDecTotalBurn += weightedAmount
```

---

## Entry Point — BurnieCoin.sol

### `terminalDecimatorBurn(address player, uint256 amount) external`

Same preamble as existing `decimatorBurn` (min amount, burn BURNIE, activity score lookup), but:
- No bucket parameter — bucket computed internally using lvl 100 rules (min bucket 2, activity score slides from base 12)
- Checks `terminalDecWindow()` instead of `decWindow()`
- Calls `game.recordTerminalDecBurn(caller, lvl, baseAmount, activityMultBps)`
- Time multiplier computed inside DecimatorModule (has access to `levelStartTime`)

---

## Window — DegenerusGame.sol

### `terminalDecWindow() external view returns (bool open, uint24 lvl)`

```solidity
lvl = level;
open = !gameOver && !(lastPurchaseDay && rngLockedFlag);
// Only blocked during RNG lock at level transition
```

Always open during normal gameplay. Separate from `decWindow()`.

---

## Resolution — GameOverModule

### GAMEOVER fires

In `handleGameOverDrain`, replace current decimator 10% allocation:

```
Old: Step 4 → normal decimator 10%
New: Step 4 → terminal decimator 10%
```

1. Allocate 10% of remaining funds to terminal decimator pool
2. VRF selects winning subbuckets per bucket denominator (2-12)
3. Store resolution snapshot in `lastTerminalDecClaimRound`
4. Normal decimator continues resolving at milestone level (no GAMEOVER allocation)

### Level completes normally

Terminal burns are a total loss. Lazy reset on next burn.

---

## Claims — DecimatorModule

### `claimTerminalDecimatorJackpot(uint24 lvl) external`

Same mechanics as normal decimator claims:
1. Verify player's subbucket matches VRF-selected winning subbucket for their bucket
2. Payout = `(entry.weightedBurn / bucketBurnTotal) * bucketPoolWei`
3. 50/50 ETH/lootbox split (or current decimator split)
4. Claim window: GAMEOVER → final sweep (30 days)

`weightedBurn` is the player's post-time-multiplier effective total. This is what differentiates early conviction from late burning.

---

## Files to Change

| File | What |
|------|------|
| `DegenerusGameStorage.sol` | New storage: `TerminalDecEntry`, mappings, claim round struct |
| `DegenerusGameDecimatorModule.sol` | `recordTerminalDecBurn`, time multiplier, terminal claim, terminal resolution |
| `BurnieCoin.sol` | New `terminalDecimatorBurn` entry point |
| `DegenerusGame.sol` | New `terminalDecWindow()` view, expose `recordTerminalDecBurn` |
| `DegenerusGameGameOverModule.sol` | Route 10% to terminal decimator in `handleGameOverDrain` |
| Interfaces | New function declarations |

---

## Execution Order

1. Add storage to DegenerusGameStorage.sol (struct + mappings)
2. Add `_terminalDecMultiplierBps` and `recordTerminalDecBurn` to DecimatorModule
3. Add `terminalDecimatorBurn` to BurnieCoin.sol
4. Add `terminalDecWindow()` to DegenerusGame.sol
5. Hook terminal resolution into `handleGameOverDrain` (replace 10% allocation)
6. Add `claimTerminalDecimatorJackpot` claim function
7. Add lazy reset logic (level change detection)
8. Update interfaces

---

## Open Questions

1. **Post-deadline burns:** Block entirely when death clock expires (remaining=0), or allow at 1x? Current spec allows at 1x.
2. **VRF word at GAMEOVER:** Liveness timeout fires because VRF is dead. What entropy resolves winning subbuckets? Last stale word, or does GAMEOVER resolution happen on a later `advanceGame` that does get a word?
3. **Normal decimator GAMEOVER change:** Confirm that normal decimator losing its 10% GAMEOVER allocation is the intended trade. Normal dec still resolves at milestones from gameplay pools.
