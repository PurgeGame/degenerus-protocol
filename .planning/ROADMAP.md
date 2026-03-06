# Roadmap: Degenerus Protocol

## Milestones

- ✅ **v1.0 Audit** — Phases 1-7 (shipped 2026-03-04)
- ✅ **v2.0 Adversarial Audit** — Phases 8-13 (shipped 2026-03-05)
- ✅ **v3.0 Adversarial Hardening** — Phases 14-18 (shipped 2026-03-05)
- ✅ **v4.0 Pre-C4A Adversarial Stress Test** — Phases 19-29 (shipped 2026-03-05)
- ✅ **v5.0 Novel Zero-Day Attack Surface Audit** — Phases 30-35 (shipped 2026-03-05)
- 🚧 **v1.0 Off-Chain Simulation Engine** — Phases 36-42 (in progress)

## Phases

<details>
<summary>✅ v1.0 Audit (Phases 1-7) — SHIPPED 2026-03-04</summary>

- [x] Phase 1: Storage Foundation Verification (4/4 plans) — completed 2026-02-28
- [x] Phase 2: Core State Machine and VRF Lifecycle (6/6 plans) — completed 2026-03-01
- [x] Phase 3a: Core ETH Flow Modules (7/7 plans) — completed 2026-03-01
- [x] Phase 3b: VRF-Dependent Modules (6/6 plans) — completed 2026-03-01
- [x] Phase 3c: Supporting Mechanics Modules (6/6 plans) — completed 2026-03-01
- [~] Phase 4: ETH and Token Accounting Integrity (1/9 plans) — INCOMPLETE (closed by Phase 8 in v2.0)
- [x] Phase 5: Economic Attack Surface (7/7 plans) — completed 2026-03-04
- [x] Phase 6: Access Control and Privilege Model (7/7 plans) — completed 2026-03-04
- [x] Phase 7: Cross-Contract Integration Synthesis (5/5 plans) — completed 2026-03-04

See: `.planning/milestones/v1.0-ROADMAP.md` for full phase details and findings.

</details>

<details>
<summary>✅ v2.0 Adversarial Audit (Phases 8-13) — SHIPPED 2026-03-05</summary>

- [x] Phase 8: ETH Accounting Invariant and CEI Verification (5/5 plans) — completed 2026-03-04
- [x] Phase 9: advanceGame() Gas Analysis and Sybil Bloat (4/4 plans) — completed 2026-03-04
- [x] Phase 10: Admin Power, VRF Griefing, and Assembly Safety (4/4 plans) — completed 2026-03-04
- [x] Phase 11: Token Security, Economic Attacks, Vault and Timing (5/5 plans) — completed 2026-03-04
- [x] Phase 12: Cross-Function Reentrancy Synthesis and Unchecked Blocks (3/3 plans) — completed 2026-03-04
- [x] Phase 13: Final Synthesis Report (4/4 plans) — completed 2026-03-05

**Results:** 0 Critical, 0 High, 0 Medium, 1 Low, 8 QA/Info. All 48 requirements satisfied.

See: `.planning/milestones/v2.0-ROADMAP.md` for full phase details.

</details>

<details>
<summary>✅ v3.0 Adversarial Hardening (Phases 14-18) — SHIPPED 2026-03-05</summary>

- [x] Phase 14: Foundry Infrastructure and Compiler Alignment (4/4 plans) — completed 2026-03-05
- [x] Phase 15: Core Handlers and ETH Solvency Invariant (3/3 plans) — completed 2026-03-05
- [x] Phase 16: Remaining Invariant Harnesses (4/4 plans) — completed 2026-03-05
- [x] Phase 17: Adversarial Sessions and Formal Verification (5/5 plans) — completed 2026-03-05
- [x] Phase 18: Consolidated Report and Coverage Metrics (3/3 plans) — completed 2026-03-05

**Results:** 0 Critical, 0 High, 0 Medium. 48 invariant tests, 53 adversarial vectors, 10 symbolic properties. 18/18 requirements satisfied.

See: `.planning/milestones/v3.0-ROADMAP.md` for full phase details.

</details>

<details>
<summary>✅ v4.0 Pre-C4A Adversarial Stress Test (Phases 19-29) — SHIPPED 2026-03-05</summary>

