# Phase 421 MIDRNG — Summary

**Done:** 2026-06-17 · **Reqs:** MIDRNG-01..03 ✅ · **Method:** council (Gemini 3 Pro + Codex) + NET-2 (Claude, 3 verifiers + critic, 2 forge probes) + crux. Subject `4a67209a`@`0bb7deca` → re-frozen `4970ba5b`@`73eb242a` after the fix.

**Verdict: 0 CAT / 0 HIGH / 1 MED FOUND+FIXED + 1 MED by-design + 2 LOW.** Mid-day RNG **data plane is sound** (word-binding, no double-drain/skip — MIDRNG-03 + 01 data-plane HOLD). NET-2's adversarial forge probes found a **control-plane** cluster the external council missed (both gemini+codex REFUTED MIDRNG-02).

**MIDRNG-02 (MEDIUM) — FOUND + FIXED `73eb242a`:** `LR_MID_DAY` was cleared only by the same-day drain block; a mid-day ticket batch whose word arrives fine but whose drain crosses the day boundary completes on the new-day gate, leaving the latch stuck at 1 → `requestLootboxRng` permanently reverts (mid-day fast-path bricked). Reachable by a benign keeper-timing race (no VRF stall). Fix: release the latch on the new-day drain (guarded, non-regressive). Regression `test_midDayLatch_clearsOnCrossDayDrain` (pass-with-fix/fail-without).

**MIDRNG-CRIT (MEDIUM) — USER by-design-acceptable:** the cross-day mid-day-ticket *stall* (word not arrived) loses the automatic daily 12h self-heal (`:282` gate front-runs `rngGate`) but recovers via permissionless `retryLootboxRng` (6h) / governance rotation — same recoverability class as a daily stall (418 precedent). USER ruled the slow-down acceptable; no fix.

**LOW:** MIDRNG-01 (lootbox-only stall self-heals via daily) + `:1843` unconditional fulfill write (optional `==0` guard, main trigger removed by the MIDRNG-02 fix) → 425 disposition.

NEXT = 423 VRFSWAP NET-2 (codex deferred — cap; gemini+NET-2), then 424 MECH, 425 COUNCIL. The 422 GAMEOVER analysis already landed clean (tombstone CAT refuted → INFO; forfeit MEDIUM-by-design).
