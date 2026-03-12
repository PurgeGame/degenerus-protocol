# Phase 10: Reward Systems and Modifiers - Research

**Researched:** 2026-03-12
**Domain:** DGNRS tokenomics, deity pass system, affiliate rewards, stETH yield, quest rewards
**Confidence:** HIGH

## Summary

Phase 10 covers five interconnected secondary reward systems that modify the core economic model documented in Phases 6-9. All constants and mechanics are verified directly from contract source code.

The DGNRS token (DegenerusStonk.sol) has a fixed 1 trillion supply split across 6 pools (creator 20%, plus 5 reward pools). Transfers are soulbound -- only the creator address and the contract itself can transfer tokens; all other holders can only burn for proportional ETH + stETH + BURNIE reserves. The deity pass system uses quadratic pricing (24 + T(n) ETH where T(n) is the n-th triangular number) with up to 32 passes total, and provides boons to other players through a weighted random draw from 31 boon types. The affiliate system is a 3-tier referral chain with BURNIE rewards at 25%/20%/5% rates depending on level and ETH freshness. stETH yield integration is passive -- admin stakes excess ETH via Lido, and the yield surplus accrues to the game contract without explicit pool allocation. The quest system runs two daily quests with fixed rewards (100/200 BURNIE) and a streak mechanic.

**Primary recommendation:** Structure the phase into 5 plans, one per subsystem, each producing a standalone audit document with exact constants, formulas, and worked examples suitable for game theory agent consumption.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| DGNR-01 | Document initial supply distribution | DegenerusStonk.sol constructor: INITIAL_SUPPLY=1T, CREATOR_BPS=2000, WHALE_POOL_BPS=1143, AFFILIATE_POOL_BPS=3428, LOOTBOX_POOL_BPS=1143, REWARD_POOL_BPS=1143, EARLYBIRD_POOL_BPS=1143, dust to lootbox |
| DGNR-02 | Document earlybird reward schedule | _awardEarlybirdDgnrs: quadratic curve, EARLYBIRD_END_LEVEL=3, EARLYBIRD_TARGET_ETH=1000 ETH, pool remainder dumps to Reward pool at level 3+ |
| DGNR-03 | Document affiliate DGNRS distribution | WhaleModule: whale minter 1% whale pool (PPM 10000), deity buyer 5% whale pool (500 BPS), affiliate direct/upline PPM constants per purchase type |
| DGNR-04 | Document soulbound mechanics | _transfer: only address(this) or CREATOR can transfer; all others can only burn; transferFromPool is game-only |
| DEIT-01 | Document deity pass pricing curve | DEITY_PASS_BASE=24 ETH, quadratic T(n)=n*(n+1)/2, discount boons tier 1/2/3 = 10/25/50% |
| DEIT-02 | Document all boon types with weights | 31 boon types across 10 categories; total weight 1298 (with decimator) or 1248 (without); -40 if deity pass unavailable |
| DEIT-03 | Document deity pass multipliers (activity score + jackpot entries) | DEITY_PASS_ACTIVITY_BONUS_BPS=8000 (+80%); replaces streak/count with floor 50/25; virtual deity-equivalent count for DGNRS/VAULT; jackpot virtual entries: floor(2% of bucket tickets), minimum 2, per JackpotModule lines 2274+2327 |
| AFFL-01 | Document affiliate reward structure | 3-tier: direct 25/20/5%, upline1 20% of scaled, upline2 4% of scaled; kickback 0-25%; payout modes coinflip/degenerette/split |
| AFFL-02 | Document affiliate tier and bonus system | Per-referrer cap 0.5 ETH/level; lootbox taper 15000-25500 score; bonus points 1%/ETH summed over prev 5 levels, cap 50 |
| AFFL-03 | Document top affiliate endgame rewards | claimAffiliateDgnrs: 5% of affiliate pool per level; proportional to score/levelPrizePool; deity bonus 20% of score as BURNIE flip credit, cap 5 ETH |
| STETH-01 | Document stETH integration | adminStakeEthForStEth: stakes excess ETH via Lido submit(); adminSwapEthForStEth: value-neutral rebalancing; claimablePool is protected reserve |
| STETH-02 | Document stETH yield effects | yieldPoolView = (ETH+stETH) - (current+next+claimable+future); yield is implicit surplus; DGNRS burn includes stETH in proportional payout |
| QRWD-01 | Document quest reward types and amounts | 9 quest types (0-8); slot 0 fixed MINT_ETH (100 BURNIE), slot 1 random (200 BURNIE); fixed targets per type |
| QRWD-02 | Document quest cooldowns and limits | 1 completion per slot per day; streak credited on first completion; shields protect streaks; version gating resets stale progress |
</phase_requirements>

