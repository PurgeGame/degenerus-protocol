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

### Active

See current milestone.

### Out of Scope

- Frontend code — not in audit scope
- Off-chain infrastructure — VRF coordinator is external
- Gas optimization beyond correctness — C4A QA findings are low-cost

## Context

- Solidity 0.8.34, Hardhat + Foundry dual test stack
- 23 protocol contracts deployed in deterministic order via CREATE nonce prediction
- All contracts use immutable `ContractAddresses` library (addresses baked at compile time)
- VRF via Chainlink VRF v2 for randomness
- Recent major change: DegenerusStonk split into StakedDegenerusStonk (soulbound, holds reserves) + DegenerusStonk (transferable ERC20 wrapper)

## Constraints

- **Audit target:** Code4rena competitive audit — findings cost real money
- **Compiler:** Solidity 0.8.34 (overflow protection built-in)
- **EVM target:** Paris (no PUSH0)

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Split DGNRS into sDGNRS + DGNRS wrapper | Enable secondary market for creator allocation while keeping game rewards soulbound | ✓ Good |
| Pool BPS rebalance (Whale 10%, Affiliate 35%, Lootbox 20%, Reward 5%, Earlybird 10%) | Better distribution alignment with game mechanics | — Pending audit |
| Coinflip bounty DGNRS gating (min 50k bet, 20k pool) | Prevent dust-amount bounty claims draining reward pool | — Pending audit |
| burnRemainingPools replacing burnForGame | Cleaner game-over cleanup, removes per-address burn authority | — Pending audit |

---
*Last updated: 2026-03-16 after sDGNRS/DGNRS split and doc sync*
