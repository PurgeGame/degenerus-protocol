# AdvanceModule `_prepareFutureTickets` cursor-clobber — council verdict 2026-07-09

**Candidate (fable re-sweep round 1, chunk 1577-1667, tree d5e9f58a):** on every advance
call of a day, `_prepareFutureTickets(base, rngWord)` (AdvanceModule:513) runs BEFORE the
current-level drain `_runProcessTicketBatch(base)` (:526). Its empty-queue probe of `base+1`
executes `ticketCursor = 0; ticketLevel = 0` (MintModule:325-328), erasing the in-flight
BASE-level ticket resume cursor left by the previous call. The next `processTicketBatch(base)`
sees `ticketLevel != base` → resets cursor to 0 (MintModule:630-632) → rescans the whole
queue from index 0, re-skipping the already-processed prefix at 1 write-budget unit each.

## Council — UNANIMOUS CONFIRM (3 Claude lenses + Codex decorrelated)

**Scope narrowed identically by all four reviewers:** PURCHASE phase is INSULATED — the
pre-RNG daily-drain gate (AdvanceModule:302-360) drains `_tqReadKey(purchaseLevel)` on the
SAME key as :526's target, before rngGate, so a mid-queue break happens at :357 before :513
ever runs; the cursor survives (and purchase-phase foil resume uses a separate foil cursor).
The vulnerable drain is **jackpot-phase `_runProcessTicketBatch(lvl)` at :526**, whose key
`_tqReadKey(lvl)` differs from the pre-gate's `_tqReadKey(lvl+1)`, so `_prepareFutureTickets`
interleaves with it unprotected.

- **Reachability lens (Claude):** STANDS jackpot-phase / REFUTED purchase-phase. Full gate
  trace entry→:513 on the 2nd same-day call: RNGREUSE clamp :191, turbo skipped (word
  cached), game-over path returns (false,0), mid-day skipped (day==dIdx+1), daily pre-gate
  :302 skipped (ticketsFullyProcessed latched true, different key), subs done, rngGate
  returns cached word gapDays=0, no phase-transition, dailyJackpotCoinTicketsPending false
  → reaches :513. Clobber + rescan confirmed at cited lines.
- **Cursor-semantics lens (Claude):** STANDS. Full reader/writer table for
  ticketLevel/ticketCursor; both empty-probe (:325-328) and non-empty-probe (:331-333)
  paths destroy the base resume state; :825 skip = exactly 1 unit; value-idempotent (owed
  zeroed, no double-mint). Correction: cold budget = **358**, not ~357. Flagged an
  ADJACENT hazard: the same empty probe can also erase a far-future resume marker
  (MintModule:455-460), a second victim of the same root cause.
- **Feeder/threshold lens (Claude):** REACHABLE. **Refutes the reviewer's own "capped ~100"
  premise.** Ordinary permissionless ticket purchases QUEUE (not direct-mint):
  `_purchaseFor`→`_queueEntriesScaled` (MintModule:1632) targets `cachedJpFlag?level:level+1`
  = base (derivation :1967), deduped per distinct address (Storage:688) → queue length ==
  distinct buyers, NO per-day/per-tx buyer cap. The 100-cap (LOOTBOX_MAX_WINNERS) bounds
  only the jackpot distributor (feeder #6), not the purchase path. Swap moves write→read at
  RNG request; that cohort is exactly what :526 drains next advance. Threshold: cold budget
  358, skip 1 unit, whole-ticket mint 11 units.
- **Codex (decorrelated, biased-to-refute):** "The cursor clobber is confirmed on the
  jackpot-phase line-526 path. The purchase-phase base queue is drained earlier and resumes
  safely. Feeder tracing also refutes the suggested 100-address aggregate cap."

## Permanence math (orchestrator derivation)

Read queue of N distinct owed=4 entries at jackpot-phase key, fresh cursor. Each advance
call: clobber → rescan from 0 → skip processed prefix P (1 unit each) → mint from remaining
budget (358 − P) at 11 units/entry → new progress = floor((358 − P)/11). P grows each call:
32, then 61, 88, … asymptoting. Progress hits 0 at P = 348 (`(358−348)/11 = 0`). **For
N ≥ ~349 the tail (entries 348…N−1) is NEVER processed → advanceGame loops
STAGE_TICKETS_WORKING forever → the day never completes → resolves only via the 120-day
liveness game-over.** For 33 ≤ N ≤ 348: quadratic re-skip = extra advance txs / gas waste
(degraded but self-completing). No double-mint in either tier (owedMap idempotent).

## Severity / disposition

- Class: **advanceGame liveness stall** = the USER-locked DOMINANT threat tier
  ([[threat-model-reentrancy-mev-nonissues]]: gas-DoS in advanceGame = "gg").
- Trigger: **permissionless** — ~349 distinct addresses each buying a ticket in one
  jackpot-phase accumulation day (Sybil-feasible at cost ≈ 349 × min ticket price). Not
  admin-gated, not a self-break.
- PRE-EXISTING: `_prepareFutureTickets`/`processTicketBatch` untouched by the 2026-07-09 C1-C5
  fix batch; the prior (old-session) sweep round called this region clean — fable's fresh
  lens surfaced it. Independent of C1-C5.
- Adjacent FF-marker victim (cursor-semantics lens) folds into the same fix.

## NEXT
1. Foundry PoC: drive a jackpot-phase day with ≥349 distinct ticket buyers, assert
   advanceGame cannot complete the day (permanent STAGE_TICKETS_WORKING). PoC-gate before
   HIGH ([[feedback_skeptic_pass_before_catastrophe]]).
2. Report to USER (contract-commit gate). Fix direction (for USER): make
   `_prepareFutureTickets` not probe/clobber while a base-level batch is in flight — e.g.
   skip the future-probe when `ticketLevel == base` (or guard the empty-probe reset to only
   fire for a level actually in the future window), preserving the base resume cursor; cover
   the adjacent FF-marker case in the same guard.
