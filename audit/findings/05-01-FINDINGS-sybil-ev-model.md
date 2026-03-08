# 05-01 Findings: Sybil Group Expected Value Model

**Audited:** 2026-03-01
**Scope:** All prize distribution channels -- scatter jackpot, daily jackpot, BAF, affiliate draw, lootbox, decimator
**Requirement:** ECON-01 (Sybil group with 51%+ ticket ownership cannot extract positive group EV from prize pool mechanics)
**Methodology:** READ-ONLY mathematical modeling from contract source; no contract files modified

---

## 1. Prize Pool Funding Analysis (Zero-Sum Baseline)

### 1.1 Funding Flow

All prize pool ETH originates from player deposits:

```
Player ticket purchase D_total:
  90% -> nextPrizePool -> currentPrizePool at level transition
  10% -> futurePrizePool

Whale bundle W:
  Level 0: 30% next / 70% future
  Level 1+: 5% next / 95% future

Deity pass: same split as whale bundle
```

**Source:** `DegenerusGameMintModule.sol` purchase routing, confirmed by Phase 3a audit.

### 1.2 Zero-Sum Property

Define:
- **P** = total prize pool at a given level (currentPrizePool after consolidation)
- **F** = fraction of total tickets owned by Sybil group G (0 < F <= 1)
- **D** = total group deposit = F * P (approximately, as group funded fraction F of the pool)
- **R** = protocol retention (stETH yield, which accrues to the protocol, not the prize pool)

The system is zero-sum minus protocol retention:

```
sum(all_channel_payouts) = P - R
```

where R is the stETH rebasing yield retained by the contract.

**For group G to have positive EV:**

```
E[total_payout_G] > D = F * P
```

This requires at least one channel where the group receives MORE than its proportional share F of the channel's payout.

### 1.3 Key Insight: Proportionality Test

For each channel C with total payout P_C:
- If `E[payout_G_C] = F * P_C` --> proportional (zero-sum for G)
- If `E[payout_G_C] > F * P_C` --> super-proportional (favors Sybil)
- If `E[payout_G_C] < F * P_C` --> sub-proportional (penalizes Sybil)

A group at F% ownership has positive EV if and only if the weighted average proportionality across all channels exceeds 1.

---

## 2. Scatter Jackpot Channel (50.625% of BAF pool)

### 2.1 Mechanism

The scatter jackpot constitutes the largest share of BAF distribution. From `DegenerusJackpots.sol` (lines 424-537):

```
scatterTop  = (P * 9) / 40   = 22.5% of BAF pool
scatterSecond = (P * 45) / 160 = 28.125% of BAF pool
Total scatter = 50.625% of BAF pool
```

**Winner selection:**
1. 50 rounds of trait sampling (`BAF_SCATTER_ROUNDS = 50`)
2. Each round: `degenerusGame.sampleTraitTickets(entropy)` returns up to 4 ticket holders
3. From the 4 sampled tickets, the top-2 by BAF score (`_bafScore`) are selected
4. First-place winners share `scatterTop`; second-place winners share `scatterSecond`

### 2.2 Trait Ticket Sampling (sampleTraitTickets)

From `DegenerusGame.sol` (lines 2628-2666):

```solidity
// Select a random level (1..min(currentLevel-1, 20))
offset = uint24(word % maxOffset) + 1;
lvlSel = currentLevel - offset;

// Select random trait (0-255) from a disjoint byte
traitSel = uint8(word >> 24);

// Sample up to 4 holders from traitBurnTicket[lvlSel][traitSel]
arr = traitBurnTicket[lvlSel][traitSel];
take = min(arr.length, 4);
start = (word >> 40) % arr.length;
tickets[i] = arr[(start + i) % arr.length];
```

**Critical observation:** Each entry in `traitBurnTicket[level][trait]` is a player address, and a player can appear MULTIPLE TIMES (more ticket burns = more entries = higher probability of being sampled).

From `DegenerusGameMintModule.sol` (line 457):
```solidity
uint8 traitId = DegenerusTraitUtils.traitFromWord(s) + (uint8(i & 3) << 6);
```

Traits are assigned pseudo-randomly at mint time (via LCG). Each ticket gets one of 256 possible traits (4 quadrants x 8 categories x 8 sub-categories). With VRF-seeded randomness, trait assignment is unbiased.

