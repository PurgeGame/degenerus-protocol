# Protocol-Wide ETH Flow Map

**Scope:** All ETH-handling contracts across the Degenerus protocol
**Date:** 2026-03-07
**Source:** Phases 50-56 ETH mutation path data + direct source verification

---

## 1. ETH Entry Points

Every path through which ETH enters the protocol from external callers.

| # | Contract | Function | Trigger | Initial Destination | Split Details |
|---|----------|----------|---------|---------------------|---------------|
| E1 | DegenerusGame | `purchase(address,uint256,uint256,bytes32,MintPaymentKind)` external payable | Player ticket purchase (DirectEth or Combined) | recordMint -> prize pool splits | currentPrizePool + nextPrizePool + futurePrizePool (configurable BPS split) |
| E2 | DegenerusGame | `purchase()` -- lootbox portion | Player ticket+lootbox purchase | futurePrizePool + nextPrizePool (+ VAULT in presale) | Normal: 90% future / 10% next; Presale: 40% future / 40% next / 20% VAULT |
| E3 | DegenerusGame | `purchaseWhaleBundle(address,uint256)` external payable | Player whale bundle purchase | futurePrizePool + nextPrizePool | Level 0: 70% future / 30% next; Level >0: 95% future / 5% next |
| E4 | DegenerusGame | `purchaseLazyPass(address)` external payable | Player lazy pass purchase | futurePrizePool + nextPrizePool | 10% future / 90% next (all levels) |
| E5 | DegenerusGame | `purchaseDeityPass(address,uint8)` external payable | Player deity pass purchase | futurePrizePool + nextPrizePool | Level 0: 70% future / 30% next; Level >0: 95% future / 5% next |
| E6 | DegenerusGame | `placeFullTicketBets(address,uint8,uint128,uint8,uint32,uint8)` external payable | Player degenerette ETH bet | futurePrizePool | 100% to futurePrizePool |
| E7 | DegenerusGame | `adminSwapEthForStEth(address,uint256)` external payable | Admin ETH-for-stETH swap | Contract ETH balance (net neutral: ETH in, stETH out) | Admin sends ETH, receives equal stETH; value-neutral swap |
| E8 | DegenerusGame | `receive()` external payable | Direct ETH transfer to Game | futurePrizePool | 100% to futurePrizePool; reverts if gameOver |
| E9 | DegenerusVault | `deposit(uint256,uint256)` external payable | Game deposits ETH to Vault | Vault ETH balance | Game-only; part of mint/lootbox presale flow |
| E10 | DegenerusVault | `receive()` external payable | Any ETH donation to Vault | Vault ETH balance | Unrestricted; increases DGVE backing |
| E11 | DegenerusVault | `gamePurchase(...)` external payable | Vault owner purchases tickets | Forwarded to Game via purchase{value} | msg.value + ethValue from vault balance |
| E12 | DegenerusVault | `gamePurchaseDeityPassFromBoon(uint256)` external payable | Vault owner deity pass from boon | Forwarded to Game via purchaseDeityPass{value} | Uses vault ETH + auto-claimed winnings if underfunded |
| E13 | DegenerusVault | `gameDegeneretteBetEth(...)` external payable | Vault owner degenerette ETH bet | Forwarded to Game via placeFullTicketBets{value} | msg.value + ethValue from vault balance |
| E14 | DegenerusStonk | `gamePurchase(...)` external payable | DGNRS holder purchases tickets | Forwarded to Game via purchase{value} | msg.value forwarded to Game |
| E15 | DegenerusStonk | `gameDegeneretteBetEth(...)` external payable | DGNRS holder degenerette ETH bet | Forwarded to Game via placeFullTicketBets{value} | msg.value forwarded to Game |
| E16 | DegenerusStonk | `receive()` external payable | Game deposits ETH to DGNRS | DGNRS ETH balance | Game-only (onlyGame modifier) |
| E17 | DegenerusAdmin | `swapGameEthForStEth()` external payable | Admin ETH-for-stETH swap relay | Forwarded to Game via adminSwapEthForStEth{value} | Relays msg.value to Game contract |

**Note on proxy entry points:** E11-E15, E17 are proxy entry points that forward ETH to the Game contract. The ETH ultimately enters the protocol through the Game contract's payable functions (E1-E7). They are listed separately because they represent distinct external caller interaction paths.

---

## 2. Internal ETH Movements

Pool-to-pool transfers within the protocol that move ETH between accounting variables without external ETH transfers.

### 2.1 Prize Pool Lifecycle Movements

