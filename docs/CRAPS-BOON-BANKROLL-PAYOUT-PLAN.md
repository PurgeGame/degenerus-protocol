# PLAN — Craps Boons as Bankroll-Payout Boosts

**Status:** DESIGN READY — implementation not authorized by this plan.
**Created:** 2026-08-28.
**Type:** CONTRACT + ECONOMIC + PACKING + GAS-SENSITIVE.
**Supersedes:** The immediate Coinflip-credit semantics and plumbing in
`CRAPS-BOONS-QUESTS-PLAN.md`. It does not supersede that plan's quest design, boon IDs, draw
weights, expiry/upgrade rules, or the already-built packed boon lane.

---

## 1. Decision Summary

Yes, the Craps bet word has room.

Reserve **bits 206..208** of the stored `_bets[betId]` word as a three-bit, one-hot boon mask:

| Stored bit | Mask | Boon | Payout boost |
|---:|---:|---|---:|
| 206 | `0x1` | Craps 5 | 5% |
| 207 | `0x2` | Craps 10 | 10% |
| 208 | `0x4` | Craps 25 | 25% |

The current layout leaves bits 206..213 unused and bits 224..255 unused. This allocation does not
touch the player, chip counts, standing, day-span stamp, or seven high-lane flags. Bits 209..213
remain free. Mirror the same mask at bits 206..208 in the packed `CrapsSlipPlaced.bet` event word.

Only one bit may be set. Invalid masks (`3`, `5`, `6`, or `7`) fail closed as no boost in payout
code and are unreachable through the trusted writer. Tests must prove the writer emits only
`0`, `1`, `2`, or `4`.

The boon increases only the slip's **individual bankroll return**:

```text
bankrollPaid = rounded non-bust run payment * entry scale
bonusBase    = min(bankrollPaid, 60,000 FLIP)
boonBonus    = floor(bonusBase * boonBps / 10,000)
paid         = bankrollPaid + boonBonus + soleHighRider
```

The 60,000-FLIP base ceiling produces maximum incremental benefits of:

| Tier | Maximum boon bonus |
|---|---:|
| 5% | 3,000 FLIP |
| 10% | 6,000 FLIP |
| 25% | **15,000 FLIP** |

This is preferable to capping every tier directly at 15,000: a shared base ceiling preserves the
tier spread instead of making sufficiently large payouts flatten all three tiers to the same value.

The boon does **not** increase or influence:

- raw bankroll used for field ranking;
- bust remainder (a bust still pays zero);
- bounty/donation/main-ladder pots;
- the sole-high rider or contested high-lane award;
- progressive awards;
- entry cost, burn amount, day action, or later budget sizing; or
- `CrapsBetSettled.won`, which remains the unboosted scaled run result.

`CrapsBetSettled.paid` becomes the actual credited amount including the bankroll boon.

---

## 2. The Whole-Day Ticket Constraint

A whole-day ticket is one stored bet reused in seven independent window settlements. Therefore a
three-bit tier plus a nominal 15,000 cap is not, by itself, enough to boost every window while
enforcing a 15,000 cap across the ticket. That design would require mutable cap-consumption state.

Do not add that state. Bind one boon to one deterministic settlement:

- A window-local or custom-battle slip applies its stored boon when that slip settles.
- A late `enterBonusDay` bundle stores the boon only on the first **successful** window slip.
- A period-0 whole-day ticket stores the boon once and applies it only to period 0.
- A multi-day `buyFutureCrapsDays` purchase stores the boon only on the first reserved day, and
  that day applies it only to period 0.

For a whole-day ticket, period 0 is the anchor because it is fixed by the bet's structure and can
be known at entry. Never implement "first window resolved": settlement is permissionless after
the words are public, so that rule would let a caller choose the most favorable known outcome or
grief the player by choosing the least favorable one.

If the anchor run busts, the boon pays zero. It does not roll forward to a later window. If the
first prepaid day lapses without opening, its pass reservation follows the existing refund rule,
but the consumed boon is not recreated. Both outcomes keep the rule simple: the boon buys upside
on one committed run, not a guaranteed rebate.

This yields one consumed boon, one boosted bankroll result, and at most 15,000 FLIP of incremental
credit with no new Craps storage slot and no settlement-order discretion.

---

## 3. Entry Data Flow