- [x] Phase 19: Nation-State Attacker (1/1 plan) — completed 2026-03-05
- [x] Phase 20: Coercion Attacker (1/1 plan) — completed 2026-03-05
- [x] Phase 21: Evil Genius Hacker (1/1 plan) — completed 2026-03-05
- [x] Phase 22: Sybil Whale Economist (1/1 plan) — completed 2026-03-05
- [x] Phase 23: Degenerate Fuzzer (1/1 plan) — completed 2026-03-05
- [x] Phase 24: Formal Methods Analyst (1/1 plan) — completed 2026-03-05
- [x] Phase 25: Dependency & Integration Attacker (1/1 plan) — completed 2026-03-05
- [x] Phase 26: Gas Griefing Specialist (1/1 plan) — completed 2026-03-05
- [x] Phase 27: White Hat Completionist (1/1 plan) — completed 2026-03-05
- [x] Phase 28: Game Theory Attacker (1/1 plan) — completed 2026-03-05
- [x] Phase 29: Synthesis & Contradiction Report (1/1 summary) — completed 2026-03-05

**Results:** 0 Critical, 0 High, 0 Medium, 5 Low, 30 QA/Info. 10/10 agents unanimous. Protocol assessed LOW RISK. C4A-ready.

See: `.planning/milestones/v4.0-ROADMAP.md` for full phase details.

</details>

<details>
<summary>✅ v5.0 Novel Zero-Day Attack Surface Audit (Phases 30-35) — SHIPPED 2026-03-05</summary>

- [x] Phase 30: Tooling Setup and Static Analysis (3/3 plans) — completed 2026-03-05
- [x] Phase 31: Cross-Contract Composition Analysis (3/3 plans) — completed 2026-03-05
- [x] Phase 32: Precision and Rounding Analysis (3/3 plans) — completed 2026-03-05
- [x] Phase 33: Temporal, Lifecycle, and EVM-Level Analysis (3/3 plans) — completed 2026-03-05
- [x] Phase 34: Economic Composition and Auditor Re-examination (3/3 plans) — completed 2026-03-05
- [x] Phase 35: Halmos Verification and Multi-Tool Synthesis (3/3 plans) — completed 2026-03-05

**Results:** 0 Critical, 0 High, 0 Medium, 2 QA/Info. 36/36 requirements satisfied. Protocol remains LOW RISK.

See: `.planning/milestones/v5.0-ROADMAP.md` for full phase details.

</details>

### v1.0 Off-Chain Simulation Engine (In Progress)

**Milestone Goal:** Build a presentation-quality TypeScript simulation engine with full logic parity to Degenerus Protocol contracts, player archetypes from the game theory paper, and interactive React/D3 visualization for the website.

- [x] **Phase 36: Engine Foundation** - Project scaffolding, deterministic PRNG, state model, event system, browser-compatible engine shell (completed 2026-03-05)
- [x] **Phase 37: Core Game Loop** - Ticket purchasing, price escalation, prize pool splits, jackpots (4-bucket traits, carryover, BURNIE jackpot), century-level mechanics, level advancement, quest streaks, activity scores (completed 2026-03-05)
- [x] **Phase 38: Extended Mechanics** - Lootboxes (boost system), BURNIE/FLIP economics (creditFlip vs creditCoin), Degenerette (match-based, 3 currencies), full affiliate system (3-tier, 3 payout modes, taper, leaderboard, top reward), ETH claims, game-over, afKing, future tickets, DGNRS day-5 reward (completed 2026-03-05)
- [x] **Phase 39: Passes and Vault** - Whale/lazy/deity pass purchasing, deity virtual jackpot entries, pass bonuses, deity boons, game-over refunds, stETH yield, vault share math (DGVB/DGVE), DGNRS burn-to-extract (completed 2026-03-05)
- [x] **Phase 40: Player Archetypes** - Degen, EV Maximizer, Whale, Hybrid behavioral profiles with Affiliate trait, budget constraints, decision-making logic (completed 2026-03-05)
- [ ] **Phase 41: Interactive Visualization** - React/D3 dashboard with wealth/pool/BURNIE/activity charts, drill-downs, parameter controls, scenario comparison, export
- [ ] **Phase 42: Validation and Contract Parity** - Vitest formula tests, price/BPS/activity/EV/pass/vault/Degenerette/coinflip comparison suites, Hardhat cross-validation

## Phase Details

