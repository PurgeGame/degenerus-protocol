# Requirements: Degenerus Off-Chain Simulation Engine

**Defined:** 2026-03-05
**Core Value:** Faithfully replicate all Degenerus Protocol game mechanics in a standalone TypeScript engine, with player profiles from the game theory paper and presentation-quality interactive visualization.

## v1.0 Requirements

Requirements for initial release. Each maps to roadmap phases.

### Simulation Engine

- [x] **ENG-01**: Simulation engine runs as pure TypeScript with no Hardhat/ethers dependency
- [x] **ENG-02**: Simulation is deterministic — same seed produces identical results
- [x] **ENG-03**: User can configure player count, level count, random seed, and archetype distribution
- [x] **ENG-04**: Simulation advances day-by-day through the full game lifecycle (level 0 through game-over or configured stop)
- [x] **ENG-05**: Engine tracks per-player state (ETH balance, BURNIE balance, FLIP stake, activity score, quest streak, ticket holdings, pass ownership, claimable amounts, affiliate code/referrer)
- [x] **ENG-06**: Engine tracks global state (current level, 4 prize pools [next/current/future/claimable], BURNIE supply, vault ETH+stETH balance, DGNRS reserves, deity pass registry)
- [x] **ENG-07**: Engine emits structured events for every state change (purchases, jackpot wins, claims, level advances, quest completions, coinflip results)
- [x] **ENG-08**: Simulation can run in browser (no Node-only APIs)

### Game Mechanics — Core

- [ ] **CORE-01**: Ticket purchasing — cost formula `costWei = (priceWei * qty) / (4 * TICKET_SCALE)` where TICKET_SCALE=100, minimum buyin 0.0025 ETH, BURNIE ticket cost `qty * 250 BURNIE` (1000 BURNIE = 1 full ticket = 4 entries)
- [ ] **CORE-02**: Price escalation matching PriceLookupLib — levels 0-4: 0.01 ETH, 5-9: 0.02, 10-29: 0.04, 30-59: 0.08, 60-89: 0.12, 90-99: 0.16, x00 (century): 0.24, then x01-x29: 0.04, x30-x59: 0.08, x60-x89: 0.12, x90-x99: 0.16 repeating
- [ ] **CORE-03**: Prize pool ETH routing — ticket purchases: 90% nextPool / 10% futurePool. Lootbox (non-presale): 10% nextPool / 90% futurePool. Presale lootbox: 40% next / 40% future / 20% vault. Pool consolidation at level transition: nextPool → currentPool (100%). Future pool drawdown each jackpot entry: 15% of futurePool → nextPool (skipped on x00 levels)
- [ ] **CORE-04**: Daily jackpot system — 5 jackpot days per level. Days 1-4: random 6-14% of currentPrizePool. Day 5: 100% remaining. 4-bucket trait system with base winner counts (25/15/8/1 scaled by pool size up to 321 max). Days 1-4 share split: equal 20/20/20/20 per bucket. Day 5: 60/13.33/13.33/13.34 (solo bucket gets 60%). Winner selection: uniform random by ticket index (proportional to count)
- [ ] **CORE-05**: Trait-based jackpot selection — 4 quadrants, 8 symbols × 8 colors = 256 traits. Jackpot-phase traits: symbol-0 biased for Q0-Q2 (random color), Q3 fully random. Hero wager override: symbol with highest daily wager wins its quadrant. Purchase-phase traits: fully random 6-bit per quadrant
- [ ] **CORE-06**: Purchase-phase daily events — BURNIE coin jackpot each purchase day (0.5% of prior prize pool target in BURNIE). ETH bonus every 3rd purchase day: 1% of futurePool (75% to lootbox ticket budget, 25% direct ETH jackpot). 1/3 chance: awards to future ticket holders (levels +2 to +50); 2/3 chance: awards to trait-based winners
- [ ] **CORE-07**: Level advancement — purchase phase ends when nextPrizePool >= previous level's prize pool. Compressed jackpot: if target met in ≤2 days, counter advances 2 per physical day (5 logical days in 3 physical). VRF simulated as deterministic PRNG
- [ ] **CORE-08**: Quest system — 2 concurrent slots per day. Slot 0: always MINT_ETH (1× current price). Slot 1: weighted-random from 8 types (MINT_BURNIE 10×, FLIP 4×, DECIMATOR 4×, LOOTBOX 3×, others 1×). Streak increments on FIRST slot completion (not both). Shields absorb missed days. Slot 0 must complete before slot 1 counts. Rewards: 100 BURNIE flip credit (slot 0), 200 BURNIE flip credit (slot 1)
- [ ] **CORE-09**: Activity score — 5 components: (1) mint streak min(streak,50)×1% = max 50%, (2) mint count (mintCount/currLevel)×25×1% = max 25%, (3) quest streak min(q,100)×1% = max 100%, (4) affiliate bonus (1pt/ETH over last 5 levels, cap 50) = max 50%, (5) whale bundle +10% (10-lvl) or +40% (100-lvl) or deity +80%. Max: 265% non-deity, 305% deity. Pass holders get floor: streak=50, mintCount=25

