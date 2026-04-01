# Phase 104: Day Advancement + VRF - Research

**Researched:** 2026-03-25
**Domain:** Adversarial smart contract audit -- DegenerusGameAdvanceModule.sol
**Confidence:** HIGH

## Summary

Phase 104 is the second unit of the v5.0 adversarial audit, targeting `DegenerusGameAdvanceModule.sol` (1,570 lines, ~35 functions). This module is the heartbeat of the Degenerus game: it handles the daily `advanceGame()` state machine, VRF request/fulfillment lifecycle, daily jackpot orchestration, ticket queue processing, future ticket activation, phase/level transitions, lootbox RNG requests, and RNG nudge mechanics. The module executes via delegatecall from DegenerusGame, meaning it reads and writes DegenerusGame's storage directly -- the exact context where BAF-class cache-overwrite bugs hide.

The phase follows the identical three-agent methodology proven in Phase 103: Taskmaster builds a coverage checklist, Mad Genius attacks every function with call trees and storage-write maps, Skeptic validates findings. The key differentiator is the PRIORITY INVESTIGATION of a ticket queue drain bug evidenced by 3 failing Foundry tests (`testFiveLevelIntegration`, `testMultiLevelZeroStranding`, `testZeroStrandingSweepAfterTransitions`) that report `Read queue not drained for level 1: 2 != 0`.

The contract's complexity is substantially higher than Unit 1's Game.sol router: `advanceGame()` alone is a 270-line function with 11 stage paths, multiple delegatecall chains into 4 different modules, a double-buffered ticket queue system, and VRF-dependent branching. The BAF-class risk is elevated because `advanceGame()` caches `level`, `jackpotPhaseFlag`, `lastPurchaseDay`, and other state in locals, then delegates to modules (JackpotModule, EndgameModule, MintModule) that write to shared storage in Game's context.

**Primary recommendation:** Follow the Phase 103 four-plan structure exactly. Invest disproportionate time on `advanceGame()`, `rngGate()`, and the ticket lifecycle functions. The ticket queue drain investigation must produce a standalone verdict section with full trace evidence before the Mad Genius can sign off.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Use Categories B/C/D only -- no Category A. This is a module, not the router. Category A (delegatecall dispatchers) does not apply. External/public state-changing functions -> Category B. Internal/private state-changing helpers -> Category C. View/pure functions -> Category D.
- **D-02:** Category B functions get full Mad Genius treatment: recursive call tree with line numbers, storage-write map, cached-local-vs-storage check, 10-angle attack analysis.
- **D-03:** Category C functions are traced as part of their parent's call tree. They do NOT get standalone attack sections unless they are called from multiple parents with different cached-local states.
- **D-04:** The ticket queue drain investigation is a PRIORITY item. The Mad Genius must produce a dedicated section tracing `_prepareFutureTickets` and `processFutureTicketBatch` end-to-end with a standalone verdict: CONFIRMED BUG or PROVEN SAFE.
- **D-05:** The investigation must trace the full ticket lifecycle: queue write -> batch processing -> consumption. The 3 failing tests (testFiveLevelIntegration, testMultiLevelZeroStranding, testZeroStrandingSweepAfterTransitions) must be examined to determine whether the failure is a contract bug or test setup issue.
- **D-06:** Fresh adversarial analysis on ALL functions -- do not reference or trust prior findings from v3.7/v3.8. The entire point of v5.0 is catching bugs that survived 24 prior milestones.
- **D-07:** VRF paths (requestRng, rawFulfillRandomWords, rngGate, backfillGapDays) get the same full treatment as every other function. No reduced scrutiny for "already audited" code.
- **D-08:** When advanceGame() or other functions chain into code from other modules (jackpot, endgame, mint), trace the subordinate calls far enough to verify the parent's state coherence -- specifically the cached-local-vs-storage check. Full internals of those modules are audited in their own unit phases (105-117).
- **D-09:** If a subordinate call writes to storage that the parent has cached locally, that IS a finding for this phase regardless of which module the subordinate lives in. The BAF pattern is what we're hunting.
- **D-10:** Follow ULTIMATE-AUDIT-DESIGN.md format: per-function sections with Call Tree, Storage Writes (Full Tree), Cached-Local-vs-Storage Check, Attack Analysis with verdicts.

### Claude's Discretion
- Ordering of function analysis within the report (suggest risk-tier ordering as in Phase 103)
- Level of detail in cross-module subordinate call traces (enough to verify state coherence, no more)
- Whether to split the attack report into multiple files if it exceeds reasonable length