## Architecture Patterns

### Contract Topology for Phase 10 Systems

```
DegenerusStonk.sol          -- DGNRS token, 5 reward pools, burn-for-backing
DegenerusGame.sol           -- Deity pass purchase, affiliate DGNRS claims, activity score, stETH admin
DegenerusGameWhaleModule.sol -- Deity pass pricing, DGNRS reward distribution (whale/affiliate pools)
DegenerusGameLootboxModule.sol -- Boon types, weights, _boonFromRoll, _applyBoon, deity boon issuance
DegenerusGameBoonModule.sol -- Boon consumption and expiry logic
DegenerusAffiliate.sol      -- 3-tier referral, payout routing, leaderboard, kickback
DegenerusQuests.sol         -- Daily quest rolling, progress tracking, streak system
BurnieCoin.sol              -- Quest reward routing (affiliateQuestReward, notifyQuestMint)
```

### Key Pattern: Delegatecall Module Architecture
All game modules operate via delegatecall from DegenerusGame, sharing DegenerusGameStorage slots. Boon state (coinflipBoonBps, lootboxBoon*Active, purchaseBoostBps, etc.) lives in game storage but is written/read by WhaleModule, LootboxModule, and BoonModule.

### Key Pattern: PPM vs BPS
DGNRS pool distribution uses parts-per-million (PPM with scale 1,000,000) for whale/affiliate rewards, while most other systems use basis points (BPS with scale 10,000). This dual-unit system is a critical documentation detail.

## DGNRS Tokenomics Detail

### Initial Supply Distribution

| Pool | BPS | Token Amount | Percentage |
|------|-----|-------------|------------|
| Creator | 2000 | 200,000,000,000 DGNRS | 20% |
| Whale | 1143 | 114,300,000,000 DGNRS | 11.43% |
| Affiliate | 3428 | 342,800,000,000 DGNRS | 34.28% |
| Lootbox | 1143 | 114,300,000,000 DGNRS + dust | 11.43%+ |
| Reward | 1143 | 114,300,000,000 DGNRS | 11.43% |
| Earlybird | 1143 | 114,300,000,000 DGNRS | 11.43% |
| **Total** | **10000** | **1,000,000,000,000 DGNRS** | **100%** |

**Dust handling:** totalAllocated is checked against INITIAL_SUPPLY; any shortfall from integer division is added to Lootbox pool.

**Pool enum order:** Whale=0, Affiliate=1, Lootbox=2, Reward=3, Earlybird=4

### Soulbound Transfer Restriction

The `_transfer` function enforces: `from != address(this) && from != ContractAddresses.CREATOR` reverts with `Unauthorized()`. This means:
- Only the contract itself (pool transfers) and the CREATOR address can send DGNRS
- All other holders can only burn via `burn()` or `burnForGame()`
- No secondary market trading is possible (ERC20 `transfer` from user wallets reverts)
- No `approve`/`transferFrom` functions exist at all

### Earlybird Reward Curve

- **Active during:** levels < EARLYBIRD_END_LEVEL (3)
- **ETH target:** EARLYBIRD_TARGET_ETH = 1,000 ETH
- **Curve:** Quadratic decreasing emission
  - `d1 = ethIn * 2 * totalEth - ethIn^2`
  - `d2 = nextEthIn * 2 * totalEth - nextEthIn^2`
  - `payout = poolStart * (d2 - d1) / (totalEth^2)`
- **Pool start snapshot:** First payout records initial earlybird pool balance
- **At level 3+:** One-shot transfer of remaining earlybird pool to Reward pool
- **Triggered by:** Any ETH purchase (tickets, lootbox, whale bundle, lazy pass, deity pass)

### DGNRS Whale/Affiliate Pool Rewards Per Purchase

