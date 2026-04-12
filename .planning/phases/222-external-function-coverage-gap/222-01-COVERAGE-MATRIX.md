# Phase 222 Plan 01 — External Function Coverage Matrix

**Date:** 2026-04-12
**Scope:** Every external / public function on every deployable `.sol` contract in `contracts/` excluding `contracts/interfaces/`, `contracts/libraries/`, `contracts/storage/`, `contracts/mocks/` per D-05. Top-level libraries / data-only (`ContractAddresses.sol`, `DegenerusTraitUtils.sol`) and the two `abstract contract` module utilities (`DegenerusGameMintStreakUtils.sol`, `DegenerusGamePayoutUtils.sol`) are excluded. The dead `GAME_ENDGAME_MODULE` address constant is excluded (dead, flagged in Phase 220). `Icons32Data.sol` IS deployable (not a library) and is included. Deployable universe: 15 top-level contracts + 9 active modules = **24 deployable contracts**.
**Method:** (1) `forge coverage --report summary --ir-minimum` produces per-file coverage stats (CSI-09 headline, committed verbatim as `222-01-COVERAGE-SUMMARY.txt`). The `--ir-minimum` workaround is required because the default `via_ir = true` profile triggers "stack too deep" errors when the Foundry coverage instrumenter disables `via_ir` for accuracy. Per Foundry docs, `--ir-minimum` may produce slightly imprecise source mappings, so the branch thresholds here should be revisited if per-function coverage is needed. (2) Per-function classifications use file-level branch coverage as the D-08 threshold signal because per-function `FNDA` data requires lcov granularity that was not feasible in this single-invocation build under the pre-existing test-infrastructure state.
**Test infrastructure state at matrix generation:** 250 tests passed, 117 failed. Most failures revert with `OnlyGame()` because `DegenerusGameAdvanceModule._emitDailyWinningTraits` uses `.delegatecall` to `DegenerusGameJackpotModule.emitDailyWinningTraits` while the target function checks `msg.sender == ContractAddresses.GAME` — but in a delegatecall chain `msg.sender` is the original caller (the test contract), not GAME. This is a pre-existing issue; its fix is out of scope for Plan 222-01 (D-03 no-contract-edits). CRITICAL_GAP counts below reflect real reachability under the current test suite.

## Summary

| Metric | Count |
|--------|------:|
| Deployable contracts classified | 24 |
| External/public functions classified (rows) | 308 |
| COVERED | 0 |
| CRITICAL_GAP | 196 |
| EXEMPT | 112 |

CRITICAL_GAP = 64% of external surface (196 of 308 functions). Plan 222-02 will close these gaps with integration-style tests on natural caller chains (D-13/D-14/D-15).

## Method Notes

- **Coverage data source:** `forge coverage --report summary --ir-minimum` (captured verbatim as `222-01-COVERAGE-SUMMARY.txt`). The `--ir-minimum` workaround is required because the default profile's `via_ir = true` triggers "stack too deep" errors when Foundry's coverage instrumenter disables `via_ir` for accuracy. This matrix should be regenerated when coverage runs cleanly on the default profile.
- **Classification threshold (D-08):** 50% file-level branch coverage. Per-function branch data would require lcov parsing; with the summary file's per-file `% Branches` column as the available granularity, we apply the D-08 threshold at file scope. Per-function refinement is tractable once lcov.info is parsed — left to Plan 222-02 when it consumes the matrix for its `scripts/coverage-check.sh` gate.
- **Exemption scope restricted to D-11/D-12 per D-09:** Admin-gated / onlyOwner / onlyAdmin / emergency / pause-gated functions are NOT auto-exempt — they remain CRITICAL_GAP until a test invokes them with ≥50% branch coverage.
- **`view`/`pure`:** EXEMPT via D-11 with rationale "D-11: view/pure".
- **`rawFulfillRandomWords`, `onTokenTransfer`, `fallback`, `receive`:** EXEMPT via D-12 (external-callback targets).
- **Constructor rows:** excluded (not external runtime surface per D-05/D-06 intent).
- **Dead `GAME_ENDGAME_MODULE`:** excluded (Phase 220 flagged as dead).
- **Pre-existing test infrastructure issue:** 117 of 367 tests fail with `OnlyGame()` reverts because `DegenerusGameAdvanceModule._emitDailyWinningTraits` uses `.delegatecall` to `DegenerusGameJackpotModule.emitDailyWinningTraits` which checks `msg.sender == ContractAddresses.GAME`. In delegatecall, `msg.sender` is the top-level caller (the test contract), so the check fails. This pre-existing production issue (D-03 forbids fixing it in Plan 222-01) artificially inflates the CRITICAL_GAP count — Plan 222-02 will need to either work around it (e.g., self-call via `IDegenerusGame(address(this)).emitDailyWinningTraits`) or request a contract edit.

## Contract Sections

### Contract: `contracts/BurnieCoin.sol`

**Deployable:** yes.
**File-level branch coverage:** 7.14% (3/42).
**File-level function coverage:** 40.00% (10/25).

| Function (signature) | Visibility | Verdict | Branch Cov | Test Ref | Notes |
|----------------------|------------|---------|-----------:|----------|-------|
| `balanceOfWithClaimable(address player) external view returns (uint256 spendable)` | external view | EXEMPT | — | — | D-11: view/pure |
| `totalSupply() external view returns (uint256)` | external view | EXEMPT | — | — | D-11: view/pure |
| `supplyIncUncirculated() external view returns (uint256)` | external view | EXEMPT | — | — | D-11: view/pure |
| `vaultMintAllowance() external view returns (uint256)` | external view | EXEMPT | — | — | D-11: view/pure |
| `approve(address spender, uint256 amount) external returns (bool)` | external | CRITICAL_GAP | 7.14% (3/42) | (none) | file branch coverage <50% per summary |
| `transfer(address to, uint256 amount) external returns (bool)` | external | CRITICAL_GAP | 7.14% (3/42) | (none) | file branch coverage <50% per summary |
| `transferFrom( address from, address to, uint256 amount ) external returns (bool)` | external | CRITICAL_GAP | 7.14% (3/42) | (none) | file branch coverage <50% per summary |
| `burnForCoinflip(address from, uint256 amount) external` | external | CRITICAL_GAP | 7.14% (3/42) | (none) | file branch coverage <50% per summary |
| `mintForGame(address to, uint256 amount) external` | external | CRITICAL_GAP | 7.14% (3/42) | (none) | file branch coverage <50% per summary |
| `vaultEscrow(uint256 amount) external` | external | CRITICAL_GAP | 7.14% (3/42) | (none) | file branch coverage <50% per summary |
| `vaultMintTo(address to, uint256 amount) external onlyVault` | external | CRITICAL_GAP | 7.14% (3/42) | (none) | file branch coverage <50% per summary |
| `burnCoin( address target, uint256 amount ) external onlyGame` | external | CRITICAL_GAP | 7.14% (3/42) | (none) | file branch coverage <50% per summary |
| `decimatorBurn(address player, uint256 amount) external` | external | CRITICAL_GAP | 7.14% (3/42) | (none) | file branch coverage <50% per summary |
| `terminalDecimatorBurn(address player, uint256 amount) external` | external | CRITICAL_GAP | 7.14% (3/42) | (none) | file branch coverage <50% per summary |

### Contract: `contracts/BurnieCoinflip.sol`

**Deployable:** yes.
**File-level branch coverage:** 35.71% (40/112).
**File-level function coverage:** 59.46% (22/37).

| Function (signature) | Visibility | Verdict | Branch Cov | Test Ref | Notes |
|----------------------|------------|---------|-----------:|----------|-------|
| `settleFlipModeChange(address player) external onlyDegenerusGameContract` | external | CRITICAL_GAP | 35.71% (40/112) | (none) | file branch coverage <50% per summary |
| `depositCoinflip(address player, uint256 amount) external` | external | CRITICAL_GAP | 35.71% (40/112) | (none) | file branch coverage <50% per summary |
| `claimCoinflips( address player, uint256 amount ) external returns (uint256 claimed)` | external | CRITICAL_GAP | 35.71% (40/112) | (none) | file branch coverage <50% per summary |
| `claimCoinflipsFromBurnie( address player, uint256 amount ) external onlyBurnieCoin returns (uint256 claimed)` | external | CRITICAL_GAP | 35.71% (40/112) | (none) | file branch coverage <50% per summary |
| `claimCoinflipsForRedemption( address player, uint256 amount ) external returns (uint256 claimed)` | external | CRITICAL_GAP | 35.71% (40/112) | (none) | file branch coverage <50% per summary |
| `getCoinflipDayResult(uint32 day) external view returns (uint16 rewardPercent, bool win)` | external view | EXEMPT | — | — | D-11: view/pure |
| `consumeCoinflipsForBurn( address player, uint256 amount ) external onlyBurnieCoin returns (uint256 consumed)` | external | CRITICAL_GAP | 35.71% (40/112) | (none) | file branch coverage <50% per summary |
| `setCoinflipAutoRebuy( address player, bool enabled, uint256 takeProfit ) external` | external | CRITICAL_GAP | 35.71% (40/112) | (none) | file branch coverage <50% per summary |
| `setCoinflipAutoRebuyTakeProfit( address player, uint256 takeProfit ) external` | external | CRITICAL_GAP | 35.71% (40/112) | (none) | file branch coverage <50% per summary |
| `processCoinflipPayouts( bool bonusFlip, uint256 rngWord, uint32 epoch ) external onlyDegenerusGameContract` | external | CRITICAL_GAP | 35.71% (40/112) | (none) | file branch coverage <50% per summary |
| `creditFlip( address player, uint256 amount ) external onlyFlipCreditors` | external | CRITICAL_GAP | 35.71% (40/112) | (none) | file branch coverage <50% per summary |
| `creditFlipBatch( address[] calldata players, uint256[] calldata amounts ) external onlyFlipCreditors` | external | CRITICAL_GAP | 35.71% (40/112) | (none) | file branch coverage <50% per summary |
| `previewClaimCoinflips(address player) external view returns (uint256 mintable)` | external view | EXEMPT | — | — | D-11: view/pure |
| `coinflipAmount(address player) external view returns (uint256)` | external view | EXEMPT | — | — | D-11: view/pure |
| `coinflipAutoRebuyInfo(address player) external view returns ( bool enabled, uint256 stop, uint256 carry, uint32 startDay )` | external view | EXEMPT | — | — | D-11: view/pure |
| `coinflipTopLastDay() external view returns (address player, uint128 score)` | external view | EXEMPT | — | — | D-11: view/pure |

### Contract: `contracts/DegenerusAdmin.sol`

**Deployable:** yes.
**File-level branch coverage:** 0.93% (1/107).
**File-level function coverage:** 8.00% (2/25).

| Function (signature) | Visibility | Verdict | Branch Cov | Test Ref | Notes |
|----------------------|------------|---------|-----------:|----------|-------|
| `proposeFeedSwap( address newFeed ) external returns (uint256 proposalId)` | external | CRITICAL_GAP | 0.93% (1/107) | (none) | file branch coverage <50% per summary |
| `voteFeedSwap(uint256 proposalId, bool approve) external` | external | CRITICAL_GAP | 0.93% (1/107) | (none) | file branch coverage <50% per summary |
| `feedThreshold(uint256 proposalId) public view returns (uint16)` | public view | EXEMPT | — | — | D-11: view/pure |
| `canExecuteFeedSwap(uint256 proposalId) external view returns (bool)` | external view | EXEMPT | — | — | D-11: view/pure |
| `swapGameEthForStEth() external payable onlyOwner` | external payable | CRITICAL_GAP | 0.93% (1/107) | (none) | file branch coverage <50% per summary |
| `propose( address newCoordinator, bytes32 newKeyHash ) external returns (uint256 proposalId)` | external | CRITICAL_GAP | 0.93% (1/107) | (none) | file branch coverage <50% per summary |
| `vote(uint256 proposalId, bool approve) external` | external | CRITICAL_GAP | 0.93% (1/107) | (none) | file branch coverage <50% per summary |
| `threshold(uint256 proposalId) public view returns (uint16)` | public view | EXEMPT | — | — | D-11: view/pure |
| `canExecute(uint256 proposalId) external view returns (bool)` | external view | EXEMPT | — | — | D-11: view/pure |
| `shutdownVrf() external` | external | CRITICAL_GAP | 0.93% (1/107) | (none) | file branch coverage <50% per summary |
| `onTokenTransfer( address from, uint256 amount, bytes calldata ) external` | external | EXEMPT | — | — | D-12: external-callback target |
| `linkAmountToEth( uint256 amount ) external view returns (uint256 ethAmount)` | external view | EXEMPT | — | — | D-11: view/pure |

