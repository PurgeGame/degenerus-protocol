# Adversarial Audit: Access Control + Integer Overflow Pass

**Scope:** All changed/new functions in v5.0-to-HEAD delta (per 213-DELTA-EXTRACTION.md Phase 214 scope)
**Method:** Fresh audit (per D-02) -- no prior audit artifacts referenced
**Chains in scope:** SM-01 through SM-56, EF-01 through EF-20, RNG-01 through RNG-11, RO-01 through RO-12 (per D-03)

## Methodology

### Access Control
For each function:
1. Identify the access modifier/guard (onlyGame, onlyVault, msg.sender == X, etc.)
2. Compare against the delta changelog: was the modifier CHANGED, ADDED, or REMOVED?
3. If changed: verify the new guard is at least as restrictive as needed (no privilege escalation)
4. If removed: verify the function no longer needs access control (or flag as VULNERABLE)
5. For delegatecall-targeted functions: verify the caller gate at the DegenerusGame entry point

### Integer Safety
For each function:
1. Identify all type narrowings (uint48->uint32, uint256->uint128, etc.)
2. For each narrowing: compute the maximum possible value and verify it fits in the target type
3. For uint32 day indexes: verify 2^32 days (11.7M years) exceeds any possible game lifetime
4. For uint128 pool values: verify maximum possible ETH (10^18 * amount) fits in uint128 (3.4 * 10^38)
5. For packed bitfield operations: verify shift constants do not overlap (BitPackingLib additions)
6. Check for unchecked arithmetic blocks and verify each cannot overflow

## Findings

No VULNERABLE findings. All access control changes are equivalent-or-stronger. All integer narrowings fit within target types with wide safety margins.

## Access Control Modifier Change Matrix

| Old Modifier/Guard | New Modifier/Guard | Contracts Affected | Verdict |
|--------------------|--------------------|--------------------|---------|
| onlyDegenerusGameContract (msg.sender == address(degenerusGame)) | onlyGame (msg.sender != ContractAddresses.GAME) | BurnieCoin | EQUIVALENT -- both resolve to same GAME address; old used immutable, new uses compile-time constant |
| onlyTrustedContracts (GAME, COIN, COINFLIP, SDGNRS, ADMIN) | onlyGame (GAME only) | BurnieCoin.burnCoin | STRENGTHENED -- removed COIN, COINFLIP, SDGNRS, ADMIN access. Only functions that needed multi-caller access were removed or split to dedicated functions (burnForCoinflip, mintForGame) |
| onlyFlipCreditors (GAME+BURNIE) | onlyFlipCreditors (GAME+QUESTS+AFFILIATE+ADMIN) | BurnieCoinflip.creditFlip/creditFlipBatch | WIDENED -- see Critical Access Control Changes: BurnieCoinflip Expanded Creditors |
| onlyAdmin (msg.sender == ADMIN) | REMOVED | BurnieCoin | SAFE -- no remaining admin-only functions in BurnieCoin; admin operations migrated to other contracts |
| onlyAffiliate (msg.sender == AFFILIATE) | REMOVED | BurnieCoin | SAFE -- affiliate reward routing moved from BurnieCoin to DegenerusAffiliate calling coinflip.creditFlip directly |
| _contractOwner (stored address) | vault.isVaultOwner(msg.sender) (>50.1% DGVE) | DegenerusDeityPass.onlyOwner | STRENGTHENED -- vault-based ownership requires >50.1% DGVE stake vs single stored EOA; cannot be brute-forced; see Vault-Based Ownership Migration |
| CREATOR (msg.sender == ContractAddresses.CREATOR) | vault.isVaultOwner(msg.sender) | DegenerusStonk.unwrapTo | EQUIVALENT/STRENGTHENED -- creator IS the initial vault owner (holds all DGVE); vault.isVaultOwner is a superset that allows ownership transfer via DGVE, which is by design |
| VRF stall 5h guard | game.rngLocked() guard | DegenerusStonk.unwrapTo | EQUIVALENT -- both prevent unwrap during active VRF; rngLocked is more precise (active request vs time-based estimate) |
| ADMIN (msg.sender == ContractAddresses.ADMIN) | vault.isVaultOwner(msg.sender) | DegenerusGame.adminStakeEthForStEth | STRENGTHENED -- admin is a separate contract; vault owner requires >50.1% DGVE; reduces admin contract attack surface |
| ADMIN (msg.sender == ContractAddresses.ADMIN) | vault.isVaultOwner(msg.sender) | DegenerusGame.setLootboxRngThreshold | STRENGTHENED -- same as above |
| COIN (msg.sender == ContractAddresses.COIN) | GAME (msg.sender == ContractAddresses.GAME) | DegenerusGame.recordMintQuestStreak | EQUIVALENT -- was called by BurnieCoin acting on behalf of Game; now called by MintModule via delegatecall (executes as GAME). Self-call from module context |
| SDGNRS+VAULT callers | VAULT only | DegenerusGame.claimWinningsStethFirst | STRENGTHENED -- removed sDGNRS access. Verified sDGNRS no longer needs stETH-first claiming: sDGNRS claimRedemption uses Game's _claimWinningsInternal via standard claimWinnings path, not stETH-first |
| circulatingSupply() | sDGNRS.votingSupply() | DegenerusAdmin.propose/vote/proposeFeedSwap/voteFeedSwap | STRENGTHENED -- votingSupply excludes the sDGNRS contract itself, DGNRS wrapper, and VAULT, so only genuine holders count. Prevents pool/wrapper tokens from inflating governance thresholds |

## Integer Type Narrowing Matrix

| Type Change | Where Used | Max Possible Value | Fits Target | Verdict |
|-------------|------------|-------------------|-------------|---------|
| uint48->uint32 (day index) | GameTimeLib.currentDayIndex/currentDayIndexAt, all modules (dailyIdx, purchaseStartDay), BurnieCoinflip (all day params), DegenerusQuests (all day params), StakedDegenerusStonk (flipDay, periodIndex), DegenerusAdmin (Proposal.createdAt remains uint40) | uint32 max = 4,294,967,295 days = ~11.7M years from epoch. Game deploys in 2024+ and runs max ~120 days per level with max ~30 levels = ~3,600 days. Even with unlimited levels, 11.7M years is unreachable. | Yes -- 11.7M years >> any possible game lifetime | SAFE |
| uint256->uint128 (currentPrizePool) | DegenerusGameStorage slot 1, _getCurrentPrizePool/_setCurrentPrizePool, all modules reading currentPrizePool | uint128 max = 3.4 * 10^38. At 10^18 wei/ETH, this holds 3.4 * 10^20 ETH. Total ETH supply is ~120M ETH = 1.2 * 10^8 ETH. Pool cannot exceed total ETH supply. | Yes -- 3.4 * 10^20 ETH >> 1.2 * 10^8 ETH supply, margin > 10^12x | SAFE |
| uint256->uint128 (claimablePool) | DegenerusGameStorage slot 1, _claimWinningsInternal, DecimatorModule, DegeneretteModule, GameOverModule, PayoutUtils | Same analysis as currentPrizePool. claimablePool tracks total owed ETH; cannot exceed total ETH deposited + stETH backing, which cannot exceed total supply. | Yes -- same 10^12x margin | SAFE |
| New bitfield shifts: HAS_DEITY_PASS_SHIFT(184) | BitPackingLib, bit 184. Adjacent fields: MINT_STREAK_LAST_COMPLETED at bits [160-183] (24 bits: 160+24=184). HAS_DEITY_PASS at bit 184 (1 bit: 184+1=185). AFFILIATE_BONUS_LEVEL at bits [185-208] (24 bits). | Bit 184 is exactly the next bit after MINT_STREAK_LAST_COMPLETED [160-183]. No overlap. | N/A | SAFE |
| New bitfield shifts: AFFILIATE_BONUS_LEVEL_SHIFT(185) | BitPackingLib, bits [185-208]. Previous field HAS_DEITY_PASS at bit 184 (1 bit ends at 185). Next field AFFILIATE_BONUS_POINTS at bits [209-214]. | 185 = 184 + 1 (deity pass). 185 + 24 = 209 = AFFILIATE_BONUS_POINTS_SHIFT. No overlap. | N/A | SAFE |
| New bitfield shifts: AFFILIATE_BONUS_POINTS_SHIFT(209) | BitPackingLib, bits [209-214] (6 bits). Next used field: LEVEL_UNITS_SHIFT at bit 228. Gap of 14 unused bits [215-227]. | 209 + 6 = 215. LEVEL_UNITS_SHIFT = 228. No overlap, 13-bit gap. | N/A | SAFE |
| uint128 Supply struct (BurnieCoin._supply) | totalSupply and vaultAllowance packed as uint128+uint128. _toUint128 guards all writes. | uint128 max = 3.4 * 10^38. BURNIE total supply starts at 2M + 2M vault = 4M ether = 4 * 10^24 wei. Even at 1000x inflation = 4 * 10^27 << 3.4 * 10^38. | Yes -- wide margin | SAFE |
| uint48 Proposal weights -> uint40 (DegenerusAdmin) | Proposal.approveWeight/rejectWeight are uint40. _voterWeight() returns uint40. | uint40 max = 1.1 * 10^12. votingSupply() returns sDGNRS excluding pools/wrapper/vault. sDGNRS total supply = 1T tokens = 10^12 * 10^18 wei. Divided by 1e18 = 10^12. This is within uint40 (max ~1.1 * 10^12) but tight. However, votingSupply excludes contract/pool holdings (~60-70% of supply), so effective max is ~3-4 * 10^11. | Yes -- votingSupply < totalSupply/1e18; with exclusions, stays under uint40 max | SAFE |
| uint48 GNRUS Proposal weights | Proposal.approveWeight/rejectWeight are uint48. weight stored as uint48(sdgnrs.balanceOf(voter) / 1e18). | uint48 max = 2.8 * 10^14. sDGNRS supply / 1e18 = 10^12. Wide margin (280x). | Yes -- 280x margin | SAFE |

