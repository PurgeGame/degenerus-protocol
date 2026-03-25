# Unit 8: Degenerette Betting -- Coverage Checklist

## Contracts Under Audit
- contracts/modules/DegenerusGameDegeneretteModule.sol (1,179 lines)
- Inherits: DegenerusGamePayoutUtils -> DegenerusGameMintStreakUtils (62 lines) -> DegenerusGameStorage (1,613 lines)

## Methodology
- Per D-01: Categories B/C/D only (no Category A -- this is a module, not the router)
- Per D-02: Category B functions get full Mad Genius treatment
- Per D-03: Category C functions traced via caller call tree; standalone for [MULTI-PARENT]
- Per D-06: Fresh adversarial analysis -- no trusting prior findings
- Per D-08/D-09: Cross-module subordinate calls traced for state coherence
- Per D-10: Multi-currency payout paths (ETH/BURNIE/WWXRP) traced independently

## Checklist Summary

| Category | Count | Analysis Depth |
|----------|-------|---------------|
| B: External State-Changing | 2 | Full Mad Genius (per D-02) |
| C: Internal Helpers (State-Changing) | 10 | Via caller call tree; standalone for [MULTI-PARENT] (per D-03) |
| D: View/Pure | 15 | Minimal; verify computation correctness |
| **TOTAL** | **27** | |

---

## Category B: External State-Changing Functions

| # | Function | Lines | Access Control | Primary Storage Writes | External Calls | Risk Tier | Analyzed? | Call Tree? | Storage Map? | Cache Check? |
|---|----------|-------|---------------|----------------------|----------------|-----------|-----------|------------|-------------|-------------|
| B1 | `placeFullTicketBets(address,uint8,uint128,uint8,uint32,uint8)` | 388-404 | any (via router delegatecall, operator-approved via _resolvePlayer) | degeneretteBets[], degeneretteBetNonce[], dailyHeroWagers[][], playerDegeneretteEthWagered[][], topDegeneretteByLevel[], claimableWinnings[], claimablePool, prizePoolsPacked/pendingPoolsPacked, lootboxRngPendingEth, lootboxRngPendingBurnie | coin.burnCoin, wwxrp.burnForGame, coin.notifyQuestDegenerette | Tier 1 | | | | |
| B2 | `resolveBets(address,uint64[])` | 411-423 | any (via router delegatecall, operator-approved via _resolvePlayer) | degeneretteBets[] (delete), claimableWinnings[], claimablePool, prizePoolsPacked (futurePrizePool portion via _setFuturePrizePool), plus LootboxModule storage via delegatecall | coin.mintForGame, wwxrp.mintPrize, sdgnrs.poolBalance, sdgnrs.transferFromPool, delegatecall to LootboxModule.resolveLootboxDirect | Tier 1 | | | | |

### Risk Tier Justification
- **B1 (Tier 1):** Multi-currency ETH/BURNIE/WWXRP bet placement. ETH path has complex claimable pull with potential off-by-one (L552, `<=` instead of `<`). Adds to futurePrizePool or pendingPools based on prizePoolFrozen flag. Burns external tokens. Activity score snapshot stored in packed bet. Hero wager tracking with packed 32-bit arithmetic. Multiple storage writes across 10+ state variables.
- **B2 (Tier 1):** Resolution loop over arbitrary betIds. Per-spin: deterministic RNG derivation from lootboxRngWord, trait matching, payout calculation with EV normalization and hero multiplier. ETH payouts: futurePrizePool deduction, claimable credit, then delegatecall to LootboxModule for lootbox conversion. BURNIE/WWXRP payouts: external token mints. sDGNRS rewards on 6+ matches. Consolation prizes on total loss. State coherence across delegatecall boundary is the primary concern.

---

## Category C: Internal Helpers (State-Changing)

