<!-- generated-by: gsd-doc-writer -->
# Craps Battle System: Detailed Reference

> This document describes the contracts in the current working tree as of 2026-08-29. It is a
> system reference, not a promise about separately deployed bytecode. If deployed bytecode differs,
> the bytecode wins.

The Craps Battle system is a deterministic tournament built around a stateless craps engine.
Players burn FLIP to enter a field, lock a selected or random board before the settlement word
exists, and then replay that board over a shared sequence of shooters. Each seat earns its own run
return, while the best run wins the field's competitive pots.

There are two products behind the same entry and settlement machinery:

- **Scheduled Dice Runs** are the protocol's seven daily windows. They use a fixed five-round
  bankroll, a 5x or 20x target, a high-water continuation after reaching the target, shooter-profit
  boosts, protocol-funded ladder awards, a global progressive, and THE BIGGEST DICE RUN record.
- **Custom battles** are creator-defined legacy races. They stop when the target is reached, rank
  successful runs by speed, and receive no scheduled subsidy, progressive award, record claim, or
  action credit.

That boundary is structural: scheduled slots are below `2^40` and custom slots begin at `2^40`.
The engine is told which limits word to use from the slot. It does not guess the product from the
bankroll, target, board, or presence of a boost.

## 1. System at a glance

~~~text
daily or custom terms become public
              |
              v
players enter, burn FLIP, and lock or amend their boards
              |
              v
entry closes -> slot binds to a future lootbox-table index
              |
              v
future VRF word arrives
              |
              +--> shared shooter sequence
              +--> player-specific random board chips
              +--> player-specific survival flips and shooter boosts
              +--> payout rounding, ladder rung, and exact-tie ordering
              |
              v
permissionless resolveSlot calls walk the dense field in batches
              |
              +--> each Goal run receives rounded Coinflip credit
              +--> each Bust receives zero, although its raw remainder still ranks
              +--> main and high scoreboards update
              |
              v
the last resolved seat finalizes the field and pays:
    main bounty pot + donations + scheduled ladder
    contested or sole-rider high lane
    scheduled progressive, if qualified
    scheduled Dice Run record bounty, if a new record
~~~

Every payment is Coinflip stake credit. Entry burns FLIP, but Craps never transfers liquid FLIP
back to a player.

## 2. Vocabulary

| Term | Meaning |
|---|---|
| **Board** | The ten craps-leg chip counts a seat will replay for every shooter. |
| **Round** | One complete ten-chip board before the mandatory escalator. |
| **Shooter / hand** | One come-out-to-seven-out craps hand, capped at 512 rolls. |
| **Run / slip settlement** | The same board replayed over successive shooters from one bankroll. |
| **Bankroll** | The amount assigned to one unscaled run. |
| **Goal** | The run's target bankroll. It is a latch in scheduled play and a finish line in custom play. |
| **High point / peak** | Largest bankroll observed after a completed shooter. It ranks scheduled Goals but is never paid. |
| **Ending bankroll** | Bankroll remaining when the run actually stops. A Goal is paid from this figure. |
| **Bounty** | Player-funded amount each entrant contributes to a competitive pot. |
| **Ladder boost** | Protocol-funded scheduled award drawn for a window from its settlement word. |
| **High lane** | A second scoreboard and pot for seats that bought the day's or battle's high multiple. |
| **Standing** | Activity score frozen on the slip, refreshed only by a legal amendment. It is a late rank component and rations protocol money. |
| **Slot** | Numeric field identity. Scheduled: `day * 8 + period + 1`. Custom: `2^40 + sequence`. |
| **Bet ID** | `(storageSlot << 64) | seat`, with a dense 1-based seat number. |
| **Battle key** | Hash of slot and shared numeric terms. Different boards still race in the same field. |

## 3. Contracts and asset flow

### `Craps.sol`

`Craps` is pure, stateless game logic. It:

- resolves the ten supported craps wagers for one shooter;
- repeats a board across a bounded multi-shooter run;
- applies the mandatory wager escalator;
- handles the mid-run survival flip;
- applies the scheduled shooter-profit boost;
- tracks the ending bankroll, high point, shooters, and roll count; and
- returns a `SlipResult` without holding or moving funds.

Because a hand and run are pure functions of their inputs, they can be reproduced off-chain and
tested with `eth_call`.

### `CrapsBattle.sol`

`CrapsBattle` owns the tournament:

- scheduled and custom field creation;
- entry burns and packed slips;
- day tickets, future seats, passes, and upgrades;
- board validation and random scatter;
- future-word binding;
- resumable settlement;
- main and high scoreboards;
- bounties, donations, daily boost budgets, and the progressive;
- the Dice Run record call; and
- Coinflip crediting.

### `LootboxCraps.sol`

`LootboxCraps` reads protocol daily words and future lootbox-table words, supplies the protocol day
index, and derives the domain-separated Craps seed used by a window.

### Other pinned dependencies

- **FLIP** burns entry prices and can attach a one-use Craps boon to the resulting slip.
- **Coinflip** receives every player credit and owns the shared BIGGEST record pool.
- **DegenerusRecordBounty** holds the five soulbound BIGGEST trophies.
- **Game** opens each scheduled day and requests the future table word when a window is armed.
- **Vault** supplies ownership checks, its automatic board, and custom-creator administration.
- **GameAfkingModule** calls the scheduled keeper from the normal protocol crank and pays a flat
  1-FLIP Coinflip bounty when real scheduled work advances.

