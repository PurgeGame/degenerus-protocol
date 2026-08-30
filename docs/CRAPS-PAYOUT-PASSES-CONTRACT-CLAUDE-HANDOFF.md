# Craps protocol-award pass split + normal-to-high conversion: Contract Claude handoff

> Status: product design approved by the user on 2026-08-29.
>
> Half of each eligible **protocol-funded** Craps award is targeted for Craps passes. Only whole
> passes are issued; every fractional remainder, cap excess, and uncreditable pass value stays in
> the winner's FLIP credit in the same transaction. Players may also atomically convert nineteen
> uncommitted normal passes into one high-roller pass.

<agent_identity>

You are Contract Claude, the senior Solidity engineer implementing this feature in the Degenerus
Protocol. Work discovery-first from the live repository. Contracts are authoritative for current
behavior; this handoff is authoritative for the approved product delta.

Preserve unrelated work. At handoff authoring time the worktree already contains user-owned edits
in `scripts/craps-high-water-system-sim.cpp` and `test/craps/CrapsViews.sol`, plus untracked Craps
fuzz handler/invariant files. Re-run `git status --short` before editing, inspect overlapping diffs,
and merge with them. Never reset, restore, overwrite, or broadly reformat somebody else's work.

Implement, test, measure, and report. Do not commit, push, deploy, or regenerate deployment ABIs
unless the user separately asks.

</agent_identity>

<domain_knowledge>

## Source truth

Read these before editing:

- `contracts/CrapsBattle.sol`
  - `_passCredits`, `_credit`, `creditPasses`, `deliverPasses`, `_takeCredits`
  - `_payout`, `_laneBoostSplit`, `_foldHigh`, `_payProgressive`
  - `CrapsBattlePaid`, `CrapsHighRollerPaid`, `CrapsProgressivePaid`,
    `CrapsPassesCredited`
- `contracts/storage/DegenerusGameStorage.sol`
  - `NORMAL_DAY_PASS_VALUE = 22_800 ether`
  - `HIGH_ROLLER_DAY_PASS_VALUE = 19 * NORMAL_DAY_PASS_VALUE = 433_200 ether`
- `contracts/modules/DegenerusGameLootboxModule.sol::_rollCrapsPasses`
  - canonical denomination switch: high iff the conversion budget is strictly greater than
    twenty normal units
- `docs/LOOTBOX-CRAPS-DAY-PASS-SPEC.md`
- `docs/CRAPS-BATTLE-SYSTEM-OVERVIEW.md`
- `docs/CRAPS-BATTLE-SYSTEM-DETAILED.md`

If a cited line moved, follow the symbol. If code and prose disagree about existing behavior,
stop and report the exact conflict before changing semantics.

## Existing pass model

- Passes are non-transferable credits in `CrapsBattle._passCredits`.
- Normal count occupies bits 0..31; high-roller count occupies bits 32..63.
- Each lane saturates at `0xFFFFFFFF` for Game-delivered awards.
- Pass issuance does not mint liquid FLIP, reserve a day, or book Craps action.
- Action is booked only if/when a pass-funded seat actually settles.
- A normal pass represents one future ordinary whole-day seat.
- A high pass represents one future 10x/100x high-roller whole-day seat, committed before that
  day's word is knowable.

## Existing payout separation

Do not blur these components:

- entrant bounty and third-party donation: player-funded, always liquid;
- scheduled main-ladder boost: protocol-funded added money;
- contested high-lane extra bounties: player-funded, always liquid;
- contested high-lane boost: protocol-funded added money;
- sole-high rider: one combined pro-rata return over player-funded extra bounty plus admitted
  protocol boost;
- progressive award: protocol-funded liability already counted when it entered the pool;
- shooter-profit boost inside a run: already folded through gameplay and explicitly out of scope;
- custom battle money: player-funded and explicitly out of scope.

## Deployment constraints

A fresh authoring-time `forge build --sizes --skip 'test/**' --skip '*.t.sol'` measured:

- `CrapsBattle`: 23,938-byte runtime; 638 bytes below EIP-170, but only 462 bytes below the
  project's stricter 24,400-byte safety ceiling.
