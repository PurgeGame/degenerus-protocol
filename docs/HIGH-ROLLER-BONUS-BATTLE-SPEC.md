# High-Roller Mode for Craps Bonus Battles — Contract Specification

**Status:** Ready for contract implementation
**Created:** 2026-08-26
**Primary target:** contracts/CrapsBattle.sol
**Tests:** test/craps/CrapsBattle.t.sol, test/craps/CrapsGas.t.sol, test/craps/CrapsEconomics.t.sol
**Requirements:** 11 locked
**Ambiguity score:** 0.05

## 1. Goal

Add one optional high-roller lane to every Craps battle without duplicating the run, changing
the odds, multiplying either protocol boost by H, or adding a second settlement walk. When
exactly one high roller enters, the otherwise uncontested high-roller bounty portion rides that
player's existing run as additional at-risk bankroll instead of being refunded.

Separate settled high-roller bankroll action from regular action when drawing future Bonus
Battle budgets. Of the modeled burn attributed to high rollers, recycle 30% into a competitive
high-roller boost and 20% into the main boost; retain the other 50%. The high-roller boost has no
minimum floor and is available whenever at least one high roller enters. For a sole high roller,
the activity-rationed boost joins the extra bounty as at-risk exposure on the same run.

For protocol-scheduled Bonus Battles, one genuine VRF-backed roll selects the high-roller
multiplier for the entire protocol day:

- 90% of protocol days: H = 10
- 10% of protocol days: H = 100
- The same H applies to all seven scheduled windows belonging to that day.

For custom battles, the creator fixes H when creating the battle, or sets H = 0 to disable
high-roller mode.

## 2. Existing Behavior and Required Delta

### Current

- CrapsBattle schedules seven Bonus Battle windows per protocol day.
- Each slot fixes one bankroll R, goal, board stake, and per-seat bounty B.
- The current entry multiple may be any integer from 1 through 256.
- That multiple scales the bankroll burn and the run return, but each seat still posts only one B.
- Every entrant is folded into one packed main scoreboard during the existing resolveSlot walk.
- The main winner receives the entrant-funded bounties plus the protocol boost and donations.
- A busted run pays zero; its remaining bankroll is deleted and does not enter any bounty pool.
- Protocol day tickets are stored once and folded into each of the seven windows when that window
  is armed.
- Custom battle terms are immutable and packed into one word.

### Target

- Battle entries become binary: normal at 1x or high roller at the battle's single H.
- A high roller burns H times both bankroll and bounty.
- Every high roller remains in the main field and also enters one high-roller-only side field.
- The main field receives exactly one B from every seat.
- The high-roller allocation receives the remaining H - 1 copies of B from each high roller.
- If exactly one high roller enters, that allocation becomes an at-risk bankroll rider on the
  sole high roller's same run; with two or more, it forms the competitive side pool.
- The existing run settles once. Its unscaled score is folded into the main scoreboard and, only
  for a high roller, the high-roller scoreboard.
- Regular-action modeled burn continues to recycle 50% into the main boost.
- High-roller-action modeled burn is split 30% to a high-roller-only boost, 20% to the
  main boost, and 50% unrecycled, using the exact integer rules in Section 4.8.
- The main boost and every donation remain in the main pool. The separate high-roller boost is
  available whenever at least one high roller enters; it is never multiplied by H.
- With zero high rollers, that window's high-roller boost is not minted, carried, refunded, or
  redirected. With exactly one high roller, X and Q_H form one combined rider on that player's
  run, so both return zero on a bust and scale pro rata on a win.

## 3. Definitions

For one battle:

| Symbol | Meaning |
|---|---|
| R | Base bankroll for one run |
| B | Base bounty posted by one normal seat |
| H | High-roller multiplier; 10 or 100 for scheduled battles, creator-set for custom battles |
| N | Total entrants in the main field, including high rollers and any protocol seats |
| N_H | Number of high-roller seats |
| X | One high roller's extra allocation, (H - 1) × B |
| Q_M | Main protocol boost actually claimable under the existing activity-score rule; zero for custom battles |
| Q_H | Activity-rationed high-roller protocol boost allocation; zero for custom battles or N_H = 0 |
| G_H | Gross high-roller boost for an eligible scheduled window before activity-score rationing |
| Y | Sole high roller's combined rider capital, X + Q_H |
| D | Donations routed through the existing main seed/donation accounting; never routed to the high-roller field |
| m_i | Entry scale for seat i; exactly 1 or H |
| P | The existing rounded payout of one base run after bust deletion; zero on a bust |
| A_H(d) | High-roller bankroll action settled on protocol day d, including X only for a sole rider |
| A_R(d) | Regular bankroll action on day d, equal to dayStaked(d) - A_H(d) |
| E_H, E_R | Seven-day modeled high-roller and regular burn, using the existing divisor 36 |

All FLIP arithmetic uses integer wei. B remains an exact multiple of BATTLE_STAKE_UNIT, so the
high-roller pool requires no fractional rounding.

## 4. Locked Product Rules

### 4.1 One Genuine Daily RNG Roll

The scheduled high-roller multiplier must be derived only from the protocol's existing committed,
Chainlink-VRF-backed daily word:

~~~solidity
bytes32 constant HIGH_ROLLER_DAY_TAG =
    keccak256("CrapsBattle.HighRollerDay.v1");

function highRollerMultiplierFromWord(uint256 vrfWord)
    internal
    pure
    returns (uint16)
{
    uint256 roll =
        uint256(keccak256(abi.encode(vrfWord, HIGH_ROLLER_DAY_TAG))) % 10;
    return roll == 0 ? 100 : 10;
}
~~~

The hash is only a domain-separated extractor from genuine VRF entropy. It is not an alternative
random source.

Normative rules:

1. A zero daily word means the draw is unavailable. There is no fallback RNG.
2. No block timestamp, block number, blockhash, prevrandao, protocol day number, caller, entry
   count, transaction order, or admin value may supply or modify the entropy.
3. The day, period, slot, player, and entry mode must not be salted into this draw.
4. Calling the derivation repeatedly for the same VRF word must return the same H.
5. All seven scheduled windows whose slot belongs to that protocol day must use the same H,
   including a window armed or claimed on a later day.
6. H is knowable before entry as soon as the daily VRF word is committed.
7. Opening or arming windows in a different order must not change H.
8. This is an independent 1-in-10 probability per protocol day, not a promise that every fixed
   block of ten consecutive days contains exactly one 100x day. Clusters and dry spells are valid.
9. The tiny modulo bias from reducing a 256-bit uniform value modulo ten is accepted.
10. Custom battles never use this roll.

### 4.2 Entry Modes and Stale-Quote Safety

Retain the existing external multiple argument and function selectors:

~~~solidity
enterBonusBattle(uint256 period, Craps.Bets calldata chips, uint16 multiple)
enterBonusDay(Craps.Bets calldata chips, uint16 multiple)
enterBattle(uint64 slot, Craps.Bets calldata chips, uint16 multiple)
~~~

For each call, resolve the slot's H before taking funds:

- multiple = 1: normal entry.
- multiple = H, where H > 1: high-roller entry.
- Every other value reverts with BadEntryMultiple.
- For a custom battle with H = 0, only multiple = 1 is valid.

This deliberately replaces arbitrary 2x through 256x battle entries. It also makes the variable
daily multiplier quote-safe: a transaction submitted with multiple = 10 cannot silently become a
100x purchase if it lands against a 100x day.

For entry scale m:

~~~text
entry burn = m × (R + B)
ordinary run payout = m × payoutOfOneRun
sole-high-roller payout = H × payoutOfOneRun + pro-rata return on X
~~~

The engine still executes one base run at bankroll R and goal G. As in the current contract,
rounding is performed on the one-run result before multiplying it by m.

If the burn cannot be funded, the complete entry reverts. No seat, count, or partial day-ticket
state may survive a failed burn.

### 4.3 Pool Partition and Conservation

Each entrant, including a high roller, contributes exactly one B to the main bounty pool.
Each high roller additionally contributes X = (H - 1) × B to the high-roller allocation.

~~~text
main bounty principal          = N × B
high-roller allocation         = N_H × X
total bounty burned            = B × N + N_H × X
~~~

Therefore:

~~~text
total bounty burned
= main bounty principal + high-roller allocation
~~~

The bankroll R is not bounty principal and never enters either bounty pool.

The main competitive award is:

~~~text
main award = N × B + Q_M + D
~~~

subject to the scheduled-window activity-score rationing. There is no walkover: every field that
forms is payable, and there is no head count below which the pot falls back out.

