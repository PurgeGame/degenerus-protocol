---
phase: 268-degenerette-statistical-validation-cross-surface-preservation
phase_number: 268
plan: 268-01
plan_id: 268-01
plan_number: 01
type: summary
status: complete
milestone: v37.0
milestone_name: Degenerette Recalibration + Maintenance Bundle
completed: 2026-05-10
duration: ~6h (single-day execution; 3 atomic commits across 3 task waves; 1 USER-APPROVED batched test commit + 2 AGENT-COMMITTED planning/chore commits)
deliverable: 3 NEW test/stat files (DegenerettePerNEvExactness + DegeneretteProducerChi2 + DegeneretteBonusEv) + 1 EXTENDED test/stat/SurfaceRegression.test.js v37.0 SURF-01..04 describe + 1 NEW test/gas/Phase268GasRegression.test.js (SURF-05 + SURF-06) + package.json test:stat wiring
requirements-completed: [STAT-01, STAT-02, STAT-03, STAT-04, STAT-05, STAT-06, STAT-07,
                         SURF-01, SURF-02, SURF-03, SURF-04, SURF-05, SURF-06]
baseline: 1c0f09132d7439af9881c56fe197f81757f8164a
baseline_signal: MILESTONE_V36_AT_HEAD_1c0f09132d7439af9881c56fe197f81757f8164a
phase_267_close_sha: e1136071
test_commit_sha: 4b277aaf
phase_close_sha: pending-task-3-commit
milestone_closure_signal: pending-phase-271
milestone_closure_target: MILESTONE_V37_AT_HEAD_<sha>
---

# Phase 268 — Degenerette Statistical Validation + Cross-Surface Preservation (SUMMARY)

## Overview

Phase 268 ships the v37.0 empirical-verification + cross-surface-preservation test
deliverable for the Phase 267 Degenerette payout-recalibration contract diff. 3 NEW
`test/stat/` files drive heavy Monte Carlo: `DegenerettePerNEvExactness.test.js`
(STAT-01 per-N basePayoutEV exactness ≥ 1M draws/N; STAT-05 per-N match-count
histogram derived from same pool; STAT-07 ETH payout split rule 3-tier distribution
+ thin-pool cap-flip sub-case via `loadFixture(deployFullProtocol)` per
D-268-THINPOOL-01); `DegeneretteProducerChi2.test.js` (STAT-02 per-quadrant color
`[16,16,16,16,16,16,16,8]/120` + symbol uniform 1/8 chi² uniformity at ≥ 1M samples
within `CHI2_CRIT_05[7] = 14.067` / Wilson-Hilferty Z<1.645 at α=0.05;
D-IMPL-01 boundary cross-validation against deployed `packedTraitsDegenerette`);
`DegeneretteBonusEv.test.js` (STAT-03 per-N hero-boost EV ±1% at ≥ 100K hero-active
draws/N; STAT-04 per-N WWXRP factor EV ±1% at ≥ 100K WWXRP-active draws/N;
D-268-HARNESS-01 on-chain spot-check 5 ETH `placeDegeneretteBet` calls). Extended
`SurfaceRegression.test.js` with v37.0 SURF-01..04 describe asserting byte-identity
of `DegenerusTraitUtils.sol` existing 3 functions (`weightedColorBucket` body
L115-135 + `traitFromWord` body L143-167 + `packedTraitsFromSeed` body L169-178) +
`DegenerusGameJackpotModule.sol` file-level zero-diff + `DegenerusGameLootboxModule.sol`
file-level zero-diff (D-268-SURF03-01: Phase 269 owns the post-cleanup re-baseline)
+ `EntropyLib.sol` file-level zero-diff (ENT-04 v36.0 carry) vs v36.0 baseline
`1c0f0913`. NEW `test/gas/Phase268GasRegression.test.js` (SURF-05 + SURF-06)
derives theoretical worst-case quickPlay state FIRST in NatSpec header (N=3 +
M=8 + ETH tier-3 + ticketCount=10 single construction per D-268-WORSTGAS-01), then
constructs a deterministic VRF-injection test hitting exactly that state via the
REF-CAPTURE pin protocol for `WORST_CASE_RNG_WORDS`; `advanceGame`
STAGE_PURCHASE_DAILY (stage 6) gas pinned at `ADVANCE_GAME_DECIMATOR_STAGE_REF =
908_320` with ±2K v36.0 envelope active. Hybrid JS-replay + on-chain spot-check
harness per D-268-HARNESS-01. Reuse-only chi² tooling per STAT-06 — `makeRng` +
`CHI2_CRIT_05` + `wilsonHilfertyZ` verbatim re-declared in all 3 stat files (no
new statistical primitives). Single USER-APPROVED batched test commit at
`4b277aaf` (Task 2) + 2 AGENT-COMMITTED planning/chore commits (`4c5aa68b` Task 1
inventory + this commit Task 3 SUMMARY/STATE). **Zero source-tree mutations:**
`git diff e1136071 HEAD -- contracts/` returns empty at phase close. 13 of 13
Phase 268 requirements (STAT-01..07 + SURF-01..06) PASS at phase close.
Phase 268 closes only at the plan level; milestone-level closure signal
`MILESTONE_V37_AT_HEAD_<sha>` deferred to Phase 271 terminal-phase delivery.

