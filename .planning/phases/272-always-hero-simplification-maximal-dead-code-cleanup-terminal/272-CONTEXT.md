# Phase 272: Always-Hero Simplification + Maximal Dead-Code Cleanup (Terminal) — Context

**Gathered:** 2026-05-11
**Status:** Ready for planning (4 user-locked decisions captured below; 3 items deferred to planner discretion with enumerated option set per REQUIREMENTS.md)

<domain>
## Phase Boundary

Single-phase v38.0 milestone-closure patch mirroring v36.0 Phase 266 precedent + v37.0 Phase 271 terminal-phase shape. Three-wave structure: Wave 1 contract commits (always-hero + Degenerette-module-only dead-code cleanup, single batched USER-APPROVED) → Wave 2 test commits (re-validation + v37+ carry bundle, single batched USER-APPROVED) → Waves 3+ audit deliverable + adversarial pass + ROADMAP/STATE/MILESTONES/PROJECT/REQUIREMENTS flips (AGENT-COMMITTED atomic-per-task).

**Audit baseline:** `MILESTONE_V37_AT_HEAD_2654fcc2` (closure signal carry-forward from `audit/FINDINGS-v37.0.md` §9c).

**Audit subject HEAD at phase-start:** `2654fcc2` (contract tree). Working tree at conversation start is `95b0cfc3` (docs-only chain since `2654fcc2`: `f47cc5e8` chore + `007ab188` archive + `b0a6e65d` v37 audit + `7aea5dc1` post-close tracking + `95b0cfc3` v38.0 milestone open). Contract tree byte-identical to `2654fcc2` through `95b0cfc3`.

**Closure target:** `audit/FINDINGS-v38.0.md` (9 sections, FINAL READ-only at v38.0 closure HEAD); closure signal `MILESTONE_V38_AT_HEAD_<sha>` emitted in §9c.

**30 v38.0 requirements (per REQUIREMENTS.md, all mapped to Phase 272):**

- **HERO-01..05** — Always-on hero semantics in `contracts/modules/DegenerusGameDegeneretteModule.sol` (5 reqs).
- **CLEAN-01..06** — Dead-code cleanup sweep (NARROWED at v38: Degenerette-module-only per D-272-CLEAN-SCOPE-01 below; 5 cleanup reqs + 1 batched-commit req).
- **STAT-01..02** — Hero-always-on statistical re-validation (DegeneretteBonusEv + DegenerettePerNEvExactness re-pins).
- **SURF-01..03** — Cross-surface preservation + LBX-03 re-anchor + v37.0 SURF-03 re-baseline carry.
- **LBX-02** — v37+ carry-forward: empirical 55%-tickets-path gas-savings pin (attempt OR formal re-defer).
- **GASPIN-02..03** — v37+ carry-forward: D-269-STAB-01 retry options (a)/(a-alt)/(c) + clean `npm run test:stat` verification.
- **STAT-03-v35-carry** — v37+ carry-forward: `PerPullEmptyBucketSkip.test.js` fixture retune (populate OR ACCEPTED-DESIGN).
- **AUDIT-01..06** — Delta audit + findings consolidation + 3-skill PARALLEL adversarial pass.
- **REG-01..04** — Regression checks (v37 + v34 closure-signal non-widening + KI envelope + prior-finding spot-check).

</domain>

<spec_lock>
## Locked Requirements (carry-forward from v36.0 Phase 266 → v37.0 Phase 271 chain)

These are NOT gray areas; they are inheritances from the prior milestone-closure chain. Do not re-discuss.

