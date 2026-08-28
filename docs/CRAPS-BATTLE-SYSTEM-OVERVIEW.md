# Craps Battle System: Current Implementation

> Code snapshot reviewed 2026-08-27. This document describes the contracts as written in the
> working tree, especially [`Craps.sol`](../contracts/Craps.sol),
> [`CrapsBattle.sol`](../contracts/CrapsBattle.sol), and
> [`LootboxCraps.sol`](../contracts/LootboxCraps.sol). The deployed bytecode, if different, wins.

The system is a winner-take-all tournament built around a deterministic multi-shooter craps run.
Every entrant in a field receives the same bankroll, target, round size, bounty, settlement word,
and shooter sequence. Players choose a seven-chip board (or choose a blank board), but the protocol
adds random chips. Each individual run may return Coinflip credit, and the best-ranked run also
wins the field's bounty pot and any boost or donation.

```text
terms open -> entries and boards lock -> future RNG table is bound -> word arrives
    -> each board is scattered -> every run uses the shared shooters
    -> individual Goal/Bust result and raw remainder are computed
    -> individual Goal returns are credited; Bust returns are deleted
    -> main and high scoreboards finalize -> pots are credited
    -> bankroll action is booked for future scheduled boosts
```

## 1. Components and Assets

- `Craps` is pure, stateless settlement logic. It holds no money.
- `CrapsBattle` owns entry, storage, ranking, scheduled/custom fields, passes, protocol seats,
  boosts, high rollers, settlement batching, and payouts.
- `LootboxCraps` reads the protocol's daily and future lootbox RNG words and derives domain-separated
  craps seeds.
- Entry burns FLIP through the pinned FLIP contract.
- Every return and prize is issued as Coinflip stake credit. Nothing here returns liquid FLIP.
- The Vault majority owner controls the Vault's standing board and the custom-battle creator list.

## 2. The Craps Table

One board has ten legs, in this fixed order:

| Leg | Current behavior |
|---|---|
| Pass Line | Pays 1:1 profit on every come-out 7/11 and every point made; remains live until its first come-out 2/3/12 or the seven-out |
| Place 4 | Pays 2:1 profit per hit and stays; true odds |
| Place 5 | Pays 3:2 and stays; true odds |
| Place 6 | Pays 7:6 and stays; positive table edge |
| Place 8 | Pays 7:6 and stays; positive table edge |
| Place 9 | Pays 3:2 and stays; true odds |
| Place 10 | Pays 2:1 and stays; true odds |
| Hard 4 | Pays 7:1 on hard 4 and stays; dies on easy 4 or 7 |
| Hard 8 | Pays 9:1 on hard 8 and stays; dies on easy 8 or 7 |
| Don't Pass | One decision per shooter; a win returns principal plus **3:4 profit** |

Place and hardway hits credit winnings while the original stake remains exposed. A seven-out
therefore sweeps the still-live light-side stake. If a hand reaches its 512-roll safety cap without
a seven-out, every still-live stake is returned.

There are no Come, Don't Come, Field, proposition, pass-odds, Fire/ATS, Big 6/8, or other legs.

### Don't Pass exactly

Don't Pass is not a persistent pays-and-stays line. It receives one decision per shooter:

- Come-out 2 or 3: wins principal plus 3:4, then retires.
- Come-out 7 or 11: loses and retires.
- Come-out 12: pushes and remains live for the next come-out.
- A point is established: it wins on the seven-out or loses when the point is made, then retires.
- If the roll cap ends the hand while it is still unresolved, its principal is returned.

Its exact win probability is `949 / 1925`. At 3:4 profit, its intrinsic one-decision edge is:

```text
1 - (949 / 1925) x (1 + 3/4) = 13.727272...%
```

That is only the wager-level edge. A battle run replays the board over many shooters and then
deletes every positive Bust remainder, so its run-level effective loss is much larger.

### Dice

For a run seed `seed`, shooter `i` uses `keccak256(seed, i)`. Within a shooter, roll `j` is
`keccak256(handSeed, j)`; two 32-bit slices become the two dice modulo six plus one. A shooter ends
on a point-phase seven-out or at 512 rolls.

All entrants in the same battle window use the same shooter seed because it is derived from the
settlement word and the window's bound slot. This includes ordinary window entries, whole-day
tickets, reserved pass seats, and protocol seats. Different windows use different bound slots even
if they happen to bind the same table index.

The shared shooter is strategically important: different boards are correlated responses to the
same dice, not independent casino trials.

## 3. Player Boards and Random Scatter

A field fixes a ten-chip round. An entrant has two board modes:

1. Submit exactly seven selected chip counts; settlement scatters the remaining three.
2. Submit all zeroes; settlement scatters all ten.

For a selected board:

- exactly seven chips must be named;
- no submitted spot may hold more than **four** chips;
- submitted Pass and Don't Pass cannot both be nonzero; and
- the counts describe proportions, not FLIP amounts. Every window scales them to its chip size.

The four-chip cap applies only to the submitted seven. Scatter may put the resolved board above
four on a spot, and may add the opposite line after a player selected Pass or Don't Pass. That is
allowed because it is the draw, not a player choosing both sides.

Scatter is keyed by the settlement word and owner. Players at the same table therefore share the
shooters but normally receive different random additions. A blank board receives ten independent
leg draws; a selected board receives three.

