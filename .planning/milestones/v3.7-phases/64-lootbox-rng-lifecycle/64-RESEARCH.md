# Phase 64: Lootbox RNG Lifecycle - Research

**Researched:** 2026-03-22
**Domain:** Lootbox RNG index lifecycle, VRF word storage, entropy derivation, and purchase-to-open trace
**Confidence:** HIGH

## Summary

This phase audits the complete lootbox RNG lifecycle: from purchase (where `lootboxRngIndex` is read and stored in the purchase record) through VRF fulfillment (where the matching word is written to `lootboxRngWordByIndex`) to opening (where the word is consumed for entropy derivation). The scope covers five requirements: index mutation mapping (LBOX-01), word-to-index correctness (LBOX-02), EntropyLib zero-state guards (LBOX-03), per-player entropy uniqueness (LBOX-04), and full lifecycle trace (LBOX-05).

The codebase uses a 1-based `lootboxRngIndex` that advances on each fresh VRF request (daily or mid-day). Purchases record the current index. When VRF fulfills, the word is stored at `lootboxRngWordByIndex[index - 1]`. Opening requires `lootboxRngWordByIndex[index] != 0`, creating a natural "RngNotReady" gate. The entropy derivation chain is `keccak256(abi.encode(rngWord, player, day, amount))` followed by `EntropyLib.entropyStep` for sub-selections, producing unique per-player per-purchase entropy.

**Primary recommendation:** The audit should systematically enumerate all `lootboxRngIndex` mutation sites (4 total: `_finalizeRngRequest` fresh, `requestLootboxRng`, `_backfillOrphanedLootboxIndices` implicit, coordinator swap implicit), all `lootboxRngWordByIndex` write sites (5 total), verify zero-state guards at every VRF word source, prove entropy uniqueness via keccak256 preimage analysis, and trace the full lifecycle end-to-end with a findings document.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| LBOX-01 | All lootboxRngIndex mutation points mapped and verified -- increment on fresh, increment on mid-day, no increment on retry | Section "lootboxRngIndex Mutation Points" -- 4 mutation sites enumerated with conditions |
| LBOX-02 | lootboxRngWordByIndex stores correct word at correct index for every VRF fulfillment path | Section "lootboxRngWordByIndex Write Sites" -- 5 write sites mapped across daily, mid-day, stale, backfill, and orphan paths |
| LBOX-03 | EntropyLib xorshift zero-state guards verified -- word==0 to word=1 at all VRF word sources | Section "Zero-State Guard Inventory" -- all VRF word injection points traced |
| LBOX-04 | Lootbox open entropy derivation produces unique tickets per purchase (keccak256 inputs verified) | Section "Entropy Derivation Analysis" -- keccak256 preimage uniqueness proven by distinct input tuples |
| LBOX-05 | Full purchase-to-open lifecycle traced -- ticket purchase through VRF to prize determination | Section "Full Lifecycle Trace" -- 6-step lifecycle from purchase to prize determination |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Foundry (forge) | Latest | Fuzz/invariant testing, gas profiling | Already configured in foundry.toml; project standard |
| forge-std | Latest | Test assertions, vm cheatcodes | Already in lib/ |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| MockVRFCoordinator | Custom (contracts/mocks/) | Simulates Chainlink VRF V2.5 coordinator | All VRF tests |
| VRFHandler | Custom (test/fuzz/helpers/) | Wraps mock VRF for invariant testing | Reuse in new fuzz/invariant tests |
| DeployProtocol | Custom (test/fuzz/helpers/) | Full protocol deployment for testing | Base contract for all new test files |

### Existing Test Infrastructure
| File | Purpose | Reusable? |
|------|---------|-----------|
| test/fuzz/VRFCore.t.sol | VRF core lifecycle tests (Phase 63) | Yes -- extend patterns for lootbox-specific tests |
| test/fuzz/VRFLifecycle.t.sol | Basic VRF fulfillment + level advancement | Yes -- has lootbox purchase helpers |
| test/fuzz/StallResilience.t.sol | Stall/swap/resume integration tests | Yes -- pattern for gap backfill tests |
| test/fuzz/helpers/DeployProtocol.sol | Full protocol deployment | Yes -- inherit for all new tests |
| test/fuzz/helpers/VRFHandler.sol | VRF fulfillment handler for fuzzing | Yes -- use for invariant tests |

**Installation:** No new packages needed.

## Architecture Patterns

### lootboxRngIndex Mutation Points (LBOX-01)

