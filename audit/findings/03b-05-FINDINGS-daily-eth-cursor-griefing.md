# 03b-05 FINDINGS: Daily ETH Distribution Cursor Griefing Resistance

**Audit date:** 2026-03-01
**Auditor:** Claude Opus 4.6
**Scope:** Daily ETH distribution bucket cursor lifecycle in `DegenerusGameJackpotModule`
**Requirement:** DOS-02
**Verdict:** PASS

---

## 1. Cursor Variable Inventory and Access Control

### 1.1 Storage Declarations

| Variable | Type | Location | Purpose |
|----------|------|----------|---------|
| `dailyEthBucketCursor` | `uint8` | `DegenerusGameStorage:260` (Slot 1, bytes 11-12) | Bucket order index (0-3) for resume |
| `dailyEthPhase` | `uint8` | `DegenerusGameStorage:264` (Slot 1, bytes 12-13) | 0 = current level, 1 = carryover |
| `dailyEthPoolBudget` | `uint256` | `DegenerusGameStorage:319` (own slot) | ETH budget for current-level distribution |
| `dailyEthWinnerCursor` | `uint16` | `DegenerusGameStorage:438` (own slot region) | Winner index within current bucket |

### 1.2 Complete Reference Map

**File: `contracts/modules/DegenerusGameJackpotModule.sol`**

| Variable | Read Sites | Write Sites |
|----------|-----------|-------------|
| `dailyEthBucketCursor` | 289 (resume check), 1370 (load cursor) | 405 (init=0), 486 (phase transition=0), 476 (reset=0), 541 (reset=0), 1424 (save=j), 1461 (complete=0) |
| `dailyEthPhase` | 288 (resume check), 421 (phase 0 check), 492 (phase 1 check) | 404 (init=0), 475 (reset=0), 485 (transition=1), 540 (reset=0) |
| `dailyEthPoolBudget` | 287 (resume check), 422 (read budget) | 331 (init=budget), 478 (reset=0), 543 (reset=0) |
| `dailyEthWinnerCursor` | 290 (resume check), 1371 (load cursor) | 406 (init=0), 477 (reset=0), 487 (phase transition=0), 542 (reset=0), 1425 (save=i), 1462 (complete=0) |

**File: `contracts/modules/DegenerusGameAdvanceModule.sol`**

| Variable | Read Sites | Write Sites |
|----------|-----------|-------------|
| `dailyEthBucketCursor` | 172, 255 | None |
| `dailyEthPhase` | 171, 256 | None |
| `dailyEthPoolBudget` | 170, 257 | None |
| `dailyEthWinnerCursor` | 173, 258 | None |

**File: `contracts/storage/DegenerusGameStorage.sol`**

Declarations only (lines 260, 264, 319, 438). No read or write logic.

### 1.3 Access Control Verdict

All WRITE sites are exclusively within `DegenerusGameJackpotModule.sol`. The AdvanceModule only READS cursor variables for control flow decisions (determining whether to resume or start fresh). Since JackpotModule is invoked only via `delegatecall` from `DegenerusGame.advanceGame()` (through `AdvanceModule.payDailyJackpot()`), no external caller can directly modify cursor variables. The call chain is:

```
msg.sender -> DegenerusGame.advanceGame()
           -> delegatecall AdvanceModule.advanceGame()
           -> delegatecall JackpotModule.payDailyJackpot()  [internal wrapper]
           -> JackpotModule._processDailyEthChunk()         [cursor writes]
```

**No external function outside the delegatecall chain can write to cursor variables.** PASS.

---

## 2. Cursor Lifecycle Trace

### 2.1 Fresh Start Initialization

**Resume detection** (JackpotModule:287-290):
```solidity
bool isResuming = dailyEthPoolBudget != 0 ||
    dailyEthPhase != 0 ||
    dailyEthBucketCursor != 0 ||
    dailyEthWinnerCursor != 0;
```

Any single non-zero value triggers resume mode. This OR-based detection is defensive: even if one variable were left stale, the system would resume rather than re-initialize (preventing double distribution).

