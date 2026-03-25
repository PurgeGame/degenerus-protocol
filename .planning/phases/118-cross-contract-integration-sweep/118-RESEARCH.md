# Phase 118: Cross-Contract Integration Sweep - Research

**Date:** 2026-03-25
**Source:** All 15 unit findings reports + contract source analysis

---

## 1. Aggregate Unit Findings Summary

### By Severity Across All 15 Units

| Severity | Count | Units |
|----------|-------|-------|
| CRITICAL | 0 | -- |
| HIGH | 0 | -- |
| MEDIUM | 1 | Unit 7: decBucketOffsetPacked collision between regular/terminal decimator |
| LOW | 2 | Unit 8: strict inequality on claimable pull; Unit 13: missing LINK recovery path |
| INFO | 29 | Units 1-15 (distributed) |
| **Total** | **32** | |

### By Category

| Finding Category | Count | Examples |
|-----------------|-------|---------|
| BAF cache-overwrite (stale local) | 0 confirmed | All units: every BAF check returned SAFE |
| Access control gap | 0 | All onlyGame/onlyCoin/onlyOwner guards verified |
| Token supply invariant | 0 | BURNIE, DGNRS, sDGNRS, WWXRP all verified |
| Storage collision | 1 (MEDIUM) | decBucketOffsetPacked shared by regular + terminal decimator |
| CEI ordering | 2 (INFO) | Unit 1 F-06 (_setAfKingMode), Unit 12 INFO-01 (WWXRP donate) |
| Stale cached-local (non-BAF) | 2 (INFO) | Unit 2 F-01 (advanceBounty), Unit 2 F-04 (lastLootboxRngWord) |
| Gas/code quality | ~15 (INFO) | Double reads, dust drops, comment discrepancies |
| Missing recovery path | 1 (LOW) | Unit 13: LINK stuck in Admin after failed transfer |
| UX friction | 1 (LOW) | Unit 8: strict inequality prevents exact-balance bet |
| Test bug | 1 (INFO) | Unit 2 F-06: ticket queue test assertion bug |
| By-design behavior | ~8 (INFO) | Diminishing returns, transient freeze, deity overwrite |

---

## 2. Cross-Contract Call Map (From Unit Reports)

### Game (via delegatecall modules) -> Standalone Contracts

| Source Module | Target Contract | Functions Called | Unit Verified |
|--------------|----------------|-----------------|---------------|
| AdvanceModule | BurnieCoin | creditFlip (bounty) | Unit 2 |
| AdvanceModule | Coinflip | (via VRF callback routing) | Unit 2 |
| JackpotModule | BurnieCoin | creditFlip (daily jackpot) | Unit 3 |
| JackpotModule | sDGNRS | deposit, transferFromPool | Unit 3 |
| EndgameModule | sDGNRS | transferBetweenPools | Unit 4 |
| EndgameModule | Jackpots | runBafJackpot | Unit 4 |
| EndgameModule | DecimatorModule | runTerminalDecimatorJackpot (delegatecall) | Unit 4 |
| GameOverModule | sDGNRS | burnRemainingPools | Unit 4 |
| GameOverModule | Vault | ETH send (call{value}) | Unit 4 |
| GameOverModule | sDGNRS | ETH send (call{value}) | Unit 4 |
| MintModule | BurnieCoin | creditFlip (streak bonus) | Unit 5 |
| MintModule | Affiliate | payAffiliate | Unit 5 |
| MintModule | Vault | ETH send (call{value}) | Unit 5 |
| WhaleModule | BurnieCoin | creditFlip | Unit 6 |
| WhaleModule | DGNRS | poolBalance (view) | Unit 6 |
| WhaleModule | sDGNRS | deposit, transferFromPool | Unit 6 |
| WhaleModule | DeityPass | mintPacked_ (ERC721) | Unit 6 |
| DecimatorModule | BurnieCoin | creditFlip | Unit 7 |
| DegeneretteModule | BurnieCoin | creditFlip, mintForGame | Unit 8 |
| DegeneretteModule | WWXRP | mintPrize | Unit 8 |
| DegeneretteModule | LootboxModule | resolveLootboxDirect (delegatecall) | Unit 8 |
| LootboxModule | BoonModule | checkAndClearExpiredBoon, consumeActivityBoon (delegatecall) | Unit 9 |
| LootboxModule | WWXRP | mintPrize | Unit 9 |
| LootboxModule | BurnieCoin | mintForGame | Unit 9 |
| Game (router) | BurnieCoin | creditFlip (via _setAfKingMode) | Unit 1 |
| Game (router) | Coinflip | setCoinflipAutoRebuy, settleFlipModeChange | Unit 1 |
| Game (router) | Admin | shutdownVrf | Unit 1 |

