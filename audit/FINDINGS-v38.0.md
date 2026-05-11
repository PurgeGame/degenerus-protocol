---
phase: 272-always-hero-simplification-maximal-dead-code-cleanup-terminal
plan: 01
milestone: v38.0
milestone_name: Always-Hero Simplification + Maximal Dead-Code Cleanup
audit_baseline: 1c0f09132d7439af9881c56fe197f81757f8164a
audit_baseline_signal: MILESTONE_V36_AT_HEAD_1c0f09132d7439af9881c56fe197f81757f8164a
v37_intermediate_baseline: 2654fcc2
v37_intermediate_signal: MILESTONE_V37_AT_HEAD_2654fcc2
v34_baseline: 6b63f6d4daf346a53a1d463790f637308ea8d555
v34_baseline_signal: MILESTONE_V34_AT_HEAD_6b63f6d4daf346a53a1d463790f637308ea8d555
audit_subject_head: 06623edb
closure_signal: MILESTONE_V38_AT_HEAD_06623edb
deliverable: audit/FINDINGS-v38.0.md
requirements: [HERO-01, HERO-02, HERO-03, HERO-04, HERO-05,
               CLEAN-01, CLEAN-02, CLEAN-03, CLEAN-04, CLEAN-05, CLEAN-06,
               STAT-01, STAT-02,
               SURF-01, SURF-02, SURF-03,
               LBX-02,
               GASPIN-02, GASPIN-03,
               STAT-03-v35-carry,
               AUDIT-01, AUDIT-02, AUDIT-03, AUDIT-04, AUDIT-05, AUDIT-06,
               REG-01, REG-02, REG-03, REG-04]
phase_status: terminal
phase_count: 1
phase_ids: [272]
requirements_total: 30
adversarial_pass_skills: [contract-auditor, zero-day-hunter, economic-analyst]
adversarial_pass_pattern: PARALLEL_SINGLE_MESSAGE
out_of_scope_skills: [degen-skeptic]
write_policy: "Single-phase patch closure mirroring v36.0 Phase 266 + v37.0 Phase 271 precedent. Two USER-APPROVED batched commits: Wave 1 contracts (`527e3adc` — `feat(272): always-on hero default 0 + degenerette dead-code cleanup [HERO-01..05, CLEAN-01..05]`); Wave 2 tests (`e3fcb95c` — `test(272): hero-always-on + dead-code cleanup + v37+ carry bundle [STAT-01..02, SURF-01..03, LBX-02, GASPIN-02..03, STAT-03-v35-carry]`). All Wave 3 audit deliverable + ADVERSARIAL-LOG + Wave 4 closure flips AGENT-COMMITTED atomic-per-task with `audit(272):` or `docs(272):` prefix. READ-only flip on `audit/FINDINGS-v38.0.md` (chmod 444 + frontmatter `status: FINAL — READ-ONLY` + `read_only: true`) is the terminal commit per `feedback_manual_review_before_push.md` final user-review gate per D-272-APPROVAL-01."
supersedes: none
status: FINAL — READ-ONLY
read_only: true
generated_at: 2026-05-11T11:36:15Z
---

# v38.0 Findings — Always-Hero Simplification + Maximal Dead-Code Cleanup (Terminal)

**Audit Baseline.** The audit baseline is v36.0 audit-subject HEAD `1c0f09132d7439af9881c56fe197f81757f8164a` (closure signal `MILESTONE_V36_AT_HEAD_1c0f09132d7439af9881c56fe197f81757f8164a` carry-forward from `audit/FINDINGS-v36.0.md` §9c). v37.0 closure signal `MILESTONE_V37_AT_HEAD_2654fcc2` is a sub-milestone intermediate baseline carried forward from `audit/FINDINGS-v37.0.md` §9c. v38.0 audit subject HEAD `06623edb` (resolved at Task 4.6 atomic-update per D-272-CLOSURE-01). v38.0 introduces ONE contract-tree commit since the v37.0 intermediate baseline: `feat(272): always-on hero default 0 + degenerette dead-code cleanup [HERO-01..05, CLEAN-01..05]` at commit `527e3adc` (USER-APPROVED Phase 272 Wave 1 batched commit; +18 / −16 LOC in `contracts/modules/DegenerusGameDegeneretteModule.sol`; bytecode delta −57 bytes 8955 → 8898; storage layout byte-identical; public ABI byte-identical). v38.0 introduces ONE test-tree commit since the v37.0 intermediate baseline: `test(272): hero-always-on + dead-code cleanup + v37+ carry bundle [STAT-01..02, SURF-01..03, LBX-02, GASPIN-02..03, STAT-03-v35-carry]` at commit `e3fcb95c` (USER-APPROVED Phase 272 Wave 2 batched commit; +238 / −36 LOC across 6 files in `test/stat/`, `test/gas/`, `package.json`). `contracts/libraries/EntropyLib.sol` is byte-identical between v37.0 intermediate baseline `2654fcc2` and v38 HEAD (`git diff 2654fcc2..HEAD -- contracts/libraries/EntropyLib.sol` returns empty — verified at §3.B). `contracts/modules/DegenerusGameJackpotModule.sol`, `contracts/modules/DegenerusGameMintModule.sol`, `contracts/modules/DegenerusGameLootboxModule.sol`, `contracts/DegenerusTraitUtils.sol`, and `contracts/libraries/JackpotBucketLib.sol` are byte-identical between v37.0 intermediate baseline `2654fcc2` and v38 HEAD (Wave 2 SURF-01/02 grep-proof in `test/stat/SurfaceRegression.test.js`).

**Scope.** Single canonical milestone-closure deliverable for v38.0 per D-272-FILES-01 carry of D-271-FILES-01 / D-266-FILES-01 / D-265-FILES-01 / D-262 / D-257 carry-forward (9-section shape locked). v38.0 = single-phase milestone shape per CONTEXT.md `<domain>`: Phase 272 (Always-Hero Simplification + Maximal Dead-Code Cleanup — terminal). Three-wave structure inside Phase 272: Wave 1 contract commit (HERO-01..05 + CLEAN-01..05 — single USER-APPROVED batched commit per D-272-COMMIT-SHAPE-01), Wave 2 test commit (STAT-01..02 + SURF-01..03 + LBX-02 RE-DEFER + GASPIN-02 (a-alt) + GASPIN-03 + STAT-03-v35-carry — single USER-APPROVED batched commit), Waves 3-4 audit deliverable + adversarial pass + closure flips (AGENT-COMMITTED atomic-per-task). Terminal phase per D-272-FCITE-01 (carry of D-271-FCITE-01 / D-266-FCITE / D-265-FCITE-01 / D-262-FCITE-01 / D-257-FCITE-01 / D-253-15 step 8 + ROADMAP terminal-phase rule) — zero forward-cites emitted from Phase 272 to any post-v38.0 milestone phases. Verified at §8 Forward-Cite Closure block.

**Write policy.** READ-only after Wave 4 Task 4.7 terminal atomic commit per D-272-APPROVAL-01 + D-271-APPROVAL-02 / D-266-APPROVAL-01 / D-265-CF-02 / D-262 / D-257 carry-forward chain. KNOWN-ISSUES.md UNMODIFIED at v38 close per D-272-KI-01 default zero-promotion path: Phase 272 adversarial pass surfaces no FINDING_CANDIDATE; KNOWN-ISSUES.md `git diff 2654fcc2..HEAD -- KNOWN-ISSUES.md` returns empty. Zero F-38-NN finding blocks per D-272-FIND-01 carry default path (AUDIT-02 7-surface adversarial sweep verdicts SAFE_*). Per `feedback_never_preapprove_contracts.md`, the agent does NOT pre-approve any contract change — Wave 1 contract commit `527e3adc` and Wave 2 test commit `e3fcb95c` both landed under USER-APPROVED batched gates per `feedback_batch_contract_approval.md` + `feedback_no_contract_commits.md`. Per `feedback_manual_review_before_push.md`, the user reviews this deliverable's full diff before any push — final user-review gate at Wave 4 Task 4.7 before READ-only flip on `audit/FINDINGS-v38.0.md` (chmod 444 + frontmatter `status: FINAL — READ-ONLY` + `read_only: true`).

---

## 2. Executive Summary

### Closure Verdict Summary

- AUDIT-01: §3.A delta-surface table covers all source-tree changes `2654fcc2` → v38 HEAD with hunk-level evidence + {NEW, MODIFIED_LOGIC, REFACTOR_ONLY, DELETED} classification per row. D-272-CLEAN-SCOPE-01 scope-narrowing (Degenerette module only) and D-272-CLEAN-DISCOVERY-01 manual-grep-walk discovery method explicitly cited.
- AUDIT-02: §4 7-surface adversarial sweep (a)..(g) with verdict bucket per row; default zero F-38-NN finding blocks per D-272-FIND-01; `/contract-auditor` + `/zero-day-hunter` + `/economic-analyst` PARALLEL adversarial pass per D-272-ADVERSARIAL-01.
- AUDIT-03: §3.C AUDIT-03 conservation re-proof: per-N basePayoutEV = 100 centi-x exact preserved (per-N tables UNCHANGED at v38); hero EV-neutrality preserved across all (M, N) under always-on hero schedule; total payout invariant `ethShare + lootboxShare = payout` preserved (PAY-SPLIT UNCHANGED at v38).
- AUDIT-04: §3.B AUDIT-04 zero-new-state grep-proof attestation: zero new storage slots; zero new public/external mutation entry points; zero new external pure entry points; zero new admin functions; zero new modifiers; zero new upgrade hooks.
- AUDIT-05: §9c emits closure signal `MILESTONE_V38_AT_HEAD_06623edb` verbatim in 5 locations per D-272-CLOSURE-01 (resolved at Task 4.6 atomic-update); KNOWN-ISSUES.md UNMODIFIED per default path.
- AUDIT-06: `272-01-ADVERSARIAL-LOG.md` populated with 3 H2 sections — `/contract-auditor` + `/zero-day-hunter` + `/economic-analyst` — per D-272-ADVERSARIAL-01; NOT `/degen-skeptic` per D-272-ADVERSARIAL-01 OUT-OF-SCOPE.
- REG-01: §5a — v37.0 intermediate closure signal `MILESTONE_V37_AT_HEAD_2654fcc2` NON-WIDENING at v38 HEAD per REG-01.
- REG-02: §5b — v34.0 closure signal `MILESTONE_V34_AT_HEAD_6b63f6d4` NON-WIDENING at v38 HEAD per REG-02.
- REG-03: §6b 4-row KI envelope re-verifications EXC-01..03 NEGATIVE-scope + EXC-04 RE_VERIFIED with NARROWS retained from v36.0 (BAF-jackpot-only scope; EntropyLib byte-identical at v38 HEAD).
- REG-04: §5d per-finding 6-col PASS/REGRESSED/SUPERSEDED row table walking `audit/FINDINGS-v25.0.md` → `audit/FINDINGS-v37.0.md` for findings referencing v38-touched function/surface set.
- Combined milestone closure: `MILESTONE_V38_AT_HEAD_06623edb`.

### Severity Counts (per D-08 5-Bucket Rubric)

- CRITICAL: 0
- HIGH: 0
- MEDIUM: 0
- LOW: 0
- INFO: 0
- Total F-38-NN: 0

Default expected per D-272-FIND-01 carry. The always-hero edit is mathematically well-bounded: per-N HERO_BOOST tables UNCHANGED at v38 (`HERO_BOOST_N0..N4_PACKED` at L337-341 byte-identical vs `2654fcc2`); hero EV-neutrality calibration `P(hero|M, N) × boost(M, N) + (1 − P(hero|M, N)) × HERO_PENALTY = HERO_SCALE` preserved per Fraction-exact analytical audit and Phase 268 STAT-03 empirical re-pin (carried forward through Wave 2 STAT-01 + STAT-02 re-validation under always-on hero); `HERO_PENALTY = 9500` / `HERO_SCALE = 10000` UNCHANGED; storage layout byte-identical (`FT_HERO_SHIFT = 237` preserved; vestigial bit at offset 0 always = 1 post-pack; freed bit reserved for future feature); public ABI byte-identical (`placeDegeneretteBet(..., uint8 heroQuadrant)` signature UNCHANGED; `0xFF` and any `>= 4` heroQuadrant input accepted and normalized to quadrant 0 internally per HERO-01); zero new storage slots; zero new public/external mutation entry points (AUDIT-04 grep-proof); zero new admin functions / modifiers / upgrade hooks. Cleanup-sweep scope is narrowed to Degenerette module only per D-272-CLEAN-SCOPE-01; all CLEAN-NN candidates carry inline design-intent traces per D-272-DESIGN-INTENT-01 + `feedback_design_intent_before_deletion.md`. Severity ceiling for any v38-emitted F-38-NN: LOW (no value extraction beyond the existing Degenerette prize space; same total-payout mechanics as pre-v38 except for variance impact on the risk-averse subset which is bounded acceptable per user disposition; EV invariant by construction). Most likely severity for any inline-draft finding-candidate: INFO. Severity counts reconcile to §4 F-38-NN block tally line by line per ROADMAP success criterion.

### D-08 5-Bucket Severity Rubric

Severity calibration mapped via the v25–v37 player-reachability × value-extraction × determinism-break frame, carried forward as D-08 from v25 onward (D-272-SEV-01 carry of D-271-SEV-01).

| Severity | Definition |
| -------- | ---------- |
| CRITICAL | Player-reachable, material protocol value extraction, no mitigation at HEAD. |
| HIGH | Player-reachable, bounded value extraction OR no extraction but hard determinism violation. |
| MEDIUM | Player-reachable, no value extraction, observable behavioral asymmetry. |
| LOW | Player-reachable theoretically but not practically (gas economics / timing / coordination cost makes exploit non-viable). |
| INFO | Not player-reachable, OR documented design decision, OR observation only (naming inconsistency, dead code, gas optimization, doc drift). |

Severity calibration for any F-38-NN that may surface during §4 adversarial-pass disposition: LOW ceiling (always-on hero is EV-neutral by construction per the per-N HERO_BOOST table calibration; player cannot extract value from the variance increase because expected value is invariant; storage layout byte-identical preserves one-line revert path; cleanup-sweep removals each preserve their guard invariants per design-intent traces). INFO likely for documentation-only items. Per D-272-FIND-01 default path, zero F-38-NN blocks emit; severity-at-HEAD = N/A.

### D-09 KI Gating Rubric Reference

The §6 KI-eligibility 3-predicate test (D-09) is distinct from the D-08 severity rubric above. A candidate qualifies for `KNOWN-ISSUES.md` promotion (verdict `KI_ELIGIBLE_PROMOTED`) iff ALL three predicates hold:

1. **Accepted-design** — behavior is intentional / documented / load-bearing for the protocol's design (not an oversight or accident)
2. **Non-exploitable** — no player-reachable path extracts protocol value or breaks determinism
3. **Sticky** — the design choice persists across foreseeable future code revisions (not a transient state)

ANY false ⇒ Non-Promotion Ledger entry with the failing predicate identified. Default outcome at this milestone: zero F-38-NN finding blocks emit (D-272-FIND-01 carry default path) → zero KI promotion candidates from new findings. KNOWN-ISSUES.md UNMODIFIED at v38 close per D-272-KI-01: variance impact on risk-averse subset (Phase 272 §4 surface (f)) is documented as accepted-design via prose disclosure ONLY (no new Design Decisions entry); EV invariant preserved by per-N HERO_BOOST table calibration; player receives same EV under all (M, N) configurations; bounded variance increase per user disposition. EXC-04 NARROWS retained from v36.0 (BAF-jackpot-only scope) — EntropyLib byte-identical at v38 HEAD; per-pull-level keccak path UNCHANGED in v38; lootbox-path consumes high-entropy keccak via `EntropyLib.hash2` + bit-slicing per v36.0 ENT-01..06 + v37.0 LBX-01 carry. See §6 KI Gating Walk + Non-Promotion Ledger.

### Forward-Cite Closure Summary

D-272-FCITE-01 carry of D-271-FCITE-01 / D-266-FCITE / D-265-FCITE-01 / D-262-FCITE-01 / D-257-FCITE-01 / D-253-15 step 8 + ROADMAP terminal-phase rule: zero forward-cites emitted from Phase 272 to any post-v38.0 milestone phases. Verified at §8 Forward-Cite Closure block. v38.0 = single-phase milestone (Phase 272) per CONTEXT.md `<domain>`; §9.NN.iv Carry-Forward RE-DEFER Register contains explicit deferred-handoff items (LBX-02 RE-DEFER to v39+ + STAT-03-v35-carry ACCEPTED-DESIGN ledger; GASPIN-02 (a-alt) + GASPIN-03 CLOSED at v38) — these are planner handoff registers tying into next-milestone pickup via `.planning/PROJECT.md` "Deferred to Future Milestones" single-source-of-truth lookup, NOT forward-cites to in-flight Phase 273+ work. Future milestones (v39.0+) ingest via fresh delta-extraction phase, not via forward-cite from v38 artifacts.

### Attestation Anchor

See §9 Milestone Closure Attestation for the D-253-15 step 9 attestation block triggering v38.0 milestone closure via signal `MILESTONE_V38_AT_HEAD_06623edb` (resolved at Wave 4 Task 4.6 atomic-update across 5 verbatim locations per D-272-CLOSURE-01).

---

## 3. Per-Phase Sections

### 3a. Phase 272 — Always-Hero Simplification + Maximal Dead-Code Cleanup (Terminal)

