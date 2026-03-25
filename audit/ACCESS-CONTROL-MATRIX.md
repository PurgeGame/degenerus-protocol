# Degenerus Protocol -- Access Control Matrix

**Audit Date:** 2026-03-25
**Source:** v5.0 Ultimate Adversarial Audit, 16 unit phases (103-118)
**Scope:** All 29 protocol contracts, every external/public state-changing function

---

## Summary

| Guard Type | Count | Pattern |
|-----------|-------|---------|
| Compile-time constant (ContractAddresses.*) | 45+ | Immutable addresses, no admin override, no re-pointing |
| DGVE majority owner (vault share voting) | 5 | Requires >50.1% of DGVE supply |
| Permissionless (player action) | 30+ | Purchases, claims, burns, standard ERC20 |
| Conditional (gameOver, rngLocked, etc.) | 8 | State-dependent gates |

**Key property:** ALL access control gates use compile-time constant addresses set via `ContractAddresses.*`. Zero configurable admin addresses. Zero proxy upgrade paths. Zero address re-pointing mechanisms.

---

## 1. DegenerusGame (Router)

All game module functions are dispatched via delegatecall from the router. Access control is enforced at the router level.

| Function | Visibility | Guard | Guard Type |
|----------|-----------|-------|------------|
| `receive()` | external | None | Permissionless (accepts ETH) |
| `advanceGame()` | external | None | Permissionless (public good) |
| `purchaseFor(address, uint8)` | external payable | None | Permissionless (requires msg.value) |
| `purchaseWhaleBundle(address, uint8, uint8)` | external payable | None | Permissionless (requires msg.value) |
| `purchaseLazyPass(address)` | external payable | None | Permissionless (requires msg.value) |
| `purchaseDeityPass(address, uint8)` | external payable | None | Permissionless (requires msg.value) |
| `placeFullTicketBets(...)` | external payable | None | Permissionless (requires funds) |
| `claimWinnings(address)` | external | None | Permissionless (claims own balance) |
| `claimWinningsStethFirst(address)` | external | None | Permissionless (claims own balance) |
| `claimDecimatorJackpot(uint24, uint8)` | external | None | Permissionless (claims own) |
| `claimTerminalDecimatorJackpot(uint24, uint8)` | external | None | Permissionless (claims own) |
| `claimWhalePass(uint24)` | external | None | Permissionless (claims own) |
| `reverseFlip()` | external | None | Permissionless (requires active ticket) |
| `requestLootboxRng()` | external | None | Permissionless (requires pending lootbox) |
| `resolveBets()` | external | None | Permissionless (resolves own bets) |
| `resolveRedemptionLootbox(address, uint128, uint64)` | external | sDGNRS only | `msg.sender == ContractAddresses.SDGNRS` |
| `operatorClaimWinnings(address)` | external | Approved operator | `operatorApprovals[player][msg.sender]` |
| `setAutoRebuy(bool)` | external | None | Permissionless (sets own config) |
| `setTakeProfit(uint8)` | external | None | Permissionless (sets own config) |
| `setOperatorApproval(address, bool)` | external | None | Permissionless (sets own approvals) |

---

## 2. Game Modules (10 modules, all delegatecalled)

Game modules do not have their own access control. They execute in DegenerusGame's storage context via delegatecall. Access control is enforced entirely at the Game router dispatch layer. The modules are:

| Module | Contract | Functions |
|--------|----------|-----------|
| AdvanceModule | DegenerusGameAdvanceModule.sol | Day advancement, VRF, ticket processing |
| MintModule | DegenerusGameMintModule.sol | Purchase flow, streak utils |
| WhaleModule | DegenerusGameWhaleModule.sol | Whale bundle, lazy pass, deity pass |
| JackpotModule | DegenerusGameJackpotModule.sol | Daily jackpot, prize pool management |
| DecimatorModule | DegenerusGameDecimatorModule.sol | Decimator burn/claim/jackpot |
| EndgameModule | DegenerusGameEndgameModule.sol | Level-end reward resolution |
| GameOverModule | DegenerusGameGameOverModule.sol | Terminal drain and refunds |
| DegeneretteModule | DegenerusGameDegeneretteModule.sol | Betting system |
| LootboxModule | DegenerusGameLootboxModule.sol | Lootbox resolution |
| BoonModule | DegenerusGameBoonModule.sol | Boon application and expiry |

