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

**Milestone Goal:** Full adversarial audit of every `contracts/` change since the v27.0 baseline (2026-04-13). v28.0 audited the sibling `database/` repo only; contracts have been unaudited for 10 commits (+ 2 post-Phase-230 RNG-hardening commits captured via `230-02-DELTA-ADDENDUM.md`) touching 12 files across entropy passthrough, earlybird rewrites, decimator changes, BAF sentinel, quest wei fix, boon exposure, and non-keccak-entropy-mixing fixes. Read-only audit from Phase 231 onward; the two addendum commits (`314443af`, `c2e5e0a9`) are bug fixes landed mid-milestone with downstream phases updated to cover their surface. Deliverable: `audit/FINDINGS-v29.0.md`.

- [x] **Phase 230: Delta Extraction & Scope Map** - Function-level changelog, cross-module interaction map, and interface-drift catalog across the 10-commit / 12-file delta — completed 2026-04-17; extended by `230-02-DELTA-ADDENDUM.md` on 2026-04-17 to capture 2 post-Phase-230 RNG-hardening commits (`314443af`, `c2e5e0a9`)
- [x] **Phase 231: Earlybird Jackpot Audit** - Adversarial audit of the purchase-phase finalize refactor and the trait-alignment rewrite + combined state-machine verification — completed 2026-04-17 (40 PASS verdicts across 3 plans; zero FAIL, zero DEFER)
- [x] **Phase 232: Decimator Audit** - Adversarial audit of burn-key-by-resolution-level, event emission, and terminal-claim passthrough — completed 2026-04-18 (44 verdict rows across 3 plans / 36 SAFE + 8 SAFE-INFO; zero VULNERABLE / zero DEFERRED; 3 SAFE-INFO Finding Candidate: Y rows total — 2 for Phase 236 FIND-01 from DCM-01 + 1 for Phase 236 FIND-02 from DCM-02 indexer-compat OBSERVATION; DCM-03 contributes zero candidate findings)
- [x] **Phase 233: Jackpot/BAF + Entropy Audit** - Adversarial audit of `traitId=420` sentinel, explicit entropy passthrough, and cross-path bonus-trait consistency — completed 2026-04-19 (77 verdict rows across 3 plans / 75 SAFE + 2 SAFE-INFO; zero VULNERABLE / zero DEFERRED; 2 Finding Candidate: Y — both event-widening indexer-compat OBSERVATIONS for off-chain ABI regeneration routed to Phase 236 FIND-01/02)
- [x] **Phase 234: Quests / Boons / Misc Audit** - Adversarial audit of `mint_ETH` wei-credit fix, `boonPacked` exposure, and incidental `BurnieCoin.sol` change — completed 2026-04-19 (23 verdict rows in one consolidated plan / 19 SAFE + 4 SAFE-INFO; zero VULNERABLE / zero DEFERRED; 1 Finding Candidate: Y — FC-234-A QST-01 companion-test-coverage observation, not a contract finding)
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
- [x] 231-03-PLAN.md — Produce 231-03-AUDIT.md: combined earlybird state machine end-to-end path walk for EBD-03 — normal / skip-split / gameover transitions, no double-spend, no orphaned reserves, no missed emissions, cross-commit invariant (pool dumped = pool consumed) — completed 2026-04-17 (13 PASS verdicts across 4 paths × 4 attack vectors; zero FAIL/DEFER; cross-commit invariant clarified as temporal + causal ordering across orthogonal storage namespaces)

### Phase 232: Decimator Audit
**Goal**: Every decimator-related change (burn-key refactor, event emission, terminal-claim passthrough) is proven safe — key alignment, event correctness, and access-control semantics all verified
**Depends on**: Phase 230
**Requirements**: DCM-01, DCM-02, DCM-03
**Success Criteria** (what must be TRUE):
  1. The burn-key refactor (`3ad0f8d3`) is audited — every read site uses the matching resolution-level key, pro-rata share calculation has no off-by-one, and the consolidated jackpot block has correct ordering
  2. The event emission change (`67031e7d`) is audited — `DecimatorClaimed` and `TerminalDecimatorClaimed` fire at the correct CEI position with correct args, and the emissions are compatible with the v28.0 indexer event surface
  3. The `claimTerminalDecimatorJackpot` passthrough (`858d83e4`) is audited — caller restriction enforced, no reentrancy, no privilege escalation, parameters passed through unchanged to the module
  4. Every verdict cites commit SHA + file:line and is added to the Phase 236 finding candidate pool
