# Requirements: Degenerus Protocol — Economic Flow Analysis

**Defined:** 2026-03-12
**Core Value:** Produce documentation accurate enough for game theory agents to generate mathematically exact examples from contract mechanics

## v1.1 Requirements

Requirements for economic flow analysis milestone. Each maps to roadmap phases.

### ETH Inflows

- [ ] **INFLOW-01**: Document every ETH purchase path with exact cost formulas (tickets, lootboxes, whale bundles, lazy pass, deity pass)
- [ ] **INFLOW-02**: Document BURNIE-to-ticket conversion path with virtual ETH formulas
- [ ] **INFLOW-03**: Document degenerette wager inflows with min bets and pool caps
- [ ] **INFLOW-04**: Document presale vs post-presale economic differences

### Pool Architecture

- [ ] **POOL-01**: Map complete pool lifecycle (future → next → current → claimable) with transition triggers
- [ ] **POOL-02**: Document per-purchase-type pool split ratios with exact BPS values
- [ ] **POOL-03**: Document freeze/unfreeze mechanics and pending accumulator behavior during jackpot phase
- [ ] **POOL-04**: Document purchase target calculation and how it drives level advancement

### Jackpot Distribution

- [ ] **JACK-01**: Document 5-day draw mechanics with daily pool slice formulas (6-14% random, 100% day 5)
- [ ] **JACK-02**: Document trait bucket distribution and winner selection per day
- [ ] **JACK-03**: Document carryover ETH mechanics and compressed jackpot conditions
- [ ] **JACK-04**: Document lootbox conversion ratios (50% daily, 75% reward jackpots)
- [ ] **JACK-05**: Document BURNIE jackpot parallel distribution and far-future allocation

### BURNIE Economics

- [ ] **BURN-01**: Document coinflip mechanics (stake, odds, payout range, bounty system, expiry)
- [ ] **BURN-02**: Document BURNIE earning paths (lootbox bonuses, quest rewards, coinflip winnings)
- [ ] **BURN-03**: Document BURNIE burn sinks (decimator eligibility, ticket purchases)
- [ ] **BURN-04**: Document vault reserve mechanics and supply invariants

### DGNRS Tokenomics

- [ ] **DGNR-01**: Document initial supply distribution (creator, whale, affiliate, lootbox, reward, earlybird pools)
- [ ] **DGNR-02**: Document earlybird reward schedule and level-gated distribution
- [ ] **DGNR-03**: Document affiliate DGNRS distribution per level
- [ ] **DGNR-04**: Document soulbound mechanics and transfer restrictions

### Level Progression

- [ ] **LEVL-01**: Document price curve across all level ranges with exact values
- [ ] **LEVL-02**: Document level length (120d) effects on pool accumulation dynamics
- [ ] **LEVL-03**: Document how whale bundle and lazy pass duration economics change across levels
- [ ] **LEVL-04**: Document activity score system and consecutive streak mechanics

### Endgame & Death Clock

- [ ] **END-01**: Document BAF mechanics (every 10 levels, future pool percentages, lootbox conversion)
- [ ] **END-02**: Document decimator mechanics (level triggers, multiplier tiers, BURNIE burn requirements)
- [ ] **END-03**: Document death clock (120d timeout, 365d deploy, distress mode, terminal gameOver)
- [ ] **END-04**: Document final distribution when gameOver triggers

### Deity System

- [ ] **DEIT-01**: Document deity pass pricing curve (base + quadratic escalation)
- [ ] **DEIT-02**: Document all boon types with discount percentages and draw weights
- [ ] **DEIT-03**: Document deity activity score bonuses and jackpot entry multipliers

### Affiliate System

- [ ] **AFFL-01**: Document affiliate referral reward structure and ETH/DGNRS flows
- [ ] **AFFL-02**: Document affiliate tier system and bonus calculations
- [ ] **AFFL-03**: Document top affiliate endgame rewards per level

### stETH & Yield

- [ ] **STETH-01**: Document stETH integration and yield accrual mechanics
- [ ] **STETH-02**: Document how stETH yield affects pool balances and distributions

### Quest Rewards

- [ ] **QRWD-01**: Document quest reward types, BURNIE amounts, and trigger conditions
- [ ] **QRWD-02**: Document quest cooldowns and per-player limits

### Parameter Reference

- [ ] **PARM-01**: Master table of all BPS constants with values, purposes, and contract locations
- [ ] **PARM-02**: Master table of all ETH thresholds, caps, and pricing constants
- [ ] **PARM-03**: Master table of all timing constants (timeouts, windows, durations)

## Future Requirements

None — this is a standalone analysis milestone.

## Out of Scope

| Feature | Reason |
|---------|--------|
| WWXRP mechanics | Booby prize, not core economic model |
| Code changes | Analysis-only milestone |
| Frontend/UI | Contract-level analysis only |
| Gas optimization | Separate concern |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| INFLOW-01 | — | Pending |
| INFLOW-02 | — | Pending |
| INFLOW-03 | — | Pending |
| INFLOW-04 | — | Pending |
| POOL-01 | — | Pending |
| POOL-02 | — | Pending |
| POOL-03 | — | Pending |
| POOL-04 | — | Pending |
| JACK-01 | — | Pending |
| JACK-02 | — | Pending |
| JACK-03 | — | Pending |
| JACK-04 | — | Pending |
| JACK-05 | — | Pending |
| BURN-01 | — | Pending |
| BURN-02 | — | Pending |
| BURN-03 | — | Pending |
| BURN-04 | — | Pending |
| DGNR-01 | — | Pending |
| DGNR-02 | — | Pending |
| DGNR-03 | — | Pending |
| DGNR-04 | — | Pending |
| LEVL-01 | — | Pending |
| LEVL-02 | — | Pending |
| LEVL-03 | — | Pending |
| LEVL-04 | — | Pending |
| END-01 | — | Pending |
| END-02 | — | Pending |
| END-03 | — | Pending |
| END-04 | — | Pending |
| DEIT-01 | — | Pending |
| DEIT-02 | — | Pending |
| DEIT-03 | — | Pending |
| AFFL-01 | — | Pending |
| AFFL-02 | — | Pending |
| AFFL-03 | — | Pending |
| STETH-01 | — | Pending |
| STETH-02 | — | Pending |
| QRWD-01 | — | Pending |
| QRWD-02 | — | Pending |
| PARM-01 | — | Pending |
| PARM-02 | — | Pending |
| PARM-03 | — | Pending |

**Coverage:**
- v1.1 requirements: 42 total
- Mapped to phases: 0
- Unmapped: 42 (pending roadmap creation)

---
*Requirements defined: 2026-03-12*
*Last updated: 2026-03-12 after initial definition*
