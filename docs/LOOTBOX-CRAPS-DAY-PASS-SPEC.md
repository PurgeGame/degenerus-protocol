# Lootbox-Funded Craps Day Passes — Contract Specification

**Status:** Ready for contract implementation

**Created:** 2026-08-26

**Primary targets:**

- `contracts/modules/DegenerusGameLootboxModule.sol`
- `contracts/storage/DegenerusGameStorage.sol`
- `contracts/DegenerusGame.sol`
- `contracts/CrapsBattle.sol`
- relevant Game/Craps interfaces, storage-layout goldens, and tests

**Depends on:**

- `docs/HIGH-ROLLER-BONUS-BATTLE-SPEC.md`
- `docs/HIGH-ROLLER-BOOST-BUDGET-ADDENDUM-SPEC.md`

**Requirements:** 14 locked

**Ambiguity score:** 0.04 (gate: <= 0.20)

## 1. Purpose and Precedence

Replace ten percentage points of the regular lootbox's flat-FLIP reward probability with
Craps full-day passes. Small pass rewards pay normal passes. Once a single box's unrounded pass
budget exceeds twenty normal-pass units, the complete reward switches to high-roller passes.
Every fractional pass is rounded with genuine VRF-backed entropy.

A pass may be committed only to a future protocol day whose daily word has not landed. It covers
one early full-day entry across all seven scheduled Bonus Battle windows. A normal pass covers a
1x day entry; a high-roller pass covers the target day's genuine 10x-or-100x high-roller entry.

This specification supersedes the two documents above only for pass-funded entries:

1. A pass-funded entry does not burn the player's FLIP entry cost.
2. Its notional bankroll action counts toward later boost budgets exactly as if the replaced
   lootbox FLIP had first been credited and then burned to buy the seat.
3. It uses the same battle, bounty, boost, ranking, payout, and high-roller rules.

All rules for paid entries remain unchanged.

## 2. Existing Behavior and Required Delta

### 2.1 Current regular lootbox distribution

`DegenerusGameLootboxModule._resolveLootboxRoll` currently reduces a sixteen-bit VRF-derived
slice modulo twenty and assigns:

| Roll | Main reward | Nominal probability |
|---:|---|---:|
| 0..7 | Tickets | 40% |
| 8..10 | DGNRS | 15% |
| 11..13 | One WWXRP Degenerette spin | 15% |
| 14..16 | Flat FLIP from `_largeFlipOut` | 15% |
| 17..18 | Three FLIP Degenerette spins | 10% |
| 19 | One ETH Degenerette spin, or tickets on recirculated boxes | 5% |

The box first removes its boon budget. All main rewards are calculated from the remaining
`mainAmount`. Flat FLIP is subsequently rounded to a whole-FLIP or 100-FLIP granule before it is
credited.

### 2.2 Target regular lootbox distribution

| Roll | Main reward | Nominal probability |
|---:|---|---:|
| 0..7 | Tickets | 40% |
| 8..10 | DGNRS | 15% |
| 11..13 | One WWXRP Degenerette spin | 15% |
| 14 | Flat FLIP from `_largeFlipOut` | 5% |
| 15..16 | Craps day-pass conversion | 10% |
| 17..18 | Three FLIP Degenerette spins | 10% |
| 19 | One ETH Degenerette spin, or tickets on recirculated boxes | 5% |

The existing `uint16 % 20` reduction and its already-accepted negligible modulo bias remain.
Presale-box rewards are a separate 50/40/10 resolver and are not changed by this specification.

## 3. Definitions

All FLIP amounts below are token wei unless stated otherwise.

| Symbol | Meaning |
|---|---|
| `V` | One pass-winning box's unrounded would-be flat-FLIP output from `_largeFlipOut(mainAmount, seed, currentLevel)` |
| `N` | Normal day-pass value unit |
| `H` | Scheduled high-roller multiplier for a target day: 10 with 90% probability or 100 with 10% probability |
| `E[H]` | Expected scheduled multiplier, exactly 19 |
| `Q_N` | Normal-pass quantity before Bernoulli rounding, `V / N` |
| `Q_H` | High-roller-pass quantity before Bernoulli rounding, `V / (19 * N)` |
| `today` | Wall-clock protocol day returned by the same GameTime day-index convention used by Craps |
| `targetDay` | Future protocol day to which one pass has been irrevocably committed |
| `credit` | Uncommitted pass inventory held by a player and usable for a future reservation |
| `reservation` | One normal or high-roller pass irrevocably assigned to one future protocol day |
| `coveredCost` | The exact normal or high-roller FLIP burn that the pass replaces when its full-day entry is taken |

## 4. Pass Value Constants

### 4.1 Normal pass value

`N` is the expected current cost of entering all seven scheduled windows at 1x, including each
window's bankroll and bounty:

| Component | Expected FLIP |
|---|---:|
| Routine period 0 | 2,433.333333333333333333 |
| Routine periods 1..5, combined | 6,133.333333333333333333 |
| All six routine periods | 8,566.666666666666666667 |
| Daily event, period 6 | 14,235.45 |
| **Complete normal day before design rounding** | **22,802.116666666666666667** |

The exact expectation is `1,368,127 / 60 FLIP`. For a clean, stable denomination, round the
expected full-day cost to the nearest 100 FLIP (ties round up):

```solidity
uint256 constant NORMAL_DAY_PASS_VALUE = 22_800 ether;
```

The 2.116666666666666667-FLIP difference is approximately 0.0093% of the exact expectation and is
accepted. No finer token-wei precision is required for pass conversion.

### 4.2 High-roller pass value

The target day's `H` is unknown when a pass is committed. Its expectation is:

```text
E[H] = 0.9 * 10 + 0.1 * 100 = 19
```

Therefore:

```solidity
uint256 constant HIGH_ROLLER_DAY_PASS_VALUE =
    19 * NORMAL_DAY_PASS_VALUE;
// 433_200 ether
```

The high-roller value is defined as exactly nineteen normal units, rather than independently
rounding the mathematical expectation.

### 4.3 Preset-change invariant

These are immutable denomination constants, not live quotes. Any future edit to the scheduled
bankroll or bounty distribution must, in the same change:

1. Recalculate the exact expected full-day cost.
2. Round that expectation to the nearest 100 FLIP, with ties rounded up.
3. Update `NORMAL_DAY_PASS_VALUE` if the rounded value changed.
4. Preserve `HIGH_ROLLER_DAY_PASS_VALUE = 19 * NORMAL_DAY_PASS_VALUE` unless the high-roller
   multiplier distribution itself changes.
5. Update the exact-expectation and rounded-value regression test.

The daily realized entry cost remains variable. Precommitment before the daily word is known is
what makes the fixed expected-value denomination economically valid.

## 5. Per-Box Pass Conversion

### 5.1 Use the pre-rounding flat-FLIP value

For roll 15 or 16, compute:

```text
V = _largeFlipOut(mainAmount, seed, currentLevel)
```

Do not apply `FlipRoundLib.floorWholeFlip` or `roundFlipToHundreds` before converting `V` into
passes. Those functions remain applicable only to an actual flat-FLIP outcome.

The threshold and denomination are evaluated independently for each box. Batched box opening
must not pool several boxes' `V` values before choosing normal versus high-roller passes.

### 5.2 Exclusive denomination switch

The exact rule is:

```text
if V <= 20 * NORMAL_DAY_PASS_VALUE:
    passType = NORMAL
    expectedCount = V / NORMAL_DAY_PASS_VALUE
else:
    passType = HIGH_ROLLER
    expectedCount = V / HIGH_ROLLER_DAY_PASS_VALUE
```

At exactly twenty normal units, the box pays normal passes. At one token wei above the threshold,
the complete box reward switches to high-roller passes.

One box must never award a mixture of normal and high-roller passes. In particular, the
high-roller branch does not award twenty normal passes first and then high-roller passes on the
remainder.

### 5.3 Unbiased Bernoulli rounding

For either denomination unit `U`:

```text
whole     = V / U
remainder = V % U
count     = whole + Bernoulli(remainder / U)
```

A Solidity-compatible form is:

```text
roundUp = remainder != 0 && (domainSeparatedVrfWord % U) < remainder
count   = whole + (roundUp ? 1 : 0)
```

The negligible modulo bias from reducing a 256-bit uniform extractor modulo `U` is accepted and
must be documented. Floating-point arithmetic, basis-point approximations, deterministic floor,
and deterministic ceiling are not valid substitutes.

Examples, expressed in normal-pass units `x = V / N`:

| `x` | Result |
|---:|---|
| 0.4 | 40% one normal pass; 60% zero passes and the WWXRP fallback |
| 7.3 | Seven normal passes, plus 30% chance of an eighth |
| 20 | Exactly twenty normal passes |
| 20.1 | One high-roller pass, plus about 5.789% chance of a second |
| 25 | One high-roller pass, plus about 31.579% chance of a second |
| 38 | Exactly two high-roller passes |
| 57 | Exactly three high-roller passes |

### 5.4 Zero-pass fallback

If and only if the normal branch Bernoulli-rounds to zero:

1. Award no pass.
2. Create no reservation and no pass credit.
3. Execute one WWXRP Degenerette spin using `_boxWwxrpStake(mainAmount)` and the box's frozen
   activity score.
4. Derive that spin's seed from its own pass-fallback domain tag and the genuine lootbox seed.

The high-roller branch is entered only above twenty normal units, so its expected count is greater
than one and it cannot round to zero.

The WWXRP fallback is intentionally additive consolation EV. It is not deducted from `V` and is
not budget-neutralized elsewhere.

## 6. RNG and Commitment Integrity

### 6.1 Genuine entropy only

The reward bucket, pass rounding, and zero-pass WWXRP spin must all derive from the already
committed Chainlink-VRF-backed lootbox word.

Use distinct domain-separated extractors, for example:

```solidity
bytes32 constant BOX_NORMAL_PASS_ROUND_TAG =
    keccak256("Degenerus.Lootbox.CrapsNormalPassRound.v1");
bytes32 constant BOX_HIGH_PASS_ROUND_TAG =
    keccak256("Degenerus.Lootbox.CrapsHighPassRound.v1");
bytes32 constant BOX_PASS_ZERO_WWXRP_TAG =
    keccak256("Degenerus.Lootbox.CrapsPassZeroWwxrp.v1");
```

The tags are extractors from genuine VRF entropy, not new random sources.

The following must never supply, replace, salt, or modify the random decisions:

- `block.timestamp`
- block number, block hash, `prevrandao`, or coinbase
- caller or transaction origin
- target day
- entrant count or participation
- transaction order
- an admin value
- a locally evolving xorshift or other pseudo-random fallback

Repeated evaluation of the same box seed must produce the same reward and rounding result.

### 6.2 Future-day commitment

Every pass application must satisfy both:

```text
targetDay > current wall-clock protocol day
rngWordByDay[targetDay] == 0
```

The first condition prevents current-day selection. The second fails closed if a future word is
ever prefilled or backfilled unexpectedly. Under the current daily lifecycle, a daily request is
not made for a wall-clock future day, so a strictly future target also precedes the observable VRF
request for that day.