## 4. The ten-leg craps board

The board has exactly ten legs in this order:

| Index | Leg | Rule |
|---:|---|---|
| 0 | Pass Line | Pays 1:1 profit on a come-out 7/11 and on every point made. It remains live until its first come-out 2/3/12 or the shooter's seven-out. |
| 1 | Place 4 | Pays 2:1 profit per hit and stays live; true odds. |
| 2 | Place 5 | Pays 3:2 and stays live; true odds. |
| 3 | Place 6 | Pays 7:6 and stays live. |
| 4 | Place 8 | Pays 7:6 and stays live. |
| 5 | Place 9 | Pays 3:2 and stays live; true odds. |
| 6 | Place 10 | Pays 2:1 and stays live; true odds. |
| 7 | Hard 4 | Hard 4 pays 7:1 and stays; easy 4 or 7 kills it. |
| 8 | Hard 8 | Hard 8 pays 9:1 and stays; easy 8 or 7 kills it. |
| 9 | Don't Pass | One decision per shooter; a win returns principal plus 3:4 profit. |

Place bets and hardways are off on the come-out. The player cannot toggle them on.

### Pass Line behavior

This is a ride-to-seven-out Pass Line, not a single casino decision. Naturals and made points pay
profit while the line remains live. A come-out 2, 3, or 12 kills it without ending the shooter.
A point-phase seven-out kills it and ends the shooter.

### Don't Pass behavior

Don't Pass is the only supported wager that does not stay active after its decision:

- come-out 2 or 3: wins principal plus 3:4 profit;
- come-out 7 or 11: loses;
- come-out 12: pushes and remains live for the next come-out;
- after a point is established: seven-out wins, point made loses; and
- if the 512-roll cap ends the hand while unresolved, principal is returned.

### Unsupported wagers

There are no Come, Don't Come, Field, one-roll propositions, pass odds, Fire/ATS, Big 6/8, take-downs,
presses, or between-roll player decisions. The board is fixed before the first roll.

### Bounded loss

The entire round is posted once before a shooter:

- light-side wins add profit while their principal stays exposed;
- Don't Pass can lose no more than its own principal;
- no supported bet can be re-armed during the hand; and
- a roll-cap truncation refunds every stake still live.

Therefore one shooter can lose at most the known round size. That invariant is what permits the
multi-shooter engine to subtract the complete mandatory round before running the hand.

## 5. Board selection, encoding, and scatter

A seat has two board modes:

1. **Picked:** submit exactly seven chips; settlement randomly places the remaining three.
2. **Blank:** submit zero; settlement randomly places all ten.

For a picked board:

- the submitted counts must sum to exactly seven;
- no selected leg may contain more than four chips;
- Pass Line and Don't Pass cannot both be selected; and
- the values are chip counts, not FLIP amounts.

Random scatter may put the resolved board above four chips on a leg or add a chip to the opposite
line. The restriction governs player selection, not the random board.

### Packed `uint32` layout

Each count uses three bits. Bits 30 and 31 must be zero.

| Leg | Bit offset |
|---|---:|
| Pass Line | 0 |
| Place 4 | 3 |
| Place 5 | 6 |
| Place 6 | 9 |
| Place 8 | 12 |
| Place 9 | 15 |
| Place 10 | 18 |
| Hard 4 | 21 |
| Hard 8 | 24 |
| Don't Pass | 27 |

The same word is accepted by entry and amendment functions, stored in the slip, and emitted in
`CrapsSlipPlaced` and `CrapsSlipAmended`.

### Correlated field, private board

All entrants in one window use the same shooter stream. Random scatter is keyed by the settlement
word and the slip owner, so each player normally gets a different completed board. Survival flips
and scheduled shooter boosts are also player-specific.

This makes a field a correlated tournament. Players are not taking independent samples from a
casino table; they are choosing different responses to the same sequence of shooters.

### Amendments

The owner may replace a slip's chip allocation with a legal seven-chip board while entry is still
open:

- a window or custom slip locks when its entry clock closes, even if nobody has armed it yet;
- a whole-day or future-day ticket locks when that day's opener closes;
- terms, owner, seat, boon, and high status cannot change; and
- the slip's standing is refreshed to the owner's current activity score when amended.

A blank slip can be amended into a picked board. `amendSlip` itself requires seven chips, so it
does not turn a picked ticket back into a blank one.

## 6. One shooter

For run seed `seed` and shooter number `i`:

~~~text
handSeed = keccak256(seed, i)
roll j   = keccak256(handSeed, j)
~~~

Two 32-bit slices of the roll hash become dice values modulo six plus one.

A shooter ends on a point-phase seven-out or after 512 rolls. If the cap is reached, unresolved
live principal is returned. The cap is an execution guarantee, not a meaningful source of ordinary
outcomes.

The engine returns:

- the amount returned by the hand;
- the roll cursor;
- the profit portion eligible for a scheduled shooter boost; and
- enough state to distinguish principal from profit, particularly on Don't Pass.

## 7. The multi-shooter run

The same resolved board is replayed against successive shooters from one bankroll.

At a high level:

~~~text
bankroll = starting bankroll
peak = bankroll

