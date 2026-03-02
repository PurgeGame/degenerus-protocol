# Degenerus Protocol: Pre-Deployment Economic & Mechanism Design Analysis

**Date:** 2026-02-25
**Analyst:** Adversarial Mechanism Design Review
**Scope:** Full contract suite (22 deployable contracts, 10 delegatecall modules)
**Methodology:** Source-level code audit of all Solidity contracts, rational actor modeling, death spiral simulation, equilibrium analysis

---

## Executive Summary

The Degenerus Protocol is a zero-rake game system where player ETH deposits are converted to stETH, with yield funding prizes. The protocol features ticket purchases, lootboxes, a daily coinflip, a Degenerette slot-machine-style game, jackpots (BAF, Decimator, Daily), whale passes, deity passes, an affiliate system, a BURNIE utility token, and a DGNRS governance/yield token. Below is a comprehensive adversarial economic analysis.

---

## MANDATE 1: Actor Incentive Mapping

### 1. Degen Gambler (Thrill-Seeking, Loss-Tolerant)

**Role in the Economy:** The degen gambler is the primary source of EV for the rest of the system. These players are not EV-maximizing rational actors — they play for excitement, variance, and the chance to hit a life-changing jackpot tomorrow. The game is deliberately designed to offer them options with negative expected value (Degenerette at low activity scores, coinflip without compounding strategy, lootboxes without EV optimization) because they don't care about marginal EV — they care about the experience and the upside tail. The EV they "lose" is not destroyed; it is redistributed to the prize pools, jackpots, and lootbox resolutions that fund returns for EV maximizers, whales, and affiliates. Without degen gamblers, the system has no primary revenue source.

**What They Do:**
- Buy tickets, open lootboxes, play Degenerette, flip coins — whatever feels fun
- Chase the 100,000x Degenerette jackpot, the daily coinflip bounty, the scatter jackpot
- Their "optimal actions" are whatever is in their head — these are not spreadsheet players
- Some will stumble into good EV (high activity scores, quest streaks) simply by playing a lot

**Alignment with System Health:** ESSENTIAL. The degen gambler is the economic engine. Their purchases fill the prize pools (10% future, 90% next). Their BURNIE burns in Degenerette and coinflip maintain token velocity. The negative EV they accept is the subsidy that makes the entire prize structure work. If a degen gambler ever decides to optimize, the path to +EV is open to them (activity score, quest streaks, mint streaks) — the game rewards engagement, and degens who play a lot naturally accumulate the bonuses that improve their returns.

### 2. EV Maximizer (Rational, Risk-Neutral)

**Optimal Actions:**
- Maximize activity score to push Degenerette ROI from 90% toward 99.9% — **this is the primary +EV path** for anyone who cares about expected value
- Place ETH bets on Degenerette at high activity score: the base ROI approaches 99.9%, and an additional +5% ETH bonus is redistributed into 5-8 match buckets, making high-match outcomes genuinely +EV (effectiveRoi on 6-match can exceed 160%). Payouts are 25% ETH / 75% lootbox (lootbox portion has the same activity-score EV multiplier as regular lootboxes, 80-135%)
- Buy whale bundles at levels 0-3 (2.4 ETH for 100 levels of coverage with 40 tickets/level early bonus)
- Enable auto-rebuy on coinflip with take-profit to compound the 1.6% afKing recycling bonus
- Acquire deity pass early (24 ETH base) for permanent 80% activity bonus and enhanced recycling
- Focus on ETH lootboxes at high activity score for 135% EV multiplier (capped at 10 ETH benefit/level)
- Pursue daily jackpot eligibility (8+ ETH mint streak) for access to 6-14% of current pool

**Alignment with System Health:** ALIGNED. EV maximizers are the protocol's ideal engaged users. Their heavy participation fills pools. Their ability to extract 135% EV on lootboxes (up to 10 ETH/level) creates a structural subsidy from low-activity players to high-activity ones. This is by design — low-activity players are gamblers who don't care about EV optimization, and if they ever start caring, the path to +EV is open to them (quest streaks, mint streaks, affiliate engagement). The system rewards effort, not insider knowledge.

### 3. Whale (Capital-Rich, Value-Extracting)

**Optimal Actions:**
- Buy deity pass early (24 ETH + T(n)) when n is small for permanent advantages
- Stack deity pass with afKing mode for enhanced coinflip recycling (up to 3% bonus per carry)
- Purchase whale bundles in bulk (up to 100 at a time) for 100-level ticket coverage
- Dominate BAF leaderboard through large coinflip stakes for 10% of jackpot pool
- Use whale bundle's 40% activity bonus to boost all other EV calculations

**Alignment with System Health:** ALIGNED. Whales provide essential upfront capital and lock liquidity through deity pass and whale bundle purchases, funding the prize pools that benefit all players. Their edges (BAF leaderboard, enhanced recycling, activity bonuses) are earned through capital commitment, not information asymmetry. Smaller players still have fair access to the vast majority of jackpot payouts — scatter distribution (50% of jackpot, trait-based) is broadly distributed, daily jackpot is accessible to anyone with an 8-mint streak, and the decimator is purely ticket-based. The 32-pass cap on deity passes prevents unbounded whale accumulation.

