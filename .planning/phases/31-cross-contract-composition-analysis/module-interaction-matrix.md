# Module Interaction Matrix

**Phase:** 31-03 -- Cross-Contract Composition Analysis
**Generated:** 2026-03-05
**Sources:** 31-01 storage-slot-matrix.md, 31-02 cross-module-write-analysis.md, DegenerusGame.sol, all module source files

## 10x10 Matrix Overview

```
         ADV   MINT  WHALE  LOOT   DEG   BOON   DEC   JACK   END   OVER
ADV       -    HIGH   LOW    LOW   NONE  NONE   LOW   HIGH   LOW   LOW
MINT     HIGH   -     MED    LOW   LOW   LOW    NONE  LOW    NONE  NONE
WHALE    LOW   MED     -     NONE  NONE  LOW    NONE  NONE   NONE  NONE
LOOT     LOW   LOW    NONE    -    MED   MED    MED   NONE   NONE  NONE
DEG      NONE  LOW    NONE   MED    -    LOW    NONE  NONE   NONE  NONE
BOON     NONE  LOW    LOW    MED   LOW    -     NONE  NONE   NONE  NONE
DEC      LOW   NONE   NONE   MED   NONE  NONE    -   NONE   NONE  NONE
JACK     HIGH  LOW    NONE   NONE  NONE  NONE   NONE   -     LOW   NONE
END      LOW   NONE   NONE   NONE  NONE  NONE   NONE  LOW     -    NONE
OVER     LOW   NONE   NONE   NONE  NONE  NONE   NONE  NONE   NONE   -
```

**Priority levels based on shared mutable state:**
- HIGH: Direct shared state writes within same orchestration chain
- MED: Shared state via nested delegatecall chains
- LOW: Shared state via separate entry points (no same-tx interaction)
- NONE: No shared mutable state

## High-Priority Pair Analysis

### 1. ADV <-> JACK (HIGH)

**Shared state:** currentPrizePool, nextPrizePool, futurePrizePool, claimablePool, dailyTicketBudgetsPacked, dailyEthPoolBudget

**AdvanceModule orchestration sequence within advanceGame():**

Step 1: `JACK.consolidatePrizePools(level, rngWord)` -- Moves nextPrizePool -> currentPrizePool, futurePrizePool -> nextPrizePool
Step 2: `JACK.payDailyJackpot(...)` -- Reads currentPrizePool, distributes to claimableWinnings, increments claimablePool, decrements currentPrizePool
Step 3: `JACK.payDailyCoinJackpot(...)` -- Credits BURNIE jackpots
Step 4: `MINT.processFutureTicketBatch(level)` -- Processes queued tickets, may modify ticketQueue
Step 5: `JACK.processTicketBatch(level)` -- Reads ticketCursor set by Step 4, processes burn tickets

**Inter-step consistency analysis:**

- After Step 1 (consolidatePrizePools): currentPrizePool is updated. Step 2 reads currentPrizePool -- this is correct because Step 1 sets it before Step 2 reads it.
- After Step 2 (payDailyJackpot): currentPrizePool is decremented, claimablePool incremented. Step 5 reads currentPrizePool -- by this point the value reflects post-jackpot state. This is the intended behavior (tickets processed against remaining pool).
- ticketCursor: Step 4 (MINT.processFutureTicketBatch) advances ticketCursor. Step 5 (JACK.processTicketBatch) reads ticketCursor. This is sequentially consistent -- MINT processes first, then JACK burns.

**Verdict: SAFE.** All inter-step reads occur after the corresponding writes. The orchestration sequence is deliberately ordered to ensure each step sees the correct state from prior steps.

### 2. ADV <-> MINT (HIGH)

**Shared state:** mintPacked_ (indirect), ticketQueue, ticketCursor, nextPrizePool, futurePrizePool

**Interaction path:** Within advanceGame(), ADV calls MINT.processFutureTicketBatch(level). This function:
1. Reads ticketQueue[level] starting from ticketCursor
2. Processes up to a batch size of entries
3. Advances ticketCursor

**Cursor state consistency:** ticketCursor is a single uint32 at slot 19. ADV reads it to check if processing is needed, then MINT modifies it. After MINT returns, ADV continues with the updated cursor. This is a clean read-then-write sequence with no stale reads.

**mintPacked_ interaction:** MINT.processFutureTicketBatch does NOT write mintPacked_. It only queues/processes tickets. mintPacked_ is written by MINT.recordMintData (separate entry point via purchase()). No same-tx conflict.

**Verdict: SAFE.** Sequential orchestration ensures correct cursor state.

### 3. MINT <-> WHALE (MEDIUM)

**Shared state:** mintPacked_ (LEVEL_COUNT, LAST_LEVEL, FROZEN_UNTIL_LEVEL, WHALE_BUNDLE_TYPE, DAY)

**Both modules write multiple fields in mintPacked_ for the same player.** This is the highest-risk pair.

**Call path analysis:**
- MINT writes via: purchase() -> MINT.purchase -> recordMint -> MINT.recordMintData
- WHALE writes via: purchaseWhaleBundle() -> WHALE.purchaseWhaleBundle

