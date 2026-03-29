# Degenerus Protocol -- C4A Contest README

---

## About

Degenerus is an on-chain ETH game with repeating levels, prize pools, and multiple jackpot systems. Players buy tickets (price escalates per level), ETH splits across current and future prize pools, and Chainlink VRF drives level advancement and all randomness. The game runs until a terminal condition triggers game over, at which point remaining pools distribute to participants.

The protocol deploys 24 contracts: 14 core + 10 delegatecall modules sharing a single storage layout. Supporting infrastructure includes a dual-token system (sDGNRS soulbound + DGNRS transferable wrapper), BURNIE token with coinflip mechanics, stETH yield via DegenerusVault, deity pass NFTs with triangular pricing, and sDGNRS-holder governance for emergency VRF coordinator rotation and price feed swap. All contract addresses are compile-time constants via nonce prediction. Nothing is upgradeable.

---

## I Care About Three Things

1. **RNG Integrity** -- VRF is the sole randomness source. All inputs to RNG-dependent calculations must be committed before the VRF request. Any path where a player can alter state between request and fulfillment to influence their outcome, or where a block proposer/validator can bias results, is a high finding.

2. **Gas Ceiling Safety** -- advanceGame must complete within block gas limit under any achievable on-chain state, not just typical load. Any path an attacker can force to exceed the gas limit is a high finding.

3. **Money Correctness** -- ETH and token accounting must be exact. Dust-level rounding (wei-scale) is not a finding -- all rounding favors protocol solvency by design. Any path where unauthorized extraction occurs -- whether by a player, external attacker, or compromised admin -- is a high finding. Admin fund theft is in scope here: assume a hostile admin key. A compromised admin must not be able to extract funds or manipulate RNG as long as the sDGNRS community is engaged. Admin governance power is bounded by a DGNRS vesting schedule that scales with game maturity; VRF coordinator swap and price feed swap both require a Chainlink death clock prerequisite before governance can act. Governance manipulation scenarios are pre-documented in KNOWN-ISSUES.md.

Everything else is noise.

---

## Out of Scope

| Category | Reason |
|----------|--------|
| Gas optimization suggestions | Already optimized through 5 dedicated gas phases (v3.3, v3.5, v4.2, v4.3, v6.0). Gas ceiling verified under worst-case load. |
| Code style / naming / formatting | Intentional conventions consistently applied across ~15,000 lines. |
| NatSpec quality / comment correctness | Full NatSpec sweep completed (v3.5 + v3.2 + v8.0 Phase 133). 69 fixes applied in latest pass. |
| Known automated tool findings | Pre-audited with Slither v0.11.5 + 4naly3er. All findings documented in KNOWN-ISSUES.md. If your bot finds it, check there first. |
| Deployment scripts / off-chain infrastructure | Deployment uses nonce-predicted addresses baked at compile time. Wrong addresses = nothing works. Self-auditing. |
| Frontend code | Not deployed on-chain. |
| Formal verification gaps | Tracked separately. Not blocking audit readiness. |
| ERC-20 deviations in DGNRS/BURNIE | Intentional. Documented in KNOWN-ISSUES.md with rationale. |
| sDGNRS/GNRUS "ERC-20 compliance" | These are soulbound tokens, not ERC-20. Filing ERC-20 issues against them is invalid. |

---

## Known Issues

See `KNOWN-ISSUES.md` in the repository root. Pre-audited with Slither v0.11.5 (1,959 raw findings, 29 detectors after triage) and 4naly3er (4,453 instances, 78 categories after triage). Covers automated tool findings, design decisions (including boon coexistence, recycling bonus economics, VRF/price feed governance, and gameover fallback), 4 ERC-20 deviations, and 30 event audit findings. Post-v8.0 delta adversarial audit (6 INFO findings, 0 actionable) and v10.0 delta audit (0 vulnerabilities, 2 INFO -- turbo unreachable at L0, backfill cap >120 days) also incorporated.

If your finding is already documented there, it will be marked as a known issue and will not be eligible for reward.

---

## Architecture

24 deployable contracts. DegenerusGame dispatches to 10 specialized modules via delegatecall -- all share `DegenerusGameStorage`. Chainlink VRF V2.5 for all randomness. Lido stETH for yield. All addresses are immutable compile-time constants (`ContractAddresses.sol`). No proxy patterns. No upgradeability.

---

## Key Contracts

### Core (14)

| Contract | Description |
|----------|-------------|
| DegenerusGame | Main game contract, delegatecall dispatcher, ~19KB |
| DegenerusAdmin | Admin operations, VRF + price feed governance (sDGNRS vote required) |
| DegenerusAffiliate | Affiliate referral tracking and bonus points |
| BurnieCoin | ERC-20 token with coinflip auto-claim and vault burn mechanics |
| BurnieCoinflip | Coinflip resolution, bounty system, DGNRS-gated claims |
| StakedDegenerusStonk | sDGNRS -- soulbound, holds all reserves and pools, gambling burn redemption |
| DegenerusStonk | DGNRS -- transferable ERC-20 wrapper over sDGNRS |
| DegenerusVault | stETH yield vault, BURNIE distribution |
| DegenerusJackpots | Jackpot state and helper logic |
| DegenerusQuests | Quest streak system with activity score |
| DegenerusDeityPass | ERC-721 deity passes, triangular pricing T(n) |
| DeityBoonViewer | Deity boon data source and roll helper |
| Icons32Data | On-chain SVG icon data |
| GNRUS | Soulbound charity token with sDGNRS-governed level-based donations |
| WrappedWrappedXRP | wXRP utility token |

### Delegatecall Modules (10)

All share `DegenerusGameStorage`. Execute in DegenerusGame's context.

| Module | Description |
|--------|-------------|
| AdvanceModule | Level advancement, VRF request/fulfillment, gap backfill |
| MintModule | Ticket purchasing, ETH splitting across pools |
| WhaleModule | Whale bundles, lazy passes, deity passes |
| JackpotModule | Daily ETH/coin/ticket jackpot drawings |
| DecimatorModule | Decimator mechanics, terminal decimator (death bet) |
| EndgameModule | Endgame logic, BAF scatter, reward jackpots |
| GameOverModule | Game over distribution, deity pass refunds |
| LootboxModule | Lootbox opening, EV calculation, RNG lifecycle |
| BoonModule | Deity boon effects |
| DegeneretteModule | Degenerette betting and resolution |

### Libraries (5)

| Library | Description |
|---------|-------------|
| ContractAddresses | Compile-time address constants (nonce-predicted) |
| DegenerusGameStorage | Shared storage layout for all modules |
| BitPackingLib | Bit packing for storage optimization |
| PriceLookupLib | Price curve lookup tables |
| DegenerusTraitUtils | Trait generation utilities |
