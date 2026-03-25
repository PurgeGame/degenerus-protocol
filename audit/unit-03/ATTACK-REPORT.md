# Unit 3: Jackpot Distribution -- Attack Report

**Agent:** Mad Genius (Attacker)
**Contracts:** DegenerusGameJackpotModule.sol (2,715 lines), DegenerusGamePayoutUtils.sol (92 lines)
**Date:** 2026-03-25
**Methodology:** Per ULTIMATE-AUDIT-DESIGN.md -- full call-tree expansion, storage-write mapping, cached-local-vs-storage check, 10-angle attack analysis. BAF-critical chain re-audited from scratch per D-07 (v4.4 fix treated as nonexistent).

---

## Findings Summary

| ID | Function | Verdict | Severity | Title |
|----|----------|---------|----------|-------|
| F-01 | _distributeYieldSurplus (C2) | INVESTIGATE | INFO | Yield surplus `obligations` snapshot includes stale claimablePool after _addClaimableEth writes |
| F-02 | _raritySymbolBatch (C20) | INVESTIGATE | INFO | Assembly uses `add(levelSlot, traitId)` for inner mapping -- correct for Solidity nested mapping but non-obvious |
| F-03 | processTicketBatch (B6) | INVESTIGATE | INFO | `processed` counter approximation via `writesUsed >> 1` may cause LCG seed drift on resume |
| F-04 | payDailyJackpot (B2) | INVESTIGATE | INFO | Double `_getFuturePrizePool()` read in earlybird deduction (line 778) reads twice from same SLOAD |
| F-05 | _processAutoRebuy (C4) | INVESTIGATE | INFO | `calc.reserved` can be 0 when takeProfit is 0 -- entire winnings converted to tickets with no claimable credit |

**Confirmed VULNERABLE:** 0
**INVESTIGATE:** 5 (all INFO-severity)
**SAFE:** All 7 Category B functions, all multi-parent helpers

---

## Risk-Tier Analysis Order

1. **Tier 1:** B2 payDailyJackpot, B5 consolidatePrizePools, B6 processTicketBatch, C3 _addClaimableEth, C4 _processAutoRebuy
2. **Tier 2:** B1 runTerminalJackpot, C2 _distributeYieldSurplus, C11 _processDailyEth, C14 _resolveTraitWinners, C16 _processSoloBucketWinner, C20 _raritySymbolBatch
3. **Tier 3:** B3 payDailyJackpotCoinAndTickets, B4 awardFinalDayDgnrsReward, B7 payDailyCoinJackpot, remaining C functions

---

## ETH Distribution Subsystem

### JackpotModule::payDailyJackpot() (B2, line 313-637)

#### Call Tree
```
payDailyJackpot(isDaily, lvl, randWord) [L313]
  |-- _calculateDayIndex() [L318] -> _simulatedDayIndex() (inherited, view)
  |
  |-- [isDaily=true, fresh start]:
  |   |-- _rollWinningTraits(lvl, randWord, true) [L332] (view)
  |   |-- _syncDailyWinningTraits(lvl, packed, questDay) [L333] = C24
  |   |   |-- writes lastDailyJackpotWinningTraits [L2555]
  |   |   |-- writes lastDailyJackpotLevel [L2556]
  |   |   |-- writes lastDailyJackpotDay [L2557]
  |   |-- _dailyCurrentPoolBps(counter, randWord) [L358] (pure)
  |   |-- _runEarlyBirdLootboxJackpot(lvl+1, randWord) [L369] = C1
  |   |   |-- _getFuturePrizePool() [L774] -> _getPrizePools() [L655]
  |   |   |-- _setFuturePrizePool(_getFuturePrizePool() - reserveContribution) [L778]
  |   |   |   |-- _getPrizePools() [L746] -> prizePoolsPacked SLOAD
  |   |   |   |-- _setPrizePools(next, newFuture) [L753] -> prizePoolsPacked SSTORE
  |   |   |-- PriceLookupLib.priceForLevel() [L791] (pure)
  |   |   |-- _randTraitTicket() [L803] (view) = D7
  |   |   |-- EntropyLib.entropyStep() [L801, L813] (pure)
  |   |   |-- _queueTickets(winner, level, count) [L819] (inherited)
  |   |   |   |-- writes ticketQueue[wk], ticketsOwedPacked[wk][buyer]
  |   |   |-- _getNextPrizePool() [L834] -> _getPrizePools()
  |   |   |-- _setNextPrizePool(_getNextPrizePool() + totalBudget) [L834]
  |   |   |   |-- _getPrizePools() -> prizePoolsPacked SLOAD
  |   |   |   |-- _setPrizePools(newNext, future) -> prizePoolsPacked SSTORE
  |   |-- _validateTicketBudget() [L373] (view) = D17
  |   |-- writes dailyEthPoolBudget [L382]
  |   |-- _budgetToTicketUnits() [L385] (pure) = D2
  |   |-- writes currentPrizePool [L391]
  |   |-- _setNextPrizePool(_getNextPrizePool() + dailyLootboxBudget) [L392]
  |   |-- _selectCarryoverSourceOffset() [L398] (view) = D20
  |   |-- _getFuturePrizePool() [L415]
  |   |-- _setFuturePrizePool(_getFuturePrizePool() - reserveSlice) [L418]
  |   |-- _validateTicketBudget() [L425] (view)
  |   |-- _setNextPrizePool(_getNextPrizePool() + carryoverLootboxBudget) [L433]
  |   |-- _packDailyTicketBudgets() [L447] (pure) = D18
  |   |-- writes dailyTicketBudgetsPacked [L447]
  |   |-- writes dailyCarryoverEthPool [L455]
  |   |-- writes dailyEthPhase [L457]
  |
  |-- [isDaily=true, Phase 0 execution]:
  |   |-- _unpackDailyTicketBudgets() [L468] (pure) = D19
  |   |-- JackpotBucketLib.bucketCountsForPoolCap() [L476] (pure)
  |   |-- JackpotBucketLib.shareBpsByBucket() [L489] (pure)
  |   |-- _processDailyEth(lvl, budget, ...) [L495] = C11
  |   |   |-- (see C11 call tree below)
  |   |-- writes currentPrizePool -= paidDailyEth [L503]
  |   |-- writes dailyCarryoverWinnerCap [L508-519]
  |   |-- _clearDailyEthState() [L526] = C25 (if no carryover)
  |   |-- writes dailyEthPhase = 1 [L530] (if carryover needed)
  |
  |-- [isDaily=true, Phase 1 execution]:
  |   |-- _processDailyEth(carryoverSourceLevel, carryPool, ...) [L565] = C11
  |   |-- _clearDailyEthState() [L575] = C25
  |
  |-- [isDaily=false, early-burn path]:
  |   |-- _rollWinningTraits(lvl, randWord, false) [L581] (view)
  |   |-- _syncDailyWinningTraits() [L582] = C24
  |   |-- _getFuturePrizePool() [L601]
  |   |-- _setFuturePrizePool(_getFuturePrizePool() - ethDaySlice) [L604]
  |   |-- _validateTicketBudget() [L610] (view)
  |   |-- _executeJackpot(jp) [L617] = C9
  |   |   |-- _runJackpotEthFlow() [L1292] = C10
  |   |   |   |-- _distributeJackpotEth() [L1314] = C12
  |   |   |   |   |-- (see C12 call tree below)
  |   |-- _distributeLootboxAndTickets() [L629] = C5
  |   |   |-- _setNextPrizePool(_getNextPrizePool() + lootboxBudget) [L1058]
  |   |   |-- _distributeTicketJackpot() [L1064] = C6
  |   |   |   |-- (see C6 call tree below)
  |   |-- coin.rollDailyQuest(questDay, randWord) [L637] (external)
```

#### Storage Writes (Full Tree)
| Variable | Slot | Written By | Line |
|----------|------|-----------|------|
| lastDailyJackpotWinningTraits | Slot 51 | _syncDailyWinningTraits (C24) | L2555 |
| lastDailyJackpotLevel | Slot 51 | _syncDailyWinningTraits (C24) | L2556 |
| lastDailyJackpotDay | Slot 51 | _syncDailyWinningTraits (C24) | L2557 |
| prizePoolsPacked (future) | Slot 3 | _setFuturePrizePool via C1 | L778 |
| ticketQueue[wk] | mapping | _queueTickets via C1 | L819 |
| ticketsOwedPacked[wk][buyer] | mapping | _queueTickets via C1 | L547-548 |
| prizePoolsPacked (next) | Slot 3 | _setNextPrizePool via C1 | L834 |
| dailyEthPoolBudget | Slot 9 | direct | L382 |
| currentPrizePool | Slot 2 | direct | L391, L503 |
| prizePoolsPacked (next) | Slot 3 | _setNextPrizePool | L392, L433 |
| prizePoolsPacked (future) | Slot 3 | _setFuturePrizePool | L418, L604 |
| dailyTicketBudgetsPacked | Slot 8 | direct | L447 |
| dailyCarryoverEthPool | Slot 10 | direct | L455 |
| dailyEthPhase | Slot 0 byte 30 | direct | L457, L530 |
| dailyCarryoverWinnerCap | Slot 48 | direct | L508-516 |
| claimableWinnings[w] | mapping | via C11->C3->C26 or C12->C13->C14->C3->C26 | L33 (PU) |
| claimablePool | Slot 11 | via C11 L1430 or C12 L1471 | |
| prizePoolsPacked (future/next) | Slot 3 | via C3->C4->_setFuturePrizePool/_setNextPrizePool | L982-984 |
| ticketQueue[wk] | mapping | via C3->C4->_queueTickets | L979 |
| whalePassClaims[winner] | mapping | via C14->C16 | L1709 |
| dailyEthPhase=0 | Slot 0 | via C25 | L2709 |
| dailyEthPoolBudget=0 | Slot 9 | via C25 | L2710 |
| dailyCarryoverEthPool=0 | Slot 10 | via C25 | L2711 |
| dailyCarryoverWinnerCap=0 | Slot 48 | via C25 | L2712 |
| dailyJackpotCoinTicketsPending=true | Slot 0 | via C25 | L2713 |

#### Cached-Local-vs-Storage Check

**Local caches in B2:**
1. `poolSnapshot = currentPrizePool` [L353] -- used ONLY for budget calculation at L364 (`budget = (poolSnapshot * dailyBps) / 10_000`). NEVER written back to storage. The actual `currentPrizePool -= paidDailyEth` at L503 is a fresh storage read-modify-write.
2. `budget = dailyEthPoolBudget` [L474] -- read from storage, used as parameter to _processDailyEth. Not a prize pool value.
3. `carryPool = dailyCarryoverEthPool` [L536] -- daily-scoped budget, not a prize pool.