**When NOT resuming** (JackpotModule:296-407):
1. `winningTraitsPacked` computed via `_rollWinningTraits()` and stored via `_syncDailyWinningTraits()` (lines 298-304)
2. `dailyEthPoolBudget = budget` set from `(currentPrizePool * dailyBps) / 10_000` minus lootbox deduction (line 331)
3. `dailyCarryoverEthPool = futureEthPool` set from futurePrizePool 1% slice (line 402)
4. All four cursors explicitly initialized (lines 404-406):
   ```solidity
   dailyEthPhase = 0;
   dailyEthBucketCursor = 0;
   dailyEthWinnerCursor = 0;
   ```

**Atomicity:** All four writes occur within the same transaction. If the transaction reverts (e.g., out of gas), no partial state is written. Solidity's all-or-nothing transaction semantics guarantee this.

### 2.2 Cursor Save on Gas Exhaustion

**Trigger** (JackpotModule:1423):
```solidity
if (cost != 0 && unitsUsed + cost > unitsBudget) {
    dailyEthBucketCursor = j;
    dailyEthWinnerCursor = uint16(i);
    if (liabilityDelta != 0) {
        claimablePool += liabilityDelta;
    }
    return (paidEth, false);
}
```

**Saved state:**
- `dailyEthBucketCursor = j` -- the current bucket ORDER index (0-3), NOT the trait index
- `dailyEthWinnerCursor = uint16(i)` -- the winner index within the current bucket's winner array
- `claimablePool += liabilityDelta` -- accumulated liability from winners already paid in this chunk
- `paidEth` -- returned to caller, which deducts from `currentPrizePool` (line 455)
- `dailyEthPoolBudget` -- NOT modified (intentional: preserves deterministic bucket share computation)

**Critical correctness property:** The save occurs BEFORE processing winner `i`. Winner `i` has NOT been paid. On resume, processing starts at winner `i` (the same one that was skipped). This prevents both double-payment and skipping.

### 2.3 Cursor Resume

**Resume path in AdvanceModule** (AdvanceModule:254-262):
```solidity
if (dailyEthBucketCursor != 0 || dailyEthPhase != 0 ||
    dailyEthPoolBudget != 0 || dailyEthWinnerCursor != 0) {
    payDailyJackpot(true, lastDailyJackpotLevel, rngWord);
    stage = STAGE_JACKPOT_ETH_RESUME;
    break;
}
```

**Resume path in JackpotModule** (JackpotModule:292-295):
```solidity
if (isResuming) {
    winningTraitsPacked = lastDailyJackpotWinningTraits;
    lvl = lastDailyJackpotLevel;
}
```

On resume:
1. Winning traits are restored from storage (not re-rolled) -- ensures same buckets
2. Level is restored from storage -- ensures same trait ticket pool
3. The fresh-start block (lines 307-407) is skipped entirely
4. `dailyEthPoolBudget` is read from storage (line 422) with original budget value
5. Bucket counts, shares, and order are recomputed deterministically from `entropy` and `ethPool`
6. `_processDailyEthChunk` reads `startOrderIdx = dailyEthBucketCursor` and `startWinnerIdx = dailyEthWinnerCursor` (lines 1370-1371)
7. `_skipEntropyToBucket` advances entropy to match the state at `startOrderIdx`
8. Inner loop starts at `(j=startOrderIdx, i=startWinnerIdx)` -- exact resume

**Determinism guarantee:** The winner list for each bucket is computed by `_randTraitTicketWithIndices()`, which is a `view` function reading from `traitBurnTicket[lvl]`. During the jackpot phase, no minting occurs (purchases are disabled), so `traitBurnTicket[lvl]` is immutable. The same entropy + same ticket pool = same winner list across calls.

### 2.4 Complete Reset

**Phase 0 completion with no carryover** (JackpotModule:475-481):
```solidity
dailyEthPhase = 0;
dailyEthBucketCursor = 0;
dailyEthWinnerCursor = 0;
dailyEthPoolBudget = 0;
dailyCarryoverEthPool = 0;
dailyCarryoverWinnerCap = 0;
dailyJackpotCoinTicketsPending = true;
```

**Phase 1 completion** (JackpotModule:540-546):
```solidity
dailyEthPhase = 0;
dailyEthBucketCursor = 0;
dailyEthWinnerCursor = 0;
dailyEthPoolBudget = 0;
dailyCarryoverEthPool = 0;
dailyCarryoverWinnerCap = 0;
dailyJackpotCoinTicketsPending = true;
```

