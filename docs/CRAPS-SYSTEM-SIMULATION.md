# Craps Battle System Economic Simulation

> Source snapshot: current uncommitted working tree on 2026-08-27. The contract is the source of
> truth. In particular, the live modeled-loss constant is `action / 8`, not the `/36` still present
> in older design specs.

This report models the complete economic loop implemented by
[`CrapsBattle.sol`](../contracts/CrapsBattle.sol): scheduled terms, ordinary and high entries,
protocol seats, configurable Vault boards, individual runs, Bust deletion, battle ranking,
bounties, high-lane riders and contests, the seven-day bonus calculation, window weights, boost
lottery, activity rationing, passes, and Coinflip-credit payouts.

Selected boards must contain exactly seven named chips, with no more than four on any one spot.
Settlement then scatters the remaining three chips randomly. The cap applies to the submitted
seven-chip board; scatter may make the resolved board exceed four on a spot. Blank tickets still
scatter all ten chips.

The reproducible simulator is [`scripts/craps-system-sim.cpp`](../scripts/craps-system-sim.cpp).

```bash
g++ -O3 -std=c++20 -pthread scripts/craps-system-sim.cpp -o /tmp/craps-system-sim
/tmp/craps-system-sim --days 10000 --calibration 250000 --schedule 500000 --settings 100000 --seed 20260827
```

Use `--scenario NAME` to run one built-in circumstance. The simulator uses a fast deterministic
64-bit mixer rather than Keccak, but preserves independent domains and the shared-shooter
structure. The important distributional result was also checked through the actual Solidity
resolver; details are below.

## Executive Summary

1. **The current bonus proxy is `/8`, not `/36`.** With steady action, ordinary seats fund main
   boosts at `action / 16`. High action funds main at `action / 40` and the high lane at
   `3 x action / 80`. Total above-floor recycling is therefore 6.25% of booked bankroll action.

2. **`/8` is conservative above the floor in the tested legal space.** The lowest-loss selected
   board tested—four named chips on Place 4 and three on Place 10, plus the compulsory three
   random chips—lost about 24.42% of starting bankroll across the scheduled setting mix. A blank
   board lost about 43.77%. The lowest of the 12 scheduled cells was about 15.99%, above the 12.5%
   modeled loss.

3. **Bust deletion is essential—and fair bets do not create the other loss.** Depending on board,
   deleting the positive remainder on Bust added about 13.2–18.1 percentage points. On the legal
   4/3 fair core, about 16.79 points came from deletion and about 7.63 from the three compulsory
   scatter chips landing on edged bets. A ten-chip all-fair control had pre-forfeit drag
   statistically indistinguishable from zero. The remainder still ranks a Bust, but is not paid.

4. **The 15,000-FLIP floor, not `/8`, is the thin-table subsidy risk.** One established ordinary
   player with no protocol bodies was about **+48.5% ROI** in the full-system simulation because the
   player received its own bounty back and won the floor boost uncontested. The same score-zero
   player received no boost and remained negative. Two cash-funded blank protocol bodies were
   approximately neutral but issued about 550 FLIP/day more credit than they burned in the
   100,000-day point estimate.

5. **Pass funding and action accounting must be evaluated together.** A pass-funded seat burns no
   face cost that day, but it receives run returns and bounties and books its full nominal bankroll
   as action for later boosts. This is not automatically protocol-wide inflation—the pass may have
   been purchased or funded by a lootbox—but a battle-only ledger makes comped fields look strongly
   issuance-positive.

6. **Board choice is a tournament game, not merely a house-edge choice.** Against 31 blank seats,
   the symmetric blank baseline is 3.125%. An established candidate won about 4.53% with legal
   4/3 Place 4/10, 5.21% with legal 4/3 Pass/Place 4, and 9.35% with legal 4/3 Don't Pass/Place 4.
   Corresponding simulated ROIs were about +6.2%, +8.9%, and +41.6%. A score-zero Don't-Pass
   candidate still returned about +20.2%, because standing rations only the boost, not bounties.

7. **No homogeneous tested board is a stable equilibrium.** In the exploratory best-response
   matrix, every field of 31 identical boards offered a profitable different-board deviation.
   Don't Pass was the best tested response to six of seven homogeneous fields; against a
   Don't-Pass field, the mixed light board was the best tested response. Public boards plus
   pre-close amendments make this a reactive, last-mover strategy game.

