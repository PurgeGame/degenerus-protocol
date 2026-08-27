# Craps Day Passes, Future Prepaid Entries, and Battle Boons — Contract Specification

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

**Requirements:** 16 locked

**Ambiguity score:** 0.04 (gate: <= 0.20)

## 1. Purpose and Precedence

Replace ten percentage points of the regular lootbox's flat-FLIP reward probability with
Craps full-day passes. Small pass rewards pay normal passes. Once a single box's unrounded pass
budget exceeds twenty normal-pass units, the complete reward switches to high-roller passes.
Every fractional pass is rounded with genuine VRF-backed entropy.

The same future-day reservation surface also lets a player prepay directly in FLIP: 25,000 FLIP
per normal day or 450,000 FLIP per high-roller day. The complete fixed price is burned when the
reservation is made, before the target day's word or high-roller multiplier is known.

Extend the existing boon table with a separate Craps battle-discount family modeled on the FLIP
Degenerette boon: 4%, 8%, and 12% tiers, each applied to at most 100,000 FLIP of the player's next
successful self-funded Craps purchase. It has its own packed lane and does not displace or consume
the player's FLIP Degenerette boon.

A pass may be committed only to a future protocol day whose daily word has not landed. It covers
one early full-day entry across all seven scheduled Bonus Battle windows. A normal pass covers a
1x day entry; a high-roller pass covers the target day's genuine 10x-or-100x high-roller entry.

This specification supersedes the two documents above only for reserved entries and their funding:

1. A pass-funded entry does not burn the player's FLIP entry cost.
2. A future-FLIP reservation burns its fixed purchase price once, at reservation time, and never
   burns, refunds, or surcharges against the target day's realized cost.
3. A battle boon reduces only the FLIP burned for the eligible purchase; it does not reduce the
   purchased bankroll, bounty, gameplay scale, or settled action.
4. A reserved seat's notional bankroll action counts toward later boost budgets exactly as if the
   underlying seat had been bought through the ordinary live path; for a pass-funded seat this is
   economically equivalent to crediting the replaced lootbox FLIP and immediately spending it.
5. No reservation or bet stores whether it was pass-funded, prepaid, discounted, or “taxed,” and
   neither fixed purchase price nor its premium enters action accounting.
6. Every reserved or boon-discounted entry uses the same battle, bounty, boost, ranking, payout,
   and high-roller rules as its full-price counterpart.

All rules for immediate paid entries remain unchanged except for optional battle-boon consumption.

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
| `targetDay` | Future protocol day to which one pass credit or prepaid purchase has been irrevocably committed |
| `credit` | Uncommitted pass inventory held by a player and usable for a future reservation |
| `reservation` | One normal or high-roller pass irrevocably assigned to one future protocol day |
| `prepaid reservation` | A reservation funded by an immediate fixed FLIP burn rather than pass credit; its stored day state is identical to a pass-funded reservation |
| `P_N` | Fixed gross price of one future normal-day reservation: 25,000 FLIP |
| `P_H` | Fixed gross price of one future high-roller-day reservation: 450,000 FLIP |
| `coveredCost` | The exact normal or high-roller FLIP burn that the live full-day path would charge for the target day's realized terms |
| `grossPurchase` | The full price of an eligible Craps purchase before an optional battle-boon discount |
| `netBurn` | `grossPurchase - battleBoonDiscount`; the amount actually burned for that purchase |

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

### 4.4 Fixed future-FLIP purchase prices

A player may reserve the same future normal or high-roller days without pass credits by burning
these immutable gross prices at reservation time:

```solidity
uint256 constant NORMAL_FUTURE_DAY_PRICE = 25_000 ether;
uint256 constant HIGH_ROLLER_FUTURE_DAY_PRICE = 450_000 ether;
```

The two values are independent constants. `HIGH_ROLLER_FUTURE_DAY_PRICE` is exactly 450,000 FLIP;
it must not be derived as nineteen times either normal constant. Against the exact current expected
costs in Sections 4.1 and 4.2, the prices carry approximate premiums of:

| Reservation | Exact expected cost | Gross prepay price | Difference | Premium vs exact expectation |
|---|---:|---:|---:|---:|
| Normal | 22,802.116666666666666667 | 25,000 | 2,197.883333333333333333 | 9.6389% |
| High roller | 433,240.216666666666666667 | 450,000 | 16,759.783333333333333333 | 3.8685% |

Those differences are economic consequences of the fixed prices, not on-chain accounting fields.
The contract burns the gross price, optionally reduced by a live battle boon, and must not derive,
store, emit, or later book a separate `tax` or `premium` amount.

The price is fixed before the target day reveals its realized bankroll, bounty, and `H`. Redemption
therefore never charges a top-up when `coveredCost` exceeds the prepaid price and never refunds a
difference when it is lower. A future change to scheduled terms or the 90/10 high-multiplier draw
must explicitly review both prepay constants, but no formula automatically links them to pass
denominations or to one another.

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

## 6. Battle-Discount Boon

### 6.1 New boon family and draw weights

Add a separate three-tier boon family to the canonical lootbox/deity boon table:

| Boon type | Suggested id | Discount | Draw weight |
|---|---:|---:|---:|
| `BOON_CRAPS_4` | 41 | 4% | 200 |
| `BOON_CRAPS_8` | 42 | 8% | 50 |
| `BOON_CRAPS_12` | 43 | 12% | 10 |

The ids follow the current 1..40 table; exact constant names may follow repository conventions.
The weights are exactly the existing FLIP Degenerette family's 200/50/10 weights. Adding 260 weight
changes `BOON_WEIGHT_TOTAL` from 2,608 to 2,868. The battle-boon family is eligible from both
lootbox and deity boon draws wherever the corresponding Degenerette family is eligible. Its draw
uses the existing genuine VRF-derived boon entropy and creates no new randomness source.

Use a distinct observable reward identity. The recommended encoding is `LootBoxReward.rewardType =
14` with `amount` equal to boon type 41, 42, or 43, plus a dedicated battle-boon consumption category
in `BoonConsumed`. Reusing the FLIP Degenerette reward identity is forbidden because indexers must be
able to distinguish which independent lane was awarded.

### 6.2 Packed state, expiry, and replacement

Use `boonPacked[player].slot1` bits 48..71 as one 24-bit battle-boon lane. Its internal format is
identical to a Degenerette currency lane:

| Lane bits | Meaning |
|---:|---|
| 0..1 | tier: 0 none, 1 = 4%, 2 = 8%, 3 = 12% |
| 2 | deity-source flag |
| 3..23 | low 21 bits of award day |

