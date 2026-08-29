# Dice Run high-water system simulation

> Proposed-system analysis, 2026-08-28. This is not a description of the currently deployed
> contract. Raw outputs and reproducible code are linked below.

## Executive Summary

The proposed scheduled system is economically viable at the **portfolio** level with the accepted
boost schedule, but it is not a 16–18% take in every individual cell. Across 100 million runs per
cell, the four equal-weight cells average **17.45% bankroll take**:

| Scheduled cell | Effective bankroll take | Margin over 12% |
|---|---:|---:|
| 5x random, 15% shooters at +33% profit | 17.45% | +5.45 pp |
| 20x random, 15% at +45% | 15.42% | +3.42 pp |
| 5x picked, 5% at +20% | 17.37% | +5.37 pp |
| 20x picked, 5% at +50% | 19.55% | +7.55 pp |
| Equal four-cell mix | **17.45%** | **+5.45 pp** |

All four aggregate estimates remain above the 12% variable scheduled allocation. The weakest cell
is 20x random at 15.42%. This is an expectation, not a daily floor: the five independent
20-million-run random-20x blocks ranged from 12.21% to 16.62% because a few giant payouts still
move a block mean.

The additive 50,000-FLIP daily base remains intentionally emissionary at low volume. At the
schedule's expected **15,622.5 FLIP of bankroll action per full daily seat**, modeled break-even is
about:

- **72 daily seats** for an equal-Goal all-random population;
- **50 daily seats** for an equal-Goal all-picked bankroll population;
- **59 daily seats** for an equal random/picked population.

Those are expected accrual break-evens for `engine take - (50,000 + 12% of action)`. Progressive
payout timing does not change them because funding the progressive books the liability once; paying
it later only releases that liability.

The final Goal–Jackpot cutoffs remain well matched across Goals in a representative 40-seat field:

| Goal | Any jackpot field rate | Rare field rate | Any jackpot per entry | Rare per entry |
|---|---:|---:|---:|---:|
| 5x: 25x / 120x | 4.4166% | 0.4774% | 0.1104% (about 1/906) | 0.01194% (about 1/8,379) |
| 20x: 50x / 225x | 4.8568% | 0.4838% | 0.1214% (about 1/824) | 0.01210% (about 1/8,268) |

Thus 20x is about 10% easier for an entry to hit any tier, while rare odds are almost identical.
That meets “roughly the same,” not exact equality.

The raised bounds are not on the ordinary path. Scheduled escalation now uses a 32-bit
4,294,967,295x ceiling instead of the old 16-bit 65,535x ceiling. The old ceiling flattened the
wager at shooter 48 and created two artificial 512-shooter random walks; the new ceiling keeps
doubling through shooter 95. Across the 36-million-seat population matrix plus two 20-million-seat
40-player calibrations there were **zero cap stops in 76 million scheduled runs**. In the precise
40-million set, the longest G5/G20 runs were 52/57 shooters and the largest dice logs were 638/668
rolls. Across the broad population matrix, the maxima were 63 shooters, 751 rolls, and about 138
resolver work units.
The absolute 8,703-roll ceiling would charge about 1,463 units.

The superseded simulator also formed `int64(1) << shift` before applying its 65,535 clamp. Its two
cap runs reached `shift == 63` at shooter 189, which is undefined signed-shift behavior in C++.
That did not affect ordinary runs or the identity/count of the two old cap stops, but it makes their
old exact post-189 balances and the previously quoted 489,503x maximum invalid. The current code
clamps before shifting; every result in this revision was regenerated with safe arithmetic and the
new 32-bit ceiling.

Customs are intentionally absent from every scheduled result. They must preserve legacy
immediate-Goal/speed settlement and receive no boost, subsidy, progressive, BIGGEST eligibility,
or shared action credit. The live contract currently books custom settlement into `_dayStaked`;
the implementation must remove that leak.

## Method and Evidence

The simulator is an economic replica, not a byte-for-byte EVM replay. It preserves shared shooter
dice within a field, independent per-player scatter/boost/survival streams, wager settlement,
profit-only boosts, protected-Goal continuation, ending-bankroll payout, high-water ranking,
scheduled funding, ladder draws, standing, and the global progressive. It replaces Keccak with a
fast counter-based 64-bit mixer, so it tests distributions and mechanism interactions rather than
hash equivalence.