### Contract: `contracts/DegenerusAffiliate.sol`

**Deployable:** yes.
**File-level branch coverage:** 42.37% (25/59).
**File-level function coverage:** 80.00% (16/20).

| Function (signature) | Visibility | Verdict | Branch Cov | Test Ref | Notes |
|----------------------|------------|---------|-----------:|----------|-------|
| `createAffiliateCode(bytes32 code_, uint8 kickbackPct) external` | external | CRITICAL_GAP | 42.37% (25/59) | (none) | file branch coverage <50% per summary |
| `referPlayer(bytes32 code_) external` | external | CRITICAL_GAP | 42.37% (25/59) | (none) | file branch coverage <50% per summary |
| `getReferrer(address player) external view returns (address)` | external view | EXEMPT | — | — | D-11: view/pure |
| `defaultCode(address addr) external pure returns (bytes32)` | external pure | EXEMPT | — | — | D-11: view/pure |
| `payAffiliate( uint256 amount, bytes32 code, address sender, uint24 lvl, bool isFreshEth, uint16 lootboxActivityScore ) external returns (uint256 playerKickback)` | external | CRITICAL_GAP | 42.37% (25/59) | (none) | file branch coverage <50% per summary |
| `affiliateTop(uint24 lvl) external view returns (address player, uint96 score)` | external view | EXEMPT | — | — | D-11: view/pure |
| `affiliateScore(uint24 lvl, address player) external view returns (uint256 score)` | external view | EXEMPT | — | — | D-11: view/pure |
| `totalAffiliateScore(uint24 lvl) external view returns (uint256 total)` | external view | EXEMPT | — | — | D-11: view/pure |
| `affiliateBonusPointsBest(uint24 currLevel, address player) external view returns (uint256 points)` | external view | EXEMPT | — | — | D-11: view/pure |

### Contract: `contracts/DegenerusDeityPass.sol`

**Deployable:** yes.
**File-level branch coverage:** 0.00% (0/23).
**File-level function coverage:** 3.70% (1/27).

| Function (signature) | Visibility | Verdict | Branch Cov | Test Ref | Notes |
|----------------------|------------|---------|-----------:|----------|-------|
| `name() external pure returns (string memory)` | external pure | EXEMPT | — | — | D-11: view/pure |
| `symbol() external pure returns (string memory)` | external pure | EXEMPT | — | — | D-11: view/pure |
| `setRenderer(address newRenderer) external onlyOwner` | external | CRITICAL_GAP | 0.00% (0/23) | (none) | file branch coverage <50% per summary |
| `setRenderColors( string calldata outlineColor, string calldata backgroundColor, string calldata nonCryptoSymbolColor ) external onlyOwner` | external | CRITICAL_GAP | 0.00% (0/23) | (none) | file branch coverage <50% per summary |
| `renderColors() external view returns (string memory outlineColor, string memory backgroundColor, string memory nonCryptoSymbolColor)` | external view | EXEMPT | — | — | D-11: view/pure |
| `tokenURI(uint256 tokenId) external view returns (string memory)` | external view | EXEMPT | — | — | D-11: view/pure |
| `supportsInterface(bytes4 id) external pure returns (bool)` | external pure | EXEMPT | — | — | D-11: view/pure |
| `balanceOf(address account) external view returns (uint256)` | external view | EXEMPT | — | — | D-11: view/pure |
| `ownerOf(uint256 tokenId) external view returns (address ownerAddr)` | external view | EXEMPT | — | — | D-11: view/pure |
| `getApproved(uint256 tokenId) external view returns (address)` | external view | EXEMPT | — | — | D-11: view/pure |
| `isApprovedForAll(address, address) external pure returns (bool)` | external pure | EXEMPT | — | — | D-11: view/pure |
| `approve(address, uint256) external pure` | external pure | EXEMPT | — | — | D-11: view/pure |
| `setApprovalForAll(address, bool) external pure` | external pure | EXEMPT | — | — | D-11: view/pure |
| `transferFrom(address, address, uint256) external pure` | external pure | EXEMPT | — | — | D-11: view/pure |
| `safeTransferFrom(address, address, uint256) external pure` | external pure | EXEMPT | — | — | D-11: view/pure |
| `safeTransferFrom(address, address, uint256, bytes calldata) external pure` | external pure | EXEMPT | — | — | D-11: view/pure |
| `mint(address to, uint256 tokenId) external` | external | CRITICAL_GAP | 0.00% (0/23) | (none) | file branch coverage <50% per summary |

### Contract: `contracts/DegenerusGame.sol`

**Deployable:** yes.
**File-level branch coverage:** 16.20% (29/179).
**File-level function coverage:** 46.55% (54/116).