### 4. Affiliate (Commission-Seeking)

**Optimal Actions:**
- Build referral network early for 25% of referred players' ETH mints (levels 1-3), 20% (level 4+)
- Stack upline tiers: upline1 gets 20% of base, upline2 gets 4% of base
- Set rakeback to 25% to attract referred players, earning net 75% of base rate
- Choose SplitCoinflipCoin payout mode (50% BURNIE, 50% discarded) -- worst EV but builds BURNIE position
- Target high-volume players for daily jackpot affiliate draw (11.25% of jackpot pool)

**Alignment with System Health:** ALIGNED. Affiliates drive player acquisition. The weighted winner roll system (deterministic per day+sender+code) prevents gaming of multi-recipient payouts. Self-referral prevention (locked to VAULT sentinel) eliminates the most obvious affiliate abuse. The 3-tier cap prevents excessive commission pyramiding.

### 5. Griefer (Disruption-Seeking)

**Optimal Actions:**
- Attempt to block advanceGame() by not minting daily (daily mint gate required)
- Attempt to grief VRF by exploiting 18h timeout to delay game progression
- Spam low-value transactions to increase gas costs for other players
- Attempt to manipulate decimator subbuckets by choosing low-denominator buckets

**Alignment with System Health:** MITIGATED. CREATOR bypass on daily mint gate ensures game always advances. 18h VRF retry timeout limits delay impact. 3-day emergency stall triggers alternate advancement path. Decimator subbucket assignment is deterministic from keccak256(player, level, bucket), preventing bucket shopping.

### 6. Competitor (Intelligence-Gathering)

**Optimal Actions:**
- Monitor on-chain activity to understand player engagement metrics
- Analyze prize pool flows to understand protocol economics
- Study activity score formula to understand engagement incentive design
- Examine DGNRS token distribution for governance attack potential

**Alignment with System Health:** NEUTRAL/THREAT. All on-chain data is public. The protocol's competitive moat lies in its engagement mechanics and community, not information asymmetry. No material intelligence risk.

### 7. Late Entrant (Joining After Many Levels)

**Optimal Actions:**
- Purchase whale bundle for instant 100-level coverage (catches up on tickets)
- Focus on quest completion and coinflip for BURNIE accumulation
- Target lootbox EV bonus by rapidly building activity score (quest streak + mint streak)
- BAF leaderboard resets every 10 levels — compete for top positions in the current cycle
- Look for deity pass discount boons from lootboxes (10/25/50% off)

**Alignment with System Health:** SLIGHTLY DISADVANTAGED but LARGELY FAIR. Higher ticket prices at later levels don't meaningfully hurt late entrants — prize pools scale with deposits, so the EV per ticket is roughly the same regardless of when you join. Earlier players didn't get cheaper tickets for the same jackpot; they got cheaper tickets for smaller pools. The real disadvantage is deity passes already sold at lower prices (quadratic pricing means later passes cost more). BAF leaderboard resets every 10 levels, so there is no incumbency advantage there. Whale bundles and lootbox ticket rolls provide catch-up mechanics.

---

## MANDATE 2: Specific Economic Attack Vectors

---

## [LOW] Affiliate Weighted Winner Roll Day-Alignment

**Mechanism:** Affiliate reward distribution uses a weighted winner roll seeded by `keccak256(AFFILIATE_ROLL_TAG, currentDay, sender, storedCode)`. This is deterministic per day+sender+code combination.

**Actor Type:** EV Maximizer / Affiliate

**Attack Steps:**
1. Pre-compute the daily roll outcome off-chain for each possible sender address
2. Identify days when specific sender addresses will route the affiliate reward to the desired recipient
3. Coordinate transactions on favorable days

**Profitability:** LOW. The roll determines which of multiple recipients gets the payout, not whether a payout occurs. Rewards are 25% of ETH mints (levels 1-3) or 20% (level 4+). Coordination costs likely exceed the marginal benefit of timing. The daily granularity limits frequency of favorable outcomes. The entropy source includes `sender` address, making pre-computation require knowing exact transaction originator.

**System Impact:** MINIMAL. Even successful day-alignment only redistributes affiliate rewards among legitimate referrers, not inflates total payouts.

**Mitigation:** The existing design is adequate. The deterministic nature prevents VRF dependency while the day+sender+code triple makes manipulation impractical for most actors.

---

## [MEDIUM] Whale Pass Pricing Step Function Exploitation

**Mechanism:** Whale bundle pricing has a step function: 2.4 ETH for levels 0-3, 4 ETH for x49/x99 levels. The whale bundle grants 100 levels of coverage with 40 tickets/level for early levels (0-10) dropping to 2 tickets/level thereafter.

**Actor Type:** Whale / EV Maximizer

**Attack Steps:**
1. Purchase whale bundles at level 0-3 (2.4 ETH) for maximum ticket density (40 entries/level = 10 full tickets/level for levels 0-10)
2. At early levels, a bundle provides 100 full tickets across 10 bonus levels (~1 ETH face value at 0.01 ETH/ticket) plus 0.5 full tickets/level for 90 standard levels at increasing prices
3. Accumulate multiple bundles (up to 100 per transaction) to dominate ticket holdings at early levels
4. These tickets grant jackpot eligibility and activity score bonuses for all future gameplay

