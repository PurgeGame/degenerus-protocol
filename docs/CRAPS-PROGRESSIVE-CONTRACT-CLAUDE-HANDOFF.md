# Craps progressive jackpot and 50,000-FLIP base: Contract Claude handoff

> Status: product/economic handoff approved in discussion on 2026-08-27.
>
> This document supplements
> [`CRAPS-SHOOTER-BOOST-CONTRACT-CLAUDE-PROPOSAL.md`](CRAPS-SHOOTER-BOOST-CONTRACT-CLAUDE-PROPOSAL.md).
> It supersedes that proposal where it says the additive daily base is 25,000 FLIP, that all of
> the main scheduled budget goes through the existing seven-window ladder, or that protocol money
> denied by activity standing is burned/left unminted. The shooter schedule, 12%-of-action rule,
> neutral Goal weighting, 3:4 Don't Pass, board limits, battle ranking, Bust deletion, and every
> other settled rule remain unchanged.

<agent_identity>

You are Contract Claude, the senior Solidity engineer responsible for implementing and proving
this Craps progressive-jackpot change in the Degenerus Protocol.

Work from the live repository and dirty working tree. Preserve deterministic settlement,
settlement-order independence, preview/payment parity for individual runs, protocol accounting,
storage safety, bytecode and gas limits, and all unrelated edits. Contracts and tests are the
authority for existing behavior; this handoff is the authority for the proposed delta.

Do not reset, restore, stage, commit, or broadly rewrite existing work unless separately asked.

</agent_identity>

<domain_knowledge>

## Canonical local sources

- [`contracts/Craps.sol`](../contracts/Craps.sol): pure Craps run engine.
- [`contracts/CrapsBattle.sol`](../contracts/CrapsBattle.sol): schedule, entry, shared fields,
  ranking, budgets, battle finalization, and Coinflip-credit payouts.
- [`test/craps/CrapsOracle.sol`](../test/craps/CrapsOracle.sol): independent settlement oracle.
- [`test/craps/CrapsSystemEcon.t.sol`](../test/craps/CrapsSystemEcon.t.sol): system economic tests.
- [`scripts/craps-system-sim.cpp`](../scripts/craps-system-sim.cpp): reference economic simulator.
- [`docs/CRAPS-SYSTEM-SIMULATION.md`](CRAPS-SYSTEM-SIMULATION.md): prior calibration evidence.
- [`docs/CRAPS-BATTLE-SYSTEM-OVERVIEW.md`](CRAPS-BATTLE-SYSTEM-OVERVIEW.md): current mechanics.

Inspect the live diff before editing. Some of these files are already modified or untracked.

## Existing rules that do not change

- Scheduled bankroll depths are 2x, 5x, and 10x.
- Scheduled Goal multiples are 5x, 10x, and 50x; do not restore 20x.
- A picked ticket names seven chips with at most four **selected** chips on one leg. The three
  forced scatter chips may subsequently land on a leg that already has four. Blank names zero and
  scatters all ten.
- A ticket cannot select both Pass and Don't Pass.
- Don't Pass pays stake plus 3:4 profit.
- Blank and picked tickets share one main battle field.
- Goal beats Bust; faster Goal beats slower Goal; later Bust beats earlier Bust; ending raw
  bankroll, standing, and deterministic tie order retain their current positions in ranking.
- A Bust may still win a field of Busts, but its remaining bankroll is deleted and it cannot win
  the proposed progressive.
- Bounties are player-to-player transfers. They are neither action nor protocol emission.
- `_dayStaked` is bankroll handle only. Never add bounties, shooter boosts, ordinary scheduled
  bonuses, progressive contributions, progressive payouts, or donations to it.
- Scheduled shooter-profit boosts remain:

| Stored ticket | Eligible shooters | Goal 5x | Goal 10x | Goal 50x |
|---|---:|---:|---:|---:|
| Blank/random | 15% | +25% profit | +30% profit | +40% profit |
| Picked | 5% | +6% profit | +20% profit | +35% profit |

