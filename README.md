# Degenerus Protocol

Smart contracts for the [Degenerus Protocol](https://degener.us) — an on-chain elimination game on Ethereum.

Players buy tickets to enter. Each round, a portion of players are eliminated via VRF-driven randomness. Survivors advance, ticket prices escalate, and the prize pool grows. Jackpots, lootboxes, deity boons, and mini-games layer on top. When the dust settles, the last players standing split the pot.

## Quick Start

```bash
npm install
npx hardhat compile
```

Requires Node.js 18+.

## Tests

```bash
# Hardhat tests (884 tests)
npx hardhat test

# Foundry invariant fuzzing
forge test
```

## Architecture

- **22 deployable contracts**, 12 delegatecall game modules sharing storage via `DegenerusGameStorage`
- Solidity 0.8.34, `viaIR` enabled, optimizer runs = 200
- All contracts under 24KB (DegenerusGame largest at 19KB)
- External dependencies: Chainlink VRF V2.5, Lido stETH, LINK token
- Pull-pattern ETH/stETH withdrawals (no push payments)

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

## Deployment

All contract addresses are compile-time constants in `ContractAddresses.sol`. The deploy pipeline:
1. Predicts nonce-based addresses (`scripts/lib/predictAddresses.js`)
2. Patches `ContractAddresses.sol` with concrete addresses
3. Recompiles and deploys in deterministic order

Modules deploy first (nonce N+0..10), then supporting contracts (COIN, COINFLIP, GAME, etc.), then contracts that depend on earlier ones (VAULT, DGNRS, ADMIN).

## Scope

See [`scope.txt`](scope.txt) for the complete in-scope file list.

**In scope:** 22 core contracts + 12 modules + 1 shared storage + 5 libraries + 12 interfaces = 52 Solidity files

**Out of scope:** `contracts/mocks/`, `contracts/test/`

## Key Mechanics

- **VRF State Machine:** `rngLockedFlag` prevents concurrent VRF requests. Request -> fulfill -> unlock cycle. 18-hour retry timeout, 3-day emergency fallback.
- **Prize Pool Split:** 90% current level / 10% future levels on ticket purchase.
- **Whale Pricing:** Bundles 2.4-4 ETH, lazy passes 0.24 ETH+, deity passes 24 + T(n) ETH triangular.
- **Game Over:** Multi-step process: advanceGame -> VRF request -> fulfill -> advanceGame -> gameOver = true. 30-day final sweep.
- **Pull Payments:** All ETH/stETH withdrawals use pull pattern via `claimWinnings()`.

## Audit

The [`audit/`](audit/) directory contains findings from internal audit work:

- **[`KNOWN-ISSUES.md`](audit/KNOWN-ISSUES.md)** — Consolidated known issues with current status
- **[`FINAL-FINDINGS-REPORT.md`](audit/FINAL-FINDINGS-REPORT.md)** — Full findings report with requirement traceability
- **[`EXTERNAL-AUDIT-PROMPT.md`](audit/EXTERNAL-AUDIT-PROMPT.md)** — Protocol overview and threat model
- **[`state-changing-function-audits.md`](audit/state-changing-function-audits.md)** — Function-level audit of all state-changing entry points

### Finding Summary

| Severity | Open | Resolved |
|----------|------|----------|
| Critical | 0 | 0 |
| High | 0 | 2 |
| Medium | 1 (acknowledged design trade-off) | 3 |
| Low | 3 | 2 |
| Informational | ~45 | — |

### Test Coverage

- **884 Hardhat tests** — unit, integration, access control, edge cases, adversarial, PoC, validation
- **28 Foundry invariant harnesses** — ETH solvency, supply invariants, VRF lifecycle, vault math, FSM, composition
- **Slither** static analysis triaged (all HIGH/MEDIUM detections reviewed)

## License

[AGPL-3.0-only](LICENSE)
