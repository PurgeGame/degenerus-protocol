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
- **v7.0 Delta Adversarial Audit (v6.0 Changes)** — Phases 126-129 (in progress)

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

<details>
<summary>v3.4 New Feature Audit — Skim Redesign + Redemption Lootbox (Phases 50-53) -- SHIPPED 2026-03-21</summary>

- [x] **Phase 50: Skim Redesign Audit** — 3 plans, 10 requirements (completed 2026-03-21)
- [x] **Phase 51: Redemption Lootbox Audit** — 4 plans, 7 requirements (completed 2026-03-21)
- [x] **Phase 52: Invariant Test Suite** — 2 plans, 3 requirements (completed 2026-03-21)
- [x] **Phase 53: Consolidated Findings** — 1 plan, 3 requirements (completed 2026-03-21)

</details>

<details>
<summary>v3.5 Final Polish — Comment Correctness + Gas Optimization (Phases 54-58) -- SHIPPED 2026-03-22</summary>

- [x] **Phase 54: Comment Correctness** — 6 plans, 4 requirements (completed 2026-03-22)
- [x] **Phase 55: Gas Optimization** — 4 plans, 4 requirements (completed 2026-03-22)
- [x] **Phase 57: Gas Ceiling Analysis** — 2 plans, 5 requirements (completed 2026-03-22)
- [x] **Phase 58: Consolidated Findings** — 1 plan, 2 requirements (completed 2026-03-22)

</details>

<details>
<summary>v3.6 VRF Stall Resilience (Phases 59-62) -- SHIPPED 2026-03-22</summary>

- [x] **Phase 59: RNG Gap Backfill Implementation** — 2 plans, 5 requirements (completed 2026-03-22)
- [x] **Phase 60: Coordinator Swap Cleanup** — 1 plan, 2 requirements (completed 2026-03-22)
- [x] **Phase 61: Stall Resilience Tests** — 1 plan, 3 requirements (completed 2026-03-22)
- [x] **Phase 62: Audit + Consolidated Findings** — 2 plans, 2 requirements (completed 2026-03-22)

</details>

<details>
<summary>v3.7 VRF Path Audit (Phases 63-67) -- SHIPPED 2026-03-22</summary>

- [x] **Phase 63: VRF Request/Fulfillment Core** — 2 plans, 4 requirements (completed 2026-03-22)
- [x] **Phase 64: Lootbox RNG Lifecycle** — 2 plans, 5 requirements (completed 2026-03-22)
- [x] **Phase 65: VRF Stall Edge Cases** — 2 plans, 7 requirements (completed 2026-03-22)
- [x] **Phase 66: VRF Path Test Coverage** — 2 plans, 4 requirements (completed 2026-03-22)
- [x] **Phase 67: Verification + Doc Sync** — 2 plans, 4 requirements (completed 2026-03-22)

</details>

<details>
<summary>v3.8 VRF Commitment Window Audit (Phases 68-73) -- SHIPPED 2026-03-23</summary>

- [x] **Phase 68: Commitment Window Inventory** - 2 plans, 3 requirements (completed 2026-03-22)
- [x] **Phase 69: Mutation Verdicts** - 2 plans, 4 requirements (completed 2026-03-22)
- [x] **Phase 70: Coinflip Commitment Window** - 2 plans, 3 requirements (completed 2026-03-22)
- [x] **Phase 71: advanceGame Day RNG Window** - 2 plans, 3 requirements (completed 2026-03-22)
- [x] **Phase 72: Ticket Queue Deep-Dive + Pattern Scan** - 2 plans, 3 requirements (completed 2026-03-23)
- [x] **Phase 73: Boon Storage Packing** - 3 plans, 6 requirements (completed 2026-03-23)

</details>

<details>
<summary>v3.9 Far-Future Ticket Fix (Phases 74-80) -- SHIPPED 2026-03-23</summary>

- [x] **Phase 74: Storage Foundation** - 1 plan, 2 requirements (completed 2026-03-23)
- [x] **Phase 75: Ticket Routing + RNG Guard** - 1 plan, 4 requirements (completed 2026-03-23)
- [x] **Phase 76: Ticket Processing Extension** - 1 plan, 3 requirements (completed 2026-03-23)
- [x] **Phase 77: Jackpot Combined Pool + TQ-01 Fix** - 1 plan, 3 requirements (completed 2026-03-23)
- [x] **Phase 78: Edge Case Handling** - 1 plan, 2 requirements (completed 2026-03-23)
- [x] **Phase 79: RNG Commitment Window Proof** - 1 plan, 1 requirement (completed 2026-03-23)
- [x] **Phase 80: Test Suite** - 2 plans, 5 requirements (completed 2026-03-23)

