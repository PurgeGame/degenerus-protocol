# Phase 78: Edge Case Safety Proof

## Summary

Both EDGE-01 and EDGE-02 are proven **SAFE** by the existing implementation from Phases 74-76.
No contract code changes required.

The far-future ticket system uses three disjoint key spaces (Slot0, FF, Slot1) with deterministic
routing at deposit time, sequential (not merged) queue processing, and monotonic level progression.
These properties make both double-counting and re-processing structurally impossible.

---

## EDGE-01: No Double-Counting Between FF Key and Write Buffer

### Claim

A ticket deposited into the FF key for level L is correctly handled when level L later
enters the +2 to +6 near-future window. No double-counting occurs between FF key and
write buffer.

### Proof

**Structural Fact 1: Key spaces are disjoint.**

Three key spaces exist, encoded via bits 22-23 of the uint24 level key
(DegenerusGameStorage.sol line 162):

```solidity
uint24 internal constant TICKET_FAR_FUTURE_BIT = 1 << 22;  // line 162
```

Key encoding functions (DegenerusGameStorage.sol lines 716-731):
- `_tqWriteKey(lvl)`: Slot0 = `lvl` (bits 22-23 clear) or Slot1 = `lvl | 0x800000` (bit 23 set), depending on `ticketWriteSlot` (line 716-718)
- `_tqReadKey(lvl)`: opposite of write key (line 721-723)
- `_tqFarFutureKey(lvl)`: FF = `lvl | 0x400000` (bit 22 set) (line 729-731)

Range analysis:
- Slot0: `[0x000000, 0x3FFFFF]` -- bits 22-23 both clear
- FF: `[0x400000, 0x7FFFFF]` -- bit 22 set, bit 23 clear
- Slot1: `[0x800000, 0xBFFFFF]` -- bit 22 clear, bit 23 set

For any valid level `lvl < 2^22`, these three ranges are non-overlapping. Phase 74 fuzz tests
prove non-collision for all valid levels.

**Structural Fact 2: Routing is deterministic at deposit time.**

At the moment of deposit, `_queueTickets` checks the CURRENT level to determine routing
(DegenerusGameStorage.sol lines 544-546):

```solidity
bool isFarFuture = targetLevel > level + 6;                                    // line 544
if (isFarFuture && rngLockedFlag && !phaseTransitionActive) revert RngLocked(); // line 545
uint24 wk = isFarFuture ? _tqFarFutureKey(targetLevel) : _tqWriteKey(targetLevel); // line 546
```

At deposit time, the ticket goes to exactly ONE key space. The check uses the current `level`
at time of deposit, not the level at time of processing. A single deposit CANNOT exist in two
key spaces.

**Structural Fact 3: `ticketsOwedPacked` is keyed on `wk` (the encoded key), not raw level.**

```solidity
uint40 packed = ticketsOwedPacked[wk][buyer];  // line 547
```

A player's owed count at `ticketsOwedPacked[_tqFarFutureKey(L)][player]` is completely
independent of `ticketsOwedPacked[_tqWriteKey(L)][player]`. They are separate storage slots
in the mapping. Modifying one has zero effect on the other.

**Structural Fact 4: `processFutureTicketBatch` drains queues sequentially, not merged.**

The processing function selects its read key based on the FF bit in `ticketLevel`
(DegenerusGameMintModule.sol lines 302-303):

```solidity
bool inFarFuture = (ticketLevel == (lvl | TICKET_FAR_FUTURE_BIT));  // line 302
uint24 rk = inFarFuture ? _tqFarFutureKey(lvl) : _tqReadKey(lvl);  // line 303
```

Each queue is processed against its own `ticketsOwedPacked[rk]` entries. The read-side queue
(entries from `_tqWriteKey` after buffer swap) is drained first. Only after it is fully empty
does the function transition to the FF queue by setting `ticketLevel = lvl | TICKET_FAR_FUTURE_BIT`
(line 311). No cross-contamination occurs between the two drains.

### Scenario Trace

Full trace of a level L transitioning from far-future to near-future:

| Time | `level` | Level 15 relative to window | Deposit to level 15 goes to | Processing reads from |
|------|---------|-----------------------------|-----------------------------|----------------------|
| T1 | 5 | Far-future (`15 > 5+6 = 11`) | `_tqFarFutureKey(15)` = `15 \| 0x400000` | Not yet processed |
| T2 | 10 | Near-future (`15 <= 10+6 = 16`) | `_tqWriteKey(15)` | `_prepareFutureTickets` probes levels 12-16 |
| T3 | 10, after swap | Same | New deposits go to write key | `processFutureTicketBatch(15)` reads `_tqReadKey(15)` then `_tqFarFutureKey(15)` |

