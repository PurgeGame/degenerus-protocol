# Degenerus Protocol — Audit Repo

## Economics Reference (v1.1)

When writing about, analyzing, or reasoning about Degenerus Protocol economics:

1. **Start with the primer:** Read `audit/v1.1-ECONOMICS-PRIMER.md` first (286 lines). It covers the complete economic model with enough detail for reasoning, plus a document index for drill-down.

2. **Drill into source files** only when you need exact Solidity expressions, worked examples, or edge cases. The primer's Document Index table tells you which file covers which topic.

3. **Parameter lookups:** Use `audit/v1.1-parameter-reference.md` for exact BPS/ETH/timing constant values with contract file + line number citations.

4. **Critical pitfalls:** Section 9 of the primer lists the 12 most common reasoning errors. Read before making economic claims.

### File Layout

```
audit/v1.1-ECONOMICS-PRIMER.md          ← Start here (286 lines, complete overview)
audit/v1.1-parameter-reference.md       ← All ~200+ constants with exact values
audit/v1.1-eth-inflows.md               ← 9 purchase paths, cost formulas, pool splits
audit/v1.1-pool-architecture.md         ← Pool lifecycle, freeze, level advancement
audit/v1.1-purchase-phase-distribution.md ← Daily drip, BURNIE jackpots
audit/v1.1-jackpot-phase-draws.md       ← 5-day draws, trait buckets, winners
audit/v1.1-transition-jackpots.md       ← BAF & Decimator mechanics
audit/v1.1-burnie-coinflip.md           ← Coinflip odds, payout tiers, recycling
audit/v1.1-burnie-supply.md             ← BURNIE supply dynamics, vault, burns
audit/v1.1-level-progression.md         ← Price curve, whale/lazy pass economics
audit/v1.1-endgame-and-activity.md      ← Activity score, death clock, terminal payouts
audit/v1.1-dgnrs-tokenomics.md          ← DGNRS token distribution, soulbound rules
audit/v1.1-deity-system.md              ← Deity passes, boons, pricing curve
audit/v1.1-affiliate-system.md          ← 3-tier referral, taper, DGNRS claims
audit/v1.1-steth-yield.md               ← stETH integration, yield surplus
audit/v1.1-quest-rewards.md             ← Quest types, streak system, slot mechanics
```

## Contract Source

- Main game: `contracts/DegenerusGame.sol`
- Token: `contracts/DegenerusStonk.sol` (DGNRS)
- Coinflip: `contracts/BurnieCoinflip.sol`
- BURNIE token: `contracts/BurnieCoin.sol`
- Modules: `contracts/modules/` (delegatecall pattern)
- Storage: `contracts/storage/DegenerusGameStorage.sol`
- Addresses: `contracts/ContractAddresses.sol`
