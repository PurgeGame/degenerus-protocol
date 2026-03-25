# Degenerus Protocol -- Storage Write Map

**Audit Date:** 2026-03-25
**Source:** v5.0 Ultimate Adversarial Audit, 16 unit phases (103-118)
**Scope:** All storage variables across all 29 protocol contracts

---

## Part 1: DegenerusGameStorage (Shared by Game Router + 10 Modules)

All 10 game modules execute via delegatecall in DegenerusGame's storage context. Storage layout verified EXACT MATCH across all modules (Unit 1, Phase 103). 102 variables across slots 0-78.

### Slot 0 -- Timing, FSM, Counters, Flags (32/32 bytes packed)

| Variable | Type | Offset | Writer Module(s) | Notes |
|----------|------|--------|------------------|-------|
| `levelStartTime` | uint48 | [0:6] | AdvanceModule | Set on level transitions |
| `dailyIdx` | uint48 | [6:12] | AdvanceModule | Day index for current game day |
| `rngRequestTime` | uint48 | [12:18] | AdvanceModule | Timestamp of last VRF request |
| `level` | uint24 | [18:21] | AdvanceModule | Current game level (FSM) |
| `jackpotPhaseFlag` | bool | [21:22] | AdvanceModule | Jackpot phase active flag |
| `jackpotCounter` | uint8 | [22:23] | AdvanceModule | Counter for jackpot phases |
| `poolConsolidationDone` | bool | [23:24] | AdvanceModule (via JackpotModule) | Prize pool consolidation complete |
| `lastPurchaseDay` | bool | [24:25] | AdvanceModule | Whether this is the last purchase day |
| `decWindowOpen` | bool | [25:26] | AdvanceModule | Decimator window open flag |
| `rngLockedFlag` | bool | [26:27] | AdvanceModule | VRF lock (prevents state changes during VRF) |
| `phaseTransitionActive` | bool | [27:28] | AdvanceModule | Phase transition in progress |
| `gameOver` | bool | [28:29] | AdvanceModule, GameOverModule | Terminal state flag |
| `dailyJackpotCoinTicketsPending` | bool | [29:30] | AdvanceModule | Pending coin ticket processing |
| `dailyEthPhase` | uint8 | [30:31] | JackpotModule | Daily ETH jackpot phase counter |
| `compressedJackpotFlag` | uint8 | [31:32] | JackpotModule | Compressed jackpot state flags |

### Slot 1 -- Price and Double-Buffer (25/32 bytes)

| Variable | Type | Offset | Writer Module(s) | Notes |
|----------|------|--------|------------------|-------|
| `purchaseStartDay` | uint48 | [0:6] | AdvanceModule | Day purchases started at current level |
| `price` | uint128 | [6:22] | AdvanceModule | Current ticket price (level-dependent) |
| `ticketWriteSlot` | uint8 | [22:23] | AdvanceModule | Double-buffer selector (0 or 1) |
| `ticketsFullyProcessed` | bool | [23:24] | JackpotModule | Ticket batch processing complete |
| `prizePoolFrozen` | bool | [24:25] | AdvanceModule | Transient guard during jackpot math |

### Slots 2-78 -- Full-Width Variables and Mappings

