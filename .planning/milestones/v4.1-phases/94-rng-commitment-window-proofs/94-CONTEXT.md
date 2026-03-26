# Phase 94: RNG Commitment Window Proofs - Context

**Gathered:** 2026-03-23
**Status:** Ready for planning
**Mode:** Auto-generated (infrastructure phase — discuss skipped)

<domain>
## Phase Boundary

Prove that the ticket double-buffer architecture and rngLocked guard make jackpot resolution immune to permissionless ticket manipulation during VRF pending windows. Deliverables are Foundry tests proving write-slot isolation plus a formal analytical proof document covering mutation surfaces.

Requirements: RNG-01, RNG-02, RNG-03, RNG-04

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion
All implementation choices are at Claude's discretion — pure infrastructure phase.

Key constraints from user:
- advanceGame is NOT permissionless — it's the resolver, not a manipulation vector. RNG requirements concern player-controlled INPUT actions (purchase, lootbox, whale bundle) that change state between VRF request and fulfillment.
- Purchase routing ALWAYS writes to write slot regardless of rngLocked state — this is the STRUCTURAL guarantee (double-buffer), not rngLocked.
- rngLocked blocks FF key writes specifically (prevents far-future manipulation during VRF window).
- Mid-day RNG (lootbox VRF) can also resolve tickets, and rng is NOT locked during mid-day — the double-buffer still protects because purchases go to write slot.

### Prior Art
- v3.8 Phases 68-72: Full VRF commitment window audit — 55 variables, 87 permissionless paths, 51/51 SAFE
- v3.8 covered ticketQueue/traitBurnTicket in the general proof (CW-01 through CW-04, MUT-01 through MUT-03)
- v3.9 Phase 79: RNG commitment window proof for far-future ticket paths specifically
- Phase 94 needs to prove the NEW ticket routing logic (unified boundary, last-day fix) preserves these guarantees

</decisions>

<code_context>
## Existing Code Insights

### Double-Buffer Architecture
- _tqWriteKey(lvl): ticketWriteSlot != 0 ? lvl | TICKET_SLOT_BIT : lvl (DGS:686-688)
- _tqReadKey(lvl): ticketWriteSlot == 0 ? lvl | TICKET_SLOT_BIT : lvl (DGS:691-692)
- _swapAndFreeze(purchaseLevel): ticketWriteSlot ^= 1 (DGS:712) — write becomes read
- Key insight: write key and read key are ALWAYS different bit 23 spaces. Purchases go to write key. Jackpot resolution reads from read key. No overlap possible.

### rngLocked Guard
- In _queueTickets (DGS:544-546): `if (isFarFuture && rngLockedFlag && !phaseTransitionActive) revert RngLocked()`
- Same guard in _queueTicketsScaled (DGS:572-574) and _queueTicketRange (DGS:621-623)
- Blocks FF writes from external callers during VRF pending, but allows phaseTransitionActive writes (advanceGame-internal)

### traitBurnTicket Mutation
- Written by processFutureTicketBatch (MintModule) via _raritySymbolBatch during advanceGame
- Written by processTicketBatch (JackpotModule) during advanceGame
- NOT writable by any permissionless external call (purchase, lootbox, whale)
- Read by jackpot winner selection functions during advanceGame

### Integration Points
- test/fuzz/TicketLifecycle.t.sol — existing 20 tests + helpers from Phases 92-93
- test/fuzz/TicketRouting.t.sol — TicketRoutingHarness with rngLocked guard tests

</code_context>

<specifics>
## Specific Ideas

- RNG-01/02 are analytical proofs — enumerate all permissionless paths and show none can mutate read-slot ticketQueue or traitBurnTicket. Can be documented in a proof file AND/OR verified with Foundry tests.
- RNG-03 can be tested with the existing TicketRoutingHarness (already has testRngGuardRevertsOnFFKey). Phase 94 adds integration-level verification.
- RNG-04 is testable: buy tickets in various states and assert all entries land in write key, never read key.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>
