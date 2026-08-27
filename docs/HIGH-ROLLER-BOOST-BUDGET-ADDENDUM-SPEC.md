# High-Roller Boost Budget and Period Allocation — Addendum Specification

**Status:** Ready for contract implementation

**Created:** 2026-08-26

**Primary target:** `contracts/CrapsBattle.sol`

**Depends on:** `docs/HIGH-ROLLER-BONUS-BATTLE-SPEC.md`

**Requirements:** 7 locked

**Ambiguity score:** 0.04 (gate: <= 0.20)

## 1. Purpose and Precedence

This is a separate, delta-only specification for the high-roller boost extension. It does not
replace the original High-Roller Bonus Battle specification and does not restate its entry,
ranking, multiplier, or side-pool design.

This addendum supersedes only these parts of the original specification:

1. Any statement that divides a daily boost budget evenly by seven.
2. Any statement that scheduled windows may be known or non-mystery.
3. Any statement that the main and high lanes share a known-versus-mystery classification.
4. The boost-budget, period-allocation, and high-boost routing tests that depend on those rules.

Everything else in the original specification remains authoritative.

For this document, **the daily event** means scheduled period 6, the day-long final event.
Periods 0 through 5 are the six routine windows.

The existing contract is already all-mystery. This addendum preserves that design. It must not
reintroduce a known-window or non-mystery path.

## 2. Goal

Split boost funding into main and high-roller daily budgets, funded from their respective prior
player action; direct 30% of modeled high-roller burn to the high-roller boost, 20% to the main
boost, and retain 50%; then allocate half of each daily budget to period 6 and divide the other
half among periods 0 through 5 using Large:Medium:Small weights of 4:2:1.

Every period remains a mystery boost. A window uses one genuine-VRF-derived ladder rung for both
its main and high-roller bases. If exactly one high roller enters, both that player's extra bounty
and allocated high-roller boost ride the same run as additional at-risk bankroll.

## 3. Definitions

All amounts are FLIP wei unless stated otherwise.

| Symbol | Meaning |
|---|---|
| `d` | Protocol settlement day |
| `p` | Scheduled period, 0 through 6 |
| `T(d)` | Total player-funded bankroll action settled on day `d` |
| `A_H(d)` | High-roller player-funded bankroll action included in `T(d)` |
| `A_R(d)` | Regular action, exactly `T(d) - A_H(d)` |
| `E_R(d)` | Seven-day modeled regular burn used to open day `d` |
| `E_H(d)` | Seven-day modeled high-roller burn used to open day `d` |
| `D_M(d)` | Frozen main boost budget for day `d` |
| `D_H(d)` | Frozen high-roller boost budget for day `d` |
| `F` | Existing main minimum budget, 15,000 FLIP |
| `w_p` | Routine tier weight: Small = 1, Medium = 2, Large = 4 |
| `W` | Sum of `w_p` for routine periods 0 through 5 |
| `B_M(d,p)` | Main mystery-ladder base for one period |
| `B_H(d,p)` | High-roller mystery-ladder base for one period |
| `q_p` | Existing mystery rung in quarters: 1, 4, 40, or 400 |
| `G` | `BATTLE_STAKE_UNIT` |
| `G_H` | Gross high-roller boost after the mystery rung and granule floor |
| `Q_H` | High-roller boost claimable after the existing activity-score share |
| `N_H` | Final high-roller entrant count for the window |
| `R` | One base run's bankroll |
| `B` | One base bounty |
| `H` | The battle's high-roller entry multiplier |
| `X` | One high roller's extra bounty allocation, `(H - 1) * B` |
| `P` | Existing rounded payout of one base run; zero on a bust |

`D_M` and `D_H` are expected-emission budgets, not hard realized-payout caps. The mystery ladder
has mean 1, but an individual day may realize far above or below its frozen budgets.

## 4. Locked Product Rules

### 4.1 Disjoint Daily Action Accounting

Settlement must maintain:

```text
A_R(d) = T(d) - A_H(d)
0 <= A_H(d) <= T(d)
```

Action is attributed to the protocol day on which the run settles, matching existing
`dayStaked` behavior.

Book action as follows:

| Settled seat | Add to `T(d)` | Add to `A_H(d)` |
|---|---:|---:|
| Normal seat | `R` | `0` |
| High seat, `N_H >= 2` | `H * R` | `H * R` |
| Sole high seat, `N_H = 1` | `H * R + X` | `H * R + X` |

The sole seat's `X` is action because it is converted from bounty principal into genuine
at-risk bankroll. For `N_H >= 2`, the extra bounties remain competitive bounty principal and are
not bankroll action.

The following never enter `T`, `A_H`, or `A_R`:

- Main protocol boost.
- High-roller protocol boost, including a sole rider's `Q_H`.
- Donations.
- Competitive bounty principal.
- Realized dice profit or loss.

Custom high-roller runs contribute to `A_H` under the same rules even though custom battles
receive no protocol boost. No player-funded action may appear in both `A_R` and `A_H`.

### 4.2 Exact 30/20/50 Budget Draw

When opening protocol day `d`, use only settled action from days `d - 1` through `d - 7` that
exist. Division occurs per historical day before summation, preserving current accounting:

```text
E_R(d) = sum(i = 1..7, d >= i) floor(A_R(d - i) / 36)
E_H(d) = sum(i = 1..7, d >= i) floor(A_H(d - i) / 36)

regularRecycle = floor(E_R / 2)
highRecycle    = floor(E_H / 2)
mainFromHigh   = floor(highRecycle * 2 / 5)

D_H = highRecycle - mainFromHigh
D_M = max(15,000 FLIP, regularRecycle + mainFromHigh)
```

For `E_H` divisible by 10, this is exactly:

```text
30% of E_H -> D_H
20% of E_H -> D_M
50% of E_H -> retained / not recycled
```

For other values, the two-stage floor above is authoritative. Any split remainder inside the
recycled half goes to `D_H`; it must not increase the recycled half itself.

The 15,000 FLIP minimum is main-only. It never tops up `D_H`. Therefore no prior high action
produces `D_H = 0`, even when the main floor is active.

Both budgets are drawn and frozen exactly once when the day opens. Same-day settlement, delayed
arming, settlement order, claim order, or a repeated open call must not change either budget.

### 4.3 Half to the Daily Event; Half Weighted 4:2:1

Apply this allocation independently to `D_M` and `D_H`. Let `D` be either frozen budget.

```text
routinePool = floor(D / 2)
eventBase   = D - routinePool
```

Thus period 6 receives exactly half when `D` is even and the one-wei remainder when `D` is odd.
Periods 0 through 5 divide `routinePool`.

For each routine period, derive its weight from the tier already fixed by the day's genuine VRF
terms:

```text
Small  (tier 1): w_p = 1
Medium (tier 2): w_p = 2
Large  (tier 3): w_p = 4

W = sum(p = 0..5) w_p
```

Use period order 0 through 5 and cumulative-floor apportionment so integer division conserves
the complete routine pool without a dust bucket:

```text
C_0 = 0
C_p = sum(j = 0..p-1) w_j

base(D, p) =
    floor(routinePool * (C_p + w_p) / W)
  - floor(routinePool * C_p / W)                 for p = 0..5

base(D, 6) = eventBase
```

The implementation must use overflow-safe integer multiplication/division with floor semantics.
Equivalent arithmetic is acceptable only if it returns the same value for every integer input.

The resulting invariants are:

```text
sum(p = 0..6) base(D, p) = D
sum(p = 0..5) base(D, p) = floor(D / 2)
base(D, 6)                  = D - floor(D / 2)
```

Use the same six routine weights for both lanes:

```text
B_M(d,p) = base(D_M(d), p)
B_H(d,p) = base(D_H(d), p)
```

Entrant count, high-roller participation, activity score, settlement result, claim order, and
donations do not affect these bases. The weights are frozen by the scheduled terms before entry.

Example, ignoring sub-wei rounding:

```text
D = 22,000 FLIP
routine tiers = [S, S, S, M, M, L]
weights       = [1, 1, 1, 2, 2, 4], W = 11

period 0 S = 1,000
period 1 S = 1,000
period 2 S = 1,000
period 3 M = 2,000
period 4 M = 2,000
period 5 L = 4,000
period 6 event = 11,000
```

