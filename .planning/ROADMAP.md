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
- ✅ **v3.3 Gambling Burn Audit + Full Adversarial Sweep** — Phases 44-49 (shipped 2026-03-21)

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

<details>
<summary>v3.3 Gambling Burn Audit + Full Adversarial Sweep (Phases 44-49) -- SHIPPED 2026-03-21</summary>

- [x] **Phase 44: Delta Audit + Redemption Correctness** — 3 plans, 12 requirements (completed 2026-03-21)
- [x] **Phase 45: Invariant Test Suite** — 3 plans, 7 requirements (completed 2026-03-21)
- [x] **Phase 46: Adversarial Sweep + Economic Analysis** — 3 plans, 5 requirements (completed 2026-03-21)
- [x] **Phase 47: Gas Optimization** — 2 plans, 4 requirements (completed 2026-03-21)
- [x] **Phase 48: Documentation Sync** — 2 plans, 4 requirements (completed 2026-03-21)
- [x] **Phase 49: Milestone Cleanup** — 2 plans, gap closure (completed 2026-03-21)

</details>

### v3.4 New Feature Audit — Skim Redesign + Redemption Lootbox

- [x] **Phase 50: Skim Redesign Audit** - Verify correctness and economic soundness of the 5-step futurepool skim pipeline (completed 2026-03-21)
- [x] **Phase 51: Redemption Lootbox Audit** - Verify correctness of 50/50 redemption split, daily cap, and cross-contract access control (completed 2026-03-21)
- [x] **Phase 52: Invariant Test Suite** - Fuzz invariants proving skim conservation, take cap, and redemption lootbox split (completed 2026-03-21)
- [x] **Phase 53: Consolidated Findings** - Master findings table with all v3.4 discoveries plus outstanding v3.2 LOW/INFO (completed 2026-03-21)

## Phase Details

### Phase 50: Skim Redesign Audit
**Goal**: The 5-step futurepool skim pipeline in `_applyTimeBasedFutureTake` is proven correct -- all arithmetic is safe, bit-field consumption has no overlap, and ETH conservation holds under all inputs
**Depends on**: Nothing (first phase of v3.4; builds on existing 22-test fuzz suite in FuturepoolSkim.t.sol)
**Requirements**: SKIM-01, SKIM-02, SKIM-03, SKIM-04, SKIM-05, SKIM-06, SKIM-07, ECON-01, ECON-02, ECON-03
**Success Criteria** (what must be TRUE):
  1. Every arithmetic step in the 5-step pipeline has a written verdict (safe / finding) with line-ref evidence -- overshoot surcharge monotonicity+cap, ratio adjustment bounds, bit-field isolation, triangular variance underflow safety, and 80% take cap
  2. ETH conservation (nextPool + futurePool + yieldAccumulator = constant) is proven to hold across the entire function for all input combinations
  3. Insurance skim is confirmed to be exactly 1% of nextPoolBefore with no rounding edge cases that leak or create ETH
  4. Overshoot surcharge is confirmed to accelerate futurepool growth during fast levels, stall escalation still functions without growth adjustment, and level 1 (lastPool=0) produces no division-by-zero or unintended surcharge
**Plans:** 3/3 plans complete

Plans:
- [x] 50-01-PLAN.md — Pipeline arithmetic verdicts (SKIM-01 through SKIM-05)
- [x] 50-02-PLAN.md — ETH conservation proof + insurance skim precision (SKIM-06, SKIM-07)
- [x] 50-03-PLAN.md — Economic analysis: overshoot, stall escalation, level-1 safety (ECON-01 through ECON-03)