The battle lane is independent of all three Degenerette currency lanes and both pass-credit lanes.
A Craps purchase must never read or consume the FLIP Degenerette lane, and a Degenerette bet must
never read or consume the battle lane.

Every lifecycle rule matches the FLIP Degenerette boon:

- a lootbox-drawn boon remains live through award day plus `DEGENERETTE_BOON_EXPIRY_DAYS = 2`;
- a deity-granted boon is live only on its award day;
- a higher live tier replaces the held tier and resets the applicable stamp;
- a lower or equal live tier is discarded and does not refresh expiry;
- an expired lane is cleared on the normal expiry sweep or the next attempted consumption; and
- every read-modify-write preserves pass credits and all unrelated boon lanes.

### 6.3 Eligible purchase and exact discount

The live boon is consumed by the player's next **successful, self-funded, FLIP-funded Craps
purchase**. Eligible purchase surfaces are:

- a custom battle entry through `enterBattle`;
- one scheduled-window entry through `enterBonusBattle`;
- one successful `enterBonusDay` call, whether it creates the period-0 full-day seat or a late-day
  set of remaining paid windows; and
- one future-day FLIP prepayment call from Section 10.3, regardless of how many days it reserves.

One external purchase consumes at most one boon. For a bundled purchase, `grossPurchase` is the sum
of all FLIP that the call would otherwise burn for the entries or reservations it actually creates.
The discount is:

```text
discountBase = min(grossPurchase, 100_000 FLIP)
discount     = floor(discountBase * boonBps / 10_000)
netBurn      = grossPurchase - discount
```

The 100,000-FLIP base cap, 4/8/12% tiers, and floor rounding are exactly the FLIP Degenerette boon
limits. Thus the maximum discounts are 4,000, 8,000, or 12,000 FLIP. A future normal reservation
costs 24,000 / 23,000 / 22,000 FLIP with the three tiers. A single future high reservation costs
446,000 / 442,000 / 438,000 FLIP because its 450,000-FLIP gross price exceeds the cap.

The following do not consume the boon:

- invalid or fully reverted entry attempts;
- an `enterBonusDay` call that creates zero paid entries;
- pass redemption or redemption of an already-prepaid reservation;
- protocol house/vault seats, free entries, claims, settlement, or walkovers; and
- bounty/boost donations, which are not battle purchases.

If a future interface ever permits a third party to fund another player's entry, that gifted entry
must not consume or use the recipient's boon. Boon consumption occurs only after the complete
purchase has passed validation; any later FLIP-burn or reservation failure reverts both consumption
and all entry state atomically.

### 6.4 Boon-budget normalization

The existing lootbox boon budget remains 10% of box value capped at 1 ETH, and the existing 50%
utilization assumption remains. Extend the weighted maximum-value normalization by exactly the same
FLIP-valued term as the FLIP Degenerette family:

```text
weightedBattleMax =
    200 * flipToEthValue(4_000 FLIP, priceWei)
  +  50 * flipToEthValue(8_000 FLIP, priceWei)
  +  10 * flipToEthValue(12_000 FLIP, priceWei)
```

Under the current closed form this changes `BOON_PRICE_WEIGHT` from 3,270 to 4,590 and
`BOON_WEIGHT_TOTAL` from 2,608 to 2,868; `BOON_FIXED_WEIGHTED_MAX` and `BOON_LAZY_WEIGHT` remain
unchanged. Update the module's lookup tree, `DeityBoonViewer`, deity eligible-range remapping,
weighted-average parity test, and exhaustive roll-tree parity test together. Boon frequency is
re-normalized by this table change; no separate emission budget is added.

## 7. RNG and Commitment Integrity

### 7.1 Genuine entropy only

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

### 7.2 Future-day commitment

Every pass application and future-FLIP purchase must satisfy both:

```text
targetDay > current wall-clock protocol day
rngWordByDay[targetDay] == 0
```

The first condition prevents current-day selection. The second fails closed if a future word is
ever prefilled or backfilled unexpectedly. Under the current daily lifecycle, a daily request is
not made for a wall-clock future day, so a strictly future target also precedes the observable VRF
request for that day.

A reservation is irrevocable. A prepaid reservation's complete `netBurn` happens in the same
transaction that creates it. Once the daily word reveals the battle terms and `H`, the player may
use the reservation or let it expire, but cannot recover, move, exchange, or downgrade it. No burn
may be deferred until redemption. These rules remove the free option to keep only 100x high-roller
days or unusually expensive normal days.

## 8. Pass and Battle-Boon Packing

### 8.1 Game storage

`DegenerusGameStorage.BoonPacked.slot1` currently leaves bits 0..71 unused. Allocate:

| Bits | Field | Type |
|---:|---|---|
| 0..23 | Uncommitted normal Craps day-pass credits | `uint24` |
| 24..47 | Uncommitted high-roller Craps day-pass credits | `uint24` |
| 48..71 | Craps battle-discount boon lane | packed `uint24` |

The public `boonPacked` getter remains layout-compatible. Every existing boon writer must preserve
the new low 72 bits through field-isolated read-modify-write logic. Pass-credit writers preserve
the battle-boon lane; battle-boon and expiry writers preserve both pass balances.

Balances do not expire. They are nontransferable and have no cash, FLIP, DGNRS, or WWXRP
redemption path.

### 8.2 Saturation

Credit additions saturate at `type(uint24).max`; they must never wrap or wedge a permissionless
lootbox sweep. If saturation discards an economically unreachable excess, emit the discarded
count explicitly.

Credit consumption is checked subtraction. Insufficient credit reverts the complete application.

### 8.3 Lootbox memory accumulation

Add one packed pass accumulator word to `BoxAcc`, sufficient to hold:

- accumulated normal pass count;
- accumulated high-roller pass count; and
- the automatic-tomorrow candidate type.

Apply the normal-versus-high threshold per box, then accumulate the already-rounded counts.
Do not add pass counts to `_resolveLootboxRoll`'s already-wide return tuple if mutating the existing
memory accumulator avoids additional stack pressure.

## 9. Automatic Tomorrow Delivery

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

## 10. Future-Day Reservation Applicators

Expose sibling player functions with behavior equivalent to:

```solidity
function applyCrapsPasses(
    uint24 startDay,
    uint8 numberOfPasses,
    CrapsPassType passType
) external;

function buyFutureCrapsDays(
    uint24 startDay,
    uint8 numberOfDays,
    CrapsPassType reservationType
) external;
```

