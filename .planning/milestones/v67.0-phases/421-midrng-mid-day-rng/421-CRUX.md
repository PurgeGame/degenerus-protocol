# Phase 421 MIDRNG — Orchestrator Crux (cross-model split resolution)

**The split:** Gemini raised an EXTRA finding (HIGH, REAL) — "Daily Advance Deadlock on Stalled Mid-Day Ticket Drain": a stalled mid-day ticket request (`LR_MID_DAY=1`, `ticketsFullyProcessed=false`) + VRF stall + day roll-over makes new-day `advanceGame` revert `RngNotReady()` at the daily drain gate (`AdvanceModule:282`, before reaching rngGate), claimed to permanently block the daily heartbeat. **Codex directly contradicts** (MIDRNG-01 MED + MIDRNG-02 REFUTED): recoverable via the daily timeout path; not a permanent brick.

## Crux verdict: Gemini HIGH is REFUTED — recoverable, NOT a permanent brick

**The drain-gate revert (AdvanceModule:274-300) IS reachable**, on a new day, when: `!ticketsFullyProcessed` AND `ticketQueue[preRk].length>0` AND `lootboxRngWordByIndex[preIdx]==0` AND `rngWordCurrent==0` → `revert RngNotReady()` (:282), before rngGate. So advanceGame reverts and the heartbeat pauses.

**But that state is recoverable** — three independent levers, all reachable under honest governance:

1. **Permissionless `retryLootboxRng` (the lever gemini missed).** The drain-gate-revert state implies a ticket swap happened, and a ticket swap is the ONLY thing that sets `LR_MID_DAY=1` (`requestLootboxRng:1129-1131`). It also implies `rngLockedFlag==false` (mid-day requests never set the daily lock; mid-day `requestLootboxRng` is itself blocked while the daily lock is held). Those are EXACTLY `retryLootboxRng`'s preconditions (`AdvanceModule:1152-1170`): `!rngLockedFlag` ✓, `LR_MID_DAY!=0` ✓, `rngRequestTime!=0` ✓, past `MIDDAY_RNG_RETRY_TIMEOUT` ✓. It re-fires the VRF word and PRESERVES `LR_INDEX` (no `_lrAdvanceIndexClearPending`), so the refilled word lands in `lootboxRngWordByIndex[preIdx]` → the drain gate's `if (word==0)` (:280) is now false → batch drains → heartbeat resumes. `retryLootboxRng` is `external` with no access modifier = permissionless; recovery does not depend on a privileged party. Gemini's own trigger concedes "*if retryLootboxRng is not called*, permanently blocked" — but it IS callable in this state.

2. **Daily 12h timeout** (for the complementary no-ticket case, see MIDRNG-01 below).

3. **Honest-governance VRF rotation** (`updateVrfCoordinatorAndSub`) if the coordinator itself is dead — the phase-418 BRICK-05 recovery precedent (total VRF death is recoverable by governance re-issuing to a healthy coordinator).

The heartbeat PAUSE is temporary (≤ `MIDDAY_RNG_RETRY_TIMEOUT` + one VRF round) and permissionlessly recoverable — the SAME recoverability class as a daily VRF stall, which phase 418 (DOMINANT brick phase) already accepted as non-bricking. **Not a permanent wedge → not HIGH.**

## Residual REAL item: MIDRNG-01 (LOW, self-healing)
The lootbox/bet-ONLY mid-day stall (no ticket swap → `LR_MID_DAY=0`): `retryLootboxRng` reverts (`:1157` `LR_MID_DAY==0` gate), so the manual accelerator does not cover this request shape. BUT: with no tickets queued, the new-day drain gate's `if (ticketQueue[preRk].length>0)` (:276) is FALSE → gate skipped → `ticketsFullyProcessed=true` → reaches rngGate, whose stale-request 12h timeout (`:1266-1270`) calls `_requestRng` for a fresh DAILY word; when it arrives, `_finalizeLootboxRng` + `_backfillOrphanedLootboxIndices` resolve the orphaned lootbox index. **Auto-recovers within ~12h; no brick, no stranded funds, no manipulability (word still VRF-frozen-at-index).** Codex rated MED; down-rated to LOW given the automatic self-heal. Disposition: LOW, real-but-self-healing retry-ergonomics gap — optional enhancement (set a retry-eligibility flag for lootbox-only requests) is a USER call at 425; NOT a mandated fix. → 424 MECH: a regression test pinning the daily-timeout recovery of a lootbox-only stall.

## MIDRNG-02 / MIDRNG-03 / hotspots — REFUTED (convergent)
Both models REFUTED; my read confirms: resumability via `ticketCursor`/`ticketsFullyProcessed` latch + the recorded-but-unsealed wall-day clamp (:184-186); word-binding correct (placement binds live `LR_INDEX`, fulfillment writes `LR_INDEX-1`, resolvers require word!=0, `openHumanBoxes:682` stops at a zero word); `rawFulfillRandomWords` daily/mid-day split is requestId+coordinator+`rngWordCurrent==0` gated then branches on `rngLockedFlag` (no wrong-branch fulfillment).