for each shooter:
    check goal or goal latch
    check shooter and roll bounds
    compute mandatory escalated round
    check affordability or protected reserve
    if partially affordable before qualification, take survival flip
    subtract the mandatory round
    resolve one complete shooter
    add the hand return and any shooter-profit boost
    update peak at this completed-shooter boundary

return ending bankroll, peak, shooters, rolls, Goal/Bust
~~~

### Mandatory escalator

The engine resolves the base board once, then scales its stake and return linearly.

One rule set, scheduled and custom alike.

| Property | Every run |
|---|---:|
| Doubling period | Every 3 shooters |
| Multiplier ceiling | `uint32.max` |
| Shooter cap | 512 |
| Between-shooter roll budget | 8,192 |
| Absolute roll ceiling | 8,703 |
| Goal behavior | Latch and continue |

Multipliers are 1x for shooters 0-2, 2x for 3-5, 4x for 6-8, and so on; the ceiling is reached at
shooter 96.

The roll budget is checked between shooters. A shooter is never cut in half, so the absolute
ceiling is `budget - 1 + 512`.

### Affordability and survival

Let `need` be the next escalated round:

- `bankroll < need / 2`: immediate Bust with the positive remainder retained as the raw ending
  bankroll;
- `need / 2 <= bankroll < need`: one player-specific fair survival flip;
  - win: the complete bankroll doubles and the shooter is played;
  - loss: bankroll becomes zero and the run Busts;
- `bankroll >= need`: play normally.

The survival result is keyed by the run seed, shooter ordinal, and player. Entrants share dice but
do not share this second chance.

### Scheduled shooter-profit boost

Only scheduled windows attach a per-shooter profit boost:

| Ticket class | Eligible shooters | 5x Goal | 20x Goal |
|---|---:|---:|---:|
| Blank/random | 15% | +33% | +45% |
| Picked | 5% | +20% | +50% |

Eligibility is drawn independently for each player and shooter. The class comes from the stored
pre-scatter ticket: a blank ticket remains a blank-class ticket after the dice place its chips.

The percentage applies only to eligible **profit**:

- included: Pass profit, Place profit, Hardway profit, and the 3:4 Don't Pass profit;
- excluded: all wager principal, roll-cap refunds, survival doubling, pre-existing bankroll, and
  post-run awards.

The uplift is floored on the base hand and then scaled by the mandatory escalator. It lands in the
bankroll before the next stop and affordability checks, so it can legitimately:

- cross the Goal;
- fund an otherwise unaffordable shooter;
- change the high point;
- change the field winner; or
- turn a would-be Bust into a Goal.

Custom battles receive a zero schedule and use the bare engine.

### Scheduled high-water lifecycle

Reaching the scheduled Goal does not end the run.

At the first completed-shooter boundary where `bankroll >= goal`:

1. Goal qualification permanently latches.
2. The Goal becomes a protected reserve.
3. The run continues using only bankroll above that reserve.

For every later shooter, the run plays exactly when:

~~~text
bankroll - nextMandatoryRound >= goal
~~~

Equality is playable. If the surplus is insufficient, the run retires as a Goal without posting
another shooter.

Consequences:

- the survival flip is never taken after qualification;
- a losing post-Goal shooter cannot reduce the bankroll below the Goal;
- a hard execution bound after qualification ends as Goal;
- a hard bound before qualification ends as Bust;
- the ending bankroll may be below the run's high point; and
- the high point is sampled after each completed shooter and is never itself paid.

### Custom finish line

A custom run stops at the first between-shooter check where `bankroll >= goal`. It receives no
high-water continuation. Its successful-run race therefore remains a speed race.

## 8. Individual settlement and payment

Each engine result produces three economically different figures:

| Figure | Purpose |
|---|---|
| `won` / ending bankroll | Raw unscaled bankroll at the actual stop. Used in ranking even for a Bust. |
| `peak` | Largest completed-shooter bankroll. Used to rank scheduled Goals and test the progressive and record. |
| `paid` | Actual Coinflip credit after rounding, Bust deletion, high scaling, rider, and boon. |

### Rounding

For a nonzero Goal result:

- at or below 1,000 FLIP: floor to whole FLIP;
- above 1,000 FLIP: probabilistically round to a 100-FLIP multiple using committed entropy.

The hundreds rounding preserves expectation apart from discarded sub-FLIP dust.

### Bust deletion

Every Bust receives zero individual credit, even when it stopped with a positive raw remainder.
The entry FLIP was already burned, so deletion means the protocol declines to recreate that
remainder as Coinflip credit. It is not transferred to the battle winner, ladder, progressive, or
record pool.

The raw remainder still participates in Bust ranking.

### High-seat scaling

A high seat buys `H` copies of one run:

- the engine runs one unscaled bankroll;
- ranking uses the unscaled result;
- rounding happens once on the single-copy result; and
- individual run credit is multiplied by `H` afterward.

Buying more copies never improves rank.

### Craps boon

Some FLIP burns return a one-hot boon stored on the slip:

| Mask | Bonus |
|---:|---:|
| 1 | 5% |
| 2 | 10% |
| 4 | 15% |

The boon applies after the base run payment has been rounded and high-scaled. Its payout base is
capped at 60,000 FLIP PER SETTLEMENT, so the maximum additions are 3,000, 6,000, and 9,000 FLIP a
window. A whole-day ticket settles seven times, so its top tier tops out at 63,000 FLIP across the
day — which is what the top rate pays for, rather than a whole-ticket cap that would need
cross-window state and hand settlement order an outcome to choose.

