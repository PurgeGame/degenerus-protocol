# Delta Extraction: Core Contracts

**Diff boundary:** v5.0..HEAD (per D-01)
**Method:** Fresh git diff only (per D-02)
**Change threshold:** Semantic code changes only; comment/NatSpec-only = UNCHANGED (per D-03)
**Scope:** 33 files -- 16 main contracts, 9 interfaces, 3 libraries, 5 mocks

## Contract Classification

### Main Contracts

| Contract | Status | Lines Changed | Justification |
|----------|--------|---------------|---------------|
| BurnieCoin.sol | MODIFIED | ~450 | Major refactor: removed quest routing (rollDailyQuest, notifyQuest*), removed creditCoin/creditFlip/creditFlipBatch/creditLinkReward, removed claimableCoin/previewClaimCoinflips/coinflipAutoRebuyInfo/coinflipAmount views, removed onlyAffiliate/onlyTrustedContracts/onlyFlipCreditors/onlyAdmin modifiers and errors, collapsed access control to onlyGame/onlyVault only, removed mintForCoinflip (unified into mintForGame with dual caller check), coinflip reference changed from raw address to typed IBurnieCoinflip constant, bounty state moved out to BurnieCoinflip |
| BurnieCoinflip.sol | MODIFIED | ~161 | Immutable refs changed to compile-time constants (IBurnieCoin/IDegenerusGame/IDegenerusJackpots/IWrappedWrappedXRP), constructor removed, day type narrowed uint48->uint32 throughout, onlyFlipCreditors expanded to GAME+QUESTS+AFFILIATE+ADMIN, creditFlipBatch changed from fixed-3 array to dynamic, RECYCLE_BONUS_BPS added (75 bps, was 1%), AFKING_RECYCLE_BONUS_BPS reduced 160->100, AFKING_DEITY_BONUS_MAX_HALF_BPS reduced 300->200, mintForCoinflip calls replaced with mintForGame, depositCoinflip auto-rebuy fix (reads claimableStored not mintable), deityPassCountFor replaced with hasDeityPass |
| ContractAddresses.sol | MODIFIED | ~3 | GNRUS address constant added, WXRP address constant removed -- both are semantic configuration changes affecting contract wiring |
| DegenerusAdmin.sol | MODIFIED | ~551 | Major governance refactor: Proposal struct repacked (3 slots from 7, uint48->uint40/uint40 for weights), added FeedProposal struct and full feed swap governance (proposeFeedSwap/voteFeedSwap/feedThreshold/canExecuteFeedSwap), circulatingSupply replaced with sDGNRS.votingSupply(), removed setLinkEthPriceFeed (replaced by governance), removed stakeGameEthToStEth/setLootboxRngThreshold admin proxies, vote refactored with shared _applyVote/_voterWeight/_requireActiveProposal/_resolveThreshold helpers, zero-weight poke pattern added, coinLinkReward routed to coinflipReward.creditFlip, purchaseInfo call replaced with mintPrice, _feedStallDuration added |
| DegenerusAffiliate.sol | MODIFIED | ~264 | Default codes via address-derived bytes32, winner-takes-all 75/20/5 roll replaced 3-recipient payout, quest routing moved from BurnieCoin to direct quests.handleAffiliate, flip crediting moved from coin.creditFlip to coinflip.creditFlip, leaderboard tracking moved post-taper (was pre-taper), affiliateBonusPoints changed to tiered rate (4pts/ETH first 5 ETH, 1.5pts/ETH next 20), _rollWeightedAffiliateWinner removed, _resolveCodeOwner added, registerAffiliateCode rejects address-range codes |
| DegenerusDeityPass.sol | MODIFIED | ~35 | Ownership model replaced: _contractOwner replaced with vault.isVaultOwner, constructor removed, Approval/ApprovalForAll/OwnershipTransferred events removed, owner()/transferOwnership() removed, IDegenerusVaultOwner interface added |
| DegenerusGame.sol | MODIFIED | ~623 | Major refactor: removed direct coin/coinflip/affiliate/dgnrs/questView constant refs (kept steth + added vault), uint48->uint32 for day types, levelStartTime replaced by purchaseStartDay+dailyIdx in constructor, deityPassCount replaced with mintPacked_ HAS_DEITY_PASS_SHIFT, reverseFlip moved from AdvanceModule delegatecall to inline with compounding nudge cost, placeFullTicketBets renamed placeDegeneretteBet, claimWhalePass moved from GAME_ENDGAME_MODULE to GAME_WHALE_MODULE, removed decWindowOpenFlag/hasActiveLazyPass/_isGameoverImminent/_activeTicketLevel/_threeDayRngGap, decWindow simplified to single bool return, removed ethMintLastLevel/ethMintLevelCount/autoRebuyEnabledFor/decimatorAutoRebuyEnabledFor/setDecimatorAutoRebuy, removed futurePrizePoolTotalView/rewardPoolView/lastRngWord/rngStalledForThreeDays/lootboxRngIndexView/lootboxRngWord/lootboxRngThresholdView/lootboxRngMinLinkBalanceView, claimablePool cast to uint128 on subtraction, finalSwept replaced with _goRead packed field, setLootboxRngThreshold access changed from ADMIN to vault owner, recordMintQuestStreak access changed from COIN to GAME, claimWinningsStethFirst restricted to VAULT only (removed SDGNRS), adminStakeEthForStEth access changed from ADMIN to vault owner, added runBafJackpot delegatecall entry, added gameOverTimestamp view, added ReverseFlip event, added _currentNudgeCost, price replaced with PriceLookupLib.priceForLevel, lootboxPresaleActive replaced with _psRead packed field, currentPrizePool replaced with _getCurrentPrizePool packed read |
| DegenerusJackpots.sol | MODIFIED | ~8 | lastBafResolvedDay type narrowed uint48->uint32, getLastBafResolvedDay return type narrowed, recordBafFlip NatSpec updated for COIN or COINFLIP access |
| DegenerusQuests.sol | MODIFIED | ~607 | Major refactor: added IBurnieCoinflip import for direct flip crediting, all uint48 day types narrowed to uint32, QuestSlotRolled event removed difficulty field, rollDailyQuest simplified (no return values, no difficulty), handleMint/handleLootBox/handleDegenerette gained mintPrice parameter, added handlePurchase for unified purchase path, rollLevelQuest added, getPlayerLevelQuestView added, quest reward crediting moved from BurnieCoin routing to direct coinflip.creditFlip calls internally |
| DegenerusStonk.sol | MODIFIED | ~136 | Vesting system added (CREATOR_INITIAL 50B, VEST_PER_LEVEL 5B, CREATOR_TOTAL 200B, claimVested), yearSweep added (1-year post-gameover 50/50 to GNRUS+VAULT), unwrapTo access changed from CREATOR to vault.isVaultOwner, unwrap guard changed from VRF stall to rngLocked, constructor splits supply between CREATOR and address(this) for vesting, transferFrom emits Approval on allowance decrease, added IDegenerusVault/IDegenerusGame interfaces, added SweepNotReady/NothingToSweep errors and YearSweep event |
| DegenerusVault.sol | MODIFIED | ~125 | gameDegeneretteBetEth/gameDegeneretteBetBurnie/gameDegeneretteBetWwxrp consolidated into single gameDegeneretteBet with currency param, placeFullTicketBets renamed to placeDegeneretteBet, sdgnrsBurn and sdgnrsClaimRedemption added for vault-held sDGNRS operations, IStakedDegenerusStonkBurn interface added, NatSpec added to all IDegenerusGamePlayerActions/ICoinflipPlayerActions/ICoinPlayerActions function signatures |
| DeityBoonViewer.sol | MODIFIED | ~19 | uint48 day types narrowed to uint32, NatSpec added to IDeityBoonDataSource and _boonFromRoll |
| GNRUS.sol | NEW | ~547 | Entirely new soulbound GNRUS donation token: 1T supply minted to contract, per-level 2% distribution via sDGNRS-weighted governance (propose/vote/pickCharity), burn-for-redemption of proportional ETH+stETH, burnAtGameOver finalization, soulbound enforcement (transfer/transferFrom/approve all revert) |
| Icons32Data.sol | UNCHANGED | ~2 | Comment-only change: renamed `_diamond` reference to `_paths[32]` in the icon layout documentation comment. No code change. |
| StakedDegenerusStonk.sol | MODIFIED | ~84 | uint48->uint32 day narrowing throughout (PendingRedemption.periodIndex, RedemptionPeriod.flipDay, etc.), resolveRedemptionPeriod changed from returning burnieToCredit to void (BURNIE paid via _payBurnie on claim instead), burnRemainingPools renamed to burnAtGameOver, votingSupply() added (excludes this/DGNRS/VAULT), poolTransfer self-win now burns instead of no-op transfer, NatSpec added to all external interface functions |
| WrappedWrappedXRP.sol | MODIFIED | ~112 | wXRP backing removed entirely: removed IERC20 import, removed wXRP constant, removed wXRPReserves state, removed unwrap/donate functions, removed Unwrapped/Donated events, removed InsufficientReserves/TransferFailed errors, all wXRP-related NatSpec stripped. Token is now a pure mint/burn game reward with no redemption path. |

