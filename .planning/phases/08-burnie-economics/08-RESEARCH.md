# Phase 8: BURNIE Economics - Research

**Researched:** 2026-03-12
**Domain:** BURNIE token supply dynamics -- coinflip mechanics, earning paths, burn sinks, vault reserves
**Confidence:** HIGH

## Summary

BURNIE is an ERC20 (18 decimals) in-game token with a tightly constrained supply model. New BURNIE enters circulation through four paths: coinflip winnings (mint on claim), lootbox BURNIE rewards (creditFlip), quest completion rewards (creditFlip), and vault mint-from-allowance (vaultMintTo). BURNIE exits circulation through three sinks: coinflip deposits (burnForCoinflip), decimator burns (decimatorBurn), and ticket purchases paid in BURNIE (burnCoin). The vault holds a virtual reserve (initially 2M BURNIE) that constrains total possible supply via the invariant `totalSupply + vaultAllowance = supplyIncUncirculated`.

The coinflip system is the central BURNIE mechanic. It operates on daily windows with VRF-based 50/50 outcomes and variable payout multipliers (1.5x to 2.5x on wins, 0x on losses). The bounty system, auto-rebuy, afKing recycling bonuses, and quest integration all layer additional complexity. All constants are verified directly from BurnieCoinflip.sol and BurnieCoin.sol source code.

**Primary recommendation:** Structure the audit document around four sections matching BURN-01 through BURN-04, with each section containing exact constants, formulas, and worked examples suitable for game theory agent consumption.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| BURN-01 | Document coinflip mechanics (stake, odds, payout range, bounty system, expiry) | Full constants extracted from BurnieCoinflip.sol: MIN stake, payout formulas, bounty accumulation/payout, claim windows, EV adjustment on last purchase day |
| BURN-02 | Document BURNIE earning paths (lootbox bonuses, quest rewards, coinflip winnings) | All earning paths traced: lootbox BURNIE output (55% tickets / 10% DGNRS / 10% WWXRP / 25% large BURNIE roll), quest rewards (100/200 BURNIE fixed), coinflip payout formula, presale 62% bonus, recycling bonuses |
| BURN-03 | Document BURNIE burn sinks (decimator eligibility, ticket purchases) | Decimator burn mechanics: 1000 BURNIE min, bucket weighting (base 12, min 5 normal / min 2 at level 100), activity score scaling, boon boosts. Ticket purchases burn via burnCoin |
| BURN-04 | Document vault reserve mechanics and supply invariants | Vault initial allowance 2M BURNIE, invariant totalSupply + vaultAllowance = supplyIncUncirculated, vaultEscrow increases allowance, vaultMintTo decreases allowance and mints, transfers to VAULT redirect to allowance |
</phase_requirements>

## Contract Source Map

| Contract | File | Role in BURNIE Economics |
|----------|------|--------------------------|
| BurnieCoin | contracts/BurnieCoin.sol | ERC20 token, decimator burns, vault escrow, quest routing |
| BurnieCoinflip | contracts/BurnieCoinflip.sol | Daily coinflip wagering, auto-rebuy, bounty, RNG processing |
| DegenerusQuests | contracts/DegenerusQuests.sol | Quest targets, rewards, streak tracking |
| DegenerusGameLootboxModule | contracts/modules/DegenerusGameLootboxModule.sol | Lootbox BURNIE output, boon system |
| DegenerusVault | contracts/DegenerusVault.sol | Vault BURNIE reserve, share-based claims |

## BURN-01: Coinflip Mechanics -- Key Constants and Formulas

### Core Constants (from BurnieCoinflip.sol)

| Constant | Value | Purpose |
|----------|-------|---------|
| `MIN` | 100 ether (100 BURNIE) | Minimum coinflip deposit |
| `PRICE_COIN_UNIT` | 1000 ether (1000 BURNIE) | Bounty accumulation per window |
| `COIN_CLAIM_FIRST_DAYS` | 30 | First claim window (days) before expiry |
| `COIN_CLAIM_DAYS` | 90 | Subsequent claim window (days) |
| `AUTO_REBUY_OFF_CLAIM_DAYS_MAX` | 1095 | Max days processed in deep auto-rebuy off |
| `AFKING_KEEP_MIN_COIN` | 20,000 ether | Min take profit for afKing mode |
| `COINFLIP_LOSS_WWXRP_REWARD` | 1 ether | WWXRP consolation per loss |
| `COINFLIP_EXTRA_MIN_PERCENT` | 78 | Normal bonus range floor |
| `COINFLIP_EXTRA_RANGE` | 38 | Normal bonus range span (0-37) |

