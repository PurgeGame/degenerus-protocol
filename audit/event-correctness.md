# Event Correctness Audit

**Date:** 2026-03-27
**Scope:** All 26 production contract files + 5 libraries (22 top-level contracts + 4 periphery contracts + 5 libraries)
**Methodology:** Three-pass verification per external/public state-changing function:
1. Event exists for the state change
2. Emitted parameter values match actual post-state (no stale locals, no pre-update snapshots)
3. Indexer-critical transitions emit sufficient data for off-chain reconstruction

**Disposition policy:** DOCUMENT per Phase 130 D-05. No contract code changes. All findings will be pre-disclosed in KNOWN-ISSUES.md (Phase 134).

**Indexed field policy (D-04):** Indexed fields evaluated against the indexer-critical standard -- events used for off-chain reconstruction must index filterable fields (addresses, IDs). Cosmetic/bookkeeping events are not penalized for missing indexes.

**Architecture note:** The game system uses a delegatecall-module architecture. DegenerusGame delegates to 10 specialized modules. Events emitted in modules execute in DegenerusGame's context -- this is correct behavior and not flagged.

---

## Finding Summary

| Category | Count | Severity | Disposition |
|----------|-------|----------|-------------|
| Missing event for state change | 25 | INFO | DOCUMENT |
| Stale/incorrect event parameter | 2 | INFO | DOCUMENT |
| Missing indexed field (indexer-critical) | 2 | INFO | DOCUMENT |
| Missing old+new value in parameter change event | 0 | -- | -- |
| Unused event declaration | 1 | INFO | DOCUMENT |
| **Total** | **30** | **INFO** | **DOCUMENT** |

**Zero parameter correctness bugs** found across all ~200+ emit statements. All events emit values computed from post-state or from the same computation that produced the state change.

## Statistics

| Metric | Value |
|--------|-------|
| Contracts audited | 26 (+ 5 libraries) |
| State-changing functions audited | ~200 |
| Events declared | ~70 |
| Emit statements analyzed | ~200+ |
| Findings | 30 (all INFO, all DOCUMENT) |

---

## Game System Contracts

---

## DegenerusGameStorage (DegenerusGameStorage.sol)

### Event Inventory

| Event | Parameters | Indexed Fields | Purpose |
|-------|-----------|----------------|---------|
| TraitsGenerated | player, level, queueIdx, startIndex, count, entropy | player, level | Indexer: trait generation tracking |
| TicketsQueued | buyer, targetLevel, quantity | buyer | Indexer: ticket queue tracking |
| TicketsQueuedScaled | buyer, targetLevel, quantityScaled | buyer | Indexer: scaled ticket queue tracking |
| TicketsQueuedRange | buyer, startLevel, numLevels, ticketsPerLevel | buyer | Indexer: range ticket queue tracking |

### Assessment

DegenerusGameStorage is the shared storage contract inherited by all modules. It declares 4 events used by internal ticket/trait queue functions. These events are emitted by `_queueTickets`, `_queueLootboxTickets`, `_queueTicketRange`, and `_generateTraits` -- internal functions called from multiple modules.

**Parameter correctness:** All 4 events emit values that are computed immediately before the emit (no stale locals). The `TicketsQueued` event emits `targetLevel` and `quantity` as passed to the queue function; `TicketsQueuedRange` emits `startLevel`, `numLevels`, `ticketsPerLevel` matching the actual queued parameters.

### Findings

No findings -- events correctly reflect actual queued state.

---

## DegenerusGame (DegenerusGame.sol) -- Router

### Event Inventory

| Event | Parameters | Indexed Fields | Purpose |
|-------|-----------|----------------|---------|
| LootboxRngThresholdUpdated | previous, current | (none) | Admin config change |
| OperatorApproval | owner, operator, approved | owner, operator | Player approval tracking |
| WinningsClaimed | player, caller, amount | player, caller | Indexer-critical: ETH claim |
| ClaimableSpent | player, amount, newBalance, payKind, costWei | player | Mint payment tracking |
| AffiliateDgnrsClaimed | affiliate, level, caller, score, amount | affiliate, level, caller | Indexer: affiliate DGNRS claims |
| AutoRebuyToggled | player, enabled | player | Config change |
| DecimatorAutoRebuyToggled | player, enabled | player | Config change |
| AutoRebuyTakeProfitSet | player, takeProfit | player | Config change |
| AfKingModeToggled | player, enabled | player | Config change |

### Function-by-Function Audit

| Function | State Changes | Event Emitted | Params Match Post-State | Indexer-Critical | Finding |
|----------|--------------|---------------|------------------------|-----------------|---------|
| `advanceGame()` | Delegatecalls to AdvanceModule | Events emitted inside module | N/A (traced in AdvanceModule section) | Yes | -- |
| `wireVrf(...)` | Delegatecalls to AdvanceModule | Events emitted inside module | N/A (traced in AdvanceModule section) | No | -- |
| `recordMint(...)` | Updates prize pools, mint data, earlybird | ClaimableSpent (if claimable used) | Yes -- emitted at line 980 after state update (line 949/967), params match: `claimableUsed`, `newClaimableBalance`, `payKind`, `amount` | No | -- |
| `recordMintQuestStreak(...)` | Updates mintPacked_ streak fields | None | N/A | No | EVT-GAME-01 |
| `payCoinflipBountyDgnrs(...)` | Transfers DGNRS from reward pool | None | N/A | No | EVT-GAME-02 |
| `setOperatorApproval(...)` | Updates operatorApprovals mapping | OperatorApproval | Yes -- emitted after storage write (line 471 after line 470) | No | -- |
| `setLootboxRngThreshold(...)` | Updates lootboxRngThreshold | LootboxRngThresholdUpdated | Yes -- emits both prev and new values | No | -- |
| `purchase(...)` | Delegatecalls to MintModule | Events emitted inside module | N/A (traced in MintModule section) | No | -- |
| `purchaseCoin(...)` | Delegatecalls to MintModule | Events emitted inside module | N/A (traced in MintModule section) | No | -- |
| `purchaseBurnieLootbox(...)` | Delegatecalls to MintModule | Events emitted inside module | N/A (traced in MintModule section) | No | -- |
| `purchaseWhaleBundle(...)` | Delegatecalls to WhaleModule | Events emitted inside module | N/A (traced in WhaleModule section) | No | -- |
| `purchaseLazyPass(...)` | Delegatecalls to WhaleModule | Events emitted inside module | N/A (traced in WhaleModule section) | No | -- |
| `purchaseDeityPass(...)` | Delegatecalls to WhaleModule | Events emitted inside module | N/A (traced in WhaleModule section) | No | -- |
| `openLootBox(...)` | Delegatecalls to LootboxModule | Events emitted inside module | N/A (traced in LootboxModule section) | Yes | -- |
| `openBurnieLootBox(...)` | Delegatecalls to LootboxModule | Events emitted inside module | N/A (traced in LootboxModule section) | No | -- |
| `placeFullTicketBets(...)` | Delegatecalls to DegeneretteModule | Events emitted inside module | N/A (traced in DegeneretteModule section) | No | -- |
| `resolveDegeneretteBets(...)` | Delegatecalls to DegeneretteModule | Events emitted inside module | N/A (traced in DegeneretteModule section) | Yes | -- |
| `consumeCoinflipBoon(...)` | Delegatecalls to BoonModule | No event (state-only return) | N/A | No | -- |
| `consumeDecimatorBoon(...)` | Delegatecalls to BoonModule | No event (state-only return) | N/A | No | -- |
| `consumePurchaseBoost(...)` | Delegatecalls to BoonModule | No event (state-only return) | N/A | No | -- |
| `issueDeityBoon(...)` | Delegatecalls to LootboxModule | Events emitted inside module | N/A (traced in LootboxModule section) | No | -- |
| `recordDecBurn(...)` | Delegatecalls to DecimatorModule | Events emitted inside module | N/A (traced in DecimatorModule section) | No | -- |
| `runDecimatorJackpot(...)` | Delegatecalls to DecimatorModule | Events emitted inside module | N/A (traced in DecimatorModule section) | Yes | -- |
| `recordTerminalDecBurn(...)` | Delegatecalls to DecimatorModule | Events emitted inside module | N/A (traced in DecimatorModule section) | No | -- |
| `runTerminalDecimatorJackpot(...)` | Delegatecalls to DecimatorModule | Events emitted inside module | N/A (traced in DecimatorModule section) | Yes | -- |
| `runTerminalJackpot(...)` | Delegatecalls to JackpotModule | Events emitted inside module | N/A (traced in JackpotModule section) | Yes | -- |
| `consumeDecClaim(...)` | Delegatecalls to DecimatorModule | Events emitted inside module | N/A (traced in DecimatorModule section) | No | -- |
| `claimDecimatorJackpot(...)` | Delegatecalls to DecimatorModule | Events emitted inside module | N/A (traced in DecimatorModule section) | Yes | -- |
| `claimWinnings(...)` | Decrements claimableWinnings and claimablePool, transfers ETH/stETH | WinningsClaimed | Yes -- emitted at line 1367 with `payout = amount - 1`, after state update at line 1363-1366 | Yes | -- |
| `claimWinningsStethFirst()` | Same as claimWinnings | WinningsClaimed | Yes -- same internal function | Yes | -- |
| `claimAffiliateDgnrs(...)` | Transfers DGNRS, updates levelDgnrsClaimed, marks claimed | AffiliateDgnrsClaimed | Yes -- emitted at line 1426 after all state updates. `score` and `paid` are actual values used. | Yes | -- |
| `setAutoRebuy(...)` | Updates autoRebuyState.autoRebuyEnabled | AutoRebuyToggled | Yes -- emitted at line 1493 after state update at line 1491 | No | -- |
| `setDecimatorAutoRebuy(...)` | Updates decimatorAutoRebuyDisabled | DecimatorAutoRebuyToggled | Yes -- emitted at line 1472 after state update at line 1470 | No | -- |
| `setAutoRebuyTakeProfit(...)` | Updates autoRebuyState.takeProfit | AutoRebuyTakeProfitSet | Yes -- emitted at line 1509 after state update at line 1507 | No | -- |
| `setAfKingMode(...)` | Updates autoRebuyState (multiple fields), coinflip state | AutoRebuyToggled, AutoRebuyTakeProfitSet, AfKingModeToggled | Yes -- each emitted after respective state update | No | -- |
| `deactivateAfKingFromCoin(...)` | Clears afKingMode/afKingActivatedLevel | AfKingModeToggled | Yes -- emitted at line 1685 after state clear at 1683-1684 | No | -- |
| `syncAfKingLazyPassFromCoin(...)` | Clears afKingMode/afKingActivatedLevel | AfKingModeToggled | Yes -- emitted at line 1670 after state clear at 1668-1669 | No | -- |
| `claimWhalePass(...)` | Delegatecalls to EndgameModule | Events emitted inside module | N/A (traced in EndgameModule section) | No | -- |
| `resolveRedemptionLootbox(...)` | Moves ETH from claimable to futurePrizePool, delegatecalls to LootboxModule | No direct event (module events inside) | N/A | No | EVT-GAME-03 |
| `adminSwapEthForStEth(...)` | Transfers stETH to recipient | None | N/A | No | EVT-GAME-04 |
| `adminStakeEthForStEth(...)` | Stakes ETH into Lido stETH | None | N/A | No | EVT-GAME-05 |
| `updateVrfCoordinatorAndSub(...)` | Delegatecalls to AdvanceModule | Events emitted inside module | N/A (traced in AdvanceModule section) | Yes | -- |
| `requestLootboxRng()` | Delegatecalls to AdvanceModule | Events emitted inside module | N/A (traced in AdvanceModule section) | No | -- |
| `reverseFlip()` | Delegatecalls to AdvanceModule | Events emitted inside module | N/A (traced in AdvanceModule section) | No | -- |
| `rawFulfillRandomWords(...)` | Delegatecalls to AdvanceModule | Events emitted inside module | N/A (traced in AdvanceModule section) | Yes | -- |

### Findings

**EVT-GAME-01: `recordMintQuestStreak` emits no event** -- INFO
- Function updates `mintPacked_[player]` streak fields (significant player stat change).
- Assessment: Low impact. Streak data is derivable from on-chain state. The COIN contract that calls this function emits its own quest completion events. No indexer requires this specific transition.
- Disposition: DOCUMENT

**EVT-GAME-02: `payCoinflipBountyDgnrs` emits no event** -- INFO
- Function transfers DGNRS from reward pool to player. The `dgnrs.transferFromPool()` call triggers an ERC-20 `Transfer` event on the sDGNRS contract, so the transfer is observable.
- Assessment: Low impact. The Transfer event on sDGNRS is sufficient for indexers tracking DGNRS rewards.
- Disposition: DOCUMENT

**EVT-GAME-03: `resolveRedemptionLootbox` emits no top-level event for the accounting reclassification** -- INFO
- Moves ETH from claimablePool to futurePrizePool (significant accounting change) without a dedicated event. The delegatecalled lootbox module emits its own resolution events.
- Assessment: Low impact. The lootbox resolution events inside the module provide sufficient granularity. The accounting reclassification is an internal optimization.
- Disposition: DOCUMENT

**EVT-GAME-04: `adminSwapEthForStEth` emits no event** -- INFO
- Admin-only function that swaps ETH for stETH. The stETH.transfer() emits an ERC-20 Transfer event.
- Assessment: Low impact. Admin actions are observable via Transfer events on stETH. A dedicated event would aid monitoring dashboards.
- Disposition: DOCUMENT

**EVT-GAME-05: `adminStakeEthForStEth` emits no event** -- INFO
- Admin-only function that stakes ETH into Lido. Lido's `submit()` emits its own events.
- Assessment: Low impact. Lido events provide sufficient traceability.
- Disposition: DOCUMENT

---

## DegenerusGameGameOverModule (DegenerusGameGameOverModule.sol)

### Event Inventory

| Event | Parameters | Indexed Fields | Purpose |
|-------|-----------|----------------|---------|
| PlayerCredited | player, recipient, amount | player, recipient | Indexer-critical: ETH credit to claimable |

### Function-by-Function Audit

| Function | State Changes | Event Emitted | Params Match Post-State | Indexer-Critical | Finding |
|----------|--------------|---------------|------------------------|-----------------|---------|
| `handleGameOverDrain(day)` | Sets gameOver, gameOverTime, gameOverFinalJackpotPaid; updates claimablePool, claimableWinnings; clears prize pools; distributes via decimator/terminal jackpot | PlayerCredited (via nested delegatecalls for deity pass refunds at line 101); delegated jackpot events in JackpotModule/DecimatorModule | Partial -- see finding | Yes | EVT-GAMEOVER-01 |
| `handleFinalSweep()` | Sets finalSwept, clears claimablePool, sweeps funds to vault/DGNRS/GNRUS | None | N/A | Yes | EVT-GAMEOVER-02 |

### Findings

**EVT-GAMEOVER-01: `handleGameOverDrain` does not emit a top-level GameOver event** -- INFO
- The function sets `gameOver = true` and `gameOverTime` at lines 120-121, then distributes funds. There is no explicit `GameOver` event.
- Assessment: The `gameOver` flag and `gameOverTime` are readable on-chain, and the nested delegatecalls to `runTerminalDecimatorJackpot` and `runTerminalJackpot` emit their own payout events. However, an indexer monitoring for the game-over transition must poll storage rather than listen for events.
- For deity pass refunds (lines 91-114): The `claimableWinnings[owner] += refund` writes emit NO event per player. The refund loop credits players without emitting `PlayerCredited`. This is a gap -- deity pass refund credits are silent.
- Disposition: DOCUMENT (the deity pass refund credit silence is the more notable gap)

**EVT-GAMEOVER-02: `handleFinalSweep` emits no event** -- INFO
- Sets `finalSwept = true`, clears `claimablePool`, and sweeps all funds via `_sendToVault`. No event emitted at any point in this function or `_sendToVault`.
- Assessment: The stETH/ETH transfers emit their own Transfer events, but the final sweep state transition (`finalSwept`) has no dedicated event. An indexer must poll `finalSwept` storage.
- Disposition: DOCUMENT

---

## DegenerusGameEndgameModule (DegenerusGameEndgameModule.sol)

### Event Inventory

