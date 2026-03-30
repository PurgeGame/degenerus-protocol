# ABI Cleanup Candidates -- Phase 144 Scan

Scanned: 25 production contracts (16 standalone + 9 delegatecall modules), ~225 external/public functions examined (excluding interface declarations).

## Forwarding Wrappers

Functions whose entire body is a single delegated call to another contract with identical or trivially mapped parameters and no additional logic (no access control, no events, no state changes beyond the forward).

| # | Contract | Function | Target | Rationale | Risk Notes |
|---|----------|----------|--------|-----------|------------|
| 1 | BurnieCoin | `previewClaimCoinflips(address)` | BurnieCoinflip.previewClaimCoinflips | Body is `return IBurnieCoinflip(coinflipContract).previewClaimCoinflips(player)` -- pure passthrough with identical signature | Check if UI/SDK calls BurnieCoin.previewClaimCoinflips; sDGNRS and Vault already call BurnieCoinflip directly |
| 2 | BurnieCoin | `coinflipAmount(address)` | BurnieCoinflip.coinflipAmount | Body is `return IBurnieCoinflip(coinflipContract).coinflipAmount(player)` -- pure passthrough | Check if UI calls BurnieCoin.coinflipAmount |
| 3 | BurnieCoin | `claimableCoin()` | BurnieCoinflip.previewClaimCoinflips(msg.sender) | Body is single forwarding call with `msg.sender` hardcoded as player arg | Convenience for UI; callers could use BurnieCoinflip.previewClaimCoinflips(player) directly |
| 4 | DegenerusAdmin | `stakeGameEthToStEth(uint256)` | DegenerusGame.adminStakeEthForStEth | Body is `gameAdmin.adminStakeEthForStEth(amount)` -- single forwarding call; onlyOwner access duplicates Game's own ADMIN-only check | Admin calls Game directly; Admin contract is the ADMIN address so it has access. Removing saves 1 hop but Admin IS the authorized caller |
| 5 | DegenerusAdmin | `setLootboxRngThreshold(uint256)` | DegenerusGame.setLootboxRngThreshold | Body is `gameAdmin.setLootboxRngThreshold(newThreshold)` -- single forwarding call; onlyOwner check duplicates Game's ADMIN check | Same situation as #4: Admin IS msg.sender for Game's check |
| 6 | DegenerusStonk (DGNRS) | `previewBurn(uint256)` | StakedDegenerusStonk.previewBurn | Body is `return stonk.previewBurn(amount)` -- pure view passthrough | Check if UI calls DGNRS.previewBurn vs sDGNRS.previewBurn; DGNRS wraps sDGNRS so this is a convenience |
| 7 | StakedDegenerusStonk | `gameAdvance()` | DegenerusGame.advanceGame | Body is `game.advanceGame()` -- single forwarding call, no access control, fully permissionless | Permissionless on both sides; anyone can call Game.advanceGame() directly. sDGNRS calls this from constructor to initialize; post-deploy purpose unclear |
| 8 | StakedDegenerusStonk | `gameClaimWhalePass()` | DegenerusGame.claimWhalePass(address(0)) | Body is `game.claimWhalePass(address(0))` -- single forwarding call. address(0) resolves to msg.sender inside Game | Permissionless on both sides; anyone can call Game.claimWhalePass. Called from sDGNRS constructor |

**Not forwarding wrappers (excluded after analysis):**

- **BurnieCoin.creditFlip / creditFlipBatch**: Have `onlyFlipCreditors` access control. DegenerusAffiliate calls these via BurnieCoin (not BurnieCoinflip directly), and BurnieCoin's modifier gates access. These are access-control routing hubs, not pure wrappers.
- **BurnieCoin.creditLinkReward**: Has `onlyAdmin` guard plus emits `LinkCreditRecorded` event -- adds logic beyond forwarding.
- **BurnieCoin.coinflipAutoRebuyInfo**: Drops the 4th return value (startDay) from BurnieCoinflip -- transforms data, not a pure passthrough.
- **DegenerusAdmin.swapGameEthForStEth**: Passes `msg.value` and `msg.sender` to Game -- has value forwarding logic (`{value: msg.value}`) and parameter transformation (msg.sender as recipient). Not a trivial forward.
- **DegenerusGame delegatecall wrappers** (advanceGame, purchase, purchaseCoin, etc.): These are the Game contract's public API routing to modules via delegatecall. They execute in Game's storage context. Removing them would remove the entire public interface -- they ARE the interface, not wrappers.
- **DegenerusVault game* functions** (gameAdvance, gamePurchase, etc.): These forward to Game but add `onlyVaultOwner` access control and often transform parameters (e.g., `_combinedValue`, `address(this)` substitution). They are the Vault's gameplay proxy layer.