**Descendant writes through _addClaimableEth -> _processAutoRebuy:**
- C4 writes `futurePrizePool` (via _setFuturePrizePool at L982) or `nextPrizePool` (via _setNextPrizePool at L984).
- B2 does NOT cache futurePrizePool or nextPrizePool in any local variable that survives across the _processDailyEth call.
- B2's writes to prizePoolsPacked [L392, L418, L433] all happen BEFORE _processDailyEth is called.
- B2's write to currentPrizePool [L503] happens AFTER _processDailyEth returns but writes currentPrizePool, not futurePrizePool/nextPrizePool.

**BAF-pattern pairs:** None found. `poolSnapshot` is read-only. All prize pool writes use fresh storage reads.

**VERDICT: SAFE**

#### Attack Analysis

**State Coherence:** `poolSnapshot` [L353] is used only for budget calculation and never written back. All pool writes after _addClaimableEth use fresh storage reads. VERDICT: SAFE

**Access Control:** External function, called via delegatecall from DegenerusGame.advanceGame. No explicit modifier -- relies on parent contract's call routing. Only reachable through the advanceGame FSM which is VRF-gated. VERDICT: SAFE

**RNG Manipulation:** `randWord` arrives as parameter from advanceGame (VRF-derived, audited in Phase 104). JackpotModule's derivations: `entropyDaily = randWord ^ (uint256(lvl) << 192)` provides level-specific entropy. `_dailyCurrentPoolBps` uses keccak256 domain separation. Winner selection via `_randTraitTicketWithIndices` uses bit rotation. All RNG words are committed via VRF before any player-controllable state changes affecting this function. VERDICT: SAFE

**Cross-Contract State Desync:** External call `coin.rollDailyQuest(questDay, randWord)` [L637] is one-way, fires-and-forgets. No state from BurnieCoin is read after this call. No callback risk. VERDICT: SAFE

**Edge Cases:** Zero budget handled (L475 `if budget != 0`). Empty buckets handled (L523-528 early return). Zero carryover pool handled (L524 check). First day (`counter == 0`) triggers earlybird path and skips carryover. Game-over state: `_addClaimableEth` checks `gameOver` at L937 and skips auto-rebuy. VERDICT: SAFE

**Conditional Paths:** Three major paths (daily fresh, daily resume, early-burn) each fully traced. Daily fresh has sub-paths: earlybird day vs carryover day, final day vs regular day, turbo/compressed/normal compression. All paths lead to valid state. Phase 0/Phase 1 split correctly handles gas budgeting. Resume path correctly reads stored state. VERDICT: SAFE

**Economic/MEV:** Budget is derived from `currentPrizePool * dailyBps / 10_000` at L364. An attacker cannot influence dailyBps (derived from VRF). Pool values are set by prior game logic. No front-running opportunity within a single advanceGame call (atomic). VERDICT: SAFE

**Griefing:** No external attacker input. Function is called by advanceGame FSM only. Cannot be called out of sequence due to FSM guards. VERDICT: SAFE

**Ordering/Sequencing:** Phase 0 must complete before Phase 1 can execute (dailyEthPhase gating at L473/L535). `_clearDailyEthState` resets phase to 0 at completion. If Phase 0 completes with no carryover, state is cleared immediately. If carryover needed, state persists for Phase 1 in next advanceGame call. VERDICT: SAFE

**Silent Failures:** Zero-budget paths return early without error (by design -- empty levels have no prizes). `_processDailyEth` returns 0 for zero ethPool [L1346-1348]. No silent skip of critical logic detected. VERDICT: SAFE

---

### JackpotModule::runTerminalJackpot() (B1, line 272-308)

#### Call Tree
```
runTerminalJackpot(poolWei, targetLvl, rngWord) [L272]
  |-- msg.sender == GAME check [L277] (revert OnlyGame)
  |-- _rollWinningTraits(targetLvl, rngWord, true) [L279] (view)
  |-- JackpotBucketLib.unpackWinningTraits() [L285] (pure)
  |-- JackpotBucketLib.bucketCountsForPoolCap() [L289] (pure)
  |-- JackpotBucketLib.shareBpsByBucket() [L295] (pure)
  |-- _distributeJackpotEth(targetLvl, poolWei, ...) [L300] = C12
  |   |-- (see C12 call tree below)
```

#### Storage Writes (Full Tree)
| Variable | Written By | Line |
|----------|-----------|------|
| claimableWinnings[w] | via C12->C13->C14->C3->C26 or C14->C16->C15->C3->C26 | PU:33 |
| claimablePool | via C12 | L1471 |
| prizePoolsPacked (future/next) | via C14->C3->C4 (auto-rebuy path) | L982-984 |
| ticketQueue, ticketsOwedPacked | via C3->C4->_queueTickets | L979 |
| whalePassClaims[winner] | via C14->C16 | L1709 |
| prizePoolsPacked (future) | via C16->_setFuturePrizePool | L1710 |

#### Cached-Local-vs-Storage Check

B1 receives `poolWei` as parameter (not from storage). No local caches of any prize pool storage values. `paidWei` is the return value from `_distributeJackpotEth`.

C12 uses `JackpotEthCtx` struct with `entropyState`, `liabilityDelta`, `totalPaidEth`, `lvl` -- none are prize pool values. C12's `claimablePool += ctx.liabilityDelta` [L1471] is a fresh storage read-modify-write.

**BAF-pattern pairs:** None. No ancestor caches futurePrizePool, nextPrizePool, or currentPrizePool.

**VERDICT: SAFE**

#### Attack Analysis

**State Coherence:** No cached prize pool values in any ancestor. VERDICT: SAFE
**Access Control:** `msg.sender == ContractAddresses.GAME` [L277] -- only callable by the Game contract (via regular call, not delegatecall). This is used by EndgameModule and GameOverModule which call `IDegenerusGame(address(this)).runTerminalJackpot(...)`. VERDICT: SAFE
**RNG Manipulation:** `rngWord` is VRF-derived, passed from parent. Entropy derivation at L284 uses level XOR. VERDICT: SAFE
**Cross-Contract State Desync:** No external calls in this function's direct code. Subordinate C15 may call `coin.creditFlip` but only on coin-pay path (payCoin=false here, so ETH path). VERDICT: SAFE
**Edge Cases:** `poolWei == 0` results in zero shares and zero payouts (handled by downstream checks). Empty buckets produce zero winners. VERDICT: SAFE
**Conditional Paths:** Single linear path through _distributeJackpotEth. Solo bucket and normal bucket paths in C14 both traced. VERDICT: SAFE
**Economic/MEV:** Terminal jackpots run during level transitions. No attacker influence on poolWei. VERDICT: SAFE
**Griefing:** Cannot be called by external attackers (OnlyGame guard). VERDICT: SAFE
**Ordering/Sequencing:** Called at specific points in the level transition FSM. Cannot be invoked out of order. VERDICT: SAFE
**Silent Failures:** Zero pool produces zero paidWei return (correct behavior). VERDICT: SAFE

---

### JackpotModule::consolidatePrizePools() (B5, line 850-879)

#### Call Tree
```
consolidatePrizePools(lvl, rngWord) [L850]
  |-- [if lvl % 100 == 0]:
  |   |-- reads yieldAccumulator [L853]
  |   |-- _getFuturePrizePool() [L855]
  |   |-- _setFuturePrizePool(_getFuturePrizePool() + half) [L855]
  |   |-- writes yieldAccumulator = acc - half [L856]
  |-- currentPrizePool += _getNextPrizePool() [L860]
  |-- _setNextPrizePool(0) [L861]
  |-- [if lvl % 100 == 0]:
  |   |-- _futureKeepBps(rngWord) [L864] (pure) = D4
  |   |-- _getFuturePrizePool() [L865]
  |   |-- _setFuturePrizePool(keepWei) [L870]
  |   |-- currentPrizePool += moveWei [L871]
  |-- _creditDgnrsCoinflip(currentPrizePool) [L876] = C28
  |   |-- reads price [L2270]
  |   |-- coin.creditFlip(SDGNRS, coinAmount) [L2274] (external)
  |-- _distributeYieldSurplus(rngWord) [L878] = C2
  |   |-- steth.balanceOf(address(this)) [L884] (external view)
  |   |-- reads currentPrizePool, claimablePool, yieldAccumulator [L886-890]
  |   |-- _getNextPrizePool() [L887], _getFuturePrizePool() [L889]
  |   |-- _addClaimableEth(VAULT, share, rngWord) [L901] = C3
  |   |   |-- (see C3 call tree below)
  |   |-- _addClaimableEth(SDGNRS, share, rngWord) [L906] = C3
  |   |-- claimablePool += claimableDelta [L911]
  |   |-- yieldAccumulator += accumulatorShare [L913]
```

#### Storage Writes (Full Tree)
| Variable | Written By | Line |
|----------|-----------|------|
| prizePoolsPacked (future) | _setFuturePrizePool | L855, L870 |
| yieldAccumulator | direct | L856, L913 |
| currentPrizePool | direct | L860, L871 |
| prizePoolsPacked (next) | _setNextPrizePool(0) | L861 |
| claimableWinnings[VAULT] | via C2->C3->C26 | PU:33 |
| claimableWinnings[SDGNRS] | via C2->C3->C26 | PU:33 |
| claimablePool | via C2 | L911 |
| prizePoolsPacked (future/next) | via C2->C3->C4 (if auto-rebuy on VAULT/SDGNRS) | L982-984 |

#### Cached-Local-vs-Storage Check

**B5 locals:**
1. `acc = yieldAccumulator` [L853] -- used to compute `half` and written back as `acc - half` [L856]. This write completes BEFORE any downstream call. SAFE.
2. `fp = _getFuturePrizePool()` [L865] -- used only for keep-roll calculation and the subsequent `_setFuturePrizePool(keepWei)` [L870]. This write completes BEFORE C2 is called. SAFE.

**B5 does NOT cache any pool value across the C2 boundary.** All pool writes (L855, L856, L860, L861, L870, L871) execute BEFORE `_distributeYieldSurplus` is called at L878.

**C2 locals:**
- `obligations` [L886-890] = snapshot of `currentPrizePool + _getNextPrizePool() + claimablePool + _getFuturePrizePool() + yieldAccumulator`. Used ONLY for surplus comparison at L892 (`if (totalBal <= obligations) return`). NOT written back to storage. After the comparison, fresh storage reads are used: `claimablePool += claimableDelta` [L911] reads claimablePool fresh, `yieldAccumulator += accumulatorShare` [L913] reads yieldAccumulator fresh.

