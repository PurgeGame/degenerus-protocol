# Craps Battle System: Current Economic Simulation

> Code snapshot reviewed 2026-08-27. Current rules in this report are **3:4 Don't Pass**, a
> maximum of four selected chips per spot, a **fixed shooter profit schedule** (15% of shooters on
> a blank ticket, 5% on a picked one, at +25/30/40% and +6/20/35% by Goal), scheduled Goals of
> **5x, 10x and 50x only**, a scheduled-bonus allocation of **50,000 FLIP/day plus 12% of trailing
> action**, and **half of that main allocation banked in one global progressive** rather than
> laddered. Older `/8`, `/36`, `/3`-with-a-15,000-floor, 5:6, 20x-Goal, 25,000-base, and
> unlimited-stack results do not describe this working tree.

This report measures the combined system implemented by
[`Craps.sol`](../contracts/Craps.sol) and
[`CrapsBattle.sol`](../contracts/CrapsBattle.sol): scheduled terms, scatter, shared shooters,
survival flips, Goal/Bust stops, Bust deletion, composite ranking, bounties, boosts, high rollers,
Vault boards, passes, and Coinflip-credit payouts.

The reproducible model is [`scripts/craps-system-sim.cpp`](../scripts/craps-system-sim.cpp).

```bash
g++ -O3 -std=c++20 -pthread scripts/craps-system-sim.cpp -o /tmp/craps-system-sim
/tmp/craps-system-sim --days 100000 --calibration 2000000 --schedule 1000000 --seed 20260827
```

The shipped shooter schedule and the `50,000 + 12%` funding rule are the model's **defaults**, so
the command above reproduces production without any boost flags. Every knob remains available for
exploring off-schedule settings. Three blocks of output are pure arithmetic and do not depend on
sampling at all: `EQUILIBRIUM_*` (the ticket-count curve), `LANES_*` (the two-lane split), and
`SHOCK_shutdown` (the seven-day funding lag).

Useful options:

```text
--scenario NAME
--settings N --settings-strategy sharp|fair|mixed|pass|blank|hardways|dark
--dont-profit-num N --dont-profit-den N
--main-base FLIP
--boosted-shooters-pct N --winnings-boost-pct N
--winnings-boost-mode all|random
--random-boosted-shooters-pct N --picked-boosted-shooters-pct N
--random-winnings-boost-pct N --picked-winnings-boost-pct N
--random-winnings-boost-jitter-pct N --picked-winnings-boost-jitter-pct N
--random-goal5-boost-bps N --random-goal10-boost-bps N --random-goal50-boost-bps N
--picked-goal5-boost-bps N --picked-goal10-boost-bps N --picked-goal50-boost-bps N
--matchup-incumbent STRATEGY --matchup-candidate STRATEGY
--board-search N --search-refine N --search-field STRATEGY|strategic_mix|duelN
```

The strategic tables below can be reproduced directly with, for example:

```bash
/tmp/craps-system-sim --board-search 5000 --search-refine 200000 \
  --search-field strategic_mix --search-top 10 --seed 20260827
/tmp/craps-system-sim --board-search 5000 --search-refine 200000 \
  --search-field duel5 --search-top 10 --seed 20260827
/tmp/craps-system-sim --dont-profit-num 5 --dont-profit-den 6 \
  --board-search 5000 --search-refine 200000 --search-field duel5 --seed 20260827
```

The model uses a deterministic 64-bit mixer instead of Keccak for speed, while retaining separate
domains, common random numbers, owner-specific scatter/survival, and a shared shooter per field.

## Executive conclusions

1. **3:4 raises the intrinsic Don't-Pass edge to 13.73%.** Versus the former 5:6 rule, that is a
   4.11-point increase per decision. On the legal 4-DP/3-Place-4 run, effective loss rose from
   56.55% to 64.86% in a common-seed two-million-run comparison.

2. **It reduces, but does not erase, the dark board's tournament value.** In a fixed diverse field
   of 31 deliberately selected boards, the best 3:4 responses still put four chips on Don't Pass.
   Their modeled ROI fell by roughly eleven points versus 5:6.

3. **Strategic adaptation is the important result.** Dark is powerful against a light-heavy field,
   but not dominant against players who react. In a full legal-board search, a modest dark share
   caused true-odds Place boards to become the best reply at 3:4; an all-dark field was attacked by
   Pass-heavy boards. This transition happened earlier than under 5:6.

4. **The current bonus formula is an additive base plus a linear rate: `50,000 FLIP/day + 12% of
   trailing action`.** Ordinary action funds main at 12%. High action funds main at 4.8% and high
   at 7.2%. The 50,000 is added, never a floor, so at the policy's 16% efficient-field assumption a
   day nets to zero around eighty ordinary daily tickets and prints below that. Against the modeled
   heterogeneous field, whose weighted edge is far above 16%, the crossing is nearer 24 — the
   equilibrium is edge-dependent, not a head count.

4a. **Half the main allocation is banked, not laddered.** `ladder = floor(raw/2)` and
   `progressive = raw - ladder`, so the odd wei goes to the pool and the two conserve the raw
   figure exactly. The high budget is not split. Both halves are emission: a wei banked is a
   liability the day it lands, and its later award releases that liability rather than issuing
   again. See section 8a.

5. **Bust deletion remains the economic foundation.** The legal true-odds core lost 24.01% across
   the current scheduled setting mix; 16.25 points came from deleting positive Bust remainders. A forced
   all-fair/no-scatter control had essentially zero wager drag and about 15.50 points of Bust
   deletion.

6. **The base subsidy is the thin-field issue, and is larger than the old floor.** A lone
   full-standing true-odds-core player recaptures its own bounty and most of a cold day's 25,000
   ladder half. The identical score-zero case cannot take the boost at all — and under the current
   rule that denied boost is not left unminted, it is banked in the progressive. This is the
   intended cost of keeping a cold table running, not a defect, but it is what makes a thin day
   emissionary.

7. **Against 30 light/core players, a 3:4 dark Vault is still highly rewarded.** Its main win share
   was 15.79% and its cash-funded ROI was +152.66% in the modeled field. That is materially below
   the same field at 5:6 (17.32%, +182.09%), but remains a strong governance incentive.

8. **The shooter profit schedule puts the crossover where it was aimed.** Post-schedule and
   depth-averaged over 5,000,000 runs per cell, a blank ticket runs 17.86% / 18.90% / 15.02% at
   Goal 5x / 10x / 50x and the picked optimum runs 15.81% / 17.30% / 19.90%. Picked is better at
   5x and 10x; blank is better at 50x. The weakest single cell measured is 13.72% (blank, depth
   10, Goal 50x), which still clears the 12% funding rate.

## 1. What the reported measures mean

| Measure | Definition | Interpretation |
|---|---|---|
| Pre-forfeit drag | `(starting bankroll - raw ending bankroll) / starting bankroll` | Wager/scatter/run effect before deleting Bust remainder |
| Bust deletion | Positive raw bankroll held by Busts, divided by starting bankroll | Extra loss caused by paying every Bust zero |
| Effective engine edge | `(starting bankroll - individual credit) / starting bankroll` | Total engine retention before bounties and boosts |
| Main win share | Fraction of fields whose main scoreboard the actor wins | Tournament performance, not wager EV |
| Player ROI | `(individual return + won pots - entry burns) / entry burns` | Field-conditional actor return |
| Net cash burn | Current entry burns minus all current Coinflip credits | Module-level current-day balance; pass origin is excluded |