The high-roller allocation is routed by final high-roller head count:

~~~text
N_H = 0: no allocation
N_H = 1: X + Q_H becomes one at-risk bankroll rider on the sole high roller's run
N_H >= 2: N_H × X becomes competitive side principal and Q_H may be added
~~~

For the sole high roller, let P be the already-rounded one-run payout that the existing engine
would use before applying H. The rider's return is:

~~~text
Y = X + Q_H
rider return = floor(P × Y / R)
total sole-high-roller credit = H × P + rider return
~~~

Use full-precision integer mulDiv and floor only the final division. Because P is zero on a bust,
both the bounty and boost rider capital are lost completely on a bust. They receive the same
pro-rata return as the existing run on every non-bust outcome and do not change the engine
bankroll, goal, board, odds, or score. Compute one mulDiv over X + Q_H; do not floor two separate
returns.

When N_H >= 2, the competitive high-roller award is:

~~~text
high-roller award = N_H × X + Q_H
~~~

Only the dedicated high-roller boost Q_H may supplement the player-funded side principal. The
main boost, donations, busted bankroll remainder, unrelated bankroll return, and rounding residue
may not enter the competitive high-roller award. No component may be counted in both routes.
Activity-score rationing fixes only Q_H and never reduces player-funded X or N_H × X.
For N_H = 1, activity-score rationing first fixes Q_H, then X + Q_H shares the run's outcome.
Q_H is protocol-funded and excluded from A_H even though it is placed at risk, preventing emitted
boost capital from recursively funding later boost budgets.

### 4.4 Eligibility and Ranking

- Every normal and high-roller seat competes in the main field.
- Only a seat explicitly stored as high roller competes in the high-roller field.
- Protocol house and vault day seats are always normal 1x seats.
- A high roller may win both the main award and the high-roller award.
- The two awards may have different winners.
- High-roller status does not improve a run's odds, goal, board, dice, survival coin, or score.

Both scoreboards use the current, identical composite ordering:

1. Goal beats every bust.
2. Faster goal beats slower goal.
3. Among busts, more hands survived wins.
4. If rank is equal, higher unscaled ending bankroll wins.
5. If still equal, higher entry-frozen standing wins.
6. An exact tie uses the existing settlement-word-derived deterministic bet-id ordering.

The high-roller multiplier and scaled payout must never enter either scoreboard.

### 4.5 High-Roller Pool Lifecycle

The side field becomes final only when the main battle has resolved every entrant.
The rider-versus-competition route is determined from the final N_H frozen when entry closes
(and, for day tickets, after their count is folded in at arm). Settlement must never decide this
from a partial batch or from the number of high rollers resolved so far.

| High-roller seats | Required result |
|---:|---|
| 0 | No high-roller liability exists; the window's high-roller boost is unminted; finalization reads the empty sideboard once and pays nothing |
| 1 | Apply X + Q_H as one at-risk pro-rata bankroll rider on that seat's existing run, during its own settlement |
| 2 or more | Credit N_H × X plus the activity-rationed high-roller boost Q_H to the best high roller as coinflip stake, in the call that finalizes the main field |

Additional rules:

- The base B paid by a sole high roller remains governed by the main pool.
- A sole high roller can win the main award, but X is paid only through the run's outcome.
- The rider is a fractional copy of the same run: it neither deepens the engine bankroll nor
  changes main-field ranking.
- The return on X + Q_H is included in the normal batched credit and is not liquid FLIP. Both
  components use the same run multiplier and are at risk.
- X is booked as bankroll action for dayStaked because it is genuinely placed at risk.
- The dedicated high-roller boost is protocol-funded and follows the winning high roller's frozen
  activity-score share. Player-funded X does not.
- Any gross high-roller boost not paid because N_H = 0, activity-score rationing, integer
  granularity, or a zero budget is never minted and is not carried or redirected to main.
- If every high roller busts, the best bust wins when N_H >= 2.
- A custom battle that permits multiple entries counts paid seats, not unique addresses. Two
  high-roller seats are competitive even if one allowed address owns both.
- If B = 0, X is zero but a scheduled sole high roller may still have Q_H rider capital. Its
  return follows P; no external payment call is made when the complete batch credit is zero.
- Main and high-roller claims are independent and may execute in either order.
- A sole rider is processed exactly once by the existing settlement cursor.
- Every competitive side award is claimable exactly once.
- The sole-rider processed bit and the competitive claimed bit are established before their
  respective external payment call.

### 4.6 Protocol Day Tickets

While period zero is open, enterBonusDay continues to create one stored ticket for all seven
windows.

For a normal day ticket:

~~~text
day cost = sum over p=0..6 of (R_p + B_p)
~~~

For a high-roller day ticket:

~~~text
day cost = H_day × sum over p=0..6 of (R_p + B_p)
~~~

The same H_day applies to all seven windows.

The ticket stores its high-roller flag once. Its normal day count and high-roller day count are
folded into each window when that window is armed, preserving the current no-per-window-write
purchase path.

The day lane is period-zero only: `enterBonusDay` reverts with `BonusPeriodSpent` once the day's
first window has closed, because a whole-day ticket is a commitment made before any of the day is
spent. After period zero the remaining windows are entered one at a time through
`enterBonusBattle`, each such entry using the same H_day and updating that window's high-roller
count directly.

House and vault day tickets remain normal and pay only the existing sum of R_p + B_p.

### 4.7 Custom Battles

createBattle gains one immutable uint16 highRollerMult term.

Valid values:

- 0: high-roller mode disabled.
- 2 through 256 inclusive: enabled at exactly that H.
- 1: invalid and reverts with BadHighRollerMultiplier.
- Greater than 256: invalid and reverts with BadHighRollerMultiplier.

Custom-battle rules:

1. H is fixed at creation and cannot be amended.
2. H is included in the packed terms, creation event data, decoded view, and battle key terms.
3. Entry accepts only multiple = 1 or, when enabled, multiple = H.
4. The creator does not choose or influence a daily VRF roll; custom H is an explicit fixed term.
5. Custom donations remain entirely in the main pool.
6. Custom battles receive no protocol boost.
7. The existing minScore and multiEntry terms remain independent of high-roller mode.
8. Setting H = 0 does not allocate or touch side-pool storage on the normal path.
9. Settled custom high-roller bankroll action still contributes to A_H for future scheduled-day
   budget draws, just as settled custom action contributes to the existing dayStaked total.

### 4.8 Burn-Derived Main and High-Roller Boost Budgets

The budget basis remains the contract's existing modeled-burn proxy, not realized table income:
player-funded settled bankroll action divided by BOOST_ACTION_DIVISOR = 36. Bounties, protocol
boost capital, and realized dice profit/loss are excluded. For a sole high roller, X is included
because Section 4.5 turns that player-funded bounty into real bankroll exposure; Q_H is excluded
because recycling protocol-funded boost capital would create a recursive emissions loop. When
N_H >= 2, X remains bounty principal and is excluded from action.

Settlement must accumulate two figures for each protocol day d:

~~~text
totalAction(d) = dayStaked(d)
highAction(d)  = A_H(d)
regularAction(d) = A_R(d) = totalAction(d) - highAction(d)
~~~

The invariant highAction(d) <= totalAction(d) must always hold. A high roller contributes H × R
to both totalAction and highAction, plus X in both only when that battle's final N_H is exactly 1.
Q_H contributes to neither accumulator. A normal seat contributes R only to totalAction. No
player-funded action may appear in both A_R and A_H.

For a day d being opened, use only the seven prior settled protocol days:

~~~text
E_R = sum(i = 1..7, d >= i) floor(A_R(d - i) / 36)
E_H = sum(i = 1..7, d >= i) floor(A_H(d - i) / 36)

regularRecycle = floor(E_R / 2)
highRecycle    = floor(E_H / 2)
mainFromHigh   = floor(highRecycle × 2 / 5)
highBudget     = highRecycle - mainFromHigh
mainRaw        = regularRecycle + mainFromHigh
mainBudget     = max(MIN_BOOST_BUDGET, mainRaw)
~~~

This is the exact integer implementation of the requested split. Whenever E_H is divisible by
10, highBudget = 30% × E_H, mainFromHigh = 20% × E_H, and E_H - highRecycle = 50% × E_H.
Otherwise, floor(E_H / 2) fixes the maximum recycled half, floor(2/5) assigns the main share,
and the at-most-one-wei split remainder goes to highBudget. The unrecycled amount is always
E_H - highRecycle, and highBudget + mainFromHigh is exactly highRecycle. Regular modeled burn
continues to recycle floor(E_R / 2) entirely to main.