**Profitability:** MODERATE. An early whale bundle (2.4 ETH) provides ~6.10 ETH in total ticket face value (~2.5x). Bonus levels 1-10 (10 full-ticket equivalents/level) account for ~1.80 ETH, while standard levels 11-100 (0.5 full-ticket equivalents/level at escalating prices up to 0.24 ETH) account for ~4.30 ETH. The bulk of the value is in future-level coverage at prices that would cost much more to buy individually. However, tickets at future levels have time-discounted value and the game must actually reach those levels.

**System Impact:** MODERATE. Early whale bundle buyers subsidized by the protocol's pricing model. Funds do flow to prize pools (30% next / 70% future pre-game, 5% next / 95% future post-game), so the protocol still captures value. But ticket-price-to-bundle-cost ratio creates alpha for early sophisticated players.

**Mitigation:** The graduated pricing (2.4 ETH early, 4 ETH at x49/x99) partially addresses this. The 100-bundle-per-tx limit caps accumulation rate. Consider whether the 40-tickets/level bonus for levels 0-10 is too generous relative to the 2.4 ETH cost.

---

## [LOW] Ticket Pricing Manipulation via Level Advancement Timing

**Mechanism:** Ticket prices follow a fixed schedule (PriceLookupLib): 0.01 ETH at levels 0-4, stepping up to 0.24 ETH at x00 levels. The advanceGame() function progresses levels.

**Actor Type:** Griefer / Competitor

**Attack Steps:**
1. Observe current level approaching a price step boundary
2. Attempt to delay or accelerate level advancement to exploit price changes
3. advanceGame() requires daily mint (skin-in-game gate) but CREATOR can bypass

**Profitability:** NEGLIGIBLE. Price steps are predetermined and publicly known. advanceGame() is permissionless but gated by daily mint requirement. CREATOR bypass is an operational concern, not a player exploit. Anyone can call advanceGame() after meeting requirements.

**System Impact:** MINIMAL. The 2-state FSM (PURCHASE <-> JACKPOT) with VRF gating means level advancement cannot be arbitrarily accelerated. Natural game progression determines pricing.

**Mitigation:** Existing design is adequate. The daily mint gate, VRF gating, and deterministic pricing schedule eliminate meaningful manipulation surface.

---

## [N/A] Vault Share Concentration

**Not a concern.** The vault (DGVE/DGVB shares) is retained by the CREATOR and not distributed to players. The vault owner has no privileged game operations — they can only burn their own shares to claim pro-rata reserves. This is the protocol operator's revenue mechanism, not a player-facing attack surface.

---

## [LOW] Coinflip EV Exploitation via Auto-Rebuy Compounding

**Mechanism:** The coinflip is a true 50/50 (VRF bit), with reward percent ranging 78-150% (mean ~96.85 BPS). Auto-rebuy carries winnings forward with a 1% recycling bonus (capped at 1000 BURNIE) or 1.6% afKing bonus. afKing with deity pass adds up to 3% additional recycling (2 half-bps per level, max 300 half-bps = 1.5%, plus 1.6% base).

**Actor Type:** EV Maximizer with Deity Pass

**Attack Steps:**
1. Acquire deity pass and activate afKing mode
2. Enable auto-rebuy with no take-profit (zero stop)
3. Deposit large BURNIE stake (e.g., 100,000 BURNIE)
4. On wins, carry = payout + recycling bonus (up to ~3.1% of carry)
5. Compound over multiple winning days
6. The coinflip has 50% win rate, mean reward ~96.85%, so raw EV = 50% * (1 + 0.9685) = 98.4%
7. Recycling bonus adds ~3.1% on carry for winning days only
8. Net EV per day (with recycling): ~50% * (1.9685 * 1.031) + 50% * 0 = ~101.5%

**Profitability:** MARGINAL. The recycling bonus is capped: 1000 BURNIE for base mode, deity bonus capped at DEITY_RECYCLE_CAP (1M BURNIE). For a 100k BURNIE stake:
- Base win payout: ~196,850 BURNIE
- Recycling bonus: ~1,000 BURNIE (capped)
- Net EV with recycling: ~50% * 197,850 = 98,925 vs 100,000 stake = 98.9% (still negative)
- Even with maximum deity bonus (3.1% uncapped up to 1M): for 100k stake, bonus = ~6,100 BURNIE
- Net: 50% * 203,000 = 101,500 vs 100,000 = +1.5% EV

The BURNIE token must maintain value for this to be profitable in ETH terms. BURNIE has complex supply dynamics: the coinflip is a net deflationary mechanism (all deposits burned upfront, wins only partially compensate), while synthetic credits (quests, recycling bonuses, bounties) and game rewards are inflationary. Other deflationary sinks include decimator burns and vault transfers. If BURNIE price declines, the +1.5% BURNIE EV may be negative in ETH terms.

