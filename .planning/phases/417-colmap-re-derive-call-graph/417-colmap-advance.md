# Column Map — Slice: AdvanceModule (`DegenerusGameAdvanceModule`)

Subject: frozen `contracts/` tree `0dd445a6`. File:
`contracts/modules/DegenerusGameAdvanceModule.sol` (1929 lines).

Execution context: the module is reached **via DELEGATECALL** from `DegenerusGame`
(the column entrypoint `mintFlip`/`advanceGame` self-dispatch). Therefore EVERY
storage write below lands in **GAME storage slots**, and every `delegatecall` this
module issues is a **NESTED delegatecall** (delegatecall-within-delegatecall:
Game → AdvanceModule → {target module}). The target module runs in Game storage too.

Storage-helper bodies live in `contracts/storage/DegenerusGameStorage.sol`
(`_setPrizePools`, `_swapTicketSlot`, `_unfreezePool`, `_queueTickets`,
`_setLevelDgnrsAllocation`, `_psWrite`, `_lrWrite`, `_lrAdvanceIndexClearPending`,
`_livenessTriggered`, `_simulatedDayIndexAt`, `_goRead`/`_goWrite`). Their writes
are attributed to the calling site here.

External (NON-delegate) synchronous handles (constants in storage):
`coinflip` (ICoinflip), `quests` (IDegenerusQuests), `affiliate` (IDegenerusAffiliate),
`dgnrs` (IsDGNRS), `jackpots` (IDegenerusJackpots), `steth` (IStETH),
`charityResolve` (IGNRUSResolve / GNRUS), `vrfCoordinator` (IVRFCoordinator),
plus `IsDGNRS(SDGNRS)` (sDGNRS redemption) and `IDegenerusGame(address(this))`
**self-calls** (re-enter Game CALL, which then delegatecalls the jackpot/BAF/decimator module).

---

## 1. CALL GRAPH (column-reachable functions)

### `advanceGame()` (external, the column tick) — L168
Internal calls:
- `_simulatedDayIndexAt(ts)` L171 (→ GameTimeLib.currentDayIndexAt)
- `_getNextPrizePool()` L200, L489
- `_handleGameOverPath(day, lvl)` L210
- `_tqReadKey` L233, `_tqWriteKey` (via swap)
- `_runProcessTicketBatch(purchaseLevel)` L238, L292, L449 (NESTED delegatecall inside)
- `_lrWrite(LR_MID_DAY…,0)` L242, `_lrRead` L226/L279
- `lootboxRngWordByIndex[…]` direct read/write L227/L281/L289
- `_runSubscriberStage(day)` L330 (NESTED delegatecall inside)
- `rngGate(...)` L374 (NESTED delegatecalls + external coinflip/quests/sDGNRS inside)
- `_swapAndFreeze(purchaseLevel)` L383 (→ `_swapTicketSlot` + freeze)
- `_processPhaseTransition(purchaseLevel)` L411 (→ `_queueTickets` ×2 + `_autoStakeExcessEth`)
- `_processFutureTicketBatch(ffLevel|nextLevel, rngWord)` L416, L509 (NESTED delegatecall inside)
- `_unlockRng(day)` L425, L497, L555 (emits snapshot; external `steth.balanceOf`)
- `_prepareFutureTickets(...)` L435 (loops → NESTED delegatecall inside)
- `IDegenerusGame(address(this)).emitDailyWinningTraits(...)` L468 — **self-CALL → Game → delegatecall JackpotModule**
- `_payDailyCoinJackpot(...)` L473, L479, L482 (NESTED delegatecall JackpotModule)
- `payDailyJackpot(...)` L481, L561 (NESTED delegatecall JackpotModule)
- `_distributeYieldSurplus(rngWord)` L518 (NESTED delegatecall JackpotModule)
- `_consolidatePoolsAndRewardJackpots(...)` L519 (external `dgnrs`, `coinflip`, `jackpots`; self-CALL BAF/Decimator)
- `_psRead`/`_psWrite` L527/L528
- `quests.rollLevelQuest(rngWord)` L537 — **external CALL to quests**
- `payDailyJackpotCoinAndTickets(rngWord)` L549 (NESTED delegatecall JackpotModule)
- `_endPhase(lvl)` L551