### Win/Loss and Payout

- **Odds:** Exactly 50/50 (`win = (rngWord & 1) == 1`)
- **Payout on win:** `stake + (stake * rewardPercent) / 100` where rewardPercent is the bonus percentage
- **Payout on loss:** 0 BURNIE (principal forfeited), plus 1 WWXRP consolation per loss day

### Reward Percent Distribution

The `rewardPercent` (bonus percentage on top of principal) is determined by `seedWord % 20`:

| Roll | Probability | rewardPercent | Total Payout Multiplier |
|------|------------|---------------|------------------------|
| 0 | 5% | 50% | 1.50x |
| 1 | 5% | 150% | 2.50x |
| 2-19 | 90% | 78% + (seedWord % 38) = [78%, 115%] | [1.78x, 2.15x] |

**Presale bonus:** During presale, +6pp is added to rewardPercent (e.g., 84%-156% range normal).

### Last Purchase Day EV Adjustment

On non-presale bonus flip days (last purchase day of a level), the reward percent is adjusted based on the ratio of current-to-previous day's flip totals:

| Ratio (current/prev) | EV Adjustment (bps) |
|----------------------|---------------------|
| <= 1.0x (10,000 bps) | 0 bps (neutral) |
| >= 3.0x (30,000 bps) | +300 bps (positive) |
| Between | Linear interpolation |

The adjustment modifies rewardPercent via: `adjustedBps = rewardPercent * 100 + (targetRewardBps - COINFLIP_REWARD_MEAN_BPS)` where `COINFLIP_REWARD_MEAN_BPS = 9685` and `targetRewardBps = 10000 + evBps * 2`.

### Bounty System

- **Accumulation:** +1000 BURNIE per resolved window (wraps on uint128 overflow)
- **Arming:** Player sets new all-time biggest raw deposit (`biggestFlipEver`). If bounty already armed by someone else, must exceed current record by 1% (min +1 wei)
- **Resolution:** On next window resolution, half the bounty pool is removed. If the day is a WIN, that half is credited as flip stake to the bounty owner, plus a DGNRS reward. If LOSS, the half is simply removed (destroyed)
- **Clearing:** `bountyOwedTo` cleared after each resolution regardless of outcome
- **Restriction:** Cannot arm bounty during RNG lock; only direct deposits (not credited flips) can arm

### Recycling Bonuses

When a player deposits and has prior claimable winnings or auto-rebuy carry that gets reinvested:

**Normal recycling:** 1% of rebet amount, capped at 1000 BURNIE

**AfKing recycling:**
- Base: `AFKING_RECYCLE_BONUS_BPS = 160` (1.60%)
- Deity bonus: `AFKING_DEITY_BONUS_PER_LEVEL_HALF_BPS = 2` per level since activation, max `AFKING_DEITY_BONUS_MAX_HALF_BPS = 300`
- Deity portion capped at `DEITY_RECYCLE_CAP = 1,000,000 BURNIE`; excess gets base only
- Formula: `bonus = (amount * (baseHalfBps + deityBonusHalfBps)) / (BPS_DENOMINATOR * 2)` for amounts <= 1M BURNIE

### Claim Windows and Expiry

- First-time claimants: 30-day window from `flipsClaimableDay`
- Subsequent claimants: 90-day window
- Auto-rebuy: Extends to `autoRebuyStartDay` (no expiry while enabled)
- Unclaimed flips beyond the window are permanently lost (forfeited)

### Coinflip Boon (from Deity Lootbox)

| Boon Type | BPS | Max Deposit Cap | Max Bonus |
|-----------|-----|-----------------|-----------|
| COINFLIP_5 (basic) | 500 (5%) | 100,000 BURNIE | 5,000 BURNIE |
| COINFLIP_10 | 1000 (10%) | 100,000 BURNIE | 10,000 BURNIE |
| COINFLIP_25 | 2500 (25%) | 100,000 BURNIE | 25,000 BURNIE |

Boons are single-use, consumed on manual deposit only.

## BURN-02: BURNIE Earning Paths

### Path 1: Coinflip Winnings (Primary)

- **Source:** BurnieCoinflip._claimCoinflipsInternal
- **Mechanism:** On win days, principal is returned plus bonus percentage. Minted via `mintForCoinflip`
- **Net effect:** New BURNIE minted into circulation (not from vault)
- **Expected value:** 50% chance of ~1.97x average payout = ~0.985x EV per flip (slightly negative)

### Path 2: Lootbox BURNIE Rewards