**System Impact:** LOW. The cap on recycling bonus limits extraction. The protocol deliberately offers this as an engagement incentive for deity pass holders. The risk is if too many deity pass holders compound simultaneously, inflating BURNIE supply faster than burn mechanisms can absorb.

**Mitigation:** The DEITY_RECYCLE_CAP (1M BURNIE) limits per-carry bonus. The 1000 BURNIE cap on base recycling prevents non-deity exploitation. The 50% base loss rate provides natural mean-reversion. Consider monitoring BURNIE supply inflation rate vs burn rate post-launch.

---

## [LOW] Quest System Gaming via Minimal Completion

**Mechanism:** Daily quests have 2 slots: slot 0 always MINT_ETH (100 BURNIE reward, target: 1x current mint price capped at 0.5 ETH), slot 1 weighted random from 6-7 eligible types (200 BURNIE reward). Quest streaks provide up to 100 activity score points (100 * 100 = 10,000 BPS).

**Actor Type:** EV Maximizer

**Attack Steps:**
1. Complete daily MINT_ETH quest with minimum 2 tickets (cost: 0.005 ETH at 0.01 ETH levels)
2. Complete slot 1 quest based on type (some require 2000 BURNIE for flip, others 2x price for lootbox)
3. Maintain streak with shields to avoid resets
4. Build quest streak to 100 for maximum activity bonus (10,000 BPS)
5. Use high activity score to boost lootbox EV to 135% and Degenerette ROI to 99.9%

**Profitability:** LOW INDIVIDUAL, HIGH AGGREGATE. The 300 BURNIE daily reward for quest completion is modest. The real value is the activity score boost. At high activity (305% = max), lootbox EV reaches 135% and Degenerette ROI reaches 99.9%. The cost to maintain a 100-day quest streak is approximately 100 * 0.005 ETH = 0.5 ETH in minimum ticket purchases plus BURNIE costs for slot 1. The activity score benefit is worth significantly more through boosted EV on all other activities.

**System Impact:** BENEFICIAL. Quest gaming incentivizes daily engagement, which is the protocol's core retention mechanic. The minimum ticket purchases fund prize pools. The activity score system intentionally rewards consistent players.

**Mitigation:** No mitigation needed. This is intended behavior. The quest system successfully converts engagement into measurable activity scores that drive EV distribution.

---

## [MEDIUM] Jackpot Prize Pool Manipulation via BAF Leaderboard Concentration

**Mechanism:** BAF (Big Ass Flip) jackpot distributes prizes from the future pool at x10 levels. Distribution: 10% to top BAF, 10% to top daily flip, 5% to random 3rd/4th, 11.25% to affiliate draw, ~50% to scatter (trait-based). Eligibility requires ethMintStreakCount >= 8. Max 5 daily jackpots per level.

**Actor Type:** Whale

**Attack Steps:**
1. Build large coinflip position to dominate BAF leaderboard
2. BAF credit is recorded from winning coinflip payouts: `jackpots.recordBafFlip(player, bafLvl, winningBafCredit)`
3. Larger coinflip stakes produce larger winning payouts, producing larger BAF credits
4. Top BAF position earns 10% of jackpot pool (10-25% of future pool)
5. At x10 levels, if future pool is 100 ETH and jackpot takes 15%, top BAF earns 1.5 ETH

**Profitability:** MODERATE for large players within a given 10-level cycle. The 8-mint-streak eligibility gate ensures minimum engagement. BAF leaderboard is size-based (total winning flip credit), giving large stakers an advantage — but it resets every 10 levels, so dominance must be re-earned each cycle. Four top-4 positions per level are available, with the top position getting 60% of the 10% top-BAF allocation.

**System Impact:** LOW-MODERATE. The 10-level reset prevents permanent leaderboard lock-in. The scatter mechanism (50% of jackpot, trait-based) distributes broadly regardless of BAF position. The daily flip leaderboard provides an alternative path. The 5-daily-jackpot cap per level prevents indefinite extraction.

**Mitigation:** The 10-level BAF reset is the primary defense — no one accumulates a permanent advantage. The scatter distribution (50 rounds x 4 trait tickets, top-2 by BAF score per round) provides broad-based distribution. Trait assignment is deterministic from player address but varies per round, preventing systematic scatter domination.

---

## [KEY INSIGHT] Degenerette ETH Bets Are +EV at High Activity Score

**Mechanism:** Degenerette ETH bets have a 3-layer payout structure that creates genuine +EV for engaged players:

1. **Base ROI scales with activity score:** 90% (0% activity) → 99.9% (305% activity), following a quadratic-then-linear curve
2. **+5% ETH bonus redistributed into high matches:** An additional `ETH_ROI_BONUS_BPS = 500` is stripped from low-match outcomes (0-4 matches) and concentrated into match buckets 5-8. At 6 matches, the bonus factor is ~13x, pushing effectiveRoi to ~160%+ at max activity. At 7-8 matches the bonus is even larger.
3. **Payout split is 25% ETH / 75% lootbox:** The lootbox portion has the same activity-score EV multiplier (80-135%) as regular lootbox opens, compounding the +EV for high-activity players. At max activity, the 75% lootbox portion is scaled to 135% of face value.

