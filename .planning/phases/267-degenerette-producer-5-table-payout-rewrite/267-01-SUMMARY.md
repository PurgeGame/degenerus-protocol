---
phase: 267-degenerette-producer-5-table-payout-rewrite
phase_number: 267
plan: 267-01
plan_id: 267-01
plan_number: 01
type: summary
status: complete
milestone: v37.0
milestone_name: Degenerette Recalibration + Maintenance Bundle
completed: 2026-05-10
duration: ~2h (single-day execution; 4 atomic commits across 4 task waves; agent-executed planning artifacts + 1 USER-APPROVED batched contract diff)
deliverable: contracts/DegenerusTraitUtils.sol (additive) + contracts/modules/DegenerusGameDegeneretteModule.sol (rewrite); audit deliverable deferred to Phase 271
requirements-completed: [DGN-01, DGN-02, DGN-03, DGN-04, DGN-05, DGN-06, DGN-07, DGN-08, DGN-09, DGN-10,
                         DGN-11, DGN-12, DGN-13, DGN-14, DGN-15,
                         PAY-SPLIT-01, PAY-SPLIT-02, PAY-SPLIT-03]
baseline: 1c0f09132d7439af9881c56fe197f81757f8164a
baseline_signal: MILESTONE_V36_AT_HEAD_1c0f09132d7439af9881c56fe197f81757f8164a
v34_baseline: 6b63f6d4daf346a53a1d463790f637308ea8d555
v34_baseline_signal: MILESTONE_V34_AT_HEAD_6b63f6d4daf346a53a1d463790f637308ea8d555
contract_commit_sha: e1136071
contract_commit_subject: "feat(267): degenerette producer + 5-table payout rewrite + 3-tier ETH split [DGN-01..15, PAY-SPLIT-01..03]"
phase_close_sha: pending-task-4-commit
milestone_closure_signal: pending-phase-271
milestone_closure_target: MILESTONE_V37_AT_HEAD_<sha>  # emitted at Phase 271 §9c per D-267-CLOSURE-01
---

# Phase 267 — Degenerette Producer + 5-Table Payout Rewrite (SUMMARY)

## Overview

Phase 267 ships the v37.0 Degenerette payout-recalibration contract diff: a NEW additive
`packedTraitsDegenerette(uint256) internal pure returns (uint32)` producer (with private
`_degTrait(uint64) private pure returns (uint8)` helper) added to `contracts/DegenerusTraitUtils.sol`
implementing the per-quadrant near-uniform color distribution `[16,16,16,16,16,16,16,8]/120`
(commons 13.33%, gold 6.67%) + uniform 1/8 symbol; the existing 3 TraitUtils functions
(`weightedColorBucket`, `traitFromWord`, `packedTraitsFromSeed`) byte-identical at v36.0
closure HEAD `1c0f0913` (DGN-14 / SURF-01 carry into Phase 268). The Degenerette consumer
`contracts/modules/DegenerusGameDegeneretteModule.sol` is rewritten for 5 per-N
(gold-quadrant-count) payout / hero / WWXRP table dispatch indexed by a NEW
`_countGoldQuadrants(uint32 ticket) private pure returns (uint8 count)` helper operating
directly on the packed `uint32` ticket; the broken `_evNormalizationRatio` runtime corrector
(L808-851 at v36 baseline) is DELETED with its single call site, and 4 single-table + 2
normalizer constants are replaced with 25 per-N packed constants
(5 × `QUICK_PLAY_PAYOUTS_N{0..4}_PACKED` + 5 × `QUICK_PLAY_PAYOUT_N{0..4}_M8` +
5 × `HERO_BOOST_N{0..4}_PACKED` + 5 × `WWXRP_FACTORS_N{0..4}_PACKED`) — net constant count
11 → 24. Hero match is symbol-only per quadrant (HERO_PENALTY 9500 / HERO_SCALE 10000
unchanged). The producer callsite at L607 (now L629 post-rewrite) swaps from
`packedTraitsFromSeed` to `packedTraitsDegenerette`. `_distributePayout` is rewritten with a
5-arg signature `(player, currency, betAmount, payout, rngWord)` (uint128 `betAmount` inserted
between `currency` and `payout`) and a 3-tier ETH split rule per PAY-SPLIT-01..03:
≤3× bet pays 100% ETH; 3-10× bet pays 2.5× bet ETH floor + remainder lootbox; >10× bet pays
the existing 25/75 split; the existing `ETH_WIN_CAP_BPS = 1_000` (10% of futurePool) cap takes
precedence on top of all three tiers. CURRENCY_BURNIE + CURRENCY_WWXRP branches and the
frozen-pool solvency-check posture are byte-unchanged. 25 packed constants verified
byte-identical to `derive_5_tables.py` Fraction-exact stdout (Task 2 evidence: PASS_ALL_25).
Mint + Jackpot + Lootbox + EntropyLib + JackpotBucketLib + GameStorage `git diff` empty
across the phase. 18 of 18 Phase 267 requirements PASS at phase close.
Tests + audit deliverable + closure flips DEFERRED to Phase 268 (STAT-01..07 + SURF-01..06)
+ Phase 271 (AUDIT-01..06 + REG-01..04 + closure signal).

