# Phase 77: Jackpot Combined Pool + TQ-01 Fix - Research

**Researched:** 2026-03-22
**Domain:** Solidity jackpot winner selection, dual-key-space pool aggregation, commitment window security
**Confidence:** HIGH

## Summary

Phase 77 modifies `_awardFarFutureCoinJackpot` (JackpotModule:2522-2607) to select winners from a combined pool spanning both the write-side double-buffer AND the far-future key space. The current code at line 2544 reads only `ticketQueue[_tqWriteKey(candidate)]`, which is the TQ-01 vulnerability documented in the v3.8 audit: the write buffer is mutable by permissionless `purchase()` and `purchaseCoin()` during the VRF commitment window, allowing an attacker to frontrun the jackpot draw.

The original TQ-01 fix recommendation (Option A: change `_tqWriteKey` to `_tqReadKey`) was a correct one-line root-cause fix for the old architecture. However, after Phase 75's routing change, tickets for far-future levels now land in the FF key space (`_tqFarFutureKey`) instead of the write buffer. If `_awardFarFutureCoinJackpot` only reads the read buffer, it misses all FF-routed tickets. The combined pool approach reads BOTH the write-side buffer (using `_tqReadKey` for security) and the FF key, selecting a winner from the union of both populations.

This phase also addresses a subtle range overlap: the jackpot samples candidates in `[lvl+5, lvl+99]`, while the routing threshold is `targetLevel > level + 6`. For candidates `lvl+5` and `lvl+6`, tickets always live in the double-buffer (write/read key). For candidates `lvl+7` through `lvl+99`, tickets may exist in BOTH the read buffer (from pre-routing-change purchases or near-future routing at earlier game levels) AND the FF key (from far-future routing). The combined pool captures all eligible tickets regardless of which key space they ended up in.

**Primary recommendation:** Replace the single `_tqWriteKey` read at JackpotModule:2544 with a combined pool computation: `readLen = ticketQueue[_tqReadKey(candidate)].length` plus `ffLen = ticketQueue[_tqFarFutureKey(candidate)].length`, then select a winner index over `readLen + ffLen`, routing indices `[0, readLen)` to the read buffer and indices `[readLen, readLen+ffLen)` to the FF key.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| JACK-01 | _awardFarFutureCoinJackpot selects winners from both write-side buffer AND far-future key combined | Current code at JM:2544 reads only `_tqWriteKey(candidate)`; must read both `_tqReadKey(candidate)` and `_tqFarFutureKey(candidate)`, sum their lengths, and select from the combined population |
| JACK-02 | Winner index is computed over the combined pool length (len + ffLen) with correct routing to the right queue | Index in `[0, readLen)` reads from read buffer; index in `[readLen, readLen+ffLen)` reads from FF key (subtract readLen to get FF index) |
| EDGE-03 | The TQ-01 fix is included or superseded by the combined pool approach | Combined pool replaces `_tqWriteKey` with `_tqReadKey` for the double-buffer portion, which is the same one-line fix as TQ-01 Option A. The FF key addition extends beyond the original fix to include Phase 75 routed tickets. TQ-01 is both fixed and superseded. |
</phase_requirements>

## Architecture Patterns

### Current _awardFarFutureCoinJackpot Flow (JM:2522-2607)

```
_awardFarFutureCoinJackpot(lvl, farBudget, rngWord)
  |
  +-- If farBudget == 0: return                     [line 2527]
  +-- entropy = rngWord ^ (lvl << 192) ^ FAR_FUTURE_COIN_TAG  [2529-2531]
  |
  +-- First pass: find up to 10 winners             [2533-2561]
  |     For s in [0, FAR_FUTURE_COIN_SAMPLES=10):
  |       entropy = EntropyLib.entropyStep(entropy ^ s)    [2539]
  |       candidate = lvl + 5 + (entropy % 95)             [2542]
  |       queue = ticketQueue[_tqWriteKey(candidate)]      [2544] <-- BUG: reads write buffer
  |       len = queue.length                               [2545]
  |       If len != 0:
  |         idx = (entropy >> 32) % len                    [2547]
  |         winner = queue[idx]                            [2548]
  |         If winner != address(0): store in winners[]
  |
  +-- If found == 0: return                         [2563]
  +-- Second pass: distribute farBudget/found to each winner via coin.creditFlipBatch  [2565-2606]
```