| Slot | Variable | Type | Writer Module(s) | Cross-Module Risk |
|------|----------|------|------------------|-------------------|
| 2 | `currentPrizePool` | uint256 | JackpotModule, EndgameModule | NONE (fresh reads) |
| 3 | `prizePoolsPacked` | uint256 | JackpotModule, MintModule, DegeneretteModule, EndgameModule | NONE (fresh read-modify-write via _set/_get) |
| 4 | `rngWordCurrent` | uint256 | AdvanceModule | Single writer |
| 5 | `vrfRequestId` | uint256 | AdvanceModule | Single writer |
| 6 | `totalFlipReversals` | uint256 | Game (router) | Single writer |
| 7 | `dailyTicketBudgetsPacked` | uint256 | JackpotModule | Single writer |
| 8 | `dailyEthPoolBudget` | uint256 | JackpotModule | Single writer |
| 9 | `claimableWinnings[addr]` | mapping | JackpotModule, EndgameModule, GameOverModule, DegeneretteModule, Game | NONE (return-value reconciliation) |
| 10 | `claimablePool` | uint256 | JackpotModule, EndgameModule, DegeneretteModule, Game | NONE (additive, no stale cache) |
| 11 | `traitBurnTicket[lvl][trait]` | mapping | JackpotModule (_raritySymbolBatch) | Single writer (assembly) |
| 12 | `mintPacked_[addr]` | mapping | MintModule, WhaleModule, BoonModule | NONE (non-overlapping bit fields) |
| 13 | `rngWordByDay[day]` | mapping | AdvanceModule | Single writer |
| 14 | `prizePoolPendingPacked` | uint256 | Game (receive()), AdvanceModule | Pending pool for frozen state |
| 15 | `ticketQueue[key]` | mapping | MintModule, WhaleModule | Additive (push only) |
| 16 | `ticketsOwedPacked[key][addr]` | mapping | MintModule, WhaleModule, JackpotModule | Writer-specific contexts |
| 17 | `ticketCursor` / `ticketLevel` | packed | JackpotModule | Single writer |
| 18 | `dailyCarryoverEthPool` | uint256 | JackpotModule | Single writer |
| 19 | `dailyCarryoverWinnerCap` | uint16 | JackpotModule | Single writer |
| 20 | `lootboxEth[day][addr]` | mapping | MintModule, WhaleModule, JackpotModule | Additive |
| 21 | `lootboxPresaleActive` | bool | MintModule | Single writer |
| 22 | `lootboxPresaleMintEth` | uint256 | MintModule | Single writer |
| 23 | `gameOverTime` / `gameOverFinalJackpotPaid` / `finalSwept` | packed | GameOverModule, AdvanceModule | Single-path write |
| 24 | `whalePassClaims[addr]` | mapping | Game (router) | Single writer |
| 25 | `autoRebuyState[addr]` | mapping | Game (router) | Single writer |
| 26 | `decimatorAutoRebuyDisabled[addr]` | mapping | DecimatorModule | Single writer |
| 27 | `lastDailyJackpotWinningTraits` / `Level` / `Day` | packed | JackpotModule | Single writer |
| 28 | `lootboxEthBase[day][addr]` | mapping | MintModule, WhaleModule | Additive |
| 29 | `operatorApprovals[owner][operator]` | mapping | Game (router) | Single writer |
| 30 | `levelPrizePool[lvl]` | mapping | JackpotModule, EndgameModule | Single-path |
| 31 | `affiliateDgnrsClaimedBy[lvl][addr]` | mapping | WhaleModule | Single writer |
| 32 | `levelDgnrsAllocation[lvl]` | mapping | JackpotModule | Single writer |
| 33 | `levelDgnrsClaimed[lvl]` | mapping | WhaleModule | Single writer |
| 34 | `deityPassCount[addr]` | mapping | WhaleModule | Single writer |
| 35 | `deityPassPurchasedCount[addr]` | mapping | WhaleModule | Single writer |
| 36 | `deityPassPaidTotal[addr]` | mapping | WhaleModule | Single writer |
| 37 | `deityPassOwners` | address[] | WhaleModule | Single writer |
| 38 | `deityPassSymbol[addr]` | mapping | WhaleModule | Single writer |
| 39 | `deityBySymbol[sym]` | mapping | WhaleModule | Single writer |
| 40 | `earlybirdDgnrsPoolStart` | uint256 | JackpotModule | Single writer |
| 41 | `earlybirdEthIn` | uint256 | JackpotModule | Single writer |
| 42 | `vrfCoordinator` | address | AdvanceModule (via Admin) | Set at construction + governance swap |
| 43 | `vrfKeyHash` | bytes32 | AdvanceModule (via Admin) | Set at construction + governance swap |
| 44 | `vrfSubscriptionId` | uint256 | AdvanceModule (via Admin) | Set at construction + governance swap |
| 45 | `lootboxRngIndex` | uint48 | AdvanceModule | Single writer |
| 46 | `lootboxRngPendingEth` | uint256 | LootboxModule, AdvanceModule | Additive (accumulate) / cleared on VRF |
| 47 | `lootboxRngThreshold` | uint256 | AdvanceModule (via Admin) | Admin-configurable threshold |
| 48 | `lootboxRngMinLinkBalance` | uint256 | Set at construction | Immutable after deploy |
| 49 | `lootboxRngWordByIndex[idx]` | mapping | AdvanceModule | Single writer (VRF fulfillment) |
| 50 | `lootboxDay[idx][addr]` | mapping | LootboxModule | Single writer |
| 51 | `lootboxBaseLevelPacked[idx][addr]` | mapping | LootboxModule | Single writer |
| 52 | `lootboxEvScorePacked[idx][addr]` | mapping | LootboxModule | Single writer |
| 53 | `lootboxBurnie[idx][addr]` | mapping | LootboxModule | Single writer |
| 54 | `lootboxRngPendingBurnie` | uint256 | LootboxModule | Single writer |
| 55 | `lastLootboxRngWord` | uint256 | AdvanceModule | Single writer |
| 56 | `midDayTicketRngPending` | bool | AdvanceModule | Single writer |
| 57 | `deityBoonDay[deity]` | mapping | BoonModule | Single writer |
| 58 | `deityBoonUsedMask[deity]` | mapping | BoonModule | Single writer |
| 59 | `deityBoonRecipientDay[addr]` | mapping | BoonModule | Single writer |
| 60 | `degeneretteBets[addr][nonce]` | mapping | DegeneretteModule | Single writer |
| 61 | `degeneretteBetNonce[addr]` | mapping | DegeneretteModule | Single writer |
| 62 | `lootboxEvBenefitUsedByLevel[addr][lvl]` | mapping | LootboxModule | Single writer |
| 63 | `decBurn[lvl][addr]` | mapping | DecimatorModule | Single writer |
| 64 | `decBucketBurnTotal[lvl]` | mapping | DecimatorModule | Single writer |
| 65 | `decClaimRounds[lvl]` | mapping | DecimatorModule | Single writer |
| 66 | `decBucketOffsetPacked[lvl]` | mapping(uint24 => uint64) | DecimatorModule (regular + terminal) | **MEDIUM: collision at GAMEOVER level** |
| 67 | `dailyHeroWagers[day]` | mapping | DegeneretteModule | Single writer |
| 68 | `playerDegeneretteEthWagered[addr][lvl]` | mapping | DegeneretteModule | Single writer |
| 69 | `topDegeneretteByLevel[lvl]` | mapping | DegeneretteModule | Single writer |
| 70 | `lootboxDistressEth[day][addr]` | mapping | LootboxModule | Single writer |
| 71 | `yieldAccumulator` | uint256 | JackpotModule | Single writer |
| 72 | `centuryBonusLevel` | uint24 | MintModule | Single writer |
| 73 | `centuryBonusUsed[addr]` | mapping | MintModule | Single writer |
| 74 | `lastVrfProcessedTimestamp` | uint48 | AdvanceModule | Single writer |
| 75 | `terminalDecEntries[addr]` | mapping | DecimatorModule | Single writer |
| 76 | `terminalDecBucketBurnTotal[key]` | mapping | DecimatorModule | Single writer |
| 77 | `lastTerminalDecClaimRound` | struct | DecimatorModule | Single writer |
| 78 | `boonPacked[addr]` | mapping (2 slots) | BoonModule | Single writer |

