# Roadmap: Degenerus Protocol Audit

## Milestones

- ✅ **v1.0 Initial RNG Security Audit** — Phases 1-5 (shipped 2026-03-14)
- ✅ **v2.0 Adversarial Audit** — Phases 6-18 (shipped 2026-03-17)
- ✅ **v3.0-v24.1** — Phases 19-212 (shipped 2026-04-10)
- ✅ **v25.0 Full Audit (Post-v5.0 Delta + Fresh RNG)** — Phases 213-217 (shipped 2026-04-11)
- ✅ **v26.0 Bonus Jackpot Split** — Phases 218-219 (shipped 2026-04-12)
- ✅ **v27.0 Call-Site Integrity Audit** — Phases 220-223 (shipped 2026-04-13)
- ✅ **v28.0 Database & API Intent Alignment Audit** — Phases 224-229 (shipped 2026-04-15) — see [milestones/v28.0-ROADMAP.md](milestones/v28.0-ROADMAP.md)
- 🚧 **v29.0 Post-v27 Contract Delta Audit** — Phases 230-236 (in progress)

## Phases

<details>
<summary>✅ v25.0 Full Audit (Phases 213-217) — SHIPPED 2026-04-11</summary>

- [x] Phase 213: Delta Extraction (3/3 plans) — completed 2026-04-10
- [x] Phase 214: Adversarial Audit (5/5 plans) — completed 2026-04-10
- [x] Phase 215: RNG Fresh Eyes (5/5 plans) — completed 2026-04-11
- [x] Phase 216: Pool & ETH Accounting (3/3 plans) — completed 2026-04-11
- [x] Phase 217: Findings Consolidation (2/2 plans) — completed 2026-04-11

</details>

<details>
<summary>✅ v26.0 Bonus Jackpot Split (Phases 218-219) — SHIPPED 2026-04-12</summary>

- [x] Phase 218: Bonus Split Implementation (2/2 plans) — completed 2026-04-12
- [x] Phase 219: Delta Audit & Gas Verification (2/2 plans) — completed 2026-04-12

</details>

<details>
<summary>✅ v27.0 Call-Site Integrity Audit (Phases 220-223) — SHIPPED 2026-04-13</summary>

- [x] Phase 220: Delegatecall Target Alignment (2/2 plans) — completed 2026-04-12
- [x] Phase 221: Raw Selector & Calldata Audit (2/2 plans) — completed 2026-04-12
- [x] Phase 222: External Function Coverage Gap (3/3 plans) — completed 2026-04-13
- [x] Phase 223: Findings Consolidation (2/2 plans) — completed 2026-04-13

</details>

<details>
<summary>✅ v28.0 Database & API Intent Alignment Audit (Phases 224-229) — SHIPPED 2026-04-15</summary>

- [x] Phase 224: API Route & OpenAPI Alignment (1/1 plans) — completed 2026-04-13
- [x] Phase 225: API Handler Behavior & Validation Schema Alignment (3/3 plans) — completed 2026-04-13
- [x] Phase 226: Schema, Migration & Orphan Audit (4/4 plans) — completed 2026-04-15
- [x] Phase 227: Indexer Event Processing Correctness (3/3 plans) — completed 2026-04-15
- [x] Phase 228: Cursor, Reorg & View Refresh State Machines (2/2 plans) — completed 2026-04-15
- [x] Phase 229: Findings Consolidation (2/2 plans) — completed 2026-04-15

**Findings:** 69 total (0 CRITICAL/HIGH/MEDIUM, 27 LOW, 42 INFO). See [milestones/v28.0-ROADMAP.md](milestones/v28.0-ROADMAP.md) and [audit/FINDINGS-v28.0.md](../audit/FINDINGS-v28.0.md).

</details>

<details open>
<summary>🚧 v29.0 Post-v27 Contract Delta Audit (Phases 230-236) — IN PROGRESS</summary>

**Milestone Goal:** Full adversarial audit of every `contracts/` change since the v27.0 baseline (2026-04-13). v28.0 audited the sibling `database/` repo only; contracts have been unaudited for 10 commits touching 12 files across entropy passthrough, earlybird rewrites, decimator changes, BAF sentinel, quest wei fix, and boon exposure. Read-only audit — no `contracts/` or `test/` writes this milestone. Deliverable: `audit/FINDINGS-v29.0.md`.