All values are expectations or Monte Carlo estimates. Winner-take-all prizes make an individual
ROI conditional on the exact field. A profitable deviation cannot remain equally profitable after
everyone copies it.

## 2. Exact current bonus calculation

For each of the seven prior playing days, let:

```text
A_R(d) = dayStaked[d] - highStaked[d]
A_H(d) = highStaked[d]
```

The implementation uses integer floors in this order:

```text
E_R = floor(sum(floor(A_R(d-i) x 1200 / 10000), i=1..7) / 7)
E_H = floor(sum(floor(A_H(d-i) x 1200 / 10000), i=1..7) / 7)

fromHighToMain = floor(E_H x 2 / 5)

highBudget    = E_H - fromHighToMain
rawMainBudget = 50,000 + E_R + fromHighToMain
```

The 50,000 is **additive and unconditional** for an opened day. It is not `max(50,000, ...)` and
not a top-up capped at that figure: a day with a busy week behind it is paid for that week *on top
of* the base.

The raw main figure is then **split in half**, once, when the day opens:

```text
ladderBudget            = floor(rawMainBudget / 2)
progressiveContribution = rawMainBudget - ladderBudget
```

The ladder half is what the seven windows share, what the day stores, and what every quote — before
the opening and after — advertises. The other half is banked in the global progressive; the odd wei
goes there, so the two conserve the raw figure exactly. **The high budget is never split**; only its
standing forfeitures leave the lane.

At steady action, ignoring single-unit floors:

```text
rawMainBudget = 50,000 + 0.120 A_R + 0.048 A_H
highBudget    = 0.072 A_H
total linear budget = 0.12 (A_R + A_H)
```

So regular action contributes 12% to the main lane; high action contributes 4.8% to the main lane
and 7.2% to its own; and total action contributes 12% across both, whichever lane put it up. The
split is applied *after* all of that and moves none of it.

### Equilibrium, as arithmetic

The base is deliberately emissionary at low turnout and pays for itself at high. At a conservative
16% post-shooter whole-run engine take and about 15,600 FLIP of bankroll action per ordinary daily
ticket (bounties are **not** action, so the ~22,000 FLIP face cost is the wrong basis):

```text
residual burn per ticket = 15,600 x (16% - 12%) = 624 FLIP
equilibrium net          = 624 x ticketCount - 50,000
```

The split does not appear in this arithmetic, and that is the point: a wei banked in the
progressive is a wei allocated. It becomes a liability the day it lands there, so the emission
counted below is the **whole** main allocation, laddered and banked together.

| Ordinary daily tickets | Bankroll action | Engine take at 16% | Allocation: 50k + 12% | Ladder half | Pool half | Expected net |
|---:|---:|---:|---:|---:|---:|---:|
| 0 | 0 | 0 | 50,000 | 25,000 | 25,000 | 50,000 issuance |
| 2 | 31,200 | 4,992 | 53,744 | 26,872 | 26,872 | 48,752 issuance |
| 16 | 249,600 | 39,936 | 79,952 | 39,976 | 39,976 | 40,016 issuance |
| 40 | 624,000 | 99,840 | 124,880 | 62,440 | 62,440 | 25,040 issuance |
| 80 | 1,248,000 | 199,680 | 199,760 | 99,880 | 99,880 | 80 issuance (break-even) |
| 81 | 1,263,600 | 202,176 | 201,632 | 100,816 | 100,816 | 544 burn |

Precise break-even is about 80.1 tickets **at the 16% policy assumption**. It is not a universal
head count: the field's weighted post-shooter edge is the other half of the division, and a
heterogeneous field that hands the table 25.5% crosses at about 24 tickets. Section 8a tabulates
that.

The simulator emits this table directly as `EQUILIBRIUM_*` rows, and
`test_F2_theBaseSubsidySetsABreakEvenTicketCount` pins the same figures against the shipped
constants.

**This is an expectation, not a daily cap.** The ladder pays a window up to 100x its share and the
budget window lags seven days, so a realized day — and the week after a sudden collapse in
activity — can be much larger than the steady-state mean. Nothing in the rule caps issuance.

### Action attribution

- An ordinary seat books bankroll, not bounty.
- A contested high seat books `H x bankroll` as high action.
- A sole high seat also books its `(H - 1) x bounty`, because that capital rides the run.
- Cash, pass, prepaid, and protocol seats book the same nominal action once they play.
- Scheduled action is assigned to the day played; custom action to the day settlement executes.
- Protocol boost is not recycled into action. Neither is a bounty, a run credit, a donated pot, or
  a shooter profit boost: a day's action is the bankroll its settled seats put up and nothing else,
  so no emitted value can size a later subsidy.

### Allocation and rung

The event receives half of each daily budget. The six routine windows split the other half using
1x/2x/4x tier weights. Each window then draws 0.25x / 1x / 10x / 100x with probabilities
76.8% / 20.8% / 2.0% / 0.4%. The mean is exactly 1x.

**The Goal multiple does not enter the allocation at all.** A window's slice is a function of its
period (event versus routine) and its size tier; two routine windows of the same tier on the same
day take the same share whether they drew 5x, 10x or 50x, and the three targets are drawn evenly
by `(roll >> 32) % 3`. That is deliberate: the shooter profit schedule already performs the Goal
rebalance, and weighting the allocation as well would subsidise 50x twice and reverse the intended
crossover.

## 3. Current schedule

One million simulated days produced:

| Whole-day quantity | Mean FLIP |
|---|---:|
| Bankroll action per ordinary seat | 15,632.90 |
| Bounties per ordinary seat | 7,183.56 |
| Ordinary face cost | 22,816.46 |
| High face cost under the 90% 10x / 10% 100x draw | 433,646.67 |
| Event bankroll | 10,381.46 |
| Event bounty | 3,865.87 |

The fixed future-day prices are 25,000 ordinary and 450,000 high, premiums of about 9.6% and 3.8%
over these simulated face-cost means.

## 4. Current engine edge by board

These are two million independent runs per row, with the nine scheduled depth/goal combinations
mixed equally. Every selected board obeys the seven-chip total and four-chip-per-spot cap, then
receives the compulsory three random chips. Blank receives ten random chips.

| Seven selected chips | Effective edge | Pre-forfeit drag | Bust deletion | Bust rate |
|---|---:|---:|---:|---:|
| 4 Place 4 + 3 Place 10 | **24.01%** | 7.76% | 16.25% | 93.41% |
| 2 P4 + 2 P5 + 1 P9 + 2 P10 | 25.94% | 8.88% | 17.06% | 93.51% |
| 2 Pass + P4/P5/P6/P8/P9 | 34.05% | 16.27% | 17.78% | 94.08% |
| 4 Pass + 3 Place 4 | 32.60% | 15.94% | 16.65% | 93.95% |
| Blank / ten random | 44.75% | 27.73% | 17.03% | 94.88% |
| 4 Hard 4 + 3 Hard 8 | 48.83% | 36.02% | 12.81% | 95.21% |
| 4 Don't Pass + 3 Place 4 | **63.13%** | 46.66% | 16.47% | 96.31% |
| Diagnostic all-fair, no scatter | 15.70% | 0.21% | 15.50% | 92.86% |

The control is not a legal submitted player board; it isolates the source of loss. Its pre-forfeit
drag is statistically near zero, while its loss comes almost entirely from positive Bust remainder
being deleted.

### Why the “0-EV board” still has wager drag