- **Phase shape**: Single phase (Phase 272 only), single multi-task plan, multi-wave structure per v36.0 Phase 266 precedent.
- **Deliverable**: Single canonical `audit/FINDINGS-v38.0.md` (no `audit/v38-*.md` per-AUDIT-NN working files) — D-271-FILES-01 carry → **D-272-FILES-01**.
- **§9 closure attestation**: TWO-subsection format (USER-APPROVED contracts + USER-APPROVED tests + AGENT-COMMITTED audit artifacts; NO §9.NN.iv awaiting-approval subsection) — D-271-CLOSURE-02 carry → **D-272-CLOSURE-02**.
- **Closure signal SHA**: `git rev-parse HEAD` at audit-pass-close commit; mutation-inclusive HEAD since Phase 272 introduces 2 USER-APPROVED batched commits — D-271-CLOSURE-01 carry → **D-272-CLOSURE-01**.
- **Forward-cite zero-emission**: Terminal-phase invariant. §8 grep-recipe verifies zero forward-cite emission across phase artifacts (no v39+ cites) — D-271-FCITE-01 carry → **D-272-FCITE-01**.
- **Adversarial pass**: 3-skill PARALLEL on finished §4 draft via single message: `/contract-auditor` + `/zero-day-hunter` + `/economic-analyst`. `/degen-skeptic` OUT of scope. Logged in `272-01-ADVERSARIAL-LOG.md` with 3 H2 sections + Disposition note — D-271-ADVERSARIAL-01/02 carry → **D-272-ADVERSARIAL-01**.
- **KNOWN-ISSUES.md**: Default zero-promotion path. Deviation requires explicit user disposition + adversarial-pass FINDING_CANDIDATE — D-271-KI-01 carry → **D-272-KI-01**.
- **Severity rubric**: D-08 5-bucket rubric, unchanged — D-271-SEV-01 carry → **D-272-SEV-01**.
- **Per-commit user approval discipline**: 2 USER-APPROVED batched commits (Wave 1 contracts + Wave 2 tests); all `.planning/`/audit/ writes AGENT-COMMITTED atomic-per-task. Per `feedback_no_contract_commits.md` + `feedback_batch_contract_approval.md` + `feedback_never_preapprove_contracts.md`. Final review-before-push per `feedback_manual_review_before_push.md` → **D-272-APPROVAL-01**.
- **HERO-02 bit allocation**: FT_HERO_SHIFT stays 3 bits; enabled bit becomes vestigial (always = 1 post-v38; freed bit reserved for future feature). Storage layout byte-identical at v38 close vs `2654fcc2`. NO collapse to 2 bits — locked by HERO-02 to prevent storage-layout shift.
- **Public ABI byte-identical**: `placeDegeneretteBet(..., uint8 heroQuadrant)` signature UNCHANGED. `0xFF` and any `>= 4` input still accepted but normalized to 0 internally per HERO-01.
- **Behavior change posture**: ACCEPTED. Hero EV-neutrality preserved per Fraction-exact analytical audit (`/tmp/degenerette_ev_audit.py` from v37 close). Player-side opt-out removed (mildly variance-increasing for risk-averse players, no EV change).

</spec_lock>

<decisions>
## User-Locked Decisions (this discussion, 2026-05-11)

### D-272-CLEAN-SCOPE-01 — CLEAN sweep scope NARROWED to Degenerette module only

**Decision:** The `contracts/` "maximal dead-code cleanup sweep" wording in ROADMAP.md + REQUIREMENTS.md CLEAN-01..05 is **NARROWED** at v38: cleanup applies ONLY to `contracts/modules/DegenerusGameDegeneretteModule.sol`. No other modules, no libraries, no top-level contracts (`DegenerusGame.sol`, `DegenerusAffiliate.sol`, `DegenerusVault.sol`, etc.) are scanned or modified at v38.

**Rationale:** Phase 272's load-bearing payload is the always-hero edit (HERO-01..05); the cleanup scope is bounded to what HERO-01..05 directly orphans (e.g., `MASK_3`, the `[0]=enabled, [1..2]=quadrant` NatSpec comment at L321, any other Degenerette-module internals made dead by the HERO edit). Broader cleanup across 14,663 LOC of non-Degenerette surface = out of scope at v38.

**Forward-looking:** Any non-Degenerette cleanup candidates discovered during the manual grep-walk are NOT applied at v38; they may be captured as v39+ backlog seeds in `.planning/notes/` if surfaced.

**Documentation deviation note:** REQUIREMENTS.md CLEAN-01 currently reads "`/gas-audit` orchestrator runs across all `contracts/` files." This is **SOFTENED** at v38 per this decision. AUDIT-01 §3.A delta-surface table must explicitly note the scope narrowing as a v38-design choice (not a coverage gap).

### D-272-CLEAN-DISCOVERY-01 — Manual grep-walk by planner; no /gas-audit orchestrator spawn

**Decision:** Cleanup-candidate discovery uses **planner manual grep-walk** within `DegenerusGameDegeneretteModule.sol`. The `/gas-audit` orchestrator (`/gas-scavenger` + `/gas-skeptic`) is **NOT** spawned at v38.