**Why this matters:** This is the primary +EV path in the entire protocol for anyone who cares about expected value. A player at max activity score (305%) betting ETH on Degenerette has:
- Near-zero house edge on low-match outcomes (99.9% ROI)
- Genuinely positive EV on 5+ match outcomes (ETH bonus redistribution exceeds the 0.1% edge)
- All excess value delivered as lootbox tickets and BURNIE, not direct ETH

**System alignment:** This is by design. The +EV reward goes to the most engaged players (high activity score requires daily quests, mint streaks, affiliate activity). The value extraction is bounded by bet size limits and the 10% pool cap on ETH payouts. The lootbox delivery mechanism converts +EV into future game participation (tickets at future levels, BURNIE for coinflip) rather than immediate ETH extraction, creating a self-reinforcing engagement loop.

---

## [LOW] Degenerette ETH Payout Pool Solvency Under Extreme Wins

**Mechanism:** Degenerette ETH bets go to futurePrizePool. Wins are distributed 25% ETH (capped at 10% of pool) + 75% lootbox. The 8-match jackpot pays 100,000x.

**Why This Is Not a Real Concern:**

Degenerette is a net contributor of ETH to the system — the house edge means more ETH flows in from losing bets than flows out from wins over time. On the rare occasion someone hits a massive jackpot:

1. **ETH portion is hard-capped** at 10% of futurePrizePool (`ETH_WIN_CAP_BPS = 1000`). The pool cannot be drained regardless of jackpot size.
2. **The lootbox portion (75%) resolves as tickets spread across ~100 future levels.** This isn't a sudden obligation — it's distributed game activity that plays out over the long term, diluted across many levels of prize pool competition.
3. **Very large wins (>5 ETH lootbox half) get deferred to whale pass claims**, further spreading the impact.

**Severity:** LOW. The system is solvent by construction. The 10% ETH cap is the hard guarantee, and the lootbox ticket distribution across 100 levels means even a 100,000x jackpot hit creates only a modest per-level ticket increase relative to normal volume.

---

## [LOW] Late-Entry Disadvantage and Soft Ponzi Characteristics

**Mechanism:** Prize pools grow from player deposits. Ticket prices increase with level. Prize distribution occurs at jackpot levels.

**Why Higher Ticket Prices Don't Matter:**

Ticket prices scale with level, but so do prize pools — because the pools are funded by those same ticket purchases. A player buying a 0.08 ETH ticket at level 50 is competing for a pool that was filled by 0.08 ETH tickets, not the 0.01 ETH tickets from level 0. The EV per ticket is roughly constant regardless of entry level. Early players didn't get "cheap" tickets for today's jackpot — they got cheap tickets for small early pools.

The only real early advantages are:
- **Deity passes** are cheaper when fewer have been sold (quadratic pricing: 24 + T(n) ETH)
- **Whale bundle bonus tickets** (40/level for first 10 levels) reward early whale buyers with extra coverage
- These represent a small fraction of total tickets in the system

**Not a Ponzi Because:**
1. No payouts from new player deposits directly to old players (zero-rake)
2. Prize funding comes from stETH yield, not principal
3. Ticket purchases go to prize pools that benefit all eligible players at that level
4. No recruitment requirement for returns
5. BAF leaderboard resets every 10 levels — no permanent incumbency advantage

**System Impact:** LOW. Late entrants face roughly equivalent per-ticket EV to early players. The activity score system rewards engagement over capital, and whale bundles provide instant catch-up on ticket coverage. The BOOTSTRAP_PRIZE_POOL (50 ETH at level 0) ensures minimum starting pool size.

---

## MANDATE 3: Death Spiral Analysis

### Scenario A: Player Exodus Cascade

**Trigger:** General loss of interest or external market conditions driving players away

**Why It's Self-Correcting:**

The protocol's prize pools are locked and accumulating — they don't leave with the players. When players exit:

1. Prize pools (daily jackpot, scatter jackpot, lootbox pool, Decimator pool) continue growing from stETH yield
2. Fewer active players means each remaining player's share of those pools increases
3. This creates a natural "buy low" attractor: as player count drops, per-player EV rises, drawing opportunistic players back in
4. The coinflip is a sideshow engagement mechanic, not the core value proposition — the real draw is jackpots, Degenerette, and Decimator, all of which pay ETH

**Structural Resilience:**
- stETH yield continues regardless of player activity
- Prize pools accumulate during inactive periods, making re-entry increasingly attractive
- 912-day idle timeout at level 0, 365-day inactivity timeout later — the game is patient
- CREATOR can bypass daily mint gate to advance game if needed

**Severity:** LOW. The only true failure is 365 days of *zero* activity triggering game-over. Any activity at all keeps the game alive, and growing prize pools create increasing incentive for someone to show up.

### Scenario B: BURNIE Token Price Decline — Why It Has a Floor

BURNIE cannot spiral to zero because every unit of BURNIE in existence was minted in exchange for ETH entering the system. The token has concrete utility that translates directly into ETH value:

**ETH-Backed Issuance:** Every source of BURNIE requires ETH flowing in:
- Minting tickets with ETH → BURNIE coin rewards
- Quest rewards are funded by ongoing ETH ticket purchases
- Vault BURNIE is backed by the vaultMintAllowance reserve

**Utility Floor — Ticket Fuel:** BURNIE purchases tickets at a fixed rate (1000 BURNIE/ticket regardless of level). As long as people play the game, there is base demand for BURNIE as ticket fuel. If BURNIE price drops below this implied value, rational players buy cheap BURNIE for tickets instead of paying ETH — creating buy pressure that restores the floor.

**Utility Floor — Decimator:** Burning BURNIE in the Decimator competes for ETH prize pools. If BURNIE is cheap, the cost-per-ETH-of-expected-value via Decimator drops, making it an increasingly attractive arbitrage. Rational players buy cheap BURNIE to burn for a shot at ETH prizes — again creating buy pressure proportional to the discount.

**Utility Floor — Lootboxes:** BURNIE lootboxes convert at 80% ETH-equivalent value, providing another price reference tied to ETH.

**Net Deflationary Pressure:** The coinflip burns ALL deposits at stake time; losers get nothing back, winners receive newly minted tokens (~1.97x) — net ~1.6% of all stakes are permanently destroyed. This means total BURNIE supply shrinks over time relative to the ETH that created it.

**Severity:** LOW. The price can fluctuate, but the structural floor is set by the ETH-denominated utility of BURNIE across tickets, Decimator, and lootboxes. A "spiral" requires the utility to disappear, which only happens if the game itself stops — at which point the game-over jackpot process handles final distribution.

### Scenario C: Whale Departure Cascade

**Trigger:** Top deity pass holders exit the game

**Why Whale Departure Is Net Positive for Remaining Players:**

A whale is a net *extractor* — they deposit ETH, but their high activity scores, deity boons, and affiliate networks mean they capture a disproportionate share of prize pools relative to their deposits. When a whale leaves:

1. **Their deposits disappear** — prize pool growth rate slows (negative effect)
2. **Their extraction disappears** — they stop claiming jackpots, Degenerette payouts, Decimator prizes, affiliate rakes, and deity boon advantages (positive effect)
3. **Effect #2 outweighs #1** — because the whale was a skilled, optimized player capturing *more* than they put in (that's what makes them a whale). Their share of prize distributions is redistributed across all remaining players.

**Concrete Mechanism:**
- Jackpot pools (daily, scatter, lootbox) are sized by total deposits. A whale leaving reduces deposits by X but removes a player who was winning >X in expected jackpot value.
- Activity score rankings compress upward — every remaining player's relative position improves, boosting their EV multiplier (80-135% range) and jackpot weighting.
- Decimator bucket competition decreases — fewer high-multiplier burns means remaining burners face better odds per ETH of prize pool.
- Degenerette payout pool has one fewer skilled bettor extracting from it.

**The "Whale Departure Paradox":** The protocol is healthier per-player after a whale leaves, even though total volume drops. This is structurally different from DeFi protocols where whale departure causes liquidity crises — here, prize pools are locked and accumulated, not withdrawable.

**When It IS Negative:**
- If the whale dumps their BURNIE holdings on exit, creating sell pressure on the token price
- If departure triggers a confidence cascade where *many* players leave simultaneously — but even then, the remaining players' per-capita EV increases further. The only true failure mode is if the game ends entirely (idle timeout after 365 days of zero activity). As long as the game continues, every departure concentrates more prize pool value into fewer hands.

**Severity:** LOW. Deity passes are capped at 32 total, limiting maximum whale concentration. The scatter jackpot mechanism (50% of jackpot, distributed by traits) ensures broad distribution independent of whale participation. The self-correcting EV rebalancing means the game naturally adjusts to any population size — fewer players means more prize per player.

**Circuit Breaker:** Deity pass refund mechanism (if level 0 after 24 months, 730 days = DEITY_PASS_REFUND_DAYS) provides a safety net for early buyers if the game fails to progress.

### Scenario D: Combined Stress Test

**Trigger:** Market downturn reducing ETH price + player exodus + BURNIE decline

**Cascade:**
1. ETH price drops 50%, reducing stETH yield in USD terms
2. Players sell positions, prize pools denominated in ETH maintain nominal value but real value halved
3. BURNIE drops proportionally (or more) as speculative premium evaporates
4. New player acquisition halts (crypto winter)
5. Existing players face negative EV on all BURNIE activities
6. Only hardcore players remain, activity score system still differentiates engagement levels
7. stETH yield (in ETH) is actually stable/increasing during market stress
8. Prize pools in ETH terms continue accumulating

**Recovery:** The protocol's ETH-denominated design means stETH yield is stable in ETH terms regardless of USD market conditions. This provides a natural floor. The game can sustain low activity through the idle timeout system (365 days inactivity). Prize pool accumulation during dormancy creates a "re-entry bonus" for returning players.

---

## MANDATE 4: Equilibrium Analysis

### Nash Equilibrium: Active Participation

The dominant strategy for all player types is consistent daily engagement. The activity score system creates a powerful Nash equilibrium:

1. **If others participate actively:** Your activity score must be high to compete for jackpot positions and achieve high ROI. Defecting (low engagement) yields lower returns.