### `_handleGameOverPath(day, lvl)` (private) — L605
- `_livenessTriggered()` L630, `_getNextPrizePool()` L633
- `GAME_GAMEOVER_MODULE.delegatecall(handleFinalSweep)` L621 — **NESTED delegatecall**
- `_gameOverEntropy(...)` L639 (external coinflip/sDGNRS inside; may request VRF)
- `GAME_MINT_MODULE.delegatecall(processTicketBatch, lvl+1)` L664 — **NESTED delegatecall (revert SWALLOWED on `!dOk`)**
- `_swapTicketSlot(lvl+1)` L683
- `GAME_GAMEOVER_MODULE.delegatecall(handleGameOverDrain, day)` L692 — **NESTED delegatecall**
- `_unlockRng(day)` L699

### `rngGate(ts,day,lvl,isTicketJackpotDay,coinflipBonus)` (internal) — L1195
- `_backfillGapDays(currentWord, idx+1, day)` L1220 (LOOP; external coinflip per gap day)
- `_backfillOrphanedLootboxIndices(currentWord)` L1224 (LOOP)
- `_applyDailyRng(day, currentWord)` L1233
- `coinflip.processCoinflipPayouts(coinflipBonus, currentWord, day)` L1234 — **external CALL coinflip**
- `quests.rollDailyQuest(...)` L1239 — **external CALL quests**
- `IsDGNRS(SDGNRS).pendingResolveDay()` L1253 / `.resolveRedemptionPeriod(...)` L1258 — **external CALL sDGNRS**
- `_finalizeLootboxRng(currentWord)` L1262
- `_requestRng(isTicketJackpotDay, lvl)` L1270, L1277 (→ VRF request, sets lock)

### `_gameOverEntropy(...)` (private) — L1293
- `_applyDailyRng` L1303/L1338
- `coinflip.processCoinflipPayouts(0,...)` L1306/L1341 — **external CALL coinflip**
- `IsDGNRS(SDGNRS).pendingResolveDay/resolveRedemptionPeriod` L1315/L1320, L1350/L1355 — **external CALL sDGNRS**
- `_getHistoricalRngFallback(day)` L1331 (LOOP)
- `_finalizeLootboxRng` L1323/L1358
- `_tryRequestRng(isTicketJackpotDay, lvl)` L1367 (try/catch VRF)

### `_consolidatePoolsAndRewardJackpots(...)` (private) — L822
- `_getPrizePools`/`_getCurrentPrizePool`/`_getFuturePrizePool`
- `_nextToFutureBps(elapsed, purchaseLevel)` L840
- `EntropyLib.hash2(...)` L958 (pure lib)
- `IDegenerusGame(address(this)).runBafJackpot(...)` L926 — **self-CALL → Game → delegatecall (BAF)**
- `jackpots.markBafSkipped(lvl)` L934 — **external CALL jackpots**
- `IDegenerusGame(address(this)).runDecimatorJackpot(...)` L948 — **self-CALL → Game → delegatecall (Decimator)**
- `coinflip.creditFlip(SDGNRS, …)` L984 — **external CALL coinflip**
- `_setPrizePools`/`currentPrizePool=`/`yieldAccumulator=`/`claimablePool+=` L998-1003

### `requestLootboxRng()` (external, standalone — NOT on advance tick) — L1079
- `vrfCoordinator.getSubscription(...)` L1095 — **external CALL VRF**
- `PriceLookupLib.priceForLevel` (pure), `_swapTicketSlot` L1131, `_lrWrite` L1132
- `_requestVrfWord(VRF_MIDDAY_CONFIRMATIONS)` L1137 (external VRF request)
- `_lrAdvanceIndexClearPending()` L1140

### `retryLootboxRng()` (external, standalone) — L1153
- `vrfCoordinator.getSubscription` L1162, `_requestVrfWord` L1167