| Event | Parameters | Indexed Fields | Purpose |
|-------|-----------|----------------|---------|
| AutoRebuyExecuted | player, ethAmount, ticketsAwarded, targetLevel | player | Indexer: auto-rebuy conversion tracking |
| RewardJackpotsSettled | lvl, futurePool, claimableDelta | lvl | Indexer-critical: BAF/Decimator pool changes |
| AffiliateDgnrsReward | affiliate, level, dgnrsAmount | affiliate, level | Indexer: top affiliate reward |
| WhalePassClaimed | player, caller, halfPasses, startLevel | player, caller | Indexer: whale pass claim tracking |

### Function-by-Function Audit

| Function | State Changes | Event Emitted | Params Match Post-State | Indexer-Critical | Finding |
|----------|--------------|---------------|------------------------|-----------------|---------|
| `rewardTopAffiliate(lvl)` | Transfers DGNRS to top affiliate, updates levelDgnrsAllocation | AffiliateDgnrsReward | Yes -- `paid` is the actual return value from `transferFromPool()` at line 141, emitted at line 142 | Yes | -- |
| `runRewardJackpots(lvl, rngWord)` | Updates futurePrizePool (with rebuy delta reconciliation), claimablePool; nested BAF/Decimator delegatecalls | RewardJackpotsSettled | Yes -- emitted at line 253 with `futurePoolLocal + rebuyDelta` (post-reconciliation) and `claimableDelta` (accumulated across all jackpot types) | Yes | -- |
| `claimWhalePass(player)` | Clears whalePassClaims, queues tickets, updates whale pass stats | WhalePassClaimed | Yes -- emitted at line 558 after `whalePassClaims[player] = 0` (line 547). `halfPasses` is the value read before clear. `startLevel = level + 1` matches actual ticket range start. | Yes | -- |
| `_addClaimableEth(...)` (private) | Updates claimableWinnings or converts to tickets via auto-rebuy | PlayerCredited (via `_creditClaimable`) or AutoRebuyExecuted | PlayerCredited: Yes (emitted inside `_creditClaimable` after write). AutoRebuyExecuted: Yes -- `calc.rebuyAmount`, `calc.ticketCount`, `calc.targetLevel` are computed values matching actual state changes. | No | -- |
| `_runBafJackpot(...)` (private) | Calls JackpotModule for winners, distributes ETH/lootbox | PlayerCredited, AutoRebuyExecuted (via _addClaimableEth), TicketsQueued/TicketsQueuedScaled (via ticket queue functions) | Yes -- all events emitted through helper functions that emit after state writes | Yes | -- |

### Findings

No findings -- all events correctly reflect post-state values. The `RewardJackpotsSettled` event is particularly well-designed with the `rebuyDelta` reconciliation ensuring the emitted `futurePool` matches actual storage.

---

## DegenerusGameBoonModule (DegenerusGameBoonModule.sol)

### Event Inventory

No events declared in this module.

### Function-by-Function Audit

| Function | State Changes | Event Emitted | Params Match Post-State | Indexer-Critical | Finding |
|----------|--------------|---------------|------------------------|-----------------|---------|
| `consumeCoinflipBoon(player)` | Clears coinflip boon fields in boonPacked[player].slot0 | None | N/A | No | EVT-BOON-01 |
| `consumePurchaseBoost(player)` | Clears purchase boost fields in boonPacked[player].slot0 | None | N/A | No | EVT-BOON-01 |
| `consumeDecimatorBoost(player)` | Clears decimator boost fields in boonPacked[player].slot0 | None | N/A | No | EVT-BOON-01 |
| `checkAndClearExpiredBoon(player)` | Clears expired boon fields across both packed slots | None | N/A | No | EVT-BOON-01 |
| `consumeActivityBoon(player)` | Clears activity boon, updates mintPacked_ levelCount, awards quest streak bonus | None | N/A | No | EVT-BOON-01 |

### Findings

**EVT-BOON-01: No events in BoonModule for boon consumption** -- INFO
- All 5 external functions modify packed boon state (clearing tiers, days, expiry checks) without emitting events.
- Assessment: Boon consumption is an internal game mechanic triggered by other contracts (LootboxModule, Coin, Coinflip). The callers of these functions (e.g., `consumeCoinflipBoon` called from DegenerusGame router, which is called by Coinflip) have their own event trails. Boon state changes are low-frequency and not indexer-critical.
- Disposition: DOCUMENT

---

## DegenerusGamePayoutUtils (DegenerusGamePayoutUtils.sol)

### Event Inventory

| Event | Parameters | Indexed Fields | Purpose |
|-------|-----------|----------------|---------|
| PlayerCredited | player, recipient, amount | player, recipient | Indexer-critical: ETH credit to claimable |

### Function-by-Function Audit

| Function | State Changes | Event Emitted | Params Match Post-State | Indexer-Critical | Finding |
|----------|--------------|---------------|------------------------|-----------------|---------|
| `_creditClaimable(beneficiary, weiAmount)` (internal) | Increments claimableWinnings[beneficiary] | PlayerCredited | Yes -- emitted at line 35 after `claimableWinnings[beneficiary] += weiAmount` at line 33. `player` and `recipient` are both `beneficiary` (self-credit). | Yes | -- |
| `_queueWhalePassClaimCore(winner, amount)` (internal) | Increments whalePassClaims[winner], may credit remainder to claimableWinnings | PlayerCredited (for remainder only) | Yes -- `PlayerCredited` emitted at line 89 for the sub-HALF_WHALE_PASS_PRICE remainder after `claimableWinnings[winner] += remainder` at line 86 and `claimablePool += remainder` at line 88. | No | -- |

### Findings

No findings -- events correctly reflect post-state. The `PlayerCredited` event is emitted with correct values in both `_creditClaimable` and the remainder path in `_queueWhalePassClaimCore`.

---

## DegenerusGameMintStreakUtils (DegenerusGameMintStreakUtils.sol)

### Event Inventory

No events declared in this module.

### Function-by-Function Audit

| Function | State Changes | Event Emitted | Params Match Post-State | Indexer-Critical | Finding |
|----------|--------------|---------------|------------------------|-----------------|---------|
| `_recordMintStreakForLevel(player, mintLevel)` (internal) | Updates mintPacked_ streak fields | None | N/A | No | -- |
| `_mintStreakEffective(player, currentMintLevel)` (view) | None (view function) | N/A | N/A | No | -- |

### Findings

No findings. These are internal/view helpers. The streak update is a derived stat change, not an indexer-critical transition. The calling context (MintModule/WhaleModule) emits its own purchase events.

---

## DegenerusGameWhaleModule (DegenerusGameWhaleModule.sol)

### Event Inventory

| Event | Parameters | Indexed Fields | Purpose |
|-------|-----------|----------------|---------|
| LootBoxBoostConsumed | player, day, originalAmount, boostedAmount, boostBps | player, day | Lootbox boost tracking |
| LootBoxIndexAssigned | buyer, index, day | buyer, index, day | Indexer-critical: lootbox assignment |

### Function-by-Function Audit

| Function | State Changes | Event Emitted | Params Match Post-State | Indexer-Critical | Finding |
|----------|--------------|---------------|------------------------|-----------------|---------|
| `purchaseWhaleBundle(buyer, quantity)` | Updates mintPacked_, queues tickets (100 levels), distributes DGNRS, splits ETH to pools, records lootbox entry | TicketsQueued (via _queueTickets, 100x), LootBoxIndexAssigned (if new lootbox entry), LootBoxBoostConsumed (if boost active) | TicketsQueued: Yes -- emitted inside _queueTickets with correct level and quantity. LootBoxIndexAssigned: Yes -- emitted at line 734 with current index and dayIndex. | No | EVT-WHALE-01 |
| `purchaseLazyPass(buyer)` | Updates mintPacked_, activates 10-level pass, queues tickets, splits ETH to pools, records lootbox entry | TicketsQueued (via _activate10LevelPass, 10x), LootBoxIndexAssigned (if new entry), LootBoxBoostConsumed (if boost active) | Yes -- same helper functions as whale bundle | No | EVT-WHALE-01 |
| `purchaseDeityPass(buyer, symbolId)` | Updates deityPassCount, deityPassPurchasedCount, deityPassOwners, deityPassSymbol, deityBySymbol, deityPassPaidTotal, mintPacked_; mints ERC721; queues tickets; distributes DGNRS; splits ETH to pools; records lootbox entry | TicketsQueued (via _queueTickets, 100x), LootBoxIndexAssigned (if new entry), LootBoxBoostConsumed (if boost active), ERC721 Transfer event from DeityPass.mint() | Yes -- ticket events match queue parameters; ERC721 event is from external contract. | Yes | EVT-WHALE-01, EVT-WHALE-02 |

### Findings

**EVT-WHALE-01: No top-level purchase event for whale bundle, lazy pass, or deity pass** -- INFO
- All three purchase functions change significant state (ETH received, tickets queued, DGNRS distributed, lootbox assigned) but emit no top-level "WhaleBundlePurchased" / "LazyPassPurchased" / "DeityPassPurchased" event.
- Assessment: The component events (TicketsQueued x100, LootBoxIndexAssigned, DGNRS Transfer) provide sufficient granularity for indexers to reconstruct purchase activity. However, an indexer must aggregate multiple events to detect a single purchase action. The `msg.value` received by the contract is not directly emitted anywhere except indirectly through pool split accounting.
- Disposition: DOCUMENT

**EVT-WHALE-02: `purchaseDeityPass` is an indexer-critical transition with no dedicated event** -- INFO
- Deity pass purchase is a significant game event (one of max 32 passes, symbol assignment, ERC721 mint). The state changes include `deityBySymbol[symbolId] = buyer` and `deityPassOwners.push(buyer)`.
- Assessment: The ERC721 `Transfer` event from `DeityPass.mint(buyer, symbolId)` provides the most critical data (who got which symbol). Additional state like `deityPassPaidTotal` is not emitted but is readable on-chain.
- Disposition: DOCUMENT

---

## Indexer-Critical Transition Coverage (Task 1 Contracts)

| Transition | Contract | Event | Sufficient Data? | Finding |
|-----------|----------|-------|------------------|---------|
| Game over | GameOverModule | None (gameOver flag set silently) | No dedicated event | EVT-GAMEOVER-01 |
| Final sweep | GameOverModule | None (finalSwept flag set silently) | No dedicated event | EVT-GAMEOVER-02 |
| ETH credit to claimable | PayoutUtils | PlayerCredited | Yes -- player, recipient, amount | -- |
| Jackpot payout (BAF/Decimator) | EndgameModule | RewardJackpotsSettled | Yes -- level, futurePool, claimableDelta | -- |
| Whale pass claim | EndgameModule | WhalePassClaimed | Yes -- player, caller, halfPasses, startLevel | -- |
| Top affiliate reward | EndgameModule | AffiliateDgnrsReward | Yes -- affiliate, level, dgnrsAmount | -- |
| ETH winnings claimed | DegenerusGame | WinningsClaimed | Yes -- player, caller, amount | -- |
| Affiliate DGNRS claimed | DegenerusGame | AffiliateDgnrsClaimed | Yes -- affiliate, level, caller, score, amount | -- |
| Deity pass purchase | WhaleModule | No dedicated event (ERC721 Transfer from external) | Partial (ERC721 Transfer only) | EVT-WHALE-02 |
| Lootbox assignment | WhaleModule | LootBoxIndexAssigned | Yes -- buyer, index, day | -- |

---

## Finding Summary (Task 1)

| ID | Severity | Contract | Description | Disposition |
|----|----------|----------|-------------|-------------|
| EVT-GAME-01 | INFO | DegenerusGame | `recordMintQuestStreak` emits no event for streak update | DOCUMENT |
| EVT-GAME-02 | INFO | DegenerusGame | `payCoinflipBountyDgnrs` emits no event (ERC-20 Transfer on sDGNRS suffices) | DOCUMENT |
| EVT-GAME-03 | INFO | DegenerusGame | `resolveRedemptionLootbox` emits no event for accounting reclassification | DOCUMENT |
| EVT-GAME-04 | INFO | DegenerusGame | `adminSwapEthForStEth` emits no event (stETH Transfer suffices) | DOCUMENT |
| EVT-GAME-05 | INFO | DegenerusGame | `adminStakeEthForStEth` emits no event (Lido events suffice) | DOCUMENT |
| EVT-GAMEOVER-01 | INFO | GameOverModule | No top-level GameOver event; deity pass refund credits are silent | DOCUMENT |
| EVT-GAMEOVER-02 | INFO | GameOverModule | `handleFinalSweep` emits no event for finalSwept transition | DOCUMENT |
| EVT-BOON-01 | INFO | BoonModule | No events for any of 5 boon consumption functions | DOCUMENT |
| EVT-WHALE-01 | INFO | WhaleModule | No top-level purchase event for whale/lazy/deity purchases | DOCUMENT |
| EVT-WHALE-02 | INFO | WhaleModule | Deity pass purchase (indexer-critical) has no dedicated event | DOCUMENT |

---

## DegenerusGameAdvanceModule (DegenerusGameAdvanceModule.sol)

### Event Inventory

| Event | Parameters | Indexed Fields | Purpose |
|-------|-----------|----------------|---------|
| Advance | stage, lvl | (none) | Indexer-critical: game advancement stage tracking |
| ReverseFlip | caller, totalQueued, cost | caller | RNG nudge tracking |
| DailyRngApplied | day, rawWord, nudges, finalWord | (none) | Indexer-critical: daily RNG lifecycle |
| LootboxRngApplied | index, word, requestId | (none) | Indexer-critical: lootbox RNG assignment |
| VrfCoordinatorUpdated | previous, current | previous, current | Admin config change |
| StEthStakeFailed | amount | (none) | Operational monitoring |

### Function-by-Function Audit

| Function | State Changes | Event Emitted | Params Match Post-State | Indexer-Critical | Finding |
|----------|--------------|---------------|------------------------|-----------------|---------|
| `advanceGame()` | Complex multi-stage: updates dailyIdx, level, prize pools, processes tickets/jackpots, manages RNG lifecycle | Advance(stage, lvl) | Yes -- `stage` matches the computed stage constant (STAGE_GAMEOVER through STAGE_JACKPOT_DAILY_STARTED), `lvl` is the current level at time of emission. Emitted at line 154 (gameover), 181 (mid-day tickets), 401 (main path). All emit the same `lvl` that was read at line 138. | Yes | -- |
| `wireVrf(...)` | Sets vrfCoordinator, vrfSubscriptionId, vrfKeyHash, lastVrfProcessedTimestamp | VrfCoordinatorUpdated | Yes -- `current` is the old address read at line 425 before the write at line 426, and `coordinator_` is the new address. Emitted at line 430. | Yes | EVT-ADV-01 |
| `requestLootboxRng()` | Requests VRF, advances lootboxRngIndex, clears pending counters | No dedicated event (VRF request is internal) | N/A | No | EVT-ADV-02 |
| `reverseFlip()` | Burns BURNIE, increments totalFlipReversals | ReverseFlip | Yes -- `newCount` is `reversals + 1` (line 1455 after line 1456 write), `cost` is the computed burn amount. Emitted at line 1457. | No | -- |
| `rawFulfillRandomWords(...)` | Stores rngWordCurrent (daily) or directly writes lootboxRngWordByIndex (mid-day) | LootboxRngApplied (mid-day path only) | Yes -- emitted at line 1484 with `index = lootboxRngIndex - 1`, `word` = received VRF word, `requestId` from state. Daily path stores word without emitting (DailyRngApplied emitted later during processing). | Yes | -- |
| `updateVrfCoordinatorAndSub(...)` | Updates coordinator, subId, keyHash, clears VRF state | VrfCoordinatorUpdated | Yes -- same pattern as wireVrf, emitted at line 1430. | Yes | -- |
| `_applyDailyRng(day, rawWord)` (private) | Applies nudges, stores rngWordByDay, updates lastVrfProcessedTimestamp | DailyRngApplied | Yes -- emitted at line 1562 with `day`, `rawWord` (original VRF), `nudges` (count consumed), and `finalWord` (rawWord + nudges). All values match post-state. | Yes | -- |
| `_backfillGapDays(...)` (private) | Fills rngWordByDay for gap days, processes coinflip payouts | DailyRngApplied | Yes -- emitted at line 1514 for each gap day with `derivedWord` as both raw and final (no nudges applied to gap days). | Yes | -- |
| `_backfillOrphanedLootboxIndices(...)` (private) | Fills lootboxRngWordByIndex for orphaned indices | LootboxRngApplied | Yes -- emitted at line 1538 with `fallbackWord` and `requestId=0` (backfill indicator). | Yes | -- |
| `_finalizeLootboxRng(rngWord)` (private) | Writes lootboxRngWordByIndex[index] | LootboxRngApplied | Yes -- emitted at line 868 with the stored word and current vrfRequestId. | Yes | -- |
| `_autoStakeExcessEth()` (private) | Stakes ETH into Lido | StEthStakeFailed (on failure only) | Yes -- emitted at line 1273 with the `stakeable` amount that failed. Success path has no event. | No | -- |