## Unused View/Pure Functions (No On-Chain Callers)

Functions with zero cross-contract on-chain callers found in any .sol file in contracts/.

| # | Contract | Function | On-Chain Callers Found | Rationale | Risk Notes |
|---|----------|----------|------------------------|-----------|------------|
| 1 | BurnieCoin | `claimableCoin()` | 0 | No cross-contract caller in any .sol file. Uses msg.sender internally so only useful for direct EOA calls. Also a forwarding wrapper (see #3 above). | May be used by UI for quick "how much can I claim" display |
| 2 | BurnieCoin | `totalSupply()` | 0 | No cross-contract caller. Standard ERC20 view but no other contract reads BURNIE totalSupply on-chain. | Standard ERC20 interface function; external tooling (Etherscan, DEX aggregators) expects this |
| 3 | BurnieCoin | `supplyIncUncirculated()` | 0 | No cross-contract caller. Used for dashboards only. | UI-only function |
| 4 | BurnieCoin | `vaultMintAllowance()` | 0 (Vault calls it on the coin contract directly via IVaultCoin) | Vault uses `coinToken.vaultMintAllowance()` which calls BurnieCoin directly -- this IS the on-chain caller. KEEP. | **FALSE POSITIVE**: Vault is an on-chain caller. Remove from candidates. |
| 5 | BurnieCoin | `coinflipAutoRebuyInfo(address)` | 0 | No cross-contract caller. Proxies to BurnieCoinflip with truncated return (drops startDay). | UI convenience; BurnieCoinflip.coinflipAutoRebuyInfo returns more data |
| 6 | DegenerusGame | `futurePrizePoolView()` | 0 | No cross-contract caller. Pure UI view. | UI dashboard function |
| 7 | DegenerusGame | `futurePrizePoolTotalView()` | 0 | No cross-contract caller. Identical implementation to futurePrizePoolView() -- returns same `_getFuturePrizePool()`. | Duplicate of futurePrizePoolView; one should be removed |
| 8 | DegenerusGame | `rewardPoolView()` | 0 | No cross-contract caller. Returns `_getFuturePrizePool()` -- same as futurePrizePoolView(). | Third duplicate of the same underlying value. Confusing naming. |
| 9 | DegenerusGame | `nextPrizePoolView()` | 0 | No cross-contract caller. UI-only view. | UI dashboard function |
| 10 | DegenerusGame | `currentPrizePoolView()` | 0 | No cross-contract caller. UI-only view. | UI dashboard function |
| 11 | DegenerusGame | `claimablePoolView()` | 0 | No cross-contract caller. UI-only view. | UI dashboard function |
| 12 | DegenerusGame | `prizePoolTargetView()` | 0 | No cross-contract caller. UI-only view. | UI dashboard function |
| 13 | DegenerusGame | `yieldPoolView()` | 0 | No cross-contract caller. Computed view with complex formula. | UI dashboard function; provides unique aggregated data |
| 14 | DegenerusGame | `yieldAccumulatorView()` | 0 | No cross-contract caller. Simple storage read. | UI dashboard function |
| 15 | DegenerusGame | `mintPrice()` | 3 (DegenerusQuests) | **FALSE POSITIVE**: Called on-chain by DegenerusQuests in multiple paths. KEEP. | On-chain consumer exists |
| 16 | DegenerusGame | `lastRngWord()` | 0 | No cross-contract caller. Returns `rngWordByDay[dailyIdx]`. | UI monitoring function |
| 17 | DegenerusGame | `isRngFulfilled()` | 0 | No cross-contract caller. Returns `rngWordCurrent != 0`. | UI monitoring function |
| 18 | DegenerusGame | `rngStalledForThreeDays()` | 0 | No cross-contract caller. NatSpec says "Retained for monitoring/external use." | Monitoring function; governance uses lastVrfProcessed() instead |
| 19 | DegenerusGame | `getWinnings()` | 0 | No cross-contract caller. Uses msg.sender, so EOA-only. Other contracts use claimableWinningsOf(player). | UI-only; claimableWinningsOf covers the same need |
| 20 | DegenerusGame | `hasActiveLazyPass(address)` | 0 | No cross-contract caller. _hasAnyLazyPass (private) is used internally. | UI convenience view |
| 21 | DegenerusGame | `autoRebuyEnabledFor(address)` | 0 | No cross-contract caller. Internal code reads autoRebuyState directly. | UI convenience view |
| 22 | DegenerusGame | `decimatorAutoRebuyEnabledFor(address)` | 0 | No cross-contract caller. Internal code reads decimatorAutoRebuyDisabled directly. | UI convenience view |
| 23 | DegenerusGame | `autoRebuyTakeProfitFor(address)` | 0 | No cross-contract caller. Internal code reads autoRebuyState directly. | UI convenience view |
| 24 | DegenerusGame | `afKingActivatedLevelFor(address)` | 0 | No cross-contract caller. | UI convenience view |
| 25 | DegenerusGame | `ethMintLastLevel(address)` | 0 | No cross-contract caller. Internal code reads mintPacked_ directly. | UI convenience view |
| 26 | DegenerusGame | `ethMintLevelCount(address)` | 0 | No cross-contract caller via this specific function name. Interface declares it but no external contract calls `game.ethMintLevelCount()`. | UI convenience view |
| 27 | DegenerusGame | `ethMintStreakCount(address)` | 0 | No cross-contract caller via this specific function name. | UI convenience view |
| 28 | DegenerusGame | `ethMintStats(address)` | 0 | No cross-contract caller. Batched version of the above 3. | UI convenience view; provides gas-efficient batch |
| 29 | DegenerusGame | `whalePassClaimAmount(address)` | 0 | No cross-contract caller. Simple storage read. | UI convenience view |
| 30 | DegenerusGame | `deityPassPurchasedCountFor(address)` | 0 | No cross-contract caller. | UI convenience view |
| 31 | DegenerusGame | `deityPassTotalIssuedCount()` | 0 | No cross-contract caller. Returns `deityPassOwners.length`. | UI convenience view |
| 32 | DegenerusGame | `jackpotCompressionTier()` | 0 | No cross-contract caller. Simple storage read. | UI convenience view |
| 33 | DegenerusGame | `lootboxRngIndexView()` | 0 | No cross-contract caller. | UI convenience view |
| 34 | DegenerusGame | `lootboxRngWord(uint48)` | 0 | No cross-contract caller. Players check lootbox readiness off-chain. | UI convenience view |
| 35 | DegenerusGame | `lootboxRngThresholdView()` | 0 | No cross-contract caller. | UI/admin monitoring view |
| 36 | DegenerusGame | `lootboxRngMinLinkBalanceView()` | 0 | No cross-contract caller. | UI/admin monitoring view |
| 37 | DegenerusGame | `lootboxStatus(address,uint48)` | 0 | No cross-contract caller. | UI convenience view |
| 38 | DegenerusGame | `degeneretteBetInfo(address,uint64)` | 0 | No cross-contract caller. Returns raw packed bet data. | UI convenience view |
| 39 | DegenerusGame | `lootboxPresaleActiveFlag()` | 1 (DegenerusAffiliate) | **On-chain caller exists**: DegenerusAffiliate reads this. KEEP. | On-chain consumer |
| 40 | DegenerusGame | `ticketsOwedView(uint24,address)` | 0 | No cross-contract caller. | UI convenience view |
| 41 | DegenerusGame | `isFinalSwept()` | 0 | No cross-contract caller. Internal code reads `finalSwept` directly. | UI convenience view |
| 42 | DegenerusGame | `gameOverTimestamp()` | 1 (DegenerusStonk) | **On-chain caller exists**: DGNRS.yearSweep() reads this. KEEP. | On-chain consumer |
| 43 | DegenerusGame | `decClaimable(address,uint24)` | 0 | No cross-contract caller. Complex view with storage reads. | UI convenience view; provides useful aggregated data |
| 44 | DegenerusGame | `decWindowOpenFlag()` | 1 (DegenerusQuests) | **On-chain caller exists**: DegenerusQuests reads this. KEEP. | On-chain consumer |
| 45 | DegenerusGame | `jackpotPhase()` | 0 (purchaseInfo bundles it) | No direct cross-contract caller for `jackpotPhase()` standalone; BurnieCoinflip uses `purchaseInfo()` which bundles it. | UI convenience view; purchaseInfo already exposes this |
| 46 | BurnieCoinflip | `getCoinflipDayResult(uint48)` | 1 (StakedDegenerusStonk) | **On-chain caller exists**: sDGNRS.claimRedemption() reads this. KEEP. | On-chain consumer |
| 47 | DegenerusJackpots | `getLastBafResolvedDay()` | 1 (BurnieCoinflip) | **On-chain caller exists**. KEEP. | On-chain consumer |
| 48 | DegenerusAffiliate | `defaultCode(address)` | 0 | Pure helper for frontend link generation. No on-chain caller. | UI utility; pure function, zero gas cost to keep |
| 49 | DegenerusAffiliate | `affiliateTop(uint24)` | 1 (EndgameModule) | **On-chain caller exists**. KEEP. | On-chain consumer |
| 50 | DegenerusQuests | `getActiveQuests()` | 0 | No cross-contract caller. View helper for frontends. | UI view function |
| 51 | DegenerusQuests | `getPlayerQuestView(address)` | 0 | No cross-contract caller. Comprehensive UI view. | UI view function; provides unique aggregated data |
| 52 | GNRUS | `getProposal(uint48)` | 0 | No cross-contract caller. View helper for governance UI. | UI governance view |
| 53 | GNRUS | `getLevelProposals(uint24)` | 0 | No cross-contract caller. View helper for governance UI. | UI governance view |
| 54 | DegenerusAdmin | `canExecute(uint256)` | 0 | No cross-contract caller. View for governance UI. | UI governance view |
| 55 | DegenerusAdmin | `canExecuteFeedSwap(uint256)` | 0 | No cross-contract caller. View for feed governance UI. | UI governance view |
| 56 | DegenerusAdmin | `threshold(uint256)` | 0 (called internally by vote()) | Used by vote() on the same contract (internal), not cross-contract. Public for UI. | UI governance view; also used internally via `threshold(proposalId)` |
| 57 | DegenerusAdmin | `feedThreshold(uint256)` | 0 (called internally by voteFeedSwap()) | Used by voteFeedSwap() on the same contract. Public for UI. | UI governance view; also used internally |
| 58 | StakedDegenerusStonk | `hasPendingRedemptions()` | 2 (AdvanceModule) | **On-chain caller exists**. KEEP. | On-chain consumer |
| 59 | StakedDegenerusStonk | `burnieReserve()` | 0 | No cross-contract caller. View showing net BURNIE backing. | UI view function |
| 60 | StakedDegenerusStonk | `previewBurn(uint256)` | 1 (DegenerusStonk) | **On-chain caller exists**: DGNRS.previewBurn forwards to this. KEEP. | On-chain consumer (DGNRS) |
| 61 | WrappedWrappedXRP | `supplyIncUncirculated()` | 0 | No cross-contract caller. Dashboard view. | UI view function |
| 62 | WrappedWrappedXRP | `vaultMintAllowance()` | 1 (DegenerusVault) | **On-chain caller exists**: Vault constructor reads this. KEEP. | On-chain consumer |
| 63 | DegenerusDeityPass | `renderColors()` | 0 | No cross-contract caller. View for reading active render colors. | UI view function |
| 64 | Icons32Data | `data(uint256)` | 1 (DegenerusDeityPass) | **On-chain caller exists**. KEEP. | On-chain consumer |
| 65 | Icons32Data | `symbol(uint256,uint8)` | 1 (DegenerusDeityPass) | **On-chain caller exists**. KEEP. | On-chain consumer |

**After removing false positives (functions with on-chain callers), the actual unused view/pure candidates are:**

| # | Contract | Function | Rationale | Risk Notes |
|---|----------|----------|-----------|------------|
| 1 | BurnieCoin | `claimableCoin()` | Zero on-chain callers; also a forwarding wrapper to BurnieCoinflip | UI convenience |
| 2 | BurnieCoin | `previewClaimCoinflips(address)` | Zero on-chain callers; pure passthrough to BurnieCoinflip | UI convenience; sDGNRS/Vault call BurnieCoinflip directly |
| 3 | BurnieCoin | `coinflipAmount(address)` | Zero on-chain callers; pure passthrough to BurnieCoinflip | UI convenience |
| 4 | BurnieCoin | `coinflipAutoRebuyInfo(address)` | Zero on-chain callers; truncated passthrough to BurnieCoinflip | UI convenience; BurnieCoinflip has full version |
| 5 | BurnieCoin | `totalSupply()` | Zero on-chain callers | Standard ERC20; Etherscan/tooling expects it |
| 6 | BurnieCoin | `supplyIncUncirculated()` | Zero on-chain callers | Dashboard function |
| 7 | DegenerusGame | `futurePrizePoolView()` | Zero on-chain callers | UI dashboard |
| 8 | DegenerusGame | `futurePrizePoolTotalView()` | Zero on-chain callers; DUPLICATE of futurePrizePoolView | UI dashboard; identical impl |
| 9 | DegenerusGame | `rewardPoolView()` | Zero on-chain callers; DUPLICATE of futurePrizePoolView | UI dashboard; identical impl, confusing name |
| 10 | DegenerusGame | `nextPrizePoolView()` | Zero on-chain callers | UI dashboard |
| 11 | DegenerusGame | `currentPrizePoolView()` | Zero on-chain callers | UI dashboard |
| 12 | DegenerusGame | `claimablePoolView()` | Zero on-chain callers | UI dashboard |
| 13 | DegenerusGame | `prizePoolTargetView()` | Zero on-chain callers | UI dashboard |
| 14 | DegenerusGame | `yieldPoolView()` | Zero on-chain callers | UI dashboard; unique computed data |
| 15 | DegenerusGame | `yieldAccumulatorView()` | Zero on-chain callers | UI dashboard |
| 16 | DegenerusGame | `lastRngWord()` | Zero on-chain callers | UI monitoring |
| 17 | DegenerusGame | `isRngFulfilled()` | Zero on-chain callers | UI monitoring |
| 18 | DegenerusGame | `rngStalledForThreeDays()` | Zero on-chain callers; explicitly "retained for monitoring" | UI monitoring |
| 19 | DegenerusGame | `getWinnings()` | Zero on-chain callers; msg.sender-only; claimableWinningsOf covers this | UI convenience |
| 20 | DegenerusGame | `hasActiveLazyPass(address)` | Zero on-chain callers | UI convenience |
| 21 | DegenerusGame | `autoRebuyEnabledFor(address)` | Zero on-chain callers | UI convenience |
| 22 | DegenerusGame | `decimatorAutoRebuyEnabledFor(address)` | Zero on-chain callers | UI convenience |
| 23 | DegenerusGame | `autoRebuyTakeProfitFor(address)` | Zero on-chain callers | UI convenience |
| 24 | DegenerusGame | `afKingActivatedLevelFor(address)` | Zero on-chain callers | UI convenience |
| 25 | DegenerusGame | `ethMintLastLevel(address)` | Zero on-chain callers | UI convenience |
| 26 | DegenerusGame | `ethMintLevelCount(address)` | Zero on-chain callers | UI convenience |
| 27 | DegenerusGame | `ethMintStreakCount(address)` | Zero on-chain callers | UI convenience |
| 28 | DegenerusGame | `ethMintStats(address)` | Zero on-chain callers; batched version of above 3 | UI convenience |
| 29 | DegenerusGame | `whalePassClaimAmount(address)` | Zero on-chain callers | UI convenience |
| 30 | DegenerusGame | `deityPassPurchasedCountFor(address)` | Zero on-chain callers | UI convenience |
| 31 | DegenerusGame | `deityPassTotalIssuedCount()` | Zero on-chain callers | UI convenience |
| 32 | DegenerusGame | `jackpotCompressionTier()` | Zero on-chain callers | UI convenience |
| 33 | DegenerusGame | `jackpotPhase()` | Zero direct on-chain callers; purchaseInfo bundles this | UI convenience; redundant with purchaseInfo |
| 34 | DegenerusGame | `lootboxRngIndexView()` | Zero on-chain callers | UI convenience |
| 35 | DegenerusGame | `lootboxRngWord(uint48)` | Zero on-chain callers | UI convenience |
| 36 | DegenerusGame | `lootboxRngThresholdView()` | Zero on-chain callers | UI/admin monitoring |
| 37 | DegenerusGame | `lootboxRngMinLinkBalanceView()` | Zero on-chain callers | UI/admin monitoring |
| 38 | DegenerusGame | `lootboxStatus(address,uint48)` | Zero on-chain callers | UI convenience |
| 39 | DegenerusGame | `degeneretteBetInfo(address,uint64)` | Zero on-chain callers | UI convenience |
| 40 | DegenerusGame | `ticketsOwedView(uint24,address)` | Zero on-chain callers | UI convenience |
| 41 | DegenerusGame | `isFinalSwept()` | Zero on-chain callers | UI convenience |
| 42 | DegenerusGame | `decClaimable(address,uint24)` | Zero on-chain callers | UI convenience; unique computed view |
| 43 | DegenerusAffiliate | `defaultCode(address)` | Zero on-chain callers; pure helper | UI link generation utility |
| 44 | DegenerusQuests | `getActiveQuests()` | Zero on-chain callers | UI view function |
| 45 | DegenerusQuests | `getPlayerQuestView(address)` | Zero on-chain callers | UI view function |
| 46 | GNRUS | `getProposal(uint48)` | Zero on-chain callers | UI governance view |
| 47 | GNRUS | `getLevelProposals(uint24)` | Zero on-chain callers | UI governance view |
| 48 | DegenerusAdmin | `canExecute(uint256)` | Zero cross-contract callers | UI governance view |
| 49 | DegenerusAdmin | `canExecuteFeedSwap(uint256)` | Zero cross-contract callers | UI governance view |
| 50 | StakedDegenerusStonk | `burnieReserve()` | Zero on-chain callers | UI view |
| 51 | WrappedWrappedXRP | `supplyIncUncirculated()` | Zero on-chain callers | Dashboard view |
| 52 | DegenerusDeityPass | `renderColors()` | Zero on-chain callers | UI view |
| 53 | StakedDegenerusStonk | `gameAdvance()` | Zero on-chain callers post-constructor; permissionless forwarding wrapper | Also in forwarding wrappers table |
| 54 | StakedDegenerusStonk | `gameClaimWhalePass()` | Zero on-chain callers post-constructor; permissionless forwarding wrapper | Also in forwarding wrappers table |

## Functions Examined But Not Candidates

Every production contract was scanned. Below documents why remaining functions are NOT candidates, grouped by contract.

### BurnieCoin (30 external/public incl interface declarations)
- **ERC20 standard**: `approve`, `transfer` -- standard interface with real logic (coinflip shortfall auto-claim on transfer)
- **Game integration**: `burnForCoinflip`, `mintForCoinflip`, `mintForGame` -- access-controlled mutation endpoints with real burn/mint logic
- **Flip crediting**: `creditCoin`, `creditFlip`, `creditFlipBatch`, `creditLinkReward` -- access-controlled routing hubs with `onlyFlipCreditors`/`onlyAdmin` guards plus event emission
- **Quest integration**: `rollDailyQuest`, `notifyQuestMint`, `notifyQuestLootBox`, `notifyQuestDegenerette`, `affiliateQuestReward` -- multi-step orchestration with events, quest processing, and reward application
- **Decimator**: `decimatorBurn`, `terminalDecimatorBurn` -- complex multi-step functions with burns, quests, boons, and bucket calculations
- **Vault**: `vaultEscrow`, `vaultMintTo` -- access-controlled with real storage mutations
- **ERC20 constants**: `decimals` (constant 18) -- standard ERC20, zero gas
- **balanceOfWithClaimable**: Adds vault allowance + coinflip claimable on top of balance -- unique aggregation logic

### BurnieCoinflip (8 external/public)
- **Core coinflip**: `settleFlipModeChange`, `depositCoinflip` -- complex multi-step functions with access control, burns, quest processing
- **Claim functions**: `claimCoinflipsFromBurnie`, `consumeCoinflipsForBurn`, `claimCoinflipsForRedemption` -- access-controlled with real claim logic
- **Views**: `previewClaimCoinflips`, `coinflipAmount` -- these are the canonical endpoints; BurnieCoin forwards to them

### DegenerusAdmin (25 external/public incl interface declarations)
- **Governance**: `propose`, `vote`, `voteFeedSwap`, `proposeFeedSwap`, `shutdownVrf` -- complex multi-step governance functions
- **VRF management**: `onTokenTransfer` -- ERC-677 callback with reward calculations
- **Views**: `threshold`, `feedThreshold` -- public because used internally AND by UI. Could be external but they serve dual purpose.
- **swapGameEthForStEth**: Passes msg.value + msg.sender transformation -- not trivially bypassable

### DegenerusAffiliate (12 external/public incl interface declarations)
- **Core functions**: `createAffiliateCode`, `referPlayer`, `payAffiliate` -- all have real logic
- **Views with on-chain callers**: `affiliateTop` (EndgameModule), `affiliateScore` (Game), `totalAffiliateScore` (Game), `affiliateBonusPointsBest` (Game, modules, DegeneretteModule), `getReferrer` (WhaleModule)

### DegenerusDeityPass (19 external/public)
- **ERC721 standard**: `name`, `symbol`, `balanceOf`, `ownerOf`, `getApproved`, `isApprovedForAll`, `supportsInterface` -- standard ERC721 interface required by wallets/marketplaces
- **Soulbound enforcement**: `approve`, `setApprovalForAll`, `transferFrom`, `safeTransferFrom` (x2) -- all revert Soulbound(), required by ERC721 spec
- **Admin**: `setRenderer`, `setRenderColors` -- real mutation logic with events
- **Token rendering**: `tokenURI` -- complex on-chain SVG rendering, required by ERC721Metadata
- **Game mint**: `mint` -- access-controlled, real state mutation

### DegenerusGame (53 external/public)
- **Core gameplay**: `advanceGame`, `purchase`, `purchaseCoin`, `purchaseWhaleBundle`, `purchaseLazyPass`, `purchaseDeityPass`, `purchaseBurnieLootbox`, `openLootBox`, `openBurnieLootBox`, `placeDegeneretteBet`, `resolveDegeneretteBets`, `issueDeityBoon` -- primary interface; delegatecall to modules
- **Claims**: `claimWinnings`, `claimWinningsStethFirst`, `claimAffiliateDgnrs`, `claimDecimatorJackpot`, `claimWhalePass` -- pull-pattern claim functions with real logic
- **Game-only self-calls**: `recordMint`, `recordMintQuestStreak`, `payCoinflipBountyDgnrs`, `consumeDecClaim`, `runTerminalDecimatorJackpot`, `runTerminalJackpot`, `consumePurchaseBoost` -- used by delegatecall modules
- **Access-controlled hooks**: `consumeCoinflipBoon`, `consumeDecimatorBoon`, `deactivateAfKingFromCoin`, `syncAfKingLazyPassFromCoin`, `resolveRedemptionLootbox` -- called by other contracts with real logic
- **Settings**: `setOperatorApproval`, `setAutoRebuy`, `setDecimatorAutoRebuy`, `setAutoRebuyTakeProfit`, `setAfKingMode`, `setLootboxRngThreshold` -- real state mutations
- **Admin/VRF**: `wireVrf`, `updateVrfCoordinatorAndSub`, `adminSwapEthForStEth`, `adminStakeEthForStEth`, `requestLootboxRng`, `reverseFlip`, `rawFulfillRandomWords` -- critical protocol functions
- **Views with on-chain callers**: `rngLocked` (6 contracts), `gameOver` (5 contracts), `level` (4 contracts), `isOperatorApproved` (3 contracts), `currentDayView` (3 contracts), `decWindow` (BurnieCoin), `terminalDecWindow` (BurnieCoin), `mintPrice` (DegenerusQuests), `rngWordForDay` (sDGNRS), `lastVrfProcessed` (DegenerusAdmin), `claimableWinningsOf` (4 contracts), `playerActivityScore` (7 callers), `deityPassCountFor` (BurnieCoinflip), `afKingModeFor` (BurnieCoinflip), `deityBoonData` (DeityBoonViewer), `lootboxPresaleActiveFlag` (DegenerusAffiliate), `gameOverTimestamp` (DegenerusStonk), `decWindowOpenFlag` (DegenerusQuests), `purchaseInfo` (DegenerusAdmin, BurnieCoinflip x2)

### DegenerusJackpots (3 external/public)
- **Core**: `recordBafFlip` -- on-chain mutation called by COIN/COINFLIP
- **Resolution**: internal, called by game modules via game contract
- **Views with on-chain callers**: `getLastBafResolvedDay` (BurnieCoinflip)

### DegenerusQuests (3 external/public)
- **Core**: `rollDailyQuest`, `awardQuestStreakBonus` -- access-controlled mutations
- **Views with on-chain callers**: `playerQuestStates` (Game, DegeneretteModule)

### DegenerusStonk / DGNRS (19 external/public incl interface declarations)
- **ERC20 standard**: `transfer`, `transferFrom`, `approve` -- standard with real logic (anti-self-transfer)
- **Core functions**: `unwrapTo`, `claimVested`, `burn`, `burnForSdgnrs`, `yearSweep` -- all have real logic
- **receive()**: Accepts ETH from sDGNRS

### DegenerusVault (56 external/public incl interface declarations + DegenerusVaultShare)
- **Share token (DegenerusVaultShare)**: Standard ERC20 (approve, transfer, transferFrom, vaultMint, vaultBurn) -- separate contract
- **Vault core**: `deposit`, `isVaultOwner`, `burnCoin`, `burnEth` -- real logic
- **Vault gameplay proxy** (game*, coin*, sdgnrs*, wwxrp*, jackpots*): All add onlyVaultOwner access control + parameter transformation (address(this) substitution, ETH value combination, input validation). NOT pure wrappers.
- **Views**: `previewBurnForCoinOut`, `previewBurnForEthOut`, `previewCoin`, `previewEth` -- unique computed views for vault share valuation

### DeityBoonViewer (1 external)
- `deityBoonSlots` -- reads Game.deityBoonData and computes boon types. Unique logic, not a wrapper.

### GNRUS (17 external/public incl interface declarations)
- **Soulbound**: `transfer`, `transferFrom`, `approve` -- revert TransferDisabled
- **Core**: `burn`, `burnAtGameOver`, `propose`, `vote`, `pickCharity` -- all have real logic
- **receive()**: Accepts ETH

### Icons32Data (6 external/public)
- **Admin**: `setPaths`, `setSymbols`, `finalize` -- access-controlled setup functions
- **Views with on-chain callers**: `data` (DegenerusDeityPass), `symbol` (DegenerusDeityPass)

### StakedDegenerusStonk / sDGNRS (33 external/public incl interface declarations)
- **Core**: `wrapperTransferTo`, `depositSteth`, `transferFromPool`, `transferBetweenPools`, `burnAtGameOver`, `burn`, `burnWrapped`, `resolveRedemptionPeriod`, `claimRedemption` -- all have real logic
- **Views with on-chain callers**: `poolBalance` (9 callers), `votingSupply` (DegenerusAdmin, GNRUS), `hasPendingRedemptions` (AdvanceModule), `previewBurn` (DegenerusStonk)
- **receive()**: Accepts ETH from game

### WrappedWrappedXRP / WWXRP (11 external/public)
- **ERC20 standard**: `approve`, `transfer`, `transferFrom` -- standard with real logic
- **Core**: `unwrap`, `donate`, `mintPrize`, `vaultMintTo`, `burnForGame` -- all have real logic
- **Views with on-chain callers**: `vaultMintAllowance` (DegenerusVault)

### Delegatecall Modules (AdvanceModule, BoonModule, DecimatorModule, DegeneretteModule, EndgameModule, GameOverModule, JackpotModule, LootboxModule, MintModule, WhaleModule)
- All module functions are called exclusively via delegatecall from DegenerusGame. They execute in Game's storage context. Their external visibility is required for the delegatecall ABI encoding. None are candidates for removal -- removing them would remove game functionality.
- **MintStreakUtils, PayoutUtils**: Library-style modules with zero external functions. No candidates.

### DegenerusTraitUtils
- Pure library with internal functions only. No external/public functions. No candidates.

## Methodology Notes

### Forwarding Wrapper Detection
1. Read every external/public non-view function body across all 25 production contracts
2. A function qualifies as "forwarding wrapper" only if its ENTIRE body is a single call to another contract with identical or trivially mapped parameters AND it adds no access control, events, or state changes beyond the forwarded call
3. DegenerusGame delegatecall wrappers were excluded: they ARE the public API routing to modules that execute in Game's storage context. Removing them would remove the entire public interface.
4. DegenerusVault game* functions were excluded: they all add onlyVaultOwner access control and/or parameter transformation (address(this) substitution, _combinedValue ETH combination)
5. BurnieCoin.creditFlip/creditFlipBatch were excluded: they add onlyFlipCreditors access control and are the designated entry point for multiple callers (Affiliate, Game)

### On-Chain Caller Search
1. For every view/pure function, searched all .sol files in contracts/ (including modules/, interfaces/, libraries/, storage/) using `grep -rn` for patterns:
   - `contractVarName.functionName(` (e.g., `game.rngLocked()`, `dgnrs.poolBalance(`)
   - `InterfaceName(addr).functionName(` patterns
   - Both direct calls and interface-cast calls
2. A function was marked as "unused" candidate only if ZERO cross-contract call sites were found
3. Functions called internally within the same contract via `this.functionName()` (self-call pattern in delegatecall modules) were counted as on-chain callers
4. Interface declarations were excluded from caller counts
5. Standard ERC20/ERC721 interface functions (even with zero on-chain callers) were noted but flagged as required by external tooling

### Ambiguous Cases
- **DegenerusAdmin.threshold/feedThreshold**: Public functions called internally by `vote()`/`voteFeedSwap()` and externally by UI. Classified as "not candidates" because they serve dual purpose (internal + external).
- **StakedDegenerusStonk.gameAdvance/gameClaimWhalePass**: Called only from the constructor during deployment. Post-deploy, they are permissionless forwarding wrappers. Listed in both forwarding wrapper and unused view tables since they overlap both categories.
- **BurnieCoin.totalSupply**: Zero on-chain callers but standard ERC20 interface. Listed as candidate with risk note about external tooling expectations.
- **Game view duplicates** (futurePrizePoolView / futurePrizePoolTotalView / rewardPoolView): Three functions returning the identical `_getFuturePrizePool()` value. Strong removal candidates -- at minimum reduce to one function.