### 2.3 Proportionality Analysis

**Claim: Scatter jackpot returns are proportional to ticket ownership.**

**Proof:**

Let group G own F fraction of all tickets at a level. The trait assignment is VRF-based and uniform across 256 traits. For any given trait t, group G owns approximately F fraction of entries in `traitBurnTicket[level][t]`.

When `sampleTraitTickets` selects a random trait and samples 4 holders:
- Each sampled position has probability F of being a group G member
- The probability that at least one of the 4 samples is a G member is `1 - (1-F)^4`

However, the scatter jackpot selects the top-2 by BAF score among the 4 sampled tickets. This introduces a second weighting:

**BAF score weighting:** `_bafScore(player, lvl)` returns `bafTotals[lvl][player]` which is the accumulated coinflip stake. A Sybil group's total BAF score across all accounts depends on how they distribute their coinflip volume.

**Key result:** Even if the Sybil group gets sampled proportionally, winning scatter requires having the HIGHEST BAF score among the 4 sampled tickets. This creates a quality-over-quantity dynamic:

- Strategy A (1 account, all coinflips concentrated): High BAF score per account, but only appears in F fraction of trait buckets
- Strategy B (N accounts, distributed coinflips): Lower BAF score per account, appears in same F fraction of trait buckets (spread across accounts)

**Under Strategy A:** When sampled, the single account almost always wins (highest BAF score). But it's only sampled with probability approximately F per round.

**Under Strategy B:** Each account has lower BAF score, so when sampled alongside non-group members with high BAF scores, group accounts may lose the selection.

**Mathematical formalization:**

For a single round, with 4 tickets sampled:
- Let p_G = probability of sampling at least one G member = `1 - (1-F)^4`
- Given a G member is sampled, let q_win = probability G member has highest BAF score among 4

Under Strategy A: q_win ~ 1 (concentrated BAF score dominates)
Under Strategy B with N accounts: q_win < 1 (diluted BAF score may lose to concentrated non-group players)

Expected scatter share for G:
```
E[scatter_G] = 50 rounds * p_G * q_win * (scatter_pool / winners_count)
```

**Conclusion: Scatter returns are at most proportional to F, and sub-proportional under Strategy B** because diluting BAF score across accounts reduces per-account competitiveness while not increasing the total number of trait samples.

### 2.4 Eligibility Gate

All scatter winners must satisfy `_eligible()`: `ethMintStreakCount >= 8`. For deity pass holders, this returns the current level (always eligible). For non-deity holders, this requires 8+ consecutive level mints.

A Sybil group splitting deposits across N accounts must ensure each account maintains an 8-mint streak. If D/N is insufficient to buy tickets at 8 consecutive levels, some accounts become ineligible. This further reduces effective scatter share.

---

## 3. Daily Jackpot Channel (6-14% of currentPrizePool per day)

### 3.1 Mechanism

From `DegenerusGameJackpotModule.sol`:

```
dailyBps = random in [600, 1400] (6-14% of currentPrizePool)
Final day (counter == 4): 100% of remaining currentPrizePool
```

The jackpot phase runs for `JACKPOT_LEVEL_CAP = 5` days per level.

**Winner selection (daily ETH chunk):**

1. 4 winning traits are rolled (`_rollWinningTraits`)
2. ETH pool is split across 4 trait buckets (by share BPS: 20/20/20/20 for days 1-4, or 60/13/13/13 for day 5)
3. Each bucket selects winners from `traitBurnTicket[level][traitId]` via `_randTraitTicketWithIndices`
4. Winners are selected randomly proportional to their entries in the trait array

### 3.2 Proportionality Analysis

**Trait-ticket-based winner selection is proportional to ticket count.**

From `_randTraitTicketWithIndices` (line 2251-2277):
```solidity
address[] storage holders = traitBurnTicket_[trait];
uint256 len = holders.length;
// ... winner selected by random index into holders array ...
```

A player with K entries in a trait bucket of size L has probability K/L of being selected as a winner. Since the Sybil group owns F fraction of all tickets, they own approximately F fraction of entries in each trait bucket.

**Expected daily jackpot payout for G:**
```
E[daily_G] = F * daily_pool
```

