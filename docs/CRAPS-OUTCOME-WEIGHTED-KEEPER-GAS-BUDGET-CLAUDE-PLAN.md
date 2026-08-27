# Outcome-weighted Craps keeper gas budget: Contract Claude plan

> Status: implementation plan approved in discussion on 2026-08-27.
>
> Goal: replace the fixed Craps seat allowance with one granular work budget that naturally
> processes many cheap busts and fewer expensive/paid runs. Calibrate the **complete**
> `game.mineFlip()` Craps crank to a worst-evaluated 95th percentile at or below 9.5M gas while
> retaining a deterministic hard safety margin below 16.7M gas on that production keeper path.

<agent_identity>

You are Contract Claude, the senior Solidity engineer responsible for implementing and
adversarially verifying this keeper-gas change in the Degenerus Protocol. Treat gas-bounded
liveness, exact economic equivalence, storage compatibility, and EIP-170 headroom as simultaneous
requirements.

Work from the live repository and current dirty working tree. The contracts and tests are the
authority for existing behavior. Do not reset, restore, discard, or broadly rewrite other work.
If this plan conflicts with live code, identify the conflict and resolve it explicitly rather than
silently changing economics.

</agent_identity>

<domain_knowledge>

## Relevant code

- [`contracts/modules/GameAfkingModule.sol`](../contracts/modules/GameAfkingModule.sol) owns the
  rewarded `mineFlip()` router, the box walk-unit budget, `_crapsSeatBudget`, and `_crapsKeep`.
- [`contracts/CrapsBattle.sol`](../contracts/CrapsBattle.sol) owns `resolveSlot`, `_settleBatch`,
  `_resolve`, battle scoring/finalization, progressive payout, action booking, and the cursor.
- [`contracts/Craps.sol`](../contracts/Craps.sol) is the bounded pure run engine.
- [`contracts/Coinflip.sol`](../contracts/Coinflip.sol) receives the deferred bankroll returns
  through `creditFlipBatch` and the keeper bounty through `creditFlip`.
- [`test/fuzz/CrapsProtocolWiring.t.sol`](../test/fuzz/CrapsProtocolWiring.t.sol) exercises the whole
  `game.mineFlip()` Craps arm/walk route.
- [`test/craps/CrapsGas.t.sol`](../test/craps/CrapsGas.t.sol) pins standalone engine, legal-slip,
  and marginal settlement gas.
- [`docs/CRAPS-BATTLE-SYSTEM-OVERVIEW.md`](CRAPS-BATTLE-SYSTEM-OVERVIEW.md) explains the current
  system but contains fixed-seat gas claims that must be updated after this work.

## Current mechanism

`GameAfkingModule` currently uses:

```solidity
CRAPS_SEAT_WEIGHT = 27;
CRAPS_KEEP_MAX_SEATS = 80;
```

It converts box `spentUnits` to a flat number of seats. `CrapsBattle.resolveSlot(slot, count)` then
allocates arrays for that many seats, resolves every one, batches nonzero bankroll returns into one
`creditFlipBatch`, books action, and moves the cursor to the requested batch end.

This is coarse for two reasons:

1. A seat's cost varies materially with its actual number of shooters/rolls and whether it creates
   a deferred Coinflip credit.
2. Every player at a table shares the shooter dice. A favorable table can make many players run
   long or get paid together, so independent per-seat averages understate field-level tails.

There is also an accounting mismatch in the existing shared budget. `OPEN_WEIGHT_BUDGET` is 1,920
walk units, while `1,920 / 27` is about 71 seats; nevertheless the untouched flat cap is 80. Worse,
when a skip-only box walk consumes all 1,920 units, `80 - floor(1,920 / 27)` still permits nine
Craps seats. The replacement must saturate the remaining work at zero instead of stacking that
tail.

## What a bust costs

A bust is not free. Its run still derives dice, executes every roll it reached, folds its score,
and emits `CrapsBetSettled`. What it avoids is the deferred bankroll-return entry in
`creditFlipBatch`.

Therefore do **not** assign every bust a token weight such as `1`, and do not classify all busts as
equally cheap. The intended rule is:

```text
seat work = gas actually consumed resolving/scoring the seat
          + conservative deferred-credit reserve if paid != 0
```

A short bust then costs little automatically. A 200-roll bust still pays for 200 rolls. A paid run
adds the storage/event cost that will occur after the loop.

## Existing measurements

Measurements below are from the current dirty tree and are evidence, not constants to copy.

### Exact correlated resolver replay