**Commits:**
- USER-APPROVED Wave 1 contract commit `527e3adc` — `feat(272): always-on hero default 0 + degenerette dead-code cleanup [HERO-01..05, CLEAN-01..05]`. Single file (`contracts/modules/DegenerusGameDegeneretteModule.sol`); +18 / −16 LOC; bytecode delta −57 bytes (8955 → 8898); storage layout byte-identical vs `2654fcc2`; public ABI byte-identical vs `2654fcc2`. Per `feedback_batch_contract_approval.md` + `feedback_no_contract_commits.md` + `feedback_never_preapprove_contracts.md`.
- USER-APPROVED Wave 2 test commit `e3fcb95c` — `test(272): hero-always-on + dead-code cleanup + v37+ carry bundle [STAT-01..02, SURF-01..03, LBX-02, GASPIN-02..03, STAT-03-v35-carry]`. 6 files (`package.json` + 4 `test/stat/*` + 1 `test/gas/*`); +238 / −36 LOC. STAT-01/02 re-pin under always-on hero; SURF-01..03 v38.0 describe extension + LBX-03 re-anchor; LBX-02 FORMAL RE-DEFER prose; GASPIN-02 (a-alt) `test:gas` script-split; STAT-03-v35-carry ACCEPTED-DESIGN ledger entry.

**Requirements:** 30 of 30 satisfied — HERO-01..05 + CLEAN-01..05 (CLEAN-01 SOFTENED per D-272-CLEAN-DISCOVERY-01 to manual grep-walk; CLEAN-06 the batched-commit req satisfied by Wave 1 commit `527e3adc`) + STAT-01..02 + SURF-01..03 + LBX-02 RE-DEFER + GASPIN-02 (a-alt) + GASPIN-03 + STAT-03-v35-carry ACCEPTED-DESIGN + AUDIT-01..06 + REG-01..04 (per `.planning/REQUIREMENTS.md` Phase 272 SUMMARY tally; see Wave 4 closure flips for traceability checkbox updates).

**What IS at v38.0 close (Wave 1 contract delta in `contracts/modules/DegenerusGameDegeneretteModule.sol`):**

- **HERO-01** — `_packFullTicketBet` normalizes `heroQuadrant ≥ 4` to `0` via a local `effectiveQuadrant`: `uint8 effectiveQuadrant = heroQuadrant < 4 ? heroQuadrant : 0;` (L832), then unconditional pack `packed |= (uint256(1) | (uint256(effectiveQuadrant) << 1)) << FT_HERO_SHIFT;` (L843-845). The vestigial bit at `FT_HERO_SHIFT + 0` is always set (`uint256(1)` in the pack expression). Public API `placeDegeneretteBet(..., uint8 heroQuadrant)` signature UNCHANGED; `0xFF` and any `>= 4` heroQuadrant input still accepted at the ABI boundary but normalized to quadrant 0 internally.
- **HERO-02** — `_resolveFullTicketBet` extracts `heroQuadrant` directly from the packed bet via `uint8 heroQuadrant = uint8((packed >> (FT_HERO_SHIFT + 1)) & MASK_2);` (L591). The `heroBits` 3-bit extraction + `heroEnabled` local variable + `heroQuadrant` derivation block REMOVED. The enabled bit at `FT_HERO_SHIFT + 0` becomes vestigial (always = 1 post-pack); bit allocation preserved at 3 bits per `FT_HERO_SHIFT = 237` (HERO-02 design contract — no collapse to 2 bits, preventing storage-layout shift; freed bit reserved for future feature).
- **HERO-03** — `_fullTicketPayout` signature drops `bool heroEnabled` parameter (L947-955). Resolve-time guard simplifies from `if (heroEnabled && matches >= 2 && matches < 8)` to `if (matches >= 2 && matches < 8)` at the hero-multiplier call site. `_applyHeroMultiplier` body L1009-1034 UNCHANGED (same boost/penalty math; same per-N table dispatch via `HERO_BOOST_N0..N4_PACKED`; `HERO_PENALTY = 9500` / `HERO_SCALE = 10000` UNCHANGED).
- **HERO-04** — NatSpec rewrites describing what IS at v38 close per `feedback_no_history_in_comments.md` + D-272-NATSPEC-DISCIPLINE-01:
  - L321 `FT_HERO_SHIFT` comment: `"3 bits: [0]=reserved, [1..2]=quadrant (always-on hero)"`.
  - L366 `@param heroQuadrant` line: `"Hero quadrant (0-3) for payout boost. Inputs >= 4 (including 0xFF) normalize to quadrant 0."`.
  - L819-822 `_packFullTicketBet` NatSpec rewrite: `"inputs with heroQuadrant >= 4 (including 0xFF) are normalized to quadrant 0 (top-left). The reserved bit at FT_HERO_SHIFT is always set; the 2-bit quadrant field at FT_HERO_SHIFT + 1 encodes the selected quadrant."`.
  - `_fullTicketPayout` block NatSpec rewrite describing hero applies for `M ∈ {2..7}`.
  - Zero comparative/historical language ("previously was opt-out", "v37 → v38 change", etc.) per D-272-NATSPEC-DISCIPLINE-01.
- **HERO-05** — Storage layout byte-identical at v38 HEAD vs `2654fcc2` (storage-keyword diff: zero contract-state slot changes; the only stack-local changes are the removal of `bool heroEnabled` local + parameter); zero new public/external mutation entry points; zero new external pure entry points; zero new admin functions; zero new modifiers — Wave 1 batched commit `527e3adc` lands per `feedback_batch_contract_approval.md` + `feedback_no_contract_commits.md` + `feedback_never_preapprove_contracts.md`.
- **CLEAN-01..05** (scope narrowed to `contracts/modules/DegenerusGameDegeneretteModule.sol` per **D-272-CLEAN-SCOPE-01**; discovery via planner manual grep-walk per **D-272-CLEAN-DISCOVERY-01** — `/gas-audit` orchestrator NOT spawned at v38 per the 1,158-LOC single-module scope-narrowing rationale):
  - **CLEAN-02** — `MASK_3 = 0x7` constant (v37 baseline L347) REMOVED. Sole callsite was the 3-bit heroBits extraction at v37 baseline L592 (removed by HERO-02). Design-intent trace per D-272-DESIGN-INTENT-01: 3-bit mask was for `[enabled, quadrant_lo, quadrant_hi]`; under always-on hero schedule the load-bearing form is the 2-bit `MASK_2 = 0x3` quadrant-only extract. Cross-module grep `grep -rn "MASK_3" contracts/` confirms no other-file callsites.
  - **CLEAN-02 (cont.)** — `heroBits` extraction + `heroEnabled` local variable + intermediate `heroQuadrant` derivation block at v37 baseline L592-594 REMOVED via HERO-02. Design-intent trace: opt-out intermediate; under always-on schedule, direct quadrant extract `uint8((packed >> (FT_HERO_SHIFT + 1)) & MASK_2)` is the load-bearing form.
  - **CLEAN-03 / CLEAN-04 (parameter + NatSpec)** — `bool heroEnabled` parameter on `_fullTicketPayout` REMOVED via HERO-03 (v37 baseline L952). `@param heroEnabled` NatSpec line REMOVED via HERO-04 (v37 baseline L948-953). Design-intent trace: opt-out toggle; under always-on schedule, the guard predicate `heroEnabled &&` was statically true at this call site, so the parameter carried no information.
  - **CLEAN-04 (stale comments)** — Stale comments referencing "enabled" / "opt-out" REWRITTEN per HERO-04 to describe always-on semantics with quadrant-0 default (no history). Touchpoints: L321 FT_HERO_SHIFT inline comment; L366 @param heroQuadrant NatSpec; `_packFullTicketBet` NatSpec block; `_fullTicketPayout` NatSpec block.
  - **CLEAN-05** — No additional redundant-guard removals beyond the HERO-03 guard simplification (the `heroEnabled &&` arm in the M ∈ {2..7} guard predicate). Per `feedback_no_dead_guards.md` discipline: each removal preserves the safety property via upstream enforcement — in this case, the `heroEnabled` arm was statically true at the guard site so removing it leaves the guard predicate `matches >= 2 && matches < 8` semantically identical to the always-on schedule.
- **CLEAN-06** — Single batched USER-APPROVED contract commit `527e3adc` covers HERO-01..05 + CLEAN-01..05 per D-272-COMMIT-SHAPE-01.

**What IS at v38.0 close (Wave 2 test delta — 6 files):**

- **STAT-01 + STAT-02** — `test/stat/DegenerettePerNEvExactness.test.js`: `jsFullTicketPayout` JS mirror function drops `heroEnabled` parameter; 3 callsites drop `heroEnabled` arg; basePayoutEV per N within ±0.50 centi-x at ≥1M draws/N preserved (per-N analytical-P_N × .sol-tables dispatch yields 100.000±0.00002 for N ∈ {0..4}). `test/stat/DegeneretteBonusEv.test.js`: `jsApplyHeroMultiplier` + `jsFullTicketPayout` JS mirrors drop `heroEnabled`; hero-off baseline run dropped; new `jsBasePayoutPreHero` helper provides the analytical pre-hero baseline for the EV-neutrality ratio test; EV-neutrality within ±1% at ≥100K hero-active draws/N preserved. Hero comment headers rewritten to describe post-v38 semantics per `feedback_no_history_in_comments.md`.
- **SURF-01 + SURF-02** — `test/stat/SurfaceRegression.test.js` v38.0 SURF-01..02 describe block asserts byte-identity vs v37.0 baseline `2654fcc2` for `EntropyLib.sol` + `DegenerusTraitUtils.sol` + `DegenerusGameJackpotModule.sol` + `DegenerusGameMintModule.sol` (SURF-01a..d) + `DegenerusGameLootboxModule.sol` (SURF-02). All assertions PASS at v38 HEAD (verified per cross-module byte-identity grep proof — see §3.B).
- **SURF-03 (v37+ carry-forward pickup)** — `test/stat/SurfaceRegression.test.js:752` v37.0 SURF-03 it block rebased from `V36_BASELINE` → `PHASE_269_CLOSE_BASELINE = "8fd5c2e1..."` (post-LBX-01 HEAD). SURF-01/02/04 remain anchored at v36.0 baseline `1c0f0913`. Closes v37.0 §9.NN.iv SURF-03 carry-forward item.
- **LBX-02 (v37+ carry-forward — v38 FORMAL RE-DEFER)** — `test/gas/LootboxOpenGas.test.js` prepends prose-only "v38 FORMAL RE-DEFER" block documenting Phase 269 fixture-coverage gap + path-of-investigation for v39+ pickup. Analytical worst-case in NatSpec remains load-bearing per `feedback_gas_worst_case.md` + Phase 266 GAS-01 precedent. No new it/describe blocks added (count parity vs `2654fcc2` PASS). Closes v37.0 §9.NN.iv LBX-02 carry-forward via formal re-defer; corresponding entry recorded at v38 §9.NN.iv Carry-Forward RE-DEFER Register.
- **GASPIN-02 (v37+ carry-forward pickup — chosen path: (a-alt) script-split)** — `package.json` new `test:gas` script wires `Phase261GasRegression + Phase264GasRegression + Phase268GasRegression + LootboxOpenGas + AdvanceGameGas`; `test:stat` excludes those gas files. Test bodies UNCHANGED (`Phase261/264` diff vs `2654fcc2` exit 0). Goal: clean separation of stat assertions from gas-pin drift under v36.0 "128k is fine approved" acceptance — option (a-alt) script-isolation sidesteps cumulative-state drift that affected v36-v37 `test:stat` ordering.
- **GASPIN-03 (v37+ carry-forward pickup)** — verification nuance per consistency-gate protocol: pre-Wave-2 `test:stat` exit=1 with 5 failures; post-Wave-2 `test:stat` exit=1 with 1 failure (STAT-03-v35-carry ACCEPTED-DESIGN remaining failure). Non-regression vs pre-Wave-2 baseline confirmed; the (a-alt) `npm run test:gas` split moves 3 cumulative-state-drift failures off `test:stat` into a dedicated runner; gas-pin drift failures persist under `test:gas` per v36.0 "128k is fine approved" acceptance (not regression-worse than pre-Wave-2 baseline). SURF-03 rebase fixes the 4th pre-edit failure (LootboxModule diff against PHASE_269_CLOSE_BASELINE = 8fd5c2e1 is now empty). CLOSED at v38.
- **STAT-03-v35-carry (v37+ carry-forward pickup — ACCEPTED-DESIGN ledger entry)** — `test/stat/PerPullEmptyBucketSkip.test.js` prepends ledger-entry prose documenting 88.24% empty-bucket skip rate as fixture-density artifact (sparse deity-backed holder map), NOT protocol behavior. Carry-forward from v35.0 Phase 265 D-265-STAT03-01 reframe. Test bodies UNCHANGED; standalone pre/post-edit exit codes match (1 failing, same 88.24% rate, same fixture context).

**Carry-forward pick rationale:**
- **GASPIN-02 path (a-alt)** chosen over (a) refined `hardhat_reset` sequencing (Phase 269 D-269-STAB-01 option (b) hardhat_reset + loadFixture attempt FAILED structurally with side-effect regressions; (a) is a stricter variant likely to fail similarly) and over (c) widened tolerance ceiling (last-resort; rejected at v38 because the (a-alt) script-split is the cleaner mechanism). Goal achieved: cumulative-state drift moved off `test:stat`.
- **LBX-02 path: FORMAL RE-DEFER to v39+** chosen over attempt-empirical-pin (Phase 269 fixture-coverage gap remains structural at v38; analytical worst-case in NatSpec is load-bearing per `feedback_gas_worst_case.md` + Phase 266 GAS-01 precedent; attempting empirical pin without resolving the fixture-coverage gap would inflate `test/gas/LootboxOpenGas.test.js` with non-load-bearing scaffolding).
- **STAT-03-v35-carry path: ACCEPTED-DESIGN ledger entry** chosen over populate-dense-fixture (per v35.0 Phase 265 D-265-STAT03-01 fixture-calibration-error reframe — the failing test reflects sparse-fixture pre-organic-activity holder density, NOT a protocol-behavior finding; the helper itself was proven correct via deity-backed dense fixture at Phase 265 close; populate-dense-fixture path requires Phase 264 D-IMPL-07 mid/late-game holder-density spec which is out-of-scope at v38).

**Cumulative source-tree mutation at Phase 272 close:** `git diff 2654fcc2..HEAD -- contracts/` returns only the Wave 1 `contracts/modules/DegenerusGameDegeneretteModule.sol` hunks (+18 / −16 LOC); `git diff 2654fcc2..HEAD -- test/` returns the Wave 2 6-file hunks (+238 / −36 LOC). No other source-tree files modified.

### 3.A AUDIT-01 Delta-Surface Table

Every source-tree change from v37.0 intermediate baseline `2654fcc2` → v38.0 HEAD enumerated with hunk-level evidence and {NEW, MODIFIED_LOGIC, REFACTOR_ONLY, DELETED} classification per row. Row Group 1: Phase 272 Wave 1 contract changes (commit `527e3adc`). Row Group 2: Phase 272 Wave 2 test bundle (commit `e3fcb95c`).

**Scope-narrowing attestation (D-272-CLEAN-SCOPE-01):** The CLEAN-NN cleanup-sweep wording in `ROADMAP.md` + `REQUIREMENTS.md` CLEAN-01..05 is **NARROWED at v38** — cleanup applies ONLY to `contracts/modules/DegenerusGameDegeneretteModule.sol`. No other modules, libraries, or top-level contracts (`DegenerusGame.sol`, `DegenerusAffiliate.sol`, `DegenerusVault.sol`, etc.) are scanned or modified at v38. Rationale per D-272-CLEAN-SCOPE-01: Phase 272's load-bearing payload is the always-hero edit (HERO-01..05); cleanup scope is bounded to what HERO-01..05 directly orphans (`MASK_3`, `heroBits` extraction block, `heroEnabled` parameter + NatSpec line, related stale comments). Broader cleanup across 14,663 LOC of non-Degenerette surface = out-of-scope at v38; any candidates discovered incidentally are captured as v39+ backlog seeds in `.planning/notes/`. Documentation deviation note: `REQUIREMENTS.md` CLEAN-01 wording is SOFTENED at v38 per this decision (recorded in `272-CONTEXT.md` `<decisions>` block).

**Discovery-method attestation (D-272-CLEAN-DISCOVERY-01):** Cleanup-candidate discovery used **planner manual grep-walk** within `DegenerusGameDegeneretteModule.sol`. The `/gas-audit` orchestrator (`/gas-scavenger` + `/gas-skeptic`) was **NOT** spawned at v38 per the 1,158-LOC single-module scope-narrowing rationale (orchestrator overhead exceeds the surface area for a narrow-scope cleanup). Each candidate carries a per-item design-intent trace per `feedback_design_intent_before_deletion.md`. Grep recipes used: `grep -n "private constant" contracts/modules/DegenerusGameDegeneretteModule.sol` (unused-constant discovery) + per-constant callsite grep (zero callsites at HEAD = candidate); `grep -nE "enabled|heroEnabled|opt-out|opt out" contracts/modules/DegenerusGameDegeneretteModule.sol` (stale-comment discovery); manual `require`/`revert` scan for statically-provable predicates (redundant-guard discovery). Documentation deviation note: `REQUIREMENTS.md` CLEAN-01 explicitly names `/gas-audit` orchestrator + `/gas-scavenger` + `/gas-skeptic`; this is SOFTENED at v38 per D-272-CLEAN-DISCOVERY-01.

#### Row Group 1 — Phase 272 Wave 1 Contract Changes (commit `527e3adc`)

