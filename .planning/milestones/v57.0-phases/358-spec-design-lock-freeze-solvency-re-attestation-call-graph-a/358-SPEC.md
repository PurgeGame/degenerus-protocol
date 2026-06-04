# v57.0 Design-Lock SPEC (Phase 358)

**Milestone:** v57.0 — Small-Feature Bundle + Day-Type UDVT Refactor
**Baseline / frozen subject:** v56.0 closure HEAD — frozen contract subject `1e7a646d`, closure signal `MILESTONE_V56_AT_HEAD_1e7a646d44da4ee26375edd0b006274821fef73e`.
**Status:** LOCKED (design-lock COMPLETE — plan 01 authored the header + TDEC-02 + TDEC-03; plan 02 appended WWXRP-02 + BURNIE-03 + SALVAGE-02 + CANCEL-02; plan 03 appended the cross-cutting RNG-freeze + SOLVENCY re-attestation + the UDVT byte-preservation discipline + the Full Call-Graph Grep-Attestation + this SPEC Lock — see `## SPEC Lock (LOCKED)` for the per-criterion assertion).
**Owns (358 design-locks):** TDEC-02 (terminal-decimator mechanics, D-04..D-13) · TDEC-03 (freeze-safety proof, D-01..D-03) · WWXRP-02 (D-14..D-18) · BURNIE-03 (D-21..D-24) · SALVAGE-02 (D-25..D-29) · CANCEL-02 (D-30..D-33). UDVT-01/02/03 design-fed (D-19/D-20, built at IMPL 359).

> **PAPER-ONLY.** This phase locks design and grep-attests anchors. It mutates ZERO `contracts/*.sol`. No contract code is authored, no implementation bodies or fenced Solidity are inlined — every reference is an identifier + line range + behavior description, re-attested against the frozen subject before being written here.

### Frozen-Subject Guard

`git diff --quiet 1e7a646d HEAD -- contracts/` is **clean** (working-tree `contracts/` is byte-identical to the frozen subject `1e7a646d`). Therefore every `file:line` anchor cited in this SPEC — whether read from the working tree or via `git show 1e7a646d:<path>` — is read-equivalent to the frozen subject. No "by construction" claim survives un-grepped: each anchor below was re-attested at SPEC time and any line drift from the planning notes is corrected inline (see the `:106` `preRefundAvailable` reconciliation in TDEC-03 and the dual daily-word-write reconciliation `:1879` / `:1831`).

### Section Table of Contents (plans 01 / 02 / 03 fill in order)

| Section | Owner plan | Requirement |
|---------|-----------|-------------|
| `## TDEC-02 — Terminal-Decimator Boost Mechanics` | 01 (this) | TDEC-02 |
| `## TDEC-03 — Freeze-Safety Proof` | 01 (this) | TDEC-03 |
| `## WWXRP-02 — Degenerette Jackpot Whale-Halfpass` | 02 | WWXRP-02 |
| `## BURNIE-03 — Coin-Buy Ticket-Queue Critical Fix` | 02 | BURNIE-03 |
| `## SALVAGE-02 — sDGNRS Salvage Combo ETH/BURNIE Pawn-Shop` | 02 | SALVAGE-02 |
| `## CANCEL-02 — Manual-Cancel Auto-Claim / Auto-Evict Forfeit` | 02 | CANCEL-02 |
| `## UDVT — `type Day is uint24` Byte-Preservation Discipline` (design feed) | 03 | UDVT-01/02/03 |
| `## Cross-Cutting Freeze / Solvency Re-Attestation` | 03 | SEC design feed |
| `## Full Call-Graph Grep-Attestation (vs `1e7a646d`)` | 03 | SC5 |
| `## SPEC Lock` | 03 | all 8 SC |

---

## TDEC-02 — Terminal-Decimator Boost Mechanics (LOCKED — owned here; TDEC-01 built at IMPL 359)

> **TDEC-01 is owned at IMPL 359 — its design is FIXED here.** The IMPL authors a new `boostTerminalDecimator()` entrypoint on `DegenerusGameDecimatorModule` (router stub on `DegenerusGame`) under the shapes below. No contract code is written in this SPEC.

**Subject machinery (re-attested at `1e7a646d`):** the terminal decimator records each player's burn into a packed `TerminalDecEntry` via `recordTerminalDecBurn` (`DegenerusGameDecimatorModule.sol:693`), which freezes a `bucket` + `subBucket` on the first burn of a level (`:725-728`), accumulates a time-multiplied `weightedBurn` saturated at `uint88` (`:750-752`), and folds the weight into the aggregate `terminalDecBucketBurnTotal[keccak256(abi.encode(lvl, bucket, subBucket))]` (`:755`). At game-over, `runTerminalDecimatorJackpot(poolWei, lvl, rngWord)` (`:780`) draws winners from those aggregates pro-rata. The bucket is derived from the player's `playerActivityScore` via `_terminalDecBucket` (`:925-936`, range BASE=12 → MIN=2; a LOWER denominator = BETTER odds), and `subBucket = keccak256(player, lvl, bucket) % bucket` via `_decSubbucketFor` (`:559-570`). The deadline helper is `_terminalDecDaysRemaining` (`:939-950`, returns 0 once `currentDay >= purchaseStartDay + DEATH_CLOCK_DAYS`; DEATH_CLOCK_DAYS=120 for `level != 0`, IDLE_TIMEOUT=365 for `level == 0`).

The boost is a final-day weight-AND-bucket re-derivation that SCALES already-committed burn — it does not buy a new entry. Decisions D-04..D-13 below are IMPL-ready.

**D-04 — Window = LAST DAY ONLY.** The boost is admissible only in the final window. This is a GAME-DESIGN lever (distinct from the freeze gate) that forces "keep the streak alive to the END": a player burns EARLY (`recordTerminalDecBurn` requires `daysRemaining > 7`, the gate `if (daysRemaining <= 7) revert` at `:700-701`) and can only boost at the deadline day `purchaseStartDay + DEATH_CLOCK_DAYS` (level != 0 ⇒ +120; level 0 ⇒ +365 idle), which is still pre-`!liveness`. Without a last-day window a player could boost at a streak peak then go dormant — gap-reset cannot retroactively undo a past boost. The exact `daysRemaining` threshold (`== 0` vs `<= 1`) is **Claude's-discretion at IMPL** within this locked shape; cite the deadline helper `_terminalDecDaysRemaining:939-950`.

**D-05 — Bucket PROMOTION IN.** The boost re-derives the bucket from the player's LIVE `playerActivityScore(player)` (which now includes the kept-alive quest streak) via `_terminalDecBucket(...)` (`:925-936`). If the resulting denominator is STRICTLY LOWER than the frozen bucket (= better odds, since bucket range is 12→2 and a lower number is a smaller draw space), PROMOTE; otherwise keep the frozen bucket. Bucket is a function of ACTIVITY SCORE, not of weight — "boosted weight improves the bucket" resolves to "the live end-game activity/streak re-qualifies a better bucket", directly addressing the original "bucket frozen too early" problem.