- [x] **Phase 230: Delta Extraction & Scope Map** - Function-level changelog, cross-module interaction map, and interface-drift catalog across the 10-commit / 12-file delta — completed 2026-04-17
- [ ] **Phase 231: Earlybird Jackpot Audit** - Adversarial audit of the purchase-phase finalize refactor and the trait-alignment rewrite + combined state-machine verification
- [ ] **Phase 232: Decimator Audit** - Adversarial audit of burn-key-by-resolution-level, event emission, and terminal-claim passthrough
- [ ] **Phase 233: Jackpot/BAF + Entropy Audit** - Adversarial audit of `traitId=420` sentinel, explicit entropy passthrough, and cross-path bonus-trait consistency
- [ ] **Phase 234: Quests / Boons / Misc Audit** - Adversarial audit of `mint_ETH` wei-credit fix, `boonPacked` exposure, and incidental `BurnieCoin.sol` change
- [ ] **Phase 235: Conservation + RNG Commitment Re-Proof + Phase Transition** - ETH + BURNIE conservation across the delta, RNG commitment-window re-proof for every new consumer, and phase-transition RNG lock removal audit
- [ ] **Phase 236: Regression + Findings Consolidation** - v25.0/v26.0/v27.0 regression sweep and `audit/FINDINGS-v29.0.md` consolidation

## Phase Details

### Phase 230: Delta Extraction & Scope Map
**Goal**: The exact v29.0 audit surface is defined — every changed/new/deleted function is catalogued with cross-module interaction paths and interface drift resolved
**Depends on**: Nothing (first phase of v29.0)
**Requirements**: DELTA-01, DELTA-02, DELTA-03
**Success Criteria** (what must be TRUE):
  1. A function-level changelog lists every changed, added, or deleted function across the 10 commits mapped to owning contract, file, and commit SHA
  2. A cross-module interaction map documents every new or modified call chain that crosses module boundaries within the 12 in-scope files
  3. An interface-drift catalog compares `IDegenerusGame`, `IDegenerusQuests`, and `IDegenerusGameModules` against their implementers with a PASS/FAIL verdict per signature
  4. Downstream audit phases (231-234) can reference this phase as their authoritative scope definition with no additional discovery required
**Plans**: 1 plan — lightweight scope map modeled on 213-03 / 224-01 catalog pattern
- [x] 230-01-PLAN.md — Produce 230-01-DELTA-MAP.md: function-level changelog + cross-module interaction map + interface drift catalog + consumer index covering the 10-commit / 12-file delta (DELTA-01/02/03) — completed 2026-04-17

### Phase 231: Earlybird Jackpot Audit
**Goal**: Every earlybird-related change (purchase-phase finalize refactor, trait-alignment rewrite) is proven safe — budget conservation, CEI, entropy independence, and combined state-machine behavior all verified
**Depends on**: Phase 230
**Requirements**: EBD-01, EBD-02, EBD-03
**Success Criteria** (what must be TRUE):
  1. The purchase-phase finalize refactor (`f20a2b5e`) has a per-function adversarial verdict covering level-transition finalization, unified award call, storage read/write ordering, CEI, and reentrancy
  2. The trait-alignment rewrite (`20a951df`) has a per-function adversarial verdict covering bonus-trait parity with the coin jackpot, salt-space isolation, fixed-level queueing at `lvl+1`, and futurePool→nextPool budget conservation
  3. The combined earlybird state machine (purchase-phase finalize + jackpot-phase run) is traced end-to-end with no double-spend, no orphaned reserves, and no missed emissions at any transition
  4. Every verdict cites commit SHA + file:line and is added to the Phase 236 finding candidate pool
