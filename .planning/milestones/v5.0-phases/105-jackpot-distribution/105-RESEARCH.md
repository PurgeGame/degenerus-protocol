# Phase 105: Jackpot Distribution - Research

**Researched:** 2026-03-25
**Domain:** Adversarial smart contract audit -- DegenerusGameJackpotModule.sol + DegenerusGamePayoutUtils.sol
**Confidence:** HIGH

## Summary

Phase 105 is the third unit of the v5.0 adversarial audit, targeting DegenerusGameJackpotModule.sol (2,715 lines, ~52 functions) and DegenerusGamePayoutUtils.sol (92 lines, 3 functions). This is the largest audit unit so far -- nearly double the line count of Unit 2's AdvanceModule (1,570 lines). The JackpotModule is where ETH actually moves to players: daily jackpot distributions, terminal jackpots at level boundaries, prize pool consolidation, auto-rebuy ticket conversion, whale pass crediting, batch ticket processing with inline assembly, and yield surplus distribution. It inherits from PayoutUtils which provides the three low-level payout primitives (_creditClaimable, _calcAutoRebuy, _queueWhalePassClaimCore).

This phase carries elevated BAF-class risk because _addClaimableEth and _processAutoRebuy are the EXACT functions where the original BAF cache-overwrite bug lived. The v4.4 fix in EndgameModule is NOT trusted per D-07 -- the Mad Genius must re-audit the entire _addClaimableEth -> _processAutoRebuy -> futurePrizePool chain from scratch. The contract also contains deep call chains (6+ levels in the ticket distribution subsystem) and inline Yul assembly for batch trait generation, both of which are prime hiding spots for subtle bugs.

The phase follows the identical four-plan structure proven in Phases 103-104: Taskmaster builds coverage checklist, Mad Genius attacks every function, Skeptic validates, final report compiles. The key difference is scale: 55 functions across two contracts, with 7 Category B entry points and ~35 Category C state-changing helpers. The report may need splitting per Claude's discretion decision.

**Primary recommendation:** Follow the Phase 103-104 four-plan structure. The Mad Genius report will be very large (2,715-line contract); consider splitting by subsystem (ETH flow, coin flow, ticket flow, pool consolidation). Invest disproportionate time on the BAF-critical paths (_addClaimableEth, _processAutoRebuy, _processSoloBucketWinner) and the inline assembly in _raritySymbolBatch.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Use Categories B/C/D only -- no Category A. Both contracts are modules, not routers. External/public state-changing functions -> Category B. Internal/private state-changing helpers -> Category C. View/pure functions -> Category D.
- **D-02:** Category B functions get full Mad Genius treatment: recursive call tree with line numbers, storage-write map, cached-local-vs-storage check, 10-angle attack analysis.
- **D-03:** Category C functions are traced as part of their parent's call tree. Standalone analysis only for MULTI-PARENT helpers (called from multiple parents with different cached-local states).
- **D-04:** DegenerusGameJackpotModule.sol (2,715 lines) and DegenerusGamePayoutUtils.sol (92 lines) are audited as a single unit. PayoutUtils is an internal helper contract inherited by JackpotModule -- its 3 functions (_creditClaimable, _calcAutoRebuy, _queueWhalePassClaimCore) get Category C treatment within JackpotModule's call trees.
- **D-05:** The Taskmaster checklist covers both contracts in a single document. Function counts from both contracts are summed for the unit total.
- **D-06:** _addClaimableEth and _processAutoRebuy are where the original BAF cache-overwrite bug lived. These functions AND every function that calls them get Tier 1 priority in the Mad Genius attack queue. The cached-local-vs-storage check is the #1 priority for these paths.
- **D-07:** The v4.4 BAF fix (rebuyDelta reconciliation in EndgameModule) is NOT trusted. The Mad Genius re-audits the entire _addClaimableEth -> _processAutoRebuy -> futurePrizePool chain from scratch as if the fix doesn't exist. Fresh adversarial analysis per D-06 from Phase 104.
- **D-08:** When JackpotModule functions call into other modules or external contracts, trace subordinate calls far enough to verify the parent's state coherence (cached-local-vs-storage check). Full internals of other modules are in their own unit phases.
- **D-09:** If a subordinate call writes to storage that the parent has cached locally, that IS a finding for this phase regardless of which module the subordinate lives in.
- **D-10:** Fresh adversarial analysis on all functions -- do not trust prior Phase 104 findings on RNG words passed to JackpotModule. The RNG words arrive as parameters; the jackpot module's use of those words (for winner selection, trait rolls, etc.) is this phase's responsibility.
- **D-11:** Follow ULTIMATE-AUDIT-DESIGN.md format: per-function sections with Call Tree, Storage Writes (Full Tree), Cached-Local-vs-Storage Check, Attack Analysis with verdicts.

### Claude's Discretion
- Function analysis ordering within risk tiers
- Level of detail in cross-module subordinate call traces
- Whether to split the attack report if it exceeds reasonable length (2,715-line contract may produce a very large report)
- Handling of the ~55 Category C private helpers -- grouping by subsystem (ETH flow, coin flow, ticket flow) may improve readability

