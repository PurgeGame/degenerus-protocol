# Phase 296: Cross-Surface Adversarial Sweep (SWEEP) - Context

**Gathered:** 2026-05-18
**Status:** Ready for planning

<domain>
## Phase Boundary

3-skill PARALLEL adversarial spawn (`/contract-auditor` + `/zero-day-hunter` + `/economic-analyst`) red-teams all 3 v42.0 audit-subject surfaces (MINTCLN + HRROLL + DPNERF) in a single pass after Phases 290-295 complete. `/degen-skeptic` OUT OF SCOPE per D-271-ADVERSARIAL-02 carry. Default outcome ships 1 AGENT-COMMITTED `296-01-ADVERSARIAL-LOG.md` artifact with 3 H2 sections (one per skill) + Disposition section + 0 contract/test commits. Non-default outcome (sweep surfaces ≥ 1 new FINDING_CANDIDATE elevated to F-42-NN) expands the wave shape to per-finding `FIX-SWEEP-NN` contract commits + `TST-SWEEP-NN` test commits, each USER-APPROVED per the same batched-approval discipline as Phases 290 + 292 + 294 (no pre-approval per `feedback_never_preapprove_contracts.md`). Adversarial RE-PASS posture per D-284-ADVERSARIAL-RE-PASS-01 carry — if any FINDING_CANDIDATE materializes against a delivered surface, re-pass the 3 skills against the candidate fix and append RE-PASS disposition to ADVERSARIAL-LOG.md. SWEEP outcome hands forward to Phase 297 §4 (adversarial surfaces) + §5 (sweep methodology) per SWEEP-03 + AUDIT-05. Zero `contracts/` + `test/` mutations BY DEFAULT.

</domain>

<decisions>
## Implementation Decisions

### Hypothesis Charge Composition

- **D-296-CHARGE-01:** **CHARGE document carries 13 hypotheses = 9 SWEEP-02 verbatim + 4 carry-forward augments; skills free to roam beyond charge.** SWEEP-02 verbatim entries: (i) MINTCLN: 3-input hash determinism break; (ii) MINTCLN: owed-in-baseKey griefing on shape collision; (iii) MINTCLN: breaking topic-hash on `TraitsGenerated` parsing-ambiguity for decoders; (iv) HRROLL: ×1.5 leader-bonus whale-coordination / wash-trading MEV; (v) HRROLL: no-floor sybil dilution attack (1-wei spam across 32 slots); (vi) HRROLL: symbol-roll VRF bit-collision with bits[0..12] / [152..167] / [200..215] / `quadrant*3`; (vii) HRROLL: gas regression DOS surface; (viii) DPNERF: intentional EV reduction secondary attacks (deity owners pivot to non-gold strategies destabilizing commons); (ix) DPNERF: ETH↔BURNIE both-paths differential-behavior exploitation. Carry-forward augments: (x) **BURNIE inline-duplicate vs ETH differential** — does the gold-tier branch at `_awardDailyCoinToTraitWinners` L1867-L1874 (commit `38319463` gap-closure) differ semantically from `_randTraitTicket` L1731-L1737 in any subtle way (sentinel pair invariants, virtualCount arithmetic, deity-selection probability) that breaks D-294-CALLER-UNIFORM-01 path-uniformity? (xi) **DPNERF callsites 1+2 production-path coverage gap** — callsites 1 (L698 `_runEarlyBirdLootboxJackpot`) + 2 (L988 `_distributeTicketsToBucket`) are NOT covered by TST-DPNERF-01..05 per D-295-CALLSITE-SCOPE-01; do these callsites exhibit any structural behavior that breaks the D-294-CALLER-UNIFORM-01 by-construction uniformity argument? (xii) **MINTCLN owed-in-baseKey collapse vs v41 owed-salt reference pattern** — Phase 281 owed-salt (4th keccak input) was the v41 cross-call seed-separation invariant; v42 MINTCLN collapses to 3-input hash with owed packed into baseKey low 32 bits — does the new packing structurally re-introduce the v40 collision class or produce a different equivalence-class break? (xiii) **HRROLL leader-bonus + rngLocked window interaction** — the new `_rollHeroSymbol` consumer uses `keccak256(abi.encode(entropy, day))`; does the leader-bonus computation read any player-controllable state between VRF request and fulfillment (per `feedback_rng_commitment_window.md`) that opens a leader-manipulation vector during the rngLocked window? **Why:** SWEEP-02 verbatim alone misses the BURNIE gap-closure differential + DPNERF callsite-coverage gap (both surfaced post-original-roadmap-authoring during Phases 294/295 plan-phase + executor work) + the MINTCLN refactor backward-cite to v41 owed-salt + the HRROLL rngLocked commitment-window check. v41 P284 precedent ran 10 hypotheses including ~2 carry-forward observations + 1 symmetric augment; v42 P296 inherits the same augmentation discipline. **How to apply:** Plan-phase 296 authors `296-ADVERSARIAL-CHARGE.md` enumerating all 13 hypotheses with `(i)`..`(xiii)` numbering + per-hypothesis evidence anchors (line citations to MINTCLN/HRROLL/DPNERF audit-subject commits + carry-forward refs to Phases 281 + 290 + 292 + 294 + 295 design-intent traces); CHARGE document closes with the v41 P284 boilerplate: "Skills are free to surface beyond-charge hypotheses where they identify a novel attack surface; document each beyond-charge hypothesis with the same disposition rubric (SAFE / SAFE_BY_DESIGN / SAFE_BY_STRUCTURAL_CLOSURE / NEGATIVE_RESULT_ONLY / ACCEPTED_DESIGN / FINDING_CANDIDATE)."

