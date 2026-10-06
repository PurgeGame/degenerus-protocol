# Degenerette: wild-color payout math

Paid bets accept **ETH (currency 0) and FLIP (currency 1)**. The player picks a
hero symbol; the hero lane's color is **wild**. Each house lane is wild with
probability **1/16**. Every symbol match scores one point, colors score by
equality or wilds, and each house wild adds **25%** to the payout. There is no
paid-payout ceiling: a fully boosted jackpot pays slightly above 1,000,000× the
paid stake.

Ordinary return is approximately **90–99.9%** with activity; ETH adds
**5 percentage points** through flat high-score additions. WWXRP internal
box/foil reward spins use the same reels and scoring, separate score-8/9 prizes,
a **5% help gate** and a **70–130%** activity target.

FLIP and WWXRP have zero decimals. Token payouts are whole integers; internal
reward spins keep fractional precision until the final conversion. FLIP floors
that final award. WWXRP awards strictly between zero and one token pay **1 WWXRP**;
zero pays zero, and larger awards floor to whole tokens. Return targets describe
payouts before token rounding.

## Ticket generation and shared draws

The only ticket input is a hero symbol `0..23` (Crypto, Zodiac or Cards):
`quadrant = symbol >> 3`, `icon = symbol & 7`. The hero lane holds that symbol
with a wild color; the other three player lanes get fresh uniform symbols and
uniform ordinary colors. The player never holds any other wild. All eight dice
remain natural house results in every color, but cannot be heroes and are
excluded from the daily jackpot hero boost.

Each house lane rolls a uniform symbol and, independently, is wild with
probability 1/16; otherwise its color is uniform over the eight ordinary colors
(15/128 each, gold included).

For ordinary ETH and FLIP bets:

- Same RNG round, hero and spin index means the same player ticket, regardless
  of wallet, bet id, stake or requested spin count. Five spins are exactly the
  first five of ten spins. Each bet starts at spin zero.
- Different hero symbols independently regenerate the other symbols and colors.
- ETH and FLIP share the player and house streams. The house stream is shared
  across hero selections, so every hero faces the same house board on a spin.
- Placement rejects an already revealed RNG index. Draws cannot be rerolled by
  changing settlement order or batching.

Using `H` for keccak256 over 32-byte ABI words and `packedH` for packed ABI:

```text
spinSeed = H(rngWord, uint256(index), uint256(symbol), uint256(spinIndex))
player   = ordinaryLanes(H(spinSeed, PLAYER_TICKET_TAG)), hero lane = 0x40 | icon
house0   = houseLanes(packedH(rngWord, uint32(index), bytes1(0x51)))
houseN   = houseLanes(packedH(rngWord, uint32(index), uint8(spinIndex), bytes1(0x51)))
```

Internal WWXRP reward spins use the box or foil award's committed seed in their
own domain. They never create a player-funded bet or burn the player's WWXRP:

```text
rewardSeed = H(committedAwardSeed, WWXRP_DRAW_TAG)
houseSeed  = H(rewardSeed, RESULT_TICKET_TAG)
rigSeed    = H(rewardSeed, WWXRP_RIG_SALT)
```

FLIP survival and award rounding keep their separate owner/bet-id domains, where
the bet id is scoped to the RNG index the bet queued at (see
[DEGENERETTE-BET-QUEUE.md](DEGENERETTE-BET-QUEUE.md)). Shared reels do not imply
identical final FLIP awards. Activity, stake boons, ETH caps and downstream
reward draws also affect settlement independently.

## Lane format

Degenerette tickets are four positional bytes, lane `q` in byte `q`:

```text
bit 7 zero | bit 6 WILD | bits 5..3 color | bits 2..0 symbol
wild lane  = 0x40 | symbol   (color bits zero)
```

There are no quadrant tags; the quadrant is the byte position. For entropy lane
`q` (64 bits), color is bits `64q+0..2`, symbol bits `64q+32..34`, and the house
lane is wild when bits `64q+3..6` are all zero. Global ticket and foil traits keep
their `[QQ][CCC][SSS]` format.

## Protocol deity boon entries

Ordinary ETH bets on hero symbol 0 (Vault/WWXRP deity) or 6 (sDGNRS/ETH deity)
also enter that deity's next-day three-boon draw. Weight uses paid ETH in 0.0001-ETH
units and the canonical activity multiplier (1x/2x/3x at 0/400/1200). The bet
recipient owns the entry. Stake-boon additions and generated award spins do not
add weight, and neither a spin win nor a jackpot hero win is required. See
[the boon draw mechanics](DEITY-BOONS.md).

## Scoring and result wilds

- Each symbol match, hero included: **1 point**.
- Each lane's color: **1 point** for equal ordinary colors or one wild, **2 points**
  for wild against wild, otherwise 0.
