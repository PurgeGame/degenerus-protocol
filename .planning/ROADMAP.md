# Roadmap: Degenerus Protocol Security Audit

## Milestones

- ✅ **v1.0 Audit** — Phases 1-7 (shipped 2026-03-04)
- ✅ **v2.0 Adversarial Audit** — Phases 8-13 (shipped 2026-03-05)
- ✅ **v3.0 Adversarial Hardening** — Phases 14-18 (shipped 2026-03-05)
- ✅ **v4.0 Pre-C4A Adversarial Stress Test** — Phases 19-29 (shipped 2026-03-05)
- 🚧 **v5.0 Novel Zero-Day Attack Surface Audit** — Phases 30-35 (in progress)

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

### v5.0 Novel Zero-Day Attack Surface Audit (In Progress)

**Milestone Goal:** Hunt for creative, unconventional, and composition-based vulnerabilities that 10 prior audit agents missed -- validated by Foundry fuzzing, Slither static analysis, and Halmos symbolic verification.

- [x] **Phase 30: Tooling Setup and Static Analysis** - Configure Foundry deep profiles, run Slither full triage, fix Halmos configuration, establish baseline (completed 2026-03-05)
- [x] **Phase 31: Cross-Contract Composition Analysis** - Analyze delegatecall shared storage assumptions, module interaction matrix, selector collisions, BitPackingLib gaps, and build composition-focused harnesses (completed 2026-03-05)
- [x] **Phase 32: Precision and Rounding Analysis** - Audit all 222 division operations, zero-rounding free actions, dust accumulation, wei lifecycle precision loss (completed 2026-03-05)
- [ ] **Phase 33: Temporal, Lifecycle, and EVM-Level Analysis** - Timestamp boundaries, multi-tx races, lifecycle edge states, forced ETH, ABI encoding, assembly safety, unchecked blocks
- [ ] **Phase 34: Economic Composition and Auditor Re-examination** - Vault share inflation, price discrepancies, affiliate farming, reward manipulation, stETH edge cases, VRF griefing costs
- [ ] **Phase 35: Halmos Verification and Multi-Tool Synthesis** - Symbolic verification of pure math invariants, cross-tool convergence matrix, final findings report with attack narratives

## Phase Details

### Phase 30: Tooling Setup and Static Analysis
**Goal**: All automated analysis tools are configured, baselined, and producing actionable signal for subsequent manual analysis phases
**Depends on**: Nothing (first v5.0 phase)
**Requirements**: TOOL-01, TOOL-02, TOOL-04
**Success Criteria** (what must be TRUE):
  1. Foundry deep profile runs all existing invariant harnesses at 10K+ fuzz runs and 1K+ invariant runs with zero failures
  2. Slither full triage produces per-finding classification (true positive / false positive / investigate) for all 636+ detector results -- no bulk category dismissals
  3. Halmos configuration is fixed and can execute symbolic properties against the codebase without foundry.toml compatibility errors
  4. Foundry code coverage baseline captured BEFORE new harness development (enables coverage delta measurement in Phase 35)
**Plans**: 3 plans

Plans:
- [x] 30-01-PLAN.md — Foundry deep profile and coverage baseline — completed 2026-03-05
- [x] 30-02-PLAN.md — Slither full triage (630 findings) — completed 2026-03-05
- [ ] 30-03-PLAN.md — Halmos configuration fix and verification

### Phase 31: Cross-Contract Composition Analysis
**Goal**: All cross-module state composition assumptions are verified -- no delegatecall shared storage corruption is possible through any module ordering or interaction sequence
**Depends on**: Phase 30 (storage layouts from forge inspect)
**Requirements**: COMP-01, COMP-02, COMP-03, COMP-04, TOOL-05
**Success Criteria** (what must be TRUE):
  1. Storage slot ownership matrix exists mapping every slot to its owning module(s) -- all 30 delegatecall sites verified for assumption correctness in composition
  2. Module interaction matrix (10x10) tested with CompositionHandler -- no state corruption found across any A-then-B module execution sequence
  3. Function selector collision analysis confirms zero collisions across all delegatecall module boundaries
  4. BitPackingLib gap bits 155-227 verified -- no setPacked call site allows attacker-controllable shift/mask parameters that could corrupt adjacent packed fields
  5. New composition-focused Foundry invariant harnesses deliver meaningful coverage of cross-module state transitions
**Plans**: 3 plans

Plans:
- [x] 31-01-PLAN.md — Storage slot ownership matrix and selector collision analysis — completed 2026-03-05
- [x] 31-02-PLAN.md — BitPackingLib gap bit verification and cross-module write analysis — completed 2026-03-05
- [x] 31-03-PLAN.md — Module interaction matrix and composition invariant harness — completed 2026-03-05