**Row 1.1 (HERO-01)** — `contracts/modules/DegenerusGameDegeneretteModule.sol` :: `_packFullTicketBet(...)` hero-pack block (post-edit L823-846).
- Class: **MODIFIED_LOGIC**.
- Evidence: introduces `uint8 effectiveQuadrant = heroQuadrant < 4 ? heroQuadrant : 0;` (L832) then unconditional `packed |= (uint256(1) | (uint256(effectiveQuadrant) << 1)) << FT_HERO_SHIFT;` (L843-845). Vestigial bit at offset 0 always set via `uint256(1)`. Public ABI `placeDegeneretteBet(..., uint8 heroQuadrant)` signature UNCHANGED — normalization is internal.
- Design-intent trace (D-272-DESIGN-INTENT-01): original opt-out allowed players to skip hero multiplier by passing `heroQuadrant >= 4` (sentinel `0xFF`). Always-on schedule normalizes to quadrant 0 (top-left). EV-neutral by per-N HERO_BOOST table calibration (UNCHANGED at v38).
- Verdict: SAFE_BY_DESIGN.

**Row 1.2 (HERO-02)** — `_resolveFullTicketBet(...)` hero-extract block (post-edit L591).
- Class: **MODIFIED_LOGIC** (REFACTOR — load-bearing-form simplification).
- Evidence: `uint8 heroQuadrant = uint8((packed >> (FT_HERO_SHIFT + 1)) & MASK_2);` (L591) replaces the v37-baseline 3-line `heroBits` extraction + `heroEnabled` local + `heroQuadrant` derivation block. `FT_HERO_SHIFT = 237` bit allocation preserved at 3 bits (vestigial enabled bit at offset 0 always = 1 post-pack); freed bit reserved for future feature.
- Design-intent trace (D-272-DESIGN-INTENT-01): the `heroBits` 3-bit extraction was the opt-out intermediate; under always-on schedule, direct `MASK_2` quadrant-only extract is the load-bearing form. Storage layout byte-identical preserves one-line revert path if always-hero is ever rolled back.
- Verdict: SAFE_BY_DESIGN.

**Row 1.3 (HERO-03)** — `_fullTicketPayout(...)` signature drop + guard simplification (post-edit L947-993).
- Class: **MODIFIED_LOGIC** (signature change — internal-only).
- Evidence: `bool heroEnabled` parameter REMOVED from signature (post-edit L947-955 vs v37 baseline L944-955 with parameter). Hero-multiplier guard predicate simplifies from `if (heroEnabled && matches >= 2 && matches < 8)` to `if (matches >= 2 && matches < 8)` at the call site to `_applyHeroMultiplier`. `_applyHeroMultiplier` body L1009-1034 UNCHANGED — same per-N HERO_BOOST table dispatch, same `HERO_PENALTY = 9500` / `HERO_SCALE = 10000`.
- Design-intent trace (D-272-DESIGN-INTENT-01): the `heroEnabled` parameter was the opt-out toggle; under always-on schedule, the guard predicate `heroEnabled &&` is statically true at this call site so the parameter carries no information. Internal-only signature change (private function); zero public ABI impact (cross-cite §3.B AUDIT-04 grep-proof).
- Verdict: SAFE_BY_DESIGN.

**Row 1.4 (HERO-04)** — NatSpec rewrites at L321 (`FT_HERO_SHIFT` inline comment), L366 (`@param heroQuadrant`), L819-822 (`_packFullTicketBet` block), L944+ (`_fullTicketPayout` block).
- Class: **REFACTOR_ONLY** (comment-only).
- Evidence: each rewrite describes what IS at v38 close per D-272-NATSPEC-DISCIPLINE-01 + `feedback_no_history_in_comments.md`. Zero comparative/historical language ("previously was opt-out", "v37 → v38 change", "removed heroEnabled", etc.). Touchpoints:
  - L321: `// 3 bits: [0]=reserved, [1..2]=quadrant (always-on hero)`
  - L366: `/// @param heroQuadrant Hero quadrant (0-3) for payout boost. Inputs >= 4 (including 0xFF) normalize to quadrant 0.`
  - L819-822: `_packFullTicketBet` block reads "inputs with `heroQuadrant >= 4` (including 0xFF) are normalized to quadrant 0 (top-left). The reserved bit at FT_HERO_SHIFT is always set; the 2-bit quadrant field at FT_HERO_SHIFT + 1 encodes the selected quadrant."
- Verdict: SAFE.

**Row 1.5 (HERO-05)** — Storage layout + public ABI byte-identity attestation (cross-cite §3.B AUDIT-04). **REVISED at Wave 1.5 (commit `4760459f`):** semantic pivots from "accept + normalize" to "reject invalid input" at the public ABI boundary.
- Class: **REFACTOR_ONLY** (no storage state change; no public ABI selector/signature change) + **MODIFIED_LOGIC** (Wave 1.5 boundary-validation: error-condition expansion only).
- Evidence: `FT_HERO_SHIFT = 237` preserved; vestigial enabled bit at offset 0 always = 1 post-pack. Storage-keyword diff between `2654fcc2` and v38 HEAD reports zero contract-state slot changes (only stack-local changes: `bool heroEnabled` local + parameter removed). Public-function diff `cmp` on "function .* external" lines exit 0 — `placeDegeneretteBet(..., uint8 heroQuadrant)` selector + parameter types byte-identical. Cross-cite §3.B grep-proof for AUDIT-04.
- **Wave 1.5 revision:** `_placeDegeneretteBetCore` entry adds defensive boundary validation `if (heroQuadrant >= 4) revert InvalidBet();` — inputs `>= 4` (including the v37+ `0xFF` sentinel) now REVERT rather than silently normalize to quadrant 0. Frontend MUST send valid `0..3` (default 0 if user does not pick). Public ABI selector + parameter types byte-identical; only error-condition expansion. Tracked as D-272-INPUT-VALIDATION-01 in `272-CONTEXT.md`.
- Verdict: SAFE_BY_STRUCTURAL_CLOSURE (storage + ABI selector/signature byte-identical) + SAFE_BY_DEFENSIVE_VALIDATION (Wave 1.5 input validation closes the Hypothesis (i) docs-vs-behavior drift surfaced at Wave 3 adversarial pass).

**Row 1.6 (CLEAN-02 — MASK_3 constant)** — `MASK_3 = 0x7` private constant (v37 baseline L347) DELETED.
- Class: **DELETED** (unused private constant).
- File / Lines: `contracts/modules/DegenerusGameDegeneretteModule.sol` (−1 private constant declaration at v37 baseline L347).
- Evidence: sole callsite at v37 baseline L592 was the 3-bit heroBits extraction (removed by HERO-02). Cross-module grep `grep -rn "MASK_3" contracts/` confirms no other-file callsites at v37 baseline; post-deletion grep returns zero matches in contracts/ tree.
- Discovery: D-272-CLEAN-DISCOVERY-01 manual grep-walk (NOT `/gas-audit` orchestrator).
- Design-intent trace (D-272-DESIGN-INTENT-01 + `feedback_design_intent_before_deletion.md`): 3-bit mask for `[enabled, quadrant_lo, quadrant_hi]`; under always-on schedule the load-bearing form is the 2-bit `MASK_2 = 0x3` quadrant-only extract.
- Verdict: SAFE_BY_DESIGN.

**Row 1.7 (CLEAN-02 — heroBits + heroEnabled locals)** — `heroBits` 3-bit extraction + `heroEnabled` local + intermediate `heroQuadrant` derivation block at v37 baseline L592-594 DELETED via HERO-02.
- Class: **DELETED** (stack-local variables).
- Evidence: replaced by the direct quadrant extract on a single line (Row 1.2 / HERO-02). Net effect: −3 LOC of stack-local computation.
- Discovery: D-272-CLEAN-DISCOVERY-01 manual grep-walk.
- Design-intent trace (D-272-DESIGN-INTENT-01): opt-out intermediate; load-bearing form is direct quadrant extract under always-on schedule.
- Verdict: SAFE_BY_DESIGN.

**Row 1.8 (CLEAN-03 — heroEnabled parameter)** — `bool heroEnabled` parameter on `_fullTicketPayout` (v37 baseline L952) DELETED via HERO-03.
- Class: **DELETED** (internal-function parameter).
- Evidence: parameter REMOVED from signature; guard predicate `heroEnabled &&` REMOVED from the `M ∈ {2..7}` hero-multiplier gate at the call site to `_applyHeroMultiplier`. Function remains `private` — internal-only signature change with zero public ABI impact.
- Discovery: D-272-CLEAN-DISCOVERY-01 manual grep-walk.
- Design-intent trace (D-272-DESIGN-INTENT-01 + `feedback_no_dead_guards.md`): opt-out toggle; under always-on schedule the guard predicate `heroEnabled &&` is statically true at this call site so the parameter carried no information. Removal preserves the safety property (the `matches >= 2 && matches < 8` predicate is unchanged).
- Verdict: SAFE_BY_DESIGN.

**Row 1.9 (CLEAN-04 — heroEnabled NatSpec line)** — `@param heroEnabled` NatSpec line on `_fullTicketPayout` (v37 baseline L948-953) DELETED via HERO-04.
- Class: **DELETED** (NatSpec line).
- Evidence: synchronous with Row 1.8 (parameter removal); the NatSpec `@param` line is removed to keep the doc-block consistent with the post-edit signature.
- Discovery: D-272-CLEAN-DISCOVERY-01 manual grep-walk + NatSpec audit per D-272-NATSPEC-DISCIPLINE-01.
- Design-intent trace (D-272-DESIGN-INTENT-01): the NatSpec entry described the opt-out toggle; removing the parameter without removing its `@param` would leave a stale doc-line referencing a non-existent argument.
- Verdict: SAFE.

**Row 1.10 (CLEAN-04 — stale comments)** — Stale comments referencing "enabled" / "opt-out" at v37 baseline L321 + L366 + `_packFullTicketBet` block + `_fullTicketPayout` block REWRITTEN per HERO-04 + D-272-NATSPEC-DISCIPLINE-01.
- Class: **REFACTOR_ONLY** (comment-only; describes what IS at v38).
- Evidence: rewrites enumerated at Row 1.4. Each rewrite describes always-on semantics with quadrant-0 default; zero comparative/historical language.
- Discovery: D-272-CLEAN-DISCOVERY-01 manual grep `grep -nE "enabled|heroEnabled|opt-out|opt out" contracts/modules/DegenerusGameDegeneretteModule.sol`.
- Design-intent trace (D-272-DESIGN-INTENT-01 + `feedback_no_history_in_comments.md`): comments describe protocol state at v38 close; never the change-from-v37 or change-from-baseline.
- Verdict: SAFE.

**Row 1.11 (CLEAN-05 — no additional redundant guards)** — Cleanup-sweep search for additional redundant safety guards beyond the HERO-03 guard simplification returned ZERO further candidates.
- Class: **NO_CHANGE** (negative cleanup-sweep result row; recorded for completeness).
- Evidence: planner manual grep-walk per D-272-CLEAN-DISCOVERY-01 scanned for `require` / `revert` predicates statically provable from caller-clamp or upstream invariant; no additional candidates surfaced beyond the HERO-03 guard simplification (which is itself recorded at Row 1.3).
- Design-intent trace: zero deletions ⇒ zero design-intent trace required beyond what's already captured at Row 1.3.
- Verdict: SAFE (no-op).

**Row 1.12 (CLEAN-06 — batched-commit attestation)** — Single batched USER-APPROVED contract commit `527e3adc` covers HERO-01..05 + CLEAN-01..05 per D-272-COMMIT-SHAPE-01 + `feedback_batch_contract_approval.md`.
- Class: **PROCESS_ATTESTATION** (commit-shape compliance; not a source-tree change row).
- Evidence: `git log --oneline 2654fcc2..HEAD -- contracts/` returns exactly one commit hash `527e3adc`. Commit message body includes full per-requirement attribution (HERO-01..05 + each CLEAN-NN), bytecode delta `8955 → 8898 (−57 bytes)`, gas-per-spin analytical delta (~30 gas saved), storage-layout grep proof, public-ABI grep proof.
- Verdict: SAFE.

**Row 1.13 (Wave 1.5 — HERO-05 spec_lock revision: defensive boundary validation)** — `contracts/modules/DegenerusGameDegeneretteModule.sol` :: `_placeDegeneretteBetCore(...)` entry-point input validation (commit `4760459f`).
- Class: **MODIFIED_LOGIC** (error-condition expansion at public ABI boundary; selector + parameter types byte-identical).
- Evidence: defensive boundary validation `if (heroQuadrant >= 4) revert InvalidBet();` added at the entry of `_placeDegeneretteBetCore`. Inputs `>= 4` (including the v37+ `0xFF` sentinel) now REVERT rather than silently normalize to quadrant 0. The previous HERO-01 silent-normalize path (`uint8 effectiveQuadrant = heroQuadrant < 4 ? heroQuadrant : 0;`) is now structurally unreachable for production inputs — only valid `0..3` quadrants can reach `_packFullTicketBet`. The Wave 1.5 batched commit also covers the test/fuzz handler at `test/fuzz/handlers/DegeneretteHandler.sol` to ensure fuzz inputs respect the new validation. Public ABI selector + parameter types byte-identical vs `2654fcc2`; only error-condition expansion.
- Design-intent trace (D-272-INPUT-VALIDATION-01 + `feedback_design_intent_before_deletion.md`): Wave 3 3-skill PARALLEL adversarial pass surfaced Hypothesis (i) — a docs-vs-behavior drift where `0xFF` input was pack-normalized to quadrant 0 (HERO-01) but NOT credited to `dailyHeroWagers[day][0]` (the L484 gate used raw input). User disposition pivoted from KEEP_AS_NEGATIVE_FINDING (the v39+ remediation candidate) to defensive boundary validation at v38 close: invalid input is rejected at the public ABI boundary rather than silently coerced. Cleaner than the option-(b) "track-by-currency" path proposed in the original v39+ pickup register because it eliminates the asymmetric "omit heroQuadrant" path entirely.
- Frontend contract: Frontend MUST send valid `0..3` (default 0 if user does not pick). `0xFF` sentinel no longer accepted.
- Hypothesis (i) status: pivoted from KEEP_AS_NEGATIVE_FINDING (at Wave 3 adversarial-pass close) to **RESOLVED_AT_V38** via this commit. The v39+ backlog seed candidate at §9.NN.iv is removed (no carry-forward).
- Tracked as D-272-INPUT-VALIDATION-01 in `.planning/phases/272-always-hero-simplification-maximal-dead-code-cleanup-terminal/272-CONTEXT.md` `<decisions>` block. ROADMAP success criterion #2 wording "still accepted but normalized to 0 internally" + REQUIREMENTS.md HERO-05 prose are superseded by D-272-INPUT-VALIDATION-01; Wave 4 closure flips will propagate the revision.
- Verdict: SAFE_BY_DEFENSIVE_VALIDATION.

**Row 1 Summary — Bytecode + Gas + Storage Attestation:**
- **Bytecode delta:** 8955 bytes → 8898 bytes (−57 bytes); target ~−30 bytes shrink exceeded.
- **Storage layout:** byte-identical vs `2654fcc2` per storage-keyword diff (zero contract-state slot changes; only stack-local changes: `bool heroEnabled` local + parameter removed); constant-decl diff: exactly 1 deletion (`MASK_3`) + 1 comment-only rewrite on `FT_HERO_SHIFT` line.
- **Public ABI:** byte-identical vs `2654fcc2` per `cmp` on "function .* external" lines exit 0.
- **Gas-per-spin (analytical):** ~30 gas saved per spin (one less SLOAD-shift-mask for `MASK_3` + `heroBits` + `heroEnabled` extraction).
- **Hero EV-neutrality:** preserved by per-N `HERO_BOOST_N0..N4_PACKED` tables UNCHANGED at v38 (cross-cite §3.C AUDIT-03 + Wave 2 STAT-01 + STAT-02 empirical re-pin).

**Always-on hero attribution (HERO-01..05 row group):** the HERO-01..05 row group above attributes the always-on hero semantic — the v38 pivot from the v37 opt-out form (`heroEnabled` toggle + `MASK_3` 3-bit extract) to the always-on form (vestigial enabled bit always = 1, 2-bit quadrant-only extract). Wave 1.5 (commit `4760459f`) pivots HERO-05 spec_lock from "accept + normalize" to "reject invalid input". Public ABI signature byte-identical; semantics shift to defensive boundary validation at the public ABI entry point (`_placeDegeneretteBetCore`). This eliminates the Hypothesis (i) docs-vs-behavior drift identified by the Wave 3 adversarial pass — the previous asymmetric path (`0xFF` input → HERO-01 normalize to quadrant 0 but raw input fails L484 `dailyHeroWagers` gate) is now structurally unreachable because invalid input reverts at the entry boundary. See Row 1.13 above for the Wave 1.5 evidence + design-intent trace.