MIN_BOOST_BUDGET remains the existing 15,000 FLIP main-budget floor. It applies after mainRaw is
calculated and never creates a high-roller budget. A floor top-up is the existing cold-table
subsidy and sits outside the 30/20/50 high-burn split. With no prior high action, highBudget is
exactly zero.

Both budgets are drawn once and stored when the protocol day opens. Each window uses one seventh
of its own day's applicable budget and the existing known/mystery ladder. The main and high-roller
lanes use the same window classification and the same genuine-VRF-derived rung; there is no second
random draw and no new entropy source. Because both ladders have mean one, mainBudget and
highBudget are expected gross daily boost allocations before granule flooring, participation
gating, activity-score rationing, and—on a sole high-roller field—the rider's run outcome. They
are not hard per-day payout caps.

For a scheduled window:

~~~text
gross main boost = existing ladder amount from mainBudget / 7
G_H              = same ladder amount from highBudget / 7
Q_H              = N_H >= 1 ? activityShare(G_H, highWinnerStanding) : 0
~~~

The main winner keeps the existing main boost and donation treatment. With two or more high
rollers, the high winner receives Q_H in addition to N_H × X. With one high roller, that player
is the high winner by default, but X + Q_H is applied to the same run as one combined rider rather
than paid outright. Only when N_H is zero is G_H unallocated; it does not move to main, a later
window, or a future day. Custom battles always have G_H = 0.

## 5. Contract Surface

Names may be adjusted to local conventions, but the following information and behavior are
required.

### 5.1 Constants and Errors

AS SHIPPED. `CrapsBattle` carries **no public constants at all** — every one of them is
`internal`, because the contract is held tight against EIP-170 and a public constant is a whole
getter. A test or client reads them through the `CrapsViews` harness or restates them.

~~~solidity
uint256 internal constant _HIGH_MULT = 10;
uint256 internal constant _HIGH_MULT_TAIL = 100;
uint256 internal constant _MAX_HIGH_MULT = 256;

error BadHighRollerMultiplier();
~~~

The minimal-ABI option was taken. `BadEntryMultiple` carries every rejected entry multiple, and
none of `HighRollerDisabled`, `NoHighRollerEntrants`, `HighRollerNotCompetitive` or
`HighRollerAlreadyClaimed` exists: with the lane paid at finalization there is no claim to refuse,
and an empty lane is a silent no-op rather than a revert.

### 5.2 Views

AS SHIPPED — **none of these is external.** The whole reader surface went `internal` to buy back
EIP-170 margin; `CrapsBattle` exposes fifteen functions, of which the only views are `GAME`,
`battleCreator`, `previewSettlement` and `stakeFor`. There is no `claimHighRoller`, because a
contested lane is paid by the settlement that finalizes its main field.

~~~solidity
function _highMultOf(uint256 word) internal pure returns (uint256);
function _highFieldOf(bytes32 key)
    internal
    view
    returns (uint32 heads, uint256 best, uint64 winnerSeat, bool bankrollRider, bool done);
function _highBase(Window memory w) internal view returns (uint256);
~~~

A test reads them back through `test/craps/CrapsViews.sol`, which re-exposes the internals under
their public names; a client reconstructs them from the daily word and the event stream. **Anything
that needs a new reader must budget the bytes for it** — see §11.1.

Semantics, unchanged from the design:

- the day's multiplier is undrawn while `_dailyWordAt(day)` is zero; otherwise 10 or 100.
- a slot carries the immutable H it was opened under, not the current day's H.
- a winner seat converts to a complete bet id through the same own-then-day mapping the settle
  walk uses, so a day-lane winner resolves correctly.
- principal is zero for N_H = 0; X for N_H = 1; or N_H × X for N_H >= 2.
- grossBoost is G_H and allocatedBoost is the activity-rationed Q_H allocation after finalization;
  both are zero for custom battles and for N_H = 0. For N_H = 1, principal + allocatedBoost is
  the combined rider capital, not a guaranteed payout. Before finalization, the existing
  quote/band surface must expose the high-roller lane's known exact amount or mystery ceiling
  alongside the main lane.
- bankrollRider is true only when N_H = 1.
- finalized mirrors complete settlement of the battle, not whether the main award was claimed.
- processed means the sole rider's run has settled when N_H = 1, or the competitive side award
  has been claimed when N_H >= 2.
- betOf must expose both the stored multiple and high-roller status.
- bonus/custom terms views must expose H without requiring event replay.
- dayStaked remains total action; highRollerDayStaked exposes A_H, highRollerDayBurn returns
  floor(A_H / 36), and highRollerBoostBudgetOf exposes the immutable stored daily high budget.
- The existing scheduled boost quote/band view must expose both main and high-roller values with
  identical known-versus-mystery semantics. An equivalent ABI is acceptable if neither indexers
  nor front ends must replay settlement transactions to reconstruct either lane.

### 5.3 Events

~~~solidity
event CrapsHighRollerDayOpened(
    uint24 indexed day,
    uint16 multiplier,
    uint256 mainBoostBudget,
    uint256 highRollerBoostBudget
);

event CrapsHighRollerFinalized(
    bytes32 indexed battleKey,
    uint48 indexed slot,
    uint16 multiplier,
    uint32 entrants,
    uint256 winnerBetId,
    uint256 principal,
    uint256 grossBoost,
    uint256 allocatedBoost,
    bool bankrollRider
);

event CrapsHighRollerPaid(
    uint256 indexed betId,
    bytes32 indexed battleKey,
    address indexed player,
    uint256 amount,
    bool bankrollRider
);
~~~

- Emit CrapsHighRollerDayOpened once when openBonusDay successfully opens a day, before or
  alongside its seven CrapsBonusOpened events. Its two budget values are the amounts frozen for
  that day by Section 4.8.
- Do not emit it on a no-word or already-open no-op.
- Emit CrapsHighRollerFinalized only when N_H > 0 and the main field becomes final.
- For N_H = 1, emit CrapsHighRollerPaid during that seat's settlement with amount equal to the
  combined rider return floor(P × (X + Q_H) / R) and bankrollRider = true. An amount-zero bust
  event is permitted and recommended so indexers can observe that the lane was processed.
- For N_H >= 2, emit CrapsHighRollerPaid during the successful side claim with
  amount = N_H × X + Q_H and bankrollRider = false.
- CrapsHighRollerFinalized reports the exact grossBoost G_H and allocatedBoost Q_H for every
  N_H >= 1 field, including a sole high roller already processed during settlement.
- The existing CrapsSlipPlaced multiple-minus-one field continues to expose 1, H, and thus entry
  mode without a second entry event.
- CrapsBattleCreated must expose the custom H through its packed terms.

## 6. Required Accounting Algorithms

### 6.1 Entry

For a direct window or custom battle:

1. Resolve the slot and immutable H.
2. Require multiple = 1 or multiple = H > 1.
3. Validate the board and existing seat/minScore rules.
4. Burn multiple × (R + B).
5. Enter the seat in the existing main scoreboard.
6. If multiple = H, increment the sideboard's high-roller entrant count.
7. Store multiple - 1 in the existing multiple byte and set the explicit high-roller flag.
8. Emit the existing placement event.

The burn must occur before making entrant counts externally durable, or the complete transaction
must revert atomically on burn failure.

### 6.2 Settlement

For every entrant in the existing resolveSlot walk:

1. Execute the one existing base run.
2. Build the one existing unscaled composite score.
3. Fold it into the main scoreboard.
4. If the stored high-roller flag is set, fold the same score and same tie-break into the
   high-roller sideboard.
5. Start the run payment at P × stored multiple.
6. If this is the sole high roller in a scheduled window, derive G_H using the same boost rung and
   apply _boostShare using that seat's frozen standing to fix Q_H. Custom Q_H is zero.
7. If this is the sole high roller, set Y = X + Q_H and add floor(P × Y / R) to the run payment.
   Perform one full-precision mulDiv over the combined Y. Perform the corresponding one combined
   pro-rata calculation from the raw one-run return for the event's raw won field.
8. Book total bankroll action at R × stored multiple, plus X only for the sole high roller. Q_H
   is protocol-funded boost capital and is not booked as action even though it rides the run.
9. If the seat is high roller, add that same action amount to the batch's highAction accumulator.
10. Mark the sole rider/boost lane processed as part of the same settlement state transition.

There must be no second walk over entrants. Within one resolveSlot batch, load/update/write the
high-roller sideboard at most once when one or more high rollers occur in that batch.