| # | Function | Lines | Called By | Key Storage Writes | Flags | Analyzed? | Call Tree? | Storage Map? | Cache Check? |
|---|----------|-------|-----------|-------------------|-------|-----------|------------|-------------|-------------|
| C1 | `_placeFullTicketBets(address,uint8,uint128,uint8,uint32,uint8)` | 430-460 | B1 | Orchestrates: C2 storage + C3 storage + external coin.notifyQuestDegenerette | | | | | |
| C2 | `_placeFullTicketBetsCore(address,uint8,uint128,uint8,uint32,uint8)` | 462-525 | C1 | degeneretteBets[player][nonce], degeneretteBetNonce[player], dailyHeroWagers[day][quadrant], playerDegeneretteEthWagered[player][level], topDegeneretteByLevel[level] | | | | | |
| C3 | `_collectBetFunds(address,uint8,uint256,uint256)` | 541-574 | C1 | claimableWinnings[player], claimablePool, prizePoolsPacked/pendingPoolsPacked (via _setPrizePools/_setPendingPools), lootboxRngPendingEth, lootboxRngPendingBurnie. External: coin.burnCoin, wwxrp.burnForGame | | | | | |
| C4 | `_resolveBet(address,uint64)` | 577-582 | B2 (loop) | Reads degeneretteBets[], dispatches to C5 | | | | | |
| C5 | `_resolveFullTicketBet(address,uint64,uint256)` | 585-672 | C4 | degeneretteBets[player][betId] (delete at L600). Per-spin: C6 writes (via _distributePayout). C9 writes (via _awardDegeneretteDgnrs). C10 writes (via _maybeAwardConsolation) | | | | | |
| C6 | `_distributePayout(address,uint8,uint256,uint256)` | 680-715 | C5 (per-spin, per-win) | ETH: prizePoolsPacked (futurePrizePool via _setFuturePrizePool), claimableWinnings[], claimablePool (via C8/_addClaimableEth), plus LootboxModule storage (via C7 delegatecall). BURNIE: external coin.mintForGame. WWXRP: external wwxrp.mintPrize | [MULTI-PARENT: called once per winning spin within C5 loop] | | | | |
| C7 | `_resolveLootboxDirect(address,uint256,uint256)` | 741-757 | C6 (ETH path only) | All LootboxModule storage writes (delegatecall -- executes in Game storage context) | | | | | |
| C8 | `_addClaimableEth(address,uint256)` | 1153-1160 | C6 (ETH path) | claimablePool, claimableWinnings[beneficiary] (via _creditClaimable from PayoutUtils) | | | | | |
| C9 | `_awardDegeneretteDgnrs(address,uint256,uint8)` | 1164-1178 | C5 (6+ match ETH bets only) | External: sdgnrs.transferFromPool(Pool.Reward, player, reward) | | | | | |
| C10 | `_maybeAwardConsolation(address,uint8,uint128)` | 722-737 | C5 (totalPayout == 0 only) | External: wwxrp.mintPrize(player, CONSOLATION_PRIZE_WWXRP) | | | | | |

---

## Category D: View/Pure Functions

| # | Function | Lines | Reads/Computes | Security Note | Reviewed? |
|---|----------|-------|---------------|---------------|-----------|
| D1 | `_revertDelegate(bytes)` | 141-146 | Pure: inline assembly revert propagation | Verify memory safety annotation is correct; no out-of-bounds read | |
| D2 | `_requireApproved(address)` | 150-153 | View: reads operatorApprovals[player][msg.sender] | Access control gate for operator-approved actions | |
| D3 | `_resolvePlayer(address)` | 160-166 | View: defaults to msg.sender if address(0); checks approval if different | Player resolution with approval check | |
| D4 | `_validateMinBet(uint8,uint128)` | 528-538 | Pure: compares against constant minimums per currency | ETH >= 0.005, BURNIE >= 100, WWXRP >= 1. Reverts on unsupported currency | |
| D5 | `_packFullTicketBet(uint32,uint8,uint8,uint128,uint48,uint16,uint8)` | 764-786 | Pure: bit packing into uint256 | Verify no field overlap: mode(1) + isRandom(1) + ticket(32) + count(8) + currency(2) + amount(128) + index(48) + activity(16) + hasCustom(1) + hero(3) = 240 bits, fits in 256 | |
| D6 | `_evNormalizationRatio(uint32,uint32)` | 803-846 | Pure: product of 4 per-quadrant probability ratios (num/den) | Weight computation: bucket 0-3=10, 4-6=9, 7=8. Three branches per quadrant (both, one, none match). Verify no overflow in num/den multiplication (4 iterations) | |
| D7 | `_countMatches(uint32,uint32)` | 852-876 | Pure: counts matching color (bits 5-3) and symbol (bits 2-0) per quadrant | Max 8 matches (2 per quadrant x 4 quadrants). Verify bit extraction is correct | |
| D8 | `_fullTicketPayout(uint32,uint32,uint8,uint8,uint128,uint256,uint256,bool,uint8)` | 912-961 | Pure: payout = betAmount * basePayout * effectiveRoi / 1_000_000, then EV normalization, then hero multiplier | Verify: WWXRP bonus redistribution, ETH bonus redistribution, overflow safety in multiplication chain | |
| D9 | `_applyHeroMultiplier(uint256,uint32,uint32,uint8,uint8)` | 966-985 | Pure: hero quadrant both-match -> boost from packed table, else -> 5% penalty (9500/10000) | Verify boost lookup from HERO_BOOST_PACKED is correct per match count (M=2..7) | |
| D10 | `_getBasePayoutBps(uint8)` | 990-993 | Pure: unpacks 32-bit entries from QUICK_PLAY_BASE_PAYOUTS_PACKED; special case for 8 matches | Verify packed constant values match documented payouts (0,0,190,475,1500,4250,19500,100000) and 8-match = 10_000_000 | |
| D11 | `_wwxrpBonusBucket(uint8)` | 880-885 | Pure: returns 0 for matches<5, else returns matches (5/6/7/8) | Simple bucket assignment | |
| D12 | `_wwxrpBonusRoiForBucket(uint8,uint256)` | 888-900 | Pure: (bonusRoiBps * factor) / WWXRP_BONUS_FACTOR_SCALE per bucket | Verify factor constants for buckets 5/6/7/8. Verify EV redistribution sums to 100% of bonus | |
| D13 | `_playerActivityScoreInternal(address)` | 1005-1078 | View: reads mintPacked_[], level, deityPassCount[], boonPacked[] (bundleType/frozenUntilLevel). External: questView.playerQuestStates, affiliate.affiliateBonusPointsBest | Complex multi-component score. Components: streak (0-50 pts), mintCount (0-25 pts), quest streak (0-100 pts), affiliate bonus, deity/whale pass bonus. Verify cap application | |
| D14 | `_roiBpsFromScore(uint256)` | 1098-1127 | Pure: piecewise curve. [0,7500] quadratic 9000-9500, [7500,25500] linear 9500-9950, [25500,30500] linear 9950-9990 | Verify continuity at breakpoints (score=7500 -> 9500, score=25500 -> 9950). Verify no overflow in quadratic term | |
| D15 | `_mintCountBonusPoints(uint24,uint24)` | 1084-1091 | Pure: if currLevel==0 return 0; if mintCount>=currLevel return 25; else proportional | Division by zero guarded. Maximum 25 points | |

