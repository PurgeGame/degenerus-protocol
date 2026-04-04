# Phase 185: Adversarial Line-by-Line Audit of Phase 183 JFIX Fix

## Audit Scope

All lines changed by the Phase 183 fix to DegenerusGameJackpotModule.sol and JackpotBucketLib.sol.
Five change groups audited against six adversarial checks each.

Reference: `.planning/phases/183-jackpot-eth-fix/183-JFIX02-verification.md`

---

## Change Group 1: Formatting-Only (_setCurrentPrizePool Line Wrap)

**Location:** DegenerusGameJackpotModule.sol line 371

**Diff:**
```diff
-                    _setCurrentPrizePool(_getCurrentPrizePool() - dailyLootboxBudget);
+                    _setCurrentPrizePool(
+                        _getCurrentPrizePool() - dailyLootboxBudget
+                    );
```

### Adversarial Checks

| # | Check | Result | Detail |
|---|-------|--------|--------|
| 1 | Reentrancy | N/A | No change to call structure. Same function call, same arguments, same order. |
| 2 | Overflow/Underflow | N/A | No arithmetic change. Expression `_getCurrentPrizePool() - dailyLootboxBudget` is identical. |
| 3 | State corruption | N/A | Same SSTORE target, same value. Whitespace is compile-time only. |
| 4 | Accounting regression | N/A | Identical bytecode after compilation. |
| 5 | Variable shadowing/scoping | N/A | No variable introduced or renamed. |
| 6 | Comment accuracy | N/A | No comment changed. |

**VERDICT: SAFE (cosmetic)**

The line wrap changes whitespace only. The function call, its argument expression, and surrounding control flow are byte-for-byte identical at the AST level.

---

## Change Group 2: Variable Rename futurePool -> futurePoolBal (Carryover Path)

**Location:** DegenerusGameJackpotModule.sol lines 396-398

**Diff:**
```diff
-                    uint256 futurePool = _getFuturePrizePool();
-                    reserveSlice = futurePool / 200;
-                    _setFuturePrizePool(futurePool - reserveSlice);
+                    uint256 futurePoolBal = _getFuturePrizePool();
+                    reserveSlice = futurePoolBal / 200;
+                    _setFuturePrizePool(futurePoolBal - reserveSlice);
```

### Adversarial Checks

| # | Check | Result | Detail |
|---|-------|--------|--------|
| 1 | Reentrancy | N/A | No change to call structure. SLOAD -> compute -> SSTORE pattern is identical. |
| 2 | Overflow/Underflow | N/A | `futurePoolBal / 200` and `futurePoolBal - reserveSlice` are the same expressions as before. `reserveSlice = futurePoolBal / 200 <= futurePoolBal`, so no underflow. |
| 3 | State corruption | N/A | Same SLOAD source, same computation, same SSTORE target. |
| 4 | Accounting regression | N/A | 1:1 variable substitution. `reserveSlice` and `_setFuturePrizePool` argument are identical. |
| 5 | Variable shadowing/scoping | PASS | `futurePoolBal` is declared at line 396 inside the `if (!isEarlyBirdDay)` block (lines 381-404). The old name `futurePool` appeared in two other scopes: the isEthDay block (now renamed to `futurePoolLocal`) and `_runEarlyBirdLootboxJackpot` (also renamed to `futurePoolLocal`). No other reference to `futurePool` exists in this function. The rename disambiguates the carryover-path variable from the ethDay-path variable. No shadowing risk. |
| 6 | Comment accuracy | N/A | No comment changed. The existing comment "0.5% of futurePrizePool reserved for carryover tickets" at line 395 remains accurate. |

**VERDICT: SAFE (rename-only)**

Pure 1:1 variable substitution. All three occurrences of the old name `futurePool` in this block are replaced with `futurePoolBal`. No behavioral change.

---

## Change Group 3: Core Fix -- Deferred SSTORE + paidEth Capture (Early-Burn Path)

**Location:** DegenerusGameJackpotModule.sol lines 478-509