The sole-rider calculation must use a full-precision mulDiv. It operates on the existing base-run
result after the contract's normal rounding/bust rule, so it behaves exactly like a fractional
copy of the bankroll:

~~~text
P = 0                         => rider return = 0
P = R                         => rider return = Y = X + Q_H
P = k × R                     => rider return = k × Y, subject only to final integer floor
~~~

### 6.3 The Main Pot

AS SHIPPED — **there is no claim transaction.** A battle pays the instant its last seat scores,
inside `resolveSlot`, from the one branch of `_scoreBattle` where `resolved == entrants`. That
branch already holds everything a payment needs — the winner, the boost, the table's word — so a
separate claim would only re-derive all of it and cost the player a second transaction to collect
what is already decided.

The main payment is responsible only for:

- N × B,
- the main protocol boost Q_M,
- donations, and
- activity-score rationing on protocol windows.

It neither pays nor marks the extra high-roller principal. There are no walkover refunds: every
field that forms pays out, and nothing in this contract mints FLIP back to anybody.

### 6.4 The High-Roller Lane

The lane is paid from the same branch, immediately after the main pot, by `_payout`:

1. Read the sideboard for the finished field's key. This is the one lane read a field with no high
   seat performs — the paying batch cannot know whether a lane stands beside it without asking.
2. Stop unless N_H >= 2. N_H = 0 has no field; N_H = 1 was already settled with its own run.
3. Map the best side winner to its full bet id and load that seat's frozen standing.
4. Derive G_H from the stored day budget and the window's same known/mystery rung; custom G_H is
   zero. Compute Q_H = `_boostShare(G_H, highWinnerStanding)`.
5. Latch the side field done before the external call.
6. Credit N_H × X + Q_H as coinflip stake. Apply `_boostShare` only to G_H, never to N_H × X.
7. Skip the external payment call only when the complete amount is zero.
8. Emit `CrapsHighRollerPaid` with `bankrollRider = false`.

This path is O(1) and runs exactly once by construction, so it needs no latch of its own to be
correct — the `done` bit is written for observers. It never processes a sole high roller.

**Ordering is load-bearing.** `_resolve` folds a high seat into the sideboard BEFORE scoring the
main board, because scoring is what finalizes the field and finalizing is what pays — so the last
high seat must already be in the sideboard when `_payout` goes looking for a lane winner.

## 7. Storage and Packing Contract

The exact bit positions below are the preferred implementation because they preserve the current
one-word bet and one-word custom terms. An equivalent packing is acceptable only if it meets the
same ABI, conservation, code-size, and gas requirements.

### 7.1 Bet Word

Use currently unused bit 217:

~~~text
bits 206..213  entry multiple minus one
bits 214..216  day-entry start period plus one
bit  217       isHighRoller
~~~

Store both the scale byte and explicit flag. Settlement eligibility must read the flag, not infer
eligibility from a caller argument.

### 7.2 Custom Terms

Use nine bits beginning at 114:

~~~text
bit  113       existing multiEntry
bits 114..122  highRollerMult, literal 0..256
~~~

Also include H in Window.terms at a non-overlapping position so battleKey commits to the complete
field economics.

### 7.3 One Sideboard Word per Battle

Use one mapping keyed by battle key or slot:

~~~text
bits   0..31   high-roller entrant count
bits  32..101  best composite score (same 70-bit score as main)
bits 102..133  winning combined seat id
bit  134       processed: sole rider settled or competitive award claimed
bits 135..255  reserved
~~~

No separate high-roller result array, resolved bitmap, resolved count, pot accumulator, or claim
cursor is required:

- Main finalization proves every eligible high-roller score has been folded.
- Entrant count is known from entry.
- Player-funded side principal is derived from immutable H, immutable B, and N_H; Q_H is derived
  from the frozen daily budget, the shared ladder rung, and the winner's frozen standing.
- N_H = 1 needs only the stored sole-seat id and one processed bit; its return is included in the
  existing settlement credit.

### 7.4 Day Tickets

Pack total day-ticket count and high-roller day-ticket count into one existing day-count storage
word. A high-roller day purchase must not write seven battle sideboards.

When each window is armed:

- add total day-ticket count to its main entrant count;
- add high-roller day-ticket count to its sideboard entrant count; and
- do each addition exactly once under the existing one-time arm latch.

### 7.5 Day Action and Boost Budgets

Add one high-action accumulator and one frozen high-budget value per protocol day:

~~~text
mapping(uint24 => uint256) highRollerDayStaked
mapping(uint24 => uint256) highRollerBoostBudget
~~~

The existing dayStaked remains the total, and the existing boostBudget becomes the main budget.
A settlement batch accumulates totalAction and highAction in memory, writes dayStaked once as it
does today, and writes highRollerDayStaked at most once only when highAction is nonzero. There is
no per-seat action write.

openBonusDay derives and stores both budgets once. The high budget is a daily value shared by the
seven windows, so it requires no per-window pot storage. Its exact window amount remains derived
from immutable day budget, period, battle key, and genuine VRF words. Packing either daily pair is
permitted only if the implementation proves that the chosen field widths cannot truncate any
legal action or budget; otherwise retain full-width words.

## 8. Economic and State Invariants

The implementation must maintain all of the following:

1. For every accepted seat, m is exactly 1 or H.
2. For every accepted seat, burned bankroll equals m × R.
3. For every accepted seat, burned bounty equals m × B.
4. Main bounty principal always equals N × B.
5. High-roller allocation always equals N_H × X.
6. When N_H = 1, X becomes sole-rider bankroll action; when N_H >= 2, N_H × X becomes side
   bounty principal.
7. Main principal plus the high-roller allocation equals all bounty burned by entrants.
8. Neither Q_M nor Q_H is multiplied by H; donations remain main-only.
9. High-roller mode never changes the base engine input R, goal, board, dice word, or score.
10. With N_H != 1, a high roller's run-derived credit is exactly H times the rounded one-run
    credit; any competitive Q_H is a separate side-award component.
11. With N_H = 1, complete settlement credit is H × P + floor(P × (X + Q_H) / R), using one
    full-precision floor over the combined rider capital.
12. A bust has P = 0 and therefore zero base credit and zero return on both X and Q_H; its
    remaining player-funded bankroll enters neither bounty pool.
13. The sole rider books X as additional total and high-roller action exactly once. Q_H is placed
    at risk but excluded from both action accumulators because it is protocol-funded emission.
14. Main and competitive side claims cannot make combined player-funded bounty-principal payout
    exceed the bounty principal routed to those fields.
15. For every day, 0 <= A_H <= dayStaked and A_R = dayStaked - A_H.
16. No bankroll action is counted in both E_R and E_H.
17. Regular modeled burn contributes exactly floor(E_R / 2) to mainRaw.
18. High modeled burn satisfies highRecycle = floor(E_H / 2),
    mainFromHigh = floor(2 × highRecycle / 5), and
    highBudget = highRecycle - mainFromHigh.
19. MIN_BOOST_BUDGET applies only to mainBudget; highBudget has no floor, subsidy, or carry.
20. Q_H is zero unless the battle is scheduled and final N_H >= 1.
21. With N_H = 1, the sole settlement credit is exactly H × P + floor(P × (X + Q_H) / R);
    with N_H >= 2, the competitive high award is exactly N_H × X + Q_H.
22. Activity-score rationing fixes Q_H only; it never reduces player-funded X. For N_H = 1, the
    resulting X + Q_H allocation then follows the run as one combined rider.
23. Main and high boosts use the same known/mystery classification and rung; high mode introduces
    no second random draw or non-VRF entropy.
24. Any Q_H unminted because N_H = 0, score rationing, or granule flooring is not redirected to
    main, another window, or another day.
25. Protocol house and vault seats never increment N_H.
26. A delayed scheduled window uses the H and both budgets of its slot's day.
27. A custom battle uses its creation-time H forever, receives no current protocol boost, and
    still contributes its settled high action to future scheduled budget draws.
28. No outcome depends on settlement batch size or settlement order.
29. Repeating open, arm, settle, finalize, or claim calls cannot create a second rider return,
    side liability, budget, or payment.
30. No direct ETH movement or new ETH solvency accounting is introduced; FLIP burn and
    coinflip-credit semantics remain the existing protocol primitives.

## 9. Worked Accounting Examples

Assume R = 1,200 FLIP and B = 200 FLIP.

### 9.1 A 10x Day

Three normal seats and two high rollers:

~~~text
normal entry cost each = 1 × (1,200 + 200) = 1,400
high entry cost each   = 10 × (1,200 + 200) = 14,000

N   = 5
N_H = 2

