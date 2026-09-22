# Degenerette: single-symbol payout math

Status: planning proposal, 2026-09-22. No game contracts changed.

The proposed shared table returns **99.9999995083% before activity scaling**,
including the matched-gold bonus. Applying the existing ordinary 90–99.9%
activity curve therefore preserves approximately **90–99.9% base return**.
The existing ETH +5 percentage points brings its gross scheduled return to
approximately **95–104.9%**, before additional rewards and settlement effects.

WWXRP uses the same score table and gold formula. Its rig adds return by improving
the result; it receives no compensating reduction in its score payouts. A proposed
**5% help gate** produces approximately **107.25–119.04%** return when WWXRP also
uses the ordinary activity curve. Retaining the current 60% help gate instead
produces approximately **296.96–329.63%**. Changing the gate is a recommendation,
not an already accepted or implemented change.

## Agreed game rules and modeling assumptions

- The player selects one of 32 symbols. Its quadrant is the hero quadrant.
- Generate the other three symbols and all four player-ticket colors afresh per
  spin, after commitment. Generate an independent result board.
- Each symbol and color is uniform among its eight possibilities. Gold is 1/8,
  exactly like each other color. The player's chosen hero symbol still has a 1/8
  chance of matching its result symbol.
- Hero symbol match: 2 points. Other symbol matches: 1 point each. Each color
  match: 1 point independently of its symbol. Maximum score: 9.
- Let G be the number of quadrants where player color and final result color
  are both gold. The payout multiplier is **1 + G/4**, applied additively across
  gold matches: 1x, 1.25x, 1.5x, 1.75x, or 2x. Count after WWXRP result adjustment.
- Retain the current payout floor: scores 0 and 1 pay zero. A single gold color
  match without another point therefore earns a point but no payout.
- Proposed WWXRP rig adaptation: if the unweighted count of matching axes is
  2–6, a successful help draw forces one uniformly selected unmatched axis to
  match. Exclude the hero symbol; all unmatched colors are eligible now that
  color points are independent. It adds one score point and may add a gold match.
  Seven or eight raw matches are left alone, so the rig never creates score 9.

The numerical WWXRP recommendation below uses the common 90–99.9% activity curve
and the rig as its bonus. That would replace the legacy WWXRP 70% payout floor
plus its separate redistribution to a 70–120% target. This is an explicit proposal
for simplifying WWXRP; the existing 70–120% curve is not preserved by these numbers.
Its old redistribution factors must not also be stacked onto this model.

## Exact score and gold probabilities

Let H be a Bernoulli(1/8) hero-symbol match. Let K be the number of matches among
the remaining seven axes (three symbols and four colors), so K is Binomial(7,1/8).
They are independent, and:

```text
S = 2H + K
P(S=s) = [C(7,s) 7^(8-s) + C(7,s-2) 7^(9-s)] / 8^8
```

Terms with invalid binomial indices are zero. Equivalently the score probability
generating polynomial is `(7 + x^2)(7 + x)^7 / 8^8`.

For a color axis, the mutually exclusive states are:

| Outcome | Probability | Score | Gold count |
|---|---:|---:|---:|
| Color misses | 56/64 | 0 | 0 |
| Matching non-gold colors | 7/64 | 1 | 0 |
| Gold matches gold | 1/64 | 1 | 1 |

The joint probability-generating polynomial for score and matched gold is:

```text
F(x,y) = ((7+x^2)/8) ((7+x)/8)^3 ((56+7x+xy)/64)^4
P(S=s,G=g) = coefficient of x^s y^g in F
```

Define `W_s = sum_g P(S=s,G=g) (1+g/4)`. A table with multipliers B_s has
expected return `E0 = sum_s B_s W_s`. This accounts for the correlation between
gold matches and high scores. Multiplying a score-only EV by the unconditional
average gold multiplier is incorrect.

As a separate derivation, conditional on K=k, four sevenths of the matching
ordinary axes are colors on average, and one eighth of those matches are gold.
Thus `E[G|K=k] = k/14`, and the conditional mean multiplier is `1+k/56`.
This gives the same W_s as the full joint enumeration.

At least one gold match occurs on **6.1050355434% of ordinary spins**, including
some nonpaying score-1 spins. The unconditional mean multiplier is 65/64, but the
proposed table's actual gold uplift contributes **4.6963836402 percentage points**
of its neutral base EV. That contribution is already included in calibration.

## Proposed shared score table