Evidence generated for this report:

| Run set | Scale | Purpose |
|---|---:|---|
| Boosted fixed-cell calibration | 400 million runs | 100m each: random/picked × 5x/20x |
| No-boost fixed-cell baseline | 400 million runs | Same four cells and block structure |
| Population matrix | 36 million seats, 5,968,750 fields | 8 field sizes × 2 Goals × 5 compositions |
| Precise mixed-40 jackpot matrix | 40 million seats, 1 million fields | 500k fields per Goal |
| Whole-system paths | 55.65 million seats | 5,000 days × 8 sizes × 5 compositions |
| Total | **931.65 million run settlements** | Plus schedule/funding bookkeeping |

Fixed-cell results are five independent 20-million-run blocks per cell. The aggregate is the
equal-weight mean. This block design exposes the payout tail instead of hiding it behind one seed.

Reproduction:

```bash
g++ -O3 -std=c++20 -pthread scripts/craps-high-water-system-sim.cpp \
  -o /tmp/craps-high-water-system-sim

/tmp/craps-high-water-system-sim \
  --population-matrix-seats 500000 --calibration 1 --schedule 1 --seed 20260828

/tmp/craps-high-water-system-sim \
  --system-matrix-days 5000 --calibration 1 --schedule 1 --seed 20260829

/tmp/craps-high-water-system-sim \
  --winner-calibration 500000 --jackpot-depth 5 --jackpot-goal 5 \
  --calibration 1 --schedule 1 --seed 202610005
```

Raw evidence:

- [`CRAPS-HIGH-WATER-CALIBRATION.tsv`](CRAPS-HIGH-WATER-CALIBRATION.tsv)
- [`CRAPS-HIGH-WATER-POPULATION-MATRIX.tsv`](CRAPS-HIGH-WATER-POPULATION-MATRIX.tsv)
- [`CRAPS-HIGH-WATER-JACKPOT-MATRIX.tsv`](CRAPS-HIGH-WATER-JACKPOT-MATRIX.tsv)
- [`CRAPS-HIGH-WATER-SYSTEM-MATRIX.tsv`](CRAPS-HIGH-WATER-SYSTEM-MATRIX.tsv)

## Mechanism Analysis

### High-water run and payout

Goal qualification latches on the first completed-shooter boundary at or above Goal. Later
shooters can use only surplus over Goal; equality is playable. The player receives the ending
bankroll, not the peak. This creates a clean separation:

- peak decides the scheduled race, Goal–Jackpot, and THE BIGGEST score;
- ending bankroll decides what the run pays;
- Goal reserve prevents post-qualification play from converting a qualified run into a Bust.

This removes the old speed race without giving the player a free peak cash-out. The main behavioral
cost is salience: a player can see a 500x peak and receive materially less if later shooters lose.
The UI needs to show both “high point” and “ending payout” prominently.

### Escalation and limits

Doubling every three shooters pushes surplus back toward Goal quickly. The ordinary run remains
short:

| Cell | Goal rate | Mean shooters | p99 resolver work units |
|---|---:|---:|---:|
| 5x random | 11.87% | 8.08 | about 41 |
| 20x random | 2.94% | 8.70 | about 47–48 |
| 5x picked | 11.98% | 7.68 | about 41 |
| 20x picked | 2.89% | 8.27 | about 46–47 |

The 512-shooter cap is therefore a tail guard, not a target duration. The roll budget is even less
likely to bind because ordinary shooters average about 8.5 rolls.

Exact entry-level duration tails in the 40-seat mix, 20 million entries per Goal:

| Goal | p95 shooters | p95 rolls | p99 shooters | p99 rolls | longest shooters | most rolls |
|---:|---:|---:|---:|---:|---:|---:|
| 5x | 13 | 138 | 15 | 173 | 52 | 638 |
| 20x | 16 | 169 | 19 | 215 | 57 | 668 |

The longest-shooter and largest-roll observations need not be the same entry. Current-contract gas
pins measured a scheduled 256-shooter engine run at 1,280,713 gas and the full-board marginal path
at about 4,589 gas per shooter / 539 gas per roll. Extrapolating those pins puts the newly observed
751-roll tail around 0.5–0.7M gas for a full resolver seat, while the absolute 8,703-roll legal
ceiling remains roughly a 5M-gas seat. Re-measure after the high-water fields and 32-bit cursor are
implemented; these are bounded estimates, not post-implementation gas snapshots.