---

## Part 2: Standalone Contract Storage

### BurnieCoin

| Variable | Type | Writer Functions | Notes |
|----------|------|-----------------|-------|
| `balanceOf[addr]` | mapping | `transfer`, `transferFrom`, `_transfer`, `mintForGame`, `mintForCoinflip`, `vaultMintTo`, `decimatorBurn`, `terminalDecimatorBurn`, `burnForCoinflip` | Standard ERC20 + game-specific mints/burns |
| `totalSupply` | uint256 | `mintForGame`, `mintForCoinflip`, `vaultMintTo`, `decimatorBurn`, `terminalDecimatorBurn`, `burnForCoinflip` | Minted by game/coinflip/vault, burned by game/coinflip |
| `allowance[owner][spender]` | mapping | `approve`, `transferFrom` | Standard ERC20 |
| `vaultAllowance` | uint256 | `vaultMintTo`, `vaultEscrow` | Vault mint budget tracking |
| `coinflipContract` | address | Constructor | Immutable after deploy |
| Supply invariant: `totalSupply + vaultAllowance` constant across all vault redirect paths |

### BurnieCoinflip

| Variable | Type | Writer Functions | Notes |
|----------|------|-----------------|-------|
| `playerState[addr]` | mapping(PlayerCoinflipState) | `depositCoinflip`, `processCoinflipPayouts`, `claimCoinflips`, `settleFlipModeChange`, `setCoinflipAutoRebuy` | Per-player coinflip state |
| `dailyFlipTotal` | uint256 | `_addDailyFlip` (via deposit) | Daily flip tracking for bounty |
| `dailyFlipRecord` | uint256 | `_addDailyFlip` | Highest daily flip for bounty |
| `dailyFlipRecordHolder` | address | `_addDailyFlip` | Bounty recipient |
| `lastProcessedDay` | uint48 | `processCoinflipPayouts` | Last day payouts were processed |
| `totalDeposits` | uint256 | `depositCoinflip`, `processCoinflipPayouts` | Global deposit tracking |

