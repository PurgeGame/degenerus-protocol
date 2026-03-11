# Pitfalls Research

**Domain:** On-chain game contract — adding double-buffer queues, prize pool freeze/unfreeze, and packed storage to an existing delegatecall-module system
**Researched:** 2026-03-11
**Confidence:** HIGH — derived directly from contract source, implementation plan, and established Solidity storage patterns

---

## Critical Pitfalls

### Pitfall 1: Storage Collision via Slot 1 Byte Overflow

**What goes wrong:**
Slot 1 currently uses 18 bytes with 14 bytes of padding. The plan adds `ticketWriteSlot` (uint8), `ticketsFullyProcessed` (bool), and `prizePoolFrozen` (bool) — 3 bytes total, consuming bytes 18–20. If any existing or future variable is accidentally inserted _between_ `purchaseStartDay` (bytes 12–18) and the new fields, or if `purchaseStartDay` is ever widened, the new flags shift to a new slot number. Every delegatecall module inherits this layout and will read from the wrong bytes.

**Why it happens:**
Slot 1 is a dense pack of heterogeneous types. Developers editing the storage file may insert variables alphabetically or near "related" variables rather than strictly at the end of the packed region. A single out-of-order insertion causes all downstream bytes to shift by one slot in the _module_ compilation units, which compile against the same source but cache abi-encoding independently.

**How to avoid:**
- Add the three new fields _immediately after_ `purchaseStartDay` (line ~280 in storage file) with an explicit byte-offset comment matching the slot diagram.
- Update the slot diagram comment in the file header to show `[18:19]`, `[19:20]`, `[20:21]` and the revised padding `[21:32]`.
- Run `forge inspect DegenerusGameStorage storage-layout` and diff it against the expected slot layout before any test run.
- Add a Foundry test that reads `ticketWriteSlot`, `ticketsFullyProcessed`, and `prizePoolFrozen` from a raw `vm.load` slot-1 offset and asserts expected packing.

**Warning signs:**
- `forge inspect` shows `ticketWriteSlot` on a slot other than 1.
- A unit test for the new flags passes but a delegatecall-path integration test produces wrong values for _existing_ Slot 1 flags (`jackpotCounter`, `rngLockedFlag`, etc.).
- Gas costs for reading Slot 1 fields jump from ~2100 (warm) to ~2100 × N (cold) — indicates multiple separate slots.

**Phase to address:** Storage Changes phase (first implementation phase, before any module is touched).

---

### Pitfall 2: Module Compiled Against Stale Storage Layout

**What goes wrong:**
Delegatecall modules (`JackpotModule`, `MintModule`, `AdvanceModule`, `EndgameModule`) each compile `DegenerusGameStorage` into their own bytecode. If a module is compiled _before_ the storage file is fully updated — e.g., during a partial commit — it encodes the old slot offsets. Calling it via `delegatecall` reads/writes the wrong storage positions in `DegenerusGame`'s state. The main contract and the module silently diverge.

**Why it happens:**
Foundry and Hardhat cache compilation artifacts per contract. A developer who rebuilds only the main contract after editing the storage file will have a stale module artifact. This is particularly dangerous with `_tqReadKey`/`_tqWriteKey` — if `MintModule` encodes the old `ticketQueue[level]` write path while `JackpotModule` uses the new `_tqReadKey` path, purchases land in one mapping slot and processing reads from another. Both succeed silently; tickets are simply never processed.

**How to avoid:**
- Always `forge clean` before compiling after any storage layout change.
- In CI, run `forge clean && forge build` — never incremental builds when storage layout is being modified.
- Pin a `forge snapshot` of gas costs for key functions; a regression in gas for `processTicketBatch` is a strong signal the module compiled against different storage.

**Warning signs:**
- `ticketQueue[rk].length` is always 0 after purchases, even though purchases confirmed via events.
- `_swapTicketSlot` never reverts `ReadSlotNotDrained` even when tickets are demonstrably pending (both sides of the swap are pointing at different mapping keys).
- Integration test: buy tickets, advance game, assert `traitBurnTicket` populated — this assertion fails without error in the ticket-processing loop.

**Phase to address:** Storage Changes phase, with a mandatory clean-build CI gate before module integration begins.

---

### Pitfall 3: _tqReadKey / _tqWriteKey Inversion Bug