### Required Fix: Combined Pool Selection

The fix modifies only the winner selection logic inside the loop (lines 2544-2555). The entropy derivation, level sampling, and payout logic are unchanged.

```
_awardFarFutureCoinJackpot(lvl, farBudget, rngWord) -- PROPOSED
  |
  +-- Same entropy setup [2527-2531]
  |
  +-- For s in [0, 10):
  |     entropy = EntropyLib.entropyStep(entropy ^ s)
  |     candidate = lvl + 5 + (entropy % 95)
  |
  |     // COMBINED POOL: read both key spaces
  |     address[] storage readQueue = ticketQueue[_tqReadKey(candidate)]
  |     uint256 readLen = readQueue.length
  |     address[] storage ffQueue = ticketQueue[_tqFarFutureKey(candidate)]
  |     uint256 ffLen = ffQueue.length
  |     uint256 combinedLen = readLen + ffLen
  |
  |     If combinedLen != 0:
  |       uint256 idx = (entropy >> 32) % combinedLen
  |       address winner = (idx < readLen)
  |         ? readQueue[idx]
  |         : ffQueue[idx - readLen]
  |       If winner != address(0): store in winners[]
  |
  +-- Same payout logic [2563-2606]
```

### Key Design Decisions

**1. Read buffer, not write buffer, for the double-buffer portion.**
The combined pool uses `_tqReadKey(candidate)` instead of `_tqWriteKey(candidate)`. This is the TQ-01 fix: the read buffer is frozen before the VRF word is requested (via `_swapAndFreeze` at AdvanceModule:233), making it immutable during the commitment window. This eliminates the frontrunning vector.

**2. FF key is safe by construction (Phase 75 RNG-02 guard).**
After Phase 75, `_queueTickets` and `_queueTicketsScaled` revert on FF key writes when `rngLockedFlag` is true (unless `phaseTransitionActive`). The `phaseTransitionActive` exemption allows advanceGame-origin vault/sDGNRS writes, but those are internal to the advanceGame flow and occur BEFORE the jackpot function runs (the phase transition completes before jackpot days begin). Therefore, the FF key population is also frozen during the commitment window.

**3. Order of pools: read buffer first, FF key second.**
The combined index assigns `[0, readLen)` to the read buffer and `[readLen, readLen+ffLen)` to the FF key. This order is arbitrary for correctness (any consistent ordering works), but placing the read buffer first is natural since it is the "older" population (frozen pre-swap) and the `readLen < combinedLen` comparison avoids a subtraction on the more common path.

**4. No overflow risk on combinedLen.**
Both `readLen` and `ffLen` are `uint256` values derived from `address[] storage` arrays. The Solidity array length is bounded by available storage slots. In practice, even a full level's ticket queue contains far fewer entries than could overflow `uint256`. The `(entropy >> 32) % combinedLen` modulo is also safe since `combinedLen > 0` (guarded by the `if` check).

### Range Analysis: Jackpot Candidates vs. Routing Threshold

The jackpot samples `candidate = lvl + 5 + (entropy % 95)`, yielding levels in `[lvl+5, lvl+99]`.

Phase 75 routes to FF key when `targetLevel > level + 6` at the time of purchase. The critical insight is that `level` (the game level) changes over time:

| Candidate Level | At Purchase Time (level = L) | Key Space |
|----------------|------------------------------|-----------|
| L+5 | `L+5 > L+6` is FALSE | Write buffer (`_tqWriteKey`) |
| L+6 | `L+6 > L+6` is FALSE | Write buffer (`_tqWriteKey`) |
| L+7 through L+99 | `> L+6` is TRUE | FF key (`_tqFarFutureKey`) |

But tickets for the same target level can be purchased at different game levels:
- A ticket for level 50 purchased when `level = 5` goes to FF key (`50 > 11`)
- A ticket for level 50 purchased when `level = 44` goes to write buffer (`50 > 50` is FALSE)

**Therefore, any candidate level may have tickets in BOTH key spaces.** The combined pool correctly handles this by reading both.