8. **The configurable Vault board creates a real governance incentive.** Against 30 legal 4/3
   fair-core players, the two blank protocol bodies won about 22.3% of main pots together. With the
   house blank and the Vault on legal 4/3 Don't Pass/Place 4, the house won about 10.6%, the Vault
   17.9%, and the players 71.4%. The Vault's simulated ROI was about +133.8%, funded mainly by
   player bounties.

9. **The boost ladder is mean-correct but extremely right-skewed.** In the healthy Place-4 field,
   a roughly 31,229-FLIP daily main budget produced a median realized main boost near 11,700,
   a 90th percentile near 36,100, and a 99th percentile near 348,200. Budget is an expectation,
   never a daily cap.

## 1. Three Different “Edges”

The analysis keeps three concepts separate:

| Measure | Definition | What it answers |
|---|---|---|
| Engine edge | `(bankroll burned - individual run credit) / bankroll` | What the dice/run/Bust rules retain before tournament prizes |
| Player ROI | `(all credits - that actor's entry burns) / entry burns` | Whether a particular board and field composition is attractive |
| Net cash burn | Current battle-entry burns minus all Coinflip credits | Whether this module's current-day credit obligation rose or fell |

The third measure is deliberately labeled **cash** burn. For a free pass, it excludes whatever
economic cost created the pass upstream. Coinflip credit is also a future stake obligation rather
than immediately liquid FLIP.

## 2. Exact Current Bonus Calculation

Let the seven prior settlement-day books contain:

```text
A_R(d) = dayStaked[d] - highStaked[d]
A_H(d) = highStaked[d]
```

The implementation computes, with integer floors:

```text
E_R = floor(sum(floor(A_R(d-i) / 8), i=1..7) / 7)
E_H = floor(sum(floor(A_H(d-i) / 8), i=1..7) / 7)

recycledHigh = floor(E_H / 2)
fromHighToMain = floor(recycledHigh * 2 / 5)

highBudget = recycledHigh - fromHighToMain
mainBudget = max(15,000, floor(E_R / 2) + fromHighToMain)
```

For steady action, ignoring one-FLIP floors:

```text
mainBudget = max(15,000, A_R / 16 + A_H / 40)
highBudget = 3 A_H / 80
total non-floor budget = (A_R + A_H) / 16
```

The main floor stops binding around:

```text
A_R + 0.4 A_H = 240,000 FLIP/day
```

One ordinary full-day seat books about 15,620 bankroll action on average. With two ordinary
protocol bodies, the main calculation clears the floor at roughly another 13.4 full-day seat
equivalents.

### What Counts as Action

- Ordinary seat: the bankroll, not its bounty.
- Contested high seat: `H x bankroll`, all classified as high action.
- Sole high seat: `H x bankroll + (H - 1) x bounty`; the extra bounties genuinely ride the run.
- Protocol, pass-funded, and prepaid seats: the same nominal action as cash seats.
- Protocol-funded boost: never recycled into new action.
- Scheduled windows: booked to the protocol day they played, even if settled later.
- Custom battles: booked to the current protocol day when settlement executes.

That last distinction means delayed custom settlement can make the daily action series lumpy;
scheduled settlement cannot be delayed into a different action day.

### High Split

The high portion is exactly the advertised 30/20/50 split of **modeled** high burn:

- 30% to the future high boost.
- 20% to the future main boost.
- 50% unrecycled.

It is not 30/20/50 of actual dice retention.

## 3. Schedule and Seat Cost

Five million simulated schedules produced:

| Whole-day quantity | Mean FLIP |
|---|---:|
| Bankroll action per ordinary seat | 15,619 |
| Bounties per ordinary seat | 7,179 |
| Ordinary face cost | 22,798 |
| High face cost, including the 90% 10x / 10% 100x draw | 432,887 |
| Event bankroll | 10,369 |
| Event bounty | 3,862 |

These reproduce the implementation comments' approximately 22,802 normal and 433,240 high
expectations. They also explain the fixed future-day prices:

- Normal 25,000: roughly a 9.7% premium to expected face cost.
- High 450,000: roughly a 3.9% premium.

For one high seat, expected high action is larger than `19 x bankroll` because its extra bounties
ride the run. It was about 421,000–425,000 FLIP/day in the scenario runs. With two or more high
seats, each books roughly `19 x 15,619 = 296,761` FLIP/day and their extra bounties are transfers
rather than action.

## 4. Engine House Edge and Bust Deletion

The following uses 1,000,000 independent runs per strategy, equally mixing the 12 scheduled
depth/goal combinations. Every selected board is legal under the four-chip-per-spot cap. A selected
strategy receives three random chips; a blank strategy receives all ten randomly.

| Seven named chips | Effective edge | Pre-forfeit engine drag | Bust deletion | Bust rate |
|---|---:|---:|---:|---:|
| 4 Place 4 + 3 Place 10 (“fair core”) | 24.42% | 7.63% | 16.79% | 94.31% |
| Fair spread over 4/5/9/10 | 26.27% | 8.56% | 17.71% | 94.41% |
| Mixed light board | 35.12% | 16.80% | 18.31% | 94.96% |
| 4 Pass + 3 Place 4 | 32.16% | 14.94% | 17.22% | 94.78% |
| Blank / all ten random | 43.77% | 26.08% | 17.69% | 95.54% |
| 4 Hard 4 + 3 Hard 8 | 50.30% | 37.10% | 13.20% | 95.95% |
| 4 Don't Pass + 3 Place 4 | 56.37% | 38.23% | 18.14% | 96.35% |

“Pre-forfeit engine drag” compares starting bankroll with the raw engine bankroll before a Bust is
zeroed. “Bust deletion” is the additional gap between that raw figure and actual payment. The two
components add to the effective edge apart from final award-rounding drift.

The first board's **seven selected chips are all on 0-EV legs**. Its 7.63% pre-forfeit drag does not
come from those legs: settlement compulsorily scatters another three chips across all ten spots.
Those chips can land on Pass, Place 6/8, hardways, or Don't Pass, all of which carry an implemented
edge. Repeating and escalating the board compounds that small per-hand scatter edge. A diagnostic
ten-chip board forced entirely onto fair Place 4/5/9/10 legs, with scatter disabled, measured
−0.31% pre-forfeit drag in one million high-variance runs—statistically consistent with zero—while
about 15.95% was still deleted on Bust. In other words: on genuinely fair bets, expected loss comes
from Bust deletion; the actual battle board is not all-fair after scatter.

The 4/3 fair core is the lowest tested selected board, not a proof of global optimality. Board
variance also changes stopping behavior, so two boards with similar per-hand edge can have different
run-level effective edges.

### Different Scheduled Settings

Effective loss rises sharply with the goal. Bankroll depth moves it much less.

**Legal 4 Place 4 + 3 Place 10 fair core**

| Bankroll depth | Goal 5x | Goal 10x | Goal 20x | Goal 50x |
|---:|---:|---:|---:|---:|
| 2 rounds | 15.99% | 21.23% | 26.21% | 31.42% |
| 5 rounds | 16.58% | 21.07% | 26.71% | 31.78% |
| 10 rounds | 17.08% | 21.66% | 27.50% | 32.02% |

**Blank board**

| Bankroll depth | Goal 5x | Goal 10x | Goal 20x | Goal 50x |
|---:|---:|---:|---:|---:|
| 2 rounds | 29.67% | 39.03% | 45.49% | 53.86% |
| 5 rounds | 32.27% | 40.81% | 47.87% | 57.21% |
| 10 rounds | 33.63% | 41.53% | 49.30% | 56.42% |

The 250,000-run-per-cell sweep gave these tested minima and maxima over the 12 scheduled settings:

| Board | Lowest cell | Highest cell |
|---|---:|---:|
| 4 Place 4 + 3 Place 10 | 15.99% | 32.02% |
| Fair spread | 16.95% | 36.97% |
| Mixed | 23.78% | 46.66% |
| 4 Pass + 3 Place 4 | 21.74% | 45.28% |
| Blank | 29.67% | 57.21% |
| Hardways | 32.84% | 64.03% |
| 4 Don't Pass + 3 Place 4 | 39.38% | 71.35% |