At T3:
- The T1 deposit (in FF key `0x40000F`) is in the FF queue
- The T2 deposit (in write key, swapped to read key) is in the read-side queue
- Both queues are processed independently by `processFutureTicketBatch(15)`
- Player deposited twice (at T1 and T2) and gets BOTH sets of tickets minted

This is correct behavior -- they deposited twice and deserve both. This is NOT double-counting
because each deposit was tracked under a different key and processed from a different queue.

### Verdict: SAFE

The combination of disjoint key spaces (Fact 1), deterministic routing at deposit time (Fact 2),
independent `ticketsOwedPacked` tracking per key (Fact 3), and sequential queue processing (Fact 4)
makes double-counting structurally impossible.

---

## EDGE-02: No Re-Processing After FF Key Drain

### Claim

Once `processFutureTicketBatch` has fully drained the FF key for a level, subsequent
deposits to that same level's FF key start a fresh queue that does not re-process
already-minted entries.

### Proof

**Structural Fact 1: Monotonic level progression prevents new FF deposits to drained levels.**

The game level is set at DegenerusGameAdvanceModule.sol line 1340:

```solidity
level = lvl;  // lvl = purchaseLevel = level + 1; only increases (line 1340)
```

Level only increases and is never decremented. There is no mechanism anywhere in the protocol
to decrease the level variable.

The FF key for level L is drained by `processFutureTicketBatch` when `_prepareFutureTickets(currentLevel)`
includes L in its processing range `[currentLevel+2, currentLevel+6]`. This requires `currentLevel >= L-6`.

Once `level >= L-6`, any future deposit to level L checks:
```
isFarFuture = (L > level + 6)
            = (L > (>= L-6) + 6)
            = (L > (>= L))
            = false
```

Since `level` only increases, `isFarFuture` is permanently `false` for level L.
New deposits go to `_tqWriteKey(L)`, not `_tqFarFutureKey(L)`.

**Structural Fact 2: `delete ticketQueue[rk]` creates a clean slate.**

After fully processing a queue, the array is deleted (DegenerusGameMintModule.sol line 438):

```solidity
delete ticketQueue[rk];  // line 438
```

Solidity `delete` on a dynamic array sets its length to 0 and clears all elements. Any
subsequent `push` to `ticketQueue[ffk]` would start at index 0 with a fresh array. There
is no leftover state from the old queue.

**Structural Fact 3: `ticketsOwedPacked` is zeroed per-player during processing.**

During the batch processing loop (DegenerusGameMintModule.sol lines 356-431), every player
is processed until `remainingOwed == 0`. The code path:

```solidity
uint40 packed = ticketsOwedPacked[rk][player];                    // line 356
// ... processing loop reduces remainingOwed to 0 ...
uint40 newPacked = (uint40(remainingOwed) << 8) | uint40(rem);    // line 418
if (newPacked != packed) {
    ticketsOwedPacked[rk][player] = newPacked;                    // line 420
}
```

When `remainingOwed == 0` and `rem == 0`: `newPacked = 0`, so `ticketsOwedPacked[rk][player] = 0`.

Skip paths also zero the packed value (lines 362, 371):
```solidity
ticketsOwedPacked[rk][player] = 0;  // lines 362, 371
```

Queue deletion (`delete ticketQueue[rk]` at line 438) only occurs when `idx >= total`,
meaning every player has been fully processed and their owed state zeroed.

**Structural Fact 4: Even hypothetically, new deposits start fresh.**

In `_queueTickets` (DegenerusGameStorage.sol lines 550-551):

```solidity
if (owed == 0 && rem == 0) {
    ticketQueue[wk].push(buyer);  // lines 550-551
}
```

After processing zeros `ticketsOwedPacked[ffk][player]` and `delete` clears the queue array,
a hypothetical new deposit would find `packed == 0` (because Fact 3 zeroed it), push a fresh
entry at index 0 (because Fact 2 deleted the array), and set a new owed count. Processing
would start from cursor 0 with the fresh queue. No old entries exist to re-process.

### Monotonic Level Argument

Formal argument that the drained FF queue can never receive new entries:

1. **Premise:** FF key for level L is drained. This requires `currentLevel >= L-6` (for L to be in the `_prepareFutureTickets` processing range `[currentLevel+2, currentLevel+6]`).