- **Source:** DegenerusGameLootboxModule._resolveLootboxRoll and _resolveCommon
- **Distribution per lootbox roll:** 55% tickets, 10% DGNRS, 10% WWXRP, 25% large BURNIE
- **Large BURNIE roll (25% chance):**
  - Low path (80% of the 25%): `LOOTBOX_LARGE_BURNIE_LOW_BASE_BPS = 5808` + roll * `LOOTBOX_LARGE_BURNIE_LOW_STEP_BPS = 477` (range: 58.08% - 130.43% of ETH-equivalent value)
  - High path (20% of the 25%): `LOOTBOX_LARGE_BURNIE_HIGH_BASE_BPS = 30705` + (roll-16) * `LOOTBOX_LARGE_BURNIE_HIGH_STEP_BPS = 9430` (range: 307.05% - 589.95% of ETH-equivalent value)
  - Conversion: `burnieOut = (amount * largeBurnieBps / 10000) * PRICE_COIN_UNIT / targetPrice`
- **Presale multiplier:** `LOOTBOX_PRESALE_BURNIE_BONUS_BPS = 6200` (62% bonus on presale-eligible BURNIE)
- **Delivery method:** `coin.creditFlip(player, burnieAmount)` -- credited as coinflip stake, not wallet balance

### Path 3: Quest Rewards

- **Source:** DegenerusQuests.sol
- **Slot 0 (always "deposit new ETH"):** `QUEST_SLOT0_REWARD = 100 BURNIE` fixed
- **Slot 1 (random quest type):** `QUEST_RANDOM_REWARD = 200 BURNIE` fixed
- **Delivery:** Credited as coinflip stake via `creditFlip`
- **Quest types:** MINT_ETH, MINT_BURNIE, FLIP, AFFILIATE, DECIMATOR, LOOTBOX, DEGENERETTE_ETH, DEGENERETTE_BURNIE
- **Targets:** 1 ticket for mint quests, 2000 BURNIE for flip/affiliate/decimator, 2x mint price for lootbox, 1x mint price for deposit ETH

### Path 4: Bounty Payout

- **Source:** BurnieCoinflip.processCoinflipPayouts
- **Mechanism:** Half of accumulated bounty pool credited as flip stake to bounty owner on win days
- **Note:** Not minted -- credited as virtual stake added to next day's coinflip balance
- **Secondary reward:** DGNRS tokens from `payCoinflipBountyDgnrs`

### Path 5: LINK Donation Credit

- **Source:** BurnieCoin.creditLinkReward
- **Mechanism:** Admin credits BURNIE as flip stake for players who donate LINK tokens for VRF funding
- **Delivery:** `creditFlip` (coinflip stake, not wallet balance)

### Path 6: Vault Mint

- **Source:** BurnieCoin.vaultMintTo (called by DegenerusVault)
- **Mechanism:** Vault mints from its virtual allowance to recipients (e.g., share redemptions)
- **Constraint:** Cannot exceed current `vaultAllowance`

### Path 7: Game Direct Mint

- **Source:** BurnieCoin.mintForGame
- **Mechanism:** Game contract mints BURNIE directly to player wallet (e.g., Degenerette wins)

### Summary: Earning Paths by Delivery Method

| Path | Delivery | Creates New Supply? |
|------|----------|-------------------|
| Coinflip win | mintForCoinflip (wallet) | Yes |
| Lootbox BURNIE | creditFlip (coinflip stake) | No (virtual until claimed) |
| Quest reward | creditFlip (coinflip stake) | No (virtual until claimed) |
| Bounty payout | _addDailyFlip (coinflip stake) | No (virtual until claimed) |
| LINK donation | creditFlip (coinflip stake) | No (virtual until claimed) |
| Vault mint | vaultMintTo (wallet) | Yes (from allowance) |
| Game mint | mintForGame (wallet) | Yes |

## BURN-03: BURNIE Burn Sinks

### Sink 1: Coinflip Deposits

- **Source:** BurnieCoinflip.depositCoinflip -> BurnieCoin.burnForCoinflip
- **Minimum:** 100 BURNIE (`MIN = 100 ether`)
- **Mechanism:** Burns from player wallet immediately. Principal is either returned with bonus on win or permanently destroyed on loss
- **Net effect:** 50% of deposited BURNIE is permanently burned (expected)

### Sink 2: Decimator Burns

- **Source:** BurnieCoin.decimatorBurn
- **Minimum:** 1,000 BURNIE (`DECIMATOR_MIN = 1000 ether`)
- **Precondition:** Active decimator window (`decWindow()` returns true)
- **Burns permanently:** Yes -- burned BURNIE is gone, player receives weighted jackpot participation
- **Bucket weighting system:**

