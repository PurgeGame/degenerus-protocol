# Requirements: v38.0 Always-Hero Simplification + Maximal Dead-Code Cleanup

**Milestone:** v38.0
**Audit baseline:** `MILESTONE_V37_AT_HEAD_2654fcc2`
**Phase shape:** Single-phase patch (Phase 272 multi-wave) per v36.0 Phase 266 precedent
**Single deliverable:** `audit/FINDINGS-v38.0.md` (terminal phase per D-NN-FCITE-01 carry)

## Out of Scope

- ETH daily jackpot recalibration (carry from v37+)
- BAF jackpot `_jackpotTicketRoll` xorshift refactor (v36.0 ENT-05 carry; same xorshift pattern as v36 lootbox refactor; out of v38.0 scope)
- New storage layout / new admin / new upgrade hooks
- New public/external mutation entry points
- KNOWN-ISSUES.md modifications (default zero-promotion path; deviation requires explicit user disposition + adversarial-pass surfaced FINDING_CANDIDATE)
- Game-over thorough hardening (defer to dedicated game-over hardening milestone)

## v38.0 Requirements

### HERO — Always-On Hero Quadrant (Phase 272 Wave 1; contracts/modules/DegenerusGameDegeneretteModule.sol)

- [ ] **HERO-01** (revised by D-272-INPUT-VALIDATION-01, Wave 1.5): `_packFullTicketBet` packs hero unconditionally. Wave 1 shipped the silent-normalize variant (`uint8 effectiveQuadrant = heroQuadrant < 4 ? heroQuadrant : 0;`); Wave 1.5 added defensive boundary validation at `placeDegeneretteBet` entry that reverts with `InvalidBet` for `heroQuadrant >= 4` (including `0xFF`), making the pack-side normalization dead-but-defensive. Public API signature `placeDegeneretteBet(..., uint8 heroQuadrant)` UNCHANGED at selector/parameter-type level; semantics shift from "accept + normalize" to "reject invalid input". Frontend MUST send valid 0..3 (default 0 if user does not pick).
- [ ] **HERO-02**: `_resolveFullTicketBet` extracts `heroQuadrant` directly from packed bet without `heroEnabled` bit check: `uint8 heroQuadrant = uint8((packed >> (FT_HERO_SHIFT + 1)) & MASK_2);`. The `heroEnabled` local variable + 3-bit `heroBits` extraction REMOVED. The enabled bit at `FT_HERO_SHIFT + 0` becomes vestigial (always 1) — leave bit allocation at 3 bits to avoid storage-layout shift; freed bit may be reclaimed for future feature.
- [ ] **HERO-03**: `_fullTicketPayout` signature drops `bool heroEnabled` parameter. Resolve-time guard simplifies from `if (heroEnabled && matches >= 2 && matches < 8)` to `if (matches >= 2 && matches < 8)`. `_applyHeroMultiplier` itself UNCHANGED — same boost/penalty math, same per-N table dispatch.
- [ ] **HERO-04**: NatSpec rewrites describing what IS at v38 close per `feedback_no_history_in_comments.md`: `_packFullTicketBet` doc explains hero is always-on with quadrant 0 default; `_fullTicketPayout` doc explains hero always applies for M ∈ {2..7}; `_applyHeroMultiplier` doc unchanged. NO prose describing "previously was opt-out" or "v37 → v38 change".
- [ ] **HERO-05** (revised by D-272-INPUT-VALIDATION-01, Wave 1.5): Storage layout byte-identical at v38.0 phase-close HEAD vs v37.0 baseline `2654fcc2` (storage-slot grep proof); zero new public/external mutation entry points; zero new external pure entry points; zero new admin functions; zero new modifiers — single batched USER-APPROVED contract commit lands per `feedback_batch_contract_approval.md` + `feedback_no_contract_commits.md` + `feedback_never_preapprove_contracts.md`. **Public ABI `placeDegeneretteBet(..., uint8 heroQuadrant)` signature byte-identical; semantics shift to defensive boundary validation: `0xFF` and any `>= 4` input revert with `InvalidBet` at entry (Wave 1.5 commit `4760459f`). Frontend MUST send valid 0..3 (default 0 if user does not pick); 0xFF sentinel no longer accepted.**

### CLEAN — Maximal Dead-Code Cleanup Sweep (Phase 272 Wave 1; contracts/ — modules + libraries + main)

