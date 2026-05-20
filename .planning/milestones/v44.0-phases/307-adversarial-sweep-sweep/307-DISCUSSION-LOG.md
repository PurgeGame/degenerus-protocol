# Phase 307: Adversarial Sweep (SWEEP) - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in 307-CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-19
**Phase:** 307-adversarial-sweep-sweep
**Areas discussed:** Skeptic-reviewer filter operationalization, Plan task shape — single vs multi-plan

---

## Gray Area Selection (Multi-select)

| Option | Description | Selected |
|--------|-------------|----------|
| CHARGE augments — v44-specific carry-forwards | Beyond SWP-01..05 verbatim, what v44-IMPL/TST surfaces get explicit augment hypotheses | |
| Elevation routing target in v44 | Where does a Tier-1/Tier-2 elevation land — 307-FIXREC-AUGMENT.md / contracts diff / Phase 308 stub | |
| Skeptic-reviewer filter operationalization | Operationalize feedback_skeptic_pass_before_catastrophe.md (structural-protection check + 3-condition EV lens) | ✓ |
| Plan task shape — single vs multi-plan | D-302-TASK-SPLIT-01 single-plan 7-task vs multi-plan split | ✓ |

**Notes:** The two unselected areas were nevertheless covered as part of "Plan task shape" follow-up questions (elevation routing target via Q3; charge augment enumeration via Q4) — D-307-ELEVATION-ROUTING-01 + D-307-CHARGE-01 in CONTEXT.md document the decisions.

---

## Skeptic-Reviewer Filter Operationalization

### Q1: Where in the pipeline does the skeptic-reviewer filter run?

| Option | Description | Selected |
|--------|-------------|----------|
| Dual gate (Recommended) | Each skill self-filters before MD write + orchestrator re-applies at integration time | ✓ |
| Integration-time only | Per-skill MDs report all candidates; orchestrator applies filter once at integration time | |
| Per-skill only | Each skill self-filters; orchestrator trusts the filtered MDs and never re-applies | |

**User's choice:** Dual gate
**Notes:** Catches obvious per-skill dismissals + cross-skill weighting that individual skills miss. Becomes D-307-SKEPTIC-FILTER-01.

### Q2: Structural-protection check — what counts as PASS (filter discards the finding)?

