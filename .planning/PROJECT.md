# Degenerus Protocol Security Audit

## What This Is

A comprehensive security review of the Degenerus Protocol smart contract suite — 22 deployable contracts and 10 delegatecall game modules implementing a multi-level ticket purchasing game with VRF-based randomness, prize pools, lootboxes, whale mechanics, and ERC20/ERC721 tokens. The deliverable is a prioritized findings report covering RNG handling, accounting integrity, and full attack surface analysis.

## Core Value

Every ETH that enters the protocol must be accounted for, every RNG outcome must be unmanipulable, and no actor — whale, Sybil group, or block proposer — can extract value beyond what the game mechanics intend.

## Requirements

### Validated

- ✓ 22-contract protocol deployed via nonce-predicted addresses — existing
- ✓ Delegatecall module pattern with shared storage layout — existing
- ✓ Chainlink VRF V2.5 integration for randomness — existing
- ✓ RNG lock state machine (request → fulfill → unlock) — existing
- ✓ Ticket purchase with price escalation curves — existing
- ✓ Prize pool split (90% current / 10% future) — existing
- ✓ Pull-pattern ETH/stETH withdrawals — existing
- ✓ Whale bundles, lazy passes, deity passes with pricing formulas — existing
- ✓ Lootbox EV multiplier based on activity score — existing
- ✓ Degenerette betting and resolution — existing
- ✓ BurnieCoin ERC20 with coinflip mechanics — existing
- ✓ Affiliate referral tracking and bonus points — existing
- ✓ Quest streak system with activity score component — existing
- ✓ 884 tests passing (unit, integration, access control, edge cases) — existing

### Active

- [ ] RNG manipulation analysis — can actors predict, influence, or exploit VRF outcomes?
- [ ] RNG state machine integrity — stuck states, reentrancy, race conditions in request/fulfill lifecycle
- [ ] ETH flow accounting — can funds get stuck, drained, or misallocated across prize pools?
- [ ] Token/pass math verification — ticket pricing, whale bundles, deity passes, lootbox EV formulas
- [ ] Fee split integrity — do all percentage splits sum correctly across all code paths?
- [ ] Delegatecall storage safety — slot collision risks across 10 modules
- [ ] Access control audit — privilege escalation, operator approval abuse
- [ ] Cross-contract interaction safety — reentrancy, callback manipulation, flash loan vectors
- [ ] Validator/MEV attack surface — tx reordering, censorship, sandwich attacks on game state
- [ ] Sybil/collusion analysis — coordinated multi-wallet strategies to extract excess value
- [ ] Edge case accounting — game over settlement, stall recovery, timeout distributions

### Out of Scope

- Gas optimization — separate concern, not security-relevant
- Frontend/off-chain code — contracts only
- Testnet-specific contracts — mainnet deployment is the target
- Mock contracts — test infrastructure only
- Deployment scripts — operational, not security surface

## Context

- Solidity 0.8.26/0.8.28 with viaIR, optimizer runs=2
- All contracts under 24KB (DegenerusGame largest at 19KB)
- Storage layout shared across main contract and all delegatecall modules via DegenerusGameStorage
- ContractAddresses uses compile-time constants (all address(0) in source, patched at deploy)
- Deploy order is critical: modules (N+0..10) → COIN (N+11) → COINFLIP (N+12) → GAME (N+13) → ... → ADMIN (N+21)
- External dependencies: Chainlink VRF V2.5, Lido stETH, LINK token
- Game is a 2-state FSM: PURCHASE ↔ JACKPOT with terminal gameOver
- RNG lock prevents state changes during VRF callback window (18h timeout mainnet)
- Custom errors throughout (no revert strings), generic `E()` for most guards

## Constraints

- **Threat model**: 1000 ETH whale + coordinated Sybil group + block proposer/validator
- **Scope**: All 22 mainnet contracts, all 10 delegatecall modules
- **Output**: Prioritized findings report with severity ratings and remediation guidance
- **Compiler**: Solidity 0.8.x with built-in overflow protection (no SafeMath needed)

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Full protocol scope (not targeted) | Interactions between contracts are where bugs hide | — Pending |
| Validator-level threat model | Strongest realistic attacker for on-chain game | — Pending |
| Findings report without code fixes | User wants assessment first, fixes separately | — Pending |

---
*Last updated: 2026-02-28 after initialization*
