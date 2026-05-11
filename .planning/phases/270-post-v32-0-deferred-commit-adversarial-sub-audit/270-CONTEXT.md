# Phase 270: Post-v32.0 Deferred-Commit Adversarial Sub-Audit - Context

**Gathered:** 2026-05-11
**Status:** Ready for planning

<domain>
## Phase Boundary

Read-only adversarial sweep of two long-deferred contract-tree commits whose adversarial coverage was carry-forward-deferred v33.0 → v34.0 → v35.0 → v36.0 close. Phase 270 is the FIRST FULL adversarial coverage of either commit; the deliverable feeds Phase 271 §3.A delta-surface authoring + §6 KI envelope walk.

**Target commits:**

1. **`002bde55`** (`feat(presale): auto-deactivate flag on per-mint cap crossing`, 2026-05-02) — 3 files / +14 / −10 LOC:
   - `contracts/modules/DegenerusGameAdvanceModule.sol` (−12 / +3): removes the `LOOTBOX_PRESALE_ETH_CAP` constant declaration at L142; removes the ETH-cap-OR branch from the level-transition deactivation predicate at L431-435, leaving the `lvl >= 3` trigger as the sole AdvanceModule-side condition.
   - `contracts/modules/DegenerusGameMintModule.sol` (+9 / −1): inlines the `presaleStatePacked` SLOAD/mask/SSTORE at L1029-1042; adds the per-mint cap-crossing check that bit-clears `PS_ACTIVE_MASK` once `newMintEth >= LOOTBOX_PRESALE_ETH_CAP`. Local `presale` boolean captured BEFORE the bump so the buyer that triggers the cap still receives presale terms (split / event / BURNIE bonus).
   - `contracts/storage/DegenerusGameStorage.sol` (+3): adds `LOOTBOX_PRESALE_ETH_CAP = 200 ether` at L863 with `internal` visibility so both modules share one source of truth.

2. **`2713ce61`** (`chore(vault): remove dead setDecimatorAutoRebuy wrapper`, 2026-05-05) — 2 files / +3 / −20 LOC:
   - `contracts/DegenerusVault.sol` (−9): removes `setDecimatorAutoRebuy(address,bool)` from `IDegenerusGamePlayerActions` interface at L29-30; removes the `gameSetDecimatorAutoRebuy(bool)` external wrapper at L640-645. The underlying GAME-side `setDecimatorAutoRebuy` was removed in the Phase 146 ABI cleanup; this commit closes the orphan wrapper.
   - `test/fuzz/CoverageGap222.t.sol` (+3 / −11): drops the `gameSetDecimatorAutoRebuy` fuzz coverage entry (`o6`); renumbers `o7 → o6`, `o8 → o7` in the surviving rejection assertions.

**Per-commit task per ROADMAP DELTA-01/02:**

For each commit: (a) full diff read at landing-SHA with hunk-level grep-cited evidence (file + line range + commit-hash anchor); (b) per-declaration classification under the `audit/FINDINGS-v33.0..v36.0.md` taxonomy `{NEW, MODIFIED_LOGIC, REFACTOR_ONLY, DELETED}`; (c) adversarial-surface sweep over the ROADMAP-enumerated surface list with per-surface verdict `{SAFE, SAFE_BY_DESIGN, SAFE_BY_STRUCTURAL_CLOSURE, FINDING_CANDIDATE}` and grep-cited evidence; (d) v37.0 HEAD invariant re-verification per surface (see D-270-COHERENCE-01).

**KI envelope walk per ROADMAP DELTA-04:**

Confirm neither commit widens EXC-01 (affiliate roll), EXC-02 (prevrandao fallback), EXC-03 (F-29-04 mid-cycle substitution), or EXC-04 (EntropyLib XOR-shift; NARROWED to BAF-only at v36); confirm no new accepted-design entries warranting KI promotion. Result feeds Phase 271 §6 KI gating walk as RE_VERIFIED-NEGATIVE-scope rows.

**Phase 270 boundary state at close:**

- 0 contract-tree mutations. 0 test-tree mutations. ZERO USER-APPROVED commits.
- 1 AGENT-COMMITTED working-file: `270-01-DELTA-SURFACE.md` (canonical filename per D-270-FILES-01; ROADMAP §270 success-criterion-5 cite uses shorthand `subaudit` which canonicalizes against the gsd-sdk init slug `sub-audit` to match the 269- directory naming pattern).
- 1 AGENT-COMMITTED 270-CONTEXT.md (this file) + 1 AGENT-COMMITTED 270-DISCUSSION-LOG.md (sibling).
- 1 AGENT-COMMITTED 270-01-PLAN.md (planner output).
- 1 AGENT-COMMITTED 270-01-SUMMARY.md (executor output at phase close).
- 1 AGENT-COMMITTED STATE.md flip.
- 4 of 4 DELTA-01..04 requirements flipped to PASS at Phase 270 close; PROGRESS table 0/0 → 1/1 (single multi-task plan per D-270-PLAN-01).
- ZERO new storage slots; zero new public/external mutation entry points; zero new modifiers; zero new admin functions (Phase 270 is audit-only — these counters trivially zero).
- Expected FINDING_CANDIDATE row count: ZERO (commits are 3+ months old, mature, and v33 REG-01 already partially handled the GameStorage slot-move side-effect of 002bde55 byte-identically). FINDING_CANDIDATE row escalation path: stubbed Phase-271-§3.A-block-ready in `270-01-DELTA-SURFACE.md` per D-270-FCFORMAT-01.

**Audit baseline:**

- v36.0 closure HEAD `1c0f09132d7439af9881c56fe197f81757f8164a` (v37.0 audit-subject baseline per PROJECT.md).
- v37.0 source-tree HEAD at Phase 270 entry = Phase 269 LBX-01 contract commit `8fd5c2e1` (Phase 269 SHIPPED 2026-05-11; PARTIAL scope per STATE.md — only LBX-01 + GASPIN-01 RCA inline; remaining GASPIN-02/03 + LBX-02/03 + SURF-03 deferred to v37+ maintenance).
- Phase 270 baseline coherence anchor: dual evidence per D-270-COHERENCE-01 — landing-SHA hunk view (`git show 002bde55` / `git show 2713ce61`) AND v37.0 current HEAD invariant cite (grep recipes against the live `contracts/` and `test/` trees).

</domain>

<decisions>
## Implementation Decisions

### Carry-forward (locked from prior milestones — not re-asked)

