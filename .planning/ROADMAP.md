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
- ✅ **v12.0 Level Quests** — Phases 153-155 (shipped 2026-04-01)
- ✅ **v13.0 Level Quests Implementation** — Phases 156-158.1 (shipped 2026-04-01)
- ✅ **v14.0 Activity Score & Quest Gas Optimization** — Phases 159-161 (shipped 2026-04-02)
- ✅ **v15.0 Delta Audit (v11.0-v14.0)** — Phases 162-167 (shipped 2026-04-02)
- ✅ **v16.0 Module Consolidation & Storage Repack** — Phases 168-172 (shipped 2026-04-03)
- ✅ **v17.0 Affiliate Bonus Cache** — Phases 173-174 (shipped 2026-04-03)
- ✅ **v17.1 Comment Correctness Sweep** — Phases 175-178 (shipped 2026-04-03)
- ✅ **v18.0 Delta Audit (v16.0-v17.1)** — Phases 179-182 (shipped 2026-04-04)
- ✅ **v19.0 Pool Accounting Fix & Sweep** — Phases 183-185 (shipped 2026-04-04)
- ✅ **v20.0 Pool Consolidation & Write Batching** — Phases 186-187 (shipped 2026-04-05)
- ✅ **v21.0 Day-Index Clock Migration** — Phases 188-189 (shipped 2026-04-05)
- ✅ **v22.0 BAF Simplification Delta Audit** — Phases 190-191 (shipped 2026-04-06)
- ✅ **v23.0 JackpotModule Delta Audit & Payout Reference** — Phases 192-193 (shipped 2026-04-06)
- **v24.0 Jackpot Gas Safety Split** — Phases 195-197

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
<summary>v11.0-v15.0 (Phases 151-167) -- SHIPPED</summary>

See individual milestone entries above.

</details>

<details>
<summary>v16.0 Module Consolidation & Storage Repack (Phases 168-172) -- SHIPPED 2026-04-03</summary>

- [x] **Phase 168: Storage Repack** - 3 plans (completed 2026-04-02)
- [x] **Phase 169: Inline rewardTopAffiliate** - 1 plan (completed 2026-04-02)
- [x] **Phase 170: Migrate runRewardJackpots** - 1 plan (completed 2026-04-03)
- [x] **Phase 171: Delete EndgameModule** - 1 plan (completed 2026-04-03)
- [x] **Phase 172: Delta Verification** - ad-hoc (completed 2026-04-03)

</details>

<details>
<summary>v17.0-v17.1 (Phases 173-178) -- SHIPPED 2026-04-03</summary>

See individual milestone entries above.

</details>

<details>
<summary>v18.0 Delta Audit (Phases 179-182) -- SHIPPED 2026-04-04</summary>

See individual milestone entries above.

</details>

<details>
<summary>v19.0 Pool Accounting Fix & Sweep (Phases 183-185) -- SHIPPED 2026-04-04</summary>

- [x] **Phase 183: Jackpot ETH Fix** - 1 plan (completed 2026-04-04)
- [x] **Phase 184: Pool Accounting Sweep** - 3 plans (completed 2026-04-04)
- [x] **Phase 185: Delta Audit** - 2 plans (completed 2026-04-04)

</details>

<details>
<summary>v20.0 Pool Consolidation & Write Batching (Phases 186-187) -- SHIPPED 2026-04-05</summary>

- [x] **Phase 186: Pool Consolidation & Write Batching** - 4 plans (completed 2026-04-05)
- [x] **Phase 187: Delta Audit** - 2 plans (completed 2026-04-05)

</details>

<details>
<summary>v21.0 Day-Index Clock Migration (Phases 188-189) -- SHIPPED 2026-04-05</summary>

- [x] **Phase 188: Clock Migration & Storage Repack** - 3 plans (completed 2026-04-05)
- [x] **Phase 189: Delta Audit** - 2 plans (completed 2026-04-05)

</details>

<details>
<summary>v22.0 BAF Simplification Delta Audit (Phases 190-191) -- SHIPPED 2026-04-06</summary>

- [x] **Phase 190: ETH Flow + Rebuy Delta + Event Audit** - 2 plans (completed 2026-04-05)
- [x] **Phase 191: Layout + Regression Testing** - 1 plan (completed 2026-04-06)

</details>

<details>
<summary>v23.0 JackpotModule Delta Audit & Payout Reference (Phases 192-193) -- SHIPPED 2026-04-06</summary>

- [x] **Phase 192: Delta Extraction & Behavioral Verification** - 2 plans (completed 2026-04-06)
- [x] **Phase 193: Gas Ceiling & Test Regression** - 1 plan (completed 2026-04-06, GAS-01 gap found: worst-case ~25M gas with 321 autorebuy winners)