| Parameter | Value |
|-----------|-------|
| `DECIMATOR_BUCKET_BASE` | 12 (worst odds) |
| `DECIMATOR_MIN_BUCKET_NORMAL` | 5 (best normal odds) |
| `DECIMATOR_MIN_BUCKET_100` | 2 (best odds at level 100 multiples) |
| `DECIMATOR_ACTIVITY_CAP_BPS` | 23,500 (235% max activity score) |
| `DECIMATOR_BOON_CAP` | 50,000 BURNIE (max base for boon boost) |

- **Bucket calculation:** Higher activity score (capped at 235%) lowers bucket from 12 toward minimum
  - `reduction = (range * bonusBps + cap/2) / cap` where range = base - min
  - `adjustedBucket = base - reduction`, floored at minBucket
- **Burn multiplier:** `BPS_DENOMINATOR + (bonusBps / 3)` = 1x + 1/3 of activity bonus
- **Decimator boons** (from deity lootbox): 10%, 25%, or 50% boost on base amount capped at 50k BURNIE

### Sink 3: BURNIE Ticket Purchases

- **Source:** DegenerusGameMintModule.purchaseCoin / _purchaseBurnieLootboxFor
- **Mechanism:** Burns via `BurnieCoin.burnCoin` (which calls `_burn`)
- **Pricing:** BURNIE ticket price = ETH price converted at `_ethToBurnieValue(costWei, priceWei)` using `PRICE_COIN_UNIT / priceWei`
- **BURNIE lootbox minimum:** 1000 BURNIE (`BURNIE_LOOTBOX_MIN = 1000 ether`)
- **Restriction:** BURNIE tickets blocked within 30 days of liveness-guard timeout

### Sink 4: Transfers to Vault Address

- **Source:** BurnieCoin._transfer (special case for `to == VAULT`)
- **Mechanism:** Instead of crediting VAULT balance, decreases `totalSupply` and increases `vaultAllowance`
- **Effect:** BURNIE exits circulation and returns to the virtual reserve

## BURN-04: Vault Reserve Mechanics and Supply Invariants

### Core Invariant

```
totalSupply + vaultAllowance = supplyIncUncirculated
```

This invariant holds at all times. `totalSupply` tracks circulating BURNIE; `vaultAllowance` tracks the virtual reserve.

### Initial State

- `totalSupply = 0` (no BURNIE in circulation at deploy)
- `vaultAllowance = 2,000,000 ether` (2M BURNIE virtual reserve)
- `supplyIncUncirculated = 2,000,000 ether`

### Supply Flows

| Operation | totalSupply | vaultAllowance | supplyIncUncirculated |
|-----------|------------|----------------|----------------------|
| _mint(user, X) | +X | unchanged | +X |
| _burn(user, X) | -X | unchanged | -X |
| _mint(VAULT, X) | unchanged | +X | +X |
| _burn(VAULT, X) | unchanged | -X | -X |
| transfer(user, VAULT, X) | -X | +X | unchanged |
| vaultEscrow(X) | unchanged | +X | +X |
| vaultMintTo(user, X) | +X | -X | unchanged |
| mintForCoinflip(user, X) | +X | unchanged | +X |
| burnForCoinflip(user, X) | -X | unchanged | -X |

### Key Observations for Game Theory Agents

1. **Coinflip is net-negative on supply:** Expected loss rate is ~1.5% per flip cycle (50% chance of loss vs ~1.97x average win). Coinflip acts as a gradual BURNIE sink over time.
2. **Vault allowance grows via game deposits:** Every time the game contract calls `vault.deposit(coinAmount, ...)`, the vault's BURNIE allowance increases, expanding potential future supply.
3. **supplyIncUncirculated is NOT constant:** It changes with every mint, burn, and vaultEscrow. Only the `totalSupply + vaultAllowance` split is invariant.
4. **No hard supply cap:** BURNIE has no max supply. mintForCoinflip and mintForGame create new supply without vaultAllowance constraint. The vault's 2M is separate from coinflip minting.
5. **Practical supply constraint:** The negative-EV coinflip and permanent decimator burns create deflationary pressure that counterbalances minting from wins and lootbox rewards.

### Vault Claim Mechanics (DGVB Shares)

- Players burn DGVB (Degenerus Vault Burnie) shares to redeem proportional BURNIE
- Formula: `coinOut = (DGVB reserve * sharesBurned) / totalDGVBSupply`
- Sources: vault balance, then claimable coinflips, then vaultMintTo remainder
- This is the primary mechanism for BURNIE to flow from the vault reserve to circulation

## Common Pitfalls