**Plans**: 3 plans — one per EBD requirement (per CONTEXT.md D-01 + auto-rule 6)
- [x] 231-01-PLAN.md — Produce 231-01-AUDIT.md: per-function verdict table for EBD-01 earlybird purchase-phase finalize refactor (`f20a2b5e`) — CEI, reentrancy, storage ordering, budget conservation at level-transition dump, signature-contraction correctness, gas delta, double/zero-award regression — completed 2026-04-17 (21 PASS verdicts across 9 target functions; zero FAIL/DEFER)
- [x] 231-02-PLAN.md — Produce 231-02-AUDIT.md: per-function verdict table for EBD-02 trait-alignment rewrite (`20a951df`) — bonus-trait parity with coin jackpot, salt-space isolation, `lvl+1` queue fix, futurePool → nextPool CEI (algebraic pool conservation handed off to Phase 235 CONS-01) — completed 2026-04-17 (6 PASS verdicts across 2 target functions; zero FAIL/DEFER)
- [ ] 231-03-PLAN.md — Produce 231-03-AUDIT.md: combined earlybird state machine end-to-end path walk for EBD-03 — normal / skip-split / gameover transitions, no double-spend, no orphaned reserves, no missed emissions, cross-commit invariant (pool dumped = pool consumed)

### Phase 232: Decimator Audit
**Goal**: Every decimator-related change (burn-key refactor, event emission, terminal-claim passthrough) is proven safe — key alignment, event correctness, and access-control semantics all verified
**Depends on**: Phase 230
**Requirements**: DCM-01, DCM-02, DCM-03
**Success Criteria** (what must be TRUE):
  1. The burn-key refactor (`3ad0f8d3`) is audited — every read site uses the matching resolution-level key, pro-rata share calculation has no off-by-one, and the consolidated jackpot block has correct ordering
  2. The event emission change (`67031e7d`) is audited — `DecimatorClaimed` and `TerminalDecimatorClaimed` fire at the correct CEI position with correct args, and the emissions are compatible with the v28.0 indexer event surface
  3. The `claimTerminalDecimatorJackpot` passthrough (`858d83e4`) is audited — caller restriction enforced, no reentrancy, no privilege escalation, parameters passed through unchanged to the module
  4. Every verdict cites commit SHA + file:line and is added to the Phase 236 finding candidate pool
**Plans**: TBD (expected 2-3 plans, one per DCM requirement)

### Phase 233: Jackpot/BAF + Entropy Audit
**Goal**: Every jackpot-side and entropy-passthrough change is proven safe — the `traitId=420` sentinel, the explicit entropy passthrough, and cross-path bonus-trait consistency all verified
**Depends on**: Phase 230
**Requirements**: JKP-01, JKP-02, JKP-03
**Success Criteria** (what must be TRUE):
  1. The BAF `traitId=420` sentinel (`104b5d42`) is audited — no collision with real trait IDs (0-255 domain), event consumers tolerate the sentinel, and no downstream branch treats `420` as a real trait
  2. The explicit entropy passthrough to `processFutureTicketBatch` (`52242a10`) is audited — passed entropy is cryptographically equivalent to prior derivation, no commitment-window widening, no re-use across calls in the same transaction
  3. Every jackpot caller site using `bonusTraitsPacked` produces an identical 4-trait set for the same VRF word across the purchase-phase path, the jackpot-phase path, and today's earlybird rewrite
  4. Every verdict cites commit SHA + file:line and is added to the Phase 236 finding candidate pool
**Plans**: TBD (expected 2-3 plans, one per JKP requirement)

### Phase 234: Quests / Boons / Misc Audit
**Goal**: Every remaining isolated change (`mint_ETH` wei fix, `boonPacked` exposure, `BurnieCoin.sol` drift) is proven safe — fresh-ETH detection, read-only accessor safety, and supply conservation all verified
**Depends on**: Phase 230
**Requirements**: QST-01, QST-02, QST-03
**Success Criteria** (what must be TRUE):
  1. The `mint_ETH` quest wei-credit fix (`d5284be5`) is audited — 1:1 wei credit correctness, interaction with fresh-ETH detection, no double-credit with companion quests, mint-module integration, and the companion test-file change reviewed
  2. The `boonPacked` mapping exposure (`e0a7f7bc`) is audited — read-only accessor safety, storage layout preserved, no write path introduced, slot accessibility matches intent
  3. The `BurnieCoin.sol` change is audited for isolated cause/effect — the change is confined to decimator-burn-key plumbing with no supply-conservation impact
  4. Every verdict cites commit SHA + file:line and is added to the Phase 236 finding candidate pool