### Deferred Ideas (OUT OF SCOPE)
- **Phase 106 coordination**: _addClaimableEth is also called from EndgameModule/GameOverModule. Phase 106 should verify the EndgameModule-side BAF fix independently.
- **Phase 117 coordination**: JackpotBucketLib.sol is used by JackpotModule for bucket distribution. Full library audit in Phase 117.
- **Phase 118**: Full cross-module state coherence verification deferred to integration sweep.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| UNIT-03 | Unit 3 -- Jackpot Distribution complete (DegenerusGameJackpotModule, DegenerusGamePayoutUtils) | Full function inventory (55 functions: 7B + 35C + 13D), call tree patterns, BAF-critical path analysis, subsystem maps documented below |
| COV-01 | Every state-changing function has a Taskmaster-built checklist entry | Function inventory identifies all 55 functions across both contracts with categories B/C/D |
| COV-02 | Every function checklist entry signed off with analyzed/call-tree/storage/cache | Format established in Phase 103 COVERAGE-CHECKLIST.md; same table structure applies |
| COV-03 | No unit advances to Skeptic review until Taskmaster gives PASS verdict with 100% coverage | 4-plan workflow enforces this gate |
| ATK-01 | Every function has a fully-expanded recursive call tree with line numbers | Call tree patterns documented for all 7 Category B functions with deep chains identified |
| ATK-02 | Every function has a complete storage-write map | Key storage variables identified for prize pool accounting (prizePoolsPacked, currentPrizePool, claimablePool, yieldAccumulator, claimableWinnings) and daily state (dailyEthPoolBudget, dailyEthPhase, etc.) |
| ATK-03 | Every function has an explicit cached-local-vs-storage check | BAF-critical pairs identified for _addClaimableEth -> _processAutoRebuy -> futurePrizePool chain; _distributeYieldSurplus obligations accounting; _processDailyEth liability tracking |
| ATK-04 | Every function attacked from all applicable angles | 10-angle attack template from ULTIMATE-AUDIT-DESIGN.md; RNG winner selection angles, inline assembly angles, cross-module boundary angles documented below |
| ATK-05 | Every VULNERABLE/INVESTIGATE finding includes exact line numbers and scenario | Report format established in Phase 103/104 ATTACK-REPORT.md |
| VAL-01 | Every VULNERABLE/INVESTIGATE finding has Skeptic verdict | Skeptic review plan (Plan 3) covers this |
| VAL-02 | Every FALSE POSITIVE dismissal cites specific line(s) | Format from Phase 103/104 SKEPTIC-REVIEW.md |
| VAL-03 | Every CONFIRMED finding has severity rating | Severity definitions in ULTIMATE-AUDIT-DESIGN.md |
| VAL-04 | Skeptic independently verifies Taskmaster's function checklist | Plan 3 includes independent function enumeration |
</phase_requirements>

## Architecture Patterns

### Contracts Under Audit

```
contracts/modules/DegenerusGameJackpotModule.sol  (2,715 lines)
  inherits: DegenerusGamePayoutUtils -> DegenerusGameStorage
  executes via: delegatecall from DegenerusGame
  storage context: DegenerusGame's shared storage layout

contracts/modules/DegenerusGamePayoutUtils.sol  (92 lines)
  inherits: DegenerusGameStorage
  abstract contract -- 3 internal/public helpers for payout primitives
```

### Function Inventory (Complete -- Both Contracts)

**Category B: External State-Changing (7 functions)**

Full Mad Genius treatment per D-02. All are delegatecall targets called from advanceGame() or other router entry points.

| # | Function | Lines | Access | Risk Tier | Key Concern |
|---|----------|-------|--------|-----------|-------------|
| B1 | `runTerminalJackpot()` | 272-308 | OnlyGame | 1 | Terminal x00-level ETH distribution via bucket system; calls _distributeJackpotEth with BAF-path _addClaimableEth |
| B2 | `payDailyJackpot()` | 313-637 | external (delegatecall) | 1 (CRITICAL) | 325-line function with 3 major paths (daily fresh, daily resume, early-burn); manages currentPrizePool, futurePrizePool, nextPrizePool accounting; calls _processDailyEth and _executeJackpot which both invoke _addClaimableEth |
| B3 | `payDailyJackpotCoinAndTickets()` | 652-737 | external (delegatecall) | 2 | Phase 2 of daily jackpot; coin distribution via coin.creditFlip/creditFlipBatch + ticket distribution via _distributeTicketJackpot; increments jackpotCounter |
| B4 | `awardFinalDayDgnrsReward()` | 744-769 | external (delegatecall) | 2 | DGNRS reward to solo bucket winner; external call to dgnrs.transferFromPool |
| B5 | `consolidatePrizePools()` | 850-879 | external (delegatecall) | 1 | Prize pool merging and yield surplus distribution; writes to currentPrizePool, prizePoolsPacked (future), yieldAccumulator; calls _distributeYieldSurplus which invokes _addClaimableEth |
| B6 | `processTicketBatch()` | 1812-1873 | external (delegatecall) | 1 | Gas-bounded ticket processing with assembly-level trait generation; manages ticketCursor, ticketLevel, ticketQueue cleanup; deep call chain into _processOneTicketEntry -> _generateTicketBatch -> _raritySymbolBatch (inline Yul) |
| B7 | `payDailyCoinJackpot()` | 2283-2324 | external (delegatecall) | 2 | BURNIE jackpot split: 75% near-future trait winners, 25% far-future ticketQueue winners; external calls to coin.creditFlip/creditFlipBatch |

**Category C: Private/Internal State-Changing Helpers (35 functions)**