### StakedDegenerusStonk (sDGNRS)

| Variable | Type | Writer Functions | Notes |
|----------|------|-----------------|-------|
| `balanceOf[addr]` | mapping | `gameDeposit`, `deposit`, `transferFromPool`, `burn`, `burnWrapped`, `_deterministicBurnFrom`, `wrapperTransferTo` | Pool-based distribution, burns |
| `totalSupply` | uint256 | All mint/burn paths | Supply tracks proportional ownership |
| `poolBalance[pool]` | mapping(Pool => uint256) | `deposit`, `transferFromPool`, `transferBetweenPools`, `burnRemainingPools` | Three pools: Whale, Affiliate, Claims |
| `pendingRedemptionEthValue` | uint256 | `resolveRedemptionPeriod`, `claimRedemption` | ETH reserved for gambling claims |
| `pendingRedemptionBurnie` | uint256 | `_submitGamblingClaimFrom`, `resolveRedemptionPeriod` | BURNIE reserved for gambling claims |
| `redemptionClaims[addr]` | mapping | `_submitGamblingClaimFrom`, `claimRedemption` | Per-player claim state |
| `currentRedemptionPeriod` | uint256 | `_submitGamblingClaimFrom` | Period counter |

### DegenerusStonk (DGNRS)

| Variable | Type | Writer Functions | Notes |
|----------|------|-----------------|-------|
| `balanceOf[addr]` | mapping | `transfer`, `transferFrom`, `burn`, `burnForSdgnrs`, `unwrapTo` | Standard ERC20 + burn paths |
| `totalSupply` | uint256 | `burn`, `burnForSdgnrs` | Monotonically decreasing (no runtime mint) |
| `allowance[owner][spender]` | mapping | `approve`, `transferFrom` | Standard ERC20 |

### DegenerusVault

| Variable | Type | Writer Functions | Notes |
|----------|------|-----------------|-------|
| `coinTracked` | uint256 | `_syncCoinReserves` (called on every entry) | BURNIE reserve tracking |
| ETH balance | native | `deposit`, `burnEth` (sends out), `receive` | Contract balance = ETH reserve |
| stETH balance | external | `deposit` (via game stakeEthToStEth) | stETH balance = staking reserve |

### DegenerusVaultShare (DGVB/DGVE)

| Variable | Type | Writer Functions | Notes |
|----------|------|-----------------|-------|
| `balanceOf[addr]` | mapping | `mint`, `burn`, `transfer`, `transferFrom` | Vault share balances |
| `totalSupply` | uint256 | `mint`, `burn` | Share supply (refill mechanism at zero) |
| `allowance[owner][spender]` | mapping | `approve`, `transferFrom` | Standard ERC20 |

### WrappedWrappedXRP (WWXRP)

| Variable | Type | Writer Functions | Notes |
|----------|------|-----------------|-------|
| `balanceOf[addr]` | mapping | `mintPrize`, `wrap`, `unwrap`, `burn`, `transfer`, `transferFrom` | Token balances |
| `totalSupply` | uint256 | `mintPrize`, `wrap`, `unwrap`, `burn` | Intentionally undercollateralized |
| `wXRPReserves` | uint256 | `wrap`, `unwrap`, `donate` | Backing reserves tracked separately from supply |
| `allowance[owner][spender]` | mapping | `approve`, `transferFrom` | Standard ERC20 |

### DegenerusAdmin

| Variable | Type | Writer Functions | Notes |
|----------|------|-----------------|-------|
| `subscriptionId` | uint256 | `_executeSwap`, `shutdownVrf` | VRF subscription ID |
| `proposals[id]` | mapping | `propose`, `vote`, `_executeSwap`, `_voidAllActive` | Governance proposals |
| `voidedUpTo` | uint256 | `_voidAllActive` | Monotonic watermark for proposal voiding |
| `proposalCount` | uint256 | `propose` | Proposal ID counter |
| `linkEthPriceFeed` | address | `setLinkEthPriceFeed` | LINK/ETH price oracle |