| Function (signature) | Visibility | Verdict | Branch Cov | Test Ref | Notes |
|----------------------|------------|---------|-----------:|----------|-------|
| `advanceGame() external` | external | CRITICAL_GAP | 16.20% (29/179) | (none) | file branch coverage <50% per summary |
| `wireVrf( address coordinator_, uint256 subId, bytes32 keyHash_ ) external` | external | CRITICAL_GAP | 16.20% (29/179) | (none) | file branch coverage <50% per summary |
| `recordMint( address player, uint24 lvl, uint256 costWei, uint32 mintUnits, MintPaymentKind payKind ) external payable returns (uint256 newClaimableBalance)` | external payable | CRITICAL_GAP | 16.20% (29/179) | (none) | file branch coverage <50% per summary |
| `recordMintQuestStreak(address player) external` | external | CRITICAL_GAP | 16.20% (29/179) | (none) | file branch coverage <50% per summary |
| `payCoinflipBountyDgnrs( address player, uint256 winningBet, uint256 bountyPool ) external` | external | CRITICAL_GAP | 16.20% (29/179) | (none) | file branch coverage <50% per summary |
| `setOperatorApproval(address operator, bool approved) external` | external | CRITICAL_GAP | 16.20% (29/179) | (none) | file branch coverage <50% per summary |
| `isOperatorApproved( address owner, address operator ) external view returns (bool approved)` | external view | EXEMPT | — | — | D-11: view/pure |
| `currentDayView() external view returns (uint32)` | external view | EXEMPT | — | — | D-11: view/pure |
| `setLootboxRngThreshold(uint256 newThreshold) external` | external | CRITICAL_GAP | 16.20% (29/179) | (none) | file branch coverage <50% per summary |
| `purchase( address buyer, uint256 ticketQuantity, uint256 lootBoxAmount, bytes32 affiliateCode, MintPaymentKind payKind ) external payable` | external payable | CRITICAL_GAP | 16.20% (29/179) | (none) | file branch coverage <50% per summary |
| `purchaseCoin( address buyer, uint256 ticketQuantity, uint256 lootBoxBurnieAmount ) external` | external | CRITICAL_GAP | 16.20% (29/179) | (none) | file branch coverage <50% per summary |
| `purchaseBurnieLootbox( address buyer, uint256 burnieAmount ) external` | external | CRITICAL_GAP | 16.20% (29/179) | (none) | file branch coverage <50% per summary |
| `purchaseWhaleBundle( address buyer, uint256 quantity ) external payable` | external payable | CRITICAL_GAP | 16.20% (29/179) | (none) | file branch coverage <50% per summary |
| `purchaseLazyPass(address buyer) external payable` | external payable | CRITICAL_GAP | 16.20% (29/179) | (none) | file branch coverage <50% per summary |
| `purchaseDeityPass(address buyer, uint8 symbolId) external payable` | external payable | CRITICAL_GAP | 16.20% (29/179) | (none) | file branch coverage <50% per summary |
| `openLootBox(address player, uint48 lootboxIndex) external` | external | CRITICAL_GAP | 16.20% (29/179) | (none) | file branch coverage <50% per summary |
| `openBurnieLootBox(address player, uint48 lootboxIndex) external` | external | CRITICAL_GAP | 16.20% (29/179) | (none) | file branch coverage <50% per summary |
| `placeDegeneretteBet( address player, uint8 currency, uint128 amountPerTicket, uint8 ticketCount, uint32 customTicket, uint8 heroQuadrant ) external payable` | external payable | CRITICAL_GAP | 16.20% (29/179) | (none) | file branch coverage <50% per summary |
| `resolveDegeneretteBets( address player, uint64[] calldata betIds ) external` | external | CRITICAL_GAP | 16.20% (29/179) | (none) | file branch coverage <50% per summary |
| `consumeCoinflipBoon( address player ) external returns (uint16 boostBps)` | external | CRITICAL_GAP | 16.20% (29/179) | (none) | file branch coverage <50% per summary |
| `consumeDecimatorBoon( address player ) external returns (uint16 boostBps)` | external | CRITICAL_GAP | 16.20% (29/179) | (none) | file branch coverage <50% per summary |
| `consumePurchaseBoost( address player ) external returns (uint16 boostBps)` | external | CRITICAL_GAP | 16.20% (29/179) | (none) | file branch coverage <50% per summary |
| `deityBoonData( address deity ) external view returns ( uint256 dailySeed, uint32 day, uint8 usedMask, bool decimatorOpen, bool deityPassAvailable )` | external view | EXEMPT | — | — | D-11: view/pure |
| `issueDeityBoon( address deity, address recipient, uint8 slot ) external` | external | CRITICAL_GAP | 16.20% (29/179) | (none) | file branch coverage <50% per summary |
| `recordDecBurn( address player, uint24 lvl, uint8 bucket, uint256 baseAmount, uint256 multBps ) external returns (uint8 bucketUsed)` | external | CRITICAL_GAP | 16.20% (29/179) | (none) | file branch coverage <50% per summary |
| `runDecimatorJackpot( uint256 poolWei, uint24 lvl, uint256 rngWord ) external returns (uint256 returnAmountWei)` | external | CRITICAL_GAP | 16.20% (29/179) | (none) | file branch coverage <50% per summary |
| `runBafJackpot( uint256 poolWei, uint24 lvl, uint256 rngWord ) external returns (uint256 claimableDelta)` | external | CRITICAL_GAP | 16.20% (29/179) | (none) | file branch coverage <50% per summary |
| `recordTerminalDecBurn( address player, uint24 lvl, uint256 baseAmount ) external` | external | CRITICAL_GAP | 16.20% (29/179) | (none) | file branch coverage <50% per summary |
| `runTerminalDecimatorJackpot( uint256 poolWei, uint24 lvl, uint256 rngWord ) external returns (uint256 returnAmountWei)` | external | CRITICAL_GAP | 16.20% (29/179) | (none) | file branch coverage <50% per summary |
| `terminalDecWindow() external view returns (bool open, uint24 lvl)` | external view | EXEMPT | — | — | D-11: view/pure |
| `runTerminalJackpot( uint256 poolWei, uint24 targetLvl, uint256 rngWord ) external returns (uint256 paidWei)` | external | CRITICAL_GAP | 16.20% (29/179) | (none) | file branch coverage <50% per summary |
| `consumeDecClaim( address player, uint24 lvl ) external returns (uint256 amountWei)` | external | CRITICAL_GAP | 16.20% (29/179) | (none) | file branch coverage <50% per summary |
| `claimDecimatorJackpot(uint24 lvl) external` | external | CRITICAL_GAP | 16.20% (29/179) | (none) | file branch coverage <50% per summary |
| `decClaimable( address player, uint24 lvl ) external view returns (uint256 amountWei, bool winner)` | external view | EXEMPT | — | — | D-11: view/pure |
| `claimWinnings(address player) external` | external | CRITICAL_GAP | 16.20% (29/179) | (none) | file branch coverage <50% per summary |
| `claimWinningsStethFirst() external` | external | CRITICAL_GAP | 16.20% (29/179) | (none) | file branch coverage <50% per summary |
| `claimAffiliateDgnrs(address player) external` | external | CRITICAL_GAP | 16.20% (29/179) | (none) | file branch coverage <50% per summary |
| `setAutoRebuy(address player, bool enabled) external` | external | CRITICAL_GAP | 16.20% (29/179) | (none) | file branch coverage <50% per summary |
| `setAutoRebuyTakeProfit( address player, uint256 takeProfit ) external` | external | CRITICAL_GAP | 16.20% (29/179) | (none) | file branch coverage <50% per summary |
| `autoRebuyTakeProfitFor( address player ) external view returns (uint256 takeProfit)` | external view | EXEMPT | — | — | D-11: view/pure |
| `setAfKingMode( address player, bool enabled, uint256 ethTakeProfit, uint256 coinTakeProfit ) external` | external | CRITICAL_GAP | 16.20% (29/179) | (none) | file branch coverage <50% per summary |
| `afKingModeFor(address player) external view returns (bool active)` | external view | EXEMPT | — | — | D-11: view/pure |
| `afKingActivatedLevelFor( address player ) external view returns (uint24 activationLevel)` | external view | EXEMPT | — | — | D-11: view/pure |
| `deactivateAfKingFromCoin(address player) external` | external | CRITICAL_GAP | 16.20% (29/179) | (none) | file branch coverage <50% per summary |
| `syncAfKingLazyPassFromCoin( address player ) external returns (bool active)` | external | CRITICAL_GAP | 16.20% (29/179) | (none) | file branch coverage <50% per summary |
| `claimWhalePass(address player) external` | external | CRITICAL_GAP | 16.20% (29/179) | (none) | file branch coverage <50% per summary |
| `resolveRedemptionLootbox( address player, uint256 amount, uint256 rngWord, uint16 activityScore ) external` | external | CRITICAL_GAP | 16.20% (29/179) | (none) | file branch coverage <50% per summary |
| `adminSwapEthForStEth( address recipient, uint256 amount ) external payable` | external payable | CRITICAL_GAP | 16.20% (29/179) | (none) | file branch coverage <50% per summary |
| `adminStakeEthForStEth(uint256 amount) external` | external | CRITICAL_GAP | 16.20% (29/179) | (none) | file branch coverage <50% per summary |
| `updateVrfCoordinatorAndSub( address newCoordinator, uint256 newSubId, bytes32 newKeyHash ) external` | external | CRITICAL_GAP | 16.20% (29/179) | (none) | file branch coverage <50% per summary |
| `requestLootboxRng() external` | external | CRITICAL_GAP | 16.20% (29/179) | (none) | file branch coverage <50% per summary |
| `reverseFlip() external` | external | CRITICAL_GAP | 16.20% (29/179) | (none) | file branch coverage <50% per summary |
| `rawFulfillRandomWords( uint256 requestId, uint256[] calldata randomWords ) external` | external | EXEMPT | — | — | D-12: external-callback target |
| `prizePoolTargetView() external view returns (uint256)` | external view | EXEMPT | — | — | D-11: view/pure |
| `nextPrizePoolView() external view returns (uint256)` | external view | EXEMPT | — | — | D-11: view/pure |
| `futurePrizePoolView() external view returns (uint256)` | external view | EXEMPT | — | — | D-11: view/pure |
| `ticketsOwedView( uint24 lvl, address player ) external view returns (uint32)` | external view | EXEMPT | — | — | D-11: view/pure |
| `lootboxStatus( address player, uint48 lootboxIndex ) external view returns (uint256 amount, bool presale)` | external view | EXEMPT | — | — | D-11: view/pure |
| `degeneretteBetInfo( address player, uint64 betId ) external view returns (uint256 packed)` | external view | EXEMPT | — | — | D-11: view/pure |
| `lootboxPresaleActiveFlag() external view returns (bool active)` | external view | EXEMPT | — | — | D-11: view/pure |
| `currentPrizePoolView() external view returns (uint256)` | external view | EXEMPT | — | — | D-11: view/pure |
| `claimablePoolView() external view returns (uint256)` | external view | EXEMPT | — | — | D-11: view/pure |
| `isFinalSwept() external view returns (bool)` | external view | EXEMPT | — | — | D-11: view/pure |
| `gameOverTimestamp() external view returns (uint48)` | external view | EXEMPT | — | — | D-11: view/pure |
| `yieldPoolView() external view returns (uint256)` | external view | EXEMPT | — | — | D-11: view/pure |
| `yieldAccumulatorView() external view returns (uint256)` | external view | EXEMPT | — | — | D-11: view/pure |
| `mintPrice() external view returns (uint256)` | external view | EXEMPT | — | — | D-11: view/pure |
| `rngWordForDay(uint32 day) external view returns (uint256)` | external view | EXEMPT | — | — | D-11: view/pure |
| `rngLocked() external view returns (bool)` | external view | EXEMPT | — | — | D-11: view/pure |
| `isRngFulfilled() external view returns (bool)` | external view | EXEMPT | — | — | D-11: view/pure |
| `lastVrfProcessed() external view returns (uint48)` | external view | EXEMPT | — | — | D-11: view/pure |
| `decWindow() external view returns (bool)` | external view | EXEMPT | — | — | D-11: view/pure |
| `jackpotCompressionTier() external view returns (uint8)` | external view | EXEMPT | — | — | D-11: view/pure |
| `jackpotPhase() external view returns (bool)` | external view | EXEMPT | — | — | D-11: view/pure |
| `purchaseInfo() external view returns ( uint24 lvl, bool inJackpotPhase, bool lastPurchaseDay_, bool rngLocked_, uint256 priceWei )` | external view | EXEMPT | — | — | D-11: view/pure |
| `ethMintStats( address player ) external view returns (uint24 lvl, uint24 levelCount, uint24 streak)` | external view | EXEMPT | — | — | D-11: view/pure |
| `playerActivityScore( address player ) external view returns (uint256 scoreBps)` | external view | EXEMPT | — | — | D-11: view/pure |
| `getWinnings() external view returns (uint256)` | external view | EXEMPT | — | — | D-11: view/pure |
| `claimableWinningsOf( address player ) external view returns (uint256)` | external view | EXEMPT | — | — | D-11: view/pure |
| `whalePassClaimAmount( address player ) external view returns (uint256)` | external view | EXEMPT | — | — | D-11: view/pure |
| `hasDeityPass(address player) external view returns (bool)` | external view | EXEMPT | — | — | D-11: view/pure |
| `mintPackedFor(address player) external view returns (uint256)` | external view | EXEMPT | — | — | D-11: view/pure |
| `sampleTraitTickets( uint256 entropy ) external view returns (uint24 lvlSel, uint8 traitSel, address[] memory tickets)` | external view | EXEMPT | — | — | D-11: view/pure |
| `sampleTraitTicketsAtLevel( uint24 targetLvl, uint256 entropy ) external view returns (uint8 traitSel, address[] memory tickets)` | external view | EXEMPT | — | — | D-11: view/pure |
| `sampleFarFutureTickets( uint256 entropy ) external view returns (address[] memory tickets)` | external view | EXEMPT | — | — | D-11: view/pure |
| `getTickets( uint8 trait, uint24 lvl, uint32 offset, uint32 limit, address player ) external view returns (uint24 count, uint32 nextOffset, uint32 total)` | external view | EXEMPT | — | — | D-11: view/pure |
| `getPlayerPurchases( address player ) external view returns (uint32 tickets)` | external view | EXEMPT | — | — | D-11: view/pure |
| `getDailyHeroWager( uint32 day, uint8 quadrant, uint8 symbol ) external view returns (uint256 wagerUnits)` | external view | EXEMPT | — | — | D-11: view/pure |
| `getDailyHeroWinner( uint32 day ) external view returns (uint8 winQuadrant, uint8 winSymbol, uint256 winAmount)` | external view | EXEMPT | — | — | D-11: view/pure |
| `getPlayerDegeneretteWager( address player, uint24 lvl ) external view returns (uint256 weiAmount)` | external view | EXEMPT | — | — | D-11: view/pure |
| `getTopDegenerette( uint24 lvl ) external view returns (address topPlayer, uint256 amountUnits)` | external view | EXEMPT | — | — | D-11: view/pure |

### Contract: `contracts/DegenerusJackpots.sol`

**Deployable:** yes.
**File-level branch coverage:** 1.96% (1/51).
**File-level function coverage:** 27.27% (3/11).

| Function (signature) | Visibility | Verdict | Branch Cov | Test Ref | Notes |
|----------------------|------------|---------|-----------:|----------|-------|
| `recordBafFlip(address player, uint24 lvl, uint256 amount) external override onlyCoin` | external | CRITICAL_GAP | 1.96% (1/51) | (none) | file branch coverage <50% per summary |
| `runBafJackpot( uint256 poolWei, uint24 lvl, uint256 rngWord ) external override onlyGame returns (address[] memory winners, uint256[] memory amounts, uint256 returnAmountWei)` | external | CRITICAL_GAP | 1.96% (1/51) | (none) | file branch coverage <50% per summary |
| `getLastBafResolvedDay() external view returns (uint32)` | external view | EXEMPT | — | — | D-11: view/pure |

### Contract: `contracts/DegenerusQuests.sol`

**Deployable:** yes.
**File-level branch coverage:** 39.68% (50/126).
**File-level function coverage:** 65.00% (26/40).

| Function (signature) | Visibility | Verdict | Branch Cov | Test Ref | Notes |
|----------------------|------------|---------|-----------:|----------|-------|
| `rollDailyQuest(uint32 day, uint256 entropy) external onlyGame` | external | CRITICAL_GAP | 39.68% (50/126) | (none) | file branch coverage <50% per summary |
| `awardQuestStreakBonus(address player, uint16 amount, uint32 currentDay) external onlyGame` | external | CRITICAL_GAP | 39.68% (50/126) | (none) | file branch coverage <50% per summary |
| `handleMint( address player, uint32 quantity, bool paidWithEth, uint256 mintPrice ) external onlyCoin returns (uint256 reward, uint8 questType, uint32 streak, bool completed)` | external | CRITICAL_GAP | 39.68% (50/126) | (none) | file branch coverage <50% per summary |
| `handleFlip( address player, uint256 flipCredit ) external onlyCoin returns (uint256 reward, uint8 questType, uint32 streak, bool completed)` | external | CRITICAL_GAP | 39.68% (50/126) | (none) | file branch coverage <50% per summary |
| `handleDecimator( address player, uint256 burnAmount ) external onlyCoin returns (uint256 reward, uint8 questType, uint32 streak, bool completed)` | external | CRITICAL_GAP | 39.68% (50/126) | (none) | file branch coverage <50% per summary |
| `handleAffiliate( address player, uint256 amount ) external onlyCoin returns (uint256 reward, uint8 questType, uint32 streak, bool completed)` | external | CRITICAL_GAP | 39.68% (50/126) | (none) | file branch coverage <50% per summary |
| `handleLootBox( address player, uint256 amountWei, uint256 mintPrice ) external onlyCoin returns (uint256 reward, uint8 questType, uint32 streak, bool completed)` | external | CRITICAL_GAP | 39.68% (50/126) | (none) | file branch coverage <50% per summary |
| `handlePurchase( address player, uint32 ethMintQty, uint32 burnieMintQty, uint256 lootBoxAmount, uint256 mintPrice, uint256 levelQuestPrice ) external onlyCoin returns (uint256 reward, uint8 questType, uint32 streak, bool completed)` | external | CRITICAL_GAP | 39.68% (50/126) | (none) | file branch coverage <50% per summary |
| `handleDegenerette( address player, uint256 amount, bool paidWithEth, uint256 mintPrice ) external onlyCoin returns (uint256 reward, uint8 questType, uint32 streak, bool completed)` | external | CRITICAL_GAP | 39.68% (50/126) | (none) | file branch coverage <50% per summary |
| `getActiveQuests() external view returns (QuestInfo[2] memory quests)` | external view | EXEMPT | — | — | D-11: view/pure |
| `playerQuestStates( address player ) external view override returns (uint32 streak, uint32 lastCompletedDay, uint128[2] memory progress, bool[2] memory completed)` | external view | EXEMPT | — | — | D-11: view/pure |
| `getPlayerQuestView(address player) external view returns (PlayerQuestView memory viewData)` | external view | EXEMPT | — | — | D-11: view/pure |
| `rollLevelQuest(uint256 entropy) external override onlyGame` | external | CRITICAL_GAP | 39.68% (50/126) | (none) | file branch coverage <50% per summary |
| `getPlayerLevelQuestView(address player) external view override returns (uint8 questType, uint128 progress, uint256 target, bool completed, bool eligible)` | external view | EXEMPT | — | — | D-11: view/pure |