The selected 4-Place-4/3-Place-10 chips are true odds, but the **played** board has ten chips. Three
mandatory scatter chips may land on Pass, Place 6/8, hardways, or Don't Pass. At least one of three
scatter chips hits Don't Pass with probability `1 - 0.9^3 = 27.1%`; a blank board hits it with
probability `1 - 0.9^10 = 65.1%`.

Therefore:

- on a genuinely all-fair board, expected non-deletion loss is approximately zero;
- on a legal selected true-odds core, scatter creates edged exposure; and
- in both cases, Bust deletion creates substantial run-level loss.

## 5. Edge at different depth/goal settings

Each cell below uses 250,000 runs and is measured **without** the shooter profit schedule — it is
the bare engine, kept as the baseline the schedule is a delta against. The post-schedule figures
that actually describe the shipped table are in section 6A. Higher goals keep the bankroll exposed
longer and are the strongest loss control; depth has a smaller and sometimes non-monotonic effect.

### 4 Place 4 + 3 Place 10

| Bankroll depth | Goal 5x | Goal 10x | Goal 50x |
|---:|---:|---:|---:|
| 2 rounds | 16.41% | 21.76% | 33.25% |
| 5 rounds | 17.61% | 22.48% | 34.40% |
| 10 rounds | 17.60% | 23.17% | 34.42% |

### Blank

| Bankroll depth | Goal 5x | Goal 10x | Goal 50x |
|---:|---:|---:|---:|
| 2 rounds | 31.29% | 40.64% | 56.92% |
| 5 rounds | 34.21% | 42.51% | 58.60% |
| 10 rounds | 35.09% | 44.28% | 59.93% |

### 4 Don't Pass + 3 Place 4

| Bankroll depth | Goal 5x | Goal 10x | Goal 50x |
|---:|---:|---:|---:|
| 2 rounds | 46.95% | 58.14% | 75.40% |
| 5 rounds | 51.36% | 61.97% | 78.52% |
| 10 rounds | 53.26% | 62.85% | 78.80% |

### How much engine retention the 12% rate recycles

Total expected allocation is `50,000/day + 12%` of action; the table below reads the LINEAR term
alone against the measured **unboosted** mixed-setting engine loss. The base subsidy sits on top of
every row and is what makes a thin day emissionary regardless. The linear term is unchanged by the
progressive split — the split halves *where the money waits*, not the rate that sizes it.

| Board | Share of measured engine loss recycled |
|---|---:|
| True-odds core | 67.4% |
| Fair spread | 62.8% |
| Mixed | 47.3% |
| Pass-heavy | 49.5% |
| Blank | 36.1% |
| Hardways | 32.9% |
| Don't-Pass-heavy | 25.7% |

Under the shipped 12% rate the weakest **post-schedule** cell measured is about 13.85% (section
6A), so the linear term sits under the engine's own take at every scheduled format — including the
20x Goal's removal, which took the old cell mix with it. That is the whole reason the rate came
down from 16.67% to 12%: the shooter schedule hands players back real money, and the funding rate
has to clear what is left. Custom battles receive neither the protocol boost nor the shooter
schedule, so custom term selection does not create this feedback in either direction.

## 6. What changing 5:6 to 3:4 did

The exact per-decision comparison is:

| Don't-Pass profit | Intrinsic edge |
|---:|---:|
| 5:6 | 9.6190% |
| **3:4 current** | **13.7273%** |
| Change | **+4.1082 percentage points** |

A common-seed, two-million-run comparison shows the collateral effect of scatter:

| Selected board | Effective edge at 5:6 | Effective edge at 3:4 | Change |
|---|---:|---:|---:|
| 4 P4 + 3 P10 | 24.12% | 24.71% | +0.59 pp |
| Fair spread | 25.79% | 26.52% | +0.73 pp |
| Mixed | 34.35% | 35.26% | +0.91 pp |
| 4 Pass + 3 P4 | 33.04% | 33.67% | +0.63 pp |
| Blank | 44.11% | 46.17% | +2.06 pp |
| Hardways | 50.32% | 50.67% | +0.35 pp |
| 4 Don't Pass + 3 P4 | 56.55% | 64.86% | **+8.31 pp** |

Players who never select Don't Pass are still affected whenever scatter places it. Blank seats are
affected the most because they scatter all ten.

## 6A. Counterfactual: 25% profit boost on 10% of shooters

This rule is **not in the contracts**. The simulator can now model it with:

```bash
/tmp/craps-system-sim --boosted-shooters-pct 10 --winnings-boost-pct 25 \
  --calibration 2000000 --seed 20260827
```

The modeled rule is deliberately precise:

- each player has an independent schedule, keyed by table seed, owner, and shooter number;
- exactly 10% of that player's shooters are boosted in expectation;
- every profit credit earned during a boosted shooter receives 25% extra;
- returned principal is not boosted, including Don't-Pass principal and live stakes returned only
  because the 512-roll cap was reached; and
- the boost is added to the in-run bankroll before the next Goal/Bust/affordability check.

The one-step expected uplift is `10% x 25% = 2.5%` of **gross eligible profit**, not 2.5% of the
starting bankroll. At the wager layer this changes the edges as follows:

| Leg | Current edge | Edge with shooter boost | Change |
|---|---:|---:|---:|
| Pass | 2.7888% | 0.3586% | -2.4303 pp |
| Place 4/5/9/10 | 0% | **-2.5000%** | -2.5000 pp |
| Place 6/8 | 2.7778% | 0.3472% | -2.4306 pp |
| Hard 4 | 12.5000% | 10.3125% | -2.1875 pp |
| Hard 8 | 10.0000% | 7.7500% | -2.2500 pp |
| Don't Pass | 13.7273% | 12.8029% | -0.9244 pp |

A negative edge in this table is a player edge. The true-odds Place legs therefore become
player-positive before the battle wrapper is considered. Don't Pass moves less because only its
3:4 profit is eligible; its returned principal is not.

The run-level effect is much larger because the board is replayed across roughly 9-12 shooters on
average and the mandatory escalator cycles multiple starting-bankroll equivalents through the
table. Two million common-seed runs per row, mixing all 12 scheduled depth/goal settings, produced:

| Selected board | Paid bankroll now | Paid with boost | Bankroll-EV lift | New effective edge |
|---|---:|---:|---:|---:|
| 4 P4 + 3 P10 | 75.29% | **90.14%** | **+14.85 pp** | 9.86% |
| Fair spread | 73.48% | **90.10%** | **+16.63 pp** | 9.90% |
| Mixed | 64.74% | 80.77% | +16.03 pp | 19.23% |
| 4 Pass + 3 P4 | 66.33% | 81.61% | +15.27 pp | 18.39% |
| Blank | 53.83% | 67.16% | +13.33 pp | 32.84% |
| Hardways | 49.33% | 57.14% | +7.81 pp | 42.86% |
| 4 Don't Pass + 3 P4 | 35.14% | 44.42% | +9.28 pp | 55.58% |
| Diagnostic all-fair/no-scatter | 83.82% | **101.20%** | **+17.38 pp** | **-1.20%** |

For the legal 4-P4/3-P10 board, pre-forfeit drag changes from +7.94% engine drag to **-7.56%**
player growth. Bust deletion rises from 16.77% to 17.42%, absorbing about 0.65 point of the gain,
so the final effective edge is still 9.86%. The all-fair diagnostic actually becomes positive
after Bust deletion; it is not itself a legal submitted board, but it exposes the direction of the
mechanism.

The effect grows with exposure. For 4-P4/3-P10, 250,000 runs per cell gave:

| Depth | Goal 5x | Goal 10x | Goal 20x | Goal 50x |
|---:|---:|---:|---:|---:|
| 2 rounds | 16.18% -> 7.80% | 21.77% -> 10.06% | 26.58% -> 11.80% | 32.43% -> 14.33% |
| 5 rounds | 17.44% -> 6.50% | 21.34% -> 6.79% | 27.64% -> 11.48% | 34.85% -> 14.13% |
| 10 rounds | 18.29% -> 6.40% | 23.31% -> 8.18% | 28.28% -> 9.46% | 34.81% -> 12.87% |

Each cell is `current effective edge -> boosted effective edge`. Long goals show lifts above 20
points because more escalated shooter exposure is eligible for the bonus.

### Focused Goal-5x result

A higher-precision rerun used two million common-seed runs at each depth for the legal
4-Place-4/3-Place-10 selection:

| Depth | Paid bankroll now | Paid with boost | EV lift | Bust deletion now -> boosted | Goal rate now -> boosted |
|---:|---:|---:|---:|---:|---:|
| 2 rounds | 83.5881% | 92.3821% | +8.7940 pp | 11.5555% -> 11.5512% | 12.7849% -> 14.0600% |
| 5 rounds | 82.3931% | 93.3182% | +10.9251 pp | 11.0765% -> 11.0938% | 12.6707% -> 14.2992% |
| 10 rounds | 82.4037% | 94.4713% | +12.0676 pp | 10.9580% -> 10.9954% | 12.7021% -> 14.4975% |

At Goal 5x, deletion is economically flat: its largest movement is only +0.0374 point. The
pre-forfeit result is what changes materially: `+4.86% -> -3.93%`, `+6.53% -> -4.41%`, and
`+6.64% -> -5.47%` engine drag at depths 2, 5, and 10 respectively. More depth means smaller
rounds and more shooters (mean hands rise from about 5.3 to 10.8 to 15.5), giving the player more
opportunities to encounter their independently scheduled boosted shooters before stopping.

### Random-versus-picked tuning at Goal 5x

Here “random” means a blank ticket that scatters all ten chips. “Picked optimum” means the
bankroll-oriented legal 4-Place-4/3-Place-10 selection; tournament best response remains dependent
on the opposing field.

With a 20% profit boost scheduled on 12% of random-ticket shooters and 2% of picked-ticket
shooters, two million common-seed runs per cell produced:

| Depth | Picked paid bankroll | Random paid bankroll | Random disadvantage |
|---:|---:|---:|---:|
| 2 rounds | 85.0247% | 77.3407% | 7.6840 pp |
| 5 rounds | 84.0627% | 76.0452% | 8.0175 pp |
| 10 rounds | 84.2132% | 75.8040% | 8.4092 pp |
| Equal-depth mean | **84.4336%** | **76.3967%** | **8.0369 pp** |

Without either boost, the mean gap is 16.3293 points. The proposed 12%/2% schedule therefore
closes about **50.8%** of the bankroll-EV disadvantage, but does not put random tickets in line
with the picked optimum.

Locally around 12% random / 2% picked, each additional percentage point of random-shooter
frequency closes about **0.76, 0.88, and 0.93 bankroll-EV point** at depths 2, 5, and 10,
respectively—an equal-depth mean of **0.86 point**. Conversely, adding one percentage point to the
picked frequency widens the mean gap by about 0.82 point. Increasing both frequencies together
therefore changes the gap very little; the economic control is their frequency difference.

Keeping the 20% payout boost and the 2% picked schedule, parity occurs near **21% of random
shooters**. A matched two-million-run check at 21%/2% measured equal-depth mean edges of 15.6876%
random and 15.5664% picked, leaving random only 0.1211 point worse. Per depth, random is 0.94 point
worse at depth 2 and 0.15/0.43 point better at depths 5/10. Thus 21% is the closest whole-percent
setting and is slightly conservative on the equal-depth mean; finer probability resolution would
put the crossover a little above 21%.

The simulator command for the proposed split is:

```bash
/tmp/craps-system-sim --winnings-boost-pct 20 \
  --random-boosted-shooters-pct 12 --picked-boosted-shooters-pct 2
```

### 15% random / 5% picked across current settings

The current scheduled Goal set is 5x, 10x, and 50x; 20x is no longer offered. With a 20% profit
boost on 15% of random-ticket shooters and 5% of picked-ticket shooters, the expected paid
bankroll is shown as `random / picked-optimum`:

| Bankroll depth | Goal 5x | Goal 10x | Goal 50x |
|---:|---:|---:|---:|
| 2 rounds | 79.58% / 87.11% | 72.92% / 82.99% | 60.63% / 73.47% |
| 5 rounds | 78.72% / 86.64% | 72.93% / 82.96% | 60.83% / 73.14% |
| 10 rounds | 78.62% / 87.07% | 72.02% / 82.63% | 60.32% / 73.51% |

The remaining picked advantage is:

| Bankroll depth | Goal 5x | Goal 10x | Goal 50x |
|---:|---:|---:|---:|
| 2 rounds | 7.53 pp | 10.07 pp | 12.84 pp |
| 5 rounds | 7.93 pp | 10.03 pp | 12.31 pp |
| 10 rounds | 8.44 pp | 10.62 pp | 13.19 pp |

Across the nine equally weighted cells, random pays 70.73%, picked pays 81.06%, and the gap is
10.33 points. Without shooter boosts those figures are 55.17%, 75.43%, and 20.27 points, so this
split closes about **49%** of the bankroll-EV gap. Moving from 12%/2% to 15%/5% mostly raises both
returns rather than bringing them closer: both schedules have the same ten-point frequency spread,
which at a 20% payout boost is the same two-point differential in expected gross-profit uplift.

If the random-ticket payout boost rises to 30% while its frequency stays 15%, and picked tickets
remain at 20% on 5% of shooters, the paid-bankroll matrix becomes:

| Bankroll depth | Goal 5x | Goal 10x | Goal 50x |
|---:|---:|---:|---:|
| 2 rounds | 85.22% / 87.11% | 80.41% / 82.99% | 71.20% / 73.47% |
| 5 rounds | 85.56% / 86.64% | 81.70% / 82.96% | 72.76% / 73.14% |
| 10 rounds | 86.07% / 87.07% | 81.11% / 82.63% | 71.99% / 73.51% |

Random remains behind in every cell, by 0.38 to 2.57 points. The equal-cell mean is 79.56% random
versus 81.06% picked, only a 1.50-point gap. Relative to the unboosted 20.27-point gap, this closes
about **92.6%** without making the random ticket the higher-bankroll-EV choice in any scheduled
cell.

### Goal-conditioned jitter proposal: keep every cell near 14-20% (NOT SHIPPED)

> **Superseded.** The jitter schedule below was the intermediate proposal and is retained as the
> evidence trail for how the amounts were chosen. The contract implements the fixed no-jitter
> schedule in the next subsection; there is no randomised percentage anywhere in the shipped
> engine.

The fixed amounts above leave the 50x formats at roughly 27-29% engine edge. A more even
counterfactual conditions the profit boost amount on the Goal while retaining player-specific
shooter eligibility:

| Ticket | Eligible shooters | Goal 5x amount | Goal 10x amount | Goal 50x amount |
|---|---:|---:|---:|---:|
| Blank/random | 15% | 23%, 24%, or 25% equally | 29%, 30%, or 31% equally | 36%/39% at 1/6 each; 37%/38% at 1/3 each |
| Picked | 5% | 12%, 13%, or 14% equally | 19%, 20%, or 21% equally | 37%, 38%, or 39% equally |

