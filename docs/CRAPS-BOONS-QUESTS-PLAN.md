# PLAN — Craps Boons and Quests

> **Boon payout amendment (2026-08-28):** The immediate Coinflip-credit design in this document is
> superseded by [`CRAPS-BOON-BANKROLL-PAYOUT-PLAN.md`](./CRAPS-BOON-BANKROLL-PAYOUT-PLAN.md).
> The quest design, boon IDs/weights/lifecycle, and completed packed-boon-lane work remain in force.
> Where the two documents conflict, the bankroll-payout amendment controls.

**Status:** BUILT — the boon lane, quests and the bankroll-payout amendment all shipped in
`484024ab4`.
**Created:** 2026-08-28. **Revised:** 2026-08-28 (verified against the working tree; see §11).
**Type:** ECONOMIC + CONTRACT + GAS-SENSITIVE.
**Repository artifact:** Standalone implementation plan.
**Primary targets:** `DegenerusGameBoonModule`, `DegenerusQuests`, `FLIP`, `Coinflip`, and
the paid-entry call sites in `CrapsBattle`.

**Relationship to existing specification:** This plan supplements
`docs/LOOTBOX-CRAPS-DAY-PASS-SPEC.md` and supersedes only that document's explicit decision that
Craps boons are out of scope and that paid Craps entry paths remain untouched. It does not change
the existing day-pass denominations, reservation rules, prices, settlement, or pass-credit
behavior.

---

## 1. Goal

Add:

1. A three-tier Craps boon, roughly equivalent to the existing Coinflip boon, which rewards a
   successful self-funded Craps purchase with **bonus Coinflip stake credit**.
2. A normal daily slot-1 quest for successfully joining a paid Craps battle.
3. A level quest for buying a Craps full-day pass, including either:
   - the current day's paid full-day entry before the first scheduled window starts; or
   - one or more future days through `buyFutureCrapsDays`.

The implementation must preserve the full Craps FLIP burn and add effectively no gas to ordinary
non-Craps transactions. `CrapsBattle` and `DegenerusGame` are both close to EIP-170, so substantial
new logic must live in contracts with room: `FLIP`, `DegenerusQuests`, and
`DegenerusGameBoonModule`.

---

## 2. Locked Economic Semantics

### 2.1 Craps boon tiers

Use exact Coinflip-boon parity:

| Boon | Suggested ID | Bonus Coinflip credit | Draw weight |
|---|---:|---:|---:|
| `BOON_CRAPS_5` | 41 | 5% | 200 |
| `BOON_CRAPS_10` | 42 | 10% | 40 |
| `BOON_CRAPS_25` | 43 | 25% | 8 |

IDs append after the existing 1..40 public table rather than reusing historical gaps.

Lifecycle matches the Coinflip boon:

- Lootbox award remains usable through award day plus two days.
- Deity award is usable only on its award day.
- A higher live tier replaces a lower tier and resets its stamp.
- A lower or equal live tier is discarded and does not refresh expiry.
- Expired state is cleared by the normal boon sweep or an attempted consumption.
- One boon supplies at most 100,000 FLIP of bonus base.

### 2.2 Full burn plus Coinflip credit

The boon is **not a purchase discount**. The full Craps price is burned:

```text
grossBurn       = the complete undiscounted price of the ONE burn the boon rides (see 2.4)
bonusBase       = min(grossBurn, 100,000 FLIP)
coinflipCredit  = floor(bonusBase * boonBps / 10,000)
```

Maximum Coinflip credits are therefore 5,000, 10,000, or 25,000 FLIP.

Examples:

- A 25,000-FLIP normal future pass with a 25% boon burns 25,000 FLIP and receives 6,250
  Coinflip credit.
- A 450,000-FLIP high future pass with a 25% boon burns 450,000 FLIP and receives 25,000
  Coinflip credit because the bonus base is capped at 100,000 FLIP.

The credit is ordinary protocol Coinflip credit for the next available flip window. It is not
liquid FLIP at purchase time and retains Coinflip variance.

The credit must enter `Coinflip._addDailyFlip` with `recordAmount == 0`, so it must not:

- consume a Coinflip boon;
- gain BAF draw weight;
- arm or ratchet the biggest-flip record;
- count as a direct self-funded Coinflip deposit; or
- recursively progress a FLIP-volume quest.

`Coinflip.creditFlip` already satisfies every one of those: it calls `_addDailyFlip(player, amount, 0)`,
and each of the boon / BAF / record branches is gated on `recordAmount != 0`. `QUESTS` is already an
authorized `onlyFlipCreditors` caller, so no access change is needed.

### 2.3 Eligible purchase surfaces

| Craps action | Boon eligible | Daily join quest | Level pass quest | Existing day-streak credit |
|---|---:|---:|---:|---:|
| `enterBattle` | yes | yes | no | none |
| `enterBonusBattle` | yes | yes | no | none |
| `enterBonusDay`, period 0 paid full-day lane | yes | yes | yes | +1 normal / +5 high |
| `enterBonusDay`, later paid-window bundle | yes | yes | no | none |
| `buyFutureCrapsDays` | yes | no | yes | none |
| `applyCrapsPasses` | no | no | no | none |
| lootbox/Game pass delivery | no | no | no | none |
| high-window upgrade | no | no | no | none |
| donation | no | no | no | none |
| protocol/vault seat | no | no | no | none |
| settlement, claim, refund, or walkover | no | no | no | none |

`createBattle` opens a table but does not join one and therefore does not progress the daily quest.

A period-0 `enterBonusDay` purchase counts as a level pass purchase only when it successfully buys
the current day's full-day lane before the first scheduled window starts. A late-day bundle is a
set of remaining window entries, not a full-day pass.

The mapping above is exact against the shipped call graph: `_enterDayLane` has exactly ONE caller
(`enterBonusDay` at period 0) and always burns. Reservations do not pass through it — they reach
`_writeDaySeat` through `_reserveDay`. (`_enterDayLane`'s docstring still claims it is "SHARED BY
BOTH DOORS" with a `reserved` parameter; that comment is stale and the parameter no longer exists.
Correct it while editing the function.)

### 2.4 One boon, one burn

**LOCKED.** A boon applies to exactly ONE burn — the first eligible Craps burn that reaches
`FLIP.burnCoinForCraps`. There is no aggregation, no shared remaining cap, and no carry across a
bundle or a transaction.