### Shooter boosts versus no-boost baseline

| Cell | No-boost take | Final take | Change in take |
|---|---:|---:|---:|
| 5x random | 36.73% | 17.45% | -19.27 pp |
| 20x random | 52.66% | 15.42% | -37.24 pp |
| 5x picked | 21.97% | 17.37% | -4.60 pp |
| 20x picked | 33.29% | 19.55% | -13.74 pp |

The boost does more than add a small linear return. It changes whether a run reaches Goal, how much
surplus it can post after Goal, and which tail it enters. That nonlinear continuation is why the 20x
random uplift has such a large system effect.

Most take still comes from deletion of remaining bankroll on Bust. The 100m boosted estimates split
as follows:

| Cell | Pre-forfeit drag | Bust deletion | Effective take |
|---|---:|---:|---:|
| 5x random | -0.34% | 17.79% | 17.45% |
| 20x random | -13.77% | 29.19% | 15.42% |
| 5x picked | 1.63% | 15.73% | 17.37% |
| 20x picked | -6.30% | 25.85% | 19.55% |

Negative pre-forfeit drag means surviving runs return more raw bankroll than was entered; Bust
deletion more than offsets it in expectation.

### Goal–Jackpot

The jackpot is a property of the already-selected main winner; there is no extra draw. Rare is
tested first and overrides common. In the precise 40-seat standard mix:

| Metric | 5x | 20x |
|---|---:|---:|
| Random winner share | 53.0754% | 52.5588% |
| Picked winner share | 46.9246% | 47.4412% |
| Winner is Goal | 56.8354% | 25.0070% |
| Winner peak p90 | 15.06x | 33.62x |
| Winner peak p95 | 23.14x | 49.19x |
| Winner peak p99 | 70.18x | 134.47x |
| Winner peak p99.5 | 116.22x | 219.27x |
| Goal-winner peak p90 | 21.32x | 73.76x |
| Goal-winner peak p99 | 105.69x | 366.05x |

The clean 25x/120x and 50x/225x cutoffs sit near the intended winner-tail regions without needing a
depth table.

### THE BIGGEST

The simulation uses a **provisional 100x initial floor**, because “healthy minimum” was not assigned
a number in the product discussion. It treats the candidate as the scheduled field winner's
peak/start score, then accepts every strict improvement. This naturally becomes harder: the first
100x clears a fixed floor, while every later claim must exceed the largest prior outlier.

First-year record-hit counts in one standard-mixed path illustrate the player-count dependency:

| Field heads | 5x hits in first 2,555 fields | 20x hits in first 2,555 fields |
|---:|---:|---:|
| 1 | 0 | 1 |
| 5 | 1 | 5 |
| 20 | 2 | 7 |
| 40 | 3 | 3 |
| 80 | 6 | 5 |
| 160 | 5 | 9 |

These are record-path samples, not stable annual rates. Record arrivals are nonstationary and
maximum-driven; one path can jump the bar so high that no later field in the sample can touch it.
The raw TSV's “Dice-only pool” columns are a sensitivity only. Actual payouts share the pool with
the four existing record categories, whose hit processes and level funding were not modeled here.

### Custom isolation

Customs must be structurally excluded, not filtered by matching terms. The simulator contains no
custom seats in the scheduled matrices. Contract tests must prove that a custom using depth 5 and
Goal 5x/20x still has:

- legacy immediate-Goal settlement and speed ranking;
- zero shooter boost;
- zero scheduled action booking;
- zero ladder/progressive funding or award;
- zero BIGGEST candidate or shared-pool claim.

Custom bounties and donations remain self-funded and pay normally.

## Population and Scenario Analysis

### Field size changes field outcomes

The following is the broad standard-mixed matrix. “Any jackpot” is exact common plus rare, with
rare overriding common.