It affects only individual run credit. It does not affect:

- the engine bankroll or high point;
- Goal/Bust status;
- either scoreboard;
- the main or high pot;
- the progressive or record;
- booked action; or
- a sole high rider.

THE BOON RIDES EVERY WINDOW ITS TICKET PLAYS. A whole-day ticket's burn paid for seven windows, so
its boon lifts all seven bankroll payments. A multi-day purchase carries one boon, on the first
reserved day's ticket. Custom and window-local slips apply their boon to their own run.

Settlement order cannot reach any of it: each window's lift is a function of that window's run and
the mask alone, so every answer is fixed before any window is cranked.

## 9. Battle ranking

Every field ranks and names a winner, including a zero-bounty custom battle.

The main scoreboard uses this lexicographic order:

1. **Goal beats Bust.**
2. Among scheduled Goals: larger high point wins.
3. Among custom Goals: fewer shooters wins.
4. Among Busts in either product: more completed shooters wins.
5. If the primary measure ties: larger raw ending bankroll, floored to whole FLIP, wins.
6. If money ties: larger frozen standing wins.
7. If everything ties: a deterministic hash of the settlement word and seat gives a total order.

The final hash makes exact ties independent of entry and settlement ordering.

Important consequences:

- A Bust's high point is irrelevant. Busts rank on longevity, then remainder.
- A 12-shooter Bust beats an 11-shooter Bust regardless of remainder.
- A scheduled Goal that peaked high and later fell back ranks on the peak but is paid on the end.
- A high multiple does not enter either scoreboard.
- The high-only scoreboard uses the same unscaled composite as the main field.

## 10. Scheduled Dice Runs

### Protocol day and close schedule

The protocol day resets at 22:57 UTC. Seven windows are opened from the day's committed word:

| Period | Close time UTC | Kind |
|---:|---|---|
| 0 | 23:20 | Opener; routine tier drawn one-third each |
| 1 | 03:00 | Routine |
| 2 | 07:00 | Routine |
| 3 | 11:00 | Routine |
| 4 | 15:00 | Routine |
| 5 | 19:00 | Routine |
| 6 | 22:42 | Event; closes 15 minutes before turnover |

All seven terms are knowable after the daily word lands. That daily word does not settle their
dice; each window binds a separate future table index after its own entry closes.

### Routine terms

Period 0 draws Small, Medium, and Large uniformly. Periods 1-5 draw them 70% / 20% / 10%.

| Tier | Starting bankroll | Bounty possibilities | Ten-chip round | Chip value |
|---|---:|---:|---:|---:|
| Small | 300 FLIP | 100 / 200 / 300 | 60 FLIP | 6 FLIP |
| Medium | 1,200 FLIP | 300 / 800 / 1,200 | 240 FLIP | 24 FLIP |
| Large | 3,000 FLIP | 1,000 / 1,500 / 3,000 | 600 FLIP | 60 FLIP |

### Event terms

The event bankroll is:

- 1,500 through 15,000 FLIP in 1,500-FLIP increments for the ordinary 93% branch;
- 30,000 FLIP with 5% probability; or
- 60,000 FLIP with 2% probability.

Its bounty is 25%, 30%, 35%, 40%, 45%, or 50% of bankroll, floored to a 100-FLIP granule.
The round remains one-fifth of bankroll.

### Terms shared by all scheduled windows

- Bankroll depth: exactly five rounds.
- Goal: 5x or 20x starting bankroll, evenly drawn.
- High multiple: 10x on 90% of days, 100x on 10%.
- Minimum standing: zero; scheduled fields do not gate entry on activity.
- Multi-entry: off; one seat per address per window.

## 11. Scheduled entry modes

### One current-day window

`enterBonusBattle(period, chips, multiple)` joins one open window:

- `multiple = 1` is ordinary;
- otherwise it must exactly equal the day's 10x or 100x high multiple; and
- a stale or intermediate multiple reverts rather than being silently reinterpreted.

### Whole current day

`enterBonusDay(chips, multiple)` buys one ticket for all seven windows. It is available only while
period 0 is still open. After the opener closes, remaining windows must be joined individually.

The whole-day ticket:

- burns the sum of all seven `bankroll + bounty` prices, scaled by the chosen multiple;
- stores one slip in the reserved day slot;
- joins each window when that window is armed;
- uses the same board and standing in all seven; and
- blocks another seat by the same address anywhere in that day.

The tagged burn credits one quest-streak step for an ordinary day ticket and five for a high day
ticket. Single-window entry, future reservation, and later upgrades do not add that day-ticket
streak.

### Pass credits and future reservations

Passes are future seats, not discount coupons:

- `deliverPasses` tries to reserve tomorrow immediately and banks any remainder as credits;
- if both types are delivered, the high pass gets first claim on tomorrow;
- `applyCrapsPasses(startDay, count, high, chips)` spends banked credits;
- `buyFutureCrapsDays(startDay, count, high, chips)` burns fixed prices of 25,000 ordinary or
  450,000 high FLIP per day; and
- a multi-day range is all-or-nothing and must be strictly future, unworded, and unoccupied.

A future high reservation adopts that future day's eventual 10x/100x multiple. It does not store
a guessed multiple in advance.