- No shooter-boost amount jitter.
- Custom battles receive neither scheduled shooter boosts nor protocol scheduled-bonus money.
- The separate high-roller budget is not split into this progressive. Its ordinary payout path
  remains intact, except that any protocol-funded amount denied solely by activity standing is
  rolled into the progressive under the approved rule below.

## Approved economic change

The raw main scheduled budget becomes:

```text
rawMainBudget(day) = 50,000 FLIP + 12% of trailing seven-day action allocated to main
```

The 50,000 is additive, never a floor or cap. Preserve the existing regular/high separation and
2:3 split of the high-derived component:

```text
regular action -> 12.0% main
high action    ->  4.8% main + 7.2% separate high lane
```

Split only the resulting **main** budget:

```text
ladderBudget            = floor(rawMainBudget / 2)
progressiveContribution = rawMainBudget - ladderBudget
```

The odd-wei remainder therefore goes to the progressive and the two amounts conserve the raw main
budget exactly. The ladder half retains the current event/routine weighting, multiplier ladder,
rounding, standing treatment, and main winner. The separate high-lane budget remains whole and
unchanged.

There is one global Craps progressive balance shared by all nine scheduled depth/Goal formats.
Funding occurs exactly once when a protocol day opens. This is a virtual FLIP emission liability,
not a transfer of already-minted liquid FLIP into the contract. A later payout must not be counted
as a second emission.

## Progressive qualification and payout

A progressive award has no independent probability roll. It is determined entirely by the
already-finalized main battle result:

1. The battle must be a protocol-scheduled main battle, not a custom battle.
2. The recipient must be the final **main battle winner** already selected by the existing
   comparator. Never search for a runner-up.
3. The winner's stop must be `Goal`. A Bust never qualifies, regardless of rolls, hands, or battle
   rank.
4. Compare the winner's cumulative `totalRolls` against the threshold for that window's bankroll
   depth and Goal multiple.
5. Test rare first. Rare overrides common; never pay both.

Thresholds are inclusive cumulative dice-roll counts:

| Bankroll depth | Goal 5x common / rare | Goal 10x common / rare | Goal 50x common / rare |
|---:|---:|---:|---:|
| 2x | 150 / 185 | 205 / 245 | 340 / 395 |
| 5x | 215 / 260 | 275 / 320 | 405 / 455 |
| 10x | 265 / 315 | 325 / 375 | 455 / 500 |

The battle's dice are shared. Shooter `n` begins and ends at the same roll for every entrant that
survives through it, although some tickets stop before reaching it. Consequently this criterion
adds no per-player roll or jackpot RNG: it measures the shared cumulative roll prefix at which the
winning ticket stopped. The deliberate behavior change is that a very long final shooter can push
a winning ticket over a cutoff even when it reached Goal in relatively few shooters. Conversely,
many short shooters need not qualify merely because their count is high.

Do **not** replace hands with rolls in battle ranking. The main comparator remains Goal before
Bust, fewer hands for Goals, and more hands for Busts, followed by its existing tiebreakers. Rolls
are progressive qualification metadata only. A Goal is tested between shooters, so the qualifying
count includes the winner's complete final shooter. The word “unbounded” is conceptual: the live
engine's existing 512-roll shooter cap and 4,096-roll slip budget still apply, giving a hard maximum
below 4,608 cumulative rolls.

`Craps.SlipResult` already returns `totalRolls`; the wrapper currently discards it. Carry it through
`Settlement`, save the leading ticket's roll count whenever the scoreboard leader changes, and
expose it as `winningRolls` in the finalized result. Do not rerun the winning settlement at field
finalization and do not add a per-entrant storage write.