| Purchase | Bonus base | 25%-tier credit |
|---|---:|---:|
| Single window / custom entry | that entry's gross | ~100-150 FLIP on a small window |
| `enterBonusDay`, period 0 (day lane) | the aggregate seven-window cost, one burn | ~5,700 FLIP |
| `enterBonusDay`, late bundle | the FIRST successful window only | ~100-150 FLIP |
| `buyFutureCrapsDays`, normal count 1 | 25,000 FLIP | 6,250 FLIP |
| `buyFutureCrapsDays`, high count 1 | 450,000, capped to 100,000 | 25,000 FLIP (the ceiling) |

Consequences that follow and must be stated in the UI:

- The 100,000-FLIP cap is now reachable only through `buyFutureCrapsDays` (high at any count, or
  normal at count >= 4). No entry path can approach it.
- A late `enterBonusDay` bundle spans at most **six** windows, not seven — `enterBonusDay` routes
  period 0 to the day lane, so the loop starts at `first = period >= 1` — and the boon is spent on
  the first of them. The remaining five burn at full price with no credit.
- Spending a 25% boon on a ~400-FLIP window pays ~100 FLIP where the same boon on a high future day
  pays 25,000. That is the player's call to make; see §8.3.
- If the call creates no paid entry it must not consume the boon or progress a quest. This holds by
  construction: consumption lives inside `burnCoinForCraps`, which only a real burn reaches.

Because storage clears the lane on consumption, a second burn in the same transaction naturally
finds tier 0 — the rule is self-enforcing and needs no cap arithmetic. Transient state survives only
as a **query-elision** optimization (§4.3), never as economic state.

---

## 3. Quest Semantics

Both new quests are **pass/fail**: one qualifying action completes them. There is no accumulation,
no scaling, and no unit conversion. They are modelled on `QUEST_TYPE_FOIL`, which is already
exactly this shape; §4.4 lists the four sites that mirror and the three FOIL behaviours that must
not be copied.

### 3.1 Daily bonus quest: join a Craps battle

Add `QUEST_TYPE_CRAPS_JOIN = 10`.

- Eligible only for random daily slot 1.
- Selection weight: 1.
- Target: one successful player-funded battle entry.
- Covers custom battles, individual scheduled windows, the early paid full-day lane, and a late
  paid `enterBonusDay` bundle.
- Completes at most once per day through the existing completion mask.
- Uses the existing slot-1 primary-lock rule: outside afking, completing the action before slot 0
  does not pay the secondary reward until slot 0 is complete.
- Reward remains the normal slot-1 reward: 100 FLIP Coinflip credit and +1 quest streak.

**No availability gate is required**, unlike `QUEST_TYPE_DECIMATOR`'s `_canRollDecimatorQuest`.
In `DegenerusGameAdvanceModule`, `CrapsBattle.openBonusDay()` and `quests.rollDailyQuest(...)` sit in
the same block under the same `day == _simulatedDayIndexAt(ts)` guard, with the craps open running
FIRST and writing all seven of the day's windows. So a day that rolls a weighted slot-1 quest has
already opened its windows. The second `rollDailyQuest` call site, in `_finalizeRngRequest`, passes
entropy 0 with `forceFoil`, and a forced slot-1 type never reaches the weighted roll — `CRAPS_JOIN`
is unreachable there. Do not add a Quests -> Craps call to the advance path to check this.

**Known dead zone: the last 15 minutes of each day.** `_currentBonusSlot` returns
`period == _BONUS_PERIODS_PER_DAY` once `elapsed >= 1 days - _EVENT_LEAD`, because the event window
shuts early. Across that 15-minute band `_joinableWindow` reverts `BonusPeriodSpent` and
`enterBonusDay` places nothing, so the quest is completable only through a custom battle — which
needs a battle creator or vault owner to have opened one. That is ~1% of the day and the same band
already exists for every other craps door, so it does not justify a gate; it does need to be stated
in the UI and covered by a test. Outside that band `armBonusWindow` cannot take a window that is
still accepting bets, so the current period is always joinable.

### 3.2 Level quest: buy a Craps day pass

Add `QUEST_TYPE_CRAPS_DAY_PASS = 11`.

- Eligible only for the level-quest roll.
- Selection weight: 1.
- Target: one successful qualifying full-day purchase.
- Qualifying current-day purchase: the paid period-0 `_enterDayLane` path, normal or high.
- Qualifying future purchase: `buyFutureCrapsDays` with any nonzero count, normal or high.
- Buying several future days in one transaction still completes the target once.
- Spending an existing pass credit through `applyCrapsPasses` is redemption, not a purchase, and
  does not count.
- Reward and eligibility remain the existing level-quest rules: 800 FLIP Coinflip credit and +5
  quest streak after the ticket/loyalty gates are satisfied.

**Cost, accepted.** This is materially the most expensive level quest in the game: the cheapest
qualifying purchase is 25,000 FLIP (`buyFutureCrapsDays`, count 1) or ~22,800 FLIP (period-0 full
day), against a flat 800 FLIP + 5 streak. Every sibling level quest is a ~20,000 FLIP **stake** that
mostly returns; this one is a burn into a ~17% realised take, so it costs roughly 4,250 FLIP of
expected value where the others cost near zero. At weight 1 against a 15-type pool (11 when decimator
is disallowed) it lands on ~6-8% of levels. **RULED: accepted as-is** — weight stays 1, the
qualifying set is not widened, and the EV gap is not compensated. Do not re-raise.

### 3.3 Reward stacking on the early full-day purchase

If both new quest types are active and all normal gates are met, a successful period-0 full-day
purchase may receive all three independent streak effects:

- existing day-kept credit: +1 normal or +5 high;
- daily Craps-join quest: +1 and 100 FLIP reward; and
- level day-pass quest: +5 and 800 FLIP reward.

The Craps boon Coinflip credit is separate from those quest rewards.

**Stacking, accepted.** +7 on a normal seat and **+11 on a high seat** from one transaction, plus
900 FLIP. The +11 case is a HIGH-ROLLER day buy — the largest single commitment the table sells, at
the day's own multiple — so a streak worth roughly eleven days is the intended price of it. It is not
farmable: the `_daySeated` latch bounds the day credit to one per address per day, the completion
mask bounds the daily quest, and the version byte bounds the level quest to one per level.
**RULED: intended.** Do not re-raise.

