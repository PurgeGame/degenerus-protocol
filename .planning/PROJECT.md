# Degenerus Protocol — Contract Audit & Modification Repo

## What This Is

The Degenerus Protocol is an on-chain game (Solidity 0.8.34, Foundry + Hardhat) where players buy tickets, compete in purchase/jackpot phases, and win ETH prizes. This audit repo holds the contract source for review and modification. v1.0 shipped always-open purchases. v1.1 produced comprehensive economic flow documentation — 13 reference documents covering every ETH/BURNIE flow, jackpot mechanic, reward system, and protocol constant with exact formulas verified against contract source.

## Core Value

Players can purchase tickets at any time — no downtime during RNG processing or jackpot payouts.

## Requirements

### Validated

- ✓ Existing game loop: purchase phase, jackpot phase, endgame — all working
- ✓ Ticket queue system (single-buffer) — working
- ✓ VRF-based RNG — working
- ✓ Prize pool split logic — working
- ✓ Lootbox, whale bundle, degenerette purchase paths — working
- ✓ Double-buffer ticket queues with bit-23 key encoding — v1.0
- ✓ Prize pool freeze/unfreeze with pending accumulators — v1.0
- ✓ Mid-day advanceGame path (swap only, no freeze) — v1.0
- ✓ Packed prize pool storage (uint128+uint128) — v1.0
- ✓ Remove rngLockedFlag purchase blocks — v1.0
- ✓ Revised advanceGame flow with drain gates — v1.0
- ✓ Complete ETH flow analysis with exact formulas for all 9 purchase paths — v1.1
- ✓ Complete BURNIE flow analysis with coinflip, earning, burning, vault mechanics — v1.1
- ✓ Purchase type breakdown with pool split tables for all conditions — v1.1
- ✓ Level length dynamics with price curves and pass economics — v1.1
- ✓ Jackpot phase mechanics with 5-day draws, trait buckets, BAF/Decimator — v1.1
- ✓ Death clock and endgame flows with terminal distribution formulas — v1.1
- ✓ Parameter reference with ~200+ constants, values, units, and locations — v1.1

### Active

## Current Milestone: v1.2 RNG Security Audit

**Goal:** Exhaustive audit of every variable and function touching RNG — confirm no manipulation window exists between RNG arrival and consumption, with delta focus on changes since v1.0 audit.

**Target features:**
- Complete inventory of all RNG-touching variables and functions
- Adversarial analysis of manipulation windows (RNG known → RNG consumed)
- Delta verification against v1.0 audit findings for 8 changed contract files
- Deep focus on ticket creation flows and mid-day RNG processing
- Verification of new `lastLootboxRngWord` and `midDayTicketRngPending` state variables

### Out of Scope

- Frontend changes — contract-level analysis only
- Gas optimization — separate effort
- Legacy shim removal (54 call sites) — functional, cosmetic debt

## Context

- Contracts use delegatecall modules pattern (`contracts/modules/`)
- Storage layout in `contracts/storage/DegenerusGameStorage.sol` — all state lives here
- 27,465 LOC Solidity, 3,658 LOC tests (66 milestone-specific + 43 pre-existing passing)
- Key invariant: read slot must drain before any swap (hard gate)
- Jackpot phase keeps freeze active across all 5 draw days
- 54 legacy shim call sites remain in non-purchase modules (marked DEPRECATED, functional)
- 12 pre-existing deploy-dependent test failures (predate v1.0)
- v1.1 output: 13 reference documents in `audit/v1.1-*.md` (8,511 lines total) — designed for game theory agent consumption with exact Solidity expressions, worked examples, and simulation pseudocode

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
| v1.1 docs structured by purchase type, not contract file | Agent consumption prioritizes economic flow over code layout | ✓ Good — 13 focused reference docs |
| Worked examples + simulation pseudocode in jackpot docs | Game theory agents need computable examples, not just formulas | ✓ Good — directly consumable |
| Separated BURNIE-denominated from ETH constants in parameter ref | Prevents ether-suffix unit confusion for agent consumers | ✓ Good — clear unit boundaries |

---
*Last updated: 2026-03-14 after v1.2 milestone start*
