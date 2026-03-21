# Roadmap: Degenerus Protocol Audit

## Milestones

- ✅ **v1.0 Initial RNG Security Audit** — Phases 1-5 (shipped 2026-03-14)
- ✅ **v1.1 Economic Flow Audit** — Phases 6-15 (shipped 2026-03-15)
- ✅ **v1.2 RNG Security Audit (Delta)** — Phases 16-18 (shipped 2026-03-15)
- ✅ **v1.3 sDGNRS/DGNRS Split + Doc Sync** — (shipped 2026-03-16)
- ✅ **v2.0 C4A Audit Prep** — Phases 19-23 (shipped 2026-03-17)
- ✅ **v2.1 VRF Governance Audit + Doc Sync** — Phases 24-25 (shipped 2026-03-18)
- ✅ **v3.0 Full Contract Audit + Payout Specification** — Phases 26-30 (shipped 2026-03-18)
- ✅ **v3.1 Pre-Audit Polish — Comment Correctness + Intent Verification** — Phases 31-37 (shipped 2026-03-19)
- ✅ **v3.2 RNG Delta Audit + Comment Re-scan** — Phases 38-43 (shipped 2026-03-19)
- **v3.3 Gambling Burn Audit + Full Adversarial Sweep** — Phases 44-48 (in progress)

## Phases

<details>
<summary>v2.0 C4A Audit Prep (Phases 19-23) -- SHIPPED 2026-03-17</summary>

- [x] **Phase 19: Delta Security Audit -- sDGNRS/DGNRS Split** (completed 2026-03-16)
- [x] **Phase 20: Correctness Verification -- Docs, Comments, Tests** (completed 2026-03-16)
- [x] **Phase 21: Novel Attack Surface -- Deep Creative Analysis** (completed 2026-03-17)
- [x] **Phase 22: Warden Simulation + Regression Check** (completed 2026-03-17)
- [x] **Phase 23: Gas Optimization -- Dead Code Removal** (completed 2026-03-17)

</details>

<details>
<summary>v2.1 VRF Governance Audit + Doc Sync (Phases 24-25) -- SHIPPED 2026-03-18</summary>

- [x] **Phase 24: Core Governance Security Audit** — 8 plans, 26 requirements (completed 2026-03-17)
- [x] **Phase 25: Audit Doc Sync** — 4 plans, 7 requirements (completed 2026-03-17)

</details>

<details>
<summary>v3.0 Full Contract Audit + Payout Specification (Phases 26-30) -- SHIPPED 2026-03-18</summary>

- [x] **Phase 26: GAMEOVER Path Audit** — 4 plans, 9 requirements (completed 2026-03-18)
- [x] **Phase 27: Payout/Claim Path Audit** — 6 plans, 19 requirements (completed 2026-03-18)
- [x] **Phase 28: Cross-Cutting Verification** — 6 plans, 19 requirements (completed 2026-03-18)
- [x] **Phase 29: Comment/Documentation Correctness** — 6 plans, 5 requirements (completed 2026-03-18)
- [x] **Phase 30: Payout Specification Document** — 6 plans, 6 requirements (completed 2026-03-18)

</details>

<details>
<summary>v3.1 Pre-Audit Polish — Comment Correctness + Intent Verification (Phases 31-37) -- SHIPPED 2026-03-19</summary>

- [x] **Phase 31: Core Game Contracts** — 2 plans, 2 requirements (completed 2026-03-19)
- [x] **Phase 32: Game Modules Batch A** — 3 plans, 2 requirements (completed 2026-03-19)
- [x] **Phase 33: Game Modules Batch B** — 3 plans, 2 requirements (completed 2026-03-19)
- [x] **Phase 34: Token Contracts** — 2 plans, 2 requirements (completed 2026-03-19)
- [x] **Phase 35: Peripheral Contracts** — 4 plans, 2 requirements (completed 2026-03-19)
- [x] **Phase 36: Consolidated Findings** — 1 plan, 1 requirement (completed 2026-03-19)
- [x] **Phase 37: Milestone Cleanup** — 1 plan, gap closure (completed 2026-03-19)

