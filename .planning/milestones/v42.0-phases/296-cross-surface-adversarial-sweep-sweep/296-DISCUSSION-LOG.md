# Phase 296: Cross-Surface Adversarial Sweep (SWEEP) - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-18
**Phase:** 296-cross-surface-adversarial-sweep-sweep
**Areas discussed:** Charge composition; Consensus + RE-PASS trigger

---

## Gray-Area Selection

| Option | Description | Selected |
|--------|-------------|----------|
| Charge composition | Verbatim SWEEP-02 9 hypotheses only, or augmented with carry-forward observations from Phases 290-295 SUMMARYs | ✓ |
| Consensus + RE-PASS trigger | 3-of-3 vs any-skill threshold; RE-PASS surface scope | ✓ |
| Skill invocation pattern | Truly parallel via 3 Agent spawns vs sequential skill calls in main context | (skipped — inherited v41 P284 default per D-296-INVOKE-01) |
| Artifact set | Full v41 P284 shape vs minimal | (skipped — inherited v41 P284 default per D-296-ARTIFACT-SET-01) |

**User's choice:** Charge composition + Consensus + RE-PASS trigger
**Notes:** User skipped 2 of 4 areas; the skipped areas default to v41 Phase 284 precedent (sequential skill dispatch in main orchestrator context; full per-skill MD + integrated LOG artifact set at planner-private location).

---

## Area 1: Charge Composition

### Sub-question 1 — Charge scope strategy

| Option | Description | Selected |
|--------|-------------|----------|
| SWEEP-02 verbatim only | 9 hypotheses (3 MINTCLN + 4 HRROLL + 2 DPNERF) verbatim from REQUIREMENTS; tight scope; skills still free to roam beyond | |
| SWEEP-02 + carry-forward augments | 9 SWEEP-02 + 4 augments (BURNIE inline-duplicate; DPNERF callsites 1+2; MINTCLN owed-in-baseKey vs v41 owed-salt; HRROLL leader-bonus + rngLocked); matches v41 P284 "10 hypothesis surfaces" pattern | ✓ |
| SWEEP-02 + augments + skill-specific framings | Same as B plus per-skill framing notes; most directive; risks narrowing skill latitude | |

**User's choice:** SWEEP-02 + carry-forward augments (Recommended)
**Notes:** User accepted the recommended option without modification.

### Sub-question 2 — Augment list refinement

| Option | Description | Selected |
|--------|-------------|----------|
| All 4 augments | Lock all 4 augments; final charge = 13 hypotheses | ✓ |
| All 4 + open beyond-charge invitation | Lock the 4 augments AND explicitly invite skills to surface novel-vector hypotheses; charge document closes with the invitation line | (implicit per v41 precedent) |
| Drop (c) and (d); keep (a) BURNIE + (b) DPNERF callsites | Keeps highest-leverage augments only; drops MINTCLN cross-call + HRROLL rngLocked because v41 covered those structurally; final charge = 11 hypotheses | |

**User's choice:** All 4 augments (Recommended)
**Notes:** Locked 13-hypothesis charge = 9 SWEEP-02 verbatim + 4 carry-forward augments. Beyond-charge invitation is implicit per v41 P284 precedent (skills free to surface novel-vector hypotheses with same disposition rubric); CONTEXT.md D-296-CHARGE-01 records this as the closing line of the CHARGE document.

---

## Area 2: Consensus + RE-PASS Trigger

### Sub-question 1 — Consensus threshold rule

| Option | Description | Selected |
|--------|-------------|----------|
| Any-skill flag triggers user review; 3-of-3 = definitive elevation | Two-tier rule per v41 P284 precedent: Tier 1 = ANY skill flag → user-review checkpoint; Tier 2 = 3-of-3 consensus → definitive F-42-NN + automatic RE-PASS | ✓ |
| 3-of-3 only | Only 3-of-3 consensus elevates; 1-of-3 or 2-of-3 dispositions logged as NEGATIVE_RESULT_ONLY / ACCEPTED_DESIGN per skill latitude; risk of missing real findings only one skill catches | |
| Any-skill flag = immediate RE-PASS | Any single FINDING_CANDIDATE triggers RE-PASS without intermediate user-review; risk of false-positive RE-PASS thrash | |

**User's choice:** Any-skill flag triggers user review; 3-of-3 = definitive elevation (Recommended)
**Notes:** Two-tier rule locked. Matches v41 P284 actual behavior (F-41-02 elevated via 3-of-3 consensus). Tier 1 preserves user visibility on minority-flag candidates; Tier 2 automatically queues RE-PASS without intermediate checkpoint (user-review checkpoint implicit at FIX-SWEEP-NN approval gate).

### Sub-question 2 — RE-PASS scope

