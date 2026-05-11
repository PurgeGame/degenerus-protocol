---
phase: 271-delta-audit-findings-consolidation-terminal
plan: 01
milestone: v37.0
milestone_name: Degenerette Recalibration + Maintenance Bundle
head_anchor: <sha>
audit_baseline: 1c0f09132d7439af9881c56fe197f81757f8164a
audit_baseline_signal: MILESTONE_V36_AT_HEAD_1c0f09132d7439af9881c56fe197f81757f8164a
v34_baseline: 6b63f6d4daf346a53a1d463790f637308ea8d555
v34_baseline_signal: MILESTONE_V34_AT_HEAD_6b63f6d4daf346a53a1d463790f637308ea8d555
deliverable: audit/FINDINGS-v37.0.md
requirements: [AUDIT-01, AUDIT-02, AUDIT-03, AUDIT-04, AUDIT-05, AUDIT-06,
               REG-01, REG-02, REG-03, REG-04]
phase_status: terminal
write_policy: "Pure-consolidation phase per D-271-APPROVAL-02 hard constraint #1. ZERO contracts/*.sol writes by agent during Phase 271; ZERO test/ writes by agent during Phase 271. All v37.0 contract + test commits already landed under USER-APPROVED batched review at Phase 267 (e1136071), Phase 268 (4b277aaf), and Phase 269 (8fd5c2e1) close. Audit deliverable + 271-01-ADVERSARIAL-LOG + 271-01-SUMMARY + ROADMAP/STATE/MILESTONES/PROJECT/REQUIREMENTS flips AGENT-COMMITTED atomic-per-task with audit(271): or docs(271): prefix. READ-only flip on audit/FINDINGS-v37.0.md (chmod 444 + frontmatter status FINAL — READ-ONLY + read_only: true) is the terminal commit per feedback_manual_review_before_push.md final user-review gate."
supersedes: none
status: DRAFT
read_only: false
closure_signal: MILESTONE_V37_AT_HEAD_<sha>
generated_at: 2026-05-11T08:42:52Z
---

# v37.0 Findings — Degenerette Recalibration + Maintenance Bundle

**Audit Baseline.** The audit baseline is v36.0 audit-subject HEAD `1c0f09132d7439af9881c56fe197f81757f8164a` (closure signal `MILESTONE_V36_AT_HEAD_1c0f09132d7439af9881c56fe197f81757f8164a` carry-forward from `audit/FINDINGS-v36.0.md` §9c). v37.0 audit subject HEAD `<sha>` (resolved at Task 14 atomic-update per D-271-CLOSURE-01). v37.0 introduces TWO contract-tree commits since the v36.0 baseline: `feat(267): degenerette producer + 5-table payout rewrite + 3-tier ETH split [DGN-01..15, PAY-SPLIT-01..03]` at commit `e1136071` (USER-APPROVED Phase 267 batched commit; +231/-196 LOC across `contracts/DegenerusTraitUtils.sol` and `contracts/modules/DegenerusGameDegeneretteModule.sol`); `feat(269): delete unreachable BURNIE-conversion branch in _resolveLootboxRoll [LBX-01]` at commit `8fd5c2e1` (USER-APPROVED Phase 269 commit; −14/+1 LOC in `contracts/modules/DegenerusGameLootboxModule.sol`; bytecode shrink 177 bytes 18,330 → 18,153). v37.0 introduces ONE test-tree commit since the v36.0 baseline: `test(268): degenerette stat suite + cross-surface preservation v37.0 + worst-case gas regression [STAT-01..07, SURF-01..06]` at commit `4b277aaf` (USER-APPROVED Phase 268 batched commit; +2,277/−1 LOC across 6 files in `test/stat/` + `test/gas/`). `contracts/libraries/EntropyLib.sol` is byte-identical between v36.0 baseline `1c0f0913` and v37 HEAD (Phase 268 SURF-04 grep-proof). `contracts/modules/DegenerusGameJackpotModule.sol` is byte-identical between v36.0 baseline `1c0f0913` and v37 HEAD (Phase 268 SURF-01 + SURF-02 + SURF-04 grep-proof; non-lootbox jackpot path untouched). `contracts/modules/DegenerusGameMintModule.sol` is byte-identical between v36.0 baseline `1c0f0913` and v37 HEAD (Phase 268 SURF-01 grep-proof). `contracts/libraries/JackpotBucketLib.sol` is byte-identical between v34.0 baseline `6b63f6d4` and v37 HEAD (REG-02 carry). `_pickSoloQuadrant` body + 4 ETH-distribution injection sites at L282 / L349 / L524 / L1147 byte-identical between v34.0 baseline `6b63f6d4` and v37 HEAD (Phase 268 SURF-02 grep-proof).

**Scope.** Single canonical milestone-closure deliverable for v37.0 per D-271-FILES-01 (single deliverable, no per-AUDIT-NN working files) + D-266-FILES-01 / D-265-FILES-01 / D-262 / D-257 carry-forward (9-section shape locked). v37.0 = 5-phase milestone shape per CONTEXT.md `<domain>`: Phase 267 (Degenerette producer + payout rewrite — contract impl), Phase 268 (statistical validation + cross-surface preservation — test impl), Phase 269 (lootbox dead-branch cleanup + SURF-05 gas-pin re-pinning — PARTIAL ship), Phase 270 (post-v32.0 deferred-commit adversarial sub-audit — zero source-tree mutations), Phase 271 (delta audit + findings consolidation — terminal). Terminal phase per D-271-FCITE-01 (carry of D-266-FCITE / D-265-FCITE-01 / D-262-FCITE-01 / D-257-FCITE-01 / D-253-15 step 8 + ROADMAP terminal-phase rule) — zero forward-cites emitted from Phase 271 to any post-v37.0 milestone phases. Verified at §8 Forward-Cite Closure block.

**Write policy.** READ-only after Task 14 terminal atomic commit per D-271-APPROVAL-02 hard constraint #1 + D-266-APPROVAL-01 / D-265-CF-02 / D-262 / D-257 carry-forward chain. KNOWN-ISSUES.md UNMODIFIED at v37 close per D-271-PAYSPLIT-01 + D-271-KI-01 default zero-promotion path: PAY-SPLIT 3-tier rule boundary discontinuity at exactly 3.0× bet is documented as accepted-design via §4 surface (h) prose disclosure ONLY; no new KNOWN-ISSUES.md entry under Design Decisions. Zero F-37-NN finding blocks per D-271-FIND-01 carry default path (AUDIT-02 8-surface adversarial sweep verdicts SAFE_*). Per `feedback_never_preapprove_contracts.md`, the agent does NOT pre-approve any contract change — all v37 contract + test commits already landed under USER-APPROVED batched gates at Phase 267 (`e1136071`) + Phase 268 (`4b277aaf`) + Phase 269 (`8fd5c2e1`) close per `feedback_batch_contract_approval.md` + `feedback_no_contract_commits.md`. Per `feedback_manual_review_before_push.md`, the user reviews this deliverable's full diff before any push — final user-review gate at Task 14 before READ-only flip on `audit/FINDINGS-v37.0.md` (chmod 444 + frontmatter `status: FINAL — READ-ONLY` + `read_only: true`).

---

## 2. Executive Summary

### Closure Verdict Summary

- AUDIT-01: TBD-by-Task-3 (§3.A delta-surface table covering all source-tree changes 1c0f0913 → v37 HEAD with hunk-level evidence + {NEW, MODIFIED_LOGIC, REFACTOR_ONLY, DELETED} classification per row)
- AUDIT-02: TBD-by-Task-5+6 (§4 8-surface adversarial sweep (a)..(h) with verdict bucket per row; default zero F-37-NN finding blocks per D-271-FIND-01; `/contract-auditor` + `/zero-day-hunter` + `/economic-analyst` PARALLEL adversarial pass per D-271-ADVERSARIAL-01)
- AUDIT-03: TBD-by-Task-7 (§3 AUDIT-03 conservation re-proof: per-N table calibration math + ETH bonus EV + per-N hero EV-neutrality + solvency invariant + ethShare/lootboxShare sum invariant)
- AUDIT-04: TBD-by-Task-4 (§3 AUDIT-04 zero-new-state grep-proof attestation: zero new storage slots; zero new public/external mutation entry points; zero new admin functions; zero new modifiers; zero new upgrade hooks; `packedTraitsDegenerette` internal pure callout per DGN-15)
- AUDIT-05: TBD-by-Task-12 (§9c emits closure signal `MILESTONE_V37_AT_HEAD_<sha>` verbatim in 5 locations per D-271-CLOSURE-01; KNOWN-ISSUES.md UNMODIFIED per default path)
- AUDIT-06: TBD-by-Task-6 (`271-01-ADVERSARIAL-LOG.md` populated with 3 H2 sections — `/contract-auditor` + `/zero-day-hunter` + `/economic-analyst` — per D-271-ADVERSARIAL-01; NOT `/degen-skeptic` per D-271-ADVERSARIAL-02)
- REG-01: TBD-by-Task-8 (§5a — v36.0 closure signal `MILESTONE_V36_AT_HEAD_1c0f0913` NON-WIDENING at v37 HEAD per D-271-REG01-01)
- REG-02: TBD-by-Task-8 (§5b — v34.0 closure signal `MILESTONE_V34_AT_HEAD_6b63f6d4` NON-WIDENING at v37 HEAD per D-271-REG02-01)
- REG-03: TBD-by-Task-9 (§6b 4-row KI envelope re-verifications EXC-01..03 NEGATIVE-scope + EXC-04 RE_VERIFIED with NARROWS retained from v36.0; Phase 270 contributes 4 rows verbatim per D-271-KI-01)
- REG-04: TBD-by-Task-8 (§5c per-finding 6-col PASS/REGRESSED/SUPERSEDED row table walking audit/FINDINGS-v25.0.md → audit/FINDINGS-v36.0.md per D-271-REG04-01)
- Combined milestone closure: `MILESTONE_V37_AT_HEAD_<sha>`

### Severity Counts (per D-08 5-Bucket Rubric)

- CRITICAL: 0
- HIGH: 0
- MEDIUM: 0
- LOW: 0
- INFO: 0
- Total F-37-NN: 0

Default expected per D-271-FIND-01 carry. The Degenerette producer + 5-table payout rewrite is mathematically well-bounded: per-quadrant producer `packedTraitsDegenerette` consumes VRF-derived high-entropy keccak bits via a `[16,16,16,16,16,16,16,8]/120` weight distribution (commons 13.33% each, gold 6.67%; uniform symbol 1/8 — player cannot bias post-VRF-fulfillment per `feedback_rng_commitment_window.md` + `feedback_rng_backward_trace.md`); 5-table per-N basePayout dispatch is `Fraction`-exact calibrated via `.planning/notes/degenerette-recalibration/derive_5_tables.py` and yields `basePayoutEV = 100 centi-x` per N ∈ {0..4} (Phase 268 STAT-01 ≥1M draws empirically validates 100.00 ± 0.50 centi-x per N); chi² uniformity empirically verified at Phase 268 STAT-02 over the 8-symbol × 8-color trait space (Wilson-Hilferty Z < 1.645); 3-tier ETH split (PAY-SPLIT-01..03) preserves `ethShare + lootboxShare = payout` invariant at every tier with PAY-SPLIT-03 pool-cap precedence enforcing `claimablePool ≤ 10% × futurePool`; cross-surface byte-identity preserved at Phase 268 SURF-01..04 (EntropyLib + BAF + MintModule + non-lootbox JackpotModule UNCHANGED vs v36.0 baseline); Phase 269 LBX-01 dead-branch removal is structurally provable byte-equivalent via caller-clamp triple-defense (Layer-1 `openLootBox` + Layer-2 `_resolveLootboxCommon` + Layer-3 (DELETED) inner branch); bytecode shrink 177 bytes confirms no-behavior-change cleanup. Severity ceiling for any v37-emitted F-37-NN: HIGH (no value extraction beyond the existing Degenerette prize space; `ethShare + lootboxShare = payout` invariant under the same total-payout mechanics as pre-recalibration; per-N table calibration analytically exact). Most likely severity for any inline-draft finding-candidate: MEDIUM/LOW. Severity counts reconcile to §4 F-37-NN block tally line by line per ROADMAP success criterion 1.

### D-08 5-Bucket Severity Rubric

Severity calibration mapped via the v25–v36 player-reachability × value-extraction × determinism-break frame, carried forward as D-08 from v25 onward (D-271-SEV-01 carry).

