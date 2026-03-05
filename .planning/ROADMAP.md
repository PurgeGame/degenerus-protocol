# Roadmap: Degenerus Protocol Security Audit

## Milestones

- ✅ **v1.0 Audit** -- Phases 1-7 (shipped 2026-03-04)
- ✅ **v2.0 Adversarial Audit** -- Phases 8-13 (shipped 2026-03-05)
- ✅ **v3.0 Adversarial Hardening** -- Phases 14-18 (shipped 2026-03-05)
- **v4.0 Pre-C4A Adversarial Stress Test** -- Phases 19-29 (in progress)

## Phases

<details>
<summary>v1.0 Audit (Phases 1-7) -- SHIPPED 2026-03-04</summary>

- [x] Phase 1: Storage Foundation Verification (4/4 plans) -- completed 2026-02-28
- [x] Phase 2: Core State Machine and VRF Lifecycle (6/6 plans) -- completed 2026-03-01
- [x] Phase 3a: Core ETH Flow Modules (7/7 plans) -- completed 2026-03-01
- [x] Phase 3b: VRF-Dependent Modules (6/6 plans) -- completed 2026-03-01
- [x] Phase 3c: Supporting Mechanics Modules (6/6 plans) -- completed 2026-03-01
- [~] Phase 4: ETH and Token Accounting Integrity (1/9 plans) -- INCOMPLETE (closed by Phase 8 in v2.0)
- [x] Phase 5: Economic Attack Surface (7/7 plans) -- completed 2026-03-04
- [x] Phase 6: Access Control and Privilege Model (7/7 plans) -- completed 2026-03-04
- [x] Phase 7: Cross-Contract Integration Synthesis (5/5 plans) -- completed 2026-03-04

See: `.planning/milestones/v1.0-ROADMAP.md` for full phase details and findings.

</details>

<details>
<summary>v2.0 Adversarial Audit (Phases 8-13) -- SHIPPED 2026-03-05</summary>

- [x] Phase 8: ETH Accounting Invariant and CEI Verification (5/5 plans) -- completed 2026-03-04
- [x] Phase 9: advanceGame() Gas Analysis and Sybil Bloat (4/4 plans) -- completed 2026-03-04
- [x] Phase 10: Admin Power, VRF Griefing, and Assembly Safety (4/4 plans) -- completed 2026-03-04
- [x] Phase 11: Token Security, Economic Attacks, Vault and Timing (5/5 plans) -- completed 2026-03-04
- [x] Phase 12: Cross-Function Reentrancy Synthesis and Unchecked Blocks (3/3 plans) -- completed 2026-03-04
- [x] Phase 13: Final Synthesis Report (4/4 plans) -- completed 2026-03-05

**Results:** 0 Critical, 0 High, 0 Medium, 1 Low, 8 QA/Info. All 48 requirements satisfied.

See: `.planning/milestones/v2.0-ROADMAP.md` for full phase details.

</details>

<details>
<summary>v3.0 Adversarial Hardening (Phases 14-18) -- SHIPPED 2026-03-05</summary>

- [x] Phase 14: Foundry Infrastructure and Compiler Alignment (4/4 plans) -- completed 2026-03-05
- [x] Phase 15: Core Handlers and ETH Solvency Invariant (3/3 plans) -- completed 2026-03-05
- [x] Phase 16: Remaining Invariant Harnesses (4/4 plans) -- completed 2026-03-05
- [x] Phase 17: Adversarial Sessions and Formal Verification (5/5 plans) -- completed 2026-03-05
- [x] Phase 18: Consolidated Report and Coverage Metrics (3/3 plans) -- completed 2026-03-05

**Results:** 0 Critical, 0 High, 0 Medium. 48 invariant tests, 53 adversarial vectors, 10 symbolic properties. 18/18 requirements satisfied.

See: `.planning/milestones/v3.0-ROADMAP.md` for full phase details.

</details>

### v4.0 Pre-C4A Adversarial Stress Test (In Progress)

**Milestone Goal:** Find every exploitable vulnerability, economic attack, and edge-case failure before Code4rena wardens do. Zero findings paid out to external auditors is the success metric.

**Architecture:** Phases 19-28 are 10 fully parallel blind threat model agents with zero inter-agent dependencies. Phase 29 is the sequential synthesis gate that waits for all 10 agents to complete.

