# Phase 112: BURNIE Token + Coinflip - Research

**Compiled:** 2026-03-25
**Contracts:**
- `contracts/BurnieCoin.sol` (~1,075 lines, 30 functions)
- `contracts/BurnieCoinflip.sol` (~1,129 lines, 28 functions)
- **Total: ~2,204 lines, 58 functions**

---

## 1. Complete Function Inventory

### 1.1 BurnieCoin.sol

#### Category B: External State-Changing (20 functions)

| # | Function | Lines | Access Control | Risk Tier | Subsystem |
|---|----------|-------|---------------|-----------|-----------|
| B1 | `approve(address, uint256)` | L394-401 | public | Tier 3 | ERC20 |
| B2 | `transfer(address, uint256)` | L408-412 | external | Tier 1 | ERC20 + AUTO-CLAIM |
| B3 | `transferFrom(address, address, uint256)` | L422-441 | external | Tier 1 | ERC20 + AUTO-CLAIM |
| B4 | `burnForCoinflip(address, uint256)` | L528-531 | coinflipContract only | Tier 2 | COINFLIP-GATE |
| B5 | `mintForCoinflip(address, uint256)` | L537-540 | coinflipContract only | Tier 2 | COINFLIP-GATE |
| B6 | `mintForGame(address, uint256)` | L546-550 | GAME only | Tier 3 | GAME-GATE |
| B7 | `creditCoin(address, uint256)` | L556-559 | onlyFlipCreditors | Tier 3 | CREDIT |
| B8 | `creditFlip(address, uint256)` | L566-568 | onlyFlipCreditors | Tier 2 | CREDIT-FORWARD |
| B9 | `creditFlipBatch(address[3], uint256[3])` | L574-576 | onlyFlipCreditors | Tier 2 | CREDIT-FORWARD |
| B10 | `creditLinkReward(address, uint256)` | L584-588 | onlyAdmin | Tier 3 | ADMIN-CREDIT |
| B11 | `vaultEscrow(uint256)` | L688-699 | GAME or VAULT | Tier 2 | VAULT-ESCROW |
| B12 | `vaultMintTo(address, uint256)` | L705-717 | onlyVault | Tier 1 | VAULT-MINT |
| B13 | `affiliateQuestReward(address, uint256)` | L724-745 | AFFILIATE only | Tier 2 | QUEST-HUB |
| B14 | `rollDailyQuest(uint48, uint256)` | L759-774 | onlyDegenerusGameContract | Tier 2 | QUEST-HUB |
| B15 | `notifyQuestMint(address, uint32, bool)` | L782-808 | GAME only | Tier 2 | QUEST-HUB |
| B16 | `notifyQuestLootBox(address, uint256)` | L814-834 | GAME only | Tier 2 | QUEST-HUB |
| B17 | `notifyQuestDegenerette(address, uint256, bool)` | L841-861 | GAME only | Tier 2 | QUEST-HUB |
| B18 | `burnCoin(address, uint256)` | L869-875 | onlyTrustedContracts | Tier 1 | BURN + AUTO-CONSUME |
| B19 | `decimatorBurn(address, uint256)` | L890-966 | public (operator check) | Tier 1 | DECIMATOR |
| B20 | `terminalDecimatorBurn(address, uint256)` | L981-1007 | public (operator check) | Tier 2 | DEATH-BET |

**Risk Tier Notes:**
- **Tier 1** (B2, B3, B12, B18, B19): Token flows with auto-claim callbacks, vault mint from allowance, complex burn paths. Highest state coherence risk.
- **Tier 2** (B4, B5, B8, B9, B11, B13, B14, B15, B16, B17, B20): Permission gates, quest notifications, vault escrow. Moderate risk -- access control must be verified.
- **Tier 3** (B1, B6, B7, B10): Simple approve, single-gate mints, admin credit. Low risk.

#### Category C: Internal/Private State-Changing (5 functions)