The seat exists immediately when reserved. There is no later redemption transaction or failure to
return that causes expiry. Its initial board may be blank or picked and can be amended until that
day's opener closes.

### Upgrading selected windows

`upgradeDayWindows(day, periodMask)` upgrades selected windows of the caller's existing normal
whole-day ticket:

~~~text
additional burn per selected window
    = (H - 1) * (bankroll + bounty)
~~~

Bits 0-6 name periods 0-6. Every newly selected window must still be open and unarmed. The call is
atomic: one invalid selected window reverts the whole upgrade.

Already-high bits are ignored, but a mask containing nothing new reverts. There is no downgrade,
transfer, refund, or additional quest credit.

### Protocol day seats

The constructor banks **twenty normal day passes to each body**, so the opening days are seated
out of that bank instead of the reserve.

At day opening, sDGNRS and the Vault may receive whole-day seats:

- an existing reservation is honored without another charge;
- otherwise the contract spends a banked pass first, a high pass ahead of a normal one;
- if the bank is empty, it tries a direct FLIP burn;
- the Vault skips the day if none can fund it;
- sDGNRS is the one fail-soft house seat and is still seated if unfunded; and
- the Vault may use a legal picked board, a blank board, or the OFF sentinel.

Both protocol bodies are seated at full standing. Once present, their boards and runs compete
under the same rules as player seats.

## 12. Entry price, pots, and donations

### Entry burn

An ordinary seat burns:

~~~text
bankroll + bounty
~~~

A high seat burns:

~~~text
H * (bankroll + bounty)
~~~

Board choice does not change the price.

### Main pot

Every seat, including a high seat, contributes exactly one bounty to the main pot:

~~~text
main pot
    = entrants * bounty
    + standing-adjusted scheduled ladder award
    + exact donations
~~~

Deleted Bust remainders do not enter this pot.

### Donations

Anyone may burn 100-FLIP granules into a joinable scheduled or custom field. Donations:

- create no seat;
- are final and nonrefundable;
- pay exactly to the main winner;
- are not standing-rationed;
- are not boost-rounded; and
- do not count as bankroll action.

## 13. Scheduled funding and ladder

The protocol records scheduled bankroll action to the day the field played, even if settlement is
late. Bounties, donations, boons, ladder awards, progressive awards, and custom volume do not enter
the action book.

Let `A_R(d)` and `A_H(d)` be ordinary and high bankroll action for a prior day. The next budget uses
the average of the preceding seven days:

~~~text
E_R = average(A_R * 12%)
E_H = average(A_H * 12%)

rawMainBudget = 50,000 FLIP + E_R + 40% of E_H
highBudget    = 60% of E_H
~~~

At steady action this is:

~~~text
rawMainBudget = 50,000 + 0.120 * ordinaryAction + 0.048 * highAction
highBudget    = 0.072 * highAction
~~~

The 50,000-FLIP base is additive, not a floor.

### Main split

When the day opens:

~~~text
ladderBudget            = floor(rawMainBudget / 2)
progressiveContribution = rawMainBudget - ladderBudget
~~~

The odd wei goes to the progressive. The high budget is not halved.

The event receives half of the ladder. The other half is split across periods 0-5 with
Small/Medium/Large weights 1/2/4.

### Window ladder

Each window draws one multiplier from its future settlement word:

| Probability | Award relative to window share |
|---:|---:|
| 76.8% | 0.25x |
| 20.8% | 1x |
| 2.0% | 10x |
| 0.4% | 100x |

The expected multiplier is exactly 1x. The published budget is an expected allocation, not a
per-day cap.

### Standing ration

Only protocol-funded value is rationed:

| Frozen standing | Share of protocol award |
|---:|---:|
| 0 | 0 |
| 1-10 | `1 / (12 - standing)` |
| 11+ | Full |

Main and high ladder amounts are computed in 100-FLIP granules. Above 4,000 FLIP they round to the
nearest 1,000.

Protocol boost denied by standing is deposited into the progressive. Player bounties and
donations always pay whole.

## 14. High-roller lane

A high seat participates in:

1. the ordinary main scoreboard with one unscaled score;
2. individual run payment scaled by `H`; and
3. a high-only sideboard funded by its extra `H - 1` bounties and the high budget.

### No high seats

No sideboard payment or high-lane ladder award exists.

### Exactly one high seat

There is no high race. The extra bounties and admitted high-lane boost ride the seat's own run:

~~~text
rider = floor(
    individualSingleCopyPaid / bankroll
    * (extraBounties + admittedHighBoost)
)
~~~

A Bust has zero individual payment and therefore returns zero rider. The standing-denied portion
of the offered boost enters the progressive before the rider is calculated.

### Two or more high seats

The best high score receives:

~~~text
highHeads * (H - 1) * bounty
    + standing-adjusted high-lane ladder award
~~~

The high field uses the same comparator and exact-tie hash as the main field. A player can win
both scoreboards. If every high seat Busts, the best-ranked Bust wins the high lane.

Only the protocol-funded high-lane amount is standing-rationed; extra player bounties pay whole.

## 15. Goal-Jackpot progressive

There is one global scheduled progressive. It is funded by:

- half of every day's raw main allocation when the day opens; and
- main/high ladder value denied by standing.

It is not funded by player bounties, donations, principal, run losses, Bust remainders, custom
volume, or record-pool money.

### Qualification