Goal multiple is the largest control: a high goal keeps the run exposed longer and leaves a larger
expected Bust-forfeiture component. Depth generally raises turnover and pre-forfeit drag, but some
cells are non-monotonic because goal hits, survival flips, the five-hand escalator, and Monte Carlo
tail noise interact. The simulator's `--settings N` option emits every cell for auditing.

### How Much Actual Burn `/8` Recycles

Above the floor, 6.25% of action becomes expected boost. As a fraction of measured engine burn:

| Board | Approximate share of actual engine burn recycled |
|---|---:|
| 4 Place 4 + 3 Place 10 | 25.6% |
| Fair spread | 23.8% |
| Mixed | 17.8% |
| 4 Pass + 3 Place 4 | 19.4% |
| Blank | 14.3% |
| Hardways | 12.4% |
| 4 Don't Pass + 3 Place 4 | 11.1% |

At the lowest measured scheduled cell, it is about 39.1%. Thus `/8` can accurately be called “half
of the 12.5% modeled loss,” but not “half of actual burn.”

## 5. Whole-System Steady-State Scenarios

The ordinary scenarios below use 100,000 simulated days per circumstance. Values are mean FLIP/day.
“Net burn” is positive when current battle burns exceeded all credits and negative when credits
exceeded current battle burns.

| Circumstance | Regular action | Main budget | Main boost paid | Net cash burn | Interpretation |
|---|---:|---:|---:|---:|---|
| Empty; both bodies unfunded | 0 | 15,000 | 0 | 0 | Floor is quoted but no field finalizes it |
| Two blank bodies, cash-funded | 31,333 | 15,000 | 14,572 | **-550** | Near break-even; cold floor slightly issuance-positive in this run |
| Two blank bodies, pass-funded | 31,126 | 15,000 | 14,349 | **-46,221** | Upstream pass cost excluded |
| Three fair-core players + two blank bodies | 78,239 | 15,000 | 14,815 | 10,527 | Actual engine retention clears the floor |
| 30 fair-core players + two blank bodies | 499,664 | 31,229 | 31,276 | 98,749 | `/8` budget is comfortably covered |
| 30 blank players + two blank bodies | 499,108 | 31,194 | 31,268 | 185,584 | Same action; much larger actual retention |
| One score-zero fair-core player, no bodies | 15,631 | 15,000 | 0 | 3,550 | Bounty returns; boost is deleted |
| One full-standing fair-core player, no bodies | 15,594 | 15,000 | 14,588 | **-11,039** | Uncontested floor creates strong positive EV |
| 20 free fair-core passes + two free body passes | 344,664 | 21,594 | 21,042 | **-434,177** | Battle-only view; pass origin excluded |
| 20 prepaid fair-core days + two cash bodies | 342,863 | 21,477 | 21,025 | 119,843 | Includes 20 x 25,000 prepaid burn/day |

The thin-field sign change is intuitive. Bounties normally transfer within the field, so aggregate
coverage is approximately engine retention minus paid boost. A fair-core field needs about
`15,000 / 24.42% = 61,400` ordinary bankroll action to cover the floor in expectation, despite the
formula remaining on its floor until 240,000.

### High-Roller Scenarios

These use 100,000 simulated days per circumstance.

| Circumstance | Regular action | High action | Main / high budgets | Main / high boost paid | Net cash burn |
|---|---:|---:|---:|---:|---:|
| 20 fair-core + 2 bodies + 1 high | 344,698 | 421,196 | 32,074 / 15,795 | 32,276 / 11,127 | 152,131 |
| 20 fair-core + 2 bodies + 2 high | 343,759 | 594,996 | 36,358 / 22,312 | 35,857 / 21,865 | 165,181 |
| Forced 100x; 10 fair-core + 2 bodies + 2 high | 186,951 | 3,115,849 | 89,581 / 116,846 | 88,593 / 115,665 | 695,426 |

The sole high lane spends less than its budget on average because the boost rides the seat's run:
a Bust returns none, and other results return it pro rata. A contested, full-standing lane pays the
drawn boost outright to its high winner.

## 6. Seven-Day Lag and Shock Behavior

