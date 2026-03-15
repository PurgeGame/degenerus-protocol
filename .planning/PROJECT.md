# Degenerus Protocol — Contract Audit & Modification Repo

## What This Is

The Degenerus Protocol is an on-chain game (Solidity 0.8.34, Foundry + Hardhat) where players buy tickets, compete in purchase/jackpot phases, and win ETH prizes. This audit repo holds the contract source for review and modification. v1.0 shipped always-open purchases. v1.1 produced comprehensive economic flow documentation. v1.2 completed an exhaustive RNG security audit confirming no manipulation windows exist between VRF arrival and consumption.

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
- ✓ Complete RNG variable inventory (9 direct + 22 influencing) with EVM slots, types, lifecycle traces — v1.2
- ✓ RNG function catalogue (60+ functions, 27 entry points, 7 guard types) — v1.2
- ✓ All 8 v1.0 attack scenarios re-verified (all PASS, no regressions) — v1.2
- ✓ 13 manipulation windows analyzed (4 BLOCKED, 9 SAFE BY DESIGN, 0 EXPLOITABLE) — v1.2
- ✓ Ticket creation and mid-day RNG flows verified manipulation-resistant — v1.2

### Active

(None — next milestone not yet defined)

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
- v1.1 output: 13 reference documents in `audit/v1.1-*.md` (8,511 lines)
- v1.2 output: 8 RNG audit documents in `audit/v1.2-*.md` (3,502 lines) — 0 exploitable windows, all attack scenarios PASS

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
| 8-field template per RNG consumption point | Consistent analysis structure across 17 points enables comparison | ✓ Good — enabled clean verdict consolidation |
| Separate daily vs lootbox adversarial timelines | Different temporal models (two-phase commit vs direct-finalize) | ✓ Good — distinct threat models documented |
| Frozen read buffer as structural commit-reveal for ticket RNG | Security based on buffer isolation, not entropy secrecy | ✓ Good — robust against known-entropy scenarios |

---
*Last updated: 2026-03-14 after v1.2 milestone completion*