- [ ] **Phase 19: Nation-State Attacker** -- 10K ETH + MEV + validator ordering attacks under blind analysis
- [ ] **Phase 20: Coercion Attacker** -- Hostile admin compromise damage map and fund extraction paths
- [x] **Phase 21: Evil Genius Hacker** -- Deep Solidity exploits: delegatecall, storage, viaIR, assembly, compiler bugs (completed 2026-03-05)
- [ ] **Phase 22: Sybil Whale Economist** -- Economic exploitation of pricing curves, whale bundles, deity passes, BURNIE token
- [ ] **Phase 23: Degenerate Fuzzer** -- New invariant harnesses targeting v3.0 coverage gaps and deep state space
- [ ] **Phase 24: Formal Methods Analyst** -- Certora CVL specs and extended symbolic verification beyond v3.0
- [ ] **Phase 25: Dependency & Integration Attacker** -- VRF/stETH/LINK failure modes and mock fidelity gaps
- [ ] **Phase 26: Gas Griefing Specialist** -- Attacker-controllable gas consumption and OOG callback attacks
- [ ] **Phase 27: White Hat Completionist** -- OWASP SC Top 10 + SWC sweep + ERC compliance + fresh-eyes review
- [ ] **Phase 28: Game Theory Attacker** -- Adversarial attack on resilience thesis, GAMEOVER path enumeration
- [ ] **Phase 29: Synthesis & Contradiction Report** -- Cross-reference all agents, coverage matrix, C4A-ready report

## Phase Details

### Phase 19: Nation-State Attacker
**Goal**: Determine whether an attacker with 10,000 ETH, MEV infrastructure, and block proposer capabilities can extract value or manipulate game outcomes
**Depends on**: Nothing (parallel with Phases 20-28)
**Requirements**: NSTATE-01, NSTATE-02, NSTATE-03, NSTATE-04, NSTATE-05
**Success Criteria** (what must be TRUE):
  1. Every frontrunning, backrunning, and sandwich attack vector against protocol interactions has been modeled with profitability analysis at 5/30/100 gwei
  2. Validator/proposer VRF fulfillment reordering attack is modeled with concrete manipulation scenarios showing whether profitable outcomes exist
  3. Malicious contract interaction patterns (callbacks, fallbacks, proxies) have been tested against all external entry points
  4. Combined nation-state + compromised admin + VRF failure scenario is fully enumerated with realistic attack timeline and mitigations identified
  5. Every Medium+ finding has a runnable Hardhat/Foundry PoC test in test/poc/
**Plans**: TBD

### Phase 20: Coercion Attacker
**Goal**: Map the complete damage surface of a compromised admin key and determine whether users can recover from hostile admin actions
**Depends on**: Nothing (parallel with Phases 19, 21-28)
**Requirements**: COERC-01, COERC-02, COERC-03, COERC-04, COERC-05
**Success Criteria** (what must be TRUE):
  1. Every admin-callable function is enumerated with maximum damage if called by a hostile actor
  2. Admin powers are classified as instant, time-locked, or constructor-only with coercion risk rated per category
  3. All fund extraction paths under hostile admin are documented (vault drain, VRF subscription redirect, fund freeze) with concrete ETH impact
  4. User recovery options after admin compromise are documented with worst-case locked-fund outcomes quantified
  5. Every Medium+ finding has a runnable Hardhat/Foundry PoC test in test/poc/
**Plans**: TBD

### Phase 21: Evil Genius Hacker
**Goal**: Find deep Solidity-level exploits in delegatecall patterns, storage layout, compiler behavior, and assembly blocks through cold-start source-only analysis
**Depends on**: Nothing (parallel with Phases 19-20, 22-28)
**Requirements**: EVIL-01, EVIL-02, EVIL-03, EVIL-04, EVIL-05, EVIL-06
**Success Criteria** (what must be TRUE):
  1. All external call sites and reentrant paths through delegatecall modules are independently re-derived without referencing v1-v3 findings
  2. Shared storage layout across all 10 delegatecall modules is independently derived and verified for zero collisions
  3. VRF manipulation vectors (request ID prediction, fulfillment delay, selective inclusion/exclusion) are analyzed with concrete attack scenarios
  4. Compiler-specific exploits for viaIR + optimizer runs=200 on Solidity 0.8.26/0.8.28 are cross-referenced against official bugs.json
  5. Every Medium+ finding has a runnable Hardhat/Foundry PoC test in test/poc/
**Plans**: TBD

