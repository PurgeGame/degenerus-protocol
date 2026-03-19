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
- **v3.2 RNG Delta Audit + Comment Re-scan** — Phases 38-43 (in progress)

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

### v3.2 RNG Delta Audit + Comment Re-scan (In Progress)

- [x] **Phase 38: RNG Delta Security** - Audit all RNG-adjacent code changes for manipulation vectors (completed 2026-03-19)
- [x] **Phase 39: Comment Scan -- Game Modules** - Fresh comment audit across all 12 game module files (completed 2026-03-19)
- [x] **Phase 40: Comment Scan -- Core + Token Contracts** - Fresh comment audit of core game and token contracts (completed 2026-03-19)
- [x] **Phase 41: Comment Scan -- Peripheral + Remaining** - Fresh comment audit of peripheral and utility contracts (completed 2026-03-19)
- [ ] **Phase 42: Governance Fresh Eyes** - Independent sanity check of VRF governance from fresh perspective
- [ ] **Phase 43: Consolidated Findings** - Cross-cutting patterns and final deliverable with severity classification

## Phase Details

### Phase 38: RNG Delta Security
**Goal**: All RNG-adjacent code changes since v3.1 are verified safe -- no new manipulation windows, no exploitable state
**Depends on**: Nothing (first phase of v3.2)
**Requirements**: RNG-01, RNG-02, RNG-03, RNG-04
**Success Criteria** (what must be TRUE):
  1. rngLocked removal from coinflip claim paths is verified safe -- carry ETH never enters claimable pool during resolution
  2. BAF epoch-based guard is confirmed sufficient as sole coinflip claim protection (no bypass via timing or reentrancy)
  3. Persistent decimator claims across rounds do not create state that an RNG-aware attacker can exploit
  4. Cross-contract RNG data flow under all recent changes combined produces no new manipulation vectors
  5. Each finding is documented with severity classification and attack scenario (or explicit "safe" verdict with reasoning)
**Plans:** 2/2 plans complete
Plans:
- [ ] 38-01-PLAN.md — Carry isolation trace + formal invariant (RNG-01) and BAF guard analysis (RNG-02)
- [ ] 38-02-PLAN.md — Decimator claim persistence correctness (RNG-03) and cross-contract dependency matrix (RNG-04)

### Phase 39: Comment Scan -- Game Modules
**Goal**: Every comment in all 12 game module files is verified accurate against current code behavior
**Depends on**: Nothing (independent of Phase 38)
**Requirements**: CMT-01
**Success Criteria** (what must be TRUE):
  1. All NatSpec tags (@param, @return, @dev, @notice) in 12 module files match actual function signatures and behavior
  2. All inline comments accurately describe the code they annotate (no stale references to removed features)
  3. All block comments and section headers reflect current contract structure
  4. All 31 v3.1 fixes verified correct in working tree
  5. Findings list produced with file, line, what/why/suggestion for each discrepancy
**Plans:** 4/4 plans complete
Plans:
- [ ] 39-01-PLAN.md — JackpotModule comment audit (2,792 lines, 6 v3.1 fixes)
- [ ] 39-02-PLAN.md — DecimatorModule + DegeneretteModule + MintModule comment audit (3,358 lines, 11 v3.1 fixes)
- [ ] 39-03-PLAN.md — LootboxModule + AdvanceModule comment audit (3,160 lines, 6 v3.1 fixes)
- [ ] 39-04-PLAN.md — Small modules audit (2,128 lines, 8 v3.1 fixes) + consolidate final deliverable

### Phase 40: Comment Scan -- Core + Token Contracts
**Goal**: Every comment in core game contracts and token contracts is verified accurate
**Depends on**: Nothing (independent)
**Requirements**: CMT-02, CMT-03
**Success Criteria** (what must be TRUE):
  1. DegenerusGame, GameStorage, and DegenerusAdmin comments all verified against current code (including post-governance changes)
  2. BurnieCoin, DegenerusStonk, StakedDegenerusStonk, and WrappedWrappedXRP comments all verified (including sDGNRS/DGNRS split changes)
  3. NatSpec on all external/public functions matches actual parameters, return values, and behavior
  4. Findings list produced with per-contract grouping