The averaging smooths but does not reserve funds. A steady 1,000,000 ordinary action/day produces
a 62,500 main budget. If action stops completely, the next budgets are approximately:

| Days since stop | Main budget |
|---:|---:|
| 0 | 62,500 |
| 1 | 53,571 |
| 2 | 44,642 |
| 3 | 35,714 |
| 4 | 26,785 |
| 5 | 17,857 |
| 6+ | 15,000 floor |

A one-day 10,000,000 high-action settlement contributes about 35,714/day to main and 53,571/day
to high for seven consecutive budgets, then disappears. Because custom action is booked when it
settles, a delayed custom batch can create exactly this kind of step.

## 7. Boost Lottery and Activity Rationing

Each window's quarter multiplier is:

| Probability | Paid multiple of its base |
|---:|---:|
| 76.8% | 0.25x |
| 20.8% | 1x |
| 2.0% | 10x |
| 0.4% | 100x |

The mean is exactly 1x before granule rounding. Across seven windows, at least one 100x rung occurs
on about 2.77% of days, roughly once every 36 days. Since the event owns half the daily budget, a
100x event alone pays roughly 50 daily budgets.

For the healthy fair-core scenario:

| Metric | Main boost FLIP/day |
|---|---:|
| Mean budget | 31,229 |
| Mean paid | 31,276 |
| Median paid | 11,700 |
| 90th percentile | 36,100 |
| 99th percentile | 348,202 |

Standing zero deletes only the protocol boost. Individual run returns, main bounties, donations,
and contested high principal are not rationed. In the simulation:

- One fresh 4/3 fair-core candidate against 31 established blank seats won 4.53% of pots and
  returned **-1.6% ROI** without boost.
- One fresh legal 4/3 Don't-Pass candidate won 8.95% and returned **+20.2% ROI**.

The activity rule is effective against fresh-wallet boost farming. It does not stop a fresh wallet
from taking player-funded bounties through a strategically different board.

## 8. Tournament Strategy and Equilibrium

### Validation Against Production Solidity

The fast simulator's key 31-blank matchup was replayed through the actual Solidity engine for
2,000 battles per candidate, including production Keccak scatter, shared shooter dice, survival
flips, raw Bust remainders, and composite ranking. Every tested candidate obeyed the four-chip cap:

| Candidate | Fast simulation win rate | Solidity wins / 2,000 | Solidity rate |
|---|---:|---:|---:|
| 4 Place 4 + 3 Place 10 | 4.53% | 100 | 5.00% |
| Fair spread | 3.37% | 67 | 3.35% |
| 4 Pass + 3 Place 4 | 5.21% | 88 | 4.40% |
| 4 Don't Pass + 3 Place 4 | 9.35% | 195 | 9.75% |

The independent implementations agree on both ordering and scale.

### One Established Candidate Against 31 Blank Seats

| Candidate board | Main win rate | Candidate ROI |
|---|---:|---:|
| 4 Place 4 + 3 Place 10 | 4.53% | +6.2% |
| Fair spread | 3.37% | -6.9% |
| Mixed | 3.31% | -15.5% |
| 4 Pass + 3 Place 4 | 5.21% | +8.9% |
| Blank | 3.09% | -20.6% |
| Hardways | 3.60% | -24.8% |
| 4 Don't Pass + 3 Place 4 | 9.35% | +41.6% |

These are field-dependent tournament returns, not intrinsic board returns. If all 32 players use
Don't Pass, each again receives roughly one thirty-second of the bounties while suffering the high
engine edge.

### Homogeneous-Field Best Responses

The exploratory matrix used 20,000 days per cell, or 140,000 fields per candidate/incumbent cell.
ROI has more Monte Carlo noise than win share, but the deviations are too large for the conclusion
to depend on a few points.

| 31 incumbents use | Best tested candidate | Candidate win rate | Candidate ROI |
|---|---|---:|---:|
| 4 Place 4 + 3 Place 10 | 4 Don't Pass + 3 Place 4 | 19.73% | +157% |
| Fair spread | 4 Don't Pass + 3 Place 4 | 16.69% | +119% |
| Mixed | 4 Don't Pass + 3 Place 4 | 16.60% | +118% |
| 4 Pass + 3 Place 4 | 4 Don't Pass + 3 Place 4 | 20.17% | +165% |
| Blank | 4 Don't Pass + 3 Place 4 | 9.35% | +41.6% |
| Hardways | 4 Don't Pass + 3 Place 4 | 42.86% | +420% |
| 4 Don't Pass + 3 Place 4 | Mixed light board | 12.36% | +84.1% |