Traced via parent call trees per D-03. Functions marked [MULTI-PARENT] get standalone analysis for differing cached-local contexts. Functions marked [BAF-CRITICAL] are on the original BAF bug path.

| # | Function | Lines | Called By | Key State Writes | Flags |
|---|----------|-------|----------|-----------------|-------|
| C1 | `_runEarlyBirdLootboxJackpot()` | 772-835 | B2 | futurePrizePool (deduct), nextPrizePool (credit), ticketQueue via _queueTickets | |
| C2 | `_distributeYieldSurplus()` | 883-914 | B5 | claimableWinnings (via _addClaimableEth), claimablePool, yieldAccumulator | BAF-PATH |
| C3 | `_addClaimableEth()` | 928-949 | C2, C11, C13, C14, C16 | claimableWinnings (direct), OR futurePrizePool/nextPrizePool (via auto-rebuy), ticketQueue | [MULTI-PARENT] [BAF-CRITICAL] |
| C4 | `_processAutoRebuy()` | 959-999 | C3 | futurePrizePool or nextPrizePool (via _setFuturePrizePool/_setNextPrizePool), ticketQueue (via _queueTickets), claimableWinnings (reserved portion) | [BAF-CRITICAL] |
| C5 | `_distributeLootboxAndTickets()` | 1050-1073 | B2 | nextPrizePool, ticketQueue (via _distributeTicketJackpot -> ... -> _queueTickets) | |
| C6 | `_distributeTicketJackpot()` | 1076-1109 | C5, B3 | ticketQueue via _distributeTicketsToBuckets chain | [MULTI-PARENT] |
| C7 | `_distributeTicketsToBuckets()` | 1112-1146 | C6 | ticketQueue via _distributeTicketsToBucket | |
| C8 | `_distributeTicketsToBucket()` | 1149-1190 | C7 | ticketQueue (via _queueTickets) | |
| C9 | `_executeJackpot()` | 1280-1294 | B2 (early-burn path) | claimableWinnings, claimablePool (via _runJackpotEthFlow) | |
| C10 | `_runJackpotEthFlow()` | 1297-1322 | C9 | claimableWinnings, claimablePool (via _distributeJackpotEth) | |
| C11 | `_processDailyEth()` | 1338-1433 | B2 (daily path) | claimableWinnings (via _addClaimableEth per winner), claimablePool | [BAF-PATH] |
| C12 | `_distributeJackpotEth()` | 1435-1474 | B1, C10 | claimableWinnings (via _processOneBucket -> _resolveTraitWinners -> _addClaimableEth), claimablePool | [MULTI-PARENT] [BAF-PATH] |
| C13 | `_processOneBucket()` | 1477-1504 | C12 | claimableWinnings, claimablePool (via _resolveTraitWinners) | |
| C14 | `_resolveTraitWinners()` | 1528-1655 | C13 | claimableWinnings (via _addClaimableEth or _creditJackpot), claimablePool (aggregated by caller), whalePassClaims, futurePrizePool (via _processSoloBucketWinner) | [BAF-PATH] |
| C15 | `_creditJackpot()` | 1663-1676 | C14 | claimableWinnings (via _addClaimableEth) or coin.creditFlip (external) | |
| C16 | `_processSoloBucketWinner()` | 1684-1717 | C14 | claimableWinnings (via _creditJackpot), whalePassClaims, futurePrizePool | [BAF-PATH] |
| C17 | `_resolveZeroOwedRemainder()` | 1877-1904 | C18 | ticketsOwedPacked | |
| C18 | `_processOneTicketEntry()` | 1907-1970 | B6 | ticketsOwedPacked, traitBurnTicket (via _generateTicketBatch) | |
| C19 | `_generateTicketBatch()` | 1973-1993 | C18 | traitBurnTicket (via _raritySymbolBatch -- inline Yul assembly) | |
| C20 | `_raritySymbolBatch()` | 2050-2145 | C19 | traitBurnTicket (inline Yul SSTORE -- manual slot math) | [ASSEMBLY] |
| C21 | `_finalizeTicketEntry()` | 1996-2021 | C18 | ticketsOwedPacked | |
| C22 | `_awardDailyCoinToTraitWinners()` | 2341-2438 | B3, B7 | coin.creditFlip/creditFlipBatch (external calls only, no storage) | [MULTI-PARENT] |
| C23 | `_awardFarFutureCoinJackpot()` | 2444-2529 | B3, B7 | coin.creditFlipBatch (external calls only, no storage) | [MULTI-PARENT] |
| C24 | `_syncDailyWinningTraits()` | 2550-2558 | B2, B7 | lastDailyJackpotWinningTraits, lastDailyJackpotLevel, lastDailyJackpotDay | [MULTI-PARENT] |
| C25 | `_clearDailyEthState()` | 2708-2714 | B2 | dailyEthPhase, dailyEthPoolBudget, dailyCarryoverEthPool, dailyCarryoverWinnerCap, dailyJackpotCoinTicketsPending | |
| C26 | `_creditClaimable()` [PayoutUtils] | PU:30-36 | C3, C4 | claimableWinnings[beneficiary] | |
| C27 | `_calcAutoRebuy()` [PayoutUtils] | PU:38-72 | C4 | pure calculation, no storage writes | |
| C28 | `_queueWhalePassClaimCore()` [PayoutUtils] | PU:75-91 | various | whalePassClaims, claimableWinnings, claimablePool | |
| C29 | `_creditDgnrsCoinflip()` | 2269-2275 | B5 | coin.creditFlip (external) | |
| C30 | `_validateTicketBudget()` | 1024-1031 | B2 | view-only helper (returns 0 or budget) | |
| C31 | `_packDailyTicketBudgets()` | 2676-2687 | B2 | pure packing | |
| C32 | `_unpackDailyTicketBudgets()` | 2689-2705 | B2, B3 | pure unpacking | |
| C33 | `_selectCarryoverSourceOffset()` | 2631-2674 | B2 | view-only | |
| C34 | `_highestCarryoverSourceOffset()` | 2613-2626 | C33 | view-only | |
| C35 | `_rollRemainder()` | 2024-2031 | C17, C21 | pure | |

