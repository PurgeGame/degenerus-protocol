# Behavioral Equivalence Trace: _processDailyEthChunk

## Executive Summary

The chunk removal from `_processDailyEthChunk` is behaviorally equivalent to the original implementation because the removed chunking infrastructure -- cursor save/restore, unit budget tracking, entropy replay via `_skipEntropyToBucket`, and the `_winnerUnits` cost function -- constituted **dead code** that could never execute under the protocol's constant constraints. The worst-case unit consumption is 321 winners x 3 units = 963, which is strictly less than the budget of 1000 (`DAILY_JACKPOT_UNITS_SAFE`). Since `complete=false` was unreachable, the cursors (`dailyEthBucketCursor`, `dailyEthWinnerCursor`) were always (0, 0) on entry, making every code path that depended on non-zero cursors dead. The new single-pass function produces identical entropy chains, winner selections, payout amounts, liability tracking, and effective return behavior.

## 1. Dead Code Proof

The chunking path activates when the unit budget is exhausted, causing an early return with `complete=false`. This section proves that path was unreachable.

**Constants (from `DegenerusGameJackpotModule.sol`):**

| Constant | Value | Purpose |
|----------|-------|---------|
| `DAILY_JACKPOT_UNITS_SAFE` | `uint16 = 1000` | Unit budget passed to `_processDailyEthChunk` |
| `DAILY_JACKPOT_UNITS_AUTOREBUY` | `uint8 = 3` | Unit cost per auto-rebuy winner (highest cost) |
| `DAILY_ETH_MAX_WINNERS` | `uint16 = 321` | Maximum total daily ETH jackpot winners |
| `MAX_BUCKET_WINNERS` | `uint8 = 250` | Per-bucket winner cap |

**The budget check (old code, line ~1468):**

```solidity
uint8 cost = _winnerUnits(w);
if (cost != 0 && unitsUsed + cost > unitsBudget) {
    dailyEthBucketCursor = j;
    dailyEthWinnerCursor = uint16(i);
    // ... save state, return (paidEth, false)
}
```

**`_winnerUnits` returns either 1 (normal winner) or 3 (auto-rebuy enabled):**

```solidity
function _winnerUnits(address winner) private view returns (uint8 units) {
    if (winner == address(0)) return 0;
    return autoRebuyState[winner].autoRebuyEnabled
        ? DAILY_JACKPOT_UNITS_AUTOREBUY  // 3
        : 1;
}
```

**Worst-case arithmetic:**

- Total winners across all 4 buckets is capped by `DAILY_ETH_MAX_WINNERS = 321` (enforced by `JackpotBucketLib.bucketCountsForPoolCap`)
- Each bucket is independently capped at `MAX_BUCKET_WINNERS = 250`
- Maximum cost per winner: `DAILY_JACKPOT_UNITS_AUTOREBUY = 3` (all winners have auto-rebuy)
- **Worst case: 321 winners x 3 units = 963 units**
- **Budget: DAILY_JACKPOT_UNITS_SAFE = 1000 units**
- **963 < 1000**

Therefore: `unitsUsed + cost > unitsBudget` is **always false**. The `complete=false` return path was **unreachable**. Every execution completed in a single call.

**Cascading implications:**

1. `dailyEthBucketCursor` was never written with a non-zero value inside the loop
2. `dailyEthWinnerCursor` was never written with a non-zero value inside the loop
3. On entry, both cursors were always 0 (they were reset to 0 at the end of every complete call, and at phase transitions)
4. `_skipEntropyToBucket(entropy, order, shares, bucketCounts, 0)` returns `entropy` unchanged (the loop `for (uint8 j; j < 0; ++j)` executes zero iterations)
5. `startWinnerIdx = 0` means `for (uint256 i = startWinnerIdx; ...)` is equivalent to `for (uint256 i = 0; ...)`

## 2. Entropy Chain Equivalence

Both versions produce identical entropy states at every step of the bucket iteration.