**Diff:**
```diff
         uint256 ethDaySlice;
+        uint256 futurePoolLocal;
         if (isEthDay) {
             uint256 poolBps = 100; // 1% daily drip from futurePool
-            uint256 futurePool = _getFuturePrizePool();
-            ethDaySlice = (futurePool * poolBps) / 10_000;
-
-            // Deduct immediately (upfront model)
-            _setFuturePrizePool(futurePool - ethDaySlice);
+            futurePoolLocal = _getFuturePrizePool();
+            ethDaySlice = (futurePoolLocal * poolBps) / 10_000;
         }
         ...
-        _executeJackpot(
+        uint256 paidEth = _executeJackpot(
             JackpotParams({ ... })
         );

-        // Pools already deducted upfront; no additional deduction needed
+        // Deferred deduction: deduct only what was actually consumed
+        if (ethDaySlice != 0) {
+            _setFuturePrizePool(futurePoolLocal - lootboxBudget - paidEth);
+        }
```

### 3a. Variable Hoisting Safety

`futurePoolLocal` is declared at line 479 (outside the `isEthDay` block), assigned inside `if (isEthDay)` at line 482. When `isEthDay` is false:
- `futurePoolLocal` remains 0 (Solidity uint256 default)
- `ethDaySlice` remains 0 (declared at line 478, only assigned inside `if (isEthDay)`)
- The guard `if (ethDaySlice != 0)` at line 507 prevents the deferred SSTORE

**Is there any path where `ethDaySlice != 0` but `futurePoolLocal == 0`?**

No. `ethDaySlice` is only assigned at line 483: `ethDaySlice = (futurePoolLocal * poolBps) / 10_000`. If `futurePoolLocal == 0`, then `ethDaySlice == 0`. The only way `ethDaySlice != 0` is if `futurePoolLocal != 0`, which requires entering the `if (isEthDay)` block where `futurePoolLocal` is assigned from `_getFuturePrizePool()`.

**Result: SAFE** -- no uninitialized-read risk.

### 3b. Deferred SSTORE Window Analysis

Between the SLOAD at line 482 and the deferred SSTORE at line 508, the following code executes:

1. **Lines 488-494:** `_validateTicketBudget` -- declared `private view` (line 912). Cannot write state. Does not read futurePool. **SAFE.**

2. **Lines 496-504:** `_executeJackpot` -- this is the critical window. The call tree is:

```
_executeJackpot (line 1174)
  -> _runJackpotEthFlow (line 1191)
    -> _distributeJackpotEth (line 1329)
      -> _processOneBucket (line 1365) [x4 buckets]
        -> _resolveTraitWinners (line 1416)
          -> _processSoloBucketWinner (line 1572) [when winnerCount==1]
            -> _setFuturePrizePool(_getFuturePrizePool() + whalePassCost)  *** LINE 1598 ***
          -> _creditJackpot (line 1551)
            -> _addClaimableEth (line 816)
              -> _processAutoRebuy (line 847) [when autoRebuyEnabled]
                -> _setFuturePrizePool(_getFuturePrizePool() + calc.ethSpent)  *** LINE 870 ***
```

**FINDING: The `_executeJackpot` call tree DOES read and write futurePool in two locations:**

**(i) `_processSoloBucketWinner` line 1598:** When a solo-bucket winner receives a whale pass, `whalePassCost` is added to futurePool via `_setFuturePrizePool(_getFuturePrizePool() + whalePassCost)`. This intermediate SSTORE is overwritten by the deferred SSTORE at line 508.

**(ii) `_processAutoRebuy` line 870:** When auto-rebuy is enabled and the target is a future-level ticket (`calc.toFuture` is true), `calc.ethSpent` is added to futurePool via `_setFuturePrizePool(_getFuturePrizePool() + calc.ethSpent)`. This intermediate SSTORE is also overwritten by the deferred SSTORE at line 508.

### 3c. Underflow Safety

The deferred SSTORE computes `futurePoolLocal - lootboxBudget - paidEth`.

Setting aside the overwrite issue above, the algebraic proof holds:
- `lootboxBudget` is carved from `ethDaySlice` (via `PURCHASE_REWARD_JACKPOT_LOOTBOX_BPS`)
- `ethPool = ethDaySlice - lootboxBudget`
- `paidEth <= ethPool + whalePassCost` (from `_processOneBucket`: `totalPaidEth += ethDelta + ticketSpent`)
- Actually `paidEth` may include auto-rebuy amounts that go to futurePool, so `paidEth` value is bounded by `ethPool` (all shares allocated from ethPool, so `sum(shares) <= ethPool`)
- `lootboxBudget + paidEth <= lootboxBudget + ethPool = ethDaySlice <= futurePoolLocal`
- No underflow via Solidity 0.8 auto-check

**Result: SAFE** -- underflow cannot occur.

### 3d. Normal Path Equivalence (No Empty Buckets, No Whale Pass, No Auto-Rebuy)