Therefore none of the seven homogeneous tested fields is a Nash equilibrium. This does not prove
there is no heterogeneous or mixed-strategy equilibrium.

The mechanism is a combination of:

- shared shooter dice;
- different boards reacting differently to that shooter;
- a Goal-first, then longevity-first ranking;
- positive Bust remainder as a later tiebreak;
- winner-take-all bounties; and
- public boards that remain amendable until entry closes.

The last entrant can observe the existing field and choose a contrarian response. Earlier entrants
can then amend in response, so a busy close can become a board-selection game rather than a static
craps choice.

### Counterfactual: Make Don't Pass Worse

This subsection is a **historical counterfactual**, written when the contract paid 5:6; it now pays
3:4, so the "current" column below is the OLD rule and the sweep is what led to the change. The
simulator option `--dont-profit-sixths N` sweeps lower profits while leaving ranking, scatter,
bounties, standing, boost, and the four-chip board cap unchanged.

The per-shooter win probability for an implemented Don't-Pass decision is `949 / 1925`, so for
profit ratio `p` its intrinsic edge is:

```text
Don't Pass edge = 1 - (949 / 1925) x (1 + p)
```

Common-random 200,000-day matchups and 12 million stratified run calibrations produced:

| Don't-Pass profit | Per-shooter edge | Legal dark-board effective edge | vs 31 blank: win / ROI | vs 31 fair-core: win / ROI | Dark Vault: win / ROI |
|---:|---:|---:|---:|---:|---:|
| 5:6, current | 9.62% | 56.42% | 9.20% / +35.1% | 19.67% / +156.1% | 17.94% / +135.5% |
| 2:3 | 17.84% | 71.63% | 7.68% / +6.8% | 16.51% / +109.5% | 14.97% / +90.1% |
| 1:2 | 26.05% | 81.55% | 6.31% / -16.1% | 13.58% / +68.7% | 12.21% / +52.4% |
| 1:3 | 34.27% | 88.03% | 5.12% / -33.4% | 11.15% / +36.0% | 9.96% / +21.6% |
| 1:6 | 42.48% | 92.31% | 4.25% / -46.4% | 9.09% / +10.3% | 8.12% / -2.2% |
| 0:1 | 50.70% | 95.03% | 3.24% / -59.6% | 7.18% / -13.7% | 6.35% / -24.4% |

The Vault column is one blank house body, one legal dark Vault body, and 30 fair-core players. Its
ROI is the Vault's own cash-funded ROI; its win share is the main-pot share.

At 2:3, Don't Pass remained the best tested response to a homogeneous fair-core field. At 1:2,
the mixed light board became the best response there, but Don't Pass remained the best response to
a homogeneous Pass field and remained highly profitable against fair-core incumbents. Interpolating
the 1:6 and zero-profit cells puts the approximate break-even profit against favorable fair-core or
Pass fields near **1:10**. That would make the selected dark board lose roughly 93–94% of starting
bankroll across the scheduled mix. Lower payout therefore taxes the strategy but does not cheaply
remove the anti-correlated tournament advantage.

It also affects players who never select Don't Pass because scatter can place it. Three random
chips hit Don't Pass at least once with probability `1 - 0.9^3 = 27.1%`; ten random chips do so
with probability `1 - 0.9^10 = 65.1%`. Moving from 5:6 to 1:2 changed the measured effective edges:

| Board | Current 5:6 | Hypothetical 1:2 | Change |
|---|---:|---:|---:|
| 4 Place 4 + 3 Place 10 | 24.42% | 26.73% | +2.31 pp |
| Fair spread | 26.27% | 29.16% | +2.89 pp |
| Mixed | 35.12% | 37.71% | +2.60 pp |
| 4 Pass + 3 Place 4 | 32.16% | 34.54% | +2.38 pp |
| Blank | 43.77% | 51.55% | +7.78 pp |
| Hardways | 50.30% | 51.36% | +1.06 pp |
| 4 Don't Pass + 3 Place 4 | 56.37% | 81.34% | +24.97 pp |

