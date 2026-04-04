# Phase 168: Storage Repack - Context

**Gathered:** 2026-04-02
**Status:** Ready for planning

<domain>
## Phase Boundary

Repack EVM slots 0-2 in DegenerusGameStorage.sol:
- Move ticketsFullyProcessed + gameOverPossible from slot 1 to slot 0 (fills 2-byte padding to 32/32)
- Downsize currentPrizePool from uint256 (slot 2) to uint128, pack into slot 1
- Kill slot 2 entirely
- Update all access patterns, helpers, comments, and test offsets

</domain>

<decisions>
## Implementation Decisions

### Packing Strategy
- **D-01:** currentPrizePool gets dedicated `_getCurrentPrizePool()` / `_setCurrentPrizePool()` helpers using shift/mask operations, matching the existing prizePoolsPacked pattern. Direct reads/writes of currentPrizePool are replaced with helper calls across all 3 consuming contracts (JackpotModule, GameOverModule, DegenerusGame).

### Slot 1 Layout
- **D-02:** currentPrizePool (uint128) appends after prizePoolFrozen in slot 1. Final layout:
  - [0:6] purchaseStartDay (uint48)
  - [6:7] ticketWriteSlot (uint8)
  - [7:8] prizePoolFrozen (bool)
  - [8:24] currentPrizePool (uint128)
  - [24:32] padding (8 bytes)

### Test Update Strategy
- **D-03:** Update all ~16 Foundry test files with hardcoded vm.load/vm.store slot offsets individually. No centralized slot constants helper — mechanical one-time fix.

### uint128 Safety
- **D-04:** uint128 max is ~3.4e38 wei (~3.4e20 ETH). Total ETH supply is ~1.2e8 ETH. currentPrizePool will never approach this limit. No overflow guard needed beyond Solidity's built-in checks.

### Slot 0 Layout (after repack)
- **D-05:** Final slot 0 layout (32/32 bytes):
  - [0:6] levelStartTime (uint48)
  - [6:12] dailyIdx (uint48)
  - [12:18] rngRequestTime (uint48)
  - [18:21] level (uint24)
  - [21:22] jackpotPhaseFlag (bool)
  - [22:23] jackpotCounter (uint8)
  - [23:24] lastPurchaseDay (bool)
  - [24:25] decWindowOpen (bool)
  - [25:26] rngLockedFlag (bool)
  - [26:27] phaseTransitionActive (bool)
  - [27:28] gameOver (bool)
  - [28:29] dailyJackpotCoinTicketsPending (bool)
  - [29:30] compressedJackpotFlag (uint8)
  - [30:31] ticketsFullyProcessed (bool) ← moved from slot 1
  - [31:32] gameOverPossible (bool) ← moved from slot 1

### Claude's Discretion
- Helper implementation details (bit shifts, masks) — follow prizePoolsPacked as template
- Comment formatting and NatSpec style — match existing conventions

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Storage Layout
- `contracts/storage/DegenerusGameStorage.sol` — Canonical storage layout, all slot comments, get/set helpers
- `.planning/research/STACK.md` — Solidity 0.8.34 packing rules, forge inspect procedures
- `.planning/research/ARCHITECTURE.md` — Storage access patterns by module, integration points

### Access Sites (currentPrizePool)
- `contracts/modules/DegenerusGameJackpotModule.sol` — Lines 317, 353, 433, 721, 732, 737, 747 (primary consumer)
- `contracts/modules/DegenerusGameGameOverModule.sol` — Lines 133, 145 (zeroed at gameover)
- `contracts/DegenerusGame.sol` — Lines 2035-2037 (view), 2063 (obligations)

### Test Blast Radius
- `test/fuzz/StorageFoundation.t.sol` — Storage layout assertions (critical — must pass post-repack)
- 15 additional test files with vm.load/vm.store — see grep for `vm.load|vm.store` in test/

### Pitfalls
- `.planning/research/PITFALLS.md` — Slot shift cascade, assembly hardcoding risks

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `_getPrizePools()` / `_setPrizePools()` in DegenerusGameStorage.sol — Template for currentPrizePool packing helpers (uses shift/mask on prizePoolsPacked uint256)
- `_swapAndFreeze()` / `_unfreezePool()` — Already reads/writes slot 1 fields; must be updated for new layout

### Established Patterns
- All packed storage access goes through `_get*()` / `_set*()` internal helpers
- prizePoolsPacked stores two uint128 values in one uint256 — exact same pattern needed for currentPrizePool in slot 1
- `forge inspect` verification after every storage change (established in v7.0+)

### Integration Points
- Every delegatecall module inherits DegenerusGameStorage — layout change propagates automatically via compilation
- currentPrizePoolView() in DegenerusGame.sol must return uint256 (external ABI stability) — helper handles upcast

</code_context>

<specifics>
## Specific Ideas

- User already has uncommitted changes removing poolConsolidationDone (freed 1 byte in slot 0, now 2 bytes padding) — repack builds on that
- Slot 1 header comment is already stale (shows 2 bools, actually has 3) — fix as part of this phase

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 168-storage-repack*
*Context gathered: 2026-04-02*
