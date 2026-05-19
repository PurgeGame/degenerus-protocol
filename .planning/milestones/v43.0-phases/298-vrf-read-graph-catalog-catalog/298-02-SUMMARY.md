---
phase: 298-vrf-read-graph-catalog-catalog
plan: 02
subsystem: vrf-read-graph-catalog
tags: [audit, catalog, rng, vrf, jackpot-module, consumer-02]
requires: [298-CONTEXT.md, 298-02-PLAN.md]
provides: [298-02-CATALOG-section.md]
affects: []
tech_stack: []
key_files:
  created:
    - .planning/phases/298-vrf-read-graph-catalog-catalog/298-02-CATALOG-section.md
    - .planning/phases/298-vrf-read-graph-catalog-catalog/298-02-SUMMARY.md
  modified: []
decisions:
  - "Trace excludes ETH-distribution paths (_processDailyEth, _resumeDailyEth, _addClaimableEth, _processAutoRebuy, whalePassClaims credits) per §2-only consumer scope — §2 is COIN+TICKETS, not ETH."
  - "Trace excludes _runEarlyBirdLootboxJackpot — verified only reached from payDailyJackpot (§1), NOT from payDailyJackpotCoinAndTickets (§2)."
  - "BurnieCoinflip cross-contract trace included per D-298-TRACE-DEPTH-01 (creditFlip/creditFlipBatch → _addDailyFlip → coinflipBalance/coinflipTopByDay reads); flagged NON-PARTICIPATING for §C/§D scope but enumerated in §B per F-41-02/03 discipline."
  - "VIOLATION classifications strict per D-298-EXEMPT-REACH-01 — runtime rngLockedFlag-revert gates do NOT confer EXEMPT status; only static call-graph descendancy from advanceGame()/rawFulfillRandomWords/retryLootboxRng does."
metrics:
  duration_minutes: 25
  completed_date: 2026-05-18
---

# Phase 298 Plan 02: VRF Read-Graph Catalog §2 — payDailyJackpotCoinAndTickets Summary

**One-liner:** Backward-traced VRF entropy from `JackpotModule.payDailyJackpotCoinAndTickets:596` across `contracts/` per D-298-TRACE-DEPTH-01; produced §A 30-function trace, §B 17-row SLOAD table, §C 8-slot writer enumeration, §D 22-row verdict matrix with **8 VIOLATIONs**, §E 8 remediation-tactic rows.

## What Was Done

Authored `.planning/phases/298-vrf-read-graph-catalog-catalog/298-02-CATALOG-section.md` — the per-consumer §2 catalog entry for Wave-2 aggregation into `.planning/RNGLOCK-CATALOG.md`. The artifact follows Phase 287 JPSURF format precedent (scaled per `D-298-CATALOG-LAYOUT-01`) and inherits trace-discipline from `feedback_rng_backward_trace.md` + `feedback_rng_window_storage_read_freshness.md` + `feedback_verify_call_graph_against_source.md` + `feedback_rng_commitment_window.md`.

## Trace Metrics

