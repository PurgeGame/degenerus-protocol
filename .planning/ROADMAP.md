# Roadmap: Degenerus Protocol

## Milestones

- ✅ **v1.0 Audit** — Phases 1-7 (shipped 2026-03-04)
- ✅ **v2.0 Adversarial Audit** — Phases 8-13 (shipped 2026-03-05)
- ✅ **v3.0 Adversarial Hardening** — Phases 14-18 (shipped 2026-03-05)
- ✅ **v4.0 Pre-C4A Adversarial Stress Test** — Phases 19-29 (shipped 2026-03-05)
- ✅ **v5.0 Novel Zero-Day Attack Surface Audit** — Phases 30-35 (shipped 2026-03-05)
- ✅ **v1.0 Off-Chain Simulation Engine** — Phases 36-42 (shipped 2026-03-06)
- 🚧 **v6.0 Contract Hardening & Parity Verification** — Phases 43-47 (in progress)

## Phases

<details>
<summary>✅ v1.0 Audit (Phases 1-7) — SHIPPED 2026-03-04</summary>

- [x] Phase 1: Storage Foundation Verification (4/4 plans) — completed 2026-02-28
- [x] Phase 2: Core State Machine and VRF Lifecycle (6/6 plans) — completed 2026-03-01
- [x] Phase 3a: Core ETH Flow Modules (7/7 plans) — completed 2026-03-01
- [x] Phase 3b: VRF-Dependent Modules (6/6 plans) — completed 2026-03-01
- [x] Phase 3c: Supporting Mechanics Modules (6/6 plans) — completed 2026-03-01
- [x] Phase 4: ETH and Token Accounting Integrity (9/9 plans) — completed 2026-03-06
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

<details>
<summary>✅ v1.0 Off-Chain Simulation Engine (Phases 36-42) — SHIPPED 2026-03-06</summary>

- [x] **Phase 36: Engine Foundation** - Project scaffolding, deterministic PRNG, state model, event system, browser-compatible engine shell (completed 2026-03-05)
- [x] **Phase 37: Core Game Loop** - Ticket purchasing, price escalation, prize pool splits, jackpots, century-level mechanics, level advancement, quest streaks, activity scores (completed 2026-03-05)
- [x] **Phase 38: Extended Mechanics** - Lootboxes, BURNIE/FLIP economics, Degenerette, full affiliate system, ETH claims, game-over, afKing, future tickets, DGNRS day-5 reward (completed 2026-03-05)
- [x] **Phase 39: Passes and Vault** - Whale/lazy/deity pass purchasing, deity bonuses, game-over refunds, stETH yield, vault share math, DGNRS burn-to-extract (completed 2026-03-05)
- [x] **Phase 40: Player Archetypes** - Degen, EV Maximizer, Whale, Hybrid behavioral profiles with Affiliate trait, budget constraints (completed 2026-03-05)
- [x] **Phase 41: Interactive Visualization** - React/D3 dashboard with charts, drill-downs, parameter controls, scenario comparison, export (completed 2026-03-06)
- [x] **Phase 42: Validation and Contract Parity** - Vitest formula tests, cross-validation suites, Hardhat parity (completed 2026-03-06)

</details>

### v6.0 Contract Hardening & Parity Verification (In Progress)

**Milestone Goal:** Comprehensive testing of all recent contract changes and systematic verification that every constant, NatSpec comment, and game theory paper number matches actual contract behavior.

- [ ] **Phase 43: Governance & Gating Tests** - DGVE majority governance, VRF shutdown lifecycle, tiered advanceGame mint gate (10 requirements)
- [ ] **Phase 44: Affiliate System Tests** - Per-referrer commission caps, lootbox activity taper, leaderboard tracking (9 requirements)
- [ ] **Phase 45: Security & Economic Hardening Tests** - Post-gameOver locks, deity refund mechanics, compressed jackpots, economic invariants (17 requirements)
- [ ] **Phase 46: Game Theory Paper Parity** - Systematic extraction of every number from the theory paper and verification against contract constants (18 requirements)
- [x] **Phase 47: NatSpec Comment Audit** - Read every NatSpec comment across all 22 contracts and verify each claim against actual code (10 requirements) (completed 2026-03-06)

## Phase Details

