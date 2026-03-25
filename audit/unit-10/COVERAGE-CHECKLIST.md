# Unit 10: BURNIE Token + Coinflip -- Coverage Checklist

**Taskmaster:** Claude Opus 4.6 (1M context)
**Phase:** 112-burnie-token-coinflip
**Contracts:** BurnieCoin.sol (~1,075 lines), BurnieCoinflip.sol (~1,129 lines)
**Total Functions:** 58 (31 Cat B, 16 Cat C, 11+ Cat D)
**Date:** 2026-03-25

---

## Category B: External State-Changing Functions

### BurnieCoin.sol (20 functions)

| # | Function | Lines | Risk | Subsystem | Analyzed? | Call Tree? | Storage Writes? | Cache Check? |
|---|----------|-------|------|-----------|-----------|-----------|----------------|-------------|
| B1 | `approve(address, uint256)` | L394-401 | T3 | ERC20 | | | | |
| B2 | `transfer(address, uint256)` | L408-412 | T1 | ERC20+AUTO-CLAIM | | | | |
| B3 | `transferFrom(address, address, uint256)` | L422-441 | T1 | ERC20+AUTO-CLAIM | | | | |
| B4 | `burnForCoinflip(address, uint256)` | L528-531 | T2 | COINFLIP-GATE | | | | |
| B5 | `mintForCoinflip(address, uint256)` | L537-540 | T2 | COINFLIP-GATE | | | | |
| B6 | `mintForGame(address, uint256)` | L546-550 | T3 | GAME-GATE | | | | |
| B7 | `creditCoin(address, uint256)` | L556-559 | T3 | CREDIT | | | | |
| B8 | `creditFlip(address, uint256)` | L566-568 | T2 | CREDIT-FORWARD | | | | |
| B9 | `creditFlipBatch(address[3], uint256[3])` | L574-576 | T2 | CREDIT-FORWARD | | | | |
| B10 | `creditLinkReward(address, uint256)` | L584-588 | T3 | ADMIN-CREDIT | | | | |
| B11 | `vaultEscrow(uint256)` | L688-699 | T2 | VAULT-ESCROW | | | | |
| B12 | `vaultMintTo(address, uint256)` | L705-717 | T1 | VAULT-MINT | | | | |
| B13 | `affiliateQuestReward(address, uint256)` | L724-745 | T2 | QUEST-HUB | | | | |
| B14 | `rollDailyQuest(uint48, uint256)` | L759-774 | T2 | QUEST-HUB | | | | |
| B15 | `notifyQuestMint(address, uint32, bool)` | L782-808 | T2 | QUEST-HUB | | | | |
| B16 | `notifyQuestLootBox(address, uint256)` | L814-834 | T2 | QUEST-HUB | | | | |
| B17 | `notifyQuestDegenerette(address, uint256, bool)` | L841-861 | T2 | QUEST-HUB | | | | |
| B18 | `burnCoin(address, uint256)` | L869-875 | T1 | BURN+AUTO-CONSUME | | | | |
| B19 | `decimatorBurn(address, uint256)` | L890-966 | T1 | DECIMATOR | | | | |
| B20 | `terminalDecimatorBurn(address, uint256)` | L981-1007 | T2 | DEATH-BET | | | | |

### BurnieCoinflip.sol (11 functions)