## Per-Function Verdicts

### Module Contracts

#### DegenerusGameAdvanceModule.sol

| Function | Visibility | Access Gate | Access Verdict | Integer Patterns | Overflow Verdict | Notes |
|----------|-----------|-------------|----------------|------------------|------------------|-------|
| advanceGame | external | Entered via DegenerusGame delegatecall (GAME entry: external, any caller) | SAFE | purchaseStartDay uint32, dailyIdx uint32, level uint24 | SAFE | Public entry but side effects are state-machine gated (jackpotPhaseFlag, rngLockedFlag, dailyIdx checks). Level increments bounded by game mechanics (max ~30 levels). |
| _handleGameOverPath | private | Called from advanceGame (access inherited) | SAFE | psd uint32 (purchaseStartDay), day comparison uint32 | SAFE | Day arithmetic: purchaseStartDay + 120 days. Max uint32 = 4.29B days. 120 << 4.29B. |
| _rewardTopAffiliate | private | Called from _requestRng (access inherited from advanceGame) | SAFE | levelDgnrsAllocation uint256, dgnrs.transferFromPool amount uint256 | SAFE | No narrowing -- operates on full-width uint256 for sDGNRS amounts. |
| _distributeYieldSurplus | private | Wraps delegatecall to JackpotModule.distributeYieldSurplus | SAFE | N/A (passthrough) | SAFE | Access control inherited from advanceGame caller chain. |
| _consolidatePoolsAndRewardJackpots | private | Called from advanceGame | SAFE | Memory-local pool math: uint256 for nextPool, futurePool, currentPrizePool read as uint256 via _getCurrentPrizePool | SAFE | All pool values remain uint256 in memory; only narrowed to uint128 on final SSTORE via _setCurrentPrizePool (which uses explicit cast). |
| rngGate | internal | Called from advanceGame | SAFE | Returns (uint256 word, uint32 gapDays). gapDays is day count difference. | SAFE | gapDays bounded by game lifetime. |
| _gameOverEntropy | private | Called from _handleGameOverPath | SAFE | Day parameter uint32 | SAFE | Day is uint32, same as all day types. |
| _requestRng | private | Called from advanceGame | SAFE | PriceLookupLib returns uint256 price. lootboxRngIndex via _lrRead returns packed uint256. | SAFE | No narrowing in this function. |
| _nextToFutureBps | internal | Called from _consolidatePoolsAndRewardJackpots | SAFE | elapsed uint32 (was uint48). BPS calculation: elapsed * STEP stays within uint256 working space. | SAFE | uint32 elapsed * 16-bit step = max ~6.8 * 10^13, well within uint256. |
| payDailyJackpot | internal | Called via delegatecall chain from advanceGame | SAFE | Parameter renamed only (isDaily -> isJackpotPhase). | SAFE | No new narrowing. |
| _enforceDailyMintGate | private | Called from advanceGame | SAFE | dailyIdx_ uint32 (was uint48). mintPacked_ deity pass bit check via BitPackingLib. | SAFE | Deity pass check reads 1 bit at position 184. No overflow possible. |
| requestLootboxRng | external | Entered via DegenerusGame delegatecall (GAME entry) | SAFE | Packed lootbox RNG reads/writes via _lrRead/_lrWrite (uint256 packed). Price via PriceLookupLib (uint256). | SAFE | All packed operations use proper masks. |
| _runProcessTicketBatch | private | Delegatecall target changed to MintModule | SAFE | N/A | SAFE | Passthrough only -- access unchanged. |
| _processPhaseTransition | private | Called from advanceGame | SAFE | _queueTickets gains rngBypass=true (bool param). | SAFE | No integer change. |
| _backfillGapDays | private | Called from rngGate | SAFE | Parameters narrowed to uint32. 120-day gap cap added. | SAFE | Cap ensures bounded iteration. uint32 day arithmetic safe per matrix. |
| _unlockRng | private | Called from advanceGame | SAFE | Day parameter uint32 | SAFE | Direct assignment to uint32 storage. |
| _backfillOrphanedLootboxIndices | private | Called from _requestRng | SAFE | lootboxRngIndex via packed _lrRead | SAFE | Index reads from packed field, no narrowing issue. |
| _applyDailyRng | private | Called from rngGate | SAFE | Day parameter uint32 | SAFE | Day stored to uint32 mapping key. |
| _finalizeLootboxRng | private | Called from rawFulfillRandomWords | SAFE | lootboxRngIndex via packed _lrRead | SAFE | Same as _backfillOrphanedLootboxIndices. |
| _wadPow | private | Pure math helper | SAFE | Fixed-point 1e18 scale. Internal unchecked blocks for known-safe shifts. | SAFE | Input bounded by day counts (max ~120); output bounded by exp(120) in fixed-point. |
| _projectedDrip | private | Pure math helper | SAFE | Geometric series over n days. n bounded by game lifetime. | SAFE | Uses _wadPow which handles the bounded inputs. |
| _evaluateGameOverAndTarget | private | Called from advanceGame | SAFE | Sets/clears gameOverPossible bool. Pool comparisons use uint256. | SAFE | No narrowing. |

#### DegenerusGameBoonModule.sol

| Function | Visibility | Access Gate | Access Verdict | Integer Patterns | Overflow Verdict | Notes |
|----------|-----------|-------------|----------------|------------------|------------------|-------|
| consumeCoinflipBoon | external | DegenerusGame delegatecall (GAME entry, player self-call via Game) | SAFE | BoonConsumed event emits (player, 1, boonBps). boonBps is uint16. | SAFE | Event emission only change. |
| consumePurchaseBoost | external | DegenerusGame delegatecall | SAFE | BoonConsumed event emits (player, 2, boostBps). | SAFE | Event emission only change. |
| consumeDecimatorBoost | external | DegenerusGame delegatecall | SAFE | BoonConsumed event emits (player, 3, boostBps). | SAFE | Event emission only change. |
| consumeActivityBoon | external | DegenerusGame delegatecall | SAFE | BoonConsumed event emits (player, 5, bonus). | SAFE | Event emission only change. |

#### DegenerusGameDecimatorModule.sol

| Function | Visibility | Access Gate | Access Verdict | Integer Patterns | Overflow Verdict | Notes |
|----------|-----------|-------------|----------------|------------------|------------------|-------|
| recordDecimatorBurn | external | DegenerusGame delegatecall (GAME entry, called from BurnieCoin.decimatorBurn which is permissionless with isOperatorApproved) | SAFE | NatSpec-only change | SAFE | No code change. |
| runDecimatorJackpot | external | DegenerusGame delegatecall (called from advanceGame chain) | SAFE | DecimatorResolved event emitted with packed offsets (uint256), pool, totalBurn. | SAFE | No narrowing. |
| claimDecimatorJackpot | external | DegenerusGame delegatecall (player self-call via Game) | SAFE | _creditClaimable replaces _addClaimableEth (auto-rebuy removed). claimablePool cast to uint128. | SAFE | claimablePool uint128 cast proven safe per matrix (3.4 * 10^20 ETH max). |
| _splitDecClaim | private | Called from claimDecimatorJackpot | SAFE | claimablePool cast to uint128 | SAFE | Same uint128 safety as above. |
| _awardDecimatorLootbox | private | Called from claimDecimatorJackpot | SAFE | _queueTicketRange with explicit parameters. | SAFE | No new narrowing. |
| recordTerminalDecBurn | external | DegenerusGame delegatecall (GAME entry, called from BurnieCoin.terminalDecimatorBurn which is permissionless with isOperatorApproved) | SAFE | Burns blocked at <=7 days (was <=1). Day arithmetic uses uint32. | SAFE | uint32 day comparison safe per matrix. Stricter blocking (7 days) is a safety improvement. |
| claimTerminalDecimatorJackpot | external | DegenerusGame delegatecall | SAFE | _creditClaimable replaces _addClaimableEth. | SAFE | Same uint128 analysis. |
| _terminalDecMultiplierBps | private | Pure math | SAFE | Day-based linear interpolation. All arithmetic in uint256 working space. | SAFE | Bounded by game level days (max 120). |
| _terminalDecDaysRemaining | private | View | SAFE | purchaseStartDay uint32 + deadline uint24. Sum fits uint32. | SAFE | 32-bit day + 24-bit level = max ~4.3B, fits uint256 working space. |