| # | Function | Lines | Called By | Key Storage Writes | Flags |
|---|----------|-------|-----------|-------------------|-------|
| C1 | `_transfer(address, address, uint256)` | L453-473 | B2, B3 | balanceOf[from], balanceOf[to], _supply.totalSupply, _supply.vaultAllowance | [MULTI-PARENT] |
| C2 | `_mint(address, uint256)` | L479-492 | B4(rev), B5, B6, B7, B12(inline), C4 | balanceOf[to], _supply.totalSupply, _supply.vaultAllowance | [MULTI-PARENT] |
| C3 | `_burn(address, uint256)` | L499-515 | B4, B18, B19, B20, C5 | balanceOf[from], _supply.totalSupply, _supply.vaultAllowance | [MULTI-PARENT] |
| C4 | `_claimCoinflipShortfall(address, uint256)` | L590-601 | B2, B3 | (via external call: BurnieCoinflip -> mintForCoinflip -> C2) | [MULTI-PARENT] |
| C5 | `_consumeCoinflipShortfall(address, uint256)` | L603-614 | B18, B19, B20 | (via external call: BurnieCoinflip.consumeCoinflipsForBurn -- no callback to BurnieCoin) | [MULTI-PARENT] |

#### Category D: View/Pure (12 functions)

| # | Function | Lines | Description |
|---|----------|-------|-------------|
| D1 | `claimableCoin()` | L284-286 | View: proxy to BurnieCoinflip.previewClaimCoinflips |
| D2 | `balanceOfWithClaimable(address)` | L295-303 | View: balance + claimable + vault allowance |
| D3 | `previewClaimCoinflips(address)` | L309-311 | View: proxy to BurnieCoinflip.previewClaimCoinflips |
| D4 | `coinflipAutoRebuyInfo(address)` | L318-322 | View: proxy to BurnieCoinflip.coinflipAutoRebuyInfo |
| D5 | `totalSupply()` | L325-327 | View: _supply.totalSupply |
| D6 | `supplyIncUncirculated()` | L332-334 | View: totalSupply + vaultAllowance |
| D7 | `vaultMintAllowance()` | L339-341 | View: _supply.vaultAllowance |
| D8 | `coinflipAmount(address)` | L1018-1020 | View: proxy to BurnieCoinflip.coinflipAmount |
| D9 | `_adjustDecimatorBucket(uint256, uint8)` | L1028-1044 | Pure: bucket calculation |
| D10 | `_decimatorBurnMultiplier(uint256)` | L1047-1050 | Pure: multiplier calculation |
| D11 | `_questApplyReward(...)` | L1059-1075 | Private: event emission + reward passthrough |
| D12 | `_toUint128(uint256)` | L443-446 | Pure: safe downcast |

### 1.2 BurnieCoinflip.sol

#### Category B: External State-Changing (11 functions)

| # | Function | Lines | Access Control | Risk Tier | Subsystem |
|---|----------|-------|---------------|-----------|-----------|
| B21 | `settleFlipModeChange(address)` | L215-222 | onlyDegenerusGameContract | Tier 2 | SETTLEMENT |
| B22 | `depositCoinflip(address, uint256)` | L225-239 | public (operator check) | Tier 1 | DEPOSIT |
| B23 | `claimCoinflips(address, uint256)` | L326-329 | public (operator check) | Tier 1 | CLAIM |
| B24 | `claimCoinflipsFromBurnie(address, uint256)` | L335-339 | onlyBurnieCoin | Tier 1 | CLAIM-CALLBACK |
| B25 | `claimCoinflipsForRedemption(address, uint256)` | L345-351 | sDGNRS only | Tier 2 | CLAIM-REDEMPTION |
| B26 | `consumeCoinflipsForBurn(address, uint256)` | L365-370 | onlyBurnieCoin | Tier 2 | CONSUME |
| B27 | `setCoinflipAutoRebuy(address, bool, uint256)` | L674-686 | public/GAME | Tier 1 | AUTO-REBUY |
| B28 | `setCoinflipAutoRebuyTakeProfit(address, uint256)` | L689-693 | public (operator check) | Tier 2 | AUTO-REBUY |
| B29 | `processCoinflipPayouts(bool, uint256, uint48)` | L778-862 | onlyDegenerusGameContract | Tier 1 | DAY-RESOLUTION |
| B30 | `creditFlip(address, uint256)` | L869-875 | onlyFlipCreditors | Tier 3 | CREDIT |
| B31 | `creditFlipBatch(address[3], uint256[3])` | L878-892 | onlyFlipCreditors | Tier 3 | CREDIT |

