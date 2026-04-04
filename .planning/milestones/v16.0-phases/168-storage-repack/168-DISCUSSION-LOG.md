# Phase 168: Storage Repack - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-02
**Phase:** 168-storage-repack
**Areas discussed:** Packing helpers, Slot 1 layout, Test update strategy
**Mode:** Auto (all areas auto-selected, recommended defaults chosen)

---

## Packing Helpers

| Option | Description | Selected |
|--------|-------------|----------|
| Getter/setter helpers | Match prizePoolsPacked pattern with _get/_set helpers | ✓ |
| Inline shift/mask | Direct bit manipulation at each access site | |

**User's choice:** [auto] Getter/setter helpers (recommended default)
**Notes:** Existing prizePoolsPacked pattern provides exact template. Keeps access patterns consistent.

---

## Slot 1 Layout

| Option | Description | Selected |
|--------|-------------|----------|
| Append after prizePoolFrozen | Natural declaration order: purchaseStartDay + ticketWriteSlot + prizePoolFrozen + currentPrizePool | ✓ |
| Before prizePoolFrozen | Alternative ordering for alignment | |

**User's choice:** [auto] Append after prizePoolFrozen (recommended default)
**Notes:** Follows Solidity's sequential packing rule. Natural order.

---

## Test Update Strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Update individually | Fix each of ~16 test files with hardcoded offsets | ✓ |
| Centralize constants | Create shared SlotConstants helper | |

**User's choice:** [auto] Update individually (recommended default)
**Notes:** One-time mechanical fix. Centralizing constants adds abstraction for a non-recurring need.

---

## Claude's Discretion

- Helper implementation details (bit shifts, masks)
- Comment formatting and NatSpec style
- uint128 safety analysis (straightforward — total ETH supply << uint128 max)
