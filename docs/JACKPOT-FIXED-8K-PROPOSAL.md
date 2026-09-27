# Fixed jackpot fee and pass purchase prices

Latest pricing configuration, 2026-09-27. The user kept **25,000 normal / 500,000 high** retail and asked to retune the component rolls. The working tree now applies the tier distributions, 8,000 jackpot fee, and pass accounting below. It also applies the jackpot Added floor (150,000 FLIP while the game level is 0 or 1, then 50,000) and one award per 10,000 of Added. Verification of pricing and integration is distinct from a proof of the maximum possible transaction gas.

## Added and award count

Let X be 0.5% of the appropriate last recorded prize pool, converted to FLIP at the committed reference price.

```
Protocol Added = max(floor, X)
  floor = 150,000 FLIP while the game level is 0 or 1, otherwise 50,000 FLIP
Normal jackpot entry fee = 8,000 FLIP
Awarded entry count = floor(Added / 10,000 FLIP), capped at 500
```

The count uses unrolled Added; paid fees and the pool lottery never change it.

Every award is backed by at least 10,000 of Added, above the 8,000 fee, so paid entries never fund the awards. With the earlier 25,000 + X and one award per 5,000 of X, Added per award fell below the fee once X passed about 41,700, and paid entries then returned roughly 0.57 to 0.8 of their fee.

The larger floor at levels 0 and 1 buys a broader early field: 15 awards instead of 5. Every award remains a separate entry. All paid and awarded entries use the same battle dice, with separately derived awarded board scatter. Settlement remains batched at jackpot time.

## Capital and participation

| X | Game level | Added | Awards | Added per award, before paid fees and pool roll |
|---:|---|---:|---:|---:|
| 25,000 (bootstrap) | 0 or 1 | 150,000 | 15 | 10,000 |
| 25,000 | 2 or later | 50,000 | 5 | 10,000 |
| 100,000 | 2 or later | 100,000 | 10 | 10,000 |
| 250,000 | any | 250,000 | 25 | 10,000 |
| 1,000,000 | any | 1,000,000 | 100 | 10,000 |
| 5,000,000 | any | 5,000,000 | 500 (cap) | 10,000 |

For P normal paid-equivalent units and F awarded units, keeping the whole-pool lottery M:

```
capital per unit = M × (Added + 8,000P) / (P + F)
```

Financial high copies count in P, while high-seat ranking and side-pot behavior remain separate. Valid pass/comp entitlements contribute quoted entry value, not a second count of their full-day face value. Pool capital is divided approximately half to gameplay and half to pot capital; allocation is not expected winnings.

For illustration, assume about 0.90 of capital comes back to an entry: an 83% engine return on the bankroll half, the whole pot half, and coinflip credit at 0.984. This excludes progressive/record/boon rewards and gas.

- A paid entry returns about 1.06 to 1.12 of its fee with two paid entries.
- It returns about 1.01 when paid units equal awards.
- It breaks even at about 1.25 paid units per award.
- It approaches the engine and coinflip edge beyond that.

This profile is the same at every game stage, because Added per award is pinned near 10,000. Shared dice correlate outcomes, so these marginal expectations are not independent-run probabilities.

**Emission.** The floor binds while X is below it:

- X reaches 150,000 at a pool of 30,000 tickets;
- X reaches 50,000 at a pool of 10,000 tickets (100 ETH at 0.01, 400 ETH at 0.04).

At bootstrap the rule emits 150,000 a day, against 50,000 under 25,000 + X. Level 0 can last up to the 365-day deploy idle timeout. Above X = 50,000 it emits 25,000 a day less than 25,000 + X.

## Small stakes become straightforward

Added is at least 10,000 times F, and each paid financial unit contributes 8,000. Therefore the smallest pool roll, M=0.5, leaves at least 4,000 capital per unit for any nonempty field. Rounding half of that down in 300-FLIP bankroll increments leaves at least **1,800 FLIP bankroll**.

Consequently this proposal does not need the earlier tiny-bankroll normalization design. A count cap only increases this lower bound. Do not derive F from the multiplied pool, which would change the proof. Very large allocations still need the existing upper-bound, high-pot residual and gas checks.

## Component rolls and pass accounting

The three ordinary tiers retain their existing bankrolls and bounties:

| Tier | Bankroll | Equally likely bounties | Mean entry price |
|---|---:|---|---:|
| Small | 600 | 200 / 300 / 400 | 900 |
| Medium | 1,800 | 600 / 1,000 / 1,400 | 2,800 |
| Large | 4,500 | 1,500 / 2,500 / 3,500 | 7,000 |

| Component | Small / medium / large odds | Mean entry price |
|---|---|---:|
| Matching first and last ordinary battles, each | 20% / 30% / 50% | 4,520 |
| Three other ordinary battles, each | 55% / 25% / 20% | 2,595 |
| Jackpot | Fixed fee | 8,000 |

Total normal mean: `2 × 4,520 + 3 × 2,595 + 8,000 = 24,825`.

The high multiplier remains either 10× or 100×, with **79/90** and **11/90** probability respectively (about 87.78% / 12.22%). Its mean is exactly 21×. One shared decoder supplies ordinary windows and the jackpot paid-unit calculation.