| Purchase Type | Buyer Reward (Whale Pool) | Affiliate Direct | Affiliate Upline | Affiliate Upline2 |
|--------------|--------------------------|-----------------|-----------------|-------------------|
| Whale Bundle | 1% (10,000 PPM) | 0.1% (1,000 PPM) | 0.02% (200 PPM) | 0.01% (100 PPM = upline/2) |
| Deity Pass | 5% (500 BPS) | 0.5% (5,000 PPM) | 0.1% (1,000 PPM) | 0.05% (500 PPM = upline/2) |

All percentages are of the respective pool's current balance. Percentages are of remaining pool balance at time of claim, meaning they decrease as pools deplete.

### DGNRS Affiliate DGNRS Claim (claimAffiliateDgnrs)

Per-level claim for affiliates with sufficient score:
- **Eligibility:** `affiliateScore(prevLevel, player) >= AFFILIATE_DGNRS_MIN_SCORE` (10 ETH) OR has deity pass
- **One claim per player per level** (tracked by affiliateDgnrsClaimedBy mapping)
- **Formula:** `reward = (poolBalance * 500 / 10000) * score / denominator`
  - poolBalance = current affiliate pool balance
  - AFFILIATE_DGNRS_LEVEL_BPS = 500 (5% of pool per level)
  - denominator = levelPrizePool[prevLevel] (or BOOTSTRAP_PRIZE_POOL = 50 ETH if zero)
- **Deity pass bonus:** `score * 2000 / 10000` BURNIE flip credit, capped at `5 ETH * 1000 / price` BURNIE

## Deity Pass System Detail

### Pricing Curve

- **Base price:** DEITY_PASS_BASE = 24 ETH
- **Escalation:** `basePrice = 24 + k*(k+1)/2` where k = deityPassOwners.length (passes sold so far)
- **Maximum 32 passes** (one per symbol, symbolId 0-31)

| Pass # (k) | Price (ETH) | Cumulative (ETH) |
|-------------|-------------|-------------------|
| 0 (first) | 24.0 | 24.0 |
| 1 | 25.0 | 49.0 |
| 2 | 27.0 | 76.0 |
| 5 | 39.0 | 213.0 |
| 10 | 79.0 | 739.0 |
| 15 | 144.0 | 2,404.0 |
| 20 | 234.0 | 5,274.0 |
| 25 | 349.0 | 9,849.0 |
| 31 (last) | 520.0 | 18,264.0 |

### Deity Pass Discount Boons

| Tier | Discount | BPS |
|------|----------|-----|
| 1 | 10% | 1000 |
| 2 | 25% | 2500 |
| 3 | 50% | 5000 |

Expiry: 4 days for lootbox-rolled boons, 1 day (current day only) for deity-granted boons.

### Deity Pass Transfer Cost

- Burns 5 ETH worth of BURNIE from sender: `burnAmount = (5 ETH * 1000 ether) / price`
- Nukes sender's mint stats (levelCount, levelStreak, lastLevel, mintStreakLastCompleted all zeroed)
- Resets sender's quest streak via `resetQuestStreak`
- Not available at level 0

### Deity Pass Activity Score Impact

- **DEITY_PASS_ACTIVITY_BONUS_BPS = 8000** (+80% activity score)
- Replaces streak/count with floor values: streak=50 (max 50%), count=25 (max 25%)
- Quest streak, affiliate bonus still calculated normally on top
- Maximum with deity: 50% + 25% + 100% + 50% + 80% = 305% (vs 265% without)
- DGNRS and VAULT get deityPassCount=1 in constructor (virtual deity-equivalent boost)

### Boon Types and Draw Weights (31 types, 10 categories)