The current scoreboard reserves 64 bits for a winner seat even though `_enterBattle` limits the
seat to its low 32-bit entrant counter. A compact implementation may retain the seat in the low 32
bits of that region and use 13 of the reclaimed upper bits for `winningRolls`: the engine proves a
maximum of 4,607, while 13 bits hold 8,191. If this packing is used, mask every winner-seat read to
32 bits, clear and replace the seat and roll slices together when leadership changes, and prove
that existing unresolved words decode identically because their reclaimed bits are zero. Keep the
public `winnerId` type if changing it would create needless ABI churn. If live storage constraints
contradict this plan, report them before choosing another layout; do not silently add one storage
slot per entrant.

Candidate award from the live balance at finalization:

```text
if Goal && winningRolls >= rareThreshold:
    candidate = floor(progressiveBalance / 2)   // 50%
else if Goal && winningRolls >= commonThreshold:
    candidate = floor(progressiveBalance / 10)  // 10%
else:
    candidate = 0

paid = standingShare(candidate, winnerStanding)
progressiveBalance -= paid
```

At full standing, `paid == candidate`. Below full standing, candidate minus paid remains in the
pool under the approved rollover rule below. Multiple qualifying windows consume only their actual
credits sequentially, and each later award uses the then-current balance. Do not snapshot or
reserve a day's pool per window. A high-multiple seat that wins the main battle receives one
progressive award; the high multiple does not scale it. Winning only the separate high lane does
not qualify. The earlier idea of an extra Bernoulli draw or entry-size scaling is not part of the
tested proposal.

Pay through the same Coinflip-credit rail used by the existing battle award. Deduct the actual
standing-adjusted credit from the pool before the external credit call. Emit a dedicated event
carrying enough information to reconcile the old balance, award tier, candidate, credit, retained
amount, and new balance.

## Approved activity-standing rollover

Every piece of **protocol-funded Craps value denied solely because the recipient has insufficient
activity standing goes into the global progressive**. It is no longer left unminted or silently
discarded.

Audit every place the existing standing curve (`_boostShare` or its equivalent) reduces house
money, including:

- the main scheduled ladder award;
- a contested high-lane scheduled boost;
- the scheduled boost capital offered to a sole high-lane rider; and
- a common or rare progressive award.

For the main and high scheduled paths, compute the full-standing protocol amount and the amount
the existing score curve actually allows at the same denomination and rounding stage:

```text
standingRollover = fullStandingProtocolAmount - actualProtocolAmount
progressiveBalance += standingRollover
```

Preserve the recipient's current score-adjusted payment exactly. Where the high boost is capital
placed at risk beside a sole rider, compare the full-standing and score-adjusted **boost capital**
before the ride; do not manufacture a hypothetical winning run return. Move the standing-denied
capital into the progressive and let only the admitted capital ride.

For a common or rare progressive result, the candidate value is already in the pool. Apply the
same standing curve directly to the candidate amount, deduct only what is actually credited, and
leave the denied remainder where it is:

```text
candidate = floor(pool / 10) or floor(pool / 2)
paid      = standingShare(candidate, winnerStanding)
retained  = candidate - paid
pool     -= paid
```

Do not add `retained` back a second time. At full standing, `paid == candidate` and this is exactly
the simulated 10%/50% rule. At score zero, the candidate remains entirely in the pool.

This rollover is limited to value removed by the activity-score rule. Do **not** sweep
player-funded bounties, donations, principal, run losses, Bust deletion, ladder under-realization,
ordinary rounding dust, or an unsuccessful high-lane ride into the progressive.

For a direct main or contested-lane award, `actual credit + standing rollover` must equal the
full-standing protocol award at the specified rounding stage. A progressive candidate retained in
place is not new funding and must not be counted as another emission.

The economic simulations put every modeled player at standing 12, so their measured balances and
emission figures contain no additional standing rollovers. Lower-standing live populations will
grow the progressive faster and leave more of each qualifying candidate in it. Do not special-case
the sDGNRS/Vault/house seat; the existing entrant standing must drive the same rule.

## Economic evidence and interpretation

The progressive cohort model ran 500 independent 730-day worlds: 40 persistent players, one
seven-window daily ticket each, or 102.2 million battle runs. The population was 20 blank/random
and five each of fixed Place-4/10, mixed, Pass-heavy, and 3:4 Don't-Pass-heavy behavior.