The fixture used unique players, one shared table word per field, the live scatter/survival/shooter
boost logic, a picked `4 Pass + 3 Place 8` board with the remaining three chips scattered, and full
field finalization. There were 160 independent table words per cell.

| Scheduled format | Seats | Resolver p95 |
|---|---:|---:|
| depth 10, Goal 5x | 80 | 13,413,589 |
| depth 10, Goal 50x | 80 | 13,836,472 |
| depth 10, Goal 50x | 52 | 8,979,963 |
| depth 10, Goal 50x | 54 | 9,251,249 |
| depth 10, Goal 50x | 56 | 9,569,613 |

This proved that 80 is not a p95-safe default and that “the format paying the most players” is not
necessarily the most expensive. Goal 5x paid far more seats, but Goal 50x had the slightly larger
95th-percentile replay tail because the runs were longer.

### Existing gas regressions

- Standalone scheduled engine hard fixture: approximately 1.59M gas currently, with a regression
  bound of 2.25M.
- Maximum legal end-to-end single slip fixture: approximately 222k gas for its chosen word.
- Current 20-seat marginal fixture: approximately 114.3k gas per added seat.
- Current deterministic 80-seat whole-crank fixture: approximately 9.07M gas for its one table
  word. This is not a percentile and must not be used as the safety argument.
- The recent progressive/roll tracking work added only about 454 gas per marginal seat versus the
  previous tree. The field tail is primarily the pre-existing replay and payout work.

### Code size

The latest available artifact measured `CrapsBattle` at approximately 22,926 runtime bytes, leaving
about 1,650 bytes below EIP-170. Rebuild and report the authoritative final size; do not assume the
stale artifact remains exact.

</domain_knowledge>

<task_definition>

## Objective

Replace the fixed format/seat model with one outcome-sensitive budget shared with the existing box
walk. A bust-heavy table should walk many seats; a correlated hot table should stop earlier. The
batch boundary may change, but every eventual rank, payment, progressive result, action total, and
normalized event set must equal an unchunked settlement of the same field.

Do not implement a nine-format seat table. Do not tune only the current deterministic word.

## Required architecture

### 1. Make `resolveSlot` budget-native

Replace the second argument's count semantics outright:

```solidity
function resolveSlot(uint64 slot, uint64 gasBudget) external;
```

Keep the two ABI types, so the external selector remains unchanged, but rename the argument and
document the intentional semantic change everywhere. Do not add a parallel count-mode resolver.
The only production caller found in the current repository is `GameAfkingModule`; the other call
sites are tests and helpers that must be migrated to budget semantics.

`gasBudget` is a soft allowance for the measured/reserved Craps work described below. Resolution
stops after the first completed seat that reaches or crosses it. Thus:

- zero budget processes zero seats;
- any nonzero budget may process at least one complete seat, assuming the transaction supplies
  enough gas for it;
- a large budget processes until the budget is crossed, the field ends, or an internal hard seat
  ceiling is reached; and
- permissionless callers choose the budget they can afford instead of guessing a seat count.

Add an internal absolute memory/iteration ceiling independent of the caller's budget. Begin
evaluation with 256 seats; increase or reduce it only from measured minimum-seat cost, memory, and
hard-bound evidence. A caller can repeat `resolveSlot` to walk a deeper field. The gas budget, not
the ceiling, should normally stop a production crank.

This change preserves permissionless liveness and the function selector, but it is still a public
semantic change. Update interfaces, NatSpec, tests, keeper code, and client-facing documentation;
do not claim old integrations can continue treating the second value as a seat count.

### 2. Pass the actual box-budget remainder

Replace `_crapsSeatBudget(spentUnits)` with a saturating remaining-work calculation:

```text
remainingUnits = max(OPEN_WEIGHT_BUDGET - spentUnits, 0)
```

Convert that remainder to the gas allowance used by the budgeted resolver. Start from the box
calibration of roughly 4,700 gas per walk unit, but derive the final conversion and fixed reserves
from measurements of the complete router.

Required properties:

- zero remaining units can still arm a newly closed Craps window;
- zero remaining units cannot settle a seat;
- a fully consumed skip-only box walk cannot receive a nine-seat tail;
- half a box budget leaves approximately half the target work for Craps;
- all arithmetic saturates rather than underflowing;
- opening a real box retains the router's current category behavior and does not stack a Craps
  settlement batch.

### 3. Meter completed seats, not predicted formats

At the beginning of the shared resolver implementation, capture a gas meter before the readiness,
window, array, and loop work that belongs to Craps. After every completely resolved seat:

1. record the actual next cursor/end;
2. add the seat's stake/high action to the running batch totals;
3. append a nonzero return to the existing compact credit arrays;
4. compute consumed gas from the meter;
5. add a conservative reserve for every pending `creditFlipBatch` item; and
6. stop when consumed gas plus deferred/tail reserves reaches the supplied budget.

The check occurs after a seat because a run cannot be partially settled without storing a large
resumable engine state. One completed seat may therefore overshoot the soft target. That is
acceptable only with the separate deterministic hard-bound proof below.

The private batch routine must return the **actual processed end**, not merely the original
`from + maxCount` end. Use that actual end for:

- `_bonusCursor[slot]`;
- the processed action passed to `_bookDay`;
- winner arrays and their truncation; and
- the keeper's before/after progress test.

The resolver's nonzero-budget rule may complete one seat before checking the meter. Protect the
production composition in `GameAfkingModule`: if the remaining box allowance is below a measured
minimum-start threshold, pass zero rather than a tiny budget. Direct permissionless callers remain
free to pass a tiny nonzero budget to request one seat at their own gas risk.

### 4. Reserve delayed work accurately

Most settlement work occurs inside `_resolve` and is visible to the gas meter. The bankroll-return
`creditFlipBatch` occurs after the loop and is not. Measure at least:

- first credit to a distinct player's cold target-day stake;
- later credit to an already nonzero stake;
- multiple distinct cold recipients in one batch;
- repeated recipient, if reachable;
- empty batch; and
- the dynamic ABI/memory overhead.

Use the conservative distinct-cold marginal plus fixed batch overhead. A starting estimate of
roughly 30k gas per paid seat is reasonable for experimentation but is **not** an approved final
constant without a trace-backed measurement.

Final-field work performed synchronously inside `_scoreBattle`/`_payout`—main pot, progressive,
standing rollover, and high lane—is already visible to the meter. Do not reserve it twice. Do
reserve the post-loop `_bookDay`, cursor write, resolver return, router cursor check, keeper
`creditFlip`, and `MinerBounty` tail either in the resolver comparison or by subtracting a fixed
router reserve before the call.

### 5. Keep the economic result independent of chunking

The work budget may change only where one transaction stops. It must not change:

- shared shooter dice or any RNG domain;
- per-player scatter, survival, or shooter-boost schedules;
- Goal/Bust outcome, raw ending bankroll, or bust deletion;
- rank, remainder/money tiebreaks, standing tiebreak, or word-derived exact tie ordering;
- main/high winner identity;
- main pot, high-lane pot, scheduled boost, progressive qualification, or payout;
- `_dayStaked`/`_highStaked` totals;
- rounding;
- event schemas, payloads, exactly-once emission, or seat-id settlement order; or
- preview/payment parity.

Cross-contract log interleaving may naturally differ at transaction boundaries: a chunk's
`CoinflipStakeUpdated` logs occur before a later chunk's `CrapsBetSettled` logs. Equivalence means
no missing, duplicate, or altered economic event—not byte-for-byte global log ordering across a
different number of transactions.

The current comparator is designed to be order- and chunk-independent. Prove that property rather
than relying on it by inspection.

### 6. Calibrate the soft target and prove the hard target

The product target applies to the **complete** `game.mineFlip()` transaction, not a direct
`CrapsBattle.resolveSlot` call:

```text
worst evaluated full-crank p95 <= 9.5M gas
preferred useful band          = 9.2M to 9.5M gas
production mineFlip ceiling    < 16.7M gas
```

Begin with an untouched Craps allowance around 8.9M–9.0M before router-tail overhead, then tune
from the measurements. Do not reduce throughput merely to make a single fixture look comfortable;
the point of this change is to spend the available envelope efficiently.

The hard proof must account for the post-check overshoot by one complete seat. Use the engine's
2.25M regression ceiling plus measured scoring/finalization/credit/router tails. Include a crafted
last seat that is simultaneously expensive, paid, field-finalizing, progressive-qualifying, and
in the high lane where reachable. The complete production `mineFlip` path must remain below 16.7M
without a statistical assumption. A direct permissionless caller may supply a larger budget than
the keeper, but the internal seat ceiling still bounds one attempt. Such a caller is outside the
default keeper target and merely reverts its own transaction if it underfunds the requested work.

## Implementation sequence

1. Map the exact `mineFlip -> _crapsKeep -> resolveSlot -> _settleBatch -> _resolve ->
   creditFlipBatch` call and storage paths on the live tree.
2. Add isolated gas probes for Coinflip batch-credit marginal/fixed costs and the router tail.
3. Change `resolveSlot` from caller-count semantics to budget semantics and add the internal seat
   ceiling.