| # | Source Pool | Destination Pool | Trigger | Function | Direction |
|---|-----------|-----------------|---------|----------|-----------|
| I1 | nextPrizePool | futurePrizePool | Time-based future skim on last purchase day | `_applyTimeBasedFutureTake` (AdvanceModule) | next -> future |
| I2 | nextPrizePool + futurePrizePool | currentPrizePool | Level transition (pool consolidation) | `consolidatePrizePools` (JackpotModule) | next+future -> current |
| I3 | futurePrizePool | nextPrizePool | Jackpot phase entry (15% drawdown, normal levels) | `_drawDownFuturePrizePool` (AdvanceModule) | future -> next |
| I4 | futurePrizePool (snapshot) | levelPrizePool[lvl] (target) | Phase end on x00 levels | `_endPhase` (AdvanceModule) | Sets target only; no actual ETH move |
| I5 | currentPrizePool | claimableWinnings[winners] + claimablePool | Daily jackpot payout | `payDailyJackpot` -> `_processDailyEthChunk` (JackpotModule) | current -> claimable |
| I6 | currentPrizePool | claimableWinnings[winners] + claimablePool | Split jackpot completion | `payDailyJackpotCoinAndTickets` (JackpotModule) | current -> claimable |
| I7 | futurePrizePool | dailyCarryoverEthPool -> claimableWinnings | Carryover level payout (days 2-4) | `payDailyJackpot` Phase 1 (JackpotModule) | future -> claimable |
| I8 | futurePrizePool | ethDaySlice -> claimablePool (winners) | Early-burn jackpot (every 3rd purchase day) | `payDailyJackpot` (JackpotModule) | future -> claimable |
| I9 | futurePrizePool | nextPrizePool (ticket backing) | Early-bird lootbox jackpot (day 1) | `_runEarlyBirdLootboxJackpot` (JackpotModule) | future -> next |
| I10 | currentPrizePool | dailyLootboxBudget -> nextPrizePool | Fresh daily jackpot start (20% of daily slice) | `payDailyJackpot` (JackpotModule) | current -> next |
| I11 | futurePrizePool | reserveSlice -> carryoverLootboxBudget -> nextPrizePool | Carryover day reserve (1% future, 50% to lootbox budget) | `payDailyJackpot` (JackpotModule) | future -> next |

### 2.2 Jackpot Distribution Movements

| # | Source Pool | Destination Pool | Trigger | Function | Direction |
|---|-----------|-----------------|---------|----------|-----------|
| I12 | currentPrizePool | claimableWinnings[winners] (4-bucket trait-matched) | Daily ETH jackpot resolution | `_distributeJackpotEth` -> `_processOneBucket` (JackpotModule) | current -> claimable |
| I13 | currentPrizePool | claimableWinnings[winner] (75%) + whalePassClaims[winner] + futurePrizePool (25%) | Solo bucket >= 8.7 ETH (whale pass conversion) | `_processSoloBucketWinner` (JackpotModule) | current -> claimable+future |
| I14 | jackpot winnings | nextPrizePool (25%) or futurePrizePool (75%) + ticketQueue | Auto-rebuy conversion of jackpot winnings | `_processAutoRebuy` (JackpotModule) | claimable -> next/future |
| I15 | jackpot winnings | claimableWinnings[player] (take-profit portion) | Auto-rebuy with take-profit setting | `_processAutoRebuy` (JackpotModule) | stays in claimable |
| I16 | remaining (after terminal) | VAULT (50%) + DGNRS (50%) | Terminal jackpot underpay during game-over | `handleGameOverDrain` -> `_sendToVault` (GameOverModule) | game -> vault/dgnrs |

### 2.3 Endgame / BAF / Decimator Movements

| # | Source Pool | Destination Pool | Trigger | Function | Direction |
|---|-----------|-----------------|---------|----------|-----------|
| I17 | futurePrizePool (bafPool allocation) | claimableWinnings[winner] + claimablePool | BAF jackpot payout (level x0 transition) | `_runBafJackpot` -> `_addClaimableEth` (EndgameModule) | future -> claimable |
| I18 | futurePrizePool (bafPool allocation) | futurePrizePool (ticket claims, no pool move) | BAF lootbox small/medium (<=5 ETH) | `_runBafJackpot` -> `_awardJackpotTickets` (EndgameModule) | stays in future |
| I19 | futurePrizePool (bafPool allocation) | whalePassClaims[winner] + claimablePool (remainder) | BAF lootbox large (>5 ETH) | `_runBafJackpot` -> `_queueWhalePassClaimCore` (EndgameModule) | future -> claimable |
| I20 | futurePrizePool (decimatorPool allocation) | claimablePool (deferred per-player claims) | Decimator x00 / x5 jackpot | `runDecimatorJackpot` (DecimatorModule) | future -> claimable |
| I21 | claimablePool (pre-reserved decimator) | claimableWinnings[account] (ETH half) | Normal decimator claim (50% ETH) | `creditDecJackpotClaimBatch/Core` (DecimatorModule) | claimable -> claimable |
| I22 | claimablePool (pre-reserved decimator) | futurePrizePool + lootbox resolution (lootbox half) | Normal decimator claim (50% lootbox) | `_awardDecimatorLootbox` (DecimatorModule) | claimable -> future |
| I23 | claimablePool (pre-reserved decimator) | claimableWinnings[account] (100% ETH) | Game-over decimator claim | `creditDecJackpotClaimBatch` (DecimatorModule) | stays in claimable |

### 2.4 Degenerette Movements

