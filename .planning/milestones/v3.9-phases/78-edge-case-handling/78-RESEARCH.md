# Phase 78: Edge Case Handling - Research

**Researched:** 2026-03-22
**Domain:** Solidity ticket queue boundary conditions, far-future/near-future window transitions, queue lifecycle integrity
**Confidence:** HIGH

## Summary

Phase 78 addresses two boundary conditions around the far-future (FF) ticket lifecycle: (1) what happens when a level L that already has FF-key deposits transitions into the near-future +2..+6 processing window, and (2) whether draining and then re-populating the same FF key for a level can cause re-processing of already-minted entries.

After detailed code tracing of the implementation delivered by Phases 74-76, both edge cases are already handled correctly by the existing architecture. The routing decision in `_queueTickets` uses separate key spaces (`_tqFarFutureKey` vs `_tqWriteKey`) based on the deposit-time comparison `targetLevel > level + 6`. These key spaces use different uint24 keys in the `ticketQueue` and `ticketsOwedPacked` mappings, making double-counting structurally impossible. For re-processing, the monotonic level progression (level never decreases) guarantees that once an FF key for level L is drained (requiring currentLevel >= L-6), all future deposits to level L go to the write key, not the FF key.

**Primary recommendation:** This phase is an audit/verification phase, not a code-change phase. The research confirms both EDGE-01 and EDGE-02 are satisfied by the existing implementation. The phase deliverable should be a formal proof document explaining WHY these edge cases are safe, with specific code references. No contract modifications needed.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| EDGE-01 | Far-future tickets opened after their target level enters the +2..+6 near-future window are handled correctly (no double-counting or stranding) | Routing uses separate key spaces per deposit-time decision; `processFutureTicketBatch` drains both independently; structurally no overlap possible |
| EDGE-02 | Far-future tickets already processed by processFutureTicketBatch cannot be re-processed if new lootbox adds more tickets to the same FF key level | Monotonic level progression prevents new FF deposits after drain; `delete ticketQueue[rk]` clears array; `ticketsOwedPacked` zeroed per-player during processing; any hypothetical new push starts fresh |
</phase_requirements>

## Architecture Patterns

### EDGE-01: No Double-Counting Between FF Key and Write Buffer

The entire argument rests on three structural facts:

**Fact 1: Routing is deterministic and key-space-exclusive at deposit time.**

```solidity
// contracts/storage/DegenerusGameStorage.sol:544-546
bool isFarFuture = targetLevel > level + 6;
if (isFarFuture && rngLockedFlag && !phaseTransitionActive) revert RngLocked();
uint24 wk = isFarFuture ? _tqFarFutureKey(targetLevel) : _tqWriteKey(targetLevel);
```

At deposit time, a ticket goes to exactly ONE of:
- `_tqFarFutureKey(L)` = `L | 0x400000` (bit 22 set) -- when `L > level + 6`
- `_tqWriteKey(L)` = `L` or `L | 0x800000` (bit 23 set, depending on slot) -- when `L <= level + 6`

These three key spaces (Slot0, FF, Slot1) are proven non-colliding by Phase 74 fuzz tests. A single deposit CANNOT exist in two key spaces.

**Fact 2: `ticketsOwedPacked` is keyed on `wk`, not on the raw level.**

```solidity
// contracts/storage/DegenerusGameStorage.sol:547
uint40 packed = ticketsOwedPacked[wk][buyer];
```

A player's owed count at `ticketsOwedPacked[_tqFarFutureKey(L)][player]` is completely independent of `ticketsOwedPacked[_tqWriteKey(L)][player]`. Processing one does not affect the other.

**Fact 3: `processFutureTicketBatch` processes read-side and FF queues sequentially, not merged.**

```solidity
// contracts/modules/DegenerusGameMintModule.sol:302-303
bool inFarFuture = (ticketLevel == (lvl | TICKET_FAR_FUTURE_BIT));
uint24 rk = inFarFuture ? _tqFarFutureKey(lvl) : _tqReadKey(lvl);
```

