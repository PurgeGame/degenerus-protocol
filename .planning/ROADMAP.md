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
- ✅ **v3.4 New Feature Audit — Skim Redesign + Redemption Lootbox** — Phases 50-53 (shipped 2026-03-21)
- ✅ **v3.5 Final Polish — Comment Correctness + Gas Optimization** — Phases 54-58 (shipped 2026-03-22)
- ✅ **v3.6 VRF Stall Resilience** — Phases 59-62 (shipped 2026-03-22)
- ✅ **v3.7 VRF Path Audit** — Phases 63-67 (shipped 2026-03-22)
- ✅ **v3.8 VRF Commitment Window Audit** — Phases 68-73 (shipped 2026-03-23)
- ✅ **v3.9 Far-Future Ticket Fix** — Phases 74-80 (shipped 2026-03-23)
- ✅ **v4.0 Ticket Lifecycle & RNG-Dependent Variable Re-Audit** — Phases 81-91 (shipped 2026-03-23)
- ✅ **v4.1 Ticket Lifecycle Integration Tests** — Phases 92-94 (shipped 2026-03-24)
- ✅ **v4.2 Daily Jackpot Chunk Removal + Gas Optimization** — Phases 95-98 (shipped 2026-03-25)
- ✅ **v4.3 prizePoolsPacked Batching Optimization** — Phase 99 (closed early 2026-03-25, savings revised ~1.6M -> ~63.8K)
- ✅ **v4.4 BAF Cache-Overwrite Bug Fix + Pattern Scan** — Phases 100-102 (shipped 2026-03-25)
- ✅ **v5.0 Ultimate Adversarial Audit** — Phases 103-119 (shipped 2026-03-25)
- ✅ **v6.0 Test Suite Cleanup + Storage/Gas Fixes + DegenerusCharity** — Phases 120-125 (shipped 2026-03-26)
- ✅ **v7.0 Delta Adversarial Audit (v6.0 Changes)** — Phases 126-129 (shipped 2026-03-26)
- ✅ **v8.0 Pre-Audit Hardening** — Phases 130-134 (shipped 2026-03-27)
- ✅ **v8.1 Final Audit Prep** — Phases 135-137 (shipped 2026-03-28)
- ✅ **v9.0 Contest Dry Run** — Phases 138-140 (shipped 2026-03-28)
- ✅ **v10.0 Audit Submission Ready** — Phases 141-143 (shipped 2026-03-29)
- ✅ **v10.1 ABI Cleanup** — Phases 144-146 (shipped 2026-03-30)
- ✅ **v10.2 Ticket Mint Gas Optimization** — Phase 147 (shipped 2026-03-30, Phase 148 skipped — no change needed)
- ✅ **v10.3 Delta Adversarial Audit (v10.1 Changes)** — Phases 149-150 (shipped 2026-03-30)
- ✅ **v11.0 BURNIE Endgame Gate** — Phases 151-152 (shipped 2026-03-31)
- [ ] **v12.0 Level Quests** — Phases 153-155

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
<summary>v3.0 Full Contract Audit + Payout Specification (Phases 26-30) -- SHIPPED 2026-03-18</summary>

- [x] **Phase 26-30**: See milestone details

</details>

<details>
<summary>v3.1-v3.9 (Phases 31-80) -- SHIPPED</summary>

See individual milestone entries above.

</details>

<details>
<summary>v4.0-v4.4 (Phases 81-102) -- SHIPPED</summary>

See individual milestone entries above.

</details>

<details>
<summary>v5.0-v7.0 (Phases 103-129) -- SHIPPED</summary>

See individual milestone entries above.

</details>

<details>
<summary>v8.0-v8.1 (Phases 130-137) -- SHIPPED</summary>

See individual milestone entries above.

</details>

<details>
<summary>v9.0-v10.3 (Phases 138-150) -- SHIPPED</summary>

See individual milestone entries above.

</details>

<details>
<summary>v11.0 BURNIE Endgame Gate (Phases 151-152) -- SHIPPED 2026-03-31</summary>

- [x] **Phase 151: Endgame Flag Implementation** - 2 plans, 10 requirements (completed 2026-03-31)
- [x] **Phase 152: Delta Audit** - 2 plans, 3 requirements (completed 2026-03-31)

</details>

### v12.0 Level Quests (Phases 153-155)

**Milestone Goal:** Produce a complete design specification for a per-level quest system -- eligibility rules, mechanics, storage layout, integration touchpoints, economic impact, and gas budget -- so implementation can proceed with zero ambiguity.

- [ ] **Phase 153: Core Design** - Eligibility, mechanics, and storage specification for level quests
- [ ] **Phase 154: Integration Mapping** - Contract touchpoints and handler site identification
- [ ] **Phase 155: Economic + Gas Analysis** - BURNIE inflation modeling and gas overhead estimation

## Phase Details

<details>
<summary>Phase 151-152 Details (v11.0)</summary>