- `DegenerusGame`: 24,424-byte runtime; only 152 bytes below EIP-170.

Re-measure on the live tree. Put no feature code in `DegenerusGame`. Add no storage slot. The final
`CrapsBattle` runtime must be at or below 24,400 bytes, not merely below 24,576.

</domain_knowledge>

<task_definition>

## Objective

Implement both approved features:

1. Convert as much as possible of a 50% target slice of eligible protocol-funded Craps awards
   into whole normal or high-roller pass credits. Pay all unconverted value as FLIP change in the
   same existing Coinflip-credit transaction.
2. Let a player convert nineteen uncommitted normal pass credits into one uncommitted high-roller
   pass credit, atomically and without subsidy.

## 1. Locked deterministic award formula

Use these immutable values inside `CrapsBattle`:

```text
N = 22_800 ether
H = 19 * N = 433_200 ether
HIGH_SWITCH = 20 * N = 456_000 ether
MAX_HIGH_PASSES_PER_AWARD = 30
```

For one eligible, post-standing protocol award `A`:

```text
targetPassBudget = floor(A / 2)

if targetPassBudget <= 20 * N:
    denomination = NORMAL
    unit = N
else:
    denomination = HIGH
    unit = H

wanted = floor(targetPassBudget / unit)
if denomination == HIGH:
    wanted = min(wanted, 30)

credited = min(wanted, available capacity in the selected pass lane)
passValue = credited * unit
liquidProtocol = A - passValue
```

The denomination boundary is strict and matches the lootbox rule:

- exactly `20 * N` targets twenty normal passes;
- one wei above `20 * N` switches the whole pass portion to high passes;
- never mix normal and high passes for one award source.

There is **no Bernoulli rounding** in this feature. Do not hash a word, add an entropy tag, make a
new RNG read, or award the lootbox's WWXRP consolation. Flooring is deliberate because the winner
is already receiving FLIP in this transaction. All fractional pass change stays liquid.

The load-bearing per-transaction identity is:

```text
liquidProtocol + normalPasses * N + highPasses * H == A
```

It must hold exactly after the 30-high cap and after pass-lane saturation. A full pass lane may
reduce `credited`; it must never delete value. Its uncredited units become FLIP automatically via
`liquidProtocol = A - passValue`.

Apply the formula independently to each source. Do not pool a main boost and progressive award
before choosing a denomination or applying the cap.

## 2. Eligible sources and exact integration points

### 2.1 Scheduled main-ladder boost

In `_payout`, split only the scheduled boost after activity-standing ration and `_roundBoost`.

- Entrant bounties stay fully liquid.
- Donations stay fully liquid.
- A custom battle performs no pass conversion.
- `CrapsBattleFinalized.pot` may continue reporting the existing pre-standing advertised figure.
- `CrapsBattlePaid.amount` must remain the actual liquid Coinflip pot credit after pass value is
  removed.

### 2.2 Contested high-lane boost

Where `heads >= 2`, split only `lane`, the admitted protocol boost returned by
`_laneBoostSplit`.

- `heads * (H - 1) * bounty` is player-funded and stays fully liquid.
- `CrapsHighRollerPaid.amount` remains the actual liquid Coinflip credit.

### 2.3 Sole-high boost return

Preserve the current combined-floor rider exactly:

```text
wholeRide = _ride(paid, extraBounty + admittedLaneBoost, bankroll)
protocolRide = _ride(paid, admittedLaneBoost, bankroll)
```

Apply the pass formula to `protocolRide`, then return:

```text
liquidWholeRide = wholeRide - creditedPassValue
```

Do not replace `wholeRide` with separately floored player and protocol rides; their floors can
sum differently. On a Bust, both rides are zero and no pass is awarded. `CrapsBetSettled.paid`
and the sole-rider `CrapsHighRollerPaid.amount` remain actual liquid amounts.

### 2.4 Progressive award

In `_payProgressive`:

- preserve qualification, cutoff selection, common/rare precedence, event/repeat doubling,
  candidate calculation, and standing adjustment byte-for-byte in behavior;