If the design goal is only to stop a dark board from outperforming against blank fields or to
remove the Vault's incentive to choose it over neutral alternatives, 1:2 is directionally enough.
If the goal is to eliminate contrarian bounty capture against light-heavy fields, payout reduction
alone is a very blunt control; ranking, shared-shooter correlation, bounty allocation, or scatter
would need to change instead.

## 9. Vault and Protocol-Body Incentives

The current implementation gives the Vault owner three standing choices through `setVaultBoard`:

- zero: blank, with all ten chips scattered;
- any legal seven-chip board with at most four chips on a spot;
- `VAULT_BOARD_OFF`: take no automatic seat unless a pass already reserved that day.

The house remains blank. Either body can consume a banked high pass and join the high lane; their
cash fallback is ordinary only.

### Cold Table

One hundred thousand simulated days per configuration produced:

| Protocol configuration | Net cash burn/day | Main winner share |
|---|---:|---|
| House blank + Vault blank | about **-550** | Roughly 50/50 |
| Vault off; house alone | **-8,051** | House 100% |
| House blank + Vault 4 Place 4 / 3 Place 10 | **-4,211** | House 52.3%, Vault 47.7% |
| House blank + Vault 4 Don't Pass / 3 Place 4 | **+1,321** | House 44.5%, Vault 55.5% |

Standing the Vault down does not protect the floor. It removes one engine-loss source while the
remaining full-standing house still wins the entire boost, making issuance larger.

### Thirty Legal Fair-Core Players

| Protocol boards | House win share | Vault win share | Players' collective share |
|---|---:|---:|---:|
| Both blank | about 11.1% each | about 11.1% | 77.7% |
| House blank, Vault 4 Don't Pass / 3 Place 4 | 10.6% | **17.9%** | 71.4% |

With the Don't-Pass board, the Vault's simulated own ROI was about +133.8%; the 30 players'
aggregate ROI was about -20.3%. This is a governance incentive to choose a board that extracts more
of the player-funded bounty pool. It also increases protocol-wide engine burn, so “good for burn”
and “good for fair player competition” point in different directions.

### Vault High Pass

A sole high-pass Vault books the day's high multiple and its extra at-risk bounties despite no
current entry burn. With the house cash-funded and the Vault on legal 4/3 Don't Pass/Place 4, the
battle-only ledger showed about 201,000 FLIP/day more credits than current entry burns. That excludes the
lootbox or purchase economics that created the high pass.

## 10. Actor Analysis

| Actor | Rational objective | Current incentive |
|---|---|---|
| Ordinary player | Maximize run credit plus expected bounty/boost | Low-edge board in a symmetric field; contrarian rank board in a homogeneous field |
| Fresh wallet | Capture bounties without activity history | Cannot take boost, but can still profitably deviate against some fields |
| High roller | Maximize scaled run plus main/high pool | Board multiple does not improve rank; field composition determines best response |
| Vault owner | Maximize Vault returns or protocol burn | Can choose a bounty-extracting board, go high through a pass, or stand down |
| sDGNRS | Automatic protocol participation | Blank, full-standing, pass-first, otherwise cash-funded ordinary seat |
| Pass holder | Exercise prepaid/awarded day value | Books full action regardless of current-day cash provenance |
| Custom creator | Set depth, goal, bounty, bar, high multiple | Can create much higher-loss formats; receives no creator fee |
| Settler/keeper | Complete fields and book action | Scheduled action day is fixed; custom settlement timing chooses its action day |

## 11. Equilibrium and System Behavior

At scale, the `/8` feedback loop is stable in expectation under every tested board because expected
boost is below actual engine retention. The equilibrium concern is not insolvency from the linear
rate; it is **who captures the zero-sum bounty pool and when the floor overrides the rate**.

Likely behavior if players optimize:

1. Players do not converge simply on the lowest-edge board.
2. Visible field composition creates contrarian entries and last-minute amendments.
3. A once-profitable deviation becomes bad if copied by the whole field.
4. The strategy can cycle: legal Don't Pass attacks many homogeneous fields, while the mixed
   light board was the best tested response to a homogeneous Don't-Pass field.
