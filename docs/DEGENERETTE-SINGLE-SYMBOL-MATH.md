# Degenerette: single-symbol payout math

Implemented in the working tree, 2026-09-22. Score 2 pays **0.5×**, before
activity scaling and matched-gold bonuses. One score table serves all currencies.
Gold is as common as every other color. Base return, including gold, remains
approximately **90–99.9%**; ETH keeps its extra **5 percentage points**.
Player-funded bets accept **ETH (currency 0) and FLIP (currency 1)** only. WWXRP
remains available through internal box and foil reward spins. Those spins keep
the **5% help gate**, with their rigged/gold-adjusted base calibrated
to **70% EV at activity 0**, rising to **130% at maximum activity**. Activity's
extra return is paid only on winning scores **6–9**, in a 10/30/30/30 budget split.
WWXRP's scheduled token return is below 100% through activity **169**. WWXRP
reward spins pay only WWXRP tokens. Stake boons apply only to ETH and FLIP bets.

## Ticket generation and shared draws

The only ticket input is a hero symbol `0..31`: `quadrant = symbol >> 3`,
`icon = symbol & 7`. Generate the other three symbols and all four colors afresh.
Each random symbol and color is uniform among eight possibilities, including gold.
There is no full-ticket selection or separate hero-quadrant parameter.

For ordinary ETH and FLIP bets:

- Same RNG round, hero and spin index means the same player ticket, regardless
  of wallet, bet nonce, stake or requested spin count. Five spins are exactly the
  first five of ten spins. Each bet starts at spin zero.
- Different hero symbols independently regenerate the other symbols and colors.
  Independent draws can coincidentally match; they are not forced apart.
- ETH and FLIP share the player and house streams. The house stream is also
  shared across different hero selections, so ETH and Bitcoin heroes face the
  same house board on a given spin.
- Placement rejects an already revealed RNG index. Draws cannot be rerolled by
  changing settlement order or batching.

Using `H` for keccak256 over 32-byte ABI words and `packedH` for packed ABI:

```text
spinSeed = H(rngWord, uint256(index), uint256(symbol), uint256(spinIndex))
player   = uniformTraits(H(spinSeed, PLAYER_TICKET_TAG)), overwrite hero icon
house0   = uniformTraits(packedH(rngWord, uint32(index), bytes1(0x51)))
houseN   = uniformTraits(packedH(rngWord, uint32(index), uint8(spinIndex), bytes1(0x51)))
```

Internal WWXRP reward spins use the box or foil award's committed seed in their
own domain. They never create a player-funded bet or burn the player's WWXRP:

```text
rewardSeed = H(committedAwardSeed, WWXRP_DRAW_TAG)
houseSeed  = H(rewardSeed, RESULT_TICKET_TAG)
rigSeed    = H(rewardSeed, WWXRP_RIG_SALT)
```

FLIP survival and award rounding retain their separate owner/bet-nonce domains.
Thus shared reels do not imply identical final FLIP awards. Activity, stake boons,
ETH caps and downstream reward draws also affect settlement independently.

## Protocol deity boon entries

Ordinary ETH bets on hero symbol 0 (Vault/WWXRP deity) or 6 (sDGNRS/ETH deity)
also enter that deity's next-day three-boon draw. Weight uses paid ETH in 0.0001-ETH
units and the existing canonical activity multiplier (1x/2x/3x at 0/400/1200).
The bet recipient owns the entry. Stake-boon additions and generated award spins
do not add weight, and neither a spin win nor a jackpot hero win is required.
These entries share the existing daily RNG settlement; ordinary ETH hero tracking
continues unchanged. See [the boon draw mechanics](DEITY-PERPETUAL-AND-BOON-DRAW-PLAN.md).

## Scoring and matched gold

- Hero symbol match: **2 points**.
- Each of the other three symbol matches: **1 point**.
- Each color match: **1 point**, even when its symbol misses.
- Maximum score: **9**. Scores 0 and 1 pay zero.
- Count `G` quadrants whose player and final house colors are **both gold**.
  The payout boost is additive: **1 + G/4**, from 1× through 2×.
  Count gold after WWXRP rigging; merely rolling unmatched gold gives no boost.