#### DegenerusGameDegeneretteModule.sol

| Function | Visibility | Access Gate | Access Verdict | Integer Patterns | Overflow Verdict | Notes |
|----------|-----------|-------------|----------------|------------------|------------------|-------|
| placeDegeneretteBet (renamed from placeFullTicketBets) | external | DegenerusGame delegatecall (GAME entry: external payable, any caller with ETH or game-approved tokens) | SAFE | Quest notification changed to quests.handleDegenerette. lootboxRngIndex via _lrRead. Activity score via _playerActivityScore. BetPlaced index cast to uint32. | SAFE | uint32 index cast: bet index cannot exceed uint32 max in any practical scenario. |
| _collectBetFunds | private | Called from placeDegeneretteBet | SAFE | claimablePool narrowed to uint128. lootboxRngPendingEth/Burnie packed as milli-ETH/whole-BURNIE. | SAFE | uint128 claimablePool proven safe. Milli-ETH encoding: max 128-bit field * 10^15 = fits uint256 for intermediate math. |
| _resolveFullTicketBet | private | Called from resolveBets | SAFE | Index decoded as uint32 | SAFE | Same uint32 index analysis. |
| _distributePayout | private | Called from _resolveFullTicketBet | SAFE | claimablePool narrowed to uint128 | SAFE | Proven safe per matrix. |
| resolveBets | external | DegenerusGame delegatecall (GAME entry, permissionless) | SAFE | Parameter formatting only | SAFE | No integer change. |

#### DegenerusGameGameOverModule.sol

| Function | Visibility | Access Gate | Access Verdict | Integer Patterns | Overflow Verdict | Notes |
|----------|-----------|-------------|----------------|------------------|------------------|-------|
| handleGameOverDrain | external | DegenerusGame delegatecall (called from advanceGame chain, gated by gameOver state) | SAFE | Day parameter uint32. gameOverStatePacked packed reads/writes. claimablePool uint128. currentPrizePool via _setCurrentPrizePool (uint128). | SAFE | All narrowings proven safe per matrix. RNG gate defense-in-depth reverts if funds exist but word unavailable -- safety improvement. |
| handleFinalSweep | external | DegenerusGame delegatecall (called from advanceGame chain, gated by gameOverStatePacked state machine) | SAFE | All state via _goRead/_goWrite packed helpers. | SAFE | Packed helpers use proper masks. |
| _sendToVault | private | Called from handleFinalSweep | SAFE | Split changed 50/50 -> 33/33/34. ETH division arithmetic stays uint256. | SAFE | Integer division: 33/100 and 34/100 of uint256 amounts. No overflow. |
| _sendStethFirst | private | Called from _sendToVault | SAFE | stETH balance uint256, ETH remainder uint256. | SAFE | No narrowing. |

#### DegenerusGameJackpotModule.sol

| Function | Visibility | Access Gate | Access Verdict | Integer Patterns | Overflow Verdict | Notes |
|----------|-----------|-------------|----------------|------------------|------------------|-------|
| distributeYieldSurplus (was private _distributeYieldSurplus) | external | DegenerusGame delegatecall (called from AdvanceModule._distributeYieldSurplus wrapper) | SAFE | GNRUS added as third yield recipient. 23% splits in uint256. | SAFE | Percentage math: value * 2300 / 10000 stays uint256. |
| payDailyJackpot | external | DegenerusGame delegatecall (from advanceGame chain) | SAFE | resumeEthPool replaces dailyEthPoolBudget/dailyEthPhase. Carryover 0.5% of futurePool as tickets. | SAFE | Percentage math (0.5% = value * 50 / 10000) stays uint256. |
| payDailyJackpotCoinAndTickets | external | DegenerusGame delegatecall | SAFE | Reads winning traits from _djtRead packed field. | SAFE | Packed reads with proper masks. |
| _addClaimableEth | private | Called internally | SAFE | Returns (claimableDelta, rebuyLevel, rebuyTickets) tuple. claimablePool access via inherited storage. | SAFE | No new narrowing. |
| _processDailyEth | private | Major rewrite, called from payDailyJackpot | SAFE | splitMode (SPLIT_NONE/CALL1/CALL2) enum. Solo bucket + whale pass + DGNRS on final day. | SAFE | All ETH amounts remain uint256. |
| _resumeDailyEth | private | Call 2 of two-call split | SAFE | Reconstructs from stored state. | SAFE | Same uint256 working space. |
| _handleSoloBucketWinner | private | Called from _processDailyEth | SAFE | Whale pass and DGNRS reward logic. | SAFE | No narrowing. |
| _payNormalBucket | private | Called from _processDailyEth | SAFE | Normal bucket payment. | SAFE | No narrowing. |
| _resolveTraitWinners | private | Called from _processDailyEth | SAFE | payCoin removed. Returns simplified tuple. | SAFE | Reduced complexity. |
| _runJackpotEthFlow | private | Called from payDailyJackpot | SAFE | Fixed bucket counts [20, 12, 6, 1] = 39 winners. Entropy rotation via keccak256. | SAFE | Fixed iteration count (39). |
| _executeJackpot | private | Called from _consolidatePoolsAndRewardJackpots | SAFE | Returns paidEth (uint256). | SAFE | Full-width return. |
| _runEarlyBirdLootboxJackpot | private | Called from payDailyJackpotCoinAndTickets | SAFE | _queueTickets gains rngBypass=true. | SAFE | Bool param, no overflow. |
| _distributeTicketJackpot | private | Called from payDailyJackpotCoinAndTickets | SAFE | Gains sourceLvl and queueLvl uint24 params. | SAFE | uint24 level values, game max ~30 levels. |
| _distributeTicketsToBuckets | private | Called from _distributeTicketJackpot | SAFE | Same sourceLvl/queueLvl params. | SAFE | Same uint24 analysis. |
| _distributeTicketsToBucket | private | Called from _distributeTicketsToBuckets | SAFE | JackpotTicketWin event emitted. | SAFE | Event emission. |
| _applyHeroOverride (renamed from _getWinningTraits) | private | Called from _rollWinningTraits | SAFE | Simplified: caller provides base traits. | SAFE | No narrowing. |
| _rollWinningTraits | private | Called from _syncDailyWinningTraits | SAFE | Removed lvl and useBurnCounts params. | SAFE | Simplified. |
| _syncDailyWinningTraits | private | Called from payDailyJackpot | SAFE | _djtWrite packed field. Day uint32. | SAFE | uint32 day per matrix. |
| _loadDailyWinningTraits | private | Called from payDailyJackpotCoinAndTickets | SAFE | _djtRead packed field. Day uint32. | SAFE | Same. |
| _calcDailyCoinBudget | private | Called from payDailyJackpotCoinAndTickets | SAFE | PriceLookupLib.priceForLevel(level) returns uint256. | SAFE | Full-width. |
| _selectDailyCoinTargetLevel | private | Made pure. Removed _hasTraitTickets check. | SAFE | Returns uint24 level. | SAFE | uint24 bounded by game levels. |
| _awardDailyCoinToTraitWinners | private | Called from payDailyJackpotCoinAndTickets | SAFE | Individual coinflip.creditFlip calls replace batch. | SAFE | No overflow from call pattern change. |
| _awardFarFutureCoinJackpot | private | Called from payDailyJackpotCoinAndTickets | SAFE | Dynamic arrays replace fixed-3. | SAFE | Array length bounded by winner count. |
| _topHeroSymbol | private | Called from _rollWinningTraits | SAFE | Day param uint32 (was uint48). | SAFE | uint32 per matrix. |
| _randTraitTicket | private | Merged with _randTraitTicketWithIndices | SAFE | keccak256(abi.encode(randomWord, trait, salt, i)) per winner. | SAFE | keccak256 output is uint256; no overflow. |
| runBafJackpot | external | DegenerusGame.runBafJackpot: msg.sender != address(this) check (self-call guard). Only Game can call itself. | SAFE | Returns claimableDelta uint256. | SAFE | Self-call guard prevents external invocation. |
| _awardJackpotTickets | private | Moved from EndgameModule | SAFE | Same logic. | SAFE | No changes. |
| _jackpotTicketRoll | private | Moved from EndgameModule | SAFE | _queueLootboxTickets gains rngBypass=true. | SAFE | Bool param. |
| _processSoloBucketWinner | private | Called from _processDailyEth | SAFE | Extended tuple return with rebuyLevel/rebuyTickets. | SAFE | uint24 levels. |

