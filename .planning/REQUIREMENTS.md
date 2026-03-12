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

### Jackpot & Distribution Mechanics

- [ ] **JACK-01**: Document daily purchase-phase future pool drip (ETH and tickets) with exact formulas and triggers
- [ ] **JACK-02**: Document daily purchase-phase BURNIE jackpots with winner selection and payout formulas
- [ ] **JACK-03**: Document 5-day jackpot-phase draw mechanics with daily pool slice formulas (6-14% random, 100% day 5)
- [ ] **JACK-04**: Document trait bucket distribution and winner selection per jackpot-phase day
- [ ] **JACK-05**: Document carryover ETH mechanics and compressed jackpot conditions
- [ ] **JACK-06**: Document lootbox conversion ratios (50% daily, 75% reward jackpots)
- [ ] **JACK-07**: Document BURNIE jackpot-phase parallel distribution and far-future allocation
- [ ] **JACK-08**: Document BAF mechanics (every 10 levels, future pool percentages, lootbox conversion) at jackpot-phase transition
- [ ] **JACK-09**: Document decimator mechanics (level triggers, multiplier tiers, BURNIE burn requirements) at jackpot-phase transition

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

- [ ] **END-01**: Document death clock (120d timeout, 365d deploy, distress mode, terminal gameOver)
- [ ] **END-02**: Document final distribution when gameOver triggers

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
| INFLOW-01 | Phase 6 | Pending |
| INFLOW-02 | Phase 6 | Pending |
| INFLOW-03 | Phase 6 | Pending |
| INFLOW-04 | Phase 6 | Pending |
| POOL-01 | Phase 6 | Pending |
| POOL-02 | Phase 6 | Pending |
| POOL-03 | Phase 6 | Pending |
| POOL-04 | Phase 6 | Pending |
| JACK-01 | Phase 7 | Pending |
| JACK-02 | Phase 7 | Pending |
| JACK-03 | Phase 7 | Pending |
| JACK-04 | Phase 7 | Pending |
| JACK-05 | Phase 7 | Pending |
| JACK-06 | Phase 7 | Pending |
| JACK-07 | Phase 7 | Pending |
| JACK-08 | Phase 7 | Pending |
| JACK-09 | Phase 7 | Pending |
| BURN-01 | Phase 8 | Pending |
| BURN-02 | Phase 8 | Pending |
| BURN-03 | Phase 8 | Pending |
| BURN-04 | Phase 8 | Pending |
| LEVL-01 | Phase 9 | Pending |
| LEVL-02 | Phase 9 | Pending |
| LEVL-03 | Phase 9 | Pending |
| LEVL-04 | Phase 9 | Pending |
| END-01 | Phase 9 | Pending |
| END-02 | Phase 9 | Pending |
| DGNR-01 | Phase 10 | Pending |
| DGNR-02 | Phase 10 | Pending |
| DGNR-03 | Phase 10 | Pending |
| DGNR-04 | Phase 10 | Pending |
| DEIT-01 | Phase 10 | Pending |
| DEIT-02 | Phase 10 | Pending |
| DEIT-03 | Phase 10 | Pending |
| AFFL-01 | Phase 10 | Pending |
| AFFL-02 | Phase 10 | Pending |
| AFFL-03 | Phase 10 | Pending |
| STETH-01 | Phase 10 | Pending |
| STETH-02 | Phase 10 | Pending |
| QRWD-01 | Phase 10 | Pending |
| QRWD-02 | Phase 10 | Pending |
| PARM-01 | Phase 11 | Pending |
| PARM-02 | Phase 11 | Pending |
| PARM-03 | Phase 11 | Pending |

**Coverage:**
- v1.1 requirements: 44 total
- Mapped to phases: 44
- Unmapped: 0

---
*Requirements defined: 2026-03-12*
*Last updated: 2026-03-12 after roadmap creation*