Note that under §2.4's one-boon-one-burn rule the boon credit on this same transaction is the day
lane's aggregate burn (~5,700 FLIP at the 25% tier), not the 25,000 ceiling — that ceiling is a
`buyFutureCrapsDays` figure and cannot co-occur with the day-lane streak credit.

### 3.4 Quest selection without widening the hot loop

Do not simply increase the existing fixed quest-weight array from 10 to 12 and iterate over both
new types on every roll.

Rename `QUEST_TYPE_COUNT` to reflect that it bounds the legacy/base types only — the constant stays
**10**, the `uint16[10]` weight array stays ten wide, and both walk loops keep covering ids 0..9.
Extend `_bonusQuestType` with one context-specific weight-1 tail passed by the caller:

- `rollDailyQuest` supplies `CRAPS_JOIN` as its tail.
- `rollLevelQuest` supplies `CRAPS_DAY_PASS` as its tail.

The tail is added to `total` and answered after the array walk falls through, so it never enters the
array and never adds an iteration. This preserves every legacy type's relative weighting, prevents
either Craps quest from appearing in the wrong context, and adds constant work rather than two extra
loop iterations. Because the tail lives outside the array, `qType >= 10` cleanly identifies "a Craps
quest type" everywhere downstream.

Forced daily FOIL, MINT_FLIP, and DECIMATOR quests retain their existing precedence.

Resulting selection frequency: `CRAPS_JOIN` lands on 1/15 of random daily slot-1 rolls (1/11 when
decimator is disallowed); `CRAPS_DAY_PASS` on 1/16 of level rolls (1/12 when decimator is
disallowed).

---

## 4. Low-Gas / Low-Bytecode Architecture

### 4.1 Packed boon state

Use `boonPacked[player].slot1` bits 0..23, currently free in the shipped storage layout, as a
compact Craps-boon lane:

| Lane bits | Meaning |
|---:|---|
| 0..1 | tier: 0 none, 1 = 5%, 2 = 10%, 3 = 25% |
| 2 | deity-source flag |
| 3..23 | low 21 bits of award day |

Using the low lane avoids shifts on the consumption hot path. Every writer must preserve all
unrelated boon fields. (`slot1` bits 0..71 are free in the shipped layout; this claims the lowest
24 and leaves 48.)

This is deliberately the **same encoding the degenerette lanes already use**, and the Craps boon's
two-day lootbox expiry equals `DEGENERETTE_BOON_EXPIRY_DAYS`. So the lane reuses, unchanged:

- `BP_DEGEN_LANE_MASK`, `BP_DEGEN_LANE_TIER_MASK`, `BP_DEGEN_LANE_DEITY_BIT`,
  `BP_DEGEN_LANE_DAY_SHIFT`, `BP_DEGEN_LANE_DAY_MASK`;
- `_degeneretteLaneLive(lane, currentDay)` verbatim for the live/expired test; and
- `_coinflipTierToBps(tier)` for the 500/1000/2500 decode (the degenerette `tier * 400` decode does
  **not** apply).

The lane is not contiguous with the degenerette lanes at shift 184, so `checkAndClearExpiredBoon`
gets one additional explicit block at shift 0 rather than a fourth loop iteration.

Update together:

- `DegenerusGameStorage.sol` layout comments, masks, and constants;
- `DegenerusGameBoonModule.sol` award, upgrade, expiry, consumption, table, and normalization;
- `DeityBoonViewer.sol` constants and exhaustive roll tree; and
- storage-layout and module/viewer parity tests.

Adding constants and masks shifts no storage slot, so `scripts/layout/storage_layout_oracle.sh`
stays green. `boonPacked` is a public mapping returning `(slot0, slot1)`; the ABI does not change,
but indexer/UI decoders of `slot1` do.

### 4.2 Preserve the size-critical Game façade

Do not add another external wrapper to `DegenerusGame`. It has **89 bytes** of EIP-170 margin and a
new wrapper is ~150-250; there is no other route to `boonPacked`, so this is forced rather than
merely economical.

Reuse the existing trusted `consumeCoinflipBoon(address)` façade selector:

- `msg.sender == COINFLIP` consumes the existing Coinflip boon lane.
- `msg.sender == COIN` consumes the new Craps boon lane.

The Game façade already authorizes exactly those two callers, and `COIN` is currently unused on this
selector — `Coinflip` is the only caller in the tree and it always arrives as `COINFLIP`. Delegatecall
preserves the original caller into `DegenerusGameBoonModule`, so the caller-sensitive behavior belongs
in the module and the Game runtime stays byte-for-byte unchanged. Document the legacy selector's dual
trusted use clearly in both interfaces.

The only added cost to manual Coinflip-boon consumption is one caller comparison inside the boon
module. Credit paths still never call this selector.

### 4.3 Dedicated Craps burn lane in FLIP

Add a dedicated function:

```solidity
function burnCoinForCraps(address player, uint256 grossAndFlags) external;
```

**Flags are packed into the low byte of the amount. RULED — do not relitigate.** This saves one
calldata word per burn (31 zero bytes at 4 gas + one nonzero at 16 ≈ 140 gas) plus the stack and
store work at three call sites, on the cheapest action the game sells. It is safe because a
sub-FLIP Craps price **cannot be constructed in the code as written** — not as a property of the
current preset values, but of the arithmetic:

*Proof.* There are exactly three eligible burn expressions:

```text
_place            (uint256(w.bankroll) + w.stakeUnits * _BATTLE_STAKE_UNIT) * multiple
_enterDayLane     the same, summed over the day's seven periods
buyFutureCrapsDays  count * (high ? 450_000 ether : 25_000 ether)
```

None of them contains a division — only `+` and `*`. Their inputs:

- `w.bankroll` is `bankrollFlip * 1 ether` (`_bonusPreset`) or `played * 1 ether * bankMult`
  (`_customTerms`); both are an integer times `1 ether`.
- `w.stakeUnits` is an integer granule **count** in both paths, multiplied by
  `_BATTLE_STAKE_UNIT = 100 ether`. Note `_bonusPreset` computes it as
  `(bountyFlip * 1 ether) / _BATTLE_STAKE_UNIT`, i.e. `bountyFlip / 100` — the division floors to an
  integer count *before* rescaling, so the product is a multiple of `100 ether` **whatever
  `bountyFlip` is**. The granule, not the table's values, is what forces this.
- `multiple` is 1 or exactly `w.highMult` (`_vetMultiple`), and `count` is a `uint8`. Both integers.

