# sDGNRS per-level whale purchases

September 20, 2026. Source reviewed at `9bdd008f`; BUILT the same day in the
working tree (uncommitted). Results are at the end of this document.

## Requested behavior

Replace sDGNRS's once-per-level 5%-of-claimable lootbox top-up with whale-pass
purchases spending at most 25% of its game-side ETH claimable.

Interpret "5 packs" as groups of **five paid whale passes**. Round down to a
whole group: buy 0, 5, 10, 15, etc. paid passes. Each group also receives the
existing bonus pass's tickets, so five paid passes award six passes' tickets.
This interpretation matches the requested zero purchase below a 20-pass balance.

For the ordinary, undiscounted price:

```text
C = sDGNRS game-side claimable at the purchase attempt
P = current whale-pass unit price
budget = floor(C / 4)
packs = floor(budget / (5 * P))
paidPasses = 5 * packs
spend = paidPasses * P
ticketAwardPasses = 6 * packs
```

Use the same raw claimable ledger basis as the existing top-up. At these purchase
thresholds, spending at most one quarter inherently preserves the 1-wei sentinel.
ETH/stETH held by sDGNRS and its prepaid AFKing balance are outside this budget.

| Stored game level | Unit price | Claimable | Paid passes | Spend |
|---|---:|---:|---:|---:|
| 1–3 | 2.4 ETH | <48 ETH | 0 | 0 |
| 1–3 | 2.4 ETH | 48 ETH | 5 | 12 ETH |
| 4+ | 4 ETH | <80 ETH | 0 | 0 |
| 4+ | 4 ETH | 80 ETH | 5 | 20 ETH |
| 4+ | 4 ETH | 100 ETH | 5 | 20 ETH |
| 4+ | 4 ETH | 159 ETH | 5 | 20 ETH |
| 4+ | 4 ETH | 160 ETH | 10 | 40 ETH |
| 4+ | 4 ETH | 240 ETH | 15 | 60 ETH |

The existing per-level latch excludes level 0; retain that timing. Keep the
ordinary daily quantity-one AFKing subscription. The new pass purchase has its
normal bundled lootbox reward; it replaces the percentage-sized AFKing box.
The 25% ceiling applies to the whale purchase, separately from the daily box.

## Choices to settle before implementation

1. **Maximum quantity.** The public whale route currently allows 100 paid passes
   per call. Proposed initial limit: one aggregated purchase, at most 100 paid
   passes per level, with the quantity still rounded to five. This additional
   cap matters above 1,600 ETH claimable at standard pricing. The user has been
   asked whether to retain this limit or support the entire rounded budget.
   A limit is not justified by repeating the ticket range per pack: that repetition
   is unnecessary. Measure the aggregate path before choosing a larger limit.
2. **Discount boons.** Proposed behavior is to retain normal whale pricing,
   including a valid first-pass discount. Factor out the canonical quote and
   choose the largest allowed multiple of five whose **actual total quote** fits
   `budget`. The table and simple formula above describe no-boon purchases.
   A boon can change the exact threshold; early-price purchases need particular
   care because the existing boon branch prices remaining passes at 4 ETH.
   If the 48/80 ETH threshold must be unconditional, use base-price purchases
   without consuming whale boons instead. Do not size at one price and debit at
   another.

## Implementation sequence

1. **Factor the whale purchase into reusable internals.** In
   `contracts/modules/DegenerusGameWhaleModule.sol`, separate quoting, funding,
   and aggregate delivery without changing ordinary player purchase semantics.
   Add an internal-module entry in `IDegenerusGameModules.sol` for the automatic
   purchase. It hardcodes sDGNRS as payer and recipient, uses zero fresh ETH,
   and can only run in GAME's delegatecall context. Do not expose a new public
   GAME function permitting outsiders to trigger repeated reserve spending.
   Preserve player approval checks on the public purchase route; calling that
   public route from a keeper is not the automatic-purchase solution.