4. Make `_settleBatch` return its actual processed end and add outcome-sensitive metering.
5. Replace `_crapsSeatBudget` with the saturating shared-work remainder and update `_crapsKeep`.
6. Add economic-equivalence, boundary, composition, and adversarial gas tests.
7. Run the correlated simulations below and tune only documented constants.
8. Update stale comments/tests/docs that still describe 80 seats or 125k per seat as the safety
   argument.
9. Recheck storage layout, bytecode, formatting, focused suites, and the broader relevant suite.

## Required correlated gas study

### Prescreen

Use the C++ engine or another fast parity-checked harness for at least 30,000 shared table words per
candidate cell. Its purpose is to find adversarial candidates, not to declare final EVM gas.

Cover all nine scheduled depth/Goal combinations and at least these field compositions:

- all blank/random tickets;
- picked `4 Pass + 3 Place 8`;
- a legal picked board maximizing live branches after scatter;
- a low-edge/long-survival true-odds-oriented board;
- a high-edge/short-bust hardway board;
- a realistic mixed field using the strategy archetypes in
  [`CRAPS-FULL-GAME-SIM-PLAYER-STRATEGIES-PROMPT.md`](CRAPS-FULL-GAME-SIM-PLAYER-STRATEGIES-PROMPT.md);
- fields containing protocol and high seats where relevant.

Use one table word per field shared by every entrant. Preserve unique player addresses so scatter,
survival, and shooter-boost schedules remain player-specific. Record rolls, shooters, paid seats,
seats processed, field-finalization status, and the work proxy.

### Exact EVM replay

Then run the real contracts through `game.mineFlip()`:

- at least 512 words for every scheduled format on the leading field compositions;
- at least 2,000 words for every candidate that could be the worst p95;
- fields deeper than `maxCount`, so the work budget rather than field end normally stops the call;
- separate tail-of-field fixtures at remaining counts around the typical stop, so finalization is
  represented;
- cold recipient/day state for the conservative payout path; and
- box/Craps composition points at zero, near-zero, half, and full remaining work.

Report mean, p50, p90, p95, p99, observed maximum, paid-seat count, and processed-seat count. State
the percentile estimator and sample count. A single deterministic word is not evidence for a tail.

## Required tests

1. `resolveSlot(slot, gasBudget)` at zero, one/tiny, below the keeper minimum-start clamp, exactly
   the clamp, one-unit boundaries, half budget, full budget, and oversized caller budget.
2. Tiny nonzero direct budget completes exactly one seat in a sufficiently deep field; the
   production keeper converts the same sub-minimum remainder to zero.
3. Cursor advances exactly over processed seats and never over an unprocessed seat.
4. `_dayStaked` and `_highStaked` grow only by processed action and reach the identical final totals
   after all chunks.
5. All-bust, all-paid, alternating, correlated paid, long-bust, and cheap-bust fields.
6. Empty deferred-credit array and maximum processed paid-credit array.
7. Final seat triggers main payout, progressive common/rare payout, standing rollover, sole and
   contested high-lane paths.
8. A field settled with a very large budget versus tiny one-seat budgets versus several ordinary
   budgets: identical final storage, winners, amounts, progressive balance, action, and normalized
   economic event sets. Do not require impossible cross-transaction Coinflip/Craps log
   interleaving equality.
9. Preview result versus eventual paid result across budget boundaries.
10. Skip-only box work plus Craps at several `spentUnits` values; full box budget leaves zero Craps
    settlement capacity.
11. Arm still succeeds with zero settlement budget and remains a separate crank from walking the
    newly armed window.
12. A budgeted call with no ready field does not earn a work bounty.
13. Underfunded caller gas reverts safely without partial committed settlement; later adequate
    calls remain live.
14. Absolute one-seat overshoot fixture and production full-router hard ceiling below 16.7M.
15. Correlated p95 regression target for the selected worst candidates.
16. Runtime bytecode below 24,576 bytes and no storage-layout drift.

## Suggested verification commands

Adapt paths if the implementation creates a dedicated permanent gas suite.

```bash
forge test --match-path test/craps/CrapsGas.t.sol -vv
forge test --match-path test/fuzz/CrapsProtocolWiring.t.sol -vv
forge test --match-path test/craps/CrapsBattle.t.sol
forge test --match-path test/craps/CrapsProgressive.t.sol
forge test --match-path test/craps/CrapsShooterBoost.t.sol
forge test --match-path test/craps/CrapsHighRoller.t.sol
forge build --sizes
git diff --check
```

