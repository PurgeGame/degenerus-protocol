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