So every burn is an integer multiple of `1 ether`. Since `1e18 = 2^18 * 5^18` and `8 <= 18`,
`256 | 1e18`, and the low byte of every eligible amount is therefore zero. The two wei-denominated
atoms in the entire path are `1 ether` and `100 ether`; producing a fractional price would mean
introducing a sub-FLIP **chip**, which the ten-chip whole-FLIP round model (`played` in whole FLIP,
`played % _BONUS_CHIPS == 0`) does not admit.

**Guard the packing anyway, in `CrapsBattle`.** Tag through one private helper that reverts on a
dirty low byte:

```solidity
function _tag(uint256 cost, uint256 flags) private pure returns (uint256) {
    if (cost & 0xFF != 0) revert BadBurnTag();
    return cost | flags;
}
```

Roughly 35 bytes and ~12 gas against the ~140 saved, and it is not about the 255 wei. A dirty low
byte would OR into the **flags**: a window entry's `JOIN` could silently become `JOIN | PASS` and pay
out an 800-FLIP level-quest reward. The helper turns a future arithmetic change from a silent
wrong-reward into a revert. If `CrapsBattle` size ever forces a choice, demote this to a
test-only invariant — never drop both.

Action flags:

```text
bit 0  paid battle join
bit 1  paid full-day pass purchase
bit 2  normal current-day full-lane streak credit
bit 3  high current-day full-lane streak credit
```

Requirements:

- Exact caller gate: `msg.sender == ContractAddresses.CRAPS`.
- Leave existing `burnCoin` byte-for-byte unchanged for Game, Parimutuel, ordinary Craps burns,
  donations, upgrades, and protocol seats.
- Decode `gross = grossAndFlags & ~uint256(0xFF)` and `flags = uint8(grossAndFlags)`, then burn the
  complete `gross` through the existing held-balance/settled-Coinflip shortfall waterfall.
- Consume the boon on the FIRST eligible burn only (§2.4): call the Game façade, and if a tier comes
  back compute `credit = min(gross, 100_000e18) * bps / 10_000` on **that burn alone**. No remaining
  base, no decrement, no carry.
- Forward the action flags and any nonzero credit to `Quests.recordCrapsAction` in one call.

**Transient state is a query-elision cache and nothing more.** One transient word per player, three
bits:

```text
bit 0  boon lane already queried this transaction
bit 1  join action already reported this transaction
bit 2  pass action already reported this transaction
```

Bit 0 is set unconditionally after the first Game call, including when the tier came back 0 — a
player holding no boon must not be re-queried once per window. Bits 1-2 keep a six-window late bundle
from calling the quest handler six times to report the same daily action. None of these bits carries
value: dropping the whole word would change gas and nothing else, because the boon lane is cleared in
Game **storage** on consumption and a second burn would find tier 0 anyway. That is what makes the
one-boon-one-burn rule self-enforcing rather than transient-enforced.

EIP-1153 transient storage reverts with state, so this adds no atomicity obligation. Mark the bits
before making downstream trusted calls. Any later revert in FLIP, Quests, Coinflip, or Craps must
unwind the burn, boon consumption, transient bits, Coinflip credit, and quest progress atomically.

Because the bits are transaction-scoped and per-player, a smart wallet batching several paid Craps
actions for one address pays for exactly one boon query and one quest report — which is the same
outcome an unbatched sequence gets, since the boon is already spent from storage. There is no
batching edge and no multicall special case to test for value.

### 4.4 Combined Craps action handler in Quests

Add a dedicated handler shaped like:

```solidity
function recordCrapsAction(
    address player,
    uint8 newActionFlags,
    uint256 boonCoinflipCredit
) external;
```

Requirements:

- Exact caller gate: `msg.sender == ContractAddresses.COIN` (`FLIP`).
- Do not widen the shared `onlyCoin` modifier or add CRAPS to every existing quest handler.
- Boon credit is independent of quest availability, primary lock, or level eligibility.
- Route nonzero boon credit through the existing authorized `Coinflip.creditFlip` lane. FLIP is not
  a flip creditor and the handler's callers do not credit on its behalf, so Quests must issue the
  credit itself — the `handleDecimator` shape, not the `handleFlip` shape.
- When possible, combine the boon credit and a completing daily quest reward into one Coinflip
  credit write. Do not broadly refactor existing level-quest reward plumbing merely to save one
  rare call; preserving non-Craps handler gas takes priority.
- Load only the active daily-quest slot for a join-only action and only the packed level-quest
  slot for a pass-only action.
- Return before loading player quest storage when no reported action matches an active quest and
  no day-streak credit is requested.
- Factor the existing whole-day `awardQuestStreakBonus` logic into a private/internal helper so
  the period-0 action retains its +1/+5 behavior without a second Craps-to-Quests call. Once
  `CrapsBattle` stops calling it, the `msg.sender == ContractAddresses.CRAPS` branch on the external
  `awardQuestStreakBonus` is dead — the boon module still reaches it as GAME, so the function stays,
  but decide explicitly whether to drop the CRAPS arm of its gate.

**Pass/fail progress — mirror FOIL exactly. RULED.** `QUEST_TYPE_FOIL` is already a pass/fail,
target-1, count-unit quest, so the two Craps types copy its treatment rather than inventing one.
FOIL's pass/fail machinery is exactly four sites, and mirroring them is the whole of the work:

| Site | FOIL today | Craps addition |
|---|---|---|
| target constant | `QUEST_FOIL_TARGET = 1` | `QUEST_CRAPS_TARGET = 1` |
| `_progressUnit` | `MINT_FLIP \|\| FOIL -> return 1` | `\|\| questType >= QUEST_TYPE_CRAPS_JOIN` |
| `_questRequirements` | `MINT_FLIP \|\| FOIL -> req.mints` | `\|\| qType >= QUEST_TYPE_CRAPS_JOIN` |
| `_questTargetValue` | `else if (FOIL) nativeTarget = QUEST_FOIL_TARGET` | `else if (qType >= QUEST_TYPE_CRAPS_JOIN) nativeTarget = QUEST_CRAPS_TARGET` |

With `_progressUnit` returning 1, `_questTargetValue`'s shared `nativeTarget / _progressUnit(qType)`
tail evaluates 1/1 = 1 — so **no early return is needed** and the division is a no-op, exactly as it
already is for FOIL. That one `||` is also what keeps `_toStoredProgress`, `_toNativeProgress` and
`_questViewData`'s progress read correct for free. Getting `_progressUnit` wrong is the sharpest edge
in the change: the tail would divide 1 by 1e18 to **0**, and `progress >= 0` then completes the quest
unconditionally.