Boards are visible on-chain and may be amended by their owner until the relevant entry closes.
Amendment changes only the chip slice and refreshes frozen standing; it cannot change the seat,
bankroll, goal, bounty, or high status.

## 4. The Multi-Shooter Run

Every entrant starts with the field's bankroll and repeats the resolved ten-chip board over
successive shooters until Goal or Bust.

### Mandatory escalator

The board multiplier is:

```text
hands 0-4:    1x
hands 5-9:    2x
hands 10-14:  4x
hands 15-19:  8x
...
cap:          65,535x
```

The multiplier is linear: the engine runs the base board once for that shooter and scales the
stake and return by the mandatory multiplier.

### Affordability and survival flip

Before a shooter whose required round is `need`:

- `bankroll < need / 2`: immediate Bust with the positive remainder intact.
- `need / 2 <= bankroll < need`: a player-specific fair survival flip runs.
  - Win: bankroll doubles and the shooter is played.
  - Loss: bankroll becomes zero and the run Busts.
- `bankroll >= need`: the shooter is played normally.

The survival flip is keyed by table seed, hand number, and owner. Players share dice but do not
share the survival result.

So, to answer the common edge case precisely: **a Bust caused by losing the survival flip has a
zero remainder**. An affordability Bust, hand-cap Bust, or roll-budget Bust can have a positive
remainder.

### The shooter profit boost

On a **protocol-scheduled** window — never a custom battle — each shooter may carry house money
added to what the board actually WON that hand. Eligibility is drawn per player and per shooter
from a domain of its own:

```text
eligible = keccak256(SHOOTER_BOOST_TAG, settlementSeed, player, handOrdinal) % 100 < chance
boost    = floor(baseHandEligibleProfit x pct / 100)
```

The schedule is fixed — there is no jitter — and depends only on the ticket class and the Goal:

| Stored ticket | Eligible shooters | Goal 5x | Goal 10x | Goal 50x |
|---|---:|---:|---:|---:|
| Blank/random | 15% | +25% | +30% | +40% |
| Picked | 5% | +6% | +20% | +35% |

The class comes from the **stored, pre-scatter** chip word: a blank ticket stays blank however the
dice fill its board. The crossover is deliberate — picking is worth more at 5x and 10x, where a
board can shorten a run, and leaving the ten chips to the dice is worth more at 50x.

**Eligible profit is winnings only.** Pass profit, Place 4/5/6/8/9/10 profit, Hard 4 and Hard 8
profit, and only the 3:4 portion of a winning Don't Pass. It excludes every wager principal, the
live-stake refunds a roll-cap truncation pays, the stake a winning Don't Pass hands back,
survival-flip doubling, pre-existing bankroll, and every post-run credit.

The percentage is floored **once**, on the base hand, before the escalating multiple scales the
round — so a high seat buys copies of one boosted run rather than a fresh schedule per copy. The
boosted return lands in the bankroll before the next Goal, hard-bound and affordability check, so
a boost may cross Goal a shooter early, buy a round the run could not otherwise afford, turn a
Bust into a Goal, and change battle rank. That is intended.

Each player's schedule is their own over the field's shared shooters, and none of it is knowable
while entry or amendment is open: the settlement seed comes from a future table word.

### Stops and bounds

At the top of each loop, Goal is checked first. A bankroll already at or above target is a Goal.
Otherwise the run Busts if it has reached 256 shooters or its 4,096-roll slip budget. The roll
budget is checked only between shooters, so no shooter is cut in half.

There is no separate `Cap` outcome: execution bounds are Busts.

## 5. Individual Settlement, Bust Deletion, and Rounding

The pure engine returns a raw ending bankroll for both Goal and Bust. The battle wrapper then:

- floors a nonzero result of at most 1,000 FLIP to whole FLIP;
- above 1,000 FLIP, probabilistically rounds to a 100-FLIP multiple using committed entropy; and
- overrides the payable amount to zero for every Bust.

The stochastic hundreds rounding preserves expectation apart from sub-FLIP dust. A high-roller
seat is rounded once as a single run, then multiplied by the high multiple.

The distinction between `won` and `paid` is deliberate:

- `won` is raw ending bankroll and remains available to ranking even on Bust.
- `paid` is actual Coinflip credit after rounding and Bust deletion.

No winner receives another player's deleted Bust remainder. It is neither a bounty nor boost
funding transfer; it simply is not recreated as Coinflip credit.

## 6. Battle Ranking

Every field ranks, including a zero-bounty custom field. Main and contested high scoreboards use
the same unscaled score:

1. Every Goal beats every Bust.
2. Among Goals, fewer shooters wins.
3. Among Busts, more shooters wins.
4. If the stop and shooter count tie, larger **raw ending bankroll floored to whole FLIP** wins.
5. If still tied, larger entry-frozen standing wins.
6. If exactly tied, a deterministic hash of the table word and seat gives a uniform total order.

Therefore the remainder is not only a win tiebreaker. It breaks ties among Busts too—but only
after Bust longevity. A 12-hand Bust with zero remainder beats an 11-hand Bust with any remainder;
between two 12-hand Busts, the larger remainder wins.

