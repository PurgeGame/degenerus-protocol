# Phase 79: RNG Commitment Window Proof - Research

**Researched:** 2026-03-22
**Domain:** VRF commitment window analysis for far-future coin jackpot (Solidity smart contract audit)
**Confidence:** HIGH

## Summary

Phase 79 requires a formal proof that the new far-future key space introduced in v3.9 Phases 74-77 is safe under VRF commitment window analysis. The core question: can any permissionless action modify the population of players eligible for a far-future coin jackpot draw between the time the VRF random word is requested and the time it is consumed to select a winner?

The v3.8 commitment window audit (Phases 68-72) established the methodology: forward-trace all variables touched by VRF fulfillment, backward-trace from every outcome to all inputs, then enumerate every permissionless mutation path for each input and assign SAFE/UNSAFE verdicts. Phase 79 applies this same methodology but scoped specifically to the new `_awardFarFutureCoinJackpot` function and its two data sources: `ticketQueue[_tqReadKey(candidate)]` and `ticketQueue[_tqFarFutureKey(candidate)]`.

The research confirms that three independent protection layers exist: (1) the double-buffer swap freezes the read buffer at RNG request time, (2) the `rngLockedFlag` guard in `_queueTickets`/`_queueTicketsScaled`/`_queueTicketRange` blocks all permissionless far-future ticket writes during the commitment window, and (3) the `phaseTransitionActive` exemption only allows `advanceGame`-origin writes which are deterministic and occur in the same transaction as the jackpot draw. The proof should enumerate every mutation path, verify each protection, and issue verdicts.

**Primary recommendation:** Structure the proof as a single audit document following v3.8 methodology: backward-trace from `_awardFarFutureCoinJackpot` outcome to all inputs, enumerate every permissionless mutation path for each input, and assign SAFE verdicts with source-line evidence. No code changes are expected.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| RNG-01 | No permissionless action during the VRF commitment window can influence which player wins a far-future coin jackpot draw -- the FF key is either frozen, guarded, or proven irrelevant to outcome selection when the RNG word is consumed | Three protection layers identified: (1) double-buffer swap freezes read buffer, (2) rngLockedFlag guard blocks FF writes, (3) phaseTransitionActive exemption is deterministic. All permissionless mutation paths enumerated from v3.8 inventory. Proof methodology defined below. |
</phase_requirements>

## Architecture Patterns

### v3.8 Commitment Window Audit Methodology (Prior Art)

The v3.8 audit (audit/v3.8-commitment-window-inventory.md) established a three-step methodology:

**Step 1 -- Forward Trace (CW-01):** Catalog every storage variable read or written during VRF fulfillment and all downstream processing, starting from `rawFulfillRandomWords`. Records slot numbers, types, purpose, R/W, and function chain.

**Step 2 -- Backward Trace (CW-02):** Trace BACKWARD from each player-visible outcome to every input variable that influenced the result. This is independently derived from outcome computation code -- not a reshuffling of forward-trace rows. The key question: "Was this word guaranteed unknown at the time the inputs being resolved were committed?"

**Step 3 -- Mutation Surface Catalog (CW-03):** For each cataloged variable, enumerate every external/public function that can write it. Record call-graph depth (D0-D3+), access control (permissionless, admin-only, game-only, VRF-only), and protection mechanisms.

**Step 4 -- Verdicts:** For each permissionless mutation path, assign SAFE/UNSAFE with reasoning.

### Phase 79 Scoped Application

Phase 79 applies this methodology to a specific scope:

**Outcome:** Far-future coin jackpot winner selection (which address receives BURNIE from the 25% far-future portion of the daily coin jackpot).

**Outcome computation location:** `DegenerusGameJackpotModule.sol` lines 2522-2614, function `_awardFarFutureCoinJackpot`.

**Two callers:**
1. `payDailyJackpotCoinAndTickets` (JM:707) -- called from advanceGame jackpot phase via delegatecall
2. `payDailyCoinJackpot` (JM:2370) -- called from advanceGame purchase phase via delegatecall

