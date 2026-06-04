---
phase: 355-gas-measure-tune-per-buy-per-open-per-settle-marginals-accum
type: CONTEXT
source: USER override (2026-06-01, mid-355-execute — three rapid directives)
status: locked
created: 2026-06-01
---

# Phase 355 CONTEXT — locked USER decisions (the mid-355 re-scope)

Phase 355 was planned as a PURE GAS measure+tune (likely Outcome-A no-diff per the v55 350
precedent). Mid-execution the USER issued three directives that RE-SCOPE it into a small IMPL
change + a two-batch split + the tune, all riding the existing `autonomous:false` 355-03
contract-commit boundary. These decisions are LOCKED — the planner MUST honor them, not
re-litigate. Full record: memory `[[v56-deferred-quest-payout-two-batch-redesign]]`.

Baselines: v55 = `453f8073`; v56 Phase-354 IMPL applied = `e18af451`; the committed 355-01
Task-1 harness = `3b9df3fb` (measures the CURRENT creditFlip-push tree → the "before" baseline).

## Locked decision 1 — size the STAGE batch against the QUEST-loaded settle day
The binding worst-case for STAGE batch sizing is the settle day (`processDay % SETTLE_PERIOD == 0`,
`SETTLE_PERIOD = 10`, `GameAfkingModule.sol:172`), NOT a plain buy day, because per sub it adds a
cross-contract `settleAfkingQuest`. The harness MUST accrue `questProgress`/`buyerOwedBurnie` over
prior non-settle days, then measure the FULLY-LOADED settle-day per-sub marginal. (The halted
355-01 agent had independently reached this.)

## Locked decision 2 — accrue the BURNIE PER DAY into a claimable balance; status on settle day; claim anytime
(FURTHER refined by the USER 2026-06-01 — SUPERSEDES the earlier "count-then-convert + gated claim"
framing. Rationale: the per-day reward is LINEAR [no settle-time multiplier], so there is no
conversion event to game and nothing to gate — accruing the actual BURNIE daily and letting the sub
pull it whenever is non-exploitable by construction: "they already earned that.")

