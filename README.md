# Degenerus Protocol

Smart contracts for the [Degenerus Protocol](https://degener.us).

## What It Is

Degenerus is an on-chain gambling protocol on Ethereum. Players buy tickets, ticket ETH fills a prize pool, and when the pool hits a target the level completes and jackpots fire. Ticket prices cycle through tiers within each 100-level century. The prize pool ratchets upward each cycle. Chainlink VRF determines every outcome.

Three products share one economy:

- **Tickets** — straightforward lottery entries. Traits are assigned by VRF, jackpots pay trait-matched holders. Honestly -EV, provably fair.
- **Lootboxes and passes** — longer-horizon products that fund the prize pools and receive future-level tickets in return. EV depends on activity score (how much you play) and level velocity (how fast the game progresses).
- **Affiliate network** — three-tier referral system. Commissions are paid as BURNIE coinflip credits, not direct ETH, which filters out mercenary referral farmers.

The protocol extracts zero rake after presale. Every wei of ETH that enters goes into prize pools and recirculates to players. No operator fees, no admin withdrawal function. The contracts are immutable with no upgrade path. An admin role exists with narrowly scoped powers (Emergency-only VRF coordinator rotation) but cannot access funds or modify game rules.

If the game stalls for 365 consecutive days, a terminal state fires and distributes all remaining ETH to eligible ticket holders. The terminal payout math makes buying during a stall individually rational, which is what prevents the stall from lasting 365 days. Full analysis in the [game theory paper](https://degener.us/theory/).

## Quick Start

```bash
npm install
npx hardhat compile
```

Requires Node.js 18+.

## Tests

```bash
# Hardhat tests (1,241 tests)
npx hardhat test

# Foundry invariant fuzzing
forge test
```

## Architecture

- **23 deployable contracts** (13 core + 10 delegatecall modules), sharing storage via `DegenerusGameStorage`
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
| DegenerusStonk | Reserve-backed burn token (ETH/stETH/BURNIE) |
| DeityBoonViewer | Standalone deity boon slot viewer |
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

Icons32Data and modules deploy first (nonce N+0..10), then supporting contracts (COIN, COINFLIP, GAME, etc.), then contracts that depend on earlier ones (VAULT, DGNRS, ADMIN).

## Scope

See [`scope.txt`](scope.txt) for the complete in-scope file list.

**In scope:** 15 core files (13 deployable + 2 libraries) + 12 module files (10 deployable + 2 abstract utils) + 1 shared storage + 5 libraries + 12 interfaces = 45 Solidity files

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

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 0 |
| Medium | 1 (acknowledged design trade-off) |
| Low | 0 |
| Informational | 8 |

### Test Coverage

- **1,241 Hardhat tests** — unit, integration, access control, edge cases, adversarial, PoC, validation
- **21 Foundry test harnesses** (10 invariant, 7 fuzz, 3 Halmos, 1 helper) — ETH solvency, supply invariants, VRF lifecycle, vault math, FSM, composition
- **Slither** static analysis triaged (all HIGH/MEDIUM detections reviewed)

## License

[AGPL-3.0-only](LICENSE)
