# Event Correctness Audit: Game System (Partial Report)

**Scope:** DegenerusGame.sol (router), DegenerusGameStorage.sol (shared storage + event declarations), and all 12 game modules.

**Methodology (D-02):** Three passes per external/public state-changing function:
1. Event exists for the state change
2. Emitted parameter values match actual post-state (no stale locals, no pre-update snapshots)
3. Indexer-critical transitions emit sufficient data for off-chain reconstruction

**Disposition policy (D-03):** Default is DOCUMENT, not fix. No contract code changes.

**Indexed field policy (D-04):** Only evaluated on indexer-critical events, not cosmetic/bookkeeping events.

**Architecture note:** All modules run via `delegatecall` from DegenerusGame. Events emitted in modules execute in DegenerusGame's context -- this is correct behavior.

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