Both callers pass `randWord` which is the VRF word from `rngGate` (AdvanceModule:798), consumed during `advanceGame`. Both are called ONLY during the daily advanceGame flow where `rngLockedFlag = true`.

### Backward Trace for _awardFarFutureCoinJackpot

The winner selection depends on these inputs:

```
Winner address
  <- readQueue[idx] OR ffQueue[idx - readLen]              [JM:2553-2555]
    <- idx = (entropy >> 32) % combinedLen                  [JM:2552]
      <- entropy = entropyStep(prevEntropy ^ s)             [JM:2539]
        <- rngWord ^ (lvl << 192) ^ FAR_FUTURE_COIN_TAG    [JM:2529-2531]
          <- rngWord from advanceGame (VRF word)
          <- lvl (current level, parameter)
      <- combinedLen = readLen + ffLen                      [JM:2549]
        <- readLen = ticketQueue[_tqReadKey(candidate)].length  [JM:2546]
        <- ffLen = ticketQueue[_tqFarFutureKey(candidate)].length [JM:2548]
    <- candidate = lvl + 5 + (entropy % 95)                 [JM:2542]
      <- lvl (current level)
      <- entropy (PRNG chain from VRF word)

  readQueue = ticketQueue[_tqReadKey(candidate)]             [JM:2545]
    <- _tqReadKey depends on ticketWriteSlot                 [GS:721-722]
    <- ticketQueue population committed by _queueTickets callers

  ffQueue = ticketQueue[_tqFarFutureKey(candidate)]          [JM:2547]
    <- _tqFarFutureKey is pure (no storage dependency)       [GS:729-730]
    <- ticketQueue population committed by _queueTickets callers
```

**All input variables for RNG-01 analysis:**

| Variable | Slot | How It Influences Winner | Must Be Immutable During Window? |
|----------|------|------------------------|----------------------------------|
| rngWord (VRF word) | 4 | Entire PRNG chain for level sampling and index selection | YES -- delivered by VRF callback, unknown until fulfillment |
| lvl (current level) | 0 (offset 18) | Seeds entropy; determines candidate range [lvl+5, lvl+99] | YES -- set at RNG request time, does not change during jackpot phase |
| ticketQueue[_tqReadKey(candidate)] | 15 (mapping) | Read buffer: player population for winner selection | YES -- frozen by double-buffer swap at RNG request |
| ticketQueue[_tqFarFutureKey(candidate)] | 15 (mapping) | FF key: player population for winner selection | YES -- guarded by rngLockedFlag in _queueTickets |
| ticketWriteSlot | 1 (offset 23) | Determines which buffer is "read" vs "write" | YES -- swapped at RNG request, not modified again until _unlockRng |
| FAR_FUTURE_COIN_TAG | constant | Hash tag mixed into entropy | Immutable (compile-time constant) |
| FAR_FUTURE_COIN_SAMPLES | constant | Loop bound (10 iterations) | Immutable (compile-time constant) |

### Mutation Paths to Enumerate

Based on the v3.8 mutation surface catalog (CW-03), the following permissionless paths can write to `ticketQueue`:

| External Function | Module | Call Path to ticketQueue | Protection |
|-------------------|--------|------------------------|------------|
| purchase() | MintModule | _purchaseFor -> _queueTickets | Writes to WRITE buffer (double-buffer protection). FF key guarded by rngLockedFlag. |
| purchaseCoin() | MintModule | _purchaseCoinFor -> _queueTicketsScaled | Same protection as purchase() |
| purchaseLazyPass() | WhaleModule | _purchaseLazyPass -> _queueTickets | Same protection (rngLockedFlag guard, WhaleModule:475) |
| purchaseDeityPass() | WhaleModule | _purchaseDeityPass -> _queueTickets | Same protection |
| claimWhalePass() | EndgameModule | _queueTickets | Same protection |
| openLootBox() | LootboxModule | _resolveLootboxCommon -> _queueTicketsScaled | Writes to FF key only when targetLevel > level + 6. rngLockedFlag guard in _queueTicketsScaled blocks FF writes. |
| openBurnieLootBox() | LootboxModule | _resolveLootboxCommon -> _queueTicketsScaled | Same as openLootBox |
| advanceGame() | JackpotModule | _processAutoRebuy -> _queueTickets | Runs during advanceGame transaction (same tx as jackpot draw). phaseTransitionActive exemption for FF writes. |
| advanceGame() | AdvanceModule | _processPhaseTransition -> _queueTickets | Runs with phaseTransitionActive = true. Queues vault/sDGNRS perpetual tickets to level + 99 (always FF). Deterministic: same addresses, same quantity, same target level every time. |