### Standalone -> Standalone Call Chains

| Source | Target | Function | Unit Verified |
|--------|--------|----------|---------------|
| BurnieCoin | Coinflip | auto-claim callback (transfer triggers claim) | Unit 10 |
| BurnieCoin | Quests | handleMint, handleFlip, handleDecimator, handleAffiliate, handleLootBox, handleDegenerette | Unit 10 |
| BurnieCoin | Jackpots | recordBafFlip | Unit 10 |
| sDGNRS | Game | claimWinnings (ETH pull during burn) | Unit 11 |
| sDGNRS | DGNRS | burnForSdgnrs (cross-contract burn) | Unit 11 |
| DGNRS | sDGNRS | wrapperTransferTo (unwrap), burnForSdgnrs | Unit 11 |
| DGNRS | BurnieCoin | transfer (burn payout) | Unit 11 |
| Vault | BurnieCoin | vaultMintTo, vaultEscrow, transfer | Unit 12 |
| Vault | Coinflip | claimCoinflips (BURNIE waterfall) | Unit 12 |
| Vault | Game | (proxy functions forwarding to Game) | Unit 12 |
| Admin | VRF Coordinator | createSubscription, cancelSubscription, requestRandomWords | Unit 13 |
| Admin | LINK Token | transfer, transferAndCall | Unit 13 |
| Affiliate | BurnieCoin | creditFlip, affiliateQuestReward | Unit 14 |

### Callback / Re-entry Chains

| Chain | Depth | Safety Status |
|-------|-------|---------------|
| BurnieCoin.transfer -> Coinflip.claimForAddress -> BurnieCoin.mintForCoinflip -> BurnieCoin._transfer (resumes) | 3 | SAFE (Unit 10: fresh storage reads) |
| Game.claimWinnings -> sends ETH -> sDGNRS.receive() (no re-entry back to Game) | 2 | SAFE (Unit 11) |
| Vault.burnEth -> sends ETH -> recipient (no callback to Vault) | 2 | SAFE (Unit 12: CEI followed) |
| LootboxModule -> BoonModule (nested delegatecall) | 2 | SAFE (Unit 9: no cached locals) |
| DegeneretteModule -> LootboxModule (nested delegatecall) | 2 | SAFE (Unit 8: pool committed before call) |

---

## 3. Shared Storage Variables (Written by Multiple Modules)

All 10 modules share DegenerusGameStorage (102 variables, slots 0-78). Variables written by multiple modules are the highest-risk targets for cross-module cache conflicts.

### Critical Shared Variables