Function names and enum spelling may follow repository conventions, and an implementation may use
one selector with an explicit funding enum. The user-facing reservation surface must offer both
funding choices. One call uses exactly one funding source: it never silently consumes available
pass credits and burns FLIP for a remainder.

### 10.1 Common valid input

- The reservation type is exactly `NORMAL` or `HIGH_ROLLER`.
- The count is 1 through 255. The `uint8` ABI bound is the gas bound.
- `startDay > today`.
- `endDay = uint256(startDay) + count - 1` fits in `uint24`.
- Every day in `[startDay, endDay]` has a zero daily word.
- The player has no seat or reservation on any target day.

Longer runs are made with multiple calls.

### 10.2 Pass-credit atomic behavior

The function must:

1. Preflight the complete range.
2. Debit exactly `numberOfPasses` credits of the selected type in one authorized Game call.
3. Reserve the same pass type on every consecutive target day.
4. Emit one aggregate application event.

If any validation, credit debit, or reservation write fails, the entire transaction reverts.
There is no skipping occupied days, no partial application, and no partial credit consumption.

Two competing transactions are serialized by normal EVM state ordering: after one succeeds, the
other must observe either an occupied day or insufficient credit and revert without partial state.

The pass path additionally requires at least `numberOfPasses` live uncommitted credits of the
selected type. It performs no FLIP burn and does not read or consume a battle boon.

### 10.3 Future-FLIP atomic behavior

The FLIP path must:

1. Preflight the complete target range before consuming a boon or burning FLIP.
2. Compute `grossPurchase = count * P_N` for normal reservations or `count * P_H` for high-roller
   reservations, using the exact constants in Section 4.4.
3. Consume at most one live battle boon and compute `netBurn` under Section 6.3.
4. Burn exactly `netBurn` from `msg.sender` in one `FLIP.burnCoin` call.
5. Reserve the selected type on every consecutive target day using the same day-state bits as a
   pass-funded reservation.
6. Emit one aggregate purchase event.

The path does not read or debit either pass-credit balance. If validation, boon consumption, FLIP
burn, or any reservation write fails, EVM reversion restores the player's boon and FLIP balance and
leaves every target day unchanged. There is no partial burn, partial reservation, skipped day, or
credit fallback.

The fixed `netBurn` is final. The target day's eventual 10x/100x result and realized normal terms
cause neither top-up nor refund. Repeating or racing the same range after one purchase succeeds must
revert on occupancy before consuming another boon or burning additional FLIP.

### 10.4 Reservation, not automatic seating

Applying a pass or purchasing a future day reserves a funded full-day entitlement. It does not
create the battle slip and does not choose the player's chip allocation. The player still calls the
reservation-specific full-day entry during period 0 of the target day.

This is deliberate:

- the player can choose a legal seven-chip allocation or a blank random board after terms exist;
- activity standing freezes at actual entry, matching paid entries;
- quest-streak credit occurs on actual entry;
- `openBonusDay`, `advanceGame`, and settlement never iterate reservation holders.

If the player does not enter during the target day's full-day lane, the reservation expires with
no refund or action credit. A prepaid reservation's `netBurn` remains deleted. The historical
mapping word may remain; no cleanup sweep is required.

## 11. Craps Day-State Packing

Change the value stored at the existing `_daySeated[daySlot][player]` mapping root from `bool` to
a packed byte or word with these flags:

| Bit | Meaning |
|---:|---|
| 0 | A day-wide battle seat has been created |
| 1 | A normal full-day entitlement is reserved for this day |
| 2 | A high-roller full-day entitlement is reserved for this day |
| 3..7 | Reserved |

The invariant is that bits 0, 1, and 2 are mutually exclusive for one player/day.

The mapping root and key derivation remain unchanged. Existing `false/true` values decode as
zero or the seated bit. Update the storage-layout golden because the compiler-reported mapping
value type changes.

All existing uses must distinguish the cases:

- A scheduled single-window placement rejects any seated or reserved state for that day.
- A paid full-day entry rejects any seated or reserved state.
- A reserved full-day entry requires the matching reservation bit.
- Protocol house and vault day tickets set only the seated bit.
- Successful reserved entry replaces the reservation bit with the seated bit in one storage write.

No bit records pass versus FLIP funding, gross price, net burn, premium, battle-boon use, or any
other purchase history. A pass-funded and prepaid reservation of the same type are byte-identical.

An existing reservation is what “tomorrow is full” means for automatic lootbox delivery.

## 12. Redeeming a Reserved Day

Expose behavior equivalent to:

```solidity
function enterReservedBonusDay(Craps.Bets calldata chips)
    external
    returns (uint256 placed);
```

An implementation may retain a pass-oriented selector name for compatibility, but its semantics
must be reservation-generic and it must not require a funding-source argument.

### 12.1 Entry window and validation

The call is valid only while period 0 still offers the existing early full-day lane. It must use
the current day's nonzero daily word and the existing validation for:

- all seven scheduled windows being open;
- a blank allocation or exactly seven selected chips;
- activity standing and its cap;
- one day-wide seat per address.

After period 0, the reservation cannot fund a partial remainder of the day. It expires without
refund or settled action.

### 12.2 Entry scale

- A normal reservation forces `multiple = 1`.
- A high-roller reservation forces `multiple = _highMultOf(currentDailyWord)`.
- The user does not quote `H`; the contract derives it from the target day's genuine daily word.
- A zero word reverts `RngNotReady`; there is no fallback multiplier.

This removes stale-quote risk and prevents the caller from selecting normal versus high mode after
the daily word is known. The reservation type fixed that choice earlier.

### 12.3 Cost and state effects

Calculate `coveredCost` exactly as the paid full-day path would:

```text
coveredCost = sum over all seven windows of
              multiple * (window bankroll + window bounty)
```

Then:

1. Do not call `FLIP.burnCoin` for `coveredCost`.
2. Replace the reservation bit with the seated bit.
3. Increment the ordinary day-ticket count and, for a high reservation, the high-day-ticket count.
4. Store the same chip allocation, standing, and high-roller flag as a paid entry.
5. Emit the ordinary slip event plus a reservation-consumption event containing the reservation type,
   multiplier, target day, and `coveredCost`.
6. Award the ordinary one-per-day quest-streak credit.

The entry participates in all seven main fields. A high-roller reservation also participates in
all seven high-roller fields. Redemption neither reads nor consumes a battle boon: a prepaid entry
already had its only purchase-time boon opportunity, and a pass redemption burns no FLIP.