### Contract: `contracts/DegenerusStonk.sol`

**Deployable:** yes.
**File-level branch coverage:** 0.00% (0/34).
**File-level function coverage:** 30.77% (4/13).

| Function (signature) | Visibility | Verdict | Branch Cov | Test Ref | Notes |
|----------------------|------------|---------|-----------:|----------|-------|
| `transfer(address to, uint256 amount) external returns (bool)` | external | CRITICAL_GAP | 0.00% (0/34) | (none) | file branch coverage <50% per summary |
| `transferFrom(address from, address to, uint256 amount) external returns (bool)` | external | CRITICAL_GAP | 0.00% (0/34) | (none) | file branch coverage <50% per summary |
| `approve(address spender, uint256 amount) external returns (bool)` | external | CRITICAL_GAP | 0.00% (0/34) | (none) | file branch coverage <50% per summary |
| `unwrapTo(address recipient, uint256 amount) external` | external | CRITICAL_GAP | 0.00% (0/34) | (none) | file branch coverage <50% per summary |
| `claimVested() external` | external | CRITICAL_GAP | 0.00% (0/34) | (none) | file branch coverage <50% per summary |
| `burn(uint256 amount) external returns (uint256 ethOut, uint256 stethOut, uint256 burnieOut)` | external | CRITICAL_GAP | 0.00% (0/34) | (none) | file branch coverage <50% per summary |
| `previewBurn(uint256 amount) external view returns (uint256 ethOut, uint256 stethOut, uint256 burnieOut)` | external view | EXEMPT | — | — | D-11: view/pure |
| `yearSweep() external` | external | CRITICAL_GAP | 0.00% (0/34) | (none) | file branch coverage <50% per summary |
| `burnForSdgnrs(address player, uint256 amount) external` | external | CRITICAL_GAP | 0.00% (0/34) | (none) | file branch coverage <50% per summary |

### Contract: `contracts/DegenerusVault.sol`

**Deployable:** yes.
**File-level branch coverage:** 14.29% (9/63).
**File-level function coverage:** 21.05% (12/57).

| Function (signature) | Visibility | Verdict | Branch Cov | Test Ref | Notes |
|----------------------|------------|---------|-----------:|----------|-------|
| `approve(address spender, uint256 amount) external returns (bool)` | external | CRITICAL_GAP | 14.29% (9/63) | (none) | file branch coverage <50% per summary |
| `transfer(address to, uint256 amount) external returns (bool)` | external | CRITICAL_GAP | 14.29% (9/63) | (none) | file branch coverage <50% per summary |
| `transferFrom(address from, address to, uint256 amount) external returns (bool)` | external | CRITICAL_GAP | 14.29% (9/63) | (none) | file branch coverage <50% per summary |
| `vaultMint(address to, uint256 amount) external onlyVault` | external | CRITICAL_GAP | 14.29% (9/63) | (none) | file branch coverage <50% per summary |
| `vaultBurn(address from, uint256 amount) external onlyVault` | external | CRITICAL_GAP | 14.29% (9/63) | (none) | file branch coverage <50% per summary |
| `isVaultOwner(address account) external view returns (bool)` | external view | EXEMPT | — | — | D-11: view/pure |
| `deposit(uint256 coinAmount, uint256 stEthAmount) external payable onlyGame` | external payable | CRITICAL_GAP | 14.29% (9/63) | (none) | file branch coverage <50% per summary |
| `gameAdvance() external onlyVaultOwner` | external | CRITICAL_GAP | 14.29% (9/63) | (none) | file branch coverage <50% per summary |
| `gamePurchase( uint256 ticketQuantity, uint256 lootBoxAmount, bytes32 affiliateCode, MintPaymentKind payKind, uint256 ethValue ) external payable onlyVaultOwner` | external payable | CRITICAL_GAP | 14.29% (9/63) | (none) | file branch coverage <50% per summary |
| `gamePurchaseTicketsBurnie(uint256 ticketQuantity) external onlyVaultOwner` | external | CRITICAL_GAP | 14.29% (9/63) | (none) | file branch coverage <50% per summary |
| `gamePurchaseBurnieLootbox(uint256 burnieAmount) external onlyVaultOwner` | external | CRITICAL_GAP | 14.29% (9/63) | (none) | file branch coverage <50% per summary |
| `gameOpenLootBox(uint48 lootboxIndex) external onlyVaultOwner` | external | CRITICAL_GAP | 14.29% (9/63) | (none) | file branch coverage <50% per summary |
| `gamePurchaseDeityPassFromBoon(uint256 priceWei, uint8 symbolId) external payable onlyVaultOwner` | external payable | CRITICAL_GAP | 14.29% (9/63) | (none) | file branch coverage <50% per summary |
| `gameClaimWinnings() external onlyVaultOwner` | external | CRITICAL_GAP | 14.29% (9/63) | (none) | file branch coverage <50% per summary |
| `gameClaimWhalePass() external onlyVaultOwner` | external | CRITICAL_GAP | 14.29% (9/63) | (none) | file branch coverage <50% per summary |
| `gameDegeneretteBet( uint8 currency, uint128 amountPerTicket, uint8 ticketCount, uint32 customTicket, uint8 heroQuadrant, uint256 ethValue ) external payable onlyVaultOwner` | external payable | CRITICAL_GAP | 14.29% (9/63) | (none) | file branch coverage <50% per summary |
| `gameResolveDegeneretteBets(uint64[] calldata betIds) external onlyVaultOwner` | external | CRITICAL_GAP | 14.29% (9/63) | (none) | file branch coverage <50% per summary |
| `gameSetAutoRebuy(bool enabled) external onlyVaultOwner` | external | CRITICAL_GAP | 14.29% (9/63) | (none) | file branch coverage <50% per summary |
| `gameSetAutoRebuyTakeProfit(uint256 takeProfit) external onlyVaultOwner` | external | CRITICAL_GAP | 14.29% (9/63) | (none) | file branch coverage <50% per summary |
| `gameSetDecimatorAutoRebuy(bool enabled) external onlyVaultOwner` | external | CRITICAL_GAP | 14.29% (9/63) | (none) | file branch coverage <50% per summary |
| `gameSetAfKingMode( bool enabled, uint256 ethTakeProfit, uint256 coinTakeProfit ) external onlyVaultOwner` | external | CRITICAL_GAP | 14.29% (9/63) | (none) | file branch coverage <50% per summary |
| `gameSetOperatorApproval(address operator, bool approved) external onlyVaultOwner` | external | CRITICAL_GAP | 14.29% (9/63) | (none) | file branch coverage <50% per summary |
| `coinDepositCoinflip(uint256 amount) external onlyVaultOwner` | external | CRITICAL_GAP | 14.29% (9/63) | (none) | file branch coverage <50% per summary |
| `coinClaimCoinflips(uint256 amount) external onlyVaultOwner returns (uint256 claimed)` | external | CRITICAL_GAP | 14.29% (9/63) | (none) | file branch coverage <50% per summary |
| `coinDecimatorBurn(uint256 amount) external onlyVaultOwner` | external | CRITICAL_GAP | 14.29% (9/63) | (none) | file branch coverage <50% per summary |
| `coinSetAutoRebuy(bool enabled, uint256 takeProfit) external onlyVaultOwner` | external | CRITICAL_GAP | 14.29% (9/63) | (none) | file branch coverage <50% per summary |
| `coinSetAutoRebuyTakeProfit(uint256 takeProfit) external onlyVaultOwner` | external | CRITICAL_GAP | 14.29% (9/63) | (none) | file branch coverage <50% per summary |
| `wwxrpMint(address to, uint256 amount) external onlyVaultOwner` | external | CRITICAL_GAP | 14.29% (9/63) | (none) | file branch coverage <50% per summary |
| `jackpotsClaimDecimator(uint24 lvl) external onlyVaultOwner` | external | CRITICAL_GAP | 14.29% (9/63) | (none) | file branch coverage <50% per summary |
| `sdgnrsBurn(uint256 amount) external onlyVaultOwner returns (uint256 ethOut, uint256 stethOut, uint256 burnieOut)` | external | CRITICAL_GAP | 14.29% (9/63) | (none) | file branch coverage <50% per summary |
| `sdgnrsClaimRedemption() external onlyVaultOwner` | external | CRITICAL_GAP | 14.29% (9/63) | (none) | file branch coverage <50% per summary |
| `burnCoin(address player, uint256 amount) external returns (uint256 coinOut)` | external | CRITICAL_GAP | 14.29% (9/63) | (none) | file branch coverage <50% per summary |
| `burnEth( address player, uint256 amount ) external returns (uint256 ethOut, uint256 stEthOut)` | external | CRITICAL_GAP | 14.29% (9/63) | (none) | file branch coverage <50% per summary |
| `previewBurnForCoinOut(uint256 coinOut) external view returns (uint256 burnAmount)` | external view | EXEMPT | — | — | D-11: view/pure |
| `previewBurnForEthOut( uint256 targetValue ) external view returns (uint256 burnAmount, uint256 ethOut, uint256 stEthOut)` | external view | EXEMPT | — | — | D-11: view/pure |
| `previewCoin(uint256 amount) external view returns (uint256 coinOut)` | external view | EXEMPT | — | — | D-11: view/pure |
| `previewEth(uint256 amount) external view returns (uint256 ethOut, uint256 stEthOut)` | external view | EXEMPT | — | — | D-11: view/pure |

### Contract: `contracts/DeityBoonViewer.sol`

**Deployable:** yes.
**File-level branch coverage:** 0.00% (0/28).
**File-level function coverage:** 0.00% (0/2).

| Function (signature) | Visibility | Verdict | Branch Cov | Test Ref | Notes |
|----------------------|------------|---------|-----------:|----------|-------|
| `deityBoonSlots( address game, address deity ) external view returns (uint8[3] memory slots, uint8 usedMask, uint32 day)` | external view | EXEMPT | — | — | D-11: view/pure |

### Contract: `contracts/GNRUS.sol`

**Deployable:** yes.
**File-level branch coverage:** 5.56% (2/36).
**File-level function coverage:** 38.46% (5/13).

| Function (signature) | Visibility | Verdict | Branch Cov | Test Ref | Notes |
|----------------------|------------|---------|-----------:|----------|-------|
| `transfer(address, uint256) external pure returns (bool)` | external pure | EXEMPT | — | — | D-11: view/pure |
| `transferFrom(address, address, uint256) external pure returns (bool)` | external pure | EXEMPT | — | — | D-11: view/pure |
| `approve(address, uint256) external pure returns (bool)` | external pure | EXEMPT | — | — | D-11: view/pure |
| `burn(uint256 amount) external` | external | CRITICAL_GAP | 5.56% (2/36) | (none) | file branch coverage <50% per summary |
| `burnAtGameOver() external onlyGame` | external | CRITICAL_GAP | 5.56% (2/36) | (none) | file branch coverage <50% per summary |
| `propose(address recipient) external returns (uint48 proposalId)` | external | CRITICAL_GAP | 5.56% (2/36) | (none) | file branch coverage <50% per summary |
| `vote(uint48 proposalId, bool approveVote) external` | external | CRITICAL_GAP | 5.56% (2/36) | (none) | file branch coverage <50% per summary |
| `pickCharity(uint24 level) external onlyGame` | external | CRITICAL_GAP | 5.56% (2/36) | (none) | file branch coverage <50% per summary |
| `getProposal(uint48 proposalId) external view returns ( address recipient, address proposer, uint48 approveWeight, uint48 rejectWeight )` | external view | EXEMPT | — | — | D-11: view/pure |
| `getLevelProposals(uint24 level) external view returns (uint48 start, uint8 count)` | external view | EXEMPT | — | — | D-11: view/pure |