Both paths zero ALL six distribution-related state variables and set `dailyJackpotCoinTicketsPending = true` to trigger the next execution phase (coin+ticket distribution). The reset is complete: no stale state persists.

### 2.5 Phase Transitions

**Phase 0 -> Phase 1** (JackpotModule:485-488):
```solidity
dailyEthPhase = 1;
dailyEthBucketCursor = 0;
dailyEthWinnerCursor = 0;
return;
```

When Phase 0 completes and carryover pool is non-zero:
1. `dailyEthPhase` set to 1
2. Bucket and winner cursors reset to 0 (fresh start for Phase 1)
3. Function returns -- next `advanceGame` call resumes into Phase 1

**Phase 1 execution** (JackpotModule:492-548):
- Reads `carryPool = dailyCarryoverEthPool` and `carryCap = dailyCarryoverWinnerCap`
- Computes new bucket counts/shares for the carryover source level
- Calls `_processDailyEthChunk` with carryover parameters
- If incomplete, saves cursors and returns (same mechanism as Phase 0)
- On completion, fully resets all variables

**Phase skip when carryover is zero** (JackpotModule:472-483):
```solidity
if (dailyCarryoverEthPool == 0 || dailyCarryoverWinnerCap == 0) {
    // Full reset + finalize
    dailyEthPhase = 0;
    ...
    return;
}
```

If no carryover work is needed, Phase 1 is skipped gracefully with a full reset.

**Phase counter bounds:** `dailyEthPhase` can only be 0 or 1. Phase 0 either transitions to Phase 1 or resets. Phase 1 always resets. There is no Phase 2. The state machine is:
```
Phase 0 --[complete, has carryover]--> Phase 1 --[complete]--> Reset
Phase 0 --[complete, no carryover]--> Reset
Phase 0 --[incomplete]--> Phase 0 (resume)
Phase 1 --[incomplete]--> Phase 1 (resume)
```

---

## 3. Griefing Vector Analysis

### 3.1 Can an external caller advance the cursor without distributing ETH?

**No.** The cursor is only written within `_processDailyEthChunk`, which:
1. Is called only from `payDailyJackpot`
2. Which is called only via delegatecall from `AdvanceModule.payDailyJackpot` (internal wrapper)
3. Which is called only from `AdvanceModule.advanceGame()`
4. Which is called only via delegatecall from `DegenerusGame.advanceGame()`

`advanceGame()` is publicly callable, but it performs full distribution work before advancing the cursor. The cursor saves the CURRENT position after paying winners -- there is no path to advance the cursor without executing the corresponding payments.

### 3.2 Can a caller manipulate the gas budget to cause premature cursor save?

**Partially, but not exploitably.** The `unitsBudget` is hardcoded as `DAILY_JACKPOT_UNITS_SAFE = 1000` (JackpotModule:162). It is NOT derived from `gasleft()` or any caller-controlled parameter. A caller cannot influence the unitsBudget value.

However, if a caller provides insufficient gas for the `advanceGame` call, the entire transaction reverts (Solidity out-of-gas revert). This means:
- No cursor save occurs (revert undoes all state changes)
- No winners are paid
- The system returns to its pre-call state
- The next caller with sufficient gas can proceed normally

Low-gas griefing is not possible because:
1. Insufficient gas causes a full revert (no partial state corruption)
2. The griefer wastes their own gas
3. The next legitimate caller proceeds as if the griefing call never happened

### 3.3 Can a caller force the cursor past unfilled buckets?

**No.** Empty buckets are handled gracefully:
- If `count == 0 || share == 0` (line 1388): `startWinnerIdx = 0; continue;` -- skip bucket, no cursor save
- If `winners.length == 0` (line 1408): `startWinnerIdx = 0; continue;` -- skip bucket, no cursor save
- If `perWinner == 0` (line 1414): `startWinnerIdx = 0; continue;` -- skip bucket, no cursor save

If ALL buckets have zero winners or zero shares, the outer loop completes without saving cursors, and the function returns `(0, true)` (complete with 0 paid). No corrupt state is written.