## Per-Task Atomic-Commit Log

| #  | Subject                                                                                                                                | SHA short | AGENT/USER                          | Files (counts)                                                                                          |
| -- | -------------------------------------------------------------------------------------------------------------------------------------- | --------- | ----------------------------------- | ------------------------------------------------------------------------------------------------------- |
| 0  | `docs(267): create phase plan — 1 plan / 4 tasks (Degenerette producer + 5-table payout rewrite + 3-tier ETH split)`                   | 719af2cb  | AGENT-COMMITTED                     | `.planning/phases/267-…/267-01-PLAN.md` (1 file)                                                        |
| 1  | `chore(267): docs upstream fixes for v37.0 phase 267 [DGN-01, DGN-03, PAY-SPLIT, STAT-07, AUDIT-04]`                                    | 39f6bba3  | AGENT-COMMITTED                     | REQUIREMENTS.md (DGN-01 visibility + DGN-03 signature), ROADMAP.md (success criterion 1 + Phase 271 AUDIT-04 attestation language), STATE.md (begin-phase carry) |
| 2  | `chore(267): constants verification — derive_5_tables.py byte-identity proof [D-267-CONSTVERIFY-01]`                                    | 3291c00a  | AGENT-COMMITTED                     | `.planning/phases/267-…/267-01-CONSTANTS-VERIFY.md` (NEW; 25/25 grep-pairs PASS_ALL_25)                  |
| 3  | `feat(267): degenerette producer + 5-table payout rewrite + 3-tier ETH split [DGN-01..15, PAY-SPLIT-01..03]`                           | e1136071  | **USER-APPROVED batched**           | `contracts/DegenerusTraitUtils.sol` (additive: +45 LOC) + `contracts/modules/DegenerusGameDegeneretteModule.sol` (+231/-196 LOC) |
| 4  | `docs(267): phase 267 summary + commit-readiness register`                                                                              | _this_     | AGENT-COMMITTED                     | `.planning/phases/267-…/267-01-SUMMARY.md` (NEW) + `.planning/STATE.md` (Phase 267 SHIPPED flips)        |

(Roadmap progress + REQUIREMENTS traceability flips for Phase 267 → 1/1 Complete are
recorded by the orchestrator via `gsd-sdk roadmap.update-plan-progress 267` +
`gsd-sdk requirements.mark-complete DGN-01 DGN-02 … PAY-SPLIT-03` after this commit lands.)

## Per-REQ Tally (18 of 18 PASS)