- [ ] **CLEAN-01**: `/gas-audit` orchestrator (`/gas-scavenger` candidate-discovery + `/gas-skeptic` validation) runs across all `contracts/` files. Produces a candidate-removal list with per-item: file path, line range, type {unused constant, unreachable branch, stale comment, redundant guard, dead function}, design-intent trace per `feedback_design_intent_before_deletion.md`, removal verdict.
- [ ] **CLEAN-02**: Unused private/internal constants removed across modules. Grep recipe: for each `uint*\|bytes*\|address constant` declaration, count callsites; if 0 callsites at HEAD, candidate for removal subject to design-intent trace. Examples likely surfaced: dead packed constants from pre-v37 designs (any leftover from `_evNormalizationRatio` deletion); deprecated salt constants; orphaned mask constants.
- [ ] **CLEAN-03**: Unreachable branches removed per `feedback_no_dead_guards.md` (extend the LBX-01 caller-clamp invariant analysis to other modules). Candidates: MintModule pre-validated paths; JackpotModule guarded paths whose callers already enforce; AdvanceModule branch dominators. Each candidate traces caller-clamp invariant before removal.
- [ ] **CLEAN-04**: Stale comments rewritten or removed per `feedback_no_history_in_comments.md`. Comments referencing pre-v37 design (single-table dispatch, opt-out hero, pre-LBX-01 lootbox branch, pre-v34 trait producer) rewritten to describe what IS at v38 close, OR deleted if non-load-bearing. NatSpec audit: every `@param` / `@return` / `@notice` block describes current behavior only.
- [ ] **CLEAN-05**: Redundant safety guards removed. Candidates: re-checks of invariants already enforced upstream; constant comparisons that are tautologically true; `unchecked` blocks whose bounds are statically provable. Each removal preserves the safety property via upstream enforcement (proof inline in commit message or NatSpec).
- [ ] **CLEAN-06**: Single batched USER-APPROVED contract commit `feat(272): always-on hero default 0 + dead-code cleanup sweep [HERO-01..05, CLEAN-01..05]` (or batched into 2 commits at planner discretion if cleanup scope is large — HERO + CLEAN may split). Per `feedback_no_contract_commits.md` + `feedback_batch_contract_approval.md`: full diff presented at user-approval gate; explicit `approved` string awaited; no push until manual review per `feedback_manual_review_before_push.md`. Bytecode shrink delta reported in commit message.

### STAT — Hero-Always-On Statistical Re-Validation (Phase 272 Wave 2; test/stat/)

- [ ] **STAT-01**: `test/stat/DegeneretteBonusEv.test.js` re-validation under always-on hero — re-pin STAT-03 per-N hero EV within ±1% at ≥100K hero-active draws/N. Since hero is now mandatory, the test setup simplifies (no `heroEnabled=false` baseline run needed); EV-neutrality formula `P(hero|M,N) × boost + (1−P) × HERO_PENALTY = HERO_SCALE` checked at each (M, N) via existing per-N HERO_BOOST tables (UNCHANGED at v38).
- [ ] **STAT-02**: `test/stat/DegenerettePerNEvExactness.test.js` re-validation — basePayoutEV per N still 100.00 ± 0.50 centi-x at ≥1M draws/N (hero composition is multiplicative on top of base; basePayoutEV definition unchanged). STAT-07 ETH 3-tier split + thin-pool cap-flip describe blocks UNCHANGED (PAY-SPLIT rule UNCHANGED at v38).

### SURF — Cross-Surface Preservation (Phase 272 Wave 2; test/stat/SurfaceRegression.test.js)

- [ ] **SURF-01**: v38.0 SURF-01..04 describe block extension confirming byte-identity vs v37.0 baseline `2654fcc2` of: (a) `DegenerusTraitUtils.sol` (Mint + Jackpot + Degenerette producer paths UNTOUCHED at v38); (b) `DegenerusGameJackpotModule.sol` (gold-solo + BAF jackpot UNTOUCHED); (c) `DegenerusGameMintModule.sol` (no v38 mutations); (d) `EntropyLib.sol` (ENT-04 v36.0 carry). Only mutation should be `DegenerusGameDegeneretteModule.sol` + any cleanup-sweep files surfaced by `/gas-audit`.
- [ ] **SURF-02**: v38.0 LBX-03 re-anchor (post-LBX-01 + any v38 cleanup-sweep changes in `_resolveLootboxRoll`). 4 hash2/bit-slice callsites byte-identical at structural level; line numbers anchored at v38 HEAD via `grep -nE "hash2|seed >> |_lootboxTicketCount|_lootboxDgnrsReward" contracts/modules/DegenerusGameLootboxModule.sol` at audit-trail-authoring time.
- [ ] **SURF-03 (v37+ carry-forward pickup)**: re-baseline `test/stat/SurfaceRegression.test.js:752` v37.0 SURF-03 it block from `V36_BASELINE` → `PHASE_269_CLOSE_BASELINE = "8fd5c2e1..."` (post-LBX-01 HEAD). SURF-01/02/04 remain anchored at v36.0 baseline `1c0f0913`. One-line edit; closes v37.0 §9.NN.iv carry-forward item.

