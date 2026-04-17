# Phase 230: Delta Extraction & Scope Map - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-17
**Phase:** 230-delta-extraction-scope-map
**Areas discussed:** Output file structure, Interaction map format, Interface drift verdict format, Consumer index

---

## Output File Structure

| Option | Description | Selected |
|--------|-------------|----------|
| A. Single `230-01-DELTA-MAP.md` | One consolidated file with three sections — matches v28.0 Phase 224 pattern for bounded scope | ✓ |
| B. Three files (`230-01-CHANGELOG.md` + `230-02-INTERACTION-MAP.md` + `230-03-INTERFACE-DRIFT.md`) | Matches v25.0 Phase 213 split pattern for large scope | |
| C. Per-commit section with theme subsections | Organize by the 10 in-scope commits | |

**User's choice:** A (recommended default — "all recommended")
**Notes:** 10 commits / 12 files is small enough to keep in one file. Matches v28.0 Phase 224 pattern the user previously validated.

---

## Interaction Map Format

| Option | Description | Selected |
|--------|-------------|----------|
| A. Mermaid call-graph diagram | Visual, not greppable | |
| B. Tabular: `Caller \| Callee \| Call Type \| Commit \| What Changed` | Greppable by downstream phases | ✓ |
| C. Narrative per call chain | Prose explanation of each chain | |

**User's choice:** B (recommended default)
**Notes:** Tabular matches the v25.0 Phase 213 style that worked well across phases 214-217.

---

## Interface Drift Verdict Format

| Option | Description | Selected |
|--------|-------------|----------|
| A. Per-method PASS/FAIL row | One row per signature across all three interfaces | ✓ |
| B. Per-contract verdict with method list | Contract-level summary with nested methods | |
| C. Just a diff summary | High-level summary without per-method rows | |

**User's choice:** A (recommended default)
**Notes:** Matches v27.0 Phase 220 delegatecall-alignment catalog style. Per-method resolution is what downstream audit agents need.

---

## Consumer Index

| Option | Description | Selected |
|--------|-------------|----------|
| A. Yes — include Consumer Index mapping each downstream requirement to relevant sections | Saves lookup work in phases 231-236 | ✓ |
| B. No — pure catalog, downstream phases do own lookups | Less upfront work in 230, more in 231-236 | |

**User's choice:** A (recommended default)
**Notes:** Pre-wiring the consumer map in 230 avoids repeated grep work across 6 downstream phases.

---

## Claude's Discretion

- Exact section ordering within 230-01 (changelog first vs interaction map first, etc.)
- Whether to produce a small companion commit↔file matrix for future agent reference
- How deeply to annotate "what changed semantically" per function

## Deferred Ideas

None — discussion stayed within phase scope.