**Old version (with cursors at 0,0 -- the only reachable state):**

```solidity
// _skipEntropyToBucket with startOrderIdx=0 (zero-iteration loop)
uint256 entropyState = _skipEntropyToBucket(
    entropy, order, shares, bucketCounts, 0  // startOrderIdx = dailyEthBucketCursor = 0
);
// entropyState == entropy (unchanged)

// For each non-empty bucket j (j=0..3):
entropyState = EntropyLib.entropyStep(
    entropyState ^ (uint256(traitIdx) << 64) ^ share
);
```

**New version:**

```solidity
uint256 entropyState = entropy;

// For each non-empty bucket j (j=0..3):
entropyState = EntropyLib.entropyStep(
    entropyState ^ (uint256(traitIdx) << 64) ^ share
);
```

**Step-by-step comparison:**

1. **Initialization:** Old: `_skipEntropyToBucket(entropy, ..., 0)` returns `entropy`. New: `entropyState = entropy`. **Identical.**
2. **Bucket ordering:** Both use `JackpotBucketLib.bucketOrderLargestFirst(bucketCounts)` to determine `order[4]`. **Identical.**
3. **Skip condition:** Both skip buckets where `count == 0 || share == 0`. **Identical.**
4. **Entropy derivation:** Both compute `EntropyLib.entropyStep(entropyState ^ (uint256(traitIdx) << 64) ^ share)`. The `entropyStep` function (from `EntropyLib.sol`) is a deterministic xorshift:
   ```solidity
   function entropyStep(uint256 state) internal pure returns (uint256) {
       unchecked {
           state ^= state << 7;
           state ^= state >> 9;
           state ^= state << 8;
       }
   }
   ```
   Same inputs produce same outputs. **Identical.**

**Conclusion:** The entropy state is identical at every step in both versions. Any downstream computation depending on `entropyState` (winner selection, auto-rebuy detection) receives the same input.

## 3. Winner Selection Equivalence

Both versions call `_randTraitTicketWithIndices` with identical arguments at each bucket.

**Old version (startWinnerIdx=0 always):**

```solidity
(address[] memory winners, uint256[] memory ticketIndexes) =
    _randTraitTicketWithIndices(
        traitBurnTicket[lvl],
        entropyState,           // identical per Section 2
        traitIds[traitIdx],     // same trait ID
        uint8(totalCount),      // same count (same bucketCounts, same MAX_BUCKET_WINNERS cap)
        uint8(200 + traitIdx)   // same salt
    );
```

**New version:**

```solidity
(address[] memory winners, uint256[] memory ticketIndexes) =
    _randTraitTicketWithIndices(
        traitBurnTicket[lvl],
        entropyState,           // identical per Section 2
        traitIds[traitIdx],     // same trait ID
        uint8(totalCount),      // same count
        uint8(200 + traitIdx)   // same salt
    );
```

**Argument comparison:**

| Argument | Old | New | Identical? |
|----------|-----|-----|------------|
| `traitBurnTicket[lvl]` | Same storage read | Same storage read | Yes |
| `entropyState` | Per Section 2 | Per Section 2 | Yes |
| `traitIds[traitIdx]` | Same calldata | Same calldata | Yes |
| `totalCount` | `min(count, MAX_BUCKET_WINNERS)` | `min(count, MAX_BUCKET_WINNERS)` | Yes |
| salt `200 + traitIdx` | Same formula | Same formula | Yes |

**Conclusion:** `_randTraitTicketWithIndices` receives identical inputs at every bucket, producing identical `winners[]` and `ticketIndexes[]` arrays.

## 4. Payout Amount Equivalence

Both versions compute and distribute identical per-winner payouts.

**Old version (starting from winner index 0):**