| # | Function | Lines | Risk | Subsystem | Analyzed? | Call Tree? | Storage Writes? | Cache Check? |
|---|----------|-------|------|-----------|-----------|-----------|----------------|-------------|
| B21 | `settleFlipModeChange(address)` | L215-222 | T2 | SETTLEMENT | | | | |
| B22 | `depositCoinflip(address, uint256)` | L225-239 | T1 | DEPOSIT | | | | |
| B23 | `claimCoinflips(address, uint256)` | L326-329 | T1 | CLAIM | | | | |
| B24 | `claimCoinflipsFromBurnie(address, uint256)` | L335-339 | T1 | CLAIM-CALLBACK | | | | |
| B25 | `claimCoinflipsForRedemption(address, uint256)` | L345-351 | T2 | CLAIM-REDEMPTION | | | | |
| B26 | `consumeCoinflipsForBurn(address, uint256)` | L365-370 | T2 | CONSUME | | | | |
| B27 | `setCoinflipAutoRebuy(address, bool, uint256)` | L674-686 | T1 | AUTO-REBUY | | | | |
| B28 | `setCoinflipAutoRebuyTakeProfit(address, uint256)` | L689-693 | T2 | AUTO-REBUY | | | | |
| B29 | `processCoinflipPayouts(bool, uint256, uint48)` | L778-862 | T1 | DAY-RESOLUTION | | | | |
| B30 | `creditFlip(address, uint256)` | L869-875 | T3 | CREDIT | | | | |
| B31 | `creditFlipBatch(address[3], uint256[3])` | L878-892 | T3 | CREDIT | | | | |

---

## Category C: Internal/Private State-Changing Functions

### BurnieCoin.sol (5 functions)

| # | Function | Lines | Called By | Key Storage Writes | Flags |
|---|----------|-------|-----------|-------------------|-------|
| C1 | `_transfer(address, address, uint256)` | L453-473 | B2, B3 | balanceOf[from], balanceOf[to], _supply.totalSupply, _supply.vaultAllowance | [MULTI-PARENT] |
| C2 | `_mint(address, uint256)` | L479-492 | B5, B6, B7, B12(inline) | balanceOf[to], _supply.totalSupply, _supply.vaultAllowance | [MULTI-PARENT] |
| C3 | `_burn(address, uint256)` | L499-515 | B4, B18, B19, B20 | balanceOf[from], _supply.totalSupply, _supply.vaultAllowance | [MULTI-PARENT] |
| C4 | `_claimCoinflipShortfall(address, uint256)` | L590-601 | B2, B3 | (triggers C2 via external callback) | [MULTI-PARENT] |
| C5 | `_consumeCoinflipShortfall(address, uint256)` | L603-614 | B18, B19, B20 | (no callback to BurnieCoin) | [MULTI-PARENT] |

### BurnieCoinflip.sol (7 state-changing functions)

| # | Function | Lines | Called By | Key Storage Writes | Flags |
|---|----------|-------|-----------|-------------------|-------|
| C6 | `_depositCoinflip(address, uint256, bool)` | L242-316 | B22 | coinflipBalance, playerState, biggestFlipEver, bountyOwedTo | |
| C7 | `_claimCoinflipsAmount(address, uint256, bool)` | L373-397 | B23, B24, B25, B26 | playerState.claimableStored | [MULTI-PARENT] |
| C8 | `_claimCoinflipsInternal(address, bool)` | L400-601 | C6, C7, B21, B29, C9, C10 | coinflipBalance[][], playerState.lastClaim, playerState.autoRebuyCarry | [MULTI-PARENT] CRITICAL |
| C9 | `_setCoinflipAutoRebuy(address, bool, uint256, bool)` | L698-748 | B27 | playerState.autoRebuyEnabled/Stop/StartDay/Carry | |
| C10 | `_setCoinflipAutoRebuyTakeProfit(address, uint256)` | L752-771 | B28 | playerState.autoRebuyStop | |
| C11 | `_addDailyFlip(address, uint256, uint256, bool, bool)` | L608-667 | C6, B29, B30, B31 | coinflipBalance, biggestFlipEver, bountyOwedTo, coinflipTopByDay | [MULTI-PARENT] |
| C12 | `_updateTopDayBettor(address, uint256, uint48)` | L1092-1103 | C11 | coinflipTopByDay | |

---

## Category D: View/Pure Functions

### BurnieCoin.sol (12 functions)

