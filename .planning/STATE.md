---
gsd_state_version: 1.0
milestone: v40.0
milestone_name: Unified Whole-Ticket Award Protocol + Whole-BURNIE Floor
status: verifying
last_updated: "2026-05-14T09:16:02.330Z"
last_activity: 2026-05-14 -- Phase 277 COMPLETE (Plan 01 contract wave + Plan 02 test wave) — ready for verification
progress:
  total_phases: 6
  completed_phases: 3
  total_plans: 6
  completed_plans: 6
  percent: 50
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-05-13 after v39.0 milestone close + v40.0 open + BUR scope expansion)

**Core value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.
**Current focus:** Phase 277 — event-surface-unification-sentinel-retirement-evt-uni

## Current Position

Phase: 277 (event-surface-unification-sentinel-retirement-evt-uni) — COMPLETE
Plan: 2 of 2 (277-01 contract wave COMPLETE `02fb7085`; 277-02 test wave COMPLETE `6fbee850`)
Status: Phase 277 complete — ready for verification
Last activity: 2026-05-14 -- Phase 277 Plan 02 (test wave) COMPLETE — USER-APPROVED commit `6fbee850`

## Last Shipped Milestone

**v39.0 — Lootbox Whole-Ticket Rounding + WWXRP Consolation** (shipped 2026-05-13)

- 1 phase (274), 1 plan, 39/39 requirements satisfied (5 LBX-WT + 4 LBX-WX + 6 LBX-EVT + 7 TST-WT + 3 TST-WX + 4 TST-REG + 6 AUDIT + 4 REG)
- Audit baseline: v38.0 audit-subject HEAD `MILESTONE_V38_AT_HEAD_06623edb` → v39.0 audit-subject HEAD `6a7455d1` (resolved at Wave 3 Task 3.10 atomic-update per D-274-CLOSURE-01)
- 1 USER-APPROVED Wave 1 contract-side commit `c21f833a` (`feat(274): manual lootbox Bernoulli whole-ticket + WWXRP consolation + LootboxTicketRoll event [LBX-WT-01..05, LBX-WX-01..04, LBX-EVT-01..06]`; `contracts/modules/DegenerusGameLootboxModule.sol` + `contracts/interfaces/IDegenerusGameModules.sol`; storage layout byte-identical; new constant inlined; new event log calldata-equivalent; D-274-BIT-SLICE-01 superseded intra-Wave-1 to 16-bit slice on bias quantification) + 1 USER-APPROVED Wave 2 batched test commit `f8e55cfe` (`test(274): manual lootbox whole-ticket + consolation + auto-resolve regression + LootboxTicketRoll [TST-WT-01..07, TST-WX-01..03, TST-REG-01..04]`; +1,422 LOC across 4 new test files; 74 tests; all 74 passing). Single-phase patch shape per v36.0 Phase 266 + v38.0 Phase 272 precedent.
- Phase 273 included-since-baseline (pre-shipped maintenance between v38.0 closure and v39.0 open per D-274-BAF273-INCLUDE-01): `ff929948` BAF credit routing 3-point patch + `e9807891` BAF-ROUTE-06/07/08 test expansion + `e04d3333` Phase 273 SUMMARY + `1eb1ecb5` `_livenessTriggered` NatSpec clarification. Folded into v39.0 audit baseline as surface-coverage attestation only (no F-39-NN finding eligible).
- Result: 8 of 8 §4 adversarial surfaces SAFE / SAFE_BY_DESIGN / SAFE_BY_STRUCTURAL_CLOSURE / SAFE_BY_DESIGN_PHASE_273 (a EV-neutrality of Bernoulli vs cross-lootbox accumulation + b bit-slice [152..167] independence + c consolation predicate gating + d storage layout byte-identical + e auto-resolve byte-equivalent to v38 + f index gating discriminator zero-crossover + g LootboxTicketRoll field-consistency invariants + h Phase 273 BAF-routing surface coverage at included-baseline); zero F-39-NN finding blocks emitted; 12 novel-vector hypotheses (i)..(t) investigated across 3 adversarial skills with 10 NEGATIVE_RESULT_ONLY + 2 ACCEPTED_DESIGN dispositions (variance tradeoff + manual/auto-resolve asymmetry; both documented via §4 (a) prose + D-274-MANUAL-ONLY-01 locked decision; NOT promoted to KNOWN-ISSUES.md)
- Adversarial pass via 3-skill PARALLEL spawn intent `/contract-auditor` + `/zero-day-hunter` + `/economic-analyst` per D-274-ADVERSARIAL-01 carry on finished §4 draft; `/degen-skeptic` OUT OF SCOPE per D-271-ADVERSARIAL-02 carry. Disposition: zero residual FINDING_CANDIDATE; zero 9th-surface NEW_VECTOR; zero KI promotion candidates per `274-01-ADVERSARIAL-LOG.md` Disposition section
- LEAN regression: 1 PASS REG-01 (v38.0 closure signal `MILESTONE_V38_AT_HEAD_06623edb` re-verified NON-WIDENING for v38-touched surfaces NOT in v39 manual-lootbox scope; Phase 273 `BurnieCoinflip.sol` carve-out folded as included-since-baseline per D-274-BAF273-INCLUDE-01) + 1 PASS REG-02 (v34.0 closure signal `MILESTONE_V34_AT_HEAD_6b63f6d4daf346a53a1d463790f637308ea8d555` re-verified NON-WIDENING; TraitUtils + `_pickSoloQuadrant` + JackpotBucketLib byte-identical) + REG-03 KI envelope re-verifications + REG-04 prior-finding spot-check sweep PASS across audit/FINDINGS-v25..v38.0
- KI envelopes EXC-01..03 RE_VERIFIED NEGATIVE-scope at v39 (Phase 274 has zero affiliate-roll / AdvanceModule / gameover-RNG-substitution interaction); EXC-04 RE_VERIFIED with NARROWS retained (BAF-jackpot-only scope; EntropyLib byte-identical at v39 HEAD; the new bits[152..167] Bernoulli reads keccak primary chunk NOT xorshift output per backward-trace cite)
- KNOWN-ISSUES.md UNMODIFIED per D-274-KI-01 default zero-promotion path. Closure verdict `0 of 0 KI_ELIGIBLE_PROMOTED; KNOWN_ISSUES_UNMODIFIED`
- Deliverable: `audit/FINDINGS-v39.0.md` (FINAL READ-only at HEAD `6a7455d1`, 9 sections; flip at Wave 3 Task 3.11 post-user-approval)
- Closure signal: `MILESTONE_V39_AT_HEAD_6a7455d1`
- Process notes: Subagent-spawned execution under `/gsd-execute-phase` Wave decomposition. 2 USER-APPROVED batched contract/test commits (Wave 1 + Wave 2) + N AGENT-COMMITTED audit-deliverable + closure-flip commits per `feedback_no_contract_commits.md` + `feedback_batch_contract_approval.md` + `feedback_never_preapprove_contracts.md` + `feedback_manual_review_before_push.md`. Adversarial-pass 3-skill PARALLEL spawn per D-274-ADVERSARIAL-01 carry. v39.0 closure invariant: terminal-phase zero forward-cite emission across scoped artifacts; planner-handoff carry-forward register in §9 §"Deferred to Future Milestones" subsection uses locked-decision IDs (D-274-MINTBOOST-OUT-01 / D-274-AUTORESOLVE-OUT-01 / D-274-JACKPOT-OUT-01) — pickup-pointers per §8 allowlist
- See `.planning/MILESTONES.md` for archive

### Prior Shipped Milestone

**v38.0 — Always-Hero Simplification + Maximal Dead-Code Cleanup** (shipped 2026-05-11)