Only the finalized **main winner** of a scheduled field can qualify:

1. the winner must be a Goal;
2. the winner's unscaled high point is divided by starting bankroll into score basis points;
3. the cutoff for that field's 5x or 20x Goal is applied; and
4. rare is tested before common and replaces it rather than stacking.

| Scheduled Goal | Common cutoff | Rare cutoff |
|---:|---:|---:|
| 5x | 25x high point | 120x high point |
| 20x | 50x high point | 225x high point |

### Award

The share depends on which window finalized. A day's seventh and last window (period 6) is its
**main event**; periods 0-5 are **routine**.

| Window | Common | Rare |
|---|---:|---:|
| Routine (periods 0-5) | 5% | 10% |
| Main event (period 6) | 20% | 40% |
| Main event, after a repeat victory | 40% | 80% |

The main event doubles when its winner already won a **routine** field the same protocol day with
that field's winning stop being **Goal**. The qualifying victory must be a distinct routine field
finalized before the event, the same address must have been its **main bounty winner**, and it need
not have triggered the progressive itself. One victory is enough and they never stack; the event
cannot qualify itself; and the state is read at resolution time, so an event resolved before the
routine victory does not double.

**A routine window never doubles.** The 5% and 10% figures are the routine schedule, not a
first-win rate that a repeat lifts.

~~~text
isEvent = (slot % 8 == 7)
base    = isEvent ? (rare ? 4_000 : 2_000) : (rare ? 1_000 : 500)   // basis points
bps     = isEvent and wonARoutineGoalToday(winner) ? base * 2 : base

candidate = floor(livePool * bps / 10_000)
paid      = standingShare(candidate)
livePool -= paid
~~~

The pool percentage is applied **before** the standing adjustment. The candidate is computed by
splitting the pool at the denominator first, which is exactly `floor(livePool * bps / 10_000)` and
cannot overflow at the 80% rung. Custom battles are excluded from the whole schedule.

Only the actual credit leaves the pool. The standing-retained portion was already in the pool and
stays there.

Awards use the live balance sequentially. A high seat receives one progressive award if it wins
the main field; `H` does not multiply it. Winning only the high sideboard does not qualify.

The progressive is paid as a separate Coinflip credit and has separate events from the main pot.

## 16. THE BIGGEST DICE RUN

Dice Run is category 4, the fifth trophy in the existing BIGGEST system. It uses Coinflip's shared
record pool and adds no Craps-specific pool, drip, fee, or action.

### Candidate and eligibility

- Candidate: finalized scheduled main winner's high point divided by starting bankroll.
- Unit: score basis points, where 10,000 is 1x.
- Entry floor: 1,000,000 bps, or 100x.
- Custom fields and Bust winners cannot qualify.
- The candidate must strictly exceed the standing Dice Run mark.
- Unlike the four older BIGGEST categories, Dice Run does not require a 20% improvement.

### Every genuine improvement receives the bounty

The record is judged when the field finalizes:

- every strict improvement at or above 100x moves the mark and trophy;
- every such improvement claims from the remaining shared record pool;
- the share is 5% plus 0.5 percentage points per elapsed protocol day, capped at 75%;
- a claim stamps the Dice Run clock to the current day;
- another strict improvement on the same day therefore receives the 5% floor; and
- a delayed lower candidate that no longer beats the live mark receives nothing.

This is intentional resolution-time behavior. A player who leaves a winning field unresolved may
lose record eligibility if another field establishes a higher mark first.

Several same-day records compound against the remaining pool. After the first day's accrued claim,
`k` additional 5% claims leave `0.95^k` of the balance they started from.

Coinflip credits the record bounty directly and emits `BigRecordUpdated`. Dice Run does not receive
the sDGNRS reward-pool leg used by the four older categories.

## 17. Custom battles

The Vault majority owner can create a custom battle and can grant or revoke creator addresses.
Joining, closing, settling, and donating remain public under the battle's terms.

### Legal terms

| Term | Range |
|---|---|
| Ten-chip round | Positive whole-FLIP multiple of 10, at most `uint24.max` FLIP |
| Bankroll depth | 1-25 rounds |
| Minimum bankroll | 300 FLIP |
| Goal | 5x-1,000x bankroll |
| Bounty | 0 through bankroll, in 100-FLIP units |
| Minimum standing | 0-4,095 |
| Close time | Future timestamp |
| Multi-entry | Creator-selected |
| High multiple | 0 for none, or 2-256 |

A custom battle with zero bounty still settles and names a winner. Donations can create a main
prize even when the creator selected zero bounty.

### What custom battles share

Custom battles reuse:

- board validation and scatter;
- future-word binding;
- shared shooters and player-specific survival flips;
- entry burns and Coinflip credits;
- Bust deletion and payout rounding;
- boons;
- main and optional high scoreboards;
- donations;
- batched `resolveSlot` settlement; and
- deterministic exact-tie ordering.

### What custom battles do not share

Custom battles play by the same rules and differ only in what money reaches them. They:

- receive no shooter-profit schedule;
- receive no daily ladder or high subsidy;
- book no scheduled action;
- neither fund nor claim the progressive; and
- cannot set THE BIGGEST DICE RUN.

A creator may copy a scheduled bankroll, five-round depth and 5x/20x target exactly and get a
run that plays identically — it simply pays only what its own field burned.

## 18. Randomness, closing, and liveness