Thus the mean eligible-shooter boosts are **24% / 30% / 37.5%** for random tickets and
**13% / 20% / 38%** for picked tickets. Only profit is boosted; returned stake is still excluded.
The slightly wider four-value 50x random distribution comes from stochastic rounding of the 37.5%
target followed by independent +/-1-point jitter. Amount and eligibility draws are both bound to
the player and shooter.

Five million runs per cell produced the following effective engine edges, shown as
`random / picked-optimum`:

| Bankroll depth | Goal 5x | Goal 10x | Goal 50x |
|---:|---:|---:|---:|
| 2 rounds | 18.40% / 14.26% | 19.64% / 16.89% | 19.84% / 19.65% |
| 5 rounds | 18.48% / 14.68% | 18.31% / 17.23% | 17.92% / 19.03% |
| 10 rounds | 18.44% / 14.54% | 18.76% / 17.17% | 17.42% / 18.59% |

All 18 strategy/format cells lie between **14.26% and 19.84%**. Equal-depth averages by Goal are:

| Goal | Random edge | Picked-optimum edge | Random minus picked |
|---:|---:|---:|---:|
| 5x | 18.44% | 14.49% | +3.95 pp |
| 10x | 18.90% | 17.09% | +1.81 pp |
| 50x | 18.39% | 19.09% | -0.70 pp |
| Equal-cell mean | **18.58%** | **16.89%** | **+1.69 pp** |

This deliberately creates a crossover. Picked is better at 5x and 10x; random is better on the
average 50x Goal and specifically at depths 5 and 10, while the two are nearly tied at depth 2.
That makes ticket choice format-dependent instead of installing one universal bankroll-EV winner.

The reproducible command is:

```bash
/tmp/craps-system-sim --days 1 --schedule 1 --calibration 1 --settings 5000000 \
  --scenario __none__ --seed 20260827 \
  --random-boosted-shooters-pct 15 --picked-boosted-shooters-pct 5 \
  --random-winnings-boost-jitter-pct 1 --picked-winnings-boost-jitter-pct 1 \
  --random-goal5-boost-bps 2400 --random-goal10-boost-bps 3000 \
  --random-goal50-boost-bps 3750 \
  --picked-goal5-boost-bps 1300 --picked-goal10-boost-bps 2000 \
  --picked-goal50-boost-bps 3800 --settings-strategy blank
```

Run the same command with `--settings-strategy sharp` for the picked-optimum matrix. This is a
simulation proposal, not a claim that the current contracts already implement shooter boosts.
Compared with the fixed 30%-random/20%-picked schedule, it lowers the equal-cell edge by about
1.86 points for random and 2.05 points for picked, so it is somewhat more generous overall.

The jitter should remain narrow. Wider player-specific amount ranges add ranking luck without
changing much mean EV. Both the eligibility and amount entropy must be unavailable until after
entry and board lock; otherwise an EV-maximizer can shop accounts or entries for a favorable
schedule.

### THE SHIPPED SCHEDULE — fixed amounts, no jitter

This is what the contract implements. There is no amount jitter and no fractional rung; the two
ticket classes and the three scheduled Goals name six numbers and nothing else moves them:

| Ticket | Eligible shooters | Goal 5x | Goal 10x | Goal 50x |
|---|---:|---:|---:|---:|
| Blank/random | 15% | 25% | 30% | 40% |
| Picked | 5% | 6% | 20% | 35% |

**All nine scheduled formats**, five million runs per cell, measured on the shipped defaults at
seed 20260827:

| Depth | Blank Goal 5x | Blank 10x | Blank 50x | Picked 5x | Picked 10x | Picked 50x |
|---:|---:|---:|---:|---:|---:|---:|
| 2 rounds | 17.84% | 19.54% | 16.57% | 15.24% | 17.19% | 20.50% |
| 5 rounds | 17.68% | 18.60% | 14.78% | 16.02% | 17.43% | 19.47% |
| 10 rounds | 18.05% | 18.54% | **13.72%** | 16.17% | 17.28% | 19.73% |

Equally averaging the three bankroll depths within each Goal:

| Goal | Random edge | Picked-optimum edge | Random minus picked |
|---:|---:|---:|---:|
| 5x | 17.86% | 15.81% | +2.05 pp |
| 10x | 18.90% | 17.30% | +1.60 pp |
| 50x | 15.02% | 19.90% | -4.88 pp |
| Equal-Goal mean | **17.26%** | **17.67%** | **-0.41 pp** |

Higher edge is worse for the player. Thus picked tickets remain better at 5x and 10x, while
random tickets become materially better at 50x. Averaged across all Goals, random is 0.41 point
better rather than 1.5 points worse. The fixed schedule sits near the 14-20% corridor on the
depth-collapsed view; picked 50x is just outside it at 19.90%.

**The weakest single cell is 13.72%** (blank, depth 10, Goal 50x), which is the number the 12%
funding rate has to clear — and does, by 1.72 points. An earlier sweep at a different seed put
the same cell at about 13.85%; the difference is Monte Carlo noise, not a rule change.

The picked 5x amount was reduced from 10% to 6% specifically to make that format worse for picked
players without changing 10x or 50x. Five million runs per cell put its depth-averaged edge at
15.96%, about 0.85 point higher than the 10%-amount result. Common-seed sensitivity checks found
that each percentage point removed from the picked 5x amount raises its house edge by about
**0.205 point** around this range.

Reducing the global picked occurrence would also make 5x worse, but would simultaneously raise the
picked 10x and 50x edges. Keeping occurrence at 5% and changing only the 5x amount is therefore the
targeted lever.

These six numbers are now the simulator's **defaults**, so reproducing the table takes no boost
flags at all — every one of them remains available for exploring off-schedule settings:

```bash
/tmp/craps-system-sim --days 10 --schedule 2000 --calibration 2000 --settings 5000000 \
  --seed 20260827 --settings-strategy blank
```

Run again with `--settings-strategy sharp_place4_4_place10_3` for the picked-optimum result.

The engine implements the schedule as follows, and the contract tests pin each clause:

- eligibility is `keccak256(SHOOTER_BOOST_TAG, settlementSeed, player, handOrdinal) % 100 < chance`
  — its own domain, so it moves neither the dice, the scatter, the survival coin, the settlement
  rounding, the ladder rung nor the tie-break, and it cannot be read while entry is open;
- the ticket is classified from its **stored, pre-scatter** chip word, so the ten chips a blank
  ticket ends up playing never reclassify it as picked;
- the boost is `floor(baseHandEligibleProfit x pct / 100)`, added to the base hand **before** the
  round's escalating multiple scales it — so a high seat buys copies of one boosted run and does
  not draw a schedule per copy;
- eligible profit is winnings only: Pass profit, Place 4/5/6/8/9/10 profit, Hard 4 and Hard 8
  profit, and only the 3:4 portion of a winning Don't Pass. It excludes all wager principal, the
  live-stake refunds a roll-cap truncation pays, the stake a winning Don't Pass hands back,
  survival-flip doubling, pre-existing bankroll, and every post-run credit;
- the boosted return lands in the bankroll before the next Goal, hard-bound and affordability
  check, so a boost may legitimately cross Goal a shooter early, buy a round the run could not
  otherwise afford, flip a Bust into a Goal, and change battle rank. That is intended;
- only protocol-**scheduled** windows carry a schedule. A custom battle is handed zero and settles
  byte-for-byte as the bare engine, even when its creator picks 5x, 10x or 50x.

### Why the funding rate came down with it

