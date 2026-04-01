# Phase 132: Event Correctness - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-27
**Phase:** 132-event-correctness
**Areas discussed:** Audit scope & depth, Indexed field policy, Output format

---

## Audit Scope & Depth

| Option | Description | Selected |
|--------|-------------|----------|
| Full sweep | Systematically audit every external/public state-changing function across all 26 files. Use 4naly3er findings as cross-reference checklist. | ✓ |
| Bot findings + targeted gap-fill | Start from 107 routed instances, verify/triage each, then targeted scan for categories bots can't detect (stale params, wrong values, silent transitions). | |
| Bot findings only | Just triage the 107 instances. Fastest but risks missing things bots don't catch. | |

**User's choice:** Full sweep
**Notes:** Ensures coverage of EVT-02 (stale parameter values) and EVT-03 (silent transitions) which bots cannot detect.

---

## Indexed Field Policy

| Option | Description | Selected |
|--------|-------------|----------|
| Prescriptive policy | Define rules (addresses always indexed, amounts never, etc.) and evaluate each event against the policy. | |
| Document as-is | Note 71 instances, acknowledge bot findings, let Phase 134 decide case-by-case. | |
| Indexer-critical only | Only evaluate indexed fields on events that off-chain indexers actually need to filter by. Ignore cosmetic suggestions. | ✓ |

**User's choice:** Indexer-critical only
**Notes:** Most of the 71 NC-10/NC-33 instances are noise. What matters for C4A is whether indexers can reconstruct state.

---

## Output Format

| Option | Description | Selected |
|--------|-------------|----------|
| Single consolidated doc | `audit/event-correctness.md` with sections per contract. | |
| Per-contract files | Separate file per contract in `audit/events/`. | |
| Single doc + bot-triage appendix | Consolidated doc for fresh audit findings, appendix mapping each of 107 routed bot findings to disposition. | ✓ |

**User's choice:** Single doc + bot-triage appendix
**Notes:** Satisfies requirements and provides clear paper trail that Phase 130 bot findings were consumed, not dropped.

---

## Claude's Discretion

- Per-contract section ordering and grouping
- Severity assessment per finding
- OpenZeppelin inherited vs custom event handling
- Whether to group or itemize findings

## Deferred Ideas

None — discussion stayed within phase scope