High multiples never improve rank. A high roller buys copies of one unscaled run, not a better
score. A high seat can win both the main field and the high sideboard.

## 7. Entry Cost and Main Pot

An ordinary seat burns:

```text
bankroll + bounty
```

A high seat at multiplier `H` burns:

```text
H x (bankroll + bounty)
```

Board choice does not change the burn. The field's bankroll, goal, ten-chip round, bounty, standing
bar, high multiple, and multi-entry flag are shared terms.

Every entrant contributes one bounty to the main winner. The main payment is:

```text
entrants x bounty + adjusted scheduled boost + exact donations
```

All Bust remainders stay outside this pot. The winner may itself be a Bust if nobody reaches Goal.

## 8. Randomness, Closing, and Settlement

Scheduled terms come from the already committed daily word. That word does **not** settle the
battle. When a window stops accepting entries, anyone may call `armBonusWindow`; it binds the slot
to `_currentIndex() + 1`, a lootbox table whose word does not yet exist. Custom battles use the
same pattern through `closeBattle` after their deadline.

The future settlement word drives domain-separated values for:

- shared shooter dice;
- owner-specific scatter;
- owner-specific survival flips;
- individual payout rounding;
- exact-score tie order; and
- the main/high boost rung.

Arming and custom closing are permissionless. Their RNG request is fail-open: failure to request
does not undo the bound index; that table can fill through the lootbox lane later.

Once the word exists, anyone calls `resolveSlot(slot, gasBudget)` repeatedly. A dense cursor makes
settlement resumable. Each batch computes individual credits, updates both scoreboards, and batches
nonzero Coinflip credits. The call that resolves the final entrant finalizes and pays the pots.

Scheduled action is booked to the protocol day the window **played**, regardless of delayed
settlement. Custom-battle action is booked to the current protocol day when it settles.

### The keeper leg

Both jobs stay permissionless on the table — that path is the unstick valve and nothing about it
changed. What is new is that the protocol's own crank takes them too, so a window is never left
hanging on nobody's initiative.

`mineFlip()`'s **last** leg drives the table's own **scheduled cursor** (`keepScheduled`): a
persistent pointer naming the oldest scheduled slot still owing work. Each crank does the next
piece of that work — cross a spent slot, sweep a lapsed day's reservations back to pass credits,
shut a window whose close has passed, or settle a batch of an armed field within the gas
allowance the box legs left. The cursor cannot pass a slot that still owes anything, so nothing
scheduled is forgotten: the old `openSlot - 1` probe abandoned any field that outlasted one
budget — the daily event above all, armed in its fifteen-minute lead and worded later. External
help through the still-permissionless `armBonusWindow`/`resolveSlot` doors is detected as done
work and crossed, never wedged on. What the cursor will not do is wait on the impossible: a live
window, a wordless armed field, and an unopened day all stop it with no progress claimed and no
bounty paid.

It pays a **flat 1 FLIP** for either, as `MinerBounty` kind 4 — the same shape and figure
`degeneretteResolve` pays the protocol's other permissionless batch resolver. The credit is
coinflip stake, not liquid FLIP, like every other crank bounty.

**Almost all of it lives in the afking module, not the table.** `CrapsBattle`'s EIP-170 margin is
tight, so the only reader it gained for the crank is a nine-byte `bonusCursorOf`. A purpose-built
`crapsKeep()` on the table was measured at 146 bytes *over* the limit and dropped; the window
ladder the crank uses to find its work is restated in the module and held to the table's own by a
drift gate that walks a full day of timestamps.

Four properties make the leg safe rather than merely convenient:

- **It never shares a call with an advance.** It lives in the crank's else branch, and only on a
  call that opened no lootbox.
- **It is sized out of the box legs' own budget, and it is charged rather than counted.** The
  second argument to `resolveSlot` is a WORK BUDGET in the protocol's own walk units (~4.7k gas
  each), not a seat count: whatever the afking walk and human sweep left of `OPEN_WEIGHT_BUDGET`,
  passed through as-is less a 32-unit router reserve — no gas conversion anywhere. An untouched
  budget hands the table **1,888 units**.

  Each settled seat then charges its own OUTCOME, deterministically:
  `_SEAT_UNITS(7) + rolls/6 + (paid ? _CREDIT_UNITS(6) : 0)` — the engine already reports the
  roll count, and rolls are what a seat's cost actually varies by (two orders of magnitude
  between a three-roll bust and a four-hundred-roll run). The walk stops on the first seat whose
  charge crosses the budget, so a head count's twin failures — underpricing the tail, overpricing
  the mean — are both gone, and the stopping point is a pure function of chain state: the same
  batch boundary on every node, under every gas schedule, with no `gasleft()` anywhere in it.
  Each weight rounds its measured gas UP (seat plumbing ~28k, dice 578-699/roll, a cold credit
  25,910), so the charge is conservative at every point.

  The old form also had an arithmetic hole: it divided the spend into seats first, so a box walk
  that consumed the whole 1,920-unit budget still left `80 - 1920/27 = 9` seats stacked on top of
  a full-budget call. The remainder now saturates at zero.

  The hard bound is the budgeted work at the units' own conservative gas ceiling plus one whole
  seat of overshoot: ~1,888 x 4.7k plus the engine's 2.25M regression ceiling and the router
  tail — around **11.3M**, far below the 16.7M that hard-fails, and the measured typical crank
  sits near 9M as before.