A reservation is irrevocable. Once the daily word reveals the battle terms and `H`, the player
may use the reservation or let it expire, but cannot recover, move, exchange, or downgrade it.
This removes the free option to keep only 100x high-roller days or unusually expensive normal
days.

## 7. Pass Inventory Packing

### 7.1 Game storage

`DegenerusGameStorage.BoonPacked.slot1` currently leaves bits 0..71 unused. Allocate:

| Bits | Field | Type |
|---:|---|---|
| 0..23 | Uncommitted normal Craps day-pass credits | `uint24` |
| 24..47 | Uncommitted high-roller Craps day-pass credits | `uint24` |
| 48..71 | Reserved for future pass extensions | — |

The public `boonPacked` getter remains layout-compatible. Every existing boon writer must preserve
the new low 48 bits through field-isolated read-modify-write logic.

Balances do not expire. They are nontransferable and have no cash, FLIP, DGNRS, or WWXRP
redemption path.

### 7.2 Saturation

Credit additions saturate at `type(uint24).max`; they must never wrap or wedge a permissionless
lootbox sweep. If saturation discards an economically unreachable excess, emit the discarded
count explicitly.

Credit consumption is checked subtraction. Insufficient credit reverts the complete application.

### 7.3 Lootbox memory accumulation

Add one packed pass accumulator word to `BoxAcc`, sufficient to hold:

- accumulated normal pass count;
- accumulated high-roller pass count; and
- the automatic-tomorrow candidate type.

Apply the normal-versus-high threshold per box, then accumulate the already-rounded counts.
Do not add pass counts to `_resolveLootboxRoll`'s already-wide return tuple if mutating the existing
memory accumulator avoids additional stack pressure.

## 8. Automatic Tomorrow Delivery

After one regular lootbox entry finishes resolving all of its boxes:

1. If both accumulated pass counts are zero, make no Craps call and make no pass-balance write.
2. Set `tomorrow = today + 1`; if the `uint24` addition is unavailable, credit all passes.
3. If tomorrow already has any seat or pass reservation for the player, credit all passes.
4. If `rngWordByDay[tomorrow] != 0`, credit all passes.
5. Otherwise reserve exactly one accumulated pass for tomorrow and credit every remaining pass.

If a single batch contains both pass types, the automatic slot uses one high-roller pass first;
all normal passes and any remaining high-roller passes become credits. This deterministic
highest-value priority applies only across distinct boxes in one batch; one box itself never
mixes denominations.

The Game must attempt at most one Game-to-Craps reservation call per resolution batch, not one
call per winning box. The call must use a bounded gas stipend. Ordinary unavailability returns
`false`. An unexpected revert, malformed response, or out-of-gas result is fail-open for the
player: the Game credits all accumulated passes and emits a delivery-fallback reason. No pass may
be lost, and a broken Craps integration must not wedge lootbox settlement.

A zero-pass WWXRP fallback is already fully settled as a spin and does not participate in this
delivery step.

## 9. Consecutive-Day Pass Applicator

Expose a player function with behavior equivalent to:

```solidity
function applyCrapsPasses(
    uint24 startDay,
    uint8 numberOfPasses,
    CrapsPassType passType
) external;
```

Function names and enum spelling may follow repository conventions, but the behavior is locked.

### 9.1 Valid input

- `passType` is exactly `NORMAL` or `HIGH_ROLLER`.
- `numberOfPasses` is 1 through 255. The `uint8` ABI bound is the gas bound.
- `startDay > today`.
- `endDay = uint256(startDay) + numberOfPasses - 1` fits in `uint24`.
- Every day in `[startDay, endDay]` has a zero daily word.
- The player has no seat or reservation on any target day.
- The player holds at least `numberOfPasses` uncommitted credits of the selected type.

Longer runs are made with multiple calls.

### 9.2 Atomic behavior

The function must:

1. Preflight the complete range.
2. Debit exactly `numberOfPasses` credits of the selected type in one authorized Game call.
3. Reserve the same pass type on every consecutive target day.
4. Emit one aggregate application event.

If any validation, credit debit, or reservation write fails, the entire transaction reverts.
There is no skipping occupied days, no partial application, and no partial credit consumption.

Two competing transactions are serialized by normal EVM state ordering: after one succeeds, the
other must observe either an occupied day or insufficient credit and revert without partial state.

### 9.3 Reservation, not automatic seating

Applying a pass reserves a funded full-day entitlement. It does not create the battle slip and
does not choose the player's chip allocation. The player still calls the pass-specific full-day
entry during period 0 of the target day.

This is deliberate:

- the player can choose a legal seven-chip allocation or a blank random board after terms exist;
- activity standing freezes at actual entry, matching paid entries;
- quest-streak credit occurs on actual entry;
- `openBonusDay`, `advanceGame`, and settlement never iterate pass holders.

If the player does not enter during the target day's full-day lane, the reservation expires with
no refund. The historical mapping word may remain; no cleanup sweep is required.

## 10. Craps Day-State Packing

Change the value stored at the existing `_daySeated[daySlot][player]` mapping root from `bool` to
a packed byte or word with these flags:

| Bit | Meaning |
|---:|---|
| 0 | A day-wide battle seat has been created |
| 1 | A normal pass is reserved for this day |
| 2 | A high-roller pass is reserved for this day |
| 3..7 | Reserved |

The invariant is that bits 0, 1, and 2 are mutually exclusive for one player/day.

The mapping root and key derivation remain unchanged. Existing `false/true` values decode as
zero or the seated bit. Update the storage-layout golden because the compiler-reported mapping
value type changes.

All existing uses must distinguish the cases:

- A scheduled single-window placement rejects any seated or reserved state for that day.
- A paid full-day entry rejects any seated or reserved state.
- A pass full-day entry requires the matching reservation bit.
- Protocol house and vault day tickets set only the seated bit.
- Successful pass entry replaces the reservation bit with the seated bit in one storage write.

An existing reservation is what “tomorrow is full” means for automatic lootbox delivery.

## 11. Redeeming a Reserved Pass

Expose behavior equivalent to:

```solidity
function enterBonusDayWithPass(Craps.Bets calldata chips)
    external
    returns (uint256 placed);
```

### 11.1 Entry window and validation

The call is valid only while period 0 still offers the existing early full-day lane. It must use
the current day's nonzero daily word and the existing validation for:

- all seven scheduled windows being open;
- a blank allocation or exactly seven selected chips;
- activity standing and its cap;
- one day-wide seat per address.

After period 0, the pass cannot fund a partial remainder of the day. It expires without refund.

### 11.2 Entry scale

- A normal reservation forces `multiple = 1`.
- A high-roller reservation forces `multiple = _highMultOf(currentDailyWord)`.
- The user does not quote `H`; the contract derives it from the target day's genuine daily word.
- A zero word reverts `RngNotReady`; there is no fallback multiplier.

This removes stale-quote risk and prevents the caller from selecting normal versus high mode after
the daily word is known. The reservation type fixed that choice earlier.

### 11.3 Cost and state effects

Calculate `coveredCost` exactly as the paid full-day path would:

```text
coveredCost = sum over all seven windows of
              multiple * (window bankroll + window bounty)
```

Then:

1. Do not call `FLIP.burnCoin` for `coveredCost`.
2. Replace the reservation bit with the seated bit.
3. Increment the ordinary day-ticket count and, for a high pass, the high-day-ticket count.
4. Store the same chip allocation, standing, and high-roller flag as a paid entry.
5. Emit the ordinary slip event plus a pass-consumption event containing the pass type,
   multiplier, target day, and `coveredCost`.
6. Award the ordinary one-per-day quest-streak credit.

The entry participates in all seven main fields. A high-roller pass entry also participates in
all seven high-roller fields.

## 12. Battle and Boost Accounting

### 12.1 Gameplay and awards are unchanged

A pass-funded seat uses the same:

- Craps engine and true/original odds;
- bankroll, goal, board, and dice;
- bust deletion and payout scaling;
- main ranking and high-roller ranking;
- entrant-funded-style main bounty accounting;
- high-roller side pool or sole-rider route;
- main boost and high-roller boost eligibility;
- activity-score boost rationing;
- walkover rules and claim paths.

The pass is a comped entry, not improved odds.

For one high-roller pass entrant, the extra high-roller bounty allocation and the applicable
high-roller boost still ride that player's run exactly as specified in the high-roller documents.
They return zero on a bust and scale with the run on a win.

### 12.2 Passes count as economic FLIP action

A pass replaces a real flat-FLIP lootbox emission. Economically, redemption is equivalent to
crediting that FLIP and immediately spending it on the day entry, even though the implementation
skips both token operations. Therefore a pass-funded seat uses the exact same settled-action
accounting as an equivalent paid seat:

| Settled pass seat | Add to `T(d)` | Add to `A_H(d)` |
|---|---:|---:|
| Normal pass | `R` | `0` |
| High pass with `N_H >= 2` | `H * R` | `H * R` |
| Sole high pass with `N_H = 1` | `H * R + X` | `H * R + X` |

The ordinary bounty remains excluded from action, exactly as on a paid seat. A sole high roller's
extra bounty `X` counts because the prior high-roller specification converts it into at-risk
bankroll. Protocol-funded `Q_M`, `Q_H`, and donations remain excluded.

No pass-specific settlement marker is needed in the bet header. Once the pass creates a normal or
high day seat, settlement and future boost accounting intentionally cannot distinguish it from a
paid copy of that seat.

## 13. Cross-Contract Authorization and Failure Semantics

The exact selector names are implementation choices, but the trust boundary must provide:

### Game-side surface

```solidity
function crapsPassBalances(address player)
    external
    view
    returns (uint24 normal, uint24 highRoller);

function consumeCrapsPassCredits(
    address player,
    CrapsPassType passType,
    uint8 count
) external; // ContractAddresses.CRAPS only
```

The lootbox module, executing by delegatecall in Game storage, may add credits directly.
No externally owned account, admin, or unrelated protocol contract may create or debit credits.

### Craps-side surface

```solidity
function tryReserveLootboxPass(
    address player,
    uint24 targetDay,
    CrapsPassType passType
) external returns (bool); // ContractAddresses.GAME only

function applyCrapsPasses(
    uint24 startDay,
    uint8 numberOfPasses,
    CrapsPassType passType
) external;

function enterBonusDayWithPass(Craps.Bets calldata chips)
    external
    returns (uint256 placed);
```

`tryReserveLootboxPass` returns `false`, rather than reverting, for ordinary occupancy or an
ineligible target. Game nevertheless catches unexpected failure and credits the complete award.

All state transitions are atomic under EVM revert semantics. Existing lootbox order dequeue-before-
resolution behavior must remain, and no pass path may hand control to arbitrary player code.

## 14. Events and Views

At minimum, expose enough information to reconstruct every pass from logs and verify current
inventory on chain.

Recommended events:

```solidity
event LootBoxCrapsPassRolled(
    address indexed player,
    uint48 indexed lootboxIndex,
    uint8 indexed passType,
    uint24 roundedCount,
    uint256 passBudget,
    bool zeroFallback
);

event CrapsPassDelivery(
    address indexed player,
    uint24 indexed automaticDay,
    uint8 automaticType,
    bool automaticApplied,
    uint24 normalCredited,
    uint24 highRollerCredited,
    uint8 fallbackReason
);

event CrapsPassesApplied(
    address indexed player,
    uint24 indexed startDay,
    uint8 count,
    uint8 indexed passType
);

event CrapsPassConsumed(
    address indexed player,
    uint24 indexed day,
    uint8 indexed passType,
    uint16 multiple,
    uint256 coveredCost
);
```