2. **Invariant:** `level` only increases (DegenerusGameAdvanceModule.sol line 1340: `level = lvl` where `lvl = purchaseLevel = level + 1`). There is no decrement path.

3. **Routing check:** For any future deposit to level L:
   ```
   isFarFuture = (L > level + 6)
   ```
   Since `level >= L-6` (from premise) and `level` only increases (from invariant):
   ```
   L > level + 6
   = L > (>= L-6) + 6
   = L > (>= L)
   = false (always)
   ```

4. **Conclusion:** New deposits to level L always route to `_tqWriteKey(L)`, never to `_tqFarFutureKey(L)`. The drained FF queue can never receive new entries.

### Verdict: SAFE

The monotonic level progression (Fact 1) guarantees that once an FF key is drained, no new
deposits can reach it. The `delete ticketQueue[rk]` cleanup (Fact 2) and per-player
`ticketsOwedPacked` zeroing (Fact 3) ensure no leftover state. Even in the hypothetical case
of a new deposit (which Fact 1 proves impossible), fresh state would start a clean queue (Fact 4).

---

## Test Coverage

Five Foundry tests in `test/fuzz/TicketEdgeCases.t.sol` provide executable proof:

| Test | Edge Case | What It Proves |
|------|-----------|----------------|
| `testEdge01NoDoubleCount_FFThenWriteKey` | EDGE-01 | FF key and write key deposits for same level are tracked independently with separate `ticketsOwedPacked` entries |
| `testEdge01ProcessBothQueuesIndependently` | EDGE-01 | Processing drains read-side and FF queues sequentially without cross-contamination |
| `testEdge02RoutingPreventsNewFFDeposits` | EDGE-02 | Once `level >= L-6`, routing sends all deposits to write key, never FF key |
| `testEdge02CleanupAfterDrain` | EDGE-02 | Queue deletion and cursor reset after FF drain leave clean state |
| `testEdge01FFOnlyQueue_NoReadSide` | EDGE-01 | FF-only levels (empty read-side) are processed correctly |

All 5 tests pass. Zero regressions on existing test suites (TicketRouting: 12/12, TicketProcessingFF: 9/9).

## Source File References

| File | Lines | Content |
|------|-------|---------|
| `contracts/storage/DegenerusGameStorage.sol` | 162 | `TICKET_FAR_FUTURE_BIT = 1 << 22` |
| `contracts/storage/DegenerusGameStorage.sol` | 544-546 | `_queueTickets` routing: `isFarFuture` check + key selection |
| `contracts/storage/DegenerusGameStorage.sol` | 547 | `ticketsOwedPacked[wk][buyer]` mapping read |
| `contracts/storage/DegenerusGameStorage.sol` | 550-551 | Queue push on first deposit (`owed == 0 && rem == 0`) |
| `contracts/storage/DegenerusGameStorage.sol` | 716-718 | `_tqWriteKey`: slot-dependent key encoding |
| `contracts/storage/DegenerusGameStorage.sol` | 721-723 | `_tqReadKey`: opposite of write key |
| `contracts/storage/DegenerusGameStorage.sol` | 729-731 | `_tqFarFutureKey`: bit 22 key space |
| `contracts/modules/DegenerusGameMintModule.sol` | 302-303 | `processFutureTicketBatch` FF phase detection + key selection |
| `contracts/modules/DegenerusGameMintModule.sol` | 311 | FF transition: `ticketLevel = lvl \| TICKET_FAR_FUTURE_BIT` |
| `contracts/modules/DegenerusGameMintModule.sol` | 356, 418-420 | `ticketsOwedPacked` read and zero-on-completion |
| `contracts/modules/DegenerusGameMintModule.sol` | 362, 371 | Skip-path `ticketsOwedPacked` zeroing |
| `contracts/modules/DegenerusGameMintModule.sol` | 438 | `delete ticketQueue[rk]` queue cleanup |
| `contracts/modules/DegenerusGameAdvanceModule.sol` | 1340 | `level = lvl` (monotonic increment, never decrements) |

## Conclusion

Both EDGE-01 and EDGE-02 are **SAFE**. The combination of disjoint key spaces (Phase 74),
deterministic routing at deposit time (Phase 75), and sequential dual-queue processing (Phase 76)
makes both double-counting and re-processing structurally impossible. No contract code changes
are required. The five Foundry tests serve as regression guards for future development.