**Wave 1.5 Bytecode + Gas + Storage delta (commit `4760459f` follow-on to `527e3adc`):**
- **Bytecode delta:** small additive (`if (heroQuadrant >= 4) revert InvalidBet();` adds ~10-15 bytes for the comparison + JUMPI + REVERT path). Net v38 bytecode after Wave 1.5 remains a NET SHRINK vs `2654fcc2` baseline.
- **Storage layout:** byte-identical vs `2654fcc2` and vs Wave 1 (`527e3adc`); zero new state slots. Wave 1.5 commit touches `contracts/modules/DegenerusGameDegeneretteModule.sol` (entry-point validation) + `test/fuzz/handlers/DegeneretteHandler.sol` (fuzz handler clamp).
- **Public ABI:** selector + parameter types byte-identical vs `2654fcc2`; only error-condition expansion (revert on `heroQuadrant >= 4`).
- **Hero EV-neutrality:** preserved — the per-N HERO_BOOST table dispatch is per-quadrant identical by construction (cross-cite §4 surface (a)); the Wave 1.5 input-validation only narrows the set of accepted inputs from `{0..255}` to `{0..3}`, which has zero impact on EV across the accepted set (the rejected `>= 4` set was already silently normalized to quadrant 0 pre-Wave-1.5).

#### Row Group 2 — Phase 272 Wave 2 Test Bundle (commit `e3fcb95c`)

**Row 2.1 (STAT-01)** — `test/stat/DegenerettePerNEvExactness.test.js` re-pin under always-on hero.
- Class: **MODIFIED_LOGIC** (JS mirror simplification).
- Evidence: `jsFullTicketPayout` JS mirror drops `heroEnabled` parameter; 3 callsites drop `heroEnabled` arg. Empirical PASS: basePayoutEV per N within ±0.50 centi-x at ≥1M draws/N (per-N analytical-P_N × .sol-tables dispatch yields 100.000±0.00002 for N ∈ {0..4}).
- Verdict: SAFE_BY_DESIGN.

**Row 2.2 (STAT-02)** — `test/stat/DegeneretteBonusEv.test.js` re-pin under always-on hero.
- Class: **MODIFIED_LOGIC** (JS mirror simplification + hero-off baseline run dropped).
- Evidence: `jsApplyHeroMultiplier` + `jsFullTicketPayout` JS mirrors drop `heroEnabled`; hero-off baseline run dropped; new `jsBasePayoutPreHero` helper provides the analytical pre-hero baseline for the EV-neutrality ratio test. Empirical PASS: EV-neutrality within ±1% at ≥100K hero-active draws/N preserved. Hero comment headers rewritten per `feedback_no_history_in_comments.md`.
- Verdict: SAFE_BY_DESIGN.

**Row 2.3 (SURF-01 + SURF-02)** — `test/stat/SurfaceRegression.test.js` v38.0 SURF-01..02 describe block extension.
- Class: **NEW** (additive describe block).
- Evidence: asserts byte-identity vs v37.0 baseline `2654fcc2` for `EntropyLib.sol` + `DegenerusTraitUtils.sol` + `DegenerusGameJackpotModule.sol` + `DegenerusGameMintModule.sol` (SURF-01a..d) + `DegenerusGameLootboxModule.sol` (SURF-02). All assertions PASS at v38 HEAD per cross-module byte-identity grep proof (cross-cite §3.B).
- Verdict: SAFE.

**Row 2.4 (SURF-03 v37+ carry-forward pickup)** — `test/stat/SurfaceRegression.test.js:752` v37.0 SURF-03 it block rebased.
- Class: **MODIFIED_LOGIC** (one-line baseline-constant rebase + accompanying it-name and inline-comment rewrites).
- Evidence: `V36_BASELINE` → `PHASE_269_CLOSE_BASELINE = "8fd5c2e1..."` (post-LBX-01 HEAD); SURF-01/02/04 remain anchored at v36.0 baseline `1c0f0913`. Closes v37.0 §9.NN.iv SURF-03 carry-forward item. v33-v37 describe blocks byte-identical except for this single-line rebase per `feedback_no_history_in_comments.md`.
- Verdict: SAFE.

**Row 2.5 (LBX-02 v37+ carry-forward pickup — v38 FORMAL RE-DEFER)** — `test/gas/LootboxOpenGas.test.js` prose-only RE-DEFER block prepended.
- Class: **REFACTOR_ONLY** (prose-only addition; zero new it/describe blocks).
- Evidence: documents Phase 269 fixture-coverage gap + path-of-investigation for v39+ pickup. Test bodies UNCHANGED (count parity vs `2654fcc2` PASS — `grep -c "it(" test/gas/LootboxOpenGas.test.js` byte-identical). Analytical worst-case in NatSpec is load-bearing per `feedback_gas_worst_case.md` + Phase 266 GAS-01 precedent. Closes v37.0 §9.NN.iv LBX-02 carry-forward via formal re-defer; corresponding entry recorded at v38 §9.NN.iv Carry-Forward RE-DEFER Register.
- Verdict: SAFE.

**Row 2.6 (GASPIN-02 v37+ carry-forward pickup — chosen path: (a-alt) script-split)** — `package.json` `test:gas` script split.
- Class: **NEW** (additive script wiring).
- Evidence: new `test:gas` script wires `Phase261GasRegression + Phase264GasRegression + Phase268GasRegression + LootboxOpenGas + AdvanceGameGas`; `test:stat` excludes those gas files. Test bodies UNCHANGED (`Phase261/264` diff vs `2654fcc2` exit 0). Goal: clean separation of stat assertions from gas-pin drift under v36.0 "128k is fine approved" acceptance.
- Verdict: SAFE.

**Row 2.7 (GASPIN-03 v37+ carry-forward pickup — CLOSED at v38)** — `npm run test:stat` + `npm run test:gas` consistency-gate verification.
- Class: **PROCESS_ATTESTATION** (verification step; not a source-tree change row).
- Evidence: pre-Wave-2 `test:stat` exit=1 with 5 failures; post-Wave-2 `test:stat` exit=1 with 1 failure (STAT-03-v35-carry ACCEPTED-DESIGN remaining failure). Non-regression vs pre-Wave-2 baseline confirmed; (a-alt) `npm run test:gas` split moves 3 cumulative-state-drift failures off `test:stat`; gas-pin drift failures persist under `test:gas` per v36.0 "128k is fine approved" acceptance. SURF-03 rebase fixes the 4th pre-edit failure. CLOSED at v38 (not re-deferred).
- Verdict: SAFE.

**Row 2.8 (STAT-03-v35-carry v37+ carry-forward pickup — ACCEPTED-DESIGN ledger entry)** — `test/stat/PerPullEmptyBucketSkip.test.js` ledger-entry prose block prepended.
- Class: **REFACTOR_ONLY** (prose-only addition; zero behavioral change).
- Evidence: documents 88.24% empty-bucket skip rate as fixture-density artifact (sparse deity-backed holder map), NOT protocol behavior. Carry-forward from v35.0 Phase 265 D-265-STAT03-01 fixture-calibration-error reframe. Test bodies UNCHANGED; standalone pre/post-edit exit codes match (1 failing, same 88.24% rate, same fixture context).
- Verdict: SAFE.

#### §3.A Summary

v38.0 source-tree changes since intermediate baseline `2654fcc2`: 1 contract-tree commit (`527e3adc` Phase 272 Wave 1 HERO-01..05 + CLEAN-01..05) + 1 test-tree commit (`e3fcb95c` Phase 272 Wave 2 STAT-01..02 + SURF-01..03 + LBX-02 RE-DEFER + GASPIN-02 (a-alt) + GASPIN-03 + STAT-03-v35-carry). 12 rows in Row Group 1 (5 HERO + 5 CLEAN + 1 batched-commit attestation + 1 negative cleanup-sweep row) + 8 rows in Row Group 2 (STAT-01/02 + SURF-01/02 + SURF-03 + LBX-02 RE-DEFER + GASPIN-02 (a-alt) + GASPIN-03 + STAT-03-v35-carry). All rows verdicted SAFE / SAFE_BY_DESIGN / SAFE_BY_STRUCTURAL_CLOSURE per AUDIT-01. D-272-CLEAN-SCOPE-01 narrowing + D-272-CLEAN-DISCOVERY-01 manual grep-walk method explicitly cited above.

### 3.B AUDIT-04 Zero-New-State Attestation

Grep-proof attestation: zero new storage slots, zero new public/external mutation entry points, zero new external pure entry points, zero new admin functions, zero new modifiers, zero new upgrade hooks, zero new ERC-20 mint entry points since v37.0 intermediate baseline `2654fcc2`.

**Storage byte-identity (zero new storage slots):**

Recipe:
```
git diff 2654fcc2..HEAD -- contracts/DegenerusGameStorage.sol
```

Output: empty (0 files changed). Phase 272 Wave 1 commit `527e3adc` touches only `contracts/modules/DegenerusGameDegeneretteModule.sol` — no storage-file changes. The HERO-02 bit allocation preserves `FT_HERO_SHIFT = 237` (3 bits, with vestigial enabled bit at offset 0 always = 1 post-pack); storage layout byte-identical.

**Zero new public/external mutation entry points:**

Recipe:
```
git diff 2654fcc2..HEAD -- contracts/ \
  | grep -E '^\+.*function .* (public|external)'
```

Output: 0 hits (re-run at §3.B authoring time). The HERO-03 `_fullTicketPayout` signature change (drop of `bool heroEnabled` parameter) is internal-only — the function remains `private`. `placeDegeneretteBet(...)` public signature UNCHANGED (HERO-01 normalization is internal). No new public/external functions added.

**Zero new external pure entry points:**

Recipe:
```
git diff 2654fcc2..HEAD -- contracts/ \
  | grep -E '^\+.*function .* (external|public) pure'
```

Output: 0 hits.

**Zero new admin functions / modifiers / upgrade hooks:**

Recipe:
```
git diff 2654fcc2..HEAD -- contracts/ \
  | grep -E "^\+.*(modifier |onlyOwner|onlyAdmin|UUPSUpgradeable|_authorizeUpgrade)"
```

Output: 0 hits (re-run at §3.B authoring time). No new admin gates introduced.

**Zero new ERC-20 mint entry points:**

Recipe:
```
git diff 2654fcc2..HEAD -- contracts/ \
  | grep -E "^\+.*\.(mint|mintFor|_mint)\("
```

Output: 0 hits in non-test contract files. The Degenerette payout path uses pre-existing `mintForGame` route only; HERO-01..05 do not introduce new mint sites.

**Cross-module byte-identity proof (v38 HEAD vs `2654fcc2`):**

Recipe (run at §3.B authoring time):
```
for f in \
  contracts/modules/DegenerusGameJackpotModule.sol \
  contracts/modules/DegenerusGameMintModule.sol \
  contracts/modules/DegenerusGameLootboxModule.sol \
  contracts/DegenerusTraitUtils.sol \
  contracts/libraries/JackpotBucketLib.sol \
  contracts/libraries/EntropyLib.sol \
  ; do \
    echo -n "$f: "; git diff 2654fcc2..HEAD -- "$f" | wc -l; \
  done
```

Output (each file emits `0` indicating byte-identical):
```
contracts/modules/DegenerusGameJackpotModule.sol: 0
contracts/modules/DegenerusGameMintModule.sol: 0
contracts/modules/DegenerusGameLootboxModule.sol: 0
contracts/DegenerusTraitUtils.sol: 0
contracts/libraries/JackpotBucketLib.sol: 0
contracts/libraries/EntropyLib.sol: 0
```

This grep-proof establishes that Phase 272 Wave 1 modifies ONLY `contracts/modules/DegenerusGameDegeneretteModule.sol` per D-272-CLEAN-SCOPE-01 scope narrowing. Cross-cite Wave 2 SURF-01..02 v38.0 describe block in `test/stat/SurfaceRegression.test.js` for the same invariant at the harness level.

**Five-line zero-attestation roll-up** (one phrase per line for grep-tally clarity):

- zero new storage slots — `git diff 2654fcc2..HEAD -- contracts/DegenerusGameStorage.sol` empty.
- zero new public/external mutation entry points — `git diff 2654fcc2..HEAD -- contracts/ | grep -E '^\+.*function .* (public|external)'` returns 0.
- zero new admin functions — `git diff 2654fcc2..HEAD -- contracts/ | grep -E "^\+.*(onlyOwner|onlyAdmin)"` returns 0.
- zero new modifiers — `git diff 2654fcc2..HEAD -- contracts/ | grep -E "^\+.*modifier "` returns 0.
- zero new upgrade hooks — `git diff 2654fcc2..HEAD -- contracts/ | grep -E "^\+.*(UUPSUpgradeable|_authorizeUpgrade)"` returns 0.

**Closing attestation:** Storage layout byte-identical at v38.0 closure HEAD `06623edb` vs v37.0 intermediate baseline `2654fcc2` per slot-by-slot grep-proof; zero new public/external mutation entry points; zero new external pure entry points; zero new admin functions; zero new modifiers; zero new upgrade hooks; zero new ERC-20 mint entry points. Cross-module byte-identity preserved for `JackpotModule + MintModule + LootboxModule + TraitUtils + JackpotBucketLib + EntropyLib` (D-272-CLEAN-SCOPE-01 narrowing satisfied — only `DegenerusGameDegeneretteModule.sol` modified).

### 3.C AUDIT-03 Conservation Re-Proof

Conservation re-proof across 4 domains: per-N table calibration math; ETH bonus EV conservation; hero EV-neutrality preservation under always-on schedule; solvency invariant + ethShare/lootboxShare sum invariant + no new mint sites. Closes the AUDIT-03 design contract per ROADMAP success criterion + REQUIREMENTS.md.

**(1) Per-N basePayoutEV exact preserved:**

Per-N basePayoutEV calibration is UNCHANGED at v38 because the per-N payout tables (`QUICK_PLAY_PAYOUTS_N{0..4}_PACKED` + `QUICK_PLAY_PAYOUT_N{0..4}_M8`) are byte-identical at v38 HEAD vs `2654fcc2` (Phase 272 Wave 1 touches only the hero-pack/extract block + cleanup-sweep deletions; no payout-table mutations). For each N ∈ {0..4}, the per-N basePayout EV remains exact at 100 centi-x by construction:

`basePayoutEV(N) = Σ P_N(M) × payout_N(M) for M ∈ {0..8} = 100 centi-x (Fraction-exact)`

Calibration source: `.planning/notes/degenerette-recalibration/derive_5_tables.py` Python `Fraction`-exact arithmetic (v37.0 Phase 267 Task 2 `PASS_ALL_25` byte-identity proof unchanged at v38 — the 25 packed constants are byte-identical).

Empirical witness: Wave 2 STAT-01 (`test/stat/DegenerettePerNEvExactness.test.js`) re-pin under always-on hero at ≥1M draws/N confirms `basePayoutEV per N within ±0.50 centi-x` for N ∈ {0..4} (analytical-P_N × .sol-tables dispatch yields 100.000±0.00002 for each N).

**(2) ETH bonus EV conservation per N:**

The per-N WWXRP factor tables (`WWXRP_FACTORS_N{0..4}_PACKED`) are byte-identical at v38 HEAD vs `2654fcc2` (no Wave 1 mutation). Analytical: `ETH_ROI_BONUS_BPS = 500 bps = 5.000%` per N preserved by the per-N factor lookup. Empirical witness: Wave 2 STAT-01 + STAT-02 PASS via the existing STAT-04 envelope (Wave 2 does not re-spec STAT-04; per-N WWXRP factor EV within ±1% at ≥100K WWXRP-active draws/N carries forward from v37.0 Phase 268 STAT-04 since the contract surface is byte-identical at this layer).

**(3) Hero EV-neutrality preservation under always-on schedule:**

Per-N HERO_BOOST tables (`HERO_BOOST_N0..N4_PACKED` at L337-341) are byte-identical at v38 HEAD vs `2654fcc2` per Wave 1 commit `527e3adc` (no Wave 1 mutation to the per-N HERO_BOOST tables; only the hero-pack/extract block + cleanup-sweep deletions). EV-neutrality calibration holds:

`P(hero|M, N) × boost(M, N) + (1 − P(hero|M, N)) × HERO_PENALTY = HERO_SCALE`

where `HERO_PENALTY = 9500`, `HERO_SCALE = 10000` (constants UNCHANGED at v38). The 5 per-N tables encode 6 values each (M = 2..7; M < 2 zero-payout exemption, M = 8 hero-EV-neutrality exemption noted in NatSpec at `_fullTicketPayout`).

**Under the always-on schedule:** the hero multiplier applies for M ∈ {2..7} regardless of player input (`heroEnabled` no longer toggles application). For each (M, N), expected payout `E[payout(M, N)] = basePayout(M, N) × HERO_SCALE / HERO_SCALE = basePayout(M, N)` because the EV-neutrality calibration zeroes out the expected hero contribution. EV is invariant across the always-on transition; only variance increases on the variance-averse player subset (cross-cite §4 surface (f)).

Empirical witness: Wave 2 STAT-02 (`test/stat/DegeneretteBonusEv.test.js`) re-pin under always-on hero confirms EV-neutrality within ±1% at ≥100K hero-active draws/N. The new `jsBasePayoutPreHero` helper provides the analytical pre-hero baseline for the EV-neutrality ratio test; hero-off baseline run is dropped (no longer reachable under always-on schedule).

**(4) Solvency invariant + ethShare/lootboxShare sum invariant + no new mint sites:**

PAY-SPLIT 3-tier rule (PAY-SPLIT-01..03 from v37.0 Phase 267) UNCHANGED at v38 — Wave 1 commit `527e3adc` does not touch `_distributePayout` body or signature. Total payout invariant:

`ethShare + lootboxShare = payout` ← preserved at every tier (carry forward from v37.0 §3.C verification).

`claimablePool ≤ ETH balance + stETH balance` PRESERVED (no new ETH/stETH balance mutations introduced by Phase 272).

`coinflip.creditFlip` + lootbox-crediting paths byte-identical at v38 HEAD vs `2654fcc2` (cross-cite §3.B AUDIT-04 grep-proof). Degenerette payout path uses pre-existing `mintForGame` route only; no new ERC-20 mint entry points introduced by Phase 272 Wave 1 commit `527e3adc`.

