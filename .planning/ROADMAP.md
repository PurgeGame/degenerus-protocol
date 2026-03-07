# Roadmap: Degenerus Protocol

## Milestones

- ✅ **v1.0 Audit** — Phases 1-7 (shipped 2026-03-04)
- ✅ **v2.0 Adversarial Audit** — Phases 8-13 (shipped 2026-03-05)
- ✅ **v3.0 Adversarial Hardening** — Phases 14-18 (shipped 2026-03-05)
- ✅ **v4.0 Pre-C4A Adversarial Stress Test** — Phases 19-29 (shipped 2026-03-05)
- ✅ **v5.0 Novel Zero-Day Attack Surface Audit** — Phases 30-35 (shipped 2026-03-05)
- ✅ **v1.0 Off-Chain Simulation Engine** — Phases 36-42 (shipped 2026-03-06)
- ✅ **v6.0 Contract Hardening & Parity Verification** — Phases 43-47 (shipped 2026-03-07)
- 🚧 **v7.0 Function-Level Exhaustive Audit** — Phases 48-58 (in progress)

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

<details>
<summary>✅ v6.0 Contract Hardening & Parity Verification (Phases 43-47) — SHIPPED 2026-03-07</summary>

- [x] Phase 43: Governance & Gating Tests (1/1 plan) — completed 2026-03-07
- [x] Phase 44: Affiliate System Tests (1/1 plan) — completed 2026-03-07
- [x] Phase 45: Security & Economic Hardening Tests (2/2 plans) — completed 2026-03-07
- [x] Phase 46: Game Theory Paper Parity (1/1 plan) — completed 2026-03-07
- [x] Phase 47: NatSpec Comment Audit (8/8 plans) — completed 2026-03-06

**Results:** 64/64 requirements satisfied. 236 new tests (1185 total). Full NatSpec audit of 22 contracts.

See: `.planning/milestones/v6.0-ROADMAP.md` for full phase details.

</details>

### v7.0 Function-Level Exhaustive Audit (In Progress)

**Milestone Goal:** Exhaustive function-by-function audit of every production Solidity file -- structured JSON + markdown reports per function covering callers, callees, state mutations, invariants, NatSpec accuracy, gas waste, and correctness verdict.

- [ ] **Phase 48: Audit Infrastructure** - Define JSON schema, cross-reference index format, and state mutation map format
- [ ] **Phase 49: Core Game Contract** - DegenerusGame.sol (19KB) and DegenerusGameStorage.sol function-level audit
- [x] **Phase 50: ETH Flow Modules** - AdvanceModule, MintModule, JackpotModule function-level audit (completed 2026-03-07)
- [x] **Phase 51: Endgame & Lifecycle Modules** - EndgameModule, LootboxModule, GameOverModule function-level audit (completed 2026-03-07)
- [ ] **Phase 52: Whale & Player Modules** - WhaleModule, DegeneretteModule, BoonModule, DecimatorModule function-level audit
- [x] **Phase 53: Module Utilities & Libraries** - MintStreakUtils, PayoutUtils, BitPackingLib, EntropyLib, GameTimeLib, PriceLookupLib, JackpotBucketLib audit (completed 2026-03-07)
- [ ] **Phase 54: Token & Economics Contracts** - BurnieCoin, BurnieCoinflip (16KB), DegenerusVault, DegenerusStonk function-level audit
- [ ] **Phase 55: Pass, Social & Interface Contracts** - DeityPass, DeityBoonViewer, Affiliate, Quests, Jackpots, and all interface verification
- [ ] **Phase 56: Admin & Support Contracts** - DegenerusAdmin, TraitUtils, ContractAddresses, Icons32Data, WrappedWrappedXRP audit
- [ ] **Phase 57: Cross-Contract Verification & Prior Claims** - Call graph, ETH flow map, mutation matrix, gas flags, v1-v6 spot-check, game theory cross-ref
- [ ] **Phase 58: Synthesis Report** - Aggregate findings, severity ratings, confidence assessment, executive summary

## Phase Details

### Phase 48: Audit Infrastructure
**Goal**: All subsequent audit phases have a defined output schema and format -- every function audit produces consistent, machine-readable JSON alongside human-readable markdown
**Depends on**: Nothing (first phase of v7.0)
**Requirements**: INFRA-01, INFRA-02, INFRA-03
**Success Criteria** (what must be TRUE):
  1. A JSON schema file exists that defines the structure for every function-level audit entry (signature, visibility, params, state reads/writes, callers, callees, invariants, NatSpec verdict, gas flags, overall verdict)
  2. A cross-reference index template exists showing how to record every caller/callee relationship with context annotations (delegatecall vs direct, internal vs external)
  3. A state mutation map template exists showing how to record which functions write which storage slots, partitioned by module
  4. A sample audit entry exists demonstrating the schema applied to a real function
**Plans**: TBD