| Heads | Goal | All-Bust fields | Any jackpot / field | Any jackpot / entry | Winner peak p95 | p99.5 |
|---:|---:|---:|---:|---:|---:|---:|
| 1 | 5x | 88.19% | 0.2565% | 0.2565% | 6.49x | 17.71x |
| 1 | 20x | 97.04% | 0.2775% | 0.2775% | 12.12x | 37.27x |
| 5 | 5x | 71.66% | 1.1470% | 0.2294% | 11.06x | 40.63x |
| 5 | 20x | 90.99% | 1.1320% | 0.2264% | 25.52x | 80.34x |
| 20 | 5x | 53.01% | 2.9240% | 0.1462% | 18.09x | 82.61x |
| 20 | 20x | 81.20% | 3.0640% | 0.1532% | 38.49x | 152.10x |
| 40 | 5x | 42.77% | 4.5520% | 0.1138% | 23.08x | 126.10x |
| 40 | 20x | 75.06% | 4.6160% | 0.1154% | 47.54x | 199.56x |
| 160 | 5x | 27.78% | 9.5360% | 0.0596% | 39.11x | 176.55x |
| 160 | 20x | 59.17% | 10.8800% | 0.0680% | 84.72x | 491.26x |

More players make it much more likely that the field contains a Goal and a threshold-clearing
winner. They do **not** make a particular run stronger. Because only one field winner can receive a
jackpot, per-entry probability falls as the field grows even while per-field award frequency rises.

This answers the earlier “days” question: elapsed days are not intrinsic to the dice probability.
There are seven scheduled fields per day, but hit cadence depends on heads per field and composition.
For all-random 5,000-day paths, exact common/rare award counts ranged from about 5.33/0.51 per year
at one head to 235.35/34.89 at 160 heads.

### Bounty specialist

One `4 Don't Pass + 3 Place 5` bounty specialist against random seats won:

| Total heads | Neutral one-seat share | 5x bounty win | 20x bounty win |
|---:|---:|---:|---:|
| 5 | 20.00% | 25.99% | 26.50% |
| 20 | 5.00% | 10.23% | 10.54% |
| 40 | 2.50% | 5.74% | 6.39% |
| 80 | 1.25% | 3.82% | 4.35% |
| 160 | 0.625% | 2.11% | 2.34% |

At 40 heads this is about 2.3x–2.6x neutral bounty share. It is not free EV: the specialist's
single-seat broad estimates showed roughly 49% take at 5x and 60% at 20x, consistent with the
previous finding that bounty optimization sacrifices bankroll efficiency.

### Extreme observations and payout tail

In the precise mixed-40 run set:

- largest observed 5x peak: **49,061.76x** (147,185,273 FLIP raw on a 3,000 start);
- largest observed 5x ending credit: **23,502.70x** (70,508,100 FLIP);
- largest observed 20x peak: **105,400.85x** (316,202,558 FLIP raw);
- largest observed 20x ending credit: **46,998.23x** (140,994,700 FLIP).

None was a hard-bound stop. These are sample maxima, not expected caps or promises. Their main
analytical value is showing why block means move and why peak fields must not use 32-bit score
arithmetic even though the **stake multiplier** now deliberately uses a 32-bit ceiling.

The broader 36-million-entry population matrix contained a still larger genuine G20 tail: one
cell's maxima were a **468,385.45x peak**, **245,038.77x ending credit**, **63 shooters**, and **751
rolls**. Those maxima appear in the same 400,000-seat cell and are consistent with one dominating
entry, although the aggregate output does not encode an entry id proving they are all the same
run. After 63 completed shooters the **next** multiplier would be only 2,097,152x (the 63rd played
shooter used 1,048,576x), far below the new ceiling, so this is not another flat-ceiling artifact.
It drove that finite cell's realized take to -44.97%. Widening the
ceiling fixes pathological duration; it does **not** make the monetary distribution thin-tailed.

## Actor Analysis

### Entertainment gambler

Benefits from a simple two-Goal menu, a visible high-point race, protected Goal reserve, and rare
run-up stories. Main risk is misunderstanding peak versus payout. Showing only the peak would feel
like confiscation when the ending bankroll is lower.

### Bankroll EV maximizer

Can choose random versus a low-edge picked board and Goal. The modeled bankroll trade is not flat:
20x random is the most player-favorable expected cell, while 20x picked is the highest-take final
cell. The maximizer also accounts for bounty and jackpot dilution by field size.

### Bounty specialist

Can approximately double or better one seat's neutral race share with a dark-side tournament board,
but pays for it through much worse bankroll expectation. This is a real strategic niche rather than
an automatically superior board.

### Whale / high entrant