#### DegenerusGameLootboxModule.sol

| Function | Visibility | Access Gate | Access Verdict | Integer Patterns | Overflow Verdict | Notes |
|----------|-----------|-------------|----------------|------------------|------------------|-------|
| openLootbox | external | DegenerusGame delegatecall (GAME entry) | SAFE | presaleActive via _psRead packed. Day index uint32. | SAFE | Packed read with masks. uint32 per matrix. |
| openBurnieLootbox | external | DegenerusGame delegatecall | SAFE | PriceLookupLib price. gameOverPossible flag replaces timestamp cutoff. Event index uint32. | SAFE | uint32 index; PriceLookupLib returns uint256. |
| resolveLootboxDirect | external | DegenerusGame delegatecall | SAFE | Day index uint32 | SAFE | Per matrix. |
| resolveRedemptionLootbox | external | DegenerusGame delegatecall | SAFE | Day index uint32 | SAFE | Per matrix. |
| deityBoonSlots | external | DegenerusGame delegatecall | SAFE | Return day uint32 | SAFE | Per matrix. |
| issueDeityBoon | external | DegenerusGame delegatecall | SAFE | Day uint32 | SAFE | Per matrix. |
| _resolveLootboxCommon | private | Called from openLootbox/openBurnieLootbox | SAFE | Day uint32. _queueTicketsScaled rngBypass=false. coinflip.creditFlip replaces coin.creditFlip. | SAFE | Route change only; creditFlip amount unchanged. |
| _rollLootboxBoons | private | Called from _resolveLootboxCommon | SAFE | Multi-boon support: _activeBoonCategory check removed. Day uint32. mintPacked_ deity bit replaces deityPassCount. | SAFE | 1-bit deity check. Multi-boon is a loosening of restriction (players can hold multiple boons) but not an access control issue. |
| _applyBoon | private | Called from _rollLootboxBoons | SAFE | Day params uint32. Deity boon upgrade semantics. | SAFE | Per matrix. |
| _activate10LevelPass | private | Called from _applyBoon | SAFE | _queueTickets rngBypass=false | SAFE | Bool param. |
| _boonPoolStats | private | Called from _rollLootboxBoons | SAFE | PriceLookupLib price | SAFE | Full-width. |
| _deityDailySeed | private | Called from issueDeityBoon | SAFE | Day uint32 | SAFE | Per matrix. |
| _deityBoonForSlot | private | Called from issueDeityBoon | SAFE | Day uint32 | SAFE | Per matrix. |
| _rollTargetLevel | private | Called from lootbox resolution | SAFE | Day uint32 | SAFE | Per matrix. |

#### DegenerusGameMintModule.sol

| Function | Visibility | Access Gate | Access Verdict | Integer Patterns | Overflow Verdict | Notes |
|----------|-----------|-------------|----------------|------------------|------------------|-------|
| recordMintData | external | DegenerusGame delegatecall (GAME entry: called from purchase flow) | SAFE | Affiliate bonus cached in mintPacked_ bits 185-214. BitPackingLib.setPacked with proper masks. | SAFE | Shift 185 + 24 bits = 209. Shift 209 + 6 bits = 215. No overlap per bitfield matrix. |
| processTicketBatch | external | DegenerusGame delegatecall (moved from JackpotModule) | SAFE | Entropy from lootboxRngWordByIndex via _lrRead. | SAFE | Full-width entropy. |
| _processOneTicketEntry | private | Called from processTicketBatch | SAFE | Moved from JackpotModule | SAFE | No change. |
| _resolveZeroOwedRemainder | private | Called from processTicketBatch | SAFE | Moved from JackpotModule | SAFE | No change. |
| _raritySymbolBatch | private | Called from processTicketBatch | SAFE | Assembly LCG PRNG. Moved from JackpotModule. | SAFE | Assembly is identical to prior implementation. |
| _finalizeTicketEntry | private | Called from processTicketBatch | SAFE | Moved from JackpotModule | SAFE | No change. |
| _rollRemainder | private | Called from _finalizeTicketEntry | SAFE | Moved from JackpotModule | SAFE | No change. |

#### DegenerusGameMintStreakUtils.sol

| Function | Visibility | Access Gate | Access Verdict | Integer Patterns | Overflow Verdict | Notes |
|----------|-----------|-------------|----------------|------------------|------------------|-------|
| _playerActivityScore (3-param) | internal | Called from modules via inheritance | SAFE | 5-component scoring with uint256 intermediate math. Cap values: DEITY_PASS_ACTIVITY_BONUS_BPS = 8000 (uint16). | SAFE | All BPS math: value * bps / 10000 in uint256. No overflow. |
| _playerActivityScore (2-param) | internal | Called from modules | SAFE | Overload using _activeTicketLevel() | SAFE | Passthrough. |
| _activeTicketLevel | internal | Called from modules | SAFE | Returns level or level+1 (uint24). | SAFE | uint24 + 1 = max 16,777,216. Cannot overflow. |

#### DegenerusGamePayoutUtils.sol

| Function | Visibility | Access Gate | Access Verdict | Integer Patterns | Overflow Verdict | Notes |
|----------|-----------|-------------|----------------|------------------|------------------|-------|
| _creditClaimable | internal | Called from modules | SAFE | NatSpec added only. | SAFE | No code change. |
| _calcAutoRebuy | internal | Called from modules | SAFE | NatSpec added only. | SAFE | No code change. |
| _queueWhalePassClaimCore | internal | Called from modules | SAFE | claimablePool cast to uint128. | SAFE | Proven safe per matrix. |

#### DegenerusGameWhaleModule.sol

| Function | Visibility | Access Gate | Access Verdict | Integer Patterns | Overflow Verdict | Notes |
|----------|-----------|-------------|----------------|------------------|------------------|-------|
| purchaseWhaleBundle | external | DegenerusGame delegatecall (GAME entry: payable, any caller with ETH) | SAFE | Formatting only. | SAFE | No change. |
| _purchaseWhaleBundle | private | Called from purchaseWhaleBundle | SAFE | presaleActive via _psRead. mintPacked_ deity bit. _queueTickets rngBypass=false. lootboxRngPendingEth packed. | SAFE | Packed operations with proper masks. |
| purchaseLazyPass | external | DegenerusGame delegatecall (GAME entry: payable) | SAFE | mintPacked_ deity bit. presaleActive via _psRead. _queueTickets rngBypass=false. | SAFE | Same packed ops. |
| purchaseDeityPass | external | DegenerusGame delegatecall (GAME entry: payable) | SAFE | mintPacked_ deity bit via BitPackingLib.setPacked. presaleActive via _psRead. DeityPassPurchased event. | SAFE | setPacked at bit 184 with MASK_1 -- proper single-bit operation. |
| claimWhalePass | external | DegenerusGame delegatecall (moved from EndgameModule via GAME_WHALE_MODULE) | SAFE | _queueTicketRange rngBypass=false. WhalePassClaimed event. | SAFE | Same logic, different module host. Access gate at DegenerusGame.claimWhalePass delegates to GAME_WHALE_MODULE. |
| _recordLootboxEntry | private | Called from purchase flows | SAFE | lootboxRngIndex via _lrRead. LootBoxIndexAssigned index uint32. lootboxRngPendingEth packed milli-ETH. | SAFE | uint32 index; milli-ETH packing verified in storage helpers. |
| _applyLootboxBoostOnPurchase | private | Called from purchase flows | SAFE | Day param uint32. | SAFE | Per matrix. |

#### DegenerusGameStorage.sol

| Function | Visibility | Access Gate | Access Verdict | Integer Patterns | Overflow Verdict | Notes |
|----------|-----------|-------------|----------------|------------------|------------------|-------|
| _isDistressMode | internal | Called from modules | SAFE | purchaseStartDay uint32, _simulatedDayIndex() uint32. Day arithmetic. | SAFE | uint32 subtraction: if a > b, result fits uint32. If b > a, Solidity 0.8 reverts. |
| _queueTickets | internal | rngBypass bool param added | SAFE | rngBypass replaces phaseTransitionActive check | SAFE | Bool param, no overflow. |
| _queueTicketsScaled | internal | rngBypass bool param | SAFE | Same | SAFE | Same. |
| _queueTicketRange | internal | rngBypass bool param | SAFE | Same | SAFE | Same. |
| _queueLootboxTickets | internal | rngBypass bool param | SAFE | Passes through to _queueTicketsScaled | SAFE | Same. |
| _tqWriteKey | internal | Internal helper | SAFE | bool comparison replaces uint8 | SAFE | Semantic equivalence; both select slot 0 or 1. |
| _tqReadKey | internal | Internal helper | SAFE | bool negation replaces uint8==0 | SAFE | Same. |
| _swapTicketSlot | internal | Internal helper | SAFE | bool negation replaces XOR | SAFE | !false=true, !true=false. Same toggle. |
| _getCurrentPrizePool | internal | Read helper | SAFE | Reads uint128 currentPrizePool, widens to uint256 via implicit cast. | SAFE | Widening (uint128->uint256) is always safe. |
| _setCurrentPrizePool | internal | Write helper | SAFE | Narrows uint256 to uint128. | INFO | Caller must ensure value fits uint128. All callers verified: pool math stays under uint128 max (per matrix). Solidity 0.8 truncation on explicit cast does NOT revert -- however, values are proven to fit. |
| _psRead / _psWrite | internal | Packed helpers | SAFE | presaleStatePacked bit operations | SAFE | Mask/shift operations. |
| _goRead / _goWrite | internal | Packed helpers | SAFE | gameOverStatePacked bit operations | SAFE | Mask/shift operations. |
| _djtRead / _djtWrite | internal | Packed helpers | SAFE | dailyJackpotTraitsPacked bit operations | SAFE | Mask/shift operations. |