### Findings

**EVT-ADV-01: `wireVrf` VrfCoordinatorUpdated event parameter naming is misleading** -- INFO
- The event parameters are `previous` and `current`, but the emit at line 430 passes `current` (old) and `coordinator_` (new). The variable name `current` in the function is the OLD coordinator read before the write. This is functionally correct (old address emitted as `previous`, new as `current`) but the local variable name `current` is confusing.
- Assessment: No actual bug -- the event params match the intended semantics. The local variable naming is a readability issue, not a correctness issue.
- Disposition: DOCUMENT

**EVT-ADV-02: `requestLootboxRng` emits no event for VRF request or index advancement** -- INFO
- The function advances `lootboxRngIndex++`, clears `lootboxRngPendingEth`/`lootboxRngPendingBurnie`, and submits a VRF request. No event is emitted for the request itself or the index advancement.
- Assessment: The subsequent `LootboxRngApplied` event (emitted when VRF fulfills) provides the index and word. An indexer can detect the request by monitoring for VRF coordinator events. The gap is that index advancement is not independently observable.
- Disposition: DOCUMENT

---

## DegenerusGameJackpotModule (DegenerusGameJackpotModule.sol)

### Event Inventory

| Event | Parameters | Indexed Fields | Purpose |
|-------|-----------|----------------|---------|
| AutoRebuyProcessed | player, targetLevel, ticketCount, ethSpent, remainder | player | Auto-rebuy conversion tracking |
| DailyCarryoverStarted | jackpotLevel, carryoverSourceLevel | jackpotLevel | Indexer: carryover source identification |
| FarFutureCoinJackpotWinner | winner, currentLevel, winnerLevel, amount | winner, currentLevel, winnerLevel | Indexer-critical: BURNIE jackpot winners |
| JackpotTicketWinner | winner, level, traitId, amount, ticketIndex | winner, level, traitId | Indexer-critical: ETH jackpot winners |

### Function-by-Function Audit

| Function | State Changes | Event Emitted | Params Match Post-State | Indexer-Critical | Finding |
|----------|--------------|---------------|------------------------|-----------------|---------|
| `payDailyJackpotCoinAndTickets(randWord)` | Distributes BURNIE jackpot, processes far-future coin jackpot | FarFutureCoinJackpotWinner, JackpotTicketWinner | FarFutureCoinJackpotWinner: Yes -- emitted at line 2502 with `winners[i]`, `lvl`, `winnerLevels[i]`, `perWinner` matching actual distribution. JackpotTicketWinner: Yes -- emitted at lines 2404 with per-winner amount matching `_creditJackpot` call. | Yes | -- |
| `awardFinalDayDgnrsReward(lvl, rngWord)` | Transfers DGNRS to winners | None (DGNRS Transfer events from sDGNRS contract) | N/A | No | EVT-JACK-01 |
| `consolidatePrizePools(lvl, rngWord)` | Merges pendingPools into main pools, unfreezes, resets jackpot state | None | N/A | No | EVT-JACK-02 |
| `processTicketBatch(lvl)` | Assigns traits to queued tickets, processes batch | TraitsGenerated (via _generateTraitsAndEmit) | Yes -- emitted at line 1991 with `player`, `lvl`, `queueIdx`, `processed`, `take`, `entropy` matching actual trait generation params. | No | -- |
| `_distributeJackpotEth(...)` (private) | Credits ETH to winners via _addClaimableEth, updates claimablePool | JackpotTicketWinner, PlayerCredited (via _creditClaimable), AutoRebuyProcessed (if auto-rebuy active) | JackpotTicketWinner: Yes -- emitted at lines 1418/1586/1619/1638 with `perWinner` matching the computed `share / totalCount`. PlayerCredited: Yes (via PayoutUtils). AutoRebuyProcessed: Yes (via _addClaimableEth -> auto-rebuy path). | Yes | -- |
| `payDailyJackpot(...)` (private) | Daily ETH jackpot distribution across trait buckets | DailyCarryoverStarted, JackpotTicketWinner, PlayerCredited, AutoRebuyProcessed | DailyCarryoverStarted: Yes -- emitted at line 545 with computed `carryoverSourceLevel`. All winner events: Yes. | Yes | -- |
| `payDailyCoinJackpot(lvl, randWord)` | Daily BURNIE jackpot distribution | JackpotTicketWinner | Yes -- emitted at line 2404 with amounts matching distribution. | Yes | -- |
| `runTerminalJackpot(...)` | Terminal game-over jackpot distribution | JackpotTicketWinner, PlayerCredited | Yes -- uses same `_distributeJackpotEth` path. | Yes | -- |

### Findings

**EVT-JACK-01: `awardFinalDayDgnrsReward` emits no event for DGNRS rewards** -- INFO
- Awards DGNRS to winners from the reward pool via `dgnrs.transferFromPool()`. The sDGNRS ERC-20 Transfer event provides traceability.
- Assessment: Low impact. Similar to EVT-GAME-02. Transfer events on sDGNRS suffice for indexers.
- Disposition: DOCUMENT

**EVT-JACK-02: `consolidatePrizePools` emits no event for pool state transition** -- INFO
- Merges pending pools into main pools, unfreezes prize pool state, resets jackpot counters. This is a significant internal state transition but emitting an event would be redundant with the `Advance` event emitted by the calling `advanceGame()` function which indicates the phase transition.
- Assessment: Low impact. The `Advance(STAGE_JACKPOT_PHASE_ENDED, lvl)` event covers the transition.
- Disposition: DOCUMENT

---

## DegenerusGameLootboxModule (DegenerusGameLootboxModule.sol)

### Event Inventory

| Event | Parameters | Indexed Fields | Purpose |
|-------|-----------|----------------|---------|
| PlayerCredited | player, recipient, amount | player, recipient | ETH credit tracking |
| LootBoxOpened | player, index, amount, futureLevel, futureTickets, burnie, bonusBurnie | player, index | Indexer-critical: lootbox resolution |
| BurnieLootOpen | player, index, burnieAmount, ticketLevel, tickets, burnieReward | player, index | Indexer: BURNIE lootbox resolution |
| LootBoxWhalePassJackpot | player, day, lootboxAmount, targetLevel, tickets, statsBoost, frozenUntilLevel | player, day | Indexer: whale pass jackpot from lootbox |
| LootBoxDgnrsReward | player, day, lootboxAmount, dgnrsAmount | player, day | DGNRS reward tracking |
| LootBoxWwxrpReward | player, day, lootboxAmount, wwxrpAmount | player, day | WWXRP reward tracking |
| LootBoxReward | player, day, rewardType, lootboxAmount, amount | player, day, rewardType | Unified boon/boost reward |
| DeityBoonIssued | deity, recipient, day, slot, boonType | deity, recipient, day | Indexer: deity boon tracking |

### Function-by-Function Audit

| Function | State Changes | Event Emitted | Params Match Post-State | Indexer-Critical | Finding |
|----------|--------------|---------------|------------------------|-----------------|---------|
| `openLootBox(player, index)` | Clears lootboxEth/lootboxDay/lootboxBurnie, distributes tickets/BURNIE/boons | LootBoxOpened, LootBoxReward (for boons), LootBoxWhalePassJackpot, LootBoxDgnrsReward, LootBoxWwxrpReward, TicketsQueuedScaled, PlayerCredited | LootBoxOpened: Yes -- emitted at line 1015 with `amount` (total ETH), `targetLevel`, `futureTickets`, `burnieAmount`, `bonusBurnie` all computed during resolution. Emitted after all state changes. | Yes | -- |
| `openBurnieLootBox(player, index)` | Clears lootboxBurnie, distributes tickets/BURNIE rewards | BurnieLootOpen | Yes -- emitted at line 679 with `burnieAmount` (input), `targetLevel`, `tickets`, `burnieReward` from resolution. | No | -- |
| `resolveLootboxDirect(player, amount, rngWord)` | Resolves lootbox inline (no storage clear) | LootBoxOpened (via _resolveEthLootbox with emitLootboxEvent=true) | Yes -- same resolution path as openLootBox. | No | -- |
| `resolveRedemptionLootbox(player, amount, rngWord, activityScore)` | Resolves redemption lootbox with overridden activity score | LootBoxOpened (via _resolveEthLootbox) | Yes -- same resolution path. | No | -- |
| `issueDeityBoon(deity, recipient, slot)` | Updates deityBoonDay, deityBoonUsedMask, deityBoonRecipientDay, applies boon to recipient | DeityBoonIssued | Yes -- emitted at line 821 after state updates at lines 808-819. `boonType` is the computed boon for the slot. | No | -- |

### Findings

No findings -- LootboxModule has comprehensive event coverage. Every lootbox resolution emits `LootBoxOpened` with full reward details. Boon awards emit `LootBoxReward` with the specific reward type. The module is well-instrumented for indexer reconstruction.

---

## DegenerusGameMintModule (DegenerusGameMintModule.sol)

### Event Inventory

| Event | Parameters | Indexed Fields | Purpose |
|-------|-----------|----------------|---------|
| LootBoxBuy | buyer, day, amount, presale, level | buyer, day | Indexer: lootbox purchase tracking |
| LootBoxIdx | buyer, index, day | buyer, index, day | Indexer-critical: lootbox index assignment |
| BurnieLootBuy | buyer, index, burnieAmount | buyer, index | BURNIE lootbox purchase |
| BoostUsed | player, day, originalAmount, boostedAmount, boostBps | player, day | Boost consumption tracking |

### Function-by-Function Audit

| Function | State Changes | Event Emitted | Params Match Post-State | Indexer-Critical | Finding |
|----------|--------------|---------------|------------------------|-----------------|---------|
| `purchase(buyer, ticketQuantity, lootBoxAmount, affiliateCode, payKind)` | Records mint via recordMint (delegatecall back to Game), records lootbox entry, processes affiliate rewards | LootBoxIdx (if new index), BoostUsed (if boost active), LootBoxBuy, TicketsQueued (via recordMint -> _recordMintDataModule), ClaimableSpent (if claimable used) | LootBoxIdx: Yes -- emitted at line 706 with current `index` and `day`. LootBoxBuy: Yes -- emitted at line 795 with `lootBoxAmount`, `presale`, `level`. All after state writes. | No | EVT-MINT-01 |
| `purchaseCoin(buyer, ticketQuantity, lootBoxBurnieAmount)` | Burns BURNIE for ticket purchase, records BURNIE lootbox | BurnieLootBuy, TicketsQueued | BurnieLootBuy: Yes -- emitted at line 1070 with `buyer`, `index`, `burnieAmount`. | No | -- |
| `purchaseBurnieLootbox(buyer, burnieAmount)` | Burns BURNIE, records BURNIE lootbox entry | BurnieLootBuy | Yes -- emitted at line 1070. | No | -- |
| `recordMintData(player, lvl, mintUnits)` | Updates mintPacked_ with level, count, streak | TraitsGenerated (if ticket queue populated) | No direct event for the mint data update itself; TraitsGenerated is emitted by the trait generation system if applicable. | No | -- |

### Findings

**EVT-MINT-01: No top-level "TicketPurchased" event for ETH ticket purchases** -- INFO
- The `purchase()` function can buy both tickets and lootboxes. Ticket purchases go through `recordMint()` which delegates to `_recordMintDataModule`. The `TicketsQueued` event (from Storage) fires for the queued tickets, and `ClaimableSpent` fires if claimable was used. However, there's no single "purchase complete" event with the full purchase summary (total ETH, tickets bought, lootbox amount).
- Assessment: The component events (TicketsQueued, LootBoxBuy, ClaimableSpent) collectively provide the data, but an indexer must aggregate them. This matches the pattern seen in WhaleModule (EVT-WHALE-01).
- Disposition: DOCUMENT

---

## DegenerusGameDegeneretteModule (DegenerusGameDegeneretteModule.sol)

### Event Inventory

| Event | Parameters | Indexed Fields | Purpose |
|-------|-----------|----------------|---------|
| BetPlaced | player, index, betId, packed | player, index, betId | Indexer-critical: bet placement |
| FullTicketResolved | player, betId, ticketCount, totalPayout, resultTicket | player, betId | Indexer-critical: bet resolution summary |
| FullTicketResult | player, betId, ticketIndex, playerTicket, matches, payout | player, betId | Indexer: per-spin result detail |
| PayoutCapped | player, cappedEthPayout, excessConverted | player | Cap event for large wins |
| ConsolationPrize | player, amount | player | Consolation prize tracking |

### Function-by-Function Audit

| Function | State Changes | Event Emitted | Params Match Post-State | Indexer-Critical | Finding |
|----------|--------------|---------------|------------------------|-----------------|---------|
| `placeFullTicketBets(player, currency, amountPerTicket, ticketCount, customTicket, heroQuadrant)` | Records bet in degeneretteBets mapping, increments nonce, updates hero wagers | BetPlaced | Yes -- emitted at line 502 with `player`, `index` (current lootboxRngIndex), `nonce` (post-increment), `packed` (the stored bet data). | Yes | -- |
| `resolveBets(player, betIds)` | Resolves each bet using RNG, distributes payouts (ETH/BURNIE/WWXRP), clears bet data | FullTicketResult (per spin), FullTicketResolved (per bet), PayoutCapped (if ETH win exceeds cap), ConsolationPrize (for losing bets) | FullTicketResult: Yes -- emitted at line 674 with `playerTicket`, `matches`, `payout` from resolution computation. FullTicketResolved: Yes -- emitted at line 713 with `totalPayout` accumulated across all spins. PayoutCapped: Yes -- emitted at line 771 with capped values. ConsolationPrize: Yes -- emitted at line 821 with fixed prize amount. | Yes | -- |

### Findings

No findings -- DegeneretteModule has comprehensive event coverage. Every bet placement and resolution is fully instrumented. The per-spin `FullTicketResult` events provide complete reconstruction data, and `FullTicketResolved` provides the summary.

---

## DegenerusGameDecimatorModule (DegenerusGameDecimatorModule.sol)

### Event Inventory

| Event | Parameters | Indexed Fields | Purpose |
|-------|-----------|----------------|---------|
| AutoRebuyProcessed | player, targetLevel, ticketsAwarded, ethSpent, remainder | player | Auto-rebuy from decimator claim |
| DecBurnRecorded | player, lvl, bucket, subBucket, effectiveAmount, newTotalBurn | player, lvl | Indexer: decimator burn tracking |
| TerminalDecBurnRecorded | player, lvl, bucket, subBucket, effectiveAmount, weightedAmount, timeMultBps | player, lvl | Terminal decimator burn tracking |

### Function-by-Function Audit

| Function | State Changes | Event Emitted | Params Match Post-State | Indexer-Critical | Finding |
|----------|--------------|---------------|------------------------|-----------------|---------|
| `recordDecBurn(player, lvl, bucket, baseAmount, multBps)` | Updates decBurn entry, updates subbucket aggregates | DecBurnRecorded | Yes -- emitted at line 177 with `delta` (actual burn increment, not total), `newBurn` (post-update total). The `delta` naming as `effectiveAmount` in the event is slightly misleading but functionally the delta IS the effective amount. | No | -- |
| `runDecimatorJackpot(poolWei, lvl, rngWord)` | Snapshots decClaimRound, selects winning subbuckets | None | N/A | Yes | EVT-DEC-01 |
| `recordTerminalDecBurn(player, lvl, baseAmount)` | Updates terminalDecEntries, updates bucket aggregates | TerminalDecBurnRecorded | Yes -- emitted at line 766 with `effectiveAmount`, `weightedAmount` (after time multiplier), `timeMultBps`. All computed values match stored state. | No | -- |
| `runTerminalDecimatorJackpot(poolWei, lvl, rngWord)` | Snapshots lastTerminalDecClaimRound, selects winning subbuckets | None | N/A | Yes | EVT-DEC-02 |
| `claimDecimatorJackpot(lvl)` | Marks claim as consumed, credits ETH via _addClaimableEth | PlayerCredited (via _creditClaimable) or AutoRebuyProcessed (if auto-rebuy active) | Yes -- amounts from `_consumeDecClaim` match actual pro-rata calculation. | Yes | EVT-DEC-03 |
| `consumeDecClaim(player, lvl)` | Same as claimDecimatorJackpot core logic | None (caller handles events) | N/A | No | -- |
| `claimTerminalDecimatorJackpot()` | Marks claim as consumed, credits ETH | PlayerCredited (via _creditClaimable) | Yes -- same pattern as regular claim. | Yes | EVT-DEC-03 |