### Phase 36: Engine Foundation
**Goal**: Developers can instantiate and run a minimal simulation that ticks through days with deterministic, reproducible results
**Depends on**: Nothing (first phase of milestone)
**Requirements**: ENG-01, ENG-02, ENG-03, ENG-04, ENG-05, ENG-06, ENG-07, ENG-08
**Success Criteria** (what must be TRUE):
  1. Running the engine with the same seed twice produces byte-identical output
  2. Engine tracks per-player state (balances, scores, holdings) and global state (level, pools, supply) that update each simulated day
  3. Structured events are emitted for state changes and can be collected by a consumer
  4. Engine runs in a browser environment (no Node-only APIs like fs, crypto, or child_process)
  5. User can configure player count, level count, seed, and archetype distribution before running
**Plans:** 3/3 plans complete
Plans:
- [x] 36-01-PLAN.md — Project scaffolding, deterministic PRNG, and core type contracts
- [x] 36-02-PLAN.md — Player/global state factories and event collector implementation
- [x] 36-03-PLAN.md — Simulation engine shell with day-tick loop and public API

### Phase 37: Core Game Loop
**Goal**: Simulation faithfully replicates the core Degenerus game loop from ticket purchase through jackpot drawing and level advancement
**Depends on**: Phase 36
**Requirements**: CORE-01, CORE-02, CORE-03, CORE-04, CORE-05, CORE-06, CORE-07, CORE-08, CORE-09, CORE-24, CORE-25, CORE-26
**Success Criteria** (what must be TRUE):
  1. Tickets can be purchased with costs matching the contract formula (costWei = priceWei * qty / 400) and prices follow PriceLookupLib escalation
  2. Prize pool splits (ticket 90/10, lootbox 10/90, presale 40/40/20) and pool consolidation with 15% futurePool drawdown match contract constants
  3. Daily jackpots use 4-bucket trait system with correct winner counts (25/15/8/1 scaled), day 1-4 random 6-14% payout, day 5 100% with 60/13/13/13 split
  4. Carryover jackpot (1% futurePool days 2-4), BURNIE coin jackpot (0.5% prior pool), and century-level mechanics (VRF keep roll, no 15% skim) operational
  5. Activity scores combine all 5 components (quest streak, mint count, quest streak, pass bonuses, affiliate bonus) matching contract calculation
**Plans:** 5/5 plans complete
Plans:
- [ ] 37-01-PLAN.md — Price lookup, ticket purchase, and pool routing modules
- [ ] 37-02-PLAN.md — Quest system and activity score modules
- [ ] 37-03-PLAN.md — Trait system and jackpot distribution modules
- [ ] 37-04-PLAN.md — Level advancement and purchase-phase events modules
- [ ] 37-05-PLAN.md — Carryover/BURNIE jackpot, century level, and engine integration

### Phase 38: Extended Mechanics
**Goal**: All secondary game mechanics operate correctly on top of the core loop, completing the full game lifecycle from lootboxes through game-over
**Depends on**: Phase 37
**Requirements**: CORE-10, CORE-11, CORE-12, CORE-13, CORE-14, CORE-15, CORE-16, CORE-17, CORE-18, CORE-19, CORE-20, CORE-21, CORE-22, CORE-23, CORE-27, CORE-28, CORE-30
**Success Criteria** (what must be TRUE):
  1. Lootboxes open with EV multiplier matching contract breakpoints (80% at score 0, 100% at 60%, 135% at 255%, capped). Lootbox boost system (5/15/25% BPS from deity boons, 10 ETH cap)
  2. BURNIE creditFlip (coinflip stake) and creditCoin (direct mint) correctly distinguished. Coinflip: 50/50, wins pay 1.5x-2.5x (mean ~1.97x). Bounty system operational
  3. Degenerette: match-based 4-quadrant betting, 3 currencies, ROI curve from activity score (90%->99.9%), hero quadrant boost/penalty, EV normalization
  4. Full affiliate system: 3-tier referral with fresh/recycled ETH rates, 3 payout modes (coinflip/degenerette/split-coin), weighted multi-tier roll, lootbox taper, quest bonus, leaderboard, rakeback, referral locking. Top affiliate reward at level end
  5. Game-over triggers on inactivity timeout (912d/365d), terminal 10% Decimator split, remaining to next-level holders, 30-day sweep. Pull-pattern ETH claims with 1 wei sentinel
  6. afKing auto-rebuy (130% bonus = 2.30x total, 145% afKing = 2.45x total). Future tickets: 95%/5% near/far split. DGNRS final-day 1% reward to solo-bucket winner