For candidates `lvl+5` and `lvl+6`: these are within the near-future window, so tickets were routed to the write buffer. After `_swapAndFreeze`, they appear in the read buffer. The FF key for these levels is typically empty (no tickets are routed there since they are within +6). The combined pool's `ffLen == 0` makes it equivalent to reading only the read buffer for these candidates.

### Files to Modify

```
contracts/
  modules/
    DegenerusGameJackpotModule.sol     # Primary: modify _awardFarFutureCoinJackpot (lines 2544-2555)
```

One file, one function, approximately 10 lines changed. No new files. No interface changes. No storage changes.

### Anti-Patterns to Avoid

- **Keeping `_tqWriteKey` for any read in this function:** Every use of `_tqWriteKey` in winner selection is a commitment window vulnerability. The write buffer is live and mutable. Always use `_tqReadKey` for the double-buffer portion.
- **Reading only one key space:** Reading only `_tqReadKey` misses FF-routed tickets. Reading only `_tqFarFutureKey` misses near-future tickets. The combined pool is the correct approach.
- **Modifying the entropy derivation or level sampling:** The entropy chain and `candidate = lvl + 5 + (entropy % 95)` formula must remain unchanged. The fix is purely in how the winner is selected from the pool, not in which levels are sampled or how entropy flows.
- **Changing the function signature or visibility:** `_awardFarFutureCoinJackpot` is `private` and called from two external-facing functions (`payDailyJackpotCoinAndTickets` at JM:707 and `payDailyCoinJackpot` at JM:2370). The fix is internal to the function; no signature or visibility change is needed.
- **Adding overflow protection for combinedLen:** `uint256 + uint256` cannot overflow in practice (array lengths are bounded by storage). Adding `unchecked` is optional but unnecessary. Do NOT add a revert on overflow as it would block the jackpot for legitimate queue sizes.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Combined pool length | Manual counting or iterating both queues | `readQueue.length + ffQueue.length` | O(1) storage reads, no iteration needed |
| Winner routing | Complex if/else chain or separate loops | `idx < readLen ? readQueue[idx] : ffQueue[idx - readLen]` | Single ternary, no loop, no extra variables |
| FF key computation | Inline `candidate \| (1 << 22)` | `_tqFarFutureKey(candidate)` from Phase 74 | Consistency with Phase 74/75/76; single definition |
| Read key computation | Inline slot bit logic | `_tqReadKey(candidate)` from Storage | Consistency with processTicketBatch (JM:1891) |

## Common Pitfalls

### Pitfall 1: Using _tqWriteKey Instead of _tqReadKey for the Double-Buffer Portion
**What goes wrong:** The TQ-01 vulnerability persists. An attacker can frontrun the jackpot by inserting tickets into the write buffer after observing the VRF word on-chain.
**Why it happens:** The existing code uses `_tqWriteKey`. A developer might combine the write buffer with the FF key without recognizing that the write buffer read itself is the security bug.
**How to avoid:** The combined pool MUST use `_tqReadKey(candidate)` for the double-buffer portion. Verify in code review that `_tqWriteKey` does not appear anywhere in `_awardFarFutureCoinJackpot` after the fix.
**Warning signs:** The string `_tqWriteKey` appears in `_awardFarFutureCoinJackpot` after modification.

### Pitfall 2: Wrong Index Routing When readLen == 0
**What goes wrong:** If `readLen == 0` and `ffLen > 0`, the combined length is `ffLen`. The index `idx = (entropy >> 32) % ffLen`. Since `idx < readLen` is `idx < 0` (always false), the function reads from `ffQueue[idx - 0] = ffQueue[idx]`. This is correct. But if the developer uses `idx <= readLen` instead of `idx < readLen`, then when `idx == 0 && readLen == 0`, it would incorrectly read from `readQueue[0]` which does not exist (empty array), causing a revert.
**Why it happens:** Off-by-one error in the routing condition.
**How to avoid:** The condition MUST be strictly `idx < readLen`, not `idx <= readLen`.
**Warning signs:** Revert on jackpot draw when read buffer is empty but FF key has entries.