### Interfaces

| Contract | Status | Lines Changed | Justification |
|----------|--------|---------------|---------------|
| DegenerusGameModuleInterfaces.sol | DELETED | 32 | File removed. Contained IDegenerusCoinModule (creditFlip, creditFlipBatch, rollDailyQuest, vaultEscrow). Functions redistributed: creditFlip/creditFlipBatch moved to IBurnieCoinflip, rollDailyQuest moved to IDegenerusQuests, vaultEscrow moved to IDegenerusCoin. |
| IBurnieCoinflip.sol | MODIFIED | ~16 | processCoinflipPayouts epoch uint48->uint32, creditFlipBatch changed from fixed address[3]/uint256[3] to dynamic arrays, coinflipAutoRebuyInfo startDay uint48->uint32, getCoinflipDayResult day uint48->uint32, creditFlip creditor list updated in NatSpec |
| IDegenerusAffiliate.sol | MODIFIED | ~2 | affiliateBonusPoints NatSpec updated for tiered rate formula |
| IDegenerusCoin.sol | MODIFIED | ~30 | No longer extends IDegenerusCoinModule, removed creditCoin/notifyQuestMint/notifyQuestLootBox/notifyQuestDegenerette, added vaultEscrow (moved from IDegenerusCoinModule) |
| IDegenerusGame.sol | MODIFIED | ~96 | decWindow simplified to single bool return (removed lvl), removed lootboxRngWord/ethMintLevelCount/ethMintStreakCount/ethMintLastLevel/futurePrizePoolTotalView/lootboxRngIndexView/lootboxRngThresholdView/lootboxRngMinLinkBalanceView/setLootboxRngThreshold/deityPassCountFor/deityPassPurchasedCountFor/deityPassTotalIssuedCount, added runBafJackpot/hasDeityPass/mintPackedFor/placeDegeneretteBet(renamed), deityBoonData day uint48->uint32, currentDayView uint48->uint32, getDailyHeroWager/getDailyHeroWinner day uint48->uint32, recordMintQuestStreak access updated, sampleFutureFarTickets NatSpec added |
| IDegenerusGameModules.sol | MODIFIED | ~74 | IDegenerusGameEndgameModule removed entirely (runRewardJackpots/rewardTopAffiliate/claimWhalePass), IDegenerusGameAdvanceModule.reverseFlip removed, consolidatePrizePools/awardFinalDayDgnrsReward/processTicketBatch removed from JackpotModule, handleGameOverDrain day uint48->uint32, payDailyJackpot param renamed isDaily->isJackpotPhase, added runBafJackpot/distributeYieldSurplus to JackpotModule, added claimWhalePass to WhaleModule, added processTicketBatch to MintModule, deityBoonSlots day uint48->uint32, placeFullTicketBets renamed placeDegeneretteBet |
| IDegenerusJackpots.sol | MODIFIED | ~2 | getLastBafResolvedDay return type uint48->uint32 |
| IDegenerusQuests.sol | MODIFIED | ~65 | rollDailyQuest simplified (uint48->uint32, removed return values), handleMint/handleLootBox/handleDegenerette gained mintPrice param, added handlePurchase for unified path, awardQuestStreakBonus day uint48->uint32, QuestInfo.day uint48->uint32, added rollLevelQuest/getPlayerLevelQuestView |
| IStakedDegenerusStonk.sol | MODIFIED | ~14 | burnRemainingPools renamed burnAtGameOver, burn NatSpec updated for gambling-path return semantics, resolveRedemptionPeriod changed from returning uint256 to void, flipDay uint48->uint32 |