| Variable | Slot | Written By | Read By | Risk |
|----------|------|-----------|---------|------|
| `prizePoolsPacked` | 4 | JackpotModule, MintModule, DegeneretteModule, DecimatorModule | All modules (via getters) | HIGH: Multiple writers |
| `claimablePool` | 5 | JackpotModule, EndgameModule, DegeneretteModule | Game (claimWinnings) | HIGH: Multiple writers |
| `claimableWinnings[addr]` | mapping | JackpotModule, EndgameModule, GameOverModule, DegeneretteModule, Game | Game (claimWinnings) | HIGH: Multiple writers |
| `mintPacked_[addr]` | mapping | MintModule, WhaleModule, LootboxModule (via BoonModule delegatecall) | MintModule, WhaleModule, LootboxModule | MEDIUM: Multiple writers |
| `boonPacked[addr]` | 2 slots | BoonModule (via LootboxModule delegatecall) | LootboxModule, DegeneretteModule | MEDIUM: Nested delegatecall |
| `jackpotPhaseFlag` | slot 0 | AdvanceModule | All modules (phase checks) | LOW: Single writer |
| `currentDay` | slot 0 | AdvanceModule | All modules (day checks) | LOW: Single writer |
| `rngLockedFlag` | slot 0 | AdvanceModule | Multiple modules | LOW: Single writer |
| `prizePoolFrozen` | slot 0 | AdvanceModule | DegeneretteModule, JackpotModule | LOW: Single writer |
| `purchaseLevel` | slot 0 | AdvanceModule | All purchase modules | LOW: Single writer |
| `ticketWriteSlot` | slot 1 | AdvanceModule | MintModule | LOW: Single writer |
| `decBucketOffsetPacked[lvl]` | mapping | DecimatorModule, GameOverModule (via DecimatorModule) | DecimatorModule | **MEDIUM: KNOWN COLLISION (Unit 7 MEDIUM finding)** |

### Safety Analysis of Multi-Writer Variables

**prizePoolsPacked:** Written via `_setFuturePrizePool`, `_setNextPrizePool` helpers which always use fresh `_get*` reads. No module caches the packed value and writes it back stale. Verified SAFE in Units 2, 3, 5, 7, 8.

**claimablePool:** Written via direct storage access. Each write is additive (+=) or freshly computed. No stale-cache pattern found in any unit.

**claimableWinnings[addr]:** Written via `_addClaimableEth` helper which returns `claimableDelta`. All callers use the return value for subsequent accounting. The rebuyDelta reconciliation in EndgameModule (Unit 4) is the critical pattern -- PROVEN CORRECT.

**mintPacked_[addr]:** Written by MintModule (purchase), WhaleModule (lazy/deity pass), and BoonModule (boon consumption via delegatecall). Each module writes to non-overlapping bit fields within the packed struct. No cross-module field collision detected.

**boonPacked[addr]:** Only written by BoonModule (delegatecalled via LootboxModule or DegeneretteModule). Single writer, but nested delegatecall pattern verified SAFE in Unit 9.

---

## 4. ETH Flow Entry Points

| Entry Point | Contract | Function | Unit |
|-------------|----------|----------|------|
| Ticket purchase (ETH) | Game (via MintModule) | `purchaseFor`, `_purchaseForDirectEth` | Unit 5 |
| Ticket purchase (claimable) | Game (via MintModule) | `purchaseFor`, `_purchaseForFromClaimable` | Unit 5 |
| Whale bundle | Game (via WhaleModule) | `purchaseWhaleBundle` | Unit 6 |
| Lazy pass | Game (via WhaleModule) | `purchaseLazyPass` | Unit 6 |
| Deity pass | Game (via WhaleModule) | `purchaseDeityPass` | Unit 6 |
| Degenerette bet (ETH) | Game (via DegeneretteModule) | `placeFullTicketBets` | Unit 8 |
| VRF bounty | Game (via AdvanceModule) | `advanceGame` (advance bounty, no ETH in) | Unit 2 |
| Game receive() | Game | `receive()` (direct ETH send) | Unit 1 |
| Vault deposit | Vault | `deposit()` | Unit 12 |
| sDGNRS receive() | sDGNRS | `receive()` (from Game claimWinnings) | Unit 11 |
| DGNRS receive() | DGNRS | `receive()` (from sDGNRS burn) | Unit 11 |
| WWXRP donate | WWXRP | `donate()` (wXRP, not ETH) | Unit 12 |
| Admin LINK | Admin | `onTokenTransfer()` (LINK, not ETH) | Unit 13 |

## 5. ETH Flow Exit Points