</details>

<details>
<summary>v3.2 RNG Delta Audit + Comment Re-scan (Phases 38-43) -- SHIPPED 2026-03-19</summary>

- [x] **Phase 38: RNG Delta Security** — 2 plans, 4 requirements (completed 2026-03-19)
- [x] **Phase 39: Comment Scan -- Game Modules** — 4 plans, 1 requirement (completed 2026-03-19)
- [x] **Phase 40: Comment Scan -- Core + Token Contracts** — 2 plans, 2 requirements (completed 2026-03-19)
- [x] **Phase 41: Comment Scan -- Peripheral + Remaining** — 3 plans, 2 requirements (completed 2026-03-19)
- [x] **Phase 42: Governance Fresh Eyes** — 2 plans, 3 requirements (completed 2026-03-19)
- [x] **Phase 43: Consolidated Findings** — 1 plan, 2 requirements (completed 2026-03-19)

</details>

### v3.3 Gambling Burn Audit + Full Adversarial Sweep (In Progress)

- [ ] **Phase 44: Delta Audit + Redemption Correctness** - Verify gambling burn code changes for value integrity, state machine correctness, and cross-contract consistency
- [ ] **Phase 45: Invariant Test Suite** - Foundry invariant tests encoding corrected invariants for the redemption system
- [ ] **Phase 46: Adversarial Sweep + Economic Analysis** - Full 29-contract warden simulation, composability attacks, and rational actor strategy analysis
- [ ] **Phase 47: Gas Optimization** - Dead variable elimination, storage packing, and gas baseline for redemption functions
- [ ] **Phase 48: Documentation Sync** - NatSpec correctness for changed files and full audit doc sync

## Phase Details

### Phase 44: Delta Audit + Redemption Correctness
**Goal**: Every code change in the 6 gambling burn files is verified for value integrity and state machine correctness -- all research-flagged findings (CP-08, CP-06, Seam-1, CP-02, CP-07) are confirmed or refuted with severity classifications
**Depends on**: Nothing (first phase of v3.3)
**Requirements**: DELTA-01, DELTA-02, DELTA-03, DELTA-04, DELTA-05, DELTA-06, DELTA-07, CORR-01, CORR-02, CORR-03, CORR-04, CORR-05
**Success Criteria** (what must be TRUE):
  1. CP-08 (deterministic burn double-spend), CP-06 (stuck claims at game-over), and Seam-1 (DGNRS.burn() fund trap) each have a confirmed/refuted verdict with severity classification and fix recommendation
  2. CP-02 (period index zero sentinel) and CP-07 (coinflip resolution stuck-claim) each have a confirmed/refuted verdict
  3. Full redemption lifecycle (submit, resolve, claim) is traced through all contracts with each state transition verified correct
  4. Segregation solvency is proven -- reserved ETH/BURNIE never exceeds contract holdings at any step in the lifecycle
  5. CEI compliance is verified for all external call paths in claimRedemption() and every other new entry point
**Plans:** 1/3 plans executed

Plans:
- [x] 44-01-PLAN.md -- Finding verdicts for all 5 research-flagged issues (CP-08, CP-06, Seam-1, CP-02, CP-07)
- [ ] 44-02-PLAN.md -- Redemption lifecycle trace, period state machine proof, supply invariant proof
- [ ] 44-03-PLAN.md -- Accounting reconciliation, segregation solvency proof, cross-contract interaction audit, CEI verification

