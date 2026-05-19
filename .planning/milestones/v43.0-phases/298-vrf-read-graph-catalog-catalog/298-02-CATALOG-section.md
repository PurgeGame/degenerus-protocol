# §2 — JackpotModule.payDailyJackpotCoinAndTickets (file:line 596)

**Consumer entry:** `contracts/modules/DegenerusGameJackpotModule.sol:596`
**Caller:** `DegenerusGameAdvanceModule.sol:937` (`payDailyJackpotCoinAndTickets`, internal helper) — invoked from `advanceGame()` stage machine at `DegenerusGameAdvanceModule.sol:461` (delegatecall to `GAME_JACKPOT_MODULE`).
**Execution context:** rngLockedFlag == true; rngWordCurrent committed to VRF entropy; runs as part of the JACKPOT-phase advance cycle in `advanceGame()`. EXEMPT-ADVANCEGAME applies to every writer callsite reached as a static call-graph descendant of `advanceGame()`.

This section follows the Phase 287 JPSURF format precedent ( `.planning/milestones/v41.0-phases/287-jackpot-influence-surface-closure-jpsurf/287-01-JPSURF-AUDIT.md` §1–§3) scaled to a single-consumer catalog row-set per `D-298-CATALOG-LAYOUT-01`. **AUDIT-ONLY (D-43N-AUDIT-ONLY-01)**: zero contract mutations; output is .planning artifact only.

---

## CAT-01 (§A) — Traced Function Set