The exact event packing may be optimized, provided these facts remain indexable or decodable.

A pass outcome must not masquerade as an ordinary all-zero `LootBoxOpened` event. Either suppress
that generic event for the pass branch or extend the outcome schema unambiguously. The dedicated
pass event must also identify a zero-pass WWXRP fallback.

Required views:

- both uncommitted pass balances for a player;
- raw or decoded day-state flags for a player/day;
- the two denomination constants;
- whether a target day is still eligible for a pass reservation.

No on-chain enumeration of all pass holders or all reservations is required.

## 15. Gas and Liveness Requirements

1. `openBonusDay`, `advanceGame`, window arming, battle settlement, and claims must not iterate
   pass holders or future reservations.
2. Automatic tomorrow delivery makes at most one bounded-gas Craps call and one packed Game
   credit write per lootbox resolution batch.
3. A box that awards neither pass type performs neither operation.
4. `applyCrapsPasses` is the only new O(N) path. `uint8` bounds `N` to 255 and the caller pays it.
5. One future-day reservation is expected to cost roughly one cold mapping read plus one
   zero-to-nonzero mapping write, approximately 20k–25k gas before call overhead.
6. Ten applications should be roughly 0.2M–0.3M gas; one hundred roughly 2M–3M; the 255-day
   worst case must be measured rather than accepted from this estimate.
7. The measured 255-day call must remain below the repository's 10M normal-path target and the
   16.7M hard transaction ceiling.
8. Pass entry reuses the existing day-state read/write and skips the FLIP burn call; it must not
   add a new per-window storage mapping.
9. Contract deployed sizes must remain below EIP-170 limits.

## 16. Normative Requirements

### R1 — Reward-table reallocation

- **Current:** Rolls 14..16 all pay flat FLIP.
- **Target:** Roll 14 pays flat FLIP and rolls 15..16 enter pass conversion; every other bucket
  and recirculated-box exception is unchanged.
- **Acceptance:** An exhaustive twenty-roll harness maps exactly the table in Section 2.2.

### R2 — Exclusive, value-preserving denomination

- **Current:** No pass conversion exists; flat FLIP is rounded and credited.
- **Target:** Each pass box uses pre-FLIP-rounding `V`, chooses normal at `V <= 20N` or high roller
  at `V > 20N`, and Bernoulli-rounds only that denomination.
- **Acceptance:** Tests at `20N - 1`, `20N`, and `20N + 1` prove the exclusive boundary, and
  statistical tests show sample mean count within tolerance of `V / unit`.

### R3 — VRF-only randomness

- **Current:** Lootbox reward rolls already derive from a committed VRF word.
- **Target:** Pass rounding and its fallback spin derive from separate tagged extractors of that
  same genuine entropy, with no pseudo-random fallback or mutable salt.
- **Acceptance:** Same-seed replay is byte-identical; tag outputs differ; source and adversarial
  tests find no forbidden entropy source on the pass path.

### R4 — Zero-pass WWXRP fallback

- **Current:** A flat-FLIP amount may floor to zero without a pass-specific consolation.
- **Target:** A normal pass result rounded to zero executes exactly one WWXRP spin and creates no
  pass state.
- **Acceptance:** Forced round-down and round-up cases prove exactly one fallback versus exactly
  one pass; high-roller conversion never reaches the fallback.

### R5 — Packed pass inventory

- **Current:** `boonPacked.slot1` bits 0..71 are unused.
- **Target:** Bits 0..23 and 24..47 hold saturating normal and high balances while every existing
  boon field is preserved.
- **Acceptance:** Layout-oracle and coexistence tests mutate every boon/pass lane in both orders
  and prove no cross-lane clobber.

### R6 — Automatic tomorrow delivery

- **Current:** Lootbox rewards do not create Craps reservations.
- **Target:** A nonzero accumulated award reserves at most one pass for eligible, empty tomorrow
  and credits the rest; unavailable or failed delivery credits all.
- **Acceptance:** Empty, occupied, preworded, overflow, mixed-type, and forced-call-failure tests
  prove the exact disposition and no pass loss.

### R7 — Consecutive future application

- **Current:** No pass applicator exists.
- **Target:** One call atomically consumes 1..255 same-type credits and reserves that many
  consecutive, strictly future, unworded, empty days.
- **Acceptance:** Boundary, overlap, insufficient-balance, word-present, day-overflow, and
  concurrent-call tests either commit the complete range or leave all state unchanged.

### R8 — One irrevocable reservation per day

- **Current:** `_daySeated` records only a boolean seat.
- **Target:** Its packed value represents mutually exclusive seated, normal-reserved, and
  high-reserved states; reservations are nontransferable, nonrefundable, and expire unused.
- **Acceptance:** State-machine tests prove every legal transition and reject double reservation,
  replacement, upgrade, downgrade, cancellation, transfer, and replay.

### R9 — Full-day-only pass redemption

- **Current:** `enterBonusDay` burns the complete cost and creates a day ticket during period 0;
  later calls place separate paid window entries.
- **Target:** A dedicated period-0 pass path covers the complete seven-window cost once, preserves
  ordinary entry, quest, and settled-action accounting, and cannot fund any partial,
  single-window, or custom entry.
- **Acceptance:** Exact-cost and period-boundary tests prove one consumption, zero burn, seven
  fields joined, paid-seat-equivalent boost action, and rejection on every excluded entry surface.