---

## 3. BurnieCoin

| Function | Visibility | Guard | Guard Type |
|----------|-----------|-------|------------|
| `transfer(address, uint256)` | external | None | Permissionless (standard ERC20) |
| `approve(address, uint256)` | external | None | Permissionless (standard ERC20) |
| `transferFrom(address, address, uint256)` | external | None | Permissionless (standard ERC20, game bypasses allowance) |
| `burnForCoinflip(address, uint128)` | external | COINFLIP only | `msg.sender != coinflipContract` revert |
| `mintForCoinflip(address, uint128)` | external | COINFLIP only | `msg.sender != coinflipContract` revert |
| `mintForGame(address, uint128)` | external | GAME only | `msg.sender != GAME` revert |
| `creditCoin(address, uint128)` | external | GAME or COINFLIP | `onlyFlipCreditors` modifier |
| `creditFlip(address, uint128)` | external | GAME or COINFLIP | `onlyFlipCreditors` modifier |
| `creditFlipBatch(address[], uint128[])` | external | GAME or COINFLIP | `onlyFlipCreditors` modifier |
| `creditLinkReward(address, uint128)` | external | ADMIN only | `onlyAdmin` modifier |
| `vaultEscrow(address, uint128)` | external | VAULT only | `msg.sender != VAULT` revert |
| `vaultMintTo(address, uint256)` | external | VAULT only | `onlyVault` modifier |
| `decimatorBurn(address, uint128)` | external | GAME only | `msg.sender != GAME` revert |
| `terminalDecimatorBurn(address, uint128)` | external | GAME only | `msg.sender != GAME` revert |
| `notifyQuestLootBox(address)` | external | GAME only | Game notification |
| `notifyQuestDegenerette(address)` | external | GAME only | Game notification |
| `affiliateQuestReward(address, uint128)` | external | AFFILIATE only | `onlyAffiliate` modifier |

---

## 4. BurnieCoinflip

| Function | Visibility | Guard | Guard Type |
|----------|-----------|-------|------------|
| `depositCoinflip(uint128)` | external | None | Permissionless (via BURNIE transfer hook) |
| `settleFlipModeChange(address, bool)` | external | GAME only | `onlyDegenerusGameContract` modifier |
| `setCoinflipAutoRebuy(address, bool)` | external | GAME only | `onlyDegenerusGameContract` modifier |
| `processCoinflipPayouts(uint256, uint24)` | external | GAME only | `onlyDegenerusGameContract` modifier |
| `claimCoinflips(address)` | external | None | Permissionless (claims own balance) |
| `claimCoinflipsFromBurnie(address)` | external | COIN only | `msg.sender == coinContract` |
| `claimCoinflipsForRedemption(address)` | external | sDGNRS only | `msg.sender == SDGNRS` |

---

## 5. StakedDegenerusStonk (sDGNRS)

| Function | Visibility | Guard | Guard Type |
|----------|-----------|-------|------------|
| `depositSteth(uint256)` | external | GAME only | `onlyGame` modifier |
| `gameDeposit(uint256)` | external | GAME only | `onlyGame` modifier |
| `deposit(uint256)` | external | GAME only | `onlyGame` modifier |
| `transferFromPool(uint8, address, uint256)` | external | GAME only | `onlyGame` modifier |
| `transferBetweenPools(uint8, uint8, uint256)` | external | GAME only | `onlyGame` modifier |
| `burnRemainingPools()` | external | GAME only | `onlyGame` modifier |
| `resolveRedemptionPeriod(uint256, uint256)` | external | GAME only | `onlyGame` modifier |
| `wrapperTransferTo(address, uint256)` | external | DGNRS only | `msg.sender == DGNRS` |
| `submitGamblingClaim(uint256)` | external | None | Permissionless (burns own tokens) |
| `claimRedemption()` | external | None | Permissionless (claims own balance) |
| `burn(uint256)` | external | None | Permissionless (burns own tokens) |
| `burnWrapped(uint256)` | external | None | Permissionless (burns own wrapped) |
| `gameAdvance()` | external | None | Permissionless (proxy to Game.advanceGame) |
| `gameClaimWhalePass(uint24)` | external | None | Permissionless (proxy to Game) |

---