### 3.4 Can a caller prevent distribution by never calling advanceGame?

**Delayed, but not permanent.** If no one calls `advanceGame`, the distribution is delayed but not skipped. Key properties:
- The cursor state persists in storage indefinitely
- Once someone calls `advanceGame`, the resume mechanism picks up exactly where it left off
- The BURNIE bounty (`ADVANCE_BOUNTY = 500 BURNIE flip credit`) incentivizes callers
- Liveness timeouts (912 days at level 0, 365 days post-game) eventually trigger game-over if the game is truly abandoned

### 3.5 Can a griefer call advanceGame repeatedly to exhaust gas budgets?

**No.** After a daily jackpot call (fresh or resume), `advanceGame` breaks and emits `Advance(stage, lvl)`. On the NEXT call to `advanceGame`:
- Same day: `day == dailyIdx` triggers `revert NotTimeYet()` (if `_unlockRng` was called) OR the resume path fires (if cursors are non-zero)
- Next day: requires VRF fulfillment (1+ day wait)

The critical observation: during a resume cycle (cursors non-zero), `_unlockRng` is NOT called. This means `dailyIdx` stays at its previous value, so `day > dailyIdx` passes the gate, and anyone can call `advanceGame` again. Multiple callers in the same day CAN trigger multiple resume chunks. This is BY DESIGN -- it's how the distribution completes across multiple calls.

However, each call makes PROGRESS (pays winners up to `unitsBudget`). A griefer calling `advanceGame` repeatedly would actually HELP complete the distribution faster. There is no path where repeated calls waste budget without distributing ETH.

---

## 4. unitsBudget Gas Mechanism

### 4.1 Computation

`unitsBudget` is a constant: `DAILY_JACKPOT_UNITS_SAFE = 1000` (JackpotModule:162).

It is passed as a parameter to `_processDailyEthChunk` (line 453) and used as the upper bound for total work per call.

### 4.2 Cost Model

Each winner costs either 1 or 3 units (JackpotModule:1315-1321):
```solidity
function _winnerUnits(address winner) private view returns (uint8 units) {
    if (winner == address(0)) return 0;
    return autoRebuyState[winner].autoRebuyEnabled
        ? DAILY_JACKPOT_UNITS_AUTOREBUY  // 3
        : 1;
}
```

- Normal winner: 1 unit (simple `claimableWinnings` credit)
- Auto-rebuy winner: 3 units (converts winnings to tickets -- more expensive)
- Zero-address winner: 0 units (skipped)

### 4.3 Budget Exhaustion

When `unitsUsed + cost > unitsBudget` (line 1423):
1. Current cursors are saved
2. `claimablePool` is updated with accumulated liability
3. Function returns `(paidEth, false)` -- cleanly, no revert

The caller (`payDailyJackpot` -> Phase 0 path at line 457) detects `!dailyComplete` and returns immediately, preserving cursor state for the next call.

### 4.4 Minimum Progress Guarantee

With `unitsBudget = 1000` and worst case `cost = 3` (auto-rebuy):
- Minimum winners per call: 333 (1000/3)
- Maximum winners per call: 1000 (all cost-1)

With `DAILY_ETH_MAX_WINNERS = 321` total winners across all buckets, the distribution always completes in at most 1 call for Phase 0. For Phase 0 + Phase 1 combined, at most 2 calls are needed (one per phase).

However, auto-rebuy processing at cost 3 could cause a single phase to split across calls if all 321 winners have auto-rebuy enabled: 321 * 3 = 963 units < 1000 -- so even in the worst case, a single phase completes in one call. A budget of 0 is impossible since `unitsBudget` is a compile-time constant.

**No infinite loop of no-progress calls is possible.** Each call processes at least one winner (the budget check is `unitsUsed + cost > unitsBudget`, not `>=`, and `cost` is at most 3 while `unitsBudget` is 1000).

---

## 5. Edge Case Analysis

### 5.1 Zero-Budget Distribution

If `dailyEthPoolBudget` computes to 0 (e.g., `currentPrizePool` is 0 or `dailyBps` rounds to 0):

Line 331: `dailyEthPoolBudget = budget` where `budget = 0`.

