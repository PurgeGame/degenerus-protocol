# Phase 302: Cross-Surface Adversarial Sweep (SWEEP) - Context

**Gathered:** 2026-05-18
**Status:** Ready for planning
**Posture:** AUDIT-ONLY milestone. 3-skill HYBRID adversarial pass; invocation pre-authorized per `D-43N-SWEEP-PREAUTH-01`.

<domain>
## Phase Boundary

3-skill HYBRID adversarial pass per Phase 296 D-296-INVOKE-01 precedent: `/contract-auditor` SEQUENTIAL_MAIN_CONTEXT + `/zero-day-hunter` + `/economic-analyst` PARALLEL_SUBAGENT. Charged with finding any storage path violating the freeze invariant — composition attacks, cross-module read/write races, ERC-callback-induced state mutations, multi-block window exploits, game-theoretic write-induced effects, multi-tx batched perturbations. `/degen-skeptic` OUT OF SCOPE per D-271-ADVERSARIAL-02 carry. `/economic-analyst` IN SCOPE per D-271-ADVERSARIAL-03 carry. **Invocation pre-authorized** per `D-43N-SWEEP-PREAUTH-01` user-authorization 2026-05-18 — Phase 302 fires the 3-skill HYBRID without re-pinging; Tier-1 any-skill FINDING_CANDIDATE still pings per D-296-CONSENSUS-01 user-review checkpoint discipline. Audit-only disposition: any FINDING_CANDIDATE routes to appended FIXREC entry (Phase 299 artifact augmentation; no contract change at v43); any SAFE_BY_DESIGN candidate is REJECTED per milestone-goal explicit exclusion. Two-pass re-pass discipline per D-284-ADVERSARIAL-RE-PASS-01 carry if any FIXREC-augment commit lands after initial pass. Wave shape: 1 AGENT-COMMITTED `.planning/phases/302-*/302-01-ADVERSARIAL-LOG.md` artifact with 3 H2 sections (one per skill) + Disposition section. **Zero `contracts/` + `test/` mutations** per audit-only posture. Requirements SWP-01..05 (5).

</domain>

<decisions>
## Implementation Decisions

### Hypothesis Charge Composition

- **D-302-CHARGE-01:** **CHARGE document = SWP-01..05 + carry-forward augments specific to v43 audit subjects.** SWP-01..05 verbatim charge: find any storage path violating the freeze invariant; composition attacks; cross-module read/write races; ERC-callback-induced state mutations; multi-block window exploits; game-theoretic write-induced effects; multi-tx batched perturbations. Carry-forward augments specific to v43 audit subjects:
  - **(i) FIXREC-recommended tactic adequacy** — for a representative subset of Phase 299 FIXREC entries (e.g., top-3 by EV magnitude), does the recommended tactic actually close the VIOLATION class structurally, or are there secondary attack paths the recommendation misses?
  - **(ii) Admin-class cross-interaction** — for Phase 300 ADMA recommendations, are there admin-class combinations (e.g., governance + parameter-update + charity-allowlist invoked in sequence within rngLock window) that bypass any individual admin gate?
  - **(iii) Phase 301 FUZZ harness `vm.skip` coverage gaps** — does the harness exercise enough perturbation classes per CAT-01 consumer to surface all VIOLATION instances, or are there perturbation classes the harness misses?
  - **(iv) Cross-consumer entropy bleed** — for shared participating slots SLOAD'd by multiple consumers (per Phase 298 §14 unique-slot index), do cross-consumer perturbations create entropy correlation that breaks one consumer's determinism via another consumer's resolution path?

  **Why:** SWP-01..05 verbatim covers the freeze-invariant attack surface; (i)..(iv) augments back-cite the v43 audit subjects (FIXREC + ADMA + FUZZ + cross-consumer dependencies) to ensure the adversarial pass attacks every artifact produced in this milestone, not just the original CATALOG output. v41 P284 + v42 P296 precedent ran 10–13 charged hypotheses + carry-forward augments. **How to apply:** Plan-phase 302 authors `302-ADVERSARIAL-CHARGE.md` enumerating SWP-01..05 + (i)..(iv) with per-hypothesis evidence anchors (line citations to FIXREC entries + ADMA recommendations + FUZZ harness functions + Phase 298 §14 unique-slot index).

### Consensus + RE-PASS Trigger

- **D-302-CONSENSUS-01:** **Two-tier consensus rule per v42 D-296-CONSENSUS-01 verbatim.** Tier 1: any single skill flagging `FINDING_CANDIDATE` = user-review checkpoint — orchestrator stops integration, surfaces the candidate disposition + the flagging skill's evidence chain + the other 2 skills' dispositions, asks user whether to elevate to F-43-NN or accept as `ACCEPTED_AS_DOCUMENTED` / `NEGATIVE_RESULT_ONLY`. Tier 2: 3-of-3 consensus `FINDING_CANDIDATE` = definitive elevation to F-43-NN, automatically triggers RE-PASS per D-284-ADVERSARIAL-RE-PASS-01 without intermediate user checkpoint.