### Libraries

| Contract | Status | Lines Changed | Justification |
|----------|--------|---------------|---------------|
| BitPackingLib.sol | MODIFIED | ~23 | Added HAS_DEITY_PASS_SHIFT(184), AFFILIATE_BONUS_LEVEL_SHIFT(185), AFFILIATE_BONUS_POINTS_SHIFT(209), MASK_6, MASK_2, MASK_1 constants for new mintPacked_ fields |
| GameTimeLib.sol | MODIFIED | ~10 | JACKPOT_RESET_TIME type uint48->uint32, currentDayIndex/currentDayIndexAt return types uint48->uint32, internal cast to uint32 |
| JackpotBucketLib.sol | MODIFIED | ~3 | NatSpec-only: added documentation for empty non-remainder bucket behavior and caller responsibility in bucketShares. Classified as MODIFIED because the NatSpec clarifies a semantic behavior requirement (empty bucket share accounting) that downstream auditors need. |

### Mocks

| Contract | Status | Lines Changed | Justification |
|----------|--------|---------------|---------------|
| MockGameCharity.sol | NEW | ~31 | New mock for DegenerusGame used by GNRUS unit tests: setGameOver, setClaimable, claimableWinningsOf, claimWinnings with ETH forwarding |
| MockSDGNRSCharity.sol | NEW | ~28 | New mock for sDGNRS used by GNRUS unit tests: settable totalSupply, balanceOf, votingSupply |
| MockVRFCoordinator.sol | MODIFIED | ~6 | Added resetFulfilled(uint256 requestId) for multi-day test sequences |
| MockVaultCharity.sol | NEW | ~12 | New mock for DegenerusVault used by GNRUS unit tests: settable isVaultOwner mapping |
| MockWXRP.sol | MODIFIED | ~2 | decimals changed from 18 to 6 (semantic: affects all WXRP amount calculations in tests) |

## Function-Level Changelog

### BurnieCoin.sol (MODIFIED)