---

## Inherited Helper Functions (Traced in Call Trees)

These are defined in DegenerusGamePayoutUtils, DegenerusGameMintStreakUtils, and DegenerusGameStorage. They are NOT standalone audit targets for this phase -- they are traced within their callers' call trees to verify state coherence per D-08/D-09.

| Function | Source | Lines | Called By | State Impact | Cache Concern |
|----------|--------|-------|-----------|-------------|---------------|
| `_creditClaimable(address,uint256)` | PayoutUtils | L30-35 | C8 | claimableWinnings[beneficiary] += weiAmount | Unchecked addition (overflow? No: bounded by contract ETH balance) |
| `_setPrizePools(uint128,uint128)` | Storage | L651-653 | C3 (non-frozen ETH bets) | prizePoolsPacked | Packed 128+128 write |
| `_getPrizePools()` | Storage | L655-659 | C3 (non-frozen ETH bets) | None (view) | |
| `_setPendingPools(uint128,uint128)` | Storage | L661-663 | C3 (frozen ETH bets) | pendingPoolsPacked | Packed 128+128 write |
| `_getPendingPools()` | Storage | L665-669 | C3 (frozen ETH bets) | None (view) | |
| `_getFuturePrizePool()` | Storage | L746-749 | C6 (ETH payouts) | None (view) | Returns future portion of prizePoolsPacked |
| `_setFuturePrizePool(uint256)` | Storage | L752-756 | C6 (ETH payouts) | prizePoolsPacked (future portion) | Preserves next portion via mask |
| `_simulatedDayIndex()` | Storage | L1134-1137 | C2 (hero wager tracking) | None (view) | Returns current simulated day |
| `_mintStreakEffective(address,uint24)` | MintStreakUtils | L49-61 | D13 (activity score) | None (view) | Reads mintPacked_[player] |

---

## Checklist Verification Notes

1. **All 27 functions** in DegenerusGameDegeneretteModule.sol are listed (2B + 10C + 15D)
2. **No function omitted** -- grep of all `function` declarations in the contract matches the inventory
3. **MULTI-PARENT flag** on C6 (_distributePayout): called once per winning spin within the C5 resolution loop. Each call operates on fresh state (pool deduction + claimable credit + delegatecall are sequential within one spin iteration). No cross-spin cache concern because pool is re-read each invocation via _getFuturePrizePool().
4. **Delegatecall tracking** on C7 (_resolveLootboxDirect): executes LootboxModule.resolveLootboxDirect in Game's storage context. Must verify no storage variables cached before this delegatecall are stale after return.
5. **Inherited helpers** from PayoutUtils (1), MintStreakUtils (1), Storage (7) are listed with their call sources and state impact.