### 4.4 Every Period Is Mystery-Only

There are no known scheduled periods. Periods 0 through 6 all use the current mystery ladder:

| Settlement roll | Probability | `q_p` in quarters | Multiplier |
|---|---:|---:|---:|
| 0..767 | 76.8% | 1 | 0.25x |
| 768..975 | 20.8% | 4 | 1x |
| 976..995 | 2.0% | 40 | 10x |
| 996..999 | 0.4% | 400 | 100x |

The expected multiplier is exactly 1:

```text
(768*1 + 208*4 + 20*40 + 4*400) / (1000*4) = 1
```

For a window, derive `q_p` once from the existing committed settlement VRF word, battle key, and
existing boost domain tag. The main and high-roller lane use the exact same `q_p`:

```text
mainGrossUnits = floor(B_M(d,p) * q_p / (4 * G))
highGrossUnits = floor(B_H(d,p) * q_p / (4 * G))

main gross boost = mainGrossUnits * G
G_H              = highGrossUnits * G
```

Do not combine the two bases before flooring. Each lane retains its own granule floor and routing.

The rung must be unknowable while entry remains open and reproducible after the settlement word
lands. No daily word, timestamp, block data, caller, entrant count, or pseudo-random fallback may
replace or modify the settlement-word entropy. No second VRF request or second boost draw is added
for the high lane.

At entry, quote only the band around each base:

```text
low  = 0.25 * base, subject to the existing granule floor
mean = 1.00 * base, subject to the existing granule floor
high = 100  * base, subject to the existing granule floor
```

Any old `knownMult`, `isMysteryWindow`, known-quote, or window-classification branch must not
control economics. If an obsolete ABI surface must be retained for compatibility, every valid
scheduled period reports mystery and the surface cannot select a different payout path.

### 4.5 High-Boost Participation and Sole-Rider Routing

After the common mystery rung is applied, use the existing frozen activity-score function to
determine the high winner's claimable high boost:

```text
Q_H = N_H == 0 ? 0 : activityShare(G_H, highWinnerStanding)
```

Route by the final `N_H` frozen after entry closes:

| `N_H` | High-roller boost result |
|---:|---|
| 0 | `Q_H = 0`; the complete high boost is unminted |
| 1 | Combine `Q_H` with `X` and apply both to the sole seat's existing run |
| 2+ | Add `Q_H` once to the competitive high-roller award |

For exactly one high roller:

```text
Y = X + Q_H
riderReturn = floor(P * Y / R)
total high-seat run credit = H * P + riderReturn
```

Use one full-precision `mulDiv` over `X + Q_H`; do not floor two separate rider returns. A bust
sets `P = 0`, so both bounty and boost rider capital return zero. A non-bust scales both by the
same realized one-run return. The rider changes neither the engine bankroll nor the goal, odds,
dice, score, or main/high ranking.

For two or more high rollers:

```text
competitive high award = N_H * X + Q_H
```

Activity rationing applies only to protocol-funded `Q_H`. It never reduces player-funded `X`.
Neither `G_H` nor `Q_H` is multiplied by `H`. The high boost is paid or applied at most once.

Unused high boost caused by `N_H = 0`, activity rationing, granule flooring, a busted sole rider,
or `D_H = 0` is not minted, refunded, carried forward, or redirected to the main boost.

### 4.6 Observability

Names may follow local conventions, but canonical views/events must expose enough information to
reconstruct:

- `T(d)`, `A_H(d)`, and therefore `A_R(d)`.
- Frozen `D_M(d)` and `D_H(d)`.
- The six routine tiers, their weights, and `W`.
- `B_M(d,p)` and `B_H(d,p)` for all seven periods.
- The main and high mystery low/mean/high bands.
- Final `N_H`, high winner, gross `G_H`, activity-rationed `Q_H`, sole-rider versus competitive
  routing, and whether the lane has paid.

The existing main `_bonusBoostBand(day, period)` may remain the main-lane reader — it is
`internal` as shipped, like the rest of the Craps reader surface, and a suite reaches it through
`test/craps/CrapsViews.sol`. A parallel high-lane band or a combined two-lane view is acceptable.
An indexer must be able to reproduce the exact integer result from canonical state and the
published VRF word.

