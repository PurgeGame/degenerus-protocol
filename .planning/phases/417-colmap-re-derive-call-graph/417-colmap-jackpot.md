# 417 Column Map — Slice: JackpotModule

Subject (frozen): `contracts/modules/DegenerusGameJackpotModule.sol` @ tree `0dd445a6`
Inherits: `DegenerusGamePayoutUtils` → `DegenerusGameStorage` (all storage writes land in the **Game's** slots under delegatecall).

Focus: BAF + terminal jackpot resolution via delegatecall (winner sampling, leaderboard, payout loops).

## Dispatch / nesting context (load-bearing)

All 7 external entry points run **inside the Game's storage via delegatecall**, so EVERY storage write below is a delegatecall write into Game slots.

Two distinct invocation shapes — both are NESTED delegatecalls (the column already entered the Game via delegatecall):

- **Direct module delegatecall (from AdvanceModule, itself delegatecalled):**
  `payDailyJackpot`, `payDailyJackpotCoinAndTickets`, `payDailyFlipJackpot`, `distributeYieldSurplus`.
  AdvanceModule does `GAME_JACKPOT_MODULE.delegatecall(abi.encodeWithSelector(...))`
  (e.g. AdvanceModule.sol:773-781 for distributeYieldSurplus; :481/:561 payDailyJackpot via internal call inside the already-delegated AdvanceModule frame; :549 payDailyJackpotCoinAndTickets; :1065 payDailyFlipJackpot selector).
- **Game external self-call wrapper → re-delegatecall (synchronous external call into address(this)):**
  `runTerminalJackpot`, `runBafJackpot`, `emitDailyWinningTraits`.
  Caller does `IDegenerusGame(address(this)).runTerminalJackpot(...)` (GameOverModule.sol:191) / `runBafJackpot(...)` (AdvanceModule.sol:926). The Game's external wrapper (DegenerusGame.sol:1013/1099/1121) checks `msg.sender != address(this)` then `GAME_JACKPOT_MODULE.delegatecall(msg.data)`. So there is a synchronous external CALL hop to the Game, then a re-delegatecall into the module. `msg.sender` is preserved as GAME, satisfying the module's own `msg.sender != GAME` guard (runTerminalJackpot:237, emitDailyWinningTraits:1569) and `msg.sender != address(this)` (runBafJackpot:1916).

## 1. CALL GRAPH (column-reachable functions)

Legend: [int]=internal/private call; [DC-NESTED]=reached via delegatecall (always true here); [EXT]=synchronous external call to FLIP/Coinflip/Vault/sDGNRS/Affiliate/Jackpots/stETH.

### `runTerminalJackpot(poolWei, targetLvl, rngWord)` external — TERMINAL jackpot (GameOver finalization path)
- [int] `_rollWinningTraits` → `JackpotBucketLib.getRandomTraits`, `_applyHeroOverride` → `_rollHeroSymbol` (view; reads dailyHeroWagers), `_applyHeroResult`; `JackpotBucketLib.packWinningTraits`
- [int] `JackpotBucketLib.unpackWinningTraits`
- [int] `_soloAdjustedEntropy` → `_pickSoloQuadrant`; `EntropyLib.hash2`
- [int] `JackpotBucketLib.bucketCountsForPoolCap`, `shareBpsByBucket`
- [int] `_processDailyEth` (see below)  ← the payout engine

### `_processDailyEth(...)` private — UNIFIED ETH distribution engine (shared by terminal + daily + purchase)
- [int] `PriceLookupLib.priceForLevel`
- [int] `JackpotBucketLib.soloBucketIndex`, `bucketShares`, `bucketOrderLargestFirst`
- [int] `_processBucket` ×(active buckets) → `_randTraitTicket` (view; reads traitBurnTicket, deityBySymbol)
  - solo leg: `_handleSoloBucketWinner` → `_processSoloBucketWinner` → `_creditClaimable` (WRITE balancesPacked), `whalePassClaims[]+=` (WRITE), `_addFuturePrizePool` (WRITE prizePoolsPacked)
  - normal leg: `_payNormalBucket` → `_creditClaimable` (WRITE balancesPacked) per winner
- WRITE `claimablePool +=` (slot 1 high half)

### `payDailyJackpot(isJackpotPhase, lvl, randWord)` external — daily (jackpot phase) OR purchase-phase jackpot
- [int] `_simulatedDayIndex` → `GameTimeLib.currentDayIndex`
- [int] `_rollWinningTraitsPair` → `_rollHeroSymbol`, `JackpotBucketLib.getRandomTraits/packWinningTraits`, `_applyHeroResult`
- jackpot-phase branch:
  - reads `jackpotCounter`, `compressedJackpotFlag`
  - [int] `_getCurrentPrizePool`; `_dailyCurrentPoolBps`
  - [int] `_runEarlyBirdLootboxJackpot` (day-1 only) — see below
  - [int] `_budgetToTicketUnits` → `PriceLookupLib.priceForLevel`
  - WRITE `currentPrizePool` (`_setCurrentPrizePool`), WRITE `prizePoolsPacked` (`_addNextPrizePool`, `_getPrizePools`/`_setPrizePools` carryover move)
  - WRITE `dailyTicketBudgetsPacked` (`_packDailyTicketBudgets`)
  - [int] `_soloAdjustedEntropy`, `JackpotBucketLib.bucketCountsForPoolCap/shareBpsByBucket`
  - [int] `_processDailyEth` (isJackpotPhase=true → solo whale-pass leg active)
  - WRITE `currentPrizePool` again; `_addFuturePrizePool` (WRITE prizePoolsPacked) on unpaid remainder
  - [int] `_emitDailyWinningTraits`
  - WRITE `dailyJackpotCoinTicketsPending = true` (slot 0)
- purchase-phase branch:
  - [int] `_emitDailyWinningTraits`; `_getFuturePrizePool`
  - [int] `_processDailyEth` (isJackpotPhase=false)
  - WRITE `prizePoolsPacked` future half (`_setFuturePrizePool`)
  - [int] `_distributeLootboxAndTickets` → `_addNextPrizePool` (WRITE prizePoolsPacked), `_distributeTicketJackpot`

### `payDailyJackpotCoinAndTickets(randWord)` external — Phase-2 (coin + tickets)
- guard: returns if `!dailyJackpotCoinTicketsPending`
- [int] `_unpackDailyTicketBudgets`; reads `level`, `jackpotCounter`
- [int] `_rollWinningTraitsPair`
- [int] `_runFlipJackpot` → `_calcDailyCoinBudget` (reads levelPrizePool), `_awardFarFutureCoinJackpot` **[EXT coinflip.creditFlipBatch]**, `_awardDailyCoinToTraitWinners` **[EXT coinflip.creditFlipBatch]**
- [int] `_distributeTicketJackpot` (daily tickets, then carryover tickets) → `_queueTickets` (WRITE ticketQueue, ticketsOwedPacked)
- WRITE `jackpotCounter = counterCached + counterStep` (slot 0); WRITE `dailyJackpotCoinTicketsPending=false`, `dailyTicketBudgetsPacked=0`

### `payDailyFlipJackpot(lvl, randWord, minLevel, maxLevel)` external
- [int] `_rollWinningTraits`; reads `level`
- [int] `_runFlipJackpot` → far-future + near-future coin awards **[EXT coinflip.creditFlipBatch] ×(0..2)**

### `distributeYieldSurplus(uint256)` external — yield-surplus split
- **[EXT steth.balanceOf(address(this))]**
- reads `address(this).balance`, `_getPrizePools`, `claimablePool`, `yieldAccumulator`, `_getCurrentPrizePool`, `_getPendingPools`
- guard: returns if `totalBal <= obligations`
- [int] `_creditClaimable` ×3 (VAULT / SDGNRS / GNRUS) → WRITE balancesPacked
- WRITE `claimablePool += quarterShare*3`; WRITE `yieldAccumulator += quarterShare`

### `emitDailyWinningTraits(uint24, randWord, bonusTargetLevel)` external — emit-only (purchaseLevel==1)
- guard `msg.sender != GAME` → revert OnlyGame
- [int] `_simulatedDayIndex`, `_rollWinningTraits` ×2, `EntropyLib.hash2`; emits only, NO storage write, NO distribution.

### `runBafJackpot(poolWei, lvl, rngWord)` external — BAF resolution
- guard `msg.sender != address(this)` → revert E
- **[EXT jackpots.runBafJackpot(poolWei, lvl, rngWord)]** → returns (winnersArr, amountsArr, _)
- per winner loop:
  - large (≥5% pool): `_creditClaimable` (WRITE), then either `_awardJackpotTickets` (small lootbox → `_jackpotTicketRoll` → `_queueTickets` WRITE) or `_queueWhalePassClaimCore` (WRITE whalePassClaims + `_creditClaimable`)
  - small even-index: `_creditClaimable` (WRITE)
  - small odd-index: `_awardJackpotTickets` → ticket rolls / whale-pass fallback
- returns `claimableDelta` (caller folds into claimablePool + futurePool debit; **no claimablePool/prizePool write in this fn**)

### `_runEarlyBirdLootboxJackpot(lvl, rngWord)` private (day-1 of jackpot phase)
- [int] `_getPrizePools`, `PriceLookupLib.priceForLevel`, `_rollWinningTraits`, `_randTraitTicket` ×4
- [int] `_queueTickets` per winner (WRITE ticketQueue, ticketsOwedPacked)
- WRITE `prizePoolsPacked` (single net `_setPrizePools`: next += budget, future -= budget)

### Leaf helpers writing Game storage
- `_creditClaimable` → WRITE `balancesPacked[beneficiary]`
- `_queueTickets` → guard `_livenessTriggered()` revert E; guard far-future+rngLocked revert RngLocked; WRITE `ticketQueue[wk]` (push), WRITE `ticketsOwedPacked[wk][buyer]`
- `_queueWhalePassClaimCore` → WRITE `whalePassClaims[winner]`, `_creditClaimable`
- `_set/_addNextPrizePool`,`_set/_addFuturePrizePool`,`_setCurrentPrizePool`,`_setPrizePools` → WRITE prize pool slots

### External-call surface summary (synchronous, callee-revert-bubbles)
| call | target | site | bubbles to |
|---|---|---|---|
| `coinflip.creditFlipBatch(players, amounts)` | Coinflip (FLIP) | `_awardFarFutureCoinJackpot`:1752, `_awardDailyCoinToTraitWinners`:1678 | payDailyJackpotCoinAndTickets / payDailyFlipJackpot → advanceGame |
| `jackpots.runBafJackpot(poolWei, lvl, rngWord)` | DegenerusJackpots | `runBafJackpot`:1918 | Game self-call wrapper → advanceGame |
| `steth.balanceOf(address(this))` | stETH | `distributeYieldSurplus`:683 | advanceGame |

## 2. REVERT-SITE INVENTORY

| fn:line | trigger | error | class |
|---|---|---|---|
| runTerminalJackpot:237 | `msg.sender != ContractAddresses.GAME` | `OnlyGame()` | TRANSIENT (access guard; correct caller = Game self-call always satisfies it) |
| emitDailyWinningTraits:1569 | `msg.sender != ContractAddresses.GAME` | `OnlyGame()` | TRANSIENT (access guard) |
| runBafJackpot:1916 | `msg.sender != address(this)` | `E()` | TRANSIENT (access guard) |
| runBafJackpot:1918 (EXT) | `jackpots.runBafJackpot` reverts/OOGs → `!ok`-bubble at DegenerusGame.sol:1022 | bubbled callee revert | **PERMANENT-CANDIDATE** — synchronous; a revert in the Jackpots contract bubbles up and reverts the BAF leg of advanceGame at a level%10 transition. See §5. |
| `_awardFarFutureCoinJackpot`:1752 (EXT) | `coinflip.creditFlipBatch` reverts/OOGs | bubbled callee revert | **PERMANENT-CANDIDATE** — reverts payDailyJackpotCoinAndTickets / payDailyFlipJackpot, both on the advanceGame chain. See §5. |
| `_awardDailyCoinToTraitWinners`:1678 (EXT) | `coinflip.creditFlipBatch` reverts/OOGs | bubbled callee revert | **PERMANENT-CANDIDATE** — same chain. See §5. |
| distributeYieldSurplus:683 (EXT) | `steth.balanceOf` reverts | bubbled callee revert | **PERMANENT-CANDIDATE** — reverts distributeYieldSurplus → advanceGame. stETH is a fixed mainnet token; low likelihood but synchronous. |
| `_queueTickets` (storage):618 | `_livenessTriggered()` true | `E()` | **PERMANENT-CANDIDATE (by design)** — once liveness-timeout fires, ALL ticket queueing reverts. Any jackpot leg that calls `_queueTickets` (early-bird lootbox, daily/carryover tickets, BAF ticket rolls) would revert if reached after liveness trips. Intent: terminal jackpot must not be manipulable by post-VRF ticket adds. The column is expected to be on the gameOver path by then. Flagged because a jackpot leg reaching `_queueTickets` post-trigger wedges that leg. |
| `_queueTickets` (storage):621 | far-future target & `rngLockedFlag` & `!rngBypass` | `RngLocked()` | TRANSIENT-by-bypass — all jackpot-module `_queueTickets` calls pass `rngBypass=true` (early-bird:647, `_distributeTicketsToBucket`:906, `_jackpotTicketRoll`:2121), so this branch is NOT taken from this slice. Listed for completeness. |
| `_debitClaimable`/`_debitAfking`/`_settleShortfall` | n/a | — | NOT reached from this slice (no debit/settle path here; jackpot only credits). |
| Checked arithmetic — `claimablePool += uint128(...)` :713/:1119 | uint128 overflow on aggregate liability | Panic 0x11 | TRANSIENT-theoretical (claimablePool ≤ total ETH supply ≪ 2^128; cannot overflow in practice) |
| Checked arithmetic — `_setCurrentPrizePool(curPool - dailyEthBudget)` :446 ; `curPool - paidDailyEth` :451 ; `futureBal - lootboxBudget - paidEth` :530 | underflow if deduction > pool | Panic 0x11 | TRANSIENT-theoretical — budgets are computed as fractions of the same cached pool; by construction deduction ≤ pool. A divergence (e.g. paidDailyEth > dailyEthBudget) would underflow-revert. Treated as invariant; flagged for the solvency lens. |
| Checked arithmetic — `_calcDailyCoinBudget`:1828 `levelPrizePool[lvl - 1]` | `lvl == 0` → uint24 underflow on `lvl-1` | Panic 0x11 | TRANSIENT — `lvl` here is the prize-pool snapshot level (≥1 in all column callers: payDailyJackpotCoinAndTickets passes `level`, payDailyFlipJackpot passes the purchase level). Would only fire at level 0, where these jackpot legs are not driven. |
| `_unpackDailyTicketBudgets` narrowing :1873-1875 | none (uintN truncation, no revert) | — | n/a (lossy-by-design pack; not a revert) |
| StakedStonk/Vault/Affiliate/sDGNRS | n/a | — | No direct calls to Vault/sDGNRS/Affiliate from this slice. SDGNRS/VAULT/GNRUS appear only as `_creditClaimable` beneficiary ADDRESSES in distributeYieldSurplus — pure storage credit, no external call, no callee revert. |

Notes:
- `runTerminalJackpot` updates `claimablePool` internally (via `_processDailyEth`); the GameOver caller must not double-count (DegenerusGame.sol:1092). A double-credit there is a solvency bug, not a revert — flagged for the corrupt/gameover lens.
- `payDailyJackpotCoinAndTickets` is idempotent-guarded by the `dailyJackpotCoinTicketsPending` latch (returns early if false), so a re-entry / double-drive is a no-op rather than a revert or double-pay.

## 3. LOOP INVENTORY

| fn:line | count bound | per-iter touch | class |
|---|---|---|---|
| `payDailyJackpot`:508 (purchase bucket rotation) | fixed 4 | memory only | BOUNDED |
| `_runEarlyBirdLootboxJackpot`:637 outer | fixed 4 (traits) | `_randTraitTicket` (view), inner winner loop | BOUNDED |
| `_runEarlyBirdLootboxJackpot`:644 inner | `winners.length` = 25 (fixed `numWinners` arg) | `_queueTickets` (push + SSTORE), emit | BOUNDED (≤25 per trait, ≤100 total) |
| `_distributeTicketsToBuckets`:841 | fixed 4 (traits) | keccak, `_distributeTicketsToBucket` | BOUNDED |
| `_distributeTicketsToBucket`:899 | `winners.length` = `count` ≤ `cap` ≤ maxWinners | `_queueTickets` (SSTORE), emit | BOUNDED — cap=`maxWinners` arg (≤ PURCHASE_PHASE_TICKET_MAX_WINNERS 120 or LOOTBOX_MAX_WINNERS 100), clamped to `ticketUnits` |
| `_computeBucketCounts`:947 | fixed 4 | SLOAD `traitBurnTicket[lvl][trait].length`, `deityBySymbol` | BOUNDED |
| `_computeBucketCounts`:972 | fixed 4 | memory | BOUNDED |
| `_computeBucketCounts`:983 while(remainder) | ≤ `maxWinners` (remainder < activeCount ≤4, but scan skips inactive → ≤ ~remainder*4 ≤ 16) | memory only | BOUNDED (remainder ≤ 3; inner walks mod-4) |
| `_pickSoloQuadrant`:1015 | fixed 4 | memory/stack | BOUNDED |
| `_processDailyEth`:1084 | fixed 4 (buckets) | `_processBucket` (selection + credits) | BOUNDED |
| `_processBucket` → `_randTraitTicket`:1499 | `numWinners` = totalCount ≤ MAX_BUCKET_WINNERS 250 | keccak, holder read | BOUNDED (≤250) |
| `_payNormalBucket`:1227 | `winners.length` ≤ 250 | `_creditClaimable` (SSTORE), emit | BOUNDED |
| `_rollHeroSymbol`:1365 outer / :1367 inner | fixed 4 × 8 = 32 | SLOAD `dailyHeroWagers[day][q]` ×4 (once per q), decode | BOUNDED (32 slots) |
| `_rollHeroSymbol`:1401 (weighted pick) | fixed 32 | memory | BOUNDED |
| `_awardDailyCoinToTraitWinners`:1604 (deity cache) | fixed 4 | `deityBySymbol` SLOAD | BOUNDED |
| `_awardDailyCoinToTraitWinners`:1625 (pulls) | `cap` = DAILY_COIN_MAX_WINNERS 50 (clamped to coinBudget) | SLOAD holders.length, keccak, emit, memory array fill | BOUNDED (≤50) |
| `_awardFarFutureCoinJackpot`:1701 (sample) | fixed FAR_FUTURE_FLIP_SAMPLES 10 | SLOAD `ticketQueue[key].length`, queue[idx] | BOUNDED (10) |
| `_awardFarFutureCoinJackpot`:1736 (distribute) | `found` ≤ 10 | emit, memory | BOUNDED |
| `runBafJackpot`:1930 | `winnersArr.length` = **DegenerusJackpots-returned** | `_creditClaimable` / `_awardJackpotTickets` / `_queueWhalePassClaimCore` (SSTOREs, emits) | **INPUT-SIZED (external-controlled length)** — see §5 / unboundedLoops. Bound lives in the Jackpots contract, NOT enforced here. |
| `_awardJackpotTickets` → `_jackpotTicketRoll` | ≤2 rolls per call | `_queueTickets` (SSTORE), emit | BOUNDED |

Note: `_queueTickets` itself does `ticketQueue[wk].push` (one SSTORE on first ticket for a (level,buyer)) — no loop; array growth is amortized per winner.

## 4. DELEGATECALL STORAGE-WRITE INVENTORY (Game slots)

All writes are delegatecall writes into the Game's storage.

| variable (as declared) | slot / packing | written by |
|---|---|---|
| `currentPrizePool` (uint128) | **slot 1 [0:16] — PACKED with claimablePool** | `_setCurrentPrizePool` ← payDailyJackpot:360/446/451 |
| `claimablePool` (uint128) | **slot 1 [16:32] — PACKED with currentPrizePool** | `claimablePool +=` _processDailyEth:1119, distributeYieldSurplus:713 |
| `prizePoolsPacked` (uint256: next[0:16]\|future[16:32]) | slot (own) — **internally packed next/future** | `_setPrizePools`/`_addNextPrizePool`/`_addFuturePrizePool`/`_setFuturePrizePool` ← payDailyJackpot:361/386/448/530, `_runEarlyBirdLootboxJackpot`:671, `_distributeLootboxAndTickets`:763, `_processSoloBucketWinner`:1274 (whale-pass → future) |
| `jackpotCounter` (uint8) | **slot 0 [16:17] — PACKED with FSM flags** | payDailyJackpotCoinAndTickets:610 (`= counterCached + counterStep`) |
| `dailyJackpotCoinTicketsPending` (bool) | **slot 0 [22:23] — PACKED** | payDailyJackpot:463 (`=true`), payDailyJackpotCoinAndTickets:614 (`=false`) |
| `dailyTicketBudgetsPacked` (uint256: counterStep\|dailyUnits\|carryUnits\|srcOffset) | slot (own) — **internally packed 4 fields** | payDailyJackpot:399 (set), payDailyJackpotCoinAndTickets:615 (clear `=0`) |
| `yieldAccumulator` (uint256) | slot (own) | distributeYieldSurplus:714 |
| `balancesPacked[addr]` (uint256: claimable[low128]\|afking[high128]) | mapping; **per-entry packed claimable/afking** | `_creditClaimable` (low half only) ← _payNormalBucket, _processSoloBucketWinner, _queueWhalePassClaimCore remainder, runBafJackpot ETH legs, distributeYieldSurplus ×3 (VAULT/SDGNRS/GNRUS) |
| `whalePassClaims[addr]` (uint256) | mapping | `_processSoloBucketWinner`:1273, `_queueWhalePassClaimCore`:42 |
| `ticketQueue[wk]` (address[]) | mapping→array | `_queueTickets`:629 (push) ← early-bird, ticket-jackpot, BAF rolls |
| `ticketsOwedPacked[wk][buyer]` (uint40: owed[8:40]\|rem[0:8]) | nested mapping; **packed owed/rem** | `_queueTickets`:634 |

Packed-slot aliasing hotspots (same EVM slot, written by different keys/legs in one tx):
- **Slot 1**: `currentPrizePool` AND `claimablePool` — written in the SAME `payDailyJackpot` jackpot-phase call (currentPrizePool via `_setCurrentPrizePool`, claimablePool via `_processDailyEth`). Each goes through its own typed accessor (read-modify-write of only its half), so they do not clobber each other, but they share a slot — any future raw-slot write must respect both halves.
- **Slot 0**: `jackpotCounter` + `dailyJackpotCoinTicketsPending` (+ read-only `compressedJackpotFlag`, `level`, `jackpotPhaseFlag`, `rngLockedFlag`) — `jackpotCounter` and `dailyJackpotCoinTicketsPending` are both written in `payDailyJackpotCoinAndTickets`. Solidity does each as a masked field write; the FSM/level fields in the same slot are read concurrently by `_livenessTriggered` / advance logic.
- **`prizePoolsPacked`** internal next/future: every accessor re-reads the full word then rewrites both halves (`_setPrizePools`). Legs that move future→next in one call (carryover :386, early-bird :671) compute both halves from one read — correct only because nothing between read and write touches the slot (asserted in-code).
- **`dailyTicketBudgetsPacked`** internal pack: counterStep(8)\|dailyTicketUnits(64@8)\|carryoverTicketUnits(64@72)\|carryoverSourceOffset(8@136). Written whole in Phase-1, consumed+cleared in Phase-2.
- **`balancesPacked[addr]`** low/high pack: jackpot path writes ONLY the low (claimable) half via `_creditClaimable` (full-word `+=`, safe because per-player ≪ 2^128); never touches the afking high half.

## 5. HUNT-RELEVANT (418-423) — surfaced items

### Unbounded / input-sized loops
- `runBafJackpot`:1930 — bound = `winnersArr.length`, returned by the EXTERNAL `jackpots.runBafJackpot` call. The winner-count ceiling is enforced inside DegenerusJackpots, NOT in this module. If that contract returns an oversized array, the per-winner loop (each doing SSTOREs + emits, large legs doing `_queueTickets` ticket rolls) can run out of gas → reverts the BAF leg of advanceGame at a level%10 transition. **Gas-brick candidate gated on the Jackpots contract's own cap** (cross-contract trust seam).

### Permanent-revert candidates (could wedge advanceGame / gameOver)
- `_queueTickets`:618 `_livenessTriggered()` → `E()`: once the liveness timeout trips, every ticket-queueing jackpot leg reverts. If any column leg that calls `_queueTickets` (early-bird lootbox, daily/carryover ticket distribution, BAF ticket rolls) is reached AFTER liveness fires, that leg wedges. By design the column should be on the gameOver drain path by then, but a path that still routes through a ticket-queueing jackpot leg post-trigger would brick.
- Checked-underflow on prize-pool deductions (`_setCurrentPrizePool(curPool - …)`:446/451, future debit :530): if a paid amount ever exceeds its cached budget (invariant break), the SSTORE-time subtraction panics and reverts the whole `payDailyJackpot` → advanceGame. This is the solvency invariant doubling as a liveness wedge.
- BAF self-call wrapper revert: `runBafJackpot` returning `data.length == 0` → `revert E()` at DegenerusGame.sol:1023, or `!ok` bubble at :1022. Any revert inside the module's BAF processing (e.g. the input-sized loop above, or a `_queueTickets` liveness revert) bubbles through the wrapper and reverts the advance leg.

### Nested delegatecalls (this whole slice is nested; raw-dispatch note)
- ALL 7 entry points are reached via delegatecall while already inside a delegatecalled column frame:
  - Direct: `payDailyJackpot`, `payDailyJackpotCoinAndTickets`, `payDailyFlipJackpot`, `distributeYieldSurplus` (AdvanceModule → `GAME_JACKPOT_MODULE.delegatecall`).
  - Via Game self-call + re-delegatecall: `runTerminalJackpot` (GameOverModule self-call), `runBafJackpot` (AdvanceModule self-call), `emitDailyWinningTraits`.
- The Game wrapper uses `GAME_JACKPOT_MODULE.delegatecall(msg.data)` (raw calldata forward) — NOT `delegatecall(msg.data)` to an arbitrary/attacker-chosen target; target is the fixed `ContractAddresses.GAME_JACKPOT_MODULE` constant. No raw `delegatecall(msg.data)` dispatch on an attacker-controlled selector/target inside this slice.

### Callee-revert risks (synchronous external; revert bubbles up and bricks the calling column tx)
- `_awardFarFutureCoinJackpot`:1752 / `_awardDailyCoinToTraitWinners`:1678 → `coinflip.creditFlipBatch` — a revert/OOG in the Coinflip contract bubbles up and reverts `payDailyJackpotCoinAndTickets` / `payDailyFlipJackpot`, both on the advanceGame chain.
- `runBafJackpot`:1918 → `jackpots.runBafJackpot` — revert bubbles to advanceGame's BAF leg.
- `distributeYieldSurplus`:683 → `steth.balanceOf` — revert bubbles to advanceGame (fixed mainnet stETH; low likelihood).

### Other notes for the corrupt / gameover / vrfswap lenses
- `runTerminalJackpot` writes `claimablePool` internally via `_processDailyEth`; GameOver caller must not double-count (solvency, not liveness).
- All entropy is derived from the single VRF `rngWord` argument passed by the parent; the module consumes it via keccak domain-separated tags (FLIP_JACKPOT_TAG, FLIP_LEVEL_TAG, BONUS_TRAITS_TAG, DAILY_*_TAG, FAR_FUTURE_FLIP_TAG). `_rollHeroSymbol` reads `dailyHeroWagers[dailyIdx]` (frozen at prev-day index during resolution) — a mid-resolution `dailyIdx` change would shift the hero pool (vrfswap / mid-rng lens; `dailyIdx` is not written by this slice).
- Winner sampling intentionally allows duplicates and uses virtual deity entries (`_deityVirtualCount`): the deity address read (`deityBySymbol`) is cached per-trait; a mid-resolution deity change is not possible from this slice (no write).