### Phase 45: Invariant Test Suite
**Goal**: Foundry invariant tests are passing that encode the corrected redemption system invariants, providing regression protection and adversarial state sequence coverage
**Depends on**: Phase 44 (tests must encode corrected invariants after delta findings are resolved)
**Requirements**: INV-01, INV-02, INV-03, INV-04, INV-05, INV-06, INV-07
**Success Criteria** (what must be TRUE):
  1. All 7 invariant tests pass at the default Foundry profile (256 runs, depth 128) with zero failures
  2. Handler contract correctly randomizes burn/claim/advanceGame call sequences to explore adversarial state paths
  3. Segregated ETH invariant catches any accounting drift (rounding dust bounded and documented)
  4. Supply consistency invariant verifies totalSupply correctness after arbitrary burn/claim sequences
**Plans**: TBD

### Phase 46: Adversarial Sweep + Economic Analysis
**Goal**: All 29 contracts are swept for High/Medium C4A findings from a fresh-eyes perspective, composability attacks are catalogued, and the gambling mechanism is proven economically fair with no rational actor exploits
**Depends on**: Phase 44 (delta must be clean before broad sweep), Phase 45 (invariant tests provide regression safety)
**Requirements**: ADV-01, ADV-02, ADV-03, ECON-01, ECON-02
**Success Criteria** (what must be TRUE):
  1. Warden simulation report covers all 29 contracts with explicit verdict per contract (finding or "clean")
  2. Cross-contract composability attack catalogue documents multi-contract interaction sequences tested and their outcomes
  3. Access control for all new entry points (claimCoinflipsForRedemption, burnForSdgnrs, resolveRedemptionPeriod, hasPendingRedemptions) is verified correct
  4. Rational actor strategy catalog documents timing attacks, cap manipulation, stale accumulation, and multi-address splitting with cost-benefit analysis showing no repeatable EV exploit
  5. Bank-run scenario (simultaneous mass burns near supply cap) is analyzed with outcome documented
**Plans**: TBD

### Phase 47: Gas Optimization
**Goal**: All gas optimization opportunities in the redemption system are identified, dead variables confirmed, storage packing analyzed, and actionable optimizations implemented
**Depends on**: Phase 44 (gas baseline must reflect corrected code)
**Requirements**: GAS-01, GAS-02, GAS-03, GAS-04
**Success Criteria** (what must be TRUE):
  1. All 7 new state variables in sDGNRS are confirmed needed or flagged for removal with justification
  2. Storage packing opportunities documented (e.g., redemptionPeriodIndex uint48 packing) with gas savings quantified
  3. forge snapshot baseline exists for all redemption functions
  4. Any dead variables identified in GAS-01 are removed and tests still pass
**Plans**: TBD

### Phase 48: Documentation Sync
**Goal**: All NatSpec and audit documentation accurately describes the final post-fix implementation -- no stale references, no misleading comments
**Depends on**: Phase 44, Phase 47 (NatSpec must describe final code after all changes)
**Requirements**: DOC-01, DOC-02, DOC-03, DOC-04
**Success Criteria** (what must be TRUE):
  1. NatSpec on all 6 changed files is verified correct against final implementation (every @param, @return, @dev, @notice)
  2. Bit allocation map comment exists in rngGate() documenting which bits each RNG consumer uses
  3. claimCoinflipsForRedemption error name is fixed (no longer uses misleading OnlyBurnieCoin)
  4. All 13+ audit reference docs are updated to reflect v3.3 findings and gambling burn mechanism
**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 44 -> 45 -> 46 -> 47 -> 48

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 44. Delta Audit + Redemption Correctness | 1/3 | In Progress|  |
| 45. Invariant Test Suite | 0/TBD | Not started | - |
| 46. Adversarial Sweep + Economic Analysis | 0/TBD | Not started | - |
| 47. Gas Optimization | 0/TBD | Not started | - |
| 48. Documentation Sync | 0/TBD | Not started | - |

## Deferred (v3.3+)

- **FORMAL-01**: Foundry fuzz invariant tests for governance (vote weight conservation, threshold monotonicity)
- **FORMAL-02**: Formal verification of vote counting arithmetic via Halmos
- **FORMAL-03**: Monte Carlo simulation of governance outcomes under various voter distributions

---
*Last updated: 2026-03-20 after Phase 44 planning*
