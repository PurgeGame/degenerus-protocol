# Phase 159: Storage Analysis & Architecture Design - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md -- this log preserves the alternatives considered.

**Date:** 2026-04-01
**Phase:** 159-storage-analysis-architecture-design
**Areas discussed:** Analysis depth, Struct packing scope, Caching mechanism, Cross-contract elimination approach
**Mode:** Auto (all recommended defaults selected)

---

## Analysis Depth

| Option | Description | Selected |
|--------|-------------|----------|
| Purchase-path only | Map SLOADs and calls only on _purchaseFor + _callTicketPurchase | |
| Purchase-path-first with all-consumer catalog | Map hot path in detail, enumerate all other consumers for compatibility | ✓ |
| All paths equally | Full analysis of every playerActivityScore consumer | |

**User's choice:** [auto] Purchase-path-first with all-consumer catalog (recommended default)
**Notes:** Purchase path is the optimization target (hottest gas path), but the design must list all 8 score consumers to ensure no non-purchase path breaks from structural changes.

---

## Struct Packing Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Score-only packing | Pack only score-related inputs (streak, mint count, pass type) | |
| Combined score+quest packing | Pack score inputs alongside quest state data | |
| Investigate both, recommend | Analyze both options and recommend based on gas savings vs complexity | ✓ |

**User's choice:** [auto] Investigate both, recommend based on savings vs complexity (recommended default)
**Notes:** Quest data lives in DegenerusQuests (separate contract) while score inputs are in DegenerusGame storage. Combined packing requires data co-location or parameter passing -- the analysis must determine if the savings justify the architectural change.

---

## Caching Mechanism

| Option | Description | Selected |
|--------|-------------|----------|
| Stack-passed parameters | Compute once, pass value through function call chain | ✓ |
| Internal storage cache | Write to a storage slot, read from other modules | |
| Transient storage (EIP-1153) | Write to transient storage, auto-cleared per tx | |

**User's choice:** [auto] Stack-passed parameters (recommended default)
**Notes:** Paris EVM target eliminates transient storage option. Internal storage cache costs 20K+2.1K gas (SSTORE+SLOAD), far worse than parameter passing. Stack-passed params are zero-cost after initial computation.

---

## Cross-Contract Call Elimination

| Option | Description | Selected |
|--------|-------------|----------|
| Parameter forwarding | Quest handlers return streak data; affiliate bonus passed from caller | ✓ |
| Data co-location | Duplicate quest streak / affiliate data into Game storage | |
| Accept the overhead | Keep cross-contract calls, just cache the score result | |

**User's choice:** [auto] Parameter forwarding as primary, co-location as fallback (recommended default)
**Notes:** Preserves contract boundaries, no storage duplication. If quest handlers already execute before score computation on the purchase path, they can return the streak for forwarding. Affiliate bonus may require co-location if no natural call order exists.

---

## Claude's Discretion

- Analysis methodology (static vs forge traces)
- Design spec document format and structure
- Packed struct bit allocation detail level
- Whether to include per-optimization gas savings estimates

## Deferred Ideas

None -- all discussion stayed within phase scope.