### Findings

**EVT-DEC-01: `runDecimatorJackpot` emits no event for jackpot snapshot** -- INFO
- Selects winning subbuckets and snapshots the claim round (`decClaimRounds[lvl]`), but emits no event indicating which subbuckets won or the total pool size.
- Assessment: The `RewardJackpotsSettled` event from EndgameModule (the caller) provides the pool-level summary. Individual winning subbucket details are revealed when players claim (each claim emits `PlayerCredited`). However, the winning subbucket selection is not directly observable until claims happen.
- Disposition: DOCUMENT

**EVT-DEC-02: `runTerminalDecimatorJackpot` emits no event for terminal jackpot snapshot** -- INFO
- Same pattern as EVT-DEC-01 but for the terminal (game-over) decimator. No event for the winning subbucket selection or pool allocation.
- Disposition: DOCUMENT

**EVT-DEC-03: `claimDecimatorJackpot` / `claimTerminalDecimatorJackpot` have no dedicated claim event** -- INFO
- Claims emit `PlayerCredited` (via `_creditClaimable`) or `AutoRebuyProcessed` (via auto-rebuy path), but there's no "DecimatorJackpotClaimed" event with the level, player, and claim amount together.
- Assessment: `PlayerCredited` provides the credit data. An indexer can correlate credits with decimator claims by context, but cannot distinguish a decimator claim credit from any other ETH credit without additional on-chain state inspection.
- Disposition: DOCUMENT

---

## Indexer-Critical Transition Coverage (Task 2 Contracts)

| Transition | Contract | Event | Sufficient Data? | Finding |
|-----------|----------|-------|------------------|---------|
| Game advancement (all stages) | AdvanceModule | Advance(stage, lvl) | Yes -- stage constant identifies exact progress point | -- |
| Daily RNG applied | AdvanceModule | DailyRngApplied | Yes -- raw word, nudges, final word | -- |
| Lootbox RNG applied | AdvanceModule | LootboxRngApplied | Yes -- index, word, requestId | -- |
| VRF coordinator change | AdvanceModule | VrfCoordinatorUpdated | Yes -- old and new addresses | -- |
| Daily ETH jackpot winner | JackpotModule | JackpotTicketWinner | Yes -- winner, level, traitId, amount, ticketIndex | -- |
| Daily BURNIE jackpot winner | JackpotModule | FarFutureCoinJackpotWinner | Yes -- winner, levels, amount | -- |
| Lootbox opened | LootboxModule | LootBoxOpened | Yes -- full resolution details | -- |
| Degenerette bet placed | DegeneretteModule | BetPlaced | Yes -- packed bet data | -- |
| Degenerette bet resolved | DegeneretteModule | FullTicketResolved + FullTicketResult | Yes -- per-spin and summary data | -- |
| Decimator burn | DecimatorModule | DecBurnRecorded | Yes -- player, level, bucket, amount | -- |
| Decimator jackpot snapshot | DecimatorModule | None | No dedicated event | EVT-DEC-01 |
| Decimator claim | DecimatorModule | PlayerCredited (indirect) | Partial (no dedicated claim event) | EVT-DEC-03 |

---

## Combined Finding Summary (All Game System Contracts)

| ID | Severity | Contract | Description | Disposition |
|----|----------|----------|-------------|-------------|
| EVT-GAME-01 | INFO | DegenerusGame | `recordMintQuestStreak` emits no event for streak update | DOCUMENT |
| EVT-GAME-02 | INFO | DegenerusGame | `payCoinflipBountyDgnrs` emits no event (ERC-20 Transfer on sDGNRS suffices) | DOCUMENT |
| EVT-GAME-03 | INFO | DegenerusGame | `resolveRedemptionLootbox` emits no event for accounting reclassification | DOCUMENT |
| EVT-GAME-04 | INFO | DegenerusGame | `adminSwapEthForStEth` emits no event (stETH Transfer suffices) | DOCUMENT |
| EVT-GAME-05 | INFO | DegenerusGame | `adminStakeEthForStEth` emits no event (Lido events suffice) | DOCUMENT |
| EVT-GAMEOVER-01 | INFO | GameOverModule | No top-level GameOver event; deity pass refund credits are silent | DOCUMENT |
| EVT-GAMEOVER-02 | INFO | GameOverModule | `handleFinalSweep` emits no event for finalSwept transition | DOCUMENT |
| EVT-BOON-01 | INFO | BoonModule | No events for any of 5 boon consumption functions | DOCUMENT |
| EVT-WHALE-01 | INFO | WhaleModule | No top-level purchase event for whale/lazy/deity purchases | DOCUMENT |
| EVT-WHALE-02 | INFO | WhaleModule | Deity pass purchase (indexer-critical) has no dedicated event | DOCUMENT |
| EVT-ADV-01 | INFO | AdvanceModule | `wireVrf` event uses confusing local variable name for old coordinator | DOCUMENT |
| EVT-ADV-02 | INFO | AdvanceModule | `requestLootboxRng` emits no event for VRF request or index advancement | DOCUMENT |
| EVT-JACK-01 | INFO | JackpotModule | `awardFinalDayDgnrsReward` emits no event (sDGNRS Transfer suffices) | DOCUMENT |
| EVT-JACK-02 | INFO | JackpotModule | `consolidatePrizePools` emits no event (Advance event covers transition) | DOCUMENT |
| EVT-MINT-01 | INFO | MintModule | No top-level "TicketPurchased" event for purchase summary | DOCUMENT |
| EVT-DEC-01 | INFO | DecimatorModule | `runDecimatorJackpot` emits no event for winning subbucket snapshot | DOCUMENT |
| EVT-DEC-02 | INFO | DecimatorModule | `runTerminalDecimatorJackpot` emits no event for terminal snapshot | DOCUMENT |
| EVT-DEC-03 | INFO | DecimatorModule | Decimator claims have no dedicated claim event (PlayerCredited only) | DOCUMENT |

**Total: 18 INFO findings across 14 game system files. 0 HIGH, 0 MEDIUM, 0 LOW. All DOCUMENT disposition per D-03.**

**Parameter correctness:** Zero stale-local or pre-update-snapshot bugs found across all ~95 emit statements. All events emit values computed from post-state or from the same computation that produced the state change.

**Indexer-critical coverage:** All major game transitions (advancement, RNG, jackpot winners, lootbox resolution, degenerette bets) have sufficient event data for off-chain reconstruction. The gaps are in secondary transitions (decimator snapshots, admin operations, game-over state flags) where the data is either derivable from other events or readable from on-chain storage.


---

## Non-Game Contracts


## BurnieCoin (BurnieCoin.sol)

### Event Inventory

| Event | Parameters | Indexed Fields | Inherited (OZ) |
|-------|-----------|----------------|-----------------|
| Transfer | from, to, amount | from, to | Custom (OZ-compatible) |
| Approval | owner, spender, amount | owner, spender | Custom (OZ-compatible) |
| DecimatorBurn | player, amountBurned, bucket | player | Custom |
| TerminalDecimatorBurn | player, amountBurned | player | Custom |
| DailyQuestRolled | day, questType, highDifficulty | day | Custom |
| QuestCompleted | player, questType, streak, reward | player | Custom |
| LinkCreditRecorded | player, amount | player | Custom |
| VaultEscrowRecorded | sender, amount | sender | Custom |
| VaultAllowanceSpent | spender, amount | spender | Custom |

### Function-by-Function Audit

| Function | Visibility | State Changes | Event Emitted | Params Match Post-State | Indexer-Critical | Finding |
|----------|-----------|--------------|---------------|------------------------|-----------------|---------|
| approve(spender, amount) | external | allowance update | Approval(msg.sender, spender, amount) | YES -- emits requested amount | NO | OK |
| transfer(to, amount) | external | balance update, possible coinflip claim | Transfer(from, to, amount) via _transfer | YES -- amount matches transfer | YES | OK |
| transferFrom(from, to, amount) | external | balance + allowance update | Transfer(from, to, amount) + Approval on allowance decrement | YES | YES | OK |
| burnForCoinflip(from, amount) | external | balance + supply decrease | Transfer(from, 0, amount) via _burn | YES | YES | OK |
| mintForCoinflip(to, amount) | external | balance + supply increase | Transfer(0, to, amount) via _mint | YES | YES | OK |
| mintForGame(to, amount) | external | balance + supply increase | Transfer(0, to, amount) via _mint | YES | YES | OK |
| creditCoin(player, amount) | external | balance + supply increase | Transfer(0, player, amount) via _mint | YES | NO | OK |
| creditFlip(player, amount) | external | forwards to coinflip | No direct event (coinflip emits) | N/A | NO | OK |
| creditFlipBatch(players, amounts) | external | forwards to coinflip | No direct event (coinflip emits) | N/A | NO | OK |
| creditLinkReward(player, amount) | external | forwards to coinflip | LinkCreditRecorded(player, amount) | YES | NO | OK |
| vaultEscrow(amount) | external | vaultAllowance increase | VaultEscrowRecorded(sender, amount) | YES | NO | OK |
| vaultMintTo(to, amount) | external | supply + balance increase, allowance decrease | VaultAllowanceSpent(address(this), amount) + Transfer(0, to, amount) | YES | YES | OK |
| rollDailyQuest(day, entropy) | external | quest state update | DailyQuestRolled(day, questType, highDifficulty) x2 | YES | NO | OK |
| notifyQuestMint(player, quantity, paidWithEth) | external | quest state | QuestCompleted(player, ...) if completed | YES | NO | OK |
| notifyQuestLootBox(player, amountWei) | external | quest state | QuestCompleted(player, ...) if completed | YES | NO | OK |
| notifyQuestDegenerette(player, amount, paidWithEth) | external | quest state | QuestCompleted(player, ...) if completed | YES | NO | OK |
| affiliateQuestReward(player, amount) | external | quest state | QuestCompleted(player, ...) if completed | YES | NO | OK |
| burnCoin(target, amount) | external | balance + supply decrease | Transfer(target, 0, amount-consumed) via _burn | YES | YES | OK |
| decimatorBurn(player, amount) | external | balance + supply decrease, game state | DecimatorBurn(caller, amount, bucketUsed) | YES -- emits raw input amount + actual bucket used | NO | OK |
| terminalDecimatorBurn(player, amount) | external | balance + supply decrease, game state | TerminalDecimatorBurn(caller, amount) | YES | NO | OK |

**Special attention: _transfer to VAULT**
When `to == ContractAddresses.VAULT`, `_transfer` emits `Transfer(from, address(0), amount)` + `VaultEscrowRecorded(from, amount)`. This is correct: sending BURNIE to the vault effectively burns it (converts to mint allowance). The Transfer event shows `to=address(0)` which accurately represents the burn, not a misleading transfer to VAULT address. Indexers tracking total supply will see the burn correctly.

**Special attention: _mint to VAULT**
When minting to VAULT, `_mint` emits only `VaultEscrowRecorded(address(0), amount)` with NO Transfer event. This is intentional -- no tokens enter circulation, only virtual allowance increases. However, an indexer tracking total supply via Transfer events would miss this. Since vault allowance is tracked separately via `supplyIncUncirculated()`, this is a design choice.

**Special attention: _burn from VAULT**
When burning from VAULT, `_burn` emits only `VaultAllowanceSpent(from, amount)` with NO Transfer event. Same reasoning as mint-to-vault above.

### Findings

- **EVT-BC-01 (INFO):** `_mint` to VAULT emits no Transfer event -- intentional design (virtual allowance, no circulating tokens created). Indexers relying solely on Transfer events will undercount total-plus-uncirculated supply. -- Disposition: DOCUMENT
- **EVT-BC-02 (INFO):** `_burn` from VAULT emits no Transfer event -- same design pattern as EVT-BC-01. -- Disposition: DOCUMENT

---

## BurnieCoinflip (BurnieCoinflip.sol)

### Event Inventory

| Event | Parameters | Indexed Fields | Inherited (OZ) |
|-------|-----------|----------------|-----------------|
| CoinflipDeposit | player, creditedFlip | player | Custom |
| CoinflipAutoRebuyToggled | player, enabled | player | Custom |
| CoinflipAutoRebuyStopSet | player, stopAmount | player | Custom |
| QuestCompleted | player, questType, streak, reward | player | Custom |
| CoinflipStakeUpdated | player, day, amount, newTotal | player, day | Custom |
| CoinflipDayResolved | day, win, rewardPercent, bountyAfter, bountyPaid, bountyRecipient | day | Custom |
| CoinflipTopUpdated | day, player, score | day, player | Custom |
| BiggestFlipUpdated | player, recordAmount | player | Custom |
| BountyOwed | player, bounty, recordFlip | player | Custom |
| BountyPaid | to, amount | to | Custom |

### Function-by-Function Audit

| Function | Visibility | State Changes | Event Emitted | Params Match Post-State | Indexer-Critical | Finding |
|----------|-----------|--------------|---------------|------------------------|-----------------|---------|
| settleFlipModeChange(player) | external | claimableStored update | None | N/A -- settlement is internal accounting | NO | OK |
| depositCoinflip(player, amount) | external | stake + burn + quest | CoinflipDeposit(caller, amount) + CoinflipStakeUpdated(...) | YES -- amount is raw deposit, newTotal is post-update | YES | OK |
| claimCoinflips(player, amount) | external | mint + state updates | None directly (mint emits Transfer in BurnieCoin) | N/A | NO | OK |
| claimCoinflipsFromBurnie(player, amount) | external | state updates | None directly | N/A | NO | OK |
| claimCoinflipsForRedemption(player, amount) | external | state updates | None directly | N/A | NO | OK |
| consumeCoinflipsForBurn(player, amount) | external | state updates | None directly | N/A | NO | OK |
| setCoinflipAutoRebuy(player, enabled, takeProfit) | external | auto-rebuy config | CoinflipAutoRebuyToggled + CoinflipAutoRebuyStopSet | YES | NO | OK |
| setCoinflipAutoRebuyTakeProfit(player, takeProfit) | external | takeProfit update | CoinflipAutoRebuyStopSet(player, takeProfit) | YES | NO | OK |
| processCoinflipPayouts(bonusFlip, rngWord, epoch) | external | day result + bounty | CoinflipDayResolved(epoch, ...) + BountyPaid if applicable | YES | YES | OK |
| creditFlip(player, amount) | external | stake update | CoinflipStakeUpdated(...) via _addDailyFlip | YES | NO | OK |
| creditFlipBatch(players, amounts) | external | stake updates | CoinflipStakeUpdated(...) per player via _addDailyFlip | YES | NO | OK |

**Special attention: CoinflipDeposit emits raw `amount` (not creditedFlip)**
`_depositCoinflip` emits `CoinflipDeposit(caller, amount)` where `amount` is the original deposit, not the credited amount after quest/recycling bonuses. The actual credited amount is captured in the separate `CoinflipStakeUpdated` event. This is consistent -- deposit event shows what the player put in; stake event shows what they got.

**Special attention: bounty resolution in processCoinflipPayouts**
`CoinflipDayResolved` emits `bountyAfter` which is `currentBounty` AFTER the +1000 accumulation (line 847: `currentBounty = currentBounty_ + uint128(PRICE_COIN_UNIT)`). This post-state value is correct for indexers.

**Special attention: settleFlipModeChange emits no event**
This is a pure internal settlement function (accumulates pending claims into claimableStored). No external state transition to signal. Acceptable.

### Findings