Keep the dedicated `FLIP.burnCoinForCraps` lane, but change its responsibility:

```solidity
function burnCoinForCraps(address player, uint256 grossAndFlags)
    external
    returns (uint8 boonMask);
```

It must:

1. admit only `ContractAddresses.CRAPS`;
2. decode the low-byte action flags and burn the complete untagged gross amount through the
   existing held/settled-Coinflip waterfall;
3. query and consume the Craps boon at most once per player per transaction;
4. translate the trusted Game result as `500 -> 1`, `1000 -> 2`, `2500 -> 4`, otherwise `0`;
5. return that mask only on the burn that consumed the boon; later burns return zero; and
6. report fresh quest/streak action flags to Quests, without computing or forwarding value.

The current transient `boon queried` and `action flags reported` cache remains a gas-only cache.
The Game's packed boon lane remains the economic source of truth. No transient word holds a payout
amount, cap, or reusable entitlement.

Revise the Quest call to:

```solidity
recordCrapsAction(address player, uint8 actionFlags)
```

The handler continues to own Craps daily/level quest progress and current-day streak credit. It no
longer accepts `boonCoinflipCredit`, accumulates a boon with quest rewards, or credits a boon through
`Coinflip.creditFlip`. Quest rewards still use their existing Coinflip-credit path.

Thread the returned mask through only the eligible paid writers:

### `_place`

- Call `burnCoinForCraps` with `JOIN`.
- Pass the returned mask to `_writeSlip`.
- A late bundle naturally marks only its first successful `_place`; subsequent burns see the
  consumed/query-cached lane and return zero.

### `_enterDayLane`

- Call `burnCoinForCraps` once with `JOIN | PASS | streak flag`.
- Pass the returned mask through `_writeDaySeat` to `_writeSlip`.
- Remove the direct `IQuestStreak.awardQuestStreakBonus` call as already planned; FLIP reports that
  action to the combined Quest handler.

### `buyFutureCrapsDays`

- Call `burnCoinForCraps` once with `PASS` and retain its returned mask.
- Extend `_reserveRun`/`_reserveDay`/`_writeDaySeat` so only `i == 0` receives the mask; every later
  reserved day receives zero.

All non-purchase paths write a zero mask: pass-credit application, Game/lootbox pass delivery,
Vault/protocol seats, upgrades, donations, amendments, refunds, and settlement-created state.

`amendSlip` already replaces only the chip and standing slices, so it must preserve bits 206..208.
`upgradeDayWindows` similarly preserves the field while changing only high-lane flags.

---

## 4. Bet and Event Packing

Update the canonical layout comment in `CrapsBattle.sol`:

```text
bits   0..159  player
bits 160..189  chip counts
bits 190..205  standing
bits 206..208  Craps boon one-hot mask
bits 209..213  unused
bits 214..216  day-span start + 1
bits 217..223  high-lane flags
bits 224..255  unused
```

Add constants equivalent to:

```solidity
uint256 internal constant _BET_BOON_SHIFT = 206;
uint256 internal constant _BET_BOON_MASK = 7;
```

`_writeSlip` must be the single assembler for both storage and `CrapsSlipPlaced`; add the boon mask
to both words at the identical shift. Do not emit a second placement event and do not change the
existing event signature.

Document the event word explicitly. Its existing fields do not overlap the new slice:

- chips end at bit 29;
- shifted bet id ends at bit 159;
- event-only multiple occupies 160..167;
- standing occupies 190..205; and
- the new boon mask occupies 206..208.

Expose the decoded mask/tier through test/read helpers used by indexers, but do not add a production
view solely for it. `CrapsSlipPlaced` plus `BoonConsumed(category = 6)` is the production source.

---

## 5. Settlement Integration

Add one small pure helper for the incremental amount. Its inputs should be the stored mask and the
already-rounded, already-scaled bankroll payment. It must return zero for mask zero, invalid masks,
or a zero bankroll payment.

Apply it in `_resolve` only after:

- `_settlementOf` has rounded the single-copy result and zeroed busts;
- the unboosted `s.paid` has been used by `_foldHigh`/`_ride`; and
- `scale` has been derived from the high flag.

Required ordering:

```text
unscaled = s.paid
ride     = _foldHigh(..., unscaled)       // unchanged
scale    = high ? w.highMult : 1
basePaid = unscaled * scale
bonus    = anchorApplies ? boon(basePaid) : 0
paid     = basePaid + bonus + ride
```

This ordering prevents the boon from increasing high-lane capital, rider returns, rankings, or
pots. The existing batch credit then carries the larger `paid` value with no extra Coinflip call,
array, or settlement credit entry.

For the anchor check:

- if the stored bet slot is a real scheduled window or any custom slot, the mask applies there;
- a slot is a day-ticket slot only when
  `slot < _CUSTOM_SLOT_BASE && slot % _BONUS_SLOTS_PER_DAY == 0`; and
- for that day-ticket case only, the mask applies when
  `w.bound % _BONUS_SLOTS_PER_DAY == 1` (period 0).

The `_CUSTOM_SLOT_BASE` guard is load-bearing: custom slots are sequential and every eighth custom
slot also has remainder zero. Remainder alone must never classify a custom battle as a day ticket.

The public `previewSettlement` must use the same boon helper for window-local/custom slips so its
quoted `paid` remains exact. It already cannot identify which of seven windows a whole-day bet is
being previewed against; do not widen its ABI in this change. Day-ticket settlement parity belongs
in the existing internal test harnesses that supply the window explicitly.

No bet-word clear or decrement occurs at settlement. The structural anchor rule prevents a day
ticket from paying repeatedly, and every window-local mask sits on a slip that settles once. This
preserves the current no-write-per-bet settlement architecture.

---

## 6. Boon Table Normalization

The boon IDs, draw weights, roll-tree boundaries, expiry, upgrade-only behavior, and packed Game
lane remain unchanged:

```text
CRAPS_5   weight 200
CRAPS_10  weight 40
CRAPS_25  weight 8
BOON_WEIGHT_TOTAL = 2,856
```

The maximum-value contribution changes because the payout-base cap is 60,000 FLIP:

```text
200 * 3,000 + 40 * 6,000 + 8 * 15,000 = 960,000
960,000 / PRICE_COIN_UNIT(1,000) = 960
```

Therefore update:

```text
BOON_PRICE_WEIGHT: 3,270 -> 4,230
```

The in-progress immediate-credit implementation currently uses `4,870`; that value belongs to
the superseded 5,000/10,000/25,000 maximums and must not survive this change. Update the independent
gas-math parity reference and every explanatory comment with the constant.

Keep the existing max-value normalization model for this change rather than redesigning the entire
boon draw-frequency system around realized Craps outcome EV. Record the realized EV separately in
the Craps simulator so a later balancing decision has evidence.

---

## 6a. Verification Stamp (checked against the tree, 2026-08-28)

Every load-bearing claim in §1, §2 and §5 was read out of the source rather than assumed:

- **Bit space.** Stored word: player 0..159, chips 160..189 (`_BET_CHIPS_MASK 0x3FFFFFFF`),
  standing 190..205 (`0xFFFF`), day-span 214..216 (`_BET_DAYFROM_SHIFT`), high flags 217..223
  (`_BET_DAYHIGH_MASK 0x7F << 217`). Bits **206..213 are free**; 206..208 taken, 209..213 spare.
- **Event word.** `chips | (betId << 32) | (evMult << 160) | (standing << 190)`. Chips end at 29;
  `betId` is `(slot << 64) | seat` with a 32-bit seat and a slot under 2^41, so shifted it ends near
  bit 137; `evMult` is a byte at 160..167. Bits 206..208 are free at the identical shift.
- **Single assembler.** `_writeSlip` is the only writer of both words — confirmed, so the log cannot
  drift from storage.
- **Anchor predicate already exists.** `amendSlip` uses
  `slot < _CUSTOM_SLOT_BASE && slot % _BONUS_SLOTS_PER_DAY == 0` for exactly this classification.
  `_daySlotOf(day) = day * 8` (remainder 0) and `_slotOf(day, p) = day * 8 + p + 1` (period 0 →
  remainder 1). `_CUSTOM_SLOT_BASE = 1 << 40` is divisible by 8, so the guard is load-bearing as §5
  states — every eighth custom slot would otherwise read as a day ticket.