### R10 — Target-day high multiplier

- **Current:** Paid high entrants quote the already-known daily `H`.
- **Target:** A high pass is committed while the target word is zero and redemption derives the
  eventual `H` internally, producing a 10x or 100x day seat as drawn.
- **Acceptance:** Forced 10x and 100x daily words prove correct scale, while same-day and
  already-worded commitment attempts revert.

### R11 — Batched, fail-open delivery

- **Current:** `BoxAcc` aggregates fungible rewards but has no pass lane or Craps call.
- **Target:** It aggregates rounded pass counts, selects at most one auto type, makes at most one
  bounded delivery call, and credits all on failure.
- **Acceptance:** A maximum mixed box entry shows one or zero Craps calls and one or zero packed
  credit writes, with exact aggregate conservation subject only to explicit uint24 saturation.

### R12 — Authorized conservation

- **Current:** No Game/Craps pass trust boundary exists.
- **Target:** Only Game creates/auto-reserves and only Craps debits credits; every nonsaturated
  rounded pass becomes either one reservation or one credit.
- **Acceptance:** Unauthorized-call tests revert, and invariant fuzzing proves `awarded = newly
  reserved + newly credited` for every successful delivery.

### R13 — Observable outcomes

- **Current:** Existing generic lootbox events cannot identify a pass.
- **Target:** Logs distinguish pass roll, zero fallback, automatic reservation, credit delivery,
  manual application, and consumption; views expose balances and day state.
- **Acceptance:** Event-schema tests reconstruct a multi-box mixed delivery exactly and prove no
  pass is indexed as an ordinary zero-value box outcome.

### R14 — Bounded gas and compatible layout

- **Current:** Daily Craps resolution has no pass loop; Game and Craps layouts are golden-tested.
- **Target:** Daily system paths remain O(1) in pass-holder count, the sole user loop is bounded at
  255, and both layout/type changes are reflected in the oracle.
- **Acceptance:** Source-structure and gas tests find no system-path pass iteration, measure the
  255-day call below 10M/16.7M, and pass storage-layout plus EIP-170 checks.

## 17. Acceptance Criteria

- [ ] **AC-01:** Regular lootbox rolls map 0..19 exactly as Section 2.2; presale boxes are unchanged.
- [ ] **AC-02:** `NORMAL_DAY_PASS_VALUE` is exactly 22,800 FLIP,
  `HIGH_ROLLER_DAY_PASS_VALUE` is exactly 433,200 FLIP, and the pass budget is
  `_largeFlipOut(mainAmount, seed, currentLevel)` before any whole/100-FLIP rounding.
- [ ] **AC-03:** `V <= 20N` produces only normal passes; `V > 20N` produces only high-roller passes.
- [ ] **AC-04:** The threshold is applied per box, not after aggregating a multi-box order.
- [ ] **AC-05:** Bernoulli rounding is unbiased within the repository's statistical tolerance and
  deterministic for a fixed VRF seed.
- [ ] **AC-06:** Zero normal passes execute one genuine-VRF-derived WWXRP spin and create no pass state.
- [ ] **AC-07:** No pseudo-random, block-derived, caller-derived, target-day-derived, or admin-derived
  entropy enters a pass outcome.
- [ ] **AC-08:** Normal and high credits occupy only their assigned `boonPacked.slot1` lanes and saturate
  without wrapping or reverting a lootbox sweep.
- [ ] **AC-09:** A batch makes at most one automatic Craps call and at most one packed credit write.
- [ ] **AC-10:** Eligible empty tomorrow receives exactly one pass; every remaining pass is credited.
- [ ] **AC-11:** An occupied, already-worded, overflowed, reverted, or out-of-gas automatic target credits
  the complete award without loss.
- [ ] **AC-12:** A mixed batch automatically applies one high-roller pass first and credits all remaining
  normal/high passes.
- [ ] **AC-13:** `applyCrapsPasses` accepts 1 and 255 and rejects 0 by ABI/validation; longer runs require
  multiple calls.
- [ ] **AC-14:** Every applied day is strictly future, has a zero daily word, and is consecutive.
- [ ] **AC-15:** Any overlap, insufficient credit, invalid type, day overflow, or failed write reverts the
  whole application with no credit debit and no reservation.
- [ ] **AC-16:** A day state cannot simultaneously be seated, normal-reserved, or high-reserved.
- [ ] **AC-17:** Reservations cannot be transferred, canceled, refunded, upgraded, downgraded, or moved.
- [ ] **AC-18:** A missed reservation expires without restoring credit and requires no protocol sweep.
- [ ] **AC-19:** Pass entry is available only in period 0 and joins exactly seven scheduled windows.
- [ ] **AC-20:** Normal pass redemption stores 1x; high pass redemption derives and stores/uses the target
  day's genuine 10x or 100x scale without a caller quote.
- [ ] **AC-21:** A valid pass entry skips exactly `coveredCost` of FLIP burn and consumes the reservation once.
- [ ] **AC-22:** Paid entry and single-window entry reject a player with a reservation for that day.
- [ ] **AC-23:** Pass entry preserves chip validation, frozen standing, quest-streak credit, main/high ranking,
  bounty, boost, rider, and payout behavior.
- [ ] **AC-24:** A pass-funded seat contributes exactly the same amount to `_dayStaked` and `_highStaked`
  as an equivalent paid seat, including the sole-high extra-bounty rider rule.
- [ ] **AC-25:** Unauthorized Game/Craps pass creation, debit, and automatic reservation calls revert.
- [ ] **AC-26:** Pass-specific logs and views reconstruct awards, dispositions, inventory, reservations, and
  consumption; no pass appears as a generic zero-value `LootBoxOpened`.