- **EVT-CF-01 (INFO):** `settleFlipModeChange` emits no event for claimableStored accumulation. This is internal accounting only; the actual mint/claim path emits events when tokens move. -- Disposition: DOCUMENT
- **EVT-CF-02 (INFO):** Claim functions (claimCoinflips, claimCoinflipsFromBurnie, consumeCoinflipsForBurn) emit no events of their own. The downstream mint via BurnieCoin emits Transfer events. Indexers tracking claims must listen for BurnieCoin Transfer events, not coinflip events. -- Disposition: DOCUMENT

---

## DegenerusStonk (DegenerusStonk.sol)

### Event Inventory

| Event | Parameters | Indexed Fields | Inherited (OZ) |
|-------|-----------|----------------|-----------------|
| Transfer | from, to, amount | from, to | Custom (OZ-compatible) |
| Approval | owner, spender, amount | owner, spender | Custom (OZ-compatible) |
| BurnThrough | from, amount, ethOut, stethOut, burnieOut | from | Custom |
| UnwrapTo | recipient, amount | recipient | Custom |
| YearSweep | ethToGnrus, stethToGnrus, ethToVault, stethToVault | (none) | Custom |

### Function-by-Function Audit

| Function | Visibility | State Changes | Event Emitted | Params Match Post-State | Indexer-Critical | Finding |
|----------|-----------|--------------|---------------|------------------------|-----------------|---------|
| transfer(to, amount) | external | balance update | Transfer(msg.sender, to, amount) | YES | YES | OK |
| transferFrom(from, to, amount) | external | balance + allowance update | Transfer(from, to, amount) | YES | YES | OK |
| approve(spender, amount) | external | allowance update | Approval(msg.sender, spender, amount) | YES | NO | OK |
| unwrapTo(recipient, amount) | external | burn + sDGNRS transfer | Transfer(msg.sender, 0, amount) via _burn + UnwrapTo(recipient, amount) | YES | YES | OK |
| burn(amount) | external | burn + asset withdrawal | Transfer(msg.sender, 0, amount) via _burn + BurnThrough(msg.sender, amount, ethOut, stethOut, burnieOut) | YES -- ethOut/stethOut/burnieOut are actual values returned by stonk.burn() | YES | OK |
| yearSweep() | external | sDGNRS burn + asset distribution | YearSweep(ethToGnrus, stethToGnrus, ethToVault, stethToVault) | YES -- values computed from 50-50 split of actual burn output | YES | OK |
| burnForSdgnrs(player, amount) | external | balance + supply decrease | Transfer(player, 0, amount) | YES | YES | OK |
| constructor() | -- | initial mint | Transfer(0, CREATOR, deposited) | YES | YES | OK |

**Special attention: burn() event ordering**
`_burn` is called first (emits Transfer(from, 0, amount)), then stonk.burn() returns actual values, then BurnThrough is emitted with the actual out values. The BurnThrough event correctly contains the actual received amounts, not estimates.

**Special attention: yearSweep no Transfer event for sDGNRS burn**
The yearSweep function calls `stonk.burn(remaining)` which burns sDGNRS from the DGNRS contract's balance. The sDGNRS contract emits its own Transfer event for that burn. The DGNRS contract only emits YearSweep. No DGNRS Transfer event is emitted since no DGNRS tokens are burned (they were already burned by prior burn() calls). This is correct.

### Findings

- **EVT-DS-01 (INFO):** `YearSweep` event has no indexed fields. Since this is a once-per-game permissionless call, indexed fields are not needed for filtering. -- Disposition: DOCUMENT

---

## StakedDegenerusStonk (StakedDegenerusStonk.sol)

### Event Inventory

| Event | Parameters | Indexed Fields | Inherited (OZ) |
|-------|-----------|----------------|-----------------|
| Transfer | from, to, amount | from, to | Custom (OZ-compatible) |
| Burn | from, amount, ethOut, stethOut, burnieOut | from | Custom |
| Deposit | from, ethAmount, stethAmount, burnieAmount | from | Custom |
| PoolTransfer | pool, to, amount | pool, to | Custom |
| PoolRebalance | from, to, amount | from, to | Custom |
| RedemptionSubmitted | player, sdgnrsAmount, ethValueOwed, burnieOwed, periodIndex | player | Custom |
| RedemptionResolved | periodIndex, roll, rolledBurnie, flipDay | periodIndex | Custom |
| RedemptionClaimed | player, roll, flipResolved, ethPayout, burniePayout, lootboxEth | player | Custom |

### Function-by-Function Audit

| Function | Visibility | State Changes | Event Emitted | Params Match Post-State | Indexer-Critical | Finding |
|----------|-----------|--------------|---------------|------------------------|-----------------|---------|
| constructor() | -- | mint to DGNRS + this | Transfer(0, DGNRS, creatorAmount) + Transfer(0, this, poolTotal) | YES | YES | OK |
| wrapperTransferTo(to, amount) | external | balance transfer | Transfer(DGNRS, to, amount) | YES -- soulbound transfer from wrapper | YES | OK |
| receive() | external payable | ETH deposit | Deposit(msg.sender, msg.value, 0, 0) | YES | YES | OK |
| depositSteth(amount) | external | stETH deposit | Deposit(msg.sender, 0, amount, 0) | YES | YES | OK |
| transferFromPool(pool, to, amount) | external | pool + balance update | Transfer(this, to, amount) + PoolTransfer(pool, to, amount) | YES -- amount may be capped to available | YES | OK |
| transferBetweenPools(from, to, amount) | external | pool rebalance | PoolRebalance(from, to, amount) | YES -- no token movement | NO | OK |
| burnAtGameOver() | external | burn all pool tokens | Transfer(this, 0, bal) | YES | YES | OK |
| burn(amount) | external | burn or submit gambling claim | Transfer(from, 0, amount) + Burn(...) for deterministic; Transfer + RedemptionSubmitted for gambling | YES | YES | OK |
| burnWrapped(amount) | external | wrapped burn path | Same as burn() but from DGNRS address | YES | YES | OK |
| resolveRedemptionPeriod(roll, flipDay) | external | period resolution | RedemptionResolved(period, roll, burnieToCredit, flipDay) | YES -- burnieToCredit is actual rolled amount | YES | OK |
| claimRedemption() | external | payout to player | RedemptionClaimed(player, roll, flipResolved, ethDirect, burniePayout, lootboxEth) | YES -- actual payout values after all calculations | YES | OK |

**Special attention: soulbound enforcement**
sDGNRS has no transfer/transferFrom/approve functions at all (they are simply absent, not reverting). Transfer events only fire for mint (constructor), burn, pool distributions, and wrapper transfers. This is correct for a soulbound token.

**Special attention: _deterministicBurnFrom Burn event**
`_deterministicBurnFrom` emits `Burn(beneficiary, amount, ethOut, stethOut, 0)` where beneficiary may differ from burnFrom (for wrapped burns, beneficiary=msg.sender, burnFrom=DGNRS). The event correctly reflects who receives the assets. The Transfer event uses `burnFrom` to show whose sDGNRS balance decreased.

**Special attention: _payEth has no event**
`_payEth` (line 772) is an internal ETH transfer helper with no event. It is always called AFTER the higher-level event (RedemptionClaimed or Burn) has already captured the amounts. This is the Slither DOC-02 pattern -- the higher-level event provides full context, making a per-transfer event redundant. See DOC-02 assessment below.

**Slither DOC-02 assessment:**
DOC-02 flagged `claimablePool -= amount` in DegenerusGame.resolveRedemptionLootbox() (not in sDGNRS). The _payEth pattern here in sDGNRS is similar but different. In sDGNRS, _payEth is always preceded by RedemptionClaimed or Burn events that capture the full payout context. No additional event needed for _payEth itself.

### Findings

- **EVT-SD-01 (INFO):** `_payEth` internal helper emits no event. The calling function (claimRedemption or _deterministicBurnFrom) always emits a comprehensive event before _payEth is called. -- Disposition: DOCUMENT
- **EVT-SD-02 (INFO):** No `transfer`, `transferFrom`, or `approve` functions exist (soulbound). No Approval events are possible. This is intentional for soulbound tokens -- warden filings about "missing ERC-20 functions" are invalid since sDGNRS is not positioned as ERC-20. -- Disposition: DOCUMENT

---

## GNRUS (GNRUS.sol)

### Event Inventory

| Event | Parameters | Indexed Fields | Inherited (OZ) |
|-------|-----------|----------------|-----------------|
| Transfer | from, to, amount | from, to | Custom (OZ-compatible) |
| Burn | burner, gnrusAmount, ethOut, stethOut | burner | Custom |
| ProposalCreated | level, proposalId, proposer, recipient | level, proposalId, proposer | Custom |
| Voted | level, proposalId, voter, approve, weight | level, proposalId, voter | Custom |
| LevelResolved | level, winningProposalId, recipient, gnrusDistributed | level, winningProposalId | Custom |
| LevelSkipped | level | level | Custom |
| GameOverFinalized | gnrusBurned, ethClaimed, stethClaimed | (none) | Custom |

### Function-by-Function Audit

| Function | Visibility | State Changes | Event Emitted | Params Match Post-State | Indexer-Critical | Finding |
|----------|-----------|--------------|---------------|------------------------|-----------------|---------|
| constructor() | -- | mint 1T to this | Transfer(0, this, INITIAL_SUPPLY) via _mint | YES | YES | OK |
| transfer/transferFrom/approve | external pure | reverts always | None (reverts with TransferDisabled) | N/A | N/A | OK |
| burn(amount) | external | balance + supply decrease, ETH/stETH payout | Transfer(burner, 0, amount) + Burn(burner, amount, ethOut, stethOut) | YES -- ethOut/stethOut reflect actual computed values | YES | OK |
| burnAtGameOver() | external | burn unallocated + finalize | Transfer(this, 0, unallocated) + GameOverFinalized(unallocated, 0, 0) | YES -- GameOverFinalized correctly shows 0 for ETH/stETH since this only burns tokens | YES | OK |
| propose(recipient) | external | proposal creation | ProposalCreated(level, proposalId, proposer, recipient) | YES -- proposalId is the pre-increment value | YES | OK |
| vote(proposalId, approveVote) | external | weight update | Voted(level, proposalId, voter, approveVote, weight) | YES -- weight includes vault bonus if applicable | YES | OK |
| pickCharity(level) | external | level resolution + distribution | LevelResolved(level, bestId, recipient, distribution) or LevelSkipped(level) | YES -- distribution is actual computed amount | YES | OK |
| receive() | external payable | ETH deposit | None | N/A | NO | EVT-GN-01 |

**Special attention: soulbound enforcement**
`transfer`, `transferFrom`, and `approve` all revert with `TransferDisabled()`. No events emitted. Correct for soulbound token.

**Special attention: burn() last-holder sweep**
If the caller's entire balance equals `amount`, or all non-contract GNRUS equals `amount`, the actual burn amount may be swept to their full balance. The Transfer event uses the swept `amount` (after adjustment at line 283/307). The Burn event also uses the adjusted amount. Both correctly reflect the actual post-state.

**Special attention: pickCharity distribution**
`pickCharity` emits both `Transfer(this, recipient, distribution)` and `LevelResolved(level, bestId, recipient, distribution)`. If distribution is 0 (empty pool), it emits `LevelSkipped(level)` instead. All three branches have correct events.

**Special attention: GameOverFinalized hardcoded zeros**
`GameOverFinalized(unallocated, 0, 0)` always emits 0 for ethClaimed and stethClaimed. This is correct because `burnAtGameOver` only burns tokens -- it does not claim any ETH/stETH. The game contract pushes ETH/stETH separately. The event name could be misleading but the values are accurate.

### Findings

- **EVT-GN-01 (INFO):** `receive()` function accepts ETH with no event. ETH arrives from game claimWinnings and direct deposits. Since the game contract emits its own distribution events, and direct ETH sends to GNRUS are uncommon utility operations, the missing event is low-impact but worth noting for indexer completeness. -- Disposition: DOCUMENT
- **EVT-GN-02 (INFO):** `GameOverFinalized` event hardcodes `ethClaimed=0, stethClaimed=0`. These fields exist for potential future use but are always zero in current implementation. Not misleading since burnAtGameOver genuinely claims no assets. -- Disposition: DOCUMENT

---

## WrappedWrappedXRP (WrappedWrappedXRP.sol)

### Event Inventory

| Event | Parameters | Indexed Fields | Inherited (OZ) |
|-------|-----------|----------------|-----------------|
| Transfer | from, to, amount | from, to | Custom (OZ-compatible) |
| Approval | owner, spender, amount | owner, spender | Custom (OZ-compatible) |
| Unwrapped | user, amount | user | Custom |
| Donated | donor, amount | donor | Custom |
| VaultAllowanceSpent | spender, amount | spender | Custom |

### Function-by-Function Audit

| Function | Visibility | State Changes | Event Emitted | Params Match Post-State | Indexer-Critical | Finding |
|----------|-----------|--------------|---------------|------------------------|-----------------|---------|
| approve(spender, amount) | external | allowance update | Approval(msg.sender, spender, amount) | YES | NO | OK |
| transfer(to, amount) | external | balance update | Transfer(from, to, amount) via _transfer | YES | YES | OK |
| transferFrom(from, to, amount) | external | balance + allowance update | Transfer(from, to, amount) + Approval(from, msg.sender, allowed-amount) on allowance decrement | YES | YES | OK |
| unwrap(amount) | external | burn + wXRP reserve decrease | Transfer(sender, 0, amount) via _burn + Unwrapped(msg.sender, amount) | YES -- amount matches both burn and wXRP transfer | YES | OK |
| donate(amount) | external | wXRP reserve increase | Donated(msg.sender, amount) | YES | NO | OK |
| mintPrize(to, amount) | external | supply + balance increase | Transfer(0, to, amount) via _mint | YES | YES | OK |
| vaultMintTo(to, amount) | external | supply + balance + allowance decrease | Transfer(0, to, amount) via _mint + VaultAllowanceSpent(this, amount) | YES | YES | OK |
| burnForGame(from, amount) | external | supply + balance decrease | Transfer(from, 0, amount) via _burn | YES | YES | OK |

**Special attention: transferFrom emits Approval on allowance decrement**
Unlike BurnieCoin (which also does this), WWXRP emits `Approval(from, msg.sender, allowed - amount)` in transferFrom when allowance is not max uint256. This correctly reflects the updated allowance. Standard ERC-20 practice, though some implementations skip the redundant Approval emit.

**Special attention: vaultMintTo with amount=0**
When `amount == 0`, the function returns early with no event. This is correct -- no state change, no event needed.

**Special attention: wrap/unwrap amounts**
`unwrap` burns WWXRP and transfers wXRP at 1:1. The Unwrapped event amount matches both the burn amount and the wXRP transfer. `donate` only transfers wXRP in (no WWXRP minted), so Donated event correctly shows only the wXRP donation amount.

### Findings

No findings. All events correctly match post-state values. Event coverage is complete.

---

## DegenerusVault (DegenerusVault.sol)

Note: DegenerusVault.sol contains TWO contracts:
1. **DegenerusVaultShare** -- Minimal ERC20 for share tokens (DGVB, DGVE)
2. **DegenerusVault** -- Main vault contract

### DegenerusVaultShare Event Inventory

| Event | Parameters | Indexed Fields | Inherited (OZ) |
|-------|-----------|----------------|-----------------|
| Transfer | from, to, amount | from, to | Custom (OZ-compatible) |
| Approval | owner, spender, amount | owner, spender | Custom (OZ-compatible) |

### DegenerusVaultShare Function-by-Function Audit

| Function | Visibility | State Changes | Event Emitted | Params Match Post-State | Indexer-Critical | Finding |
|----------|-----------|--------------|---------------|------------------------|-----------------|---------|
| constructor(name_, symbol_) | -- | initial supply mint | Transfer(0, CREATOR, INITIAL_SUPPLY) | YES | YES | OK |
| approve(spender, amount) | external | allowance update | Approval(msg.sender, spender, amount) | YES | NO | OK |
| transfer(to, amount) | external | balance update | Transfer(from, to, amount) via _transfer | YES | YES | OK |
| transferFrom(from, to, amount) | external | balance + allowance update | Transfer(from, to, amount) + Approval(from, sender, newAllowance) | YES | YES | OK |
| vaultMint(to, amount) | external | supply + balance increase | Transfer(0, to, amount) | YES | YES | OK |
| vaultBurn(from, amount) | external | supply + balance decrease | Transfer(from, 0, amount) | YES | YES | OK |