### Contract: `contracts/Icons32Data.sol`

**Deployable:** yes.
**File-level branch coverage:** 0.00% (0/17).
**File-level function coverage:** 0.00% (0/5).

| Function (signature) | Visibility | Verdict | Branch Cov | Test Ref | Notes |
|----------------------|------------|---------|-----------:|----------|-------|
| `setPaths(uint256 startIndex, string[] calldata paths) external` | external | CRITICAL_GAP | 0.00% (0/17) | (none) | file branch coverage <50% per summary |
| `setSymbols(uint256 quadrant, string[8] memory symbols) external` | external | CRITICAL_GAP | 0.00% (0/17) | (none) | file branch coverage <50% per summary |
| `finalize() external` | external | CRITICAL_GAP | 0.00% (0/17) | (none) | file branch coverage <50% per summary |
| `data(uint256 i) external view returns (string memory)` | external view | EXEMPT | — | — | D-11: view/pure |
| `symbol(uint256 quadrant, uint8 idx) external view returns (string memory)` | external view | EXEMPT | — | — | D-11: view/pure |

### Contract: `contracts/StakedDegenerusStonk.sol`

**Deployable:** yes.
**File-level branch coverage:** 33.33% (22/66).
**File-level function coverage:** 64.29% (18/28).

| Function (signature) | Visibility | Verdict | Branch Cov | Test Ref | Notes |
|----------------------|------------|---------|-----------:|----------|-------|
| `wrapperTransferTo(address to, uint256 amount) external` | external | CRITICAL_GAP | 33.33% (22/66) | (none) | file branch coverage <50% per summary |
| `gameAdvance() external` | external | CRITICAL_GAP | 33.33% (22/66) | (none) | file branch coverage <50% per summary |
| `gameClaimWhalePass() external` | external | CRITICAL_GAP | 33.33% (22/66) | (none) | file branch coverage <50% per summary |
| `depositSteth(uint256 amount) external onlyGame` | external | CRITICAL_GAP | 33.33% (22/66) | (none) | file branch coverage <50% per summary |
| `poolBalance(Pool pool) external view returns (uint256)` | external view | EXEMPT | — | — | D-11: view/pure |
| `votingSupply() external view returns (uint256)` | external view | EXEMPT | — | — | D-11: view/pure |
| `transferFromPool(Pool pool, address to, uint256 amount) external onlyGame returns (uint256 transferred)` | external | CRITICAL_GAP | 33.33% (22/66) | (none) | file branch coverage <50% per summary |
| `transferBetweenPools(Pool from, Pool to, uint256 amount) external onlyGame returns (uint256 transferred)` | external | CRITICAL_GAP | 33.33% (22/66) | (none) | file branch coverage <50% per summary |
| `burnAtGameOver() external onlyGame` | external | CRITICAL_GAP | 33.33% (22/66) | (none) | file branch coverage <50% per summary |
| `burn(uint256 amount) external returns (uint256 ethOut, uint256 stethOut, uint256 burnieOut)` | external | CRITICAL_GAP | 33.33% (22/66) | (none) | file branch coverage <50% per summary |
| `burnWrapped(uint256 amount) external returns (uint256 ethOut, uint256 stethOut, uint256 burnieOut)` | external | CRITICAL_GAP | 33.33% (22/66) | (none) | file branch coverage <50% per summary |
| `hasPendingRedemptions() external view returns (bool)` | external view | EXEMPT | — | — | D-11: view/pure |
| `resolveRedemptionPeriod(uint16 roll, uint32 flipDay) external` | external | CRITICAL_GAP | 33.33% (22/66) | (none) | file branch coverage <50% per summary |
| `claimRedemption() external` | external | CRITICAL_GAP | 33.33% (22/66) | (none) | file branch coverage <50% per summary |
| `previewBurn(uint256 amount) external view returns (uint256 ethOut, uint256 stethOut, uint256 burnieOut)` | external view | EXEMPT | — | — | D-11: view/pure |
| `burnieReserve() external view returns (uint256)` | external view | EXEMPT | — | — | D-11: view/pure |

### Contract: `contracts/WrappedWrappedXRP.sol`

**Deployable:** yes.
**File-level branch coverage:** 0.00% (0/15).
**File-level function coverage:** 18.18% (2/11).

| Function (signature) | Visibility | Verdict | Branch Cov | Test Ref | Notes |
|----------------------|------------|---------|-----------:|----------|-------|
| `supplyIncUncirculated() external view returns (uint256)` | external view | EXEMPT | — | — | D-11: view/pure |
| `vaultMintAllowance() external view returns (uint256)` | external view | EXEMPT | — | — | D-11: view/pure |
| `approve(address spender, uint256 amount) external returns (bool)` | external | CRITICAL_GAP | 0.00% (0/15) | (none) | file branch coverage <50% per summary |
| `transfer(address to, uint256 amount) external returns (bool)` | external | CRITICAL_GAP | 0.00% (0/15) | (none) | file branch coverage <50% per summary |
| `transferFrom( address from, address to, uint256 amount ) external returns (bool)` | external | CRITICAL_GAP | 0.00% (0/15) | (none) | file branch coverage <50% per summary |
| `mintPrize(address to, uint256 amount) external` | external | CRITICAL_GAP | 0.00% (0/15) | (none) | file branch coverage <50% per summary |
| `vaultMintTo(address to, uint256 amount) external` | external | CRITICAL_GAP | 0.00% (0/15) | (none) | file branch coverage <50% per summary |
| `burnForGame(address from, uint256 amount) external` | external | CRITICAL_GAP | 0.00% (0/15) | (none) | file branch coverage <50% per summary |

### Contract: `contracts/modules/DegenerusGameAdvanceModule.sol`

**Deployable:** yes (delegatecall target, deploys as own address).
**File-level branch coverage:** 48.00% (72/150).
**File-level function coverage:** 86.11% (31/36).

| Function (signature) | Visibility | Verdict | Branch Cov | Test Ref | Notes |
|----------------------|------------|---------|-----------:|----------|-------|
| `advanceGame() external` | external | CRITICAL_GAP | 48.00% (72/150) | (none) | file branch coverage <50% per summary |
| `wireVrf( address coordinator_, uint256 subId, bytes32 keyHash_ ) external` | external | CRITICAL_GAP | 48.00% (72/150) | (none) | file branch coverage <50% per summary |
| `requestLootboxRng() external` | external | CRITICAL_GAP | 48.00% (72/150) | (none) | file branch coverage <50% per summary |
| `updateVrfCoordinatorAndSub( address newCoordinator, uint256 newSubId, bytes32 newKeyHash ) external` | external | CRITICAL_GAP | 48.00% (72/150) | (none) | file branch coverage <50% per summary |
| `rawFulfillRandomWords( uint256 requestId, uint256[] calldata randomWords ) external` | external | EXEMPT | — | — | D-12: external-callback target |

### Contract: `contracts/modules/DegenerusGameBoonModule.sol`

**Deployable:** yes (delegatecall target, deploys as own address).
**File-level branch coverage:** 2.04% (1/49).
**File-level function coverage:** 20.00% (1/5).

| Function (signature) | Visibility | Verdict | Branch Cov | Test Ref | Notes |
|----------------------|------------|---------|-----------:|----------|-------|
| `consumeCoinflipBoon(address player) external returns (uint16 boonBps)` | external | CRITICAL_GAP | 2.04% (1/49) | (none) | file branch coverage <50% per summary |
| `consumePurchaseBoost(address player) external returns (uint16 boostBps)` | external | CRITICAL_GAP | 2.04% (1/49) | (none) | file branch coverage <50% per summary |
| `consumeDecimatorBoost(address player) external returns (uint16 boostBps)` | external | CRITICAL_GAP | 2.04% (1/49) | (none) | file branch coverage <50% per summary |
| `checkAndClearExpiredBoon(address player) external returns (bool hasAnyBoon)` | external | CRITICAL_GAP | 2.04% (1/49) | (none) | file branch coverage <50% per summary |
| `consumeActivityBoon(address player) external` | external | CRITICAL_GAP | 2.04% (1/49) | (none) | file branch coverage <50% per summary |

### Contract: `contracts/modules/DegenerusGameDecimatorModule.sol`

**Deployable:** yes (delegatecall target, deploys as own address).
**File-level branch coverage:** 1.59% (1/63).
**File-level function coverage:** 3.85% (1/26).

| Function (signature) | Visibility | Verdict | Branch Cov | Test Ref | Notes |
|----------------------|------------|---------|-----------:|----------|-------|
| `recordDecBurn( address player, uint24 lvl, uint8 bucket, uint256 baseAmount, uint256 multBps ) external returns (uint8 bucketUsed)` | external | CRITICAL_GAP | 1.59% (1/63) | (none) | file branch coverage <50% per summary |
| `runDecimatorJackpot( uint256 poolWei, uint24 lvl, uint256 rngWord ) external returns (uint256 returnAmountWei)` | external | CRITICAL_GAP | 1.59% (1/63) | (none) | file branch coverage <50% per summary |
| `consumeDecClaim( address player, uint24 lvl ) external returns (uint256 amountWei)` | external | CRITICAL_GAP | 1.59% (1/63) | (none) | file branch coverage <50% per summary |
| `claimDecimatorJackpot(uint24 lvl) external` | external | CRITICAL_GAP | 1.59% (1/63) | (none) | file branch coverage <50% per summary |
| `decClaimable( address player, uint24 lvl ) external view returns (uint256 amountWei, bool winner)` | external view | EXEMPT | — | — | D-11: view/pure |
| `recordTerminalDecBurn( address player, uint24 lvl, uint256 baseAmount ) external` | external | CRITICAL_GAP | 1.59% (1/63) | (none) | file branch coverage <50% per summary |
| `runTerminalDecimatorJackpot( uint256 poolWei, uint24 lvl, uint256 rngWord ) external returns (uint256 returnAmountWei)` | external | CRITICAL_GAP | 1.59% (1/63) | (none) | file branch coverage <50% per summary |
| `claimTerminalDecimatorJackpot() external` | external | CRITICAL_GAP | 1.59% (1/63) | (none) | file branch coverage <50% per summary |
| `terminalDecClaimable( address player ) external view returns (uint256 amountWei, bool winner)` | external view | EXEMPT | — | — | D-11: view/pure |

### Contract: `contracts/modules/DegenerusGameDegeneretteModule.sol`

**Deployable:** yes (delegatecall target, deploys as own address).
**File-level branch coverage:** 34.48% (30/87).
**File-level function coverage:** 84.00% (21/25).

| Function (signature) | Visibility | Verdict | Branch Cov | Test Ref | Notes |
|----------------------|------------|---------|-----------:|----------|-------|
| `placeDegeneretteBet( address player, uint8 currency, uint128 amountPerTicket, uint8 ticketCount, uint32 customTicket, uint8 heroQuadrant ) external payable` | external payable | CRITICAL_GAP | 34.48% (30/87) | (none) | file branch coverage <50% per summary |
| `resolveBets(address player, uint64[] calldata betIds) external` | external | CRITICAL_GAP | 34.48% (30/87) | (none) | file branch coverage <50% per summary |

### Contract: `contracts/modules/DegenerusGameGameOverModule.sol`

**Deployable:** yes (delegatecall target, deploys as own address).
**File-level branch coverage:** 42.31% (11/26).
**File-level function coverage:** 100.00% (4/4).

| Function (signature) | Visibility | Verdict | Branch Cov | Test Ref | Notes |
|----------------------|------------|---------|-----------:|----------|-------|
| `handleGameOverDrain(uint32 day) external` | external | CRITICAL_GAP | 42.31% (11/26) | (none) | file branch coverage <50% per summary |
| `handleFinalSweep() external` | external | CRITICAL_GAP | 42.31% (11/26) | (none) | file branch coverage <50% per summary |

### Contract: `contracts/modules/DegenerusGameJackpotModule.sol`

**Deployable:** yes (delegatecall target, deploys as own address).
**File-level branch coverage:** 36.57% (49/134).
**File-level function coverage:** 72.22% (26/36).