- [ ] **AC-27:** No pass-holder loop is reachable from `openBonusDay`, `advanceGame`, arming, settlement, or claim.
- [ ] **AC-28:** A measured 255-day application is below 10M gas and the 16.7M hard transaction ceiling.
- [ ] **AC-29:** Game and Craps storage-layout goldens and the EIP-170 deployed-size checks pass.
- [ ] **AC-30:** Existing non-pass lootbox, Craps, high-roller, gas-ceiling, RNG-freeze, and storage-coexistence
  regression suites remain green.

## 18. Edge Coverage

The canonical edge-completeness classifier raised 59 applicable boundary, precision, collection,
ordering, idempotency, and concurrency edges across R1..R14. The rows below group candidates only
when the same acceptance checks resolve every category named.

**Coverage:** 59/59 applicable edges resolved explicitly; 0 unresolved.

| Categories | Requirement | Status | Explicit resolution |
|---|---|---|---|
| Boundary, precision | R1 | Resolved | AC-01 fixes all twenty buckets and preserves the modulo contract. |
| Boundary, precision, idempotency, concurrency | R2 | Resolved | AC-02..05 pin pre-rounding value, `20N` boundary, per-box ordering, replay, and unbiased rounding. |
| Idempotency, concurrency | R3 | Resolved | AC-05 and AC-07 pin deterministic replay and immutable entropy inputs. |
| Boundary, precision, idempotency, concurrency | R4 | Resolved | AC-06 covers zero versus nonzero and exactly-once fallback. |
| Boundary, precision, idempotency, concurrency | R5 | Resolved | AC-08, AC-15, and AC-29 cover zero/max counts, saturation, atomic debit, and lane preservation. |
| Adjacency, empty, ordering, idempotency, concurrency | R6 | Resolved | AC-09..12 define empty batches, occupied tomorrow, mixed ordering, retry, and failure disposition. |
| Boundary, adjacency, empty, ordering, precision, idempotency, concurrency | R7 | Resolved | AC-13..15 cover 0/1/255, touching ranges, overlap, ordering, overflow, replay, and atomicity. |
| Adjacency, empty, ordering, idempotency, concurrency | R8 | Resolved | AC-16..18 define mutually exclusive states, replay rejection, and expiry. |
| Idempotency, concurrency | R9 | Resolved | AC-19, AC-21..24 cover period boundary, exactly-once use, paid-seat action parity, and collision with paid entry. |
| Boundary, precision, idempotency, concurrency | R10 | Resolved | AC-14 and AC-20 pin preword commitment and exact 10x/100x derivation. |
| Adjacency, empty, ordering, idempotency, concurrency | R11 | Resolved | AC-09..12 cover accumulation order, empty batch, one call/write, and fail-open retry behavior. |
| Boundary, precision, idempotency, concurrency | R12 | Resolved | AC-08, AC-15, and AC-25 cover max balances, exact debit, authorization, and atomic conservation. |
| Adjacency, empty, ordering, concurrency | R13 | Resolved | AC-26 fixes event identity, aggregate ordering, zero fallback, and view parity. |
| Boundary, adjacency, empty, ordering, precision, idempotency, concurrency | R14 | Resolved | AC-27..30 pin the 255 bound, empty/system paths, stable layout, gas ceiling, and regression behavior. |

## 19. Prohibitions (Must NOT)

The prohibition probe retained five product-specific constraints. Generic Solidity access control,
reentrancy, arithmetic safety, and EIP-170 compliance remain mandatory but are canonical contract-
audit concerns rather than duplicated bespoke prohibitions.

**Coverage:** 5/5 applicable prohibitions resolved; 0 unresolved.

| Prohibition | Requirement | Status | Verification |
|---|---|---|---|
| A pass must not be assigned to the current day or to a day whose daily word is already known. | R7, R10 | Resolved | Test: AC-14, AC-20 |
| A committed reservation must not become a free option through cancellation, refund, transfer, upgrade, downgrade, or rescheduling after terms are known. | R8, R10 | Resolved | Test: AC-17, AC-18 |
| Pass randomness must not silently become pseudo-random, admin-selected, block-derived, caller-derived, or participation-dependent. | R3 | Resolved | Test plus adversarial source review: AC-07 |
| The protocol must not auto-seat pass holders by iterating them during daily system work. | R9, R14 | Resolved | Test/source structure: AC-27 |
| A pass outcome must not be represented to indexers as an unexplained zero-value ordinary lootbox result. | R13 | Resolved | Test: AC-26 |

## 20. Boundaries

### In scope

- Ten percentage points of the regular lootbox main-reward distribution move from flat FLIP to
  Craps day passes.
- Normal pass value rounded to 22,800 FLIP and high-roller value fixed at 19x, or 433,200 FLIP.
- Per-box exclusive denomination and genuine-VRF Bernoulli rounding.
- Zero-pass WWXRP Degenerette fallback.
- Packed normal/high pass inventories in Game storage.
- One automatic tomorrow reservation per lootbox resolution batch.
- Same-type consecutive future-day reservation application.
- Full-day period-0 pass redemption for normal and scheduled high-roller seats.
- Paid-seat-equivalent action accounting for pass-funded normal and high-roller seats.
- Events, views, interfaces, storage-layout updates, gas tests, and economic/RNG invariants.

### Out of scope

