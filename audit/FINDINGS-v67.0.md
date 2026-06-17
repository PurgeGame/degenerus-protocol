# Degenerus Protocol — v67.0 Audit Findings

**Milestone:** v67.0 — Spinal-Column Brick & State-Corruption Audit (mintFlip / advanceGame chain) — Cross-Model Council
**Date:** 2026-06-17
**Subject (frozen):** HEAD `3d0ee5d3` · `contracts/` tree **`4970ba5b`**. The audit opened on tree `0dd445a6` @ `fa7932f6`; the tree advanced only via the two in-milestone fixes below (DELEGATE-FIND-01 `095a7ac9`, MIDRNG-02 `73eb242a`).
**Closure signal:** `MILESTONE_V67_AT_HEAD_3d0ee5d31def04d3a49c838ea2f87f8093673787`
**Method:** Cross-model council (Gemini 3 Pro + Codex/gpt-5.5) as PRIMARY finder + Claude NET-2 (isolated break-attempt verifiers → adversarial refutation → completeness critic, forge probes where decisive) + orchestrator crux adjudication. Every candidate adversarially verified before recording; majority-refute kills it. Honest admin/governance assumed (admin malice out of scope; rotation/keeper liveness IN scope).
**Regression floor:** full forge suite **903 passed / 0 failed / 108 skipped** (exit 0) on the frozen tree.

---

## Verdict: 0 CATASTROPHE / 0 HIGH · 1 MEDIUM FOUND + FIXED · all else by-design / INFO / LOW

The spinal column is **brick-resistant and corruption-resistant** across 10 phases. The hunt found **two real contract defects, both fixed in-milestone** (one LOW in DELEGATE, one MEDIUM in MIDRNG). Every other candidate — including two convergent cross-model CATASTROPHE candidates — was refuted as unreachable or dispositioned as by-design.

| Phase | Category | Verdict |
|---|---|---|
| 416 FOUND | Subject freeze + green baseline | ✅ frozen `0dd445a6`@`fa7932f6`; baseline 900/0/109 |
| 417 COLMAP | Re-derived call graph | ✅ 322 fns / 393 reverts / 192 DC-writes / load-bearing map |
| 418 BRICK (DOMINANT) | Permanent-brick / liveness | ✅ 0 real; **BRICK-FIND-01** gas-headroom remediated `2aed5d28` (all-evict 13.6M→9.7M); gemini L4/L6 CATASTROPHE refuted (honest VRF-rotation recovery) |
| 419 DELEGATE | Delegatecall integrity | ✅ 0 CAT/HIGH/MED; **DELEGATE-FIND-01 (LOW) found+fixed `095a7ac9`** (direct-call ETH-trap on 4 payable delegatecall-only entrypoints; codex-unique) |
| 420 CORRUPT | State-corruption invariants | ✅ 0 real; CORRUPT-01..05 HOLD; 2 INFO (decimator reserve-superset documented; slot-46 callee-protected) |
| 421 MIDRNG | Mid-day RNG edge cases | ✅ **1 MED FOUND+FIXED `73eb242a`** (MIDRNG-02 LR_MID_DAY latch leak); 1 MED by-design; 2 LOW |
| 422 GAMEOVER | Terminal-branch liveness | ✅ 0 real; FLIP-tombstone CATASTROPHE **refuted→INFO** (unreachable); forfeit MED-by-design; gas ~7.2M<16.78M |
| 423 VRFSWAP | Honest coordinator rotation | ✅ 0 real; VRFSWAP-01/02/03 HOLD; LOW re-roll + 3 rotation-timer notes |
| 424 MECH | Mechanical-net closure (test-only) | ✅ gas/solvency covered; MIDRNG-02 + DEF-380-04-FC1 regressions; suite 903/0/108 |
| 425 COUNCIL | Synthesis + closure | ✅ this document |

---

## Confirmed findings (both fixed in-milestone)

### DELEGATE-FIND-01 — LOW — direct-call ETH-trap (FIXED `095a7ac9`)
Four `external payable` delegatecall-only entrypoints (Boon ×3 + `resolveLootboxDirect`) lacked an `address(this)==GAME` guard, so a direct call with ETH would trap the caller's own value (no Game-state corruption, no drain). Codex-unique. Fixed with the existing Degenerette idiom (`address(this)==GAME` guard). Suite 901/0/109.

### MIDRNG-02 — MEDIUM — `LR_MID_DAY` latch leak across the day boundary (FIXED `73eb242a`)
The mid-day lootbox latch `LR_MID_DAY` was released only by the same-day drain block. A mid-day ticket batch whose VRF word arrives fine but whose drain crosses the day boundary (no same-day `advanceGame`) completes on the new-day daily-drain gate, which never released the latch — leaving it stuck at `1` and permanently reverting `requestLootboxRng` (the mid-day fast path) for the rest of the game. Reachable by a benign keeper-timing race (not a VRF stall); NET-2 confirmed with two independent forge probes (the external council REFUTED MIDRNG-02 — a Claude-net-unique catch). The data plane (which ticket/box gets which word) was sound throughout; this was a control-latch leak only.
**Fix:** release `LR_MID_DAY` where the new-day gate sets `ticketsFullyProcessed=true`, symmetric with the same-day release, guarded so non-bug flows take the identical no-write path (provably non-regressive). Regression `test_midDayLatch_clearsOnCrossDayDrain` (pass-with-fix / fail-without `NotTimeYet`). USER-approved.

