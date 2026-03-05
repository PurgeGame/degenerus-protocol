# Roadmap: Degenerus Protocol Security Audit

## Milestones

- ✅ **v1.0 Audit** — Phases 1-7 (shipped 2026-03-04)
- ✅ **v2.0 Adversarial Audit** — Phases 8-13 (shipped 2026-03-05)
- **v3.0 Adversarial Hardening** — Phases 14-18 (in progress)

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

### v3.0 Adversarial Hardening (In Progress)

**Milestone Goal:** Reduce C4 payout risk through dynamic invariant testing and independent blind adversarial attack sessions that find what static analysis missed.

- [x] **Phase 14: Foundry Infrastructure and Compiler Alignment** - Full protocol deployable and testable inside Foundry's test EVM (completed 2026-03-05)
- [x] **Phase 15: Core Handlers and ETH Solvency Invariant** - ETH solvency invariant validates the full fuzzing pipeline end-to-end (completed 2026-03-05)
- [ ] **Phase 16: Remaining Invariant Harnesses** - BurnieCoin supply, game FSM, vault shares, and ticket queue invariants all passing
- [ ] **Phase 17: Adversarial Sessions and Formal Verification** - 4 blind attack sessions and 2 Halmos bounded model checks completed independently
- [ ] **Phase 18: Consolidated Report and Coverage Metrics** - All findings consolidated into C4-format report with PoC tests and invariant coverage metrics

## Phase Details

### Phase 14: Foundry Infrastructure and Compiler Alignment
**Goal**: The full 22-contract protocol compiles and deploys correctly inside Foundry's test EVM with all cross-contract addresses matching production constants
**Depends on**: Nothing (first phase of v3.0)
**Requirements**: INFRA-01, INFRA-02, INFRA-03, INFRA-04
**Success Criteria** (what must be TRUE):
  1. `forge build` compiles all production contracts with solc 0.8.34 without errors or warnings
  2. `DeployProtocol.sol` deploys all 22 contracts in setUp() and a canary test confirms every address matches its ContractAddresses constant
  3. `patchForFoundry.js` predicts Foundry deployer nonces, patches ContractAddresses.sol, and a Makefile target automates the patch-build-test-restore cycle
  4. A VRF mock handler can fulfill randomness requests inside Foundry tests, allowing game state to advance past level 0
**Plans**: 4 plans
Plans:
- [ ] 14-01-PLAN.md -- Compiler alignment: solc 0.8.34 binary path, pragma fixes, forge build
- [ ] 14-02-PLAN.md -- Address prediction: patchForFoundry.js, empirical nonce validation
- [ ] 14-03-PLAN.md -- Full deploy: DeployProtocol.sol, canary test, Makefile automation
- [ ] 14-04-PLAN.md -- VRF validation: VRFHandler skeleton, game advances past level 0

### Phase 15: Core Handlers and ETH Solvency Invariant
**Goal**: The ETH solvency invariant holds across thousands of randomized call sequences, proving the full fuzzing pipeline works end-to-end
**Depends on**: Phase 14
**Requirements**: FUZZ-01
**Success Criteria** (what must be TRUE):
  1. ETH solvency invariant (`address(game).balance >= claimablePool + prizePool + futurePool + fees`) holds across all fuzzer-generated call sequences with zero violations
  2. Ghost variable accounting (`ghost_totalDeposited - ghost_totalClaimed`) reconciles with on-chain balances after every call
  3. Fuzzer achieves >60% non-reverting call rate and game advances past level 0 in at least some runs (confirmed via `show_metrics`)
  4. GameHandler, VRFHandler, and WhaleHandler drive the fuzzer through valid state transitions with bounded inputs and multi-actor support
**Plans**: 3 plans
Plans:
- [x] 15-01-PLAN.md -- GameHandler + base EthSolvency invariant scaffold
- [x] 15-02-PLAN.md -- WhaleHandler + ghost variable reconciliation
- [x] 15-03-PLAN.md -- Tuning + metrics verification + level advancement

**Results:** ETH solvency invariant holds across 256 runs x 128 depth (32,768 calls). 100% non-reverting handler rate. Ghost accounting reconciles. 5 invariants passing.

### Phase 16: Remaining Invariant Harnesses
**Goal**: Four additional invariant harnesses cover BurnieCoin supply conservation, game FSM transitions, vault share math, and ticket queue ordering -- all passing with adequate state coverage
**Depends on**: Phase 15
**Requirements**: FUZZ-02, FUZZ-03, FUZZ-04, FUZZ-05
**Success Criteria** (what must be TRUE):
  1. BurnieCoin supply invariant holds: `totalSupply() == sum of all credit/mint paths` with no violations across all call sequences
  2. Game FSM invariant holds: level only increases, gameOver is terminal, rngLocked follows request-fulfill-unlock cycle
  3. Vault share invariant holds: `vault.totalAssets() >= sum(all redeemable shares)` with no violations
  4. Ticket queue invariant holds: no player appears twice at same level after any call sequence
  5. CoinHandler drives BURNIE mint/burn/transfer/coinflip operations with adequate coverage (>50% non-reverting calls)