An unopened day must be distinguishable from an opened day whose `D_H` is legitimately zero.
Custom battles report zero for both protocol-funded bases and bands.

### 4.7 Complexity and Storage Bounds

This extension must preserve bounded resolution:

- No additional entrant walk.
- No entrant-count-dependent loop when drawing or allocating a budget.
- No per-window daily budget storage. Store at most the two daily lane budgets plus packed or
  derivable fixed-size metadata.
- Routine-weight work is bounded to the six scheduled routine periods.
- `N_H = 0` must not touch high-sideboard storage on ordinary entry/settlement paths beyond any
  already-required daily budget state.
- A sole rider is folded into the existing settlement batch credit.
- A competitive high claim remains `O(1)`.
- No additional VRF request is introduced.

The implementation may derive `W` from the immutable daily word or pack the 5-bit value
(`6 <= W <= 24`) into existing day metadata. That choice is implementation detail; all external
results must match Section 4.3 exactly.

## 5. Requirements

1. **Disjoint action accounting**: Maintain exact, non-overlapping regular and high action totals.
   - Current: The base implementation's boost draw uses one `dayStaked` total; high-action fields
     in the in-progress implementation do not yet define the complete sole-rider rule.
   - Target: Section 4.1 partitions every player-funded wei and excludes protocol emissions.
   - Acceptance: `ACT-01` through `ACT-06` pass.

2. **30/20/50 budget construction**: Freeze separate main and high daily budgets from the prior
   seven settlement days.
   - Current: The established main path recycles 50% of the combined `/36` proxy into one
     floor-backed budget.
   - Target: Section 4.2 applies the exact two-lane formula and a main-only floor.
   - Acceptance: `BUD-01` through `BUD-08` pass.

3. **Event and tier-weighted allocation**: Replace `budget / 7` with exact half-event,
   half-4:2:1 allocation for both lanes.
   - Current: `_boostBase` divides the main budget evenly among seven periods.
   - Target: Section 4.3 conserves each lane budget exactly using immutable routine tiers.
   - Acceptance: `ALLOC-01` through `ALLOC-10` pass.

4. **All-mystery shared rung**: Preserve the existing all-mystery ladder and use one window rung
   across both lane bases.
   - Current: The live contract is already all-mystery, but the original high-roller draft has
     stale known/non-mystery wording.
   - Target: Section 4.4 is the sole scheduled boost-randomness rule.
   - Acceptance: `MYST-01` through `MYST-08` pass.

5. **Cardinality-correct high boost**: Allocate the high boost at zero, one, and multiple high
   entrants exactly as specified.
   - Current: The base contract has no completed high-boost payout route.
   - Target: Section 4.5 leaves zero unminted, makes a sole allocation ride the run, and pays a
     competitive allocation once.
   - Acceptance: `ROUTE-01` through `ROUTE-10` pass.

6. **Reconstructable state**: Publish the frozen inputs and final outputs needed by clients.
   - Current: Existing views expose the main daily budget and main mystery band only.
   - Target: Section 4.6 makes both lanes and their route exactly replayable.
   - Acceptance: `OBS-01` through `OBS-06` pass.

7. **Bounded implementation**: Add the extension without participant-scaled budget or claim work.
   - Current: The main settlement uses one dense entrant pass and the daily schedule is fixed at
     seven periods.
   - Target: Section 4.7 preserves one settlement walk, fixed-size daily work, and `O(1)` claim.
   - Acceptance: `GAS-01` through `GAS-07` pass.

## 6. Acceptance Test Matrix

### Action Accounting

- [ ] **ACT-01:** With only normal seats, `A_H = 0`, `A_R = T`, and every settled bankroll wei is
  booked once.
- [ ] **ACT-02:** With mixed normal/high seats and `N_H >= 2`, normal `R` enters only `A_R` and
  each high `H*R` enters only `A_H`; competitive `X` and both boosts enter neither.
- [ ] **ACT-03:** With `N_H = 1`, exactly `H*R + X` enters both `T` and `A_H`; `Q_H` enters
  neither, including when the rider wins.