- **Settlement ordering.** `_resolve` computes `ride = _foldHigh(..., s.paid)` on the UNSCALED
  figure, runs `_scoreBattle`, then `scale = hi ? w.highMult : 1`, then `paid = s.paid * scale +
  ride`. The bonus inserts between `basePaid` and `+ ride` and provably cannot reach the rider,
  ranking, `staked` (derived from `w.bankroll * scale`) or `won`.
- **Bust safety.** `cost = ... + (paid != 0 ? _CREDIT_UNITS : 0)`; a bust makes `basePaid` zero and
  `floor(0 * bps)` zero, so credit-unit accounting is unchanged.
- **`amendSlip` needs no edit.** It rewrites `header` clearing only the chip and standing slices, so
  bits 206..208 survive by construction.
- **Price weight.** 200x3,000 + 40x6,000 + 8x15,000 = 960,000 / 1,000 = 960; 3,270 + 960 = **4,230**.

**Dilution improves versus the superseded 4,870.** Existing boon families keep more of their
frequency, and the point where boons start getting rarer moves out to a ~0.23 ETH ticket price:

| Ticket price | existing-family frequency @4,870 | @4,230 |
|---|---:|---:|
| 0.04 ETH | 0.964 | **0.978** |
| 0.12 ETH | 0.911 | **0.945** |
| 0.24 ETH | 0.860 | **0.911** |

**Open risk.** `CrapsBattle` had 232 bytes of margin before this change. The superseded design was
projected to SHRINK it; this one adds mask threading, `_tag`, `_boonBonus` and `_boonAnchored`
against that margin. Measure before writing anything further.

---

## 7. Current Working-Tree Delta

As of this plan, the working tree already contains parts of the superseded design. Preserve the
valid work and revise only its value path:

### Keep

- boon IDs 41..43 and weights 200/40/8;
- the `boonPacked.slot1` low 24-bit lane;
- award, upgrade, expiry, sweep, and caller-sensitive consumption;
- module/viewer roll-tree parity;
- `BoonConsumed` category 6 and `LootBoxReward` type 14;
- the new daily/level quest types and their selection tail; and
- FLIP's low-byte action tagging and transient query/report elision.

### Revise

- `FLIP.burnCoinForCraps` returns a one-hot mask instead of calculating `credit`;
- remove `CRAPS_BOON_MAX_BASE` and all boon-credit math from FLIP;
- `IDegenerusQuests.recordCrapsAction` drops the credit parameter;
- `DegenerusQuests.recordCrapsAction` no longer forwards boon value to Coinflip;
- `BOON_PRICE_WEIGHT` and parity references change from 4,870 to 4,230; and
- add the bet-word threading and settlement math in `CrapsBattle`.

No existing user change should be reverted wholesale. Make targeted edits against the dirty tree.

---

## 8. Implementation Sequence

### Step 1 — Freeze the new contract in tests

Add failing tests for the exact bit slice, one-hot validity, 60,000-FLIP base cap, tier maxima,
anchor rule, and exclusions before changing Craps settlement.

### Step 2 — Convert the FLIP/Quest bridge

Change the FLIP return value and remove immediate boon credit. Narrow the combined Quest handler to
action flags while retaining daily quest, level quest, and streak behavior. Prove ordinary
`burnCoin` and non-Craps Quest paths are byte/gas unchanged.

### Step 3 — Thread the mask into slips

Update `IFlipCoin`, `_place`, `_enterDayLane`, `buyFutureCrapsDays`, `_reserveRun`, `_reserveDay`,
`_writeDaySeat`, and `_writeSlip`. Mirror the bits into `CrapsSlipPlaced`. Build immediately because
`CrapsBattle` is size-constrained.

### Step 4 — Boost only the bankroll payment

Add the shared pure bonus helper and deterministic anchor predicate. Integrate after scale and after
the rider calculation. Update preview/test readers and settlement documentation.

### Step 5 — Reprice the boon table

Change the price weight to 4,230, update independent parity models, and add an outcome-aware scenario
to `scripts/craps-system-sim.cpp` without changing the contract's existing max-value normalizer.

### Step 6 — Verify and size-gate

Run the targeted Craps, boon, Quest, storage-layout, interface, bytecode, gas, and full-suite gates.
Do not accept an EIP-170-only pass: `CrapsBattle` must remain at or below the project's 24,400-byte
safety ceiling.