2. **Replace the top-up block** at the start of
   `GameAfkingModule.processSubscriberStage`. Run in the existing unlocked,
   pre-RNG stage, before ordinary daily subscription spending, under the explicit
   RNG timing contract below. Read claimable once, size the purchase, then
   delegate to the whale module. Reuse the
   `_sdgnrsBonusLevel` storage slot as the successful-purchase latch; update its
   documentation without moving any packed fields. A successful purchase closes
   the gate for all later chunks/days at that level. Zero affordable packs do
   not spend or latch, preserving the existing ability to retry later that level.

3. **Separate pass delivery from the daily box stamp.** The pass purchase must
   not write `Sub.lastAutoBoughtDay`, replace an unopened AFKing box, or increment
   `_pendingBoxCount`. Let the normal subscription loop handle those fields.
   Account pass lootboxes in the existing lootbox-order ledger. Preserve normal
   whale pool routing, pending-pool handling, participation/stat updates,
   affiliate recycling, presale credit and applicable Craps pass credits.
   The automatic entry passes a blank affiliate code: the affiliate contract
   resolves that to the VAULT default (locking sDGNRS's referral to the vault
   on first use, zero kickback), which is the intended destination. The
   purchase is fully claimable-funded, so only the recycle-rate leg pays.
   Debit claimable and `claimablePool` by exactly the purchase price once.

4. **Keep advancement live.** Preflight expected purchase blockers before any
   debit or latch update, including terminal state and a full lootbox entry
   with no custom box available to absorb the bundled reward. Defer that
   purchase and let subscribers/RNG processing continue; retry on a later
   eligible stage. Keep accounting invariant failures visible. Test every
   external side effect newly reachable from advancement and update its call
   classification. Do not assume the public purchase path is revert-free merely
   because claimable covers the price.

5. **Latch the protocol wallets' seat bit at deploy.** sDGNRS and the vault
   already hold the two construction seats (serials 1 and 2, minted by the
   AFKing Subscription Token constructor), but their `SEAT_CLAIMED` bit in
   `mintPacked_` is never set, so the whale route's `_grantSeatCoin` would mint
   each a second free-tranche seat on its first pass purchase and, for sDGNRS,
   make an AFKing-token call reachable from advancement. Set the bit for both
   wallets in `initProtocolDeity` (the `_registerDeity` write already touches
   the same word, so this is a bit-OR on an existing store, not a new slot).
   After that the seat grant is a pure bit test on every automatic purchase,
   with no external call and no supply-cap revert path. Add a deploy assertion
   that both bits are set and that neither wallet receives a third seat.

6. **Update tests and documentation.** Replace the old percentage-box expectations
   in `test/fuzz/SdgnrsLevelLootbox.t.sol` with a clearly named whale-purchase
   suite. Update storage comments, `_pendingBoxCount` documentation, relevant
   architecture notes and the affected structural manifests.

## RNG timing contract

**Choose unlocked execution.** The automatic purchase stays in the subscriber
stage before `rngGate`, where `DegenerusGameAdvanceModule` currently requires
`!locked && rngWordByDay[day] == 0`. The normal whale award passes
`rngBypass = false` to both `_queueEntryRange` and `_queueHalfPassAward`; retain
that setting. Their shared range helper otherwise reverts `RngLocked()` when
it reaches a far-future level while the game is locked.

Pass the boundary-pinned `processDay` to the automatic-purchase entry and check
the live state before sizing, debiting, consuming boons, writing the level latch,
or granting rewards:

```text
if rngLockedFlag || rngWordByDay[processDay] != 0:
    return without purchasing or marking the level complete
```

Checking the word as well as the lock matters: a VRF-gap replay can be unlocked
with that day's random word already public. Defer to a later eligible pre-RNG
stage. Pending and fulfilled-but-unsettled requests must not trigger a purchase.
Retain the once-per-level success latch across all eligible resumptions.

If gas measurements require a separate resumable purchase stage, place it under
the same two guards and complete its pre-RNG work before requesting randomness.
Do not move the buy into locked settlement/transition housekeeping just to reuse
recent deity writes. Every later call must recheck eligibility before effects.
No manual clearing of the RNG lock or weakening of ordinary whale-buy guards
is part of this design.

## Gas design

**Aggregate all packs into one ticket-range award.** For `k` packs, the paid
quantity is `5k`, the award quantity is `6k`, and the standard leg adds `3k`
whole tickets per level. The early bonus leg adds `120k` entries per eligible
level. The two legs partition the same 100-level span. Because the award
quantity is even, the standard leg needs no extra odd-pass strided walk.
Existing range helpers already express this shape. Never call the complete
purchase routine once per pack or once per pass.