### DegenerusVault Event Inventory

| Event | Parameters | Indexed Fields | Inherited (OZ) |
|-------|-----------|----------------|-----------------|
| Deposit | from, ethAmount, stEthAmount, coinAmount | from | Custom |
| Claim | from, sharesBurned, ethOut, stEthOut, coinOut | from | Custom |

### DegenerusVault Function-by-Function Audit

| Function | Visibility | State Changes | Event Emitted | Params Match Post-State | Indexer-Critical | Finding |
|----------|-----------|--------------|---------------|------------------------|-----------------|---------|
| deposit(coinAmount, stEthAmount) | external payable | coin escrow + stETH pull | Deposit(msg.sender, msg.value, stEthAmount, coinAmount) | YES -- msg.value is actual ETH received | YES | OK |
| receive() | external payable | ETH received | Deposit(msg.sender, msg.value, 0, 0) | YES | YES | OK |
| burnCoin(player, amount) | external | DGVB burn + BURNIE payout | Claim(player, amount, 0, 0, coinOut) | YES -- coinOut is actual computed value | YES | OK |
| burnEth(player, amount) | external | DGVE burn + ETH/stETH payout | Claim(player, amount, ethOut, stEthOut, 0) | YES -- ethOut/stEthOut are actual computed values | YES | OK |
| gameAdvance() | external | forwards to game | None (game emits) | N/A | NO | OK |
| gamePurchase(...) | external payable | forwards to game | None (game emits) | N/A | NO | OK |
| gamePurchaseTicketsBurnie(quantity) | external | forwards to game | None (game emits) | N/A | NO | OK |
| gamePurchaseBurnieLootbox(burnieAmount) | external | forwards to game | None (game emits) | N/A | NO | OK |
| gameOpenLootBox(lootboxIndex) | external | forwards to game | None (game emits) | N/A | NO | OK |
| gamePurchaseDeityPassFromBoon(priceWei, symbolId) | external payable | forwards to game | None (game emits) | N/A | NO | OK |
| gameClaimWinnings() | external | forwards to game | None (game emits) | N/A | NO | OK |
| gameClaimWhalePass() | external | forwards to game | None (game emits) | N/A | NO | OK |
| gameDegeneretteBetEth(...) | external payable | forwards to game | None (game emits) | N/A | NO | OK |
| gameDegeneretteBetBurnie(...) | external | forwards to game | None (game emits) | N/A | NO | OK |
| gameDegeneretteBetWwxrp(...) | external | forwards to game | None (game emits) | N/A | NO | OK |
| gameResolveDegeneretteBets(betIds) | external | forwards to game | None (game emits) | N/A | NO | OK |
| gameSetAutoRebuy(enabled) | external | forwards to game | None (game emits) | N/A | NO | OK |
| gameSetAutoRebuyTakeProfit(takeProfit) | external | forwards to game | None (game emits) | N/A | NO | OK |
| gameSetDecimatorAutoRebuy(enabled) | external | forwards to game | None (game emits) | N/A | NO | OK |
| gameSetAfKingMode(...) | external | forwards to game | None (game emits) | N/A | NO | OK |
| gameSetOperatorApproval(operator, approved) | external | forwards to game | None (game emits) | N/A | NO | OK |
| coinDepositCoinflip(amount) | external | forwards to coinflip | None (coinflip emits) | N/A | NO | OK |
| coinClaimCoinflips(amount) | external | forwards to coinflip | None (coinflip emits) | N/A | NO | OK |
| coinDecimatorBurn(amount) | external | forwards to coin | None (coin emits) | N/A | NO | OK |
| coinSetAutoRebuy(enabled, takeProfit) | external | forwards to coinflip | None (coinflip emits) | N/A | NO | OK |
| coinSetAutoRebuyTakeProfit(takeProfit) | external | forwards to coinflip | None (coinflip emits) | N/A | NO | OK |
| wwxrpMint(to, amount) | external | forwards to WWXRP | None (WWXRP emits) | N/A | NO | OK |
| jackpotsClaimDecimator(lvl) | external | forwards to game | None (game emits) | N/A | NO | OK |

**Special attention: _payEth has no event (Slither DOC-02 pattern)**
`_payEth` and `_paySteth` are internal transfer helpers with no events. They are always called after the Claim event is emitted, which captures the full payout amounts. Same pattern as sDGNRS. No additional event needed.

**Special attention: Vault forwarding functions emit no events**
All 20+ gameplay forwarding functions (gameAdvance, gamePurchase, etc.) emit no events at the vault level. The target contracts (game, coinflip, coin, WWXRP) emit their own events. This is correct -- the vault is a thin proxy and adding redundant events would waste gas.

**Special attention: Refill mechanism (burnCoin/burnEth full supply)**
When a user burns the entire supply of DGVB or DGVE, 1T new shares are minted to them. The `vaultMint` on the share token emits `Transfer(0, player, REFILL_SUPPLY)`. The Claim event captures the burn amount and payout. Both events fire correctly.

### Findings

- **EVT-DV-01 (INFO):** `_payEth` internal helper emits no event. The calling function always emits Claim event before _payEth is called, capturing the full payout context. Same pattern as Slither DOC-02 in DegenerusGame. -- Disposition: DOCUMENT

---

## Slither DOC-02 Cross-Reference

**DOC-02:** `events-maths` detector flagged `claimablePool -= amount` in `DegenerusGame.resolveRedemptionLootbox()` for missing a dedicated event.

**Assessment for non-game contracts:** The `_payEth` pattern in StakedDegenerusStonk and DegenerusVault follows the same design -- internal ETH transfer helpers with no dedicated event, relying on higher-level events (Burn, RedemptionClaimed, Claim) to capture the full context. This is consistent and correct. The DOC-02 finding itself targets DegenerusGame (Plan 01 scope), not these non-game contracts. Confirmed addressed here: no additional events needed for non-game _payEth helpers.

---

## Summary of Findings (Task 1)

| ID | Contract | Severity | Description | Disposition |
|----|----------|----------|-------------|-------------|
| EVT-BC-01 | BurnieCoin | INFO | _mint to VAULT emits no Transfer event (virtual allowance design) | DOCUMENT |
| EVT-BC-02 | BurnieCoin | INFO | _burn from VAULT emits no Transfer event (virtual allowance design) | DOCUMENT |
| EVT-CF-01 | BurnieCoinflip | INFO | settleFlipModeChange emits no event (internal accounting) | DOCUMENT |
| EVT-CF-02 | BurnieCoinflip | INFO | Claim functions emit no events (downstream mint emits Transfer) | DOCUMENT |
| EVT-DS-01 | DegenerusStonk | INFO | YearSweep event has no indexed fields (once-per-game call) | DOCUMENT |
| EVT-SD-01 | StakedDegenerusStonk | INFO | _payEth helper emits no event (higher-level event captures context) | DOCUMENT |
| EVT-SD-02 | StakedDegenerusStonk | INFO | No transfer/approve functions exist (soulbound by design) | DOCUMENT |
| EVT-GN-01 | GNRUS | INFO | receive() accepts ETH with no event (game emits distribution events) | DOCUMENT |
| EVT-GN-02 | GNRUS | INFO | GameOverFinalized hardcodes ethClaimed=stethClaimed=0 (accurate) | DOCUMENT |
| EVT-DV-01 | DegenerusVault | INFO | _payEth helper emits no event (Claim event captures context) | DOCUMENT |

---

## DegenerusAdmin (DegenerusAdmin.sol)

### Event Inventory

| Event | Parameters | Indexed Fields | Inherited (OZ) |
|-------|-----------|----------------|-----------------|
| CoordinatorUpdated | coordinator, subId | coordinator, subId | Custom |
| ConsumerAdded | consumer | consumer | Custom |
| SubscriptionCreated | subId | subId | Custom |
| SubscriptionCancelled | subId, to | subId, to | Custom |
| SubscriptionShutdown | subId, to, sweptAmount | subId, to | Custom |
| LinkCreditRecorded | player, amount | player | Custom |
| LinkEthFeedUpdated | feed | feed | Custom |
| ProposalCreated | proposalId, proposer, coordinator, keyHash, path | proposalId, proposer | Custom |
| VoteCast | proposalId, voter, approve, weight | proposalId, voter | Custom |
| ProposalExecuted | proposalId, coordinator, newSubId | proposalId | Custom |
| ProposalKilled | proposalId | proposalId | Custom |

### Function-by-Function Audit

| Function | Visibility | State Changes | Event Emitted | Params Match Post-State | Indexer-Critical | Finding |
|----------|-----------|--------------|---------------|------------------------|-----------------|---------|
| constructor() | -- | VRF sub creation + wiring | SubscriptionCreated + CoordinatorUpdated + ConsumerAdded | YES | YES | OK |
| setLinkEthPriceFeed(feed) | external | price feed update | LinkEthFeedUpdated(feed) | YES | YES | OK |
| swapGameEthForStEth() | external payable | forwards to game | None (game emits) | N/A | NO | EVT-DA-01 |
| stakeGameEthToStEth(amount) | external | forwards to game | None (game emits) | N/A | NO | EVT-DA-01 |
| setLootboxRngThreshold(newThreshold) | external | forwards to game | None (game emits) | N/A | NO | EVT-DA-01 |
| propose(newCoordinator, newKeyHash) | external | proposal creation | ProposalCreated(id, sender, coordinator, keyHash, path) | YES | YES | OK |
| vote(proposalId, approve) | external | vote recording + possible execute/kill | VoteCast(id, voter, approve, weight) + ProposalKilled or _executeSwap events | YES -- weight is live sDGNRS balance | YES | OK |
| shutdownVrf() | external | VRF subscription cancel | SubscriptionCancelled + SubscriptionShutdown | YES | YES | OK |
| onTokenTransfer(from, amount, _) | external | LINK forwarding + credit | LinkCreditRecorded(from, credit) | YES -- credit is computed value, not raw LINK amount | YES | OK |

**NC-17 Assessment (Missing event for critical parameter change):**

DegenerusAdmin has three admin setter functions that forward to the game contract:
1. `swapGameEthForStEth()` -- no event at admin level (game emits)
2. `stakeGameEthToStEth(amount)` -- no event at admin level (game emits)
3. `setLootboxRngThreshold(newThreshold)` -- no event at admin level (game emits)

These are thin forwarders. The game contract is responsible for emitting events on parameter changes. Adding redundant events at the admin level would waste gas. The `setLinkEthPriceFeed(feed)` function DOES emit `LinkEthFeedUpdated(feed)` since the state lives in the admin contract itself.

**Special attention: _executeSwap comprehensive event trail**
The `_executeSwap` function emits: (1) SubscriptionCancelled for old sub, (2) CoordinatorUpdated for new config, (3) SubscriptionCreated for new sub, (4) ConsumerAdded for game, (5) ProposalExecuted for the proposal, plus ProposalKilled for all voided proposals. Complete event trail for indexers to reconstruct the swap.

**Special attention: vote() side effects**
A single `vote()` call can trigger `_executeSwap` (if threshold met) or emit `ProposalKilled` (if rejection threshold met). The VoteCast event is always emitted before any side effects. Correct ordering.

### Findings

- **EVT-DA-01 (INFO):** Three admin forwarder functions (swapGameEthForStEth, stakeGameEthToStEth, setLootboxRngThreshold) emit no events. These are thin proxies to the game contract which emits its own events. Adding events here would be redundant. However, NC-17 bot findings may flag these as "critical parameter changes without events." -- Disposition: DOCUMENT

---

## DegenerusAffiliate (DegenerusAffiliate.sol)

### Event Inventory

| Event | Parameters | Indexed Fields | Inherited (OZ) |
|-------|-----------|----------------|-----------------|
| Affiliate | amount, code, sender | code | Custom |
| ReferralUpdated | player, code, referrer, locked | player, code, referrer | Custom |
| AffiliateEarningsRecorded | level, affiliate, amount, newTotal, sender, code, isFreshEth | level, affiliate, sender | Custom |
| AffiliateTopUpdated | level, player, score | level, player | Custom |

### Function-by-Function Audit

| Function | Visibility | State Changes | Event Emitted | Params Match Post-State | Indexer-Critical | Finding |
|----------|-----------|--------------|---------------|------------------------|-----------------|---------|
| constructor(...) | -- | bootstrap codes + referrals | Affiliate(1, code, owner) per code + Affiliate(0, code, player) per referral + ReferralUpdated per referral | YES | NO | OK |
| createAffiliateCode(code_, kickbackPct) | external | code registration | Affiliate(1, code_, msg.sender) | YES -- amount=1 signals code creation | NO | OK |
| referPlayer(code_) | external | referral registration | Affiliate(0, code_, msg.sender) + ReferralUpdated(player, code, referrer, locked) | YES | NO | OK |
| payAffiliate(amount, code, sender, lvl, isFreshEth, lootboxActivityScore) | external | earnings + leaderboard + distribution | AffiliateEarningsRecorded(...) + AffiliateTopUpdated if new top + Affiliate(amount, storedCode, sender) | YES -- scaledAmount is after BPS scaling and commission cap | YES | OK |

**Special attention: Affiliate event overloading**
The `Affiliate` event uses `amount` to distinguish event types: `1` = code created, `0` = player referred, `>1` = base input amount for payout. This is a single-event-for-multiple-purposes pattern. While unconventional, it works for indexers that check the `amount` field.

**Special attention: payAffiliate referral resolution emits ReferralUpdated**
When `payAffiliate` resolves a referral for the first time (stored code is bytes32(0)), it calls `_setReferralCode` which emits `ReferralUpdated`. This ensures indexers can track when referrals are locked. All code paths through referral resolution emit this event.

**Special attention: payAffiliate early return**
If `scaledAmount == 0` after BPS scaling, only `Affiliate(amount, storedCode, sender)` is emitted (no AffiliateEarningsRecorded). This is correct -- no earnings to record.

### Findings

No findings. Event coverage is complete and values match post-state.

---

## DegenerusQuests (DegenerusQuests.sol)

### Event Inventory

| Event | Parameters | Indexed Fields | Inherited (OZ) |
|-------|-----------|----------------|-----------------|
| QuestSlotRolled | day, slot, questType, flags, version, difficulty | day, slot | Custom |
| QuestProgressUpdated | player, day, slot, questType, progress, target | player, day, slot | Custom |
| QuestCompleted | player, day, slot, questType, streak, reward | player, day, slot | Custom |
| QuestStreakShieldUsed | player, used, remaining, currentDay | player | Custom |
| QuestStreakBonusAwarded | player, amount, newStreak, currentDay | player | Custom |
| QuestStreakReset | player, previousStreak, currentDay | player | Custom |

### Function-by-Function Audit

| Function | Visibility | State Changes | Event Emitted | Params Match Post-State | Indexer-Critical | Finding |
|----------|-----------|--------------|---------------|------------------------|-----------------|---------|
| rollDailyQuest(day, entropy) | external | quest slot seeding | QuestSlotRolled(day, slot, ...) x2 | YES -- version/difficulty reflect actual seeded values | NO | OK |
| handleMint(player, quantity, paidWithEth) | external | progress update | QuestProgressUpdated + QuestCompleted if completed + QuestStreakShieldUsed/QuestStreakReset if needed | YES | NO | OK |
| handleFlip(player, amount) | external | progress update | QuestProgressUpdated + QuestCompleted if completed | YES | NO | OK |
| handleAffiliate(player, amount) | external | progress update | QuestProgressUpdated + QuestCompleted if completed | YES | NO | OK |
| handleDecimator(player, amount) | external | progress update | QuestProgressUpdated + QuestCompleted if completed | YES | NO | OK |
| handleLootBox(player, amountWei) | external | progress update | QuestProgressUpdated + QuestCompleted if completed | YES | NO | OK |
| handleDegenerette(player, amount, paidWithEth) | external | progress update | QuestProgressUpdated + QuestCompleted if completed | YES | NO | OK |
| awardQuestStreakBonus(player, amount, currentDay) | external | streak increase | QuestStreakBonusAwarded(player, amount, newStreak, currentDay) | YES | NO | OK |