2. **If others participate minimally:** Your consistent participation earns relatively higher activity scores, capturing proportionally larger shares of smaller pools. Still optimal to participate.

3. **The equilibrium is "always engage daily"** because the activity score formula rewards streak consistency (up to 50 points), mint frequency (up to 25 points), quest completion (up to 100 points), and affiliate engagement -- all of which require daily action.

### Stability Assessment

**Stable Elements:**
- Activity score incentive structure creates self-reinforcing engagement
- Zero-rake design means player deposits fund stETH yield, not operator extraction
- Prize pool accumulation creates natural attractors during low activity
- Multiple engagement vectors (coinflip, Degenerette, quests, affiliates) provide diverse appeal

**Unstable Elements:**
- BURNIE token value depends on continued gameplay activity (structural equilibrium holds as long as people play)
- Deity pass pricing (quadratic growth) creates increasing barrier for late participants
- BAF leaderboard concentration favors capital-intensive players
- Activity score difference between min (90% ROI) and max (99.9% ROI) creates a 10% gap that compounds over time

### Growth Scenario

**Conditions:** Steady new player acquisition, ETH price stable or rising, stETH yield > 3%

- Prize pools grow linearly with deposits
- stETH yield provides sustainable prize funding
- Activity score competition drives engagement
- Affiliate network expands referral base
- BURNIE token maintains value through burn/mint equilibrium
- Deity passes sell at increasing prices, funding prize pools
- Game progresses through levels, unlocking new jackpot opportunities

**Steady-State:** At maturity (all 32 deity passes sold, stable player base), the protocol becomes a yield-funded entertainment system where stETH yield is redistributed based on engagement metrics. The key metric is whether stETH yield on total deposits exceeds the expected value distributed through prizes. Since the protocol is zero-rake and prizes come from yield, this should be sustainable indefinitely.

### Decline Scenario

**Conditions:** Player acquisition < churn, BURNIE declining, competitive alternatives emerge

- Prize pools grow slower than prize distribution
- Current pool depletes faster than next pool fills
- Jackpot sizes decrease, reducing engagement incentive
- Activity scores cluster at extremes (highly engaged or inactive)
- BURNIE inflation exceeds burns, token value declines
- Late-entry disadvantage becomes more pronounced

**Terminal State:** The protocol's terminal defense is the idle timeout system. After 365 days of inactivity, the game can resolve through emergency mechanisms. Remaining prize pools can be claimed by active participants. The deity pass refund mechanism (730 days at level 0) ensures early investors are partially protected.

---

## Economic Health Verdict

**OVERALL ASSESSMENT: SOUND WITH MODERATE STRUCTURAL RISKS**

The Degenerus Protocol demonstrates sophisticated mechanism design with several notable strengths:

1. **Zero-rake architecture** eliminates the most common failure mode (operator extraction exceeding sustainable yield)
2. **Activity score system** creates a well-designed engagement flywheel that rewards consistent participation
3. **Multiple prize distribution mechanisms** (BAF, Decimator, Daily, Scatter) prevent single-point-of-failure in reward distribution
4. **ETH solvency invariant** (`address(this).balance + steth.balanceOf(this) >= claimablePool`) is enforced across all modules
5. **VRF-based randomness** eliminates manipulation of game outcomes
6. **Degenerette ETH payout cap** (10% of pool) prevents solvency attacks from extreme jackpots

The primary structural risks are:
1. **Late-entry disadvantage** -- the perception (even if not the reality) of early-player advantage could deter growth
2. **Deity pass concentration** -- 32 passes with quadratic pricing creates a permanent class divide in engagement rewards
3. **Player acquisition dependency** -- the system is robust while people play, but prolonged player drought tests the timeout/game-over mechanisms

---

## Risk Matrix

| Risk | Likelihood | Impact | Severity | Status |
|------|-----------|--------|----------|--------|
| ETH solvency breach | Very Low | Critical | LOW | Mitigated by invariant + cap |
| BURNIE hyperinflation | Low | Moderate | LOW | Structural equilibrium: never minted without ETH entering; primary sink (tickets/lootboxes) scales with play; coinflip net deflationary |
| Whale leaderboard dominance | High | Moderate | MEDIUM | By design, partially mitigated by scatter |
| Late-entry player churn | Moderate | High | MEDIUM | Catch-up mechanics exist |
| Affiliate system gaming | Low | Low | LOW | Self-referral blocked, weighted roll |
| Vault concentration attack | Low | Moderate | LOW | 30% threshold, intended functionality |
| Coinflip compounding exploit | Moderate | Low | LOW | Caps limit extraction |
| Degenerette pool drain | Very Low | High | LOW | 10% cap enforced |
| VRF manipulation | Very Low | Critical | LOW | Chainlink VRF V2.5 |
| Game progression stall | Low | Moderate | LOW | CREATOR bypass, timeout system |
| DGNRS governance attack | Low | Moderate | LOW | 0.05% threshold for boons |
| Death spiral (combined) | Low | Critical | MEDIUM | Multiple circuit breakers |

---

## Top 3 Recommendations