Phase 0 entry (line 421-423):
```solidity
if (dailyEthPhase == 0) {
    uint256 budget = dailyEthPoolBudget;  // 0
    if (budget != 0) { ... } else {
        dailyCarryoverWinnerCap = DAILY_ETH_MAX_WINNERS;
    }
```

The `budget != 0` check at line 423 skips the entire distribution. Cursor variables stay at 0 (from initialization). If no carryover either, the full reset path fires at lines 475-481. SAFE.

### 5.2 Single-Winner Bucket

A bucket with exactly 1 winner:
- `count = 1`, `totalCount = 1`, `perWinner = share / 1 = share`
- Winner loop iterates once (i=0)
- Winner is paid `share` amount
- `startWinnerIdx = 0` at line 1455 (bucket complete)
- Cursor advances to next bucket

Correct behavior. No edge case issues.

### 5.3 Maximum-Winner Bucket (250 winners)

A bucket with 250 winners:
- `totalCount = min(count, MAX_BUCKET_WINNERS) = 250`
- 250 winners generated by `_randTraitTicketWithIndices`
- At cost 1 per winner: 250 units consumed (well within 1000 budget)
- At cost 3 per winner: 750 units consumed (still within 1000 budget)
- All 250 winners paid in a single chunk

Even with 4 buckets at 250 winners each (1000 total -- impossible given `DAILY_ETH_MAX_WINNERS = 321`), the budget of 1000 units would handle at least 333 normal winners per call.

### 5.4 Day Boundary During Incomplete Distribution

**Can a new day start before the previous day's distribution completes?**

No. The flow prevents this:

1. During active distribution (cursors non-zero), `_unlockRng()` has NOT been called
2. `dailyIdx` has NOT been updated
3. When next day arrives (`day > dailyIdx`), `advanceGame` proceeds
4. `rngGate` returns cached `rngWordByDay[day]` (same word from first call)
5. The resume check (AdvanceModule:254-258) fires because cursors are non-zero
6. Distribution resumes from saved position

The previous day's distribution MUST complete before new daily work can start:
- Resume path (line 260) fires before fresh daily jackpot (line 282)
- `_unlockRng(day)` is only called AFTER `dailyJackpotCoinTicketsPending` is processed (line 276)
- `dailyJackpotCoinTicketsPending` is only set after cursor distribution fully completes

**No day boundary can overwrite cursor state.** The previous distribution always finishes first.

### 5.5 Concurrent Modification During Distribution

**Can ticket purchases or burns during distribution affect winner lists?**

No. During jackpot phase (`jackpotPhaseFlag = true`):
- Purchase function checks `jackpotPhaseFlag` and applies appropriate restrictions
- The `traitBurnTicket[lvl]` array for the CURRENT level is not modified during jackpot phase
- `_randTraitTicketWithIndices` is a `view` function that reads from this immutable-during-jackpot array

The winner list is effectively snapshotted by the immutability of `traitBurnTicket[lvl]` during jackpot phase.

### 5.6 `_processDailyEthChunk` Return After ethPool=0

If `ethPool == 0` (line 1353-1355):
```solidity
if (ethPool == 0) {
    return (0, true);
}
```

Returns immediately as complete, cursor variables unchanged. The caller sees `dailyComplete = true` and proceeds to Phase 1 or reset. No cursor state corruption. SAFE.

---

## 6. DOS-02 Verdict: Daily ETH Distribution Cursor Griefing Resistance

### Requirement

> Daily ETH distribution bucket cursor cannot be griefed to skip distributions.

### Verdict: PASS

### Reasoning

The daily ETH distribution cursor system is resistant to griefing because:

**1. No External Cursor Manipulation.**
All cursor writes occur within `_processDailyEthChunk` in `DegenerusGameJackpotModule`, which is only reachable via the delegatecall chain from `DegenerusGame.advanceGame()`. No external contract or caller can directly write to cursor storage variables.

**2. Deterministic Resume.**
On resume, bucket shares, winner lists, and per-winner amounts are recomputed identically from stored parameters (`dailyEthPoolBudget`, `lastDailyJackpotWinningTraits`, `lastDailyJackpotLevel`) and the cached RNG word (`rngWordByDay[day]`). The `traitBurnTicket[lvl]` array is immutable during jackpot phase. The `_skipEntropyToBucket` function ensures entropy state is consistent across chunks.