### Phase 49: Core Game Contract
**Goal**: Every function in DegenerusGame.sol and every storage variable in DegenerusGameStorage.sol has a complete audit report with correctness verdict
**Depends on**: Phase 48
**Requirements**: CORE-01, CORE-02
**Success Criteria** (what must be TRUE):
  1. Every public/external function in DegenerusGame.sol has a JSON + markdown audit entry covering callers, callees, state mutations, invariants, NatSpec accuracy, gas flags, and verdict
  2. Every internal/private function in DegenerusGame.sol has a JSON + markdown audit entry
  3. Every storage variable in DegenerusGameStorage.sol is documented with its slot, type, which modules read it, and which modules write it
  4. All delegatecall dispatch paths from DegenerusGame into modules are enumerated with their selectors and target modules
**Plans**: TBD

### Phase 50: ETH Flow Modules
**Goal**: Every function in the three core ETH-path modules (Advance, Mint, Jackpot) has a complete audit report
**Depends on**: Phase 48
**Requirements**: MOD-01, MOD-02, MOD-03
**Success Criteria** (what must be TRUE):
  1. Every function in DegenerusGameAdvanceModule.sol has a JSON + markdown audit entry with verdict
  2. Every function in DegenerusGameMintModule.sol has a JSON + markdown audit entry with verdict
  3. Every function in DegenerusGameJackpotModule.sol has a JSON + markdown audit entry with verdict
  4. All ETH mutation paths through these three modules are traced and annotated
**Plans:** 4/4 plans complete
Plans:
- [ ] 50-01-PLAN.md -- AdvanceModule function-level audit (~40 functions)
- [ ] 50-02-PLAN.md -- MintModule function-level audit (~16 functions)
- [ ] 50-03-PLAN.md -- JackpotModule Part 1: entry points, pool management, auto-rebuy (~21 functions)
- [ ] 50-04-PLAN.md -- JackpotModule Part 2: distribution engine, coin jackpots, helpers (~36 functions)

### Phase 51: Endgame & Lifecycle Modules
**Goal**: Every function in the three game lifecycle modules (Endgame, Lootbox, GameOver) has a complete audit report
**Depends on**: Phase 48
**Requirements**: MOD-04, MOD-05, MOD-06
**Success Criteria** (what must be TRUE):
  1. Every function in DegenerusGameEndgameModule.sol has a JSON + markdown audit entry with verdict
  2. Every function in DegenerusGameLootboxModule.sol has a JSON + markdown audit entry with verdict
  3. Every function in DegenerusGameGameOverModule.sol has a JSON + markdown audit entry with verdict
  4. Game-over terminal state transitions and prize distribution paths are fully traced
**Plans**: TBD

### Phase 52: Whale & Player Modules
**Goal**: Every function in the four player interaction modules (Whale, Degenerette, Boon, Decimator) has a complete audit report
**Depends on**: Phase 48
**Requirements**: MOD-07, MOD-08, MOD-09, MOD-10
**Success Criteria** (what must be TRUE):
  1. Every function in DegenerusGameWhaleModule.sol has a JSON + markdown audit entry with verdict
  2. Every function in DegenerusGameDegeneretteModule.sol has a JSON + markdown audit entry with verdict
  3. Every function in DegenerusGameBoonModule.sol has a JSON + markdown audit entry with verdict
  4. Every function in DegenerusGameDecimatorModule.sol has a JSON + markdown audit entry with verdict
  5. All whale pricing formulas (bundle, lazy pass, deity pass) are verified against game theory paper
**Plans:** 2/4 plans executed
Plans:
- [ ] 52-01-PLAN.md -- WhaleModule function-level audit (18 functions)
- [ ] 52-02-PLAN.md -- DegeneretteModule function-level audit (31 functions)
- [ ] 52-03-PLAN.md -- BoonModule function-level audit (5 functions)
- [ ] 52-04-PLAN.md -- DecimatorModule function-level audit (24 functions)

### Phase 53: Module Utilities & Libraries
**Goal**: Every function in the 2 module utility contracts and 5 library contracts has a complete audit report
**Depends on**: Phase 48
**Requirements**: MOD-11, MOD-12, LIB-01, LIB-02, LIB-03, LIB-04, LIB-05
**Success Criteria** (what must be TRUE):
  1. Every function in DegenerusGameMintStreakUtils.sol has a JSON + markdown audit entry with verdict
  2. Every function in DegenerusGamePayoutUtils.sol has a JSON + markdown audit entry with verdict
  3. Every function in BitPackingLib.sol, EntropyLib.sol, GameTimeLib.sol, PriceLookupLib.sol, and JackpotBucketLib.sol has a JSON + markdown audit entry with verdict
  4. All library call sites across the protocol are enumerated for each library
**Plans**: TBD

### Phase 54: Token & Economics Contracts
**Goal**: Every function in BurnieCoin, BurnieCoinflip (16KB), DegenerusVault, and DegenerusStonk has a complete audit report
**Depends on**: Phase 48
**Requirements**: TOKEN-01, TOKEN-02, TOKEN-03, TOKEN-04
**Success Criteria** (what must be TRUE):
  1. Every function in BurnieCoin.sol has a JSON + markdown audit entry with verdict
  2. Every function in BurnieCoinflip.sol has a JSON + markdown audit entry with verdict (including coinflip resolution and payout distribution)
  3. Every function in DegenerusVault.sol has a JSON + markdown audit entry with verdict (including stETH yield and share math)
  4. Every function in DegenerusStonk.sol has a JSON + markdown audit entry with verdict
