# Phase 421 — MIDRNG (Mid-Day RNG Edge Cases) — Findings

**Phase:** 421 MIDRNG · **Date:** 2026-06-17 · **Reqs:** MIDRNG-01..03
**Subject:** frozen `contracts/` tree `4a67209a` @ HEAD `0bb7deca` (clean).
**Method:** cross-model council (Gemini 3 Pro + Codex) = NET-1 · Claude NET-2 (3 break-attempt verifiers + adversarial refute + completeness critic; **2 verifiers built+ran forge probes**) · orchestrator crux. Honest admin/governance assumed (rotation/keeper liveness IN scope).

## Verdict: 0 CAT / 0 HIGH / **1 MEDIUM cluster (2 MED + 2 LOW, interrelated)** — CONTRACT FIX PENDING USER DECISION

The mid-day RNG **word-binding and partial-drain DATA plane are sound** (no double-drain, no skipped ticket/box, no outcome-shifting rebind in the base case — MIDRNG-03 HOLDS, MIDRNG-01 data-plane HOLDS). But NET-2's adversarial probes (which the external council MISSED — both gemini+codex REFUTED MIDRNG-02) surfaced a real **mid-day CONTROL-plane cluster** on the heartbeat spine, centered on the cross-day-boundary interleaving of a stalled mid-day **ticket** request. This was **already known-open**: the skipped test `test_midDayRequest_doesNotBlockDaily` (`test/fuzz/VRFCore.t.sol:419`, `vm.skip(true)`, `DEF-380-04-FC1`) documents this exact divergence and **explicitly deferred it to this council sweep**.

## Findings