**What goes wrong:**
`_tqWriteKey` returns `level | TICKET_SLOT_BIT` when `ticketWriteSlot == 1`. `_tqReadKey` must return the _opposite_ — `level` when `ticketWriteSlot == 1`. An off-by-one error in the ternary, or a copy-paste that uses `ticketWriteSlot != 0` for both functions, causes reads and writes to target the _same_ slot. Purchases add to the slot that processing also reads from. The "write slot fills while read slot processes" invariant collapses entirely.

**Why it happens:**
The two helper functions are mirror images. The natural mistake is to write `_tqReadKey` as `ticketWriteSlot != 0 ? level | TICKET_SLOT_BIT : level` (same as `_tqWriteKey`) instead of `ticketWriteSlot == 0 ? level | TICKET_SLOT_BIT : level`.

**How to avoid:**
- Write a unit test that: sets `ticketWriteSlot = 0`, asserts `_tqWriteKey(5) == 5` and `_tqReadKey(5) == 5 | TICKET_SLOT_BIT`. Then flip to `ticketWriteSlot = 1`, assert `_tqWriteKey(5) == 5 | TICKET_SLOT_BIT` and `_tqReadKey(5) == 5`.
- Add an invariant assertion: `_tqWriteKey(level) != _tqReadKey(level)` — they must never be equal for any level.
- Review the `^= 1` XOR swap logic: after `_swapTicketSlot`, what was the write slot becomes the read slot. Trace through manually once.

**Warning signs:**
- `_swapTicketSlot` reverts `ReadSlotNotDrained` immediately after a normal processing cycle that visibly completed (length appeared to go to 0).
- Ticket count discrepancies between "queued" events and "processed" events for the same player/level.

**Phase to address:** Queue Double-Buffer implementation phase, in the first test written for the feature.

---

### Pitfall 4: uint128 Truncation in Packed Prize Pool Helpers

**What goes wrong:**
Every call site that writes to `prizePoolsPacked` must cast individual amounts to `uint128` before the shift-or pack. A missing cast — e.g., `next += nextShare` where `nextShare` is `uint256` — will compile without warning in Solidity 0.8 _if_ the addition is done in `uint256` space and then assigned to `uint128 next`. The assignment truncates silently. The packed value is wrong and the discarded bits are lost forever. This is most dangerous in `consolidatePrizePools` and `payDailyJackpot`, which move large amounts between pools.

**Why it happens:**
Porting from `uint256 nextPrizePool` to `uint128 next` requires explicit casts everywhere. Solidity does not warn on narrowing implicit casts in assignments (only in function arguments for certain versions). A developer porting line-by-line may miss a `uint256` local or a function return value that feeds into the `uint128` accumulation.

**How to avoid:**
- Declare locals explicitly: `uint128 next` — this makes any `uint256` right-hand side a compiler error.
- Add a Foundry fuzz test for `_setPrizePools` / `_getPrizePools` round-trip: `forAll uint128 a, uint128 b → _setPrizePools(a,b); (x,y) = _getPrizePools(); assert x==a && y==b`.
- For every function migrated, add a post-condition assertion in a test: after the function, `(next, future) = _getPrizePools()` and compare against separately-calculated expected values with explicit `uint128` arithmetic.
- Grep the codebase after implementation: `nextPrizePool` and `futurePrizePool` should appear _zero_ times outside comments after migration.

**Warning signs:**
- Prize pool values drift downward over time in simulation tests, especially after high-value jackpot operations.
- `consolidatePrizePools` produces a `nextPrizePool` smaller than either input pool.
- Fuzz tests with large values (> 1e18) fail sporadically.

**Phase to address:** Packed Storage implementation phase. Each migrated function needs its own round-trip test before moving to the next.

---

### Pitfall 5: Freeze Flag Not Checked in All Purchase-Revenue Paths

**What goes wrong:**
The plan enumerates specific callsites that must branch on `prizePoolFrozen`. If any callsite is missed — a secondary purchase path, a bonus award, a referral kickback, a degenerette payout — then during freeze those amounts write directly to live pools, defeating the isolation guarantee. Jackpot payouts sized against the "frozen" pool actually pay out against a pool that has grown from concurrent purchases.

**Why it happens:**
The codebase has many purchase paths spread across five modules (`DegenerusGame.sol`, `MintModule`, `WhaleModule`, `DegeneretteModule`, and the ETH fallback). Any path that adds to `nextPrizePool` or `futurePrizePool` is in scope. During porting, a less-traveled path (e.g., auto-rebuy ticket credit, decimator lootbox pool split) can be overlooked.