| # | Function | Lines | Type | Description |
|---|----------|-------|------|-------------|
| D1 | `claimableCoin()` | L284-286 | view | Proxy to BurnieCoinflip.previewClaimCoinflips |
| D2 | `balanceOfWithClaimable(address)` | L295-303 | view | Balance + claimable + vault allowance |
| D3 | `previewClaimCoinflips(address)` | L309-311 | view | Proxy to BurnieCoinflip.previewClaimCoinflips |
| D4 | `coinflipAutoRebuyInfo(address)` | L318-322 | view | Proxy to BurnieCoinflip.coinflipAutoRebuyInfo |
| D5 | `totalSupply()` | L325-327 | view | _supply.totalSupply |
| D6 | `supplyIncUncirculated()` | L332-334 | view | totalSupply + vaultAllowance |
| D7 | `vaultMintAllowance()` | L339-341 | view | _supply.vaultAllowance |
| D8 | `coinflipAmount(address)` | L1018-1020 | view | Proxy to BurnieCoinflip.coinflipAmount |
| D9 | `_adjustDecimatorBucket(uint256, uint8)` | L1028-1044 | pure | Bucket calculation |
| D10 | `_decimatorBurnMultiplier(uint256)` | L1047-1050 | pure | Burn multiplier |
| D11 | `_questApplyReward(...)` | L1059-1075 | private | Event emission + reward passthrough |
| D12 | `_toUint128(uint256)` | L443-446 | pure | Safe downcast with overflow check |

### BurnieCoinflip.sol (12 functions)

| # | Function | Lines | Type | Description |
|---|----------|-------|------|-------------|
| D13 | `getCoinflipDayResult(uint48)` | L354-360 | view | Day result lookup |
| D14 | `previewClaimCoinflips(address)` | L899-903 | view | Daily + stored claimable |
| D15 | `coinflipAmount(address)` | L906-909 | view | Stake for next day |
| D16 | `coinflipAutoRebuyInfo(address)` | L912-927 | view | Auto-rebuy state |
| D17 | `coinflipTopLastDay()` | L930-939 | view | Leaderboard query |
| D18 | `_viewClaimableCoin(address)` | L942-990 | view | Daily claimable calculation |
| D19 | `_coinflipLockedDuringTransition()` | L1000-1013 | view | BAF resolution lock check |
| D20 | `_recyclingBonus(uint256)` | L1016-1023 | pure | 1% capped at 1000 BURNIE |
| D21 | `_afKingRecyclingBonus(uint256, uint16)` | L1027-1040 | pure | afKing recycling with deity bonus |
| D22 | `_afKingDeityBonusHalfBpsWithLevel(address, uint24)` | L1043-1057 | view | Deity bonus calculation |
| D23 | `_targetFlipDay()` | L1060-1062 | view | Next flip day |
| D24 | `_requireApproved(address)` | L1124-1128 | view | Operator approval check |
| D25 | `_resolvePlayer(address)` | L1113-1121 | view | Player resolution |
| D26 | `_questApplyReward(...)` | L1065-1080 | private | Event emission (coinflip) |
| D27 | `_score96(uint256)` | L1083-1089 | pure | Score truncation to uint96 |
| D28 | `_bafBracketLevel(uint24)` | L1106-1110 | pure | Round level to BAF bracket |

---

## Cross-Contract Callback Chain

```
BurnieCoin                                    BurnieCoinflip
=========                                    ==============

transfer(to, amount)
  |
  +-> _claimCoinflipShortfall(from, amount)
  |     |
  |     +-> if balance < amount && !rngLocked:
  |           |
  |           +-----> claimCoinflipsFromBurnie(from, shortfall) --------+
  |                                                                     |
  |                   _claimCoinflipsAmount(player, amount, true)       |
  |                     |                                               |
  |                     +-> _claimCoinflipsInternal(player, false)      |
  |                     |     -> processes days, accumulates mintable   |
  |                     |     -> records BAF credit (jackpots)          |
  |                     |     -> mints WWXRP consolation (wwxrp)       |
  |                     |                                               |
  |  mintForCoinflip(player, claimed) <---------+                      |
  |    |                                                                |
  |    +-> _mint(player, claimed)                                      |
  |          -> balanceOf[player] += claimed                           |
  |          -> _supply.totalSupply += claimed                         |
  |                                                                    |
  +-> _transfer(from, to, amount)                                     |
        -> balanceOf[from] -= amount   [balance now includes minted]   |
        -> balanceOf[to] += amount                                     |
```

