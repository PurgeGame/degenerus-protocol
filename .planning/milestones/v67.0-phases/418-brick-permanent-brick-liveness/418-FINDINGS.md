# Phase 418 — BRICK (Permanent-Brick / Liveness) — Findings

**Phase:** 418 BRICK (DOMINANT) · **Date:** 2026-06-17 · **Reqs:** BRICK-01..05
**Subject:** `contracts/` tree `0dd445a6` (council + NET-2 ran on this) → **re-frozen `4921a428`** after the in-milestone gas-headroom remediation (the reweight is constants-only; no brick conclusion changes).
**Method:** cross-model council (Gemini + Codex) = NET-1 primary finder · Claude Workflow = NET-2 (9 verifiers + adjudication) · orchestrator crux verification on the cross-model split. Honest admin/governance assumed.

## Verdict: 0 CATASTROPHE / 0 HIGH / 0 MEDIUM / 0 LOW real findings

The spinal column is brick-resistant: no reachable transaction permanently wedges `advanceGame`, blocks `gameOver` finalization, makes the daily VRF word permanently unobtainable, or crosses the 16.7M (EIP-7825 16,777,216) per-tx gas cap. **One gas-headroom finding (BRICK-FIND-01) was found and remediated in-milestone.** One test-hardening item routed to 424 MECH.

## Leads adjudicated

| Lead | NET-1 (council) | NET-2 | Orchestrator | Disposition |
|------|-----------------|-------|--------------|-------------|
| **L1** sDGNRS `resolveRedemptionPeriod` uint96 underflow (P20) | gemini + codex REFUTED | REFUTED (bit-exact: submit `maxIncrement` :1108 ↔ resolve `segregatedMax` :753/:756 cancel; checked arith + INV-13 + claim-after-resolve ordering) | — | **REFUTED** |
| **L2 / BRICK-04** worst-case gas vs 16.7M | gemini REFUTED w/ bounds; codex UNCERTAIN (sandbox couldn't run harness) | REFUTED (all 4 near-spine loops bounded: orphan-backfill O(1–2)@:1894, deity ≤32, BAF 50-round cap, redemption-lootbox off-spine; heavy legs decoupled) | **empirically confirmed**: 27 worst-case forge gas tests pass < 16.78M; binding tx measured | **REFUTED** (+ headroom improved by BRICK-FIND-01 fix) |
| **L3** gameOver finalization all-or-nothing | gemini + codex REFUTED (clean revert-rollback of the `gameOver` latch; `GameOverCompositionAdvanceGas` passes) | covered by PERM-triage (P16–P19 finalize reverts → transient/rollback) | — | **REFUTED** |
| **L4 / L6** cross-day VRF-stall deadlock | **gemini flagged CATASTROPHE**; codex REFUTED | covered by council + crux | **crux-REFUTED (airtight)**: in the `lastPurchaseDay`/`jackpotPhaseFlag` window the permissionless `_livenessTriggered` bailout is gated off (Storage:1465) AND the in-loop 12h retry is unreachable past the `:283` `RngNotReady` revert — BUT the honest-governance `updateVrfCoordinatorAndSub` re-issues the stalled daily request (`AdvanceModule:1774-1780`, gated on `rngLockedFlag` which the daily request sets at `:1696`); the healthy coordinator's callback sets `rngWordCurrent` (`:1840`) and the next `advanceGame` passes `:283`. Recoverable under honest governance. | **REFUTED** (residual INFO: recovery is admin-dependent in that terminal-approach window — by-design, the bailout is intentionally gated off near gameover) |
| **L5** post-liveness stranded reverts | gemini + codex REFUTED (`handleGameOverDrain` captures stranded value via `preRefundAvailable = totalFunds − claimablePool`) | covered by PERM-triage | — | **REFUTED** |
| **BRICK-01** permanent-revert candidate class (58 → COLMAP P1–P43 + 4 gas comps) | — | **REFUTED**: every candidate → transient / guarded-by-construction / unreachable-under-honest-economics / callee-safe / structurally-unreachable-post-liveness / hard-bounded-loop / non-spine | — | **0 permanent-wedge survivors** |
| **BRICK-02** `advanceGame` always-progresses | — | covered by PERM-triage + the P10 discharge + critic | — | **HOLDS** |
| **Completeness critic** | — | REFUTED (every category maps to an existing candidate / a phase-420 CORRUPT slot / an enumerated gas comp; no missing brick vector) | — | **no missing vector** |

### P10 residual (div-by-zero `(memFuture*100)/memNext` at `AdvanceModule:845`) — DISCHARGED
NET-2's one MEDIUM-confidence residual. Re-traced + closed: `_consolidatePoolsAndRewardJackpots` runs only on the level-transition branch (`:515-518`), reached only after `lastPurchase` latched past a met **positive** target; `purchaseLevel==1` takes a separate branch breaking at `:498` before the div. `memNext` cannot be 0 at `:845`. Not a finding. → a regression test pinning this is routed to **424 MECH** (test-only).

## BRICK-FIND-01 — binding-stage gas headroom + miscalibrated weight model — FOUND + REMEDIATED in-milestone

**Finding (LOW/robustness, defense-in-depth):** the afking subscriber-STAGE `SUB_STAGE_WEIGHT_BUDGET` under-weighted evictions (`SUB_STAGE_EVICT_WEIGHT = 1` vs the true ~27k cold marginal — a cross-contract quest streak write + `_removeFromSet` swap-pop, on par with a ticket), so a saturated all-evict crank packed 500 finalizes/chunk ≈ **13.6M** gas — the binding advance-chain worst case, only ~3.1M under the 16.78M EIP-7825 cap. The weight model's own comments mis-stated this chunk as ~5.5M, and the afking gas-ceiling tests were **analytic projections that hardcoded the old weights** (a detection-net gap — they never cranked the chunk live).

**Disposition: USER-directed + approved fix SHIPPED `2aed5d28`** (constants only, zero logic): `EVICT_WEIGHT 1→7`, `BUDGET 500→2500` (+ `LOOTBOX 2→10`, `TICKET 4→21` to ratio all ops on true marginals). All-evict chunk → **9,712,869** (live-measured), headroom **3.1M → 7.06M**; lootbox/ticket chunk counts ~unchanged; V62-02 backfill segregation intact (weight-independent control flow). Added `test_AllEvictSaturatedChunk_LIVE_Measured` (a real live crank, closing the analytic gap). Full suite 901/0/109. Independent post-fix review (`wf_c8fde4b8`) = CLEAN, strict safety improvement. New binding stage = warm ticket-batch resume ~9.94M (6.83M headroom) — the figure to watch going forward.

## Coverage / transparency note
NET-2 had 5 of 9 verifier agents (L3, L4, L5, L6, BRICK-02-progress) complete their analysis but fail to emit *structured* output (a StructuredOutput tooling hiccup; their work is in the run transcripts). Those exact leads are independently covered by NET-1 (council, all on record) + the orchestrator crux verification (L4/L6) + NET-2's PERM-triage (P1–P43, which enumerates the gameover/liveness/strand revert sites) + the completeness critic. The 0-finding verdict has ≥2 independent nets on every lead.

## Routed forward
- **424 MECH:** (1) a level-0→1 zero-next-pool regression pinning `_consolidatePoolsAndRewardJackpots` (P10); (2) the live worst-case eviction harness already landed (`test_AllEvictSaturatedChunk_LIVE_Measured`); (3) keep the worst-case gas harness asserting < 16.78M.
- **420 CORRUPT:** the critic mapped 2 items to CORRUPT-01 (packed-slot) — already in 420's scope.