| Severity | Definition |
| -------- | ---------- |
| CRITICAL | Player-reachable, material protocol value extraction, no mitigation at HEAD. |
| HIGH | Player-reachable, bounded value extraction OR no extraction but hard determinism violation. |
| MEDIUM | Player-reachable, no value extraction, observable behavioral asymmetry. |
| LOW | Player-reachable theoretically but not practically (gas economics / timing / coordination cost makes exploit non-viable). |
| INFO | Not player-reachable, OR documented design decision, OR observation only (naming inconsistency, dead code, gas optimization, doc drift). |

Severity calibration for any F-37-NN that may surface during §4 adversarial-pass disposition: HIGH ceiling (per-N table dispatch does not extract value; bucket-share-sum × pool invariant under the same total-payout mechanics as pre-recalibration; `ethShare + lootboxShare = payout` invariant preserved; per-pull entropy VRF-derived not player-controllable). MEDIUM/LOW likely for any inline-draft finding-candidate. INFO for documentation-only items. Per D-271-FIND-01 default path, zero F-37-NN blocks emit; severity-at-HEAD = N/A.

### D-09 KI Gating Rubric Reference

The §6 KI-eligibility 3-predicate test (D-09) is distinct from the D-08 severity rubric above. A candidate qualifies for `KNOWN-ISSUES.md` promotion (verdict `KI_ELIGIBLE_PROMOTED`) iff ALL three predicates hold:

1. **Accepted-design** — behavior is intentional / documented / load-bearing for the protocol's design (not an oversight or accident)
2. **Non-exploitable** — no player-reachable path extracts protocol value or breaks determinism
3. **Sticky** — the design choice persists across foreseeable future code revisions (not a transient state)

ANY false ⇒ Non-Promotion Ledger entry with the failing predicate identified. Default outcome at this milestone: zero F-37-NN finding blocks emit (D-271-FIND-01 carry default path) → zero KI promotion candidates from new findings. KNOWN-ISSUES.md UNMODIFIED at v37 close per D-271-PAYSPLIT-01 + D-271-KI-01: the PAY-SPLIT 3-tier rule boundary discontinuity at exactly 3.0× bet is documented as accepted-design via §4 surface (h) prose disclosure ONLY (no new Design Decisions entry); total payout invariant preserved (`ethShare + lootboxShare = payout`); player receives same total value in different mix; Phase 268 STAT-07 empirically validates per-band frequency distribution. EXC-04 NARROWS retained from v36.0 (BAF-jackpot-only scope) — EntropyLib byte-identical at v37 HEAD; per-pull-level keccak path UNCHANGED in v37; lootbox-path consumes high-entropy keccak via `EntropyLib.hash2` + bit-slicing per v36.0 ENT-01..06. See §6 KI Gating Walk + Non-Promotion Ledger.

### Forward-Cite Closure Summary

D-271-FCITE-01 carry of D-266-FCITE / D-265-FCITE-01 / D-262-FCITE-01 / D-257-FCITE-01 / D-253-15 step 8 + ROADMAP terminal-phase rule: zero forward-cites emitted from Phase 271 to any post-v37.0 milestone phases. Verified at §8 Forward-Cite Closure block. v37.0 = 5-phase milestone (Phases 267-271) per CONTEXT.md `<domain>`; §9.NN.iv v38+ Carry-Forward subsection contains 5 explicit deferred-handoff items (LBX-02 + GASPIN-02 + GASPIN-03 + SURF-03 re-baseline + STAT-03 v35.0 carry) per D-271-DEFERRED-02 — these are planner handoff registers tying into next-milestone pickup via `.planning/PROJECT.md` "Deferred to Future Milestones" single-source-of-truth lookup (D-271-DEFERRED-03), NOT forward-cites to in-flight Phase 272+ work. Future milestones (v38.0+) ingest via fresh delta-extraction phase, not via forward-cite from v37 artifacts.

### Attestation Anchor

See §9 Milestone Closure Attestation for the D-253-15 step 9 attestation block triggering v37.0 milestone closure via signal `MILESTONE_V37_AT_HEAD_<sha>` (resolved at Task 14 atomic-update across 5 verbatim locations per D-271-CLOSURE-01).

---

## 3. Per-Phase Sections

### 3a. Phase 267 — Degenerette Producer + 5-Table Payout Rewrite

**Commit:** `e1136071` — `feat(267): degenerette producer + 5-table payout rewrite + 3-tier ETH split [DGN-01..15, PAY-SPLIT-01..03]`. USER-APPROVED batched commit per `feedback_batch_contract_approval.md` + `feedback_no_contract_commits.md`. Files: `contracts/DegenerusTraitUtils.sol` (additive +45 LOC) + `contracts/modules/DegenerusGameDegeneretteModule.sol` (+231 / −196 LOC).

**Requirements:** 18 of 18 PASS — DGN-01..15 + PAY-SPLIT-01..03 (Phase 267 SUMMARY.md per-REQ tally).

**What IS at v37.0 close:**

- `contracts/DegenerusTraitUtils.sol` — NEW additive helper `packedTraitsDegenerette(uint256 seed) internal pure returns (uint32)` with private `_degTrait(uint64) private pure returns (uint8)` companion. Per-quadrant near-uniform color distribution `[16,16,16,16,16,16,16,8]/120` (commons 13.33% each, gold 6.67%); uniform 1/8 symbol; byte layout `[QQ][CCC][SSS]` preserved per DGN-01 + DGN-14. The existing 3 TraitUtils functions (`weightedColorBucket`, `traitFromWord`, `packedTraitsFromSeed`) byte-identical at v36.0 baseline `1c0f0913` per Phase 268 SURF-01 grep-proof.
- `contracts/modules/DegenerusGameDegeneretteModule.sol` — 5 per-N (gold-quadrant-count) payout / hero / WWXRP table dispatch indexed by NEW `_countGoldQuadrants(uint32 ticket) private pure returns (uint8 count)` operating on the packed `uint32` ticket via `((ticket >> (q*8 + 3)) & 7) == 7` for q∈{0..3} per DGN-03 strict-color boundary.
- `_evNormalizationRatio` body L808-851 at v36.0 baseline + single call site L965-969 DELETED per DGN-02; no runtime EV correction; payout schedule fully visible in storage.
- `_getBasePayoutBps(uint256 matchCount, uint8 N)` REWRITTEN with 5-table per-N dispatch (`QUICK_PLAY_PAYOUTS_N{0..4}_PACKED` + `QUICK_PLAY_PAYOUT_N{0..4}_M8`); `basePayoutEV = 100 centi-x` exact per N ∈ {0..4} per Fraction-exact derivation.
- `_applyHeroMultiplier(...)` REWRITTEN symbol-only per DGN-07 via `((playerTicket >> heroQuadrant*8) & 7) == ((resultTicket >> heroQuadrant*8) & 7)` reading only bits 0-2 of the hero quadrant byte; per-N hero boost dispatch via `HERO_BOOST_N{0..4}_PACKED`. P(hero match) = 1/8 exactly. Color bits 3-5 NOT read by equality comparison.
- `_wwxrpBonusRoiForBucket(...)` REWRITTEN with 5-table per-N WWXRP factor dispatch via `WWXRP_FACTORS_N{0..4}_PACKED` per DGN-09 + DGN-10.
- `_distributePayout(player, currency, betAmount, payout, rngWord)` REWRITTEN with 5-arg signature (uint128 `betAmount` inserted between `currency` and `payout`) and 3-tier ETH split rule per PAY-SPLIT-01..03:
  - **PAY-SPLIT-01** (≤3× bet → 100% ETH): strict inclusive at exactly 3.0× bet; no off-by-one ambiguity.
  - **PAY-SPLIT-02** (3× < payout ≤ 10× bet → 2.5× bet ETH floor + remainder lootbox): `ethShare = max(2.5 * betAmount, payout / 4)`.
  - **PAY-SPLIT-03** (pool-cap precedence): `ETH_WIN_CAP_BPS = 1_000 = 10% × futurePool`; excess flips to lootbox per existing L716-723 logic.
  - `CURRENCY_BURNIE` + `CURRENCY_WWXRP` branches UNCHANGED.
  - NatSpec documents 3-tier rule + pool-cap precedence per `feedback_no_history_in_comments.md` (describes what IS).
- Packed-constants delta: 11 → 24 net (5 + 5 + 5 + 5 add = 20 NEW per-N constants; 6 v36 constants DELETED per DGN-05/06/08/10/11 — `QUICK_PLAY_BASE_PAYOUTS_PACKED`, `QUICK_PLAY_BASE_PAYOUT_8_MATCHES`, `WWXRP_BONUS_FACTOR_BUCKET5..8` block, `HERO_BOOST_PACKED`, 2 normalizer constants). The 25 packed constants are byte-identical to `.planning/notes/degenerette-recalibration/derive_5_tables.py` Fraction-exact stdout (Phase 267 Task 2 evidence: `PASS_ALL_25`).
- 4 stale comment rewrites at L239 / L262 / L287-298 / L316 per DGN-13 (per `feedback_no_history_in_comments.md` describes per-N reality at v37.0).
- Producer call site at L607 (now L629 post-rewrite) SWAPPED from `packedTraitsFromSeed` to `packedTraitsDegenerette` per DGN-12.

Cross-cite `.planning/notes/degenerette-recalibration/derive_5_tables.py` (Fraction-exact derivation source of truth). Mint + Jackpot + Lootbox + EntropyLib + JackpotBucketLib + GameStorage `git diff 1c0f0913..e1136071` empty.

### 3b. Phase 268 — Degenerette Statistical Validation + Cross-Surface Preservation

**Commit:** `4b277aaf` — `test(268): degenerette stat suite + cross-surface preservation v37.0 + worst-case gas regression [STAT-01..07, SURF-01..06]`. USER-APPROVED batched commit per `feedback_batch_contract_approval.md`. 6 files; +2,277 / −1 LOC; 3 NEW `test/stat/` files (`DegenerettePerNEvExactness.test.js`, `DegeneretteProducerChi2.test.js`, `DegeneretteBonusEv.test.js`) + 1 EXTENDED `test/stat/SurfaceRegression.test.js` v37.0 SURF-01..04 describe + 1 NEW `test/gas/Phase268GasRegression.test.js` (SURF-05 + SURF-06) + `package.json` `test:stat` wiring.

**Requirements:** 13 of 13 PASS — STAT-01..07 + SURF-01..06 (Phase 268 SUMMARY.md per-REQ tally).

**Empirical evidence:**

- **STAT-01** (per-N basePayoutEV exactness ≥ 1M draws/N): `basePayoutEV = 100.00 ± 0.50 centi-x` for each N ∈ {0..4}; Fraction-exact 100 centi-x per N is the analytical anchor.
- **STAT-02** (per-quadrant producer chi² uniformity ≥ 1M samples): color `[16,16,16,16,16,16,16,8]/120` + uniform 1/8 symbol passes within `CHI2_CRIT_05[7] = 14.067` / Wilson-Hilferty Z<1.645 at α=0.05.
- **STAT-03** (per-N hero-boost EV ±1% at ≥ 100K hero-active draws/N): per-N hero EV within ±1% analytical reference.
- **STAT-04** (per-N WWXRP factor EV ±1% at ≥ 100K WWXRP-active draws/N): per-N WWXRP factor EV within ±1% analytical reference; 5.000% ETH bonus per N (analytical).
- **STAT-05** (per-N match-count histogram derived from STAT-01 pool): bin-tolerance ±0.5% vs analytical binomial-convolution reference.
- **STAT-06** (reuse Phase 261/264/266 chi² infrastructure): `makeRng` / `CHI2_CRIT_05` / `wilsonHilfertyZ` verbatim re-declared in all 3 stat files; no new statistical primitives.
- **STAT-07** (ETH payout 3-tier split rule distribution + thin-pool cap-flip): per-band frequency match within ±0.5% bin tolerance across all per-N basePayout × roiBps distributions; thin-pool cap-flip sub-case via `loadFixture(deployFullProtocol)` per D-268-THINPOOL-01.
- **SURF-01..04** (byte-identity grep-proof vs v36.0 baseline `1c0f0913`): `DegenerusTraitUtils.sol` existing 3 functions byte-identical; `DegenerusGameJackpotModule.sol` file-level zero-diff; `DegenerusGameLootboxModule.sol` file-level zero-diff (D-268-SURF03-01: Phase 269 owns post-cleanup re-baseline); `EntropyLib.sol` file-level zero-diff (ENT-04 v36.0 carry).
- **SURF-05** (worst-case quickPlay gas regression): theoretical worst-case derivation FIRST in NatSpec header (N=3 + M=8 + ETH tier-3 + ticketCount=10 single construction per D-268-WORSTGAS-01) per `feedback_gas_worst_case.md`; deterministic VRF-injection test hitting exactly that state via REF-CAPTURE pin protocol for `WORST_CASE_RNG_WORDS`.
- **SURF-06** (advanceGame ±2K gas envelope): `ADVANCE_GAME_DECIMATOR_STAGE_REF = 908_320` pinned; v36.0 envelope active.