With the former 25,000 base and half of main funding the progressive:

| Quantity | Mean per day |
|---|---:|
| Bankroll action | 624,604 FLIP |
| Post-shooter engine retention | 159,688 FLIP (25.57% of action) |
| Immediate ladder paid | 49,489 FLIP |
| Progressive contribution | 49,770 FLIP |
| Total emission, counting stored pool value | 99,258 FLIP (15.89%) |
| Net | 60,430 FLIP burn (9.68%) |

The high 25.57% field edge is not an error in the subsidy arithmetic. The 40-ticket breakeven
estimate assumed a 16% efficient field; the heterogeneous field deliberately included suboptimal
behavior:

| Behavior | Measured bankroll loss |
|---|---:|
| Blank/random | 17.85% |
| Fixed Place 4/10 | 18.37% |
| Mixed | 28.25% |
| Pass-heavy | 26.69% |
| 3:4 Don't-Pass-heavy | 59.81% |
| Weighted field | 25.57% |

Raising the additive base from 25,000 to 50,000 adds exactly 25,000 FLIP/day to allocated economic
emission in expectation when stored progressive value is counted. A second same-seed 500-by-730-day
run with the 50,000 base measured:

| Quantity | Mean per day |
|---|---:|
| Bankroll action | 624,604 FLIP |
| Post-shooter engine retention | 159,688 FLIP (25.57% of action) |
| Immediate ladder paid | 61,970 FLIP |
| Progressive contribution | 62,270 FLIP |
| Total emission, counting stored pool value | 124,240 FLIP (19.89%) |
| Net | **35,448 FLIP burn (5.68%)** |

The measured burn reduction was 24,981 FLIP/day rather than exactly 25,000 because the displayed
figure uses the ladder payout actually realized after integer rounding and finite multiplier draws.
That 19-FLIP/day difference is noise, not a different funding rule.

The participation equilibrium is edge-dependent, not a universal player count. At about 15,615
bankroll action per complete daily ticket and the new 50,000 base:

| Weighted post-shooter edge | Approximate zero-EV daily tickets |
|---:|---:|
| 16.00% efficient-field policy assumption | 80 |
| 17.85% all blank/random | 55 |
| 18.37% fixed Place 4/10 | 50 |
| 25.57% modeled heterogeneous field | 24 |

For the modeled heterogeneous field, the continuous breakeven is 23.6 daily tickets: 23 emits
about 1,300 FLIP/day and 24 burns about 800 FLIP/day. This low-participation emission is intended.
Do not introduce a hard issuance cap solely to eliminate it.

The roll table was calibrated with 3,000,000 independent blank/random runs in each of the nine
formats, then each cutoff was rounded to its nearest multiple of five; no cutoff moved more than
two rolls. Conditional on reaching Goal, it preserves the former hand table's intended bands:
common qualification measured 6.97%-8.66% and rare qualification measured 0.335%-0.892%. The
unrounded starting points were probability-matched integer quantiles, not “average rolls per
shooter” multiplication. That matters because long shooters are correlated with run outcomes.

Roll qualification does change which qualifying tickets also win their field. In the same-seed
40-player mixed cohort, the progressive therefore accumulated to a day-730 mean of **19.204
million FLIP**; its median was 19.177 million and its 10th-90th percentile range was
13.979-24.354 million. The field produced about **9.63 common-only awards and 0.151 rare awards per
year**, versus 68.4 and 5.8 under the superseded hand criterion. Mean progressive credits over the
first 730 days were 35,963 FLIP/day. This payout is a release of stored liability, so the 124,240
FLIP/day emission and 35,448 FLIP/day net burn above are unchanged. Actual awards always use the
live pre-payout balance and winner standing. A 100-world, ten-year extension ended at an inferred
mean of about **21.32 million FLIP**, consistent with the pool approaching a roughly 21-million
long-run level under this cohort rather than growing without bound.