### Phase 151: Endgame Flag Implementation
**Goal**: The 30-day BURNIE ban is replaced with a drip-projection-based endgame flag that dynamically restricts BURNIE ticket purchases only when a level could mechanically be the last
**Depends on**: Phase 150 (v10.3 complete, codebase stable)
**Requirements**: REM-01, FLAG-01, FLAG-02, FLAG-03, FLAG-04, DRIP-01, DRIP-02, ENF-01, ENF-02, ENF-03
**Plans**: 2 plans
Plans:
- [x] 151-01-PLAN.md — Storage + WAD projection math + flag lifecycle in AdvanceModule
- [x] 151-02-PLAN.md — Remove 30-day ban + wire enforcement in MintModule and LootboxModule

### Phase 152: Delta Audit
**Goal**: Every function changed by the endgame flag implementation is proven safe -- no security regressions, no RNG commitment window violations, no gas ceiling breaches from drip projection math
**Depends on**: Phase 151 (implementation complete, tests passing)
**Requirements**: AUD-01, AUD-02, AUD-03
**Plans**: 2 plans
Plans:
- [x] 152-01-PLAN.md — Per-function adversarial audit + storage layout + RNG commitment window re-verification
- [x] 152-02-PLAN.md — Gas ceiling analysis for drip projection computation

</details>

### Phase 153: Core Design
**Goal**: A complete specification exists for level quest eligibility, mechanics, and storage such that an implementer can write the Solidity with zero design ambiguity
**Depends on**: Phase 152 (v11.0 complete, codebase stable)
**Requirements**: ELIG-01, ELIG-02, MECH-01, MECH-02, MECH-03, MECH-04, STOR-01, STOR-02
**Success Criteria** (what must be TRUE):
  1. The eligibility check is fully specified -- which storage slots are read for levelStreak, pass status, and ETH mint count; the exact boolean expression combining them; and the gas cost of the full eligibility evaluation
  2. The global quest roll mechanism is specified -- the exact point in advanceGame level transition where the roll occurs, which VRF entropy word is consumed, and how quest type + target are packed into storage
  3. All 8 quest types have 10x target values defined with edge case analysis for each (e.g., decimator availability across multi-day levels, ETH mint price sensitivity, quest types that may be impossible or trivially easy at 10x)
  4. Per-player progress tracking is fully specified -- storage layout, version invalidation scheme at level boundaries, completion mask, and the once-per-level creditFlip payout trigger
  5. The storage layout document specifies slot assignments, packing strategy, new SLOAD/SSTORE count, and confirms no collision with existing storage
**Plans**: 1 plan
Plans:
- [x] 153-01-PLAN.md — Complete level quest design specification (eligibility, mechanics, targets, storage, completion)

### Phase 154: Integration Mapping
**Goal**: Every contract and function that must change for level quests is identified, with the exact modification scope documented so implementation touches nothing unexpected
**Depends on**: Phase 153 (storage layout and mechanics design locked)
**Requirements**: INTG-01, INTG-02
**Success Criteria** (what must be TRUE):
  1. A contract touchpoint map exists listing every contract that needs modification, what interface changes are required, and what new cross-contract calls are introduced
  2. Every handleX() call site in DegenerusQuests.sol is listed with a specification of what level quest progress tracking logic must be added at each site
**Plans**: TBD

### Phase 155: Economic + Gas Analysis
**Goal**: The BURNIE inflation impact and gas overhead of level quests are quantified with worst-case bounds, confirming the feature is economically and computationally viable
**Depends on**: Phase 153 (storage layout needed for gas estimation, mechanics needed for economic modeling)
**Requirements**: ECON-01, ECON-02, GAS-01, GAS-02
**Success Criteria** (what must be TRUE):
  1. BURNIE inflation from 800 BURNIE/level/player is modeled for worst-case (all eligible players complete every level) and expected case, with comparison to existing BURNIE mint/burn rates
  2. The interaction between level quest payouts and the gameOverPossible drip projection is analyzed -- whether creditFlip payouts affect futurePool, and if so, whether the drip projection formula needs adjustment
  3. Gas overhead of the eligibility check in the quest handler hot path is estimated with SLOAD counts and worst-case cost
  4. Gas overhead of the level quest roll in the advanceGame level transition path is estimated, confirming it stays within the existing gas ceiling headroom
**Plans**: TBD

## Progress

**Execution Order:**
Phase 153 (sequential) -> Phase 154 + Phase 155 (can parallel after 153)

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 151. Endgame Flag Implementation | v11.0 | 2/2 | Complete | 2026-03-31 |
| 152. Delta Audit | v11.0 | 2/2 | Complete | 2026-03-31 |
| 153. Core Design | v12.0 | 1/1 | Complete   | 2026-04-01 |
| 154. Integration Mapping | v12.0 | 0/? | Not started | - |
| 155. Economic + Gas Analysis | v12.0 | 0/? | Not started | - |

## Deferred

- **FORMAL-01**: Foundry fuzz invariant tests for governance (vote weight conservation, threshold monotonicity)
- **FORMAL-02**: Formal verification of vote counting arithmetic via Halmos
- **FORMAL-03**: Monte Carlo simulation of governance outcomes under various voter distributions
- **FVER-01**: Halmos symbolic proof of CHARITY burn math (proportional ETH/stETH)
- **FVER-02**: stETH shares-based accounting for 1-2 wei rounding precision
- **FVER-03**: Foundry fuzz invariant tests for governance (vote weight conservation)