**3. Correct Save/Resume Boundary.**
The cursor saves at winner `i` BEFORE processing it. Resume starts at winner `i`. No winner is double-paid or skipped. The `startWinnerIdx` is reset to 0 when advancing to the next bucket (line 1455).

**4. Complete Reset.**
Both Phase 0 and Phase 1 completion paths zero ALL cursor variables plus `dailyCarryoverEthPool` and `dailyCarryoverWinnerCap`. No stale state persists between distributions.

**5. Atomic Phase Transitions.**
Phase 0 -> Phase 1 transition resets bucket and winner cursors to 0. Phase 1 -> Reset zeros everything. All transitions occur within a single transaction.

**6. Mandatory Completion Before New Work.**
The AdvanceModule resume check (lines 254-258) fires before the fresh daily jackpot path (line 282). An incomplete distribution MUST complete before new daily work begins. Day boundary changes cannot overwrite cursor state.

**7. Gas Budget Is Not Caller-Controllable.**
`unitsBudget = 1000` is a compile-time constant. Insufficient gas causes full transaction revert (no partial state). Repeated calls make progress (pay winners), benefiting the system.

**8. Graceful Empty-Bucket Handling.**
Zero-count buckets, zero-share buckets, and zero-winner results are all handled with `continue` (no cursor save, no state corruption).

---

## 7. Findings

### Informational

**INF-01: dailyEthPoolBudget is never decremented during chunked distribution**

`dailyEthPoolBudget` is set once during fresh start (line 331) and only zeroed on completion (lines 478, 543). Between chunks, it retains the ORIGINAL budget value. Each chunk's `paidEth` is separately deducted from `currentPrizePool` (line 455). This design is intentional -- it ensures `perWinner = share / totalCount` is identical across chunks -- but it means `dailyEthPoolBudget` does NOT reflect remaining distribution work. The budget is used purely for share computation, not as a "remaining balance" tracker.

**Severity:** Informational -- no impact on correctness.

**INF-02: Maximum winners per phase (321) always fits within unitsBudget (1000)**

With `DAILY_ETH_MAX_WINNERS = 321` and worst-case per-winner cost of 3 (auto-rebuy), the maximum units consumed is `321 * 3 = 963 < 1000`. This means a single phase always completes in one `_processDailyEthChunk` call. The chunking mechanism, while correctly implemented, may never actually trigger for the daily distribution under current constants. This could change if `DAILY_ETH_MAX_WINNERS` or `DAILY_JACKPOT_UNITS_SAFE` constants are adjusted.

**Severity:** Informational -- defense-in-depth that may not activate under current parameters. If constants change, the chunking mechanism is ready.

**INF-03: Resume detection condition is mirrored between AdvanceModule and JackpotModule**

The resume condition appears in two places:
- AdvanceModule:254-258 (controls whether to call resume path vs fresh path)
- JackpotModule:287-290 (controls whether to skip initialization)

These conditions check the same four variables but in different order. Both use OR-based logic, so order doesn't matter. However, the duplication creates a maintenance coupling: if one is updated without the other, the system could enter inconsistent states (e.g., AdvanceModule thinks it's resuming but JackpotModule initializes fresh). Comment at AdvanceModule:252-253 acknowledges this: "Must match payDailyJackpot's isResuming condition."

**Severity:** Informational -- documented coupling, not currently a bug.

---

## 8. Summary

| Check | Result |
|-------|--------|
| All cursor variable write sites within JackpotModule | PASS |
| Fresh start initialization of all four variables | PASS |
| Cursor save at exact (bucket, winner) position | PASS |
| Resume from exact saved position (no skip, no repeat) | PASS |
| Complete reset after distribution | PASS |
| Phase 0 -> Phase 1 transition with cursor reset | PASS |
| Phase 1 skip when carryover is zero | PASS |
| No phase counter beyond 1 | PASS |
| No external cursor advancement without distribution | PASS |
| Gas budget not caller-controllable | PASS |
| Empty bucket handling | PASS |
| Day boundary cannot overwrite cursor state | PASS |
| Winner list deterministic across resume calls | PASS |
| **DOS-02 Verdict** | **PASS** |