The daily write path copies `_handleFoilPackQuest` beat for beat — `_toStoredProgress(questType, 1)`,
`_setProgressOf`, emit `QuestProgressUpdated`, compare against target, `_secondaryLocked`,
`_questCompleteWithPair`, then `coinflip.creditFlip` on a nonzero reward.

**Do NOT mirror these three FOIL behaviours**, which are specific to it:

- the forced slot-1 assignment on a level's first purchase day (`rollDailyQuest`);
- the `_bonusQuestType` exclusion (`candidate == QUEST_TYPE_FOIL` skip). Craps types are never in the
  weight array at all — they arrive only through the §3.4 tail — so no skip is needed and adding one
  would be dead code; and
- `_foilStreakFloor` / `FOIL_STREAK_FLOOR = 12`. A Craps purchase confers no streak floor.

The level side needs no unit work at all. `_handleLevelQuestProgress` compares a raw `uint128`
against `_levelQuestTargetValue` and never consults `_progressUnit`, so `delta = 1` against a target
of 1 is already pass/fail. FOIL is absent from `_levelQuestTargetValue` (it never rolls as a level
quest), so there is no precedent to copy: add `if (questType == QUEST_TYPE_CRAPS_DAY_PASS) return 1;`
explicitly. Note its unknown-type fallthrough returns 0, which auto-completes the level quest and
announces target 0 in `LevelQuestRolled`; a `target == 0 -> return` guard in
`_handleLevelQuestProgress` is cheap hardening for a landmine that is currently unreachable.

Under §2.4 the handler is invoked at most once per action per transaction: the boon rides a single
burn, and the transient report bits collapse a six-window late bundle to one join report. There is no
repeat-invocation-for-another-chunk path.

### 4.5 Minimal CrapsBattle changes

Replace only the three eligible paid-burn sites:

1. `_place`: `burnCoinForCraps(msg.sender, _tag(cost, JOIN))`.
2. `_enterDayLane`: `burnCoinForCraps(msg.sender, _tag(cost, JOIN | PASS | (high ? HIGH_STREAK :
   NORMAL_STREAK)))`, then remove the existing direct `awardQuestStreakBonus` call — and with it the
   local `IQuestStreak` interface, whose only use this is.
3. `buyFutureCrapsDays`: `burnCoinForCraps(msg.sender, _tag(count * price, PASS))`.

The flag term is a compile-time constant at sites 1 and 3 and a single ternary at site 2, so the
packed word (§4.3) costs no per-site branching beyond the shared `_tag` guard. `_place` needs no new
parameter and no knowledge of which door called it: the transient report bits in FLIP (§4.3) collapse
a late bundle's repeated join flags, which keeps the dedup out of the size-critical contract
entirely.

All other `burnCoin` sites remain unchanged: the high-window upgrade, `donate`, and the protocol/vault
seat's `try burnCoin`.

No new storage, public view, standalone quest call, boon math, or Coinflip-credit call belongs in
`CrapsBattle`.

**Ordering invariant (new, must be tested).** `burnCoin` makes no external calls today; the new
selector reaches Game -> Quests -> Coinflip. Two of the three sites burn before they latch their
seat: `_enterDayLane` writes `_daySeated` via `_writeDaySeat` after the burn, and
`buyFutureCrapsDays` runs `_reserveRun` after it. (`_place` is safe by construction — it sets
`_bonusSeated` before burning, except on a `multiEntry` battle where a second seat is legal anyway.)
The chain is currently non-reentrant into Craps: `Coinflip.creditFlip` calls out to nothing, and
Quests' only Game calls on this path — `recordAfkingSecondary` and `floorAfkingStreakBase` — are pure
state writes. The single Game -> Craps edge in the tree is the afking crank's `keepScheduled`, which
is unreachable from here. That is now load-bearing and needs an explicit test rather than being left
as an accident.

---

## 5. Boon Table and Events

Adding the Coinflip-parity family changes:

```text
BOON_WEIGHT_TOTAL:  2,608 -> 2,856
BOON_PRICE_WEIGHT:  3,270 -> 4,870
```

The added price-weight term is the same nominal maximum-credit term as the Coinflip boon:

```text
200 * 5,000 + 40 * 10,000 + 8 * 25,000 = 1,600,000
```

under the existing closed-form scale (`PRICE_COIN_UNIT = 1000 ether`, so the term contributes
1,600,000 / 1,000 = 1,600). The shipped 3,270 reconstructs exactly as coinflip 1,600 + decimator 350
+ degenerette-FLIP 1,320, which confirms both the scale and the increment.

Append the three new families at the **tail** of the roll tree, after `BOON_DEGEN_WWXRP_12`:
`[2608, 2808) -> CRAPS_5`, `[2808, 2848) -> CRAPS_10`, `[2848, 2856) -> CRAPS_25`. No existing
boundary moves. The deity roll's two skip bands (`BOON_WEIGHT_PRE_DECIMATOR = 982`,
`BOON_WEIGHT_PRE_DEITY_PASS = 1072`) are below the new band and need no adjustment; only the reduced
modulus changes, from `2608 - 50 - 40` to `2856 - 50 - 40 = 2766`.

Use the existing VRF-derived boon entropy; add no new randomness source.

Observable identities:

- `LootBoxReward.rewardType = 14`, with `amount` identifying boon ID 41, 42, or 43 — as built.
  (2, 4, 5, 6 and 8-13 were already in use; 14 was the next free value.)
- A new `BoonConsumed` category for Craps: **6**, not 5 — as built. Categories 1-5 already shipped
  — 1 coinflip, 2 purchase, 3 decimator, 4 degenerette, 5 activity.
- Existing `CoinflipStakeUpdated` reports the resulting bonus stake credit.

The craps family is always deliverable, so `_deliverBoon` needs no new discard branch — only the
deity-pass family is ever permanently dead.

Module and viewer lookup trees must remain exhaustive and bit-identical for every roll in
`0..2,855`.

---

## 6. Gas and Bytecode Constraints

Measured against the working tree on 2026-08-28 (forge and hardhat artifacts agree exactly):