| Function | Visibility | Change | Description |
|----------|-----------|--------|-------------|
| claimableCoin() | external view | REMOVED | Proxied to BurnieCoinflip; callers should use BurnieCoinflip directly |
| spendableCoin(address) | external view | MODIFIED | Now uses typed `coinflip` constant instead of raw address cast |
| previewClaimCoinflips(address) | external view | REMOVED | Proxied to BurnieCoinflip; callers should use BurnieCoinflip directly |
| coinflipAutoRebuyInfo(address) | external view | REMOVED | Proxied to BurnieCoinflip; callers should use BurnieCoinflip directly |
| burnForCoinflip(address, uint256) | external | MODIFIED | Access check changed from `coinflipContract` to `ContractAddresses.COINFLIP` |
| mintForCoinflip(address, uint256) | external | REMOVED | Replaced by expanded mintForGame with dual caller check |
| mintForGame(address, uint256) | external | MODIFIED | Access expanded to accept both COINFLIP and GAME callers |
| creditCoin(address, uint256) | external | REMOVED | Was onlyFlipCreditors; functionality consolidated |
| creditFlip(address, uint256) | external | REMOVED | Forwarded to BurnieCoinflip; callers now call BurnieCoinflip directly |
| creditFlipBatch(address[3], uint256[3]) | external | REMOVED | Forwarded to BurnieCoinflip; callers now call BurnieCoinflip directly |
| creditLinkReward(address, uint256) | external | REMOVED | DegenerusAdmin now calls coinflip.creditFlip directly |
| _claimCoinflipShortfall(address, uint256) | private | MODIFIED | Uses typed `coinflip` constant |
| _consumeCoinflipShortfall(address, uint256) | private | MODIFIED | Uses typed `coinflip` constant |
| affiliateQuestReward(address, uint256) | external | REMOVED | Affiliate now calls quests.handleAffiliate directly |
| rollDailyQuest(uint48, uint256) | external | REMOVED | AdvanceModule now calls DegenerusQuests.rollDailyQuest directly |
| notifyQuestMint(address, uint32, bool) | external | REMOVED | MintModule now calls DegenerusQuests.handleMint/handlePurchase directly |
| notifyQuestLootBox(address, uint256) | external | REMOVED | LootboxModule now calls DegenerusQuests.handleLootBox directly |
| notifyQuestDegenerette(address, uint256, bool) | external | REMOVED | DegeneretteModule now calls DegenerusQuests.handleDegenerette directly |
| burnCoin(address, uint256) | external | MODIFIED | Modifier changed from onlyTrustedContracts to onlyGame |
| decimatorBurn(address, uint256) | external | MODIFIED | decWindow now returns single bool; level fetched separately via degenerusGame.level(); quest processing simplified |
| coinflipAmount(address) | external view | REMOVED | Proxied to BurnieCoinflip; callers should use BurnieCoinflip directly |
| onlyDegenerusGameContract | modifier | REMOVED | Replaced by onlyGame |
| onlyTrustedContracts | modifier | REMOVED | Replaced by onlyGame |
| onlyFlipCreditors | modifier | REMOVED | Moved to BurnieCoinflip with expanded caller list |
| onlyAdmin | modifier | REMOVED | No remaining admin-only functions in BurnieCoin |
| onlyGame | modifier | ADDED | Simple msg.sender == GAME check, replaces multiple modifiers |

### BurnieCoinflip.sol (MODIFIED)

| Function | Visibility | Change | Description |
|----------|-----------|--------|-------------|
| constructor(address, address, address, address) | public | REMOVED | Contract references now compile-time constants |
| onlyFlipCreditors | modifier | MODIFIED | Expanded from GAME+BURNIE to GAME+QUESTS+AFFILIATE+ADMIN |
| onlyBurnieCoin | modifier | MODIFIED | Uses ContractAddresses.COIN instead of address(burnie) |
| onlyDegenerusGameContract | modifier | MODIFIED | Uses ContractAddresses.GAME instead of address(degenerusGame) |
| depositCoinflip(address, uint256) | external | MODIFIED | Auto-rebuy rollAmount reads claimableStored instead of mintable; deityPassCountFor replaced with hasDeityPass; NatSpec added |
| claimCoinflips(address, uint256) | external | MODIFIED | NatSpec added for params and return |
| claimCoinflipsFromBurnie(address, uint256) | external | MODIFIED | NatSpec added for params and return |
| claimCoinflipsForRedemption(address, uint256) | external | MODIFIED | NatSpec added for params and return |
| consumeCoinflipsForBurn(address, uint256) | external | MODIFIED | NatSpec added for params and return |
| _claimInternal(address, bool, bool) | private | MODIFIED | mintForCoinflip replaced with mintForGame; deityPassCountFor replaced with hasDeityPass; all uint48 day types narrowed to uint32 |
| _settleResolvedDays(address, PlayerCoinflipState, bool, bool) | private | MODIFIED | All uint48 day types narrowed to uint32; deityPassCountFor replaced with hasDeityPass |
| _addDailyFlip(address, uint256, uint256, bool, bool) | private | MODIFIED | uint48 targetDay narrowed to uint32 |
| setCoinflipAutoRebuy(address, bool, uint256) | external | MODIFIED | NatSpec added; mintForCoinflip replaced with mintForGame |
| setCoinflipAutoRebuyTakeProfit(address, uint256) | external | MODIFIED | NatSpec added; mintForCoinflip replaced with mintForGame |
| processCoinflipPayouts(bool, uint256, uint32) | external | MODIFIED | epoch param type uint48->uint32; NatSpec added |
| creditFlip(address, uint256) | external | MODIFIED | NatSpec updated for expanded creditor list |
| creditFlipBatch(address[], uint256[]) | external | MODIFIED | Changed from fixed address[3]/uint256[3] to dynamic arrays; loop bound changed from 3 to players.length |
| coinflipAmount(address) | external view | MODIFIED | uint48->uint32 for targetDay |
| coinflipAutoRebuyInfo(address) | external view | MODIFIED | startDay type uint48->uint32 |
| topDayBettorView() | external view | MODIFIED | uint48->uint32 for lastDay |
| _pendingFlipWinnings(address) | internal view | MODIFIED | All uint48 day types narrowed to uint32 |
| getCoinflipDayResult(uint32) | external view | MODIFIED | day param type uint48->uint32 |
| _recyclingBonus(uint256) | private pure | MODIFIED | Rate changed from 1% (amount/100) to 0.75% (amount * RECYCLE_BONUS_BPS / BPS_DENOMINATOR) |
| _targetFlipDay() | internal view | MODIFIED | Return type uint48->uint32 |
| _updateTopDayBettor(address, uint256, uint32) | private | MODIFIED | day param type uint48->uint32 |