**Plans**: TBD (expected 1 plan with per-requirement sections — grab-bag pattern per v29.0 roadmap guidance)

### Phase 235: Conservation + RNG Commitment Re-Proof + Phase Transition
**Goal**: ETH and BURNIE conservation are proven across the delta, every new RNG consumer has a backward-trace + commitment-window proof matching the v25.0 / v15.0 RNG audit pattern, and the `2471f8e7` phase-transition `_unlockRng` removal is proven safe
**Depends on**: Phase 231, Phase 232, Phase 233, Phase 234
**Requirements**: CONS-01, CONS-02, RNG-01, RNG-02, TRNX-01
**Success Criteria** (what must be TRUE):
  1. Every new or modified SSTORE site touching `currentPrizePool` / `nextPrizePool` / `futurePrizePool` / `claimablePool` / `decimatorPool` is catalogued with mutation direction and guard, and sum-before = sum-after is proven algebraically at every path endpoint
  2. BURNIE conservation is verified across the `BurnieCoin.sol` change and the quest changes — no new mint site bypasses `mintForGame`, and mint/burn accounting closes end-to-end
  3. Every new RNG consumer in the delta (earlybird bonus-trait roll, BAF `traitId=420` sentinel emission, `processFutureTicketBatch` entropy passthrough) has a backward trace proving the VRF word was unknown at input commitment time
  4. Every player-controllable state variable that can change between VRF request and fulfillment is enumerated across the delta and verified non-influential for every new consumer
  5. The removed `_unlockRng(day)` at `DegenerusGameAdvanceModule:425` is verified safe — RNG lock invariant preserved across the newly-packed housekeeping step, no exploitable state-changing path between `_endPhase()` and the next `_unlockRng` reactivation, no missed or double unlock across any reachable path (normal / gameover / skip-split)
**Plans**: TBD (expected 3 plans — one CONS, one RNG, one TRNX — modeled on 215-02/215-03 + 216-01/216-02 structure)

### Phase 236: Regression + Findings Consolidation
**Goal**: Every prior finding is regression-checked against the delta, and all v29.0 findings are consolidated into `audit/FINDINGS-v29.0.md` with severity / source / resolution fields
**Depends on**: Phase 231, Phase 232, Phase 233, Phase 234, Phase 235
**Requirements**: REG-01, REG-02, FIND-01, FIND-02, FIND-03
**Success Criteria** (what must be TRUE):
  1. All 16 v27.0 INFO findings plus the 3 v27.0 KNOWN-ISSUES entries are re-verified against current code with a PASS / REGRESSED / SUPERSEDED verdict per item
  2. All 13 v25.0 findings and the v26.0 delta-audit conclusions are re-verified against current code with no regression introduced by the 10-commit delta
  3. `audit/FINDINGS-v29.0.md` exists in v27.0-style per-finding block format — every finding from phases 231-235 has a stable `F-29-NN` ID, severity (CRITICAL/HIGH/MEDIUM/LOW/INFO), source phase + file:line, and resolution status
  4. `audit/KNOWN-ISSUES.md` is updated with any new design-decision entries referencing `F-29-NN` IDs, and the executive summary table (per-phase counts + per-severity totals) is published in the deliverable
**Plans**: TBD (expected 2 plans — one regression sweep + one consolidation, modeled on 217-01/217-02 + 223-01/223-02)

## Progress

**Execution Order:**
Phase 230 first. Phases 231, 232, 233, 234 can execute in parallel after 230 completes. Phase 235 requires all four audit phases. Phase 236 requires Phase 235.

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 230. Delta Extraction & Scope Map | 1/1 | Complete | 2026-04-17 |
| 231. Earlybird Jackpot Audit | 1/3 | In progress | — |
| 232. Decimator Audit | 0/3 | Not started | — |
| 233. Jackpot/BAF + Entropy Audit | 0/3 | Not started | — |
| 234. Quests / Boons / Misc Audit | 0/1 | Not started | — |
| 235. Conservation + RNG Commitment Re-Proof | 0/2 | Not started | — |
| 236. Regression + Findings Consolidation | 0/2 | Not started | — |

</details>