**F-01 INVESTIGATE (INFO):** The `obligations` snapshot at L886-890 includes `claimablePool`. After `_addClaimableEth(VAULT, ...)` [L901] returns, if VAULT has auto-rebuy enabled, C4 writes futurePrizePool/nextPrizePool. But more importantly, the second `_addClaimableEth(SDGNRS, ...)` [L906] could theoretically run with a stale `obligations` comparison already passed. However, `obligations` is only used for the initial surplus gate (L892) -- it is NOT used for any arithmetic that gets written back. The surplus check is a one-time gate at function entry. After passing, the writes are independent. Additionally, VAULT and SDGNRS are contract addresses (ContractAddresses.VAULT, ContractAddresses.SDGNRS) -- these addresses would need `autoRebuyState[addr].autoRebuyEnabled == true` for C4 to trigger, which requires explicit opt-in that contract addresses cannot perform (they have no UI/transaction path to enable auto-rebuy). The auto-rebuy path is unreachable for these beneficiaries in practice.

**Severity rationale:** INFO. The `obligations` snapshot is directionally conservative -- if auto-rebuy were to move ETH to futurePrizePool, obligations would actually increase, meaning the surplus would be smaller. Distributing based on a slightly-too-large surplus is safe (protocol gives away marginally less than actual surplus). And auto-rebuy on contract addresses is unreachable in practice.

**VERDICT: SAFE (with F-01 INFO noted)**

#### Attack Analysis

**State Coherence:** See cache check above. All pool writes complete before C2 boundary. F-01 is INFO-level. VERDICT: SAFE
**Access Control:** External (delegatecall). Called by advanceGame at level transition. Not callable out of sequence (poolConsolidationDone flag prevents re-entry). VERDICT: SAFE
**RNG Manipulation:** `rngWord` used only for `_futureKeepBps` (30-65% range) and passed to C2 for yield surplus. No winner selection in B5 itself. VERDICT: SAFE
**Cross-Contract State Desync:** `steth.balanceOf(address(this))` [L884] is view-only. `coin.creditFlip` [L2274] in C28 is one-way. No state read from external contracts after writes. VERDICT: SAFE
**Edge Cases:** Zero yieldAccumulator handled (half=0, no-op). Zero futurePrizePool handled (keepBps check at L866). Non-x00 levels skip the keep-roll entirely. Zero surplus causes early return in C2 [L892]. VERDICT: SAFE
**Conditional Paths:** x00-level path (yield dump + keep-roll) vs non-x00 path (simple consolidation). Both traced. VERDICT: SAFE
**Economic/MEV:** No external input. Pool consolidation is deterministic given VRF word. VERDICT: SAFE
**Griefing:** Cannot be called externally. FSM-gated. VERDICT: SAFE
**Ordering/Sequencing:** `poolConsolidationDone` flag prevents double execution. Called once per level transition. VERDICT: SAFE
**Silent Failures:** Zero nextPrizePool produces no-op consolidation (correct). Zero surplus produces no yield distribution (correct). VERDICT: SAFE

---

### JackpotModule::processTicketBatch() (B6, line 1812-1873)

#### Call Tree
```
processTicketBatch(lvl) [L1812]
  |-- _tqReadKey(lvl) [L1813] (inherited, view)
  |-- reads ticketQueue[rk].length [L1815]
  |-- [if ticketLevel != lvl]:
  |   |-- writes ticketLevel = lvl [L1819]
  |   |-- writes ticketCursor = 0 [L1820]
  |-- reads ticketCursor [L1823]
  |-- [if idx >= total]:
  |   |-- delete ticketQueue[rk] [L1826]
  |   |-- writes ticketCursor = 0 [L1827]
  |   |-- writes ticketLevel = 0 [L1828]
  |   |-- return true
  |-- reads lastLootboxRngWord [L1838]
  |-- LOOP: while idx < total && used < writesBudget:
  |   |-- _processOneTicketEntry(queue[idx], lvl, rk, room, processed, entropy, idx) [L1842] = C18
  |   |   |-- reads ticketsOwedPacked[rk][player] [L1916]
  |   |   |-- [owed == 0]: _resolveZeroOwedRemainder() [L1925] = C17
  |   |   |   |-- _rollRemainder() [L1893] (pure) = D22
  |   |   |   |-- writes ticketsOwedPacked[rk][player] [L1888/L1895/L1901]
  |   |   |-- _generateTicketBatch(player, lvl, processed, take, entropy, queueIdx) [L1953] = C19
  |   |   |   |-- _raritySymbolBatch(player, baseKey, startIndex, count, entropyWord) [L1984] = C20
  |   |   |   |   |-- DegenerusTraitUtils.traitFromWord() (pure)
  |   |   |   |   |-- ASSEMBLY: sstore traitBurnTicket[lvl][traitId] length and data
  |   |   |-- _finalizeTicketEntry(rk, player, packed, owed, take, entropy, rollSalt) [L1960] = C21
  |   |   |   |-- _rollRemainder() [L2011] (pure) = D22
  |   |   |   |-- writes ticketsOwedPacked[rk][player] [L2018]
  |-- writes ticketCursor = uint32(idx) [L1863]
  |-- [if idx >= total]:
  |   |-- delete ticketQueue[rk] [L1867]
  |   |-- writes ticketCursor = 0 [L1868]
  |   |-- writes ticketLevel = 0 [L1869]
```

#### Storage Writes (Full Tree)
| Variable | Written By | Line |
|----------|-----------|------|
| ticketLevel | direct | L1819, L1828, L1869 |
| ticketCursor | direct | L1820, L1827, L1863, L1868 |
| ticketQueue[rk] | delete | L1826, L1867 |
| ticketsOwedPacked[rk][player] | via C17 | L1888, L1895, L1901 |
| ticketsOwedPacked[rk][player] | via C21 | L2018 |
| traitBurnTicket[lvl][traitId] (length + data) | via C20 assembly SSTORE | L2126, L2137 |

#### Cached-Local-vs-Storage Check

B6 has NO cached prize pool values. All locals are cursor/budget tracking:
- `total = queue.length` [L1815] -- queue length read once, not written back.
- `idx = ticketCursor` [L1823] -- cursor tracking.
- `writesBudget` [L1832] -- gas budget constant.
- `entropy = lastLootboxRngWord` [L1838] -- RNG seed, read once. Used as parameter, not written back.

No descendant writes prize pool values. The entire ticket subsystem writes only to `traitBurnTicket` and `ticketsOwedPacked`.

**VERDICT: SAFE** (no BAF-pattern applicable -- no prize pool involvement)

**F-03 INVESTIGATE (INFO):** The `processed` counter at L1858 uses `processed += writesUsed >> 1` as an approximation of tickets processed within a single entry. This affects the `startIndex` parameter passed to `_generateTicketBatch` on resume within the same entry (when `advance` is false). The approximation means the LCG seed derivation in `_raritySymbolBatch` [L2074] uses `groupIdx = i >> 4` where `i = startIndex + ...`. If `processed` is off by a few units, the LCG seed changes, producing different traits. This is not a security issue (traits are still deterministic and fair given the VRF seed), but the non-exact tracking means resume-within-entry produces slightly different traits than a single-pass would.

**Severity rationale:** INFO. The trait distribution remains deterministic and VRF-derived. The approximation only affects trait aesthetics (which symbols are assigned), not economic value or fairness.

#### Attack Analysis

**State Coherence:** No prize pool caches. VERDICT: SAFE
**Access Control:** External (delegatecall). Called by advanceGame during ticket processing phase. VERDICT: SAFE
**RNG Manipulation:** Uses `lastLootboxRngWord` as entropy seed. This word was set by VRF fulfillment, unknown at ticket purchase time. Trait generation via LCG is deterministic given the seed. A player who knows the VRF word could predict their trait distribution if they know their queue position, but the economic impact is negligible (traits affect jackpot eligibility, not direct value, and the player already committed their tickets before the VRF word was revealed). VERDICT: SAFE
**Cross-Contract State Desync:** No external calls. VERDICT: SAFE
**Edge Cases:** Zero-length queue returns immediately [L1824-1830]. Single-ticket entries handled by `_resolveZeroOwedRemainder`. Queue cleanup (`delete ticketQueue[rk]`) fires at both early-exit [L1826] and normal completion [L1867]. VERDICT: SAFE
**Conditional Paths:** Level switch vs resume (L1818). Budget exhaustion mid-batch (L1851 break). Completion mid-batch (L1865). Remainder-only entries (owed=0, rem>0). All paths save cursor state correctly. VERDICT: SAFE
**Economic/MEV:** No ETH movement. Tickets are trait assignments only. VERDICT: SAFE
**Griefing:** Cannot be called externally outside advanceGame. Queue cannot be corrupted -- entries are immutable once written. VERDICT: SAFE
**Ordering/Sequencing:** `ticketLevel` and `ticketCursor` track exact position. Level switch resets cursor [L1820]. Completion clears all state [L1827-1829]. No ordering attack possible. VERDICT: SAFE
**Silent Failures:** `writesUsed == 0 && !advance` triggers break [L1851], preventing infinite loop on budget exhaustion. Correct behavior. VERDICT: SAFE

---

### JackpotModule::payDailyJackpotCoinAndTickets() (B3, line 652-737)

#### Call Tree
```
payDailyJackpotCoinAndTickets(randWord) [L652]
  |-- reads dailyJackpotCoinTicketsPending [L653]
  |-- _unpackDailyTicketBudgets() [L661] (pure) = D19
  |-- reads lastDailyJackpotLevel [L664]
  |-- reads lastDailyJackpotWinningTraits [L665]
  |-- _calcDailyCoinBudget(lvl) [L674] (view) = D12
  |-- _awardFarFutureCoinJackpot(lvl, farBudget, randWord) [L678] = C23
  |   |-- (see C23 call tree in Multi-Parent section)
  |-- _selectDailyCoinTargetLevel() [L685] (view) = D15
  |-- _awardDailyCoinToTraitWinners(targetLevel, packed, nearBudget, coinEntropy) [L691] = C22
  |   |-- (see C22 call tree in Multi-Parent section)
  |-- _distributeTicketJackpot(lvl, packed, dailyTicketUnits, entropyDaily, 100, 241) [L704] = C6
  |   |-- (see C6 call tree below)
  |-- _distributeTicketJackpot(carryoverSourceLevel, packed, carryoverTicketUnits, entropyNext, 100, 240) [L716] = C6
  |-- unchecked { jackpotCounter += counterStep } [L728]
  |-- writes dailyJackpotCoinTicketsPending = false [L732]
  |-- writes dailyTicketBudgetsPacked = 0 [L733]
  |-- coin.rollDailyQuest(day, randWord) [L736] (external)
```

#### Storage Writes (Full Tree)
| Variable | Written By | Line |
|----------|-----------|------|
| ticketQueue, ticketsOwedPacked | via C6->C7->C8->_queueTickets | |
| jackpotCounter | direct (unchecked) | L728 |
| dailyJackpotCoinTicketsPending | direct | L732 |
| dailyTicketBudgetsPacked | direct | L733 |