| Metric | Value |
|--------|-------|
| Traced function-set size (§A) | **30** functions across JackpotModule, Storage, EntropyLib, JackpotBucketLib, PriceLookupLib, GameTimeLib, BurnieCoinflip, DegenerusGame |
| Total SLOADs enumerated (§B) | **17** rows (including 4-row consolidated `_livenessTriggered` slots) |
| Participating slot count (Participating? = YES) | **10** (dailyTicketBudgetsPacked, level, jackpotCounter, dailyIdx, dailyHeroWagers, levelPrizePool, ticketQueue far-future key, deityBySymbol, traitBurnTicket, ticketWriteSlot) |
| Non-participating SLOADs flagged for F-41-02/03 discipline | **7** (dailyJackpotCoinTicketsPending guard; ticketsOwedPacked RMW; rngLockedFlag bypassed-read; _livenessTriggered's 4 slots; coinflipBalance + coinflipTopByDay cross-contract) |
| VIOLATION count (§D) | **8** (slot #6 × 1 + slot #8 × 6 non-advanceGame writer callsites + slot #9 × 1) |
| EXEMPT-ADVANCEGAME / EXEMPT-VRFCALLBACK / EXEMPT-RETRYLOOTBOXRNG count | **14** callsite rows (mix of ADVANCEGAME + VRFCALLBACK; no RETRYLOOTBOXRNG on this consumer's resolution tree) |

## Key Findings

1. **`dailyHeroWagers[day][q]` (slot #6) — `placeDegeneretteBet` writer is unguarded for the rngLockedFlag window.** The bet's only existing gate is `lootboxRngWordByIndex[index] != 0` (DegeneretteModule:452), which is FALSE during the commitment window. Recommended tactic (b) snapshot/anchor — freeze the read-day at lock time. (Phase 287 §3 row 1 + F-41-02/03 + Phase 285 fix history apply directly.)

2. **`ticketQueue[far-future key]` (slot #8) — 6 distinct non-advanceGame writer entries reach `_queueTickets.push(buyer)` through the far-future key.** These are `purchase`/`purchaseCoin`/`purchaseBurnieLootbox`/`purchaseWhaleBundle`/`purchaseDeityPass`/`claimWhalePass`/Degenerette `resolveBets` payout. The far-future key intentionally ignores `ticketWriteSlot` (Storage:731), so the double-buffer does NOT protect this slot — only the runtime `rngLockedFlag` revert at Storage:572/604/660 does. Per `D-298-EXEMPT-REACH-01` the runtime gate does NOT confer EXEMPT status; classification is per-callsite based on static descendancy. Recommended tactic (a) rngLockedFlag-gated revert for purchase entries (already enforced; promotion-to-invariant); (b) snapshot for `resolveBets` payout (which uses `rngBypass=true`).

3. **`deityBySymbol[fullSymId]` (slot #9) — `purchaseDeityPass` writer at WhaleModule:598.** Already gated `if (rngLockedFlag) revert RngLocked();` at WhaleModule:543. Per strict classification, still listed as VIOLATION because the gate is runtime, not static. Recommended tactic (a) confirm sufficient — this is a candidate for FIX sub-phase to accept the runtime-gate as adequate and reclassify, or to add an additional structural anchor.

4. **`level` (slot #3) — writer at AdvanceModule:1643 is reached from `rawFulfillRandomWords` (VRF callback).** Classified EXEMPT-VRFCALLBACK. The VRF callback writes `level` BEFORE the §2 consumer runs (within the same `_finalizeRngRequest`), so the read at JackpotModule:608 sees the just-incremented value. No race window for §2 against this writer.

5. **`dailyIdx` semantics confirmed (Phase 287 precedent).** Reader at `_rollHeroSymbol(dailyIdx, ...)` uses storage `dailyIdx` set by PREVIOUS day's `_unlockRng`; writer at DegeneretteModule:499 keys by `_simulatedDayIndex()` (current day). Same-cycle bets do NOT influence the slot the §2 reader actually accesses — the cross-day F-41-03 envelope from Phase 287 persists structurally but is not in-cycle exploitable for THIS consumer's single read.

## Deviations from Plan

None. Trace followed PLAN.md tasks 2.1 exactly. Sub-agent dispatch step (per PLAN.md action wording) was inlined into the main-context trace because this is a parallel-dispatch agent already running the consumer-§2 trace work; spawning a further sub-agent would duplicate work.

## Verification

- `.planning/phases/298-vrf-read-graph-catalog-catalog/298-02-CATALOG-section.md` exists with `## CAT-01`, `## CAT-02`, `## CAT-03`, `## CAT-04`, `## CAT-06` headings present
- No `SAFE_BY_DESIGN` in catalog file
- Every §D row classified ∈ {EXEMPT-ADVANCEGAME, EXEMPT-VRFCALLBACK, VIOLATION}; no blanks
- Every VIOLATION row carries a §E tactic ∈ {(a), (b), (c), (d)} with ≤80-char rationale
- Zero `contracts/` and zero `test/` modifications (audit-only artifact)
- No STATE.md / ROADMAP.md edits (orchestrator owns those writes after wave)

## Self-Check: PASSED

- File `.planning/phases/298-vrf-read-graph-catalog-catalog/298-02-CATALOG-section.md`: FOUND
- File `.planning/phases/298-vrf-read-graph-catalog-catalog/298-02-SUMMARY.md`: FOUND
- All 5 CAT sub-headings present in catalog (CAT-01, CAT-02, CAT-03, CAT-04, CAT-06)
- No "SAFE_BY_DESIGN" string in catalog
- Zero contracts/ + test/ files modified
