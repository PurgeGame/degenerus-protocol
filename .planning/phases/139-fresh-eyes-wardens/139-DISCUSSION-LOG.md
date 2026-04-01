# Phase 139: Fresh-Eyes Wardens - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-28
**Phase:** 139-fresh-eyes-wardens
**Areas discussed:** Warden scope, PoC depth, contract delivery

---

## Warden Scope and Cross-Domain Reporting

| Option | Description | Selected |
|--------|-------------|----------|
| Full scope | All wardens get all contracts, report anything important regardless of domain | ✓ |
| Domain-restricted | Wardens only see contracts relevant to their specialty | |
| Domain-primary | See all contracts but only report within their domain | |

**User's choice:** "full scope. if they find anything actually important need the full deal."
**Notes:** User wants no artificial boundaries — wardens should act like real C4A wardens who look at everything.

---

## PoC Depth

| Option | Description | Selected |
|--------|-------------|----------|
| Full Foundry PoC | Runnable Foundry tests with concrete calldata | ✓ |
| Pseudocode + calldata | Detailed pseudocode showing the attack path | |
| Narrative trace | Written explanation of the exploit path | |

**User's choice:** Implied by "full deal" — real Foundry PoCs required.

---

## Claude's Discretion

- Report structure/format (D-11)