**Budget ticket updates as nonzero-to-nonzero writes, plus one fresh far-end
record.** The agreed baseline is that sDGNRS already has tickets for the first
99 levels of the span through its protocol deity coverage: genesis covers
levels 1-100 and each jackpot-to-purchase transition extends coverage to
`level + 100`. The latch opens in the jackpot phase (the level is promoted at
the last-purchase-day RNG request and the subscriber stage keeps running on
jackpot days), so the buy fires before the transition queues `level + 100`.
The span's last level therefore has NO sDGNRS record at purchase time: budget
exactly one fresh owner registration, one `entryOwnerPosition` write and one
far-future lane append there, on top of 99 nonzero-to-nonzero owed updates.
The deity pass stops one level short in the jackpot phase for this reason; the
whale route does not, and the automatic purchase keeps the whale shape. The
later transition then finds a nonzero record at `level + 100` and adds to it.
Do not size the allowance as 100 fresh registrations. This is an existing-record
assumption for levels 1-99 of the span, not an assumption of EVM access-list
warmth.

Build gas fixtures with that coverage established before the measured
transaction, retaining first-access read costs: level promoted, jackpot phase
active, transition not yet run, far-end level unregistered for sDGNRS. Pin the
coverage invariant at the chosen unlocked purchase hook, including near/far-future
queue keys, write-slot changes and the fresh far-end record. A mismatch requires
correcting the integration timing or queue handling before accepting this
budget. Reuse the existing queue helpers. Other purchase effects, such as the
first bundled lootbox order, still need their own zero-to-nonzero costs where
applicable.

**Batch the sDGNRS reward burn.** Currently each paid pass reads the Whale
reward pool and calls `transferFromPool` separately. A self-award burns supply.
For the automated aggregate purchase, read the starting reserve once and
compute the exact existing recurrence locally:

```text
remaining = startingWhaleReserve
repeat paidPasses times:
    remaining -= floor(remaining / 100)
reward = startingWhaleReserve - remaining
```

Then call `transferFromPool(Whale, SDGNRS, reward)` once. This preserves the
per-pass integer rounding and resulting pool/supply balances, while collapsing
cross-contract calls and storage writes. Emit the aggregated reward transfer;
test event totals as well as balances. Do not substitute a rounded geometric
formula. This local loop still needs an explicit quantity bound.

**Charge the whale purchase to the stage budget.** The current
`SUB_STAGE_WEIGHT_BUDGET` is 2,500 units, but the old top-up executes before
`uint256 weight` is initialized. Move budget initialization ahead of the new
automatic-purchase block. Introduce `SUB_STAGE_SDGNRS_WHALE_WEIGHT`, calibrated
to the selected maximum paid quantity and the most expensive reachable purchase
state under the existing-ticket invariant, including cold first accesses.
Charge that weight before executing the purchase; the normal
subscriber loop starts with that consumed weight, not zero. One purchase plus
an untouched 2,500-unit subscriber allowance is forbidden.

Derive the constant from measurements of the implemented aggregate path:

```text
Gunit = conservative gas bound per existing weight unit, recalibrated across
        lootbox buys, ticket buys, skips and evictions
Gwhale = worst measured incremental automatic-purchase gas, including all
         reward calls, box recording, queue writes, accounting, events and
         the success latch, plus an explicit calibration margin
Wwhale = ceil(Gwhale / Gunit)
subscriber allowance on the purchase call = B - Wwhale
```

`B` starts from the existing 2,500 units and must pass the complete-call bound
below; reduce it if necessary. The existing comments' approximate 3.4k gas per
unit are a calibration starting point, not proof that the new weight is safe.
A single maximum-quantity weight is sufficient initially; smaller buys may
conservatively consume the same allowance. The common no-buy/latched/too-poor
probe and capacity-deferral checks belong in fixed overhead. Later chunks
after a successful purchase use the normal allowance and cannot charge or
execute another whale purchase that level.