| # | Source Pool | Destination Pool | Trigger | Function | Direction |
|---|-----------|-----------------|---------|----------|-----------|
| I24 | futurePrizePool | claimableWinnings[player] + claimablePool | ETH degenerette bet win (>=2 matches) | `_distributePayout` -> `_addClaimableEth` (DegeneretteModule) | future -> claimable |
| I25 | futurePrizePool (virtual) | Lootbox rewards via delegatecall | ETH degenerette bet resolution (75% lootbox) | `_distributePayout` -> `_resolveLootboxDirect` (DegeneretteModule) | future -> lootbox accounting |
| I26 | claimableWinnings[player] | futurePrizePool | ETH bet from claimable (claimable-funded bets) | `_collectBetFunds` (DegeneretteModule) | claimable -> future |

### 2.5 Yield / stETH Movements

| # | Source Pool | Destination Pool | Trigger | Function | Direction |
|---|-----------|-----------------|---------|----------|-----------|
| I27 | stETH appreciation | claimableWinnings[VAULT] (23%) | Yield surplus distribution | `_distributeYieldSurplus` (JackpotModule) | yield -> claimable |
| I28 | stETH appreciation | claimableWinnings[DGNRS] (23%) | Yield surplus distribution | `_distributeYieldSurplus` (JackpotModule) | yield -> claimable |
| I29 | stETH appreciation | futurePrizePool (46%) | Yield surplus distribution | `_distributeYieldSurplus` (JackpotModule) | yield -> future |
| I30 | stETH appreciation | (8% unextracted buffer) | Yield surplus distribution | `_distributeYieldSurplus` (JackpotModule) | yield -> buffer |

### 2.6 Game-Over Movements

| # | Source Pool | Destination Pool | Trigger | Function | Direction |
|---|-----------|-----------------|---------|----------|-----------|
| I31 | Available balance (totalFunds - claimablePool) | claimableWinnings[deityOwner] + claimablePool | Deity refund credit (level < 10) | `handleGameOverDrain` (GameOverModule) | available -> claimable |
| I32 | Available (10%) | DecimatorModule snapshot (deferred claims) | Game-over drain decimator allocation | `handleGameOverDrain` -> `runDecimatorJackpot` (GameOverModule) | available -> claimable |
| I33 | Remaining (90% + dec refund) | claimableWinnings via terminal jackpot | Game-over drain terminal jackpot | `handleGameOverDrain` -> `runTerminalJackpot` (GameOverModule) | remaining -> claimable |
| I34 | All excess (totalFunds - claimablePool) | VAULT (50%) + DGNRS (50%) via _sendToVault | 30-day final sweep | `handleFinalSweep` (GameOverModule) | excess -> vault/dgnrs |

### 2.7 Lootbox Accounting Movements

| # | Source Pool | Destination Pool | Trigger | Function | Direction |
|---|-----------|-----------------|---------|----------|-----------|
| I35 | lootboxEth[index][player] (accounting) | Cleared (zeroed) upon resolution | Player opens ETH lootbox | `openLootBox` (LootboxModule) | resolved |
| I36 | (virtual from purchase ETH) | lootboxEthTotal / lootboxRngPendingEth | Whale/lazy/deity lootbox recording | `_recordLootboxEntry` (WhaleModule) | tracking |

### 2.8 Vault Internal Movements

| # | Source Pool | Destination Pool | Trigger | Function | Direction |
|---|-----------|-----------------|---------|----------|-----------|
| I37 | Game claimable -> Vault ETH | Vault ETH balance | Vault auto-claims winnings when underfunded | `gamePurchaseDeityPassFromBoon` / `_burnEthFor` (Vault) | game -> vault |

### 2.9 DGNRS Internal Movements

| # | Source Pool | Destination Pool | Trigger | Function | Direction |
|---|-----------|-----------------|---------|----------|-----------|
| I38 | Game claimable -> DGNRS ETH | DGNRS contract balance | Burn when DGNRS balance < owed | `_burnFor` -> claimable materialization (Stonk) | game -> dgnrs |

---

## 3. ETH Exit Points

Every path through which ETH leaves the protocol to external addresses.