### Pitfall 3: combinedLen == 0 Division by Zero
**What goes wrong:** If both queues are empty, `combinedLen == 0`, and `(entropy >> 32) % combinedLen` causes an EVM revert (division by zero).
**Why it happens:** The `if (len != 0)` guard in the current code prevents this. In the combined pool version, this guard must check `combinedLen`, not a single queue length.
**How to avoid:** The `if (combinedLen != 0)` guard MUST wrap the modulo operation.
**Warning signs:** Jackpot function reverts when no tickets exist for a sampled candidate level.

### Pitfall 4: Forgetting to Update Both Callers
**What goes wrong:** `_awardFarFutureCoinJackpot` is called from two paths: `payDailyJackpotCoinAndTickets` (JM:707) and `payDailyCoinJackpot` (JM:2370). Since the function is `private` and the fix is inside the function itself, both callers automatically get the fix. No caller-side changes are needed.
**Why it happens:** The Phase 72 audit flagged both call paths. A developer might try to fix the callers instead of the function.
**How to avoid:** The fix is entirely within `_awardFarFutureCoinJackpot`. Both callers pass `randWord` to it unchanged. No caller modification needed.
**Warning signs:** Unnecessary changes to `payDailyJackpotCoinAndTickets` or `payDailyCoinJackpot`.

### Pitfall 5: Gas Cost of Two Storage Reads Per Sample
**What goes wrong:** The combined pool adds one extra storage read per sample iteration (reading `ffQueue.length` in addition to `readQueue.length`). With `FAR_FUTURE_COIN_SAMPLES = 10`, this adds up to 10 extra cold SLOADs (~2100 gas each) = ~21,000 gas.
**Why it happens:** Reading from two key spaces inherently requires two storage accesses.
**How to avoid:** This is acceptable and expected. The 21K gas overhead is negligible within the context of `advanceGame` (which already uses hundreds of thousands of gas). Do NOT try to optimize by caching or pre-computing -- the simplicity of the direct read is worth the gas.
**Warning signs:** Premature optimization attempts that add complexity without meaningful gas savings.

## Code Examples

### Combined Pool Implementation (Verified Pattern)

```solidity
// Source: contracts/modules/DegenerusGameJackpotModule.sol, lines 2538-2561
// PROPOSED MODIFICATION — replaces the inner loop body

for (uint8 s; s < FAR_FUTURE_COIN_SAMPLES; ) {
    entropy = EntropyLib.entropyStep(entropy ^ uint256(s));

    // Pick a random level in [lvl+5, lvl+99]
    uint24 candidate = lvl + 5 + uint24(entropy % 95);

    // COMBINED POOL: read from both the frozen read buffer and the FF key
    address[] storage readQueue = ticketQueue[_tqReadKey(candidate)];
    uint256 readLen = readQueue.length;
    address[] storage ffQueue = ticketQueue[_tqFarFutureKey(candidate)];
    uint256 ffLen = ffQueue.length;
    uint256 combinedLen = readLen + ffLen;

    if (combinedLen != 0) {
        uint256 idx = (entropy >> 32) % combinedLen;
        address winner = idx < readLen
            ? readQueue[idx]
            : ffQueue[idx - readLen];
        if (winner != address(0)) {
            winners[found] = winner;
            winnerLevels[found] = candidate;
            unchecked {
                ++found;
            }
        }
    }

    unchecked {
        ++s;
    }
}
```

### Before/After Comparison

```solidity
// BEFORE (vulnerable, line 2544):
address[] storage queue = ticketQueue[_tqWriteKey(candidate)];
uint256 len = queue.length;
if (len != 0) {
    uint256 idx = (entropy >> 32) % len;
    address winner = queue[idx];

// AFTER (combined pool):
address[] storage readQueue = ticketQueue[_tqReadKey(candidate)];
uint256 readLen = readQueue.length;
address[] storage ffQueue = ticketQueue[_tqFarFutureKey(candidate)];
uint256 ffLen = ffQueue.length;
uint256 combinedLen = readLen + ffLen;
if (combinedLen != 0) {
    uint256 idx = (entropy >> 32) % combinedLen;
    address winner = idx < readLen
        ? readQueue[idx]
        : ffQueue[idx - readLen];
```

