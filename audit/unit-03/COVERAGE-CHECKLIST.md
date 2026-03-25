# Unit 3: Jackpot Distribution -- Coverage Checklist

## Contracts Under Audit
- contracts/modules/DegenerusGameJackpotModule.sol (2,715 lines)
  - Inherits: DegenerusGamePayoutUtils -> DegenerusGameStorage
  - Executes via: delegatecall from DegenerusGame
  - Storage context: DegenerusGame's shared storage layout (102 variables, slots 0-78)
- contracts/modules/DegenerusGamePayoutUtils.sol (92 lines)
  - Abstract contract, 3 internal helpers for payout primitives
  - Inherited by JackpotModule -- treated as part of the same unit per D-04/D-05

## Methodology
- Per D-01: Categories B/C/D only (no Category A -- these are modules, not the router)
- Per D-04/D-05: Both contracts audited as single unit. PayoutUtils functions get Category C treatment within JackpotModule's call trees.
- Per D-06: BAF-critical functions flagged [BAF-CRITICAL] and prioritized Tier 1
- Per D-07: _processAutoRebuy re-audited from scratch (v4.4 fix NOT trusted)
- Per D-10: Fresh RNG analysis (Phase 104 findings NOT trusted for JackpotModule's RNG usage)

## Checklist Summary

| Category | Count | Analysis Depth |
|----------|-------|---------------|
| B: External State-Changing | 7 | Full Mad Genius (per D-02): recursive call tree, storage-write map, cached-local-vs-storage, 10-angle attack |
| C: Internal Helpers (State-Changing) | 28 | Via caller call tree; standalone for [MULTI-PARENT] (per D-03) |
| D: View/Pure | 20 | Minimal; RNG derivation functions and assembly get extra scrutiny |
| **TOTAL** | **55** | |

**Count discrepancy vs research:** Research listed 35C + 13D = 48 non-B functions. Independent verification reclassified 7 functions from C to D:
- C27 `_calcAutoRebuy` (PayoutUtils L38-72): `internal pure`, zero storage writes -- moved to D16
- C30 `_validateTicketBudget` (L1024-1031): `private view`, zero storage writes -- moved to D17
- C31 `_packDailyTicketBudgets` (L2676-2687): `private pure` -- moved to D18
- C32 `_unpackDailyTicketBudgets` (L2689-2705): `private pure` -- moved to D19
- C33 `_selectCarryoverSourceOffset` (L2631-2674): `private view` -- moved to D20
- C34 `_highestCarryoverSourceOffset` (L2613-2626): `private view` -- moved to D21 (note: merged with D20 below for adjacency)
- C35 `_rollRemainder` (L2024-2031): `private pure` -- moved to D22 (note: merged numbering below)

The state-changing function count (requiring full Mad Genius analysis) drops from 42 to 35 (7B + 28C). The total function count remains 55.

**Inherited Storage Helpers (not counted):** The following inherited functions from DegenerusGameStorage are called by functions in this unit but are NOT counted as JackpotModule/PayoutUtils functions. They are noted in storage-write columns where relevant: `_queueTickets`, `_getNextPrizePool`, `_getFuturePrizePool`, `_setNextPrizePool`, `_setFuturePrizePool`, `_getPrizePools`, `_tqReadKey`, `_tqFarFutureKey`, `_simulatedDayIndex`.

---

## Category B: External State-Changing Functions

Full Mad Genius treatment per D-02: recursive call tree with line numbers, storage-write map, cached-local-vs-storage check, 10-angle attack analysis.

| # | Function | Lines | Access Control | Storage Writes | External Calls | Risk Tier | Subsystem | Analyzed? | Call Tree? | Storage Map? | Cache Check? |
|---|----------|-------|---------------|----------------|---------------|-----------|-----------|-----------|------------|--------------|-------------|
| B1 | `runTerminalJackpot()` | 272-308 | `msg.sender == ContractAddresses.GAME` (OnlyGame revert) | claimableWinnings[winners] (via C12->C13->C14->C3), claimablePool (via C12), whalePassClaims[winner] (via C14->C16), futurePrizePool (via C16->_setFuturePrizePool, C3->C4->_setFuturePrizePool/_setNextPrizePool) | coin.creditFlip (via C15->C14 payCoin path) | 2 | ETH-DIST | YES | YES | YES | YES |
| B2 | `payDailyJackpot()` | 313-637 | external (delegatecall from advanceGame) | currentPrizePool (L391, L503), futurePrizePool (via _setFuturePrizePool at L418, L604, L778, and via C3->C4), nextPrizePool (via _setNextPrizePool at L392, L434, L834, L1058), dailyEthPoolBudget (L382), dailyTicketBudgetsPacked (L447), dailyCarryoverEthPool (L455), dailyEthPhase (L457, L530), dailyCarryoverWinnerCap (L508-516), dailyJackpotCoinTicketsPending (via _clearDailyEthState), lastDailyJackpotWinningTraits (via C24), lastDailyJackpotLevel (via C24), lastDailyJackpotDay (via C24), claimableWinnings[winners] (via C11->C3, C9->C10->C12->C13->C14->C3), claimablePool (via C11, C12), ticketQueue (via C1, C5->C6->C7->C8, C3->C4->_queueTickets), whalePassClaims (via C14->C16) | coin.rollDailyQuest (L637), coin.creditFlip (via C14->C15 payCoin path) | 1 (CRITICAL) | ETH-DIST | YES | YES | YES | YES |
| B3 | `payDailyJackpotCoinAndTickets()` | 652-737 | external (delegatecall); gated by `dailyJackpotCoinTicketsPending` | jackpotCounter (L728), dailyJackpotCoinTicketsPending=false (L732), dailyTicketBudgetsPacked=0 (L733), ticketQueue (via C6->C7->C8->_queueTickets) | coin.creditFlipBatch (via C22), coin.creditFlip (via C22), coin.rollDailyQuest (L736), coin.creditFlipBatch (via C23) | 2 | COIN-JACKPOT + TICKET-DIST | YES | YES | YES | YES |
| B4 | `awardFinalDayDgnrsReward()` | 744-769 | external (delegatecall) | none (external transfer only) | dgnrs.poolBalance (L745, view), dgnrs.transferFromPool (L763) | 2 | COIN-JACKPOT | YES | YES | YES | YES |
| B5 | `consolidatePrizePools()` | 850-879 | external (delegatecall) | yieldAccumulator (L856, via C2 L913), futurePrizePool (via _setFuturePrizePool L855, L870, and via C2->C3->C4), currentPrizePool (L860, L871), nextPrizePool (via _setNextPrizePool L861), claimableWinnings (via C2->C3 for VAULT and SDGNRS), claimablePool (via C2 L911) | coin.creditFlip (via C29 L2274), steth.balanceOf (via C2 L884, view) | 1 | POOL-MGMT | YES | YES | YES | YES |
| B6 | `processTicketBatch()` | 1812-1873 | external (delegatecall) | ticketLevel (L1819), ticketCursor (L1820, L1863, L1827, L1868), ticketQueue[rk] (delete L1826, L1867), ticketsOwedPacked[rk][player] (via C18->C17, C18->C21), traitBurnTicket[lvl][traitId] (via C18->C19->C20 assembly SSTORE) | none | 1 | TICKET-DIST | YES | YES | YES | YES |
| B7 | `payDailyCoinJackpot()` | 2283-2324 | external (delegatecall) | lastDailyJackpotWinningTraits (via C24 if traits not loaded), lastDailyJackpotLevel (via C24), lastDailyJackpotDay (via C24) | coin.creditFlipBatch (via C22, C23), coin.creditFlip (via C22) | 2 | COIN-JACKPOT | YES | YES | YES | YES |

**Risk Tier Key:**
- **Tier 1** (3 functions: B2, B5, B6): BAF-critical paths, complex multi-path logic, prize pool accounting, inline assembly.
  - B2 payDailyJackpot: 325-line function with 3 major paths (daily fresh/resume, early-burn). Manages currentPrizePool, futurePrizePool, nextPrizePool. Calls _addClaimableEth through multiple chains. THE primary BAF-class target in this unit.
  - B5 consolidatePrizePools: Pool merging, yield surplus distribution, calls _addClaimableEth for VAULT and SDGNRS addresses. Prize pool accounting across 4 pools.
  - B6 processTicketBatch: Gas-bounded iteration with cursor resume logic. Inline Yul assembly in _raritySymbolBatch with manual storage slot calculation. State consistency on interruption.
- **Tier 2** (4 functions: B1, B3, B4, B7): Significant ETH/coin flows, deep call chains.
  - B1 runTerminalJackpot: Terminal jackpot via _distributeJackpotEth bucket system. Calls _addClaimableEth through C12->C13->C14 chain.
  - B3 payDailyJackpotCoinAndTickets: Phase 2 coin+ticket distribution. External calls to BurnieCoin. Ticket distribution via _distributeTicketJackpot.
  - B4 awardFinalDayDgnrsReward: DGNRS reward to solo bucket winner. External transfer via dgnrs.transferFromPool.
  - B7 payDailyCoinJackpot: BURNIE jackpot with 75/25 near/far-future split. External calls to BurnieCoin.

---

## Category C: Internal Helpers (State-Changing)

Traced via parent call trees per D-03. Functions marked **[MULTI-PARENT]** get standalone analysis for differing cached-local contexts. Functions marked **[BAF-CRITICAL]** are on the original BAF cache-overwrite bug path. Functions marked **[BAF-PATH]** are in call chains that reach _addClaimableEth. Functions marked **[ASSEMBLY]** contain inline Yul.

| # | Function | Lines | Contract | Called By | Storage Writes | Flags | Analyzed? | Call Tree? | Storage Map? | Cache Check? |
|---|----------|-------|----------|----------|----------------|-------|-----------|------------|--------------|-------------|
| C1 | `_runEarlyBirdLootboxJackpot()` | 772-835 | JackpotModule | B2 | futurePrizePool (via _setFuturePrizePool L778), nextPrizePool (via _setNextPrizePool L834), ticketQueue (via _queueTickets L819) | | YES | YES | YES | YES |
| C2 | `_distributeYieldSurplus()` | 883-914 | JackpotModule | B5 | claimableWinnings (via C3 for VAULT, SDGNRS addresses), claimablePool (L911), yieldAccumulator (L913) | [BAF-PATH] | YES | YES | YES | YES |
| C3 | `_addClaimableEth()` | 928-949 | JackpotModule | C2, C11, C14 (via C15), C16 (via C15), C12 (via C13->C14->C15/C16) | claimableWinnings[beneficiary] (via C26 _creditClaimable L947), OR futurePrizePool/nextPrizePool (via C4 _processAutoRebuy L982-984), ticketQueue (via C4->_queueTickets L979), claimableWinnings[player] (via C4->C26 L988) | **[MULTI-PARENT] [BAF-CRITICAL]** | YES | YES | YES | YES |
| C4 | `_processAutoRebuy()` | 959-999 | JackpotModule | C3 | futurePrizePool (via _setFuturePrizePool L982) or nextPrizePool (via _setNextPrizePool L984), ticketQueue (via _queueTickets L979), claimableWinnings[player] (via C26 _creditClaimable L988) | **[BAF-CRITICAL]** | YES | YES | YES | YES |
| C5 | `_distributeLootboxAndTickets()` | 1050-1073 | JackpotModule | B2 | nextPrizePool (via _setNextPrizePool L1058), ticketQueue (via C6->C7->C8->_queueTickets) | | YES | YES | YES | YES |
| C6 | `_distributeTicketJackpot()` | 1076-1109 | JackpotModule | C5, B3 | ticketQueue (via C7->C8->_queueTickets) | **[MULTI-PARENT]** | YES | YES | YES | YES |
| C7 | `_distributeTicketsToBuckets()` | 1112-1146 | JackpotModule | C6 | ticketQueue (via C8->_queueTickets) | | YES | YES | YES | YES |
| C8 | `_distributeTicketsToBucket()` | 1149-1190 | JackpotModule | C7 | ticketQueue (via _queueTickets L1180) | | YES | YES | YES | YES |
| C9 | `_executeJackpot()` | 1280-1294 | JackpotModule | B2 (early-burn path) | claimableWinnings, claimablePool (via C10->C12->C13->C14->C3) | | YES | YES | YES | YES |
| C10 | `_runJackpotEthFlow()` | 1297-1322 | JackpotModule | C9 | claimableWinnings, claimablePool (via C12) | | YES | YES | YES | YES |
| C11 | `_processDailyEth()` | 1338-1433 | JackpotModule | B2 (daily Phase 0 and Phase 1) | claimableWinnings[winners] (via C3 L1407), claimablePool (L1430) | **[BAF-PATH]** | YES | YES | YES | YES |
| C12 | `_distributeJackpotEth()` | 1435-1474 | JackpotModule | B1, C10 | claimableWinnings (via C13->C14->C3), claimablePool (L1471), whalePassClaims (via C14->C16), futurePrizePool (via C14->C16->_setFuturePrizePool, C14->C3->C4) | **[MULTI-PARENT] [BAF-PATH]** | YES | YES | YES | YES |
| C13 | `_processOneBucket()` | 1477-1504 | JackpotModule | C12 | claimableWinnings (via C14->C3), whalePassClaims (via C14->C16), futurePrizePool (via C14->C16, C14->C3->C4) | | YES | YES | YES | YES |
| C14 | `_resolveTraitWinners()` | 1528-1655 | JackpotModule | C13 | claimableWinnings (via C3 L1627, via C16->C15->C3), claimablePool (aggregated by caller), whalePassClaims (via C16 L1709), futurePrizePool (via C16 L1710, via C3->C4) | **[BAF-PATH]** | YES | YES | YES | YES |
| C15 | `_creditJackpot()` | 1663-1676 | JackpotModule | C14 | claimableWinnings (via C3 if ETH path L1674) or coin.creditFlip (if coin path L1670, external) | | YES | YES | YES | YES |
| C16 | `_processSoloBucketWinner()` | 1684-1717 | JackpotModule | C14 | claimableWinnings (via C15->C3 L1706/L1714), whalePassClaims[winner] (L1709), futurePrizePool (via _setFuturePrizePool L1710) | **[BAF-PATH]** | YES | YES | YES | YES |
| C17 | `_resolveZeroOwedRemainder()` | 1877-1904 | JackpotModule | C18 | ticketsOwedPacked[rk][player] (L1888, L1895, L1901) | | YES | YES | YES | YES |
| C18 | `_processOneTicketEntry()` | 1907-1970 | JackpotModule | B6 | ticketsOwedPacked[rk][player] (via C17, C21), traitBurnTicket[lvl][traitId] (via C19->C20 assembly) | | YES | YES | YES | YES |
| C19 | `_generateTicketBatch()` | 1973-1993 | JackpotModule | C18 | traitBurnTicket[lvl][traitId] (via C20 assembly SSTORE) | | YES | YES | YES | YES |
| C20 | `_raritySymbolBatch()` | 2050-2145 | JackpotModule | C19 | traitBurnTicket[lvl][traitId] -- manual slot math via inline Yul: keccak256(lvl, traitBurnTicket.slot) + traitId for array length, keccak256(elem) for data start. Raw SSTORE of player address. | **[ASSEMBLY]** | YES | YES | YES | YES |
| C21 | `_finalizeTicketEntry()` | 1996-2021 | JackpotModule | C18 | ticketsOwedPacked[rk][player] (L2018) | | YES | YES | YES | YES |
| C22 | `_awardDailyCoinToTraitWinners()` | 2341-2438 | JackpotModule | B3, B7 | none (external calls only: coin.creditFlipBatch L2411/L2437, coin.creditFlip via batch) | **[MULTI-PARENT]** | YES | YES | YES | YES |
| C23 | `_awardFarFutureCoinJackpot()` | 2444-2529 | JackpotModule | B3, B7 | none (external calls only: coin.creditFlipBatch L2510/L2527) | **[MULTI-PARENT]** | YES | YES | YES | YES |
| C24 | `_syncDailyWinningTraits()` | 2550-2558 | JackpotModule | B2, B7 | lastDailyJackpotWinningTraits (L2555), lastDailyJackpotLevel (L2556), lastDailyJackpotDay (L2557) | **[MULTI-PARENT]** | YES | YES | YES | YES |
| C25 | `_clearDailyEthState()` | 2708-2714 | JackpotModule | B2 | dailyEthPhase=0 (L2709), dailyEthPoolBudget=0 (L2710), dailyCarryoverEthPool=0 (L2711), dailyCarryoverWinnerCap=0 (L2712), dailyJackpotCoinTicketsPending=true (L2713) | | YES | YES | YES | YES |
| C26 | `_creditClaimable()` | PU:30-36 | PayoutUtils | C3, C4 | claimableWinnings[beneficiary] (PU:33) | | YES | YES | YES | YES |
| C27 | `_queueWhalePassClaimCore()` | PU:75-91 | PayoutUtils | (not called directly from JackpotModule; available for EndgameModule) | whalePassClaims[winner] (PU:82), claimableWinnings[winner] (PU:86), claimablePool (PU:88) | | YES | YES | YES | YES |
| C28 | `_creditDgnrsCoinflip()` | 2269-2275 | JackpotModule | B5 | none (external call: coin.creditFlip L2274) | | YES | YES | YES | YES |

**Multi-parent function index (7 functions):**

| Function | Parents | Why Standalone Analysis Required |
|----------|---------|--------------------------------|
| C3 `_addClaimableEth` | C2 (_distributeYieldSurplus), C11 (_processDailyEth loop), C14 (_resolveTraitWinners normal bucket), C16 (via C15 _creditJackpot from _processSoloBucketWinner), C12 (via C13->C14) | BAF-CRITICAL: each caller may have different storage cached; auto-rebuy path writes futurePrizePool/nextPrizePool |
| C6 `_distributeTicketJackpot` | C5 (_distributeLootboxAndTickets from B2), B3 (payDailyJackpotCoinAndTickets) | Different entropy sources and maxWinners parameters |
| C12 `_distributeJackpotEth` | B1 (runTerminalJackpot), C10 (_runJackpotEthFlow from B2 early-burn) | Called with terminal params vs daily params; different ethPool sources |
| C22 `_awardDailyCoinToTraitWinners` | B3 (payDailyJackpotCoinAndTickets), B7 (payDailyCoinJackpot) | Same logic but different callers with different entropy derivation |
| C23 `_awardFarFutureCoinJackpot` | B3 (payDailyJackpotCoinAndTickets), B7 (payDailyCoinJackpot) | Same as above -- different callers, different entropy |
| C24 `_syncDailyWinningTraits` | B2 (payDailyJackpot at L333/L582), B7 (payDailyCoinJackpot at L2305) | Different level and trait sources; B7 may roll fresh traits when cache misses |
| C27 `_queueWhalePassClaimCore` | (available from PayoutUtils inheritance; not directly called from JackpotModule Category B functions -- used by EndgameModule) | Included per D-04/D-05 for completeness; multi-module availability |

**C-numbering note vs research:** Research used C1-C35 with C30-C35 as view/pure helpers. This checklist reclassifies those 6 functions (plus C27 _calcAutoRebuy) to Category D and renumbers the remaining 28 state-changing helpers as C1-C28. Cross-reference:

| Research # | Checklist # | Function | Change |
|-----------|-------------|----------|--------|
| C1-C26 (minus C27 _calcAutoRebuy) | C1-C26 | (same) | C26 _creditClaimable keeps its number |
| C27 _calcAutoRebuy | D16 | `_calcAutoRebuy` | Reclassified: `internal pure`, zero storage writes |
| C28 _queueWhalePassClaimCore | C27 | `_queueWhalePassClaimCore` | Renumbered |
| C29 _creditDgnrsCoinflip | C28 | `_creditDgnrsCoinflip` | Renumbered |
| C30 _validateTicketBudget | D17 | `_validateTicketBudget` | Reclassified: `private view` |
| C31 _packDailyTicketBudgets | D18 | `_packDailyTicketBudgets` | Reclassified: `private pure` |
| C32 _unpackDailyTicketBudgets | D19 | `_unpackDailyTicketBudgets` | Reclassified: `private pure` |
| C33 _selectCarryoverSourceOffset | D20 | `_selectCarryoverSourceOffset` | Reclassified: `private view` |
| C34 _highestCarryoverSourceOffset | D21 | `_highestCarryoverSourceOffset` | Reclassified: `private view` |
| C35 _rollRemainder | D22 | `_rollRemainder` | Reclassified: `private pure` |

---

## Category D: View/Pure Functions

Read-only functions. No state changes. Minimal audit depth: verify correct reads/computation. RNG derivation functions and assembly helpers get extra scrutiny.

| # | Function | Lines | Reads/Computes | Security Note | Subsystem | Reviewed? |
|---|----------|-------|---------------|---------------|-----------|-----------|
| D1 | `_hasTraitTickets()` | 1002-1021 | `traitBurnTicket[lvl][trait].length`, `deityBySymbol[fullSymId]` | View: checks if any packed traits have real tickets or virtual deity entries. Deity virtual entry gate: `fullSymId < 32 && deityBySymbol[fullSymId] != address(0)`. | ETH-DIST / TICKET-DIST | YES |
| D2 | `_budgetToTicketUnits()` | 1034-1041 | `PriceLookupLib.priceForLevel(lvl)` | Pure: converts ETH budget to ticket units via `(budget << 2) / ticketPrice`. Returns 0 if ticketPrice is 0. No overflow risk (Solidity 0.8.34). | TICKET-DIST | YES |
| D3 | `_computeBucketCounts()` | 1193-1245 | `traitBurnTicket[lvl][trait].length`, `deityBySymbol[fullSymId]` | View: computes winner counts for active trait buckets with even distribution + entropy-based remainder. | ETH-DIST / TICKET-DIST | YES |
| D4 | `_futureKeepBps()` | 1252-1267 | Pure: `keccak256(rngWord, FUTURE_KEEP_TAG)` | Pure: 5-dice roll with [0-3] range each, mapped to 3000-5333 BPS (30-53.3%). Range bounds: total in [0,15], BPS in [3000, 3000+15*3500/15] = [3000, 6500]. | POOL-MGMT | YES |
| D5 | `_getWinningTraits()` | 1729-1763 | `dailyHeroWagers[day][q]` (via `_topHeroSymbol`), `randomWord` bits | View: derives 4 winning trait IDs. Base: sym=0 with random color for Q0/Q1/Q2, fully random Q3. Hero override: top daily hero symbol auto-wins its quadrant. RNG: direct bit extraction (3 bits per color, 6 bits for Q3). | TRAIT-SELECTION | YES |
| D6 | `_topHeroSymbol()` | 1767-1795 | `dailyHeroWagers[day][q]` -- packed 32-bit amounts per symbol | View: finds top hero symbol by wagered amount. Iterates 4 quadrants x 8 symbols = 32 entries. Deterministic tie-break: first seen (q asc, symbol asc). | TRAIT-SELECTION | YES |
| D7 | `_randTraitTicket()` | 2160-2203 | `traitBurnTicket_[trait]`, `deityBySymbol[fullSymId]` | View: selects random winners via `slice % effectiveLen`. Duplicates intentionally allowed. Virtual deity entries: `floor(len/50)`, minimum 2. **RNG note:** Bit rotation (16-bit shift) for subsequent winners -- not cryptographically independent but acceptable for jackpot selection. **Modulo bias:** present if effectiveLen not power-of-2 (known/intentional per docs). | WINNER-SELECTION | YES |
| D8 | `_randTraitTicketWithIndices()` | 2206-2260 | Same as D7 plus `ticketIndexes` output | View: same selection as D7 plus ticket indices for event emission. Deity entries get `ticketIndex = type(uint256).max`. Same RNG note as D7. | WINNER-SELECTION | YES |
| D9 | `_calculateDayIndex()` | 2265-2267 | Delegates to `_simulatedDayIndex()` (inherited from DegenerusGameStorage) | View: day index calculation. Single wrapper. | TIMING | YES |
| D10 | `_rollWinningTraits()` | 2533-2548 | `JackpotBucketLib.packWinningTraits()`, `_getWinningTraits()`, `JackpotBucketLib.getRandomTraits()` | View: rolls or derives packed winning traits. `useBurnCounts=true` uses hero override (D5). `useBurnCounts=false` uses fully random traits. `lvl` parameter is unused (assigned to itself, dead code). | TRAIT-SELECTION | YES |
| D11 | `_loadDailyWinningTraits()` | 2560-2567 | `lastDailyJackpotWinningTraits`, `lastDailyJackpotDay`, `lastDailyJackpotLevel` | View: loads stored daily winning traits. Validity check: day and level must match current values. | STATE-CACHE | YES |
| D12 | `_calcDailyCoinBudget()` | 2570-2574 | `price`, `levelPrizePool[lvl-1]` | View: calculates 0.5% of prize pool target in BURNIE. Formula: `(levelPrizePool[lvl-1] * PRICE_COIN_UNIT) / (price * 200)`. Returns 0 if price is 0. **Note:** Uses `lvl-1` for prize pool lookup (previous level's pool). | COIN-JACKPOT | YES |
| D13 | `_dailyCurrentPoolBps()` | 2579-2592 | Pure: `keccak256(randWord, DAILY_CURRENT_BPS_TAG, counter)` | Pure: days 1-4 random 6%-14%, day 5+ returns 10000 (100%). `range = 1400 - 600 + 1 = 801`. `seed % 801` gives uniform [0,800], mapped to [600,1400] BPS. | ETH-DIST | YES |
| D14 | `_hasActualTraitTickets()` | 2595-2609 | `traitBurnTicket[lvl][traitIds[i]].length` | View: checks for non-virtual (real) trait tickets. Unlike D1, does NOT check deity virtual entries. Used for carryover source selection. | CARRYOVER | YES |
| D15 | `_selectDailyCoinTargetLevel()` | 2328-2338 | `_hasTraitTickets()` (D1) | View: picks random level in [lvl, lvl+4] for coin jackpot. `entropy % 5` for uniform level selection. Returns 0 if chosen level has no eligible tickets. | COIN-JACKPOT | YES |
| D16 | `_calcAutoRebuy()` | PU:38-72 | Pure: `EntropyLib.entropyStep()`, `PriceLookupLib.priceForLevel()` | Pure (PayoutUtils): computes auto-rebuy parameters. **Confirmed pure:** Zero storage reads, zero storage writes. Level offset: `(entropy & 3) + 1` gives [1,4] levels ahead. `toFuture = (offset > 1)` means +1 -> next (25%), +2/+3/+4 -> future (75%). Take-profit: `(weiAmount / takeProfit) * takeProfit` rounds down. Bonus: 130% base, 145% afKing. | BAF-PAYOUT | YES |
| D17 | `_validateTicketBudget()` | 1024-1031 | `_hasTraitTickets()` (D1) | View: zeros budget if no trait tickets exist for given level/traits. Simple gate function. | TICKET-DIST | YES |
| D18 | `_packDailyTicketBudgets()` | 2676-2687 | Pure: bit packing | Pure: packs counterStep (8 bits), dailyTicketUnits (64 bits @ 8), carryoverTicketUnits (64 bits @ 72), carryoverSourceOffset (8 bits @ 136). | PACKING | YES |
| D19 | `_unpackDailyTicketBudgets()` | 2689-2705 | Pure: bit unpacking | Pure: inverse of D18. Uses uint64 casts for ticket units (truncates to 64 bits). | PACKING | YES |
| D20 | `_selectCarryoverSourceOffset()` | 2631-2674 | `_highestCarryoverSourceOffset()` (D21), `_hasActualTraitTickets()` (D14) | View: selects random eligible carryover source offset in [1..highest]. Wrapping probe starting from random point. Returns 0 if no eligible offsets. | CARRYOVER | YES |
| D21 | `_highestCarryoverSourceOffset()` | 2613-2626 | `_hasActualTraitTickets()` (D14) | View: scans [1..5] offsets in reverse, returns highest with actual tickets. Returns 0 if none eligible. | CARRYOVER | YES |
| D22 | `_rollRemainder()` | 2024-2031 | Pure: `EntropyLib.entropyStep()` | Pure: `(rollEntropy % TICKET_SCALE) < rem` where TICKET_SCALE=100. Fractional ticket roll. rem in [0,99]. Fair if entropyStep output is uniform. | TICKET-DIST | YES |

---

## BAF-Critical Call Chains

Every path from a Category B entry point to `_addClaimableEth` (C3). For each chain, the Mad Genius must verify: does any ancestor cache `futurePrizePool`, `nextPrizePool`, `currentPrizePool`, or `claimablePool` in a local variable that could become stale after C3/C4 writes?

### Chain 1: B2 -> C11 -> C3 (payDailyJackpot Phase 0 daily ETH distribution)
```
B2 payDailyJackpot() [L313]
  -> caches: poolSnapshot = currentPrizePool [L353]
  -> _processDailyEth(lvl, budget, ...) [L495] = C11
     -> loops over 4 buckets, per winner:
        -> _addClaimableEth(w, perWinner, entropyState) [L1407] = C3
           -> if autoRebuy:
              -> _processAutoRebuy() [L941] = C4
                 -> _setFuturePrizePool(_getFuturePrizePool() + ethSpent) [L982]
                 -> OR _setNextPrizePool(_getNextPrizePool() + ethSpent) [L984]
                 -> _creditClaimable(player, reserved) [L988] = C26
              -> returns calc.reserved
           -> else: _creditClaimable(beneficiary, weiAmount) [L947] = C26
              -> returns weiAmount
     -> claimablePool += liabilityDelta [L1430]
  -> currentPrizePool -= paidDailyEth [L503]

KEY CHECK: B2 caches poolSnapshot [L353] but only uses it for budget calculation [L364].
The write at L503 uses currentPrizePool (fresh storage read). C4 writes futurePrizePool/
nextPrizePool, NOT currentPrizePool. poolSnapshot is NOT written back.
C11 does NOT cache futurePrizePool or nextPrizePool locally.
```

### Chain 2: B2 -> C11 -> C3 (payDailyJackpot Phase 1 carryover distribution)
```
B2 payDailyJackpot() [L535]
  -> carryPool = dailyCarryoverEthPool [L536] (not a prize pool -- daily-scoped)
  -> _processDailyEth(carryoverSourceLevel, carryPool, ...) [L565] = C11
     -> (same chain as Chain 1 -- C3 -> C4 writes to futurePrizePool/nextPrizePool)
  -> _clearDailyEthState() [L575] = C25

KEY CHECK: No prize pool locals are cached in the Phase 1 path. carryPool is the
daily carryover budget, not a prize pool.
```

### Chain 3: B2 -> C9 -> C10 -> C12 -> C13 -> C14 -> C3 (early-burn path)
```
B2 payDailyJackpot() [L617]
  -> _executeJackpot(jp) [L617] = C9
     -> _runJackpotEthFlow(jp, ...) [L1292] = C10
        -> _distributeJackpotEth(lvl, ethPool, ...) [L1314] = C12
           -> loops over 4 buckets:
              -> _processOneBucket(ctx, ...) [L1458] = C13
                 -> _resolveTraitWinners(false, ...) [L1491] = C14
                    -> normal bucket: _addClaimableEth(w, perWinner, ...) [L1627] = C3
                       -> C4 may write futurePrizePool/nextPrizePool
                    -> solo bucket: _processSoloBucketWinner(w, ...) [L1611] = C16
                       -> _creditJackpot(false, winner, ethAmount, ...) [L1706] = C15
                          -> _addClaimableEth(winner, ethAmount, ...) [L1674] = C3
                       -> _setFuturePrizePool(_getFuturePrizePool() + whalePassCost) [L1710]
           -> claimablePool += ctx.liabilityDelta [L1471]

KEY CHECK: C12 uses JackpotEthCtx struct with liabilityDelta, totalPaidEth, entropyState,
lvl -- NONE of which are prize pool values. C14 does not cache prize pools.
C16 reads fresh _getFuturePrizePool() before write [L1710].
B2 early-burn path: ethDaySlice is deducted from futurePrizePool upfront [L604]
before calling C9. No stale cache.
```

### Chain 4: B1 -> C12 -> C13 -> C14 -> C3 (runTerminalJackpot)
```
B1 runTerminalJackpot() [L272]
  -> _distributeJackpotEth(targetLvl, poolWei, ...) [L300] = C12
     -> (same sub-chain as Chain 3: C12 -> C13 -> C14 -> C3/C16)

KEY CHECK: B1 receives poolWei as parameter, does not cache any prize pool storage values.
C12's ctx struct does not cache prize pools. Same safety analysis as Chain 3.
```

### Chain 5: B5 -> C2 -> C3 (consolidatePrizePools -> _distributeYieldSurplus)
```
B5 consolidatePrizePools() [L850]
  -> yieldAccumulator operations [L853-856]
  -> currentPrizePool += _getNextPrizePool() [L860]
  -> _setNextPrizePool(0) [L861]
  -> x00 keep-roll: fp = _getFuturePrizePool() [L865], then _setFuturePrizePool(keepWei) [L870]
  -> _creditDgnrsCoinflip(currentPrizePool) [L876] = C28 (external only)
  -> _distributeYieldSurplus(rngWord) [L878] = C2
     -> obligations = currentPrizePool + _getNextPrizePool() + claimablePool +
        _getFuturePrizePool() + yieldAccumulator [L886-890]
     -> _addClaimableEth(VAULT, stakeholderShare, rngWord) [L901] = C3
        -> C4 may write futurePrizePool/nextPrizePool (if VAULT has autoRebuy -- unlikely for contract address)
     -> _addClaimableEth(SDGNRS, stakeholderShare, rngWord) [L906] = C3
        -> C4 may write futurePrizePool/nextPrizePool (if SDGNRS has autoRebuy -- unlikely)
     -> claimablePool += claimableDelta [L911]
     -> yieldAccumulator += accumulatorShare [L913]

KEY CHECK: C2 computes `obligations` [L886-890] as a snapshot for surplus comparison only
[L892]. `obligations` is NOT written back to storage. After the comparison, fresh storage
reads are used for all writes (claimablePool L911, yieldAccumulator L913).
B5's prize pool writes [L855-871] all complete BEFORE C2 is called [L878].
HOWEVER: B5 does not cache any pool values across the C2 call boundary.
VAULT and SDGNRS are contract addresses that almost certainly do NOT have autoRebuy
enabled, so C4 is likely unreachable here. But the Mad Genius must verify this assumption.
```

### Chain 6: B2 -> C1 -> no C3 path (earlybird lootbox -- does NOT reach _addClaimableEth)
```
B2 payDailyJackpot() [L368]
  -> _runEarlyBirdLootboxJackpot(lvl+1, randWord) [L369] = C1
     -> _setFuturePrizePool(_getFuturePrizePool() - reserveContribution) [L778]
     -> _queueTickets(winner, ...) [L819]
     -> _setNextPrizePool(_getNextPrizePool() + totalBudget) [L834]

KEY CHECK: C1 does NOT call _addClaimableEth. No BAF chain here.
B2 caches no prize pool values before calling C1. C1's futurePrizePool deduction [L778]
uses fresh _getFuturePrizePool() reads.
```

---

## Cross-Module External Calls

External calls made by JackpotModule (not delegatecall -- actual cross-contract calls). Per D-08, traced for state coherence only. Full internals audited in their own unit phases.

| Call | From Functions | Target Contract | State Impact | Notes |
|------|---------------|----------------|-------------|-------|
| `coin.creditFlip(addr, amount)` | C15 (L1670), C28 (L2274), B2 (indirectly via coin.rollDailyQuest L637) | BurnieCoin | BURNIE minting to specified address | One-way call. No callback into JackpotModule. |
| `coin.creditFlipBatch(players, amounts)` | C22 (L2411, L2437), C23 (L2510, L2527) | BurnieCoin | Batch BURNIE minting (3 recipients per call) | One-way call. No callback. |
| `coin.rollDailyQuest(day, rngWord)` | B2 (L637), B3 (L736) | BurnieCoin | Quest state update | One-way call. No return value used. |
| `dgnrs.transferFromPool(pool, to, amount)` | B4 (L763) | StakedDegenerusStonk | sDGNRS transfer from reward pool | One-way transfer. Only in awardFinalDayDgnrsReward. |
| `dgnrs.poolBalance(pool)` | B4 (L745) | StakedDegenerusStonk | View only: reward pool balance query | Read-only. No state change. |
| `steth.balanceOf(address(this))` | C2 (L884) | Lido stETH | View only: stETH balance query | Read-only. Used for yield surplus calculation. |

**State coherence note:** All external calls are either view-only or one-way writes to other contracts. None of these calls write to DegenerusGame storage (the delegatecall context). No callback risk -- BurnieCoin, StakedDegenerusStonk, and stETH are trusted internal protocol contracts with no reentrancy paths back into JackpotModule.

---

## RNG/Entropy Usage Map

All RNG words arrive as parameters from advanceGame (verified in Phase 104). JackpotModule's RNG usage is this phase's responsibility per D-10.

| Usage | Function(s) | Entropy Derivation | Source | Concern |
|-------|------------|-------------------|--------|---------|
| Winner selection | D7 `_randTraitTicket`, D8 `_randTraitTicketWithIndices` | `randomWord ^ (trait << 128) ^ (salt << 192)`, then 16-bit rotation per winner: `(slice >> 16) \| (slice << 240)` | VRF word (parameter) | Modulo bias if `effectiveLen` not power-of-2 (known/intentional). Bit rotation provides pseudo-independence between winner picks. |
| Trait rolling (burn-weighted) | D5 `_getWinningTraits` | Direct bit extraction: 3 bits per color (Q0-Q2), 6 bits for Q3 | VRF word (parameter) | Hero override reads `dailyHeroWagers` from storage. Storage read is current (not stale). |
| Trait rolling (random) | D10 `_rollWinningTraits` | Via `JackpotBucketLib.getRandomTraits(randWord)` | VRF word (parameter) | Library function. Full audit in Phase 117. |
| Bucket sizing | B2, B1 | Via `JackpotBucketLib.bucketCountsForPoolCap()` and `soloBucketIndex()` | VRF-derived entropy | Library audit deferred to Phase 117. soloBucketIndex: `entropy & 3` (2-bit extraction). |
| Solo bucket index | C11, C14 | `JackpotBucketLib.soloBucketIndex(entropy)` | VRF-derived entropy | 2-bit extraction: uniform over [0,3]. |
| Auto-rebuy level offset | D16 `_calcAutoRebuy` | `EntropyLib.entropyStep(entropy ^ player ^ weiAmount) & 3` -> [0,3] + 1 = [1,4] | VRF-derived, XORed with player address and amount | Entropy step provides mixing. Per-player uniqueness via XOR. |
| Daily BPS roll | D13 `_dailyCurrentPoolBps` | `keccak256(randWord, DAILY_CURRENT_BPS_TAG, counter) % 801` | VRF word + counter | Range [600, 1400] BPS. 801 is not power-of-2; negligible modulo bias (2^256 >> 801). |
| Future keep BPS | D4 `_futureKeepBps` | 5 dice: `keccak256(rngWord, FUTURE_KEEP_TAG)`, 4-bit extraction per die (% 4) | VRF word | Range [3000, 6500] BPS. Die values [0,3] with 16-bit shifts. Modulo bias for `% 4`: zero (4 divides all power-of-2 extractions). |
| Carryover source selection | D20 `_selectCarryoverSourceOffset` | `keccak256(randWord, DAILY_CARRYOVER_SOURCE_TAG, counter) % highestEligible` | VRF word + counter | Wrapping probe. `highestEligible` in [1,5]; negligible modulo bias. |
| LCG trait generation (assembly) | C20 `_raritySymbolBatch` | `seed = (baseKey + groupIdx) ^ entropyWord`, then `s * TICKET_LCG_MULT + 1` (Knuth MMIX) | VRF-derived (lastLootboxRngWord passed through) | LCG with full period (odd seed guaranteed). Trait distribution via DegenerusTraitUtils.traitFromWord. Deterministic given seed -- player could predict trait distribution if they know queue position and VRF word. Economic impact: low (traits affect jackpot eligibility, not direct value). |
| Far-future level selection | C23 `_awardFarFutureCoinJackpot` | `entropy % 95` for level in [lvl+5, lvl+99] | VRF-derived | 95 is not power-of-2; negligible modulo bias. |
| Daily coin target level | D15 `_selectDailyCoinTargetLevel` | `entropy % 5` | VRF-derived | Uniform over [0,4]. `% 5`: negligible bias. |
| Ticket remainder roll | D22 `_rollRemainder` | `EntropyLib.entropyStep(entropy ^ rollSalt) % 100` | VRF-derived + deterministic salt | `TICKET_SCALE = 100`. Fair if entropyStep output is uniform mod 100. |

---

## Completeness Verification

**Independent source scan results:** Read all 2,715 lines of DegenerusGameJackpotModule.sol and all 92 lines of DegenerusGamePayoutUtils.sol. Every `function` keyword was verified:

| Total functions found in source | 55 |
|--------------------------------|-----|
| Category B (external state-changing) | 7 |
| Category C (internal/private state-changing) | 28 |
| Category D (view/pure) | 20 |
| Functions missing from checklist | 0 |
| Functions in checklist not in source | 0 |

**Discrepancy from research (55 total matches, categorization differs):**
- Research: 7B + 35C + 13D = 55
- Checklist: 7B + 28C + 20D = 55
- Difference: 7 functions reclassified from C to D (all confirmed view/pure with zero storage writes)

**MULTI-PARENT functions verified (7):**
1. C3 `_addClaimableEth` -- called from C2, C11, C14 (via C15), C16 (via C15)
2. C6 `_distributeTicketJackpot` -- called from C5 (B2 path) and B3
3. C12 `_distributeJackpotEth` -- called from B1 and C10 (B2 early-burn path)
4. C22 `_awardDailyCoinToTraitWinners` -- called from B3 and B7
5. C23 `_awardFarFutureCoinJackpot` -- called from B3 and B7
6. C24 `_syncDailyWinningTraits` -- called from B2 and B7
7. C27 `_queueWhalePassClaimCore` -- inherited from PayoutUtils, available to all inheritors

**BAF-CRITICAL functions (2):** C3 `_addClaimableEth`, C4 `_processAutoRebuy`
**ASSEMBLY functions (1):** C20 `_raritySymbolBatch`
**BAF-PATH functions (5):** C2, C11, C12, C14, C16

**Category A: NONE.** Per D-01, these modules do not dispatch delegatecalls as routers. They ARE the targets of delegatecalls from the router (DegenerusGame.sol).