The cohort wrapper used for these two runs was an analysis harness over the tracked C++ model, not
a committed production mode. Integrate and test its equivalent in `scripts/craps-system-sim.cpp`
rather than treating these output numbers as a substitute for a reproducible model.

</domain_knowledge>

<task_definition>

## Objective

Implement the 50,000-FLIP additive base and one shared scheduled-Craps progressive, while retaining
all existing Craps settlement, battle, high-lane, and shooter-boost rules. Update contracts, views,
events, tests, the differential/reference model, and economic documentation so the accounting is
reproducible and contract behavior is independently verifiable.

## Required contract behavior

1. Change `_BASE_MAIN_BUDGET` from `25_000 ether` to `50_000 ether` and update every view, comment,
   test, and report that presents it as active behavior.
2. Factor the main-budget split into one canonical helper or equally unambiguous implementation.
   Use it both when a day opens and when an unopened day's boost is quoted. Never let a pre-open
   quote advertise twice the ladder amount ultimately stored.
3. Store only the ladder half in the existing main boost-budget path. Add the other half to one
   global progressive balance exactly once per opened day.
4. Keep the high-lane budget and payout path unchanged except for routing its activity-standing
   forfeiture into the global progressive.
5. Determine qualification from the finalized main scoreboard's stop and the winning ticket's
   cumulative roll count. Derive depth as `bankroll / playedRound` and Goal multiple as
   `goal / bankroll`, after proving those ratios are exact for every scheduled preset. Do not apply
   the table to custom terms. Preserve `winningHands` and add `winningRolls` to the production
   `Battle` view and finalized-battle event so ranking and qualification can both be reconstructed.
6. Pay rare before common, using integer division on the live pool. Deduct state before calling
   Coinflip. Never pay twice when resolution is split across batches or retried.
7. Add explicit pool-funding and pool-award events and a production view of the current balance.
   Add a pure/view threshold surface only if it materially improves client parity without harming
   code size.
8. Preserve the event/routine ladder split, ladder distribution, rounding, standing payment curve,
   Goal weighting, action lag, action partition, and all bounty accounting. Route the difference
   between full-standing and score-adjusted protocol value into the progressive.
9. Audit every activity-rationed main and high path. Add each standing forfeiture to the pool
   before any external credit call. For a rationed progressive award, subtract only the actual
   credit because the forfeiture is already inside the pool.
10. Update the C++ model and full-game simulator handoff so emission is counted when value enters
   the progressive. A later payout is a liability release, not new issuance.
11. Measure deployed bytecode and worst-case settlement gas. Prefer a compact threshold lookup and
    avoid adding work to every non-final entrant.

Suggested events; adapt names/types to local conventions without dropping their information:

```solidity
event CrapsProgressiveFunded(
    uint24 indexed day,
    uint256 contribution,
    uint256 balance
);

event CrapsProgressivePaid(
    uint256 indexed betId,
    bytes32 indexed battleKey,
    address indexed player,
    bool rare,
    uint16 rolls,
    uint256 candidate,
    uint256 paid,
    uint256 retained,
    uint256 balance
);

event CrapsProgressiveRolled(
    uint256 indexed betId,
    bytes32 indexed battleKey,
    uint8 source,
    uint256 amount,
    uint256 balance
);
```

Use documented source values to distinguish at least main-ladder and high-lane standing rollovers.
The progressive payout event itself records a candidate retained in place, so do not emit a fake
second funding event for that unchanged balance.

## Required verification

At minimum, prove:

1. Zero action produces raw main 50,000, ladder 25,000, progressive contribution 25,000.
2. Raw main always equals ladder plus progressive contribution, including every odd-wei residue.
3. Regular and high action retain the exact 12% total rate and are never double-counted.
4. The separate high budget is identical before and after this change for identical history.
5. A day funds the progressive once despite repeated arm/open/advance calls.
6. Pre-open quotes, opened budget storage, events, and views agree on the ladder half.
7. All 18 roll thresholds have explicit `threshold - 1` and `threshold` tests (36 boundary cases).
8. Rare overrides common and creates only the 50% candidate, never 50% plus 10%.
9. A Goal below common pays zero; a Bust above rare pays zero.
10. Custom battles neither contribute to nor withdraw from the progressive.
11. Sequential awards use the reduced live balance and conserve `funding - payouts = pool`.
12. Integer division cannot overdraw; a tiny pool safely produces a zero award without a needless
    external call.