#### Cached-Local-vs-Storage Check

B3 has NO cached prize pool values. Locals are all parameter-derived:
- `lvl = lastDailyJackpotLevel` [L664] -- level, not pool value.
- `winningTraitsPacked = lastDailyJackpotWinningTraits` [L665] -- trait data.
- `coinBudget` [L674] -- computed from `levelPrizePool[lvl-1]` and `price`, both read-only.
- `farBudget`, `nearBudget` -- derived from coinBudget.

No descendant writes prize pool values. C22 and C23 only make external calls to `coin.creditFlip/creditFlipBatch`. C6 chain writes only to ticketQueue/ticketsOwedPacked.

**VERDICT: SAFE** (no BAF-pattern applicable)

#### Attack Analysis

**State Coherence:** No pool caches. VERDICT: SAFE
**Access Control:** External (delegatecall). Gated by `dailyJackpotCoinTicketsPending` [L653]. VERDICT: SAFE
**RNG Manipulation:** `randWord` from VRF. Entropy derivations use level XOR and domain-separated tags. VERDICT: SAFE
**Cross-Contract State Desync:** `coin.creditFlipBatch` and `coin.rollDailyQuest` are one-way calls. No state read from coin after writes. VERDICT: SAFE
**Edge Cases:** Zero coinBudget returns early (via internal checks). Zero targetLevel skips near-future distribution [L690]. Zero ticketUnits skips ticket distribution (checked in C6 at L1084). VERDICT: SAFE
**Conditional Paths:** Coin distribution has far-future (always) + near-future (if target level valid). Ticket distribution has daily (always if units>0) + carryover (if offset>0 and units>0). All paths traced. VERDICT: SAFE
**Economic/MEV:** BURNIE distribution is via external calls -- no ETH movement. Ticket distribution is ticket queue writes. No frontrunning opportunity. VERDICT: SAFE
**Griefing:** FSM-gated. Cannot be invoked outside sequence. VERDICT: SAFE
**Ordering/Sequencing:** Can only run when `dailyJackpotCoinTicketsPending` is true (set by C25 in B2). Clears the flag at L732. Cannot double-execute. VERDICT: SAFE
**Silent Failures:** Zero budget produces no coin distribution (correct). Zero ticket units produces no ticket distribution (correct). No silent skip of critical logic. VERDICT: SAFE

---

### JackpotModule::awardFinalDayDgnrsReward() (B4, line 744-769)

#### Call Tree
```
awardFinalDayDgnrsReward(lvl, rngWord) [L744]
  |-- dgnrs.poolBalance(Reward) [L745] (external view)
  |-- reads lastDailyJackpotWinningTraits [L752]
  |-- JackpotBucketLib.soloBucketIndex(entropy) [L751] (pure)
  |-- JackpotBucketLib.unpackWinningTraits(packed) [L753] (pure)
  |-- _randTraitTicket(traitBurnTicket[lvl], entropy, traitIds[soloIdx], 1, 254) [L755] (view) = D7
  |-- dgnrs.transferFromPool(Reward, winners[0], reward) [L763] (external)
```

#### Storage Writes (Full Tree)

**None in JackpotModule.** B4 makes two external calls to StakedDegenerusStonk (view + transfer) but writes no JackpotModule/Game storage. The transfer is one-way to the winner.

#### Cached-Local-vs-Storage Check

No cached storage values. `reward` is computed from external `dgnrs.poolBalance` call. No stale cache possible.