### Phase 22: Sybil Whale Economist
**Goal**: Determine whether coordinated economic actors can extract value beyond intended game mechanics through pricing manipulation, token economy attacks, or multi-account coordination
**Depends on**: Nothing (parallel with Phases 19-21, 23-28)
**Requirements**: SYBIL-01, SYBIL-02, SYBIL-03, SYBIL-04, SYBIL-05, SYBIL-06
**Success Criteria** (what must be TRUE):
  1. Pricing curve manipulation via coordinated Sybil buying is modeled with concrete ETH profit/loss using actual PriceLookupLib values
  2. BURNIE token economy attacks (coinflip manipulation, mint/burn arbitrage, activity score gaming) are analyzed with extraction scenarios
  3. Deity pass market cornering and whale bundle exploitation are modeled at scale with T(n) pricing verified against contract code
  4. Multi-account coordination profit is compared against N independent accounts with concrete breakeven analysis
  5. Every Medium+ finding has a runnable Hardhat/Foundry PoC test in test/poc/
**Plans**: TBD

### Phase 23: Degenerate Fuzzer
**Goal**: Discover state-dependent vulnerabilities missed by v3.0 fuzzing through new harnesses targeting documented coverage gaps and deeper state space exploration
**Depends on**: Nothing (parallel with Phases 19-22, 24-28)
**Requirements**: FUZZ-01, FUZZ-02, FUZZ-03, FUZZ-04, FUZZ-05, FUZZ-06
**Success Criteria** (what must be TRUE):
  1. New invariant harnesses exist for Degenerette bet accounting, vault deposit/withdraw math, and level 10+ game progression (the three primary v3.0 gaps)
  2. Multi-level game progression is fuzzed across level transitions with 1000+ runs covering purchase-VRF-fulfill-advance cycles
  3. Concurrent whale bundle + Sybil ticket pressure scenarios are fuzzed simultaneously
  4. Coverage gap analysis documents state space reached vs total reachable states with explicit gap identification
  5. Every Medium+ finding discovered by fuzzing has a runnable PoC test in test/poc/
**Plans**: TBD

### Phase 24: Formal Methods Analyst
**Goal**: Extend formal verification beyond v3.0's 10 Halmos properties using unbounded Certora specs and deeper symbolic analysis to find arithmetic and state machine bugs
**Depends on**: Nothing (parallel with Phases 19-23, 25-28)
**Requirements**: FORMAL-01, FORMAL-02, FORMAL-03, FORMAL-04, FORMAL-05
**Success Criteria** (what must be TRUE):
  1. Certora CVL specs exist and verify for ETH solvency invariant, token supply conservation, and access control completeness
  2. Halmos symbolic verification is extended beyond v3.0's 10 properties to cover arithmetic invariants and state transition validity at deeper bounds
  3. ETH taint analysis tracks every wei from msg.value entry to .call{value:} exit across all 22 contracts with explicit flow documentation
  4. Reachability analysis determines whether premature gameOver, claimablePool exceeding ETH balance, or other dangerous states are reachable under any execution path
  5. Every Medium+ finding has a runnable Hardhat/Foundry PoC test in test/poc/
**Plans**: TBD

### Phase 25: Dependency & Integration Attacker
**Goal**: Identify all failure modes where external dependencies (VRF, stETH, LINK) behave differently from test mocks and quantify protocol impact
**Depends on**: Nothing (parallel with Phases 19-24, 26-28)
**Requirements**: DEP-01, DEP-02, DEP-03, DEP-04, DEP-05
**Success Criteria** (what must be TRUE):
  1. VRF coordinator failure modes (down, delayed, manipulated randomness, subscription exhausted, self-destruct) are each analyzed with protocol state impact
  2. stETH depeg solvency impact is computed with concrete ETH numbers at 10%, 50%, and 90% depeg scenarios
  3. LINK depletion and onTokenTransfer abuse vectors are modeled with fallback path analysis
  4. Dependency upgrade/deprecation risks (VRF V2.5 deprecated, stETH rebasing change, LINK upgrade) are documented with protocol impact
  5. Every Medium+ finding has a runnable Hardhat/Foundry PoC test in test/poc/
**Plans**: TBD

### Phase 26: Gas Griefing Specialist
**Goal**: Determine whether any protocol function can be forced into out-of-gas conditions or made prohibitively expensive through attacker-controlled inputs
**Depends on**: Nothing (parallel with Phases 19-25, 27-28)
**Requirements**: GAS-01, GAS-02, GAS-03, GAS-04, GAS-05
**Success Criteria** (what must be TRUE):
  1. Every function is analyzed for attacker-controllable gas consumption with a determination of whether any single transaction can be forced above 10M gas
  2. advanceGame and VRF callback gas is recalculated against current Ethereum block gas parameters (30M limit, not stale 16M)
  3. Storage slot bombing via bucket cursor, ticket queue, and player registry mappings is analyzed with concrete gas cost projections
  4. OOG in VRF callback and ETH receive callback is analyzed for game state bricking potential
  5. Every Medium+ finding has a runnable Hardhat/Foundry PoC test in test/poc/
