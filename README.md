# Degenerus Protocol

Smart contracts for the [Degenerus Protocol](https://degener.us).

## What It Is

Degenerus is an on-chain gambling protocol on Ethereum. Players buy tickets, ticket ETH fills a prize pool, and when the pool hits a target the level completes and jackpots fire. Ticket prices cycle through tiers within each 100-level century. The prize pool ratchets upward each cycle. Chainlink VRF determines every outcome.

Three products share one economy:

- **Tickets** — straightforward lottery entries. Traits are assigned by VRF, jackpots pay trait-matched holders. Honestly -EV, provably fair.
- **Lootboxes and passes** — longer-horizon products that fund the prize pools and receive future-level tickets in return. EV depends on activity score (how much you play) and level velocity (how fast the game progresses).
- **Affiliate network** — three-tier referral system. Commissions are paid as BURNIE coinflip credits, not direct ETH, which filters out mercenary referral farmers.

The protocol extracts zero rake after presale. Every wei of ETH that enters goes into prize pools and recirculates to players. No operator fees, no admin withdrawal function. The contracts are immutable with no upgrade path.

Ownership is vault-based: the DGVE holder (>50.1% of vault governance token) acts as admin. Powers are narrowly scoped — VRF coordinator swaps (via sDGNRS-holder governance with decaying approval threshold), ETH→stETH liquidity conversion, lootbox RNG threshold, and LINK price feed configuration. The admin cannot access player funds or modify core game rules. A community governance path allows 0.5%+ sDGNRS holders to propose VRF coordinator swaps after a 7-day VRF stall.

Two liveness guards prevent permanent fund lockup. At level 0, a 365-day deploy timeout fires if no level ever completes. Once past level 0, a 120-day inactivity guard fires if no level completes for 120 consecutive days (VRF stall durations are excluded from this count). When either guard triggers, remaining funds are distributed: deity pass holders receive 20 ETH refunds each (if game ends before level 10), then 10% goes to Decimator death-bet holders, 90% to next-level ticketholders, and any uncredited remainder is split between the vault and DGNRS backing. A 30-day final sweep forfeits unclaimed winnings and sends all remaining balances to vault (50%) and DGNRS (50%). The terminal payout math makes buying during a stall individually rational, which is what prevents the stall from lasting 120 days. Full analysis in the [game theory paper](https://degener.us/theory/).

## Quick Start

```bash
npm install
npx hardhat compile
```

Requires Node.js 18+.

## Tests

```bash
# Hardhat tests (1,463 tests)
npx hardhat test

# Foundry invariant fuzzing
forge test
```

## Architecture

- **25 deployable contracts** (15 core + 10 delegatecall modules), sharing storage via `DegenerusGameStorage`
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
| StakedDegenerusStonk | Soulbound reserve token (sDGNRS), holds all pools |
| DegenerusStonk | Transferable ERC-20 wrapper (DGNRS) for sDGNRS |
| DeityBoonViewer | Standalone deity boon slot viewer |
| GNRUS | Soulbound charity token with sDGNRS-governed level-based donations |
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

Icons32Data and modules deploy first (nonce N+0..10), then supporting contracts (COIN, COINFLIP, GAME, etc.), then contracts that depend on earlier ones (VAULT, DGNRS, ADMIN, GNRUS).

## Scope

See [`scope.txt`](scope.txt) for the complete in-scope file list.

**In scope:** 17 core files (15 deployable + ContractAddresses + DegenerusTraitUtils) + 12 module files (10 deployable + 2 abstract utils) + 1 shared storage + 5 libraries + 12 interfaces = 47 Solidity files

**Out of scope:** `contracts/mocks/`, `contracts/test/`

## Key Mechanics

- **VRF State Machine:** `rngLockedFlag` prevents concurrent VRF requests. Request -> fulfill -> unlock cycle. 12-hour retry timeout, 3-day emergency fallback.
- **Prize Pool Split:** 90% current level / 10% future levels on ticket purchase.
- **Whale Pricing:** Bundles 2.4-4 ETH, lazy passes 0.24 ETH+, deity passes 24 + T(n) ETH triangular.
- **Game Over:** Liveness guard fires inside `advanceGame` (120-day inactivity or 365-day deploy timeout). `handleGameOverDrain` distributes funds using historical RNG (3-day VRF fallback if Chainlink is stalled). 30-day final sweep sends unclaimed remainder to vault and DGNRS.
- **Pull Payments:** All ETH/stETH withdrawals use pull pattern via `claimWinnings()`.

## Audit

- **[`KNOWN-ISSUES.md`](KNOWN-ISSUES.md)** — Pre-disclosed known issues and intentional design decisions for wardens

### Test Coverage

- **1,463 Hardhat tests** — unit, integration, access control, edge cases, adversarial, PoC, validation
- **27 Foundry test harnesses** (24 fuzz/invariant, 3 Halmos) — ETH solvency, supply invariants, VRF lifecycle, vault math, FSM, composition
- **Slither** static analysis triaged (all HIGH/MEDIUM detections reviewed)

## License

[AGPL-3.0-only](LICENSE)