### Consensus + RE-PASS Trigger

- **D-296-CONSENSUS-01:** **Two-tier consensus rule per v41 P284 precedent.** Tier 1: ANY single skill flagging `FINDING_CANDIDATE` on a hypothesis = user-review checkpoint — orchestrator stops integration, surfaces the candidate disposition + the flagging skill's evidence chain + the other 2 skills' dispositions on the same hypothesis, asks user whether to elevate to F-42-NN or accept as ACCEPTED_DESIGN / NEGATIVE_RESULT_ONLY at the integration step. Tier 2: 3-of-3 consensus `FINDING_CANDIDATE` on the same hypothesis = definitive elevation to F-42-NN, automatically triggers RE-PASS per D-284-ADVERSARIAL-RE-PASS-01 carry without intermediate user checkpoint (the user-review checkpoint is implicit at the FIX-SWEEP-NN + TST-SWEEP-NN approval gate per `feedback_never_preapprove_contracts.md` + `feedback_batch_contract_approval.md`). **Why:** v41 P284 actual behavior matched this two-tier pattern — F-41-02 (hero-override cross-day divergence) elevated via 3-of-3 consensus; 1-of-3 and 2-of-3 dispositions on other hypotheses logged as NEGATIVE_RESULT_ONLY / ACCEPTED_DESIGN per the flagging skill's note (no false-positive RE-PASS thrash). Two-tier rule preserves the v41 precedent + adds an explicit user-review checkpoint for 1-of-3 cases to ensure the user retains visibility on minority-flag candidates (avoids the failure mode where one skill catches a real bug the other two miss). **How to apply:** Plan-phase 296 records the two-tier rule in `296-ADVERSARIAL-CHARGE.md` Disposition Rubric section. Executor implements the rule at the integration step: (1) accumulate per-skill dispositions into the per-hypothesis row table; (2) if any cell = `FINDING_CANDIDATE` and the row is NOT 3-of-3, STOP + AskUserQuestion presenting the cell + the other 2 skills' dispositions; (3) if row IS 3-of-3 `FINDING_CANDIDATE`, mark elevation + queue RE-PASS without checkpoint. Disposition section of `296-01-ADVERSARIAL-LOG.md` includes a consensus-rule attestation line ("This pass applied the two-tier consensus rule per D-296-CONSENSUS-01: any-skill flag = user-review checkpoint; 3-of-3 consensus = definitive elevation + automatic RE-PASS.").

- **D-296-REPASS-SCOPE-01:** **RE-PASS narrows to the candidate-fix surface only.** If FIX-SWEEP-NN lands against MINTCLN (or HRROLL or DPNERF), the RE-PASS dispatches the 3 skills against the FIX-SWEEP-NN diff + the affected surface's hypothesis subset only. Other 2 surfaces stay at original-pass disposition (no full 3-surface re-pass). RE-PASS hypothesis count is bounded by the affected surface's row count in the 13-hypothesis charge (3 for MINTCLN, 4 for HRROLL, 2 for DPNERF) + the affected augments (e.g., (x) BURNIE differential is DPNERF-affected; (xii) owed-in-baseKey is MINTCLN-affected; (xiii) leader-bonus rngLocked is HRROLL-affected). **Why:** v41 P284 RE-PASS precedent narrowed to the Phase 288 dailyIdx fix only — re-passing all surfaces would have dragged Phase 281 MINTCLN cross-call seed separation back into scope unnecessarily (it was already RESOLVED_AT_V41 at the original pass). Candidate-fix-only RE-PASS is the cost-efficient + audit-precise pattern; unaffected surfaces don't need re-attestation if the fix is structurally isolated to the candidate surface. The 3rd option (cross-surface delta check) is over-engineered for the v42 audit subject — MINTCLN/HRROLL/DPNERF are structurally independent (different modules, different function bodies, different RNG consumers); no cross-surface invalidation risk. **How to apply:** Plan-phase 296 records the candidate-fix-only RE-PASS shape. If RE-PASS triggers, the executor authors `296-ADVERSARIAL-RE-PASS-CHARGE.md` (or appends a RE-PASS section to the original CHARGE) scoped to the affected surface; dispatches 3 skills with the narrowed scope; integrates RE-PASS dispositions into `296-01-ADVERSARIAL-LOG.md` as an appended section per D-284-ADVERSARIAL-RE-PASS-01 carry. Per-skill RE-PASS artifact files at `.planning/phases/296-*/296-ADVERSARIAL-RE-PASS-{SKILL}.md` mirror the original-pass artifact convention.

### Claude's Discretion (planner & executor latitude)

The following gray areas inherit v41 P284 + sister-phase defaults; planner uses these without re-asking the user:

- **D-296-INVOKE-01 — Skill invocation pattern: sequential in main orchestrator context.** Carry from D-284-ADVERSARIAL-SCOPE-01 + v35 Phase 265 documented experience (skills don't run cleanly in subagent contexts; main context is the required invocation site). Plan-phase splits skill dispatch into 3 sequential tasks (Task N+1 contract-auditor, Task N+2 zero-day-hunter, Task N+3 economic-analyst), each running in main orchestrator context. The v41 P284 CHARGE document's "PARALLEL via single message" phrasing is a literal pattern aspiration but the practical execution sequences the 3 skill invocations one-after-another (skills are single-instance per turn). Plan-phase 296 finalizes the task split.

- **D-296-ARTIFACT-SET-01 — Full v41 P284 artifact shape at planner-private location.** Files produced by Phase 296:
  - `.planning/phases/296-*/296-ADVERSARIAL-CHARGE.md` — the 13-hypothesis charge prompt + disposition rubric + boilerplate (NOT the per-skill outputs; the prompt passed to each skill)
  - `.planning/phases/296-*/296-ADVERSARIAL-CONTRACT-AUDITOR.md` — full contract-auditor disposition + per-hypothesis evidence + beyond-charge entries
  - `.planning/phases/296-*/296-ADVERSARIAL-ZERO-DAY-HUNTER.md` — full zero-day-hunter disposition + per-hypothesis evidence + beyond-charge entries
  - `.planning/phases/296-*/296-ADVERSARIAL-ECONOMIC-ANALYST.md` — full economic-analyst disposition + per-hypothesis evidence + beyond-charge entries
  - `.planning/phases/296-*/296-01-ADVERSARIAL-LOG.md` — the integrated 3-H2-section log per SWEEP-03 literal text (each H2 contains the skill's disposition table + cross-cutting prose + report-file reference) + Disposition section applying the two-tier consensus rule per D-296-CONSENSUS-01

  Conditional on FINDING_CANDIDATE elevation:
  - `.planning/phases/296-*/296-ADVERSARIAL-RE-PASS-CONTRACT-AUDITOR.md`
  - `.planning/phases/296-*/296-ADVERSARIAL-RE-PASS-ZERO-DAY-HUNTER.md`
  - `.planning/phases/296-*/296-ADVERSARIAL-RE-PASS-ECONOMIC-ANALYST.md`
  - RE-PASS section appended to `296-01-ADVERSARIAL-LOG.md`
  - `296-NN-FIX-SWEEP.md` plan(s) + USER-APPROVED `contracts/` + `test/` commits per Phase 290/292/294 batched discipline

  Wave shape: default zero-finding → 1 AGENT-COMMITTED commit (CHARGE + 3 per-skill MDs + integrated LOG bundled into ONE commit per `feedback_batch_contract_approval.md` artifact-bundling discipline). Non-default → expands.

- **D-296-RESEARCH-AGENT-01 — Plan-phase skips research-agent dispatch.** Per `feedback_skip_research_test_phases.md` lineage (Phase 283 D-283-RESEARCH-AGENT-01 + Phase 291 + Phase 293 + Phase 295). Phase 296 is an adversarial sweep with locked direction (this CONTEXT.md): 13-hypothesis charge enumerated + consensus rule + RE-PASS scope + artifact set locked. Plan-phase agent authors the CHARGE document inline + drafts the integration step skeleton + leaves the per-skill MDs as `_TO_BE_FILLED_BY_ADVERSARIAL_PASS_` placeholders; orchestrator dispatches the 3 skills (sequential per D-296-INVOKE-01) + integrates dispositions + applies two-tier consensus rule per D-296-CONSENSUS-01.

- **D-296-KI-01 — KNOWN-ISSUES.md UNMODIFIED by default.** Mirrors D-281-KI-01 + D-291-KI-01 + D-293-KI-01 + D-295-KI-01 disposition for non-mutating phases. Phase 297 terminal closure-flip handles KNOWN-ISSUES.md disposition per `D-42N-KI-01` lock; Phase 296 default outcome preserves UNMODIFIED. Non-default outcome (≥ 1 F-42-NN) inherits the same approval discipline as the FIX-SWEEP-NN + TST-SWEEP-NN expansion.

- **D-296-TASK-SPLIT-01 — Plan-phase task structure (default).** Carry from v41 P284 task layout: Task 1 = author CHARGE document; Task 2 = dispatch /contract-auditor + capture report; Task 3 = dispatch /zero-day-hunter + capture report; Task 4 = dispatch /economic-analyst + capture report; Task 5 = integrate dispositions + apply two-tier consensus rule + write integrated 296-01-ADVERSARIAL-LOG.md; Task 6 (conditional) = if any FINDING_CANDIDATE elevates, surface for user review + queue RE-PASS or FIX-SWEEP-NN escalation; Task 7 = AGENT-COMMIT artifact bundle + STATE.md update. Plan-phase 296 finalizes the exact task names + skill-prompt body shape (passing CHARGE document verbatim per `paper-test` skill-orchestration pattern).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 296 Anchors
- `.planning/ROADMAP.md` — Phase 296 entry (5 success criteria; SWEEP-01..05 references; depends on Phases 290-295; default zero-finding wave shape; non-default expansion per Phase 290/292/294 batched-approval discipline)
- `.planning/REQUIREMENTS.md` — SWEEP-01..05 verbatim wording (SWEEP-01 3-skill PARALLEL spawn lock + `/degen-skeptic` OUT OF SCOPE; SWEEP-02 9-hypothesis surface; SWEEP-03 ADVERSARIAL-LOG.md 3-H2 + Disposition shape + RE-PASS posture; SWEEP-04 FIX-SWEEP-NN + TST-SWEEP-NN expansion with USER APPROVAL; SWEEP-05 default zero-finding outcome)
- `.planning/PROJECT.md` — v42.0 milestone goal + audit baseline `MILESTONE_V41_AT_HEAD_315978a0c18294e0d7fa5cd4cdfe7f8e5b9a95c4`
- `.planning/STATE.md` — Phase 295 complete marker; ready to plan Phase 296

### v41 Phase 284 Adversarial-Pass Precedent (load-bearing for shape inheritance)
- `.planning/milestones/v41.0-phases/284-delta-audit-findings-consolidation-terminal/284-ADVERSARIAL-CHARGE.md` — the 10-hypothesis charge format + disposition rubric + boilerplate; Phase 296 CHARGE document mirrors this shape (substitute v42 audit-subject anchors + 13-hypothesis surface)
- `.planning/milestones/v41.0-phases/284-delta-audit-findings-consolidation-terminal/284-01-ADVERSARIAL-LOG.md` — the integrated 3-H2-section log format with skill-major organization + per-skill disposition table + cross-cutting note; Phase 296 `296-01-ADVERSARIAL-LOG.md` mirrors this shape
- `.planning/milestones/v41.0-phases/284-delta-audit-findings-consolidation-terminal/284-ADVERSARIAL-CONTRACT-AUDITOR.md` — per-skill report shape; full disposition + evidence + beyond-charge entries
- `.planning/milestones/v41.0-phases/284-delta-audit-findings-consolidation-terminal/284-ADVERSARIAL-ZERO-DAY-HUNTER.md` — per-skill report shape (zero-day-hunter persona)
- `.planning/milestones/v41.0-phases/284-delta-audit-findings-consolidation-terminal/284-ADVERSARIAL-ECONOMIC-ANALYST.md` — per-skill report shape (economic-analyst persona)
- `.planning/milestones/v41.0-phases/284-delta-audit-findings-consolidation-terminal/284-ADVERSARIAL-RE-PASS-CONTRACT-AUDITOR.md` — RE-PASS report shape; Phase 296 RE-PASS files mirror this
- `.planning/milestones/v41.0-phases/284-delta-audit-findings-consolidation-terminal/284-ADVERSARIAL-RE-PASS-ZERO-DAY-HUNTER.md` — RE-PASS report shape
- `.planning/milestones/v41.0-phases/284-delta-audit-findings-consolidation-terminal/284-ADVERSARIAL-RE-PASS-ECONOMIC-ANALYST.md` — RE-PASS report shape
- `.planning/milestones/v41.0-phases/284-delta-audit-findings-consolidation-terminal/284-CONTEXT.md` — D-284-ADVERSARIAL-CHARGE-01 + D-284-ADVERSARIAL-RE-PASS-01 + D-284-ADVERSARIAL-SCOPE-01 (skills don't run cleanly in subagent contexts; main orchestrator context is the required invocation site)

### v42.0 Surface-Phase Carry-Forward Artifacts (load-bearing for hypothesis (x)..(xiii) augments)

**MINTCLN (Phase 290 + 291):**
- `.planning/phases/290-mint-batch-event-sig-cleanup-mintcln/290-CONTEXT.md` — D-42N-EVT-BREAK-01 indexer-migration disposition; D-290-MINTCLN-* locked decisions
- `.planning/phases/290-mint-batch-event-sig-cleanup-mintcln/290-01-MEASUREMENT.md` — MINTCLN-01..10 bytecode delta + storage byte-identity + public ABI byte-identity attestations
- `.planning/phases/290-mint-batch-event-sig-cleanup-mintcln/290-01-DESIGN-INTENT-TRACE.md` — owed-in-baseKey collapse design rationale (hypothesis (xii) backward-cite to Phase 281 D-281-FIX-SHAPE-01 owed-salt)
- `.planning/phases/290-mint-batch-event-sig-cleanup-mintcln/290-02-SUMMARY.md` — Phase 290 audit-subject commit + carry-forward notes
- `.planning/phases/291-mintcln-regression-fixture-tst-mintcln/291-CONTEXT.md` — TST-MINTCLN-01..05 regression coverage matrix
- `.planning/phases/291-mintcln-regression-fixture-tst-mintcln/291-02-SUMMARY.md` — TST-MINTCLN test artifact + JS-replay oracle pattern

**HRROLL (Phase 292 + 293):**
- `.planning/phases/292-hero-override-weighted-roll-hrroll/292-CONTEXT.md` — D-292-HRROLL-* + ×1.5 leader-bonus design + no-floor sybil dilution disposition + symbol-roll VRF bit-collision attestation (hypothesis (vi) backward-cite)
- `.planning/phases/292-hero-override-weighted-roll-hrroll/292-01-MEASUREMENT.md` — HRROLL-01..10 bytecode delta + bit-slice non-collision proof
- `.planning/phases/292-hero-override-weighted-roll-hrroll/292-01-DESIGN-INTENT-TRACE.md` — leader-bonus + rngLocked window design rationale (hypothesis (xiii) backward-cite)
- `.planning/phases/292-hero-override-weighted-roll-hrroll/292-02-SUMMARY.md` — Phase 292 audit-subject commit + gas regression worst-case + carry-forward notes
- `.planning/phases/293-hrroll-regression-fixture-tst-hrroll/293-CONTEXT.md` — TST-HRROLL-01..06 regression coverage matrix; D-293-INVOKE-01 hybrid methodology
- `.planning/phases/293-hrroll-regression-fixture-tst-hrroll/293-02-SUMMARY.md` — TST-HRROLL test artifact + chi² goodness-of-fit pattern

**DPNERF (Phase 294 + 295):**
- `.planning/phases/294-deity-pass-gold-nerf-dpnerf/294-CONTEXT.md` — D-42N-GOLD-FLOOR-01 + D-42N-DEITY-EV-01 + D-42N-PATH-COVERAGE-01 + D-294-CALLER-UNIFORM-01 + D-294-NATSPEC-01 + BURNIE gap-closure context (hypotheses (x) + (xi) backward-cite)
- `.planning/phases/294-deity-pass-gold-nerf-dpnerf/294-01-MEASUREMENT.md` — DPNERF-01..06 callsite enumeration + bytecode delta + zero-new-state grep-proof
- `.planning/phases/294-deity-pass-gold-nerf-dpnerf/294-01-DESIGN-INTENT-TRACE.md` — DPNERF design-intent + actor-walk + SWEEP-02(iii) 4 pre-emptive answers (hypothesis (ix) backward-cite)
- `.planning/phases/294-deity-pass-gold-nerf-dpnerf/294-02-SUMMARY.md` — Phase 294 audit-subject commit `47936e0c` + BURNIE gap-closure amendment `38319463` + callsite-coverage carry-forward (hypothesis (xi) explicit hand-forward to Phase 296 SWEEP)
- `.planning/phases/295-dpnerf-regression-fixture-tst-dpnerf/295-CONTEXT.md` — TST-DPNERF-01..05 regression coverage matrix; D-295-CALLSITE-SCOPE-01 (callsites 1+2 deferred to Phase 296 SWEEP — hypothesis (xi))

### Contract Source (live HEAD at end of Phase 295)
- `contracts/modules/DegenerusGameMintModule.sol` — MINTCLN audit subject; hypotheses (i)..(iii) + (xii) target this module; `_raritySymbolBatch` signature collapse (3-input hash); `processFutureTicketBatch` + `processTicketBatch` callers; `TraitsGenerated` event topic-hash change
- `contracts/modules/DegenerusGameJackpotModule.sol` — HRROLL + DPNERF audit subjects; hypotheses (iv)..(vii) + (viii)..(xi) + (xiii) target this module
  - L1707-L1763 `_randTraitTicket` (DPNERF audit subject; hypothesis (x) inline-duplicate differential anchor)
  - L1731-L1737 DPNERF gold-tier branch (audit-subject mutation site for ETH path)
  - L1822-L1913 `_awardDailyCoinToTraitWinners` (BURNIE-path body)
  - L1867-L1874 BURNIE inline-duplicate gold-tier branch (commit `38319463` gap-closure; hypothesis (x) explicit site)
  - L698 `_runEarlyBirdLootboxJackpot` + L988 `_distributeTicketsToBucket` (DPNERF callsites 1+2; hypothesis (xi) anchor)
  - HRROLL `_rollHeroSymbol` + `_dailyHeroWagers` (hypothesis (xiii) anchor)
- `contracts/storage/DegenerusGameStorage.sol` — storage byte-identity locked at Phases 290 + 292 + 294 measurement attestations
- `contracts/modules/DegenerusGameAdvanceModule.sol` — rngLocked window + `_unlockRng` semantics (hypotheses (vi) + (xiii) anchor)

### Audit Methodology Feedback (enforce at plan-phase + at adversarial-pass dispatch)
- `~/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_skip_research_test_phases.md` — D-296-RESEARCH-AGENT-01 instantiates; plan-phase skips research-agent dispatch
- `~/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_batch_contract_approval.md` — non-default outcome (FIX-SWEEP-NN + TST-SWEEP-NN) follows batched-approval discipline; default outcome bundles CHARGE + 3 per-skill MDs + LOG into 1 AGENT-COMMITTED artifact commit
- `~/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_no_contract_commits.md` — zero `contracts/` mutations by default; any FIX-SWEEP-NN is USER-APPROVED per `feedback_never_preapprove_contracts.md`
- `~/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_never_preapprove_contracts.md` — orchestrator MUST NOT tell adversarial-pass skills that FIX-SWEEP-NN remediations are pre-approved; user-review checkpoint at both two-tier consensus rule (D-296-CONSENSUS-01 Tier 1) and FIX-SWEEP-NN approval gate
- `~/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_manual_review_before_push.md` — executor presents the 296-01-ADVERSARIAL-LOG.md commit diff + any FIX-SWEEP-NN diff for explicit user approval before commit
- `~/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_rng_backward_trace.md` — hypothesis (vi) HRROLL bit-collision + hypothesis (xii) MINTCLN owed-in-baseKey collapse + hypothesis (xiii) HRROLL rngLocked commitment-window analysis all require backward-trace methodology
- `~/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_rng_commitment_window.md` — hypothesis (xiii) HRROLL leader-bonus + rngLocked window check directly applies this rule
- `~/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_verify_call_graph_against_source.md` — hypothesis (x) BURNIE inline-duplicate differential + hypothesis (xi) DPNERF callsites 1+2 production-path uniformity both require grep-verified call-graph attestation against source pre-patch (Phase 294 BURNIE gap precedent is the load-bearing prior)
- `~/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_design_intent_before_deletion.md` — if any FIX-SWEEP-NN proposes deletion of existing logic, design-intent trace + actor-walk required before deletion
- `~/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_no_dead_guards.md` — if any FIX-SWEEP-NN proposes adding a guard, demonstrate the guard is reachable
- `~/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_frozen_contracts_no_future_proofing.md` — any FIX-SWEEP-NN must address an actual exploitable vector, not future-proofing
- `~/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_no_history_in_comments.md` — `296-01-ADVERSARIAL-LOG.md` is a planner artifact (not NatSpec); CAN reference v40/v41 baselines; if FIX-SWEEP-NN touches NatSpec, no "previously/used to be" wording
- `~/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_gas_worst_case.md` — hypothesis (vii) HRROLL gas regression DOS check requires theoretical worst-case derivation; Phase 292 §5 attestation is the load-bearing prior

### Carry-Forward Decision Anchors
- `D-271-ADVERSARIAL-01` + `D-271-ADVERSARIAL-02` + `D-271-ADVERSARIAL-03` (v37.0 carry) — 3-skill PARALLEL adversarial pass + `/degen-skeptic` OUT OF SCOPE
- `D-284-ADVERSARIAL-RE-PASS-01` (v41.0 carry) — RE-PASS posture if FINDING_CANDIDATE materializes; Phase 296 D-296-REPASS-SCOPE-01 narrows scope to candidate-fix-only
- `D-284-ADVERSARIAL-SCOPE-01` (v41.0 carry) — skill invocation in main orchestrator context (skills don't run cleanly in subagent contexts per v35 Phase 265 documented experience); Phase 296 D-296-INVOKE-01 instantiates
- `D-42N-PATH-COVERAGE-01` + `D-294-CALLER-UNIFORM-01` (v42.0 Phase 294) — BURNIE↔ETH path-uniformity structural argument; Phase 296 hypothesis (x) red-teams the differential
- `D-295-CALLSITE-SCOPE-01` (v42.0 Phase 295) — DPNERF callsites 1+2 deferred to Phase 296 SWEEP; hypothesis (xi) anchor
- `D-281-FIX-SHAPE-01` (v41.0 Phase 281) — owed-salt cross-call seed separation reference pattern; Phase 296 hypothesis (xii) backward-cite for MINTCLN owed-in-baseKey collapse

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **v41 P284 CHARGE document template** — `.planning/milestones/v41.0-phases/284-delta-audit-findings-consolidation-terminal/284-ADVERSARIAL-CHARGE.md` is the load-bearing shape reference; Phase 296 CHARGE document mirrors the section structure (Context / Charge / Required output format per hypothesis / Disposition Rubric / Boilerplate closing).
- **v41 P284 integrated LOG format** — `.planning/milestones/v41.0-phases/284-delta-audit-findings-consolidation-terminal/284-01-ADVERSARIAL-LOG.md` is the integrated-log shape reference; skill-major H2 organization with per-hypothesis disposition table + cross-cutting prose per skill + Disposition section applying consensus rule.
- **v41 P284 per-skill MD files** — full disposition + per-hypothesis evidence chain + beyond-charge entries pattern; Phase 296 inherits verbatim.
- **3 skills already registered as project-local skills** — `/contract-auditor` + `/zero-day-hunter` + `/economic-analyst` per `.claude/skills/` registry; dispatchable via main-context skill invocation.
- **paper-test skill orchestration pattern** — `.claude/skills/paper-test/SKILL.md` provides the multi-skill orchestration template (degen-skeptic + protocol-advocate + doug-polk + readability-reviewer); Phase 296 plan-phase can reference this pattern for the 3-skill sequential dispatch shape.

### Established Patterns
- **3-skill PARALLEL adversarial pass at non-terminal phase** — NEW PATTERN at v42.0. v37.0 (Phase 271) + v40.0 (Phase 280) + v41.0 (Phase 284) all ran the adversarial pass AS PART OF the terminal audit phase. v42.0 (Phase 296) is the FIRST milestone splitting the adversarial pass into its own phase between surface phases (290-295) and terminal audit (297). Plan-phase 296 records this as a new shape inheriting v41 P284 internal mechanics but landing one phase earlier in the milestone.
- **Skill-major H2 organization** — v41 P284 + earlier precedents; one H2 per skill with per-hypothesis disposition table inside. Phase 296 inherits.
- **Per-hypothesis disposition rubric** — 6 dispositions: SAFE / SAFE_BY_DESIGN / SAFE_BY_STRUCTURAL_CLOSURE / NEGATIVE_RESULT_ONLY / ACCEPTED_DESIGN / FINDING_CANDIDATE. Phase 296 inherits verbatim.
- **AGENT-COMMITTED single-bundle commit for non-mutating phases** — Phase 283 (v41 SWEEP) + Phase 280 (v40 terminal) + Phase 274 (v39 terminal) + Phase 271 (v37 terminal) precedent; CHARGE + per-skill MDs + integrated LOG bundled into ONE commit at phase close.
- **Two-tier consensus rule + RE-PASS** — Phase 296 NEW codification of the v41 P284 implicit behavior; D-296-CONSENSUS-01 documents the rule explicitly.

### Integration Points
- **Phase 296 → Phase 297 §4 + §5** — per SWEEP-03 + AUDIT-05; Phase 297 §4 cites Phase 296 `296-01-ADVERSARIAL-LOG.md` for adversarial-pass disposition (SAFE / SAFE_BY_DESIGN / SAFE_BY_STRUCTURAL_CLOSURE / RESOLVED_AT_V42); §5 sweep-methodology prose copies the consensus-rule attestation + per-hypothesis disposition summary forward.
- **Phase 296 → ROADMAP / STATE update** — phase-close commit updates STATE.md `stopped_at` to "Phase 296 complete; ready to plan Phase 297" + ROADMAP Phase 296 line to checked.
- **Phase 296 non-default → FIX-SWEEP-NN + TST-SWEEP-NN expansion** — if any FINDING_CANDIDATE elevates (3-of-3 or user-approved Tier-1 escalation), wave shape expands per SWEEP-04: per-finding contract commit + test commit; each USER-APPROVED per Phase 290/292/294 batched discipline; SWEEP outcome carried forward to Phase 297 §4 (F-42-NN finding block) + §5 (RE-PASS methodology attestation).

### Out-of-Scope Source-Tree Surfaces (planner MUST NOT touch by default)
- `contracts/` entire directory — D-296-CHARGE-01 instantiates analytical adversarial pass only; ANY `contracts/` mutation at Phase 296 requires explicit USER approval per `feedback_never_preapprove_contracts.md` (FIX-SWEEP-NN escalation path)
- `test/` entire directory — same posture (TST-SWEEP-NN escalation path)
- `KNOWN-ISSUES.md` — UNMODIFIED by default per D-296-KI-01
- `audit/` entire directory — Phase 297 terminal phase owns audit/FINDINGS-v42.0.md authoring; Phase 296 does NOT touch audit/
- v41 closure artifacts under `.planning/milestones/v41.0-phases/` — frozen; read-only for precedent reference

</code_context>

<specifics>
## Specific Ideas

- **CHARGE document hypothesis numbering** — use (i)..(xiii) Roman numerals per v41 P284 precedent; group by surface (i..iii MINTCLN core; iv..vii HRROLL core; viii..ix DPNERF core; x..xiii augments grouped by surface affinity). Per-hypothesis section includes: (a) hypothesis statement; (b) evidence anchors (file:line citations to audit-subject commits + carry-forward refs); (c) expected disposition class (e.g., "expected SAFE_BY_STRUCTURAL_CLOSURE pending skill confirmation"); (d) cross-cite to relevant Phase 290/292/294 design-intent traces.
- **Disposition Rubric section** — CHARGE document closes with verbatim disposition list: SAFE / SAFE_BY_DESIGN / SAFE_BY_STRUCTURAL_CLOSURE / NEGATIVE_RESULT_ONLY / ACCEPTED_DESIGN / FINDING_CANDIDATE per v41 P284 exact wording. Each skill returns disposition per hypothesis + 1-2 sentence evidence note + beyond-charge entries with same rubric.
- **Skill prompt body** — pass CHARGE document verbatim per `paper-test` skill-orchestration pattern; do NOT pre-summarize for skills (each skill reads the full context fresh + applies its persona). Adversarial-pass output format per hypothesis is the format mandate that each skill MUST follow.
- **Integration step trigger order** — orchestrator dispatches contract-auditor first (likely surfaces gas/RNG/MEV issues + sets the baseline disposition table), then zero-day-hunter (novel-vector composition issues + state-machine gaps), then economic-analyst (incentive shifts + EV distortion). Each skill's output is captured to its `296-ADVERSARIAL-{SKILL}.md` file BEFORE the next skill is invoked. At the integration step, orchestrator reads all 3 per-skill MDs + applies the two-tier consensus rule per D-296-CONSENSUS-01.
- **Two-tier consensus rule integration logic (pseudocode)** — for each of 13 hypotheses:
  ```
  read row[hypothesis_id] = [contract_auditor_disposition, zero_day_hunter_disposition, economic_analyst_disposition]
  count_findings = count(d == "FINDING_CANDIDATE" for d in row)
  if count_findings == 3:
      mark row as ELEVATED (definitive F-42-NN candidate); queue RE-PASS automatically
  elif count_findings >= 1:
      STOP integration; AskUserQuestion presenting the row + flagging skill's evidence + other 2 dispositions; user decides {ELEVATE_TO_F42_NN, ACCEPT_AS_DOCUMENTED, KEEP_AS_FINDING_CANDIDATE_PENDING_REPASS}
  else:
      mark row as CLEAR (all dispositions are SAFE-variant or NEGATIVE_RESULT_ONLY or ACCEPTED_DESIGN)
  ```
  Plan-phase 296 finalizes the exact AskUserQuestion shape + user-disposition options.
- **Default wave-shape commit message** — `docs(296): cross-surface adversarial sweep [SWEEP-01..05]` for the 1 AGENT-COMMITTED artifact bundle (CHARGE + 3 per-skill MDs + integrated LOG). Non-default expansion: per-finding `feat(296): SWEEP-derived <surface> fix [FIX-SWEEP-NN]` + `test(296): SWEEP-derived <surface> regression [TST-SWEEP-NN]` matching Phase 290/292/294 commit naming.

</specifics>

<deferred>
## Deferred Ideas

- **CHARGE composition option C (skill-specific framings)** — adding per-skill framing notes in CHARGE.md (e.g., "contract-auditor focuses on gas/RNG/MEV; zero-day-hunter on composition/state-machine; economic-analyst on incentive shifts") was considered but DEFERRED — risks narrowing skill latitude. Each skill's persona prompt already defines its focus area; explicit framings in CHARGE.md would over-constrain. If a future milestone wants tighter skill specialization, consider this then.
- **RE-PASS option C (candidate-fix + cross-surface delta check)** — over-engineered for v42 audit subject; MINTCLN/HRROLL/DPNERF are structurally independent so no cross-surface invalidation risk. If a future milestone has tightly coupled surfaces, revisit.
- **Truly parallel skill invocation via 3 Agent spawns** — D-296-INVOKE-01 locks sequential in main context per D-284-ADVERSARIAL-SCOPE-01 carry. The "PARALLEL via single message" aspiration from v41 P284 CHARGE document is preserved in name only; practical execution is sequential. If a future Claude Code release supports clean multi-skill parallel invocation, revisit.
- **CHARGE document supplementary boilerplate** — v41 P284 included context about Phase 281 + Phase 282 + Phase 283 as the audit subject. Phase 296 inherits the equivalent (Phase 290 MINTCLN + Phase 292 HRROLL + Phase 294 DPNERF as audit subjects); Phase 291 + 293 + 295 regression fixtures provide regression evidence but are NOT primary audit-subject anchors for the adversarial pass (the contract changes are the audit subjects). Plan-phase 296 finalizes the exact boilerplate length.
- **`paper-test` skill direct invocation** — `paper-test` orchestrates degen-skeptic + protocol-advocate + doug-polk + readability-reviewer for whitepaper review. NOT applicable to Phase 296 (different skill set + different rubric). Considered for skill-orchestration shape reference only.
- **Helper extraction for adversarial-pass dispatch** — the CHARGE-and-dispatch pattern could become a reusable Skill or sub-workflow if it lands at every milestone. Defer to post-v42 launch consideration.
- **Phase 297 audit/FINDINGS-v42.0.md §4 + §5 prose copy-forward shape** — Phase 297 plan-phase decides exact prose; Phase 296 hands forward the integrated `296-01-ADVERSARIAL-LOG.md` + per-skill MDs as the source. If Phase 297 wants a publicly-citable raw artifact, plan-phase 297 decides whether to copy any 296-* file into `audit/`.
- **KNOWN-ISSUES.md disposition for any Phase 296-surfaced finding** — D-296-KI-01 defaults to UNMODIFIED; Phase 297 D-42N-KI-01 owns the final disposition. If Phase 296 surfaces a F-42-NN that maps to a known-issue taxonomy, Phase 297 closure-flip handles the promotion (not Phase 296).
- **CHARGE / per-skill MD / LOG public-citability** — Phase 296 artifacts at `.planning/phases/296-*/` are planner-private per the gitignore convention. If a future audit deliverable wants them publicly cited, the copy-forward decision lives at Phase 297 (not Phase 296). Default: planner-private.

</deferred>

---

*Phase: 296-cross-surface-adversarial-sweep-sweep*
*Context gathered: 2026-05-18*
*4 user-locked decisions captured this session: D-296-CHARGE-01 (13-hypothesis charge = 9 SWEEP-02 verbatim + 4 carry-forward augments + beyond-charge invitation), D-296-CONSENSUS-01 (two-tier consensus rule: any-skill flag = user-review checkpoint; 3-of-3 = definitive elevation + automatic RE-PASS), D-296-REPASS-SCOPE-01 (candidate-fix-only RE-PASS scope; other surfaces stay at original-pass disposition).*
*5 Claude's-Discretion defaults captured: D-296-INVOKE-01 (sequential skill invocation in main orchestrator context per D-284-ADVERSARIAL-SCOPE-01 carry); D-296-ARTIFACT-SET-01 (full v41 P284 artifact shape at planner-private `.planning/phases/296-*/`); D-296-RESEARCH-AGENT-01 (skip research-agent dispatch); D-296-KI-01 (KNOWN-ISSUES.md UNMODIFIED by default); D-296-TASK-SPLIT-01 (7-task plan structure: CHARGE author → 3 skill dispatches → integration → conditional RE-PASS/escalation → artifact commit).*
*Locked carry-forward from v37/v40/v41 adversarial precedents: 3-skill PARALLEL spawn (D-271-ADVERSARIAL-01 + D-271-ADVERSARIAL-03); /degen-skeptic OUT OF SCOPE (D-271-ADVERSARIAL-02); RE-PASS posture (D-284-ADVERSARIAL-RE-PASS-01); skill invocation in main context (D-284-ADVERSARIAL-SCOPE-01).*
*Plan-phase next: research-agent skipped per D-296-RESEARCH-AGENT-01. Plan structure likely 7 tasks per D-296-TASK-SPLIT-01. Default wave shape = 1 AGENT-COMMITTED commit bundling CHARGE + 3 per-skill MDs + integrated LOG. Non-default expansion if any FINDING_CANDIDATE elevates (Tier-1 user review OR Tier-2 3-of-3 consensus) — per-finding FIX-SWEEP-NN + TST-SWEEP-NN USER-APPROVED commits per Phase 290/292/294 batched discipline + RE-PASS dispatch per D-296-REPASS-SCOPE-01.*