| Contract | Runtime bytes | EIP-170 margin | Estimated delta |
|---|---:|---:|---:|
| `CrapsBattle` | 24,344 | 232 | −120 … +60 |
| `DegenerusGame` | 24,487 | 89 | 0 |
| `DegenerusQuests` | 20,825 | 3,751 | +800 … +1,100 |
| `Coinflip` | 20,069 | 4,507 | 0 |
| `FLIP` | 7,781 | 16,795 | +500 … +900 |
| `DegenerusGameBoonModule` | 12,115 | 12,461 | +400 … +700 |
| `DeityBoonViewer` | 1,698 | 22,878 | +60 |

`CrapsBattle` is the only size risk, and it is projected to **shrink**: dropping the
`awardQuestStreakBonus` call and the `IQuestStreak` interface outweighs three flag-tagged call sites
even after the shared `_tag` guard (§4.3), which is ~35 bytes. The `FLIP` figure fell from an
earlier +700…+1,200 when the shared-cap machinery came out (§2.4).

Mandatory gates:

- `CrapsBattle` must remain at or below the project's 24,400-byte safety ceiling, not merely the
  24,576-byte protocol limit.
- `DegenerusGame` should remain byte-for-byte unchanged; it may never exceed 24,576 bytes.
- Existing `FLIP.burnCoin` must receive no new caller branch or storage read.
- Existing non-Craps quest handlers must receive no additional caller comparison or player-state
  read.
- The quest-selection tail may add constant work only to daily/level quest-roll transactions.
- The new boon lane may add arithmetic to boon award/expiry paths but no storage slot beyond the
  two already used by `BoonPacked`.
- Benchmark `advanceGame(0)` after the quest-table change. The project's bounds are a **<10M soft
  target and a 16.7M hard ceiling**; the binding stage is the x00 jackpot-phase-END advance at
  11.74M, already over the soft target. The tail adds an estimated 100-300 gas to two roll
  functions, so the requirement is that the measured stage does not move, not that it clears 15M.

Craps-specific gas increases are accepted for:

- the first paid burn's Game -> boon-module read, once per transaction. It is paid on **every**
  paid Craps entry, including the cheapest ~400-600 FLIP window join, and cannot be conditioned
  away — FLIP cannot read Game storage without the call, so the check *is* the call. Estimated
  8-12k, and the transient query bit keeps a six-window bundle from paying it six times;
- the first relevant action's FLIP -> Quests call, likewise once per transaction per action; and
- one Coinflip stake write when the boon actually pays.

Worst case for a late bundle is therefore one boon query + one quest report + five elided calls,
not six of each. Estimated +25-40k over the bundle, against roughly +240k under the superseded
shared-cap design.

---

## 7. Security and Economic Invariants

1. **Full payment:** every eligible purchase burns exactly the same gross FLIP as without a boon.
2. **No Craps-state boost:** bankroll, bounty, action accounting, field ranking, pots, and payouts
   are identical with and without the boon.
3. **Bounded liability:** one boon can create at most 25,000 FLIP of Coinflip stake credit, and
   only a `buyFutureCrapsDays` purchase can reach that ceiling (§2.4).
4. **No recursive boon:** the generated credit cannot consume the player's Coinflip boon.
5. **No BAF/record amplification:** generated credit carries no direct-deposit or record weight.
6. **Trusted call chain:** only Craps invokes the special FLIP burn; only FLIP reports the action
   and credit to Quests; only the existing trusted Game façade consumes boon state.
7. **Atomicity:** a failed entry, reservation, burn, quest update, or Coinflip credit restores all
   prior state, including the boon lane and the transient bits.
8. **One boon, one burn:** no transaction, bundle, or multicall can spread one boon across two
   burns or aggregate two burns into one bonus base.
9. **No zero-entry consumption:** a skipped/empty late bundle consumes nothing and progresses
   nothing. This holds by construction — consumption lives inside `burnCoinForCraps`, which only
   `_place` reaches, and a fully-skipped bundle never calls it.
10. **No RNG expansion:** boon selection continues to derive solely from committed VRF-backed boon
    entropy.
11. **No hot-path tax:** ordinary Game/Parimutuel burns and non-Craps quest actions do not touch
    Craps-boon or Craps-quest state.
12. **No reentry into Craps** from the burn's downstream chain, on the pre-latch window described
    in §4.5.
13. **No value in transient state:** deleting the entire transient word changes gas and nothing
    else. Every economic rule is enforced by Game storage.

---

## 8. Economic Effects — Recorded and Accepted

These are consequences of the design, not defects. All three are RULED ACCEPTED; they are recorded
so the choice stays deliberate and is not rediscovered as a finding later.

### 8.1 Every existing boon family is diluted, by a price-dependent amount

The normalization is EV-preserving:
`avgMaxValue = (BOON_FIXED_WEIGHTED_MAX + BOON_PRICE_WEIGHT * P + BOON_LAZY_WEIGHT * L) / BOON_WEIGHT_TOTAL`.
Raising the numerator and denominator together moves boon *frequency*, and the two effects cross
over at **P ≈ 0.116 ETH**:

| Ticket price | Boon draws per box | Existing families' net frequency | Craps share of old rate |
|---|---:|---:|---:|
| 0.04 ETH | ×1.055 | −3.6% | 9.2% |
| 0.116 ETH | ×1.00 | −8.7% | 8.7% |
| 0.24 ETH (x00) | ×0.942 | −14% | 8.2% |

### 8.2 The table prices a Craps boon as if it were a Coinflip boon

It carries the same 1,600 price-weight term, but a Coinflip boon is spendable by anyone holding
FLIP while a Craps boon needs a ≥400-FLIP Craps purchase inside two days. It is not the WWXRP case
(zero value by design, weight carried deliberately) — it is *conditionally* valuable, and the closed
form cannot see the condition. The net is a small cross-subsidy from non-Craps players to Craps
players. Accept, or down-weight the family.

### 8.3 The daily quest can lead a player to waste the boon

The boon is consumed by the **first** eligible Craps burn however small, and `QUEST_CRAPS_JOIN`
steers players toward the cheapest window (~400-600 FLIP). A 25% boon burned there pays ~100 FLIP
where the same boon on a high future day pays 25,000. The Coinflip boon has the same
first-deposit-wins shape, so there is precedent.

**RULED: accepted.** No consumption floor, no opt-in, no ordering hint enforced on-chain. A player
choosing when to spend a boon is playing the game, and a bad choice is theirs to make. Surface the
tier and the remaining expiry in the UI so the choice is informed; do not gate it. Do not re-raise.

---

## 9. Implementation Sequence

