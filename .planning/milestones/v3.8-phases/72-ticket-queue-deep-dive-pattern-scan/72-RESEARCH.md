# Phase 72: Ticket Queue Deep-Dive + Pattern Scan - Research

**Researched:** 2026-03-22
**Domain:** Smart contract security audit -- VRF commitment window analysis for ticket queue double-buffer mechanism
**Confidence:** HIGH

## Summary

The ticket queue "known vulnerability" is real and specific: `_awardFarFutureCoinJackpot` (JackpotModule:2544) reads from `ticketQueue[_tqWriteKey(candidate)]` -- the **write** buffer, not the read buffer. This means tickets added by permissionless `purchase()` calls AFTER the VRF word is visible on-chain (in `rngWordCurrent`) can influence which player wins the 25% far-future portion of the daily BURNIE jackpot. The attacker can precompute exactly which far-future levels will be sampled and add themselves to those queue positions.

Phase 69's SAFE verdict for `ticketQueue` (line 1422 of the audit artifact) contains an incorrect claim: "ticketQueue[readKey] is the far-future winner pool." The far-future winner pool actually uses `_tqWriteKey`, not `_tqReadKey`. The double-buffer protection is effective for `processTicketBatch` (which correctly uses `_tqReadKey`), but does NOT protect `_awardFarFutureCoinJackpot`.

**Primary recommendation:** Document this as a confirmed commitment window violation (severity depends on BURNIE value), identify the fix (change `_tqWriteKey` to `_tqReadKey` in `_awardFarFutureCoinJackpot`, or add `rngLockedFlag` guard to `purchase()`), then systematically scan all contracts for similar patterns where VRF-dependent outcome computation reads mutable state that is not protected during the commitment window.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| TQ-01 | Deep-dive on ticket queue swap during jackpot phase -- full exploitation scenario documented with attacker steps | Full attack sequence traced: VRF fulfillment exposes `rngWordCurrent`, attacker precomputes sampled levels, calls `purchase()` (no `rngLockedFlag` guard), adds tickets to write buffer read by `_awardFarFutureCoinJackpot` |
| TQ-02 | Identify and verify fix for the ticket queue commitment window violation | Two candidate fixes identified: (1) change `_tqWriteKey` to `_tqReadKey` at JackpotModule:2544, or (2) add `rngLockedFlag` guard to `_purchaseFor`. Each has tradeoffs documented below. |
| TQ-03 | Pattern scan for similar commitment window violations across all contracts | Methodology defined: enumerate all state reads during VRF-dependent outcome computation, cross-reference against permissionless writers active during commitment window, check for missing guards. 8 contracts + 12 modules in scope. |
</phase_requirements>

## Architecture Patterns

### Ticket Queue Double-Buffer Mechanism

The ticket queue uses a double-buffer controlled by `ticketWriteSlot` (packed in slot 1, offset 23):

```
ticketQueue[mapping(uint24 => address[])]  -- slot 15
ticketsOwedPacked[mapping(uint24 => mapping(address => uint40))]  -- slot 16

Write key: _tqWriteKey(lvl) = ticketWriteSlot != 0 ? lvl | TICKET_SLOT_BIT : lvl
Read key:  _tqReadKey(lvl)  = ticketWriteSlot == 0 ? lvl | TICKET_SLOT_BIT : lvl

TICKET_SLOT_BIT = 1 << 23 (bit 23 of the uint24 level key)
```

**Swap mechanism:** `_swapTicketSlot` flips `ticketWriteSlot ^= 1`, making the old write buffer the new read buffer and vice versa. Called via `_swapAndFreeze` at daily RNG request time (AdvanceModule:230) and via `requestLootboxRng` (AdvanceModule:720).

### Daily Jackpot Timeline (Jackpot Phase)

```
Day N of jackpot phase:
  TX1: advanceGame() -> rngGate() -> _requestRng() [sets rngLockedFlag=true]
                                  -> _swapAndFreeze() [swaps ticket buffer]
                                  -> break (VRF pending)

  TX2: rawFulfillRandomWords() -> rngWordCurrent = word
       ^^^ VRF WORD NOW VISIBLE ON-CHAIN ^^^

  === COMMITMENT WINDOW: rngLockedFlag=true, VRF word visible ===
  === purchase() NOT blocked by rngLockedFlag -- writes to WRITE buffer ===

  TX3: advanceGame() -> rngGate() -> returns word
                      -> payDailyJackpot(true, lvl, rngWord) -> ETH distribution
                      -> break

  TX4+: advanceGame() -> resume ETH distribution if needed

  TXn: advanceGame() -> payDailyJackpotCoinAndTickets(rngWord)
                      -> _awardFarFutureCoinJackpot(lvl, farBudget, rngWord)
                         ^^^ READS ticketQueue[_tqWriteKey(candidate)] ^^^
                      -> _unlockRng(day) [clears rngLockedFlag]
```

