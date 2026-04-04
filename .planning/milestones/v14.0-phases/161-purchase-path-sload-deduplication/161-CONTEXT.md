# Phase 161: Purchase Path SLOAD Deduplication - Context

**Gathered:** 2026-04-02
**Status:** Ready for planning

<domain>
## Phase Boundary

Each of the remaining hot-path storage variables is read exactly once per purchase transaction and cached for all subsequent consumers. Mechanical caching via local variables and parameter passing — no structural changes.

**Post-Phase 160.1 changes:** `price` storage variable was removed (replaced with PriceLookupLib.priceForLevel). `purchaseLevel` is now jackpot-aware. `level` is still read from storage multiple times and needs caching. Original 6-variable scope reduced to 5.

</domain>

<decisions>
## Implementation Decisions

### Caching Strategy (all from Phase 159 Architecture Spec §6)
- **D-01:** All caching via stack local variables and parameter passing. No transient storage (Paris EVM).
- **D-02:** `level` (Slot 0) — read once in `_purchaseFor` entry, used to derive `purchaseLevel` and passed as parameter to `_callTicketPurchase`. Lootbox path uses `level + 1` (now explicit after 160.1). Eliminates multiple warm SLOADs.
- **D-03:** ~~`price` (Slot 1)~~ — **REMOVED by Phase 160.1.** `price` storage variable no longer exists. All pricing uses `PriceLookupLib.priceForLevel()` (pure function, no SLOAD). This requirement is satisfied.
- **D-04:** `compressedJackpotFlag` (Slot 0) — read once at `_callTicketPurchase` entry, local variable. Eliminates 2 warm SLOADs (~200 gas).
- **D-05:** `jackpotCounter` (Slot 0) — read once at `_callTicketPurchase` entry, local variable. Eliminates 1 warm SLOAD (~100 gas).
- **D-06:** `jackpotPhaseFlag` (Slot 0) — read once at `_callTicketPurchase` entry, local variable. Eliminates 1 warm SLOAD (~100 gas).
- **D-07:** `claimableWinnings[buyer]` — read once in `_purchaseFor` entry, local variable reused in shortfall branch. Eliminates 1-2 warm SLOADs (~100-200 gas).

### Claude's Discretion
- Parameter naming and ordering
- Whether Slot 0 fields are read via a single assembly SLOAD or individual Solidity reads (both valid)
- Plan decomposition

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Architecture Spec
- `.planning/phases/159-storage-analysis-architecture-design/159-01-ARCHITECTURE-SPEC.md` §6 — SLOAD dedup catalog with exact line numbers, read counts, and caching strategies

### Purchase Path (files to modify)
- `contracts/modules/DegenerusGameMintModule.sol` — `_purchaseFor` and `_callTicketPurchase`

### Storage Layout
- `contracts/storage/DegenerusGameStorage.sol` — Slot 0/1 variable declarations

</canonical_refs>

<code_context>
## Existing Code Insights

### Established Patterns
- Phase 160 already passes `questStreak` and `cachedScore` through the purchase path via parameters — same pattern extends to SLOAD caching
- `_purchaseFor` already reads `level` and `price` at entry; some consumers re-read from storage instead of using the local

### Integration Points
- `_purchaseFor` → `_callTicketPurchase` parameter boundary is the main interface to extend
- Lootbox path within `_purchaseFor` also needs cached values

</code_context>

<specifics>
## Specific Ideas

No specific requirements — mechanical caching per architecture spec catalog.

</specifics>

<deferred>
## Deferred Ideas

None — phase scope is self-contained.

</deferred>

---

*Phase: 161-purchase-path-sload-deduplication*
*Context gathered: 2026-04-02*
