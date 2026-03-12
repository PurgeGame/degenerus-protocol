# Roadmap: Degenerus Protocol

## Milestones

- ✅ **v1.0 Always-Open Purchases** — Phases 1-5 (shipped 2026-03-11)
- 🚧 **v1.1 Economic Flow Analysis** — Phases 6-11 (in progress)

## Phases

<details>
<summary>v1.0 Always-Open Purchases (Phases 1-5) — SHIPPED 2026-03-11</summary>

- [x] Phase 1: Storage Foundation (2/2 plans) — completed 2026-03-11
- [x] Phase 2: Queue Double-Buffer (2/2 plans) — completed 2026-03-11
- [x] Phase 3: Prize Pool Freeze (2/2 plans) — completed 2026-03-11
- [x] Phase 4: advanceGame Rewrite (1/1 plan) — completed 2026-03-11
- [x] Phase 5: Lock Removal (1/1 plan) — completed 2026-03-11

Full details: `.planning/milestones/v1.0-ROADMAP.md`

</details>

### v1.1 Economic Flow Analysis

**Milestone Goal:** Produce comprehensive economic flow documentation accurate enough for game theory agents to generate mathematically exact examples from contract mechanics.

- [x] **Phase 6: ETH Inflows and Pool Architecture** - Map every ETH entry path and the pool lifecycle that routes funds to prizes
- [x] **Phase 7: Jackpot & Distribution Mechanics** - Document all distribution flows: purchase-phase daily drip/BURNIE jackpots, jackpot-phase 5-day draws, and transition jackpots (BAF/Decimator) (completed 2026-03-12)
- [x] **Phase 8: BURNIE Economics** - Document the parallel BURNIE token economy (coinflip, earning, burning, vault) (completed 2026-03-12)
- [x] **Phase 9: Level Progression and Endgame** - Document price curves, level length dynamics, activity scores, death clock, and terminal distribution (completed 2026-03-12)
- [ ] **Phase 10: Reward Systems and Modifiers** - Document DGNRS tokenomics, deity boons, affiliates, stETH yield, and quest rewards
- [ ] **Phase 11: Parameter Reference** - Consolidate every constant, threshold, and BPS value into master lookup tables

## Phase Details

### Phase 6: ETH Inflows and Pool Architecture
**Goal**: A game theory agent can trace every ETH wei from purchase entry to pool allocation with exact formulas
**Depends on**: Nothing (first v1.1 phase)
**Requirements**: INFLOW-01, INFLOW-02, INFLOW-03, INFLOW-04, POOL-01, POOL-02, POOL-03, POOL-04
**Success Criteria** (what must be TRUE):
  1. Every purchase type (ticket, lootbox, whale bundle, lazy pass, deity pass, degenerette) has its ETH cost formula documented with exact Solidity expressions verified against contract source
  2. The complete pool lifecycle (future -> next -> current -> claimable) is diagrammed with every transition trigger identified by function name and condition
  3. Per-purchase-type pool split ratios are documented with exact BPS values that match contract constants
  4. Freeze/unfreeze behavior during jackpot phase is documented showing how pending accumulators interact with packed storage
  5. Presale vs post-presale economic differences are enumerated with the exact conditionals that gate them
**Plans**: 2 plans

Plans:
- [x] 06-01-PLAN.md — Document all ETH purchase paths with exact cost formulas and presale differences
- [x] 06-02-PLAN.md — Document pool storage, lifecycle transitions, freeze/unfreeze, and purchase targets

### Phase 7: Jackpot & Distribution Mechanics
**Goal**: A game theory agent can compute expected payouts across all distribution events — daily purchase-phase drip, jackpot-phase 5-day draws, and transition jackpots (BAF/Decimator)
**Depends on**: Phase 6 (pool architecture feeds all distribution inputs)
**Requirements**: JACK-01, JACK-02, JACK-03, JACK-04, JACK-05, JACK-06, JACK-07, JACK-08, JACK-09
**Success Criteria** (what must be TRUE):
  1. Daily purchase-phase future pool drip (ETH and tickets) is documented with exact formulas, triggers, and how it feeds into the next cycle
  2. Daily purchase-phase BURNIE jackpots are documented with winner selection and payout formulas
  3. The 5-day jackpot-phase draw sequence is documented with exact daily pool slice percentages (6-14% random range, 100% day 5) and the Solidity expressions that compute them
  4. Trait bucket distribution and winner selection mechanics are documented showing how ticket traits map to jackpot eligibility per day
  5. Carryover ETH mechanics and compressed jackpot conditions are documented with exact trigger thresholds
  6. Lootbox-to-jackpot conversion ratios (50% daily, 75% reward) are verified against contract constants
  7. BURNIE jackpot-phase parallel distribution and far-future allocation formulas are documented
  8. BAF mechanics (every 10 levels, future pool percentages, lootbox conversion) at jackpot-phase transition are fully documented
  9. Decimator mechanics (level triggers, multiplier tiers, BURNIE burn requirements) at jackpot-phase transition are fully documented
**Plans**: 3 plans

Plans:
- [ ] 07-01-PLAN.md — Document purchase-phase daily ETH drip and BURNIE jackpots
- [ ] 07-02-PLAN.md — Document 5-day jackpot-phase draw sequence with trait buckets, carryover, and BURNIE parallel distribution
- [ ] 07-03-PLAN.md — Document BAF and Decimator transition jackpot mechanics