**Plans:** 2/2 plans complete
Plans:
- [ ] 40-01-PLAN.md — Core game contracts scan (DegenerusGame, GameStorage, DegenerusAdmin)
- [ ] 40-02-PLAN.md — Token contracts scan (BurnieCoin, DegenerusStonk, StakedDegenerusStonk, WrappedWrappedXRP)

### Phase 41: Comment Scan -- Peripheral + Remaining
**Goal**: Every comment in peripheral and remaining utility contracts is verified accurate
**Depends on**: Nothing (independent)
**Requirements**: CMT-04, CMT-05
**Success Criteria** (what must be TRUE):
  1. BurnieCoinflip, DegenerusVault, DegenerusAffiliate, DegenerusQuests, DegenerusJackpots comments all verified
  2. DeityPass, TraitUtils, DeityBoonViewer, ContractAddresses, Icons32Data comments all verified
  3. All interface files (IBurnieCoinflip, IDegenerusGame) NatSpec matches implementation
  4. Findings list produced with per-contract grouping
**Plans:** 3/3 plans complete
Plans:
- [ ] 41-01-PLAN.md — Heavy-change peripheral (BurnieCoinflip, DegenerusQuests, DegenerusJackpots)
- [ ] 41-02-PLAN.md — Light-change peripheral + interfaces (DegenerusVault, DegenerusAffiliate, IBurnieCoinflip, IDegenerusGame)
- [ ] 41-03-PLAN.md — Remaining/utility (DeityPass, TraitUtils, DeityBoonViewer, ContractAddresses, Icons32Data)

### Phase 42: Governance Fresh Eyes
**Goal**: VRF governance flow independently verified from fresh perspective -- all attack surfaces catalogued and edge cases evaluated
**Depends on**: Phase 38 (RNG context informs governance RNG interactions)
**Requirements**: GOV-01, GOV-02, GOV-03
**Success Criteria** (what must be TRUE):
  1. Complete attack surface catalogue for VRF swap governance (proposal, voting, execution, timelock, veto paths)
  2. Timing attack scenarios re-evaluated against current code (including any post-v2.1 changes)
  3. Cross-contract governance interactions verified (DegenerusAdmin, GameStorage, AdvanceModule, DegenerusStonk state consistency)
  4. Any new findings documented with severity; known issues (WAR-01, WAR-02, WAR-06) confirmed still accurate
**Plans**: TBD

### Phase 43: Consolidated Findings
**Goal**: All findings from phases 38-42 consolidated into deliverable with cross-cutting patterns and severity classification
**Depends on**: Phase 38, Phase 39, Phase 40, Phase 41, Phase 42
**Requirements**: CMT-06, CMT-07
**Success Criteria** (what must be TRUE):
  1. Cross-cutting patterns identified across all contract groups (recurring NatSpec issues, systematic comment drift, pattern-level fixes)
  2. Master findings table with severity classification (LOW/INFO), per-contract counts, and pattern tags
  3. Deliverable is consumable by protocol team for pre-C4A fix decisions
**Plans**: TBD

## Progress

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 38. RNG Delta Security | 2/2 | Complete   | 2026-03-19 |
| 39. Comment Scan -- Game Modules | 4/4 | Complete   | 2026-03-19 |
| 40. Comment Scan -- Core + Token | 2/2 | Complete    | 2026-03-19 |
| 41. Comment Scan -- Peripheral + Remaining | 3/3 | Complete    | 2026-03-19 |
| 42. Governance Fresh Eyes | 0/TBD | Not started | - |
| 43. Consolidated Findings | 0/TBD | Not started | - |

## Deferred (v3.3+)

- **FUZZ-01**: Foundry fuzz invariant tests for governance (vote weight conservation, threshold monotonicity)
- **FUZZ-02**: Formal verification of vote counting arithmetic via Halmos
- **FUZZ-03**: Monte Carlo simulation of governance outcomes under various voter distributions

---
*Last updated: 2026-03-19 after Phase 41 planning*
