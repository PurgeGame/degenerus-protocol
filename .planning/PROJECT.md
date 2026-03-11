# Degenerus Protocol — Always-Open Purchases

## What This Is

The Degenerus Protocol is an on-chain game (Solidity 0.8.34, Foundry + Hardhat) where players buy tickets, compete in purchase/jackpot phases, and win ETH prizes. This audit repo holds the contract source for review and modification. The current work eliminates purchase downtime by double-buffering ticket queues so players can always buy.

## Core Value

Players can purchase tickets at any time — no downtime during RNG processing or jackpot payouts.

## Current Milestone: v1.0 Always-Open Purchases

**Goal:** Implement the double-buffer ticket queue system so purchases never revert due to `rngLockedFlag`, with prize pool freeze to protect jackpot payout integrity.

**Target features:**
- Double-buffered ticket queues (write slot / read slot separation)
- Prize pool freeze during daily processing (pending accumulators)
- Mid-day processing path for large queues
- Packed prize pool storage (gas optimization)
- Remove `rngLockedFlag` purchase reverts

## Requirements

### Validated

- Existing game loop: purchase phase, jackpot phase, endgame — all working
- Ticket queue system (single-buffer) — working
- VRF-based RNG — working
- Prize pool split logic — working
- Lootbox, whale bundle, degenerette purchase paths — working

### Active

- [ ] Double-buffer ticket queues with bit-23 key encoding
- [ ] Prize pool freeze/unfreeze with pending accumulators
- [ ] Mid-day advanceGame path (swap only, no freeze)
- [ ] Packed prize pool storage (uint128+uint128)
- [ ] Remove rngLockedFlag purchase blocks
- [ ] Revised advanceGame flow with drain gates

### Out of Scope

- New game mechanics — this is infrastructure only
- Frontend changes — contract-level only
- Token (DGNRS) changes — already soulbound, no further work
- Gas optimization beyond the packed pools — separate effort

## Context

- Contracts use delegatecall modules pattern (`contracts/modules/`)
- Storage layout in `contracts/storage/DegenerusGameStorage.sol` — all state lives here
- The plan (`audit/PLAN-ALWAYS-OPEN-PURCHASES.md`) is comprehensive and implementation-ready
- Key invariant: read slot must drain before any swap (hard gate)
- Jackpot phase keeps freeze active across all 5 draw days

## Constraints

- **Storage layout**: New fields must fit in existing Slot 1 padding (3 bytes available)
- **No proxy upgrade**: Fresh deploy assumed — storage slot renumbering acceptable
- **Solidity version**: 0.8.34
- **Testing**: Foundry test suite must pass after changes

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Bit-23 key encoding for double buffer | Avoids new mapping declarations, zero storage layout change | — Pending |
| uint128 packing for prize pools | Saves 1 SSTORE per purchase, max 3.4e20 ETH far exceeds supply | — Pending |
| Freeze only at daily RNG, not mid-day | Mid-day processing doesn't touch jackpots/payouts | — Pending |

---
*Last updated: 2026-03-11 after milestone v1.0 initialization*