- compute the gross standing-admitted award exactly as today;
- subtract the **whole gross award** from `_progressive`, not only its liquid portion;
- apply the pass formula to that gross award;
- send only `liquidProtocol` to `Coinflip.creditFlip`.

Keep the existing `CrapsProgressivePaid` event signature. Its `paid` field remains the gross
standing-admitted award and therefore exactly the pool debit. Update its NatSpec to say that, once
this feature is active, `paid` can be split between liquid Coinflip credit and pass value. The new
split event below carries the liquid/pass breakdown. This preserves reconstruction of:

```text
poolBefore - poolAfter == CrapsProgressivePaid.paid
```

## 3. Award helper and events

Add one compact internal helper shared by all four sources. It should:

1. choose the denomination from `A / 2`;
2. floor to whole passes;
3. cap a high award at thirty;
4. credit through the existing packed balance;
5. use the **actual** credited count after saturation to calculate pass value;
6. emit the split event only when at least one pass was credited; and
7. return the exact liquid protocol amount.

The smallest implementation may change `_credit` to return `sum - held`; existing callers can
ignore the return. Do not duplicate its saturation or packed-write logic in every payout site.

Add compact source constants and one event, with source values frozen as:

```text
1 = MAIN_LADDER
2 = HIGH_CONTESTED
3 = HIGH_SOLE
4 = PROGRESSIVE
```

Recommended event shape:

```solidity
event CrapsProtocolAwardSplit(
    bytes32 indexed battleKey,
    address indexed player,
    uint8 indexed source,
    uint256 grossProtocol,
    uint256 liquidFlip
);
```

Keep this event compact because `CrapsBattle` is size- and gas-constrained. `_credit` emits the
existing `CrapsPassesCredited(player, highRoller, actualCount)` immediately before the split event;
that log is the denomination/count record, while `grossProtocol - liquidFlip` is its exact pass
value. Document and test that ordering so an indexer can correlate the two without duplicated
fields.

## 4. Player normal-to-high conversion

Add a direct player entry point with a count expressed in desired high passes:

```solidity
function convertNormalToHigh(uint32 highCount) external;
```

Locked rule:

```text
normalCost = 19 * highCount
```

Requirements:

- `highCount == 0` reverts.
- Insufficient normal credits revert.
- A result above the high-lane `0xFFFFFFFF` cap reverts.
- The debit and credit happen in one packed-word write and are all-or-nothing.
- It touches only uncommitted `_passCredits`; existing reservations are unreachable.
- It creates no reservation, burn, mint, Coinflip credit, action, quest, affiliate credit, streak,
  boon, or RNG interaction.
- It is one-way; do not add high-to-normal conversion.
- Use a single canonical conversion event for both lane deltas; do not also emit
  `CrapsPassesCredited`, which would invite indexers to double-count the high addition.

Recommended event:

```solidity
event CrapsNormalPassesConverted(
    address indexed player,
    uint256 normalSpent,
    uint256 highReceived
);
```

Nineteen is the expected-value pass ratio. Do not derive eighteen from the independent retail
reservation prices of 25,000 and 450,000 FLIP; 18:1 would subsidize conversion.

## 5. Explicit exclusions

Do not convert any part of:

- an individual run's bankroll return;
- the scheduled per-shooter profit boost embedded inside that run;
- entrant main bounties;
- high-lane extra bounties;
- third-party donations;
- Craps boons;
- record awards;
- custom-battle pots or seeds;
- lapsed-pass refunds;
- protocol seat funding.

Do not change pass redemption, future-day pricing, the 10x/100x distribution, action accounting,
or the lootbox/presale-box pass resolvers.

## 6. Required tests

### Deterministic formula

- `A / 2 < N`: zero passes and the whole `A` remains liquid.
- `A = 2N`: one normal pass and exactly `N` liquid.
- `A / 2 = 20N`: exactly twenty normal passes.
- `A / 2 = 20N + 1 wei`: high denomination, one high pass, all change liquid.
- Normal and high fractional remainders return as FLIP exactly.
- Thirty-high boundary and thirty-one-high cap path.
- Selected pass lane with zero/partial capacity: only actual credits reduce liquid FLIP.
- Different VRF words with the same `A` produce identical pass counts and liquid amounts.
- For every boundary above, assert exact conservation:
  `liquid + passValue == grossProtocol`.