### Pitfall 1: Confusing Coinflip Stake Credits with Minted BURNIE
**What goes wrong:** Treating `creditFlip` amounts as circulating supply
**Why it happens:** creditFlip adds to coinflipBalance (a virtual ledger) without minting. BURNIE only enters circulation when a player claims winning flips via `mintForCoinflip`.
**How to avoid:** Track creditFlip as "virtual stake" separate from circulating supply. Only mintForCoinflip/mintForGame/vaultMintTo create real supply.

### Pitfall 2: Forgetting Claim Window Expiry
**What goes wrong:** Modeling all coinflip winnings as eventually claimed
**Why it happens:** Unclaimed flips beyond 30/90 days are permanently lost
**How to avoid:** Account for claim expiry as a supply sink. Auto-rebuy players have no expiry while enabled.

### Pitfall 3: Treating supplyIncUncirculated as Constant
**What goes wrong:** Assuming total theoretical supply is fixed at 2M
**Why it happens:** The initial 2M vaultAllowance looks like a cap
**How to avoid:** Recognize that coinflip minting (mintForCoinflip) and vaultEscrow both increase supplyIncUncirculated independently.

### Pitfall 4: Ignoring Recycling Bonus in EV Calculations
**What goes wrong:** Computing coinflip EV without accounting for 1% recycling bonus (or 1.6%+ afKing bonus)
**Why it happens:** The bonus is applied on rebet/auto-rebuy carry, not on fresh deposits
**How to avoid:** Include recycling bonus when modeling auto-rebuy sequences.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Foundry (forge) |
| Config file | foundry.toml |
| Quick run command | N/A (analysis-only phase) |
| Full suite command | N/A (analysis-only phase) |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| BURN-01 | Coinflip mechanics documented with exact values | manual-only | Verify constants against BurnieCoinflip.sol source | N/A |
| BURN-02 | All earning paths enumerated with amounts | manual-only | Cross-reference creditFlip/mintForCoinflip/mintForGame callers | N/A |
| BURN-03 | All burn sinks documented with conditions | manual-only | Cross-reference _burn/burnCoin/burnForCoinflip callers | N/A |
| BURN-04 | Vault invariants documented | manual-only | Verify _supply struct and invariant in BurnieCoin.sol | N/A |

**Justification for manual-only:** This is an analysis-only phase producing documentation. Validation means verifying that documented constants match contract source, which is a code-reading task.

### Sampling Rate
- **Per task commit:** Grep verification of constants against source
- **Per wave merge:** Full cross-reference of all BURNIE flow paths
- **Phase gate:** All constants verified, all paths enumerated

### Wave 0 Gaps
None -- existing contract source is the test infrastructure for this analysis phase.

## Architecture Patterns

### Recommended Document Structure

The audit document should follow the established v1.1 format (see audit/v1.1-purchase-phase-distribution.md):
1. Overview with orchestration diagram
2. One numbered section per requirement (BURN-01 through BURN-04)
3. Constants reference table at the end
4. Worked examples with concrete numbers for agent consumption

### Cross-References to Prior Phase Docs

- **BURNIE-to-ticket conversion:** audit/06-eth-inflows.md (INFLOW-02)
- **Lootbox conversion ratios:** audit/v1.1-purchase-phase-distribution.md (JACK-06)
- **Decimator mechanics:** audit/v1.1-transition-jackpots.md (JACK-09)
- **BURNIE jackpot distribution:** audit/v1.1-purchase-phase-distribution.md (JACK-02, JACK-07)

## Sources

### Primary (HIGH confidence)
- contracts/BurnieCoinflip.sol -- All coinflip constants, payout formulas, bounty system, auto-rebuy logic
- contracts/BurnieCoin.sol -- ERC20 mechanics, supply invariant, vault escrow, decimator burns, quest routing
- contracts/DegenerusQuests.sol -- Quest types, fixed rewards (100/200 BURNIE), targets
- contracts/modules/DegenerusGameLootboxModule.sol -- Lootbox BURNIE output formulas, boon BPS values
- contracts/DegenerusVault.sol -- Vault deposit/claim/mint mechanics, DGVB share redemption

## Metadata

**Confidence breakdown:**
- Coinflip mechanics (BURN-01): HIGH -- all constants extracted directly from source
- Earning paths (BURN-02): HIGH -- all creditFlip/mintForCoinflip/mintForGame callers traced
- Burn sinks (BURN-03): HIGH -- all _burn/burnCoin/burnForCoinflip callers traced
- Vault reserve (BURN-04): HIGH -- invariant and supply struct verified in source

**Research date:** 2026-03-12
**Valid until:** Indefinite (contract source is immutable reference)