```solidity
uint256 perWinner = share / totalCount;
// ...
uint256 len = winners.length;
for (uint256 i = startWinnerIdx; i < len; ) {  // startWinnerIdx = 0 always
    address w = winners[i];
    // ...
    if (w != address(0)) {
        uint256 claimableDelta = _addClaimableEth(w, perWinner, entropyState);
        emit JackpotTicketWinner(w, lvl, traitIds[traitIdx], perWinner, ticketIndexes[i]);
        paidEth += perWinner;
        liabilityDelta += claimableDelta;
    }
    // Note: _winnerUnits(w) and unitsUsed tracking happen here but never trigger early exit
}
```

**New version:**

```solidity
uint256 perWinner = share / totalCount;
// ...
uint256 len = winners.length;
for (uint256 i; i < len; ) {  // i starts at 0
    address w = winners[i];
    if (w != address(0)) {
        uint256 claimableDelta = _addClaimableEth(w, perWinner, entropyState);
        emit JackpotTicketWinner(w, lvl, traitIds[traitIdx], perWinner, ticketIndexes[i]);
        paidEth += perWinner;
        liabilityDelta += claimableDelta;
    }
}
```

**Per-winner payout:**

| Component | Old | New | Identical? |
|-----------|-----|-----|------------|
| `share` | From `JackpotBucketLib.bucketShares(...)` | Same call, same args | Yes |
| `totalCount` | `min(count, MAX_BUCKET_WINNERS)` | Same computation | Yes |
| `perWinner = share / totalCount` | Integer division | Same integer division | Yes |
| Loop start | `i = startWinnerIdx = 0` | `i = 0` | Yes |
| Loop end | `i < winners.length` | `i < winners.length` | Yes |
| Payout call | `_addClaimableEth(w, perWinner, entropyState)` | Same call, same args | Yes |

**Removed code that has no effect on payouts:**

```solidity
// Old version only - inside the winner loop:
uint8 cost = _winnerUnits(w);
// cost is computed but only used for budget check (which never triggers)
unitsUsed += cost;
// unitsUsed is accumulated but never causes early return (963 < 1000)
```

This `_winnerUnits` call and `unitsUsed` accumulation are pure overhead -- they never alter control flow, never modify payouts, and never trigger cursor save.

**Conclusion:** Every winner receives the same `perWinner` amount via `_addClaimableEth`. The `paidEth` total is identical.

## 5. Liability Tracking Equivalence

Both versions accumulate `liabilityDelta` identically and write `claimablePool` once at the end.

**Old version:**

```solidity
uint256 liabilityDelta;
// ... (for each bucket, for each winner):
liabilityDelta += claimableDelta;  // claimableDelta from _addClaimableEth
// ... after all buckets:
if (liabilityDelta != 0) {
    claimablePool += liabilityDelta;
}
dailyEthBucketCursor = 0;     // Removed (always 0 -> 0, no-op)
dailyEthWinnerCursor = 0;     // Removed (always 0 -> 0, no-op)
return (paidEth, true);        // complete always true
```

**New version:**

```solidity
uint256 liabilityDelta;
// ... (for each bucket, for each winner):
liabilityDelta += claimableDelta;  // same claimableDelta values (same inputs to _addClaimableEth)
// ... after all buckets:
if (liabilityDelta != 0) {
    claimablePool += liabilityDelta;
}
return paidEth;
```

**Comparison:**

| Step | Old | New | Identical? |
|------|-----|-----|------------|
| Accumulation order | Same bucket order, same winner order | Same | Yes |
| `claimableDelta` values | From `_addClaimableEth(w, perWinner, entropyState)` | Same call, same args | Yes |
| Write point | Single `claimablePool +=` after all buckets | Same | Yes |
| Cursor reset (old only) | `dailyEthBucketCursor = 0; dailyEthWinnerCursor = 0;` | N/A | No-op: writing 0 to slots that already contained 0 |

**Note on the budget-exhaustion early write path (old only):**

```solidity
if (cost != 0 && unitsUsed + cost > unitsBudget) {
    // ...
    if (liabilityDelta != 0) {
        claimablePool += liabilityDelta;
    }
    return (paidEth, false);
}
```

