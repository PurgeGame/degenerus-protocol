# Phase 423 — VRFSWAP (Honest Coordinator Rotation) — Findings

**Phase:** 423 VRFSWAP · **Date:** 2026-06-17 · **Reqs:** VRFSWAP-01..03
**Subject:** frozen `contracts/` tree `4970ba5b` @ `73eb242a` (post-MIDRNG-02-fix). Clean.
**Method:** NET-1 = Gemini 3 Pro council (**codex DEFERRED — usage cap, resets ~16:48; backfill outstanding**) · Claude NET-2 (5 break-attempt verifiers + adversarial refute + completeness critic) · orchestrator crux. Honest admin/governance assumed; rotation **liveness** in scope (admin malice out).

## Verdict: 0 CATASTROPHE / 0 HIGH / 0 MEDIUM real findings

An honest-governance coordinator rotation at any timing (mid-day / mid-request / stalled / while-locked) holds every freeze-relevant variable consistent, never lets a stale coordinator/requestId write a word, and always restores a path to a fulfilled word on the correct day. All residuals are LOW/INFO robustness notes, none a brick.

## Leads adjudicated

| Lead | NET-1 (gemini) | NET-2 + crux | Disposition |
|------|----------------|--------------|-------------|
| **VRFSWAP-01** rotation holds freeze-vars consistent | REFUTED | **HOLDS** — stale-callback safety (`msg.sender==vrfCoordinator` after repoint + `requestId==vrfRequestId` + `rngWordCurrent==0`); 3 mutually-exclusive re-issue branches correct; **slot 5 never RMW'd by rotation** (no clobber); recovery composition (12h retry + gameover fallback + re-rotation) intact | **HOLDS** |
| **VRFSWAP-02** mid-day/mid-request/stalled/while-locked rotation | REFUTED | **HOLDS/INFO** — all 4 timings restore a fulfilled-word path; mid-day re-issue keeps `LR_INDEX`/`LR_MID_DAY` so the word lands in the reserved slot; rotation tx atomic (reverting re-issue rolls back the whole swap, no corruption); **blocks-never-bricks** | **HOLDS** |
| **VRFSWAP-03** rawFulfill stale coordinator/requestId | REFUTED | **HOLDS** — two-layer guard rejects old-coordinator + stale-requestId callbacks; post-rotation fulfillment lands on the intended day/index | **HOLDS** |
| **VRFSWAP-REROLL** mid-day rotation re-roll / `:1850` unconditional write | gemini flagged LOW | **COUNTEREXAMPLE → LOW** (refuter stands-up=true, LOW) — the `:1850` mid-day fulfill write has no `==0` guard, so a rotation while a delivered-but-undrained mid-day word sits at `LR_MID_DAY=1` re-rolls `lootboxRngWordByIndex[N]`. **VRF-fair: no attacker-chosen outcome, no EV, no solvency effect** (auto-open uses an unpredictable/un-timeable seed; open zeroes the entry → no double-pay). Effectively unreachable under honest admin (needs a 20h daily-stall rotation to coincide with a fresh-but-undrained mid-day word). Same `:1843`/`:1850` root as the MIDRNG `:1843`-rebind LOW. | **LOW → 425 (optional `==0` guard)** |
| **VRFSWAP-SLOT5** totalFlipReversals carry vs timestamp | — | **HOLDS** — rotation writes neither slot-5 field (carry by not-touching); all slot-5 writers are typed masked-RMW; nudge carry + `_gameOverEntropy` pre-subtraction sound | **HOLDS** |

## Completeness critic — 3 new rotation-timer modalities, all LOW/INFO (none a brick)
1. **Grace-bailout reset chain (LOW):** rotation re-arms `rngRequestTime` (`:1779`/`:1785`), which is the timer `_livenessTriggered`'s 14-day grace bailout + `_gameOverEntropy`'s fallback read. A chain of honest rotations (each <14d) defers the grace fallback — but the **120/365-day day-math backstop is NOT rotation-resettable** and honest governance won't loop maliciously → LOW liveness-delay, not a brick. (A "split-timer" coupling: recovery resets the timer the safety net uses; the Admin author preserves `lastVrfProcessedTimestamp` but the module resets the *different* `rngRequestTime` that gates liveness.)
2. **Wasted-recovery in gameover-fallback wait (INFO/LOW):** a rotation during the VRF-dead gameover wait issues no request on the fresh coordinator (the fallback set `rngRequestTime` without `rngLockedFlag` → rotation classifies "nothing in flight" → no-op repoint), so the game waits out the 14-day fallback instead of using fresh VRF. Liveness preserved → INFO.
3. **Rotation-aborts-on-new-coordinator-revert (LOW):** the in-flight re-issue has no try/catch, so a new coordinator that reverts the request aborts the whole swap (atomic, retryable — not a stale-write). Honest governance rotates to a standards-compliant coordinator → LOW. (Asymmetry: re-issue un-wrapped while the other two swap steps are try/catch-wrapped.)

## Cross-model coverage caveat
Codex was deferred (usage cap). 423 ran on **gemini + NET-2 (Claude, 2 rounds incl. refute)** + crux, all converging on 0 real findings. The verdict has ≥2 independent nets on every lead; the codex backfill (when the cap resets) is a completeness nicety, recorded as outstanding for 425.

## Routed forward (425)
- LOW: the `:1843`/`:1850` re-roll — optional `lootboxRngWordByIndex[index] == 0` guard (shared with the MIDRNG `:1843` LOW; USER-deferred for the MIDRNG cluster).
- LOW/INFO: the 3 rotation-timer robustness notes (grace-bailout reset chain is the most substantive — optional: reset a *separate* timer on rotation, or gate liveness off the non-resettable clock).
- Codex backfill outstanding.