**Risk Tier Notes:**
- **Tier 1** (B22, B23, B24, B27, B29): Complex state transitions, auto-rebuy carry, day resolution, cross-contract callbacks.
- **Tier 2** (B21, B25, B26, B28): Moderate risk -- specific access control paths, settlement logic.
- **Tier 3** (B30, B31): Simple credit forwarding.

#### Category C: Internal/Private State-Changing (11 functions)

| # | Function | Lines | Called By | Key Storage Writes | Flags |
|---|----------|-------|-----------|-------------------|-------|
| C6 | `_depositCoinflip(address, uint256, bool)` | L242-316 | B22 | coinflipBalance, playerState (via _claimCoinflipsInternal), bounty state (via _addDailyFlip) | |
| C7 | `_claimCoinflipsAmount(address, uint256, bool)` | L373-397 | B23, B24, B25, B26 | playerState.claimableStored, (via _claimCoinflipsInternal) | [MULTI-PARENT] |
| C8 | `_claimCoinflipsInternal(address, bool)` | L400-601 | C6, C7, B21, B29, C9, C10 | coinflipBalance[][], playerState.lastClaim, playerState.autoRebuyCarry, (BAF via jackpots.recordBafFlip), (WWXRP via wwxrp.mintPrize) | [MULTI-PARENT] CRITICAL |
| C9 | `_setCoinflipAutoRebuy(address, bool, uint256, bool)` | L698-748 | B27 | playerState.autoRebuyEnabled, autoRebuyStop, autoRebuyStartDay, autoRebuyCarry | |
| C10 | `_setCoinflipAutoRebuyTakeProfit(address, uint256)` | L752-771 | B28 | playerState.autoRebuyStop | |
| C11 | `_addDailyFlip(address, uint256, uint256, bool, bool)` | L608-667 | C6, B29, B30, B31 | coinflipBalance[][], biggestFlipEver, bountyOwedTo, coinflipTopByDay | [MULTI-PARENT] |
| C12 | `_updateTopDayBettor(address, uint256, uint48)` | L1092-1103 | C11 | coinflipTopByDay | |
| C13 | `_questApplyReward(...)` | L1065-1080 | C6 | none (event only) | reclassify to D |
| C14 | `_score96(uint256)` | L1083-1089 | C12 | none (pure) | reclassify to D |
| C15 | `_bafBracketLevel(uint24)` | L1106-1110 | C8 | none (pure) | reclassify to D |
| C16 | `_resolvePlayer(address)` | L1113-1121 | B23, B28 | none (view) | reclassify to D |

**Reclassification notes:** C13, C14, C15, C16 are pure/view functions. They should be reclassified to Category D during the Taskmaster phase. Listed here as C because they are critical links in state-changing call chains.

#### Category D: View/Pure (6 functions)

| # | Function | Lines | Description |
|---|----------|-------|-------------|
| D13 | `getCoinflipDayResult(uint48)` | L354-360 | View: day result lookup |
| D14 | `previewClaimCoinflips(address)` | L899-903 | View: daily + stored claimable |
| D15 | `coinflipAmount(address)` | L906-909 | View: stake for next day |
| D16 | `coinflipAutoRebuyInfo(address)` | L912-927 | View: auto-rebuy state |
| D17 | `coinflipTopLastDay()` | L930-939 | View: leaderboard query |
| D18 | `_viewClaimableCoin(address)` | L942-990 | View: daily claimable calculation |
| D19 | `_coinflipLockedDuringTransition()` | L1000-1013 | View: BAF lock check |
| D20 | `_recyclingBonus(uint256)` | L1016-1023 | Pure: 1% capped bonus |
| D21 | `_afKingRecyclingBonus(uint256, uint16)` | L1027-1040 | Pure: afKing bonus |
| D22 | `_afKingDeityBonusHalfBpsWithLevel(address, uint24)` | L1043-1057 | View: deity bonus calculation |
| D23 | `_targetFlipDay()` | L1060-1062 | View: next day |
| D24 | `_requireApproved(address)` | L1124-1128 | View: approval check |

---

## 2. Storage Layout

### 2.1 BurnieCoin Storage

| Slot | Variable | Type | Size |
|------|----------|------|------|
| 0 | _supply | Supply{totalSupply: uint128, vaultAllowance: uint128} | 32 bytes |
| 1 | balanceOf | mapping(address => uint256) | mapping |
| 2 | allowance | mapping(address => mapping(address => uint256)) | mapping |