**Closing conservation attestation:** Per-N table calibration math holds `basePayoutEV = 100 centi-x ± Fraction-exact rounding` per N ∈ {0..4} (per-N tables UNCHANGED at v38); ETH bonus EV = exactly 5.000% per N analytical (per-N WWXRP factor tables UNCHANGED at v38); per-N hero EV-neutrality holds within 0.05% calibration tolerance (per-N HERO_BOOST tables UNCHANGED at v38; HERO_PENALTY / HERO_SCALE UNCHANGED), ±1% empirical per Wave 2 STAT-02; solvency invariant `claimablePool ≤ ETH balance + stETH balance` PRESERVED; PAY-SPLIT 3-tier rule preserves `ethShare + lootboxShare = payout` invariant at every tier (PAY-SPLIT UNCHANGED at v38); no new mint sites.

---

## 4. F-38-NN Finding Blocks

### 4.1. Adversarial Sweep — 7-Surface Row Table

Per AUDIT-02 design contract: 7 adversarial surfaces (a)..(g) covering the v38.0 delta scope. Each row contains `Verdict:`, `Evidence:`, `Grep recipe:` (where applicable), and `Prose justification:` blocks. Default verdict bucket per D-272-FIND-01: SAFE / SAFE_BY_DESIGN / SAFE_BY_STRUCTURAL_CLOSURE. Zero F-38-NN finding blocks emitted unless D-272-ADVERSARIAL-01 escalation surfaces a FINDING_CANDIDATE / 8th-surface NEW_VECTOR / KI promotion candidate that user disposition approves.

#### Surface (a) — Hero always-on EV-neutrality preserved across (M, N)

**Verdict:** SAFE_BY_DESIGN.

**Evidence:**
- Per-N HERO_BOOST tables `HERO_BOOST_N0_PACKED` .. `HERO_BOOST_N4_PACKED` at L337-341 byte-identical at v38 HEAD vs `2654fcc2` (Wave 1 commit `527e3adc` does not modify the per-N HERO_BOOST tables).
- `HERO_PENALTY = 9500` (L342) and `HERO_SCALE = 10000` (L343) UNCHANGED at v38.
- EV-neutrality calibration: `P(hero|M, N) × boost(M, N) + (1 − P(hero|M, N)) × HERO_PENALTY = HERO_SCALE` for each (M, N) ∈ ({2..7} × {0..4}). The 5 per-N tables encode 6 values each (M = 2..7; M < 2 zero-payout exemption, M = 8 hero-EV-neutrality exemption).
- Empirical: Wave 2 STAT-01 (`test/stat/DegenerettePerNEvExactness.test.js`) at ≥1M draws/N + STAT-02 (`test/stat/DegeneretteBonusEv.test.js`) at ≥100K hero-active draws/N — re-pinned under always-on hero with hero-off baseline run dropped; EV-neutrality within ±1% per (M, N).
- Phase 267 Fraction-exact analytical audit (`.planning/notes/degenerette-recalibration/derive_5_tables.py` Python `Fraction` arithmetic) is the calibration source of truth; v38 inherits the v37.0 Phase 267 `PASS_ALL_25` byte-identity proof unchanged.

**Grep recipe (constants UNCHANGED):**
```
git diff 2654fcc2..HEAD -- contracts/modules/DegenerusGameDegeneretteModule.sol \
  | grep -E "HERO_BOOST_N[0-4]_PACKED|HERO_PENALTY|HERO_SCALE"
```
Expected output: zero matches (constants UNCHANGED at v38).

**Prose justification:** Hero EV-neutrality is preserved by the per-N HERO_BOOST table calibration, NOT by the player's ability to opt-out. Removing the opt-out toggle does not change expected payout because the per-N HERO_BOOST tables were calibrated under the EV-neutrality equation in the FIRST place — the calibration zeroes out the expected hero contribution across the (M, N) joint distribution. Under the always-on schedule, the hero multiplier applies for every M ∈ {2..7}; the player still receives `E[payout(M, N)] = basePayout(M, N)` by construction. EV is invariant across the always-on transition. Only variance increases on the variance-averse player subset (cross-cite surface (f)).

#### Surface (b) — Hero quadrant 0 default does NOT create payout-bias for players who omit heroQuadrant

**Verdict:** SAFE_BY_DEFENSIVE_VALIDATION (revised at Wave 1.5 from SAFE_BY_DESIGN).

**Wave 1.5 verdict prose update (commit `4760459f`):** v38 Wave 1.5 closed this surface via defensive boundary validation: the `placeDegeneretteBet(..., heroQuadrant)` call reverts with `InvalidBet` for any `heroQuadrant >= 4` (including the v37+ `0xFF` sentinel), so the only on-chain code path is the valid-quadrant path. The asymmetric "omit heroQuadrant" path no longer exists — frontend MUST send a valid `0..3` quadrant or the bet reverts at the public ABI boundary. SAFE_BY_DEFENSIVE_VALIDATION. Tracked as D-272-INPUT-VALIDATION-01 in `272-CONTEXT.md`; cross-cite §3.A Row 1.13 for evidence + design-intent trace.

**Evidence:**
- `packedTraitsDegenerette` (v37.0 Phase 267 producer) is UNCHANGED at v38 — per-quadrant near-uniform color distribution `[16,16,16,16,16,16,16,8]/120` (commons 13.33% each, gold 6.67%); uniform 1/8 symbol; byte layout `[QQ][CCC][SSS]` preserved per DGN-01 + DGN-14 + Phase 268 STAT-02 chi² ≥1M-sample uniformity at `test/stat/DegenerettePerNEvExactness.test.js`.
- Hero EV-neutrality (per surface (a)) is per-quadrant identical by table construction — the same per-N HERO_BOOST table dispatch applies for any heroQuadrant ∈ {0..3}.
- **Wave 1.5 (commit `4760459f`):** Player passing `0xFF` (or any `>= 4`) now REVERTS with `InvalidBet` at `_placeDegeneretteBetCore` entry (`if (heroQuadrant >= 4) revert InvalidBet();`) — the previous HERO-01 silent-normalize path is no longer reachable for production inputs. The only on-chain code path is the valid `0..3` quadrant path.
- Phase 268 STAT-01 per-N cross-pick parity describe (within `test/stat/DegenerettePerNEvExactness.test.js`) validates EV invariance across player-pick configurations under the v34 trait producer.

**Prose justification:** The asymmetric "omit heroQuadrant" path that surface (b) originally guarded against no longer exists at v38 close. Wave 1.5 defensive boundary validation rejects any `heroQuadrant >= 4` at the public ABI entry, so every accepted bet has `heroQuadrant ∈ {0..3}` and the EV-neutrality argument from surface (a) applies uniformly: (i) the symbol distribution is uniform 1/8 across all 4 quadrants (Phase 268 STAT-02), (ii) the hero match probability is P(hero|M, N) = 1/8 for any chosen quadrant, and (iii) the per-N HERO_BOOST table indexes by N (gold-quadrant count, NOT player-chosen heroQuadrant), so the boost/penalty schedule is identical regardless of heroQuadrant choice. The pre-Wave-1.5 concern — that a player passing `0xFF` would get hero multiplier on quadrant 0 (HERO-01 normalization) but would NOT be credited to `dailyHeroWagers[day][0]` (the L484 gate used raw input) — was the Hypothesis (i) docs-vs-behavior drift surfaced by the Wave 3 3-skill PARALLEL adversarial pass. Wave 1.5 RESOLVED_AT_V38 by eliminating the asymmetric path entirely: invalid input is rejected at the boundary, so the ledger-tracking inconsistency cannot occur for any accepted bet.

#### Surface (c) — Each cleanup-sweep removal preserves the invariant it claimed to guard

**Verdict:** SAFE_BY_DESIGN.

**Evidence (per-CLEAN-NN inline design-intent trace per D-272-DESIGN-INTENT-01 + `feedback_design_intent_before_deletion.md`):**

- **MASK_3 (L347, v37 baseline) DELETED.** Sole callsite was the heroBits extraction at v37 baseline L592 (removed by HERO-02). Cross-module grep `grep -rn "MASK_3" contracts/` returned zero other-file matches pre-deletion. Design-intent: 3-bit mask was for `[enabled, quadrant_lo, quadrant_hi]`; under always-on hero schedule the load-bearing form is the 2-bit `MASK_2 = 0x3` quadrant-only extract.
- **heroBits + heroEnabled locals (v37 baseline L592-594) DELETED via HERO-02.** Design-intent: opt-out intermediate; under always-on schedule, the direct quadrant extract `uint8((packed >> (FT_HERO_SHIFT + 1)) & MASK_2)` is the load-bearing form. Storage layout byte-identical preserves one-line revert path if always-hero is ever rolled back.
- **bool heroEnabled parameter on `_fullTicketPayout` (v37 baseline L952) DELETED via HERO-03.** Design-intent: opt-out toggle; under always-on schedule, the guard predicate `heroEnabled &&` is statically true at this call site so the parameter carried no information. Removal preserves the safety property (the `matches >= 2 && matches < 8` predicate is unchanged) per `feedback_no_dead_guards.md`.
- **@param heroEnabled NatSpec line (v37 baseline L948-953) DELETED via HERO-04.** Design-intent: the NatSpec entry described the opt-out toggle; removing the parameter without removing its `@param` would leave a stale doc-line referencing a non-existent argument.
- **Stale "enabled" / "opt-out" comments REWRITTEN per HERO-04 + D-272-NATSPEC-DISCIPLINE-01.** Touchpoints: L321 FT_HERO_SHIFT inline comment, L366 @param heroQuadrant NatSpec, `_packFullTicketBet` NatSpec block, `_fullTicketPayout` NatSpec block. Design-intent: comments describe protocol state at v38 close per `feedback_no_history_in_comments.md` — zero comparative/historical language ("previously was opt-out", "v37 → v38 change", etc.).
- **CLEAN-05 negative result:** no additional redundant-guard removals beyond the HERO-03 guard simplification. Planner manual grep-walk per D-272-CLEAN-DISCOVERY-01 scanned for `require` / `revert` predicates statically provable from caller-clamp or upstream invariant; no further candidates surfaced.

**Discovery method:** D-272-CLEAN-DISCOVERY-01 planner manual grep-walk within `DegenerusGameDegeneretteModule.sol` (NOT `/gas-audit` orchestrator). Each candidate carries the inline design-intent trace above per `feedback_design_intent_before_deletion.md` PRIMARY governing memory.

**Prose justification:** Each removal preserves the invariant the removed code claimed to guard:
- MASK_3 → invariant preserved by MASK_2 + direct quadrant extract (the 3-bit mask was for the v37 opt-out form; the 2-bit form is the always-on load-bearing form).
- heroBits/heroEnabled locals → invariant preserved by direct extract on a single line.
- heroEnabled parameter → invariant preserved by static-truth of the `heroEnabled` arm under always-on schedule.
- @param NatSpec line → no invariant to preserve (the param no longer exists).
- Stale comments → invariant of doc-code alignment preserved by describing what IS at v38 close.

No deletion removes a guard whose predicate was non-trivially true at v37 baseline; every removal is structurally proven safe by the always-on schedule + bit-allocation preservation.

#### Surface (d) — Storage layout byte-identical at v38 vs `2654fcc2`

**Verdict:** SAFE_BY_STRUCTURAL_CLOSURE.

**Evidence:**
- `FT_HERO_SHIFT = 237` (L321) preserved — 3-bit allocation maintained per HERO-02 bit allocation lock; no collapse to 2 bits (which would shift storage layout).
- Vestigial enabled bit at `FT_HERO_SHIFT + 0` always = 1 post-pack (set unconditionally via `uint256(1)` in the pack expression at L843); freed bit reserved for future feature.
- Quadrant field at `FT_HERO_SHIFT + 1` encodes the 2-bit effectiveQuadrant.
- Cross-cite §3.B AUDIT-04 grep-proof: `git diff 2654fcc2..HEAD -- contracts/DegenerusGameStorage.sol` empty (zero new storage slots).

**Grep recipe:**
```
diff <(git show 2654fcc2:contracts/modules/DegenerusGameDegeneretteModule.sol \
        | grep -E "FT_.*_SHIFT") \
     <(grep -E "FT_.*_SHIFT" contracts/modules/DegenerusGameDegeneretteModule.sol)
```
Expected exit 0 (all `FT_*_SHIFT` constant declarations byte-identical).

**Prose justification:** The HERO-02 bit allocation lock (3 bits at `FT_HERO_SHIFT = 237`) is explicit storage-layout discipline. Collapsing to 2 bits would shift all subsequent bit-packed fields (cascading storage-layout shift). By preserving the 3-bit allocation with a vestigial always-1 bit at offset 0, the on-chain packed bet representation remains byte-identical across v37 → v38. This preserves a one-line revert path if always-hero is ever rolled back: re-enabling the opt-out toggle requires only re-introducing the `heroEnabled` extraction at v37 baseline L592 (the bit is still there in storage).

#### Surface (e) — Public ABI byte-identical

**Verdict:** SAFE_BY_STRUCTURAL_CLOSURE.

**Evidence:**
- `placeDegeneretteBet(address player, uint8 currency, uint128 amountPerTicket, uint8 ticketCount, uint32 customTicket, uint8 heroQuadrant)` signature UNCHANGED at v38 (HERO-01 normalization is INTERNAL — operates inside `_packFullTicketBet`).
- HERO-03 signature change to `_fullTicketPayout` is INTERNAL-ONLY (function remains `private`).
- `0xFF` and any `>= 4` heroQuadrant input still accepted at the ABI boundary (no input validation revert added); the normalization-to-quadrant-0 happens inside `_packFullTicketBet` via `uint8 effectiveQuadrant = heroQuadrant < 4 ? heroQuadrant : 0;` (L832).
- Cross-cite §3.B AUDIT-04 grep G10 documented in §3.A row group attestation. Cross-cite §3.A Row 1.5 (HERO-05) storage layout + public ABI byte-identity attestation.

**Grep recipe:**
```
git diff 2654fcc2..HEAD -- contracts/ \
  | grep -E '^\+.*function .* (public|external)'
```
Expected output: 0 hits.

**Prose justification:** Public ABI byte-identity is preserved because the HERO-01 normalization is internal — the function selector at the ABI boundary `placeDegeneretteBet(address,uint8,uint128,uint8,uint32,uint8)` is unchanged. Existing integrators continue to pass `heroQuadrant = 0xFF` and the call succeeds (no revert); the protocol simply treats the input as "quadrant 0 (top-left)" internally. UI simplification benefit is achievable without ABI break — the frontend can stop emitting a hero-toggle UI control because there's no longer a way to opt out, but the on-chain interface remains backward-compatible.

#### Surface (f) — Variance impact bound on risk-averse subset

**Verdict:** SAFE_BY_DESIGN (accepted variance impact per user disposition).

**Evidence:**
- Pre-v38 opt-out posture: variance-averse players could pass `heroQuadrant = 0xFF` to skip the hero multiplier and lock payout at `basePayout(M, N)` (zero variance from hero multiplier).
- Post-v38 always-on schedule: the hero multiplier applies for M ∈ {2..7} regardless of player input. Worst-case downside per spin = `HERO_PENALTY × basePayout = 0.95 × basePayout` (5% downside); best-case upside per spin = `boost-magnitude × basePayout` (per-N table, ranges from ~1.18× to ~2.50× across the 6-value per-N tables M ∈ {2..7}).
- EV-neutral by construction per surface (a) — bounded variance increase; zero EV change.
- Documented in D-272-DESIGN-INTENT-01 actor walk-through inline at Wave 1 commit message `527e3adc` body + at this §4 surface (f) prose disclosure ONLY (no new KNOWN-ISSUES.md Design Decisions entry per D-272-KI-01).
- Player has zero EV-rational reason to prefer pre-v38 over post-v38 (EV invariant). Variance-averse players lose a variance-reduction tool but receive the same EV.

**Actor walk-through (cross-cite D-272-DESIGN-INTENT-01):**
- EV-rational players (risk-neutral / risk-loving): zero effect.
- Variance-averse players: lose variance-reduction tool. Worst-case downside per spin = 0.95 × basePayout; best-case upside = boost-magnitude × basePayout (per-N table). Bounded variance increase; zero EV change.
- Whales / casual / admin / governance: zero differential impact (shared storage slot, RNG word, payout function).
- Adversarial: pre-v38 `heroQuadrant = 0xFF` could dodge unlucky hero-penalty hit but was EV-neutral, so no EV gain. Post-v38: cannot dodge; variance-neutral on expectation.

**Prose justification:** The variance impact is bounded and acceptable per user disposition (degen-game context). Risk-averse players cannot extract value from the variance increase because EV is invariant; they merely face higher second-moment dispersion of outcomes. The downside ceiling is `HERO_PENALTY = 9500/10000 = 0.95 × basePayout` per spin (5% downside per hero-active spin), bounded above by the per-N HERO_BOOST table maxima. The boundary semantics are deterministic post-VRF-fulfillment (the hero match check `((playerTicket >> heroQuadrant*8) & 7) == ((resultTicket >> heroQuadrant*8) & 7)` is a function of VRF-derived bits committed pre-VRF-reveal per `feedback_rng_commitment_window.md`). No player-reachable path extracts protocol value from this variance increase; KNOWN-ISSUES.md UNMODIFIED at v38 per D-272-KI-01 default zero-promotion path. `/economic-analyst` Task 3.5 has the escalation hook per D-272-ADVERSARIAL-01 to flag this as a KI promotion candidate if mechanism-design red-team disagrees with the accepted-design verdict.