| # | Contract | Function | Recipient | Source Pool | Trigger |
|---|----------|----------|-----------|-------------|---------|
| X1 | DegenerusGame | `claimWinnings(address)` -> `_payoutWithStethFallback` | Player (msg.sender or approved) | claimableWinnings[player] -> claimablePool decrement | Player claims accrued winnings |
| X2 | DegenerusGame | `claimWinningsStethFirst()` -> `_payoutWithEthFallback` | VAULT or DGNRS contract | claimableWinnings[caller] -> claimablePool decrement | Vault/DGNRS claims yield winnings (stETH-preferred) |
| X3 | DegenerusGame | `adminSwapEthForStEth` | Admin (DGVE majority holder) | stETH balance (stETH exits, ETH enters net-neutral) | Admin ETH/stETH swap |
| X4 | DegenerusGame | `_autoStakeExcessEth` -> `steth.submit{value:}` | Lido stETH contract | address(this).balance - claimablePool | Phase transition auto-staking |
| X5 | DegenerusGame | `adminStakeEthForStEth` -> `steth.submit{value:}` | Lido stETH contract | ETH balance (above claimablePool reserve) | Admin-initiated ETH-to-stETH conversion |
| X6 | DegenerusGame (GameOverModule) | `_sendToVault` -> `payable(VAULT).call{value:}` | DegenerusVault | Game ETH balance (when stETH insufficient for vault share) | Game-over drain / final sweep |
| X7 | DegenerusGame (GameOverModule) | `_sendToVault` -> `payable(DGNRS).call{value:}` | DegenerusStonk | Game ETH balance (when stETH insufficient for DGNRS share) | Game-over drain / final sweep |
| X8 | DegenerusGame (GameOverModule) | `_sendToVault` -> `steth.transfer(VAULT)` | DegenerusVault | Game stETH balance | Game-over drain (stETH to Vault) |
| X9 | DegenerusGame (GameOverModule) | `_sendToVault` -> `steth.transfer(DGNRS)` / `steth.approve + dgnrs.depositSteth` | DegenerusStonk | Game stETH balance | Game-over drain (stETH to DGNRS) |
| X10 | DegenerusGame (MintModule) | `payable(VAULT).call{value: vaultShare}` | DegenerusVault | Lootbox presale vault share | Presale lootbox purchase (20% of lootbox ETH) |
| X11 | DegenerusVault | `_payEth(to, amount)` -> `to.call{value:}` | DGVE holder (player) | Vault ETH balance | DGVE burn-to-extract (ETH portion) |
| X12 | DegenerusVault | `_paySteth(to, amount)` -> `steth.transfer(to)` | DGVE holder (player) | Vault stETH balance | DGVE burn-to-extract (stETH fallback) |
| X13 | DegenerusVault | `gamePurchase{value}` / `gamePurchaseDeityPassFromBoon{value}` / `gameDegeneretteBetEth{value}` | DegenerusGame | Vault ETH balance | Vault owner gameplay actions |
| X14 | DegenerusStonk | `player.call{value: ethOut}` | DGNRS holder (player) | DGNRS ETH balance | DGNRS burn-to-extract (ETH portion) |
| X15 | DegenerusStonk | `steth.transfer(player, stethOut)` | DGNRS holder (player) | DGNRS stETH balance | DGNRS burn-to-extract (stETH fallback) |
| X16 | DegenerusStonk | `gamePurchase{value}` / `gameDegeneretteBetEth{value}` | DegenerusGame | DGNRS ETH balance (from msg.value) | DGNRS holder gameplay proxy |
| X17 | DegenerusAdmin | `gameAdmin.adminSwapEthForStEth{value: msg.value}` | DegenerusGame | Admin ETH (from msg.value) | Admin ETH-for-stETH swap relay |

**Note on ETH conversion exits:** X4 and X5 convert ETH to stETH via Lido. The ETH "leaves" the contract as native ETH but the protocol receives stETH in return, so total protocol value is preserved. These are tracked as exits because native ETH physically leaves the contract.

**Note on inter-contract exits:** X6, X7, X10, X13, X16, X17 transfer ETH between protocol contracts. They are external calls (crossing contract boundaries) but ETH stays within the protocol ecosystem. Marked as exits because they involve `call{value:}` patterns.

---

## 4. ETH Flow Diagrams

### 4.1 Mint-to-Jackpot Flow

```
External Caller
    |
    | msg.value
    v
DegenerusGame.purchase()
    |
    +--[ticket portion]-- recordMint()
    |   |
    |   +-- currentPrizePool  += currentShare (configurable BPS)
    |   +-- nextPrizePool     += nextShare
    |   +-- futurePrizePool   += futureShare
    |
    +--[lootbox portion]-- _purchaseFor()
        |
        +-- Normal:  futurePrizePool += 90%, nextPrizePool += 10%
        +-- Presale: futurePrizePool += 40%, nextPrizePool += 40%, VAULT += 20%

        ...time passes, level advances...

Last Purchase Day:
    nextPrizePool --[time-based skim]--> futurePrizePool
    nextPrizePool --[consolidation]---> currentPrizePool
    futurePrizePool --[partial]-------> currentPrizePool

Jackpot Phase (5 days):
    futurePrizePool --[15% drawdown]--> nextPrizePool
    |
    +-- Day 1-4: currentPrizePool * 6-14% --> daily jackpot budget
    +-- Day 5:   currentPrizePool * 100%  --> final jackpot budget
    |
    daily budget --> 4-bucket trait-matched distribution
        |
        +-- Multi-bucket winners --> claimableWinnings[winner]
        +-- Solo bucket (>=8.7 ETH) --> 75% claimable + 25% whale pass conversion
        +-- Auto-rebuy enabled --> tickets queued, ethSpent to next/futurePrizePool
        |
        claimablePool += aggregate liability delta

Player Claims:
    claimableWinnings[player] --> claimablePool -= payout
        |
        +-- ETH first (player.call{value:})
        +-- stETH fallback if ETH insufficient
```