| REQ ID       | File evidence                                                              | Verifying grep recipe                                                                                                  | ✓ |
| ------------ | -------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- | - |
| DGN-01       | `contracts/DegenerusTraitUtils.sol:201`                                   | `grep -nE "function packedTraitsDegenerette\(uint256 [a-z]+\) internal pure returns \(uint32\)" contracts/DegenerusTraitUtils.sol` | ✓ |
| DGN-02       | `contracts/modules/DegenerusGameDegeneretteModule.sol` (zero hits at HEAD) | `grep -nE "_evNormalizationRatio" contracts/modules/DegenerusGameDegeneretteModule.sol  # expect 0`                    | ✓ |
| DGN-03       | `contracts/modules/DegenerusGameDegeneretteModule.sol:859`                | `grep -nE "function _countGoldQuadrants\(uint32 ticket\) private pure returns \(uint8 count\)" contracts/modules/DegenerusGameDegeneretteModule.sol` | ✓ |
| DGN-04       | `contracts/modules/DegenerusGameDegeneretteModule.sol:1041`               | `grep -nE "function _getBasePayoutBps\(uint8 N, uint8 matches\)" contracts/modules/DegenerusGameDegeneretteModule.sol` | ✓ |
| DGN-05       | `contracts/modules/DegenerusGameDegeneretteModule.sol:254-258`            | `grep -cE "QUICK_PLAY_PAYOUTS_N[0-4]_PACKED" contracts/modules/DegenerusGameDegeneretteModule.sol  # expect >= 5`      | ✓ |
| DGN-06       | `contracts/modules/DegenerusGameDegeneretteModule.sol:262-266`            | `grep -cE "QUICK_PLAY_PAYOUT_N[0-4]_M8" contracts/modules/DegenerusGameDegeneretteModule.sol  # expect >= 5`           | ✓ |
| DGN-07       | `contracts/modules/DegenerusGameDegeneretteModule.sol:1007`               | `grep -nE "function _applyHeroMultiplier" contracts/modules/DegenerusGameDegeneretteModule.sol  # symbol-only branch`  | ✓ |
| DGN-08       | `contracts/modules/DegenerusGameDegeneretteModule.sol:337-341`            | `grep -cE "HERO_BOOST_N[0-4]_PACKED" contracts/modules/DegenerusGameDegeneretteModule.sol  # expect >= 5`              | ✓ |
| DGN-09       | `contracts/modules/DegenerusGameDegeneretteModule.sol:920`                | `grep -nE "function _wwxrpFactor\(uint8 N, uint8 bucket\)" contracts/modules/DegenerusGameDegeneretteModule.sol`       | ✓ |
| DGN-10       | `contracts/modules/DegenerusGameDegeneretteModule.sol:281-285`            | `grep -cE "WWXRP_FACTORS_N[0-4]_PACKED" contracts/modules/DegenerusGameDegeneretteModule.sol  # expect >= 5`           | ✓ |
| DGN-11       | `contracts/modules/DegenerusGameDegeneretteModule.sol` (zero hits at HEAD) | `grep -cE "QUICK_PLAY_BASE_PAYOUTS_PACKED\|QUICK_PLAY_BASE_PAYOUT_8_MATCHES\|WWXRP_BONUS_FACTOR_BUCKET[5-8]\|HERO_BOOST_PACKED " contracts/modules/DegenerusGameDegeneretteModule.sol  # expect 0` | ✓ |
| DGN-12       | `contracts/modules/DegenerusGameDegeneretteModule.sol:629`                | `grep -nE "DegenerusTraitUtils\.packedTraitsDegenerette\(resultSeed\)" contracts/modules/DegenerusGameDegeneretteModule.sol` | ✓ |
| DGN-13       | `contracts/modules/DegenerusGameDegeneretteModule.sol:236, 241, 269, 275, 304-306, 932-934` | `grep -cE "99\.99% RTP\|all weights=10\|EXACT EV NORMALIZATION" contracts/modules/DegenerusGameDegeneretteModule.sol  # expect 0` | ✓ |
| DGN-14       | `contracts/DegenerusTraitUtils.sol` (existing 3 functions byte-identical) | `git diff 1c0f0913..HEAD -- contracts/DegenerusTraitUtils.sol \| grep -E "^[+-].*function (weightedColorBucket\|traitFromWord\|packedTraitsFromSeed)"  # expect empty` | ✓ |
| DGN-15       | `contracts/storage/GameStorage.sol` byte-identical                         | `git diff 1c0f0913..HEAD -- contracts/storage/GameStorage.sol  # expect empty` AND `git diff 1c0f0913..HEAD -- contracts/ \| grep -E "^\+.*function .* (public\|external)" \| grep -vE "internal\|private"  # expect empty` | ✓ |
| PAY-SPLIT-01 | `contracts/modules/DegenerusGameDegeneretteModule.sol:736-741`            | `grep -nE "if \(payout <= threeBet\)" contracts/modules/DegenerusGameDegeneretteModule.sol  # tier-1 100% ETH branch`  | ✓ |
| PAY-SPLIT-02 | `contracts/modules/DegenerusGameDegeneretteModule.sol:746-749`            | `grep -nE "uint256 minEth = \(uint256\(betAmount\) \* 5\) / 2" contracts/modules/DegenerusGameDegeneretteModule.sol  # 2.5× bet floor` | ✓ |
| PAY-SPLIT-03 | `contracts/modules/DegenerusGameDegeneretteModule.sol:771-779`            | `grep -nE "ETH_WIN_CAP_BPS\|PayoutCapped" contracts/modules/DegenerusGameDegeneretteModule.sol  # pool-cap precedence after split` | ✓ |

**Cross-check:** `task4_phase_close` canonical_grep_recipes from
`267-01-PLAN.md` frontmatter:

```
test -f .planning/phases/267-…/267-01-SUMMARY.md && grep -c "DGN-01" SUMMARY.md   # expect >= 1 ✓
grep -cE "PAY-SPLIT-0[1-3]" SUMMARY.md                                            # expect >= 3 ✓
grep -c "Phase 267 SHIPPED" .planning/STATE.md                                     # expect 1   ✓
```

All three pass.

## Cross-Phase Forward Cross-Cites

Phase 267 ships contracts only; empirical verification + cross-surface byte-identity
+ audit deliverable + closure-signal emission live downstream:

| Forward consumer    | Coverage                                                                                                                                | Verifies Phase 267 evidence                                       |
| ------------------- | --------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------- |
| Phase 268 STAT-01   | Per-N basePayoutEV exactness (≥ 1M draws per N; assert 100.00 ± 0.50 centi-x)                                                            | DGN-04, DGN-05, DGN-06 (5-table dispatch + per-N calibration)      |
| Phase 268 STAT-02   | Producer chi² uniformity for `packedTraitsDegenerette` per-quadrant color distribution `[16,16,16,16,16,16,16,8]/120`                   | DGN-01 (D-267-DIST-01 producer)                                    |
| Phase 268 STAT-03   | Bonus EV (WWXRP factor) exactness per N — assert 5.000% ± 0.10% per N                                                                   | DGN-09, DGN-10 (per-N WWXRP factors at 10/30/30/30 split)          |
| Phase 268 STAT-04   | Match-count distribution P_N(M) histogram per N — assert binomial-convolution shape                                                     | DGN-03 (`_countGoldQuadrants` N-index correctness)                 |
| Phase 268 STAT-05   | On-chain dispatch byte-identity vs `derive_5_tables.py` (catches paste / bit-rot drift the script-grep cannot detect)                    | DGN-05, DGN-06, DGN-08, DGN-10 (25 packed constants)               |
| Phase 268 STAT-06   | Symbol-only hero match P(hero) = 1/8 uniform per quadrant                                                                               | DGN-07 (D-267-HERO-01 symbol-only)                                 |
| Phase 268 STAT-07   | ETH split-rule distribution validation across all per-N basePayout × roiBps × hero × WWXRP-bonus combos; boundary-gaming sweep at 3.0× | PAY-SPLIT-01, PAY-SPLIT-02, PAY-SPLIT-03 (3-tier rule)             |
| Phase 268 SURF-01   | TraitUtils existing 3 functions byte-identical                                                                                          | DGN-14                                                             |
| Phase 268 SURF-02   | JackpotModule v34 gold-solo + 4 ETH-distribution injection sites + JackpotBucketLib byte-identical                                      | DGN-15                                                             |
| Phase 268 SURF-03   | LootboxModule byte-identical at Phase 267 close (LBX cleanup is Phase 269)                                                              | DGN-15                                                             |
| Phase 268 SURF-04   | EntropyLib API + body byte-identical (v36.0 ENT-04 carry)                                                                                | DGN-15                                                             |
| Phase 268 SURF-05   | SurfaceRegression test extension covering all of the above (re-pinning of Phase 261/264 gas-pin drift is Phase 269)                     | DGN-14, DGN-15                                                     |
| Phase 268 SURF-06   | advanceGame gas envelope — derive theoretical worst-case FIRST per `feedback_gas_worst_case.md`, then test                              | DGN-04, DGN-07, DGN-09 (per-N dispatch added)                      |
| Phase 271 AUDIT-01  | §3.A delta-surface row enumeration including TraitUtils + DegeneretteModule + 25-constant rewrite + 3-tier `_distributePayout` rewrite  | All 18 Phase 267 requirements                                      |
| Phase 271 AUDIT-02  | 8-surface adversarial sweep — surfaces (a)–(h); surface (h) = ETH split-rule monotonicity + boundary-gaming                              | All 18 Phase 267 requirements                                      |
| Phase 271 AUDIT-03  | Conservation re-proof — ETH / BURNIE / DGNRS / WWXRP / Tickets / Boon / Solvency / Bucket-share-sum × pool                              | DGN-15 + PAY-SPLIT-03 (cap-flip preserves total payout invariant) |
| Phase 271 AUDIT-04  | Zero-new-state attestation — storage-slot scan + GameStorage byte-identity + zero new public/external/admin/modifier; ZERO new external pure entries (`packedTraitsDegenerette` is `internal pure` per D-267-VISIBILITY-01; "ALLOWED-NEW-STATELESS-ENTRY" phrasing dropped per Task 1 fix) | DGN-15 + DGN-01                                                    |
| Phase 271 AUDIT-05  | KNOWN-ISSUES.md walkthrough — EXC-01..03 NEGATIVE-scope at v37; EXC-04 RE_VERIFIED with NARROWS retained from v36 (BAF-jackpot-only)    | DGN-12 (Degenerette producer swap doesn't widen EXC-04 scope)      |
| Phase 271 AUDIT-06  | Closure signal `MILESTONE_V37_AT_HEAD_<sha>` emitted in §9c per D-267-CLOSURE-01                                                         | All 18 Phase 267 requirements (rolled into milestone closure)      |
| Phase 271 REG-01    | v36.0 closure signal `MILESTONE_V36_AT_HEAD_1c0f09132d7439af9881c56fe197f81757f8164a` re-verified non-widening                          | DGN-15                                                             |
| Phase 271 REG-02    | v34.0 closure signal `MILESTONE_V34_AT_HEAD_6b63f6d4daf346a53a1d463790f637308ea8d555` re-verified non-widening                          | DGN-14, DGN-15                                                     |
| Phase 271 REG-03    | KI envelope re-verifications carried from v36                                                                                            | DGN-12, DGN-15                                                     |
| Phase 271 REG-04    | Prior-finding spot-check sweep across `audit/FINDINGS-v25.0.md` → `audit/FINDINGS-v36.0.md`                                              | All 18 Phase 267 requirements                                      |

## Locked Decisions Honored

- **D-267-SCOPE-01** — Degenerette only; existing `weightedColorBucket` / `traitFromWord` / `packedTraitsFromSeed` byte-identical. Mint + Jackpot + v34 gold-solo paths UNTOUCHED. ✓
- **D-267-DIST-01** — Producer color widths `[16,16,16,16,16,16,16,8]/120` via base-15 scaling `scaled = uint32((uint64(uint32(rnd)) * 15) >> 32)` then `scaled == 14 ? 7 : scaled >> 1`; symbol uniform 1/8. Visible in `_degTrait` body (`contracts/DegenerusTraitUtils.sol:218-228`). ✓
- **D-267-NORM-01** — `_evNormalizationRatio` and its single call site DELETED (`grep -c _evNormalizationRatio` → 0 at HEAD). ✓
- **D-267-EV-TARGET-01** — Each per-N table satisfies `Σ P_N(M) × payout(M) = exactly 100 centi-x` (script verification: drift ±0.0003 bps at HEAD; 267-01-CONSTANTS-VERIFY.md L160-165). ✓
- **D-267-EV-PRECISION-01** — M=4/M=5/M=6 cascade absorbs residual; M=8 monotonic in N (107,564 / 125,830 / 147,929 / 175,123 / 209,164). ✓
- **D-267-HERO-01** — Symbol-only hero match; HERO_PENALTY (9500) and HERO_SCALE (10000) UNCHANGED (visible at `_applyHeroMultiplier` body). ✓
- **D-267-HERO-02** — 5 separate `HERO_BOOST_N{0..4}_PACKED` tables, M=2..7 packed in 96 bits each (16 bits per multiplier). ✓
- **D-267-WWXRP-SPLIT-01** — 10/30/30/30 split across buckets 5/6/7/8 preserved; 5 separate `WWXRP_FACTORS_N{0..4}_PACKED` tables (4 × 64-bit factors per uint256). ✓
- **D-267-PRODUCER-API-01** — Existing 3 TraitUtils functions byte-identical; new `packedTraitsDegenerette` additive only. ✓
- **D-267-COUNTGOLD-01** — `_countGoldQuadrants(uint32 ticket) private pure returns (uint8 count)` operates directly on the packed `uint32` ticket. REQUIREMENTS.md DGN-03 wording corrected in Task 1. ✓
- **D-267-VISIBILITY-01** — `packedTraitsDegenerette` is `internal pure` (mirrors `packedTraitsFromSeed`); ZERO new public selector. REQUIREMENTS.md DGN-01 + ROADMAP success criteria + Phase 271 AUDIT-04 attestation language ("ALLOWED-NEW-STATELESS-ENTRY" dropped) corrected in Task 1. ✓
- **D-267-PAYSPLIT-01** — Tier 1: `payout <= threeBet` → 100% ETH (visible at `_distributePayout` body L737-741). ✓
- **D-267-PAYSPLIT-02** — Tier 2 + Tier 3 via `ethShare = max(2.5*betAmount, payout/4)`; bands meet at `payout = 10 * bet` (visible at L745-749). ✓
- **D-267-PAYSPLIT-03** — Pool-cap (`ETH_WIN_CAP_BPS = 1_000` = 10% of futurePool) takes PRECEDENCE over the 3-tier split in the unfrozen branch (visible at L771-779). NatSpec at L711-715 documents precedence. ✓
- **D-267-PAYSPLIT-04** — Scope = ETH-currency Degenerette quickPlay only; CURRENCY_BURNIE (`coin.mintForGame(player, payout)` at L793) and CURRENCY_WWXRP (`wwxrp.mintPrize(player, payout)` at L795) byte-unchanged. ✓
- **D-267-PAYSPLIT-05** — `_distributePayout` 5-arg signature `(address player, uint8 currency, uint128 betAmount, uint256 payout, uint256 rngWord)` (declaration at L725-731); L656 call site updated to pass `amountPerTicket` (now at L678). ✓
- **D-267-PLAN-01** — Single multi-task plan with 4 atomic-commit tasks (1 USER-APPROVED contract + 3 AGENT-COMMITTED chore/planning). ✓
- **D-267-CONSTVERIFY-01** — Three-part: (1) `derive_5_tables.py` re-run captured into 267-01-CONSTANTS-VERIFY.md; (2) 25 grep-assertions byte-identical (PASS_ALL_25 verdict); (3) Phase 268 STAT-05 empirical re-verification deferred. ✓
- **D-267-COMMENTS-01** — NatSpec-first + surgical inline rewrite; ZERO history prose ("was/used to/previously/formerly/changed from/removed/deleted") in rewritten regions. Block headers L235-251 / L253-268 / L314-322 rewritten as fresh per-N table headers; L239 RTP claim + L262 weights=10 + L287-298 EXACT EV NORMALIZATION prose + L316 HERO_BOOST_PACKED reference all rewritten in language of CURRENT design. ✓
- **D-267-APPROVAL-02** — Task 3 batched contract diff presented at `checkpoint:human-verify` gate; agent waited for explicit `approved` string before committing. Agent did NOT pre-approve. ✓
- **D-267-CLOSURE-01** — Closure signal `MILESTONE_V37_AT_HEAD_<sha>` deferred to Phase 271 §9c. Phase 267 records placeholder only. ✓
- **D-267-CLOSURE-02** — TWO-subsection commit-readiness register format (§i USER-APPROVED contracts + §ii USER-APPROVED tests + §iii AGENT-COMMITTED planning artifacts; NO §iv awaiting-approval subsection). See "Commit-Readiness Register" section below. ✓

## Project-Feedback-Rules Honored

| Rule                                       | How Phase 267 honored it                                                                                                          |
| ------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------- |
| `feedback_no_contract_commits.md`          | Task 3 contract diff awaited explicit user `approved` string before commit; ALL contract changes batched into ONE commit (e1136071). |
| `feedback_batch_contract_approval.md`      | Single batched diff for the entire phase contract change (TraitUtils additive + DegeneretteModule rewrite combined into e1136071). |
| `feedback_never_preapprove_contracts.md`   | Agent did NOT claim pre-approval for any contract change at any task gate. Task 3 explicitly waited at `checkpoint:human-verify`.  |
| `feedback_wait_for_approval.md`            | Explicit `approved` string captured at Task 3 gate before any `git add` of contract files.                                         |
| `feedback_no_history_in_comments.md`       | NatSpec + inline comments in rewritten regions describe the CURRENT design only; ZERO "was/used to/previously/formerly/changed from/removed/deleted" prose anywhere in TraitUtils additions or DegeneretteModule rewrite. Tripwire grep at Task 3 verification returned 0 matches in touched regions. |
| `feedback_manual_review_before_push.md`    | Agent did NOT `git push` at any task gate. Pre-push human review reserved for user.                                                |
| `feedback_skip_research_test_phases.md`    | Research phase skipped per CONTEXT.md as source of truth (paste-ready Solidity + locked decisions + 25 packed constants byte-values pre-rendered in `.planning/notes/2026-05-10-degenerette-payout-recalibration.md`); jumped straight to plan + execute. |
| `feedback_contract_locations.md`           | All contract reads + edits used `contracts/` paths only — no stale copy elsewhere consulted.                                      |
| `feedback_contractaddresses_policy.md`     | N/A — Phase 267 did not touch `contracts/ContractAddresses.sol`.                                                                  |
| `feedback_no_dead_guards.md`               | N/A for Phase 267 — lootbox dead-branch cleanup is Phase 269. (No new dead guards introduced; threshold/floor multipliers kept inline as literal `* 3` and `(* 5) / 2` per CONTEXT.md preference.) |
| `feedback_rng_backward_trace.md`           | RNG-relevant surface = producer change (Degenerette only). Backward-trace verified at Task 3 review: per-quadrant 64-bit lanes consume `rand >> 0/64/128/192` from a single `resultSeed` (already standard Degenerette VRF flow); no commitment-window changes. Phase 271 AUDIT-02 surface (b) will re-verify symbol-only hero match correctness. |
| `feedback_rng_commitment_window.md`        | No commitment-window changes (player input commitment unchanged; result seed derived from existing VRF flow at L587-621). Producer swap at L629 is post-VRF; no new player-controllable state between request and fulfillment. |
| `feedback_gas_worst_case.md`               | Theoretical-worst-case derivation deferred to Phase 268 SURF-06 (gold-counter 4-iter loop + 5-case dispatch + 5 packed-constant SLOAD-equivalents); empirical pin to follow the theoretical bound. Phase 267 ships contracts only. |
| `feedback_test_rnglock.md`                 | N/A for Phase 267 — Phase 267 ships zero test changes. (Testing is Phase 268; rnglock removal from coinflip claim paths is unrelated to v37.0 scope.) |

## Commit-Readiness Register (per D-267-CLOSURE-02 carry)

### §i USER-APPROVED contracts (1 commit)

| SHA short | Subject                                                                                                            | Files                                                                                              | Approval evidence                                              |
| --------- | ------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------- | -------------------------------------------------------------- |
| e1136071  | `feat(267): degenerette producer + 5-table payout rewrite + 3-tier ETH split [DGN-01..15, PAY-SPLIT-01..03]`        | `contracts/DegenerusTraitUtils.sol` (additive +45 LOC) + `contracts/modules/DegenerusGameDegeneretteModule.sol` (+231/-196 LOC) | User explicit `approved` string captured at Task 3 `checkpoint:human-verify` gate. |

### §ii USER-APPROVED tests (0 commits)

Phase 267 ships **zero** test changes. All v37.0 test work (STAT-01..07 + SURF-01..06) is
owned by Phase 268. This subsection intentionally has zero rows at Phase 267 close.

### §iii AGENT-COMMITTED planning artifacts (4 commits)

| SHA short | Subject                                                                                                              | Files                                                                                            |
| --------- | -------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| 719af2cb  | `docs(267): create phase plan — 1 plan / 4 tasks (Degenerette producer + 5-table payout rewrite + 3-tier ETH split)` | `.planning/phases/267-…/267-01-PLAN.md`                                                          |
| 39f6bba3  | `chore(267): docs upstream fixes for v37.0 phase 267 [DGN-01, DGN-03, PAY-SPLIT, STAT-07, AUDIT-04]`                  | `.planning/REQUIREMENTS.md`, `.planning/ROADMAP.md`, `.planning/STATE.md`                         |
| 3291c00a  | `chore(267): constants verification — derive_5_tables.py byte-identity proof [D-267-CONSTVERIFY-01]`                  | `.planning/phases/267-…/267-01-CONSTANTS-VERIFY.md`                                              |
| _this_     | `docs(267): phase 267 summary + commit-readiness register`                                                           | `.planning/phases/267-…/267-01-SUMMARY.md`, `.planning/STATE.md`                                  |

**No §iv awaiting-approval subsection** — Phase 267 closes with zero pending items per
D-267-CLOSURE-02 carry. Tests + audit deliverable + closure-signal emission are explicit
deferrals to downstream phases (268 / 271), not pending-approval debt.

## Open Items / Deferrals

Phase 267 ships contracts only. Downstream phases own:

- **Phase 268 — Degenerette Statistical Validation + Cross-Surface Preservation:** STAT-01..07 (per-N EV exactness + producer chi² + bonus EV + match-count histogram + on-chain dispatch byte-identity vs `derive_5_tables.py` + symbol-only hero P=1/8 + ETH split-rule distribution validation) + SURF-01..06 (TraitUtils existing functions + JackpotModule + LootboxModule + EntropyLib + SurfaceRegression extension + advanceGame gas envelope per `feedback_gas_worst_case.md`). 12 requirements; depends on Phase 267.
- **Phase 269 — Lootbox Dead-Branch Cleanup + SURF-05 Gas-Pin Re-Pinning:** LBX-01..03 (delete unreachable BURNIE-conversion branch in `_resolveLootboxRoll` L1568-1581) + GASPIN-01..03 (root-cause + fix Phase 261/264 SURF-05 ~120K gas-pin drift under `npm run test:stat` ordering). 6 requirements; independent maintenance.
- **Phase 270 — Post-v32.0 Deferred-Commit Adversarial Sub-Audit:** DELTA-01..04 (audit-only sweep of commits `002bde55` + `2713ce61`; read-only delta-classification + KI envelope check). 4 requirements; audit-only.
- **Phase 271 — Delta Audit + Findings Consolidation (Terminal):** AUDIT-01..06 + REG-01..04 (single `audit/FINDINGS-v37.0.md` 9-section deliverable; closure signal `MILESTONE_V37_AT_HEAD_<sha>` emitted in §9c; KNOWN-ISSUES.md walkthrough; ROADMAP/STATE/MILESTONES milestone-level closure flips). 10 requirements; depends on Phase 267, 268, 269, 270.

Milestone-level closure (closure signal `MILESTONE_V37_AT_HEAD_<sha>` + KNOWN-ISSUES.md
walkthrough + audit deliverable + ROADMAP/STATE/MILESTONES milestone-level demotion + final
user-review gate) DEFERRED to Phase 271. Phase 267 closes only at the plan level.

## Closure Signal

```
pending-phase-271
```

The terminal milestone closure signal `MILESTONE_V37_AT_HEAD_<sha>` will be emitted in
`audit/FINDINGS-v37.0.md` §9c at Phase 271 close per D-267-CLOSURE-01. Phase 267 records
this as the carry target only.

## Notes

- **Single batched contract commit discipline.** Per
  `feedback_no_contract_commits.md` + `feedback_batch_contract_approval.md` +
  `feedback_never_preapprove_contracts.md` + `feedback_wait_for_approval.md`,
  the Task 3 diff combined `contracts/DegenerusTraitUtils.sol` (additive new
  helpers) and `contracts/modules/DegenerusGameDegeneretteModule.sol` (full
  per-N rewrite + `_distributePayout` 3-tier ETH split + `betAmount` threading
  + 4 stale-comment surface rewrites) into a single diff presented at the
  `checkpoint:human-verify` gate. User typed `approved`, the agent committed,
  did NOT push. Mirrors the v36 Phase 266 single-batched-commit precedent.

- **Agent-committed planning artifacts.** Tasks 1, 2, 4 (this commit) touch
  only `.planning/` files and were AGENT-COMMITTED autonomous per `write_policy`.
  Task 1 (`39f6bba3`) batched all 6 REQUIREMENTS.md edits + 4 ROADMAP.md edits
  into a single chore commit; Task 2 (`3291c00a`) wrote `267-01-CONSTANTS-VERIFY.md`
  with the full `derive_5_tables.py` stdout + 25 grep-pair byte-identity assertions
  (PASS_ALL_25 verdict) which UNBLOCKED Task 3 per D-267-CONSTVERIFY-01.

- **Constants verification BLOCKED Task 3 on any mismatch.** Per D-267-CONSTVERIFY-01,
  the 25 packed constants must match `derive_5_tables.py` byte-for-byte (Fraction-exact
  Python derivation; no FP drift). At HEAD: 25 of 25 PASS. Phase 268 STAT-05 will
  empirically re-verify on-chain dispatch produces `basePayoutEV = 100.00 ± 0.50
  centi-x` per N over ≥1M draws (catches paste / bit-rot drift the script-grep
  cannot detect).

- **`_distributePayout` 3-tier split rule — boundary discontinuity at 3.0× bet.**
  At exactly `payout = 3.0 × bet`, ethShare = 3.0 × bet (Tier 1 inclusive); at
  `payout = 3.01 × bet`, ethShare = 2.5 × bet (Tier 2 floor). The 3.0× → 2.5×
  ETH drop at 3.01× is the documented design tradeoff per D-267-PAYSPLIT-01:
  much smaller than the alternative `3.0× → 0.7525×` drop under naive 25%
  split. Phase 271 AUDIT-02 surface (h) will sweep the boundary for
  payout-multiple gaming exploits.

- **Pool-cap precedence applies AFTER the split rule in the unfrozen branch.**
  Per D-267-PAYSPLIT-03, if computed `ethShare > pool * ETH_WIN_CAP_BPS / 10_000`,
  the excess flips to lootbox: `lootboxShare += ethShare - maxEth; ethShare = maxEth;
  emit PayoutCapped(player, ethShare, lootboxShare);`. A thin-pool cap-flip can
  convert a sub-3× bet payout into a partial-ETH-partial-lootbox split
  (preserves the `ethShare + lootboxShare = payout` invariant). Frozen-pool
  branch retains its existing solvency-check posture (full ethShare debited
  from pending future pool with revert-on-insufficient).

- **Cross-surface byte-identity preserved.** `git diff 1c0f0913..HEAD` empty for
  `contracts/modules/DegenerusGameMintModule.sol`,
  `contracts/modules/DegenerusGameJackpotModule.sol`,
  `contracts/modules/DegenerusGameLootboxModule.sol`,
  `contracts/libraries/EntropyLib.sol`,
  `contracts/libraries/JackpotBucketLib.sol`,
  `contracts/storage/GameStorage.sol`. Phase 268 SURF-01..04 will assert the
  same in the test harness.

- **Zero new public ABI surface.** Per D-267-VISIBILITY-01, `packedTraitsDegenerette`
  is `internal pure` on a `library` declaration → inlined into the consumer at
  compile time. ZERO new function selector. Phase 271 AUDIT-04 attestation will
  drop the v34/v35/v36 "ALLOWED-NEW-STATELESS-ENTRY" phrasing in favor of
  "ZERO new external pure entries added" per the Task 1 ROADMAP correction.

## Self-Check: PASSED

Verifications performed before recording PASSED:

- `267-01-SUMMARY.md` exists at `.planning/phases/267-degenerette-producer-5-table-payout-rewrite/267-01-SUMMARY.md` (file written this task).
- `grep -c "DGN-01" 267-01-SUMMARY.md` → ≥ 1.
- `grep -cE "PAY-SPLIT-0[1-3]" 267-01-SUMMARY.md` → ≥ 3.
- `grep -c "Phase 267 SHIPPED" .planning/STATE.md` → 1 (set by this task's STATE update).
- All 4 task commits referenced exist in git log:
  - `git log --oneline 39f6bba3 -1` → `chore(267): docs upstream fixes for v37.0 phase 267 [DGN-01, DGN-03, PAY-SPLIT, STAT-07, AUDIT-04]`.
  - `git log --oneline 3291c00a -1` → `chore(267): constants verification — derive_5_tables.py byte-identity proof [D-267-CONSTVERIFY-01]`.
  - `git log --oneline e1136071 -1` → `feat(267): degenerette producer + 5-table payout rewrite + 3-tier ETH split [DGN-01..15, PAY-SPLIT-01..03]`.
  - `git log --oneline 719af2cb -1` → `docs(267): create phase plan — 1 plan / 4 tasks (Degenerette producer + 5-table payout rewrite + 3-tier ETH split)`.
- TWO-subsection commit-readiness register present (§i / §ii / §iii); §iv intentionally absent per D-267-CLOSURE-02.
- All 18 requirement IDs (DGN-01..15 + PAY-SPLIT-01..03) appear in the per-REQ tally and in the frontmatter `requirements-completed` array.