- Presale-box reward distribution — it uses a separate resolver.
- Individual scheduled-window passes — passes fund the complete early day lane only.
- Custom-battle passes — creator-set custom high multipliers are unrelated to scheduled day-pass value.
- Same-day pass use — it would reveal terms and `H` before commitment.
- Automatic protocol seating or keeper walks over pass holders — omitted for gas/liveness and chip-choice reasons.
- Transferable, tradable, giftable, refundable, or cash-redeemable passes — credits are account-bound utility.
- Pass cancellation, upgrade, downgrade, or rescheduling — these would recreate outcome selection.
- Admin-set pass outcomes, pass grants, pass prices, or entropy — the mechanism is immutable and VRF-derived.
- Any change to Craps odds, goals, bankroll tables, bounties, mystery boosts, ranking, or the 90/10 high-multiplier draw.
- Any change to the lootbox boon budget or to non-flat-FLIP reward magnitudes.
- On-chain enumeration of all holders/reservations or cleanup of expired historical words.

## 21. Ambiguity Report

| Dimension | Score | Minimum | Status | Notes |
|---|---:|---:|---|---|
| Goal clarity | 0.98 | 0.75 | Met | Reward reallocation and pass behavior are exact. |
| Boundary clarity | 0.96 | 0.70 | Met | Entry surfaces and excluded systems are enumerated. |
| Constraint clarity | 0.94 | 0.65 | Met | RNG, packing, commitment, gas, authorization, and action accounting are fixed. |
| Acceptance criteria | 0.95 | 0.70 | Met | Thirty pass/fail checks cover unit, integration, economic, and gas behavior. |
| **Ambiguity** | **0.04** | **<= 0.20** | **Gate passed** | No unresolved product decision remains. |

## 22. Decision Log

| Perspective | Question resolved | Locked decision |
|---|---|---|
| Researcher | Which existing lootbox emission is replaced? | Two of the three flat-FLIP roll buckets, leaving 5% flat FLIP and adding 10% passes. |
| Economic | What is one normal/high pass worth? | Exact current expectation rounded to 22,800 FLIP; high unit is exactly 19 normal units, or 433,200 FLIP. |
| Simplifier | How are large awards represented? | Normal only through `20N`; above it, high-roller only; no mixed award from one box. |
| RNG integrity | How are fractions rounded? | Genuine lootbox VRF plus domain-separated Bernoulli extraction; never pseudo RNG. |
| Boundary keeper | When may a pass be used? | Any strictly future, unworded day; never today, a single window, or a custom battle. |
| Failure analyst | What if tomorrow is occupied or Craps delivery fails? | Credit the complete award; lootbox resolution remains live. |
| Gas | How are consecutive days handled? | User-paid bounded loop, reservation only, no daily subscriber iteration. |
| Economic feedback | Does a pass entry fund future boost? | Yes; the pass replaces real lootbox FLIP emission, so it books exactly the same action as an equivalent paid seat. |
| Specification close | Which type takes an empty tomorrow slot in a mixed batch? | High-roller first; all other passes become credits. |

## 23. Required Test Matrix

At minimum, the implementation plan must cover:

### Lootbox unit and statistical tests

- Exhaustive roll-bucket mapping for all twenty residues.
- Exact current expectation plus nearest-100-FLIP derivation of `NORMAL_DAY_PASS_VALUE = 22,800 FLIP`.
- `V = 0`, `N - 1`, `N`, `20N - 1`, `20N`, `20N + 1`, `38N`, and large high-pass cases.
- Bernoulli mean, boundary, deterministic-replay, seed-uniqueness, and domain-separation tests.
- Zero-pass WWXRP fallback and nonzero no-fallback tests.
- Per-box threshold versus aggregate-batch non-equivalence regression.
- Direct, auto-resolved, recirculated, redemption, afking, and other callers of the shared regular
  lootbox resolver; presale resolver unchanged.

### Storage and integration tests

- All existing boon lanes coexisting with both pass balances.
- `uint24` saturation and checked debit.
- Empty tomorrow, normal-full tomorrow, high-full tomorrow, already-worded tomorrow, day overflow,
  Craps false return, Craps revert, and bounded-call out-of-gas.
- Multi-box normal-only, high-only, and mixed accumulation with one call/write.
- Game-only auto reservation and Craps-only credit consumption.
- Storage-layout oracle proving the Game low-bit allocation and Craps mapping-type change.

### Applicator state-machine tests

- Counts 1 and 255, zero, start today, start tomorrow, end-day overflow, insufficient credit.
- Occupied first/middle/last day and a daily word present first/middle/last day.
- Atomic rollback of both Game credit debit and Craps reservations.
- Concurrent/replayed application and cross-type overlap.
- Expiry without refund, cancellation, reschedule, transfer, upgrade, or downgrade.

### Entry and economic tests

- Normal and high pass entry at period 0 with blank and seven-chip boards.
- 10x and 100x high-pass days derived internally.
- Period boundary immediately before and after the full-day lane closes.
- Exact skipped burn, one reservation consumption, seven joined windows, and quest credit.
- Paid day entry and individual-window entry blocked by a reservation.
- Pass-funded main and high winners, busts, walkovers, contested pots, and sole high rider.
- Identical ranking/gameplay result for paid versus pass-funded copies of the same committed inputs.
- Exact `_dayStaked`/`_highStaked` parity between pass-funded and paid copies of every seat shape,
  including the sole-high `X` rider.
- Protocol-funded boosts and donations remain excluded from action on both pass and paid seats.

### Gas and size tests

- Automatic no-award, award-plus-credit, and award-plus-reservation marginals.
- Application gas at 1, 10, 100, and 255 days.
- Pass entry versus paid entry gas.
- No pass-count-dependent gas in `openBonusDay`, `advanceGame`, arming, settlement, or claim.
- 10M target, 16.7M hard ceiling, EIP-170 size, and existing Craps/lootbox gas suites.

---

*Standalone contract handoff specification; no GSD roadmap phase was created.*