</details>

<details>
<summary>v4.0 Ticket Lifecycle & RNG-Dependent Variable Re-Audit (Phases 81-91) -- SHIPPED 2026-03-23</summary>

- [x] **Phase 81: Ticket Creation & Queue Mechanics** — 2 plans, 8 requirements (completed 2026-03-23)
- [x] **Phase 82: Ticket Processing Mechanics** — 2 plans, 6 requirements (completed 2026-03-23)
- [x] **Phase 83: Ticket Consumption & Winner Selection** — 2 plans, 4 requirements (completed 2026-03-23)
- [x] **Phase 84: Prize Pool Flow & currentPrizePool Deep Dive** — 1 plan, 6 requirements (completed 2026-03-23)
- [x] **Phase 85: Daily ETH Jackpot** — 2 plans, 5 requirements (completed 2026-03-23)
- [x] **Phase 86: Daily Coin + Ticket Jackpot** — 2 plans, 4 requirements (completed 2026-03-23)
- [x] **Phase 87: Other Jackpots** — 4 plans, 6 requirements (completed 2026-03-23)
- [x] **Phase 88: RNG-Dependent Variable Re-verification** — 2 plans, 4 requirements (completed 2026-03-23)
- [x] **Phase 89: Consolidated Findings** — 1 plan, 3 requirements (completed 2026-03-23)
- [x] **Phase 90: Verification Backfill** — gap closure (completed 2026-03-23)
- [x] **Phase 91: Consolidated Findings Rewrite** — gap closure (completed 2026-03-23)

</details>

<details>
<summary>v4.1 Ticket Lifecycle Integration Tests (Phases 92-94) -- SHIPPED 2026-03-24</summary>

- [x] **Phase 92: Integration Scaffold + Source Coverage** — 2 plans, 10 requirements (completed 2026-03-24)
- [x] **Phase 93: Edge Cases + Zero-Stranding Assertions** — 1 plan, 8 requirements (completed 2026-03-24)
- [x] **Phase 94: RNG Commitment Window Proofs** — 1 plan, 4 requirements (completed 2026-03-24)

</details>

<details>
<summary>v4.2 Daily Jackpot Chunk Removal + Gas Optimization (Phases 95-98) -- SHIPPED 2026-03-25</summary>

- [x] **Phase 95: Delta Verification** — 3 plans, 4 requirements (completed 2026-03-25)
- [x] **Phase 96: Gas Ceiling + Optimization** — 3 plans, 6 requirements (completed 2026-03-25)
- [x] **Phase 97: Comment Cleanup** — 1 plan, 1 requirement (completed 2026-03-25)
- [x] **Phase 98: Milestone Documentation Cleanup** — 1 plan, 2 requirements, gap closure (completed 2026-03-25)

</details>

<details>
<summary>v4.3 prizePoolsPacked Batching Optimization (Phase 99) -- CLOSED 2026-03-25 (early)</summary>

- [x] **Phase 99: Callsite Audit** — 1 plan, 2 requirements (completed 2026-03-25)
- Phases 100-102 abandoned — gas savings revised from ~1.6M to ~63.8K (0.46% of ceiling, ~$0.13/execution at 1 gwei)

</details>

<details>
<summary>v4.4 BAF Cache-Overwrite Bug Fix + Pattern Scan (Phases 100-102) -- SHIPPED 2026-03-25</summary>

- [x] **Phase 100: Protocol-Wide Pattern Scan** — 1 plan, 2 requirements (completed 2026-03-25)
- [x] **Phase 101: Bug Fix** — 1 plan, 3 requirements (completed 2026-03-25)
- [x] **Phase 102: Verification** — 2 plans, 4 requirements (completed 2026-03-25)

</details>

<details>
<summary>v5.0 Ultimate Adversarial Audit (Phases 103-119) -- SHIPPED 2026-03-25</summary>

