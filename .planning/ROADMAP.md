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
- 🚧 **v6.0 Test Suite Cleanup + Storage/Gas Fixes + DegenerusCharity** — Phases 120-125 (in progress)

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

### v6.0 Test Suite Cleanup + Storage/Gas Fixes + DegenerusCharity (Phases 120-125, In Progress)

**Milestone Goal:** Fix broken tests, apply storage/gas/event fixes from audit findings, implement the new DegenerusCharity contract with yield split integration, and prune redundant test coverage.

- [x] **Phase 120: Test Suite Cleanup** - Fix broken Foundry tests and establish green baseline for both suites (completed 2026-03-26)
- [x] **Phase 121: Storage and Gas Fixes** - Delete lastLootboxRngWord, eliminate double SLOADs, fix event emission, NatSpec, deity boon, advanceBounty (completed 2026-03-26)
- [x] **Phase 122: Degenerette Freeze Fix** - Route frozen-context degenerette ETH through pending pools (I-12, isolated for BAF safety) (completed 2026-03-26)
- [x] **Phase 123: DegenerusCharity Contract** - Standalone soulbound GNRUS token with burn-for-ETH/stETH redemption and sDGNRS governance (completed 2026-03-26)
- [x] **Phase 124: Game Integration** - Wire yield surplus split, resolveLevel hook, stETH-first allowlist, and claimYield into existing contracts (completed 2026-03-26)
- [ ] **Phase 125: Test Suite Pruning** - Redundancy audit, prune duplicates, verify zero coverage loss, final green baseline

## Phase Details

### Phase 120: Test Suite Cleanup
**Goal**: Both test suites pass 100% with documented coverage, providing a trustworthy regression baseline before any contract changes
**Depends on**: Nothing (first phase -- green baseline is prerequisite for all subsequent work)
**Requirements**: TEST-01, TEST-02, TEST-03, TEST-04
**Success Criteria** (what must be TRUE):
  1. All 14 failing Foundry tests either fixed or deleted with documented justification for each deletion
  2. `forge test` runs to completion with zero failures
  3. `npx hardhat test` runs to completion with zero failures
  4. LCOV coverage reports generated for both suites showing per-contract line coverage percentages
**Plans:** 2/2 plans complete
Plans:
- [x] 120-01-PLAN.md — Fix all 14 failing Foundry tests and establish green forge test baseline
- [x] 120-02-PLAN.md — Hardhat green baseline + LCOV coverage reports for both suites

### Phase 121: Storage and Gas Fixes
**Goal**: Audit findings FIX-01 through FIX-03, FIX-05 through FIX-08 applied as mechanical contract changes with delta verification proving behavioral equivalence
**Depends on**: Phase 120 (green baseline required to detect regressions from contract changes)
**Requirements**: FIX-01, FIX-02, FIX-03, FIX-05, FIX-06, FIX-07, FIX-08
**Success Criteria** (what must be TRUE):
  1. `lastLootboxRngWord` storage declaration DELETED (not deprecated), all 3 write sites removed, the 1 read site in JackpotModule redirected to `lootboxRngWordByIndex[lootboxRngIndex - 1]`, and FIX-08 delta audit proves equivalent values across all 5 RNG paths
  2. Earlybird and early-burn paths cache `_getFuturePrizePool()` into a local variable and reuse it, eliminating the double SLOAD
  3. `RewardJackpotsSettled` event emits `futurePoolLocal + rebuyDelta` (post-reconciliation value) instead of stale `futurePoolLocal`
  4. BitPackingLib NatSpec reads "bits 152-153" (not "bits 152-154") with zero bytecode change confirmed
  5. Deity boon application checks existing tier and never downgrades any boon type; `advanceBounty` computed at payout time using current price and escalation multiplier at all 3 locations
**Plans:** 3/3 plans complete
Plans:
- [x] 121-01-PLAN.md — Delete lastLootboxRngWord + advanceBounty rewrite + NatSpec fix + delta audit
- [x] 121-02-PLAN.md — Cache double SLOAD + fix RewardJackpotsSettled event
- [x] 121-03-PLAN.md — Deity boon downgrade prevention

### Phase 122: Degenerette Freeze Fix
**Goal**: Degenerette ETH bets resolve correctly during `prizePoolFrozen` without reintroducing the BAF cache-overwrite class of bug
**Depends on**: Phase 121 (storage/gas fixes must be stable before isolating the BAF-sensitive change)
**Requirements**: FIX-04
**Success Criteria** (what must be TRUE):
  1. Degenerette ETH resolution succeeds when `prizePoolFrozen` is true, routing payouts through `_setPendingPools` (matching existing bet-placement pattern at DegeneretteModule L558-561)
  2. BAF cache-overwrite re-scan of all `_getFuturePrizePool()` read-then-write paths in DegeneretteModule confirms zero reintroduction
  3. Foundry test proves ETH conservation across a resolution-during-freeze scenario (total ETH in = total ETH out + total ETH held)
**Plans:** 1/1 plans complete
Plans:
- [x] 122-01-PLAN.md — Fix _distributePayout freeze guard + BAF re-scan + ETH conservation test