### Deferred Ideas (OUT OF SCOPE)
- **Phase 107 coordination**: `processFutureTicketBatch` lives in AdvanceModule but the ticket queue write path lives in MintModule. Phase 107 (Mint + Purchase Flow) should coordinate with this phase's ticket queue drain findings.
- **Phase 118**: Full cross-module state coherence verification is deferred to the integration sweep.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| UNIT-02 | Unit 2 -- Day Advancement + VRF complete (DegenerusGameAdvanceModule) | Full function inventory, call tree patterns, cross-module delegation map, ticket lifecycle trace documented below |
| COV-01 | Every state-changing function has a Taskmaster-built checklist entry | Function inventory identifies all 35 functions with categories B/C/D |
| COV-02 | Every function checklist entry signed off with analyzed/call-tree/storage/cache | Format established in Phase 103 COVERAGE-CHECKLIST.md; same table structure applies |
| COV-03 | No unit advances to Skeptic review until Taskmaster gives PASS verdict with 100% coverage | 4-plan workflow enforces this gate |
| ATK-01 | Every function has a fully-expanded recursive call tree with line numbers | Call tree patterns documented for all cross-module delegatecall chains below |
| ATK-02 | Every function has a complete storage-write map | Key storage variables identified for all 102 variables in DegenerusGameStorage |
| ATK-03 | Every function has an explicit cached-local-vs-storage check | Critical cached-local pairs identified for advanceGame() and rngGate() below |
| ATK-04 | Every function attacked from all applicable angles | 10-angle attack template from ULTIMATE-AUDIT-DESIGN.md; RNG-specific angles documented |
| ATK-05 | Every VULNERABLE/INVESTIGATE finding includes exact line numbers and scenario | Report format established in Phase 103 ATTACK-REPORT.md |
| VAL-01 | Every VULNERABLE/INVESTIGATE finding has Skeptic verdict | Skeptic review plan (Plan 3) covers this |
| VAL-02 | Every FALSE POSITIVE dismissal cites specific line(s) | Format from Phase 103 SKEPTIC-REVIEW.md |
| VAL-03 | Every CONFIRMED finding has severity rating | Severity definitions in ULTIMATE-AUDIT-DESIGN.md |
| VAL-04 | Skeptic independently verifies Taskmaster's function checklist | Plan 3 includes independent function enumeration |
</phase_requirements>

## Architecture Patterns

### Contract Under Audit

```
contracts/modules/DegenerusGameAdvanceModule.sol  (1,570 lines)
  inherits: DegenerusGameStorage (1,613 lines)
  executes via: delegatecall from DegenerusGame
  storage context: DegenerusGame's 102-variable layout (slots 0-78)
```

### Function Inventory (Complete)

**Category B: External/Public State-Changing (6 functions)**

These receive full Mad Genius treatment per D-02.

| # | Function | Lines | Access | Risk Tier | Key Concern |
|---|----------|-------|--------|-----------|-------------|
| B1 | `advanceGame()` | 125-397 | external, any caller | 1 (CRITICAL) | 270-line FSM, 11 stage paths, caches level/jackpotPhaseFlag/lastPurchaseDay in locals, delegates to 4 modules via delegatecall |
| B2 | `requestLootboxRng()` | 689-759 | external, any caller | 1 (HIGH) | Mid-day VRF request, ticket buffer swap, LINK balance check, pending accumulator reset |
| B3 | `reverseFlip()` | 1438-1446 | external, any caller | 3 (LOW) | Burns BURNIE, increments totalFlipReversals counter |
| B4 | `rawFulfillRandomWords()` | 1455-1476 | external, VRF coordinator only | 1 (HIGH) | VRF callback, branching on rngLockedFlag for daily vs mid-day path |
| B5 | `wireVrf()` | 412-425 | external, ADMIN only | 3 (LOW) | Deploy-only VRF config, write 4 storage vars |
| B6 | `updateVrfCoordinatorAndSub()` | 1390-1419 | external, ADMIN only | 2 (MEDIUM) | Emergency VRF rotation, resets 6 state flags including midDayTicketRngPending |

**Category C: Private/Internal State-Changing Helpers (21 functions)**

Traced via parent call trees per D-03. Functions marked with [MULTI-PARENT] get extra scrutiny for differing cached-local contexts.