**How to avoid:**
- After removing `nextPrizePool`/`futurePrizePool` as standalone variables, run `forge build`. Any remaining reference is a compile error — use this as an automatic completeness check.
- Write an integration test: freeze the pool, then exercise every single purchase path (regular ticket, lootbox, whale bundle, degenerette, ETH fallback, auto-rebuy), assert that live pools are unchanged and pending accumulators grew by the expected amounts.
- Grep for `_setPrizePools` call sites and cross-check against the plan's table of affected locations.

**Warning signs:**
- During jackpot phase integration tests, `nextPrizePool` grows during freeze even with no explicit calls to pool-modifying game logic.
- `prizePoolPendingPacked` stays 0 despite ETH flowing through purchase paths during freeze.

**Phase to address:** Freeze/Unfreeze implementation phase. The integration test covering all purchase paths is the acceptance criterion for this phase.

---

### Pitfall 6: Unfreeze Called at Wrong Point in advanceGame — Pending Lost or Double-Applied

**What goes wrong:**
`_unfreezePool()` must be called at exactly three points: (1) daily purchase-phase processing complete, (2) jackpot phase `_endPhase()`, and (3) phase-transition completion. Calling it early — e.g., before `_endPhase` finishes its pool logic — applies pending accumulators to live pools while jackpot payout calculations are still in progress, inflating the payout. Calling it at the wrong `jackpotPhaseFlag` transition point (e.g., after `jackpotPhaseFlag = false` but before verifying `ticketsFullyProcessed`) can cause pending amounts to be applied with partial state.

A different failure: if the plan places `_unfreezePool()` _inside_ a `do { } while(false)` branch that can `break` early, a `break` path that bypasses the call leaves the freeze permanently active. All subsequent purchases accumulate in pending indefinitely, and live pools never grow again.

**Why it happens:**
The `advanceGame` flow uses a `do { } while(false)` with multiple `break` exits. Each `break` is a potential bypass of any code placed after it. The correct approach (in the plan) is to call `_unfreezePool` at each specific `break` site where the condition is met, not after the loop.

**How to avoid:**
- Map every `break` in the revised `advanceGame` and confirm that no break path can exit with `prizePoolFrozen == true` unless it is expected to remain frozen (i.e., mid-jackpot-phase breaks).
- Write a state-machine test: starting from freeze-active state, simulate all break paths and assert `prizePoolFrozen` is `false` only when expected, `true` when expected.
- `_unfreezePool` is idempotent (it guards `if (!prizePoolFrozen) return`) — prefer calling it _too many_ times in questionable paths rather than missing it.

**Warning signs:**
- After a full purchase-day cycle, `prizePoolFrozen` is still `true` in storage.
- Pending accumulators (`prizePoolPendingPacked`) are non-zero after unfreeze should have cleared them.
- Live prize pools are lower than expected by exactly the amount in pending.

**Phase to address:** advanceGame Rewrite phase, specifically the unfreeze placement review.

---

### Pitfall 7: Hard Gate Check Uses Wrong Level — _swapTicketSlot Reverts Spuriously

**What goes wrong:**
`_swapTicketSlot(purchaseLevel)` checks `ticketQueue[_tqReadKey(purchaseLevel)].length != 0` and reverts with `ReadSlotNotDrained`. If `purchaseLevel` passed to the function differs from the level used during processing, the gate checks the wrong mapping key. Example: processing used `ticketLevel` (the cursor-tracked level) but the swap is called with `level` (the global current level). The read key resolves to a different array, which may be empty even while the actual read queue for `ticketLevel` is not drained.

**Why it happens:**
The codebase has both `level` (global game level) and `ticketLevel` (processing cursor level). They can diverge when processing spans multiple levels. The gate must check every level currently being processed, or the system must guarantee that only one level is processed at a time per swap cycle. If the swap function only checks a single key (the `purchaseLevel` parameter), and processing is spread across multiple levels with tickets, the gate is under-checking.

**How to avoid:**
- Confirm in the plan: is the double-buffer keyed by a single `purchaseLevel` (current game level), or by every level in the queue? The plan's `_swapTicketSlot` checks only `_tqReadKey(purchaseLevel)`. This is correct _only_ if the drain gate is checked for every active level before calling swap. Verify this coverage in `advanceGame`.
- Write a test where two different levels have read-slot tickets, call `_swapTicketSlot` — it should revert.
- If multi-level drain is possible in a single call, the gate must iterate all non-empty read keys or keep a count of in-flight levels.