- **It pays for work, not for calling.** An arm reverts when there is nothing to arm, and
  `resolveSlot` returns *silently* on a field that is already finished — so the cursor is read
  either side and the bounty is gated on it actually moving. An idle table pays nothing.
- **The arm is available exactly when the RNG request is.** `armBonusWindow` asks the lootbox lane
  fail-open, so a locked lane or an in-flight request still shuts the window on the clock; a window
  shut this way is walked by a later crank, since its word cannot exist in the same block.

A field deeper than one batch settles over as many cranks as it needs — the slot's cursor is what
carries it between them.

## 9. Scheduled Daily Battles

The Game opens all seven windows once the day's daily word is present. The protocol day begins at
22:57 UTC. Current close schedule:

| Period | Close | Format |
|---:|---|---|
| 0 | 23:20 UTC | opener; routine tier drawn flat 1/3 each |
| 1 | 03:00 UTC | routine |
| 2 | 07:00 UTC | routine |
| 3 | 11:00 UTC | routine |
| 4 | 15:00 UTC | routine |
| 5 | 19:00 UTC | routine |
| 6 | 22:42 UTC | event, 15 minutes before turnover |

### Routine terms

The opener draws the three tiers uniformly. Periods 1-5 draw them 70% / 20% / 10%:

| Tier | Bankroll | Possible bounty |
|---|---:|---|
| Small | 300 | 100 / 200 / 300 |
| Medium | 1,200 | 300 / 800 / 1,200 |
| Large | 3,000 | 1,000 / 1,500 / 3,000 |

### Event terms

The event bankroll is 1,500-15,000 in 1,500 steps, except a 5% 30,000 tail and 2% 60,000 tail.
Its bounty is 25%-50% of bankroll in five-point steps, floored to a 100-FLIP granule.

### Terms common to all seven

- Bankroll depth is 2, 5, or 10 rounds.
- Goal is 5x, 10x, or 50x bankroll.
- Round size is a whole ten-chip amount derived from bankroll and depth.
- The scheduled standing bar is zero; standing affects boost payout and late ranking only.
- The day high multiple is 10x on 90% of days and 100x on 10%.

One million simulated schedules averaged about 15,633 bankroll action, 7,184 bounty, and 22,816
total face cost per ordinary whole-day seat. The fixed future-day prices are 25,000 ordinary and
450,000 high.

## 10. Ways to Enter a Scheduled Day

### Packed board ABI

The production player doors take `chips` as one `uint32`, not as a ten-word tuple. Bits are ten
three-bit counts in board order: pass line at 0, place 4/5/6/8/9/10 at 3/6/9/12/15/18, hard 4/8
at 21/24, and don't pass at 27. Bits 30-31 are zero. The affected signatures are
`enterBattle(uint64,uint32,uint16)`, `enterBonusBattle(uint256,uint32,uint16)`,
`enterBonusDay(uint32,uint16)`, and `amendSlip(uint256,uint32)`. The Vault's
`crapsEnterBattle(uint64,uint32,uint16)` and `crapsAmendSlip(uint256,uint32)` forward the same word.

### One window

`enterBonusBattle(period, chips, multiple)` joins one still-open current-day window. `multiple=1`
is ordinary; any other value must exactly equal that day's 10x/100x high multiple.

**Chips go in PACKED**, at every door — `enterBattle`, `enterBonusBattle`, `enterBonusDay` and
`amendSlip` all take a `uint32`: three bits a leg, board order, don't pass at bit 27. It is the
same word `setVaultBoard` has always taken, the same word a bet is stored as, and the same word
`CrapsSlipPlaced` and `CrapsSlipAmended` emit. Decoding a ten-field struct at four separate doors
cost 1,931 bytes of EIP-170 to arrive at that word anyway.

### Whole day at the opener

During period 0, `enterBonusDay` writes one day ticket that joins all seven fields. It burns the
sum of all seven entry costs, freezes one standing score, and awards quest-streak days: **one for
an ordinary day ticket and five for a high one**, since a high seat buys the same seven windows at
the day's own multiple. Either way it is one credit per address per day — the `_daySeated` latch
that refuses a second day seat is what bounds it.

A day pass reserved in advance (`buyFutureCrapsDays`, `applyCrapsPasses`, or a lootbox award)
writes its seat through `_reserveDay` and awards **no** streak; only the current-day door does.

### Remaining-day bundle

After period 0, `enterBonusDay` places separate slips into every remaining open window the caller
has not already joined. Already armed or already occupied windows are skipped. The bundle is
marked so its amendments lock together when its first included window closes.

### One-seat rules

Scheduled windows do not allow multi-entry. A day ticket or future reservation blocks another
seat by that address in every window of the day. A caller also cannot buy a day ticket after first
entering one of its windows separately.

### Upgrading a normal day ticket, window by window

`upgradeDayWindows(day, periodMask)` upgrades chosen windows of the caller's own whole-day ticket
to the day's high-roller lane. The ticket already supplies one copy of each window's run, so the
upgrade burns only the missing `(H - 1) x (bankroll + bounty)` per selected window — after which
that window settles exactly as a native high seat: `H` copies of the one run (same board, dice,
and rounding), one main-scoreboard entry, one bounty in the main pot, `H - 1` in the lane, and
`H x bankroll` booked as both total and high action.