### Game Mechanics — Extended

- [ ] **CORE-10**: Lootbox EV — piecewise linear: score 0-60%: EV 80%→100%. Score 60-255%: EV 100%→135%. Score ≥255%: EV capped at 135%. Per-account benefit cap: 10 ETH/level. BURNIE lootboxes convert at 80% rate to ETH-equivalent, NOT affected by EV multiplier
- [ ] **CORE-11**: BURNIE/FLIP system — creditFlip() = coinflip stake (queued for next flip day, NOT direct tokens). creditCoin() = direct BURNIE mint. Coinflip: 50/50 win/loss. Win payout: 5% chance 1.5× stake, 90% chance 1.78×-2.15× stake, 5% chance 2.5× stake (mean ~1.97×). Loss: forfeit entire stake. Bounty system: increases 1000 BURNIE each window, armed on new records
- [ ] **CORE-12**: Degenerette — single bet mode: custom 4-quadrant ticket (8 attributes), match 0-8 against random result. 3 currencies: ETH (min 0.005), BURNIE (min 100), WWXRP (min 1). Base payouts: 0/0/1.9/4.75/15/42.5/195/1000/100000× at 100% ROI. Actual ROI from activity score: 90% (score 0) → 95% (75%) → 99.5% (255%) → 99.9% (305%). ETH wins: 25% paid as ETH (capped 10% futurePool), 75% converted to lootbox rewards. Hero quadrant: both-match boost (varies), miss penalty 95%. EV normalization for trait rarity. Consolation: 1 WWXRP on all-loss qualifying bets
- [ ] **CORE-13**: Affiliate system — 3-tier referral (affiliate → upline1 at 20% → upline2 at 4%), fresh ETH rates (25% lvl 1-3, 20% lvl 4+), recycled ETH rate (5%), rakeback (0-25% returned to referred player)
- [ ] **CORE-18**: Affiliate payout modes — Coinflip (default FLIP credit), Degenerette (pending credit bucket), SplitCoinflipCoin (50% direct BURNIE via creditCoin, 50% discarded)
- [ ] **CORE-19**: Affiliate multi-tier weighted roll — when uplines exist, roll weighted random winner who receives combined total (EV-preserved per recipient)
- [ ] **CORE-20**: Affiliate lootbox taper — activity score 15000-25500 BPS linearly tapers payout from 100% to 50%, score ≥25500 floors at 50%. Leaderboard tracking always uses full untapered amount
- [ ] **CORE-21**: Affiliate quest reward bonus added on top of base affiliate share
- [ ] **CORE-22**: Affiliate leaderboard — per-level top affiliate tracking, bonus points (1pt per 1 ETH over last 5 levels, capped at 50)
- [ ] **CORE-23**: Affiliate referral locking — first-come permanent, invalid codes default to VAULT, presale mutability window
- [ ] **CORE-14**: Pull-pattern ETH claims — claimableWinnings uses 1 wei sentinel (set to 1 not 0 after claim for SSTORE gas optimization). claimablePool decremented before transfer (CEI). Two claim modes: ETH-first (players) and stETH-first (VAULT/DGNRS only)
- [ ] **CORE-15**: Game-over — triggers: 912-day idle at level 0, or 365-day inactivity at level 1+. Requires VRF (3-day fallback to historical word). Terminal distribution: 10% to Decimator (refunds return to pool), then remaining to next-level ticketholders. Unsold remainder → 50/50 VAULT/DGNRS. Post-game-over 30-day sweep: remaining funds above claimablePool → 50/50 VAULT/DGNRS
- [ ] **CORE-16**: afKing auto-rebuy — bonus tickets ON TOP of base: standard 130% bonus (total 2.30× base), afKing 145% bonus (total 2.45× base). Target level: currentLevel + random(1-4). Take-profit reservation before rebuy
- [ ] **CORE-17**: Future ticket awards — 95% chance: near-future k∈[0,5] (uniform over 6 values). 5% chance: far-future k∈[5,50] (uniform over 46 values). Floor-clamped to currentLevel
- [ ] **CORE-24**: Carryover jackpot (jackpot days 2-4) — 1% of futurePool distributed to future-level ticket holders (randomly selected level +1 to +5). 50% of carryover goes to lootbox tickets. Day 1: replaced by early-bird lootbox jackpot (3% of futurePool → free tickets for 100 random winners at levels +0 to +4)
- [ ] **CORE-25**: BURNIE coin jackpot (Phase 2 of daily jackpot) — 0.5% of prior level's prize pool in BURNIE to trait winners. 25% to far-future holders (+5 to +99), 75% to near-future trait winners
- [ ] **CORE-26**: Century level (x00) special mechanics — future pool drawdown skipped (no 15% skim). VRF-driven keep roll determines how much futurePool flows to currentPool (5 dice rolls, averaging 50% transfer). Rare dump: 1-in-1e15 chance on non-x00 levels → 90% of futurePool → currentPool
- [ ] **CORE-27**: Lootbox boost system — 5%/15%/25% BPS ticket quantity boost from deity boons, capped at LOOTBOX_BOOST_MAX_VALUE = 10 ETH equivalent
- [ ] **CORE-28**: DGNRS final-day reward — 1% of DGNRS reward pool awarded to solo-bucket winner on jackpot day 5
- [x] **CORE-29**: Deity pass virtual jackpot entries — floor(2% of bucket ticket count), minimum 2 entries, applied in trait bucket matching deity's symbol. Gives perpetual jackpot exposure without purchasing tickets
- [ ] **CORE-30**: Top affiliate reward — awarded at end of each level's jackpot phase to the affiliate with highest leaderboard score for that level