Let `H ~ Bernoulli(1/8)` be the hero match and `K ~ Binomial(7,1/8)` be the
other seven matching axes. These are independent, and `S = 2H + K`.
The score probability generating polynomial is `(7+x²)(7+x)^7 / 8^8`.
The joint score/gold polynomial is:

```text
F(x,y) = ((7+x²)/8) ((7+x)/8)^3 ((56+7x+xy)/64)^4
P(S=s,G=g) = coefficient of x^s y^g
W_s = sum_g P(S=s,G=g) (1+g/4)
E0 = sum_s B_s W_s
```

A matching non-gold color has probability 7/64, a gold-to-gold match 1/64,
and a color miss 56/64. Conditional on `K=k`, the mean gold multiplier is
`1+k/56`, providing an independent cross-check of `W_s`. Applying an
unconditional average gold boost to score-only EV would be incorrect.

At least one gold match occurs on **6.1050355434%** of ordinary spins.
The table's gold bonus contributes **4.7859431207 percentage points** of neutral
EV; this contribution is already included in the calibration.

## Shared payout table

Multipliers are gross scheduled payouts per effective stake, including returned
stake, before activity scaling, matched gold and the ETH high-tier bonus.
For ETH/FLIP, score 2 pays **45–49.95% of effective stake** after ordinary
activity scaling, before gold. It is not a profitable result by itself.

| Score | Ordinary chance | Shared base | Neutral EV contribution, gold included |
|---|---:|---:|---:|
| 0 | 34.3608915806% | 0.00× | 0.00000000% |
| 1 | 34.3608915806% | 0.00× | 0.00000000% |
| 2 | 19.6347951889% | 0.50× | 10.08036360% |
| 3 | 8.4149122238% | 3.00× | 26.07120126% |
| 4 | 2.6046156883% | 10.00× | 27.15526521% |
| 5 | 0.5438208580% | 25.00× | 14.36218619% |
| 6 | 0.0735998154% | 125.00× | 9.86624509% |
| 7 | 0.0061750412% | 625.00× | 4.20492142% |
| 8 | 0.0002920628% | 23,470.36× | 7.58926290% |
| 9 | 0.0000059605% | 100,000.00× | 0.67055225% |

Scores 2–7 use simple values. Score 9 is 100,000× (200,000× with four matched
golds), close to the previous non-gold/all-gold base jackpots. Score 8 absorbs
the remaining EV budget:

```text
B8_exact = (1 - sum_{s != 8} B_s W_s) / W_8
         = 10186139 / 434 = 23,470.366359447005...×
B8_used  = 23,470.36×
E0       = 3355443131 / 3355443200 = 0.9999999794363975...
```

A paying score occurs on **31.2782168388%** of ordinary spins. This counts
partial-stake payouts and precedes FLIP survival. The nine-point jackpot is
**1 in 16,777,216**, independent of the chosen hero.

Keeping the previous N0 table under the new scoring rules would return
**188.274357833%** before activity scaling, which is why intermediate prizes
were recalibrated. The comparison model retains those historical N0 constants
explicitly; they are no longer production payout tables.

## Activity and ETH bonus

With activity return fraction `r`, non-ETH unrigged payout is
`effectiveStake * B_S * (1+G/4) * r`. ETH/FLIP use the existing
activity targets: 90% at 0, 98.91% at 305, 99.7% at 500 and 99.9% at 30,000+.
WWXRP uses the same activity knees with its own 70/124/127.6/130% targets.
This preserves the previous curve shape: 90% of its activity gain by score 305,
96% by 500, and the remaining 4% by 30,000. The concentration at the top end
refers to **winning score tiers**, not a delayed activity ramp.

ETH adds five percentage points of expected return, retaining the bonus budget
allocation of 10% to score 6 and 30% each to scores 7, 8 and 9. For those scores,
`f_s = bonusBudgetShare_s / (B_s W_s)`. ETH payout uses
`effectiveStake * B_S * (1+G/4) * (r + 0.05*f_s)`.