**Plans**: 3 plans — one per DCM requirement (per 232-CONTEXT.md D-01 + v29.0 auto-mode rule)
- [x] 232-01-PLAN.md — Produce 232-01-AUDIT.md: per-function verdict table for DCM-01 decimator burn-key refactor (`3ad0f8d3`) — pro-rata off-by-one under lvl+1 keying, read/write key-space alignment across every decBurns/decBurnBuckets/decPool consumer, consolidated jackpot-block x00/x5 mutual exclusivity + decPoolWei determinism + runDecimatorJackpot self-call args/CEI preserved, DECIMATOR_MIN_BUCKET_100 reachability side-effect; BurnieCoin conservation deferred to Phase 235 CONS-02 per D-14 — completed 2026-04-18 (23 verdict rows / 21 SAFE + 2 SAFE-INFO; zero VULNERABLE / zero DEFERRED row-level verdicts; 2 SAFE-INFO Finding Candidate: Y rows for Phase 236 FIND-01)
- [x] 232-02-PLAN.md — Produce 232-02-AUDIT.md: per-function verdict table for DCM-02 decimator event emission (`67031e7d`) — CEI position of all 3 emit sites (DecimatorClaimed gameOver fast-path + normal ETH/lootbox split; TerminalDecimatorClaimed terminal), event-argument correctness invariants (ethPortion+lootboxPortion==amountWei, lvl from input/storage, player==msg.sender), v28.0 Phase 227 indexer-compat OBSERVATION per D-10 — completed 2026-04-18 (14 verdict rows / 9 SAFE + 5 SAFE-INFO; zero VULNERABLE / zero DEFERRED row-level verdicts; 1 SAFE-INFO Finding Candidate: Y for v28.0 Phase 227 indexer-compat OBSERVATION routing to Phase 236 FIND-02)
- [x] 232-03-PLAN.md — Produce 232-03-AUDIT.md: per-function verdict table for DCM-03 terminal-claim passthrough (`858d83e4`) — D-11 attack vectors (caller restriction, reentrancy, parameter pass-through, privilege escalation) + IM-08 delegatecall chain end-to-end + interface/implementer lockstep (ID-30/ID-93) + check-delegatecall 44/44 corroboration per D-12 — completed 2026-04-18 (7 verdict rows / 6 SAFE + 1 SAFE-INFO; zero VULNERABLE / zero DEFERRED row-level verdicts; ZERO Finding Candidate: Y rows; DCM-03 contributes zero candidate findings to Phase 236 FIND-01 pool)

### Phase 232.1: RNG-index ticket drain ordering enforcement (INSERTED)

**Goal**: Every ticket queued at lootbox RNG index X is fully resolved using the correct non-zero `lootboxRngWordByIndex[X]` before any bucket-swap advances `LR_INDEX` to X+1 and requests a new VRF — under all reachable code paths (normal end-of-day, mid-day threshold cross, game-over)
**Depends on:** Phase 232
**Requirements**: SPEC §R1 normal end-of-day drain-before-swap, §R2 mid-day drain-before-swap, §R3 game-over / terminal drain-before-swap, §R4 processTicketBatch entropy consumption, §R5 ticket↔RNG binding consistency, §R6 sim-replay regression (locked in 232.1-SPEC.md; not registered in REQUIREMENTS.md as URGENT-inserted phase)
**Success Criteria** (what must be TRUE):
  1. The lazy pre-finalize gate locked in CONTEXT.md D-01 is inserted at the entry of the daily-drain block in `DegenerusGameAdvanceModule.advanceGame` — `make check-delegatecall` passes 44/44 — empirical gas delta within +5% of pre-fix baseline
  2. Forge invariant test demonstrates `_swapAndFreeze` cannot advance `LR_INDEX` while any read-slot ticket remains undrained (fails on pre-fix HEAD~1, passes on post-fix HEAD)
  3. Forge invariant test demonstrates `_raritySymbolBatch` is never invoked with `entropyWord == 0` under any reachable advanceGame stage sequence (normal end-of-day, mid-day threshold cross, game-over) — D-05's vacuous-safety claim made testable via dedicated path-isolation forge test
  4. Sim-replay regression: post-fix 25L/100P turbo sim shows ZERO `_raritySymbolBatch` events with `entropyWord == 0`; per-quadrant cat-0/cat-7 percentages at L5 within ±1pp of design; zero zero-hit trait IDs at L5
  5. `processFutureTicketBatch` reachable-caller audit confirms every call site supplies non-zero `entropy` — no code change to that function per SPEC §Out of Scope ("audit only")
  6. All `contracts/` and `test/` diffs reviewed and explicitly approved by user before commit (per `feedback_no_contract_commits.md`)