- **D-302-REPASS-SCOPE-01:** **Candidate-fix-only RE-PASS per v42 D-296-REPASS-SCOPE-01 verbatim.** If FIXREC-augment commit lands against a specific FIXREC entry, RE-PASS dispatches the 3 skills against the FIXREC-augment diff + the affected hypothesis subset only. Other hypotheses stay at original-pass disposition.

### Elevation Routing under Audit-Only Posture

- **D-302-AUDIT-ONLY-ROUTING-01:** **Any FINDING_CANDIDATE elevation appends to Phase 299 FIXREC, not to a Phase 303a/etc FIX wave.** Under `D-43N-AUDIT-ONLY-01`, no contract changes ship in v43. If a Tier-2 (3-of-3) consensus FINDING_CANDIDATE elevates, the orchestrator:
  1. Authors an appended `.planning/RNGLOCK-FIXREC-AUGMENT.md` (or appends a §N+1 entry to RNGLOCK-FIXREC.md) covering the new VIOLATION class
  2. Adds a v44.0 handoff anchor `D-43N-V44-HANDOFF-NN+1`
  3. AGENT-COMMITS the augment bundle (no contract/test commit; if Phase 301 FUZZ harness needs a new test for the elevated VIOLATION, the user-approved test-commit pings)
  4. If FIXREC-augment commits, RE-PASS is triggered per D-302-REPASS-SCOPE-01

  **Why:** Audit-only posture precludes contract changes; FINDING_CANDIDATE elevation is captured in the audit deliverable + handoff register for v44.0 consumption. **How to apply:** Phase 302 orchestrator at the integration step routes elevation to FIXREC-augment + AGENT-COMMIT; the F-43-NN block in FINDINGS-v43.0.md §4 references the FIXREC-augment entry.

### Claude's Discretion (planner & executor latitude)

- **D-302-INVOKE-01 — Skill invocation pattern: HYBRID (sequential main + parallel subagent).** Carry from v42 D-296-INVOKE-01 verbatim. Plan-phase splits skill dispatch into 3 sequential tasks: Task N+1 `/contract-auditor` SEQUENTIAL_MAIN_CONTEXT; Task N+2 + Task N+3 `/zero-day-hunter` + `/economic-analyst` PARALLEL_SUBAGENT via single-message multi-Task block.

- **D-302-ARTIFACT-SET-01 — Full v42 P296 artifact shape at planner-private location.** Files produced:
  - `.planning/phases/302-*/302-ADVERSARIAL-CHARGE.md` — charge prompt + disposition rubric + boilerplate (SWP-01..05 + (i)..(iv) augments per D-302-CHARGE-01)
  - `.planning/phases/302-*/302-ADVERSARIAL-CONTRACT-AUDITOR.md` — per-skill report
  - `.planning/phases/302-*/302-ADVERSARIAL-ZERO-DAY-HUNTER.md` — per-skill report
  - `.planning/phases/302-*/302-ADVERSARIAL-ECONOMIC-ANALYST.md` — per-skill report
  - `.planning/phases/302-*/302-01-ADVERSARIAL-LOG.md` — integrated 3-H2-section log + Disposition section applying D-302-CONSENSUS-01
  Conditional on FINDING_CANDIDATE elevation: RE-PASS files mirror v42 P296 artifact convention.

- **D-302-RESEARCH-AGENT-01 — Plan-phase skips research-agent dispatch.** Per v42 D-296-RESEARCH-AGENT-01 verbatim. Methodology locked by this CONTEXT.md + REQUIREMENTS SWP-01..05 + v42 P296 precedent.

- **D-302-KI-01 — KNOWN-ISSUES.md UNMODIFIED.** Phase 303 TERMINAL handles per `D-43N-KI-01`.