**Per delivered (paid) day — the warm in-slot accrue (no cross-contract call, "basically free", same
slot already written):**
- `pendingBurnie += QUEST_SLOT0_REWARD + thisBuy'sTicketBuyerBonus` — the actual claimable BURNIE,
  accrued DAILY. This FOLDS IN / REPLACES the separate `buyerOwedBurnie` accumulator (quest reward
  AND ticket-buy bonus go into the one balance — "update the burnie from quests and any other source
  like ticket buys every day since it's in the sub struct").
- `++questProgress` — KEPT, but now ONLY as the delivered-day COUNT for the streak (NOT a BURNIE
  proxy).
- `affiliateBase += …` — unchanged (pulled separately via `drainAffiliateBase`).

**Settle day (~10-day cadence, `currentDay % SETTLE_PERIOD == 0`) — the ONLY per-sub cross-contract
work:** `quests.settleAfkingQuest(player, questProgress, currentDay)` advances the ±10 streak ("just
do quest status on settle day"), then zeroes `questProgress`. NO BURNIE work here — it is already in
`pendingBurnie`. This `settleAfkingQuest` cost is the heavier per-sub case → the binding marginal for
`SUB_STAGE_BATCH_SETTLE`. (`_settleQuest`'s old `creditFlip` body is GONE.)

**Claim (player PULL, anytime) — the ONLY `creditFlip`, off the auto-run:**
`creditFlip(player, pendingBurnie); pendingBurnie = 0`. A permissionless entrypoint (always credits
the sub, never the caller; idempotent). It does NOT touch quest status/streak and does NOT settle
in-flight progress — it only pays the accrued balance.

**Unsub / claim whenever — unrestricted, no gating:** `pendingBurnie` is the sub's already-earned
per-delivered-day balance, so realizing it early gains nothing ("if they unsub or claim whenever it's
fine they already earned that"). The unsub `_settleQuest` call (`:314`) and the ungated early-settle
in `claimQuest` (`:1182-1192`) are REMOVED — the streak gap-resets naturally; `pendingBurnie` stays
claimable.

**Keeper `mintBurnie` bounty stays an IMMEDIATE push** (`:1090`) — one `creditFlip`/call, the keeper's
own crank incentive, not a per-item batch cost. **Scope = auto-run only;** the manual-buy path is
UNCHANGED. Off the solvency path (BURNIE-emission-timing only) → SOLVENCY-01 byte-unchanged,
RNG-freeze intact. (= the new GAS-05 requirement; SUPERSEDES the AGG-02 inline settle-day
`creditFlip`.)

## Locked decision 3 — TWO STAGE batch sizes (normal vs quest/settle day)
Split `SUB_STAGE_BATCH` (=50, `DegenerusGameAdvanceModule.sol:149`, used `:761`) into:
- `SUB_STAGE_BATCH_NORMAL` — LARGE (the ~9/10 cheap days: buy + in-slot accrue, zero
  cross-contract calls).
- `SUB_STAGE_BATCH_SETTLE` — SMALLER (the settle day adds per-sub `settleAfkingQuest`).
The STAGE chunker branches on `currentDay % SETTLE_PERIOD == 0` to pick which. Each sized from its
day's MEASURED per-sub marginal so the worst-case chunk TARGETS <10M and is PROVABLY ≤16.7M at the
`SUBSCRIBER_CAP` (the dual bound, `[[v56-batch-sizing-10m-target-16p7m-ceiling]]`). `OPEN_BATCH`
stays SINGLE — box opens are uniform (no quest-day variant).

## Sequencing guidance (for the planner — not a hard plan structure)
The contract change lands as ONE batched USER-APPROVED diff at 355-03: the per-day `pendingBurnie`
accrue (folding in `buyerOwedBurnie`) + the `_settleQuest` body reduced to streak-only on the settle
day + the payout claim entrypoint + the removal of the unsub/ungated early-settle + the two-batch
chunker branch + the two computed constants. The settle-day per-sub marginal is now the
`settleAfkingQuest` streak cost (no `creditFlip`, no conversion), so the harness measures it directly
on the IMPL-applied tree to size `SUB_STAGE_BATCH_SETTLE`; the cheap-day marginal (warm accrue only)
sizes `SUB_STAGE_BATCH_NORMAL`. Files in play: `contracts/modules/GameAfkingModule.sol` (per-day
accrue + streak-only `_settleQuest` + claim + `pendingBurnie` field — coordinate with
`contracts/storage/DegenerusGameStorage.sol` Sub-slot packing, replacing `buyerOwedBurnie`),
`contracts/modules/DegenerusGameAdvanceModule.sol` (the two-batch chunker branch + constants),
`test/gas/V56AfkingGasMarginal.t.sol` (extend the before-baseline harness `3b9df3fb`).

## Hard constraints (unchanged from the phase floor)
- Security-over-gas floor: gas-scavenger surfaces, gas-skeptic validates; any simplification must
  stay UNMANIPULABLE — not-real / invariant-trading wins REJECTED with reasoning.
- `pendingBurnie` must PACK INTO THE ALREADY-WARM accrue slot (whole-BURNIE width + the 100M-style
  clamp, replacing `buyerOwedBurnie`) so the per-day accrue stays a SINGLE warm SSTORE — no new cold
  per-buy SSTORE (GAS-02). If it would spill to a new slot, the per-day accrue is no longer "free" —
  the IMPL must confirm it fits (preserving `QUEST_SLOT0_REWARD` granularity).
- The contract diff is HELD at the `autonomous:false` 355-03 boundary for explicit USER hand-review
  (never auto-committed). Doc/test plans run hands-off.
- `pendingBurnie` field width: hold the accrued claimable (per-delivered-day `QUEST_SLOT0_REWARD` +
  ticket buyer-bonus, accumulated across many days until claim) without saturating over a realistic
  horizon — the planner/SPEC picks the width + Sub-slot packing.

---

# SUPERSEDING DESIGN — compute-on-read afking streak (2026-06-01, post-adversarial-review)

The streak half of "Locked decision 2/3" above is SUPERSEDED. After a 3-lens adversarial review
(zero-day-hunter + economic-analyst + contract-auditor) the BLANKET-FORWARD-ANCHOR custom updater was
found CRITICAL-unsafe (permanent free streak → ~+18 ETH/window box-EV; the forward anchor defeats the
only decay path), and the heavy `_questSyncState`-skipping updater was rejected (double-credit +
QST-04 perturbation). The USER then converged on a COMPUTE-ON-READ design that is exploit-closed by
construction. The `pendingBurnie` per-day-accrual + `claimAfkingBurnie` pull half (above) is UNCHANGED
and was found sound — KEEP it. `claimAfkingBurnie` now has its Game dispatch stub (was unreachable —
contract-auditor F-1, FIXED). `SUB_STAGE_BATCH_NORMAL` reverted 100→50 (the 100 placeholder blew the
16.7M ceiling — ~25M at ~262k/sub; the per-buy `playerQuestStates` STATICCALL dominates the normal day).

## The afking streak is COMPUTED ON READ, never written during afking
- Store per-sub (Sub-slot variant, to remove the per-buy STATICCALL — see tradeoff below):
  `afkingStartDay` + `streakAtAfkingStart` (the base snapshot). `afkCoveredThroughDay` (last funded
  delivery, monotone) already exists in the Sub slot.
- **Effective streak (read, Game-side):**
  `(afkCoveredThroughDay >= currentDay - 1) ? streakAtAfkingStart + (afkCoveredThroughDay - afkingStartDay) : 0`
  - It only ADVANCES as `afkCoveredThroughDay` advances → requires a FUNDED MINT each day (debit-gated,
    unfarmable). Closes V1/V3.
  - **DECAY-ON-READ:** if the last funded mint is more than 1 day ago (`afkCoveredThroughDay < currentDay - 1`),
    the read returns 0 — miss ONE day → streak gone, enforced at read time (no frozen-high residual).
- **Gap-reset-on-resume** (cheap warm in-slot, in the accrue path): on a delivered day, if
  `afkCoveredThroughDay < processDay - 1` (resuming after a gap), set `afkingStartDay = processDay`,
  `streakAtAfkingStart = 0` — the new run counts from zero, not the stale span.

## Subscribe does a min buy on a non-complete quest day (so afkingStartDay is always grounded)
`subscribe` (already `payable`) checks whether today's slot-0 quest is already complete. If NOT, it
does a MINIMUM buy of the sub's OWN product — lootbox if lootbox-mode, ticket if ticket-mode (per
`useTickets`) — funded from `msg.value` → claimable winnings → the funding source, and REVERTS if none
can cover it (all empty). That min buy completes today's quest, so `afkingStartDay = today` is a real
completion day and it counts as the day-0 afking delivery (`afkCoveredThroughDay = today`, day-0 reward
accrued to `pendingBurnie`, `streakAtAfkingStart = streak`). If today's quest is already complete, skip
the buy. The subscribe-day completion is the LAST streak-affecting event before `afkingActive` flips on.

## During afking: slot-0 completions accrue to pendingBurnie (no immediate payout), streak-neutral
While `afkingActive`, a SLOT-0 quest completion (the subscribe min-buy + any afking-context completion)
records its completion-day + per-slot progress/version sync, but: (a) pays NO immediate slot-0 BURNIE
reward — the reward IS the per-delivered-day `pendingBurnie` accrual (the pull), so paying it here too
would DOUBLE-credit (the O1 double-credit class, avoided by construction); and (b) does NOT advance or
gap-reset `state.streak` (the compute-on-read owns the streak). The afking special-casing is keyed on
the SLOT being slot-0 — it must NOT gate the quest handler broadly.

SLOT-1 (the player's own random/manual quest) stays FULLY ACCESSIBLE EVERY DAY during afking: its
per-slot daily progress/version sync (`_questSyncProgress`) still runs (fresh each day), the player
completes it manually, and `QUEST_RANDOM_REWARD` pays NORMALLY/immediately (only slot-0's reward is the
deferred `pendingBurnie`). The subscribe min-buy completes slot-0 only; the two slots are independent so
it never locks out slot-1. Safety: a slot-1 completion DURING afking is STREAK-NEUTRAL (it must not
advance the afking compute-on-read streak — a cheap slot-1 completion bumping the debit-gated streak
would re-open the C3-a non-funded streak dodge); for a NON-afking player slot-1 advances the streak
normally. The `afkingActive` flag separates the two. (Flag: 1 bit in `PlayerQuestState`; slot 0 has 17
free bytes; set/cleared onlyGame at subscribe/unsub.)

## Finalize on EVERY sub-ending path, BEFORE the slot is deleted
Four ending paths (GameAfkingModule): explicit cancel `subscribe(_,0)` `:305`; **cancel-reclaim `:619`
(DELETES `_subOf`)**; pass-eviction (AFSUB-03 crossing); funding-kill (unfunded NORMAL sub). Each must
do the QUEST-STATUS CHANGE (the finalize) = write the **decay-applied** final streak
`(afkCovered >= currentDay-1) ? base + (afkCovered - afkingStartDay) : 0` to `DegenerusQuests.state.streak`
+ clear `afkingActive` + clear `afkingStartDay`, handing streak control back to the manual system
(also set `lastActiveDay = lastValidMintDay` so the manual gap-reset is honest from there). A
cancel-reclaim of a still-current sub finalizes to its real earned value.

**Funding-kill must NOT zero unless a full day was DEFINITELY missed with NO valid mint (afking OR
manual)** (USER 2026-06-01). Two protections: (1) the `currentDay - 1` grace means a sub funding-killed
on the FIRST unfunded day (delivered yesterday) is NOT zeroed — only a full PRIOR missed day zeros; and
(2) the decay must key on `lastValidMintDay` = the last day a valid mint occurred AFKING OR MANUAL (the
slot-0 quest-completion day, e.g. `lastCompletedDay`), NOT just `afkCoveredThroughDay` — else a sub who
let afking funding lapse but kept minting MANUALLY would be wrongly zeroed. The per-buy HOT path keeps
the cheap `afkCovered`-only Game-side compute (no STATICCALL); the funding-kill finalize (a RARE
eviction path) reads the quest-completion state to get the true `lastValidMintDay` and zeros only if
`lastValidMintDay <= currentDay - 2`. This `DegenerusQuests` write is the
cross-contract cost that makes an in-stage evict the HEAVY branch (vs the now call-free local buy) → it
drives the weighted batch budget above. The cancel-reclaim case MUST finalize BEFORE the `_subOf` delete
(load-bearing ordering, since the Sub-slot variant holds the afking streak state there). Currently NO
unsub path writes quest status (the prior `_settleQuest`-on-cancel was removed) — all four need the
finalize added.

## Consequence: NO settle day → the two-batch split is OBVIATED
Compute-on-read removes BOTH things the two-batch split existed to handle: (1) the per-settle
cross-contract streak write is GONE (streak computed on read; `pendingBurnie` accrues per-day) — there
is NO settle day, and `SETTLE_PERIOD` is unused by the streak/reward math (gap + decay key off
`currentDay − 1`, daily); (2) the per-buy `playerQuestStates` STATICCALL is GONE (streak computed
locally from the Sub slot). So every day is UNIFORM and cheaper → revert `SUB_STAGE_BATCH_NORMAL`/
`_SETTLE` + the AdvanceModule `SETTLE_PERIOD` back to a SINGLE `SUB_STAGE_BATCH`, sized larger than 50
from measurement (the STATICCALL removal is the headroom). The two-batch split (USER directive 3) is
SUPERSEDED by this — the gas win it chased is delivered uniformly instead.

## Unsub-finalize gas: evict may be HEAVIER than a (now-cheap) buy → USE the weighted budget
CORRECTION (the prior "evict is cheaper" note was wrong — it relied on the stale ~262k, which was the
v55 `purchaseWith` heavyweight, NOT the v56 buy). The v56 minimal-write buy is much cheaper (GAS-01
target lootbox ~130–140k), and compute-on-read REMOVES the per-buy `playerQuestStates` STATICCALL — so
a buy (esp. lootbox: a warm Sub-slot stamp + ETH debit + in-slot accrue) is all LOCAL, no cross-contract
calls. The in-stage evict (cancel-reclaim `:619`, pass-evict, funding-kill) instead does a CROSS-CONTRACT
`DegenerusQuests` finalize write (cold-ish account access + streak SSTORE + call frame) that the buy no
longer has — so an evict iteration can EQUAL or EXCEED a buy. `buy XOR evict` per sub, but evict is the
heavier branch now. So ADOPT the USER's weighted-budget: the STAGE consumes a gas-WEIGHT per iteration
(cheap buy = 1, evict-finalize = W players-worth) and ends the chunk on accumulated weight, not raw
count — bounding the worst-case chunk (even all-evicts) under 16.7M. W + the base batch come from
MEASUREMENT (BLOCKED on the fixture). (The explicit `subscribe(_,0)` cancel `:305` runs on the user's
own tx, off the advance chain — not in the budget.)

## State-location: RESOLVED → Sub struct (USER priority: no daily cross-call)
The afking fields `afkingStartDay` + `streakAtAfkingStart` live in the **Sub struct** (Game-side),
NOT `PlayerQuestState`. RATIONALE (USER 2026-06-01): the everyday afking auto-buy must do ZERO
`DegenerusQuests` cross-calls — the per-buy activity-score streak is computed LOCALLY from the Sub slot
(`afkCovered` + the afking fields). queststatus was rejected because it would keep a DAILY STATICCALL
(the per-buy read of the afking fields). Cross-`DegenerusQuests` calls happen ONLY at: subscribe (read
the starting streak to snapshot `streakAtAfkingStart` + the min-buy's slot-0 completion), unsub/finalize
(write the final streak, on the 4 ending paths), and an occasional player-initiated manual quest action
— never the daily auto-buy, never a settle (settle is gone). COST accepted: the afking fields need a
2ND Sub slot (~15 free bits in slot-0 < the ~48 needed) → +1 cold SLOAD/buy, far cheaper than the daily
cross-contract STATICCALL it replaces; and the finalize MUST run BEFORE `delete _subOf` on cancel-reclaim
(`:619`). The `afkingActive` flag stays in `PlayerQuestState` slot-0 (it gates the manual-path slot-0
handling, which IS in DegenerusQuests).

## RESOLVED DECISIONS (2026-06-01) — ready to author, ALL forks closed
- LOCATION: Sub struct (above).
- SCOPE: all 8 items in ONE contract diff (USER "all in one diff").
- RECONCILIATION: REMOVE the settle-day machinery so finalize is the SOLE streak authority — delete
  `_settleQuest` + the stage `% SETTLE_PERIOD` settle hook + `claimQuest` (+ its interface decl + any
  Game stub) + the first-sub head-start's `settleAfkingQuest` call + the now-dead `settleAfkingQuest`
  in DegenerusQuests. (Necessary: two streak authorities would double-write.)
- HEAD-START: the first-sub +0..9 grant FOLDS INTO `streakAtAfkingStart` at subscribe (added to the
  snapshot base), surviving because the min-buy makes subscribe-day the day-0 delivery (no pre-first-
  delivery gap to wipe it).
- SUBSCRIBE MIN-BUY: a NORMAL buy of the sub's product — lootbox = STAMP-for-later-open (sets
  `lastAutoBoughtDay=today`, leaves `lastOpenedDay<that`; the open pass materializes from
  `rngWordByDay[today]`; NEVER an inline resolve — pre-RNG → 0-entropy risk), ticket = normal queue;
  funded msg.value → claimable → funding source, REVERT if all empty; it is the day-0 delivery (sets the
  markers so the STAGE doesn't re-deliver day-0) + grounds `afkingStartDay`/base + sets `afkingActive`.
- FUNDING-KILL: any-valid-mint decay (per the section above) — read quest-completion to get the true
  `lastValidMintDay`, zero only if `<= currentDay-2`.
- PACKING / FIELD WIDTHS (USER 2026-06-01, CORRECTED): `afkingStartDay` = **uint24** (MUST match the
  day-index range — a uint16 day truncates ~179y AND mixing widths with the uint24 `afkCoveredThroughDay`
  in `afkCovered - afkingStartDay` is unsafe). `streakAtAfkingStart` = **uint8**, capped at 100 on write
  (the score caps at `min(streak,100)`; no benefit above). Day markers STAY uint24 (same safety reason —
  do NOT narrow them; scrap the earlier uint16 idea). DROP `questProgress` (uint8) — unused
  post-reconciliation (streak is `afkCovered`-derived, reward is the per-day `pendingBurnie`).
  RESOLVED → ONE SLOT (USER 2026-06-01 "make it one slot"). Current Sub = 31/32 bytes used (a Solidity
  `bool` is 1 BYTE, so `hasEverSubscribed` already burns a full byte — the earlier "~15 free" was wrong).
  The exact one-slot layout (32 bytes, 0 free):
    • DROP `questProgress` (uint8) − 1 byte (unused post-reconciliation).
    • `amount` uint32 → uint24 − 1 byte (milli-ETH; 16,777-ETH/buy cap — safe).
    • NEW `afkingStartDay` uint24 + 3 bytes (days stay uint24 — safety).
    • NEW `streakAtAfkingStart` 7-bit (capped 100 on write) PACKED into `hasEverSubscribed`'s byte
      (1-bit latch at bit 7 + 7-bit streak at bits 0–6 = one uint8, masked) + 0 net bytes.
    31 − 1 − 1 + 3 + 0 = 32 → exactly one slot. This AVOIDS bit-packing `affiliateBase`/`pendingBurnie`
    (they stay clean uint32 → the per-buy accrue has NO masking). The ONLY masked field is the
    streak/latch byte, written rarely (subscribe + gap-reset), read per-buy as a couple of cheap ops.
    Day markers stay uint24. AUTHORING SESSION confirms offsets via `forge inspect DegenerusGame storageLayout`.

## Re-validation gate
This is a FRESH architecture with its own surface (the decay-on-read + gap-reset day-math, the 4
finalize hooks + slot-deletion ordering, the manual-neutral rule, the subscribe inline-mint). Author
carefully, then RE-RUN the 3 lenses on THIS design before locking / the 355-03 contract gate. The
fixture is still down → gas measurement (the two-batch sizing) is blocked until the DeployProtocol
vanity-address realignment is repaired (separate test-only fix; whole suite is red at setUp).