- 1 phase (272), 1 plan, 29/30 requirements satisfied + 1/30 RE-DEFERRED-V39+ (29 Complete: 5 HERO + 6 CLEAN + 2 STAT + 3 SURF + 2 GASPIN + 1 STAT-03-v35-carry + 6 AUDIT + 4 REG; 1 RE-DEFERRED-V39+: LBX-02 fixture-coverage gap)
- Audit baseline: v37.0 audit-subject HEAD `MILESTONE_V37_AT_HEAD_2654fcc2` → v38.0 audit-subject HEAD `06623edb` (placeholder; resolved at Wave 4 Task 4.6 atomic-update per D-272-CLOSURE-01)
- 1 USER-APPROVED Wave 1 contract commit `527e3adc` (`feat(272): always-on hero default 0 + degenerette dead-code cleanup [HERO-01..05, CLEAN-01..05]`; `contracts/modules/DegenerusGameDegeneretteModule.sol` +18/-16 LOC; bytecode delta -57 bytes 8955 → 8898; storage layout byte-identical; public ABI byte-identical) + 1 USER-APPROVED Wave 1.5 contract revision commit `4760459f` (`feat(272): wave 1.5 validate heroQuadrant input (revert on >= 4) [HERO-05-revised]` — D-272-INPUT-VALIDATION-01 defensive boundary validation; `placeDegeneretteBet` validates `heroQuadrant < 4` at entry, reverts with `InvalidBet` on `>= 4`; reverses v37+ "0xFF = no hero" sentinel semantic) + 1 USER-APPROVED Wave 2 batched test commit `e3fcb95c` (`test(272): hero-always-on + dead-code cleanup + v37+ carry bundle [STAT-01..02, SURF-01..03, LBX-02, GASPIN-02..03, STAT-03-v35-carry]`; +238/-36 LOC across 6 files in `test/stat/`, `test/gas/`, `package.json`)
- Result: 7 of 7 §4 adversarial surfaces SAFE / SAFE_BY_DESIGN / SAFE_BY_STRUCTURAL_CLOSURE (a EV-neutrality preserved + b quadrant 0 default no-bias + c cleanup-removal invariants preserved per `feedback_no_dead_guards.md` + `feedback_design_intent_before_deletion.md` + d storage byte-identical + e public ABI byte-identical + f Wave 1.5 input-validation boundary + g 3-skill PARALLEL adversarial-pass surfaces); zero F-38-NN finding blocks emitted; Hypothesis (i) docs-vs-behavior drift surfaced at Wave 3 PARALLEL pass and RESOLVED_AT_V38 via Wave 1.5 commit `4760459f`
- Adversarial pass via 3-skill PARALLEL spawn `/contract-auditor` + `/zero-day-hunter` + `/economic-analyst` per D-271-ADVERSARIAL-01 carry on finished §4 draft; `/degen-skeptic` OUT OF SCOPE per D-271-ADVERSARIAL-02 carry. Disposition: zero residual FINDING_CANDIDATE post Wave 1.5 (Hypothesis (i) RESOLVED_AT_V38 via Wave 1.5 commit `4760459f` per `272-01-ADVERSARIAL-LOG.md` Wave 1.5 disposition update at commit `1249a6fd`)
- LEAN regression: 1 PASS REG-01 (v37.0 closure signal `MILESTONE_V37_AT_HEAD_2654fcc2` re-verified non-widening; Mint + Jackpot + EntropyLib + JackpotBucketLib byte-identical at v38 HEAD) + 1 PASS REG-02 (v34.0 closure signal `MILESTONE_V34_AT_HEAD_6b63f6d4daf346a53a1d463790f637308ea8d555` re-verified non-widening; TraitUtils 3 functions + `_pickSoloQuadrant` + JackpotBucketLib byte-identical) + REG-03 KI envelope re-verifications + REG-04 prior-finding spot-check sweep PASS across audit/FINDINGS-v25..v37.0 for v38-touched function/surface set
- KI envelopes EXC-01..03 RE_VERIFIED NEGATIVE-scope at v38 (Phase 272 has zero affiliate-roll / AdvanceModule / gameover-RNG-substitution interaction); EXC-04 RE_VERIFIED with NARROWS retained (BAF-jackpot-only scope; EntropyLib byte-identical at v38 HEAD)
- KNOWN-ISSUES.md UNMODIFIED per D-272-KI-01 default zero-promotion path. Closure verdict `0 of 0 KI_ELIGIBLE_PROMOTED; KNOWN_ISSUES_UNMODIFIED`
- Deliverable: `audit/FINDINGS-v38.0.md` (FINAL READ-only at HEAD `06623edb`, 9 sections, ~850 lines)
- Closure signal: `MILESTONE_V38_AT_HEAD_06623edb`
- Process notes: Subagent-spawned execution under `/gsd-execute-phase` Wave decomposition. 2 USER-APPROVED batched contract/test commits (Wave 1 + Wave 2) + 1 USER-APPROVED Wave 1.5 input-validation revision commit + N AGENT-COMMITTED audit-deliverable + closure-flip commits per `feedback_no_contract_commits.md` + `feedback_batch_contract_approval.md` + `feedback_never_preapprove_contracts.md` + `feedback_manual_review_before_push.md`. Adversarial-pass 3-skill PARALLEL spawn per D-271-ADVERSARIAL-01 carry; `/economic-analyst` added vs v36.0 single-pair pattern per D-271-ADVERSARIAL-03 carry. v38.0 closure invariant: terminal-phase zero forward-cite emission across scoped artifacts; pickup-pointer carve-out in test files acceptable per §8.
- See `.planning/MILESTONES.md` for archive

### Prior Shipped Milestone

**v37.0 — Degenerette Recalibration + Maintenance Bundle** (shipped 2026-05-11; closure signal `MILESTONE_V37_AT_HEAD_2654fcc2`)

- 5 phases (267-271), 5 plans, 48/48 in-scope requirements + 3 DEFERRED-V38+ folded into v38.0 (LBX-02 + GASPIN-02 + GASPIN-03; 4 of those 4 v38 carry-pickups COMPLETE at v38 close except LBX-02 which RE-DEFERS to v39+ — fixture-coverage gap persists)
- Audit baseline: v36.0 audit-subject HEAD `1c0f09132d7439af9881c56fe197f81757f8164a` → v37.0 audit-subject HEAD `2654fcc2`
- Result: 8 of 8 §4 adversarial surfaces SAFE / SAFE_BY_DESIGN / SAFE_BY_STRUCTURAL_CLOSURE; zero F-37-NN findings; 1 PASS REG-01 + 1 PASS REG-02 + 5 PASS + 1 SUPERSEDED REG-04
- Closure signal: `MILESTONE_V37_AT_HEAD_2654fcc2`
- See `.planning/MILESTONES.md` for archive

### Prior Shipped Milestone

**v36.0 — Lootbox-Path Entropy Refactor** (shipped 2026-05-10; closure signal `MILESTONE_V36_AT_HEAD_1c0f09132d7439af9881c56fe197f81757f8164a`)

- 1 phase (266), 1 plan, 24/24 requirements satisfied (ENT-01..06 + STAT-01..03 + GAS-01..02 + SURF-01..04 + AUDIT-01..05 + REG-01..04)
- Audit baseline: v35.0 audit-subject HEAD `5db8682bd7b811437f0c1cf47e832619d1478ac6` → v36.0 audit-subject HEAD `1c0f09132d7439af9881c56fe197f81757f8164a`
- Result: 6 of 6 §4 adversarial surfaces SAFE_BY_DESIGN / SAFE_BY_STRUCTURAL_CLOSURE; zero F-36-NN findings; KNOWN-ISSUES.md modified by 1 entry rephrase (EntropyLib XOR-shift NARROWS to BAF-jackpot-only scope)
- Closure signal: `MILESTONE_V36_AT_HEAD_1c0f09132d7439af9881c56fe197f81757f8164a`
- See `.planning/MILESTONES.md` for archive

### Prior Shipped Milestone (rotated out of detail; retained at MILESTONES.md)

**v35.0 — BURNIE Near-Future Per-Pull Level Resample** (shipped 2026-05-09)