When all buckets are populated, no solo-bucket whale pass trigger, and no auto-rebuy:
- `paidEth == ethPool` (all shares sum to ethPool, all ETH paid to claimable)
- Deferred SSTORE: `futurePoolLocal - lootboxBudget - ethPool = futurePoolLocal - ethDaySlice`
- Pre-fix SSTORE: `futurePoolLocal - ethDaySlice`
- **Identical.** No regression on the normal path.

### 3e. No External Calls (Reentrancy)

Between SLOAD (line 482) and SSTORE (line 508):
- `_validateTicketBudget` is `view` -- no external calls
- `_executeJackpot` and its entire call tree are `private` functions
- `_addClaimableEth` writes to `claimableWinnings` mapping (storage) or processes auto-rebuy (storage writes)
- `_creditJackpot` calls `coinflip.creditFlip()` only for COIN payments (`payInCoin == true`), and in the early-burn ETH path `payInCoin` is always `false` in `_resolveTraitWinners` line 1482 (`return (entropyState, 0, 0, 0)` for coin path; the ETH path at line 1515 calls `_addClaimableEth`)
- No `.call`, `.transfer`, `.send`, or `delegatecall` in the ETH distribution path

**Result: SAFE** -- no reentrancy vector. However, the intermediate SSTORE writes in `_processSoloBucketWinner` and `_processAutoRebuy` are still problematic (they are internal state writes, not external calls).

### 3f. Guard Correctness

`if (ethDaySlice != 0)` at line 507:
- `ethDaySlice` is only assigned inside `if (isEthDay)` at line 483
- When `isEthDay == false`, `ethDaySlice` remains 0 (default), guard prevents SSTORE
- When `isEthDay == true` but `futurePoolLocal == 0`, `ethDaySlice = 0 * 100 / 10_000 = 0`, guard prevents SSTORE
- The guard correctly prevents writing uninitialized `futurePoolLocal` to storage

**Result: SAFE** -- guard is correct.

### Adversarial Checks Summary

| # | Check | Result | Detail |
|---|-------|--------|--------|
| 1 | Reentrancy | PASS | No external calls between SLOAD and deferred SSTORE. |
| 2 | Overflow/Underflow | PASS | `futurePoolLocal - lootboxBudget - paidEth >= 0` proven algebraically. Solidity 0.8 auto-reverts as defense in depth. |
| 3 | State corruption | **FINDING** | Deferred SSTORE at line 508 overwrites intermediate futurePool writes from `_processSoloBucketWinner` (line 1598) and `_processAutoRebuy` (line 870). See Finding F-185-01 below. |
| 4 | Accounting regression | **FINDING** | Normal path (no whale pass, no auto-rebuy) is equivalent. Whale-pass path and auto-rebuy-to-future path lose ETH from futurePool. See Finding F-185-01. |
| 5 | Variable shadowing/scoping | PASS | `futurePoolLocal` hoisted to outer scope safely; guard prevents uninitialized write. Old `futurePool` name eliminated from this scope. |
| 6 | Comment accuracy | PASS | "Deferred deduction: deduct only what was actually consumed" is accurate for the non-whale-pass, non-auto-rebuy case. However, the comment does not acknowledge that intermediate futurePool writes are overwritten. |

### Finding F-185-01: Deferred SSTORE Overwrites Intermediate futurePool Mutations

**Severity: HIGH**

**Description:**

The deferred SSTORE at line 508 (`_setFuturePrizePool(futurePoolLocal - lootboxBudget - paidEth)`) uses `futurePoolLocal` which was captured at line 482 BEFORE `_executeJackpot` runs. During `_executeJackpot` execution, two code paths write to futurePool:

1. **`_processSoloBucketWinner` (line 1598):** When a solo-bucket winner qualifies for whale passes, the whale pass cost is added to futurePool: `_setFuturePrizePool(_getFuturePrizePool() + whalePassCost)`. The `whalePassCost` is also included in `paidEth` via `ticketSpent` (line 1390: `ctx.totalPaidEth += ethDelta + ticketSpent`).

2. **`_processAutoRebuy` (line 870):** When auto-rebuy is enabled and the ticket target is a future level (`calc.toFuture == true`), `calc.ethSpent` is added to futurePool: `_setFuturePrizePool(_getFuturePrizePool() + calc.ethSpent)`. The `ethSpent` is NOT included in `paidEth` because `_addClaimableEth` returns `calc.reserved` (line 886), not `calc.ethSpent`.