**Warning signs:**
- `ReadSlotNotDrained` revert in a path that was expected to succeed.
- Tickets for level N+1 are present in the read slot but the swap fires because only level N was checked.

**Phase to address:** Queue Double-Buffer phase. Gate coverage is part of the `_swapTicketSlot` unit tests.

---

### Pitfall 8: Constructor Tickets Written to Wrong Slot After Swap

**What goes wrong:**
Constructor tickets are written at deploy time with `ticketWriteSlot == 0`, so they land in raw-level keys (slot 0). The first `_swapTicketSlot` call flips `ticketWriteSlot` to 1, making the read slot = slot 0. Constructor tickets are now on the read side — correct. But if the constructor calls a `_queueTickets*` function _after_ storage is initialized with a non-zero `ticketWriteSlot` (which cannot happen in the current plan but could happen in a test setup that pre-sets `ticketWriteSlot`), constructor tickets land in the wrong slot and are never processed unless a swap moves them to the read side.

More concretely: any test that initializes state with `ticketWriteSlot = 1` and then calls a queueing function to simulate "pre-existing tickets" must use `_tqWriteKey(level)` internally. If the test sets up tickets by writing directly to `ticketQueue[level]` (the raw key) without accounting for the current write slot, it places tickets on the _read_ side of the buffer, and they will be processed immediately (correct behavior in the happy path), or it places them on the wrong side entirely, depending on the current slot.

**Why it happens:**
Test setup code often directly manipulates storage via `vm.store` or direct mappings without going through the abstracted helper functions. When the buffer bit is in play, direct manipulation must be slot-aware.

**How to avoid:**
- All test fixtures that seed the ticket queue must call `_queueTickets*` through the contract interface (or through storage helpers that respect `ticketWriteSlot`), never write `ticketQueue[rawLevel]` directly.
- Write a specific test: fresh deploy, queue tickets (slot 0), call swap (slot 0 becomes read), advance game and process — assert all constructor tickets processed. Then repeat: queue more tickets (now slot 1 is write), swap again (slot 1 becomes read, slot 0 is write), assert second batch processed.

**Warning signs:**
- Constructor-seeded tickets never appear in `traitBurnTicket` after processing.
- Tests that pass individually fail in sequence because earlier tests left `ticketWriteSlot` in a non-default state.

**Phase to address:** Queue Double-Buffer phase, in the constructor-ticket edge case test.

---

### Pitfall 9: Reentrancy via ETH Transfer During Unfreeze

**What goes wrong:**
`_unfreezePool` merges pending accumulators into live pools. If any ETH transfer occurs between the time `prizePoolFrozen = true` and `_unfreezePool()` being called — specifically, if a player triggers a `claim` that sends ETH while freeze is active — the claimed amount was sized against the pre-freeze live pool. After unfreeze, the live pool is larger (pending applied), but the claim amount was already committed. This is not directly a reentrancy — the pull pattern prevents it — but a subtler form: the `claimablePool` accounting must correctly separate "ETH owed from jackpot at freeze time" from "pending purchase revenue being merged."

A true reentrancy risk emerges if `_unfreezePool` is preceded by an ETH send in the same call and there is no nonReentrant guard. Any external call before `prizePoolFrozen = false` could re-enter a purchase path that checks `prizePoolFrozen` and routes to pending, then when the outer call sets `prizePoolFrozen = false` the pending amount accumulated during the re-entrant call is not merged (because the reentrant call set pending before the outer call zeroed it).

**Why it happens:**
Multi-step settlement functions (advanceGame payouts) combine multiple state mutations. In complex flows like `_endPhase` + `_unfreezePool`, a developer might insert an ETH send (claim credit) between pool mutations, not realizing the interaction between freeze state and the ETH transfer callback window.

**How to avoid:**
- Check-effects-interactions: all state mutations (`_unfreezePool`, pool credits) before any ETH send.
- Verify that `_unfreezePool` has no external calls inside it — it reads/writes storage only.
- If `advanceGame` sends ETH to bounty recipients, ensure that happens _after_ `_unfreezePool` in the call flow.
- Add a test with a mock reentrancy attacker that attempts to re-enter via the ETH send in advance game — assert the reentrancy guard (if present) fires or the state machine prevents it.