| Category | Boon Type | ID | Effect | Weight | Probability |
|----------|-----------|----|---------| -------|-------------|
| Coinflip | +5% | 1 | 500 BPS coinflip bonus | 200 | 15.41% |
| Coinflip | +10% | 2 | 1000 BPS coinflip bonus | 40 | 3.08% |
| Coinflip | +25% | 3 | 2500 BPS coinflip bonus | 8 | 0.62% |
| Lootbox | +5% | 5 | 500 BPS lootbox boost (cap 10 ETH) | 200 | 15.41% |
| Lootbox | +15% | 6 | 1500 BPS lootbox boost (cap 10 ETH) | 30 | 2.31% |
| Lootbox | +25% | 22 | 2500 BPS lootbox boost (cap 10 ETH) | 8 | 0.62% |
| Purchase | +5% | 7 | 500 BPS purchase boost | 400 | 30.82% |
| Purchase | +15% | 8 | 1500 BPS purchase boost | 80 | 6.16% |
| Purchase | +25% | 9 | 2500 BPS purchase boost | 16 | 1.23% |
| Decimator | +10% | 13 | 1000 BPS decimator boost | 40 | 3.08%* |
| Decimator | +25% | 14 | 2500 BPS decimator boost | 8 | 0.62%* |
| Decimator | +50% | 15 | 5000 BPS decimator boost | 2 | 0.15%* |
| Whale | -10% | 16 | 1000 BPS whale bundle discount | 28 | 2.16% |
| Whale | -25% | 23 | 2500 BPS whale bundle discount | 10 | 0.77% |
| Whale | -50% | 24 | 5000 BPS whale bundle discount | 2 | 0.15% |
| Deity Pass | -10% | 25 | 1000 BPS deity pass discount (tier 1) | 28 | 2.16%** |
| Deity Pass | -25% | 26 | 2500 BPS deity pass discount (tier 2) | 10 | 0.77%** |
| Deity Pass | -50% | 27 | 5000 BPS deity pass discount (tier 3) | 2 | 0.15%** |
| Activity | +10 | 17 | +10 to levelCount | 100 | 7.70% |
| Activity | +25 | 18 | +25 to levelCount | 30 | 2.31% |
| Activity | +50 | 19 | +50 to levelCount | 8 | 0.62% |
| Whale Pass | Free | 28 | Free whale pass claim | 8 | 0.62% |
| Lazy Pass | -10% | 29 | 1000 BPS lazy pass discount | 30 | 2.31% |
| Lazy Pass | -25% | 30 | 2500 BPS lazy pass discount | 8 | 0.62% |
| Lazy Pass | -50% | 31 | 5000 BPS lazy pass discount | 2 | 0.15% |

*Decimator boons only available when decWindowOpen is true (total weight drops from 1298 to 1248)
**Deity pass boons only available when deityPassOwners.length < 24 (total weight drops by 40 = DEITY_BOON_WEIGHT_DEITY_PASS_ALL)

**Boon expiry rules:**
- Coinflip: 2 days (COINFLIP_BOON_EXPIRY_DAYS)
- Lootbox boost: 2 days (LOOTBOX_BOOST_EXPIRY_DAYS)
- Purchase boost: 4 days (PURCHASE_BOOST_EXPIRY_DAYS)
- Deity pass boon: 4 days for lootbox-sourced, current-day-only for deity-sourced
- Activity boon: 2 days (uses COINFLIP_BOON_EXPIRY_DAYS)
- Whale/lazy pass boon: 4 days

**Deity-sourced vs lootbox-sourced:**
- Deity-sourced boons overwrite existing boons (always replace)
- Lootbox-sourced boons upgrade only if higher tier (upgrade semantics)
- Deity-sourced boons expire at end of current day (deityDay != currentDay triggers clear)
- Lootbox-sourced boons expire after N days from stamp day

### Deity Boon Issuance Rules

- **3 slots per deity per day** (DEITY_DAILY_BOON_COUNT = 3)
- Each slot produces a deterministic boon type from: `keccak256(dailySeed, deity, day, slot) % totalWeight`
- **Cannot issue to self** (deity == recipient reverts)
- **One boon per recipient per day** (deityBoonRecipientDay tracks last receipt)
- Requires valid RNG word for the day

## Affiliate System Detail

### Reward Rates

| ETH Type | Levels | Rate (BPS) | Effective % |
|----------|--------|-----------|-------------|
| Fresh ETH | 0-3 | 2500 | 25% |
| Fresh ETH | 4+ | 2000 | 20% |
| Recycled ETH | All | 500 | 5% |

### Per-Referrer Commission Cap

MAX_COMMISSION_PER_REFERRER_PER_LEVEL = 0.5 ETH BURNIE per level per sender-affiliate pair.