- [ ] **ACT-04:** Zero-amount components, zero bounties, busts, wins, maximum legal multipliers,
  and maximum supported bankrolls preserve `0 <= A_H <= T` without overflow.
- [ ] **ACT-05:** Repeated settlement calls, partial batches, and different legal batch boundaries
  cannot double-book action or change its day attribution.
- [ ] **ACT-06:** Custom high seats contribute to `A_H`, but custom battles receive zero protocol
  boost.

### Budget Construction

- [ ] **BUD-01:** Day `d` includes each available day `d-1` through `d-7` exactly once and
  excludes `d`, `d-8`, and future days.
- [ ] **BUD-02:** Division by 36 occurs separately for each historical day before summation; test
  daily residues 0 through 35 against an independent model.
- [ ] **BUD-03:** `regularRecycle`, `highRecycle`, `mainFromHigh`, `D_H`, and `D_M` match Section
  4.2 for `E_R/E_H` values 0 through 20 and large fuzzed values.
- [ ] **BUD-04:** For `E_H` divisible by 10, the split is exactly 30% high, 20% main, and 50%
  retained; for residues 1 through 9, conservation follows the two-stage floor rule.
- [ ] **BUD-05:** Empty history produces `D_M = 15,000 FLIP` and `D_H = 0`.
- [ ] **BUD-06:** Values just below, at, and above the main floor affect only `D_M`; the floor
  never creates or raises `D_H`.
- [ ] **BUD-07:** Repeated open calls, delayed arms, late settlements, and main/high claim order do
  not mutate frozen budgets.
- [ ] **BUD-08:** The implementation is order-invariant across otherwise identical historical
  settlement sequences and cannot overflow at the maximum supported action.

### Period Allocation

- [ ] **ALLOC-01:** For each lane and every `D`, period 6 receives `D - floor(D/2)` and periods
  0 through 5 sum to `floor(D/2)`.
- [ ] **ALLOC-02:** All seven bases sum exactly to `D`; no rounding dust is stored, carried, or
  minted elsewhere.
- [ ] **ALLOC-03:** Routine tiers map exactly `S=1`, `M=2`, `L=4`; `W` is in `[6,24]`.
- [ ] **ALLOC-04:** `D=22,000 FLIP` with `[S,S,S,M,M,L]` produces routine bases
  `[1,000,1,000,1,000,2,000,2,000,4,000] FLIP` and an 11,000 FLIP event base.
- [ ] **ALLOC-05:** `D=0`, `D=1 wei`, odd values, values smaller than `W`, and maximum budget
  values match the cumulative-floor formula exactly.
- [ ] **ALLOC-06:** Period order is 0 through 5 for cumulative rounding; permuting equal-value
  tier windows cannot alter `W`, while changing a period's tier changes only the deterministic
  apportionment implied by the new ordered weight list.
- [ ] **ALLOC-07:** Period 5 and period 6 remain distinct: period 5 is tier-weighted routine;
  period 6 receives the event half and is never included in `W`.
- [ ] **ALLOC-08:** Main and high bases are calculated independently from `D_M` and `D_H`; one
  lane's integer residue cannot enter the other.
- [ ] **ALLOC-09:** Entrants, high-roller count, standing, donations, results, and claim timing do
  not change any base after the day opens.
- [ ] **ALLOC-10:** An invalid period returns the contract's documented zero/revert behavior and
  cannot alias a valid base; custom battles have zero protocol-funded base.

### Mystery RNG

- [ ] **MYST-01:** Every valid scheduled period 0 through 6 follows the mystery path; no period
  exposes or pays a known rung before its settlement word exists.
- [ ] **MYST-02:** Rolls 0, 767, 768, 975, 976, 995, 996, and 999 select the exact ladder rows in
  Section 4.4.
- [ ] **MYST-03:** The probability table's weighted mean is exactly 1 in integer quarters.
- [ ] **MYST-04:** For the same window, main and high gross boosts use the identical `q_p` but
  floor independently at `G`.
- [ ] **MYST-05:** Repeating derivation for the same settlement word and battle key is identical;
  entrant/settlement order cannot reroll it.