5. Protocol bodies and especially the configurable Vault are active strategic opponents, not
   neutral liquidity.
6. Thin established fields seek the 15,000 floor; score-zero sybils cannot take it, but coordinated
   standing-bearing wallets can.

## 12. Risk Matrix

| Risk | Likelihood | Impact | Evidence |
|---|---|---|---|
| Reactive board-selection / last-mover advantage | High | High | Public amendable boards; every homogeneous tested field had a profitable deviation |
| Vault bounty extraction conflict | High if optimized | High for player distribution | Legal Don't-Pass Vault took 17.9% of pots against 30 fair-core players |
| Cold-floor positive EV | Medium | Medium | Lone established fair-core seat about +48.5% ROI; one blank body also issuance-positive |
| Pass-funded nominal-action feedback | Medium | Medium/High | Free seats book action, returns, bounties, and later boost despite no day-of burn |
| `/8` linear rate exceeds actual burn | Low in tested space | High if it occurred | Lowest measured scheduled-cell loss about 15.99%, above 12.5% model |
| Daily boost volatility | Certain | Medium | Median far below mean; 100x tail produces multi-budget days |
| High-budget/current-demand mismatch | Medium | Low for solvency | No current high field means past-funded high boost is simply unminted |
| Custom settlement-day action lumping | Medium | Medium | Custom action is booked when permissionless settlement occurs |

## 13. Recommendations

1. **Decide explicitly whether the contrarian-board tournament is intended.** It is the dominant
   strategic feature, not a small tiebreak artifact. If unintended, test alternatives such as
   per-entrant shooter streams, concealed board commitments, a non-winner-take-all bounty split,
   or a ranking based on normalized return. Each changes the product, so this needs a design choice
   rather than a local patch.

2. **Do not let the Vault board policy remain economically implicit.** A Vault-controlled board can
   materially redirect player bounties. Consider a fixed neutral board, timelocked/public policy,
   exclusion of protocol seats from player-funded bounty capture, or an explicit statement that
   the Vault is a strategic table participant.

3. **Retune or gate the 15,000 floor by organic competition.** Options include paying no boost to a
   protocol-only field, scaling the floor by non-protocol action, requiring at least two organic
   entrants, or rolling unused floor forward. Merely standing the Vault down makes the one-body
   case more issuance-positive.

4. **Model pass issuance end to end.** The battle module alone cannot say whether a free pass is
   funded. Add lootbox pass frequency, upstream box burn, pass exercise rate, body pass inventory,
   and expiry/non-use to the economic ledger before setting pass quantities.

5. **Describe `/8` precisely.** It returns half of a 12.5% conservative modeled loss. Across the
   tested scheduled mix it returned about 11.1–25.6% of actual engine burn, and roughly 39.1% in
   the lowest-loss scheduled cell.

6. **Monitor realized, not just budgeted, boost.** Track main/high action, frozen budget, current
   high head count, winner standing, rung, actual paid boost, and protocol-body win share. The
   lottery and activity ration make budget alone a poor daily cash-flow proxy.

7. **Treat custom settlement timing as part of the bonus surface.** If custom volume becomes large,
   monitor old custom slots settling into one day and consider whether custom action should be
   attributed to close time rather than settlement time.

## 14. Validation and Limitations

- Current budget formula tests passed directly in Foundry.
- The C++ engine calibration matches the earlier high-sample production-engine measurements.
- The counterintuitive board-rank ordering was independently confirmed through 256,000 actual
  Solidity slip resolutions: 2,000 battles for each of four legal selected candidates against 31
  blank incumbents.
- System scenario point estimates use 100,000 simulated days each. Shared shooter dice, 50x goals,
  and the 100x boost rung still make tail-sensitive values noisier than the raw day count suggests.
- No gas costs, transaction failures, market price response, player arrival timing, or upstream
  lootbox economics are included.
- The 4 Place 4 / 3 Place 10 fair core is the lowest tested board, not a mathematical proof of the
  global optimum.
- Best-response ROI is conditional on a static 31-seat incumbent field. Once other players react,
  those returns change; the result diagnoses strategic instability rather than promising a live
  profit.