### Consume Chain (No Callback)
```
BurnieCoin                                    BurnieCoinflip
=========                                    ==============

burnCoin(target, amount)
  |
  +-> _consumeCoinflipShortfall(target, amount)
  |     |
  |     +-> if balance < amount && !rngLocked:
  |           |
  |           +-----> consumeCoinflipsForBurn(player, shortfall) -------+
  |                                                                     |
  |                   _claimCoinflipsAmount(player, amount, false)      |
  |                     -> mintTokens=false, NO callback to BurnieCoin  |
  |                     -> returns consumed amount                      |
  |     <------------- returns consumed ----------------------------+   |
  |                                                                     |
  +-> _burn(target, amount - consumed)                                 |
        -> balanceOf[target] -= (amount - consumed)                    |
        -> _supply.totalSupply -= (amount - consumed)                  |
```

---

## Cross-Module External Calls

| Source | Target Contract | Function Called | Purpose |
|--------|----------------|----------------|---------|
| BurnieCoin.decimatorBurn | DegenerusGame | decWindow() | Check decimator window |
| BurnieCoin.decimatorBurn | DegenerusGame | recordDecBurn() | Record burn |
| BurnieCoin.decimatorBurn | DegenerusGame | consumeDecimatorBoon() | Boon consumption |
| BurnieCoin.decimatorBurn | DegenerusGame | playerActivityScore() | Activity score |
| BurnieCoin.decimatorBurn | DegenerusGame | isOperatorApproved() | Operator check |
| BurnieCoin.terminalDecimatorBurn | DegenerusGame | terminalDecWindow() | Terminal window check |
| BurnieCoin.terminalDecimatorBurn | DegenerusGame | recordTerminalDecBurn() | Record burn |
| BurnieCoin.quest functions | DegenerusQuests | handle*() | Quest processing |
| BurnieCoin.rollDailyQuest | DegenerusQuests | rollDailyQuest() | Quest roll |
| BurnieCoinflip._claimCoinflipsInternal | DegenerusJackpots | recordBafFlip() | BAF credit |
| BurnieCoinflip._claimCoinflipsInternal | DegenerusJackpots | getLastBafResolvedDay() | BAF day |
| BurnieCoinflip._claimCoinflipsInternal | WrappedWrappedXRP | mintPrize() | WWXRP consolation |
| BurnieCoinflip._claimCoinflipsInternal | DegenerusGame | purchaseInfo() | Level/phase |
| BurnieCoinflip._claimCoinflipsInternal | DegenerusGame | syncAfKingLazyPassFromCoin() | afKing sync |
| BurnieCoinflip._claimCoinflipsInternal | DegenerusGame | level() | Level cache |
| BurnieCoinflip._claimCoinflipsInternal | DegenerusGame | gameOver() | Game over check |
| BurnieCoinflip._claimCoinflipsInternal | DegenerusGame | deityPassCountFor() | Deity check |
| BurnieCoinflip._claimCoinflipsInternal | DegenerusGame | afKingActivatedLevelFor() | Activation level |
| BurnieCoinflip._depositCoinflip | DegenerusQuests | handleFlip() | Quest processing |
| BurnieCoinflip._depositCoinflip | DegenerusGame | afKingModeFor() | afKing check |
| BurnieCoinflip._depositCoinflip | DegenerusGame | deityPassCountFor() | Deity check |
| BurnieCoinflip._addDailyFlip | DegenerusGame | consumeCoinflipBoon() | Boon consumption |
| BurnieCoinflip._addDailyFlip | DegenerusGame | rngLocked() | RNG lock check |
| BurnieCoinflip._addDailyFlip | DegenerusGame | currentDayView() | Target day |
| BurnieCoinflip._setCoinflipAutoRebuy | DegenerusGame | rngLocked() | RNG lock |
| BurnieCoinflip._setCoinflipAutoRebuy | DegenerusGame | deactivateAfKingFromCoin() | afKing deactivation |
| BurnieCoinflip.processCoinflipPayouts | DegenerusGame | lootboxPresaleActiveFlag() | Presale check |
| BurnieCoinflip.processCoinflipPayouts | DegenerusGame | payCoinflipBountyDgnrs() | DGNRS reward |