### 4.2 Whale Pass Flow

```
External Caller
    |
    | msg.value
    v
purchaseWhaleBundle() / purchaseLazyPass() / purchaseDeityPass()
    |
    +-- Whale Bundle (2.4 ETH levels 0-3, 4 ETH levels x49/x99):
    |   Level 0: futurePrizePool += 70%, nextPrizePool += 30%
    |   Level >0: futurePrizePool += 95%, nextPrizePool += 5%
    |   + 100 tickets queued across 100 levels
    |   + lootbox entry recorded (virtual, no additional ETH)
    |
    +-- Lazy Pass (0.24 ETH flat levels 0-2, sum-of-10 levels 3+):
    |   futurePrizePool += 10%, nextPrizePool += 90%
    |   + 10 tickets queued across 10 levels
    |   + lootbox entry recorded
    |
    +-- Deity Pass (24 + T(n) ETH, T(n) = n*(n+1)/2):
        Level 0: futurePrizePool += 70%, nextPrizePool += 30%
        Level >0: futurePrizePool += 95%, nextPrizePool += 5%
        + permanent virtual trait tickets (2% representation)
        + lootbox entry recorded
        + deity boon access granted

All splits: futurePrizePool_delta + nextPrizePool_delta == msg.value
```

### 4.3 Game-Over Flow

```
Game Over Triggered (liveness timeout):
    |
    v
handleGameOverDrain()
    |
    +-- Reserve: claimablePool (existing liabilities)
    |
    +-- Deity Refunds (if level < 10):
    |   20 ETH/pass, FIFO, budget-capped
    |   credited to claimableWinnings[owner] (pull pattern)
    |   claimablePool += refund amounts
    |
    +-- available = totalFunds - claimablePool (recalculated)
    |
    +-- 10% to Decimator Jackpot
    |   |
    |   +-- decSpend --> claimablePool (winners credited)
    |   +-- decRefund --> returned to remaining
    |
    +-- remaining --> Terminal Jackpot (next-level ticketholders)
    |   |
    |   +-- termPaid --> claimablePool (via JackpotModule)
    |   +-- undistributed --> _sendToVault()
    |       |
    |       +-- 50% to Vault (stETH preferred, ETH fallback)
    |       +-- 50% to DGNRS (stETH preferred, ETH fallback)
    |
    +-- [30 days later]
        handleFinalSweep()
            |
            +-- excess = totalFunds - claimablePool
            +-- 50% to Vault, 50% to DGNRS
            +-- admin.shutdownVrf() --> LINK to Vault
```

### 4.4 Lootbox Flow

```
Lootbox Purchase (within ticket purchase):
    |
    lootBoxAmount (from msg.value or claimable)
    |
    +-- Normal: futurePrizePool += 90%, nextPrizePool += 10%
    +-- Presale: futurePrizePool += 40%, nextPrizePool += 40%, VAULT += 20%
    |
    lootboxEth[rngIndex][buyer] += amount  (tracking)
    lootboxRngPendingEth += amount         (RNG threshold tracking)

        ...VRF fulfillment...

Lootbox Resolution (openLootBox):
    |
    lootboxEth[index][player] --> zero (accounting cleared)
    |
    +-- EV multiplier applied (80%-135% based on activity score)
    |
    +-- Amount > 0.5 ETH: split into two independent rolls
    |
    Roll Outcomes (each roll):
        +-- 55% --> Future tickets (queued at target level)
        +-- 10% --> DGNRS tokens (from pool)
        +-- 10% --> WWXRP tokens (minted)
        +-- 25% --> BURNIE (creditFlip)
    |
    +-- 10% carve-out for boon chance (max 1 ETH budget)
        +-- Boons modify future ETH flows (discounts, boosts)
        +-- No immediate ETH transfer

Note: Lootbox resolution does NOT move ETH between pools.
The ETH was already split into prize pools at purchase time.
Lootbox tracking is purely accounting-level.
```

### 4.5 Yield Flow

```
ETH enters protocol (via purchases)
    |
    v
address(this).balance (Game contract)
    |
    +-- Phase transition: _autoStakeExcessEth()
    |   excess = address(this).balance - claimablePool
    |   |
    |   v
    |   steth.submit{value: excess}(address(0))  --> Lido
    |   Game now holds stETH instead of ETH
    |
    +-- Admin-initiated: adminStakeEthForStEth(amount)
        amount <= address(this).balance - claimablePool
        |
        v
        steth.submit{value: amount}(address(0))  --> Lido

stETH Appreciation (Lido rebasing):
    |
    totalBalance = ETH + stETH > obligations
    surplus = totalBalance - (current + next + claimable + future)
    |
    _distributeYieldSurplus():
        +-- 23% --> claimableWinnings[VAULT]  (DGVE holders)
        +-- 23% --> claimableWinnings[DGNRS]  (DGNRS holders)
        +-- 46% --> futurePrizePool           (players)
        +-- 8%  --> unextracted buffer        (safety margin)

VAULT/DGNRS Claim Yield:
    claimWinningsStethFirst()
        +-- stETH first (preferred for yield-bearing)
        +-- ETH fallback if stETH insufficient

DGVE Burn-to-Extract:
    Vault holds ETH + stETH
    |
    DGVE holder burns shares --> proportional payout
        +-- ETH preferred, stETH fallback
```