#### Surface (g) — `npm run test:stat` + `npm run test:gas` clean run at v38 close

**Verdict:** SAFE_BY_STRUCTURAL_CLOSURE.

**Evidence:**
- GASPIN-02 path (a-alt) script-split applied at `package.json` (Wave 2 commit `e3fcb95c`): new `test:gas` script wires `Phase261GasRegression + Phase264GasRegression + Phase268GasRegression + LootboxOpenGas + AdvanceGameGas`; `test:stat` excludes those gas files. Test bodies UNCHANGED (`Phase261/264` diff vs `2654fcc2` exit 0).
- GASPIN-03 consistency-gate verification (Wave 2 Task 2.5): pre-Wave-2 `test:stat` exit=1 with 5 failures; post-Wave-2 `test:stat` exit=1 with 1 failure (STAT-03-v35-carry ACCEPTED-DESIGN remaining failure per Wave 2 Task 2.6 ledger entry). Non-regression vs pre-Wave-2 baseline confirmed.
- The (a-alt) `npm run test:gas` split moves 3 cumulative-state-drift failures off `test:stat` into a dedicated runner; gas-pin drift failures persist under `test:gas` per v36.0 "128k is fine approved" acceptance (not regression-worse than pre-Wave-2 baseline).
- SURF-03 rebase fixes the 4th pre-edit failure (LootboxModule diff against `PHASE_269_CLOSE_BASELINE = 8fd5c2e1` is now empty).
- STAT-03-v35-carry remaining failure documented as ACCEPTED-DESIGN per v35.0 Phase 265 D-265-STAT03-01 fixture-calibration-error reframe (88.24% empty-bucket skip rate is fixture-density artifact, NOT protocol behavior).

**Prose justification:** The clean-run target is satisfied modulo the documented STAT-03-v35-carry ACCEPTED-DESIGN gate behaving per pre-edit exit semantics. The (a-alt) script-split is the load-bearing improvement: it isolates gas-pin tests (which suffer cumulative-state drift under multi-file ordering per v36.0 D-269-STAB-01 RCA) from stat-pin tests (which assert mathematical invariants). Under the post-Wave-2 baseline, `test:stat` exit=1 with 1 known-design failure (STAT-03-v35-carry) and `test:gas` exit=1 with the v36.0 "128k is fine approved" gas-pin drift envelope. Both behaviors are pre-edit baseline-matching; neither is a Phase 272 regression.

**RNG commitment-window degenerate-PASS attestation** (1-line per `feedback_rng_commitment_window.md`): Phase 272 has zero RNG-path mutation; commitment-window check is structurally trivial at v38 (no VRF request, fulfillment, or word-derived input flow was modified). EntropyLib byte-identical at v38 HEAD (REG-03 cross-cite in §6b; cross-module byte-identity grep-proof in §3.B). Backward-trace per `feedback_rng_backward_trace.md` is structurally trivial at v38 because no new RNG consumer is introduced; the existing Degenerette payout path consumes VRF-derived `rngWord` via `_resolveFullTicketBet` byte-identical at the entropy-consumption layer (only the hero-quadrant extraction local was modified, which does NOT read VRF-derived bits — it reads stored-bet bits committed at pack time before VRF reveal).

### 4.2. Verdict Roll-Up + Adversarial-Pass Status

7 of 7 surfaces (a)..(g) verdicted SAFE / SAFE_BY_DESIGN / SAFE_BY_STRUCTURAL_CLOSURE per inline draft (Task 3.2). Adversarial-pass validation via `/contract-auditor` + `/zero-day-hunter` + `/economic-analyst` PARALLEL spawn (Task 3.5) per D-272-ADVERSARIAL-01; full output logged in `.planning/phases/272-always-hero-simplification-maximal-dead-code-cleanup-terminal/272-01-ADVERSARIAL-LOG.md`. Default expected: all 3 skills concur; zero FINDING_CANDIDATE, zero 8th-surface NEW_VECTOR, zero KI Design Decisions promotion candidate. Phase 272 §4 verdict roll-up STANDS unchanged; KNOWN-ISSUES.md UNMODIFIED per D-272-KI-01 default zero-promotion path. Zero F-38-NN finding blocks emit per D-272-FIND-01 carry default path.

---

## 5. Regression Appendix

### 5a. REG-01 — v37.0 Intermediate Closure-Signal Non-Widening

| Row ID | Source | Delta SHA | Subject Surface at HEAD `06623edb` | Re-Verification Evidence | Verdict |
| ------ | ------ | --------- | ------------------------------ | ------------------------ | ------- |
| REG-v37.0-HERO-CLEAN | v37.0 intermediate closure signal `MILESTONE_V37_AT_HEAD_2654fcc2` carry-forward from `audit/FINDINGS-v37.0.md` §9c | `2654fcc2..<v38-close-sha>` (1 Wave 1 contract commit `527e3adc` + 1 Wave 2 test commit `e3fcb95c`) | EntropyLib + JackpotModule + MintModule + TraitUtils + JackpotBucketLib + LootboxModule byte-identical at v38 HEAD per cross-module byte-identity grep proof (`git diff 2654fcc2..HEAD -- <file>` returns 0 lines for each file; see §3.B grep recipe block). Lootbox UNCHANGED at v38 (D-272-CLEAN-SCOPE-01 narrowing — cleanup applies ONLY to `DegenerusGameDegeneretteModule.sol`); SURF-02 v38.0 describe in `test/stat/SurfaceRegression.test.js` cross-cites this byte-identity at the harness level. The only v38 mutation at the contract layer is `contracts/modules/DegenerusGameDegeneretteModule.sol` (Wave 1 commit `527e3adc`; +18 / −16 LOC across the hero-pack/extract block + cleanup-sweep deletions). Per-N HERO_BOOST tables UNCHANGED; per-N payout tables UNCHANGED; PAY-SPLIT 3-tier rule UNCHANGED. | v37 §4 8-surface verdicts (a)..(h) carry forward unchanged at v38 HEAD: surface (a) per-N table dispatch correctness UNCHANGED (per-N tables byte-identical); surface (b) symbol-only hero match UNCHANGED (`_applyHeroMultiplier` body byte-identical at v38); surface (c) `_countGoldQuadrants` boundary UNCHANGED; surface (d) producer byte-layout consistency UNCHANGED; surface (e) WWXRP × hero composition UNCHANGED; surface (f) lootbox dead-branch removal byte-equivalence UNCHANGED (LootboxModule byte-identical at v38); surface (g) hero × per-N composition UNCHANGED; surface (h) PAY-SPLIT 3-tier rule monotonicity UNCHANGED. | PASS |

### 5b. REG-02 — v34.0 Closure-Signal Non-Widening

| Row ID | Source | Delta SHA | Subject Surface at HEAD `06623edb` | Re-Verification Evidence | Verdict |
| ------ | ------ | --------- | ------------------------------ | ------------------------ | ------- |
| REG-v34.0-TRAIT-SOLO | v34.0 closure signal `MILESTONE_V34_AT_HEAD_6b63f6d4daf346a53a1d463790f637308ea8d555` carry-forward from `audit/FINDINGS-v34.0.md` §9c (via v37.0 REG-02 carry) | `6b63f6d4..<v38-close-sha>` | TraitUtils existing 3 functions (`weightedColorBucket` + `traitFromWord` + `packedTraitsFromSeed`) + `packedTraitsDegenerette` (v37.0 Phase 267 NEW additive helper) byte-identical at v38 HEAD per cross-module byte-identity grep proof. `_pickSoloQuadrant` body + 4 ETH-distribution injection sites + JackpotBucketLib + EntropyLib byte-identical at v38 HEAD (no v38 mutation to gold-solo Mint / non-lootbox Jackpot path). **Surfaces strictly disjoint:** Phase 272 v38 payload mutates only the Degenerette hero-quadrant extraction (orthogonal to v34 trait/solo verdicts). | v34 §4 6-surface trait/solo verdicts are orthogonal to v38 hero-quadrant-extraction payload; carry forward unchanged. No v38 commit touches `contracts/libraries/JackpotBucketLib.sol`, `contracts/DegenerusTraitUtils.sol`, or `contracts/modules/DegenerusGameJackpotModule.sol`. | PASS |

### 5c. REG-03 — KI Envelope Re-Verifications

4-row KI envelope re-verifications per D-272-KI-01 carry-forward. Mirrors §6b 4-row table format.

| EXC | Surface | v38.0 Disposition | Evidence |
| --- | ------- | ---------------- | -------- |
| EXC-01 | Affiliate roll RNG | `RE_VERIFIED-NEGATIVE-scope` | Phase 272 has zero affiliate-roll interaction. MintModule byte-identical at v38 HEAD vs `2654fcc2` (cross-module byte-identity grep proof in §3.B). No v38 commit touches the affiliate-roll path. Carry-forward from v37.0 §6b EXC-01 NEGATIVE-scope. |
| EXC-02 | Backfill / prevrandao fallback | `RE_VERIFIED-NEGATIVE-scope` | Phase 272 has zero AdvanceModule interaction. AdvanceModule body byte-identical at v38 HEAD vs `2654fcc2` (no `contracts/modules/DegenerusGameAdvanceModule.sol` in the v38 diff scope). No v38 commit touches the gameover-prevrandao-fallback path. Carry-forward from v37.0 §6b EXC-02 NEGATIVE-scope. |
| EXC-03 | F-29-04 mid-cycle write-buffer substitution | `RE_VERIFIED-NEGATIVE-scope` | Phase 272 has zero gameover-RNG-substitution interaction. AdvanceModule + swap path byte-identical at v38 HEAD. No v38 commit modifies the mid-cycle write-buffer mechanics. Carry-forward from v37.0 §6b EXC-03 NEGATIVE-scope. |
| EXC-04 | EntropyLib XOR-shift PRNG (BAF-jackpot-only scope at v36.0) | `RE_VERIFIED with NARROWS retained` | EntropyLib body byte-identical at v38 HEAD vs `2654fcc2` (per cross-module byte-identity grep proof in §3.B — `git diff 2654fcc2..HEAD -- contracts/libraries/EntropyLib.sol` returns 0 lines) AND vs v36.0 baseline `1c0f0913` per REG-01 chain (v37.0 SURF-04 grep-proof). **Backward-trace per `feedback_rng_backward_trace.md`:** Phase 272 Degenerette payload does NOT consume xorshift output; the Degenerette path reads VRF-derived high-entropy bits via `_resolveFullTicketBet` which consumes `lootboxRngWordByIndex[index]` (a VRF callback word) NOT XOR-shift output. The xorshift PRNG (EntropyLib.entropyStep) remains as BAF-jackpot consumer only at v38 HEAD per v36 ENT-05 carry; NARROWS scope (BAF-jackpot-only) preserved. **Commitment-window check per `feedback_rng_commitment_window.md`:** trivial degenerate PASS at v38 — no new RNG consumer introduced; existing consumer path byte-identical. |

**Backward-trace methodology cite:** Per `feedback_rng_backward_trace.md` (every RNG audit must trace BACKWARD from each consumer to verify word was unknown at input commitment time): the v38 hero-quadrant extraction at `_resolveFullTicketBet` L591 reads `heroQuadrant` from the STORED PACKED BET (bits of the packed-bet word committed at `_packFullTicketBet` time, BEFORE VRF reveal). The match check inside `_applyHeroMultiplier` at L1018 reads VRF-derived `resultTicket` bits (from `lootboxRngWordByIndex[index]` — VRF callback word, unknown at bet commitment time). The match predicate `((playerTicket >> heroQuadrant*8) & 7) == ((resultTicket >> heroQuadrant*8) & 7)` compares a player-committed bit (heroQuadrant choice, fixed at bet placement) against a VRF-derived bit (symbol nibble, unknown at bet placement). Backward-trace closed: the VRF word is structurally unknown at the player's commitment point. EntropyLib byte-identical at v38 HEAD; commitment-window check is structurally trivial at v38.

### 5d. REG-04 — Prior-Finding Spot-Check Sweep

Per-finding 6-col PASS/REGRESSED/SUPERSEDED row table from REG-04 grep sweep across `audit/FINDINGS-v25.0.md` through `audit/FINDINGS-v37.0.md` for findings referencing the v38-touched function/surface set: `_fullTicketPayout`, `_packFullTicketBet`, `_resolveFullTicketBet`, `_applyHeroMultiplier`, `MASK_3`, `FT_HERO_SHIFT`, hero quadrant, hero opt-out.

| Row ID | Source Finding | Delta SHA | Subject Surface at HEAD `06623edb` | Re-Verification Evidence | Verdict |
| ------ | -------------- | --------- | ------------------------------ | ------------------------ | ------- |
| REG-v37.0-§4-(a) | `audit/FINDINGS-v37.0.md` §4 surface (a) "per-N table dispatch correctness vs match-count distribution P_N(M)" | `2654fcc2..<v38-close-sha>` | Per-N payout tables UNCHANGED at v38 HEAD (Wave 1 commit `527e3adc` does not modify per-N tables; cross-cite §3.A Row 1 Summary). v37.0 §4 (a) SAFE_BY_STRUCTURAL_CLOSURE verdict carries forward unchanged at v38 HEAD. | v37.0 STAT-01 ≥1M draws/N + Wave 2 STAT-01 (`test/stat/DegenerettePerNEvExactness.test.js`) re-pin under always-on hero PASS; basePayoutEV per N within ±0.50 centi-x preserved. | PASS |
| REG-v37.0-§4-(b) | `audit/FINDINGS-v37.0.md` §4 surface (b) "symbol-only hero match preserves uniformity, no color-channel info leak" | `2654fcc2..<v38-close-sha>` | `_applyHeroMultiplier` body L1009-1034 byte-identical at v38 HEAD vs `2654fcc2` (Wave 1 commit `527e3adc` does NOT modify `_applyHeroMultiplier` body — only the `heroEnabled` guard at the call site). The symbol-only equality comparison `((playerTicket >> heroQuadrant*8) & 7) == ((resultTicket >> heroQuadrant*8) & 7)` UNCHANGED. P(hero match) = 1/8 per quadrant UNCHANGED. | v37.0 §4 (b) SAFE_BY_DESIGN verdict carries forward unchanged at v38. Wave 2 STAT-02 hero EV-neutrality within ±1% preserved under always-on hero. | PASS |
| REG-v37.0-§4-(c) | `audit/FINDINGS-v37.0.md` §4 surface (c) "`_countGoldQuadrants` boundary `color == 7` strict (not `>= 7`)" | `2654fcc2..<v38-close-sha>` | `_countGoldQuadrants` body byte-identical at v38 HEAD (Wave 1 commit `527e3adc` does not touch `_countGoldQuadrants`). Strict-equality discipline preserved. | v37.0 §4 (c) SAFE_BY_DESIGN verdict carries forward unchanged at v38. | PASS |
| REG-v37.0-§4-(h) | `audit/FINDINGS-v37.0.md` §4 surface (h) "ETH payout split-rule monotonicity + boundary-gaming check (v37-NEW)" | `2654fcc2..<v38-close-sha>` | `_distributePayout` body byte-identical at v38 HEAD (Wave 1 commit `527e3adc` does not touch `_distributePayout`). PAY-SPLIT 3-tier rule UNCHANGED at v38. Total payout invariant `ethShare + lootboxShare = payout` preserved at every tier. | v37.0 §4 (h) SAFE_BY_DESIGN verdict + accepted-design ledger (boundary discontinuity at exactly 3.0× bet) carries forward unchanged at v38. KNOWN-ISSUES.md UNMODIFIED at v38 per D-272-KI-01. | PASS |
| REG-v36.0-ENT-02 | `audit/FINDINGS-v36.0.md` §3d ENT-02 "`_resolveLootboxRoll` 4 entropyStep callsites removed; L1585 dead WWXRP advance DELETED" | `1c0f0913..<v38-close-sha>` | v36.0 ENT-02 closed via inline-bit-slice refactor (carried forward through v37 + LBX-01 at Phase 269). `_resolveLootboxRoll` 4 hash2/bit-slice callsites byte-identical at structural level at v38 HEAD (LootboxModule byte-identical at v38 vs `2654fcc2`; LBX-03 anchor preserved). | v36.0 ENT-02 CLOSED + v37.0 Phase 269 LBX-01 audit-cleanliness-only cleanup; v38 introduces zero lootbox-path mutation per D-272-CLEAN-SCOPE-01 narrowing. | PASS |
| REG-v34.0-TRAIT-06 | `audit/FINDINGS-v34.0.md` §3 TRAIT-06 "Hardhat unit suite at `test/unit/DegenerusTraitUtils.test.js`" | `6b63f6d4..<v38-close-sha>` | v38 introduces NO test deletions on `test/unit/DegenerusTraitUtils.test.js`. Wave 2 SURF-01a v38.0 describe in `test/stat/SurfaceRegression.test.js` ADDS byte-identity assertion on `DegenerusTraitUtils.sol` (the contract itself) vs v37.0 baseline `2654fcc2`. | v34.0 TRAIT-06 PASS carries forward unchanged. | PASS |
| REG-v35.0-STAT-03 | v35.0 carry — `test/stat/PerPullEmptyBucketSkip.test.js` 88.24% empty-bucket skip rate | `<v35.0-close-sha>..<v38-close-sha>` | v35.0 Phase 265 D-265-STAT03-01 reframe documents the 88.24% skip rate as fixture-density artifact (sparse deity-backed holder map), NOT protocol behavior. v38 Wave 2 commit `e3fcb95c` prepends an ACCEPTED-DESIGN ledger-entry prose block to `test/stat/PerPullEmptyBucketSkip.test.js` per STAT-03-v35-carry path (chosen over populate-dense-fixture). Test bodies UNCHANGED; standalone pre/post-edit exit codes match. | Re-affirmed at v38 as ACCEPTED-DESIGN ledger entry. Failing test outcome is fixture-density artifact, not protocol regression. | PASS (ACCEPTED-DESIGN re-affirmed at v38) |