### Lootbox Activity Taper (fresh ETH only)

| Activity Score | Payout Factor |
|---------------|---------------|
| < 15,000 | 100% |
| 15,000 | 100% |
| 20,250 | 75% |
| 25,500+ | 50% (floor) |

Linear interpolation between 15,000 and 25,500. Leaderboard tracking always uses full untapered amount.

### 3-Tier Distribution

1. **Direct affiliate:** (scaledAmount - kickback) + quest bonus as FLIP credit
2. **Upline tier 1:** 20% of scaledAmount + quest bonus
3. **Upline tier 2:** 4% of scaledAmount (20% of tier 1) + quest bonus

When multiple recipients exist, a weighted random winner receives the combined total (EV-preserving lottery).

### Payout Modes

| Mode | ID | Behavior |
|------|----|----------|
| Coinflip | 0 | creditFlip (default) |
| Degenerette | 1 | pendingDegeneretteCredit accumulator |
| SplitCoinflipCoin | 2 | 50% creditCoin, 50% discarded |

### Kickback

- Configurable 0-25% (MAX_KICKBACK_PCT = 25)
- Returned to the referred player by the calling contract
- Does not reduce leaderboard tracking score

### DGNRS Affiliate Pool Claims Per Level

From DegenerusGame.claimAffiliateDgnrs:
- Available only when level > 1 (claim for prevLevel)
- Base eligibility: affiliateScore >= 10 ETH OR has deity pass
- Share formula: `(poolBalance * 500 / 10000) * score / levelPrizePool[prevLevel]`
- Deity pass bonus: `min(score * 20%, 5 ETH worth of BURNIE)` credited as FLIP

## stETH Integration Detail

### Yield Mechanics

stETH is Lido's rebasing staked ETH token. The game contract holds both ETH and stETH. stETH balance increases over time through Lido staking rewards (rebasing), creating a yield surplus.

**Yield surplus formula:**
```
yieldSurplus = (address(this).balance + steth.balanceOf(this)) - (currentPrizePool + nextPrizePool + claimablePool + futurePrizePool)
```

### Admin Operations

| Function | Access | Effect | Constraint |
|----------|--------|--------|------------|
| adminStakeEthForStEth | ADMIN only | Stakes ETH via Lido submit() | Cannot stake below claimablePool reserve |
| adminSwapEthForStEth | ADMIN only | Sends ETH, receives stETH back | Value-neutral swap (msg.value == amount) |

### stETH in Payouts

- **Player claims (claimWinnings):** ETH-first, stETH fallback for remainder
- **Vault/DGNRS claims (claimWinningsStethFirst):** stETH-first, ETH fallback
- **DGNRS deposits:** Game calls `dgnrs.depositSteth(amount)` via `_transferSteth` which uses `steth.approve` + `depositSteth`
- **DGNRS burn:** Returns proportional ETH + stETH + BURNIE; ETH preferred over stETH

### Key Pitfall: stETH Rounding

Lido stETH has known 1-2 wei rounding issues on transfers due to shares-to-balance conversion. The game handles this implicitly through its fallback/retry payout logic.

## Quest System Detail

### Quest Types

| Type | ID | Slot Eligibility | Target | Weight (slot 1) |
|------|-----|-----------------|--------|-----------------|
| MINT_BURNIE | 0 | Slot 1 only | 1 ticket | 10 |
| MINT_ETH | 1 | Slot 0 (fixed) | 1x mintPrice (cap 0.5 ETH) | N/A (always slot 0) |
| FLIP | 2 | Slot 1 only | 2000 BURNIE | 4 |
| AFFILIATE | 3 | Slot 1 only | 2000 BURNIE | 1 |
| RESERVED | 4 | Never | N/A | 0 |
| DECIMATOR | 5 | Slot 1 only | 2000 BURNIE | 4 (when allowed) |
| LOOTBOX | 6 | Slot 1 only | 2x mintPrice (cap 0.5 ETH) | 3 |
| DEGENERETTE_ETH | 7 | Slot 1 only | 2x mintPrice (cap 0.5 ETH) | 1 |
| DEGENERETTE_BURNIE | 8 | Slot 1 only | 2000 BURNIE | 1 |

### Quest Rewards

