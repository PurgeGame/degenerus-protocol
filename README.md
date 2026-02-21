# Degenerus Protocol

The complete, unmodified Solidity source for every contract in the [Degenerus Protocol](https://degener.us).

This repo exists so anyone can read the code, verify the logic, and compile the exact bytecode that's deployed on-chain. No hidden mechanics, no off-chain state. Everything that matters is right here.

Players buy tickets to enter an elimination game. Each round, a portion of players are decimated. Survivors advance, ticket prices escalate, and the prize pool grows. Jackpots, lootboxes, deity boons, and mini-games layer on top. When the dust settles, the last players standing split the pot.

Full details at **[degener.us](https://degener.us)**

## Build & Verify

```bash
npm install
npx hardhat compile
```

Requires Node.js 18+. Compiles with Solidity's IR pipeline (`viaIR: true`) and optimizer runs=2 — the same settings used for the production deployment. You can diff the compiled bytecode against what's deployed on-chain to verify nothing was changed.

## Architecture

Degenerus uses a **delegatecall module pattern**. The core `DegenerusGame` contract holds all game state and delegates execution to specialized modules. Every module inherits `DegenerusGameStorage`, ensuring storage slot alignment across all delegatecall targets.

```
DegenerusGame.sol
  ├── MintModule           Buy tickets, enter the game
  ├── AdvanceModule        Progress through rounds, daily RNG
  ├── BoonModule           Deity boon rewards
  ├── DecimatorModule      Elimination events
  ├── EndgameModule        Final-round resolution
  ├── GameOverModule       Payout distribution
  ├── JackpotModule        Jackpot pool mechanics
  ├── LootboxModule        Lootbox drops and claims
  ├── WhaleModule          Whale bundles and deity passes
  └── DegeneretteModule    Degenerette mini-game
```

### Core Contracts

| Contract | What It Does |
|---|---|
| **DegenerusGame** | Main entry point. Holds all game state, routes calls to modules via delegatecall. |
| **BurnieCoin** | ERC-20 game token. Deflationary — every transfer burns a cut. |
| **BurnieCoinflip** | Daily coinflip side-game. Bet BURNIE, win or burn. |
| **DegenerusVault** | Treasury. Manages staking yield (stETH) and protocol reserves. |
| **DegenerusJackpots** | Jackpot pool accounting — daily, weekly, and grand jackpots. |
| **DegenerusQuests** | On-chain quest system with milestone rewards. |
| **DegenerusAffiliate** | Referral tracking and affiliate payout splits. |
| **DegenerusAdmin** | Admin configuration (timelocked where applicable). |
| **DegenerusDeityPass** | ERC-721 deity passes with fully on-chain SVG rendering. |
| **DegenerusStonk** | Bonding curve token mechanics for DGNRS. |

### Libraries

| Library | Purpose |
|---|---|
| **BitPackingLib** | Bit-level packing for gas-efficient storage |
| **EntropyLib** | Deterministic entropy derivation from VRF seeds |
| **GameTimeLib** | Day/epoch boundary calculations |
| **JackpotBucketLib** | Jackpot tier allocation math |
| **PriceLookupLib** | Ticket price curve lookups by level |

### On-Chain Rendering

| Contract | Purpose |
|---|---|
| **Icons32Data** | 33 SVG path definitions for deity pass artwork |
| **DegenerusTraitUtils** | Trait generation for on-chain metadata |

## Contract Addresses

`ContractAddresses.sol` contains compile-time address constants. The file in this repo is zeroed out — the deploy pipeline generates a concrete version with live addresses before compilation. Deployed addresses are published at **[degener.us](https://degener.us)**.

## License

[AGPL-3.0-only](LICENSE)