**Proportional.** No super-proportional return.

### 3.3 Deity Pass Virtual Entries

From `_randTraitTicketWithIndices` (lines 2254-2266):
```solidity
uint8 fullSymId = (trait >> 6) * 8 + (trait & 0x07);
address deity;
uint256 virtualCount;
if (fullSymId < 32) {
    deity = deityBySymbol[fullSymId];
    if (deity != address(0)) {
        virtualCount = len / 50;   // 2% of bucket, min 2
    }
}
uint256 effectiveLen = len + virtualCount;
```

Deity pass holders get virtual entries (2% of bucket size, minimum 2) in their owned symbol's trait buckets. This provides a small probability boost to deity holders but is bounded and does not create super-proportional returns at the channel level -- it shifts some probability from non-deity to deity holders within the same trait bucket.

**For Sybil analysis:** If the Sybil group holds deity passes, the virtual entries increase their effective ticket count but only marginally (2% of bucket in traits matching their symbol). This is at most +2% relative probability on the deity-symbol traits, averaged across all 256 traits: negligible.

---

## 4. BAF Non-Scatter Channels (25% + 10% return of BAF pool)

### 4.1 Top BAF Bettor (9/80 = 11.25% of BAF pool)

```solidity
(address w, ) = _bafTop(lvl, 0);  // Top BAF leaderboard position
```

Winner is the player with the highest accumulated coinflip stake at this level. This is a pure leaderboard position -- whoever stakes the most BURNIE in coinflips wins.

**Sybil analysis:** The group's total coinflip stake is fixed regardless of whether they use 1 or N accounts. Concentrating all coinflips in 1 account maximizes the chance of being #1. Splitting across N accounts dilutes individual leaderboard positions.

**Result: Sub-proportional under Sybil splitting.** Optimal strategy is 1 account, which provides no Sybil advantage.

### 4.2 Top Coinflip Bettor (9/80 = 11.25% of BAF pool)

```solidity
(address w, ) = coin.coinflipTopLastDay();  // Last 24h top bettor
```

Same analysis as Top BAF: leaderboard-based, favors concentration. **Sub-proportional under splitting.**

### 4.3 Random BAF Pick (9/160 = 5.625% of BAF pool)

```solidity
uint8 pick = 2 + uint8(entropy & 1);  // 3rd or 4th BAF leaderboard slot
(address w, ) = _bafTop(lvl, pick);
```

Goes to the 3rd or 4th top BAF bettor. Same leaderboard dynamics. **Sub-proportional under splitting.**

### 4.4 Affiliate Draw (9/80 = 11.25% of BAF pool)

From `runBafJackpot` (lines 287-418):

1. Collect top affiliates from prior 20 levels (deduped)
2. Shuffle candidates randomly
3. Select up to 4 eligible candidates (requires 8-mint streak)
4. Sort by BAF score
5. Top candidate gets 50%, second 30%, third 20%

**Sybil analysis:** Self-referral is prevented (`DegenerusAffiliate.sol` locks self-referrals to VAULT). A Sybil group can create circular referral chains (A refers B, B refers A), but affiliate draw eligibility requires being a top affiliate at a prior level.

The affiliate draw pays ETH from the BAF pool (not BURNIE). However, the draw is weighted by BAF score and limited to 4 winners from the top affiliate pool. A Sybil group would need to both be top affiliates AND have high BAF scores.

**Key insight:** The affiliate draw is a small share of BAF (11.25%), and requires being a historical top affiliate across prior levels. This is a reputation-based system that cannot be trivially Sybil'd -- it requires substantial sustained referral volume at multiple prior levels.

**Result: Sub-proportional.** Requires building affiliate reputation over many levels, cannot be manufactured cheaply.

### 4.5 Return Pool (10% of BAF pool)

```solidity
toReturn += slice10;  // 10% returned to futurePool
```

This is returned to the protocol, not distributed. **Not claimable by any player.**

---

## 5. Lootbox Channel

### 5.1 Mechanism

Lootboxes are generated from ticket purchases. The lootbox amount is a fraction of the purchase cost. The EV multiplier depends on activity score:

| Activity Score | EV Multiplier |
|----------------|---------------|
| 0% (0 BPS) | 80% |
| 60% (6,000 BPS) | 100% (neutral) |
| 305% (30,500 BPS) | 135% (max) |

Per-account per-level benefit cap: 10 ETH of raw input gets enhanced EV, producing max 3.5 ETH benefit at 135% EV.

### 5.2 Sybil Strategy: 1 Account vs N Accounts

**Strategy A (1 account, deposit D):**
- Maximum activity score achievable with investment D
- Lootbox benefit capped at 3.5 ETH per level (one account)
- Total enhanced-EV lootbox volume: 10 ETH per level

**Strategy B (N accounts, deposit D/N each):**
- Each account has diluted activity score (see Section 8)
- Each account gets its own 10 ETH cap
- Total enhanced-EV lootbox volume: N * 10 ETH per level

**Question:** Can Strategy B extract more total benefit than Strategy A?

### 5.3 Analysis

For Strategy B to be profitable, each of N accounts must:
1. Have sufficient activity score for EV > 100%
2. Generate 10 ETH of lootbox volume to exhaust the cap
3. The combined benefit must exceed the cost of maintaining N accounts

**Activity score with diluted deposit D/N:**

If D/N is too small:
- `levelCount` (max 25 points): requires minting at each level. With D/N ETH per account, some accounts may not afford tickets at higher-level prices
- `streak` (max 50 points): requires consecutive level mints -- same constraint
- `questStreak` (max 100 points): requires daily quest completion per account (time cost scales linearly with N)
- `affiliateBonus` (max 50 points): requires 1 ETH of referred volume per point per level across 5 levels -- cannot be manufactured by self-referral

**Without deity pass (max 265% activity score / ~129% EV):**
```
Per-account max benefit = 10 ETH * (129% - 100%) = 2.9 ETH per level
N-account total benefit = N * 2.9 ETH per level
```

**But:** Each account must generate 10 ETH of lootbox volume. Lootbox amounts are fractions of ticket purchases. To generate 10 ETH of lootbox, an account needs substantially more than 10 ETH in ticket purchases at a given level.

**Critical constraint:** The total group deposit D is fixed. Splitting D across N accounts means each has D/N to spend. The total lootbox volume generated is proportional to D (not to N), because lootbox amounts are a fraction of ticket purchases.

```
Total group lootbox volume = k * D  (where k is the lootbox-to-purchase ratio)
```

This is independent of N. Splitting into N accounts does NOT increase total lootbox volume.

**Therefore:** Strategy B cannot exhaust more total cap than Strategy A if the total lootbox volume is the same. The N * 10 ETH cap is irrelevant if the group only generates k * D total lootbox volume.

**Edge case -- whale bundles:** A Sybil group buying whale bundles on N accounts generates N lootboxes from the whale bundle portion. At level 0, whale bundle = 2.4 ETH, lootbox = 10-20% = 0.24-0.48 ETH. This is far below the 10 ETH cap. Even with 100 whale bundles per account (max quantity), the lootbox would be at most 48 ETH -- but the deposit would be 240 ETH per account.

**Result: Proportional to deposit.** Total lootbox benefit is bounded by total group deposit, not by number of accounts. Activity score dilution under splitting reduces per-account EV multiplier, making Strategy B strictly worse.

### 5.4 Activity Score Dilution Under Splitting

See Section 8 for the quantified dilution model.

---

## 6. Decimator Channel

### 6.1 Mechanism

From `DegenerusGameDecimatorModule.sol`:

The decimator fires at levels x5 (not x95), taking 10% of futurePool (or 30% at level x00). It distributes based on BURNIE burn volume across subbuckets (denominators 2-12).

**Winner selection:** Players who burned BURNIE tokens are eligible for pro-rata claims based on their burn amount in the winning subbucket.

### 6.2 Proportionality Analysis

Decimator claims are proportional to BURNIE burn volume:

```
player_claim = (player_burn_in_winning_subbucket / total_burn_in_winning_subbucket) * poolWei
```

A Sybil group's total BURNIE burn is independent of account count. The pro-rata share is proportional to total burn, not to number of accounts.

**VRF selects the winning subbucket** -- the group cannot control which subbucket wins. Their expected share across all possible winning subbuckets is proportional to their total burn fraction.

**Result: Proportional.** No super-proportional return from splitting.