**Key insight:** The `advanceGame` caller is the SAME transaction that consumes the RNG word. An attacker cannot insert a transaction between `advanceGame`'s auto-rebuy writes and `_awardFarFutureCoinJackpot` because they execute atomically in the same EVM call frame.

### Protection Layers

**Layer 1: Double-Buffer Swap (Read Buffer)**

`_swapAndFreeze` (GS:749) is called when daily RNG is requested (AdvanceModule:233). This flips `ticketWriteSlot ^= 1`, making the old write buffer the new read buffer. All subsequent `purchase()` / `purchaseCoin()` calls write to the NEW write buffer. `_awardFarFutureCoinJackpot` reads from `_tqReadKey(candidate)` which points to the OLD (now frozen) buffer.

Timeline:
1. `_swapAndFreeze` called (ticketWriteSlot flips) -- read buffer frozen
2. VRF request sent to Chainlink
3. [commitment window -- 3+ blocks]
4. VRF fulfillment callback stores word in `rngWordCurrent`
5. Next `advanceGame()` call enters `rngGate`, processes daily RNG
6. `payDailyJackpotCoinAndTickets` or `payDailyCoinJackpot` called
7. `_awardFarFutureCoinJackpot` reads from frozen read buffer

During step 3, any `purchase()` writes go to the NEW write buffer, not the frozen read buffer. The read buffer population is committed at step 1.

**Layer 2: rngLockedFlag Guard (FF Key)**

Phase 75 added the guard in `_queueTickets` (GS:545):
```solidity
bool isFarFuture = targetLevel > level + 6;
if (isFarFuture && rngLockedFlag && !phaseTransitionActive) revert RngLocked();
```

`rngLockedFlag` is set to `true` by `_finalizeRngRequest` (AdvanceModule:1328), which is called from `_requestRng`. It remains true until `_unlockRng` (AdvanceModule:1414) is called after daily processing completes.

During the commitment window (`rngLockedFlag = true`), ALL permissionless callers of `_queueTickets`/`_queueTicketsScaled`/`_queueTicketRange` that attempt to write far-future tickets will revert with `RngLocked()`. This covers:
- `purchase()` -> `_queueTickets` with far-future target: REVERTS
- `purchaseCoin()` -> `_queueTicketsScaled` with far-future target: REVERTS
- `openLootBox()` -> `_queueTicketsScaled` with far-future target: REVERTS
- `openBurnieLootBox()` -> `_queueTicketsScaled` with far-future target: REVERTS
- `purchaseLazyPass()` -> `_queueTickets` with far-future target: REVERTS (also has its own rngLockedFlag guard at WhaleModule:475)
- `purchaseDeityPass()` -> `_queueTickets`: REVERTS
- `claimWhalePass()` -> `_queueTickets`: REVERTS

**Layer 3: phaseTransitionActive Exemption (advanceGame-only)**

The only code path that can write FF tickets while `rngLockedFlag = true` is when `phaseTransitionActive = true`. This flag is set only by `advanceGame()` during level transitions (AdvanceModule:239-250) and cleared in the same transaction.

`_processPhaseTransition` (AdvanceModule:1222-1236) queues vault and sDGNRS perpetual tickets with `targetLevel = purchaseLevel + 99` (always far-future). This is:
- **Deterministic:** Fixed addresses (`ContractAddresses.SDGNRS`, `ContractAddresses.VAULT`), fixed quantity (16 per address per level), computed target level
- **Same transaction:** Executes atomically with all jackpot functions -- no external actor can intervene
- **Not influenced by the VRF word:** The ticket queuing happens BEFORE `rngGate` returns the VRF word