### 4.6 Affiliate Flow

```
Ticket Purchase (with affiliate code):
    |
    msg.value --> purchase() --> recordMint()
    |
    +-- freshEth = msg.value (DirectEth) or partial (Combined)
    |
    affiliate.payAffiliate(burnieValue, ..., isFreshEth, activityScore)
        |
        +-- NO ETH TRANSFERRED to affiliate
        +-- Affiliate reward is BURNIE (via coin.creditFlip)
        |
        +-- Direct affiliate: BURNIE credit
        +-- Upline 1 (20% of tapered amount): BURNIE credit
        +-- Upline 2 (4% of tapered amount): BURNIE credit
        |
        +-- Rakeback to buyer: coin.creditFlip(buyer, totalRakeback)

    Affiliate Payout Modes (BURNIE only):
        +-- Coinflip (0): coin.creditFlip (default)
        +-- Degenerette (1): pendingDegeneretteCredit[player] (stored)
        +-- SplitCoinflipCoin (2): coin.creditCoin (50% minted, 50% discarded)

    DGNRS Affiliate Claims:
        claimAffiliateDgnrs() --> DGNRS tokens from affiliate pool
        (No ETH movement)

Note: The affiliate system is entirely BURNIE/DGNRS-denominated.
No ETH enters or exits through DegenerusAffiliate.
Affiliate "ETH value" is a virtual calculation for BURNIE conversion only.
```

---

## 5. ETH Conservation Analysis

### Pool-by-Pool Analysis

| Pool | Entry Paths | Exit Paths | Conservation Check |
|------|------------|------------|-------------------|
| **nextPrizePool** | E1 (mint ticket next share), E2 (lootbox next share), E3 (whale next share), E4 (lazy 90%), E5 (deity next share), I3 (future drawdown 15%), I9 (early-bird backing), I10 (daily lootbox budget), I11 (carryover lootbox), I14 (auto-rebuy 25%) | I1 (future skim), I2 (consolidation to current) | CONSERVED: All increments come from documented entry paths. All decrements go to documented destination pools. At consolidation, 100% moves to currentPrizePool. |
| **futurePrizePool** | E1 (mint ticket future share), E2 (lootbox future share), E3 (whale future share), E4 (lazy 10%), E5 (deity future share), E6 (degenerette 100%), E8 (receive 100%), I1 (future skim from next), I14 (auto-rebuy 75%), I22 (decimator lootbox half), I29 (yield 46%) | I2 (consolidation partial), I3 (drawdown 15%), I7 (carryover 1%), I8 (early-burn 1%), I9 (early-bird 3%), I17 (BAF payout), I20 (decimator jackpot), I24 (degenerette payout), I25 (degenerette lootbox) | CONSERVED: All paths accounted for. The pool grows from purchases and yield, shrinks from jackpots and level transitions. |
| **currentPrizePool** | I2 (consolidation from next+future) | I5 (daily jackpot), I6 (split jackpot), I10 (daily lootbox budget), I12 (trait-matched distribution), I13 (solo bucket) | CONSERVED: Only filled at consolidation, only drained by daily jackpots. Day 5 takes 100%, ensuring complete drain per level. |
| **claimablePool** | I5-I8 (jackpot credits), I12-I13 (distribution credits), I17-I19 (BAF credits), I20-I23 (decimator credits), I24 (degenerette credits), I27-I28 (yield credits), I31-I33 (game-over credits) | X1 (player claims), X2 (vault/DGNRS claims), I26 (claimable-funded bets) | CONSERVED: Incremented when claimableWinnings[player] is credited, decremented when ETH is actually sent. The 1-wei sentinel ensures non-zero storage after claim. |
| **claimableWinnings[player]** | I5-I8, I12-I15, I17, I21, I23-I24, I27-I28, I31-I33 (all jackpot/payout credits) | X1 (claim), X2 (claim stETH-first), I26 (bet from claimable), I37-I38 (auto-claim for vault/dgnrs) | CONSERVED: Pull-pattern. Every credit is traceable to a pool debit. Every claim decrements both claimableWinnings and claimablePool. |
| **Vault ETH balance** | E9 (game deposit), E10 (donation), X6 (game-over ETH), I37 (auto-claim) | X11 (DGVE burn payout), X13 (gameplay forwarding) | CONSERVED: ETH enters from Game deposits and game-over. Exits via DGVE burns (proportional) and gameplay proxy. |
| **Vault stETH balance** | X8 (game-over stETH), I37 (stETH portion) | X12 (DGVE burn stETH payout) | CONSERVED: Lido rebasing increases balance passively. Burns pay proportional share. |
| **DGNRS ETH balance** | E16 (game deposit via receive), X7 (game-over ETH) | X14 (DGNRS burn payout), X16 (gameplay forwarding) | CONSERVED: Receives ETH from Game. Exits via token burns and gameplay proxy. |
| **DGNRS stETH balance** | X9 (game-over stETH via depositSteth) | X15 (DGNRS burn stETH payout) | CONSERVED: Receives stETH from Game. Exits proportionally via burns. |