The original all-ticket 25%-on-10% counterfactual broke the old recycling margin outright. At the
old `/3`-then-`/2` rule the protocol recycled 16.67% of action, while a legal light board would
retain only about 9.86% after that shooter boost — roughly **6.81% of bankroll action more
protocol credit than engine retention** for a homogeneous full-standing field, before any subsidy.

The shipped combination fixes that from both sides. The schedule is far narrower than the
counterfactual (15%/5% of shooters, not 100%), and the funding rate came down from 16.67% to 12%,
which is under the 13.72% weakest post-schedule cell measured above. The base subsidy is the part
that is knowingly emissionary, and it is a flat 50,000 rather than a rate — so it does not scale
with a field that has learned to play. Half of it waits in the progressive rather than being
laddered out on the day, which changes when the field sees the money and nothing about how much of
it exists.

Independent per-player schedules do not change the marginal bankroll expectation above, but they
do add relative ranking variance. Two players seeing identical dice can cross Goal or Bust on
different shooters solely because their boost flags differ. The schedule must therefore be bound
to future entropy after entry and board lock. If an address can inspect its schedule before entry,
an EV-maximizer can shop identities for a favorable schedule; a rational board selector also moves
toward the legs with the largest eligible gross-profit flow.

## 7. Strategic-player search, not random-player search

There are **8,917** legal board choices: one blank/ten-scatter mode plus 8,916 selected boards after
enforcing seven chips, max four per spot, and no selected Pass/Don't-Pass combination. The search
enumerates all 8,917, screens them under common random terms/dice, and refines the strongest
candidates at larger sample size. It integrates the exact expected boost-rung distribution rather
than relying on rare 100x samples.

The opponent boards below are deliberate. “Random” refers only to protocol-required dice,
scatter, survival, schedule, and tie entropy.

### Fixed diverse field

The 31 incumbents were six true-odds-core seats and five each of fair-spread, mixed, Pass-heavy,
hardway, and Don't-Pass-heavy selected boards. At standing 12 and the current `/3` boost:

| Rule | Strongest refined board cluster | Main win share | Candidate ROI |
|---|---|---:|---:|
| 5:6 | 4 DP + 3 P9 | 9.48% | +57.98% |
| **3:4** | **4 DP + 3 P9** | **8.98%** | **+47.33%** |

So 3:4 cuts the fixed-field advantage but does not make dark unattractive in an unchanging mixed
population.

### Adaptive field

To measure reaction, the model used 31 deliberate incumbents split between:

```text
light = 4 Pass + 3 Place 5
dark  = 4 Don't Pass + 3 Place 5
```

Every row then searched the full legal board space for a new best reply. Here, “best” means maximum
cash-funded ROI at standing 12, including individual return, expected boost, and the bounty pot—not
maximum win rate in isolation.

| Dark incumbents out of 31 | Best-reply character at 3:4 | Approximate result |
|---:|---|---|
| 0 | Four-chip Don't Pass | 21.25% win, +214.39% ROI |
| 5 | True-odds Place board, no Pass/DP selected | 8.86% win, +76.52% ROI |
| 10 | True-odds Place board | 8.09% win, +66.01% ROI |
| 15 | True-odds Place board | 7.83% win, +62.62% ROI |
| 25 | True-odds Place board | 8.30% win, +69.60% ROI |
| 31 | Four-chip Pass board | 14.04% win, +139.40% ROI |

At the sampled 5:6 rows, a DP-containing reply was still best with five dark incumbents and a
true-odds reply was best with ten. At 3:4, the corresponding switch occurred somewhere between
zero and five dark incumbents. In the five-dark 3:4 row, a dark board still won more fields, but
its much higher engine loss left it below the true-odds board on ROI. The precise transition
depends on the rest of the population, but the direction is robust: 3:4 makes the field
self-correct against dark concentration sooner.

This is closer to the real game-theory question than “does dark beat random players?” The result is
not a single solved Nash equilibrium. It shows a counter-strategy loop:

```text
light-heavy field -> dark is valuable
dark becomes common -> neutral true-odds boards become valuable
very dark field -> Pass becomes valuable
```

Public boards and pre-close amendments let players act on that loop in real time.

## 8. Whole-system scenarios under `50,000 + 12%`

The following use 100,000 simulated days each at 3:4, with the shipped shooter schedule and the
additive funding rule. Values are mean FLIP/day. "Bodies" here are cash-funded scenario
assumptions; upstream protocol funding details are deliberately separate.

Negative net cash burn is **issuance**. At this horizon the pool is at its steady state — payouts
have converged on funding — so the cash and accrual bases agree and the last two columns can be
read against each other directly.

| Circumstance | Regular action | Raw main allocation | Ladder paid | Progressive funded | Progressive paid | Engine edge | Net cash burn |
|---|---:|---:|---:|---:|---:|---:|---:|
| Two cash-funded blank bodies | 31,137 | 53,736 | 27,006 | 26,868 | 26,835 | 17.17% | **-48,493** |
| Three true-odds-core players + two blank bodies | 78,036 | 59,364 | 29,419 | 29,682 | 29,621 | 19.32% | **-43,961** |
| 30 true-odds-core players + two blank bodies | 500,887 | 110,106 | 54,529 | 55,053 | 54,864 | 18.90% | **-14,740** |
| 30 blank players + two blank bodies | 499,881 | 109,985 | 54,821 | 54,993 | 54,765 | 17.65% | **-21,373** |
| One score-zero true-odds-core player | 15,570 | 51,868 | 0 | 25,934 | 0 | 20.17% | 3,140 |
| One standing-12 true-odds-core player | 15,648 | 51,877 | 25,169 | 25,939 | 25,808 | 16.01% | **-48,472** |
| 20 prepaid 25k days + two cash bodies | 343,172 | 91,180 | 46,060 | 45,590 | 45,379 | 18.31% | 15,945 |
| 40-ticket heterogeneous cohort | 623,118 | 124,775 | 61,457 | 62,388 | 62,152 | 25.83% | 37,340 |

Read against the arithmetic in section 2, these land where the rule predicts. Doubling the base
doubled the thin-field issuance almost exactly, and the 30-player tables that used to cross into
net burn now sit on the issuing side: at a ~18% field edge the crossing is above thirty ordinary
tickets and none of these fields reaches it in ordinary seats alone. Only the heterogeneous
40-ticket cohort — whose weighted edge is 25.8%, not 18% — actually burns.

### The score-zero table never pays its pool out

`fresh_solo_no_bodies` is the degenerate case and is worth stating plainly. A scoreless winner is
credited nothing, so its ladder award rolls entirely into the pool **and** its progressive
candidate is entirely retained. Over 100,000 days that table banked 25,934 FLIP/day of contribution
plus 25,844 FLIP/day of rollover and paid out **zero**, ending on a pool of 5.18 **billion** FLIP.

That is the rule behaving exactly as specified, not a defect: nothing was minted, and the whole
figure is a liability against a wallet that cannot collect it. But it does mean the pool has no
upper bound in general — the ~21M equilibrium in section 8a is a property of a field that can
actually claim, not of the mechanism. The bounded quantity is emission, not the balance.

The established solo player measured **+212.2% ROI** on its own burn; the score-zero version, which
can take neither the boost nor the progressive, measured **-13.8%**. The difference is the base
subsidy landing on a single seat. This risk is a property of the base and exists independently of
the 12% rate — it is the price of keeping a cold table running, and it is why the base is a flat
figure rather than a rate that would grow with the field.