- **D-270-FILES-01 (single canonical audit deliverable, Phase 271):** Mirror v37 D-267/268/269 FILES-01. NOT a Phase 270 concern (Phase 271 owns `audit/FINDINGS-v37.0.md`); Phase 270 owns ONLY the working-file appendix `.planning/phases/270-post-v32-0-deferred-commit-adversarial-sub-audit/270-01-DELTA-SURFACE.md`. Filename canonical per discussion: the ROADMAP §270 success-criterion-5 cite uses shorthand (`-subaudit` joined) — canonicalized against the gsd-sdk init slug + 269- directory naming convention (`-sub-audit` hyphenated, `v32-0` for the `v32.0` milestone reference). Phase 271 §3.A grep-cite anchor = this exact path.
- **D-270-CLOSURE-01 (signal SHA = HEAD at audit-pass-close):** Mirror v37 D-267/268/269 CLOSURE-01. NOT a Phase 270 concern (Phase 271 §9c emits `MILESTONE_V37_AT_HEAD_<sha>`).
- **D-270-CLOSURE-02 (commit-readiness register §9.NN three-subsection):** Mirror v37 D-267/268/269 CLOSURE-02. Phase 270 SUMMARY contributes ONLY a §9.NN.iii AGENT-COMMITTED audit-artifact row (the `270-01-DELTA-SURFACE.md` working-file appendix). NO §9.NN.i USER-APPROVED contracts row + NO §9.NN.ii USER-APPROVED tests row (Phase 270 has zero source-tree mutations).
- **D-270-SEV-01 (D-08 5-bucket severity rubric):** NOT a Phase 270 concern (Phase 271 §4 owns full-severity F-37-NN finding blocks). Phase 270 only marks severity-tier candidates on FINDING_CANDIDATE rows in `270-01-DELTA-SURFACE.md` stub form per D-270-FCFORMAT-01.
- **D-270-APPROVAL-01 (audit/.planning writes agent-author):** Phase 270 SUMMARY + PLAN + DISCUSSION-LOG + CONTEXT + DELTA-SURFACE all AGENT-COMMITTED. Phase 270 has ZERO contract-tree OR test-tree mutations, so `feedback_no_contract_commits.md` + `feedback_batch_contract_approval.md` are trivially satisfied (no USER-APPROVED gates exist in this phase).
- **D-270-SKIPRESEARCH-01 (skip phase-researcher per `feedback_skip_research_test_phases.md`):** Phase 270 scope is mechanical and fully enumerated: 2 specific commit SHAs, per-commit adversarial-surface enumeration in ROADMAP §270 + DELTA-01/02, taxonomy lifted from `audit/FINDINGS-v33.0..v36.0.md`, KI envelope state at v37.0 entry locked from v36.0 close. Phase-researcher dispatch adds latency with no value — jump straight to plan-phase.
- **D-270-DESIGN-INTENT-METHOD-01 (per `feedback_design_intent_before_deletion.md`):** BOTH target commits ARE removal commits (002bde55 removes the unreachable AdvanceModule cap-OR arm + moves a constant; 2713ce61 removes the orphan vault wrapper). The user's quality bar requires design-intent-trace + actor-game-theory walk for any code-removal proposal — and this generalizes to audit METHODOLOGY for removal commits. Phase 270's sweep MUST include, per commit per surface:
  - **Design-intent trace** — what was the removed code MEANT to do? Use `git log -p -S "<distinctive string>"` (pickaxe) to find when it landed and against what surrounding context. For 002bde55: the removed AdvanceModule cap-OR arm originally fired whenever cumulative mint-only ETH crossed 200 ETH AT the level-transition — pickaxe trace identifies its initial-commit context. For 2713ce61: the removed vault wrapper originally proxied an admin GAME function that the Phase 146 ABI cleanup deleted — pickaxe trace anchors the Phase 146 removal as the unreachability cause.
  - **Actor game-theory walk** — across actor types (presale buyer triggering exactly the cap-crossing mint, presale buyer mid-cycle, late mint after cap-crossing, vault owner attempting to call removed wrapper, fuzz coverage exercising removed selector) × state combinations (presale active / just-deactivated / inactive; cumulative ETH < cap / = cap / > cap; vault ABI consumer using removed selector with `call()` returning false), state explicitly: does any actor gain advantage, lose value, or experience a state-machine ordering hazard?
  - **Forward-looking risk bound** — what could a future engineer break by re-introducing similar code? Cite visibility scope (private/internal/public) and any grep-recipe / audit-trail anchor that bounds the risk.

### Locked this discussion