### Conservation Invariants

1. **No ETH creation:** The only source of new ETH in the protocol is `msg.value` from external callers. No function mints or creates ETH internally.

2. **No ETH destruction:** ETH is never sent to `address(0)` or permanently locked. The only "conversion" is ETH -> stETH via Lido (X4, X5), which preserves value.

3. **claimablePool solvency:** `address(this).balance + steth.balanceOf(address(this)) >= claimablePool` is maintained at all times. The `adminStakeEthForStEth` function explicitly guards `amount <= ethBal - claimablePool`.

4. **Pool sum accounting:** At any point during active gameplay: `nextPrizePool + currentPrizePool + futurePrizePool + claimablePool <= address(this).balance + steth.balanceOf(address(this))`. The difference is the yield surplus.

5. **Entry = Exit principle:** Every wei that enters via `msg.value` eventually exits through one of: player claims (X1/X2), DGVE/DGNRS burns (X11/X14), game-over sweeps (X6-X9), or stETH conversion (X4/X5).

---

## 6. Completeness Verification

### 6.1 Cross-Reference: Audit ETH Mutation Paths vs Protocol Map

| Audit Report | ETH Paths Documented | All Captured? |
|-------------|---------------------|---------------|
| 50-01 AdvanceModule (13 paths) | Future skim, consolidation, drawdown, daily jackpots, auto-stake, game-over | YES -- mapped to I1-I3, I5-I11, I27-I30, X4 |
| 50-02 MintModule (ticket + lootbox + claimable + BURNIE flows) | Purchase splits, lootbox splits, claimable deductions | YES -- mapped to E1-E2, X10 |
| 50-03 JackpotModule Part 1 (pool consolidation, daily jackpot, early-burn, early-bird, yield, auto-rebuy) | All pool flows | YES -- mapped to I2, I5-I15, I27-I30 |
| 50-04 JackpotModule Part 2 (distribution, coin, tickets) | ETH distribution, chunked daily, BURNIE (non-ETH) | YES -- mapped to I12-I13 (ETH); BURNIE paths excluded as non-ETH |
| 51-01 EndgameModule (13 paths) | BAF payouts, decimator, whale pass, affiliate DGNRS | YES -- mapped to I17-I20; DGNRS paths excluded as non-ETH |
| 51-03 LootboxModule Part 2 (lootbox resolution) | Accounting clears, token rewards | YES -- mapped to I35; token rewards (BURNIE/DGNRS/WWXRP) excluded as non-ETH |
| 51-04 GameOverModule (11 paths) | Deity refunds, decimator, terminal jackpot, sweeps, VRF shutdown | YES -- mapped to I31-I34, X6-X9 |
| 52-01 WhaleModule (13 paths) | Whale/lazy/deity splits, lootbox recording, DGNRS rewards | YES -- mapped to E3-E5, I36; DGNRS paths excluded as non-ETH |
| 52-02 DegeneretteModule (7 paths) | Bet placement, payouts, lootbox conversion | YES -- mapped to E6, I24-I26 |
| 52-03 BoonModule (0 paths) | "Does not move ETH directly" | CONFIRMED -- no ETH paths |
| 52-04 DecimatorModule (15 paths) | Batch/single/self-claim, auto-rebuy, lootbox routing | YES -- mapped to I20-I23 |
| 53-01 Module Utils (3 paths) | _creditClaimable, _queueWhalePassClaimCore, _calcAutoRebuy | YES -- these are helper functions called by mapped paths |
| 54-01 BurnieCoin (0 paths) | "Does not handle ETH" | CONFIRMED -- no ETH paths |
| 54-03 Vault (14 paths) | Deposit, gameplay proxy, burn payouts, auto-claim | YES -- mapped to E9-E13, X11-X13, I37 |
| 54-04 Stonk (10 paths) | Deposit, gameplay proxy, burn payouts, claimable materialization | YES -- mapped to E14-E16, X14-X16, I38 |
| 55-02 Affiliate (0 paths) | "No direct ETH flows" -- BURNIE only | CONFIRMED -- no ETH paths |
| 56-01 Admin (2 paths) | swapGameEthForStEth, stakeGameEthToStEth relay | YES -- mapped to E17, X17 |
| 56-02 WWXRP (0 paths) | No ETH handling | CONFIRMED -- no ETH paths |

### 6.2 Source Code Grep Verification