**Reserve for work outside the loop.** Define a measured upper bound `F` for
transaction intrinsic gas, routing, stage setup/probes and final accounting,
and `T` for the most expensive reachable continuation after the subscriber
stage, including a same-call RNG request and eligible `mineFlip` bounty work.
Measure direct `advanceGame` and the full keeper route. The existing subscriber
loop checks `weight < B` before an item and charges afterward, so its last item
can overshoot by up to 20 units with the current maximum item weight of 21.
Retaining that loop requires budgeting the overshoot explicitly:

```text
F + (B + 20) * Gunit + T < 10,000,000 gas
```

Recalculate the overshoot if item weights change. Alternatively, preflight the
next item's weight so it cannot exceed the remaining allowance, and prove
cursor/swap-pop progress with that change. In either implementation, retain
the repository's 16.7M hard ceiling as an independent regression gate. The
gap between the <10M design target and hard ceiling is safety headroom; it is
not extra unbudgeted purchase capacity.

**Yield with recorded progress.** When the whale purchase leaves insufficient
room for subscriber work, keep the success latch and return with the subscriber
cursor unfinished; the existing advance stage resumes on the next call before
RNG is requested. Do not advance the cursor over an unprocessed subscriber or
set `subsFullyProcessed` merely because the whale purchase finished. If even
one maximum-quantity purchase cannot fit the calibrated shared-stage budget,
use a dedicated bounded pre-RNG purchase chunk with its own completion signal
and measured envelope. Its successful call returns before running subscribers
or requesting RNG. A fresh purchase chunk must fit by construction; repeated
no-progress budget deferral is not an acceptable fallback. If the purchase
alone exceeds the target, reduce the selected maximum or redesign its work.

Use deterministic work weights and fixed limits in production, consistent with
`scripts/check-gasleft.sh`. Caller-supplied gas must not select how many passes
are bought, discard a purchase, or close the once-per-level latch. An
underfunded transaction reverts atomically. Check later ticket drains and
bundled-box opening costs as well as the immediate purchase.

If quantities above 100 are chosen, define a bounded reward calculation and
verify integer field limits and downstream drain volume. If completion spans
transactions, snapshot and reserve the original budget, track progress, and
apply ticket/pool/box effects exactly once. Recomputing 25% of the remaining
claimable on each call would violate the per-level policy. Do not introduce
unbounded repeated 100-pass purchases inside `advanceGame`.

## Acceptance checks

- Exact thresholds and +/-1 wei boundaries, five-pack rounding, early/standard
  prices, and boon quote/debit agreement; total pass spend never exceeds 25%.
- Successful once-per-level purchase across repeated calls, subscriber chunks,
  days and level changes; zero-budget retry; level-zero and terminal skips.
- Funded automatic purchases succeed through both ticket-range legs while
  unlocked with an uncommitted day word. Pending VRF, buffered fulfillment,
  and unlocked gap replay with a known word perform no automatic purchase,
  debit, boon consumption or success-latch update. A later eligible stage buys
  once; repeated resumes cannot buy twice. Ordinary whale purchases retain
  their existing RNG-lock protection.
- Exact claimable/pool debit with no AFKing-funding fallback or redemption-reserve
  consumption. Confirm ordinary daily spending independently.
- Ticket awards equal the normal bulk-buy shape across all 100 levels,
  including intro and century boundaries, existing deity entries and remainders.
- Aggregate self-reward equals the current per-pass recurrence exactly, including
  tiny Whale reserves and zero rewards; total-supply accounting remains exact.
- Normal bundled rewards, no AFKing box orphaning/counter corruption, and a
  full custom-less lootbox order defers without blocking advancement.
- Cold gas measurements for 0, 5, 10 and the selected maximum passes: established
  nonzero coverage on the first 99 span levels, unregistered far-end level in the
  jackpot phase before the transition, first eligible level, near/far queue
  boundaries, first box order, populated order, frozen pools, full subscriber
  chunks, and later drains. Assert the far-end write set is exactly one owner
  registration and lane append, never more.
- Budget-composition tests: maximum purchase plus the permitted remainder of
  all-ticket, all-lootbox, all-skip, all-eviction and mixed subscriber chunks;
  a completing chunk plus RNG request; and the full eligible keeper route.
  Assert the measured whale weight bounds its cost, charge reduces subscriber
  capacity on the purchase call, and final-item overshoot is covered. Verify
  resume makes progress without duplicate purchases or premature RNG requests.
  Insufficient transaction gas must roll back the debit, rewards and latch.