main bounty principal = 5 × 200 = 1,000
side bounty principal = 2 × 9 × 200 = 3,600
total bounty burned   = 1,000 + 3,600 = 4,600
~~~

The main winner receives 1,000 plus the main boost/donations. The best of the two high rollers
receives 3,600 plus the dedicated activity-rationed high-roller boost. One high roller may
receive both.

### 9.2 A Sole High Roller on a 100x Day

~~~text
high entry cost        = 100 × (1,200 + 200) = 140,000
main bounty principal  includes 1 × 200
sole bankroll rider X  = 99 × 200 = 19,800
player-funded bankroll exposure = 100 × 1,200 + 19,800 = 139,800
combined exposure after boost allocation = 139,800 + Q_H
~~~

The 200 base bounty stays in the main competition. Neither the 19,800 nor Q_H comes back. If the
one-run rounded payout P is zero, both rider components return zero. If P is 2,400:

~~~text
combined rider capital = 19,800 + Q_H
combined rider return = floor(2,400 × (19,800 + Q_H) / 1,200) = 39,600 + 2 × Q_H
complete settlement credit = 100 × 2,400 + 39,600 + 2 × Q_H
                           = 279,600 + 2 × Q_H
~~~

The base run's competitive score remains unchanged. Because N_H = 1, both the player-funded
19,800 and activity-rationed Q_H ride the run and scale with its outcome. On a bust, both return
zero. Q_H is nevertheless excluded from future burn accounting because it was protocol-funded.

### 9.3 A 30/20 High-Burn Split

Suppose the seven prior days produce 100,000 FLIP of regular modeled burn and 40,000 FLIP of
high-roller modeled burn after the per-day division by 36:

~~~text
E_R = 100,000
E_H =  40,000

regularRecycle = 100,000 / 2 = 50,000 to main
highRecycle    =  40,000 / 2 = 20,000 total recycled from high action
mainFromHigh   =  20,000 × 2 / 5 = 8,000
highBudget     =  20,000 - 8,000 = 12,000

mainRaw        = 50,000 + 8,000 = 58,000
mainBudget     = max(15,000, 58,000) = 58,000
~~~

The high-derived 40,000 therefore routes 12,000 (30%) to the high-roller budget, 8,000 (20%)
to main, and leaves 20,000 (50%) unrecycled. The two boost budgets are expected-allocation bases;
their seven window payouts still follow the existing mean-one boost ladder, activity rationing,
and participation gates.

## 10. Edge Cases

- **No VRF word:** the day has no H and cannot use a fallback or pseudo-random draw.
- **Repeated day open:** no reroll and no duplicate daily event.
- **All seven periods:** every period reports the same H.
- **Delayed arm/claim:** resolve H from the slot's original day, not currentDayIndex.
- **Day boundary transaction:** a submitted 10 is rejected if the destination battle requires 100.
- **Custom H disabled:** normal entry works; high entry reverts; side storage remains untouched.
- **Custom H boundaries:** 0, 2, and 256 are accepted as specified; 1 and 257 are rejected.
- **N_H = 0/1/2:** respectively no high payment, sole X + Q_H bankroll rider, and
  competitive side principal plus Q_H.
- **No prior high action:** highBudget is zero; the main floor does not subsidize it.
- **Zero high rollers in a window:** its G_H is unminted without carry or rerouting.
- **Exactly one high roller:** X + Q_H is one at-risk rider on that seat's run; both return zero
  on a bust and both scale pro rata on a non-bust.
- **Exactly two high rollers:** the better high score receives side principal plus Q_H.
- **Budget split rounding:** floor the recycled half first, floor its 2/5 main share second, and
  assign the remaining recycled wei to highBudget.
- **Seven-day boundary:** today's settlements cannot alter today's already-frozen budgets and
  affect only future draws whose prior-seven-day window includes today.
- **B = 0:** high mode may still scale bankroll; X and the rider/side amount are zero.
- **B = 0 with a scheduled high field:** X/player-funded side principal is zero, but Q_H may
  still be nonzero because it is funded by prior high action; for N_H = 1 it rides the run alone.
- **Rider rounding:** floor only the final full-precision P × (X + Q_H) / R division.
- **Sole high roller bust:** P = 0, so both X and Q_H return zero and no later claim exists.
- **All high rollers bust:** rank the busts normally and pay the best bust when N_H >= 2.
- **Exact score tie:** use the same word-derived total ordering as the main scoreboard.
- **Same winner twice:** a high roller may claim both independently; neither claim blocks the other.
- **Custom multiEntry:** paid seats count independently even if controlled by one address.
- **House/vault funding failure:** preserve existing fail-soft seating behavior; neither becomes high roller.
- **Batch splits:** resolving one field as 1 + 1 + N or all N at once yields identical winners and amounts.
- **Claim races:** first valid claim wins the latch; later calls revert without payment.
- **Arithmetic maximums:** H = 256, maximum bounty granules, maximum bankroll, and a uint32 entrant count
  must not overflow any cost or pot calculation.

## 11. Gas, Storage, and Code-Size Requirements

### 11.1 Structural Limits

- One additional persistent sideboard word per battle that actually receives a high roller.
- At most one additional high-action accumulator word per day that settles high-roller action,
  and one frozen high-budget word per opened day when that budget is nonzero.
- No per-entrant side result storage.
- No second settlement loop.
- No loop on the lane's payment; a sole rider is handled inside the existing settlement walk.
- No per-window storage writes when purchasing an early high-roller day ticket.
- A no-high-roller battle must not WRITE the sideboard mapping, and must read it at most once —
  on the seat that finalizes the field, which is the seat that pays it. Never once per entrant.
- A settlement batch containing no high rollers must not write highRollerDayStaked.
- Main and high boosts must reuse the same ladder draw; no per-window high-boost state or RNG word.
- Runtime bytecode must remain below the EIP-170 limit of 24,576 bytes.

### 11.2 Pre-Implementation Baseline

Measured on 2026-08-26 with the current working tree and Solc 0.8.34:

| Existing benchmark | Gas |
|---|---:|
| createBattle | 61,082 |
| enterBattle, first seat | 109,417 |
| enterBattle, later seat | 32,694 |
| closeBattle | 78,300 |
| resolveSlot, field of 2 | 187,710 |
| resolveSlot, field of 20 | 2,266,811 |
| max legal slip settlement | 215,467 |
| engine worst-case run | 1,528,173 |

### 11.3 Regression Budgets

- Normal entry: no more than 2,500 gas above its equivalent baseline.
- First direct high-roller entry into a battle: no more than 25,000 incremental gas.
- Later direct high-roller entry: no more than 10,000 incremental gas.
- A resolveSlot batch containing no high rollers: no more than 2,500 gas above the equivalent
  baseline batch.
- The first resolveSlot batch in a protocol day that books nonzero high action: no more than
  35,000 fixed incremental gas plus 1,000 per additional high roller in the same batch.
- A later high-containing resolveSlot batch booked to an already-nonzero high-action day: no more
  than 18,000 fixed incremental gas plus 1,000 per additional high roller in the same batch.
- The batch that FINISHES a field carries both payments — the main pot and, where the lane is
  contested, the lane — on top of the settle itself. That is what a claimer used to pay separately.
  ⚠ The resolve path is NOT gas-measurable here: a field's shooter is keyed to the slot, so no two
  battles play the same dice and no A/B pair is like-for-like; hand length is geometric with a long
  tail, and over 24 samples the mean still swings by ~20k. The lane's cost is asserted against the
  STORAGE the batch touched instead — see `test_storage_*` in `test/craps/CrapsHighRoller.t.sol`.
- openBonusDay: no more than 25,000 incremental gas for deriving and freezing the second budget.
- Budget drawing remains one fixed seven-day loop and must not scale with entrants or battles.
- The sole-rider mulDiv and accounting must fit inside the existing high-containing resolution
  batch budget; it must not trigger a second external credit call.
- Existing MAX_SLIP_HANDS and engine gas ceilings must not change.

If a budget cannot be met without compromising an invariant, the contract owner must approve a
documented exception with measured before/after gas. It must not be silently waived.

## 12. Requirements

1. **Daily VRF multiplier**
   - Current: No high-roller multiplier exists.
   - Target: One VRF-backed H is derived per protocol day, with a 1-in-10 100x bucket and a
     9-in-10 10x bucket, shared by all seven windows.
   - Acceptance: RNG-01 through RNG-08 pass, including no-word, repeated-open, all-period, and
     delayed-window cases.