### ContractAddresses.sol (MODIFIED)

| Function | Visibility | Change | Description |
|----------|-----------|--------|-------------|
| GNRUS | constant | ADDED | New address constant for GNRUS donation contract |
| WXRP | constant | REMOVED | wXRP address removed as WWXRP no longer wraps a backing token |

### DegenerusAdmin.sol (MODIFIED)

| Function | Visibility | Change | Description |
|----------|-----------|--------|-------------|
| setLinkEthPriceFeed(address) | external | REMOVED | Replaced by governance-based proposeFeedSwap/voteFeedSwap |
| stakeGameEthToStEth(uint256) | external | REMOVED | Admin proxy removed; function moved directly to DegenerusGame |
| setLootboxRngThreshold(uint256) | external | REMOVED | Admin proxy removed; function moved directly to DegenerusGame |
| proposeFeedSwap(address) | external | ADDED | Governance proposal for LINK/ETH feed swap (admin 2d stall, community 7d stall) |
| voteFeedSwap(uint256, bool) | external | ADDED | Vote on feed swap proposal with auto-cancel on feed recovery |
| feedThreshold(uint256) | public view | ADDED | Decaying threshold for feed proposals (50%->40%->25%->15% over 4 days) |
| canExecuteFeedSwap(uint256) | external view | ADDED | View-only check for feed proposal execution readiness |
| _executeFeedSwap(uint256) | internal | ADDED | Execute feed swap, void other active feed proposals |
| circulatingSupply() | public view | REMOVED | Replaced by sDGNRS.votingSupply() |
| proposeVrfSwap(address, bytes32) | external | MODIFIED | Uses sDGNRS.votingSupply() instead of circulatingSupply(); Proposal struct repacked with uint40 fields |
| vote(uint256, bool) | external | MODIFIED | Refactored to use _applyVote/_voterWeight/_requireActiveProposal/_resolveThreshold helpers; zero-weight poke pattern added |
| canExecute(uint256) | external view | MODIFIED | Uses _isActiveProposal and _resolveThreshold helpers |
| onTokenTransfer(address, uint256, bytes) | external | MODIFIED | purchaseInfo() call replaced with mintPrice(); coinLinkReward replaced with coinflipReward.creditFlip |
| _applyVote(bool, uint40, Vote, uint40, uint40, uint40) | private pure | ADDED | Shared vote application logic for VRF and feed governance |
| _voterWeight() | private view | ADDED | Get voter sDGNRS weight as whole tokens |
| _requireActiveProposal(ProposalState, uint40, uint256) | private view | ADDED | Validate proposal is active and not expired |
| _isActiveProposal(ProposalState, uint40, uint256) | private view | ADDED | Non-reverting active proposal check |
| _resolveThreshold(uint256, uint256, uint256, uint16) | private pure | ADDED | Shared threshold resolution logic (Execute/Kill/None) |
| _feedStallDuration(address) | private view | ADDED | Calculate feed unhealthy duration for governance thresholds |

### DegenerusAffiliate.sol (MODIFIED)

| Function | Visibility | Change | Description |
|----------|-----------|--------|-------------|
| referPlayer(bytes32) | external | MODIFIED | Uses _resolveCodeOwner for both custom and default address-derived codes |
| defaultCode(address) | external pure | ADDED | Computes default affiliate code for any address (bytes32(uint256(uint160(addr)))) |
| payAffiliate(uint256, bytes32, ...) | external | MODIFIED | Major rework: resolves default codes, winner-takes-all 75/20/5 roll replaces 3-recipient payout, leaderboard tracking moved post-taper, quest routing goes to quests.handleAffiliate directly, flip crediting to coinflip.creditFlip |
| affiliateBonusPoints(uint24, address) | external view | MODIFIED | Tiered rate: 4pts/ETH for first 5 ETH, 1.5pts/ETH for next 20 ETH (was flat 1pt/ETH) |
| _setReferralCode(address, bytes32) | private | MODIFIED | Uses _resolveCodeOwner for referrer lookup |
| _resolveCodeOwner(bytes32) | private view | ADDED | Resolves code owner: custom lookup first, then address-derived default |
| _referrerAddress(address) | private view | MODIFIED | Uses _resolveCodeOwner with address(0)->VAULT fallback |
| _registerAffiliateCode(bytes32, address, uint8) | private | MODIFIED | Rejects codes in address-derived range (uint256(code_) <= type(uint160).max) |
| _routeAffiliateReward(address, uint256) | private | MODIFIED | Routes through coinflip.creditFlip instead of coin.creditFlip |
| _rollWeightedAffiliateWinner(address[3], uint256[3], ...) | private view | REMOVED | Replaced by inline 75/20/5 roll |

### DegenerusDeityPass.sol (MODIFIED)

| Function | Visibility | Change | Description |
|----------|-----------|--------|-------------|
| constructor() | public | REMOVED | No constructor needed; owner verification via vault.isVaultOwner |
| owner() | external view | REMOVED | Ownership is now via vault DGVE majority |
| transferOwnership(address) | external | REMOVED | Not applicable with vault-based ownership |
| onlyOwner | modifier | MODIFIED | Changed from _contractOwner check to vault.isVaultOwner(msg.sender) |
| setRenderer(address) | external | MODIFIED | NatSpec added for newRenderer param |
| mint(address, uint256) | external | MODIFIED | NatSpec added for to and tokenId params |

