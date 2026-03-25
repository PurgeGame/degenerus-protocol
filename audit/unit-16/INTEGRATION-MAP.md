# Unit 16: Cross-Contract Integration Map

**Phase:** 118 (Cross-Contract Integration Sweep)
**Date:** 2026-03-25
**Source:** Synthesized from Units 1-15 findings, attack reports, and contract source

---

## Section 1: Cross-Contract Call Graph

### 1.1 Game Module -> Standalone Contract Calls

All calls from Game modules execute in Game's storage context (delegatecall). External calls from modules cross into the standalone contract's own storage.

| # | Source Module | Target Contract | Function Called | Data Flow | Unit Verified |
|---|-------------|----------------|-----------------|-----------|---------------|
| 1 | AdvanceModule | BurnieCoin | `creditFlip(caller, advanceBounty)` | BURNIE bounty for advance caller | Unit 2 |
| 2 | AdvanceModule | BurnieCoin | `creditFlip` via `_applyDailyRng` | Daily RNG rewards | Unit 2 |
| 3 | JackpotModule | BurnieCoin | `creditFlip(winner, amount)` | Daily jackpot coin payout | Unit 3 |
| 4 | JackpotModule | BurnieCoin | `creditFlipBatch(players, amounts)` | Batch trait winner payouts | Unit 3 |
| 5 | JackpotModule | sDGNRS | `deposit(amount)` | sDGNRS pool allocation from jackpot | Unit 3 |
| 6 | JackpotModule | sDGNRS | `transferFromPool(pool, to, amount)` | Pool-to-player transfers | Unit 3 |
| 7 | EndgameModule | sDGNRS | `transferBetweenPools(from, to, amount)` | Pool rebalancing at level end | Unit 4 |
| 8 | EndgameModule | Jackpots | `runBafJackpot(bafPool, lvl, rngWord)` | BAF jackpot resolution | Unit 4 |
| 9 | EndgameModule | DecimatorModule | `runDecimatorJackpot` (delegatecall) | Regular decimator at level end | Unit 4 |
| 10 | EndgameModule | DecimatorModule | `runTerminalDecimatorJackpot` (delegatecall) | Terminal decimator at game-over | Unit 4 |
| 11 | GameOverModule | sDGNRS | `burnRemainingPools()` | Burn residual pools at game-over | Unit 4 |
| 12 | GameOverModule | Vault | ETH send via `.call{value}` | Surplus ETH to vault at game-over | Unit 4 |
| 13 | GameOverModule | sDGNRS | ETH send via `.call{value}` | Surplus ETH to sDGNRS at game-over | Unit 4 |
| 14 | GameOverModule | stETH | `transfer(VAULT, amount)` | stETH to vault at game-over | Unit 4 |
| 15 | MintModule | BurnieCoin | `creditFlip(buyer, amount)` | Streak bonus, century bonus | Unit 5 |
| 16 | MintModule | Affiliate | `payAffiliate(buyer, code, amount)` | Affiliate commission on purchase | Unit 5 |
| 17 | MintModule | Vault | ETH send via `.call{value}` | Vault share of purchase ETH | Unit 5 |
| 18 | WhaleModule | BurnieCoin | `creditFlip(buyer, amount)` | Whale purchase BURNIE reward | Unit 6 |
| 19 | WhaleModule | DGNRS | `poolBalance(pool)` (view) | Pool size for reward calc | Unit 6 |
| 20 | WhaleModule | sDGNRS | `deposit(amount)`, `transferFromPool` | DGNRS reward distribution | Unit 6 |
| 21 | WhaleModule | DeityPass | `mint(to, tokenId)` (ERC721) | Deity pass NFT mint | Unit 6 |
| 22 | DecimatorModule | BurnieCoin | `decimatorBurn(player, amount)` | Burn BURNIE for decimator bet | Unit 7 |
| 23 | DecimatorModule | BurnieCoin | `terminalDecimatorBurn(player, amount)` | Terminal decimator burn | Unit 7 |
| 24 | DecimatorModule | BurnieCoin | `creditFlip(winner, amount)` | Decimator prize payout | Unit 7 |
| 25 | DegeneretteModule | BurnieCoin | `creditFlip`, `mintForGame` | Degenerette BURNIE payouts | Unit 8 |
| 26 | DegeneretteModule | WWXRP | `mintPrize(winner, amount)` | Degenerette WWXRP payouts | Unit 8 |
| 27 | DegeneretteModule | LootboxModule | `resolveLootboxDirect` (delegatecall) | Direct lootbox from Degenerette win | Unit 8 |
| 28 | LootboxModule | BoonModule | `checkAndClearExpiredBoon`, `consumeActivityBoon` (delegatecall) | Boon management during lootbox | Unit 9 |
| 29 | LootboxModule | BurnieCoin | `mintForGame(to, amount)` | BURNIE lootbox payout | Unit 9 |
| 30 | LootboxModule | WWXRP | `mintPrize(to, amount)` | WWXRP lootbox payout | Unit 9 |
| 31 | Game (router) | BurnieCoin | `creditFlip` via `_setAfKingMode` | afKing activation bonus | Unit 1 |
| 32 | Game (router) | Coinflip | `setCoinflipAutoRebuy`, `settleFlipModeChange` | afKing mode toggle | Unit 1 |
| 33 | Game (router) | Admin | `shutdownVrf()` | VRF shutdown at game-over | Unit 1 |
| 34 | Game (router) | sDGNRS | `resolveRedemptionLootbox` | Redemption lootbox path | Unit 1 |