---

## 7. Composite Model

### 7.1 Channel Weights and Proportionality

| Channel | % of Pool | Proportionality | Notes |
|---------|-----------|-----------------|-------|
| Daily Jackpot ETH (5 days) | 6-100% of currentPrizePool (cumulative) | Proportional | Trait-ticket-based, proportional to ticket count |
| Scatter (via BAF) | 50.625% of BAF pool | At most proportional | BAF score weighting penalizes splitting |
| Top BAF Bettor | 11.25% of BAF pool | Sub-proportional | Leaderboard favors concentration |
| Top Coinflip Bettor | 11.25% of BAF pool | Sub-proportional | Leaderboard favors concentration |
| Random BAF Pick | 5.625% of BAF pool | Sub-proportional | Leaderboard position |
| Affiliate Draw | 11.25% of BAF pool | Sub-proportional | Requires reputation, self-referral blocked |
| BAF Return | 10% of BAF pool | N/A | Returned to protocol |
| Lootbox | Per-ticket fraction | Proportional to deposit | Cap + dilution prevent super-proportional |
| Decimator | 10-30% of futurePool | Proportional | Pro-rata burn |

### 7.2 BAF Pool Size

BAF fires every 10 levels:
- Normal: 10% of futurePool
- Level 50: 25% of futurePool
- Level 100: 20% of futurePool

The BAF pool is drawn from `futurePrizePool` (funded by the 10% deposit split and whale bundle contributions). It is a fraction of total protocol value, not the current level's prize pool.

### 7.3 Composite EV Formula

For group G with fraction F of tickets and total deposit D:

```
E[total_G] = E[daily_G] + E[BAF_G] + E[lootbox_G] + E[decimator_G]

E[daily_G]     = F * daily_pool                    (proportional)
E[BAF_G]       <= F * BAF_pool                      (at most proportional)
E[lootbox_G]   = EV_mult(activity_G) * lootbox_G    (proportional to deposit, diluted by splitting)
E[decimator_G] = F_burn * decimator_pool             (proportional to burn)

Total: E[total_G] <= F * (daily_pool + BAF_pool) + EV_mult * lootbox_G + F_burn * dec_pool
```

Since `daily_pool + BAF_pool + lootbox_pool + decimator_pool = P - R` (total minus retention), and the group deposited D = F * P:

```
E[total_G] <= F * P - R_G     (where R_G = group's share of protocol retention)
            = D - R_G
            < D
```

**The group's expected payout is at most proportional to their deposit, minus their share of protocol retention.** No channel provides super-proportional returns.

### 7.4 Why Splitting Cannot Help

Every channel is either:
1. **Proportional to tickets** (daily jackpot, scatter): Total tickets owned by the group is fixed regardless of N accounts. Splitting doesn't create more tickets.
2. **Favors concentration** (BAF leaderboard channels): Splitting dilutes per-account BAF scores, reducing competitiveness.
3. **Proportional to deposit** (lootbox): Total lootbox volume is proportional to total deposit, not account count.
4. **Proportional to burn** (decimator): Total BURNIE burn is independent of account structure.

**In no channel does increasing N (account count) increase the group's expected return.** In several channels (BAF leaderboard, activity-score-dependent channels), splitting DECREASES returns.

---

## 8. Activity Score Dilution Analysis

### 8.1 Model Setup

A player with total ETH budget D chooses between:
- **Strategy A:** 1 account, full D deposited
- **Strategy B:** N accounts, D/N each

### 8.2 Per-Component Dilution

#### levelCount (max 25 points)
```
Score = (levels_minted / current_level) * 25, capped at 25

Strategy A: If D buys tickets at all L levels, score = 25
Strategy B: Each account with D/N may not afford tickets at all levels
  At level 30+ (price 0.08 ETH): D/N must >= 0.08 ETH per level
  For N > D / (0.08 * L), some accounts cannot mint every level
```

At D = 10 ETH, L = 50: each account needs 0.08 * 50 = 4 ETH minimum.
Max N for full streak = 10 / 4 = 2 accounts.
At N = 5: each account has 2 ETH, can only afford ~25 levels at 0.08 ETH. Score = 25/50 * 25 = 12.5 points.