- The hero lane therefore scores 1 / 2 / 2 / 3 for ordinary house + wrong symbol /
  ordinary + right symbol / wild + wrong symbol / wild + right symbol. The hero
  color always scores, so scores run **1..9**; scores 1 and 2 pay zero.
- `W` = wilds on the house board (0..4), whether or not their symbols hit. The
  payout multiplier is additive: **1 + W/4**. The player's own wild does not count.
  Gold is an ordinary color with no bonus.
- Score 9 needs all four symbols, all three non-hero colors (equal or house wild)
  and a house wild on the hero lane.

With `w = 1/16`, the joint score/wild probability-generating polynomial is:

```text
F(x,y) = x((1-w) + w·x·y) · ((7+x)/8)^4 · ((1-w)·7/8 + (1-w)·x/8 + w·x·y)^3
P(S=s,W=k) = coefficient of x^s y^k
W_s = sum_k P(S=s,W=k) (1+k/4)
E0 = sum_s B_s W_s
```

Score and `W` are correlated: multiplying score-only EV by an average wild bonus
would be wrong. At least one house wild occurs on **22.7523803711%** of spins;
the wild bonus contributes **19.9904054032 percentage points** of neutral EV,
already included in the calibration.

## ETH/FLIP payout table

Multipliers are gross scheduled payouts per effective stake, including returned
stake, before activity scaling and the wild multiplier. ETH adds flat additions
`A` that are scaled by the wild multiplier and stake boon but not by activity.

| Score | Chance | Shared base `B` | ETH addition `A` | Neutral EV contribution, wilds included |
|---|---:|---:|---:|---:|
| 1 | 30.3348238049% | 0 | 0 | 0 |
| 2 | 39.2908194044% | 0 | 0 | 0 |
| 3 | 21.9566343731% | 0.5× | 0 | 12.22163224% |
| 4 | 6.9068407465% | 3× | 0 | 24.23222766% |
| 5 | 1.3358868615% | 10× | 0 | 16.38720121% |
| 6 | 0.1623963064% | 100× | 2.4× | 20.89068998% |
| 7 | 0.0120877434% | 625× | 46× | 10.20575598% |
| 8 | 0.0005019072% | 18,173.28× | 1,050× | 12.98618938% |
| 9 | 0.0000088527% | 230,000× | 224,084× | 3.07629853% |

```text
E0 = 27487789317497 / 27487790694400 = 0.99999994990856...
payout = effectiveStake * (B_S[centi-x] * activityBps + A_S[centi-x] * 10000) * (4 + W) / 4,000,000
```

`A = 0` for FLIP. Precision is kept until the single final division. The ETH
additions contribute **4.999995757825673 percentage points** (0.501 / 0.751 /
0.750 / 2.997 from scores 6 / 7 / 8 / 9).

A paying score occurs on **30.3743567907%** of spins, before FLIP survival. The
nine-point jackpot is **1 in 11,296,042.86**, independent of the chosen hero; with
four house wilds it is **1 in 268,435,456**.

At maximum activity, the maximum +12% stake boon, score 9 and four house wilds:

- ETH pays **1,016,632.96×** the paid stake, scheduled gross including lootbox value.
- FLIP pays **1,029,369.60×** on a winning survival flip, before token rounding.

Reels on the same hero, round and spin index are shared, so multiple bettors can
hit together and aggregate jackpot liability scales with their total stake. The
ETH pool cap redirects excess cash into lootbox rewards. Scheduled EV does not
specify cash liquidity or the realized value of downstream rewards.

## Activity and returns

Non-ETH unrigged payout is `effectiveStake * B_S * (1+W/4) * r`, with activity
return fraction `r`: 90% at 0, 98.91% at 305, 99.7% at 500 and 99.9% at 30,000+.
WWXRP uses the same knees with its own 70/124/127.6/130% targets.

| Activity score | Ordinary / FLIP | ETH | WWXRP, rig included |
|---|---:|---:|---:|
| 0 | 89.999995% | 94.999991% | 69.999999% |
| 100 | 92.919995% | 97.919991% | 87.699994% |
| 169 | 94.929995% | 99.929991% | 99.919990% |
| 170 | 94.959995% | 99.959991% | 100.089990% |
| 305 | 98.909995% | 103.909991% | 123.999983% |
| 500 | 99.699995% | 104.699990% | 127.599982% |
| 30,000 | 99.899994% | 104.899990% | 129.999981% |

## WWXRP help gate and high-tier bonus