- [ ] **MYST-06:** A missing settlement word produces no fallback quote-as-result or payout.
- [ ] **MYST-07:** Source inspection and tests prove the entropy root is the existing genuine VRF
  settlement word and that no block-derived, caller-derived, cadence, or pseudo-random source is
  present.
- [ ] **MYST-08:** Main and high low/mean/high views match their weighted bases and the exact
  granule behavior; the event is mystery under the same ladder.

### High-Boost Routing

- [ ] **ROUTE-01:** `N_H = 0` produces `Q_H = 0`, no high liability, and no carry/refund/main
  transfer.
- [ ] **ROUTE-02:** `N_H = 1` activity-rations `G_H`, combines `X + Q_H` once, and computes
  `floor(P*(X+Q_H)/R)` with one full-precision division.
- [ ] **ROUTE-03:** A sole bust returns zero rider; break-even and profitable run vectors scale
  both components by the same `P/R` ratio.
- [ ] **ROUTE-04:** `N_H = 2` is the exact competition threshold and pays `2*X + Q_H` once to the
  high winner; larger counts use `N_H*X + Q_H`.
- [ ] **ROUTE-05:** Activity score may reduce only `Q_H`; it cannot reduce `X` or change winner
  ranking.
- [ ] **ROUTE-06:** Neither `G_H` nor `Q_H` is multiplied by `H` on 10x or 100x days.
- [ ] **ROUTE-07:** `Q_H` never enters later action or modeled-burn calculations, whether paid
  competitively, lost on a sole bust, or returned by a sole win.
- [ ] **ROUTE-08:** Main boost and donations remain main-only; busted bankroll remainder does not
  enter either boost allocation.
- [ ] **ROUTE-09:** Settlement/claim order, duplicate calls, and partial batches cannot select a
  different cardinality route or pay either route twice.
- [ ] **ROUTE-10:** `B=0`, `D_H=0`, `Q_H=0`, zero standing, and every activity-share boundary
  complete without spurious external zero-value payments.

### Observability and Cost

- [ ] **OBS-01:** Views expose `T`, `A_H`, `D_M`, and `D_H`, and an independent seven-day model
  reproduces them.
- [ ] **OBS-02:** For every period, views/events expose or permit exact reconstruction of tiers,
  weights, `W`, both bases, and both mystery bands.
- [ ] **OBS-03:** Event replay agrees with views before entry, after arm, after final settlement,
  and after claim.
- [ ] **OBS-04:** An unopened day is distinguishable from an opened zero-high-budget day.
- [ ] **OBS-05:** High finalization exposes `N_H`, winner, gross and allocated boost, route, and
  processed state exactly once.
- [ ] **OBS-06:** Repeated reads and different event-consumption order reconstruct identical
  results; custom and invalid periods follow their documented zero/revert behavior.
- [ ] **GAS-01:** Opening remains a fixed seven-period operation with at most six routine-weight
  evaluations and no entrant/battle iteration.
- [ ] **GAS-02:** No seven-element per-day window-budget mapping or array is added.
- [ ] **GAS-03:** An ordinary entry and settlement does not touch `_highField` or `_highStaked`
  unless required by a high seat.
- [ ] **GAS-04:** Resolution retains one entrant walk and one batched credit path.
- [ ] **GAS-05:** A sole rider adds no later claim transaction; competitive high claim remains
  `O(1)` and below the original specification's gas bound.
- [ ] **GAS-06:** No additional VRF request or callback path exists.
- [ ] **GAS-07:** Before/after gas snapshots and runtime bytecode checks remain within the limits
  locked by the original high-roller specification.

## 7. Boundaries

### In Scope

- Disjoint regular/high settled-action accounting for future boost funding.
- Exact 30% high / 20% main / 50% retained treatment of modeled high burn.
- Existing 50% regular modeled-burn recycle into main.
- Main-only 15,000 FLIP daily floor.
- Separate frozen main and high daily boost budgets.
- Half of each lane budget to period 6.
- Half of each lane budget across periods 0–5 at Large:Medium:Small = 4:2:1.
- All-mystery scheduled windows using the current ladder and genuine settlement VRF word.
- One shared mystery rung per window across both lane bases.
- High-boost behavior for `N_H = 0`, `1`, and `2+`.
- A sole high roller's combined bounty-plus-boost bankroll rider.
- Views, events, tests, integer invariants, and bounded-cost constraints required above.