## 6. DegenerusStonk (DGNRS)

| Function | Visibility | Guard | Guard Type |
|----------|-----------|-------|------------|
| `transfer(address, uint256)` | external | None | Standard ERC20 |
| `approve(address, uint256)` | external | None | Standard ERC20 |
| `transferFrom(address, address, uint256)` | external | None | Standard ERC20 |
| `burnForSdgnrs(address, uint256)` | external | sDGNRS only | `msg.sender == SDGNRS` |
| `burn(uint256)` | external | Game-over only | `gameOver()` check (permissionless after game-over) |
| `unwrapTo(address, uint256)` | external | CREATOR only | `msg.sender == CREATOR` |

---

## 7. DegenerusVault

| Function | Visibility | Guard | Guard Type |
|----------|-----------|-------|------------|
| `deposit()` | external payable | GAME only | `onlyGame` modifier |
| `burnCoin(uint256)` | external | Approved shareholders | `_requireApproved` (operator approval via Game) |
| `burnEth(uint256)` | external | Approved shareholders | `_requireApproved` |
| `setLinkPriceFeed(address)` | external | DGVE majority owner | `onlyVaultOwner` (>50.1% DGVE supply) |
| `swapEthForStEth(uint256)` | external | DGVE majority owner | `onlyVaultOwner` |
| `stakeEthToStEth(uint256)` | external | DGVE majority owner | `onlyVaultOwner` |
| `setLootboxRngThreshold(uint256)` | external | DGVE majority owner | `onlyVaultOwner` |
| `gameSetAutoRebuy(bool)` | external | Self (vault) | Internal proxy to Game |
| Proxy functions (purchase, advance, etc.) | external | None | Permissionless (forward to Game) |

---

## 8. DegenerusVaultShare (DGVB/DGVE)

| Function | Visibility | Guard | Guard Type |
|----------|-----------|-------|------------|
| `transfer(address, uint256)` | external | None | Standard ERC20 (soulbound for DGVB) |
| `approve(address, uint256)` | external | None | Standard ERC20 |
| `transferFrom(address, address, uint256)` | external | None | Standard ERC20 |
| `mint(address, uint256)` | external | VAULT only | `onlyVault` modifier |
| `burn(address, uint256)` | external | VAULT only | `onlyVault` modifier |

---

## 9. WrappedWrappedXRP (WWXRP)

| Function | Visibility | Guard | Guard Type |
|----------|-----------|-------|------------|
| `mintPrize(address, uint256)` | external | Authorized minters | `onlyMinter` (GAME, COIN, COINFLIP, VAULT -- 4 compile-time constants) |
| `wrap(uint256)` | external | None | Permissionless (requires wXRP balance) |
| `unwrap(uint256)` | external | None | Permissionless (first-come-first-served against reserves) |
| `donate(uint256)` | external | None | Permissionless (requires wXRP balance) |
| `burn(uint256)` | external | None | Permissionless (burns own tokens) |
| `transfer(address, uint256)` | external | None | Standard ERC20 |
| `approve(address, uint256)` | external | None | Standard ERC20 |
| `transferFrom(address, address, uint256)` | external | None | Standard ERC20 |

---

## 10. DegenerusAdmin

| Function | Visibility | Guard | Guard Type |
|----------|-----------|-------|------------|
| `setLinkEthPriceFeed(address)` | external | DGVE majority owner | `onlyOwner` + broken feed gate |
| `swapGameEthForStEth(uint256)` | external | DGVE majority owner | `onlyOwner` |
| `stakeGameEthToStEth(uint256)` | external | DGVE majority owner | `onlyOwner` |
| `setLootboxRngThreshold(uint256)` | external | DGVE majority owner | `onlyOwner` |
| `propose(address)` | external | DGVE owner (20h stall) OR 0.5% sDGNRS (7d stall) | Dual-path with stall requirement |
| `vote(uint256, bool)` | external | Any sDGNRS holder | `sDGNRS.balanceOf > 0` + stall check |
| `shutdownVrf()` | external | GAME only | `msg.sender == GAME` |
| `onTokenTransfer(address, uint256, bytes)` | external | LINK token only | `msg.sender == LINK_TOKEN` (ERC-677) |

---

## 11. DegenerusDeityPass (ERC721)