### Two different words

Scheduled play deliberately separates:

1. **Daily terms word:** known before entry and used to draw bankrolls, bounties, Goals, and the
   day's high multiple.
2. **Settlement word:** selected only after the window closes and used for the actual tournament.

When entry closes, `armBonusWindow` binds the slot to `currentTableIndex + 1`. That word cannot
already exist. `closeBattle` does the same for custom fields after their creator-set deadline.

Arming requests lootbox RNG on a fail-open basis. If the request cannot be made in that call, the
binding remains and the table can be filled by the shared lootbox lane later.

### Domain separation

The future word feeds separate domains for:

- window-specific shared shooters;
- owner-specific random scatter;
- owner- and shooter-specific survival flips;
- owner- and shooter-specific scheduled profit boosts;
- per-bet rounding;
- main/high ladder rung;
- exact-score tie ordering.

The daily word separately derives the scheduled terms and high multiple.

### Permissionless settlement

Anyone may:

- arm a closed scheduled window;
- close an expired custom battle;
- call `resolveSlot(slot, budgetUnits)`; and
- call `keepScheduled(budgetUnits)`.

`resolveSlot` uses a dense cursor and settles at most 256 seats per call. Its production throttle
is not that ceiling but a deterministic work budget:

~~~text
seat cost
    = 7 base units
    + totalRolls / 6
    + 6 units if the seat receives a credit
~~~

The charge is applied after one complete seat, so a call may overshoot by one seat but never leaves
a half-resolved run. No `gasleft()`-dependent state transition exists.

The scheduled keeper remembers the oldest scheduled slot still owing work. It can:

- cross completed or empty slots;
- refund reservations from a day the protocol never opened;
- arm a window whose clock has closed;
- settle the next batch of an armed and worded field; and
- resume the same field on a later crank.

Direct permissionless help and the protocol crank share the same state. Externally completed work
is observed and crossed rather than repeated.

## 19. IDs, events, and read surfaces

### IDs

~~~text
scheduled window slot = day * 8 + period + 1
whole-day storage slot = day * 8
custom slot base       = 2^40
bet ID                 = (storageSlot << 64) | seat
~~~

A whole-day ticket is one stored bet reused in seven window fields. Its bet ID can therefore
appear in seven `CrapsBetSettled` events.

### Primary player functions

| Function | Purpose |
|---|---|
| `enterBonusBattle(period, chips, multiple)` | Join one current-day scheduled window. |
| `enterBonusDay(chips, multiple)` | Buy all seven windows while the opener is still live. |
| `enterBattle(slot, chips, multiple)` | Join a custom battle. |
| `amendSlip(betId, chips)` | Re-spread an unlocked slip to seven legal chips. |
| `applyCrapsPasses(startDay, count, high, chips)` | Spend pass credits on consecutive future days. |
| `buyFutureCrapsDays(startDay, count, high, chips)` | Buy consecutive future days at fixed prices. |
| `upgradeDayWindows(day, periodMask)` | Upgrade selected live windows of a normal day ticket. |
| `donate(custom, index, granules)` | Add exact 100-FLIP granules to a joinable field. |
| `previewSettlement(betId)` | Return the run's `won` and individual `paid` once its word exists. |
| `progressivePool()` | Return the live scheduled progressive balance. |

### Permissionless lifecycle functions

| Function | Purpose |
|---|---|
| `armBonusWindow(slot)` | Bind a closed scheduled window to a future table index. |
| `closeBattle(slot)` | Bind an expired custom battle. |
| `resolveSlot(slot, budgetUnits)` | Settle the next deterministic batch. |
| `keepScheduled(budgetUnits)` | Advance the oldest scheduled lifecycle work. |

### Important events

| Event | Meaning |
|---|---|
| `CrapsSlipPlaced` | Seat, packed board, multiple, frozen standing, and boon. |
| `CrapsSlipAmended` | New packed seven-chip board. |
| `CrapsBonusOpened` | Scheduled terms and maximum ladder quote. |
| `CrapsBattleCreated` | Packed custom terms. |
| `CrapsBonusArmed` | Battle key, slot, and future table index. |
| `CrapsBetSettled` | Raw scaled ending bankroll and actual individual credit. |
| `CrapsBattleFinalized` | Winner, Goal/Bust, peak, end, score, and advertised pot. |
| `CrapsBattlePaid` | Actual main-pot credit. |
| `CrapsHighRollerPaid` | Sole rider or contested high-lane payment. |
| `CrapsProgressiveFunded` | Daily contribution into the global progressive. |
| `CrapsProgressiveRolled` | Standing-denied ladder value moved into the progressive. |
| `CrapsProgressivePaid` | Progressive tier, the applied `poolBps` rung, candidate, credit, and pool after. What standing denied is `candidate - paid`. |
| `BigRecordUpdated` on Coinflip | Dice Run record mark and shared-pool claim. |

The event stream is the main integration surface. The contract intentionally avoids restating
derivable tables and results in many on-chain views to preserve deployment bytecode.

## 20. Worked examples

### Scheduled Small, 5x field

Assume:

- bankroll: 300 FLIP;
- round: 60 FLIP;
- chip: 6 FLIP;
- Goal: 1,500 FLIP;
- bounty: 100 FLIP; and
- ordinary seat.

The player burns 400 FLIP. Their picked seven-chip board receives three random chips, producing a
60-FLIP board. The run doubles its mandatory round every three shooters.

