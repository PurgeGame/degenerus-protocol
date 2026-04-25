# Phase 243: Delta Extraction & Per-Commit Classification - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-23
**Phase:** 243-delta-extraction-per-commit-classification
**Areas discussed:** Auto-decide via precedents (user selected single option to skip interactive gray-area drilldown)

---

## Gray Area Selection

| Option | Description | Selected |
|--------|-------------|----------|
| Auto-decide via precedents | Use v29.0 Phase 230 + v30.0 Phase 237 patterns directly: single-file catalog `audit/v31-243-DELTA-SURFACE.md`, fresh-eyes with reconciliation, READ-only, scope-guard deferral. Skip interactive discussion. | ✓ |
| Plan split (1 vs 3 plans) | Phase 230 = 1 plan; Phase 237 = 3 plans per requirement. DELTA-01/02/03 could map 1:1, or collapse into 1 plan. | |
| REFACTOR_ONLY vs MODIFIED_LOGIC bar | New taxonomy this milestone. Borderlines: `ethFreshWei→ethMintSpendWei` rename + return-drop, multi-line SLOAD reformat, `_unlockRng(day)` removal. Need clear rule for Phase 244 key-in. | |
| Storage layout + call-site scope | Does Phase 243 include `forge inspect` slot-layout diff as part of DELTA-01, or defer to Phase 244 GOX-07? DELTA-03 grep reproducibility — exact commands inline per function, or only at section headers? | |

**User's choice:** Auto-decide via precedents (Recommended)
**Notes:** User opted to skip interactive drilldown. Claude auto-resolved all 4 alternative gray areas using Phase 230 + Phase 237 precedents as the authority — recorded in CONTEXT.md as D-01 through D-22.

---

## Auto-Resolved Alternatives (would have been asked interactively)

### Plan split (1 vs 3 plans)

| Option | Description | Auto-decided |
|--------|-------------|--------------|
| 1 plan (Phase 230 style) | Single consolidated plan covering DELTA-01/02/03 sequentially. Lower overhead; matches smaller scope (4 code-touching commits). | |
| 3 plans, 2-wave topology (Phase 237 style) | 243-01 DELTA-01 wave 1, then 243-02 DELTA-02 + 243-03 DELTA-03 wave 2 parallel. Preserves per-requirement traceability. | ✓ |

**Auto-rationale:** Phase 237 precedent wins — DELTA-01 produces the universe row list that DELTA-02 classification and DELTA-03 call-site enumeration both depend on. 3-plan 2-wave topology preserves per-requirement traceability and allows parallel execution after enumeration lands. Recorded as D-10/D-11.

### REFACTOR_ONLY vs MODIFIED_LOGIC bar

| Option | Description | Auto-decided |
|--------|-------------|--------------|
| Strict (execution trace must be byte-equivalent) | REFACTOR_ONLY burden: reviewer must prove no SSTORE/call/branch/emit/return changed. Any doubt → MODIFIED_LOGIC. | ✓ |
| Permissive (documented intent) | Accept the commit message's "refactor" claim as evidence; MODIFIED_LOGIC only when the commit itself calls the change a logic fix. | |
| Hybrid (rubric-driven) | Apply a pre-locked rubric with borderline-case verdicts frozen in CONTEXT.md. | |

**Auto-rationale:** Strict + pre-locked borderline rubric (hybrid execution with strict floor). Every REFACTOR_ONLY verdict requires hunk citation AND one-line rationale naming the specific non-execution-changing element. Every MODIFIED_LOGIC verdict names the specific execution-trace-changing element. Pre-locked verdicts for all 10 known boundary cases in the 5-commit surface. Recorded as D-04/D-05/D-06/D-19.

### Storage layout scope

| Option | Description | Auto-decided |
|--------|-------------|--------------|
| Include in Phase 243 (as DELTA-01 state-var) | Phase 243 produces `forge inspect` slot-layout diff; Phase 244 GOX-07 verifies it. | ✓ |
| Defer entirely to Phase 244 GOX-07 | Phase 243 only lists state variable names; slot-layout verification belongs with the GOX audit. | |

**Auto-rationale:** Slot layout IS delta data — state variables changing shape or ordering is fundamental inventory. Keeping it in Phase 243 preserves the "sole scope input" invariant from ROADMAP Phase 243 success criterion 4 (Phase 244 references Phase 243 as its sole input). GOX-07's job is verdict, not production. Recorded as D-16.

### Call-site reproducibility

| Option | Description | Auto-decided |
|--------|-------------|--------------|
| Inline grep command per function row | Every call-site catalog row includes the exact grep command. Maximum reproducibility. | ✓ |
| Section-header commands only | One set of grep commands at the section header; rows reference it. Less repetition. | |
| Companion reproduction recipe only | Commands in a dedicated appendix; rows cite the recipe step. | |

**Auto-rationale:** Inline grep per row + aggregate reproduction recipe appendix. Per-row grep commands give reviewers one-click replay; aggregate appendix lets reviewers rerun the entire Phase 243 from shell. Matches Phase 230 / Phase 237 grep-reproducibility precedent. Recorded as D-18.

---

## Claude's Discretion (from CONTEXT.md D-23..D-28 equivalent)

The following items are left to the planner's discretion:

- Exact section ordering within `audit/v31-243-DELTA-SURFACE.md` (7 sections, any readable order)
- Whether to produce a per-commit "change count card" one-line summary for Phase 244 convenience
- Final Row ID prefix scheme (`D-243-C/F/S/X/I-NNN` vs flattened `D-243-NNN`)
- Inline vs companion-file split for oversized diff/grep output (soft threshold 50 rows for grep, 200 lines for diff)
- Whether DELTA-03 separates direct calls from delegatecall selectors in output
- Rationale format for REFACTOR_ONLY functions that changed local-variable ordering without changing SSTORE order

## Deferred Ideas

- Automated CI gate on deltas (future-milestone candidate)
- Cross-milestone delta chain audit (future tooling convenience)
- Row-count bounds enforcement (reconciliation via D-17 surfaces wildly divergent counts; no formal bounds locked)
