# VRF stall recovery and catastrophic terminal claims

Status: implementation plan, not implemented. September 20, 2026.

## Agreed behavior

1. Correctness, preserved financial liabilities, RNG integrity, and bounded gas
   take priority over usability during an exceptional outage.
2. Allow up to one calendar-day index of lag. Pause ordinary actions that create
   daily-RNG obligations when `wallDay > dailyIdx + 1`. Do not introduce a pause
   at every rollover or simply because an ordinary VRF request is pending.
3. Gate action entry points. Do not indiscriminately gate shared credit helpers,
   VRF fulfillment, or the settlement calls needed by `advanceGame` to recover.
4. Preserve the lootbox queue's use of subsequent eligible real VRF. There is no
   requirement to keep lootbox opening/settlement available during the pause.
   Do not add deferred-credit balances or a special accommodation for boxes.
5. Recovery may finish the outstanding daily commitment and backfill one extra
   accepted day. Using an already-committed word followed by a fresh recovery
   word is acceptable; minimizing request count must not weaken RNG boundaries.
6. A full calendar day without daily VRF should count as no played day for most
   gameplay systems. The permitted settlement backfill does not recreate those
   days' gameplay, rewards, or repeated automatic actions.
7. Normal game over continues to use real VRF and its normal terminal jackpot.
8. Catastrophic VRF failure instead activates irreversible, deterministic claims:
   split the distributable pot equally among eligible traits and then equally
   among ticket occurrences within each trait.
9. Only occurrences already materialized in the frozen terminal trait buckets
   qualify. Unassigned tickets get nothing. Do not run a ticket/foil assignment
   drain or invent entropy to make them eligible in catastrophic mode.
10. Keep emergency claim bookkeeping out of purchases and ordinary ticket
    materialization. Use the existing packed trait buckets as ownership evidence.

The unassigned-ticket forfeiture is an explicit exception to fund preservation.
It is not authorization to erase existing claimable winnings or unrelated
reserved financial obligations.

## Calendar time, played days, and settlement are different

Keep the wall-clock day used by the admission guard separate from the notion of
a played day. A day key can identify an old obligation without proving that a
daily game actually ran on that date. Do not change `currentDayView()` or replace
all `GameTimeLib` calls with a logical counter without auditing their consumers.

| System | Treatment of a whole missing daily-VRF day |
| --- | --- |
| Quest and purchase streaks | No missed-day penalty and no free streak increment |
| Daily quest/boon/foil boards and daily awards | No synthetic historical opening or award |
| Coinflip auto-rebuy | No additional flips, compounding, or recycling bonuses for empty days |
| Automatic purchases and subscription deliveries | No catch-up purchases, charges, or rewards merely because calendar time passed |
| Level/jackpot progression | No extra stage advancement for empty days |
| Gameplay-duration benefits and participation windows | Preserve remaining playable duration where the rule measures access to gameplay; audit each expiry |
| Purchase-phase inactivity accounting | Exclude outage days from gameplay inactivity while preserving a separate real-time escape |
| VRF request age, recovery governance, catastrophic timeout | Continue using real elapsed time |
| Normal post-terminal withdrawal/sweep deadlines | Retain explicit terminal rules; do not accidentally pause them with gameplay time |

Previously executed purchases or accepted wagers are not rolled back merely
because their calendar day later becomes a skipped day. Settle the bounded
outstanding obligations under their original commitment rules. Existing paid
work is different from generating additional work for missed days.

Record enough request/fulfillment provenance to distinguish an absent daily
word from a timely delivered word whose processing was delayed. A keeper must
not choose whether a day happened by withholding the processing transaction.
A lootbox-only fulfillment must not manufacture a played daily epoch. A late
daily fulfillment can discharge old commitments without retroactively granting
the missing calendar days daily benefits.

Prefer existing unrolled-day and gap-forgiveness mechanisms where sufficient.
Any additional gap accounting should be aggregate or range-based, updated on
recovery, not a per-player sweep or a loop over all missed dates. Explicitly
classify boon expiry, AFKing tenure, pass claim windows, decimator windows, and
other day-based features before treating the clock audit as complete.

## Bounded recovery contract

Example: day 100 is complete. Day 101 is allowed by the one-day grace and can
accept obligations targeting day 102. At day 102 the guard closes. If recovery
occurs on day 110, it can owe the original day-101 cohort and the extra day-102
cohort; days 103–109 must not accumulate more daily wagers or simulated flips.

"One day of backfill" means that one extra accepted cohort, not every date
between the old index and the wall clock. Simply reducing the current
`GAP_BACKFILL_MAX_DAYS` constant to one is not sufficient.

- Bind accepted inputs to immutable request/cohort boundaries. Never use an
  already-public word for later accepted inputs.