**Plans:** 6/6 plans complete
Plans:
- [x] 38-01-PLAN.md — Lootbox EV multiplier, boost system, and BURNIE coinflip mechanics
- [x] 38-02-PLAN.md — Degenerette match-based betting with ROI curve and 3 currencies
- [x] 38-03-PLAN.md — Full affiliate system (3-tier, payout modes, taper, leaderboard)
- [x] 38-04-PLAN.md — ETH claims with 1 wei sentinel and game-over mechanics
- [x] 38-05-PLAN.md — afKing auto-rebuy, future ticket distribution, and DGNRS reward
- [x] 38-06-PLAN.md — Engine integration of all Phase 38 mechanics

### Phase 39: Passes and Vault
**Goal**: All pass types and vault/yield mechanics operate with correct pricing, bonuses, and capital flows
**Depends on**: Phase 37
**Requirements**: PASS-01, PASS-02, PASS-03, PASS-04, PASS-05, PASS-06, PASS-07, VAULT-01, VAULT-02, VAULT-03, VAULT-04, VAULT-05, CORE-29
**Success Criteria** (what must be TRUE):
  1. Whale bundles (2.4/4 ETH pricing with boon discounts), lazy passes (0.24 ETH flat or sum-of-10, x9 windows), and deity passes (24 + T(n) triangular, 32-cap, 5 ETH BURNIE transfer cost) all price correctly
  2. Deity pass holders receive +80% activity score bonus, perpetual 2% bucket jackpot entries (min 2), 3 boons/day (bitmask), and FIFO game-over refund (20 ETH/pass, levels 0-9 only, budget-capped)
  3. Pass capital injection splits: Whale/Deity 30/70 (lvl 0), 5/95 (lvl 1+). Lazy 90/10 all levels
  4. stETH yield accrues at configurable daily rate and distributes 46/23/23/8 to futurePool, vault, DGNRS, and buffer
  5. Vault share math (two share tokens DGVB/DGVE, floor-division burn, 1T refill) and DGNRS pure burn-to-extract (ETH+stETH+BURNIE+WWXRP) function correctly. 16 tickets/level perpetual entries for both
**Plans:** 3/3 plans complete
Plans:
- [ ] 39-01-PLAN.md — Pass pricing (whale/lazy/deity) and capital injection modules
- [ ] 39-02-PLAN.md — stETH yield, vault share math, and DGNRS burn-to-extract modules
- [ ] 39-03-PLAN.md — Deity bonuses/boons/refund and engine integration

### Phase 40: Player Archetypes
**Goal**: Four distinct player archetypes plus the Affiliate trait drive realistic simulated behavior with configurable parameters and budget constraints
**Depends on**: Phase 38, Phase 39
**Requirements**: PLAY-01, PLAY-02, PLAY-03, PLAY-04, PLAY-05, PLAY-06, PLAY-07, PLAY-08
**Success Criteria** (what must be TRUE):
  1. Degen archetype makes irregular purchases, spins Degenerette, opens lootboxes regardless of score, and buys on day 5 -- visibly different behavior from EV Maximizer who engages daily, maximizes activity score, and times lootbox opens
  2. Whale archetype acquires deity/whale passes early, makes large coinflip stakes, issues boons, and pursues BAF leaderboard -- Hybrid archetype shows spectrum behavior from near-degen to near-grinder
  3. Affiliate trait composes onto any archetype, adding referral network building and day-5 activation pushes with rakeback balancing
  4. Budget constraints create increasing capital pressure, bankroll ruin risk, and streak maintenance cost per Section 3.6
  5. Each archetype exposes configurable parameters (aggression, budget, risk tolerance) with sensible defaults from the game theory paper
**Plans:** 4/4 plans complete
Plans:
- [x] 40-01-PLAN.md — Archetype type contracts and decision engine framework
- [x] 40-02-PLAN.md — Degen and EV Maximizer behavior implementations
- [x] 40-03-PLAN.md — Whale, Hybrid, and Affiliate trait implementations
- [x] 40-04-PLAN.md — Budget constraints and engine integration