| Slot | Reward |
|------|--------|
| Slot 0 (MINT_ETH) | 100 BURNIE (QUEST_SLOT0_REWARD) |
| Slot 1 (random) | 200 BURNIE (QUEST_RANDOM_REWARD) |

Rewards are credited as FLIP stakes via the BurnieCoin quest routing.

### Quest Target Constants

| Target Type | Value | Applies To |
|-------------|-------|-----------|
| QUEST_MINT_TARGET | 1 ticket | MINT_BURNIE |
| QUEST_BURNIE_TARGET | 2000 BURNIE | FLIP, DECIMATOR, AFFILIATE, DEGENERETTE_BURNIE |
| QUEST_LOOTBOX_TARGET_MULTIPLIER | 2x mintPrice | LOOTBOX, DEGENERETTE_ETH |
| QUEST_DEPOSIT_ETH_TARGET_MULTIPLIER | 1x mintPrice | MINT_ETH (slot 0) |
| QUEST_ETH_TARGET_CAP | 0.5 ETH | All ETH-based targets |

### Streak System

- **Increment:** First quest completion of any slot per day increments streak by 1
- **Reset:** Missing a day resets streak to 0 (unless streak shields cover all missed days)
- **Shields:** questStreakShieldCount per player, consumed on missed days (1 shield per missed day)
- **Version gating:** Progress resets when quest day or version changes (prevents stale carry-over)
- **Slot 1 gate:** Slot 1 cannot be completed unless slot 0 is already complete for the day
- **Combo completion:** Completing one slot auto-checks if the paired slot also meets its target

### Decimator Quest Availability

Available only when:
1. `decWindowOpenFlag` is true
2. Level is a multiple of 100 (100, 200, 300...) OR
3. Level ends in 5 (5, 15, 25...) except levels ending in 95

### Quest Streak in Activity Score

Quest streak contributes +1% per streak day, capped at 100% (10,000 BPS). This is the largest single component of the activity score.

## Common Pitfalls

### Pitfall 1: PPM vs BPS Unit Confusion
**What goes wrong:** DGNRS pool reward calculations use PPM (1,000,000 scale) while most other systems use BPS (10,000 scale). Mixing them produces 100x errors.
**How to avoid:** Always specify the unit system when documenting percentages. PPM: whale minter 10,000 PPM = 1%, affiliate direct whale 1,000 PPM = 0.1%. BPS: deity whale pool 500 BPS = 5%.

### Pitfall 2: Pool Balance Decay in Sequential Claims
**What goes wrong:** DGNRS pool percentages are of current remaining balance, not initial balance. Each claim reduces the pool, so later claimants get less from the same percentage.
**How to avoid:** Document that DGNRS rewards decrease over time. First whale bundle buyer gets 1% of full whale pool; 100th buyer gets 1% of a significantly reduced pool.

### Pitfall 3: Deity-Sourced vs Lootbox-Sourced Boon Expiry
**What goes wrong:** Deity boons expire at end of current day (strict same-day use), while lootbox boons expire after N days. Conflating these produces wrong lifetime calculations.
**How to avoid:** Track deityCoinflipBoonDay/deityLootboxBoon*Day separately. If deityDay != 0 and deityDay != currentDay, boon is expired regardless of stamp day.

### Pitfall 4: Affiliate Weighted Random Lottery
**What goes wrong:** When multiple recipients exist (affiliate + upline + upline2), rewards are NOT split proportionally. Instead, a single winner receives ALL rewards via weighted random selection. EV is preserved but variance is high.
**How to avoid:** Document clearly that the affiliate payout is EV-preserving lottery, not deterministic split.

### Pitfall 5: Slot 1 Quest Gate
**What goes wrong:** Slot 1 (bonus quest) cannot be completed unless slot 0 (MINT_ETH) is already complete for that day. This is not obvious from the quest type descriptions alone.
**How to avoid:** Document the slot 0 prerequisite: `if (slot == 1 && (completionMask & 1) == 0) return false`.