### Phase 8: BURNIE Economics
**Goal**: A game theory agent can model BURNIE supply dynamics including all earning paths, burn sinks, and vault mechanics
**Depends on**: Phase 6 (BURNIE-to-ticket conversion references ETH formulas)
**Requirements**: BURN-01, BURN-02, BURN-03, BURN-04
**Success Criteria** (what must be TRUE):
  1. Coinflip mechanics (stake amounts, odds, payout range, bounty system, expiry) are documented with exact values from BurnieCoinflip.sol
  2. All BURNIE earning paths (lootbox bonuses, quest rewards, coinflip winnings) are enumerated with exact amounts verified against contract source
  3. All BURNIE burn sinks (decimator eligibility, ticket purchases) are documented with exact burn amounts and conditions
  4. Vault reserve mechanics and supply invariants are documented showing how the vault constrains total circulating BURNIE
**Plans**: 2 plans

Plans:
- [ ] 08-01-PLAN.md — Document BurnieCoinflip mechanics (stake, odds, payout tiers, bounty, recycling, claim windows, boons)
- [ ] 08-02-PLAN.md — Document BURNIE supply dynamics (earning paths, burn sinks, vault reserve invariant)

### Phase 9: Level Progression and Endgame
**Goal**: A game theory agent can simulate level transitions, price changes, and terminal game conditions across the full game lifespan
**Depends on**: Phase 6 (purchase targets drive level advancement), Phase 7 (BAF/Decimator covered there)
**Requirements**: LEVL-01, LEVL-02, LEVL-03, LEVL-04, END-01, END-02
**Success Criteria** (what must be TRUE):
  1. The complete price curve across all level ranges is documented with exact ETH values per ticket at each level transition
  2. Level length (120d) effects on pool accumulation and the purchase target formula are documented with exact Solidity expressions
  3. How whale bundle and lazy pass duration economics change across levels is documented
  4. Death clock (120d timeout, 365d deploy, distress mode) and terminal gameOver distribution are documented with exact timing constants and final payout formulas
  5. Activity score system and consecutive streak mechanics are documented with exact bonus calculations
**Plans**: 2 plans

Plans:
- [ ] 09-01-PLAN.md — Document price curve, level transition mechanics, and whale/lazy pass economics across levels
- [ ] 09-02-PLAN.md — Document activity score system, death clock escalation, and terminal distribution

### Phase 10: Reward Systems and Modifiers
**Goal**: A game theory agent can account for all secondary reward flows and modifier effects that adjust the core economic model
**Depends on**: Phase 6 (pool splits feed reward calculations), Phase 7 (deity boons affect jackpot entries)
**Requirements**: DGNR-01, DGNR-02, DGNR-03, DGNR-04, DEIT-01, DEIT-02, DEIT-03, AFFL-01, AFFL-02, AFFL-03, STETH-01, STETH-02, QRWD-01, QRWD-02
**Success Criteria** (what must be TRUE):
  1. DGNRS initial supply distribution across all pool types (creator, whale, affiliate, lootbox, reward, earlybird) is documented with exact token amounts and the soulbound transfer restriction rules
  2. Deity pass pricing curve (base + quadratic escalation) and all boon types with discount percentages and draw weights are documented with exact values from contract constants
  3. Affiliate referral reward structure (ETH and DGNRS flows), tier system with bonus calculations, and top affiliate endgame rewards are fully documented
  4. stETH integration mechanics and how yield accrual affects pool balances and distributions are documented
  5. Quest reward types, BURNIE amounts, trigger conditions, cooldowns, and per-player limits are documented with exact values
**Plans**: 5 plans

Plans:
- [ ] 10-01-PLAN.md — Document DGNRS tokenomics (supply distribution, earlybird curve, per-purchase rewards, soulbound mechanics)
- [ ] 10-02-PLAN.md — Document deity pass system (pricing curve, boon types and weights, activity score bonuses)
- [ ] 10-03-PLAN.md — Document affiliate system (3-tier referral, taper, kickback, per-level DGNRS claims)
- [ ] 10-04-PLAN.md — Document stETH yield integration (admin staking, yield surplus formula, payout ordering)
- [ ] 10-05-PLAN.md — Document quest reward system (types, targets, slot mechanics, streak system)

### Phase 11: Parameter Reference
**Goal**: Any constant, threshold, or BPS value in the protocol can be looked up in a single reference document with its exact value, purpose, and contract location
**Depends on**: Phases 6-10 (consolidates all parameters discovered during prior analysis)
**Requirements**: PARM-01, PARM-02, PARM-03
**Success Criteria** (what must be TRUE):
  1. A master table of all BPS constants includes the constant name, exact value, purpose description, and contract file + line number for every basis point split in the protocol
  2. A master table of all ETH thresholds, caps, and pricing constants includes exact wei/ETH values verified against contract source
  3. A master table of all timing constants (timeouts, windows, durations) includes exact values in seconds/days with their contract locations
**Plans**: TBD

Plans:
- [ ] 11-01: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 6 -> 7 -> 8 -> 9 -> 10 -> 11

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Storage Foundation | v1.0 | 2/2 | Complete | 2026-03-11 |
| 2. Queue Double-Buffer | v1.0 | 2/2 | Complete | 2026-03-11 |
| 3. Prize Pool Freeze | v1.0 | 2/2 | Complete | 2026-03-11 |
| 4. advanceGame Rewrite | v1.0 | 1/1 | Complete | 2026-03-11 |
| 5. Lock Removal | v1.0 | 1/1 | Complete | 2026-03-11 |
| 6. ETH Inflows and Pool Architecture | v1.1 | 2/2 | Complete | 2026-03-12 |
| 7. Jackpot & Distribution Mechanics | 3/3 | Complete   | 2026-03-12 | - |
| 8. BURNIE Economics | 2/2 | Complete   | 2026-03-12 | - |
| 9. Level Progression and Endgame | 2/2 | Complete   | 2026-03-12 | - |
| 10. Reward Systems and Modifiers | v1.1 | 0/5 | Not started | - |
| 11. Parameter Reference | v1.1 | 0/? | Not started | - |