Multipliers below are gross scheduled payouts per effective spin stake, including
any returned stake, before activity scaling, the matched-gold multiplier, and the
ETH-specific +5-point bonus. A 1x entry is not a guaranteed break-even payout after
activity scaling. The current comparison is the ordinary all-non-gold table; the
existing contract has eight ordinary tables, so there is no single current table.

| Score | Ordinary chance | Current N0 base | Proposed shared base | Neutral EV contribution, gold included |
|---|---:|---:|---:|---:|
| 0 | 34.36089158% | 0x | 0x | 0% |
| 1 | 34.36089158% | 0x | 0x | 0% |
| 2 | 19.63479519% | 1.95x | **1x** | 20.16072720% |
| 3 | 8.41491222% | 4.87x | **2.5x** | 21.72600105% |
| 4 | 2.60461569% | 15.34x | **8x** | 21.72421217% |
| 5 | 0.54382086% | 43.55x | **24x** | 13.78769875% |
| 6 | 0.07359982% | 199.88x | **120x** | 9.47159529% |
| 7 | 0.00617504% | 1,024.90x | **625x** | 4.20492142% |
| 8 | 0.0002920628% | 51,245.17x | **25,527.01x** | 8.25429137% |
| 9 | 0.0000059605% | 107,564.11x | **100,000x** | 0.67055225% |

Scores 2–7 are deliberately simple numbers chosen to retain an increasing prize
ladder. Score 9 is pinned at 100,000x, close to the current 107,564.11x non-gold
jackpot. Four matched golds produce 200,000x before activity/other bonuses, close
to the current 209,164.35x all-gold jackpot. These are design choices, not a claim
of a unique optimal table. Score 8 uses the remaining EV budget:

```text
B8_exact = (1 - sum_{s != 8} B_s W_s) / W_8
         = 11078723 / 434
         = 25,527.011520737327...x
B8_used  = floor(100 * B8_exact) / 100 = 25,527.01x
E0       = 6710886367 / 6710886400 = 0.9999999950826168...
```

Only the near-jackpot entry needs a less rounded value; the shortfall is below
0.0000005 percentage points of neutral return. This is close enough that ordinary
activity scaling meets the requested target to much finer precision than a basis
point, before per-payout integer flooring.

The chance of a paying score rises from **19.609375%** for the current N0 ticket
to **31.2782168388%**, about 1 in 3.20 spins. This is a chance of a scheduled payout,
not a profit probability or the final FLIP payout probability after survival.
The nine-point jackpot is **1 in 16,777,216** under the proposed uniform model.
Both facts are independent of the chosen symbol.

Keeping the current N0 score multipliers under these new rules would return
**188.274357833%** before activity scaling. Smaller intermediate prizes are needed
to preserve overall EV. Other current ordinary tables, if reused as the universal
table, would give even higher returns (207–272%).

## Activity scaling and the existing ETH bonus

Let r(a) be the existing ordinary activity return fraction. For a non-ETH,
unrigged spin the formula is:

```text
payout = effectiveStake * B_S * (1 + G/4) * r(activity)
EV     = r(activity) * E0
```

Keep the ETH bonus at **+5 percentage points**, preserving the current split of
its EV budget: 10% to score 6, and 30% each to scores 7, 8, and 9. One set of four
factors is enough; none depend on ticket gold count or hero color.

For those scores let `f_s = bonusBudgetShare_s / (B_s W_s)` and use zero for other
scores. Then the ETH multiplier is `B_s (1+G/4) (r + 0.05 f_s)`.

The proposed factors, floored to a 1,000,000 fixed-point scale, are:

| Score | Scaled ETH bonus factor |
|---|---:|
| 6 | 1,055,788 |
| 7 | 7,134,497 |
| 8 | 3,634,473 |
| 9 | 44,739,242 |

Their EV contribution is **4.9999997303 percentage points** if fractional precision
is retained until the final payout division. Keeping the current additional
intermediate floor to whole ROI basis points instead gives **4.9988116221 points**.
Recommendation: combine factors before the final integer division, then round
the payout once. The return table below uses that approach, before token-unit
flooring. The bonus makes actual ETH high-tier multipliers larger than the base
score table; e.g. score 9 at max activity and zero matched gold is about 323,596.21x
gross, before the ETH/lootbox split and pool cap.

| Activity score | Ordinary / FLIP before settlement rounding | ETH including +5-point bonus | WWXRP with proposed 5% help gate |
|---|---:|---:|---:|
| 0 | 90.00% | 95.00% | 107.24675331% |
| 305 | 98.91% | 103.91% | 117.86418189% |
| 500 | 99.70% | 104.70% | 118.80557006% |
| 30,000+ | 99.90% | 104.90% | 119.04389618% |

