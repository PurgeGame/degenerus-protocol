# Degenerus Protocol — v69.0 Audit Findings

**Milestone:** v69.0 — Activity-Score Points + Streak/Sub Precision + pendingFlip Right-Size
**Date:** 2026-06-19
**Subject (frozen):** `contracts/` tree **`8a633d1d`** (HEAD `dee4ae1f` at authoring; the orchestrator's closure commit becomes final HEAD). Baseline was the v68.0 closure subject `contracts/` tree **`e9a5fc24`** (HEAD `3cc51d00`). The tree advanced only via the changes recorded below: the originally-approved IMPL (`c4b09267`), the re-audit remediation (`c297893a`), and the separately-found `_autoOpen` fix (`21df2411`).
**Closure signal:** MILESTONE_V69_AT_HEAD_7d0fa2c6b16bf4b0291fe5b1edb7560cf7641d45
**Method:** Phased design -> IMPL -> TST -> re-audit. The 438 re-audit used an adversarial 12-agent sweep + a cross-model council (**Codex** + **Claude** + orchestrator source-verification; Gemini CLI auth-expired this milestone) as the finder, every candidate verified against the frozen source before recording. The separately-found `_autoOpen` critical was surfaced by the USER via the afking simulator and live-proven on-chain before fix. Honest admin/governance assumed (rotation/keeper liveness in scope; admin malice out of scope).
**Regression floor:** final full forge suite **934 passed / 0 failed / 108 skipped** (134 suites; the 108 skips are pre-existing `vm.skip`) on the frozen tree.

---

## Verdict: 0 CATASTROPHE / 0 HIGH OPEN · 2 HIGH + 2 MED (migration) + 1 CRITICAL (afking) FOUND + FIXED IN-MILESTONE · 0 open findings on the final subject

v69 is a **precision + storage milestone**: it migrates the player activity score from a basis-points internal representation to whole points, replaces the dual-width quest-streak path with one exact integer path, and right-sizes the per-sub `pendingFlip` accumulator. The originally-approved IMPL (`c4b09267`) was **byte-frozen and then adversarially re-audited** — the re-audit caught that the IMPL had migrated the score *producer* and 3 consumers but **left 6 bps-domain consumer sites behind** (a ~100x scale mismatch), and a separate afking simulation surfaced a **pre-existing critical open-leg strand**. Both classes were fixed and re-verified in-milestone. The activity-score points migration now ships **complete across all consumers**, plus the afking critical fix. Nets are green; **0 findings remain open on the final subject.**

| Phase | Category | Verdict |
|---|---|---|
| 435 DESIGN | Point-unit / streak-path / packing / equivalence design-lock | OK D-01..D-10 locked; consumer-equivalence (scale-invariance) proof authored; no `.sol` change |
| 436 IMPL | Batched 6-file `.sol` diff (the approved change) | OK atomic commit `c4b09267`; EIP-170 + `Sub`-slot sanity green; D-436-09 kept the cap at `65_534` |
| 437 TST | Behavioural proofs of floor / streak / clamp / equivalence | OK 14/14 must-haves; gsd-verifier 14/14; `testGas04` packing golden updated |
| 438 REAUDIT | Adversarial re-audit + cross-model council | FOUND->FIXED **4 migration findings (2 HIGH + 2 MED, 6 sites) + 1 pre-existing CRITICAL** — ALL fixed + re-verified; nets green |
| 439 TERMINAL | Evidence pack + closure | OK this document |

---

## The headline: the 436 IMPL migration was INCOMPLETE (re-audit, phase 438)

The 436 IMPL collapsed `_playerActivityScoreAt` to the point domain (1 pt = 100 bps) and migrated the score *producer* plus three consumer families (Lootbox EV, Degenerette ROI, the terminal-decimator path). The 438 re-audit + council found the **435 design-lock's TABLE-A consumer inventory was not exhaustive** — **6 consumer sites in 4 files still read the score as basis points**, so once `playerActivityScore` returned points (~100x smaller) those sites silently mis-scaled. The council (three independent confirmations, **0 divergence**) ruled **all 4 findings REAL**, the **6-site list EXHAUSTIVE** (no 7th consumer), and **every fix scale-invariant with no new overflow**.

All four fixes are the identical mechanical /100 constant migration (plus the one `(points*100)/3` re-scale) already approved for the terminal-decimator path in the 436 IMPL — i.e. the same pattern, just at the sites the inventory missed.

### MIGRATE-01 — HIGH — FLIP regular `decimatorBurn` bonus ~100x nullified (adverse-to-player) (FIXED `c297893a`)
`FLIP.sol` regular (non-terminal) `decimatorBurn` (`:164/:666/:751/:763`) kept the bps-domain `bonusBps` cap `23_500`, the `bonusBps/3` multiplier, and a bucket reduction that divides by `23_500` — all now fed a points-domain score. The bonus collapsed ~100x (a 235-pt input yielded a `1.008x` multiplier instead of the intended `1.78x`), under-paying every regular decimator burner. **Fix:** cap `23_500`->`235`, multiplier `(bonusPoints*100)/3`, bucket denominator `/235`, param rename `bonusBps`->`bonusPoints`. This is the same re-scale the 436 IMPL applied to the terminal path; the regular path was the missed sibling.

### MIGRATE-02 — HIGH — DegenerusAffiliate lootbox taper never fires (value-leak / favourable-to-actor) (FIXED `c297893a`)
`DegenerusAffiliate.sol` lootbox taper (`:187-188`) compared a points-domain score against bps-domain thresholds `10_000 / 25_500`. With the score now ~100x smaller, the anti-farming taper **never engaged** -> 100% affiliate over-payout (the taper that is supposed to throttle high-score farmers was effectively disabled). **Fix:** thresholds `10_000 / 25_500`->`100 / 255`, plus the taper doc-comment to the points domain.

### MIGRATE-03 — MEDIUM — century quantity bonus collapses ~100x at two sites (adverse-to-player) (FIXED `c297893a`)
`modules/DegenerusGameMintModule.sol` (`:1712-1713`) and `modules/GameAfkingModule.sol` (`:835-836`) both compute `qty * min(score, 30_500) / 30_500`. With the points-domain score the numerator shrank ~100x so the century quantity bonus degenerated to ~`qty/100`. **Fix:** the bps denominator `30_500`->`305` at **both** sites.

### MIGRATE-04 — MEDIUM — DecimatorModule `_minScoreForBucket` bimodal EV (favourable-to-actor) (FIXED `c297893a`)
`modules/DegenerusGameDecimatorModule.sol._minScoreForBucket` (`:691`) kept the bps cap `23_500` against the points-domain score, producing a bimodal `90% / 145%` decimator-claim EV on every win (the graduated EV ladder collapsed to two outcomes). **Fix:** cap `23_500`->`235`.

**Remediation commit `c297893a`** — 8 `.sol` files (the four fixes above + getter/interface natspec `bps`->`whole points` accuracy on `DegenerusGame.sol`, `interfaces/IDegenerusGame.sol`, `interfaces/IDegenerusAffiliate.sol`). **Tests `fa21e39e`** — new `test/fuzz/V69ConsumerMigrationFixes.t.sol` (5 tests, pure-math mirrors, fails-without/passes-with for all four fixes) + re-pinned the V56/V61/DegeneretteHeroScore harnesses whose stale pre-PACK Sub offsets and stale bps score asserts the targeted sweep had not exercised. USER-approved ("ok approved").

---

## The separate critical: `_autoOpen` open-leg cursor strand (pre-existing; USER-found via the simulator)

Distinct from the migration — a **pre-existing** defect in the afking auto-open path, surfaced by the USER via the afking simulator and **live-proven on-chain** (`len=81, cursor=80, ~80 sealed boxes unopened, mintFlip -> NoWork`).

### AFKING-CRIT-01 — CRITICAL — `_autoOpen` strands `[0, cursor)` -> mintFlip bricks with sealed boxes -> mass quest-streak reset (FIXED `21df2411`)
The afking-box open cursor `_subOpenCursor` wrapped **only at loop entry** — it scanned `[cursor, len)`. A `subscribe` that grew `_subscribers` while the cursor sat at the old length left the cursor stranded mid-array: `_autoOpen` returned 0, `mintFlip` reverted `NoWork` (rolling back the cursor advance), and the subscribers in `[0, cursor)` were **permanently stranded** with their boxes sealed. The downstream effect is severe: sealed boxes never open -> **mass quest-streak reset** for the stranded cohort (the `drainAfkingBoxes` un-stick path exists but is unrewarded, so no keeper has economic incentive to call it).

**Distinction from the buy/stamp leg:** the sibling buy/stamp cursor `_subCursor` was **verified safe** — it resets per-day, so it cannot strand across a subscribe. Only the open leg (`_subOpenCursor`), which advances across days, was vulnerable.

**Fix:** a full-ring scan — wrap mid-scan, bound the walk by `scanned < len`, and write back a normalized cursor. Worst-case scan is unchanged (`len <= SUBSCRIBER_CAP = 1000`) and per-call opens still respect `OPEN_BATCH = 80`, so the gas envelope is preserved. **Commit `21df2411`** (GameAfkingModule only). **Tests `c019da64`** (`AutoOpenCursorRing` 4/4, incl. a 0/4-on-pre-fix proof + the real-subscribe-path repro) + **`fba12966`** (`MintFlipLifecycleCoverage` 5/5, `N=100 > OPEN_BATCH`: stamp-all -> open-all -> `NoWork` only once the set is genuinely drained). USER-approved.

---

## Design-lock summary (phase 435) — what the migration is

The 435 design-lock recorded ten USER-locked decisions (D-01..D-10) with source-anchored rationale and the load-bearing consumer-equivalence proof. The decisions that frame the v69 subject:

| Decision | Lock |
|---|---|
| **D-01** Point unit | 1 point = 100 bps; score = bps / 100. Exact for every additive contributor (each a multiple of 100 bps) except the quest-streak leg. |
| **D-02** Quest-streak floor | `floor(questStreak / 2)` — the sole sub-point leg (`questStreak * 50` bps = 0.5 pt/quest); odd streaks drop the trailing half-point. `floor(q/2) == floor((q*50)/100)`, the natural point representation. |
| **D-03** Point cap & widths | The natural point cap is `floor(65534/100) = 655`; `Sub.score` stays uint16 (656 << 65535, no collision with the sDGNRS `+1` unset sentinel). |
| **D-04/D-05** Single exact streak path | Widen `Sub.subStreakLatch` uint8->uint16 (matching the uint16 manual `state.streak`), drop the silent 255-clamp, and delete the `finalizeAfking` floor-hack. The only behaviour change is removing the prior silent 255-truncation (and its compensating exit-restore) for manual-streak > 255 players; for streak <= 255 it is byte-identical. |
| **D-06/D-07/D-08** pendingFlip right-size | `Sub.pendingFlip` uint32->uint24 + clamp re-pinned to the uint24 ceiling (`16_777_215`); the 8 freed bits feed the latch widening, keeping the accumulator at exactly `affiliateBase(32) + pendingFlip(24) + subStreakLatch(16) = 72` bits and `Sub` at one 256-bit slot, 0 free (net-zero repack). `lootboxRngPendingFlip` (uint40, a separate global field) confirmed out of scope. |
| **D-09/D-10** Equivalence | Consumer correctness = scale-invariance of the threshold/interpolation math under /100: score-INPUT thresholds convert /100 *with* the score (TABLE-A); OUTPUT bps (ROI/EV result anchors, `BPS_DENOMINATOR`) must NOT convert (TABLE-B). The single accepted divergence is the de-minimis odd-half-point boundary shift (D-02). |

**D-436-09 (IMPL discretion, recorded):** the IMPL kept the activity-score hard cap at `ACTIVITY_SCORE_HARD_CAP_POINTS = 65_534` (rename-only, **not** floored to 655). The cap is gameplay-inert — every live consumer clamp is <= 400/305/235, far below it — and keeping `65_534` makes the uint16-sentinel rationale (`65534 + 1 = 65535` fits uint16, one below max, `0` = sDGNRS unset sentinel) true verbatim. `Sub.score` stays uint16.

---

## IMPL summary (phase 436) — the approved diff `c4b09267`

The sole `.sol` change of the milestone landed as one atomic, USER-hand-reviewed commit across six files:

- **`DegenerusGameMintStreakUtils.sol`** — `_playerActivityScoreAt` collapsed to the point domain (deity base `50`/`+25`; `*100` legs dropped; whale `+10`/`+40`; curse `- curse`; quest streak `questStreak/2` floor); cap clamp -> `ACTIVITY_SCORE_HARD_CAP_POINTS`; return var `scoreBps`->`scorePoints`.
- **`DegenerusGameStorage.sol`** — TABLE-A point renames (`DEITY_PASS_ACTIVITY_BONUS_POINTS=80`, `LOOTBOX_EV_ACTIVITY_NEUTRAL_POINTS=60`, `LOOTBOX_EV_ACTIVITY_MAX_POINTS=400`, `ACTIVITY_SCORE_HARD_CAP_POINTS=65_534`); `subStreakLatch` uint8->uint16 (`SUB_STREAK_MASK 0xff->0xffff`); `Sub.pendingFlip` uint32->uint24; slot/section/field comments reconciled.
- **`DegenerusGameDegeneretteModule.sol`** — `ACTIVITY_SCORE_MID/HIGH/MAX_POINTS = 75/255/305`; ROI + WWXRP formulas scale-invariant (shape unchanged).
- **`DegenerusGameDecimatorModule.sol`** — `TERMINAL_DEC_ACTIVITY_CAP_POINTS = 235`; terminal burn multiplier re-scaled to `BPS_DENOMINATOR + (bonusPoints*100)/3` (the one non-scale-invariant migration); bucket scale-invariant.
- **`GameAfkingModule.sol`** — latch follow-through on uint16; both `pendingFlip` accrue clamps re-pinned `100_000_000`->`type(uint24).max` with `uint24(newOwed)` casts (lossless — clamp precedes cast); `affiliateBase` 100M clamp untouched (D-436-08).
- **`DegenerusQuests.sol`** — deleted the `finalizeAfking` floor-hack; the uint16 latch now carries the pre-run snapshot exactly; decay logic + final safety clamp retained.

EIP-170 at IMPL: DegenerusGame 20,388 B / 4,188 B headroom (net-neutral). `Sub` confirmed one 32-byte slot, 0 free.

---

## TST summary (phase 437) — 14/14 verified

Three new fuzz suites + the packing-golden edit, all green; gsd-verifier scored **14/14 must-haves**:

- `test/fuzz/ActivityScorePointFloor.t.sol` (4 tests) — quest-streak floor `floor(q/2) == floor((q*50)/100)` on an 18-element grid + explicit 4->2/5->2/6->3/7->3 boundaries; end-to-end `playerActivityScore` returns the floored leg; afking-XOR-manual exclusivity; exact integer combine with no fractional intermediate.
- `test/fuzz/StreakSnapshotAndPendingFlipClamp.t.sol` (5 tests) — pre-streak > 255 snapshot exactness (300/1000/60000 verbatim, no uint8 truncation); <= 255 byte-identical; `_setStreakBase` saturates at `type(uint16).max` (never wraps); `pendingFlip` saturates at `type(uint24).max = 16_777_215` (explicit `read != k` no-wrap guard); settle round-trip credits `16_777_215 * 1e18` FLIP without corrupting `affiliateBase`.
- `test/fuzz/ConsumerPointEquivalence.t.sol` (5 tests) — Lootbox EV bit-identical point-vs-bps on the whole-point grid; Degenerette ROI + WWXRP bit-identical; the Decimator `(points*100)/3` re-scale reproduces `bonusBps/3` exactly (naive `points/3` proven wrong: 117->10039 != 13900); bucket scale-invariant with `range=10` un-converted.
- `test/gas/KeeperLeversAndPacking.t.sol` — `testGas04` packing golden updated to the post-PACK widths (`uint24 pendingFlip;` / `uint16 subStreakLatch;`); `Sub` byte-sum still exactly 32.

---

## Verification on the final subject (phase 438)

| Gate | Result |
|---|---|
| Storage-layout oracle (`scripts/layout/storage_layout_oracle.sh`) | OK **all goldens match.** The earlier all-removed diff was a forge-1.6-nightly "storageLayout missing from artifact" caching artifact, fixed by `forge clean`; `_autoOpen` is logic-only so the layout is unchanged. V56-cluster slot harnesses re-pinned to the post-PACK Sub offsets (`affiliateBase u32@23, pendingFlip u24@27, subStreakLatch u16@30`). |
| EIP-170 deployed-bytecode ceiling | OK DegenerusGame **20,388 B / 4,188 B headroom** under 24,576 (natspec-only since IMPL, unchanged); GameAfkingModule under ceiling. |
| Final full forge suite | OK **934 passed / 0 failed / 108 skipped** (134 suites; the 108 skips are pre-existing `vm.skip`). |
| Cross-model council | OK Codex + Claude + orchestrator source-verification, **0 divergence**; all 4 migration findings confirmed REAL, the 6-site list EXHAUSTIVE, fixes scale-invariant. |

---

## Carried recommendations (non-blocking)

1. **Mutation / Halmos / deep-invariant coverage of the v69-changed modules** — these machine nets have zero coverage of the modules touched this milestone (the dual-net manual audit + the 14 TST proofs + the 5 migration-fix proofs carry the correctness load). **Documented carry, acceptable per the v68 close**; run on a detached/CI host when the campaign resumes.
2. **Cosmetic residual (optional):** stale "bps" doc-comments on the *frozen-snapshot* activityScore params in `IDegenerusGameModules.sol` + `DegenerusGameLootboxModule.sol` (they describe a frozen value that is consumed correctly; only the unit word is stale — no logic impact).
3. Carried from prior milestones (non-blocking): optional `:1843`/`:1850` `== 0` re-roll fulfill-write guard; optional 423 rotation-timer hardening; the v68 Coinflip/Lootbox mutation tail.

---

**Milestone audit verdict: v69 ships the activity-score points migration COMPLETE (all consumers), the single exact integer streak path, the net-zero pendingFlip repack, AND a separately-found critical afking open-leg fix. The re-audit caught and closed the incomplete migration (2 HIGH + 2 MED across 6 sites) before the subject shipped, and the USER-found `_autoOpen` critical was live-proven and fixed. Nets are green; 0 findings remain open on the final subject `8a633d1d`.**