| Function (signature) | Visibility | Verdict | Branch Cov | Test Ref | Notes |
|----------------------|------------|---------|-----------:|----------|-------|
| `runTerminalJackpot( uint256 poolWei, uint24 targetLvl, uint256 rngWord ) external returns (uint256 paidWei)` | external | CRITICAL_GAP | 36.57% (49/134) | (none) | file branch coverage <50% per summary |
| `payDailyJackpot( bool isJackpotPhase, uint24 lvl, uint256 randWord ) external` | external | CRITICAL_GAP | 36.57% (49/134) | (none) | file branch coverage <50% per summary |
| `payDailyJackpotCoinAndTickets(uint256 randWord) external` | external | CRITICAL_GAP | 36.57% (49/134) | (none) | file branch coverage <50% per summary |
| `distributeYieldSurplus(uint256 rngWord) external` | external | CRITICAL_GAP | 36.57% (49/134) | (none) | file branch coverage <50% per summary |
| `payDailyCoinJackpot(uint24 lvl, uint256 randWord, uint24 minLevel, uint24 maxLevel) external` | external | CRITICAL_GAP | 36.57% (49/134) | (none) | file branch coverage <50% per summary |
| `emitDailyWinningTraits(uint24, uint256 randWord, uint24 bonusTargetLevel) external` | external | CRITICAL_GAP | 36.57% (49/134) | (none) | file branch coverage <50% per summary |
| `runBafJackpot( uint256 poolWei, uint24 lvl, uint256 rngWord ) external returns (uint256 claimableDelta)` | external | CRITICAL_GAP | 36.57% (49/134) | (none) | file branch coverage <50% per summary |

### Contract: `contracts/modules/DegenerusGameLootboxModule.sol`

**Deployable:** yes (delegatecall target, deploys as own address).
**File-level branch coverage:** 25.81% (40/155).
**File-level function coverage:** 50.00% (12/24).

| Function (signature) | Visibility | Verdict | Branch Cov | Test Ref | Notes |
|----------------------|------------|---------|-----------:|----------|-------|
| `openLootBox(address player, uint48 index) external` | external | CRITICAL_GAP | 25.81% (40/155) | (none) | file branch coverage <50% per summary |
| `openBurnieLootBox(address player, uint48 index) external` | external | CRITICAL_GAP | 25.81% (40/155) | (none) | file branch coverage <50% per summary |
| `resolveLootboxDirect(address player, uint256 amount, uint256 rngWord) external` | external | CRITICAL_GAP | 25.81% (40/155) | (none) | file branch coverage <50% per summary |
| `resolveRedemptionLootbox(address player, uint256 amount, uint256 rngWord, uint16 activityScore) external` | external | CRITICAL_GAP | 25.81% (40/155) | (none) | file branch coverage <50% per summary |
| `deityBoonSlots( address deity ) external view returns (uint8[3] memory slots, uint8 usedMask, uint32 day)` | external view | EXEMPT | — | — | D-11: view/pure |
| `issueDeityBoon(address deity, address recipient, uint8 slot) external` | external | CRITICAL_GAP | 25.81% (40/155) | (none) | file branch coverage <50% per summary |

### Contract: `contracts/modules/DegenerusGameMintModule.sol`

**Deployable:** yes (delegatecall target, deploys as own address).
**File-level branch coverage:** 47.06% (64/136).
**File-level function coverage:** 57.89% (11/19).

| Function (signature) | Visibility | Verdict | Branch Cov | Test Ref | Notes |
|----------------------|------------|---------|-----------:|----------|-------|
| `recordMintData( address player, uint24 lvl, uint32 mintUnits ) external payable` | external payable | CRITICAL_GAP | 47.06% (64/136) | (none) | file branch coverage <50% per summary |
| `processFutureTicketBatch( uint24 lvl ) external returns (bool worked, bool finished, uint32 writesUsed)` | external | CRITICAL_GAP | 47.06% (64/136) | (none) | file branch coverage <50% per summary |
| `processTicketBatch(uint24 lvl) external returns (bool finished)` | external | CRITICAL_GAP | 47.06% (64/136) | (none) | file branch coverage <50% per summary |
| `purchase( address buyer, uint256 ticketQuantity, uint256 lootBoxAmount, bytes32 affiliateCode, MintPaymentKind payKind ) external payable` | external payable | CRITICAL_GAP | 47.06% (64/136) | (none) | file branch coverage <50% per summary |
| `purchaseCoin( address buyer, uint256 ticketQuantity, uint256 lootBoxBurnieAmount ) external` | external | CRITICAL_GAP | 47.06% (64/136) | (none) | file branch coverage <50% per summary |
| `purchaseBurnieLootbox( address buyer, uint256 burnieAmount ) external` | external | CRITICAL_GAP | 47.06% (64/136) | (none) | file branch coverage <50% per summary |

### Contract: `contracts/modules/DegenerusGameWhaleModule.sol`

**Deployable:** yes (delegatecall target, deploys as own address).
**File-level branch coverage:** 46.51% (40/86).
**File-level function coverage:** 100.00% (13/13).

| Function (signature) | Visibility | Verdict | Branch Cov | Test Ref | Notes |
|----------------------|------------|---------|-----------:|----------|-------|
| `purchaseWhaleBundle( address buyer, uint256 quantity ) external payable` | external payable | CRITICAL_GAP | 46.51% (40/86) | (none) | file branch coverage <50% per summary |
| `purchaseLazyPass(address buyer) external payable` | external payable | CRITICAL_GAP | 46.51% (40/86) | (none) | file branch coverage <50% per summary |
| `purchaseDeityPass(address buyer, uint8 symbolId) external payable` | external payable | CRITICAL_GAP | 46.51% (40/86) | (none) | file branch coverage <50% per summary |
| `claimWhalePass(address player) external` | external | CRITICAL_GAP | 46.51% (40/86) | (none) | file branch coverage <50% per summary |

## Phase 223 Handoff Preview

**Coverage matrix summary:**

| Metric | Count |
|--------|------:|
| Deployable contracts classified | 24 |
| External/public functions classified | 308 |
| COVERED | 0 |
| CRITICAL_GAP | 196 |
| EXEMPT | 112 |

**Finding ID reservation:** Plan 222-02 introduces the `INFO-222-01-{N}` namespace for any CRITICAL_GAP that remains unclosed after Plan 222-02's test-writing pass. Phase 223's findings rollup consumes these IDs directly.

**CRITICAL_GAP work queue for Plan 222-02** (ranking rule: modules before top-level contracts — modules are deeper in the call chain and harder to reach, so priority; within each group, ordered by source appearance):

