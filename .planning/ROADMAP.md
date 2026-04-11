# Roadmap: Degenerus Protocol Audit

## Milestones

- ✅ **v1.0 Initial RNG Security Audit** — Phases 1-5 (shipped 2026-03-14)
- ✅ **v2.0 Adversarial Audit** — Phases 6-18 (shipped 2026-03-17)
- ✅ **v3.0-v24.1** — Phases 19-212 (shipped 2026-04-10)
- 🚧 **v25.0 Full Audit (Post-v5.0 Delta + Fresh RNG)** — Phases 213-217 (in progress)

## Phases

- [x] **Phase 213: Delta Extraction** - Produce function-level changelog, contract classifications, and interaction map for the entire v6.0-v24.1 delta (completed 2026-04-10)
- [x] **Phase 214: Adversarial Audit** - Per-function adversarial analysis of every changed/new function plus storage layout and cross-function attack chains (completed 2026-04-10)
- [x] **Phase 215: RNG Fresh Eyes** - Ground-up VRF lifecycle audit with no reliance on prior RNG conclusions (completed 2026-04-11)
- [ ] **Phase 216: Pool & ETH Accounting** - ETH conservation proof and pool mutation audit across the restructured architecture
- [ ] **Phase 217: Findings Consolidation** - Severity classification, KNOWN-ISSUES update, and regression check against all prior findings

## Phase Details

### Phase 213: Delta Extraction
**Goal**: The exact audit surface is defined — every changed, new, and deleted function is catalogued with cross-module interaction paths
**Depends on**: Nothing (first phase of milestone)
**Requirements**: DELTA-01, DELTA-02, DELTA-03
**Success Criteria** (what must be TRUE):
  1. A function-level changelog exists covering every contract modified between v5.0 (phase 103) and v24.1 (phase 212)
  2. Every contract in the codebase is classified as NEW / MODIFIED / DELETED / UNCHANGED with justification
  3. An interaction map shows all cross-module call chains between changed functions
  4. Subsequent audit phases can reference the delta extraction as their scope definition
**Plans:** 3/3 plans complete
Plans:
- [x] 213-01-PLAN.md — Classify and changelog modules + storage contracts (13 files, ~6,800 diff lines)
- [x] 213-02-PLAN.md — Classify and changelog core contracts: main, interfaces, libraries, mocks (33 files, ~3,700 diff lines)
- [x] 213-03-PLAN.md — Build cross-module interaction map and unified delta extraction document

### Phase 214: Adversarial Audit
**Goal**: Every changed/new function is proven safe against reentrancy, access control violations, integer overflow, state corruption, and composition attacks
**Depends on**: Phase 213
**Requirements**: ADV-01, ADV-02, ADV-03, ADV-04
**Success Criteria** (what must be TRUE):
  1. Every changed/new function has a per-function audit verdict (SAFE / VULNERABLE / INFO) covering reentrancy, access control, overflow, and state corruption
  2. Storage layout is verified identical across all DegenerusGameStorage inheritors via forge inspect output
  3. Cross-function attack chains are enumerated and each is classified as SAFE or flagged as a finding
  4. All changed external/public entry points have call graph audit showing reachable state mutations
**Plans:** 5/5 plans complete
Plans:
- [x] 214-01-PLAN.md — Reentrancy + CEI compliance pass across all changed/new functions
- [x] 214-02-PLAN.md — Access control + integer overflow pass across all changed/new functions
- [x] 214-03-PLAN.md — State corruption + composition attack pass across all changed/new functions
- [x] 214-04-PLAN.md — Storage layout verification via forge inspect (ADV-02)
- [x] 214-05-PLAN.md — Cross-function attack chain analysis + call graph audit (ADV-03, ADV-04)

### Phase 215: RNG Fresh Eyes
**Goal**: The VRF/RNG system is proven sound from first principles — no prior conclusions carried forward
**Depends on**: Phase 213
**Requirements**: RNG-01, RNG-02, RNG-03, RNG-04, RNG-05
**Success Criteria** (what must be TRUE):
  1. VRF request/fulfillment lifecycle is traced end-to-end with explicit proof at each stage
  2. Every RNG consumer has a backward trace proving the VRF word was unknown at input commitment time
  3. Every path between VRF request and fulfillment has an analysis of what player-controllable state can change in that window
  4. Every keccak/shift/mask producing a game outcome is traced to its VRF source word with derivation steps shown
  5. rngLocked mutual exclusion is verified across all state-changing paths that touch RNG state
**Plans:** 5/5 plans complete
Plans:
- [x] 215-01-PLAN.md — VRF lifecycle end-to-end trace (daily, lootbox, gap backfill, gameover fallback)
- [x] 215-02-PLAN.md — Backward trace from every RNG consumer proving word unknown at commitment
- [x] 215-03-PLAN.md — Commitment window analysis (player-controllable state between VRF request/fulfillment)
- [x] 215-04-PLAN.md — Word derivation verification (keccak/shift/mask/modulo to VRF source)
- [x] 215-05-PLAN.md — rngLocked mutual exclusion verification + phase synthesis

### Phase 216: Pool & ETH Accounting
**Goal**: ETH conservation is proven across the entire restructured pool architecture — no ETH can be created, destroyed, or misrouted
**Depends on**: Phase 213
**Requirements**: POOL-01, POOL-02, POOL-03
**Success Criteria** (what must be TRUE):
  1. An algebraic ETH conservation proof covers the consolidated pool architecture (all ETH in = all ETH out + all ETH held)
  2. Every SSTORE site touching prize pool / claimable pool / future pool is catalogued with mutation direction and guards
  3. Jackpot payout, redemption, and sweep flows are traced cross-module with ETH amounts verified at each handoff
**Plans:** 2/3 plans executed
Plans:
- [x] 216-01-PLAN.md — Algebraic ETH conservation proof across all 20 EF chains (POOL-01)
- [x] 216-02-PLAN.md — Pool mutation SSTORE catalogue for all ETH-touching state variables (POOL-02)
- [ ] 216-03-PLAN.md — Cross-module flow verification for jackpot, redemption, and sweep paths (POOL-03)

### Phase 217: Findings Consolidation
**Goal**: All audit findings are severity-classified and checked against prior known issues — the audit is ready for external review
**Depends on**: Phase 214, Phase 215, Phase 216
**Requirements**: FIND-01, FIND-02, FIND-03
**Success Criteria** (what must be TRUE):
  1. Every finding from phases 214-216 has a severity classification (CRITICAL / HIGH / MEDIUM / LOW / INFO) with justification
  2. KNOWN-ISSUES.md is updated with any new entries discovered during this audit
  3. All prior findings from v3.3 through v24.1 are regression-checked against current code (still fixed or still documented)
**Plans**: TBD

## Progress

**Execution Order:**
Phase 213 first. Phases 214, 215, 216 can execute in parallel after 213 completes. Phase 217 requires all three.

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 213. Delta Extraction | 3/3 | Complete    | 2026-04-10 |
| 214. Adversarial Audit | 5/5 | Complete    | 2026-04-10 |
| 215. RNG Fresh Eyes | 5/5 | Complete    | 2026-04-11 |
| 216. Pool & ETH Accounting | 2/3 | In Progress|  |
| 217. Findings Consolidation | 0/? | Not started | - |