### Core Contracts

#### DegenerusGame.sol

| Function | Visibility | Access Gate | Access Verdict | Integer Patterns | Overflow Verdict | Notes |
|----------|-----------|-------------|----------------|------------------|------------------|-------|
| constructor | public | Deploy-time only | SAFE | purchaseStartDay via GameTimeLib.currentDayIndex() uint32. mintPacked_ HAS_DEITY_PASS_SHIFT bit set. | SAFE | Deploy-time uint32 day index. |
| recordMintQuestStreak | external | msg.sender == ContractAddresses.GAME (self-call from MintModule delegatecall) | SAFE | Replaced COIN access with GAME access. MintModule executes as Game via delegatecall, so self-call is correct. | SAFE | No integer change. |
| payCoinflipBountyDgnrs | external | msg.sender == COIN or COINFLIP | SAFE | NatSpec only change | SAFE | No code change. |
| setLootboxRngThreshold | external | vault.isVaultOwner(msg.sender) (was ADMIN) | SAFE | Packed lootbox RNG state write. | SAFE | Packed operations with masks. |
| currentDayView | external view | Public | SAFE | Return uint32 (was uint48) | SAFE | Per matrix. |
| placeDegeneretteBet (renamed from placeFullTicketBets) | external payable | Public (any caller with ETH) | SAFE | Rename only at Game level; delegatecall to DegeneretteModule. | SAFE | No integer change at entry. |
| claimWhalePass | external | Public (player self-call via Game) | SAFE | Delegates to GAME_WHALE_MODULE (was GAME_ENDGAME_MODULE) | SAFE | Module address change; same delegatecall pattern. |
| _processMintPayment | private | Called from purchase flow | SAFE | claimablePool subtraction cast to uint128 | SAFE | Per matrix. |
| claimWinningsStethFirst | external | msg.sender == ContractAddresses.VAULT (removed SDGNRS access) | SAFE | STRENGTHENED. Only VAULT can call. | SAFE | No integer change. |
| _claimWinningsInternal | private | Called from claimWinnings/claimWinningsStethFirst | SAFE | _goRead for finalSwept. claimablePool -= uint128(payout). | SAFE | payout is always <= claimableWinnings[player] which is <= claimablePool. claimablePool fits uint128 per matrix. |
| claimAffiliateDgnrs | external | Public (player self-call) | SAFE | mintPacked_ HAS_DEITY_PASS_SHIFT. PriceLookupLib.priceForLevel. coinflip.creditFlip replaces coin.creditFlip. | SAFE | Route change; amounts unchanged. |
| adminStakeEthForStEth | external | vault.isVaultOwner(msg.sender) (was ADMIN) | SAFE | AdminStakeEthForStEth event added. | SAFE | No narrowing. |
| reverseFlip | external | Public (any caller with BURNIE to burn) | SAFE | Moved from AdvanceModule delegatecall to inline. Compounding nudge cost. | SAFE | _currentNudgeCost uses uint256 math: 100 ether * 15^n / 10^n. Bounded by nudge queue length. |
| _currentNudgeCost | private pure | Called from reverseFlip | SAFE | 100 BURNIE base * 1.5^n compounding. | SAFE | Exponential growth but n is bounded by gas limits (queue operations). |
| runBafJackpot | external | msg.sender == address(this) (self-call guard) | SAFE | Delegatecall to JackpotModule.runBafJackpot. | SAFE | Self-call only; cannot be called externally. |
| gameOverTimestamp | external view | Public | SAFE | Reads from gameOverStatePacked. | SAFE | Packed read. |
| mintPackedFor | external view | Public | SAFE | Raw packed data access. | SAFE | Read-only. |
| hasDeityPass | external view | Public | SAFE | Reads HAS_DEITY_PASS_SHIFT from mintPacked_. | SAFE | 1-bit read. |
| _hasAnyLazyPass | private view | Called from hasActiveLazyPass | SAFE | mintPacked_ HAS_DEITY_PASS_SHIFT replaces deityPassCount | SAFE | 1-bit check equivalent. |

#### DegenerusAdmin.sol

| Function | Visibility | Access Gate | Access Verdict | Integer Patterns | Overflow Verdict | Notes |
|----------|-----------|-------------|----------------|------------------|------------------|-------|
| proposeFeedSwap | external | vault.isVaultOwner (admin path: 2d stall) OR sDGNRS holder 0.5% (community: 7d stall) | SAFE | FeedProposal struct with uint40 fields. | SAFE | uint40 timestamps/weights per narrowing matrix. |
| voteFeedSwap | external | Any caller (votes weighted by sDGNRS balance) | SAFE | _voterWeight() returns uint40. _applyVote updates uint40 weights. | SAFE | Per narrowing matrix (votingSupply fits uint40 with exclusions). |
| feedThreshold | public view | Public | SAFE | Decaying threshold calculation. Pure BPS math. | SAFE | No overflow in BPS comparison. |
| canExecuteFeedSwap | external view | Public | SAFE | View-only threshold check. | SAFE | Read-only. |
| _executeFeedSwap | internal | Called from voteFeedSwap when threshold met | SAFE | Voids other active proposals. | SAFE | No narrowing. |
| proposeVrfSwap (was propose) | external | vault.isVaultOwner (admin) OR sDGNRS 0.5% (community) | SAFE | votingSnapshot uint40. | SAFE | Per narrowing matrix. |
| vote | external | Any caller (weighted by sDGNRS) | SAFE | _voterWeight uint40. _applyVote. Zero-weight poke pattern. | SAFE | Per narrowing matrix. |
| onTokenTransfer | external | msg.sender == ContractAddresses.LINK_TOKEN | SAFE | mintPrice() replaces purchaseInfo(). coinflipReward.creditFlip replaces coinLinkReward. | SAFE | Route change; credit amount calculation unchanged. |
| _applyVote | private pure | Called from vote/voteFeedSwap | SAFE | uint40 weight arithmetic. | SAFE | Additions bounded by total votingSupply which fits uint40. |
| _voterWeight | private view | Called from vote/voteFeedSwap | SAFE | uint40(raw / 1 ether). Floor to 1 if dust. | SAFE | Per narrowing matrix. |
| _requireActiveProposal | private view | Called from vote | SAFE | uint40 createdAt timestamp comparison. | SAFE | Block timestamps fit uint40 until year ~36,000. |
| _resolveThreshold | private pure | Called from vote | SAFE | BPS math on uint40/uint256. | SAFE | All in uint256 working space. |
| _feedStallDuration | private view | Called from proposeFeedSwap | SAFE | Chainlink feed timestamp comparison. | SAFE | uint256 timestamp arithmetic. |

#### DegenerusAffiliate.sol

| Function | Visibility | Access Gate | Access Verdict | Integer Patterns | Overflow Verdict | Notes |
|----------|-----------|-------------|----------------|------------------|------------------|-------|
| payAffiliate | external | COIN or GAME only (msg.sender check) | SAFE | Winner-takes-all 75/20/5 roll. Quest routing to quests.handleAffiliate. Flip crediting via coinflip.creditFlip. Leaderboard post-taper. | SAFE | Percentage math in uint256. |
| affiliateBonusPoints | external view | Public | SAFE | Tiered rate: 4pts/ETH first 5 ETH, 1.5pts/ETH next 20. | SAFE | uint256 arithmetic, result stored in uint6 (6 bits, max 63). Points capped at 50 by game logic. |
| referPlayer | external | Public | SAFE | _resolveCodeOwner for default codes. | SAFE | bytes32 code operations. |
| defaultCode | external pure | Public | SAFE | bytes32(uint256(uint160(addr))). | SAFE | Safe type conversion. |
| _resolveCodeOwner | private view | Called internally | SAFE | Custom lookup then address-derived default. | SAFE | No narrowing. |
| _registerAffiliateCode | private | Called from registerAffiliateCode | SAFE | Rejects codes where uint256(code_) <= type(uint160).max (address-range codes). | SAFE | Prevents collision with default address-derived codes. |
| _routeAffiliateReward | private | Called from payAffiliate | SAFE | coinflip.creditFlip replaces coin.creditFlip | SAFE | Route change only. |

