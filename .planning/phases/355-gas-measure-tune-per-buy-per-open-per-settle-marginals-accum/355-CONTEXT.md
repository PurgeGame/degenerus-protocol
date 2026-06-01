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