### DegenerusAffiliate

| Variable | Type | Writer Functions | Notes |
|----------|------|-----------------|-------|
| `affiliateCodes[code]` | mapping | `createAffiliateCode` | Code -> owner mapping |
| `referralOf[addr]` | mapping | `referPlayer` | Player -> referral code |
| `commissionPaid[code][sender][lvl]` | mapping | `payAffiliate` | Per-affiliate per-sender per-level cap |
| `affiliateEarnings[code]` | mapping | `payAffiliate` | Total earnings tracking |

### DegenerusQuests

| Variable | Type | Writer Functions | Notes |
|----------|------|-----------------|-------|
| `questSlots[addr]` | mapping | `rollDailyQuest` | Per-player quest configuration |
| `questProgress[addr]` | mapping | `handle*` (6 handlers) | Per-player quest progress |
| `questVersion[addr]` | mapping | `rollDailyQuest` | Progress versioning for day-boundary invalidation |
| `completionMask[addr]` | mapping | `handle*` handlers | Bitflag for completed slots |
| `streakCounter[addr]` | mapping | `rollDailyQuest`, `awardQuestStreakBonus` | Quest streak tracking |
| `streakShields[addr]` | mapping | `rollDailyQuest` | Streak shield consumption |

### DegenerusJackpots

| Variable | Type | Writer Functions | Notes |
|----------|------|-----------------|-------|
| `bafTotalStaked[addr]` | mapping | `recordBafFlip` | Per-player BAF stake tracking |
| `bafEpoch` | uint256 | `runBafJackpot` | Epoch counter for lazy reset |
| `playerBafEpoch[addr]` | mapping | `recordBafFlip` | Per-player epoch tracking |
| `bafResults[epoch]` | mapping | `runBafJackpot` | BAF jackpot results |

### DegenerusDeityPass (ERC721)

| Variable | Type | Writer Functions | Notes |
|----------|------|-----------------|-------|
| `_owners[tokenId]` | mapping | `mint`, `transferFrom`, `safeTransferFrom` | Token ownership |
| `_balances[addr]` | mapping | `mint`, `transferFrom` | Balance tracking |
| `_tokenApprovals[tokenId]` | mapping | `approve` | Per-token approval |
| `_operatorApprovals[owner][operator]` | mapping | `setApprovalForAll` | Operator approvals |

---

## Part 3: Cross-Module Write Conflicts

### Variables Written by 2+ Modules (Within Game's Storage Context)

| Variable | Writers | Access Pattern | Conflict Status |
|----------|---------|---------------|-----------------|
| `prizePoolsPacked` (slot 3) | JackpotModule, MintModule, DegeneretteModule, EndgameModule | Fresh `_get*` / `_set*` read-modify-write | **SAFE** |
| `claimablePool` (slot 10) | JackpotModule, EndgameModule, DegeneretteModule, Game | Additive pattern, no stale cache | **SAFE** |
| `claimableWinnings[addr]` (slot 9) | JackpotModule, EndgameModule, GameOverModule, DegeneretteModule, Game | Via `_addClaimableEth` with return-value tracking | **SAFE** |
| `mintPacked_[addr]` (slot 12) | MintModule, WhaleModule, BoonModule | Non-overlapping bit fields per writer | **SAFE** |
| `decBucketOffsetPacked[lvl]` (slot 66) | DecimatorModule (regular), DecimatorModule (terminal) | Same slot, different RNG words | **MEDIUM: collision at GAMEOVER level** |
| `totalDecBurned[addr]` | DecimatorModule (regular + terminal) | Additive accumulation | **SAFE** |
| `activityScorePacked[addr]` | MintModule, WhaleModule, DegeneretteModule | Via `_recordActivity` helper, additive | **SAFE** |

### Isolation Mechanisms

| Mechanism | Location | What It Prevents |
|-----------|----------|-----------------|
| Do-while break isolation | AdvanceModule L135-235 | Prevents stale local reuse after rngGate chain completes |
| Pre-commit before delegatecall | DegeneretteModule L703-704 | Ensures pool/claimable writes committed before lootbox call |
| rebuyDelta reconciliation | EndgameModule L244-246 | Captures all auto-rebuy writes during BAF/Decimator resolution |

---

*Storage write map compiled from 16 unit audits, v5.0 Ultimate Adversarial Audit.*
*Phase 119 deliverable DEL-03.*
*Date: 2026-03-25*