| Exit Point | Contract | Function | Destination | Unit |
|------------|----------|----------|-------------|------|
| Claim winnings | Game | `claimWinnings` | Player | Unit 1 |
| Claim winnings (stETH first) | Game | `claimWinningsStethFirst` | Player | Unit 1 |
| Vault share burn (ETH) | Vault | `burnEth` | Shareholder | Unit 12 |
| Vault share burn (stETH) | Vault | `burnEth` | Shareholder (stETH) | Unit 12 |
| sDGNRS claim redemption | sDGNRS | `claimRedemption` | Player | Unit 11 |
| sDGNRS deterministic burn | sDGNRS | `_deterministicBurnFrom` -> claimWinnings | Player | Unit 11 |
| DGNRS burn | DGNRS | `burn` -> sDGNRS burn | Player | Unit 11 |
| Vault to player (BURNIE burn) | Vault | `burnCoin` | Player (BURNIE) | Unit 12 |
| Game-over drain to Vault | GameOverModule | `handleGameOverDrain` | Vault | Unit 4 |
| Game-over drain to sDGNRS | GameOverModule | `handleGameOverDrain` | sDGNRS | Unit 4 |
| MintModule vault share | MintModule | `_purchaseFor` | Vault | Unit 5 |
| Admin LINK transfer | Admin | `shutdownVrf` | Vault (LINK) | Unit 13 |

---

## 6. Cross-Unit Integration Concerns Identified by Individual Units

### From Unit 10 (BURNIE Token + Coinflip):
> "Phase 118 (Integration): Cross-contract state coherence between BurnieCoin and BurnieCoinflip should be verified end-to-end, particularly the auto-claim callback chain under concurrent transaction scenarios."

### From Unit 9 (Lootbox + Boons):
> Nested delegatecall state coherence (LootboxModule -> BoonModule) verified SAFE within the unit. Integration phase should verify this holds across all possible entry paths.

### From Unit 7 (Decimator System):
> decBucketOffsetPacked collision is a MEDIUM finding. The integration phase should verify the exact conditions under which this triggers via the EndgameModule -> GameOverModule call chain.

### From Unit 4 (Endgame + Game Over):
> rebuyDelta reconciliation mechanism is the fix for the original BAF bug. Integration should verify no other ancestor function bypasses this mechanism.

### From Unit 3 (Jackpot Distribution):
> F-01 correction: VAULT CAN enable auto-rebuy via gameSetAutoRebuy. Integration should verify this does not create a new BAF-class interaction.

---

## 7. Protocol-Wide State Machine

### Key State Variables (packed in slot 0)

| Variable | Type | Written By | State Machine Role |
|----------|------|-----------|-------------------|
| `currentDay` | uint8 | AdvanceModule | Day counter (0-255) |
| `purchaseLevel` | uint24 | AdvanceModule | Current game level |
| `jackpotPhaseFlag` | uint8 | AdvanceModule | FSM: NORMAL=0, JACKPOT=1 |
| `rngLockedFlag` | bool | AdvanceModule | VRF request in flight |
| `prizePoolFrozen` | bool | AdvanceModule | Jackpot math in progress |
| `gameOverFlag` | bool | AdvanceModule/GameOverModule | Terminal state |
| `ethPhaseFlag` | uint8 | AdvanceModule | ETH pool phase (0/1/2) |
| `ticketWriteSlot` | uint8 | AdvanceModule | Double-buffer selector (0/1) |

### State Transitions

1. `advanceGame()` is the ONLY function that advances the FSM (day/level/phase transitions)
2. All other modules read state, they do not transition it
3. `prizePoolFrozen` is set and cleared within a single `advanceGame()` execution -- never observed as true between transactions (verified Unit 8 F-03)
4. `rngLockedFlag` is set when VRF request is made, cleared on fulfillment
5. `gameOverFlag` is terminal -- once set, most purchase functions revert

### Potential Stuck States

| Concern | Analysis |
|---------|----------|
| VRF never fulfilled | 120-day timeout triggers game-over via `_backfillGapDays`. Not permanently stuck. |
| rngLocked stuck | Cleared by `rawFulfillRandomWords` or by timeout in `advanceGame`. Not permanently stuck. |
| prizePoolFrozen stuck | Set and cleared within same `advanceGame` call. Cannot be stuck. |
| jackpotPhaseFlag stuck | Cleared when rngGate processes final jackpot stage. VRF timeout prevents permanent stuck. |