### Security Argument: Why Combined Pool is Safe Under VRF Commitment Window

```
Timeline during advanceGame:

1. rngGate returns 1 → _swapAndFreeze(purchaseLevel)
   - ticketWriteSlot ^= 1 (global swap)
   - All write-buffer entries become read-buffer entries
   - Read buffer is now FROZEN (swapped, no permissionless writes reach it)

2. _requestRng → rngLockedFlag = true
   - VRF request sent to Chainlink

3. rawFulfillRandomWords → rngWordCurrent = word
   - VRF word stored on-chain (attacker can read it)

4. [COMMITMENT WINDOW: attacker knows rngWord, may try to influence outcome]

   4a. purchase() → _queueTickets → writes to _tqWriteKey(targetLevel)
       → Combined pool reads _tqReadKey (OPPOSITE buffer) → INVISIBLE to jackpot

   4b. purchase() → _queueTickets → targetLevel > level+6 → _tqFarFutureKey
       → REVERTS because rngLockedFlag && !phaseTransitionActive (Phase 75 guard)

   4c. advanceGame-origin writes (vault perpetual, sDGNRS)
       → phaseTransitionActive = true → allowed through guard
       → BUT phase transition completes BEFORE jackpot days begin
       → By the time _awardFarFutureCoinJackpot runs, no more writes happen

5. advanceGame resumes → _awardFarFutureCoinJackpot(lvl, farBudget, rngWord)
   - readQueue = ticketQueue[_tqReadKey(candidate)] → frozen pre-swap entries
   - ffQueue = ticketQueue[_tqFarFutureKey(candidate)] → guarded by rngLocked
   - Both populations are immutable from attacker's perspective
   - Winner selection is deterministic and unmanipulable
```

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
| JACK-01 | _awardFarFutureCoinJackpot reads both read buffer and FF key | unit | `forge test --match-test testCombinedPoolReadsBothQueues -vv` | Wave 0 |
| JACK-02 | Winner index routes correctly to read buffer vs FF key | unit | `forge test --match-test testWinnerIndexRouting -vv` | Wave 0 |
| EDGE-03 | _tqWriteKey no longer used in _awardFarFutureCoinJackpot | unit | `forge test --match-test testNoWriteKeyInJackpot -vv` | Wave 0 |

### Sampling Rate
- **Per task commit:** `npx hardhat compile` (must succeed)
- **Per wave merge:** `forge test` (full Foundry suite)
- **Phase gate:** All requirement tests pass + full suite green

### Wave 0 Gaps
- [ ] Foundry test harness replicating `_awardFarFutureCoinJackpot` combined pool logic with controllable `ticketQueue` state, `ticketWriteSlot`, and entropy input
- [ ] Test: both read buffer and FF key have entries -- winner selected from combined pool (JACK-01)
- [ ] Test: only read buffer has entries -- winner selected from read buffer, FF queue empty has no effect (JACK-01 boundary)
- [ ] Test: only FF key has entries -- winner selected from FF key, read buffer empty has no effect (JACK-01 boundary)
- [ ] Test: both queues empty -- `found` stays 0, no winner for that sample (division safety)
- [ ] Test: winner index in `[0, readLen)` returns read buffer entry, index in `[readLen, readLen+ffLen)` returns FF entry (JACK-02)
- [ ] Test: `_tqReadKey` used instead of `_tqWriteKey` (EDGE-03 -- verified by construction in harness, not by bytecode inspection)

Note: Full integration tests (TEST-03) and commitment window proof (RNG-01) are deferred to Phase 80 and Phase 79 respectively.

### Test Harness Design

Since `_awardFarFutureCoinJackpot` is `private` (not `internal`), a Foundry harness cannot inherit from `DegenerusGameJackpotModule` and expose it. Two approaches:

**Option A (Recommended): Replicate the combined pool selection logic in a standalone harness.** The harness inherits `DegenerusGameStorage` (for `ticketQueue`, `_tqReadKey`, `_tqFarFutureKey`, etc.) and implements the proposed combined pool selection logic in a public function. Tests verify the selection logic produces correct winners from controlled queue state. This is the same pattern used by Phase 75 (TicketRouting.t.sol) and Phase 76 (TicketProcessingFF.t.sol).