### 1.2 Standalone -> Standalone Contract Calls

| # | Source | Target | Function Called | Purpose | Unit |
|---|--------|--------|-----------------|---------|------|
| 1 | BurnieCoin | Coinflip | `claimCoinflipsFromBurnie` (auto-claim) | Auto-claim on transfer | Unit 10 |
| 2 | BurnieCoin | Quests | `handleMint`, `handleFlip`, `handleDecimator`, `handleAffiliate`, `handleLootBox`, `handleDegenerette` | Quest progress notification | Unit 10 |
| 3 | BurnieCoin | Jackpots | `recordBafFlip(player, amount)` | BAF jackpot tracking | Unit 10 |
| 4 | sDGNRS | Game | `claimWinnings(address(this))` | ETH pull during burn | Unit 11 |
| 5 | sDGNRS | DGNRS | `burnForSdgnrs(player, amount)` | Cross-contract burn | Unit 11 |
| 6 | sDGNRS | BurnieCoin | `transfer`, `claimCoinflips` | BURNIE payout in redemption | Unit 11 |
| 7 | sDGNRS | Coinflip | `claimCoinflipsForRedemption` | Coinflip payout in redemption | Unit 11 |
| 8 | sDGNRS | Game | `resolveRedemptionLootbox` | Lootbox during redemption | Unit 11 |
| 9 | DGNRS | sDGNRS | `wrapperTransferTo(to, amount)` | Unwrap DGNRS to sDGNRS | Unit 11 |
| 10 | DGNRS | sDGNRS | `burn(amount)` via `burnForSdgnrs` | DGNRS burn path | Unit 11 |
| 11 | Vault | BurnieCoin | `vaultMintTo`, `vaultEscrow`, `transfer` | BURNIE management | Unit 12 |
| 12 | Vault | Coinflip | `claimCoinflips` | BURNIE waterfall claim | Unit 12 |
| 13 | Vault | Game | Proxy forwarding functions | Vault->Game proxy | Unit 12 |
| 14 | Admin | VRF Coordinator | `createSubscription`, `cancelSubscription`, `requestRandomWords` | VRF management | Unit 13 |
| 15 | Admin | LINK Token | `transfer`, `transferAndCall` | LINK token operations | Unit 13 |
| 16 | Affiliate | BurnieCoin | `creditFlip`, `affiliateQuestReward` | Commission payouts | Unit 14 |

### 1.3 Callback / Re-entry Chains

| # | Chain | Max Depth | Safety Verdict |
|---|-------|-----------|----------------|
| 1 | BurnieCoin.transfer -> Coinflip.claimCoinflipsFromBurnie -> BurnieCoin.mintForCoinflip -> BurnieCoin._transfer (resumes) | 3 | SAFE: fresh storage reads at each re-entry point (Unit 10) |
| 2 | Game.claimWinnings -> ETH send -> sDGNRS.receive() | 2 | SAFE: sDGNRS.receive() only accepts from DGNRS (Unit 11) |
| 3 | sDGNRS._deterministicBurnFrom -> Game.claimWinnings -> ETH send -> sDGNRS.receive() | 3 | SAFE: receive() rejects (only DGNRS accepted), ETH goes to player not sDGNRS (Unit 11) |
| 4 | Vault.burnEth -> ETH send -> recipient | 2 | SAFE: CEI followed, shares burned before send (Unit 12) |
| 5 | LootboxModule -> BoonModule (nested delegatecall, same storage) | 2 | SAFE: no cached locals across boundary (Unit 9) |
| 6 | DegeneretteModule -> LootboxModule (nested delegatecall, same storage) | 2 | SAFE: pool committed before call (Unit 8) |
| 7 | DegeneretteModule -> LootboxModule -> BoonModule (triple nesting) | 3 | SAFE: each layer verified independently (Units 8, 9) |