## 13. Battle and Boost Accounting

### 13.1 Gameplay and awards are unchanged

A pass-funded, prepaid, or battle-boon-discounted seat uses the same:

- Craps engine and true/original odds;
- bankroll, goal, board, and dice;
- bust deletion and payout scaling;
- main ranking and high-roller ranking;
- entrant-funded-style main bounty accounting;
- high-roller side pool or sole-rider route;
- main boost and high-roller boost eligibility;
- activity-score boost rationing;
- walkover rules and claim paths.

Funding and discount mechanics change only when/how much FLIP is burned, not the run.

For one high-roller reserved entrant, the extra high-roller bounty allocation and the applicable
high-roller boost still ride that player's run exactly as specified in the high-roller documents.
They return zero on a bust and scale with the run on a win.

### 13.2 Gameplay action is independent of reservation funding and discounts

A pass replaces a real flat-FLIP lootbox emission. Economically, redemption is equivalent to
crediting that FLIP and immediately spending it on the day entry, even though the implementation
skips both token operations. A future-FLIP reservation burns its fixed price earlier, and a battle
boon may reduce the burn for either a future or live purchase. None of those facts changes settled
action. Every resulting seat uses the exact same action accounting as an equivalent full-price
live seat:

| Settled reserved seat | Add to `T(d)` | Add to `A_H(d)` |
|---|---:|---:|
| Normal | `R` | `0` |
| High with `N_H >= 2` | `H * R` | `H * R` |
| Sole high with `N_H = 1` | `H * R + X` | `H * R + X` |

The ordinary bounty remains excluded from action, exactly as on a paid seat. A sole high roller's
extra bounty `X` counts because the prior high-roller specification converts it into at-risk
bankroll. Protocol-funded `Q_M`, `Q_H`, and donations remain excluded.

Booking a future reservation writes zero to `_dayStaked` and `_highStaked`; action is booked only
if/when the created seat settles. An expired prepaid reservation therefore produces no action even
though its `netBurn` remains deleted.

The following amounts are never added to action and never require a settlement distinction:

- `P_N`, `P_H`, or aggregate future prepayment;
- the economic difference between fixed prepay and expected/realized `coveredCost`;
- a battle-boon discount or the resulting `netBurn`; and
- any label or calculated component called tax or premium.

No funding-, tax-, or discount-specific marker exists in the reservation state or bet header.
Once a normal or high seat exists, settlement and future boost accounting intentionally cannot
distinguish a live full-price, boon-discounted, pass-funded, or prepaid copy of that seat.

## 14. Cross-Contract Authorization and Failure Semantics

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

function consumeCrapsBattleBoon(address player)
    external
    returns (uint16 discountBps); // ContractAddresses.CRAPS only
```

The lootbox module, executing by delegatecall in Game storage, may add credits directly.
The boon module, also executing in Game storage, awards, upgrades, expires, and consumes the battle
lane. No externally owned account, admin, or unrelated protocol contract may create or debit
credits or consume a player's battle boon.

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

function buyFutureCrapsDays(
    uint24 startDay,
    uint8 numberOfDays,
    CrapsPassType reservationType
) external;

function enterReservedBonusDay(Craps.Bets calldata chips)
    external
    returns (uint256 placed);
```

`tryReserveLootboxPass` returns `false`, rather than reverting, for ordinary occupancy or an
ineligible target. Game nevertheless catches unexpected failure and credits the complete award.

`CrapsBattle` uses its existing `ContractAddresses.CRAPS` authorization on `FLIP.burnCoin` for both
ordinary entries and future prepayment. The new Game boon-consumption wrapper accepts only
`ContractAddresses.CRAPS`, then delegatecalls the pinned boon module. Neither call reaches arbitrary
player code.

All state transitions are atomic under EVM revert semantics. Existing lootbox order dequeue-before-
resolution behavior must remain. Validation precedes boon consumption, and a failed FLIP burn or
later state write reverts the cross-contract boon clear as part of the same transaction.

## 15. Events and Views

At minimum, expose enough information to reconstruct every pass, future purchase, and battle-boon
award/consumption from logs and verify current inventory on chain.

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

event CrapsFutureDaysPurchased(
    address indexed player,
    uint24 indexed startDay,
    uint8 count,
    uint8 indexed reservationType,
    uint256 grossPurchase,
    uint16 boonBps,
    uint256 netBurn
);