### MIDRNG-02 — `LR_MID_DAY` latch leak across the day boundary — **MEDIUM** (confirmed by 2 independent forge probes)
`LR_MID_DAY` has exactly ONE setter (`AdvanceModule:1131`, in `requestLootboxRng`'s ticket-swap block) and ONE clearer (`:241`, inside the same-day `if (day == dIdx)` mid-day block). If a mid-day ticket request's read-slot drain instead completes on the **new-day daily-drain gate** (`:274-300`, which sets `ticketsFullyProcessed=true` at `:299` but has **no** `LR_MID_DAY` clear), `LR_MID_DAY` stays `1` forever → `requestLootboxRng` permanently reverts at `:1082` → the mid-day lootbox fast-path is **permanently disabled** for the rest of the game (self-deadlock: the clearer needs the mid-day block, which needs `requestLootboxRng`, which the stuck flag blocks). **Reachable in honest flow** (no adversary): just requires no `advanceGame` between the mid-day VRF fulfillment and the day boundary — a normal keeper-timing race. NOT a brick / NOT a fund loss (boxes still resolve via the daily advance one cycle later), hence MEDIUM. Both the NET-2 verifier and its independent refuter reproduced it with forge probes (`LR_MID_DAY` stuck at 1 across 16+ days; `requestLootboxRng` reverts).

### MIDRNG-CRIT — ticket-stall-cross-day loses the daily 12h self-heal — **MEDIUM** (recoverable, but the automatic fallback is structurally bypassed)
In the same cross-day interleaving, if the mid-day VRF word has NOT yet arrived, the new-day daily-drain gate reverts `RngNotReady()` at `:282` (orphan word `==0` AND `rngWordCurrent==0`) **before** `rngGate` is reached — so `rngGate`'s daily 12h timeout-retry (`:1266-1272`, the normal VRF-stall self-heal) is **structurally unreachable** in this state (chicken-and-egg: setting `rngWordCurrent` needs a daily request, which needs `rngGate`, which the `:282` revert blocks). The heartbeat pauses. **Recovery under honest governance exists** but requires reviving the mid-day lane specifically: permissionless `retryLootboxRng` (after 6h, needs 40 LINK) re-fires the mid-day word → fills the orphan → unblocks the drain gate; or honest-governance `updateVrfCoordinatorAndSub` re-issues. So **NOT a permanent brick under the honest-admin model** (matches the 418 BRICK-05 VRF-death-recoverable precedent), but the **automatic daily self-heal is lost** — recovery depends on the mid-day lane being revived. CATASTROPHE-ceiling only if VRF is dead AND no governance acts (outside the honest model). Rated MEDIUM (liveness degradation on the DOMINANT spine).

### MIDRNG-01 — lootbox/bet-only stall can't use `retryLootboxRng` — **LOW** (self-healing)
A lootbox/bet-only mid-day request (no ticket swap → `LR_MID_DAY=0`) that stalls can't use the manual `retryLootboxRng` accelerator (`:1157` gate). But with no tickets queued, the new-day drain gate is **skipped** (`:276` false) → reaches `rngGate` → the daily 12h timeout (`:1266`) auto-recovers + `_backfillOrphanedLootboxIndices` resolves the orphan with the daily word. **Auto-heals; no brick, no stranded funds.** (Distinct from MIDRNG-CRIT: the no-ticket case does NOT hit the `:282` drain-gate trap.) Down-rated from codex's MED to LOW given the self-heal.

### MIDRNG-`:1843`-rebind — unconditional fulfill write enables word-rebind on re-issue — **LOW** (shared root with the 423 re-roll finding)
`rawFulfillRandomWords` mid-day branch (`:1843`) writes `lootboxRngWordByIndex[LR_INDEX-1] = word` **unconditionally** (no `== 0` guard). Combined with the stuck-`LR_MID_DAY` state (MIDRNG-02) or a governance coordinator rotation (the 423 gemini "Mid-day Rotation Re-roll" LOW), a re-issued mid-day request's word can **overwrite an already-finalized index** (probe reproduced: `0xCAFE → 0x9999`). VRF-fair (no attacker-chosen outcome, no EV gain), gated on a coinciding re-issue/rotation, hence LOW — but a binding-integrity defect.

### MIDRNG-03 — word-binding holds — **HOLDS**
Placement binds the live `LR_INDEX` (word `==0`-guarded for Degenerette/mint/presale); words always land at `LR_INDEX-1` (live index strictly ahead); resolvers require word `!=0`; `openHumanBoxes:681-682` stops at an un-worded index (no maroon); stale/old-coordinator callbacks rejected (`:1831-1832`). No re-pick, no double-write, no outcome-shift across stall/retry/gap-backfill/rotation/wall-day-jump.

## Recommended fix cluster (interrelated — design together; NEEDS USER APPROVAL)
1. **Clear `LR_MID_DAY` on the new-day drain completion** (`AdvanceModule:299`, where `ticketsFullyProcessed=true`), symmetric with `:241` → fixes MIDRNG-02 latch leak.
2. **Restore an automatic daily fallback for the orphaned mid-day ticket index** in the cross-day state — e.g. let the daily 12h timeout fire even when the orphan word is pending, or finalize the orphan from the daily word path — so the heartbeat self-heals without depending solely on the mid-day lane → fixes MIDRNG-CRIT.
3. **Guard the `:1843` fulfill write on `lootboxRngWordByIndex[index] == 0`** (don't overwrite a finalized index) → fixes the `:1843`-rebind + the 423 re-roll.

These touch `contracts/modules/DegenerusGameAdvanceModule.sol` only. Per the standing rule, **no `.sol` commit without USER review** — fixes are HELD pending the decision. Regression tests (incl. un-skipping `DEF-380-04-FC1`) → 424 MECH.

## Corrects the interim crux note
`421-CRUX.md` claimed the daily 12h timeout auto-recovers the ticket-stall case — that is **wrong for the ticket case** (the `:282` drain-gate revert front-runs `rngGate`); it is correct only for the no-ticket case (MIDRNG-01). The ticket case recovers via permissionless `retryLootboxRng` / governance rotation, not the daily timeout. This FINDINGS doc supersedes the crux note.