The `lootboxRngIndex` variable (type `uint48`, initialized to 1 in Storage) is the core state that links purchases to VRF words. Every mutation point MUST be enumerated.

**Mutation Site 1: `_finalizeRngRequest` (daily fresh request) -- AdvanceModule line 1277**
```solidity
// contracts/modules/DegenerusGameAdvanceModule.sol:1267-1280
function _finalizeRngRequest(bool isTicketJackpotDay, uint24 lvl, uint256 requestId) private {
    bool isRetry = vrfRequestId != 0 && rngRequestTime != 0 && rngWordCurrent == 0;
    if (!isRetry) {
        lootboxRngIndex++;              // <-- MUTATION: fresh daily request
        lootboxRngPendingEth = 0;
        lootboxRngPendingBurnie = 0;
    }
    // Retry: no increment (correct -- same lootbox round)
    vrfRequestId = requestId;
    rngWordCurrent = 0;
    rngRequestTime = uint48(block.timestamp);
    rngLockedFlag = true;
}
```
**Condition:** `isRetry == false` (fresh request, not timeout retry).
**Called by:** `_requestRng` (daily path from `rngGate`) and `_tryRequestRng` (gameover path).

**Mutation Site 2: `requestLootboxRng` (mid-day request) -- AdvanceModule line 738**
```solidity
// contracts/modules/DegenerusGameAdvanceModule.sol:726-743
uint256 id = vrfCoordinator.requestRandomWords(...);
lootboxRngIndex++;                    // <-- MUTATION: mid-day request
lootboxRngPendingEth = 0;
lootboxRngPendingBurnie = 0;
vrfRequestId = id;
rngWordCurrent = 0;
rngRequestTime = uint48(block.timestamp);
```
**Condition:** Always increments (no retry concept for mid-day; guards prevent double-call).
**Guards:** `rngLockedFlag == false`, `rngRequestTime == 0`, today's daily RNG recorded, not in 15-min window, LINK balance sufficient, pending value above threshold.

**Non-Mutation (verified): Retry path in `_finalizeRngRequest` -- AdvanceModule line 1275-1280**
When `isRetry == true`, the `lootboxRngIndex++` is skipped. This is correct: the previous fresh request already advanced the index, and the retry should fill the same slot.

**Non-Mutation (verified): `updateVrfCoordinatorAndSub` -- AdvanceModule line 1338-1367**
Coordinator swap does NOT touch `lootboxRngIndex`. The current index value persists. Any orphaned index (where a word was never written) is handled by `_backfillOrphanedLootboxIndices` on the next successful VRF fulfillment.

**Summary table:**

| Site | Function | Line | When | Increments? |
|------|----------|------|------|-------------|
| 1 | `_finalizeRngRequest` | 1277 | Fresh daily/gameover request | YES (isRetry==false) |
| 2 | `requestLootboxRng` | 738 | Mid-day standalone request | YES (always) |
| 3 | `_finalizeRngRequest` | 1275-1280 | Timeout retry (12h) | NO (isRetry==true) |
| 4 | `updateVrfCoordinatorAndSub` | 1338-1367 | Coordinator swap | NO (not touched) |

### lootboxRngWordByIndex Write Sites (LBOX-02)

Every path that writes to `lootboxRngWordByIndex[index]` must be mapped and verified for index correctness.