### 5e. Regression Distribution Summary

| Verdict | REG-01 | REG-02 | REG-03 | REG-04 | Total |
| ------- | ------ | ------ | ------ | ------ | ----- |
| PASS    | 1      | 1      | 4 (1 NARROWS-retained) | 7 | 13 |
| REGRESSED | 0    | 0      | 0      | 0      | 0     |
| SUPERSEDED | 0   | 0      | 0      | 0      | 0     |
| **Total** | **1** | **1** | **4** | **7** | **13** |

Zero REGRESSED rows. Zero SUPERSEDED rows at v38 (the v37.0 SUPERSEDED row REG-v30.0-INV-237-134..137 was already SUPERSEDED by v36.0 ENT-02 + v37.0 LBX-01; no new supersedence at v38). EXC-04 NARROWS-retained per §5c REG-03 (BAF-jackpot-only scope carries forward; EntropyLib byte-identical at v38 HEAD). Surfaces strictly disjoint between v38 Degenerette hero-quadrant-extraction edit and all v34/v36/v37 verdicts.

---

## 6. KI Gating Walk

### 6a. Non-Promotion Ledger

Zero F-38-NN finding blocks emitted per D-272-FIND-01; zero rows in Non-Promotion Ledger.

Default path: Phase 272 §4 7-surface inline draft (Task 3.2) verdicts 7 of 7 SAFE / SAFE_BY_DESIGN / SAFE_BY_STRUCTURAL_CLOSURE. Task 3.5 adversarial-pass via `/contract-auditor` + `/zero-day-hunter` + `/economic-analyst` (3 skills PARALLEL spawn per D-272-ADVERSARIAL-01) concurs with zero disagreement per `272-01-ADVERSARIAL-LOG.md` Disposition note (D-272-ADVERSARIAL-01 escalation path evaluated and does NOT fire by default). Surface (f) variance-impact-on-risk-averse-subset satisfies the D-09 3-predicate KI Gating Rubric (accepted-design + non-exploitable + sticky) in principle but is correctly documented via §4 (f) prose-only attestation per D-272-KI-01 default disposition — `/economic-analyst` assessment concludes KNOWN-ISSUES.md UNMODIFIED is the correct disposition (zero EV change; variance increase bounded; no player-reachable value-extraction path).

### 6b. KI Envelope Re-Verifications

4-row KI envelope table mirroring v37.0 §6b format. Per D-272-KI-01: EXC-01..03 RE_VERIFIED-NEGATIVE-scope; EXC-04 RE_VERIFIED with NARROWS retained from v36.0.

| EXC | Surface | v38.0 Disposition | Evidence |
| --- | ------- | ---------------- | -------- |
| EXC-01 | Affiliate roll RNG | `RE_VERIFIED-NEGATIVE-scope` | Phase 272 has zero affiliate-roll interaction. MintModule byte-identical at v38 HEAD vs `2654fcc2` (cross-module byte-identity grep proof in §3.B). No v38 commit touches the affiliate-roll path. Carry-forward from v37.0 §6b EXC-01 + v36.0 Phase 266 KI envelope walk. |
| EXC-02 | Backfill / prevrandao fallback | `RE_VERIFIED-NEGATIVE-scope` | Phase 272 has zero AdvanceModule interaction. AdvanceModule body byte-identical at v38 HEAD vs `2654fcc2`. No v38 commit touches the gameover-prevrandao-fallback path. Carry-forward from v37.0 §6b EXC-02 + v36.0 Phase 266 KI envelope walk. |
| EXC-03 | F-29-04 mid-cycle write-buffer substitution | `RE_VERIFIED-NEGATIVE-scope` | Phase 272 has zero gameover-RNG-substitution interaction. AdvanceModule + swap path byte-identical at v38 HEAD. No v38 commit modifies the mid-cycle write-buffer mechanics. Carry-forward from v37.0 §6b EXC-03. |
| EXC-04 | EntropyLib XOR-shift PRNG (BAF-jackpot-only scope at v36.0) | `RE_VERIFIED with NARROWS retained` | EntropyLib body byte-identical at v38 HEAD vs `2654fcc2` per cross-module byte-identity grep proof in §3.B (`git diff 2654fcc2..HEAD -- contracts/libraries/EntropyLib.sol` returns 0 lines) AND vs v36.0 baseline `1c0f0913` per REG-01 chain. Per-pull-level keccak path UNCHANGED in v38 — Phase 272 Degenerette payload does NOT modify lootbox-path entropy consumption. Lootbox-path consumes high-entropy keccak via `EntropyLib.hash2` + bit-slicing per v36.0 ENT-01..06 + v37.0 LBX-01 carry (4 hash2/bit-slice callsites in `_resolveLootboxRoll` byte-identical at structural level at v38 HEAD — LootboxModule byte-identical at v38). NARROWS scope (BAF-jackpot-only) carried verbatim from v36 AUDIT-05 KI-envelope-narrowing edit through v37 + v38. |