| # | Function | Lines | Called By | State Writes |
|---|----------|-------|----------|--------------|
| C1 | `_handleGameOverPath()` | 433-482 | B1 | levelStartTime; delegatecall to GAMEOVER_MODULE |
| C2 | `_endPhase()` | 487-495 | B1 (jackpot path) | phaseTransitionActive, levelPrizePool, jackpotCounter, compressedJackpotFlag |
| C3 | `_rewardTopAffiliate()` | 515-525 | B1 | delegatecall to ENDGAME_MODULE |
| C4 | `_runRewardJackpots()` | 528-539 | B1 | delegatecall to ENDGAME_MODULE |
| C5 | `_consolidatePrizePools()` | 553-564 | B1 | delegatecall to JACKPOT_MODULE |
| C6 | `_awardFinalDayDgnrsReward()` | 567-580 | B1 | delegatecall to JACKPOT_MODULE |
| C7 | `payDailyJackpot()` | 587-603 | B1 [MULTI-PARENT: purchase + jackpot paths] | delegatecall to JACKPOT_MODULE |
| C8 | `payDailyJackpotCoinAndTickets()` | 609-621 | B1 | delegatecall to JACKPOT_MODULE |
| C9 | `_payDailyCoinJackpot()` | 628-639 | B1 | delegatecall to JACKPOT_MODULE |
| C10 | `_enforceDailyMintGate()` | 647-683 | B1 | view-only (no writes) |
| C11 | `rngGate()` | 783-856 | B1 | rngWordByDay, rngWordCurrent, totalFlipReversals, lastVrfProcessedTimestamp, levelStartTime; external calls to coinflip + sdgnrs |
| C12 | `_finalizeLootboxRng()` | 858-864 | C11, C13 | lootboxRngWordByIndex, lastLootboxRngWord |
| C13 | `_gameOverEntropy()` | 871-964 | C1 | rngWordByDay, rngWordCurrent, rngRequestTime; external calls |
| C14 | `_getHistoricalRngFallback()` | 977-1001 | C13 | view-only |
| C15 | `_applyTimeBasedFutureTake()` | 1044-1119 | B1 | prizePoolsPacked (next, future), yieldAccumulator |
| C16 | `_drawDownFuturePrizePool()` | 1121-1133 | B1 | prizePoolsPacked (next, future) |
| C17 | `_processFutureTicketBatch()` | 1149-1163 | C18, B1 [MULTI-PARENT] | delegatecall to MINT_MODULE |
| C18 | `_prepareFutureTickets()` | 1171-1197 | B1 | ticketLevel via C17 |
| C19 | `_runProcessTicketBatch()` | 1210-1227 | B1 [MULTI-PARENT: mid-day, daily, purchase, jackpot paths] | ticketCursor, ticketLevel via JACKPOT_MODULE delegatecall |
| C20 | `_processPhaseTransition()` | 1234-1255 | B1 | ticketQueue, ticketsOwedPacked via _queueTickets; stETH submission via _autoStakeExcessEth |
| C21 | `_autoStakeExcessEth()` | 1260-1270 | C20 | external stETH submit (no game storage writes) |
| C22 | `_requestRng()` | 1276-1289 | C11, B1 | via C24 (_finalizeRngRequest) |
| C23 | `_tryRequestRng()` | 1291-1318 | C13 | via C24 |
| C24 | `_finalizeRngRequest()` | 1320-1382 | C22, C23 | vrfRequestId, rngWordCurrent, rngRequestTime, rngLockedFlag, lootboxRngIndex, lootboxRngPendingEth, lootboxRngPendingBurnie, decWindowOpen, level, price |
| C25 | `_unlockRng()` | 1424-1431 | B1, C11 [MULTI-PARENT] | dailyIdx, rngLockedFlag, rngWordCurrent, vrfRequestId, rngRequestTime; _unfreezePool |
| C26 | `_backfillGapDays()` | 1489-1507 | C11 | rngWordByDay[gapDay]; external coinflip.processCoinflipPayouts |
| C27 | `_backfillOrphanedLootboxIndices()` | 1513-1533 | C11 | lootboxRngWordByIndex, lastLootboxRngWord |
| C28 | `_applyDailyRng()` | 1536-1552 | C11, C13 [MULTI-PARENT] | totalFlipReversals, rngWordCurrent, rngWordByDay, lastVrfProcessedTimestamp |

**Category D: View/Pure (8 functions)**

| # | Function | Lines | Purpose |
|---|----------|-------|---------|
| D1 | `_enforceDailyMintGate()` | 647-683 | View-only gate check |
| D2 | `_getHistoricalRngFallback()` | 977-1001 | Pure RNG derivation (view of rngWordByDay) |
| D3 | `_nextToFutureBps()` | 1010-1042 | Pure BPS calculation |
| D4 | `_currentNudgeCost()` | 1560-1569 | Pure cost computation |
| D5 | `_revertDelegate()` | 544-549 | Pure revert bubbling |
| D6-D8 | Inherited Storage getters | Various | _getPrizePools, _getPendingPools, etc. |