WWXRP shares the base table for scores 0–7, with its own score 8 (**4,806.77×**)
and score 9 (**1,000,000×**). On `rigSeed % 20 == 0`, an already-paying spin
(`S >= 3`) with at most six matched axes `M` (the hero color counts once, so
`M = S - (house hero lane is wild)`) is helped: one uniformly selected missed
non-hero symbol, or missed color where neither side is wild, copies the player's
bits into the house lane. Each help adds exactly one point and leaves `W`
unchanged. The hero symbol and wild flags are never touched. With `M <= 6` at
least one axis is always eligible, and the help can never create a score 9.

The rig preserves the probability of a paying score and of every score-9/wild
combination. Score ≥6 rises from 0.17499481% to 0.24178915%.

The WWXRP table against the rigged score/wild distribution has neutral return
`Ew = 1335639553707493 / 1099511627776000 ≈ 1.2147570976`. One currency-wide
factor sets the base to 70%, and the activity surplus goes to scores 6–9:

```text
a0 = floor(7000 * 1,000,000 / Ew) / 10,000,000,000 = 0.5762468903
Ww_s = sum_k P_rigged(S=s,W=k) * (1+k/4)
f_s = floor(1,000,000 * share_s / (B_s * Ww_s)) / 1,000,000
WWXRP payout = effectiveStake * B_S * (1+W/4) * [a0 + (R(activity)-0.70)*f_S]
```

`f_S` is zero for scores 0–5; `R` is the target return fraction from 0.70 to 1.30.

| Winning score | WWXRP bonus factor, scaled by 1,000,000 | Share of added EV |
|---|---:|---:|
| 6 | 356,636 | 10% |
| 7 | 1,825,147 | 30% |
| 8 | 5,245,201 | 30% |
| 9 | 2,242,955 | 30% |

Scheduled WWXRP return is below 100% through activity 169. Fixed-point flooring
causes less than 0.00002 percentage points of shortfall across the whole uint16
activity range. Activity never affects the tickets, rig eligibility or rig choice.
A natural WWXRP score 9 pays its token prize through the ordinary payout path.

## Side rewards

- **sDGNRS** (paid ETH bets and box ETH spins): scores 7 / 8 / 9 pay **2.04% /
  4.66% / 10.10%** of the Reward pool per capped 1 ETH of stake. Each tier is
  scaled by its old/new frequency, keeping the previous expected pool outflow per
  1-ETH spin (99.86% of the previous rate).
- **Affiliate** (paid ETH bets): the referrer receives **4.26%** of the summed
  lootbox share of the bet's score ≥5 spins, as FLIP, including cash redirected by
  the pool cap. This keeps the previous expected referrer credit per ETH staked
  (99.3–100.05% across the activity knees, nonbinding cap).
- Quests and records are unchanged and outside the spin multiplier.

## Other rewards, automatic spins and compatibility

- ETH and FLIP stake boons raise effective stake versus paid stake under their
  caps. WWXRP boons do not boost automatic reward spins. See
  [WWXRP boons](WWXRP-BOONS.md).
- FLIP keeps its 50/50 double-or-nothing survival flip per bet, EV-neutral before
  whole-token flooring and stochastic hundred-FLIP rounding.
- ETH keeps its payout split, pool caps and downstream boxes. Scheduled return is
  not all immediately withdrawable ETH.
- Box spins request a random hero using internal sentinel `32`; symbols `0..23`,
  including zero, are real hero selections. Record awards keep the selected hero.
  Foil awards select one hero from the matched line using the sealed seed and
  regenerate the rest, including every color, so foil color rarity never reaches
  Degenerette payouts.
- Automatic player, hero, result and rig draws use separate tagged domains.
- The public bet ABI is `placeDegeneretteBet(address,uint8,uint128,uint8,uint8)`.
  Currency accepts only `0` (ETH) and `1` (FLIP). ETH permits up to 25 spins and
  FLIP up to 15. In the queued bet word, bits 160–164 hold the symbol, 188–251 the
  effective stake units, and 252–255 are reserved.

## Reproducible verification

Run `python3 scripts/data/degenerette_single_symbol_math.py` (the
`derive_5_tables.py` entry point forwards to it). Exact `Fraction` arithmetic
enumerates every symbol-hit / house-wild / color-equality state and every eligible
help choice, cross-checked against the generating-function convolution. The model
verifies the compiled payout table, ETH additions, WWXRP factors, rig rate, base
normalization, target curves and the sDGNRS/affiliate rates against an exact model
of the previous rules. Every uint16 activity value is checked for monotonicity and
deviation from the WWXRP target.

`DegeneretteHeroScore.t.sol` checks the compiled payout path against the exact
neutral EV over every state; `DegeneretteFastScoreParity.t.sol` proves the
branch-free scorer and producers against scalar references on every valid board;
`DegeneretteSingleSymbol.t.sol` tests the shared streams, prefix invariance,
placement commitment, scoring, the help rule and pinned natural jackpots.