### DegenerusGame.sol (MODIFIED)

| Function | Visibility | Change | Description |
|----------|-----------|--------|-------------|
| constructor() | public | MODIFIED | Uses purchaseStartDay/dailyIdx instead of levelStartTime; deity pass tracking via mintPacked_ instead of deityPassCount; _queueTickets gains 4th param |
| advanceGame() | external | MODIFIED | (No functional change visible in diff; orchestration changes are in modules) |
| recordMintPurchase(uint256, uint32, MintPaymentKind) | external | MODIFIED | Formatting cleanup only |
| recordMintQuestStreak(address) | external | MODIFIED | Access changed from COIN to GAME (self-call from MintModule delegatecall) |
| payCoinflipBountyDgnrs(address, uint256, uint256) | external | MODIFIED | NatSpec added for winningBet and bountyPool params |
| currentDayView() | external view | MODIFIED | Return type uint48->uint32 |
| setLootboxRngThreshold(uint256) | external | MODIFIED | Access changed from ADMIN to vault.isVaultOwner |
| placeFullTicketBets -> placeDegeneretteBet | external payable | MODIFIED | Renamed; selector reference updated in delegatecall |
| deityBoonData(address) | external view | MODIFIED | day return type uint48->uint32 |
| _processMintPayment(uint256, uint32, MintPaymentKind) | private | MODIFIED | claimablePool subtraction cast to uint128 |
| claimWinningsStethFirst() | external | MODIFIED | Restricted to VAULT only (removed SDGNRS access) |
| _claimWinningsInternal(address, bool) | private | MODIFIED | finalSwept replaced with _goRead packed field; claimablePool subtraction cast to uint128 |
| claimAffiliateDgnrs() | external | MODIFIED | deityPassCount replaced with mintPacked_ HAS_DEITY_PASS_SHIFT; price replaced with PriceLookupLib.priceForLevel; coin.creditFlip replaced with coinflip.creditFlip |
| setDecimatorAutoRebuy(address, bool) | external | REMOVED | Decimator auto-rebuy configuration removed |
| autoRebuyEnabledFor(address) | external view | REMOVED | View function removed |
| decimatorAutoRebuyEnabledFor(address) | external view | REMOVED | View function removed |
| _hasAnyLazyPass(address) | private view | MODIFIED | Uses mintPacked_ HAS_DEITY_PASS_SHIFT instead of deityPassCount |
| hasActiveLazyPass(address) | external view | REMOVED | External view removed; internal _hasAnyLazyPass still exists |
| claimWhalePass(address) | external | MODIFIED | Delegates to GAME_WHALE_MODULE instead of GAME_ENDGAME_MODULE |
| _claimWhalePassFor(address) | private | MODIFIED | Delegates to IDegenerusGameWhaleModule.claimWhalePass |
| poolTransferAndRecycle(uint256) | external | MODIFIED | claimablePool subtraction cast to uint128 |
| adminSwapEthForStEth(address, uint256) | external | MODIFIED | Added AdminSwapEthForStEth event emission |
| adminStakeEthForStEth(uint256) | external | MODIFIED | Access changed from ADMIN to vault.isVaultOwner; added AdminStakeEthForStEth event emission |
| reverseFlip() | external | MODIFIED | Moved from AdvanceModule delegatecall to inline implementation with compounding nudge cost |
| _currentNudgeCost(uint256) | private pure | ADDED | Base 100 BURNIE with +50% per queued nudge |
| runBafJackpot(uint256, uint24, uint256) | external | ADDED | Delegatecall entry to JackpotModule.runBafJackpot |
| recordTerminalDecBurn(address, uint24, uint256) | external | MODIFIED | Formatting only (selector split across lines) |
| runTerminalDecimatorJackpot(uint256, uint24, uint256) | external | MODIFIED | Formatting only (selector split across lines) |
| decWindow() | external view | MODIFIED | Simplified from (bool on, uint24 lvl) to single bool return |
| _isGameoverImminent() | private view | REMOVED | No longer used by decWindow |
| _activeTicketLevel() | private view | REMOVED | Moved elsewhere (likely MintStreakUtils or storage) |
| _threeDayRngGap(uint48) | private view | REMOVED | Governance uses lastVrfProcessed time-based detection |
| rngStalledForThreeDays() | external view | REMOVED | Replaced by time-based stall detection |
| futurePrizePoolTotalView() | external view | REMOVED | Redundant with futurePrizePoolView |
| ethMintLastLevel(address) | external view | REMOVED | Raw data available via mintPackedFor |
| ethMintLevelCount(address) | external view | REMOVED | Raw data available via mintPackedFor |
| lootboxRngIndexView() | external view | REMOVED | Packed into storage; not exposed |
| lootboxRngWord(uint48) | external view | REMOVED | Internal access only |
| lootboxRngThresholdView() | external view | REMOVED | Packed into storage; not exposed |
| lootboxRngMinLinkBalanceView() | external view | REMOVED | Removed |
| lastRngWord() | external view | REMOVED | Callers use rngWordForDay(dailyIdx) |
| rewardPoolView() | external view | REMOVED | Redundant with futurePrizePoolView |
| lootboxPresaleActiveFlag() | external view | MODIFIED | Reads from packed presale state field |
| currentPrizePoolView() | external view | MODIFIED | Uses _getCurrentPrizePool packed read |
| claimablePoolView() | external view | MODIFIED | finalSwept replaced with _goRead packed field |
| isFinalSwept() | external view | MODIFIED | Reads from packed gameover state field |
| gameOverTimestamp() | external view | ADDED | Reads gameover timestamp from packed field |
| yieldPoolView() | external view | MODIFIED | currentPrizePool replaced with _getCurrentPrizePool |
| mintPrice() | external view | MODIFIED | price storage replaced with PriceLookupLib.priceForLevel |
| rngWordForDay(uint32) | external view | MODIFIED | day param type uint48->uint32 |
| purchaseState() | external view | MODIFIED | price replaced with PriceLookupLib.priceForLevel |
| mintPackedFor(address) | external view | ADDED | Raw packed data access (replaces ethMintLastLevel, ethMintLevelCount, etc.) |
| hasDeityPass(address) | external view | ADDED | Reads HAS_DEITY_PASS_SHIFT from mintPacked_ (replaces deityPassCountFor) |

