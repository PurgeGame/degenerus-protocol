# Degenerus Protocol

Smart contracts for the [Degenerus Protocol](https://degener.us).

## What It Is

Degenerus is an on-chain gambling protocol on Ethereum. Players buy tickets, ticket ETH fills a prize pool, and when the pool hits a target the level completes and jackpots fire. Ticket prices cycle through tiers within each 100-level century. The prize pool ratchets upward each cycle. Chainlink VRF determines every outcome.

Three products share one economy:

- **Tickets** — straightforward lottery entries. Traits are assigned by VRF, jackpots pay trait-matched holders. Honestly -EV, provably fair.
- **Lootboxes and passes** — longer-horizon products that fund the prize pools and receive future-level tickets in return. EV depends on activity score (how much you play) and level velocity (how fast the game progresses).
- **Affiliate network** — three-tier referral system. Commissions are paid as FLIP coinflip credits, not direct ETH, which filters out mercenary referral farmers.

The protocol extracts zero rake after presale. Every wei of ETH that enters goes into prize pools and recirculates to players. No operator fees, no admin withdrawal function. The contracts are immutable with no upgrade path.

Ownership is vault-based: the DGVE holder (>50.1% of vault governance token) acts as admin. Powers are narrowly scoped — VRF coordinator swaps (via sDGNRS-holder governance with decaying approval threshold), ETH→stETH liquidity conversion, lootbox RNG threshold, LINK price feed configuration, and thanos-level declaration (a pre-announced, prospective-only entry divisor for a level at least 6 levels out; see `SECURITY.md` role 2 for its full bounds). The admin cannot access player funds or modify core game rules. A community governance path allows 0.5%+ sDGNRS holders to propose VRF coordinator swaps after a 7-day VRF stall.

Two liveness guards prevent permanent fund lockup. At level 0, a 365-day deploy timeout fires if no level ever completes. Once past level 0, a 120-day inactivity guard fires if no level completes for 120 consecutive days (VRF stall durations are excluded from this count). When either guard triggers, remaining funds are distributed: deity pass holders receive refunds of up to 20 ETH each (if game ends before level 10), then 10% goes to Decimator death-bet holders and 90% to the phase-correct terminal ticket cohort (next-level tickets during the ordinary purchase phase; current-level tickets during jackpot phase or a locked final-purchase transition). Any uncredited remainder is split three ways between the vault, sDGNRS backing, and GNRUS. A 30-day final sweep forfeits unclaimed winnings and splits all remaining balances three ways between the vault, sDGNRS, and GNRUS. The terminal payout math makes buying during a stall individually rational, which is what prevents the stall from lasting 120 days. Full analysis in the [game theory paper](https://degener.us/theory/).

## Architecture

- **29 deployable contracts** (17 core + 12 delegatecall modules), sharing storage via `DegenerusGameStorage`
- Solidity 0.8.34, `viaIR` enabled, optimizer runs = 1000, EVM target `osaka`
- All contracts under the 24,576-byte EIP-170 limit (largest: DegenerusGame at 24,487 bytes, 89 to spare; AdvanceModule at 24,207, 369 to spare; DegenerusMintModule at 22,399, 2,177 to spare)
- External dependencies: Chainlink VRF V2.5, Lido stETH, LINK token, and (optionally) an ENS
  reverse registrar — `ENS_REVERSE_REGISTRAR` is `address(0)` in this tree, which disables the
  constructor self-naming call entirely
- Pull-pattern ETH/stETH withdrawals (no push payments)

```
DegenerusGame.sol (main entry point, delegatecall dispatcher)
  ├── MintModule           Ticket purchasing, ETH splitting
  ├── AdvanceModule        Level advancement, VRF requests
  ├── JackpotModule        Daily/weekly/grand jackpots
  ├── GameOverModule       Game-over distribution and sweep
  ├── LootboxModule        Lootbox drops and claims
  ├── WhaleModule          Whale bundles, lazy passes, deity passes
  ├── BoonModule           Deity boon rewards
  ├── BingoModule          Bingo color-completion claims
  ├── FoilPackModule       Foil pack purchases and match claims
  ├── AfkingModule         AfKing auto-play subscriptions
  ├── DecimatorModule      Elimination events
  └── DegeneretteModule    Degenerette mini-game
```

### Supporting Contracts

| Contract | Purpose |
|----------|---------|
| FLIP | Deflationary ERC-20 game token |
| Coinflip | Daily coinflip side-game |
| DegenerusParimutuel | Over/under side-book on prize-pool growth |
| DegenerusVault | stETH yield treasury |
| DegenerusJackpots | Jackpot pool accounting |
| DegenerusQuests | On-chain quest/streak system |
| DegenerusAffiliate | Referral tracking and payouts |
| DegenerusAdmin | Admin configuration, VRF wiring |
| DegenerusDeityPass | ERC-721 with on-chain SVG rendering |
| sDGNRS | Soulbound reserve token, holds all pools |
| DGNRS | Transferable ERC-20 wrapper for sDGNRS |
| DeityBoonViewer | Standalone deity boon slot viewer |
| GNRUS | Soulbound charity token with sDGNRS-governed level-based donations |
| AFKingSubscriptionToken | AfKing seat ERC-721 (subscription <-> seat) |
| WWXRP | Meme wrapper contract |
| Icons32Data | On-chain SVG icon path and symbol name storage |

### Libraries

| Library | Purpose |
|---------|---------|
| ActivityCurveLib | Activity-score reward curves |
| BitPackingLib | Bit-level packing for gas-efficient storage |
| EntropyLib | Deterministic entropy from VRF seeds |
| FlipRoundLib | 100-FLIP award granule and whole-FLIP floor |
| GameTimeLib | Day/epoch boundary calculations |
| JackpotBucketLib | Jackpot tier allocation math |
| PriceLookupLib | Ticket price curves by level |
| SigFigLib | DGNRS three-significant-figure floor |
| DegenerusTraitUtils | Trait generation and foil rarity math (lives at `contracts/`, not `contracts/libraries/`) |

## Repository Layout

56 production Solidity files: 21 in `contracts/` (17 deployable + `ContractAddresses` + `DegenerusTraitUtils` + `DeityBoonViewer` + `DegenerusGameLens`), 14 in `modules/` (12 deployable + 2 abstract utils), 1 shared storage contract, 8 libraries, and 12 interfaces. `contracts/mocks/` and `contracts/test/` are test scaffolding and are never deployed.

## Deployment

All contract addresses are compile-time constants in `ContractAddresses.sol`. Deployment is nonce-deterministic: addresses are predicted from the deployer nonce, patched into `ContractAddresses.sol`, then everything is recompiled and deployed in fixed order — Icons32Data and the modules first, then the tokens and game contracts, then contracts that depend on earlier ones (DGNRS, ADMIN, GNRUS). The FoilPack module and then AFKingSubscriptionToken are appended last, so neither shifts any earlier address.

The `ContractAddresses.sol` values committed here are the **Foundry deterministic-test set** (with template `VRF_KEY_HASH = 0xabab…` and `DEPLOY_DAY_BOUNDARY = 0`), not a production manifest — a clean checkout builds and tests against them with no patching. `scripts/lib/predictAddresses.js` and `scripts/deploy.js` regenerate the real set for an actual deployment.

## Key Mechanics

- **VRF State Machine:** `rngLockedFlag` prevents concurrent daily VRF requests. Request -> fulfill -> unlock cycle. 12-hour retry timeout, 14-day emergency game-over fallback.
- **Prize Pool Split:** 90% current level / 10% future levels on ticket purchase.
- **Thanos levels (snap valve):** the vault owner may declare a level at least 6 levels out a "thanos level", after which every drained ticket entry for that level onward divides by `2^shift` (shift ≤ 8). Purely prospective — the declaration lands strictly before the target level's first materialization, so one level's entries always share one exponent and the uniform division cancels in the pot-share fraction. A non-zero shift is only declarable once projected demand exceeds 40M entries at the target level. The foil pack expresses the valve the other way round — it keeps its entry count and pays `2^shift` the price. Its payouts do not scale, so a thanos level makes the pack bad value outright: scaling them would mean reading an exponent at claim time, and a claim can land arbitrarily later than its buy, so a claim parked across a fresh declaration would pay `2^(new - old)` times its face. The valve is an emergency lever, not something to farm around.
- **Century BAF incinerator:** at an ×00 level whose BAF *loses* its flip (the bracket is skipped and the pool normally just rolls forward), 25% of the would-be BAF pool instead pays one burn-weighted winner drawn from the WWXRP burns made during the preceding ×99 level. Entries close when the level increments off ×99 — the same transaction that requests the VRF word deciding the flip.
- **Growth parimutuel:** an over/under book on the ratchet the game already records. Round L, open through level L's whole jackpot phase, resolves OVER iff `growth(L+1) > growth(L)` where `growth(L) = ratchet(L)/ratchet(L-1)` — compared cross-multiplied so the arithmetic is exact, with a push resolving UNDER. One fixed 1,000-FLIP stake per address per round, burned at placement; winners split the entire book evenly through the coinflip credit rail. There is no settlement transaction: every claim re-derives the outcome from write-once ratchet entries (century levels served from the append-only achieved-pool history), so a settled round's answer can never change.
- **All-time record pool:** four records — biggest direct coinflip deposit (200k-FLIP floor), biggest Degenerette spin (1 ETH, per-transaction total), biggest lootbox deposit (5 ETH, raw), biggest ticket buy (100 whole tickets) — share one FLIP pot seeded at 10,000 FLIP that drips 2,000/day and takes 0.1% of each completed level's achieved pool, converted notionally at that level's ticket price (no ETH moves). Beating a standing mark by at least a fifth claims 5% of the pot plus 0.5% per day that category went unclaimed (cap 75% at 140 days), paid as coinflip credit plus a 1/500-scale sDGNRS Reward-pool leg; a larger value below the beat threshold still ratchets the mark for free. Category clocks start at deploy, and each category's first mark — still gated by its entry floor — draws the launch-accrued share. Records never reset.
- **Whale Pricing:** Bundles 2.4-4 ETH, lazy passes 0.24 ETH+, deity passes 24 + T(n) ETH triangular.
- **Game Over:** Liveness guard fires inside `advanceGame` (120-day inactivity or 365-day deploy timeout). `handleGameOverDrain` distributes funds using historical RNG (14-day fallback if Chainlink is stalled, or immediate fallback once the >120-day suppressed-phase deadman fires). A 30-day final sweep sends unclaimed remainder three ways to the vault, sDGNRS, and GNRUS.
- **Pull Payments:** All ETH/stETH withdrawals use pull pattern via `claimWinnings()`.

## Build

```
git clone --recursive https://github.com/PurgeGame/degenerus-protocol
cd degenerus-protocol
npm ci        # OpenZeppelin + Hardhat deps, pinned via package-lock.json
forge build   # Solidity 0.8.34, viaIR, optimizer runs=1000, evm=osaka
```

The Solidity build is pinned — `foundry.toml` fixes the compiler (solc 0.8.34) and codegen, `foundry.lock` pins forge-std, `package-lock.json` pins the npm tree. A clean checkout compiles and tests with no local patches. (CI runs on a pinned Node; runner tool versions like Foundry/Aderyn track their action defaults.)

## Tests & Verification

The full assurance pipeline lives in this repository and runs in CI (`.github/workflows/ci.yml`) on every push:

- **`forge test`** — **1,722 Foundry tests across 227 suites**: 1,615 passing, 104 skipped, and 3 fixtures left stale by the packed-box-order change (see below). Coverage spans unit, integration, fuzz, invariant, gas, access-control, governance, economics, and named regression harnesses for every fixed finding.
  The three stale fixtures — `TicketLifecycle::testLootboxFarRollTicketsRouteToFF`, `VRFLifecycle::test_vrfLifecycle_levelAdvancement` and `FoilSnapPayout::test_matchPayoutIgnoresSnapExponent` — encode the superseded model in which repeated lootbox spends of differing sizes accumulated for one buyer in one RNG index. `_mergeBoxOrder` now deliberately admits one custom box *size* per (index, buyer), so those fixtures build a smaller scenario than they assert over. The contracts behave as designed; the fixtures await migration and are tracked as test debt, not findings (`test/` is out of scope).
- **EIP-170 size gate** — CI fails if any deployed contract breaches the 24,576-byte limit.
- **Storage-layout oracle** (`scripts/layout/storage_layout_oracle.sh`) — 12 modules execute by `delegatecall` against one shared `DegenerusGameStorage`, so CI fails the build if any storage slot in the game, any state contract, or any module moves versus a committed golden. This makes the "a module writes a slot the game uses for something else" corruption class un-shippable.
- **Source-drift gates** (`make check-*`) — interface coverage, delegatecall target alignment, raw-selector bans, RNG-window consumer classification, pool-write provenance, unbounded storage-array deletes.
- **Static analysis** — Slither + Aderyn (non-blocking).
- **Weekly** — 35 Halmos symbolic proofs + a deep invariant sweep (runs=1000, depth=256).

Reproduce the core suite locally:

```
forge test    # 1,615 passing, 104 skipped, 3 known-stale fixtures
make check-interfaces check-delegatecall check-raw-selectors check-rng-window check-pool-writes check-array-delete
bash scripts/layout/storage_layout_oracle.sh
```

A secondary Hardhat behavioral suite (`npx hardhat test`) provides additional coverage — 1,627 passing.

## Scope & Known Issues

- **`scope.txt` / `out_of_scope.txt`** — the exact audited surface, pinned to `contracts/` tree `46cc1c67` (tag `degenerus-c4a`).
- **`KNOWN-ISSUES.md`** — every pre-triaged finding, by-design ruling, and static-analysis disposition, each with its precise mechanism. Not vague disclaimers.
- **`SECURITY.md`** — threat model, trusted-role matrix (functional authority, not just Solidity modifiers), and disclosure process.
- **`ECONOMIC_DISCLOSURES.md`** — creator allocations, vesting, governance control, the WWXRP reserve, and terminal value — every figure cited to a contract line.

## Security

The code is **not yet deployed** — no live funds, no disclosure embargo. Security contact: [burnie@degener.us](mailto:burnie@degener.us). See `SECURITY.md` for the threat model and reporting guidance.

## License

[AGPL-3.0-only](LICENSE)