### Pitfall 6: stETH Yield is Passive Surplus
**What goes wrong:** Treating stETH yield as an explicit pool or distribution. There is no "yield pool" that gets distributed. Yield simply increases total balance, and any surplus above obligations can be rebalanced by admin.
**How to avoid:** Document yield as implicit surplus = totalBalance - totalObligations. No automatic distribution mechanism exists.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| DGNRS pool math | Custom percentage calc | Extract exact BPS/PPM constants | Integer division with dual scale systems; PPM for whale/affiliate rewards, BPS for deity rewards |
| Earlybird curve | Approximate emission | Exact quadratic formula from contract | d2-d1 formula with totalEth^2 denominator is not standard linear |
| Boon probability | Simple division | Full weight table with conditionals | Decimator and deity pass availability change total weight dynamically |
| Deity pass pricing | Simple arithmetic | Triangular number formula T(n) | k*(k+1)/2 with k = current owners count, not pass number |

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Manual verification against contract constants |
| Config file | N/A (analysis-only milestone) |
| Quick run command | `grep -c "constant" contracts/DegenerusStonk.sol` |
| Full suite command | N/A |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| DGNR-01 | DGNRS supply distribution | manual-only | Verify BPS sum = 10000, amounts match | N/A |
| DGNR-02 | Earlybird curve | manual-only | Verify quadratic formula matches contract | N/A |
| DGNR-03 | Affiliate DGNRS per level | manual-only | Verify PPM/BPS constants match code | N/A |
| DGNR-04 | Soulbound restrictions | manual-only | Verify _transfer ACL | N/A |
| DEIT-01 | Deity pricing curve | manual-only | Compute T(n) for all n=0..31 | N/A |
| DEIT-02 | Boon types and weights | manual-only | Sum weights, verify total 1298/1248 | N/A |
| DEIT-03 | Deity activity bonus | manual-only | Verify BPS constants | N/A |
| AFFL-01 | Affiliate reward rates | manual-only | Verify BPS constants match code | N/A |
| AFFL-02 | Affiliate tiers/bonus | manual-only | Verify taper formula | N/A |
| AFFL-03 | Top affiliate endgame | manual-only | Verify claim formula | N/A |
| STETH-01 | stETH integration | manual-only | Verify admin functions and constraints | N/A |
| STETH-02 | stETH yield effects | manual-only | Verify yieldPoolView formula | N/A |
| QRWD-01 | Quest types/rewards | manual-only | Verify type constants and rewards | N/A |
| QRWD-02 | Quest cooldowns/limits | manual-only | Verify streak/shield logic | N/A |

### Sampling Rate
- **Per task commit:** Manual constant verification
- **Per wave merge:** Cross-reference with prior phase docs
- **Phase gate:** All 14 requirements documented with exact values

### Wave 0 Gaps
None -- existing contract source serves as test infrastructure for analysis-only milestone.

## Sources

### Primary (HIGH confidence)
- `contracts/DegenerusStonk.sol` -- Full DGNRS token, pool distribution, burn mechanics
- `contracts/DegenerusGame.sol` lines 190-270 -- Affiliate/deity constants, constructor
- `contracts/DegenerusGame.sol` lines 1410-1461 -- claimAffiliateDgnrs
- `contracts/DegenerusGame.sol` lines 2360-2486 -- playerActivityScore
- `contracts/DegenerusGame.sol` lines 1775-1817 -- stETH admin functions
- `contracts/DegenerusGame.sol` lines 2129-2141 -- yieldPoolView
- `contracts/modules/DegenerusGameWhaleModule.sol` -- Deity pass pricing, DGNRS rewards
- `contracts/modules/DegenerusGameLootboxModule.sol` lines 354-460, 1235-1415 -- Boon types, weights, application
- `contracts/modules/DegenerusGameBoonModule.sol` -- Boon consumption and expiry
- `contracts/DegenerusAffiliate.sol` -- Full affiliate system
- `contracts/DegenerusQuests.sol` -- Full quest system
- `contracts/storage/DegenerusGameStorage.sol` lines 1062-1128 -- Earlybird DGNRS logic

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- all constants extracted directly from contract source
- Architecture: HIGH -- complete contract topology mapped with delegatecall paths
- Pitfalls: HIGH -- identified from actual code patterns (PPM/BPS, pool decay, boon expiry)

**Research date:** 2026-03-12
**Valid until:** 2026-04-12 (stable -- contract code is immutable on-chain)