The function reads from `_tqReadKey(L)` (which is the swapped version of what was once `_tqWriteKey(L)`), then transitions to `_tqFarFutureKey(L)`. Each queue is processed against its own `ticketsOwedPacked[rk]` entries. No cross-contamination.

**Scenario trace: Level L transitions from far-future to near-future.**

| Time | currentLevel | L relative to window | Deposit target L goes to | Processing reads from |
|------|-------------|----------------------|--------------------------|-----------------------|
| T1 | 5 | L=15, far-future (15>11) | `_tqFarFutureKey(15)` = `15\|0x400000` | Not yet processed |
| T2 | 9 | L=15, near-future (15<=15) | `_tqWriteKey(15)` | `_prepareFutureTickets(9)` processes levels 11-15 |
| T3 | 9, after swap | Same | New deposits go to write key | `processFutureTicketBatch(15)` reads `_tqReadKey(15)` then `_tqFarFutureKey(15)` |

At T3, the T1 deposit (in FF key) and the T2 deposit (in write->read key after swap) are in separate queues. Both are processed. Neither is double-counted. A player who deposited at both T1 and T2 appears in both queues with independent owed counts, and gets both sets of tickets minted. This is correct -- they deposited twice and deserve both.

### EDGE-02: No Re-Processing After FF Key Drain

The argument rests on three facts:

**Fact 1: Monotonic level progression prevents new FF deposits to a drained level.**

The FF key for level L is drained by `processFutureTicketBatch` when `_prepareFutureTickets(currentLevel)` includes L in its range `[currentLevel+2, currentLevel+6]`. This requires `currentLevel >= L-6`. Since `level` only increases (set at line AdvanceModule:1340 and never decremented), once `level >= L-6`, it stays >= L-6 forever. Any future deposit to level L checks `L > level + 6`: since `level >= L-6`, we get `L <= level + 6`, so `isFarFuture = false`. New deposits go to `_tqWriteKey(L)`, not `_tqFarFutureKey(L)`.

**Fact 2: `delete ticketQueue[rk]` creates a clean slate.**

```solidity
// contracts/modules/DegenerusGameMintModule.sol:438
delete ticketQueue[rk];
```

Solidity `delete` on a dynamic array sets its length to 0 and clears all elements. Any subsequent `push` to `ticketQueue[ffk]` starts at index 0 with a fresh array. There is no leftover state from the old queue.

**Fact 3: `ticketsOwedPacked` is zeroed per-player during processing.**

During the batch processing loop (MintModule:351-431), every player is processed until `remainingOwed == 0`. At that point:
- `ticketsOwedPacked[rk][player]` = `(0 << 8) | 0` = 0 (set at line 420 via newPacked)
- `idx` advances past this player (line 428)

The skip path (lines 359-368) also zeros `ticketsOwedPacked` for players with `owed == 0 && rem == 0`. Queue deletion (`delete ticketQueue[rk]`) only happens when `idx >= total`, meaning every player has been fully processed and their owed state zeroed.

If a hypothetical new deposit to `_tqFarFutureKey(L)` were to occur (which Fact 1 proves cannot happen for already-drained levels), `_queueTickets` would find `ticketsOwedPacked[ffk][player] == 0`, push a new entry, and set fresh owed count. Processing would start from cursor 0 with the new queue. No old entries would be re-processed because the old queue array no longer exists.

### Key Interactions Between FF and Near-Future Queues

```
Level L lifecycle through ticket windows:

  currentLevel:  ...  L-7    L-6    L-5    L-4    L-3    L-2    L-1    L
                       |      |                                  |     |
                       v      v                                  v     v
                  FF deposit  L enters             L processed   L is  L played
                  target L    near-future          by _prepare   current
                  goes to     window               FutureTickets level
                  FF key      New deposits
                              go to write key
```

### Anti-Patterns to Avoid

