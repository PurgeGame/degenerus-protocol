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
- ✅ **v20.0 Pool Consolidation & Write Batching** — Phases 186-187 (shipped 2026-04-08)
- ✅ **v21.0 Jackpot Two-Call Split & Skip-Split Optimization** — Phases 195-198 (shipped 2026-04-08)
- ✅ **v22.0 Delta Audit & Payout Reference Rewrite** — Phases 199-200 (shipped 2026-04-08)
- ✅ **v23.0 Redemption Coinflip Fix** — Phases 201-202 (shipped 2026-04-09)
- **v24.0 Gameover Flow Audit & Fix** — Phases 203-206 (in progress)

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
<summary>v20.0 Pool Consolidation & Write Batching (Phases 186-187) -- SHIPPED 2026-04-08</summary>

- [x] **Phase 186: Pool Consolidation & Write Batching** - 4 plans (completed 2026-04-05)
- [x] **Phase 187: Delta Audit** - 2 plans (completed 2026-04-05)

</details>

<details>
<summary>v21.0 Jackpot Two-Call Split & Skip-Split Optimization (Phases 195-198) -- SHIPPED 2026-04-08</summary>

- [x] **Phase 195: Jackpot Two-Call Split** - 1 plan (completed 2026-04-06)
- [x] **Phase 196: Post-Split Audit — Gas, Logic Parity, State, Bytecode** - 3 plans (completed 2026-04-06)
- [x] **Phase 197: Payout Reference & Event Catalog** - 1 plan (completed 2026-04-06)
- [x] **Phase 198: Skip-Split Optimization + Code Cleanup** - 1 plan (completed 2026-04-08)

</details>

<details>
<summary>v22.0 Delta Audit & Payout Reference Rewrite (Phases 199-200) -- SHIPPED 2026-04-08</summary>

- [x] **Phase 199: Delta Audit — Skip-Split + Gas Ceiling Proof** — 2 plans (completed 2026-04-08)
- [x] **Phase 200: Payout Reference Rewrite + Purchase Phase Redesign** — 2 plans + contract changes (completed 2026-04-08)

</details>

<details>
<summary>v23.0 Redemption Coinflip Fix (Phases 201-202) -- SHIPPED 2026-04-09</summary>

- [x] **Phase 201: Redemption Coinflip Accounting Fix** - 1 plan (completed 2026-04-09)
- [x] **Phase 202: Delta Audit — Redemption Accounting Verification** - 1 plan (completed 2026-04-09)

</details>

### v24.0 Gameover Flow Audit & Fix (In Progress)

**Milestone Goal:** Audit and fix the entire gameover flow end-to-end — from trigger conditions through fund distribution to final sweep — ensuring every path executes exactly once with no double-refund, re-burn, or re-latch bugs.

- [x] **Phase 203: Drain Fix** - 1 plan (completed 2026-04-09)
  - [x] 203-01-PLAN.md — Restructure handleGameOverDrain RNG gating + test verification
- [x] **Phase 204: Trigger & Drain Audit** - Verify gameover trigger conditions, entropy paths, and drain fund math (completed 2026-04-09)
- [x] **Phase 205: Sweep & Interaction Audit** - Verify post-drain sweep mechanics and cross-module gameover interactions (completed 2026-04-09)
- [x] **Phase 206: Delta Audit** - Confirm restructured drain is behaviorally equivalent and test suite clean (completed 2026-04-09)

## Phase Details

### Phase 203: Drain Fix
**Goal**: handleGameOverDrain restructured so RNG retry is a pure revert (no side effects until committed) and all one-time operations execute exactly once
**Depends on**: Nothing (first phase of v24.0)
**Requirements**: DFIX-01, DFIX-02, DFIX-03, DFIX-04, DFIX-05
**Success Criteria** (what must be TRUE):
  1. handleGameOverDrain reverts when funds > 0 but rngWordByDay[day] == 0, preventing silent no-op that skips drain
  2. Deity pass refunds, burns, gameOver/gameOverTime latch, and pool zeroing all execute only after RNG word is confirmed available
  3. No code path through handleGameOverDrain can execute any side effect (refund, burn, latch, zero) more than once per gameover
  4. The caller (_handleGameOverPath) contract flow unchanged -- it still guarantees rngWordByDay[day] != 0 before calling drain, and handles the 3-day fallback