| Pass | Mean cost of individual entries | Fixed purchase price | Price versus mean |
|---|---:|---:|---:|
| Normal | 24,825 | **25,000** | **0.705% premium** |
| High roller | 521,325 | **500,000** | **4.091% discount** |

These prices are committed before the target day's opening RNG. Margins compare to expected entry cost, not every realized day's price or expected winnings. The already-open whole-day purchase continues to sum the actual component fees and use the actual high multiplier.

`CrapsPriceLib` supplies table, Game and FLIP pricing from a common source:

- Reward denominations: **24,800 normal / 520,800 high**. The normal is the daily mean rounded to 100; the high is exactly 21 normal units.
- Banked conversion: **21 normal credits → 1 high credit**. Packed credit balances and reservation storage retain their existing formats.
- Reward denomination switch: strictly above **22 normal units** (545,600), ensuring even the high branch's unrounded count exceeds one. Existing award caps and rounding rules remain.
- Future-window comp quotes: **4,520 / 2,595 / 8,000**, multiplied by **21** for high comps. Future-day comps use retail; flexible banked-pass comps use reward face value.
- FLIP's initial comp allowance remains **200 normal reward passes**, now 4,960,000. This changes initialization, not an already-deployed balance.

The component tier odds change, not their maximum bankroll or bounty. Matching bookends keep the same terms. No new RNG request, storage slot, or settlement stage is introduced by the pricing retune. A subsequent user decision applies one limit to every craps run: a 1,000-roll budget checked between shooters and a 1,511-roll absolute ceiling. Jackpot, ordinary and custom fields now share that rule.

## Implementation and remaining integration checks

At the daily request, Game computes X and applies the floor with `CrapsPriceLib.jackpotAdded(X, level)`, using the level before the last-purchase bump. The jackpot delegate stores that whole Added and counts awards as Added / 10,000. Paid fees and the pool lottery do not change that target. The cap is 500 awards, collected in chunks of up to 150. The old capacity-based removal of awards is unnecessary under this funding formula; the minimum-bankroll argument above applies.

The floor is additional protocol subsidy while it binds. Every paid and awarded entry throws the field's one dice seed. An awarded entry keys only its board scatter, survival coin and shooter boost to its bet id, so repeat awards to one wallet stay separate runs. Only paid fees are craps action. At seal the battle books the bankroll share of the fee money the pool roll kept (half the fees, halved again on a 0.5x roll) and credits 2% of that to the comp lane. Awarded bankroll, Added and any roll gain are never booked or comped. The table books and comps nothing further for the jackpot slot.

Focused verification includes exhaustive preset expectation checks, high odds and retail margins, comp debits, future-day commitment gates, 21:1 conversion, award splits, and jackpot funding/count checks. Full merged-jackpot worst-case gas certification remains separate; a typical successful advance is not a maximum-gas proof.

### Verification snapshot

**Commit-readiness blocker:** the expanded regression build fails with a via-IR stack-depth error at `test/gas/AdvanceNestedFullCompositionGas.t.sol:244`. That fixture and its `PurchaseDailyWorstCase` / `AdvanceNestedSettlementGas` dependencies still assume the earlier single-call battle, removed `JackpotBattleRun` events, and RNG application combined with daily payouts. They need porting to the current staged lifecycle before the broader test tree is green. The focused checks below pass; they do not imply that expanded suite passed.

Verification uses an isolated copy with Foundry deployment addresses patched only there. Coverage includes exact preset means and margins; pass purchases/conversion/award splits; live and future comps; real FLIP/vault allowance sharing; real lootbox and level-close rewards; jackpot fee, Added floors by level, award count and cap; shared dice; fee-only booking; and the universal roll ceiling. Historical engine parity retains its original digest using a test-only 8,192-roll reference, compares current results to an inline 1,000-roll reference, and requires runs ending below the new budget to remain unchanged.

All ten source audit gates pass: advance calls, RNG taint, unchecked blocks, delegatecall, raw selectors, RNG window, array delete, pool writes, write owners and gasleft. The three stale manifests were updated for the current prepare/append flow and shared pricing helpers. The advance integration tests pin the actual lock, append and settlement calls. The storage-layout oracle and interface coverage checks pass; the six `IJackpotBattle` selectors were also checked against the table/delegate ABI union without collisions.

All **11 cold-transaction advance integration tests** pass with `FOUNDRY_ISOLATE=true`. The largest measured jackpot transaction is **7,196,658 gas**, including intrinsic gas. The 500-award fixture uses four draw transactions and seven later settlement transactions; its last draw transaction also settles on its remaining work budget. Tests cover full sealing chunks, empty awards, initialization retry, both game phases, last-purchase promotion, transition, midnight delay, and release of the daily lock. This is measured coverage, **not a proof of the maximum gas over all possible dice sequences**.

Runtime sizes (patched test addresses): CrapsBattle **24,273 bytes** (303 bytes EIP-170 headroom); JackpotBattle **6,971**; CrapsEngine **5,829**; AdvanceModule **24,180** (396 headroom); JackpotModule **22,012**; LootboxModule **22,911**; FLIP **9,350**. The table and delegate have identical storage layouts. The intentionally oversized test-only `CrapsViews` harness is excluded from these production size checks.