- 3 phases (263-265), 4 plans, 27/27 requirements satisfied (PPL-01..08 + STAT-01..04 + SURF-01..05 + AUDIT-01..06 + REG-01..04)
- Audit baseline: v34.0 source-tree HEAD `6b63f6d4daf346a53a1d463790f637308ea8d555` → v35.0 audit-subject HEAD `5db8682bd7b811437f0c1cf47e832619d1478ac6` (Phase 265 emits zero source-tree mutations per CONTEXT.md hard constraint #1; audit-subject HEAD = post-Phase-264 close commit)
- 1 contract-tree commit since baseline: `cf564816` (Phase 263 single batched contract-tree commit — `feat(263): per-pull level resample for daily coin jackpot [PPL-01..PPL-08]`; +91/-74 LOC, net +17 LOC) + 6 test/chore commits since baseline (Phase 264 — `aa41485e` PerPullLevelDistribution.test.js + `7dcfeb0c` PerPullEmptyBucketSkip.test.js + `82717bcf` SurfaceRegression v35.0 extension + `36234847` Phase264GasRegression.test.js + `20b15468` AdvanceGameGas extension + `833b341d` package.json scripts wiring)
- Result: 6 of 6 §4 adversarial surfaces SAFE / SAFE_BY_DESIGN / SAFE_BY_STRUCTURAL_CLOSURE (a predictability + b level-salt collision + c deity-cache staleness + d cross-caller _randTraitTicket salt collision + e off-chain indexer semantic-shift + f gas-griefing cold SLOAD); STAT-03 reframe row SAFE_BY_STRUCTURAL_CLOSURE per D-265-STAT03-01 (88.24% empty-bucket skip rate reframed as fixture-calibration error, NOT a finding); zero F-35-NN finding blocks emitted
- Adversarial pass via `/contract-auditor` + `/zero-day-hunter` parallel spawn returned ZERO disagreements; `/economic-analyst` + `/degen-skeptic` explicitly NOT in scope per D-265-ADVERSARIAL-01
- LEAN regression: 1 PASS REG-01 (v34.0 closure signal `MILESTONE_V34_AT_HEAD_6b63f6d4daf346a53a1d463790f637308ea8d555` re-verified non-widening; TraitUtils + JackpotBucketLib + EntropyLib + GameStorage byte-identical) + 1 PASS REG-02 (v33.0 closure signal `MILESTONE_V33_AT_HEAD_4ce3703d740d3707c88a1af595618120a8168399` re-verified non-widening; GNRUS.sol byte-identical) + 9 PASS + 1 SUPERSEDED REG-04 (prior-finding spot-check sweep across audit/FINDINGS-v25..v34)
- KI envelopes EXC-01..03 RE_VERIFIED NEGATIVE-scope at v35 (per-pull-level path has zero affiliate-roll / AdvanceModule / gameover-RNG-substitution interaction); EXC-04 RE_VERIFIED with Phase 264 STAT-01 chi² empirical cross-cite (`test/stat/PerPullLevelDistribution.test.js` 10K samples; range=4 chi²=5.114 < 7.815 critical at α=0.05 df=3; range=8 chi²=3.019 < 14.067 df=7); per-pull-level keccak consumes VRF-derived high-entropy bits, NOT XOR-shift output (backward-trace per `feedback_rng_backward_trace.md`)
- KNOWN-ISSUES.md UNMODIFIED at HEAD — AUDIT-06 `JackpotBurnieWin.lvl` semantic-shift documented in `audit/FINDINGS-v35.0.md` §3c (the v34→v35 audit deliverable IS the proper venue for delta-event semantic-shift disclosures; KNOWN-ISSUES.md is reserved for warden pre-disclosure of ongoing-protocol-behavior items). D-265-AUDIT06-01's KI promotion was REVERTED at v35.0 close per user-review-of-diff venue-mismatch finding. Closure verdict `0 of 0 KI_ELIGIBLE_PROMOTED; KNOWN_ISSUES_UNMODIFIED`
- Deliverable: `audit/FINDINGS-v35.0.md` (FINAL READ-only at HEAD `5db8682bd7b811437f0c1cf47e832619d1478ac6`, 9 sections, ~600 lines)
- Closure signal: `MILESTONE_V35_AT_HEAD_5db8682bd7b811437f0c1cf47e832619d1478ac6`
- Process notes: Standard `/gsd-execute-phase` subagent delegation blocked by global `.md`-write guard pattern-matching FINDINGS/SUMMARY/ADVERSARIAL-LOG filenames; user opted for orchestrator-inline execution path. All 14 atomic-commit tasks executed inline; adversarial-pass /contract-auditor + /zero-day-hunter spawned via Skill tool in parallel (skills load into orchestrator context for review work — no .md-write guard interference).
- See `.planning/MILESTONES.md` for archive

### Prior Shipped Milestone

**v34.0 — Trait Rarity Rework + Gold Solo Priority** (shipped 2026-05-09)

- 4 phases (259-262), 10 plans, 36/36 requirements satisfied (TRAIT-01..06 + SOLO-01..09 + STAT-01..07 + SURF-01..05 + AUDIT-01..05 + REG-01..04)
- Audit baseline: v33.0 contract-tree HEAD `4ce3703d740d3707c88a1af595618120a8168399` → v34.0 source-tree HEAD `6b63f6d4daf346a53a1d463790f637308ea8d555` (Phase 262 emits zero source-tree mutations per CONTEXT.md hard constraint #1; source-tree HEAD stable across Phase 262's docs-only commits per D-262-CLOSURE-01)
- 5 source-tree commits since baseline (`301f7fad` rewrite TraitUtils, `031a8cbc` TraitUtilsTester, `2fa7fb6e` gold-solo + tests, `1574d533` noOp companion, `a6c4f18a` perf refactor) + 8 test-tree commits (Phase 259/260/261 test files)
- Result: 6 of 6 §4 §4 adversarial surfaces SAFE_BY_DESIGN / SAFE_BY_STRUCTURAL_CLOSURE (a entropy-bit collision, b split-call coherence, c gold-trait population manipulation, d gas-griefing 4-iter loop, e overflow / signed-vs-unsigned XOR mask, f hero × gold composition added per Task 7 user disposition as intended skill-expression channel for high-engagement Degenerette wagerers); zero F-34-NN finding blocks emitted
- LEAN regression: 1 PASS REG-01 (v33.0 closure signal `MILESTONE_V33_AT_HEAD_4ce3703d740d3707c88a1af595618120a8168399` re-verified non-widening; charity governance / GNRUS.sol byte-identical) + 1 PASS REG-02 (v32.0 closure signal `MILESTONE_V32_AT_HEAD_acd88512` re-verified non-widening; L173 turbo guard + L1174 backfill sentinel + GameStorage `_livenessTriggered` body byte-identical between v32 baseline and v34 HEAD) + 4 PASS REG-04 (v25/v27/v29/v30 prior-finding spot-check rows)
- KI envelopes EXC-01..03 RE_VERIFIED NEGATIVE-scope at v34 (trait/solo path has zero affiliate-roll / AdvanceModule / gameover-RNG-substitution interaction); EXC-04 RE_VERIFIED with STAT-05 chi² empirical cross-cite (`test/stat/GoldSoloCoverage.test.js:159-209`, 100K samples per goldCount ∈ {2,3,4})
- KNOWN-ISSUES.md UNMODIFIED per D-262-KI-01 default zero-promotion path
- Deliverable: `audit/FINDINGS-v34.0.md` (FINAL READ-only at HEAD `6b63f6d4daf346a53a1d463790f637308ea8d555`, 9 sections, ~700 lines)
- Closure signal: `MILESTONE_V34_AT_HEAD_6b63f6d4daf346a53a1d463790f637308ea8d555`
- Process notes: Task 7 user disposition Option B default-path approved by user; Surface (a) bits 24-25 doc gap + Surface (c) two-channel tightening + NEW Surface (f) hero × gold composition all surfaced via /contract-auditor + /zero-day-hunter parallel spawn (D-262-ADVERSARIAL-02 sequential-after-draft pattern) + folded into §4 prose via Task 7b atomic-commit prose-amendment per user disposition
- Phase 261 deferred items (carried forward as INFO-tier): (a) STAT-07 ROADMAP cites informational headline targets vs canonical analytical values (test asserts canonical-within-Wilson-99%-CI-of-measured); (b) ROADMAP Phase 261 success criterion #5 cites `_pickSoloQuadrant per-call < 500 gas` while REQUIREMENTS.md SURF-05 amendment `73d533d8` supersedes with `≤ 1500 gas paired-empty-wrapper delta` — both surfaced INFO-only in §3c per D-262-FIND-01 default path; REQUIREMENTS.md amendment commit `73d533d8` is load-bearing
- See `.planning/MILESTONES.md` for archive

## Active Milestone

_None — between-milestones state. v39.0 SHIPPED 2026-05-13. Next milestone scope TBD._

### Just-Shipped Milestone Reference

**v39.0 Lootbox Whole-Ticket Rounding + WWXRP Consolation** (started 2026-05-13; SHIPPED 2026-05-13; closure signal `MILESTONE_V39_AT_HEAD_6a7455d1`)

- **Goal:** On MANUAL lootbox opens (`openLootBox` + `openBurnieLootBox` only), replace fractional-residue accumulation with a single Bernoulli round-up at open time on `bits[152..167]` of the per-resolution seed; queue whole tickets via `_queueTickets`; pay `LOOTBOX_WWXRP_CONSOLATION = 1 ether` WWXRP consolation when `whole == 0` from non-zero `scaledPre`; emit new additive `LootboxTicketRoll` event for remainder visibility. Auto-resolve paths (`resolveLootboxDirect` decimator-claim + `resolveRedemptionLootbox` sDGNRS-redemption) explicitly UNCHANGED per D-274-MANUAL-ONLY-01.
- **Audit baseline:** v38.0 closure HEAD `MILESTONE_V38_AT_HEAD_06623edb`
- **Phases completed:** 1 (Phase 274) — single-phase multi-wave shape per v36.0 Phase 266 + v38.0 Phase 272 precedent
- **Requirements:** 39 total (5 LBX-WT + 4 LBX-WX + 6 LBX-EVT + 7 TST-WT + 3 TST-WX + 4 TST-REG + 6 AUDIT + 4 REG); coverage 39/39 satisfied at v39 close.
- **READ-only posture:** LIFTED — `contracts/` + `test/` writes via per-commit user approval per `feedback_no_contract_commits.md` + `feedback_batch_contract_approval.md` + `feedback_never_preapprove_contracts.md`. 2 USER-APPROVED batched commits (Wave 1 contracts `c21f833a` + Wave 2 tests `f8e55cfe`).
- **Behavior change posture:** ACCEPTED — Bernoulli collapse is EV-neutral by construction (`E[whole_post] == scaledPre / 100` exact identity); per-lootbox variance slightly higher than v38 cross-lootbox-deterministic-accumulation but bounded; auto-resolve paths byte-equivalent to v38; new `LootboxTicketRoll` event purely additive (no consumer break for non-adopters); new WWXRP consolation magnitude `1 ether` matches existing 10%-path `LOOTBOX_WWXRP_PRIZE`.
- **Adversarial-pass posture:** SEQUENTIAL after full §4 draft per D-NN-ADVERSARIAL-02 carry; 3-skill PARALLEL spawn `/contract-auditor` + `/zero-day-hunter` + `/economic-analyst` per D-274-ADVERSARIAL-01 carry on finished §4 draft (`/degen-skeptic` OUT OF SCOPE per D-271-ADVERSARIAL-02 carry). Disposition: zero residual FINDING_CANDIDATE; 12 novel-vector hypotheses (i)..(t) returned 10 NEGATIVE_RESULT_ONLY + 2 ACCEPTED_DESIGN (variance tradeoff + manual/auto-resolve asymmetry; both documented via §4 (a) prose + D-274-MANUAL-ONLY-01 locked decision).
- **Out of scope (deferred):** Mint-boost fractional retirement (D-274-MINTBOOST-OUT-01); auto-resolve lootbox path retirement (D-274-AUTORESOLVE-OUT-01); jackpot ticket-award sites + BAF Bernoulli + v36.0 ENT-05 xorshift refactor (D-274-JACKPOT-OUT-01); LBX-02 fixture-coverage gap (D-274-LBX02-OUT-01, RE-DEFERRED-V40+).
- **Closure signal:** `MILESTONE_V39_AT_HEAD_6a7455d1` (resolved at Wave 3 Task 3.10 atomic-update per D-274-CLOSURE-01).
- **Phase 274 SHIPPED 2026-05-13:** Lootbox Whole-Ticket Rounding + WWXRP Consolation (Terminal). Multi-wave shape: Wave 1 USER-APPROVED batched contract commit `c21f833a` (LBX-WT-01..05 + LBX-WX-01..04 + LBX-EVT-01..06; manual-branch addition + new private constant + new event + index threading + bit-allocation NatSpec update 152 → 168; D-274-BIT-SLICE-01 superseded intra-Wave-1 from 8-bit to 16-bit slice on bias quantification) + Wave 2 USER-APPROVED batched test commit `f8e55cfe` (TST-WT-01..07 + TST-WX-01..03 + TST-REG-01..04; +1,422 LOC across 4 new test files; 74 tests passing) + Wave 3 AGENT-COMMITTED audit deliverable atomic chain `386e797d` → `6a7455d1` + Wave 3 closure-flip commits + Wave 3 final user-review gate at Task 3.11. 39/39 requirements satisfied.
- See `.planning/ROADMAP.md` for the single-phase Phase 274 entry + `.planning/phases/274-lootbox-whole-ticket-rounding-wwxrp-consolation-terminal/` for plan + context + adversarial-log + summary artifacts.

### Prior Just-Shipped Milestone Reference (rotated from active position)

**v38.0 Always-Hero Simplification + Maximal Dead-Code Cleanup** (started 2026-05-11; SHIPPED 2026-05-11; closure signal `MILESTONE_V38_AT_HEAD_06623edb`)

- **Goal:** Drop the Degenerette hero opt-out semantics so hero always fires with quadrant 0 as default — adds random competition for any player's winning symbol, simplifies bet API + resolve path. Bundle with a maximal cleanup sweep across `contracts/modules/DegenerusGameDegeneretteModule.sol` for accumulated dead code (D-272-CLEAN-SCOPE-01 narrowing — single-file scope per planner discretion). Land 4 of 5 v37+ carry-forward items COMPLETE; RE-DEFER LBX-02 to v39+ with path-of-investigation prose (fixture-coverage gap persists).
- **Audit baseline:** v37.0 closure HEAD `MILESTONE_V37_AT_HEAD_2654fcc2`
- **Phases planned:** 1 (Phase 272) — single-phase multi-wave shape per v36.0 Phase 266 precedent
- **Requirements:** 30 total (5 HERO + 6 CLEAN + 2 STAT + 3 SURF + 1 LBX + 2 GASPIN + 1 PPL + 6 AUDIT + 4 REG); coverage 30/30 mapped to Phase 272. Resolution at close: 29 Complete + 1 RE-DEFERRED-V39+ (LBX-02).
- **READ-only posture:** LIFTED — `contracts/` + `test/` writes via per-commit user approval per `feedback_no_contract_commits.md` + `feedback_batch_contract_approval.md` + `feedback_never_preapprove_contracts.md`. 2 USER-APPROVED batched commits (Wave 1 contracts `527e3adc` + Wave 2 tests `e3fcb95c`) + 1 USER-APPROVED Wave 1.5 input-validation revision (commit `4760459f`).
- **Behavior change posture:** ACCEPTED — hero EV-neutrality preserved per Fraction-exact analytical audit; player-side opt-out removed (mildly variance-increasing for risk-averse players, no EV change); cleanup removals each preserve safety invariants via upstream enforcement; D-272-INPUT-VALIDATION-01 (Wave 1.5) shifts from silent-normalize to defensive boundary validation — `0xFF` and any `>= 4` revert with `InvalidBet`.
- **Adversarial-pass posture:** SEQUENTIAL after full §4 draft per D-NN-ADVERSARIAL-02 carry; 3-skill PARALLEL spawn `/contract-auditor` + `/zero-day-hunter` + `/economic-analyst` per D-271-ADVERSARIAL-01 carry on finished §4 draft (`/degen-skeptic` OUT OF SCOPE per D-271-ADVERSARIAL-02 carry). Disposition: zero residual FINDING_CANDIDATE post Wave 1.5; Hypothesis (i) RESOLVED_AT_V38.
- **Out of scope (deferred):** ETH daily jackpot recalibration; BAF jackpot `_jackpotTicketRoll` xorshift refactor (v36.0 ENT-05 carry); new storage layout / new admin / new upgrade hooks; new public/external mutation entry points; KNOWN-ISSUES.md modifications (default zero-promotion path); game-over thorough hardening (defer to dedicated milestone).
- **Closure signal:** `MILESTONE_V38_AT_HEAD_06623edb` (resolved at Wave 4 Task 4.6 atomic-update per D-272-CLOSURE-01).
- **Phase 272 SHIPPED 2026-05-11:** Always-Hero Simplification + Maximal Dead-Code Cleanup (Terminal). Multi-wave shape: Wave 1 USER-APPROVED batched contract commit `527e3adc` (HERO-01..05 silent-normalize + CLEAN-01..05 dead-code sweep narrowed to DegenerusGameDegeneretteModule.sol per D-272-CLEAN-SCOPE-01) + Wave 1.5 USER-APPROVED contract revision commit `4760459f` (HERO-05 spec_lock revision per D-272-INPUT-VALIDATION-01 — input validation; revert on `>= 4` instead of normalize) + Wave 2 USER-APPROVED batched test commit `e3fcb95c` (STAT-01..02 + SURF-01..03 + LBX-02 + GASPIN-02..03 + STAT-03-v35-carry test bundle) + Wave 3 AGENT-COMMITTED audit deliverable commits `b3f6af6d`..`6a9f427c` + Wave 3 adversarial-pass commit `873b8295` (3-skill PARALLEL `/contract-auditor` + `/zero-day-hunter` + `/economic-analyst`) + Wave 1.5 audit amendments `c63a75a1` + `08706ebd` + `1249a6fd` + `06623edb` + Wave 4 closure-flip commits. 30/30 requirements satisfied (29 Complete + 1 RE-DEFERRED-V39+ — LBX-02).
- See `.planning/ROADMAP.md` for the single-phase Phase 272 entry + `.planning/phases/272-always-hero-simplification-maximal-dead-code-cleanup-terminal/` for plan + context + adversarial-log + summary artifacts.

### Prior Just-Shipped Milestone Reference (rotated from active position)

**v37.0 Degenerette Recalibration + Maintenance Bundle** (started 2026-05-10; SHIPPED 2026-05-11; closure signal `MILESTONE_V37_AT_HEAD_2654fcc2`)

- **Goal:** Reconcile Degenerette payout calibration with the v34.0 heavy-tail trait producer (pre-launch fix), execute deferred maintenance (lootbox dead-branch cleanup + SURF-05 gas-pin re-pinning), and clear the long-deferred adversarial audit of post-v32.0 commits — all closed under a single `audit/FINDINGS-v37.0.md` deliverable.
- **Audit baseline:** v36.0 audit-subject HEAD `1c0f09132d7439af9881c56fe197f81757f8164a` (signal `MILESTONE_V36_AT_HEAD_1c0f09132d7439af9881c56fe197f81757f8164a`)
- **Phases planned:** 5 (267-271) — 5-phase bundled milestone shape per requirements scope (Degenerette contracts → stat + cross-surface tests → maintenance → post-v32 sub-audit → terminal delta audit)
- **Requirements:** 47 total (15 DGN + 6 STAT + 6 SURF + 3 LBX + 3 GASPIN + 4 DELTA + 6 AUDIT + 4 REG); coverage 47/47 mapped to Phases 267-271
- **READ-only posture:** LIFTED — `contracts/` + `test/` writes via per-commit user approval per `feedback_no_contract_commits.md` + `feedback_batch_contract_approval.md` + `feedback_never_preapprove_contracts.md`; Phase 267 Degenerette rewrite uses single batched contract commit; Phase 269 LBX cleanup uses single batched contract commit; Phase 270 audit-only emits zero source-tree mutations
- **Behavioral change posture:** Acceptable per user disposition — payout-calibration reconciliation IS the intended behavior change; equal-EV invariant satisfied across all 16,384 player-pick configurations within statistical tolerance
- **Adversarial-pass posture:** SEQUENTIAL after full §4 draft per D-NN-ADVERSARIAL-02 carry; `/contract-auditor` + `/zero-day-hunter` in scope; `/economic-analyst` + `/degen-skeptic` deferred to Phase 271 discuss-phase decision (mechanism-design + skeptic review candidates given the payout-recalibration nature)
- **Out of scope (deferred):** ETH daily jackpot recalibration; far-future BURNIE portion (already per-pull random level v35.0); purchase-phase ticket distributions; trait-roll logic outside Degenerette path; `EntropyLib` API additions (v36.0 ENT-04 carry); BAF jackpot `_jackpotTicketRoll` xorshift refactor (v36.0 ENT-05 carry); storage layout changes; new admin / upgrade hooks
- **Closure signal target:** `MILESTONE_V37_AT_HEAD_06623edb` emitted via `audit/FINDINGS-v37.0.md` §9c
- **Phase 267 SHIPPED 2026-05-10:** Degenerette Producer + 5-Table Payout Rewrite. Single batched USER-APPROVED contract commit `e1136071` (`contracts/DegenerusTraitUtils.sol` additive +45 LOC + `contracts/modules/DegenerusGameDegeneretteModule.sol` rewrite +231/-196 LOC); 18 of 18 DGN-01..15 + PAY-SPLIT-01..03 requirements PASS. v37.0 source-tree HEAD = `e1136071`.
- **Phase 268 SHIPPED 2026-05-10:** Degenerette Statistical Validation + Cross-Surface Preservation. Single batched USER-APPROVED test commit `4b277aaf` (3 NEW `test/stat/` files + 1 EXTENDED `test/stat/SurfaceRegression.test.js` v37.0 SURF-01..04 describe + 1 NEW `test/gas/Phase268GasRegression.test.js` + package.json wiring; +2,277/-1 LOC across 6 files); 13 of 13 STAT-01..07 + SURF-01..06 requirements PASS; ZERO source-tree mutations (`git diff e1136071 HEAD -- contracts/` empty at phase close).
- **Phase 269 SHIPPED 2026-05-11 (deliberate partial scope):** Lootbox Dead-Branch Cleanup. Single USER-APPROVED contract commit `8fd5c2e1` (`feat(269): delete unreachable BURNIE-conversion branch in _resolveLootboxRoll [LBX-01]`; `contracts/modules/DegenerusGameLootboxModule.sol` −14/+1 LOC; pure LBX-01 deletion + user-approved cascade param cleanup dropping unused `targetLevel`/`currentLevel` from signature + 2 callsites + 2 NatSpec @param lines; bytecode shrink 177 bytes 18,330→18,153). Plus AGENT-COMMITTED `009cbde3` (`docs(269): GASPIN-01 root-cause inline — fixture-loader caching`; `269-01-PLAN.md` +80 LOC RCA section). **2 of 6 Phase 269 requirements PASS** (LBX-01 + GASPIN-01); 4 DEFERRED to v37+ maintenance (LBX-02 empirical pin — fixture-coverage gap matches Phase 266 GAS-01 precedent; LBX-03 — Phase 271 author computes anchors at audit-trail-authoring time; GASPIN-02/03 — D-269-STAB-01 option (b) `hardhat_reset`+`loadFixture` attempt FAILED structurally with side-effect regressions, options (a)/(c) violate GASPIN-03 or plan scope; SURF-03 re-baseline — Phase 270/271 plan can include one-line edit if needed). Audit cleanliness was the shipped value — per-open runtime savings ~0.005% (sub-0.01%) of typical 600K-1M-gas open. v36.0 acceptance "128k is fine approved" (MILESTONES.md L19) carries forward verbatim. STAT-03 pre-existing failure (`test/stat/PerPullEmptyBucketSkip.test.js` skip rate 88% > 10% threshold; introduced at Phase 264 commit `7dcfeb0c` and unchanged since; failing at every HEAD through Phase 265-268) flagged for Phase 270 or v37+ maintenance pickup.
- **Phase 270 SHIPPED 2026-05-11:** Post-v32.0 Deferred-Commit Adversarial Sub-Audit. Single AGENT-COMMITTED working-file commit `4017b9ec` (`docs(270): post-v32.0 deferred-commit adversarial sub-audit working file [DELTA-01..04]`; `270-01-DELTA-SURFACE.md` +305 LOC; canonical Phase-271-§3.A grep-cite anchor per D-270-FILES-01) + AGENT-COMMITTED phase-close batched commit (`docs(270): phase 270 summary — post-v32.0 deferred-commit adversarial sub-audit complete [DELTA-01..04 PASS]`; `270-01-SUMMARY.md` + STATE.md + REQUIREMENTS.md). **4 of 4 DELTA-01..04 requirements PASS.** Zero source-tree mutations (`git diff --stat contracts/ test/` empty cumulative). Zero FINDING_CANDIDATE rows (8 surface verdicts: SAFE_BY_STRUCTURAL_CLOSURE × 6 + SAFE_BY_DESIGN × 2). 4 RE_VERIFIED-NEGATIVE-scope KI envelope rows (EXC-01 affiliate roll / EXC-02 prevrandao fallback / EXC-03 F-29-04 mid-cycle substitution / EXC-04 EntropyLib XOR-shift NARROWED-to-BAF-only) feed Phase 271 §6b. Phase 271 §3.A grep-cite anchor: `.planning/phases/270-post-v32-0-deferred-commit-adversarial-sub-audit/270-01-DELTA-SURFACE.md`. v37.0 source-tree HEAD at Phase 270 close = `8fd5c2e1` UNCHANGED (Phase 270 emits zero source-tree mutations). Pure agent grep-sweep posture per D-270-ADVERSARIAL-01; `/contract-auditor` + `/zero-day-hunter` SEQUENTIAL skill-tool pass deferred to Phase 271 §4 per D-NN-ADVERSARIAL-02 carry. Phase 146 ABI cleanup `31ec2780` (Apr 9 2026) anchored as Commit B `2713ce61` unreachability cause via design-intent trace per `feedback_design_intent_before_deletion.md` (PRIMARY governing memory).
- See `.planning/ROADMAP.md` for the 5-phase entries + `.planning/notes/2026-05-10-degenerette-payout-recalibration.md` for primary workstream seed + `.planning/notes/2026-05-10-resolveLootboxRoll-dead-burnie-conversion-branch.md` for lootbox cleanup seed.

## Roadmap Overview

| Phase | Goal | Requirements (count) | Depends on |
|-------|------|----------------------|------------|
| 272 — Always-Hero Simplification + Maximal Dead-Code Cleanup (Terminal) — SHIPPED | Drop Degenerette hero opt-out semantics (`_packFullTicketBet` normalizes `heroQuadrant ≥ 4` → `0`; `_resolveFullTicketBet` extracts quadrant unconditionally; `_fullTicketPayout` drops `heroEnabled` parameter); maximal dead-code cleanup sweep narrowed to `DegenerusGameDegeneretteModule.sol` per D-272-CLEAN-SCOPE-01; land v37+ carry bundle (4 COMPLETE + 1 RE-DEFERRED-V39+: LBX-02); single `audit/FINDINGS-v38.0.md` terminal deliverable; closure signal `MILESTONE_V38_AT_HEAD_06623edb` emitted in §9c. Wave 1.5 D-272-INPUT-VALIDATION-01 revision adds input validation at `placeDegeneretteBet` entry (revert with `InvalidBet` on `>= 4`). | HERO-01..05 + CLEAN-01..06 + STAT-01..02 + SURF-01..03 + LBX-02 + GASPIN-02..03 + STAT-03-v35-carry + AUDIT-01..06 + REG-01..04 (30) | Nothing (baseline v37.0 closure HEAD `MILESTONE_V37_AT_HEAD_2654fcc2`) |

**Coverage:** 30/30 v38.0 requirements mapped (5 HERO + 6 CLEAN + 2 STAT + 3 SURF + 1 LBX + 2 GASPIN + 1 PPL + 6 AUDIT + 4 REG); zero orphan requirements; zero duplicate mappings. Resolution at v38 close: 29 Complete + 1 RE-DEFERRED-V39+ (LBX-02).

## Next-Milestone Backlog (v39+)

Carry-forward seeds from v36.0 / v37.0 / v38.0 close. Do NOT pull into v38.0 (already shipped).

| Seed | Subsystem | Target | Notes |
|------|-----------|--------|-------|
| LBX-02 empirical 55%-tickets-path gas-savings pin | lootbox/gas | v39+ | RE-DEFERRED at v38.0 close (fixture-coverage gap persists); path-of-investigation prose at `audit/FINDINGS-v38.0.md` §9.NN.iv; analytical worst-case load-bearing per Phase 266 GAS-01 + `feedback_gas_worst_case.md` |
| BAF jackpot `_jackpotTicketRoll` xorshift refactor | jackpot entropy | v39+ | v36.0 ENT-05 explicit deferral per user disposition; same xorshift pattern as the v36.0-completed lootbox refactor; out of v38.0 scope per `272-CONTEXT.md <out_of_scope>` |
| `runrewardjackpots` module-misplacement | architecture | v39+ | Stale 2026-04-02 backlog note; not v38.0-tagged |
| Game-over thorough hardening | gameover | v39+ | `gameover-thorough-test.md` backlog; out of v38.0 scope; defer to dedicated game-over hardening milestone per `272-CONTEXT.md <out_of_scope>` |

## Deferred Items

Items acknowledged and deferred at v34.0 milestone close on 2026-05-09 (carry-forward chain v32.0 → v33.0 → v34.0 → v35.0 → v36.0 → v37.0 → v38.0):

| Category | Item | Status | Notes |
|----------|------|--------|-------|
| quick_task | 260327-n7h-run-full-test-suite-and-analyze-results- | missing (tracker frontmatter) | Stale pre-v30.0 entry dated 2026-03-27. PLAN.md + SUMMARY.md present on disk; audit tool flags on frontmatter status mismatch only. Carried forward from v29.0 → v30.0 → v31.0 → v32.0 → v33.0 → v34.0 → v35.0 → v36.0 → v37.0 → v38.0 close. |
| quick_task | 260327-q8y-test-boon-changes | missing (tracker frontmatter) | Stale pre-v30.0 entry dated 2026-03-27. PLAN.md + SUMMARY.md present on disk; audit tool flags on frontmatter status mismatch only. Carried forward from v29.0 → v30.0 → v31.0 → v32.0 → v33.0 → v34.0 → v35.0 → v36.0 → v37.0 → v38.0 close. |
| verification_gap | Phase 257 (257-VERIFICATION.md) | human_needed | Gate resolved by Phase 258 supersedence (HUMAN-UAT marked `resolved`, resolved_by: phase-258), but VERIFICATION.md frontmatter `status: human_needed` field was not flipped to `resolved`. Bookkeeping defect; tracker out of date with reality. See `.planning/v33.0-MILESTONE-AUDIT.md`. |
| verification_gap | Phase 258 (258-VERIFICATION.md) | human_needed | Gate resolved by Phase 258-03 stale-reference sweep, but VERIFICATION.md frontmatter `status: human_needed` was not flipped to `resolved`. Bookkeeping defect. See `.planning/v33.0-MILESTONE-AUDIT.md`. |
| process_gap | Phases 254/255/256 missing VERIFICATION.md | not_run | Formal verification gate did not run when those phases closed (pre-session). Phase 257 delta-audit independently re-validated all that work (`audit/FINDINGS-v33.0.md`); functional risk: low. See `.planning/v33.0-MILESTONE-AUDIT.md` for the full per-phase analysis. |
| schema_drift | Phase 255 SUMMARY frontmatter key | requirements:_not_requirements-completed: | All three Phase 255 SUMMARYs (255-01/02/03) use `requirements:` instead of the canonical `requirements-completed:`. Tooling that parses the canonical key misses 10 Phase 255 reqs. Bookkeeping defect; the work itself is complete. See `.planning/v33.0-MILESTONE-AUDIT.md`. |
| schema_drift | Phase 256 SUMMARY req-completion fields | provides:_not_requirements-completed: | 256-03b uses `provides: [TST-03]`; 256-03c uses `provides: [TST-04, TST-06, D-256-GAS-01]`. Both should use `requirements-completed:`. Bookkeeping defect; tests for TST-03/04/06 pass and are part of the v33 governance suite. |
| documentation | ROADMAP.md Phase 257 plan checkbox | unchecked | `- [ ] 257-01-PLAN.md` on line ~196 not ticked despite phase being marked complete. All authoritative completion records (Progress table, MILESTONES.md, STATE.md) confirm completion. Cosmetic. |
| documentation | MILESTONES.md Phase 257 paragraph | "8 of 8 §4 surfaces" | Reads as if Phase 258 didn't add surface (i). The Phase 258 bullet in MILESTONES.md is correct; two paragraphs within the same document are mutually inconsistent. Cosmetic. |
| documentation | audit/FINDINGS-v33.0.md §3.4 commit-count | not extended | §3.4 enumerates 7 post-anchor non-GNRUS commits; post-Phase-258 contract tree has 9 (added `636f60ea` GNRUS-only + `4ce3703d` test-only). Phase 258-03 explicitly deferred this as `D-258-03-§34-COMMIT-COUNT-NOT-EXTENDED` since the new commits are covered elsewhere (`636f60ea` in §3a Part A; `4ce3703d` is test-only). Annotated, not extended. |
| audit_process | Phase 257 Task 7 manual-fallback record | resolved at v34 | The original Phase 257 Task 7 adversarial validation fell back to executor-manual when `/contract-auditor` and `/zero-day-hunter` skills failed to spawn. RESOLVED at v34.0 Phase 262 Task 6 — both skills successfully spawned in parallel with real captured output (see `.planning/milestones/v34.0-phases/262-delta-audit-findings-consolidation/262-01-ADVERSARIAL-LOG.md`). The C4A-warden-contest independence-claim hardening is satisfied at v34 closure HEAD `6b63f6d4`. Concurrent v33.0 close concern (queue-branch redirect bug) was already structurally closed in Phase 258 FIX-01 + FIX-02 prior to the v34 re-run. |

## Accumulated Context

### Phase 276 Plan A — JackpotModule:2216 BAF Bernoulli (executing 2026-05-14)

- **276-A COMPLETE** — 1 USER-APPROVED batched contract commit `c473867e` (`feat(276): jackpot ticket-roll Bernoulli whole-ticket [JPT-BR-01..06]`; `contracts/modules/DegenerusGameJackpotModule.sol` +36/−10; inline Bernoulli round-up in `_jackpotTicketRoll` on `bits[200..215]` + `:2216` call swap to direct `_queueTickets(winner, targetLevel, whole, true)` + bit-allocation NatSpec + `JackpotTicketWin` event-doc/inline-comment rewrite). NOT pushed (local-only; future push is a separate user gate). 6/6 JPT-BR-01..06 satisfied. Storage byte-identical to v39 baseline `6a7455d1` (`276-A-STORAGE-LAYOUT-DIFF.md` PASS); bytecode −513 bytes; gas NET-NEGATIVE analytical (`276-A-GAS-WORSTCASE.md`; empirical FIXTURE_COVERAGE_GAP_NOTED per `feedback_gas_worst_case.md` + Phase 266 GAS-01 precedent).
- **D-276-RNGBYPASS-01 (LOAD-BEARING):** the new `_queueTickets` call passes `rngBypass = true` — this DELIBERATELY OVERRIDES the literal ROADMAP §Phase-276 SC1 + REQUIREMENTS JPT-BR-02 text (which both say `false`, a copy-paste artifact from Phase 275 LBX-AR's surface). `_jackpotTicketRoll` runs inside the `advanceGame` window before `_unlockRng(day)`, so `rngLockedFlag == true` is live every invocation; `false` would revert `advanceGame` at `DegenerusGameStorage.sol:575` on every far-future jackpot ticket roll and freeze the game state machine. The existing `_queueLootboxTickets(... true)` wrapper already passed `rngBypass = true` — the swap preserves the bypass posture, does not introduce a new one. Asymmetry rule: advanceGame-chain ticket awards bypass the RNG lock; claimable-on-demand awards must revert during RNG-lock. **FOLLOW-UP:** ROADMAP SC1 + REQUIREMENTS JPT-BR-02 text flagged for separate correction `false` → `true`.
- **D-276-INLINE-01:** Bernoulli inlined as ~4 function-scope locals, no `_bernoulliWhole` helper, no re-touch of Phase 275's `_resolveLootboxCommon` — change confined to `DegenerusGameJackpotModule.sol`.
- **D-276-EVT-STATUSQUO-01:** `JackpotTicketWin` surface unchanged — `ticketCount` stays pre-Bernoulli scaled (`uint32(quantityScaled)`); Phase 277 EVT-UNI-04 adds the `roundedUp` field.
- **276-B COMPLETE** — 1 USER-APPROVED batched test commit `1568fd5c` (`test(276): jackpot ticket-roll Bernoulli + silent cold-bust + bit-slice independence + 2-roll uniqueness [TST-JPT-BR-01..04]`; 5 files +965/−1: new `contracts/test/JackpotBernoulliTester.sol` `external pure` tester with slice `>> 200` + 3 new test files + `package.json` `test:stat` wiring). 4/4 TST-JPT-BR-01..04 satisfied. Full new-test set green: 29 passing, 0 failing via the canonical multi-file `test:stat` invocation. NOT pushed (local-only; future push is a separate user gate per `feedback_manual_review_before_push.md`).
- **Pre-existing repo quirk noted:** per-file `npx hardhat test <file>` produces a trailing Mocha file-unloader `Cannot find module` error + non-zero exit AFTER assertions pass — Phase 275's committed `LootboxAutoResolveBernoulliEv.test.js` exhibits the identical behavior; canonical run shape is the multi-file `test:stat` invocation.
- **Phase 276 COMPLETE** — both Plan A (contract `c473867e`) and Plan B (test `1568fd5c`) landed as USER-APPROVED commits; neither pushed.

### Phase 277 Plan 01 — Event Surface Unification + Sentinel Retirement, contract wave (executing 2026-05-14)

- **277-01 COMPLETE** — 1 USER-APPROVED batched contract commit `02fb7085` (`feat(277): event surface unification + sentinel retirement [EVT-UNI-01..08]`; 3 files +162/−157: `DegenerusGameLootboxModule.sol` +149/−137, `DegenerusGameJackpotModule.sol` +13/−4, `IDegenerusGameModules.sol` 0/−16). NOT pushed (local-only; future push is a separate user gate per `feedback_manual_review_before_push.md`). 8/8 EVT-UNI-01..08 satisfied.
- **What landed:** `LootboxTicketRoll` event DELETED from both the `IDegenerusGameLootboxModule` interface and the `DegenerusGameLootboxModule` event block (zero remaining references in `contracts/`). `LootBoxOpened` restructured — mislabeled `uint32 indexed index` (emit fed `day` into it) replaced by real `uint48 indexed lootboxIndex` + separate non-indexed `uint32 day`, plus new `bool roundedUp`; `amount`/`burnie`/`bonusBurnie` kept `uint256` wei per D-277-EVT-WIDE-01. `BurnieLootOpen` + `JackpotTicketWin` each gain a `bool roundedUp` (non-indexed). `_resolveLootboxCommon` `index != type(uint48).max` sentinel RETIRED — single unified `_queueTickets(player, targetLevel, whole, false)` flow; manual cold-bust WWXRP consolation re-gated under `if (emitLootboxEvent)`. Auto-resolve callers (`resolveLootboxDirect`, `resolveRedemptionLootbox`) pass `index=0` + `emitLootboxEvent=false` — silent on the advanceGame chain per D-277-AR-SILENT-01.
- **D-277-VIAIR-HELPERS-01 (deviation, Rule 3 blocking):** adding `bool roundedUp` as a 4th named return to the 14-param `_resolveLootboxCommon` tripped a viaIR stack-too-deep error. Resolved by extracting two behavior-preserving `private` helpers — `_lootboxBoonBudget(uint256) pure` (boon-budget BPS/cap arithmetic) and `_accumulateLootboxRolls(...)` (the 1-or-2 `_resolveLootboxRoll` invocations + BURNIE accumulation + scaled-ticket sum) — plus a `{ }` block scope around the split-amount compute. No behavior change; both helpers are `private`, add no entry points.
- **Bytecode delta:** `DegenerusGameLootboxModule` −527 bytes (shrinks despite the 2 new helpers — deleted event def + emit + dual-branch sentinel construct); `DegenerusGameJackpotModule` +23 bytes (`roundedUp` capture + 7th emit arg × 3 sites). Gas worst-case derived analytically first per `feedback_gas_worst_case.md`: manual `openLootBox` net gas-NEGATIVE (deleted `LootboxTicketRoll` LOG3 outweighs +1 `roundedUp` data word), advanceGame-chain auto-resolve net gas-NEGATIVE (full `LootBoxOpened` LOG3 removed), `JackpotTicketWin` +256 gas (1 new data word, unavoidable).
- **D-40N-EVT-BREAK-01 honored:** breaking ABI change accepted — `LootBoxOpened`/`BurnieLootOpen`/`JackpotTicketWin` topic-hashes change, `LootboxTicketRoll` removed; pre-launch, indexer rebuild expected, no live indexer impact. Storage layout byte-identical to v39 baseline `6a7455d1`.
- **Next:** Phase 277 Plan 02 (test wave — `277-02-PLAN.md`).

### Phase 277 Plan 02 — Event Surface Unification + Sentinel Retirement, test wave (executing 2026-05-14)

- **277-02 COMPLETE** — 1 USER-APPROVED batched test commit `6fbee850` (`test(277): event surface unification test wave [TST-EVT-UNI-01..06]`; 7 files +1,341/−379: new `test/unit/EventSurfaceUnification.test.js` +665 + 5 modified precedent test files + `package.json` 1-line `test:evt-uni` wiring). NOT pushed (local-only; future push is a separate user gate per `feedback_manual_review_before_push.md`). 6/6 TST-EVT-UNI-01..06 satisfied. **Phase 277 COMPLETE** — both Plan 01 (contract `02fb7085`) and Plan 02 (test `6fbee850`) landed as USER-APPROVED commits; neither pushed.
- **What landed:** new `test/unit/EventSurfaceUnification.test.js` — six `describe` blocks (one per TST-EVT-UNI requirement) following the Phase 274/275/276 source-structural + compiled-ABI precedent (no end-to-end resolution fixture — that gap stays RE-DEFERRED, LBX-02): topic-hash change tests via `ethers.Interface` on the freshly compiled post-Wave-1 ABIs, `LootboxTicketRoll` removal sweep across `contracts/`, `index != type(uint48).max` sentinel-retirement structural proof, manual/auto-resolve/jackpot field-consistency derived from `futureTickets`/`tickets` + `roundedUp` per D-277-NO-PREROLL-01, auto-resolve silence proof. Plus targeted retargeting of 5 precedent test files off their stale Wave-1 assertions (`LootboxAutoResolveRegression`, `LootboxWholeTicket`, `JackpotTicketRollSilentColdBust`, `LootboxConsolation`, `LootboxAutoResolveSilentColdBust`).
- **D-277-02-FOLDIN-01 (scope expansion, user-approved):** the plan's original `files_modified` named 4 test files; the Task 3 affected-suite run found `LootboxConsolation.test.js` + `LootboxAutoResolveSilentColdBust.test.js` also asserting the retired sentinel surface (8 failures). Per the plan's Task 3 directive they were surfaced to the user rather than silently fixed; the user explicitly approved folding them into the batched diff. Final batched commit = 6 test files + `package.json`.
- **D-277-02-WT05-BASELINE-01:** `LootboxWholeTicket.test.js` TST-WT-05 `[05b]` baseline-diff against v38 `06623edb` replaced with a direct structural assertion — the v38 baseline is three phases stale and the `grep -c` diff-count test was no longer meaningful.
- **Verification:** `npx hardhat test` on all 6 affected files — **107 passing, 0 failing**. `contracts/ContractAddresses.sol` + `package-lock.json` (pre-existing unrelated working-tree changes) deliberately NOT staged. No test references a `preRollTickets` field. Harmless trailing mocha file-unloader `MODULE_NOT_FOUND` on per-file CLI runs is a documented repo quirk (Phase 275/276 precedent), does not affect results.
- **Next:** Phase 277 verification gate, then Phase 276/278/279 surface phases per the v40.0 ROADMAP sequencing.

Decisions and completed milestones logged in `.planning/PROJECT.md`.
Detailed milestone retrospectives in `.planning/RETROSPECTIVE.md` (v37.0 / v36.0 / v35.0 sections most recent).
Archived milestone artifacts:

- v37.0: `.planning/milestones/v37.0-phases/` (267-271 archived per phase rotation)
- v36.0: `.planning/milestones/v36.0-ROADMAP.md`, `v36.0-REQUIREMENTS.md`, `v36.0-phases/`
- v35.0: `.planning/milestones/v35.0-ROADMAP.md`, `v35.0-REQUIREMENTS.md`, `v35.0-phases/` (if rotated)
- v34.0: `.planning/milestones/v34.0-ROADMAP.md`, `v34.0-REQUIREMENTS.md`, `v34.0-phases/`
- v33.0: `.planning/milestones/v33.0-ROADMAP.md`, `v33.0-REQUIREMENTS.md`, `v33.0-phases/`
- v32.0: `.planning/milestones/v32.0-ROADMAP.md`, `v32.0-REQUIREMENTS.md`, `v32.0-phases/`
- v31.0: `.planning/milestones/v31.0-ROADMAP.md`, `v31.0-REQUIREMENTS.md`, `v31.0-phases/`
- v30.0: `.planning/milestones/v30.0-ROADMAP.md`, `v30.0-REQUIREMENTS.md`, `v30.0-phases/`
- v29.0: `.planning/milestones/v29.0-ROADMAP.md`, `v29.0-REQUIREMENTS.md`, `v29.0-phases/`
- Earlier: `.planning/milestones/` (v2.1 onward)

Audit deliverables:

- `audit/FINDINGS-v38.0.md` (FINAL READ-only at HEAD `06623edb`, ~850 lines, 9 sections; 7 of 7 §4 adversarial surfaces SAFE / SAFE_BY_DESIGN / SAFE_BY_STRUCTURAL_CLOSURE; zero F-38-NN findings; 1 PASS REG-01 + 1 PASS REG-02 + REG-03 KI envelope re-verifications + REG-04 prior-finding spot-check sweep; 4 KI envelope re-verifications (EXC-01..03 NEGATIVE-scope at v38; EXC-04 RE_VERIFIED with NARROWS retained to BAF-jackpot-only); KNOWN-ISSUES.md UNMODIFIED; 3-skill PARALLEL adversarial-pass `/contract-auditor` + `/zero-day-hunter` + `/economic-analyst` zero disagreement; Hypothesis (i) RESOLVED_AT_V38 via Wave 1.5 commit `4760459f`; closure signal `MILESTONE_V38_AT_HEAD_06623edb`)
- `audit/FINDINGS-v37.0.md` (FINAL READ-only at HEAD `MILESTONE_V37_AT_HEAD_2654fcc2`, 9 sections; 8 of 8 §4 adversarial surfaces SAFE / SAFE_BY_DESIGN / SAFE_BY_STRUCTURAL_CLOSURE; zero F-37-NN findings; 1 PASS REG-01 + 1 PASS REG-02 + 5 PASS + 1 SUPERSEDED REG-04; 4 NEGATIVE-scope/RE_VERIFIED KI envelope re-verifications; KNOWN-ISSUES.md UNMODIFIED; closure signal `MILESTONE_V37_AT_HEAD_2654fcc2`)
- `audit/FINDINGS-v36.0.md` (FINAL READ-only at HEAD `1c0f09132d7439af9881c56fe197f81757f8164a`, ~700 lines, 9 sections; 6 of 6 §4 adversarial surfaces SAFE_BY_DESIGN / SAFE_BY_STRUCTURAL_CLOSURE; zero F-36-NN findings; 1 PASS REG-01 + 1 PASS REG-02 + 11 PASS REG-04; 4 KI envelope re-verifications (EXC-01..03 NEGATIVE-scope at v36; EXC-04 RE_VERIFIED with NARROWS to BAF-jackpot-only); KNOWN-ISSUES.md modified by 1 entry rephrase EntropyLib XOR-shift NARROWS to BAF-only scope per AUDIT-05; closure signal `MILESTONE_V36_AT_HEAD_1c0f09132d7439af9881c56fe197f81757f8164a`)
- `audit/FINDINGS-v35.0.md` (FINAL READ-only at HEAD `5db8682bd7b811437f0c1cf47e832619d1478ac6`, ~600 lines, 9 sections; 6 of 6 §4 adversarial surfaces SAFE / SAFE_BY_DESIGN / SAFE_BY_STRUCTURAL_CLOSURE; zero F-35-NN findings; 1 PASS REG-01 + 1 PASS REG-02 + 9 PASS + 1 SUPERSEDED REG-04; 4 NEGATIVE-scope/RE_VERIFIED KI envelope re-verifications; KNOWN-ISSUES.md UNMODIFIED; closure signal `MILESTONE_V35_AT_HEAD_5db8682bd7b811437f0c1cf47e832619d1478ac6`)
- `audit/FINDINGS-v34.0.md` (FINAL READ-only at HEAD `6b63f6d4daf346a53a1d463790f637308ea8d555`, ~700 lines, 9 sections; 6 of 6 §4 adversarial surfaces SAFE_BY_DESIGN / SAFE_BY_STRUCTURAL_CLOSURE; zero F-34-NN findings; 1 PASS REG-01 + 1 PASS REG-02 + 4 PASS REG-04; 4 NEGATIVE-scope/RE_VERIFIED KI envelope re-verifications; KNOWN-ISSUES.md UNMODIFIED; closure signal `MILESTONE_V34_AT_HEAD_6b63f6d4daf346a53a1d463790f637308ea8d555`)
- `audit/FINDINGS-v33.0.md` (FINAL READ-only at HEAD `4ce3703d740d3707c88a1af595618120a8168399`, ~750 lines, 9 sections + Phase 258 §3a/§4/§5/§9 updates; 9 of 9 §4 adversarial surfaces SAFE / SAFE_BY_DESIGN / SAFE_BY_STRUCTURAL_CLOSURE / SAFE_BY_TRUST_ASYMMETRY; zero F-33-NN findings; closure signal `MILESTONE_V33_AT_HEAD_4ce3703d740d3707c88a1af595618120a8168399` supersedes `MILESTONE_V33_AT_HEAD_dcb70941`)
- `audit/FINDINGS-v32.0.md` (548 lines, 9 sections, FINAL READ-only at HEAD `acd88512`; 2 HIGH SUPERSEDED-at-HEAD F-32-NN disclosure blocks; closure signal `MILESTONE_V32_AT_HEAD_acd88512`)
- `audit/v32-247-DELTA-SURFACE.md` through `audit/v32-252-POST31.md` (FINAL READ-only at HEAD `acd88512`; 6 v32 supporting working-file appendices)
- `audit/FINDINGS-v31.0.md` (403 lines, 9 sections; 0 CRITICAL/HIGH/MEDIUM/LOW/INFO; closure signal `MILESTONE_V31_CLOSED_AT_HEAD_cc68bfc7`)
- `audit/FINDINGS-v30.0.md` (729 lines, 10 sections; 17 INFO / 31-row regression PASS / 0 KI promotions)
- `audit/FINDINGS-v29.0.md`, `audit/FINDINGS-v28.0.md`, `audit/FINDINGS-v27.0.md`, `audit/FINDINGS-v25.0.md` (prior milestones)
- `audit/v31-243-DELTA-SURFACE.md` (FINAL READ-only) + `audit/v31-244-PER-COMMIT-AUDIT.md` (FINAL READ-only) + `audit/v31-245-SDR-GOE.md` (FINAL READ-only) + 6 v31 working-file appendices
- `audit/v30-*.md` — 16 upstream Phase 237-241 proof artifacts (byte-identical since Phase 242 plan-start)

## Global Project State

- Contract tree at v39.0 audit-subject HEAD `6a7455d1` (resolved at Wave 3 Task 3.10 atomic-update; this STATE.md row updated atomically at the same point).
- READ-only audit pattern carried forward v28.0–v31.0; **READ-only LIFTED for v32.0 + v33.0 + v34.0 + v35.0 + v36.0 + v37.0 + v38.0 + v39.0** — audit-then-commit (or impl-then-audit) with per-commit user approval per `feedback_no_contract_commits.md` + `feedback_batch_contract_approval.md` + `feedback_never_preapprove_contracts.md` + `feedback_manual_review_before_push.md`. No agent commits contracts/ or test/ changes without explicit user review of the diff. v38.0 Phase 272 used 2 USER-APPROVED batched commits (Wave 1 contracts `527e3adc` + Wave 2 tests `e3fcb95c`) + 1 USER-APPROVED Wave 1.5 input-validation revision (commit `4760459f`).
- KNOWN-ISSUES.md: 4 accepted RNG-determinism exceptions (EXC-01 affiliate roll / EXC-02 prevrandao fallback / EXC-03 F-29-04 mid-cycle substitution / EXC-04 EntropyLib XOR-shift) — all re-verified non-widening at v39 HEAD. EXC-01..03 NEGATIVE-scope at v39 (Phase 274 has zero affiliate-roll / AdvanceModule / gameover-RNG-substitution interaction); EXC-04 RE_VERIFIED with NARROWS retained from v36.0 (BAF-jackpot-only scope unchanged; EntropyLib byte-identical at v39 HEAD; the new bits[152..167] Bernoulli reads keccak primary chunk NOT xorshift output per backward-trace cite).

## Operator Next Steps

- Start the next milestone with /gsd-new-milestone

## Performance Metrics

| Phase | Plan | Duration | Tasks | Files |
|-------|------|----------|-------|-------|
| 277 | 02 | ~1h | 3 | 7 |

## Decisions

- [Phase 277]: D-277-02-FOLDIN-01: LootboxConsolation + LootboxAutoResolveSilentColdBust folded into 277-02 batched test diff with explicit user approval — 277-01 sentinel retirement invalidated their assertions, expanding scope from 4 to 6 test files + package.json
- [Phase 277]: D-277-02-WT05-BASELINE-01: TST-WT-05 [05b] baseline-diff (vs v38 06623edb) replaced with a direct structural assertion — v38 baseline three phases stale, diff-count test no longer meaningful