Backward trace from `payDailyJackpotCoinAndTickets` at JackpotModule.sol:596. Walks transitively into every internal/external function reached across `contracts/`. Stops only at no-source external interfaces (Chainlink VRF coordinator — outside this consumer's resolution path; only `IBurnieCoinflip` external calls leave the game contract here, and source is available under `contracts/BurnieCoinflip.sol` so the trace continues).

| # | Function | File:Line | Visibility | Notes |
|---|----------|-----------|-----------|-------|
| 1 | `payDailyJackpotCoinAndTickets(uint256 randWord)` | JackpotModule.sol:596 | external | Consumer entry. Reads `dailyJackpotCoinTicketsPending`, `dailyTicketBudgetsPacked`, `level`, `jackpotCounter`. Writes `jackpotCounter`, `dailyJackpotCoinTicketsPending`, `dailyTicketBudgetsPacked`. |
| 2 | `_unpackDailyTicketBudgets(uint256)` | JackpotModule.sol:2043 | private pure | Pure bit-unpack; no SLOAD. |
| 3 | `_rollWinningTraits(uint256 randWord, bool isBonus)` | JackpotModule.sol:1993 | private view | Calls `_applyHeroOverride`. Pure call to `JackpotBucketLib.getRandomTraits`/`packWinningTraits`. |
| 4 | `_applyHeroOverride(uint8[4], uint256, uint256)` | JackpotModule.sol:1600 | private view | Calls `_rollHeroSymbol(dailyIdx, heroEntropy)`. Reads `dailyIdx`. |
| 5 | `_rollHeroSymbol(uint32 day, uint256 entropy)` | JackpotModule.sol:1639 | private view | Reads `dailyHeroWagers[day][q]` for q∈{0..3}. |
| 6 | `EntropyLib.hash2(uint256, uint256)` | EntropyLib.sol:23 | internal pure | Pure keccak scratch-mix. |
| 7 | `_calcDailyCoinBudget(uint24 lvl)` | JackpotModule.sol:2006 | private view | Reads `level` (passed as parameter to `priceForLevel`), `levelPrizePool[lvl-1]`. |
| 8 | `PriceLookupLib.priceForLevel(uint24)` | PriceLookupLib.sol | internal pure | Pure table lookup. |
| 9 | `_awardFarFutureCoinJackpot(uint24, uint256, uint256)` | JackpotModule.sol:1918 | private | Reads `ticketQueue[_tqFarFutureKey(candidate)]`. Calls `coinflip.creditFlipBatch` (external). |
| 10 | `_tqFarFutureKey(uint24)` | DegenerusGameStorage.sol:731 | internal pure | Pure bit-set (`lvl | TICKET_FAR_FUTURE_BIT`). |
| 11 | `_awardDailyCoinToTraitWinners(uint24, uint24, uint32, uint256, uint256)` | JackpotModule.sol:1822 | private | Reads `deityBySymbol[fullSymId]` (line 1844), `traitBurnTicket[lvlPrime][trait_i]` (line 1860). Calls `coinflip.creditFlip` (external). |
| 12 | `JackpotBucketLib.unpackWinningTraits(uint32)` | JackpotBucketLib.sol:272 | internal pure | Pure bit-unpack. |
| 13 | `JackpotBucketLib.getRandomTraits(uint256)` | JackpotBucketLib.sol:281 | internal pure | Pure bit-slice. |
| 14 | `JackpotBucketLib.packWinningTraits(uint8[4])` | JackpotBucketLib.sol:267 | internal pure | Pure bit-pack. |
| 15 | `_distributeTicketJackpot(uint24, uint24, uint32, uint256, uint256, uint16, uint8)` | JackpotModule.sol:896 | private | Calls `_computeBucketCounts` + `_distributeTicketsToBuckets`. |
| 16 | `_computeBucketCounts(uint24 lvl, uint8[4], uint16, uint256)` | JackpotModule.sol:1030 | private view | Reads `traitBurnTicket[lvl][trait]` (line 1039) and `deityBySymbol[fullSymId]` (line 1044). |
| 17 | `_distributeTicketsToBuckets(uint24, uint24, uint8[4], uint16[4], uint256, uint256, uint16, uint8)` | JackpotModule.sol:934 | private | Calls `_distributeTicketsToBucket` per trait. No direct SLOAD. |
| 18 | `_distributeTicketsToBucket(...)` | JackpotModule.sol:973 | private | Calls `_randTraitTicket` + `_queueTickets`. |
| 19 | `_randTraitTicket(address[][256] storage, uint256, uint8, uint8, uint8)` | JackpotModule.sol:1707 | private view | Reads `traitBurnTicket[sourceLvl][trait]` length+elements (line 1718-1753), `deityBySymbol[fullSymId]` (line 1730). |
| 20 | `_queueTickets(address, uint24, uint32, bool rngBypass=true)` | DegenerusGameStorage.sol:559 | internal | Reads `level` (via `_livenessTriggered` + the explicit `level + 5` at line 571), `rngLockedFlag` (line 572), `ticketWriteSlot` (via `_tqWriteKey` line 575 / `_tqFarFutureKey` is pure), `ticketsOwedPacked[wk][buyer]` (line 576). Writes `ticketQueue[wk]` push (line 580) and `ticketsOwedPacked[wk][buyer]` (line 585). `rngBypass=true` from every callsite reached here, so the rngLockedFlag check is **bypassed**. |
| 21 | `_livenessTriggered()` | DegenerusGameStorage.sol:1243 | internal view | Reads `lastPurchaseDay`, `jackpotPhaseFlag`, `level`, `purchaseStartDay`, `rngRequestTime`. `_simulatedDayIndex()` returns from `block.timestamp` (no SLOAD). |
| 22 | `_simulatedDayIndex()` | DegenerusGameStorage.sol:1208 | internal view | Returns `GameTimeLib.currentDayIndex()` — pure-time (block.timestamp only). |
| 23 | `_tqWriteKey(uint24)` | DegenerusGameStorage.sol:718 | internal view | Reads `ticketWriteSlot`. |
| 24 | `coinflip.creditFlip(address, uint256)` | BurnieCoinflip.sol:898 | external | Cross-contract via immutable `coinflip = IBurnieCoinflip(ContractAddresses.COINFLIP)` (storage line 138). `onlyFlipCreditors` modifier checks `msg.sender == GAME`. Calls `_addDailyFlip(player, amount, 0, false, false)` → `recordAmount==0` skips boon branch, `canArmBounty==false` skips bounty branch. |
| 25 | `coinflip.creditFlipBatch(address[], uint256[])` | BurnieCoinflip.sol:909 | external | Loop over `_addDailyFlip(player, amount, 0, false, false)` per element. Same gating as #24. |
| 26 | `BurnieCoinflip._addDailyFlip(address, uint256, uint256, bool, bool)` | BurnieCoinflip.sol:627 | private | Reads `coinflipBalance[targetDay][player]` (line 652). Writes `coinflipBalance[targetDay][player]` (line 656). Calls `_updateTopDayBettor` + `_targetFlipDay`. |
| 27 | `BurnieCoinflip._targetFlipDay()` | BurnieCoinflip.sol:1095 | internal view | Calls `degenerusGame.currentDayView()` (external view; no SLOAD that affects this consumer — pure-time). |
| 28 | `BurnieCoinflip._updateTopDayBettor(address, uint256, uint32)` | BurnieCoinflip.sol:1127 | private | Reads `coinflipTopByDay[day]` (line 1133). Writes `coinflipTopByDay[day]` (line 1135) when score exceeds current leader. |
| 29 | `BurnieCoinflip._score96(uint256)` | BurnieCoinflip.sol (above _updateTopDayBettor) | private pure | Pure uint96 cast. |
| 30 | `DegenerusGame.currentDayView()` | DegenerusGame.sol:471 | external view | Returns `_simulatedDayIndex()` — pure-time. |

**Excluded from trace (out of resolution path):** `_runEarlyBirdLootboxJackpot` (called only from `payDailyJackpot` §1, NOT from §2); `_processDailyEth`, `_resumeDailyEth`, `_handleSoloBucketWinner`, `_payNormalBucket`, `_processSoloBucketWinner` (ETH-distribution paths reached only from §1/§3); `_addClaimableEth`, `_processAutoRebuy`, `_creditClaimable`, `_calcAutoRebuy`, `whalePassClaims` writes (consumer §2 awards COIN + tickets only — no ETH credit path).

**External-interface stops:** Chainlink VRF coordinator (not reached on §2 resolution path — VRF is the predecessor; `randWord` arrives via parameter from `_unlockRng`-gated advance stage). `dgnrs`/`vault`/`steth` not reached on §2 (yield/DGNRS paths are §1/distributeYieldSurplus, not §2).

---

## CAT-02 (§B) — SLOAD Table

Every SLOAD reached on the §2 resolution path enumerated below per `feedback_rng_window_storage_read_freshness.md` (F-41-02/03 precedent — non-VRF reads consumed alongside RNG are a distinct bug class). `Participating?` = does this value influence any VRF-derived output (winner address, ticket queue target, coin amount, etc.). Slot path: `contracts/storage/DegenerusGameStorage.sol` unless otherwise noted; cross-contract slot paths cite the owning contract file.

| # | Slot | Read-site (file:line) | Read context | Participating? | Attestation (if NO) |
|---|------|----------------------|--------------|----------------|---------------------|
| 1 | `dailyJackpotCoinTicketsPending` (Storage:295) | JackpotModule.sol:597 | Phase-2 idempotency guard | NO | Boolean gate; if false the function returns. Does not flow into any random output. |
| 2 | `dailyTicketBudgetsPacked` (Storage:390) | JackpotModule.sol:605 | counterStep, dailyTicketUnits, carryoverTicketUnits, carryoverSourceOffset | **YES** | n/a — drives `sourceLevel = lvl + carryoverSourceOffset` (line 612), entropy salt-domain (line 613), winner cap, ticket distribution amounts. |
| 3 | `level` (Storage:250) | JackpotModule.sol:608 (`level`), 651 (`jackpotCounter + counterStep >= JACKPOT_LEVEL_CAP`), 2007 (`priceForLevel(level)`), 2009 (`levelPrizePool[lvl-1]`) | Current jackpot level — used as `lvl` for trait-bucket index, coin-budget level, ticket queue level. Also read via `_queueTickets`/`_livenessTriggered` (line 571, 1248). | **YES** | n/a — `traitBurnTicket[lvl]`/`levelPrizePool[lvl-1]` keying. |
| 4 | `jackpotCounter` (Storage:268) | JackpotModule.sol:651 | `isFinalDay = jackpotCounter + counterStep >= JACKPOT_LEVEL_CAP` | **YES** | n/a — drives `isFinalDay → queueLvl = lvl+1 vs lvl` for carryover bucket (line 654). |
| 5 | `dailyIdx` (Storage:236) | JackpotModule.sol:1609 (`_rollHeroSymbol(dailyIdx, …)`) | Day index for hero wager pool lookup | **YES** | n/a — keys `dailyHeroWagers[dailyIdx]`. |
| 6 | `dailyHeroWagers[dailyIdx][q]` (Storage:1485, mapping(uint32 => uint256[4])) | JackpotModule.sol:1653 (4× per resolution) | Hero-symbol weighted roll: pass 1 caches 32 packed weights + finds leader; pass 2 walks cumulative cursor against keccak pick + leaderBonus | **YES** | n/a — sets `heroQuadrant`/`heroSymbol` for `_applyHeroOverride` which overwrites one of the 4 winning trait IDs (line 1623). Both main+bonus roll paths invoke `_applyHeroOverride` (line 609, 610) so both reads consume slot[dailyIdx]. |
| 7 | `levelPrizePool[lvl-1]` (Storage:944) | JackpotModule.sol:2009 | Daily coin budget = `levelPrizePool[lvl-1] * PRICE_COIN_UNIT / (priceWei * 200)` (0.5% of prize-pool target in BURNIE) | **YES** | n/a — drives `coinBudget` which splits into `farBudget` + `nearBudget` and ultimately determines coin payout amounts. |
| 8 | `ticketQueue[_tqFarFutureKey(candidate)]` (Storage:461) | JackpotModule.sol:1940 (`queue.length`), 1944 (`queue[(entropy >> 32) % len]`) | Far-future coin jackpot winner pool — up to 10 random level samples in `[lvl+5, lvl+99]`, picks 1 winner per non-empty level via `(entropy >> 32) % len` | **YES** | n/a — selects winner addresses + queue cardinality drives `farBudget / found` per-winner amount. Far-future key has TICKET_FAR_FUTURE_BIT set (line 731); ticketWriteSlot is ignored on far-future key so the double-buffer does NOT protect this slot (Phase 287 §3 row 4-FF precedent). |
| 9 | `deityBySymbol[fullSymId]` (Storage:975) | JackpotModule.sol:1044 (via `_computeBucketCounts`), 1730 (via `_randTraitTicket`), 1844 (via `_awardDailyCoinToTraitWinners` per-trait deity cache) | Virtual-deity holder injection: gold tier (color==7) adds 1 virtual entry; common tier adds `floor(2% of bucket)` virtual entries (min 2). | **YES** | n/a — sets `virtualCount` ≥ 2 when deity exists (line 1736, 1737, 1872, 1873); inflates effective bucket length used in `% effectiveLen` index roll (line 1750, 1885); winner becomes deity address when `idx ≥ len` (line 1756, 1892). |
| 10 | `traitBurnTicket[lvl][trait]` (Storage:415, mapping(uint24 => address[][256])) | JackpotModule.sol:1039 (via `_computeBucketCounts.hasEntries`), 1718-1753 (via `_randTraitTicket`: length + holders[idx]), 1860 (via `_awardDailyCoinToTraitWinners`) | Trait-bucket holder list — drives effective bucket size + winner address selection per random index roll. | **YES** | n/a — `holders[idx]` is the literal winner; `hasEntries`/`len` participates in the virtual-deity count + effective-length math. |
| 11 | `rngLockedFlag` (Storage:284) | DegenerusGameStorage.sol:572 (via `_queueTickets`) | Gate `if (isFarFuture && rngLockedFlag && !rngBypass) revert RngLocked();` — `rngBypass=true` from every consumer-§2 callsite so this read does NOT influence control flow on this path. | NO | Read but result short-circuited by `!rngBypass` (always true from §2 callsites at JackpotModule.sol:703, 837, 1007, 2305). Slot is read regardless but never causes revert and is not an entropy input. |
| 12 | `ticketWriteSlot` (Storage:325) | DegenerusGameStorage.sol:719 (via `_tqWriteKey` from `_queueTickets`) | Selects write key for non-far-future ticket queue: `lvl` or `lvl | TICKET_SLOT_BIT`. | **YES** | n/a — writer key determines which buffer the ticket-queue write lands in. Although consumer §2 reads only ticketQueue at the far-future key (which ignores ticketWriteSlot), it WRITES via `_queueTickets` to the write-slot-keyed buffer — and that write location is participating (downstream advance-cycles drain the read-slot buffer). |
| 13 | `ticketsOwedPacked[wk][buyer]` (Storage:465) | DegenerusGameStorage.sol:576 (via `_queueTickets`) | Read-modify-write of per-(level-key, buyer) packed-tickets-owed counter. | NO | RMW accumulator only; the read+add+store sequence does not influence which slot is written or which entropy is consumed. Pre-existing balance is added to and stored — not a randomness input. Excluded from §C; flagged here for F-41-02/03 enumeration discipline. |
| 14 | `lastPurchaseDay` (Storage:273), `jackpotPhaseFlag` (Storage:257), `purchaseStartDay` (Storage:228), `rngRequestTime` (Storage:244) | DegenerusGameStorage.sol:1244-1251 (via `_livenessTriggered` from `_queueTickets`) | Liveness-timeout check that reverts `_queueTickets` once liveness fires. | NO | Each is an authoritative-state SLOAD reached only as a revert guard. During §2 resolution we are inside `advanceGame()` jackpot phase with `jackpotPhaseFlag==true` and `rngLockedFlag==true`; `_livenessTriggered` short-circuits at line 1244 (`if (lastPurchaseDay || jackpotPhaseFlag) return false;`), so subsequent reads of `purchaseStartDay`/`rngRequestTime`/`level` happen only if both flags are false — impossible here. Captured for completeness per F-41-02/03 enumeration discipline; not entropy inputs. |
| 15 | `coinflipBalance[targetDay][player]` (BurnieCoinflip.sol:163 declaration; read at BurnieCoinflip.sol:652) | BurnieCoinflip.sol:652 (via `_addDailyFlip` from `creditFlip`/`creditFlipBatch`) | Read-modify-write of per-(day, player) coinflip stake accumulator. | NO | RMW accumulator outside the §2 game-contract resolution path. Read drives only the new stake total written back, not any randomness input that flows into §2's winner/payout selection. Flagged for cross-contract enumeration discipline per `D-298-TRACE-DEPTH-01`. |
| 16 | `coinflipTopByDay[day]` (BurnieCoinflip.sol declaration; read at BurnieCoinflip.sol:1133) | BurnieCoinflip.sol:1133 (via `_updateTopDayBettor` from `_addDailyFlip`) | Read of current leaderboard top for day → conditional write at line 1135 if new score is higher. | NO | Leaderboard accumulator; result of read does not feed back into §2 consumer's resolution. Flagged for cross-contract enumeration discipline. |
| 17 | `coinflip` immutable target address (Storage:138, `IBurnieCoinflip(ContractAddresses.COINFLIP)`) | JackpotModule.sol:1906 (`coinflip.creditFlip`), 1985 (`coinflip.creditFlipBatch`) | Cross-contract call target. | n/a | Immutable (declared `internal constant`); not a mutable slot. |

**Per `D-298-SLOT-CLASSIFICATION-01` two-tier:** rows with `Participating? = YES` (#2, #3, #4, #5, #6, #7, #8, #9, #10, #12) proceed to §C writer enumeration + §D verdict matrix. Rows with `NO` are captured but excluded from §C/§D (per `D-298-SLOT-CLASSIFICATION-01`; F-41-02/03 enumeration discipline preserved by listing them here).

---

## CAT-03 (§C) — Per-Participating-Slot Writer Enumeration

For each participating slot, enumerate every external/public function (including OZ-inherited writers, admin/owner, affiliate, and anything reachable from a non-internal entry point) that writes the slot. Each row carries a callsite (file:line). Internal-only writes are enumerated when the internal function is reachable transitively from a non-internal entry. Constructor writes are listed separately under "Pre-deployment" per `Deferred` default.

### Slot #2 — `dailyTicketBudgetsPacked` (Storage:390)

| Writer function | File:Line | Access | Callsite (file:line) |
|-----------------|-----------|--------|----------------------|
| `_packDailyTicketBudgets` (caller-stored) | JackpotModule.sol:2030 | private pure | JackpotModule.sol:406 (in `payDailyJackpot` §1, writes `dailyTicketBudgetsPacked = _packDailyTicketBudgets(...)`) |
| Direct write in `payDailyJackpotCoinAndTickets` | JackpotModule.sol:670 | — | JackpotModule.sol:670 (`dailyTicketBudgetsPacked = 0;` — clears at end of §2) |

External entry reaching writes: `advanceGame()` (DegenerusGame:284 → AdvanceModule stage machine → delegatecall to JackpotModule.payDailyJackpot at AdvanceModule:473 OR delegatecall to JackpotModule.payDailyJackpotCoinAndTickets at AdvanceModule:461).

### Slot #3 — `level` (Storage:250)

| Writer function | File:Line | Access | Callsite (file:line) |
|-----------------|-----------|--------|----------------------|
| `_finalizeRngRequest` (private; sets `level = lvl;` on isTicketJackpotDay && !isRetry) | AdvanceModule.sol:1643 | private | AdvanceModule.sol:1643 (reached from `rawFulfillRandomWords` VRF callback → `_finalizeRngRequest`) |
| Constructor / deploy-time initializer | DegenerusGameStorage.sol:250 (`uint24 public level = 0;`) | n/a | n/a (initialized to 0 at deploy) |

External entry reaching write: `rawFulfillRandomWords` (DegenerusGame:1946; `msg.sender == VRF coordinator`).

### Slot #4 — `jackpotCounter` (Storage:268)

| Writer function | File:Line | Access | Callsite (file:line) |
|-----------------|-----------|--------|----------------------|
| `payDailyJackpotCoinAndTickets` (the consumer itself, line 665 `unchecked { jackpotCounter += counterStep; }`) | JackpotModule.sol:665 | external (via delegatecall) | JackpotModule.sol:665 |
| `payDailyJackpot` (line 506 `unchecked { jackpotCounter += counterStep; }`) | JackpotModule.sol:506 | external (via delegatecall) | JackpotModule.sol:506 |
| `_endPhase` (`jackpotCounter = 0;`) | AdvanceModule.sol:644 | private | AdvanceModule.sol:644 (reached from advanceGame phase transition) |

External entry reaching writes: `advanceGame()` (all paths). Constructor writes 0 implicitly.

### Slot #5 — `dailyIdx` (Storage:236)

| Writer function | File:Line | Access | Callsite (file:line) |
|-----------------|-----------|--------|----------------------|
| `_unlockRng(uint32 day)` (`dailyIdx = day;`) | AdvanceModule.sol:1730 | private | AdvanceModule.sol:1730 (reached from `advanceGame` stage transitions and `rawFulfillRandomWords`) |
| Constructor (`dailyIdx = currentDay;`) | DegenerusGame.sol:219 | n/a | DegenerusGame.sol:219 |

External entry reaching writes: `advanceGame()` and `rawFulfillRandomWords` (VRF callback drives the unlock cycle).

### Slot #6 — `dailyHeroWagers[day][q]` (Storage:1485)

| Writer function | File:Line | Access | Callsite (file:line) |
|-----------------|-----------|--------|----------------------|
| `_placeDegeneretteBetCore` (writes `dailyHeroWagers[day][heroQuadrant] = wPacked;`) | DegeneretteModule.sol:499 | private (reached from external) | DegeneretteModule.sol:499 |
| External entry → `_placeDegeneretteBetCore`: `placeDegeneretteBet(player, currency, amount, count, ticket, heroQuadrant)` | DegeneretteModule.sol:367 | external (no access control; via `_resolvePlayer`) | DegeneretteModule.sol:367 — no `rngLockedFlag` check. Only gate is `lootboxRngWordByIndex[index] != 0` revert (line 452), which during commitment-window is FALSE → bet IS allowed. |

External entry: `placeDegeneretteBet` (callable by anyone via `DegenerusGame.placeDegeneretteBet` and direct on DegeneretteModule if it were initialized — module direct-call hits uninitialized storage). Game-contract entry at `DegenerusGame.sol:placeDegeneretteBet` (game-level wrapper).

### Slot #7 — `levelPrizePool[lvl-1]` (Storage:944)

| Writer function | File:Line | Access | Callsite (file:line) |
|-----------------|-----------|--------|----------------------|
| Constructor (`levelPrizePool[0] = BOOTSTRAP_PRIZE_POOL;`) | DegenerusGame.sol:220 | n/a (deploy) | DegenerusGame.sol:220 |
| `advanceGame` stage machine (`levelPrizePool[purchaseLevel] = _getNextPrizePool();`) | AdvanceModule.sol:422 | private | AdvanceModule.sol:422 (inside `_advancePhase`) |
| `_endPhase` (`levelPrizePool[lvl] = _getFuturePrizePool() / 3;`) | AdvanceModule.sol:642 | private | AdvanceModule.sol:642 |

External entry reaching writes: `advanceGame()`. No other external write path.

### Slot #8 — `ticketQueue[wk]` (Storage:461)

Far-future key (`lvl | TICKET_FAR_FUTURE_BIT`) — the only key consumed by §2 reads at line 1940. Writes via `.push(buyer)` happen via every ticket-queue-write path.

| Writer function | File:Line | Access | Callsite (file:line) |
|-----------------|-----------|--------|----------------------|
| `_queueTickets` (`ticketQueue[wk].push(buyer)` when buyer fresh) | DegenerusGameStorage.sol:580 | internal | DegenerusGameStorage.sol:580 — gated by `if (isFarFuture && rngLockedFlag && !rngBypass) revert RngLocked();` (line 572). |
| `_queueTicketsScaled` (`ticketQueue[wk].push(buyer)`) | DegenerusGameStorage.sol:612 | internal | DegenerusGameStorage.sol:612 — same gate (line 604). |
| `_queueTicketRange` (`ticketQueue[wk].push(buyer)`) | DegenerusGameStorage.sol:666 | internal | DegenerusGameStorage.sol:666 — same gate (line 660). |
| `delete ticketQueue[rk]` (`MintModule.processTicketBatch`) | MintModule.sol:674, 714 | external (delegatecall-only effective) | reached from advanceGame stage machine delegatecall at AdvanceModule.sol:589/607/1516. |

External entries reaching writes (any path that pushes a buyer to a far-future-keyed queue):
- `DegenerusGame.purchase(...)` → MintModule purchase path → `_queueTickets`/`_queueTicketsScaled` (rngLockedFlag-gated for far-future)
- `DegenerusGame.purchaseCoin(...)` → same
- `DegenerusGame.purchaseBurnieLootbox(...)` → same
- `DegenerusGame.purchaseWhaleBundle(...)` → `_queueTicketRange` (rngLockedFlag-gated for far-future)
- `DegenerusGame.purchaseDeityPass(...)` → `_queueTicketRange` (rngLockedFlag-gated AT FUNCTION ENTRY at WhaleModule:543)
- `DegenerusGame.claimWhalePass(...)` → `_queueTicketRange` (rngLockedFlag-gated for far-future at Storage:660)
- `DegenerusGame.placeDegeneretteBet(...)` / `resolveBets(...)` payout via `coinflip.creditFlip`/`_creditClaimable`/`_queueTickets` — Degenerette payout uses `_queueTickets(rngBypass=true)` ONLY when the bet resolves successfully (which requires `lootboxRngWordByIndex[index] != 0` → must be AFTER RNG fulfillment); writes occur during resolution, not during the commitment window — **but resolution timing is player-controlled** (player calls `resolveBets` to trigger payout, which can be during the next-day's rngLocked window).
- `DegenerusGame.runBafJackpot(...)` — self-call from `advanceGame`
- `JackpotModule._jackpotTicketRoll` / `_queueTickets` / `_runEarlyBirdLootboxJackpot` / `_distributeLootboxAndTickets` (all advanceGame-stack-reached writes via `_queueTickets` with `rngBypass=true`)

### Slot #9 — `deityBySymbol[fullSymId]` (Storage:975)

| Writer function | File:Line | Access | Callsite (file:line) |
|-----------------|-----------|--------|----------------------|
| `_purchaseDeityPass` (`deityBySymbol[symbolId] = buyer;`) | WhaleModule.sol:598 | private (reached from external) | WhaleModule.sol:598 |
| External entry → `_purchaseDeityPass`: `purchaseDeityPass(buyer, symbolId)` (`DegenerusGame.purchaseDeityPass` at DegenerusGame.sol:644) | WhaleModule.sol:538 / DegenerusGame.sol:644 | external | WhaleModule.sol:538 — gated `if (rngLockedFlag) revert RngLocked();` at line 543. |

External entry: `purchaseDeityPass` — rngLockedFlag-gated.

### Slot #10 — `traitBurnTicket[lvl][trait]` (Storage:415)

| Writer function | File:Line | Access | Callsite (file:line) |
|-----------------|-----------|--------|----------------------|
| `_raritySymbolBatch` (assembly `sstore` push at MintModule.sol:611-630; appends `player` `occurrences` times to `traitBurnTicket[lvl][traitId]`) | MintModule.sol:537 / write at MintModule.sol:616, 627 | private (reached from external) | MintModule.sol:616 (length increment), 627 (player push). |
| External entries → `_raritySymbolBatch`: `processTicketBatch(uint24 lvl)` (MintModule.sol:662) AND `processFutureTicketBatch(...)` (MintModule.sol:385) — both `external` on MintModule. Effective reach: only via delegatecall from AdvanceModule (direct external call lands on MintModule's uninitialized storage; no game-state effect). | MintModule.sol:662, 385 | external (delegatecall-effective only) | reached from AdvanceModule.sol:589, 607, 1446, 1516 (advanceGame stage). |

External entry: `advanceGame()` only. Direct external call to MintModule.processTicketBatch is per Phase 287 SBS-3 — lands on module's own storage; no game-state effect.

### Slot #12 — `ticketWriteSlot` (Storage:325)

| Writer function | File:Line | Access | Callsite (file:line) |
|-----------------|-----------|--------|----------------------|
| `_swapTicketSlot` (`ticketWriteSlot = !ticketWriteSlot;`) | DegenerusGameStorage.sol:744 | internal | DegenerusGameStorage.sol:744 (reached from `_swapAndFreeze` at Storage:755, called only from AdvanceModule stage transitions) |

External entry reaching write: `advanceGame()` only.

---

## CAT-04 (§D) — Verdict Matrix

Per-(slot × writer × callsite) classification. Strict per `D-298-EXEMPT-REACH-01` (stack-rooted, per-callsite) + `D-298-EXEMPT-CROSSCONTRACT-01` (EXEMPT propagates through static call-graph descendancy across in-source contracts). 3 EXEMPT classes only: `EXEMPT-ADVANCEGAME` (descendant of `advanceGame()` resolution stack), `EXEMPT-VRFCALLBACK` (descendant of `rawFulfillRandomWords`), `EXEMPT-RETRYLOOTBOXRNG` (descendant of `retryLootboxRng`). Everything else = `VIOLATION`. Discretionary "safe by design" dispositions are precluded by the v43.0 milestone goal per `D-298-EXEMPT-REACH-01`.

| Slot | Writer function | Callsite (file:line) | Reached from EXEMPT stack? | Classification |
|------|-----------------|---------------------|----------------------------|----------------|
| #2 dailyTicketBudgetsPacked | `payDailyJackpot` (sets) | JackpotModule.sol:406 | advanceGame → AdvanceModule:473 → delegatecall JackpotModule.payDailyJackpot | EXEMPT-ADVANCEGAME |
| #2 dailyTicketBudgetsPacked | `payDailyJackpotCoinAndTickets` (clears) | JackpotModule.sol:670 | advanceGame → AdvanceModule:461 → delegatecall self-consumer | EXEMPT-ADVANCEGAME |
| #3 level | `_finalizeRngRequest` (`level = lvl;`) | AdvanceModule.sol:1643 | `rawFulfillRandomWords` (VRF callback) → `_finalizeRngRequest` | EXEMPT-VRFCALLBACK |
| #4 jackpotCounter | `payDailyJackpotCoinAndTickets` (`jackpotCounter += counterStep;`) | JackpotModule.sol:665 | advanceGame → AdvanceModule:461 → delegatecall self-consumer | EXEMPT-ADVANCEGAME |
| #4 jackpotCounter | `payDailyJackpot` (`jackpotCounter += counterStep;`) | JackpotModule.sol:506 | advanceGame → AdvanceModule:473 → delegatecall | EXEMPT-ADVANCEGAME |
| #4 jackpotCounter | `_endPhase` (`jackpotCounter = 0;`) | AdvanceModule.sol:644 | advanceGame stage transition | EXEMPT-ADVANCEGAME |
| #5 dailyIdx | `_unlockRng` (`dailyIdx = day;`) | AdvanceModule.sol:1730 | advanceGame stage transitions + rawFulfillRandomWords | EXEMPT-ADVANCEGAME / EXEMPT-VRFCALLBACK |
| #6 dailyHeroWagers[day][q] | `_placeDegeneretteBetCore` (`dailyHeroWagers[day][heroQuadrant] = wPacked;`) | DegeneretteModule.sol:499 | `placeDegeneretteBet` (DegeneretteModule:367 / DegenerusGame:placeDegeneretteBet) — NOT descendant of advanceGame/VRF/retry stacks | **VIOLATION** |
| #7 levelPrizePool[lvl-1] | `_advancePhase` (`levelPrizePool[purchaseLevel] = _getNextPrizePool();`) | AdvanceModule.sol:422 | advanceGame stage | EXEMPT-ADVANCEGAME |
| #7 levelPrizePool[lvl-1] | `_endPhase` (`levelPrizePool[lvl] = _getFuturePrizePool() / 3;`) | AdvanceModule.sol:642 | advanceGame stage | EXEMPT-ADVANCEGAME |
| #8 ticketQueue[far-future key] | `_queueTickets` (`ticketQueue[wk].push(buyer)`) | DegenerusGameStorage.sol:580 — reached from `DegenerusGame.purchase(...)` via MintModule purchase path | NO (external `purchase` is rngLockedFlag-gated INSIDE `_queueTickets` for far-future via line 572, but the gate is bypassed only when `rngBypass=true`; purchase paths call with `rngBypass=false` → revert when rngLocked+farFuture). However, gate enforcement is a runtime revert, not a static-call-graph exclusion. Per `D-298-EXEMPT-REACH-01`, classification is per-callsite based on static descendancy from EXEMPT roots. The `purchase` entry point is NOT a descendant of advanceGame/VRF/retry. | **VIOLATION** |
| #8 ticketQueue[far-future key] | `_queueTickets` reached from `claimWhalePass` (`_queueTicketRange` via WhaleModule) | DegenerusGameStorage.sol:666 — reached from `DegenerusGame.claimWhalePass(...)` | NO (same rngLockedFlag runtime gate; not static descendant of EXEMPT) | **VIOLATION** |
| #8 ticketQueue[far-future key] | `_queueTickets` reached from `purchaseDeityPass` | DegenerusGameStorage.sol:666 — reached from `DegenerusGame.purchaseDeityPass(...)` via WhaleModule | NO (rngLockedFlag gate at WhaleModule:543 + runtime gate at Storage:660) | **VIOLATION** |
| #8 ticketQueue[far-future key] | `_queueTickets` reached from `purchaseWhaleBundle` (`_queueTicketRange`) | DegenerusGameStorage.sol:666 — reached from `DegenerusGame.purchaseWhaleBundle(...)` via WhaleModule | NO (runtime rngLockedFlag gate; not static-EXEMPT) | **VIOLATION** |
| #8 ticketQueue[far-future key] | `_queueTickets` reached from `purchaseCoin` / `purchaseBurnieLootbox` | DegenerusGameStorage.sol:580/612 — reached from MintModule purchase paths | NO (runtime rngLockedFlag gate; not static-EXEMPT) | **VIOLATION** |
| #8 ticketQueue[far-future key] | `_queueTickets` reached from `resolveBets` payout (Degenerette payout via `_queueTickets(rngBypass=true)`) | DegeneretteModule.sol payout sites → DegenerusGameStorage:580 | NO (`resolveBets` is a non-advanceGame external entry — even with `rngBypass=true`, the static call graph does NOT root in `advanceGame()`/`rawFulfillRandomWords`/`retryLootboxRng`) | **VIOLATION** |
| #8 ticketQueue[far-future key] | `_queueTickets` from `runBafJackpot` self-call | JackpotModule._jackpotTicketRoll → DegenerusGameStorage:580 | YES (advanceGame → `runBafJackpot` self-call from advance stack) | EXEMPT-ADVANCEGAME |
| #8 ticketQueue[far-future key] | `_queueTickets` from `_runEarlyBirdLootboxJackpot` / `_distributeLootboxAndTickets` / `_jackpotTicketRoll` reached during jackpot processing | JackpotModule.sol:703/837/1007/2305 → DegenerusGameStorage:580 | YES (advanceGame jackpot phase) | EXEMPT-ADVANCEGAME |
| #8 ticketQueue[far-future key] | `delete ticketQueue[rk]` in `MintModule.processTicketBatch` | MintModule.sol:674, 714 | YES (advanceGame stage delegatecall) | EXEMPT-ADVANCEGAME |
| #9 deityBySymbol[fullSymId] | `_purchaseDeityPass` (`deityBySymbol[symbolId] = buyer;`) | WhaleModule.sol:598 — reached from `DegenerusGame.purchaseDeityPass` | NO (runtime rngLockedFlag gate at WhaleModule:543; not static descendant of EXEMPT stacks) | **VIOLATION** |
| #10 traitBurnTicket[lvl][trait] | `_raritySymbolBatch` (assembly sstore push) | MintModule.sol:616, 627 — reached from `processTicketBatch`/`processFutureTicketBatch` via delegatecall from AdvanceModule | YES (advanceGame → AdvanceModule:589/607/1446/1516 → delegatecall MintModule) | EXEMPT-ADVANCEGAME |
| #12 ticketWriteSlot | `_swapTicketSlot` (`ticketWriteSlot = !ticketWriteSlot;`) | DegenerusGameStorage.sol:744 — reached from `_swapAndFreeze` at advanceGame stage | YES (advanceGame stage transitions only) | EXEMPT-ADVANCEGAME |

**VIOLATION count: 8** (slot #6 × 1 callsite + slot #8 × 6 non-advanceGame writer callsites + slot #9 × 1 callsite).

**EXEMPT count:** 14 callsites (#2 × 2, #3 × 1, #4 × 3, #5 × 1, #7 × 2, #8 × 3, #10 × 1, #12 × 1).

**Cross-call hazard note (echoes Phase 287 §3 row 4-FF + F-41-03 candidate):** Slot #8 (`ticketQueue[far-future key]`) is read at `_awardFarFutureCoinJackpot:1940` once during §2 resolution. Bets / purchases that push to the same far-future key DURING the commitment window will appear in the queue size + queue contents BEFORE the SLOAD. Even where `rngLockedFlag` blocks far-future writes from purchase entries, the gate is a runtime revert, not a static-call exclusion — per `D-298-EXEMPT-REACH-01`, classification is structural. Phase 299 FIX sub-phase planning may choose to claim the runtime gate as the de-facto mitigation when computing the residual surface (see §E rationale).

**`dailyHeroWagers` race specificity:** The slot is keyed by `_simulatedDayIndex()` on the writer side (DegeneretteModule:486) and by storage `dailyIdx` on the reader side (JackpotModule:1609). `dailyIdx` was set by the PREVIOUS day's `_unlockRng`. During §2 resolution, `_simulatedDayIndex()` returns the CURRENT day (the day the advance is processing), while `dailyIdx` still holds the PREVIOUS day's index. Bets placed during §2 commitment-window write slot[currentDay] — the reader at `_rollHeroSymbol(dailyIdx, ...)` reads slot[currentDay-1]. Therefore the §2 consumer is NOT exposed to same-cycle Degenerette wagers on the read it actually performs. The **VIOLATION** stands per `D-298-EXEMPT-REACH-01` strict per-callsite classification (the write IS to a participating slot of this consumer's read graph, just on a future-day index — and `dailyIdx` itself is updated mid-cycle, opening a downstream day's read to manipulation accumulated within this cycle's window).

---

## CAT-06 (§E) — Per-VIOLATION Remediation Tactic

Tactic menu per `D-298-RECOMMEND-DEPTH-01`: `(a) rngLockedFlag-gated revert | (b) snapshot/anchor pattern | (c) pre-lock reorder | (d) immutable`. ONE tactic + ≤80-char rationale per VIOLATION row.

| # | Slot / writer / callsite | Tactic | Rationale (≤80 chars) |
|---|--------------------------|--------|------------------------|
| 1 | #6 dailyHeroWagers / `_placeDegeneretteBetCore` / DegeneretteModule.sol:499 | (b) | Phase 288 dailyIdx snapshot precedent; freeze read-day at lock time, not call-time. |
| 2 | #8 ticketQueue[far-future] / `_queueTickets` from `DegenerusGame.purchase` / Storage:580 | (a) | Add rngLockedFlag check at queue-write site for ALL far-future entries (no rngBypass). |
| 3 | #8 ticketQueue[far-future] / `_queueTickets` from `claimWhalePass` / Storage:666 | (a) | rngLockedFlag gate already present at line 660; promote to unconditional far-future revert. |
| 4 | #8 ticketQueue[far-future] / `_queueTickets` from `purchaseDeityPass` / Storage:666 | (a) | WhaleModule:543 gate already exists; sufficient. Confirm structural propagation. |
| 5 | #8 ticketQueue[far-future] / `_queueTickets` from `purchaseWhaleBundle` / Storage:666 | (a) | rngLockedFlag gate at Storage:660 for far-future; promote to all-callsite invariant. |
| 6 | #8 ticketQueue[far-future] / `_queueTickets` from `purchaseCoin` / `purchaseBurnieLootbox` / Storage:580/612 | (a) | Same far-future rngLockedFlag gate at Storage:572/604; already enforced. |
| 7 | #8 ticketQueue[far-future] / `_queueTickets` from `resolveBets` (Degenerette payout, rngBypass=true) / Storage:580 | (b) | Snapshot far-future queue length at lock-time, OR pre-lock-reorder payout to non-far-future levels only during rngLocked window. |
| 8 | #9 deityBySymbol / `_purchaseDeityPass` / WhaleModule.sol:598 | (a) | rngLockedFlag-revert gate at WhaleModule:543 already in place; confirm sufficient. |

---

*Catalog section: 298-02 — JackpotModule.payDailyJackpotCoinAndTickets*
*Authored: 2026-05-18 (Phase 298 CATALOG, parallel-dispatch agent §2)*
*Audit-only artifact per D-43N-AUDIT-ONLY-01 — zero contracts/* + zero test/* mutations*