**`payable` functions -- all captured:**
- DegenerusGame: purchase, purchaseWhaleBundle, purchaseLazyPass, purchaseDeityPass, placeFullTicketBets, adminSwapEthForStEth, receive -- ALL in E1-E8
- DegenerusVault: deposit, receive, gamePurchase, gamePurchaseDeityPassFromBoon, gameDegeneretteBetEth -- ALL in E9-E13
- DegenerusStonk: gamePurchase, gameDegeneretteBetEth, receive -- ALL in E14-E16
- DegenerusAdmin: swapGameEthForStEth -- in E17
- Module payable functions (WhaleModule, MintModule, DegeneretteModule) -- called via delegatecall from Game, so msg.value is the Game's received ETH. Covered by E1-E6.

**`.call{value:}` patterns -- all captured:**
- DegenerusGame:1972 (`_payoutWithStethFallback` ETH send) -- X1, X2
- DegenerusGame:1989 (`_payoutWithStethFallback` retry) -- X1, X2
- DegenerusGame:2010 (`_payoutWithEthFallback` ETH send) -- X2
- DegenerusVault:1037 (`_payEth`) -- X11
- DegenerusStonk:818 (`player.call{value: ethOut}`) -- X14
- GameOverModule:197 (`payable(VAULT).call{value:}`) -- X6
- GameOverModule:214 (`payable(DGNRS).call{value:}`) -- X7
- MintModule:737 (`payable(VAULT).call{value: vaultShare}`) -- X10

**`steth.submit{value:}` patterns -- all captured:**
- DegenerusGame:1837 (`adminStakeEthForStEth`) -- X5
- AdvanceModule:1015 (`_autoStakeExcessEth`) -- X4

**`steth.transfer()` patterns -- all captured:**
- DegenerusGame:1816 (`adminSwapEthForStEth` stETH to admin) -- X3
- DegenerusGame:1957 (`_transferSteth` to recipient) -- X1, X2
- DegenerusVault:1045 (`_paySteth` to DGVE burner) -- X12
- DegenerusStonk:822 (`steth.transfer(player)` to DGNRS burner) -- X15
- GameOverModule:188,192 (`steth.transfer(VAULT/DGNRS)`) -- X8, X9

**`receive()` / `fallback()` functions -- all captured:**
- DegenerusGame:2806 -- E8
- DegenerusStonk:648 -- E16
- DegenerusVault:460 -- E10
- No `fallback()` functions exist in any contract.

### 6.3 Discrepancies

**None found.** All ETH paths identified in Phase 50-56 audit reports are reflected in this protocol-wide map. All source code ETH-handling patterns (`payable`, `msg.value`, `.call{value:}`, `.transfer()`, `steth.submit{value:}`) are accounted for.

---

## 7. Summary Statistics

| Metric | Count |
|--------|-------|
| ETH entry points | 17 (E1-E17) |
| Internal pool movements | 38 (I1-I38) |
| ETH exit points | 17 (X1-X17) |
| Total unique ETH paths | 72 |
| Standalone contracts handling ETH | 4 (DegenerusGame, DegenerusVault, DegenerusStonk, DegenerusAdmin) |
| Delegatecall modules handling ETH | 10 (AdvanceModule, MintModule, JackpotModule, EndgameModule, LootboxModule, WhaleModule, DegeneretteModule, DecimatorModule, GameOverModule, PayoutUtils) |
| Contracts NOT handling ETH | 6 (BurnieCoin, BurnieCoinflip, DegenerusAffiliate, DegenerusQuests, DegenerusDeityPass, WrappedWrappedXRP) |
| Non-ETH modules (via delegatecall) | 1 (BoonModule -- modifies boon state only, no ETH movement) |
| Contracts with `receive()` | 3 (DegenerusGame, DegenerusVault, DegenerusStonk) |
| Contracts with `steth.submit{value:}` | 2 (DegenerusGame via adminStakeEthForStEth, AdvanceModule via _autoStakeExcessEth) |
| Conservation violations | 0 |
| Undocumented ETH flows | 0 |

### Key Architectural Observations

1. **DegenerusGame is the ETH nexus.** All external ETH enters through the Game contract (directly or via proxy). Prize pool accounting lives in Game storage. The Vault and DGNRS receive ETH only from Game deposits or game-over distributions.

2. **Pull-pattern withdrawal.** All player ETH exits use the pull pattern: credits accumulate in `claimableWinnings[player]`, then `claimWinnings()` sends ETH. No push payments to players during jackpot distribution.

3. **stETH as yield layer.** Excess ETH is auto-staked to Lido stETH at phase transitions. Yield surplus is distributed 23/23/46/8 (Vault/DGNRS/futurePrize/buffer). The protocol holds a mix of ETH + stETH but accounts for obligations in ETH-equivalent terms.

4. **Game-over is terminal.** Once triggered, no new ETH can enter (receive() reverts). All remaining value is drained to claimable credits, then swept to Vault/DGNRS after 30 days.

5. **Module delegatecall pattern.** Modules (AdvanceModule, JackpotModule, etc.) modify Game storage via delegatecall. ETH transfers from modules (MintModule vault share, GameOverModule sweeps) use the Game contract's ETH balance since msg.sender and address(this) are the Game contract.