- **D-270-ADVERSARIAL-01 (pure agent grep-sweep; no skill-tool dispatch in Phase 270):** Phase 270 stays a feeder phase. NO `/contract-auditor`, `/zero-day-hunter`, `/economic-analyst`, or `/degen-skeptic` dispatch during Phase 270 sweep. Adversarial verification is pure agent-driven with grep-cited evidence per ROADMAP surface enumeration. `/contract-auditor` + `/zero-day-hunter` SEQUENTIAL pass on the FULL §4 surface table (which includes Phase 270's two-commit carry-forward declarations as surface rows) is scheduled in Phase 271 per ROADMAP §271 D-NN-ADVERSARIAL-02 carry. `/economic-analyst` + `/degen-skeptic` inclusion = Phase 271 discuss-phase decision per Phase 269 deferral precedent. Rationale: avoids duplicating Phase 271 §4 work on the same surfaces; matches ROADMAP framing "feeding directly into Phase 271 §3.A authoring"; commits are tiny (+14/-10 + +3/-20 LOC) and well within agent capacity.

- **D-270-COHERENCE-01 (landing-SHA delta + HEAD invariant re-verification per surface; "β-deep"):** Every ROADMAP-enumerated adversarial surface row in `270-01-DELTA-SURFACE.md` carries DUAL evidence:
  - **Landing-time hunk evidence** — `git show <sha> -- <path>` view; file + line range at landing-SHA; per-declaration classification `{NEW, MODIFIED_LOGIC, REFACTOR_ONLY, DELETED}` under the `audit/FINDINGS-v33.0..v36.0.md` taxonomy.
  - **v37.0 current HEAD invariant cite** — grep recipe against the live `contracts/` and `test/` trees confirming the invariant the surface is auditing still holds. Examples per commit:
    - For 002bde55 surface "presale-flag timing across the auto-deactivate threshold": HEAD grep recipe confirms the MintModule local `presale` boolean is STILL captured BEFORE the `presaleStatePacked` bump (buyer-receives-presale-terms-before-deactivation invariant).
    - For 002bde55 surface "downstream consumer assumptions in MintModule interaction": HEAD grep recipe confirms `presaleStatePacked` mask/shift constants (PS_MINT_ETH_SHIFT, PS_MINT_ETH_MASK, PS_ACTIVE_MASK) are byte-identical at HEAD vs landing-SHA + the per-mint cap-clear bit-write hasn't been refactored away.
    - For 002bde55 surface "state-machine ordering implications": HEAD grep recipe confirms `LOOTBOX_PRESALE_ETH_CAP` is STILL `internal constant` in `DegenerusGameStorage.sol` (didn't get moved or rescoped) + AdvanceModule's level-transition deactivation predicate at L431-435 still reads as `lvl >= 3 && _psRead(PS_ACTIVE_SHIFT, PS_ACTIVE_MASK) != 0`.
    - For 002bde55 surface "presale → post-presale transition coherence": HEAD grep recipe walks `presaleStatePacked` callsites under both modules; confirms no third writer of `PS_ACTIVE_MASK` introduced post-landing.
    - For 2713ce61 surface "admin-entry-point-removal blast radius": HEAD grep recipe `grep -rn "setDecimatorAutoRebuy\|gameSetDecimatorAutoRebuy" contracts/ test/` returns EMPTY or only the test/fuzz/CoverageGap222.t.sol coverage-list comment (residual-callsite-of-zero proof per DELTA-02).
    - For 2713ce61 surface "downstream gating assumptions in BURNIE auto-rebuy code path": HEAD grep recipe confirms `setAutoRebuyTakeProfit` + `gameSetAutoRebuy` (the BURNIE-auto-rebuy code path callsites that EXISTED alongside the removed `setDecimatorAutoRebuy`) are byte-identical at HEAD and don't reference any decimator-auto-rebuy state.
    - For 2713ce61 surface "Decimator state-machine implications": HEAD grep recipe walks decimator-related callsites (`claimDecimatorJackpot`, `decimator-`, `Decimator`); confirms no residual decimator-auto-rebuy state-machine arm survives.
  - **Why both:** The audit was deferred v33→v37 specifically because no coverage had been done. (β-light) would leave the HEAD-survival question implicit — Phase 271 REG-04 walks PRIOR findings for HEAD-survival, but no prior Phase 270 findings exist yet to walk, so REG-04 doesn't close the gap. (β-deep) closes the gap fully and produces a clean Phase 271 §3.A input.
  - **Cost:** ~4-5 extra grep recipes per commit (8-10 total for both); well within Phase 270 scope.

- **D-270-DEPTH-01 (stay strictly within ROADMAP per-commit surface enumeration):** No scope expansion. The ROADMAP per-commit surface enumeration is:
  - **002bde55 (4 surfaces per DELTA-01):**
    - (i) state-machine ordering implications
    - (ii) presale-flag timing across the auto-deactivate threshold
    - (iii) downstream consumer assumptions in `MintModule` interaction
    - (iv) presale → post-presale transition coherence
  - **2713ce61 (4 surfaces per DELTA-02):**
    - (v) admin-entry-point-removal blast radius
    - (vi) downstream gating assumptions in BURNIE auto-rebuy code path
    - (vii) Decimator state-machine implications
    - (viii) residual `setDecimatorAutoRebuy` callsite proof of zero (grep-recipe)
  If the agent spots an additional adversarial surface during sweep (e.g., flag-clear-vs-write race in 002bde55's inlined `presaleStatePacked` SSTORE, ABI-consumer breakage from 2713ce61's selector removal), the surface is ROUTED to `<deferred>` in this CONTEXT or to a v38+ backlog note — NOT added to the Phase 270 deliverable. Rationale: feeder-phase framing requires bounded deliverable shape; Phase 271 §4 full-surface table absorbs any genuinely new surfaces.

- **D-270-FCFORMAT-01 (FINDING_CANDIDATE rows stubbed Phase-271-§3.A-block-ready):** Default expectation per ROADMAP success-criterion-3: ZERO FINDING_CANDIDATE rows (commits are mature post-v32.0 with no known regressions). If a surface flags FINDING_CANDIDATE, the row in `270-01-DELTA-SURFACE.md` carries a stub block ready for direct Phase 271 §3.A promotion:
  - **Severity-tier candidate** under D-08 5-bucket rubric (CRITICAL / HIGH / MEDIUM / LOW / INFO) — Phase 270 marks the candidate tier; Phase 271 confirms or revises.
  - **Surface description** — 1-3 sentences naming the surface, the invariant, and the candidate violation.
  - **Exploit path** — adversarial argument: actor type × state combination × outcome. Must satisfy the design-intent-trace + actor-game-theory walk methodology per D-270-DESIGN-INTENT-METHOD-01.
  - **Defensive argument** — rebuttal: structural closure / caller-clamp invariant / downstream guard / orthogonality argument. If the defensive argument holds, the verdict downgrades from FINDING_CANDIDATE to SAFE_BY_STRUCTURAL_CLOSURE or SAFE_BY_DESIGN; if it doesn't, the candidate promotes to Phase 271 §3.A.
  - **Grep-cited evidence** — file + line range + commit-hash anchor for both the landing-time and v37.0 HEAD states per D-270-COHERENCE-01.

- **D-270-PLAN-01 (single multi-task PLAN; commit-A → commit-B → KI walk → working-file sequencing):** Single `270-01-PLAN.md` with ~3-4 atomic tasks. Mirrors Phase 267/268/269 single-multi-task-atomic-commit-per-task precedent. Default ordering (planner refines exact decomposition):
  1. **Task 1: 002bde55 sub-audit.** Read `git show 002bde55`; classify per declaration under taxonomy; sweep 4 ROADMAP-enumerated surfaces (i)-(iv) with dual landing-SHA + HEAD invariant evidence per D-270-COHERENCE-01; assign per-surface verdicts; record design-intent-trace + actor-game-theory walk per D-270-DESIGN-INTENT-METHOD-01. AGENT-COMMITTED working-file-draft chore commit if planner finalizes sub-audit-A-only landing checkpoint, OR fold into Task 3.
  2. **Task 2: 2713ce61 sub-audit.** Same shape as Task 1 against the 4 ROADMAP-enumerated surfaces (v)-(viii) including residual-callsite-of-zero grep recipe per DELTA-02. AGENT-COMMITTED working-file-draft chore commit or fold into Task 3.
  3. **Task 3: KI envelope walk + working-file finalization.** EXC-01..04 row-level non-widening confirmation; finalize `270-01-DELTA-SURFACE.md` as Phase-271-§3.A-ready input. AGENT-COMMITTED single batched working-file commit (if Tasks 1+2 didn't already land chore commits).
  4. **Task 4: Phase-close.** `270-01-SUMMARY.md` + 4-requirement PASS table + STATE.md flip + commit-readiness register update (§9.NN.iii AGENT-COMMITTED row only).
  Total: ~2-3 AGENT-COMMITTED commits (combining sub-audit + KI walk + finalization vs splitting per-commit chore commits; planner finalizes).

- **D-270-KI-01 (zero KI promotions expected; rows feed Phase 271 §6 as RE_VERIFIED-NEGATIVE-scope):** EXC-01 (affiliate roll), EXC-02 (prevrandao fallback), EXC-03 (F-29-04 mid-cycle substitution), EXC-04 (EntropyLib XOR-shift NARROWED to BAF-only at v36) — neither commit touches the surface that any EXC envelope ranges over. 002bde55 = presale state-packed-slot bit-clear + AdvanceModule unreachable-arm removal + GameStorage constant relocation (zero RNG / affiliate / gameover / xorshift interaction). 2713ce61 = vault wrapper removal + fuzz coverage drop (zero RNG / affiliate / gameover / xorshift interaction). Result: 4-row RE_VERIFIED-NEGATIVE-scope contribution to Phase 271 §6b. Zero KI promotions; zero KNOWN-ISSUES.md modifications attributable to Phase 270.

### Claude's Discretion (planner refines)

- **Per-commit working-file structure** — single combined `270-01-DELTA-SURFACE.md` with two top-level sections (one per commit) vs two sub-files (`270-01-DELTA-SURFACE-002bde55.md` + `270-01-DELTA-SURFACE-2713ce61.md`). ROADMAP wording ("working-file appendix ... or equivalent canonical filename") accepts either; planner picks single-file combined per Phase 269 single-multi-task-plan single-deliverable precedent unless commit-A and commit-B sub-audits land on different days requiring incremental chore-commits per sub-file.
- **Adversarial-surface table shape** — markdown table with columns (commit, surface, landing-SHA evidence, HEAD invariant cite, verdict) vs prose sections per surface. Phase 269's `_resolveLootboxRoll` LBX-03 §3.A-prep notes used a prose-walk approach; v33.0 FINDINGS §3.A used a markdown table. Either is grep-citable; planner picks for readability.
- **Pickaxe trace depth for design-intent traces (D-270-DESIGN-INTENT-METHOD-01)** — single `git log -p -S "<string>"` pickaxe call per distinctive string vs walking full commit-history of the affected function. Planner picks; single-pickaxe-per-string is the cheap default; full-history walk reserved for surfaces whose initial-landing commit hash isn't obvious (002bde55's AdvanceModule cap-OR arm likely traces back to early Phase ~50-60 presale-flag-introduction commits; 2713ce61's vault wrapper traces back to early vault-introduction).
- **Inline NatSpec vs prose for actor-game-theory walks** — actor × state combinations enumerated as a sub-row table per surface vs flowing prose. Phase 269 used prose; v33.0 FINDINGS §4 used per-surface sub-row prose disclosure for specific surfaces only. Planner picks per surface complexity.
- **Atomic-commit count** — D-270-PLAN-01 estimates 2-3 AGENT-COMMITTED commits (combining vs splitting sub-audit-per-commit chore commits + final working-file commit + phase-close). Planner finalizes (e.g., whether sub-audit-A and sub-audit-B produce standalone chore commits, or fold into a single working-file commit at Task 3).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 270 Anchors

- `.planning/ROADMAP.md` §"Phase 270: Post-v32.0 Deferred-Commit Adversarial Sub-Audit" — 5 success criteria; depends-on = nothing (audit-only; can run in parallel with Phase 267-269 from a content perspective; sequenced before Phase 271 to feed delta-surface inputs).
- `.planning/REQUIREMENTS.md` DELTA-01..04 — 4 v37.0 requirements all mapped to Phase 270 (per the requirements-to-phase mapping table at L151-154).
- `.planning/STATE.md` — milestone v37.0 status; Phase 269 SHIPPED 2026-05-11 (PARTIAL scope — LBX-01 contract commit `8fd5c2e1` + GASPIN-01 RCA inline at `269-01-PLAN.md`; remaining GASPIN-02/03 + LBX-02/03 + SURF-03 deferred to v37+ maintenance per RCA finding that drift mechanism is hardhat-internal); Phase 270 next.
- `.planning/PROJECT.md` — current focus banner; v37.0 audit baseline `1c0f0913`; "Deferred to Future Milestones — carried forward into v37.0" lists "Auditing post-v32.0 commits (`002bde55` presale auto-deactivate, `2713ce61` setDecimatorAutoRebuy removal) — adversarial sub-audit phase planned in v37.0" — Phase 270 fulfills this.

### Phase 269 Source-of-Truth (immediate predecessor)

- `.planning/phases/269-lootbox-dead-branch-cleanup-surf-05-gas-pin-re-pinning/269-CONTEXT.md` — Phase 269 lock register. Phase 270 inherits: single-multi-task-plan precedent (D-269-PLAN-01 → D-270-PLAN-01); AGENT-COMMITTED audit/planning artifact policy (D-269-APPROVAL-01 → D-270-APPROVAL-01); adversarial-skill expansion deferral to Phase 271 (D-269 deferred-ideas → D-270-ADVERSARIAL-01).
- `.planning/phases/269-lootbox-dead-branch-cleanup-surf-05-gas-pin-re-pinning/269-01-PLAN.md` — single-multi-task plan precedent. Phase 270 mirrors structure with audit-only adaptation (no contract/test commits; only AGENT-COMMITTED working-file).
- `.planning/phases/269-lootbox-dead-branch-cleanup-surf-05-gas-pin-re-pinning/269-01-SUMMARY.md` — phase-closure SUMMARY format precedent.

### Phase 267/268 Source-of-Truth (atomic-commit + AGENT-COMMITTED-vs-USER-APPROVED discipline)

- `.planning/phases/267-degenerette-producer-5-table-payout-rewrite/267-01-SUMMARY.md` — phase-closure SUMMARY format precedent.
- `.planning/phases/268-degenerette-statistical-validation-cross-surface-preservation/268-01-SUMMARY.md` — test-only phase SUMMARY precedent (closest shape to Phase 270's audit-only deliverable: zero USER-APPROVED contract commits + 1 batched test commit; Phase 270 = zero USER-APPROVED of either kind + 1 AGENT-COMMITTED working-file).

### Target Commit Diffs (audit subject)

- **`git show 002bde55`** — primary commit A diff. 3 files: `contracts/modules/DegenerusGameAdvanceModule.sol` (−12/+3), `contracts/modules/DegenerusGameMintModule.sol` (+9/−1), `contracts/storage/DegenerusGameStorage.sol` (+3). Net +14 / −10. Commit-hash anchor: `002bde55069202806ba365f748646f7077576e59`.
- **`git show 2713ce61`** — primary commit B diff. 2 files: `contracts/DegenerusVault.sol` (−9), `test/fuzz/CoverageGap222.t.sol` (+3/−11). Net +3 / −20. Commit-hash anchor: `2713ce61e0d4e5953ee5ad00b49e67bf8df2eaf6`.

### Live Contract State (v37.0 HEAD invariant re-verification targets per D-270-COHERENCE-01)

- `contracts/modules/DegenerusGameMintModule.sol` — surface (ii)/(iii) HEAD invariant cite target. Live `presaleStatePacked` SLOAD/mask/SSTORE block at L1029-1042 (post-002bde55 landing-SHA region; line numbers may shift at HEAD due to subsequent v33-v37 work). Live local `presale` boolean capture pattern. Live cap-clear bit-write predicate `if (newMintEth >= LOOTBOX_PRESALE_ETH_CAP) psPacked &= ~uint256(PS_ACTIVE_MASK);`.
- `contracts/modules/DegenerusGameAdvanceModule.sol` — surface (i)/(iv) HEAD invariant cite target. Live level-transition deactivation predicate at L431-435 (post-002bde55 landing-SHA region; line numbers may shift). Confirm `lvl >= 3 && _psRead(PS_ACTIVE_SHIFT, PS_ACTIVE_MASK) != 0` is the sole AdvanceModule-side deactivation condition.
- `contracts/storage/DegenerusGameStorage.sol` — surface (i) HEAD invariant cite target. Live `LOOTBOX_PRESALE_ETH_CAP = 200 ether` at L863 (or wherever GameStorage constant order has settled at HEAD) with `internal constant` visibility. Live `PS_MINT_ETH_SHIFT`, `PS_MINT_ETH_MASK`, `PS_ACTIVE_SHIFT`, `PS_ACTIVE_MASK` byte-identical at HEAD vs landing-SHA.
- `contracts/DegenerusVault.sol` — surface (v)/(vi)/(vii)/(viii) HEAD invariant cite target. Confirm `setDecimatorAutoRebuy` and `gameSetDecimatorAutoRebuy` selectors STILL absent from interface + external function set. Confirm `setAutoRebuyTakeProfit` + `gameSetAutoRebuy` (the BURNIE-auto-rebuy code path callsites that survived) byte-identical at HEAD vs landing-SHA.
- `test/fuzz/CoverageGap222.t.sol` — surface (viii) HEAD invariant cite target. Confirm renumbered `o6` / `o7` (no `o8`) assertion order survives at HEAD; confirm no `gameSetDecimatorAutoRebuy(bool)` selector reference reintroduced.

### Pickaxe / git-log Recipes (design-intent-trace + actor-game-theory walk per D-270-DESIGN-INTENT-METHOD-01)

- `git log -p -S "LOOTBOX_PRESALE_ETH_CAP" -- contracts/modules/DegenerusGameAdvanceModule.sol` — traces when the AdvanceModule cap-OR arm originally landed (pre-002bde55) + when 002bde55 removed it. Anchors design-intent for surface (i) state-machine ordering.
- `git log -p -S "setDecimatorAutoRebuy" -- contracts/DegenerusVault.sol` — traces vault wrapper introduction + Phase 146 GAME-side removal + 2713ce61 vault-side removal. Anchors design-intent for surface (v) admin-entry-point-removal blast radius.
- `git log -p -S "setDecimatorAutoRebuy" -- contracts/modules/` — traces GAME-side function lifetime. Cross-references Phase 146 ABI cleanup as the unreachability cause.
- `git log -p -S "_psWrite\|presaleStatePacked" -- contracts/modules/DegenerusGameMintModule.sol` — traces MintModule's presale-state bit-write callsite evolution; confirms 002bde55's per-mint cap-crossing check has no pre-existing predecessor predicate that 002bde55 missed.

### Taxonomy Reference

- `audit/FINDINGS-v33.0.md` §3a (cont.) AUDIT-01 Delta-Surface Table — `{NEW, MODIFIED_LOGIC, REFACTOR_ONLY, DELETED}` taxonomy precedent. Phase 270 mirrors classification shape.
- `audit/FINDINGS-v34.0.md` §3.A delta-surface table — same taxonomy carried forward.
- `audit/FINDINGS-v35.0.md` §3.A delta-surface table — same.
- `audit/FINDINGS-v36.0.md` §3.A delta-surface table — same. Phase 270 declarations feed Phase 271's `FINDINGS-v37.0.md` §3.A authoring; row shape must match.

### KI Envelope State (v37.0 entry; carry-forward from v36.0 close)

- `.planning/KNOWN-ISSUES.md` at v36.0 close — EXC-04 entry NARROWED to BAF-jackpot-only scope per v36 AUDIT-05 rephrase. EXC-01..03 entries unchanged from v32-v36. Phase 270 DELTA-04 confirms `002bde55` + `2713ce61` neither widen EXC-01..04 nor introduce new accepted-design entries warranting KI promotion.
- `audit/FINDINGS-v36.0.md` §6b — KI envelope re-verification format precedent. Phase 270 contributes RE_VERIFIED-NEGATIVE-scope rows to Phase 271 §6b.

### Memory / Feedback Governing This Phase

- **`feedback_design_intent_before_deletion.md`** — **PRIMARY governing memory for Phase 270 methodology.** Generalizes to audit-of-removal-commits. Phase 270 sweep MUST include design-intent-trace + actor-game-theory walk for each removed code path per D-270-DESIGN-INTENT-METHOD-01.
- `feedback_skip_research_test_phases.md` — Phase 270 has clear mechanical scope (2 specific commit SHAs, surfaces enumerated, taxonomy locked). Skip phase-researcher dispatch; jump straight to plan-phase per D-270-SKIPRESEARCH-01.
- `feedback_no_contract_commits.md` — N/A active gate (Phase 270 has zero contract/test commits) but discipline applies trivially.
- `feedback_batch_contract_approval.md` — N/A active gate (Phase 270 has zero contract/test commits).
- `feedback_never_preapprove_contracts.md` — N/A active gate.
- `feedback_no_dead_guards.md` — N/A; Phase 270 doesn't propose any new code deletion. (The two TARGET commits ARE deletions — Phase 270 audits them; the methodology lens is `feedback_design_intent_before_deletion.md`.)
- `feedback_no_history_in_comments.md` — applies to `270-01-DELTA-SURFACE.md` working-file prose: describe what the surface IS at HEAD (current invariant) + what the landing-SHA hunk shows; NOT what changed pre-002bde55 vs post-002bde55 except as design-intent-trace input (per D-270-DESIGN-INTENT-METHOD-01 the trace is allowed because it informs the verdict, not because it documents history).
- `feedback_wait_for_approval.md` — N/A active gate (Phase 270 has zero USER-APPROVED gates).
- `feedback_manual_review_before_push.md` — applies to AGENT-COMMITTED working-file + planning artifacts: NO `git push` by agent at any point during Phase 270.
- `feedback_rng_backward_trace.md` — N/A; Phase 270 commits have ZERO RNG interaction (002bde55 = presale flag bit-clear + constant relocation; 2713ce61 = vault wrapper removal). Confirmed by EXC-02 / EXC-03 RE_VERIFIED-NEGATIVE-scope per D-270-KI-01.
- `feedback_rng_commitment_window.md` — N/A; no RNG interaction.
- `feedback_test_rnglock.md` — N/A; no RNG-lock changes.
- `feedback_gas_worst_case.md` — N/A active gate (Phase 270 has zero gas-test deliverables) but `002bde55`'s own commit message claims "~10 gas" added cost per the inlined SLOAD/SSTORE check — if Phase 270 sweep wants to validate that claim adversarially (gaming the cap-crossing mint to inflate gas cost), that surfaces as surface (i) state-machine ordering and gets dual evidence per D-270-COHERENCE-01.
- `feedback_contractaddresses_policy.md` — N/A; Phase 270 doesn't touch `ContractAddresses.sol`.

### Phase 271 Forward-Cite (downstream consumer)

- `audit/FINDINGS-v37.0.md` §3.A delta-surface table — `270-01-DELTA-SURFACE.md` rows feed directly. Phase 271 §3.A authoring grep-cites the Phase 270 working-file at the canonical path `.planning/phases/270-post-v32-0-deferred-commit-adversarial-sub-audit/270-01-DELTA-SURFACE.md` per D-270-FILES-01 + ROADMAP §270 success-criterion-5.
- `audit/FINDINGS-v37.0.md` §4 adversarial sweep — `/contract-auditor` + `/zero-day-hunter` SEQUENTIAL pass per ROADMAP §271 D-NN-ADVERSARIAL-02 carry re-audits Phase 270's two-commit declarations as part of the full §4 surface table. If Phase 270's pure-grep-sweep verdict is `SAFE_BY_DESIGN` / `SAFE_BY_STRUCTURAL_CLOSURE` and the Phase 271 skill-tool pass agrees, the verdict locks; if the skill-tool pass disagrees, Phase 271 §4 takes precedence and the Phase 270 verdict gets revised in the SUMMARY-time disposition row.
- `audit/FINDINGS-v37.0.md` §6 KI gating walk — Phase 270 contributes 4 RE_VERIFIED-NEGATIVE-scope EXC-01..04 row inputs per D-270-KI-01. Phase 271 §6b consumes.
- `audit/FINDINGS-v37.0.md` §5 REG-04 — prior-finding spot-check sweep across `audit/FINDINGS-v25..v36.0.md` for findings referencing `setDecimatorAutoRebuy` (2713ce61's removed selector) + presale-flag-handling (002bde55's modified surface). v33 REG-01 already has a row noting 002bde55's GameStorage `_livenessTriggered` body byte-identity — Phase 271 REG-04 walk likely encounters that row and marks PASS; default expectation per ROADMAP §271 success-criterion-4 = ALL rows PASS.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- **`audit/FINDINGS-v33.0.md` §3a (cont.) AUDIT-01 Delta-Surface Table** — markdown table format precedent. `270-01-DELTA-SURFACE.md` mirrors row shape: per-declaration classification (NEW/MODIFIED_LOGIC/REFACTOR_ONLY/DELETED) + per-surface verdict (SAFE/SAFE_BY_DESIGN/SAFE_BY_STRUCTURAL_CLOSURE/FINDING_CANDIDATE) + grep-cited evidence column. Two-column-pair "landing-SHA evidence" + "v37.0 HEAD invariant cite" extends the precedent for D-270-COHERENCE-01 dual-evidence shape.
- **`audit/FINDINGS-v33.0.md` REG-01 row** — already audited 002bde55's GameStorage `_livenessTriggered` body byte-identity at v33 close (cited "now at L1249-1259 due to constant insertion at `GameStorage:863` for the `LOOTBOX_PRESALE_ETH_CAP` move from `AdvanceModule:139` per `002bde55`, but body bytes char-by-char identical to baseline L1246-1256 region"). Phase 270 confirms this row's continued validity at v37.0 HEAD (slot-move side-effect only; not full adversarial coverage — Phase 270 is the first full coverage).
- **v33-v36 §3.A delta-surface table prose conventions** — "row carries hunk-level evidence" style; column shape; verdict semantics. Phase 270 mirrors.

### Established Patterns

- **AGENT-COMMITTED audit-artifact-only phase** — Phase 270 is the first PURELY audit-only phase in v37.0 (Phases 267-269 each have USER-APPROVED contract or test commits). Closest precedent: pre-v37 audit-only sub-phases inside terminal phases (e.g., v32 Phase 250 adversarial sweep sub-tasks). Phase 270 establishes the AGENT-COMMITTED audit-feeder-phase shape as a standalone phase.
- **Dual landing-time + HEAD-state evidence** — extends v33-v36 §3.A row shape with HEAD-invariant cite column per D-270-COHERENCE-01. Phase 271 §3.A inherits this shape for any future deferred-commit carry-forward audits.
- **Pure agent grep-sweep verdict generation** — Phase 271 D-NN-ADVERSARIAL-02 SEQUENTIAL skill-tool pass precedent locks the format for skill-tool-validated verdicts; Phase 270's pure-grep-sweep verdicts are recorded with the SAME format but flagged as "grep-sweep-only; skill-tool pass deferred to Phase 271 §4".
- **Single-multi-task plan with atomic-commit-per-task** — v33/v34/v35/v36/v37-P267-269 precedent. Phase 270 mirrors with audit-only adaptation (AGENT-COMMITTED chore commits per task or single batched working-file commit per planner choice).

### Integration Points

- **`.planning/phases/270-post-v32-0-deferred-commit-adversarial-sub-audit/`** — phase artifacts: `270-CONTEXT.md` (this file), `270-DISCUSSION-LOG.md` (sibling), `270-01-PLAN.md` (planner output), `270-01-DELTA-SURFACE.md` (executor output; the canonical working-file appendix per D-270-FILES-01), `270-01-SUMMARY.md` (phase-close output).
- **`audit/FINDINGS-v37.0.md`** — does NOT exist at Phase 270 close; authored in Phase 271. Phase 270 contributes §3.A delta-surface row source + §6 KI envelope row source.
- **`.planning/STATE.md`** — Phase 270 close flip from `executing` (Phase 270 active) to `executing` (Phase 271 next) with "Phase 270 SHIPPED" last-activity line; PROGRESS table row 270 0/0 → 1/1.
- **`.planning/MILESTONES.md`** — N/A active at Phase 270 close (milestone flip happens at Phase 271 §9c closure-signal emission).
- **`.planning/REQUIREMENTS.md`** — DELTA-01..04 status flip Pending → PASS at Phase 270 close.

</code_context>

<specifics>
## Specific Ideas

### Working-file template sketch (per D-270-FILES-01 + D-270-COHERENCE-01)

```markdown
# 270-01-DELTA-SURFACE.md — Post-v32.0 Deferred-Commit Adversarial Sub-Audit Working File

**Phase:** 270
**Audit baseline:** v36.0 closure HEAD `1c0f0913` → v37.0 source-tree HEAD at Phase 270 entry `<sha>`
**Adversarial-skill posture:** pure agent grep-sweep (per D-270-ADVERSARIAL-01; /contract-auditor + /zero-day-hunter deferred to Phase 271 §4)
**Coherence anchor:** landing-SHA delta + v37.0 HEAD invariant re-verification per surface (per D-270-COHERENCE-01)

## Commit A: 002bde55 — feat(presale): auto-deactivate flag on per-mint cap crossing

### Per-Declaration Classification

| Declaration | File | Lines (landing-SHA) | Taxonomy | Notes |
|---|---|---|---|---|
| `LOOTBOX_PRESALE_ETH_CAP` (AdvanceModule) | `DegenerusGameAdvanceModule.sol` | L142 | DELETED | Moved to GameStorage |
| AdvanceModule cap-OR deactivation arm | `DegenerusGameAdvanceModule.sol` | L431-435 | DELETED (unreachable post-MintModule-check) |
| MintModule inlined SLOAD/mask/SSTORE | `DegenerusGameMintModule.sol` | L1029-1042 | MODIFIED_LOGIC | Replaces helper-based `_psWrite` |
| MintModule per-mint cap-clear predicate | `DegenerusGameMintModule.sol` | L1037-1040 | NEW | `if (newMintEth >= LOOTBOX_PRESALE_ETH_CAP) psPacked &= ~uint256(PS_ACTIVE_MASK);` |
| `LOOTBOX_PRESALE_ETH_CAP` (GameStorage) | `DegenerusGameStorage.sol` | L863 | NEW | `internal constant` |

### Design-Intent Trace (per D-270-DESIGN-INTENT-METHOD-01)

[Pickaxe trace of AdvanceModule cap-OR arm origin + 002bde55 removal motive. Cite anchoring commits.]

### Adversarial-Surface Sweep

| Surface | Landing-SHA Evidence | v37.0 HEAD Invariant Cite | Verdict |
|---|---|---|---|
| (i) state-machine ordering implications | [git show 002bde55 lines] | [grep recipe against contracts/ at HEAD] | SAFE_BY_DESIGN / SAFE_BY_STRUCTURAL_CLOSURE / ... |
| (ii) presale-flag timing across the auto-deactivate threshold | ... | ... | ... |
| (iii) downstream consumer assumptions in MintModule interaction | ... | ... | ... |
| (iv) presale → post-presale transition coherence | ... | ... | ... |

### Actor Game-Theory Walk (per D-270-DESIGN-INTENT-METHOD-01)

[Per actor × state combination: outcome bound + verdict rationale.]

## Commit B: 2713ce61 — chore(vault): remove dead setDecimatorAutoRebuy wrapper

[Mirror structure of Commit A section.]

## KI Envelope Walk (DELTA-04)

| KI | Surface | Phase 270 disposition |
|---|---|---|
| EXC-01 (affiliate roll) | RE_VERIFIED-NEGATIVE-scope at Phase 270 | grep recipe: neither commit touches affiliate-roll path |
| EXC-02 (prevrandao fallback) | RE_VERIFIED-NEGATIVE-scope at Phase 270 | grep recipe: neither commit touches prevrandao usage |
| EXC-03 (F-29-04 mid-cycle substitution) | RE_VERIFIED-NEGATIVE-scope at Phase 270 | grep recipe: neither commit touches gameover-RNG-substitution |
| EXC-04 (EntropyLib XOR-shift, BAF-only at v36) | RE_VERIFIED-NEGATIVE-scope at Phase 270 | grep recipe: neither commit touches EntropyLib or BAF-jackpot path |

## Phase 271 Handoff

- §3.A row count: 2 (one per target commit, summary row each) + sub-rows per surface where prose disclosure is warranted.
- §4 surface table inputs: NONE NEW (Phase 270 surfaces are subsumed into Phase 271 §4's full v37.0 surface table at rows (a)-(h) — Phase 270 declarations feed §3.A only; Phase 271 §4 adversarial-skill pass re-audits these surfaces as part of the full v37 surface walk).
- §6 KI walk inputs: 4 RE_VERIFIED-NEGATIVE-scope rows per the table above.
- FINDING_CANDIDATE escalations: [expected ZERO; if any, list with Phase-271-§3.A-block-ready stub content per D-270-FCFORMAT-01].
```

### 002bde55 invariant-re-verification grep recipes (sketch)

```bash
# Surface (i): LOOTBOX_PRESALE_ETH_CAP location + visibility at HEAD
grep -n "LOOTBOX_PRESALE_ETH_CAP" contracts/storage/DegenerusGameStorage.sol
grep -n "LOOTBOX_PRESALE_ETH_CAP" contracts/modules/DegenerusGameAdvanceModule.sol
# Expected: GameStorage = present (internal constant); AdvanceModule = present as CALLSITE only (no declaration)

# Surface (ii): presale local-boolean capture-before-bump ordering at HEAD
grep -nB2 -A20 "if (presale)" contracts/modules/DegenerusGameMintModule.sol
# Expected: local `presale` is captured BEFORE the bumping `if (presale) { ... }` block

# Surface (iii): mask/shift constants byte-identical at HEAD
grep -nE "(PS_MINT_ETH_(SHIFT|MASK)|PS_ACTIVE_(SHIFT|MASK))" contracts/storage/DegenerusGameStorage.sol
# Expected: PS_MINT_ETH_SHIFT = 8, PS_MINT_ETH_MASK = 0xFFFF... (128 bits), PS_ACTIVE_SHIFT/MASK byte-identical

# Surface (iv): presale → post-presale transition coherence (no third PS_ACTIVE_MASK writer)
grep -rn "PS_ACTIVE_MASK\|PS_ACTIVE_SHIFT" contracts/modules/
# Expected: only MintModule (per-mint cap-clear) + AdvanceModule (lvl>=3 trigger) write PS_ACTIVE
```

### 2713ce61 invariant-re-verification grep recipes (sketch)

```bash
# Surface (v)/(viii): residual setDecimatorAutoRebuy callsite proof of zero at HEAD
grep -rn "setDecimatorAutoRebuy\|gameSetDecimatorAutoRebuy" contracts/ test/
# Expected: EMPTY (or only CoverageGap222.t.sol assertion text without selector reference)

# Surface (vi): BURNIE auto-rebuy survivors byte-identical at HEAD
grep -n "setAutoRebuy\|gameSetAutoRebuy\|setAutoRebuyTakeProfit" contracts/DegenerusVault.sol
# Expected: setAutoRebuy + gameSetAutoRebuy + setAutoRebuyTakeProfit selectors all present, byte-identical to landing-SHA

# Surface (vii): Decimator state-machine implications — no residual decimator-auto-rebuy arm
grep -rn "decimator.*[Aa]uto[Rr]ebuy\|[Aa]uto[Rr]ebuy.*[Dd]ecimator" contracts/
# Expected: EMPTY (no callsite combines decimator and auto-rebuy state)
```

### Pickaxe traces (sketch)

```bash
# Design-intent trace for 002bde55 AdvanceModule cap-OR arm origin
git log -p -S "LOOTBOX_PRESALE_ETH_CAP" -- contracts/modules/DegenerusGameAdvanceModule.sol | head -200

# Design-intent trace for 2713ce61 vault wrapper origin + Phase 146 GAME-side removal
git log -p -S "setDecimatorAutoRebuy" -- contracts/DegenerusVault.sol | head -100
git log -p -S "setDecimatorAutoRebuy" -- contracts/modules/ | head -200
```

</specifics>

<deferred>
## Deferred Ideas

### Phase 271 §4 adversarial-skill pass over the full v37.0 surface table

`/contract-auditor` + `/zero-day-hunter` SEQUENTIAL pass after full §4 draft per ROADMAP §271 D-NN-ADVERSARIAL-02 carry. The pass re-audits Phase 270's two-commit declarations as surface rows (a)/(h)-adjacent in the §4 full v37 surface table. NOT a Phase 270 concern.

### `/economic-analyst` + `/degen-skeptic` adversarial-skill expansion

Resolve at Phase 271 discuss-phase per Phase 269 deferral precedent. NOT a Phase 270 concern. 002bde55's per-mint cap-clear has presale-economics implications (the "buyer who triggers the cap still receives presale terms" property is an economic-incentive surface that `/economic-analyst` could deep-dive); if Phase 271 discuss-phase decides to bring `/economic-analyst` into scope, Phase 270's pure-grep-sweep verdict can be revisited at that lens.

### Additional adversarial surfaces beyond ROADMAP enumeration (per D-270-DEPTH-01)

If the agent spots an additional adversarial surface during sweep, the surface is ROUTED here (not added to Phase 270 deliverable):
- **Hypothetical: flag-clear-vs-write race in 002bde55's inlined MintModule SSTORE** — between the local `presale = true` capture and the `presaleStatePacked &= ~PS_ACTIVE_MASK` bit-clear, is there any reentrancy window where another mint could observe an inconsistent state? Single-tx single-modifier execution suggests not, but a deeper check could surface here.
- **Hypothetical: ABI-consumer breakage from 2713ce61's selector removal** — does any deployed contract or off-chain consumer (e.g., the dashboard ABI) still call `gameSetDecimatorAutoRebuy(bool)` via `.call()` and silently fail? Phase 271 §4 (h) ABI-stability surface could absorb.
- **Hypothetical: gas-cost claim audit for 002bde55** — commit message claims "~10 gas" added cost. Phase 270 could adversarially test the worst-case gas for the cap-crossing mint to validate; routed to v38+ backlog if any drift surfaces.

These remain v38+ backlog candidates unless promoted by Phase 271 discuss-phase user disposition.

### BURNIE-lootbox `lootboxDay = 0` fallback at `openBurnieLootBox` L623-626 (v38+ candidate; carry from Phase 269)

Carried from Phase 269 deferred-ideas. NOT a Phase 270 concern (orthogonal to both target commits).

### `_jackpotTicketRoll` BAF jackpot xorshift refactor (v36 ENT-05 carry)

Out of v37.0 scope per `.planning/REQUIREMENTS.md` Out of Scope table. Tracked for future milestone.

### `runrewardjackpots` module-misplacement (2026-04-02 stale backlog note)

Out of v37.0 scope.

### Game-over thorough hardening (`gameover-thorough-test.md`)

Out of v37.0 scope.

</deferred>

---

*Phase: 270-post-v32-0-deferred-commit-adversarial-sub-audit*
*Context gathered: 2026-05-11*