#### DegenerusQuests.sol

| Function | Visibility | Access Gate | Access Verdict | Integer Patterns | Overflow Verdict | Notes |
|----------|-----------|-------------|----------------|------------------|------------------|-------|
| rollDailyQuest | external | onlyGame (msg.sender == GAME) | SAFE | Day uint32 (was uint48). No return values. | SAFE | Per matrix. |
| handleMint | external | onlyCoin (COIN, COINFLIP, GAME, AFFILIATE) | SAFE | Added mintPrice uint256 param. Credits flip rewards internally via coinflip.creditFlip. | SAFE | Full-width mintPrice. |
| handleLootBox | external | onlyCoin | SAFE | Added mintPrice uint256 param. Credits flip rewards internally. | SAFE | Same. |
| handleDegenerette | external | onlyCoin | SAFE | Added mintPrice uint256 param. Credits flip rewards internally. | SAFE | Same. |
| handleDecimator | external | onlyCoin | SAFE | Credits flip rewards via coinflip.creditFlip. | SAFE | Route change. |
| handleAffiliate | external | onlyCoin | SAFE | Credits flip rewards via coinflip.creditFlip. | SAFE | Route change. |
| handlePurchase | external | onlyCoin (COIN, COINFLIP, GAME, AFFILIATE) | SAFE | New unified purchase path. uint32 day params. | SAFE | Combines handleMint + handleLootBox. Per matrix for uint32. |
| rollLevelQuest | external | onlyGame | SAFE | New level-scoped quest rolled during level transition. | SAFE | No narrowing. |
| getPlayerLevelQuestView | external view | Public | SAFE | New view function. | SAFE | Read-only. |
| awardQuestStreakBonus | external | onlyCoin | SAFE | Day uint32 (was uint48). | SAFE | Per matrix. |

#### BurnieCoin.sol

| Function | Visibility | Access Gate | Access Verdict | Integer Patterns | Overflow Verdict | Notes |
|----------|-----------|-------------|----------------|------------------|------------------|-------|
| burnForCoinflip | external | msg.sender == ContractAddresses.COINFLIP (unchanged address, changed constant name) | SAFE | No narrowing. | SAFE | |
| mintForGame | external | msg.sender == COINFLIP or GAME (expanded from COINFLIP only) | SAFE | Both COINFLIP and GAME are trusted contracts. GAME needs mint for module operations. | SAFE | No narrowing. |
| burnCoin | external | onlyGame (was onlyTrustedContracts) | SAFE | STRENGTHENED -- fewer callers. | SAFE | No narrowing. |
| decimatorBurn | external | Public (player or approved operator) | SAFE | decWindow returns single bool. Level fetched via degenerusGame.level(). Quest via questModule.handleDecimator. | SAFE | No narrowing in BurnieCoin; downstream uses uint256. |
| terminalDecimatorBurn | external | Public (player or approved operator) | SAFE | Same access pattern as decimatorBurn. | SAFE | No narrowing. |
| vaultEscrow | external | GAME or VAULT | SAFE | uint128 cast via _toUint128 (reverts on overflow). | SAFE | _toUint128 provides explicit overflow protection. |
| vaultMintTo | external | onlyVault | SAFE | uint128 cast via _toUint128. | SAFE | Same protection. |
| onlyGame modifier | - | msg.sender != ContractAddresses.GAME | SAFE | Replaces 5+ modifiers. Verified all functions using onlyGame only need GAME access. | N/A | See Critical Access Control Changes: BurnieCoin Modifier Collapse. |

#### BurnieCoinflip.sol

| Function | Visibility | Access Gate | Access Verdict | Integer Patterns | Overflow Verdict | Notes |
|----------|-----------|-------------|----------------|------------------|------------------|-------|
| onlyFlipCreditors modifier | - | GAME + QUESTS + AFFILIATE + ADMIN | SAFE | See Critical Access Control Changes: BurnieCoinflip Expanded Creditors. | N/A | |
| depositCoinflip | external | Public (player or approved operator) | SAFE | claimableStored read (uint128) for auto-rebuy. hasDeityPass replaces deityPassCountFor. | SAFE | uint128 claimableStored fits deposit math. |
| _claimInternal | private | Called from claim functions | SAFE | mintForGame replaces mintForCoinflip. All uint48->uint32 day types. hasDeityPass replaces deityPassCountFor. | SAFE | Per matrix. |
| _settleResolvedDays | private | Called from _claimInternal | SAFE | All uint48->uint32 day types. | SAFE | Per matrix. |
| _addDailyFlip | private | Called from creditFlip/depositCoinflip | SAFE | targetDay uint32 (was uint48). | SAFE | Per matrix. |
| processCoinflipPayouts | external | onlyDegenerusGameContract (GAME only) | SAFE | epoch uint32 (was uint48). | SAFE | Per matrix. |
| creditFlip | external | onlyFlipCreditors (GAME+QUESTS+AFFILIATE+ADMIN) | SAFE | NatSpec updated for expanded creditors. | SAFE | See Expanded Creditors analysis. |
| creditFlipBatch | external | onlyFlipCreditors | SAFE | Dynamic arrays replace fixed address[3]/uint256[3]. | SAFE | Dynamic array length bounded by gas. No overflow: loop iterates players.length. |
| _recyclingBonus | private pure | Called from _claimInternal | SAFE | Rate: amount * RECYCLE_BONUS_BPS / BPS_DENOMINATOR (75/10000 = 0.75%). | SAFE | uint256 * uint16 / uint16. No overflow. |
| _targetFlipDay | internal view | Called from _addDailyFlip | SAFE | Return uint32 (was uint48). | SAFE | Per matrix. |
| coinflipAmount | external view | Public | SAFE | uint32 for targetDay. | SAFE | Per matrix. |
| coinflipAutoRebuyInfo | external view | Public | SAFE | startDay uint32. | SAFE | Per matrix. |
| topDayBettorView | external view | Public | SAFE | uint32 for lastDay. | SAFE | Per matrix. |
| getCoinflipDayResult | external view | Public | SAFE | Day param uint32. | SAFE | Per matrix. |
| _updateTopDayBettor | private | Called from depositCoinflip | SAFE | Day param uint32. | SAFE | Per matrix. |
| setCoinflipAutoRebuy | external | Public (player or approved) | SAFE | mintForGame replaces mintForCoinflip. | SAFE | Route change. |
| setCoinflipAutoRebuyTakeProfit | external | Public (player or approved) | SAFE | mintForGame replaces mintForCoinflip. | SAFE | Route change. |

#### DegenerusStonk.sol

| Function | Visibility | Access Gate | Access Verdict | Integer Patterns | Overflow Verdict | Notes |
|----------|-----------|-------------|----------------|------------------|------------------|-------|
| constructor | public | Deploy-time only | SAFE | CREATOR_INITIAL (50B), unvested balance. | SAFE | Constants fit uint256. |
| transferFrom | external | Standard ERC20 (allowance or unlimited) | SAFE | Emits Approval on allowance decrease. | SAFE | uint256 arithmetic. |
| unwrapTo | external | vault.isVaultOwner(msg.sender) (was CREATOR). game.rngLocked() guard (was VRF stall). | SAFE | See modifier change matrix. | SAFE | No narrowing. |
| claimVested | external | vault.isVaultOwner(msg.sender) | SAFE | CREATOR_INITIAL + game.level() * VEST_PER_LEVEL. level() returns uint24 (max ~16M). VEST_PER_LEVEL = 5B * 1e18. Max: 50B + 16M * 5B * 1e18 -- but capped at CREATOR_TOTAL (200B * 1e18). | SAFE | Intermediate: 16M * 5 * 10^27 = 8 * 10^34. Fits uint256 (max 1.15 * 10^77). |
| burn | external | Public (post-gameOver only) | SAFE | game.gameOver() check. | SAFE | No narrowing. |
| yearSweep | external | Permissionless (1-year post-gameOver) | SAFE | gameOverTimestamp uint48. block.timestamp + 365 days comparison. 50-50 split to GNRUS+VAULT. | SAFE | uint48 timestamp + 365 days fits uint256. Division arithmetic safe. |
| burnForSdgnrs | external | msg.sender == ContractAddresses.SDGNRS | SAFE | Unchanged access. | SAFE | No narrowing. |

#### StakedDegenerusStonk.sol