event CrapsReservationConsumed(
    address indexed player,
    uint24 indexed day,
    uint8 indexed reservationType,
    uint16 multiple,
    uint256 coveredCost
);
```

The exact event packing may be optimized, provided these facts remain indexable or decodable.

A pass outcome must not masquerade as an ordinary all-zero `LootBoxOpened` event. Either suppress
that generic event for the pass branch or extend the outcome schema unambiguously. The dedicated
pass event must also identify a zero-pass WWXRP fallback. The existing boon award/consumption event
families must identify the new independent battle-boon category. No event needs or may invent a
separate tax amount; the purchase event reports only gross price, actual boon BPS, and net burn.

Required views:

- both uncommitted pass balances for a player;
- raw or decoded day-state flags for a player/day;
- the two pass denomination constants and two fixed future-purchase prices;
- decoded live battle-boon tier/expiry state; and
- whether a target day is still eligible for either reservation funding path.

No on-chain enumeration of all pass holders or all reservations is required.

## 16. Gas and Liveness Requirements

1. `openBonusDay`, `advanceGame`, window arming, battle settlement, and claims must not iterate
   pass holders, boon holders, or future reservations.
2. Automatic tomorrow delivery makes at most one bounded-gas Craps call and one packed Game
   credit write per lootbox resolution batch.
3. A box that awards neither pass type performs neither operation.
4. `applyCrapsPasses` and `buyFutureCrapsDays` are the only new O(N) paths. Both share one bounded
   internal range-preflight/reservation routine; `uint8` bounds `N` to 255 and the caller pays it.
5. One future-day reservation is expected to cost roughly one cold mapping read plus one
   zero-to-nonzero mapping write, approximately 20k–25k gas before call overhead.
6. Ten applications should be roughly 0.2M–0.3M gas; one hundred roughly 2M–3M; the 255-day
   worst case must be measured rather than accepted from this estimate.
7. Both measured 255-day calls must remain below the repository's 10M normal-path target and the
   16.7M hard transaction ceiling. The FLIP-funded path performs exactly one boon-consumption call
   and one FLIP burn regardless of count.
8. Reserved entry reuses the existing day-state read/write and skips the FLIP burn call; it must not
   add a new per-window storage mapping.
9. An ordinary paid Craps purchase adds at most one authorized Game call when a boon check is
   required; no boon-holder-dependent loop or per-window boon mapping is permitted.
10. Contract deployed sizes must remain below EIP-170 limits after extending the boon module,
    viewer, Game wrapper, and Craps purchase paths.

## 17. Normative Requirements

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

### R5 — Packed pass inventory and battle-boon lane

- **Current:** `boonPacked.slot1` bits 0..71 are unused.
- **Target:** Bits 0..23 and 24..47 hold saturating normal and high balances, bits 48..71 hold the
  independent battle-boon lane, and every existing boon field is preserved.
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

### R9 — Full-day-only reservation redemption

- **Current:** `enterBonusDay` burns the complete cost and creates a day ticket during period 0;
  later calls place separate paid window entries.
- **Target:** A dedicated period-0 reservation path covers the complete seven-window cost once, preserves
  ordinary entry, quest, and settled-action accounting, and cannot fund any partial,
  single-window, or custom entry.
- **Acceptance:** Exact-cost and period-boundary tests prove one consumption, zero burn, seven
  fields joined, paid-seat-equivalent boost action, and rejection on every excluded entry surface.

### R10 — Target-day high multiplier

- **Current:** Paid high entrants quote the already-known daily `H`.
- **Target:** A high reservation is committed while the target word is zero and redemption derives the
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
  manual application, future purchase, reservation consumption, and battle-boon award/use; views
  expose balances, prices, boon state, and day state.
- **Acceptance:** Event-schema tests reconstruct a multi-box mixed delivery, discounted future
  purchase, and later consumption exactly and prove no pass or boon is misidentified.

### R14 — Bounded gas and compatible layout

- **Current:** Daily Craps resolution has no pass loop; Game and Craps layouts are golden-tested.
- **Target:** Daily system paths remain O(1) in pass/boon-holder count, both user reservation loops
  are bounded at 255, and all layout/type changes are reflected in the oracle.
- **Acceptance:** Source-structure and gas tests find no system-path pass iteration, measure the
  two 255-day calls below 10M/16.7M, and pass storage-layout plus EIP-170 checks.

### R15 — Fixed-price future FLIP reservations

- **Current:** A player can buy today's known scheduled entries, but cannot burn FLIP now to reserve
  strictly future unknown normal/high days.
- **Target:** One call atomically burns 25,000 FLIP per normal day or 450,000 FLIP per high day,
  optionally reduced by one live battle boon, and creates 1..255 consecutive reservations identical
  to pass-funded state. Gross price, net burn, premium, and funding source never enter gameplay
  action or reservation/bet storage.
- **Acceptance:** Price, count, range, collision, replay, 10x/100x, failure-rollback, expiry, and
  action-parity tests prove one upfront burn, no redemption burn/refund/top-up, no funding marker,
  and no action from price/premium/discount.

### R16 — Independent battle-discount boon

- **Current:** FLIP Degenerette has an independent 4/8/12% stake-boon lane capped at a 100,000-FLIP
  base; Craps purchases have no equivalent discount boon.
- **Target:** Boon ids 41..43 add an independently packed 4/8/12% Craps purchase discount with
  200/50/10 draw weights, the same 100,000-FLIP cap, expiry, deity, and upgrade-only rules, and
  consumption only on the next successful self-funded FLIP Craps purchase.
- **Acceptance:** Exhaustive draw, EV-normalization, storage-coexistence, expiry/upgrade,
  eligibility, cap/rounding, atomic-consumption, authorization, and action-parity tests match
  Sections 6.1..6.4 without touching any Degenerette lane.

## 18. Acceptance Criteria

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
- [ ] **AC-08:** Normal credits, high credits, and the battle boon occupy only their assigned
  `boonPacked.slot1` lanes; pass balances saturate without wrapping or reverting a lootbox sweep.
- [ ] **AC-09:** A batch makes at most one automatic Craps call and at most one packed credit write.
- [ ] **AC-10:** Eligible empty tomorrow receives exactly one pass; every remaining pass is credited.
- [ ] **AC-11:** An occupied, already-worded, overflowed, reverted, or out-of-gas automatic target credits
  the complete award without loss.
- [ ] **AC-12:** A mixed batch automatically applies one high-roller pass first and credits all remaining
  normal/high passes.
- [ ] **AC-13:** `applyCrapsPasses` accepts 1 and 255 and rejects 0 by ABI/validation; longer runs require
  multiple calls.
- [ ] **AC-14:** Every pass-applied or FLIP-purchased day is strictly future, has a zero daily word,
  and is consecutive.
- [ ] **AC-15:** Any overlap, insufficient credit, invalid type, day overflow, or failed write reverts the
  whole application with no credit debit and no reservation.
- [ ] **AC-16:** A day state cannot simultaneously be seated, normal-reserved, or high-reserved.
- [ ] **AC-17:** Reservations cannot be transferred, canceled, refunded, upgraded, downgraded, or moved.
- [ ] **AC-18:** A missed reservation expires without restoring credit, refunding prepaid FLIP, or
  booking action, and requires no protocol sweep.
- [ ] **AC-19:** Reserved entry is available only in period 0 and joins exactly seven scheduled windows.
- [ ] **AC-20:** Normal reservation redemption stores 1x; high reservation redemption derives and stores/uses the target
  day's genuine 10x or 100x scale without a caller quote.
- [ ] **AC-21:** A valid reserved entry performs no redemption-time FLIP burn and consumes the
  reservation once; `coveredCost` is still calculated for parity/observability.
- [ ] **AC-22:** Paid entry and single-window entry reject a player with a reservation for that day.
- [ ] **AC-23:** Reserved entry preserves chip validation, frozen standing, quest-streak credit, main/high ranking,
  bounty, boost, rider, and payout behavior.
- [ ] **AC-24:** Full-price, battle-boon-discounted, pass-funded, and prepaid copies of an equivalent
  seat contribute exactly the same amount to `_dayStaked` and `_highStaked`, including the
  sole-high extra-bounty rider rule.
- [ ] **AC-25:** Unauthorized Game/Craps pass creation, credit debit, battle-boon consumption, and
  automatic reservation calls revert.
- [ ] **AC-26:** Logs and views reconstruct pass awards/dispositions, future purchases, battle-boon
  awards/consumption, reservations, and consumption; no pass or boon appears as an unexplained generic outcome.
- [ ] **AC-27:** No pass-, boon-, or reservation-holder loop is reachable from `openBonusDay`,
  `advanceGame`, arming, settlement, or claim.
- [ ] **AC-28:** Measured 255-day pass and FLIP applications are each below 10M gas and the 16.7M
  hard transaction ceiling; the FLIP path makes one boon call and one burn call regardless of count.
- [ ] **AC-29:** Game and Craps storage-layout goldens and the EIP-170 deployed-size checks pass.
- [ ] **AC-30:** Existing non-pass lootbox, boon, Degenerette, Craps, high-roller, gas-ceiling,
  RNG-freeze, and storage-coexistence regression suites remain green.
- [ ] **AC-31:** `NORMAL_FUTURE_DAY_PRICE` is exactly 25,000 FLIP and
  `HIGH_ROLLER_FUTURE_DAY_PRICE` is exactly 450,000 FLIP; neither is derived from a pass denomination
  or from the other future price.
- [ ] **AC-32:** A future-FLIP purchase accepts counts 1 and 255, rejects 0, calculates the exact
  checked gross product, performs one upfront burn, and reserves the complete consecutive range.
- [ ] **AC-33:** Any invalid/occupied/worded day, overflow, failed boon call, insufficient FLIP,
  failed burn, or failed reservation write reverts the complete future purchase with no boon loss,
  FLIP burn, pass debit, or reservation.
- [ ] **AC-34:** The same fixed high price is committed before `H` is known and produces the target
  day's genuine 10x or 100x seat with no top-up, refund, surcharge, or second burn; expiry refunds nothing.
- [ ] **AC-35:** Pass-funded and FLIP-prepaid reservations of the same type have byte-identical day
  state, and neither reservation nor bet stores funding, gross price, net burn, tax, premium, or boon use.
- [ ] **AC-36:** Future purchase writes no `_dayStaked`/`_highStaked`; settlement books only the
  ordinary seat-derived action. Gross price, net burn, premium, and boon discount never enter action.
- [ ] **AC-37:** Boon ids 41/42/43 have exact 200/50/10 weights, the full table totals 2,868, and
  exhaustive module/viewer draws plus deity remapping agree for every reachable roll.
- [ ] **AC-38:** The weighted-value formula adds the battle family's 4,000/8,000/12,000-FLIP maxima,
  yielding `BOON_PRICE_WEIGHT = 4,590` while leaving the 10% budget, 1-ETH cap, 50% utilization,
  fixed-value term, and lazy term unchanged.
- [ ] **AC-39:** The battle boon occupies only bits 48..71, coexists with all pass and boon lanes,
  applies upgrade-only replacement, and matches FLIP Degenerette lootbox/deity expiry semantics.
- [ ] **AC-40:** On gross costs below, exactly at, and above 100,000 FLIP, the 4/8/12% boon floors
  the discount exactly as Section 6.3 and never discounts more than 4,000/8,000/12,000 FLIP.
- [ ] **AC-41:** Exactly one live battle boon is consumed by the next successful self-funded paid
  custom, scheduled, daily-bundle, or future-prepay purchase; invalid/zero-entry calls, donations,
  gifts, pass/prepay redemption, house/vault seats, claims, and settlement do not consume it.
- [ ] **AC-42:** A battle-boon-discounted purchase creates identical bankroll, bounty, odds,
  rankings, payout, and settled action to the undiscounted purchase, and never reads or clears any
  Degenerette boon lane.

## 19. Edge Coverage

The canonical edge-completeness classifier raised 59 applicable edges across R1..R14. The update
probe explicitly classified R15 and R16 as numeric-range, collection, stateful, and I/O behavior
and raised seven boundary/adjacency/empty/ordering/precision/idempotency/concurrency edges for each,
for 73 total. The rows below group candidates only when the same acceptance checks resolve every
category named.

**Coverage:** 73/73 applicable edges resolved explicitly; 0 unresolved.

| Categories | Requirement | Status | Explicit resolution |
|---|---|---|---|
| Boundary, precision | R1 | Resolved | AC-01 fixes all twenty buckets and preserves the modulo contract. |
| Boundary, precision, idempotency, concurrency | R2 | Resolved | AC-02..05 pin pre-rounding value, `20N` boundary, per-box ordering, replay, and unbiased rounding. |
| Idempotency, concurrency | R3 | Resolved | AC-05 and AC-07 pin deterministic replay and immutable entropy inputs. |
| Boundary, precision, idempotency, concurrency | R4 | Resolved | AC-06 covers zero versus nonzero and exactly-once fallback. |
| Boundary, precision, idempotency, concurrency | R5 | Resolved | AC-08, AC-15, AC-29, and AC-39 cover zero/max counts, saturation, atomic debit, and every low-slot lane. |
| Adjacency, empty, ordering, idempotency, concurrency | R6 | Resolved | AC-09..12 define empty batches, occupied tomorrow, mixed ordering, retry, and failure disposition. |
| Boundary, adjacency, empty, ordering, precision, idempotency, concurrency | R7 | Resolved | AC-13..15 cover 0/1/255, touching ranges, overlap, ordering, overflow, replay, and atomicity. |
| Adjacency, empty, ordering, idempotency, concurrency | R8 | Resolved | AC-16..18 define mutually exclusive states, replay rejection, and expiry. |
| Idempotency, concurrency | R9 | Resolved | AC-19, AC-21..24 cover period boundary, exactly-once use, paid-seat action parity, and collision with paid entry. |
| Boundary, precision, idempotency, concurrency | R10 | Resolved | AC-14 and AC-20 pin preword commitment and exact 10x/100x derivation. |
| Adjacency, empty, ordering, idempotency, concurrency | R11 | Resolved | AC-09..12 cover accumulation order, empty batch, one call/write, and fail-open retry behavior. |
| Boundary, precision, idempotency, concurrency | R12 | Resolved | AC-08, AC-15, and AC-25 cover max balances, exact debit, authorization, and atomic conservation. |
| Adjacency, empty, ordering, concurrency | R13 | Resolved | AC-26 fixes event identity, aggregate ordering, zero fallback, and view parity. |
| Boundary, adjacency, empty, ordering, precision, idempotency, concurrency | R14 | Resolved | AC-27..30 pin the 255 bound, empty/system paths, stable layout, gas ceiling, and regression behavior. |
| Boundary, adjacency, empty, ordering, precision, idempotency, concurrency | R15 | Resolved | AC-31..36 pin both prices, 0/1/255 counts, touching/occupied ranges, preflight-before-burn ordering, exact multiplication, replay/races, rollback, target-day uncertainty, and action isolation. |
| Boundary, adjacency, empty, ordering, precision, idempotency, concurrency | R16 | Resolved | AC-37..42 pin draw boundaries, empty/expired lanes, independent-lane adjacency, award/consume ordering, cap precision, upgrade/replay behavior, atomic rollback, and concurrent next-purchase consumption. |

## 20. Prohibitions (Must NOT)

The prohibition probe retained seven product-specific constraints. Generic Solidity access control,
reentrancy, arithmetic safety, and EIP-170 compliance remain mandatory but are canonical contract-
audit concerns rather than duplicated bespoke prohibitions.

**Coverage:** 7/7 applicable prohibitions resolved; 0 unresolved.

| Prohibition | Requirement | Status | Verification |
|---|---|---|---|
| A reservation must not be assigned to the current day or to a day whose daily word is already known. | R7, R10, R15 | Resolved | Test: AC-14, AC-20, AC-34 |
| A committed reservation must not become a free option through deferred prepay burn, cancellation, refund, transfer, upgrade, downgrade, or rescheduling after terms are known. | R8, R10, R15 | Resolved | Test: AC-17, AC-18, AC-32..34 |
| Pass randomness must not silently become pseudo-random, admin-selected, block-derived, caller-derived, or participation-dependent. | R3 | Resolved | Test plus adversarial source review: AC-07 |
| The protocol must not auto-seat reservation holders or iterate pass/boon holders during daily system work. | R9, R14 | Resolved | Test/source structure: AC-27 |
| A pass or battle-boon outcome must not be represented to indexers as an unexplained or wrong-category lootbox result. | R13, R16 | Resolved | Test: AC-26, AC-37 |
| Fixed future price, premium, net burn, or battle-boon discount must not enter settled action or force a funding/tax marker into reservation or bet state. | R15, R16 | Resolved | Test: AC-24, AC-35, AC-36, AC-42 |
| A battle boon must not consume a Degenerette lane or be spent by an invalid, zero-entry, gifted, free, protocol-funded, donation, redemption, claim, or settlement path. | R16 | Resolved | Test: AC-39, AC-41, AC-42 |

## 21. Boundaries

### In scope

- Ten percentage points of the regular lootbox main-reward distribution move from flat FLIP to
  Craps day passes.
- Normal pass value rounded to 22,800 FLIP and high-roller value fixed at 19x, or 433,200 FLIP.
- Per-box exclusive denomination and genuine-VRF Bernoulli rounding.
- Zero-pass WWXRP Degenerette fallback.
- Packed normal/high pass inventories in Game storage.
- Fixed future normal/high purchases at 25,000/450,000 FLIP, with one optional battle-boon
  discount and immediate atomic burn.
- One automatic tomorrow reservation per lootbox resolution batch.
- Same-type consecutive future-day reservation application funded wholly by pass credit or FLIP.
- Full-day period-0 reservation redemption for normal and scheduled high-roller seats.
- Funding/tax/discount-blind, paid-seat-equivalent action accounting.
- A separate packed Craps battle-boon family with 4/8/12% tiers, 100,000-FLIP discount-base cap,
  200/50/10 weights, FLIP-Degenerette-equivalent lifecycle, and use on the next eligible purchase.
- Boon-table/viewer/normalization updates while preserving the existing boon budget.
- Events, views, interfaces, storage-layout updates, gas tests, and economic/RNG invariants.

### Out of scope

- Presale-box reward distribution — it uses a separate resolver.
- Individual scheduled-window passes — passes fund the complete early day lane only.
- Custom-battle passes — creator-set custom high multipliers are unrelated to scheduled day-pass value.
- Same-day reservation use — it would reveal terms and `H` before commitment.
- Future prepayment for custom battles or individual windows — fixed prepay covers scheduled full days only.
- Automatic protocol seating or keeper walks over reservation holders — omitted for gas/liveness and chip-choice reasons.
- Transferable, tradable, giftable, refundable, or cash-redeemable passes — credits are account-bound utility.
- Reservation cancellation, upgrade, downgrade, refund, or rescheduling — these would recreate outcome selection.
- Hybrid pass-plus-FLIP funding inside one reservation call — each call chooses one complete funding source.
- Dynamic, participation-based, day-specific, or admin-set future purchase prices — prices are fixed constants.
- Transferable, refundable, or cash-redeemable battle boons — the boon is account-bound utility.
- Applying the battle boon to pass/prepay redemption, gifts, donations, protocol seats, claims, or settlement — only a successful self-funded FLIP purchase consumes it.
- Admin-set pass outcomes, pass grants, boon outcomes, prices, or entropy — random awards are VRF-derived and prices are immutable.
- Any change to Craps odds, goals, bankroll tables, bounties, mystery boosts, ranking, or the 90/10 high-multiplier draw.
- Any change to the lootbox boon budget percentage, 1-ETH cap, 50% utilization assumption, or
  non-flat-FLIP main-reward magnitudes — only the normalized boon table is extended.
- On-chain enumeration of all holders/reservations or cleanup of expired historical words.

## 22. Ambiguity Report

| Dimension | Score | Minimum | Status | Notes |
|---|---:|---:|---|---|
| Goal clarity | 0.98 | 0.75 | Met | Passes, fixed future purchase, and battle-boon outcomes are exact. |
| Boundary clarity | 0.96 | 0.70 | Met | Eligible purchase/reservation surfaces and excluded systems are enumerated. |
| Constraint clarity | 0.95 | 0.65 | Met | RNG, prices, packing, boon lifecycle, commitment, gas, authorization, and action accounting are fixed. |
| Acceptance criteria | 0.96 | 0.70 | Met | Forty-two pass/fail checks cover unit, integration, economic, and gas behavior. |
| **Ambiguity** | **0.04** | **<= 0.20** | **Gate passed** | No unresolved product decision remains. |

## 23. Decision Log

| Perspective | Question resolved | Locked decision |
|---|---|---|
| Researcher | Which existing lootbox emission is replaced? | Two of the three flat-FLIP roll buckets, leaving 5% flat FLIP and adding 10% passes. |
| Economic | What is one normal/high pass worth? | Exact current expectation rounded to 22,800 FLIP; high unit is exactly 19 normal units, or 433,200 FLIP. |
| Simplifier | How are large awards represented? | Normal only through `20N`; above it, high-roller only; no mixed award from one box. |
| RNG integrity | How are fractions rounded? | Genuine lootbox VRF plus domain-separated Bernoulli extraction; never pseudo RNG. |
| Boundary keeper | When may a reservation be created? | Any strictly future, unworded scheduled day; never today, a single window, or a custom battle. |
| Failure analyst | What if tomorrow is occupied or Craps delivery fails? | Credit the complete award; lootbox resolution remains live. |
| Gas | How are consecutive days handled? | User-paid bounded loop, reservation only, no daily subscriber iteration. |
| Economic feedback | Does a pass entry fund future boost? | Yes; the pass replaces real lootbox FLIP emission, so it books exactly the same action as an equivalent paid seat. |
| Specification close | Which type takes an empty tomorrow slot in a mixed batch? | High-roller first; all other passes become credits. |
| Future purchase | What are the fixed FLIP prices? | 25,000 normal and 450,000 high roller, burned upfront; the constants are independent. |
| Accounting simplifier | Does fixed-price premium or boon discount count as action? | No. Only ordinary settled seat action is booked; no funding/tax/discount marker exists. |
| Boon design | What does the Craps boon mirror? | A separate 4/8/12% lane with the FLIP Degenerette family's 100k cap, 200/50/10 weights, expiry, and upgrade rules. |
| Boon boundary | Which call spends it? | The next successful self-funded FLIP Craps purchase, including future prepay; never redemption, gifts, donations, protocol seats, or failed calls. |

## 24. Required Test Matrix

At minimum, the implementation plan must cover:

### Lootbox unit and statistical tests

- Exhaustive roll-bucket mapping for all twenty residues.
- Exact current expectation plus nearest-100-FLIP derivation of `NORMAL_DAY_PASS_VALUE = 22,800 FLIP`.
- `V = 0`, `N - 1`, `N`, `20N - 1`, `20N`, `20N + 1`, `38N`, and large high-pass cases.
- Bernoulli mean, boundary, deterministic-replay, seed-uniqueness, and domain-separation tests.
- Zero-pass WWXRP fallback and nonzero no-fallback tests.
- Per-box threshold versus aggregate-batch non-equivalence regression.
- Exhaustive 0..2,867 boon-table parity across the module and `DeityBoonViewer`, including exact
  200/50/10 battle-boon bands and deity eligible-range remapping.
- Legacy-table versus optimized weighted-average parity with the added 4k/8k/12k-FLIP maximum
  values, `BOON_PRICE_WEIGHT = 4,590`, and total weight 2,868.
- Direct, auto-resolved, recirculated, redemption, afking, and other callers of the shared regular
  lootbox resolver; presale resolver unchanged.

### Storage and integration tests

- All existing boon lanes, the battle-boon lane, and both pass balances coexisting under every
  writer/expiry/consume ordering.
- `uint24` saturation and checked debit.
- Empty tomorrow, normal-full tomorrow, high-full tomorrow, already-worded tomorrow, day overflow,
  Craps false return, Craps revert, and bounded-call out-of-gas.
- Multi-box normal-only, high-only, and mixed accumulation with one call/write.
- Game-only auto reservation and Craps-only credit/battle-boon consumption.
- Storage-layout oracle proving the Game low-bit allocation and Craps mapping-type change.

### Reservation-applicator state-machine tests

- Pass and FLIP counts 1 and 255, zero, start today, start tomorrow, end-day overflow, insufficient
  credit, and insufficient FLIP.
- Occupied first/middle/last day and a daily word present first/middle/last day.
- Exact 25,000/450,000 unit prices and checked aggregate multiplication; high price remains fixed on
  forced 10x and 100x target days.
- One prepay burn for the complete range and no redemption burn, top-up, surcharge, or refund.
- Atomic rollback of Game credit debit, battle-boon consumption, FLIP burn, and Craps reservations.
- Concurrent/replayed application and cross-type overlap.
- Byte-identical pass/prepaid day states and absence of funding/tax/price/discount markers.
- Expiry without credit restoration, action, refund, cancellation, reschedule, transfer, upgrade,
  or downgrade.

### Battle-boon tests

- Independent slot1 bits 48..71 and no read/write/clear of ETH, FLIP, or WWXRP Degenerette lanes.
- Lootbox two-day and deity same-day expiry, 21-bit day handling, expired-lane clear, upgrade-only
  replacement, and no lower/equal-tier refresh.
- Discount bases below, exactly at, and above 100,000 FLIP for all three tiers; integer-floor dust.
- Exact future normal net burns 24,000/23,000/22,000 FLIP and single-high net burns
  446,000/442,000/438,000 FLIP.
- One consumption per successful `enterBattle`, `enterBonusBattle`, bundled `enterBonusDay`, and
  future-prepay call, including a late-day bundle with skipped windows.
- No consumption on invalid/reverted/zero-placement calls, pass/prepay redemption, gifts, donations,
  house/vault seats, claims, settlement, or walkover.
- Boon clear rolls back if Game response, FLIP burn, or any later Craps write reverts; concurrent
  purchases cannot both use the same boon.
- Unauthorized consumption reverts; award and consumption events identify the battle lane.

### Entry and economic tests

- Normal and high reserved entry at period 0 with blank and seven-chip boards, under both pass and
  prepay creation.
- 10x and 100x high-reservation days derived internally.
- Period boundary immediately before and after the full-day lane closes.
- Exact skipped burn, one reservation consumption, seven joined windows, and quest credit.
- Paid day entry and individual-window entry blocked by a reservation.
- Pass-funded, prepaid, full-price, and boon-discounted main/high winners, busts, walkovers,
  contested pots, and sole high rider.
- Identical ranking/gameplay result for full-price, pass-funded, prepaid, and boon-discounted copies
  of the same committed inputs.
- Exact `_dayStaked`/`_highStaked` parity across every funding/discount copy of every seat shape,
  including the sole-high `X` rider; prepayment itself and expired reservations book zero action.
- Gross price, net burn, premium, and boon discount remain absent from action calculations.
- Protocol-funded boosts and donations remain excluded from action on all seat variants.

### Gas and size tests

- Automatic no-award, award-plus-credit, and award-plus-reservation marginals.
- Pass and future-FLIP application gas at 1, 10, 100, and 255 days, proving one boon call and one
  burn call independent of count.
- Reserved entry versus full-price and boon-discounted paid-entry gas.
- No pass-, boon-, or reservation-count-dependent gas in `openBonusDay`, `advanceGame`, arming,
  settlement, or claim.
- Game wrapper, boon-module/viewer, and Craps deployed-size deltas; 10M target, 16.7M hard ceiling,
  EIP-170 size, and existing Craps/lootbox/boon gas suites.

---

*Standalone contract handoff specification; no GSD roadmap phase was created.*