| Score | ETH factor, scaled by 1,000,000 |
|---|---:|
| 6 | 1,013,556 |
| 7 | 7,134,497 |
| 8 | 3,952,953 |
| 9 | 44,739,242 |

Precision is retained until the final integer payout division. These factors
contribute **4.9999995155 percentage points**, before token-unit flooring.

| Activity score | Ordinary / FLIP | ETH with bonus | WWXRP, rig and bonus included |
|---|---:|---:|---:|
| 0 | 89.999998% | 94.999998% | 70.000000% |
| 100 | 92.919998% | 97.919998% | 87.699997% |
| 169 | 94.929998% | 99.929998% | 99.919994% |
| 170 | 94.959998% | 99.959998% | 100.089994% |
| 305 | 98.909998% | 103.909997% | 123.999990% |
| 500 | 99.699998% | 104.699997% | 127.599989% |
| 30,000 | 99.899998% | 104.899997% | 129.999989% |

## WWXRP rig and high-tier bonus

Use the same score table and gold boost. On `rigSeed % 20 == 0`, count raw
matching axes without the hero's extra point. If 2–6 axes match, force one
uniformly selected unmatched axis to match. Eligible axes are all four colors
and the three non-hero symbols. The hero symbol is never forced. Seven or eight
raw matches are unchanged, so the rig cannot manufacture the nine-point jackpot.

The rig adds exactly one score point when it applies, and can create a gold
match. The exact model includes that score/gold correlation. It improves high
scores without changing the probability of any payout, since low results are
ineligible. Score ≥3 rises from 11.64342165% to 12.37972647%; score ≥6 rises
from 0.08007288% to 0.10726392%. Jackpot probability and jackpot gold mix stay fixed.

The shared table evaluated against the rigged score/gold distribution has
neutral return `Ew = 80439974071 / 67108864000 ≈ 1.19864902006`. Applying the
ordinary 90% activity multiplier would therefore pay 107.8784% at activity 0.
Instead, one currency-wide factor sets the base to 70%, and the activity surplus
is allocated to winning scores 6–9:

```text
a0 = floor(7000 * 1,000,000 / Ew) / 10,000,000,000
   = 0.5839907998
Ww_s = sum_g P_rigged(S=s,G=g) * (1+g/4)
f_s = floor(1,000,000 * share_s / (B_s * Ww_s)) / 1,000,000
WWXRP payout = effectiveStake * B_S * (1+G/4) * [a0 + (R(activity)-0.70)*f_S]
```

`f_S` is zero for scores 0–5. `R` is the target return fraction, from 0.70 to
1.30. The shared score table remains the same; the currency-wide base factor
and four high-tier bonus factors account for the different rigged distribution.

| Winning score | WWXRP bonus factor, scaled by 1,000,000 | Share of added EV |
|---|---:|---:|
| 6 | 767,803 | 10% |
| 7 | 4,612,705 | 30% |
| 8 | 1,928,269 | 30% |
| 9 | 44,739,242 | 30% |

At maximum activity, those tiers receive approximately **6 / 18 / 18 / 18 extra
percentage points** of EV, respectively. Scores 2–5 stay flat across activity.
Score 2 pays 0.2919953999× before matched gold in WWXRP; the common base table
still lists 0.5× before currency scaling. Hero points and gold boosts are identical.

Scheduled WWXRP return is **69.9999999905%** at activity 0 and
**129.9999888532%** at 30,000+. Fixed-point flooring causes less than 0.00002
percentage points of shortfall across the entire uint16 activity range. Activity
169 pays approximately 99.92%; activity 170 pays approximately 100.09%.
Gold and the rig are included in these returns. Activity never affects the
tickets, rig eligibility or rig choice: the same committed reward seed produces
the same reels at every activity score.

## Other rewards, automatic spins and compatibility

- ETH and FLIP stake boons raise effective stake versus paid stake under their
  existing caps. WWXRP boons retain their +4% / +8% / +12% tiers and now boost
  daily burn and century incinerator entry weights. They do not boost automatic
  reward spins. See [WWXRP boons](WWXRP-BOONS.md) for the ecosystem consumption hook.
