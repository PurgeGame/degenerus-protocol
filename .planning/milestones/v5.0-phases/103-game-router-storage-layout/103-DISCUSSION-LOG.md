# Phase 103: Game Router + Storage Layout - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-25
**Phase:** 103-game-router-storage-layout
**Areas discussed:** Audit granularity, Storage verification, Report format, Cross-module coherence
**Mode:** --auto (all decisions auto-selected)

---

## Audit Granularity

| Option | Description | Selected |
|--------|-------------|----------|
| Router logic only | Trace delegatecall routing and access control; don't re-audit module internals (phases 104-117 cover those) | [auto] |
| Full trace into modules | Follow every delegatecall into module code within this phase | |
| Hybrid | Trace into modules for storage-write mapping only | |

**User's choice:** [auto] Router logic only (recommended default)
**Notes:** Module internals are covered in their respective phases. This phase proves the router dispatches correctly and the storage layout is sound.

---

## Storage Verification

| Option | Description | Selected |
|--------|-------------|----------|
| forge inspect + manual cross-reference | Use forge inspect for authoritative slots, cross-ref against manual comments | [auto] |
| Manual slot counting only | Count slots by hand from the Solidity source | |
| Assembly read verification | Verify via inline assembly patterns in the code | |

**User's choice:** [auto] forge inspect + manual cross-reference (recommended default)
**Notes:** forge inspect gives ground truth; manual cross-reference catches comment drift.

---

## Report Format

| Option | Description | Selected |
|--------|-------------|----------|
| ULTIMATE-AUDIT-DESIGN.md format | Per-function: call tree, storage-write map, cache check, attack analysis | [auto] |
| C4A-style findings only | Only produce findings documents, skip per-function analysis | |

**User's choice:** [auto] ULTIMATE-AUDIT-DESIGN.md format (recommended default)
**Notes:** The whole point of v5.0 is exhaustive per-function analysis.

---

## Cross-Module Coherence

| Option | Description | Selected |
|--------|-------------|----------|
| Prove layout here, defer alignment to Phase 118 | Verify DegenerusGameStorage is correct; per-module checks in integration sweep | [auto] |
| Full module alignment in this phase | Check all 10 modules for storage alignment now | |

**User's choice:** [auto] Prove layout here, defer alignment to Phase 118 (recommended default)
**Notes:** Phase 118 is specifically designed for cross-contract coherence verification.

---

## Claude's Discretion

- Function analysis ordering within the report
- Level of detail in delegatecall dispatch traces

## Deferred Ideas

None.