**Write Site 1: `rawFulfillRandomWords` daily branch (via `_finalizeLootboxRng`) -- AdvanceModule line 826**
```solidity
// In rngGate, after _applyDailyRng:
_finalizeLootboxRng(currentWord);    // line 826

// _finalizeLootboxRng implementation:
function _finalizeLootboxRng(uint256 rngWord) private {
    uint48 index = lootboxRngIndex - 1;              // Points to most recent reserved index
    if (lootboxRngWordByIndex[index] != 0) return;   // Already filled (idempotent)
    lootboxRngWordByIndex[index] = rngWord;           // <-- WRITE
    lastLootboxRngWord = rngWord;
    emit LootboxRngApplied(index, rngWord, vrfRequestId);
}
```
**Index used:** `lootboxRngIndex - 1` (the index that was just reserved by `_finalizeRngRequest`'s `lootboxRngIndex++`).
**Zero guard:** `if (word == 0) word = 1` in `rawFulfillRandomWords` line 1410, AND `_applyDailyRng` preserves nonzero (adds nudges to nonzero word).
**Idempotency:** `if (lootboxRngWordByIndex[index] != 0) return` prevents double-write.

**Write Site 2: `rawFulfillRandomWords` mid-day branch -- AdvanceModule line 1418**
```solidity
// contracts/modules/DegenerusGameAdvanceModule.sol:1412-1422
if (rngLockedFlag) {
    rngWordCurrent = word;           // Daily: store for advanceGame
} else {
    uint48 index = lootboxRngIndex - 1;
    lootboxRngWordByIndex[index] = word;     // <-- WRITE (mid-day direct)
    emit LootboxRngApplied(index, word, requestId);
    vrfRequestId = 0;
    rngRequestTime = 0;
}
```
**Index used:** `lootboxRngIndex - 1` (reserved by `requestLootboxRng`'s `lootboxRngIndex++`).
**Zero guard:** `if (word == 0) word = 1` on line 1410.

**Write Site 3: Stale daily word redirect -- AdvanceModule line 788**
```solidity
// In rngGate, when requestDay < day (stale word from previous day):
_finalizeLootboxRng(currentWord);    // <-- WRITE (reuses _finalizeLootboxRng)
rngWordCurrent = 0;
_requestRng(isTicketJackpotDay, lvl);
```
**Index used:** Same `lootboxRngIndex - 1` logic. The stale word is used for lootbox only.
**Zero guard:** `if (word == 0) word = 1` in `rawFulfillRandomWords`.

**Write Site 4: `_backfillOrphanedLootboxIndices` -- AdvanceModule line 1466**
```solidity
// contracts/modules/DegenerusGameAdvanceModule.sol:1456-1472
function _backfillOrphanedLootboxIndices(uint256 vrfWord) private {
    uint48 idx = lootboxRngIndex;
    if (idx <= 1) return;
    for (uint48 i = idx - 1; i >= 1;) {
        if (lootboxRngWordByIndex[i] != 0) break;    // Hit filled index, done
        uint256 fallbackWord = uint256(keccak256(abi.encodePacked(vrfWord, i)));
        if (fallbackWord == 0) fallbackWord = 1;      // <-- ZERO GUARD
        lootboxRngWordByIndex[i] = fallbackWord;       // <-- WRITE
        lastLootboxRngWord = fallbackWord;
        emit LootboxRngApplied(i, fallbackWord, 0);
        unchecked { --i; }
    }
}
```
**Index used:** Scans backwards from `lootboxRngIndex - 1` until hitting a filled index.
**Zero guard:** `if (fallbackWord == 0) fallbackWord = 1`.
**Purpose:** Fills orphaned indices from coordinator swap + stall.

**Write Site 5: Game-over paths via `_finalizeLootboxRng` -- AdvanceModule lines 888, 917**
```solidity
// _gameOverEntropy normal VRF path (line 888):
_finalizeLootboxRng(currentWord);

// _gameOverEntropy fallback path (line 917):
_finalizeLootboxRng(fallbackWord);
```
**Index used:** Same `lootboxRngIndex - 1` via `_finalizeLootboxRng`.
**Zero guard:** fallbackWord gets `if (fallbackWord == 0) fallbackWord = 1` in `_getHistoricalRngFallback`'s keccak256 output. Actually -- `_getHistoricalRngFallback` does NOT have an explicit zero guard. The keccak256 output is astronomically unlikely to be 0, but must be flagged.

**AUDIT NOTE (potential finding):** `_getHistoricalRngFallback` returns `uint256(keccak256(abi.encodePacked(combined, currentDay, block.prevrandao)))`. This is overwhelmingly unlikely to be 0, but unlike all other VRF word sources, there is no explicit `if (word == 0) word = 1` guard. The `_applyDailyRng` function called on the result adds nudges, but if nudges are 0, the raw fallback word flows through. `_finalizeLootboxRng` then stores it. If it were 0, `openLootBox` would see `rngWord == 0` and revert `RngNotReady` permanently for that index -- a liveness issue. Severity: INFO (probability ~2^-256).

### Zero-State Guard Inventory (LBOX-03)

EntropyLib's `entropyStep` is an xorshift PRNG: `state ^= state << 7; state ^= state >> 9; state ^= state << 8`. If the input state is 0, ALL steps produce 0 (xorshift fixed point). This is catastrophic for entropy.

**VRF word injection points where zero guard is required:**

| Site | Location | Zero Guard | Status |
|------|----------|------------|--------|
| `rawFulfillRandomWords` | AdvanceModule:1410 | `if (word == 0) word = 1` | GUARDED |
| `_backfillGapDays` | AdvanceModule:1444 | `if (derivedWord == 0) derivedWord = 1` | GUARDED |
| `_backfillOrphanedLootboxIndices` | AdvanceModule:1465 | `if (fallbackWord == 0) fallbackWord = 1` | GUARDED |
| `_getHistoricalRngFallback` | AdvanceModule:962 | **NONE** | UNGUARDED (INFO-level, 2^-256 probability) |
| `_applyDailyRng` | AdvanceModule:1478-1488 | `rawWord + nudges` (if nudges > 0); no guard if nudges == 0 | DEPENDS ON INPUT |

**Critical analysis:** `_applyDailyRng` receives a word that has already been zero-guarded at `rawFulfillRandomWords` (line 1410). The daily path is: VRF word -> zero guard -> `rngWordCurrent = word` -> `rngGate` reads `rngWordCurrent` -> `_applyDailyRng(day, currentWord)`. The input is guaranteed nonzero.

**For the gameover fallback path:** `_getHistoricalRngFallback` -> `_applyDailyRng` -> `_finalizeLootboxRng`. If `_getHistoricalRngFallback` returned 0 AND nudges are 0, the lootbox word would be 0. This is the only unguarded path. Risk: negligible (keccak256 preimage for 0 is infeasible).

**EntropyLib consumption sites in lootbox flow:**
- `_rollTargetLevel`: `EntropyLib.entropyStep(entropy)` where entropy = `keccak256(rngWord, player, day, amount)`. Since `rngWord != 0` (guarded at storage time by `RngNotReady` check), and keccak256 of nonzero input is overwhelmingly nonzero, this is safe.
- `_resolveLootboxRoll`: Multiple `EntropyLib.entropyStep(nextEntropy)` calls -- each step's input is the output of a previous step seeded from keccak256 of a VRF word. Safe.
- `_lootboxTicketCount`: `EntropyLib.entropyStep(entropy)` -- same chain. Safe.

### Entropy Derivation Analysis (LBOX-04)

The core entropy derivation for lootbox opening is:

**ETH Lootbox (LootboxModule line 570):**
```solidity
uint256 entropy = uint256(keccak256(abi.encode(rngWord, player, day, amount)));
```

**BURNIE Lootbox (LootboxModule line 644):**
```solidity
uint256 entropy = uint256(keccak256(abi.encode(rngWord, player, day, amountEth)));
```

**Uniqueness proof:** For any two distinct `(player, day, amount)` tuples with the same `rngWord`, the keccak256 preimage is distinct, producing distinct entropy. For the same player purchasing on the same day:
- If amounts differ: distinct preimage -> distinct entropy.
- If amounts are identical: same preimage -> same entropy. BUT this cannot happen because `lootboxEth[index][player]` accumulates (line 716: `newAmount = existingAmount + boostedAmount`), so the `amount` stored in the packed value is the TOTAL for that player at that index, not per-purchase. Multiple purchases in the same day accumulate into a single `amount` value.

**Same player, same day, same RNG index, same amount (theoretical):** This would require the player to have exactly the same accumulated lootbox amount for two different RNG indices on the same day. Since `lootboxRngIndex` changes between daily advances, the `rngWord` would differ, making the preimage distinct.

**Degenerette bets (DegeneretteModule line 597-618):**
```solidity
uint256 rngWord = lootboxRngWordByIndex[index];
// Per-spin entropy:
uint256 resultSeed = spinIdx == 0
    ? uint256(keccak256(abi.encodePacked(rngWord, index, QUICK_PLAY_SALT)))
    : uint256(keccak256(abi.encodePacked(rngWord, index, spinIdx, QUICK_PLAY_SALT)));
```
Uniqueness: Different `spinIdx` values produce different preimages. `QUICK_PLAY_SALT` is a constant that prevents cross-function collision.

**Redemption lootbox (Game.sol line 1841):**
```solidity
rngWord = uint256(keccak256(abi.encode(rngWord)));
```
Each 5 ETH chunk uses a chained keccak hash of the previous rngWord, ensuring distinct entropy per chunk.

### Full Lifecycle Trace (LBOX-05)

**Step 1: Purchase**
Player calls `purchaseCoin` / `purchaseWhaleBundle` / `purchaseBurnieLootbox`, which delegatecalls to MintModule/WhaleModule.

- MintModule reads `lootboxRngIndex` (line 686): `uint48 index = lootboxRngIndex;`
- Records purchase: `lootboxEth[index][buyer] = (uint256(purchaseLevel) << 232) | newAmount;` (line 716)
- Records day: `lootboxDay[index][buyer] = day;` (line 694)
- Records base level: `lootboxBaseLevelPacked[index][buyer] = uint24(level + 2);` (line 695)
- Records activity score: `lootboxEvScorePacked[index][buyer] = uint16(score + 1);` (line 696-697)
- Accumulates pending ETH: `lootboxRngPendingEth += lootBoxAmount;` (line 1075)
- Same-day guard: `if (storedDay != day) revert E();` (line 700) prevents cross-day accumulation

**Step 2: VRF Request**
Either daily (`advanceGame` -> `rngGate` -> `_requestRng`) or mid-day (`requestLootboxRng`):
- `lootboxRngIndex++` (fresh request only)
- `lootboxRngPendingEth = 0; lootboxRngPendingBurnie = 0;`
- New purchases now target `lootboxRngIndex` (the incremented value)
- Old purchases at `lootboxRngIndex - 1` await VRF word

**Step 3: VRF Fulfillment**
Chainlink calls `rawFulfillRandomWords`:
- Validates `requestId == vrfRequestId && rngWordCurrent == 0`
- Zero guard: `if (word == 0) word = 1;`
- Daily path (`rngLockedFlag == true`): `rngWordCurrent = word;` (stored for advanceGame)
- Mid-day path (`rngLockedFlag == false`): `lootboxRngWordByIndex[lootboxRngIndex - 1] = word;` (direct)

**Step 4: Daily Processing (daily path only)**
`advanceGame` -> `rngGate`:
- `_applyDailyRng(day, currentWord)` -- adds nudges, stores to `rngWordByDay[day]`
- `_finalizeLootboxRng(currentWord)` -- stores to `lootboxRngWordByIndex[lootboxRngIndex - 1]`
- Sets `lastLootboxRngWord = rngWord` for ticket processing entropy

**Step 5: RngNotReady Guard (opening)**
Player calls `openLootBox(player, lootboxIndex)`:
- Reads `rngWord = lootboxRngWordByIndex[index];` (LootboxModule line 549)
- `if (rngWord == 0) revert RngNotReady();` (line 550)
- This gate prevents premature opening before VRF fulfillment

**Step 6: Prize Determination**
- Derives entropy: `keccak256(abi.encode(rngWord, player, day, amount))` (line 570)
- Rolls target level: `_rollTargetLevel(baseLevel, entropy)` (line 571)
- Resolves lootbox: `_resolveLootboxCommon(...)` (line 599)
  - Ticket roll (55% chance): `EntropyLib.entropyStep` chain for ticket count with variance
  - DGNRS reward (10% chance): `EntropyLib.entropyStep` for amount
  - WWXRP reward (10% chance): fixed 1 token
  - Large BURNIE (25% chance): `EntropyLib.entropyStep` for variance roll
  - Boon draw: additional entropy chain if allowed

### Consumers of `lootboxRngWordByIndex` (Cross-Reference)

| Consumer | Contract | Purpose | Index Source |
|----------|----------|---------|-------------|
| `openLootBox` | LootboxModule:549 | ETH lootbox opening | Caller-provided `index` parameter |
| `openBurnieLootBox` | LootboxModule:627 | BURNIE lootbox opening | Caller-provided `index` parameter |
| `_resolveFullTicketBet` | DegeneretteModule:597 | Degenerette bet resolution | Stored in packed bet at placement time |
| Mid-day ticket drain | AdvanceModule:167 | `lastLootboxRngWord` update for ticket processing | `lootboxRngIndex - 1` |

### Consumers of `lastLootboxRngWord`

| Consumer | Contract | Purpose |
|----------|----------|---------|
| `processTicketBatch` | JackpotModule:1916 | Trait assignment entropy for ticket processing |
| Mid-day drain path | AdvanceModule:170 | Updated from `lootboxRngWordByIndex[lootboxRngIndex - 1]` |

### Anti-Patterns to Avoid

- **Do not assume lootboxRngIndex starts at 0:** It is initialized to 1 in DegenerusGameStorage.sol line 1299. Index 0 is never valid.
- **Do not conflate rngWord with lootboxRngWord:** `rngWordCurrent` is the daily VRF word (consumed by `_applyDailyRng`). `lootboxRngWordByIndex` is the stored word per lootbox index. They may have the same value (daily path) or different values (mid-day path).
- **Do not ignore the mid-day ticket drain flow:** When `midDayTicketRngPending == true`, the mid-day `advanceGame` path (line 166-171) reads `lootboxRngWordByIndex[lootboxRngIndex - 1]` and updates `lastLootboxRngWord`. This is a separate consumption path from `openLootBox`.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| VRF mock | Custom VRF simulation | MockVRFCoordinator.sol | Already handles fulfillRandomWords + fulfillRandomWordsRaw |
| Protocol deployment | Manual contract setup | DeployProtocol.sol | Deploys all 23 contracts with correct addresses |
| VRF fulfillment handler | Manual fulfill in tests | VRFHandler.sol | Wraps mock with ghost tracking |
| Gas profiling | Manual opcode counting | forge test --gas-report | Foundry native is more accurate |

## Common Pitfalls

### Pitfall 1: Index Off-by-One Between Purchase and Write
**What goes wrong:** Purchases read `lootboxRngIndex` as their target. The VRF word is written to `lootboxRngWordByIndex[lootboxRngIndex - 1]` AFTER `lootboxRngIndex++`. If the increment happens at the wrong time, purchases and words would be misaligned.
**Why it happens:** The increment happens at VRF REQUEST time, not at fulfillment time. This means all purchases BEFORE the request see `index = N`, then `lootboxRngIndex++` makes it `N+1`, and the word is written at slot `N+1 - 1 = N`. This is CORRECT.
**How to verify:** Trace the sequence: purchase sees `lootboxRngIndex = N` -> request fires -> `lootboxRngIndex = N+1` -> VRF fulfills -> writes to `lootboxRngWordByIndex[N+1-1] = lootboxRngWordByIndex[N]`. Purchase at index N opens with word at index N.
**Warning signs:** `openLootBox` reverts with `RngNotReady` for indices that should have been filled.

### Pitfall 2: Mid-day `requestLootboxRng` Increments Before VRF Arrives
**What goes wrong:** `requestLootboxRng` increments `lootboxRngIndex` immediately (line 738). New purchases after this call target the NEW index. But the VRF word for the OLD index has not arrived yet.
**Why it happens:** By design -- the increment separates "purchases awaiting this word" from "new purchases". The `RngNotReady` guard on `openLootBox` prevents premature opening.
**How to verify:** Confirm that between `requestLootboxRng` and the VRF callback, any calls to `openLootBox(player, oldIndex)` revert with `RngNotReady`, and after callback they succeed.
**Warning signs:** Players can open lootboxes before VRF fulfillment.

### Pitfall 3: EntropyLib Zero State Propagation
**What goes wrong:** If `entropyStep(0)` is called, it returns 0. All subsequent steps also return 0. All lootbox rolls would produce deterministic, exploitable results.
**Why it happens:** Xorshift has a fixed point at 0.
**How to verify:** Confirm `rngWord == 0` is guarded at every VRF injection point (already mapped in "Zero-State Guard Inventory"). Also confirm `openLootBox` gates on `rngWord == 0` (it does: LootboxModule line 550).
**Warning signs:** Multiple players getting identical lootbox outcomes.

### Pitfall 4: Orphaned Index After Coordinator Swap
**What goes wrong:** A coordinator swap clears `vrfRequestId`, `rngRequestTime`, and `rngWordCurrent` but does NOT touch `lootboxRngIndex` or `lootboxRngWordByIndex`. If a request was in-flight, the index was already incremented but the word was never delivered.
**Why it happens:** The swap resets VRF state but preserves game state.
**How to avoid:** `_backfillOrphanedLootboxIndices` (line 1456) scans backwards on the next successful VRF fulfillment and fills empty indices with keccak256-derived words.
**Warning signs:** `lootboxRngWordByIndex[index] == 0` for indices less than `lootboxRngIndex`.

### Pitfall 5: Same Player Multiple Purchases Across RNG Index Boundary
**What goes wrong:** Player purchases at index N. Daily advance fires, `lootboxRngIndex` becomes N+1. Player purchases again -- now at index N+1. Player has lootboxes at two different indices.
**Why it happens:** This is correct behavior. Each index is an independent "lootbox round." The player opens each independently with the respective word.
**How to verify:** Confirm `openLootBox` takes an explicit `lootboxIndex` parameter and uses the corresponding word.
**Warning signs:** Player cannot open lootbox because they use wrong index.

### Pitfall 6: DegeneretteModule Uses lootboxRngWordByIndex Directly
**What goes wrong:** Degenerette bets record `lootboxRngIndex` at bet time (DegeneretteModule line 473) and resolve using `lootboxRngWordByIndex[index]` (line 597). If the index-to-word mapping is broken, bets resolve with wrong entropy.
**Why it happens:** Degenerette piggybacks on the lootbox RNG system.
**How to verify:** Confirm the same index-to-word guarantees apply to degenerette bets.
**Warning signs:** `RngNotReady` on bet resolution when word should be available.

## Code Examples

### Lootbox Purchase Recording (MintModule)
```solidity
// Source: contracts/modules/DegenerusGameMintModule.sol lines 686-716
uint48 index = lootboxRngIndex;                    // Read current index
uint256 packed = lootboxEth[index][buyer];         // Check existing purchase
uint256 existingAmount = packed & ((1 << 232) - 1);
if (existingAmount == 0) {
    lootboxDay[index][buyer] = day;                // First purchase at this index
    lootboxBaseLevelPacked[index][buyer] = uint24(level + 2);
    lootboxEvScorePacked[index][buyer] = uint16(score + 1);
}
uint256 newAmount = existingAmount + boostedAmount;
lootboxEth[index][buyer] = (uint256(purchaseLevel) << 232) | newAmount;
```

### Lootbox Opening Entropy Chain (LootboxModule)
```solidity
// Source: contracts/modules/DegenerusGameLootboxModule.sol lines 549-571
uint256 rngWord = lootboxRngWordByIndex[index];    // Load word for this index
if (rngWord == 0) revert RngNotReady();             // Guard: VRF not yet fulfilled

uint256 entropy = uint256(keccak256(abi.encode(rngWord, player, day, amount)));
(uint24 targetLevel, uint256 nextEntropy) = _rollTargetLevel(baseLevel, entropy);
// ... _resolveLootboxCommon uses nextEntropy for all subsequent rolls
```

### VRF Word Write (Daily Path via _finalizeLootboxRng)
```solidity
// Source: contracts/modules/DegenerusGameAdvanceModule.sol lines 845-851
function _finalizeLootboxRng(uint256 rngWord) private {
    uint48 index = lootboxRngIndex - 1;
    if (lootboxRngWordByIndex[index] != 0) return;  // Idempotent
    lootboxRngWordByIndex[index] = rngWord;
    lastLootboxRngWord = rngWord;
    emit LootboxRngApplied(index, rngWord, vrfRequestId);
}
```

### VRF Word Write (Mid-day Direct in rawFulfillRandomWords)
```solidity
// Source: contracts/modules/DegenerusGameAdvanceModule.sol lines 1415-1422
} else {
    uint48 index = lootboxRngIndex - 1;
    lootboxRngWordByIndex[index] = word;              // Direct write
    emit LootboxRngApplied(index, word, requestId);
    vrfRequestId = 0;
    rngRequestTime = 0;
}
```

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Foundry (forge) with Solidity 0.8.34 |
| Config file | foundry.toml |
| Quick run command | `forge test --match-path test/fuzz/LootboxRngLifecycle.t.sol -vvv` |
| Full suite command | `forge test --fuzz-runs 1000 -vvv` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| LBOX-01 | lootboxRngIndex increments on fresh, not on retry, not on swap | fuzz | `forge test --match-test test_lootboxRngIndex -vvv` | Wave 0 |
| LBOX-02 | lootboxRngWordByIndex stores correct word at correct index for daily/mid-day/stale/backfill/gameover | fuzz | `forge test --match-test test_lootboxWordByIndex -vvv` | Wave 0 |
| LBOX-03 | EntropyLib xorshift zero-state guards at all VRF word sources | unit | `forge test --match-test test_zeroStateGuard -vvv` | Wave 0 |
| LBOX-04 | Unique entropy per (player, day, amount) tuple via keccak256 | fuzz | `forge test --match-test test_entropyUniqueness -vvv` | Wave 0 |
| LBOX-05 | Full purchase-to-open lifecycle | integration | `forge test --match-test test_fullLifecycle -vvv` | Wave 0 |

### Sampling Rate
- **Per task commit:** `forge test --match-path test/fuzz/LootboxRngLifecycle.t.sol -vvv`
- **Per wave merge:** `forge test --fuzz-runs 1000 -vvv`
- **Phase gate:** Full suite green before verify

### Wave 0 Gaps
- [ ] `test/fuzz/LootboxRngLifecycle.t.sol` -- new file covering LBOX-01 through LBOX-05
- [ ] No new framework install needed (Foundry already configured)
- [ ] No new helpers needed (VRFHandler + DeployProtocol already exist)

## Open Questions

1. **`_getHistoricalRngFallback` missing zero guard**
   - What we know: Returns `uint256(keccak256(abi.encodePacked(combined, currentDay, block.prevrandao)))`. No explicit `if (word == 0) word = 1` guard. The result flows through `_applyDailyRng` (which adds nudges but does not guard zero if nudges == 0) and then to `_finalizeLootboxRng`.
   - What's unclear: Is this an intentional omission or oversight? Probability of keccak256 returning 0 is 2^-256.
   - Recommendation: Flag as INFO finding. Theoretically, if this returned 0 with zero nudges, `_finalizeLootboxRng` would store 0, and `openLootBox` would permanently revert `RngNotReady` for that index. The fix is trivial: add `if (fallbackWord == 0) fallbackWord = 1` after `_applyDailyRng`. The gameover path already guards via `_applyDailyRng` which won't return 0 if input is nonzero, so this is a defense-in-depth concern only.

2. **Mid-day `lastLootboxRngWord` update path**
   - What we know: The mid-day drain path (AdvanceModule line 167-170) reads `lootboxRngWordByIndex[lootboxRngIndex - 1]` and sets `lastLootboxRngWord = word`. This happens inside `advanceGame` when `day == dailyIdx` and `midDayTicketRngPending == true`.
   - What's unclear: If the mid-day VRF callback arrives but `advanceGame` is never called that day (no ticket queue to drain), does `lastLootboxRngWord` get updated? YES -- `rawFulfillRandomWords` mid-day branch does NOT update `lastLootboxRngWord`. It is only updated via `_finalizeLootboxRng` or the mid-day drain path.
   - Recommendation: Verify this path in the findings document. It is correct by design: `lastLootboxRngWord` is only needed for ticket processing entropy, and tickets are only processed via `advanceGame`, which will read the word when needed.

3. **Cross-day lootbox accumulation guard**
   - What we know: MintModule line 700: `if (storedDay != day) revert E();` prevents a player from adding to their lootbox across days for the same RNG index.
   - What's unclear: If `lootboxRngIndex` does not change across a day boundary (no VRF request that day), the player's second-day purchase would revert because `storedDay` (set on first purchase) differs from `day` (current day).
   - Recommendation: This is correct behavior -- it forces each index's purchases for a player to be within a single day. Verify and document.

## Sources

### Primary (HIGH confidence)
- contracts/modules/DegenerusGameAdvanceModule.sol lines 675-1511 -- All VRF request, fulfillment, lootbox finalization, backfill logic
- contracts/modules/DegenerusGameLootboxModule.sol lines 536-705 -- openLootBox, openBurnieLootBox, resolveLootboxDirect, resolveRedemptionLootbox
- contracts/modules/DegenerusGameMintModule.sol lines 684-1076 -- Purchase recording, lootboxRngIndex read, _purchaseBurnieLootboxFor
- contracts/modules/DegenerusGameWhaleModule.sol lines 696-745 -- _recordLootboxEntry (whale purchase path)
- contracts/modules/DegenerusGameDegeneretteModule.sol lines 462-618 -- Degenerette bet placement and resolution using lootboxRngWordByIndex
- contracts/modules/DegenerusGameJackpotModule.sol line 1916 -- lastLootboxRngWord consumption for ticket processing
- contracts/storage/DegenerusGameStorage.sol lines 1294-1348 -- Complete lootbox RNG state variable definitions
- contracts/libraries/EntropyLib.sol -- Full xorshift PRNG implementation (24 lines)
- contracts/DegenerusGame.sol lines 697-740 -- openLootBox, openBurnieLootBox proxy layer

### Secondary (MEDIUM confidence)
- .planning/phases/63-vrf-request-fulfillment-core/63-RESEARCH.md -- Phase 63 VRF core research (verified patterns reused)
- audit/KNOWN-ISSUES.md -- v3.7 Phase 63 findings (0 HIGH/MEDIUM/LOW, 2 INFO)
- audit/v3.7-vrf-core-findings.md -- VRF core findings document

### Tertiary (LOW confidence)
- None. All findings verified against source code.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All infrastructure already exists in repo
- lootboxRngIndex mutation mapping: HIGH - Complete code read of all mutation sites (4), cross-referenced with Phase 63 research
- lootboxRngWordByIndex write mapping: HIGH - Complete code read of all write sites (5), idempotency guard verified
- Zero-state guards: HIGH - All VRF injection points traced, 1 unguarded path identified (2^-256 probability)
- Entropy uniqueness: HIGH - keccak256 preimage analysis with distinct input tuples verified
- Full lifecycle: HIGH - End-to-end trace from purchase through 6 steps to prize determination

**Research date:** 2026-03-22
**Valid until:** Indefinite (auditing fixed codebase, not evolving API)