### DegenerusJackpots.sol (MODIFIED)

| Function | Visibility | Change | Description |
|----------|-----------|--------|-------------|
| getLastBafResolvedDay() | external view | MODIFIED | Return type uint48->uint32 |

### DegenerusQuests.sol (MODIFIED)

| Function | Visibility | Change | Description |
|----------|-----------|--------|-------------|
| rollDailyQuest(uint32, uint256) | external | MODIFIED | Day param uint48->uint32; simplified to no return values; difficulty removed |
| handleMint(address, uint32, bool, uint256) | external | MODIFIED | Added mintPrice param for target scaling; credits flip rewards internally via coinflip.creditFlip |
| handleLootBox(address, uint256, uint256) | external | MODIFIED | Added mintPrice param for target scaling; credits flip rewards internally |
| handleDegenerette(address, uint256, bool, uint256) | external | MODIFIED | Added mintPrice param for target scaling; credits flip rewards internally |
| handleDecimator(address, uint256) | external | MODIFIED | Credits flip rewards internally via coinflip.creditFlip |
| handleAffiliate(address, uint256) | external | MODIFIED | Credits flip rewards internally via coinflip.creditFlip |
| handlePurchase(address, uint32, uint32, uint256, uint256, uint256) | external | ADDED | Unified purchase path combining handleMint + handleLootBox for single cross-contract call |
| rollLevelQuest(uint256) | external | ADDED | Level-scoped quest rolled by AdvanceModule during level transition |
| getPlayerLevelQuestView(address) | external view | ADDED | Returns level quest state (type, progress, target, completed, eligible) |
| awardQuestStreakBonus(address, uint16, uint32) | external | MODIFIED | Day param uint48->uint32 |

### DegenerusStonk.sol (MODIFIED)

| Function | Visibility | Change | Description |
|----------|-----------|--------|-------------|
| constructor() | public | MODIFIED | Splits supply between CREATOR (50B) and address(this) (unvested); initializes _vestingReleased |
| transferFrom(address, address, uint256) | external | MODIFIED | Emits Approval event on allowance decrease (ERC20 compliance) |
| unwrapTo(address, uint256) | external | MODIFIED | Access changed from CREATOR to vault.isVaultOwner; guard changed from VRF stall (5h) to rngLocked |
| claimVested() | external | ADDED | Vault owner claims level-vested DGNRS (50B initial + 5B/level, max 200B at level 30) |
| burn(uint256) | external | MODIFIED | Uses game.gameOver() constant instead of ad-hoc interface call; NatSpec expanded |
| yearSweep() | external | ADDED | Permissionless 1-year post-gameover sweep: burns remaining sDGNRS, splits ETH/stETH 50-50 to GNRUS and VAULT |

### DegenerusVault.sol (MODIFIED)

| Function | Visibility | Change | Description |
|----------|-----------|--------|-------------|
| gameDegeneretteBetEth(uint128, uint8, uint32, uint8, uint256) | external payable | REMOVED | Consolidated into gameDegeneretteBet |
| gameDegeneretteBetBurnie(uint128, uint8, uint32, uint8) | external | REMOVED | Consolidated into gameDegeneretteBet |
| gameDegeneretteBetWwxrp(uint128, uint8, uint32, uint8) | external | REMOVED | Consolidated into gameDegeneretteBet |
| gameDegeneretteBet(uint8, uint128, uint8, uint32, uint8, uint256) | external payable | ADDED | Unified degenerette bet with currency param (0=ETH, 1=BURNIE, 3=WWXRP) |
| sdgnrsBurn(uint256) | external | ADDED | Vault owner burns vault-held sDGNRS to claim backing assets |
| sdgnrsClaimRedemption() | external | ADDED | Vault owner claims resolved sDGNRS gambling burn redemption |
| gamePurchaseDeityPassFromBoon(uint256, uint8) | external payable | MODIFIED | NatSpec updated for symbolId param |

### DeityBoonViewer.sol (MODIFIED)

| Function | Visibility | Change | Description |
|----------|-----------|--------|-------------|
| deityBoonSlots(address, address) | external view | MODIFIED | day return type uint48->uint32 |
| _boonFromRoll(uint256, bool, bool) | private pure | MODIFIED | NatSpec added for params and return |

