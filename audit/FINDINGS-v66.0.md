# FINDINGS — v66.0 RNG-Surface & Cross-Contract-Call Manipulability Re-Audit (Cross-Model Council)

**Date:** 2026-06-16
**Subject (byte-frozen):** contract commit `42c8e9c6` / `contracts/` tree `0dd445a64cfe7e096427d44f058c40abb1233b5f`
(= origin/main `bb0912a6` + the additive `CurseChanged` indexer-parity emit). Tree verified intact after every fan-out.
**Method:** cross-model council (Gemini + Codex) as PRIMARY finder + Claude multi-agent workflows; every candidate adversarially verified.

## VERDICT

**0 CATASTROPHE / 0 HIGH / 0 MEDIUM. 0 real findings.**
Dispositions: **1 LOW** (by-design) · **2 BY-DESIGN** (USER-ruled) · **1 INFO** (by-design emergency tradeoff).
The RNG-freeze invariant and the full cross-contract composition surface hold across the re-derived consumer net.
No player-manipulable VRF outcome, no foreknowable payout, no cross-contract cycle disagreement was found.

## WHY THIS MILESTONE (the thesis)

The protocol's RNG had been audited 10+ times "clean." The risk this milestone targeted was **confirmation
convergence**: every prior pass re-derived its VRF-consumer net *from the same trusted catalog*, which turned out
to be a **stale, pre-rename snapshot**. A six-lens blind-spot panel (`.planning/v66-BLIND-SPOT-PANEL.md`) confirmed
the thesis up front, so v66 **re-derived the net from current HEAD** instead of inheriting it.

## HEADLINE RESULT

- **VRF-consumer net: 13 (catalog) → 72 (re-derived).** The catalog under-counted by ~5×.
- **The council earned its keep:** codex independently found **5 consumers the Claude net + Gemini both missed**
  (decimator jackpot ×2, daily + level quest rolls, deity-boon viewer) — files no Claude cluster had assigned. This
  is the cross-model premise paying off ([[cross-model-led-audits-over-claude-only]]).
- **9 stale anchors** reconciled: the catalog §12 "headline cross-day re-roll exploit" is already remediated (day-keyed
  redemption model); the v30 state-machine's third clear-site C-02 (`updateVrfCoordinatorAndSub rngLockedFlag=false`)
  is removed (rotation now KEEPS the lock + re-issues); `currentDayView()` cross-calls replaced by local `GameTimeLib`;
  every consumer line anchor off by tens-to-hundreds. The catalog + v30 docs are a historical SUBSET and are superseded
  by `.planning/v66-RNGNET-CONSUMER-NET.md`.

## FINDINGS & DISPOSITIONS (by phase)

### Phase 412 — Cross-contract freeze seams (RNGSEAM-01..05): all FREEZE-HOLDS
| Seam | Verdict | The gate that holds it |
|------|---------|------------------------|
| RNGSEAM-01 redemption `claimRedemption(player,day)` arg-selection | FREEZE-HOLDS | slot keyed by the burn's own `currentPeriod`; `D+1` provably undrawn at submit (no future-day word writer); single-pool sentinel |
| RNGSEAM-02 FLIP-escrow leg `getCoinflipDayResult(day+1)` | FREEZE-HOLDS | `day+1` result undrawn at submit, committed lock-step by the resolving advance; no packed-lane aliasing |
| RNGSEAM-03 BAF winner-set + `coinflipTopByDay` leaderboard | FREEZE-HOLDS | `isFarFuture && rngLockedFlag` revert + `level==X0` + `lastPurchaseDay` span the whole request→unlock window |
| RNGSEAM-04 stall gap-backfill correlation | FREEZE-HOLDS | freshness gates admit the burn only with the word drawn; the shared post-gap word creates no EV break |
| RNGSEAM-05 coordinator-rotation-while-locked | FREEZE-HOLDS | `rngLockedFlag` has exactly 2 writers (set `_finalizeRngRequest`, clear `_unlockRng`); rotation is neither; every branch reaches `_unlockRng` |

- **LOW (by-design):** `_awardDegeneretteDgnrs` reads a live `sdgnrs.poolBalance(Pool.Reward)` for the reward *amount*
  (the VRF *score* is frozen). The pool magnitude is a shared resource; this is a documented design property, not a
  freeze break.
- Both **council divergences** from Phase 411 resolved in codex's favor: `dailyHeroWagers` is protected by the day
  offset (bets affect a future resolution, not the now-resolving word); the sDGNRS day+1 redemption is pinned by the
  `BurnsBlockedBeforeDailyRng` submit gate. (Gemini's "open seam" framing conflated claim-time *knowability* with
  submit-time *steerability*.)

### Phase 413 — Input-selection grinding + gameover fallback (RNGSEL-01..03, RNGFALL-01)
- **RNGSEL-02 Degenerette index-keyed score → FREEZE-HOLDS.** The score seed omits betId/player, so the freeze rests
  entirely on the placement guard (`lootboxRngWordByIndex[activeIndex]!=0 ⇒ revert`). Exhaustive trace: **no word-set
  path coincides with an accepting placement at the active `LR_INDEX`** (across gap-backfill, mid-day retry, pre-increment).
  The panel's HIGH-if-real is **refuted**.
