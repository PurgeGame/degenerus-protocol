---
phase: 355-gas-measure-tune-per-buy-per-open-per-settle-marginals-accum
plan: 03
status: complete
contract_commit: 3d969621
baseline_sha: 453f8073
---

# 355-03 SUMMARY — residual GAS tune + GAS-05 deferred payout + liveness adds (contract gate)

## Self-Check: PASSED — all contract commits USER-approved + PUSHED to origin/main

## What landed (net contract diff, NOT Outcome-A)

The GAS phase landed a net `contracts/*.sol` diff (heavily USER-re-scoped mid-execute), then this session
added two USER-directed liveness/safety changes on the same boundary. All committed + pushed
(`414c8260`→`3d969621`).

GAS tune + re-scope (committed `39b2b4e1` / `115c7e37` / `e2590c1c` / `7bd595ba` / `329e0c7b`):
- GAS-05 deferred-quest payout: per-delivered-day quest reward + ticket buyer-bonus accrue into a claimable
  in-slot `pendingBurnie`; quest streak settles via `settleAfkingQuest` on the settle day; a permissionless
  claim pays `pendingBurnie` in one `creditFlip`. No per-buy `creditFlip`, no new cold SSTORE. See
  [[v56-deferred-quest-payout-two-batch-redesign]].
- GAS-03: STAGE chunking re-tuned — weighted gas-budget (`SUB_STAGE_WEIGHT_BUDGET=1000`; ticket weight 8 /
  lootbox 1 / evict 2) replacing the flat count; `SUBSCRIBER_CAP` 1000; `OPEN_BATCH` 200→130 (9.29M chunk).
- Single-roll afking open + per-roll lootbox reroll + afking-open day-cache (`329e0c7b`); PlayerQuestState
  5→1 pack + GAME deploy under the 16.7M tx cap (`e2590c1c`).

Liveness/safety adds (this session, USER-approved):
- `openBoxes(uint256 maxCount)` unified box-open valve (afking-first + human, uncapped, unrewarded) — commit
  `86a2d6c8`. Drops the standalone human `autoOpen`; adds `drainAfkingBoxes`. Individual `openLootBox` +
  rewarded `mintBurnie` unchanged.
- Gap-backfill / daily-jackpot decouple (`STAGE_GAP_BACKFILLED` early-return after `rngGate`) — commit
  `3d969621`. Fixes the Codex-found protocol-forced 16.7M composition breach (121+ day stall resume).

## Verification

- All forge gas suites green 26/26 (gas-suite retarget `08e59a4a`); every measured worst-case chunk < 16.7M.
- SOLVENCY-01 debit byte-unchanged; RNG-freeze intact.
- The 3-model 16.7M worst-case proof (`audit/PROOF-V56-16P7M-GAS-CEILING.md`, local/gitignored) reconciled
  Claude + Codex + Gemini: all protocol-forced loops capped.

## Deferred to Phase 356 (TST) — USER: "leave tests for the test phase"

- Per-tx <16.7M measurement of the decoupled gap-resume (each `advanceGame` call; existing test bounds only
  the 25M total resume).
- A `gap → defer → next-advance-pays` regression test for the decouple.
- The stale-Sub-offset fuzz-suite migration (`OFF_LASTBOUGHT=21→11`/uint24, ~10 files) — the pre-existing reds.
- Empirical proof of the new SEC reqs (LIVE-01 valve, GAS-06 decouple) + the 16.7M-proof residual assumptions.

## Requirements

GAS-01/02/03/04/05 met; LIVE-01 (valve) + GAS-06 (decouple) added for 356 verification.