This path is unreachable (Section 1), so this intermediate `claimablePool` write never executes.

**Conclusion:** `claimablePool` is updated with the same `liabilityDelta` value in both versions, at the same point in execution.

## 6. Return Value and Caller Integration

**Old signature and return:**

```solidity
function _processDailyEthChunk(
    uint24 lvl, uint256 ethPool, uint256 entropy,
    uint8[4] memory traitIds, uint16[4] memory shareBps,
    uint16[4] memory bucketCounts,
    uint16 unitsBudget                    // REMOVED parameter
) private returns (uint256 paidEth, bool complete) {
    // ...
    return (paidEth, true);               // complete always true
}
```

**New signature and return:**

```solidity
function _processDailyEthChunk(
    uint24 lvl, uint256 ethPool, uint256 entropy,
    uint8[4] memory traitIds, uint16[4] memory shareBps,
    uint16[4] memory bucketCounts
) private returns (uint256 paidEth) {
    // ...
    return paidEth;
}
```

**Caller changes in `payDailyJackpot` (DegenerusGameJackpotModule.sol):**

**Phase 0 -- old caller:**

```solidity
(uint256 paidDailyEth, bool dailyComplete) = _processDailyEthChunk(
    lvl, budget, entropyDaily, traitIdsDaily, shareBpsDaily, bucketCountsDaily,
    unitsBudget
);
currentPrizePool -= paidDailyEth;
if (!dailyComplete) { return; }    // REMOVED check (always true -> never returned)
```

**Phase 0 -- new caller:**

```solidity
uint256 paidDailyEth = _processDailyEthChunk(
    lvl, budget, entropyDaily, traitIdsDaily, shareBpsDaily, bucketCountsDaily
);
currentPrizePool -= paidDailyEth;
// No complete check needed -- always completes in one call
```

**Phase 1 (carryover) -- old caller:**

```solidity
(, bool carryComplete) = _processDailyEthChunk(
    carryoverSourceLevel, carryPool, entropyNext, traitIdsDaily, shareBpsNext,
    bucketCountsNext, unitsBudget
);
if (!carryComplete) { return; }    // REMOVED check (always true -> never returned)
```

**Phase 1 (carryover) -- new caller:**

```solidity
_processDailyEthChunk(
    carryoverSourceLevel, carryPool, entropyNext, traitIdsDaily, shareBpsNext,
    bucketCountsNext
);
// No complete check needed
```

**Net caller behavior:**

| Aspect | Old | New | Effect |
|--------|-----|-----|--------|
| `paidEth` | Returned and used | Same | Same `currentPrizePool` deduction |
| `complete` flag | Always `true` | Not returned | `if (!dailyComplete) return` was dead code |
| Phase progression | Always proceeds to carryover/finalize | Always proceeds | Identical |
| `unitsBudget` argument | Passed but unused (budget never exceeded) | Removed | No behavioral change |

**Conclusion:** Callers receive the same `paidEth` value. The `complete` flag removal is safe because `complete` was always `true`.

## 7. Worked Example

Consider a daily jackpot with 4 trait buckets, `ethPool = 10 ETH`, `lvl = 5`:

**Setup (identical in both versions):**

```
entropy = 0xABCD...1234  (from VRF word ^ (uint256(lvl) << 192))
traitIds = [0, 1, 2, 3]
```

Assume `JackpotBucketLib.bucketOrderLargestFirst` returns `order = [2, 0, 3, 1]` and `JackpotBucketLib.bucketShares` allocates:

| Bucket | traitIdx | count | share (wei) |
|--------|----------|-------|-------------|
| 0      | 0        | 10    | 2.5 ETH     |
| 1      | 1        | 0     | 0           |
| 2      | 2        | 20    | 4.0 ETH     |
| 3      | 3        | 5     | 0.5 ETH     |

**Iteration (both versions process in order [2, 0, 3, 1]):**