### Phase 51: Redemption Lootbox Audit
**Goal**: The 50/50 sDGNRS redemption lootbox split is proven correct -- routing, daily cap enforcement, slot packing, and cross-contract access control are all verified
**Depends on**: Nothing (independent of Phase 50; separate contracts and feature)
**Requirements**: REDM-01, REDM-02, REDM-03, REDM-04, REDM-05, REDM-06, REDM-07
**Success Criteria** (what must be TRUE):
  1. The 50/50 split correctly routes half to direct ETH redemption and half to lootbox, and gameOver burns bypass the lootbox entirely (pure ETH/stETH, no BURNIE)
  2. The 160 ETH daily cap per wallet is enforced correctly with no bypass via multiple calls, timestamp manipulation, or cross-day boundary abuse
  3. PendingRedemption slot packing (uint96+uint96+uint48+uint16=256) is verified correct with no bit overlap or truncation, and activity score snapshot at submission is immutable through resolution
  4. Cross-contract call chain sDGNRS -> Game -> LootboxModule has correct access control at every hop, and lootbox reclassification performs no ETH transfer (internal accounting only)
**Plans:** 4/4 plans complete

Plans:
- [x] 51-01-PLAN.md — 50/50 split routing + gameOver bypass verdicts (REDM-01, REDM-02)
- [x] 51-02-PLAN.md — Daily cap enforcement + slot packing verification (REDM-03, REDM-05)
- [x] 51-03-PLAN.md — Activity score snapshot immutability (REDM-04)
- [x] 51-04-PLAN.md — Cross-contract access control + lootbox reclassification (REDM-06, REDM-07)

### Phase 52: Invariant Test Suite
**Goal**: Foundry fuzz invariant tests provide automated proof that the skim pipeline and redemption lootbox maintain their core safety properties under randomized inputs
**Depends on**: Phase 50, Phase 51 (audit understanding informs invariant design and edge case targeting)
**Requirements**: INV-01, INV-02, INV-03
**Success Criteria** (what must be TRUE):
  1. Skim conservation invariant passes: nextPool + futurePool + yieldAccumulator is constant across all fuzzed inputs (extends existing FuturepoolSkim.t.sol suite)
  2. Take cap invariant passes: skim take never exceeds 80% of nextPool across all fuzzed inputs
  3. Redemption lootbox split invariant passes: direct ETH + lootbox ETH sums to total rolled ETH for every redemption resolution
**Plans:** 2/2 plans complete

Plans:
- [x] 52-01-PLAN.md — Skim conservation + take cap fuzz invariants (INV-01, INV-02)
- [x] 52-02-PLAN.md — Redemption lootbox split invariant: arithmetic + lifecycle (INV-03)

### Phase 53: Consolidated Findings
**Goal**: All v3.4 audit findings are consolidated into a single master table sorted by severity, ready for manual triage before C4A submission
**Depends on**: Phase 50, Phase 51, Phase 52 (all findings must be gathered first)
**Requirements**: FIND-01, FIND-02, FIND-03
**Success Criteria** (what must be TRUE):
  1. Every finding from Phases 50-52 appears in the master table with severity, contract, line reference, and recommendation
  2. Outstanding v3.2 LOW/INFO findings are included in the master list for completeness (not re-audited, just consolidated)
  3. Master table is sorted by severity (HIGH > MEDIUM > LOW > INFO) for efficient manual triage
**Plans:** 1/1 plans complete

Plans:
- [x] 53-01-PLAN.md — Master findings table with v3.4 discoveries + v3.2 carry-forward + validation

## Progress

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 50. Skim Redesign Audit | 3/3 | Complete    | 2026-03-21 |
| 51. Redemption Lootbox Audit | 4/4 | Complete    | 2026-03-21 |
| 52. Invariant Test Suite | 2/2 | Complete    | 2026-03-21 |
| 53. Consolidated Findings | 1/1 | Complete   | 2026-03-21 |

## Deferred

- **FORMAL-01**: Foundry fuzz invariant tests for governance (vote weight conservation, threshold monotonicity)
- **FORMAL-02**: Formal verification of vote counting arithmetic via Halmos
- **FORMAL-03**: Monte Carlo simulation of governance outcomes under various voter distributions
- Storage packing implementation — 3 opportunities documented in v3.3 gas analysis

---
*Last updated: 2026-03-21 after Phase 53 planning (1 plan created)*