**Constants (not in storage):**
- degenerusGame: IDegenerusGame = ContractAddresses.GAME
- questModule: IDegenerusQuests = ContractAddresses.QUESTS
- coinflipContract: address = ContractAddresses.COINFLIP

**Critical invariant:** `totalSupply + vaultAllowance = supplyIncUncirculated` must hold at all times.

### 2.2 BurnieCoinflip Storage

| Slot | Variable | Type | Size |
|------|----------|------|------|
| immutable | burnie | IBurnieCoin | 20 bytes (constructor) |
| immutable | degenerusGame | IDegenerusGame | 20 bytes (constructor) |
| immutable | jackpots | IDegenerusJackpots | 20 bytes (constructor) |
| immutable | wwxrp | IWrappedWrappedXRP | 20 bytes (constructor) |
| 0 | coinflipBalance | mapping(uint48 => mapping(address => uint256)) | mapping |
| 1 | coinflipDayResult | mapping(uint48 => CoinflipDayResult) | mapping |
| 2 | playerState | mapping(address => PlayerCoinflipState) | mapping |
| 3 | currentBounty (packed) | uint128 | 16 bytes |
| 3 | biggestFlipEver (packed) | uint128 | 16 bytes |
| 4 | bountyOwedTo | address | 20 bytes |
| 5 | flipsClaimableDay | uint48 | 6 bytes |
| 6 | coinflipTopByDay | mapping(uint48 => PlayerScore) | mapping |

---

## 3. Cross-Contract Call Map

### BurnieCoin -> BurnieCoinflip (outbound)
| Caller Function | Target | Returns To |
|----------------|--------|-----------|
| creditFlip() | coinflipContract.creditFlip() | void |
| creditFlipBatch() | coinflipContract.creditFlipBatch() | void |
| creditLinkReward() | coinflipContract.creditFlip() | void |
| _claimCoinflipShortfall() | coinflipContract.claimCoinflipsFromBurnie() | uint256 claimed |
| _consumeCoinflipShortfall() | coinflipContract.consumeCoinflipsForBurn() | uint256 consumed |
| notifyQuestMint() | coinflipContract.creditFlip() | void |
| notifyQuestLootBox() | coinflipContract.creditFlip() | void |
| notifyQuestDegenerette() | coinflipContract.creditFlip() | void |
| decimatorBurn() | coinflipContract.creditFlip() | void |

### BurnieCoinflip -> BurnieCoin (callback)
| Caller Function | Target | Returns To |
|----------------|--------|-----------|
| _depositCoinflip() | burnie.burnForCoinflip() | void |
| _claimCoinflipsAmount() | burnie.mintForCoinflip() | void |
| _setCoinflipAutoRebuy() | burnie.mintForCoinflip() | void |
| _setCoinflipAutoRebuyTakeProfit() | burnie.mintForCoinflip() | void |

### BurnieCoinflip -> Other Contracts
| Caller Function | Target | Purpose |
|----------------|--------|---------|
| _claimCoinflipsInternal() | jackpots.recordBafFlip() | BAF leaderboard credit |
| _claimCoinflipsInternal() | jackpots.getLastBafResolvedDay() | BAF day check |
| _claimCoinflipsInternal() | wwxrp.mintPrize() | WWXRP consolation |
| _claimCoinflipsInternal() | game.purchaseInfo() | Level/phase check |
| _claimCoinflipsInternal() | game.syncAfKingLazyPassFromCoin() | afKing sync |
| _claimCoinflipsInternal() | game.level() | Level cache |
| _claimCoinflipsInternal() | game.gameOver() | Game over check |
| _depositCoinflip() | questModule.handleFlip() | Quest processing |
| _depositCoinflip() | game.afKingModeFor() | afKing check |
| _depositCoinflip() | game.consumeCoinflipBoon() (via _addDailyFlip) | Boon consumption |
| _setCoinflipAutoRebuy() | game.deactivateAfKingFromCoin() | afKing deactivation |
| processCoinflipPayouts() | game.payCoinflipBountyDgnrs() | DGNRS bounty reward |
| processCoinflipPayouts() | game.lootboxPresaleActiveFlag() | Presale check |