Suppose the run:

- first crosses 1,500 FLIP after a completed shooter;
- continues under the protected-reserve rule;
- reaches a 9,000-FLIP high point;
- gives back surplus and stops at 1,800 FLIP.

The result is:

- Goal;
- high-point score: 30x, or 300,000 bps;
- individual payment base: the 1,800-FLIP ending bankroll, not 9,000;
- main ranking measure: 9,000-FLIP peak;
- common progressive qualification: yes, because 30x exceeds the 25x 5x-Goal cutoff — which pays
  5% of the live pool on a routine window and 20% on the day's main event;
- rare qualification: no, because it is below 120x; and
- Dice Run record eligibility: no, because it is below 100x.

If this seat is the field's main winner, it receives the main pot and its standing-adjusted common
progressive credit in addition to its individual run credit.

### Scheduled high seat

On a 10x day, the same 300 + 100 terms cost 4,000 FLIP. The engine still evaluates one 300-FLIP
run and one unscaled board:

- score and main/high rank are identical to an ordinary copy;
- rounded individual run payment is multiplied by ten;
- one bounty joins the main pot;
- nine extra bounties join the high-lane economics; and
- a main-field progressive or record bounty is still paid once, not ten times.

### Custom battle

Assume a creator chooses:

- 100-FLIP round;
- five-round bankroll depth;
- 20x Goal;
- 100-FLIP bounty;
- no high lane.

Each ordinary seat burns a 500-FLIP bankroll plus 100-FLIP bounty. The run uses the legacy
five-shooter escalator and stops immediately when it reaches 10,000 FLIP. Successful seats rank by
fewest shooters, then ending bankroll and standing. No daily ladder, progressive, record, shooter
boost, or scheduled action is involved.

## 21. Non-obvious invariants and consequences

- **Peak is never paid.** It ranks scheduled Goals and feeds the progressive and record.
- **Ending bankroll is never scheduled Goal rank's first measure.** It is the next money tie-break
  and the individual payout base.
- **Bust remainder can rank but cannot pay.**
- **A high seat buys copies, not a better score.**
- **The field shares shooters but not completed random boards, survival flips, or shooter boosts.**
- **The daily terms word is not the settlement word.**
- **A window closes by the clock even before somebody arms it.** Late amendment is not possible.
- **Scheduled action follows the day played, not the day resolved.**
- **Custom action never feeds scheduled emission.**
- **Player money is never standing-rationed.** Only protocol-funded value is.
- **Progressive awards use the live balance.** Earlier qualifying windows reduce what later ones
  can claim.
- **Every strict Dice Run record improvement gets its bounty at resolution time.** Delayed
  resolution can lose eligibility to a higher mark.
- **Settlement chunking cannot change the result.** The cursor, scoreboards, and deterministic
  work budget make one large resolve and many small resolves equivalent.
- **Friendly custom fields still rank.** A zero pot removes payment, not the tournament.

## 22. Source map and verification

Primary implementation:

- [`contracts/Craps.sol`](../contracts/Craps.sol) — one-shooter table and multi-shooter engine.
- [`contracts/CrapsBattle.sol`](../contracts/CrapsBattle.sol) — entries, fields, settlement,
  scoreboards, payouts, progressive, and keeper.
- [`contracts/LootboxCraps.sol`](../contracts/LootboxCraps.sol) — day/table words and Craps seed.
- [`contracts/Coinflip.sol`](../contracts/Coinflip.sol) — Coinflip credit and shared BIGGEST pool.
- [`contracts/DegenerusRecordBounty.sol`](../contracts/DegenerusRecordBounty.sol) — five trophies.

High-value executable specifications:

- [`test/craps/Craps.t.sol`](../test/craps/Craps.t.sol) — craps wager rules.
- [`test/craps/CrapsSlip.t.sol`](../test/craps/CrapsSlip.t.sol) — run and settlement behavior.
- [`test/craps/CrapsHighWater.t.sol`](../test/craps/CrapsHighWater.t.sol) — scheduled high-water and
  custom isolation.
- [`test/craps/CrapsBattle.t.sol`](../test/craps/CrapsBattle.t.sol) — fields, entries, timing,
  ranking, and daily funding.
- [`test/craps/CrapsProgressive.t.sol`](../test/craps/CrapsProgressive.t.sol) — progressive funding
  and qualification.
- [`test/craps/CrapsHighRoller.t.sol`](../test/craps/CrapsHighRoller.t.sol) — high-lane accounting.
- [`test/craps/CrapsResolveBudget.t.sol`](../test/craps/CrapsResolveBudget.t.sol) — chunking and
  work-budget invariance.
- [`test/craps/CrapsPasses.t.sol`](../test/craps/CrapsPasses.t.sol) — passes and reservations.
- [`test/unit/Coinflip.test.js`](../test/unit/Coinflip.test.js) — Dice Run record claims.
- [`test/unit/DegenerusRecordBounty.test.js`](../test/unit/DegenerusRecordBounty.test.js) — fifth
  trophy behavior.

Useful quantitative companion:

- [`CRAPS-HIGH-WATER-SYSTEM-SIMULATION.md`](CRAPS-HIGH-WATER-SYSTEM-SIMULATION.md) — simulation
  methodology, population effects, jackpot frequency, and economic calibration.