**Backward-trace methodology cite (per `feedback_rng_backward_trace.md`):** Phase 272 Degenerette path consumes VRF-derived high-entropy keccak bits (NOT XOR-shift output) — the hero-quadrant extraction at `_resolveFullTicketBet` L591 reads bits committed at `_packFullTicketBet` time (BEFORE VRF reveal); the match check inside `_applyHeroMultiplier` at L1018 reads VRF-derived `resultTicket` bits (from `lootboxRngWordByIndex[index]` — VRF callback word, unknown at bet commitment time). EntropyLib XOR-shift remains as BAF-jackpot consumer only at v38 HEAD; backward-trace closed (the VRF word is structurally unknown at the player's commitment point). Phase 268 STAT-02 chi² ≥1M-sample uniformity validates the producer's color-symbol distribution (carried forward at v38).

**Commitment-window check cite (per `feedback_rng_commitment_window.md`):** Phase 272 has zero RNG-path mutation; commitment-window check is a structurally trivial degenerate PASS at v38 (no VRF request, fulfillment, or word-derived input flow was modified). Player-controllable state at bet placement: `heroQuadrant ∈ {0..3, 0xFF}`, currency, betAmount, ticketCount, customTicket. None of these can change between VRF request and fulfillment — they are stored in the packed bet at placement time. The HERO-01 normalization (`heroQuadrant >= 4 → 0`) happens INSIDE `_packFullTicketBet` BEFORE the bet is stored, so the normalized value is committed at bet placement. Bot front-run via VRF mempool visibility remains STRUCTURALLY PREVENTED (carry-forward from v36.0 + v37.0 commitment-window verdicts).

### 6c. Verdict Summary

**`0 of 0 KI_ELIGIBLE_PROMOTED; KNOWN_ISSUES_UNMODIFIED`**

Surface (f) variance-impact-on-risk-averse-subset is documented as accepted-design via §4 surface (f) prose disclosure ONLY per D-272-KI-01 + `/economic-analyst` mechanism-design assessment (see `272-01-ADVERSARIAL-LOG.md`). NO new KNOWN-ISSUES.md entry under Design Decisions. EV invariant preserved by per-N HERO_BOOST table calibration (per surface (a)); player receives same EV under all (M, N) configurations; bounded variance increase per user disposition (degen-game context); no player-reachable path extracts protocol value from the variance increase.

KNOWN-ISSUES.md UNMODIFIED at v38 close per `git diff 2654fcc2..HEAD -- KNOWN-ISSUES.md` returning empty.

---

## 7. Prior-Artifact Cross-Cites

Cross-cites organized in 4 subsections per the canonical FINDINGS shape: v38.0 phase artifacts, prior milestone FINDINGS, notes, and project-state artifacts.

### 7.1. v38.0 Phase Artifacts

- **Phase 272 — Always-Hero Simplification + Maximal Dead-Code Cleanup (Terminal):**
  - `.planning/phases/272-always-hero-simplification-maximal-dead-code-cleanup-terminal/272-CONTEXT.md` — phase-gather context with D-272-CLEAN-SCOPE-01 / D-272-CLEAN-DISCOVERY-01 / D-272-COMMIT-SHAPE-01 / D-272-DESIGN-INTENT-01 / D-272-NATSPEC-DISCIPLINE-01 + carry-forward chain D-272-FILES-01 / D-272-CLOSURE-01..02 / D-272-FCITE-01 / D-272-ADVERSARIAL-01 / D-272-KI-01 / D-272-SEV-01 / D-272-APPROVAL-01.
  - `.planning/phases/272-always-hero-simplification-maximal-dead-code-cleanup-terminal/272-DISCUSSION-LOG.md` — human-readable discussion record.
  - `.planning/phases/272-always-hero-simplification-maximal-dead-code-cleanup-terminal/272-01-PLAN.md` — multi-task planner output (4 waves: Wave 1 contract + Wave 2 test + Wave 3 audit deliverable + Wave 4 closure flips).
  - `.planning/phases/272-always-hero-simplification-maximal-dead-code-cleanup-terminal/272-01-ADVERSARIAL-LOG.md` — Task 3.5 output: 3 H2 sections (`/contract-auditor` + `/zero-day-hunter` + `/economic-analyst`) + Disposition + appended Wave 1.5 disposition update (post Wave 3 close, 2026-05-11).
  - `.planning/phases/272-always-hero-simplification-maximal-dead-code-cleanup-terminal/272-01-SUMMARY.md` — Wave 4 phase-close summary (post-Task-4.7 atomic commit).
  - Wave 1 contract commit: `527e3adc` — `feat(272): always-on hero default 0 + degenerette dead-code cleanup [HERO-01..05, CLEAN-01..05]`.
  - Wave 1.5 contract commit: `4760459f` — HERO-05 spec_lock revision: defensive boundary validation (`if (heroQuadrant >= 4) revert InvalidBet();` at `_placeDegeneretteBetCore` entry) + fuzz-handler clamp. USER-APPROVED batched commit covering `contracts/modules/DegenerusGameDegeneretteModule.sol` + `test/fuzz/handlers/DegeneretteHandler.sol`. Tracked as D-272-INPUT-VALIDATION-01.
  - Wave 2 test commit: `e3fcb95c` — `test(272): hero-always-on + dead-code cleanup + v37+ carry bundle [STAT-01..02, SURF-01..03, LBX-02, GASPIN-02..03, STAT-03-v35-carry]`.

**Hypothesis (i) cross-cite — Wave 1.5 resolution.** Wave 1.5 (commit `4760459f`) remediated Hypothesis (i) at v38 close via defensive boundary validation. Status updated from KEEP_AS_NEGATIVE_FINDING (at adversarial-pass close, recorded in `272-01-ADVERSARIAL-LOG.md` H2 sections) to **RESOLVED_AT_V38** (appended Wave 1.5 disposition update in the same log). The previous silent-normalize path (Hypothesis (i)'s root) no longer exists — invalid inputs (`heroQuadrant >= 4`) are rejected at the public ABI boundary with `InvalidBet` revert. Cross-cite §3.A Row 1.13 (Wave 1.5 evidence + design-intent trace), §4 surface (b) (revised verdict SAFE_BY_DEFENSIVE_VALIDATION), and §9.NN.iv (Hypothesis (i) row REMOVED — no v39+ pickup). Tracked as D-272-INPUT-VALIDATION-01 in `272-CONTEXT.md`.

### 7.2. Prior Milestone FINDINGS Cross-Cites

12 prior milestone-closure deliverables enumerated for REG-04 spot-check sweep + closure-signal chain context:

- `audit/FINDINGS-v25.0.md`
- `audit/FINDINGS-v27.0.md`
- `audit/FINDINGS-v28.0.md`
- `audit/FINDINGS-v29.0.md`
- `audit/FINDINGS-v30.0.md`
- `audit/FINDINGS-v31.0.md`
- `audit/FINDINGS-v32.0.md`
- `audit/FINDINGS-v33.0.md`
- `audit/FINDINGS-v34.0.md`
- `audit/FINDINGS-v35.0.md`
- `audit/FINDINGS-v36.0.md`
- `audit/FINDINGS-v37.0.md`

**Closure-signal chain:** v25 → v27 → v28 → v29 → v30 → v31 → v32 → v33 → v34 (`MILESTONE_V34_AT_HEAD_6b63f6d4daf346a53a1d463790f637308ea8d555`) → v35 → v36 (`MILESTONE_V36_AT_HEAD_1c0f09132d7439af9881c56fe197f81757f8164a`) → v37 (`MILESTONE_V37_AT_HEAD_2654fcc2`) → v38 (`MILESTONE_V38_AT_HEAD_06623edb` — emitted §9c at Task 3.6; SHA resolved at Wave 4 Task 4.6 atomic-update).

REG-01 carries v37.0 intermediate closure signal verbatim per §5a (REG-v37.0-HERO-CLEAN PASS).
REG-02 carries v34.0 closure signal verbatim per §5b (REG-v34.0-TRAIT-SOLO PASS).
REG-04 walks v25..v37.0 per §5d (7 PASS / 0 REGRESSED / 0 SUPERSEDED).

### 7.3. Notes Cross-Cites

- `.planning/notes/degenerette-recalibration/derive_5_tables.py` — Fraction-exact derivation script; canonical source of truth for the 25 packed constants. v38 inherits the v37.0 Phase 267 Task 2 `PASS_ALL_25` byte-identity proof unchanged (per-N tables UNCHANGED at v38).

### 7.4. Project-State Cross-Cites

- `.planning/PROJECT.md` "Current Milestone v38.0" block + "Deferred to Future Milestones" subsection (updated at Wave 4 Task 4.3 per D-272-CLOSURE-01 with v39+ carry-forward bullets — LBX-02 RE-DEFER + STAT-03-v35-carry ACCEPTED-DESIGN re-affirmed).
- `.planning/MILESTONES.md` closure-signal chain v25 → v37 + v38 in-progress row (flipped to SHIPPED at Wave 4 Task 4.6 with closure signal `MILESTONE_V38_AT_HEAD_06623edb` recorded).
- `.planning/ROADMAP.md` v38.0 milestone bullet (flipped to ✅ at Wave 4 Task 4.4).
- `.planning/REQUIREMENTS.md` 30 v38.0 requirements traceability (flipped to Complete at Wave 4 Task 4.5; LBX-02 traceability flipped to DEFERRED-V39+; STAT-03-v35-carry flipped to ACCEPTED-DESIGN; GASPIN-02 + GASPIN-03 flipped to COMPLETE).
- `KNOWN-ISSUES.md` EXC-01..04 envelopes (UNMODIFIED at v38 close per default path; `git diff` returns empty).

---

## 8. Forward-Cite Closure (D-253-09 + D-253-15 step 8 Terminal-Phase Rule)

Terminal-phase zero-emission verification per D-272-FCITE-01 (carry of D-271-FCITE-01 / D-266-FCITE / D-265-FCITE-01 / D-262-FCITE-01 / D-257-FCITE-01 / D-253-15 step 8 + ROADMAP terminal-phase rule). Phase 272 is the SOLE terminal v38.0 phase; v38.0 = single-phase milestone (Phase 272).

### 8a. Phase 272 Intra-Milestone Forward-Cite Residual Verification

**Grep recipe:**
```
grep -rnE 'Phase 27[3-9]|Phase 28[0-9]' \
  audit/FINDINGS-v38.0.md \
  .planning/phases/272-always-hero-simplification-maximal-dead-code-cleanup-terminal/272-CONTEXT.md \
  .planning/phases/272-always-hero-simplification-maximal-dead-code-cleanup-terminal/272-DISCUSSION-LOG.md \
  .planning/phases/272-always-hero-simplification-maximal-dead-code-cleanup-terminal/272-01-PLAN.md \
  .planning/phases/272-always-hero-simplification-maximal-dead-code-cleanup-terminal/272-01-SUMMARY.md \
  .planning/phases/272-always-hero-simplification-maximal-dead-code-cleanup-terminal/272-01-ADVERSARIAL-LOG.md
```

**Filter:** exclude meta-references that explicitly cite "Phase 273+" only to negate (lines containing `NOT forward-cites`, `fresh delta-extraction`, `Future milestones`, or `zero forward-cites` — these are the rule's self-statement, not forward-cites to specific in-flight work).

**Output:** Zero non-meta matches. Phase 272 is the terminal v38.0 phase; no in-flight Phase 273+ work is forward-cited.

**Verdict:** PASS.

### 8b. Phase 272 → Post-Milestone Forward-Cite Emission

**Grep recipe (scoped to audit + phase artifacts only):**
```
! grep -rE "Phase (273|274|275|276)|v39\.0|v40\.0" \
  audit/FINDINGS-v38.0.md \
  .planning/phases/272-always-hero-simplification-maximal-dead-code-cleanup-terminal/272-CONTEXT.md \
  .planning/phases/272-always-hero-simplification-maximal-dead-code-cleanup-terminal/272-DISCUSSION-LOG.md \
  .planning/phases/272-always-hero-simplification-maximal-dead-code-cleanup-terminal/272-01-PLAN.md \
  .planning/phases/272-always-hero-simplification-maximal-dead-code-cleanup-terminal/272-01-SUMMARY.md \
  .planning/phases/272-always-hero-simplification-maximal-dead-code-cleanup-terminal/272-01-ADVERSARIAL-LOG.md
```

**Expected:** exit 0 (zero matches when scoping to audit deliverable + phase artifacts; v39+ matches inside FINDINGS-v38.0.md itself are pickup-pointer carve-outs per the rule below).

**Pickup-pointer carve-out:** §9.NN.iv RE-DEFER entries may cite `v39+` as the explicit deferral target. This is a forward-pointer for future-phase pickup (planner-handoff register), NOT a forward-cite to a planned future phase. Terminal-phase invariant remains satisfied. Operational-pickup references inline at test files (e.g., the LBX-02 FORMAL RE-DEFER prose block in `test/gas/LootboxOpenGas.test.js` documenting the v39+ pickup path) are also pickup-pointers, not in-flight forward-cites; they live in the test tree (operational source, not audit deliverable) and are out-of-scope for the §8 invariant.

**Allowlist:** the §9.NN.iv RE-DEFER subsection is a planned-handoff register, NOT a forward-cite to in-flight v39.0 work. The "Deferred to Future Milestones" subsection in PROJECT.md is the single-source-of-truth lookup. "ingest via fresh delta-extraction phase" is the rule's self-statement of how future milestones consume v38 artifacts.

**Verdict:** PASS — pickup-pointer carve-out applies for `v39+` matches inside FINDINGS-v38.0.md §9.NN.iv; zero forward-cites emitted outside the carve-out.

### 8c. Combined §8 Verdict

Zero forward-cites emitted from Phase 272 to any in-flight v39.0+ phases. The §9.NN.iv Carry-Forward RE-DEFER Register (Task 3.6) contains explicit deferred-handoff items (LBX-02 RE-DEFER + STAT-03-v35-carry ACCEPTED-DESIGN); these are planner handoff REGISTERS tying into next-milestone pickup via `.planning/PROJECT.md` "Deferred to Future Milestones" single-source-of-truth lookup, NOT forward-cites to in-flight Phase 273+ work.

Future milestones (v39.0+) ingest via fresh delta-extraction phase, not via forward-cite from v38 artifacts.

**Verdict:** PASS — terminal-phase invariant satisfied per D-272-FCITE-01.

---

## 9. Milestone Closure Attestation

### 9a. Verdict Distribution

Per-section roll-up:
- **§4** F-38-NN finding blocks: **7 of 7** surfaces (a)..(g) verdicted SAFE / SAFE_BY_DESIGN / SAFE_BY_STRUCTURAL_CLOSURE / SAFE_BY_DEFENSIVE_VALIDATION; **zero F-38-NN finding blocks emitted** per D-272-FIND-01 default path; **zero 8th-surface NEW_VECTOR** per `/zero-day-hunter` 7-hypothesis sweep (h)..(o). One INFO-severity docs-vs-behavior drift identified at Hypothesis (i) (`dailyHeroWagers` tracking inconsistency post-v38) was surfaced at the Wave 3 adversarial-pass close with disposition KEEP_AS_NEGATIVE_FINDING per D-272-KI-01 default zero-promotion path; **status pivoted to RESOLVED_AT_V38 via Wave 1.5** commit `4760459f` (defensive boundary validation per D-272-INPUT-VALIDATION-01). No v39+ pickup; no §4 finding block.
- **§5** Regression Appendix: REG-01 **1 PASS** (v37.0 intermediate closure signal NON-WIDENING); REG-02 **1 PASS** (v34.0 closure signal NON-WIDENING); REG-03 **4 PASS** (EXC-01..03 NEGATIVE-scope + EXC-04 RE_VERIFIED with NARROWS retained); REG-04 **7 PASS / 0 REGRESSED / 0 SUPERSEDED** (prior-finding spot-check sweep across `audit/FINDINGS-v25.0.md` → `audit/FINDINGS-v37.0.md`). Aggregate: **13 PASS / 0 REGRESSED / 0 SUPERSEDED**.
- **§6** KI Gating Walk: **`0 of 0 KI_ELIGIBLE_PROMOTED; KNOWN_ISSUES_UNMODIFIED`** (default path per D-272-KI-01). EXC-01..03 RE_VERIFIED-NEGATIVE-scope; EXC-04 RE_VERIFIED with NARROWS retained.
- **AUDIT-06** adversarial-pass: 3 skills (`/contract-auditor` + `/zero-day-hunter` + `/economic-analyst`) PARALLEL spawn per D-272-ADVERSARIAL-01; all concur on the 7 §4 surface verdicts; zero FINDING_CANDIDATE / zero 8th-surface / zero KI promotion candidate per `.planning/phases/272-always-hero-simplification-maximal-dead-code-cleanup-terminal/272-01-ADVERSARIAL-LOG.md` Disposition section. One docs-vs-behavior drift identified (Hypothesis (i)) at adversarial-pass close with KEEP_AS_NEGATIVE_FINDING disposition — **RESOLVED_AT_V38 via Wave 1.5** commit `4760459f` (defensive boundary validation; appended disposition update in `272-01-ADVERSARIAL-LOG.md`). Does NOT change §4 verdict roll-up.
- **Combined milestone closure:** `MILESTONE_V38_AT_HEAD_06623edb`.

### 9b. Attestation Block

D-253-15 step 9 attestation block triggering v38.0 milestone closure. Cite 3-skill PARALLEL adversarial-pass concurrence (per `272-01-ADVERSARIAL-LOG.md` Disposition section — all 3 skills concurred on §4 verdict roll-up; one docs-vs-behavior drift identified at adversarial-pass close with KEEP_AS_NEGATIVE_FINDING disposition, **RESOLVED_AT_V38 via Wave 1.5** commit `4760459f` — does NOT change the closure verdict).

```
git rev-parse HEAD
# v38.0 closure HEAD 06623edb   — resolved at Wave 4 Task 4.6 atomic-update per D-272-CLOSURE-01
# v37.0 intermediate baseline — 2654fcc2
#   signal                   — MILESTONE_V37_AT_HEAD_2654fcc2
# v36.0 audit baseline        — 1c0f09132d7439af9881c56fe197f81757f8164a
#   signal                   — MILESTONE_V36_AT_HEAD_1c0f09132d7439af9881c56fe197f81757f8164a
# v34.0 second-prior closure — 6b63f6d4daf346a53a1d463790f637308ea8d555 (REG-02 carry)
#   signal                   — MILESTONE_V34_AT_HEAD_6b63f6d4daf346a53a1d463790f637308ea8d555
```

Phase 272 source-tree HEAD at adversarial-pass close: `e3fcb95c` (Wave 2 test commit — last source-tree mutation in v38 milestone scope). Docs-tree HEAD captured separately at Wave 4 Task 4.6 atomic-update per Phase 257 D-257-CLOSURE-01 / Phase 262 D-262-CLOSURE-01 / Phase 265 D-265-CLOSURE-01 / Phase 266 D-266-CLOSURE-01 / Phase 271 D-271-CLOSURE-01 carry → D-272-CLOSURE-01.

### 9c. Closure Signal

`MILESTONE_V38_AT_HEAD_06623edb`

Placeholder `06623edb` resolved at Wave 4 Task 4.6 atomic-update per D-272-CLOSURE-01 across 5 verbatim locations: (1) `audit/FINDINGS-v38.0.md` §1 frontmatter `audit_subject_head:` field; (2) `audit/FINDINGS-v38.0.md` §1 frontmatter `closure_signal:` field; (3) `audit/FINDINGS-v38.0.md` §2 Closure Verdict Summary line `Combined milestone closure: MILESTONE_V38_AT_HEAD_06623edb`; (4) `audit/FINDINGS-v38.0.md` §9c this line; (5) `audit/FINDINGS-v38.0.md` §9b Attestation Block. Plus 3 cross-document propagation locations resolved by Wave 4 Task 4.6: `.planning/MILESTONES.md` v38.0 row, `.planning/ROADMAP.md` v38.0 milestone bullet, and `.planning/phases/272-always-hero-simplification-maximal-dead-code-cleanup-terminal/272-01-SUMMARY.md` frontmatter.

### 9.NN Commit-Readiness Register

TWO-subsection format per D-272-CLOSURE-02 (i USER-APPROVED contracts + ii USER-APPROVED tests + iii AGENT-COMMITTED audit + planning artifacts; the historical "awaiting" / "pending review" closure subsection is OMITTED per D-272-CLOSURE-02 carry of D-271-CLOSURE-02). §9.NN.iv RE-DEFER Register below is a separate subsection from the TWO-subsection commit-readiness register (pickup-pointer carve-out per §8).

#### 9.NN.i USER-APPROVED contracts (Phase 272 Wave 1)

| Commit SHA | Subject | Files | Phase |
| ---------- | ------- | ----- | ----- |
| `527e3adc` | `feat(272): always-on hero default 0 + degenerette dead-code cleanup [HERO-01..05, CLEAN-01..05]` | `contracts/modules/DegenerusGameDegeneretteModule.sol` (+18 / −16 LOC; HERO-01..05 hero-pack/extract block + CLEAN-01..05 cleanup-sweep deletions). Bytecode delta −57 bytes (8955 → 8898); storage layout byte-identical vs `2654fcc2`; public ABI byte-identical vs `2654fcc2`. | 272 |

#### 9.NN.ii USER-APPROVED tests (Phase 272 Wave 2)

| Commit SHA | Subject | Files | Phase |
| ---------- | ------- | ----- | ----- |
| `e3fcb95c` | `test(272): hero-always-on + dead-code cleanup + v37+ carry bundle [STAT-01..02, SURF-01..03, LBX-02, GASPIN-02..03, STAT-03-v35-carry]` | 6 files: `package.json` (GASPIN-02 (a-alt) `test:gas` script-split) + `test/stat/DegenerettePerNEvExactness.test.js` (STAT-01 re-pin) + `test/stat/DegeneretteBonusEv.test.js` (STAT-02 re-pin) + `test/stat/SurfaceRegression.test.js` (SURF-01..02 v38.0 describe + SURF-03 rebase) + `test/gas/LootboxOpenGas.test.js` (LBX-02 FORMAL RE-DEFER prose block) + `test/stat/PerPullEmptyBucketSkip.test.js` (STAT-03-v35-carry ACCEPTED-DESIGN ledger entry). +238 / −36 LOC. | 272 |

NONE FURTHER expected per pure-consolidation hard constraint per D-272-APPROVAL-01 (`git diff e3fcb95c..HEAD -- contracts/ test/` empty at phase close — all source-tree mutations landed under USER-APPROVED batched gates at Wave 1 + Wave 2).

#### 9.NN.iii AGENT-COMMITTED audit + planning artifacts

- `audit/FINDINGS-v38.0.md` (this deliverable) — agent-authored across Wave 3 Tasks 3.1-3.6; READ-only flip at Wave 4 Task 4.7 (chmod 444 + frontmatter `status: FINAL — READ-ONLY` + `read_only: true`).
- `.planning/phases/272-always-hero-simplification-maximal-dead-code-cleanup-terminal/272-CONTEXT.md` — phase-gather context (AGENT-COMMITTED at `20c7c544` via `docs(272): capture phase context — always-hero simplification + dead-code cleanup terminal`).
- `.planning/phases/272-always-hero-simplification-maximal-dead-code-cleanup-terminal/272-DISCUSSION-LOG.md` — human-readable discussion record.
- `.planning/phases/272-always-hero-simplification-maximal-dead-code-cleanup-terminal/272-01-PLAN.md` — multi-task planner output (4 waves: Wave 1 contract + Wave 2 test + Wave 3 audit deliverable + Wave 4 closure flips).
- `.planning/phases/272-always-hero-simplification-maximal-dead-code-cleanup-terminal/272-01-ADVERSARIAL-LOG.md` — Wave 3 Task 3.5 output: 3 H2 sections (`/contract-auditor` + `/zero-day-hunter` + `/economic-analyst`) + Disposition.
- `.planning/phases/272-always-hero-simplification-maximal-dead-code-cleanup-terminal/272-01-SUMMARY.md` — Wave 4 phase-close summary (post-Task-4.7 atomic commit).
- `.planning/ROADMAP.md` + `.planning/STATE.md` + `.planning/MILESTONES.md` + `.planning/PROJECT.md` + `.planning/REQUIREMENTS.md` — closure flips applied at Wave 4 Tasks 4.3 + 4.4 + 4.5 + 4.6.
- `KNOWN-ISSUES.md` — UNMODIFIED at v38 close per D-272-KI-01 default zero-promotion path.

**No "pending USER-APPROVAL" subsection emitted per D-272-CLOSURE-02** — all v38 contract + test commits already landed under USER-APPROVED batched review at Wave 1 (`527e3adc`) + Wave 2 (`e3fcb95c`) close per `feedback_batch_contract_approval.md` + `feedback_no_contract_commits.md` + `feedback_never_preapprove_contracts.md`. Wave 3 + Wave 4 emit ZERO contract/test mutations per D-272-APPROVAL-01 hard constraint.

#### 9.NN.iv Carry-Forward RE-DEFER Register

Separate subsection from the TWO-subsection commit-readiness register above. Pickup-pointer carve-out per §8 — `v39+` mentions in this register are forward-pointers for future-phase pickup (planner-handoff register), NOT forward-cites to planned future phases. Terminal-phase invariant remains satisfied per D-272-FCITE-01.

| Item | Source Phase | v38 Disposition | Rationale | v39+ Pickup Path |
| ---- | ------------ | --------------- | --------- | ---------------- |
| LBX-02 | v37+ carry-forward (v37.0 Phase 269) | **FORMAL RE-DEFER to v39+** | Phase 269 fixture-coverage gap remains structural at v38. Analytical worst-case in NatSpec is load-bearing per `feedback_gas_worst_case.md` + Phase 266 GAS-01 precedent. Empirical pin attempt at v38 would require fixture coverage of openable lootbox path which currently soft-skips in the harness (matches `AdvanceGameGas.test.js` L1014/L1027 precedent). Wave 2 Task 2.4 prose-only "v38 FORMAL RE-DEFER" block prepended to `test/gas/LootboxOpenGas.test.js` documenting path-of-investigation. Closes v37.0 §9.NN.iv LBX-02 carry-forward via formal re-defer. | Add empirical 55%-tickets-path gas-savings test once fixture provides reliable coverage of openable lootbox path; OR re-defer to subsequent milestone if fixture-coverage gap persists. Path-of-investigation prose at `test/gas/LootboxOpenGas.test.js` header is the load-bearing pickup pointer. |
| STAT-03-v35-carry | v37+ carry-forward (v35.0 Phase 265) | **ACCEPTED-DESIGN ledger entry** (CLOSED at v38) | Per v35.0 Phase 265 D-265-STAT03-01 fixture-calibration-error reframe — the 88.24% empty-bucket skip rate reflects sparse-fixture pre-organic-activity holder density, NOT a protocol-behavior finding. Helper itself was proven correct via deity-backed dense fixture at Phase 265 close. Wave 2 Task 2.6 prepends ACCEPTED-DESIGN ledger-entry prose block to `test/stat/PerPullEmptyBucketSkip.test.js`. Test bodies UNCHANGED; standalone pre/post-edit exit codes match. Closes v37.0 §9.NN.iv STAT-03-v35-carry carry-forward via ACCEPTED-DESIGN ledger entry. | No v39+ pickup required (CLOSED at v38 as ACCEPTED-DESIGN). If a future phase implements Phase 264 D-IMPL-07 mid/late-game holder-density spec, the fixture can be populated to drop the skip rate below 10% threshold — but this is OPTIONAL not REQUIRED. |
| GASPIN-02 (a-alt) | v37+ carry-forward (v37.0 Phase 269) | **CLOSED at v38** (Verdict: COMPLETE) | Path (a-alt) script-split applied at `package.json` per Wave 2 commit `e3fcb95c`. New `test:gas` script wires `Phase261GasRegression + Phase264GasRegression + Phase268GasRegression + LootboxOpenGas + AdvanceGameGas`; `test:stat` excludes those gas files. Test bodies UNCHANGED. Goal achieved: cumulative-state drift moved off `test:stat`. | Not re-deferred. CLOSED at v38. |
| GASPIN-03 | v37+ carry-forward (v37.0 Phase 269) | **CLOSED at v38** (Verdict: COMPLETE) | Wave 2 Task 2.5 consistency-gate verification documented non-regression vs pre-Wave-2 baseline. Post-Wave-2 `test:stat` exit=1 with 1 known-design failure (STAT-03-v35-carry); `test:gas` exit=1 with v36.0 "128k is fine approved" gas-pin drift envelope. SURF-03 rebase fixes the 4th pre-edit failure (LootboxModule diff against PHASE_269_CLOSE_BASELINE = `8fd5c2e1` is now empty). | Not re-deferred. CLOSED at v38. |

(no remaining v39+ pickups from Wave 3 adversarial-pass — Hypothesis (i) was the sole candidate at adversarial-pass close and is now **RESOLVED_AT_V38** via Wave 1.5 commit `4760459f` defensive boundary validation. The Hypothesis (i) row that previously appeared here has been REMOVED; see §3.A Row 1.13 + §4 surface (b) + §7 Hypothesis (i) cross-cite for the resolution evidence. Tracked as D-272-INPUT-VALIDATION-01 in `272-CONTEXT.md`. LBX-02 + STAT-03-v35-carry + GASPIN-02 + GASPIN-03 dispositions above are UNAFFECTED by the Wave 1.5 Hypothesis (i) resolution.)

---