### LBX — v37+ Carry-Forward Pickup (Phase 272 Wave 2; test/gas/)

- [ ] **LBX-02 (v37+ carry-forward pickup)**: empirical 55%-tickets-path gas-savings test pin in `test/gas/LootboxOpenGas.test.js`. Add `it("v37.0 LBX-01 saves 20-50 gas on 55%-tickets-path")` describe block that constructs the openable-lootbox fixture (Phase 266 GAS-01 precedent if fixture-coverage gap was structural), measures gas pre/post LBX-01 hypothetically (or against pinned baseline). Closes v37.0 §9.NN.iv carry-forward item. If fixture-coverage gap REMAINS unresolvable, document the path-of-investigation inline (per Phase 266 GAS-01 `feedback_gas_worst_case.md` precedent: analytical worst-case load-bearing) and re-defer to v39+ via §9.NN.iv.

### GASPIN — SURF-05 Gas-Pin Stabilization (Phase 272 Wave 2; test/stat/ + test/gas/)

- [ ] **GASPIN-02 (v37+ carry-forward pickup)**: D-269-STAB-01 retry — choose one of: (a) refined `hardhat_reset` sequencing; (b) test-isolation via dedicated mocha config (separate `npm run test:gas` script splitting Phase261GasRegression + Phase264GasRegression off `test:stat`); (c) widened tolerance ceiling (last resort; preserves "128k is fine approved" v36.0 acceptance but as documented configurable tolerance). Goal: clean `npm run test:stat` start-to-finish in CI-equivalent fresh-checkout. Decision documented inline at test fixture or in 272-01-PLAN.md.
- [ ] **GASPIN-03 (v37+ carry-forward pickup)**: Verify clean `npm run test:stat` start-to-finish at v38.0 phase-close HEAD with zero flaky failures. Both standalone and combined-suite gas pins agree within tolerance. If GASPIN-02 chose option (c) widened-tolerance, the new tolerance is documented as v38 ACCEPTED-TOLERANCE per `feedback_no_history_in_comments.md` discipline.

### PPL — PerPullEmptyBucketSkip Fixture Retune (Phase 272 Wave 2; test/stat/)

- [ ] **STAT-03-v35-carry (v37+ carry-forward pickup)**: `test/stat/PerPullEmptyBucketSkip.test.js` fixture density retune per Phase 264 D-IMPL-07 mid/late-game holder-density spec. Either (a) populate the deity-backed dense fixture so empty-bucket skip rate drops below 10% threshold; OR (b) document the actual production-floor rate (88.24% empty-bucket skip in current sparse fixture per v35.0 Phase 265 D-265-STAT03-01 reframe) as an ACCEPTED-DESIGN ledger entry referencing the fixture-calibration-error reframe.

### AUDIT — Delta Audit + Findings Consolidation (Phase 272 terminal wave)

- [ ] **AUDIT-01**: `audit/FINDINGS-v38.0.md` §3.A delta-surface table covering all source-tree changes v37.0 baseline `2654fcc2` → v38.0 closure HEAD. All Phase 272 contract changes (HERO-01..05 + CLEAN-01..05 removals) enumerated with hunk-level evidence + {NEW, MODIFIED_LOGIC, REFACTOR_ONLY, DELETED} classification.
- [ ] **AUDIT-02**: Adversarial sweep verdicts every Phase 272 surface SAFE / SAFE_BY_DESIGN / SAFE_BY_STRUCTURAL_CLOSURE / FINDING_CANDIDATE with grep-cited evidence. Minimum surfaces: (a) hero always-on EV-neutrality preserved across (M, N); (b) hero quadrant 0 default does NOT create payout-bias for players who omit heroQuadrant; (c) each cleanup-sweep removal preserves the invariant the removed code claimed to guard (per `feedback_no_dead_guards.md` + `feedback_design_intent_before_deletion.md`); (d) storage layout byte-identical; (e) public ABI byte-identical (`placeDegeneretteBet` signature UNCHANGED).
- [ ] **AUDIT-03**: Conservation re-proof — total payout invariant `ethShare + lootboxShare = payout` preserved (PAY-SPLIT UNCHANGED at v38); per-N basePayoutEV = 100 centi-x exact preserved (per-N tables UNCHANGED at v38); hero EV-neutrality preserved across all (M, N) combinations under always-on hero; no new mint sites; solvency invariant unchanged.
- [ ] **AUDIT-04**: Zero-new-state scan — zero new storage slots; zero new public/external mutation entry points; zero new external pure entry points; zero new admin functions; zero new modifiers; existing storage layout byte-identical at v38 HEAD.
- [ ] **AUDIT-05**: `audit/FINDINGS-v38.0.md` published as milestone deliverable; FINAL READ-only at v38.0 closure HEAD; closure signal `MILESTONE_V38_AT_HEAD_<sha>` emitted in §9c with verbatim presence in 5 FINDINGS locations + 3 cross-document propagation targets. KNOWN-ISSUES.md walkthrough — default zero-promotion path per D-271-KI-01 carry; deviation requires user disposition + explicit FINDING_CANDIDATE from adversarial pass.
- [ ] **AUDIT-06**: Adversarial pass via `/contract-auditor` + `/zero-day-hunter` + `/economic-analyst` PARALLEL spawn per D-271-ADVERSARIAL-01 carry on finished §4 draft (`/degen-skeptic` OUT OF SCOPE per D-271-ADVERSARIAL-02 carry). 3 H2 sections in `272-01-ADVERSARIAL-LOG.md` + Disposition note.