- **D-302-TASK-SPLIT-01 — Plan-phase task structure (default).** Carry from v42 D-296-TASK-SPLIT-01 verbatim: Task 1 = author CHARGE; Task 2 = dispatch `/contract-auditor`; Task 3 = dispatch `/zero-day-hunter`; Task 4 = dispatch `/economic-analyst`; Task 5 = integrate dispositions + apply two-tier consensus rule + write integrated LOG; Task 6 (conditional) = elevation routing per D-302-AUDIT-ONLY-ROUTING-01; Task 7 = AGENT-COMMIT artifact bundle + STATE.md update.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 302 Anchors
- `.planning/ROADMAP.md` — Phase 302 entry (3-skill HYBRID; invocation pre-authorized per `D-43N-SWEEP-PREAUTH-01`); v43.0 milestone goal precludes SAFE_BY_DESIGN
- `.planning/REQUIREMENTS.md` — SWP-01..05 verbatim (post-pivot with audit-only routing note)
- `.planning/phases/298-vrf-read-graph-catalog-catalog/298-CONTEXT.md` — Phase 298 CATALOG; §14 unique-slot index drives hypothesis (iv) cross-consumer entropy bleed augment
- `.planning/phases/299-fix-recommendation-document-fixrec/299-CONTEXT.md` — Phase 299 FIXREC; drives hypothesis (i) tactic-adequacy augment
- `.planning/phases/300-admin-path-enumeration-audit-adma/300-CONTEXT.md` — Phase 300 ADMA; drives hypothesis (ii) admin-class cross-interaction augment
- `.planning/phases/301-state-shuffle-determinism-fuzz-harness-fuzz/301-CONTEXT.md` — Phase 301 FUZZ; drives hypothesis (iii) vm.skip coverage gap augment

### v42 Phase 296 Adversarial-Pass Precedent (load-bearing for shape inheritance)
- `.planning/milestones/v42.0-phases/296-cross-surface-adversarial-sweep-sweep/296-CONTEXT.md` — D-296-INVOKE-01 + D-296-CONSENSUS-01 + D-296-REPASS-SCOPE-01 + D-296-ARTIFACT-SET-01 + D-296-RESEARCH-AGENT-01 + D-296-TASK-SPLIT-01 — all carried verbatim
- `.planning/milestones/v42.0-phases/296-cross-surface-adversarial-sweep-sweep/296-ADVERSARIAL-CHARGE.md` — charge document format
- `.planning/milestones/v42.0-phases/296-cross-surface-adversarial-sweep-sweep/296-01-ADVERSARIAL-LOG.md` — integrated log format

### v41 Phase 284 Adversarial-Pass Precedent (load-bearing for RE-PASS shape)
- `.planning/milestones/v41.0-phases/284-delta-audit-findings-consolidation-terminal/284-ADVERSARIAL-RE-PASS-CONTRACT-AUDITOR.md` — RE-PASS report shape

### Skill Source Definitions
- `~/.claude/skills/contract-auditor/SKILL.md` — `/contract-auditor` skill definition; SEQUENTIAL_MAIN_CONTEXT invocation
- `~/.claude/skills/zero-day-hunter/SKILL.md` — `/zero-day-hunter` skill definition; PARALLEL_SUBAGENT invocation
- `~/.claude/skills/economic-analyst/SKILL.md` — `/economic-analyst` skill definition; PARALLEL_SUBAGENT invocation

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **v42 P296 ADVERSARIAL-CHARGE.md format** — direct template inheritance; substitute v42 audit-subject anchors for v43 anchors
- **v42 P296 ADVERSARIAL-LOG.md 3-H2-section structure** — direct template inheritance
- **Two-tier consensus rule** — verbatim carry from v42

### Established Patterns
- **AGENT-COMMITTED adversarial-log artifact bundle** — Phase 283 + Phase 296 precedent
- **HYBRID invocation pattern** — Phase 296 sequential `/contract-auditor` + parallel `/zero-day-hunter` + `/economic-analyst`

### Integration Points
- **Phases 298-301 → Phase 302**: every artifact (CATALOG, FIXREC, ADMA, FUZZ harness) feeds into hypothesis charge augments
- **Phase 302 → Phase 303**: §4 adversarial-pass disposition table in FINDINGS-v43.0.md AUDIT-06

</code_context>

<specifics>
## Specific Ideas

- **Pre-authorized invocation** — Phase 302 fires the 3-skill HYBRID without re-pinging; Tier-1 still triggers user-review checkpoint
- **Audit-only elevation routing** — FINDING_CANDIDATE elevation appends to FIXREC, not a contract-change phase

</specifics>

<deferred>
## Deferred Ideas

- **`/degen-skeptic` inclusion** — OUT OF SCOPE per D-271-ADVERSARIAL-02 carry; revisit only if v44.0 FIX-MILESTONE changes the adversarial-pass policy
- **4th+ skill addition** — defer to milestone-level decision; v43 stays at 3-skill HYBRID
- **Cross-milestone adversarial RE-PASS** (re-run v42 adversarial pass against v43 surfaces) — REG-04 prior-finding spot-check already covers this at Phase 303

</deferred>

---

*Phase: 302-Cross-Surface-Adversarial-Sweep-SWEEP*
*Context gathered: 2026-05-18*