### 1.4 Nested Delegatecall Chains (within Game storage context)

| Chain | Path | Storage Concern | Verdict |
|-------|------|-----------------|---------|
| advanceGame -> rngGate -> JackpotModule functions | AdvanceModule -> JackpotModule | prizePoolsPacked, claimablePool written by JackpotModule while AdvanceModule's do-while loop is active | SAFE: do-while break isolation prevents stale reuse (Unit 2) |
| advanceGame -> rngGate -> EndgameModule.runRewardJackpots | AdvanceModule -> EndgameModule | futurePrizePool written by rebuyDelta reconciliation | SAFE: rebuyDelta mechanism (Unit 4) |
| advanceGame -> rngGate -> EndgameModule -> DecimatorModule | AdvanceModule -> EndgameModule -> DecimatorModule | decBucketOffsetPacked | **KNOWN ISSUE: collision at GAMEOVER level (Unit 7 MEDIUM)** |
| DegeneretteModule -> LootboxModule -> BoonModule | 3-deep nested delegatecall | boonPacked, mintPacked_ | SAFE: no cached locals (Units 8, 9) |

---

## Section 2: Shared Storage Write Map

### 2.1 Variables Written by Multiple Modules

All modules execute in DegenerusGame's storage context via delegatecall. The following variables are written by 2+ modules within the same or different transaction paths.

| Variable | Storage | Writers | Access Pattern | Conflict Risk |
|----------|---------|---------|---------------|---------------|
| `prizePoolsPacked` | Slot 4 (packed) | JackpotModule, MintModule, DegeneretteModule, EndgameModule | Always via `_setFuturePrizePool` / `_setNextPrizePool` with fresh `_get*` reads | **NONE**: fresh read-modify-write pattern |
| `claimablePool` | Slot 5 | JackpotModule, EndgameModule, DegeneretteModule, Game (router) | Direct `claimablePool +=` or fresh computation | **NONE**: additive pattern, no stale cache |
| `claimableWinnings[addr]` | Mapping | JackpotModule, EndgameModule, GameOverModule, DegeneretteModule, Game | Via `_addClaimableEth` helper (return-value tracking) | **NONE**: return-value reconciliation pattern |
| `mintPacked_[addr]` | Mapping | MintModule (purchase), WhaleModule (pass), BoonModule (boon consumption) | Each writes non-overlapping bit fields | **NONE**: no bit field overlap |
| `boonPacked[addr]` | 2 slots | BoonModule only (delegatecalled by LootboxModule/DegeneretteModule) | Single writer module | **NONE**: single writer |
| `decBucketOffsetPacked[lvl]` | Mapping | DecimatorModule (regular), DecimatorModule (terminal, via GameOverModule) | Same storage slot, different RNG words | **MEDIUM**: collision at GAMEOVER level (Unit 7 finding) |
| `totalDecBurned[addr]` | Mapping | DecimatorModule (regular burn), DecimatorModule (terminal burn) | Additive via different paths | **NONE**: additive accumulation |
| `activityScorePacked[addr]` | Mapping | MintModule, WhaleModule, DegeneretteModule | Write via `_recordActivity` helper | **NONE**: activity score is additive, not read-modify-write |

### 2.2 Single-Writer State Variables (No Cross-Module Risk)

These critical state variables are written by exactly one module:

| Variable | Writer | Role |
|----------|--------|------|
| `currentDay` | AdvanceModule | Day counter (FSM) |
| `purchaseLevel` | AdvanceModule | Game level (FSM) |
| `jackpotPhaseFlag` | AdvanceModule | Phase state (FSM) |
| `rngLockedFlag` | AdvanceModule | VRF lock (FSM) |
| `prizePoolFrozen` | AdvanceModule | Jackpot math guard |
| `gameOverFlag` | AdvanceModule / GameOverModule | Terminal state |
| `ticketWriteSlot` | AdvanceModule | Double-buffer selector |
| `price` | AdvanceModule | Ticket price (level-dependent) |
| `rngWordCurrent` | AdvanceModule | Current VRF word |