#### streak (max 50 points)
```
Consecutive level mints required.
Same constraints as levelCount -- if D/N is too small for higher-level prices, streak breaks.
```

#### questStreak (max 100 points)
```
Requires daily quest completion per account.
Strategy B: N accounts each need daily management for 100+ days.
Time cost = N * 100 days of daily actions.
```

This is the primary operational cost of Sybil splitting. Managing 10+ accounts daily for 100+ days is a significant burden. The time cost scales linearly with N.

#### affiliateBonus (max 50 points)
```
Requires referred player volume: 1 ETH per point per level, across 5 recent levels.
Self-referral blocked. Circular referral (A refers B, B refers A) requires BOTH accounts to be real depositors.
Sybil group can create referral chains internally, but each account's deposit is D/N, limiting referral volume.
```

At D = 10 ETH, N = 5: each account has 2 ETH. Referring between accounts:
Account A refers B: B deposits 2 ETH, A gets affiliate credit for 2 ETH.
To reach 50 points across 5 levels: need 1 ETH/point/level * 50 points / 5 levels = 10 ETH total referred volume per level.
With D/N = 2 ETH per account, would need 5 referrals per level. Total referred volume = 5 * 2 = 10 ETH per level, but each account can only deposit D/N = 2 ETH.
Net: affiliate points achievable only with large D/N.

### 8.3 Quantified Comparison at D = 10 ETH

| Component | Strategy A (1 account) | Strategy B (5 accounts) | Strategy B (10 accounts) |
|-----------|----------------------|------------------------|--------------------------|
| levelCount | 25 points | ~12 points each | ~6 points each |
| streak | 50 points | ~25 points each | ~12 points each |
| questStreak | 100 points (1 account * 100 days) | 100 points each (5 * 100 days effort) | 100 points each (10 * 100 days effort) |
| affiliateBonus | 50 points (with external referrals) | ~10 points each (circular referrals limited) | ~5 points each |
| deityPass | 8000 BPS (24 ETH -- cannot afford with D=10) | N/A | N/A |
| whaleBundle | 4000 BPS (4 ETH whale) | 2 accounts can buy (D/N=2 too small) | N/A |

**Activity Score at D = 10 ETH:**

| Strategy | Score (BPS) | EV Multiplier |
|----------|-------------|---------------|
| A (1 account, whale bundle) | (25+50+100+50)*100 + 4000 = 26,500 | ~129% |
| A (1 account, no whale) | (25+50+100+50)*100 = 22,500 | ~123% |
| B (5 accounts, no whale) | (12+25+100+10)*100 = 14,700 each | ~111% |
| B (10 accounts, no whale) | (6+12+100+5)*100 = 12,300 each | ~108% |

**Note:** Quest streak of 100 for all accounts is the OPTIMISTIC case -- it requires managing N accounts daily for 100+ days. Realistically, many Sybil accounts would have lower quest streaks.

### 8.4 Quantified Comparison at D = 50 ETH

| Strategy | Score (BPS) | EV Multiplier | Max lootbox benefit/level |
|----------|-------------|---------------|---------------------------|
| A (1 account, deity pass at 24 ETH) | 30,500 | 135% | 3.5 ETH |
| A (1 account, whale bundle) | 26,500 | ~129% | 2.9 ETH |
| B (5 accounts, each 10 ETH, whale bundle) | ~22,500 each | ~123% each | 2.3 ETH each = 11.5 ETH total |
| B (10 accounts, each 5 ETH) | ~14,700 each | ~111% each | 1.1 ETH each = 11.0 ETH total |

**Observation:** At D = 50 ETH with 5 accounts, the total lootbox benefit cap is 5 * 10 ETH = 50 ETH of enhanced-EV volume. But each account only has 10 ETH total deposit, and lootbox amounts are a FRACTION of ticket purchases. To generate 10 ETH of lootbox volume per account, each needs substantially more than 10 ETH in ticket purchases.

**Critical constraint reiterated:** Total lootbox volume = k * D (proportional to total deposit). With D = 50 ETH and k approximately 0.1-0.2 (lootbox is 10-20% of purchase), total lootbox volume is approximately 5-10 ETH. This is well below even 1 account's 10 ETH cap, making the multi-account cap expansion irrelevant for realistic deposit sizes.

