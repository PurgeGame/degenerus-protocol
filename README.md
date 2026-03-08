# Degenerus Protocol — Audit Repository

Consolidated smart contract repository for the [Degenerus Protocol](https://degener.us), prepared for competitive audit submission.

## Overview

Degenerus is an on-chain elimination game on Ethereum. Players buy tickets to enter. Each round, a portion of players are eliminated via VRF-driven randomness. Survivors advance, ticket prices escalate, and the prize pool grows. Jackpots, lootboxes, deity boons, and mini-games layer on top. When the dust settles, the last players standing split the pot.

- **22 deployable contracts**, 12 delegatecall game modules sharing storage via `DegenerusGameStorage`
- Solidity 0.8.26 / 0.8.28, `viaIR` enabled, optimizer runs = 200
- All contracts under 24KB (DegenerusGame largest at 19KB)
- External dependencies: Chainlink VRF V2.5, Lido stETH, LINK token
- Pull-pattern ETH/stETH withdrawals (no push payments)

## Repository History

This repo consolidates the full development history of the Degenerus Protocol:

| Era | Dates | Commits | Description |
|-----|-------|---------|-------------|
| Purge Game v1 | Mar 2022 — Jan 2025 | 196 | Original game contracts (PurgeGame.sol, PurgedCoin.sol) |
| Purge Game v2 | Oct 2025 — Jan 2026 | 728 | Modular rewrite with delegatecall architecture |
| Degenerus Protocol | Feb 2026 — present | 469 | Current protocol with full test suite and audit |

## Build

```bash
npm install
npx hardhat compile
```

Requires Node.js 18+.

## Test

```bash
# Hardhat tests (884 tests)
npx hardhat test

# Foundry invariant fuzzing
forge test
```

## Architecture

```
DegenerusGame.sol (main entry point, delegatecall dispatcher)
  ├── MintModule           Ticket purchasing, ETH splitting
  ├── AdvanceModule        Level advancement, VRF requests
  ├── JackpotModule        Daily/weekly/grand jackpots
  ├── EndgameModule        Final-round resolution
  ├── GameOverModule       Game-over distribution and sweep
  ├── LootboxModule        Lootbox drops and claims
  ├── WhaleModule          Whale bundles, lazy passes, deity passes
  ├── BoonModule           Deity boon rewards
  ├── DecimatorModule      Elimination events
  └── DegeneretteModule    Degenerette mini-game
```

### Supporting Contracts

| Contract | Purpose |
|----------|---------|
| BurnieCoin | Deflationary ERC-20 game token |
| BurnieCoinflip | Daily coinflip side-game |
| DegenerusVault | stETH yield treasury |
| DegenerusJackpots | Jackpot pool accounting |
| DegenerusQuests | On-chain quest/streak system |
| DegenerusAffiliate | Referral tracking and payouts |
| DegenerusAdmin | Admin configuration, VRF wiring |
| DegenerusDeityPass | ERC-721 with on-chain SVG rendering |
| DegenerusStonk | Bonding curve token mechanics |
| WrappedWrappedXRP | Meme wrapper contract |

### Libraries

| Library | Purpose |
|---------|---------|
| BitPackingLib | Bit-level packing for gas-efficient storage |
| EntropyLib | Deterministic entropy from VRF seeds |
| GameTimeLib | Day/epoch boundary calculations |
| JackpotBucketLib | Jackpot tier allocation math |
| PriceLookupLib | Ticket price curves by level |

## Scope

See [`scope.txt`](scope.txt) for the complete in-scope file list.

**In scope:** 22 core contracts + 12 modules + 1 shared storage + 5 libraries + 12 interfaces = 52 Solidity files

**Out of scope:** `contracts/mocks/`, `contracts/test/`

## Deployment

All contract addresses are compile-time constants in `ContractAddresses.sol`. The deploy pipeline:
1. Predicts nonce-based addresses (`scripts/lib/predictAddresses.js`)
2. Patches `ContractAddresses.sol` with concrete addresses
3. Recompiles and deploys in deterministic order

Modules deploy first (nonce N+0..10), then supporting contracts (COIN, COINFLIP, GAME, etc.), then contracts that depend on earlier ones (VAULT → COIN, DGNRS → GAME, ADMIN → GAME).

## Prior Audit Work

The [`audit/`](audit/) directory contains findings from internal audit work:

- **`KNOWN-ISSUES.md`** — Consolidated known issues with current status (fixed/open)
- **`EXTERNAL-AUDIT-PROMPT.md`** — Detailed protocol overview and threat model
- **`findings/`** — 61 detailed finding reports across 7 audit phases + 4 adversarial sessions
- **`state-changing-function-audits.md`** — Exhaustive function-level audit of all state-changing entry points

### Finding Summary

| Severity | Open | Fixed |
|----------|------|-------|
| Critical | 0 | 0 |
| High | 1 (spec/code mismatch) | 1 |
| Medium | 1 (design limitation, acknowledged) | 4 |
| Low | 4 | 2 |
| Informational | ~45 | — |

See [`audit/KNOWN-ISSUES.md`](audit/KNOWN-ISSUES.md) for details.

### Test Coverage

- **884 Hardhat tests** — unit, integration, access control, edge cases, adversarial, PoC, validation
- **28 Foundry invariant harnesses** — ETH solvency, supply invariants, VRF lifecycle, vault math, FSM, composition
- **Slither** static analysis triaged (all HIGH/MEDIUM detections reviewed)

## Key Mechanics for Auditors

- **VRF State Machine:** `rngLockedFlag` prevents concurrent VRF requests. Request → fulfill → unlock cycle. 18-hour retry timeout, 3-day emergency fallback.
- **Prize Pool Split:** 90% current level / 10% future levels on ticket purchase.
- **Whale Pricing:** Bundles 2.4-4 ETH, lazy passes 0.24 ETH+, deity passes 24 + T(n) ETH triangular.
- **Game Over:** Multi-step process: advanceGame → VRF request → fulfill → advanceGame → gameOver = true. 30-day final sweep.
- **Pull Payments:** All ETH/stETH withdrawals use pull pattern via `claimWinnings()`.
- **Threat Model:** 10,000 ETH whale, coordinated Sybil, block proposer with MEV, compromised admin, flash loans.

## Documentation

- [`docs/`](docs/) — Protocol mechanics documentation
- [`ECONOMIC_ANALYSIS.md`](ECONOMIC_ANALYSIS.md) — Economic analysis and attack surface review
- [`GAME_THEORY_ANALYSIS.md`](GAME_THEORY_ANALYSIS.md) — Game theory and mechanism design analysis
- [`audit/EXTERNAL-AUDIT-PROMPT.md`](audit/EXTERNAL-AUDIT-PROMPT.md) — Comprehensive protocol overview for auditors

## License

[AGPL-3.0-only](LICENSE)