**Note on C30-C35:** Several of these are view/pure but are listed as C-category because they are called exclusively within state-changing parent chains and the Taskmaster must verify they exist. The planner may reclassify some to Category D during checklist construction -- this is expected and acceptable.

**Category D: View/Pure (13 functions)**

| # | Function | Lines | Purpose |
|---|----------|-------|---------|
| D1 | `_hasTraitTickets()` | 1002-1021 | View: checks if any packed traits have tickets at a level |
| D2 | `_budgetToTicketUnits()` | 1034-1041 | Pure: converts ETH budget to ticket units |
| D3 | `_computeBucketCounts()` | 1193-1245 | View: computes winner counts for active trait buckets |
| D4 | `_futureKeepBps()` | 1252-1267 | Pure: level-100 keep roll calculation (5-dice) |
| D5 | `_getWinningTraits()` | 1729-1763 | View: derives winning trait IDs from entropy |
| D6 | `_topHeroSymbol()` | 1767-1795 | View: finds top hero symbol for daily override |
| D7 | `_randTraitTicket()` | 2160-2203 | View: selects random winners from trait ticket pool |
| D8 | `_randTraitTicketWithIndices()` | 2206-2260 | View: same as D7 plus ticket indices |
| D9 | `_calculateDayIndex()` | 2265-2267 | View: current day index |
| D10 | `_rollWinningTraits()` | 2533-2548 | View: rolls or derives packed winning traits |
| D11 | `_loadDailyWinningTraits()` | 2560-2567 | View: loads stored daily winning traits |
| D12 | `_calcDailyCoinBudget()` | 2570-2574 | View: calculates 0.5% of target in BURNIE |
| D13 | `_dailyCurrentPoolBps()` | 2579-2592 | Pure: daily jackpot share percentage (6-14%) |
| D14 | `_hasActualTraitTickets()` | 2595-2609 | View: checks for non-virtual trait tickets |
| D15 | `_selectDailyCoinTargetLevel()` | 2328-2338 | View: picks random level for coin jackpot |

**Total: 55 functions (7 Category B + 35 Category C + 13-15 Category D)**

The exact B/C/D boundary for view-only helpers in the C-range (C30-C35) may shift during Taskmaster checklist construction. The total count of state-changing functions that need full analysis is ~42 (7B + 35C).

### Risk Tiers for Mad Genius Ordering

**Tier 1 (CRITICAL -- 5 functions):** BAF-critical paths and complex multi-path entry points
- B2 `payDailyJackpot()` -- 325 lines, 3 major paths, prize pool accounting, calls _addClaimableEth through multiple chains
- B5 `consolidatePrizePools()` -- Pool merging, yield surplus, calls _addClaimableEth for VAULT and SDGNRS
- B6 `processTicketBatch()` -- Gas-bounded iteration, inline Yul assembly, manual storage slot math
- C3 `_addClaimableEth()` -- [MULTI-PARENT] The BAF bug function; auto-rebuy path writes to futurePrizePool
- C4 `_processAutoRebuy()` -- Writes futurePrizePool or nextPrizePool; must verify no ancestor caches these

**Tier 2 (HIGH -- 6 functions):** Significant ETH flows and deep call chains
- B1 `runTerminalJackpot()` -- Terminal jackpot execution, bucket distribution
- C2 `_distributeYieldSurplus()` -- Yield accounting with BAF-path _addClaimableEth calls
- C11 `_processDailyEth()` -- Per-winner ETH distribution loop with _addClaimableEth
- C14 `_resolveTraitWinners()` -- Multi-path winner resolution (ETH vs COIN, solo vs normal)
- C16 `_processSoloBucketWinner()` -- Whale pass conversion, futurePrizePool write
- C20 `_raritySymbolBatch()` -- Inline Yul assembly with manual storage slot calculation

**Tier 3 (MEDIUM -- remainder):** Standard distribution paths, coin payouts, ticket mechanics

### BAF-Critical Call Chain Analysis