### 2.3 Cross-Module Transaction Paths (Same Top-Level Call)

These are paths where multiple modules execute within a single `advanceGame()` call:

| Path | Modules Touched | Shared Variables Written | Isolation Mechanism |
|------|----------------|------------------------|---------------------|
| advanceGame -> rngGate -> payDailyJackpot | Advance + Jackpot | prizePoolsPacked, claimablePool, claimableWinnings | do-while break isolation (AdvanceModule caches break before JackpotModule writes) |
| advanceGame -> rngGate -> runRewardJackpots | Advance + Endgame + Decimator | prizePoolsPacked, claimablePool, decBucketOffsetPacked | rebuyDelta reconciliation + do-while break |
| advanceGame -> rngGate -> processTicketBatch | Advance + Jackpot (ticket processing) | mintPacked_ (via _raritySymbolBatch) | Independent: ticket processing writes to different addresses than active purchaser |
| placeFullTicketBets -> resolveBets -> resolveLootboxDirect | Degenerette + Lootbox + Boon | prizePoolsPacked, boonPacked, mintPacked_ | Pool committed before lootbox delegatecall. Boon writes use fresh SLOADs. |

---

## Section 3: Access Control Matrix

### 3.1 Game Contract (DegenerusGame.sol) -- Router

| Function | Access Control | Guard Type |
|----------|---------------|------------|
| receive() | Permissionless | None (accepts ETH) |
| advanceGame() | Permissionless | None (public good) |
| purchaseFor() | Permissionless | None (requires msg.value) |
| purchaseWhaleBundle() | Permissionless | None (requires msg.value) |
| purchaseLazyPass() | Permissionless | None (requires msg.value) |
| purchaseDeityPass() | Permissionless | None (requires msg.value) |
| placeFullTicketBets() | Permissionless | None (requires funds) |
| claimWinnings() | Permissionless | Claims own balance |
| claimWinningsStethFirst() | Permissionless | Claims own balance |
| claimDecimatorJackpot() | Permissionless | Claims own balance |
| claimTerminalDecimatorJackpot() | Permissionless | Claims own balance |
| claimWhalePass() | Permissionless | Claims own pass |
| reverseFlip() | Permissionless | Requires active ticket |
| requestLootboxRng() | Permissionless | Requires pending lootbox |
| resolveBets() | Permissionless | Resolves own bets |
| resolveRedemptionLootbox() | sDGNRS only | `msg.sender == SDGNRS` |
| operatorClaimWinnings() | Approved operator | `operatorApprovals` mapping |
| setAutoRebuy() | Permissionless | Sets own config |
| setTakeProfit() | Permissionless | Sets own config |
| All view functions | Permissionless | Read-only |

### 3.2 Game Modules (10 modules, all delegatecalled)

Game modules do not have their own access control -- they execute in Game's context. Access control is enforced at the Game router level via the delegatecall dispatch functions.

### 3.3 BurnieCoin

| Function | Access Control | Guard |
|----------|---------------|-------|
| transfer, approve, transferFrom | Permissionless | Standard ERC20 |
| burnForCoinflip | COINFLIP only | `msg.sender != coinflipContract` revert |
| mintForCoinflip | COINFLIP only | `msg.sender != coinflipContract` revert |
| mintForGame | GAME only | `msg.sender != GAME` revert |
| creditCoin, creditFlip, creditFlipBatch | GAME or COINFLIP | `onlyFlipCreditors` modifier |
| creditLinkReward | ADMIN only | `onlyAdmin` modifier |
| vaultEscrow | VAULT only | `msg.sender != VAULT` revert |
| vaultMintTo | VAULT only | `onlyVault` modifier |
| decimatorBurn, terminalDecimatorBurn | GAME only | `msg.sender != GAME` revert |
| notifyQuestLootBox, notifyQuestDegenerette | GAME only | Quest notification |

### 3.4 BurnieCoinflip

| Function | Access Control | Guard |
|----------|---------------|-------|
| depositCoinflip | Permissionless (via BurnieCoin transfer) | Validates sender holds BURNIE |
| settleFlipModeChange | GAME only | `onlyDegenerusGameContract` |
| setCoinflipAutoRebuy | GAME only | `onlyDegenerusGameContract` |
| processCoinflipPayouts | GAME only | `onlyDegenerusGameContract` |
| claimCoinflips | Permissionless | Claims own balance |