These are separate external entry points on DegenerusGame. Within a single transaction:
- A user can call purchaseWhaleBundle() which calls WHALE
- A user can call purchase() which calls MINT
- There is NO call path from purchase() that reaches WHALE, nor from purchaseWhaleBundle() that reaches MINT

**Can an attacker construct a transaction that triggers both?** No. Each external function on DegenerusGame calls exactly one module for mintPacked_ writes. There is no batching function that calls both purchase() and purchaseWhaleBundle() in sequence.

**Multi-call attack via contract:** An attacker contract could call purchaseWhaleBundle() then purchase() in the same tx. This would:
1. WHALE writes mintPacked_[attacker]: LEVEL_COUNT=100, FROZEN_UNTIL_LEVEL=99+level, WHALE_BUNDLE_TYPE=3, LAST_LEVEL=99+level
2. MINT reads mintPacked_[attacker]: sees the WHALE-written values. MINT's logic correctly handles frozenUntilLevel (skips level tracking if frozen). LAST_LEVEL and LEVEL_COUNT are read fresh from storage.

**This is intentionally supported behavior.** Whale bundle followed by purchase works correctly because MINT reads the current state (including WHALE's modifications) before applying its own updates.

**Verdict: SAFE.** Both modules read-modify-write mintPacked_ atomically (read current, compute new, write back). Sequential calls produce correct results regardless of ordering.

### 4. LOOT <-> BOON (MEDIUM)

**Shared state:** boon mappings (lootboxBoon5Active, coinflipBoonDay, etc.), mintPacked_ (via BOON.consumeActivityBoon)

**Interaction path:** Chain 5: LOOT.openLootBox -> BOON (various consume functions)

**Analysis:**
- LOOT generates a lootbox result based on RNG. If the result triggers a boon, LOOT delegates to BOON.
- BOON writes boon-specific mappings (coinflipBoonDay, lootboxBoon5Active, etc.) and potentially mintPacked_.LEVEL_COUNT.
- After BOON returns, LOOT continues processing the remaining lootbox result. LOOT does NOT re-read any boon state after the BOON call.

**Critical check:** Does LOOT read any state that BOON modifies?
- LOOT reads: lootboxEth, lootboxRngWordByIndex, lootboxEthTotal, lootboxEthBase
- BOON writes: boon-specific mappings, mintPacked_.LEVEL_COUNT
- **No overlap.** LOOT does not read boon mappings or mintPacked_.

**Verdict: SAFE.** No state assumption violation in the LOOT->BOON chain.

### 5. DEG <-> LOOT (MEDIUM)

**Shared state:** lootboxEth, lootboxEthTotal

**Interaction path:** Chain 6: DEG.resolveBets -> LOOT.resolveLootboxDirect

**Analysis:**
- DEG resolves degenerette bets. If a bet wins a lootbox prize, DEG calls LOOT.resolveLootboxDirect to immediately resolve the lootbox (instead of queuing for later).
- LOOT.resolveLootboxDirect reads lootboxEth[idx][player] and decrements lootboxEthTotal.
- DEG sets lootboxEth[idx][player] BEFORE calling LOOT.resolveLootboxDirect.

**State consistency:** DEG writes lootboxEth, then LOOT reads it. Sequential. No stale read possible.

**Verdict: SAFE.** Write-before-read ordering is correct.

### 6. DEC <-> LOOT (MEDIUM)

**Shared state:** lootboxEth, lootboxEthTotal, claimableWinnings, claimablePool

**Interaction path:** Chain 7: DEC.creditDecJackpotClaim -> LOOT.resolveLootboxDirect

**Analysis:**
- DEC credits a decimator jackpot claim. Part of the credit may trigger a lootbox resolution (50/50 split: half ETH credit, half lootbox).
- DEC sets lootboxEth[idx][player] before calling LOOT.resolveLootboxDirect.
- LOOT reads the set value, resolves the lootbox, may credit claimableWinnings.
- Both DEC and LOOT may increment claimableWinnings and claimablePool for the same player.

**claimableWinnings double-credit check:** DEC credits claimableWinnings with the ETH portion. LOOT (via lootbox resolution) may credit additional claimableWinnings from lootbox wins. These are SEPARATE, INDEPENDENT credits -- one for the decimator ETH share, one for the lootbox win. Both are correct and intentional. The total is the sum of both.

**Verdict: SAFE.** No double-credit. Both credits are for different value sources.

### 7. JACK <-> END (LOW)

**Shared state:** claimableWinnings, claimablePool

**Interaction path:** Both are called within advanceGame() orchestration, but for DIFFERENT purposes:
- JACK: credits daily jackpot winnings to burn ticket holders
- END: credits endgame reward jackpots to top affiliates

**Double-credit check:** JACK credits based on trait matching (burn tickets). END credits based on affiliate score. These select different players (or if the same player, for different reasons). Both correctly increment claimableWinnings and claimablePool. The pool accounting is additive and cannot double-count.

**Verdict: SAFE.** Additive credits for different value sources. No accounting overlap.

## Low-Priority Pairs

The remaining pairs have no direct shared mutable state or interact only through separate external entry points:

| Pair | Classification | Reason |
|------|---------------|--------|
| BOON <-> WHALE | SAFE | BOON reads whaleBoonDiscountBps (BOON writes it). WHALE reads it for discount. Separate entry points. |
| BOON <-> MINT | SAFE | BOON writes mintPacked_.LEVEL_COUNT. MINT reads it. Separate entry points. |
| BOON <-> ADV | SAFE | No shared writes. BOON writes boon state; ADV does not read boon state. |
| OVER <-> all non-ADV | SAFE | OVER only accessed through ADV orchestration. Sets gameOver flag and credits pool. |
| DEC <-> ADV | SAFE | DEC.runDecimatorJackpot called by ADV. Sequential orchestration. |
| DEC <-> JACK | SAFE | No direct shared state. Both credit claimablePool but at different stages. |
| DEC <-> MINT | SAFE | No shared mutable state. |
| DEC <-> WHALE | SAFE | No shared mutable state. |
| END <-> MINT | SAFE | No shared mutable state. |
| END <-> WHALE | SAFE | No shared mutable state. |
| END <-> DEC | SAFE | No shared mutable state. |
| END <-> DEG | SAFE | No shared mutable state. |
| END <-> BOON | SAFE | No shared mutable state. |
| JACK <-> MINT | SAFE | ticketQueue read by JACK after MINT processes. Sequential. |
| JACK <-> WHALE | SAFE | No direct interaction path. |
| JACK <-> DEC | SAFE | Both credit claimablePool independently. |
| JACK <-> LOOT | SAFE | No direct interaction path. |
| JACK <-> DEG | SAFE | No direct interaction path. |
| JACK <-> BOON | SAFE | No direct interaction path. |
| OVER <-> JACK | SAFE | OVER sets gameOver; JACK checks it. Sequential (OVER runs before JACK in certain paths). |
| All remaining | SAFE | No shared mutable state between these pairs. |

## AdvanceModule Orchestration Sequence Verification

The advanceGame() function orchestrates multiple module calls in a fixed sequence. The full sequence (simplified):

```
1. Guard checks (gameOver, liveness, daily gate)
2. If phaseTransitionActive:
   a. JACK.consolidatePrizePools() -- moves next->current, future->next
   b. JACK.payDailyJackpot() -- distributes from currentPrizePool
   c. JACK.payDailyCoinJackpot() -- BURNIE jackpots
   d. MINT.processFutureTicketBatch() -- processes ticket queue
   e. JACK.processTicketBatch() -- processes burn tickets
3. If jackpotPhaseFlag && phase complete:
   a. END.rewardTopAffiliate() -- affiliate reward
   b. END.runRewardJackpots() -- decimator/BAF jackpots
   c. Check gameOver conditions
4. If gameOver conditions met:
   a. OVER.handleGameOverDrain() -- terminal settlement
5. RNG request/fulfillment handling
```

**Each step reads state that was written by a prior step.** The ordering ensures:
- consolidatePrizePools runs BEFORE payDailyJackpot (so jackpot distributes from the correct pool)
- payDailyJackpot runs BEFORE processTicketBatch (so ticket burns happen against post-jackpot state)
- processFutureTicketBatch runs BEFORE processTicketBatch (so cursor is correct)
- rewardTopAffiliate/runRewardJackpots run AFTER all daily processing is complete
- handleGameOverDrain runs LAST (terminal state after all rewards distributed)

**Verified: No inter-step state inconsistency in the orchestration sequence.**

## Findings Summary

| Pair | Risk | Classification | Finding |
|------|------|---------------|---------|
| ADV <-> JACK | HIGH priority | SAFE | Sequential orchestration ensures correct pool values at each step |
| ADV <-> MINT | HIGH priority | SAFE | Cursor state consistently updated by MINT before JACK reads |
| MINT <-> WHALE | MEDIUM priority | SAFE | Separate entry points; read-modify-write is atomic per call |
| LOOT <-> BOON | MEDIUM priority | SAFE | LOOT does not read any state that BOON modifies |
| DEG <-> LOOT | MEDIUM priority | SAFE | Write-before-read ordering for lootboxEth |
| DEC <-> LOOT | MEDIUM priority | SAFE | Independent credits for different value sources |
| JACK <-> END | LOW priority | SAFE | Additive credits, no accounting overlap |
| All remaining 38 pairs | LOW priority | SAFE | No shared mutable state or separate entry points |

**Zero composition bugs found.** All 7 high-priority pairs and 38 low-priority pairs classified as SAFE.

**The architecture's composition safety relies on three key properties:**
1. Single storage source (DegenerusGameStorage) eliminates slot collision
2. Fixed orchestration ordering within advanceGame() ensures sequential consistency
3. Separate entry points for MINT/WHALE/DEG/BOON prevent same-tx multi-writer conflicts for mintPacked_
