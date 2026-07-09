# AdvanceModule findings — fix sketches (for USER review)

All 5 survived cross-model council; C2 is Foundry-PoC-confirmed. These are CONTRACT
changes → USER authors/approves under the contract-commit gate. Sketches below are
options with tradeoffs, not applied. Full council text:
`advance-council-verdicts-2026-07-09.md`.

---

## C2 — purchase-phase-stall permanent brick  [CRITICAL · PoC-confirmed]

**Root cause.** `purchaseStartDay` (psd) is bumped by the FULL VRF gap for the
death-clock (`rngGate` ~L1263 `purchaseStartDay += gapCount`), but the SAME variable
is read as the purchase-phase-day counter in `day - psd` at:
- L203  `uint32 purchaseDays = day - psd;`  (turbo gate)
- L547  `if (day - psd <= 3)`               (compressed-jackpot flag)

The RNGREUSE clamp (L190) rewinds `day` to `dailyIdx+1` to re-walk backfilled days,
so `day` sits below the bumped psd → checked uint24 subtraction underflow → Panic,
above the game-over gate (L216) → permanent brick.

**Fix options (owner design intent needed):**
- **(A) Saturate the subtraction.** `day > psd ? day - psd : 0` at L203/L547.
  Minimal, but changes semantics: a 0 result makes `purchaseDays <= 1` and
  `day - psd <= 3` TRUE, which could mis-fire turbo/compressed-jackpot during a walk.
  Only safe if target-met is false on the walked historical days (usually true, but
  not guaranteed) — needs verification.
- **(B) Skip the turbo gate on backfill-walk days.** Add `&& day >= psd` (or
  `day > psd`) to the L202 guard `!inJackpot && !lastPurchaseDay && !locked`. Turbo is
  an optimization; skipping it when `day < psd` (only reachable on a backfill walk) is
  behavior-preserving for the normal path and removes the underflow. L547 needs the
  same `day >= psd` guard around the compressed-flag check. **Recommended** — smallest
  blast radius, no semantic change to the normal path.
- **(C) Decouple the two roles.** Keep a separate death-clock accumulator so psd stays
  the true purchase-phase start and is never bumped by the gap. Largest change; most
  "correct" but touches the death-clock/liveness logic — higher review cost.

Regression: invert `test/repro/AdvanceGapBackfillBrick.t.sol` (currently asserts the
brick EXISTS) to assert advanceGame survives the stall and the game keeps sealing.

---

## C4 — game-over ticket drain keys `lvl+1`, deadman tickets sit at `lvl`  [exclusion]

**Root cause.** The `_gameOverEntropy` drain block uses unconditional `lvl+1`
(L731 `processTicketBatch(lvl+1)`, L746 read-key), but on the VRF-death deadman entry
tickets from a locked last-purchase day / jackpot phase are queued at key `lvl`
(level pre-increments at the last-purchase RNG request; jackpot buys queue at
cachedLevel=lvl). Empty `lvl+1` queue → `_swapTicketSlot` with a non-empty read slot →
`ticketsFullyProcessed=true` latched while `lvl` entries stay undrained → excluded from
`handleGameOverDrain` terminal distribution.

**Fix sketch.** Derive the drain key the SAME conditional way the live path does
(L213/L502: `(lastPurchase && locked) ? lvl : lvl+1`, or `inJackpot ? lvl : purchaseLevel`)
instead of hard-coding `lvl+1` at L731/L746. Also review the sibling
`GameOverModule.runTerminalJackpot(remaining, lvl+1, rngWord)` for the same off-by-one
(flagged for the JackpotModule sweep).

Regression: drive VRF-death game-over with tickets queued at `lvl`; assert every queued
ticket participates in the terminal distribution.

---

## C5 — stale `ticketsFullyProcessed=true` skips the game-over drain  [exclusion]

**Root cause.** The flag is only cleared by `_swapTicketSlot` (daily path: at RNG
request time, L437). Two game-over entries never swap: (i) full abandonment → deadman
game-over via `_tryRequestRng` (L1424) with no swap; (ii) coordinator revert at request →
fallback word commits, no swap. Either way the write-slot queue at `_tqWriteKey(lvl+1)`
is never promoted to read → those buyers excluded from the terminal jackpot. The mid-day
path already handles this at L1190-1194.

**Fix sketch.** Mirror the mid-day guard in the game-over drain: before the drain, if
the write/read ticket slot holds entries and `ticketsFullyProcessed`, force a
`_swapTicketSlot()` so the pending cohort is drained. Likely fixed together with C4
(both are the game-over drain block's ticket-slot handling).

Regression: both sequences (abandonment; coordinator-revert-fallback) → assert
write-slot buyers are in the terminal distribution.

---

## C1 — VRF rotation re-issues on a stale LR_MID_DAY flag  [entropy · admin-gated]

**Root cause.** `updateVrfCoordinatorAndSub` L1878 tests `LR_MID_DAY != 0` as "mid-day
in flight", but mid-day fulfillment clears vrfRequestId/rngRequestTime while leaving
LR_MID_DAY=1 until the batch drains. Rotation in that window re-issues a spurious request
whose fulfillment overwrites the write-once `lootboxRngWordByIndex[N]` (entropy re-roll) +
double `LootboxRngApplied`. The daily branch (L1885) guards on `rngWordCurrent==0`; the
mid-day branch has no `rngRequestTime!=0` equivalent.

**Fix sketch.** Gate the mid-day re-issue (L1878) on an actual in-flight marker:
`if (_lrRead(LR_MID_DAY...) != 0 && rngRequestTime != 0)`. When LR_MID_DAY is set but
`rngRequestTime == 0` (word already landed, batch draining), do nothing — the batch drains
on the normal advance. Admin/governance-gated, so lower severity, but the write-once
entropy overwrite is real.

Regression: fulfill a mid-day request (word lands, LR_MID_DAY still 1), then rotate the
coordinator; assert `lootboxRngWordByIndex[N]` is NOT overwritten and no second
`LootboxRngApplied`.

---

## C3 — `_processPhaseTransition` double-run double-credits vault perpetual entries  [accounting]

**Root cause.** Resume marker `ticketLevel == ffLevel|TICKET_FAR_FUTURE_BIT` (L462), but
MintModule clears `ticketLevel=0` in the same call that finishes the drain; the in-range
break `ffWorked || !ffFinished` (L474) still breaks on a work+finish batch. Next advance:
`resumingFF` false → `_processPhaseTransition(purchaseLevel)` runs a 2nd time → `_queueEntries`
accumulates → SDGNRS + VAULT each get 2× VAULT_PERPETUAL_ENTRIES at level+99.

**Fix sketch.** Make `_processPhaseTransition`'s perpetual-entry queueing idempotent per
transition — e.g. a per-level "perpetuals queued" marker checked before `_queueEntries`,
or restructure the resume-marker/break so a finished-and-worked batch does not lose the
resume marker before housekeeping completes. Needs a careful look at the MintModule
`ticketLevel` clear ordering to pick the minimal seam.

Regression: drive a phase transition whose level+5 far-future bucket is non-empty; assert
SDGNRS/VAULT receive exactly 1× perpetual entries at level+99, not 2×.

---

### Suggested sequencing
C4 + C5 share the game-over drain block → fix together, one diff. C2 is standalone and
top-severity. C1 standalone (admin-gated). C3 standalone (needs MintModule cross-read).
Each fix lands with its PoC inverted to a regression test, then re-run the AdvanceModule
mutation campaign (Track 3) on the fixed code.