**Rationale:** For a 1,158-LOC single module with ~7 LOC of HERO edits, the orchestrator overhead exceeds the surface area. Manual grep is faster, more deterministic, and easier to review. Each candidate still gets a per-item design-intent trace per `feedback_design_intent_before_deletion.md` (proactively, inline in the plan's removal-task block — see D-272-DESIGN-INTENT-01 below).

**Documentation deviation note:** REQUIREMENTS.md CLEAN-01 explicitly names `/gas-audit` orchestrator + `/gas-scavenger` + `/gas-skeptic`. This is **SOFTENED** at v38 per this decision. AUDIT-02 §4 surface (c) attestation prose must cite manual grep-walk as the discovery method, NOT the orchestrator.

**Grep recipe (planner uses these):**
- Unused constants: `grep -n "private constant" contracts/modules/DegenerusGameDegeneretteModule.sol`, then for each constant grep callsites in the same file; zero callsites at HEAD = candidate.
- Stale comments referencing pre-v38 design: `grep -nE "enabled|heroEnabled|opt-out|opt out" contracts/modules/DegenerusGameDegeneretteModule.sol`
- Redundant safety guards: scan for `require`/`revert` whose predicate is statically provable from caller-clamp or upstream invariant; trace inline.

### D-272-COMMIT-SHAPE-01 — Single combined Wave 1 contract commit

**Decision:** **One** USER-APPROVED batched contract commit covers both HERO-01..05 and CLEAN-01..05:

```
feat(272): always-on hero default 0 + degenerette dead-code cleanup [HERO-01..05, CLEAN-01..05]
```

**Rationale:** Mirrors v36.0 Phase 266 batched-commit precedent. With the cleanup scope narrowed to Degenerette module + likely-small candidate count (MASK_3 + L321 NatSpec rewrite + handful of others), the diff fits cleanly under one approval gate. Bytecode shrink delta reported in commit message.

**Commit message body must include:**
- Full per-requirement attribution (HERO-01..05 + each CLEAN-NN applied; each CLEAN candidate with file-path:line range + type + 1-line design-intent trace).
- Bytecode delta (pre/post `npx hardhat compile` size measurement).
- Gas-per-spin delta (~30 gas saved target per HERO-01..05; cleanup additions if any).
- Storage-layout grep proof: `storage` keyword count + slot allocation byte-identical vs `2654fcc2`.

### D-272-DESIGN-INTENT-01 — Always-hero removal design-intent trace (inline + audit-deliverable)

**Decision:** Per `feedback_design_intent_before_deletion.md`, the always-hero removal carries the following inline trace, surfaced (a) in the Wave 1 contract commit message, (b) in `272-01-PLAN.md` Task-1 description, (c) in `audit/FINDINGS-v38.0.md` §3.A delta-surface table HERO-01..05 row(s), and (d) in §4 surface attestation prose:

1. **Original design intent of `heroEnabled` opt-out.** Allowed variance-averse players to skip hero boost/penalty multiplier (`payout × (HERO_BOOST | HERO_PENALTY)`) and lock payout at basePayout. EV-neutral by construction (per-N HERO_BOOST tables calibrated so `P(hero|M,N) × boost + (1−P) × HERO_PENALTY = HERO_SCALE`). Variance-reduction only; no expectation change.
2. **Actor walk-through across (player risk-profile × game state).**
   - EV-rational players (risk-neutral/risk-loving): zero effect — EV invariant by construction.
   - Variance-averse players: lose variance-reduction tool. Worst-case downside per spin = `HERO_PENALTY × basePayout = 0.95 × basePayout`. Best-case upside = boost-magnitude × basePayout (per-N table, ~1.18×–2.50× at M=2..7). Bounded variance increase; zero EV change.
   - Whales / casual / admin / governance: zero differential impact (shared storage slot, RNG word, payout function).
   - Adversarial: pre-v38 `heroQuadrant = 0xFF` could dodge unlucky hero-penalty hit but EV-neutral, so no EV gain. Post-v38: cannot dodge; variance-neutral on expectation.
3. **Forward-looking risk.** 3-bit FT_HERO_SHIFT allocation preserved (vestigial enabled-bit always = 1); re-introduction is one-line revert. Storage layout byte-identical at v38 vs `2654fcc2` (SURF-01 verifies).
4. **Why now (pre-launch).** UI simplification (no hero-opt-out toggle), ~30-byte bytecode shrink, ~30 gas/spin saved, no EV impact, bounded acceptable variance impact per user disposition (degen-game context).

### D-272-NATSPEC-DISCIPLINE-01 — HERO-04 NatSpec discipline (no history in comments)

**Decision:** Per `feedback_no_history_in_comments.md`, all HERO-04 NatSpec rewrites describe what IS at v38 close. Strictly no comparative/historical language ("previously was opt-out", "v37 → v38 change", "removed the heroEnabled flag", "reduced from 3 to 2 bits", etc.).

**Specific touchpoints:**
- L321 `FT_HERO_SHIFT` comment — currently `"3 bits: [0]=enabled, [1..2]=quadrant"`. Rewrite to describe current allocation only (e.g., `"3 bits: [0]=reserved, [1..2]=quadrant (always-on hero)"` or planner's variant). Vestigial-bit phrasing must NOT reference what bit 0 USED to mean.
- `_packFullTicketBet` NatSpec — describes hero as always-on with quadrant 0 default for `heroQuadrant >= 4` input.
- `_fullTicketPayout` NatSpec — describes hero applying for `M ∈ {2..7}`.
- `_applyHeroMultiplier` NatSpec — UNCHANGED at body level (math identical).

### D-272-INPUT-VALIDATION-01 — HERO-05 spec_lock revised; input validation added (Wave 1.5)

**Decision:** Public ABI `placeDegeneretteBet(..., uint8 heroQuadrant)` validates `heroQuadrant < 4` at entry; inputs `>= 4` (including `0xFF`) revert with `InvalidBet`. Reverses the v37+ "0xFF = no hero" sentinel semantic at v38 close.

**Rationale:** Wave 3 3-skill PARALLEL adversarial pass surfaced Hypothesis (i) — a docs-vs-behavior drift where `0xFF` input was pack-normalized to quadrant 0 (HERO-01) but NOT credited to `dailyHeroWagers[day][0]` (L484 gate used raw input). INFO-severity; KEEP_AS_NEGATIVE_FINDING at adversarial-pass; user disposition pivoted to defensive boundary validation as the v38 remediation. Cleaner than the silent-normalize approach: invalid input is rejected rather than coerced.

**Frontend contract:** Frontend MUST send valid 0..3 (default 0 if user does not pick). 0xFF sentinel no longer accepted.

**Supersedes:**
- `<spec_lock>` "Public ABI byte-identical": amended; signature unchanged but semantics shift from "accept + normalize" to "reject invalid input". Public ABI selector + parameter types byte-identical; only error-condition expansion.
- ROADMAP success criterion #2 wording "still accepted but normalized to 0 internally" — superseded by D-272-INPUT-VALIDATION-01 (revert on >= 4). Wave 4 closure flip will reflect this revision.
- REQUIREMENTS.md HERO-05 prose — superseded (Wave 4 closure flip).

**Commit:** `4760459f` (Wave 1.5 USER-APPROVED batched commit covering `contracts/modules/DegenerusGameDegeneretteModule.sol` + `test/fuzz/handlers/DegeneretteHandler.sol`).

**Hypothesis (i) disposition update:** Status pivoted from KEEP_AS_NEGATIVE_FINDING (at Wave 3 adversarial pass, 2026-05-11) to RESOLVED_AT_V38 (post Wave 1.5, 2026-05-11). The v39+ backlog seed candidate at `audit/FINDINGS-v38.0.md` §9.NN.iv is removed (no longer carry-forward).

</decisions>

<deferred_to_planner>
## Deferred to Planner Discretion (option set locked in REQUIREMENTS.md; planner picks at plan-phase)

These were presented as gray areas during this discussion but user explicitly opted to defer:

### GASPIN-02 path (REQUIREMENTS.md GASPIN-02)

Three enumerated options:
- **(a)** Refined `hardhat_reset` sequencing retry — Phase 269 D-269-STAB-01 tried (b) `hardhat_reset` + `loadFixture` and it FAILED structurally with side-effect regressions. (a) is a stricter sequencing variant.
- **(a-alt)** Dedicated `npm run test:gas` script splitting Phase261GasRegression + Phase264GasRegression off `test:stat` via separate mocha config.
- **(c)** Widened tolerance ceiling — last resort; preserves v36.0 "128k is fine approved" acceptance but as documented configurable tolerance. If chosen, the new tolerance is documented as v38 ACCEPTED-TOLERANCE per `feedback_no_history_in_comments.md` discipline.

**Planner picks one and documents in `272-01-PLAN.md` Task-N with rationale.** Goal: clean `npm run test:stat` start-to-finish in CI-equivalent fresh-checkout with zero flaky failures.

### LBX-02 attempt vs re-defer (REQUIREMENTS.md LBX-02)

Two paths:
- **Attempt empirical pin** — add `it("v37.0 LBX-01 saves 20-50 gas on 55%-tickets-path")` describe block in `test/gas/LootboxOpenGas.test.js`; construct openable-lootbox fixture (Phase 266 GAS-01 precedent if fixture-coverage gap was structural); measure gas pre/post LBX-01 hypothetically or against pinned baseline.
- **Formal re-defer to v39+** — document path-of-investigation prose inline at the test fixture or in `272-01-PLAN.md` (per Phase 266 GAS-01 `feedback_gas_worst_case.md` precedent: analytical worst-case load-bearing). Closes v37.0 §9.NN.iv carry-forward register by formal re-defer.

**Planner picks one. If attempt fails structurally, planner falls back to formal re-defer with path-of-investigation prose.**

### STAT-03-v35-carry resolution (REQUIREMENTS.md STAT-03-v35-carry)

Two paths:
- **Populate dense fixture** — populate the deity-backed dense fixture in `test/stat/PerPullEmptyBucketSkip.test.js` so empty-bucket skip rate drops below 10% threshold.
- **ACCEPTED-DESIGN ledger entry** — document the 88.24% empty-bucket skip rate in current sparse fixture as v38 ACCEPTED-DESIGN, referencing the v35.0 Phase 265 D-265-STAT03-01 fixture-calibration-error reframe (skip rate is fixture-density artifact, NOT a protocol-behavior finding).

**Planner picks one. Default expectation per v35.0 reframe carry: ACCEPTED-DESIGN ledger entry. Populate-dense-fixture is the variant if planner determines fixture-density retune is mechanically feasible in v38 scope.**

</deferred_to_planner>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 272 Anchors

- `.planning/ROADMAP.md` (lines 21, 26, 30-51) — Phase 272 success criteria + plan list; audit baseline `MILESTONE_V37_AT_HEAD_2654fcc2`; v37+ carry-forward picks.
- `.planning/REQUIREMENTS.md` — 30 v38.0 requirements (5 HERO + 6 CLEAN + 2 STAT + 3 SURF + 1 LBX + 2 GASPIN + 1 PPL + 6 AUDIT + 4 REG); all mapped to Phase 272.
- `.planning/STATE.md` — milestone v38.0 status; v37.0 closure signal `MILESTONE_V37_AT_HEAD_2654fcc2` last-shipped reference; Phase 272 active.

### v36.0 Phase 266 + v37.0 Phase 271 Precedent (deliverable shape + commit discipline)

- `audit/FINDINGS-v37.0.md` — v37.0 9-section deliverable; closure signal `MILESTONE_V37_AT_HEAD_2654fcc2`; 8-of-8 §4 surfaces SAFE_*; 3-skill PARALLEL adversarial-pass output; §9.NN three-subsection format. **Primary template for Phase 272 deliverable shape.**
- `audit/FINDINGS-v36.0.md` — v36.0 single-phase patch deliverable; secondary template precedent.
- `.planning/milestones/v36.0-phases/266-lootbox-entropy-refactor/266-CONTEXT.md` — Phase 266 carry-forward decision chain (D-266-FILES-01 / D-266-ADVERSARIAL-01..03 / D-266-PLAN-01 / D-266-CLOSURE-01..02 / D-266-FCITE-01 / D-266-SEV-01 / D-266-APPROVAL-01..02). **Primary template for Phase 272 decision shape.**
- `.planning/milestones/v36.0-phases/266-lootbox-entropy-refactor/266-01-PLAN.md` — Phase 266 single-plan multi-task atomic-commit ordering precedent.
- `.planning/milestones/v36.0-phases/266-lootbox-entropy-refactor/266-01-ADVERSARIAL-LOG.md` — adversarial-pass log format precedent (2-skill v36; Phase 272 extends to 3-skill PARALLEL).

### Live Contract State (Phase 272 mutation subject — HEAD `2654fcc2`)

- `contracts/modules/DegenerusGameDegeneretteModule.sol` — the **only** contract file mutated at v38 (per D-272-CLEAN-SCOPE-01). Key surface:
  - L321 `FT_HERO_SHIFT = 237; // 3 bits: [0]=enabled, [1..2]=quadrant` — comment rewrite per HERO-04 + D-272-NATSPEC-DISCIPLINE-01.
  - L347 `MASK_3 = 0x7` — only callsite at L592 (deleted by HERO-02); MASK_3 itself becomes a CLEAN-02 candidate.
  - L578-594 `_resolveFullTicketBet` — HERO-02 edit: replace `heroBits` extraction + `heroEnabled` local with direct `heroQuadrant = uint8((packed >> (FT_HERO_SHIFT + 1)) & MASK_2)`.
  - L640-650 `_fullTicketPayout` callsite — HERO-03 edit: drop `heroEnabled` argument.
  - L823-847 `_packFullTicketBet` — HERO-01 edit: `effectiveQuadrant = heroQuadrant < 4 ? heroQuadrant : 0; packed |= (uint256(1) | (uint256(effectiveQuadrant) << 1)) << FT_HERO_SHIFT;` (unconditional set; no `if` guard).
  - L944-994 `_fullTicketPayout` — HERO-03 edit: drop `bool heroEnabled` parameter (signature change); resolve-time guard simplifies from `if (heroEnabled && matches >= 2 && matches < 8)` to `if (matches >= 2 && matches < 8)`.
  - L1007+ `_applyHeroMultiplier` — UNCHANGED at body level (math identical).
- `contracts/modules/DegenerusGameLootboxModule.sol` — SURF-02 byte-identity verification target; LBX-03 anchor at v38 HEAD (4 hash2/bit-slice callsites).
- `contracts/libraries/EntropyLib.sol` — SURF-01 byte-identity verification target (ENT-04 v36.0 carry).
- `contracts/DegenerusTraitUtils.sol` — SURF-01 byte-identity verification target (Mint + Jackpot + Degenerette producer paths UNTOUCHED at v38).
- `contracts/modules/DegenerusGameJackpotModule.sol` — SURF-01 byte-identity verification target (gold-solo + BAF jackpot UNTOUCHED).
- `contracts/modules/DegenerusGameMintModule.sol` — SURF-01 byte-identity verification target (no v38 mutations).

### Test Surfaces

- `test/stat/DegeneretteBonusEv.test.js` — STAT-03 re-pin under always-on hero (drop hero-off baseline run; EV-neutrality formula UNCHANGED). Hero references at L207-302 + L460+ flagged for test-side `heroEnabled` removal (mirror contract-side HERO-03 signature change).
- `test/stat/DegenerettePerNEvExactness.test.js` — STAT-01 re-pin under always-on hero. Hero references at L255-293 + L430 flagged for `heroEnabled` removal.
- `test/stat/SurfaceRegression.test.js` — SURF-01..03 v38.0 describe extension. SURF-03 re-baseline from `V36_BASELINE` → `PHASE_269_CLOSE_BASELINE = "8fd5c2e1..."` (post-LBX-01 HEAD) per v37+ carry.
- `test/gas/LootboxOpenGas.test.js` — LBX-02 empirical pin attempt OR formal re-defer (deferred to planner).
- `test/stat/PerPullEmptyBucketSkip.test.js` — STAT-03-v35-carry fixture retune (deferred to planner).
- `test/gas/Phase261GasRegression.test.js` + `test/gas/Phase264GasRegression.test.js` — GASPIN-02/03 D-269-STAB-01 retry surfaces (deferred to planner).

### Memory / Feedback Governing This Phase

- `feedback_no_contract_commits.md` — explicit per-commit user approval for `contracts/` + `test/` changes. Phase 272 has 1 batched contract commit + 1 batched test commit, both USER-APPROVED.
- `feedback_batch_contract_approval.md` — batch all phase contract edits, present one diff at end. D-272-COMMIT-SHAPE-01 combines HERO + CLEAN into one batched commit.
- `feedback_never_preapprove_contracts.md` — orchestrator/agent must NOT pre-approve any contract change.
- `feedback_no_history_in_comments.md` — D-272-NATSPEC-DISCIPLINE-01. All NatSpec describes what IS at v38; zero comparative/historical language.
- `feedback_design_intent_before_deletion.md` — D-272-DESIGN-INTENT-01 + each CLEAN-NN candidate carries inline trace before deletion shape is presented.
- `feedback_no_dead_guards.md` — CLEAN-05 removals each preserve safety property via upstream enforcement (proof inline in commit message or NatSpec).
- `feedback_wait_for_approval.md` — adversarial-pass disagreement-disposition rule + contract-diff approval gate.
- `feedback_manual_review_before_push.md` — final user-review gate before `git push`. Agent does NOT push.
- `feedback_rng_backward_trace.md` — REG-03 EXC-04 RE_VERIFIED uses backward-trace methodology; EntropyLib byte-identical at v38 HEAD preserves BAF-jackpot-only NARROWS scope.
- `feedback_rng_commitment_window.md` — Phase 272 has zero RNG-path mutation, so commitment-window check is a degenerate PASS at v38; AUDIT-02 surface attestation can be 1-line.
- `feedback_gas_worst_case.md` — LBX-02 path-of-investigation prose (if formal re-defer chosen) per Phase 266 GAS-01 precedent.
- `feedback_skip_research_test_phases.md` — single-phase patch with locked decisions; skip research-agent dispatch (this CONTEXT.md captures all locked decisions inline).

### Active KI Envelope

- `KNOWN-ISSUES.md` — current state at HEAD `2654fcc2` (EntropyLib XOR-shift entry NARROWS to BAF-jackpot-only scope at v36.0 close; UNMODIFIED at v37.0 close). At v38: EXC-04 RE_VERIFIED with NARROWS retained (EntropyLib byte-identical at v38 HEAD). EXC-01..03 RE_VERIFIED NEGATIVE-scope at v38 (Phase 272 has zero affiliate-roll / AdvanceModule / gameover-RNG-substitution interaction).

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- **9-section template prose** — copy structural skeleton from `audit/FINDINGS-v37.0.md` §1-§9 (most recent precedent). Substitute v37 → v38 milestone identifiers, v37 → v38 closure-signal SHAs, v37 → v38 phase IDs.
- **§4 row format** — copy from v37.0 §4 (8-surface a-h). Adapt for v38 surfaces: (a) hero always-on EV-neutrality preserved across (M, N); (b) hero quadrant 0 default does NOT create payout-bias for players who omit heroQuadrant; (c) each cleanup-sweep removal preserves the invariant the removed code claimed to guard; (d) storage layout byte-identical; (e) public ABI byte-identical. Likely 5 surfaces total (versus v37's 8).
- **§5 regression appendix** — copy from v37.0 §5a-d. v38 REG-01 covers v37 closure-signal carry-forward + REG-02 covers v34 carry-forward + REG-04 prior-finding spot-check across audit/FINDINGS-v25..v37.0.
- **§6 KI gating walk** — copy from v37.0 §6a-c. EXC-04 RE_VERIFIED NARROWS-retained row in §6b; §6c verdict default `0 of 0 KI_ELIGIBLE_PROMOTED; KNOWN_ISSUES_UNMODIFIED` per D-272-KI-01.
- **§9 closure-attestation TWO-subsection format** — copy from v37.0 §9 per D-272-CLOSURE-02.
- **Closure-signal emission paragraph** — copy from v37.0 §9c; substitute `MILESTONE_V37` → `MILESTONE_V38` and HEAD SHA.
- **3-skill adversarial-pass spawn pattern** — copy from v37.0 Phase 271 (parallel spawn via single message: `/contract-auditor` + `/zero-day-hunter` + `/economic-analyst`); v38 uses identical pattern.
- **STAT test JS helpers** — `jsApplyHeroMultiplier` + `jsFullTicketPayout` already defined in `DegeneretteBonusEv.test.js` (L207-302) and `DegenerettePerNEvExactness.test.js` (L255-293); STAT-01/02 re-validation drops the `heroEnabled` parameter from the JS mirror functions (one-line edit each) + drops the `false` baseline run in STAT-03 describe blocks.

### Established Patterns

- **Single-phase patch shape** — v36.0 Phase 266 precedent. Phase 272 inherits: contract + test + audit + closure flips all in one phase, one multi-task plan.
- **Atomic-commit per task** — v33/v34/v35/v36/v37 single-plan multi-task pattern. Phase 272 inherits.
- **Adversarial-pass logging** — v33-v37 wrote `{padded_phase}-01-ADVERSARIAL-LOG.md`. Phase 272 mirrors via `272-01-ADVERSARIAL-LOG.md` with 3 H2 sections (one per skill).
- **Forward-cite zero-emission** — terminal-phase invariant. §8 grep-recipe verifies zero forward-cite emission across phase artifacts (no v39+ cites).
- **Manual grep-walk over /gas-audit orchestrator** — D-272-CLEAN-DISCOVERY-01 new precedent for narrow-scope cleanup. Future phases with narrow cleanup scope may inherit.

### Integration Points

- **`audit/FINDINGS-v38.0.md`** — sole canonical deliverable (single-file per D-272-FILES-01). Lives in `audit/` directory alongside FINDINGS-v25.0..v37.0.
- **`KNOWN-ISSUES.md`** — UNMODIFIED at v38 per D-272-KI-01 default zero-promotion (unless adversarial pass surfaces FINDING_CANDIDATE — then user disposition required).
- **`ROADMAP.md`** — closure-signal emission paragraph updated; v38.0 section flipped to COMPLETE; closure-signal `MILESTONE_V38_AT_HEAD_<sha>` recorded.
- **`MILESTONES.md`** — v38.0 entry prepended to top with closure-signal recorded; v37.0 demoted.
- **`STATE.md`** — milestone v38.0 marked closed; Last Shipped Milestone updated; v37.0 demoted to Prior Shipped Milestone.
- **`PROJECT.md`** — v38.0 accumulated-context entry appended.
- **`REQUIREMENTS.md`** — 30/30 Phase 272 requirements marked complete (or formally re-deferred per planner discretion for LBX-02 / GASPIN-02 / STAT-03-v35-carry).
- **`.planning/phases/272-always-hero-simplification-maximal-dead-code-cleanup-terminal/`** — phase artifacts: `272-CONTEXT.md` (this file), `272-DISCUSSION-LOG.md` (human-readable discussion record), `272-01-PLAN.md` (planner output), `272-01-SUMMARY.md` (executor output), `272-01-ADVERSARIAL-LOG.md` (executor output).

</code_context>

<specifics>
## Specific Ideas

### HERO-04 NatSpec rewrite examples (planner refines)

**L321 `FT_HERO_SHIFT` comment — current:**
```solidity
uint256 private constant FT_HERO_SHIFT = 237; // 3 bits: [0]=enabled, [1..2]=quadrant
```

**Proposed v38 rewrite (describes what IS, no history):**
```solidity
uint256 private constant FT_HERO_SHIFT = 237; // 3 bits: [0]=reserved, [1..2]=quadrant (always-on hero)
```

**`_packFullTicketBet` NatSpec — proposed v38 rewrite (sample; planner refines):**
```solidity
/// @dev Packs a Full Ticket bet for storage. Hero quadrant is always-on; inputs
///      with `heroQuadrant >= 4` (including 0xFF) are normalized to quadrant 0
///      (top-left). The reserved bit at FT_HERO_SHIFT is always set; the 2-bit
///      quadrant field at FT_HERO_SHIFT + 1 encodes the selected quadrant.
```

**`_fullTicketPayout` NatSpec — proposed v38 rewrite (sample; planner refines):**
```solidity
/// @dev Calculates Full Ticket payout based on matches and activity score ROI.
///      Hero multiplier applies for M ∈ {2..7} (per-N HERO_BOOST table on
///      symbol-axis match in the hero quadrant; HERO_PENALTY otherwise).
///      Hero EV-neutrality preserved across all (M, N) under the always-on
///      hero schedule.
```

### Likely CLEAN-02 / CLEAN-04 candidates (planner verifies via grep)

- `MASK_3` (L347): only callsite at L592 — deleted by HERO-02. Verify no other-file callsites: `grep -rn "MASK_3" contracts/` confirms scope.
- L592 `heroBits` extraction (3-line block + 2 local vars `heroEnabled` + intermediate `heroQuadrant` derivation) — replaced by direct quadrant extract per HERO-02.
- L984 guard `if (heroEnabled && matches >= 2 && matches < 8)` — `heroEnabled` arm removed.
- L944-953 `_fullTicketPayout` parameter list `bool heroEnabled` — removed; callsite at L640+ drops the `heroEnabled` argument.
- L948-953 NatSpec `@param heroEnabled` line — removed.
- L367 `@param heroQuadrant Hero quadrant (0-3) for payout boost, or 0xFF for no hero.` — rewrite to `Hero quadrant (0-3) for payout boost. Inputs >= 4 (including 0xFF) normalize to 0.`

### Adversarial-pass surface candidates for §4 (planner finalizes)

Likely 5 surfaces at v38 (down from v37's 8 — narrower phase scope):

- **(a) Hero always-on EV-neutrality preserved across (M, N).** Re-cite Fraction-exact analytical audit; STAT-01/02 empirical re-pins serve as expected SAFE_BY_DESIGN evidence.
- **(b) Hero quadrant 0 default does not create payout-bias for players who omit heroQuadrant.** Player passing `0xFF` lands in quadrant 0 (top-left); quadrant choice itself does not change EV under EV-neutral hero design — verify symbol distribution across 4 quadrants is uniform under the v34 trait producer.
- **(c) Each cleanup-sweep removal preserves the invariant it claimed to guard.** Per-item design-intent trace inline per D-272-DESIGN-INTENT-01 + `feedback_design_intent_before_deletion.md`.
- **(d) Storage layout byte-identical at v38 vs `2654fcc2`.** Grep-proof: same storage-slot count + same packing order.
- **(e) Public ABI byte-identical.** `placeDegeneretteBet(..., uint8 heroQuadrant)` signature unchanged; `0xFF` + `>= 4` input still accepted (normalized).

Additional candidates planner evaluates:
- **(f) Variance impact bound on risk-averse subset.** Worst-case downside per spin = 0.95 × basePayout; cite per-N HERO_PENALTY constancy.
- **(g) `npm run test:stat` clean run at v38 close** — covers GASPIN-03 verification.

</specifics>

<deferred>
## Deferred Ideas

### Maximal cleanup sweep across non-Degenerette `contracts/`

ROADMAP.md + REQUIREMENTS.md CLEAN-01 originally scoped a "maximal cleanup sweep" across modules + libraries + main contract (14,663 LOC total). Narrowed to Degenerette-module-only at v38 per D-272-CLEAN-SCOPE-01. Cross-module candidates (if any are surfaced incidentally during the manual grep-walk) are captured as v39+ backlog seeds in `.planning/notes/2026-05-11-v39-cleanup-candidates.md` (if any are found). No source-tree mutation outside Degenerette module at v38.

### /gas-audit orchestrator (Scavenger + Skeptic)

Originally part of REQUIREMENTS.md CLEAN-01 wording. NOT spawned at v38 per D-272-CLEAN-DISCOVERY-01 (manual grep-walk by planner is the chosen discovery method). The orchestrator remains available for future phases with broader cleanup scope. Not deprecated; just out-of-scope at v38.

### BAF jackpot `_jackpotTicketRoll` xorshift refactor (v36.0 ENT-05 carry)

Same xorshift pattern as v36 lootbox refactor; trivially convertible to bit-sliced keccak draws via `hash2(rngWord, salt)`. Out of v38 scope per ROADMAP.md "Out of Scope" list. Future-phase candidate.

### `runrewardjackpots` module-misplacement

Stale 2026-04-02 backlog note (`.planning/notes/2026-04-02-runrewardjackpots-module-misplacement.md`). Not v38-tagged. Defer to dedicated architecture-cleanup milestone.

### Game-over thorough hardening

`.planning/notes/gameover-thorough-test.md` backlog. Out of v38 scope; defer to dedicated game-over hardening milestone.

### `/degen-skeptic` adversarial-skill addition

Explicitly OUT of scope per D-271-ADVERSARIAL-02 carry → D-272-ADVERSARIAL-01. If post-adversarial-pass concerns surface around practitioner-burned patterns specific to player-side opt-out removal, the skill can be added in a follow-up audit pass — requires new explicit user opt-in.

### v37.0 milestone archive rotation

Per STATE.md operator-next-step notes: optionally rotate `.planning/milestones/v37.0-ROADMAP.md` + `v37.0-REQUIREMENTS.md` archive structure (mirroring v36.0 / v35.0 archive pattern). Not v38-tagged; can be addressed inline during Phase 272 closure flips at planner's discretion.

</deferred>

---

*Phase: 272-always-hero-simplification-maximal-dead-code-cleanup-terminal*
*Context gathered: 2026-05-11*
*4 user-locked decisions (D-272-CLEAN-SCOPE-01 / D-272-CLEAN-DISCOVERY-01 / D-272-COMMIT-SHAPE-01 / D-272-DESIGN-INTENT-01 + D-272-NATSPEC-DISCIPLINE-01) captured this session.*
*3 items deferred to planner discretion with REQUIREMENTS.md-enumerated option sets (GASPIN-02 / LBX-02 / STAT-03-v35-carry).*
*Locked carry-forward from v36.0 Phase 266 → v37.0 Phase 271 chain: D-272-FILES-01, D-272-CLOSURE-01/02, D-272-FCITE-01, D-272-ADVERSARIAL-01, D-272-KI-01, D-272-SEV-01, D-272-APPROVAL-01.*
