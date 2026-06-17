# Phase 423 VRFSWAP — Verification

**Subject:** frozen tree `4970ba5b` @ `73eb242a`. Clean.
**Method:** gemini council (codex DEFERRED — cap) + NET-2 (Claude, 5 verifiers + refute + critic) + crux.

## Requirement attestation

| Req | Statement | Verdict | Evidence |
|-----|-----------|---------|----------|
| **VRFSWAP-01** | Rotation holds every freeze-relevant variable consistent | ✅ HOLDS | 3 re-issue branches correct; stale-callback two-layer guard; slot 5 never RMW'd; in-flight request preserved/re-requested |
| **VRFSWAP-02** | Mid-day/mid-request/stalled/while-locked rotation can't brick or corrupt binding | ✅ HOLDS | All 4 timings restore a fulfilled-word path; atomic swap tx; blocks-never-bricks; existing rotation tests green |
| **VRFSWAP-03** | rawFulfill rejects stale coordinator/requestId; post-rotation lands on intended day/index | ✅ HOLDS | `msg.sender==vrfCoordinator` + `requestId==vrfRequestId` + `rngWordCurrent==0` guards |

## Findings
- **0 CAT / 0 HIGH / 0 MED real.**
- **LOW:** `:1850`/`:1843` re-roll (VRF-fair, benign, no EV/double-pay) → optional `==0` guard (shared with MIDRNG `:1843`).
- **LOW/INFO (3 rotation-timer notes):** grace-bailout reset chain (bounded by the non-resettable 120/365-day backstop), wasted-recovery in gameover wait, rotation-aborts-on-new-coordinator-revert (atomic/retryable). All recoverable under honest governance.
- Existing tests green: VrfRotationLiveness (6), RngLockRotationDeterminism (2 @1000 runs), VrfRotationOrphanIndex, VRFCore/VRFStallEdgeCases/StallResilience/LootboxRngLifecycle (64, 1 skip).

## Coverage caveat
Codex deferred (usage cap, ~16:48). Verdict carried by gemini + NET-2 (2 rounds) + crux, ≥2 nets per lead. Backfill outstanding → 425.

## Success criteria (ROADMAP phase 423) — met
1. Rotation holds freeze-vars consistent / in-flight preserved-or-re-requested ✅ 2. Any-timing rotation can't brick or corrupt the binding ✅ 3. rawFulfill validation correct across rotation ✅
