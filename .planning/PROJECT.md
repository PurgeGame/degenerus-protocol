# Degenerus Protocol — Audit Repository

## What This Is

Smart contract audit repository for the Degenerus Protocol — an on-chain ETH game with repeating levels, prize pools, BURNIE token economy, DGNRS/sDGNRS governance tokens, and a comprehensive deity pass system. Contains all protocol contracts, deploy scripts, tests (Hardhat + Foundry fuzz), and audit documentation.

## Core Value

Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.

## Requirements

### Validated

- ✓ v1.0 RNG security audit — VRF integration, manipulation windows, ticket selection
- ✓ v1.1 Economic flow audit — 13 reference docs covering all subsystems
- ✓ v1.2 RNG storage/function/data-flow deep dive
- ✓ v1.2 Delta attack reverification after code changes
- ✓ State-changing function audit — all external/public functions across all contracts
- ✓ Parameter reference — every named constant consolidated
- ✓ sDGNRS/DGNRS split implementation — soulbound + liquid wrapper architecture
- ✓ Audit doc sync — all 10 docs updated for sDGNRS/DGNRS split
- ✓ v2.1 Governance security audit — 26 verdicts covering all attack vectors — v2.1
- ✓ v2.1 M-02 closure — emergencyRecover eliminated, governance replaces single-admin authority — v2.1
- ✓ v2.1 War-game scenarios — 6 adversarial scenarios assessed with severity ratings — v2.1
- ✓ v2.1 Audit doc sync — all docs updated for governance, zero stale references — v2.1
- ✓ v2.1 Post-audit hardening — CEI fix, removed death clock pause + activeProposalCount — v2.1

### Active

## Current Milestone: v3.0 Full Contract Audit + Payout Specification

**Goal:** Comprehensive security audit of all Degenerus Protocol contracts with zero tolerance on every code path that moves ETH, stETH, BURNIE, DGNRS, or WWXRP, plus a complete payout specification document covering every distribution system.

**Target features:**
- GAMEOVER path audit (critical — terminal distribution, final sweep, death clock, distress mode)
- All payout/claim path audits (daily jackpot, decimator, coinflip, lootbox, quest, affiliate, stETH yield, deity refunds, bounties)
- Recent changes verification (VRF governance, deity non-transferability, parameter changes)
- Comment and documentation correctness (natspec, inline, storage layout, constants, parameter reference)
- Invariant verification (claimablePool, pool accounting, sDGNRS supply, BURNIE mint/burn, unclaimable funds)
- Edge case and griefing analysis (GAMEOVER at various levels, single player, gas griefing, timing attacks, rounding)
- Payout Specification HTML document covering 17+ distribution systems with diagrams and exact code references

### Deferred (v3.1+)

- [ ] Foundry fuzz invariant tests for governance (vote weight conservation, threshold monotonicity)
- [ ] Formal verification of vote counting arithmetic via Halmos
- [ ] Monte Carlo simulation of governance outcomes under various voter distributions

### Out of Scope

- Frontend code — not in audit scope
- Off-chain infrastructure — VRF coordinator is external
- Gas optimization beyond correctness — C4A QA findings are low-cost
- Governance UI/frontend — not in audit scope
- Off-chain vote aggregation — on-chain only governance
- Governance upgrade mechanisms — contract is immutable per spec

## Context

- Solidity 0.8.34, Hardhat + Foundry dual test stack
- 23 protocol contracts deployed in deterministic order via CREATE nonce prediction
- All contracts use immutable `ContractAddresses` library (addresses baked at compile time)
- VRF via Chainlink VRF v2 for randomness
- DegenerusStonk split into StakedDegenerusStonk (soulbound, holds reserves) + DegenerusStonk (transferable ERC20 wrapper)
- VRF governance: emergencyRecover replaced with sDGNRS-holder propose/vote/execute (M-02 mitigation). Touches DegenerusAdmin, AdvanceModule, GameStorage, Game, DegenerusStonk.
- Post-v2.1: death clock pause removed (unnecessary complexity), activeProposalCount removed (no on-chain consumer), _executeSwap CEI fixed

## Constraints

- **Audit target:** Code4rena competitive audit — findings cost real money
- **Compiler:** Solidity 0.8.34 (overflow protection built-in)
- **EVM target:** Paris (no PUSH0)

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Split DGNRS into sDGNRS + DGNRS wrapper | Enable secondary market for creator allocation while keeping game rewards soulbound | ✓ Good |
| Pool BPS rebalance (Whale 10%, Affiliate 35%, Lootbox 20%, Reward 5%, Earlybird 10%) | Better distribution alignment with game mechanics | ✓ Audited v2.0 |
| Coinflip bounty DGNRS gating (min 50k bet, 20k pool) | Prevent dust-amount bounty claims draining reward pool | ✓ Audited v2.0 |
| burnRemainingPools replacing burnForGame | Cleaner game-over cleanup, removes per-address burn authority | ✓ Audited v2.0 |
| Replace emergencyRecover with sDGNRS governance | M-02 mitigation: compromised admin key can no longer unilaterally control RNG | ✓ Audited v2.1, M-02 downgraded to Low |
| VRF retry timeout 18h → 12h | Faster recovery from stale VRF requests | ✓ Audited v2.1 |
| unwrapTo blocked during VRF stall | Prevents creator vote-stacking via DGNRS→sDGNRS conversion during governance | ✓ Audited v2.1 |
| Remove death clock pause for governance | Chainlink death + game death + 256 proposals is unrealistic; reduces complexity | ✓ Post-v2.1 |
| Remove activeProposalCount tracking | No on-chain consumer after death clock pause removal; eliminates uint8 overflow surface | ✓ Post-v2.1 |
| Move _voidAllActive before external calls | CEI compliance in _executeSwap; prevents theoretical sibling-proposal reentrancy | ✓ Post-v2.1 |

## Known Issues (Documented, Not Blocking)

| ID | Severity | Description |
|----|----------|-------------|
| WAR-01 | Medium | Compromised admin + 7-day community inattention enables coordinator swap |
| WAR-02 | Medium | Colluding voter cartel at day 6 (5% threshold) |
| WAR-06 | Low | Admin spam-propose gas griefing (no per-proposer cooldown) |

---
*Last updated: 2026-03-17 after v3.0 milestone start*