- Bits 0..6 of the mask name periods 0..6; anything above reverts.
- Every newly selected window must still be joinable — open, unarmed, and its period still to
  come. A window closed by the clock is locked even before anyone arms it. One locked selection
  reverts the whole batch; nothing burns.
- Bits already high are ignored, never recharged; a mask with nothing new reverts
  `NothingToUpgrade`.
- Only the ticket's holder can reach it (the seat lookup is keyed to the caller), the day must be
  open (so a banked pass or an unworded future reservation has no calculable terms to upgrade at),
  and no quest streak, downgrade, transfer, or refund exists.
- `CrapsDayWindowsUpgraded(player, day, upgradedMask, burned)` reports exactly the new bits and
  the exact delta burned.

Internally the day-ticket word (`_dayTickets`) holds the total in its low 32 bits and one
high-roller count per period above it, 32 bits each; a whole-day high entry bumps all seven, an
upgrade bumps only its own, and each window folds in its own period's count when it arms. The bet
word carries seven high flags (bits 217..223, one per period); a whole-day high ticket sets all
seven, and window-local slips keep the single bit-217 flag. `_daySeated` stores the holder's seat
number — still the nonzero one-seat latch everywhere it is read, and what lets the upgrade find
the caller's ticket without a walk.

## 11. Day Passes and Future Seats

Pass awards are seats, not coupons requiring later redemption.

Credits arrive from four sources, all through the table's `OnlyGame` credit doors:

- The regular lootbox's day-pass conversion (`deliverPasses`, which first tries to seat
  tomorrow and banks the rest).
- A whale-pass purchase below level 10: one normal pass credit per pass bought
  (`creditPasses`; the purchase's 10% lootbox is untouched).
- A deity-pass purchase: one high-roller credit below level 10, funded by halving that
  purchase's lootbox to 5% of price; one normal credit from level 10 on, with the lootbox
  at the full 10%.
- A presale box's FLIP branch: a committed coin toss pays half the boxes their roll as
  coinflip credit untouched, and denominates the other half's WHOLE roll into passes at
  the regular box units (22,800-FLIP normal, switching wholly to 19x high-roller above
  twenty normal units, the fraction Bernoulli-rounded), capped at twelve high passes per
  box with the rest of the roll staying coinflip credit; a sub-pass roll whose fraction
  loses pays the box's WWXRP dud.

- `deliverPasses` first tries to reserve tomorrow immediately, preferring a high pass if both
  denominations arrived. Leftovers become banked normal/high credits.
- `applyCrapsPasses(startDay, count, high, chips)` spends banked credits and writes whole-day
  seats for consecutive strictly future days — on the packed board `chips` names, or blank for
  zero. The board is held to the live doors' rules (seven chips or none, four to a leg, one side
  of the line), vetted before anything is debited, and the same initial slip serves every day of
  the run.
- `buyFutureCrapsDays(startDay, count, high, chips)` burns the fixed price now and writes the
  same seats, same board rules.
- Each range is all-or-nothing. An occupied, worded, past/current, or overflowing day reverts the
  entire run.
- A high reservation automatically uses the future day's eventual 10x/100x draw; no multiplier is
  stored early.
- The seat is already live when the day opens. There is no redemption function and no expiry due
  to failing to return.
- The early seat starts on the board its reservation named, or blank. Its owner may amend any
  single reserved day at any time until that day's first window closes — days ahead of the clock
  included — which also refreshes standing. A lootbox-delivered automatic seat always starts
  blank.

## 12. High-Roller Lane

Every high seat joins the ordinary main scoreboard and a second high-only scoreboard. For day
tickets the lane is per window: a whole-day high ticket rides all seven lanes, an upgraded normal
ticket only the windows its mask names, and each window reads its own period's flag and count.

### No high seats

No high prize is formed and no high boost is paid.

### Exactly one high seat

There is no high race. The seat's extra `(H - 1)` bounties and standing-adjusted high boost ride
its own run pro rata:

```text
ride = floor(individual paid / bankroll x (extra bounties + adjusted high boost))
```

A Bust has zero individual paid and therefore receives zero rider. This sole-lane capital is
booked as high action because it was actually at risk.

### Two or more high seats

The best high score receives:

```text
high heads x (H - 1) x bounty + standing-adjusted high boost
```

The player-funded extra bounties pay whole; only the protocol boost is standing-rationed. The same
boost rung drives main and high. A high player can win both pots, and if all high players Bust the
best-ranked Bust wins the lane.

## 13. Boost Budget and Lottery

Let each of the prior seven playing-day books contain ordinary bankroll action `A_R(d)` and high
action `A_H(d)`. With integer floors omitted for readability:

```text
E_R = average(A_R x 1200 / 10000)
E_H = average(A_H x 1200 / 10000)

fromHighToMain = E_H x 2/5

rawMainBudget = 50,000 + E_R + fromHighToMain
highBudget    = E_H - fromHighToMain
```

At steady action:

```text
rawMainBudget = 50,000 + 0.120 A_R + 0.048 A_H
highBudget    = 0.072 A_H
total linear budget = 0.12 (A_R + A_H)
```