- `contracts/BurnieCoin.sol:approve(address spender, uint256 amount)` — file branch coverage 7.14% (3/42)
- `contracts/BurnieCoin.sol:transfer(address to, uint256 amount)` — file branch coverage 7.14% (3/42)
- `contracts/BurnieCoin.sol:transferFrom( address from, address to, uint256 amount )` — file branch coverage 7.14% (3/42)
- `contracts/BurnieCoin.sol:burnForCoinflip(address from, uint256 amount)` — file branch coverage 7.14% (3/42)
- `contracts/BurnieCoin.sol:mintForGame(address to, uint256 amount)` — file branch coverage 7.14% (3/42)
- `contracts/BurnieCoin.sol:vaultEscrow(uint256 amount)` — file branch coverage 7.14% (3/42)
- `contracts/BurnieCoin.sol:vaultMintTo(address to, uint256 amount)` — file branch coverage 7.14% (3/42)
- `contracts/BurnieCoin.sol:burnCoin( address target, uint256 amount )` — file branch coverage 7.14% (3/42)
- `contracts/BurnieCoin.sol:decimatorBurn(address player, uint256 amount)` — file branch coverage 7.14% (3/42)
- `contracts/BurnieCoin.sol:terminalDecimatorBurn(address player, uint256 amount)` — file branch coverage 7.14% (3/42)
- `contracts/BurnieCoinflip.sol:settleFlipModeChange(address player)` — file branch coverage 35.71% (40/112)
- `contracts/BurnieCoinflip.sol:depositCoinflip(address player, uint256 amount)` — file branch coverage 35.71% (40/112)
- `contracts/BurnieCoinflip.sol:claimCoinflips( address player, uint256 amount )` — file branch coverage 35.71% (40/112)
- `contracts/BurnieCoinflip.sol:claimCoinflipsFromBurnie( address player, uint256 amount )` — file branch coverage 35.71% (40/112)
- `contracts/BurnieCoinflip.sol:claimCoinflipsForRedemption( address player, uint256 amount )` — file branch coverage 35.71% (40/112)
- `contracts/BurnieCoinflip.sol:consumeCoinflipsForBurn( address player, uint256 amount )` — file branch coverage 35.71% (40/112)
- `contracts/BurnieCoinflip.sol:setCoinflipAutoRebuy( address player, bool enabled, uint256 takeProfit )` — file branch coverage 35.71% (40/112)
- `contracts/BurnieCoinflip.sol:setCoinflipAutoRebuyTakeProfit( address player, uint256 takeProfit )` — file branch coverage 35.71% (40/112)
- `contracts/BurnieCoinflip.sol:processCoinflipPayouts( bool bonusFlip, uint256 rngWord, uint32 epoch )` — file branch coverage 35.71% (40/112)
- `contracts/BurnieCoinflip.sol:creditFlip( address player, uint256 amount )` — file branch coverage 35.71% (40/112)
- `contracts/BurnieCoinflip.sol:creditFlipBatch( address[] calldata players, uint256[] calldata amounts )` — file branch coverage 35.71% (40/112)
- `contracts/DegenerusAdmin.sol:proposeFeedSwap( address newFeed )` — file branch coverage 0.93% (1/107)
- `contracts/DegenerusAdmin.sol:voteFeedSwap(uint256 proposalId, bool approve)` — file branch coverage 0.93% (1/107)
- `contracts/DegenerusAdmin.sol:swapGameEthForStEth()` — file branch coverage 0.93% (1/107)
- `contracts/DegenerusAdmin.sol:propose( address newCoordinator, bytes32 newKeyHash )` — file branch coverage 0.93% (1/107)
- `contracts/DegenerusAdmin.sol:vote(uint256 proposalId, bool approve)` — file branch coverage 0.93% (1/107)
- `contracts/DegenerusAdmin.sol:shutdownVrf()` — file branch coverage 0.93% (1/107)
- `contracts/DegenerusAffiliate.sol:createAffiliateCode(bytes32 code_, uint8 kickbackPct)` — file branch coverage 42.37% (25/59)
- `contracts/DegenerusAffiliate.sol:referPlayer(bytes32 code_)` — file branch coverage 42.37% (25/59)
- `contracts/DegenerusAffiliate.sol:payAffiliate( uint256 amount, bytes32 code, address sender, uint24 lvl, bool isFreshEth, uint16 lootboxActivityScore )` — file branch coverage 42.37% (25/59)
- `contracts/DegenerusDeityPass.sol:setRenderer(address newRenderer)` — file branch coverage 0.00% (0/23)
- `contracts/DegenerusDeityPass.sol:setRenderColors( string calldata outlineColor, string calldata backgroundColor, string calldata nonCryptoSymbolColor )` — file branch coverage 0.00% (0/23)
- `contracts/DegenerusDeityPass.sol:mint(address to, uint256 tokenId)` — file branch coverage 0.00% (0/23)
- `contracts/DegenerusGame.sol:advanceGame()` — file branch coverage 16.20% (29/179)
- `contracts/DegenerusGame.sol:wireVrf( address coordinator_, uint256 subId, bytes32 keyHash_ )` — file branch coverage 16.20% (29/179)
- `contracts/DegenerusGame.sol:recordMint( address player, uint24 lvl, uint256 costWei, uint32 mintUnits, MintPaymentKind payKind )` — file branch coverage 16.20% (29/179)
- `contracts/DegenerusGame.sol:recordMintQuestStreak(address player)` — file branch coverage 16.20% (29/179)
- `contracts/DegenerusGame.sol:payCoinflipBountyDgnrs( address player, uint256 winningBet, uint256 bountyPool )` — file branch coverage 16.20% (29/179)
- `contracts/DegenerusGame.sol:setOperatorApproval(address operator, bool approved)` — file branch coverage 16.20% (29/179)
- `contracts/DegenerusGame.sol:setLootboxRngThreshold(uint256 newThreshold)` — file branch coverage 16.20% (29/179)
- `contracts/DegenerusGame.sol:purchase( address buyer, uint256 ticketQuantity, uint256 lootBoxAmount, bytes32 affiliateCode, MintPaymentKind payKind )` — file branch coverage 16.20% (29/179)
- `contracts/DegenerusGame.sol:purchaseCoin( address buyer, uint256 ticketQuantity, uint256 lootBoxBurnieAmount )` — file branch coverage 16.20% (29/179)
- `contracts/DegenerusGame.sol:purchaseBurnieLootbox( address buyer, uint256 burnieAmount )` — file branch coverage 16.20% (29/179)
- `contracts/DegenerusGame.sol:purchaseWhaleBundle( address buyer, uint256 quantity )` — file branch coverage 16.20% (29/179)
- `contracts/DegenerusGame.sol:purchaseLazyPass(address buyer)` — file branch coverage 16.20% (29/179)
- `contracts/DegenerusGame.sol:purchaseDeityPass(address buyer, uint8 symbolId)` — file branch coverage 16.20% (29/179)
- `contracts/DegenerusGame.sol:openLootBox(address player, uint48 lootboxIndex)` — file branch coverage 16.20% (29/179)
- `contracts/DegenerusGame.sol:openBurnieLootBox(address player, uint48 lootboxIndex)` — file branch coverage 16.20% (29/179)
- `contracts/DegenerusGame.sol:placeDegeneretteBet( address player, uint8 currency, uint128 amountPerTicket, uint8 ticketCount, uint32 customTicket, uint8 heroQuadrant )` — file branch coverage 16.20% (29/179)
- `contracts/DegenerusGame.sol:resolveDegeneretteBets( address player, uint64[] calldata betIds )` — file branch coverage 16.20% (29/179)
- `contracts/DegenerusGame.sol:consumeCoinflipBoon( address player )` — file branch coverage 16.20% (29/179)
- `contracts/DegenerusGame.sol:consumeDecimatorBoon( address player )` — file branch coverage 16.20% (29/179)
- `contracts/DegenerusGame.sol:consumePurchaseBoost( address player )` — file branch coverage 16.20% (29/179)
- `contracts/DegenerusGame.sol:issueDeityBoon( address deity, address recipient, uint8 slot )` — file branch coverage 16.20% (29/179)
- `contracts/DegenerusGame.sol:recordDecBurn( address player, uint24 lvl, uint8 bucket, uint256 baseAmount, uint256 multBps )` — file branch coverage 16.20% (29/179)
- `contracts/DegenerusGame.sol:runDecimatorJackpot( uint256 poolWei, uint24 lvl, uint256 rngWord )` — file branch coverage 16.20% (29/179)
- `contracts/DegenerusGame.sol:runBafJackpot( uint256 poolWei, uint24 lvl, uint256 rngWord )` — file branch coverage 16.20% (29/179)
- `contracts/DegenerusGame.sol:recordTerminalDecBurn( address player, uint24 lvl, uint256 baseAmount )` — file branch coverage 16.20% (29/179)
- `contracts/DegenerusGame.sol:runTerminalDecimatorJackpot( uint256 poolWei, uint24 lvl, uint256 rngWord )` — file branch coverage 16.20% (29/179)
- `contracts/DegenerusGame.sol:runTerminalJackpot( uint256 poolWei, uint24 targetLvl, uint256 rngWord )` — file branch coverage 16.20% (29/179)
- `contracts/DegenerusGame.sol:consumeDecClaim( address player, uint24 lvl )` — file branch coverage 16.20% (29/179)
- `contracts/DegenerusGame.sol:claimDecimatorJackpot(uint24 lvl)` — file branch coverage 16.20% (29/179)
- `contracts/DegenerusGame.sol:claimWinnings(address player)` — file branch coverage 16.20% (29/179)
- `contracts/DegenerusGame.sol:claimWinningsStethFirst()` — file branch coverage 16.20% (29/179)
- `contracts/DegenerusGame.sol:claimAffiliateDgnrs(address player)` — file branch coverage 16.20% (29/179)
- `contracts/DegenerusGame.sol:setAutoRebuy(address player, bool enabled)` — file branch coverage 16.20% (29/179)
- `contracts/DegenerusGame.sol:setAutoRebuyTakeProfit( address player, uint256 takeProfit )` — file branch coverage 16.20% (29/179)
- `contracts/DegenerusGame.sol:setAfKingMode( address player, bool enabled, uint256 ethTakeProfit, uint256 coinTakeProfit )` — file branch coverage 16.20% (29/179)
- `contracts/DegenerusGame.sol:deactivateAfKingFromCoin(address player)` — file branch coverage 16.20% (29/179)
- `contracts/DegenerusGame.sol:syncAfKingLazyPassFromCoin( address player )` — file branch coverage 16.20% (29/179)
- `contracts/DegenerusGame.sol:claimWhalePass(address player)` — file branch coverage 16.20% (29/179)
- `contracts/DegenerusGame.sol:resolveRedemptionLootbox( address player, uint256 amount, uint256 rngWord, uint16 activityScore )` — file branch coverage 16.20% (29/179)
- `contracts/DegenerusGame.sol:adminSwapEthForStEth( address recipient, uint256 amount )` — file branch coverage 16.20% (29/179)
- `contracts/DegenerusGame.sol:adminStakeEthForStEth(uint256 amount)` — file branch coverage 16.20% (29/179)
- `contracts/DegenerusGame.sol:updateVrfCoordinatorAndSub( address newCoordinator, uint256 newSubId, bytes32 newKeyHash )` — file branch coverage 16.20% (29/179)
- `contracts/DegenerusGame.sol:requestLootboxRng()` — file branch coverage 16.20% (29/179)
- `contracts/DegenerusGame.sol:reverseFlip()` — file branch coverage 16.20% (29/179)
- `contracts/DegenerusJackpots.sol:recordBafFlip(address player, uint24 lvl, uint256 amount)` — file branch coverage 1.96% (1/51)
- `contracts/DegenerusJackpots.sol:runBafJackpot( uint256 poolWei, uint24 lvl, uint256 rngWord )` — file branch coverage 1.96% (1/51)
- `contracts/DegenerusQuests.sol:rollDailyQuest(uint32 day, uint256 entropy)` — file branch coverage 39.68% (50/126)
- `contracts/DegenerusQuests.sol:awardQuestStreakBonus(address player, uint16 amount, uint32 currentDay)` — file branch coverage 39.68% (50/126)
- `contracts/DegenerusQuests.sol:handleMint( address player, uint32 quantity, bool paidWithEth, uint256 mintPrice )` — file branch coverage 39.68% (50/126)
- `contracts/DegenerusQuests.sol:handleFlip( address player, uint256 flipCredit )` — file branch coverage 39.68% (50/126)
- `contracts/DegenerusQuests.sol:handleDecimator( address player, uint256 burnAmount )` — file branch coverage 39.68% (50/126)
- `contracts/DegenerusQuests.sol:handleAffiliate( address player, uint256 amount )` — file branch coverage 39.68% (50/126)
- `contracts/DegenerusQuests.sol:handleLootBox( address player, uint256 amountWei, uint256 mintPrice )` — file branch coverage 39.68% (50/126)
- `contracts/DegenerusQuests.sol:handlePurchase( address player, uint32 ethMintQty, uint32 burnieMintQty, uint256 lootBoxAmount, uint256 mintPrice, uint256 levelQuestPrice )` — file branch coverage 39.68% (50/126)
- `contracts/DegenerusQuests.sol:handleDegenerette( address player, uint256 amount, bool paidWithEth, uint256 mintPrice )` — file branch coverage 39.68% (50/126)
- `contracts/DegenerusQuests.sol:rollLevelQuest(uint256 entropy)` — file branch coverage 39.68% (50/126)
- `contracts/DegenerusStonk.sol:transfer(address to, uint256 amount)` — file branch coverage 0.00% (0/34)
- `contracts/DegenerusStonk.sol:transferFrom(address from, address to, uint256 amount)` — file branch coverage 0.00% (0/34)
- `contracts/DegenerusStonk.sol:approve(address spender, uint256 amount)` — file branch coverage 0.00% (0/34)
- `contracts/DegenerusStonk.sol:unwrapTo(address recipient, uint256 amount)` — file branch coverage 0.00% (0/34)
- `contracts/DegenerusStonk.sol:claimVested()` — file branch coverage 0.00% (0/34)
- `contracts/DegenerusStonk.sol:burn(uint256 amount)` — file branch coverage 0.00% (0/34)
- `contracts/DegenerusStonk.sol:yearSweep()` — file branch coverage 0.00% (0/34)
- `contracts/DegenerusStonk.sol:burnForSdgnrs(address player, uint256 amount)` — file branch coverage 0.00% (0/34)
- `contracts/DegenerusVault.sol:approve(address spender, uint256 amount)` — file branch coverage 14.29% (9/63)
- `contracts/DegenerusVault.sol:transfer(address to, uint256 amount)` — file branch coverage 14.29% (9/63)
- `contracts/DegenerusVault.sol:transferFrom(address from, address to, uint256 amount)` — file branch coverage 14.29% (9/63)
- `contracts/DegenerusVault.sol:vaultMint(address to, uint256 amount)` — file branch coverage 14.29% (9/63)
- `contracts/DegenerusVault.sol:vaultBurn(address from, uint256 amount)` — file branch coverage 14.29% (9/63)
- `contracts/DegenerusVault.sol:deposit(uint256 coinAmount, uint256 stEthAmount)` — file branch coverage 14.29% (9/63)
- `contracts/DegenerusVault.sol:gameAdvance()` — file branch coverage 14.29% (9/63)
- `contracts/DegenerusVault.sol:gamePurchase( uint256 ticketQuantity, uint256 lootBoxAmount, bytes32 affiliateCode, MintPaymentKind payKind, uint256 ethValue )` — file branch coverage 14.29% (9/63)
- `contracts/DegenerusVault.sol:gamePurchaseTicketsBurnie(uint256 ticketQuantity)` — file branch coverage 14.29% (9/63)
- `contracts/DegenerusVault.sol:gamePurchaseBurnieLootbox(uint256 burnieAmount)` — file branch coverage 14.29% (9/63)
- `contracts/DegenerusVault.sol:gameOpenLootBox(uint48 lootboxIndex)` — file branch coverage 14.29% (9/63)
- `contracts/DegenerusVault.sol:gamePurchaseDeityPassFromBoon(uint256 priceWei, uint8 symbolId)` — file branch coverage 14.29% (9/63)
- `contracts/DegenerusVault.sol:gameClaimWinnings()` — file branch coverage 14.29% (9/63)
- `contracts/DegenerusVault.sol:gameClaimWhalePass()` — file branch coverage 14.29% (9/63)
- `contracts/DegenerusVault.sol:gameDegeneretteBet( uint8 currency, uint128 amountPerTicket, uint8 ticketCount, uint32 customTicket, uint8 heroQuadrant, uint256 ethValue )` — file branch coverage 14.29% (9/63)
- `contracts/DegenerusVault.sol:gameResolveDegeneretteBets(uint64[] calldata betIds)` — file branch coverage 14.29% (9/63)
- `contracts/DegenerusVault.sol:gameSetAutoRebuy(bool enabled)` — file branch coverage 14.29% (9/63)
- `contracts/DegenerusVault.sol:gameSetAutoRebuyTakeProfit(uint256 takeProfit)` — file branch coverage 14.29% (9/63)
- `contracts/DegenerusVault.sol:gameSetDecimatorAutoRebuy(bool enabled)` — file branch coverage 14.29% (9/63)
- `contracts/DegenerusVault.sol:gameSetAfKingMode( bool enabled, uint256 ethTakeProfit, uint256 coinTakeProfit )` — file branch coverage 14.29% (9/63)
- `contracts/DegenerusVault.sol:gameSetOperatorApproval(address operator, bool approved)` — file branch coverage 14.29% (9/63)
- `contracts/DegenerusVault.sol:coinDepositCoinflip(uint256 amount)` — file branch coverage 14.29% (9/63)
- `contracts/DegenerusVault.sol:coinClaimCoinflips(uint256 amount)` — file branch coverage 14.29% (9/63)
- `contracts/DegenerusVault.sol:coinDecimatorBurn(uint256 amount)` — file branch coverage 14.29% (9/63)
- `contracts/DegenerusVault.sol:coinSetAutoRebuy(bool enabled, uint256 takeProfit)` — file branch coverage 14.29% (9/63)
- `contracts/DegenerusVault.sol:coinSetAutoRebuyTakeProfit(uint256 takeProfit)` — file branch coverage 14.29% (9/63)
- `contracts/DegenerusVault.sol:wwxrpMint(address to, uint256 amount)` — file branch coverage 14.29% (9/63)
- `contracts/DegenerusVault.sol:jackpotsClaimDecimator(uint24 lvl)` — file branch coverage 14.29% (9/63)
- `contracts/DegenerusVault.sol:sdgnrsBurn(uint256 amount)` — file branch coverage 14.29% (9/63)
- `contracts/DegenerusVault.sol:sdgnrsClaimRedemption()` — file branch coverage 14.29% (9/63)
- `contracts/DegenerusVault.sol:burnCoin(address player, uint256 amount)` — file branch coverage 14.29% (9/63)
- `contracts/DegenerusVault.sol:burnEth( address player, uint256 amount )` — file branch coverage 14.29% (9/63)
- `contracts/GNRUS.sol:burn(uint256 amount)` — file branch coverage 5.56% (2/36)
- `contracts/GNRUS.sol:burnAtGameOver()` — file branch coverage 5.56% (2/36)
- `contracts/GNRUS.sol:propose(address recipient)` — file branch coverage 5.56% (2/36)
- `contracts/GNRUS.sol:vote(uint48 proposalId, bool approveVote)` — file branch coverage 5.56% (2/36)
- `contracts/GNRUS.sol:pickCharity(uint24 level)` — file branch coverage 5.56% (2/36)
- `contracts/Icons32Data.sol:setPaths(uint256 startIndex, string[] calldata paths)` — file branch coverage 0.00% (0/17)
- `contracts/Icons32Data.sol:setSymbols(uint256 quadrant, string[8] memory symbols)` — file branch coverage 0.00% (0/17)
- `contracts/Icons32Data.sol:finalize()` — file branch coverage 0.00% (0/17)
- `contracts/StakedDegenerusStonk.sol:wrapperTransferTo(address to, uint256 amount)` — file branch coverage 33.33% (22/66)
- `contracts/StakedDegenerusStonk.sol:gameAdvance()` — file branch coverage 33.33% (22/66)
- `contracts/StakedDegenerusStonk.sol:gameClaimWhalePass()` — file branch coverage 33.33% (22/66)
- `contracts/StakedDegenerusStonk.sol:depositSteth(uint256 amount)` — file branch coverage 33.33% (22/66)
- `contracts/StakedDegenerusStonk.sol:transferFromPool(Pool pool, address to, uint256 amount)` — file branch coverage 33.33% (22/66)
- `contracts/StakedDegenerusStonk.sol:transferBetweenPools(Pool from, Pool to, uint256 amount)` — file branch coverage 33.33% (22/66)
- `contracts/StakedDegenerusStonk.sol:burnAtGameOver()` — file branch coverage 33.33% (22/66)
- `contracts/StakedDegenerusStonk.sol:burn(uint256 amount)` — file branch coverage 33.33% (22/66)
- `contracts/StakedDegenerusStonk.sol:burnWrapped(uint256 amount)` — file branch coverage 33.33% (22/66)
- `contracts/StakedDegenerusStonk.sol:resolveRedemptionPeriod(uint16 roll, uint32 flipDay)` — file branch coverage 33.33% (22/66)
- `contracts/StakedDegenerusStonk.sol:claimRedemption()` — file branch coverage 33.33% (22/66)
- `contracts/WrappedWrappedXRP.sol:approve(address spender, uint256 amount)` — file branch coverage 0.00% (0/15)
- `contracts/WrappedWrappedXRP.sol:transfer(address to, uint256 amount)` — file branch coverage 0.00% (0/15)
- `contracts/WrappedWrappedXRP.sol:transferFrom( address from, address to, uint256 amount )` — file branch coverage 0.00% (0/15)
- `contracts/WrappedWrappedXRP.sol:mintPrize(address to, uint256 amount)` — file branch coverage 0.00% (0/15)
- `contracts/WrappedWrappedXRP.sol:vaultMintTo(address to, uint256 amount)` — file branch coverage 0.00% (0/15)
- `contracts/WrappedWrappedXRP.sol:burnForGame(address from, uint256 amount)` — file branch coverage 0.00% (0/15)
- `contracts/modules/DegenerusGameAdvanceModule.sol:advanceGame()` — file branch coverage 48.00% (72/150)
- `contracts/modules/DegenerusGameAdvanceModule.sol:wireVrf( address coordinator_, uint256 subId, bytes32 keyHash_ )` — file branch coverage 48.00% (72/150)
- `contracts/modules/DegenerusGameAdvanceModule.sol:requestLootboxRng()` — file branch coverage 48.00% (72/150)
- `contracts/modules/DegenerusGameAdvanceModule.sol:updateVrfCoordinatorAndSub( address newCoordinator, uint256 newSubId, bytes32 newKeyHash )` — file branch coverage 48.00% (72/150)
- `contracts/modules/DegenerusGameBoonModule.sol:consumeCoinflipBoon(address player)` — file branch coverage 2.04% (1/49)
- `contracts/modules/DegenerusGameBoonModule.sol:consumePurchaseBoost(address player)` — file branch coverage 2.04% (1/49)
- `contracts/modules/DegenerusGameBoonModule.sol:consumeDecimatorBoost(address player)` — file branch coverage 2.04% (1/49)
- `contracts/modules/DegenerusGameBoonModule.sol:checkAndClearExpiredBoon(address player)` — file branch coverage 2.04% (1/49)
- `contracts/modules/DegenerusGameBoonModule.sol:consumeActivityBoon(address player)` — file branch coverage 2.04% (1/49)
- `contracts/modules/DegenerusGameDecimatorModule.sol:recordDecBurn( address player, uint24 lvl, uint8 bucket, uint256 baseAmount, uint256 multBps )` — file branch coverage 1.59% (1/63)
- `contracts/modules/DegenerusGameDecimatorModule.sol:runDecimatorJackpot( uint256 poolWei, uint24 lvl, uint256 rngWord )` — file branch coverage 1.59% (1/63)
- `contracts/modules/DegenerusGameDecimatorModule.sol:consumeDecClaim( address player, uint24 lvl )` — file branch coverage 1.59% (1/63)
- `contracts/modules/DegenerusGameDecimatorModule.sol:claimDecimatorJackpot(uint24 lvl)` — file branch coverage 1.59% (1/63)
- `contracts/modules/DegenerusGameDecimatorModule.sol:recordTerminalDecBurn( address player, uint24 lvl, uint256 baseAmount )` — file branch coverage 1.59% (1/63)
- `contracts/modules/DegenerusGameDecimatorModule.sol:runTerminalDecimatorJackpot( uint256 poolWei, uint24 lvl, uint256 rngWord )` — file branch coverage 1.59% (1/63)
- `contracts/modules/DegenerusGameDecimatorModule.sol:claimTerminalDecimatorJackpot()` — file branch coverage 1.59% (1/63)
- `contracts/modules/DegenerusGameDegeneretteModule.sol:placeDegeneretteBet( address player, uint8 currency, uint128 amountPerTicket, uint8 ticketCount, uint32 customTicket, uint8 heroQuadrant )` — file branch coverage 34.48% (30/87)
- `contracts/modules/DegenerusGameDegeneretteModule.sol:resolveBets(address player, uint64[] calldata betIds)` — file branch coverage 34.48% (30/87)
- `contracts/modules/DegenerusGameGameOverModule.sol:handleGameOverDrain(uint32 day)` — file branch coverage 42.31% (11/26)
- `contracts/modules/DegenerusGameGameOverModule.sol:handleFinalSweep()` — file branch coverage 42.31% (11/26)
- `contracts/modules/DegenerusGameJackpotModule.sol:runTerminalJackpot( uint256 poolWei, uint24 targetLvl, uint256 rngWord )` — file branch coverage 36.57% (49/134)
- `contracts/modules/DegenerusGameJackpotModule.sol:payDailyJackpot( bool isJackpotPhase, uint24 lvl, uint256 randWord )` — file branch coverage 36.57% (49/134)
- `contracts/modules/DegenerusGameJackpotModule.sol:payDailyJackpotCoinAndTickets(uint256 randWord)` — file branch coverage 36.57% (49/134)
- `contracts/modules/DegenerusGameJackpotModule.sol:distributeYieldSurplus(uint256 rngWord)` — file branch coverage 36.57% (49/134)
- `contracts/modules/DegenerusGameJackpotModule.sol:payDailyCoinJackpot(uint24 lvl, uint256 randWord, uint24 minLevel, uint24 maxLevel)` — file branch coverage 36.57% (49/134)
- `contracts/modules/DegenerusGameJackpotModule.sol:emitDailyWinningTraits(uint24, uint256 randWord, uint24 bonusTargetLevel)` — file branch coverage 36.57% (49/134)
- `contracts/modules/DegenerusGameJackpotModule.sol:runBafJackpot( uint256 poolWei, uint24 lvl, uint256 rngWord )` — file branch coverage 36.57% (49/134)
- `contracts/modules/DegenerusGameLootboxModule.sol:openLootBox(address player, uint48 index)` — file branch coverage 25.81% (40/155)
- `contracts/modules/DegenerusGameLootboxModule.sol:openBurnieLootBox(address player, uint48 index)` — file branch coverage 25.81% (40/155)
- `contracts/modules/DegenerusGameLootboxModule.sol:resolveLootboxDirect(address player, uint256 amount, uint256 rngWord)` — file branch coverage 25.81% (40/155)
- `contracts/modules/DegenerusGameLootboxModule.sol:resolveRedemptionLootbox(address player, uint256 amount, uint256 rngWord, uint16 activityScore)` — file branch coverage 25.81% (40/155)
- `contracts/modules/DegenerusGameLootboxModule.sol:issueDeityBoon(address deity, address recipient, uint8 slot)` — file branch coverage 25.81% (40/155)
- `contracts/modules/DegenerusGameMintModule.sol:recordMintData( address player, uint24 lvl, uint32 mintUnits )` — file branch coverage 47.06% (64/136)
- `contracts/modules/DegenerusGameMintModule.sol:processFutureTicketBatch( uint24 lvl )` — file branch coverage 47.06% (64/136)
- `contracts/modules/DegenerusGameMintModule.sol:processTicketBatch(uint24 lvl)` — file branch coverage 47.06% (64/136)
- `contracts/modules/DegenerusGameMintModule.sol:purchase( address buyer, uint256 ticketQuantity, uint256 lootBoxAmount, bytes32 affiliateCode, MintPaymentKind payKind )` — file branch coverage 47.06% (64/136)
- `contracts/modules/DegenerusGameMintModule.sol:purchaseCoin( address buyer, uint256 ticketQuantity, uint256 lootBoxBurnieAmount )` — file branch coverage 47.06% (64/136)
- `contracts/modules/DegenerusGameMintModule.sol:purchaseBurnieLootbox( address buyer, uint256 burnieAmount )` — file branch coverage 47.06% (64/136)
- `contracts/modules/DegenerusGameWhaleModule.sol:purchaseWhaleBundle( address buyer, uint256 quantity )` — file branch coverage 46.51% (40/86)
- `contracts/modules/DegenerusGameWhaleModule.sol:purchaseLazyPass(address buyer)` — file branch coverage 46.51% (40/86)
- `contracts/modules/DegenerusGameWhaleModule.sol:purchaseDeityPass(address buyer, uint8 symbolId)` — file branch coverage 46.51% (40/86)
- `contracts/modules/DegenerusGameWhaleModule.sol:claimWhalePass(address player)` — file branch coverage 46.51% (40/86)

*Matrix generated by `/tmp/build_matrix.sh` via source enumeration + summary-branch-coverage classification. Per-function refinement via lcov.info is left to Plan 222-02.*
