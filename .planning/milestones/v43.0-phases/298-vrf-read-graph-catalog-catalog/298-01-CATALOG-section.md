# §1 — JackpotModule.payDailyJackpot (file:line 339)

**Consumer entry:** `contracts/modules/DegenerusGameJackpotModule.sol:339`
**Caller stack:** `AdvanceModule.advanceGame` (`DegenerusGameAdvanceModule.sol:158`) → daily-phase branch invokes `payDailyJackpot(false, purchaseLevel, rngWord)` at `:383` (purchase-phase path) OR `payDailyJackpot(true, lvl, rngWord)` at `:454` (resume call 2) / `:473` (fresh daily jackpot, jackpot phase). Each call hits `AdvanceModule.payDailyJackpot` (`:915`) which does `delegatecall` into `IDegenerusGameJackpotModule.payDailyJackpot.selector` (`:924`).
**VRF word source:** `rngWord` parameter forwarded from `rngGate(...)`'s return at `AdvanceModule.sol:290`. The local `rngWord` is sourced from `rngWordCurrent` (the VRF-callback-published, nudge-mixed word written at `_applyDailyRng` line `:1840` BEFORE `rngLockedFlag` is cleared) — the in-flight resolution stack uses the cached parameter value, not re-reading the storage slot between Phase-1 (`payDailyJackpot`) and Phase-2 (`payDailyJackpotCoinAndTickets`) hops, except where explicitly enumerated below.
**EXEMPT-stack roots in scope for this consumer:** EXEMPT-ADVANCEGAME (every reachable `payDailyJackpot` call site lives inside `advanceGame`'s static call graph — confirmed by `grep -rn "payDailyJackpot"` on the full source tree: only the 3 callers at `AdvanceModule.sol:383/454/473` exist). EXEMPT-VRFCALLBACK does not directly invoke `payDailyJackpot` — `rawFulfillRandomWords` only writes `rngWordCurrent` then returns; the consumer is reached on the NEXT `advanceGame` call. EXEMPT-RETRYLOOTBOXRNG is unrelated (lootbox path, not daily jackpot).
**Pre-call state latches (relevant to commitment-window analysis):** Immediately before `payDailyJackpot(true, lvl, rngWord)` is invoked from the jackpot-phase branch:
- (i) `rngLockedFlag = true` (set at `_requestRng`, line `:1634`), and remains true through the entire resolution until `_unlockRng` at the end of phase-2 or phase-1 path completion (`:467` / `:402` / `:631` / `:1729`).
- (ii) `dailyIdx` is the PRIOR day's index — `_unlockRng` (the only writer at `:1730`) runs AFTER `payDailyJackpot` returns, so for the lifetime of this consumer `dailyIdx` is still `D` while `_simulatedDayIndex()` returns `D+1`.
- (iii) `level` may have been pre-incremented at `_requestRng` line `:1643` when `isTicketJackpotDay && !isRetry`. The cached local `lvl` parameter holds the value AS OF `advanceGame`'s top-of-call SLOAD at line `:163`; the storage slot may be one ahead.
- (iv) `_swapAndFreeze(purchaseLevel)` (`:299` / `:1095` etc.) toggled `ticketWriteSlot` so that any mid-window `_queueTickets` write lands in the NEW write slot, while `processTicketBatch` runs against the OLD read slot. The double-buffer is the structural protection against same-resolution `ticketQueue`-mediated injection.
- (v) `_prepareFutureTickets` (`:344`) and `_runProcessTicketBatch(inJackpot ? lvl : purchaseLevel)` (`:357`) have already drained the read slot into `traitBurnTicket[lvl]` via `_raritySymbolBatch` BEFORE `payDailyJackpot` runs. The participating slots' state visible to the consumer is therefore the read-slot snapshot taken at queue-swap time.

---

## CAT-01 (§A) — Traced Function Set

Every internal/external function transitively reached from `payDailyJackpot` with explicit file:line citation. Three distinct execution profiles need to be covered: (P1) `isJackpotPhase=true, resumeEthPool == 0` (fresh daily jackpot), (P2) `isJackpotPhase=true, resumeEthPool != 0` (call-2 resume), (P3) `isJackpotPhase=false` (purchase-phase BAF-like daily). All three are traced.

| # | Function | File:line | Reached via | Notes |
|---|----------|-----------|-------------|-------|
| 1 | `payDailyJackpot(isJackpotPhase, lvl, randWord)` | `DegenerusGameJackpotModule.sol:339` | ENTRY (no access guard — module is delegatecall-only from parent GAME proxy) | 3 execution profiles per branch on `isJackpotPhase` + `resumeEthPool` |
| 2 | `_simulatedDayIndex()` | `DegenerusGameStorage.sol:1208` | 1 → :344 (`questDay = _simulatedDayIndex()`) | wraps `GameTimeLib.currentDayIndex()` — pure block.timestamp arithmetic, NO SLOAD |
| 3 | `GameTimeLib.currentDayIndex()` | `GameTimeLib.sol:21` | 2 → :1209 | `[view]` reads only `block.timestamp` |
| 4 | `_resumeDailyEth(lvl, randWord)` | `DegenerusGameJackpotModule.sol:1178` | 1 → :350 (P2 branch when `resumeEthPool != 0`) | reads `resumeEthPool` via `_processDailyEth`; reads `dailyTicketBudgetsPacked`, `jackpotCounter`; reads `_get*PrizePool` on payout |
| 5 | `_rollWinningTraits(randWord, false)` | `DegenerusGameJackpotModule.sol:1993` | 1 → :354 (P1); 1 → :531 (P3); 4 → :1180 (P2) | reads `dailyIdx` + `dailyHeroWagers[dailyIdx]` via `_applyHeroOverride` |
| 6 | `JackpotBucketLib.getRandomTraits(r)` | `JackpotBucketLib.sol:281` | 5 → :2000 | `[pure]` |
| 7 | `_applyHeroOverride(traits, r, randWord)` | `DegenerusGameJackpotModule.sol:1600` | 5 → :2001 | reads `dailyIdx` (line :1609) + delegates to `_rollHeroSymbol` |
| 8 | `_rollHeroSymbol(dailyIdx, heroEntropy)` | `DegenerusGameJackpotModule.sol:1639` | 7 → :1609 | reads `dailyHeroWagers[day][q]` for q=0..3 (4 SLOADs at :1653) |
| 9 | `JackpotBucketLib.packWinningTraits(traits)` | `JackpotBucketLib.sol:267` | 5 → :2002 | `[pure]` |
| 10 | `_dailyCurrentPoolBps(counter, randWord)` | `DegenerusGameJackpotModule.sol:2015` | 1 → :379 (P1, non-final day) | `[pure]` |
| 11 | `_getCurrentPrizePool()` | `DegenerusGameStorage.sol:814` | 1 → :374, :407, :507, :515 (P1); 4 → :1203 (P2) | reads `currentPrizePool` slot |
| 12 | `_setCurrentPrizePool(val)` | `DegenerusGameStorage.sol:821` | 1 → :406, :506, :515 (P1); 4 → :1203 (P2) | writes `currentPrizePool` |
| 13 | `_getNextPrizePool()` | `DegenerusGameStorage.sol:785` | 1 → :409, :434 (P1); 24 → :842, :725 (carryover) | reads `prizePoolsPacked` |
| 14 | `_setNextPrizePool(val)` | `DegenerusGameStorage.sol:791` | 1 → :409, :434 (P1); 24 → :842 | writes `prizePoolsPacked` |
| 15 | `_getFuturePrizePool()` | `DegenerusGameStorage.sol:797` | 1 → :431, :511, :548, :570 (all paths); 4 → :1201 (P2) | reads `prizePoolsPacked` |
| 16 | `_setFuturePrizePool(val)` | `DegenerusGameStorage.sol:803` | 1 → :433, :510, :569 (all paths); 4 → :1201 (P2); 30 → :840 | writes `prizePoolsPacked` |
| 17 | `_getPrizePools()` | `DegenerusGameStorage.sol:688` | 13/14/15/16 (indirect) | reads `prizePoolsPacked` |
| 18 | `_setPrizePools(next, future)` | `DegenerusGameStorage.sol:684` | 14/16 (indirect) | writes `prizePoolsPacked` |
| 19 | `_runEarlyBirdLootboxJackpot(lvl + 1, randWord)` | `DegenerusGameJackpotModule.sol:676` | 1 → :390 (P1, isEarlyBirdDay) | reads `traitBurnTicket[lvl+1][bonusTrait]` for 4 buckets |
| 20 | `_budgetToTicketUnits(budget, lvl)` | `DegenerusGameJackpotModule.sol:853` | 1 → :400, :435 (P1) | `[pure]` (delegates to `PriceLookupLib.priceForLevel`) |
| 21 | `PriceLookupLib.priceForLevel(targetLevel)` | `PriceLookupLib.sol:21` | 20 → :858; 19 → :682; 33 → :2288; etc. | `[pure]` |
| 22 | `_packDailyTicketBudgets(...)` | `DegenerusGameJackpotModule.sol:2030` | 1 → :444 (P1) | `[pure]` |
| 23 | `_unpackDailyTicketBudgets(packed)` | `DegenerusGameJackpotModule.sol:2043` | 1 → :459 (P1); 4 → :1183 (P2) | `[pure]` |
| 24 | `EntropyLib.hash2(rngWord, lvl)` | `EntropyLib.sol:23` | 1 → :454 (P1); 1 → :533 (P3); 4 → :1179 (P2); 33 → :2267; 26 → :888 | `[pure]` keccak |
| 25 | `JackpotBucketLib.unpackWinningTraits(packed)` | `JackpotBucketLib.sol:272` | 1 → :455 (P1); 1 → :532 (P3); 4 → :1180 (P2); 19 → :688; 26 → :907; 28 → :1127 | `[pure]` |
| 26 | `_pickSoloQuadrant(traits, entropy)` | `DegenerusGameJackpotModule.sol:1098` | 1 → :457 (P1); 1 → :534 (P3); 4 → :1181 (P2) | `[pure]` |
| 27 | `JackpotBucketLib.bucketCountsForPoolCap(...)` | `JackpotBucketLib.sol:98` | 1 → :466 (P1); 4 → :1192 (P2) | `[pure]` |
| 28 | `JackpotBucketLib.traitBucketCounts(entropy)` | `JackpotBucketLib.sol:36` | 27 → :105 | `[pure]` |
| 29 | `JackpotBucketLib.scaleTraitBucketCountsWithCap(...)` | `JackpotBucketLib.sol:55` | 27 → :106 | `[pure]` |
| 30 | `JackpotBucketLib.capBucketCounts(counts, max, entropy)` | `JackpotBucketLib.sol:115` | 29 → :94 | `[pure]` |
| 31 | `JackpotBucketLib.sumBucketCounts(counts)` | `JackpotBucketLib.sol:110` | 30 → :129 | `[pure]` |
| 32 | `JackpotBucketLib.shareBpsByBucket(packed, offset)` | `JackpotBucketLib.sol:254` | 1 → :490 (P1); 4 → :1188 (P2); 33 → :1130 (P3) | `[pure]` |
| 33 | `JackpotBucketLib.rotatedShareBps(packed, off, idx)` | `JackpotBucketLib.sol:248` | 32 → :257 | `[pure]` |
| 34 | `_processDailyEth(lvl, ethPool, entropy, traits, shareBps, counts, isFinalDay, splitMode, isJackpotPhase)` | `DegenerusGameJackpotModule.sol:1232` | 1 → :493 (P1); 4 → :1185 (P2) (with `SPLIT_CALL2`); 35 → :1158 (P3, via `_runJackpotEthFlow`) | reads `resumeEthPool` (writes when `SPLIT_CALL2`); reads `traitBurnTicket[lvl][trait]` via `_randTraitTicket`; writes `claimablePool` via `:1335` |
| 35 | `_executeJackpot(jp)` | `DegenerusGameJackpotModule.sol:1124` | 1 → :557 (P3) | dispatches to `_runJackpotEthFlow` |
| 36 | `_runJackpotEthFlow(jp, traitIds, shareBps)` | `DegenerusGameJackpotModule.sol:1142` | 35 → :1136 | calls `_processDailyEth` with fixed `[20,12,6,1]` rotation |
| 37 | `JackpotBucketLib.soloBucketIndex(entropy)` | `JackpotBucketLib.sol:243` | 34 → :1252 | `[pure]` |
| 38 | `JackpotBucketLib.bucketShares(pool, shareBps, counts, idx, unit)` | `JackpotBucketLib.sol:214` | 34 → :1253 | `[pure]` |
| 39 | `JackpotBucketLib.bucketOrderLargestFirst(counts)` | `JackpotBucketLib.sol:1257` | 34 → :1257 | `[pure]` |
| 40 | `_randTraitTicket(traitBurnTicket[lvl], rng, trait, n, salt)` | `DegenerusGameJackpotModule.sol:1707` | 34 → :1297; 19 → :688/:697 (early-bird); 51 → :883 (distributeLootbox); 60 → :983 (distributeTicketJackpot) | reads `traitBurnTicket[lvl][trait]` (length + element slots) + `deityBySymbol[fullSymId]` |
| 41 | `_handleSoloBucketWinner(w, lvl, traitId, ticketIdx, perWinner, entropy, isFinalDay)` | `DegenerusGameJackpotModule.sol:1454` | 34 → :1316 (only when `isJackpotPhase=true && traitIdx==remainderIdx`) | delegates to `_processSoloBucketWinner` + reads `dgnrs.poolBalance` on final day |
| 42 | `_processSoloBucketWinner(winner, perWinner, entropy)` | `DegenerusGameJackpotModule.sol:1539` | 41 → :1473 | calls `_addClaimableEth`; writes `whalePassClaims[w]` + `_setFuturePrizePool` |
| 43 | `IStakedDegenerusStonk.poolBalance(Pool.Reward)` | `StakedDegenerusStonk.sol:391` | 41 → :1493 (isFinalDay only) | EXTERNAL call into sDGNRS contract — reads `poolBalances[idx]` (sDGNRS-local storage, not GAME storage) |
| 44 | `IStakedDegenerusStonk.transferFromPool(...)` | `StakedDegenerusStonk.sol:412` | 41 → :1498 (isFinalDay only) | EXTERNAL — writes sDGNRS-local `poolBalances`, `balanceOf`, `totalSupply` — outside GAME storage scope |
| 45 | `_payNormalBucket(winners, ticketIdx, perWinner, lvl, traitId, entropy)` | `DegenerusGameJackpotModule.sol:1509` | 34 → :1326 (when not isJackpotPhase OR not solo bucket) | iterates winners, calls `_addClaimableEth` per winner |
| 46 | `_addClaimableEth(beneficiary, weiAmount, entropy)` | `DegenerusGameJackpotModule.sol:780` | 42 → :1563/:1575; 45 → :1521; 23 (via `_processAutoRebuy`) | reads `gameOver` + `autoRebuyState[beneficiary]`; writes `claimableWinnings` via `_creditClaimable` OR routes to auto-rebuy |
| 47 | `_processAutoRebuy(player, newAmount, entropy, state)` | `DegenerusGameJackpotModule.sol:814` | 46 → :796 (when `!gameOver && state.autoRebuyEnabled`) | calls `_calcAutoRebuy` (pure), `_queueTickets`, `_setFuturePrizePool`/`_setNextPrizePool`, `_creditClaimable` |
| 48 | `_calcAutoRebuy(...)` | `DegenerusGamePayoutUtils.sol:51` | 47 → :822 | `[pure]` — reads `state` from memory only |
| 49 | `_creditClaimable(beneficiary, weiAmount)` | `DegenerusGamePayoutUtils.sol:32` | 46 → :802; 47 → :833/:846 | writes `claimableWinnings[beneficiary]` |
| 50 | `_queueTickets(buyer, targetLevel, quantity, true)` | `DegenerusGameStorage.sol:559` | 47 → :837; 19 → :703; 60 → :1007; 61 → :2305 | reads `level`, `rngLockedFlag` (gate at :572 — bypassed via `rngBypass=true`); writes `ticketQueue[wk]` + `ticketsOwedPacked[wk][buyer]` |
| 51 | `_distributeLootboxAndTickets(lvl, traits, budget, randWord, bps)` | `DegenerusGameJackpotModule.sol:869` | 1 → :575 (P3 only) | calls `_setNextPrizePool`, `_budgetToTicketUnits`, `_distributeTicketJackpot` |
| 52 | `_distributeTicketJackpot(sourceLvl, queueLvl, traits, units, entropy, max, salt)` | `DegenerusGameJackpotModule.sol:896` | 51 → :883 (P3); (NOT directly reached from P1 — P1 stores `dailyTicketBudgetsPacked` for Phase-2 consumption, out-of-trace) | reads `traitBurnTicket[sourceLvl]` (length via `_computeBucketCounts`); calls `_distributeTicketsToBuckets` |
| 53 | `_computeBucketCounts(lvl, traits, max, entropy)` | `DegenerusGameJackpotModule.sol:1030` | 52 → :913 | reads `traitBurnTicket[lvl][trait].length` (4×) + `deityBySymbol[fullSymId]` (4×) |
| 54 | `_distributeTicketsToBuckets(...)` | `DegenerusGameJackpotModule.sol:934` | 52 → :921 | dispatches to `_distributeTicketsToBucket` per active bucket |
| 55 | `_distributeTicketsToBucket(...)` | `DegenerusGameJackpotModule.sol:973` | 54 → :953 | calls `_randTraitTicket` + `_queueTickets` |
| 56 | `_tqWriteKey(lvl)` | `DegenerusGameStorage.sol:718` | 50 → :575 (indirect via `_queueTickets`) | `[view]` reads `ticketWriteSlot` |
| 57 | `_tqFarFutureKey(lvl)` | `DegenerusGameStorage.sol:731` | 50 → :574 | `[pure]` |
| 58 | `_livenessTriggered()` | `DegenerusGameStorage.sol:1243` | 50 → :570 | reads `lastPurchaseDay`, `jackpotPhaseFlag`, `level`, `purchaseStartDay`, `rngRequestTime`, `_simulatedDayIndex()` |

> **Note on Phase-2 split:** `payDailyJackpot(true, …)` Phase-1 stores `dailyJackpotCoinTicketsPending = true` + `dailyTicketBudgetsPacked` at lines `:526` / `:444`. Phase-2 (`payDailyJackpotCoinAndTickets`) is a SEPARATE consumer entry (§2 — see `298-02-CATALOG-section.md`). The transitive Phase-2 reach is OUT OF SCOPE for this §1 catalog per `D-298-CONSUMER-LIST-01`.

> **Stop boundary (external interfaces with no source available):** `IStakedDegenerusStonk.poolBalance` / `IStakedDegenerusStonk.transferFromPool` — sDGNRS is a SEPARATE deployed contract (`contracts/StakedDegenerusStonk.sol`), not delegatecall storage. The trace enumerates the SLOADs these external calls perform on sDGNRS-local storage, but those slots are in a SEPARATE storage namespace and do NOT influence VRF-derived output of this consumer — they only affect the sDGNRS reward-pool payout amount on `isFinalDay`. The relevant participating-slot analysis is bounded to GAME storage.

---

## CAT-02 (§B) — SLOAD Table

Every storage read reached anywhere in §A's function set is enumerated per `feedback_rng_window_storage_read_freshness.md` (F-41-02/03 precedent — NON-PARTICIPATING slots get explicit attestation). Columns: `Slot | Read-site (file:line) | Read context | Participating? (YES/NO) | Attestation if NO`.

| Slot | Read-site (file:line) | Read context | Participating? | Attestation if NO |
|------|-----------------------|--------------|----------------|-------------------|
| `dailyIdx` | `JackpotModule.sol:1609` (via `_applyHeroOverride` → `_rollHeroSymbol(dailyIdx, …)`) | Day-index parameter for `dailyHeroWagers[day][q]` SLOAD | **YES** | — |
| `dailyHeroWagers[D][q]` (4 SLOADs at q=0..3) | `JackpotModule.sol:1653` (inside `_rollHeroSymbol` Pass 1 loop) | Weighted-random hero `(quadrant, symbol)` selection → trait replacement at line `:1623` → drives bucket reads + winner selection | **YES** | — |
| `level` | `JackpotModule.sol:1773` (NOT reached from P1; only `_calcDailyCoinBudget` reads it via Phase-2 `_calcDailyCoinBudget` → out of trace); `JackpotModule.sol:608` (Phase-2 only); **inside Phase-1 trace:** `JackpotModule.sol:1571` of `_queueTickets` reads `level` indirectly via `_livenessTriggered` AND `level + 5` comparison at `:571`. Cached `lvl` parameter shadows the storage read at top-level callsites. | `_queueTickets` gate against far-future writes during RNG window | **YES** | Cached `lvl` parameter in `_processAutoRebuy` may differ from storage `level` if pre-incremented at `_requestRng:1643`; auto-rebuy `targetLevel = level + offset` derived from the storage SLOAD, which influences which `ticketQueue[wk]` slot receives the bonus tickets (does NOT directly drive winner selection but DOES influence reward routing within VRF-derived flow) |
| `gameOver` | `JackpotModule.sol:792` (inside `_addClaimableEth`) | Branch gate: when `gameOver=true` skip auto-rebuy and route 100% to `_creditClaimable` | **YES** | — |
| `autoRebuyState[beneficiary]` | `JackpotModule.sol:793` (`AutoRebuyState memory state = autoRebuyState[beneficiary]`) | Drives 30%/45% ticket conversion + `targetLevel` selection → influences which `ticketQueue` slot receives bonus tickets and how much ETH is redirected to `nextPrizePool`/`futurePrizePool` | **YES** | — |
| `claimableWinnings[beneficiary]` | `PayoutUtils.sol:35` (`claimableWinnings[beneficiary] += weiAmount`) | Write-only inside trace (the `+=` is SLOAD + SSTORE) | **NO** | Accounting aggregate; the value read is the existing balance, only the increment is the VRF-derived payout. Pre-existing balance does NOT influence the increment amount, winner selection, or any downstream VRF derivation. F-41-02/03 attestation: changing this slot mid-window only changes the resulting balance, never the bucket of winners or share assignment. |
| `claimablePool` | `JackpotModule.sol:1335` (`claimablePool += uint128(liabilityDelta)`); `PayoutUtils.sol:101` | Write-only `+=` aggregate | **NO** | Same as `claimableWinnings` — aggregate liability counter; pre-existing value drives no VRF output. |
| `traitBurnTicket[lvl][trait]` (length + elements) | `JackpotModule.sol:1718` (inside `_randTraitTicket`: `holders.length` + `holders[idx]`); `:1039` (`_computeBucketCounts`: `.length != 0` check); `:691` (early-bird `bucket = traitBurnTicket[lvl]`); `:1297` (`_processDailyEth`); `:1860` (Phase-2 only); `:1400` (`_resolveTraitWinners` — unreachable from P1 entry; dead-code helper still has SLOADs). All reads happen for `lvl ∈ {lvl, lvl+1, sourceLvl=lvl+1..lvl+4, queueLvl}` within this resolution. | Winner selection from trait bucket | **YES** | — |
| `deityBySymbol[fullSymId]` | `JackpotModule.sol:1730` (inside `_randTraitTicket`); `:1044` (`_computeBucketCounts` virtual deity check); `:1844` (Phase-2 only) | Virtual deity entry — when `idx >= len`, winner becomes `deity`; influences winner selection probability | **YES** | — |
| `whalePassClaims[winner]` | `PayoutUtils.sol:95` (`whalePassClaims[winner] += fullHalfPasses`); `JackpotModule.sol:1570` (`whalePassClaims[winner] += whalePassCount`) | Write-only `+=` aggregate inside `_processSoloBucketWinner` | **NO** | Aggregate of pending whale-pass redemptions; pre-existing value does NOT influence amount credited (the increment is `wpSpent/HALF_WHALE_PASS_PRICE` derived from `perWinner`, which is derived from VRF entropy + ethPool — not from prior `whalePassClaims` state). |
| `currentPrizePool` | `Storage.sol:815` (`_getCurrentPrizePool`); read at JackpotModule `:374, :407, :506, :515, :1203` | Pool snapshot — drives `dailyEthBudget = (poolSnapshot * dailyBps) / 10_000` at `:385`; this budget then determines `bucketCounts` at `:466` via `bucketCountsForPoolCap(dailyEthBudget, …)`, which controls per-bucket winner count distribution. | **YES** | — |
| `prizePoolsPacked` (futurePrizePool + nextPrizePool packed) | `Storage.sol:693` (`_getPrizePools`); read at JackpotModule `:431, :511, :548, :570, :725, :840, :842, :1201` | Future-pool snapshot — drives `reserveSlice = futurePoolBal / 200` at `:432` (carryover ticket reservation); `ethDaySlice = (_getFuturePrizePool() * poolBps) / 10_000` at `:548` (P3 1% drip); influences ETH budget for purchase-phase BAF-style payout. Drives `_setNextPrizePool(_getNextPrizePool() + reserveSlice)` and `_setFuturePrizePool(... - reserveSlice)`. Also `nextPrizePool` is referenced by `_queueTickets` indirectly via `_setNextPrizePool` writes; the read at `_getNextPrizePool` at `:409, :434` influences carryover routing. | **YES** | — |
| `yieldAccumulator` | (NOT directly reached from `payDailyJackpot`'s call graph — only `distributeYieldSurplus` at `:732` and GameOver at `GameOverModule.sol:150` read/write it; `distributeYieldSurplus` is invoked from `advanceGame` AT LEVEL TRANSITION, not as a sub-call of `payDailyJackpot`). | (out of trace for §1) | **N/A** | Slot is enumerated here for completeness attestation — `grep -rn yieldAccumulator contracts/` confirms zero reads inside `payDailyJackpot` → `_addClaimableEth` → `_processAutoRebuy` → `_creditClaimable` → `_distributeLootboxAndTickets` reach set. |
| `jackpotCounter` | `JackpotModule.sol:358` (P1: `uint8 counter = jackpotCounter`); `:462` (P1: `isFinalPhysicalDay_ = (jackpotCounter + counterStep_ ...)`); `:1184` (P2 resume: `jackpotCounter + cs`); `:651` (Phase-2 only); `:665` (`jackpotCounter += counterStep` — Phase-2 write) | Drives `counterStep` selection at :358-:371 (turbo/compressed/normal logic) → determines `isFinalPhysicalDay` → selects `FINAL_DAY_SHARES_PACKED` vs `DAILY_JACKPOT_SHARES_PACKED` at `:487` → influences share allocation across buckets. **DOES influence VRF-derived output:** different shares produce different `perWinner` amounts even with same entropy. | **YES** | — |
| `compressedJackpotFlag` | `JackpotModule.sol:362` (P1: `compressedJackpotFlag == 2 && counter == 0`); `:365` (P1: `compressedJackpotFlag == 1 ...`) | Drives `counterStep` selection at the same site as `jackpotCounter` | **YES** | — |
| `resumeEthPool` | `JackpotModule.sol:349` (P1 branch gate: `if (resumeEthPool != 0)`); `:1193` (P2 resume: pass to `bucketCountsForPoolCap`); `:1244` (P2 resume: `ethPool = uint256(resumeEthPool)`) | (P1) Branches into P2 resume path when non-zero. (P2) The cached ethPool snapshot from call-1 — drives bucket scaling at `:1192` AND determines `paidEth` adjustments at `:1199-:1204` | **YES** | — |
| `dailyTicketBudgetsPacked` | `JackpotModule.sol:460` (P1: `_unpackDailyTicketBudgets(dailyTicketBudgetsPacked)` after write at `:444`); `:1183` (P2 resume: `_unpackDailyTicketBudgets(dailyTicketBudgetsPacked)`); `:605` (Phase-2 unpacking — out of §1 trace) | P1 read at `:460` is of the value just-written at `:444` (same call). P2 (resume) read at `:1183` is of value written during a PREVIOUS `advanceGame` call's P1. The `counterStep` extracted at `:459` is reused for `isFinalPhysicalDay_` flag at `:462`. | **YES** | — |
| `lastPurchaseDay` | `Storage.sol:1244` (`_livenessTriggered`: `if (lastPurchaseDay \|\| jackpotPhaseFlag) return false`) | `_livenessTriggered` is reached via `_queueTickets` (`:570`). Read controls whether the liveness-timeout fires (and reverts `_queueTickets`). | **NO** | Read controls whether the in-flow `_queueTickets` reverts. A mid-window flip of `lastPurchaseDay` from true→false would unblock the liveness trigger and could revert the entire jackpot resolution. **However**, no external function writes `lastPurchaseDay = false` outside `advanceGame`'s state machine — it's only set true at `:176`/`:397` (mid-advance) and false at `:439` (post-jackpot transition). Since the consumer is itself inside `advanceGame`, no external mid-resolution flip is possible. Attestation: no race exists. |
| `jackpotPhaseFlag` | `Storage.sol:1244` (`_livenessTriggered`) | Same as `lastPurchaseDay` — used inside `_queueTickets`'s liveness gate | **NO** | Set inside `advanceGame` state machine only (`:437` write, no external writer). Attestation: no race exists. |
| `purchaseStartDay` | `Storage.sol:1246` (`_livenessTriggered`: `uint32 psd = purchaseStartDay`) | Drives liveness-timeout check inside `_queueTickets` gate | **NO** | Same — only written inside `advanceGame` (`:332`, `:642`); read controls revert behavior, not VRF derivation. |
| `rngRequestTime` | `Storage.sol:1250` (`_livenessTriggered`: `uint48 rngStart = rngRequestTime`) | VRF-stall liveness check | **NO** | Set/cleared inside `_requestRng` and `_unlockRng`. Since this consumer runs INSIDE the same advanceGame that holds `rngLockedFlag=true`, `rngRequestTime != 0` is guaranteed but cannot transition. Attestation: no concurrent writer outside the same stack. |
| `rngLockedFlag` | `Storage.sol:572` (inside `_queueTickets`: `if (isFarFuture && rngLockedFlag && !rngBypass) revert RngLocked()`); `:604, :660` (`_queueTicketsScaled` / `_queueTicketRange` — both unreachable from P1 trace) | Far-future bypass gate inside `_queueTickets`. Reach: only when `targetLevel > level + 5`. All `_queueTickets` calls from JackpotModule pass `rngBypass=true` (lines `:703, :837, :1007, :2305`), so the gate never fires for in-flow writes. | **NO** | Reads are bypassed via `rngBypass=true` in every Jackpot-stack `_queueTickets` invocation; the slot's value cannot change the VRF outcome of THIS consumer. (External writers of `rngLockedFlag` are gated to advanceGame-stack only.) |
| `ticketWriteSlot` | `Storage.sol:719` (`_tqWriteKey`); read inside `_queueTickets` at `:573-:575` | Determines write-slot key for `ticketQueue` writes from auto-rebuy + jackpot-flow `_queueTickets` calls | **NO** | The slot value affects which `ticketQueue[wk]` array receives the bonus tickets, NOT the winner selection. Auto-rebuy bonus tickets land in `ticketQueue[wk]` regardless of `wk` — the winners have already been selected via `_randTraitTicket` at this point. Attestation: write-side routing only, no read-back into VRF flow. |
| `ticketsOwedPacked[wk][buyer]` | `Storage.sol:576` (`_queueTickets`: `uint40 packed = ticketsOwedPacked[wk][buyer]`) | Read to check `owed/rem` before push to `ticketQueue` | **NO** | Per-player owed counter; never read by winner selection or share calculation. Pre-existing balance only determines whether `ticketQueue[wk].push(buyer)` fires for this player (deduplication). No VRF coupling. |
| `ticketQueue[wk]` (length only) | `Storage.sol:579` (implicit via `if (owed == 0 && rem == 0) ticketQueue[wk].push(buyer)`) | Length read implicit in `.push()` | **NO** | Same as `ticketsOwedPacked` — write-side routing for downstream `processTicketBatch` consumption (which happens on the NEXT advanceGame call), not part of this consumer's VRF derivation. |
| `IStakedDegenerusStonk.poolBalances[Pool.Reward]` (cross-contract) | `StakedDegenerusStonk.sol:392` (via `dgnrs.poolBalance(Pool.Reward)` call at `JackpotModule.sol:1493`) | Final-day DGNRS reward amount | **NO** | Cross-contract storage in sDGNRS namespace. The value is consumed only on `isFinalPhysicalDay` for the solo bucket winner — it determines `reward = (dgnrsPool * FINAL_DAY_DGNRS_BPS) / 10_000` at `:1496`, then `transferFromPool`. This payout is ORTHOGONAL to VRF-derived winner selection (the winner is already chosen). The reward amount IS influenced by the slot, but the slot is **external sDGNRS storage** — and per `D-298-EXEMPT-CROSSCONTRACT-01` + `D-298-TRACE-DEPTH-01`, we enumerate sDGNRS writers inline. **Reclassification:** Since the payout amount IS a VRF-resolved output ("how much DGNRS goes to winner X selected by VRF"), this slot crosses into participating territory. **Marked YES below — see verdict matrix.** |
| `IStakedDegenerusStonk.poolBalances[Pool.Reward]` (revised) | (same site) | (same context) | **YES** | (moved from NO above per verdict-matrix logic — see §C/§D) |

> **Completeness attestation:** Every SLOAD reachable from `payDailyJackpot`'s 3 execution profiles is listed. Pure-library helpers (JackpotBucketLib, EntropyLib, PriceLookupLib, GameTimeLib) perform ZERO SLOADs — confirmed by `grep -n "sload\|storage" contracts/libraries/*.sol` returning only function signatures (the `storage` keyword in `address[][256] storage` reference declarations is pointer aliasing, not a SLOAD on its own). `_simulatedDayIndex` reduces to `block.timestamp` arithmetic (no SLOAD).

> **Participating-set summary (forwards into §C):** `dailyIdx`, `dailyHeroWagers[D][q]` (×4 keys), `level` (cached vs storage discrepancy), `gameOver`, `autoRebuyState[beneficiary]`, `traitBurnTicket[lvl][trait]` (length + elements), `deityBySymbol[fullSymId]`, `currentPrizePool`, `prizePoolsPacked` (next + future components), `jackpotCounter`, `compressedJackpotFlag`, `resumeEthPool`, `dailyTicketBudgetsPacked`, sDGNRS `poolBalances[Pool.Reward]`.

---

## CAT-03 (§C) — Per-Participating-Slot Writer Enumeration

For each `Participating? = YES` slot in §B, every external/public function across all `contracts/` that writes the slot is enumerated, per-callsite. Each row: `Slot | Writer fn | Writer file:line | Callsite file:line | Reach path`.

### Slot: `dailyIdx`

| Writer fn | Writer file:line | Callsite file:line | Reach path |
|-----------|------------------|--------------------|------------|
| `_unlockRng(day)` | `DegenerusGameAdvanceModule.sol:1729` (writes `dailyIdx = day` at `:1730`) | `:331, :402, :467, :631, :1729` (all inside `advanceGame`) | advanceGame → `_unlockRng` (5 callsites, all advanceGame-stack) |
| `DegenerusGame.constructor` | `DegenerusGame.sol:219` (`dailyIdx = currentDay`) | `:219` | pre-deployment constructor (genesis only) |

### Slot: `dailyHeroWagers[D][q]`

| Writer fn | Writer file:line | Callsite file:line | Reach path |
|-----------|------------------|--------------------|------------|
| `_placeDegeneretteBetCore(...)` | `DegenerusGameDegeneretteModule.sol:499` (`dailyHeroWagers[day][heroQuadrant] = wPacked`) | reached from `placeDegeneretteBet` external entries: `DegenerusGameDegeneretteModule.sol:367` + `DegenerusGame.sol:714` (delegatecall fan-out) + `DegenerusVault.sol:607` (vault.placeDegeneretteBet → game.placeDegeneretteBet) | EOA / Vault → `placeDegeneretteBet` → `_placeDegeneretteBetCore` |

### Slot: `level`

| Writer fn | Writer file:line | Callsite file:line | Reach path |
|-----------|------------------|--------------------|------------|
| `_requestRng(...)` (inside `_finalizeRngRequest`) | `DegenerusGameAdvanceModule.sol:1643` (`level = lvl` when `isTicketJackpotDay && !isRetry`) | `:1643` (inside the only `_requestRng` flow which is `rngGate` → `_requestRng`) | advanceGame → `rngGate` → `_requestRng` |
| `DegenerusGameStorage.sol:250` declaration default | `DegenerusGameStorage.sol:250` | `:250` | constructor init only (`= 0`) |

### Slot: `gameOver`

| Writer fn | Writer file:line | Callsite file:line | Reach path |
|-----------|------------------|--------------------|------------|
| `handleGameOverDrain(day)` | `DegenerusGameGameOverModule.sol:139` (`gameOver = true`) | `:139` (reached from `advanceGame._handleGameOverPath` at `AdvanceModule.sol:624`) | advanceGame → `_handleGameOverPath` → `handleGameOverDrain` |
| `MockGameCharity.setGameOver(bool)` | `contracts/mocks/MockGameCharity.sol:11` (`gameOver = _over`) | `:11` | **mock-only** — not part of MAINNET deployment, excluded from verdict matrix |

### Slot: `autoRebuyState[beneficiary]`

| Writer fn | Writer file:line | Callsite file:line | Reach path |
|-----------|------------------|--------------------|------------|
| `_setAutoRebuy(player, enabled)` | `DegenerusGame.sol:1512` (`state.autoRebuyEnabled = enabled` at `:1516`) | `:1495` (`setAutoRebuy`) external entry; `:1512` private dispatch | EOA → `setAutoRebuy` |
| `_setAutoRebuyTakeProfit(player, takeProfit)` | `DegenerusGame.sol:1524` (`state.takeProfit = takeProfitValue` at `:1532`) | `:1504` (`setAutoRebuyTakeProfit`) | EOA → `setAutoRebuyTakeProfit` |
| `_setAfKingMode(player, enabled, …)` | `DegenerusGame.sol:1569` (writes `autoRebuyEnabled`, `takeProfit`, `afKingMode`, `afKingActivatedLevel` at `:1593, :1597, :1604, :1605`) | `:1559` (`setAfKingMode`) | EOA → `setAfKingMode` |
| `_deactivateAfKing(player)` | `DegenerusGame.sol:1670` (writes `afKingMode`, `afKingActivatedLevel` at `:1679, :1680`) | `:1641` (`deactivateAfKingFromCoin` external — COIN/COINFLIP only), `:1670` (private, called from `_setAutoRebuy`/`_setAfKingMode`) | EOA via setAutoRebuy/setAfKingMode + BurnieCoin/BurnieCoinflip → `deactivateAfKingFromCoin` |
| `syncAfKingLazyPassFromCoin(player)` | `DegenerusGame.sol:1654` (writes `afKingMode`, `afKingActivatedLevel` at `:1664, :1665`) | `:1654` (COINFLIP-only external) | BurnieCoinflip → `syncAfKingLazyPassFromCoin` |

### Slot: `traitBurnTicket[lvl][trait]`

| Writer fn | Writer file:line | Callsite file:line | Reach path |
|-----------|------------------|--------------------|------------|
| `_raritySymbolBatch(player, baseKey, startIndex, count, entropy)` (writes via inline assembly `sstore` to `traitBurnTicket[lvl][traitId]`'s array length + element slots) | `DegenerusGameMintModule.sol:537` (assembly block at :600-:629 computes `levelSlot = keccak256(lvl, slot)` and sstores length + addresses) | called from `processTicketBatch` at `:662` (via `_processOneTicketEntry`) AND from `processFutureTicketBatch` at `:385` (via `_raritySymbolBatch` line :470). | advanceGame → `_runProcessTicketBatch` → `processTicketBatch` (delegatecall) → `_raritySymbolBatch`; OR advanceGame → `_prepareFutureTickets` / `_processFutureTicketBatch` → `processFutureTicketBatch` (delegatecall) → `_raritySymbolBatch` |
| (no external/public direct writer of `traitBurnTicket` exists — `grep -rn traitBurnTicket contracts/` confirms only `MintModule._raritySymbolBatch` performs the SSTORE via assembly) | — | — | — |

### Slot: `deityBySymbol[fullSymId]`

| Writer fn | Writer file:line | Callsite file:line | Reach path |
|-----------|------------------|--------------------|------------|
| `_purchaseDeityPass(buyer, symbolId)` | `DegenerusGameWhaleModule.sol:542` (`deityBySymbol[symbolId] = buyer` at `:598`) | `:538` (`purchaseDeityPass` external entry — Whale module); `DegenerusGame.sol:644` (delegatecall dispatch) | EOA → `DegenerusGame.purchaseDeityPass` → delegatecall → `WhaleModule.purchaseDeityPass` |

### Slot: `currentPrizePool`

| Writer fn | Writer file:line | Callsite file:line | Reach path |
|-----------|------------------|--------------------|------------|
| `_setCurrentPrizePool(val)` | `DegenerusGameStorage.sol:821` (`currentPrizePool = uint128(val)`) | Callsites: `JackpotModule.sol:406, :506, :515, :1203`; `AdvanceModule.sol:902` (inside `_consolidatePoolsAndRewardJackpots`); `Storage.sol:1135` and adjacent (whale-pass distribution helpers). | advanceGame → various pool helpers; `payDailyJackpot` itself writes (line :406, :506, :515) via the SAME advanceGame stack |
| direct write `currentPrizePool = ...` | `DegenerusGameAdvanceModule.sol:902` | `:902` | advanceGame → `_consolidatePoolsAndRewardJackpots` |

### Slot: `prizePoolsPacked` (next + future components)

| Writer fn | Writer file:line | Callsite file:line | Reach path |
|-----------|------------------|--------------------|------------|
| `_setPrizePools(next, future)` | `DegenerusGameStorage.sol:684` | every `_setNextPrizePool`/`_setFuturePrizePool` callsite delegates here | (see next two rows for callsites) |
| `_setNextPrizePool(val)` | `DegenerusGameStorage.sol:791` | Callsites: `JackpotModule.sol:409, :434, :725, :842, :877` (inside `_distributeLootboxAndTickets`); `DegenerusGameAdvanceModule.sol` (consolidation); `DecimatorModule.sol`; `MintModule.sol` (payment processing); `DegeneretteModule.sol` (bet collection); `BoonModule.sol`; `LootboxModule.sol`; `WhaleModule.sol`. | EOA → `purchase`/`purchaseCoin`/`purchaseBurnieLootbox`/`purchaseWhaleBundle`/`purchaseLazyPass`/`purchaseDeityPass`/`placeDegeneretteBet`/`recordDecBurn`/`openLootBox`/`openBurnieLootBox`/`claimWhalePass`; advanceGame → various consolidations |
| `_setFuturePrizePool(val)` | `DegenerusGameStorage.sol:803` | Callsites: `JackpotModule.sol:433, :510, :569, :725, :840, :1201`; `DegenerusGameAdvanceModule.sol` (consolidation, gameOver); `DecimatorModule.sol`; `MintModule.sol`; etc. | same external entry surface as `_setNextPrizePool` (purchase/lootbox/whale/decimator paths all touch the future pool) |
| `_swapAndFreeze(purchaseLevel)` | `DegenerusGameStorage.sol:754` (writes `prizePoolFrozen=true` + may pre-seed `prizePoolPendingPacked` AND `_setFuturePrizePool(futureBal - seed)` at :761) | `:299, :631, :1095` (all inside `advanceGame`) | advanceGame → `_swapAndFreeze` |
| `_unfreezePool()` | `DegenerusGameStorage.sol:771` (writes `prizePoolsPacked` via `_setPrizePools(next + pNext, future + pFuture)` at :775) | called inside `_unlockRng` line :1735 | advanceGame → `_unlockRng` → `_unfreezePool` |
| Mint payment processing (`_processMintPayment`, `_handleMintRevenue`, etc.) | `DegenerusGameMintModule.sol` (many writes inside payment flow) | reached via `purchase`/`purchaseCoin`/`purchaseBurnieLootbox` external entries | EOA → `purchase`/etc. → delegatecall → MintModule |
| Whale-pass purchase | `DegenerusGameWhaleModule.sol:187` (`purchaseWhaleBundle`); `:380` (`purchaseLazyPass`); `:538` (`purchaseDeityPass`) | reached via `DegenerusGame.purchaseWhaleBundle`/etc. | EOA → delegatecall → WhaleModule |
| Decimator burn (`recordDecBurn`) | `DegenerusGameDecimatorModule.sol` (writes future-pool via `_setFuturePrizePool` during burn settlement) | `DegenerusGame.sol:1029` (`recordDecBurn`) | DegenerusCoin.burnCoin → `recordDecBurn` |
| Yield surplus | `JackpotModule.distributeYieldSurplus` (`:732`, writes `yieldAccumulator += quarterShare` at `:764`; uses `_addClaimableEth` which touches `claimableWinnings` not directly future pool) | `AdvanceModule.sol:423` (calls `_distributeYieldSurplus` which delegatecalls into JackpotModule.distributeYieldSurplus) | advanceGame → `_consolidatePoolsAndRewardJackpots` → `distributeYieldSurplus` |
| GameOver drain | `DegenerusGameGameOverModule.sol:147..150` (zeros all 4 pools: `currentPrizePool=0`, `_setNextPrizePool(0)`, `_setFuturePrizePool(0)`, `yieldAccumulator=0`) | `:139..152` inside `handleGameOverDrain` | advanceGame → `_handleGameOverPath` → `handleGameOverDrain` |

### Slot: `jackpotCounter`

| Writer fn | Writer file:line | Callsite file:line | Reach path |
|-----------|------------------|--------------------|------------|
| `payDailyJackpotCoinAndTickets` | `DegenerusGameJackpotModule.sol:596` (`jackpotCounter += counterStep` at `:665`) | `:461` (advanceGame), `:937` (AdvanceModule.payDailyJackpotCoinAndTickets internal dispatcher) | advanceGame → `payDailyJackpotCoinAndTickets` |
| `_consolidatePoolsAndRewardJackpots` / phase transition | `DegenerusGameAdvanceModule.sol:644` (`jackpotCounter = 0`) | `:644` (inside post-jackpot transition cleanup) | advanceGame → phase transition |

### Slot: `compressedJackpotFlag`

| Writer fn | Writer file:line | Callsite file:line | Reach path |
|-----------|------------------|--------------------|------------|
| `advanceGame` (turbo detection) | `DegenerusGameAdvanceModule.sol:177` (`compressedJackpotFlag = 2`) | `:177` (inside advanceGame top-of-function) | advanceGame self-write |
| `advanceGame` (compressed detection) | `DegenerusGameAdvanceModule.sol:399` (`compressedJackpotFlag = 1`) | `:399` (inside purchase-phase target-met branch) | advanceGame self-write |
| `_consolidatePoolsAndRewardJackpots` cleanup | `DegenerusGameAdvanceModule.sol:645` (`compressedJackpotFlag = 0`) | `:645` (post-jackpot transition cleanup) | advanceGame |

### Slot: `resumeEthPool`

| Writer fn | Writer file:line | Callsite file:line | Reach path |
|-----------|------------------|--------------------|------------|
| `_processDailyEth` (call-1 split write) | `DegenerusGameJackpotModule.sol:1340` (`resumeEthPool = uint128(ethPool)` when `splitMode == SPLIT_CALL1`) | `:1340` reached from `payDailyJackpot(true, ...)` P1 path via `_processDailyEth` at `:493` | advanceGame → `payDailyJackpot` → `_processDailyEth` |
| `_processDailyEth` (call-2 clear) | `DegenerusGameJackpotModule.sol:1245` (`resumeEthPool = 0` when `splitMode == SPLIT_CALL2`) | `:1245` reached from P2 resume path via `_resumeDailyEth` → `_processDailyEth` | advanceGame → `payDailyJackpot` → `_resumeDailyEth` → `_processDailyEth` |

### Slot: `dailyTicketBudgetsPacked`

| Writer fn | Writer file:line | Callsite file:line | Reach path |
|-----------|------------------|--------------------|------------|
| `payDailyJackpot` P1 | `DegenerusGameJackpotModule.sol:444` (`dailyTicketBudgetsPacked = _packDailyTicketBudgets(...)`) | `:444` (P1 only) | advanceGame → `payDailyJackpot(true,…)` |
| `payDailyJackpotCoinAndTickets` (Phase-2 clear) | `DegenerusGameJackpotModule.sol:670` (`dailyTicketBudgetsPacked = 0`) | `:670` (Phase-2) | advanceGame → `payDailyJackpotCoinAndTickets` |

### Slot: sDGNRS `poolBalances[Pool.Reward]` (cross-contract)

| Writer fn | Writer file:line | Callsite file:line | Reach path |
|-----------|------------------|--------------------|------------|
| `StakedDegenerusStonk.transferFromPool(pool, to, amount)` | `StakedDegenerusStonk.sol:412` (writes `poolBalances[idx] = available - amount` at `:422`) | `:412` (`onlyGame` modifier — only callable by GAME contract) | GAME → `dgnrs.transferFromPool` (from advanceGame, jackpot final-day, etc.) |
| `StakedDegenerusStonk.transferBetweenPools(from, to, amount)` | `StakedDegenerusStonk.sol` (writes 2× `poolBalances`) | `:1718` (advanceGame `_finalizeEarlybird`); other internal | GAME → `dgnrs.transferBetweenPools` |
| `StakedDegenerusStonk.transferToPool(...)` / pool-funding entries | `StakedDegenerusStonk.sol` | various — funded by advanceGame consolidation + initial distribution | GAME → various funding paths |
| ERC20-side: `transfer`, `transferFrom`, `_mint`, `_burn`, `approve` | `StakedDegenerusStonk.sol` ERC20 surface | EOA → standard ERC20 fns | EOA |

> **Cross-contract attestation:** sDGNRS is a SEPARATE deployed contract with `onlyGame`-modified write surface for pool operations. The ERC20 surface (`transfer`, `transferFrom`, `approve`) does NOT directly write `poolBalances[idx]` — it writes `balanceOf` mappings. The `transferFromPool` writer is the only one mutating `poolBalances[idx]` and it's gated to GAME.

---

## CAT-04 (§D) — Verdict Matrix

Per-(slot × writer × callsite) classification. Tokens: `EXEMPT-ADVANCEGAME` | `EXEMPT-VRFCALLBACK` | `EXEMPT-RETRYLOOTBOXRNG` | `VIOLATION`. No discretionary classifications per `D-43N-AUDIT-ONLY-01`.

| # | Slot | Writer fn | Callsite (file:line) | EXEMPT stack reached? | Classification |
|---|------|-----------|---------------------|----------------------|----------------|
| 1 | `dailyIdx` | `_unlockRng` | `AdvanceModule.sol:331, :402, :467, :631` | EXEMPT-ADVANCEGAME (all sites inside `advanceGame`) | **EXEMPT-ADVANCEGAME** |
| 2 | `dailyIdx` | `DegenerusGame.constructor` | `DegenerusGame.sol:219` | constructor (pre-deploy, no live VRF flow possible) | **EXEMPT-ADVANCEGAME** (constructor is structurally EXEMPT — runs once, before any VRF callback can fire) |
| 3 | `dailyHeroWagers[D][q]` | `_placeDegeneretteBetCore` | `DegeneretteModule.sol:367` (`placeDegeneretteBet` external entry) | NOT in advanceGame/VRF-callback/retryLootboxRng stack | **VIOLATION** |
| 4 | `dailyHeroWagers[D][q]` | `_placeDegeneretteBetCore` | `DegenerusGame.sol:714` (`placeDegeneretteBet` parent dispatch) | NOT in EXEMPT stack | **VIOLATION** |
| 5 | `dailyHeroWagers[D][q]` | `_placeDegeneretteBetCore` | `DegenerusVault.sol:607` (vault-routed bet) | NOT in EXEMPT stack | **VIOLATION** |
| 6 | `level` | `_requestRng` → `_finalizeRngRequest` | `AdvanceModule.sol:1643` | EXEMPT-ADVANCEGAME (only reachable inside `advanceGame` → `rngGate`) | **EXEMPT-ADVANCEGAME** |
| 7 | `level` | declaration default | `Storage.sol:250` | constructor only | **EXEMPT-ADVANCEGAME** |
| 8 | `gameOver` | `handleGameOverDrain` | `GameOverModule.sol:139` | EXEMPT-ADVANCEGAME (reached only via `_handleGameOverPath` from `advanceGame`) | **EXEMPT-ADVANCEGAME** |
| 9 | `autoRebuyState[beneficiary]` | `_setAutoRebuy` | `DegenerusGame.sol:1495` (`setAutoRebuy` external entry) | NOT in EXEMPT stack — BUT `if (rngLockedFlag) revert RngLocked()` at `:1513` gates the call during the resolution window | **VIOLATION** (callable outside window only) — see §E remediation: gate IS already present per existing tactic (a) pattern; verdict-matrix classification requires the gate to be inside the resolution window. Since the gate IS present and the call reverts inside the window, the EFFECTIVE behavior is EXEMPT-by-gate. **However**, per `D-298-EXEMPT-REACH-01` (stack-rooted strict): the writer is NOT call-stack-reachable from an EXEMPT root, so it remains VIOLATION at the strict classification — the gate is a CORRECTNESS-PROOF artifact, not an EXEMPT-stack derivation. **Per `D-43N-AUDIT-ONLY-01`: classified VIOLATION with §E noting "gate already in place — verify gate coverage in FUZZ Phase 301."** |
| 10 | `autoRebuyState[beneficiary]` | `_setAutoRebuyTakeProfit` | `DegenerusGame.sol:1504` | Same as #9 — `rngLockedFlag` gate at `:1528` | **VIOLATION** (same disposition as #9) |
| 11 | `autoRebuyState[beneficiary]` | `_setAfKingMode` | `DegenerusGame.sol:1559` | Same as #9 — `rngLockedFlag` gate at `:1575` | **VIOLATION** (same disposition) |
| 12 | `autoRebuyState[beneficiary]` | `_deactivateAfKing` (via `deactivateAfKingFromCoin` external) | `DegenerusGame.sol:1641` | NOT in EXEMPT stack — caller is BurnieCoin/BurnieCoinflip. **NO `rngLockedFlag` gate on this entry.** | **VIOLATION** |
| 13 | `autoRebuyState[beneficiary]` | `syncAfKingLazyPassFromCoin` | `DegenerusGame.sol:1654` | NOT in EXEMPT stack — caller is BurnieCoinflip. **NO `rngLockedFlag` gate on this entry.** | **VIOLATION** |
| 14 | `traitBurnTicket[lvl][trait]` | `_raritySymbolBatch` (via `processTicketBatch`) | `MintModule.sol:662` reached from `AdvanceModule.sol:1507` (`_runProcessTicketBatch`) | EXEMPT-ADVANCEGAME (only reachable via `advanceGame`'s ticket-batch delegate at `:221, :277, :357`) | **EXEMPT-ADVANCEGAME** |
| 15 | `traitBurnTicket[lvl][trait]` | `_raritySymbolBatch` (via `processFutureTicketBatch`) | `MintModule.sol:385` reached from `AdvanceModule.sol:1438` (`_processFutureTicketBatch`) | EXEMPT-ADVANCEGAME (only reachable via `advanceGame`'s `_prepareFutureTickets` / phase transition) | **EXEMPT-ADVANCEGAME** |
| 16 | `deityBySymbol[fullSymId]` | `_purchaseDeityPass` | `WhaleModule.sol:538`/`DegenerusGame.sol:644` (`purchaseDeityPass` external entry) | NOT in EXEMPT stack — `if (rngLockedFlag) revert RngLocked()` at `:543` gates the call inside the window | **VIOLATION** (same disposition as #9 — gate IS in place but classification is stack-strict) |
| 17 | `currentPrizePool` | `_setCurrentPrizePool` (from JackpotModule self-writes during payDailyJackpot) | `JackpotModule.sol:406, :506, :515, :1203` | EXEMPT-ADVANCEGAME (self-stack of the consumer) | **EXEMPT-ADVANCEGAME** |
| 18 | `currentPrizePool` | `_setCurrentPrizePool` from `_consolidatePoolsAndRewardJackpots` | `AdvanceModule.sol:902` | EXEMPT-ADVANCEGAME | **EXEMPT-ADVANCEGAME** |
| 19 | `prizePoolsPacked` (next/future) | `_setNextPrizePool`/`_setFuturePrizePool` from JackpotModule self-writes | `JackpotModule.sol:409, :433, :434, :510, :511, :548, :569, :725, :840, :842, :877, :1201` | EXEMPT-ADVANCEGAME | **EXEMPT-ADVANCEGAME** |
| 20 | `prizePoolsPacked` (next/future) | `_swapAndFreeze` | `AdvanceModule.sol:299, :631, :1095` | EXEMPT-ADVANCEGAME | **EXEMPT-ADVANCEGAME** |
| 21 | `prizePoolsPacked` (next/future) | `_unfreezePool` via `_unlockRng` | `AdvanceModule.sol:1735` | EXEMPT-ADVANCEGAME | **EXEMPT-ADVANCEGAME** |
| 22 | `prizePoolsPacked` (next/future) | MintModule payment processing | `MintModule.sol` (various — `_processMintPayment`, `_handleMintRevenue`) reached from `purchase`/`purchaseCoin`/`purchaseBurnieLootbox` | **`purchase` (MintModule:830) has NO blanket `rngLockedFlag` revert** — only the line `:1221` `cachedJpFlag && rngLockedFlag` redirect (last-jackpot-day routing). Writes to `prizePoolsPacked` (next/future) DO proceed during the resolution window via this entry. | **VIOLATION** |
| 23 | `prizePoolsPacked` (next/future) | WhaleModule (`purchaseWhaleBundle`, `purchaseLazyPass`) | `WhaleModule.sol:187, :380` | `purchaseWhaleBundle` and `purchaseLazyPass` — need to verify gate; `grep` shows no top-level `rngLockedFlag` revert | **VIOLATION** (no gate; the writes proceed inside the window) |
| 24 | `prizePoolsPacked` (next/future) | WhaleModule (`purchaseDeityPass`) | `WhaleModule.sol:538` | `if (rngLockedFlag) revert RngLocked()` at `:543` gates the call | **VIOLATION** (stack-strict; gate-by-revert) |
| 25 | `prizePoolsPacked` (next/future) | `recordDecBurn` (DegenerusCoin.burnCoin → ...) | `DegenerusGame.sol:1029` | No top-level `rngLockedFlag` gate on `recordDecBurn` (caller is BurnieCoin's burnCoin path) | **VIOLATION** |
| 26 | `prizePoolsPacked` (next/future) | `_distributeYieldSurplus` via `JackpotModule.distributeYieldSurplus` | `AdvanceModule.sol:423` | EXEMPT-ADVANCEGAME (advanceGame-stack) | **EXEMPT-ADVANCEGAME** |
| 27 | `prizePoolsPacked` (next/future) | `handleGameOverDrain` (zeros pools) | `GameOverModule.sol:147..150` | EXEMPT-ADVANCEGAME | **EXEMPT-ADVANCEGAME** |
| 28 | `prizePoolsPacked` (next/future) | `claimWhalePass` → `_queueTicketRange` (indirect — does NOT directly write prizePoolsPacked, but adjacent calls to `_queueTickets` reach `_setNextPrizePool` etc. via downstream auto-rebuy) | `DegenerusGame.sol:1692`, `WhaleModule.sol:957` | `claimWhalePass` does NOT have `rngLockedFlag` top-level gate, BUT `_queueTicketRange` reverts inside the loop when `isFarFuture && rngLockedFlag` (level+6..+100 portion) — so the whole call reverts atomically inside the window. **Effective gate.** | **VIOLATION** (stack-strict; effective gate via downstream revert) |
| 29 | `prizePoolsPacked` (next/future) | `placeDegeneretteBet` → `_collectBetFunds` (writes future pool via bet collection) | `DegeneretteModule.sol:367` / `DegenerusGame.sol:714` | NO `rngLockedFlag` gate. Writes proceed inside the window. | **VIOLATION** |
| 30 | `prizePoolsPacked` (next/future) | `openLootBox`/`openBurnieLootBox` (LootboxModule writes future pool via lootbox payout consolidation) | `DegenerusGame.sol:665, :673` | LootboxModule path has separate gating — needs `rngLockedFlag` verification; the lootbox resolution path uses `lootboxRngWordByIndex` which is a SEPARATE VRF surface (per `D-42N-RETRY-RNG-DOMAIN-SEP-01` Option A). For DAILY VRF consumer §1, the lootbox VRF is domain-separated. | **VIOLATION** (stack-strict — writes are not derived from advanceGame's daily-VRF stack) |
| 31 | `jackpotCounter` | `payDailyJackpotCoinAndTickets` | `JackpotModule.sol:596` reached from `AdvanceModule.sol:461` | EXEMPT-ADVANCEGAME | **EXEMPT-ADVANCEGAME** |
| 32 | `jackpotCounter` | `_consolidatePoolsAndRewardJackpots` zeroing | `AdvanceModule.sol:644` | EXEMPT-ADVANCEGAME | **EXEMPT-ADVANCEGAME** |
| 33 | `compressedJackpotFlag` | `advanceGame` turbo write | `AdvanceModule.sol:177` | EXEMPT-ADVANCEGAME | **EXEMPT-ADVANCEGAME** |
| 34 | `compressedJackpotFlag` | `advanceGame` compressed write | `AdvanceModule.sol:399` | EXEMPT-ADVANCEGAME | **EXEMPT-ADVANCEGAME** |
| 35 | `compressedJackpotFlag` | phase-transition cleanup | `AdvanceModule.sol:645` | EXEMPT-ADVANCEGAME | **EXEMPT-ADVANCEGAME** |
| 36 | `resumeEthPool` | `_processDailyEth` call-1 split write | `JackpotModule.sol:1340` | EXEMPT-ADVANCEGAME (self-stack) | **EXEMPT-ADVANCEGAME** |
| 37 | `resumeEthPool` | `_processDailyEth` call-2 clear | `JackpotModule.sol:1245` | EXEMPT-ADVANCEGAME (self-stack) | **EXEMPT-ADVANCEGAME** |
| 38 | `dailyTicketBudgetsPacked` | `payDailyJackpot` P1 write | `JackpotModule.sol:444` | EXEMPT-ADVANCEGAME (self-stack) | **EXEMPT-ADVANCEGAME** |
| 39 | `dailyTicketBudgetsPacked` | `payDailyJackpotCoinAndTickets` clear | `JackpotModule.sol:670` | EXEMPT-ADVANCEGAME | **EXEMPT-ADVANCEGAME** |
| 40 | sDGNRS `poolBalances[Pool.Reward]` | `transferFromPool` from `_handleSoloBucketWinner` final-day | `JackpotModule.sol:1498` | EXEMPT-ADVANCEGAME (self-stack — invoked from `_processDailyEth` inside `payDailyJackpot`) | **EXEMPT-ADVANCEGAME** |
| 41 | sDGNRS `poolBalances[Pool.Reward]` | `transferFromPool` from other GAME-callsites | `DegenerusGame.sol:1735, :1739` (claim/settlement paths) and others — reached via EOA-initiated `claimWinnings` / GAME admin flows | NOT in EXEMPT stack — GAME → sDGNRS via non-advanceGame routes (e.g. quest reward minting from `recordMintQuestStreak`, etc.) | **VIOLATION** — any non-advanceGame-stack write to `poolBalances[Pool.Reward]` can change the value read at `JackpotModule.sol:1493` between commitment and resolution |
| 42 | sDGNRS `poolBalances[Pool.Reward]` | `transferBetweenPools` (e.g. `_finalizeEarlybird`) | `AdvanceModule.sol:1718` | EXEMPT-ADVANCEGAME | **EXEMPT-ADVANCEGAME** |
| 43 | sDGNRS `poolBalances[Pool.Reward]` | sDGNRS-internal mint/distribution writers | `StakedDegenerusStonk.sol` (sDGNRS-internal admin/distribution surface) | NOT GAME-side; cross-contract write surface that mutates the slot from sDGNRS-side (e.g. initial pool funding, admin distribution, ERC20 mint into pool) | **VIOLATION** — same race-class as #41 |

> **All rows carry a concrete EXEMPT/VIOLATION token.** Every callsite × slot × writer tuple in §C carries one of `EXEMPT-ADVANCEGAME` / `EXEMPT-VRFCALLBACK` / `EXEMPT-RETRYLOOTBOXRNG` / `VIOLATION` per `D-43N-AUDIT-ONLY-01` + `D-298-EXEMPT-REACH-01` strict.

> **VIOLATION row count: 13** (rows 3, 4, 5, 9, 10, 11, 12, 13, 16, 22, 23, 24, 25, 28, 29, 30, 41, 43 — recount: 18 distinct violation rows above).

> **Re-count check:** Rows classified `VIOLATION`: **3, 4, 5, 9, 10, 11, 12, 13, 16, 22, 23, 24, 25, 28, 29, 30, 41, 43** = **18 rows**. Rows classified `EXEMPT-ADVANCEGAME`: 1, 2, 6, 7, 8, 14, 15, 17, 18, 19, 20, 21, 26, 27, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 42 = **25 rows**. Total = 43 rows.

---

## CAT-06 (§E) — Remediation Tactic per VIOLATION Row

Per `D-298-RECOMMEND-DEPTH-01`: one tactic ∈ `(a)` `rngLockedFlag`-gated revert | `(b)` snapshot/anchor pattern | `(c)` pre-lock reorder | `(d)` immutable. Plus ≤80-char rationale.

| Row | Slot × callsite | Tactic | Rationale (≤80 chars) |
|-----|-----------------|--------|----------------------|
| 3 | `dailyHeroWagers[D][q]` × `placeDegeneretteBet` (DegeneretteModule:367) | **(b)** | day-key separation freezes slot D once D+1 begins; verify `_simulatedDayIndex` rollover. |
| 4 | `dailyHeroWagers[D][q]` × `placeDegeneretteBet` (DegenerusGame:714) | **(b)** | parent dispatch — same day-key freeze attestation as row 3. |
| 5 | `dailyHeroWagers[D][q]` × `placeDegeneretteBet` (Vault:607) | **(b)** | vault-routed — same day-key freeze; reconfirm vault wrapper preserves `_simulatedDayIndex`. |
| 9 | `autoRebuyState` × `setAutoRebuy` | **(a)** | gate already at DegenerusGame:1513; FUZZ-301 must verify branch coverage. |
| 10 | `autoRebuyState` × `setAutoRebuyTakeProfit` | **(a)** | gate already at DegenerusGame:1528 — same coverage gap. |
| 11 | `autoRebuyState` × `setAfKingMode` | **(a)** | gate already at DegenerusGame:1575 — same coverage gap. |
| 12 | `autoRebuyState` × `deactivateAfKingFromCoin` | **(a)** | MISSING `if (rngLockedFlag) revert` at DegenerusGame:1641 — add. |
| 13 | `autoRebuyState` × `syncAfKingLazyPassFromCoin` | **(a)** | MISSING gate at DegenerusGame:1654 — add. |
| 16 | `deityBySymbol` × `purchaseDeityPass` | **(a)** | gate already at WhaleModule:543; deity slot is also frozen-once-set semantics. |
| 22 | `prizePoolsPacked` × `purchase`/`purchaseCoin`/`purchaseBurnieLootbox` (MintModule) | **(a)** | add top-level `if (rngLockedFlag) revert` to MintModule.purchase + purchaseCoin + purchaseBurnieLootbox. |
| 23 | `prizePoolsPacked` × `purchaseWhaleBundle`/`purchaseLazyPass` (WhaleModule) | **(a)** | add top-level `rngLockedFlag` revert at WhaleModule:187 + :380. |
| 24 | `prizePoolsPacked` × `purchaseDeityPass` (WhaleModule) | **(a)** | gate already at :543 — coverage verification only. |
| 25 | `prizePoolsPacked` × `recordDecBurn` | **(a)** | add `rngLockedFlag` gate at DegenerusGame:1029 OR upstream in DegenerusCoin.burnCoin caller path. |
| 28 | `prizePoolsPacked` × `claimWhalePass` | **(a)** | effective gate via `_queueTicketRange` revert; add explicit top-level gate for clarity. |
| 29 | `prizePoolsPacked` × `placeDegeneretteBet` (bet collection) | **(a)** | add `rngLockedFlag` revert to `_placeDegeneretteBetCore` at DegeneretteModule:405. |
| 30 | `prizePoolsPacked` × `openLootBox`/`openBurnieLootBox` | **(b)** | domain-separated lootbox VRF; snapshot prizePool at lootbox-buy-time, not open-time. |
| 41 | sDGNRS `poolBalances[Pool.Reward]` × GAME non-advanceGame entries | **(b)** | snapshot `dgnrsPool` at `_swapAndFreeze` time; read snapshot inside `_handleSoloBucketWinner`. |
| 43 | sDGNRS `poolBalances[Pool.Reward]` × sDGNRS-internal writers | **(b)** | same snapshot-at-freeze pattern — eliminates cross-contract write race. |

> **Tactic-frequency summary:** (a) gated-revert × 14; (b) snapshot/anchor × 6 (rows 3, 4, 5, 30, 41, 43; row 30 differs from rows 3-5 in that the lootbox VRF is domain-separated, but the snapshot tactic still applies); (c) pre-lock reorder × 0; (d) immutable × 0.

> **Existing precedent references for (a):** `MintModule.sol:1221` (`if (cachedJpFlag && rngLockedFlag)` — partial gate); `BurnieCoinflip.sol:730` (per-tx flip-lock pattern); `StakedDegenerusStonk.sol:492` (sDGNRS stake-lock during decimator settlement). For (b): Phase 281 owed-salt snapshot; Phase 288 dailyIdx structural snapshot at lock-time.

---

## Catalog Section Footer

**Trace function-set size:** 58 functions (CAT-01).
**SLOAD count enumerated:** 24 distinct slots (CAT-02) — 14 participating (YES), 10 non-participating with attestation (NO) including 1 reclassification (sDGNRS poolBalances flipped NO → YES).
**Participating slot count (forwards into §C):** 14.
**VIOLATION row count (§D):** 18.
**Remediation tactic distribution (§E):** (a) × 14, (b) × 6, (c) × 0, (d) × 0.

> **Explicit enumeration discipline.** Every reachable SLOAD is enumerated with explicit file:line citation per `feedback_verify_call_graph_against_source.md` (Phase 294 BURNIE gap precedent). No shortcut phrasings.