- Run the focused whale/AFKing/redemption regression suites and advance gas
  suites; run the applicable interface, delegatecall, RNG, external-call,
  pool/write-owner, storage-layout and deployable-size checks described in
  `docs/VERIFICATION.md`. Use isolated build caches and fixtures as documented.

Deliver the measured purchase increment, `Gunit`, calibration margin, whale
weight, stage budget, continuation reserve, complete advance/keeper gas and
selected maximum quantity with the implementation. Record the resulting target
and hard-ceiling headroom. This draft contains no gas result.

## Build results (September 20, 2026, working tree on `9bdd008f`)

- **Code.** `DegenerusGameWhaleModule`: `purchaseWhalePass` split into
  `_whaleBoonState` / `_whaleUnitPrices` / `_deliverWhalePass` (the player route is
  byte-for-byte the same sequence of effects); new delegatecall-only
  `purchaseWhalePassForSdgnrs(processDay)`; `_rewardWhalePassDgnrs(buyer, quantity)`
  batches the per-pass 1% recurrence into one `transferFromPool`; `initProtocolDeity`
  latches both protocol wallets' seat bit. `GameAfkingModule.processSubscriberStage`:
  the 5% top-up block is replaced by the whale delegatecall, latch on non-zero return,
  `SUB_STAGE_SDGNRS_WHALE_WEIGHT` charged to the chunk. Interface entry added; the
  `_sdgnrsBonusLevel` and stage-budget comments updated. No storage layout change.
- **Selected maximum quantity.** 100 paid passes (20 groups), the public route's cap.
- **Boons.** Kept: the automatic quote uses the same first/rest prices as a player,
  boon consumed on the buy; sized against the actual quote.
- **Gas (cold, `vm.cool` on every touched contract, level 4, genesis coverage, far
  end unregistered):** stage call with no purchase 244,112; with 5 passes 2,143,744;
  10 passes 2,144,183; 100 passes 2,151,751. Increment: 1,899,632 / 1,900,071 /
  1,907,639. The 100-level ticket walk dominates; quantity is nearly free.
- **Weight.** `Gunit` = the existing ≈3.4k unit. `Wwhale` = 700 (2.38M), a ≈25%
  margin over the 1.91M measurement; the gas suite asserts increment ≤ 700 × 3,400.
  Subscriber allowance on the purchase call = 2,500 − 700 = 1,800 units. Because the
  purchase costs less than the units it displaces, every chunk composition stays
  inside the existing <10M proof (V56AfkingGasMarginal / AdvanceStageWorstCaseGas);
  the 16.7M hard ceiling is asserted on the measured call as well.
- **Tests.** `test/fuzz/SdgnrsWhaleBuy.t.sol` (16 tests: genesis seat bits, 48/80 ETH
  thresholds, the table, the 100 cap, fuzzed 25% bound, once-per-level, zero-budget
  retry, aggregate ticket shape incl. the fresh level-101 record, exact reward
  recurrence and self-burn, no second seat, full-entry deferral, direct-entry RNG
  lock / committed word / unlocked buy, boon quote+consume, player bulk route) and
  `test/gas/SdgnrsWhaleBuyStageGas.t.sol`. `test/fuzz/SdgnrsLevelLootbox.t.sol`
  removed. Manifests updated: advance-call (whale delivery sites now CRANK-PINNED on
  the new suite, the stage delegatecall and recordCoverBox CRANK-SELF), rng-window,
  pool-write, unchecked. All eleven structural gates green.
- **Sizes (foundry-patched addresses):** WhaleModule 22,665 (1,911 left),
  AfkingModule 18,807, AdvanceModule 24,458 (118 left, comment-only change).
- **Owed off-chain.** The sDGNRS `PoolTransfer`/`Transfer` for a whale buy is now one
  aggregated event per purchase instead of one per pass (same totals); the indexer
  is event-only and should expect the collapsed shape. `MintRecorded` is emitted once
  per protocol wallet at genesis for the seat bit.