### The Vulnerability: Write Buffer Read During Outcome Computation

**Code location:** JackpotModule:2544

```solidity
// Source: contracts/modules/DegenerusGameJackpotModule.sol:2522-2561
function _awardFarFutureCoinJackpot(
    uint24 lvl,
    uint256 farBudget,
    uint256 rngWord
) private {
    // ...
    for (uint8 s; s < FAR_FUTURE_COIN_SAMPLES; ) {
        entropy = EntropyLib.entropyStep(entropy ^ uint256(s));
        uint24 candidate = lvl + 5 + uint24(entropy % 95);

        // BUG: Uses _tqWriteKey, not _tqReadKey
        // This reads the ACTIVE write buffer, which purchase() can modify
        address[] storage queue = ticketQueue[_tqWriteKey(candidate)];
        uint256 len = queue.length;
        if (len != 0) {
            uint256 idx = (entropy >> 32) % len;
            address winner = queue[idx];
            // ...
        }
    }
}
```

**Why processTicketBatch is NOT affected (correct implementation):**

```solidity
// Source: contracts/modules/DegenerusGameJackpotModule.sol:1891
function processTicketBatch(uint24 lvl) external returns (bool finished) {
    uint24 rk = _tqReadKey(lvl);  // CORRECT: uses read key
    address[] storage queue = ticketQueue[rk];
    // ...
}
```

### Attack Sequence (TQ-01)

**Preconditions:**
1. Game is in jackpot phase (`jackpotPhaseFlag = true`)
2. Daily VRF word has been requested (`rngLockedFlag = true`)
3. VRF fulfillment has occurred (`rngWordCurrent` is set and visible via `eth_getStorageAt`)
4. `payDailyJackpotCoinAndTickets` has not yet been called for this day

**Attacker steps:**
1. Monitor mempool / chain for `rawFulfillRandomWords` tx that sets `rngWordCurrent`
2. Read `rngWordCurrent` via `eth_getStorageAt(gameProxy, slot_4)` -- storage slot 4
3. Precompute `_awardFarFutureCoinJackpot` entropy derivation:
   - `entropy = rngWord ^ (uint256(level) << 192) ^ uint256(keccak256("far-future-coin"))`
   - For each of 10 samples: `entropy = EntropyLib.entropyStep(entropy ^ uint256(s))`
   - `candidate = level + 5 + uint24(entropy % 95)` -- identifies which far-future levels will be sampled
   - `idx = (entropy >> 32) % queueLength` -- identifies winning queue position
4. Call `purchase()` to add tickets for the target far-future level(s)
   - `purchase()` -> `_purchaseFor()` -> `_queueTickets()` -> pushes to `ticketQueue[_tqWriteKey(targetLevel)]`
   - No `rngLockedFlag` check in `_purchaseFor()` (confirmed: MintModule has zero references to `rngLockedFlag`)
5. When `advanceGame()` is called next, `payDailyJackpotCoinAndTickets` -> `_awardFarFutureCoinJackpot` reads attacker's freshly-added ticket from the write buffer

**Outcome manipulation:** Attacker can guarantee they are selected as one of up to 10 far-future winners, receiving a share of 25% of the daily BURNIE jackpot budget (FAR_FUTURE_COIN_BPS = 2500).

**Severity assessment:** MEDIUM (possibly LOW depending on BURNIE value at exploitation time). The attack requires:
- Cost: at least one ticket purchase (`price / 4` wei per ticket scaled by TICKET_SCALE)
- Reward: share of 25% of daily BURNIE coin budget
- The BURNIE is a game token (BurnieCoinflip flipCredit), not directly ETH
- Attack is repeatable every jackpot day

### Candidate Fixes (TQ-02)

**Fix Option A: Change `_tqWriteKey` to `_tqReadKey` in `_awardFarFutureCoinJackpot`**

```solidity
// JackpotModule:2544 - change from:
address[] storage queue = ticketQueue[_tqWriteKey(candidate)];
// to:
address[] storage queue = ticketQueue[_tqReadKey(candidate)];
```

