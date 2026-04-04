# Phase 160: Score & Quest Handler Consolidation - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-01
**Phase:** 160-Score & Quest Handler Consolidation
**Areas discussed:** Handler merging approach, mintPrice passthrough scope, Batched quest writes scope, handleDegenerette bug

---

## Handler Merging Approach

| Option | Description | Selected |
|--------|-------------|----------|
| New handlePurchase | Single external function taking both mint qty and lootbox amount. Loads state once, processes both quest types, writes once. Non-purchase handlers untouched. Cleanest gas savings. | ✓ |
| Keep separate, optimize internals | Keep handleMint + handleLootBox as separate calls but extract shared state loading into a cached struct pattern. Less interface change, but still 2 external calls per lootbox purchase. | |
| Thin wrapper delegates to both | New handlePurchase that calls handleMint + handleLootBox internally. Saves one external call but still duplicates internal state loading. | |

**User's choice:** New handlePurchase (Recommended)
**Notes:** Cleanest approach — single call, single state load, single write.

---

## mintPrice Passthrough Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Purchase path only | Only handlePurchase gets the mintPrice param. handleDegenerette keeps its own callback. Minimal interface churn. | |
| All ETH-aware handlers | Add mintPrice param to handleDegenerette too. Saves one extra STATICCALL on degenerette bets. More consistent interface. | ✓ |
| Remove standalone handleMint/handleLootBox | Since handlePurchase replaces them on the purchase path, remove the old functions entirely. | |

**User's choice:** All ETH-aware handlers
**Notes:** User prefers consistent interface — all handlers that need mintPrice get it as a parameter.

---

## Batched Quest Writes Scope

| Option | Description | Selected |
|--------|-------------|----------|
| All 6 handlers | Refactor the shared internals so daily + level quest writes are batched. Every handler benefits since they all call the same shared helpers. | ✓ |
| Purchase-path handler only | Only handlePurchase gets batched writes. Other handlers keep separate writes. Less code churn. | |
| Claude's discretion | Let the planner decide based on complexity once it reads the internals. | |

**User's choice:** All 6 handlers (Recommended)
**Notes:** Since shared helpers are used by all handlers, refactoring at the helper level propagates universally.

---

## handleDegenerette Bug

**Investigation result:** False alarm. The function uses named return variables (`reward`, `questType`, `streak`, `completed`) set by `_questHandleProgressSlot` at L787. The implicit return at L801 correctly returns these named variables. No bug.

---

## Claude's Discretion

- Return value structure from `_callTicketPurchase` (multiple returns vs struct)
- Parameter naming conventions
- Whether standalone `handleMint` / `handleLootBox` are removed or kept
- Plan decomposition and ordering
- `handlePurchase` detailed signature beyond the decided parameters

## Deferred Ideas

None — discussion stayed within phase scope