**Option B: Change visibility to `internal`.** This allows a harness to inherit the module and expose the function. However, this changes the contract's bytecode and may affect gas (private functions can be inlined by the optimizer). Not recommended.

The harness approach (Option A) is consistent with all prior phases and avoids touching the production code's visibility.

## Open Questions

1. **Should the combined pool also include the write buffer (in addition to read buffer and FF key)?**
   - What we know: No. The write buffer is the active, mutable buffer where new purchases land. Including it would reintroduce the TQ-01 vulnerability. The read buffer contains all committed tickets from before the last swap. The FF key contains all far-future routed tickets (guarded by rngLocked). Together they form the complete, immutable eligible population.
   - Recommendation: Two pools only: read buffer + FF key. Never read the write buffer for winner selection.

2. **What if a candidate level has tickets in the write buffer that are NOT in the read buffer?**
   - What we know: Tickets purchased after the most recent `_swapAndFreeze` are in the write buffer and NOT yet in the read buffer. These tickets are from the current commitment window and are correctly excluded from the jackpot draw. They will appear in the read buffer after the next swap.
   - Recommendation: This is correct behavior, not a bug. Newly purchased tickets should not be eligible for the current jackpot draw because their inclusion could be manipulated.

3. **Does the combined pool change the expected number of winners?**
   - What we know: The current code reads only the write buffer, which may or may not have entries for a given far-future level. The combined pool reads both the read buffer and FF key, which may have MORE entries total. This could increase `found` (the number of non-zero winners) since more candidate levels may have non-empty queues. This is a feature, not a bug -- more eligible tickets means more fair distribution.
   - Recommendation: No action needed. The change correctly increases the eligible population.

## Sources

### Primary (HIGH confidence)
- contracts/modules/DegenerusGameJackpotModule.sol:2522-2607 -- Full `_awardFarFutureCoinJackpot` implementation (current code with `_tqWriteKey` bug)
- contracts/modules/DegenerusGameJackpotModule.sol:681-707 -- `payDailyJackpotCoinAndTickets` caller (call path 1)
- contracts/modules/DegenerusGameJackpotModule.sol:2361-2370 -- `payDailyCoinJackpot` caller (call path 2)
- contracts/storage/DegenerusGameStorage.sol:714-731 -- `_tqWriteKey`, `_tqReadKey`, `_tqFarFutureKey` key encoding helpers
- contracts/storage/DegenerusGameStorage.sol:537-564 -- `_queueTickets` with Phase 75 FF routing and rngLocked guard
- contracts/storage/DegenerusGameStorage.sol:739-744 -- `_swapTicketSlot` global swap mechanism
- contracts/modules/DegenerusGameAdvanceModule.sol:232-235 -- `_swapAndFreeze` called before VRF request
- audit/v3.8-commitment-window-inventory.md:3522-3668 -- TQ-01 vulnerability documentation, severity MEDIUM, Fix Option A recommended
- .planning/phases/75-ticket-routing-rng-guard/75-01-SUMMARY.md -- Phase 75 establishing rngLocked guard on FF key writes
- .planning/phases/76-ticket-processing-extension/76-01-SUMMARY.md -- Phase 76 establishing dual-queue drain in processFutureTicketBatch

### Secondary (MEDIUM confidence)
- audit/v3.8-commitment-window-inventory.md:3758-3812 -- Cross-contract pattern scan confirming TQ-01 is the only write-buffer vulnerability

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- pure Solidity modification to one private function in JackpotModule; no new libraries, no interface changes, no storage changes
- Architecture: HIGH -- combined pool pattern is a straightforward extension; read buffer + FF key covers all eligible tickets; security argument is well-established from Phase 72 audit and Phase 75 guard implementation
- Pitfalls: HIGH -- identified from direct analysis of the TQ-01 audit findings, the range overlap between jackpot sampling and routing threshold, and the gas implications of dual reads

**Research date:** 2026-03-22
**Valid until:** Indefinite (Solidity control flow analysis; valid as long as the function signature, double-buffer mechanism, and FF key space remain unchanged)
