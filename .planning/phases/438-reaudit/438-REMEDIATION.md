# Phase 438 REAUDIT — Contract Remediation (v69 incomplete-migration fixes)

**Status:** AUTHORED + VALIDATED — ⏸ AWAITING USER REVIEW + COMMIT APPROVAL (the milestone's sole gate)
**Date:** 2026-06-19
**Subject under repair:** v69 IMPL `c4b09267` (contracts/ tree `2eeed005`)
**Nothing is committed.** All changes sit uncommitted in the working tree for hand-review.

---

## What the re-audit found

The 438 adversarial re-audit (workflow `wf_3150aa91`, 12 agents) + a cross-model council (**Codex** + **Claude** + orchestrator source-verification; Gemini CLI auth-expired) found the v69 IMPL migrated the activity-score *producer* + 3 consumers from basis points → whole points, but **left 6 consumer sites in 4 files still bps-domain** — a ~100× scale mismatch now that `playerActivityScore` returns points. The 435 design-lock's TABLE-A consumer inventory missed them.

**Council verdict: all 4 findings REAL (2 HIGH, 2 MED); the 6-site list is EXHAUSTIVE (no 7th consumer); all fixes scale-invariant with no new overflow.** Three independent confirmations, zero divergence.

| # | Site | Sev | Direction | Bug | Fix (mirrors the migrated terminal path) |
|---|------|-----|-----------|-----|------|
| 1 | `FLIP.sol` regular `decimatorBurn` (`:164/:666/:751/:763`) | HIGH | adverse-to-player | `bonusBps` cap 23_500 + `bonusBps/3` + bucket ÷23_500 → bonus ~100× nullified (235pt→1.008× vs 1.78×) | cap→235, `(bonusPoints*100)/3`, bucket ÷235, rename `bonusBps`→`bonusPoints` |
| 2 | `DegenerusAffiliate.sol` lootbox taper (`:187-188`) | HIGH | value-leak / favourable-to-actor | thresholds 10_000/25_500 bps vs points input → anti-farming taper never fires → 100% affiliate over-payout | thresholds → 100 / 255 |
| 3 | Century bonus ×2: `MintModule:1712-1713` + `GameAfkingModule:835-836` | MED | adverse-to-player | `qty*min(score,30_500)/30_500` → ~qty/100 (bonus collapses ~100×) | `30_500` → `305` (both sites) |
| 4 | `DecimatorModule._minScoreForBucket` (`:691`) | MED | favourable-to-actor | bps cap 23_500 → points EV → bimodal 90%/145% on every win | `cap` → `235` |

All fixes are mechanical ÷100 constant migrations + the `(points*100)/3` re-scale — the identical pattern already approved for the terminal-decimator path in the 436 IMPL.

---

## Files changed (uncommitted)

### contracts/ — the fix (8 files, fingerprint `d28dfdf9…`)
- `contracts/FLIP.sol` — finding 1 (cap rename 23_500→235, multiplier `(bonusPoints*100)/3`, bucket ÷235, param rename, comment).
- `contracts/DegenerusAffiliate.sol` — finding 2 (taper thresholds 100/255) + taper doc-comment to points.
- `contracts/modules/DegenerusGameMintModule.sol` — finding 3a (century 30_500→305).
- `contracts/modules/GameAfkingModule.sol` — finding 3b (century 30_500→305).
- `contracts/modules/DegenerusGameDecimatorModule.sol` — finding 4 (`_minScoreForBucket` cap 235) + comment.
- `contracts/DegenerusGame.sol` — natspec: getter `@return scoreBps … basis points` → `scorePoints … whole points` (API accuracy; pairs with the impl).
- `contracts/interfaces/IDegenerusGame.sol` — getter interface natspec → whole points.
- `contracts/interfaces/IDegenerusAffiliate.sol` — `lootboxActivityScore … in BPS` → whole points.

### test/ — proof + detection-net re-pin (7 files, all green)
- NEW `test/fuzz/V69ConsumerMigrationFixes.t.sol` — 5 tests, pure-math mirror, fails-without/passes-with for all 4 fixes (e.g. FLIP 235pt→17833 rejects buggy 10078; century 305pt→full qty rejects buggy qty/100; affiliate taper engages at 100pt; `_minScoreForBucket` graduated EV rejects saturated 145%).
- Re-pinned (stale pre-PACK Sub offsets + stale bps score asserts): `V56SecUnmanipulable.t.sol`, `V56SubHardening.t.sol`, `V56FreezeSolvency.t.sol`, `V56AfkingGasMarginal.t.sol` (pendingFlip u24@27 / subStreakLatch u16@30, drop `&0x7f`); `V61RngFreezeIntact.t.sol` (curse `*100`→point domain); `DegeneretteHeroScore.t.sol` (ROI mirror anchors 75/255/305).

---

## Validation (orchestrator-independent)
- `forge build` — success (only pre-existing unsafe-typecast advisory warnings).
- `V69ConsumerMigrationFixes` — 5/5 pass.
- Re-pin + related suite (11 contracts) — 92 passed / 0 failed / 2 pre-existing skips; the 3 previously-red tests now pass (1000 fuzz runs each).
- contracts/ fingerprint verified unchanged after the test pass (no agent touched source).

---

## To APPROVE + COMMIT (tomorrow)
1. Review the contract diff: `git diff -- contracts/`  (8 files) and the tests: `git diff -- test/` + `test/fuzz/V69ConsumerMigrationFixes.t.sol`.
2. If approved, commit (contracts need the hook move-aside + env bypass, per the 436 precedent):
   ```
   mv .git/hooks/pre-commit .git/hooks/pre-commit.bak
   git add -f contracts/ test/ .planning/STATE.md .planning/ROADMAP.md .planning/REQUIREMENTS.md .planning/phases/438-reaudit/
   CONTRACTS_COMMIT_APPROVED=1 git commit -m "fix(438): complete the v69 bps→points migration — 6 missed consumer sites (re-audit)"
   mv .git/hooks/pre-commit.bak .git/hooks/pre-commit
   ```
   (New byte-frozen subject after this commit; UNPUSHED — push stays a separate USER action.)

---

## Remaining 438/439 work (after the fix is committed)
- **438 REAUDIT close-out:** re-run the storage-layout oracle (`bash scripts/layout/storage_layout_oracle.sh` — expected CLEAN, no recapture; normalize drops struct internals) + EIP-170 re-measure on the new subject; record the detection-net coverage GAPS the council flagged (mutation/Halmos/invariant nets have zero coverage of the v69-changed modules — documented carry acceptable per the v68 close); fold this remediation into the 438 verdict.
- **439 TERMINAL:** `audit/FINDINGS-v69.0.md` (chmod 444) + HTML report recording the design-lock, equivalence verdict, TST results, **the re-audit findings + this remediation**, and the closure signal `MILESTONE_V69_AT_HEAD_<sha>`.
- **Cosmetic residual (optional):** stale "bps" doc-comments on the *frozen-snapshot* activityScore params in `IDegenerusGameModules.sol` + `DegenerusGameLootboxModule.sol` (describe a frozen value consumed correctly; only the unit word is stale).