- **Adding explicit "already processed" tracking:** Do not add a bitmap or mapping to track which FF keys have been processed. The combination of monotonic level progression and separate key spaces already prevents re-processing. Adding tracking would be dead code that complicates the storage layout.
- **Merging FF and write-key queues:** Do not try to merge the FF queue into the write buffer when a level enters the near-future window. The queues are in different key spaces by design, and `processFutureTicketBatch` already drains both sequentially.
- **Moving tickets between key spaces:** Do not implement a migration function that copies entries from `_tqFarFutureKey(L)` to `_tqWriteKey(L)`. This would be gas-expensive, bug-prone, and unnecessary since processing handles both queues.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Double-count prevention | Dedup check between queues | Separate key spaces (already done) | Routing ensures deposits go to exactly one key; no dedup needed |
| Re-processing prevention | Processed-level bitmap | Monotonic level + delete (already done) | Level progression guarantees no new FF deposits to drained levels |
| Queue cleanup after drain | Manual per-player cleanup | `delete ticketQueue[rk]` + per-player zeroing (already done) | Existing processing loop zeros owed counts; `delete` clears array |

## Common Pitfalls

### Pitfall 1: Confusing Key Spaces with Raw Levels
**What goes wrong:** Assuming `_tqFarFutureKey(L)` and `_tqWriteKey(L)` could somehow map to the same storage slot.
**Why it happens:** Without understanding the bit-22 vs bit-23 encoding, it seems like "level 15" is "level 15" everywhere.
**How to avoid:** Remember: `_tqFarFutureKey(15) = 15 | 0x400000`, `_tqWriteKey(15) = 15` or `15 | 0x800000`. These are different uint24 keys in the mapping. Phase 74 fuzz tests prove non-collision.
**Warning signs:** Test assertions that expect `ticketQueue[_tqFarFutureKey(L)].length` to change when deposits go to `_tqWriteKey(L)`.

### Pitfall 2: Assuming Level Can Decrease
**What goes wrong:** Worrying that after draining FF key for level L, the level might decrease below L-6, causing new FF deposits to the same level.
**Why it happens:** Not understanding the game's level progression is strictly monotonic.
**How to avoid:** `level` is set at AdvanceModule:1340 (`level = lvl` where `lvl = purchaseLevel = level + 1`). It only ever increases. There is no mechanism to decrease it.
**Warning signs:** Adding guards against "level regression" scenarios that cannot occur.

### Pitfall 3: Incomplete ticketsOwedPacked Cleanup
**What goes wrong:** If the processing loop doesn't zero `ticketsOwedPacked[rk][player]` for fully-processed players, then after `delete ticketQueue[rk]`, a new push of the same player would find `packed != 0` and NOT push them to the queue, silently dropping their tickets.
**Why it happens:** The `if (owed == 0 && rem == 0) { ticketQueue[wk].push(buyer); }` check in `_queueTickets` only pushes when the packed value is zero.
**How to avoid:** Verify that the processing loop (MintModule:351-431) always zeroes `ticketsOwedPacked[rk][player]` when a player is fully processed. Current code does this correctly: `newPacked = 0` when `remainingOwed == 0 && rem == 0`, and it's written at line 420.
**Warning signs:** `ticketsOwedPacked[ffk][player] != 0` after the FF queue has been deleted and all entries processed.

### Pitfall 4: Swap Timing and Read-Key Contents
**What goes wrong:** Assuming `_tqReadKey(L)` always has content when `_prepareFutureTickets` processes level L.
**Why it happens:** The double-buffer swap (`_swapTicketSlot`) is global, toggling `ticketWriteSlot`. After a swap, what was in `_tqWriteKey(L)` becomes `_tqReadKey(L)`. But if no deposits targeted level L during the current write window, the read-side queue for level L is empty.
**How to avoid:** The existing `processFutureTicketBatch` handles empty read-side queues correctly: if `total == 0`, it checks the FF queue and transitions if non-empty. Both EDGE-01 and EDGE-02 are handled regardless of whether the read-side queue has content.
**Warning signs:** Tests that assume `_tqReadKey(L)` must have entries for `processFutureTicketBatch` to work.

## Code Examples

### EDGE-01 Proof Trace

