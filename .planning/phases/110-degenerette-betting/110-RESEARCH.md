# Phase 110: Degenerette Betting - Research

## Contract Under Audit

**DegenerusGameDegeneretteModule.sol** -- 1,179 lines (including constants, events, interfaces)
- Inherits: DegenerusGamePayoutUtils -> DegenerusGameMintStreakUtils -> DegenerusGameStorage
- Executed via delegatecall from DegenerusGame.sol (all storage reads/writes operate on Game's storage)
- 2 external entry points, 25 private helpers
- Multi-currency betting system: ETH, BURNIE, WWXRP

## Complete Function Inventory

### Category B: External State-Changing Functions (2)

| # | Function | Lines | Access Control | Risk Tier | Key Concern |
|---|----------|-------|---------------|-----------|-------------|
| B1 | `placeFullTicketBets(address,uint8,uint128,uint8,uint32,uint8)` | 388-404 | any (via router delegatecall, operator-approved) | Tier 1 | Multi-currency ETH/BURNIE/WWXRP bet placement, pool accounting, hero wager tracking, activity score snapshot, claimable ETH pull |
| B2 | `resolveBets(address,uint64[])` | 411-423 | any (via router delegatecall, operator-approved) | Tier 1 | Multi-bet resolution loop, RNG word lookup, payout distribution across 3 currencies, delegatecall to LootboxModule, futurePrizePool deduction, sDGNRS rewards |

**Risk tier justification:**
- **B1 (Tier 1):** Handles ETH payment with partial claimable pull (off-by-one concern at L552), burns BURNIE/WWXRP tokens, writes to futurePrizePool/pendingPools, activity score snapshot stored in bet, hero wager tracking with packed arithmetic. Multiple storage writes: degeneretteBets, degeneretteBetNonce, claimableWinnings, claimablePool, prizePoolsPacked/pendingPoolsPacked, lootboxRngPendingEth/lootboxRngPendingBurnie, dailyHeroWagers, playerDegeneretteEthWagered, topDegeneretteByLevel. External calls: coin.burnCoin, wwxrp.burnForGame, coin.notifyQuestDegenerette.
- **B2 (Tier 1):** Resolution loop processes arbitrary number of bets. Per-spin: RNG derivation, match counting, payout calculation with EV normalization + hero multiplier, ETH distribution with pool cap + lootbox delegatecall, BURNIE mint, WWXRP mint, sDGNRS reward transfer. Storage: degeneretteBets (delete), claimableWinnings, claimablePool, futurePrizePool (via _setFuturePrizePool), plus all lootbox storage from delegatecall. External calls: coin.mintForGame, wwxrp.mintPrize, sdgnrs.poolBalance, sdgnrs.transferFromPool, delegatecall to LootboxModule.

### Category C: Internal/Private State-Changing Helpers (10)

| # | Function | Lines | Called By | Key Storage Writes | Flags |
|---|----------|-------|-----------|-------------------|-------|
| C1 | `_placeFullTicketBets(address,uint8,uint128,uint8,uint32,uint8)` | 430-460 | B1 | All B1 writes via C2+C3, external: coin.notifyQuestDegenerette | |
| C2 | `_placeFullTicketBetsCore(address,uint8,uint128,uint8,uint32,uint8)` | 462-525 | C1 | degeneretteBets[], degeneretteBetNonce[], dailyHeroWagers[][], playerDegeneretteEthWagered[][], topDegeneretteByLevel[] | |
| C3 | `_collectBetFunds(address,uint8,uint256,uint256)` | 541-574 | C1 | claimableWinnings[], claimablePool, prizePoolsPacked/pendingPoolsPacked, lootboxRngPendingEth, lootboxRngPendingBurnie. External: coin.burnCoin, wwxrp.burnForGame | |
| C4 | `_resolveBet(address,uint64)` | 577-582 | B2 (loop) | Delegates to C5 | |
| C5 | `_resolveFullTicketBet(address,uint64,uint256)` | 585-672 | C4 | degeneretteBets[] (delete), claimableWinnings[], claimablePool (via C6), futurePrizePool (via C6). External: coin.mintForGame, wwxrp.mintPrize. Delegatecall: LootboxModule (via C7). External: sdgnrs.poolBalance, sdgnrs.transferFromPool (via C9). External: wwxrp.mintPrize (via C10) | |
| C6 | `_distributePayout(address,uint8,uint256,uint256)` | 680-715 | C5 (per-spin, per-win) | claimableWinnings[], claimablePool (via _addClaimableEth), futurePrizePool (via _setFuturePrizePool). External: coin.mintForGame, wwxrp.mintPrize. Delegatecall: LootboxModule (via C7) | [MULTI-PARENT: called per-spin within C5 loop] |
| C7 | `_resolveLootboxDirect(address,uint256,uint256)` | 741-757 | C6 (ETH path only) | All LootboxModule storage (via delegatecall) | |
| C8 | `_addClaimableEth(address,uint256)` | 1153-1160 | C6 (ETH path) | claimablePool, claimableWinnings[] (via _creditClaimable) | |
| C9 | `_awardDegeneretteDgnrs(address,uint256,uint8)` | 1164-1178 | C5 (6+ match ETH bets) | External only: sdgnrs.transferFromPool (Reward pool) | |
| C10 | `_maybeAwardConsolation(address,uint8,uint128)` | 722-737 | C5 (total payout == 0) | External only: wwxrp.mintPrize | |

### Category D: View/Pure Functions (15)

| # | Function | Lines | Reads/Computes | Security Note |
|---|----------|-------|---------------|---------------|
| D1 | `_revertDelegate(bytes)` | 141-146 | Pure: assembly revert propagation | Verify no memory corruption |
| D2 | `_requireApproved(address)` | 150-153 | View: reads operatorApprovals[player][msg.sender] | Access control gate |
| D3 | `_resolvePlayer(address)` | 160-166 | View: reads operatorApprovals if player != msg.sender | Player resolution + approval |
| D4 | `_validateMinBet(uint8,uint128)` | 528-538 | Pure: compares against constant minimums | Per-currency minimum enforcement |
| D5 | `_packFullTicketBet(uint32,uint8,uint8,uint128,uint48,uint16,uint8)` | 764-786 | Pure: bit packing | Verify no field overlap in packed uint256 |
| D6 | `_evNormalizationRatio(uint32,uint32)` | 803-846 | Pure: per-outcome probability ratio product | Math correctness for EV equalization |
| D7 | `_countMatches(uint32,uint32)` | 852-876 | Pure: trait attribute matching (0-8 matches) | Color=bits 5-3, Symbol=bits 2-0 per quadrant |
| D8 | `_fullTicketPayout(uint32,uint32,uint8,uint8,uint128,uint256,uint256,bool,uint8)` | 912-961 | Pure: payout calculation with EV normalization and hero multiplier | Complex math; verify no overflow or precision loss |
| D9 | `_applyHeroMultiplier(uint256,uint32,uint32,uint8,uint8)` | 966-985 | Pure: hero quadrant boost/penalty | EV-neutral constraint verification |
| D10 | `_getBasePayoutBps(uint8)` | 990-993 | Pure: match-count to packed payout lookup | Table correctness verification |
| D11 | `_wwxrpBonusBucket(uint8)` | 880-885 | Pure: maps match count to bonus bucket | Bucket assignment logic |
| D12 | `_wwxrpBonusRoiForBucket(uint8,uint256)` | 888-900 | Pure: per-bucket bonus ROI scaling | Factor arithmetic |
| D13 | `_playerActivityScoreInternal(address)` | 1005-1078 | View: reads mintPacked_[], level, deityPassCount[], boonPacked[]; external: questView.playerQuestStates, affiliate.affiliateBonusPointsBest | Complex score computation; verify all components |
| D14 | `_roiBpsFromScore(uint256)` | 1098-1127 | Pure: piecewise curve (quadratic + 2 linear segments) | Verify continuity at breakpoints, no overflow |
| D15 | `_mintCountBonusPoints(uint24,uint24)` | 1084-1091 | Pure: proportional mint count bonus | Division by zero when currLevel==0 (handled) |

**Note on D2/D3:** These read storage (operatorApprovals) but are non-state-changing (view). Classified as D.
**Note on D13:** Reads storage and makes external view calls. Still classified as D because it makes no state changes.

### Summary

| Category | Count | Analysis Depth |
|----------|-------|---------------|
| B: External State-Changing | 2 | Full Mad Genius (per D-02) |
| C: Internal Helpers (State-Changing) | 10 | Via caller call tree; standalone for [MULTI-PARENT] (per D-03) |
| D: View/Pure | 15 | Minimal; verify computation correctness and edge cases |
| **TOTAL** | **27** | |

Plus inherited helpers from PayoutUtils/Storage traced within call trees.

## Cross-Module Delegatecall Map

DegenerusGameDegeneretteModule is called via delegatecall from DegenerusGame.sol router:
- `placeFullTicketBets` dispatched from Game.sol router
- `resolveBets` dispatched from Game.sol router

The module itself makes a delegatecall OUT:
- `_resolveLootboxDirect` (L746-756) delegatecalls to `GAME_LOOTBOX_MODULE.resolveLootboxDirect`
  - This is a delegatecall FROM a delegatecalled module -- both execute in Game's storage context
  - LootboxModule writes to its own storage slots (lootbox resolution data) which are in Game's storage

## External Calls Made by This Module

| Call | From | Target Contract | State Impact |
|------|------|----------------|-------------|
| `coin.burnCoin(player, totalBet)` | C3 (BURNIE bets) | BurnieCoin | Burns BURNIE from player |
| `coin.mintForGame(player, payout)` | C6 (BURNIE payouts) | BurnieCoin | Mints BURNIE to player |
| `coin.notifyQuestDegenerette(player, totalBet, isEth)` | C1 | BurnieCoin | Quest progress tracking |
| `wwxrp.burnForGame(player, totalBet)` | C3 (WWXRP bets) | WrappedWrappedXRP | Burns WWXRP from player |
| `wwxrp.mintPrize(player, payout)` | C6 (WWXRP payouts), C10 (consolation) | WrappedWrappedXRP | Mints WWXRP to player |
| `sdgnrs.poolBalance(Pool.Reward)` | C9 | StakedDegenerusStonk | View only (reads pool balance) |
| `sdgnrs.transferFromPool(Pool.Reward, player, reward)` | C9 | StakedDegenerusStonk | Transfers sDGNRS from Reward pool |
| `questView.playerQuestStates(player)` | D13 | DegenerusQuests | View only (reads quest state) |
| `affiliate.affiliateBonusPointsBest(level, player)` | D13 | DegenerusAffiliate | View only (reads affiliate bonus) |
| LootboxModule.resolveLootboxDirect (delegatecall) | C7 | GAME_LOOTBOX_MODULE | All lootbox resolution storage writes in Game context |

## Storage Variables Written

### Direct Writes (in this module)

| Variable | Written By | Type | Concern |
|----------|-----------|------|---------|
| `degeneretteBets[player][nonce]` | C2 (write), C5 (delete) | mapping(address => mapping(uint64 => uint256)) | Write on place, delete on resolve |
| `degeneretteBetNonce[player]` | C2 | mapping(address => uint64) | Monotonic increment |
| `dailyHeroWagers[day][quadrant]` | C2 (ETH only) | mapping(uint48 => mapping(uint8 => uint256)) | Packed 8x32-bit per symbol |
| `playerDegeneretteEthWagered[player][level]` | C2 (ETH only) | mapping(address => mapping(uint24 => uint256)) | Cumulative per-level |
| `topDegeneretteByLevel[level]` | C2 (ETH only) | mapping(uint24 => uint256) | Packed: (amount << 160) | address |
| `claimableWinnings[player]` | C3 (deduct on bet), C8 (add on payout) | mapping(address => uint256) | ETH claimable balance |
| `claimablePool` | C3 (deduct), C8 (add) | uint256 | Global claimable total |
| `prizePoolsPacked` | C3 (via _setPrizePools, non-frozen) | uint256 | Packed next+future pools |
| `pendingPoolsPacked` | C3 (via _setPendingPools, frozen) | uint256 | Packed pending pools |
| `lootboxRngPendingEth` | C3 (ETH bets) | uint256 | Pending ETH for lootbox RNG |
| `lootboxRngPendingBurnie` | C3 (BURNIE bets) | uint256 | Pending BURNIE for lootbox RNG |

### Indirect Writes (via inherited helpers)

| Variable | Written By | Via |
|----------|-----------|-----|
| `claimableWinnings[beneficiary]` | _creditClaimable (PayoutUtils L30-35) | C8 -> _creditClaimable |
| `prizePoolsPacked` (futurePrizePool portion) | _setFuturePrizePool (Storage L752) | C6 -> _setFuturePrizePool |

### Delegatecall Writes (via LootboxModule)

Not enumerated here -- LootboxModule writes to lootbox-specific storage slots. Full audit in Phase 111. For this phase, we trace state coherence: does any variable cached before the delegatecall get overwritten by the delegatecall?

## Key Risk Areas

### Risk 1: ETH Claimable Pull Off-By-One (L552)
```solidity
if (claimableWinnings[player] <= fromClaimable) revert InvalidBet();
```
This uses `<=` not `<`. If `claimableWinnings[player] == fromClaimable`, the bet reverts. Player cannot use their exact full claimable balance. This means a player with 0.1 ETH claimable cannot place a 0.1 ETH bet entirely from claimable -- they need at least 1 wei more. This may be intentional (ensuring non-zero claimable remains) or a bug.

### Risk 2: prizePoolFrozen Check Gap
- `_collectBetFunds` (L558-564): Checks `prizePoolFrozen` and routes to pending vs live pools
- `_distributePayout` (L685): `if (prizePoolFrozen) revert E();` -- blocks ETH payouts during freeze
- Bet placement can happen during freeze (adds to pending pools). Resolution cannot (reverts on ETH). What about BURNIE/WWXRP resolution during freeze? Those paths don't check prizePoolFrozen and don't touch prize pools -- SAFE for those currencies.

### Risk 3: Delegatecall State Coherence
- `_distributePayout` reads `_getFuturePrizePool()` at L687
- Deducts `ethPortion` at L702, writes back via `_setFuturePrizePool` at L703
- Then calls `_addClaimableEth` at L704 (writes claimableWinnings, claimablePool)
- Then calls `_resolveLootboxDirect` at L708 (delegatecall to LootboxModule)
- If LootboxModule writes to `prizePoolsPacked` or `claimablePool`, the parent's state is already committed (no stale cache). Pool was written at L703, claimable at L704, both BEFORE the delegatecall. SAFE ordering.

### Risk 4: Activity Score Snapshot
- Activity score is computed at bet PLACEMENT time (L480) and stored in packed bet
- At resolution time, the stored score is used (L592, L602), NOT recomputed
- This is intentional: prevents gaming by changing activity score between bet and resolution
- But: if a player's activity score IMPROVES between placement and resolution, they get the lower score. Not a bug, but a design trade-off.

### Risk 5: Hero Wager Packed Arithmetic (L504-511)
- `wagerUnit = totalBet / 1e12` -- truncates to 12-decimal granularity
- `current + wagerUnit` capped at `0xFFFFFFFF` -- max ~4.295 billion units = ~4,295 ETH equivalent
- Wager per symbol per quadrant per day. Unlikely to overflow for a single symbol.

### Risk 6: Spin RNG Derivation
- Spin 0: `keccak256(rngWord, index, QUICK_PLAY_SALT)` (L617)
- Spin N>0: `keccak256(rngWord, index, spinIdx, QUICK_PLAY_SALT)` (L618)
- Different preimages, different results. But spin 0 has a different encoding than spin N. Is there any collision risk between these two formats? No: abi.encodePacked of (uint256, uint48, bytes1) vs (uint256, uint48, uint8, bytes1) have different lengths. SAFE.

---

*Phase: 110-degenerette-betting*
*Research completed: 2026-03-25*