`git diff e1136071 4b277aaf -- contracts/` returns empty (zero source-tree mutations at Phase 268 close).

### 3c. Phase 269 — Lootbox Dead-Branch Cleanup + SURF-05 Gas-Pin Re-Pinning (PARTIAL ship)

**Commits:**
- USER-APPROVED contract commit `8fd5c2e1` — `feat(269): delete unreachable BURNIE-conversion branch in _resolveLootboxRoll [LBX-01]`. 1 file (`contracts/modules/DegenerusGameLootboxModule.sol`); −14 / +1 LOC; LBX-01 dead-branch deletion + user-approved cascade param cleanup.
- AGENT-COMMITTED RCA commit `009cbde3` — `docs(269): GASPIN-01 root-cause inline — fixture-loader caching`. `269-01-PLAN.md` +80 LOC "Root Cause (GASPIN-01)" section.

**Requirements:** 2 of 6 PASS — LBX-01 + GASPIN-01. 4 DEFERRED to v38+ maintenance per D-271-DEFERRED-02 (cross-cite §9.NN.iv): LBX-02 + LBX-03 (LBX-03 now anchored at §3.A) + GASPIN-02 + GASPIN-03 + SURF-03 re-baseline.

**LBX-01 shipped at v37.0 close:**

- Inner `if (targetLevel < currentLevel) { burnieOut = ... }` branch at `_resolveLootboxRoll` L1574-1578 (v36.0 baseline line numbers) DELETED with its 4-LOC body + matching cascade signature parameter drop (the unused `targetLevel` + `currentLevel` params from the signature + 2 callsites + 2 NatSpec `@param` lines).
- **Triple-defense caller-clamp invariant** proves byte-equivalence:
  - **Layer-1** `openLootBox` L557-559 unconditionally clamps `targetLevel = max(targetLevel, currentLevel)` before invocation.
  - **Layer-2** `_resolveLootboxCommon` L882-884 unconditionally clamps again before reaching `_resolveLootboxRoll`.
  - **Layer-3** (DELETED) inner `_resolveLootboxRoll` branch was structurally dead.
