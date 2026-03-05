# Requirements: Degenerus Protocol v5.0 Novel Zero-Day Attack Surface Audit

**Defined:** 2026-03-05
**Core Value:** Every ETH that enters the protocol must be accounted for, every RNG outcome must be unmanipulable, and no actor can extract value beyond what the game mechanics intend.

## v5.0 Requirements

Requirements for novel zero-day attack surface audit. Each maps to roadmap phases.

### Automated Tooling

- [ ] **TOOL-01**: Foundry fuzzing runs with increased depth (10K+ fuzz runs, 1K+ invariant runs) on all existing harnesses — zero failures
- [ ] **TOOL-02**: Slither static analysis full re-triage with zero-day lens — all 636+ results classified per-finding (not bulk-dismissed)
- [ ] **TOOL-03**: Halmos symbolic verification of pure math invariants in ShareMathInvariants, PriceLookupInvariants, and BurnieCoinInvariants — results reported per function (pass/fail/timeout)
- [ ] **TOOL-04**: Halmos configuration fixed (foundry.toml compatibility, function prefix matching) to enable symbolic execution
- [ ] **TOOL-05**: New composition-focused Foundry invariant harnesses targeting precision chains, temporal boundaries, and cross-module state

### Cross-Contract Composition

- [ ] **COMP-01**: All 30 delegatecall sites analyzed for shared storage assumptions that hold individually but break in composition
- [ ] **COMP-02**: Module A → Module B state transition sequences tested for storage corruption (10 modules × 10 modules interaction matrix)
- [ ] **COMP-03**: Function selector collision analysis across all delegatecall module boundaries
- [ ] **COMP-04**: BitPackingLib gap bits (155-227) verified — no setPacked call site has attacker-controllable shift/mask parameters

### Precision and Rounding

- [x] **PREC-01**: All 222 division operations audited for division-before-multiplication chains spanning multiple contracts
- [x] **PREC-02**: Minimum viable amount analysis — identify any input that rounds to zero allowing free actions (e.g., ticket qty=1 cost formula)
- [x] **PREC-03**: Accumulated rounding error analysis across thousands of operations (dust attack feasibility)
- [x] **PREC-04**: Wei lifecycle trace through purchase→split→credit→claim path for precision loss accumulation

### Temporal Edge Cases

- [ ] **TEMP-01**: Block timestamp ±15s manipulation tested against all 5 timeout boundaries (912d, 365d, 18h, 3d, 30d) for day-boundary effects
- [ ] **TEMP-02**: Multi-tx race condition analysis between concurrent players (purchase interleaving, VRF callback ordering)
- [ ] **TEMP-03**: Time-dependent state divergence across contracts — timestamp read in one contract vs stale assumption in another

### Edge-of-Lifecycle States

- [ ] **LIFE-01**: Pre-first-purchase state analyzed — all functions callable at level 0 before any ticket exists
- [ ] **LIFE-02**: Exact level boundary transitions tested — state consistency at level N→N+1 crossover
- [ ] **LIFE-03**: Post-gameOver residual calls — all functions tested for correct behavior after gameOver=true
- [ ] **LIFE-04**: Partial multi-step gameOver interleaving — state mutations between advanceGame→VRF→fulfill→advanceGame steps

### EVM-Level

- [ ] **EVM-01**: selfdestruct/SELFDESTRUCT forced ETH analysis — verify no code path uses address(this).balance instead of internal accounting
- [ ] **EVM-02**: ABI encoding collision analysis for delegatecall dispatch — abi.encodePacked with variable-length arguments
- [ ] **EVM-03**: All 6 assembly SSTORE/SLOAD operations in MintModule and JackpotModule re-verified for memory model correctness
- [ ] **EVM-04**: All unchecked blocks (231 total) audited for semantic correctness beyond overflow — wrong variable, wrong operator, truncation

### Cross-System Economic Composition

