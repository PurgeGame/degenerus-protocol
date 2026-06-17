# Phase 421 MIDRNG — Verification

**Subject:** frozen tree `4a67209a` @ `0bb7deca` (analysis) → **re-frozen `4970ba5b` @ `73eb242a`** after the MIDRNG-02 fix. Clean.
**Method:** council (Gemini 3 Pro + Codex) + NET-2 (Claude, 3 verifiers + adversarial refute + completeness critic; 2 probes built+run) + orchestrator crux.

## Requirement attestation

| Req | Statement | Verdict | Evidence |
|-----|-----------|---------|----------|
| **MIDRNG-01** | Mid-day swap/retry cannot brick or mis-bind | ✅ HOLDS (+1 LOW) | Data plane sound; retry/daily-timeout/rotation recover any stall. LOW: lootbox-only stall can't use the manual retry but self-heals via the daily timeout. |
| **MIDRNG-02** | Mid-day partial-drain read slot resumable, no double-drain/skip | ✅ HOLDS after fix | Data plane was sound; the **control-latch** `LR_MID_DAY` leaked across the day boundary → **FOUND + FIXED `73eb242a`** (release on the new-day drain). Regression `test_midDayLatch_clearsOnCrossDayDrain` (pass-with-fix / fail-without). |
| **MIDRNG-03** | Mid-day word binding (live index/day) | ✅ HOLDS | Placement binds live `LR_INDEX` (word!=0 guarded); words land at `LR_INDEX-1`; resolvers require word!=0; `openHumanBoxes` stops at an un-worded index; stale/old-coordinator callbacks rejected. No re-pick / double-write / outcome-shift. |

## Findings
- **MIDRNG-02 (MEDIUM): FOUND + FIXED `73eb242a`** — `LR_MID_DAY` latch leak (NET-2-found, council-missed). Fix released the latch on the new-day drain; regression added.
- **MIDRNG-CRIT (MEDIUM): by-design-acceptable (USER)** — cross-day mid-day-ticket *stall* loses the automatic daily self-heal but recovers via permissionless `retryLootboxRng` / governance rotation. Same recoverability class as a daily VRF stall (418 precedent). No fix (USER call).
- **MIDRNG-01 (LOW):** self-healing retry-ergonomics gap → 425 disposition.
- **`:1843`-rebind (LOW):** unconditional fulfill write; main trigger (stuck latch) removed by the MIDRNG-02 fix; optional `==0` guard → 425.

## Success criteria (ROADMAP phase 421) — met
1. Mid-day swap/retry can't brick/corrupt/mis-bind ✅ (MIDRNG-02 latch leak fixed; retry recovers stalls). 2. Partial-drain resumable, no double-drain/skip ✅ (data plane sound; latch leak fixed). 3. Mid-day word binding holds ✅.

## Routed forward (424 MECH / 425)
- 424: un-skip or pair `DEF-380-04-FC1` with the new latch regression; assert the cross-day drain + stall-recovery behaviors.
- 425: final disposition of MIDRNG-01 LOW + the optional `:1843` `==0` guard; record MIDRNG-CRIT USER by-design ruling.