**Plans**: TBD

### Phase 17: Adversarial Sessions and Formal Verification
**Goal**: 4 independent blind adversarial sessions with distinct attacker personas and 2 Halmos bounded model checks complete, producing PoC-backed findings for any Medium+ vulnerabilities discovered
**Depends on**: Phase 14 (adversarial sessions use Hardhat, not Foundry handlers; Halmos uses Foundry contracts)
**Requirements**: ADVR-01, ADVR-02, ADVR-03, ADVR-04, FVRF-01, FVRF-02
**Success Criteria** (what must be TRUE):
  1. 4 adversarial attack sessions completed independently: ETH extraction, advanceGame bricking, claimWinnings overflow, delegatecall reentrancy -- each with a distinct C4 warden persona and contradiction-framed brief
  2. Every Medium+ finding from adversarial sessions has a working PoC test that demonstrates the vulnerability
  3. Halmos bounded model check confirms Game FSM transition validity within bounded depth (no illegal state transitions)
  4. Halmos bounded model check confirms key arithmetic properties (price curves, BPS splits, T(n) formula) hold within bounded input ranges
  5. Sessions honestly report if no Medium+ findings were discovered (absence of findings is a valid outcome)
**Plans**: TBD

### Phase 18: Consolidated Report and Coverage Metrics
**Goal**: All adversarial findings, invariant results, and formal verification outcomes consolidated into a single C4-format report with honest confidence metrics
**Depends on**: Phase 16, Phase 17
**Requirements**: REPT-01, REPT-02, REPT-03
**Success Criteria** (what must be TRUE):
  1. Every Medium+ finding from adversarial sessions has a reproducible PoC Hardhat test in the test suite
  2. Consolidated C4-format findings report includes severity ratings, root cause analysis, and remediation guidance for all findings across all attack sessions
  3. Invariant test coverage metrics report includes revert rates, maximum state depth reached, call distribution across handlers, and honest confidence assessment
**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 14 -> 15 -> 16 -> 17 -> 18
Note: Phase 17 can begin after Phase 14 completes (does not depend on 15/16).

| Phase | Milestone | Plans | Status | Completed |
|-------|-----------|-------|--------|-----------|
| 1. Storage Foundation Verification | v1.0 | 4/4 | Complete | 2026-02-28 |
| 2. Core State Machine and VRF Lifecycle | v1.0 | 6/6 | Complete | 2026-03-01 |
| 3a. Core ETH Flow Modules | v1.0 | 7/7 | Complete | 2026-03-01 |
| 3b. VRF-Dependent Modules | v1.0 | 6/6 | Complete | 2026-03-01 |
| 3c. Supporting Mechanics Modules | v1.0 | 6/6 | Complete | 2026-03-01 |
| 4. ETH and Token Accounting Integrity | v1.0 | 1/9 | Gap (closed in v2.0) | - |
| 5. Economic Attack Surface | v1.0 | 7/7 | Complete | 2026-03-04 |
| 6. Access Control and Privilege Model | v1.0 | 7/7 | Complete | 2026-03-04 |
| 7. Cross-Contract Integration Synthesis | v1.0 | 5/5 | Complete | 2026-03-04 |
| 8. ETH Accounting Invariant and CEI | v2.0 | 5/5 | Complete | 2026-03-04 |
| 9. advanceGame() Gas and Sybil Bloat | v2.0 | 4/4 | Complete | 2026-03-04 |
| 10. Admin Power, VRF, Assembly | v2.0 | 4/4 | Complete | 2026-03-04 |
| 11. Token, Vault, Timing | v2.0 | 5/5 | Complete | 2026-03-04 |
| 12. Reentrancy Synthesis, Unchecked | v2.0 | 3/3 | Complete | 2026-03-04 |
| 13. Final Synthesis Report | v2.0 | 4/4 | Complete | 2026-03-05 |
| 14. Foundry Infrastructure | v3.0 | 4/4 | Complete | 2026-03-05 |
| 15. Core Handlers and ETH Solvency | v3.0 | 3/3 | Complete | 2026-03-05 |
| 16. Remaining Invariant Harnesses | v3.0 | 0/TBD | Not started | - |
| 17. Adversarial Sessions and Formal Verification | v3.0 | 0/TBD | Not started | - |
| 18. Consolidated Report and Metrics | v3.0 | 0/TBD | Not started | - |
