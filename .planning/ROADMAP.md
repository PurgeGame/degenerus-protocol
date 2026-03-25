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
- ✅ **v4.3 prizePoolsPacked Batching Optimization** — Phase 99 (closed early 2026-03-25, savings revised ~1.6M → ~63.8K)
- 🔄 **v4.4 BAF Cache-Overwrite Bug Fix + Pattern Scan** — Phases 100-102 (active)

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

### v4.4 BAF Cache-Overwrite Bug Fix + Pattern Scan (Phases 100-102) -- ACTIVE

- [x] **Phase 100: Protocol-Wide Pattern Scan** - 1 plan, 2 requirements (completed 2026-03-25)
- [x] **Phase 101: Bug Fix** - 1 plan, 3 requirements — Apply delta reconciliation to `runRewardJackpots`, arithmetic proof, SCAN-03 compliance (completed 2026-03-25)
- [ ] **Phase 102: Verification** - Foundry targeted test, Hardhat + Foundry regression suites, comment accuracy

## Phase Details

### Phase 100: Protocol-Wide Pattern Scan
**Goal**: Every function in the protocol that caches a storage variable locally, calls nested functions that write to the same slot, then writes back the stale local is identified and classified
**Depends on**: Nothing (first phase of v4.4)
**Requirements**: SCAN-01, SCAN-02
**Success Criteria** (what must be TRUE):
  1. A complete inventory lists every function across all contracts examined for the read-local / nested-write / stale-writeback pattern
  2. Each candidate instance carries a VULNERABLE or SAFE verdict with a plain-English reason (e.g., "nested call cannot reach this slot", "no auto-rebuy path reachable here")
  3. The known BAF instance in `runRewardJackpots` (EndgameModule) appears in the inventory and is classified VULNERABLE
  4. All storage variables that `_addClaimableEth` or any auto-rebuy path can write are enumerated so the Phase 101 fix targets the correct slots
**Plans**: 1 plan
- [x] 100-01-PLAN.md — Scan all contracts for cache-then-overwrite pattern; produce VULNERABLE/SAFE inventory + Phase 101 fix targets (completed 2026-03-25)

### Phase 101: Bug Fix
**Goal**: The cache-overwrite vulnerability in `runRewardJackpots` is eliminated and any additional vulnerable instances found in Phase 100 are fixed or documented
**Depends on**: Phase 100
**Requirements**: BAF-01, BAF-02, SCAN-03
**Success Criteria** (what must be TRUE):
  1. `runRewardJackpots` reads `futurePrizePool` from storage immediately before the final `_setFuturePrizePool` write-back, computes `rebuyDelta = storageNow - baseFuturePool`, and adds it to `futurePoolLocal` before writing
  2. An arithmetic proof shows the delta reconciliation preserves both `runRewardJackpots`' own deductions and any auto-rebuy contributions for every execution path (zero-rebuy path, single-rebuy path, multi-rebuy path)
  3. Every additional VULNERABLE instance from Phase 100 either has an equivalent fix applied or a documented fix recommendation explaining why the instance was deferred
  4. No existing function signatures or external interfaces are changed by the fix
**Plans**: 1 plan
- [x] 101-01-PLAN.md — Apply delta reconciliation fix to runRewardJackpots; arithmetic proof covering all execution paths; SCAN-03 compliance documentation

### Phase 102: Verification
**Goal**: The fix is proven correct by tests, existing test suites show zero regressions, and all modified code has accurate comments
**Depends on**: Phase 101
**Requirements**: TEST-01, TEST-02, TEST-03, CMT-01
**Success Criteria** (what must be TRUE):
  1. A Foundry test triggers `runRewardJackpots` with at least one auto-rebuy execution, then asserts that `futurePrizePool` storage contains the sum of `runRewardJackpots`' contributions plus the auto-rebuy contribution (i.e., the auto-rebuy value is not lost)
  2. The full Hardhat suite passes with zero new failures (pre-existing failures remain unchanged and are accounted for)
  3. The full Foundry suite passes with zero new failures
  4. All NatSpec and inline comments in modified functions accurately describe the post-fix behavior, including an explanation of why the delta snapshot is taken
**Plans**: TBD

## Progress Table

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 100. Protocol-Wide Pattern Scan | 1/1 | Complete    | 2026-03-25 |
| 101. Bug Fix | 1/1 | Complete   | 2026-03-25 |
| 102. Verification | 0/? | Not started | - |

## Deferred

- **FORMAL-01**: Foundry fuzz invariant tests for governance (vote weight conservation, threshold monotonicity)
- **FORMAL-02**: Formal verification of vote counting arithmetic via Halmos
- **FORMAL-03**: Monte Carlo simulation of governance outcomes under various voter distributions