### `rawFulfillRandomWords(requestId, randomWords)` (external, VRF callback) — L1828
- `_lrRead` L1843, `lootboxRngWordByIndex[index]=word` L1844

### Admin VRF (deploy/governance only — NOT column): `wireVrf` L583, `updateVrfCoordinatorAndSub` L1755 — `_setVrfConfig`, `_requestVrfWord`.

### Helpers issuing NESTED delegatecalls
`_runProcessTicketBatch` L1539, `_processFutureTicketBatch` L1470, `_prepareFutureTickets` L1495 (loops),
`_runSubscriberStage` L796, `_distributeYieldSurplus` L772, `payDailyJackpot` L1012,
`payDailyJackpotCoinAndTickets` L1034, `_payDailyCoinJackpot` L1055. All bubble via `_revertDelegate`.

---

## 2. REVERT-SITE INVENTORY

| fn:line | trigger | error | class |
|---|---|---|---|
| advanceGame:230 | mid-day ticket swap pending but lootbox word not delivered | `RngNotReady()` | TRANSIENT (clears when VRF delivers; mid-day path) |
| advanceGame:251 | new day not reached AND read slot already drained | `NotTimeYet()` | TRANSIENT (time-gated; intended idle) |
| advanceGame:283 | daily drain gate: lootbox word empty AND `rngWordCurrent==0` | `RngNotReady()` | **PERMANENT-CANDIDATE** — pre-RNG drain gate; if VRF never delivers AND queue is non-empty, advance cannot pass here until VRF recovers (covered by 12h/14d timeouts in rngGate/gameOver, not here) |
| rngGate:1273 | VRF pending, elapsed < 12h | `RngNotReady()` | TRANSIENT (12h timeout then `_requestRng`) |
| `_gameOverEntropy`:1364 | VRF pending, elapsed < `GAMEOVER_RNG_FALLBACK_DELAY` (14d) | `RngNotReady()` | TRANSIENT (after 14d → historical fallback word, no revert) |
| `_processFutureTicketBatch`:1484 | delegate returned empty data | `E()` | **PERMANENT-CANDIDATE** — if MintModule ever returns 0-len on this selector, every advance that reaches FF processing wedges; also bubbles any inner MintModule revert (L1483) |
| `_runProcessTicketBatch`:1553 | delegate returned empty data | `E()` | **PERMANENT-CANDIDATE** — same shape; reached on the daily ticket-drain gate that every new-day advance crosses |
| `_revertDelegate`:813 | delegate revert with empty reason | `E()` | depends on callee — see §callee risks; bubbles real reason at L815 |
| `_swapTicketSlot`:798 (storage) | read slot length != 0 at swap | `E()` | TRANSIENT-ish — only called after the read slot is asserted empty by callers; a stale non-empty read slot at swap would revert that advance leg |
| `_queueTickets`:618 / `:621` (storage, via `_processPhaseTransition`) | `_livenessTriggered()` true / far-future while `rngLockedFlag` & `!rngBypass` | `E()` / `RngLocked()` | phase-transition calls pass `rngBypass=true`; liveness-true at a phase transition would block the perpetual-ticket queue, but `_livenessTriggered()` returns false while `jackpotPhaseFlag`/`lastPurchaseDay` and a phase transition runs with the day already in jackpot housekeeping — low wedge risk |
| requestLootboxRng:1080/1083/1088/1090/1092/1098/1110/1123 | locked / mid-day / pre-reset window / no daily word / request in flight / low LINK / no pending / below threshold | `RngLocked()` / `E()` | TRANSIENT — standalone fast path, never on advance tick; failure here does not block advanceGame |
| retryLootboxRng:1157/1158/1159/1160/1165 | locked / no mid-day / no request / before retry timeout / low LINK | `RngLocked()` / `E()` | TRANSIENT — standalone |
| rawFulfillRandomWords:1832 | caller != vrfCoordinator | `E()` | TRANSIENT (access guard); mismatched requestId silently returns (L1833) — no revert |
| wireVrf:588 / updateVrfCoordinatorAndSub:1760 | caller != ADMIN | `E()` | TRANSIENT (access; off-column) |
| Checked arithmetic (implicit overflow/underflow reverts): | | | |
| `_consolidatePoolsAndRewardJackpots`:846 | `(memFuture*100)/memNext` — **division by zero if `memNext==0`** | Panic 0x12 | **PERMANENT-CANDIDATE** — runs on the lastPurchase level-transition leg; `memNext` is the `next` pool which is normally non-zero at transition, but a zeroed next pool would revert the transition and wedge level advance |
| `_consolidatePoolsAndRewardJackpots`:899 | `memNext -= take + insuranceSkim` underflow | Panic 0x11 | PERMANENT-CANDIDATE (take capped at 80% + 1% skim = 81% of memNext, so subtraction is bounded; underflow only if invariant broken) |
| `_consolidatePoolsAndRewardJackpots`:857 | `(memNext*10_000)/lastPool` div — guarded by `lastPool != 0` (L856) | n/a | guarded |
| `_consolidatePoolsAndRewardJackpots`:987 | `priceForLevel(purchaseLevel)*20` denom — pure lib, non-zero for valid levels | Panic 0x12 if zero | low risk |
| advanceGame:198 | `day - psd` (uint32) underflow if `psd > day` | Panic 0x11 | low — psd is `purchaseStartDay <= day` by construction |
| advanceGame:262 | `ts - dayStart` underflow | Panic 0x11 | low — new-day path guarantees ts past dayStart |
| `_unlockRng`:1815 (storage, snapshot) | `steth.balanceOf(address(this))` external read in emit args | revert bubbles | **PERMANENT-CANDIDATE if stETH reverts** — `_unlockRng` is the day-seal chokepoint every completed day crosses; a reverting `steth.balanceOf` would block the seal (see §callee risks) |