Similarly, `_processAutoRebuy` runs within `advanceGame` -> `payDailyJackpot` -> `_addClaimableEth`. Auto-rebuy tickets are queued in the same transaction frame that calls `_awardFarFutureCoinJackpot`. Even if auto-rebuy writes FF tickets, the writes and the jackpot draw are atomic -- no external actor can influence the sequence.

### Proof Structure

The proof document should follow this structure:

1. **Scope statement:** Define the exact outcome being analyzed (far-future coin jackpot winner)
2. **Backward trace:** From winner selection to all inputs (reproduce the trace above with exact source line references)
3. **Input inventory:** Every variable that influences the outcome, with its commitment point
4. **Mutation surface:** For each input, enumerate every permissionless write path
5. **Verdict per path:** SAFE with specific protection mechanism cited
6. **Combined pool length invariant:** Prove `combinedLen = readLen + ffLen` cannot change between VRF request and winner selection
7. **Cross-reference:** Show this proof extends v3.8 Category 3 (Jackpot BURNIE Winner) with the new FF key data source

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Mutation path enumeration | Manual grep | v3.8 CW-03 catalog | Already comprehensive; just filter for ticketQueue mutation paths |
| Backward trace | Ad-hoc analysis | v3.8 Category 3 backward trace | Phase 79 is an UPDATE to Category 3, not a new category |

## Common Pitfalls

### Pitfall 1: Forgetting the Mid-Day Lootbox RNG Path
**What goes wrong:** Assuming all VRF requests set `rngLockedFlag = true`.
**Why it happens:** The mid-day `requestLootboxRng` path (AdvanceModule:677) does NOT set `rngLockedFlag` -- it only sets `rngRequestTime` and advances the lootbox index. However, `_awardFarFutureCoinJackpot` is NEVER called from the mid-day path. It is only called from `payDailyJackpotCoinAndTickets` and `payDailyCoinJackpot`, both of which are only invoked during `advanceGame` where `rngLockedFlag` IS true.
**How to avoid:** The proof must explicitly state that `_awardFarFutureCoinJackpot` is only reachable via the daily advanceGame path where rngLockedFlag is true, and cite the two call sites (JM:707, JM:2370).

### Pitfall 2: Near-Future Ticket Writes Conflated with FF Writes
**What goes wrong:** Claiming that purchase() can modify FF key population during the window.
**Why it happens:** `purchase()` calls `_queueTickets` which routes to `_tqWriteKey` for near-future targets (targetLevel <= level + 6). Near-future writes to the WRITE buffer are harmless because `_awardFarFutureCoinJackpot` reads from the READ buffer.
**How to avoid:** Distinguish three data flows: (1) near-future -> write buffer -> not read by jackpot, (2) far-future -> FF key -> guarded by rngLockedFlag, (3) advanceGame-origin FF writes -> exempted by phaseTransitionActive -> same transaction as jackpot.

### Pitfall 3: Assuming ticketWriteSlot Can Change During Window
**What goes wrong:** Worrying that a mid-day `_swapTicketSlot` could flip which buffer is "read" vs "write" during the commitment window.
**Why it happens:** `requestLootboxRng` (AdvanceModule:717-720) calls `_swapTicketSlot` but only when `ticketsFullyProcessed` is true and write slot is non-empty. However, during the daily commitment window (`rngLockedFlag = true`), `requestLootboxRng` reverts at line 678 (`if (rngLockedFlag) revert RngLocked()`).
**How to avoid:** Note that `requestLootboxRng` is blocked by rngLockedFlag during the daily commitment window, so no mid-day buffer swap can occur while the daily jackpot flow is active.