The deferred SSTORE at line 508 writes `futurePoolLocal - lootboxBudget - paidEth`, which:
- Overwrites the whale pass addition at line 1598
- Overwrites the auto-rebuy-to-future addition at line 870

**Impact -- Whale Pass Path:**

- Pre-fix: `futurePool = original - ethDaySlice + whalePassCost` (whale pass ETH retained in pool)
- Post-fix: `futurePool = original - lootboxBudget - paidEth` where `paidEth` includes `whalePassCost` as `ticketSpent`
- Post-fix simplifies to: `original - lootboxBudget - ethPaid - whalePassCost`
- Pre-fix simplifies to: `original - lootboxBudget - ethPool + whalePassCost` = `original - lootboxBudget - (ethPaid + whalePassCost) + whalePassCost` = `original - lootboxBudget - ethPaid`
- **Difference: Post-fix is lower by `whalePassCost`.** The whale pass ETH that should be recycled into futurePool is lost.

**Impact -- Auto-Rebuy-to-Future Path:**

- Pre-fix: `futurePool = original - ethDaySlice + autoRebuyEthToFuture` (auto-rebuy ETH retained in pool)
- Post-fix: `futurePool = original - lootboxBudget - paidEth`, where `paidEth` does NOT include `autoRebuyEthToFuture` (because `_addClaimableEth` returns `calc.reserved`, not the full amount)
- However, the intermediate SSTORE adding `autoRebuyEthToFuture` is overwritten
- **Difference: Post-fix is lower by `autoRebuyEthToFuture`.** The auto-rebuy ETH that should be recycled into futurePool is lost.

**Reproduction:**

1. Set up an early-burn ETH day with futurePool = 10 ETH
2. Ensure one trait bucket has exactly 1 holder (triggers solo-bucket whale pass logic)
3. Ensure `perWinner / 4 >= HALF_WHALE_PASS_PRICE` (triggers whale pass conversion)
4. After `_executeJackpot` returns, the intermediate futurePool write from `_processSoloBucketWinner` is overwritten by the deferred SSTORE
5. futurePool ends up lower by `whalePassCost` compared to the pre-fix behavior

**Root Cause:**

The deferred SSTORE pattern assumes `_executeJackpot` does not read or write futurePool. This assumption is violated by two internal code paths:
- `_processSoloBucketWinner` (whale pass conversion)
- `_processAutoRebuy` (auto-rebuy with future-level ticket targeting)

**VERDICT: FINDING -- HIGH severity. The deferred SSTORE overwrites intermediate futurePool mutations from whale pass conversion and auto-rebuy.**

---

## Change Group 4: Variable Rename futurePool -> futurePoolLocal (_runEarlyBirdLootboxJackpot)

**Location:** DegenerusGameJackpotModule.sol lines 656-661

**Diff:**
```diff
-        uint256 futurePool = _getFuturePrizePool();
-        uint256 reserveContribution = (futurePool * 300) / 10_000; // 3%
+        uint256 futurePoolLocal = _getFuturePrizePool();
+        uint256 reserveContribution = (futurePoolLocal * 300) / 10_000; // 3%
         uint256 totalBudget = reserveContribution;
-        _setFuturePrizePool(futurePool - reserveContribution);
+        _setFuturePrizePool(futurePoolLocal - reserveContribution);
```

### Adversarial Checks

| # | Check | Result | Detail |
|---|-------|--------|--------|
| 1 | Reentrancy | N/A | SLOAD -> compute -> SSTORE pattern is identical. No calls inserted. |
| 2 | Overflow/Underflow | N/A | `futurePoolLocal * 300 / 10_000` and `futurePoolLocal - reserveContribution` are same expressions. `reserveContribution = futurePoolLocal * 3% <= futurePoolLocal`. |
| 3 | State corruption | N/A | Same SLOAD source (`_getFuturePrizePool()`), same computation, same SSTORE target (`_setFuturePrizePool`). |
| 4 | Accounting regression | N/A | 1:1 substitution. The SLOAD-compute-SSTORE window is unchanged and the SSTORE is immediate (not deferred), so no intermediate write issue. |
| 5 | Variable shadowing/scoping | PASS | `futurePoolLocal` is the only local of that name in `_runEarlyBirdLootboxJackpot`. The function is a separate scope from `payDailyJackpot`. No shadowing. |
| 6 | Comment accuracy | N/A | No comment changed. Existing comments ("Take 3% from unified reserve", "Deduct from reserve") remain accurate. |