**VERDICT: SAFE** (trivially -- no storage writes in this function's tree)

#### Attack Analysis

**State Coherence:** No storage writes, no cache risk. VERDICT: SAFE
**Access Control:** External (delegatecall). Called at end of Day 5 jackpot sequence. VERDICT: SAFE
**RNG Manipulation:** Uses stored `lastDailyJackpotWinningTraits` (set during Day 5 ETH phase). Solo bucket derived from `rngWord ^ (uint256(lvl) << 192)`. Winner selected via `_randTraitTicket`. All VRF-derived. VERDICT: SAFE
**Cross-Contract State Desync:** `dgnrs.poolBalance` is view-only. `dgnrs.transferFromPool` is one-way transfer. No state read after transfer. VERDICT: SAFE
**Edge Cases:** Zero reward returns early [L747]. No winners produces no transfer [L762 check]. `winners[0] == address(0)` skips transfer. VERDICT: SAFE
**Conditional Paths:** Single linear path. Winner found or not. VERDICT: SAFE
**Economic/MEV:** DGNRS transfer amount is 1% of reward pool. No ETH movement. VERDICT: SAFE
**Griefing:** FSM-gated. Cannot be invoked out of sequence. VERDICT: SAFE
**Ordering/Sequencing:** Called after Day 5 coin+tickets phase. Uses stored winning traits from earlier in the day. VERDICT: SAFE
**Silent Failures:** Zero pool balance results in zero reward and early return (correct). VERDICT: SAFE

---

### JackpotModule::payDailyCoinJackpot() (B7, line 2283-2324)

#### Call Tree
```
payDailyCoinJackpot(lvl, randWord) [L2283]
  |-- _calcDailyCoinBudget(lvl) [L2284] (view) = D12
  |-- _awardFarFutureCoinJackpot(lvl, farBudget, randWord) [L2292] = C23
  |-- _calculateDayIndex() [L2297] (view)
  |-- _loadDailyWinningTraits(lvl, questDay) [L2298] (view) = D11
  |-- [if !valid]:
  |   |-- _rollWinningTraits(lvl, randWord, useBurn) [L2304] (view)
  |   |-- _syncDailyWinningTraits(lvl, packed, questDay) [L2305] = C24
  |-- _selectDailyCoinTargetLevel() [L2311] (view) = D15
  |-- _awardDailyCoinToTraitWinners(targetLevel, packed, nearBudget, entropy) [L2318] = C22
```

#### Storage Writes (Full Tree)
| Variable | Written By | Line |
|----------|-----------|------|
| lastDailyJackpotWinningTraits | via C24 (if traits not cached) | L2555 |
| lastDailyJackpotLevel | via C24 | L2556 |
| lastDailyJackpotDay | via C24 | L2557 |

**Note:** C22 and C23 make external calls to `coin.creditFlip/creditFlipBatch` but write NO Game storage.

#### Cached-Local-vs-Storage Check

B7 has NO cached prize pool values. `coinBudget` is computed from view functions. No downstream writes to storage that any ancestor caches.

**VERDICT: SAFE** (no BAF-pattern applicable -- only external coin minting calls)

#### Attack Analysis

**State Coherence:** No pool caches, no pool writes. VERDICT: SAFE
**Access Control:** External (delegatecall). Called during purchase phase daily advancement. VERDICT: SAFE
**RNG Manipulation:** `randWord` from VRF. Entropy derivation uses domain-separated COIN_JACKPOT_TAG. VERDICT: SAFE
**Cross-Contract State Desync:** `coin.creditFlipBatch` is one-way. No state read from coin after writes. VERDICT: SAFE
**Edge Cases:** Zero coinBudget returns early [L2285]. Zero targetLevel skips near-future [L2316]. No valid cached traits triggers fresh roll [L2302-2305]. VERDICT: SAFE
**Conditional Paths:** Cached traits vs fresh roll. Target level valid vs zero. All paths traced. VERDICT: SAFE
**Economic/MEV:** BURNIE minting only. No ETH movement. VERDICT: SAFE
**Griefing:** FSM-gated. Cannot be invoked outside sequence. VERDICT: SAFE
**Ordering/Sequencing:** Called daily during purchase phase. `_loadDailyWinningTraits` ensures consistency with prior ETH jackpot traits. VERDICT: SAFE
**Silent Failures:** Zero budget paths return gracefully. VERDICT: SAFE

---

## BAF-Critical Payout Subsystem

### JackpotModule::_addClaimableEth() (C3, line 928-949) [MULTI-PARENT] [BAF-CRITICAL]

#### Call Tree
```
_addClaimableEth(beneficiary, weiAmount, entropy) [L928]
  |-- [weiAmount == 0]: return 0 [L933]
  |-- [if !gameOver]:
  |   |-- reads autoRebuyState[beneficiary] [L938]
  |   |-- [if autoRebuyEnabled]:
  |   |   |-- return _processAutoRebuy(beneficiary, weiAmount, entropy, state) [L941] = C4
  |   |   |   |-- (see C4 below)
  |-- _creditClaimable(beneficiary, weiAmount) [L947] = C26
  |   |-- [weiAmount == 0]: return (PU:31)
  |   |-- claimableWinnings[beneficiary] += weiAmount (PU:33)
  |-- return weiAmount [L948]
```

#### Storage Writes (Full Tree)
| Variable | Written By | Line |
|----------|-----------|------|
| claimableWinnings[beneficiary] | _creditClaimable (C26) | PU:33 |
| prizePoolsPacked (future) | via C4->_setFuturePrizePool | L982 |
| prizePoolsPacked (next) | via C4->_setNextPrizePool | L984 |
| ticketQueue, ticketsOwedPacked | via C4->_queueTickets | L979 |
| claimableWinnings[player] | via C4->_creditClaimable | L988 |

#### Multi-Parent Standalone Analysis

**Parent 1: C2 (_distributeYieldSurplus) via B5**
- C2 caches: `obligations` [L886-890] = sum of currentPrizePool + nextPrizePool + claimablePool + futurePrizePool + yieldAccumulator. NOT written back.
- C2 reads after C3 returns: `claimablePool += claimableDelta` [L911] -- fresh storage read.
- C3->C4 writes futurePrizePool/nextPrizePool. `obligations` becomes stale but is never used again after L892.
- **Auto-rebuy reachability:** VAULT and SDGNRS are contract addresses. `autoRebuyState[VAULT].autoRebuyEnabled` would need to be true. No transaction path exists for contract addresses to enable auto-rebuy (requires user-initiated tx to toggle state). Unreachable in practice.
- **VERDICT: SAFE**

**Parent 2: C11 (_processDailyEth) via B2**
- C11 caches: `liabilityDelta` [L1365] -- running sum of return values from C3. `paidEth` [L1419] -- running sum of perWinner amounts. Neither is a prize pool value.
- C11 does NOT cache futurePrizePool, nextPrizePool, or currentPrizePool.
- C3->C4 writes futurePrizePool/nextPrizePool via fresh _getFuturePrizePool()/_setFuturePrizePool() reads/writes.
- C11 writes `claimablePool += liabilityDelta` [L1430] -- uses accumulated return values from C3 (correct pattern per Pitfall 1).
- **VERDICT: SAFE**

**Parent 3: C14 (_resolveTraitWinners) via C12->C13 (normal bucket path)**
- C14 caches: `totalPayout` [L1599], `totalLiability` [L1601], `totalWhalePassSpent` [L1600] -- running sums, not pool values.
- C14 does NOT cache futurePrizePool or nextPrizePool.
- `_addClaimableEth` at L1627 returns claimableDelta, accumulated in totalLiability [L1640]. Correct return value usage (Pitfall 1/2 check passes).
- **VERDICT: SAFE**

**Parent 4: C16 (_processSoloBucketWinner) via C14 -> C15 (_creditJackpot)**
- C16 caches: none of the prize pool values.
- C16 calls `_creditJackpot(false, winner, ethAmount, entropy)` [L1706] which calls `_addClaimableEth` [L1674].
- C16 then writes `_setFuturePrizePool(_getFuturePrizePool() + whalePassCost)` [L1710] -- fresh read AFTER C3 returns.
- If C3->C4 wrote futurePrizePool (auto-rebuy), C16's read at L1710 picks up the updated value.
- **VERDICT: SAFE**

**Parent 5: C14 (_resolveTraitWinners) via C16 (solo bucket path)**
- Same as Parent 4. C14 does not cache pool values. C16's _setFuturePrizePool uses fresh read.
- **VERDICT: SAFE**

---

### JackpotModule::_processAutoRebuy() (C4, line 959-999) [BAF-CRITICAL]

**D-07 Re-audit: Treating v4.4 fix as nonexistent. Analyzing this function from scratch.**

#### Call Tree
```
_processAutoRebuy(player, newAmount, entropy, state) [L959]
  |-- _calcAutoRebuy(player, newAmount, entropy, state, level, 13_000, 14_500) [L965] = D16 (pure)
  |   |-- EntropyLib.entropyStep() (pure)
  |   |-- PriceLookupLib.priceForLevel() (pure)
  |   |-- returns AutoRebuyCalc: toFuture, hasTickets, targetLevel, ticketCount, ethSpent, reserved, rebuyAmount
  |-- [if !calc.hasTickets]:
  |   |-- _creditClaimable(player, newAmount) [L975] = C26
  |   |-- return newAmount [L976]
  |-- _queueTickets(player, calc.targetLevel, calc.ticketCount) [L979]
  |-- [if calc.toFuture]:
  |   |-- _setFuturePrizePool(_getFuturePrizePool() + calc.ethSpent) [L982]
  |-- [else]:
  |   |-- _setNextPrizePool(_getNextPrizePool() + calc.ethSpent) [L984]
  |-- [if calc.reserved != 0]:
  |   |-- _creditClaimable(player, calc.reserved) [L988] = C26
  |-- return calc.reserved [L998]
```

#### Storage Writes
| Variable | Written By | Line |
|----------|-----------|------|
| ticketQueue[wk], ticketsOwedPacked[wk][player] | _queueTickets | L979 |
| prizePoolsPacked (future) | _setFuturePrizePool | L982 |
| prizePoolsPacked (next) | _setNextPrizePool | L984 |
| claimableWinnings[player] | _creditClaimable (C26) | L975 or L988 |

#### Cached-Local-vs-Storage Check

C4 reads `level` (storage) at L970 -- passed to `_calcAutoRebuy` which is pure. No cached pool values.

`_setFuturePrizePool(_getFuturePrizePool() + calc.ethSpent)` [L982] reads fresh via `_getFuturePrizePool()` then writes via `_setFuturePrizePool()`. Both go through `_getPrizePools()` which reads `prizePoolsPacked` from storage. Each call is an atomic read-modify-write. If called multiple times (via loop in C11), each iteration reads the updated value from the previous iteration's write.

**VERDICT: SAFE** -- no cached values, all reads are fresh.

**F-05 INVESTIGATE (INFO):** When `state.takeProfit == 0`, `calc.reserved = 0` [L50] and `calc.rebuyAmount = weiAmount` [L52]. The entire winnings amount is converted to tickets with zero claimable credit. The function returns `calc.reserved = 0`, which means `claimablePool` gets 0 added. The ETH is accounted for in futurePrizePool or nextPrizePool via `calc.ethSpent`. However, `ethSpent = baseTickets * ticketPrice` may be less than `rebuyAmount` (dust from integer division). The dust (`rebuyAmount - ethSpent`) is silently dropped -- not credited to player, not added to any pool. For small amounts this dust is negligible (< ticketPrice, which is the minimum ticket cost, typically < 0.01 ETH / 4).

**Severity rationale:** INFO. Dust loss is by design (NatSpec says "Fractional dust is ignored") and economically negligible.

#### Verification of _calcAutoRebuy purity

`_calcAutoRebuy` at PayoutUtils L38-72 is declared `internal pure`. Verified: zero storage reads (`state` is a memory struct passed in, `currentLevel` is a parameter), zero storage writes. Uses only `EntropyLib.entropyStep()` (pure) and `PriceLookupLib.priceForLevel()` (pure). **Confirmed pure.**

#### Level offset and pool routing verification

- `levelOffset = (EntropyLib.entropyStep(entropy ^ uint256(uint160(beneficiary)) ^ weiAmount) & 3) + 1` => [1,4]
- `toFuture = levelOffset > 1` => +1 goes to nextPrizePool (25%), +2/+3/+4 go to futurePrizePool (75%)
- `targetLevel = currentLevel + uint24(levelOffset)` => always ahead of current level

This is correct: next-level tickets go to nextPrizePool (available at next level), future tickets go to futurePrizePool (available at future levels).

---

## Coin/BURNIE Jackpot Subsystem

### JackpotModule::_awardDailyCoinToTraitWinners() (C22, line 2341-2438) [MULTI-PARENT]

#### Call Tree
```
_awardDailyCoinToTraitWinners(lvl, winningTraitsPacked, coinBudget, entropy) [L2341]
  |-- JackpotBucketLib.unpackWinningTraits() [L2351] (pure)
  |-- _computeBucketCounts(lvl, traitIds, cap, entropy) [L2354] (view) = D3
  |-- LOOP over 4 trait buckets:
  |   |-- _randTraitTicketWithIndices(traitBurnTicket[lvl], entropy, traitId, count, salt) [L2381] (view) = D8
  |   |-- LOOP over winners:
  |   |   |-- coin.creditFlipBatch(batchPlayers, batchAmounts) [L2411] (external) -- batched per 3
  |-- coin.creditFlipBatch(batchPlayers, batchAmounts) [L2437] (external) -- remainder
```

#### Storage Writes: **None in JackpotModule.** All writes are external `coin.creditFlipBatch` calls.

#### Multi-Parent Analysis
- **Parent B3** (payDailyJackpotCoinAndTickets): Calls with `coinEntropy = randWord ^ (uint256(lvl) << 192) ^ uint256(COIN_JACKPOT_TAG)`. No cached pool values in B3.
- **Parent B7** (payDailyCoinJackpot): Calls with `entropy = randWord ^ (uint256(lvl) << 192) ^ uint256(COIN_JACKPOT_TAG)`. No cached pool values in B7.

Both parents pass equivalent entropy derivation. No storage writes in C22 to conflict with any parent cache.

**VERDICT: SAFE** (no storage writes at all)

---

### JackpotModule::_awardFarFutureCoinJackpot() (C23, line 2444-2529) [MULTI-PARENT]

#### Call Tree
```
_awardFarFutureCoinJackpot(lvl, farBudget, rngWord) [L2444]
  |-- LOOP (10 samples):
  |   |-- reads ticketQueue[_tqFarFutureKey(candidate)].length [L2467]
  |   |-- reads ticketQueue[key][idx] [L2470]
  |-- LOOP (distribute):
  |   |-- coin.creditFlipBatch(batchPlayers, batchAmounts) [L2510, L2527] (external)
```

#### Storage Writes: **None in JackpotModule.** Only external `coin.creditFlipBatch` calls.

#### Multi-Parent Analysis
- **Parent B3** (payDailyJackpotCoinAndTickets): Calls with budget derived from `_calcDailyCoinBudget`. No pool caches.
- **Parent B7** (payDailyCoinJackpot): Same.

**VERDICT: SAFE** (no storage writes)

---

### JackpotModule::_creditDgnrsCoinflip() (C28, line 2269-2275)

#### Call Tree
```
_creditDgnrsCoinflip(prizePoolWei) [L2269]
  |-- reads price [L2270]
  |-- coin.creditFlip(SDGNRS, coinAmount) [L2274] (external)
```

#### Storage Writes: **None.** One external call, no storage writes.

**VERDICT: SAFE** (trivially)

---

## Ticket Distribution Subsystem

### JackpotModule::_distributeTicketJackpot() (C6, line 1076-1109) [MULTI-PARENT]

#### Call Tree
```
_distributeTicketJackpot(lvl, winningTraitsPacked, ticketUnits, entropy, maxWinners, saltBase) [L1076]
  |-- JackpotBucketLib.unpackWinningTraits() [L1086] (pure)
  |-- _computeBucketCounts(lvl, traitIds, cap, entropy) [L1092] (view) = D3
  |-- _distributeTicketsToBuckets(lvl, traitIds, counts, ticketUnits, entropy, cap, saltBase) [L1100] = C7
  |   |-- LOOP 4 buckets:
  |   |   |-- _distributeTicketsToBucket(lvl, traitId, count, entropy, salt, ...) [L1130] = C8
  |   |   |   |-- _randTraitTicket(traitBurnTicket[lvl], entropy, traitId, count, salt) [L1161] (view) = D7
  |   |   |   |-- LOOP winners: _queueTickets(winner, lvl+1, units) [L1180]
```

#### Storage Writes
| Variable | Written By | Line |
|----------|-----------|------|
| ticketQueue[wk] | _queueTickets | L1180 |
| ticketsOwedPacked[wk][buyer] | _queueTickets | L547-548 |

#### Multi-Parent Analysis
- **Parent C5** (_distributeLootboxAndTickets from B2 early-burn path): Called with `lvl`, `winningTraitsPacked`, `ticketUnits`, entropy from `randWord ^ (uint256(lvl) << 192)`, maxWinners=100, saltBase=242.
- **Parent B3** (payDailyJackpotCoinAndTickets): Called with `lvl`, `winningTraitsPacked`, `dailyTicketUnits`, entropyDaily/entropyNext, maxWinners=100, saltBase=241/240.

Neither parent caches any pool values. C6 writes only to ticketQueue (no pool writes). No conflict possible.

**VERDICT: SAFE**

---

### JackpotModule::_distributeJackpotEth() (C12, line 1435-1474) [MULTI-PARENT] [BAF-PATH]

#### Call Tree
```
_distributeJackpotEth(lvl, ethPool, entropy, traitIds, shareBps, bucketCounts) [L1435]
  |-- JackpotEthCtx memory ctx [L1443-1445]
  |-- PriceLookupLib.priceForLevel(lvl+1) [L1447] (pure)
  |-- JackpotBucketLib.soloBucketIndex(entropy) [L1448] (pure)
  |-- JackpotBucketLib.bucketShares(ethPool, shareBps, bucketCounts, remainderIdx, unit) [L1449] (pure)
  |-- LOOP 4 buckets:
  |   |-- _processOneBucket(ctx, traitIdx, traitIds, shares, bucketCounts) [L1458] = C13
  |   |   |-- _resolveTraitWinners(false, lvl, traitId, traitIdx, share, ctx.entropyState, count) [L1491] = C14
  |   |   |   |-- (see C14 analysis below)
  |   |   |-- ctx.totalPaidEth += ethDelta + ticketSpent [L1502]
  |   |   |-- ctx.liabilityDelta += bucketLiability [L1503]
  |-- claimablePool += ctx.liabilityDelta [L1471]
  |-- return ctx.totalPaidEth [L1473]
```

#### Storage Writes
| Variable | Written By | Line |
|----------|-----------|------|
| claimableWinnings[w] | via C14->C3->C26 or C14->C16->C15->C3->C26 | PU:33 |
| claimablePool | direct | L1471 |
| prizePoolsPacked (future/next) | via C14->C3->C4 (auto-rebuy) | L982-984 |
| ticketQueue, ticketsOwedPacked | via C3->C4->_queueTickets | L979 |
| whalePassClaims[winner] | via C14->C16 | L1709 |
| prizePoolsPacked (future) | via C16->_setFuturePrizePool | L1710 |

#### Cached-Local-vs-Storage Check

`JackpotEthCtx` struct contains: `entropyState`, `liabilityDelta`, `totalPaidEth`, `lvl`. **None** are prize pool values.

C12 does NOT cache futurePrizePool, nextPrizePool, currentPrizePool, or claimablePool before the loop. `claimablePool += ctx.liabilityDelta` [L1471] is a read-modify-write on claimablePool after the loop completes.

**BAF check:** C14->C3->C4 may write futurePrizePool/nextPrizePool during the loop. Since ctx does not cache these values, no stale writeback occurs. The `claimablePool` aggregate at L1471 uses `ctx.liabilityDelta` which is the sum of return values from C14 calls. C14 returns `liabilityDelta` which is the sum of C3 return values. C3 returns `calc.reserved` on auto-rebuy path, `weiAmount` on normal path. This is the correct pattern (Pitfall 1 check passes).

**VERDICT: SAFE**

#### Multi-Parent Analysis
- **Parent B1** (runTerminalJackpot): Passes `poolWei` (parameter), `targetLvl` (parameter). B1 has no cached pool values.
- **Parent C10** (_runJackpotEthFlow via C9 from B2 early-burn): Passes `jp.ethPool` (parameter from JackpotParams struct), `jp.lvl`. C10/C9/B2 early-burn path deducts `ethDaySlice` from futurePrizePool at L604 BEFORE calling C9. No stale cache.

**VERDICT: SAFE** for both parents.

---

### JackpotModule::_resolveTraitWinners() (C14, line 1528-1655) [BAF-PATH]

#### Call Tree
```
_resolveTraitWinners(payCoin, lvl, traitId, traitIdx, traitShare, entropy, winnerCount) [L1528]
  |-- _randTraitTicketWithIndices(traitBurnTicket[lvl], entropy, traitId, count, salt) [L1563] (view) = D8
  |-- [if payCoin]:
  |   |-- LOOP: _creditJackpot(true, w, perWinner, entropy) [L1578] = C15
  |   |   |-- coin.creditFlip(beneficiary, amount) [L1670] (external)
  |-- [if !payCoin]:
  |   |-- [solo bucket: winnerCount == 1]:
  |   |   |-- _processSoloBucketWinner(w, perWinner, entropy) [L1611] = C16
  |   |   |   |-- _creditJackpot(false, winner, ethAmount, entropy) [L1706] = C15
  |   |   |   |   |-- _addClaimableEth(winner, ethAmount, entropy) [L1674] = C3
  |   |   |   |-- whalePassClaims[winner] += whalePassCount [L1709]
  |   |   |   |-- _setFuturePrizePool(_getFuturePrizePool() + whalePassCost) [L1710]
  |   |-- [normal bucket]:
  |   |   |-- LOOP: _addClaimableEth(w, perWinner, entropy) [L1627] = C3
  |   |   |   |-- (see C3 call tree above)
```

#### Cached-Local-vs-Storage Check

C14 locals: `totalPayout` [L1599], `totalWhalePassSpent` [L1600], `totalLiability` [L1601] -- running sums, not pool values. `perWinner = traitShare / totalCount` [L1572] -- derived from parameter.

C14 does NOT cache futurePrizePool, nextPrizePool, currentPrizePool. C3->C4 writes go through fresh reads/writes. C16 writes `_setFuturePrizePool(_getFuturePrizePool() + whalePassCost)` [L1710] AFTER C3 returns, using a fresh read.

**VERDICT: SAFE**

---

### JackpotModule::_processSoloBucketWinner() (C16, line 1684-1717) [BAF-PATH]

#### Call Tree (detailed)
```
_processSoloBucketWinner(winner, perWinner, entropy) [L1684]
  |-- quarterAmount = perWinner >> 2 [L1698]
  |-- whalePassCount = quarterAmount / HALF_WHALE_PASS_PRICE [L1699]
  |-- [if whalePassCount != 0]:
  |   |-- whalePassCost = whalePassCount * HALF_WHALE_PASS_PRICE [L1703]
  |   |-- ethAmount = perWinner - whalePassCost [L1704]
  |   |-- claimableDelta = _creditJackpot(false, winner, ethAmount, entropy) [L1706] = C15
  |   |   |-- _addClaimableEth(winner, ethAmount, entropy) [L1674] = C3
  |   |   |   |-- (C3->C4 may write futurePrizePool/nextPrizePool)
  |   |-- whalePassClaims[winner] += whalePassCount [L1709]
  |   |-- _setFuturePrizePool(_getFuturePrizePool() + whalePassCost) [L1710]
  |-- [else]:
  |   |-- claimableDelta = _creditJackpot(false, winner, perWinner, entropy) [L1714] = C15
```

#### Cached-Local-vs-Storage Check

C16 does NOT cache futurePrizePool before calling C3 (via C15). After C3->C4 potentially writes futurePrizePool, C16 reads `_getFuturePrizePool()` fresh at L1710. The fresh read picks up any C4 writes.

**Key verification:** Line 1710 is `_setFuturePrizePool(_getFuturePrizePool() + whalePassCost)`. The `_getFuturePrizePool()` call at L1710 reads prizePoolsPacked from storage. If C4 (called via C3 at L1674) wrote to futurePrizePool, the read at L1710 will see the updated value. This is the correct pattern.

**VERDICT: SAFE**

---

### JackpotModule::_processDailyEth() (C11, line 1338-1433) [BAF-PATH]

#### Call Tree
```
_processDailyEth(lvl, ethPool, entropy, traitIds, shareBps, bucketCounts) [L1338]
  |-- PriceLookupLib.priceForLevel(lvl+1) [L1350] (pure)
  |-- JackpotBucketLib.soloBucketIndex(entropy) [L1351] (pure)
  |-- JackpotBucketLib.bucketShares(ethPool, shareBps, bucketCounts, remainderIdx, unit) [L1352] (pure)
  |-- JackpotBucketLib.bucketOrderLargestFirst(bucketCounts) [L1360] (pure)
  |-- LOOP 4 buckets:
  |   |-- _randTraitTicketWithIndices(traitBurnTicket[lvl], entropy, traitId, count, salt) [L1386] (view) = D8
  |   |-- LOOP winners:
  |   |   |-- _addClaimableEth(w, perWinner, entropyState) [L1407] = C3
  |   |   |-- paidEth += perWinner [L1419]
  |   |   |-- liabilityDelta += claimableDelta [L1420]
  |-- claimablePool += liabilityDelta [L1430]
```

#### Cached-Local-vs-Storage Check

C11 locals: `ethPool` (parameter), `liabilityDelta` (running sum of C3 return values), `paidEth` (running sum of perWinner amounts). **None** are prize pool values.

C11 does NOT cache futurePrizePool, nextPrizePool, or currentPrizePool. C3->C4 writes futurePrizePool/nextPrizePool via fresh reads.

**Liability tracking verification (Pitfall 1):**
- `claimableDelta = _addClaimableEth(w, perWinner, entropyState)` [L1407]
- `liabilityDelta += claimableDelta` [L1420] -- uses RETURN VALUE, not perWinner
- `claimablePool += liabilityDelta` [L1430] -- aggregate update at end

This correctly handles the auto-rebuy case where C3 returns `calc.reserved` (less than perWinner). The difference goes to futurePrizePool/nextPrizePool, not claimablePool.

**VERDICT: SAFE**

---

### JackpotModule::_distributeYieldSurplus() (C2, line 883-914) [BAF-PATH]

#### Call Tree (already covered in B5 analysis)

#### Cached-Local-vs-Storage Check

`obligations` [L886-890] = snapshot. NOT written back. Used only for surplus gate at L892.

**F-01 (repeated):** See B5 analysis. `obligations` becomes stale after C3->C4 writes futurePrizePool, but it is never used again. Auto-rebuy unreachable for VAULT/SDGNRS addresses.

**VERDICT: SAFE (with F-01 INFO)**

---

## Multi-Parent Standalone Analysis

### C3 _addClaimableEth [BAF-CRITICAL]

| Parent | Caches Pool Values? | Post-C3 Stale Writeback? | Verdict |
|--------|-------------------|-------------------------|---------|
| C2 (_distributeYieldSurplus) | `obligations` snapshot (read-only) | No -- `obligations` never written back | SAFE |
| C11 (_processDailyEth loop) | `liabilityDelta` (return value sum) | No -- uses C3 return value, not perWinner | SAFE |
| C14 (_resolveTraitWinners, normal bucket at L1627) | `totalLiability` (return value sum) | No -- uses C3 return value | SAFE |
| C16 via C15 (_processSoloBucketWinner) | No pool caches | _setFuturePrizePool at L1710 uses fresh read | SAFE |
| C12 via C13->C14 (both paths) | ctx struct (no pool fields) | claimablePool at L1471 uses aggregate return values | SAFE |

### C6 _distributeTicketJackpot

| Parent | Context | Verdict |
|--------|---------|---------|
| C5 (from B2 early-burn) | entropy from `randWord ^ (uint256(lvl) << 192)`, maxWinners=100, saltBase=242 | SAFE -- no pool writes in C6 |
| B3 (payDailyJackpotCoinAndTickets) | entropyDaily/entropyNext, maxWinners=100, saltBase=241/240 | SAFE -- no pool writes in C6 |

### C12 _distributeJackpotEth

| Parent | Context | Verdict |
|--------|---------|---------|
| B1 (runTerminalJackpot) | poolWei from parameter, targetLvl from parameter | SAFE -- no cached pool values in B1 |
| C10 via C9 (B2 early-burn) | jp.ethPool from JackpotParams, jp.lvl | SAFE -- pool deductions complete before C9 call |

### C22 _awardDailyCoinToTraitWinners

| Parent | Context | Verdict |
|--------|---------|---------|
| B3 (payDailyJackpotCoinAndTickets) | coinEntropy from randWord XOR | SAFE -- no storage writes in C22 |
| B7 (payDailyCoinJackpot) | same entropy derivation | SAFE -- no storage writes in C22 |

### C23 _awardFarFutureCoinJackpot

| Parent | Context | Verdict |
|--------|---------|---------|
| B3 (payDailyJackpotCoinAndTickets) | farBudget from _calcDailyCoinBudget | SAFE -- no storage writes in C23 |
| B7 (payDailyCoinJackpot) | same | SAFE -- no storage writes in C23 |

### C24 _syncDailyWinningTraits

| Parent | Context | Verdict |
|--------|---------|---------|
| B2 (payDailyJackpot at L333, L582) | Writes lastDailyJackpotWinningTraits, Level, Day | SAFE -- B2 does not read these back after write |
| B7 (payDailyCoinJackpot at L2305) | Same writes. B7 uses `_loadDailyWinningTraits` before calling `_syncDailyWinningTraits` only when cache is invalid | SAFE -- no stale read after write |

### C27 _queueWhalePassClaimCore (PayoutUtils)

Not called from any JackpotModule Category B function. Retained in checklist per D-04/D-05 for EndgameModule availability. Analysis deferred to Phase 106 (EndgameModule unit).

---

## Inline Assembly Verification

### _raritySymbolBatch (C20, line 2050-2145) [ASSEMBLY]

#### Storage Slot Correctness

**Target:** `traitBurnTicket[lvl][traitId]` where `traitBurnTicket` is `mapping(uint24 => address[][256])`.

**Solidity standard layout for nested mapping with fixed-size inner array:**

1. Outer mapping: `keccak256(lvl . traitBurnTicket.slot)` gives the base slot for the 256-element array of dynamic arrays at level `lvl`.
2. Inner fixed array element: base + traitId gives the slot for `traitBurnTicket[lvl][traitId]`, which is a dynamic `address[]`.
3. Dynamic array length: stored at the element's slot.
4. Dynamic array data: starts at `keccak256(element_slot)`.

**Assembly code analysis:**

```solidity
// Lines 2110-2113: Level slot computation
assembly ("memory-safe") {
    mstore(0x00, lvl)
    mstore(0x20, traitBurnTicket.slot)
    levelSlot := keccak256(0x00, 0x40)
}
```

This computes `keccak256(abi.encode(lvl, traitBurnTicket.slot))` which is the Solidity standard formula for `mapping[key]`. **CORRECT.**

```solidity
// Lines 2121-2139: Per-trait writes
assembly ("memory-safe") {
    let elem := add(levelSlot, traitId)    // Fixed array index
    let len := sload(elem)                  // Current array length
    let newLen := add(len, occurrences)      // Updated length
    sstore(elem, newLen)                    // Store new length

    mstore(0x00, elem)
    let data := keccak256(0x00, 0x20)       // Dynamic array data start
    let dst := add(data, len)               // Next write position
    for { let k := 0 } lt(k, occurrences) { k := add(k, 1) } {
        sstore(dst, player)                 // Write player address
        dst := add(dst, 1)
    }
}
```

**`elem = add(levelSlot, traitId)`:** For a fixed-size array `address[][256]`, the element at index `traitId` is at slot `levelSlot + traitId`. This is the standard Solidity layout for fixed-size arrays within mappings. **CORRECT.**

**`len = sload(elem)`:** The length of the dynamic array `traitBurnTicket[lvl][traitId]` is stored at slot `elem`. **CORRECT.**

**`data = keccak256(elem)`:** The data of the dynamic array starts at `keccak256(element_slot)`. This is the standard Solidity layout for dynamic arrays. **CORRECT.**

**`dst = add(data, len)`:** The next available write position is at `data + current_length`. Since each `address` occupies one full slot (padded to 32 bytes), `add(data, len)` gives the correct slot for the next entry. **CORRECT.**

**`sstore(dst, player)`:** Writes the player address to the next slot. Solidity stores addresses left-padded in 32 bytes; writing the full uint256 representation of an address is correct. **CORRECT.**

#### Collision Risk

Can different `(lvl, traitId)` pairs produce the same slot?

- Different `lvl` values produce different `levelSlot` (keccak256 collision resistance).
- Different `traitId` values with the same `lvl` produce different `elem = levelSlot + traitId` (traitId is [0,255], so elements are at consecutive slots -- no overlap with other levels' slots since keccak256 output space is 2^256).
- Data slots: `keccak256(elem)` for different `elem` values are distinct (keccak collision resistance).
- No overlap between length slots and data slots: length is at `elem`, data starts at `keccak256(elem)`. These are in disjoint regions of the storage space.

**VERDICT: SAFE -- no collision risk.**

#### Array Length Accounting

`newLen = add(len, occurrences)` correctly tracks the total array length. `sstore(elem, newLen)` saves it. Since `occurrences` is a `uint32` count from the memory tracking array, and `len` is the current length, the addition is correct. Overflow: would require 2^256 entries, practically impossible.

**VERDICT: SAFE**

#### LCG Analysis

```solidity
// Line 2076-2084
uint64 s = uint64(seed) | 1;  // Ensure odd
s = s * (TICKET_LCG_MULT + uint64(offset)) + uint64(offset);  // Initial skip
s = s * TICKET_LCG_MULT + 1;  // LCG step (Knuth MMIX)
```

`TICKET_LCG_MULT = 0x5851F42D4C957F2D` is the Knuth MMIX LCG multiplier.

Standard form: `s = a * s + c (mod 2^64)` where `a = TICKET_LCG_MULT`, `c = 1`.

Full period requirements (Hull-Dobell theorem): (1) c is odd -- yes (c=1). (2) a-1 is divisible by all prime factors of m=2^64 -- a-1 = 0x5851F42D4C957F2C, which is divisible by 4 (last 2 bits are 00), and by 2 (the only prime factor of 2^64). (3) If 4 divides m, then 4 divides a-1 -- 0x...F2C & 3 = 0, so a-1 mod 4 = 0. **Full period guaranteed.**

The `| 1` at L2076 ensures the seed is odd, which does not affect the LCG's period guarantee (the period is always 2^64 for valid Hull-Dobell parameters regardless of seed).

The initial skip at L2079 `s = s * (TICKET_LCG_MULT + uint64(offset)) + uint64(offset)` uses a modified multiplier for the first step. This breaks the standard LCG form for one step but effectively just provides a different starting point in the sequence. Not a security issue.

**F-02 INVESTIGATE (INFO):** The assembly uses `add(levelSlot, traitId)` to compute the inner dimension slot. This is correct for Solidity's layout of fixed-size arrays within mappings (`T[N]` stored at consecutive slots starting from the mapping value slot). However, this layout assumption is not explicitly documented in the assembly block. If the `traitBurnTicket` declaration were ever changed from `mapping(uint24 => address[][256])` to `mapping(uint24 => mapping(uint8 => address[]))`, the assembly would silently write to wrong slots. Since the contract is non-upgradeable, this is not a practical risk.

**Severity rationale:** INFO. The code is correct for the current declaration and the contract is immutable.

#### Memory Safety

The assembly blocks are annotated `"memory-safe"`. Verification:
- Only scratch space (0x00-0x3F) is used for `mstore`. This is the designated scratch space per Solidity docs.
- No `mload` from memory managed by Solidity.
- No `mstore` to locations beyond scratch space.

**VERDICT: SAFE**

---

## Five Common Pitfalls Verification

### Pitfall 1: Liability Tracking Mismatch

Every call site of `_addClaimableEth` verified:

| Call Site | Uses Return Value? | Accumulates to claimablePool? | Verdict |
|-----------|-------------------|------------------------------|---------|
| C11 L1407 | `claimableDelta = _addClaimableEth(...)` | `liabilityDelta += claimableDelta` [L1420], then `claimablePool += liabilityDelta` [L1430] | CORRECT |
| C2 L901 | `claimableDelta = _addClaimableEth(VAULT, ...)` | Accumulated with L906 result, then `claimablePool += claimableDelta` [L911] | CORRECT |
| C2 L906 | `+ _addClaimableEth(SDGNRS, ...)` | Same as above | CORRECT |
| C14 L1627 | `claimableDelta = _addClaimableEth(w, perWinner, ...)` | `totalLiability += claimableDelta` [L1640], returned as `liabilityDelta` | CORRECT |
| C15 L1674 | `return _addClaimableEth(beneficiary, amount, entropy)` | Return value propagated to caller (C14 or C16) | CORRECT |

**All call sites use the return value.** No instance of using `weiAmount` instead of `claimableDelta`.

### Pitfall 2: Auto-Rebuy ETH Diversion

Verified at each call site above -- all use `claimableDelta` (C3's return value), not the original amount parameter. The auto-rebuy return path at C3 L941 returns `calc.reserved` (which may be 0 or takeProfit amount), and all callers correctly accumulate this value, not the original `weiAmount`.

### Pitfall 3: Assembly Storage Slot Miscalculation

Verified in the Inline Assembly Verification section above. Manual slot computation matches Solidity standard layout.

### Pitfall 4: Gas-Bounded Iteration Inconsistency

B6 `processTicketBatch` verified:
- Level switch: `ticketLevel = lvl; ticketCursor = 0` [L1819-1820]
- Normal exit (budget exhausted): `ticketCursor = uint32(idx)` [L1863]
- Completion: `delete ticketQueue[rk]; ticketCursor = 0; ticketLevel = 0` [L1867-1869]
- Early completion (idx >= total before loop): same cleanup at L1826-1829

All exit paths save cursor state. No path that returns without updating `ticketCursor`. `_processOneTicketEntry` returns `(0, false)` when budget insufficient [L1941, L1950], triggering the `break` at L1851.

**F-04 INVESTIGATE (INFO):** At L778, `_setFuturePrizePool(_getFuturePrizePool() - reserveContribution)` calls `_getFuturePrizePool()` twice in two successive lines (L774 for the calculation, L778 for the deduction). Both read `prizePoolsPacked` from storage. Since no writes occur between L774 and L778, the two reads return the same value. The double SLOAD is a minor gas inefficiency (warm read is 100 gas), not a correctness issue. This pattern appears in several places (L604, L855, L982, L984).

### Pitfall 5: Prize Pool Accounting Drift

Conservation invariant: `currentPrizePool + nextPrizePool + futurePrizePool + claimablePool + yieldAccumulator = total_protocol_eth` (minus stETH balance adjustments for yield).

**B2 daily path (Phase 0):**
1. Pool deductions: `currentPrizePool -= paidDailyEth` [L503]
2. Pool credits: For each winner, either `claimableWinnings[w] += perWinner` (normal) or `futurePrizePool/nextPrizePool += ethSpent` (auto-rebuy) + `claimableWinnings[player] += reserved`
3. Aggregate: `claimablePool += liabilityDelta` [L1430] where `liabilityDelta = sum(claimableDelta)`
4. Conservation: `currentPrizePool` decreases by `paidEth`. `claimablePool` increases by `liabilityDelta`. Auto-rebuy diverts `ethSpent` to future/nextPrizePool. Total: `paidEth = sum(perWinner)` for all winners. For each winner: `perWinner = claimableDelta + ethSpent` (auto-rebuy) or `perWinner = claimableDelta` (normal). So `paidEth = liabilityDelta + totalEthSpent`. `currentPrizePool` decreases by `paidEth`, `claimablePool` increases by `liabilityDelta`, `future/nextPrizePool` increases by `totalEthSpent`. **Conserved.**

**B5 consolidation:**
1. `currentPrizePool += nextPrizePool; nextPrizePool = 0` -- zero-sum transfer.
2. x00 keep-roll: `futurePrizePool = keepWei; currentPrizePool += moveWei` where `moveWei = fp - keepWei`. Total change: futurePool decreases by moveWei, currentPool increases by moveWei. **Conserved.**
3. Yield surplus: surplus = `totalBal - obligations`. Split: 23% to VAULT, 23% to SDGNRS (via claimableWinnings/claimablePool), 46% to yieldAccumulator. Total allocated = `2 * stakeholderShare + accumulatorShare`. `stakeholderShare = yieldPool * 2300 / 10000`, `accumulatorShare = yieldPool * 4600 / 10000`. Sum = `yieldPool * 9200 / 10000 = 92%`. Remaining 8% stays as unextracted buffer. **This is by design** (NatSpec: "~8% buffer left unextracted").

**Conserved across all paths.**

---

## Additional C-function Analyses (Tier 3 Completions)

### _runEarlyBirdLootboxJackpot (C1, line 772-835)

**Call Tree:** See B2 call tree. C1 deducts 3% from futurePrizePool [L778], distributes tickets via `_queueTickets` [L819], then adds full budget to nextPrizePool [L834]. No _addClaimableEth calls. No BAF chain.

**Storage Writes:** prizePoolsPacked (future at L778, next at L834), ticketQueue/ticketsOwedPacked (via _queueTickets).

**Cache Check:** C1 reads `_getFuturePrizePool()` at L774 for calculation, then fresh at L778 for deduction. No stale cache -- reads are in consecutive lines with no intervening writes. SAFE.

### _distributeLootboxAndTickets (C5, line 1050-1073)

**Call Tree:** `_setNextPrizePool(_getNextPrizePool() + lootboxBudget)` [L1058], then `_distributeTicketJackpot` [L1064] (C6). No _addClaimableEth calls.

**Storage Writes:** prizePoolsPacked (next at L1058), ticketQueue (via C6->C7->C8->_queueTickets).

**Cache Check:** No pool values cached. SAFE.

### _executeJackpot (C9, line 1280-1294)

**Call Tree:** Unpacks params, calls `_runJackpotEthFlow` (C10) [L1292].

**Storage Writes:** Via C10->C12->...->C3->C4 chain. No direct writes.

**Cache Check:** No pool values cached. JackpotParams struct has `ethPool`, `lvl`, `entropy` -- none are storage-backed pool caches. SAFE.

### _runJackpotEthFlow (C10, line 1297-1322)

**Call Tree:** JackpotBucketLib calls (pure), then `_distributeJackpotEth` (C12) [L1314].

**Storage Writes:** Via C12 chain. No direct writes.

**Cache Check:** No pool values cached. SAFE.

### _processOneBucket (C13, line 1477-1504)

**Call Tree:** Calls `_resolveTraitWinners` (C14) [L1491], accumulates results into ctx struct.

**Storage Writes:** Via C14 chain. No direct writes.

**Cache Check:** `ctx` struct passed by reference. Fields are running sums, not pool values. SAFE.

### _creditJackpot (C15, line 1663-1676)

**Call Tree:** If payCoin: `coin.creditFlip` [L1670] (external). If !payCoin: `_addClaimableEth` [L1674] (C3).

**Storage Writes:** Via C3 chain (if ETH path). coin.creditFlip is external-only.

**Cache Check:** No local caches. Pure delegation. SAFE.

### _resolveZeroOwedRemainder (C17, line 1877-1904)

**Call Tree:** `_rollRemainder` (D22, pure) [L1893]. Writes `ticketsOwedPacked[rk][player]` [L1888/1895/1901].

**Storage Writes:** ticketsOwedPacked only.

**Cache Check:** `packed` is read from storage [passed in from C18 L1916]. No pool values. SAFE.

### _processOneTicketEntry (C18, line 1907-1970)

**Call Tree:** `_resolveZeroOwedRemainder` (C17) [L1925], `_generateTicketBatch` (C19) [L1953], `_finalizeTicketEntry` (C21) [L1960].

**Storage Writes:** ticketsOwedPacked (via C17, C21), traitBurnTicket (via C19->C20 assembly).

**Cache Check:** `packed = ticketsOwedPacked[rk][player]` [L1916] cached locally. C17 may write back to same slot. However, C17's write happens at L1888/1895/1901, and the `packed` value is re-derived from C17's return at L1925 (`packed, skip = _resolveZeroOwedRemainder(...)`). So the local is updated. SAFE.

### _generateTicketBatch (C19, line 1973-1993)

**Call Tree:** Stack reduction wrapper for `_raritySymbolBatch` (C20) [L1984]. Emits `TraitsGenerated` event.

**Storage Writes:** Via C20 assembly. No direct writes.

**Cache Check:** No pool values. SAFE.

### _finalizeTicketEntry (C21, line 1996-2021)

**Call Tree:** `_rollRemainder` (D22, pure) [L2011]. Writes `ticketsOwedPacked[rk][player]` [L2018].

**Storage Writes:** ticketsOwedPacked only.

**Cache Check:** `packed` passed as parameter. `newPacked` computed from `remainingOwed` and `rem`. No pool values. SAFE.

### _clearDailyEthState (C25, line 2708-2714)

**Call Tree:** Direct writes only, no sub-calls.

**Storage Writes:** dailyEthPhase=0, dailyEthPoolBudget=0, dailyCarryoverEthPool=0, dailyCarryoverWinnerCap=0, dailyJackpotCoinTicketsPending=true.

**Cache Check:** No reads, only writes. SAFE.

### _creditClaimable (C26, PayoutUtils line 30-36)

**Call Tree:** `claimableWinnings[beneficiary] += weiAmount` [PU:33]. Emits `PlayerCredited`.

**Storage Writes:** claimableWinnings[beneficiary] only.

**Cache Check:** No cached values. Direct write. SAFE.

---

## Summary of All Verdicts

### Category B Functions (7 total)

| Function | State Coherence | Access Control | RNG | Cross-Contract | Edge Cases | Conditional | Economic | Griefing | Ordering | Silent Failures |
|----------|----------------|---------------|-----|---------------|------------|------------|----------|---------|----------|----------------|
| B1 runTerminalJackpot | SAFE | SAFE | SAFE | SAFE | SAFE | SAFE | SAFE | SAFE | SAFE | SAFE |
| B2 payDailyJackpot | SAFE | SAFE | SAFE | SAFE | SAFE | SAFE | SAFE | SAFE | SAFE | SAFE |
| B3 payDailyJackpotCoinAndTickets | SAFE | SAFE | SAFE | SAFE | SAFE | SAFE | SAFE | SAFE | SAFE | SAFE |
| B4 awardFinalDayDgnrsReward | SAFE | SAFE | SAFE | SAFE | SAFE | SAFE | SAFE | SAFE | SAFE | SAFE |
| B5 consolidatePrizePools | SAFE | SAFE | SAFE | SAFE | SAFE | SAFE | SAFE | SAFE | SAFE | SAFE |
| B6 processTicketBatch | SAFE | SAFE | SAFE | SAFE | SAFE | SAFE | SAFE | SAFE | SAFE | SAFE |
| B7 payDailyCoinJackpot | SAFE | SAFE | SAFE | SAFE | SAFE | SAFE | SAFE | SAFE | SAFE | SAFE |

### Category C Multi-Parent Functions (6 standalone)

| Function | All Parents SAFE? | BAF Pattern? |
|----------|------------------|-------------|
| C3 _addClaimableEth | YES (5 parents verified) | No stale writeback in any parent |
| C6 _distributeTicketJackpot | YES (2 parents) | No pool writes in C6 |
| C12 _distributeJackpotEth | YES (2 parents) | No cached pool values in ctx struct |
| C22 _awardDailyCoinToTraitWinners | YES (2 parents) | No storage writes in C22 |
| C23 _awardFarFutureCoinJackpot | YES (2 parents) | No storage writes in C23 |
| C24 _syncDailyWinningTraits | YES (2 parents) | No pool writes, no pool reads |

### Inline Assembly

| Check | Result |
|-------|--------|
| Storage slot correctness | CORRECT -- matches Solidity standard layout |
| Array length accounting | CORRECT -- `add(len, occurrences)` |
| Data slot calculation | CORRECT -- `keccak256(elem)` for dynamic array data start |
| Collision risk | NONE -- keccak256 collision resistance |
| LCG full period | GUARANTEED -- Hull-Dobell theorem satisfied |
| Memory safety | VERIFIED -- scratch space only |

### Five Pitfalls

| Pitfall | Checked | Result |
|---------|---------|--------|
| 1. Liability tracking mismatch | All 5 _addClaimableEth call sites | All use return value correctly |
| 2. Auto-rebuy ETH diversion | All call sites | All use claimableDelta, not weiAmount |
| 3. Assembly slot miscalculation | _raritySymbolBatch | Matches standard Solidity layout |
| 4. Gas-bounded iteration | processTicketBatch | All exit paths save cursor correctly |
| 5. Prize pool accounting drift | B2, B5 conservation analysis | Conserved across all paths |

---

**End of Attack Report. 0 VULNERABLE, 5 INVESTIGATE (all INFO). Ready for Skeptic review.**