### Out of Scope

- Entry multiplier selection, including the daily 10x/100x roll — owned by the original spec.
- Custom battle high-multiplier validation — owned by the original spec.
- Ranking, tie-breaking, dice, boards, goals, Craps payouts, or bust rules — unchanged.
- A known/non-mystery boost mode — intentionally removed from the product.
- Changing the mystery ladder probabilities or multipliers — this addendum preserves them.
- A new VRF request or any pseudo-random fallback — prohibited.
- Multiplying protocol boost by the entry multiplier — high rollers receive a separate budget,
  not `H` copies of a boost.
- A high-budget floor, high-budget carry, or redistribution of unused high boost.
- Funding custom battles with either protocol boost.
- Realized house P&L accounting — the existing action-divided-by-36 proxy remains authoritative.
- ETH reserve, solvency-bucket, or direct-ETH accounting changes — this spec concerns FLIP boost
  emission only.
- Per-window budget storage — deterministic derivation is sufficient.

## 8. Edge Coverage

**Coverage:** 36/36 applicable edges resolved; 0 unresolved.

| Category | Requirement | Status | Resolution |
|---|---|---|---|
| Boundary | R1 | Resolved / explicit | `ACT-01` through `ACT-04` cover zero, mixed, sole, and maximum action |
| Precision | R1 | Resolved / explicit | `ACT-02` through `ACT-04` require exact wei conservation and overflow safety |
| Idempotency | R1 | Resolved / explicit | `ACT-05` forbids double booking |
| Concurrency | R1 | Resolved / explicit | `ACT-05` covers partial batches and reordered legal calls |
| Boundary | R2 | Resolved / explicit | `BUD-03` through `BUD-06` cover zero, residues, and the floor threshold |
| Adjacency | R2 | Resolved / explicit | `BUD-01` fixes inclusion at `d-7` and exclusion at `d-8` |
| Empty | R2 | Resolved / explicit | `BUD-05` fixes empty-history behavior |
| Ordering | R2 | Resolved / explicit | `BUD-08` requires order invariance |
| Precision | R2 | Resolved / explicit | `BUD-02` through `BUD-04` lock every floor and residue |
| Idempotency | R2 | Resolved / explicit | `BUD-07` freezes budgets once |
| Concurrency | R2 | Resolved / explicit | `BUD-07` covers late settlement, arm, and claim ordering |
| Boundary | R3 | Resolved / explicit | `ALLOC-01`, `ALLOC-05`, and `ALLOC-07` cover value and period boundaries |
| Adjacency | R3 | Resolved / explicit | `ALLOC-07` separates routine period 5 from event period 6 |
| Empty | R3 | Resolved / explicit | `ALLOC-05` specifies a zero budget and sub-weight pools |
| Ordering | R3 | Resolved / explicit | `ALLOC-06` fixes cumulative period order |
| Precision | R3 | Resolved / explicit | `ALLOC-01` through `ALLOC-05` lock exact floors and conservation |
| Idempotency | R3 | Resolved / explicit | `ALLOC-09` freezes bases after open |
| Concurrency | R3 | Resolved / explicit | `ALLOC-09` excludes participation and claim timing from bases |
| Boundary | R4 | Resolved / explicit | `MYST-01`, `MYST-02`, and `MYST-06` cover periods and ladder thresholds |
| Precision | R4 | Resolved / explicit | `MYST-03`, `MYST-04`, and `MYST-08` cover mean and granule floors |
| Idempotency | R4 | Resolved / explicit | `MYST-05` requires repeatable derivation |
| Concurrency | R4 | Resolved / explicit | `MYST-05` makes order unable to reroll the window |
| Boundary | R5 | Resolved / explicit | `ROUTE-01` through `ROUTE-04` cover `N_H=0/1/2+` and bust/win edges |
| Precision | R5 | Resolved / explicit | `ROUTE-02`, `ROUTE-03`, and `ROUTE-10` lock single-floor rider arithmetic |
| Idempotency | R5 | Resolved / explicit | `ROUTE-09` prohibits duplicate processing |
| Concurrency | R5 | Resolved / explicit | `ROUTE-09` makes partial settlement and claim order irrelevant |
| Adjacency | R6 | Resolved / explicit | `OBS-03` and `OBS-05` cover open/arm/finalize/claim transitions |
| Empty | R6 | Resolved / explicit | `OBS-04` and `OBS-06` cover unopened, zero-high, custom, and invalid states |
| Ordering | R6 | Resolved / explicit | `OBS-06` requires order-independent replay |
| Idempotency | R6 | Resolved / explicit | `OBS-06` requires repeatable reads |
| Concurrency | R6 | Resolved / explicit | `OBS-03` fixes canonical state across lifecycle ordering |
| Adjacency | R7 | Resolved / explicit | `GAS-04` covers batch boundaries without another pass |
| Empty | R7 | Resolved / explicit | `GAS-03` keeps the no-high path sparse |
| Ordering | R7 | Resolved / explicit | `GAS-04` and `GAS-05` preserve one settlement/claim route |
| Idempotency | R7 | Resolved / explicit | `GAS-03` through `GAS-05` prevent duplicate work and state |
| Concurrency | R7 | Resolved / explicit | `GAS-01`, `GAS-04`, and `GAS-05` keep work bounded under batching |