**Plans:** 1/1 plans complete
Plans:
- [x] 203-01-PLAN.md — Restructure handleGameOverDrain RNG gating + test verification

### Phase 204: Trigger & Drain Audit
**Goal**: Every path from liveness trigger through entropy acquisition through fund distribution is verified correct
**Depends on**: Phase 203
**Requirements**: TRIG-01, TRIG-02, TRIG-03, DRNA-01, DRNA-02, DRNA-03, DRNA-04
**Success Criteria** (what must be TRUE):
  1. Liveness guard fires at the documented thresholds (365d L0, 120d L1+, safety abort) and no other conditions
  2. _gameOverEntropy resolves correctly on all three paths: VRF word already available, 3-day fallback to blockhash, and VRF pending (revert/retry)
  3. RNG word requested by gameover is stored, consumed exactly once, and not reusable by any other consumer
  4. Drain splits funds correctly (10% decimator / 90% terminal jackpot) with claimablePool accounting consistent before and after
  5. Deity pass refunds pay exactly 20 ETH/pass in FIFO order, capped by available budget, with no double-refund possible
**Plans:** 1/1 plans complete
Plans:
- [x] 204-01-PLAN.md — Trigger + drain audit (TRIG-01 through DRNA-04)

### Phase 205: Sweep & Interaction Audit
**Goal**: Post-drain operations (30-day sweep, VRF shutdown) and all module interactions with gameover state are verified correct
**Depends on**: Phase 204
**Requirements**: SWEP-01, SWEP-02, SWEP-03, SWEP-04, IXNR-01, IXNR-02, IXNR-03, IXNR-04, IXNR-05
**Success Criteria** (what must be TRUE):
  1. handleFinalSweep enforces 30-day delay from gameOverTime, with the delay non-manipulable and non-bypassable
  2. Sweep splits unclaimed funds correctly (33/33/34), transfers stETH-first with hard-revert on failure, and shuts down VRF + recovers LINK
  3. Claims work between drain and sweep (claimablePool accessible), and all claim paths blocked after finalSwept
  4. Purchases, mints, and new gameplay actions are blocked once gameOver is true
  5. Post-gameover redemption pays deterministic (non-RNG) payout and auto-rebuy bypass is confirmed active
**Plans:** 2/2 plans complete
Plans:
- [x] 205-01-PLAN.md — Sweep audit (SWEP-01 through SWEP-04)
- [x] 205-02-PLAN.md — Interaction audit (IXNR-01 through IXNR-05)

### Phase 206: Delta Audit
**Goal**: The Phase 203 code change is proven behaviorally equivalent (except the intentional revert-vs-return change) and introduces no regressions
**Depends on**: Phase 203, Phase 204, Phase 205
**Requirements**: DLTA-01, DLTA-02
**Success Criteria** (what must be TRUE):
  1. Line-by-line diff of handleGameOverDrain shows only the intended restructuring -- no logic changes beyond revert-vs-return and side-effect reordering
  2. Full test suite (Hardhat + Foundry) passes with zero new failures
**Plans:** 1/1 plans complete
Plans:
- [x] 206-01-PLAN.md — Delta audit: annotated diff + test regression check (DLTA-01, DLTA-02)

## Progress

**Execution Order:**
Phases execute in numeric order: 203 -> 204 -> 205 -> 206

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 203. Drain Fix | 1/1 | Complete    | 2026-04-09 |
| 204. Trigger & Drain Audit | 1/1 | Complete    | 2026-04-09 |
| 205. Sweep & Interaction Audit | 2/2 | Complete    | 2026-04-09 |
| 206. Delta Audit | 1/1 | Complete   | 2026-04-09 |

## Deferred

- **FORMAL-01**: Foundry fuzz invariant tests for governance (vote weight conservation, threshold monotonicity)
- **FORMAL-02**: Formal verification of vote counting arithmetic via Halmos
- **FORMAL-03**: Monte Carlo simulation of governance outcomes under various voter distributions
- **FVER-01**: Halmos symbolic proof of CHARITY burn math (proportional ETH/stETH)
- **FVER-02**: stETH shares-based accounting for 1-2 wei rounding precision
- **FVER-03**: Foundry fuzz invariant tests for governance (vote weight conservation)