**Special attention: streak tracking events**
Quest completion triggers streak accounting which may emit QuestStreakShieldUsed (if shields consumed for missed days), QuestStreakReset (if missed days exceed shields), or neither (consecutive days). All paths emit appropriate events.

### Findings

No findings. Event coverage is comprehensive with events for every state transition.

---

## DegenerusJackpots (DegenerusJackpots.sol)

### Event Inventory

| Event | Parameters | Indexed Fields | Inherited (OZ) |
|-------|-----------|----------------|-----------------|
| BafFlipRecorded | player, lvl, amount, newTotal | player, lvl | Custom |

### Function-by-Function Audit

| Function | Visibility | State Changes | Event Emitted | Params Match Post-State | Indexer-Critical | Finding |
|----------|-----------|--------------|---------------|------------------------|-----------------|---------|
| recordBafFlip(player, lvl, amount) | external | BAF total + leaderboard update | BafFlipRecorded(player, lvl, amount, newTotal) | YES -- newTotal is actual post-update value | NO | OK |
| runBafJackpot(poolWei, lvl, rngWord) | external | BAF epoch increment + leaderboard clear | None | N/A -- returns winners/amounts to game which handles distribution events | YES | EVT-JK-01 |

**Special attention: runBafJackpot has no events**
`runBafJackpot` returns winner arrays to the game contract, which handles the actual ETH distribution and event emission. The jackpot contract is a computation-only helper. This is consistent with the delegatecall architecture where the game emits all distribution events.

### Findings

- **EVT-JK-01 (INFO):** `runBafJackpot` emits no event despite modifying BAF state (epoch increment, leaderboard reset). The game contract emits jackpot distribution events. An off-chain indexer wanting to track BAF epoch transitions would need to monitor the game contract's jackpot resolution events rather than DegenerusJackpots directly. -- Disposition: DOCUMENT

---

## DegenerusDeityPass (DegenerusDeityPass.sol)

### Event Inventory

| Event | Parameters | Indexed Fields | Inherited (OZ) |
|-------|-----------|----------------|-----------------|
| Transfer | from, to, tokenId | from, to, tokenId | Custom (ERC721-compatible) |
| Approval | owner, approved, tokenId | owner, approved, tokenId | Custom (ERC721-compatible) |
| ApprovalForAll | owner, operator, approved | owner, operator | Custom (ERC721-compatible) |
| OwnershipTransferred | previousOwner, newOwner | previousOwner, newOwner | Custom |
| RendererUpdated | previousRenderer, newRenderer | previousRenderer, newRenderer | Custom |
| RenderColorsUpdated | outlineColor, backgroundColor, nonCryptoSymbolColor | (none) | Custom |

### Function-by-Function Audit

| Function | Visibility | State Changes | Event Emitted | Params Match Post-State | Indexer-Critical | Finding |
|----------|-----------|--------------|---------------|------------------------|-----------------|---------|
| constructor() | -- | owner set | OwnershipTransferred(0, msg.sender) | YES | NO | OK |
| transferOwnership(newOwner) | external | owner update | OwnershipTransferred(prev, newOwner) | YES -- emits old+new values (NC-11 compliant) | YES | OK |
| setRenderer(newRenderer) | external | renderer update | RendererUpdated(prev, newRenderer) | YES -- emits old+new values (NC-11 compliant) | NO | OK |
| setRenderColors(outline, bg, nonCrypto) | external | color strings update | RenderColorsUpdated(outlineColor, backgroundColor, nonCryptoSymbolColor) | YES | NO | OK |
| approve(_, _) | external pure | reverts (Soulbound) | None | N/A | N/A | OK |
| setApprovalForAll(_, _) | external pure | reverts (Soulbound) | None | N/A | N/A | OK |
| transferFrom(_, _, _) | external pure | reverts (Soulbound) | None | N/A | N/A | OK |
| safeTransferFrom(_, _, _) | external pure | reverts (Soulbound) | None | N/A | N/A | OK |
| safeTransferFrom(_, _, _, _) | external pure | reverts (Soulbound) | None | N/A | N/A | OK |
| mint(to, tokenId) | external | NFT mint | Transfer(0, to, tokenId) | YES | YES | OK |

**Special attention: soulbound enforcement**
All transfer/approve functions revert with `Soulbound()`. No events emitted on reverts. Transfer event only fires on mint. Correct for soulbound ERC721.

**Special attention: NC-11 compliance**
`transferOwnership` and `setRenderer` both emit old+new values in their events. `setRenderColors` emits all three new color values (no old values -- colors are cosmetic, not critical parameters).

### Findings

No findings. Event coverage is complete. NC-11 (old+new values) is satisfied for critical parameter changes.

---

## Periphery Contracts

### ContractAddresses.sol (39 lines)
**Type:** Pure library of compile-time constants.
**State-changing functions:** None.
**Events:** None.
**Assessment:** No events needed. Pure constant address registry with no state.

### Icons32Data.sol (228 lines)
**Type:** Static data contract for icon SVG path data.
**State-changing functions:** None.
**Events:** None.
**Assessment:** No events needed. Pure view functions returning static string data.

### DegenerusTraitUtils.sol (183 lines)
**Type:** Pure utility library for trait calculations.
**State-changing functions:** None.
**Events:** None.
**Assessment:** No events needed. Pure math functions with no state modifications.

### DeityBoonViewer.sol (171 lines)
**Type:** View-only contract for aggregating deity boon data.
**State-changing functions:** None.
**Events:** None.
**Assessment:** No events needed. Pure view aggregator.

---

## Libraries

### BitPackingLib.sol (88 lines)
**Events:** None. Pure bit manipulation library.

### EntropyLib.sol (24 lines)
**Events:** None. Pure entropy/RNG utility.

### GameTimeLib.sol (35 lines)
**Events:** None. Pure time calculation utility.

### JackpotBucketLib.sol (307 lines)
**Events:** None. Pure jackpot math library.

### PriceLookupLib.sol (47 lines)
**Events:** None. Pure price calculation library.

**Libraries confirmed: All 5 libraries contain zero event declarations and zero emit statements. Pure computation only.**

---

## NC-17 Cross-Reference (Missing event for critical parameter change)

The 4naly3er NC-17 category flagged 27 instances of "missing event for critical parameter change" across the codebase. For non-game contracts:

| Contract | Function | Parameter Changed | Event Emitted | NC-17 Status |
|----------|----------|-------------------|---------------|-------------|
| DegenerusAdmin | setLinkEthPriceFeed | linkEthPriceFeed | LinkEthFeedUpdated(feed) | COVERED |
| DegenerusAdmin | swapGameEthForStEth | (forwards to game) | Game emits | COVERED (forwarded) |
| DegenerusAdmin | stakeGameEthToStEth | (forwards to game) | Game emits | COVERED (forwarded) |
| DegenerusAdmin | setLootboxRngThreshold | (forwards to game) | Game emits | COVERED (forwarded) |
| DegenerusDeityPass | transferOwnership | _contractOwner | OwnershipTransferred | COVERED |
| DegenerusDeityPass | setRenderer | renderer | RendererUpdated | COVERED |
| DegenerusDeityPass | setRenderColors | color strings | RenderColorsUpdated | COVERED |

All critical parameter changes in non-game contracts emit events. The three admin forwarders rely on the game contract's events (EVT-DA-01).

---

## Summary of Findings (Task 2)

| ID | Contract | Severity | Description | Disposition |
|----|----------|----------|-------------|-------------|
| EVT-DA-01 | DegenerusAdmin | INFO | Three admin forwarder functions emit no events (game emits its own) | DOCUMENT |
| EVT-JK-01 | DegenerusJackpots | INFO | runBafJackpot emits no event for epoch/leaderboard reset (game handles distribution events) | DOCUMENT |

---

## Combined Summary (All Non-Game Contracts)

**Total contracts audited:** 21 (7 token/vault + 5 admin/governance + 4 periphery + 5 libraries)
**Total state-changing functions audited:** 108
**Total findings:** 12 (all INFO, all DOCUMENT disposition)
**Critical parameter changes without events:** 0 (all covered or forwarded)
**Libraries with events:** 0 (confirmed pure computation)
**Periphery with events:** 0 (confirmed view/data only)
**Slither DOC-02:** Cross-referenced and assessed (non-game _payEth patterns are covered by higher-level events)

---

## Appendix: Bot-Race Findings Disposition (Phase 130 Handoff)

This appendix maps all 108 event-related bot findings (107 from 4naly3er + 1 from Slither) routed to Phase 132 during Phase 130 triage. Each instance is assigned a disposition: **AGREE** (independently found in main audit above), **FP** (false positive), or **DOCUMENT** (valid but intentional/acceptable).

Per D-04, indexed field findings (NC-10/NC-33) are triaged against the indexer-critical standard, not against "every address should be indexed."

---

### NC-9: Event is never emitted (2 instances)

| # | Location | Event | Disposition | Reasoning |
|---|----------|-------|-------------|-----------|
| 1 | DegenerusDeityPass.sol:48 | `Approval(address indexed owner, address indexed approved, uint256 indexed tokenId)` | FP | Soulbound ERC721 -- `approve()` reverts with `Soulbound()`. Event is declared for ERC721 interface compliance but correctly never emitted. Removing the declaration would break ERC721 ABI compatibility. |
| 2 | DegenerusDeityPass.sol:49 | `ApprovalForAll(address indexed owner, address indexed operator, bool approved)` | FP | Same as #1. `setApprovalForAll()` reverts with `Soulbound()`. Declaration required for ERC721 ABI. |

---

### NC-10: Event missing indexed field (4 instances)

| # | Location | Event | Disposition | Reasoning |
|---|----------|-------|-------------|-----------|
| 1 | DegenerusDeityPass.sol:52 | `RenderColorsUpdated(string, string, string)` | FP | String fields cannot be indexed in Solidity (indexed strings hash to bytes32, losing the value). Non-indexer-critical cosmetic event. |
| 2 | DegenerusGame.sol:122 | `LootboxRngThresholdUpdated(uint256 previous, uint256 current)` | DOCUMENT | Admin config change event. Not indexer-critical (admin operations are infrequent). Indexing uint256 values provides limited benefit for filtering. |
| 3 | DegenerusStonk.sol:244 | `YearSweep(uint256, uint256, uint256, uint256)` | AGREE | Cross-ref EVT-DS-01. Once-per-game permissionless call. Indexed fields not needed for filtering but noted for completeness. |
| 4 | GNRUS.sol:114 | `GameOverFinalized(uint256, uint256, uint256)` | DOCUMENT | Once-per-game event. Not indexer-critical for filtering. Fields are all uint256 values, not addresses/IDs. |

---

### NC-11: Events should contain old+new value (7 instances)

| # | Location | Event | Disposition | Reasoning |
|---|----------|-------|-------------|-----------|
| 1 | DegenerusAdmin.sol:357 | `setLinkEthPriceFeed` -- `LinkEthFeedUpdated(feed)` | DOCUMENT | Emits only new feed address. Old value not included. Valid finding -- parameter change events should show old+new for monitoring. |
| 2 | DegenerusDeityPass.sol:97 | `setRenderer` -- `RendererUpdated(prev, newRenderer)` | FP | Already emits both old (`prev`) and new (`newRenderer`) values. Bot incorrectly flagged this. |
| 3 | DegenerusDeityPass.sol:107 | `setRenderColors` -- `RenderColorsUpdated(outline, bg, nonCrypto)` | DOCUMENT | Emits only new color values. Old values not included. Cosmetic parameter -- low impact. |
| 4 | DegenerusGame.sol:468 | `setOperatorApproval` -- `OperatorApproval(owner, operator, approved)` | FP | This is a boolean toggle, not a parameter change. The event shows the current state (approved: true/false). Old+new is implicit -- the opposite of emitted value. |
| 5 | DegenerusGame.sol:512 | `setLootboxRngThreshold` -- `LootboxRngThresholdUpdated(prev, newThreshold)` | FP | Already emits both old (`prev`) and new (`newThreshold`) values. Bot incorrectly flagged this. |
| 6 | DegenerusGame.sol:512 | Duplicate of #5 | FP | Duplicate instance in bot report (same function appears twice in scope). |
| 7 | DegenerusGame.sol:1466 | `setDecimatorAutoRebuy` -- `DecimatorAutoRebuyToggled(player, enabled)` | FP | Boolean toggle, not parameter change. Same reasoning as #4. |

---

### NC-17: Missing event for critical parameter change (27 instances)

| # | Location | Function | Disposition | Reasoning |
|---|----------|----------|-------------|-----------|
| 1 | BurnieCoinflip.sol:215 | `settleFlipModeChange(player)` | AGREE | Cross-ref EVT-CF-01. Internal accounting settlement, no event. |
| 2 | BurnieCoinflip.sol:674 | `setCoinflipAutoRebuy(player, enabled, takeProfit)` | FP | Function DOES emit `CoinflipAutoRebuyToggled` + `CoinflipAutoRebuyStopSet` events via `_setCoinflipAutoRebuy`. Bot did not trace into private helper. |
| 3 | BurnieCoinflip.sol:689 | `setCoinflipAutoRebuyTakeProfit(player, takeProfit)` | FP | Function DOES emit `CoinflipAutoRebuyStopSet` via `_setCoinflipAutoRebuyTakeProfit`. Bot did not trace into private helper. |
| 4 | DegenerusAdmin.sol:71 | `updateVrfCoordinatorAndSub` (interface declaration) | FP | Interface declaration, not an implementation. The implementation in AdvanceModule emits `VrfCoordinatorUpdated`. |
| 5 | DegenerusAdmin.sol:86 | `setLootboxRngThreshold` (interface declaration) | FP | Interface declaration. The game contract implementation emits `LootboxRngThresholdUpdated`. |
| 6 | DegenerusAdmin.sol:383 | `setLootboxRngThreshold(newThreshold)` | AGREE | Cross-ref EVT-DA-01. Admin forwarder, no event at admin level. Game emits its own event. |
| 7 | DegenerusGame.sol:1457 | `setAutoRebuy(player, enabled)` | FP | Function emits `AutoRebuyToggled(player, enabled)` via `_setAutoRebuy`. Bot matched the wrong line (line 1457 is inside the function body, not the emit). |
| 8 | DegenerusGame.sol:1482 | `setAutoRebuyTakeProfit(player, takeProfit)` | FP | Function emits `AutoRebuyTakeProfitSet(player, takeProfit)` via `_setAutoRebuyTakeProfit`. Same bot issue. |
| 9 | DegenerusGame.sol:1555 | `setAfKingMode(player, enabled, ethTP, coinTP)` | FP | Function emits `AfKingModeToggled`, `AutoRebuyToggled`, and `AutoRebuyTakeProfitSet` via `_setAfKingMode`. Multiple events for the multi-parameter change. |
| 10 | DegenerusGame.sol:1879 | `updateVrfCoordinatorAndSub(newCoord, newSub, newKey)` | FP | Delegatecalls to AdvanceModule which emits `VrfCoordinatorUpdated`. Bot cannot trace through delegatecall. |
| 11 | DegenerusVault.sol:24 (1st) | `setDecimatorAutoRebuy` (interface) | FP | Interface declaration. Game implementation emits events. |
| 12 | DegenerusVault.sol:24 (2nd) | Duplicate of #11 | FP | Duplicate in bot report. |
| 13 | DegenerusVault.sol:36 (1st) | `setAutoRebuy` (interface) | FP | Interface declaration. Game implementation emits events. |
| 14 | DegenerusVault.sol:36 (2nd) | Duplicate of #13 | FP | Duplicate in bot report. |
| 15 | DegenerusVault.sol:37 (1st) | `setAutoRebuyTakeProfit` (interface) | FP | Interface declaration. |
| 16 | DegenerusVault.sol:37 (2nd) | Duplicate of #15 | FP | Duplicate in bot report. |
| 17 | DegenerusVault.sol:38 (1st) | `setAfKingMode` (interface) | FP | Interface declaration. |
| 18 | DegenerusVault.sol:38 (2nd) | Duplicate of #17 | FP | Duplicate in bot report. |
| 19 | DegenerusVault.sol:44 (1st) | `setOperatorApproval` (interface) | FP | Interface declaration. Game implementation emits events. |
| 20 | DegenerusVault.sol:44 (2nd) | Duplicate of #19 | FP | Duplicate in bot report. |
| 21 | DegenerusVault.sol:58 (1st) | `setCoinflipAutoRebuy` (interface) | FP | Interface declaration. Coinflip implementation emits events. |
| 22 | DegenerusVault.sol:58 (2nd) | Duplicate of #21 | FP | Duplicate in bot report. |
| 23 | DegenerusVault.sol:59 (1st) | `setCoinflipAutoRebuyTakeProfit` (interface) | FP | Interface declaration. |
| 24 | DegenerusVault.sol:59 (2nd) | Duplicate of #23 | FP | Duplicate in bot report. |
| 25 | Icons32Data.sol:153 | `setPaths(startIndex, paths)` | DOCUMENT | Cosmetic data setter (SVG icon paths). No event emitted. Pre-deploy-only function (reverts after finalization). Low impact. |
| 26 | Icons32Data.sol:171 | `setSymbols(quadrant, symbols)` | DOCUMENT | Same as #25. Cosmetic data setter, pre-deploy only. |
| 27 | StakedDegenerusStonk.sol:11 | `setAfKingMode` (interface) | FP | Interface declaration. Game implementation emits events. |