### Pitfall 4: Missing the Auto-Rebuy Path
**What goes wrong:** Omitting `_processAutoRebuy` from the mutation surface.
**Why it happens:** Auto-rebuy is deep in the call chain (advanceGame -> payDailyJackpot -> _addClaimableEth -> _processAutoRebuy -> _queueTickets). It can write FF tickets if the auto-rebuy target level is > level + 6.
**How to avoid:** Include auto-rebuy in the mutation surface but note it is SAFE because (1) it executes within advanceGame with phaseTransitionActive context, and (2) it executes atomically in the same EVM transaction as the jackpot draw.

### Pitfall 5: Forgetting processTicketBatch Mutations to ticketQueue
**What goes wrong:** Missing that `processTicketBatch` (JM:1890-1951) deletes entries from `ticketQueue[readKey]` during processing.
**Why it happens:** processTicketBatch is called during advanceGame to drain the read-side queue and mint trait tickets.
**How to avoid:** Note that processTicketBatch runs BEFORE `_awardFarFutureCoinJackpot` in the advanceGame flow. The read buffer at jackpot time reflects the state AFTER processTicketBatch has drained entries for the current level. However, `_awardFarFutureCoinJackpot` selects from levels [lvl+5, lvl+99] -- well beyond the current level being processed. So processTicketBatch only drains the current level's queue, not the candidate levels the jackpot samples from. Still, this should be explicitly addressed in the proof.

## Code Examples

### Protection Check Pattern (for proof verification)

Each mutation path verdict should follow this pattern:

```
Path: purchase() -> _purchaseFor -> _queueTickets
Target variable: ticketQueue[_tqFarFutureKey(candidate)]
Protection:
  1. If targetLevel <= level + 6 -> routes to _tqWriteKey (not FF key) -> IRRELEVANT
  2. If targetLevel > level + 6 -> checks rngLockedFlag (GS:545)
     - rngLockedFlag = true during commitment window -> reverts RngLocked()
     - phaseTransitionActive = false for external callers -> no exemption
Verdict: SAFE -- permissionless callers cannot write to FF key during commitment window
Evidence: DegenerusGameStorage.sol:544-545
```

### Combined Pool Length Invariant

The proof must show that `combinedLen = readLen + ffLen` at JM:2549 cannot differ from what it would have been at VRF request time:

```
readLen = ticketQueue[_tqReadKey(candidate)].length
  - _tqReadKey depends on ticketWriteSlot (swapped at request time)
  - No push/delete to readKey queue between request and jackpot draw:
    - processTicketBatch drains current level only, not candidate levels [lvl+5, lvl+99]
    - No external function writes to read key (all writes go to write key or FF key)
  -> readLen is stable between request and consumption

ffLen = ticketQueue[_tqFarFutureKey(candidate)].length
  - rngLockedFlag blocks all permissionless FF writes (GS:545, GS:580, GS:642)
  - phaseTransitionActive exemption:
    - _processPhaseTransition writes to level purchaseLevel + 99 (one specific level)
    - Auto-rebuy writes to computed target level
    - Both execute atomically in same tx as jackpot draw
  -> ffLen is stable between request and consumption for external actors

combinedLen = readLen + ffLen -> stable between VRF request and consumption
```

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Foundry (forge) |
| Config file | foundry.toml |
| Quick run command | `forge test --match-contract JackpotCombinedPoolTest -vv` |
| Full suite command | `forge test` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| RNG-01 | No permissionless action during VRF commitment window can influence far-future coin jackpot winner | manual-only (audit proof document) | N/A -- this is an analytical proof, not a code test | N/A |

**Justification for manual-only:** RNG-01 is a security proof that requires exhaustive enumeration of mutation paths and reasoning about EVM transaction atomicity. The proof output is a document, not executable code. The existing Foundry tests from Phases 75 (12 routing tests) and 77 (8 combined pool tests) already verify the mechanical protections (rngLockedFlag guard, combined pool selection). What Phase 79 adds is the analytical proof that these protections are COMPLETE -- that no path was missed.