### BurnieCoin -> Other Contracts
| Caller Function | Target | Purpose |
|----------------|--------|---------|
| decimatorBurn() | game.decWindow() | Decimator window check |
| decimatorBurn() | game.recordDecBurn() | Record burn |
| decimatorBurn() | game.consumeDecimatorBoon() | Boon consumption |
| decimatorBurn() | game.playerActivityScore() | Activity score |
| decimatorBurn() | questModule.handleDecimator() | Quest processing |
| terminalDecimatorBurn() | game.terminalDecWindow() | Terminal window check |
| terminalDecimatorBurn() | game.recordTerminalDecBurn() | Record burn |
| affiliateQuestReward() | questModule.handleAffiliate() | Quest processing |
| rollDailyQuest() | questModule.rollDailyQuest() | Quest roll |
| notifyQuestMint() | questModule.handleMint() | Quest processing |
| notifyQuestLootBox() | questModule.handleLootBox() | Quest processing |
| notifyQuestDegenerette() | questModule.handleDegenerette() | Quest processing |

---

## 4. Critical Call Chains (Priority Analysis Targets)

### Chain 1: Auto-Claim on Transfer (HIGHEST PRIORITY)
```
BurnieCoin.transfer(to, amount)
  -> _claimCoinflipShortfall(msg.sender, amount)
    -> if (balanceOf[msg.sender] < amount && !rngLocked):
      -> BurnieCoinflip.claimCoinflipsFromBurnie(msg.sender, amount - balance)
        -> _claimCoinflipsAmount(player, amount, true)
          -> _claimCoinflipsInternal(player, false) -- processes days
          -> BurnieCoin.mintForCoinflip(player, toClaim)
            -> _mint(player, toClaim) -- WRITES balanceOf[player], _supply.totalSupply
  -> _transfer(msg.sender, to, amount) -- READS balanceOf[msg.sender] (now INCREASED by mint)
```
**Question:** Is this safe? _claimCoinflipShortfall executes fully before _transfer reads balanceOf. The mint happens inside the shortfall call, so by the time _transfer runs, the balance is correctly updated. APPEARS SAFE but needs full Mad Genius verification.

### Chain 2: Consume on Burn (CEI Pattern)
```
BurnieCoin.burnCoin(target, amount)
  -> _consumeCoinflipShortfall(target, amount)
    -> BurnieCoinflip.consumeCoinflipsForBurn(player, amount - balance)
      -> _claimCoinflipsAmount(player, amount, false) -- mintTokens=false, NO callback to BurnieCoin
  -> _burn(target, amount - consumed)
```
**Note:** consumeCoinflipsForBurn does NOT call mintForCoinflip (mintTokens=false). No callback chain. Simpler than Chain 1.

### Chain 3: Coinflip Day Resolution
```
BurnieCoinflip.processCoinflipPayouts(bonusFlip, rngWord, epoch) [called by GAME]
  -> compute rewardPercent and win from entropy
  -> store coinflipDayResult[epoch]
  -> bounty resolution: _addDailyFlip(bountyOwner, slice, 0, false, false) -- no bounty arming
  -> bountyOwedTo = address(0)
  -> flipsClaimableDay = epoch
  -> currentBounty += PRICE_COIN_UNIT
  -> game.payCoinflipBountyDgnrs(...)
  -> _claimCoinflipsInternal(sDGNRS, false) -- keep sDGNRS cursor current
```

### Chain 4: Auto-Rebuy Carry + BAF Credit
```
BurnieCoinflip._claimCoinflipsInternal(player, false)
  -> for each resolved day:
    -> if win + autoRebuy:
      -> carry = payout (or payout - reserved)
      -> carry += recyclingBonus(carry)
    -> if loss + autoRebuy:
      -> carry = 0
  -> if winningBafCredit != 0:
    -> jackpots.recordBafFlip(player, bafLvl, winningBafCredit) [MAY REVERT with RngLocked]
  -> state.lastClaim = processed
  -> state.autoRebuyCarry = carry
  -> if lossCount != 0: wwxrp.mintPrize(player, lossCount * 1 ether)
```

---

## 5. Access Control Matrix