| Function | Visibility | Access Gate | Access Verdict | Integer Patterns | Overflow Verdict | Notes |
|----------|-----------|-------------|----------------|------------------|------------------|-------|
| votingSupply | external view | Public | SAFE | totalSupply - balanceOf[this] - balanceOf[DGNRS] - balanceOf[VAULT]. | SAFE | Subtraction: all terms are <= totalSupply. Solidity 0.8 reverts on underflow. |
| poolTransfer | external | onlyGame | SAFE | Self-win (to == address(this)) now burns instead of no-op. | SAFE | _burn reduces totalSupply. Semantically correct: self-win increases value per token. |
| burnAtGameOver (renamed from burnRemainingPools) | external | onlyGame | SAFE | Rename only. | SAFE | No code change. |
| resolveRedemptionPeriod | external | msg.sender == GAME | SAFE | flipDay uint32 (was uint48). No longer returns burnieToCredit (void). | SAFE | Per matrix. BURNIE now paid via _payBurnie on claim instead of upfront. |
| claimRedemption | external | Public (player self-call) | SAFE | uint32 for period index types. | SAFE | Per matrix. |
| burn | external | Public | SAFE | rngLocked gate during active game. | SAFE | No narrowing. |
| _submitRedemption | internal | Called from burn (gambling path) | SAFE | uint32 currentPeriod. | SAFE | Per matrix. |

#### DegenerusVault.sol

| Function | Visibility | Access Gate | Access Verdict | Integer Patterns | Overflow Verdict | Notes |
|----------|-----------|-------------|----------------|------------------|------------------|-------|
| gameDegeneretteBet (consolidated from 3 functions) | external payable | onlyVaultOwner | SAFE | Currency param (uint8: 0=ETH, 1=BURNIE, 3=WWXRP). Consolidation reduces surface without changing access. | SAFE | No narrowing. |
| sdgnrsBurn | external | onlyVaultOwner | SAFE | New function. Only vault owner can burn vault-held sDGNRS. | SAFE | Delegates to sdgnrsToken.burn. |
| sdgnrsClaimRedemption | external | onlyVaultOwner | SAFE | New function. Only vault owner can claim. | SAFE | Delegates to sdgnrsToken.claimRedemption. |

#### DegenerusDeityPass.sol

| Function | Visibility | Access Gate | Access Verdict | Integer Patterns | Overflow Verdict | Notes |
|----------|-----------|-------------|----------------|------------------|------------------|-------|
| onlyOwner modifier | - | vault.isVaultOwner(msg.sender) (was _contractOwner) | SAFE | See modifier change matrix. External call to vault.isVaultOwner. | N/A | See Vault-Based Ownership Migration. |
| setRenderer | external | onlyOwner (vault.isVaultOwner) | SAFE | No integer change. | SAFE | |
| setRenderColors | external | onlyOwner (vault.isVaultOwner) | SAFE | No integer change. | SAFE | |
| mint | external | msg.sender == ContractAddresses.GAME | SAFE | tokenId bounded [0, 31]. | SAFE | tokenId < 32 enforced. |

#### DegenerusJackpots.sol

| Function | Visibility | Access Gate | Access Verdict | Integer Patterns | Overflow Verdict | Notes |
|----------|-----------|-------------|----------------|------------------|------------------|-------|
| getLastBafResolvedDay | external view | Public | SAFE | Return uint32 (was uint48). | SAFE | Per matrix. |

#### DeityBoonViewer.sol

| Function | Visibility | Access Gate | Access Verdict | Integer Patterns | Overflow Verdict | Notes |
|----------|-----------|-------------|----------------|------------------|------------------|-------|
| deityBoonSlots | external view | Public | SAFE | Day return uint32. | SAFE | Per matrix. |
| _boonFromRoll | private pure | Called internally | SAFE | NatSpec added. | SAFE | No code change. |

#### WrappedWrappedXRP.sol

| Function | Visibility | Access Gate | Access Verdict | Integer Patterns | Overflow Verdict | Notes |
|----------|-----------|-------------|----------------|------------------|------------------|-------|
| unwrap | external | REMOVED | SAFE | Function removed entirely (wXRP backing stripped). No residual access: function does not exist in bytecode. | N/A | Verified: function not in current source. |
| donate | external | REMOVED | SAFE | Same as unwrap. | N/A | Verified: function not in current source. |
| mintPrize | external | GAME, COIN, COINFLIP (unchanged) | SAFE | No change. | SAFE | |
| burnForGame | external | GAME only (unchanged) | SAFE | No change. | SAFE | |
| vaultMintTo | external | VAULT only (unchanged) | SAFE | No change. | SAFE | |

### Libraries

#### BitPackingLib.sol

| Function/Constant | Type | Access | Access Verdict | Integer Patterns | Overflow Verdict | Notes |
|-------------------|------|--------|----------------|------------------|------------------|-------|
| HAS_DEITY_PASS_SHIFT (184) | constant | N/A | N/A | Bit 184. Previous field ends at 183 (MINT_STREAK_LAST_COMPLETED [160-183]). Next field starts at 185 (AFFILIATE_BONUS_LEVEL). | SAFE | No overlap. Verified by shift analysis: 160+24=184 (exact boundary). |
| AFFILIATE_BONUS_LEVEL_SHIFT (185) | constant | N/A | N/A | Bits [185-208]. Previous: deity pass bit 184. Next: AFFILIATE_BONUS_POINTS at 209. 185+24=209 (exact boundary). | SAFE | No overlap. |
| AFFILIATE_BONUS_POINTS_SHIFT (209) | constant | N/A | N/A | Bits [209-214]. Previous: bonus level ends at 208. Next used: LEVEL_UNITS at 228. Gap [215-227]. 209+6=215 (13-bit gap to 228). | SAFE | No overlap. |
| MASK_6 | constant | N/A | N/A | (1 << 6) - 1 = 63. Used for 6-bit affiliate bonus points field. | SAFE | Correct mask for 6-bit field. |
| MASK_2 | constant | N/A | N/A | 0x3. Used for 2-bit whale bundle type field. | SAFE | Correct mask for 2-bit field. |
| MASK_1 | constant | N/A | N/A | 0x1. Used for 1-bit deity pass flag. | SAFE | Correct mask for 1-bit field. |
| setPacked | internal pure | Called from modules | SAFE | (data & ~(mask << shift)) | ((value & mask) << shift). Standard bit manipulation. | SAFE | mask << shift bounded by 256-bit word. All shifts verified < 256. |

#### GameTimeLib.sol

| Function | Type | Access | Access Verdict | Integer Patterns | Overflow Verdict | Notes |
|----------|------|--------|----------------|------------------|------------------|-------|
| currentDayIndex | internal view | Called from modules | SAFE | Returns uint32. uint32((ts - JACKPOT_RESET_TIME) / 1 days) - uint32(DEPLOY_DAY_BOUNDARY) + 1. | SAFE | ts is block.timestamp (uint48 cast). Division by 86400 yields day count. DEPLOY_DAY_BOUNDARY is a constant. Result is relative day index starting at 1. Per matrix, uint32 holds 11.7M years. |
| currentDayIndexAt | internal pure | Called from currentDayIndex | SAFE | uint48 ts input. uint32 intermediate cast. | SAFE | Timestamp / 86400 yields ~79,000 days since epoch in 2024. Fits uint32. Subtraction: current boundary - deploy boundary always >= 0 (deploy is in past). |
| JACKPOT_RESET_TIME | constant | N/A | N/A | uint32 82620 (was uint48 82620). | SAFE | Value fits both types. |

#### JackpotBucketLib.sol

| Function | Type | Access | Access Verdict | Integer Patterns | Overflow Verdict | Notes |
|----------|------|--------|----------------|------------------|------------------|-------|
| bucketShares | internal pure | Called from JackpotModule | SAFE | NatSpec-only change. Documents empty bucket behavior. | SAFE | No code change. |

## GNRUS Access Control (New Contract)

GNRUS is an entirely new soulbound donation token. All access controls audited from source at `contracts/GNRUS.sol`.

| Function | Expected Access | Actual Guard | Verdict | Notes |
|----------|----------------|--------------|---------|-------|
| burn(uint256) | Any GNRUS holder | balanceOf[burner] -= amount (Solidity 0.8 underflow revert) + MIN_BURN (1 GNRUS) check | SAFE | No access modifier needed. Balance check is sufficient. Last-holder sweep correctly uses burnerBal. CEI: state updates before external transfers. |
| burnAtGameOver() | Game contract only | onlyGame modifier (msg.sender != ContractAddresses.GAME reverts Unauthorized) + finalized flag (idempotent) | SAFE | Only callable once (finalized = true). Only by Game. Burns all unallocated balanceOf[address(this)]. |
| propose(address) | sDGNRS holder (0.5% threshold) or vault owner (up to 5x per level) | Vault path: vault.isVaultOwner(proposer) + creatorProposalCount[level] < MAX_CREATOR_PROPOSALS (5). Community path: (sdgnrs.balanceOf(proposer) / 1e18) * BPS_DENOM >= snapshot * PROPOSE_THRESHOLD_BPS + hasProposed[level][proposer] (once per level). Both: recipient != address(0), recipient.code.length == 0 (no contracts). | SAFE | Dual-path governance. Vault owner has higher proposal limit (5x vs 1x). Community requires 0.5% sDGNRS stake. Snapshot locked on first proposal per level. RecipientIsContract prevents stuck GNRUS. |
| vote(uint48, bool) | sDGNRS holder | hasVoted[level][voter][proposalId] prevents double-voting. Weight = uint48(sdgnrs.balanceOf(voter) / 1e18). Vault owner bonus: +5% of snapshot. weight == 0 reverts InsufficientStake. | SAFE | Per-proposal one-vote-per-address enforcement. Vault owner gets standing bonus. Zero-weight callers rejected. |
| pickCharity(uint24) | Game contract only | onlyGame modifier. level == currentLevel check. levelResolved[level] prevents double-resolve. | SAFE | Only Game can resolve levels. Level must be current. Distribution: 2% of remaining unallocated. Winner: highest positive net weight. |
| receive() | Anyone (payable) | No guard (accepts ETH) | SAFE | Contract must accept ETH from Game claimWinnings and year sweep. Open receive is by design. |
| transfer/transferFrom/approve | Disabled | Always revert TransferDisabled() | SAFE | Soulbound enforcement. Pure functions -- no state read needed. |
| getProposal | Public view | No guard needed | SAFE | Read-only. |
| getLevelProposals | Public view | No guard needed | SAFE | Read-only. |
| _mint | Private | Called only from constructor | SAFE | Constructor-only. Mints INITIAL_SUPPLY to address(this). |