### Step 1 — Freeze behavior in tests

Add failing tests for the complete action matrix, boon formula, both quest selectors, current-day
pass qualification, future-pass qualification, exclusions, and atomic rollback.

### Step 2 — Add storage and boon-table support ✅ DONE

Implemented the 24-bit lane, IDs 41-43, weights 200/40/8, the tail-appended lookup tree,
award/upgrade/expiry behaviour, consumption, normalization constants, events, and viewer parity.

Measured after the change (`forge build`):

| Contract | Before | After | Delta | Estimate |
|---|---:|---:|---:|---|
| `DegenerusGame` | 24,487 | 24,487 | **0** | 0 ✅ |
| `DegenerusGameBoonModule` | 12,115 | 12,807 | +692 | +400…+700 ✅ |
| `DeityBoonViewer` | 1,698 | 1,767 | +69 | +60 ✅ |

`DegenerusGame`'s runtime is byte-for-byte identical to the pre-change build apart from the metadata
CBOR tail (which encodes the source hash, so a comment edit necessarily moves it) — verified by
comparing the two artifacts directly. The façade-reuse ruling in §4.2 holds as specified.

Two changes beyond the literal plan text, both to keep the shared lane honest:

1. The 24-bit lane encoding is now shared by two families, so its constants and helper were renamed
   off the degenerette-specific names: `BP_DEGEN_LANE_{MASK,TIER_MASK,DEITY_BIT,DAY_SHIFT,DAY_MASK}`
   -> `BP_LANE_*`, `_degeneretteLaneLive` -> `_boonLaneLive`,
   `DEGENERETTE_BOON_EXPIRY_DAYS` -> `BOON_LANE_EXPIRY_DAYS`. `BP_DEGEN_LANE0_SHIFT` keeps its name:
   it is the base of the three per-currency lanes and is still degenerette-specific. Mechanical, no
   bytecode effect; `test/fuzz/DegeneretteBoonStake.t.sol` declares its own copies and is unaffected.
2. `DeityBoonViewer._boonFromRoll` went `private` -> `internal` so a test harness can subclass and
   drive it directly. Internal linkage either way, so no bytecode change and no ABI entry.

The craps lane is deliberately NOT given a shift constant: it is slot1's low 24 bits, and a
`SHIFT = 0` constant would read as though a shift were happening on the consumption hot path.

New suite `test/fuzz/CrapsBoonLane.t.sol` (9 tests, all passing) covers the four things no existing
suite did: exhaustive **module-vs-viewer** tree parity over `0..2855` (they are independent
transcriptions and nothing compared them before), the deity composed-roll bands, the 5/10/25% decode
against the coinflip table, and lane disjointness in both directions across the shared selector.
`BoonRollTreeParity` and `BoonGasMathParity` were extended to 2,856 / 4,870 and pass.

One existing fixture needed resizing, not weakening. `BoonStaticDiscard`'s
`test_decDrawOutsideWindowIsDeliveredNotDiscarded` opens boxes and asserts a decimator tier lands at
least once, proving the walk is no longer eligibility-gated. Its 150-box sample was pinned to the old
50/2,608 share; at 50/2,856 the fixed seed sequence stopped hitting. The decimator band itself is
provably unmoved — the exhaustive `0..2855` parity confirms boundaries 982..1031 — so the sample was
raised to 400 and the reason recorded at the call site. **This is §8.1's dilution showing up in a
test rather than a defect**, and it is the concrete warning for the rest of the build: any fixture
that depends on a band's SHARE rather than its BOUNDARIES becomes a coin-flip after the table widens.
Expect more of these in Steps 3-5 and resize them; do not relax the assertion.

### Step 3 — Add quest types and the dedicated handler

Implement the context-specific selector tail, the four FOIL-mirror sites from §4.4, daily completion,
level completion, combined day-streak behavior, exact FLIP access gate, and boon-credit forwarding.

### Step 4 — Add the FLIP bridge

Implement the dedicated Craps burn selector with low-byte flag decoding and the `_tag` guard, the
full gross burn, single-burn boon consumption, the three-bit transient query-elision word,
caller-sensitive Game consumption, and bonus-credit forwarding.

### Step 5 — Swap the three Craps call sites

Tag `_place`, `_enterDayLane`, and `buyFutureCrapsDays`; remove the redundant direct day-streak call
and the `IQuestStreak` interface; fix `_enterDayLane`'s stale "SHARED BY BOTH DOORS" docstring.
Build immediately and stop if the 24,400-byte Craps safety ceiling is breached.

### Step 6 — Update interfaces and integration documentation

Update the Game-boon, FLIP, Quests, and Craps-local interfaces plus indexer/UI constants for boon
IDs, reward type, consumption category, quest IDs, and the `slot1` bit layout.

### Step 7 — Complete verification

Run targeted unit/fuzz tests, storage-layout checks, module/viewer exhaustive parity, contract-size
checks, gas snapshots, `advanceGame(0)` bounds, and the complete Forge suite.

---

## 10. Required Tests

### Boon table and storage

- Exact 200/40/8 weights and all boundary rolls.
- Exhaustive module/viewer parity over `0..2,855`. **Both existing parity harnesses carry their own
  independent references and must be extended:** `test/fuzz/BoonRollTreeParity.t.sol` (its
  `_reference` walks `roll < 2608`) and `test/fuzz/BoonGasMathParity.t.sol` (its `_legacyAverage`
  restates the weighted table).
- Updated weighted-average closed-form parity: total 2,856, price weight 4,870.
- Lootbox two-day expiry and deity same-day expiry.
- Upgrade-only replacement and no equal/lower-tier expiry refresh.
- Day-field wrap behavior.
- Craps lane coexistence with every existing boon lane; bits outside 0..23 unchanged in both
  writer orders.

### Burn and credit behavior

- Full gross burn below, at, and above the 100,000-FLIP cap.
- Exact 5%, 10%, and 25% Coinflip credits.
- Normal/high current-day full-lane purchases.
- Normal/high single-day and multi-day future purchases.
- Late `enterBonusDay` spends the boon on its FIRST successful window only; the remaining windows
  burn at full price with no credit and the lane reads tier 0 for the rest of the transaction.
