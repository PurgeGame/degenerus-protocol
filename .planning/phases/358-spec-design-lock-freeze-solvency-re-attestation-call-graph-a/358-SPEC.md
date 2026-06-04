# v57.0 Design-Lock SPEC (Phase 358)

**Milestone:** v57.0 — Small-Feature Bundle + Day-Type UDVT Refactor
**Baseline / frozen subject:** v56.0 closure HEAD — frozen contract subject `1e7a646d`, closure signal `MILESTONE_V56_AT_HEAD_1e7a646d44da4ee26375edd0b006274821fef73e`.
**Status:** DRAFT (design-lock in progress — plan 01 authors the header + TDEC-02 + TDEC-03; plans 02/03 append the remaining sections).
**Owns (this plan, 01):** TDEC-02 (terminal-decimator mechanics, D-04..D-13) · TDEC-03 (freeze-safety proof, D-01..D-03).

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