13. Main winner identity is unchanged by the progressive. High multiple cannot scale it, and a
    separate high-lane victory alone cannot claim it.
14. Split-batch settlement, repeated resolution, and settlement order cannot double-pay or change
    the progressive recipient.
15. Pool state is reduced before the external credit and remains safe under the Coinflip mock's
    most adversarial callback behavior permitted by the architecture.
16. At standing scores 0, 1, 6, 11, and 12, the main winner receives exactly the existing
    score-adjusted boost and the full-standing difference is added to the pool exactly once.
17. Contested and sole-rider high paths route only their standing-denied protocol allocation; they
    do not route bounty principal, ride losses, or unrelated rounding differences.
18. A score-rationed progressive award subtracts only the actual credit. Candidate minus credit
    remains in the pool without a second addition.
19. Full-standing recipients create zero standing rollover on every path.
20. Immediate boost, progressive funding, standing rollovers, progressive payouts, bounties, and
    run credits never feed `_dayStaked`.
21. Events and production views allow an indexer to reconcile day funding, standing rollover, and
    progressive payouts from genesis.
22. Existing preview/payment parity for the individual run remains exact. The internal engine
    result already computes the roll count, while the current external `previewSettlement` ABI
    returns only `won` and `paid`; the progressive is a field-finalization award and is therefore
    not included in that payment preview.
23. Focused differential, fuzz/invariant, gas, code-size, and full-suite tests pass.
24. The tracked simulator reproduces the new formula, all nine roll thresholds, and the fresh
    full-standing pool trajectory within documented Monte Carlo tolerance.
25. Two tickets that reach the same shooter boundary on one shared field report the same cumulative
    rolls even when their boards differ; tickets that stop earlier report the corresponding prefix.
26. A long final shooter can cross a common or rare roll boundary without changing the winner's
    hand-based rank.
27. When a new leader displaces the old one, the stored roll count changes with the winner; when a
    challenger loses, neither winner nor roll count changes.
28. Every stored roll count from 0 through the engine's 4,607 maximum round-trips through the
    scoreboard packing, and an old-format word with zero reclaimed bits decodes unchanged.
29. Finalized event data, the `Battle` view, and the progressive event agree on winning hands and
    rolls. Settlement batching and entrant order do not change either value.

Run at least:

```bash
forge test --match-path test/craps/CrapsBattle.t.sol
forge test --match-path test/craps/CrapsHighRoller.t.sol
forge test --match-path test/craps/CrapsSystemEcon.t.sol
forge test --match-path test/craps/CrapsGas.t.sol
forge test --match-path test/craps/EngineGas.t.sol
forge test --match-path test/fuzz/CrapsProtocolWiring.t.sol
forge test
git diff --check
```

If the live suite has moved, run the current equivalent and report the substitution.

## Delivery

Return:

1. concise implementation summary;
2. exact raw-budget split and integer-floor order;
3. exact threshold lookup and payout ordering;
4. storage-layout and external-call safety analysis;
5. files changed;
6. focused and full test output;
7. bytecode and worst-case gas deltas;
8. updated economic simulation and equilibrium table;
9. any live-code contradiction and the exact standing-rollover behavior implemented.

Do not stage or commit changes unless separately requested.

</task_definition>

<interaction_patterns>

1. Inspect `git status`, the Craps-related diff, storage layout, views, events, and tests first.
2. State any code/spec contradiction that changes value flow before editing semantics.
3. Implement budget conservation and once-per-day funding before payout logic.
4. Carry the engine's existing `totalRolls` through settlement and store it only when the
   scoreboard leader changes. Implement qualification only in the one field-finalization branch;
   do not add per-seat storage, rerun the winner, or add a second winner-selection pass.
