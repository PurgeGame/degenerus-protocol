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
- [ ] **v8.0 Pre-Audit Hardening** — Phases 130-134 (in progress)

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

<details>
<summary>v7.0 Delta Adversarial Audit (v6.0 Changes) (Phases 126-129) -- SHIPPED 2026-03-26</summary>

- [x] **Phase 126: Delta Extraction + Plan Reconciliation** - Map every v6.0 contract change, reconcile plan-vs-reality, flag unplanned diffs (completed 2026-03-26)
- [x] **Phase 127: DegenerusCharity Full Adversarial Audit** - Three-agent audit of all Charity functions + GNRUS token + governance + game hooks + storage layout (completed 2026-03-26)
- [x] **Phase 128: Changed Contract Adversarial Audit** - Three-agent audit of all modified functions across 11 changed contracts + storage verification (completed 2026-03-26)
- [x] **Phase 129: Consolidated Findings** - Master findings report with plan-drift annotations, KNOWN-ISSUES update (completed 2026-03-26)

</details>

### v8.0 Pre-Audit Hardening (Phases 130-134)

**Milestone Goal:** Eliminate every finding category that costs money at C4A before wardens touch the code.

- [x] **Phase 130: Bot Race** - Run Slither + 4naly3er on all production contracts, triage every finding (completed 2026-03-27)
- [x] **Phase 131: ERC-20 Compliance** - Verify ERC-20 interface compliance across all 4 token contracts (completed 2026-03-27)
- [x] **Phase 132: Event Correctness** - Systematic event audit across all 29 production contracts + GNRUS (completed 2026-03-27)
- [ ] **Phase 133: Comment Re-scan** - Delta NatSpec/inline comment sweep since v3.5 baseline
- [ ] **Phase 134: Consolidation** - Fix or document all findings, harden KNOWN-ISSUES.md for C4A

## Phase Details

### Phase 130: Bot Race
**Goal**: Every automated finding that Slither or 4naly3er would surface is triaged before wardens run the same tools
**Depends on**: Nothing (first v8.0 phase)
**Requirements**: BOT-01, BOT-02
**Success Criteria** (what must be TRUE):
  1. Slither runs clean on all production contracts with every finding categorized as fixed, documented, or false-positive
  2. 4naly3er runs clean on all production contracts with every finding categorized as fixed, documented, or false-positive
  3. A triage spreadsheet/document exists mapping each raw finding to its disposition (fix, document, or FP with reasoning)
**Plans:** 2/2 plans complete
Plans:
- [x] 130-01-PLAN.md — Slither analysis + triage (BOT-01)
- [x] 130-02-PLAN.md — 4naly3er analysis + triage (BOT-02)

### Phase 131: ERC-20 Compliance
**Goal**: All 4 token contracts pass ERC-20 interface compliance checks with no edge-case deviations that wardens could file
**Depends on**: Nothing (independent of Phase 130)
**Requirements**: ERC-01, ERC-02, ERC-03, ERC-04
**Success Criteria** (what must be TRUE):
  1. DGNRS transfer/approve/transferFrom/allowance behave per EIP-20 (zero-amount, self-transfer, max-uint approval edge cases verified)
  2. sDGNRS soulbound restrictions are documented and view functions (balanceOf, totalSupply, decimals, name, symbol) return correct values
  3. BURNIE transfer/approve/transferFrom/allowance behave per EIP-20 with edge cases verified
  4. GNRUS soulbound restrictions are documented and view functions return correct values
  5. Any intentional ERC-20 deviations are listed in KNOWN-ISSUES.md with rationale so wardens cannot file them
**Plans:** 1/1 plans complete
Plans:
- [x] 131-01-PLAN.md — ERC-20 compliance audit + consolidated report (ERC-01, ERC-02, ERC-03, ERC-04)

### Phase 132: Event Correctness
**Goal**: Every state-changing function emits correct events and no indexer-critical transition is silent
**Depends on**: Nothing (independent of Phases 130-131)
**Requirements**: EVT-01, EVT-02, EVT-03
**Success Criteria** (what must be TRUE):
  1. Every external/public state-changing function across all production contracts either emits an event or has a documented reason for not emitting
  2. Every emitted event's parameter values match the actual post-state (no stale locals, no pre-update snapshots)
  3. Off-chain indexer-critical transitions (level changes, game over, jackpot payouts, token transfers, governance actions) all emit events with sufficient data for reconstruction
**Plans**: 3 plans
Plans:
- [x] 132-01-PLAN.md — Game system event audit (DegenerusGame + 12 modules) (EVT-01, EVT-02, EVT-03)
- [x] 132-02-PLAN.md — Non-game contract event audit (tokens, admin, periphery, libraries) (EVT-01, EVT-02, EVT-03)
- [x] 132-03-PLAN.md — Consolidated report assembly + bot-race appendix (EVT-01, EVT-02, EVT-03)

### Phase 133: Comment Re-scan
**Goal**: NatSpec and inline comments across all contracts changed since v3.5 accurately describe current code behavior
**Depends on**: Nothing (independent of Phases 130-132)
**Requirements**: CMT-01, CMT-02, CMT-03
**Success Criteria** (what must be TRUE):
  1. Every NatSpec tag (@param, @return, @notice, @dev) in contracts changed since v3.5 matches current function signatures and behavior
  2. Inline comments in v6.0/v7.0-modified functions describe what the code actually does (no stale logic descriptions)
  3. Zero references to removed/renamed functions, variables, or constants remain anywhere in the codebase
**Plans**: TBD

### Phase 134: Consolidation
**Goal**: All bot-race, ERC-20, event, and comment findings are either fixed in code or comprehensively documented in KNOWN-ISSUES.md so wardens cannot file them
**Depends on**: Phases 130, 131, 132, 133
**Requirements**: BOT-03, BOT-04
**Success Criteria** (what must be TRUE):
  1. Every actionable finding from Phases 130-133 has either a code fix committed or a KNOWN-ISSUES.md entry with severity assessment and rationale
  2. KNOWN-ISSUES.md is comprehensive enough that re-running Slither/4naly3er produces zero findings not already documented
  3. A final v8.0 findings summary exists with counts by category (bot/ERC/event/comment) and disposition (fixed/documented/FP)
**Plans**: TBD

## Progress

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 130. Bot Race | 2/2 | Complete    | 2026-03-27 |
| 131. ERC-20 Compliance | 1/1 | Complete   | 2026-03-27 |
| 132. Event Correctness | 3/3 | Complete   | 2026-03-27 |
| 133. Comment Re-scan | 0/TBD | Not started | - |
| 134. Consolidation | 0/TBD | Not started | - |

## Deferred

- **FORMAL-01**: Foundry fuzz invariant tests for governance (vote weight conservation, threshold monotonicity)
- **FORMAL-02**: Formal verification of vote counting arithmetic via Halmos
- **FORMAL-03**: Monte Carlo simulation of governance outcomes under various voter distributions
- **FVER-01**: Halmos symbolic proof of CHARITY burn math (proportional ETH/stETH)
- **FVER-02**: stETH shares-based accounting for 1-2 wei rounding precision
- **FVER-03**: Foundry fuzz invariant tests for governance (vote weight conservation)