2. **Binary entry and full buy-in scaling**
   - Current: Any multiple from 1 through 256 scales bankroll only.
   - Target: Only 1 or H is accepted, and H scales both R and B while the run is executed once.
   - Acceptance: ENTRY-01 through ENTRY-07 prove valid costs, invalid values, atomic failure, and
     stale 10/100 quote rejection.

3. **Conserved two-pool accounting**
   - Current: One main bounty pool contains one B per seat.
   - Target: Main receives one B per seat; each high roller supplies X; a sole X becomes bankroll
     action while two or more X allocations form player-funded side principal. Donations and the
     main boost remain main-only; the separately budgeted Q_H joins the sole rider or supplements
     the competitive side award.
   - Acceptance: ACCT-01 through ACCT-08 prove the formulas for mixed fields, H = 10, H = 100,
     B = 0, maximum values, and randomized entrant counts.

4. **Single-run dual ranking**
   - Current: One packed scoreboard is updated during the existing resolution walk.
   - Target: The same unscaled score conditionally updates one packed high-roller sideboard,
     without rerunning the engine or changing the main result.
   - Acceptance: RANK-01 through RANK-07 prove goal/bust ordering, raw-money ordering, standing,
     exact ties, batch independence, and identical main results with the feature disabled.

5. **Side-pool finalization and claim**
   - Current: No side claim exists.
   - Target: N_H = 0, 1, and at least 2 produce no allocation, one at-risk pro-rata bankroll
     rider containing X + Q_H, and one competitive award of N_H × X + Q_H respectively. Q_H is
     unallocated only for N_H = 0, and every route is processed at most once without another
     entrant walk.
   - Acceptance: CLAIM-01 through CLAIM-10 cover all cardinalities, proportional payout, bust,
     zero amount, claim order, latching, and duplicate calls.

6. **Day-ticket fan-out**
   - Current: One early day ticket is folded into seven main fields at arm time.
   - Target: One stored high-roller flag/count is also folded into all seven side fields and the
     ticket pays the shared H across the complete day.
   - Acceptance: DAY-01 through DAY-07 prove exact cost, one ticket write, seven counts, the
     period-zero-only day lane, house/vault exclusion, and arm idempotency.

7. **Creator-set custom mode**
   - Current: Custom terms contain no high-roller modifier.
   - Target: Custom H is immutable and either 0 or 2..256, with no daily RNG dependency.
   - Acceptance: CUSTOM-01 through CUSTOM-08 cover every numeric boundary, packed/view/event
     round-trip, battle-key separation, disabled mode, donations, and delayed close.

8. **Observable state**
   - Current: Existing views/events cannot reconstruct a side field.
   - Target: Indexers can reconstruct H, entry mode, N_H, winner, principal, gross and claimable
     high boost allocation, bankroll-rider versus competitive routing, daily high action/budget,
     finalization, and processed state from canonical events and views.
   - Acceptance: OBS-01 through OBS-08 compare event replay with live views at budget draw, open,
     entry, finalization, rider settlement, competitive payout, and duplicate-call boundaries.

9. **Bounded gas and storage**
   - Current: Settlement is one dense entrant walk with one main scoreboard.
   - Target: High-roller scoring adds constant storage per battle, at most one sideboard write per
     settlement batch, at most one high-action write per high-containing batch, and O(1) claim
     under the stated gas/code limits.
   - Acceptance: GAS-01 through GAS-11 record before/after measurements and fail if any regression
     budget or EIP-170 bound is exceeded.

10. **Preserve unrelated economics**
    - Current: Busts are deleted, the existing main boost is score-rationed on protocol windows,
      donations follow current routing, and house/vault seats are normal.
    - Target: Except for the explicit budget split and high-only boost, high-roller mode changes
      none of those rules and introduces no direct ETH path.
    - Acceptance: REG-01 through REG-09 prove unchanged bust, main-ladder, donation, RNG,
      house/vault, coinflip-credit, and correctly partitioned dayStaked behavior.

11. **30/20 high-roller burn recycling**
    - Current: dayStaked is not partitioned by entry mode, and 50% of all modeled burn feeds one
      floor-backed main boost budget.
    - Target: The prior seven days' high action is modeled separately at /36; exactly
      floor(E_H / 2) is recycled, with its integer 40% main share producing the requested 20% of
      high burn and its remainder producing the requested 30% high-only budget. High action is
      excluded from E_R, the 15,000 FLIP floor remains main-only, both budgets freeze at day open,
      and Q_H is allocated whenever N_H >= 1 but unallocated when N_H = 0. A sole allocation
      rides the run with X rather than paying outright.
    - Acceptance: BOOST-01 through BOOST-12 prove action partition, 30/20/50 conservation,
      rounding, seven-day draw, floor isolation, shared real-RNG rung, sparse-field behavior,
      activity rationing, custom-action contribution, and no carry or double count.

## 13. Acceptance Test Matrix

### RNG

- [ ] **RNG-01:** For a nonzero mocked daily VRF word whose domain-separated residue is 0,
  highRollerMultiplierForDay returns 100.
- [ ] **RNG-02:** Residues 1 through 9 each return 10.
- [ ] **RNG-03:** A zero daily word returns 0 and openBonusDay does not invent a fallback H.
- [ ] **RNG-04:** All periods 0 through 6 for one day expose the same H.
- [ ] **RNG-05:** Repeated derivation and repeated openBonusDay calls cannot reroll H or emit a
  second daily event.
- [ ] **RNG-06:** Arm order, arm delay, entrant count, caller, timestamp within the day, and
  settlement batch size do not change H.
- [ ] **RNG-07:** A previous-day slot retains its own H after currentDayIndex advances.
- [ ] **RNG-08:** Tests assert that the entropy root is dailyWordAt(day) and no block-derived or
  deterministic cadence fallback exists.

### Entry

- [ ] **ENTRY-01:** On a 10x scheduled day, multiples 1 and 10 succeed; 0, 2, 9, 11, 100, and 256
  revert.
- [ ] **ENTRY-02:** On a 100x scheduled day, multiples 1 and 100 succeed; 10 and every other value
  revert.
- [ ] **ENTRY-03:** Normal burn is R + B; high burn is H × (R + B), in exact wei.
- [ ] **ENTRY-04:** High run-derived credit is H times the already-rounded one-run credit; when
  N_H = 1, the settlement credit also includes one pro-rata rider over X + Q_H.
- [ ] **ENTRY-05:** High status does not alter the unscaled run, board, RNG seed, score, or main
  winner.
- [ ] **ENTRY-06:** Insufficient FLIP reverts without a stored bet or changed main/side/day count.
- [ ] **ENTRY-07:** A stale multiple = 10 transaction against a 100x destination reverts rather
  than charging 100x.

### Accounting

- [ ] **ACCT-01:** For arbitrary N and N_H <= N, main bounty principal equals N × B.
- [ ] **ACCT-02:** High-roller allocation equals N_H × X.
- [ ] **ACCT-03:** For N_H = 1, X is booked as bankroll action; for N_H >= 2, N_H × X is side
  principal; main principal plus that allocation exactly equals all bounty burned.
- [ ] **ACCT-04:** Donations and Q_M are present only in the main award; Q_H is present only in a
  high-lane payment for N_H >= 1 and neither boost is multiplied by H.
- [ ] **ACCT-05:** Busted remainder appears in neither award.
- [ ] **ACCT-06:** B = 0 yields X = 0 and zero rider/player-funded side principal; a scheduled
  N_H >= 1 field may still allocate Q_H, while a zero complete amount makes no external call.
- [ ] **ACCT-07:** H = 256 and maximum legal R, B, and entrant count do not overflow.
- [ ] **ACCT-08:** A stateful fuzz invariant over entry, rider settlement, and both competitive
  claim orders conserves principal and never processes X through both routes.

### Ranking

- [ ] **RANK-01:** Main ranking is byte-for-byte unchanged for a field with no high rollers.
- [ ] **RANK-02:** A high roller is eligible for both fields; a normal seat is main-only.
- [ ] **RANK-03:** Goal/bust and hand-count ordering match the existing _rankOf behavior.
- [ ] **RANK-04:** The raw, unscaled bankroll and frozen standing retain their current tie order.
- [ ] **RANK-05:** H never enters either composite score.
- [ ] **RANK-06:** Exact high-roller ties use the same word-derived bet-id total order.
- [ ] **RANK-07:** Every partition of one field into resolveSlot batches produces identical main
  and side winners.

### Payment

- [ ] **CLAIM-01:** N_H = 0 creates no high-roller allocation, pays nothing, and leaves the
  sideboard unwritten; finalization reads it exactly once.
