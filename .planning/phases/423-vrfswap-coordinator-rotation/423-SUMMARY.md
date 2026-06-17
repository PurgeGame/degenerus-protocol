# Phase 423 VRFSWAP — Summary

**Done:** 2026-06-17 · **Reqs:** VRFSWAP-01..03 ✅ · **Method:** gemini council (codex DEFERRED — cap ~16:48) + NET-2 (Claude, 5 verifiers + refute + critic) + crux. Subject `4970ba5b`@`73eb242a`.

**Verdict: 0 CAT / 0 HIGH / 0 MED real findings.** Honest-governance coordinator rotation at any timing holds freeze-vars consistent, rejects stale coordinator/requestId writes, and always restores a fulfilled-word path. VRFSWAP-01/02/03 HOLD; existing rotation tests green (VrfRotationLiveness, RngLockRotationDeterminism @1000 runs, VrfRotationOrphanIndex, +64 VRF tests).

**LOW (→ 425):**
- `:1850`/`:1843` re-roll: the mid-day fulfill write lacks a `==0` guard, so a rotation while a delivered-but-undrained mid-day word is latched re-rolls the lootbox word — **VRF-fair, no EV, no double-pay** (open zeroes the entry); same root as the MIDRNG `:1843`-rebind LOW; optional `==0` guard.
- 3 rotation-timer robustness notes (critic): **grace-bailout reset chain** (rotation re-arms `rngRequestTime`, deferring the 14-day liveness fallback — bounded by the non-resettable 120/365-day backstop; a split-timer coupling), **wasted-recovery** (rotation in the gameover-fallback wait issues no fresh request), **rotation-aborts-on-new-coordinator-revert** (un-wrapped re-issue; atomic/retryable). All recoverable under honest governance, none a brick.

**Coverage caveat:** codex deferred → carried by gemini + NET-2 (2 rounds) + crux (≥2 nets/lead); backfill outstanding.

NEXT = 424 MECH (regression tests, test-only) + 425 COUNCIL (synthesis + `FINDINGS-v67.0` + closure). Open 425 dispositions are all LOW/INFO/by-design.