### Phase 41: Interactive Visualization
**Goal**: Users can explore simulation results through an interactive React/D3 dashboard with configurable parameters, drill-downs, and exportable charts
**Depends on**: Phase 40
**Requirements**: VIZ-01, VIZ-02, VIZ-03, VIZ-04, VIZ-05, VIZ-06, VIZ-07, VIZ-08, VIZ-09, VIZ-10, VIZ-11
**Success Criteria** (what must be TRUE):
  1. Dashboard renders player wealth (ETH + claimable + future ticket value), prize pools (next/current/future/claimable), BURNIE economics (supply, implied price, coinflip volume), and activity score distribution over time
  2. User can click any player to drill down into their strategy decisions, outcomes, streak history, and pass ownership
  3. User can adjust simulation parameters (player count, level count, seed, archetype mix) in-browser and re-run the simulation live
  4. User can run two configurations side-by-side with overlaid comparison charts
  5. Charts export as PNG/SVG for paper figures, and the dashboard embeds in the website alongside the game theory paper (standalone component or iframe-ready)
**Plans:** 2/3 plans executed
Plans:
- [ ] 41-01-PLAN.md — Vite+React scaffold, simulation hook, parameter controls, dashboard shell
- [ ] 41-02-PLAN.md — Four core D3 charts (wealth, pools, BURNIE, activity scores)
- [ ] 41-03-PLAN.md — Player drill-down, scenario comparison, PNG/SVG export

### Phase 42: Validation and Contract Parity
**Goal**: A comprehensive test suite proves the simulation engine produces results matching the actual Solidity contracts for all critical calculations
**Depends on**: Phase 38, Phase 39
**Requirements**: VAL-01, VAL-02, VAL-03, VAL-04, VAL-05, VAL-06, VAL-07, VAL-08, VAL-09, VAL-10
**Success Criteria** (what must be TRUE):
  1. Vitest formula test suite passes, covering price escalation for all 100 cycle positions, BPS splits for all payment paths, and activity score for representative states
  2. Lootbox EV multiplier matches contract calculation at all activity score breakpoints
  3. Pass pricing (whale, lazy, deity) matches contract for all level ranges and purchase counts
  4. Vault share math (deposit/withdraw/yield) matches DegenerusVault.sol calculations
  5. Degenerette payout tests: base payouts, ROI curve, hero quadrant boost/penalty, EV normalization match DegeneretteModule
  6. Coinflip payout tests: win distribution (5%/90%/5% tiers), mean payout ~1.97x, match BurnieCoinflip.sol
  7. At least one end-to-end scenario runs through both the sim engine and real contracts (via Hardhat), comparing final state to confirm parity
**Plans:** 3 plans
Plans:
- [ ] 42-01-PLAN.md — Core formula validation (price escalation, BPS splits, activity score, lootbox EV)
- [ ] 42-02-PLAN.md — Pass pricing, vault share math, coinflip, and degenerette validation
- [ ] 42-03-PLAN.md — Hardhat cross-validation (sim vs contract end-to-end parity)

## Progress

**Execution Order:**
Phases execute in numeric order: 36 -> 37 -> 38 (parallel with 39) -> 40 -> 41 -> 42

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1-7 | v1.0 Audit | 47/57 | Complete | 2026-03-04 |
| 8-13 | v2.0 Audit | 25/25 | Complete | 2026-03-05 |
| 14-18 | v3.0 Audit | 19/19 | Complete | 2026-03-05 |
| 19-29 | v4.0 Audit | 10/10 | Complete | 2026-03-05 |
| 30-35 | v5.0 Audit | 18/18 | Complete | 2026-03-05 |
| 36. Engine Foundation | 3/3 | Complete    | 2026-03-05 | - |
| 37. Core Game Loop | 5/5 | Complete    | 2026-03-05 | - |
| 38. Extended Mechanics | Sim v1.0 | Complete    | 2026-03-05 | 2026-03-05 |
| 39. Passes and Vault | 3/3 | Complete    | 2026-03-05 | - |
| 40. Player Archetypes | 4/4 | Complete    | 2026-03-05 | - |
| 41. Interactive Visualization | 2/3 | In Progress|  | - |
| 42. Validation and Contract Parity | Sim v1.0 | 0/3 | Not started | - |

**Cumulative:** 37 phases complete (130 plans), 5 phases planned. 5 milestones shipped, 1 in progress.