### Source isolation

- Main: only admitted scheduled boost splits; bounty and donation cash are unchanged.
- Main score zero: denied boost rolls into the progressive and creates no passes.
- Custom battle: no passes and existing payout unchanged.
- Contested high: only admitted lane boost splits; extra bounties stay liquid.
- Sole high: combined-floor `wholeRide` is preserved; only actual protocol ride can become passes;
  Bust awards none.
- Progressive: qualification/rung/candidate unchanged; pool decreases by gross `paid`; cash plus
  passes conserves gross.
- A winner receiving main and progressive awards gets two independently denominated/capped split
  events rather than one pooled conversion.

### Player conversion

- Nineteen normal credits become one high credit.
- Thirty-eight become two.
- Zero reverts.
- Eighteen normals cannot buy one high.
- Insufficient normals revert without either lane changing.
- High-lane overflow reverts without normal debit.
- Existing reservations, action books, and day seats are unchanged.
- Conversion emits exactly one canonical conversion event.

### Invariants and integration

- Resolving a field in one batch or many budgeted batches produces identical pass balances,
  liquid credits, events, winner, and progressive balance.
- Packed normal/high lanes never bleed into each other.
- No new FLIP mint or burn occurs from award splitting or conversion.
- Pass issuance itself books zero action; later redemption retains existing action behavior.
- Existing pool ledger identity still reconstructs from funding, rollover, and gross progressive
  payments.
- Storage layout is byte-identical; no new slot.

Use and extend the existing Craps suites rather than building a disconnected toy harness:

- `test/craps/CrapsPasses.t.sol`
- `test/craps/CrapsProgressive.t.sol`
- `test/craps/CrapsBattle.t.sol`
- `test/craps/CrapsHighRoller.t.sol`
- `test/craps/CrapsSystemEcon.t.sol`
- `test/craps/CrapsResolveBudget.t.sol`
- `test/fuzz/CrapsKeeperBudgetGas.t.sol`
- the live Craps conservation handler/invariant work, if present

`test/craps/CrapsViews.sol` was already dirty at handoff authoring time. Inspect and preserve its
current edits before adding any view/helper needed by tests.

## 7. Simulation, docs, and verification

Update the tracked Craps simulation carefully, preserving the user's current edits, to report at
least:

- normal/high passes issued by source;
- FLIP change returned;
- frequency of the thirty-high cap;
- outstanding pass-days under stated redemption assumptions; and
- pass-funded action's later 12% budget feedback.

Update:

- `docs/CRAPS-BATTLE-SYSTEM-OVERVIEW.md`
- `docs/CRAPS-BATTLE-SYSTEM-DETAILED.md`
- `docs/LOOTBOX-CRAPS-DAY-PASS-SPEC.md` pass-source table

Run and report:

```text
forge test --match-path 'test/craps/*.t.sol'
forge test --match-path 'test/fuzz/Craps*.t.sol'
forge test --match-path 'test/fuzz/invariant/CrapsConservation.inv.t.sol'
forge build --sizes --skip 'test/**' --skip '*.t.sol'
make check-rng-window check-craps-progressive
scripts/layout/storage_layout_oracle.sh
git diff --check
```

Also run the targeted Game/lootbox pass-award tests affected by `_credit` returning a value, and
the worst-case keeper/finalization gas case where main, high, and progressive pass writes all land
on a cold player balance. Record actual `CrapsBattle` runtime size and headroom against 24,400.

No new randomness is introduced, so `check-rng-window` should remain green without a new manifest
entry. If it reports otherwise, classify the exact read rather than editing the manifest blindly.

## 8. Acceptance criteria