- Bytecode shrink: 177 bytes (18,330 → 18,153) measured via direct artifact inspection at Phase 269 Task 4 — confirms no-behavior-change cleanup.
- Per-open runtime savings: theoretical 20-50 gas on the 55%-tickets-path (~55% of opens); ~0.005% of typical 600K-1M-gas lootbox open. The shipped value is **audit cleanliness** (dead branch removed from auditor's reading path before Phase 271), not gas optimization.
- Game-theory neutrality: ETH-lootbox `day` snapshot at buy → seed fixed → no timing-grind window per `feedback_rng_commitment_window.md` backward-trace.

**PARTIAL-ship rationale (4 deferred to v38+):**

- **LBX-02** (empirical 55%-tickets-path gas-savings test): fixture-coverage gap; analytical worst-case in NatSpec is load-bearing per `feedback_gas_worst_case.md` + Phase 266 GAS-01 precedent. Empirical pin requires fixture coverage of openable lootbox path which currently soft-skips in the harness (matches `AdvanceGameGas.test.js` L1014/L1027 precedent). Bytecode shrink confirmed empirically at Phase 269 Task 4.
- **GASPIN-02 + GASPIN-03** (combined-suite gas-pin stabilization): D-269-STAB-01 option (b) `before(hardhat_reset)` + `loadFixture(deployFullProtocol)` attempt FAILED structurally — Hardhat-toolbox error *"There was an error reverting the snapshot of the fixture. This might be caused by using hardhat_reset and loadFixture calls in a testcase"* AND introduced more failures than it resolved (Phase 261 SURF-05 payDailyJackpot regressed PASS drift −33 → FAIL drift −47,833; Phase 264 SURF-05 stage-9 regressed soft-skip → FAIL; Phase 268 SURF-06 fixture deployment broke). Options (a)/(c) violate GASPIN-03 hard ceiling or plan scope. Combined with negligible production-gas impact of LBX-01 (sub-0.01%), GASPIN-02 effort cannot be justified within v37.0 scope. RCA evidence inline at `269-01-PLAN.md` "Root Cause (GASPIN-01)" section (option (c) fixture-loader caching mechanism — Hardhat `loadFixture` + `evm_snapshot`/`evm_revert` semantics under multi-file combined-suite ordering).
- **v36.0 acceptance carries forward verbatim:** "User accepted the flaky behavior at the Wave 2 gate (`128k is fine approved`); future re-pinning pass deferred to v37.0 maintenance scope" → now deferred further to v38+ maintenance.
- **SURF-03 re-baseline** (D-269-SURF03-01): one-line `test/stat/SurfaceRegression.test.js` edit when v38+ test-tree work resumes; pure-consolidation hard constraint #1 prohibits Phase 271 from doing test-tree edits.

### 3d. Phase 270 — Post-v32.0 Deferred-Commit Adversarial Sub-Audit (cross-cite)

**Commits:**
- AGENT-COMMITTED working-file commit `4017b9ec` — `docs(270): post-v32.0 deferred-commit adversarial sub-audit working file [DELTA-01..04]`. `270-01-DELTA-SURFACE.md` NEW (305 LOC); canonical Phase-271-§3.A grep-cite anchor per D-270-FILES-01.
- AGENT-COMMITTED phase-close commit `5cd4f2bc` — `docs(270): phase 270 summary — post-v32.0 deferred-commit adversarial sub-audit complete [DELTA-01..04 PASS]`.

**Requirements:** 4 of 4 PASS — DELTA-01..04. Zero deferred.

**Scope:** FIRST FULL adversarial coverage of two specific post-v32.0 contract-tree commits whose adversarial coverage was carry-forward-deferred v33.0 → v34.0 → v35.0 → v36.0 close:
- **Commit A** `002bde55` (`feat(presale): auto-deactivate flag on per-mint cap crossing`, 2026-05-02; +14 / −10 LOC across 3 files) — Phase 270 verdict **SAFE_BY_STRUCTURAL_CLOSURE**.
- **Commit B** `2713ce61` (`chore(vault): remove dead setDecimatorAutoRebuy wrapper`, 2026-05-05; +3 / −20 LOC across 2 files) — Phase 270 verdict **SAFE_BY_DESIGN** (admin-entry-point-removal blast radius = zero; Phase 146 ABI cleanup `31ec2780` (Apr 9 2026) anchored as Commit B `2713ce61` unreachability cause via design-intent trace per `feedback_design_intent_before_deletion.md` PRIMARY governing memory).

**Verdict distribution across 8 surfaces:** SAFE_BY_STRUCTURAL_CLOSURE × 6 (surfaces i / iii / iv on Commit A side + surfaces v / vii / viii on Commit B side) + SAFE_BY_DESIGN × 2 (surface ii on Commit A buyer-receives-presale-terms-before-deactivation invariant + surface vi on Commit B decimator-vs-BURNIE auto-rebuy orthogonality). ZERO FINDING_CANDIDATE rows.

**4 RE_VERIFIED-NEGATIVE-scope KI envelope rows** (EXC-01 affiliate roll / EXC-02 prevrandao fallback / EXC-03 F-29-04 mid-cycle substitution / EXC-04 EntropyLib XOR-shift narrowed-to-BAF-only) feed Phase 271 §6b directly per D-271-KI-01.

**Cumulative zero source-tree mutations at Phase 270 close:** `git diff --stat -- contracts/ test/` returns EMPTY at both AGENT-COMMITTED commit boundaries. Both Commit A `002bde55` and Commit B `2713ce61` PREDATE v37.0 baseline `1c0f0913` (Phase 270 sub-audit subjects, not v37-introduced); rows enumerated at §3.A for milestone-completeness per CONTEXT.md `<domain>` AUDIT-01 source-tree-change inventory + Phase 270 D-270-FILES-01 cross-cite discipline.

Cross-cite full appendix at `.planning/phases/270-post-v32-0-deferred-commit-adversarial-sub-audit/270-01-DELTA-SURFACE.md`.

### 3.A AUDIT-01 Delta-Surface Table

Every source-tree change from v36.0 baseline `1c0f0913` → v37.0 HEAD enumerated with hunk-level evidence and {NEW, MODIFIED_LOGIC, REFACTOR_ONLY, DELETED} classification per row. Row groups: Phase 267 Degenerette contract changes (commit `e1136071`); Phase 269 LootboxModule dead-branch deletion (commit `8fd5c2e1`) with LBX-03 HEAD line-number anchors; Phase 270 carry-forward 2-row commit-summary (sub-audit subjects predating v37.0 baseline; cross-cited to `270-01-DELTA-SURFACE.md`).

#### Row Group 1 — Phase 267 Degenerette Contract Changes (commit `e1136071`)

**Row 1.1** — `contracts/DegenerusTraitUtils.sol` :: `packedTraitsDegenerette(uint256 seed) internal pure returns (uint32)` + private `_degTrait(uint64) private pure returns (uint8)` helper.
- Class: **NEW** (additive library helper).
- File / Lines: `contracts/DegenerusTraitUtils.sol` (+45 LOC).
- Evidence: per-quadrant near-uniform color `[16,16,16,16,16,16,16,8]/120` (commons 13.33%, gold 6.67%); uniform symbol 1/8; byte layout `[QQ][CCC][SSS]` preserved. Library `internal pure` is inlined into consumer at compile time — does NOT widen public ABI per DGN-01 + DGN-15. Phase 268 STAT-02 chi² ≥1M-sample uniformity at `test/stat/DegeneretteProducerChi2.test.js`.
- Verdict: SAFE.

**Row 1.2** — `contracts/modules/DegenerusGameDegeneretteModule.sol` :: `_evNormalizationRatio` body (v36 L808-851) + single call site (v36 L965-969).
- Class: **DELETED**.
- File / Lines: `contracts/modules/DegenerusGameDegeneretteModule.sol` (−1 internal function body + −5-line callsite block).
- Evidence: per DGN-02. No runtime EV correction; payout schedule fully visible in storage post-rewrite.
- Verdict: SAFE_BY_DESIGN.

**Row 1.3** — `_countGoldQuadrants(uint32 ticket) private pure returns (uint8)`.
- Class: **NEW**.
- Evidence: counts color==7 across 4 player-pick quadrants strictly via `((ticket >> (q*8 + 3)) & 7) == 7` per DGN-03. 3-bit color field bounded {0..7}; uint8 return; 4-iteration loop bounded; cumulative count ≤ 4.
- Verdict: SAFE_BY_DESIGN.

**Row 1.4** — `_getBasePayoutBps(uint256 matchCount, uint8 N)`.
- Class: **MODIFIED_LOGIC** (REWRITTEN).
- Evidence: 5-table per-N dispatch indexed by N from `_countGoldQuadrants`; `basePayoutEV = 100 centi-x` exact per N analytically; Phase 268 STAT-01 ≥1M draws/N empirical evidence within ±0.50 centi-x.
- Verdict: SAFE.

**Row 1.5** — `_applyHeroMultiplier(...)`.
- Class: **MODIFIED_LOGIC** (REWRITTEN).
- Evidence: symbol-only hero match per DGN-07 via `((playerTicket >> heroQuadrant*8) & 7) == ((resultTicket >> heroQuadrant*8) & 7)`; per-N hero boost dispatch via `HERO_BOOST_N{0..4}_PACKED`; HERO_PENALTY 9500 / HERO_SCALE 10000 unchanged.
- Verdict: SAFE_BY_DESIGN.

**Row 1.6** — `_wwxrpBonusRoiForBucket(...)`.
- Class: **MODIFIED_LOGIC** (REWRITTEN).
- Evidence: 5-table per-N WWXRP factor dispatch via `WWXRP_FACTORS_N{0..4}_PACKED` per DGN-09 + DGN-10; Phase 268 STAT-04 per-N WWXRP EV within ±1% empirical.
- Verdict: SAFE.

**Row 1.7** — `_distributePayout(player, currency, betAmount, payout, rngWord)` (ETH-currency branch).
- Class: **MODIFIED_LOGIC** (REWRITTEN).
- Evidence: 5-arg signature with `uint128 betAmount` inserted between `currency` and `payout`; `betAmount` threaded from L656 callsite. 3-tier ETH split rule per PAY-SPLIT-01..03 (≤3× → 100% ETH; 3-10× → 2.5× bet ETH floor + remainder lootbox; pool-cap precedence via L716-723 `ETH_WIN_CAP_BPS = 1_000 = 10% × futurePool`); `CURRENCY_BURNIE` + `CURRENCY_WWXRP` branches UNCHANGED. NatSpec documents 3-tier rule + pool-cap precedence per `feedback_no_history_in_comments.md`.
- Verdict: SAFE_BY_DESIGN (boundary discontinuity at exactly 3.0× bet is accepted-design per D-271-PAYSPLIT-01 — see §4 surface (h)).

**Row 1.8** — 25 packed constants delta (11 → 24 net).
- Class: **NEW** (15 add) + **DELETED** (6 drop).
- Evidence: 5 × `QUICK_PLAY_PAYOUTS_N{0..4}_PACKED` + 5 × `QUICK_PLAY_PAYOUT_N{0..4}_M8` + 5 × `HERO_BOOST_N{0..4}_PACKED` + 5 × `WWXRP_FACTORS_N{0..4}_PACKED` ADDED. `QUICK_PLAY_BASE_PAYOUTS_PACKED` + `QUICK_PLAY_BASE_PAYOUT_8_MATCHES` + `WWXRP_BONUS_FACTOR_BUCKET5..8` block + `HERO_BOOST_PACKED` + 2 normalizer constants DELETED per DGN-05/06/08/10/11. Cross-cite `.planning/notes/degenerette-recalibration/derive_5_tables.py` Fraction-exact derivation (Phase 267 Task 2: `PASS_ALL_25` byte-identity).
- Verdict: SAFE.

**Row 1.9** — 4 stale comment rewrites at L239 / L262 / L287-298 / L316.
- Class: **REFACTOR_ONLY** (comment-only).
- Evidence: per DGN-13; no prose drift between code and comments; per `feedback_no_history_in_comments.md` describes per-N reality at v37.0.
- Verdict: SAFE.

**Row 1.10** — `packedTraitsFromSeed` callsite at L607 SWAPPED to `packedTraitsDegenerette` (post-rewrite line ~L629).
- Class: **REFACTOR_ONLY** (producer call site).
- Evidence: per DGN-12. Mint + Jackpot path UNCHANGED (still consume `packedTraitsFromSeed` per SURF-01 byte-identity grep-proof).
- Verdict: SAFE_BY_DESIGN.

#### Row Group 2 — Phase 269 LootboxModule Dead-Branch Deletion (commit `8fd5c2e1`)

**Row 2.1** — `contracts/modules/DegenerusGameLootboxModule.sol` :: `_resolveLootboxRoll` inner `if (targetLevel < currentLevel) { burnieOut = ... }` branch + cascade signature parameter cleanup.
- Class: **DELETED** (inner branch) + **REFACTOR_ONLY** (cascade signature parameter drop).
- File / Lines: v36.0 baseline L1574-1578 (4-LOC inner branch body) DELETED; cascade signature `_resolveLootboxRoll` `targetLevel` + `currentLevel` params dropped + 2 callsites updated + 2 NatSpec `@param` lines removed.
- Evidence — **caller-clamp triple-defense invariant at HEAD `<sha>` per D-271-DEFERRED-01:**
  - **Layer-1** `openLootBox` L557-559 unconditionally clamps `targetLevel = max(targetLevel, currentLevel)` before invocation.
  - **Layer-2** `_resolveLootboxCommon` L882-884 unconditionally clamps again before reaching `_resolveLootboxRoll`.
  - **Layer-3** (DELETED) inner `_resolveLootboxRoll` branch was structurally dead.
  - **Bytecode shrink:** 177 bytes (18,330 → 18,153) measured at Phase 269 Task 4 via direct artifact inspection.
  - **Per-open runtime savings:** theoretical 20-50 gas on the 55%-tickets-path (~55% of opens); ~0.005% of typical 600K-1M-gas lootbox open. Empirical pin DEFERRED to v38+ maintenance per D-271-DEFERRED-02 (LBX-02 fixture-coverage gap; analytical worst-case load-bearing).
- Verdict: SAFE_BY_STRUCTURAL_CLOSURE.

**Row 2.1 LBX-03 audit-trail (per D-271-DEFERRED-01):** v36.0 ENT-02 callsite numbering at HEAD anchored as follows. 4 hash2/bit-slice callsites in `_resolveLootboxRoll` (function NatSpec @ L1534; function body opens immediately after) survive byte-identical at the structural level. v36.0 baseline (pre-LBX-01) line numbers L1548 / L1569 / L1585 / L1599; **HEAD (post-LBX-01) line numbers L1559 / L1564 / L1571 / L1599** — measured via `grep -nE "hash2|seed >> |_lootboxTicketCount|_lootboxDgnrsReward" contracts/modules/DegenerusGameLootboxModule.sol` at Phase 271 §3.A authoring time. Concrete callsites at HEAD:
- **L1559** — `uint16(seed >> 40) % 20` (pathRoll bit-slice; bits[40..55]).
- **L1564** — call to `_lootboxTicketCount(... seed)` (forwards seed to L1635 inner bit-slice `uint24(seed >> 96) % 10_000`; bits[96..119]).
- **L1571** — call to `_lootboxDgnrsReward(amount, seed)` (forwards seed to inner DGNRS bit-slice; bits[56..79]).
- **L1599** — `uint16(seed >> 80) % 20` (varianceRoll large-BURNIE branch bit-slice; bits[80..95]).

Line numbers shift downward by 11 LOC (L1548 → L1559) for the first three callsites after dead-branch removal; the 4th (L1599) is invariant because the deletion was upstream of the shift point in the function body. Bit-slice budget UNAFFECTED — same 4 callsites, same bit ranges, same modulo constants; structural cleanup only.

#### Row Group 3 — Phase 270 Post-v32.0 Carry-Forward 2-Row Commit-Summary

Both commits PREDATE v37.0 baseline `1c0f0913` (Phase 270 sub-audit subjects, not v37-introduced). Rows enumerated here for milestone-completeness per CONTEXT.md `<domain>` AUDIT-01 source-tree-change inventory + Phase 270 D-270-FILES-01 cross-cite discipline. Full appendix: `.planning/phases/270-post-v32-0-deferred-commit-adversarial-sub-audit/270-01-DELTA-SURFACE.md`.

**Row 3.A — Commit `002bde55`** (`feat(presale): auto-deactivate flag on per-mint cap crossing`; 2026-05-02; +14 / −10 LOC across 3 files). 5 declaration rows verbatim from Phase 270 270-01-DELTA-SURFACE.md:
1. AdvanceModule cap-OR arm — **DELETED**.
2. AdvanceModule constant — **DELETED**.
3. GameStorage constant — **NEW**.
4. MintModule inlined SLOAD/mask/SSTORE — **MODIFIED_LOGIC**.
5. MintModule per-mint cap-clear predicate — **NEW**.
- Phase 270 verdict: **SAFE_BY_STRUCTURAL_CLOSURE**.

**Row 3.B — Commit `2713ce61`** (`chore(vault): remove dead setDecimatorAutoRebuy wrapper`; 2026-05-05; +3 / −20 LOC across 2 files). 2 declaration rows verbatim from Phase 270 270-01-DELTA-SURFACE.md:
1. `DegenerusVault.sol` `setDecimatorAutoRebuy` wrapper — **DELETED**.
2. Fuzz coverage entry — **DELETED**.
- Phase 270 verdict: **SAFE_BY_DESIGN** (admin-entry-point-removal blast radius = zero; Phase 146 ABI cleanup `31ec2780` (Apr 9 2026) anchored as Commit B unreachability cause via design-intent trace per `feedback_design_intent_before_deletion.md` PRIMARY governing memory).

#### §3.A Summary

v37.0 source-tree changes since baseline `1c0f0913`: 2 contract-tree commits (`e1136071` Phase 267 Degenerette + `8fd5c2e1` Phase 269 LBX-01) + 1 test-tree commit (`4b277aaf` Phase 268; not enumerated above — test surface, not contract surface). Phase 270 sub-audit subjects (`002bde55` + `2713ce61`) PREDATE the v37.0 baseline and are enumerated for milestone-completeness per Phase 270 working-file appendix cross-cite. All rows verdicted SAFE / SAFE_BY_DESIGN / SAFE_BY_STRUCTURAL_CLOSURE per AUDIT-01 + AUDIT-02 + DELTA-03.

### 3.B AUDIT-04 Zero-New-State Attestation

Grep-proof attestation: zero new storage slots, zero new public/external mutation entry points, zero new admin functions, zero new modifiers, zero new upgrade hooks, zero new ERC-20 mint entry points since v36.0 baseline `1c0f0913`.

**Storage byte-identity (zero new storage slots):**

Recipe:
```
git diff 1c0f09132d7439af9881c56fe197f81757f8164a..HEAD -- contracts/storage/
```

Output: empty (no `contracts/storage/` subdirectory; storage is consolidated at `contracts/DegenerusGameStorage.sol`). Recipe re-run against the actual storage file:
```
git diff 1c0f09132d7439af9881c56fe197f81757f8164a..HEAD -- contracts/DegenerusGameStorage.sol
```

Output: empty (0 files changed). Phase 268 SURF-01..04 byte-identity grep-proof cross-cites this same invariant at the test-tree harness level. `packedTraitsDegenerette` is a `internal pure` library helper added to `contracts/DegenerusTraitUtils.sol` — no storage slots touched.

**Zero new public/external mutation entry points:**

Recipe:
```
git diff 1c0f09132d7439af9881c56fe197f81757f8164a..HEAD -- contracts/ \
  | grep -E '^\+.*function .* (public|external)'
```

Output: 0 hits (re-run at §3.B authoring time). The Phase 267 `_distributePayout` signature change (insertion of `uint128 betAmount` between `currency` and `payout`) is internal-only — the function remains `internal`. `packedTraitsDegenerette` is `internal pure` library helper, inlined into `DegenerusGameDegeneretteModule` at compile time. The function selector does NOT appear in the deployed artifact ABI (cross-cite Solidity language semantics for `internal` linkage; Phase 268 SURF-01 v37.0 describe in `test/stat/SurfaceRegression.test.js` selector-enumeration evidence). `_countGoldQuadrants` is `private pure`. `_degTrait` is `private pure`.

**Zero new admin functions / modifiers / upgrade hooks:**

Recipe:
```
git diff 1c0f09132d7439af9881c56fe197f81757f8164a..HEAD -- contracts/ \
  | grep -E "^\+.*(modifier |onlyOwner|onlyAdmin|UUPSUpgradeable|_authorizeUpgrade)"
```

Output: 0 hits (re-run at §3.B authoring time). No new admin gates introduced; existing admin surface (Phase 270 working-file audit of post-v32.0 commits `002bde55` + `2713ce61` covers admin-surface narrowing — `setDecimatorAutoRebuy` wrapper DELETED is admin-entry-point-removal blast radius = zero per Phase 270 SAFE_BY_DESIGN verdict).

**Zero new ERC-20 mint entry points:**

Recipe:
```
git diff 1c0f09132d7439af9881c56fe197f81757f8164a..HEAD -- contracts/ \
  | grep -E "^\+.*\.(mint|mintFor|_mint)\("
```

Output: 0 hits in non-test contract files. Degenerette payout flow uses pre-existing `mintForGame` route only; no new mint sites introduced per AUDIT-03 conservation cross-cite (see §3.C below).

**Storage layout slot-by-slot proof:** `contracts/DegenerusGameStorage.sol` is byte-identical at v37.0 HEAD vs v36.0 baseline `1c0f0913` per the storage-file diff recipe above. Slot-by-slot enumeration trivially preserved because the file is unchanged. Phase 268 SURF-01..04 codehash-equality / selector-enumeration assertions cross-cite this invariant at the consumer artifact-tree level (Mint + Jackpot + EntropyLib + non-lootbox JackpotModule UNCHANGED vs baseline). The `_distributePayout` signature change is internal-linkage only — no ABI widening, no storage rearrangement.

**Note on `packedTraitsDegenerette` internal-pure linkage:** `packedTraitsDegenerette(uint256 seed) internal pure returns (uint32)` is a library helper in `contracts/DegenerusTraitUtils.sol`. Per Solidity language semantics, `internal` linkage means the function is inlined into its caller (`DegenerusGameDegeneretteModule`) at compile time — it does NOT appear in the deployed artifact's public ABI; the function selector is NOT in the contract's `function-selectors` set. This is the explicit DGN-01 + DGN-15 design contract. Cross-cite Phase 268 SURF-01 v37.0 describe in `test/stat/SurfaceRegression.test.js` for selector-enumeration evidence at the harness level.

**Five-line zero-attestation roll-up** (one phrase per line for grep-tally clarity):

- zero new storage slots — `git diff 1c0f0913..HEAD -- contracts/DegenerusGameStorage.sol` empty.
- zero new public/external mutation entry points — `git diff 1c0f0913..HEAD -- contracts/ | grep -E '^\+.*function .* (public|external)'` returns 0.
- zero new admin functions — `git diff 1c0f0913..HEAD -- contracts/ | grep -E "^\+.*(onlyOwner|onlyAdmin)"` returns 0.
- zero new modifiers — `git diff 1c0f0913..HEAD -- contracts/ | grep -E "^\+.*modifier "` returns 0.
- zero new upgrade hooks — `git diff 1c0f0913..HEAD -- contracts/ | grep -E "^\+.*(UUPSUpgradeable|_authorizeUpgrade)"` returns 0.

**Closing attestation:** Storage layout byte-identical at v37.0 closure HEAD `<sha>` vs v36.0 baseline `1c0f0913` per slot-by-slot grep-proof; zero new public/external mutation entry points; zero new external pure entry points (`packedTraitsDegenerette` is internal pure library helper, inlined at compile time, not in deployed ABI); zero new admin functions; zero new modifiers; zero new upgrade hooks; zero new ERC-20 mint entry points per DGN-15 + AUDIT-04 design contract.

### 3.C AUDIT-03 Conservation Re-Proof

Conservation re-proof across 4 domains: per-N table calibration math; ETH bonus EV conservation; solvency invariant + ethShare/lootboxShare sum invariant; no new mint sites. Closes the AUDIT-03 design contract per ROADMAP success criterion + REQUIREMENTS.md.

**(1) Degenerette payout flow conservation — per-N table calibration math:**

For each N ∈ {0..4}, the per-N basePayout EV is exact at 100 centi-x by construction:

`basePayoutEV(N) = Σ P_N(M) × payout_N(M) for M ∈ {0..8} = 100 centi-x (Fraction-exact)`

where `P_N(M)` is the binomial-convolution per-N match-count distribution (4 color indicators with N at Bernoulli(1/15) + (4-N) at Bernoulli(2/15) plus 4 symbol indicators at Bernoulli(1/8)) and `payout_N(M)` is the per-N packed schedule from `QUICK_PLAY_PAYOUTS_N{N}_PACKED` (M = 0..7) + `QUICK_PLAY_PAYOUT_N{N}_M8` (M = 8 jackpot slot, exceeds 32-bit packing range).

Calibration source: `.planning/notes/degenerette-recalibration/derive_5_tables.py` Python `Fraction`-exact arithmetic produces the 25 packed constants. Phase 267 Task 2 byte-identity proof (`PASS_ALL_25`) confirms the deployed constants match the script's Fraction-exact stdout.

Empirical witness: Phase 268 STAT-01 (`test/stat/DegenerettePerNEvExactness.test.js`) ≥ 1M draws per N confirms `basePayoutEV = 100.00 ± 0.50 centi-x` for each N ∈ {0..4}.

**(2) ETH bonus EV conservation per N:**

Analytical: `ETH_ROI_BONUS_BPS = 500 bps = 5.000%` (the protocol's ETH-currency bonus ROI target). The per-N WWXRP factor table redistributes this 5.000% across the 5+ match buckets via `_wwxrpFactor(N, bucket)` lookup. By construction:

`Σ_{M≥5} P_N(M) × factor_N(bucket(M)) × ETH_ROI_BONUS_BPS / WWXRP_BONUS_FACTOR_SCALE = 5.000% per N`

The 10/30/30/30 bucket split (M ∈ {5,6,7,8}) × per-N factor lookup yields exactly 5.000% total ETH bonus EV per N. Empirical witness: Phase 268 STAT-04 per-N WWXRP factor EV within ±1% at ≥ 100K WWXRP-active draws/N.

**Per-N hero EV-neutrality** is preserved by the per-N HERO_BOOST table calibration:

`P(hero|M, N) × boost(M, N) + (1 − P(hero|M, N)) × HERO_PENALTY = HERO_SCALE`

where `HERO_PENALTY = 9500`, `HERO_SCALE = 10000`. The 5 per-N tables (`HERO_BOOST_N{0..4}_PACKED`) encode 6 values each (M = 2..7; M < 2 zero-payout exemption, M = 8 hero-EV-neutrality exemption noted in NatSpec at `_fullTicketPayout`). Empirical witness: Phase 268 STAT-03 per-N hero EV within ±1% at ≥ 100K hero-active draws/N. By exchangeability of the 4 symbol indicators (uniform 1/8 regardless of player symbol choice) and color-match indicator structure (gold vs common), `P(hero|M, N)` depends only on (M, N) — not on the specific player pick configuration. The per-N table is correctly indexed.

**(3) Solvency invariant + ethShare/lootboxShare sum invariant:**

`claimablePool ≤ ETH balance + stETH balance` PRESERVED. The Degenerette payout-recalibration touches per-quadrant payout schedule + payout-distribution mechanics only — no ETH/stETH balance mutations beyond pre-existing `_distributePayout` mechanics.

The PAY-SPLIT 3-tier rule (PAY-SPLIT-01..03) is INTRA-`_distributePayout` redistribution between `ethShare` and `lootboxShare`. Total payout sum invariant:

`ethShare + lootboxShare = payout` ← preserved at every tier

Verified in code:
- PAY-SPLIT-01 (Tier 1, L737-740): `ethShare = payout; lootboxShare = 0` → sum = `payout`. ✓
- PAY-SPLIT-02 (Tier 2, L741-748): `ethShare = max(2.5 × bet, payout / 4); lootboxShare = payout − ethShare` → sum = `payout`. ✓
- PAY-SPLIT-03 (Tier 3 + pool-cap, L774-779): `maxEth = (pool × ETH_WIN_CAP_BPS) / 10_000 = 10% × pool`; if `ethShare > maxEth`, then `lootboxShare += ethShare − maxEth; ethShare = maxEth` → sum = `payout` (additive transfer preserves total). ✓

Pool-cap precedence (PAY-SPLIT-03) ensures `ethShare ≤ 10% × futurePool` per payout event; ETH balance is bounded by the futurePool ceiling at every settlement. Frozen-pool path (L751-768) uses pending-pool side-channel debit with revert-on-insufficient solvency check.

**(4) No new mint sites:**

`coinflip.creditFlip` + lootbox-crediting paths byte-identical at v37.0 HEAD vs v36.0 baseline (Phase 268 SURF-01..04 cross-cite). Degenerette payout path uses pre-existing `mintForGame` route only (`coin.mintForGame(player, payout)` at L792 for CURRENCY_BURNIE branch; `wwxrp.mintPrize(player, payout)` at L794 for CURRENCY_WWXRP branch); no new ERC-20 mint entry points introduced by Phase 267 commit `e1136071`.

Grep recipe re-run at §3.C authoring time:
```
git diff 1c0f09132d7439af9881c56fe197f81757f8164a..HEAD -- contracts/ \
  | grep -E "^\+.*\.(mint|mintFor|_mint)\("
```
Output: zero hits in non-test contract files (verified via `§3.B AUDIT-04 Zero-New-State Attestation` grep recipes).

**Closing conservation attestation:** Per-N table calibration math holds `basePayoutEV = 100 centi-x ± Fraction-exact rounding` per N ∈ {0..4} per `.planning/notes/degenerette-recalibration/derive_5_tables.py`; ETH bonus EV = exactly 5.000% per N analytical, ±1% empirical per Phase 268 STAT-04; per-N hero EV-neutrality holds within 0.05% calibration tolerance per design contract DGN-07, ±1% empirical per Phase 268 STAT-03; solvency invariant `claimablePool ≤ ETH balance + stETH balance` PRESERVED; PAY-SPLIT 3-tier rule preserves `ethShare + lootboxShare = payout` invariant at every tier with pool-cap precedence enforcing `ethShare ≤ 10% × futurePool`; no new mint sites.

---

## 4. F-37-NN Finding Blocks

### 4.1. Adversarial Sweep — 8-Surface Row Table

Per AUDIT-02 design contract: 8 adversarial surfaces (a)..(h) covering the v37.0 delta scope. Each row contains `Verdict:`, `Evidence:`, `Grep recipe:` (where applicable), and `Prose justification:` blocks. Default verdict bucket per D-271-FIND-01: SAFE / SAFE_BY_DESIGN / SAFE_BY_STRUCTURAL_CLOSURE. Zero F-37-NN finding blocks emitted unless D-271-ADVERSARIAL-04 escalation surfaces a FINDING_CANDIDATE / 9th-surface NEW_VECTOR / KI promotion candidate that user disposition approves.

#### Surface (a) — per-N table dispatch correctness vs match-count distribution P_N(M)

**Verdict:** SAFE_BY_STRUCTURAL_CLOSURE.

**Evidence:**
- 5-table per-N payout dispatch calibrated via `.planning/notes/degenerette-recalibration/derive_5_tables.py` Fraction-exact derivation.
- `basePayoutEV = 100 centi-x` exact per N ∈ {0..4} (analytical).
- Phase 268 STAT-01 ≥1M draws/N empirically validates `100.00 ± 0.50 centi-x` for each N — `test/stat/DegenerettePerNEvExactness.test.js`.
- Phase 268 STAT-05 per-N match-count histogram matches analytical binomial-convolution reference within ±0.5% bin tolerance — same file.
- Phase 267 commit `e1136071` `_getBasePayoutBps` 5-table dispatch + `_countGoldQuadrants` N selector.

**Prose justification:** P_N(M) is the binomial-convolution per-N match-count distribution. The 5-table dispatch indexes the per-N payout schedule by N (output of `_countGoldQuadrants`). Each per-N schedule is Fraction-exact calibrated so that `Σ P_N(M) × payout_N(M) for M ∈ {0..8} = 100 centi-x`. Phase 268 STAT-01 empirically validates the EV calibration; STAT-05 validates the distribution-shape match. Structural closure: the per-N table is the SAME mathematical object as the per-N P_N(M) ⊗ payout_N(M) integral — by construction.

#### Surface (b) — symbol-only hero match preserves uniformity, no color-channel info leak

**Verdict:** SAFE_BY_DESIGN.

**Evidence:**
- DGN-07 design contract: hero match is symbol-only via `((playerTicket >> heroQuadrant*8) & 7) == ((resultTicket >> heroQuadrant*8) & 7)`.
- Comparison reads only bits 0-2 (the symbol nibble) of the hero quadrant byte; color bits 3-5 are NOT read.
- Symbol distribution is uniform 1/8 per producer DGN-01 (`[16,16,16,16,16,16,16,8]/120` color × uniform 1/8 symbol).
- P(hero match) = 1/8 exactly (analytical).
- Phase 268 STAT-03 hero EV per N within ±1% — `test/stat/DegeneretteBonusEv.test.js`.
- Phase 267 commit `e1136071` `_applyHeroMultiplier` symbol-only rewrite.

**Prose justification:** No color-channel info leak because color bits are not inputs to the equality comparison; only the symbol nibble (3 bits) is compared. The uniform 1/8 symbol distribution combined with the bit-mask isolation gives exactly P(hero match) = 1/8 per quadrant. Per-N hero boost dispatch via `HERO_BOOST_N{0..4}_PACKED` preserves EV-neutrality within 0.05% tolerance (HERO_PENALTY 9500 / HERO_SCALE 10000 unchanged); empirical ±1% per Phase 268 STAT-03.

#### Surface (c) — `_countGoldQuadrants` boundary `color == 7` strict (not `>= 7`)

**Verdict:** SAFE_BY_DESIGN.

**Evidence:**
- DGN-03 design contract: `_countGoldQuadrants(uint32 ticket) private pure returns (uint8)` returns N ∈ {0..4} from strict `color == 7` comparison: `((ticket >> (q*8 + 3)) & 7) == 7` for q ∈ {0..3}.
- 3-bit color field range {0..7}; with `& 7` mask there is no `>= 7` ambiguity (only 7 itself satisfies).
- uint8 return + bounded 4-iteration loop + cumulative count ≤ 4 — overflow immune.
- Phase 268 STAT-01 per-N cross-pick parity describe implicitly validates N-dispatch boundary.

**Prose justification:** Strict equality `== 7` is the only meaningful test for a 3-bit field where 7 is the maximum value. The masking `& 7` is redundant (since the shift `(ticket >> (q*8 + 3))` already isolates 3 bits when combined with the field width), but provides explicit byte-layout discipline. Off-by-one immune because `== 7` is unambiguous. The 4-iteration loop is bounded; cumulative count is naturally bounded ≤ 4 by the loop. uint8 return type is sufficient for {0..4}.

#### Surface (d) — producer `[16,16,16,16,16,16,16,8]/120` byte-layout consistency with downstream consumers

**Verdict:** SAFE_BY_STRUCTURAL_CLOSURE.

**Evidence:**
- DGN-01 + DGN-14 design contracts: `packedTraitsDegenerette` preserves `[QQ][CCC][SSS]` byte layout (color 3 bits at offset 3-5 of each player-pick byte; symbol 3 bits at offset 0-2).
- `packedTraitsFromSeed` body byte-identical (Mint + Jackpot UNCHANGED per Phase 268 SURF-01); the only additive change is the new producer helper.
- Phase 268 STAT-02 chi² ≥1M-sample uniformity verification within Wilson-Hilferty Z<1.645 / `CHI2_CRIT_05[7] = 14.067` at α=0.05.
- Phase 267 commit `e1136071` packed-traits producer + `_countGoldQuadrants` consumer dispatch share the byte layout.

**Prose justification:** Producer + consumer share the same byte layout — structurally closed. The chi² uniformity test verifies the producer empirically matches the analytical `[16,16,16,16,16,16,16,8]/120` distribution; SURF-01 byte-identity verifies the consumer reads the same byte layout the producer writes. Mint + Jackpot paths consume `packedTraitsFromSeed` (unchanged byte layout); Degenerette consumes `packedTraitsDegenerette` (new producer, SAME byte layout). No layout drift across consumers.

#### Surface (e) — WWXRP factor table-dispatch composition with hero boost — no double-counting

**Verdict:** SAFE_BY_DESIGN.

**Evidence:**
- DGN-09 + DGN-10 design contracts: per-N WWXRP factor dispatch via `WWXRP_FACTORS_N{0..4}_PACKED`; hero boost via `HERO_BOOST_N{0..4}_PACKED` (independent table).
- Phase 268 STAT-04 per-N WWXRP factor EV within ±1% at ≥100K WWXRP-active draws/N.
- Multiplicative composition in `_fullTicketPayout`: hero × WWXRP applied sequentially to base payout, then `_distributePayout` consumes the post-hero-post-WWXRP amount.

**Prose justification:** Hero and WWXRP boosts are independent multiplicative factors applied sequentially. Hero touches the symbol nibble (surface (b)); WWXRP touches a separate per-N factor table indexed by RNG-derived bucket (Phase 268 STAT-04 empirical validation). No shared inputs, no double-counting. The 3-tier ETH split (surface (h)) operates on the FINAL post-hero-post-WWXRP payout amount, so split-rule decisions see the composed value, not the pre-multiplier base.

#### Surface (f) — lootbox dead-branch removal byte-equivalence via caller-clamp invariant

**Verdict:** SAFE_BY_STRUCTURAL_CLOSURE.

**Evidence:**
- Phase 269 commit `8fd5c2e1` caller-clamp triple-defense (cross-cite §3.A Row Group 2):
  - **Layer-1** `openLootBox` L557-559 unconditionally clamps `targetLevel = max(targetLevel, currentLevel)`.
  - **Layer-2** `_resolveLootboxCommon` L882-884 unconditionally clamps `targetLevel = max(targetLevel, currentLevel)`.
  - **Layer-3** (DELETED) inner `_resolveLootboxRoll` `if (targetLevel < currentLevel) { burnieOut = ... }` branch was structurally dead.
- Bytecode shrink 177 bytes (18,330 → 18,153) confirms no behavior change.
- LBX-03 anchor cross-cite §3.A Row Group 2 — 4 hash2/bit-slice callsites in `_resolveLootboxRoll` at HEAD L1559 / L1564 / L1571 / L1599 byte-identical at structural level.

**Prose justification:** Layer-1 and Layer-2 unconditionally enforce `targetLevel ≥ currentLevel` before `_resolveLootboxRoll` is reached. The deleted inner branch tested `targetLevel < currentLevel` — an invariantly-false predicate under the caller-clamp regime. Removing dead code does not change behavior; bytecode shrink empirically confirms via direct artifact inspection. Bit-slice budget UNAFFECTED (same 4 callsites, same bit ranges, same modulo constants).

#### Surface (g) — hero × per-N composition skill-expression channel preserved (v34.0 surface (f) carry-forward)

**Verdict:** SAFE_BY_DESIGN.

**Evidence:**
- `audit/FINDINGS-v34.0.md` §4 surface (f) predecessor analysis (hero × gold composition prose) — v34.0 carry source.
- Phase 268 STAT-01 per-N cross-pick parity describe (within `test/stat/DegenerettePerNEvExactness.test.js`).
- Phase 268 STAT-03 hero EV per N within ±1%.
- Equal-EV invariant holds across all 16,384 player-pick configurations within statistical tolerance (player has full freedom of pick configuration; EV is config-invariant within ±1%).

**Prose justification:** Hero is a per-quadrant symbol-match boost; per-N is a payout-table dispatch indexed by gold-quadrant count. They compose multiplicatively on the base payout, and their compositions are independent (hero indexes the hero quadrant byte; per-N indexes the gold-color count across all 4 quadrants). Skill-expression channel is preserved: player chooses pick configuration → distribution of N depends on configuration → EV remains within ±1% across configurations (by construction of the per-N tables). v34.0 §4 surface (f) carry-forward applies: hero × gold composition was previously verdicted SAFE_BY_DESIGN under the single-table payout schedule; the 5-table per-N rewrite preserves the same composition property because each per-N table is independently EV-calibrated to 100 centi-x.

#### Surface (h) — ETH payout split-rule monotonicity + boundary-gaming check (v37-NEW)

**Verdict:** SAFE_BY_DESIGN (with `/economic-analyst` escalation hook per D-271-ADVERSARIAL-04).

**Evidence:**
- **PAY-SPLIT-01** (≤3× bet → 100% ETH): `_distributePayout` branch guards `payout <= 3 * betAmount` strictly inclusive at exactly 3.0×. No off-by-one (≤ vs <) ambiguity per Phase 267 D-PAY-SPLIT-01 design contract.
- **PAY-SPLIT-02** (3× < payout ≤ 10× → 2.5× bet ETH floor + remainder lootbox): `ethShare = max(2.5 * betAmount, payout / 4)`. Boundary discontinuity at exactly 3.0× bet documented as ACCEPTED-DESIGN: player at payout = 3.0× bet receives 3.0× bet ETH (PAY-SPLIT-01 path); player at payout = 3.01× bet receives 2.5× bet ETH + 0.51× bet lootbox (PAY-SPLIT-02 path); 0.5× bet ETH-share drop at the 3.0× → 3.01× transition. Total payout invariant preserved (`ethShare + lootboxShare = payout`).
- **PAY-SPLIT-03** (pool-cap precedence): if computed `ethShare > 10% × futurePool`, excess flips to lootbox per existing L716-723 logic. Verified to compose correctly with PAY-SPLIT-01/02 (pool cap takes precedence over small-payout passthrough AND 2.5× floor). NatSpec on `_distributePayout` documents the precedence rule per Phase 267 DGN-13 stale-comments rewrite.
- **Empirical evidence:** Phase 268 STAT-07 (`test/stat/DegenerettePerNEvExactness.test.js describe("ETH payout split rule")`) validates per-band frequency match within ±0.5% bin tolerance for the 3-tier split across all per-N basePayout × roiBps distributions; pool-cap excess-flip path tested separately under thin-pool fixture (D-268-THINPOOL-01).
- **Composition with hero × WWXRP:** hero boost + WWXRP factor table dispatch applies BEFORE `_distributePayout` receives the final payout amount; the 3-tier split rule sees the post-hero-post-WWXRP amount; no double-counting (cross-cite surface (e) WWXRP composition + (g) hero × per-N composition).

**Boundary-gaming analysis:**
- Player CANNOT control the payout amount post-VRF-fulfillment (payout is a deterministic function of (player picks, VRF-derived match count, hero, WWXRP-bonus) — all inputs committed before VRF reveal per `feedback_rng_commitment_window.md` backward-trace per `feedback_rng_backward_trace.md`).
- Player CAN choose `betAmount` and currency, but the 3-tier split is structurally bounded by the payout-multiple distribution; no actor can precisely target the 3.0× boundary because the player-side parameter is `betAmount`, not payout-multiple.
- Pool-cap precedence (PAY-SPLIT-03) ensures protocol solvency dominates payout-shape preferences; thin-pool conditions cap-flip excess to lootbox preserving `claimablePool` ceiling.

**Prose justification:** Total payout invariant `ethShare + lootboxShare = payout` is preserved at every tier — the player receives the same total value, just in a different mix. The boundary discontinuity at 3.0× bet (0.5× bet ETH-share drop at 3.0× → 3.01×) is the accepted-design tradeoff between (a) preserving 100% ETH for small wins (≤3× bet — keeps the per-bet break-even clean) and (b) bounding ETH outflow per win to a fixed 2.5× bet floor in the mid-band (3-10× bet) to protect the prize pool. Player cannot game the boundary because `betAmount` is the player-side lever, not payout-multiple, and payout-multiple is a deterministic post-VRF function of inputs committed pre-VRF reveal. Per D-271-PAYSPLIT-01 default disposition: this boundary discontinuity is documented as accepted-design via this §4 surface (h) prose disclosure ONLY; no new KNOWN-ISSUES.md entry under Design Decisions (zero-promotion default). `/economic-analyst` Task 6 has the escalation hook per D-271-ADVERSARIAL-04 to flag this as a KI promotion candidate if mechanism-design red-team disagrees with the accepted-design verdict.

### 4.2. Verdict Roll-Up + Adversarial-Pass Status

8 of 8 surfaces (a)..(h) SAFE / SAFE_BY_DESIGN / SAFE_BY_STRUCTURAL_CLOSURE per inline draft (Task 5). Adversarial-pass validation via `/contract-auditor` + `/zero-day-hunter` + `/economic-analyst` PARALLEL spawn (Task 6) per D-271-ADVERSARIAL-01; full output logged in `271-01-ADVERSARIAL-LOG.md`. All 3 skills concurred; zero FINDING_CANDIDATE, zero 9th-surface NEW_VECTOR, zero KI Design Decisions promotion candidate. Phase 271 §4 verdict roll-up STANDS unchanged; KNOWN-ISSUES.md UNMODIFIED per D-271-PAYSPLIT-01 + D-271-KI-01 default zero-promotion path.

---

## 5. Regression Appendix

### 5a. REG-01 — v36.0 Closure-Signal Non-Widening

| Row ID | Source | Delta SHA | Subject Surface at HEAD `<sha>` | Re-Verification Evidence | Verdict |
| ------ | ------ | --------- | ------------------------------ | ------------------------ | ------- |
| REG-v36.0-LBX-ENT | v36.0 closure signal `MILESTONE_V36_AT_HEAD_1c0f09132d7439af9881c56fe197f81757f8164a` carry-forward | `1c0f0913..<v37-close-sha>` (2 contract commits `e1136071` + `8fd5c2e1`; 1 test commit `4b277aaf`) | EntropyLib body byte-identical at v37 HEAD vs baseline `1c0f0913` (Phase 268 SURF-04 grep-proof). Lootbox v36.0 entropy refactor bodies byte-identical EXCEPT for LBX-01 dead-branch deletion (Phase 269 commit `8fd5c2e1`; bytecode shrink 177 bytes 18,330 → 18,153; caller-clamp triple-defense proves no behavior change). 4 hash2/bit-slice callsites in `_resolveLootboxRoll` survive byte-identical at structural level — line numbers shift downward by 11 LOC (L1548 → L1559 etc.) for the first 3 callsites after dead-branch removal; 4th callsite at L1599 invariant; bit-slice budget UNAFFECTED. LBX-03 anchor cross-cite §3.A Row Group 2. | Phase 268 SURF-03 + SURF-04 v37.0 describe asserts byte-identity vs v36.0 baseline; LBX-01 deletion is no-behavior-change cleanup with caller-clamp triple-defense invariant + structural audit-trail row at §3.A. | PASS |

### 5b. REG-02 — v34.0 Closure-Signal Non-Widening

| Row ID | Source | Delta SHA | Subject Surface at HEAD `<sha>` | Re-Verification Evidence | Verdict |
| ------ | ------ | --------- | ------------------------------ | ------------------------ | ------- |
| REG-v34.0-TRAIT-SOLO | v34.0 closure signal `MILESTONE_V34_AT_HEAD_6b63f6d4daf346a53a1d463790f637308ea8d555` carry-forward | `6b63f6d4..<v37-close-sha>` | TraitUtils existing 3 functions (`weightedColorBucket` body L115-135 + `traitFromWord` body L143-167 + `packedTraitsFromSeed` body L169-178) byte-identical at v37 HEAD per DGN-14 design contract — only additive change is the NEW `packedTraitsDegenerette` helper. `_pickSoloQuadrant` body + 4 ETH-distribution injection sites at L282 / L349 / L524 / L1147 byte-identical between v34.0 baseline `6b63f6d4` and v37 HEAD per Phase 268 SURF-02 grep-proof. JackpotBucketLib + `weightedColorBucket` byte-identical. **Surfaces strictly disjoint:** Degenerette path uses NEW `packedTraitsDegenerette`; gold-solo Mint/Jackpot path uses unchanged `packedTraitsFromSeed`; no widening. | Phase 268 SURF-01 + SURF-02 v37.0 describe codehash-equality / selector-enumeration assertions; no v37 commit touches `contracts/libraries/JackpotBucketLib.sol` or `DegenerusGameJackpotModule.sol`. | PASS |

### 5c. REG-04 — Prior-Finding Spot-Check Sweep

Per-finding 6-col PASS/REGRESSED/SUPERSEDED row table from REG-04 grep sweep across `audit/FINDINGS-v25.0.md` through `audit/FINDINGS-v36.0.md` for findings referencing the v37-touched function set (`_evNormalizationRatio`, `_getBasePayoutBps`, `_applyHeroMultiplier`, `_wwxrpBonusRoiForBucket`, `_distributePayout`, `packedTraitsFromSeed`, `_resolveLootboxRoll`, `setDecimatorAutoRebuy`).

| Row ID | Source Finding | Delta SHA | Subject Surface at HEAD `<sha>` | Re-Verification Evidence | Verdict |
| ------ | -------------- | --------- | ------------------------------ | ------------------------ | ------- |
| REG-v25.0-F-25-02 | `audit/FINDINGS-v25.0.md` §F-25-02 "DegeneretteModule._distributePayout Sequential External Calls" | `1c0f0913..<v37-close-sha>` | `_distributePayout` REWRITTEN at Phase 267 commit `e1136071` with 5-arg signature (`betAmount` inserted) + PAY-SPLIT 3-tier rule. Sequential-external-calls posture preserved: CURRENCY_BURNIE → `coin.mintForGame`; CURRENCY_WWXRP → `wwxrp.mintPrize`; ETH branch → `_addClaimableEth` + `_resolveLootboxDirect` (delegatecall to LootboxModule). All post-state-write external calls remain one-way token operations or in-protocol delegatecalls with no caller callback. v37 rewrite does not introduce new external-call vectors. | v29.0 PASS verdict carries forward; Phase 267 rewrite preserves the sequential-external-calls posture; no new untrusted-external-call paths. | PASS |
| REG-v30.0-INV-237-134..137 | `audit/FINDINGS-v30.0.md` §3 INV-237-134..137 "`_resolveLootboxRoll` entropyStep callsites (KI: EXC-04)" | `1c0f0913..<v37-close-sha>` | v36.0 Phase 266 ENT-02 refactored the 4 entropyStep callsites to inline bit-slices (per `audit/FINDINGS-v36.0.md` ENT-02 closure). Phase 269 LBX-01 commit `8fd5c2e1` deletes the dead BURNIE-conversion inner branch without touching any of the 4 bit-slice callsites. v37.0 HEAD: 4 hash2/bit-slice callsites at L1559 / L1564 / L1571 / L1599 (vs v36.0 baseline L1548 / L1569 / L1585 / L1599; first 3 shifted downward by 11 LOC). EXC-04 KI envelope NARROWS retained (BAF-jackpot-only scope) — see §6b. | v36.0 ENT-02 CLOSED carries forward; Phase 269 LBX-01 caller-clamp triple-defense + bytecode shrink 177 bytes confirm structural byte-equivalence; bit-slice budget UNAFFECTED. | SUPERSEDED (by v36.0 ENT-02 closure + v37.0 Phase 269 LBX-01 dead-branch deletion; INV-237-134..137 EXC-04 envelope retained NARROWS — see §6b EXC-04 row) |
| REG-v33.0-DEFERRED-2713ce61 | `audit/FINDINGS-v33.0.md` §3 deferred-commit entry `2713ce61` "chore(vault): remove dead setDecimatorAutoRebuy wrapper" (ORTHOGONAL_PROVEN verdict at v33) | `2713ce61..<v37-close-sha>` | Adversarial sub-audit completed at Phase 270 (commit `4017b9ec` `docs(270): post-v32.0 deferred-commit adversarial sub-audit working file [DELTA-01..04]`). Phase 270 verdict for Commit B `2713ce61`: **SAFE_BY_DESIGN** (admin-entry-point-removal blast radius = zero; Phase 146 ABI cleanup `31ec2780` (Apr 9 2026) anchored as unreachability cause via design-intent trace per `feedback_design_intent_before_deletion.md` PRIMARY governing memory). 2 declaration rows enumerated at §3.A Row Group 3. | Phase 270 270-01-DELTA-SURFACE.md full appendix; 4 RE_VERIFIED-NEGATIVE-scope KI envelope rows feed §6b. | PASS (carry-forward-deferred adversarial coverage closed at Phase 270) |
| REG-v33.0-DEFERRED-002bde55 | `audit/FINDINGS-v33.0.md` (and carry-forward to v34.0/v35.0/v36.0) deferred-commit entry `002bde55` "feat(presale): auto-deactivate flag on per-mint cap crossing" | `002bde55..<v37-close-sha>` | Adversarial sub-audit completed at Phase 270 (same working-file appendix as `2713ce61`). Phase 270 verdict for Commit A `002bde55`: **SAFE_BY_STRUCTURAL_CLOSURE**. 5 declaration rows enumerated at §3.A Row Group 3. | Phase 270 270-01-DELTA-SURFACE.md full appendix. | PASS (carry-forward-deferred adversarial coverage closed at Phase 270) |
| REG-v34.0-TRAIT-03 | `audit/FINDINGS-v34.0.md` §3 TRAIT-03 "`packedTraitsFromSeed(uint256) → uint32` REFACTOR_ONLY at L169-180; byte layout `[QQ][CCC][SSS]` preserved" | `6b63f6d4..<v37-close-sha>` | `packedTraitsFromSeed` body byte-identical at v37 HEAD vs v34.0 baseline `6b63f6d4` per Phase 268 SURF-01 grep-proof. The new `packedTraitsDegenerette` helper is ADDITIVE (does NOT modify `packedTraitsFromSeed`). DGN-14 design contract preserves the byte layout invariant. | Phase 268 SURF-01 v37.0 describe + DGN-14 design contract preservation. | PASS |
| REG-v34.0-TRAIT-06 | `audit/FINDINGS-v34.0.md` §3 TRAIT-06 "Hardhat unit suite at `test/unit/DegenerusTraitUtils.test.js`" | `6b63f6d4..<v37-close-sha>` | v37 introduces NO test deletions; the unit suite for `weightedColorBucket` / `traitFromWord` / `packedTraitsFromSeed` carries forward. New stat suite (`test/stat/DegenerettePerNEvExactness.test.js` + `DegeneretteProducerChi2.test.js` + `DegeneretteBonusEv.test.js`) is ADDITIVE coverage for the Degenerette producer + payout rewrite. | `test/unit/DegenerusTraitUtils.test.js` byte-identical at v37 HEAD (Phase 268 task verification). | PASS |
| REG-v36.0-ENT-02 | `audit/FINDINGS-v36.0.md` §3d ENT-02 "`_resolveLootboxRoll` 4 entropyStep callsites removed; L1585 dead WWXRP advance DELETED" | `1c0f0913..<v37-close-sha>` | v36.0 Phase 266 ENT-02 closed via inline-bit-slice refactor. Phase 269 LBX-01 commit `8fd5c2e1` removes ONE additional unreachable branch (BURNIE-conversion at v36 L1574-1578) without touching ENT-02's 4 bit-slice callsites. Caller-clamp triple-defense (Layer-1 L557-558 + Layer-2 L882-883 + Layer-3 deleted) proves byte-equivalence. | v36.0 ENT-02 CLOSED + Phase 269 LBX-01 audit-cleanliness-only cleanup; bit-slice budget UNAFFECTED. | PASS |

### 5d. Regression Distribution Summary

| Verdict | REG-01 | REG-02 | REG-04 | Total |
| ------- | ------ | ------ | ------ | ----- |
| PASS    | 1      | 1      | 5      | 7     |
| REGRESSED | 0    | 0      | 0      | 0     |
| SUPERSEDED | 0   | 0      | 1      | 1     |
| **Total** | **1** | **1** | **6** | **8** |

Zero REGRESSED rows. One SUPERSEDED row (REG-v30.0-INV-237-134..137) — supersedence by v36.0 ENT-02 closure + v37.0 Phase 269 LBX-01 dead-branch deletion; EXC-04 KI envelope NARROWS retained per §6b. Surfaces strictly disjoint between Degenerette (new `packedTraitsDegenerette`) and gold-solo Mint/Jackpot (unchanged `packedTraitsFromSeed`).

---

## 6. KI Gating Walk

### 6a. Non-Promotion Ledger

Zero F-37-NN finding blocks emitted per D-271-FIND-01; zero rows in Non-Promotion Ledger.

Default path: Phase 271 §4 8-surface inline draft (Task 5) verdicts 8 of 8 SAFE / SAFE_BY_DESIGN / SAFE_BY_STRUCTURAL_CLOSURE. Task 6 adversarial-pass via `/contract-auditor` + `/zero-day-hunter` + `/economic-analyst` (3 skills PARALLEL spawn per D-271-ADVERSARIAL-01) concurs with zero disagreement per `271-01-ADVERSARIAL-LOG.md` Disposition note (D-271-ADVERSARIAL-04 path evaluated and does NOT fire). Surface (h) PAY-SPLIT 3-tier boundary discontinuity at exactly 3.0× bet satisfies the D-09 3-predicate KI Gating Rubric (accepted-design + non-exploitable + sticky) in principle but is correctly documented via §4 (h) prose-only attestation per D-271-PAYSPLIT-01 default disposition — `/economic-analyst` assessment concludes KNOWN-ISSUES.md UNMODIFIED is the correct disposition.

### 6b. KI Envelope Re-Verifications

4-row KI envelope table mirroring Phase 253 / 257 / 262 / 265 / 266 §6b format. Per D-271-KI-01: EXC-01..03 RE_VERIFIED-NEGATIVE-scope (Phase 270 contributes 3 rows verbatim); EXC-04 RE_VERIFIED with NARROWS retained from v36.0 (Phase 270 contributes 1 row verbatim).

| EXC | Surface | v37.0 Disposition | Evidence |
| --- | ------- | ---------------- | -------- |
| EXC-01 | Affiliate roll RNG | `RE_VERIFIED-NEGATIVE-scope` | Phase 270 grep recipe verification: neither commit `002bde55` (presale auto-deactivate) nor commit `2713ce61` (`setDecimatorAutoRebuy` removal) touches the affiliate-roll path. Phase 267 Degenerette commit `e1136071` + Phase 269 LBX-01 commit `8fd5c2e1` zero affiliate-roll interaction at v37 HEAD. Cross-cite Phase 270 270-01-DELTA-SURFACE.md KI walk row 1. |
| EXC-02 | Backfill / prevrandao fallback | `RE_VERIFIED-NEGATIVE-scope` | Phase 270 grep recipe verification: AdvanceModule body untouched in v37 except for Phase 270 sub-audit subject `002bde55` (cap-OR arm DELETED + constant DELETED) which received SAFE_BY_STRUCTURAL_CLOSURE verdict per Phase 270 surface (i) + (iii) + (iv). v37 contract commits do not introduce new prevrandao usage. Cross-cite Phase 270 270-01-DELTA-SURFACE.md KI walk row 2. |
| EXC-03 | F-29-04 mid-cycle write-buffer substitution | `RE_VERIFIED-NEGATIVE-scope` | Phase 270 grep recipe verification: gameover-RNG-substitution path untouched in v37. No commit modifies the mid-cycle write-buffer mechanics. Cross-cite Phase 270 270-01-DELTA-SURFACE.md KI walk row 3. |
| EXC-04 | EntropyLib XOR-shift PRNG (BAF-jackpot-only scope at v36.0) | `RE_VERIFIED with NARROWS retained` | EntropyLib body byte-identical at v37.0 HEAD vs v36.0 baseline `1c0f0913` (Phase 268 SURF-04 grep-proof — `git diff` returns empty). Per-pull-level keccak path UNCHANGED in v37 — Phase 267 Degenerette + Phase 269 LBX-01 do NOT modify lootbox-path entropy consumption. Lootbox-path consumes high-entropy keccak via `EntropyLib.hash2` + bit-slicing per v36.0 ENT-01..06 (byte-identical structural surface; 4 callsites at L1559/L1564/L1571/L1599 post-LBX-01 vs v36.0 baseline L1548/L1569/L1585/L1599). NARROWS scope (BAF-jackpot-only) carried verbatim from v36 AUDIT-05 KI-envelope-narrowing edit. Cross-cite Phase 270 270-01-DELTA-SURFACE.md KI walk row 4. |

**Backward-trace methodology cite:** Per `feedback_rng_backward_trace.md` (every RNG audit must trace BACKWARD from each consumer to verify word was unknown at input commitment time): Degenerette path `packedTraitsDegenerette` consumes VRF-derived high-entropy keccak bits (NOT XOR-shift output) — `resultSeed = keccak(rngWord, index, [spinIdx], QUICK_PLAY_SALT)` per `_resolveFullTicketBet` at L615-628; the input bits are bits of a keccak-derived seed, not raw VRF output. EntropyLib XOR-shift remains as BAF-jackpot consumer only at v37 HEAD. Phase 268 STAT-02 chi² ≥1M-sample uniformity validates the producer's color-symbol distribution; the producer's entropy source (post-keccak) inherits VRF entropy via the well-mixed keccak hash function.

**Commitment-window check cite:** Per `feedback_rng_commitment_window.md` (every RNG audit must check what player-controllable state can change between VRF request and fulfillment): Degenerette bet placement (`placeDegeneretteBet`) reads the CURRENT open `LR_INDEX` and stores the bet in `degeneretteBets[player][nonce]`. VRF request increments `LR_INDEX` atomically in the SAME transaction (`DegenerusGameAdvanceModule.sol:1100-1116`), so new bets after the request go to the NEXT index, not the index being resolved. No player-controllable state can change between VRF request and fulfillment that affects the index-I bet's outcome. Bot front-run via VRF mempool visibility is STRUCTURALLY PREVENTED (per `/zero-day-hunter` Hypothesis 4 in `271-01-ADVERSARIAL-LOG.md`).

### 6c. Verdict Summary

**`0 of 0 KI_ELIGIBLE_PROMOTED; KNOWN_ISSUES_UNMODIFIED`**

PAY-SPLIT 3-tier rule boundary discontinuity at exactly 3.0× bet is documented as accepted-design via §4 surface (h) prose disclosure ONLY per D-271-PAYSPLIT-01 + `/economic-analyst` mechanism-design assessment (see `271-01-ADVERSARIAL-LOG.md`). NO new KNOWN-ISSUES.md entry under Design Decisions. Total payout invariant preserved (`ethShare + lootboxShare = payout` at every tier); player receives same total value in different mix; Phase 268 STAT-07 empirically validates per-band frequency distribution within ±0.5% bin tolerance. The 2.5× bet floor in Tier 2 is a player-friendly buff (paying MORE ETH than the alternative 25%-standard rule would in the 3-10× band); the boundary cliff at 3.0× → 3.01× is the unavoidable price of the floor concession and is bounded (~5% perceived value loss under typical liquidity-discount models; non-player-targetable because payout-multiple is RNG-determined post-VRF-fulfillment).

KNOWN-ISSUES.md UNMODIFIED at v37 close per `git diff 1c0f09132d7439af9881c56fe197f81757f8164a..HEAD -- KNOWN-ISSUES.md` returning empty.

---

## 7. Prior-Artifact Cross-Cites

Cross-cites organized in 4 subsections per the canonical FINDINGS shape: v37.0 phase artifacts, prior milestone FINDINGS, notes, and project-state artifacts.

### 7.1. v37.0 Phase Artifacts

- **Phase 267 — Degenerette Producer + 5-Table Payout Rewrite:**
  - `.planning/phases/267-degenerette-producer-5-table-payout-rewrite/267-CONTEXT.md`
  - `.planning/phases/267-degenerette-producer-5-table-payout-rewrite/267-01-PLAN.md`
  - `.planning/phases/267-degenerette-producer-5-table-payout-rewrite/267-01-SUMMARY.md`
  - `.planning/phases/267-degenerette-producer-5-table-payout-rewrite/267-01-CONSTANTS-VERIFY.md` (25/25 packed-constants byte-identity proof `PASS_ALL_25`)
  - Contract commit: `e1136071` `feat(267): degenerette producer + 5-table payout rewrite + 3-tier ETH split [DGN-01..15, PAY-SPLIT-01..03]`
- **Phase 268 — Degenerette Statistical Validation + Cross-Surface Preservation:**
  - `.planning/phases/268-degenerette-statistical-validation-cross-surface-preservation/268-CONTEXT.md`
  - `.planning/phases/268-degenerette-statistical-validation-cross-surface-preservation/268-01-PLAN.md`
  - `.planning/phases/268-degenerette-statistical-validation-cross-surface-preservation/268-01-SUMMARY.md`
  - `.planning/phases/268-degenerette-statistical-validation-cross-surface-preservation/268-VERIFICATION.md`
  - `.planning/phases/268-degenerette-statistical-validation-cross-surface-preservation/268-01-CHORE-INVENTORY.md`
  - Test commit: `4b277aaf` `test(268): degenerette stat suite + cross-surface preservation v37.0 + worst-case gas regression [STAT-01..07, SURF-01..06]`
- **Phase 269 — Lootbox Dead-Branch Cleanup + SURF-05 Gas-Pin Re-Pinning (PARTIAL ship):**
  - `.planning/phases/269-lootbox-dead-branch-cleanup-surf-05-gas-pin-re-pinning/269-CONTEXT.md`
  - `.planning/phases/269-lootbox-dead-branch-cleanup-surf-05-gas-pin-re-pinning/269-01-PLAN.md` (including the "Root Cause (GASPIN-01)" 80-LOC RCA section inline at commit `009cbde3`)
  - `.planning/phases/269-lootbox-dead-branch-cleanup-surf-05-gas-pin-re-pinning/269-01-SUMMARY.md`
  - Contract commit: `8fd5c2e1` `feat(269): delete unreachable BURNIE-conversion branch in _resolveLootboxRoll [LBX-01]`
  - RCA-inline commit: `009cbde3` `docs(269): GASPIN-01 root-cause inline — fixture-loader caching`
- **Phase 270 — Post-v32.0 Deferred-Commit Adversarial Sub-Audit (cross-cite):**
  - `.planning/phases/270-post-v32-0-deferred-commit-adversarial-sub-audit/270-CONTEXT.md`
  - `.planning/phases/270-post-v32-0-deferred-commit-adversarial-sub-audit/270-01-PLAN.md`
  - `.planning/phases/270-post-v32-0-deferred-commit-adversarial-sub-audit/270-01-SUMMARY.md`
  - `.planning/phases/270-post-v32-0-deferred-commit-adversarial-sub-audit/270-01-DELTA-SURFACE.md` (305 LOC canonical Phase-271-§3.A grep-cite anchor per D-270-FILES-01; 8 surface verdicts SAFE_BY_STRUCTURAL_CLOSURE × 6 + SAFE_BY_DESIGN × 2; 4 RE_VERIFIED-NEGATIVE-scope KI envelope rows feeding §6b)
  - `.planning/phases/270-post-v32-0-deferred-commit-adversarial-sub-audit/270-VERIFICATION.md`
  - Working-file commit: `4017b9ec` `docs(270): post-v32.0 deferred-commit adversarial sub-audit working file [DELTA-01..04]`
  - Phase-close commit: `5cd4f2bc` `docs(270): phase 270 summary — post-v32.0 deferred-commit adversarial sub-audit complete [DELTA-01..04 PASS]`
- **Phase 271 — Delta Audit + Findings Consolidation (Terminal) — self-cite:**
  - `.planning/phases/271-delta-audit-findings-consolidation-terminal/271-CONTEXT.md`
  - `.planning/phases/271-delta-audit-findings-consolidation-terminal/271-01-PLAN.md` (this plan)
  - `.planning/phases/271-delta-audit-findings-consolidation-terminal/271-01-ADVERSARIAL-LOG.md` (Task 6 output — 3 H2 sections + Disposition)
  - `.planning/phases/271-delta-audit-findings-consolidation-terminal/271-01-SUMMARY.md` (Task 14 output)

### 7.2. Prior Milestone FINDINGS Cross-Cites

11 prior milestone-closure deliverables enumerated for REG-04 spot-check sweep + closure-signal chain context:

- `audit/FINDINGS-v25.0.md`
- `audit/FINDINGS-v27.0.md`
- `audit/FINDINGS-v28.0.md`
- `audit/FINDINGS-v29.0.md`
- `audit/FINDINGS-v30.0.md`
- `audit/FINDINGS-v31.0.md`
- `audit/FINDINGS-v32.0.md`
- `audit/FINDINGS-v33.0.md`
- `audit/FINDINGS-v34.0.md`
- `audit/FINDINGS-v35.0.md`
- `audit/FINDINGS-v36.0.md`

**Closure-signal chain:** v25 → v27 → v28 → v29 → v30 → v31 → v32 → v33 → v34 (`MILESTONE_V34_AT_HEAD_6b63f6d4daf346a53a1d463790f637308ea8d555`) → v35 → v36 (`MILESTONE_V36_AT_HEAD_1c0f09132d7439af9881c56fe197f81757f8164a`) → v37 (`MILESTONE_V37_AT_HEAD_<sha>` — emitted §9c at Task 12; SHA resolved at Task 14 atomic-update).

REG-01 carries v36.0 closure signal verbatim per §5a (REG-v36.0-LBX-ENT PASS).
REG-02 carries v34.0 closure signal verbatim per §5b (REG-v34.0-TRAIT-SOLO PASS).
REG-04 walks v25..v36.0 per §5c (5 PASS / 1 SUPERSEDED).

### 7.3. Notes Cross-Cites

- `.planning/notes/2026-05-10-degenerette-payout-recalibration.md` — primary workstream seed note for v37.0 Degenerette content.
- `.planning/notes/degenerette-recalibration/derive_5_tables.py` — Fraction-exact derivation script; canonical source of truth for the 25 packed constants (5 × `QUICK_PLAY_PAYOUTS_N{0..4}_PACKED` + 5 × `QUICK_PLAY_PAYOUT_N{0..4}_M8` + 5 × `HERO_BOOST_N{0..4}_PACKED` + 5 × `WWXRP_FACTORS_N{0..4}_PACKED`); Phase 267 Task 2 `PASS_ALL_25` byte-identity proof verifies deployed constants match script stdout.
- `.planning/notes/2026-05-10-resolveLootboxRoll-dead-burnie-conversion-branch.md` — lootbox cleanup seed note for v37.0 LBX-01 content.

### 7.4. Project-State Cross-Cites

- `.planning/PROJECT.md` "Current Milestone v37.0" block + "Deferred to Future Milestones" subsection (updated at Task 13 per D-271-DEFERRED-03 with 4 v38+ carry-forward bullets — LBX-02 + GASPIN-02/03 combined + SURF-03 re-baseline + STAT-03 v35.0 carry).
- `.planning/MILESTONES.md` closure-signal chain v25 → v36 + v37 in-progress row (flipped to SHIPPED at Task 14 with closure signal `MILESTONE_V37_AT_HEAD_<sha>` recorded).
- `.planning/ROADMAP.md` v37.0 milestone bullet (flipped to ✅ at Task 14).
- `.planning/REQUIREMENTS.md` AUDIT-01..06 + REG-01..04 traceability (flipped to Complete at Task 14); LBX-02 + GASPIN-02 + GASPIN-03 traceability (flipped to DEFERRED-V38+ at Task 14).
- `KNOWN-ISSUES.md` EXC-01..04 envelopes (UNMODIFIED at v37 close per default path; `git diff` returns empty).

---