- FLIP retains its 50/50 double-or-nothing survival flip, EV-neutral before
  whole-token flooring and stochastic hundred-FLIP rounding.
- ETH retains its payout split, pool caps and downstream boxes. Scheduled
  return is not all immediately withdrawable ETH.
- sDGNRS, quests and records are extra rewards on their eligible bet paths.
  Internal WWXRP reward spins pay their token payout, including at score 9. At
  the existing sDGNRS rates, the new score distribution increases instantaneous
  expected Reward-pool outflow per one-ETH spin to 0.0000027126073837280272 of
  the pool, approximately **1.883×** the historical N0 rate. Those reward rates
  are unchanged; their EV is outside the requested base-return target.
- Box spins request a random hero using internal sentinel `32`; all symbols
  `0..31`, including zero, are real hero selections. Record awards retain the
  selected hero. Foil awards select one hero from the matched line using the
  sealed seed, then regenerate the rest, including every color. Full foil
  tickets cannot carry their unusual gold distribution into Degenerette payouts.
- Automatic player, hero, result and rig draws use separate tagged domains.
  `BoxSpin.packedSpins` now includes each spin's 2-bit hero quadrant at bits
  225–230; the earlier reel, count and survival fields keep their positions.
- The public bet ABI is now
  `placeDegeneretteBet(address,uint8,uint128,uint8,uint8)`.
  Its currency argument accepts only `0` (ETH) and `1` (FLIP); all other values,
  including `3` (WWXRP), revert. ETH permits up to 25 spins and FLIP up to 15.
  The vault wrapper and module callers use the new symbol argument. Packed bet
  bits 0–4 contain the symbol; bits 5–31 and 218–219 are reserved. The redundant
  hero-quadrant copy has been removed; the quadrant is always `symbol >> 3`.
  Storage slots do not move.
  This is a new ABI/packed-data format, not a migration for outstanding old bets.

## Reproducible verification

Run `python3 scripts/data/degenerette_single_symbol_math.py` (the old
`derive_5_tables.py` entry point forwards to it). Exact `Fraction` arithmetic
covers all 4,096 match/gold states and every eligible rig choice, cross-checked
against the independent 16-state binomial derivation. The model verifies the
actual production payout, ETH/WWXRP bonus factors, WWXRP rig rate, base
normalization and target-curve constants. Every uint16 activity value is checked
for monotonicity and deviation from the WWXRP target.

`DegeneretteSingleSymbol.t.sol` tests the public shared streams, prefix invariance,
placement commitment, scoring, gold and payout bounds.
The production math harness also supports exhaustive score/rig/trait tests and
the four Degenerette statistical suites. Existing settlement, boon, record,
freeze, gas and automatic-award suites cover integration with the rest of the game.

The shared `SpinResult` pipeline generates, optionally rigs, scores and counts
gold for every manual, box, foil and record spin. Payouts consume that result
and the frozen activity score directly. Foil callers pass a symbol instead of
a full ticket. Automatic FLIP stake sizing now rejects values that would
truncate when converted to uint128, consistently with the ETH/WWXRP paths.

Validation after the WWXRP calibration and cleanup:

- Exact probability/EV model passes against the production constants, including
  all 65,536 activity values and the 169/170 negative-EV crossover.
- Hardhat: **59 passing**, covering the four Degenerette statistical suites,
  deployed payout integration, event surfaces and hero-override regressions.
- Foundry: **132 distinct checks passing** across the focused integration run
  and corrected invariant rerun; one existing sDGNRS-award test remains skipped.
  The initial invariant run exposed a fixture that could reach game-over before
  placing a bet. The fixture now places and resolves a real bet before fuzzing;
  all five invariants pass at 256 runs and 128 calls per run.
- All ten source gates and interface coverage pass. The storage-layout oracle
  matches every golden, including shared delegatecall slots.
- All 32 production runtime-size checks pass. The Degenerette module is
  **17,582 bytes**, leaving 6,994 bytes below the EIP-170 limit.

Foundry evidence is in `.audit-test-logs/degenerette-wwxrp-cleanup/` and
`.audit-test-logs/degenerette-wwxrp-invariant/`.