| Option | Description | Selected |
|--------|-------------|----------|
| Candidate-fix-only | RE-PASS narrows to the FIX-SWEEP-NN diff + affected surface's hypothesis subset; other 2 surfaces stay at original-pass disposition; matches v41 P284 RE-PASS narrowing to Phase 288 dailyIdx fix | ✓ |
| Full re-pass against all 3 surfaces | RE-PASS dispatches all 3 skills against all 3 surfaces; higher coverage but expensive; drags unrelated surfaces back into scope | |
| Candidate-fix-only + cross-surface delta check | RE-PASS targets candidate fix AND adds lightweight cross-surface delta check; compromise; over-engineered for v42 audit subject | |

**User's choice:** Candidate-fix-only (Recommended)
**Notes:** Candidate-fix-only RE-PASS locked. v42 audit subject surfaces are structurally independent (different modules, different function bodies, different RNG consumers); no cross-surface invalidation risk to justify full re-pass.

---

## Wrap-up

### Question — Anything else before writing CONTEXT.md?

| Option | Description | Selected |
|--------|-------------|----------|
| Write CONTEXT.md now | Skipped areas inherit v41 P284 defaults; CONTEXT.md records these as Claude's Discretion defaults | ✓ |
| Discuss skill invocation pattern | Reopen the skill invocation gray area | |
| Discuss artifact set | Reopen the artifact set gray area | |

**User's choice:** Write CONTEXT.md now (Recommended)
**Notes:** User accepted skipping the 2 remaining gray areas; CONTEXT.md captures D-296-INVOKE-01 (sequential skill dispatch in main orchestrator context per D-284-ADVERSARIAL-SCOPE-01 carry) + D-296-ARTIFACT-SET-01 (full v41 P284 artifact shape: CHARGE.md + 3 per-skill MDs + integrated LOG.md + 3 RE-PASS MDs conditional, at planner-private `.planning/phases/296-*/`) as Claude's Discretion defaults.

---

## Claude's Discretion

Areas where Claude inherits sister-phase defaults without explicit user disposition:

- **D-296-INVOKE-01 (skill invocation pattern)** — sequential in main orchestrator context per D-284-ADVERSARIAL-SCOPE-01 + v35 Phase 265 documented experience. Plan-phase splits skill dispatch into 3 sequential tasks (contract-auditor → zero-day-hunter → economic-analyst).
- **D-296-ARTIFACT-SET-01 (artifact set)** — full v41 P284 shape: `296-ADVERSARIAL-CHARGE.md` + 3 `296-ADVERSARIAL-{SKILL}.md` + `296-01-ADVERSARIAL-LOG.md` + 3 `296-ADVERSARIAL-RE-PASS-{SKILL}.md` (conditional). Planner-private `.planning/phases/296-*/` location.
- **D-296-RESEARCH-AGENT-01 (research-agent skip)** — per `feedback_skip_research_test_phases.md` lineage (Phase 283/291/293/295). Plan-phase authors CHARGE document inline; no research dispatch.
- **D-296-KI-01 (KNOWN-ISSUES.md disposition)** — UNMODIFIED by default. Mirrors D-281-KI-01 + D-291-KI-01 + D-293-KI-01 + D-295-KI-01 for non-mutating phases. Phase 297 D-42N-KI-01 owns the final closure-flip disposition.
- **D-296-TASK-SPLIT-01 (plan-phase task structure)** — 7-task structure: Task 1 author CHARGE; Tasks 2-4 dispatch 3 skills sequentially with per-skill MD capture; Task 5 integrate dispositions + apply two-tier consensus rule + write integrated LOG; Task 6 (conditional) FINDING_CANDIDATE surface → user review → RE-PASS or FIX-SWEEP-NN escalation; Task 7 AGENT-COMMIT artifact bundle + STATE.md update.

## Deferred Ideas

Mentioned during discussion + scout phase, not in Phase 296 scope:

- **CHARGE composition option C (skill-specific framings)** — over-narrows skill latitude. Considered for tighter specialization; deferred.
- **RE-PASS option C (candidate-fix + cross-surface delta check)** — over-engineered for v42 audit subject. Deferred for future tightly-coupled-surface milestones.
- **Truly parallel skill invocation via 3 Agent spawns** — D-296-INVOKE-01 locks sequential per v35 Phase 265 + D-284-ADVERSARIAL-SCOPE-01. If a future Claude Code release supports clean multi-skill parallel invocation, revisit.
- **CHARGE / per-skill MD / LOG public-citability** — planner-private at `.planning/phases/296-*/` per gitignore convention. Phase 297 owns any copy-forward to `audit/` decision.
- **Helper extraction for adversarial-pass dispatch** — the CHARGE-and-dispatch pattern as a reusable Skill or sub-workflow. Defer to post-v42 launch consideration.
- **KNOWN-ISSUES.md promotion for any Phase 296-surfaced finding** — Phase 297 D-42N-KI-01 owns the final disposition; Phase 296 defaults to UNMODIFIED.