**VERDICT: SAFE (rename-only)**

Pure 1:1 variable substitution across all three occurrences. SLOAD-compute-SSTORE is immediate (not deferred), so the `_processSoloBucketWinner`/`_processAutoRebuy` overwrite issue from Change Group 3 does not apply here.

---

## Change Group 5: NatSpec Addition on bucketShares (Comment-Only)

**Location:** JackpotBucketLib.sol lines 211-213

**Diff:**
```diff
     /// @dev Computes ETH/COIN shares for each bucket.
     ///      Round non-solo buckets to unit * winnerCount; remainder goes to the override bucket.
+    ///      Empty non-remainder buckets (count==0) contribute their computed share to
+    ///      `distributed` without receiving ETH, reducing the remainder bucket allocation.
+    ///      The caller is responsible for refunding ethPool - paidEth to the source pool.
```

### Adversarial Checks

| # | Check | Result | Detail |
|---|-------|--------|--------|
| 1 | Reentrancy | N/A | Comment-only change. No code modified. |
| 2 | Overflow/Underflow | N/A | Comment-only change. |
| 3 | State corruption | N/A | Comment-only change. |
| 4 | Accounting regression | N/A | Comment-only change. Zero bytecode impact. |
| 5 | Variable shadowing/scoping | N/A | Comment-only change. |
| 6 | Comment accuracy | See below | |

**Comment accuracy analysis:**

1. **"Empty non-remainder buckets (count==0) contribute their computed share to `distributed` without receiving ETH"** -- Verified against lines 222-233 of `bucketShares()`:
   - Line 225: `uint256 share = (pool * shareBps[i]) / 10_000;` -- computed for all non-remainder buckets regardless of count
   - Lines 226-231: `shares[i] = share` only assigned inside `if (count != 0)` guard
   - Line 233: `distributed += share` -- accumulated ALWAYS, outside the count guard
   - When `count == 0`: share is computed, `shares[i]` stays 0, `distributed` includes the share
   - **ACCURATE.**

2. **"reducing the remainder bucket allocation"** -- Verified against line 239:
   - `shares[remainderIdx] = pool - distributed`
   - Higher `distributed` (from phantom shares) means lower remainder allocation
   - **ACCURATE.**

3. **"The caller is responsible for refunding ethPool - paidEth to the source pool"** -- This describes the intended behavior of the deferred SSTORE fix in Change Group 3. The caller (`payDailyJackpot`) should refund the difference between what was allocated and what was actually paid. **ACCURATE in intent**, though per Finding F-185-01, the current implementation of the deferred SSTORE does not correctly handle intermediate futurePool writes.

**VERDICT: SAFE (comment-only, accurate)**

All three NatSpec lines accurately describe `bucketShares` behavior and the caller's responsibility.

---

## Gas Analysis (DELTA-02)

### SLOAD/SSTORE Comparison: Early-Burn Path

| Operation | Pre-Fix | Post-Fix | Delta |
|-----------|---------|----------|-------|
| `_getFuturePrizePool()` SLOAD | 1 (line 479) | 1 (line 482) | 0 |
| `_setFuturePrizePool()` SSTORE | 1 (line 483, upfront) | 1 (line 508, deferred) | 0 |
| `paidEth` return value capture | 0 (discarded) | 1 (stack assignment) | +1 stack op (~3 gas) |
| `ethDaySlice != 0` guard | 0 | 1 (conditional check) | +1 comparison (~3 gas) |
| `futurePoolLocal - lootboxBudget - paidEth` | 0 | 1 (two subtractions) | +2 SUB ops (~6 gas) |

**Total SLOAD count: identical (1)**
**Total SSTORE count: identical (1)**

Note: The SSTORE writes a different value on the empty-bucket path (larger, because unspent ETH remains in futurePool). SSTORE gas cost is value-independent for warm slots (same storage key already accessed). No gas difference from the value change.

### Normal Path (No Empty Buckets)

When all buckets are populated: `paidEth == ethPool = ethDaySlice - lootboxBudget`.
- Deferred SSTORE writes: `futurePoolLocal - lootboxBudget - (ethDaySlice - lootboxBudget) = futurePoolLocal - ethDaySlice`
- Pre-fix SSTORE wrote: `futurePoolLocal - ethDaySlice`
- **Identical computation, identical SSTORE value, identical gas.**

**Normal path overhead: ZERO.**

### Empty-Bucket Path (Phantom Shares)