- Preserve a valid delivered result for its commitments. Request a fresh word
  for additional eligible commitments if necessary; domain-separate derived
  values by their original day and purpose.
- Freeze the recovery boundary once. Do not extend the historical cohort each
  time a recovery transaction crosses midnight.
- Handle the extra cohort, then skip the empty interval without writing fake
  words, coinflip results, daily draws, or rewards for every missing date.
- Do not prematurely advance the public freshness marker and reopen entry while
  historical commitments remain unresolved. Current `rngGate` moves `dailyIdx`
  during gap handling, before the final seal; this ordering needs explicit work.
- Advance claim cursors across skipped ranges without stranding accepted stakes.
  Keep stateful and view-only coinflip replay consistent.
- Retain exact-word availability guards. After a jump, a recent `dailyIdx` does
  not prove that yesterday's word exists. Never hash a missing word as entropy.

### Coinflip auto-rebuy through a skipped interval

Auto-rebuy follows playable flip rounds, not the number of wall-clock dates
crossed. It does not need to iterate or update every player's position at pause.
Keep the existing lazy `autoRebuyCarry` representation.

- A carry already committed to an outstanding flip remains committed. Resolve
  that flip exactly once when its valid result arrives. A loss still loses that
  stake; a win applies the existing take-profit split. A stall is not an optional
  cancellation or protection against an already-committed loss.
- Preserve the resulting carry across empty dates. Do not simulate wins/losses,
  add recycling bonuses, award loss consolation, or add BAF credit merely for
  crossing those dates. Resume it on the next actual playable flip round.
- Distinguish a settlement-only historical day from a playable flip round. The
  one extra backfill can settle explicit stored deposits without automatically
  betting the running carry again. Follow the frozen auto-rebuy/take-profit
  settings for those proceeds and carry them forward to real play; apply a
  recycling bonus only once for an actual reinvestment. If an old cohort also
  contains a genuinely precommitted carry, preserve that commitment explicitly
  rather than inferring it from the mere existence of a day-result byte.
- Keep mode changes, take-profit changes, carry withdrawals, and indirect carry
  consumption frozen while they could change exposure to an outstanding or
  revealed-but-unconsumed result. Already banked claimables remain distinct.
- The write replay and preview replay must use identical round classification
  and gap skipping. A recovery word must not let a player choose which of its
  derived results their carry participates in.

This is a required change to the existing code, not something its zero-result
branch already guarantees. `_claimCoinflipsInternal` decrements its work budget
for every zero day but only advances `processed` on a resolved result. A long
empty range can therefore exhaust a call without advancing the persisted claim
cursor. `_viewClaimableCoin` also consumes its budget scanning zero days, and
ordinary non-rebuy claim windows use calendar subtraction. Use an explicit
skipped-range/round-successor mechanism so permanent skips advance the cursor
without losing accepted stakes or prematurely expiring claims. A pending day is
not a permanent skip just because its result is currently zero.

**Protocol seed exception to the two-cohort bound:** the Coinflip constructor
and `armCenturySeedWindow` prepopulate 20 future calendar-day stakes for both
VAULT and sDGNRS. Those are existing future commitments; an admission gate alone
cannot make all dates after the grace cohort empty. Preserve the remaining seed
program over played rounds, with explicit accounting that does not double-credit
or erase seed amounts mixed into ordinary stake storage. This is fixed protocol
work for two accounts, not a reason to backfill every outage date or scan all
players. Update the sDGNRS auto-rebuy arming condition to follow actual seed
completion rather than an advanced calendar day.

## Admission coverage and gas

Use one shared stale-day predicate in Game storage and a narrow read-only Game
surface for standalone contracts. Reuse an already-read day and slot-0 value
where possible. Slot 0 is not intrinsically cheap: the saving comes from its
being warm or already cached because the path also reads level/phase flags.

| Surface | Required work |
| --- | --- |
| Coinflip deposits and daily stake producers | Gate fresh obligations, including operator/gift paths; preserve claim-only calls and necessary recovery credits |
| WWXRP `enter` | Gate before burning/enrolling; include its linked incinerator entry in the review |
| Foil purchases | Gate the paid entry path before accepting a new resolve-day obligation |
| Protocol boon ETH hero entries | Inherit the Degenerette placement gate before funding and day enrollment |
| sDGNRS gambling burns | Preserve existing stronger word-availability/single-pool guards; verify consistency |
| AFKing, whale purchases, and other automatic producers | Preserve recovery's required work; prevent repeated historical-day deliveries |
| Ordinary actions that reward FLIP | Audit every root calling `creditFlip`, batch/pair credit, or `creditSdgnrsBacking`; paused roots may revert |
| Prior-day-word consumers | Retain/add word-presence checks for deity menus, salvage pricing, and other exact-key readers |