</details>

### v24.0 Jackpot Gas Safety Split

**Milestone Goal:** Split daily jackpot and early-burn ETH distribution across two advanceGame calls so no single call can exceed 16M gas under worst-case conditions (321 unique autorebuy winners). Verify the fix with a true worst-case gas benchmark.

- [ ] **Phase 195: Jackpot Two-Call Split** - 2 plans
- [ ] **Phase 196: Worst-Case Gas Benchmark** - Build true worst-case test (321 unique autorebuy players, 200+ ETH pool, final jackpot day) and verify both calls stay under 16M
- [ ] **Phase 197: Payout Reference & Event Catalog** - Standalone documentation of jackpot payout flows and event emissions (post-split)

## Phase Details

### Phase 195: Jackpot Two-Call Split
**Goal**: No single advanceGame call processes more than 160 jackpot winners -- daily jackpot and early-burn ETH distribution split across two stages by lowering scaling constants so bucket counts naturally fit two-call boundaries
**Depends on**: Phase 193
**Requirements**: GAS-02, GAS-03
**Plans:** 2 plans
Plans:
- [ ] 195-01-PLAN.md — Lower scaling constants, split _processDailyEth and _distributeJackpotEth iteration, add resumeEthPool storage
- [ ] 195-02-PLAN.md — Wire STAGE_JACKPOT_ETH_RESUME (stage 8) in AdvanceModule, add resume entry point, verify test regression
**Success Criteria** (what must be TRUE):
  1. `_processDailyEth` (daily jackpot path) processes largest+solo buckets in STAGE_JACKPOT_DAILY_STARTED, then two mid buckets in a new STAGE_JACKPOT_ETH_RESUME (stage 8) on the next advanceGame call
  2. `DAILY_JACKPOT_SCALE_MAX_BPS` lowered from 66_667 to 63_600 (6.36x); `DAILY_ETH_MAX_WINNERS` lowered from 321 to 305; at max scale: largest=159, mid=95, small=50, solo=1 — call 1 ≤160, call 2 ≤145
  3. `_distributeJackpotEth` (early-burn path) uses the same two-call pattern for its 4-bucket iteration
  4. Inter-call state: original ethPool stored as uint128 in a single storage slot; non-zero = resume pending; bucket parameters recomputed from deterministic RNG word + stored ethPool
  5. Both modules compile under 24KB after changes
  6. Existing Hardhat and Foundry test suites pass with zero new regressions

### Phase 196: Worst-Case Gas Benchmark
**Goal**: A true worst-case gas benchmark proves both split calls stay under 16M gas with 321 unique autorebuy winners
**Depends on**: Phase 195
**Requirements**: GAS-04
**Success Criteria** (what must be TRUE):
  1. A Hardhat test constructs the absolute worst case: 321 unique players with autorebuy enabled, all with trait-matching tickets, pool >= 200 ETH, final jackpot day
  2. Both advanceGame calls (large+solo buckets, then mid buckets) are individually measured
  3. Neither call exceeds 16M gas
  4. The early-burn path is also measured under equivalent worst-case conditions and stays under 16M

### Phase 197: Payout Reference & Event Catalog
**Goal**: A reader can look up any jackpot type and immediately understand who wins, how much, and which events fire -- without reading contract source code
**Depends on**: Phase 195
**Requirements**: DOC-01, DOC-02
**Success Criteria** (what must be TRUE):
  1. The payout reference document covers every jackpot type (daily normal, daily x10, daily x100, trait jackpot, decimator, BAF) with winner selection criteria, payout calculation formulas, and the ETH flow from pool to recipient
  2. The event catalog lists every jackpot-related event with its Solidity signature, field descriptions, and which code paths emit it -- including the new specialized events from commit 520249a2
  3. Both documents are internally consistent with each other and with the current contract source code (post-split)

## Progress Table

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 195. Jackpot Two-Call Split | 0/2 | Not started | - |
| 196. Worst-Case Gas Benchmark | 0/TBD | Not started | - |
| 197. Payout Reference & Event Catalog | 0/TBD | Not started | - |

## Deferred

- **FORMAL-01**: Foundry fuzz invariant tests for governance (vote weight conservation, threshold monotonicity)
- **FORMAL-02**: Formal verification of vote counting arithmetic via Halmos
- **FORMAL-03**: Monte Carlo simulation of governance outcomes under various voter distributions
- **FVER-01**: Halmos symbolic proof of CHARITY burn math (proportional ETH/stETH)
- **FVER-02**: stETH shares-based accounting for 1-2 wei rounding precision
- **FVER-03**: Foundry fuzz invariant tests for governance (vote weight conservation)