**Total: ~35 functions (6 Category B + 21 Category C + 8 Category D)**

### Critical Cached-Local-vs-Storage Pairs in advanceGame()

These are the highest-priority BAF-class checks for the Mad Genius:

| Local Variable | Cached At | Descendant Writes Via | Risk |
|---------------|-----------|----------------------|------|
| `lvl = level` | Line 131 | `_finalizeRngRequest` writes `level = lvl` (line 1352) on lastPurchaseDay fresh request | HIGH -- level is read from storage, descendant overwrites it; parent continues using stale `lvl` |
| `inJackpot = jackpotPhaseFlag` | Line 130 | `advanceGame` itself writes `jackpotPhaseFlag = true` (line 341) and `jackpotPhaseFlag = false` (line 263) | MEDIUM -- self-write, but must verify no reuse of stale `inJackpot` after the write |
| `lastPurchase` (derived from `lastPurchaseDay`) | Line 143 | `advanceGame` writes `lastPurchaseDay = true` (line 139, 302) | MEDIUM -- cached before Turbo check could set it |
| `purchaseLevel` (derived from lvl, lastPurchase, rngLockedFlag) | Line 145 | `_finalizeRngRequest` writes `level` which changes what `purchaseLevel` should be | HIGH -- stale purchaseLevel after level increment |
| `day = _simulatedDayIndexAt(ts)` | Line 129 | Not written by descendants (pure computation) | LOW |
| `advanceBounty` | Line 127 | Not written by descendants (uses `price` which could be written by `_finalizeRngRequest`) | MEDIUM -- price can change if level increments during this call |

### Cross-Module Delegatecall Map

`advanceGame()` delegates to 4 external modules during execution:

```
advanceGame()
  +-- payDailyJackpot() --> GAME_JACKPOT_MODULE.payDailyJackpot
  |     Storage writes: jackpotCounter, currentPrizePool, claimableWinnings[winners],
  |                     claimablePool, dailyEthPoolBudget, dailyEthPhase,
  |                     dailyJackpotCoinTicketsPending, lastDailyJackpotLevel
  |
  +-- payDailyJackpotCoinAndTickets() --> GAME_JACKPOT_MODULE.payDailyJackpotCoinAndTickets
  |     Storage writes: dailyJackpotCoinTicketsPending=false, jackpotCounter++,
  |                     coin/ticket distributions
  |
  +-- _payDailyCoinJackpot() --> GAME_JACKPOT_MODULE.payDailyCoinJackpot
  |     Storage writes: coin distributions via external coin.creditFlip
  |
  +-- _consolidatePrizePools() --> GAME_JACKPOT_MODULE.consolidatePrizePools
  |     Storage writes: prizePoolsPacked, currentPrizePool, yieldAccumulator
  |
  +-- _awardFinalDayDgnrsReward() --> GAME_JACKPOT_MODULE.awardFinalDayDgnrsReward
  |     Storage writes: external dgnrs transfers
  |
  +-- _rewardTopAffiliate() --> GAME_ENDGAME_MODULE.rewardTopAffiliate
  |     Storage writes: affiliate-related state
  |
  +-- _runRewardJackpots() --> GAME_ENDGAME_MODULE.runRewardJackpots
  |     Storage writes: BAF/decimator jackpot resolution, claimableWinnings, claimablePool
  |
  +-- _processFutureTicketBatch() --> GAME_MINT_MODULE.processFutureTicketBatch
  |     Storage writes: ticketCursor, ticketLevel, ticket processing state
  |
  +-- _runProcessTicketBatch() --> GAME_JACKPOT_MODULE.processTicketBatch
  |     Storage writes: ticketCursor, ticketLevel, trait assignments, ticket data
  |
  +-- _handleGameOverPath() --> GAME_GAMEOVER_MODULE.handleGameOverDrain / handleFinalSweep
        Storage writes: gameOver flag, prize pool draining, claimable distributions
```

### advanceGame() State Machine Stages

The FSM has 12 stages, each emitted via `Advance(stage, lvl)`:

| Stage | Constant | Path | What Happens |
|-------|----------|------|-------------|
| 0 | STAGE_GAMEOVER | Liveness guard fires | delegatecall to GameOverModule |
| 1 | STAGE_RNG_REQUESTED | VRF word not ready | _swapAndFreeze + _requestRng |
| 2 | STAGE_TRANSITION_WORKING | Phase transition in progress | _processPhaseTransition or FF drain |
| 3 | STAGE_TRANSITION_DONE | Phase transition complete | phaseTransitionActive=false, _unlockRng |
| 4 | STAGE_FUTURE_TICKETS_WORKING | Near-future tickets being processed | _prepareFutureTickets |
| 5 | STAGE_TICKETS_WORKING | Current-level tickets being processed | _runProcessTicketBatch |
| 6 | STAGE_PURCHASE_DAILY | Purchase phase daily jackpot | payDailyJackpot + _payDailyCoinJackpot |
| 7 | STAGE_ENTERED_JACKPOT | Purchase->jackpot transition | jackpotPhaseFlag=true, pool rebalancing |
| 8 | STAGE_JACKPOT_ETH_RESUME | Jackpot phase: ETH resume | payDailyJackpot carryover |
| 9 | STAGE_JACKPOT_COIN_TICKETS | Jackpot phase: coin+ticket done | payDailyJackpotCoinAndTickets |
| 10 | STAGE_JACKPOT_PHASE_ENDED | Level complete, 5 jackpots done | _endPhase + _unlockRng |
| 11 | STAGE_JACKPOT_DAILY_STARTED | Jackpot phase: fresh daily | payDailyJackpot |

### Ticket Queue Double-Buffer Architecture

Understanding this system is critical for the priority investigation:

```
Three key spaces (disjoint for lvl < 2^22):
  Slot 0:  lvl (bits 0-21)                    -- key space [0x000000-0x3FFFFF]
  FF:      lvl | TICKET_FAR_FUTURE_BIT (bit 22) -- key space [0x400000-0x7FFFFF]
  Slot 1:  lvl | TICKET_SLOT_BIT (bit 23)      -- key space [0x800000-0xBFFFFF]

ticketWriteSlot = 0 or 1 (toggled by _swapTicketSlot):
  Write key = Slot{ticketWriteSlot}[lvl]   -- where new tickets land
  Read key  = Slot{1-ticketWriteSlot}[lvl] -- where processing reads from

Lifecycle:
  1. Purchase/lootbox/constructor queues tickets to write key (or FF if > level+5)
  2. _swapAndFreeze() or _swapTicketSlot() toggles write<->read
  3. _runProcessTicketBatch() drains the read key via JACKPOT_MODULE.processTicketBatch
  4. ticketsFullyProcessed = true signals read key is empty
  5. FF keys drain via _processFutureTicketBatch() at phase transitions
  6. Near-future read queues (+1..+4) drain via _prepareFutureTickets() during daily advance
```

### Ticket Queue Drain Investigation Context

**Failing tests:** `testFiveLevelIntegration`, `testMultiLevelZeroStranding`, `testZeroStrandingSweepAfterTransitions`

**Error message:** `Read queue not drained for level 1: 2 != 0`

**Key observation:** The assertion is `_queueLength(readKey) == 0` for level 1 after driving through 5+ level transitions. The value is 2, suggesting exactly 2 addresses remain in the read queue at level 1 that were never processed.

**Investigation trace path for Mad Genius:**

1. **Who writes to the read key for level 1?** At level 0, `_tqWriteKey(1)` routes to one slot. After `_swapAndFreeze` (at RNG request), the write slot becomes the read slot. The 2 remaining entries could be constructor-seeded tickets (SDGNRS + VAULT each get 16 tickets per level 1-100 at constructor time).

2. **When are level 1 read queue tickets processed?** During `advanceGame()` at the daily drain gate (lines 204-219) and within the `do-while` loop (lines 284-291) when processing `_runProcessTicketBatch(purchaseLevel)` where `purchaseLevel = level + 1 = 1` during purchase phase at level 0.

3. **The double-buffer swap timing is critical:** If tickets are written to the write key for level 1, then `_swapAndFreeze` is called (toggling write<->read), those tickets appear in the read key. But if _more_ tickets are written to the _new_ write key for level 1 after the swap, those will only be processed after the NEXT swap. The question is whether the test setup creates tickets that arrive after the final swap for level 1.