---

## Refuted CATASTROPHE candidates (the two that mattered)

### FLIP `tombstoneAtGameOver` uint128 overflow (422) — REFUTED → INFO
Both Gemini and Codex flagged `vaultAllowance = _toUint128(vaultAllowance + 1e36)` reverting on overflow inside `handleGameOverDrain` as a finalization wedge — both punted on reachability. NET-2's emission-bound derivation closed it: `vaultAllowance ≤ total FLIP ever minted` (conserved across vault transfers), the boundary (~3.4e20 FLIP) needs **~34 consecutive max-bonus coinflip wins on separate days (`P ≤ 2^-34`)**, and `autoRebuyCarry`/`claimableStored` are themselves uint128-capped backstops; the only boundary-reaching test uses a god-mode `vm.prank(GAME)` escrow. The checked revert is correct defensive behavior → INFO ("headroom not formally reserved", optional; ~340× headroom documented).

### gemini cross-day VRF-stall deadlock (418 L4/L6) — REFUTED
Refuted by crux: recoverable under honest governance via `updateVrfCoordinatorAndSub` re-issuing the stalled daily request to a healthy coordinator. (The 418 BRICK-05 recoverability precedent.)

---

## By-design / INFO / LOW dispositions (no fix; USER sign-off requested)

| ID | Sev | Disposition |
|---|---|---|
| **CORRUPT-05 / INFO-01** | INFO | `claimablePool == Σ(claimable+afking)` is a temporary *reserve superset* during decimator settlement — **documented in-code** (`Storage:361`), solvency-POSITIVE (over-reserved). The accurate identity includes outstanding decimator claim rounds. By-design. |
| **slot-46 `yieldAccumulator` / INFO-02** | INFO | Cache-overwrite across `coinflip.creditFlip` is reentrancy-safe *because* `creditFlip` is callback-free (layer-1 structural) — not reachable on the frozen tree; future-edit fragility only (same class as the fixed `_payoutWithStethFallback`). |
| **MIDRNG-CRIT** | MED (by-design) | Cross-day mid-day-*ticket* **stall** loses the automatic daily 12h self-heal (the `:282` drain gate front-runs `rngGate`); recovers via permissionless `retryLootboxRng` / governance rotation — same recoverability class as a daily VRF stall. **USER ruled acceptable** (slows down, never bricks). |
| **GAMEOVER forfeit** | MED (by-design) | Pending degenerette bets / unopened lootboxes are *forfeited* (not refunded per-player) at liveness gameover — but the **ETH is conserved** (prize-pool ETH captured by `handleGameOverDrain` and redistributed to terminal pools/sinks; solvency preserved). Matches prior-milestone gameover forfeits. |
| **MIDRNG-01** | LOW | A lootbox/bet-only mid-day stall can't use the manual `retryLootboxRng` accelerator but self-heals via the daily 12h timeout. No brick, no stranded funds. |
| **`:1843`/`:1850` re-roll** | LOW | The mid-day fulfill write lacks a `== 0` guard, so a re-issue/rotation while a delivered-but-undrained word is latched can overwrite a finalized index — **VRF-fair, no EV, no double-pay** (auto-open uses an unpredictable seed; open zeroes the entry). Optional `== 0` guard; the MIDRNG-02 fix removed the main (stuck-latch) trigger. |
| **423 rotation-timer notes ×3** | LOW/INFO | grace-bailout reset chain (bounded by the non-resettable 120/365-day backstop), wasted-recovery in the gameover wait, rotation-aborts-on-new-coordinator-revert (atomic/retryable). All recoverable under honest governance. |
| **`claimTerminalDecimatorJackpot` no GO_SWEPT guard** | INFO | Documented forfeiture; doesn't strand the sinks. |

---

## Coverage / transparency notes
- **Cross-model:** every lead has ≥2 independent nets (Gemini, Codex, Claude NET-2) + orchestrator crux. **Codex was deferred on phase 423** (usage cap); 423 was carried by Gemini + NET-2 (2 rounds incl. refute) + crux. **Codex backfill for 423 is outstanding** (recommended when the cap resets).
- **Completeness critics earned their keep:** the 420 critic showed the inherited COLMAP-04 packed-slot flag-list under-counted the corruption surface by 8 slots (all re-derived from `forge inspect` and verified clean in round 2) — the v66 "under-counted catalog" lesson recurring; the 421 critic + NET-2 probes found MIDRNG-02 (council-missed).
- **Methodology:** re-deriving the call graph and storage layout from HEAD (417, 420-r2) rather than trusting an inherited catalog is the structural defense against confirmation convergence.

## Carried recommendations (non-blocking)
1. Codex backfill for 423.
2. Full `forge inspect DegenerusGame storageLayout` snapshot CI oracle (MECH-02 completion — diff against `417-game-storage-layout.json`).
3. Optional `:1843`/`:1850` `lootboxRngWordByIndex[index] == 0` fulfill-write guard (the re-roll LOW).
4. Optional 423 rotation-timer hardening (gate liveness off a non-rotation-resettable clock).

**Milestone audit verdict: the spinal column holds. 0 outstanding CAT/HIGH/MED; the one real MEDIUM and the one real LOW are fixed; all residuals are LOW/INFO/by-design.**