**Warning signs:**
- Pending accumulator values are inconsistent after a full jackpot phase with active players claiming mid-phase.
- `claimablePool` drops below the sum of `claimableWinnings` mappings after unfreeze.

**Phase to address:** Freeze/Unfreeze phase and advanceGame Rewrite phase. Combined review of call ordering in `_endPhase` and `_processPhaseTransition`.

---

### Pitfall 10: ticketsFullyProcessed Reset Missing After Mid-Day Swap

**What goes wrong:**
`_swapTicketSlot` sets `ticketsFullyProcessed = false`. If a mid-day swap is triggered with `ticketsFullyProcessed == true` (read slot was already drained from a previous cycle), the flag must reset so the daily path will process the freshly-swapped read slot. If the mid-day path somehow calls `_swapTicketSlot` but then the daily path checks `ticketsFullyProcessed == true` and skips processing, the freshly-swapped tickets are never processed. The read slot grows unboundedly; the next swap hits `ReadSlotNotDrained`.

**Why it happens:**
`ticketsFullyProcessed` has dual responsibility: flow-control gate in the daily path and internal state. The mid-day path does not always use `ticketsFullyProcessed` as a gate (it only checks queue length directly). It is easy to miss the flag reset on a mid-day path code branch.

**How to avoid:**
- `_swapTicketSlot` unconditionally sets `ticketsFullyProcessed = false`. This means the reset is inside the function, not in the caller. Verify the implementation matches — callers must not set it to `true` before the daily processing loop runs.
- Write a test: mid-day swap fires with `ticketsFullyProcessed == true`, assert that after swap `ticketsFullyProcessed == false`, assert the subsequent daily path processes the newly-read tickets.

**Warning signs:**
- After a mid-day swap, the daily path jumps straight to jackpot logic without processing any tickets.
- `traitBurnTicket` does not reflect purchases made between the mid-day swap and the next daily advance.

**Phase to address:** advanceGame Rewrite phase, mid-day path section.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Skip updating slot diagram comment in storage file | Saves 10 minutes | Diagram drifts from reality, future developers miscount bytes, introduce collision | Never — the comment IS the spec for delegatecall safety |
| Use `uint256` locals throughout migrated functions instead of `uint128` | Fewer casts to write | Truncation bugs silently drop ETH; harder to reason about overflow | Never for pool-touching functions |
| Single test covering the full freeze/unfreeze cycle instead of per-path tests | Faster to write | Any single path regression is masked; unclear which path broke | Only acceptable as a _final_ integration smoke test after all unit tests exist |
| Leave `rngLockedFlag` writes in place "just in case" while removing the purchase revert | Rollback safety | Flag remains set indefinitely in new flow, future code reads stale flag, behavior diverges | Never — the flag is removed as part of this milestone; dead state is dangerous |
| Check only `purchaseLevel` in `_swapTicketSlot` hard gate | Simple | Multi-level queue scenarios escape the gate | Never if multiple levels can be in the read slot simultaneously |

---

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| VRF callback + freeze flag | VRF callback fires during freeze; callback writes `rngWordCurrent` and triggers `advanceGame`-equivalent logic that touches live pools | VRF callback only sets `rngWordCurrent` — no pool logic. Pool logic runs in `advanceGame` after `rngGate` returns the word. Verify the callback does not branch on `prizePoolFrozen`. |
| `ticketCursor` reset across swap boundary | `ticketCursor` tracks position within the current read queue. After a swap, it must reset to 0 for the new read slot. If the swap does not reset `ticketCursor`, processing of the new read slot starts mid-array, skipping entries. | `ticketsFullyProcessed = false` resets the flag; the processing loop must also reset `ticketCursor` to 0 when it detects a new queue to process. Verify `ticketCursor` is 0 at swap time. |
| `processFutureTicketBatch` in MintModule | Future ticket processing uses its own read path. After the double-buffer migration, if `processFutureTicketBatch` still reads `ticketQueue[level]` directly (old path), it processes the wrong slot during periods when write slot = 1. | Migrate `processFutureTicketBatch` to `_tqReadKey(level)` as specified in the plan. Add a targeted test that future tickets queued on write slot 1 are processed correctly. |
| `_processPhaseTransition` perpetual vault tickets | Perpetual vault tickets are written during phase transition. At this point, `ticketWriteSlot` may be 0 or 1. The write must use `_tqWriteKey`, not the raw level. If write uses raw level and write slot is 1, the tickets land on the read side and are processed in the current cycle instead of the next. | Plan already specifies `_processPhaseTransition` uses write key. Confirm in implementation. |
| Packed `prizePoolsPacked` vs old `nextPrizePool`/`futurePrizePool` storage slots | Old slots (around line 308, 409) occupied specific slot numbers. The new `prizePoolsPacked` occupies a different slot number. Any code that calculates slot numbers manually (e.g., in tests using `vm.load`) will read garbage. | Never use hardcoded slot numbers. Use `forge inspect` to get slot numbers after each build. Update test helpers accordingly. |