- **RNGSEL-03 first-mover / elective resolution → FREEZE-HOLDS.** The redemption seed is bound to a pre-written slot;
  no caller-chosen re-derivation; the whale-pass award is not capturably order-dependent.
- **RNGSEL-01 salvage address-selection → BY-DESIGN (USER-ruled).** Salvage is liquidity for otherwise-illiquid
  far-future tickets; the seed only moves the payout within 70–110% of an already-discounted, **sub-fair** amount —
  even max-roll is −EV vs holding (max offer 16.5% of face), so address-selection picks the least-bad point on a
  below-break-even curve. No protocol value extracted; the counterparty is always +EV (never drained below cost).
- **`_deityBoonForSlot` (carried from 411, net-flagged MUTABLE-INPUT) → BY-DESIGN (USER + code + V62 precedent).**
  `deity != recipient` (no self-boon), 3 fixed-type slots/day used-once, ≤1 boon per recipient per day, boon type a
  pure `keccak(rngWord,deity,day,slot)` with no re-roll. Foreknowing the public word only chooses which 3 distinct
  *others* receive the 3 fixed boons — the intended "bless whom you choose" power. No quality-grind, no self-enrichment.
- **RNGFALL-01 gameover prevrandao fallback → INFO (by-design emergency).** No *non-proposer* player can bias a
  fallback consumer via a controllable input; the only residual is the known 1-bit validator/proposer bias, which only
  occurs after **14 days of dead VRF** (an extreme emergency) and was re-confirmed safe under the reworked consumers.

### Phase 414 — Test-net closure (the real deliverable improvement, test-only): +10 tests
The audit's surfaced gaps were all in the *test suite*, not on-chain. All closed (contracts untouched):
- **MECH-01** — real un-mocked redemption claim-side seed test pins `rngWordForDay(day+1)`; the v62 REDEMPTION-ZERO-SEED
  class mutant (`day+1→day`) now FAILS (the prior suite mocked the word source and was blind).
- **MECH-02** — the `vm.skip`'d mid-day cross-day lootbox binding test un-skipped + rewritten to read storage; now runs.
- **MECH-03** — Coinflip RNG-spine behavioral net replaces the source-string occurrence check; full gambit mutation
  campaign on `processCoinflipPayouts`/`_storeDayResult`/`_dayResult` remains **CI-resumable**.
- **MECH-04** — `b >= 50` win-classification floor proven (`COINFLIP_EXTRA_MIN_PERCENT=78`; no win stores `b ∈ [2,49]`).

New forge baseline ≈ **899/0/109** (was 889/0/110; +10 tests, one skip removed, 0 regressions).

## METHOD ATTESTATION (COUNCIL-01 / COUNCIL-02)

- **COUNCIL-01 — council as primary finder:** Gemini + Codex ran over the RNGNET / RNGSEAM / RNGSEL / RNGFALL surfaces,
  seeded with the blind-spot-panel hypotheses. The council surfaced the 5 missed consumers and the 2 freeze divergences
  that shaped the 412/413 hunts. (Codex's terminal 412-proof challenge was rate-capped — non-blocking; the proofs +
  the in-phase council coverage stand. Re-run when quota resets if a third-party tie-break is wanted.)
- **COUNCIL-02 — adversarial verification:** every candidate finding went through independent refutation (3-lens
  correctness / state-ordering / economic-EV); a finding had to survive majority refutation to be recorded. None did —
  each resolved to FREEZE-HOLDS or BY-DESIGN with a cited gate.

## SUBJECT INTEGRITY

- One pre-freeze contract change: the USER-approved additive `CurseChanged(address indexed player, uint8 newCurseCount)`
  indexer-parity emit (`_applyCurseStack`/`_clearCurse` in `MintStreakUtils`, commit `42c8e9c6`). Proven inert: forge
  889/0/110 identical to v65, packed-bytes byte-identical, EIP-170 OK. Folded in before the freeze so the audit covers
  real shipping bytecode.
- Tree `0dd445a6` verified byte-frozen after every council/workflow fan-out.

## OPEN / CARRIED (non-blocking)
- Full gambit mutation campaign on the Coinflip + RNG spine — CI-resumable (per the v63/v64 precedent).
- Codex 412-proof challenge — re-runnable when its quota resets.

## CLOSURE
- Deliverables: this file (`audit/FINDINGS-v66.0.md`), `.planning/v66-RNGNET-CONSUMER-NET.md` (the net that supersedes
  the stale catalog), `.planning/v66-BLIND-SPOT-PANEL.md`, and the per-phase summaries under `.planning/phases/410..414`.
- All v66 commits are **LOCAL / UNPUSHED**; the `CurseChanged` emit + the full milestone await USER diff-review before push.