**Plans**: TBD

### Phase 27: White Hat Completionist
**Goal**: Systematically verify protocol against standard vulnerability checklists and ERC compliance with fresh-eyes source review to catch what specialist agents miss
**Depends on**: Nothing (parallel with Phases 19-26, 28)
**Requirements**: WHTHAT-01, WHTHAT-02, WHTHAT-03, WHTHAT-04, WHTHAT-05, WHTHAT-06
**Success Criteria** (what must be TRUE):
  1. OWASP Smart Contract Top 10 (2026) SC-01 through SC-10 each have an explicit pass/fail/N-A verdict for every contract
  2. SWC Registry gaps not covered by OWASP are checked against the codebase with per-item verdicts
  3. BurnieCoin (ERC20) and DegenerusDeityPass/DegenerusNFT (ERC721) are verified for full standards compliance including edge cases (zero transfer, self-transfer, max approval)
  4. Fresh-eyes top-to-bottom code review documents anything that looks wrong without prior audit context
  5. Every Medium+ finding has a runnable Hardhat/Foundry PoC test in test/poc/
**Plans**: TBD

### Phase 28: Game Theory Attacker
**Goal**: Adversarially attack the resilience thesis paper, enumerate every GAMEOVER path, and verify every formal claim against actual contract code
**Depends on**: Nothing (parallel with Phases 19-27)
**Requirements**: GTHRY-01, GTHRY-02, GTHRY-03, GTHRY-04, GTHRY-05, GTHRY-06, GTHRY-07
**Success Criteria** (what must be TRUE):
  1. Every claim in the resilience thesis is identified as correct, wrong, understated, or unfalsifiable with code evidence from PriceLookupLib/WhaleModule/JackpotModule
  2. Every contract-level AND game-theoretic path to GAMEOVER is enumerated with probability estimates and capital requirements
  3. Cross-subsidy breakdown scenarios and death spiral constructions are modeled with concrete ETH figures showing where rational actors let the game die
  4. Every formal proposition and theorem in the paper (Proposition 4.1, Corollary 4.4, Observation 5.1, Design Property 8.4) is verified against actual contract code with discrepancies flagged
  5. Every Medium+ finding discovered during theory verification has a runnable Hardhat/Foundry PoC test in test/poc/
**Plans**: TBD

### Phase 29: Synthesis & Contradiction Report
**Goal**: Cross-reference all 10 agent reports to detect contradictions, identify coverage gaps, deduplicate findings, and deliver a C4A-ready final report
**Depends on**: Phases 19, 20, 21, 22, 23, 24, 25, 26, 27, 28
**Requirements**: SYNTH-01, SYNTH-02, SYNTH-03, SYNTH-04, SYNTH-05
**Success Criteria** (what must be TRUE):
  1. Contradictions where one agent says "X is safe" and another says "X is exploitable" are detected and resolved with reasoning
  2. Coverage matrix maps every contract function to which agents analyzed it, with zero-coverage functions explicitly identified
  3. All findings are deduplicated, severity-rated in C4A format, with consolidated PoC tests verified as runnable
  4. Honest confidence assessment acknowledges same-auditor bias, documents coverage gaps, and quantifies residual risk
  5. Final C4A-ready report includes all 10 agent attestations (finding or no-finding with specific coverage evidence)
**Plans**: TBD

## Progress

**Execution Order:**
Phases 19-28 execute in parallel (zero inter-agent dependencies). Phase 29 executes after all of 19-28 complete.

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 19. Nation-State Attacker | v4.0 | 0/TBD | Not started | - |
| 20. Coercion Attacker | v4.0 | 0/TBD | Not started | - |
| 21. Evil Genius Hacker | 1/1 | Complete   | 2026-03-05 | - |
| 22. Sybil Whale Economist | v4.0 | 0/TBD | Not started | - |
| 23. Degenerate Fuzzer | v4.0 | 0/TBD | Not started | - |
| 24. Formal Methods Analyst | v4.0 | 0/TBD | Not started | - |
| 25. Dependency & Integration Attacker | v4.0 | 0/TBD | Not started | - |
| 26. Gas Griefing Specialist | v4.0 | 0/TBD | Not started | - |
| 27. White Hat Completionist | v4.0 | 0/TBD | Not started | - |
| 28. Game Theory Attacker | v4.0 | 0/TBD | Not started | - |
| 29. Synthesis & Contradiction Report | v4.0 | 0/TBD | Not started | - |