The 50,000 is **additive, not a floor**: a day with a busy week behind it is paid for that week on
top of the base, never instead of it. The base rides the main lane alone — the high lane is funded
only by action high seats actually put through it.

### The main split

The raw main figure is **halved** the moment the day opens:

```text
ladderBudget            = floor(rawMainBudget / 2)
progressiveContribution = rawMainBudget - ladderBudget
```

The ladder half is what the day's seven windows share and what every quote — before the day opens
and after — advertises. The other half is banked in one global progressive (section 13a); the odd
wei goes there, so the two always sum back to the raw figure exactly. **The high budget is not
split.** Only its standing forfeitures ever leave the lane.

Both halves are emission. A wei banked in the progressive is a liability the day it lands there,
and its later award releases that liability rather than issuing again.

At a conservative 16% whole-run engine take and ~15,600 FLIP of bankroll action per ordinary daily
ticket, each ticket leaves about 624 FLIP behind, so a day nets to zero around **eighty ordinary
daily tickets** and issues below that. That is an expectation, not a cap: the ladder pays a window
up to 100x its share, and the funding window lags a week in both directions. It is also an
*edge-dependent* figure rather than a universal head count — see section 13a.

The event receives half of the LADDER. The other half of it is split among the six routine
windows with 1x/2x/4x weights based on their drawn tiers.

Each window then draws one rung, expressed here as the paid multiple of its share:

| Probability | Multiple |
|---:|---:|
| 76.8% | 0.25x |
| 20.8% | 1x |
| 2.0% | 10x |
| 0.4% | 100x |

The expected multiplier is exactly 1x. A budget is an expected daily allocation, not a daily cap.

### What counts as action

- Ordinary seat: one bankroll, not its bounty.
- Contested high seat: `H x bankroll`, classified as high.
- Sole high seat: `H x bankroll + (H - 1) x bounty`, because the extra bounty rides the run.
- Cash, pass, reserved, and protocol seats book the same nominal action once they play.
- Protocol boost is not recycled into new action.

### Standing ration and boost rounding

Scheduled house boost is rationed using standing frozen on the seat:

- score 0: none;
- score 1-10: `1 / (12 - score)`;
- score 11 or more: full boost.

Only the protocol boost is rationed. It is counted in 100-FLIP granules and, above 4,000 FLIP,
rounded to the nearest 1,000.

Rationed boost is **not** left unminted. Every wei of protocol-funded value a standing score denies
is banked in the progressive instead:

```text
standingRollover = fullStandingProtocolAmount - actualProtocolAmount
```

compared at the same granule and rounding stage the payment lands on, so `actual credit + rollover`
is the full-standing award exactly. This applies to the main ladder award, a contested high-lane
boost, and the boost capital offered to a sole high rider — where the denied part is banked *before*
the run is consulted, so only the admitted capital rides. At full standing every one of these is
zero.

Nothing else is a forfeiture. Player-funded bounties, principal, run losses, deleted Bust
remainders, ladder under-realisation and rounding dust all stay exactly where they are.

## 13a. The Progressive

**One pool, shared by all nine scheduled depth/Goal formats and by every day.** It is funded once
when a protocol day opens — half the day's raw main allocation — and topped up by the standing
forfeitures above. Custom battles neither fund it nor draw on it.

### Qualification

There is **no separate draw**. A progressive award is decided entirely by the already-finalized
main battle:

1. the battle is a protocol-scheduled main battle;
2. the recipient is the final main battle winner the existing comparator named — never a runner-up;
3. that winner's stop is `Goal` — a Bust never qualifies, however far it ran;
4. its cumulative `totalRolls` is compared against the cutoffs for that window's bankroll depth and
   Goal multiple; and
5. rare is tested first and **overrides** — a field never pays both rungs.

Cutoffs are inclusive cumulative dice-roll counts:

| Bankroll depth | Goal 5x common / rare | Goal 10x common / rare | Goal 50x common / rare |
|---:|---:|---:|---:|
| 2x | 150 / 185 | 205 / 245 | 340 / 395 |
| 5x | 215 / 260 | 275 / 320 | 405 / 455 |
| 10x | 265 / 315 | 325 / 375 | 455 / 500 |

The battle's dice are shared: shooter `n` begins and ends on the same roll for every entrant still
in it, so this criterion adds no per-player roll and no jackpot RNG — it measures the shared
cumulative roll prefix at which the winning ticket stopped. The deliberate consequence is that a
very long final shooter can push a winning ticket over a cutoff on relatively few shooters, and
many short shooters need not qualify merely because their count is high.

**Rolls do not rank.** The comparator remains Goal before Bust, fewer hands for Goals, more hands
for Busts, then the existing tiebreakers. The roll count is qualification metadata carried beside
the winning seat on the scoreboard, and it moves only when the lead does. A Goal is tested between
shooters, so the qualifying count includes the winner's complete final shooter. The engine's
512-roll shooter cap and 4,096-roll slip budget give a hard maximum of 4,607 cumulative rolls.

### Award

```text
if Goal and rolls >= rareCutoff:    candidate = floor(pool / 2)
elif Goal and rolls >= commonCutoff: candidate = floor(pool / 10)
else:                                candidate = 0

paid  = standingShare(candidate, winnerStanding)
pool -= paid
```