A battle-only run with 22 free/pass-funded seats issues far more credit than current-day entry
burns (`comped_20_passes`, -537,399 FLIP/day). That number is not an end-to-end loss estimate: the
cost and probability that created the passes are outside the battle module and must be added
before judging pass economics.

## 8a. The progressive

Half of every opened day's raw main allocation is banked in **one global pool**, shared by all nine
scheduled depth/Goal formats and by every day. Nothing else funds it except protocol money an
activity score denied (below). Custom battles neither contribute nor draw.

### Qualification is the shared roll prefix, not a new draw

An award is decided entirely by the already-finalized main battle: the recipient is the winner the
existing comparator named, its stop must be `Goal`, and its **cumulative dice-roll count** is
compared against a cutoff for that window's depth and Goal multiple. Rare is tested first and
overrides; a field never pays both rungs.

| Bankroll depth | Goal 5x common / rare | Goal 10x common / rare | Goal 50x common / rare |
|---:|---:|---:|---:|
| 2x | 150 / 185 | 205 / 245 | 340 / 395 |
| 5x | 215 / 260 | 275 / 320 | 405 / 455 |
| 10x | 265 / 315 | 325 / 375 | 455 / 500 |

The table was calibrated at 3,000,000 independent blank/random runs per format, then each cutoff
rounded to its nearest multiple of five; no cutoff moved more than two rolls. Conditional on
reaching Goal, common qualification measured 6.97%-8.66% and rare 0.335%-0.892%. The unrounded
starting points were probability-matched integer quantiles, **not** "average rolls per shooter"
multiplication — long shooters are correlated with run outcomes, so the two are not the same thing.

Because the battle's dice are shared, shooter `n` begins and ends on the same roll for every
entrant still in it. The criterion therefore adds **no per-player roll and no jackpot RNG**: it
reads the shared cumulative prefix at which the winning ticket stopped. The deliberate consequence
is that a very long final shooter can push a winning ticket over a cutoff on few shooters, and many
short shooters need not qualify merely because their count is high. Rolls never enter the
comparator — ranking is Goal/Bust then hands, unchanged. The engine's 512-roll shooter cap and
4,096-roll slip budget give a hard maximum of 4,607 cumulative rolls.

### Award and standing

```text
candidate = floor(pool / 2)   if rolls >= rare
          = floor(pool / 10)  if rolls >= common
          = 0                 otherwise

paid  = standingShare(candidate, winnerStanding)
pool -= paid
```

The candidate is already in the pool, so the curve applies to it directly and only the credit is
deducted — what the curve denies never left and is not added back. Each later award uses the
then-current balance; nothing is reserved or snapshotted per window.

### Activity-standing rollover

Every wei of protocol-funded value a standing score denies now goes **into the pool** rather than
being left unminted: the main ladder award, a contested high-lane boost, and the boost capital
offered to a sole high rider (banked before the run is consulted, so only admitted capital rides).
Compared at the same granule and rounding stage the payment lands on, so `credit + rollover` is the
full-standing award exactly, and both are zero at full standing.

Player money is never swept: bounties, principal, run losses, Bust deletion, ladder
under-realisation and rounding dust all stay where they are.

### Measured trajectory

Committed as the `mixed_40_cohort` scenario — forty daily tickets, twenty blank/random and five
each of fixed Place 4/10, mixed, Pass-heavy and 3:4 Don't-Pass-heavy, every seat at standing 12.
Run with `--worlds`:

```bash
/tmp/craps-system-sim --days 730 --worlds 500 --scenario mixed_40_cohort \
    --calibration 1 --schedule 1 --settings 0 --seed 20260827
```

| Quantity | Mean per day |
|---|---:|
| Bankroll action | 625,626 FLIP |
| Post-shooter engine retention | 159,440 FLIP (25.48% of action) |
| Immediate ladder paid | 62,527 FLIP |
| Progressive contribution | 62,539 FLIP |
| Progressive paid out | 37,679 FLIP |
| Total emission, counting stored pool value | 125,066 FLIP (19.99%) |
| Net | **34,374 FLIP burn (5.49%)** |

Because every modeled seat is at standing 12, `prog_rolled_per_day` is exactly zero here. A live
population below the floor will grow the pool faster and leave more of each candidate in it.

The pool reached a day-730 mean of **19.28M FLIP** (median 19.12M, 10th-90th 13.82M-24.97M),
paying **9.61 common and 0.149 rare awards a year**. A 100-world ten-year extension ended at a mean
of **21.40M** (median 20.88M), with payouts (56,956/day) having nearly caught funding
(62,504/day) — so the pool approaches a roughly 21-million level under this cohort rather than
growing without bound.

`--worlds` also prints `WORLDS_IDENTITY`, which is the accounting check worth reading: emission on
an **accrual** basis (counted when banked) and on a **cash** basis (counted when awarded) differ by
exactly the pool's growth, and the residual is zero. That is what makes "a payout is a release, not
a second issuance" a measured statement rather than an assertion.

### The equilibrium is edge-dependent

The 40-ticket break-even estimate in section 2 assumes a 16% efficient field. The modeled cohort
deliberately is not one:

| Behavior | Measured bankroll loss |
|---|---:|
| Blank/random | 17.85% |
| Fixed Place 4/10 | 18.37% |
| Mixed | 28.25% |
| Pass-heavy | 26.69% |
| 3:4 Don't-Pass-heavy | 59.81% |
| Weighted field | ~25.5% |

At about 15,615 bankroll action per complete daily ticket and the 50,000 base:

| Weighted post-shooter edge | Approximate zero-EV daily tickets |
|---:|---:|
| 16.00% efficient-field policy assumption | 80 |
| 17.85% all blank/random | 55 |
| 18.37% fixed Place 4/10 | 50 |
| 25.5% modeled heterogeneous field | 24 |

For the modeled field the continuous breakeven is about 23.6 tickets: 23 emits roughly 1,300
FLIP/day and 24 burns roughly 800. This low-participation emission is intended; there is
deliberately no hard issuance cap.

### Where the numbers are pinned

The cutoffs and the base subsidy live in two places — `contracts/CrapsBattle.sol` and this model —
and neither can read the other. `make check-craps-progressive` holds them together on source text,
so a cutoff moved in one and not the other fails the build rather than quietly leaving a model that
no longer describes the chain.

## 9. Vault incentives at 3:4

### Cold two-seat field

With both house and Vault modeled as cash-funded:

| Vault board | Vault main share | Vault ROI | Whole-field engine edge | Aggregate net cash burn |
|---|---:|---:|---:|---:|
| 4 P4 + 3 P10 | 44.67% | +82.32% | 20.34% | -47,451/day |
| 4 DP + 3 P4 | 50.62% | +65.48% | 39.51% | -41,226/day |

The dark board wins more often but loses far more to the engine — nearly double the whole-field
edge — and at 3:4 that loss outweighs the extra ranking power: the sharp board's ROI is the higher
of the two. Both seats are strongly ROI-positive in absolute terms because a two-seat cold table
splits the whole base subsidy between them; negative net cash burn is that subsidy being issued.

### Vault against 30 light/core players

A 200,000-day common-seed comparison used one blank house, one 4-DP/3-P4 Vault, and 30
4-P4/3-P10 players:

| Measure | 5:6 counterfactual | **3:4 current** | Change |
|---|---:|---:|---:|
| Whole-field engine edge | 17.63% | **18.74%** | +1.11 pp |
| Vault main win share | 17.32% | **15.79%** | -1.53 pp |
| Vault cash-funded ROI | +182.09% | **+152.66%** | -29.43 pp |
| Net cash burn/day | -20,977 | **-15,435** | +5,542 |