If the new settlement helper breaches 24,400, first reclaim bytes from the removed direct Quest
call/interface and obsolete immediate-credit plumbing. Do not weaken the 15,000 cap, anchor rule,
or packed-field validation to make size.

---

## 9. Required Tests

### Packing and propagation

- Existing headers with every legal chip/standing/day/high combination remain unchanged outside
  bits 206..208.
- Masks `1`, `2`, and `4` round-trip through storage and `CrapsSlipPlaced`.
- Masks with multiple bits never originate from FLIP; invalid injected masks pay zero.
- `amendSlip` and `upgradeDayWindows` preserve the boon mask.
- Pass redemption, delivered passes, Vault seats, donations, and upgrades write no mask.

### Formula and cap

- Exact 5%, 10%, and 25% results below the 60,000 base ceiling.
- Exact boundary behavior at 60,000 and above it.
- Maximum bonuses are exactly 3,000, 6,000, and 15,000 FLIP.
- Fractional percentage results floor only at the final integer division.
- Bust, zero payout, bounty pots, high riders, contested lanes, and progressive payouts are not
  increased.
- High entries calculate the base from the scaled bankroll payment, then apply the 60,000 cap.
- `won` and ranking are identical with and without a boon; only `paid` and Coinflip credit differ.

### One-boon/one-anchor behavior

- A custom/window slip receives at most one boost.
- Custom slots on both sides of every modulo-8 boundary, especially remainder zero, receive their
  boost and are never classified as day-ticket slots.
- A late bundle marks only its first successful placed slip, including when earlier windows are
  skipped as closed/already-seated.
- An early whole-day ticket boosts period 0 and none of periods 1..6.
- Settling periods out of order cannot move the boost away from period 0.
- A period-0 bust pays no boon and does not roll the entitlement forward.
- A multi-day future purchase marks only the first reserved day and only its period 0.
- A reverted entry restores burn, boon lane, transient cache, quest state, and bet word.
- A smart-wallet transaction with several eligible burns consumes and attaches at most one boon.

### Quest separation

- Craps join/pass quests and day streak still progress from their action flags.
- No boon-only Coinflip credit occurs at entry.
- Quest rewards remain unchanged and cannot be folded into the later settlement boon.
- Players with no active relevant quest do not receive an entry-time Coinflip write from the boon.

### Parity, gas, and size

- Module/viewer roll parity remains exhaustive over `0..2,855`.
- Weighted-max parity uses 4,230 and the independent Craps term of 960.
- Storage-layout oracle stays green.
- `previewSettlement` equals actual `paid` for boon-bearing local/custom slips.
- Internal day-ticket preview harness equals each actual window settlement.
- Direct entry, late bundle, early day lane, and future-day purchase gas snapshots cover no boon and
  each tier.
- Settlement budget accounting remains valid: a boon never turns a zero-paying bust into a credit,
  so `_CREDIT_UNITS` classification does not change.
- `CrapsBattle <= 24,400` runtime bytes; `DegenerusGame <= 24,576` and retains the existing façade
  behavior; `advanceGame(0)` remains within the project's stage bounds.

---

## 10. Acceptance Criteria

The change is ready only when all of the following are true:

1. A paid Craps entry still burns the full gross amount.
2. No Craps boon generates entry-time Coinflip credit.
3. Exactly one stored slip carries the consumed boon mask.
4. The mask occupies only bits 206..208 and is visible in `CrapsSlipPlaced`.
5. Only the rounded/scaled bankroll payment receives the percentage.
6. The top tier can add no more than 15,000 FLIP; lower tiers cap at 3,000 and 6,000.
7. A whole-day or multi-day purchase cannot multiply one boon over several settlements.
8. Settlement order cannot select or deny which known window receives the boost.
9. Pots, riders, progressives, ranking, action accounting, and Quest rewards are unchanged.
10. All targeted/full tests, layout checks, parity checks, gas checks, and bytecode ceilings pass.

---

## 11. Non-Goals

- No purchase discount or partial burn.
- No immediate boon Coinflip credit.
- No liquid FLIP payment.
- No boost to bounty, rider, progressive, ranking, or action accounting.
- No mutable per-bet cap ledger and no new storage slot.
- No rollover after an anchor bust or lapsed prepaid day.
- No player-selected settlement target after RNG is known.
- No change to boon IDs, weights, expiry, upgrade rules, or quest qualification.