## WWXRP: improve results, use the same table

Let E1 be the shared-table EV when every eligible result gets one helped match.
For this table, `E1 - E0 = 3.832611945569514...` stake units. If q is the help
probability on eligible results, linearity gives:

```text
E_WWXRP_before_activity(q) = E0 + q * (E1 - E0)
E_WWXRP_after_activity(q)  = r(activity) * E_WWXRP_before_activity(q)
```

The joint enumeration includes gold matches manufactured by a helped color.
It does not pretend the gold multiplier is independent of the improved score.

| Help gate on eligible results | Neutral table return | Return at activity 0 | Return at max activity |
|---|---:|---:|---:|
| 0% (ordinary random results) | 100.000000% | 90.000000% | 99.900000% |
| **5% (recommended simple gate)** | **119.163059%** | **107.246753%** | **119.043896%** |
| 60% (current gate retained) | 329.956716% | 296.961045% | 329.626760% |

A gate of approximately **5.2497150501%** would give exactly 120% at the maximum
activity score in the ideal model. Prefer 5% for simplicity unless that exact cap
is wanted. This is an occasional upgrade: it fires only within the eligible band,
not on 5% of all spins.

With a 5% gate, score >=3 becomes 12.37972647% instead of 11.64342165%, and score
>=6 becomes 0.10726392% instead of 0.08007288%. The chance of any paying score
stays 31.27821684% because results below two raw matches are not helped. WWXRP gets
larger wins, and more high-tier results, rather than newly created low-tier wins.
The nine-point jackpot and its gold-count distribution are unchanged by the rig.

## Additional bonuses and integration limits

These are scheduled spin returns per effective stake, not a valuation of every
reward in the protocol:

- Stake boons increase effective stake relative to paid stake, subject to their
  existing currency caps and rounding. Multiply these scheduled returns by the
  actual effective-stake/paid-stake ratio when presenting an individual bet.
- FLIP's survival flip remains EV-neutral before rounding (50% double, 50% zero).
  Whole-token and 100-FLIP rounding must be included in implementation checks.
- ETH keeps its existing ETH/lootbox split and cap. Gross scheduled value is not
  a promise of that much withdrawable ETH; valuing downstream boxes is separate.
- sDGNRS awards, quests, record rewards, and WWXRP whale-halfpass jackpots are
  additional rewards. Their value is not included in the 90–99.9% figure. At the
  existing sDGNRS rates, a one-ETH spin has expected instantaneous pool outflow
  `0.0000027126073837280272 * currentRewardPool`, versus
  `0.0000014405864197530864 * currentRewardPool` for the old N0 ticket: approximately
  **1.883x**. If those bonus budgets must also stay fixed, recalibrate their rates
  separately; do not describe them as automatically unchanged in EV.
- This calibration assumes fresh uniform player colors. Foil rewards currently
  pass a preexisting full ticket; such tickets have a different gold mix and need
  explicit modeling or a switch to the new ticket-generation flow. They cannot
  silently inherit the standard-ticket EV claim. The same applies to any retained
  full-ticket selection API.
- Player ticket generation, result generation, and rig draws need separate random
  domains committed before revelation. Chosen symbol, stake, and settlement order
  must not allow selecting a favorable generated ticket after observing outcomes.

## Verification and implementation handoff

Run the reproducible model:

```bash
python3 scripts/data/degenerette_single_symbol_math.py
```

The script reads current payout constants from the contract, enumerates all 4,096
match-mask/player-gold-mask combinations with exact `Fraction` arithmetic, and
enumerates every eligible forced-match choice. It cross-checks score probabilities
and gold-weighted EV against an independently derived 16-state binomial model.
It also checks total probability, gold frequency, monotone score improvements,
invariance of the jackpot and its gold distribution under rigging, current-table
base EV, the proposed table's rounding residual, and the ETH bonus budget.

This is a mathematical model verification, not contract implementation testing.
Implementation should subsequently reproduce the model from actual emitted
tickets, including color-only scoring and gold matches introduced by the rig,
then check currency settlement, bonus floors, caps, and automatic reward callers.

Source references:

- `contracts/DegenerusTraitUtils.sol`: current near-uniform gold/color generator.
- `contracts/modules/DegenerusGameDegeneretteModule.sol`: current tables, activity
  curves, ETH bonus split, rig, stake boons, settlement, and automatic spins.
- `scripts/data/derive_5_tables.py`: current table derivation and score-floor intent.
- `scripts/data/degenerette_single_symbol_math.py`: proposed exact model.