| Function | Visibility | Guard | Guard Type |
|----------|-----------|-------|------------|
| `mint(address, uint256)` | external | GAME only | `onlyGame` modifier |
| `transferFrom(address, address, uint256)` | external | None | Standard ERC721 |
| `safeTransferFrom(address, address, uint256)` | external | None | Standard ERC721 |
| `approve(address, uint256)` | external | None | Standard ERC721 |
| `setApprovalForAll(address, bool)` | external | None | Standard ERC721 |

---

## 12. DegenerusAffiliate

| Function | Visibility | Guard | Guard Type |
|----------|-----------|-------|------------|
| `createAffiliateCode(bytes32)` | external | None | Permissionless |
| `referPlayer(bytes32)` | external | None | Permissionless (self-referral blocked) |
| `payAffiliate(address, bytes32, uint128)` | external | COIN or GAME | `msg.sender != COIN && msg.sender != GAME` revert |

---

## 13. DegenerusQuests

| Function | Visibility | Guard | Guard Type |
|----------|-----------|-------|------------|
| `rollDailyQuest(address, uint256)` | external | COIN or COINFLIP | `onlyCoin` modifier |
| `awardQuestStreakBonus(address)` | external | GAME only | `onlyGame` modifier |
| `handleMint(address, uint128, uint24)` | external | COIN or COINFLIP | `onlyCoin` modifier |
| `handleFlip(address, uint128)` | external | COIN or COINFLIP | `onlyCoin` modifier |
| `handleDecimator(address, uint128)` | external | COIN or COINFLIP | `onlyCoin` modifier |
| `handleAffiliate(address)` | external | COIN or COINFLIP | `onlyCoin` modifier |
| `handleLootBox(address)` | external | COIN or COINFLIP | `onlyCoin` modifier |
| `handleDegenerette(address)` | external | COIN or COINFLIP | `onlyCoin` modifier |

---

## 14. DegenerusJackpots

| Function | Visibility | Guard | Guard Type |
|----------|-----------|-------|------------|
| `recordBafFlip(address, uint128)` | external | COIN or COINFLIP | `onlyCoin` modifier |
| `runBafJackpot(uint128, uint24, uint256)` | external | GAME only | `onlyGame` modifier |

---

## 15. DegenerusTraitUtils

| Function | Visibility | Guard | Guard Type |
|----------|-----------|-------|------------|
| View/pure functions only | external | None | Permissionless (read-only) |

---

## 16. DeityBoonViewer

| Function | Visibility | Guard | Guard Type |
|----------|-----------|-------|------------|
| View functions only | external | None | Permissionless (read-only) |

---

## 17. Icons32Data

| Function | Visibility | Guard | Guard Type |
|----------|-----------|-------|------------|
| View functions only | external | None | Permissionless (read-only, on-chain SVG data) |

---

## 18. Libraries (5 contracts)

All library functions are `internal` and execute in the caller's context. No external/public functions.

| Library | Functions | Notes |
|---------|-----------|-------|
| EntropyLib | `entropyStep` | Internal pure |
| BitPackingLib | `setPacked` + 11 constants | Internal pure |
| GameTimeLib | `dayIndex`, `secondsIntoDay` | Internal view |
| JackpotBucketLib | 13 functions | Internal pure/view |
| PriceLookupLib | `lookupPrice` | Internal pure |

---

## Access Control Architecture

### Design Principles

1. **Compile-time constants:** All privileged caller addresses are set via `ContractAddresses.*` at compile time. No runtime configuration, no setter functions, no admin re-pointing.

2. **No upgradability:** No proxy patterns, no UUPS, no transparent proxy, no diamond pattern for logic upgrades. Contract code is immutable after deployment.

3. **Minimal privilege:** Each contract exposes only the functions needed by its callers. The game router is the primary orchestrator; standalone contracts have narrow interfaces.

4. **Permissionless claims:** All claim/burn/ERC20 functions are permissionless. Players never need admin approval to withdraw their funds.

5. **Governance limited scope:** The governance system (Admin.propose/vote) can ONLY swap the VRF coordinator. It cannot modify game logic, transfer funds, or change access control.

---

*Access control matrix compiled from 16 unit audits, v5.0 Ultimate Adversarial Audit.*
*Phase 119 deliverable DEL-02.*
*Date: 2026-03-25*