Both columns were re-measured on the current tree at the 50,000 base, so the absolute levels differ
from earlier revisions of this report for two reasons that are not the payout ratio: the shooter
profit schedule returns a large part of the engine's take to players, which is why the whole-field
edge is now around 18-19% rather than the 26-27% measured before it shipped; and the doubled base
roughly doubles the subsidy in the net-burn row. Negative net cash burn is issuance. The
*comparison* is unaffected — both sides carry the identical base and schedule — and the direction
is the same as it always was.

The payout change materially weakens dark extraction, but the Vault remains a powerful contrarian
against a static light field. If players adapt, the full-board search says the field should move
toward true-odds or Pass responses, reducing that advantage.

The Vault can also be a high roller through a pre-reserved high seat or a high pass used when its
ordinary FLIP burn fails. A high multiple scales its money, not its rank.

## 10. Boost volatility and lag

In the 32-seat true-odds-core scenario:

| Daily main metric | FLIP |
|---|---:|
| Mean budget | 83,151 |
| Mean paid | 83,247 |
| Median paid | 31,800 |
| 90th percentile | 97,910 |
| 99th percentile | 903,802 |

The budget is mean-correct, but the 100x rung makes daily payout extremely right-skewed.

**Expected ladder payout is not one day's realized payout.** The ladder's mean is exactly the
window's share, so the budget and the mean paid agree; the median day pays well under half of it
and the 99th percentile pays an order of magnitude over. Any claim about issuance is a claim about
the mean, and the tail is the reason the rule is stated as an expectation and never as a cap.

A steady 1,000,000 ordinary action/day gives a `50,000 + 120,000 = 170,000` raw main allocation —
an 85,000 ladder and an 85,000 progressive contribution. If action stops, the allocation walks down
the trailing window one day at a time and lands on the base — this is the SEVEN-DAY LAG the window
is built from, not a leak, and the simulator emits it as `SHOCK_shutdown` rows:

| Days since stop | Raw main allocation | Ladder half |
|---:|---:|---:|
| 0 | 170,000 | 85,000 |
| 1 | 152,857 | 76,428 |
| 2 | 135,714 | 67,857 |
| 3 | 118,571 | 59,285 |
| 4 | 101,428 | 50,714 |
| 5 | 84,285 | 42,142 |
| 6 | 67,142 | 33,571 |
| 7+ | 50,000 base | 25,000 |

The ramp is the trailing average emptying, one day per step; from day seven the base is all that
is left. The same lag runs the other way, so the week after a burst of activity keeps paying for
it. A one-day 10,000,000 high-action shock contributes about 68,571 main and 102,857 high budget on
each of the next seven draws, then disappears.

## 11. Economic interpretation

### What 3:4 accomplishes

- Raises direct dark wager loss substantially.
- Raises collateral loss on scatter-exposed boards, especially blank seats.
- Lowers dark win share and ROI in static light fields.
- Causes rational best responses to leave Don't Pass at a lower dark population share.
- Increases whole-field net burn in the modeled Vault/light scenario.

### What it does not accomplish

- It does not make Don't Pass strategically useless against a light-heavy field.
- It does not produce one stable best board; shared dice create counters and cycles.
- It does not solve thin-field base subsidy, which the progressive split does not change either:
  the base is emission whether it is laddered or banked.
- It does not eliminate the Vault's incentive to choose a contrarian board against static players.
- It does not make fixed-field ROI portable to an adaptive live population.

### Why payout reduction is preferable to assuming random opponents

The meaningful design target is not “dark loses intrinsically” or “dark beats blank.” It is whether
the cost of dark is high enough that copying it creates its own counterpopulation. The 3:4 sweeps
show that behavior: dark remains a tactical response, while concentration invites fair/Pass
responses sooner than 5:6 did.

## 12. Risks and monitoring

| Risk | Current evidence | Useful production metric |
|---|---|---|
| Reactive last-mover board choice | Full legal search finds field-dependent counterboards | Board composition by close-time minute; amendment rate |
| Vault bounty extraction | 15.79% win share vs 30 static light players | Vault win share and pot credit by opponent mix |
| Thin-field base subsidy | 50,000 FLIP/day allocated whether or not the table earned it; break-even near 80 ordinary tickets at the 16% policy edge, ~24 at the modeled field's 25.5% | Organic entrants, allocation, protocol/player head count |
| Progressive as an unbounded liability | 500x730d cohort settles near 19.3M and a 100x10y extension near 21.4M, with payouts converging on funding — but a purely score-zero field pays out nothing and reached 5.18B over 100,000 days | `progressivePool()`, funding vs payout per day, winner standing distribution |
| Rare rung concentration | One award takes half the pool; ~0.15/year in the modeled field | Time since last rare award, pool at award, winner standing |
| 12% rate too generous for lowest-loss cells | 12% linear rate vs 13.72% weakest measured post-schedule cell | Rolling engine retention vs frozen budget by terms |
| Shooter schedule reaching principal | Profit-only by construction; oracle differential and 22 focused fixtures | Realized boost / eligible profit, by ticket class and Goal |
| Pass provenance omitted | Free-seat battle ledger strongly issuance-positive | Pass source cost, award rate, exercise rate, expiry/non-use |
| Tail cash-flow volatility | Median 31.8k vs mean 83.2k and p99 903.8k | Rung, budget, actual boost, rolling tail reserve |
| Custom settlement lumping | Custom action books on settlement day | Age and volume of custom slots settled per day |

## 13. Validation and limitations

- The simulator implements current 3:4 arithmetic exactly in integer sixtieths of FLIP.
- It enforces the legal seven-chip/max-four selected board and Pass/Don't-Pass exclusion.
- It preserves one shared shooter per field and owner-specific scatter and survival.
- The strategic search considers all 8,917 legal board choices at screening depth, then refines a
  broad union of the best ROI, win-rate, and engine-return candidates.
- Engine tables use two million runs per mixed-setting row and 250,000 per fixed setting.
- Scenario tables use 100,000 days; the Vault 5:6/3:4 comparison uses 200,000 common-seed days.
- Progressive trajectories use `--worlds`: independent worlds rather than one long path, because
  the rare rung takes half the pool and a single path is not a distribution. 500 worlds x 730 days
  for the two-year figures, 100 x 3,650 for the ten-year extension.
- The nine roll cutoffs were calibrated at 3,000,000 blank/random runs per format and are
  probability-matched integer quantiles rounded to the nearest five, not a shooter-count product.
- The model's progressive is graded against the contract by `make check-craps-progressive`, which
  compares the base subsidy, both divisors and all eighteen cutoffs on source text.
- The reported strategic searches use 5,000 common-random-number screening samples and 200,000
  refinement samples. ROI integrates the exact boost-rung expectation to remove rare-100x sampling
  noise, but field outcome and run return remain Monte Carlo estimates.
- Whole-system Monte Carlo rows model the scheduled lane. Donations are deterministic pot add-ons,
  and custom battles have no protocol boost, so those paths are specified in the implementation
  overview rather than assigned an arbitrary arrival distribution here.
- No gas, market-price response, player arrival timing, collusion, hidden off-chain coordination,
  or upstream lootbox/pass economics are modeled.
- A full legal best-response search is not a solved Nash equilibrium. It establishes that the best
  reply changes with population composition and that 3:4 moves the transition away from dark.
- Source was changing during analysis. Re-run the commands above after any further contract edit;
  the contract remains the source of truth.