## Per-Task Atomic-Commit Log

| #  | Subject                                                                                                                                  | SHA short | AGENT/USER                          | Files (counts)                                                                                                                  |
| -- | ---------------------------------------------------------------------------------------------------------------------------------------- | --------- | ----------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| 0a | `docs(268): create phase plan — 1 plan / 3 tasks (Degenerette stat suite + cross-surface preservation v37.0 + worst-case gas regression)` | 5f453877  | AGENT-COMMITTED                     | `.planning/phases/268-…/268-01-PLAN.md` (1 file)                                                                                |
| 0b | `docs(268): revise plan — D-268-WORSTGAS-01 single-construction + ticketCount=1 fallback removed`                                          | 5bb32a9c  | AGENT-COMMITTED                     | `.planning/phases/268-…/268-01-PLAN.md` (1 file; gsd-plan-checker revision)                                                     |
| 1  | `chore(268): test-file authoring sketches + helper inventory`                                                                             | 4c5aa68b  | AGENT-COMMITTED                     | `.planning/phases/268-…/268-01-CHORE-INVENTORY.md` (NEW; 510 LOC, 8 sections)                                                   |
| 2  | `test(268): degenerette stat suite + cross-surface preservation v37.0 + worst-case gas regression [STAT-01..07, SURF-01..06]`             | 4b277aaf  | **USER-APPROVED batched**           | 3 NEW stat + 1 EXTENDED surface + 1 NEW gas + `package.json` (6 files; +2,277/-1 LOC)                                          |
| 3  | `docs(268): phase 268 summary + commit-readiness register`                                                                                 | _this_     | AGENT-COMMITTED                     | `.planning/phases/268-…/268-01-SUMMARY.md` (NEW) + `.planning/STATE.md` (Phase 268 SHIPPED flips)                                |

(Roadmap progress + REQUIREMENTS traceability flips for Phase 268 → 1/1 Complete are
attempted via `gsd-sdk query roadmap update-plan-progress 268` +
`gsd-sdk query requirements mark-complete STAT-01 … SURF-06` after this commit
lands; any tracking-tree mutations from those SDK calls land in a SEPARATE follow-up
commit subject `docs(phase-268): update tracking after phase 268 close`.)

## Per-REQ Tally (13 of 13 PASS)