### REG — Regression Checks (Phase 272 terminal wave)

- [ ] **REG-01**: v37.0 closure signal `MILESTONE_V37_AT_HEAD_2654fcc2` re-verified non-widening at v38.0 HEAD. Mint + Jackpot + EntropyLib + JackpotBucketLib byte-identical. Lootbox unchanged except for any cleanup-sweep changes flagged at AUDIT-01.
- [ ] **REG-02**: v34.0 closure signal `MILESTONE_V34_AT_HEAD_6b63f6d4daf346a53a1d463790f637308ea8d555` re-verified non-widening at v38.0 HEAD. TraitUtils existing 3 functions + `_pickSoloQuadrant` + JackpotBucketLib byte-identical.
- [ ] **REG-03**: KI envelope re-verifications. EXC-01..03 NEGATIVE-scope at v38 (Phase 272 has zero affiliate-roll / AdvanceModule / gameover-RNG-substitution interaction). EXC-04 RE_VERIFIED with NARROWS retained (BAF-jackpot-only scope; EntropyLib byte-identical at v38 HEAD).
- [ ] **REG-04**: Prior-finding spot-check sweep across audit/FINDINGS-v25.0.md → audit/FINDINGS-v37.0.md for findings referencing v38-touched function/surface set (`_fullTicketPayout`, `_packFullTicketBet`, `_applyHeroMultiplier`, any cleanup-sweep surfaces). Default expectation: all rows PASS; SUPERSEDED allowed with explicit successor cite.

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| HERO-01 | Phase 272 | Complete (revised by D-272-INPUT-VALIDATION-01 Wave 1.5; Wave 1 commit `527e3adc` + Wave 1.5 commit `4760459f`) |
| HERO-02 | Phase 272 | Complete (Wave 1 commit `527e3adc`) |
| HERO-03 | Phase 272 | Complete (Wave 1 commit `527e3adc`) |
| HERO-04 | Phase 272 | Complete (Wave 1 commit `527e3adc`) |
| HERO-05 | Phase 272 | Complete (revised by D-272-INPUT-VALIDATION-01 Wave 1.5; commit `4760459f` validates `heroQuadrant < 4` at entry, reverts with `InvalidBet` on `>= 4`) |
| CLEAN-01 | Phase 272 | Complete (Wave 1 commit `527e3adc` — `/gas-audit` candidate-discovery + design-intent trace per `feedback_design_intent_before_deletion.md`) |
| CLEAN-02 | Phase 272 | Complete (Wave 1 commit `527e3adc`) |
| CLEAN-03 | Phase 272 | Complete (Wave 1 commit `527e3adc`) |
| CLEAN-04 | Phase 272 | Complete (Wave 1 commit `527e3adc`) |
| CLEAN-05 | Phase 272 | Complete (Wave 1 commit `527e3adc`) |
| CLEAN-06 | Phase 272 | Complete (Wave 1 USER-APPROVED batched contract commit `527e3adc` per `feedback_batch_contract_approval.md`; Wave 1.5 USER-APPROVED revision commit `4760459f`) |
| STAT-01 | Phase 272 | Complete (Wave 2 batched test commit `e3fcb95c`) |
| STAT-02 | Phase 272 | Complete (Wave 2 batched test commit `e3fcb95c`) |
| SURF-01 | Phase 272 | Complete (Wave 2 batched test commit `e3fcb95c`) |
| SURF-02 | Phase 272 | Complete (Wave 2 batched test commit `e3fcb95c`) |
| SURF-03 | Phase 272 | Complete (v37+ carry resolved; Wave 2 commit `e3fcb95c` — re-baselined to `PHASE_269_CLOSE_BASELINE = "8fd5c2e1..."`) |
| LBX-02 | Phase 272 | RE-DEFERRED-V39+ (v37+ carry; fixture-coverage gap persists at v38 — empirical 55%-tickets-path pin not feasible without new fixture infrastructure; analytical worst-case load-bearing per Phase 266 GAS-01 precedent + `feedback_gas_worst_case.md`; path-of-investigation prose at `audit/FINDINGS-v38.0.md` §9.NN.iv) |
| GASPIN-02 | Phase 272 | Complete (v37+ carry resolved via (a-alt) script-split per planner pick; Wave 2 commit `e3fcb95c` includes `package.json` `test:gas` script splitting Phase261GasRegression + Phase264GasRegression off `test:stat`) |
| GASPIN-03 | Phase 272 | Complete (v37+ carry resolved; clean `npm run test:stat` + `npm run test:gas` runs verified at v38.0 phase-close HEAD; Wave 2 commit `e3fcb95c`) |
| STAT-03-v35-carry | Phase 272 | Complete (v37+ carry resolved via ACCEPTED-DESIGN ledger entry per planner pick option (b); Wave 2 commit `e3fcb95c` — `test/stat/PerPullEmptyBucketSkip.test.js` header documents 88.24% empty-bucket skip rate on sparse-fixture as fixture-calibration-error reframe per v35.0 Phase 265 D-265-STAT03-01) |
| AUDIT-01 | Phase 272 | Complete (Wave 3 audit-deliverable commit `b3f6af6d` — §3.A delta-surface table) |
| AUDIT-02 | Phase 272 | Complete (Wave 3 audit-deliverable commit `78e8bec1` — §4 7-surface adversarial-sweep draft) |
| AUDIT-03 | Phase 272 | Complete (Wave 3 audit-deliverable commit `b3f6af6d` — §3.C conservation re-proof) |
| AUDIT-04 | Phase 272 | Complete (Wave 3 audit-deliverable commits `b3f6af6d` + `079ec007` — §3.B zero-new-state + §8 forward-cite closure) |
| AUDIT-05 | Phase 272 | Complete (Wave 3 + Wave 4 — `audit/FINDINGS-v38.0.md` published; closure signal emitted §9c; Wave 4 atomic SHA resolution + FINAL READ-only flip at user-review gate) |
| AUDIT-06 | Phase 272 | Complete (Wave 3 3-skill PARALLEL adversarial-pass commit `873b8295` — `/contract-auditor` + `/zero-day-hunter` + `/economic-analyst` per D-271-ADVERSARIAL-01 carry; Wave 1.5 disposition update commit `1249a6fd` — Hypothesis (i) RESOLVED_AT_V38) |
| REG-01 | Phase 272 | Complete (Wave 3 audit-deliverable commit `fa4e3991` — §5 REG-01 v37.0 closure non-widening re-verified) |
| REG-02 | Phase 272 | Complete (Wave 3 audit-deliverable commit `fa4e3991` — §5 REG-02 v34.0 closure non-widening re-verified) |
| REG-03 | Phase 272 | Complete (Wave 3 audit-deliverable commit `079ec007` — §6 KI envelope re-verifications EXC-01..04) |
| REG-04 | Phase 272 | Complete (Wave 3 audit-deliverable commit `fa4e3991` — §5 prior-finding spot-check sweep across audit/FINDINGS-v25..v37.0) |

**Coverage:**
- v38.0 requirements: 30 total (5 HERO + 6 CLEAN + 2 STAT + 3 SURF + 1 LBX + 2 GASPIN + 1 PPL + 6 AUDIT + 4 REG)
- Mapped to phase: 30 → Phase 272 (single-phase multi-wave shape)
- Unmapped: 0
- **Resolution at v38 close:** 29/30 Complete + 1/30 RE-DEFERRED-V39+ (LBX-02 — fixture-coverage gap persists).

**v37+ carry-forward pickup count:** 5 items folded in. Resolution at v38 close: 4 COMPLETE (SURF-03 + GASPIN-02 + GASPIN-03 + STAT-03-v35-carry) + 1 RE-DEFERRED-V39+ (LBX-02 with path-of-investigation prose). Closes the COMPLETE branch of v37.0 §9.NN.iv carry-forward register; LBX-02 path-of-investigation prose lives in `audit/FINDINGS-v38.0.md` §9.NN.iv.