### Phase 123: DegenerusCharity Contract
**Goal**: DegenerusCharity.sol exists as a standalone tested contract at nonce N+23 with soulbound GNRUS token, proportional burn-for-ETH/stETH redemption, sDGNRS governance, and a verified deploy pipeline
**Depends on**: Phase 122 (all existing contract fixes must be complete before adding a new contract to the deploy pipeline)
**Requirements**: CHAR-01, CHAR-02, CHAR-03, CHAR-04, CHAR-05, CHAR-06, CHAR-07
**Success Criteria** (what must be TRUE):
  1. DegenerusCharity.sol deploys at nonce N+23 with soulbound GNRUS token (name="Degenerus Charity", symbol="GNRUS", 18 decimals, 1T supply to contract, no transfer/transferFrom/approve)
  2. Burning GNRUS returns proportional ETH and stETH (`amount/totalSupply` share of both assets) with minimum burn enforcement and last-holder sweep
  3. Per-level sDGNRS-weighted governance (propose, vote, resolveLevel) functions correctly with documented vote window, quorum, and tie-breaking rules
  4. ContractAddresses.sol contains CHARITY constant, and the full deploy pipeline (predictAddresses.js, patchForFoundry.js, DeployProtocol.sol) handles nonce N+23
  5. DeployCanary.t.sol passes with CHARITY address prediction matching actual deploy
**Plans:** 3/3 plans complete
Plans:
- [x] 123-01-PLAN.md — DegenerusCharity.sol contract (soulbound GNRUS + burn redemption + governance)
- [x] 123-02-PLAN.md — Deploy pipeline integration (ContractAddresses + predictAddresses + DeployProtocol + DeployCanary)
- [x] 123-03-PLAN.md — Hardhat unit tests for DegenerusCharity

### Phase 124: Game Integration
**Goal**: DegenerusCharity responds to level transitions and gameover via game hooks
**Depends on**: Phase 123 (CHARITY contract must exist and ContractAddresses must be updated before existing contracts can reference it)
**Requirements**: INTG-02
**Success Criteria** (what must be TRUE):
  1. ~~`_distributeYieldSurplus` routes charity share~~ — DONE in Phase 123 (JackpotModule lines 912-916)
  2. `_finalizeRngRequest` in AdvanceModule calls `resolveLevel` on CHARITY at level transition (direct call, no try/catch)
  3. ~~`claimWinningsStethFirst` allowlist~~ — DONE in Phase 123 (VAULT-only restriction, GNRUS uses regular claimWinnings)
  4. ~~`claimYield()` permissionless pull~~ — DROPPED (burn() lazy pull at DegenerusCharity:297 is sufficient)
  5. `handleGameOverDrain` calls `DegenerusCharity.handleGameOver()` to burn unallocated GNRUS at gameover (direct call, no try/catch)
**Plans:** 1/1 plans complete
Plans:
- [x] 124-01-PLAN.md — Wire resolveLevel hook in AdvanceModule + handleGameOver hook in GameOverModule + integration tests

### Phase 125: Test Suite Pruning
**Goal**: Redundant test coverage across Foundry and Hardhat identified and removed without losing any unique line coverage
**Depends on**: Phase 124 (all contract changes must be finalized before pruning tests against the stable codebase)
**Requirements**: PRUNE-01, PRUNE-02, PRUNE-03, PRUNE-04
**Success Criteria** (what must be TRUE):
  1. Redundancy audit document identifies every duplicate-coverage test across Foundry and Hardhat suites with justification for each deletion candidate
  2. Redundant tests deleted from the repository
  3. Coverage comparison (before vs after pruning) shows zero lost unique coverage via function-level tracing (LCOV infeasible per Phase 120 findings)
  4. Both `forge test` and `npx hardhat test` pass 100% with documented final pass/fail counts
**Plans:** 2 plans
Plans:
- [ ] 125-01-PLAN.md — Redundancy audit across all 90 test files + delete redundant tests
- [ ] 125-02-PLAN.md — Final green baseline verification + coverage comparison document

## Progress

**Execution Order:**
Phases execute sequentially: 120 -> 121 -> 122 -> 123 -> 124 -> 125.
Phase 122 (I-12 freeze fix) isolated from Phase 121 due to BAF cache-overwrite reintroduction risk.
Phase 123 (CHARITY) must precede Phase 124 (integration) because ContractAddresses must exist first.
Phase 125 (pruning) must be last since it depends on all contract changes being stable.

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 120. Test Suite Cleanup | 2/2 | Complete    | 2026-03-26 |
| 121. Storage and Gas Fixes | 3/3 | Complete    | 2026-03-26 |
| 122. Degenerette Freeze Fix | 1/1 | Complete    | 2026-03-26 |
| 123. DegenerusCharity Contract | 3/3 | Complete    | 2026-03-26 |
| 124. Game Integration | 1/1 | Complete    | 2026-03-26 |
| 125. Test Suite Pruning | 0/2 | Not started | - |

## Deferred

- **FORMAL-01**: Foundry fuzz invariant tests for governance (vote weight conservation, threshold monotonicity)
- **FORMAL-02**: Formal verification of vote counting arithmetic via Halmos
- **FORMAL-03**: Monte Carlo simulation of governance outcomes under various voter distributions
- **FVER-01**: Halmos symbolic proof of CHARITY burn math (proportional ETH/stETH)
- **FVER-02**: stETH shares-based accounting for 1-2 wei rounding precision
- **FVER-03**: Foundry fuzz invariant tests for governance (vote weight conservation)