Also run the new correlated-tail suite explicitly and include its emitted table in the handoff.

## Deliverables

1. Minimal contract changes implementing the shared outcome-sensitive budget.
2. Permanent correctness, equivalence, composition, and gas-tail tests.
3. A reproducible simulation/probe source—no unexplained spreadsheet constants.
4. Updated keeper comments and Craps overview documentation.
5. A final report containing:
   - files changed;
   - exact budget/reserve constants and their trace evidence;
   - before/after throughput for bust-heavy, mixed, and paid-heavy fields;
   - all-nine-format and worst-candidate percentile tables;
   - maximum crafted production-crank gas and its margin to 16.7M;
   - code-size before/after;
   - storage-layout result;
   - tests/commands run; and
   - any unresolved caveat.

</task_definition>

<interaction_patterns>

- Work autonomously from inspection through focused verification.
- If code contradicts this plan, report the exact file/function and whether following code would
  violate the 9.5M target, hard ceiling, unchanged selector, documented API migration, or economic
  equivalence.
- Prefer measured traces and executable tests over prose estimates.
- Treat the unchanged selector but changed second-argument meaning as an intentional public API
  migration and list every repository call site updated.
- Do not stop at “tests pass.” Report the percentile distribution, processed-seat throughput, and
  deterministic hard-bound argument.
- Do not commit, deploy, or discard unrelated dirty-tree changes unless separately instructed.

</interaction_patterns>

<guardrails>

- Do not implement nine fixed caps or a depth/Goal lookup table.
- Do not retain a parallel caller-count settlement mode; one budget-native resolver is the design.
- Do not count every bust as a constant cheap unit; long busts must count their real replay work.
- Do not count only paid seats; a field of expensive busts must still stop.
- Do not use independent per-player dice in a gas simulation.
- Do not use the 9.07M one-word fixture as p95 evidence.
- Do not make batch boundaries affect rankings, payouts, progressive qualification, or action.
- Do not write resumable per-roll engine state merely to hit the soft target more tightly.
- Do not add storage for gas budgeting.
- Do not pay more than one keeper bounty or stack it with a box-open bounty.
- Do not weaken the absolute engine bound, RNG readiness checks, cursor contiguity, CEI ordering,
  creditor authorization, or preview/payment parity.
- Do not treat `try/catch` as the hard gas bound. A repeatable out-of-gas catch with no cursor
  progress is a liveness failure.
- Do not exceed EIP-170 or change storage layout.
- Do not reset or overwrite the user's existing Craps changes.

</guardrails>

<examples>

## Correct: cheap bust field

A shared word causes many entrants to bust after only a few rolls. Each completed seat consumes its
actual small replay/score/event cost, adds no deferred-credit reserve, and the call processes far
more than 54 seats before reaching the same work budget.

## Correct: correlated hot field

A shared word produces long runs and many nonzero payments. Actual consumed gas rises quickly and
each pending recipient adds the measured Coinflip reserve. The call stops after fewer seats, writes
the cursor to the last completed one, pays that compact batch once, and the next crank resumes at
the following seat.

## Correct: long bust

A player ultimately busts but only after hundreds of rolls. The seat receives no Coinflip reserve,
but all of its actual replay gas is already present in the meter. It is therefore much more
expensive than a short bust without needing a format-specific rule.

## Failure mode to avoid

Do not implement `bust = 1 unit, win = N units`. That underprices a long bust, recreates a correlated
out-of-gas/liveness risk, and makes the safety proof depend on outcome labels instead of work the
EVM actually performed.

</examples>

## Acceptance checklist

- [ ] No nine-format gas table exists.
- [ ] `resolveSlot(uint64,uint64)` keeps its selector but the second value is solely a gas budget.
- [ ] An internal hard seat ceiling bounds memory and iteration independently of caller budget.
- [ ] The keeper uses a saturating shared work remainder and zero remainder settles zero seats.
- [ ] Short busts consume less budget; long busts consume their actual cost; paid seats reserve
      the delayed Coinflip cost.
- [ ] The cursor, action, credits, and events cover exactly the seats processed.
- [ ] Chunking is economically identical to one-shot settlement.
- [ ] Worst evaluated full-crank p95 is at or below 9.5M and preferably at least 9.2M.
- [ ] Crafted production `mineFlip` maximum is below 16.7M with explicit margin.
- [ ] Box/Craps mixed-work compositions remain inside the same envelope.
- [ ] Runtime bytecode remains below EIP-170 and storage layout is unchanged.
- [ ] Permanent tests and reproducible percentile evidence ship with the implementation.