---

### NC-33: Event is missing indexed fields (67 instances)

Per D-04, indexed fields are evaluated against the indexer-critical standard. Events that already index the most useful filter fields (addresses, IDs) are not penalized for leaving value fields unindexed. String fields cannot be meaningfully indexed.

| # | File | Event | Disposition | Reasoning |
|---|------|-------|-------------|-----------|
| 1 | BurnieCoin.sol:50 | `Transfer(from indexed, to indexed, amount)` | FP | Already indexes both addresses (2 of 3 fields). `amount` is a value, not a filter key. |
| 2 | BurnieCoin.sol:53 | `Approval(owner indexed, spender indexed, amount)` | FP | Already indexes both addresses. `amount` is a value. |
| 3 | BurnieCoin.sol:63 | `DecimatorBurn(player indexed, amountBurned, bucket)` | DOCUMENT | `bucket` could be indexed for filtering burns by bucket. Low priority -- decimator burns are trackable via `player`. |
| 4 | BurnieCoin.sol:70 | `TerminalDecimatorBurn(player indexed, amountBurned)` | FP | Only 2 fields, 1 indexed. `amountBurned` is a value, not useful as filter. |
| 5 | BurnieCoin.sol:79 | `DailyQuestRolled(day indexed, questType, highDifficulty)` | DOCUMENT | `questType` could be indexed for quest-type filtering. Low priority. |
| 6 | BurnieCoin.sol:90 | `QuestCompleted(player indexed, questType, streak, reward)` | DOCUMENT | `questType` could be indexed. Low priority. |
| 7 | BurnieCoin.sol:100 | `LinkCreditRecorded(player indexed, amount)` | FP | Only 2 fields, 1 indexed. Sufficient. |
| 8 | BurnieCoin.sol:105 | `VaultEscrowRecorded(sender indexed, amount)` | FP | Only 2 fields, 1 indexed. Sufficient. |
| 9 | BurnieCoin.sol:109 | `VaultAllowanceSpent(spender indexed, amount)` | FP | Only 2 fields, 1 indexed. Sufficient. |
| 10 | BurnieCoinflip.sol:41 | `CoinflipDeposit(player indexed, creditedFlip)` | FP | Only 2 fields, 1 indexed. Sufficient. |
| 11 | BurnieCoinflip.sol:42 | `CoinflipAutoRebuyToggled(player indexed, enabled)` | FP | Only 2 fields, 1 indexed. Sufficient. |
| 12 | BurnieCoinflip.sol:43 | `CoinflipAutoRebuyStopSet(player indexed, stopAmount)` | FP | Only 2 fields, 1 indexed. Sufficient. |
| 13 | BurnieCoinflip.sol:44 | `QuestCompleted(player indexed, questType, streak, reward)` | DOCUMENT | Same as #6. `questType` could be indexed. |
| 14 | BurnieCoinflip.sol:55 | `CoinflipStakeUpdated(player indexed, day indexed, amount, newTotal)` | FP | Already indexes 2 of 4 fields (player + day). Sufficient for filtering. |
| 15 | BurnieCoinflip.sol:68 | `CoinflipDayResolved(day indexed, win, rewardPercent, bountyAfter, bountyPaid, bountyRecipient)` | DOCUMENT | `bountyRecipient` (address) could be indexed. 1 of 6 fields indexed. |
| 16 | BurnieCoinflip.sol:80 | `CoinflipTopUpdated(day indexed, player indexed, score)` | FP | Already indexes 2 of 3 fields. Sufficient. |
| 17 | BurnieCoinflip.sol:88 | `BiggestFlipUpdated(player indexed, recordAmount)` | FP | Only 2 fields, 1 indexed. Sufficient. |
| 18 | BurnieCoinflip.sol:89 | `BountyOwed(player indexed, bounty, recordFlip)` | FP | `player` is indexed. `bounty`/`recordFlip` are values. Sufficient. |
| 19 | BurnieCoinflip.sol:90 | `BountyPaid(to indexed, amount)` | FP | Only 2 fields, 1 indexed. Sufficient. |
| 20 | DegenerusAdmin.sol:200 | `SubscriptionShutdown(subId indexed, to indexed, sweptAmount)` | FP | Already indexes 2 of 3 fields. Sufficient. |
| 21 | DegenerusAdmin.sol:205 | `LinkCreditRecorded(player indexed, amount)` | FP | Only 2 fields, 1 indexed. Sufficient. |
| 22 | DegenerusAdmin.sol:209 | `ProposalCreated(... proposalId indexed, proposer indexed, ...)` | FP | Already indexes 2 of 5 fields. Key filter fields covered. |
| 23 | DegenerusAdmin.sol:216 | `VoteCast(proposalId indexed, voter indexed, approve, weight)` | FP | Already indexes 2 of 4 fields. Sufficient. |
| 24 | DegenerusAdmin.sol:222 | `ProposalExecuted(proposalId indexed, coordinator, newSubId)` | DOCUMENT | `coordinator` (address) could be indexed. Low priority -- proposals are rare governance events. |
| 25 | DegenerusAffiliate.sol:72 | `Affiliate(amount, code indexed, sender)` | DOCUMENT | `sender` (address) could be indexed. Currently only `code` is indexed. |
| 26 | DegenerusAffiliate.sol:105 | `AffiliateTopUpdated(level indexed, player indexed, score)` | FP | Already indexes 2 of 3 fields. Sufficient. |
| 27 | DegenerusDeityPass.sol:49 | `ApprovalForAll(owner indexed, operator indexed, approved)` | FP | Already indexes 2 of 3 fields. Soulbound -- event never emitted anyway. |
| 28 | DegenerusDeityPass.sol:52 | `RenderColorsUpdated(string, string, string)` | FP | String fields cannot be meaningfully indexed (hashed to bytes32). Cosmetic event. |
| 29 | DegenerusGame.sol:122 | `LootboxRngThresholdUpdated(uint256, uint256)` | DOCUMENT | Admin config event with no indexed fields. Not indexer-critical. Same as NC-10 #2. |
| 30 | DegenerusGame.sol:127 | `OperatorApproval(owner indexed, operator indexed, approved)` | FP | Already indexes 2 of 3 fields. Sufficient. |
| 31 | DegenerusGame.sol:1304 | `WinningsClaimed(player indexed, caller indexed, amount)` | FP | Already indexes 2 of 3 fields. `amount` is a value. Sufficient. |
| 32 | DegenerusGame.sol:1317 | `ClaimableSpent(player indexed, amount, newBalance, payKind, costWei)` | DOCUMENT | Only 1 of 5 fields indexed. `payKind` could be indexed for filtering by payment type. |
| 33 | DegenerusGame.sol:1436 | `DecimatorAutoRebuyToggled(player indexed, enabled)` | FP | Only 2 fields, 1 indexed. Sufficient. |
| 34 | DegenerusGame.sol:1439 | `AutoRebuyTakeProfitSet(player indexed, takeProfit)` | FP | Only 2 fields, 1 indexed. Sufficient. |
| 35 | DegenerusGame.sol:1442 | `AfKingModeToggled(player indexed, enabled)` | FP | Only 2 fields, 1 indexed. Sufficient. |
| 36 | DegenerusGame.sol:1445 | `AutoRebuyToggled(player indexed, enabled)` | FP | Only 2 fields, 1 indexed. Sufficient. |
| 37 | DegenerusJackpots.sol:64 | `BafFlipRecorded(player indexed, lvl indexed, amount, newTotal)` | FP | Already indexes 2 of 4 fields. Sufficient. |
| 38 | DegenerusQuests.sol:65 | `QuestSlotRolled(day indexed, slot indexed, questType, flags, version, difficulty)` | DOCUMENT | Already indexes 2 of 6 fields. Could index `questType`. Low priority. |
| 39 | DegenerusQuests.sol:95 | `QuestStreakShieldUsed(player indexed, used, remaining, currentDay)` | DOCUMENT | Only 1 of 4 indexed. `currentDay` could be indexed. Low priority. |
| 40 | DegenerusQuests.sol:103 | `QuestStreakBonusAwarded(player indexed, amount, newStreak, currentDay)` | DOCUMENT | Only 1 of 4 indexed. Same as #39. |
| 41 | DegenerusQuests.sol:111 | `QuestStreakReset(player indexed, previousStreak, currentDay)` | FP | Only 3 fields, 1 indexed. `previousStreak`/`currentDay` are values, not useful filters. |
| 42 | DegenerusStonk.sol:52 | `Transfer(from indexed, to indexed, amount)` | FP | Already indexes 2 of 3 fields. Standard ERC-20. |
| 43 | DegenerusStonk.sol:54 | `Approval(owner indexed, spender indexed, amount)` | FP | Already indexes 2 of 3 fields. Standard ERC-20. |
| 44 | DegenerusStonk.sol:56 | `BurnThrough(from indexed, amount, ethOut, stethOut, burnieOut)` | DOCUMENT | Only 1 of 5 indexed. Could index additional field but `from` is the primary filter. |
| 45 | DegenerusStonk.sol:58 | `UnwrapTo(recipient indexed, amount)` | FP | Only 2 fields, 1 indexed. Sufficient. |
| 46 | DegenerusStonk.sol:244 | `YearSweep(uint256, uint256, uint256, uint256)` | AGREE | Cross-ref EVT-DS-01. No indexed fields on a once-per-game event. Same as NC-10 #3. |
| 47 | DegenerusVault.sol:156 | `Transfer(from indexed, to indexed, amount)` | FP | Already indexes 2 of 3 fields. Standard. |
| 48 | DegenerusVault.sol:161 | `Approval(owner indexed, spender indexed, amount)` | FP | Already indexes 2 of 3 fields. Standard. |
| 49 | DegenerusVault.sol:332 | `Deposit(from indexed, ethAmount, stEthAmount, coinAmount)` | DOCUMENT | Only 1 of 4 indexed. Deposit events are indexer-critical. However, `from` is the primary filter key. |
| 50 | DegenerusVault.sol:339 | `Claim(from indexed, sharesBurned, ethOut, stEthOut, coinOut)` | DOCUMENT | Only 1 of 5 indexed. Same reasoning as #49. |
| 51 | GNRUS.sol:96 | `Transfer(from indexed, to indexed, amount)` | FP | Already indexes 2 of 3 fields. Standard. |
| 52 | GNRUS.sol:99 | `Burn(burner indexed, gnrusAmount, ethOut, stethOut)` | FP | Only 1 of 4 indexed, but `burner` is the primary filter. Values are not useful as filters. |
| 53 | GNRUS.sol:108 | `LevelResolved(level indexed, winningProposalId indexed, recipient, gnrusDistributed)` | DOCUMENT | Already indexes 2 of 4. `recipient` (address) could be indexed as 3rd field. |
| 54 | GNRUS.sol:114 | `GameOverFinalized(uint256, uint256, uint256)` | DOCUMENT | No indexed fields. Same as NC-10 #4. Once-per-game event. |
| 55 | StakedDegenerusStonk.sol:101 | `Transfer(from indexed, to indexed, amount)` | FP | Already indexes 2 of 3 fields. Standard. |
| 56 | StakedDegenerusStonk.sol:109 | `Burn(from indexed, amount, ethOut, stethOut, burnieOut)` | DOCUMENT | Only 1 of 5 indexed. Same as DegenerusStonk BurnThrough. |
| 57 | StakedDegenerusStonk.sol:116 | `Deposit(from indexed, ethAmount, stethAmount, burnieAmount)` | FP | Only 1 of 4 indexed, but `from` is the only filterable field. Amounts are values. |
| 58 | StakedDegenerusStonk.sol:122 | `PoolTransfer(pool indexed, to indexed, amount)` | FP | Already indexes 2 of 3 fields. Sufficient. |
| 59 | StakedDegenerusStonk.sol:128 | `PoolRebalance(from indexed, to indexed, amount)` | FP | Already indexes 2 of 3 fields. Sufficient. |
| 60 | StakedDegenerusStonk.sol:131 | `RedemptionSubmitted(player indexed, sdgnrsAmount, ethValueOwed, burnieOwed, periodIndex)` | DOCUMENT | Only 1 of 5 indexed. `periodIndex` could be indexed for filtering by period. |
| 61 | StakedDegenerusStonk.sol:134 | `RedemptionResolved(periodIndex indexed, roll, rolledBurnie, flipDay)` | FP | Primary filter key (`periodIndex`) is indexed. Other fields are values. |
| 62 | StakedDegenerusStonk.sol:137 | `RedemptionClaimed(player indexed, roll, flipResolved, ethPayout, burniePayout, lootboxEth)` | DOCUMENT | Only 1 of 6 indexed. Indexer-critical event with many value fields. |
| 63 | WrappedWrappedXRP.sol:51 | `Transfer(from indexed, to indexed, amount)` | FP | Already indexes 2 of 3 fields. Standard. |
| 64 | WrappedWrappedXRP.sol:57 | `Approval(owner indexed, spender indexed, amount)` | FP | Already indexes 2 of 3 fields. Standard. |
| 65 | WrappedWrappedXRP.sol:66 | `Unwrapped(user indexed, amount)` | FP | Only 2 fields, 1 indexed. Sufficient. |
| 66 | WrappedWrappedXRP.sol:71 | `Donated(donor indexed, amount)` | FP | Only 2 fields, 1 indexed. Sufficient. |
| 67 | WrappedWrappedXRP.sol:76 | `VaultAllowanceSpent(spender indexed, amount)` | FP | Only 2 fields, 1 indexed. Sufficient. |

---

### Slither DOC-02: events-maths (1 instance)

| # | Location | Finding | Disposition | Reasoning |
|---|----------|---------|-------------|-----------|
| 1 | DegenerusGame.sol:1725-1775 | `resolveRedemptionLootbox` -- `claimablePool -= amount` without dedicated event | AGREE | Cross-ref EVT-GAME-03. The function moves ETH from claimablePool to futurePrizePool without emitting an event for the accounting reclassification. The delegatecalled lootbox module emits resolution events for the higher-level operation. |

---

### Bot-Race Appendix Summary

| Category | Instances | Agree | FP | Document |
|----------|-----------|-------|----|----------|
| NC-9: Event never emitted | 2 | 0 | 2 | 0 |
| NC-10: Event missing indexed field | 4 | 1 | 1 | 2 |
| NC-11: Old+new value missing | 7 | 0 | 5 | 2 |
| NC-17: Missing event for parameter change | 27 | 2 | 22 | 3 |
| NC-33: Event missing indexed fields | 67 | 1 | 42 | 24 |
| Slither DOC-02: events-maths | 1 | 1 | 0 | 0 |
| **Total** | **108** | **5** | **72** | **31** |

**Key observations:**
- **72 of 108 (67%) are false positives** -- the bot cannot trace through delegatecall, interface declarations, or private helper functions.
- **NC-17 is 81% FP** (22/27) because the bot flags interface declarations and vault forwarding functions, neither of which are implementations.
- **NC-33 is 63% FP** (42/67) because most events already index the primary filter field(s); the bot applies a blanket "index all fields" rule.
- **5 AGREE findings** independently confirmed by the main audit above: EVT-DS-01 (YearSweep), EVT-CF-01 (settleFlipModeChange), EVT-DA-01 (admin forwarder), EVT-GAME-03 (resolveRedemptionLootbox).