```solidity
// At currentLevel = 5, player opens lootbox targeting level 15:
// In _queueTickets:
bool isFarFuture = 15 > 5 + 6; // true (15 > 11)
uint24 wk = _tqFarFutureKey(15); // = 15 | 0x400000 = 0x40000F
ticketQueue[0x40000F].push(player); // entry in FF key space
ticketsOwedPacked[0x40000F][player] = (owed << 8); // tracked under FF key

// Later, at currentLevel = 10, same player opens lootbox targeting level 15:
// In _queueTickets:
bool isFarFuture = 15 > 10 + 6; // false (15 <= 16)
uint24 wk = _tqWriteKey(15); // = 15 (or 15 | 0x800000 depending on slot)
ticketQueue[wk].push(player); // entry in write key space (separate from FF)
ticketsOwedPacked[wk][player] = (owed << 8); // tracked under write key

// When _prepareFutureTickets(9) runs (processes levels 11-15):
// processFutureTicketBatch(15) reads _tqReadKey(15) first
//   -> processes write-buffer deposits (from when currentLevel was 10+)
// Then transitions to _tqFarFutureKey(15):
//   -> processes FF deposits (from when currentLevel was 5)
// Both deposits are minted. No double-counting.
```

### EDGE-02 Proof Trace

```solidity
// Level progression is monotonic:
// contracts/modules/DegenerusGameAdvanceModule.sol:1340
level = lvl; // lvl = purchaseLevel = level + 1; only increases

// After processFutureTicketBatch drains _tqFarFutureKey(15):
// currentLevel >= 9 (required for level 15 to be in the processing window)

// Can a new deposit go to _tqFarFutureKey(15)?
// In _queueTickets, new deposit for level 15:
bool isFarFuture = 15 > currentLevel + 6;
// Since currentLevel >= 9: 15 > 9 + 6 = 15 > 15 = false
// Since currentLevel only increases: always false going forward
// New deposit goes to _tqWriteKey(15), NOT _tqFarFutureKey(15)

// The drained FF queue (deleted via `delete ticketQueue[0x40000F]`)
// will never receive new entries because the routing condition
// `targetLevel > level + 6` is permanently false for this level.
```

### advanceGame Phase Transition (Vault Perpetual Tickets)

```solidity
// contracts/modules/DegenerusGameAdvanceModule.sol:1226-1231
uint24 targetLevel = purchaseLevel + 99;
_queueTickets(ContractAddresses.SDGNRS, targetLevel, VAULT_PERPETUAL_TICKETS);
_queueTickets(ContractAddresses.VAULT, targetLevel, VAULT_PERPETUAL_TICKETS);
```

These deposits target `purchaseLevel + 99`, which is always far-future (99 > 6). They go to `_tqFarFutureKey(purchaseLevel + 99)`. This is a DIFFERENT level than any level currently being processed. No interaction with the EDGE-01/EDGE-02 scenarios for level L.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Foundry (forge) + Hardhat |
| Config file | foundry.toml, hardhat.config.js |
| Quick run command | `npx hardhat compile` |
| Full suite command | `forge test && npx hardhat test` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| EDGE-01 | FF deposits and write-buffer deposits for same level are processed independently, no double-counting | unit | `forge test --match-test testEdge01NoDoubleCount -vv` | Wave 0 |
| EDGE-02 | After FF key drain, new deposits to same FF key start fresh queue (no re-processing) | unit | `forge test --match-test testEdge02NoReprocessing -vv` | Wave 0 |

### Sampling Rate
- **Per task commit:** `npx hardhat compile` (must succeed)
- **Per wave merge:** `forge test` (full Foundry suite)
- **Phase gate:** EDGE-01 and EDGE-02 tests pass + full suite green