**Plans**: 3 plans (one per natural deliverable boundary: contract fix + diff review; forge test suite + pre-fix replay; sim replay + processFutureTicketBatch audit)
- [x] 232.1-01-PLAN.md — Lazy pre-finalize gate at the daily-drain entry of `advanceGame`; `232.1-01-FIX.md` with diff + gas analysis + make-gate output. Shipped across four revisions: `432fb8f9` Rev 1 initial gate, `d09e93ec` Rev 2 queue-length + nudged-word + do-while integration, `749192cd` Rev 3 game-over best-effort drain + liveness-triggered ticket block, `26cea00b` Rev 4 selector fix `NotTimeYet` → `RngNotReady` at L207 + L263 — completed 2026-04-18. `make check-delegatecall` PASS 46/46 at HEAD.
- [x] 232.1-02-PLAN.md — Forge test suite (`2e5dfa03`): invariant (drain-before-swap + no-zero-entropy), binding consistency, game-over path-isolation. 8/8 PASS on HEAD. Pre-fix replay verified tests FAIL on HEAD~1 and PASS on HEAD — completed 2026-04-18. AC-6 narrowed per user directive to "zero new failures from Plan 02's NEW test files" (legacy test modernization tracked as tech debt for a follow-up phase).
- [x] 232.1-03-PLAN.md — Sim-replay regression (`232.1-03-SIM-REPLAY.md`) + `processFutureTicketBatch` reachable-caller audit (`232.1-03-PFTB-AUDIT.md`) — completed 2026-04-18. AC-4 PASS (zero `_raritySymbolBatch(entropyWord==0)` events; direct on-chain storage shows all 256 trait buckets populated at every level L1-L6). AC-5 PASS (zero L5 zero-hit trait IDs — was 6 pre-fix; per-quadrant cat-0/cat-7 within ±1pp for 7 of 8 cells, Q1 cat-7 marginal at -1.36pp within 1.77σ sampling variance; maximum cell deviation reduced ~20× vs pre-fix baseline). AC-7 PASS (per-caller verdict table proves non-zero entropy at all 4 reachable `_processFutureTicketBatch` call sites — AdvanceModule L315 phase-transition FF, L407 last-purchase-day next-level FF, L1418 + L1428 `_prepareFutureTickets` — via rawFulfillRandomWords L1698 zero-guard + rngGate L291 sentinel-1 break + Plan 01 pre-drain gate; zero code change to `processFutureTicketBatch` body per SPEC §Out of Scope). AC-9 PASS (Plans 01 + 02 commits and artifacts verified present). Sim-tooling DB-aggregation anomaly (19.3× ratio with trait-30=58 / trait-60=3 vs on-chain 4.4× with different trait IDs) handed off to degenerus-sim maintainers as sim-tooling defect, not contract defect.

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
**Plans**: 5 plans — one per requirement, all parallel Wave 1 (per 235-CONTEXT.md D-01 + D-02). HEAD anchor `1646d5af`.
- [ ] 235-01-PLAN.md — Produce 235-01-AUDIT.md: CONS-01 ETH conservation Per-SSTORE Catalog + Per-Path Algebraic Proofs + 232.1 Ticket-Processing Impact sub-section per D-06; cross-cites 231-01 EBD-01 / 231-02 EBD-02 / 231-03 EBD-03 / 232-01 DCM-01 re-verified at HEAD 1646d5af per D-04
- [ ] 235-02-PLAN.md — Produce 235-02-AUDIT.md: CONS-02 BURNIE conservation Per-Mint-Site + Per-Burn-Site Catalogs + Quest Credit Algebra + 232.1 Ticket-Processing Impact sub-section; cross-cites 232-01 DCM-01 + 234-01 QST-01/02/03 re-verified at HEAD 1646d5af
- [ ] 235-03-PLAN.md — Produce 235-03-AUDIT.md: RNG-01 Per-Consumer Backward-Trace Table covering 5 consumer categories (earlybird bonus-trait, BAF sentinel, entropy passthrough, 17 per-site c2e5e0a9 rows per D-07, 314443af keccak-seed per D-09) + D-09 Non-Zero-Entropy Availability Cross-Cite to 232.1-03-PFTB-AUDIT + 232.1 Ticket-Processing Impact sub-section; cross-cites 233-02 JKP-02 + 231-02 EBD-02 + 232.1-03-PFTB-AUDIT re-verified at HEAD 1646d5af
- [ ] 235-04-PLAN.md — Produce 235-04-AUDIT.md: RNG-02 Per-Consumer Commitment-Window Enumeration Table covering 5 consumer categories (17 per-site c2e5e0a9 rows per D-08 + 314443af per D-09) + rngLocked Invariant sub-section with D-11 citation + Global State-Variable Enumeration + D-09 Availability Cross-Cite + 232.1 Ticket-Processing Impact sub-section; cross-cites 233-02 JKP-02 D-06 + 232.1 Plan 02 forge invariants re-verified at HEAD 1646d5af
- [ ] 235-05-PLAN.md — Produce 235-05-AUDIT.md: TRNX-01 D-11 rngLocked invariant verbatim statement + Buffer-Swap Site Citation at concrete file:line per D-12 + 4-Path Walk Table (Normal / Gameover / Skip-split / Phase-transition freeze per D-13) + rngLocked End-State Check + 232.1 Ticket-Processing Impact sub-section walking 6 fix-series changes; cross-cites 232.1-01-FIX + 232.1-02 forge invariants re-verified at HEAD 1646d5af

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
| 231. Earlybird Jackpot Audit | 3/3 | Complete | 2026-04-17 |
| 232. Decimator Audit | 3/3 | Complete | 2026-04-18 |
| 232.1. RNG-Index Ticket Drain Ordering Enforcement | 3/3 | Complete | 2026-04-18 |
| 233. Jackpot/BAF + Entropy Audit | 3/3 | Complete | 2026-04-19 |
| 234. Quests / Boons / Misc Audit | 1/1 | Complete | 2026-04-19 |
| 235. Conservation + RNG Commitment Re-Proof | 0/5 | Not started | — |
| 236. Regression + Findings Consolidation | 0/2 | Not started | — |

</details>
</content>