## 9. Prohibitions (Must-NOT)

**Coverage:** 9/9 applicable prohibitions resolved; 0 unresolved.

| Prohibition | Requirement | Status | Verification |
|---|---|---|---|
| MUST NOT reintroduce a known or non-mystery scheduled window | R4 | Resolved | Test: `MYST-01` |
| MUST NOT use pseudo-random, block-derived, caller-derived, or fallback entropy | R4 | Resolved | Test: `MYST-06`, `MYST-07` |
| MUST NOT request or draw a second boost RNG value for the high lane | R4 | Resolved | Test: `MYST-04`, `GAS-06` |
| MUST NOT let entrant count or any post-open state determine period weights or bases | R3 | Resolved | Test: `ALLOC-09` |
| MUST NOT apply the main floor or another subsidy to `D_H` | R2 | Resolved | Test: `BUD-05`, `BUD-06` |
| MUST NOT recycle protocol-funded `Q_H` into later budget action | R1/R5 | Resolved | Test: `ACT-03`, `ROUTE-07` |
| MUST NOT multiply either protocol boost by `H` or route the main boost/donations high | R5 | Resolved | Test: `ROUTE-06`, `ROUTE-08` |
| MUST NOT use activity score to reduce player-funded `X` | R5 | Resolved | Test: `ROUTE-05` |
| MUST NOT carry, refund, or redirect unused high boost | R5 | Resolved | Test: `ROUTE-01` |

## 10. Ambiguity Report

| Dimension | Score | Minimum | Status | Notes |
|---|---:|---:|---|---|
| Goal clarity | 0.98 | 0.75 | Met | Exact economic split and allocation are locked |
| Boundary clarity | 0.96 | 0.70 | Met | Delta from original spec and exclusions are explicit |
| Constraint clarity | 0.94 | 0.65 | Met | RNG, rounding, storage, and complexity constraints are exact |
| Acceptance criteria | 0.96 | 0.70 | Met | 55 pass/fail checks plus 36 resolved edge probes |
| **Ambiguity** | **0.04** | **<= 0.20** | **Passed** | No unresolved product decision |

## 11. Decision Log

| Round | Perspective | Decision locked |
|---|---|---|
| 1 | Researcher | Give high rollers a boost funded from their own prior modeled burn |
| 2 | Simplifier | Split high modeled burn 30% high boost, 20% main boost, 50% retained |
| 3 | Boundary keeper | One high roller still receives the high boost; no high floor or carry |
| 4 | Failure analyst | Apply both sole bounty and boost to the same run, so a bust returns zero |
| 5 | Seed closer | Give half of each lane budget to period 6 and weight the routine half 4:2:1 L:M:S |
| 6 | Seed closer | Keep all seven periods mystery-only; create this as a separate addendum |

---

*This addendum changes boost funding, allocation, and routing only. The original high-roller
specification remains controlling for every other behavior.*
