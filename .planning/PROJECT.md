# Degenerus Protocol — Contract Audit & Modification Repo

## What This Is

The Degenerus Protocol is an on-chain game (Solidity 0.8.34, Foundry + Hardhat) where players buy tickets, compete in purchase/jackpot phases, and win ETH prizes. This audit repo holds the contract source for review and modification. v1.0 shipped always-open purchases — players can now buy tickets at any time, even during RNG processing and jackpot payouts.

## Core Value

Players can purchase tickets at any time — no downtime during RNG processing or jackpot payouts.

## Requirements

### Validated

- Existing game loop: purchase phase, jackpot phase, endgame — all working
- Ticket queue system (single-buffer) — working
- VRF-based RNG — working
- Prize pool split logic — working
- Lootbox, whale bundle, degenerette purchase paths — working
- ✓ Double-buffer ticket queues with bit-23 key encoding — v1.0
- ✓ Prize pool freeze/unfreeze with pending accumulators — v1.0
- ✓ Mid-day advanceGame path (swap only, no freeze) — v1.0
- ✓ Packed prize pool storage (uint128+uint128) — v1.0
- ✓ Remove rngLockedFlag purchase blocks — v1.0
- ✓ Revised advanceGame flow with drain gates — v1.0

### Active

(None — next milestone not yet planned)

### Out of Scope

- New game mechanics — infrastructure-only focus
- Frontend changes — contract-level only
- Token (DGNRS) changes — already soulbound, separate concern
- Gas optimization beyond packed pools — separate effort
- Legacy shim removal (54 call sites) — functional, cosmetic debt

## Context

- Contracts use delegatecall modules pattern (`contracts/modules/`)
- Storage layout in `contracts/storage/DegenerusGameStorage.sol` — all state lives here
- 27,465 LOC Solidity, 3,658 LOC tests (66 milestone-specific + 43 pre-existing passing)
- Key invariant: read slot must drain before any swap (hard gate)
- Jackpot phase keeps freeze active across all 5 draw days
- 54 legacy shim call sites remain in non-purchase modules (marked DEPRECATED, functional)
- 12 pre-existing deploy-dependent test failures (predate v1.0)

## Constraints

- **Storage layout**: Slot 1 has 5 bytes padding remaining after v1.0 additions
- **No proxy upgrade**: Fresh deploy assumed — storage slot renumbering acceptable
- **Solidity version**: 0.8.34
- **Testing**: Foundry test suite must pass after changes

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Bit-23 key encoding for double buffer | Avoids new mapping declarations, zero storage layout change | ✓ Good — clean, zero-overhead key separation |
| uint128 packing for prize pools | Saves 1 SSTORE per purchase, max 3.4e20 ETH far exceeds supply | ✓ Good — measurable gas savings |
| Freeze only at daily RNG, not mid-day | Mid-day processing doesn't touch jackpots/payouts | ✓ Good — simpler state machine |
| error E() centralized in DegenerusGameStorage | Solidity 0.8.34 forbids redeclaration in inheritance chain | ✓ Good — eliminated 9 duplicate declarations |
| prizePoolPendingPacked at Slot 16 (in-place replacement) | Avoids storage slot shifts across all modules | ✓ Good — zero layout disruption |
| Building-block test harnesses over full AdvanceModule harness | delegatecall + coin + VRF dependencies too complex for unit tests | ✓ Good — 66 focused tests with clean isolation |
| LOCK-02 preserves lastPurchaseDay+jackpotLevel block | Business rule independent of rngLockedFlag | ✓ Good — correct separation of concerns |

---
*Last updated: 2026-03-11 after v1.0 milestone completion*