- Only `buyFutureCrapsDays` can reach the 100,000-FLIP base cap; no entry path approaches it.
- **Low-byte invariant, fuzzed:** over the full `_bonusPreset` roll domain (all seven periods, every
  tier and event branch), every `_vetMultiple`-legal multiple, and the full `createBattle` parameter
  domain, `cost % 1 ether == 0` — so tagging is lossless. Separately assert `_tag` reverts
  `BadBurnTag` on a deliberately dirtied amount, so a dirty low byte can never reach FLIP.
- Flags decode exactly: a `JOIN`-tagged window entry never sets `PASS`, and so never completes the
  level quest or pays its 800 FLIP.
- Invalid/reverted purchases restore the boon, burn, Coinflip credit, quest state, reservation, and
  transient lane.
- No credit or consumption on every excluded action.
- Generated Coinflip credit has `recordAmount == 0`: no Coinflip-boon consumption, BAF interval,
  biggest-flip record, or self-funded deposit behavior.
- Gameplay state is bit-identical with and without a boon except for the boon lane and Coinflip
  stake credit.
- A tier-0 (no boon) player is queried once per transaction, not once per burn — the queried flag
  works.

### Daily quest

- `CRAPS_JOIN` is reachable in random daily slot 1 and never rolls as a level quest.
- Custom, scheduled, early full-day, and late-bundle paid entries complete it.
- `createBattle`, future reservation, pass redemption, donation, upgrade, protocol seat, and
  settlement do not complete it.
- Completion is idempotent, respects the slot-1 primary lock, and retains afking behavior.
- Reward is 100 FLIP and +1 streak under existing rules.
- The last-15-minute event-lead band leaves no scheduled window joinable; a custom battle still
  completes the quest there and `enterBonusBattle` / `enterBonusDay` revert or place nothing.
- Target and progress read as 1 and 1 — not 1e18 — through `getQuest`-style views and
  `QuestProgressUpdated`, and `_questRequirements` reports them in `req.mints` rather than
  `req.tokenAmount`. Assert byte-for-byte parity of the view shape against a FOIL quest.
- Neither Craps type is force-assigned to slot 1, appears in the `_bonusQuestType` weight array, or
  triggers the foil streak floor — the three FOIL behaviours deliberately not mirrored.

### Level quest

- `CRAPS_DAY_PASS` is reachable as a level quest and never rolls as a daily quest.
- A successful paid period-0 current-day full-lane purchase completes it.
- `buyFutureCrapsDays` completes it for any nonzero count.
- Late `enterBonusDay`, `applyCrapsPasses`, pass delivery, and automatic seats do not progress it.
- Existing ticket/loyalty eligibility remains mandatory.
- Reward remains 800 FLIP and +5 streak.
- A Craps type never reaches `_levelQuestTargetValue`'s zero fallthrough.

### Gas, size, and adversarial behavior

- `CrapsBattle <= 24,400` bytes and `DegenerusGame <= 24,576` bytes, with `DegenerusGame`'s runtime
  byte-for-byte identical.
- Snapshot direct entry, early full-day, late full-day bundle, and future-day purchase with:
  no boon/no relevant quest; boon only; quest only; and boon plus both quests.
- Prove existing `FLIP.burnCoin` gas is unchanged.
- Prove existing non-Craps quest-handler gas is unchanged within compiler noise.
- Measure boon-active late-bundle worst case: one boon query, one quest report, five elided.
- Prove the transient query bit elides repeat Game calls for a player holding NO boon, not just for
  one whose boon was just spent.
- Smart-wallet multicall test proving one batched transaction spends exactly one boon on one burn and
  cannot exceed 25,000 FLIP of credit.
- Reentrancy/revert harness proving no partial burn, credit, quest reward, or boon consumption, and
  covering the §4.5 pre-latch window on `_enterDayLane` and `buyFutureCrapsDays`.
- `advanceGame(0)` remains within the project's bounds on every affected quest-roll path, with the
  x00 jackpot-phase-END stage unmoved from 11.74M.

---

## 11. Verification Stamp

Checked against the working tree on 2026-08-28 (clean, branch `craps-council-fixes`). Confirmed by
direct source read:

- `boonPacked.slot1` bits 0-71 are free (`DegenerusGameStorage.sol`, `BoonPacked` layout comment).
- `BOON_PRICE_WEIGHT = 3270` reconstructs exactly from the three FLIP-priced families; the Craps
  increment is +1,600.
- `DegenerusGame.consumeCoinflipBoon` gates `COIN || COINFLIP`; the only caller in the tree is
  `Coinflip`, arriving as `COINFLIP`. FLIP never calls it.
- `_enterDayLane` has one caller and always burns; reservations bypass it.
- Every eligible Craps price is a whole-FLIP multiple.
- `Coinflip.creditFlip` passes `recordAmount == 0`; `QUESTS` is an authorized creditor.
- `BoonConsumed` categories 1-5 and `LootBoxReward` types 2, 4, 5, 6, 8-13 were occupied when this
  was written; the craps family took category 6 and type 14, both now shipped.
- In `DegenerusGameAdvanceModule`, `openBonusDay()` precedes `rollDailyQuest(...)` under the same
  wall-day guard; the second `rollDailyQuest` site passes entropy 0 with `forceFoil`.
- `_currentBonusSlot` reports `period == _BONUS_PERIODS_PER_DAY` for the final `_EVENT_LEAD`
  (15 minutes) of each day, so no scheduled window is joinable in that band.
- Quest selection weights: FLIP 4, DECIMATOR 4 (when allowed), LOOTBOX 3, all others 1; slot-1
  pools total 14/10 and level pools 15/11 before the weight-1 tail.
- Sizes in §6 read from `forge-out/` and `artifacts/`, which agree exactly.

Not verified by a fresh build: a full `forge build --sizes` did not finish inside a 900s budget.
Re-run it at implementation time and re-stamp §6.

---

## 12. Non-Goals

- No purchase discount or partial burn.
- No liquid FLIP reward from the Craps boon.
- No change to Craps odds, resolution, pots, payouts, action, progressive, or boost accounting.
- No boon use on pass-credit redemption, upgrades, donations, protocol seats, or settlement.
- No new Craps storage or public view.
- No new randomness source.
- No change to pass prices, pass values, delivery, lapse, or reservation rules.
- No availability gate on the daily Craps quest (see §3.1) and no Quests -> Craps call in the
  advance path.
- No aggregation of a boon across burns, bundles, or batched transactions (§2.4).
- No compensation for the level quest's EV gap and no boon consumption floor (§3.2, §8.3).
- No unpacked flags argument; the low-byte packing is settled (§4.3).