4. **Constructor tickets:** The constructor calls `_queueTickets(SDGNRS, i, 16)` and `_queueTickets(VAULT, i, 16)` for `i=1..100`. At deploy time, `ticketWriteSlot` is 0, so these go to Slot 0 for levels 1-5 (near-future, not FF) and FF key for levels 6-100. Slot 0 for level 1 gets SDGNRS and VAULT entries. When `_swapAndFreeze` first fires (at level 0's RNG request), Slot 0 becomes the read slot, Slot 1 becomes write. The 2 constructor entries should now be in the read slot and get processed by `_runProcessTicketBatch(1)`.

5. **The key question:** Are those constructor entries actually processed before level 1 transitions? Or does the test reveal that `_processPhaseTransition` at level 0->1 queues vault perpetual tickets (lines 1239-1248) to the write key for level `purchaseLevel + 99 = 100` (FF route), AND `_queueTickets` for near-future levels happen at constructor time into Slot 0 -- but if `ticketWriteSlot` is toggled an even number of times by the time the test checks, the "read key" computation might point at the wrong slot.

6. **Verdict hypothesis:** The test computes `_readKeyForLevel(1)` using the CURRENT `ticketWriteSlot` value. If the game has advanced through multiple levels, `ticketWriteSlot` has been toggled multiple times. The "read key" at test assertion time may NOT be the same slot that was the "read key" when level 1 was being processed. If the constructor entries went to Slot 0, Slot 0 was the read key when first swapped, and those tickets were processed, but by the time the test checks, `ticketWriteSlot` has toggled back to 0 (even number of swaps), making the current read key = Slot 1 for level 1 -- which might have entries from vault perpetual tickets written during a later phase transition.

**This is likely a test setup issue, not a contract bug.** The test should track which slot was active during processing rather than computing the read key at assertion time. But the Mad Genius must confirm this with a full trace.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Function enumeration | Manual grep | `forge inspect DegenerusGameAdvanceModule methods` + source grep | Ensures no functions are missed by visibility tricks |
| Storage slot verification | Manual counting | `forge inspect DegenerusGameAdvanceModule storage-layout` | Matches Phase 103 methodology |
| Call tree expansion | Summarized trees | Line-by-line manual trace with exact line numbers | ULTIMATE-AUDIT-DESIGN.md mandates this; the BAF bug hid in a rare-path descendant |

## Common Pitfalls

### Pitfall 1: Stale `lvl` After _finalizeRngRequest Level Increment
**What goes wrong:** `advanceGame()` caches `lvl = level` at line 131 and `purchaseLevel` at line 145. `_finalizeRngRequest()` at line 1352 writes `level = lvl` (where `lvl` is the `purchaseLevel` argument, i.e., `level + 1`). If the parent continues using the stale `lvl` after this write, it operates on the wrong level.
**Why it happens:** The level increment occurs inside `_requestRng` -> `_finalizeRngRequest`, which is called from `rngGate()`, which returns to the do-while loop. The parent then uses `lvl` for subsequent operations.
**How to avoid:** Trace every use of `lvl` and `purchaseLevel` after the `rngGate()` call. Verify that the do-while loop breaks immediately after `rngGate()` returns 1 (stage STAGE_RNG_REQUESTED), preventing further use of stale locals.
**Warning signs:** Any code path that continues past `rngGate()` returning 1 without re-reading `level`.

### Pitfall 2: Cross-Module Storage Writes Corrupting advanceGame Locals
**What goes wrong:** `advanceGame()` delegates to JackpotModule (payDailyJackpot, etc.) which writes to `jackpotCounter`, `dailyJackpotCoinTicketsPending`, `dailyEthPhase`, `dailyEthPoolBudget`, and `lastDailyJackpotLevel`. If `advanceGame()` cached any of these before the delegatecall, the cache is stale after return.
**Why it happens:** Delegatecall runs in the caller's storage context. The module writes directly to Game's storage, not through the AdvanceModule's locals.
**How to avoid:** For every delegatecall in `advanceGame()`, list ALL storage variables the delegate writes. Then verify none of those variables were cached in a local before the delegatecall.
**Warning signs:** A local variable that was read from storage, followed by a delegatecall, followed by the local being written back to storage or used in a condition.

### Pitfall 3: Mid-Day vs Daily RNG Path Confusion in rawFulfillRandomWords
**What goes wrong:** `rawFulfillRandomWords()` branches on `rngLockedFlag` (line 1465). The daily path stores the word for later processing. The mid-day path directly finalizes lootbox RNG and clears VRF state. Confusing these paths could lead to either (a) a daily word being treated as mid-day (lootbox finalized, daily processing skipped) or (b) a mid-day word being treated as daily (word stored but not immediately finalized).
**Why it happens:** The same VRF callback handles two different request types. The only discriminator is `rngLockedFlag`.
**How to avoid:** Verify that `rngLockedFlag` is set to `true` exactly and only when a daily RNG request is in-flight, and remains `false` for mid-day lootbox requests.
**Warning signs:** Any code path that could change `rngLockedFlag` between VRF request and fulfillment without going through the intended state machine.

### Pitfall 4: Ticket Queue Double-Buffer Slot Confusion
**What goes wrong:** The write key and read key are computed from `ticketWriteSlot` which toggles on every swap. Functions that process tickets from the read slot must use the CURRENT read key at the time of processing, not a cached value. If the slot toggles between key computation and queue access, the wrong queue is read/drained.
**Why it happens:** `_swapAndFreeze()` and `_swapTicketSlot()` modify `ticketWriteSlot` in storage. Any function that computes a key before the swap and uses it after will access the wrong buffer.
**How to avoid:** Verify that key computation and queue access happen atomically (no swap between them). Verify that `_swapAndFreeze` is only called at the start of daily processing, before any ticket reads.
**Warning signs:** Queue keys computed in one function, stored, and passed to another function that might trigger a swap.

### Pitfall 5: VRF Gap Day Backfill Completeness
**What goes wrong:** `rngGate()` at line 799 checks `if (day > idx + 1)` and backfills gap days from `idx+1` to `day-1`. If the gap calculation is off by one, either a day gets double-processed or a day gets skipped.
**Why it happens:** Fencepost errors in the `startDay..endDay` range. `_backfillGapDays` uses exclusive end (`gapDay < endDay`), while the current day is processed separately via `_applyDailyRng`.
**How to avoid:** Verify the boundary: `startDay = dailyIdx + 1`, `endDay = day`. Gap days are `[startDay, endDay)`. Current day (`day`) is handled by `_applyDailyRng` after the backfill.
**Warning signs:** `rngWordByDay[day]` being written twice, or a day index that never gets a word.

## Code Examples

### Phase 103 Report Format (Category B function section)

Source: `audit/unit-01/ATTACK-REPORT.md`

```markdown
## DegenerusGameAdvanceModule::functionName() (lines X-Y) [BN]

### Call Tree
functionName() [line X]
  +-- _helper1() [line A]
  |    +-- _subHelper() [line B]
  |         +-- externalContract.method() [line C]
  +-- _helper2() [line D]

### Storage Writes (Full Tree)
- `storageVar1` (slot N, type) -- written by _helper1 at line B
- `storageVar2` (slot M, type) -- written by _subHelper at line C

### Cached-Local-vs-Storage Check
[Explicit list of (ancestor_local, descendant_write) pairs with verdict]

### Attack Analysis
**State Coherence:** [analysis] VERDICT: SAFE/VULNERABLE/INVESTIGATE
**Access Control:** [analysis] VERDICT: ...
[... all 10 angles ...]
```

### Coverage Checklist Format (Category B)

Source: `audit/unit-01/COVERAGE-CHECKLIST.md`

```markdown
| # | Function | Lines | Access Control | Storage Writes | External Calls | Risk Tier | Analyzed? | Call Tree? | Storage Map? | Cache Check? |
|---|----------|-------|---------------|----------------|----------------|-----------|-----------|------------|--------------|-------------|
| B1 | advanceGame() | 125-397 | any | [list] | [list] | 1 | YES | YES | YES | YES |
```

### Skeptic Review Format

Source: `audit/unit-01/SKEPTIC-REVIEW.md`

```markdown
### F-XX: [Title]
**Mad Genius Verdict:** VULNERABLE / INVESTIGATE
**Skeptic Verdict:** CONFIRMED / FALSE POSITIVE / DOWNGRADE TO INFO

**Analysis:** [Precise technical explanation]
**If FALSE POSITIVE:** [Exact line(s) that prevent the attack]
**If CONFIRMED:** [Severity + justification]
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Phase 103: Category A (dispatchers) in checklist | Phase 104: Categories B/C/D only (D-01) | Phase 104 design | Module audit skips dispatch verification (done in Phase 103 for all modules) |
| Single-file attack report | May split if length exceeds 100KB (Claude's discretion) | Phase 104 design | Prevents context window exhaustion during Skeptic review |
| No priority investigation | Ticket queue drain is mandatory PRIORITY item (D-04) | Phase 104 design | Must be resolved before unit can complete |

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Foundry (forge) |
| Config file | `foundry.toml` |
| Quick run command | `forge test --match-contract TicketLifecycleTest -vvv` |
| Full suite command | `forge test` |

### Phase Requirements to Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| UNIT-02 | All state-changing functions audited with 3-agent system | manual-only | N/A -- audit deliverable review | N/A |
| COV-01 | Taskmaster checklist built with 100% function coverage | manual-only | N/A -- checklist artifact | N/A |
| ATK-01 | Call trees fully expanded for all functions | manual-only | N/A -- attack report artifact | N/A |
| ATK-03 | Cached-local-vs-storage check on all functions | manual-only | N/A -- attack report artifact | N/A |
| D-04/D-05 | Ticket queue drain investigation verdict | integration | `forge test --match-test "testFiveLevelIntegration\|testMultiLevelZeroStranding\|testZeroStrandingSweepAfterTransitions" -vvv` | Yes: `test/fuzz/TicketLifecycle.t.sol` |

### Sampling Rate
- **Per task commit:** Review audit artifacts for completeness
- **Per wave merge:** Cross-reference coverage checklist against attack report
- **Phase gate:** All 6 success criteria verified before `/gsd:verify-work`

### Wave 0 Gaps
- None -- existing test infrastructure covers the ticket queue integration tests. The 3 failing tests are the investigation targets, not gaps to create.

## Open Questions

1. **Ticket queue drain: test bug or contract bug?**
   - What we know: 3 tests fail with `Read queue not drained for level 1: 2 != 0`. The `_readKeyForLevel` helper in the test computes the key based on CURRENT `ticketWriteSlot`, which may have toggled an even number of times, pointing to the wrong buffer.
   - What's unclear: Whether the 2 remaining entries are unprocessed constructor tickets (contract bug: tickets were never drained) or correctly processed tickets that appear in the wrong slot at assertion time (test bug: read key computation is stale).
   - Recommendation: Mad Genius must trace both the contract's processing path for level 1 tickets AND the test's assertion logic to produce definitive verdict. This is D-04 / D-05.

2. **advanceBounty using potentially stale `price`**
   - What we know: `advanceBounty` is computed at line 127 using `price`. `_finalizeRngRequest` can update `price` at lines 1356-1379 when the level changes.
   - What's unclear: Whether the bounty is paid before or after the price could change. If `rngGate()` triggers `_requestRng` -> `_finalizeRngRequest` which sets new price, then the bounty at line 396 uses the OLD price.
   - Recommendation: Flag for Mad Genius to check whether this matters economically (bounty is ~0.005 ETH worth of BURNIE -- minor). Likely INFO at worst.

3. **Cross-module storage write completeness**
   - What we know: The delegatecall targets (JACKPOT_MODULE, ENDGAME_MODULE, MINT_MODULE, GAMEOVER_MODULE) write to Game's storage. Per D-08, the Mad Genius must trace far enough to verify state coherence but not audit internal module logic.
   - What's unclear: The exact set of storage variables written by each module delegatecall is not documented in this phase's audit scope. The Mad Genius needs to read into the module code to enumerate writes.
   - Recommendation: For each delegatecall in `advanceGame()`, the Mad Genius should open the target module, find the entry function, and list every storage write (SSTOREs) in its top-level execution. Deep recursion into sub-helpers within the module is deferred to the module's own unit phase.

## Sources

### Primary (HIGH confidence)
- `contracts/modules/DegenerusGameAdvanceModule.sol` -- 1,570 lines, complete source read
- `contracts/storage/DegenerusGameStorage.sol` -- 1,613 lines, storage layout and ticket queue helpers
- `contracts/interfaces/IDegenerusGameModules.sol` -- module interface signatures
- `.planning/ULTIMATE-AUDIT-DESIGN.md` -- three-agent system design, attack angles, output format
- `audit/unit-01/` -- Phase 103 deliverables (format reference for all 5 artifacts)
- `test/fuzz/TicketLifecycle.t.sol` -- 1,300+ lines, failing test source

### Secondary (MEDIUM confidence)
- `.planning/phases/104-day-advancement-vrf/104-CONTEXT.md` -- user decisions and canonical references
- `audit/KNOWN-ISSUES.md` -- known issues to exclude from findings

### Tertiary (LOW confidence)
- None -- all research based on direct source code reading

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- identical to Phase 103, no new tools needed
- Architecture: HIGH -- complete function inventory from direct source reading
- Pitfalls: HIGH -- derived from line-by-line contract analysis of the specific code
- Ticket investigation: MEDIUM -- hypothesis formed from source analysis but verdict requires full Mad Genius trace

**Research date:** 2026-03-25
**Valid until:** Indefinite (source code is the audit target, not a changing dependency)