**Plans**: TBD

### Phase 55: Pass, Social & Interface Contracts
**Goal**: Every function in DeityPass, DeityBoonViewer, Affiliate, Quests, and Jackpots has a complete audit report, and every interface signature and NatSpec is verified against its implementation
**Depends on**: Phase 48
**Requirements**: PASS-01, PASS-02, SOCIAL-01, SOCIAL-02, SOCIAL-03, IFACE-01, IFACE-02
**Success Criteria** (what must be TRUE):
  1. Every function in DegenerusDeityPass.sol and DeityBoonViewer.sol has a JSON + markdown audit entry with verdict
  2. Every function in DegenerusAffiliate.sol, DegenerusQuests.sol, and DegenerusJackpots.sol has a JSON + markdown audit entry with verdict
  3. Every interface function signature across all interface files matches its implementation exactly (parameter types, return types, visibility)
  4. Every interface NatSpec comment matches the actual behavior of the implementing function
**Plans**: TBD

### Phase 56: Admin & Support Contracts
**Goal**: Every function in Admin, TraitUtils, and support contracts has a complete audit report, and ContractAddresses constants are verified
**Depends on**: Phase 48
**Requirements**: ADMIN-01, ADMIN-02, ADMIN-03, ADMIN-04, ADMIN-05
**Success Criteria** (what must be TRUE):
  1. Every function in DegenerusAdmin.sol has a JSON + markdown audit entry with verdict (including VRF wiring and admin privilege paths)
  2. Every function in DegenerusTraitUtils.sol has a JSON + markdown audit entry with verdict
  3. Every constant in ContractAddresses.sol is verified against the deploy order and actual usage across all contracts
  4. Every function in Icons32Data.sol and WrappedWrappedXRP.sol has a JSON + markdown audit entry with verdict
**Plans**: TBD

### Phase 57: Cross-Contract Verification & Prior Claims
**Goal**: Complete cross-cutting analysis across the entire protocol -- call graph, ETH flow map, state mutation matrix, gas flags, and verification of prior v1-v6 claims against current code
**Depends on**: Phases 49-56 (all individual contract audits)
**Requirements**: XREF-01, XREF-02, XREF-03, GAS-01, GAS-02, VERIFY-01, VERIFY-02
**Success Criteria** (what must be TRUE):
  1. A complete call graph exists showing every caller/callee relationship across the protocol, annotated with call type (delegatecall, direct external, internal)
  2. An ETH flow map traces every path ETH enters, moves within, or exits the protocol (deposits, splits, claims, refunds, sweeps)
  3. A state mutation matrix shows which modules can write which storage slots via delegatecall, with no undocumented writes
  4. All impossible condition checks and redundant storage reads are flagged across all contracts
  5. Critical claims from v1-v6 audits are spot-checked against current code, and game theory paper intent is cross-referenced for ambiguous functions
**Plans**: TBD

### Phase 58: Synthesis Report
**Goal**: A complete aggregate findings report with severity ratings and an executive summary with honest confidence assessment
**Depends on**: Phase 57 (cross-contract verification complete)
**Requirements**: SYNTH-01, SYNTH-02
**Success Criteria** (what must be TRUE):
  1. An aggregate findings report exists listing every finding from Phases 49-57, classified by severity (Critical/High/Medium/Low/QA)
  2. An executive summary exists with overall protocol confidence assessment, coverage metrics, and honest limitations
  3. Every finding has a clear description, affected function(s), severity justification, and remediation guidance where applicable
**Plans**: TBD

## Progress

**Execution Order:**
Phases 48 first (infrastructure). Phases 49-56 can be parallelized after 48. Phase 57 depends on 49-56. Phase 58 depends on 57.

**Cumulative:** 47 phases complete across 7 milestones shipped.

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 48. Audit Infrastructure | 0/TBD | Not started | - |
| 49. Core Game Contract | 0/TBD | Not started | - |
| 50. ETH Flow Modules | 4/4 | Complete    | 2026-03-07 |
| 51. Endgame & Lifecycle Modules | 4/4 | Complete    | 2026-03-07 |
| 52. Whale & Player Modules | 2/4 | In Progress|  |
| 53. Module Utilities & Libraries | 4/4 | Complete    | 2026-03-07 |
| 54. Token & Economics Contracts | 0/TBD | Not started | - |
| 55. Pass, Social & Interface Contracts | 0/TBD | Not started | - |
| 56. Admin & Support Contracts | 0/TBD | Not started | - |
| 57. Cross-Contract Verification & Prior Claims | 0/TBD | Not started | - |
| 58. Synthesis Report | 0/TBD | Not started | - |