### GNRUS.sol (NEW)

| Function | Visibility | Change | Description |
|----------|-----------|--------|-------------|
| constructor() | public | ADDED | Mints 1T GNRUS to address(this) as unallocated pool |
| transfer(address, uint256) | external pure | ADDED | Always reverts (soulbound enforcement) |
| transferFrom(address, address, uint256) | external pure | ADDED | Always reverts (soulbound enforcement) |
| approve(address, uint256) | external pure | ADDED | Always reverts (soulbound enforcement) |
| burn(uint256) | external | ADDED | Burns GNRUS from caller, pays proportional ETH+stETH (pulls from game claimable if needed) |
| burnAtGameOver() | external | ADDED | Game-only: burns all unallocated GNRUS at gameover |
| propose(address) | external | ADDED | Create governance proposal for current level (0.5% sDGNRS threshold or vault owner up to 5x) |
| vote(uint48, bool) | external | ADDED | Cast approve/reject vote with sDGNRS weight (vault owner gets +5% snapshot bonus) |
| pickCharity(uint24) | external | ADDED | Game-only: resolves level, distributes 2% of unallocated to winning proposal's recipient |
| receive() | external payable | ADDED | Accepts ETH from game claimWinnings and direct deposits |
| getProposal(uint48) | external view | ADDED | View proposal details by global ID |
| getLevelProposals(uint24) | external view | ADDED | View proposal range (start, count) for a level |

### StakedDegenerusStonk.sol (MODIFIED)

| Function | Visibility | Change | Description |
|----------|-----------|--------|-------------|
| votingSupply() | external view | ADDED | Returns sDGNRS supply excluding this contract, DGNRS wrapper, and vault |
| poolTransfer(Pool, address, uint256) | external | MODIFIED | Self-win (to == address(this)) now burns instead of no-op transfer |
| burnRemainingPools -> burnAtGameOver | external | MODIFIED | Renamed for clarity |
| resolveRedemptionPeriod(uint16, uint32) | external | MODIFIED | flipDay uint48->uint32; no longer returns burnieToCredit (BURNIE paid via _payBurnie on claim) |
| claimRedemption() | external | MODIFIED | uint48->uint32 for period index types |
| _submitRedemption(address, uint256) | internal | MODIFIED | uint48->uint32 for currentPeriod |

### WrappedWrappedXRP.sol (MODIFIED)

| Function | Visibility | Change | Description |
|----------|-----------|--------|-------------|
| unwrap(uint256) | external | REMOVED | wXRP backing removed; no redemption path |
| donate(uint256) | external | REMOVED | wXRP backing removed; no donation mechanism |

### DegenerusGameModuleInterfaces.sol (DELETED)

| Function | Visibility | Change | Description |
|----------|-----------|--------|-------------|
| IDegenerusCoinModule.creditFlip(address, uint256) | external | MOVED | Moved to IBurnieCoinflip.creditFlip (callers now go to BurnieCoinflip directly) |
| IDegenerusCoinModule.creditFlipBatch(address[3], uint256[3]) | external | MOVED | Moved to IBurnieCoinflip.creditFlipBatch (changed to dynamic arrays) |
| IDegenerusCoinModule.rollDailyQuest(uint48, uint256) | external | MOVED | Moved to IDegenerusQuests.rollDailyQuest (called by AdvanceModule directly) |
| IDegenerusCoinModule.vaultEscrow(uint256) | external | MOVED | Moved to IDegenerusCoin.vaultEscrow |

### MockGameCharity.sol (NEW)

| Function | Visibility | Change | Description |
|----------|-----------|--------|-------------|
| setGameOver(bool) | external | ADDED | Test helper to toggle gameOver state |
| setClaimable(address, uint256) | external | ADDED | Test helper to set claimable amounts |
| claimableWinningsOf(address) | external view | ADDED | Returns stored claimable for address |
| claimWinnings(address) | external | ADDED | Sends stored ETH to player and zeroes claimable |
| receive() | external payable | ADDED | Accepts ETH funding |

### MockSDGNRSCharity.sol (NEW)

| Function | Visibility | Change | Description |
|----------|-----------|--------|-------------|
| setTotalSupply(uint256) | external | ADDED | Test helper to set totalSupply |
| setBalance(address, uint256) | external | ADDED | Test helper to set per-address balance |
| setVotingSupply(uint256) | external | ADDED | Test helper to set voting supply |
| votingSupply() | external view | ADDED | Returns explicit _votingSupply or totalSupply fallback |

### MockVRFCoordinator.sol (MODIFIED)

| Function | Visibility | Change | Description |
|----------|-----------|--------|-------------|
| resetFulfilled(uint256) | external | ADDED | Resets fulfilled flag for multi-day test reuse |

### MockVaultCharity.sol (NEW)

| Function | Visibility | Change | Description |
|----------|-----------|--------|-------------|
| setVaultOwner(address, bool) | external | ADDED | Test helper to set vault owner status |
| isVaultOwner(address) | external view | ADDED | Returns stored vault owner status |

### MockWXRP.sol (MODIFIED)

| Function | Visibility | Change | Description |
|----------|-----------|--------|-------------|
| decimals | constant | MODIFIED | Changed from 18 to 6 (affects all test amount calculations) |