Buys monetary copies and extra bounty exposure, not better dice, more boost schedules, a multiplied
rank, or multiplied jackpot/BIGGEST eligibility. This prevents capital from directly buying record
probability beyond taking more separately paid seats where permitted.

### Affiliate / acquisition operator

Benefits from visible large-run stories and larger fields, but cannot honestly quote a field-size-
independent per-entry jackpot probability. Referral economics were not changed or modeled. Any
marketing should separate field award cadence from individual odds.

### Fresh wallet / sybil

Multiple seats increase chance of owning the winning run, but scheduled house-money standing still
rations the subsidy. Bounties remain entrant-funded. The record and progressive should inherit the
same frozen-standing policy where specified; customs offer no shared subsidy to farm.

### Griefer / MEV searcher

Potential targets are a freak resolver OOG, malformed score packing, delayed/out-of-order BIGGEST
finalization, and the current custom action-booking leak. Budget-1 manual resolution handles the
first; explicit packing proofs, deterministic record ordering, and a hard custom branch handle the
rest.

### Competitor / vampire product

Can create attractive self-funded custom tables, but customs cannot externalize rewards into the
protocol schedule. That boundary prevents a competing front end from using custom terms to drain
the 12% ladder or shared records.

### Late entrant

Can see terms, field size, and posted bounties but not future table entropy. A late entrant may pick
a thinner field for better per-entry jackpot odds or a larger one for a richer bounty contest; it
cannot choose after seeing shooter dice or boost eligibility.

## Equilibrium Analysis

Expected daily action for one full seven-window ticket is:

```text
opener expected bankroll                         1,500.0
five routine windows at 70%/20%/10% tiers       3,750.0
event expected bankroll                         10,372.5
total                                            15,622.5 FLIP
```

With edge `e`, the expected accrual after the variable allocation is
`15,622.5 × (e - 12%)` per daily seat. The 50,000 base is then covered at:

| Population mix | Equal-Goal edge | Residual per seat/day | Expected base break-even |
|---|---:|---:|---:|
| All random | 16.4378% | about 693 FLIP | about 72.1 seats |
| All picked bankroll board | 18.4573% | about 1,009 FLIP | about 49.6 seats |
| Equal random/picked | 17.4475% | about 851 FLIP | about 58.8 seats |

Goal mix also matters. An all-random 20x population has only a 3.42-point cushion over 12%, making
its break-even near 94 daily seats; picked 20x has a 7.55-point cushion and breaks even near 42.

Therefore the stable equilibrium is not determined by raw player count alone. It depends on daily
seat count, bankroll-tier schedule, random/picked split, Goal split, high entries, standing, and
realized payout tail. The 12% linear term is supported in expectation in every modeled cell; the
50,000 base is a separate deliberate subsidy that requires volume to amortize.

### Full scheduled allocation versus engine burn

The system comparison must include the complete scheduled allocation, not just its fixed base:

```text
scheduled allocation = 50,000 + 12% of scheduled bankroll action
```

For the equal-Goal, 50/50 random/bankroll-pick mix, one full daily seat covers all seven scheduled
fields and carries about 15,622.5 FLIP of bankroll action. At the calibrated 17.4475% take, that
seat burns **2,725.7 FLIP in expectation**, while its variable 12% allocation is **1,874.7 FLIP**.
It therefore contributes only **851.0 FLIP/day** toward amortizing the fixed 50,000 base. The full
allocation crossover is **58.75**, so the first whole-seat expectation above break-even is about
**59 full daily seats**, not 19.

| Full daily seats | Expected engine burn/day | `50,000 + 12%` allocation/day | Allocation minus burn |
|---:|---:|---:|---:|
| 1 | 2,726 | 51,875 | +49,149 emission |
| 5 | 13,629 | 59,374 | +45,745 emission |
| 10 | 27,257 | 68,747 | +41,490 emission |
| 20 | 54,515 | 87,494 | +32,979 emission |
| 40 | 109,030 | 124,988 | +15,958 emission |
| 58 | 158,093 | 158,733 | +639 emission |
| 59 | 160,819 | 160,607 | -212 net burn |
| 80 | 218,059 | 199,976 | -18,083 net burn |
| 160 | 436,119 | 349,952 | -86,167 net burn |