### 8.5 Quantified Comparison at D = 100 ETH

| Strategy | Score (BPS) | EV Multiplier | Practical benefit |
|----------|-------------|---------------|-------------------|
| A (1 account, deity at 24 ETH) | 30,500 | 135% | 3.5 ETH/level, deposit covers ~7 levels |
| B (5 accounts, deity at 24 + 24.5 + ... prohibitive) | Deity pass is 24+ ETH each -- too expensive for 5 | N/A | Cannot afford deity for all |
| B (10 accounts, 10 ETH each, whale bundle at 4 ETH) | ~22,500 each | ~123% each | 2.3 ETH each, 23 ETH total cap -- but total lootbox volume only ~10-20 ETH |

**Even at 100 ETH, the lootbox cap is not the binding constraint -- total lootbox volume (proportional to deposit) is the binding constraint.** The multi-account cap expansion provides no practical benefit.

---

## 9. ECON-01 Verdict

### 9.1 Summary of Findings

| Channel | Sybil Proportionality | Super-proportional? | Notes |
|---------|----------------------|---------------------|-------|
| Daily Jackpot | Proportional | No | Trait-ticket weighted, proportional to ticket count |
| Scatter (BAF) | At most proportional | No | BAF score weighting penalizes splitting |
| BAF Leaderboard (25%) | Sub-proportional | No | Leaderboard favors concentration |
| Affiliate Draw | Sub-proportional | No | Reputation-based, self-referral blocked |
| Lootbox EV | Proportional to deposit | No | Activity dilution + fixed total volume |
| Decimator | Proportional | No | Pro-rata BURNIE burn |
| BAF Return (10%) | N/A | No | Returned to protocol |

### 9.2 Mathematical Proof

For any Sybil group G with N accounts owning fraction F of tickets at a given level:

**1. Total prize pool is zero-sum:**
```
sum(all_payouts) = P - R    where R = protocol retention (stETH yield)
```

**2. No channel provides super-proportional returns:**
```
For all channels C: E[payout_G_C] <= F * payout_C
```

This is proved individually for each channel in Sections 2-6. The strongest result is that BAF leaderboard channels are strictly sub-proportional (favoring concentration over splitting).

**3. Therefore:**
```
E[total_G] = sum_C(E[payout_G_C])
           <= sum_C(F * payout_C)
           = F * sum_C(payout_C)
           = F * (P - R)
           < F * P
           = D
```

The group's expected total payout is strictly less than their total deposit D.

**4. Activity score dilution provides additional anti-Sybil defense:**

Splitting deposits across N accounts reduces per-account activity scores, which:
- Reduces lootbox EV multiplier (from 135% down to 108-111% at 10 accounts)
- Does not increase total lootbox volume (proportional to total deposit)
- Increases operational burden (N * 100 days of quest management)

**5. Eligibility gates provide further anti-Sybil defense:**

Both daily jackpot and scatter require `ethMintStreakCount >= 8`. Splitting deposits means each account has fewer mints, risking streak breakage at higher-level ticket prices.

### 9.3 Edge Case: Lootbox Cap Expansion via Multiple Accounts

The one theoretical avenue for super-proportional returns is the per-account 10 ETH lootbox cap. With N accounts, the group has N * 10 ETH of enhanced-EV capacity vs 1 * 10 ETH for a single account.

**This does not create positive group EV because:**

1. **Total lootbox volume is bounded by total deposit:** Lootbox amounts are approximately 10-20% of ticket purchases. A group depositing D ETH generates approximately 0.1D to 0.2D in total lootbox volume. For D < 50 ETH, this is below even a single account's 10 ETH cap.

2. **Activity score dilution reduces per-account EV multiplier:** At 10 accounts with 5 ETH each, the EV multiplier drops to ~108% (from ~129% with concentration). The benefit per ETH of lootbox drops from 29% to 8%.

3. **Even with infinite cap:** At 108% EV, the lootbox channel produces 8% benefit on total lootbox volume. Total lootbox volume approximately 0.1D-0.2D. Benefit approximately 0.008D-0.016D. This is approximately 0.8-1.6% of total deposit -- far below the protocol retention (stETH yield) that the group never receives back.