---

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Loading `prizePoolsPacked` inside a loop | Gas cost scales with loop iterations instead of being O(1) | Load once at function entry, work with locals, store once at exit — plan already specifies this pattern | Any function with >1 iteration that reads pools; worst case: a multi-winner jackpot loop |
| `ticketQueue[rk].length` SLOAD in the hard gate being called on a hot path | ~2100 gas per check even when queue is obviously empty | Gate is only called at swap time, not per-purchase; this is acceptable | Not a trap in the current design — `_swapTicketSlot` is called once per day or mid-day |
| Pending accumulator SLOAD/SSTORE on every purchase during freeze | 2× SSTORE cost per purchase during freeze period | Already designed as a single packed slot (both pending pools in one word); acceptable | Only problematic if the packed slot is split; do not split `prizePoolPendingPacked` |
| `_queueTicketRange` writing to all levels in a whale bundle during freeze | Each level write hits the pending branch; no additional cost vs non-freeze path — correct | Already handled; each level write uses the same SLOAD/SSTORE pattern via `_tqWriteKey` | Not a trap — cost is per-level regardless |

---

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Allowing `_swapAndFreeze` to be called from outside `advanceGame` | Attacker can force-freeze prize pools, redirecting all purchases to pending indefinitely | `_swapAndFreeze` is `internal` and called only from the daily path of `advanceGame`. Verify no `public` or `external` wrapper exists. |
| Setting `prizePoolFrozen = false` without calling `_unfreezePool` | Pending accumulator ETH is silently lost — pooled purchases during freeze vanish | `prizePoolFrozen` must only be set to `false` inside `_unfreezePool`. Never write it directly at call sites. Add a comment on the variable: "only `_unfreezePool` may clear this". |
| `_swapTicketSlot` callable without drain gate from a new mid-day entry point | Tickets in read slot are overwritten/orphaned when write slot becomes read slot with non-zero data | Hard gate is inside `_swapTicketSlot` itself (reverts). This defense is in-function. Do not add bypass paths. |
| Not resetting `prizePoolPendingPacked = 0` during freeze activation if already frozen | Second freeze call (jackpot-phase daily re-entry) resets accumulators to 0, discarding pending from earlier in the same jackpot phase | `_swapAndFreeze` has `if (!prizePoolFrozen)` guard before zeroing. Already in the plan. Verify this guard is preserved in implementation. |
| Arithmetic on `uint128` local exceeding `type(uint128).max` | Silent truncation losing ETH | Use checked arithmetic (Solidity 0.8 default, no `unchecked` block around pool additions). Max 3.4e20 ETH is unreachable, but truncation during intermediate overflow is possible in unchecked blocks. |

---

## "Looks Done But Isn't" Checklist

- [ ] **Slot 1 diagram updated:** `forge inspect DegenerusGameStorage storage-layout` matches the header comment byte-by-byte for all three new fields.
- [ ] **All purchase paths migrated:** `grep -r "nextPrizePool\|futurePrizePool" contracts/` returns 0 results outside comments.
- [ ] **All queue writes use write key:** `grep -r "ticketQueue\[" contracts/` — every write site uses `_tqWriteKey`; every read site uses `_tqReadKey`. No direct `ticketQueue[level]` access in migrated code.
- [ ] **Freeze branch present in all purchase paths:** Exercise every purchase function during active freeze in integration test — pending accumulators grow, live pools do not.
- [ ] **Unfreeze called at all three exit points:** After purchase-daily complete, after `_endPhase`, after `_processPhaseTransition`. Verify in code, not just in plan.
- [ ] **`rngLockedFlag` purchase reverts removed:** The two `revert E()` lines in MintModule are gone. No other purchase-blocking checks were unintentionally removed.
- [ ] **Constructor ticket processing tested:** Full cycle from deploy → queue → first swap → process → assert tickets processed.
- [ ] **Jackpot phase 5-day freeze persistence tested:** Simulate all 5 jackpot days; assert freeze persists between days and is released only after `_endPhase`.
- [ ] **`ticketCursor` reset after swap:** After mid-day swap, `ticketCursor` is 0 before first processing call.
- [ ] **`processFutureTicketBatch` uses read key:** Integration test — queue future tickets, swap, advance game, assert processed.