Mix sensitivity is material because only the take above 12% pays down the fixed base. With equal
Goal participation, all-random seats cross near 72.1 seats and all-picked bankroll-board seats
cross near 49.6. An all-random 20x population crosses near 94 seats. These are action-equivalent
daily seats, not unique wallets: repeat entries and high-stake scheduled entries should be converted
to their scheduled-action equivalents. Customs, boons, quests, and self-funded bounty transfers
remain outside both action and allocation.

## Risk Matrix

| Risk | Severity | Likelihood | Evidence | Mitigation |
|---|---|---|---|---|
| Custom action leaks into scheduled denominator | High | Certain in current code | `resolveSlot` books custom to current `_dayStaked` | Skip `_bookDay` for every custom slot; pin storage delta at zero |
| Peak paid instead of ending bankroll | High | Implementation risk | Peaks and endings differ by orders of magnitude in tails | Separate fields/types/events and explicit payout tests |
| Score packing truncates/wraps extreme peak | Critical | Medium without redesign | Observed 468,385x; old rank/roll layout is obsolete | Exact-width proof, saturation proof, or safe extra scoreboard storage |
| BIGGEST resolver-order MEV | High | Medium | Permissionless closed fields can finalize out of order | Aggregate/order candidates deterministically before pool claim |
| 100x BIGGEST floor is not product-confirmed | Medium | Certain assumption | Discussion named only “healthy minimum” | One named constant; confirm before deployment; rerun record path if changed |
| Fixed-base low-volume issuance | High | Certain below break-even | 50k base; post-12% break-even about 50–94 seats by mix | Accept explicitly, reduce base, or fund from a capped reserve |
| 20x monetary tail overwhelms short horizons | High | High on finite horizons | New 20m blocks bottomed at 12.21%; one 400k population cell landed at -44.97% | Size reserve on drawdown, not only mean; monitor block results |
| Freak seat OOG | Medium | Very low | 0/76m cap stops; observed maximum 138 work units; hard ceiling ~1,463 | Keeper margin, budget-1 manual retry, no hot-path worst-seat reservation |
| Jackpot odds marketed as field-size invariant | Medium | High if UI is vague | Per-entry odds fall from ~0.26% at N=1 to ~0.06% at N=160 | Show field size and distinguish field cadence from entry odds |
| Bounty board mistaken for bankroll optimum | Medium | Medium | 2.3x+ race share with ~50%+ single-seat take | Show separate bankroll and bounty metrics; avoid “best board” label |
| Shared BIGGEST pool model incomplete | Medium | Certain analytically | Other four record hits and level funding omitted | Simulate all record kinds before changing pool funding; add no Dice drip now |
| Custom mechanics accidentally inherit scheduled continuation | High | Medium | Pure engine is shared today | Explicit scheduled-mode parameter plus legacy custom differential oracle |

## Recommendations

1. Implement the locked scheduled constants and the hard custom branch exactly as the Contract
   Claude handoff specifies.
2. Treat **100x BIGGEST minimum** as the one explicit assumption requiring product confirmation
   before deployment. No other proposed numeric calibration needs reopening from these results.
3. Keep the 12% variable allocation. Maintain an explicit reserve policy for the 50,000 base and
   tail drawdowns; do not describe 12% as a realized daily ceiling.
4. Make BIGGEST candidate processing deterministic across permissionless field resolution before
   exposing the fifth shared-pool category.
5. Widen/redesign scoreboard metadata. Remove the old roll-based progressive field rather than
   relabeling 13 bits that cannot hold the new hard roll ceiling or extreme score.
6. Keep the normal resolver outcome-budgeted. Add an estimate-gas margin and a documented manual
   budget-1 path; do not burden every normal batch with a theoretical 8,703-roll reservation.
7. Monitor, by Goal and ticket type: bankroll action, ending credit, effective take in large rolling
   blocks, Goal rate, peak and ending quantiles, common/rare rate, field heads, all-Bust rate, cap
   stops, resolver work units, progressive balance, record mark, and record-claim intervals.
8. In the UI, show `Goal`, jackpot cutoffs, current peak, ending payout, and field size as distinct
   concepts. Never present peak as cash secured.
9. Re-run the exact simulator and differential oracle after any change to boost percentages,
   escalation cadence, Goal mix, BIGGEST floor, or record claim rule; these effects are nonlinear.