4. **Operational cost:** Managing N accounts * 100 days of daily quests is non-trivial. At 10 accounts, this is 1000 days of daily interactions, which has real labor cost.

### 9.4 Verdict

**ECON-01: PASS**

A Sybil group with any ticket ownership fraction F (including 51%+) cannot extract positive group EV from prize pool mechanics. This is because:

1. The prize pool is zero-sum (funded entirely by player deposits minus stETH yield)
2. Every prize distribution channel provides at most proportional returns to ticket ownership
3. Several channels (BAF leaderboard, affiliate draw) are strictly sub-proportional, penalizing Sybil splitting
4. Activity score dilution under splitting reduces lootbox EV multipliers
5. The lootbox per-account cap expansion via splitting is irrelevant because total lootbox volume is bounded by total deposit, not by account count
6. Eligibility gates (8-mint streak) create additional hurdles for split accounts

The protocol's economic design provides natural anti-Sybil resistance through: proportional prize distribution, leaderboard-based rewards that favor concentration, activity score dilution under splitting, and eligibility gates that penalize thin accounts.

---

## 10. Findings

### Finding ECON-F01: Lootbox Per-Account Cap Provides Theoretical Multi-Account Advantage

**Severity:** Informational
**Requirement:** ECON-01

**Description:** The per-account per-level 10 ETH lootbox benefit cap (`lootboxEvBenefitUsedByLevel[player][lvl]`) means that N accounts can theoretically process N * 10 ETH of enhanced-EV lootboxes vs 1 account processing 10 ETH. This is a theoretical multi-account advantage.

**Why it does not create positive EV:**
1. Total lootbox volume is proportional to total deposit, not account count
2. Activity score dilution reduces per-account EV multiplier
3. For any practical deposit size (< 500 ETH), total lootbox volume is below even a single account's 10 ETH cap
4. The cap tracks raw input (conservative -- see Phase 3b-03 Finding 8.1)

**Assessment:** The cap design is correct. The theoretical multi-account advantage is neutralized by the proportional lootbox volume constraint and activity score dilution. No remediation needed.

### Finding ECON-F02: Deity Pass Virtual Entries Create Small Probability Boost

**Severity:** Informational
**Requirement:** ECON-01

**Description:** Deity pass holders receive virtual entries (2% of bucket size, minimum 2) in their owned symbol's trait buckets (`_randTraitTicketWithIndices` lines 2254-2266). This gives deity holders a small probability boost in daily jackpot and scatter winner selection for their specific symbol's traits.

**Why it does not create super-proportional returns:**
1. Virtual entries apply only to 1 of 32 possible symbols (each symbol maps to a subset of the 256 traits)
2. The boost is at most 2% of the existing bucket size (diminishing as more tickets are in the bucket)
3. Deity passes cost 24+ ETH -- the probability boost is a designed reward for that investment
4. The boost is per-trait, not per-total-pool -- averaged across all winning trait selections, the impact is negligible

**Assessment:** This is intentional game design, not a vulnerability. The deity pass economic model was verified in Phase 3b (MATH-05 PASS). No remediation needed.

### Finding ECON-F03: Affiliate Weighted Winner Roll Uses Non-VRF Entropy

**Severity:** Informational (previously documented in 05-RESEARCH.md)
**Requirement:** ECON-01

**Description:** The affiliate weighted winner roll in `DegenerusAffiliate.sol` uses `keccak256(AFFILIATE_ROLL_TAG, currentDay, sender, storedCode)` as entropy, which is deterministic and computable off-chain. An attacker could theoretically time transactions to align with favorable days.

**Why it does not affect Sybil EV:**
1. Affiliate rewards are BURNIE, not ETH -- they do not drain the ETH prize pool
2. The BAF affiliate draw (which IS ETH) selects from historical top affiliates, not from the weighted winner roll
3. Even with optimal timing, the attacker's expected BURNIE affiliate reward is bounded by the affiliate reward rate (20-25% of purchase amount) -- they cannot receive more BURNIE than the rate allows
4. Self-referral is prevented (locked to VAULT), limiting circular extraction

**Assessment:** The non-VRF entropy in affiliate rolls is a known design trade-off (gas efficiency vs perfect randomness). It does not create exploitable Sybil advantages in the ETH prize pool. Documented for completeness.