No blanket revert in `creditFlip` or another shared helper that the recovery
call graph needs. Identify every external route into those helpers and gate the
ordinary action roots instead. A bypass must be internal/authorized, never a
caller-controlled boolean. A paused operation rolls back its debit and rewards
atomically. There is no new holding-balance subsystem.

The hot-path target is a small entry check, no new per-ticket/per-player writes,
and no added per-recipient checks in bulk settlement. Standalone calls have a
cross-contract cost; measure it and cache readiness once per applicable batch.
Do not substitute Coinflip's result cursor for Game's index without proving
the boundary remains the same during multi-transaction day processing.

## Two terminal modes

### Normal terminal

Preserve real-VRF terminal settlement, phase-correct terminal level selection,
and its ordinary economics. A temporary pause does not select emergency payout.
No catastrophic claim can coexist with a normal terminal jackpot over the same
pool. Existing normal-terminal input-freeze issues must not be represented as
fixed merely because historical/prevrandao fallback is removed.

### Catastrophic terminal

Replace the historical-word/`prevrandao` fallback with a separate latched mode.
Activation must not require fresh VRF, ticket assignment, foil materialization,
or a successful walk through unresolved lootbox queues.

Use a fixed real-time failure rule and explicit callback/activation precedence.
Preserve valid results accepted before the relevant failure boundary; a caller
must not choose the deterministic alternative after seeing an accepted result.
Late callbacks cannot reopen a latched emergency or mutate its entitlements.
Retain the existing 14-day terminal fallback and 120-day phase-independent
deadman constants as starting parameters; specify which trigger applies in each
phase, including failed requests, before implementation. Retries must not reset
the escape indefinitely.

At activation:

1. Freeze the phase-correct terminal level and prevent subsequent bucket changes.
2. Reserve earned claimables, prepaid balances, and other surviving liabilities.
3. Determine the distributable pool once. Later donations do not reprice claims.
4. Inspect the fixed 256 trait buckets and record the nonempty-trait mask/count.
   No scan over all ticket occurrences or all players is needed.
5. Reserve the entire emergency allocation separately from existing claimables.
   No normal payout or final sweep can spend it.

Implementation defaults proposed for this plan, not additional user rulings:

- Split across nonempty materialized trait buckets so empty buckets do not strand
  pot shares. If all are empty, use a documented deterministic residual-funds
  route consistent with the existing terminal sinks, after protecting liabilities.
- Actual bucket occurrences qualify; normal jackpot virtual deity entries do not
  automatically become emergency tickets. Preserve existing early-game deity
  refund rules before calculating the remaining pool unless deliberately changed.
- The emergency trait allocation receives the remaining distributable pool;
  do not silently deduct the normal 2% affiliate jackpot from that allocation.
- Emergency allocations are protected from the normal 30-day forfeiture sweep.
  A different emergency claim expiry would be an explicit economic decision.

### Claim mechanism

Suggested surface:

```solidity
claimDeadVrf(address player, uint8 trait, uint256[] calldata positions)
```

For a bounded batch, verify each position is below the frozen bucket length,
resolve its owner through `lvlEntryOwner`, require that owner to be `player`,
and mark the position in a claim bitmap. Anyone may submit a claim, but credits
always belong to the stored owner. Use full-width positions unless a smaller
bound is proven; bucket occurrence counts are not registry-owner indices.

Bitmap keys include the trait and occurrence-word index. Each bit identifies
one occurrence, so repeated owners, repeated registry records, reordered batches,
and multiple wallets cannot claim an occurrence twice. Mark claims before any
external transfer; preferably credit the existing withdrawal ledger.

For exact deterministic allocation, let `P` be the pool, `N` the populated trait
count, `r` a trait's rank among populated IDs, and `n` its frozen length:

```text
traitBudget = floor(P / N) + (r < P % N ? 1 : 0)
occurrenceAmount(i) = floor(traitBudget / n) + (i < traitBudget % n ? 1 : 0)
```

This assigns rounding wei by immutable position, not claim order. Derive rank
from the frozen trait mask. Enforce explicit batch limits and reject duplicates
atomically. Moving an allocation to `claimablePool` reduces the emergency reserve
by exactly the same amount; do not reserve or credit it twice.

The frozen buckets and immutable owner records provide on-chain evidence. No
off-chain Merkle root, administrator allocation, or hot-path ownership index is
needed. Post-terminal writers must not append/rewrite eligible lanes or advance
claim denominators.

### Other unresolved financial obligations

Removing `_gameOverEntropy`'s fallback also removes the word currently used for
pending coinflips and sDGNRS gambling-redemption resolution. Audit these callers
explicitly; they cannot continue requiring a nonexistent terminal word.