### Phase 43: Governance & Gating Tests
**Goal**: Every governance check (DGVE majority ownership) and advanceGame gating mechanism has dedicated test coverage proving correct behavior for authorized, unauthorized, and edge-case callers
**Depends on**: Nothing (first phase of milestone)
**Requirements**: ADMIN-01, ADMIN-02, ADMIN-03, ADMIN-04, ADMIN-05, ADMIN-06, GATE-01, GATE-02, GATE-03, GATE-04
**Success Criteria** (what must be TRUE):
  1. A test proves that only accounts holding >50.1% DGVE supply pass onlyOwner (Admin) and onlyVaultOwner (Vault) checks, and that the old CREATOR address alone fails both
  2. A test proves shutdownVrf() is callable only by GAME, successfully cancels subscription and sweeps LINK to VAULT, silently succeeds when subscriptionId is already 0, and handles coordinator/LINK transfer failures via try/catch
  3. A test proves the tiered advanceGame mint gate requires same-day minting, relaxes after the configured time delay, and is bypassed entirely by DGVE majority holders
  4. A test proves non-minters without DGVE majority revert with MustMintToday()
**Plans:** 1 plans
Plans:
- [ ] 43-01-PLAN.md -- Validate and commit governance/gating tests (ADMIN-01..06, GATE-01..04)

### Phase 44: Affiliate System Tests
**Goal**: The affiliate commission cap and lootbox activity taper produce correct payouts across all boundary conditions, and leaderboard tracking remains accurate regardless of taper
**Depends on**: Nothing (parallelizable with Phase 43)
**Requirements**: AFF-01, AFF-02, AFF-03, AFF-04, AFF-05, AFF-06, AFF-07, AFF-08, AFF-09
**Success Criteria** (what must be TRUE):
  1. A test proves per-referrer commission is capped at 0.5 ETH BURNIE per sender per level -- cumulative small purchases hit the cap, cap resets at the next level, and different affiliates have independent caps for the same sender
  2. A test proves lootbox activity taper: score <15000 BPS pays 100%, score 15000-25500 BPS linearly tapers from 100% to 50%, and score >=25500 BPS floors at 50%
  3. A test proves leaderboard tracking uses the full untapered amount even when the actual payout is reduced by taper
  4. A test proves the lootboxActivityScore parameter flows correctly through payAffiliate and produces the expected taper calculation
**Plans**: TBD

### Phase 45: Security & Economic Hardening Tests
**Goal**: Every post-audit security fix and economic change has a dedicated test proving it works correctly -- no whale/lazy/deity purchase after gameOver, no voluntary deity refund, correct gameOver deity payout, and all economic formula changes verified
**Depends on**: Nothing (parallelizable with Phases 43-44)
**Requirements**: FIX-01, FIX-02, FIX-03, FIX-04, FIX-05, FIX-06, FIX-07, FIX-08, FIX-09, FIX-10, FIX-11, FIX-12, ECON-01, ECON-02, ECON-03, ECON-04, ECON-05
**Success Criteria** (what must be TRUE):
  1. Tests prove whale bundle, lazy pass, deity pass purchases, and plain ETH receive() all revert after gameOver
  2. A test proves deity pass gameOver payout: flat 20 ETH/pass, levels 0-9 only, FIFO by purchase order, budget-capped; deity refund clears deityPassPurchasedCount; no voluntary pre-gameOver refund path exists
  3. Tests prove the 30-day BURNIE liveness guard blocks ticket purchases, subscriptionId is uint256 (large IDs handled), 1 wei sentinel preserved in degenerette claims, capBucketCounts handles zero-count buckets without underflow, and carryover floor is enforced
  4. Tests prove JackpotModule uses explicit 46% futureShare (2300+2300 BPS) with ~8% buffer unextracted, MintModule has no level-dependent coin cost modifiers, multi-level scatter targeting distributes correctly, compressed jackpot advances 2 per physical day when target met in <=2 days, and LINK reward formula is correct
**Plans**: TBD