### Wave 0 Gaps
- [ ] `test/fuzz/TicketEdgeCases.t.sol` -- harness and tests for EDGE-01/EDGE-02 scenarios
- [ ] Test: player deposits to FF key for level L at low currentLevel, then deposits to write key for same level L at higher currentLevel, then processing drains both independently with correct separate owed counts (EDGE-01)
- [ ] Test: FF key for level L is drained, queue deleted, then new deposit attempt shows it would go to write key (not FF key) because currentLevel has advanced (EDGE-02 routing proof)
- [ ] Test: after FF queue deletion, `ticketsOwedPacked[ffk][player]` is zero for all processed players (EDGE-02 cleanup proof)
- [ ] Test: `processFutureTicketBatch(L)` with non-empty FF key and empty read-side key correctly processes FF entries (common scenario for levels that were far-future and only received FF deposits)

Note: Integration-level testing (multi-level advancement with FF ticket lifecycle) is covered by TEST-05 in Phase 80.

## Open Questions

1. **Should this phase produce a formal proof document or code changes?**
   - What we know: Both EDGE-01 and EDGE-02 are satisfied by the existing implementation from Phases 74-76. No code changes are needed.
   - What's unclear: Whether the project owner wants a formal proof document, Foundry tests proving the edge cases, or both.
   - Recommendation: Produce both a proof document (explaining WHY the edge cases are safe with code references) AND Foundry tests (demonstrating the behavior concretely). The tests serve as executable proofs and regression guards.

2. **Should the tests live in a new file or extend TicketProcessingFF.t.sol?**
   - What we know: Phase 76 created `test/fuzz/TicketProcessingFF.t.sol` with 9 tests for PROC requirements. The EDGE tests cover related but distinct scenarios.
   - Recommendation: Create a new `test/fuzz/TicketEdgeCases.t.sol` for clarity. The EDGE tests exercise routing + processing interactions (cross-cutting Phase 75 and 76), while the existing file focuses on processing mechanics alone.

## Sources

### Primary (HIGH confidence)
- contracts/storage/DegenerusGameStorage.sol:537-565 -- `_queueTickets` routing logic with `isFarFuture` check and key selection
- contracts/storage/DegenerusGameStorage.sol:572-628 -- `_queueTicketsScaled` with identical routing pattern
- contracts/storage/DegenerusGameStorage.sol:631-668 -- `_queueTicketRange` with identical routing pattern
- contracts/storage/DegenerusGameStorage.sol:714-731 -- `_tqWriteKey`, `_tqReadKey`, `_tqFarFutureKey` key encoding (three disjoint key spaces)
- contracts/storage/DegenerusGameStorage.sol:162 -- `TICKET_FAR_FUTURE_BIT = 1 << 22`
- contracts/modules/DegenerusGameMintModule.sol:298-454 -- `processFutureTicketBatch` with dual-queue drain (Phase 76 implementation)
- contracts/modules/DegenerusGameAdvanceModule.sol:1156-1185 -- `_prepareFutureTickets` with FF-bit stripping (Phase 76 fix)
- contracts/modules/DegenerusGameAdvanceModule.sol:1340 -- `level = lvl` (monotonic increment, never decrements)
- contracts/modules/DegenerusGameAdvanceModule.sol:1222-1243 -- `_processPhaseTransition` vault perpetual tickets (purchaseLevel+99, always far-future, different level)
- .planning/phases/76-ticket-processing-extension/76-RESEARCH.md -- Phase 76 research documenting dual-queue drain architecture
- .planning/phases/76-ticket-processing-extension/76-01-SUMMARY.md -- Phase 76 completed implementation

## Metadata

**Confidence breakdown:**
- EDGE-01 (no double-counting): HIGH -- proven by structural analysis of three disjoint key spaces, separate `ticketsOwedPacked` tracking, and sequential (not merged) processing in `processFutureTicketBatch`
- EDGE-02 (no re-processing): HIGH -- proven by monotonic level progression preventing new FF deposits to drained levels, combined with `delete ticketQueue[rk]` clearing the array and per-player `ticketsOwedPacked` zeroing during processing
- Implementation approach: HIGH -- no code changes needed; both edge cases are satisfied by existing architecture; phase deliverable is proof + tests

**Research date:** 2026-03-22
**Valid until:** Indefinite (structural correctness argument; valid as long as key encoding, routing logic, and monotonic level progression remain unchanged)
