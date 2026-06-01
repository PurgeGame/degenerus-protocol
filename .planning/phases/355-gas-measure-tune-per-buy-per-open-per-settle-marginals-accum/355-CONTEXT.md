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

## Locked decision 2 — defer the quest+buyer-bonus PAYOUT to a player claim (keep the streak)
In `_settleQuest` (`GameAfkingModule.sol:1141`):
- **KEEP** `quests.settleAfkingQuest(player, progress, currentDay)` — the quest-core streak STILL
  advances on the ~10-day cadence ("I still want to do the quest stuff").
- **KEEP** draining `questProgress` each settle (so the `uint8` 255-cap stays a non-issue).
- **REPLACE** the per-sub `coinflip.creditFlip(player, owed)` (`:1164`) with `pendingBurnie += owed`
  — a warm in-slot SSTORE into a NEW accumulator field on the `Sub`. NO coinflip CALL in the
  auto-run.
- **NEW permissionless claim entrypoint** (extends the `claimQuest` family): does a final settle of
  any un-drained progress, then `creditFlip(player, pendingBurnie); pendingBurnie = 0`. The flip
  credit happens WHEN THE SUB CLAIMS. Always credits the sub, never the caller; idempotent.
- **Keeper `mintBurnie` bounty stays an IMMEDIATE push** (`:1090`) — "quest + buyer-bonus only".
  It is one `creditFlip` per call (the keeper's own crank incentive), not a per-item batch cost.
- **Scope = auto-run only.** The manual-buy path is UNCHANGED.
- Off the solvency path (BURNIE-emission-timing only) → SOLVENCY-01 byte-unchanged, RNG-freeze
  intact. (= the new GAS-05 requirement; SUPERSEDES the AGG-02 inline settle-day `creditFlip`.)

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
The harness can measure the `creditFlip` component cost on the current tree and DERIVE the
post-swap settle marginal (= current settle marginal − the per-sub creditFlip cost) WITHOUT
applying the IMPL first. So both batch sizes are derivable pre-IMPL, and the contract change can
land as ONE batched USER-APPROVED diff at 355-03: the `creditFlip`→`pendingBurnie` swap + the claim
entrypoint + the two-batch chunker branch + the two computed constants. Files in play:
`contracts/modules/GameAfkingModule.sol` (swap + claim + `pendingBurnie` field — coordinate with
`contracts/storage/DegenerusGameStorage.sol` Sub-slot packing), `contracts/modules/DegenerusGameAdvanceModule.sol`
(the two-batch chunker branch + constants), `test/gas/V56AfkingGasMarginal.t.sol` (extend the
before-baseline harness).

## Hard constraints (unchanged from the phase floor)
- Security-over-gas floor: gas-scavenger surfaces, gas-skeptic validates; any simplification must
  stay UNMANIPULABLE — not-real / invariant-trading wins REJECTED with reasoning.
- The `pendingBurnie` field must add NO new cold per-buy SSTORE (written only on the settle day in
  the already-warm Sub slot; drained at claim) — GAS-02.
- The contract diff is HELD at the `autonomous:false` 355-03 boundary for explicit USER hand-review
  (never auto-committed). Doc/test plans run hands-off.
- `pendingBurnie` field width: size so it does not saturate over a realistic claim horizon
  (`questProgress` ≤ ~10/epoch × `QUEST_SLOT0_REWARD` + `buyerOwedBurnie` whole-BURNIE, accumulated
  across many epochs until claim) — the planner/SPEC picks the width + Sub-slot packing.