### Phase 32: Precision and Rounding Analysis
**Goal**: All division operations, rounding behaviors, and precision loss paths are verified -- no input combination allows free actions via zero-rounding or accumulated dust extraction
**Depends on**: Phase 30 (Slither arithmetic flags as input signal)
**Requirements**: PREC-01, PREC-02, PREC-03, PREC-04
**Success Criteria** (what must be TRUE):
  1. All 222 division operations classified by risk -- every division-before-multiplication chain spanning multiple contracts identified and verified safe or flagged as finding
  2. Minimum viable amount analysis confirms no ticket quantity, lootbox amount, or other input rounds to zero cost while producing non-zero output
  3. Accumulated rounding error analysis across thousands of purchase-split-credit-claim cycles demonstrates dust cannot be extracted profitably
  4. Wei lifecycle trace from purchase through split through credit through claim shows total precision loss per full cycle is bounded and non-exploitable
**Plans**: 3 plans

Plans:
- [ ] 32-01-PLAN.md — Division operation census and classification (all 222 ops + 18 Slither INVESTIGATE)
- [ ] 32-02-PLAN.md — Zero-rounding boundary testing with Foundry fuzz tests
- [ ] 32-03-PLAN.md — Dust accumulation invariant tests and wei lifecycle trace

### Phase 33: Temporal, Lifecycle, and EVM-Level Analysis
**Goal**: All timestamp boundaries, lifecycle edge states, and EVM-level mechanics are verified -- no temporal manipulation, lifecycle interleaving, forced ETH, or unchecked arithmetic can corrupt protocol state or extract value
**Depends on**: Phase 30 (storage layouts for assembly verification)
**Requirements**: TEMP-01, TEMP-02, TEMP-03, LIFE-01, LIFE-02, LIFE-03, LIFE-04, EVM-01, EVM-02, EVM-03, EVM-04
**Success Criteria** (what must be TRUE):
  1. Block timestamp +-15s manipulation at all 5 timeout boundaries (912d, 365d, 18h, 3d, 30d) produces no day-boundary double-trigger or premature expiry
  2. Multi-tx race conditions between concurrent players (purchase interleaving, VRF callback ordering) produce no state inconsistency
  3. Pre-first-purchase (level 0), exact level boundaries (N to N+1), post-gameOver, and partial multi-step gameOver states all produce correct behavior for every callable function
  4. No code path uses address(this).balance instead of internal accounting -- forced ETH via selfdestruct cannot corrupt protocol state
  5. All 231 unchecked blocks verified for semantic correctness (wrong variable, wrong operator, truncation) beyond simple overflow -- all 6 assembly SSTORE/SLOAD operations re-verified against storage layout
**Plans**: 3 plans

Plans:
- [x] 33-01-PLAN.md — Temporal analysis (timestamp boundaries, race conditions, cross-contract divergence) — completed 2026-03-05
- [x] 33-02-PLAN.md — Lifecycle edge states (level 0, boundary transitions, gameOver, interleaving) — completed 2026-03-05
- [x] 33-03-PLAN.md — EVM-level analysis (forced ETH, ABI encoding, assembly, unchecked blocks) — completed 2026-03-05

### Phase 34: Economic Composition and Auditor Re-examination
**Goal**: All cross-system economic interactions and previously-cleared audit assumptions are re-verified -- no price discrepancy, vault manipulation, reward farming, or stETH edge case enables value extraction beyond game mechanics
**Depends on**: Phase 32 (precision results inform whether cheap-mint economic exploits are possible)
**Requirements**: ECON-01, ECON-02, ECON-03, ECON-04, ECON-05, REEX-01, REEX-02, REEX-03
**Success Criteria** (what must be TRUE):
  1. Vault share inflation / donation attack re-examination independently re-derives vault math and confirms no first-depositor or share manipulation attack is viable
  2. Price discrepancies between Game pricing, Vault shares, DGNRS pricing, and Degenerette odds cannot be composed to extract cross-system arbitrage
  3. Circular affiliate chains, quest reward farming, and boon effect stacking cannot produce net-positive value extraction
  4. stETH read-only reentrancy (share rate changing during callback) and slashing (balance decrease without transfer) are handled correctly -- no view function reads stale share rate
  5. VRF subscription balance depletion cost analysis confirms sustained griefing is economically infeasible
**Plans**: 3 plans

Plans:
- [ ] 34-01-PLAN.md — Vault math, price discrepancies, and affiliate chain analysis (ECON-01, ECON-02, ECON-03)
- [ ] 34-02-PLAN.md — Activity score manipulation and boon stacking analysis (ECON-04, ECON-05)
- [ ] 34-03-PLAN.md — Auditor re-examination: stETH reentrancy, VRF depletion, stETH slashing (REEX-01, REEX-02, REEX-03)