**Step 1: Bucket j=0, traitIdx=2, count=20, share=4.0 ETH**

```
entropyState = EntropyLib.entropyStep(entropy ^ (2 << 64) ^ 4e18)
  // Old: _skipEntropyToBucket(entropy, ..., 0) returned entropy unchanged, same derivation
  // New: entropyState = entropy, same derivation
```

Winner selection: `_randTraitTicketWithIndices(traitBurnTicket[5], entropyState, 2, 20, 202)`
- Returns 20 winners (addresses + ticket indexes)
- `perWinner = 4e18 / 20 = 0.2 ETH`
- Each non-zero winner: `_addClaimableEth(winner, 0.2 ETH, entropyState)`
- Old version: `_winnerUnits(w)` returns 1 or 3, accumulated to `unitsUsed` (max 60 after this bucket)

**Step 2: Bucket j=1, traitIdx=0, count=10, share=2.5 ETH**

```
entropyState = EntropyLib.entropyStep(entropyState ^ (0 << 64) ^ 2.5e18)
  // Both: same entropyState input from Step 1 -> same output
```

Winner selection: `_randTraitTicketWithIndices(traitBurnTicket[5], entropyState, 0, 10, 200)`
- Returns 10 winners
- `perWinner = 2.5e18 / 10 = 0.25 ETH`
- Old version: `unitsUsed` grows by at most 30 (max 90 cumulative)

**Step 3: Bucket j=2, traitIdx=3, count=5, share=0.5 ETH**

```
entropyState = EntropyLib.entropyStep(entropyState ^ (3 << 64) ^ 0.5e18)
  // Both: same entropyState input from Step 2 -> same output
```

Winner selection: `_randTraitTicketWithIndices(traitBurnTicket[5], entropyState, 3, 5, 203)`
- Returns 5 winners
- `perWinner = 0.5e18 / 5 = 0.1 ETH`
- Old version: `unitsUsed` grows by at most 15 (max 105 cumulative)

**Step 4: Bucket j=3, traitIdx=1, count=0, share=0**

- Both versions: `count == 0 || share == 0` -> `continue` (skip)
- No entropy step, no winner selection

**Post-loop (both versions):**

```
claimablePool += liabilityDelta;   // same accumulated value
return paidEth;                    // same total (0.2*20 + 0.25*10 + 0.1*5 = 7.0 ETH)
// Old also returns: true (complete)
// Old also writes: dailyEthBucketCursor = 0, dailyEthWinnerCursor = 0 (no-ops)
```

**Unit budget in old version for this example:**

- Worst case (all auto-rebuy): 20*3 + 10*3 + 5*3 = 105 units
- Best case (no auto-rebuy): 20*1 + 10*1 + 5*1 = 35 units
- Budget: 1000 units
- 105 << 1000. Budget never even approached.

## 8. Removed Symbols Inventory

| Symbol | Type | Former Purpose | Why Safe to Remove |
|--------|------|---------------|-------------------|
| `dailyEthBucketCursor` | `uint8` storage (slot 0, offset 30) | Resume bucket iteration at saved position | Always 0: the `complete=false` path that wrote non-zero was unreachable (963 < 1000) |
| `dailyEthWinnerCursor` | `uint16` storage (slot 17, offset 7) | Resume winner iteration within a bucket | Always 0: only written non-zero in the unreachable budget-exhaustion branch |
| `_skipEntropyToBucket` | `private pure` function | Replay entropy forward to resume mid-bucket after pause | Called with `startOrderIdx=0` (always), executing zero loop iterations, returning `entropy` unchanged |
| `_winnerUnits` | `private view` function | Compute unit cost per winner (1 normal, 3 auto-rebuy) | Only consumed by budget tracking. Budget was never exceeded, so the cost was computed and accumulated but never triggered any branching |
| `DAILY_JACKPOT_UNITS_SAFE` | `uint16 constant = 1000` | Gas budget in abstract units for chunked distribution | The budget ceiling. With max 963 units consumed, this constant served no protective purpose |
| `DAILY_JACKPOT_UNITS_AUTOREBUY` | `uint8 constant = 3` | Unit cost multiplier for auto-rebuy winners | Only used by `_winnerUnits` for budget tracking. Removing the budget removes the need for cost computation |