Custom errors are tiny: `E()` (inherited), `NotTimeYet()`, `RngNotReady()`, `RngLocked()` (inherited).

---

## 3. LOOP INVENTORY

| fn:line | iteration bound | per-iter storage/gas | class |
|---|---|---|---|
| `_getHistoricalRngFallback`:1394 | `searchDay` 1..`searchLimit` where `searchLimit = min(currentDay,30)`; early-break at `found==5` | reads `rngWordByDay[searchDay]` (SLOAD), `EntropyLib.hash2` | **BOUNDED** (≤30 SLOADs, ≤5 hashes) |
| `_prepareFutureTickets`:1513 | `target` `startLevel..endLevel` = `lvl+1..lvl+4` → fixed 4 iterations | each iter does a NESTED delegatecall `_processFutureTicketBatch` (one MintModule batch) | **BOUNDED** (≤4 delegatecalls; early-returns on `worked || !levelFinished`) |
| `_backfillGapDays`:1869 | `gapDay` `startDay..endDay`, capped to `startDay+120` (L1868) | per iter: `rngWordByDay[gapDay]=` SSTORE + **external `coinflip.processCoinflipPayouts`** + emit | **BOUNDED by 120** but input/state-sized up to 120; each iter makes an external coinflip call → 120× external calls in worst case (gas-heavy; decoupled from jackpot via STAGE_GAP_BACKFILLED) |
| `_backfillOrphanedLootboxIndices`:1894 | `i` from `idx-1` down to `1`, break on first filled index | per iter: `lootboxRngWordByIndex[i]=` SSTORE + emit | **UNBOUNDED / INPUT-SIZED** — bound = count of consecutive orphaned (empty) lootbox indices below `idx`; grows with number of un-fulfilled mid-day lootbox reservations accrued during a VRF stall. No explicit cap. |
| `_queueTicketRange` (storage):713 | `i` 0..`numLevels` | per iter ticket SSTOREs | BOUNDED by `numLevels` (off this slice's column path — whale-pass; not reached from advanceGame) |

NOTE: the heavy per-tx work in this slice is fanned across advance calls by the
partial-drain breaks (`STAGE_TICKETS_WORKING`, `STAGE_SUBS_WORKING`,
`STAGE_FUTURE_TICKETS_WORKING`, `STAGE_TRANSITION_WORKING`) and by the
`STAGE_GAP_BACKFILLED` / `STAGE_SUBS_BACKFILL_DEFERRED` decouples, so the gap
backfill (≤120) never shares a tx with the daily jackpot.

---

## 4. DELEGATECALL STORAGE-WRITE INVENTORY (Game slots written by this module)

Slot-0 packed fields (declared in `DegenerusGameStorage`, compiler-packed into slot 0
per the layout comment L47-66) — **packed-slot write hotspots**; a write to any one is a
read-modify-write of the shared slot-0 word:

| field (as declared) | written at | notes |
|---|---|---|
| `lastPurchaseDay` (bool) | advanceGame:202, 492, 534; `_handleGameOverPath` reads via `_livenessTriggered` | turbo set L202; target-met set L492; cleared at jackpot entry L534 |
| `compressedJackpotFlag` (uint8) | advanceGame:203, 494; `_endPhase`:713 (=0) | turbo=2 L203, compressed=1 L494 |
| `ticketsFullyProcessed` (bool) | advanceGame:241, 300, 456; `_handleGameOverPath`:685; `_swapTicketSlot`(=false):800 | drain-complete latch; co-packed |
| `jackpotPhaseFlag` (bool) | advanceGame:427(=false via transition), 532(=true) | phase flag |
| `phaseTransitionActive` (bool) | advanceGame:424(=false); `_endPhase`:707(=true) | transition latch |
| `ticketRedemptionOpen` (bool) | `_finalizeRngRequest`:1715(=false) | window close |
| `decWindowOpen` (bool) | `_finalizeRngRequest`:1733(=true)/1737(=false) | decimator window |
| `level` (uint24) | `_finalizeRngRequest`:1727 (`level = lvl`) | **level increment** at RNG request on lastPurchase |
| `purchaseStartDay` (uint24) | advanceGame:426 (`= day`); rngGate via `psd` not stored here but `_backfillGapDays` caller `purchaseStartDay += gapCount` L1228 | death-clock |
| `jackpotCounter` (uint8) | `_endPhase`:711 (=0) | reset at phase end |
| `rngLockedFlag` (bool) | `_finalizeRngRequest`:1696(=true); `_unlockRng`:1799(=false) | RNG lock |
| `ticketWriteSlot` (bool) | `_swapTicketSlot`:799 (negate) | double-buffer toggle |
| `subsFullyProcessed` (bool) | advanceGame:325(=false), 347/360(=true) | afking drain latch |
| `gameOver` (bool) | NOT written in this slice (set in GameOverModule) — read only | — |

Slot-1 packed (`currentPrizePool` uint128 + `claimablePool` uint128):
- `currentPrizePool = uint128(memCurrent)` — `_consolidatePoolsAndRewardJackpots`:999 (**packed slot-1 write**)
- `claimablePool += uint128(claimableDelta)` — `_consolidatePoolsAndRewardJackpots`:1002 (**packed slot-1 write**; aliases currentPrizePool slot)

Other Game-storage writes:
- `prizePoolsPacked` (next|future, 128/128 packed) — `_setPrizePools` from `_consolidatePoolsAndRewardJackpots`:998; `_swapAndFreeze`→`_setFuturePrizePool` (L816, storage); `_unfreezePool`:830 — **packed write keyed by next/future halves**
- `prizePoolPendingPacked` (next|future pending, packed) — `_setPendingPools` in `_swapAndFreeze`:817; cleared L819/`_unfreezePool`:831 — **packed**
- `prizePoolFrozen` (bool, own slot) — `_swapAndFreeze`:812(=true), `_unfreezePool`:832(=false)
- `yieldAccumulator` (uint256) — `_consolidatePoolsAndRewardJackpots`:1000
- `levelPrizePool[purchaseLevel]` (mapping) — advanceGame:517; `_endPhase`:709 (`levelPrizePool[lvl]` on x00)
- `levelDgnrsPacked[lvl]` (allocation half, packed 128/128) — `_setLevelDgnrsAllocation` from `_rewardTopAffiliate`:762 — **packed slot keyed by `lvl`, allocation half only**
- `dailyIdx` (uint24) — `_unlockRng`:1798
- `rngWordCurrent` (uint256) — `_applyDailyRng`:1923; `_unlockRng`:1800(=0); `requestLootboxRng`:1142; `_finalizeRngRequest`:1694; `_gameOverEntropy`:1372; `rawFulfillRandomWords`:1840
- `rngWordByDay[day]` (mapping) — `_applyDailyRng`:1924; `_backfillGapDays`:1874 (`rngWordByDay[gapDay]`) — **keyed by day**
- `rngRequestTime` (uint48) — `_finalizeRngRequest`:1695; `_unlockRng`:1802(=0); `requestLootboxRng`:1143; `retryLootboxRng`:1170; `_gameOverEntropy`:1361(=0)/1373; `updateVrfCoordinatorAndSub`:1773/1779
- `vrfRequestId` (uint256) — `_finalizeRngRequest`:1693; `_unlockRng`:1801(=0); `requestLootboxRng`:1141; `retryLootboxRng`:1169; `rawFulfillRandomWords`:1846(=0); `updateVrfCoordinatorAndSub`:1772/1778
- `totalFlipReversals` (uint64) — `_applyDailyRng`:1921(=0); consumed L1337 (local only)
- `lastVrfProcessedTimestamp` (uint48) — `_applyDailyRng`:1925; `wireVrf`:592
- `lootboxRngWordByIndex[index]` (mapping) — advanceGame:289; `_finalizeLootboxRng`:1284; `_backfillOrphanedLootboxIndices`:1901; `rawFulfillRandomWords`:1844 — **keyed by lootbox index**
- `lootboxRngPacked` (5 fields packed) — `_lrWrite(LR_MID_DAY…)` advanceGame:242, requestLootboxRng:1132; `_lrAdvanceIndexClearPending`:1666 (advances LR_INDEX + clears pending eth/flip) — **packed slot keyed by LR_* offsets (index/pendingEth/pendingFlip/midDay)**
- `presaleStatePacked` (PS_ACTIVE half) — `_psWrite(PS_ACTIVE…,0)` advanceGame:528 — **packed slot keyed by PS_ACTIVE_SHIFT**
- `ticketLevel` (uint24) — advanceGame:413; `_runProcessTicketBatch`/`_prepareFutureTickets` mutate it indirectly via MintModule delegatecalls (read-back at L1543/1555)
- `ticketCursor` (uint32) — advanceGame:414 (=0); mutated by MintModule delegatecalls (read-back L1542/1555)
- `ticketQueue[wk]` (array push) / `ticketsOwedPacked[wk][buyer]` (packed owed|rem) — `_queueTickets` from `_processPhaseTransition`:1564/1570 (perpetual tickets for SDGNRS + VAULT) — **packed mapping value (owed<<8 | rem)**
- `_afkingResetDay` (uint24) — advanceGame:324
- `_subCursor` (uint16) — advanceGame:326(=0); mutated by AfkingModule delegatecall (read-back L331)
- `vrfCoordinator` / `vrfKeyHash` / `vrfSubscriptionId` — `_setVrfConfig` (off-column admin only)

Game-storage writes performed INSIDE the nested delegatecalls (JackpotModule,
MintModule, AfkingModule, GameOverModule, Decimator/BAF, Whale) are owned by THOSE
slices' maps — not enumerated here, but every one lands in Game slots.

---

## 5. HUNT-RELEVANT NOTES (418-425)

- **`_backfillOrphanedLootboxIndices` (L1894) is the only un-capped loop in the slice.**
  Its bound = consecutive empty lootbox indices below `lootboxRngIndex`, which grows
  with un-fulfilled mid-day lootbox reservations during a VRF stall. It runs INSIDE the
  gap-backfill branch of `rngGate` (which is itself decoupled to its own tx via
  `STAGE_GAP_BACKFILLED`), but the orphan scan + the ≤120 gap loop run in the SAME tx
  (L1220+L1224). Worst-case gas (120 gap days × external coinflip + N orphan SSTOREs)
  is the brick-relevant composition.
- **Pre-RNG drain gate revert `RngNotReady` at L283** is on the new-day critical path:
  if the read ticket slot is non-empty AND `rngWordCurrent==0`, the advance cannot pass.
  It is the intended "wait for VRF" gate; permanence depends on VRF recovery (12h/14d
  timeouts live in `rngGate`/`_gameOverEntropy`, NOT here).
- **`_runProcessTicketBatch`:1553 / `_processFutureTicketBatch`:1484 empty-data → `E()`**
  are PERMANENT-CANDIDATEs: any inner MintModule revert bubbles (via `_revertDelegate`),
  and a 0-length return wedges the new-day advance. The terminal-jackpot `processTicketBatch`
  delegatecall in `_handleGameOverPath`:664 is the ONE place a delegate revert is
  deliberately **SWALLOWED** (`dOk==false` → fall through to drain) so terminal fund
  release is never blocked.
- **NESTED delegatecalls everywhere**: because the whole module is delegatecalled from
  Game, all 8 `*.delegatecall(...)` sites are nested. The synthesizer should treat
  `handleFinalSweep` (L621), `handleGameOverDrain` (L692), `processTicketBatch` (L664),
  `processFutureTicketBatch` (L1478), `processTicketBatch` (L1548), `processSubscriberStage`
  (L801), `distributeYieldSurplus` (L777), `payDailyJackpot`/`payDailyJackpotCoinAndTickets`/
  `payDailyFlipJackpot` (L1021/1041/1065) as nested. No `delegatecall(msg.data)` raw
  dispatch in this slice (the raw-dispatch fallback lives in `DegenerusGame`, not here).
- **External-call revert bubble risks on the column** (a synchronous callee revert
  bricks the advance tick):
  - `coinflip.processCoinflipPayouts` (rngGate L1234, gameOver L1306/1341, backfill L1877)
  - `coinflip.creditFlip` (consolidate L984) and `coinflip.rollLevelQuest` analog via `quests.rollLevelQuest` L537 / `quests.rollDailyQuest` L1239
  - `IsDGNRS(SDGNRS).resolveRedemptionPeriod` (rngGate L1258, gameOver L1320/1355)
  - `dgnrs.transferFromPool` / `dgnrs.poolBalance` (`_rewardTopAffiliate` L742/748)
  - `jackpots.markBafSkipped` (consolidate L934)
  - `steth.balanceOf` inside `_unlockRng` snapshot emit (L1815) — day-seal chokepoint
  - `charityResolve.pickCharity` (`_finalizeRngRequest` L1745) — runs at the level-transition
    RNG request; a revert here would block the level increment leg
  - self-CALLs `runBafJackpot` L926 / `runDecimatorJackpot` L948 / `emitDailyWinningTraits`
    L468 re-enter Game (CALL) then delegatecall their module — a revert bubbles.
  - `steth.submit` in `_autoStakeExcessEth` is the ONLY one wrapped in try/catch (L1590)
    — non-blocking by design (emits `StEthStakeFailed`).
- **packed-write aliasing hotspots**: slot-0 small flags (level/lastPurchaseDay/flags),
  slot-1 `currentPrizePool`+`claimablePool`, `prizePoolsPacked` next|future,
  `lootboxRngPacked` LR_* fields, `levelDgnrsPacked[lvl]` allocation|claimed,
  `presaleStatePacked` PS_ACTIVE. A mis-masked write to any of these corrupts a co-packed
  field (RMW correctness, not aliasing-by-key, except `rngWordByDay`/`lootboxRngWordByIndex`/
  `levelPrizePool`/`levelDgnrsPacked` which are keyed mappings → check day/index/level key derivation).
- **mid-RNG / VRF-swap surfaces**: `updateVrfCoordinatorAndSub` (L1755) re-issues in-flight
  requests and intentionally preserves `totalFlipReversals` (nudges carry over, L1786-1789);
  `rawFulfillRandomWords` rejects stale requestIds (L1833) and routes daily vs mid-day by
  `rngLockedFlag`. The fallback-word path (`_gameOverEntropy` L1337) pre-subtracts
  `totalFlipReversals` to cancel the nudge a committer could otherwise steer.