### Phase 35: Halmos Verification and Multi-Tool Synthesis
**Goal**: Pure math invariants are symbolically verified across the full input space, all tool signals are cross-referenced at function level, and a final findings report with honest confidence assessment is delivered
**Depends on**: Phases 31, 32, 33, 34 (all analysis complete; synthesis requires full data)
**Requirements**: TOOL-03, REEX-04, SYNTH-01, SYNTH-02, SYNTH-03
**Success Criteria** (what must be TRUE):
  1. Halmos symbolic verification of ShareMathInvariants, PriceLookupInvariants, and BurnieCoinInvariants reports per-function results (pass/fail/timeout) -- timeouts are reported honestly, not as "verified"
  2. Cross-tool convergence matrix maps every externally-callable function to its Slither/Halmos/Foundry signal -- functions flagged by 2+ tools are investigated to resolution
  3. C4A-format findings report includes novelty justification, attack narratives, and PoC tests for any Medium+ findings discovered across all v5.0 phases
  4. Top 5 most promising hypotheses investigated with detailed failure analysis explaining why each did not yield an exploitable finding (if no Medium+ findings)
  5. Honest confidence assessment states explicit coverage gaps, same-auditor bias limitations, and coverage delta from v1-v4
**Plans**: 3 plans

Plans:
- [ ] 35-01: TBD
- [ ] 35-02: TBD
- [ ] 35-03: TBD

## Progress

**Execution Order:**
Phases 31 and 32 can execute in parallel after Phase 30. Phase 33 depends on Phase 30. Phase 34 depends on Phase 32. Phase 35 depends on all prior phases.

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Storage Foundation | v1.0 | 4/4 | Complete | 2026-02-28 |
| 2. Core State Machine | v1.0 | 6/6 | Complete | 2026-03-01 |
| 3a. Core ETH Modules | v1.0 | 7/7 | Complete | 2026-03-01 |
| 3b. VRF Modules | v1.0 | 6/6 | Complete | 2026-03-01 |
| 3c. Supporting Modules | v1.0 | 6/6 | Complete | 2026-03-01 |
| 4. ETH Accounting | v1.0 | 1/9 | Incomplete | 2026-03-04 |
| 5. Economic Attack | v1.0 | 7/7 | Complete | 2026-03-04 |
| 6. Access Control | v1.0 | 7/7 | Complete | 2026-03-04 |
| 7. Integration Synthesis | v1.0 | 5/5 | Complete | 2026-03-04 |
| 8. ETH Invariant | v2.0 | 5/5 | Complete | 2026-03-04 |
| 9. Gas Analysis | v2.0 | 4/4 | Complete | 2026-03-04 |
| 10. Admin/VRF/Assembly | v2.0 | 4/4 | Complete | 2026-03-04 |
| 11. Token/Vault/Timing | v2.0 | 5/5 | Complete | 2026-03-04 |
| 12. Reentrancy/Unchecked | v2.0 | 3/3 | Complete | 2026-03-04 |
| 13. Synthesis Report | v2.0 | 4/4 | Complete | 2026-03-05 |
| 14. Foundry Infra | v3.0 | 4/4 | Complete | 2026-03-05 |
| 15. Core Handlers | v3.0 | 3/3 | Complete | 2026-03-05 |
| 16. Invariant Harnesses | v3.0 | 4/4 | Complete | 2026-03-05 |
| 17. Adversarial Sessions | v3.0 | 5/5 | Complete | 2026-03-05 |
| 18. Report & Coverage | v3.0 | 3/3 | Complete | 2026-03-05 |
| 19. Nation-State | v4.0 | 1/1 | Complete | 2026-03-05 |
| 20. Coercion | v4.0 | 1/1 | Complete | 2026-03-05 |
| 21. Evil Genius | v4.0 | 1/1 | Complete | 2026-03-05 |
| 22. Sybil Whale | v4.0 | 1/1 | Complete | 2026-03-05 |
| 23. Fuzzer | v4.0 | 1/1 | Complete | 2026-03-05 |
| 24. Formal Methods | v4.0 | 1/1 | Complete | 2026-03-05 |
| 25. Dependency | v4.0 | 1/1 | Complete | 2026-03-05 |
| 26. Gas Griefing | v4.0 | 1/1 | Complete | 2026-03-05 |
| 27. White Hat | v4.0 | 1/1 | Complete | 2026-03-05 |
| 28. Game Theory | v4.0 | 1/1 | Complete | 2026-03-05 |
| 29. Synthesis | v4.0 | 0/0 | Complete | 2026-03-05 |
| 30. Tooling Setup | 3/3 | Complete    | 2026-03-05 | - |
| 31. Composition | v5.0 | 3/3 | Complete | 2026-03-05 |
| 32. Precision | 3/3 | Complete   | 2026-03-05 | - |
| 33. Temporal/EVM | v5.0 | 3/3 | Complete | 2026-03-05 |
| 34. Economic/Re-exam | v5.0 | 0/? | Not started | - |
| 35. Halmos/Synthesis | v5.0 | 0/? | Not started | - |