- **AWARD-01:** Only the four approved protocol-funded award sources can create payout passes.
- **AWARD-02:** The target slice is `floor(A / 2)` and denomination uses strict `> 20N`.
- **AWARD-03:** Counts are floored; no Bernoulli, entropy, or WWXRP fallback exists.
- **AWARD-04:** Per source and transaction, liquid FLIP plus credited pass value equals `A` exactly.
- **AWARD-05:** A high source credits at most thirty passes; all excess stays liquid.
- **AWARD-06:** Pass-lane saturation cannot delete or strand award value.
- **AWARD-07:** Player-funded bounties/donations and excluded payouts stay fully liquid.
- **PROG-01:** Progressive qualification and gross award are unchanged.
- **PROG-02:** Pool debit equals gross `CrapsProgressivePaid.paid`, not liquid credit alone.
- **CONV-01:** Nineteen normal passes atomically convert to one high pass.
- **CONV-02:** Conversion is one-way, owner-only by `msg.sender`, and cannot touch reservations.
- **CONV-03:** Invalid or overflowing conversion changes neither lane.
- **ARCH-01:** No Game change and no new Craps storage slot.
- **ARCH-02:** `CrapsBattle` runtime is at or below 24,400 bytes.
- **RNG-01:** No new RNG read or hash and identical amounts resolve identically across words.
- **GAS-01:** Worst-case finalization remains inside the keeper/block-gas envelope.
- **DOC-01:** Events and all three canonical Craps/pass docs describe gross, liquid, and pass value
  without implying that passes are an emission sink.

</task_definition>

<interaction_patterns>

1. Start with a concise discovery report: current git status, live source anchors, current runtime
   sizes, and any mismatch with this handoff.
2. If the source matches, implement the locked behavior without reopening settled product choices.
3. If bytecode exceeds 24,400, first consolidate the award helper, reuse `_credit`, and make local
   behavior-identical reductions in `CrapsBattle`. Do not move code into the nearly-full Game and
   do not weaken accounting, caps, events, or validation.
4. If a locked requirement cannot fit or conflicts with a newer user decision, stop before making
   a semantic compromise and present the exact blocker plus the smallest alternatives.
5. Finish with a structured implementation report: files changed, behavioral summary, tests and
   commands with results, runtime size/headroom, gas result, storage result, and remaining risks.

</interaction_patterns>

<guardrails>

- Do not use Bernoulli rounding, fresh entropy, a hash-derived coin, or WWXRP consolation.
- Do not turn player-funded bounty, donation, bankroll, or custom-battle money into passes.
- Do not split before standing; doing so would let passes bypass the activity ration.
- Do not subtract only liquid FLIP from the progressive; the full gross award leaves that ledger.
- Do not let saturation, cap flooring, or fractional dust delete value.
- Do not auto-reserve tomorrow; payout passes are banked credits.
- Do not add transfers, claims, expiration, high-to-normal conversion, or configurable rates.
- Do not derive 18:1 from retail future-day prices.
- Do not add a storage slot or modify `DegenerusGame`.
- Do not accept runtime bytecode above the project's 24,400-byte safety ceiling.
- Do not change Craps winners, rankings, goals, high-water results, progressive rungs, standing,
  pass redemption, or action accounting.
- Do not overwrite the existing dirty simulation, view, handler, or invariant work.
- Do not commit, push, deploy, or discard user changes.

</guardrails>

<examples>

### Correct example 1: exact normal boundary

`A = 45,600 FLIP` gives a 22,800 target. Credit one normal pass worth 22,800 and pay 22,800
liquid FLIP. No coin toss and no remainder.

### Correct example 2: denomination cliff with FLIP change

`A = 1,000,000 FLIP` gives a 500,000 target, above 456,000. Credit one high pass worth 433,200
and pay 566,800 liquid FLIP. Do not issue twenty-one normal passes and do not randomly round to a
second high pass.

### Correct example 3: player conversion

A player with 38 normal and 4 high passes calls `convertNormalToHigh(2)`. The resulting balances
are 0 normal and 6 high, written atomically, with no reservation or action entry.

### Failure mode to avoid

A progressive gross award is 1,000,000. The implementation subtracts only the 566,800 liquid FLIP
from `_progressive`, credits one high pass, and leaves that pass's 433,200 value in the pool. This
counts the pass portion twice. The correct pool debit is the full 1,000,000; the winner receives
566,800 liquid plus one 433,200-valued high pass.

</examples>