Do not generalize the user's unassigned-ticket forfeiture to all outstanding
wagers. In particular, preserve sDGNRS's already-segregated ETH. A proposed simple
emergency rule is a 100% snapshotted-base ETH redemption paid directly, without a
random multiplier or new lootbox; specify terminal token-escrow treatment too.
Inventory other unresolved ETH-backed commitments before calculating the pot.
If they need a policy beyond the agreed ticket forfeiture, present that specific
choice before implementing a confiscation or an unfunded refund promise.

## Implementation sequence

1. **Consumer and clock inventory.** Enumerate daily-word readers, day-based
   gameplay timers, every daily-stake producer, and the advance recovery call
   graph. Record admission, skipped-day, claim, and catastrophic treatment for
   each. Fix the activation/callback precedence and residual liability policies.
2. **Freshness gate.** Implement the one-day predicate and entry gates, including
   indirect producers. Preserve existing stronger RNG locks. Prove ordinary
   rollover and pending requests behave as before and recovery cannot self-block.
3. **Skipped-day recovery.** Replace the long daily backfill with the original
   commitment plus one extra accepted cohort, range skipping, consistent claim
   replay, and gameplay-clock forgiveness. Preserve lootbox request bindings.
4. **Catastrophic activation and claims.** Add cold-path state and claim code;
   freeze actual trait buckets without assignment; protect all reserves; separate
   normal terminal settlement and remove synthetic entropy from emergency release.
5. **Verification and documentation.** Update relevant tests, interfaces, manifests,
   storage-layout goldens, known issues, and player-facing failure semantics.

Primary files: `DegenerusGame.sol`, `DegenerusGameStorage.sol`, Advance and
GameOver modules, `Coinflip.sol`, `WWXRP.sol`, `sDGNRS.sol`, FoilPack and Boon
modules, AFKing/automatic-action modules, and the associated interfaces/lens.
The audit's Advance and Mint bytecode margins are tight: place terminal claim
logic in a suitable cold module and verify actual deployed bytecode sizes.

## Required evidence

- Boundary tests: lag 0 and 1 allowed; lag 2 blocked; existing stricter gates
  retained; claim-only operations and required recovery calls stay reachable.
- Test every direct/indirect daily producer, including rewards from ordinary
  purchases, lootbox settlement, protocol transfers, gifts, and batches.
- A multi-day gap with grace-day entries settles both accepted cohorts exactly
  once and generates no obligations or rewards for the empty interval.
- Timely delivery with late processing, late delivery, midnight crossings,
  repeated cranks, coordinator swaps, retries, duplicate/stale callbacks, and
  delivered-word preservation all have explicit expected outcomes.
- Paused days neither damage nor improve streaks, consume gameplay duration,
  generate subscription catch-up charges, or compound auto-rebuy carry. Previously
  executed transactions stay accounted for.
- Auto-rebuy wins/losses and take-profit splits around the pause, extra explicit
  deposits, settlement-only backfill, indirect carry spending, preview/execution
  parity, and a skipped range longer than the ordinary replay budget. Verify
  persisted cursor progress and no duplicate bonus/BAF/consolation issuance.
- Initial and century VAULT/sDGNRS seed windows straddling an outage: every owed
  seed installment remains accounted for once, with no phantom rolls and no
  early sDGNRS auto-rebuy arming.
- Normal terminal still pays its VRF jackpot. Catastrophic activation succeeds
  with no word and undrainable/unassigned queues, and excludes those tickets.
- Frozen bucket ownership/counts; empty traits; no traits; zero pot; multiple
  occurrences per owner; mixed owners; out-of-range/duplicate positions; partial
  and reordered claims; rounding; late donations; and late VRF callbacks.
- Conservation: emergency amounts paid plus remaining reserve equal the original
  allocation; ordinary claimables remain backed; no double allocation; final
  sweep cannot spend unpaid emergency shares.
- Compare baseline and changed normal-path gas. Measure cold recovery and maximum
  claim batches below the existing 15M review target without raising caps. Long
  outages must not add work proportional to missing dates. Check runtime sizes,
  storage layout, RNG manifests, and relevant invariant/interface gates.

Existing suites to adapt include `StallDaysNeverHappened`, `StallResilience`,
`DailyRngStallRecovery`, `QuestStreakStallForgiveness`, `VRFStallEdgeCases`, daily
Coinflip/WWXRP/Foil suites, terminal fixtures, and cold advance gas suites. Current
tests expecting every historical day to receive a derived word must be replaced
with the agreed skipped-day behavior, not merely deleted.

The existing retry/promotion/governance request-replacement assumptions require
explicit RNG review alongside this work. A freshness gate or deterministic
terminal payout does not by itself remove selective-withholding or reroll risks.

## Current work status

Only this plan has been added. No production contracts, existing tests, storage
layouts, or accepted-issues documents have been modified by this planning task.
Implementation and gas measurements remain to be done.