---

## 8. Token Supply Authority Chains

### BURNIE (BurnieCoin)

| Operation | Authorized Callers | Guard |
|-----------|-------------------|-------|
| mintForGame | GAME only | `msg.sender == GAME` |
| mintForCoinflip | COINFLIP only | `msg.sender == coinflipContract` |
| creditFlip | GAME only | (same as mintForGame internally) |
| vaultMintTo | VAULT only | `msg.sender == VAULT` |
| burnForCoinflip | COINFLIP only | `msg.sender == coinflipContract` |
| burnForGame | GAME only | `msg.sender == GAME` |
| burn (self) | Any holder | Burns own tokens |

All mint/burn authorities use compile-time `ContractAddresses.*` constants (immutable at deploy). No admin override.

### DGNRS (DegenerusStonk)

| Operation | Authorized Callers | Guard |
|-----------|-------------------|-------|
| constructor mint | CREATOR (one-time) | Constructor only |
| burnForSdgnrs | sDGNRS only | `msg.sender == SDGNRS` |
| burn | Any holder (after gameOver) | `gameOver()` check |
| unwrapTo | CREATOR only | `msg.sender == CREATOR` |

No runtime mint function. All DGNRS created at construction. Supply can only decrease.

### sDGNRS (StakedDegenerusStonk)

| Operation | Authorized Callers | Guard |
|-----------|-------------------|-------|
| gameDeposit | GAME only | `onlyGame` |
| transferFromPool / transferBetweenPools | GAME only | `onlyGame` |
| burnRemainingPools | GAME only | `onlyGame` |
| wrapperTransferTo | DGNRS only | `msg.sender == DGNRS` |
| _submitGamblingClaimFrom | Any holder (via submitGamblingClaim) | Caller must hold sDGNRS |
| _deterministicBurnFrom | Any holder (via burn) | Caller must hold sDGNRS |

Pool operations: GAME-only. Individual burns: self-only. No arbitrary mint to external addresses.

### WWXRP (WrappedWrappedXRP)

| Operation | Authorized Callers | Guard |
|-----------|-------------------|-------|
| mintPrize | GAME, COIN, COINFLIP, VAULT | `onlyMinter` (4 addresses) |
| wrap | Any holder of wXRP | Permissionless, 1:1 backed |
| unwrap | Any holder of WWXRP | First-come-first-served against wXRPReserves |
| donate | Any holder of wXRP | Permissionless |
| burn (self) | Any holder | Burns own tokens |

Intentionally undercollateralized (mintPrize creates unbacked WWXRP). Documented in KNOWN-ISSUES.md as design decision.

---

## 9. Priority Investigation Targets for Integration Analysis

### P1: decBucketOffsetPacked Collision (Unit 7 MEDIUM)
The only MEDIUM finding across all 15 units. Need to trace the exact call chain: EndgameModule.runRewardJackpots -> DecimatorModule.runDecimatorJackpot writes `decBucketOffsetPacked[lvl]`, then if game-over triggers at same level, GameOverModule.handleGameOverDrain -> DecimatorModule.runTerminalDecimatorJackpot overwrites same slot.

### P2: ETH Conservation Proof
Verify total ETH in = total ETH distributed + total ETH held across all contracts. Critical for protocol solvency.

### P3: Auto-Rebuy BAF Pattern (Cross-Module)
Unit 3 F-01 correction: VAULT CAN enable auto-rebuy. The yield surplus path (consolidatePrizePools -> _distributeYieldSurplus -> _addClaimableEth -> _processAutoRebuy) could modify futurePrizePool. Verify the snapshot staleness is truly bounded by the 8% buffer.

### P4: Cross-Contract Reentrancy via ETH Sends
Every `.call{value}` is a potential re-entry point. Verify CEI ordering at all ETH send sites.

### P5: State Machine Completeness
Can all state transitions reach a terminal state? Can any configuration prevent advanceGame() from eventually completing?

---

*Research completed: 2026-03-25*
*Input: 15 unit findings reports, contract source analysis*