---

## Storage Write Map

### BurnieCoin Storage Writes

| Storage Variable | Written By |
|-----------------|-----------|
| _supply.totalSupply | C1 (_transfer to vault), C2 (_mint), C3 (_burn), B12 (vaultMintTo) |
| _supply.vaultAllowance | C1 (_transfer to vault), C2 (_mint to vault), C3 (_burn from vault), B11 (vaultEscrow), B12 (vaultMintTo) |
| balanceOf[addr] | C1 (_transfer), C2 (_mint), C3 (_burn), B12 (vaultMintTo) |
| allowance[owner][spender] | B1 (approve), B3 (transferFrom) |

### BurnieCoinflip Storage Writes

| Storage Variable | Written By |
|-----------------|-----------|
| coinflipBalance[day][player] | C8 (_claimCoinflipsInternal: clear on claim), C11 (_addDailyFlip: add stake) |
| coinflipDayResult[epoch] | B29 (processCoinflipPayouts) |
| playerState[player].claimableStored | C7 (_claimCoinflipsAmount), B21 (settleFlipModeChange) |
| playerState[player].lastClaim | C8 (_claimCoinflipsInternal) |
| playerState[player].autoRebuyEnabled | C9 (_setCoinflipAutoRebuy) |
| playerState[player].autoRebuyStop | C9 (_setCoinflipAutoRebuy), C10 (_setCoinflipAutoRebuyTakeProfit) |
| playerState[player].autoRebuyStartDay | C9 (_setCoinflipAutoRebuy) |
| playerState[player].autoRebuyCarry | C8 (_claimCoinflipsInternal), C9 (_setCoinflipAutoRebuy) |
| currentBounty | B29 (processCoinflipPayouts) |
| biggestFlipEver | C11 (_addDailyFlip) |
| bountyOwedTo | C11 (_addDailyFlip), B29 (processCoinflipPayouts) |
| flipsClaimableDay | B29 (processCoinflipPayouts) |
| coinflipTopByDay[day] | C12 (_updateTopDayBettor) |

---

## Priority Investigation Targets for Mad Genius

1. **Auto-claim callback chain** (B2/B3 -> C4 -> BurnieCoinflip -> B5 -> C2): Verify no stale balanceOf[] or _supply values after callback
2. **Vault redirect correctness** (C1/C2/C3): Verify supply invariant holds across all 6 vault paths
3. **processCoinflipPayouts RNG** (B29): Verify entropy derivation, modulo bias, win determination
4. **Auto-rebuy carry extraction** (C8/C9): Verify RNG lock prevents carry extraction before known outcomes
5. **Bounty timing + RNG knowledge** (C11): Verify rngLocked() prevents manipulation
6. **uint128 truncation** (C7/C8/C9/C10): Verify accumulation cannot overflow uint128
7. **BAF credit during claim** (C8): Verify rngLocked revert is correct for BAF resolution levels
8. **Game contract transferFrom bypass** (B3): Verify no path allows non-GAME caller to bypass allowance

---

*Taskmaster: Coverage checklist complete. 31 Cat B + 12 Cat C + 28 Cat D = 71 total functions tracked. Ready for Mad Genius attack phase.*
