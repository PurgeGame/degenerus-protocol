# Phase 1: Storage Foundation - Context

**Gathered:** 2026-03-11
**Status:** Ready for planning

<domain>
## Phase Boundary

Add all new storage fields, packed pool slots, key encoding helpers, and swap/freeze/unfreeze functions to DegenerusGameStorage.sol. This phase delivers the foundation that all subsequent phases build on. No module migration or advanceGame changes — only Storage.

</domain>

<decisions>
## Implementation Decisions

### Slot 1 Placement
- Field order: `ticketWriteSlot` (uint8) at byte 18, `ticketsFullyProcessed` (bool) at byte 19, `prizePoolFrozen` (bool) at byte 20 — exactly as the plan specifies
- Full NatSpec documentation matching existing Slot 1 field style (4-5 lines each with @dev, purpose, security notes)
- Update BOTH the top-of-file overview ASCII diagram (lines ~49-66) AND the inline section header comment near the variable declarations

### Pool Migration
- `prizePoolsPacked` replaces `nextPrizePool` in-place (currently slot ~5, line 308) — keeps it near `currentPrizePool`
- `prizePoolPendingPacked` goes immediately after `prizePoolsPacked` — adjacent packed pool slots
- `futurePrizePool` declaration (line 409) removed entirely — no comment placeholder, clean deletion
- All packed helper functions (`_getPrizePools`, `_setPrizePools`, `_getPendingPools`, `_setPendingPools`) are `internal` visibility — modules need them via delegatecall inheritance

### Error Pattern
- Use existing `revert E()` pattern for all new revert sites (e.g., the hard gate in `_swapTicketSlot`)
- No new named custom errors — matches codebase convention of single gas-minimal error
- Reuse existing `error E()` declaration already visible to modules

### Claude's Discretion
- Exact NatSpec wording for new fields and helpers (matching existing tone/style)
- Whether to group the new helper functions in a dedicated section or place near related storage vars
- Internal ordering of helper function declarations

</decisions>

<specifics>
## Specific Ideas

- The plan document (`audit/PLAN-ALWAYS-OPEN-PURCHASES.md`) has exact Solidity snippets for all helpers — use those as the starting point
- `dailyTicketBudgetsPacked` (line 331) is an existing precedent for the uint128+uint128 packing pattern in this codebase
- `ticketWriteSlot` must be `uint8` not `bool` — the XOR toggle `ticketWriteSlot ^= 1` requires numeric type

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `BitPackingLib` imported at line 7 — already used for bit manipulation, though packed pool helpers are simpler inline shifts
- `GameTimeLib` imported at line 8 — not directly relevant to this phase

### Established Patterns
- Storage variables are grouped by slot with ASCII art layout diagrams and byte-offset comments
- Each variable has detailed NatSpec with @dev, purpose description, and SECURITY notes
- Helper functions (`_queueTickets`, `_queueTicketsScaled`, `_queueTicketRange`) live in the same Storage file near related mappings
- All storage helpers use `internal` visibility
- `unchecked` blocks used for safe arithmetic optimizations

### Integration Points
- DegenerusGameStorage is inherited by DegenerusGame and all delegatecall modules — any change here propagates to all
- `nextPrizePool` has ~50+ references across 11 files — removal will cause compile errors until Phase 2 migrates them
- `futurePrizePool` has ~50+ references — same situation
- Phase 1 should add the helpers but NOT yet remove the old variables if that would break compilation of modules. Alternative: remove old vars and add temporary compatibility shims, OR do a full find-replace in this phase. Decision for planner.

</code_context>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 01-storage-foundation*
*Context gathered: 2026-03-11*