**Storage impact of removal:**

- Removing `dailyEthBucketCursor` (1 byte from slot 0) caused `dailyEthPhase` and `compressedJackpotFlag` to shift within the packed slot 0/1 layout. This is a compile-time packing change -- the Solidity compiler automatically adjusts field offsets. No runtime behavioral change.
- Removing `dailyEthWinnerCursor` (2 bytes from slot 17) freed space in the packed slot 17. Same compile-time adjustment, no runtime impact.

## 9. Test Evidence

Results from Plans 01 and 02 confirm no behavioral regressions:

### Hardhat Test Suite (Plan 01 -- DELTA-01)

- **Result:** 1209 passing, 33 failing
- **Before chunk removal:** 1209 passing, 33 failing (identical)
- **Delta:** Zero regressions
- **Verification commit:** `39f8330f`
- **Evidence file:** `.planning/phases/95-delta-verification/95-01-hardhat-verification.log`

All 33 failures are pre-existing issues documented in RESEARCH.md, categorized as:
- DegenerusStonk burn tests (10)
- Distress Lootbox tests (10)
- Mint Gate tests (7)
- Compressed Jackpot timing tests (3)
- Other pre-existing (3)

### Symbol Sweep (Plan 01 -- DELTA-02)

- **Result:** Zero remaining references to all 6 removed symbols in `contracts/`
- **Symbols verified absent:** `dailyEthBucketCursor`, `dailyEthWinnerCursor`, `_skipEntropyToBucket`, `_winnerUnits`, `DAILY_JACKPOT_UNITS_SAFE`, `DAILY_JACKPOT_UNITS_AUTOREBUY`
- **Verification commit:** `0b27caff`
- **Evidence file:** `.planning/phases/95-delta-verification/95-01-symbol-sweep.log`

### Foundry Test Suite (Plan 02 -- DELTA-04)

- **Result:** 354 passing, 14 failing
- **Before fixes:** 352 passing, 16 failing
- **Change:** Fixed 2 pre-existing `StorageFoundation` test failures (stale slot offsets corrected to match authoritative `forge inspect` output)
- **Remaining 14 failures:** All pre-existing (LootboxRngLifecycle 4, TicketLifecycle 3, VRFCore 2, VRFStallEdgeCases 3, FuturepoolSkim 1, VRFLifecycle 1)
- **Zero regressions from chunk removal**
- **Verification commits:** `ae004aeb`, `0b087689`, `5c4ad045`, `07761028`

## Conclusion

The chunk removal from `_processDailyEthChunk` is proven behaviorally equivalent across all 6 dimensions:

1. **Dead code:** 321 x 3 = 963 < 1000 -- the budget-exhaustion branch was unreachable
2. **Entropy:** Identical chain derivation (removed `_skipEntropyToBucket` with zero iterations is identity)
3. **Winners:** Same `_randTraitTicketWithIndices` calls with same arguments at every step
4. **Payouts:** Same `perWinner = share / totalCount` credited via same `_addClaimableEth` calls
5. **Liability:** Same `liabilityDelta` accumulation, same single `claimablePool` write
6. **Caller integration:** `complete=true` was the only reachable return, making the flag check dead code

The removed infrastructure was dead code that could never activate under the protocol's constant constraints (`DAILY_ETH_MAX_WINNERS=321`, `DAILY_JACKPOT_UNITS_AUTOREBUY=3`, `DAILY_JACKPOT_UNITS_SAFE=1000`). The Hardhat and Foundry test suites both confirm zero behavioral regressions. This document serves as formal audit evidence for C4A wardens reviewing the chunk removal.