- Pros: Minimal change, directly addresses the root cause, aligns with processTicketBatch pattern
- Cons: Far-future levels [lvl+5, lvl+99] may have empty read buffers (these levels haven't been processed yet). The read buffer for far-future levels may never have been populated because `_swapAndFreeze` only swaps the current purchase level, not all future levels. Need to verify what data exists in the read buffer for far-future levels.
- **CRITICAL SUBTLETY:** The read key for far-future levels (e.g., level 50 when current is level 5) may point to an empty buffer because the swap only happens for `purchaseLevel` (current level + 1). Far-future levels may only have data in the write buffer.

**Fix Option B: Add `rngLockedFlag` guard to purchase functions**

```solidity
// MintModule _purchaseFor:
function _purchaseFor(...) private {
    if (rngLockedFlag) revert RngLocked();
    // ...
}
```

- Pros: Blocks ALL ticket writes during commitment window, comprehensive protection
- Cons: Blocks legitimate purchases during jackpot phase (may be intentionally allowed for UX reasons), broader impact on game mechanics

**Fix Option C: Snapshot far-future queue lengths at swap time**

- Store queue lengths at `_swapAndFreeze` time, use snapshots in `_awardFarFutureCoinJackpot` for modular index calculation
- Pros: Allows continued purchases without affecting outcome
- Cons: Higher complexity, additional storage writes, more gas

**Recommendation:** Fix Option A is the most natural fix IF the read buffer has data for far-future levels. If not, Fix Option B or a variation (guard ticket queuing specifically, not all purchases) may be needed. The planner should verify read buffer contents for far-future levels as a prerequisite task.

### Pattern Scan Methodology (TQ-03)

**Definition of commitment window violation:** Any state that:
1. Is READ during VRF-dependent outcome computation (any function called with rngWord as input)
2. Can be WRITTEN by a permissionless external function
3. Is NOT protected during the commitment window (rngLockedFlag period) by any guard

**Scan scope:** All VRF-dependent outcome computations identified in Phase 68-69:
- Category 1: ETH jackpot winners (payDailyJackpot)
- Category 2: BURNIE jackpot winners (payDailyJackpotCoinAndTickets, payDailyCoinJackpot)
- Category 3: Lootbox index assignment
- Category 4: Coinflip resolution
- Category 5: Redemption roll
- Category 6: Degenerette resolution
- Category 7: Gap day backfill
- Category 8: Ticket processing trait generation
- Category 9: Reward jackpots
- Category 10: Final day DGNRS reward

**Scan procedure per category:**
1. List every storage variable READ during outcome computation
2. For each variable, identify all permissionless external functions that can WRITE it
3. For each writer, check: is it blocked by `rngLockedFlag`, `prizePoolFrozen`, double-buffer (correctly using read key), day+1 keying, or other guard?
4. If no guard prevents write during commitment window AND the write can influence the outcome -> VULNERABLE

**Contracts to scan (28 total):**
- Core: DegenerusGame.sol, DegenerusAdmin.sol
- Storage: DegenerusGameStorage.sol
- Modules (12): AdvanceModule, BoonModule, DecimatorModule, DegeneretteModule, EndgameModule, GameOverModule, JackpotModule, LootboxModule, MintModule, MintStreakUtils, PayoutUtils, WhaleModule
- Token: BurnieCoinflip.sol, BurnieCoin.sol, DegenerusStonk.sol, StakedDegenerusStonk.sol
- Other: DegenerusAffiliate.sol, DegenerusDeityPass.sol, DegenerusJackpots.sol, DegenerusQuests.sol, DegenerusTraitUtils.sol, DegenerusVault.sol, DeityBoonViewer.sol

**High-priority targets for similar patterns:**
1. `traitBurnTicket` -- populated by `processTicketBatch`, read during jackpot winner selection. LIKELY SAFE (populated by advanceGame itself, not permissionless external callers)
2. `autoRebuyState` -- read during jackpot credit flow. SAFE (setAutoRebuy has `rngLockedFlag` guard at DegenerusGame:1494)
3. `deityBySymbol` -- virtual deity entries in jackpot. SAFE (purchaseDeityPass has `rngLockedFlag` guard at WhaleModule:475)
4. `currentPrizePool` -- jackpot budget calculation. SAFE (prizePoolFrozen during jackpot phase)
5. Far-future queue via `_tqWriteKey` in `sampleFarFutureTickets` -- VIEW ONLY (DegenerusGame:2683), no outcome effect

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Commitment window analysis | Ad-hoc checking | Systematic backward trace from every RNG consumer | Prior audits missed this bug because they only traced forward from VRF delivery |
| Pattern scan | Spot-checking known patterns | Exhaustive enumeration of all reads during outcome computation | The bug was at the seam between two correct subsystems -- queue management and RNG delivery |

## Common Pitfalls

### Pitfall 1: Confusing Read Key and Write Key
**What goes wrong:** Phase 69 verdict states "ticketQueue[readKey] is the far-future winner pool" but `_awardFarFutureCoinJackpot` actually uses `_tqWriteKey`.
**Why it happens:** The double-buffer is complex; most ticket processing correctly uses the read key (processTicketBatch), so auditors assume all reads do.
**How to avoid:** Grep for EVERY call to `_tqWriteKey` and `_tqReadKey` -- verify each is using the correct slot for its context.
**Warning signs:** Any VRF-dependent function reading from the write buffer.

### Pitfall 2: Assuming rngLockedFlag Guards All Permissionless Actions
**What goes wrong:** Purchase functions (MintModule) have no `rngLockedFlag` check.
**Why it happens:** Not all permissionless actions need this guard -- most writes during the commitment window are harmless because of other protections (double-buffer, day+1 keying, freeze). But when the double-buffer is bypassed (reading from write slot), the missing guard becomes exploitable.
**How to avoid:** For each "SAFE" verdict, verify the stated protection mechanism actually applies to the specific code path.

### Pitfall 3: Forward-Only Trace Missing Seam Bugs
**What goes wrong:** Tracing forward from VRF delivery ("where does the word go?") misses cases where the word reaches a consumer that reads uncommitted state.
**Why it happens:** Forward trace validates the RNG pipeline, not the data it operates on.
**How to avoid:** ALWAYS trace backward from every RNG consumer: "What state does this function read? Was that state committed before the VRF word was requestable?"

### Pitfall 4: Incorrectly Assuming Fix Option A Works for Far-Future Levels
**What goes wrong:** Changing `_tqWriteKey` to `_tqReadKey` in `_awardFarFutureCoinJackpot` might make the function read from empty buffers for far-future levels.
**Why it happens:** `_swapTicketSlot` only swaps for `purchaseLevel` (current level + 1). Far-future levels (lvl+5 to lvl+99) may never have had their buffers swapped.
**How to avoid:** Trace the full lifecycle of a far-future ticket: when is it written, which buffer does it land in, when (if ever) does that buffer get swapped to become the read buffer?

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Foundry (forge) + Hardhat |
| Config file | foundry.toml, hardhat.config.js |
| Quick run command | `forge test --match-path test/foundry/*.t.sol -vv` |
| Full suite command | `npx hardhat test && forge test` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| TQ-01 | Exploitation scenario documented | manual-only | N/A -- audit documentation deliverable | N/A |
| TQ-02 | Fix identified and verified | manual-only | N/A -- code review deliverable (fix may require contract edit) | N/A |
| TQ-03 | Cross-contract pattern scan complete | manual-only | N/A -- audit documentation deliverable | N/A |

### Sampling Rate
- **Per task commit:** Not applicable -- this phase produces audit documentation, not code changes
- **Per wave merge:** Visual inspection of documented findings
- **Phase gate:** All three requirements addressed with verdicts in audit artifact

### Wave 0 Gaps
None -- this phase is purely documentation/analysis, no test infrastructure needed.

## Code Examples

### Reading VRF Word From Storage (Attacker Perspective)

```javascript
// Attacker reads rngWordCurrent (slot 4) after VRF fulfillment
const word = await ethers.provider.getStorageAt(gameProxyAddress, 4);
// word is now known before payDailyJackpotCoinAndTickets executes
```

### Entropy Derivation in _awardFarFutureCoinJackpot

```solidity
// Source: contracts/modules/DegenerusGameJackpotModule.sol:2529-2548
uint256 entropy = rngWord ^
    (uint256(lvl) << 192) ^
    uint256(FAR_FUTURE_COIN_TAG);  // keccak256("far-future-coin")

for (uint8 s; s < 10; ) {
    entropy = EntropyLib.entropyStep(entropy ^ uint256(s));
    uint24 candidate = lvl + 5 + uint24(entropy % 95);
    // Attacker can precompute 'candidate' and 'idx' from known rngWord
    address[] storage queue = ticketQueue[_tqWriteKey(candidate)];
    uint256 idx = (entropy >> 32) % queue.length;
    // ...
}
```

### Guards Present on Other Permissionless Functions

```solidity
// WhaleModule:475 -- deity pass purchase IS guarded
function _purchaseDeityPass(address buyer, uint8 symbolId) private {
    if (rngLockedFlag) revert RngLocked();  // GUARDED
    // ...
}

// DegenerusGame:1494 -- auto-rebuy IS guarded
function _setAutoRebuy(address player, bool enabled) private {
    if (rngLockedFlag) revert RngLocked();  // GUARDED
    // ...
}

// MintModule:619 -- purchase is NOT guarded
function _purchaseFor(...) private {
    if (gameOver) revert E();       // Only gameOver check
    uint24 purchaseLevel = level + 1;
    // NO rngLockedFlag check
    // ...
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Forward-only VRF trace | Forward + backward trace with commitment window analysis | v3.8 (this milestone) | Catches seam bugs between subsystems |
| Per-variable isolated verdicts | Cross-reference proof with all permissionless paths | Phase 69 | 87 paths enumerated, but missed the _tqWriteKey vs _tqReadKey distinction |

**Phase 69 verdict revision needed:**
- ticketQueue[key] (slot 15) verdict should be revised from unconditional SAFE to SAFE-with-exception: the double-buffer protects processTicketBatch (which uses `_tqReadKey`) but does NOT protect `_awardFarFutureCoinJackpot` (which uses `_tqWriteKey`)

## Open Questions

1. **What data exists in the read buffer for far-future levels?**
   - What we know: `_swapTicketSlot` swaps only for `purchaseLevel` (current level + 1). Far-future levels (5-99 levels ahead) may never have their buffers swapped.
   - What's unclear: Whether Fix Option A (`_tqReadKey` in `_awardFarFutureCoinJackpot`) would cause the function to always read empty queues for far-future levels, making it non-functional.
   - Recommendation: Trace the buffer swap history across multiple levels to determine if far-future levels' write buffers eventually become read buffers as levels advance. This should be a Wave 1 task.

2. **Is `purchaseCoin()` also unguarded?**
   - What we know: `_purchaseCoinFor` (MintModule:591-617) also has no `rngLockedFlag` check. It calls `_callTicketPurchase` which calls `_queueTicketsScaled`.
   - What's unclear: Whether the COIN_PURCHASE_CUTOFF guard (line 602) effectively blocks purchases during jackpot phase due to elapsed time.
   - Recommendation: Check whether `COIN_PURCHASE_CUTOFF` would typically have been exceeded by the time jackpot phase begins.

3. **Is the vulnerability exploitable during mid-day VRF (requestLootboxRng)?**
   - What we know: `requestLootboxRng` does NOT set `rngLockedFlag = true` (confirmed at AdvanceModule:1156). Mid-day VRF callback goes to the `else` branch in `rawFulfillRandomWords` which does NOT use `_awardFarFutureCoinJackpot`.
   - Recommendation: Confirm that mid-day VRF path never calls far-future jackpot functions. This should be a quick verification task.

## Sources

### Primary (HIGH confidence)
- Direct code inspection of contracts/modules/DegenerusGameJackpotModule.sol:2544 -- confirmed `_tqWriteKey` usage
- Direct code inspection of contracts/modules/DegenerusGameMintModule.sol:619-680 -- confirmed no `rngLockedFlag` guard
- Direct code inspection of contracts/storage/DegenerusGameStorage.sol:696-718 -- double-buffer mechanism
- Direct code inspection of contracts/modules/DegenerusGameAdvanceModule.sol:220-384 -- advanceGame flow
- audit/v3.8-commitment-window-inventory.md:1416-1423 -- Phase 69 verdict (contains the incorrect claim)
- Project memory: feedback_rng_backward_trace.md, feedback_rng_commitment_window.md -- confirms this is the known surviving bug

### Secondary (MEDIUM confidence)
- Phase 69 cross-reference proof (87 permissionless paths) -- comprehensive but missed the write key distinction

## Metadata

**Confidence breakdown:**
- Vulnerability identification: HIGH -- directly verified in source code; `_tqWriteKey` at JackpotModule:2544 is unambiguous
- Attack sequence: HIGH -- traced through code with concrete line references
- Fix options: MEDIUM -- Option A needs verification of far-future buffer contents; Option B is straightforward but has UX implications
- Pattern scan methodology: HIGH -- well-defined based on 4 prior phases of commitment window analysis

**Research date:** 2026-03-22
**Valid until:** Indefinite (code analysis, not version-dependent)