- [ ] **CLAIM-02:** N_H = 1 routes exactly X + Q_H into the sole seat's bankroll exposure, with
  nothing handed back, no guaranteed Q_H payout, and no second payment.
- [ ] **CLAIM-03:** With N_H = 1 and P = 0, the base and combined X + Q_H rider both return zero;
  the complete settlement credit is zero.
- [ ] **CLAIM-04:** With N_H = 1 and P = R, rider return is exactly X + Q_H and total settlement
  credit is H × P + X + Q_H.
- [ ] **CLAIM-05:** For arbitrary P, R, B, H, and Q_H, rider return is
  floor(P × (X + Q_H) / R), computed with one full-precision mulDiv and included in the existing
  batch credit; separate floors over X and Q_H are forbidden.
- [ ] **CLAIM-06:** Re-resolving or splitting settlement batches cannot process the sole rider
  twice.
- [ ] **CLAIM-07:** N_H = 2 pays exactly 2 × X + Q_H to the better high roller as coinflip stake,
  with _boostShare applied only to G_H.
- [ ] **CLAIM-08:** N_H > 2 pays the exact full side principal plus Q_H to one best eligible seat;
  the best bust wins if every high roller busts.
- [ ] **CLAIM-09:** Competitive claim before finalization reverts; after finalization its latch is
  written before payment and duplicate/reentrant calls cannot pay twice.
- [ ] **CLAIM-10:** N_H = 1 with B = 0 produces an at-risk rider containing Q_H alone; it returns
  floor(P × Q_H / R), and a zero complete credit marks processed without an external call.

### Day Tickets

- [ ] **DAY-01:** Early normal day cost equals the sum of seven R_p + B_p values.
- [ ] **DAY-02:** Early high day cost equals H_day times that exact sum.
- [ ] **DAY-03:** One early high day purchase stores one bet, one high flag, and one packed high
  day count rather than seven sideboard writes.
- [ ] **DAY-04:** Arming each of the seven windows adds that day high count exactly once.
- [ ] **DAY-05:** Every resulting day-seat run uses the same H while keeping window-specific R,
  B, goal, and board.
- [ ] **DAY-06:** Bulk day entry is refused with `BonusPeriodSpent` once the first window has
  closed; the remaining windows are entered singly through `enterBonusBattle`, each using H_day.
- [ ] **DAY-07:** House and vault day tickets never set the high flag or increment high counts.

### Custom Battles

- [ ] **CUSTOM-01:** H = 0, 2, and 256 create successfully.
- [ ] **CUSTOM-02:** H = 1 and H = 257 revert with BadHighRollerMultiplier.
- [ ] **CUSTOM-03:** H round-trips through packed storage, event data, terms view, and battle key.
- [ ] **CUSTOM-04:** Disabled custom battles accept only multiple = 1.
- [ ] **CUSTOM-05:** Enabled custom battles accept exactly 1 or their fixed H.
- [ ] **CUSTOM-06:** Advancing the protocol day or changing its daily VRF word cannot change
  custom H.
- [ ] **CUSTOM-07:** Donations remain main-only and custom side principal remains entrant-funded.
- [ ] **CUSTOM-08:** multiEntry counts paid high seats, while a non-multiEntry field still enforces
  the existing one-seat rule.

### Boost Budget Split

- [ ] **BOOST-01:** Each settlement batch books totalAction once and, only when it contains high
  seats, highAction once; highAction never exceeds totalAction.
- [ ] **BOOST-02:** For every settled seat, normal action contributes R only to A_R; high action
  contributes H × R only to A_H, plus X only for a final N_H = 1; Q_H contributes to neither.
- [ ] **BOOST-03:** For each of the prior seven days, E_R uses
  floor((dayStaked - highRollerDayStaked) / 36) and E_H uses
  floor(highRollerDayStaked / 36); no action contributes to both sums.
- [ ] **BOOST-04:** For arbitrary E_H, highRecycle = floor(E_H / 2),
  mainFromHigh = floor(2 × highRecycle / 5), highBudget = highRecycle - mainFromHigh, and the
  three values conserve exactly with no overflow.
- [ ] **BOOST-05:** For E_H divisible by 10, highBudget, mainFromHigh, and unrecycled high burn are
  exactly 30%, 20%, and 50%; residues 0 through 9 follow the stated two-stage floor rule.
- [ ] **BOOST-06:** mainBudget is max(15,000 FLIP, floor(E_R / 2) + mainFromHigh); the floor never
  raises highBudget, and zero prior high action yields highBudget = 0.
- [ ] **BOOST-07:** Both budgets use only the prior seven settled days and freeze exactly once at
  open; same-day settlements, repeated opens, delayed arms, and claim order cannot mutate them.
- [ ] **BOOST-08:** For every window, main and high lanes use the identical known/mystery flag and
  ladder rung derived solely from existing genuine VRF words; no pseudo-random or second draw exists.
- [ ] **BOOST-09:** N_H = 0 makes Q_H = 0 and leaves G_H unallocated without refund, carry, or
  transfer to main; N_H = 1 applies X + Q_H as one at-risk bankroll rider.
- [ ] **BOOST-10:** Every N_H >= 1 field allocates _boostShare(G_H, highWinnerStanding): into the
  sole seat's combined rider for N_H = 1, or in addition to N_H × X on competitive claim for
  N_H >= 2; standing 0, every partial rung, the full-score floor, and above-floor values match the
  existing activity-share ladder.
- [ ] **BOOST-11:** Activity-score rationing fixes Q_H only and cannot reduce player-funded X;
  after that, a sole X + Q_H rider follows one run. Settled custom high action contributes to
  future A_H, but custom G_H and Q_H remain zero.
- [ ] **BOOST-12:** Stateful fuzzing across empty histories, days 0 through 7, maximum legal
  action, mixed normal/high batches, N_H cardinalities, and repeated calls preserves every budget,
  allocation, realized-payout, and no-double-count invariant.

### Observability, Gas, and Regression

- [ ] **OBS-01:** One successful protocol day emits one daily H event.
- [ ] **OBS-02:** Event replay and views agree on each entry's mode and multiplier.
- [ ] **OBS-03:** Side view agrees on N_H before settlement.
- [ ] **OBS-04:** Side view exposes the correct full winner bet id for direct and day-lane winners.
- [ ] **OBS-05:** Finalized/principal/grossBoost/allocatedBoost/bankrollRider/processed fields
  match all N_H cardinalities.
- [ ] **OBS-06:** Claimed state and payment event change exactly once.
- [ ] **OBS-07:** dayStaked, highRollerDayStaked, highRollerDayBurn, main budget, and high budget
  views agree with independently recomputed seven-day accounting.
- [ ] **OBS-08:** Daily-open and high-finalization events expose the same two frozen budgets and
  exact gross/allocated high boost as live views.
- [ ] **GAS-01:** No-high entry and resolution stay within their regression budgets.
- [ ] **GAS-02:** First/later high entry stay within their incremental budgets.
- [ ] **GAS-03:** A high-containing resolution batch meets its fixed and marginal budgets.
- [ ] **GAS-04:** A contested lane's payment is O(1) and rides the batch that finalizes the main
  field; the sole lane folds X + Q_H into the existing batch credit. Neither creates a later
  payment path. Asserted against touched STORAGE, not gas — the resolve path is not measurable
  here (§11.3).
- [ ] **GAS-05:** Early day purchase performs no seven-window sideboard fan-out.
- [ ] **GAS-06:** Resolution performs no second entrant walk.
- [ ] **GAS-07:** Only one sideboard storage word exists per battle.
- [ ] **GAS-08:** MAX_SLIP_HANDS and engine worst-case bounds are unchanged.
- [ ] **GAS-09:** Deployed runtime bytecode is below 24,576 bytes.
- [ ] **GAS-10:** openBonusDay's second budget derivation/storage stays within its 25,000-gas
  incremental budget.
- [ ] **GAS-11:** Budget drawing remains a fixed seven-day loop with no entrant/battle iteration.
- [ ] **REG-01:** Busts still pay zero and their remaining bankroll is deleted.
- [ ] **REG-02:** Main pot behavior is unchanged. There is no walkover: every field that forms
  pays, and the seed and boost never fall back out of the pot on a head count.
- [ ] **REG-03:** The main boost retains the current known/mystery ladder and score rationing; its
  only formula change is the explicit 20% contribution from high-modeled burn.
- [ ] **REG-04:** Scheduled/custom donation behavior is unchanged except for explicit main-only
  documentation.