- [x] **Phase 103: Game Router + Storage Layout** - Unit 1: DegenerusGame, DegenerusGameStorage (completed 2026-03-25)
- [x] **Phase 104: Day Advancement + VRF** - Unit 2: DegenerusGameAdvanceModule (completed 2026-03-25)
- [x] **Phase 105: Jackpot Distribution** - Unit 3: DegenerusGameJackpotModule, DegenerusGamePayoutUtils (completed 2026-03-25)
- [x] **Phase 106: Endgame + Game Over** - Unit 4: DegenerusGameEndgameModule, DegenerusGameGameOverModule (completed 2026-03-25)
- [x] **Phase 107: Mint + Purchase Flow** - Unit 5: DegenerusGameMintModule, DegenerusGameMintStreakUtils (completed 2026-03-25)
- [x] **Phase 108: Whale Purchases** - Unit 6: DegenerusGameWhaleModule (completed 2026-03-25)
- [x] **Phase 109: Decimator System** - Unit 7: DegenerusGameDecimatorModule (completed 2026-03-25)
- [x] **Phase 110: Degenerette Betting** - Unit 8: DegenerusGameDegeneretteModule (completed 2026-03-25)
- [x] **Phase 111: Lootbox + Boons** - Unit 9: DegenerusGameLootboxModule, DegenerusGameBoonModule (completed 2026-03-25)
- [x] **Phase 112: BURNIE Token + Coinflip** - Unit 10: BurnieCoin, BurnieCoinflip (completed 2026-03-25)
- [x] **Phase 113: sDGNRS + DGNRS** - Unit 11: StakedDegenerusStonk, DegenerusStonk (completed 2026-03-25)
- [x] **Phase 114: Vault + WWXRP** - Unit 12: DegenerusVault, DegenerusVaultShare, WrappedWrappedXRP (completed 2026-03-25)
- [x] **Phase 115: Admin + Governance** - Unit 13: DegenerusAdmin (completed 2026-03-25)
- [x] **Phase 116: Affiliate + Quests + Jackpots** - Unit 14: DegenerusAffiliate, DegenerusQuests, DegenerusJackpots (completed 2026-03-25)
- [x] **Phase 117: Libraries** - Unit 15: EntropyLib, BitPackingLib, GameTimeLib, JackpotBucketLib, PriceLookupLib (completed 2026-03-25)
- [x] **Phase 118: Cross-Contract Integration Sweep** - Unit 16: all contracts, meta-analysis (completed 2026-03-25)
- [x] **Phase 119: Final Deliverables** - Master findings, access control matrix, storage write map, ETH flow map (completed 2026-03-25)

</details>

<details>
<summary>v6.0 Test Suite Cleanup + Storage/Gas Fixes + DegenerusCharity (Phases 120-125) -- SHIPPED 2026-03-26</summary>

- [x] **Phase 120: Test Suite Cleanup** - Fix broken Foundry tests and establish green baseline (completed 2026-03-26)
- [x] **Phase 121: Storage and Gas Fixes** - Delete lastLootboxRngWord, eliminate double SLOADs, fix event emission, NatSpec, deity boon, advanceBounty (completed 2026-03-26)
- [x] **Phase 122: Degenerette Freeze Fix** - Route frozen-context degenerette ETH through pending pools (completed 2026-03-26)
- [x] **Phase 123: DegenerusCharity Contract** - Soulbound GNRUS token with burn redemption and sDGNRS governance (completed 2026-03-26)
- [x] **Phase 124: Game Integration** - resolveLevel hook + handleGameOver hook wired into game modules (completed 2026-03-26)
- [x] **Phase 125: Test Suite Pruning** - 13 redundant tests deleted, zero unique coverage lost (completed 2026-03-26)

</details>

### v7.0 Delta Adversarial Audit (v6.0 Changes) (In Progress)

**Milestone Goal:** Verify every v6.0 contract change is correct, safe, and matches plan intent using v5.0-style three-agent adversarial system.

- [x] **Phase 126: Delta Extraction + Plan Reconciliation** - Map every v6.0 contract change, reconcile plan-vs-reality, flag unplanned diffs (completed 2026-03-26)
- [x] **Phase 127: DegenerusCharity Full Adversarial Audit** - Three-agent audit of all Charity functions + GNRUS token + governance + game hooks + storage layout (completed 2026-03-26)
- [ ] **Phase 128: Changed Contract Adversarial Audit** - Three-agent audit of all modified functions across 11 changed contracts + storage verification
- [ ] **Phase 129: Consolidated Findings** - Master findings report with plan-drift annotations, KNOWN-ISSUES update

## Phase Details

### Phase 126: Delta Extraction + Plan Reconciliation
**Goal**: Every v6.0 contract change is mapped, cataloged, and reconciled against phase plans so the audit scope is precisely defined
**Depends on**: Nothing (first phase)
**Requirements**: DELTA-01, DELTA-02, DELTA-03, PLAN-01, PLAN-02, PLAN-03
**Success Criteria** (what must be TRUE):
  1. A complete diff inventory exists showing every changed contract file with insertion/deletion counts
  2. Every changed/new/deleted function is cataloged with its change type and originating v6.0 phase
  3. The DegenerusAffiliate unplanned change (commit a3e2341f) is traced and explained
  4. Each v6.0 phase plan's intended changes are cross-referenced against actual commits with drift documented
  5. Any commit history anomalies (reverts, merge weirdness, out-of-order commits) are identified and explained