---

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Storage slot collision discovered post-deploy | HIGH | No upgrade path; requires new deploy and state migration. Full loss of current game state unless migration script is written. Fresh deploy assumed per project constraints. |
| Freeze never unfreezes (bug in unfreeze call site) | HIGH | Pending ETH is locked until a fix is deployed. Short-term: admin function to force-unfreeze (if admin role exists). Long-term: new deploy. |
| uint128 truncation causes prize pool drain | HIGH | ETH is irrecoverably lost from the pool. Mitigation: monitor pool balances off-chain and alert on unexpected drops. Recovery requires new deploy with corrected accounting. |
| Wrong key used in queue write, tickets lost | MEDIUM | Tickets are in an orphaned mapping slot. No player impact until processing cycle. Can be recovered with an admin migration function that reads orphaned keys and re-queues. Cost: gas for migration. |
| `ticketsFullyProcessed` stuck `true` after swap | LOW | Next advance game call will check queue length, see non-zero, and set flag false before proceeding. The flag is self-correcting IF the daily path's drain check uses queue length as primary signal (plan specifies this). |
| `rngLockedFlag` left as dead state after migration | LOW | Flag is `false` by default after processing completes; leftover `true` value causes issues only if other code still reads it. Audit all remaining reads of `rngLockedFlag` after migration and remove. |

---

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| Storage Collision — Slot 1 byte overflow | Storage Changes (Phase 1) | `forge inspect` slot layout diff; Slot 1 byte-offset unit test |
| Module compiled against stale layout | Storage Changes (Phase 1, CI gate) | Mandatory `forge clean` in CI; module integration test reads all Slot 1 fields via delegatecall |
| _tqReadKey/_tqWriteKey inversion | Queue Double-Buffer (Phase 2) | Unit test asserting read != write key for all slot states |
| uint128 truncation in packed helpers | Packed Storage (Phase 3) | Fuzz test round-trips; post-condition assertions on all migrated functions |
| Freeze branch missing in a purchase path | Freeze/Unfreeze (Phase 4) | Integration test exercising all purchase paths under freeze |
| Unfreeze at wrong advanceGame point | advanceGame Rewrite (Phase 5) | State-machine test: all break-path exits assert correct freeze state |
| Hard gate checks wrong level | Queue Double-Buffer (Phase 2) | Multi-level drain test; swap-with-non-empty-other-level test |
| Constructor ticket slot mismatch | Queue Double-Buffer (Phase 2) | Constructor-ticket round-trip test |
| Reentrancy window around unfreeze | Freeze/Unfreeze + advanceGame Rewrite | Mock reentrancy test; check-effects-interactions review |
| ticketsFullyProcessed reset missing | advanceGame Rewrite (Phase 5) | Mid-day swap test asserting flag reset |

---

## Sources

- Contract source: `contracts/storage/DegenerusGameStorage.sol` (direct inspection, HIGH confidence)
- Implementation plan: `audit/PLAN-ALWAYS-OPEN-PURCHASES.md` (direct inspection, HIGH confidence)
- Project context: `.planning/PROJECT.md` (direct inspection, HIGH confidence)
- EVM storage packing rules: Solidity 0.8 documentation — packed variables fill from low byte to high byte within a slot; types are packed in declaration order (HIGH confidence, stable spec)
- Delegatecall storage collision: Known class of vulnerability; documented in OpenZeppelin proxy upgrade guides and Ethereum storage layout specifications (HIGH confidence)
- uint128 truncation: Solidity 0.8 type narrowing behavior — implicit narrowing in assignment is a compile error for function args but not always for local assignment depending on context; explicit cast required (MEDIUM confidence — version-specific behavior; verify with actual compile test)

---
*Pitfalls research for: Degenerus Protocol — Always-Open Purchases milestone*
*Researched: 2026-03-11*