- [ ] **REG-05:** House and vault seats remain normal-only.
- [ ] **REG-06:** Existing committed table RNG and board scatter are unchanged.
- [ ] **REG-07:** Combined X + Q_H sole-rider return is part of the normal coinflip batch credit,
  and a contested side award uses coinflip credit. Craps only ever BURNS — `mintForGame` is gone
  from the table entirely, so no path here can hand FLIP back.
- [ ] **REG-08:** dayStaked includes H × R normally and H × R + X for a sole high roller, while
  highRollerDayStaked records exactly the high subset, Q_H is excluded from both, and ordinary
  player-funded action remains in A_R.
- [ ] **REG-09:** No direct ETH transfer, ETH reserve mutation, or new solvency bucket is added.

## 14. Boundaries

### In Scope

- One daily 10x/100x high-roller term for all seven scheduled Bonus Battle windows.
- Genuine daily VRF entropy with domain separation and no fallback pseudo-randomness.
- Binary normal/high entry validation.
- Full bankroll-plus-bounty scaling for high rollers.
- One main bounty pool and one high-roller allocation routed to a sole bankroll rider or a
  competitive side pool.
- Separate settled high-roller action accounting and a seven-day 30% high / 20% main / 50%
  unrecycled split of high-modeled burn.
- One floorless high-roller-only boost budget, using the same known/mystery window rung as the
  main budget and allocated whenever N_H >= 1, including as at-risk rider capital for a sole
  high roller.
- Shared run, shared comparator, and two folded winners.
- N_H = 0/1/2+ no-allocation, bankroll-rider, and competitive-claim behavior.
- Early and late day-ticket handling.
- Creator-set custom H or disabled mode.
- Required views, events, packing, invariants, tests, and gas limits.

### Out of Scope

- Additional 5x, 25x, or nested bounty tiers — replaced by one optional high-roller lane.
- Per-window 10x/100x rolls — the roll is daily.
- A deterministic every-tenth-day schedule — genuine VRF draws may cluster.
- A new VRF request per window or entry — the existing daily VRF word is the entropy root.
- Arbitrary normal entry multiples from 2 through 256 — battle entries become 1 or H.
- Multiplying either protocol boost by H, routing the main boost or donations into the side pool,
  or routing the high boost anywhere except the sole high roller or competitive high winner.
- Changing Craps payouts, boards, goals, stop rules, pass/don't-pass behavior, or hard ways.
- Changing the known/mystery ladder distributions, adding another boost RNG draw, or changing the
  existing activity-score function.
- A minimum floor, carryover, or refund of an unused N_H = 0 high-roller boost.
- Measuring realized dice profit/loss instead of the existing action / 36 modeled-burn proxy.
- Sending busted bankroll remainder to any bounty pool.
- Adding direct ETH accounting, a reserve, or a new solvency bucket.
- Custom-battle cancellation or post-creation term editing.
- A dedicated high-roller donation API.

## 15. Prohibitions

**Coverage:** 11/11 resolved; 0 unresolved.

| Must-NOT statement | Requirement | Verification |
|---|---|---|
| MUST NOT use pseudo-random fallback entropy when the daily VRF word is absent | R1 | test: RNG-03, RNG-08 |
| MUST NOT describe the draw as guaranteeing one 100x day in each fixed ten-day block | R1 | judgment: documentation review |
| MUST NOT silently convert a caller's 10x quote into a 100x burn | R2 | test: ENTRY-07 |
| MUST NOT let money scale alter odds, RNG, or competitive score | R4 | test: ENTRY-05, RANK-05 |
| MUST NOT return a sole high roller's X risk-free or process it as both bankroll and side bounty | R3, R5 | test: ACCT-03, ACCT-08, CLAIM-02 |
| MUST NOT multiply either boost by H or route Q_M/donations into the high-roller pool | R3, R11 | test: ACCT-04, BOOST-08 |
| MUST NOT let a creator or admin reroll or mutate H after a field opens | R1, R7 | test: RNG-05, CUSTOM-06 |
| MUST NOT use high-roller mode to introduce a second settlement walk or unbounded claim | R9 | test: GAS-04, GAS-06 |
| MUST NOT count high-roller action in both E_H and E_R or recycle more than floor(E_H / 2) | R11 | test: BOOST-03..BOOST-05, BOOST-12 |
| MUST NOT pay a sole Q_H risk-free or leave it unused; it must join X on the run, while N_H = 0 G_H must not carry, refund, or redirect | R5, R11 | test: CLAIM-03..CLAIM-05, CLAIM-10, BOOST-09 |
| MUST NOT activity-ration player-funded X or N_H × X; ration Q_H first, then apply the combined sole rider | R3, R5, R11 | test: CLAIM-05, BOOST-10, BOOST-11 |

Generic reentrancy, overflow, access-control, and VRF-coordinator threats remain owned by the
normal contract security review; the product-specific constraints above do not replace it.

## 16. Edge Coverage

The edge-completeness probe raised 53 applicable boundary, precision, empty-field, ordering,
idempotency, and concurrency edges across the eleven requirements. All are resolved explicitly by
the acceptance matrix.

| Requirement | Applicable categories | Status | Resolution |
|---|---|---|---|
| R1 | boundary, precision, idempotency, concurrency | Resolved / explicit | RNG-01..RNG-08 |
| R2 | boundary, precision, idempotency, concurrency | Resolved / explicit | ENTRY-01..ENTRY-07 |
| R3 | boundary, adjacency, empty, ordering, precision, idempotency, concurrency | Resolved / explicit | ACCT-01..ACCT-08 |
| R4 | adjacency, empty, ordering, idempotency, concurrency | Resolved / explicit | RANK-01..RANK-07 |
| R5 | boundary, precision, idempotency, concurrency | Resolved / explicit | CLAIM-01..CLAIM-10 |
| R6 | boundary, adjacency, empty, ordering, precision, idempotency, concurrency | Resolved / explicit | DAY-01..DAY-07 |
| R7 | boundary, precision, idempotency, concurrency | Resolved / explicit | CUSTOM-01..CUSTOM-08 |
| R8 | idempotency, concurrency | Resolved / explicit | OBS-01..OBS-08 |
| R9 | boundary, adjacency, empty, ordering, precision, idempotency, concurrency | Resolved / explicit | GAS-01..GAS-11 |
| R10 | idempotency, concurrency | Resolved / explicit | REG-01..REG-09 |
| R11 | boundary, adjacency, empty, ordering, precision, idempotency, concurrency | Resolved / explicit | BOOST-01..BOOST-12 |

## 17. Ambiguity Report

| Dimension | Score | Minimum | Status | Notes |
|---|---:|---:|---|---|
| Goal clarity | 0.98 | 0.75 | Met | One optional lane; daily 10x/100x rule locked |
| Boundary clarity | 0.95 | 0.70 | Met | Main/side/custom/protocol and boost-budget boundaries explicit |
| Constraint clarity | 0.92 | 0.65 | Met | VRF, split rounding, packing, gas, ABI, and code-size limits explicit |
| Acceptance criteria | 0.95 | 0.70 | Met | Cardinality, conservation, budget, RNG, and gas matrix supplied |
| **Ambiguity** | **0.05** | **at most 0.20** | **Passed** | Ready for implementation planning |

## 18. Decision Log

| Discussion decision | Locked result |
|---|---|
| Multiple tier pools versus one side lane | One optional high-roller lane |
| Default high-roller size | 10x |
| Tail size | 100x |
| Tail frequency | Independent 10% probability per protocol day |
| Roll granularity | One real VRF-backed roll for the day, shared by all seven windows |
| Regular modeled-burn recycle | 50% to main, subject to the existing main floor |
| High-roller modeled-burn recycle | 30% high-only boost, 20% main boost, 50% unrecycled |
| High-roller boost eligibility | Any N_H >= 1; a sole allocation rides the bet with X; no floor or carry; N_H = 0 unallocated |
| High-roller boost randomness | Same known/mystery classification and rung as main; no second draw |
| High buy-in | Multiplies both bankroll and bounty |
| Ranking | One unscaled run and identical comparator for both fields |
| Sole high roller | Extra bounty X and boost Q_H ride the same run pro rata; both zero on bust, no refund |
| Sole-rider math | floor(P × (X + Q_H) / R), added to H × P; only player-funded X counts as future budget action |
| Custom battles | Creator fixes H, or 0 disables |
| Randomness source | Existing committed daily Chainlink VRF word only; no pseudo fallback |

---

This document specifies the required behavior. Implementation may alter internal helper names or
equivalent packing details only when every accounting invariant, observable behavior, acceptance
test, gas bound, and code-size bound remains satisfied.