**Plans:** 2/2 plans complete
Plans:
- [x] 126-01-PLAN.md — Delta extraction: file-level diff inventory + per-contract function catalog
- [x] 126-02-PLAN.md — Plan reconciliation: per-plan MATCH/DRIFT verdicts + anomaly analysis

### Phase 127: DegenerusCharity Full Adversarial Audit
**Goal**: DegenerusCharity.sol is proven correct and safe through exhaustive three-agent adversarial analysis covering all functions, token economics, governance, and game integration
**Depends on**: Phase 126
**Requirements**: CHAR-01, CHAR-02, CHAR-03, CHAR-04, STOR-02
**Success Criteria** (what must be TRUE):
  1. Every state-changing function in DegenerusCharity.sol has a Mad Genius attack analysis with Skeptic validation
  2. GNRUS soulbound enforcement, proportional redemption math, and supply invariants are proven correct
  3. Governance (propose/vote/resolveLevel) is verified resistant to vote manipulation, flash-loan attacks, and threshold gaming
  4. Game integration hooks (resolveLevel, handleGameOver) are verified for reentrancy safety and state consistency across module boundaries
  5. Storage layout has no slot collisions (forge inspect verified)
**Plans:** 3/3 plans complete
Plans:
- [ ] 127-01-PLAN.md — Token operations audit: soulbound enforcement, burn redemption math, supply invariants
- [ ] 127-02-PLAN.md — Governance audit: propose/vote/resolveLevel, flash-loan attacks, threshold gaming
- [ ] 127-03-PLAN.md — Game hooks + storage: handleGameOver, resolveLevel call paths, forge inspect layout verification

### Phase 128: Changed Contract Adversarial Audit
**Goal**: Every modified function across the 11 non-Charity changed contracts is verified correct through three-agent adversarial analysis with BAF-class checks and storage layout verification
**Depends on**: Phase 126
**Requirements**: AUDIT-01, AUDIT-02, AUDIT-03, AUDIT-04, STOR-01, STOR-03
**Success Criteria** (what must be TRUE):
  1. Every changed/new state-changing function across all 11 modified contracts has Mad Genius attack analysis with Skeptic validation
  2. Taskmaster confirms 100% coverage of all changed functions (zero gaps)
  3. Every function that reads then writes storage has a BAF-class cache-overwrite check with explicit verdict
  4. Storage layout changes verified via forge inspect for all modified contracts, with lastLootboxRngWord deletion confirmed zero stale references
**Plans**: TBD

### Phase 129: Consolidated Findings
**Goal**: All findings from Phases 126-128 are consolidated into a single report with C4A severity ratings, plan-drift annotations, and KNOWN-ISSUES updated
**Depends on**: Phase 127, Phase 128
**Requirements**: FIND-01, FIND-02, FIND-03
**Success Criteria** (what must be TRUE):
  1. A single findings report exists with every finding rated by C4A severity (CRITICAL/HIGH/MEDIUM/LOW/INFO)
  2. Any finding triggered by plan-vs-reality mismatch has a plan-drift annotation linking back to the Phase 126 reconciliation
  3. KNOWN-ISSUES.md is updated with any new findings from this milestone
**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 126 -> 127 -> 128 -> 129
(Phases 127 and 128 can execute in parallel after 126 completes)

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 126. Delta Extraction + Plan Reconciliation | 2/2 | Complete    | 2026-03-26 |
| 127. DegenerusCharity Full Adversarial Audit | 0/3 | Complete    | 2026-03-26 |
| 128. Changed Contract Adversarial Audit | 0/TBD | Not started | - |
| 129. Consolidated Findings | 0/TBD | Not started | - |

## Deferred

- **FORMAL-01**: Foundry fuzz invariant tests for governance (vote weight conservation, threshold monotonicity)
- **FORMAL-02**: Formal verification of vote counting arithmetic via Halmos
- **FORMAL-03**: Monte Carlo simulation of governance outcomes under various voter distributions
- **FVER-01**: Halmos symbolic proof of CHARITY burn math (proportional ETH/stETH)
- **FVER-02**: stETH shares-based accounting for 1-2 wei rounding precision
- **FVER-03**: Foundry fuzz invariant tests for governance (vote weight conservation)