The candidate is already in the pool, so the standing curve applies to it directly and **only the
credit is deducted** — what the curve denies never left and is not added back. At full standing
`paid == candidate`.

Multiple qualifying windows consume only their actual credits, sequentially, and each later award
uses the then-current balance. No day's contribution is reserved or snapshotted per window. A
high-multiple seat that wins the main battle receives one award; the multiple does not scale it,
and winning only the separate high lane does not qualify at all.

Payment goes through the same Coinflip-credit rail as the battle award, as a separate credit, after
the pool has already been reduced. A pool too small to pay a rung produces a zero award and no
external call.

### Reading it

- `progressivePool()` — the live balance, and the second reader production ships. It is the one
  figure of the system that is not a pure function of published inputs.
- `CrapsProgressiveFunded(day, contribution, balance)` — once per opened day.
- `CrapsProgressivePaid(betId, battleKey, player, rare, rolls, candidate, paid, retained, balance)`.
- `CrapsProgressiveRolled(battleKey, source, amount, balance)` — source 1 main ladder, 2 contested
  high lane, 3 sole high rider.
- `CrapsBattleFinalized` and the `Battle` view both carry `winningRolls` beside `winningHands`.

### What it is worth

Measured on the committed `mixed_40_cohort` scenario — forty daily tickets, twenty blank/random and
five each of fixed Place 4/10, mixed, Pass-heavy and 3:4 Don't-Pass-heavy — over 500 independent
730-day worlds:

| Quantity | Mean per day |
|---|---:|
| Bankroll action | 625,626 FLIP |
| Post-shooter engine retention | 159,440 FLIP (25.48% of action) |
| Immediate ladder paid | 62,527 FLIP |
| Progressive contribution | 62,539 FLIP |
| Total emission, counting stored pool value | 125,066 FLIP (19.99%) |
| Net | **34,374 FLIP burn (5.49%)** |

The pool reached a day-730 mean of **19.28M FLIP** (median 19.12M, 10th-90th 13.82M-24.97M), paying
about **9.6 common and 0.15 rare awards a year**. A 100-world ten-year extension ended at a mean of
**21.40M**, so the pool approaches a roughly 21-million level under this cohort rather than growing
without bound.

That equilibrium is a property of a field that can **claim**, not of the mechanism. A scoreless
winner is credited nothing, so its ladder award rolls entirely into the pool and its progressive
candidate is entirely retained. A table whose only player is score-zero therefore banks its whole
subsidy and pays out none of it — measured at 5.18 **billion** FLIP after 100,000 simulated days.
Nothing is minted there and the whole figure is a liability against a wallet that cannot collect
it, but the bounded quantity is emission, not the balance.

The participation equilibrium is **edge-dependent, not a universal player count**. At ~15,615
bankroll action per complete daily ticket and the 50,000 base:

| Weighted post-shooter edge | Approximate zero-EV daily tickets |
|---:|---:|
| 16.00% efficient-field policy assumption | 80 |
| 17.85% all blank/random | 55 |
| 18.37% fixed Place 4/10 | 50 |
| 25.5% modeled heterogeneous field | 24 |

This low-participation emission is intended; there is deliberately no hard issuance cap.

## 14. Donations

Anyone may donate 100-FLIP granules to a scheduled or custom battle while it is still joinable.
The burn is final; the donor receives no seat or refund.

Current payout keeps donations separate from protocol subsidy:

- donations are paid exactly in their 100-FLIP granules;
- they are not activity-rationed;
- they are not passed through boost rounding; and
- they go to the main winner on top of bounties and any scheduled boost.

Custom battles have no protocol boost, so their main pot is entrant bounties plus donations.

## 15. Custom Battles

The Vault majority owner always may create them and may grant/revoke other creator addresses.
Creation fixes:

| Term | Current legal range |
|---|---|
| Ten-chip round (`played`) | positive whole-FLIP multiple of 10, at most `uint24.max` |
| Bankroll depth | 1-25 rounds, total bankroll at least 300 FLIP |
| Goal | 5x-1,000x bankroll |
| Bounty | 0 up to bankroll, in 100-FLIP units |
| Minimum standing | 0-4,095 |
| Close | future timestamp |
| Multi-entry | creator-selected boolean |
| High multiple | 0 (off) or 2-256; 1 is invalid |

Anyone meeting the public terms may join. Entry, board validation, high behavior, future RNG
binding, settlement, ranking, donations, and payment otherwise reuse the scheduled machinery.
Custom fields receive no scheduled main or high boost.

The `uint24.max` round cap is deliberate: a blank board may scatter all ten chips onto one leg,
so the entire round must fit the engine's `uint24` per-leg type.

## 16. Protocol Day Seats and the Vault

At day opening, sDGNRS and the Vault are handled as whole-day seats.

- An already reserved future seat is left alone.
- The Vault board is read before funding. It may be blank, a legal seven-chip/max-four board, or
  the OFF sentinel. OFF prevents a new automatic seat but cannot erase a seat already reserved.
- The current funding order is **ordinary FLIP burn first**, then a banked high pass, then a banked
  normal pass if the burn failed.
- A high pass makes the protocol body a high roller at the day's exact draw. A successful FLIP
  fallback is always an ordinary seat.