5. Apply checks-effects-interactions to the pool, then use the existing Coinflip credit rail.
6. Run focused tests before the full suite and simulation.
7. Report measured evidence and distinguish completed runs from projections.

</interaction_patterns>

<guardrails>

- Do not change the 12% action rate. The new base is 50,000, additive.
- Do not split the high-only budget into the progressive; only its activity-standing forfeiture
  rolls over.
- Do not change shooter-profit boosts, add jitter, or reintroduce Goal 20x.
- Do not change 3:4 Don't Pass, board selection limits, scatter, survival, Bust deletion, ranking,
  standing score, bounties, passes, Vault behavior, or custom-battle economics.
- Do not add a separate jackpot RNG roll. The shared cumulative roll prefix is the qualification
  draw.
- Do not use rolls in the battle comparator. Goal/Bust ranking remains hand-based.
- Do not pay a qualifying Bust or select a nonwinning Goal as an alternate recipient.
- Do not scale the progressive by high entry multiple or pay the separate high-lane winner.
- Do not pay both common and rare.
- Do not count a payout as fresh emission after its pool contribution was already counted.
- Do not let payout timing or settlement batching change the winner or percentage.
- Do not make progressive funding or standing rollover recursive through `_dayStaked`.
- Do not discard activity-standing forfeitures. Route them to the progressive exactly once.
- Do not call player-funded money, run losses, Bust deletion, ladder variance, or rounding dust a
  standing forfeiture.
- Do not sacrifice reentrancy safety, storage compatibility, bytecode limits, or gas bounds.
- Do not discard, overwrite, stage, or commit unrelated dirty-tree work.

</guardrails>

<examples>

## Correct daily split

At modeled 40-player action, suppose the raw main budget is 125,000 FLIP:

```text
ladder budget            = 62,500
progressive contribution = 62,500
high budget              = whatever the unchanged high-action formula produced
```

Do not halve the high budget and do not allocate 125,000 to the ladder as well as 62,500 to the
pool.

## Correct sequential awards

The pool is 1,000,000 when a full-standing rare winner finalizes:

```text
rare award = floor(1,000,000 / 2) = 500,000
pool       = 500,000
```

If the next finalized window has a full-standing common winner:

```text
common award = floor(500,000 / 10) = 50,000
pool         = 450,000
```

## Correct qualification boundary

For depth 5, Goal 10:

```text
274 rolls -> no progressive
275 rolls -> common 10%
319 rolls -> common 10%
320 rolls -> rare 50% candidate only
```

The 320-roll result is not a 10% common award followed by a 50% rare award.

## Correct main-ladder standing rollover

Suppose a main window's full-standing boost is 40 granules, each worth 100 FLIP. A score-6 winner
receives one part in `12 - 6 = 6` under the existing curve:

```text
full-standing boost = 40 granules = 4,000 FLIP
winner boost        = floor(40 / 6) = 6 granules = 600 FLIP
standing rollover   = 4,000 - 600 = 3,400 FLIP
```

Credit the winner's existing 600-FLIP boost and add 3,400 FLIP to the progressive before the
external credit. Do not alter the player-funded bounty portion of the pot.

## Correct progressive standing retention

The pool is 900,000 FLIP, a common result makes the candidate 90,000, and the winner has score 6:

```text
candidate = 90,000
paid      = floor(90,000 / 6) = 15,000
retained  = 75,000
new pool  = 900,000 - 15,000 = 885,000
```

Do not subtract 90,000 and then add 75,000 back. Subtracting only the actual 15,000 credit is the
same accounting with fewer state transitions and no transient underfunding.

## Failure mode to avoid

Wrong implementation:

```text
main ladder receives rawMainBudget
progressive also receives rawMainBudget / 2
```

That creates 150% of the intended main emission. The invariant is always:

```text
rawMainBudget == ladderBudget + progressiveContribution
```

</examples>