The BAF pattern to hunt: an ancestor function caches a storage value locally, a descendant writes to that same storage slot, and the ancestor continues using its stale local value (overwriting the descendant's update).

**Primary BAF chain in JackpotModule:**

```
_processDailyEth() [line 1338]
  |-- loops over 4 buckets, calling per winner:
  |   _addClaimableEth(w, perWinner, entropyState) [line 1407]
  |     |-- if autoRebuy enabled:
  |     |   _processAutoRebuy(player, weiAmount, entropy, state) [line 941]
  |     |     |-- _calcAutoRebuy() [PayoutUtils line 38] -- pure, SAFE
  |     |     |-- _queueTickets(player, targetLevel, ticketCount) [line 979]
  |     |     |-- _setFuturePrizePool(_getFuturePrizePool() + calc.ethSpent) [line 982]
  |     |     |   ^^ CRITICAL: Writes prizePoolsPacked (future component)
  |     |     |-- _setNextPrizePool(_getNextPrizePool() + calc.ethSpent) [line 984]
  |     |     |   ^^ CRITICAL: Writes prizePoolsPacked (next component)
  |     |     |-- _creditClaimable(player, calc.reserved) [line 988]
  |     |     |   ^^ Writes claimableWinnings[player]
  |     |     |-- returns calc.reserved (NOT weiAmount)
  |     |-- else (no autoRebuy):
  |         _creditClaimable(beneficiary, weiAmount) [line 947]
  |         returns weiAmount
  |
  |-- After loop: claimablePool += liabilityDelta [line 1430]
```

**Key question for Mad Genius:** Does _processDailyEth (or any of its callers) cache futurePrizePool, nextPrizePool, or currentPrizePool in a local variable before the loop? If so, the _processAutoRebuy write to these pools would be overwritten.

**Preliminary trace (HIGH confidence):**
- `_processDailyEth` does NOT cache futurePrizePool or nextPrizePool locally -- it only caches `ethPool` (the budget parameter) and `liabilityDelta` (cumulative tracking). The futurePrizePool/nextPrizePool writes in _processAutoRebuy go through `_getFuturePrizePool()` and `_setFuturePrizePool()` which read/write storage directly each time. This appears SAFE but the Mad Genius must verify every ancestor in every call path.
- `payDailyJackpot` (B2) caches `poolSnapshot = currentPrizePool` at line 353 and later writes `currentPrizePool -= paidDailyEth` at line 503. The _addClaimableEth chain does NOT write currentPrizePool -- it writes futurePrizePool and nextPrizePool. So the `poolSnapshot` cache is SAFE.
- `_distributeYieldSurplus` (C2) reads `currentPrizePool + _getNextPrizePool() + claimablePool + _getFuturePrizePool() + yieldAccumulator` as `obligations` at lines 886-890, then calls `_addClaimableEth` which can write futurePrizePool and claimablePool. However, `obligations` is only used for the surplus comparison (line 892) and is not written back to storage. The subsequent writes (`claimablePool += claimableDelta` at line 911, `yieldAccumulator +=` at line 913) use fresh storage reads. This needs CAREFUL verification by the Mad Genius.

### Inline Assembly Risk Area

`_raritySymbolBatch()` (lines 2050-2145) contains inline Yul assembly that manually computes storage slots for `traitBurnTicket` mapping and performs raw SSTORE operations:

```solidity
assembly ("memory-safe") {
    mstore(0x00, lvl)
    mstore(0x20, traitBurnTicket.slot)
    levelSlot := keccak256(0x00, 0x40)
}
// ... later ...
assembly ("memory-safe") {
    let elem := add(levelSlot, traitId)
    let len := sload(elem)
    let newLen := add(len, occurrences)
    sstore(elem, newLen)
    mstore(0x00, elem)
    let data := keccak256(0x00, 0x20)
    let dst := add(data, len)
    for { let k := 0 } lt(k, occurrences) { k := add(k, 1) } {
        sstore(dst, player)
        dst := add(dst, 1)
    }
}
```

**Attack angles for assembly block:**
1. Storage slot calculation correctness -- does the manual keccak hash match Solidity's auto-generated layout for `traitBurnTicket[lvl][traitId]`?
2. Array length accounting -- does `add(len, occurrences)` correctly track the dynamic array length?
3. Data slot calculation -- does `keccak256(elem)` correctly compute the dynamic array data start?
4. Collision risk -- can two different (lvl, traitId) pairs produce the same slot?
5. Memory safety -- the `memory-safe` annotation claims no scratch space corruption; verify.

### Subsystem Map

The contract organizes into distinct subsystems that can guide report splitting:

**ETH Distribution Subsystem:**
- B2 payDailyJackpot (entry)
- B1 runTerminalJackpot (entry)
- B5 consolidatePrizePools (entry)
- C2 _distributeYieldSurplus
- C9 _executeJackpot, C10 _runJackpotEthFlow
- C11 _processDailyEth, C12 _distributeJackpotEth
- C13 _processOneBucket, C14 _resolveTraitWinners
- C15 _creditJackpot, C16 _processSoloBucketWinner

**BAF-Critical Payout Subsystem:**
- C3 _addClaimableEth (hub)
- C4 _processAutoRebuy
- C26 _creditClaimable [PayoutUtils]
- C27 _calcAutoRebuy [PayoutUtils]
- C28 _queueWhalePassClaimCore [PayoutUtils]

**Coin/BURNIE Jackpot Subsystem:**
- B7 payDailyCoinJackpot (entry)
- B3 payDailyJackpotCoinAndTickets (entry)
- B4 awardFinalDayDgnrsReward (entry)
- C22 _awardDailyCoinToTraitWinners
- C23 _awardFarFutureCoinJackpot
- C29 _creditDgnrsCoinflip

**Ticket Distribution Subsystem:**
- B6 processTicketBatch (entry)
- C5 _distributeLootboxAndTickets
- C6 _distributeTicketJackpot, C7 _distributeTicketsToBuckets, C8 _distributeTicketsToBucket
- C17 _resolveZeroOwedRemainder, C18 _processOneTicketEntry
- C19 _generateTicketBatch, C20 _raritySymbolBatch
- C21 _finalizeTicketEntry

**Trait/Winner Selection (View -- used by all subsystems):**
- D5 _getWinningTraits, D6 _topHeroSymbol
- D7 _randTraitTicket, D8 _randTraitTicketWithIndices
- D10 _rollWinningTraits, D3 _computeBucketCounts

### Cross-Module External Calls

JackpotModule makes the following external calls (not delegatecall -- actual cross-contract calls to other deployed contracts):

| Call | From Functions | Target | State Impact |
|------|---------------|--------|-------------|
| `coin.creditFlip(addr, amount)` | C15, C29, B2 (via rollDailyQuest) | BurnieCoin | BURNIE minting to player |
| `coin.creditFlipBatch(players, amounts)` | C22, C23 | BurnieCoin | Batch BURNIE minting |
| `coin.rollDailyQuest(day, rngWord)` | B2, B3 | BurnieCoin | Quest state update |
| `dgnrs.transferFromPool(pool, to, amount)` | B4 | StakedDegenerusStonk | sDGNRS transfer from reward pool |
| `dgnrs.poolBalance(pool)` | B4 | StakedDegenerusStonk | View: reward pool balance |
| `steth.balanceOf(address(this))` | C2 | Lido stETH | View: stETH balance |

Per D-08, these external calls are traced only for state coherence verification. Full internals of BurnieCoin, StakedDegenerusStonk are in their own unit phases.

### Multi-Parent Functions Requiring Standalone Analysis

Per D-03, these functions are called from multiple parents with potentially different cached-local states:

| Function | Parents | Why Standalone |
|----------|---------|---------------|
| C3 `_addClaimableEth` | C2, C11, C14 (via C15), C16 (via C15) | Different callers may have different storage cached; BAF-CRITICAL |
| C6 `_distributeTicketJackpot` | C5, B3 | Different entropy and maxWinners parameters |
| C12 `_distributeJackpotEth` | B1, C10 | Called from runTerminalJackpot (external params) and _runJackpotEthFlow (daily params) |
| C22 `_awardDailyCoinToTraitWinners` | B3, B7 | Same logic but different callers (Phase 2 daily vs standalone coin jackpot) |
| C23 `_awardFarFutureCoinJackpot` | B3, B7 | Same as above |
| C24 `_syncDailyWinningTraits` | B2, B7 | Different levels and trait sources |

### RNG/Entropy Usage Map

All RNG words arrive as parameters (not read from storage within JackpotModule). The module uses them for:

| Usage | Function(s) | Entropy Derivation | Concern |
|-------|------------|-------------------|---------|
| Winner selection | D7, D8 | `randomWord ^ (trait << 128) ^ (salt << 192)`, then bit rotation | Modulo bias if effectiveLen not power-of-2 (known, intentional per contract docs) |
| Trait rolling | D5, D10 | Direct bit extraction from randomWord | Hero override path uses `_topHeroSymbol` which reads dailyHeroWagers (storage) |
| Bucket sizing | B2, B1 | Via JackpotBucketLib functions | Library audit deferred to Phase 117 |
| Solo bucket index | C11, C14 | `JackpotBucketLib.soloBucketIndex(entropy)` | 2-bit extraction |
| Auto-rebuy level | C27 [PayoutUtils] | `entropyStep(entropy ^ player ^ weiAmount) & 3` | 1-4 levels ahead |
| Daily BPS roll | D13 | `keccak256(randWord, tag, counter) % range` | 6-14% range |
| Future keep BPS | D4 | 5-dice keccak derivation | 30-65% range |
| Carryover source | C33 | `keccak256(randWord, tag, counter) % highestEligible` | Wrapping probe |
| LCG trait generation | C20 | `seed * TICKET_LCG_MULT + 1` | Knuth MMIX LCG in assembly; full period guaranteed by odd seed |
| Far-future level selection | C23 | `entropy % 95` for level in [lvl+5, lvl+99] | |

Per D-10, the Mad Genius must verify fresh that each RNG usage is sound (unknown at commitment time, not manipulable between request and fulfillment). Since JackpotModule receives RNG words as parameters from advanceGame (already audited in Phase 104), the primary concern is whether the module's derivations introduce bias or predictability.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Bucket share calculation | Manual BPS arithmetic | JackpotBucketLib.bucketShares() | Complex rounding, remainder assignment, gas-optimal |
| Winner count scaling | Manual capacity math | JackpotBucketLib.scaleTraitBucketCountsWithCap() | Gas budgeting with pool-size-dependent scaling |
| Trait packing/unpacking | Manual bit ops | JackpotBucketLib.packWinningTraits/unpackWinningTraits | Consistent 8-bit packing across all callers |
| Storage slot math for arrays | Solidity high-level access | Inline Yul (already used in _raritySymbolBatch) | Gas optimization for batch writes; BUT this is a prime audit target |

## Common Pitfalls

### Pitfall 1: Liability Tracking Mismatch (claimablePool vs claimableWinnings sum)
**What goes wrong:** Individual claimableWinnings[player] credits accumulate via _addClaimableEth, but the aggregate claimablePool is updated separately (often batched after a loop). If a code path credits claimableWinnings without incrementing claimablePool, the protocol becomes under-reserved.
**Why it happens:** _addClaimableEth returns `claimableDelta` which the caller must accumulate and add to claimablePool. If a caller forgets to add it, or adds the wrong amount, the invariant breaks.
**How to avoid:** For every call to _addClaimableEth, verify the return value is accumulated into claimablePool (either inline or after the loop).
**Warning signs:** A function calling _addClaimableEth that does not have a `claimablePool +=` anywhere in its body or in its immediate caller.

### Pitfall 2: Auto-Rebuy Diverts ETH Without Tracking
**What goes wrong:** When auto-rebuy is enabled, _processAutoRebuy sends ETH to futurePrizePool or nextPrizePool (ticket backing) and returns only the `reserved` amount as claimableDelta. The caller tracks liability as if `reserved` wei was credited. If the caller ALSO adds the full `weiAmount` to some pool accounting, the ETH is double-counted.
**Why it happens:** _addClaimableEth returns different values depending on auto-rebuy state. With auto-rebuy off: returns weiAmount. With auto-rebuy on: returns calc.reserved (just the take-profit portion).
**How to avoid:** Callers must use the returned claimableDelta for liability tracking, not the original weiAmount.
**Warning signs:** A caller that passes `weiAmount` to _addClaimableEth but then uses `weiAmount` (instead of the return value) for pool accounting.

### Pitfall 3: Assembly Storage Slot Miscalculation
**What goes wrong:** The inline Yul in _raritySymbolBatch manually computes storage slots using keccak256. If the slot calculation doesn't match Solidity's standard layout for `mapping(uint24 => address[256])`, data is written to wrong slots, potentially corrupting unrelated storage.
**Why it happens:** Solidity's storage layout for nested mappings with fixed-size arrays is well-defined but easy to get wrong in manual assembly.
**How to avoid:** Verify the keccak256(key, slot) calculation matches the expected layout. Cross-reference with DegenerusGameStorage.sol's variable declarations to confirm `traitBurnTicket.slot` is correct.
**Warning signs:** Any assembly block that computes storage slots manually.

### Pitfall 4: Gas-Bounded Iteration Leaving Inconsistent State
**What goes wrong:** processTicketBatch uses a writes budget to bound gas. If processing is interrupted mid-batch, the state must be consistent for resumption. If ticketCursor or ticketLevel is updated incorrectly, tickets can be skipped or double-processed.
**Why it happens:** The batch processor has complex resume logic with `ticketCursor`, `ticketLevel`, and per-player `ticketsOwedPacked` tracking partial progress.
**How to avoid:** Verify that every early-exit path from the processing loop correctly saves cursor state, and that resumption picks up exactly where processing left off.
**Warning signs:** An exit path that returns without updating ticketCursor.

### Pitfall 5: Prize Pool Accounting Drift
**What goes wrong:** Multiple functions manipulate prize pools (currentPrizePool, nextPrizePool, futurePrizePool) in the same transaction. If one function deducts from currentPrizePool and a descendant adds to futurePrizePool via auto-rebuy, the total protocol balance must still equal `currentPrizePool + nextPrizePool + futurePrizePool + claimablePool + yieldAccumulator`. Any leak or double-count breaks solvency.
**Why it happens:** Prize pool manipulation is distributed across many functions with different accounting models (upfront deduction, post-loop reconciliation, etc.).
**How to avoid:** The Mad Genius must trace every ETH flow from pool deduction to destination (claimableWinnings, nextPrizePool, futurePrizePool) and verify conservation.
**Warning signs:** A function that deducts from one pool but the destination pool credit depends on a branch that might not execute.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Foundry (forge) |
| Config file | foundry.toml |
| Quick run command | `forge test --match-contract JackpotModule -vvv --no-match-test testFork` |
| Full suite command | `forge test -vvv --no-match-test testFork` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| UNIT-03 | Full audit of JackpotModule + PayoutUtils | manual (audit report) | N/A -- audit deliverables, not code tests | N/A |
| COV-01 | Taskmaster coverage checklist | manual (document review) | N/A | N/A |
| COV-02 | Checklist sign-off columns | manual (document review) | N/A | N/A |
| COV-03 | PASS verdict before Skeptic | manual (process gate) | N/A | N/A |
| ATK-01-05 | Attack report with call trees, storage maps, findings | manual (audit analysis) | N/A | N/A |
| VAL-01-04 | Skeptic verdicts on all findings | manual (review) | N/A | N/A |

### Sampling Rate
- **Per task commit:** Verify output file exists and follows ULTIMATE-AUDIT-DESIGN.md format
- **Per wave merge:** Cross-reference function counts between Taskmaster checklist and attack report
- **Phase gate:** All 5 success criteria from phase description verified

### Wave 0 Gaps
None -- this phase produces audit documents, not code. No test infrastructure needed. The `audit/unit-03/` directory will be created during Plan 1 execution.

## Code Examples

### Pattern: _addClaimableEth Return Value Usage (BAF-Critical)

The correct pattern for calling _addClaimableEth and tracking liability:

```solidity
// CORRECT (from _processDailyEth, lines 1403-1420):
uint256 claimableDelta = _addClaimableEth(w, perWinner, entropyState);
paidEth += perWinner;
liabilityDelta += claimableDelta;  // Uses RETURN VALUE, not perWinner
// ... after loop ...
if (liabilityDelta != 0) {
    claimablePool += liabilityDelta;  // Aggregate update
}

// INCORRECT (hypothetical -- the bug to look for):
_addClaimableEth(w, perWinner, entropyState);
claimablePool += perWinner;  // WRONG: uses perWinner, not return value
// If auto-rebuy diverts some ETH, claimablePool is over-counted
```

### Pattern: processTicketBatch Resume Logic

```solidity
// Correct resume pattern (lines 1818-1829):
if (ticketLevel != lvl) {
    ticketLevel = lvl;      // Switch to new level
    ticketCursor = 0;       // Reset cursor
}
uint256 idx = ticketCursor; // Resume from saved position
if (idx >= total) {
    delete ticketQueue[rk]; // Cleanup
    ticketCursor = 0;
    ticketLevel = 0;
    return true;            // Done
}
```

### Pattern: _distributeYieldSurplus Obligations Check

```solidity
// Lines 884-892 -- obligations snapshot for surplus calculation:
uint256 stBal = steth.balanceOf(address(this));
uint256 totalBal = address(this).balance + stBal;
uint256 obligations = currentPrizePool +
    _getNextPrizePool() +
    claimablePool +
    _getFuturePrizePool() +
    yieldAccumulator;
if (totalBal <= obligations) return;
// NOTE: After this point, _addClaimableEth calls may change
// futurePrizePool and claimablePool -- but 'obligations' is only
// used for the initial comparison, not written back to storage.
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Per-winner SSTORE for claimablePool | Batched liability tracking with post-loop claimablePool update | v4.x | Gas optimization: 1 SSTORE per distribution instead of N |
| Single jackpot distribution pass | Two-phase distribution (ETH in Phase 1, coin+tickets in Phase 2) | v4.x | Gas budgeting to stay under 15M block limit |
| Full ticket processing per call | Gas-bounded batch processing with cursor resume | v4.x | Prevents OOG on large ticket queues |
| High-level Solidity for trait assignment | Inline Yul assembly batch writes | v4.x | Gas optimization for bulk trait storage |

## Open Questions

1. **_processSoloBucketWinner whale pass pricing**
   - What we know: Uses `HALF_WHALE_PASS_PRICE = 2.25 ether` constant. 25% of winnings go to whale passes if enough to cover at least one half-pass.
   - What's unclear: Is 2.25 ETH per half-pass aligned with the current game economics? The whale pass price might be defined elsewhere and could drift.
   - Recommendation: The Mad Genius should verify that the whale pass price constant is consistent with the MintModule's whale pass pricing. Cross-module price inconsistency would be an economic finding.

2. **LCG quality for trait generation**
   - What we know: Uses Knuth's MMIX LCG constant (0x5851F42D4C957F2D) with full-period guarantee via odd seed.
   - What's unclear: Whether the LCG output quality is sufficient for trait generation or introduces exploitable bias.
   - Recommendation: The Mad Genius should check if a player could predict their trait distribution given knowledge of their position in the ticket queue and the public VRF word. If predictable, assess economic impact.

3. **Virtual deity entry sizing**
   - What we know: `virtualCount = len / 50; if (virtualCount < 2) virtualCount = 2;`
   - What's unclear: When `len == 0`, `virtualCount = 2` (deity gets 2 virtual entries out of 2 total = 100% win rate). Is this intended?
   - Recommendation: Flag for the Mad Genius to verify. If a deity symbol has zero real tickets, the deity wins 100% of draws for that trait. This is by design per the comment "more tickets = more chances" but could be an economic concern.

## Sources

### Primary (HIGH confidence)
- `contracts/modules/DegenerusGameJackpotModule.sol` -- Full 2,715-line source read
- `contracts/modules/DegenerusGamePayoutUtils.sol` -- Full 92-line source read
- `.planning/ULTIMATE-AUDIT-DESIGN.md` -- Three-agent system design and format requirements
- `.planning/phases/105-jackpot-distribution/105-CONTEXT.md` -- User decisions (D-01 through D-11)
- `audit/unit-01/COVERAGE-CHECKLIST.md` -- Taskmaster format reference
- `audit/unit-02/ATTACK-REPORT.md` -- Mad Genius format reference

### Secondary (MEDIUM confidence)
- `.planning/phases/104-day-advancement-vrf/104-RESEARCH.md` -- Cross-module delegatecall map showing how advanceGame calls into JackpotModule
- `.planning/STATE.md` -- Prior phase outcomes (Phase 103: 0 confirmed findings, Phase 104: 0 confirmed vulnerabilities)

## Metadata

**Confidence breakdown:**
- Function inventory: HIGH -- complete source read of both contracts, grep-verified function count
- BAF-critical path analysis: HIGH -- traced _addClaimableEth -> _processAutoRebuy chain line-by-line from source
- Architecture patterns: HIGH -- established in Phases 103-104, same methodology
- Pitfalls: HIGH -- derived from actual code patterns, not theoretical
- RNG analysis: MEDIUM -- JackpotModule receives RNG as parameters; derivation quality (LCG, modulo bias) needs Mad Genius verification
- Inline assembly: MEDIUM -- identified the code block and attack angles but manual Yul verification requires Mad Genius deep-dive

**Research date:** 2026-03-25
**Valid until:** 2026-04-25 (stable -- contract code is fixed for audit)