When one or more non-remainder buckets are empty: `paidEth < ethPool`.
- One extra local variable read (`paidEth`) and two extra `SUB` operations vs the old code
- All are stack/memory operations: ~3 gas each
- **Empty-bucket path overhead: ~12 gas (negligible)**
- No additional SLOADs. The `_getFuturePrizePool()` call count is 1 in both pre-fix and post-fix

### Rename and Formatting Changes

- Change Groups 1, 2, 4: Zero gas impact. Local variable names and whitespace are compile-time only; identical bytecode produced.

### `_getFuturePrizePool` Call Count Verification

Searched all changed code in the early-burn path for `_getFuturePrizePool` calls:
- Line 482: `futurePoolLocal = _getFuturePrizePool()` -- the sole SLOAD in the early-burn path (same as pre-fix)
- No additional calls introduced by the fix

**Note on intermediate writes:** Inside the deferred SSTORE window, `_processSoloBucketWinner` (line 1598) and `_processAutoRebuy` (line 870) each call `_getFuturePrizePool()` and `_setFuturePrizePool()`. These are pre-existing calls that existed in the pre-fix code as well. The deferred SSTORE pattern does not add new SLOADs or SSTOREs -- it merely changes WHEN the caller's SSTORE executes relative to these intermediate writes. The gas impact of these intermediate operations is unchanged.

---

## Overall Verdicts

### DELTA-01: Adversarial Line-by-Line Audit

| Change Group | Verdict | Notes |
|-------------|---------|-------|
| 1. Formatting (_setCurrentPrizePool wrap) | SAFE | Cosmetic only |
| 2. Rename futurePool -> futurePoolBal | SAFE | 1:1 substitution |
| 3. Core fix (deferred SSTORE + paidEth) | **FINDING** | F-185-01: Deferred SSTORE overwrites intermediate futurePool writes |
| 4. Rename futurePool -> futurePoolLocal | SAFE | 1:1 substitution |
| 5. NatSpec addition (bucketShares) | SAFE | Comment-only, accurate |

**DELTA-01: FINDING -- Change Group 3 introduces a state corruption regression when solo-bucket whale pass conversion or auto-rebuy-to-future paths are active.**

The deferred SSTORE pattern at line 508 assumes `_executeJackpot` does not modify futurePool. This assumption is violated by:

1. `_processSoloBucketWinner` (line 1598): writes `futurePool += whalePassCost`
2. `_processAutoRebuy` (line 870): writes `futurePool += calc.ethSpent` (when `calc.toFuture`)

Both intermediate writes are overwritten by the deferred SSTORE. The result is ETH that should be recycled into futurePool (whale pass conversions, auto-rebuy ticket purchases) is lost from the pool accounting.

Change Groups 1, 2, 4, and 5 are verified SAFE with no findings.

### DELTA-02: Gas Impact Analysis

**DELTA-02: VERIFIED -- normal path has zero gas overhead; empty-bucket path has ~12 gas additional stack operations (negligible); no new SLOADs or SSTOREs.**

| Path | SLOAD Count | SSTORE Count | Additional Gas |
|------|-------------|--------------|----------------|
| Normal (all buckets populated) | 1 (same) | 1 (same) | 0 |
| Empty-bucket (phantom shares) | 1 (same) | 1 (same) | ~12 gas (stack ops) |
| Renames (Groups 2, 4) | 0 change | 0 change | 0 |
| Formatting (Group 1) | 0 change | 0 change | 0 |

---

## Threat Model Verification

| Threat ID | Status | Notes |
|-----------|--------|-------|
| T-185-01 (futurePool stale read during deferred window) | **VIOLATED** | `_executeJackpot` call tree DOES read futurePool via `_processSoloBucketWinner` and `_processAutoRebuy`. The plan's premise that "no callee reads futurePool" is incorrect. |
| T-185-02 (paidEth undercount leading to futurePool inflation) | MITIGATED | `paidEth` includes `ticketSpent` (whale pass amounts), so undercount is not the issue. The issue is overcount: `paidEth` includes amounts that were supposed to be added back to futurePool. |
| T-185-03 (futurePoolLocal underflow in deferred SSTORE) | MITIGATED | Algebraic proof holds: `lootboxBudget + paidEth <= ethDaySlice <= futurePoolLocal`. |
| T-185-04 (uninitialized futurePoolLocal written to storage) | MITIGATED | Guard `if (ethDaySlice != 0)` correctly prevents SSTORE when isEthDay=false. |