Thus the Vault can join the high lane through a pre-reserved high day or a high pass used after its
ordinary burn fails. Merely holding a high credit does not force high entry while its ordinary
FLIP burn succeeds.

The Vault board is a genuine strategic choice. It competes for player-funded bounties using the
same ranking as players; it is not neutral liquidity.

## 17. IDs, Events, and Views

- Scheduled window slot: `day x 8 + period + 1`.
- Reserved whole-day slot: `day x 8` (remainder zero).
- Custom slots begin at `2^40`.
- Bet ID: `(storage slot << 64) | dense seat`.

A whole-day ticket is one stored bet reused in all seven window fields, so its bet ID can appear in
seven `CrapsBetSettled` events.

Important event distinctions:

- `CrapsBetSettled.won`: raw run bankroll (scaled for high); `paid`: actual individual credit,
  including a sole-high rider.
- `CrapsBattleFinalized.pot`: the raw advertised bounty/boost/donation figure before activity
  ration and boost rounding.
- `CrapsBattlePaid.amount`: actual main-pot credit.
- `CrapsHighRollerPaid`: sole rider or contested-lane payment, distinguished by
  `bankrollRider`.
- `CrapsDayWindowsUpgraded(player, day, upgradedMask, burned)`: a day ticket's newly upgraded
  period bits and the exact delta burned for them. The ticket's `CrapsSlipPlaced` predates its
  upgrades, so this stream is what carries a day seat's high-lane membership per window.
- `CrapsBonusOpened.seed`: maximum 100x scheduled quote, not a guaranteed payment.
- `CrapsHighRollerDayOpened.mainBoostBudget`: the **ladder half** the day's seven windows share.
  Its other half is in `CrapsProgressiveFunded`, and the two sum to the raw allocation.
- `CrapsBattleFinalized.winningRolls`: the winner's cumulative dice rolls. It decides nothing about
  the rank — `winningStop` then `winningHands` do — and is carried so a reader can check the
  progressive's cutoffs without replaying the run.
- `CrapsProgressiveFunded` / `CrapsProgressivePaid` / `CrapsProgressiveRolled`: see section 13a.
  Together with `CrapsHighRollerDayOpened` they reconstruct the pool from genesis.
- `CrapsBattlePaid.amount` is the **pot and only the pot**. A progressive award riding the same
  finalization is a separate credit and a separate log.

`previewSettlement` returns the individual scaled run and includes a sole-high rider. It does not
include the main pot, a contested high pot, or a progressive award — the progressive is a field
award decided at finalization, not part of what a single slip is worth.

Production views: `bonusCursorOf(slot)` and `progressivePool()`. Everything else is rebuilt from
the events.

## 18. Strategic and Economic Consequences

- Bust deletion is a large component of effective house edge even on true-odds selected boards.
- Raw Bust remainder affects ranking but never becomes an individual payment.
- Shared shooters reward boards that are contrarian to the visible field; board EV alone does not
  determine tournament EV.
- Public, amendable boards create a reactive close-time game.
- 3:4 makes Don't Pass expensive, but its anti-light correlation remains strategically useful.
  When dark boards become common, Pass and true-odds Place boards counter them.
- The funding rule is an **additive base plus a linear rate**, not a floor: `50,000 FLIP/day +
  12% of trailing average daily action`. There is no `max()` anywhere in it, and the older `/8`,
  `/36` and 15,000-floor drafts are gone.
- Half of that allocation never reaches a window. The 50,000 base therefore buys a 25,000/day
  ladder and a 25,000/day progressive contribution, and the thin-field emission is the whole
  50,000 — the split changes when players see the money, not how much is created.
- The progressive makes the long-run reward distribution far heavier-tailed than the ladder alone:
  about ten awards a year across a forty-ticket field, one of them rare roughly every seven years,
  against a pool that settles near 21M FLIP. It rewards surviving a long shared shooter prefix,
  which is a different thing from winning quickly.
- Pass-funded or protocol seats still book nominal action and can win returns and pots; their
  upstream funding provenance is outside this contract's battle ledger.

Quantitative results, including the 3:4 strategic sweep and setting-by-setting engine edges, are
in [`CRAPS-SYSTEM-SIMULATION.md`](CRAPS-SYSTEM-SIMULATION.md).

## 19. Source-of-Truth Checklist

When inspecting a live result, reconstruct it in this order:

1. Decode the slot and shared terms.
2. Confirm entry closed and find its bound table index and word.
3. Decode the submitted board; apply owner-keyed scatter.
4. Derive the window-keyed shared shooter stream and owner-keyed survival flips.
5. Run the escalator to Goal or Bust, retaining raw bankroll even on Bust.
6. Apply individual rounding, then delete Bust payment.
7. Build the composite rank from stop, hands, raw whole-FLIP remainder, and frozen standing.
8. Resolve the main and any high scoreboard; apply the deterministic final tie hash.
9. Separate bounties, scheduled boost, and donation; ration/round only scheduled boost, and bank
   what the ration denied in the progressive.
10. If the winner reached Goal, compare its cumulative rolls against its format's cutoffs; test
    rare first, take the rung off the live pool, and deduct only what standing actually credits.
11. Credit Coinflip stake and book bankroll action to the correct day. Progressive funding,
    rollovers and awards never enter that action book.