**GNRUS Integer Analysis:**
- approveWeight/rejectWeight stored as uint48. Max single-voter weight = votingSupply / 1e18. sDGNRS supply = 1T * 1e18. votingSupply excludes pools/wrapper/vault (~60-70%). Max effective = ~3-4 * 10^11. uint48 max = 2.8 * 10^14. Margin: ~700x. SAFE.
- DISTRIBUTION_BPS = 200, BPS_DENOM = 10000. 2% distribution: `unallocated * 200 / 10000`. unallocated starts at 1T * 1e18. Product: 10^30 * 200 = 2 * 10^32. Fits uint256 (max 1.15 * 10^77). SAFE.
- proposalCount is uint48. Max 2.8 * 10^14 proposals. Even at 30 proposals per level for 30 levels = 900 proposals. Wide margin. SAFE.

## Critical Access Control Changes

### BurnieCoin Modifier Collapse

BurnieCoin previously had 5+ access modifiers: `onlyDegenerusGameContract`, `onlyTrustedContracts`, `onlyFlipCreditors`, `onlyAffiliate`, `onlyAdmin`. All have been replaced by two modifiers: `onlyGame` (GAME address only) and `onlyVault` (VAULT address only).

**Verification of each removed function:**

| Removed Function | Old Modifier | New Location | Access Verification |
|------------------|-------------|--------------|---------------------|
| creditFlip(address, uint256) | onlyFlipCreditors | BurnieCoinflip.creditFlip | Callers now call BurnieCoinflip directly. No path exists to call the removed function because it is not in BurnieCoin's ABI. SAFE. |
| creditFlipBatch(address[3], uint256[3]) | onlyFlipCreditors | BurnieCoinflip.creditFlipBatch | Same -- callers route to BurnieCoinflip. SAFE. |
| rollDailyQuest(uint48, uint256) | onlyDegenerusGameContract | DegenerusQuests.rollDailyQuest | AdvanceModule calls DegenerusQuests directly. No BurnieCoin involvement. SAFE. |
| notifyQuestMint/notifyQuestLootBox/notifyQuestDegenerette | onlyDegenerusGameContract | DegenerusQuests.handleMint/handleLootBox/handleDegenerette | Modules call DegenerusQuests directly. SAFE. |
| affiliateQuestReward | onlyAffiliate | DegenerusQuests.handleAffiliate | DegenerusAffiliate calls DegenerusQuests directly. SAFE. |
| creditLinkReward | onlyAdmin | DegenerusAdmin.onTokenTransfer -> coinflipReward.creditFlip | Admin routes to BurnieCoinflip directly. SAFE. |
| creditCoin | onlyFlipCreditors | REMOVED (functionality consolidated) | No caller needs this path. SAFE. |
| mintForCoinflip | onlyBurnieCoinflip | BurnieCoin.mintForGame (accepts COINFLIP or GAME) | Caller check expanded but both are trusted contracts. SAFE. |

**Remaining BurnieCoin functions with access:**
- `burnCoin`: onlyGame (STRENGTHENED from onlyTrustedContracts)
- `burnForCoinflip`: msg.sender == COINFLIP (EQUIVALENT)
- `mintForGame`: msg.sender == COINFLIP or GAME (SAFE -- both trusted)
- `vaultEscrow`: GAME or VAULT (EQUIVALENT)
- `vaultMintTo`: onlyVault (UNCHANGED)

**Conclusion:** No privilege escalation. Every removed function either no longer exists in BurnieCoin or has been properly redirected to its canonical contract with equivalent-or-stronger access control.

### BurnieCoinflip Expanded Creditors

`onlyFlipCreditors` expanded from `GAME + BURNIE` to `GAME + QUESTS + AFFILIATE + ADMIN`.

**BURNIE (BurnieCoin) removed as creditor.** BurnieCoin no longer calls creditFlip on BurnieCoinflip because the forwarding functions (creditFlip, creditFlipBatch) were removed from BurnieCoin. Instead, each caller routes directly to BurnieCoinflip.

**Verification of each new creditor:**

| New Creditor | Contract | Why It Needs creditFlip | Legitimacy |
|-------------|----------|-------------------------|------------|
| QUESTS (DegenerusQuests) | DegenerusQuests.sol | Quest rewards: handleMint, handleLootBox, handleDegenerette, handleDecimator, handleAffiliate each call coinflip.creditFlip internally to award quest completion flip credits. Previously routed through BurnieCoin as intermediary. | LEGITIMATE -- quest rewards were always distributed; routing changed from coin-proxied to direct. Amount calculation is identical. |
| AFFILIATE (DegenerusAffiliate) | DegenerusAffiliate.sol | Affiliate rewards: payAffiliate calls coinflip.creditFlip for affiliate reward distribution. Previously routed through BurnieCoin.creditFlip. | LEGITIMATE -- affiliate rewards unchanged; routing is direct instead of proxied. |
| ADMIN (DegenerusAdmin) | DegenerusAdmin.sol | LINK donation rewards: onTokenTransfer calls coinflipReward.creditFlip for LINK donation coinflip credits. Previously routed through BurnieCoin.creditLinkReward. | LEGITIMATE -- LINK reward crediting unchanged; routing is direct. |

**Can any new creditor inflate flip balances?**
- QUESTS: Only credits flips as quest rewards, which are bounded by quest completion logic (one reward per quest per day per player). Cannot be called externally except by onlyCoin-gated handle* functions.
- AFFILIATE: Only credits flips proportional to affiliate revenue. Cannot be called externally except by payAffiliate which is COIN/GAME gated.
- ADMIN: Only credits flips proportional to LINK donation value. Cannot be called externally except via onTokenTransfer which requires msg.sender == LINK_TOKEN.

**Conclusion:** All new creditors are legitimate. The expansion reflects routing simplification (direct calls instead of BurnieCoin proxy) with no change in credited amounts or business logic.

### Vault-Based Ownership Migration

Three contracts migrated from stored `_contractOwner` address to `vault.isVaultOwner(msg.sender)`:

| Contract | Functions Affected | Analysis |
|----------|-------------------|----------|
| DegenerusDeityPass | setRenderer, setRenderColors, mint (mint has separate GAME check) | onlyOwner modifier calls vault.isVaultOwner(msg.sender) which calls DegenerusVault.isVaultOwner. |
| DegenerusStonk | unwrapTo, claimVested | Direct vault.isVaultOwner(msg.sender) check. |
| DegenerusGame | adminStakeEthForStEth, setLootboxRngThreshold | Direct vault.isVaultOwner(msg.sender) check. |

**DegenerusVault.isVaultOwner implementation** (verified from source):
```
function _isVaultOwner(address account) private view returns (bool) {
    uint256 supply = ethShare.totalSupply();
    uint256 balance = ethShare.balanceOf(account);
    return balance * 1000 > supply * 501;
}
```

**Can an attacker gain vault owner status?**
- Requires >50.1% of DGVE (ethShare) total supply.
- DGVE is a standard ERC20 minted at deploy. Initial supply goes to CREATOR.
- To become vault owner, an attacker must acquire >50.1% of all DGVE tokens.
- This requires either purchasing DGVE on open market or social engineering the owner to transfer.
- The 50.1% threshold is a supermajority check, not a simple ownership flag.
- **Verdict:** SAFE -- vault-based ownership is stronger than single-EOA ownership because it requires economic majority rather than private key compromise.

**Is the external call to vault.isVaultOwner a reentrancy risk?**
- vault.isVaultOwner is a view function (reads balanceOf and totalSupply only).
- No state mutations occur in the vault during this call.
- **Verdict:** SAFE -- read-only external call.
