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
- ✅ **v24.0 Gameover Flow Audit & Fix** — Phases 203-206 (shipped 2026-04-09)
- **v24.1 Storage Layout Optimization** — Phases 207-210

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

<details>
<summary>v24.0 Gameover Flow Audit & Fix (Phases 203-206) -- SHIPPED 2026-04-09</summary>

- [x] **Phase 203: Drain Fix** - 1 plan (completed 2026-04-09)
- [x] **Phase 204: Trigger & Drain Audit** - 1 plan (completed 2026-04-09)
- [x] **Phase 205: Sweep & Interaction Audit** - 2 plans (completed 2026-04-09)
- [x] **Phase 206: Delta Audit** - 1 plan (completed 2026-04-09)

</details>

### v24.1 Storage Layout Optimization (Phases 207-210)

- [x] **Phase 207: Storage Foundation** - 2 plans (completed 2026-04-10)
- [x] **Phase 208: Module Cascade + Interfaces** - 4 plans (completed 2026-04-10)
- [x] **Phase 209: External Contracts** - 3 plans (completed 2026-04-10)
- [x] **Phase 210: Verification** - forge inspect layout check, test suites, timestamp audit (completed 2026-04-10)

## Phase Details

### Phase 207: Storage Foundation
**Goal**: All storage variable declarations, mapping keys, and slot packing in DegenerusGameStorage.sol reflect the optimized layout
**Depends on**: Nothing (first phase of v24.1)
**Requirements**: TYPE-01, TYPE-02, TYPE-06, SLOT-01, SLOT-02, SLOT-03, SLOT-05, SLOT-06, SLOT-07, SLOT-08
**Success Criteria** (what must be TRUE):
  1. All four day-index storage variables (purchaseStartDay, dailyIdx, lastDailyJackpotDay, lootboxRngIndex) are uint32
  2. All day-index mapping keys (rngWordByDay, lootboxDay, dailyHeroWagers, lootbox* mappings, deityBoonDay, deityBoonRecipientDay) are uint32
  3. ticketWriteSlot is bool, toggled via negation (not XOR), and packed into slot 0 alongside prizePoolFrozen
  4. claimablePool is uint128 and packed into slot 1 alongside currentPrizePool (32/32 bytes)
  5. Storage slot layout comment block matches the actual layout
  6. Six lootboxRng scalar variables packed into single uint256 with scaling helpers
  7. Game over state (gameOverTime + gameOverFinalJackpotPaid + finalSwept) packed into single uint256
  8. Daily jackpot traits (winningTraits + level + day) packed into single uint256
  9. Presale state (lootboxPresaleActive + lootboxPresaleMintEth) packed into single uint256
**Plans**: 2 plans
Plans:
- [x] 207-01-PLAN.md — Type narrowing, bool conversion, slot 0/1 repack, GameTimeLib
- [x] 207-02-PLAN.md — Pack lootboxRng, gameover, jackpot traits, and presale blocks

### Phase 208: Module Cascade + Interfaces
**Goal**: Every module and interface that reads or writes day-index variables or claimablePool compiles cleanly with the narrowed types
**Depends on**: Phase 207
**Requirements**: TYPE-03, TYPE-05, SLOT-04
**Success Criteria** (what must be TRUE):
  1. All function parameters, return types, local variables, and event parameters using day indices are uint32 across all game modules
  2. All claimablePool read/write sites cast or operate on uint128 without truncation risk
  3. The _maybeRequestLootboxRng inline (already committed) compiles with the new types
  4. All interface signatures (IDegenerusGame, IDegenerusGameModules, IDegenerusGameStorage, IStakedDegenerusStonk, IDegenerusQuests, IBurnieCoinflip) match updated module signatures
  5. Packed slot access uses existing _read/_write helpers (no named wrappers)
  6. forge build succeeds with zero errors for core game contracts and interfaces
**Plans**: 4 plans
Plans:
- [x] 208-01-PLAN.md — AdvanceModule + GameOverModule + DecimatorModule (packed lootboxRng/gameOver/presale + day-index)
- [x] 208-02-PLAN.md — JackpotModule + LootboxModule + DegeneretteModule (packed dailyJackpotTraits + day-index)
- [x] 208-03-PLAN.md — MintModule + WhaleModule + PayoutUtils (packed lootboxRng/presale + day-index)
- [x] 208-04-PLAN.md — DegenerusGame.sol + all interfaces + forge build

### Phase 209: External Contracts
**Goal**: All contracts outside the core game module tree compile and interoperate with the narrowed types
**Depends on**: Phase 208
**Requirements**: TYPE-04
**Success Criteria** (what must be TRUE):
  1. BurnieCoinflip, DegenerusQuests, StakedDegenerusStonk, DegenerusJackpots, and DegenerusVault use uint32 for all day-index parameters and storage
  2. View contracts use uint32 for day-index types
  3. forge build succeeds across the entire project with zero errors
**Plans**: 3 plans
Plans:
- [x] 209-01-PLAN.md — BurnieCoinflip uint48->uint32 day-index narrowing
- [x] 209-02-PLAN.md — DegenerusQuests uint48->uint32 day-index narrowing
- [x] 209-03-PLAN.md — StakedDegenerusStonk + DegenerusJackpots + DegenerusVault + DeityBoonViewer

### Phase 210: Verification
**Goal**: The entire refactor is proven correct -- no layout drift, no test regressions, no accidental timestamp narrowing
**Depends on**: Phase 209
**Requirements**: TYPE-07, VER-01, VER-02, VER-03
**Success Criteria** (what must be TRUE):
  1. forge inspect output confirms identical storage slot layout across all DegenerusGameStorage inheritors (DegenerusGame, any proxies)
  2. Foundry test suite passes with zero new failures
  3. Hardhat test suite passes with zero new failures
  4. All timestamp types (rngRequestTime, lastVrfProcessedTimestamp, gameOverTime) and GNRUS governance uint48s remain uint48 -- verified by grep
**Plans**: 2 plans
Plans:
- [x] 210-01-PLAN.md — Storage layout inspection + timestamp uint48 audit
- [x] 210-02-PLAN.md — Foundry + Hardhat test suite execution

## Progress

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 207. Storage Foundation | 2/2 | Complete   | 2026-04-10 |
| 208. Module Cascade + Interfaces | 4/4 | Complete    | 2026-04-10 |
| 209. External Contracts | 3/3 | Complete    | 2026-04-10 |
| 210. Verification | 2/2 | Complete   | 2026-04-10 |

## Deferred

- **FORMAL-01**: Foundry fuzz invariant tests for governance (vote weight conservation, threshold monotonicity)
- **FORMAL-02**: Formal verification of vote counting arithmetic via Halmos
- **FORMAL-03**: Monte Carlo simulation of governance outcomes under various voter distributions
- **FVER-01**: Halmos symbolic proof of CHARITY burn math (proportional ETH/stETH)
- **FVER-02**: stETH shares-based accounting for 1-2 wei rounding precision
- **FVER-03**: Foundry fuzz invariant tests for governance (vote weight conservation)