| REQ ID  | File evidence                                                                              | Verifying grep recipe                                                                                                                              | ✓ |
| ------- | ------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------- | - |
| STAT-01 | `test/stat/DegenerettePerNEvExactness.test.js:365` (per-N exactness describe) + L565 (cross-pick parity) | `grep -nE "describe\(\"STAT-01 — per-N basePayoutEV exactness" test/stat/DegenerettePerNEvExactness.test.js` returns `365:` and `npx hardhat test test/stat/DegenerettePerNEvExactness.test.js -g "STAT-01"` exits 0 | ✓ |
| STAT-02 | `test/stat/DegeneretteProducerChi2.test.js:137` (color chi²) + L184 (symbol chi²) + L226 (D-IMPL-01 boundary cross-validation) | `grep -nE "describe\(\"STAT-02" test/stat/DegeneretteProducerChi2.test.js` returns 3 hits; `npx hardhat test test/stat/DegeneretteProducerChi2.test.js -g "STAT-02"` exits 0 | ✓ |
| STAT-03 | `test/stat/DegeneretteBonusEv.test.js:269` (per-N hero-boost EV) + L456 (D-268-HARNESS-01 on-chain spot-check, joint) | `grep -nE "describe\(\"STAT-03" test/stat/DegeneretteBonusEv.test.js` returns 2 hits; `npx hardhat test test/stat/DegeneretteBonusEv.test.js -g "STAT-03"` exits 0 | ✓ |
| STAT-04 | `test/stat/DegeneretteBonusEv.test.js:326` (per-N WWXRP/ETH-bonus factor EV) + L456 (joint on-chain spot-check) | `grep -nE "describe\(\"STAT-04" test/stat/DegeneretteBonusEv.test.js` returns 1 hit; `npx hardhat test test/stat/DegeneretteBonusEv.test.js -g "STAT-04"` exits 0 | ✓ |
| STAT-05 | `test/stat/DegenerettePerNEvExactness.test.js:365` (histogram derived from same per-N pool as STAT-01) | `grep -nE "STAT-05" test/stat/DegenerettePerNEvExactness.test.js  # expect >= 1` returns ≥1 hit; cross-cited NatSpec at file header L3 | ✓ |
| STAT-06 | All 3 NEW stat files re-declare `makeRng` + `CHI2_CRIT_05` + `wilsonHilfertyZ` verbatim (verbatim chi² re-declaration discipline) | `for F in test/stat/Degenerette{PerNEvExactness,ProducerChi2,BonusEv}.test.js; do grep -c "function makeRng" $F; done` outputs 3 with count >= 1 each (lines 85 / 80 / 77) | ✓ |
| STAT-07 | `test/stat/DegenerettePerNEvExactness.test.js:719` (ETH payout split rule 3-tier describe) + L780 (thin-pool cap-flip JS verification) | `grep -nE "describe\(\"STAT-07" test/stat/DegenerettePerNEvExactness.test.js` returns L719; `npx hardhat test test/stat/DegenerettePerNEvExactness.test.js -g "ETH payout split rule"` exits 0 | ✓ |
| SURF-01 | `test/stat/SurfaceRegression.test.js:742` v37.0 it block (`SURF-01 — DegenerusTraitUtils.sol existing functions byte-identical vs v36.0 baseline 1c0f0913 (additions to packedTraitsDegenerette + _degTrait permitted)`) | `grep -nE "SURF-01 — DegenerusTraitUtils.sol existing functions" test/stat/SurfaceRegression.test.js` returns `742:`; `npx hardhat test test/stat/SurfaceRegression.test.js -g "v37.0 SURF.*SURF-01"` exits 0 | ✓ |
| SURF-02 | `test/stat/SurfaceRegression.test.js:747` v37.0 it block (`SURF-02 — DegenerusGameJackpotModule.sol file-level zero-diff`) | `git diff 1c0f09132d7439af9881c56fe197f81757f8164a HEAD -- contracts/modules/DegenerusGameJackpotModule.sol \| wc -l` returns `0` | ✓ |
| SURF-03 | `test/stat/SurfaceRegression.test.js:752` v37.0 it block (`SURF-03 — DegenerusGameLootboxModule.sol file-level zero-diff` — D-268-SURF03-01: Phase 269 owns the post-cleanup re-baseline; file-level zero-diff at Phase 268 close per plan) | `git diff 1c0f09132d7439af9881c56fe197f81757f8164a HEAD -- contracts/modules/DegenerusGameLootboxModule.sol \| wc -l` returns `0` | ✓ |
| SURF-04 | `test/stat/SurfaceRegression.test.js:763` v37.0 it block (`SURF-04 — EntropyLib.sol file-level zero-diff vs v36.0 baseline 1c0f0913 (ENT-04 v36.0 carry)`) | `git diff 1c0f09132d7439af9881c56fe197f81757f8164a HEAD -- contracts/libraries/EntropyLib.sol \| wc -l` returns `0` | ✓ |
| SURF-05 | `test/stat/SurfaceRegression.test.js:768` v37.0 SURF preservation gate self-test (chi² primitives verbatim re-declaration → structural pin) + `test/gas/Phase268GasRegression.test.js:348` advanceGame ±2K vs `ADVANCE_GAME_DECIMATOR_STAGE_REF = 908_320` | `npx hardhat test test/stat/SurfaceRegression.test.js -g "v37.0"` AND `npx hardhat test test/gas/Phase268GasRegression.test.js -g "advanceGame"` exit 0 | ✓ |
| SURF-06 | `test/gas/Phase268GasRegression.test.js:263` (worst-case quickPlay describe — D-268-WORSTGAS-01 single construction) + L348 (advanceGame envelope) | `npx hardhat test test/gas/Phase268GasRegression.test.js` exits 0; `grep -cE "Worst-case dimensions\|WORST_CASE_QUICKPLAY_GAS_REF\|WORST_CASE_RNG_WORDS" test/gas/Phase268GasRegression.test.js` returns >= 3 | ✓ |

**Cross-check:** plan-level acceptance criteria from `268-01-PLAN.md:1040-1057`
canonical_grep_recipes:

```bash
test -f .planning/phases/268-…/268-01-SUMMARY.md                            # PASS ✓
grep -cE "STAT-0[1-7]" .planning/phases/268-…/268-01-SUMMARY.md  # expect >= 7 ✓
grep -cE "SURF-0[1-6]" .planning/phases/268-…/268-01-SUMMARY.md  # expect >= 6 ✓
grep -c "13 of 13"      .planning/phases/268-…/268-01-SUMMARY.md  # expect >= 1 ✓
grep -c "Phase 268 SHIPPED" .planning/STATE.md                                # expect 1   ✓
grep -c "completed_phases: 2" .planning/STATE.md                              # expect 1   ✓
grep -c "completed_plans: 2"  .planning/STATE.md                              # expect 1   ✓
grep -c "percent: 40"         .planning/STATE.md                              # expect 1   ✓
```

All eight pass.

## Cross-Phase Cross-Cite Density

Phase 268 ships test-tree changes only; forward-cite consumption + audit-tree
finalization live downstream:

| Forward consumer                | Coverage                                                                                                                                                              | Verifies Phase 268 evidence                                    |
| ------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------- |
| Phase 269 GASPIN-01..03         | Root-cause + fix of Phase 261/264 SURF-05 ~120K gas-pin drift; Phase 268 deliberately did NOT touch the Phase 261/264 gas-pin tests (Phase 268's SURF-05/06 worst-case + advanceGame envelope tests are NEW pins under v37.0 baselines, not re-pins of v36.0 surfaces). Phase 269 GASPIN owns the v36.0 inheritance carry. | SURF-05 SurfaceRegression v37.0 describe self-test + SURF-06 Phase268GasRegression worst-case + advanceGame pins |
| Phase 271 AUDIT-02 surface (a)  | Per-N table dispatch correctness vs match-count distribution P_N(M) — empirical evidence is STAT-01 + STAT-05 per-N exactness + per-N analytical match-count histogram match | STAT-01, STAT-05                                                |
| Phase 271 AUDIT-02 surface (b)  | Symbol-only hero match P=1/8 + no color-channel info leak                                                                                                              | STAT-02 (symbol uniform 1/8) + STAT-03 (hero EV per-N target) |
| Phase 271 AUDIT-02 surface (c)  | `_countGoldQuadrants` boundary `color == 7` strict — overflow / off-by-one immune                                                                                      | STAT-02 (color distribution validates gold-bucket boundary) + D-IMPL-01 boundary cross-validation at L226 |
| Phase 271 AUDIT-02 surface (d)  | Producer `[16,16,16,16,16,16,16,8]/120` byte-layout consistency with downstream consumers                                                                              | STAT-02 (≥ 1M-sample chi² + D-IMPL-01 boundary)                |
| Phase 271 AUDIT-02 surface (e)  | WWXRP factor table-dispatch composition with hero boost — no double-counting                                                                                            | STAT-03 + STAT-04 (independent per-N hero + WWXRP EVs)         |
| Phase 271 AUDIT-02 surface (g)  | Hero × per-N composition skill-expression channel preserved (v34.0 surface (f) carry)                                                                                  | STAT-03 (per-N hero boost EV per-N target)                     |
| Phase 271 AUDIT-02 surface (h)  | ETH payout split-rule monotonicity + boundary-gaming + composition correctness audit; reviewer audits across all per-N basePayout × roiBps × hero × WWXRP-bonus combos | STAT-07 (3-tier rule empirical) + STAT-07 thin-pool cap-flip sub-case (preserves `ethShare + lootboxShare = payout` invariant) |
| Phase 271 AUDIT-03 conservation | Algebraic re-proof basePayoutEV = 100 centi-x ± rounding per N + ETH bonus EV = exactly 5.000% per N + hero EV-neutrality                                              | STAT-01 + STAT-03 + STAT-04 empirical evidence cross-cited       |
| Phase 271 §3a (per-phase summary) | Phase 268 contributes test-tree-only delta-surface row (zero source-tree mutations; 13 of 13 STAT + SURF requirements PASS)                                              | All 13 Phase 268 requirements (rolled into milestone summary) |
| Phase 271 REG-01                | v36.0 closure signal non-widening — SURF-04 EntropyLib byte-identical at v37.0 HEAD                                                                                    | SURF-04 (test/stat/SurfaceRegression.test.js:763)              |
| Phase 271 REG-04                | Prior-finding spot-check sweep across v25-v36 findings — Degenerette-touched function references stay PASS                                                              | STAT-01..07 empirical + SURF-01..06 byte-identity              |

## Project-Feedback-Rules Honored

| Rule                                       | How Phase 268 honored it                                                                                                                                                                |
| ------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `feedback_no_contract_commits.md`          | Task 2 batched test commit (`4b277aaf`) awaited explicit user `approved` string before commit per `checkpoint:human-verify` gate. ZERO `contracts/` writes in Phase 268.                  |
| `feedback_batch_contract_approval.md`      | Single batched diff for the entire phase test-tree change (3 NEW + 1 EXTENDED + 1 NEW + package.json) into ONE commit (`4b277aaf`). Test-tree treated identically to contract-tree under this rule. |
| `feedback_never_preapprove_contracts.md`   | Agent did NOT claim pre-approval for any test commit at any task gate. Task 2 explicitly waited at `checkpoint:human-verify`; deviations (analytical-P_N load-bearing assertion, 8-pick parity sub-sample, REF-CAPTURE rngWords pinning) approved explicitly. |
| `feedback_wait_for_approval.md`            | Explicit `approved` string captured at Task 2 gate before any `git add` of test files.                                                                                                  |
| `feedback_manual_review_before_push.md`    | Agent did NOT `git push` at any task gate (including this Task 3 close commit). Pre-push human review reserved for user.                                                                  |
| `feedback_no_history_in_comments.md`       | NatSpec + inline comments in all 5 new/extended test files describe the CURRENT v37.0 design only; ZERO "was/used to/previously/formerly/changed from/removed/deleted" prose. Test files re-declare chi² helpers verbatim per STAT-06 carry — no `// was: …` style annotations. |
| `feedback_gas_worst_case.md`               | SURF-06 derived theoretical worst-case quickPlay state FIRST in `Phase268GasRegression.test.js:70-122` NatSpec header (D-268-WORSTGAS-01 single construction: N=3 + M=8 + ETH tier-3 + ticketCount=10; ≤800K gas analytical ceiling). REF-CAPTURE protocol pins `WORST_CASE_RNG_WORDS` literals for subsequent runs; `ADVANCE_GAME_DECIMATOR_STAGE_REF = 908_320` literal pinned at L129 for advanceGame envelope (±2K active). |
| `feedback_skip_research_test_phases.md`    | Research-agent dispatch skipped for Phase 268. CONTEXT.md + plan + Task 1 chore inventory (510 LOC, 8 sections) provided enough authoring artifact to author Task 2 directly.            |
| `feedback_contract_locations.md`           | Test JS-replays paste constants from `contracts/modules/DegenerusGameDegeneretteModule.sol` only (not from any stale copy). 25 per-N packed-constant JS tables (`QUICK_PLAY_PAYOUTS_N{0..4}_PACKED` + `QUICK_PLAY_PAYOUT_N{0..4}_M8` + `HERO_BOOST_N{0..4}_PACKED` + `WWXRP_FACTORS_N{0..4}_PACKED`) replicated from the canonical `contracts/` source. |
| `feedback_rng_backward_trace.md`           | N/A for Phase 268 (test-only phase; producer surface unchanged since Phase 267 close). Test verifies the existing Degenerette VRF flow at L587-621 (single `resultSeed` → per-quadrant 64-bit lanes) is preserved — no commitment-window changes introduced by Phase 268.                                                  |
| `feedback_rng_commitment_window.md`        | N/A for Phase 268 (no commitment-window changes — Phase 268 emits zero source-tree mutations; tests simply consume the same Degenerette VRF flow as Phase 267 contract close).             |
| `feedback_test_rnglock.md`                 | N/A for Phase 268 — `rngLocked` removal from coinflip claim paths is unrelated to v37.0 Degenerette scope. Phase 268 deliberately did NOT modify coinflip test fixtures.                  |

## Commit-Readiness Register (per D-268-CLOSURE-02 carry; THREE subsections; NO §iv awaiting-approval subsection)

### §i USER-APPROVED contracts (0 commits)

Phase 268 owns **zero** contract changes (test-only phase). The v37.0 source-tree HEAD
at Phase 268 close is unchanged from Phase 267 close `e1136071`:

```bash
git diff e1136071 HEAD -- contracts/  # returns empty (verified at Phase 268 close)
```

Cross-cite: `contracts/DegenerusTraitUtils.sol` + `contracts/modules/DegenerusGameDegeneretteModule.sol`
Phase 267 changes (commit `e1136071`) byte-identical at v37.0 HEAD. SURF-01..04 v37.0
SurfaceRegression describe (`test/stat/SurfaceRegression.test.js:609-787`) asserts the
SAME byte-identity claim against the v36.0 baseline `1c0f0913` (for the OTHER 4 protected
files: JackpotModule + LootboxModule + EntropyLib + TraitUtils existing functions).

### §ii USER-APPROVED tests (1 commit at Task 2)

| SHA short | Subject                                                                                                                              | Files                                                                                              | Approval evidence                                                                                                                                          |
| --------- | ------------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 4b277aaf  | `test(268): degenerette stat suite + cross-surface preservation v37.0 + worst-case gas regression [STAT-01..07, SURF-01..06]` | 3 NEW: `test/stat/DegenerettePerNEvExactness.test.js` (+812 LOC) + `test/stat/DegeneretteProducerChi2.test.js` (+324 LOC) + `test/stat/DegeneretteBonusEv.test.js` (+484 LOC); 1 EXTENDED: `test/stat/SurfaceRegression.test.js` (+214 LOC v37.0 describe + chi²-helper structural pin); 1 NEW: `test/gas/Phase268GasRegression.test.js` (+442 LOC); `package.json` (+1/-1 test:stat wiring) — net +2,277/-1 LOC across 6 files | User explicit `approved` string captured at Task 2 `checkpoint:human-verify` gate. User-approved deviations recorded in commit body: (1) STAT-01/04 use analytical-P_N × .sol-paste tables for the load-bearing assertion (empirical mean informational only because M=8 variance dominates at 1M draws/N — tightening to ±0.50/±1% empirical would require ~225M draws/N which the orchestrator deemed wasteful); (2) STAT-01 cross-pick parity sub-sampled to 8 picks/N × 100K draws = 800K total/N instead of 32 picks/N (same statistical reach within M=8 variance bound; saves 75% wall-clock); (3) SURF-06 worst-case `rngWords` pinned via REF-CAPTURE protocol on first successful brute-force run; analytical worst-case derivation (≤ 800K gas ceiling) remains load-bearing NatSpec audit trail; `advanceGame` ±2K vs 908_320 active. |

### §iii AGENT-COMMITTED planning artifacts (3 commits)

| SHA short | Subject                                                                                                                                  | Files                                                                                          |
| --------- | ---------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| 5f453877  | `docs(268): create phase plan — 1 plan / 3 tasks (Degenerette stat suite + cross-surface preservation v37.0 + worst-case gas regression)` | `.planning/phases/268-…/268-01-PLAN.md` (initial author)                                       |
| 5bb32a9c  | `docs(268): revise plan — D-268-WORSTGAS-01 single-construction + ticketCount=1 fallback removed`                                          | `.planning/phases/268-…/268-01-PLAN.md` (gsd-plan-checker revision iteration)                  |
| 4c5aa68b  | `chore(268): test-file authoring sketches + helper inventory`                                                                             | `.planning/phases/268-…/268-01-CHORE-INVENTORY.md` (NEW; 510 LOC, 8 sections)                  |
| _this_    | `docs(268): phase 268 summary + commit-readiness register`                                                                                 | `.planning/phases/268-…/268-01-SUMMARY.md` (NEW) + `.planning/STATE.md` (Phase 268 SHIPPED flips) |

(Plus an optional follow-up `docs(phase-268): update tracking after phase 268 close`
commit lands ONLY IF the post-close `gsd-sdk query roadmap update-plan-progress 268`
+ `gsd-sdk query requirements mark-complete STAT-01 … SURF-06` invocations mutate
the ROADMAP.md / REQUIREMENTS.md tracking trees. See Task 3 action body in
`268-01-PLAN.md` for the orchestrator-handoff fallback contract.)

**No §iv awaiting-approval subsection** — Phase 268 closes with zero pending items
per D-268-CLOSURE-02 carry. The orchestrator-handoff SDK flips (roadmap progress
1/1 + 13 requirements mark-complete) are bookkeeping carry, not pending-approval debt.

## Open Items / Deferrals

Phase 268 ships test-tree only. Downstream phases own:

- **Phase 269 — Lootbox Dead-Branch Cleanup + SURF-05 Gas-Pin Re-Pinning:** LBX-01..03
  (delete unreachable BURNIE-conversion branch in `_resolveLootboxRoll` L1568-1581) +
  GASPIN-01..03 (root-cause + fix Phase 261/264 SURF-05 ~120K gas-pin drift under
  `npm run test:stat` ordering). 6 requirements; independent maintenance. Phase 268's
  v37.0 SURF-05/06 pins are deliberately NEW (not re-pins of v36.0 surfaces) so as
  not to entangle with the Phase 269 GASPIN root-cause investigation.

- **Phase 270 — Post-v32.0 Deferred-Commit Adversarial Sub-Audit:** DELTA-01..04
  (audit-only sweep of commits `002bde55` + `2713ce61`; read-only delta-classification
  + KI envelope check). 4 requirements; audit-only.

- **Phase 271 — Delta Audit + Findings Consolidation (Terminal):** AUDIT-01..06 +
  REG-01..04 (single `audit/FINDINGS-v37.0.md` 9-section deliverable; closure signal
  `MILESTONE_V37_AT_HEAD_<sha>` emitted in §9c; KNOWN-ISSUES.md walkthrough;
  ROADMAP/STATE/MILESTONES milestone-level closure flips). 10 requirements; depends
  on Phase 267, 268, 269, 270. Phase 268's STAT-01..07 + SURF-01..06 empirical
  evidence feeds §4 surfaces (a)..(h) + §3 conservation re-proof in §3 of the
  terminal deliverable.

Milestone-level closure (closure signal `MILESTONE_V37_AT_HEAD_<sha>` + KNOWN-ISSUES.md
walkthrough + audit deliverable + ROADMAP/STATE/MILESTONES milestone-level demotion
+ final user-review gate) DEFERRED to Phase 271. Phase 268 closes only at the plan
level.

## Closure Signal

```
pending-phase-271
```

`MILESTONE_V37_AT_HEAD_<sha>` will be emitted in `audit/FINDINGS-v37.0.md` §9c at
Phase 271 close per D-267-CLOSURE-01 + D-268-CLOSURE-01 carry from v36 D-266-FILES-01
+ D-266-CLOSURE-01. Phase 268 records this as the carry target only.

## Notes

- **Single batched test commit discipline.** Per `feedback_no_contract_commits.md` +
  `feedback_batch_contract_approval.md` + `feedback_never_preapprove_contracts.md` +
  `feedback_wait_for_approval.md`, the Task 2 test diff combined 3 NEW stat files +
  1 EXTENDED surface file + 1 NEW gas file + `package.json` test:stat wiring into a
  single diff presented at the `checkpoint:human-verify` gate. User typed `approved`,
  the agent committed (`4b277aaf`), did NOT push. Mirrors the v36 Phase 266 / v37
  Phase 267 single-batched-commit precedent.

- **Agent-committed planning artifacts.** Plan-authoring (`5f453877` + `5bb32a9c`
  revision iteration), Task 1 chore inventory (`4c5aa68b`), and Task 3 SUMMARY +
  STATE flips (this commit) touch only `.planning/` files and are AGENT-COMMITTED
  autonomous per Phase 268 plan write_policy.

- **Zero source-tree mutations at Phase 268 close.** `git diff e1136071 HEAD --
  contracts/` returns empty; `git diff 1c0f0913 HEAD -- contracts/` returns only
  the Phase 267 Degenerette diff (TraitUtils additive + DegeneretteModule rewrite).
  Phase 268's v37.0 SURF-01..04 SurfaceRegression describe asserts the same
  byte-identity claim live in the test harness.

- **User-approved Task 2 deviations documented in commit body and §ii row.** Three
  deviations from the original plan text:

  1. **STAT-01/04 analytical-P_N × .sol-paste tables load-bearing.** Original plan
     wording suggested empirical-mean ±0.50 centi-x assertion. Task 2 review noted
     M=8 variance dominates at 1M draws/N → tightening to ±0.50 centi-x empirically
     would require ~225M draws/N (≈ a 225× wall-clock blowup). User-approved
     compromise: load-bearing assertion is `analytical_P_N · .sol_paste_table_value ==
     contract_computed_value` (exact equality at the JS-replay layer, with the
     analytical P_N derived from binomial-convolution + 25 packed-constant
     byte-identity grep); the empirical-mean readout is logged as informational
     `console.log` only. Equivalent strength; far less wall-clock.

  2. **Cross-pick parity sub-sampled to 8 picks/N × 100K draws.** Original spec
     suggested 32 picks/N × 1M draws (32M per-N total). M=8 variance bound proves
     8 picks/N × 100K = 800K samples covers the parity space within the same
     statistical envelope; user-approved 25% wall-clock retention.

  3. **SURF-06 worst-case `rngWords` pinned via REF-CAPTURE protocol.** Brute-force
     search for the exact rngWords-tuple maximizing quickPlay gas would exceed
     practical wall-clock per test run; instead the test prints a `[SURF-06
     REF-CAPTURE]` line on first successful search; subsequent runs read the pinned
     literals from `WORST_CASE_RNG_WORDS` constant. Analytical worst-case ≤ 800K gas
     ceiling (D-268-WORSTGAS-01 single construction: N=3 + M=8 + ETH tier-3 +
     ticketCount=10) remains the load-bearing NatSpec audit trail. `advanceGame`
     ±2K envelope vs `ADVANCE_GAME_DECIMATOR_STAGE_REF = 908_320` is fully active
     (no REF-CAPTURE deferral; pinned at L129).

- **STAT-06 reuse-only chi² tooling.** All 3 new stat files verbatim re-declare
  `makeRng` + `CHI2_CRIT_05` + `wilsonHilfertyZ` (`DegenerettePerNEvExactness.test.js:85`
  + `DegeneretteProducerChi2.test.js:80` + `DegeneretteBonusEv.test.js:77`). Mirrors
  the `test/stat/TraitDistribution.test.js` L48-100 / Phase 261 / Phase 264 / Phase
  266 carry. No new statistical primitives introduced. The
  `SurfaceRegression.test.js:768` v37.0 SURF preservation gate self-test asserts the
  verbatim re-declaration discipline structurally.

- **D-268-HARNESS-01 hybrid JS-replay + on-chain spot-check.** Stat assertion is
  pure JS-replay (heavy Monte Carlo; cheap; deterministic with seed); a small
  spot-check (5 ETH `placeDegeneretteBet` calls — one per N) runs on-chain via the
  Hardhat node to verify the JS-replay tables match the deployed contract bytecode
  (`DegenerettePerNEvExactness.test.js:674` and `DegeneretteBonusEv.test.js:456`).
  Cross-validation reuses `loadFixture` + Hardhat VRF override pattern documented
  in `268-01-CHORE-INVENTORY.md` §3.

- **D-268-THINPOOL-01 STAT-07 thin-pool sub-case.** Fresh `loadFixture(deployFullProtocol)`
  + small pool seed used to construct the cap-flip path test fixture (the only
  on-chain round-trip in the STAT-07 suite). Pure-JS verification of the cap-flip
  invariant `ethShare + lootboxShare = payout` runs as the load-bearing assertion
  at `DegenerettePerNEvExactness.test.js:780-815`.

- **D-268-WORSTGAS-01 single-construction discipline (plan revision `5bb32a9c`).**
  The worst-case quickPlay state derivation in `Phase268GasRegression.test.js:65-122`
  NatSpec header constructs the ≤800K gas analytical ceiling from a SINGLE state
  (N=3 + M=8 + ETH tier-3 + ticketCount=10), not by composing multiple
  ticketCount=1 fallback constructions. User clarification during plan revision:
  "hero match INHERENT at M=8" — at M=8 every quadrant matches by definition, so
  hero match is structurally guaranteed and does not need to be engineered into
  the worst-case rngWords pin.

## Self-Check: PASSED

Verifications performed before recording PASSED:

- `268-01-SUMMARY.md` exists at `.planning/phases/268-degenerette-statistical-validation-cross-surface-preservation/268-01-SUMMARY.md` (file written this task).
- `grep -cE "STAT-0[1-7]" 268-01-SUMMARY.md` ≥ 7 — all 7 STAT IDs cited in per-REQ tally + cross-phase + commit-readiness register.
- `grep -cE "SURF-0[1-6]" 268-01-SUMMARY.md` ≥ 6 — all 6 SURF IDs cited.
- `grep -c "13 of 13"` ≥ 1 — PASS count documented in Overview + Per-REQ Tally heading.
- `grep -c "USER-APPROVED tests\|USER-APPROVED batched"` ≥ 1 — commit-readiness §ii.
- `grep -c "AGENT-COMMITTED"` ≥ 1 — commit-readiness §iii.
- `grep -c "MILESTONE_V37_AT_HEAD"` ≥ 1 — closure signal target documented as
  pending Phase 271 in frontmatter `milestone_closure_target` + Closure Signal
  section + Open Items / Deferrals.
- ≥ 4 feedback rules cited (`feedback_gas_worst_case.md` +
  `feedback_no_contract_commits.md` + `feedback_batch_contract_approval.md` +
  `feedback_never_preapprove_contracts.md` + 8 more) in Project-Feedback-Rules table.
- THREE-subsection commit-readiness register present (§i / §ii / §iii); §iv
  intentionally absent per D-268-CLOSURE-02.
- All 4 referenced commits verified in git log:
  - `git log --oneline 5f453877 -1` → `docs(268): create phase plan — 1 plan / 3 tasks (Degenerette stat suite + cross-surface preservation v37.0 + worst-case gas regression)`.
  - `git log --oneline 5bb32a9c -1` → `docs(268): revise plan — D-268-WORSTGAS-01 single-construction + ticketCount=1 fallback removed`.
  - `git log --oneline 4c5aa68b -1` → `chore(268): test-file authoring sketches + helper inventory`.
  - `git log --oneline 4b277aaf -1` → `test(268): degenerette stat suite + cross-surface preservation v37.0 + worst-case gas regression [STAT-01..07, SURF-01..06]`.
- 13 requirement IDs (STAT-01..07 + SURF-01..06) appear in frontmatter
  `requirements-completed` array AND in the per-REQ tally rows.
- `git diff e1136071 HEAD -- contracts/` returns empty (verified pre-commit; zero
  source-tree mutation since Phase 267 close).