### 3.5 sDGNRS (StakedDegenerusStonk)

| Function | Access Control | Guard |
|----------|---------------|-------|
| depositSteth | GAME only | `onlyGame` |
| gameDeposit | GAME only | `onlyGame` |
| transferFromPool, transferBetweenPools, burnRemainingPools | GAME only | `onlyGame` |
| resolveRedemptionPeriod | GAME only | `onlyGame` |
| wrapperTransferTo | DGNRS only | `msg.sender == DGNRS` |
| submitGamblingClaim | Permissionless | Burns own tokens |
| claimRedemption | Permissionless | Claims own balance |
| burn | Permissionless | Burns own tokens |
| gameAdvance, gameClaimWhalePass | Permissionless | Proxy to Game |

### 3.6 DGNRS (DegenerusStonk)

| Function | Access Control | Guard |
|----------|---------------|-------|
| burnForSdgnrs | sDGNRS only | `msg.sender == SDGNRS` |
| burn | Permissionless (gameOver only) | `gameOver()` check |
| unwrapTo | CREATOR only | `msg.sender == CREATOR` |
| Standard ERC20 | Permissionless | Standard |

### 3.7 DegenerusVault

| Function | Access Control | Guard |
|----------|---------------|-------|
| deposit | GAME only | `onlyGame` |
| burnCoin, burnEth | Approved shareholders | `_requireApproved` |
| setLinkPriceFeed, swapEthForStEth, stakeEthToStEth, setLootboxRngThreshold | DGVE majority owner | `onlyVaultOwner` |
| gameSetAutoRebuy | Self (vault contract calling Game) | Internal proxy |
| All proxy functions | Permissionless | Forward to Game |

### 3.8 WWXRP (WrappedWrappedXRP)

| Function | Access Control | Guard |
|----------|---------------|-------|
| mintPrize | GAME, COIN, COINFLIP, VAULT | `onlyMinter` (4 compile-time addresses) |
| wrap | Permissionless (requires wXRP) | 1:1 backed |
| unwrap | Permissionless (requires WWXRP) | First-come-first-served against reserves |
| donate | Permissionless (requires wXRP) | Increases reserves |
| burn | Permissionless | Burns own tokens |

### 3.9 DegenerusAdmin

| Function | Access Control | Guard |
|----------|---------------|-------|
| setLinkEthPriceFeed | DGVE majority owner | `onlyOwner` + broken feed gate |
| swapGameEthForStEth, stakeGameEthToStEth | DGVE majority owner | `onlyOwner` |
| setLootboxRngThreshold | DGVE majority owner | `onlyOwner` |
| propose | DGVE owner (20h stall) OR 0.5% sDGNRS (7d stall) | Dual-path |
| vote | Any sDGNRS holder | Balance > 0 + stall check |
| shutdownVrf | GAME only | `msg.sender == GAME` |
| onTokenTransfer | LINK token only | `msg.sender == LINK_TOKEN` |

### 3.10 Peripherals (Affiliate, Quests, Jackpots)

| Contract | Function | Access Control |
|----------|----------|---------------|
| Affiliate | createAffiliateCode | Permissionless |
| Affiliate | referPlayer | Permissionless (self-referral blocked) |
| Affiliate | payAffiliate | COIN or GAME only |
| Quests | rollDailyQuest | COIN or COINFLIP only |
| Quests | awardQuestStreakBonus | GAME only |
| Quests | handle* (6 handlers) | COIN or COINFLIP only |
| Jackpots | recordBafFlip | COIN or COINFLIP only |
| Jackpots | runBafJackpot | GAME only |

### 3.11 Access Control Summary

| Guard Type | Count | Pattern |
|-----------|-------|---------|
| Compile-time constant (ContractAddresses.*) | 45+ | Immutable, no admin override |
| DGVE majority owner (vault share voting) | 5 | Owner requires >50.1% of DGVE |
| Permissionless (player action) | 30+ | Purchases, claims, burns, standard ERC20 |
| Conditional (gameOver, rngLocked, etc.) | 8 | State-dependent gates |

**Key finding:** ALL access control gates use compile-time constant addresses set via `ContractAddresses.*`. No configurable admin addresses. No proxy upgrade paths. No address re-pointing.

---

*Integration map completed: 2026-03-25*
*Source: 15 unit findings reports + contract source verification*