### Sampling Rate
- **Per task commit:** N/A (document output, not code)
- **Per wave merge:** `forge test` (verify no regression from any accidental edits)
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
None -- existing test infrastructure covers all mechanical behaviors. Phase 79 produces a proof document, not new tests.

## Open Questions

1. **processTicketBatch drain timing vs jackpot candidate range**
   - What we know: processTicketBatch drains entries for the CURRENT level, while `_awardFarFutureCoinJackpot` samples from levels [lvl+5, lvl+99]. These ranges do not overlap.
   - What's unclear: Could processFutureTicketBatch (the Phase 76 extension that drains FF key entries) be called between VRF request and jackpot draw within the same advanceGame flow?
   - Recommendation: The proof should trace the advanceGame call order to confirm processFutureTicketBatch runs BEFORE the jackpot functions, and verify it only processes levels that have already been swapped into the read-side queue -- not the candidate levels [lvl+5, lvl+99] that the jackpot samples from.

2. **Auto-rebuy target level range**
   - What we know: Auto-rebuy calls `_queueTickets(winner, lvl + 1, units)` at JM:1210, targeting the NEXT level. If `lvl + 1 > level + 6`, this would be a far-future write.
   - What's unclear: Whether the auto-rebuy target can fall within the jackpot's candidate range [lvl+5, lvl+99].
   - Recommendation: Since auto-rebuy runs atomically within advanceGame (same tx as jackpot), even if it modifies FF key population, no external actor can exploit it. But the proof should confirm the atomicity argument explicitly.

## Sources

### Primary (HIGH confidence)
- DegenerusGameJackpotModule.sol lines 2522-2614 -- current `_awardFarFutureCoinJackpot` implementation with combined pool (verified in code)
- DegenerusGameStorage.sol lines 537-565 -- `_queueTickets` with rngLockedFlag guard (verified in code)
- DegenerusGameStorage.sol lines 572-623 -- `_queueTicketsScaled` with rngLockedFlag guard (verified in code)
- DegenerusGameStorage.sol lines 631-672 -- `_queueTicketRange` with rngLockedFlag guard (verified in code)
- DegenerusGameStorage.sol lines 714-731 -- `_tqWriteKey`, `_tqReadKey`, `_tqFarFutureKey` key encoding (verified in code)
- DegenerusGameAdvanceModule.sol lines 1308-1328 -- `_finalizeRngRequest` sets rngLockedFlag (verified in code)
- DegenerusGameAdvanceModule.sol lines 1412-1418 -- `_unlockRng` clears rngLockedFlag (verified in code)
- DegenerusGameAdvanceModule.sol lines 677-744 -- `requestLootboxRng` blocked by rngLockedFlag (verified in code)
- DegenerusGameAdvanceModule.sol lines 1222-1236 -- `_processPhaseTransition` FF ticket queuing (verified in code)

### Secondary (HIGH confidence -- prior audit documents)
- audit/v3.8-commitment-window-inventory.md -- CW-01, CW-02, CW-03 catalogs: forward trace, backward trace, mutation surface
- .planning/phases/75-ticket-routing-rng-guard/75-01-PLAN.md -- Phase 75 routing + guard implementation details
- .planning/phases/77-jackpot-combined-pool-tq-01-fix/77-01-PLAN.md -- Phase 77 combined pool implementation details

### Tertiary (HIGH confidence -- project memory)
- feedback_rng_backward_trace.md -- Mandatory backward-trace methodology
- feedback_rng_commitment_window.md -- Mandatory commitment window analysis methodology

## Metadata

**Confidence breakdown:**
- Protection mechanisms: HIGH -- all three protection layers verified directly in source code
- Mutation surface: HIGH -- v3.8 CW-03 already cataloged all permissionless ticketQueue mutation paths; Phase 79 adds the FF key analysis
- Methodology: HIGH -- v3.8 established the pattern; Phase 79 applies it to a narrower scope
- Open questions: HIGH -- both questions have likely-SAFE answers based on code analysis; proof document will confirm

**Research date:** 2026-03-22
**Valid until:** Indefinite (smart contract audit, no external dependencies to go stale)