**D-06 — Forced subBucket re-derive on promotion.** `subBucket = keccak256(player, lvl, bucket) % bucket` (`_decSubbucketFor:559-570`) is BUCKET-DEPENDENT. A promotion MUST re-derive `subBucket` — a kept old subBucket could exceed the new (smaller) denominator and never win. "Keep vs re-derive" is therefore SETTLED = re-derive. This is safe because all of it is committed before the RNG request (forward-reference to TDEC-03's future-day-word lemma).

**D-07 — Aggregate re-key (solvency conserved).** On promotion, MOVE the player's weighted contribution from `terminalDecBucketBurnTotal[keccak256(abi.encode(lvl, oldBucket, oldSub))]` to `[keccak256(abi.encode(lvl, newBucket, newSub))]` — REMOVE-from-old, ADD-to-new — so total aggregate weight is conserved and `runTerminalDecimatorJackpot`'s pro-rata shares still sum to the pool (SOLVENCY-NEUTRAL; weight-only, the BURNIE/ETH payout path is untouched). Cite the aggregate key `terminalDecBucketBurnTotal:755` (note it is `abi.encode`, NOT `abi.encodePacked`) + the resolver `runTerminalDecimatorJackpot:780`.

**D-08 — Weight scaling.** Multiply `weightedBurn` by `boostFactor(effectiveStreak)` with anchors streak 100 ⇒ 20×, streak 10 ⇒ 4×, and a 1× floor at streak 0. Candidate two-line curve (the calibration TARGET — exact constants are **Claude's-discretion at IMPL/GAS**): `factorBps = 10000 + 3000·s` for `s <= 10`; `factorBps = 40000 + (s − 10)·1778` for `10 < s <= 100`; cap 20× (200000 bps). The quest streak caps at 100 (`DegenerusGameMintStreakUtils.sol:251` `questStreakCapped = questStreak > 100 ? 100`). Headroom note: the existing time multiplier already caps at 20× at the deadline (`_terminalDecMultiplierBps:916`, `10000 + ((daysRemaining − 10)·190000)/110` → 20× at day 120), so base × time-mult (≤20×) × boost (≤20×) ≈ 400× base — see D-11 for the overflow policy.

**D-09 — Effective-streak source = `getPlayerQuestView(player).baseStreak`.** Validate the streak via `getPlayerQuestView(player)` (`DegenerusQuests.sol:1088`) — the EFFECTIVE streak with daily gap-reset + shields applied (the view previews streak decay: it zeroes the streak when missed days exceed available `streakShield`, `:1094-1100`). This is NOT the raw, spoofable, stored `playerQuestStates.streak`. `getPlayerQuestView` is a `view` (no mutation).

**D-10 — Double-count = KEEP BOTH LEVERS.** The quest streak ALREADY feeds burn-time weight: `DegenerusGameMintStreakUtils.sol:252` folds `questStreakCapped * 100` bps into the activity-score `bonusBps`, which drives BOTH the frozen bucket (`_terminalDecBucket`) AND the activity multiplier `multBps = BPS_DENOMINATOR + (bonusBps / 3)` at `DecimatorModule:710-712`. The final-day boost multiplies a base that ALREADY contains streak — this stacking is INTENTIONAL (it rewards early conviction AND sustained-to-the-end play). `playerActivityScore` is left UNTOUCHED — it is shared by other systems, so stripping streak from it has a large blast radius and is REJECTED.

**D-11 — Overflow = SATURATE uint88.** The boost clamps `weightedBurn` to `type(uint88).max`, matching the existing `recordTerminalDecBurn` behavior (`:750-752` `if (newWeighted > type(uint88).max) newWeighted = type(uint88).max`). The aggregate add stays consistent (the same saturated delta moves on a re-key under D-07).

**D-12 — Shields = READ-ONLY, no consume.** The boost reads the effective streak via the `view` (`getPlayerQuestView` already factors shields into whether the streak survived gaps); it CONSUMES NOTHING. Shields are still consumed naturally by the player's normal quest actions / `_questSyncState`.

**D-13 — Idempotence + prerequisite.** One-time per terminal level via a `boosted` bit added to the packed `TerminalDecEntry`. The packing has 24 spare bits — verified at `DegenerusGameStorage.sol:1585-1591`: `uint80 totalBurn / uint88 weightedBurn / uint8 bucket / uint8 subBucket / uint48 burnLevel` = 80+88+8+8+48 = **232 of 256 bits** (24 spare). The boost REQUIRES an existing terminal-dec burn for the current level (you scale committed weight, you do not buy an entry) — consistent with the lazy-reset on stale `burnLevel` at `:716-723`.

---

## TDEC-03 — Freeze-Safety Proof (LOCKED — the load-bearing re-proof under the bucket-promotion allowance)

> **TDEC-01 builds it; this proof is the SPEC's design gate.** SEC-01 (RNG-freeze) is OWNED empirically at TST 361; the bucket-promotion freeze is adversarially probed at TERMINAL 362. This section RIGOROUSLY DISCHARGES the future-day-word lemma — it does not assert it.

### Proof map (the discharge in one table)

| Step | Claim | Discharged by (anchors @ `1e7a646d`) |
|------|-------|--------------------------------------|
| 0 | Obligation = "all weight + bucket + subBucket mutation precedes the resolution word" (the `subBucket`-fixed simplification is dead under D-05 promotion) | USER framing (CONTEXT `<specifics>`); TDEC-02 D-05/D-06/D-07 |
| 1 | `require(!_livenessTriggered())` ALONE is the correct + sufficient gate (`!gameOver` was wrong) | `_livenessTriggered:1231-1240` (day-constant); `gameOver=true:145` flips AFTER the read `:106`/draw `:174` |
| 2 | Future-day-word lemma: `rngWordByDay[gameOverDay]` cannot exist before the gate closes | day-constant liveness ⇒ first advance routes to game-over `:591`/`:599-604`; word materialized fresh by `_gameOverEntropy:1289` (`:1295`); consumed `:106`→`:174` |
| 3 | The 2nd daily-word writer does not pre-write `gameOverDay` | `_backfillGapDays:1817` writes `gapDay < endDay` (current-day-EXCLUSIVE, `:1815`/`:1826`) |
| 4 | VRF-grace stall has no fallback-seed hole; `:106` guard drift reconciled | RNG-locked during stall; `handleGameOverDrain` reverts on word 0 `:107` (inside `preRefundAvailable != 0` `:104`) |
| 5 | The same-day-reuse refinement is internally inconsistent → RETRACTED | evening-liveness ⇒ morning-liveness ⇒ already routed; belt-and-suspenders `==0` gate recorded, default OFF |
| 6 | Pool finalized + shares sum to pool (D-07 conservation) | draw inside `handleGameOverDrain:172-183`; re-key conserves `terminalDecBucketBurnTotal:755` total → `runTerminalDecimatorJackpot:780` |

### Step 0 — Statement of the obligation

The original terminal-decimator design (`PLAN-TERMINAL-DECIMATOR-STREAK-BOOST.md`, weight-only) was freeze-safe under a `subBucket`-FIXED simplification: the bucket and subBucket were frozen on the first burn (`recordTerminalDecBurn:725-728`) and never changed, so the only mutable quantity was the within-bucket WEIGHT, and the validator could lean on "the bucket is immutable". TDEC-01 (D-05) now allows a bucket PROMOTION — a NEW write that changes BOTH the bucket AND the subBucket AND re-keys the aggregate (D-06/D-07). The `subBucket`-fixed simplification therefore NO LONGER HOLDS.

The correct freeze-safety argument is the GENERAL rule, per the USER framing (CONTEXT `<specifics>`): "if the number OR bucket was manipulable between the rng request and the decimator resolution that would violate the rules." So the obligation is:

> **ALL weight + bucket + subBucket mutation (the boost and any promotion) must provably precede the RNG word that determines the draw.** Promotion is NOT a special case — the standard pre-request freeze gate covers both weight and bucket.

The gap that matters is between the RNG REQUEST and the resolution, NOT between the rngWord reveal and the `gameOver` flip.

### Step 1 — Gate (D-01): `require(!_livenessTriggered())` ALONE is sufficient

`boostTerminalDecimator()` gates on `require(!_livenessTriggered())` (plus the idempotent `boosted` bit, an existing entry for the current terminal level, and a live effective streak from D-09). `_livenessTriggered` (`DegenerusGameStorage.sol:1231-1240`) is a DAY-CONSTANT predicate: it returns `true` for the death-clock path once `currentDay − purchaseStartDay > 120` (`level != 0`) or `> _DEPLOY_IDLE_TIMEOUT_DAYS` (`level == 0`), and `true` for the VRF-grace-stall branch once `block.timestamp − rngRequestTime >= _VRF_GRACE_PERIOD`.

The original `!gameOver` framing was the WRONG gate. `gameOver` flips only INSIDE the resolution (`handleGameOverDrain` sets `gameOver = true` at `GameOverModule:145`), AFTER the resolution word has already been read at `:106` and consumed by the decimator draw at `:174`. Gating on `!gameOver` would still permit a boost in the same block, after the word was revealed but before the flip latched — a real manipulation window. Gating on `!_livenessTriggered()` closes the window strictly earlier: the boost is only admissible while liveness is still false, i.e. BEFORE the day on which the game-over path can run at all. This is the timing buffer the original plan's caveat ("a variant that improves the BUCKET would need a hard timing buffer") demanded — the `!liveness` gate IS that buffer.

### Step 2 — The future-day-word lemma (D-02): the resolution word cannot exist before the boost gate closes

**Resolution read.** The decimator resolution reads `rngWord = rngWordByDay[day]` (`GameOverModule:106`) and feeds it into `runTerminalDecimatorJackpot(decPool, lvl, rngWord)` (`:174`, inside `handleGameOverDrain` reached from `:86`). Here `day` is the `gameOverDay` — the day liveness fires (e.g. `purchaseStartDay + 121` on the death-clock path). The word is keyed by the CURRENT processing day.

**The word for `gameOverDay` is written FRESH at game-over, never before.** On `gameOverDay` itself the day-index liveness predicate is already `true` from the day's start (it is day-constant — the inequality `currentDay − psd > 120` does not depend on intra-day timestamp). So the FIRST `advanceGame` of that day routes straight into the game-over path: `_handleGameOverPath` (`AdvanceModule:565`) checks `if (!_livenessTriggered()) return (false, 0)` (`:591`) — which now passes through — then, if `rngWordByDay[day] == 0` (`:599`), acquires the word via `_gameOverEntropy(...)` (`:600-604`) and proceeds to `handleGameOverDrain` (the delegatecall at `:665-670`). `_gameOverEntropy` (`:1289`) returns the existing word if present (`:1295 if (rngWordByDay[day] != 0) return rngWordByDay[day]`) or requests/derives one — so the `gameOverDay` word is materialized AT game-over, as part of the same routing that consumes it.

**Conclusion.** Any boost that passed `!_livenessTriggered()` necessarily executed on an EARLIER day (liveness was still false, so `currentDay − psd <= 120`), strictly before `gameOverDay` and therefore before the resolution word for `gameOverDay` could exist. The resolution word is ALWAYS a FUTURE-DAY word relative to any admitted boost. The boost + any promotion are deterministic from the player's fixed effective-streak factor (D-09, read from a `view`) × their committed burn — fixed BEFORE any randomness is revealed. The player cannot use draw knowledge to manipulate placement (bucket OR subBucket OR weight). ∎

**Worked timeline (death-clock path, `level != 0`, `purchaseStartDay = P`).**

- Days `P+1 .. P+120` — `currentDay − P <= 120` ⇒ `_livenessTriggered()` is FALSE. The boost is admissible. A player may call `boostTerminalDecimator()` on any of these days; it re-derives the bucket from the LIVE activity score, re-keys the aggregate, and scales `weightedBurn` — all writes commit now, with NO resolution word in existence (`rngWordByDay[P+121]` is unwritten).
- Day `P+121` — `currentDay − P = 121 > 120` ⇒ `_livenessTriggered()` is TRUE from the day's start. The boost gate `require(!_livenessTriggered())` now REVERTS — no further mutation possible. The first `advanceGame` of this day routes to `_handleGameOverPath` (`:591` passes), acquires `rngWordByDay[P+121]` fresh via `_gameOverEntropy` (`:600-604`), and `handleGameOverDrain` reads it (`:106`) and draws the decimator winners (`:174`).

The resolution word `rngWordByDay[P+121]` is born on day `P+121`, the exact day the boost becomes inadmissible. There is no day on which BOTH the boost is admissible AND the resolution word exists. The two windows are disjoint by the day-constant predicate.

### Step 3 — The dual daily-word-write reconciliation (the backlog/catch-up edge)

The planning note called `_applyDailyRng` (`AdvanceModule:1879`, `rngWordByDay[day] = finalWord`) "the only daily-word write". Grep at `1e7a646d` shows a SECOND write: `_backfillGapDays` (`:1831`, `rngWordByDay[gapDay] = derivedWord`). This is the exact backlog/catch-up surface D-03 worries about, so it is reconciled here explicitly rather than asserted away.

`_backfillGapDays(vrfWord, startDay, endDay, ...)` (`:1817`) backfills words for PAST gap days `for (gapDay = startDay; gapDay < endDay; ...)` — `endDay` is documented "Current day (exclusive — not backfilled, handled by normal path)" (`:1815`) and is capped at `startDay + 120`. So the gap backfill writes words for days STRICTLY BEFORE the current day; it NEVER pre-writes the word for the day the game-over path is currently processing. The `gameOverDay` word is always acquired by the fresh `_gameOverEntropy` path (Step 2), not lifted from a pre-set backfill slot. The future-day-word property holds for the resolution key regardless of the gap backfill: a boost admitted on day D (liveness false) cannot see the word for `gameOverDay > D`, and the backfill of intermediate gap days `< gameOverDay` does not write the `gameOverDay` key.

### Step 4 — The VRF-grace-stall branch (D-02)

`_livenessTriggered` also fires on the VRF-grace-stall branch (`Storage:1239-1240`, `rngRequestTime != 0 && block.timestamp − rngRequestTime >= _VRF_GRACE_PERIOD`). Handle it explicitly: during a stall the stalled day's word stays 0 and the game is RNG-LOCKED (no new daily words are written during the stall — `_applyDailyRng` runs only on VRF fulfillment). The decimator path requires a REAL VRF word: `handleGameOverDrain` reverts on `rngWordByDay[day] == 0` when funds are distributable (`:107 if (rngWord == 0) revert E()`, inside the `preRefundAvailable != 0` guard). So there is NO predictable-fallback-seed hole — the draw cannot proceed on a zero/derivable word.

**Reconcile the verified `:106` `preRefundAvailable != 0` guard drift.** At `1e7a646d` the `rngWord = rngWordByDay[day]` read at `:106` is INSIDE `if (preRefundAvailable != 0)` (`:104`), NOT unconditional — the planning note flagged this. Reconciliation: the decimator pool branch is `decPool = remaining / 10` with `remaining = available`, and the function early-returns `if (available == 0) return` (`:165`) BEFORE the decimator block (`:172-183`); `available` is the post-refund distributable, ≤ the pre-refund `preRefundAvailable` plus refunds-into-claimablePool... more simply: the decimator draw `runTerminalDecimatorJackpot(decPool, lvl, rngWord)` only runs when `decPool != 0`, which requires `available != 0`, which requires distributable funds exist — and whenever distributable funds exist the `:104` guard has populated `rngWord` (or reverted via `:107` if the word is 0). The guard does NOT weaken the lemma: (a) the future-day-word property is a property of the KEY `rngWordByDay[gameOverDay]` and holds regardless of whether the read is guarded; (b) when no funds are distributable the decimator draw is moot (no pool to place into / win from), so a `rngWord` of 0 in that case is harmless. Either way, no admitted boost ever observed the resolution word.

### Step 5 — The retracted same-day-reuse refinement (D-03)

An earlier "same-day rngWord reuse" concern — gate additionally on `rngWordByDay[currentDay] == 0` — was investigated and is RETRACTED as internally inconsistent. The scenario it imagined (a pre-set word for the day game-over processes) cannot arise on the normal path: for liveness to be true in the evening it was already true that morning (the day-constant predicate, Step 2), so any "normal advance" that morning would ALREADY have routed to the game-over path — there is no separate, earlier, pre-set word for `gameOverDay`. Step 3 confirms the only other writer (`_backfillGapDays`) writes strictly-earlier days, not `gameOverDay`.

**Belt-and-suspenders fallback (recorded, default OFF).** IF a later formal/empirical pass surfaces a genuine backlog/catch-up edge in which the game-over path processes a day whose word was PRE-SET by some other writer, the cheap mitigation is to AND-in a `rngWordByDay[resolutionDay] == 0` gate at the boost. The default per USER is `!_livenessTriggered()` ALONE. **Conclusion of this formal pass: NO such edge surfaced** — Step 2 (day-constant liveness ⇒ fresh game-over-day word) + Step 3 (gap backfill is current-day-exclusive) close it. The fallback is documented for the IMPL author as a known cheap escape hatch, NOT a required gate.

### Step 6 — Invariant re-attestation

- **`!_livenessTriggered()` / pre-request gate** (D-01) — re-attested as the correct and sufficient freeze gate; supersedes the obsolete `!gameOver` framing.
- **Pool finalized in the resolution tx** — the decimator pool `decPool = remaining / 10` is computed and drawn inside `handleGameOverDrain` (`:172-183`), in the same tx as the `gameOverDay` word read; no boost runs after that tx (liveness is true, the boost gate is closed).
- **Shares sum to the pool** (D-07 conservation) — the aggregate re-key on promotion REMOVES the weighted contribution from the old key and ADDS the identical amount to the new key (cross-reference TDEC-02 D-07), so `terminalDecBucketBurnTotal` total weight is conserved and `runTerminalDecimatorJackpot`'s pro-rata shares (`:780`) still sum to `decPool`. SOLVENCY-neutral, weight-only; the ETH/BURNIE payout path is byte-untouched.

The terminal-decimator boost + bucket promotion are FREEZE-SAFE and SOLVENCY-NEUTRAL. The proof rests on the future-day-word lemma (all weight/bucket/subBucket mutation provably precedes the resolution word), not on any "by construction" assertion.

### Step 7 — Threat-register mapping (what 361/362 must verify)

This proof discharges, on paper, the two load-bearing TDEC threats; TST 361 and TERMINAL 362 verify them empirically/adversarially against the frozen subject.

| Threat | Claim | Proof step | Verified at |
|--------|-------|-----------|-------------|
| T-358-01 (Tampering — RNG/freeze) | A boost or bucket-promotion timed to exploit draw knowledge is impossible | Steps 1–3 (gate + future-day-word lemma + dual-write reconciliation) | TST 361 SEC-01 (determinism); 362 adversarial (bucket-promotion freeze) |
| T-358-02 (Tampering — RNG) | No predictable-fallback-seed hole on the VRF-grace stall | Step 4 (RNG-locked stall + revert-on-zero `:107`) | TST 361 SEC-01; 362 adversarial |
| T-358-03 (Tampering — solvency-of-shares) | Aggregate re-key on promotion conserves total weight | Step 6 (D-07 conservation) | cross-cutting solvency section (plan 03); TST 361 SEC-02 |

### Step 8 — IMPL handoff invariants (carried into TDEC-01 @ 359)

The IMPL author MUST preserve these as code-level invariants (re-proven at TST 361):

1. The boost gate is EXACTLY `require(!_livenessTriggered())` (NOT `require(!gameOver)`) plus the `boosted`-bit / existing-entry / live-streak preconditions. Do not relax to `!gameOver`.
2. The bucket promotion + subBucket re-derive + aggregate re-key are a single atomic in-tx mutation, committed under the gate (no deferred / two-phase placement that could straddle the resolution).
3. The re-key REMOVES the exact pre-boost weighted contribution from the old aggregate key and ADDS the post-boost weighted contribution to the new key — net conservation of `terminalDecBucketBurnTotal` total weight (D-07).
4. The boost reads the effective streak via the `view` `getPlayerQuestView` only (D-09/D-12 — no mutation, no shield consume).
5. The `boosted` bit makes the boost one-time per terminal level (D-13); a second call is a no-op / revert, never a second scaling.

These invariants are the design gate; the empirical byte-diff + determinism proofs are owned at TST 361 (SEC-01) and the adversarial bucket-promotion probe at TERMINAL 362.

---

## WWXRP-02 — Degenerette Jackpot Whale-Halfpass (LOCKED — design half; WWXRP-01 built at IMPL 359)

> **WWXRP-01 is owned at IMPL 359 — its design is FIXED here.** The IMPL hooks a small award into the existing per-spin loop of `_resolveFullTicketBet` (`DegenerusGameDegeneretteModule.sol:614`) + appends one new mapping to `DegenerusGameStorage`. No contract code is written in this SPEC; anchors + behavior only.

**Subject machinery (re-attested at `1e7a646d`).** All Degenerette resolve entrypoints funnel through the shared `_resolveFullTicketBet` (`:614`): the public `resolveBets:407` (no access modifier — permissionless) and the router stubs `DegenerusGame.resolveDegeneretteBets:902` / `degeneretteResolve:1742` / `_degeneretteResolveBet:1900`. Per spin the loop computes the score `s = _score(...)` at `:674` (S = A + 2·H, S ∈ {0..9}), pays out, and on a high ETH bet awards sDGNRS from the Reward pool in the `if (currency == CURRENCY_ETH && s >= 7)` block at `:713-715`. The owner is resolved up-front by `_resolvePlayer:142-150` (returns `msg.sender` for the zero sentinel, else `_requireApproved(player)` then the owner). Currency tags `CURRENCY_WWXRP = 3` `:216`, `MIN_BET_WWXRP = 1 ether` `:225`. The whale-pass grant primitive is the cheap `whalePassClaims[player] += 1` (`DegenerusGameStorage.sol:973`; conversion in `DegenerusGamePayoutUtils.sol`; materialized by the existing `claimWhalePass` future-ticket deferral). There is NO existing WWXRP-jackpot state.

**Decisions D-14..D-18 below are IMPL-ready.**

**D-14 — Rationing = GLOBAL PER BRACKET.** ONE pass per `level/10` bracket total, to whoever lands the FIRST WWXRP jackpot in that bracket; later jackpots in the same bracket award nothing. New state: `mapping(uint256 => bool) wwxrpJackpotWhalePassBracketAwarded` keyed by `level/10`, appended to `DegenerusGameStorage` in the slot region after `whalePassClaims:973` / `lootboxEthBase:977` (no existing WWXRP state — a clean append). This SUPERSEDES the old `PLAN-WWXRP-JACKPOT-WHALEPASS.md` global `0→5` lifetime cap; that plan's `matches == 8` is the relabeled `s == 9` in current code.

**D-15 — Multi-bracket allow.** A single player CAN collect passes across different brackets — naturally rationed by the per-bracket flag (the flag is keyed by bracket, not by player, so one player winning bracket 0 does not preclude them winning bracket 1).

**D-16 — Recipient = the bettor `player`.** The pass always accrues to the bet OWNER. `_resolveFullTicketBet`'s `player` parameter is always the owner — `_resolvePlayer:142-150` validates `operatorApprovals[player][msg.sender]` (via `_requireApproved`) then returns the owner; the operator address (`msg.sender`) is NOT in scope at the award site. Permissionless resolve is fine: `resolveBets:407` (no access modifier) + the router stubs all funnel through the shared `_resolveFullTicketBet`, so the award path is identical regardless of who triggers the resolve, and it always credits `player`. (Threat T-358-07 — operator-redirect — is closed by construction at the award site.)

**D-17 — Hook + gate.** Hook at `_resolveFullTicketBet` IMMEDIATELY AFTER the ETH-only `s >= 7` sDGNRS block (`:713-715`). Gate: `s == 9 && currency == CURRENCY_WWXRP (3) && amountPerTicket >= MIN_BET_WWXRP (1 ether) && !wwxrpJackpotWhalePassBracketAwarded[level/10]`. The `s == 9` jackpot check short-circuits FIRST (1-in-10M) → zero added cost on non-jackpot spins (the common case reads no new state). On a hit: award `whalePassClaims[player] += 1` directly (the cheap freeze-safe grant — skips the ETH→halfpass conversion path), set `wwxrpJackpotWhalePassBracketAwarded[level/10] = true`, and emit an event. (Note the existing ETH sDGNRS block at `:713-715` is `currency == CURRENCY_ETH`-gated; the WWXRP award is a distinct currency/score gate that cannot collide with it.)

**D-18 — Freeze-safe + pre-liveness + SOLVENCY-neutral.** The award writes ONLY an RNG-INSENSITIVE counter (`whalePassClaims[player]`) + flag (`wwxrpJackpotWhalePassBracketAwarded[level/10]`), gated by the already-committed `s == 9` (deterministic from the committed daily `rngWord` — the player cannot retime/grind it after the request). It reuses the `claimWhalePass` future-ticket deferral → NO ETH / `claimablePool` touch (SOLVENCY-neutral). It only fires pre-liveness anyway: `resolveBets` reverts on `_livenessTriggered()` at `:413` (the same guard that protects whale-pass claims from crediting out of the already-distributed game-over residual). See the cross-cutting freeze/solvency re-attestation (plan 03).

**Anchor drift reconciled (vs the planning notes).** Two line-numbers in the CONTEXT/PLAN drifted from the frozen subject and are corrected here: (1) the ETH-only sDGNRS block is at `:713-715`, NOT `:710-715`; (2) the liveness revert in `resolveBets` is at `:413`, NOT `:414`. Both re-grepped at `1e7a646d`.

---

## BURNIE-03 — Coin-Buy Ticket-Queue Critical Fix (LOCKED — design half; BURNIE-01/02 built at IMPL 359; highest severity in the bundle)

> **BURNIE-01/02 are owned at IMPL 359 — their design is FIXED here.** This is the highest-severity item in the bundle: a live BURNIE-coin purchase entrypoint burns the coin but queues ZERO tickets (a direct loss-of-funds). No contract code is written in this SPEC; anchors + behavior only.

**D-21 — The verified bug.** `_purchaseCoinFor` (`DegenerusGameMintModule.sol:887-907`) calls `_callTicketPurchase(buyer, ticketQuantity, MintPaymentKind.DirectEth, true [payInCoin], bytes32(0), 0, level, jackpotPhaseFlag)` as a bare STATEMENT and DISCARDS all four returns. Inside `_callTicketPurchase` the `payInCoin` branch (`:1545-1555`) burns the coin (`_coinReceive(buyer, coinCost)` `:1548` → `coin.burnCoin` at `_coinReceive:1652-1653`) and only accumulates `burnieMintUnits` — it NEVER calls `_queueTicketsScaled`. So the BURNIE buy burns the coin and queues ZERO tickets: a pure token sink, a direct loss of funds on a LIVE entrypoint (`DegenerusGame.purchaseCoin:660`, consumed by `DegenerusVault.gamePurchaseTicketsBurnie:571-574`). Root cause: phase-160 commit `24f0898b` ("handlePurchase + compute-once score") moved `_queueTicketsScaled` out of `_callTicketPurchase`'s shared tail into the ETH-only `_purchaseForWith` queue site (`:1251`). **DECISIVE grep at `1e7a646d`:** `_queueTicketsScaled` (defined `DegenerusGameStorage.sol:612`) has EXACTLY TWO callers — `MintModule:1251` (the ETH purchase path, inside `_purchaseForWith:1036`) and `GameAfkingModule:800` — NEITHER reachable from the coin path. (The vault/sDGNRS init loop `DegenerusGame:226` uses the UN-scaled `_queueTickets`, also not coin-reachable; this corrects the planning note's "three `_queueTicketsScaled` callers incl. DegenerusGame:226" — that third site is `_queueTickets`, a different function.)

**D-22 — BURNIE-01 fix = QUEUE ON RETURN.** In `_purchaseCoinFor`, CAPTURE `_callTicketPurchase`'s returns (it already returns the adjusted quantity that the ETH path uses) and `if (adjustedQty != 0) _queueTicketsScaled(buyer, targetLevel, adjustedQty, false);` — restoring the pre-160 BURNIE→ticket behavior (the same `_queueTicketsScaled(..., false)` shape the ETH path uses at `:1251`).

**D-23 — BURNIE-02 fix = MINT_BURNIE quest credit as a BURN REBATE.** Restore the MINT_BURNIE quest credit on the coin path via `quests.handlePurchase`'s MINT_BURNIE leg ONLY: pass `ethMintSpendWei = 0`, `lootBoxAmount = 0` (the call site is `MintModule:1210-1217`), so it deliberately SKIPS activity-score / `recordMint`, affiliate, and non-mint quests (correct for BURNIE). The reward is a BURN REBATE, NOT a separate `creditFlip`: REQUIRE the player to afford the FULL ticket cost upfront, DEFER the burn until after `handlePurchase` returns, then burn net = full `coinCost` − MINT_BURNIE reward (floored at 0). The rebate can therefore NEVER enable a buy the player could not otherwise complete (eligibility is the full cost; T-358-09 closed). CO-DESIGN with BATCH-01 (which makes `handlePurchase` RETURN `burnieMintReward` instead of crediting it inline at `DegenerusQuests.sol:947-949`): the coin caller takes the RETURNED reward and nets it against the burn, whereas the ETH caller folds the returned `questReward` into `lootboxFlipCredit` (`MintModule:1220` → single credit `:1355`). **PRODUCER-BEFORE-CONSUMER obligation (load-bearing):** the reward must be KNOWN before the net burn, so the burn is DEFERRED until after `handlePurchase` returns — but the full-cost affordability check stays UPFRONT (before any of it runs). Today the burn happens INSIDE `_callTicketPurchase` (`:1548`) before `handlePurchase` is called by the caller, so BURNIE-02 must reorder: gate-on-full-cost → run `handlePurchase` (MINT_BURNIE leg) → burn net. This producer→consumer reordering is the sequencing the IMPL must implement; it is fixed here.

**D-24 — Freeze / solvency framing (posture-widening FLAGGED).** RNG-freeze UNAFFECTED: `purchaseCoin` reads no `rngWord` (`_purchaseCoinFor` is gated by `_livenessTriggered()` at `:891` + `gameOverPossible` at `:895`). SOLVENCY: the ETH / `claimablePool` DEBIT code stays BYTE-UNCHANGED, BUT this RESTORES ticket claims on the ETH prize pools (the intended pre-160 design) — a GENUINE FUNCTIONAL FIX, not a no-op-on-pools change. No unbacked obligation: ticket wins stay pro-rata from the AVAILABLE pool, and BURNIE pays no ETH INTO pools, so the restoration must keep `claimablePool <= balance` (the restored claims dilute existing ticket holders pro-rata rather than over-promising). The posture-widening (a functional behavior change, vs the bundle's other weight-only/annotation items) is FLAGGED — forward-ref the cross-cutting SEC-02 framing in plan 03. HYG-03 (361) adds the positive test (coin buy → tickets queued) + fixes the 3-arg `purchaseCoin` test drift + the unenforced "blocked when RNG locked" docstrings.

**Anchor drift reconciled (vs the planning notes).** The planning note cited "three `_queueTicketsScaled` callers (incl. `DegenerusGame:226`)"; the decisive grep at `1e7a646d` shows only TWO `_queueTicketsScaled` callers (`MintModule:1251`, `GameAfkingModule:800`) — `DegenerusGame:226` is the UN-scaled `_queueTickets` (vault/sDGNRS init), a different function. The conclusion (no coin-path queue caller) is UNCHANGED and in fact stronger. The payInCoin branch spans `:1545-1555` (the planning's `:1545-1554` is within range). All other BURNIE anchors confirmed exactly: `_purchaseCoinFor:887-907`, `purchaseCoin:880`/router `:660`, `gamePurchaseTicketsBurnie:571-574`, `handlePurchase` call `:1210-1217` / return-fold `:1220` / single credit `:1355`, BATCH-01 inline `creditFlip(player, burnieMintReward)` `DegenerusQuests.sol:947-949`, `_ethToBurnieValue:1657`, root-cause `24f0898b`.

---

## SALVAGE-02 — sDGNRS Salvage-Swap Combo ETH/BURNIE Pawn-Shop Payout (LOCKED — design half; SALVAGE-01 built at IMPL 359, SALVAGE-03 proven at TST 361)

> **SALVAGE-01 is owned at IMPL 359, SALVAGE-03 (the no-arb re-proof) at TST 361 — the design is FIXED here.** This is the ETH/solvency-path + RNG-reading item: it splits the existing far-future-salvage cash leg into a combo ETH/BURNIE "pawn-shop" payout. No contract code is written in this SPEC; anchors + behavior only.

**D-25 — Current structure (re-attested at `1e7a646d`).** `DegenerusGame.sellFarFutureTickets(player, levels[], quantities[], queueIndices[])` `:2074` → delegate → `DegenerusGameMintModule.sol:929`. Gated by `if (rngLockedFlag) revert RngLocked()` + `if (gameOver) revert E()` + `if (_livenessTriggered()) revert E()` (`:935-937`). Quote/jitter in `DegenerusGameMintStreakUtils.sol._quoteFarFutureSwap:145-190`: `seed = keccak(player, rngWordByDay[_simulatedDayIndex() - 1])` (the SETTLED prior-day word, `:160-163`), `jitterMult = 7000 + (seed % 4001)` ∈ [70%,110%] (`:165`), `ticketShareBps = 4000 + ((seed >> 128) % 4001)` ∈ [40%,80%] → cash ∈ [20%,60%] = the eth/cash cap (`:166`); it returns the four named values `(totalFaceWei, totalBudget, ticketWei, cashWei)` with `cashWei = totalBudget − ticketWei` (`:190`). Payout = ticket leg (`ticketWei` → current-level tickets via `_purchaseFor(player, qty, 0, bytes32(0), MintPaymentKind.Claimable)` `:983`) + cash leg (`cashWei` → ETH in `claimableWinnings[player]`). ETH source = the pool-neutral SDGNRS relabel `claimableWinnings[ContractAddresses.SDGNRS] -= totalBudget; claimableWinnings[player] += totalBudget` (`:976-977`), guarded by the `>=1 ETH` SDGNRS floor `if (claimableWinnings[SDGNRS] < totalBudget + 1 ether) revert E()` (`:958`). Helpers: `_ethToBurnieValue(amountWei, mintPrice())` (`:1657`, `= amountWei·PRICE_COIN_UNIT/priceWei`), `coinflip.creditFlip`. The distance fraction is `_farFutureFractionBps:127-130`. There is NO existing BURNIE leg.

**D-26 — SALVAGE-01 design.** Split the cash leg `cashWei` into an ETH part + a BURNIE part. Randomize a TARGET BURNIE portion full-range `[0 .. cashWei]` from a NEW slice of the existing prior-day `seed` (no new VRF — a third derived bit-slice alongside `seed % 4001` and `(seed >> 128) % 4001`); `ethCap` = the existing cash ≤60%-of-`totalBudget` limit (so ETH out ≤ `cashWei` ≤ cap ALWAYS; the BURNIE part is NOT counted against the eth-% cap). The BURNIE leg is paid from sDGNRS-OWNED BURNIE — NOT a `creditFlip` mint: the sources are (a) sDGNRS's BURNIE TOKEN balance (`burnie.balanceOf(ContractAddresses.SDGNRS)`, moved via `BurnieCoin.transfer:315` / `transferFrom:329`) and (b) sDGNRS's claimable coinflip credit (`coinflipAmount(SDGNRS):934` / `previewClaimCoinflips:927`, consumed like the existing sDGNRS redemption-settle stake-consume at `BurnieCoinflip:904-912` / `consumeCoinflipsForBurn:366` `onlyBurnieCoin`), valued via `_ethToBurnieValue(part, mintPrice())` `:1657` at the current eth-equivalent. **FUNDING FALLBACK:** `actualBurnie = min(targetBurnie, sDGNRS-available)`; pay `actualBurnie` from sDGNRS-owned BURNIE and the REMAINDER (`cashWei − actualBurnie`) as ETH. If sDGNRS has ZERO BURNIE + ZERO claimable coinflip → no BURNIE leg, pay the WHOLE cash leg in ETH (the current behavior). Always cap-compliant: `ethOut = cashWei − actualBurnie ≤ cashWei ≤ ethCap`. The ticket leg is UNCHANGED. Update BOTH the execute path (`MintModule:929` / the relabel `:976-977`) AND the preview/quote (`_quoteFarFutureSwap`) — the preview MUST reflect source-availability + fallback so the offer stays truly knowable-in-advance. **LOCK the exact sDGNRS-owned-BURNIE primitive:** `transfer`/`transferFrom` for the token balance; the `consumeCoinflipsForBurn`-style claim for the claimable stake; plus the availability READ (`balanceOf(SDGNRS)` + `coinflipAmount(SDGNRS)`) and the ETH fallback.

**D-27 — The "pawn-shop" safety model (load-bearing).** The salvage makes a VARIABLE, KNOWABLE-IN-ADVANCE offer — total value AND the ETH/BURNIE split may differ (even intra-day across bundles/timing). It is NOT value-neutral (the earlier value-neutral framing is DROPPED). The SOLE non-exploitability property is the TOTAL PAYOUT CAP (the existing no-arb ceiling) + the eth-% cap: every reachable offer — across all seed × bundle × split × timing — sits ≤ the cap, so there is NO extraction above it regardless of how the player optimizes, even though the offer is fully predictable. Suboptimal players forfeit EV to the protocol/pools (captured by everyone else — INTENDED game design, not a leak). Claude's-discretion within-day-variability latitude: the IMPL MAY mix an optional within-day component (bundle composition is already one; an optional block/nonce slice) into the seed AS LONG AS every offer stays previewable + ≤ the no-arb ceiling + the eth-% cap; the randomness SOURCE stays the settled prior-day word — NO new VRF.

**D-28 — Freeze framing.** Freeze-safe by the EXISTING accepted pattern — the offer is a transparent function of the SETTLED prior-day word (`rngWordByDay[_simulatedDayIndex() − 1]`) under the `rngLockedFlag` gate (the v48 jitter already works exactly this way at `:160-166`); the new ETH/BURNIE split is one MORE derived slice of the same seed → NO new VRF, NO new manipulable freeze surface. Non-exploitability rests on the cap (D-27), not on unpredictability. SEC-01 (361) covers it empirically.

**D-29 — Solvency framing + no-arb re-proof obligation.** SOLVENCY-positive/neutral + NO new BURNIE emission. Only the ETH part (`cashWei − actualBurnie`) is relabeled out of `claimableWinnings[SDGNRS]` (`:976`) — and that ETH part is ≤ the full `cashWei`, so the ETH liability the SDGNRS relabel creates DROPS vs today (`claimablePool <= balance` continues to hold, and the `>=1 ETH` floor `:958` still gates). The BURNIE part is a TRANSFER of sDGNRS-OWNED BURNIE (token balance and/or its claimable coinflip stake) to the player — NO `creditFlip` mint, NO inflation. The source-availability check + ETH fallback (D-26) guarantee the swap never over-draws sDGNRS's BURNIE and stays cap-compliant (T-358-12). **LOCK the load-bearing obligation owned at SALVAGE-02 (verified at SALVAGE-03):** EXTEND `test_SWAP08_NoArbAtCeiling_SweepAllDistances` (`test/fuzz/FarFutureSalvageSwap.t.sol:168`) so the MAX reachable offer still sits below the far-ticket acquisition floor across the FULL split range + the BURNIE-source valuation + the fallback path. Since the split conserves the cash-leg VALUE (it changes the form/source only), the total-value ceiling is mathematically unchanged — but the proof MUST cover the full split range, the `_ethToBurnieValue` BURNIE-source valuation, and the zero-available fallback.

**Flag:** SALVAGE-01 owned at IMPL 359, SALVAGE-03 at TST 361 — design fixed here.

**Anchor drift reconciled (vs the planning notes).** The SDGNRS relabel ASSIGNMENT pair is at `:976-977` (`-= totalBudget` / `+= totalBudget`); the planning's `:975-977` includes the leading comment line `:975`. `_quoteFarFutureSwap` already returns `cashWei` as a fourth named value (`:190`) — the planning's "`cashWei = totalBudget − ticketWei`" is computed there, not at the call site. All other SALVAGE anchors confirmed exactly: `sellFarFutureTickets:929`/router `:2074`, the gates `:935-937`, the SDGNRS floor `:958`, `_purchaseFor(...Claimable):983`, `_quoteFarFutureSwap:145-190` (seed `:160-163`, jitter `:165`, ticketShareBps `:166`), `_farFutureFractionBps:127-130`, `_ethToBurnieValue:1657`, `mintPrice:2539`, the BURNIE-source primitives (`previewClaimCoinflips:927`, `coinflipAmount:934`, `consumeCoinflipsForBurn:366`, the sDGNRS stake-consume `:904-912`, `creditFlip:859`, `BurnieCoin.transfer:315`/`transferFrom:329`), and the no-arb test `SWAP08:168`.

---

## CANCEL-02 — Manual Sub-Cancel Auto-Claim + Auto-Evict Pure-Forfeit (LOCKED — design half; CANCEL-01 built at IMPL 359, CANCEL-03 proven at TST 361)

> **CANCEL-01 is owned at IMPL 359, CANCEL-03 (the loss-race proof) at TST 361 — the design is FIXED here.** This is the CLEAN original-v57 posture (BURNIE-emission only, OFF the ETH path, `rngLock`-gated — unlike BURNIE/SALVAGE): it fixes a latent loss-of-funds race and makes the cancel-vs-evict asymmetry explicit. No contract code is written in this SPEC; anchors + behavior only.

**D-30 — The latent loss bug it fixes.** Manual cancel (`GameAfkingModule.sol:345-362`, the `if (dailyQuantity == 0)` branch of `subscribe`) calls `_finalizeAfking` (`:353` → `_finalizeAfking:1026`) and writes the `c.dailyQuantity = 0` tombstone (`:354`) but LEAVES `pendingBurnie` + `affiliateBase` in the slot. A docstring (`:348-351`) promises the sub "pulls its earned BURNIE via `claimAfkingBurnie` whenever" — BUT the next `processSubscriberStage` reclaim does `delete _subOf[player]` at `:1148` (the tombstone-reclaim path, after a guarding `_finalizeAfking`), wiping BOTH accumulators. So the accruals are LOST if any advance runs the reclaim before the player (+ an affiliate caller) claim. **The "claim whenever" comment is FALSE** (the reclaim is permissionless and advance-driven, not gated on the sub having claimed); the auto-claim closes the race (T-358-13).

**D-31 — CANCEL-01 manual-cancel auto-claim.** On manual cancel, BEFORE clearing: (a) pay the canceller's `pendingBurnie` to THEMSELVES via `coinflip.creditFlip` + the presale-box-credit parity (mirror `claimAfkingBurnie:1560` — zero the field FIRST, CEI: `s.pendingBurnie = 0` then `creditFlip(player, owed * 1 ether)`, with the `presaleBoxCredit` grant while `!presaleOver`); (b) drain `affiliateBase` + settle the affiliate tree A/U1/U2 = 75/20/5 (mirror `DegenerusAffiliate.claim:629` via `drainAffiliateBase:1605` — the AFFILIATE-only read-and-zero `base = s.affiliateBase; s.affiliateBase = 0`; A = the canceller's REFERRER — the base is owed UPLINE, NOT to the canceller — resolved by `_referrerAddress:809`; the split is the documented 75/20/5 winner-takes-all roll, `u1Share = (sumB − skipU1)·20/100`, `u2Share = (sumB − skipU2)·5/100`, remainder floored to A; deterministic, no extra roll); (c) `_finalizeAfking` + clear (delete the slot). Order matters: claim self + drain-to-tree, THEN finalize+clear.

**D-32 — CANCEL-01 auto-evict = pure FORFEIT.** Auto-evict (pass-expiry `:1175-1186`, funding-out `:1245`, tombstone-reclaim `:1148`) stays "just delete the data" — delete the Sub record incl. BOTH accumulators, NO payout to self OR uplines. Make the forfeit EXPLICIT: today the pass-expiry / funding-out evict paths `_finalizeAfking` + `sub.dailyQuantity = 0` + `_removeFromSet` but leave `_subOf` claimable OUT-OF-SET (a latent inconsistency — the slot stays addressable with live `pendingBurnie`/`affiliateBase` while no longer in the active set); the forfeit intent means they MUST wipe the accruals (`delete _subOf[player]`, as the tombstone-reclaim path already does at `:1148`) so the residue is truly UNCLAIMABLE post-evict (T-358-14). (USER accepted that auto-evict denies innocent uplines their share — the distinction is chose-to-leave vs got-kicked.)

**D-33 — CANCEL freeze / solvency (the clean posture).** BURNIE-emission only (`creditFlip` / `drainAffiliateBase`); reads no `rngWord`; no ETH / `claimablePool` touch (SOLVENCY-01 untouched — the afking funding ledger is separate from the cancel/evict accumulators). Cancel is `rngLock`-gated at the `subscribe` entry (`if (rngLockedFlag) revert RngLocked()` `:300`, which the docstring at `:256-257` confirms covers ALL of create/replace/cancel). CEI throughout (zero before credit, per the `claimAfkingBurnie:1574` mirror). No new freeze surface — this is the clean original-v57 posture (unlike the BURNIE/SALVAGE functional-solvency exceptions).

**Flag:** CANCEL-01 owned at IMPL 359, CANCEL-03 at TST 361 — design fixed here.

**Anchor drift reconciled (vs the planning notes).** `_referrerAddress` is at `:809` (the planning's `:809-815` is the function body span). The funding-out evict tombstone is at `:1245` (within the planning's `:1226-1252` range). `Sub.affiliateBase`/`pendingBurnie` are the packed `uint32` fields at `:1952`/`:1960` (within the planning's `:1946-1952`/`:1953-1960` docstring+field spans). All other CANCEL anchors confirmed exactly: manual cancel `:345-362` (FALSE comment `:348-351`, `_finalizeAfking` call `:353`, tombstone `:354`), `subscribe` `rngLock` gate `:300`, `_finalizeAfking:1026`, tombstone-reclaim `delete _subOf` `:1148`, pass-expiry evict `:1175-1186`, `claimAfkingBurnie:1560` (CEI `:1574`), `drainAffiliateBase:1605`, `DegenerusAffiliate.claim:629` (75/20/5), `creditFlip:859`.

---

## Small-Feature Anchor Re-Attestation Summary (vs `1e7a646d`)

Every `file:line` cited in the four sections above was re-grepped against the frozen subject before being written. The table consolidates the load-bearing anchors + the corrections (no "by construction" survives un-grepped).

| Feature | Anchor | Status @ `1e7a646d` |
|---------|--------|---------------------|
| WWXRP-02 | `_resolveFullTicketBet:614`, score `s:674`, `_resolvePlayer:142-150`, `resolveBets:407` | confirmed |
| WWXRP-02 | ETH-only `s>=7` sDGNRS block | **DRIFT** — `:713-715`, NOT `:710-715` |
| WWXRP-02 | liveness revert in `resolveBets` | **DRIFT** — `:413`, NOT `:414` |
| WWXRP-02 | `CURRENCY_WWXRP=3:216`, `MIN_BET_WWXRP=1 ether:225`, `whalePassClaims:973`, `lootboxEthBase:977` | confirmed |
| WWXRP-02 | router stubs `resolveDegeneretteBets:902` / `degeneretteResolve:1742` / `_degeneretteResolveBet:1900` | confirmed |
| BURNIE-03 | `_purchaseCoinFor:887-907` (discards 4 returns), `purchaseCoin:880`/router `:660` | confirmed |
| BURNIE-03 | payInCoin branch (burn, no queue) | spans `:1545-1555` (planning `:1545-1554` in-range); `_coinReceive:1652`→`burnCoin:1653` |
| BURNIE-03 | `_queueTicketsScaled` callers | **DRIFT** — exactly 2 (`MintModule:1251`, `GameAfkingModule:800`); `DegenerusGame:226` is the UN-scaled `_queueTickets` |
| BURNIE-03 | `gamePurchaseTicketsBurnie:571-574`, `handlePurchase` call `:1210-1217`/fold `:1220`/credit `:1355`, BATCH-01 inline `:947-949`, `_ethToBurnieValue:1657`, root-cause `24f0898b` | confirmed |
| SALVAGE-02 | `sellFarFutureTickets:2074`→`MintModule:929` (gates `:935-937`), SDGNRS floor `:958`, ticket leg `:983` | confirmed |
| SALVAGE-02 | SDGNRS relabel assignment pair | `:976-977` (planning `:975-977` includes the comment `:975`) |
| SALVAGE-02 | `_quoteFarFutureSwap:145-190` (seed `:160-163`, jitter `:165`, ticketShareBps `:166`, `cashWei` `:190`), `_farFutureFractionBps:127-130` | confirmed |
| SALVAGE-02 | sDGNRS-owned-BURNIE: `previewClaimCoinflips:927`, `coinflipAmount:934`, `consumeCoinflipsForBurn:366`, stake-consume `:904-912`, `creditFlip:859`, `BurnieCoin.transfer:315`/`transferFrom:329` | confirmed |
| SALVAGE-02 | no-arb test `test_SWAP08_NoArbAtCeiling_SweepAllDistances:168`, `_ethToBurnieValue:1657`, `mintPrice:2539` | confirmed |
| CANCEL-02 | manual cancel `:345-362` (FALSE comment `:348-351`, finalize `:353`, tombstone `:354`), `rngLock` gate `:300` | confirmed |
| CANCEL-02 | `_finalizeAfking:1026`, tombstone-reclaim `delete _subOf:1148`, pass-expiry evict `:1175-1186`, funding-out evict `:1245` | confirmed |
| CANCEL-02 | `claimAfkingBurnie:1560` (CEI `:1574`), `drainAffiliateBase:1605`, `Affiliate.claim:629` (75/20/5), `_referrerAddress:809` | confirmed (`_referrerAddress:809` = header; planning `:809-815` = body span) |
| CANCEL-02 | `Sub.affiliateBase:1952`, `Sub.pendingBurnie:1960` (packed `uint32`) | confirmed (within planning span) |

## IMPL Handoff Invariants — small features (carried into 359, re-proven at TST 361)

The IMPL author MUST preserve these as code-level invariants:

1. **WWXRP recipient** — the award credits `whalePassClaims[player]` (the bet OWNER from `_resolvePlayer`), NEVER `msg.sender`/the operator. The `s == 9` short-circuit gate is FIRST in the conjunction so non-jackpot spins read no new state.
2. **WWXRP rationing** — `wwxrpJackpotWhalePassBracketAwarded[level/10]` is keyed by bracket (NOT a per-player or `0→5` lifetime counter); the flag set is part of the same award branch (set-on-win, idempotent per bracket).
3. **BURNIE queue-on-return** — `_purchaseCoinFor` MUST capture the adjusted quantity and `_queueTicketsScaled(buyer, targetLevel, adjustedQty, false)` when non-zero; the ETH/`claimablePool` DEBIT code stays byte-unchanged.
4. **BURNIE producer-before-consumer** — the full-cost affordability gate is UPFRONT; `handlePurchase` (MINT_BURNIE leg, `ethMintSpendWei=0`/`lootBoxAmount=0`) runs to produce the reward; the burn is DEFERRED and netted (full `coinCost` − reward, floored at 0). The reward is a rebate ≤ full cost, never a separate `creditFlip`.
5. **SALVAGE BURNIE source** — the BURNIE leg is TRANSFERRED from sDGNRS-owned BURNIE (token balance + claimable coinflip stake), NEVER `creditFlip`-minted; `actualBurnie = min(target, sDGNRS-available)` with the remainder + zero-available case paid as ETH; `ethOut = cashWei − actualBurnie ≤ ethCap`.
6. **SALVAGE preview parity** — the preview/quote MUST reflect source-availability + the ETH fallback so the offer is truly knowable-in-advance; the randomness source stays the SETTLED prior-day word (no new VRF). The no-arb ceiling + eth-% cap bound EVERY reachable offer (SALVAGE-03 extends `SWAP08`).
7. **CANCEL auto-claim ordering** — manual cancel pays self (`pendingBurnie`→`creditFlip`, CEI zero-first) + drains `affiliateBase` to the 75/20/5 tree (A = referrer-upline) BEFORE `_finalizeAfking`+clear.
8. **CANCEL forfeit explicitness** — auto-evict paths (pass-expiry, funding-out, tombstone-reclaim) MUST `delete _subOf[player]` so no out-of-set claimable residue survives (pure forfeit, no self/upline payout).

## Freeze / Solvency Posture — small-feature summary (design feed → plan 03 cross-cutting)

The milestone hard floor is RNG-freeze intact + SOLVENCY-01 byte-untouched. Of the four small features, two stay in the CLEAN posture (RNG-insensitive / BURNIE-emission only) and two are FUNCTIONAL solvency-posture exceptions that are explicitly flagged. Plan 03's cross-cutting re-attestation expands this into the SEC design feed.

| Feature | RNG-freeze | Solvency (ETH/`claimablePool`) | Posture |
|---------|-----------|--------------------------------|---------|
| WWXRP-02 | Award is RNG-INSENSITIVE (counter/flag gated by the already-committed `s==9`); pre-liveness only (`:413`) | NO touch — reuses the `claimWhalePass` future-ticket deferral (SOLVENCY-neutral) | CLEAN |
| BURNIE-03 | UNAFFECTED — `purchaseCoin` reads no `rngWord` (gated by `_livenessTriggered`/`gameOverPossible`) | DEBIT byte-unchanged BUT RESTORES ticket claims (genuine functional fix; ticket wins stay pro-rata; BURNIE adds no ETH) | **FLAGGED** (functional restoration; SEC-02) |
| SALVAGE-02 | Transparent function of the SETTLED prior-day word under `rngLockedFlag` (the v48 jitter pattern); NO new VRF | SOLVENCY-positive — ETH part `≤ cashWei` relabeled out of SDGNRS (liability DROPS); BURNIE TRANSFERRED not minted | **FLAGGED** (pawn-shop cap, not value-neutral; no-arb re-proof @ SALVAGE-03) |
| CANCEL-02 | Reads no `rngWord`; `rngLock`-gated at `subscribe` entry (`:300`) | NO touch — BURNIE-emission only (`creditFlip`/`drainAffiliateBase`); SOLVENCY-01 untouched | CLEAN |

The two FLAGGED exceptions are both solvency-positive-or-neutral with their proof obligations handed to TST 361 (BURNIE → HYG-03 positive test + the `claimablePool <= balance` re-attestation; SALVAGE → the EXTEND-`SWAP08` no-arb re-proof across the full split range). No HIGH design hole remains open at lock for these four surfaces — every reachable behavior is bounded by a named invariant + anchor.

---

## Cross-Cutting RNG-Freeze Re-Attestation (paper) (SEC-01 design feed — OWNED at TST 361)

> **The milestone hard floor is RNG-freeze intact on EVERY item.** SEC-01 is OWNED empirically at TST 361 (the per-site byte-diff + determinism harness against `1e7a646d`); this section is the SPEC design gate — one labelled row per the 8 items, each with its source anchor + the TST-361 SEC-01 proof obligation. The freeze invariant the whole milestone protects: **no player-controlled mutation of VRF-derived state between the VRF REQUEST and resolution** (`threat-model-reentrancy-mev-nonissues`). The load-bearing item is (5) the UDVT byte-image — it is the ONLY one that touches the RNG-entropy `abi.encodePacked` boundary.

**(1) BATCH-01/02 — `handlePurchase` BURNIE-flip batching.** FREEZE-INTACT. The change is BURNIE-accounting only: `DegenerusQuests.handlePurchase` returns `burnieMintReward` (today credited inline at `DegenerusQuests.sol:947-949`) instead of crediting it, and the caller folds the return into the existing `lootboxFlipCredit` batch (`DegenerusGameMintModule.sol:1220` accumulate → single credit `:1355`). Neither path reads or derives any `rngWord`; determinism is byte-unchanged (same recipient, same amount, additive accumulator). **SEC-01 obligation @ 361:** byte-diff the `handlePurchase`/caller fold and assert the credited amount is identical to the inline-credit baseline.

**(2) WWXRP — Degenerette jackpot whale-halfpass.** FREEZE-INTACT. The award writes ONLY the RNG-insensitive `whalePassClaims[player]` counter (`DegenerusGameStorage.sol:973`) + the `wwxrpJackpotWhalePassBracketAwarded[level/10]` flag, gated by the already-committed `s == 9` (the jackpot score is deterministic from the committed daily `rngWord` — the player cannot retime/grind it after the request). It fires pre-liveness only (`resolveBets` reverts on `_livenessTriggered()` at `DegeneretteModule:413`). No ETH/`claimablePool` touch (reuses the `claimWhalePass` future-ticket deferral). Cross-ref WWXRP-02 D-18. **SEC-01 obligation @ 361:** assert the award branch reads/writes no VRF-derived state beyond the already-committed `s == 9`, and is unreachable post-liveness.

**(3) Terminal-decimator boost + bucket promotion.** FREEZE-INTACT. All weight + bucket + subBucket mutation (the boost AND any promotion) provably PRECEDES the resolution word — the future-day-word lemma (TDEC-03 Steps 1–3): the `require(!_livenessTriggered())` gate closes strictly before the `gameOverDay` word is born (disjoint windows, day-constant predicate), so the placement is deterministic from the fixed effective-streak factor (D-09, a `view` read of `getPlayerQuestView:1088`) × the committed burn, fixed before any randomness is revealed. Promotion is NOT special — the standard pre-request freeze gate covers both weight and bucket. Cross-ref TDEC-03 (the load-bearing re-proof). **SEC-01 obligation @ 361:** the determinism harness + the adversarial bucket-promotion probe at TERMINAL 362.

**(4) HYG — test/comment hygiene.** FREEZE-INTACT trivially. HYG-01 (stale `gameSetAutoRebuy` test refs) + HYG-02 (the two stale `_runRewardJackpots`/`runRewardJackpots` comment refs) + HYG-03 (BURNIE positive test + docstrings) are comment/test-only — NO contract logic changes, so NO RNG surface is touched. **SEC-01 obligation @ 361:** confirm zero contract-logic diff in the HYG hunks (comment/test files only).

**(5) UDVT — `type Day is uint24` (LOAD-BEARING).** FREEZE-INTACT BY EXPLICIT DISCIPLINE, not by annotation. The 3 `abi.encodePacked(…day…)` entropy sites cast `Day → uint32` so the keccak preimage byte-image is preserved BIT-FOR-BIT: `DegenerusGameAdvanceModule.sol:1405` (`keccak256(abi.encodePacked(combined, currentDay, block.prevrandao))`), `:1828` (`keccak256(abi.encodePacked(vrfWord, gapDay))`), `DegenerusGame.sol:1011` (`keccak256(abi.encodePacked(day, address(this)))`) — all three grep-confirmed at exactly these lines @ `1e7a646d`. An unwrapped uint24-backed `Day` would SHORTEN the preimage (3 bytes vs 4) and change the derived word — the seed's "pure annotation" premise is FALSE at these sites. The `rngWordByDay` mapping KEY layout is unchanged: it is `mapping(uint32 => uint256)` (`DegenerusGameStorage.sol:454`), and a uint24-backed `Day` / a uint32 cast both zero-pad to the same 32-byte mapping slot. **This is the per-site RNG-freeze byte-diff GATE the TST 361 SEC-01 enforces EMPIRICALLY** — the derived `rngWord` must be byte-identical at every entropy site after the uint32 casts. **SEC-01 obligation @ 361:** the per-site byte-diff (UDVT-02 enforced empirically — the load-bearing gate of the whole milestone).

**(6) BURNIE coin-buy fix.** FREEZE-INTACT. `purchaseCoin` reads no `rngWord` — `_purchaseCoinFor` (`DegenerusGameMintModule.sol:887-907`) is gated by `_livenessTriggered()` at `:891` + `gameOverPossible` at `:895`; the queue-on-return + the deferred net-burn rebate touch only BURNIE accounting + the ticket queue, never VRF-derived state. Cross-ref BURNIE-03 D-24. **SEC-01 obligation @ 361:** assert the coin path reads no `rngWord` (the determinism harness + the HYG-03 positive coin-buy-queues-tickets test).

**(7) SALVAGE combo payout.** FREEZE-INTACT by the EXISTING accepted pattern. It reads ONLY the SETTLED prior-day word `rngWordByDay[_simulatedDayIndex() − 1]` under the `rngLockedFlag` gate (`sellFarFutureTickets` reverts on `rngLockedFlag` at `MintModule:935`); the v48 jitter already works exactly this way (`_quoteFarFutureSwap:145-190`, seed `:160-163`, jitter `:165`, ticketShareBps `:166`). The new ETH/BURNIE split is ONE MORE derived bit-slice of the SAME seed → NO new VRF, NO new manipulable freeze surface. Non-exploitability rests on the cap (D-27), NOT on unpredictability — the offer is fully predictable. Cross-ref SALVAGE-02 D-28. **SEC-01 obligation @ 361:** assert the split reads only the settled prior-day word (no new VRF dependency) and the offer is previewable.

**(8) CANCEL auto-claim / auto-evict forfeit.** FREEZE-INTACT (the clean posture). It reads no `rngWord` (`creditFlip` / `drainAffiliateBase` only); cancel is `rngLock`-gated at the `subscribe` entry (`GameAfkingModule:300`, the docstring at `:257` confirms the gate covers ALL of create/replace/cancel). Cross-ref CANCEL-02 D-33. **SEC-01 obligation @ 361:** assert the cancel/evict paths read no VRF-derived state and are `rngLock`-gated.

**SEC-01 is OWNED at TST 361** (the per-site byte-diff + determinism harness against `1e7a646d`); the bucket-promotion freeze is adversarially probed at TERMINAL 362. This section is the design gate — every item's freeze claim rests on a named anchor + gate, none "by construction".

---

## Cross-Cutting SOLVENCY Re-Attestation (paper) (SEC-02 design feed — OWNED at TST 361)

> **The milestone hard floor is SOLVENCY-01 byte-untouched.** The framing: SIX of the eight items are BURNIE flip-credit / weight-only / pure-annotation OFF the ETH/`claimablePool` path with the ETH/pool DEBIT code BYTE-UNCHANGED (BATCH, WWXRP, TDEC, HYG, UDVT, CANCEL). The TWO functional exceptions (BURNIE, SALVAGE) are FLAGGED + both solvency-positive-or-neutral. The invariant re-attested on EVERY path: **`claimablePool <= balance`**. SEC-02 is OWNED at TST 361 (the solvency-invariant harness); this section is the design gate.

### The six clean items (ETH/`claimablePool` DEBIT byte-unchanged)

- **(1) BATCH-01/02** — BURNIE flip-credit accounting only; reroutes the `burnieMintReward` credit (inline → folded) with the SAME amount/recipient. No ETH/pool touch. **SEC-02 obligation @ 361:** assert the ETH/pool debit code is byte-identical to baseline.
- **(2) WWXRP** — RNG-insensitive counter/flag grant; reuses the `claimWhalePass` future-ticket deferral; no ETH into pools. **SEC-02 obligation @ 361:** assert `claimablePool` is untouched by the award.
- **(4) HYG** — comment/test only; no solvency surface. **SEC-02 obligation @ 361:** confirm zero contract-logic diff.
- **(3) TDEC** — weight-only; the D-07 aggregate re-key REMOVES the weighted contribution from the old `terminalDecBucketBurnTotal` key and ADDS the identical amount to the new key → total weight conserved → `runTerminalDecimatorJackpot` shares still sum to the pool. The ETH/BURNIE payout path is byte-untouched. **SEC-02 obligation @ 361:** assert the re-key conserves total aggregate weight (solvency-of-shares).
- **(5) UDVT** — pure annotation/explicit-cast; the packed `Sub`/struct day fields stay uint24-backed (no cold-slot spill) and no ETH/pool DEBIT logic changes. **SEC-02 obligation @ 361:** assert the ETH/pool debit code + the storage layout of the solvency-bearing slots are byte-identical.
- **(8) CANCEL** — BURNIE-emission only (`creditFlip` / `drainAffiliateBase`); the afking funding ledger is SEPARATE from the cancel/evict accumulators → SOLVENCY-01 untouched. **SEC-02 obligation @ 361:** assert no ETH/`claimablePool` touch on cancel OR evict.

### The two functional exceptions (FLAGGED — both solvency-positive-or-neutral)

- **(6) BURNIE coin-buy fix — POSTURE-WIDENING, FLAGGED.** The ETH/`claimablePool` DEBIT code stays BYTE-UNCHANGED, BUT this RESTORES queued ticket claims on the ETH prize pools (the intended pre-160 design) — a GENUINE FUNCTIONAL FIX, not a no-op-on-pools change. NO unbacked obligation: ticket wins stay pro-rata from the AVAILABLE pool, and BURNIE pays no ETH INTO pools, so the restored claims DILUTE existing ticket holders pro-rata rather than over-promising → `claimablePool <= balance` holds. Cross-ref BURNIE-03 D-24. **SEC-02 obligation @ 361:** the HYG-03 BURNIE-buy-then-claim path proving `claimablePool` never exceeds balance after the restored claims.
- **(7) SALVAGE combo payout — SOLVENCY-POSITIVE, FLAGGED.** The swap draws LESS ETH from `claimableWinnings[SDGNRS]` than today: only the ETH part `cashWei − actualBurnie` is relabeled out of SDGNRS (`MintModule:976-977`), which is ≤ the full `cashWei` → the ETH liability the SDGNRS relabel creates DROPS (solvency-POSITIVE); the `>= 1 ETH` SDGNRS floor (`:958`) still gates. The BURNIE part is a TRANSFER of sDGNRS-OWNED BURNIE (token balance via `BurnieCoin.transfer:315`/`transferFrom:329` + the claimable coinflip stake via `consumeCoinflipsForBurn:366`/`coinflipAmount:934`) — NO `creditFlip` mint, NO inflation. The source-availability check + the ETH fallback (`actualBurnie = min(target, sDGNRS-available)`) guarantee the swap never over-draws sDGNRS's BURNIE and stays cap-compliant. Cross-ref SALVAGE-02 D-29. **SEC-02 obligation @ 361:** the EXTEND-`SWAP08` proof that `claimablePool <= balance` holds across the full split range + the BURNIE-source valuation + the zero-available fallback, and only the ETH part leaves `claimableWinnings[SDGNRS]`.

**CANCEL + the SALVAGE-BURNIE leg are sDGNRS-owned / BURNIE-emission, NO new ETH-pool draw** — CANCEL emits BURNIE via `creditFlip`/`drainAffiliateBase` (off the ETH path entirely); the SALVAGE BURNIE leg TRANSFERS sDGNRS's own BURNIE (no mint, no ETH-pool draw — it only REDUCES the ETH relabel). The invariant **`claimablePool <= balance` holds on EVERY path** — re-attested for all eight items above. SEC-02 is OWNED at TST 361 (the solvency-invariant harness against `1e7a646d`); this is the design gate.

---

## UDVT Width/Byte-Preservation Discipline (design feed — UDVT-01/02/03 built at IMPL 359)

> **The UDVT is the HEAVY item + the load-bearing freeze item of the milestone.** Its byte-preservation discipline is FIXED here (the per-site D-19 matrix + D-20 test-file handling); UDVT-01/02/03 are built at IMPL 359, the GAS-neutrality measured at 360, the per-site byte-diff regression proven at 361. The IMPL must follow this matrix byte-for-byte.

**(1) The 3 RNG `abi.encodePacked(…day…)` sites cast `Day → uint32`** to preserve the exact keccak preimage byte-image: `DegenerusGameAdvanceModule.sol:1405` (`combined, currentDay, block.prevrandao`), `:1828` (`vrfWord, gapDay`), `DegenerusGame.sol:1011` (`day, address(this)`) — all three grep-confirmed at exactly these lines @ `1e7a646d`. The "pure annotation" premise is FALSE at these sites: an unwrapped uint24-backed `Day` would shorten the preimage from 4 bytes to 3 and change the derived word. The cast `uint32(Day.unwrap(d))` keeps the preimage identical to the current raw-`uint32` encoding. (This is T-358-15, the milestone's load-bearing freeze item.)

**(2) Packed `Sub`/struct day fields become `Day` (uint24-backed) → same slots, the v56 packed-Sub gas win intact** (no cold-slot spill). A `type Day is uint24` UDVT occupies the same 3 bytes the current packed uint24 day fields use, so the packed `Sub` struct + the other packed day-bearing structs keep their existing slot layout — no field is pushed to a new cold slot. (T-358-16; proven GAS-NEUTRAL at 360.)

**(3) Standalone day slots + `indexed` day event topics stay raw `uint32`** (preserve the existing "uint24 packed / uint32 transient" convention; cast at the `Day` boundaries). Standalone storage day slots that are already `uint32` stay `uint32`-backed, and `indexed` day event topics stay raw `uint32` so the indexed-topic byte-image is unchanged for off-chain consumers; the conversion happens explicitly at the `Day` ↔ raw boundaries.

**(4) `rngWordByDay` mapping KEY layout unchanged.** It is `mapping(uint32 => uint256)` at `DegenerusGameStorage.sol:454` (grep-confirmed); a uint24-backed `Day` and a uint32 cast both zero-pad to the same 32-byte mapping slot, so the KEY layout (and thus every stored daily word's address) is byte-preserved. The mapping key is left as `uint32` (or cast at the access boundary) — the slot is identical either way.

**(5) Operator overloads `<, <=, ==, %, +, -`** — the candidate set, finalized from the actual day comparisons at IMPL (the exact set is Claude's-discretion at IMPL within this list — the grep of real day comparisons drives the final set). solc 0.8.34 supports UDVT + global `using {…} for Day global` operator overloads (CONFIRMED — the milestone toolchain is solc 0.8.34, which has UDVT operator-overload support since 0.8.19).

**(6) Repo-wide ~649 day-bearing lines / 27 contracts** (the exact per-site count is produced at IMPL — Claude's-discretion within the locked shapes). The heaviest surfaces are `DegenerusQuests` / `GameAfkingModule` / `DegenerusGameStorage` / `DegenerusGameAdvanceModule` / `DegenerusGameBoonModule`.

**D-20 — test-file handling.** The contract-side UDVT is part of the ONE batched USER-approved 359 diff (HELD for hand-review at the contract-commit boundary). The ~143 test-file updates land as SEPARATE AGENT-committable commits (only `contracts/*.sol` commits need explicit approval — the project's "only contract commits need approval" rule).

**UDVT-01/02/03 are owned at IMPL 359** — their byte-preservation discipline is FIXED here; the GAS-neutrality is measured at 360 (packed Sub day fields stay uint24, no cold-slot spill), the per-site byte-diff regression proven at 361 (SEC-01). The IMPL author must preserve items (1)–(4) as code-level invariants.

---

## Full Call-Graph Grep-Attestation (vs `1e7a646d`)

> **Frozen-subject guard (re-asserted):** `git diff --quiet 1e7a646d HEAD -- contracts/` is **clean** at execution of this plan — the working tree is byte-identical to the frozen subject `1e7a646d`, so every grep below (run against the working tree) is read-equivalent to the frozen subject. Each row was actually grep-run at SPEC time; the recorded Y / drift is the grep result, NOT a "by construction" claim. The drifts already recorded by plans 01 + 02 are folded in (consistent with their re-attestation tables); the three NOTED drifts (HYG-02 `:809`, GameOverModule `:106` guard, auto-evict explicit-delete) are reconciled below.

**No "by construction" / "single fn reaches all paths" claim survives un-checked** — every cited `file:line` across the whole milestone scope is grep-confirmed here against `1e7a646d`.

### Block A — Degenerette / WWXRP (`DegenerusGameDegeneretteModule.sol` unless noted)

| Anchor (symbol) | Cited path:line | Confirmed | Drift note |
|-----------------|-----------------|-----------|------------|
| `_resolveFullTicketBet` | `:614` | Y | — |
| score `s = _score(...)` | `:674` | Y | — |
| jackpot gate `s == 9` | (in `_resolveFullTicketBet`) | Y | the relabeled 8-match jackpot; `s` ∈ {0..9} |
| ETH-only sDGNRS `s >= 7` block | `:713-715` | Y (drift fixed) | **DRIFT** (plan 02) — `:713-715` (`currency == CURRENCY_ETH && s >= 7` → `_awardDegeneretteDgnrs`), NOT the planning's `:710-715`. WWXRP hook goes immediately after. |
| `CURRENCY_WWXRP = 3` | `:216` | Y | — |
| `MIN_BET_WWXRP = 1 ether` | `:225` | Y | — |
| `resolveBets` (permissionless) | `:407` | Y | no access modifier |
| liveness revert in `resolveBets` | `:413` | Y (drift fixed) | **DRIFT** (plan 02) — `:413`, NOT the planning's `:414` |
| `_resolvePlayer` | `:142-150` | Y | returns the bet OWNER; operator out of scope at the award site |
| router stub `resolveDegeneretteBets` | `DegenerusGame.sol:902` | Y | — |
| router stub `degeneretteResolve` | `DegenerusGame.sol:1742` | Y | — |
| router stub `_degeneretteResolveBet` | `DegenerusGame.sol:1900` | Y | — |
| `whalePassClaims[player] += 1` grant | `DegenerusGameStorage.sol:973` | Y | the cheap freeze-safe grant |

### Block B — Terminal-Decimator (`DegenerusGameDecimatorModule.sol`)

| Anchor (symbol) | Cited path:line | Confirmed | Drift note |
|-----------------|-----------------|-----------|------------|
| `recordTerminalDecBurn` | `:693` (burn gate `:700-701`, bucket freeze `:725-728`, uint88 saturate `:750-752`) | Y | — |
| `_decSubbucketFor` | `:559-570` | Y | `keccak256(player, lvl, bucket) % bucket` |
| `_terminalDecBucket` | `:925-936` | Y | range BASE=12 → MIN=2 (lower = better) |
| `_terminalDecMultiplierBps` | `:916` | Y | 20× cap at the deadline |
| `runTerminalDecimatorJackpot` | `:780` | Y | pro-rata draw from the aggregates |
| `_terminalDecDaysRemaining` | `:939-950` | Y | deadline helper |
| aggregate key `terminalDecBucketBurnTotal` | `:755` (`keccak256(abi.encode(lvl, bucket, subBucket))`) | Y | `abi.encode`, NOT `abi.encodePacked` |
| `TerminalDecEntry` packing (24 spare bits) | `DegenerusGameStorage.sol:1585-1591` | Y | `uint80 / uint88 / uint8 / uint8 / uint48` = 232/256 |
| `getPlayerQuestView` (effective streak) | `DegenerusQuests.sol:1088` | Y | a `view` (no mutation) |
| quest-streak → activity score | `DegenerusGameMintStreakUtils.sol:251-252` | Y | `questStreakCapped * 100` bps fold |

### Block C — Advance / GameOver / RNG (the freeze spine)

| Anchor (symbol) | Cited path:line | Confirmed | Drift note |
|-----------------|-----------------|-----------|------------|
| `_handleGameOverPath` liveness gate | `AdvanceModule:591` | Y | `if (!_livenessTriggered()) return` |
| `_gameOverEntropy` (fresh word) | `AdvanceModule:1289` (`:1295` return-if-present) | Y | materializes the gameOverDay word |
| `_applyDailyRng` write `rngWordByDay[day]=finalWord` | `AdvanceModule:1879` | Y | the normal-path daily-word write |
| 2nd daily-word writer `_backfillGapDays` | `AdvanceModule:1817` (write `:1831`, loop `:1826`) | Y (drift folded) | **DRIFT** (plan 01) — the planning's "`:1879` is the only write" is WRONG; the backfill writes gap days `< endDay` (current-day-EXCLUSIVE) → never pre-writes `gameOverDay` |
| encodePacked site (combined, currentDay, prevrandao) | `AdvanceModule:1405` | Y | UDVT casts `Day → uint32` |
| encodePacked site (vrfWord, gapDay) | `AdvanceModule:1828` | Y | UDVT casts `Day → uint32` |
| encodePacked site (day, address(this)) | `DegenerusGame.sol:1011` | Y | UDVT casts `Day → uint32` |
| `rngWordByDay` mapping (KEY layout) | `DegenerusGameStorage.sol:454` | Y | `mapping(uint32 => uint256)` — KEY byte-preserved |
| `handleGameOverDrain` | `GameOverModule:86` | Y | — |
| `rngWord = rngWordByDay[day]` read | `GameOverModule:106` | Y (guard reconciled) | **DRIFT (NOTED)** — the read is INSIDE `if (preRefundAvailable != 0)` (`:105`), with revert-on-zero at `:107`; reconciled in TDEC-03 Step 4 — the future-day-word property is a property of the KEY, so the guard does NOT weaken the lemma; cross-ref TDEC-03 |
| `gameOver = true` | `GameOverModule:145` | Y | flips AFTER the `:106` read / `:174` draw |
| decimator draw `runTerminalDecimatorJackpot(decPool, lvl, rngWord)` | `GameOverModule:174` | Y | inside `handleGameOverDrain` |
| `_livenessTriggered` (day-constant) | `DegenerusGameStorage.sol:1231-1240` | Y | death-clock + VRF-grace-stall branches |
| HYG-02 first comment site `_runRewardJackpots` | `AdvanceModule:1191` | Y (drift reconciled) | **DRIFT (NOTED)** — `:1191` is a comment-table row naming `JackpotModule (_runRewardJackpots)`; the actual resolution function is `_consolidatePoolsAndRewardJackpots` (`:794`, called `:477`). HYG-02 fix target = `_consolidatePoolsAndRewardJackpots`; comment-only, owned at TST 361 |
| HYG-02 second comment site | `DegeneretteModule:809` | Y (drift reconciled) | **DRIFT (NOTED)** — `:809` does NOT match a `_runRewardJackpots` SYMBOL grep; the exact text @ `1e7a646d` is the comment `// snapshot that advanceGame / runRewardJackpots operates on stays` (a `runRewardJackpots` mention inside the poolFrozen ETH-share comment block `:807-812`). HYG-02 also names `EndgameModule`/`runRewardJackpots`; the fix target is `_consolidatePoolsAndRewardJackpots`. Comment-only, owned at TST 361 |

### Block D — Quests / streak / BATCH-01

| Anchor (symbol) | Cited path:line | Confirmed | Drift note |
|-----------------|-----------------|-----------|------------|
| `getPlayerQuestView` | `DegenerusQuests.sol:1088` | Y | (also Block B) |
| `PlayerQuestState` | `DegenerusQuests.sol:277-290` | Y | — |
| BATCH-01 inline `creditFlip(player, burnieMintReward)` | `DegenerusQuests.sol:947-949` | Y | the inline credit BATCH-01 replaces with a return |
| BATCH-01 caller return-fold | `DegenerusGameMintModule.sol:1220` | Y | `lootboxFlipCredit += questReward` |
| BATCH-01 caller single credit | `DegenerusGameMintModule.sol:1355` | Y | `coinflip.creditFlip(buyer, lootboxFlipCredit)` — confirms the `:1220`/`:1355` fold |

### Block E — BURNIE coin-buy path

| Anchor (symbol) | Cited path:line | Confirmed | Drift note |
|-----------------|-----------------|-----------|------------|
| `purchaseCoin` impl | `DegenerusGameMintModule.sol:880` | Y | — |
| `_purchaseCoinFor` (discards 4 returns) | `DegenerusGameMintModule.sol:887-907` | Y | the `_callTicketPurchase(... payInCoin=true ...)` bare statement — discards-returns CONFIRMED; gated `_livenessTriggered():891` + `gameOverPossible:895` |
| `payInCoin` branch (burns, no queue) | `DegenerusGameMintModule.sol:1545-1555` | Y (drift folded) | **DRIFT** (plan 02) — spans `:1545-1555` (planning's `:1545-1554` in-range); accumulates `burnieMintUnits`, never calls `_queueTicketsScaled` |
| `_queueTicketsScaled` definition | `DegenerusGameStorage.sol:612` | Y | — |
| `_queueTicketsScaled` callers | `MintModule:1251` + `GameAfkingModule:800` | Y (drift folded) | **DRIFT** (plan 02) — EXACTLY 2 callers, NEITHER coin-reachable; `DegenerusGame:226` is the UN-scaled `_queueTickets` (a different fn), NOT a third `_queueTicketsScaled` caller — the "no coin-path queue caller" conclusion is STRONGER |
| `purchaseCoin` router stub | `DegenerusGame.sol:660` | Y | — |
| `gamePurchaseTicketsBurnie` (live consumer) | `DegenerusVault.sol:571-574` | Y | `gamePlayer.purchaseCoin(address(this), ticketQuantity)` |
| `handlePurchase` call site | `DegenerusGameMintModule.sol:1210-1217` | Y | — |
| `_ethToBurnieValue` | `DegenerusGameMintModule.sol:1657` | Y | — |
| root-cause commit (phase 160) | `24f0898b` | Y | moved `_queueTicketsScaled` out of the shared tail |

### Block F — SALVAGE swap

| Anchor (symbol) | Cited path:line | Confirmed | Drift note |
|-----------------|-----------------|-----------|------------|
| `sellFarFutureTickets` router | `DegenerusGame.sol:2074` | Y | — |
| `sellFarFutureTickets` impl + gates | `DegenerusGameMintModule.sol:929` (gates `:935-937`) | Y | `rngLockedFlag` `:935` / `gameOver` `:936` / `_livenessTriggered` `:937` |
| SDGNRS relabel (assignment pair) | `DegenerusGameMintModule.sol:976-977` | Y (drift folded) | **DRIFT** (plan 02) — the `-= totalBudget` / `+= totalBudget` pair is `:976-977`; the planning's `:975-977` includes the leading comment `:975` |
| SDGNRS `>= 1 ETH` floor | `DegenerusGameMintModule.sol:958` | Y | — |
| ticket leg `_purchaseFor(...Claimable)` | `DegenerusGameMintModule.sol:983` | Y | — |
| `_quoteFarFutureSwap` (seed/jitter/share) | `DegenerusGameMintStreakUtils.sol:145-190` (seed `:160-163`, jitter `:165`, ticketShareBps `:166`) | Y | the prior-day-word + jitter pattern |
| `_farFutureFractionBps` | `DegenerusGameMintStreakUtils.sol:127-130` | Y | — |
| sDGNRS-owned-BURNIE: `previewClaimCoinflips` | `BurnieCoinflip.sol:927` | Y | — |
| sDGNRS-owned-BURNIE: `coinflipAmount` | `BurnieCoinflip.sol:934` | Y | — |
| sDGNRS-owned-BURNIE: `consumeCoinflipsForBurn` | `BurnieCoinflip.sol:366` | Y | `onlyBurnieCoin` |
| `creditFlip` | `BurnieCoinflip.sol:859` | Y | — |
| `BurnieCoin.transfer` | `BurnieCoin.sol:315` | Y | — |
| `BurnieCoin.transferFrom` | `BurnieCoin.sol:329` | Y | — |
| no-arb proof to EXTEND `test_SWAP08_NoArbAtCeiling_SweepAllDistances` | `test/fuzz/FarFutureSalvageSwap.t.sol:168` | Y | TST-owned at SALVAGE-03 (361) |
| `mintPrice` | `DegenerusGame.sol:2539` | Y | — |

### Block G — CANCEL (afking sub-cancel / evict)

| Anchor (symbol) | Cited path:line | Confirmed | Drift note |
|-----------------|-----------------|-----------|------------|
| manual cancel branch `subscribe(…, dailyQuantity=0)` | `GameAfkingModule.sol:345-362` | Y | `if (dailyQuantity == 0)` block; `_finalizeAfking` call `:353`, tombstone `c.dailyQuantity = 0` `:354` |
| FALSE "claim whenever" comment | `GameAfkingModule.sol:348-351` | Y | the comment "the sub pulls its earned BURNIE via `claimAfkingBurnie` whenever" — FALSE (the reclaim is permissionless/advance-driven) |
| `subscribe` `rngLock` gate | `GameAfkingModule.sol:300` | Y | docstring `:257` confirms it covers create/replace/cancel |
| `_finalizeAfking` | `GameAfkingModule.sol:1026` | Y | — |
| tombstone-reclaim `delete _subOf[player]` | `GameAfkingModule.sol:1148` (+ `_removeFromSet:1149`) | Y | the ONLY evict path that `delete`s `_subOf` today |
| pass-expiry evict | `GameAfkingModule.sol:1175-1187` | Y (drift NOTED) | **DRIFT (NOTED — auto-evict explicit-delete)** — the pass-expiry path does `_finalizeAfking` + `sub.dailyQuantity = 0` + `_removeFromSet:1187` but does NOT `delete _subOf` → leaves the slot's `pendingBurnie`/`affiliateBase` claimable OUT-OF-SET (a latent inconsistency); the CANCEL-02 D-32 forfeit intent requires an EXPLICIT `delete _subOf` here |
| funding-out evict | `GameAfkingModule.sol:1240-1252` (`_removeFromSet:1246`) | Y (drift NOTED) | **DRIFT (NOTED — auto-evict explicit-delete)** — same shape as pass-expiry: `_finalizeAfking` + `sub.dailyQuantity = 0` + `_removeFromSet:1246`, NO `delete _subOf` → out-of-set residue; CANCEL-02 D-32 requires the explicit delete |
| `claimAfkingBurnie` (CEI mirror) | `GameAfkingModule.sol:1560` (CEI zero-first `:1574`) | Y | the self-pay parity the cancel auto-claim mirrors |
| `drainAffiliateBase` | `GameAfkingModule.sol:1605` | Y | the upline-tree drain the cancel auto-claim mirrors |
| `claimAfkingBurnie` dispatcher | `DegenerusGame.sol:413` | Y | — |
| `DegenerusAffiliate.claim` (A/U1/U2 75/20/5) | `DegenerusAffiliate.sol:629` | Y | — |
| `_referrerAddress` | `DegenerusAffiliate.sol:809` | Y (drift folded) | **DRIFT** (plan 02) — header at `:809` (planning's `:809-815` = body span) |
| `creditFlip` | `BurnieCoinflip.sol:859` | Y | (also Block F) |

### Block H — HYG-01 stale `gameSetAutoRebuy` test refs (TST-owned at 361; cited in CONTEXT → attested present)

| Anchor (symbol) | Cited path:line | Confirmed | Drift note |
|-----------------|-----------------|-----------|------------|
| `gameSetAutoRebuy(true)` revert-non-owner | `test/unit/DegenerusVault.test.js:385` | Y (drift NOTED) | the `it("gameSetAutoRebuy reverts …")` block is `:382`, the call `:385`; the planning's `:385/456` conflates this with `:456` which is `gameSetAutoRebuyTakeProfit` (`:453/456`). Present at the cited line. |
| `gameSetAutoRebuyTakeProfit` | `test/unit/DegenerusVault.test.js:453/456` | Y | the `:456` ref is the TakeProfit variant, not the base |
| `gameSetAutoRebuy(true)` | `test/unit/GovernanceGating.test.js:247` | Y | — |
| `gameSetAutoRebuy(bool)` sig + asserts | `test/fuzz/CoverageGap222.t.sol:1055/1060/1084/1085` | Y | — |
| rename TARGET `coinSetAutoRebuy(bool,uint256)` | `test/fuzz/CoverageGap222.t.sol:1183` (+ `coinSetAutoRebuyTakeProfit:1191`) | Y | the live 2-arg signature the HYG-01 fix points the stale refs to |

**Attestation result:** every CONTEXT "Source anchors" `file:line` is grep-confirmed at `1e7a646d`. The line-drifts (folded from plans 01 + 02 + the three NOTED drifts) are corrected/reconciled inline; in every case the CONCLUSION is unchanged or strengthened (the BURNIE 2-caller grep is stronger; the GameOverModule guard does not weaken the future-day-word lemma; the HYG-02 `:809` is a comment-only mention with a clear fix target; the auto-evict out-of-set residue is exactly the latent inconsistency CANCEL-02 D-32 closes with an explicit delete). **No "by construction" / "single fn reaches all paths" claim survives un-checked.**

---

## SPEC Lock (LOCKED)

**Status: LOCKED** (was DRAFT). The v57.0 design-lock SPEC is COMPLETE — the document header's status DRAFT is hereby superseded by LOCKED. After this lock the SPEC provides: (1) every owned design-lock IMPL-ready (TDEC-02/03 · WWXRP-02 · BURNIE-03 · SALVAGE-02 · CANCEL-02), (2) the RNG-freeze + SOLVENCY design floor re-attested on paper across all 8 milestone items, (3) the UDVT byte-preservation discipline the IMPL must follow byte-for-byte, and (4) every cited `file:line` grep-proven against the frozen subject `1e7a646d` (the 3 noted drifts reconciled). Phase 359 authors the batched diff with zero un-checked assumptions.

### Owned requirement IDs — DESIGN-LOCKED (this phase 358)

| Req-ID | Design-lock | IMPL/TST owner |
|--------|-------------|----------------|
| **WWXRP-02** | Degenerette jackpot whale-halfpass (D-14..D-18) — per-bracket rationing key `level/10`, recipient = bettor `player`, hook + gate, freeze-safe RNG-insensitive grant | WWXRP-01 @ IMPL 359 |
| **TDEC-02** | Terminal-decimator boost mechanics (D-04..D-13) — last-day window, bucket promotion, subBucket re-derive, aggregate re-key, weight scaling, effective-streak source, uint88 saturate, boosted bit | TDEC-01 @ IMPL 359 |
| **TDEC-03** | Freeze-safety re-proof (D-01..D-03) — the future-day-word lemma under the bucket-promotion allowance | TDEC-01 @ IMPL 359 (built); proven at TST 361 SEC-01 + adversarial at TERMINAL 362 |
| **BURNIE-03** | Coin-buy ticket-queue Critical fix (D-21..D-24) — queue-on-return + MINT_BURNIE burn-rebate + the BATCH-01 co-design + posture-widening flag | BURNIE-01/02 @ IMPL 359; HYG-03 positive test @ TST 361 |
| **SALVAGE-02** | sDGNRS salvage combo ETH/BURNIE pawn-shop payout (D-25..D-29) — sDGNRS-owned-BURNIE source + fallback + the pawn-shop cap model + the no-arb re-proof obligation | SALVAGE-01 @ IMPL 359; SALVAGE-03 (EXTEND-`SWAP08`) @ TST 361 |
| **CANCEL-02** | Manual-cancel auto-claim + auto-evict pure-forfeit (D-30..D-33) — self + tree A/U1/U2 75/20/5 then clear; auto-evict explicit-delete forfeit; the latent loss-race fix | CANCEL-01 @ IMPL 359; CANCEL-03 (loss-race proof) @ TST 361 |

**UDVT-01/02/03** (the heavy item) are DESIGN-FED here (the D-19/D-20 byte-preservation discipline) and built at IMPL 359; the GAS-neutrality is measured at 360, the per-site byte-diff regression proven at 361 (SEC-01). They are NOT owned 358 req-IDs (UDVT is a 359 IMPL category) — the SPEC fixes their discipline.

### ROADMAP Phase-358 Success Criteria

All EIGHT ROADMAP Phase-358 Success Criteria are SATISFIED, each mapped to the SPEC section that satisfies it:

- [x] **SC1 — WWXRP whale-halfpass design locked** → SATISFIED by **`## WWXRP-02 — Degenerette Jackpot Whale-Halfpass`** (D-14..D-18: per-bracket rationing key `level/10`, recipient = bettor `player`, multi-bracket allow, hook + gate, the RNG-insensitive/pre-liveness/SOLVENCY-neutral re-attestation). Owned req-ID: WWXRP-02.
- [x] **SC2 — Terminal-decimator design decisions locked** → SATISFIED by **`## TDEC-02 — Terminal-Decimator Boost Mechanics`** (D-04..D-13: effective-streak source `getPlayerQuestView`, the bucket-improvement/promotion rule, the keep-vs-re-derive-subBucket decision, the uint88 overflow policy, the double-count-vs-burn-time resolution, shields consume-vs-read). Owned req-ID: TDEC-02.
- [x] **SC3 — Terminal-decimator freeze-safety RE-PROVEN under the bucket-promotion allowance** → SATISFIED by **`## TDEC-03 — Freeze-Safety Proof`** (D-01..D-03: the future-day-word lemma rigorously discharged — all weight + bucket + subBucket mutation precedes the resolution word; the `require(!_livenessTriggered())` gate; the dual-write reconciliation; the `:106` guard reconciliation). Owned req-ID: TDEC-03.
- [x] **SC4 — UDVT width/byte-preservation discipline locked** → SATISFIED by **`## UDVT Width/Byte-Preservation Discipline (design feed)`** (D-19 per-site matrix items 1–6: 3 encodePacked sites cast uint32, packed Sub fields stay uint24, standalone/indexed stay uint32, `rngWordByDay` KEY unchanged, operator-overload set + solc 0.8.34 confirmed; D-20 test-file handling). Design-fed: UDVT-01/02/03.
- [x] **SC5 — Freeze/solvency re-attestation + every cited `file:line` grep-attested vs `1e7a646d`** → SATISFIED by **`## Cross-Cutting RNG-Freeze Re-Attestation (paper)`** + **`## Cross-Cutting SOLVENCY Re-Attestation (paper)`** + **`## Full Call-Graph Grep-Attestation (vs 1e7a646d)`** (all 8 items freeze-intact with the UDVT byte-image load-bearing; 6-of-8 off the ETH path + the 2 flagged exceptions; every anchor grep-confirmed with the 3 noted drifts reconciled — no "by construction" survives un-checked). Design feed: SEC-01/02 (owned at TST 361).
- [x] **SC6 — BURNIE coin-buy ticket-queue Critical fix design-locked** → SATISFIED by **`## BURNIE-03 — Coin-Buy Ticket-Queue Critical Fix`** (D-21..D-24: the verified bug with all decisive anchors, the queue-on-return fix, the MINT_BURNIE burn-rebate full-cost-upfront/deferred-net-burn mechanic, the BATCH-01 co-design, the freeze + posture-widening framing). Owned req-ID: BURNIE-03.
- [x] **SC7 — sDGNRS salvage-swap combo ETH/BURNIE pawn-shop payout design-locked** → SATISFIED by **`## SALVAGE-02 — sDGNRS Salvage-Swap Combo ETH/BURNIE Pawn-Shop Payout`** (D-25..D-29: the cash-leg split, the sDGNRS-owned-BURNIE source + fallback, the pawn-shop total-payout-cap + eth-%-cap safety model, the no-new-VRF freeze framing, the solvency-positive accounting + the EXTEND-`SWAP08` no-arb re-proof obligation). Owned req-ID: SALVAGE-02.
- [x] **SC8 — manual-sub-cancel auto-claim + auto-evict pure-forfeit design-locked** → SATISFIED by **`## CANCEL-02 — Manual Sub-Cancel Auto-Claim + Auto-Evict Pure-Forfeit`** (D-30..D-33: the documented latent loss bug + the FALSE "claim whenever" comment, the auto-claim self + tree A/U1/U2 75/20/5 then clear, the auto-evict explicit-delete pure-forfeit, the BURNIE-emission-only clean freeze/solvency posture). Owned req-ID: CANCEL-02.

### Final paper-only attestation

ZERO `contracts/*.sol` were touched in this phase — `git diff --quiet 1e7a646d HEAD -- contracts/` is clean throughout (re-asserted at the Full Call-Graph Grep-Attestation guard above and at every commit). This is a paper-only design-lock SPEC; the single batched contract diff is authored at IMPL 359 (the one contract-commit boundary). The SPEC is **LOCKED**.