| Option | Description | Selected |
|--------|-------------|----------|
| Strict (Recommended) | Code path makes the attack literally physically unreachable; defense-in-depth alone does NOT pass | ✓ |
| Strict + uncertainty-auto-fails | Strict + auto-fail-on-uncertainty (if reviewer can't construct 1-2 sentence proof, surface to user) | |
| Permissive (defense-in-depth) | Layered defenses accepted as PASS | |

**User's choice:** Strict
**Notes:** Defense-in-depth alone does NOT pass — those findings surface to user-pause. Becomes part of D-307-SKEPTIC-FILTER-01.

### Q3: 3-condition EV lens — threshold application

| Option | Description | Selected |
|--------|-------------|----------|
| All-3 must hold to survive (Recommended) | A finding survives only if (a) attacker controls necessary state, (b) gain measurable, (c) gain > costs all hold | |
| (a) strict, (b)+(c) inform severity only | Only (a) is a hard discard reason; (b)+(c) downgrade severity but do not discard | ✓ |
| (a)+(b) hold; (c) is a note | (a) + (b) are hard discards; (c) sizing note only | |

**User's choice:** (a) strict, (b)+(c) inform severity only
**Notes:** Captures even small-EV findings as MEDIUM/LOW rather than dropping. Preserves audit-trail completeness. Aligns with memory's "reject CATASTROPHE-labeling without rigor" as severity-downgrade rather than discard.

### Q4: Audit trail for discarded findings

| Option | Description | Selected |
|--------|-------------|----------|
| Inline in LOG Disposition (Recommended) | All discards enumerated in 307-01-ADVERSARIAL-LOG.md Disposition section with file:line citations | ✓ |
| Per-skill MD + LOG summary | Per-skill MDs list their discards; LOG has summary count only | |
| Inline + severity-downgrade table | Discards inline AND separate severity-downgrade table for surviving findings | |

**User's choice:** Inline in LOG Disposition
**Notes:** Becomes D-307-AUDIT-TRAIL-01. CONTEXT.md adds a Severity-Downgrade Rationale table alongside the Disposition table as a follow-on (the third option's idea was incorporated as a complementary table, not as alternative to inline LOG audit-trail).

---

## Plan Task Shape — Single vs Multi-Plan

### Q1: Plan structure for Phase 307

| Option | Description | Selected |
|--------|-------------|----------|
| Single plan, D-302-TASK-SPLIT-01 verbatim (Recommended) | 1 plan / 7 tasks: CHARGE + 3 dispatches + integration + conditional elevation + commit | ✓ |
| Two plans — initial pass + conditional RE-PASS | Plan 01 initial pass; Plan 02 conditional RE-PASS only on elevation | |
| Three plans — CHARGE / dispatch / integration | Separation of concerns across 3 plans | |

**User's choice:** Single plan, D-302-TASK-SPLIT-01 verbatim
**Notes:** ROADMAP wave shape "1 AGENT-COMMITTED artifact bundle" maps cleanly. Becomes D-307-PLAN-01.

### Q2: 3-skill dispatch sequencing

| Option | Description | Selected |
|--------|-------------|----------|
| Sequential auditor THEN parallel hunter+economist (Recommended) | /contract-auditor SEQUENTIAL_MAIN first; /zero-day-hunter + /economic-analyst PARALLEL_SUBAGENT after | ✓ |
| All-three parallel from the start | All three PARALLEL_SUBAGENT in one block | |
| All-three sequential (HYBRID-fallback) | All sequential in main context; highest fidelity, slowest, most expensive | |

**User's choice:** Sequential auditor THEN parallel hunter+economist
**Notes:** Strict D-302-INVOKE-01 carry. Auditor MD becomes context for hunter + economist subagents to avoid redundant rediscovery. Becomes D-307-DISPATCH-01. HYBRID-fallback is documented as a runtime escape per ROADMAP allowance — no re-ask required if the parallel attempt fails.

### Q3: Elevation routing in v44

| Option | Description | Selected |
|--------|-------------|----------|
| 307-FIXREC-AUGMENT.md + Phase 308 §4 stub (Recommended) | Author 307-FIXREC-AUGMENT.md; if contract diff needed, USER-APPROVED batched commit; RE-PASS; Phase 308 §4 cross-cites | ✓ |
| Direct amendment to contracts/ with user approval | Treat elevation as Phase 305-style USER-APPROVED batched diff inline; no separate FIXREC-augment artifact | |
| Phase 308 §4 stub only (defer) | Phase 307 flags only; Phase 308 decides whether to RE-PASS or accept-as-documented | |

**User's choice:** 307-FIXREC-AUGMENT.md + Phase 308 §4 stub
**Notes:** Preserves the audit trail (FIXREC-augment artifact precedes any contract diff). RE-PASS discipline per D-302-REPASS-SCOPE-01 fires against the augment diff. Becomes D-307-ELEVATION-ROUTING-01.

### Q4: CHARGE augment enumeration

| Option | Description | Selected |
|--------|-------------|----------|
| Enumerate in plan, planner expands (Recommended) | CONTEXT.md lists 5 candidate v44-specific augments; planner expands each with evidence anchors at plan time | ✓ |
| Defer entirely to planner/CHARGE-author | CONTEXT.md only carries SWP-01..05 + D-302-CHARGE-01 pattern; augments figured out at plan time | |
| Lock the 5 augments verbatim in CONTEXT.md | CONTEXT.md enumerates 5 augments as LOCKED decisions; planner cannot add more without amending | |

**User's choice:** Enumerate in plan, planner expands
**Notes:** CONTEXT.md enumerates the 5 augments as candidates (i)..(v) — 1-slot DayPending packing, pendingResolveDay sentinel race, gwei-snap precision, Phase 306 INV harness gaps, Vault scope-expansion. Planner expands each with evidence anchors AT PLAN TIME and may add 6th+ augments at discretion. Becomes D-307-CHARGE-01.

---

## Claude's Discretion

The following were left to planner/executor latitude (documented under D-307-* "Claude's Discretion" clauses in CONTEXT.md):
- Plan-level vs Task-level boundary for the conditional RE-PASS sub-step inside Task 6.
- HYBRID-fallback trigger at runtime (parallel-subagent failure → sequential main).
- Charge augment expansion (6th+ augments at planner discretion if a v44 surface deserves standalone treatment).
- Severity tag fine-grain sub-tags (5-level baseline is the minimum).
- Per-skill MD frontmatter additions beyond the required `[skeptic-filter]` and `[invocation]` blocks.

---

## Deferred Ideas

- `/degen-skeptic` re-inclusion — OUT per D-271-ADVERSARIAL-02 carry.
- 4th+ skill addition (`/zeneca`, `/doug-polk`, etc.) — defer to milestone-level decision.
- Cross-milestone adversarial RE-PASS (re-run v43 SWEEP against v44) — Phase 308 §5 REG-01 covers v43-surface integrity.
- Direct `contracts/*.sol` augment within Phase 307 without FIXREC-augment artifact — REJECTED.
- Defer all elevation to Phase 308 TERMINAL — REJECTED.
- 6th+ CHARGE augment surface — at planner discretion; not pre-locked.
- Adversarial RE-PASS against Phase 308 §3.F invariant attestation matrix — not applicable (Phase 308 is planning/writing, not contract-mutation).