### Game Mechanics — Passes

- [x] **PASS-01**: Whale bundle — 2.4 ETH (levels 0-3), 4 ETH (level 4+, with boon discounts: 10%/25%/50% off). Qty 1-100. Covers 100 levels: bonus tier (passLevel through level 10): 40×qty tickets/level, standard tier (11+): 2×qty tickets/level. Sets bundle type to 3 (100-level)
- [x] **PASS-02**: Lazy pass — 0.24 ETH flat (levels 0-2, excess over actual ticket cost → bonus tickets). Sum-of-10-level-prices (level 3+). Purchase windows: any level 0-2, then only x9 levels (9,19,29...) or with valid boon. Provides 4 tickets/level for 10 consecutive levels. Blocked if player holds deity pass or has 7+ levels remaining on freeze
- [x] **PASS-03**: Deity pass — T(n) triangular pricing: 24 + k×(k+1)/2 ETH where k = passes already sold (0-indexed). 32-pass cap (one per symbol). Boon discounts: 10%/25%/50% off by tier. One per buyer. Transfer cost: 5 ETH worth of BURNIE burned at current price (resets sender's mint stats and quest streak)
- [x] **PASS-04**: Deity pass bonuses — +80% activity score (replaces whale bundle bonus). Virtual jackpot entries: floor(2% of matching-symbol trait bucket count), min 2. Perpetual auto-entries each level
- [x] **PASS-05**: Deity boon issuance — 3 slots/day per deity (bitmask enforced, not 5 as stale NatSpec says). One recipient per boon per day. Boon types: coinflip odds boost (500/1000/2500 BPS), lootbox ETH boost (5%/15%/25%), purchase boost, decimator boost, pass discounts, activity stat boosts. Types deterministic from deity+day+slot entropy. Short expiry (2-4 game days)
- [x] **PASS-06**: Deity pass game-over refund — flat 20 ETH/pass, levels 0-9 only, budget-capped (totalFunds - claimablePool), purchase-order priority (FIFO via deityPassOwners array)
- [x] **PASS-07**: Pass capital injection splits — Whale/Deity: 30% next / 70% future (level 0), 5% next / 95% future (level 1+). Lazy: 90% next / 10% future (all levels). All pass types also send vault share during presale where applicable

### Game Mechanics — Vault & Yield

- [x] **VAULT-01**: stETH yield simulation — configurable daily BPS rate (production: implicit Lido rebase; sim uses configurable rate, default 10 BPS/day ≈ 3.65% APY). Yield detected as surplus: totalBalance - (nextPool + currentPool + futurePool + claimablePool)
- [x] **VAULT-02**: Yield distribution split — 2300 BPS (23%) to VAULT claimable, 2300 BPS (23%) to DGNRS claimable, 4600 BPS (46%) to futurePool, 800 BPS (~8%) unextracted buffer
- [x] **VAULT-03**: DegenerusVault share math — two share tokens (DGVB for BURNIE, DGVE for ETH+stETH). Floor-division on burn: `claimValue = (reserve * shares) / totalSupply`. Ceiling-division on reverse queries. Initial supply: 1 trillion shares pre-minted. Full-supply burn triggers 1T-share refill
- [x] **VAULT-04**: DGNRS token — no per-holder yield accrual. Pure burn-to-extract proportional backing: ETH+stETH (ETH first, stETH remainder) + BURNIE + WWXRP. Yield reaches DGNRS via game's 23% claimable credit → DGNRS claims → reserves grow → holders burn to extract
- [x] **VAULT-05**: Vault/DGNRS perpetual entries — 16 tickets/level each (not 4) at level purchaseLevel+99. Both have deity-pass-equivalent activity score (+80% via deityPassCount=1 in constructor)

### Player Archetypes

- [ ] **PLAY-01**: Degen archetype — entertainment-seeking, irregular purchases, Degenerette spins, lootbox opens regardless of activity score, day-5 ticket buying
- [ ] **PLAY-02**: EV Maximizer archetype — disciplined daily engagement, activity score maximization, reinvestment-focused, lootbox timing optimization
- [ ] **PLAY-03**: Whale archetype — early deity/whale pass acquisition, large coinflip stakes, deity boon issuance, BAF leaderboard play
- [ ] **PLAY-04**: Hybrid archetype — spectrum from near-degen to near-grinder, mostly near-breakeven, occasional leaks and sub-optimal decisions
- [ ] **PLAY-05**: Affiliate trait composable with any archetype — referral network building, day-5 activation pushes, rakeback balancing
- [ ] **PLAY-06**: Budget constraints per Section 3.6 — increasing capital requirements, bankroll ruin risk, streak maintenance cost pressure
- [ ] **PLAY-07**: Player decision-making follows within-level timing advantage (early-level purchases more valuable)
- [ ] **PLAY-08**: Each archetype has configurable parameters (aggression, budget, risk tolerance) with sensible defaults from the paper

### Interactive Visualization

- [x] **VIZ-01**: React/D3 dashboard renders simulation results with responsive layout
- [x] **VIZ-02**: Player wealth chart — ETH balance + claimable + estimated future ticket value over time, per player and aggregate by archetype
- [x] **VIZ-03**: Prize pool chart — nextPool, currentPool, futurePool, claimablePool over time
- [x] **VIZ-04**: BURNIE economics chart — supply, implied price (ETH-equivalent per BURNIE via ticket price ratio), coinflip volume
- [x] **VIZ-05**: Activity score distribution — histogram of player scores over time, archetype-colored
- [ ] **VIZ-06**: Per-player drill-down — click player to see their strategy decisions, outcomes, streak history, pass ownership
- [x] **VIZ-07**: Configurable simulation parameters in-browser — player count, level count, seed, archetype mix sliders
- [x] **VIZ-08**: Re-run simulation live in browser with parameter changes
- [ ] **VIZ-09**: Scenario comparison — run two configs side-by-side and overlay charts
- [x] **VIZ-10**: Embeddable in website alongside the game theory paper (standalone React component or iframe-ready)
- [ ] **VIZ-11**: Export charts as PNG/SVG for paper figures

### Validation

- [ ] **VAL-01**: Formula test suite (Vitest) comparing sim engine calculations to known contract outputs for specific inputs
- [ ] **VAL-02**: Price escalation tests — sim PriceLookup matches PriceLookupLib.sol for all 100-level cycle positions
- [ ] **VAL-03**: BPS split tests — sim fee/pool splits match contract BPS constants for all payment paths (ticket, lootbox, presale lootbox, pass splits, yield distribution)
- [ ] **VAL-04**: Activity score tests — sim score calculation matches contract for representative player states (non-deity, deity, whale, lazy pass, bare player)
- [ ] **VAL-05**: Lootbox EV tests — sim EV multiplier matches contract calculation at all activity score breakpoints (0%, 60%, 150%, 255%, 305%)
- [ ] **VAL-06**: Contract comparison tests — Hardhat tests run same scenario through sim engine and real contracts, compare final state
- [ ] **VAL-07**: Pass pricing tests — whale (levels 0-3 vs 4+), lazy (0-2 flat vs x9 sum-of-10), deity (T(n) for n=0..31) all match contract
- [ ] **VAL-08**: Vault share math tests — deposit/withdraw/yield calculations match DegenerusVault.sol
- [ ] **VAL-09**: Degenerette payout tests — base payouts, ROI curve, hero quadrant boost/penalty, EV normalization match DegeneretteModule
- [ ] **VAL-10**: Coinflip payout tests — win distribution (5%/90%/5% tiers), mean payout ≈1.97×, match BurnieCoinflip.sol

## v2 Requirements

Deferred to future release.

### Advanced Visualization

- **VIZ2-01**: Animated simulation playback (watch the game unfold tick-by-tick)
- **VIZ2-02**: Network graph showing affiliate referral tree
- **VIZ2-03**: Heatmap of player activity across levels and days

### Advanced Modeling

- **ADV-01**: Monte Carlo mode — run N simulations with varied seeds, show distribution of outcomes
- **ADV-02**: Sensitivity analysis — sweep one parameter, show impact on key metrics
- **ADV-03**: Nash equilibrium finder — iteratively optimize player strategies against each other

## Out of Scope

| Feature | Reason |
|---------|--------|
| On-chain execution | Pure math sim; contract comparison tests use Hardhat separately |
| Real VRF integration | Simulated PRNG is sufficient for modeling |
| Frontend for non-technical users | Target audience is paper readers and presentation viewers |
| Mobile-specific optimization | Desktop-first dashboard |
| Deployment pipeline | Simulator is a dev/presentation tool |
| Gas simulation | Not relevant for off-chain engine |
| WWXRP token full economics | Only needed for Degenerette consolation; not a core simulation output |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| ENG-01 | Phase 36 | Complete |
| ENG-02 | Phase 36 | Complete |
| ENG-03 | Phase 36 | Complete |
| ENG-04 | Phase 36 | Complete |
| ENG-05 | Phase 36 | Complete |
| ENG-06 | Phase 36 | Complete |
| ENG-07 | Phase 36 | Complete |
| ENG-08 | Phase 36 | Complete |
| CORE-01 | Phase 37 | Pending |
| CORE-02 | Phase 37 | Pending |
| CORE-03 | Phase 37 | Pending |
| CORE-04 | Phase 37 | Pending |
| CORE-05 | Phase 37 | Pending |
| CORE-06 | Phase 37 | Pending |
| CORE-07 | Phase 37 | Pending |
| CORE-08 | Phase 37 | Pending |
| CORE-09 | Phase 37 | Pending |
| CORE-10 | Phase 38 | Pending |
| CORE-11 | Phase 38 | Pending |
| CORE-12 | Phase 38 | Pending |
| CORE-13 | Phase 38 | Pending |
| CORE-14 | Phase 38 | Pending |
| CORE-15 | Phase 38 | Pending |
| CORE-16 | Phase 38 | Pending |
| CORE-17 | Phase 38 | Pending |
| CORE-18 | Phase 38 | Pending |
| CORE-19 | Phase 38 | Pending |
| CORE-20 | Phase 38 | Pending |
| CORE-21 | Phase 38 | Pending |
| CORE-22 | Phase 38 | Pending |
| CORE-23 | Phase 38 | Pending |
| CORE-24 | Phase 37 | Pending |
| CORE-25 | Phase 37 | Pending |
| CORE-26 | Phase 37 | Pending |
| CORE-27 | Phase 38 | Pending |
| CORE-28 | Phase 38 | Pending |
| CORE-29 | Phase 39 | Complete |
| CORE-30 | Phase 38 | Pending |
| PASS-01 | Phase 39 | Complete |
| PASS-02 | Phase 39 | Complete |
| PASS-03 | Phase 39 | Complete |
| PASS-04 | Phase 39 | Complete |
| PASS-05 | Phase 39 | Complete |
| PASS-06 | Phase 39 | Complete |
| PASS-07 | Phase 39 | Complete |
| VAULT-01 | Phase 39 | Complete |
| VAULT-02 | Phase 39 | Complete |
| VAULT-03 | Phase 39 | Complete |
| VAULT-04 | Phase 39 | Complete |
| VAULT-05 | Phase 39 | Complete |
| PLAY-01 | Phase 40 | Pending |
| PLAY-02 | Phase 40 | Pending |
| PLAY-03 | Phase 40 | Pending |
| PLAY-04 | Phase 40 | Pending |
| PLAY-05 | Phase 40 | Pending |
| PLAY-06 | Phase 40 | Pending |
| PLAY-07 | Phase 40 | Pending |
| PLAY-08 | Phase 40 | Pending |
| VIZ-01 | Phase 41 | Complete |
| VIZ-02 | Phase 41 | Complete |
| VIZ-03 | Phase 41 | Complete |
| VIZ-04 | Phase 41 | Complete |
| VIZ-05 | Phase 41 | Complete |
| VIZ-06 | Phase 41 | Pending |
| VIZ-07 | Phase 41 | Complete |
| VIZ-08 | Phase 41 | Complete |
| VIZ-09 | Phase 41 | Pending |
| VIZ-10 | Phase 41 | Complete |
| VIZ-11 | Phase 41 | Pending |
| VAL-01 | Phase 42 | Pending |
| VAL-02 | Phase 42 | Pending |
| VAL-03 | Phase 42 | Pending |
| VAL-04 | Phase 42 | Pending |
| VAL-05 | Phase 42 | Pending |
| VAL-06 | Phase 42 | Pending |
| VAL-07 | Phase 42 | Pending |
| VAL-08 | Phase 42 | Pending |
| VAL-09 | Phase 42 | Pending |
| VAL-10 | Phase 42 | Pending |

**Coverage:**
- v1 requirements: 63 total
- Mapped to phases: 63
- Unmapped: 0

---
*Requirements defined: 2026-03-05*
*Last updated: 2026-03-05 after contract audit verification*