### Phase 46: Game Theory Paper Parity
**Goal**: Every number, formula, rate, and threshold in the game theory paper (website/theory/index.html) is verified to match the corresponding contract constant or calculation -- systematic extraction with zero gaps
**Depends on**: Nothing (parallelizable with Phases 43-45)
**Requirements**: PAR-01, PAR-02, PAR-03, PAR-04, PAR-05, PAR-06, PAR-07, PAR-08, PAR-09, PAR-10, PAR-11, PAR-12, PAR-13, PAR-14, PAR-15, PAR-16, PAR-17, PAR-18
**Success Criteria** (what must be TRUE):
  1. A sanity-check test verifies PriceLookupLib prices at every tier boundary (levels 0,4,5,9,10,29,30,...,200), the ticket cost formula (costWei = priceWei * qty / 400), and BURNIE entry cost (250 BURNIE = 1 entry, 1000 = 1 full ticket) all match the paper
  2. A sanity-check test verifies prize pool split BPS (90/10 ticket, 10/90 lootbox, 40/40/20 presale), jackpot day structure (5 days, 6-14% days 1-4, 100% day 5), jackpot bucket shares (20/20/20/20 and 60/13.33/13.33/13.34), and yield distribution (23/23/46/8) all match the paper
  3. A sanity-check test verifies activity score components and caps, lootbox EV breakpoints (80%->100% at 0-60%, 100%->135% at 60-255%), and future ticket odds (95% near, 5% far) match the paper
  4. A sanity-check test verifies affiliate commission rates (25%/20%/5%), tier structure (direct/upline1/upline2 at 20%/4%), whale/lazy/deity pass pricing, coinflip payout distribution (5%/90%/5%, mean ~1.97x), Degenerette base payouts and ROI curve, and pass capital injection splits all match the paper
**Plans**: TBD

### Phase 47: NatSpec Comment Audit
**Goal**: Every NatSpec comment across all 22 contracts has been read and verified against actual code -- no stale claims, no wrong numbers, no misleading descriptions survive
**Depends on**: Phases 43-45 (test coverage for recent changes should be in place before auditing comments about those changes)
**Requirements**: DOC-01, DOC-02, DOC-03, DOC-04, DOC-05, DOC-06, DOC-07, DOC-08, DOC-09, DOC-10
**Success Criteria** (what must be TRUE):
  1. Every @notice and @dev comment in DegenerusAdmin, DegenerusAffiliate, AdvanceModule, MintModule, JackpotModule, and WhaleModule has been verified against the code -- any mismatch is either fixed or documented
  2. Every @notice and @dev comment in the remaining 7 modules (Endgame, GameOver, Lootbox, Boon, Decimator, Degenerette, MintStreakUtils) and 6 standalone contracts (BurnieCoin, BurnieCoinflip, DegenerusVault, DegenerusStonk, DegenerusQuests, DegenerusJackpots) has been verified
  3. Every error message description matches its actual trigger condition -- no error fires under conditions different from what its comment says
  4. Every event parameter description matches the actual emitted value -- no event emits data inconsistent with its documentation
**Plans:** 8/8 plans complete
Plans:
- [ ] 47-01-PLAN.md -- Fix existing Admin/Affiliate findings and verify completeness
- [ ] 47-02-PLAN.md -- Audit AdvanceModule and WhaleModule NatSpec
- [ ] 47-03-PLAN.md -- Audit MintModule and JackpotModule NatSpec
- [ ] 47-04-PLAN.md -- Audit LootboxModule, DecimatorModule, DegeneretteModule NatSpec
- [ ] 47-05-PLAN.md -- Audit EndgameModule, GameOverModule, BoonModule, MintStreakUtils, BurnieCoinflip NatSpec
- [ ] 47-06-PLAN.md -- Audit BurnieCoin, DegenerusVault, DegenerusStonk NatSpec
- [ ] 47-07-PLAN.md -- Audit DegenerusQuests, DegenerusJackpots NatSpec
- [ ] 47-08-PLAN.md -- Cross-contract error/event verification and final report consolidation

## Progress

**Execution Order:**
Phases 43, 44, 45, 46 are parallelizable (independent). Phase 47 depends on 43-45 completing first.

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1-7 | v1.0 Audit | 47/57 | Complete | 2026-03-04 |
| 8-13 | v2.0 Audit | 25/25 | Complete | 2026-03-05 |
| 14-18 | v3.0 Audit | 19/19 | Complete | 2026-03-05 |
| 19-29 | v4.0 Audit | 10/10 | Complete | 2026-03-05 |
| 30-35 | v5.0 Audit | 18/18 | Complete | 2026-03-05 |
| 36-42 | Sim v1.0 | 27/27 | Complete | 2026-03-06 |
| 43. Governance & Gating Tests | v6.0 | 0/1 | Not started | - |
| 44. Affiliate System Tests | v6.0 | 0/TBD | Not started | - |
| 45. Security & Economic Hardening Tests | v6.0 | 0/TBD | Not started | - |
| 46. Game Theory Paper Parity | v6.0 | 0/TBD | Not started | - |
| 47. NatSpec Comment Audit | 8/8 | Complete    | 2026-03-06 | - |

**Cumulative:** 42 phases complete, 5 phases planned. 6 milestones shipped, 1 in progress.