| Function | Allowed Callers | Guard |
|----------|----------------|-------|
| approve | anyone | none |
| transfer | anyone | none |
| transferFrom | anyone | allowance check (game bypass) |
| burnForCoinflip | coinflipContract | == ContractAddresses.COINFLIP |
| mintForCoinflip | coinflipContract | == ContractAddresses.COINFLIP |
| mintForGame | GAME | == ContractAddresses.GAME |
| creditCoin | GAME, AFFILIATE | onlyFlipCreditors modifier |
| creditFlip | GAME, AFFILIATE | onlyFlipCreditors modifier |
| creditFlipBatch | GAME, AFFILIATE | onlyFlipCreditors modifier |
| creditLinkReward | ADMIN | onlyAdmin modifier |
| vaultEscrow | GAME, VAULT | inline check |
| vaultMintTo | VAULT | onlyVault modifier |
| affiliateQuestReward | AFFILIATE | == ContractAddresses.AFFILIATE |
| rollDailyQuest | GAME | onlyDegenerusGameContract |
| notifyQuest* | GAME | == ContractAddresses.GAME |
| burnCoin | GAME, AFFILIATE | onlyTrustedContracts |
| decimatorBurn | anyone (for self/approved) | operator check |
| terminalDecimatorBurn | anyone (for self/approved) | operator check |
| settleFlipModeChange | GAME | onlyDegenerusGameContract |
| depositCoinflip | anyone (for self/approved) | operator check |
| claimCoinflips | anyone (for self/approved) | operator check |
| claimCoinflipsFromBurnie | BurnieCoin | onlyBurnieCoin |
| claimCoinflipsForRedemption | sDGNRS | == ContractAddresses.SDGNRS |
| consumeCoinflipsForBurn | BurnieCoin | onlyBurnieCoin |
| setCoinflipAutoRebuy | anyone/GAME | conditional check |
| setCoinflipAutoRebuyTakeProfit | anyone (for self/approved) | operator check |
| processCoinflipPayouts | GAME | onlyDegenerusGameContract |
| creditFlip (coinflip) | GAME, BurnieCoin | onlyFlipCreditors |
| creditFlipBatch (coinflip) | GAME, BurnieCoin | onlyFlipCreditors |

---

## 6. Potential Attack Surfaces (Pre-Analysis)

### 6.1 Supply Invariant Violation
The `_supply` struct packs totalSupply and vaultAllowance in one slot. Every path through _transfer, _mint, _burn must maintain: `totalSupply + vaultAllowance = supplyIncUncirculated`. The vault redirect paths in each function are the primary risk.

### 6.2 Game Contract Transfer Bypass
`transferFrom()` skips allowance check when `msg.sender == ContractAddresses.GAME`. This gives the game contract unlimited transfer authority over any player's BURNIE. By design, but the Mad Genius should verify no path allows a non-GAME caller to trigger this bypass.

### 6.3 Auto-Claim Race Condition
The _claimCoinflipShortfall flow mints tokens before the parent _transfer subtracts them. If the mint amount exceeds what's needed, the player ends up with more balance than expected after the transfer. Verify exact amount arithmetic.

### 6.4 Bounty Arming + RNG Knowledge
bountyOwedTo is set when a player deposits a record-breaking flip. The bounty pays on the NEXT day's resolution. If a player can see the VRF result before depositing, they could arm the bounty only on winning days. The `!game.rngLocked()` check in _addDailyFlip should prevent this.

### 6.5 uint128 Truncation in claimableStored
Multiple paths cast to uint128: `state.claimableStored = uint128(stored - toClaim)`. If stored exceeds uint128 max, silent truncation occurs. The carry is also uint128. Verify overflow is impossible given token supply bounds.

### 6.6 Claim Window Expiry Griefing
Non-auto-rebuy players lose unclaimed winnings after 90 days. Can an attacker delay resolution or manipulate lastClaim to cause unintended forfeiture?

### 6.7 processCoinflipPayouts RNG Bias
rewardPercent uses `seedWord % 20` for extreme outcomes and `seedWord % COINFLIP_EXTRA_RANGE` for normal range. The seedWord is derived from keccak256(rngWord, epoch). Since rngWord is VRF-provided and epoch is deterministic, this should be unbiased. But verify the modulo bias for COINFLIP_EXTRA_RANGE (38).

### 6.8 afKing Deactivation Path Coverage
Multiple paths call `degenerusGame.deactivateAfKingFromCoin(player)`. Verify all paths that should deactivate actually do, and that no path skips deactivation when take-profit is below AFKING_KEEP_MIN_COIN.