- [x] **ECON-01**: Vault share inflation / donation attack re-examination — highest-value individual vector per industry data
- [x] **ECON-02**: Price discrepancy analysis between Game pricing, Vault shares, DGNRS pricing, and Degenerette odds
- [x] **ECON-03**: Circular affiliate chain analysis — self-referral loops, affiliate bonus farming
- [x] **ECON-04**: Quest reward and activity score manipulation for guaranteed jackpot/lootbox EV advantage
- [x] **ECON-05**: Boon effect stacking analysis — multiple boons compounding to unintended advantage

### Auditor Re-examination

- [x] **REEX-01**: Read-only reentrancy via stETH share rate changing during callback — verify no view function reads stale share rate
- [x] **REEX-02**: VRF subscription balance depletion as griefing vector — cost analysis for sustained depletion
- [x] **REEX-03**: stETH slashing reducing balance without transfer — verify protocol handles balance decrease
- [ ] **REEX-04**: Cross-tool convergence matrix — function-level signal combining Slither + Halmos + Foundry flags

### Synthesis

- [ ] **SYNTH-01**: C4A-format findings report with novelty justification, attack narratives, and PoC tests for any findings
- [ ] **SYNTH-02**: Top 5 most promising hypotheses investigated with detailed failure analysis (if no findings)
- [ ] **SYNTH-03**: Honest confidence assessment with explicit limitations and coverage gaps

## v6.0 Requirements

Deferred to future release.

- **DEPLOY-01**: Mainnet deployment with real VRF subscription
- **DEPLOY-02**: Operational monitoring and alerting
- **DEPLOY-03**: Incident response runbooks

## Out of Scope

| Feature | Reason |
|---------|--------|
| Gas optimization | Separate concern, not security-relevant |
| Frontend/off-chain code | Contracts only |
| Testnet-specific contracts | Mainnet is the target |
| Mock contracts | Test infrastructure only |
| Deployment scripts | Operational, not security surface |
| Re-auditing cleared vectors | v1-v4 confirmed: gas limits, VRF/RNG, basic reentrancy, MEV, access control, ETH solvency, sybil resistance, standard economic attacks |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| TOOL-01 | Phase 30 | Pending |
| TOOL-02 | Phase 30 | Pending |
| TOOL-03 | Phase 35 | Pending |
| TOOL-04 | Phase 30 | Pending |
| TOOL-05 | Phase 31 | Pending |
| COMP-01 | Phase 31 | Pending |
| COMP-02 | Phase 31 | Pending |
| COMP-03 | Phase 31 | Pending |
| COMP-04 | Phase 31 | Pending |
| PREC-01 | Phase 32 | Complete |
| PREC-02 | Phase 32 | Complete |
| PREC-03 | Phase 32 | Complete |
| PREC-04 | Phase 32 | Complete |
| TEMP-01 | Phase 33 | Pending |
| TEMP-02 | Phase 33 | Pending |
| TEMP-03 | Phase 33 | Pending |
| LIFE-01 | Phase 33 | Pending |
| LIFE-02 | Phase 33 | Pending |
| LIFE-03 | Phase 33 | Pending |
| LIFE-04 | Phase 33 | Pending |
| EVM-01 | Phase 33 | Pending |
| EVM-02 | Phase 33 | Pending |
| EVM-03 | Phase 33 | Pending |
| EVM-04 | Phase 33 | Pending |
| ECON-01 | Phase 34 | Complete |
| ECON-02 | Phase 34 | Complete |
| ECON-03 | Phase 34 | Complete |
| ECON-04 | Phase 34 | Complete |
| ECON-05 | Phase 34 | Complete |
| REEX-01 | Phase 34 | Complete |
| REEX-02 | Phase 34 | Complete |
| REEX-03 | Phase 34 | Complete |
| REEX-04 | Phase 35 | Pending |
| SYNTH-01 | Phase 35 | Pending |
| SYNTH-02 | Phase 35 | Pending |
| SYNTH-03 | Phase 35 | Pending |

**Coverage:**
- v5.0 requirements: 36 total
- Mapped to phases: 36
- Unmapped: 0

---
*Requirements defined: 2026-03-05*
*Last updated: 2026-03-05 after roadmap creation*