### 1. BURNIE Supply Monitoring (Operational)

**Priority:** LOW
**Rationale:** BURNIE hyperinflation was a primary design concern and the tokenomics were built to prevent it. BURNIE is never created without ETH entering the system to "cover" it. The primary sink — buying tickets and lootboxes with BURNIE — naturally achieves equilibrium as long as people play the game. If they stop playing, BURNIE deflation is irrelevant because the game-over jackpot process (which is BURNIE-denominated) triggers anyway. The coinflip is net deflationary (~1.6% of all stakes destroyed). Operational monitoring of supply metrics is still good practice but dynamic adjustment mechanisms are unnecessary — the equilibrium is structural.

**Specific Concern:** The coinflip itself is deflationary for almost every actor — all deposits are burned upfront via `burnForCoinflip()`, winners receive newly minted tokens (~1.97x average), and losers get nothing back. The net effect is ~1.6% permanent destruction of all staked BURNIE. However, synthetic credits entering the flip without a corresponding burn (quest rewards, recycling bonuses, bounties) are inflationary when won. Quest rewards (300 BURNIE/day per active player) add steady inflation through this channel. Decimator burns are voluntary and may not scale with synthetic minting. The vault transfer burn (redirect to mint allowance) is a clever deflationary mechanism but depends on players sending BURNIE to the vault.

### 2. Strengthen Late-Entry Catch-Up Mechanisms

**Priority:** MEDIUM
**Rationale:** The activity score system rewards long-term engagement (mint streak, quest streak, level count), which structurally disadvantages new players. While whale bundles provide ticket coverage, they do not help with activity score. The 10% gap between minimum (90% ROI) and maximum (99.9% ROI) in Degenerette means new players face 10% worse expected returns on their bets.

**Suggestion:** Consider implementing an "onboarding bonus" that provides temporary activity score boost for new players (e.g., first 30 days get a minimum activity score floor). This would be analogous to the WHALE_PASS_STREAK_FLOOR_POINTS mechanism already present for whale pass holders. The activity boon from lootboxes (10/25/50 bonus points) partially addresses this but is probabilistic.

### 3. Real-Time Pool Analytics (Internal / Power-User Tooling)

**Priority:** LOW
**Rationale:** The prize pool flow (future -> next -> current -> claimable) is deliberately opaque. The game is designed so that sophisticated players who understand the mechanics extract value from casual players who are there for the gambling experience and don't care about the math. This information asymmetry is a feature, not a bug — it rewards the players who put in the work to understand the system. Exposing full pool analytics publicly would flatten the skill curve and remove the edge that engaged players earn.

That said, internal monitoring and optional power-user dashboards (gated behind engagement or deity pass) could serve operational and retention goals without undermining the design intent.

**Potential Internal/Gated Metrics:**
- Current/next/future pool sizes in ETH (internal monitoring)
- BURNIE supply metrics (total supply, recent burn/mint rates)
- Player's personal activity score and ROI tier (already partially visible)
- Historical jackpot distribution data (post-hoc, not predictive)

---

## Appendix: Key Economic Parameters

| Parameter | Value | Impact |
|-----------|-------|--------|
| Ticket price range | 0.01 - 0.24 ETH | Entry cost scaling |
| Whale bundle price | 2.4 / 4 ETH | Catch-up mechanism cost |
| Deity pass base | 24 ETH + T(n) | Whale commitment cost |
| Deity pass cap | 32 total | Concentration limit |
| Coinflip win rate | 50% (VRF) | Fair game guarantee |
| Coinflip reward range | 50-150% (normal 78-115%) | Bonus on top of stake |
| Coinflip reward mean | 96.85% | Slight negative EV |
| Recycling bonus (base) | 1% (cap 1000 BURNIE) | Auto-rebuy incentive |
| Recycling bonus (afKing) | 1.6% + deity bonus | Deity pass value driver |
| Lootbox EV range | 80% - 135% | Activity score reward |
| Lootbox EV cap | 10 ETH/level/account | Extraction limit |
| Degenerette ROI range | 90% - 99.9% | Activity score reward |
| Degenerette ETH cap | 10% of pool per win | Solvency guarantee |
| Quest daily reward | 300 BURNIE | Engagement incentive |
| Affiliate ETH rate | 20-25% of mints | Referral incentive |
| BAF jackpot | 10-25% of future pool | x10 level prize |
| Decimator jackpot | 10% of future pool | x5 level prize |
| Daily jackpot | 6-14% of current pool | Daily engagement driver |
| BOOTSTRAP_PRIZE_POOL | 50 ETH | Minimum pool guarantee |
| stETH yield (assumed) | 3-5% APY | Sustainable prize funding |
| BURNIE vault allowance | 2M initial | Virtual reserve |
| Jackpot eligibility | 8+ ETH mint streak | Engagement gate |
| DGNRS boon threshold | 0.05% supply | Governance minimum |

---

*This analysis is based on source-code review of all contract files in the repository. Economic projections are theoretical and depend on actual player behavior, market conditions, and token dynamics that cannot be precisely predicted pre-launch. All severity ratings assume rational actors and standard market conditions.*
